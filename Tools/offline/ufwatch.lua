-- Unit frame watch test (offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/ufwatch.lua < /dev/null
-- /cine debug ufwatch (Style/UnitFrameWatch.lua): the player-copy watch for
-- "unit frames messed up after a fight, /reload fixes it". A stand-in target
-- frame with a name, bars, level and portrait; checked: a fight that moves
-- nothing logs nothing, a level moved by a fight is logged with the unit and
-- what happened in it, a new target isn't compared with the old one, secret
-- reads don't break it or count as moved, and with the watch off nothing is
-- logged. Says PASS or FAIL per check.
-- (Optional first argument: another .toc to load, to run it on older code.)
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })

-- luacheck: push ignore 111 112 113 121 122 212
local ns = dofile("Tools/offline/load.lua")("forever", arg and arg[1], function()
	issecretvalue = function(value) return value == SECRET end
end)

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

-- Timers run when the test says so.
local timers = {}
C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
local function RunTimers()
	local list = timers
	timers = {}
	for _, fn in ipairs(list) do fn() end
end

local combat, guid = false, "Creature-1"
InCombatLockdown = function() return combat end
UnitExists = function(unit) return unit == "target" end
UnitGUID = function() return guid end
UnitName = function() return "Pixie Shadowburn" end
UnitLevel = function() return 11 end
UnitClassification = function() return "normal" end
UnitIsPlayer = function() return true end
UnitPowerType = function() return 0, "MANA" end
-- luacheck: pop

-- A region at a spot of the frame's (top left 100, 500): its center and size.
local secretReads = false
local function Region(name, x, y, w, h, isText)
	local r = { _name = name, x = x, y = y, w = w, h = h, shown = true }
	function r:GetCenter() if secretReads then return SECRET, SECRET end return 100 + self.x, 500 + self.y end
	function r:GetSize() return self.w, self.h end
	function r:IsShown() return self.shown end
	function r:GetPoint() return "CENTER", nil, "TOPLEFT", self.x, self.y end
	function r:GetDebugName() return self._name end
	if isText then function r:GetFont() return "font", 12, "" end end
	return r
end
local frame = {
	unit = "target",
	healthbar = Region("health", 70, -40, 150, 20),
	manabar = Region("power", 70, -60, 150, 10),
	name = Region("name", 70, -20, 80, 12, true),
	portrait = Region("portrait", 170, -40, 64, 64),
}
local level = Region("level", 140, -70, 20, 12, true)
function frame:GetLeft() return 100 end
function frame:GetTop() return 500 end
function frame:IsShown() return true end
_G.TargetFrame = frame
_G.PlayerFrame = nil
_G.FocusFrame = nil
ns.UnitPartRegions = function(f, part)
	if f == frame and part == "Level" then return { level } end
	return {}
end
ns.UnitThemeArt = function() return {} end

local function WatchLines()
	local out = {}
	for _, line in ipairs(ns.db.log or {}) do
		if line:find("ufwatch: ", 1, true) then out[#out + 1] = line end
	end
	return out
end
local function Has(lines, text)
	for _, line in ipairs(lines) do if line:find(text, 1, true) then return true end end
	return false
end
local function Fight(during)
	ns.UnitWatchOnEvent("PLAYER_REGEN_DISABLED")
	combat = true
	if during then during() end
	combat = false
	ns.UnitWatchOnEvent("PLAYER_REGEN_ENABLED")
	RunTimers()
end
local function Target(newGuid)
	guid = newGuid
	ns.UnitWatchOnEvent("PLAYER_TARGET_CHANGED")
	RunTimers()
end

ns.db.log = {}
CinematicDB = CinematicDB or {}
CinematicDB.unitWatch = nil
ns.UnitWatchReset()
ns.UnitWatchToggle()
Check("command turns it on", CinematicDB.unitWatch == true)
Check("its start is in the log", Has(WatchLines(), "ufwatch: on:"))
Target("Creature-1")

-- 1. A fight that moves nothing: no report.
local before = #WatchLines()
Fight()
Check("a fight that moves nothing logs nothing", #WatchLines() == before, #WatchLines() - before)

-- 2. The level moved by the fight (and a target change in it): logged.
Fight(function()
	ns.UnitWatchOnEvent("UNIT_LEVEL", "target")
	level.x, level.y = 160, -90
end)
local lines = WatchLines()
Check("a moved level is logged", Has(lines, "TargetFrame level1: at 160.0,-90.0"), lines[#lines])
Check("the report names the unit", Has(lines, "Pixie Shadowburn lvl 11 normal player power MANA"))
Check("the report says what happened in the fight", Has(lines, "level target 1"))
Check("parts that stayed aren't listed", not Has(lines, "TargetFrame health:"))

-- 3. A new target with another layout: not compared with the old one.
level.x, level.y = 140, -70
before = #WatchLines()
frame.manabar.shown = false -- (the new one has no power bar: its own layout)
Target("Creature-2")
Fight()
Check("a new target isn't compared with the last", #WatchLines() == before, #WatchLines() - before)

-- 4. Secret reads in the check: no error, nothing counted as moved.
before = #WatchLines()
Fight(function() secretReads = true end)
secretReads = false
Check("secret reads: no error, no report", #WatchLines() == before and not Has(WatchLines(), "failed"),
	WatchLines()[#WatchLines()])

-- 5. Off: nothing at all.
ns.UnitWatchToggle()
Check("the command again turns it off", CinematicDB.unitWatch == nil)
before = #WatchLines()
Fight(function() frame.healthbar.x = 10 end)
Check("off: a moved bar logs nothing", #WatchLines() == before)

-- 6. Diff by itself: a hidden part and a changed anchor count, a 1 px nudge doesn't.
local a = { bar = { x = 0, y = 0, w = 10, h = 5, shown = true, anchor = "LEFT>x.LEFT 0.0,0.0" } }
local b = { bar = { x = 1, y = 0, w = 10, h = 5, shown = true, anchor = "LEFT>x.LEFT 0.0,0.0" } }
Check("1 px is in place", #ns.UnitWatchDiff(a, b) == 0)
b.bar.shown = false
Check("hidden counts", #ns.UnitWatchDiff(a, b) == 1)
b.bar.shown, b.bar.anchor = true, "LEFT>y.LEFT 0.0,0.0"
Check("another anchor counts", #ns.UnitWatchDiff(a, b) == 1)

print(fails == 0 and "all checks passed" or (fails .. " check(s) failed"))
os.exit(fails == 0 and 0 or 1)
