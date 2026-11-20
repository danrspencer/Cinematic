-- You level up card's emotes (offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/youlevelemotes.lua < /dev/null
-- The card started with Cheer, Dance, Flex; now Cheer, Congratulate, Commend
-- (user, 2026-11-20). Checks the new default, and the update that moves a
-- list still at the old default (saved settings, profiles) but keeps one a
-- player changed. Says PASS or FAIL per check.

-- luacheck: push ignore 111 112 113 121 122 212
local ns = dofile("Tools/offline/load.lua")("forever", arg and arg[1])
-- luacheck: pop

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

local NEW, OLD = "CHEER,CONGRATULATE,COMMEND", "CHEER,DANCE,FLEX"
Check("new default", ns.DEFAULTS.emoteVisionYouLevelEmotes == NEW, ns.DEFAULTS.emoteVisionYouLevelEmotes)

local db = ns.db
db.youLevelEmotesV1 = nil
db.emoteVisionYouLevelEmotes = OLD
db.profiles = db.profiles or {}
db.profiles.CineOld = { settings = { emoteVisionYouLevelEmotes = OLD } }
db.profiles.CineMine = { settings = { emoteVisionYouLevelEmotes = "CHEER,DANCE" } }
ns.RunMigrations()
Check("old default moves", db.emoteVisionYouLevelEmotes == NEW, db.emoteVisionYouLevelEmotes)
Check("profile at old default moves", db.profiles.CineOld.settings.emoteVisionYouLevelEmotes == NEW)
Check("changed list stays", db.profiles.CineMine.settings.emoteVisionYouLevelEmotes == "CHEER,DANCE")
Check("update runs once", db.youLevelEmotesV1 == true)
db.emoteVisionYouLevelEmotes = OLD
ns.RunMigrations()
Check("not again (a player's own pick later)", db.emoteVisionYouLevelEmotes == OLD)
Check("card's buttons", table.concat(ns.EmoteVisionEmotes("YouLevel"), ",") == OLD)
db.emoteVisionYouLevelEmotes = NEW
Check("card's buttons, new", table.concat(ns.EmoteVisionEmotes("YouLevel"), ",") == NEW)
db.profiles.CineOld, db.profiles.CineMine = nil, nil

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
if fails > 0 then os.exit(1) end
