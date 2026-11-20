-- /cine debug ctkeep: Combat Text Style keeps the game's damage numbers as
-- its Your damage row says (2026-11-20: a reset of the game's options turned
-- Text on Target > Damage back on, and Cinematic let it be). Hands off, about
-- 10 s; CineMode off meanwhile; everything put back as it was at the end:
--   1 held     the page and its switches on, Your damage Cinematic's: the
--              game's damage settings 0 and held (PASS/FAIL)
--   2 reset    the game's own Damage setting turned on, as its options' reset
--              does (its settings object, else SetCVar): back to 0 within a
--              second, still held, logged (PASS/FAIL)
--   3 game's   Your damage set to Game's: on; turned off from outside, back on
--              (PASS/FAIL)
--   4 back     your settings back: the game's damage settings as they were at
--              the start (PASS/FAIL)
-- Into CinematicDB.combatTextKeepLog. Dev copy only.
local _, ns = ...

local CVARS = { "floatingCombatTextCombatDamage", "floatingCombatTextCombatDamage_v2" }
local WAIT = 1.5
local run

local function Log(text)
	local log = CinematicDB and CinematicDB.combatTextKeepLog
	if log then log[#log + 1] = ("%s %s"):format(date("%H:%M:%S"), text) end
end
local function CVar(name)
	local ok, value = pcall(GetCVar, name)
	return ok and value or nil
end
local function Present()
	local list = {}
	for _, cvar in ipairs(CVARS) do
		if CVar(cvar) ~= nil then list[#list + 1] = cvar end
	end
	return list
end
local function State(label)
	local parts = {}
	for _, cvar in ipairs(run.cvars) do
		parts[#parts + 1] = ("%s=%s held %s saved %s leftAlone %s"):format(cvar, tostring(CVar(cvar)),
			tostring(ns.IsCVarHeld(cvar)), tostring(ns.db.savedCVars[cvar]), tostring(ns.db.cvarsLeftAlone[cvar]))
	end
	Log(("  %s: page on %s, your damage by %s | %s"):format(label, tostring(ns.StyleOn("combatTextStyle")),
		tostring(ns.CombatTextBy and ns.CombatTextBy("damage")), table.concat(parts, " | ")))
end
local function All(value, held)
	for _, cvar in ipairs(run.cvars) do
		local now = CVar(cvar)
		if not (now == value or tonumber(now) == tonumber(value)) then return false end
		if held ~= nil and ns.IsCVarHeld(cvar) ~= held then return false end
	end
	return true
end
local function Verdict(ok, text)
	if ok then run.pass = run.pass + 1 else run.fail = run.fail + 1 end
	Log(("  verdict %s: %s"):format(ok and "PASS" or "FAIL", text))
end
local function LogHas(text, from)
	for i = from + 1, #(ns.db.log or {}) do
		local line = ns.db.log[i]
		if type(line) == "string" and line:find(text, 1, true) then return true end
	end
	return false
end
local function CineOn() return ns.IsCineModeOn and ns.IsCineModeOn() and true or false end
local function SetCine(on)
	if Cinematic_ToggleCineMode and CineOn() ~= on then Cinematic_ToggleCineMode() end
end

-- An outside write, as the game's options make it: through the game's own
-- setting object where it has one for this setting (its reset's path), else
-- SetCVar. Says which.
local function OutsideWrite(cvar, on)
	local setting = Settings and Settings.GetSetting and select(2, pcall(Settings.GetSetting, cvar))
	if type(setting) == "table" and setting.SetValue then
		local current = setting.GetValue and select(2, pcall(setting.GetValue, setting))
		local value = on
		if type(current) == "number" or type(current) == "string" then value = on and 1 or 0 end
		if pcall(setting.SetValue, setting, value) then return "the game's setting object" end
	end
	SetCVar(cvar, on and "1" or "0")
	return "SetCVar"
end

-- Your settings back as they were, then the page's refresh.
local function PutBack()
	if not run or run.putBack then return end
	run.putBack = true
	for key, value in pairs(run.kept) do ns.db[key] = value end
	for cvar, value in pairs(run.leftAlone) do
		if value then ns.KeepYourCVar(cvar) end
	end
	ns.RefreshCombatTextStyle()
	SetCine(run.cineWasOn)
end

local function Finish()
	State("after putting back")
	local same = true
	for cvar, value in pairs(run.start) do
		if CVar(cvar) ~= value then same = false end
	end
	Verdict(same, "the game's damage settings as they were at the start")
	local line = ("done: %d pass, %d fail"):format(run.pass, run.fail)
	Log(line)
	run = nil
	ns.TestPrompt(("Combat text keep test DONE: %s. Say \"check log\"."):format(line), 15)
end

local function Later(fn)
	C_Timer.After(WAIT, function()
		if run then ns.Guard(fn) end
	end)
end

function ns.CombatTextKeepTest()
	if not CinematicDB then return end
	if run then
		PutBack()
		run = nil
		ns.TestPrompt("Combat text keep test stopped; your settings are back.", 4)
		return
	end
	CinematicDB.combatTextKeepLog = {}
	run = { pass = 0, fail = 0, kept = {}, leftAlone = {}, start = {}, cineWasOn = CineOn() }
	run.cvars = Present()
	Log(("start: %s (game %s), in a fight %s, CineMode %s"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), tostring(InCombatLockdown()), tostring(run.cineWasOn)))
	if #run.cvars == 0 then
		Log("  verdict INFO: this client has none of the damage number settings: nothing to test")
		run = nil
		ns.TestPrompt("Combat text keep test: nothing to test on this client. Say \"check log\".", 10)
		return
	end
	for _, cvar in ipairs(run.cvars) do run.start[cvar] = CVar(cvar) end
	State("as it was")
	SetCine(false)

	Log("--- 1 of 4: held ---")
	ns.TestPrompt("Combat text keep test: hands off, about 10 seconds.", 10)
	local function Keep(key, value)
		if run.kept[key] == nil then run.kept[key] = ns.db[key] == nil and false or ns.db[key] end
		ns.db[key] = value
	end
	-- (The page and every switch above it on: Style switch chain.)
	Keep("styleGeneral", true)
	local switch = "combatTextStyle"
	while switch do
		Keep(switch, true)
		switch = ns.PageSwitchOf(switch)
	end
	Keep("combatTextDamageBy", "ours")
	for _, cvar in ipairs(run.cvars) do
		run.leftAlone[cvar] = ns.db.cvarsLeftAlone[cvar] or false
		if ns.db.cvarsLeftAlone[cvar] then ns.UseOurCVar(cvar) end
	end
	ns.RefreshCombatTextStyle()
	State("page on, Cinematic's")
	Verdict(All("0", true), "the game's damage settings 0 and held")

	Log("--- 2 of 4: the game's options reset Damage ---")
	local logFrom = #(ns.db.log or {})
	for _, cvar in ipairs(run.cvars) do
		Log(("  %s turned on through %s"):format(cvar, OutsideWrite(cvar, true)))
	end
	State("right after")
	Later(function()
		State(WAIT .. " s later")
		Verdict(All("0", true), "back to 0 and still held")
		Verdict(LogHas("(its page holds it): put back to 0", logFrom), "the put-back logged")

		Log("--- 3 of 4: Your damage: Game's ---")
		ns.db.combatTextDamageBy = "game"
		ns.RefreshCombatTextStyle()
		State("Game's")
		Verdict(All("1", true), "the game's damage settings on and held")
		for _, cvar in ipairs(run.cvars) do
			Log(("  %s turned off through %s"):format(cvar, OutsideWrite(cvar, false)))
		end
		Later(function()
			State(WAIT .. " s later")
			Verdict(All("1", true), "back on and still held")

			Log("--- 4 of 4: your settings back ---")
			PutBack()
			Later(Finish)
		end)
	end)
end
