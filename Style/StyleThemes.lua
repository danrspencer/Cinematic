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
ns.DEFAULTS.stylePanel = "square"    -- panels' shape: "square" or one of PANEL_ART's
ns.DEFAULTS.styleBarShape = "square" -- thin bars' shape: "square" or one of BAR_ART's

local ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Themes\\"

-- A health and mana pair, and the rest of what a theme says about bars, the
-- same way in each. health/mana: { r, g, b }. Unit and raid frames, and the
-- personal display.
-- A theme's line as the metal of a unit frame: a strong color pulled toward grey and
-- darkened, or the outline shouts over the bars inside it. A quiet one's left near as it is.
local function Metal(line)
	local top, low = math.max(line[1], line[2], line[3]), math.min(line[1], line[2], line[3])
	local grey = (line[1] + line[2] + line[3]) / 3
	local pull = math.min(0.5, (top - low) * 0.6)
	local out = {}
	for i = 1, 3 do out[i] = (line[i] + (grey - line[i]) * pull) * (1 - pull * 0.5) end
	return out
end

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
	-- (The tooltip's bar too: the game's bright green sits off every palette.)
	settings.tooltipBarColor = "custom"
	settings.tooltipBarR, settings.tooltipBarG, settings.tooltipBarB = health[1], health[2], health[3]
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

-- The line round everything, and its action buttons' outline. (The buttons'
-- always 1 thick: a heavy theme's 2, Runestone's, read chunky on them.)
local function Line(settings, size, color)
	settings.styleBorder, settings.styleBorderSize = "custom", size
	settings.styleBorderR, settings.styleBorderG, settings.styleBorderB = color[1], color[2], color[3]
	settings.abEdge, settings.abEdgeSize = "custom", 1
	settings.abEdgeR, settings.abEdgeG, settings.abEdgeB = color[1], color[2], color[3]
	return settings
end

-- Card Vision's big words. Most card styles take the theme's color and font;
-- these keep their own, as they mean something (red for danger) or are a look
-- of their own (the Storybook's lettering).
-- (Since 2026-11-18 the ones with a meaning keep only their color and take the
-- theme's font, so a theme's cards all match; the looks of their own keep both.)
local CARDS_KEEP = { film = true, storybook = true, arcade = true }
local CARDS_KEEP_COLOR = { danger = true, combat = true, respite = true, rare = true, alert = true, death = true,
	victory = true, triumph = true }
local function CardSettings(theme)
	local list = {}
	if not theme.cardColor then return list end
	for _, style in ipairs(ns.CARD_STYLES or {}) do
		if not CARDS_KEEP[style.id] then
			if not CARDS_KEEP_COLOR[style.id] then
				list[ns.CardStyleKey("R", style.id)] = theme.cardColor[1]
				list[ns.CardStyleKey("G", style.id)] = theme.cardColor[2]
				list[ns.CardStyleKey("B", style.id)] = theme.cardColor[3]
			end
			-- (cardMeaningFont: a plainer one for the meaning cards, Death, Victory,
			-- Danger...: Neon Coast's script read wrong on "YOU DIED", 2026-11-18.)
			list[ns.CardStyleKey("Font", style.id)] = CARDS_KEEP_COLOR[style.id] and theme.cardMeaningFont
				or theme.cardFont
			list[ns.CardStyleKey("Outline", style.id)] = 0
			list[ns.CardStyleKey("Shadow", style.id)] = "on"
		end
	end
	return list
end

-- The pages a theme dresses: on with it, whatever the profile has. (The game's
-- theme leaves them as the profile has them.)
local SWITCHES = { "ufStyle", "rfStyle", "prdStyle", "tooltipStyle", "bubblesStyle", "abStyle", "plateCastStyle",
	"questTalkStyled", "questItemStyle", "rollStyle" }

-- A table and every table in it, copied (a theme of yours is made from one of ours).
local function Copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for key, each in pairs(value) do out[key] = Copy(each) end
	return out
end

local function Theme(info)
	-- (Its plate and name themes: its own, made from it. PlateThemes.lua,
	-- NameThemes.lua.)
	info.plates, info.names = info.plates or info.key, info.names or info.key
	-- (Its settings as written, before what's made from its colors below: a
	-- theme of yours starts from them, with its own colors.)
	info.raw = info.raw or Copy(info.settings)
	local s = info.settings
	for _, key in ipairs(SWITCHES) do s[key] = true end
	-- (A shape of ours: the game's strip behind the target's name was drawn for its
	-- frame art, and floats alone without it. On the Overrides tab, so it can be undone.)
	if s.ufShape and s.ufShape ~= "game" then s.styleOver_unitPartTargetNameBack = "hide" end
	-- (The modern themes: flat and clean, where a stone gryphon at each end of the bar
	-- looks out of place. Also on the Overrides tab.)
	if info.layout == "slab" then s.styleOver_barArt = "hide" end
	-- (Raid frames, one way in every theme. Their tiles are tall, which stretches a
	-- bar texture's bands into shapes, and their names are small on bright class
	-- colors: a smooth fill, dark under the name, in the game's font for small text.)
	-- (A soft shadow, not an outline: at this size an outline reads heavy and cartoony.)
	-- (smallFont: a theme whose own font holds up small, Neon Coast's Outfit, there too.)
	s.rfTexture, s.rfFont, s.rfNameSize, s.rfOutline, s.rfShadow = "tile", info.smallFont or "friz", 1.15, 0, "on"
	s.ufNameColor = "theme"
	-- (Unit names are small too: the themes' thin fonts go faint there.)
	s.ufFont, s.ufOutline, s.ufShadow = info.smallFont or "friz", 0, info.layout == "slab" and "soft" or "on"
	Bars(s, info.health, info.mana, info.back)
	-- (A slab: the name on the bar in the theme's own font, the bar in class colors.)
	-- With a thin black line and nothing else. (darkBars: charcoal, not class colors.)
	if info.layout == "slab" then
		s.ufFont, s.ufNameSize, s.ufOutline = s.styleFont, 1.1, 0
		s.ufBorder, s.ufBorderSize, s.ufBorderR, s.ufBorderG, s.ufBorderB = "custom", 1, 0, 0, 0
		-- (ownBars: the theme's color, a gauge rather than a nameplate.)
		if not (info.darkBars or info.ownBars) then s.ufHealthColor = "class" end
	end
	-- (Bands of light on a texture read as cheap plastic on a bar this big: flat, with
	-- the shape doing the work. The game's frame art keeps the theme's own.)
	if s.ufShape and s.ufShape ~= "game" then s.ufTexture = info.unitBars or "flat" end
	-- (Each bar in the theme's thin line, as the game's frame has them.)
	if s.ufShape and s.ufShape ~= "game" and info.layout ~= "slab" then
		s.ufBorder, s.ufBorderSize = "custom", 2
		local metal = Metal(info.line)
		s.ufBorderR, s.ufBorderG, s.ufBorderB = metal[1], metal[2], metal[3]
	end
	-- (Open: the bars stand alone under the name, with no line round them.)
	if info.layout == "open" then s.ufBorder = "none" end
	Panels(s, info.panel, info.panelAlpha)
	Casts(s, info.cast, info.channel, info.locked, info.stop)
	Line(s, info.lineSize, info.line)
	return info
end

local THEMES = {
	{ key = "game", name = "The game's", tip = "Everything as the game draws it. Each Style page's own defaults.",
		swatch = { { 0.10, 0.09, 0.08 }, { 1, 0.82, 0 }, { 0, 0.8, 0 }, { 0, 0.45, 1 } }, settings = {}, plain = true },
	Theme({
		key = "reel", name = "Silver Screen", unitBars = "brushed",
		tip = "Black and silver, like an old film print. Thin lines, narrow lettering, nothing in the way of the picture.",
		swatch = { { 0.05, 0.05, 0.06 }, { 0.86, 0.87, 0.9 }, { 0.55, 0.56, 0.6 }, { 0.94, 0.72, 0.3 } },
		menu = { accent = { 0.9, 0.9, 0.93 }, edge = { 0.52, 0.53, 0.58 }, field = { 0.07, 0.07, 0.08 },
			window = { 0.03, 0.03, 0.035 }, well = { 0, 0, 0 }, knob = { 0.95, 0.95, 0.97 }, thumb = { 0.72, 0.72, 0.76 } },
		grain = "Reel", ornament = { 0.86, 0.87, 0.9 },
		health = { 0.62, 0.64, 0.69 }, mana = { 0.42, 0.48, 0.58 }, back = 0.75,
		panel = { 0.045, 0.045, 0.055 }, panelAlpha = 0.94,
		cast = { 0.94, 0.72, 0.3 }, channel = { 0.72, 0.76, 0.82 }, locked = { 0.45, 0.46, 0.5 }, stop = { 0.8, 0.25, 0.22 },
		line = { 0.6, 0.61, 0.66 }, lineSize = 1,
		cardColor = { 0.95, 0.95, 0.97 }, cardFont = "bebas",
		settings = { styleTexture = "reel", styleFont = "barlow", styleOutline = 0, styleShadow = "on",
			stylePanel = "frame", styleBarShape = "bevel",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "square", ufShape = "octagon" },
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
			questTalkStyle = "parchment", questTalkShadow = "none", rollPanel = "rounded",
			ufBorder = "game" }, -- (the frame art's its border: a line of ours crosses it)
	}),
	Theme({
		key = "forge", name = "Emberforge", unitBars = "hammered",
		barDepth = { 0, 0, 0, 0.3 },
		tip = "Blackened iron, rivets and molten light. Heavy, loud and built to take a hit.",
		swatch = { { 0.09, 0.085, 0.08 }, { 1, 0.5, 0.12 }, { 0.82, 0.24, 0.1 }, { 0.56, 0.36, 0.22 } },
		menu = { accent = { 1, 0.55, 0.16 }, edge = { 0.56, 0.36, 0.22 }, field = { 0.11, 0.1, 0.09 },
			window = { 0.06, 0.055, 0.05 }, well = { 0.025, 0.02, 0.02 }, knob = { 1, 0.74, 0.42 },
			thumb = { 0.66, 0.42, 0.22 } },
		-- (Its rings hot copper, its lines heated iron: the forge's glow on the metal.)
		grain = "Forge", ornament = { 0.88, 0.47, 0.2 },
		health = { 0.86, 0.34, 0.1 }, mana = { 0.28, 0.44, 0.62 }, back = 0.8,
		panel = { 0.135, 0.115, 0.1 }, panelAlpha = 0.97,
		cast = { 1, 0.6, 0.12 }, channel = { 0.95, 0.82, 0.4 }, locked = { 0.46, 0.44, 0.42 }, stop = { 0.75, 0.1, 0.06 },
		line = { 0.56, 0.36, 0.22 }, lineSize = 2,
		cardColor = { 1, 0.62, 0.2 }, cardFont = "germania",
		settings = { styleTexture = "forged", styleFont = "germania", styleOutline = 0, styleShadow = "on",
			stylePanel = "plate", styleBarShape = "chisel",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "square", ufShape = "shield" },
	}),
	Theme({
		key = "glade", name = "Moonlit Glade", unitBars = "linen",
		tip = "Night in an old forest: deep teal, soft silver and vines climbing the edges. Quiet and alive.",
		swatch = { { 0.05, 0.11, 0.12 }, { 0.22, 0.6, 0.52 }, { 0.3, 0.72, 0.56 }, { 0.46, 0.42, 0.8 } },
		menu = { accent = { 0.34, 0.7, 0.62 }, edge = { 0.1, 0.31, 0.29 }, field = { 0.05, 0.1, 0.11 },
			window = { 0.03, 0.065, 0.075 }, well = { 0.015, 0.035, 0.04 }, knob = { 0.82, 0.96, 0.9 },
			thumb = { 0.18, 0.43, 0.38 } },
		-- (Saturated, not silver: pale, its edges read dry and close to Runestone's.)
		grain = "Glade", ornament = { 0.22, 0.6, 0.52 },
		health = { 0.3, 0.72, 0.56 }, mana = { 0.46, 0.42, 0.82 }, back = 0.65,
		xp = { 0.5, 0.28, 0.98 }, -- (the XP bar, XpBarStyle.lua: a violet of its own; its mana turned read washed out)
		panel = { 0.055, 0.12, 0.13 }, panelAlpha = 0.93,
		cast = { 0.68, 0.84, 0.92 }, channel = { 0.62, 0.52, 0.9 }, locked = { 0.4, 0.48, 0.5 }, stop = { 0.8, 0.3, 0.4 },
		line = { 0.12, 0.36, 0.33 }, lineSize = 1,
		cardColor = { 0.82, 0.96, 0.9 }, cardFont = "cinzel",
		settings = { styleTexture = "lunar", styleFont = "philosopher", styleOutline = 0, styleShadow = "on",
			stylePanel = "leaf", styleBarShape = "soft",
			questTalkStyle = "dark", rollPanel = "flat", ufShape = "petal" },
	}),
	Theme({
		key = "rime", name = "Frostbound", unitBars = "brushed",
		tip = "Cut ice over cold slate. Crisp lines and a clear head at the top of the world.",
		swatch = { { 0.07, 0.1, 0.14 }, { 0.72, 0.88, 1 }, { 0.32, 0.66, 0.84 }, { 0.82, 0.9, 0.96 } },
		menu = { accent = { 0.66, 0.86, 1 }, edge = { 0.36, 0.48, 0.6 }, field = { 0.07, 0.1, 0.14 },
			window = { 0.04, 0.06, 0.09 }, well = { 0.02, 0.03, 0.05 }, knob = { 0.86, 0.95, 1 },
			thumb = { 0.46, 0.6, 0.74 } },
		grain = "Rime", ornament = { 0.72, 0.88, 1 },
		health = { 0.32, 0.72, 0.8 }, mana = { 0.3, 0.42, 0.9 }, back = 0.7,
		panel = { 0.075, 0.11, 0.155 }, panelAlpha = 0.93,
		cast = { 0.72, 0.9, 1 }, channel = { 0.56, 0.62, 0.95 }, locked = { 0.46, 0.52, 0.58 }, stop = { 0.9, 0.34, 0.4 },
		line = { 0.46, 0.64, 0.8 }, lineSize = 1,
		cardColor = { 0.84, 0.94, 1 }, cardFont = "rajdhani",
		settings = { styleTexture = "rime", styleFont = "rajdhani", styleOutline = 0, styleShadow = "on",
			stylePanel = "facet", styleBarShape = "bevel",
			questTalkStyle = "dark", rollPanel = "flat", ufShape = "crystal" },
	}),
	Theme({
		key = "vanguard", name = "Crimson Vanguard", unitBars = "satin",
		tip = "A war banner in motion: blades, cut bars and diamonds in crimson and ivory.",
		swatch = { { 0.07, 0.05, 0.06 }, { 0.86, 0.13, 0.17 }, { 0.93, 0.89, 0.8 }, { 0.3, 0.32, 0.38 } },
		menu = { accent = { 0.95, 0.27, 0.27 }, edge = { 0.5, 0.2, 0.22 }, field = { 0.1, 0.06, 0.07 },
			window = { 0.055, 0.04, 0.045 }, well = { 0.03, 0.02, 0.025 }, knob = { 0.95, 0.9, 0.82 },
			thumb = { 0.62, 0.22, 0.24 } },
		grain = "Reel", ornament = { 0.86, 0.13, 0.17 },
		nameColor = { 0.95, 0.9, 0.82 }, -- (crimson names sink into a dusk sky)
		health = { 0.8, 0.13, 0.17 }, mana = { 0.3, 0.34, 0.44 }, back = 0.8,
		panel = { 0.075, 0.055, 0.065 }, panelAlpha = 0.95,
		cast = { 0.93, 0.89, 0.8 }, channel = { 0.86, 0.3, 0.3 }, locked = { 0.4, 0.38, 0.42 }, stop = { 0.5, 0.05, 0.08 },
		line = { 0.86, 0.13, 0.17 }, lineSize = 1,
		cardColor = { 0.95, 0.9, 0.82 }, cardFont = "bebas",
		settings = { styleTexture = "minimal", styleFont = "rajdhani", styleOutline = 0, styleShadow = "on",
			stylePanel = "blade", styleBarShape = "chisel", ufShape = "diamond",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "square" },
	}),
	Theme({
		key = "hearth", name = "Hearthside", unitBars = "linen",
		tip = "A warm inn at the end of the road: soft round panels, capsule bars and honey light. Nothing has a sharp edge.",
		swatch = { { 0.17, 0.11, 0.08 }, { 0.95, 0.72, 0.38 }, { 0.48, 0.72, 0.26 }, { 0.84, 0.47, 0.34 } },
		menu = { accent = { 0.97, 0.76, 0.44 }, edge = { 0.6, 0.38, 0.2 }, field = { 0.16, 0.11, 0.08 },
			window = { 0.11, 0.075, 0.055 }, well = { 0.07, 0.045, 0.035 }, knob = { 1, 0.86, 0.62 },
			thumb = { 0.66, 0.48, 0.32 } },
		grain = "Glade", ornament = { 0.95, 0.72, 0.38 },
		health = { 0.48, 0.72, 0.26 }, mana = { 0.3, 0.52, 0.84 }, back = 0.7, -- (rich: muted, they read dry)
		panel = { 0.17, 0.115, 0.085 }, panelAlpha = 0.95,
		cast = { 0.95, 0.72, 0.38 }, channel = { 0.48, 0.72, 0.26 }, locked = { 0.5, 0.42, 0.36 }, stop = { 0.84, 0.36, 0.3 },
		line = { 0.68, 0.42, 0.2 }, lineSize = 1,
		cardColor = { 0.98, 0.84, 0.6 }, cardFont = "almendra",
		settings = { styleTexture = "soft", styleFont = "philosopher", styleOutline = 0, styleShadow = "on",
			stylePanel = "round", styleBarShape = "capsule", ufShape = "circle",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "round" },
	}),
	Theme({
		key = "open", name = "Adventurer", unitBars = "soft", layout = "open",
		tip = "Just the hero: a gold-ringed portrait, the name over two slim bars, and nothing round them.",
		swatch = { { 0.08, 0.07, 0.06 }, { 1, 0.82, 0 }, { 0, 0.8, 0 }, { 0, 0.55, 1 } },
		menu = { accent = { 1, 0.82, 0.2 }, edge = { 0.5, 0.4, 0.2 }, field = { 0.09, 0.08, 0.07 },
			window = { 0.05, 0.045, 0.04 }, well = { 0.025, 0.02, 0.02 }, knob = { 1, 0.9, 0.55 },
			thumb = { 0.66, 0.52, 0.24 } },
		grain = "Reel", ornament = { 0.8, 0.65, 0.25 },
		nameColor = { 1, 0.82, 0 }, -- (the game's own gold, as the preview's names)
		health = { 0, 0.8, 0 }, mana = { 0, 0.55, 1 }, back = 0.5,
		panel = { 0.07, 0.06, 0.05 }, panelAlpha = 0.93,
		cast = { 1, 0.7, 0 }, channel = { 0, 0.8, 0 }, locked = { 0.5, 0.5, 0.5 }, stop = { 0.85, 0.2, 0.15 },
		line = { 0.55, 0.45, 0.25 }, lineSize = 1,
		cardColor = { 1, 0.86, 0.4 }, cardFont = "cinzel",
		settings = { styleTexture = "soft", styleFont = "friz", styleOutline = 0, styleShadow = "on",
			styleBarShape = "soft", -- (gently rounded ends: everything else on it is round)
			ufShape = "circle", questTalkStyle = "dark", rollPanel = "flat", abShape = "round" },
	}),
	Theme({
		key = "cathedral", name = "Cathedral", unitBars = "satin",
		tip = "Stained glass at dusk: jewel colors behind dark lead, pointed bars and arched windows for portraits.",
		swatch = { { 0.06, 0.06, 0.13 }, { 0.3, 0.42, 0.95 }, { 0.82, 0.17, 0.32 }, { 0.92, 0.72, 0.28 } },
		menu = { accent = { 0.95, 0.76, 0.34 }, edge = { 0.32, 0.34, 0.58 }, field = { 0.07, 0.07, 0.15 },
			window = { 0.045, 0.045, 0.1 }, well = { 0.025, 0.025, 0.06 }, knob = { 0.98, 0.85, 0.55 },
			thumb = { 0.42, 0.44, 0.74 } },
		grain = "Glade", ornament = { 0.92, 0.72, 0.28 },
		health = { 0.68, 0.12, 0.28 }, mana = { 0.27, 0.4, 0.95 }, back = 0.8,
		panel = { 0.06, 0.06, 0.14 }, panelAlpha = 0.95,
		cast = { 0.92, 0.72, 0.28 }, channel = { 0.3, 0.42, 0.95 }, locked = { 0.4, 0.4, 0.52 }, stop = { 0.82, 0.17, 0.32 },
		line = { 0.92, 0.72, 0.28 }, lineSize = 1,
		cardColor = { 0.96, 0.8, 0.45 }, cardFont = "cinzel",
		settings = { styleTexture = "glass", styleFont = "marcellus", styleOutline = 0, styleShadow = "on",
			stylePanel = "notch", styleBarShape = "soft", ufShape = "arch",
			questTalkStyle = "dark", rollPanel = "flat" },
	}),
	Theme({
		key = "rune", name = "Runestone", unitBars = "worn",
		tip = "Carved from old rock: heavy cut stone, hexagons and chiseled bars, lit by a faint glow in the runes.",
		swatch = { { 0.13, 0.14, 0.13 }, { 0.42, 0.85, 0.72 }, { 0.5, 0.52, 0.48 }, { 0.7, 0.66, 0.55 } },
		menu = { accent = { 0.5, 0.9, 0.76 }, edge = { 0.42, 0.44, 0.4 }, field = { 0.13, 0.135, 0.125 },
			window = { 0.085, 0.09, 0.085 }, well = { 0.05, 0.055, 0.05 }, knob = { 0.72, 0.95, 0.86 },
			thumb = { 0.48, 0.52, 0.48 } },
		grain = "Forge", ornament = { 0.5, 0.9, 0.76 },
		health = { 0.3, 0.68, 0.56 }, mana = { 0.36, 0.5, 0.68 }, back = 0.8,
		panel = { 0.125, 0.13, 0.12 }, panelAlpha = 0.96,
		cast = { 0.5, 0.9, 0.76 }, channel = { 0.7, 0.66, 0.55 }, locked = { 0.42, 0.44, 0.4 }, stop = { 0.8, 0.3, 0.26 },
		line = { 0.46, 0.48, 0.44 }, lineSize = 2,
		cardColor = { 0.62, 0.95, 0.82 }, cardFont = "germania",
		settings = { styleTexture = "forged", styleFont = "marcellus", styleOutline = 0, styleShadow = "on",
			stylePanel = "chamfer", styleBarShape = "bevel", ufShape = "hex",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "square" },
	}),
	Theme({
		key = "fel", name = "Fel Pact", unitBars = "worn",
		tip = "A warlock's bargain: near black, lit by sickly fel green.",
		swatch = { { 0.03, 0.04, 0.03 }, { 0.42, 0.86, 0.2 }, { 0.46, 0.24, 0.66 }, { 0.16, 0.2, 0.14 } },
		menu = { accent = { 0.56, 0.92, 0.3 }, edge = { 0.2, 0.32, 0.16 }, field = { 0.05, 0.065, 0.045 },
			window = { 0.03, 0.038, 0.028 }, well = { 0.015, 0.02, 0.014 }, knob = { 0.72, 0.95, 0.5 },
			thumb = { 0.26, 0.44, 0.18 } },
		grain = "Forge", ornament = { 0.34, 0.68, 0.17 }, veil = { raid = 0.46, plate = 0.26 },
		nameColor = { 0.74, 0.95, 0.54 },
		health = { 0.3, 0.66, 0.14 }, mana = { 0.46, 0.24, 0.66 }, back = 0.88,
		xp = { 0.44, 0.1, 0.78 }, -- (the XP bar, XpBarStyle.lua: a darker purple; its mana turned came out pink)
		panel = { 0.03, 0.04, 0.028 }, panelAlpha = 0.96,
		cast = { 0.5, 0.9, 0.24 }, channel = { 0.56, 0.3, 0.8 }, locked = { 0.32, 0.36, 0.3 }, stop = { 0.6, 0.12, 0.1 },
		line = { 0.28, 0.56, 0.14 }, lineSize = 1,
		cardColor = { 0.62, 0.95, 0.32 }, cardFont = "germania",
		settings = { styleTexture = "forged", styleFont = "philosopher", styleOutline = 0, styleShadow = "on",
			stylePanel = "sigil", styleBarShape = "chisel", ufShape = "cut",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "square" },
	}),
	Theme({
		key = "void", name = "Void Whisper", unitBars = "satin",
		-- (Its eye behind the portrait, parked for now: portraitBack = "Eye" brings it back,
		-- in place of the connector. Art: make_shape_art.py eye_back.)
		tip = "What shadow priests hear: black, and something violet moving in it, watching from the frames.",
		keepColors = true, barDepth = { 0, 0, 0, 0.7 },
		swatch = { { 0.02, 0.015, 0.035 }, { 0.42, 0.3, 0.66 }, { 0.16, 0.22, 0.46 }, { 0.72, 0.68, 0.82 } },
		menu = { accent = { 0.72, 0.54, 1 }, edge = { 0.26, 0.18, 0.42 }, field = { 0.055, 0.04, 0.09 },
			window = { 0.032, 0.022, 0.058 }, well = { 0.016, 0.01, 0.03 }, knob = { 0.82, 0.74, 0.98 },
			thumb = { 0.36, 0.24, 0.58 } },
		grain = "Reel", ornament = { 0.42, 0.3, 0.66 }, veil = { raid = 0.46, plate = 0.26 },
		nameColor = { 0.78, 0.74, 0.88 },
		health = { 0.4, 0.2, 0.68 }, mana = { 0.14, 0.24, 0.5 }, back = 0.9,
		panel = { 0.02, 0.015, 0.035 }, panelAlpha = 0.96,
		cast = { 0.72, 0.52, 1 }, channel = { 0.38, 0.32, 0.86 }, locked = { 0.3, 0.27, 0.38 }, stop = { 0.5, 0.1, 0.32 },
		line = { 0.26, 0.2, 0.4 }, lineSize = 1,
		cardColor = { 0.8, 0.68, 1 }, cardFont = "cinzel",
		settings = { styleTexture = "lunar", styleFont = "marcellus", styleOutline = 0, styleShadow = "on",
			stylePanel = "veil", styleBarShape = "capsule", ufShape = "circle",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "round" },
	}),
	Theme({
		key = "slate", name = "Slate", unitBars = "satin", layout = "slab",
		barDepth = { 0, 0, 0, 0.3 },
		tip = "Clean type on one flat bar in your class color. No portraits, no ornament, nothing else.",
		swatch = { { 0.085, 0.09, 0.1 }, { 0.74, 0.8, 0.88 }, { 0.36, 0.72, 0.58 }, { 0.3, 0.5, 0.85 } },
		menu = { accent = { 0.78, 0.84, 0.92 }, edge = { 0.3, 0.33, 0.38 }, field = { 0.1, 0.105, 0.115 },
			window = { 0.06, 0.063, 0.07 }, well = { 0.03, 0.032, 0.036 }, knob = { 0.86, 0.9, 0.95 },
			thumb = { 0.42, 0.46, 0.52 } },
		grain = "Reel", ornament = { 0.5, 0.55, 0.62 }, veil = { raid = 0.4, plate = 0.3 },
		nameColor = { 1, 1, 1 },
		health = { 0.36, 0.72, 0.58 }, mana = { 0.3, 0.5, 0.85 }, back = 0.85,
		panel = { 0.085, 0.09, 0.1 }, panelAlpha = 0.92,
		cast = { 0.74, 0.8, 0.88 }, channel = { 0.36, 0.72, 0.58 }, locked = { 0.4, 0.42, 0.46 }, stop = { 0.8, 0.3, 0.3 },
		line = { 0.3, 0.33, 0.38 }, lineSize = 1,
		cardColor = { 0.92, 0.94, 0.97 }, cardFont = "barlow",
		settings = { styleTexture = "satin", styleFont = "barlow", styleOutline = 0, styleShadow = "on",
			stylePanel = "soft", ufShape = "none",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "square" },
	}),
	Theme({
		key = "obsidian", name = "Obsidian", unitBars = "satin", layout = "slab", darkBars = true,
		barDepth = { 0, 0, 0, 0.42 },
		tip = "Black on black. No portraits: flat dark bars and one thin line of cold light.",
		swatch = { { 0.02, 0.025, 0.03 }, { 0.25, 0.85, 0.95 }, { 0.2, 0.72, 0.84 }, { 0.45, 0.4, 0.95 } },
		menu = { accent = { 0.3, 0.88, 0.97 }, edge = { 0.14, 0.32, 0.38 }, field = { 0.04, 0.05, 0.055 },
			window = { 0.022, 0.027, 0.03 }, well = { 0.01, 0.012, 0.015 }, knob = { 0.6, 0.94, 1 },
			thumb = { 0.16, 0.44, 0.5 } },
		grain = "Reel", ornament = { 0.25, 0.85, 0.95 }, veil = { raid = 0.46, plate = 0.26 },
		nameColor = { 1, 1, 1 },
		health = { 0.27, 0.29, 0.32 }, mana = { 0.25, 0.85, 0.95 }, back = 0.8,
		panel = { 0.02, 0.025, 0.03 }, panelAlpha = 0.94,
		cast = { 0.3, 0.88, 0.97 }, channel = { 0.5, 0.45, 0.98 }, locked = { 0.28, 0.32, 0.36 }, stop = { 0.9, 0.25, 0.35 },
		line = { 0.16, 0.5, 0.58 }, lineSize = 1,
		cardColor = { 0.5, 0.92, 1 }, cardFont = "rajdhani",
		settings = { styleTexture = "satin", styleFont = "rajdhani", styleOutline = 0, styleShadow = "on",
			stylePanel = "soft", ufShape = "none",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "square" },
	}),
	Theme({
		key = "carbon", name = "Carbon", unitBars = "brushed", layout = "slab",
		barDepth = { 0, 0, 0, 0.3 },
		tip = "A dash at night: amber gauges on charcoal, a steel line under them, and no portraits.",
		ownBars = true,
		swatch = { { 0.075, 0.075, 0.08 }, { 0.98, 0.68, 0.2 }, { 0.9, 0.6, 0.18 }, { 0.36, 0.5, 0.7 } },
		menu = { accent = { 1, 0.72, 0.26 }, edge = { 0.34, 0.31, 0.26 }, field = { 0.095, 0.095, 0.1 },
			window = { 0.055, 0.055, 0.06 }, well = { 0.028, 0.028, 0.03 }, knob = { 1, 0.84, 0.54 },
			thumb = { 0.52, 0.4, 0.2 } },
		grain = "Forge", ornament = { 0.98, 0.68, 0.2 }, veil = { raid = 0.4, plate = 0.3 },
		nameColor = { 1, 1, 1 },
		health = { 0.9, 0.6, 0.18 }, mana = { 0.42, 0.56, 0.76 }, back = 0.88,
		panel = { 0.075, 0.075, 0.08 }, panelAlpha = 0.94,
		cast = { 1, 0.72, 0.26 }, channel = { 0.5, 0.66, 0.86 }, locked = { 0.36, 0.36, 0.38 }, stop = { 0.85, 0.22, 0.16 },
		line = { 0.4, 0.34, 0.24 }, lineSize = 1,
		cardColor = { 1, 0.74, 0.3 }, cardFont = "bebas",
		settings = { styleTexture = "brushed", styleFont = "rajdhani", styleOutline = 0, styleShadow = "on",
			stylePanel = "soft", ufShape = "none",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "square" },
	}),
	Theme({
		-- (Health bars in Sunset's own colors, Media/make_sunset_art.py: white, so
		-- nothing tints them, and keepColors so white stays white. Plates keep the
		-- game's color on a strip under the bar, PlateHealthStyle.lua. Sleek, not
		-- ornate: one thin line, no corner art, Moonlit Glade's petal portraits,
		-- Outfit on unit frame names.)
		key = "neon", name = "Neon Coast", unitBars = "sunsettall", keepColors = true,
		smallFont = "outfit", barDepth = { 0.12, 0.02, 0.18, 0.2 },
		-- (Names over heads: Outfit Bold in the sunset's colors, each still meaning
		-- what the game's does: coral hostile, gold neutral, mint friendly, sky cyan
		-- for friendly players. No band: it read badly there. NameThemes.lua.)
		-- (Its own damage numbers, Combat Text Style: on with it, in Outfit Bold and
		-- the sunset's colors. CombatTextStyle.lua's ns.ThemeCombatColor.)
		turnsOn = { "combatTextStyle" },
		-- (Its Death card: "wasted", the crime-sandbox picture. alsoSets, so
		-- another theme's pick leaves it as it is.)
		alsoSets = { deathBannerStyle = "wasted" },
		combatText = { hit = { 1, 0.9, 0.95 }, spell = { 1, 0.76, 0.3 }, heal = { 0.36, 0.94, 0.71 },
			crit = { 1, 0.31, 0.6 }, miss = { 0.72, 0.65, 1 } },
		-- (The plates' reaction strip in the same colors: PlateHealthStyle.lua.)
		reaction = { hostile = { 1, 0.31, 0.43 }, neutral = { 1, 0.76, 0.3 }, friendly = { 0.36, 0.94, 0.71 },
			friends = { 0.36, 0.84, 1 } },
		nameLook = { Font = "outfitbold", Hostile = "custom", HostileR = 1, HostileG = 0.31, HostileB = 0.43,
			Neutral = "custom", NeutralR = 1, NeutralG = 0.76, NeutralB = 0.3,
			Friendly = "custom", FriendlyR = 0.36, FriendlyG = 0.94, FriendlyB = 0.71,
			Friends = "custom", FriendsR = 0.36, FriendsG = 0.84, FriendsB = 1, Shadow = true },
		tip = "A beach city at dusk: a blue, magenta and gold sky behind palm trees, under clean modern lettering.",
		swatch = { { 0.09, 0.04, 0.14 }, { 0.23, 0.36, 0.82 }, { 1, 0.18, 0.53 }, { 1, 0.6, 0.24 } },
		menu = { accent = { 1, 0.38, 0.68 }, edge = { 0.44, 0.16, 0.52 }, field = { 0.1, 0.05, 0.14 },
			window = { 0.06, 0.03, 0.09 }, well = { 0.03, 0.015, 0.05 }, knob = { 1, 0.78, 0.36 },
			thumb = { 0.62, 0.26, 0.6 } },
		grain = "Neon", ornament = { 1, 0.5, 0.74 }, veil = { raid = 0.3, plate = 0.2 },
		nameColor = { 1, 0.94, 0.97 },
		health = { 1, 1, 1 }, mana = { 0.2, 0.78, 1 }, back = 0.8,
		xp = { 0.92, 0.22, 0.66 },
		panel = { 0.07, 0.03, 0.1 }, panelAlpha = 0.88,
		cast = { 1, 0.38, 0.68 }, channel = { 0.3, 0.8, 1 }, locked = { 0.5, 0.44, 0.56 }, stop = { 0.95, 0.2, 0.25 },
		line = { 0.46, 0.15, 0.44 }, lineSize = 1, -- (one quiet line: sleek, not a frame)
		cardColor = { 1, 0.86, 0.94 }, cardFont = "damion", -- (script, as the sign on a beach bar)
		cardMeaningFont = "archivoblack", -- (Death, Victory, Danger...: serious and heavy, not script)
		settings = { styleTexture = "sunset", styleFont = "outfit", styleOutline = 0, styleShadow = "on",
			stylePanel = "soft", ufShape = "petal", bubblesFont = "outfit", combatTextFont = "outfitbold",
			questTalkStyle = "dark", rollPanel = "flat", abShape = "round" },
	}),
}
local BY_KEY = {}
for _, theme in ipairs(THEMES) do BY_KEY[theme.key] = theme end

-- ---------------------------------------------------------------------------
-- Themes of yours (Themes tab, under Yours): one of ours to start from, the
-- colors you gave it and the settings you saved into it. Made with Theme()
-- as ours are, under "u:<id>", so a pick, Undo, Reapply and "with your
-- changes" treat it as any theme. For every profile on the account:
-- CinematicDB.styleMyThemes = { nextId, list = { { id, name, base, colors,
-- settings } } }. Plates and names take its starting theme's.
-- ---------------------------------------------------------------------------

local MAX_MINE, MAX_MINE_NAME, MAX_MINE_NOTE = 20, 24, 200
-- (The colors a theme of yours can have, in the editor's order.)
local MINE_COLORS = { "accent", "panel", "line", "ornament", "health", "mana", "cast" }
ns.MY_THEME_COLORS = MINE_COLORS
local MINE = {} -- (made, in the store's order)
local mineDirty, mineVersion = true, 0

local function MineStore(make)
	local saved = _G.CinematicDB
	if type(saved) ~= "table" then return nil end
	local store = saved.styleMyThemes
	if type(store) ~= "table" then
		if not make then return nil end
		store = {}
		saved.styleMyThemes = store
	end
	if type(store.list) ~= "table" then store.list = {} end
	store.nextId = tonumber(store.nextId) or 1
	return store
end

-- A starting theme: one of ours, the game's too (Silver Screen if not).
local function BaseOf(key)
	local base = BY_KEY[key]
	if not base or base.mine then return BY_KEY.reel end
	return base
end

-- A color of ours as one of yours has it: its own, else its starting theme's.
local function BaseColor(base, which)
	if which == "accent" then return base.menu and base.menu.accent or { 1, 0.82, 0 } end
	return base[which]
end

local function Rgb(color)
	if type(color) ~= "table" then return nil end
	local out = {}
	for i = 1, 3 do
		local n = tonumber(color[i])
		if not n then return nil end
		out[i] = math.max(0, math.min(1, n))
	end
	return out
end

local function BuildMine(entry)
	local base = BaseOf(entry.base)
	-- (On the game's: nothing of ours to dress, so no colors, only what you saved
	-- over the game's look. plain: read as the game's wherever that's asked.)
	if base.key == "game" then
		local info = { key = "u:" .. entry.id, id = entry.id, name = entry.name, mine = true, base = "game",
			plain = true, plates = "game", names = "game", swatch = Copy(base.swatch), settings = {}, raw = {} }
		if type(entry.settings) == "table" then
			for key, value in pairs(entry.settings) do info.settings[key] = value end
		end
		return info
	end
	local info = {}
	for key, value in pairs(base) do
		if key ~= "settings" and key ~= "raw" then info[key] = Copy(value) end
	end
	info.settings = Copy(base.raw)
	info.key, info.id, info.name, info.mine, info.base = "u:" .. entry.id, entry.id, entry.name, true, base.key
	info.tip = nil
	local colors = type(entry.colors) == "table" and entry.colors or {}
	local function Pick(which)
		return Rgb(colors[which]) or Copy(BaseColor(base, which))
	end
	if colors.accent then
		info.menu = info.menu or {}
		info.menu.accent = Pick("accent")
		info.nameColor = nil -- (names take the accent you gave it)
	end
	if colors.line then
		info.line = Pick("line")
		if info.menu then info.menu.edge = info.line end
	end
	for _, which in ipairs({ "panel", "ornament", "health", "mana", "cast" }) do
		if colors[which] then info[which] = Pick(which) end
	end
	info.swatch = { Pick("panel"), Pick("accent"), Pick("health"), Pick("mana") }
	Theme(info)
	-- (Then what you saved into it, over what Theme() made.)
	if type(entry.settings) == "table" then
		for key, value in pairs(entry.settings) do info.settings[key] = value end
	end
	return info
end

local function EnsureMine()
	if not mineDirty then return end
	local store = MineStore()
	if _G.CinematicDB == nil then return end -- (not loaded yet: again later)
	for _, theme in ipairs(MINE) do BY_KEY[theme.key] = nil end
	MINE = {}
	for _, entry in ipairs(store and store.list or {}) do
		if type(entry) == "table" and entry.id and type(entry.name) == "string" then
			local ok, theme = pcall(BuildMine, entry)
			if ok and theme then
				MINE[#MINE + 1] = theme
				BY_KEY[theme.key] = theme
			end
		end
	end
	mineDirty = false
	mineVersion = mineVersion + 1
end

local function Find(key)
	EnsureMine()
	return BY_KEY[key]
end
-- Ours, then yours.
local function All()
	EnsureMine()
	local list = {}
	for _, theme in ipairs(THEMES) do list[#list + 1] = theme end
	for _, theme in ipairs(MINE) do list[#list + 1] = theme end
	return list
end
local function EntryOf(key)
	local store = MineStore()
	for at, entry in ipairs(store and store.list or {}) do
		if type(entry) == "table" and "u:" .. tostring(entry.id) == key then return entry, at end
	end
end
-- A theme's name to show: ours in the player's language, yours as you named it.
local function NameOf(theme) return theme.mine and theme.name or L[theme.name] end
local function TipOf(theme)
	if theme.mine then
		-- (Its description, if you wrote one: ns.SetMyStyleThemeNote.)
		local entry = EntryOf(theme.key)
		local note = entry and type(entry.note) == "string" and entry.note ~= "" and entry.note
		return note or L["Your theme, started from %s."]:format(L[BY_KEY[theme.base].name])
	end
	return L[theme.tip]
end
ns.StyleThemeName = NameOf

-- A theme's own data by its key (nil: none such), read only: the Look
-- panels' Start from a theme.
function ns.StyleThemeByKey(key) return Find(key) end
-- Yours, made (the Themes tab's Yours).
function ns.MyStyleThemes()
	EnsureMine()
	return MINE
end

-- The list as the page shows it: each theme's key, name and tip in the
-- player's language, and its colors.
function ns.StyleThemeList()
	local list = {}
	for i, theme in ipairs(THEMES) do
		list[i] = { key = theme.key, name = NameOf(theme), tip = TipOf(theme), swatch = theme.swatch }
	end
	return list
end

-- The theme whose palette and art show now: none with Style off.
local function Active()
	local db = ns.db
	if not (db and db.styleGeneral) then return BY_KEY.game end
	return Find(db.styleTheme) or BY_KEY.game
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
	local theme = Active()
	return theme.nameColor or (theme.menu and theme.menu.accent)
end
function ns.ThemeRing() return Active().ornament end
function ns.ThemeMetal()
	local line = Active().line
	return line and Metal(line) or { 0.5, 0.5, 0.5 }
end
-- A color fuller than a theme's own: its muted bars go chalky on a bar this size.
local function Vivid(color)
	if Active().keepColors then return color end
	local top = math.max(color[1], color[2], color[3])
	local out = {}
	for i = 1, 3 do out[i] = math.max(0, top - (top - color[i]) * 1.35) * math.min(1.2, 0.85 / math.max(top, 0.01)) end
	for i = 1, 3 do out[i] = math.min(1, math.max(out[i], color[i] * 0.8)) end
	return out
end
ns.ThemeVivid = Vivid
-- A texture faded across, from one alpha to another.
function ns.ThemeGradient(texture, r, g, b, from, to)
	texture:SetColorTexture(1, 1, 1, 1)
	if texture.SetGradient and CreateColor then
		texture:SetGradient("HORIZONTAL", CreateColor(r, g, b, from), CreateColor(r, g, b, to))
	elseif texture.SetGradientAlpha then
		texture:SetGradientAlpha("HORIZONTAL", r, g, b, from, r, g, b, to)
	else
		texture:SetColorTexture(r, g, b, (from + to) / 2)
	end
end

-- What a bar's fill fades from, toward its leading edge: so no bar's one color. r, g, b, a.
function ns.ThemeBarDepth()
	local theme = Active()
	local deep = theme.barDepth or theme.panel
	if not deep then return nil end
	return { deep[1], deep[2], deep[3], deep[4] or 0.5 }
end

function ns.ThemeMana()
	local mana = Active().mana
	return mana and Vivid(mana)
end
function ns.ThemeLayout() return Active().layout end

-- Our menus' colors (Skin.lua's roles): nil for its own.
function ns.MenuPalette() return Active().menu end
function ns.MenuPaletteKey()
	-- (One of yours: its colors can change under the same key, so a change repaints.)
	local theme = Active()
	return theme.mine and theme.key .. ":" .. mineVersion or theme.key
end

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

-- Shapes (Media/make_shape_art.py), as ordinary settings: a theme picks them and
-- any can be picked on top of any theme.
local SHAPES = ART .. "Shapes\\"
local PANEL_ART = { round = "Round", chamfer = "Chamfer", blade = "Blade", notch = "Notch", sigil = "Sigil",
	veil = "Veil", plate = "Plate", leaf = "Leaf", facet = "Facet", soft = "Soft",
	frame = "Frame" }
local BAR_ART = { capsule = "Capsule", chisel = "Chisel", soft = "Soft", bevel = "Bevel" }
local PORTRAIT_ART = { hex = "Hex", diamond = "Diamond", arch = "Arch", cut = "Cut", eye = "Eye",
	octagon = "Octagon", shield = "Shield", petal = "Petal", crystal = "Crystal" }
local CLAMP = "CLAMPTOBLACKADDITIONAL"

function ns.ThemePortraitMask(shape)
	return PORTRAIT_ART[shape] and SHAPES .. "Portrait" .. PORTRAIT_ART[shape]
end
-- What cuts a real portrait: the shape a little smaller, on clear, with the mask
-- over the portrait's whole place. (A mask only cuts inside its own rectangle: set
-- smaller than the portrait, its rounded picture's edges poke out past it.)
function ns.ThemePortraitCut(shape)
	if shape == "circle" then return SHAPES .. "PortraitCircleCut" end
	return PORTRAIT_ART[shape] and SHAPES .. "Portrait" .. PORTRAIT_ART[shape] .. "Cut"
end
-- How much bigger than the portrait's place a shape's drawn. A shape narrower than
-- a square cuts into the picture, and the picture can't be moved or shrunk (it's the
-- game's): so the shape grows round it, until only its background's lost.
local PORTRAIT_FIT = { diamond = 1.26, hex = 1.12, crystal = 1.12, cut = 1.03, eye = 1.18, shield = 1.1,
	arch = 1.05, petal = 1.04, octagon = 1.15 }
function ns.ThemePortraitFit(shape) return PORTRAIT_FIT[shape] or 1 end

-- How much of its square a shape leaves empty at the side, at the rows' height.
local PORTRAIT_SIDE = { hex = 0.08, eye = 0.09, shield = 0.06, octagon = 0.05, circle = 0.03, arch = 0.015,
	petal = 0.03, cut = 0.015, diamond = -0.03, crystal = -0.015 }
function ns.ThemePortraitSide(shape) return PORTRAIT_SIDE[shape] or 0 end

-- Where the level's badge sits on each shape: on its ring, as parts of the portrait's
-- width from the outer bottom corner: always on the ring, never off a point.
local PORTRAIT_BADGE = { circle = { 0.16, 0.14 }, square = { 0.04, 0.04 }, octagon = { 0.13, 0.11 }, hex = { 0.17, 0.2 },
	diamond = { 0.2, 0.2 }, shield = { 0.17, 0.16 }, eye = { 0.2, 0.14 }, crystal = { 0.12, 0.2 }, cut = { 0.08, 0.06 },
	arch = { 0.12, 0.14, true }, petal = { 0.19, 0.17, false, 0.06, 0.06 } } -- (true: the top corner, where an arch leaves room)
function ns.ThemeBadgeSpot(shape) return PORTRAIT_BADGE[shape] or PORTRAIT_BADGE.circle end
-- A mask twice a portrait's size, clear in the shape's middle: what's under a picture cut
-- away, so it can't show through as the frame fades.
function ns.ThemePortraitOut(shape)
	if shape == "circle" or shape == "square" then return SHAPES .. "Portrait" .. (shape == "circle" and "Circle" or "Square") .. "Out" end
	return PORTRAIT_ART[shape] and SHAPES .. "Portrait" .. PORTRAIT_ART[shape] .. "Out"
end
-- Art behind a theme's portrait and under its rows (Void Whisper's eye): nil for none.
-- Made round a circle, so for a circle only. Its file, its shape's mask, the mist
-- that drifts in it, and its vessels' glow.
function ns.ThemePortraitBack(shape)
	local back = Active().portraitBack
	if not (back and shape == "circle") then return nil end
	local file = SHAPES .. "PortraitBack" .. back
	return file, file .. "Mask", file .. "Mist", file .. "Veins"
end
-- wear: 1 to 4, the ring worn a different way (its cracks and nicks elsewhere), so
-- frames side by side don't match.
function ns.ThemePortraitRing(shape, wear)
	local art = shape == "circle" and "Circle" or PORTRAIT_ART[shape]
	if not art then return nil end
	return SHAPES .. "Portrait" .. art .. "Ring" .. ((wear and wear > 1) and wear or "")
end
-- Dark inside a shape's edge, and dirt for flat fills: the game's frames are worn, and
-- clean ones look cheap beside them.
function ns.ThemePortraitShade(shape)
	if shape == "circle" then return SHAPES .. "PortraitCircleShade" end
	return PORTRAIT_ART[shape] and SHAPES .. "Portrait" .. PORTRAIT_ART[shape] .. "Shade"
end
ns.THEME_GRIT, ns.THEME_SHEEN, ns.THEME_COLLAR = SHAPES .. "Grit", SHAPES .. "Sheen", SHAPES .. "Collar"
ns.THEME_ROW_SHADOW = SHAPES .. "RowShadow"
-- The dark just inside the minimap's ring (Media/make_shape_art.py's minimap()).
ns.THEME_MINIMAP_SHADE = SHAPES .. "MinimapRimShade"
-- A square button's frame alone, as a mask (the minimap's calendar: its frame tinted).
ns.THEME_SQUARE_FRAME_MASK = SHAPES .. "SquareFrameMask"
ns.THEME_CELL_CORNER = SHAPES .. "CellCorner"

-- A veil of the theme's panel color over a bar's fill, under its words: raid tiles'
-- bright class colors and the plates' reds drawn into the theme, whatever color the
-- game gives them (often not one an addon can read). kind: "raid" or "plate"; nil
-- takes it off.
local veils = setmetatable({}, { __mode = "k" })
local VEIL = { raid = 0.34, plate = 0.2 }
function ns.DressThemeVeil(bar, kind)
	local theme = Active()
	local veil = veils[bar]
	local fill = bar:GetStatusBarTexture()
	if not (kind and theme.panel and fill) then
		if veil then veil:Hide() end
		return
	end
	if not veil then
		veil = bar:CreateTexture()
		veils[bar] = veil
	end
	local layer, sub = fill:GetDrawLayer()
	veil:SetDrawLayer(layer or "ARTWORK", math.min(7, (sub or 0) + 1))
	veil:ClearAllPoints()
	veil:SetAllPoints(fill)
	local p = theme.panel
	veil:SetColorTexture(p[1], p[2], p[3], (theme.veil and theme.veil[kind]) or VEIL[kind])
	veil:Show()
end

-- The panel shape in use (nil: plain rectangles).
local function PanelShape()
	local db = ns.db
	return db and db.styleGeneral and PANEL_ART[db.stylePanel] and db.stylePanel or nil
end
ns.ThemePanelShape = PanelShape

-- A bubble's tail to go with a panel's line: its fill and the line down its sides.
-- thin: for a line of one, as a shaped panel's is two.
function ns.ThemeTailArt(thin)
	return SHAPES .. "Tail", SHAPES .. (thin and "TailEdgeThin" or "TailEdge")
end

-- A shaped panel on frame: nine pieces of the shape's art (corners kept their
-- size, the rest stretched), its fill then its line, as textures of frame's
-- own at the back, so whatever frame draws stays on top.
local CORNER = 16
local CUTS = { { 0, 0.25 }, { 0.25, 0.75 }, { 0.75, 1 } }

-- Off the pixel grid: left on it, the game samples drawn art point by point
-- and every curve and slant comes out in steps. For any shaped art or mask.
function ns.ThemeNoSnap(texture)
	if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
	if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end
local function MakePieces(frame, sub)
	local pieces = {}
	for row = 1, 3 do
		for column = 1, 3 do
			local piece = frame:CreateTexture(nil, "BACKGROUND", nil, sub)
			piece:SetTexCoord(CUTS[column][1], CUTS[column][2], CUTS[row][1], CUTS[row][2])
			ns.ThemeNoSnap(piece)
			pieces[#pieces + 1] = piece
		end
	end
	local tl, top, tr, left, mid, right, bl, bottom, br = unpack(pieces)
	-- (frame.themeSliceOut: how far past frame it reaches, for words that sit
	-- close to frame's edge and would run into a cut corner.)
	local out = frame.themeSliceOut or 0
	tl:SetPoint("TOPLEFT", -out, out)
	tr:SetPoint("TOPRIGHT", out, out)
	bl:SetPoint("BOTTOMLEFT", -out, -out)
	br:SetPoint("BOTTOMRIGHT", out, -out)
	-- (frame.themeSliceCorner: smaller corners, for a panel too short for these.)
	local corner = frame.themeSliceCorner or CORNER
	for _, piece in ipairs({ tl, tr, bl, br }) do piece:SetSize(corner, corner) end
	local function Between(piece, a, aPoint, b, bPoint)
		piece:SetPoint("TOPLEFT", a, aPoint)
		piece:SetPoint("BOTTOMRIGHT", b, bPoint)
	end
	Between(top, tl, "TOPRIGHT", tr, "BOTTOMLEFT")
	Between(left, tl, "BOTTOMLEFT", bl, "TOPRIGHT")
	Between(mid, tl, "BOTTOMRIGHT", br, "TOPLEFT")
	Between(right, tr, "BOTTOMLEFT", br, "TOPRIGHT")
	Between(bottom, bl, "TOPRIGHT", br, "BOTTOMLEFT")
	return pieces
end

function ns.HideThemeSlice(frame)
	local slice = frame.themeSlice
	if not slice then return end
	for _, piece in ipairs(slice.fill) do piece:Hide() end
	for _, piece in ipairs(slice.edge) do piece:Hide() end
end

-- Gives whether it's shaped (false: draw the plain panel). shape: this one, not
-- the setting's (a theme's card on the picker).
function ns.DressThemeSlice(frame, r, g, b, a, er, eg, eb, ea, shape)
	shape = shape or PanelShape()
	if not (shape and PANEL_ART[shape]) then
		ns.HideThemeSlice(frame)
		return false
	end
	local slice = frame.themeSlice
	if not slice then
		slice = { fill = MakePieces(frame, -6), edge = MakePieces(frame, -5) }
		frame.themeSlice = slice
	end
	if slice.shape ~= shape then
		slice.shape = shape
		for _, piece in ipairs(slice.fill) do piece:SetTexture(SHAPES .. "Panel" .. PANEL_ART[shape]) end
		for _, piece in ipairs(slice.edge) do piece:SetTexture(SHAPES .. "Panel" .. PANEL_ART[shape] .. "Edge") end
	end
	for _, piece in ipairs(slice.fill) do
		piece:SetVertexColor(r, g, b, a or 1)
		piece:Show()
	end
	for _, piece in ipairs(slice.edge) do
		piece:SetVertexColor(er, eg, eb, ea or 1)
		piece:Show()
	end
	return true
end

-- A thin bar's shape: a mask over its fill and its dark back, stretched with
-- the bar. Gives whether it's shaped (a straight border can't follow it: the
-- caller leaves that off). skip: this bar keeps its corners (a raid tile, too
-- tall for these).
local barShapes = setmetatable({}, { __mode = "k" })
-- Textures over a shaped bar, cut to its shape: nil-safe, and taken off with it.
function ns.MaskBarExtras(bar, shaped, list)
	local state = barShapes[bar]
	if not (state and state.mask) then return end
	state.extras = state.extras or {}
	for _, texture in ipairs(list) do
		if shaped and not state.extras[texture] then
			texture:AddMaskTexture(state.mask)
			state.extras[texture] = true
		elseif state.extras[texture] and not shaped then
			texture:RemoveMaskTexture(state.mask)
			state.extras[texture] = nil
		end
	end
end

-- (rect: the frame the shape's cut to, if not the bar: see UnitStyle's DressSkin.
-- gap: that much off its top, so a bar right under another stands apart from it.)
-- shape: a shape of its own ("bevel"...; a plate theme's) in place of
-- General's.
function ns.DressBarShape(bar, back, skip, rect, gap, shape)
	local db = ns.db
	local art
	if not skip then
		if shape ~= nil then
			art = BAR_ART[shape]
		else
			art = db and db.styleGeneral and BAR_ART[db.styleBarShape] or nil
		end
	end
	local state = barShapes[bar]
	if not (art or state) then return false end
	if not state then
		state = {}
		barShapes[bar] = state
	end
	local fill = bar:GetStatusBarTexture()
	if state.fill and (state.fill ~= fill or not art) then
		state.fill:RemoveMaskTexture(state.mask)
		for _, mask in ipairs(state.gameMasks or {}) do state.fill:AddMaskTexture(mask) end
		state.gameMasks = nil
		state.fill = nil
	end
	if state.backOn and not art then
		back:RemoveMaskTexture(state.backMask)
		state.backOn = nil
	end
	if not art then return false end
	if not state.mask then
		state.mask = bar:CreateMaskTexture()
		state.mask.cineBarShape = true -- (ours: UnitStyle's StripMasks leaves it on)
		state.mask:SetAllPoints(bar)
		ns.ThemeNoSnap(state.mask)
		state.backMask = back:GetParent():CreateMaskTexture()
		state.backMask:SetAllPoints(back)
		ns.ThemeNoSnap(state.backMask)
	end
	local file = SHAPES .. "Bar" .. art
	state.mask:SetTexture(file, CLAMP, CLAMP)
	state.backMask:SetTexture(file, CLAMP, CLAMP)
	if rect and (state.rect ~= rect or state.gap ~= gap) then
		state.rect, state.gap = rect, gap
		for _, mask in ipairs({ state.mask, state.backMask }) do
			mask:ClearAllPoints()
			mask:SetPoint("TOPLEFT", rect, "TOPLEFT", 0, -(gap or 0))
			mask:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT")
		end
	end
	if fill and not state.fill then
		-- (The game's own rounding off first: it'd keep the fill's ends round, inside ours.)
		state.gameMasks = {}
		local count = fill.GetNumMaskTextures and fill:GetNumMaskTextures() or 0
		for i = (type(count) == "number" and count or 0), 1, -1 do
			local mask = fill:GetMaskTexture(i)
			if mask then
				state.gameMasks[#state.gameMasks + 1] = mask
				fill:RemoveMaskTexture(mask)
			end
		end
		fill:AddMaskTexture(state.mask)
		state.fill = fill
	end
	if not state.backOn then
		back:AddMaskTexture(state.backMask)
		state.backOn = true
	end
	return true
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
			ns.ThemeNoSnap(piece)
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

-- What the theme in use gives a setting (nil: nothing, it's General's or yours).
function ns.ThemeSetting(key)
	local theme = Active()
	if theme.key == "game" then return nil end
	return SettingsOf(theme)[key]
end

-- The parts a theme reaches (General's Pages tab: a switch each,
-- styleThemeReach<part>, on to start). A part switched off is left alone
-- by a pick: its settings aren't written, Reapply and the "with your
-- changes" line ignore them, and plates and names keep the theme they had.
ns.THEME_PARTS = { "Frames", "Panels", "Bars", "Plates", "Names", "Casts", "Visions" }
for _, part in ipairs(ns.THEME_PARTS) do ns.DEFAULTS["styleThemeReach" .. part] = true end
-- (A setting's part by its key; nil: General's own, always reached.)
local PART_PATTERNS = {
	{ "^uf", "Frames" }, { "^rf", "Frames" }, { "^prd", "Frames" }, { "^styleOver_unitPart", "Frames" },
	{ "^tooltip", "Panels" }, { "^bubbles", "Panels" },
	{ "^ab", "Bars" }, { "^styleOver_barArt", "Bars" },
	{ "^plateCast", "Casts" },
	{ "^card", "Visions" }, { "^deathBanner", "Visions" }, { "^questTalk", "Visions" }, { "^questItem", "Visions" }, { "^roll", "Visions" },
	{ "^emote", "Visions" }, { "^damageVision", "Visions" }, { "^visionStyle", "Visions" },
}
local partOf = {}
function ns.ThemePartOf(key)
	local part = partOf[key]
	if part == nil then
		part = false
		for _, each in ipairs(PART_PATTERNS) do
			if key:find(each[1]) then
				part = each[2]
				break
			end
		end
		partOf[key] = part
	end
	return part or nil
end
local function Reached(key, db)
	local part = ns.ThemePartOf(key)
	return not part or (db or ns.GetDB())["styleThemeReach" .. part] ~= false
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
	for _, theme in ipairs(All()) do
		for key in pairs(SettingsOf(theme)) do Add(key) end
	end
	for key in pairs(ns.SHARED_STYLE) do Add(key) end
	for key in pairs(ns.DEFAULTS) do
		if type(key) == "string" and (key:find("^ufOwn_") or key:find("^rfOwn_")) then Add(key) end
	end
	for _, key in ipairs({ "stylePanel", "styleBarShape", "styleTexture", "styleFont", "styleOutline", "styleShadow", "styleBorder", "styleBorderSize",
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
	-- (Each step's time in the log when the whole is slow: a pick's hitch.)
	local started = debugprofilestop()
	local marks = {}
	local function Step(name, run)
		if not run then return end
		local at = debugprofilestop()
		run()
		marks[#marks + 1] = ("%s %.0f"):format(name, debugprofilestop() - at)
	end
	Step("styles", ns.RefreshAllStyles)
	Step("menu skin", ns.ApplyMenuSkin and function() ns.ApplyMenuSkin(true) end)
	Step("unit parts", ns.ApplyUnitFrameParts) -- (a theme's overrides)
	Step("bar art", ns.ApplyBarArtOverride)
	local total = debugprofilestop() - started
	if total > 20 then ns.Log("style", ("theme shown: %.0f ms (%s)"):format(total, table.concat(marks, ", "))) end
	-- (And the work left for the next frame: the recolor, the tracker, the settings page.)
	local nextAt = debugprofilestop()
	C_Timer.After(0, function()
		local gap = debugprofilestop() - nextAt
		if gap > 50 then ns.Log("style", ("theme shown: next frame came %.0f ms later"):format(gap)) end
	end)
end

-- Everything a pick changes, as it is now, and that put back.
function ns.StyleSnapshot()
	local db = ns.GetDB()
	local kept = { styleTheme = db.styleTheme or "game", styleGeneral = db.styleGeneral,
		-- (The plate and name themes: never written by a pick, but put back by
		-- Undo with the rest. PlateThemes.lua, NameThemes.lua.)
		plateTheme = db.plateTheme or "main", nameTheme = db.nameTheme or "main" }
	for _, each in ipairs(ThemeKeys()) do
		kept[each] = db[each]
		if kept[each] == nil then kept[each] = "default" end
	end
	-- (And the pages a theme turns on, for Undo: TurnsOnKeys.)
	for _, theme in ipairs(All()) do
		for _, each in ipairs(theme.turnsOn or {}) do
			kept[each] = db[each]
			if kept[each] == nil then kept[each] = "default" end
		end
		for each in pairs(theme.alsoSets or {}) do
			kept[each] = db[each]
			if kept[each] == nil then kept[each] = ns.DEFAULTS[each] end
		end
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
-- (A theme moves and sizes parts of the game's frames, which can't be done in a fight: it'd
-- come out half done. Gives whether it's clear to go.)
local function OutOfFights()
	if not InCombatLockdown() then return true end
	ns.Print(L["Style themes can't be changed in a fight."])
	return false
end

function ns.ApplyStyleTheme(key, noUndo)
	if not OutOfFights() then return false end
	local db = ns.GetDB()
	local theme = Find(key)
	if not (db and theme) then return end
	local keys = ThemeKeys()
	if not noUndo then db.styleThemeKept = ns.StyleSnapshot() end
	-- (Plates and names switched off on the Pages tab while they follow the
	-- main theme: kept on the theme they had, picked for them.)
	local before = Find(db.styleTheme or "game") or BY_KEY.game
	if db.styleThemeReachNames == false and (db.nameTheme or "main") == "main" then
		db.nameTheme = before.key == "game" and "game" or before.names
	end
	if db.styleThemeReachPlates == false and (db.plateTheme or "main") == "main" then
		db.plateTheme = before.key == "game" and "game" or before.plates
	end
	db.styleGeneral = true
	db.styleTheme = key
	local settings, base = SettingsOf(theme), Base()
	for _, each in ipairs(keys) do
		if Reached(each, db) then db[each] = ThemeValue(each, settings, base) end
	end
	-- (turnsOn: pages this theme switches on, Neon Coast's Combat Text Style. Kept
	-- out of its settings, so another theme's pick never switches them off: one
	-- you'd turned on yourself stays. Undo puts them back, StyleSnapshot.)
	for _, each in ipairs(theme.turnsOn or {}) do
		if Reached(each, db) then db[each] = true end
	end
	-- (alsoSets: the same, with a value: Neon Coast's "wasted" Death card. Words
	-- of your own on it are kept.)
	for each, value in pairs(theme.alsoSets or {}) do
		if Reached(each, db) and not (each == "deathBannerStyle" and db[each] == "custom") then db[each] = value end
	end
	ShowTheme()
	return true
end

-- The settings as they were before the last pick.
function ns.UndoStyleTheme()
	if not OutOfFights() then return end
	local db = ns.GetDB()
	local kept = db and db.styleThemeKept
	if type(kept) ~= "table" then return end
	db.styleThemeKept = nil
	ns.RestoreStyleSnapshot(kept)
end

-- Whether a setting's been changed since the theme was picked.
function ns.StyleThemeEdited()
	local db = ns.GetDB()
	local theme = db and Find(db.styleTheme)
	if not theme then return false end
	local settings, base = SettingsOf(theme), Base()
	for _, key in ipairs(ThemeKeys()) do
		-- (A part switched off on the Pages tab: not the theme's to judge.)
		if Reached(key, db) then
			local value, own = ThemeValue(key, settings, base), db[key]
			if own == nil then own = "default" end
			if value == nil then value = "default" end
			if own ~= value then return true end
		end
	end
	return false
end

-- Your changes over a theme, as setting = value (what "with your changes" means).
local function EditsOver(theme)
	local db = ns.GetDB()
	local edits = {}
	if not (db and theme) then return edits end
	local settings, base = SettingsOf(theme), Base()
	for _, key in ipairs(ThemeKeys()) do
		if Reached(key, db) then
			local value, own = ThemeValue(key, settings, base), db[key]
			if own ~= nil and own ~= value then edits[key] = own end
		end
	end
	return edits
end

local function MineChanged()
	mineDirty = true
	EnsureMine()
end
ns.MyStyleThemesChanged = MineChanged -- (the store changed from outside: Tools/offline/check.lua)

-- One of yours changed (its colors, where it started): made again and, the
-- one in use, shown again with any changes you'd made on top kept.
local function Remade(key, change)
	local db = ns.GetDB()
	local using = db and db.styleGeneral and db.styleTheme == key
	local edits = using and EditsOver(Find(key))
	change()
	MineChanged()
	if using and Find(key) then
		ns.ApplyStyleTheme(key, true)
		for each, value in pairs(edits) do db[each] = value end
		ShowTheme()
	end
end

-- A new theme of yours, from another (ours or yours): name, or one made up;
-- withEdits: your changes over it now go in too. Gives its key, or nil and why.
function ns.AddMyStyleTheme(fromKey, name, withEdits)
	if not OutOfFights() then return nil end
	local store = MineStore(true)
	if not store then return nil end
	if #store.list >= MAX_MINE then
		return nil, L["You have %d themes of your own already: delete one to add another."]:format(MAX_MINE)
	end
	local from = Find(fromKey) or BY_KEY.reel
	local fromEntry = from.mine and EntryOf(from.key)
	local entry = { id = store.nextId, base = BaseOf(from.mine and from.base or from.key).key,
		colors = fromEntry and Copy(fromEntry.colors) or {},
		settings = fromEntry and Copy(fromEntry.settings) or {} }
	store.nextId = store.nextId + 1
	if withEdits then
		for key, value in pairs(EditsOver(from)) do entry.settings[key] = value end
	end
	name = type(name) == "string" and name:gsub("|", ""):match("^%s*(.-)%s*$") or ""
	if name == "" then name = L["My theme %d"]:format(#store.list + 1) end
	entry.name = name:sub(1, MAX_MINE_NAME)
	store.list[#store.list + 1] = entry
	MineChanged()
	return "u:" .. entry.id
end

-- Your changes over the theme of yours in use, saved into it.
function ns.SaveMyStyleTheme()
	local db = ns.GetDB()
	local entry = db and EntryOf(db.styleTheme)
	if not entry then return end
	local edits = EditsOver(Find(db.styleTheme))
	ns.BackupMyStyleTheme(db.styleTheme, "save") -- (the saved version it replaces)
	entry.settings = type(entry.settings) == "table" and entry.settings or {}
	for key, value in pairs(edits) do entry.settings[key] = value end
	MineChanged()
end

function ns.RenameMyStyleTheme(key, name)
	local entry = EntryOf(key)
	name = type(name) == "string" and name:gsub("|", ""):match("^%s*(.-)%s*$") or ""
	if not entry or name == "" then return false end
	entry.name = name:sub(1, MAX_MINE_NAME)
	MineChanged()
	return true
end

-- A line on what one of yours is for (empty: none, its starting theme said instead).
function ns.SetMyStyleThemeNote(key, text)
	local entry = EntryOf(key)
	if not entry then return end
	text = type(text) == "string" and text:gsub("[%c|]", ""):match("^%s*(.-)%s*$") or ""
	entry.note = text ~= "" and text:sub(1, MAX_MINE_NOTE) or nil
	MineChanged()
end
function ns.MyStyleThemeNote(key)
	local entry = EntryOf(key)
	return entry and entry.note or nil
end

-- ---------------------------------------------------------------------------
-- Backups of yours, for the account as the themes are: a copy (its name,
-- start, colors, settings and description) just before Save changes and
-- Delete, and once a day at login when one has changed (Backups.lua's Daily,
-- as for profiles, with its keep count). CinematicDB.styleThemeBackups[id],
-- newest first; a deleted one's go to CinematicDB.styleThemesDeleted for 30
-- days. Restoring adds it as a new theme of yours; the one it came from stays.
-- ---------------------------------------------------------------------------
do
	local DELETED_DAYS, DAY = 30, 24 * 60 * 60
	local function Store(name)
		local saved = _G.CinematicDB
		if type(saved) ~= "table" then return nil end
		if type(saved[name]) ~= "table" then saved[name] = {} end
		return saved[name]
	end
	local function Keep() return ns.BackupKeep and ns.BackupKeep() or 10 end
	local function Taken(entry)
		return { name = entry.name, base = entry.base, note = entry.note,
			colors = Copy(type(entry.colors) == "table" and entry.colors or {}),
			settings = Copy(type(entry.settings) == "table" and entry.settings or {}) }
	end
	local function Same(a, b)
		if type(a) ~= "table" or type(b) ~= "table" then return a == b end
		for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
		for k in pairs(b) do if a[k] == nil then return false end end
		return true
	end

	-- why: "save", "delete" or "daily". None when it's the same as its newest.
	function ns.BackupMyStyleTheme(key, why)
		local entry = EntryOf(key)
		local store = entry and Store("styleThemeBackups")
		if not store then return end
		local id = tostring(entry.id)
		local list = store[id] or {}
		local copy = Taken(entry)
		if list[1] and Same(list[1].theme, copy) then return end
		table.insert(list, 1, { time = time(), version = ns.Version and ns.Version() or "?", why = why, theme = copy })
		for i = #list, Keep() + 1, -1 do list[i] = nil end
		store[id] = list
	end
	-- Just before Delete: its last copy, and the lot kept as a deleted theme's.
	function ns.BackupDeletedStyleTheme(key)
		local entry = EntryOf(key)
		if not entry then return end
		ns.BackupMyStyleTheme(key, "delete")
		local store, id = Store("styleThemeBackups"), tostring(entry.id)
		local list = store and store[id]
		if not (list and list[1]) then return end
		store[id] = nil
		table.insert(Store("styleThemesDeleted"), 1, { name = entry.name, time = time(), backups = list })
	end

	-- Each of yours with its backups ({ key, name, backups }), then the deleted ones.
	function ns.StyleThemeBackups()
		local out, store = {}, Store("styleThemeBackups") or {}
		for _, theme in ipairs(ns.MyStyleThemes()) do
			out[#out + 1] = { key = theme.key, name = theme.name, backups = store[tostring(theme.id)] or {} }
		end
		return out, Store("styleThemesDeleted") or {}
	end
	ns.STYLE_THEME_DELETED_DAYS = DELETED_DAYS

	-- A copy as a new theme of yours: its key, or nil and why.
	local function AddCopy(copy, name)
		local key, why = ns.AddMyStyleTheme(BaseOf(copy.base).key, name)
		if not key then return nil, why end
		local entry = EntryOf(key)
		entry.colors, entry.settings, entry.note = Copy(copy.colors or {}), Copy(copy.settings or {}), copy.note
		MineChanged()
		return key
	end
	-- A backup of one of yours (key) as a new theme, named with its day.
	function ns.RestoreStyleThemeBackup(key, i)
		local entry = EntryOf(key)
		local store = entry and Store("styleThemeBackups")
		local backup = store and store[tostring(entry.id)] and store[tostring(entry.id)][i]
		if not backup then return nil end
		return AddCopy(backup.theme, L["%s (%s)"]:format(backup.theme.name or entry.name, date("%Y-%m-%d", backup.time)))
	end
	-- A deleted one back as it was, with its backups.
	function ns.RestoreDeletedStyleTheme(i)
		local deleted = Store("styleThemesDeleted")
		local gone = deleted and deleted[i]
		local backup = gone and gone.backups and gone.backups[1]
		if not backup then return nil end
		local key, why = AddCopy(backup.theme, gone.name)
		if not key then return nil, why end
		table.remove(deleted, i)
		Store("styleThemeBackups")[tostring(EntryOf(key).id)] = gone.backups
		return key
	end

	-- At login (Backups.lua): deleted ones past their time go, and each of
	-- yours gets the day's copy if it's changed since its newest.
	function ns.DailyStyleThemeBackups(daily)
		local deleted = Store("styleThemesDeleted")
		if not deleted then return end
		for i = #deleted, 1, -1 do
			if time() - (deleted[i].time or 0) > DELETED_DAYS * DAY then table.remove(deleted, i) end
		end
		local store, keep = Store("styleThemeBackups"), Keep()
		for _, list in pairs(store) do
			for i = #list, keep + 1, -1 do list[i] = nil end
		end
		if not daily then return end
		local today = date("%Y-%m-%d")
		for _, theme in ipairs(ns.MyStyleThemes()) do
			local list = store[tostring(theme.id)]
			if not (list and list[1] and date("%Y-%m-%d", list[1].time) == today) then
				ns.BackupMyStyleTheme(theme.key, "daily")
			end
		end
	end
end

-- which: one of MY_THEME_COLORS; color nil: back to its starting theme's.
function ns.SetMyStyleThemeColor(key, which, color)
	local entry = EntryOf(key)
	if not entry or not OutOfFights() then return end
	Remade(key, function()
		entry.colors = type(entry.colors) == "table" and entry.colors or {}
		entry.colors[which] = Rgb(color)
	end)
end
function ns.MyStyleThemeColor(key, which)
	local theme, entry = Find(key), EntryOf(key)
	if not (theme and entry) then return nil end
	local own = Rgb(type(entry.colors) == "table" and entry.colors[which])
	return own or BaseColor(BY_KEY[theme.base], which), own ~= nil
end

-- Where one of yours starts: another of ours (its colors and saved settings stay).
function ns.SetMyStyleThemeBase(key, baseKey)
	local entry = EntryOf(key)
	if not entry or not OutOfFights() then return end
	Remade(key, function() entry.base = BaseOf(baseKey).key end)
end

-- Deletes one of yours. In use: its starting theme's palette and art, your
-- settings left as they are.
function ns.DeleteMyStyleTheme(key)
	local entry, at = EntryOf(key)
	if not entry or not OutOfFights() then return end
	local base = BaseOf(entry.base).key
	ns.BackupDeletedStyleTheme(key) -- (kept a while, to bring back: Backups)
	table.remove(MineStore().list, at)
	local db = ns.GetDB()
	if db and db.styleTheme == key then db.styleTheme = base end
	MineChanged()
	ShowTheme()
end

-- Sharing one of yours: "CINET1:" (T for theme), its name, start, colors and
-- settings. Read back as data: only settings a theme can have, plain values.
local SHARE_PREFIX, SHARE_FORMAT = "CINET", 1
function ns.ExportMyStyleTheme(key)
	local entry = EntryOf(key)
	if not entry then return nil end
	return ns.PackShared(SHARE_PREFIX, SHARE_FORMAT, { name = entry.name, base = entry.base,
		colors = entry.colors, settings = entry.settings, note = entry.note,
		who = UnitName and UnitName("player") or nil })
end
-- Any theme, ours too, as the same line. The one in use goes with your
-- changes over it (as a profile's Export gives it as it is now).
function ns.ExportStyleTheme(key)
	local theme = Find(key)
	if not theme then return nil end
	local db = ns.GetDB()
	local using = db and db.styleGeneral and db.styleTheme == key
	local entry = theme.mine and EntryOf(key)
	local settings = entry and Copy(type(entry.settings) == "table" and entry.settings or {}) or {}
	if using then
		for each, value in pairs(EditsOver(theme)) do settings[each] = value end
	end
	return ns.PackShared(SHARE_PREFIX, SHARE_FORMAT, { name = NameOf(theme),
		base = entry and entry.base or theme.key, colors = entry and entry.colors or {}, settings = settings,
		note = entry and entry.note or nil, who = UnitName and UnitName("player") or nil })
end
local SHARE_WHY = { empty = "", newer = "This theme is from a newer Cinematic: update it to add this one.",
	other = "That isn't a theme (they start CINET1:).", broken = "That isn't a whole theme: copy it again, all of it." }
function ns.ReadSharedStyleTheme(text)
	local data, why = ns.UnpackShared(SHARE_PREFIX, SHARE_FORMAT, text)
	if type(data) ~= "table" then return nil, L[SHARE_WHY[why] or SHARE_WHY.broken] end
	local name = type(data.name) == "string" and data.name:gsub("[%c|]", ""):match("^%s*(.-)%s*$") or ""
	local info = { name = name ~= "" and name:sub(1, MAX_MINE_NAME) or L["Shared theme"],
		base = BaseOf(type(data.base) == "string" and data.base or nil).key, colors = {}, settings = {},
		who = type(data.who) == "string" and data.who:gsub("[%c|]", ""):sub(1, 48) or nil, skipped = 0 }
	local note = type(data.note) == "string" and data.note:gsub("[%c|]", ""):match("^%s*(.-)%s*$") or ""
	if note ~= "" then info.note = note:sub(1, MAX_MINE_NOTE) end
	for _, which in ipairs(MINE_COLORS) do
		info.colors[which] = Rgb(type(data.colors) == "table" and data.colors[which])
	end
	local known = {}
	for _, key in ipairs(ThemeKeys()) do known[key] = true end
	for key, value in pairs(type(data.settings) == "table" and data.settings or {}) do
		local kind = type(value)
		if known[key] and (kind == "string" and #value <= 64 or kind == "number" or kind == "boolean") then
			info.settings[key] = value
		else
			info.skipped = info.skipped + 1
		end
	end
	return info
end
-- A shared theme added to yours: its key, or nil and why.
function ns.AddSharedStyleTheme(info)
	local key, why = ns.AddMyStyleTheme(info.base, info.name)
	if not key then return nil, why end
	local entry = EntryOf(key)
	entry.colors, entry.settings, entry.note = info.colors, info.settings, info.note
	MineChanged()
	return key
end

-- A shared profile's theme of theirs (Share.lua): one of yours just like it
-- (name, start, colors, settings), else added. Its key, or nil and why.
local function SameValue(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do if not SameValue(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
function ns.AddProfileStyleTheme(info)
	local store = MineStore()
	for _, entry in ipairs(store and store.list or {}) do
		if type(entry) == "table" and entry.name == info.name and BaseOf(entry.base).key == info.base
			and SameValue(entry.colors or {}, info.colors) and SameValue(entry.settings or {}, info.settings) then
			return "u:" .. entry.id
		end
	end
	return ns.AddSharedStyleTheme(info)
end

-- The General page's quick settings. A change turns the Style pages on: with
-- them off, as on the game's theme, General's settings reach nothing and the
-- pick would seem to do nothing.
local function PagesOn()
	local db = ns.GetDB()
	db.styleGeneral = true
	for _, key in ipairs(SWITCHES) do db[key] = true end
end

-- One of General's own settings as a quick setting.
function ns.ThemeQuickField(key)
	return {
		get = function()
			local db = ns.GetDB()
			return db and db[key]
		end,
		set = function(value)
			ns.GetDB()[key] = value
			PagesOn()
		end,
	}
end

-- A font for the cards' big words, and one for the small names on unit and
-- raid frames, each a field over several settings. What they show when a
-- setting follows General: General's font.
local function Shown(value)
	local db = ns.GetDB()
	if value == nil or value == "default" or ns.IsGeneralStyle(value) then return db and db.styleFont end
	return value
end
function ns.ThemeTitleFontField()
	return {
		get = function()
			local db = ns.GetDB()
			return db and Shown(db[ns.CardStyleKey("Font", "place")])
		end,
		set = function(value)
			local db = ns.GetDB()
			for _, style in ipairs(ns.CARD_STYLES or {}) do
				if not CARDS_KEEP[style.id] then db[ns.CardStyleKey("Font", style.id)] = value end
			end
			PagesOn()
		end,
	}
end
function ns.ThemeSmallFontField()
	return {
		get = function()
			local db = ns.GetDB()
			return db and Shown(db.rfFont)
		end,
		set = function(value)
			local db = ns.GetDB()
			db.rfFont, db.ufFont = value, value
			PagesOn()
		end,
	}
end

-- The picker, for the General page: a card for each theme drawn in that
-- theme's own panel, corners, lettering and colors, the one in use outlined.
-- (Five to a row since 2026-11-18, on a 600 wide grid: the page's whole width; the
-- General tab's current-theme strip keeps a card the same size.)
local CARD_H, CARD_GAP, PER_ROW, STRIP_PER_ROW = 80, 8, 5, 4
-- (Russian, Korean and Chinese names keep the game's font: ours have no such letters.)
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]
local function FontOf(theme)
	return ns.StyleFontFile(theme.cardFont or theme.settings.styleFont) or (_G.GameFontNormal:GetFont())
end

-- What a card draws of a theme, as one string: one of yours is made again as a
-- new table on every change to any of yours, so its card is kept while this
-- stays the same (a frame can't be freed: one per change piled up).
local function CardLook(theme)
	if not theme.mine then return theme.key end
	local parts = { theme.key, tostring(theme.name), tostring(theme.base), tostring(theme.cardFont),
		tostring(theme.settings.styleFont), tostring(theme.settings.stylePanel) }
	local function Add(c)
		parts[#parts + 1] = type(c) == "table" and ("%.3f,%.3f,%.3f"):format(c[1] or 0, c[2] or 0, c[3] or 0) or "-"
	end
	for _, c in ipairs(theme.swatch or {}) do Add(c) end
	Add(theme.line)
	Add(theme.ornament)
	Add(theme.panel)
	Add(theme.menu and theme.menu.accent)
	return table.concat(parts, "|")
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
	-- (Its own shape, on a card that has one.)
	-- (One of yours on the game's look has a panel shape saved but no panel of ours.)
	local panel = theme.panel
	local shape = panel and theme.settings.stylePanel
	if shape then back:Hide() end
	if theme.corner then
		for i, spot in ipairs(CORNERS) do
			if i == 1 or i == 4 then
				local piece = card:CreateTexture(nil, "ARTWORK")
				piece:SetTexture(ART .. theme.corner .. "Corner")
				piece:SetTexCoord(spot[2], spot[3], spot[4], spot[5])
				piece:SetVertexColor(theme.ornament[1], theme.ornament[2], theme.ornament[3], 0.9)
				piece:SetSize(22, 22)
				piece:SetPoint(spot[1], card, spot[1], spot[6] * 1, spot[7] * 1)
			end
		end
	end
	local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("CENTER", 0, 22)
	name:SetWidth(width - 6) -- (past the fit below: room for a letter's overhang)
	name:SetWordWrap(false)
	name:SetTextColor(color[1], color[2], color[3])
	name:SetText(NameOf(theme))
	-- (A long name a little smaller, to fit its card: Moonlit Glade's at five to a row.
	-- Again on each Refresh: measured as the card's made, a font not loaded yet reads
	-- the wrong width, cutting some names off and shrinking others to nothing, retail
	-- 2026-11-18.)
	function card.FitName()
		if not ROMAN then return end
		local file, size = FontOf(theme), 13
		name:SetFont(file, size, "")
		-- (Unbounded: on a fixed width with no wrap, GetStringWidth gives the cut-off
		-- text's width, so a name cut short read as fitting.)
		local function Wide()
			if name.GetUnboundedStringWidth then return name:GetUnboundedStringWidth() end
			return name:GetStringWidth()
		end
		while size > 9 and Wide() > width - 12 do
			size = size - 1
			name:SetFont(file, size, "")
		end
	end
	card.FitName()
	name.searchSkip = true
	local chips = #theme.swatch - 1
	card.chips = {} -- (the Themes tab puts "(changed)" in their place: MakeThemePicker)
	for i = 2, #theme.swatch do
		local chip = card:CreateTexture(nil, "ARTWORK", nil, 1)
		card.chips[#card.chips + 1] = chip
		chip:SetSize(16, 5)
		chip:SetPoint("CENTER", card, "CENTER", (i - 2 - (chips - 1) / 2) * 19, -27)
		local c = theme.swatch[i]
		chip:SetColorTexture(c[1], c[2], c[3], 1)
	end
	-- What it gives plates and names: a name in its name theme (its font and
	-- hostile color) over a little bar in its plate theme (texture and line).
	local nameTheme = ns.NameThemeByKey and ns.NameThemeByKey(theme.names or theme.key)
	local look = nameTheme and nameTheme.look or {}
	local sample = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	sample:SetPoint("CENTER", 0, 3)
	local sampleFile, sampleSize = _G.GameFontNormalSmall:GetFont()
	if ROMAN and look.Font and look.Font ~= "game" and ns.StyleFontFile(look.Font) then
		sampleFile = ns.StyleFontFile(look.Font)
	end
	if sampleFile then sample:SetFont(sampleFile, (sampleSize or 10) * (tonumber(look.Size) or 1), "") end
	if look.Hostile == "custom" then
		sample:SetTextColor(look.HostileR, look.HostileG, look.HostileB)
	elseif look.Colour == "one" then
		sample:SetTextColor(look.ColourR or 1, look.ColourG or 1, look.ColourB or 1)
	else
		sample:SetTextColor(1, 0.25, 0.2)
	end
	sample:SetText(L["Gnoll Brute"])
	sample.searchSkip = true
	local plateTheme = ns.PlateThemeByKey and ns.PlateThemeByKey(theme.key == "game" and "game" or theme.plates)
	local bar = CreateFrame("StatusBar", nil, card)
	bar:SetSize(math.min(90, width - 30), 6)
	bar:SetPoint("CENTER", 0, -11)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0.7)
	if not (plateTheme and plateTheme.texture ~= "game" and ns.SetBarTexture(bar, plateTheme.texture, true)) then
		bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	end
	bar:SetStatusBarColor(0.85, 0.15, 0.1)
	-- (This card's theme's hostile color, not the one in use.)
	local hostile = theme.reaction and theme.reaction.hostile or { 0.85, 0.15, 0.1 }
	ns.DressPlateFullColor(bar, plateTheme and ns.StyleTextureFull(plateTheme.texture), hostile[1], hostile[2], hostile[3])
	local barGround = bar:CreateTexture(nil, "BACKGROUND")
	barGround:SetAllPoints()
	barGround:SetColorTexture(0, 0, 0, 0.6)
	if plateTheme and plateTheme.border == "custom" then
		local edges = ns.MakeStyleEdges(bar)
		ns.DressStyleEdges(edges, plateTheme.size or 1, plateTheme.color[1], plateTheme.color[2], plateTheme.color[3], 1, true)
	end
	local hover = card:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.06)
	Tooltip(card, TipOf(theme))
	card:SetScript("OnClick", function() onPick(theme.key) end)
	function card:Mark(on)
		if shape then
			local edge = on and color or theme.line
			ns.DressThemeSlice(self, panel[1], panel[2], panel[3], 1, edge[1], edge[2], edge[3], 1, shape)
			self.edges:Hide()
		elseif on then
			ns.DressStyleEdges(self.edges, 2, color[1], color[2], color[3], 1, false)
		else
			ns.DressStyleEdges(self.edges, 1, 0.3, 0.3, 0.32, 1, false)
		end
	end
	return card
end

-- The zone card, to see a theme just picked on the real thing. Another Test of
-- the same card would only stop the one running, so that goes first.
function ns.PlayThemeCard()
	if not ns.CardTest then return end
	if ns.CardTestRunning and ns.CardTestRunning("zone") then pcall(ns.CardTest, "zone") end
	pcall(ns.CardTest, "zone")
end

-- The theme picked now, for the General tab under its preview (2026-11-18):
-- its card (each theme's made, the picked one shown), its name ("with your
-- changes" when edited) and a button to the Themes tab, as its card does.
function ns.MakeCurrentThemeStrip(kit, parent, width)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, CARD_H)
	local cardW = (width - (STRIP_PER_ROW - 1) * CARD_GAP) / STRIP_PER_ROW
	local function Open() ns.OpenOptions("Style Themes") end
	-- (Each made the first time it's the one picked; one of yours made again
	-- once changed, as a new theme table.)
	local cards = {}
	local label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", holder, "TOPLEFT", cardW + 14, -18)
	label:SetText(L["Current theme"])
	local name = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	name:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
	name:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
	name:SetJustifyH("LEFT")
	name.searchSkip = true
	local change = ns.PanelButton(holder)
	change:SetSize(130, 22)
	change:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -8)
	change:SetText(L["Change theme"])
	kit.Tooltip(change, L["Opens the Themes tab."])
	change:SetScript("OnClick", Open)
	function holder:Refresh()
		local db = ns.GetDB()
		local current = db and db.styleGeneral and Find(db.styleTheme) or BY_KEY.game
		-- (By theme key, made again only when what it draws changed: CardLook.)
		local look = CardLook(current)
		local card = cards[current.key]
		if not card or card.look ~= look then
			if card then card:Hide() end
			card = MakeCard(holder, current, cardW, Open, kit.Tooltip)
			card.look = look
			card:SetPoint("TOPLEFT")
			card:Mark(true)
			cards[current.key] = card
		end
		for key, each in pairs(cards) do each:SetShown(key == current.key) end
		card.FitName()
		local shown = NameOf(current)
		name:SetText(ns.StyleThemeEdited() and (L["%s, with your changes"]):format(shown) or shown)
	end
	holder:SetScript("OnShow", holder.Refresh)
	holder.pageSwitch = false
	kit.AddControl(holder)
	return holder
end

-- A small color square: a click opens the color picker (TintStyle.lua's kind).
local function ColorSquare(parent, size)
	local square = CreateFrame("Button", nil, parent)
	square:SetSize(size, size)
	local border = square:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0, 0, 0, 0.9)
	square.fill = square:CreateTexture(nil, "ARTWORK")
	square.fill:SetPoint("TOPLEFT", 1, -1)
	square.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	local glow = square:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 1, 1, 0.15)
	square:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	return square
end

local MINE_COLOR_NAMES = { accent = "Accent", panel = "Panels", line = "Lines", ornament = "Rings", health = "Health",
	mana = "Mana", cast = "Casts" }
local MINE_COLOR_TIPS = {
	accent = "Titles, names and our menus' highlights.",
	panel = "Tooltips, chat bubbles and our menus' panels.",
	line = "The thin line round bars, panels and buttons.",
	ornament = "Portrait rings and corner art.",
	health = "Health bars on unit frames, the personal display and tooltips.",
	mana = "Mana bars.",
	cast = "Cast bars on nameplates.",
}

-- kit: the page's. changed: a pick's been made. Gives the picker, with its
-- Refresh, for the page's stack: ours under Built in, yours under Yours (with
-- + New theme, as the Cameras page has them), and under the grid the one of
-- yours in use, to change.
function ns.MakeThemePicker(kit, parent, width, changed)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 1)
	local cardW = (width - (PER_ROW - 1) * CARD_GAP) / PER_ROW
	local cards = {} -- (by theme table)
	local function Fit()
		C_Timer.After(0, function()
			if kit.FitContentHeight then kit.FitContentHeight(parent) end
		end)
	end
	local function Changed()
		changed()
		kit.Refresh()
	end
	local function Apply(key)
		if not ns.ApplyStyleTheme(key) then return end
		Changed()
		ns.PlayThemeCard()
	end
	-- A pick writes the theme's settings over yours, so with changes over the
	-- one in use (its card says "(changed)") it asks first: keep them (Save
	-- changes into yours, or a new theme of yours from ours), switch anyway or
	-- cancel; Reset, just whether to. (No Undo since 2026-11-18: asked here instead.)
	-- sure: nothing to lose, as + New theme has taken your changes with it.
	local function Pick(key, sure)
		local db = ns.GetDB()
		local now = db and db.styleGeneral and Find(db.styleTheme)
		if sure or not now or not ns.StyleThemeEdited() then return Apply(key) end
		local which = key == now.key and "CINEMATIC_STYLE_THEME_RESET"
			or now.mine and "CINEMATIC_STYLE_THEME_SWITCH_MINE" or "CINEMATIC_STYLE_THEME_SWITCH"
		StaticPopup_Show(which, NameOf(now), nil, { from = now.key, to = key, apply = Apply })
	end
	if not StaticPopupDialogs.CINEMATIC_STYLE_THEME_SWITCH then
		-- (Keep them, then the pick.)
		local function Keep(_, data)
			if not data then return end
			local from = Find(data.from)
			if from and from.mine then
				ns.SaveMyStyleTheme()
			else
				local key, why = ns.AddMyStyleTheme(data.from, nil, true)
				if not key then
					if why then ns.Print(why) end
					return
				end
			end
			data.apply(data.to)
		end
		local function Anyway(_, data) if data then data.apply(data.to) end end
		local function Switch(keep)
			return { text = L["Your changes to %s will be lost."], button1 = keep, button2 = CANCEL,
				button3 = L["Switch anyway"], OnAccept = Keep, OnAlt = Anyway,
				timeout = 0, whileDead = true, hideOnEscape = true }
		end
		StaticPopupDialogs.CINEMATIC_STYLE_THEME_SWITCH = Switch(L["Save as a new theme"])
		StaticPopupDialogs.CINEMATIC_STYLE_THEME_SWITCH_MINE = Switch(L["Save changes"])
		StaticPopupDialogs.CINEMATIC_STYLE_THEME_RESET = {
			text = L["Put %s back as it comes? Your changes will be lost."], button1 = L["Reset"], button2 = CANCEL,
			OnAccept = Anyway, timeout = 0, whileDead = true, hideOnEscape = true,
		}
	end

	-- The box under the grids, as on the Profiles page: what the card (or
	-- button) pointed at is and what a click does, else the theme in use. As
	-- tall as the longest it can say, so nothing under it moves with the mouse.
	local MENUS = MenuUtil and MenuUtil.CreateContextMenu and true or false
	local box = CreateFrame("Frame", nil, holder)
	box:SetSize(width, 44)
	local boxBack = box:CreateTexture(nil, "BACKGROUND")
	boxBack:SetAllPoints()
	boxBack:SetColorTexture(1, 1, 1, 0.03)
	local about = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	about:SetPoint("TOPLEFT", 10, -8)
	about:SetWidth(width - 20)
	about:SetJustifyH("LEFT")
	about:SetSpacing(2)
	about.searchSkip = true -- (it changes with the mouse)
	local tips = {} -- (every button's, to size the box)
	local Describe -- (below)
	local function BoxTip(widget, tip)
		widget.searchTip = tip
		tips[#tips + 1] = tip
		widget:SetScript("OnEnter", function() Describe(tip) end)
		widget:SetScript("OnLeave", function() Describe() end)
	end
	local function Current()
		local db = ns.GetDB()
		return db and db.styleGeneral and Find(db.styleTheme) or nil
	end
	-- A theme's words: its name, (changed) on the one in use with your
	-- changes, its line, and what a click does.
	local function ThemeText(theme)
		local now = Current()
		local using = now ~= nil and now.key == theme.key
		local hint = not using and L["Click to use it."] or nil
		if MENUS then hint = (hint and hint .. " " or "") .. L["Right-click for more."] end
		return "|cffffd100" .. NameOf(theme) .. "|r"
			.. (using and ns.StyleThemeEdited() and "  |cff808080" .. L["(changed)"] .. "|r" or "")
			.. "   " .. (TipOf(theme) or "")
			.. (hint and "\n|cff808080" .. hint .. "|r" or "")
	end
	function Describe(text)
		if text then
			about:SetText(text)
			return
		end
		local now = Current()
		about:SetText(now and ThemeText(now) or L["Pick a theme to use it."])
	end

	local builtInHead = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	builtInHead:SetText(L["Built in"])
	local mineHead = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mineHead:SetText(L["Yours"])
	local import = ns.PanelButton(holder)
	import:SetSize(80, 20)
	import:SetText(L["Import"])
	BoxTip(import, L["Adds a theme someone shared to yours."])
	-- (Beside Import: the theme in use as text, ours too, and the backups of yours.)
	local export = ns.PanelButton(holder)
	export:SetSize(80, 20)
	export:SetText(L["Export"])
	BoxTip(export, L["Gives the theme you're using, with your changes, as text to share."])
	local backups = ns.PanelButton(holder)
	backups:SetSize(90, 20)
	backups:SetText(L["Backups"])
	BoxTip(backups, L["Brings back an older copy of a theme of yours, or one you deleted."])

	-- + New theme: a plain card, the plus and its words.
	local newCard = CreateFrame("Button", nil, holder)
	newCard:SetSize(cardW, CARD_H)
	local newBack = newCard:CreateTexture(nil, "BACKGROUND")
	newBack:SetAllPoints()
	newBack:SetColorTexture(1, 1, 1, 0.04)
	local newHover = newCard:CreateTexture(nil, "HIGHLIGHT")
	newHover:SetAllPoints()
	newHover:SetColorTexture(1, 0.82, 0, 0.1)
	local plus = newCard:CreateTexture(nil, "ARTWORK")
	plus:SetSize(32, 32)
	plus:SetPoint("CENTER", 0, 10)
	plus:SetTexture("Interface\\PaperDollInfoFrame\\Character-Plus")
	local newWords = newCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	newWords:SetPoint("TOP", plus, "BOTTOM", 0, -6)
	newWords:SetText(L["+ New theme"])
	BoxTip(newCard, L["A theme of your own, made from the one you're using now with your changes."])

	-- Under the grid: the theme's name and, with changes over one of yours,
	-- Save changes. (Undo and Reapply theme gone 2026-11-18: a pick asks before
	-- your changes go, and Reset is on the card's right-click menu. Clients
	-- without the game's menus, Classic Era, keep Reapply as Reset's way in.)
	local status = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status.searchSkip = true
	local again = ns.PanelButton(holder)
	again:SetSize(110, 20)
	again:SetText(L["Reapply theme"])
	BoxTip(again, L["Puts every setting back as this theme has it."])
	again:SetScript("OnClick", function()
		local db = ns.GetDB()
		Pick(db and db.styleTheme or "game")
	end)
	local save = ns.PanelButton(holder)
	save:SetSize(110, 20)
	save:SetText(L["Save changes"])
	BoxTip(save, L["Saves your changes into this theme of yours."])
	save:SetScript("OnClick", function()
		ns.SaveMyStyleTheme()
		Changed()
	end)

	-- The editor: the one of yours in use.
	local editor = CreateFrame("Frame", nil, holder)
	editor:SetSize(width, 150)
	local editorBack = editor:CreateTexture(nil, "BACKGROUND")
	editorBack:SetAllPoints()
	editorBack:SetColorTexture(1, 1, 1, 0.03)
	local editTitle = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	editTitle:SetPoint("TOPLEFT", 10, -10)
	editTitle.searchSkip = true
	local rename = ns.PanelButton(editor)
	rename:SetSize(80, 20)
	rename:SetPoint("TOPRIGHT", -10, -6)
	rename:SetText(L["Rename"])
	local share = ns.PanelButton(editor)
	share:SetSize(70, 20)
	share:SetPoint("RIGHT", rename, "LEFT", -6, 0)
	share:SetText(L["Share"])
	kit.Tooltip(share, L["A line of text to send a friend: they add it with Import under Yours."])
	local delete = ns.PanelButton(editor)
	delete:SetSize(70, 20)
	delete:SetPoint("RIGHT", share, "LEFT", -6, 0)
	delete:SetText(L["Delete"])
	local describe = ns.PanelButton(editor)
	describe:SetSize(96, 20)
	describe:SetPoint("RIGHT", delete, "LEFT", -6, 0)
	describe:SetText(L["Description"])
	kit.Tooltip(describe, L["Write what this theme is for."])
	local fromLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fromLabel:SetPoint("TOPLEFT", 10, -40)
	fromLabel:SetText(L["Started from:"])
	local function Editing()
		local db = ns.GetDB()
		local theme = db and db.styleGeneral and Find(db.styleTheme)
		return theme and theme.mine and theme or nil
	end
	local ok, from = ns.MenuDropdown(editor)
	if ok and from and from.SetupMenu then
		from:SetWidth(170)
		from:SetupMenu(function(_, root)
			for _, theme in ipairs(THEMES) do
				root:CreateRadio(L[theme.name], function()
					local mine = Editing()
					return mine ~= nil and mine.base == theme.key
				end, function()
					local mine = Editing()
					if not mine then return end
					ns.SetMyStyleThemeBase(mine.key, theme.key)
					Changed()
				end)
			end
		end)
		from.Refresh = function(self) self:GenerateMenu() end
	else
		from = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		from.Refresh = function(self)
			local mine = Editing()
			self:SetText(mine and L[BY_KEY[mine.base].name] or "")
		end
	end
	from:SetPoint("LEFT", fromLabel, "RIGHT", 10, 0)
	from.searchSkip = true
	if from.SetScript then
		kit.Tooltip(from, L["The theme of ours it's made from: its art, shapes and fonts, under your colors and changes."])
	end
	local colorsLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	colorsLabel:SetPoint("TOPLEFT", 10, -72)
	colorsLabel:SetText(L["Colors:"])
	-- (A color picked: put in once the picker's been still a moment, as each
	-- one makes the whole theme again.)
	local pending, pendingAt = {}, 0
	local function Flush()
		local mine = Editing()
		if mine then
			for which, color in pairs(pending) do ns.SetMyStyleThemeColor(mine.key, which, color) end
		end
		pending = {}
		Changed()
	end
	local squares = {}
	local COLUMN = math.floor((width - 20) / #MINE_COLORS)
	for i, which in ipairs(MINE_COLORS) do
		local square = ColorSquare(editor, 22)
		square:SetPoint("TOPLEFT", editor, "TOPLEFT", 10 + (i - 1) * COLUMN + (COLUMN - 22) / 2, -92)
		local words = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		words:SetPoint("TOP", square, "BOTTOM", 0, -4)
		words:SetText(L[MINE_COLOR_NAMES[which]])
		square.words = words
		square:SetScript("OnClick", function(self, button)
			local mine = Editing()
			if not mine then return end
			if button == "RightButton" then
				ns.SetMyStyleThemeColor(mine.key, which, nil)
				Changed()
				return
			end
			local now = ns.MyStyleThemeColor(mine.key, which) or { 1, 1, 1 }
			kit.OpenColorPicker(now[1], now[2], now[3], function(r, g, b)
				self.fill:SetColorTexture(r, g, b, 1)
				pending[which] = { r, g, b }
				pendingAt = pendingAt + 1
				local mark = pendingAt
				C_Timer.After(0.4, function()
					if mark == pendingAt then Flush() end
				end)
			end)
		end)
		kit.Tooltip(square, L[MINE_COLOR_TIPS[which]] .. " " .. L["Right-click: back to its starting theme's."])
		squares[which] = square
	end
	local editHelp = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	editHelp:SetPoint("BOTTOMLEFT", 10, 8)
	editHelp:SetPoint("RIGHT", editor, "RIGHT", -10, 0)
	editHelp:SetJustifyH("LEFT")
	editHelp:SetText(L["Fonts, bars and shapes: change them on Quick Settings or any Style page, then Save changes."])

	-- Rename, Delete (popups), Share, Import, and the right-click menu.
	if ns.NamePopup and not StaticPopupDialogs.CINEMATIC_STYLE_THEME_RENAME then
		StaticPopupDialogs.CINEMATIC_STYLE_THEME_RENAME = ns.NamePopup(L["Rename the theme:"], function(text, key)
			if not ns.RenameMyStyleTheme(key, text) then return true end
			Changed()
		end, { initial = function(key)
			local theme = Find(key)
			return theme and theme.name or ""
		end, maxLetters = MAX_MINE_NAME })
	end
	if not StaticPopupDialogs.CINEMATIC_STYLE_THEME_DELETE then
		StaticPopupDialogs.CINEMATIC_STYLE_THEME_DELETE = {
			text = L["Delete the theme %s? Your settings stay as they are."],
			button1 = YES, button2 = NO,
			OnAccept = function(_, key)
				ns.DeleteMyStyleTheme(key)
				Changed()
			end,
			timeout = 0, whileDead = true, hideOnEscape = true,
		}
	end
	if ns.NamePopup and not StaticPopupDialogs.CINEMATIC_STYLE_THEME_NOTE then
		StaticPopupDialogs.CINEMATIC_STYLE_THEME_NOTE = ns.NamePopup(L["Describe the theme:"], function(text, key)
			ns.SetMyStyleThemeNote(key, text)
			Changed()
		end, { initial = function(key) return ns.MyStyleThemeNote(key) or "" end, maxLetters = MAX_MINE_NOTE, width = 360 })
	end
	local function Rename(theme) StaticPopup_Show("CINEMATIC_STYLE_THEME_RENAME", nil, nil, theme.key) end
	local function Note(theme) StaticPopup_Show("CINEMATIC_STYLE_THEME_NOTE", nil, nil, theme.key) end
	local function Delete(theme) StaticPopup_Show("CINEMATIC_STYLE_THEME_DELETE", theme.name, nil, theme.key) end
	-- (Ours too, and the one in use with your changes: ExportStyleTheme.)
	local function Share(theme)
		local text = ns.ExportStyleTheme(theme.key)
		if text and ns.ShowCameraShare then ns.ShowCameraShare(text, L["Share %s"]:format(NameOf(theme))) end
	end
	local function Backups(theme)
		if ns.ShowStyleThemeBackups then ns.ShowStyleThemeBackups(theme and theme.key, Pick) end
	end
	local function New(fromKey, withEdits)
		local key, why = ns.AddMyStyleTheme(fromKey, nil, withEdits)
		if key then
			Pick(key, withEdits) -- (your changes went into it: nothing to ask)
		elseif why then
			ns.Print(why)
		end
	end
	rename:SetScript("OnClick", function()
		local mine = Editing()
		if mine then Rename(mine) end
	end)
	delete:SetScript("OnClick", function()
		local mine = Editing()
		if mine then Delete(mine) end
	end)
	share:SetScript("OnClick", function()
		local mine = Editing()
		if mine then Share(mine) end
	end)
	describe:SetScript("OnClick", function()
		local mine = Editing()
		if mine then Note(mine) end
	end)
	export:SetScript("OnClick", function()
		local now = Current()
		if now then Share(now) end
	end)
	backups:SetScript("OnClick", function() Backups(nil) end)
	newCard:SetScript("OnClick", function()
		-- (On the game's look: one of yours on the game's, your changes in it.)
		local db = ns.GetDB()
		local now = db and db.styleGeneral and Find(db.styleTheme)
		New(now and now.key or "game", now ~= nil)
	end)
	import:SetScript("OnClick", function()
		if not ns.ShowShareImport then return end
		ns.ShowShareImport(L["Import a theme"], {
			read = ns.ReadSharedStyleTheme,
			describe = function(info)
				local function Safe(text) return (tostring(text or ""):gsub("|", "||")) end
				local lines = { ("|cffffd100%s|r %s"):format(L["Theme:"], Safe(info.name)),
					L["Started as: %s"]:format(L[BY_KEY[info.base].name]) }
				if info.who then lines[#lines + 1] = L["Shared by: %s"]:format(Safe(info.who)) end
				if info.skipped > 0 then
					lines[#lines + 1] = L["%d settings this Cinematic doesn't have are left out."]:format(info.skipped)
				end
				return table.concat(lines, "\n")
			end,
			add = function(info)
				local key, why = ns.AddSharedStyleTheme(info)
				if not key then return nil, why end
				Pick(key)
				return true
			end,
		})
	end)
	local function Menu(card, theme)
		if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
		-- (As a profile card's: what's done to a theme, for that one.)
		local now = Current()
		local using = now ~= nil and now.key == theme.key
		local edited = using and ns.StyleThemeEdited()
		ns.ContextMenu(card, function(_, root)
			root:CreateTitle(NameOf(theme))
			if not using then root:CreateButton(L["Use"], function() Pick(theme.key) end) end
			root:CreateButton(L["Copy to yours"], function() New(theme.key, false) end)
			if edited then
				-- (Your changes: into yours, or a new one of yours from ours; Reset drops them.)
				if theme.mine then
					root:CreateButton(L["Save changes"], function()
						ns.SaveMyStyleTheme()
						Changed()
					end)
				else
					root:CreateButton(L["Save as a new theme"], function() New(theme.key, true) end)
				end
				root:CreateButton(L["Reset"], function() Pick(theme.key) end)
			end
			if theme.mine then
				root:CreateButton(L["Rename"], function() Rename(theme) end)
				root:CreateButton(L["Description"], function() Note(theme) end)
			end
			root:CreateButton(L["Share"], function() Share(theme) end)
			if theme.mine then
				root:CreateButton(L["Backups"], function() Backups(theme) end)
				root:CreateDivider()
				root:CreateButton("|cffff4040" .. L["Delete"] .. "|r", function() Delete(theme) end)
			end
		end)
	end

	-- (By theme key; made again only when what it draws changed: CardLook.)
	local function CardOf(theme)
		local card = cards[theme.key]
		local look = CardLook(theme)
		if card and card.look ~= look then
			card:Hide()
			card = nil
		end
		if not card then
			-- (Its words go in the box under the grids, not a tooltip: Describe.)
			card = MakeCard(holder, theme, cardW, Pick, function(widget, tip) widget.searchTip = tip end)
			card.look = look
			card:SetScript("OnEnter", function(self) Describe(ThemeText(self.theme)) end)
			card:SetScript("OnLeave", function() Describe() end)
			-- (The one in use with your changes: a quiet tag where its color chips
			-- are, as a changed profile's card has one. In a corner it ran over the
			-- chips and a shaped card's edge, Forever 2026-11-18.)
			card.changedTag = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			card.changedTag:SetPoint("CENTER", card, "CENTER", 0, -27)
			card.changedTag:SetText(L["(changed)"])
			card.changedTag.searchSkip = true
			card.changedTag:Hide()
			card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			card:SetScript("OnClick", function(self, button)
				if button == "RightButton" then Menu(self, self.theme) else Pick(self.theme.key) end
			end)
			cards[theme.key] = card
		end
		card.theme = theme
		return card
	end

	-- Built in, Yours with + New theme, then the line under them and the editor.
	local function Layout()
		for _, card in pairs(cards) do card:Hide() end
		local y = 0
		local function Place(list, head, extra)
			head:ClearAllPoints()
			head:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
			y = y + 22
			local count = #list + (extra and 1 or 0)
			for i = 1, count do
				local frame = list[i] and CardOf(list[i]) or extra
				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT", holder, "TOPLEFT", ((i - 1) % PER_ROW) * (cardW + CARD_GAP),
					-(y + math.floor((i - 1) / PER_ROW) * (CARD_H + CARD_GAP)))
				frame:Show()
			end
			y = y + math.ceil(count / PER_ROW) * (CARD_H + CARD_GAP) + 6
		end
		Place(THEMES, builtInHead)
		Place(ns.MyStyleThemes(), mineHead, newCard)
		import:ClearAllPoints()
		import:SetPoint("LEFT", mineHead, "RIGHT", 10, 0)
		export:ClearAllPoints()
		export:SetPoint("LEFT", import, "RIGHT", 6, 0)
		backups:ClearAllPoints()
		backups:SetPoint("LEFT", export, "RIGHT", 6, 0)
		-- (The box: as tall as the longest it says, in this language.)
		local tallest = 0
		for _, theme in ipairs(All()) do
			about:SetText(ThemeText(theme))
			tallest = math.max(tallest, about:GetStringHeight() or 0)
		end
		for _, tip in ipairs(tips) do
			about:SetText(tip)
			tallest = math.max(tallest, about:GetStringHeight() or 0)
		end
		box:SetHeight(math.max(44, math.ceil(tallest) + 16))
		Describe()
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
		y = y + box:GetHeight() + 8
		status:ClearAllPoints()
		status:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(y + 4))
		save:ClearAllPoints()
		save:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -y)
		again:ClearAllPoints()
		again:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -116, -y)
		y = y + 30
		local mine = Editing()
		editor:SetShown(mine ~= nil)
		if mine then
			-- (On the game's look: no colors of ours to give, so no squares and a shorter editor.)
			colorsLabel:SetShown(not mine.plain)
			for _, square in pairs(squares) do
				square:SetShown(not mine.plain)
				square.words:SetShown(not mine.plain)
			end
			editor:SetHeight(mine.plain and 92 or 150)
			editor:ClearAllPoints()
			editor:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
			y = y + editor:GetHeight() + 6
		end
		if math.abs(holder:GetHeight() - y) > 0.5 then
			holder:SetHeight(y)
			Fit()
		end
	end

	function holder:Refresh()
		local db = ns.GetDB()
		local on = db and db.styleGeneral and true or false
		local current = db and Find(db.styleTheme) or BY_KEY.game
		Layout()
		for key, card in pairs(cards) do
			if card:IsShown() then card.FitName() end
			card:Mark(key == current.key)
			card:SetEnabled(on)
			card:SetAlpha(on and 1 or 0.45)
		end
		newCard:SetEnabled(on)
		newCard:SetAlpha(on and 1 or 0.45)
		export:SetEnabled(on)
		local edited = on and ns.StyleThemeEdited()
		for key, card in pairs(cards) do
			local tagged = edited and key == current.key and true or false
			card.changedTag:SetShown(tagged)
			for _, chip in ipairs(card.chips or {}) do chip:SetShown(not tagged) end
		end
		status:SetText(edited and (L["%s, with your changes"]):format(NameOf(current)) or NameOf(current))
		again:SetShown(edited and not MENUS and true or false)
		save:SetShown(edited and current.mine and true or false)
		local mine = Editing()
		if mine then
			editTitle:SetText(L["Your theme: %s"]:format(mine.name))
			if from.Refresh then from:Refresh() end
			for which, square in pairs(squares) do
				local color, own = ns.MyStyleThemeColor(mine.key, which)
				color = pending[which] or color or { 1, 1, 1 }
				square.fill:SetColorTexture(color[1], color[2], color[3], 1)
				square.words:SetFontObject(own and "GameFontHighlightSmall" or "GameFontDisableSmall")
				-- (Its words again after the swap: else Russian shows as boxes.)
				square.words:SetText(L[MINE_COLOR_NAMES[which]])
			end
		end
	end
	-- (Names fitted again a moment after the page shows: a font loading just then.)
	holder:HookScript("OnShow", function()
		C_Timer.After(0.3, function()
			for _, card in pairs(cards) do
				if card:IsShown() then card.FitName() end
			end
		end)
	end)
	-- (Its parts, for the dev copy's test: Dev/MyThemesTest.lua.)
	holder.testParts = { cards = cards, newCard = newCard, save = save, editor = editor, squares = squares,
		status = status, cardW = cardW, box = box, about = about, export = export, backups = backups }
	ns.themePicker = holder
	holder.pageSwitch = false
	kit.AddControl(holder)
	return holder
end
