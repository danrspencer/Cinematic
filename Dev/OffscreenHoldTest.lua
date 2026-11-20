-- /cine debug offhold: one run checking CineMode's hold on the game's Show
-- Offscreen Nameplates by Settings > General's Allow offscreen nameplates in
-- CineMode (plateOffscreen; Effects.lua's ns.plates.OffscreenWhy, 2026-11-20).
-- It runs itself, out of a fight in the open world; the only thing it asks of
-- you is targeting a mob (addons can't target). Steps:
--   1 off        CineMode off, your Show Offscreen set to 0 for the run
--   2 never      Never, CineMode on (turned on by the test): stays 0
--   3 yours on   Never, your Show Offscreen set to 1 (as yours): stays 1, not
--                turned off by CineMode; then 0 again
--   4 always     Always: on (1)
--   5 auto       Auto, no target: on only if Emote Vision's cards or Heal
--                Vision want it here (says which)
--   6 enemy      you target an attackable mob: let go (0)
--   7 cleared    you clear the target: as in step 5 again
--   8 city       Auto in a city, simulated for 3 s (the place readers answer
--                "city"): off, unless your own rows take cities in
--   9 back       your pick, CineMode and your setting back as they were
-- Each check: PASS or FAIL with the setting, the reason and what wants it.
-- Into CinematicDB.offHoldLog. Puts everything back, a /reload too. Dev copy
-- only (CinematicDev.toc).
local _, ns = ...

local SETTLE = 2

local run
local function Say(text)
	local log = CinematicDB and CinematicDB.offHoldLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Check(what, ok, detail)
	if ok then run.pass = run.pass + 1 else run.fail = run.fail + 1 end
	Say(("  %s %s: %s"):format(ok and "PASS" or "FAIL", what, detail))
end

local function Cine() return ns.lastCinematic and true or false end
local function SetCine(want)
	if Cine() ~= want and _G.Cinematic_ToggleCineMode then pcall(_G.Cinematic_ToggleCineMode) end
end
local function Value() return tostring(GetCVar("nameplateShowOffscreen")) end
local function Why()
	return ns.plates and ns.plates.OffscreenWhy and ns.plates.OffscreenWhy(Cine()) or nil
end
local function State()
	local wants = ns.plates and ns.plates.friendWants or {}
	return ("Show Offscreen %s; reason %s; cards want plates %s; Heal Vision plates %s; Allow offscreen %s; place %s; "
		.. "target %s (attackable %s); CineMode %s"):format(Value(), tostring(Why()), tostring(wants.plateCards),
		tostring(ns.HealVisionPlatesOn and ns.HealVisionPlatesOn()), tostring(ns.db.plateOffscreen),
		tostring(ns.PlateSuffix and ns.PlateSuffix() or "open world"), tostring(ns.Flag(UnitExists("target"))),
		tostring(ns.Flag(UnitCanAttack("player", "target"))), tostring(Cine()))
end
local function Enemy()
	return ns.Flag(UnitExists("target")) and ns.Flag(UnitCanAttack("player", "target")) and true or false
end
-- The Allow offscreen nameplates pick, the plate pass again at once.
local function Allow(choice)
	ns.db.plateOffscreen = choice
	if ns.plates and ns.plates.seen then ns.plates.seen.at = nil end
	Say("  Allow offscreen nameplates: " .. choice)
end
-- (Auto: on exactly while a Vision wants it here, the reason says which.)
local function AutoCheck(what)
	local why = Why()
	Check(what, (why ~= nil) == (Value() == "1"),
		(why and ("on for " .. why) or "nothing here wants it (cards' rows or Heal Vision): off") .. "; " .. State())
end

-- The simulated city: the place readers the plate code and the rows go by.
local real
local function City(on)
	if on and not real then
		real = { GetPlaceType = ns.GetPlaceType, PlateSuffix = ns.PlateSuffix, GetOptionPlace = ns.GetOptionPlace }
		ns.GetPlaceType = function() return "city" end
		ns.PlateSuffix = function() return "Cities" end
		ns.GetOptionPlace = function() return "city" end
	elseif not on and real then
		ns.GetPlaceType, ns.PlateSuffix, ns.GetOptionPlace = real.GetPlaceType, real.PlateSuffix, real.GetOptionPlace
		real = nil
	end
	if ns.plates and ns.plates.seen then ns.plates.seen.at = nil end -- (the plate pass again at once)
end

-- Your setting and CineMode as they were (a /reload cut it short: next login).
local function PutBack()
	City(false)
	local saved = CinematicDB and CinematicDB.offHoldWas
	if not saved or InCombatLockdown() then return end
	if Cine() then SetCine(false) end
	if saved.allow ~= nil and ns.db then ns.db.plateOffscreen = saved.allow end
	pcall(SetCVar, "nameplateShowOffscreen", saved.value)
	if saved.cine then C_Timer.After(0.5, function() SetCine(true) end) end
	CinematicDB.offHoldWas = nil
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	C_Timer.After(2, PutBack)
end)

local function Box(text, sub, waiting)
	ns.PadTestBox(text, sub or "", waiting and 1 or 0.3, waiting and 0.82 or 1, waiting and 0 or 0.3)
end

-- Each step: what it waits for (ask: shown while it waits), what it does as
-- it starts, and its checks once settled.
local STEPS = {
	{ key = "off", ask = "CLEAR your target (Escape) if you have one.",
		start = function() SetCine(false) end,
		ready = function() return not Cine() and not ns.Flag(UnitExists("target")) end,
		checks = function()
			pcall(SetCVar, "nameplateShowOffscreen", "0")
			Say("  your Show Offscreen set to 0 for the run")
			Check("off outside CineMode", Value() == "0", State())
		end },
	{ key = "never", start = function() Allow("never"); SetCine(true) end,
		ready = function() return Cine() and not Enemy() end,
		checks = function()
			Check("Never: not turned on", Value() == "0" and Why() == nil, State())
		end },
	{ key = "yours on", start = function()
			pcall(SetCVar, "nameplateShowOffscreen", "1")
			Say("  your Show Offscreen set to 1 (as yours)")
		end,
		ready = function() return Cine() and not Enemy() end,
		checks = function()
			Check("Never: yours on stays on (CineMode doesn't turn it off)", Value() == "1", State())
			pcall(SetCVar, "nameplateShowOffscreen", "0")
			Say("  your Show Offscreen back to 0")
		end },
	{ key = "always", start = function() Allow("always") end,
		ready = function() return Cine() and not Enemy() end,
		checks = function()
			local why = Why()
			Check("Always: on", Value() == "1" and why ~= nil, State())
		end },
	{ key = "auto", start = function() Allow("auto") end,
		ready = function() return Cine() and not Enemy() end,
		checks = function() AutoCheck("Auto: on only where a Vision wants it") end },
	{ key = "enemy", ask = "TARGET any attackable mob (Tab). Don't attack it.",
		ready = function() return Cine() and Enemy() end,
		checks = function()
			Check("Auto: let go with an attackable target", Value() == "0" and Why() == nil, State())
		end },
	{ key = "cleared", ask = "CLEAR your target (Escape).",
		ready = function() return Cine() and not ns.Flag(UnitExists("target")) end,
		checks = function() AutoCheck("Auto: as before once the target's cleared") end },
	{ key = "city", start = function() City(true) end,
		ready = function() return Cine() and not Enemy() end,
		checks = function()
			local why = Why()
			Say("  (simulated city) " .. State())
			Check("Auto: off in a city unless your rows take cities in", (why == nil) == (Value() == "0"),
				why and ("on for " .. why .. ": your own rule or City tick takes cities in") or "off")
			Check("Emote Vision's cards don't want plates in a city", not (ns.plates.friendWants.plateCards),
				tostring(ns.plates.friendWants.plateCards))
			City(false)
		end },
	{ key = "back", start = function() SetCine(false) end,
		ready = function() return not Cine() end,
		checks = function()
			Check("your 0 back outside CineMode", Value() == "0", State())
		end },
}

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	Say(("done: %d PASS, %d FAIL%s"):format(run.pass, run.fail, done and "" or " (stopped early)"))
	run = nil
	PutBack()
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped. /reload, then say \"check log\".",
		"", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local step = STEPS[run.index]
	if not step then
		Finish(true)
		return
	end
	if InCombatLockdown() then
		Box(("%d/%d: leave the fight first"):format(run.index, #STEPS), "WAITING FOR YOU", true)
		return
	end
	if run.phase == "start" then
		Say(("--- step %d: %s ---"):format(run.index, step.key))
		if step.start then step.start() end
		run.phase, run.phaseAt = "wait", GetTime()
		return
	end
	if run.phase == "wait" then
		if step.ready() then
			run.phase, run.phaseAt = "settle", GetTime()
		elseif step.ask then
			Box(("%d/%d: %s"):format(run.index, #STEPS, step.ask), "WAITING FOR YOU", true)
		else
			Box(("%d/%d: HANDS OFF"):format(run.index, #STEPS), "setting up", false)
		end
		return
	end
	if run.phase == "settle" then
		if not step.ready() then
			run.phase = "wait"
			return
		end
		if GetTime() - run.phaseAt < SETTLE then
			Box(("%d/%d: HANDS OFF"):format(run.index, #STEPS), "checking", false)
			return
		end
		local ok, err = pcall(step.checks)
		if not ok then Say("  error in checks: " .. tostring(err)) end
		run.index, run.phase = run.index + 1, "start"
	end
end

function ns.OffscreenHoldTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("offscreen hold test: not in a fight")
		return
	end
	CinematicDB.offHoldLog = {}
	CinematicDB.offHoldWas = { value = GetCVar("nameplateShowOffscreen"), cine = Cine(), allow = ns.db.plateOffscreen }
	run = { at = GetTime(), index = 1, phase = "start", pass = 0, fail = 0 }
	Say(("start: %s (game %s), Cinematic %s, CineMode %s, your Show Offscreen %s; %s"):format(
		ns.isRetail and "retail" or "classic", tostring((select(4, GetBuildInfo()))), ns.Version and ns.Version() or "?",
		tostring(Cine()), tostring(CinematicDB.offHoldWas.value), State()))
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print("offscreen hold test: follow the box (type it again to stop)")
end
