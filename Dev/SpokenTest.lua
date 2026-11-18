-- /cine debug spokentest: one run recording Spoken's narrator windows and
-- their portraits, after a player saw the speaker's head stay on screen with
-- the window faded (the portrait is a 3D model, which doesn't fade with its
-- window: Support/Spoken.lua makes it follow), and then "something is
-- hiding it". Two timed steps in the big test box (ns.PadTestBox): CineMode
-- off, then on (the test turns it, and puts it back), each with a quest
-- giver talked to so Spoken reads. Spoken is set to its Large Window (the
-- style with a 3D model) for the run, and put back. The log (its own list,
-- CinematicDB.spokenTestLog) gets each window and its portrait whenever they
-- change (shown, alpha, effective alpha, Cinematic's fade of it, which
-- portrait kind shows), every SetAlpha / Show / Hide on them with its caller,
-- Cinematic's reasons (/cine why) as each step starts and as a window
-- shows, and verdicts: HEAD LEFT (the portrait clearly above its window) and
-- PORTRAIT HIDDEN (the window up, its portrait not). Screenshots 5, 12 and 20
-- sec into each step and as a window shows. Dev copy only (CinematicDev.toc).
local ADDON_NAME, ns = ...

local LOG_MAX = 4000
local READY = 4 -- seconds to read each step before it records
local STEP_TIME = 30
local WINDOWS = { "SpokenPlayerFrame", "SpokenMinimalPlayerFrame", "SpokenSubtitleFrame" }
local SHORT = { SpokenPlayerFrame = "narrator", SpokenMinimalPlayerFrame = "minimal", SpokenSubtitleFrame = "subtitles" }

local run -- { at, step, stepAt, last, hooked, kept, bad, phaseShot }

local function Num(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end

local function Log(text)
	local db = ns.db
	if not db then return end
	local log = db.spokenTestLog
	if type(log) ~= "table" then
		log = {}
		db.spokenTestLog = log
	end
	if #log < LOG_MAX then
		log[#log + 1] = ("%.1fs %s"):format(run and GetTime() - run.at or 0, text)
	end
end

-- (Wrapped: C_Timer refused the game's Screenshot itself on WoW Forever.)
local function Shot(why)
	Log("screenshot: " .. why)
	Screenshot()
end

local function Call(object, method)
	if not (object and object[method]) then return nil end
	local ok, value = pcall(object[method], object)
	return ok and value or nil
end

-- Who called: the stack's first lines past this file, paths cut short.
local function Caller()
	local stack = debugstack(3, 6, 0) or ""
	local out = {}
	for line in stack:gmatch("[^\n]+") do
		if not line:find("SpokenTest") then
			line = line:gsub("Interface[/\\]AddOns[/\\]", ""):gsub("%[string \"@?", ""):gsub("\"%]", "")
			out[#out + 1] = line:sub(1, 90)
			if #out >= 3 then break end
		end
	end
	return table.concat(out, " < ")
end

local function ModelOf(name, window)
	if name == "SpokenSubtitleFrame" then
		local env = rawget(_G, "SpokenEnv")
		local subtitle = type(env) == "table" and rawget(env, "Subtitle")
		local viewport = type(subtitle) == "table" and subtitle.viewport
		return viewport and viewport.model, viewport
	end
	local portrait = window.portrait
	if not portrait then return nil end
	if name == "SpokenMinimalPlayerFrame" then
		return portrait.viewport and portrait.viewport.model, portrait.viewport
	end
	return portrait.model, portrait
end

local function EntryOf(window)
	for _, entry in ipairs(ns.managed or {}) do
		if entry.frame == window then return entry end
	end
end

-- A region's state, short.
local function State(region)
	if not region then return "none" end
	return ("shown %s visible %s alpha %s effective %s"):format(tostring(Call(region, "IsShown")),
		tostring(Call(region, "IsVisible")), Num(Call(region, "GetAlpha")), Num(Call(region, "GetEffectiveAlpha")))
end

local function Spoken()
	local spoken = rawget(_G, "Spoken")
	local playing
	if spoken and spoken.GetNowPlaying then
		local ok, now = pcall(spoken.GetNowPlaying, spoken)
		playing = ok and now ~= nil
	end
	local style, hidePortrait = "?", "?"
	local env = rawget(_G, "SpokenEnv")
	local addon = type(env) == "table" and rawget(env, "Addon")
	if addon and addon.Profile then
		local ok, frame = pcall(addon.Profile, addon, "Frame")
		if ok and type(frame) == "table" then
			hidePortrait = tostring(frame.HidePortrait)
			style = tostring(frame.Style or frame.PlayerStyle or frame.Mode)
		end
	end
	return playing, style, hidePortrait
end

-- Spoken's window style (Large Window "classic" is the one with a 3D model).
local function SpokenFrameConfig()
	local env = rawget(_G, "SpokenEnv")
	local addon = type(env) == "table" and rawget(env, "Addon")
	if not (addon and addon.Profile) then return nil end
	local ok, frame = pcall(addon.Profile, addon, "Frame")
	return ok and type(frame) == "table" and frame or nil
end

local function WhyLog(window, label)
	local entry = EntryOf(window)
	if not (entry and ns.WhyLater) then
		Log(("why %s: not faded by Cinematic (no entry)"):format(label))
		return
	end
	ns.WhyLater(entry, function(ok, status, out)
		if not ok then
			Log(("why %s: error %s"):format(label, tostring(status)))
			return
		end
		local parts = {}
		for _, reason in ipairs(out or {}) do
			parts[#parts + 1] = ("[%s] %s%s"):format(tostring(reason.state), tostring(reason.text),
				reason.page and (" (" .. reason.page .. ")") or "")
		end
		Log(("why %s: %s | %s"):format(label, tostring(status), #parts > 0 and table.concat(parts, "; ") or "no reasons"))
	end)
end

-- Every SetAlpha / Show / Hide on the windows and their portraits, logged with
-- the caller (a hook can't be taken off: one with no run does nothing).
local function Watch(region, label)
	if not region or run.hooked[region] then return end
	run.hooked[region] = true
	local lastAlphaCaller
	hooksecurefunc(region, "SetAlpha", function(_, alpha)
		if not run then return end
		local caller = Caller()
		-- (A fade sets it every frame: logged when the caller changes, or at the ends.)
		if caller ~= lastAlphaCaller or alpha == 0 or alpha == 1 then
			lastAlphaCaller = caller
			Log(("%s SetAlpha(%s) by %s"):format(label, Num(alpha), caller))
		end
	end)
	for _, method in ipairs({ "Show", "Hide" }) do
		hooksecurefunc(region, method, function()
			if run then Log(("%s %s() by %s"):format(label, method, Caller())) end
		end)
	end
end

local Finish

local function Tick()
	local now = GetTime()
	local into = now - run.stepAt - READY
	local cine = ns.lastCinematic and true or false
	local playing, style, hidePortrait = Spoken()
	local head = ("CineMode %s | enabled %s, Advanced Frames page %s, rows narrator %s minimal %s subtitles %s | Spoken playing %s, " ..
		"style %s, hide portrait %s"):format(tostring(cine), tostring(ns.db.enabled), tostring(ns.db.handleAddonFrames),
		tostring(ns.db.addonFrames and ns.db.addonFrames.spokenNarrator), tostring(ns.db.addonFrames and ns.db.addonFrames.spokenMinimal),
		tostring(ns.db.addonFrames and ns.db.addonFrames.spokenSubtitles),
		tostring(playing), style, hidePortrait)
	if head ~= run.last.head then
		run.last.head = head
		Log(head)
	end
	for _, name in ipairs(WINDOWS) do
		local window = _G[name]
		if window then
			local short = SHORT[name]
			Watch(window, short)
			local model, host = ModelOf(name, window)
			Watch(model, short .. " model")
			local entry = EntryOf(window)
			local line = ("%s: %s | Cinematic %s | host %s, kind %s | model %s"):format(short, State(window),
				entry and ("fade %s base %s applied %s"):format(Num(entry.alpha), Num(entry.baseAlpha), Num(entry.applied)) or "not faded",
				State(host), tostring(host and host.active), State(model))
			if line ~= run.last[name] then
				run.last[name] = line
				Log(line)
			end
			-- (A window coming up: its reasons, and two shots.)
			local visible = Call(window, "IsVisible") == true
			if visible and not run.wasVisible[name] then
				WhyLog(window, short)
				Shot(("%s came up, step %d"):format(short, run.step))
				C_Timer.After(2, function() if run then Shot(short .. " came up, 2 sec on") end end)
			end
			run.wasVisible[name] = visible
			-- Verdicts, once they've lasted half a second.
			local windowAlpha = Call(window, "GetEffectiveAlpha")
			local modelAlpha = model and Call(model, "GetAlpha")
			local modelUp = model and Call(model, "IsVisible") == true
			local readable = type(windowAlpha) == "number" and type(modelAlpha) == "number"
				and not (issecretvalue and (issecretvalue(windowAlpha) or issecretvalue(modelAlpha)))
			local bad
			if readable and modelUp and modelAlpha > windowAlpha + 0.2 then
				bad = ("HEAD LEFT: %s model alpha %s, window %s"):format(short, Num(modelAlpha), Num(windowAlpha))
			elseif readable and visible and windowAlpha > 0.5 and modelUp and modelAlpha < 0.3 then
				bad = ("PORTRAIT HIDDEN: %s model alpha %s, window %s"):format(short, Num(modelAlpha), Num(windowAlpha))
			end
			local key = name .. (bad and bad:match("^%u+ %u+") or "")
			if bad then
				run.badSince[key] = run.badSince[key] or now
				if now - run.badSince[key] >= 0.5 and not run.badSeen[key] then
					run.badSeen[key] = true
					run.bad[run.step] = (run.bad[run.step] and run.bad[run.step] .. "; " or "") .. bad
					Log(("step %d %s"):format(run.step, bad))
					Shot(bad)
				end
			else
				for k in pairs(run.badSince) do
					if k:find(name, 1, true) == 1 then run.badSince[k] = nil end
				end
			end
		end
	end
	-- The box.
	local wantCine = run.step == 2
	local say = ("%d/2: CineMode %s. TALK TO A QUEST GIVER now and open a quest, so Spoken reads it aloud"):format(
		run.step, wantCine and "ON" or "OFF")
	if into < 0 then
		ns.PadTestBox(say, ("GET READY: starts in %d"):format(math.ceil(-into)), 1, 0.82, 0)
		return
	end
	if not run.started[run.step] then
		run.started[run.step] = true
		if cine ~= wantCine and Cinematic_ToggleCineMode then
			Log(("act: CineMode %s"):format(wantCine and "on" or "off"))
			Cinematic_ToggleCineMode()
		end
		C_Timer.After(1, function()
			if not run then return end
			for _, name in ipairs(WINDOWS) do
				if _G[name] then WhyLog(_G[name], name .. " at step " .. run.step) end
			end
		end)
		for _, at in ipairs({ 5, 12, 20 }) do
			local step = run.step
			C_Timer.After(at, function()
				if run and run.step == step then Shot(("step %d, %d sec in"):format(step, at)) end
			end)
		end
	end
	ns.PadTestBox(say, ("RECORDING: %d sec left"):format(math.max(0, math.ceil(STEP_TIME - into))), 0.3, 1, 0.3)
	if into >= STEP_TIME then
		Log(("step %d done: %s"):format(run.step, run.bad[run.step] or "OK"))
		run.step, run.stepAt = run.step + 1, now
		if run.step > 2 then Finish(true) end
	end
end

Finish = function(done)
	run.ticker:Cancel()
	local verdict = ("step 1 (CineMode off) %s | step 2 (CineMode on) %s"):format(run.bad[1] or "OK", run.bad[2] or "OK")
	Log("verdict " .. verdict)
	local frameConfig = SpokenFrameConfig()
	if frameConfig and run.kept.spokenStyle ~= nil then
		frameConfig.Style = run.kept.spokenStyle
		Log("act: Spoken style back to " .. tostring(run.kept.spokenStyle))
	end
	if (ns.lastCinematic and true or false) ~= run.kept.cine and Cinematic_ToggleCineMode then
		Log("act: CineMode back as it was")
		Cinematic_ToggleCineMode()
	end
	run = nil
	ns.Print("Spoken test: " .. verdict)
	ns.Print("type /reload to save the log, then say check log")
	ns.PadTestBox(done and "Test done. Type /reload, then say check log" or "Test stopped. Type /reload", verdict, 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
end

-- Typed again while running: stops.
function ns.SpokenTest()
	if run then
		Finish(false)
		return
	end
	ns.db.spokenTestLog = {}
	run = { at = GetTime(), step = 1, stepAt = GetTime(), last = {}, hooked = {}, wasVisible = {}, started = {},
		bad = {}, badSince = {}, badSeen = {}, kept = { cine = ns.lastCinematic and true or false } }
	-- (Large Window: the style with the 3D head the player saw left behind.)
	local frameConfig = SpokenFrameConfig()
	if frameConfig then
		run.kept.spokenStyle = frameConfig.Style
		frameConfig.Style = "classic"
	end
	local versions = {}
	for _, name in ipairs({ ADDON_NAME, "Spoken", "Spoken_Quests", "DialogueUI", "Immersion", "EllesmereUI", "ElvUI" }) do
		if C_AddOns.IsAddOnLoaded(name) then
			local ok, version = pcall(C_AddOns.GetAddOnMetadata, name, "Version")
			versions[#versions + 1] = name .. " " .. (ok and tostring(version) or "?")
		end
	end
	Log(("start: build %s, %s, loaded: %s"):format(tostring((select(4, GetBuildInfo()))),
		ns.isRetail and "retail" or "not retail", table.concat(versions, ", ")))
	run.ticker = C_Timer.NewTicker(0.1, function()
		local ok, err = pcall(Tick)
		if not ok and run then
			Log("error " .. tostring(err))
			Finish(false)
		end
	end)
end
