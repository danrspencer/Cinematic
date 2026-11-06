-- Style themes: a whole look for the addon in one pick, on the Style hub's
-- General page. A theme is settings (written over General's and the pages',
-- so every page changes with it and any of it can still be changed by hand),
-- a palette for our menus (Skin.lua) and art of its own: a grain on panels
-- and an ornament on their corners (Media/make_theme_art.py).
--
-- db.styleTheme names the theme in use, for its palette and art; its settings
-- are ordinary settings once written. Tools/style-lab draws every frame in
-- every theme from this list: run it after changing one.

local ADDON_NAME, ns = ...
local L = ns.L

ns.DEFAULTS.styleTheme = "game"

local ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Themes\\"

-- A health and mana pair, and the rest of what a theme says about bars, the
-- same way in each. health/mana: { r, g, b }. Unit and raid frames, and the
-- personal display.
local function Bars(settings, health, mana, back)
	-- (Raid frames keep their class colors: telling your group apart at a glance
	-- matters more than the theme, and one color made every tile the same.)
	settings.ufHealthColor, settings.prdHealthColor = "custom", "custom"
	settings.ufHealthR, settings.ufHealthG, settings.ufHealthB = health[1], health[2], health[3]
	settings.prdHealthR, settings.prdHealthG, settings.prdHealthB = health[1], health[2], health[3]
	settings.prdManaColor = "custom"
	settings.prdManaR, settings.prdManaG, settings.prdManaB = mana[1], mana[2], mana[3]
	settings.ufBack, settings.prdBack = back, back
	settings.rfBack = back
	return settings
end

-- A panel's color on tooltips and bubbles.
local function Panels(settings, color, alpha)
	settings.tooltipBack, settings.bubblesBack = "custom", "custom"
	settings.tooltipBackR, settings.tooltipBackG, settings.tooltipBackB = color[1], color[2], color[3]
	settings.bubblesBackR, settings.bubblesBackG, settings.bubblesBackB = color[1], color[2], color[3]
	settings.tooltipAlpha, settings.bubblesAlpha = alpha, alpha
	settings.tooltipNames = "class"
	return settings
end

-- Cast bars: normal, channel, can't be stopped, stopped.
local function Casts(settings, cast, channel, locked, stop)
	settings.plateCastR, settings.plateCastG, settings.plateCastB = cast[1], cast[2], cast[3]
	settings.plateCastChannelR, settings.plateCastChannelG, settings.plateCastChannelB = channel[1], channel[2], channel[3]
	settings.plateCastLockedR, settings.plateCastLockedG, settings.plateCastLockedB = locked[1], locked[2], locked[3]
	settings.plateCastStopR, settings.plateCastStopG, settings.plateCastStopB = stop[1], stop[2], stop[3]
	return settings
end

-- The line round everything, and its action buttons' outline.
local function Line(settings, size, color)
	settings.styleBorder, settings.styleBorderSize = "custom", size
	settings.styleBorderR, settings.styleBorderG, settings.styleBorderB = color[1], color[2], color[3]
	settings.abEdge, settings.abEdgeSize = "custom", size
	settings.abEdgeR, settings.abEdgeG, settings.abEdgeB = color[1], color[2], color[3]
	return settings
end

-- Card Vision's big words. Most card styles take the theme's color and font;
-- these keep their own, as they mean something (red for danger) or are a look
-- of their own (the Storybook's lettering).
local CARDS_KEEP = { danger = true, combat = true, respite = true, rare = true, alert = true, death = true,
	victory = true, film = true, storybook = true, arcade = true }
local function CardSettings(theme)
	local list = {}
	if not theme.cardColor then return list end
	for _, style in ipairs(ns.CARD_STYLES or {}) do
		if not CARDS_KEEP[style.id] then
			list[ns.CardStyleKey("R", style.id)] = theme.cardColor[1]
			list[ns.CardStyleKey("G", style.id)] = theme.cardColor[2]
			list[ns.CardStyleKey("B", style.id)] = theme.cardColor[3]
			list[ns.CardStyleKey("Font", style.id)] = theme.cardFont
		end
	end
	return list
end

-- The pages a theme dresses: on with it, whatever the profile has. (The game's
-- theme leaves them as the profile has them.)
local SWITCHES = { "ufStyle", "rfStyle", "prdStyle", "tooltipStyle", "bubblesStyle", "abStyle", "plateCastStyle",
	"questTalkStyled", "questItemStyle", "rollStyle" }

local function Theme(info)
	local s = info.settings
	for _, key in ipairs(SWITCHES) do s[key] = true end
	s.rfOutline = 1 -- (white names on any class's color: pale ones lose them otherwise)
	s.ufNameColor = "theme"
	Bars(s, info.health, info.mana, info.back)
	Panels(s, info.panel, info.panelAlpha)
	Casts(s, info.cast, info.channel, info.locked, info.stop)
	Line(s, info.lineSize, info.line)
	return info
end

local THEMES = {
	{ key = "game", name = "The game's", tip = "Everything as the game draws it. Each Style page's own defaults.",
		swatch = { { 0.10, 0.09, 0.08 }, { 1, 0.82, 0 }, { 0, 0.8, 0 }, { 0, 0.45, 1 } }, settings = {} },
	Theme({
		key = "reel", name = "Silver Screen",
		tip = "Black and silver, like an old film print. Thin lines, narrow lettering, nothing in the way of the picture.",
		swatch = { { 0.05, 0.05, 0.06 }, { 0.86, 0.87, 0.9 }, { 0.55, 0.56, 0.6 }, { 0.94, 0.72, 0.3 } },
		menu = { accent = { 0.9, 0.9, 0.93 }, edge = { 0.52, 0.53, 0.58 }, field = { 0.07, 0.07, 0.08 },
			window = { 0.03, 0.03, 0.035 }, well = { 0, 0, 0 }, knob = { 0.95, 0.95, 0.97 }, thumb = { 0.72, 0.72, 0.76 } },
		grain = "Reel", corner = "Reel", ornament = { 0.86, 0.87, 0.9 }, cornerSize = 26,
		health = { 0.62, 0.64, 0.69 }, mana = { 0.42, 0.48, 0.58 }, back = 0.75,
		panel = { 0.045, 0.045, 0.055 }, panelAlpha = 0.94,
		cast = { 0.94, 0.72, 0.3 }, channel = { 0.72, 0.76, 0.82 }, locked = { 0.45, 0.46, 0.5 }, stop = { 0.8, 0.25, 0.22 },
		line = { 0.6, 0.61, 0.66 }, lineSize = 1,
		cardColor = { 0.95, 0.95, 0.97 }, cardFont = "bebas",
		settings = { styleTexture = "reel", styleFont = "barlow", styleOutline = 0, styleShadow = "on",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "square" },
	}),
	Theme({
		key = "codex", name = "Gilded Codex",
		tip = "An illuminated book: dark vellum, gold leaf and filigree in every corner. The tale of your journey, written as it happens.",
		swatch = { { 0.11, 0.075, 0.05 }, { 0.93, 0.74, 0.34 }, { 0.2, 0.55, 0.32 }, { 0.5, 0.11, 0.1 } },
		menu = { accent = { 0.95, 0.76, 0.36 }, edge = { 0.58, 0.44, 0.22 }, field = { 0.1, 0.07, 0.05 },
			window = { 0.06, 0.04, 0.03 }, well = { 0.03, 0.02, 0.015 }, knob = { 0.98, 0.86, 0.58 },
			thumb = { 0.74, 0.58, 0.32 } },
		grain = "Codex", corner = "Codex", ornament = { 0.93, 0.74, 0.34 }, cornerSize = 34,
		health = { 0.2, 0.58, 0.32 }, mana = { 0.2, 0.36, 0.66 }, back = 0.7,
		panel = { 0.15, 0.1, 0.07 }, panelAlpha = 0.97,
		cast = { 0.93, 0.7, 0.28 }, channel = { 0.42, 0.6, 0.78 }, locked = { 0.5, 0.44, 0.38 }, stop = { 0.72, 0.16, 0.13 },
		line = { 0.68, 0.51, 0.24 }, lineSize = 1,
		cardColor = { 0.96, 0.8, 0.44 }, cardFont = "almendra",
		settings = { styleTexture = "gilt", styleFont = "marcellus", styleOutline = 0, styleShadow = "on",
			questTalkStyle = "parchment", questTalkShadow = "none", rollPanel = "rounded" },
	}),
	Theme({
		key = "forge", name = "Emberforge",
		tip = "Blackened iron, rivets and molten light. Heavy, loud and built to take a hit.",
		swatch = { { 0.09, 0.085, 0.08 }, { 1, 0.5, 0.12 }, { 0.82, 0.24, 0.1 }, { 0.5, 0.48, 0.46 } },
		menu = { accent = { 1, 0.55, 0.16 }, edge = { 0.46, 0.43, 0.4 }, field = { 0.11, 0.105, 0.1 },
			window = { 0.06, 0.055, 0.05 }, well = { 0.025, 0.02, 0.02 }, knob = { 1, 0.74, 0.42 },
			thumb = { 0.66, 0.42, 0.22 } },
		grain = "Forge", corner = "Forge", ornament = { 0.56, 0.53, 0.5 }, cornerSize = 28,
		health = { 0.86, 0.34, 0.1 }, mana = { 0.28, 0.44, 0.62 }, back = 0.8,
		panel = { 0.13, 0.125, 0.12 }, panelAlpha = 0.97,
		cast = { 1, 0.6, 0.12 }, channel = { 0.95, 0.82, 0.4 }, locked = { 0.46, 0.44, 0.42 }, stop = { 0.75, 0.1, 0.06 },
		line = { 0.03, 0.03, 0.03 }, lineSize = 2,
		cardColor = { 1, 0.62, 0.2 }, cardFont = "germania",
		settings = { styleTexture = "forged", styleFont = "germania", styleOutline = 1, styleShadow = "none",
			questTalkStyle = "dark", rollPanel = "flat", rollOutline = 0, abShape = "square" },
	}),
	Theme({
		key = "glade", name = "Moonlit Glade",
		tip = "Night in an old forest: deep teal, soft silver and vines climbing the edges. Quiet and alive.",
		swatch = { { 0.05, 0.11, 0.12 }, { 0.72, 0.9, 0.84 }, { 0.3, 0.72, 0.56 }, { 0.46, 0.42, 0.8 } },
		menu = { accent = { 0.66, 0.92, 0.82 }, edge = { 0.3, 0.47, 0.46 }, field = { 0.05, 0.1, 0.11 },
			window = { 0.03, 0.065, 0.075 }, well = { 0.015, 0.035, 0.04 }, knob = { 0.82, 0.96, 0.9 },
			thumb = { 0.42, 0.62, 0.58 } },
		grain = "Glade", corner = "Glade", ornament = { 0.72, 0.9, 0.84 }, cornerSize = 34,
		health = { 0.3, 0.72, 0.56 }, mana = { 0.46, 0.42, 0.82 }, back = 0.65,
		panel = { 0.055, 0.12, 0.13 }, panelAlpha = 0.93,
		cast = { 0.68, 0.84, 0.92 }, channel = { 0.62, 0.52, 0.9 }, locked = { 0.4, 0.48, 0.5 }, stop = { 0.8, 0.3, 0.4 },
		line = { 0.34, 0.52, 0.5 }, lineSize = 1,
		cardColor = { 0.82, 0.96, 0.9 }, cardFont = "cinzel",
		settings = { styleTexture = "lunar", styleFont = "philosopher", styleOutline = 0, styleShadow = "on",
			questTalkStyle = "dark", rollPanel = "rounded" },
	}),
	Theme({
		key = "rime", name = "Frostbound",
		tip = "Cut ice over cold slate. Crisp lines and a clear head at the top of the world.",
		swatch = { { 0.07, 0.1, 0.14 }, { 0.72, 0.88, 1 }, { 0.32, 0.66, 0.84 }, { 0.82, 0.9, 0.96 } },
		menu = { accent = { 0.66, 0.86, 1 }, edge = { 0.36, 0.48, 0.6 }, field = { 0.07, 0.1, 0.14 },
			window = { 0.04, 0.06, 0.09 }, well = { 0.02, 0.03, 0.05 }, knob = { 0.86, 0.95, 1 },
			thumb = { 0.46, 0.6, 0.74 } },
		grain = "Rime", corner = "Rime", ornament = { 0.72, 0.88, 1 }, cornerSize = 34,
		health = { 0.32, 0.72, 0.8 }, mana = { 0.3, 0.42, 0.9 }, back = 0.7,
		panel = { 0.075, 0.11, 0.155 }, panelAlpha = 0.93,
		cast = { 0.72, 0.9, 1 }, channel = { 0.56, 0.62, 0.95 }, locked = { 0.46, 0.52, 0.58 }, stop = { 0.9, 0.34, 0.4 },
		line = { 0.46, 0.64, 0.8 }, lineSize = 1,
		cardColor = { 0.84, 0.94, 1 }, cardFont = "rajdhani",
		settings = { styleTexture = "rime", styleFont = "rajdhani", styleOutline = 0, styleShadow = "on",
			questTalkStyle = "dark", rollPanel = "flat" },
	}),
}
local BY_KEY = {}
for _, theme in ipairs(THEMES) do BY_KEY[theme.key] = theme end

-- The list as the page shows it: each theme's key, name and tip in the
-- player's language, and its colors.
function ns.StyleThemeList()
	local list = {}
	for i, theme in ipairs(THEMES) do
		list[i] = { key = theme.key, name = L[theme.name], tip = L[theme.tip], swatch = theme.swatch }
	end
	return list
end

-- The theme whose palette and art show now: none with Style off.
local function Active()
	local db = ns.db
	if not (db and db.styleGeneral) then return BY_KEY.game end
	return BY_KEY[db.styleTheme] or BY_KEY.game
end
ns.ActiveStyleTheme = Active

-- A dark panel's color and edge for windows of our own (r, g, b, a tables),
-- and its grain's file: nil with no theme, for the window's own.
function ns.ThemePanel()
	local theme = Active()
	if not theme.panel then return nil end
	local p, e = theme.panel, theme.line
	return { p[1], p[2], p[3], theme.panelAlpha or 1 }, { e[1], e[2], e[3], 1 }, theme.grain and ART .. theme.grain .. "Grain"
end

-- The theme's accent (a name's color) and ornament (the frames' rings): nil
-- with no theme.
function ns.ThemeAccent()
	local menu = Active().menu
	return menu and menu.accent
end
function ns.ThemeRing() return Active().ornament end

-- Our menus' colors (Skin.lua's roles): nil for its own.
function ns.MenuPalette() return Active().menu end
function ns.MenuPaletteKey() return Active().key end

-- A panel's surface, on texture: the theme's grain tiled over it, else plain
-- white (the caller sets the color on it either way).
local WHITE = "Interface\\Buttons\\WHITE8X8"
function ns.DressThemeGrain(texture)
	local grain = Active().grain or false
	-- (Only when it changes: tooltips are dressed each time they show.)
	if texture.themeGrain == grain then return end
	texture.themeGrain = grain
	if grain then
		texture:SetTexture(ART .. grain .. "Grain", "REPEAT", "REPEAT")
		if texture.SetHorizTile then
			texture:SetHorizTile(true)
			texture:SetVertTile(true)
		end
	else
		if texture.SetHorizTile then
			texture:SetHorizTile(false)
			texture:SetVertTile(false)
		end
		texture:SetTexture(WHITE)
	end
end

-- The theme's ornament on the corners of holder (ns.MakeStyleEdges' lines
-- round a panel, marked ornate): a piece each, the top left's art flipped
-- for the others, sitting a little over the panel's edge.
local CORNERS = { { "TOPLEFT", 0, 1, 0, 1, -1, 1 }, { "TOPRIGHT", 1, 0, 0, 1, 1, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0, -1, -1 },
	{ "BOTTOMRIGHT", 1, 0, 1, 0, 1, -1 } }
local CORNER_REACH = 3 -- (how far past the edge, at a size of 32)
-- (A tooltip's size can be secret on Forever: then the theme's own size.)
local function Plain(value)
	if type(value) == "number" and not (issecretvalue and issecretvalue(value)) then return value end
end
function ns.DressThemeCorners(holder, alpha)
	local theme = Active()
	local file = theme.corner
	if not holder.corners then
		if not file then return end
		holder.corners = {}
		for i, spot in ipairs(CORNERS) do
			local piece = holder:CreateTexture(nil, "OVERLAY", nil, 2)
			piece:SetTexCoord(spot[2], spot[3], spot[4], spot[5])
			holder.corners[i] = piece
		end
	end
	local size = theme.cornerSize or 32
	-- (Small on a small panel, clear of its words: a tooltip's a few lines tall.)
	local width, height = Plain(holder:GetWidth()), Plain(holder:GetHeight())
	if width and height and width > 0 and height > 0 then
		size = math.max(14, math.min(size, width * 0.2, height * 0.34))
	end
	local reach = CORNER_REACH * size / 32
	for i, spot in ipairs(CORNERS) do
		local piece = holder.corners[i]
		piece:SetShown(file ~= nil)
		if file then
			local color = theme.ornament or { 1, 1, 1 }
			piece:SetTexture(ART .. file .. "Corner")
			piece:SetVertexColor(color[1], color[2], color[3], alpha or 1)
			piece:SetSize(size, size)
			piece:ClearAllPoints()
			piece:SetPoint(spot[1], holder, spot[1], spot[6] * reach, spot[7] * reach)
		end
	end
end

-- The ornament alone on a frame that's no lines of ours (a window with a
-- backdrop, a card): over it, on a holder of its own.
function ns.ThemeOrnament(frame)
	local holder = frame.themeOrnament
	if not holder then
		if not Active().corner then return end
		holder = CreateFrame("Frame", nil, frame)
		holder:SetAllPoints()
		holder:SetFrameLevel(frame:GetFrameLevel() + 3)
		frame.themeOrnament = holder
	end
	ns.DressThemeCorners(holder, 1)
end

-- A theme's settings, its cards' with them.
local function SettingsOf(theme)
	local list = {}
	for key, value in pairs(theme.settings) do list[key] = value end
	for key, value in pairs(CardSettings(theme)) do list[key] = value end
	return list
end

-- Every setting any theme writes, and every page's shared setting (back on
-- General, so the theme reaches them), each frame's own switched off.
local function ThemeKeys()
	local keys, list = {}, {}
	local function Add(key)
		if not keys[key] then
			keys[key] = true
			list[#list + 1] = key
		end
	end
	for _, theme in ipairs(THEMES) do
		for key in pairs(SettingsOf(theme)) do Add(key) end
	end
	for key in pairs(ns.SHARED_STYLE) do Add(key) end
	for key in pairs(ns.DEFAULTS) do
		if type(key) == "string" and (key:find("^ufOwn_") or key:find("^rfOwn_")) then Add(key) end
	end
	for _, key in ipairs({ "styleTexture", "styleFont", "styleOutline", "styleShadow", "styleBorder", "styleBorderSize",
		"styleBorderR", "styleBorderG", "styleBorderB" }) do
		Add(key)
	end
	return list
end

ns.StyleThemeSettingKeys = ThemeKeys -- (for Tools/offline/check.lua)

-- A setting as a theme has it: its own, else as the profile has it.
local function ThemeValue(key, settings, base)
	local value = settings[key]
	if value == nil then value = base[key] end
	if value == nil then value = ns.DEFAULTS[key] end
	-- (A card style's own, with none in the settings: as the style comes.)
	if value == nil and key:find("^cardLook") then value = "default" end
	return value
end
local function Base() return ns.ResetBase and ns.ResetBase() or ns.DEFAULTS end

-- Everything back on after a pick.
local function ShowTheme()
	if ns.RefreshAllStyles then ns.RefreshAllStyles() end
	if ns.ApplyMenuSkin then ns.ApplyMenuSkin(true) end
end

-- Everything a pick changes, as it is now, and that put back.
function ns.StyleSnapshot()
	local db = ns.GetDB()
	local kept = { styleTheme = db.styleTheme or "game", styleGeneral = db.styleGeneral }
	for _, each in ipairs(ThemeKeys()) do
		kept[each] = db[each]
		if kept[each] == nil then kept[each] = "default" end
	end
	return kept
end
function ns.RestoreStyleSnapshot(kept)
	local db = ns.GetDB()
	for key, value in pairs(kept) do db[key] = value end
	ShowTheme()
end

-- The theme over the settings (what's there kept for Undo). noUndo: leave Undo
-- as it is.
function ns.ApplyStyleTheme(key, noUndo)
	local db = ns.GetDB()
	local theme = BY_KEY[key]
	if not (db and theme) then return end
	local keys = ThemeKeys()
	if not noUndo then db.styleThemeKept = ns.StyleSnapshot() end
	db.styleGeneral = true
	db.styleTheme = key
	local settings, base = SettingsOf(theme), Base()
	for _, each in ipairs(keys) do db[each] = ThemeValue(each, settings, base) end
	ShowTheme()
end

-- The settings as they were before the last pick.
function ns.UndoStyleTheme()
	local db = ns.GetDB()
	local kept = db and db.styleThemeKept
	if type(kept) ~= "table" then return end
	db.styleThemeKept = nil
	ns.RestoreStyleSnapshot(kept)
end

-- Whether a setting's been changed since the theme was picked.
function ns.StyleThemeEdited()
	local db = ns.GetDB()
	local theme = db and BY_KEY[db.styleTheme]
	if not theme then return false end
	local settings, base = SettingsOf(theme), Base()
	for _, key in ipairs(ThemeKeys()) do
		local value, own = ThemeValue(key, settings, base), db[key]
		if own == nil then own = "default" end
		if value == nil then value = "default" end
		if own ~= value then return true end
	end
	return false
end

-- The picker, for the General page: a card for each theme drawn in that
-- theme's own panel, corners, lettering and colors, the one in use outlined.
local CARD_H, CARD_GAP, PER_ROW = 66, 8, 3
-- (Russian, Korean and Chinese names keep the game's font: ours have no such letters.)
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]
local function FontOf(theme)
	return ns.StyleFontFile(theme.cardFont or theme.settings.styleFont) or (_G.GameFontNormal:GetFont())
end

local function MakeCard(parent, theme, width, onPick, Tooltip)
	local card = CreateFrame("Button", nil, parent)
	card:SetSize(width, CARD_H)
	local back = card:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	if theme.grain then
		back:SetTexture(ART .. theme.grain .. "Grain", "REPEAT", "REPEAT")
		if back.SetHorizTile then
			back:SetHorizTile(true)
			back:SetVertTile(true)
		end
		back:SetVertexColor(theme.panel[1], theme.panel[2], theme.panel[3], 1)
	else
		back:SetColorTexture(theme.swatch[1][1], theme.swatch[1][2], theme.swatch[1][3], 1)
	end
	local color = theme.menu and theme.menu.accent or { 1, 0.82, 0 }
	card.edges = ns.MakeStyleEdges(card)
	if theme.corner then
		for i, spot in ipairs(CORNERS) do
			if i == 1 or i == 4 then
				local piece = card:CreateTexture(nil, "ARTWORK")
				piece:SetTexture(ART .. theme.corner .. "Corner")
				piece:SetTexCoord(spot[2], spot[3], spot[4], spot[5])
				piece:SetVertexColor(theme.ornament[1], theme.ornament[2], theme.ornament[3], 0.9)
				piece:SetSize(26, 26)
				piece:SetPoint(spot[1], card, spot[1], spot[6] * 1, spot[7] * 1)
			end
		end
	end
	local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("CENTER", 0, 7)
	name:SetWidth(width - 16)
	if ROMAN then name:SetFont(FontOf(theme), 14, "") end
	name:SetTextColor(color[1], color[2], color[3])
	name:SetText(L[theme.name])
	name.searchSkip = true
	local chips = #theme.swatch - 1
	for i = 2, #theme.swatch do
		local chip = card:CreateTexture(nil, "ARTWORK", nil, 1)
		chip:SetSize(16, 5)
		chip:SetPoint("CENTER", card, "CENTER", (i - 2 - (chips - 1) / 2) * 19, -13)
		local c = theme.swatch[i]
		chip:SetColorTexture(c[1], c[2], c[3], 1)
	end
	local hover = card:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.06)
	Tooltip(card, L[theme.tip])
	card:SetScript("OnClick", function() onPick(theme.key) end)
	function card:Mark(on)
		if on then
			ns.DressStyleEdges(self.edges, 2, color[1], color[2], color[3], 1, false)
		else
			ns.DressStyleEdges(self.edges, 1, 0.3, 0.3, 0.32, 1, false)
		end
	end
	return card
end

-- kit: the page's. changed: a pick's been made. Gives the picker, with its
-- Refresh, for the page's stack.
function ns.MakeThemePicker(kit, parent, width, changed)
	local holder = CreateFrame("Frame", nil, parent)
	local rows = math.ceil(#THEMES / PER_ROW)
	local gridH = rows * CARD_H + (rows - 1) * CARD_GAP
	holder:SetSize(width, gridH + 30)
	local cardW = (width - (PER_ROW - 1) * CARD_GAP) / PER_ROW
	local cards = {}
	local function Pick(key)
		ns.ApplyStyleTheme(key)
		changed()
		kit.Refresh()
	end
	for i, theme in ipairs(THEMES) do
		local card = MakeCard(holder, theme, cardW, Pick, kit.Tooltip)
		local row, column = math.floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
		card:SetPoint("TOPLEFT", holder, "TOPLEFT", column * (cardW + CARD_GAP), -row * (CARD_H + CARD_GAP))
		cards[theme.key] = card
	end
	local status = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(gridH + 8))
	status.searchSkip = true
	local undo = ns.PanelButton(holder)
	undo:SetSize(70, 20)
	undo:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -(gridH + 4))
	undo:SetText(L["Undo"])
	kit.Tooltip(undo, L["Your settings as they were before the last theme you picked."])
	undo:SetScript("OnClick", function()
		ns.UndoStyleTheme()
		changed()
		kit.Refresh()
	end)
	local again = ns.PanelButton(holder)
	again:SetSize(110, 20)
	again:SetPoint("RIGHT", undo, "LEFT", -6, 0)
	again:SetText(L["Reapply theme"])
	kit.Tooltip(again, L["Every setting back as this theme has it. Undo brings your changes back."])
	again:SetScript("OnClick", function()
		local db = ns.GetDB()
		Pick(db and db.styleTheme or "game")
	end)
	function holder:Refresh()
		local db = ns.GetDB()
		local on = db and db.styleGeneral and true or false
		local current = db and BY_KEY[db.styleTheme] or BY_KEY.game
		for key, card in pairs(cards) do
			card:Mark(key == current.key)
			card:SetEnabled(on)
			card:SetAlpha(on and 1 or 0.45)
		end
		local edited = ns.StyleThemeEdited()
		status:SetText(edited and (L["%s, with your changes"]):format(L[current.name]) or L[current.name])
		again:SetShown(edited and on)
		undo:SetShown(on and type(db and db.styleThemeKept) == "table")
	end
	holder.pageSwitch = false
	kit.AddControl(holder)
	return holder
end
