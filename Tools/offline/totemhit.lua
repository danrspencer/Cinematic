-- Totem test check (offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/totemhit.lua < /dev/null
-- /cine debug totemhit (Dev/TotemHitTest.lua, dev copy) on a stand-in: a
-- shaman targets a dummy, drops a totem, its hits land (no line, left out),
-- then attacks too. Checked: the command starts it, a non-shaman is refused,
-- each step moves on, the verdicts count lines, drawn and left out, the
-- Combat Text settings are held and put back, CineMode put back, the
-- recorder stopped; typed again mid-run, it stops cleanly.
-- luacheck: push ignore 111 112 113 121 122 212
local ns, wow = dofile("Tools/offline/load.lua")("forever", "CinematicDev.toc")

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

local now, combat, class = 100, false, "SHAMAN"
local target, totem = nil, nil
GetTime = function() return now end
InCombatLockdown = function() return combat end
UnitClass = function() return "Shaman", class end
UnitCanAttack = function(_, unit) return unit == "target" and target ~= nil end
UnitIsUnit = function(a, b)
	return target ~= nil and (((a == "nameplate1" or a == "nameplate2target") and b == "target") or a == b)
end
local TOTEM_GUID = "Creature-2523"
UnitName = function(unit)
	if unit == "nameplate2" then return totem end
	return unit == "target" and target or nil
end
UnitGUID = function(unit)
	if unit == "nameplate2" then return totem and TOTEM_GUID end
	if unit == "target" or unit == "nameplate2target" then return target and "Creature-1" or nil end
end
C_Spell = { GetSpellName = function(id) return ({ [3599] = "Searing Totem", [3606] = "Attack" })[id] end }
local cvars = { nameplateShowFriends = "0", nameplateShowFriendlyTotems = "0" }
GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value) cvars[name] = tostring(value) end
C_CVar = { GetCVar = GetCVar, SetCVar = SetCVar }
UnitExists = function() return false end
C_NamePlate = { GetNamePlateForUnit = function(unit) return unit == "target" and target and {} or nil end,
	GetNamePlates = function() return {} end }
GetTotemInfo = function(slot)
	if slot == 1 and totem then return true, totem, 90, 60 end
	return false
end
local ticker
C_Timer.NewTicker = function(_, fn) ticker = { fn = fn, Cancel = function(self) self.cancelled = true end } return ticker end
C_Timer.After = function() end
local prompt = ""
ns.TestPrompt = function(text) prompt = tostring(text) end
local cine = true
ns.IsCineModeOn = function() return cine end
_G.Cinematic_ToggleCineMode = function() cine = not cine end
-- (The recorder: a stand-in keeping its lines.)
local recLines, recording, recArgs = {}, false, nil
ns.CombatTextProbe = function(lines, seconds)
	if recording then recording, ns.combatTextRecord = false, nil return end
	recording, recArgs = true, { lines, seconds }
	recLines = {}
	ns.combatTextRecord = function(text) recLines[#recLines + 1] = text end
end
ns.RefreshCombatTextStyle = function() end
-- luacheck: pop

local function Tick(seconds)
	for _ = 1, math.floor((seconds or 0.25) / 0.25) do
		now = now + 0.25
		if ticker and not ticker.cancelled then ticker.fn() end
	end
end
local function Has(text)
	for _, line in ipairs(recLines) do if line:find(text, 1, true) then return line end end
end
local function Fire(event, ...) wow.Fire(event, ...) end
-- A hit on the dummy's plate, and what our numbers made of it.
local function Hit(school, drawn)
	Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 50, school)
	ns.combatTextRecord(drawn and "DRAWN unit=nameplate1" or "LEFT OUT")
	now = now + 2
end

Check("the command is on ns", type(ns.TotemHitTest) == "function")
local realTest, called = ns.TotemHitTest, nil
ns.TotemHitTest = function() called = true end
ns.HandleSlash("debug totemhit")
Check("/cine debug totemhit starts the test", called == true)
ns.TotemHitTest = realTest

-- 0. Not a shaman: refused, nothing changed.
class = "MAGE"
ns.TotemHitTest()
Check("a mage is refused", not recording and ticker == nil)
class = "SHAMAN"

-- 1. A whole run.
ns.db.combatTextStyle, ns.db.combatTextPetBy = false, "game"
ns.TotemHitTest()
Check("recorder started long", recording and recArgs[2] == 1800, recArgs and recArgs[2])
Check("style held on", ns.db.combatTextStyle == true and ns.db.combatTextPetBy == "ours")
Check("CineMode off for the run", cine == false)
Check("totem plates held on", cvars.nameplateShowFriendlyTotems == "1", cvars.nameplateShowFriendlyTotems)
Check("start logged", Has("TOTEMHIT start: Forever") ~= nil)
Tick()
Check("step 1 asks for a dummy", prompt:find("1/3", 1, true) ~= nil, prompt)
target = "Training Dummy"
Tick()
Check("on to the totem step", Has("--- step totem") ~= nil)
Tick()
Check("step 2 asks for a totem", prompt:find("put down", 1, true) ~= nil, prompt)
totem = "Searing Totem"
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 3599)
Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
Check("totem plate found", Has("your totem's plate: nameplate2 Searing Totem " .. TOTEM_GUID) ~= nil)
Tick()
Check("totem seen", Has("totems now: 1=Searing Totem") ~= nil)
Check("step 2 says don't attack", prompt:find("DON'T attack", 1, true) ~= nil, prompt)
now = now + 2
Hit(1, false) -- (a swing: not the totem's)
for i = 1, 8 do
	if i > 1 then Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate2", "cast-t", 3606) end
	now = now + 0.5
	Hit(4, false)
end
Fire("COMBAT_LOG_MESSAGE", "x")
Tick()
Check("verdict: one log line", Has("VERDICT totem log: 1 combat log lines came with 8 totem hits") ~= nil)
Check("verdict: numbers left out", Has("VERDICT totem numbers: FAIL: 0 numbers drawn for 8 totem hits, 9 left out") ~= nil)
Check("verdict: totem casts", Has("VERDICT totem casts: 7 cast events from your totems (Attack 3606 x7)") ~= nil)
Check("verdict: matched", Has("VERDICT totem match: 7 of 8 totem hits landed within 3 s of a totem cast") ~= nil)
Check("verdict: target", Has("VERDICT totem target: its target read on 7 of 7 casts, 7 of them your target") ~= nil)
Check("verdict: schools", Has("VERDICT totem schools: 1 x1, 4 x8") ~= nil)
Check("on to both", Has("--- step both") ~= nil)
for _ = 1, 4 do Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 403) end
for _ = 1, 12 do Hit(4, true) end
Tick()
Check("verdict: both", Has("VERDICT both: 12 hits on the dummy, 4 casts of yours, 0 log lines, 12 drawn") ~= nil)
Check("done prompt", prompt:find("Totem test DONE", 1, true) ~= nil, prompt)
Check("settings put back", ns.db.combatTextStyle == false and ns.db.combatTextPetBy == "game")
Check("CineMode put back", cine == true)
Check("totem plates put back", cvars.nameplateShowFriendlyTotems == "0", cvars.nameplateShowFriendlyTotems)
Check("recorder stopped", not recording)
Check("ticker stopped", ticker.cancelled == true)
Check("no errors logged", not Has("error"))

-- 2. Typed again mid-run: stops, all put back.
ticker = nil
ns.TotemHitTest()
Tick()
ns.TotemHitTest()
Check("stopped early", Has("stopped early") ~= nil and prompt:find("stopped", 1, true) ~= nil, prompt)
Check("no verdicts when stopped", not Has("VERDICT"))
Check("settings put back after a stop", ns.db.combatTextStyle == false and ns.db.combatTextPetBy == "game")
Check("recorder stopped after a stop", not recording)

for _, warning in ipairs(wow.warnings) do
	if warning:find("TotemHit", 1, true) then Check("load: " .. warning, false) end
end
print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
if fails > 0 then os.exit(1) end
