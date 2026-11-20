-- Corpse test check (offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/corpse.lua < /dev/null
-- /cine debug deadmob (Dev/CorpseTest.lua, dev copy): a stand-in run through
-- every step with a stand-in mob: targeted alive, killed, the fight ends,
-- moused over, picked by soft interact, looted. Checked: the box moves on at
-- each step, the corpse's reads are logged, a secret name is logged as
-- <secret> and counted as not read, the combat log's death is noticed, a
-- RESULT per question at the end, soft interact put back and the events let
-- go; typed again mid-run, it stops cleanly. Says PASS or FAIL per check.
-- luacheck: push ignore 111 112 113 121 122 212
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local ns, wow = dofile("Tools/offline/load.lua")("forever", "CinematicDev.toc", function()
	issecretvalue = function(value) return value == SECRET end
end)

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

-- The world: who each unit name points at, the fight, the clock.
local MOB = "Creature-0-1-2-3-4-5"
local mob = { guid = MOB, name = "Flesh Eating Worm", dead = false }
local units = {}
local combat, now = false, 100
local cvars = { SoftTargetInteract = "0" }
GetTime = function() return now end
InCombatLockdown = function() return combat end
GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value) cvars[name] = tostring(value) end
UnitGUID = function(unit) return units[unit] and units[unit].guid end
UnitExists = function(unit) return units[unit] ~= nil end
UnitName = function(unit) return units[unit] and units[unit].name end
UnitIsDead = function(unit) return units[unit] and units[unit].dead or false end
UnitCanAttack = function(_, unit) return units[unit] ~= nil and not units[unit].dead end
UnitLevel = function() return 12 end
CanLootUnit = function() return true, true end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() return nil end }
C_TooltipInfo = { GetUnit = function(unit)
	return units[unit] and { lines = { { leftText = units[unit].name }, { leftText = "Skinnable" } } }
end }
C_Console = { GetAllCommands = function() return { { command = "nameplateShowDead" }, { command = "Sound" } } end }
Screenshot = function() end
local ticker
C_Timer.NewTicker = function(_, fn) ticker = { fn = fn, Cancel = function(self) self.cancelled = true end } return ticker end
C_Timer.After = function() end
local combatLogInfo
CombatLogGetCurrentEventInfo = function() return unpack(combatLogInfo) end
local box = ""
ns.PadTestBox = function(text, sub) box = tostring(text) .. " / " .. tostring(sub) end
ns.PadTestBoxHide = function() end
ns.TestPrompt = function() end
-- luacheck: pop

local function Tick(seconds)
	for _ = 1, math.floor((seconds or 0.25) / 0.25) do
		now = now + 0.25
		if ticker and not ticker.cancelled then ticker.fn() end
	end
end
local function Log() return CinematicDB.corpseLog or {} end
local function Has(text)
	for _, line in ipairs(Log()) do if line:find(text, 1, true) then return line end end
end
local function Fire(event, ...) wow.Fire(event, ...) end

CinematicDB = CinematicDB or {}
Check("the command is on ns", type(ns.CorpseTest) == "function")
-- (/cine debug corpse is the older corpse-run report: the test is deadmob.)
local realTest, called = ns.CorpseTest, nil
ns.CorpseTest = function() called = true end
ns.HandleSlash("debug deadmob")
Check("/cine debug deadmob starts the test", called == true)
called = nil
pcall(ns.HandleSlash, "debug corpse") -- (the report itself needs more of the game than the stand-in has)
Check("/cine debug corpse stays the corpse-run report", called == nil)
ns.CorpseTest = realTest

-- (Frames listening for the loot window before the run: other parts of the addon.)
local function Listening()
	local count = 0
	for _, frame in ipairs(wow.frames) do if frame._events.LOOT_OPENED then count = count + 1 end end
	return count
end
local listenersBefore = Listening()

-- 1. A whole run.
ns.CorpseTest()
Check("start logged", Has("start: Forever") ~= nil)
Check("Dead and Corpse settings listed", Has("nameplateShowDead=") ~= nil)
Check("soft interact held on", cvars.SoftTargetInteract == "3", cvars.SoftTargetInteract)
-- (Forever: asking for the combat log is a forbidden action with secret values.)
Check("combat log skipped with secret values", Has("COMBAT_LOG_EVENT_UNFILTERED=skipped") ~= nil)
local cleu = false
for _, frame in ipairs(wow.frames) do if frame._events.COMBAT_LOG_EVENT_UNFILTERED then cleu = true end end
Check("no frame of the test registered the combat log", not cleu)
Tick()
Check("step 1 asks for a kill", box:find("KILL", 1, true) ~= nil, box)
units.target = mob
combat = true
Tick()
Check("the kill kept", Has("the kill: Flesh Eating Worm " .. MOB) ~= nil)
mob.dead = true
Tick()
Check("the death seen on the target", Has("the kill died (target reads dead)") ~= nil)
Check("corpse read as target when it died", Has("just dead target: exists true, name Flesh Eating Worm") ~= nil)
Tick()
Check("step 2 waits for the fight", box:find("Finish the fight", 1, true) ~= nil, box)
units.target = nil -- (auto loot clears the target before the fight ends)
combat = false
Tick(2)
Check("target gone after the fight logged", Has("the corpse wasn't your target after the fight") ~= nil)
Check("its tooltip logged", Has("'Skinnable'") ~= nil)
units.target = mob
Check("a screenshot", Has("screenshot (corpse targeted)") ~= nil)
Tick()
Check("step 3 asks for the mouse", box:find("MOUSE over the body", 1, true) ~= nil, box)
units.target = nil
units.mouseover = { guid = MOB, name = SECRET, dead = true } -- (a secret name: counted as not read)
Tick()
Check("mouseover logged, name secret", Has("corpse as mouseover mouseover: exists true, name <secret>") ~= nil)
units.mouseover = nil
Tick()
Check("step 4 asks for the right-click", box:find("RIGHT-CLICK", 1, true) ~= nil, box)
units.softinteract = mob
Tick()
Check("soft interact pick logged", Has("soft interact picked the kill's corpse in step soft") ~= nil)
Fire("LOOT_OPENED")
Tick()
Check("loot window moves on", box:find("Close the loot window", 1, true) ~= nil, box)
Fire("LOOT_CLOSED")
Tick(4)
Check("result: target", Has("RESULT target: the corpse's name reads as your target") ~= nil)
Check("result: mouseover not read", Has("RESULT mouseover: no name read on mouseover") ~= nil)
Check("result: soft", Has("RESULT soft: soft interact picked the corpse (soft)") ~= nil)
Check("result: no death line", Has("RESULT death: no death line for it in the combat log") ~= nil)
Check("result: plate", Has("RESULT plate: no plate on the corpse") ~= nil)
Check("done box", box:find("Corpse test DONE", 1, true) ~= nil, box)
Check("soft interact put back", cvars.SoftTargetInteract == "0", cvars.SoftTargetInteract)
Check("ticker stopped", ticker.cancelled == true)
Check("events let go", Listening() == listenersBefore, Listening() .. " vs " .. listenersBefore)
Check("no errors logged", not Has("error"))

-- 2. A client without secret values: the combat log's death line moves it on.
issecretvalue = nil -- luacheck: ignore 121
units = { target = { guid = MOB, name = "Flesh Eating Worm", dead = false } }
ns.CorpseTest()
Check("combat log registered without secret values", Has("COMBAT_LOG_EVENT_UNFILTERED=true") ~= nil)
Tick()
combatLogInfo = { 0, "UNIT_DIED", false, nil, nil, 0, 0, MOB, "Flesh Eating Worm" }
Fire("COMBAT_LOG_EVENT_UNFILTERED")
Check("the death line noticed", Has("log UNIT_DIED: Flesh Eating Worm " .. MOB .. " (the kill)") ~= nil)
Check("it moves on to the fight's end", Has("--- step calm") ~= nil)
ns.CorpseTest()

-- 3. Typed again mid-run: stops.
units = { target = { guid = "Creature-9", name = "Rotted One", dead = false } }
ns.CorpseTest()
Tick()
ns.CorpseTest()
Check("stopped early", Has("stopped early") ~= nil and box:find("stopped", 1, true) ~= nil, box)
Check("no results when stopped", not Has("RESULT"))
Check("soft interact put back after a stop", cvars.SoftTargetInteract == "0", cvars.SoftTargetInteract)

for _, warning in ipairs(wow.warnings) do
	if warning:find("CorpseTest", 1, true) then Check("load: " .. warning, false) end
end
print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
if fails > 0 then os.exit(1) end
