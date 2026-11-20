-- Tooltip Location row (offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/tooltiplocation.lua < /dev/null
-- A player asked (Discord, 2026-11-16) to keep a party member's zone on their
-- tooltip without the class line: the zone used to go with the Spec and class
-- row. Now it's its own row (Location). Checks which lines the Tooltips page
-- takes out of a party member's short tooltip (name, class, zone) and a full
-- one (name, class, faction), with Spec and class off and Location on, and the
-- reverse. Also the update that starts Location as Spec was set. Says PASS or
-- FAIL per check.

-- luacheck: push ignore 111 112 113 121 122 212
local ns = dofile("Tools/offline/load.lua")("forever", arg and arg[1], function()
	LOCALIZED_CLASS_NAMES_MALE = { WARLOCK = "Warlock", DRUID = "Druid" }
	LOCALIZED_CLASS_NAMES_FEMALE = { WARLOCK = "Warlock", DRUID = "Druid" }
	FACTION_ALLIANCE, FACTION_HORDE = "Alliance", "Horde"
end)
-- luacheck: pop

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

-- The tooltip's left lines, as the game names them.
local lines = {}
for i = 1, 6 do
	lines[i] = UIParent:CreateFontString("GameTooltipTextLeft" .. i)
	_G["GameTooltipTextLeft" .. i] = lines[i]
end
local tooltip = CreateFrame("GameTooltip", "CineTestTooltip", UIParent)
local function Fill(texts)
	for i = 1, 6 do
		lines[i]:SetText(texts[i])
		lines[i]:Show()
	end
	return #texts
end
local function CutOf(texts)
	local count = Fill(texts)
	local cut = ns.TooltipLinesToCut(tooltip, count, "party1")
	local out = {}
	for i = 2, count do
		if cut[i] then out[#out + 1] = texts[i] end
	end
	return table.concat(out, ",")
end

local db = ns.db
db.enabled, db.handleTooltips, db.tooltipFullAfter = true, true, 2
-- (Every switch the page is under on: a fresh install has some off.)
local master = ns.PageSwitchOf("handleTooltips")
while master do
	db[master] = true
	master = ns.PageSwitchOf(master)
end
for _, part in ipairs(ns.TOOLTIP_PARTS) do
	db["tooltipShow" .. part .. "First"] = true
end
local SHORT = { "Sniper Lock", "Warlock", "Hillsbrad Foothills" }
local FULL = { "Guinevere Lysander", "Druid", "Alliance" }

Check("Location is a part of the grid", (function()
	for _, part in ipairs(ns.TOOLTIP_PARTS) do
		if part == "Location" then return true end
	end
end)())

db.tooltipShowSpecFirst, db.tooltipShowLocationFirst = false, true
Check("class off, zone on: only the class goes", CutOf(SHORT) == "Warlock", CutOf(SHORT))
Check("full tooltip, class off: Druid goes", CutOf(FULL) == "Druid", CutOf(FULL))
db.tooltipShowFactionFirst = false
Check("full tooltip, class + faction off", CutOf(FULL) == "Druid,Alliance", CutOf(FULL))
db.tooltipShowFactionFirst = true

db.tooltipShowSpecFirst, db.tooltipShowLocationFirst = true, false
Check("class on, zone off: only the zone goes", CutOf(SHORT) == "Hillsbrad Foothills", CutOf(SHORT))

db.tooltipShowSpecFirst, db.tooltipShowLocationFirst = false, false
Check("both off: both go", CutOf(SHORT) == "Warlock,Hillsbrad Foothills", CutOf(SHORT))

-- The update: Location starts as Spec was set (saved settings and profiles).
db.tooltipLocationV1 = nil
db.tooltipShowSpecFirst, db.tooltipShowSpecLater = false, false
db.tooltipShowLocationFirst, db.tooltipShowLocationLater = nil, nil
db.profiles = db.profiles or {}
db.profiles.CineTest = { settings = { tooltipShowSpecLater = false } }
ns.RunMigrations()
Check("update copies Spec's First", db.tooltipShowLocationFirst == false, tostring(db.tooltipShowLocationFirst))
Check("update copies Spec's Later", db.tooltipShowLocationLater == false, tostring(db.tooltipShowLocationLater))
Check("update reaches profiles", db.profiles.CineTest.settings.tooltipShowLocationLater == false)
Check("update runs once", db.tooltipLocationV1 == true)
db.profiles.CineTest = nil

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
if fails > 0 then os.exit(1) end
