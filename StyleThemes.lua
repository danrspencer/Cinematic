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
local CARDS_KEEP = { danger = true, combat = true, respite = true, rare = true, alert = true, death = true,
	victory = true, triumph = true, film = true, storybook = true, arcade = true }
local function CardSettings(theme)
	local list = {}
	if not theme.cardColor then return list end
	for _, style in ipairs(ns.CARD_STYLES or {}) do
		if not CARDS_KEEP[style.id] then
			list[ns.CardStyleKey("R", style.id)] = theme.cardColor[1]
			list[ns.CardStyleKey("G", style.id)] = theme.cardColor[2]
			list[ns.CardStyleKey("B", style.id)] = theme.cardColor[3]
			list[ns.CardStyleKey("Font", style.id)] = theme.cardFont
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

local function Theme(info)
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
	s.rfTexture, s.rfFont, s.rfNameSize, s.rfOutline, s.rfShadow = "tile", "friz", 1.15, 0, "on"
	s.ufNameColor = "theme"
	-- (Unit names are small too: the themes' thin fonts go faint there.)
	s.ufFont, s.ufOutline, s.ufShadow = "friz", 0, info.layout == "slab" and "soft" or "on"
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
	Panels(s, info.panel, info.panelAlpha)
	Casts(s, info.cast, info.channel, info.locked, info.stop)
	Line(s, info.lineSize, info.line)
	return info
end

local THEMES = {
	{ key = "game", name = "The game's", tip = "Everything as the game draws it. Each Style page's own defaults.",
		swatch = { { 0.10, 0.09, 0.08 }, { 1, 0.82, 0 }, { 0, 0.8, 0 }, { 0, 0.45, 1 } }, settings = {} },
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
			stylePanel = "deco", styleBarShape = "bevel",
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

-- Shapes (Media/make_shape_art.py), as ordinary settings: a theme picks them and
-- any can be picked on top of any theme.
local SHAPES = ART .. "Shapes\\"
local PANEL_ART = { round = "Round", chamfer = "Chamfer", blade = "Blade", notch = "Notch", sigil = "Sigil",
	veil = "Veil", deco = "Deco", plate = "Plate", leaf = "Leaf", facet = "Facet", soft = "Soft" }
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
function ns.DressBarShape(bar, back, skip, rect, gap)
	local db = ns.db
	local art = not skip and db and db.styleGeneral and BAR_ART[db.styleBarShape] or nil
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
	local theme = BY_KEY[key]
	if not (db and theme) then return end
	local keys = ThemeKeys()
	if not noUndo then db.styleThemeKept = ns.StyleSnapshot() end
	db.styleGeneral = true
	db.styleTheme = key
	local settings, base = SettingsOf(theme), Base()
	for _, each in ipairs(keys) do db[each] = ThemeValue(each, settings, base) end
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
	-- (Its own shape, on a card that has one.)
	local shape = theme.settings.stylePanel
	local panel = theme.panel
	if shape then back:Hide() end
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
		if not ns.ApplyStyleTheme(key) then return end
		changed()
		kit.Refresh()
		ns.PlayThemeCard()
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
