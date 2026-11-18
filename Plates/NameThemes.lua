-- Name themes: a whole look for Name Style's names in one pick, a step
-- under All names (row -> All names -> the name theme -> the game's:
-- NameRowLook.lua). One per main theme, made from its own data
-- (StyleThemes.lua), and a few that stand alone; the Name Style page's old
-- presets are among them (Bold, Subtle; Like the game's names is The
-- game's). db.nameTheme picks one; "main" (to start) the main theme's own.
-- Kept out of the main theme's own settings (a main theme never writes it:
-- a name theme picked by hand stays), only in its Undo.

local _, ns = ...

ns.DEFAULTS.nameTheme = "main"

-- (A color the way to another: the game's reaction colors pulled toward a
-- theme's own, so they keep their meaning in its palette.)
local function Toward(from, to, share)
	return from[1] + (to[1] - from[1]) * share, from[2] + (to[2] - from[2]) * share, from[3] + (to[3] - from[3]) * share
end
local function SetColor(look, setting, r, g, b)
	look[setting .. "R"], look[setting .. "G"], look[setting .. "B"] = r, g, b
end

-- Themes with a glow behind names (in their ornament's color), and the
-- flat modern ones with a dark band.
-- (Glow off in every main theme for now, 2026-11-17: it read as a blob over
-- names and titles. Was fel, void, glade, forge. Lantern keeps its own.)
local GLOW = {}

-- A main theme's names: its small names font (Friz; a slab theme's own, as
-- the themes do for unit frame names), its reaction colors, a grey second
-- line toward its ornament, and its glow or band.
local function FromTheme(theme)
	local s = theme.settings or {}
	local look = { Font = theme.layout == "slab" and s.styleFont or "friz", Hostile = "custom", Neutral = "custom",
		Friendly = "custom", Line2Color = "grey" }
	SetColor(look, "Hostile", Toward({ 1, 0, 0 }, theme.stop or { 1, 0, 0 }, 0.35))
	SetColor(look, "Neutral", Toward({ 1, 1, 0 }, theme.cast or { 1, 1, 0 }, 0.35))
	SetColor(look, "Friendly", Toward({ 0, 1, 0 }, theme.health or { 0, 1, 0 }, 0.45))
	if GLOW[theme.key] and theme.ornament then
		look.Glow = "soft"
		SetColor(look, "Glow", theme.ornament[1], theme.ornament[2], theme.ornament[3])
	elseif theme.layout == "slab" then
		look.Back, look.BackAlpha = "band", 0.55
		SetColor(look, "Back", 0.04, 0.04, 0.05)
	end
	return look
end

-- The themes that stand alone, after the main themes' own.
local OWN = {
	{ key = "bold", name = "Bold", tip = "Colored, with a thin black outline, a little bigger.",
		look = { Outline = 1, Shadow = false, Size = 1.1 } },
	{ key = "subtle", name = "Subtle", tip = "Colored, a little smaller and see-through.",
		look = { Size = 0.9, Alpha = 0.75 } },
	{ key = "storybook", name = "Storybook", tip = "Warm colors in a hand-lettered font, with a soft shadow.",
		look = { Font = "almendra", Shadow = true, ShadowAlpha = 0.8, Hostile = "custom", HostileR = 0.92,
			HostileG = 0.36, HostileB = 0.28, Neutral = "custom", NeutralR = 0.96, NeutralG = 0.82, NeutralB = 0.48,
			Friendly = "custom", FriendlyR = 0.64, FriendlyG = 0.86, FriendlyB = 0.46 } },
	{ key = "subtitle", name = "Subtitle", tip = "White on a soft dark band, like film subtitles. Reads over anything.",
		look = { Colour = "one", ColourR = 1, ColourG = 1, ColourB = 1, Back = "band", BackR = 0, BackG = 0, BackB = 0,
			BackAlpha = 0.55 } },
	{ key = "lantern", name = "Lantern", tip = "A warm glow behind each name, as if lit by a lantern at night.",
		look = { Glow = "soft", GlowR = 1, GlowG = 0.72, GlowB = 0.3 } },
	{ key = "game", name = "The game's", tip = "Names as the game draws them over heads.", look = {} },
}

-- The list (made once the main themes are known): { key, name, tip, look =
-- { setting = value } as NameRowLook's settings, family }.
local list, byKey
local function List()
	if list then return list end
	list, byKey = {}, {}
	for _, info in ipairs(ns.StyleThemeList and ns.StyleThemeList() or {}) do
		local theme = ns.StyleThemeByKey(info.key)
		if theme and theme.key ~= "game" then
			list[#list + 1] = { key = theme.key, name = theme.name, family = theme.key, look = FromTheme(theme) }
		end
	end
	for _, theme in ipairs(OWN) do list[#list + 1] = theme end
	for _, theme in ipairs(list) do byKey[theme.key] = theme end
	return list
end
function ns.NameThemeList() return List() end
function ns.NameThemeByKey(key)
	List()
	return byKey[key]
end

-- The name theme a key gives: "main", the main theme's own (none on the
-- game's look, or with the Style hub off).
local function ThemeOf(key)
	if key == "main" then
		local main = ns.ActiveStyleTheme and ns.ActiveStyleTheme()
		if not main or main.key == "game" then return nil end
		return ns.NameThemeByKey(main.names or main.key)
	end
	return ns.NameThemeByKey(key)
end
-- The name theme in use (nil: none) and its look ({ setting = value }).
function ns.NameThemeNow()
	local db = ns.db
	return ThemeOf(db and db.nameTheme or "main")
end
function ns.NameThemeLook(key)
	local theme
	if key then theme = ThemeOf(key) else theme = ns.NameThemeNow() end
	return theme and theme.look or nil
end

-- D12: a profile on the game's own look keeps the game's names when a main
-- theme comes, as they had: its name theme "game". Once, every profile.
-- fresh: a new install, only marked done.
function ns.MigrateNameTheme(fresh)
	local db = ns.db
	if not db or db.nameThemeGameV1 then return end
	if fresh then
		db.nameThemeGameV1 = true
		return
	end
	local function Move(t)
		if type(t) ~= "table" then return end
		if (t.styleTheme == nil or t.styleTheme == "game") and t.nameTheme == nil then t.nameTheme = "game" end
	end
	Move(db)
	for _, saved in pairs(db.profiles or {}) do
		if type(saved) == "table" then Move(type(saved.settings) == "table" and saved.settings or saved) end
	end
	db.nameThemeGameV1 = true
end
