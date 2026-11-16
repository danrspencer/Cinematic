-- /cine debug euiswing: one run finding why EllesmereUI's swing timer
-- (ERB_SwingTimerFrame, its shell) stays hidden in CineMode on WoW Forever
-- (player report 2026-11-16, v2.1.4: gone in fights and out, back with
-- CineMode or the HUD page off). Three timed steps in the test box:
--   1 still:  out of a fight, CineMode on;
--   2 fight:  auto-attacking an enemy or a target dummy;
--   3 after:  out of the fight again, standing still.
-- Recorded the whole time, into CinematicDB.euiSwingTestLog:
--   every SetAlpha on its shell, ours or its own, with the caller;
--   twice a second when anything changes: the shell (shown, visible, alpha,
--   effective alpha), its rows (shown, alpha, drawn, running), our entry
--   (fade, target, applied, base) and the alpha EllesmereUI keeps to put
--   back after hiding it (SetElementVisibility saves the alpha it reads,
--   ours in it: our faded alpha saved there would come back as its own);
--   Inspect's reasons and a screenshot at the end of each step.
-- Verdicts at the end. Dev copy only (CinematicDev.toc).
local addonName, ns = ...

local WAIT = 4 -- seconds to read the box
local STEPS = {
	{ secs = 14, say = "1/3: Stand STILL, OUT OF A FIGHT. CineMode ON. Don't touch anything.", tag = "still" },
	{ secs = 18, say = "2/3: ATTACK an enemy or a target dummy and keep auto-attacking (melee).", tag = "fight" },
	{ secs = 18, say = "3/3: STOP attacking and LEAVE the fight. Then stand still.", tag = "after" },
}
local MAX_LINES = 4000

local run -- { step, at, ticker, entry, last, seen = { [tag] = facts } }
local hooked = false

local function Log(text)
	local log = CinematicDB and CinematicDB.euiSwingTestLog
	if not log or #log >= MAX_LINES then return end
	log[#log + 1] = ("%.2f %s %s"):format(GetTime(), run and STEPS[run.step] and STEPS[run.step].tag or "-", text)
end

local function Secret(value) return issecretvalue and issecretvalue(value) end
local function Num(value)
	if value == nil then return "nil" end
	if Secret(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Plain(value)
	return type(value) == "number" and not Secret(value) and value or nil
end
local function Call(frame, method)
	if not (frame and frame[method]) then return nil end
	local ok, value = pcall(frame[method], frame)
	if not ok then return nil end
	return value
end

local function Shell() return _G.ERB_SwingTimerFrame end

local function Entry()
	local shell = Shell()
	for _, entry in ipairs(ns.managed or {}) do
		if entry.frame == shell then return entry end
	end
	return nil
end

-- The alpha EllesmereUI keeps for the shell, to put back when it shows it.
local function RestoreAlpha()
	local shell, eui = Shell(), _G.EllesmereUI
	if not (shell and eui and type(eui._GetFFD) == "function") then return "n/a" end
	local ok, ffd = pcall(eui._GetFFD, shell)
	if not (ok and type(ffd) == "table") then return "n/a" end
	return ffd.restoreAlpha
end

-- Who called SetAlpha: the first lines of the stack, past this hook.
local function Caller()
	local stack = debugstack and debugstack(3, 4, 0) or ""
	stack = stack:gsub("Interface[/\\]AddOns[/\\]", ""):gsub("%[string \"@?", ""):gsub("\"%]", "")
	stack = stack:gsub("\n", " | ")
	return stack:sub(1, 300)
end

local function HookShell()
	local shell = Shell()
	if hooked or not shell then return end
	hooked = true
	hooksecurefunc(shell, "SetAlpha", function(_, alpha)
		if not run then return end
		local entry = run.entry
		local ours = entry and entry.settingAlpha
		Log(("SetAlpha %s by %s (restore %s)%s"):format(Num(alpha), ours and "US" or "IT", Num(RestoreAlpha()),
			ours and "" or (" from " .. Caller())))
	end)
end

-- Everything that decides whether the bar is seen, as one line.
local function Facts()
	local shell, entry = Shell(), run.entry
	local facts = {
		combat = InCombatLockdown() and "yes" or "no",
		cine = ns.lastCinematic and "on" or "off",
		shown = shell and tostring(ns.Flag(Call(shell, "IsShown"))) or "no frame",
		visible = shell and tostring(ns.Flag(Call(shell, "IsVisible"))) or "no frame",
		alpha = Call(shell, "GetAlpha"),
		effective = Call(shell, "GetEffectiveAlpha"),
		restore = RestoreAlpha(),
	}
	local rows = {}
	for _, row in ipairs(shell and { shell:GetChildren() } or {}) do
		rows[#rows + 1] = ("%s/%s/%s/%s"):format(ns.Flag(Call(row, "IsShown")) and "shown" or "hidden",
			Num(Call(row, "GetAlpha")), tostring(rawget(row, "_drawn")), tostring(rawget(row, "_live")))
	end
	facts.rows = table.concat(rows, " ")
	if entry then
		facts.ours = ("fade %s, target %s, applied %s, base %s, own %s, group %s"):format(Num(entry.alpha),
			Num(entry.fadeTarget), Num(entry.applied), Num(entry.baseAlpha), tostring(entry.ownAlpha), tostring(entry.group))
	else
		facts.ours = "not one of our faded frames"
	end
	return facts
end

local function FactsLine(facts)
	return ("combat %s, CineMode %s, shell shown %s visible %s alpha %s effective %s, EUI restore %s; rows %s; ours: %s")
		:format(facts.combat, facts.cine, facts.shown, facts.visible, Num(facts.alpha), Num(facts.effective),
			Num(facts.restore), facts.rows, facts.ours)
end

local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	Log(ok and ("screenshot %s at %s"):format(what, date("%m%d%y_%H%M%S")) or "screenshot failed")
end

local function LogWhy(tag)
	if not (run and run.entry and ns.WhyLater) then return end
	ns.WhyLater(run.entry, function(ok, status, out)
		Log(("why at %s: %s"):format(tag, ok and tostring(status) or ("error " .. tostring(status))))
		for _, reason in ipairs(out) do
			Log(("  [%s] %s%s"):format(tostring(reason.state), tostring(reason.text),
				reason.page and (" (" .. reason.page .. ")") or ""))
		end
	end)
end

-- EllesmereUI's swing timer settings on its active profile: what's stored
-- (defaults aren't, so visibility missing = its default, "in_combat"), with
-- the multi-select visibility (visibilityModes) spelled out. All its addons'
-- settings are in EllesmereUIDB.profiles[active].addons[folder].
local function LogSettings()
	local db, eui = _G.EllesmereUIDB, _G.EllesmereUI
	local active = eui and eui.GetActiveProfileName and eui.GetActiveProfileName() or "?"
	local profile = type(db) == "table" and type(db.profiles) == "table" and db.profiles[active]
	local addons = type(profile) == "table" and profile.addons
	local swing = type(addons) == "table" and type(addons.EllesmereUIResourceBars) == "table"
		and addons.EllesmereUIResourceBars.swingTimer
	if type(swing) ~= "table" then
		Log(("EUI profile %s: no swingTimer stored (all its defaults)"):format(tostring(active)))
		return
	end
	local parts = {}
	for key, value in pairs(swing) do
		if type(value) ~= "table" then
			parts[#parts + 1] = key .. "=" .. tostring(value)
		elseif key == "visibilityModes" then
			local modes = {}
			for mode, on in pairs(value) do modes[#modes + 1] = tostring(mode) .. "=" .. tostring(on) end
			table.sort(modes)
			parts[#parts + 1] = "visibilityModes={" .. table.concat(modes, ",") .. "}"
		end
	end
	table.sort(parts)
	Log(("EUI profile %s swingTimer: %s"):format(tostring(active), table.concat(parts, " ")))
end

local function Verdict(name, ok, detail)
	Log(("VERDICT %s: %s%s"):format(name, ok == nil and "CAN'T TELL" or (ok and "PASS" or "FAIL"),
		detail and (" (" .. detail .. ")") or ""))
end

-- true over min, false under, nil when it can't be read.
local function Over(value, min)
	local n = Plain(value)
	if not n then return nil end
	return n > min
end

local function Finish()
	local seen = run.seen
	local fight = seen.fight
	-- (Shown too: its alpha alone passed with the frame never shown, 2026-11-16.)
	local drawn = fight and Over(fight.effective, 0.5)
	if fight and fight.visible ~= "true" then drawn = false end
	Verdict("swing bar drawn in the fight", drawn,
		fight and ("visible %s, effective alpha %s"):format(fight.visible, Num(fight.effective)) or "no fight step")
	-- (nil: it never hid it, so it shows at full.)
	local restore = seen.after and seen.after.restore
	Verdict("EllesmereUI keeps a full alpha to put back", restore == nil or Over(restore, 0.9), "restore " .. Num(restore))
	local entry = run.entry
	Verdict("our base alpha full (what it set itself)", entry and Over(entry.baseAlpha, 0.9),
		entry and ("base " .. Num(entry.baseAlpha)) or "no entry")
	run.ticker:Cancel()
	run = nil
	ns.PadTestBox("Test done. Type /reload to save it, then say 'check log'.", "", 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
end

function ns.EuiSwingTest()
	if run then
		run.ticker:Cancel()
		run = nil
		ns.PadTestBoxHide()
		ns.Print("euiswing test stopped")
		return
	end
	if not Shell() then
		ns.Print("euiswing test: no ERB_SwingTimerFrame (EllesmereUI Resource Bars not loaded)")
		return
	end
	-- (Shown once it's switched on: hidden for good only while its Enable
	-- Swing Timer is off, its default. Off, the run proves nothing.)
	if not ns.Flag(Call(Shell(), "IsShown")) then
		ns.Print("euiswing test: EllesmereUI's swing timer is off. Turn on Enable Swing Timer on its Resource Bars > " ..
			"Swing Timer page, then run this again.")
		return
	end
	CinematicDB.euiSwingTestLog = {}
	HookShell()
	run = { step = 1, at = GetTime(), entry = Entry(), seen = {} }
	local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	local function Version(addon)
		local ok, value = pcall(meta, addon, "Version")
		return ok and tostring(value) or "?"
	end
	-- (The page's own switch and as it acts: under the Timers master on
	-- Forever, handleTimers. Its own alone read "on" with Timers off.)
	local effective = ns.PageSetting and ns.PageSetting("handleSwing")
	Log(("start %s: Cinematic %s, game %s, EllesmereUI Resource Bars %s, profile %s, Swing timer row on %s, page on %s (own switch %s, Timers %s), EUI support %s"):format(
		date("%Y-%m-%d %H:%M"), Version(addonName), tostring((GetBuildInfo())), Version("EllesmereUIResourceBars"),
		tostring(ns.ActiveProfile and ns.ActiveProfile()), tostring(ns.IsCombatShowOn("swing")),
		tostring(effective and true or false), tostring(ns.db.handleSwing), tostring(ns.db.handleTimers),
		tostring(ns.AddonSupportOn("EllesmereUIResourceBars"))))
	LogSettings()
	Log("facts: " .. FactsLine(Facts()))
	LogWhy("start")
	run.ticker = C_Timer.NewTicker(0.5, function()
		if not run then return end
		-- (Made later than the scan? Found once it's one of ours.)
		run.entry = run.entry or Entry()
		local step = STEPS[run.step]
		local into = GetTime() - run.at
		if into < WAIT then
			ns.PadTestBox(step.say, ("GET READY: starts in %d"):format(math.ceil(WAIT - into)), 1, 0.82, 0)
		else
			ns.PadTestBox(step.say, ("RECORDING: %d sec left"):format(math.ceil(step.secs - into)), 0.2, 1, 0.2)
		end
		local facts = Facts()
		local line = FactsLine(facts)
		if line ~= run.last then
			run.last = line
			Log("facts: " .. line)
		end
		if into >= step.secs then
			run.seen[step.tag] = facts
			LogWhy(step.tag)
			Shot(step.tag)
			if run.step >= #STEPS then
				-- (The last reasons come half a second on: the verdicts after them.)
				C_Timer.After(0.6, function() if run then Finish() end end)
				run.ticker:Cancel()
				return
			end
			run.step, run.at = run.step + 1, GetTime()
		end
	end)
end
