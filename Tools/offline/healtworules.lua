-- Heal Vision's two Show in rows (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/healtworules.lua < /dev/null
-- Its Unit Frames and Nameplates tabs each have their own rule (2026-11-20):
-- the frames start in dungeons and raids only (out in the world they faded
-- healthy party members, a player's report), the plates everywhere but
-- cities. Checks the starts, where each is on (ns.HealVisionHere), the
-- once-only update of saved rules (Migrations.lua's healVisionTwoRulesV1)
-- and the page's Reset. Says PASS or FAIL per check.
-- (Optional first argument: another .toc to load, to run it on older code.)
local ns, wow = dofile("Tools/offline/load.lua")("forever", arg and arg[1])

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

local db = ns.db
local PLATES = ns.HEAL_VISION_PLATE_ROW
local FRAMES_START, PLATES_START = "(dungeon or raid) and not dead", "not city and not dead"
Check("the plates' row has a key", type(PLATES) == "string" and PLATES ~= "healVision", PLATES)

-- 1. A fresh install's starts.
Check("fresh: Unit Frames rule starts in dungeons and raids", db.frameRules.healVision == FRAMES_START,
	db.frameRules.healVision)
Check("fresh: Nameplates rule starts everywhere but cities", PLATES and db.frameRules[PLATES] == PLATES_START,
	PLATES and db.frameRules[PLATES])
Check("fresh: Show only while hurt still Off", not db.healVisionPlates and db.healVisionPlatesShow == "off")

-- 2. Where each is on: the facts as the rules read them, one place at a time.
-- (Its page on: the stand-in's fresh install starts on a profile with it off.)
db.handleHealVision = true
local realFacts = ns.RuleFactsNow
local function At(place)
	local facts = { world = place == "world", city = place == "city", dungeon = place == "dungeon",
		raid = place == "raid", instance = place == "dungeon" or place == "raid", dead = false, alive = true, always = true }
	ns.RuleFactsNow = function() return facts end
	local frames, plates = ns.HealVisionHere(db), ns.HealVisionHere(db, true)
	ns.RuleFactsNow = realFacts
	return frames and true or false, plates and true or false
end
local frames, plates = At("world")
Check("open world: unit frames not faded", frames == false)
Check("open world: nameplates rule on", plates == true)
frames = At("dungeon")
Check("dungeon: unit frames faded", frames == true)
frames = At("raid")
Check("raid: unit frames faded", frames == true)
frames, plates = At("city")
Check("city: unit frames not faded", frames == false)
Check("city: nameplates rule off", plates == false)
-- (Each row its own: a plates rule changed leaves the frames be.)
db.frameRules[PLATES] = "always"
frames, plates = At("world")
Check("plates rule 'always': plates on in the world", plates == true)
Check("plates rule 'always': unit frames still off in the world", frames == false)
db.frameRules[PLATES] = PLATES_START

-- 3. The once-only update of saved rules, here and in saved profiles.
local function Migrate(rule, plateRule)
	db.healVisionTwoRulesV1 = nil
	db.frameRules.healVision, db.frameRules[PLATES] = rule, plateRule
	db.profiles = db.profiles or {}
	db.profiles.twoRulesTest = { frameRules = { healVision = rule } }
	ns.RunMigrations()
	local saved = db.profiles.twoRulesTest.frameRules
	db.profiles.twoRulesTest = nil
	return db.frameRules.healVision, db.frameRules[PLATES], saved.healVision, saved[PLATES]
end
local mine, minePlates, profile, profilePlates = Migrate(PLATES_START, nil)
Check("update: v2.1.17's untouched start goes back to dungeons and raids", mine == FRAMES_START, mine)
Check("update: ... in a saved profile too", profile == FRAMES_START, profile)
Check("update: the plates' row left to its start", minePlates == nil and profilePlates == nil,
	tostring(minePlates) .. ", " .. tostring(profilePlates))
mine, minePlates, profile, profilePlates = Migrate("combat or group", nil)
Check("update: a rule the player wrote stays", mine == "combat or group", mine)
Check("update: the plates keep going by it", minePlates == "combat or group", minePlates)
Check("update: ... in a saved profile too", profile == "combat or group" and profilePlates == "combat or group",
	tostring(profile) .. ", " .. tostring(profilePlates))
mine, minePlates = Migrate("", nil)
Check("update: a cleared rule stays cleared, for both", mine == "" and minePlates == "",
	tostring(mine) .. ", " .. tostring(minePlates))
mine, minePlates = Migrate("world", "raid")
Check("update: a plates rule already there stays", mine == "world" and minePlates == "raid")
db.healVisionTwoRulesV1 = nil
db.frameRules.healVision = "world"
ns.RunMigrations()
db.frameRules.healVision = PLATES_START
ns.RunMigrations()
Check("update: once only", db.frameRules.healVision == PLATES_START)

-- 4. The page: both rows on it, and its Reset puts both rules back.
local settings = ns.PageSettings and ns.PageSettings()
local page = settings and settings["Heal Vision"]
local rows = page and page.rows and page.rows.frameRules
Check("page: both rows recorded for its Reset", rows and rows.healVision ~= nil and rows[PLATES] ~= nil)
db.frameRules.healVision, db.frameRules[PLATES] = "combat", "world"
-- (Its Reset page button's popup, on the page's content: canvas.content.)
local accept = StaticPopupDialogs.CINEMATIC_RESET_PAGE and StaticPopupDialogs.CINEMATIC_RESET_PAGE.OnAccept
for _, frame in ipairs(accept and wow.frames or {}) do
	if frame.pageName == "Heal Vision" and frame.content then
		accept(nil, frame.content)
		break
	end
end
Check("page: Reset puts both rules back", db.frameRules.healVision == FRAMES_START
	and db.frameRules[PLATES] == PLATES_START,
	tostring(db.frameRules.healVision) .. ", " .. tostring(db.frameRules[PLATES]))

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
