-- /cine debug euicast: one run finding why EllesmereUI's cast bar
-- (ERB_CastBarFrame) never shows (player report 2026-11-19, since v2.1.16
-- made it fade with our Cast bar row: Support/EllesmereUI.lua). It fades an
-- idle cast bar to alpha 0 (SetElementVisibility, never Hide) and back up
-- as a cast starts, keeping the alpha it read to put back: our faded alpha
-- saved there would keep it hidden. Three steps, each waiting for a cast of
-- yours (no time limit; the command again stops it):
--   1 idle:  CineMode off, out of a fight, cast a spell with a cast time;
--   2 fight: CineMode off, in a fight, cast one;
--   3 cine:  the test turns CineMode on, cast one more.
-- Recorded into CinematicDB.euiCastTestLog: every SetAlpha on the frame with
-- the caller, its state when it changes (shown, visible, alpha, effective,
-- EllesmereUI's restore alpha, the bar inside), our entry (fade, target,
-- applied, base), the game's own cast bar, Inspect's reasons, and 0.4 s into
-- each cast its state and a screenshot. Verdicts at the end. Dev copy only.
local addonName, ns = ...

local STEPS = {
	{ tag = "idle", say = "Cast bar test 1/3: OUT OF A FIGHT, cast any spell with a CAST TIME (a heal, a Hearthstone)." },
	{ tag = "fight", say = "Cast bar test 2/3: ATTACK an enemy or a target dummy, then cast a spell with a CAST TIME." },
	{ tag = "cine", say = "Cast bar test 3/3: CineMode is ON now. Cast a spell with a CAST TIME once more." },
}
local MAX_LINES = 4000
local INTO = 0.4 -- seconds into a cast to read it and take the screenshot

local run -- { step, entry, last, seen = { [tag] = facts }, cineWasOn, waiting, ticker }
local hooked = false
local events = CreateFrame("Frame")

local function Log(text)
	local log = CinematicDB and CinematicDB.euiCastTestLog
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

local function Shell() return _G.ERB_CastBarFrame end

local function Entry()
	local shell = Shell()
	for _, entry in ipairs(ns.managed or {}) do
		if entry.frame == shell then return entry end
	end
	return nil
end

-- The alpha EllesmereUI keeps for the frame, to put back when it shows it.
local function RestoreAlpha()
	local shell, eui = Shell(), _G.EllesmereUI
	if not (shell and eui and type(eui._GetFFD) == "function") then return "n/a" end
	local ok, ffd = pcall(eui._GetFFD, shell)
	if not (ok and type(ffd) == "table") then return "n/a" end
	return ffd.restoreAlpha
end

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

local function Facts()
	local shell, entry = Shell(), run.entry
	local bar = _G.ERB_CastBar
	local game = _G.PlayerCastingBarFrame or _G.CastingBarFrame
	local facts = {
		combat = InCombatLockdown() and "yes" or "no",
		cine = ns.IsCineModeOn and ns.IsCineModeOn() and "on" or "off",
		casting = (UnitCastingInfo("player") or UnitChannelInfo("player")) and "yes" or "no",
		shown = shell and tostring(ns.Flag(Call(shell, "IsShown"))) or "no frame",
		visible = shell and tostring(ns.Flag(Call(shell, "IsVisible"))) or "no frame",
		alpha = Call(shell, "GetAlpha"),
		effective = Call(shell, "GetEffectiveAlpha"),
		restore = RestoreAlpha(),
		flags = shell and ("casting %s channeling %s"):format(tostring(rawget(shell, "_casting")),
			tostring(rawget(shell, "_channeling"))) or "-",
		bar = bar and ("%s/%s"):format(ns.Flag(Call(bar, "IsShown")) and "shown" or "hidden", Num(Call(bar, "GetAlpha")))
			or "no bar",
		game = game and ("%s visible %s alpha %s"):format(game:GetName() or "?", tostring(ns.Flag(Call(game, "IsVisible"))),
			Num(Call(game, "GetAlpha"))) or "none",
	}
	if entry then
		facts.ours = ("fade %s, target %s, applied %s, base %s, own %s, group %s"):format(Num(entry.alpha),
			Num(entry.fadeTarget), Num(entry.applied), Num(entry.baseAlpha), tostring(entry.ownAlpha), tostring(entry.group))
	else
		facts.ours = "not one of our faded frames"
	end
	return facts
end

local function FactsLine(facts)
	return ("combat %s, CineMode %s, casting %s; ERB_CastBarFrame shown %s visible %s alpha %s effective %s, EUI restore %s, %s; bar %s; game's %s; ours: %s")
		:format(facts.combat, facts.cine, facts.casting, facts.shown, facts.visible, Num(facts.alpha),
			Num(facts.effective), Num(facts.restore), facts.flags, facts.bar, facts.game, facts.ours)
end

local function Shot(what)
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

-- EllesmereUI's cast bar settings on its active profile (what's stored;
-- defaults aren't).
local function LogSettings()
	local db, eui = _G.EllesmereUIDB, _G.EllesmereUI
	local active = eui and eui.GetActiveProfileName and eui.GetActiveProfileName() or "?"
	local profile = type(db) == "table" and type(db.profiles) == "table" and db.profiles[active]
	local addons = type(profile) == "table" and profile.addons
	local cb = type(addons) == "table" and type(addons.EllesmereUIResourceBars) == "table"
		and addons.EllesmereUIResourceBars.castBar
	if type(cb) ~= "table" then
		Log(("EUI profile %s: no castBar stored (all its defaults)"):format(tostring(active)))
		return
	end
	local parts = {}
	for key, value in pairs(cb) do
		if type(value) ~= "table" then parts[#parts + 1] = key .. "=" .. tostring(value) end
	end
	table.sort(parts)
	Log(("EUI profile %s castBar: %s"):format(tostring(active), table.concat(parts, " ")))
end

local function Verdict(name, ok, detail)
	Log(("VERDICT %s: %s%s"):format(name, ok == nil and "CAN'T TELL" or (ok and "PASS" or "FAIL"),
		detail and (" (" .. detail .. ")") or ""))
end

local function Over(value, min)
	local n = Plain(value)
	if not n then return nil end
	return n > min
end

local function SetCine(on)
	if not (ns.IsCineModeOn and Cinematic_ToggleCineMode) then return end
	if (ns.IsCineModeOn() and true or false) ~= on then
		Cinematic_ToggleCineMode()
		Log("CineMode turned " .. (on and "on" or "off") .. " by the test")
	end
end

local function Stop(done)
	if not run then return end
	run.ticker:Cancel()
	events:UnregisterAllEvents()
	if done then
		for _, step in ipairs(STEPS) do
			local seen = run.seen[step.tag]
			local drawn = seen and Over(seen.effective, 0.5)
			if seen and seen.visible ~= "true" then drawn = false end
			Verdict("cast bar drawn while casting, " .. step.tag, drawn,
				seen and ("visible %s, effective %s, restore %s"):format(seen.visible, Num(seen.effective), Num(seen.restore))
					or "no cast seen")
		end
	end
	local cineWasOn = run.cineWasOn
	run = nil
	SetCine(cineWasOn)
	ns.TestPrompt(done and "Cast bar test DONE. Type /reload, then say \"check log\"." or "Cast bar test stopped.", 20)
end

local function Prompt()
	ns.TestPrompt(STEPS[run.step].say, 3600)
end

local function OnCast()
	if not run or run.waiting then return end
	local step = STEPS[run.step]
	if step.tag == "idle" and InCombatLockdown() then
		Log("cast in a fight at step idle: not counted, waiting for one out of a fight")
		return
	end
	if step.tag == "fight" and not InCombatLockdown() then
		Log("cast out of a fight at step fight: not counted, waiting for one in a fight")
		return
	end
	run.waiting = true
	Log("cast started: " .. FactsLine(Facts()))
	C_Timer.After(INTO, function()
		if not run then return end
		local facts = Facts()
		run.seen[step.tag] = facts
		Log(("into the cast %.1fs: %s"):format(INTO, FactsLine(facts)))
		Shot(step.tag)
		LogWhy(step.tag)
		C_Timer.After(1, function()
			if not run then return end
			run.waiting = false
			if run.step >= #STEPS then
				Stop(true)
				return
			end
			run.step = run.step + 1
			if STEPS[run.step].tag == "cine" then SetCine(true) else SetCine(false) end
			Log("facts: " .. FactsLine(Facts()))
			Prompt()
		end)
	end)
end

events:SetScript("OnEvent", function(_, _, unit)
	if unit == "player" then OnCast() end
end)

function ns.EuiCastTest()
	if run then
		Stop(false)
		return
	end
	if not Shell() then
		ns.Print("euicast test: no ERB_CastBarFrame (EllesmereUI Resource Bars not loaded, or its Cast Bar is off). " ..
			"Turn on its Cast Bar, then run this again.")
		return
	end
	CinematicDB.euiCastTestLog = {}
	HookShell()
	run = { step = 1, entry = Entry(), seen = {}, cineWasOn = ns.IsCineModeOn and ns.IsCineModeOn() or false }
	local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	local function Version(addon)
		local ok, value = pcall(meta, addon, "Version")
		return ok and tostring(value) or "?"
	end
	Log(("start %s: Cinematic %s, game %s, EllesmereUI Resource Bars %s, profile %s, Cast bar row on %s, CineMode was %s, EUI support %s"):format(
		date("%Y-%m-%d %H:%M"), Version(addonName), tostring((GetBuildInfo())), Version("EllesmereUIResourceBars"),
		tostring(ns.ActiveProfile and ns.ActiveProfile()), tostring(ns.IsCombatShowOn("castbar")),
		run.cineWasOn and "on" or "off", tostring(ns.AddonSupportOn("EllesmereUIResourceBars"))))
	LogSettings()
	SetCine(false)
	Log("facts: " .. FactsLine(Facts()))
	LogWhy("start")
	events:RegisterEvent("UNIT_SPELLCAST_START")
	events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	Prompt()
	-- (Its state as it changes, twice a second; CineMode kept as the step wants.)
	run.ticker = C_Timer.NewTicker(0.5, function()
		if not run then return end
		run.entry = run.entry or Entry()
		SetCine(STEPS[run.step].tag == "cine")
		local line = FactsLine(Facts())
		if line ~= run.last then
			run.last = line
			Log("facts: " .. line)
		end
	end)
end
