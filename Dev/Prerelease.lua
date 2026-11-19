-- /cine prerelease: one run before a release, checking nothing broke since
-- the last one. Dev copy only (CinematicDev.toc). Hands-free unless guided:
--   /cine prerelease          selftest, the smoke checks, then the full
--                             settings sweep (every page and setting, ~5 min)
--   /cine prerelease quick    the same with the sweep's page pass only
--                             (every page and tab opened, nothing changed)
--   /cine prerelease guided   a few steps you do (a fight, a mount, the map,
--                             an NPC): a big box says what, each one waits
--                             for it (or 90 sec), takes a screenshot, and
--                             passes when no Lua error or blocked action came
--   /cine prerelease skip     a guided step skipped
--   /cine prerelease          again while it runs: stops
-- Every check is a verdict (pass, fail, skip) by its name. Each run is kept
-- per client and kind (CinematicDB.prerelease), and compared with the last
-- one of its kind: NEW FAIL (passed last time), still failing, fixed. A Lua
-- error or blocked action during a check fails it. Into
-- CinematicDB.prereleaseLog; Tools/prerelease.py prints it from the saved
-- settings after a /reload.
--
-- A smoke check: Smoke(name, fn). fn() returns status, detail ("pass",
-- "fail", "skip") or, when it needs time, takes done and calls done(status,
-- detail) later (Later() keeps a stopped run from going on). Each puts back
-- what it changed. Add one whenever a bug is fixed that a check could catch.
local _, ns = ...

local GAP = 1 -- seconds between checks
local GUIDED_WAIT = 90 -- seconds a guided step waits for you
local KEEP_RUNS = 6 -- runs kept per client and kind
-- Saved settings that aren't settings: left out of before/after compares.
local QUIET = { log = true, sweepLog = true, sweepPending = true, prerelease = true, prereleaseLog = true,
	selfTest = true, pageTimes = true, profiler = true, slashUsage = true, savedCVars = true, profiles = true,
	hubLastTab = true, hubKept = true, sectionsOpen = true, chatCamDebug = true, smartFindLooks = true }

local run

local function Client()
	local interface = tonumber((select(4, GetBuildInfo()))) or 0
	return interface >= 100000 and "retail" or (interface >= 16000 and interface < 20000) and "forever"
		or (interface >= 10000 and interface < 16000) and "era" or ("game" .. interface)
end

local function Say(text)
	local log = CinematicDB and CinematicDB.prereleaseLog
	if log then log[#log + 1] = ("%5.1f %s"):format(run and GetTime() - run.at or 0, text) end
end

local function Box(text, sub, r, g, b)
	ns.PadTestBox(text, sub or "", r or 1, g or 0.82, b or 0)
end

local function Copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for k, v in pairs(value) do result[k] = Copy(v) end
	return result
end
local function Same(a, b)
	if a == b then return true end
	if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-6 end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do
		if not Same(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end
local function Snapshot()
	local copy = {}
	for k, v in pairs(CinematicDB or {}) do
		if not QUIET[k] then copy[k] = Copy(v) end
	end
	return copy
end
-- Keys whose value isn't what it was, sorted.
local function Changed(before, after)
	local keys = {}
	for k, v in pairs(before) do
		if not Same(v, after[k]) then keys[#keys + 1] = tostring(k) end
	end
	for k in pairs(after) do
		if before[k] == nil and not QUIET[k] then keys[#keys + 1] = tostring(k) end
	end
	table.sort(keys)
	return keys
end
local function List(items, most)
	most = most or 5
	local shown = {}
	for i = 1, math.min(#items, most) do shown[i] = items[i] end
	return table.concat(shown, ", ") .. (#items > most and (" and %d more"):format(#items - most) or "")
end
local function FirstLine(text)
	return (tostring(text):match("^[^\n]*"))
end

-- Game settings changed since before (the sweep's list: the ones the game
-- doesn't change as you play), each put back.
local function CVarsBack(before)
	if not (before and ns.SweepCVars) then return {} end
	local after, changed = ns.SweepCVars() or {}, {}
	for name, value in pairs(before) do
		if after[name] ~= nil and after[name] ~= value then
			changed[#changed + 1] = ("%s %s -> %s"):format(name, value, after[name])
			pcall(SetCVar, name, value)
		end
	end
	table.sort(changed)
	return changed
end

local function Shot(what)
	if not run then return end
	run.shots = (run.shots or 0) + 1
	ns.PadTestBoxHide()
	C_Timer.After(0.2, function()
		pcall(Screenshot)
		Say(("  screenshot %d: %s (%s)"):format(run and run.shots or 0, what, date("%H:%M:%S")))
		C_Timer.After(0.6, function() if run and run.boxText then Box(run.boxText, run.boxSub) end end)
	end)
end

-- Lua errors and blocked actions as they're logged: the check running gets them.
hooksecurefunc(ns, "Log", function(category, text)
	if run and (category == "ERROR" or category == "BLOCKED") then
		run.errors[#run.errors + 1] = category .. " " .. FirstLine(text)
	end
end)

-- fn a few seconds on, if this run is still the one going.
local function Later(seconds, fn)
	local this = run
	C_Timer.After(seconds, function()
		if run == this and not run.stopping then ns.Guard(fn) end
	end)
end

local function Result(name, status, detail)
	run.results[name] = { status = status, detail = detail }
	local mark = status == "pass" and "PASS" or status == "fail" and "FAIL" or "SKIP"
	Say(("%s %s%s"):format(mark, name, detail and detail ~= "" and (": " .. detail) or ""))
	run.counts[status] = (run.counts[status] or 0) + 1
end

---------------------------------------------------------------------------
-- The smoke checks.
local SMOKE = {}
local function Smoke(name, fn) SMOKE[#SMOKE + 1] = { name = name, fn = fn } end

local function NeedsOn()
	if not (ns.db and ns.db.enabled) then return "Cinematic is off" end
	if ns.ProfileChosen and not ns.ProfileChosen() then return "no profile picked" end
end

-- The once-only updates, run again on your settings: each has its done-flag
-- set, so nothing may change (one that does would change settings at every
-- login). Put back if it did.
Smoke("migrations: run again, nothing changes", function()
	if not ns.RunMigrations then return "skip", "no ns.RunMigrations" end
	local before = Snapshot()
	ns.migrationErrors = nil
	ns.RunMigrations()
	local keys = Changed(before, Snapshot())
	for _, key in ipairs(keys) do CinematicDB[key] = Copy(before[key]) end
	if #keys > 0 and ns.SettingsChanged then ns.Guard(ns.SettingsChanged) end
	local errors = ns.migrationErrors
	if errors and #errors > 0 then return "fail", "errors: " .. List(errors, 3) end
	if #keys > 0 then return "fail", "changed (put back): " .. List(keys, 8) end
	return "pass"
end)

-- Your profile through Share and back: every setting comes in as it went out.
Smoke("profile share: export, read back the same", function()
	local name = ns.ActiveProfile and ns.ActiveProfile()
	if not name then return "skip", "no profile" end
	local text = ns.ExportProfile(name)
	local info, why = ns.ReadSharedProfile(text)
	if not info then return "fail", "read back: " .. tostring(why) end
	local want, wrong = ns.ProfileForSharing(name), {}
	for key, value in pairs(want) do
		if ns.KnownProfileSetting(key, value) and not Same(value, info.settings[key]) then
			wrong[#wrong + 1] = key
		end
	end
	table.sort(wrong)
	if #wrong > 0 then return "fail", ("%d settings came back different: %s"):format(#wrong, List(wrong, 8)) end
	return "pass", ("%d settings, %d skipped, %d characters"):format(info.count, info.skipped, #text)
end)

-- Every built-in profile: its settings build, and it shares and reads back.
Smoke("built-in profiles: each builds and shares", function()
	local bad, count = {}, 0
	for _, profile in ipairs(ns.BUILTIN_PROFILES or {}) do
		count = count + 1
		local ok, base = pcall(ns.ProfileBase, profile.name)
		if not ok or type(base) ~= "table" then
			bad[#bad + 1] = ("%s (%s)"):format(profile.name, ok and "no settings" or FirstLine(base))
		else
			local okShare, text = pcall(ns.ExportProfile, profile.name)
			local info = okShare and ns.ReadSharedProfile(text)
			if not info then bad[#bad + 1] = profile.name .. " (share: " .. (okShare and "unreadable" or FirstLine(text)) .. ")" end
		end
	end
	if count == 0 then return "fail", "no built-in profiles" end
	if #bad > 0 then return "fail", List(bad, 4) end
	return "pass", count .. " profiles"
end)

-- Themes through Share and back (yours as you have it, and two of ours).
Smoke("theme share: export, read back", function()
	if not (ns.ExportStyleTheme and ns.ReadSharedStyleTheme) then return "skip", "no theme share" end
	local keys, seen, bad = {}, {}, {}
	for _, key in ipairs({ ns.GetDB().styleTheme or "game", "reel", "vanguard" }) do
		if not seen[key] then
			seen[key] = true
			keys[#keys + 1] = key
		end
	end
	for _, key in ipairs(keys) do
		local text = ns.ExportStyleTheme(key)
		if text then
			local info, why = ns.ReadSharedStyleTheme(text)
			if not info then
				bad[#bad + 1] = key .. " (" .. tostring(why) .. ")"
			elseif (info.skipped or 0) > 0 then
				bad[#bad + 1] = ("%s (%d settings skipped)"):format(key, info.skipped)
			end
		end
	end
	if #bad > 0 then return "fail", List(bad) end
	return "pass", table.concat(keys, ", ")
end)

-- Why Is It Showing: every tab answers, every feature has its line.
Smoke("why: every tab and feature explained", function()
	if not ns.WhyCoverage then return "skip", "no ns.WhyCoverage" end
	local gaps = ns.WhyCoverage() or {}
	if #gaps > 0 then return "fail", ("%d gaps: %s"):format(#gaps, List(gaps, 3)) end
	return "pass"
end)

-- The Toggle CineMode key: on, off, and back as it was, game settings too.
Smoke("cinemode: key turns it on and off, back as it was", function(done)
	local why = NeedsOn()
	if why then return done("skip", why) end
	if InCombatLockdown() then return done("skip", "in a fight") end
	local was, cvars = ns.IsCineModeOn(), ns.SweepCVars and ns.SweepCVars()
	Cinematic_ToggleCineMode()
	Later(3, function()
		local flipped, faded = ns.IsCineModeOn() ~= was, ns.lastCinematic and true or false
		Shot(("CineMode %s"):format(was and "off" or "on"))
		Later(1.5, function()
			Cinematic_ToggleCineMode()
			Later(4, function()
				local back = ns.IsCineModeOn() == was
				local changed = CVarsBack(cvars)
				local detail = ("was %s, flipped %s, faded UI %s, back %s"):format(tostring(was), tostring(flipped),
					tostring(faded), tostring(back))
				if #changed > 0 then detail = detail .. "; game settings not back (put back): " .. List(changed, 4) end
				done((flipped and back and #changed == 0) and "pass" or "fail", detail)
			end)
		end)
	end)
end)

-- A standing-still camera from its key: starts, stops, camera back.
Smoke("camera: vista starts and stops, camera back", function(done)
	local why = NeedsOn()
	if why then return done("skip", why) end
	if InCombatLockdown() then return done("skip", "in a fight") end
	if ns.playerMoving or (ns.OnTaxi and ns.OnTaxi()) or IsMounted() then return done("skip", "stand still, unmounted") end
	if ns.activeCam then return done("skip", "a camera is running: " .. tostring(ns.activeCam)) end
	local zoom, cvars = GetCameraZoom(), ns.SweepCVars and ns.SweepCVars()
	Cinematic_StartCam("vista", true, "prerelease")
	Later(4, function()
		local script = ns.PlayingCameraScript and ns.PlayingCameraScript()
		local started = ns.activeCam or (script and script.id)
		Shot("vista camera")
		Later(1.5, function()
			-- (Its key again: stops it as a player would; ns.StopCamera would
			-- keep the cameras off till you move.)
			Cinematic_StartCam("vista", true, "prerelease")
			Later(6, function()
				local still = ns.activeCam or (ns.PlayingCameraScript and ns.PlayingCameraScript())
				local changed = CVarsBack(cvars)
				local zoomNow = GetCameraZoom()
				local detail = ("started %s, stopped %s, zoom %.1f -> %.1f"):format(tostring(started or false),
					tostring(not still), zoom, zoomNow)
				if #changed > 0 then detail = detail .. "; game settings not back (put back): " .. List(changed, 4) end
				if not started then return done("fail", "never started: " .. detail) end
				done((not still and #changed == 0 and math.abs(zoomNow - zoom) < 1.5) and "pass" or "fail", detail)
			end)
		end)
	end)
end)

-- Our skinned scroll bars show only while there's something to scroll to: a
-- test list made short (no bar), tall (bar), short again (no bar), each read a
-- moment on, once the game has worked out its range.
Smoke("scroll bar: hidden when the page fits", function(done)
	if not ns.SkinScroll then return done("skip", "no ns.SkinScroll") end
	local scroll = CreateFrame("ScrollFrame", nil, UIParent, "UIPanelScrollFrameTemplate")
	scroll:SetSize(300, 200)
	scroll:SetPoint("CENTER")
	scroll:SetAlpha(0)
	-- (unseen and out of the mouse's way, even if a stopped run leaves it up)
	scroll:EnableMouse(false)
	scroll:EnableMouseWheel(false)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(300, 50)
	scroll:SetScrollChild(content)
	ns.SkinScroll(scroll)
	local bar = scroll.ScrollBar
	if not bar then
		scroll:Hide()
		return done("skip", "template has no ScrollBar")
	end
	local seen = {}
	local function Read(label)
		local range = scroll:GetVerticalScrollRange()
		seen[#seen + 1] = ("%s: range %s, bar %s"):format(label,
			(issecretvalue and issecretvalue(range)) and "secret" or ("%.0f"):format(range or 0),
			bar:IsShown() and "shown" or "hidden")
		return bar:IsShown()
	end
	Later(0.5, function()
		local shortHidden = not Read("short")
		content:SetHeight(800)
		Later(0.5, function()
			local tallShown = Read("tall")
			content:SetHeight(50)
			Later(0.5, function()
				local againHidden = not Read("short again")
				scroll:Hide()
				scroll:SetParent(nil)
				done((shortHidden and tallShown and againHidden) and "pass" or "fail", table.concat(seen, "; "))
			end)
		end)
	end)
end)

---------------------------------------------------------------------------
-- Guided steps:{ name, say, wait = fn -> true once it's happening,
-- hold = fn -> true while it lasts (or seconds), after = seconds once over }.
local GUIDED = {
	{ name = "guided: a fight", say = "Get in a fight: hit a target dummy or a mob, about 10 seconds, then stop.",
		wait = function() return InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) end,
		hold = function() return InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) end, after = 8,
		note = function() return ("CineMode out for the fight: %s"):format(tostring(ns.CineOutForFight and ns.CineOutForFight())) end },
	{ name = "guided: a mount", say = "Mount up and ride (or fly) for about 10 seconds, then get off.",
		wait = IsMounted, hold = IsMounted, after = 4 },
	{ name = "guided: the map", say = "Open the world map (M), look 3 seconds, close it.",
		wait = function() return _G.WorldMapFrame and _G.WorldMapFrame:IsShown() end,
		hold = function() return _G.WorldMapFrame and _G.WorldMapFrame:IsShown() end, after = 3 },
	{ name = "guided: an NPC", say = "Talk to an NPC (quest giver, vendor, anyone with a window), then close it.",
		wait = function()
			for _, name in ipairs({ "GossipFrame", "QuestFrame", "MerchantFrame" }) do
				local frame = _G[name]
				if frame and frame:IsShown() then return true end
			end
			return ns.activeCam == "quest"
		end,
		hold = function()
			for _, name in ipairs({ "GossipFrame", "QuestFrame", "MerchantFrame" }) do
				local frame = _G[name]
				if frame and frame:IsShown() then return true end
			end
		end, after = 4 },
}

---------------------------------------------------------------------------
-- The run: stages one after another, then the report.
local Finish, NextStage

local function RunCheck(check, index, total, onDone)
	if InCombatLockdown() then
		Result(check.name, "skip", "in a fight")
		return onDone()
	end
	run.boxText = ("Prerelease check %d of %d: %s"):format(index, total, check.name)
	run.boxSub = "Don't touch anything. (/cine prerelease stops)"
	Box(run.boxText, run.boxSub)
	local errorsBefore, answered = #run.errors, false
	local function Done(status, detail)
		if answered or not run then return end
		answered = true
		local errors = {}
		for i = errorsBefore + 1, #run.errors do errors[#errors + 1] = run.errors[i] end
		if #errors > 0 then
			status = "fail"
			detail = (detail and (detail .. "; ") or "") .. ("%d Lua errors/blocked: %s"):format(#errors, List(errors, 2))
		end
		Result(check.name, status or "fail", detail)
		Later(GAP, onDone)
	end
	local ok, status, detail = pcall(check.fn, Done)
	if not ok then
		Done("fail", "its own error: " .. FirstLine(status))
	elseif status then
		Done(status, detail)
	end
end

local function RunList(list, onDone)
	local index = 0
	local function Next()
		index = index + 1
		if not run or run.stopping then return end
		if index > #list then return onDone() end
		RunCheck(list[index], index, #list, Next)
	end
	Next()
end

local function SelfTestStage(onDone)
	Box("Prerelease: selftest", "")
	if not ns.SelfTest then
		Result("selftest", "skip", "no ns.SelfTest")
		return onDone()
	end
	local ok, counts, problems = pcall(ns.SelfTest)
	if not ok then
		Result("selftest", "fail", "its own error: " .. FirstLine(counts))
		return onDone()
	end
	local keys = {}
	for key in pairs(problems or {}) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		-- (failed or error, and changed too: a game change worth a look. The
		-- selftest keeps the new value, so a changed one is "fixed" next run.)
		Result("selftest: " .. key, "fail", problems[key])
	end
	Result("selftest", (counts.failed + counts.error) == 0 and "pass" or "fail",
		("%d ok, %d failed, %d changed, %d skipped"):format(counts.ok, counts.failed + counts.error, counts.changed,
			counts.skipped))
	Later(GAP, onDone)
end

-- The sweep's FAIL lines, numbers out, so the same one reads the same next run.
local function SweepFails()
	local keys, seen = {}, {}
	for _, line in ipairs(CinematicDB.sweepLog or {}) do
		local text = line:gsub("^[%d%.]+ ", "")
		if text:find("^FAIL ") then
			local key = text:gsub("^FAIL ", ""):gsub('setting ".-":', "setting:"):gsub("%-?%d+%.?%d*", "#")
			key = key:sub(1, 200)
			if not seen[key] then
				seen[key] = true
				keys[#keys + 1] = key
			end
		end
	end
	return keys
end

local function SweepStage(onDone)
	if not ns.SettingsSweep then
		Result("sweep", "skip", "no ns.SettingsSweep")
		return onDone()
	end
	local pagesOnly = run.kind == "quick"
	local this = run
	local started = ns.SettingsSweep(pagesOnly and "pages" or "", function(finished, fails, warns)
		if run ~= this then return end
		run.sweepRunning = false
		for _, key in ipairs(SweepFails()) do Result("sweep: " .. key, "fail") end
		Result(pagesOnly and "sweep (pages)" or "sweep", (finished and fails == 0) and "pass" or "fail",
			("%s, %d fail, %d warn (CinematicDB.sweepLog)"):format(finished and "done" or "stopped", fails, warns))
		if not run.stopping then Later(2, onDone) else Finish(false) end
	end)
	if not started then
		Result("sweep", "fail", "didn't start (see chat)")
		return onDone()
	end
	run.sweepRunning = true
end

local function GuidedStage(onDone)
	local index = 0
	local function Next()
		index = index + 1
		if not run or run.stopping then return end
		local step = GUIDED[index]
		if not step then return onDone() end
		local errorsBefore, began, seenAt, overAt = #run.errors, GetTime(), nil, nil
		run.skipStep = false
		run.boxText = ("Step %d of %d: %s"):format(index, #GUIDED, step.say)
		local notes = {}
		local function Verdict(status, detail)
			local errors = {}
			for i = errorsBefore + 1, #run.errors do errors[#errors + 1] = run.errors[i] end
			if #errors > 0 then
				status = "fail"
				detail = (detail and (detail .. "; ") or "") .. ("%d Lua errors/blocked: %s"):format(#errors, List(errors, 2))
			end
			Result(step.name, status, detail)
			Later(2, Next)
		end
		local this = run
		run.ticker = C_Timer.NewTicker(0.5, function(ticker)
			if run ~= this or run.stopping then return ticker:Cancel() end
			local now = GetTime()
			if run.skipStep then
				ticker:Cancel()
				return Verdict("skip", "skipped by hand")
			end
			local okWait, happening = pcall(seenAt and step.hold or step.wait)
			happening = okWait and happening and true or false
			if not seenAt then
				local left = math.ceil(GUIDED_WAIT - (now - began))
				run.boxSub = ("%d sec left (/cine prerelease skip)"):format(left)
				Box(run.boxText, run.boxSub)
				if happening then
					seenAt = now
					Say(("  %s: started after %.0f sec"):format(step.name, now - began))
					Later(1.5, function() Shot(step.name) end)
				elseif left <= 0 then
					ticker:Cancel()
					return Verdict("skip", "didn't happen in time")
				end
			elseif not overAt then
				run.boxSub = "Seen. Carry on, then stop."
				Box(run.boxText, run.boxSub)
				if step.note and not notes.during then
					local okNote, note = pcall(step.note)
					if okNote and note then notes.during = note end
				end
				if not happening then overAt = now end
			elseif now - overAt >= (step.after or 3) then
				ticker:Cancel()
				Shot(step.name .. ", after")
				return Verdict("pass", ("%.0f sec%s"):format(overAt - seenAt, notes.during and ("; " .. notes.during) or ""))
			else
				run.boxSub = "Done. Wait a moment..."
				Box(run.boxText, run.boxSub)
			end
		end)
	end
	Next()
end

local STAGES = {
	full = { SelfTestStage, function(done) RunList(SMOKE, done) end, SweepStage },
	quick = { SelfTestStage, function(done) RunList(SMOKE, done) end, SweepStage },
	guided = { GuidedStage },
}

-- This run against the last of its kind on this client.
local function Compare(last)
	local new, still, fixed = {}, {}, {}
	local names = {}
	for name in pairs(run.results) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local now, was = run.results[name], last and last.results[name]
		if now.status == "fail" then
			if not last then
				still[#still + 1] = name
			elseif not was then
				new[#new + 1] = name -- (a check that's new since: a fail all the same)
			elseif was.status == "fail" then
				still[#still + 1] = name
			else
				new[#new + 1] = name
			end
		end
	end
	if last then
		for name, was in pairs(last.results) do
			local now = run.results[name]
			if was.status == "fail" and (not now or now.status == "pass") then
				fixed[#fixed + 1] = name
			end
		end
		table.sort(fixed)
	end
	return new, still, fixed
end

function Finish(finished)
	if not run then return end
	local this = run
	this.stopping = true
	if this.ticker then this.ticker:Cancel() end
	if this.sweepRunning and ns.SettingsSweepRunning and ns.SettingsSweepRunning() then
		-- (Stopping the sweep calls back here once its settings are back.)
		this.sweepRunning = false
		ns.SettingsSweep()
		return
	end
	local client = Client()
	CinematicDB.prerelease = CinematicDB.prerelease or {}
	local store = CinematicDB.prerelease
	store[client] = store[client] or {}
	local runs = store[client]
	local last
	for i = #runs, 1, -1 do
		if runs[i].kind == this.kind and runs[i].finished then
			last = runs[i]
			break
		end
	end
	local new, still, fixed = Compare(last)
	Say("--- report ---")
	Say(last and ("against the last %s run: %s, %s"):format(this.kind, last.when, last.version or "?")
		or ("first %s run on %s: nothing to compare with"):format(this.kind, client))
	for _, name in ipairs(new) do
		local r = this.results[name]
		Say(("NEW FAIL %s%s"):format(name, r.detail and (": " .. r.detail) or ""))
	end
	for _, name in ipairs(still) do Say("still failing: " .. name) end
	for _, name in ipairs(fixed) do Say("fixed: " .. name) end
	local c = this.counts
	local summary = ("%s %s on %s: %d pass, %d fail (%d new), %d skip, %d screenshots, %.0f sec"):format(
		finished and "done" or "stopped", this.kind, client, c.pass or 0, c.fail or 0, #new, c.skip or 0,
		this.shots or 0, GetTime() - this.at)
	Say(summary)
	runs[#runs + 1] = { kind = this.kind, when = date("%Y-%m-%d %H:%M"), finished = finished,
		version = ns.Version and ns.Version() or nil, game = tostring((select(4, GetBuildInfo()))),
		results = this.results, new = new, summary = summary }
	while #runs > KEEP_RUNS do table.remove(runs, 1) end
	run = nil
	local good = #new == 0
	Box(("Prerelease %s: %d new fail%s."):format(finished and "done" or "stopped", #new, #new == 1 and "" or "s"),
		"/reload, then say \"check log\"", good and 0.3 or 1, good and 1 or 0.3, 0.3)
	ns.Print(summary)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
end

function NextStage()
	if not run or run.stopping then return end
	run.stage = run.stage + 1
	local stage = STAGES[run.kind][run.stage]
	if not stage then return Finish(true) end
	local ok, err = pcall(stage, NextStage)
	if not ok then
		Result("stage " .. run.stage, "fail", "its own error: " .. FirstLine(err))
		NextStage()
	end
end

function ns.Prerelease(arg)
	arg = (arg or ""):lower():match("^%s*(.-)%s*$")
	if arg == "skip" then
		if run and run.kind == "guided" then run.skipStep = true else ns.Print("prerelease: no guided step to skip") end
		return
	end
	if run then
		ns.Print("prerelease: stopping")
		return Finish(false)
	end
	local kind = arg == "" and "full" or arg
	if not STAGES[kind] then return ns.Print("/cine prerelease [quick|guided|skip]") end
	if InCombatLockdown() then return ns.Print("prerelease: not in a fight") end
	CinematicDB.prereleaseLog = {}
	run = { at = GetTime(), kind = kind, stage = 0, results = {}, counts = {}, errors = {} }
	Say(("start %s: %s run on %s (game %s), Cinematic %s, profile %s, CineMode %s"):format(date("%Y-%m-%d %H:%M:%S"),
		kind, Client(), tostring((select(4, GetBuildInfo()))), tostring(ns.Version and ns.Version()),
		tostring(ns.ActiveProfile and ns.ActiveProfile()), tostring(ns.IsCineModeOn and ns.IsCineModeOn())))
	ns.Print(kind == "guided" and "prerelease (guided): follow the box; /cine prerelease skip skips a step"
		or ("prerelease (%s): about %s min, don't touch anything; again to stop"):format(kind, kind == "quick" and "2" or "6"))
	NextStage()
end
