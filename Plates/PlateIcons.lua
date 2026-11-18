-- The Nameplates hub's Icons page: the class icons beside players' health
-- bars (friendly and enemy apart) and the role icons beside your group's
-- (tank, healer, damage), each a Show in row of its own (PlateParts draws
-- them). The Nameplate Style page's Show in row goes the same way: see
-- ns.PlateIconWanted. Outside CineMode only a row's Always counts; in it,
-- the rest of the row too, as the Standard Frames rows go.
-- They used to be rows on the Nameplates page's Cinematic plate parts grid
-- (plateAlwaysPart<part>, plateCombatPart<part>...), then had a When for a
-- while (plateIconWhen<part>, targetArrowWhen): moved over once, below.

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.handlePlateIcons = true -- (its page's switch: off, no class or role icons at all)
DEFAULTS.plateIconSize = 1        -- the icons' size, times their own
local ICON_PARTS = { "ClassFriendly", "ClassEnemy", "RoleTank", "RoleHealer", "RoleDamager" }

-- Each part's Show in row (its ticks in the frames lists by this key) and
-- its Always setting. Enemy class icons and tank and healer role icons
-- always to start with, as their Always ticks were.
local ROW_KEY, ALWAYS_KEY = { TargetArrow = "platemark:show" }, { TargetArrow = "targetArrowAlways" }
for _, part in ipairs(ICON_PARTS) do
	ROW_KEY[part], ALWAYS_KEY[part] = "plateicon:" .. part, "plateIconAlways" .. part
end
for part, key in pairs(ALWAYS_KEY) do
	DEFAULTS[key] = false
	ns.CINE_SHOW_SETTING[ROW_KEY[part]] = key
end
for _, part in ipairs({ "ClassEnemy", "RoleTank", "RoleHealer" }) do
	DEFAULTS[ALWAYS_KEY[part]] = true
end

-- Whether a part (an icon above, or TargetArrow) shows now, by its Show in
-- row, or nil for a part that has none (the Quest Icon: its grid row).
-- cinematic: CineMode's on. (Rows read four times a second: ns.RowOnNow
-- works out the facts each time.)
local READ_EVERY = 0.25
local readAt, readNow = -1, {}
function ns.PlateIconWanted(part, cinematic)
	local key = ROW_KEY[part]
	if not key then return nil end
	local db = ns.db
	if part ~= "TargetArrow" and not (db.handlePlateIcons and not ns.MasterOff("handlePlateIcons", db)) then return false end
	if db[ALWAYS_KEY[part]] then return true end
	if not cinematic then return false end
	local now = GetTime()
	if now - readAt >= READ_EVERY then
		readAt = now
		wipe(readNow)
	end
	local shows = readNow[part]
	if shows == nil then
		local ok, on = pcall(ns.RowOnNow, key, false, true)
		shows = ok and on and true or false
		readNow[part] = shows
	end
	return shows
end

-- The old choices to the rows, once (live settings and saved profiles). A
-- When: always, Always ticked; in CineMode, the CineMode tick; in combat,
-- the In combat tick; off, nothing. Before it, the grid's ticks: Always
-- ticked, Always; a CineMode tick (a place, CineMode, groups), the CineMode
-- tick; only fight ticks, In combat. A saved profile holding none of a
-- part's old choices keeps the default.
local WHEN_KEY = { TargetArrow = "targetArrowWhen" }
for _, part in ipairs(ICON_PARTS) do WHEN_KEY[part] = "plateIconWhen" .. part end
local function OldWhen(t, part)
	local when = t[WHEN_KEY[part]]
	if when ~= nil then return when end
	-- (plate<column>Part<part>: Always, Combat, CombatPvP, or CineMode's
	-- others: Cinematic, Group, In<place>.)
	local any, always, place, fight = false, false, false, false
	local suffix = "Part" .. part
	for setting, value in pairs(t) do
		local column = type(setting) == "string" and setting:match("^plate(%a+)" .. suffix .. "$")
		if column then
			any = true
			if value == true then
				if column == "Always" then always = true
				elseif column == "Combat" or column == "CombatPvP" then fight = true
				else place = true end
			end
		end
	end
	if not any then return nil end
	if t["plateAlways" .. suffix] == nil and ns.PLATE_ICONS_ALWAYS then
		for _, each in ipairs(ns.PLATE_ICONS_ALWAYS) do
			if each == part then always = true end
		end
	end
	return always and "always" or place and "cinemode" or fight and "combat" or "off"
end
local function Migrate(t)
	if type(t) ~= "table" then return end
	for part, key in pairs(ROW_KEY) do
		local when = OldWhen(t, part)
		if when and t[ALWAYS_KEY[part]] == nil then
			t[ALWAYS_KEY[part]] = when == "always"
			local list = when == "cinemode" and "cineModeShow" or when == "combat" and "combatShow" or nil
			if list then
				t[list] = type(t[list]) == "table" and t[list] or {}
				t[list][key] = true
			end
		end
		t[WHEN_KEY[part]] = nil
	end
end
-- Nameplate Style's Show in row has no Cine column now (the CineMode page's
-- Outside CineMode > Nameplates says whether plates work outside it): a Cine
-- tick, "all through CineMode", is Always, the same there. Once, every profile.
local function CineToAlways(t)
	if type(t) ~= "table" then return end
	local list = t.cineModeShow
	if type(list) == "table" and list[ROW_KEY.TargetArrow] then
		list[ROW_KEY.TargetArrow] = nil
		t[ALWAYS_KEY.TargetArrow] = true
	end
end
function ns.MigratePlateIconWhen(db)
	if not db.plateIconShowInV1 then
		Migrate(db)
		for _, saved in pairs(type(db.profiles) == "table" and db.profiles or {}) do
			Migrate(saved)
		end
		db.plateIconWhenV1 = nil
		db.plateIconShowInV1 = true
	end
	if not db.markCineAlwaysV1 then
		CineToAlways(db)
		for _, saved in pairs(type(db.profiles) == "table" and db.profiles or {}) do
			CineToAlways(type(saved.settings) == "table" and saved.settings or saved)
		end
		db.markCineAlwaysV1 = true
	end
end

-- Each row's icon, before its name: the same art PlateParts draws (role
-- coords as its ROLES'); the class rows' as your own class. (Pixels on the
-- textures: the class circles 256 square, the roles 64.)
local ROLE_COORDS = {
	RoleTank = { 0, 19, 22, 41 },
	RoleHealer = { 20, 39, 1, 20 },
	RoleDamager = { 20, 39, 22, 41 },
}
local function IconText(part)
	local role = ROLE_COORDS[part]
	if role then
		return ("|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:%d:%d:%d:%d|t "):format(unpack(role))
	end
	local ok, _, class = pcall(UnitClass, "player")
	local c = ok and type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if not c then return "" end
	return ("|TInterface\\TargetingFrame\\UI-Classes-Circles:16:16:0:0:256:256:%d:%d:%d:%d|t "):format(
		c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

local function Changed()
	if ns.RefreshPlateIcons then ns.RefreshPlateIcons() end
end

function ns.CreatePlateIconsPage(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Nameplate Icons"])
	-- (The Nameplates icon's Icons tab, 2026-11-16: its tabs over the title.)
	local tabs = ns.PageTabs(content, ns.ShowInTabs("plates"), ns.ShowInIndex("plates", "Plate Icons"))
	title:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 8, -14)
	local intro = kit.PageIntro(content, title, L["Class and role icons beside players' health bars on their nameplates."])
	local switch = kit.PageSwitch(content, "handlePlateIcons", L["Enable Page"],
		L["Turns this page's icons on or off."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local header = stack:Header(content, L["Show in"])
	local ROWS = {
		{ "ClassFriendly", L["Friendly class"], L["A class icon beside friendly players' health bars."] },
		{ "ClassEnemy", L["Enemy class"], L["A class icon beside enemy players' health bars."] },
		{ "RoleTank", L["Tanks"], L["A role icon beside your group's tanks' health bars."] },
		{ "RoleHealer", L["Healers"], L["A role icon beside your group's healers' health bars."] },
		{ "RoleDamager", L["Damage"], L["A role icon beside your group's damage dealers' health bars."] },
	}
	local rows = { opts = { anyFight = true }, underHeader = true }
	for _, row in ipairs(ROWS) do
		local always = ALWAYS_KEY[row[1]]
		rows[#rows + 1] = { key = ROW_KEY[row[1]], label = IconText(row[1]) .. row[2], tip = row[3],
			alwaysKey = always,
			alwaysOn = function() return ns.GetDB()[always] end,
			setAlways = function(value) ns.GetDB()[always] = value Changed() end,
			alwaysTip = L["Shows everywhere, in CineMode and out. (The other columns then have nothing to add.)"],
			apply = Changed }
	end
	local lastRow = ns.ShowTable(content, header, rows, L["Nameplate Icons"])
	stack:Continue(lastRow, "label")

	stack:Header(content, L["Look"])
	local size = kit.Slider(content, "plateIconSize", L["Size"], 50, 200, 5, "%d%%", 100, Changed)
	stack:Add(size, "slider")
	kit.GreyUnless(size, function(db) return db.handlePlateIcons end)
	kit.Tooltip(size, L["How big the class and role icons are."])

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Plate Icons", L["Nameplate Icons"])
end

-- The Nameplate Style page's Show in row (Options.lua), as the icons'.
function ns.TargetMarksShowRow(onChange)
	return { key = ROW_KEY.TargetArrow, label = L["Nameplate Style"], alwaysKey = ALWAYS_KEY.TargetArrow,
		tip = L["When the marks and their colors show on the plates."],
		alwaysOn = function() return ns.GetDB()[ALWAYS_KEY.TargetArrow] end,
		setAlways = function(value)
			ns.GetDB()[ALWAYS_KEY.TargetArrow] = value
			if onChange then onChange() end
		end,
		alwaysTip = L["Shows everywhere, in CineMode and out. (The other columns then have nothing to add.)"],
		apply = onChange }
end
