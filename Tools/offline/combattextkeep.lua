-- Combat Text Style keeps the game's numbers as its rows say (offline, Lua 5.1
-- via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/combattextkeep.lua < /dev/null
-- A player reset the game's options and the game's damage numbers on their
-- target came back, though Your damage said Cinematic's (2026-11-20): the
-- set was "your change wins", so the reset's write let go of it for good.
-- Now its sets are kept (keep): an outside write is put back, the page off
-- still puts yours back, "Game's" on a row hands them over, and Keep yours
-- on the Game Settings page leaves them alone. A plain "your change wins"
-- set still lets go. Says PASS or FAIL per check.

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

local DAMAGE = "floatingCombatTextCombatDamage_v2"
local cvars = { [DAMAGE] = "1", floatingCombatTextCombatDamage = "1", floatingCombatTextCombatHealing_v2 = "1",
	floatingCombatTextCombatHealing = "1", floatingCombatTextPetMeleeDamage = "1",
	floatingCombatTextPetSpellDamage = "1", floatingCombatTextPetMeleeDamage_v2 = "1",
	floatingCombatTextPetSpellDamage_v2 = "1", someOtherSetting = "1", Sound_MusicVolume = "1", Sound_EnableMusic = "1" }
local outside = false
local timers = {}

local function Install()
	-- luacheck: push ignore 111 112 113 121 122
	C_CVar = {
		SetCVar = function(name, value) if cvars[name] ~= nil then cvars[name] = tostring(value) end end,
		GetCVar = function(name) return cvars[name] end,
	}
	SetCVar = function(name, value) return C_CVar.SetCVar(name, value) end
	GetCVar = function(name) return cvars[name] end
	hooksecurefunc = function(a, b, c)
		local tbl, name, fn = a, b, c
		if type(a) == "string" then tbl, name, fn = _G, a, b end
		local orig = tbl[name]
		if type(orig) ~= "function" then return end
		tbl[name] = function(...)
			local r = { orig(...) }
			fn(...)
			return unpack(r)
		end
	end
	debugstack = function()
		return outside and "[string \"@Interface/AddOns/Blizzard_Settings/Defaults.lua\"]:1: in function 'SetValue'"
			or "Interface/AddOns/CinematicDev/Core.lua:1: in function 'WriteCVar'"
	end
	C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
	-- luacheck: pop
end

local ns = dofile("Tools/offline/load.lua")("forever", "CinematicDev.toc", Install)
local function RunTimers()
	local now = timers
	timers = {}
	for _, fn in ipairs(now) do fn() end
end
local function OutsideSet(name, value)
	outside = true
	SetCVar(name, value)
	outside = false
	RunTimers()
end
local function Logged(text)
	for _, line in ipairs(ns.db.log or {}) do
		if tostring(line):find(text, 1, true) then return true end
	end
	return false
end

-- 1: the page on, Your damage Cinematic's (the default): the game's off.
local pageOn = true
ns.StyleOn = function(key) return key == "combatTextStyle" and pageOn end
ns.MasterOff = function() return false end -- (the switches over the rows: on)
ns.db.combatTextDamageBy = "ours"
ns.RefreshCombatTextStyle()
Check("1 page on: the game's damage numbers off", cvars[DAMAGE] == "0", cvars[DAMAGE])
Check("1 yours saved to put back", ns.db.savedCVars[DAMAGE] == "1", tostring(ns.db.savedCVars[DAMAGE]))

-- 2: a reset of the game's options writes its default: put back.
OutsideSet(DAMAGE, "1")
Check("2 reset's write put back", cvars[DAMAGE] == "0", cvars[DAMAGE])
Check("2 still held", ns.IsCVarHeld(DAMAGE))
Check("2 yours still saved", ns.db.savedCVars[DAMAGE] == "1", tostring(ns.db.savedCVars[DAMAGE]))
Check("2 logged", Logged(DAMAGE .. " changed outside the addon (its page holds it): put back to 0"))
ns.RefreshCombatTextStyle()
Check("2 the next refresh leaves it off", cvars[DAMAGE] == "0", cvars[DAMAGE])

-- 3: "Game's" on the row: the game's on, and kept on.
ns.db.combatTextDamageBy = "game"
ns.RefreshCombatTextStyle()
Check("3 Game's: the game's damage numbers on", cvars[DAMAGE] == "1", cvars[DAMAGE])
OutsideSet(DAMAGE, "0")
Check("3 Game's kept on through an outside write", cvars[DAMAGE] == "1", cvars[DAMAGE])

-- 4: the page off: yours back, and no longer held.
ns.db.combatTextDamageBy = "ours"
ns.RefreshCombatTextStyle()
Check("4 back to ours: off again", cvars[DAMAGE] == "0", cvars[DAMAGE])
pageOn = false
ns.RefreshCombatTextStyle()
Check("4 page off: yours back", cvars[DAMAGE] == "1", cvars[DAMAGE])
Check("4 page off: not held", not ns.IsCVarHeld(DAMAGE))
OutsideSet(DAMAGE, "0")
Check("4 page off: your change stands", cvars[DAMAGE] == "0", cvars[DAMAGE])
OutsideSet(DAMAGE, "1")

-- 5: Keep yours on the Game Settings page: left alone even with the page on.
pageOn = true
ns.RefreshCombatTextStyle()
Check("5 page on again: off", cvars[DAMAGE] == "0", cvars[DAMAGE])
ns.KeepYourCVar(DAMAGE)
Check("5 Keep yours: yours back", cvars[DAMAGE] == "1", cvars[DAMAGE])
OutsideSet(DAMAGE, "0")
OutsideSet(DAMAGE, "1")
Check("5 Keep yours: your changes stand", cvars[DAMAGE] == "1", cvars[DAMAGE])
ns.UseOurCVar(DAMAGE)
Check("5 Ours: off again", cvars[DAMAGE] == "0", cvars[DAMAGE])
OutsideSet(DAMAGE, "1")
Check("5 Ours: kept again", cvars[DAMAGE] == "0", cvars[DAMAGE])

-- 6: a plain "your change wins" set still lets go.
local plain = ns.CVarSet("Offline plain", "combattextkeep.lua", { playerWins = true, values = { someOtherSetting = "0" } })
ns.ApplyCVarSet(plain, true)
Check("6 plain set: ours written", cvars.someOtherSetting == "0", cvars.someOtherSetting)
OutsideSet("someOtherSetting", "1")
Check("6 plain set: your change stands", cvars.someOtherSetting == "1", cvars.someOtherSetting)
Check("6 plain set: let go", not ns.IsCVarHeld("someOtherSetting"))

print(fails == 0 and "all passed" or (fails .. " FAILED"))
