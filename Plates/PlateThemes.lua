-- Plate themes: a nameplate bar's look in one pick (texture and the line
-- round it; the name is Name Style's). One per main theme, made from its
-- own data (StyleThemes.lua), and a few that stand alone. db.plateTheme
-- picks one; "main" (to start) follows the Style hub's General page as
-- plates always have, so a texture set there by hand still reaches them.
-- Kept out of the main theme's own settings (a main theme never writes it:
-- a plate theme picked by hand stays), only in its Undo.
-- PlateHealthStyle draws by it (ns.PlateThemeBar); the Nameplate Style page
-- picks it (ns.MakePartThemeStrip, below, shared with Name Style).

local _, ns = ...
local L = ns.L

ns.DEFAULTS.plateTheme = "main"

-- The themes that stand alone, after the main themes' own.
local OWN = {
	{ key = "clean", name = "Clean", tip = "Just a flat bar with a thin black border.",
		texture = "flat", border = "custom", size = 1, color = { 0, 0, 0 }, ground = { 0, 0, 0, 0.6 } },
	{ key = "minimal", name = "Minimal", tip = "A flat bar with no border.", texture = "flat", border = "none",
		ground = { 0, 0, 0, 0.35 } },
	{ key = "game", name = "The game's", tip = "The game's own bars, unchanged.", texture = "game", border = "game" },
}

-- The list (made once the main themes are known): { key, name, tip,
-- texture, border, size, color, family = the main theme it's made from }.
local list, byKey
local function List()
	if list then return list end
	list, byKey = {}, {}
	for _, info in ipairs(ns.StyleThemeList and ns.StyleThemeList() or {}) do
		local theme = ns.StyleThemeByKey(info.key)
		if theme and theme.key ~= "game" then
			local s = theme.settings or {}
			list[#list + 1] = { key = theme.key, name = theme.name, family = theme.key,
				tip = nil,
				texture = s.styleTexture or "game", border = s.styleBorder or "game", size = s.styleBorderSize or 1,
				color = { s.styleBorderR or 0, s.styleBorderG or 0, s.styleBorderB or 0 },
				-- (Its bar shape, and the ground behind the fill in its panel's
				-- color, as its own bars have them.)
				shape = s.styleBarShape, ground = theme.panel and { theme.panel[1], theme.panel[2], theme.panel[3],
					theme.back or 0.7 } or nil }
		end
	end
	for _, theme in ipairs(OWN) do list[#list + 1] = theme end
	for _, theme in ipairs(list) do byKey[theme.key] = theme end
	return list
end
function ns.PlateThemeList() return List() end
function ns.PlateThemeByKey(key)
	List()
	return byKey[key]
end

-- The plate theme in use: nil while it follows General ("main").
function ns.PlateThemeNow()
	local db = ns.db
	local key = db and db.plateTheme or "main"
	if key == "main" then return nil end
	return ns.PlateThemeByKey(key)
end

-- A plate bar's look under the rows: its texture (nil: the game's), its
-- border's kind, size and color. General's live ones while "main"; else
-- the plate theme's. Nothing while the Style hub is off.
function ns.PlateThemeBar()
	local db = ns.db
	-- (Off with the Nameplates style icon's own switch too, Default's, 2026-11-17.)
	if not (db and ns.StyleOn("handlePlateStyle", db)) then return nil, "game", 0, 0, 0, 0 end
	local theme = ns.PlateThemeNow()
	if not theme then
		local texture = db.styleTexture
		if texture == "game" then texture = nil end
		return texture, ns.StyleBorder(db, "styleBorder")
	end
	local texture = theme.texture ~= "game" and theme.texture or nil
	return texture, ns.StyleBorder({ b = theme.border, bSize = theme.size, bR = theme.color and theme.color[1],
		bG = theme.color and theme.color[2], bB = theme.color and theme.color[3] }, "b")
end

-- A plate bar's shape ("bevel"..., nil: square) and the ground behind its
-- fill ({ r, g, b, a }, nil: the game's), from a plate theme picked on the
-- page: none while it follows General, as plates always have.
function ns.PlateThemeExtras()
	local db = ns.db
	if not (db and db.styleGeneral) then return nil, nil end
	local theme = ns.PlateThemeNow()
	if not theme then return nil, nil end
	return theme.shape, theme.ground
end

-- A plate theme as a Nameplate Style row's Look (its panel's Start from a
-- theme): texture and border.
function ns.PlateThemeRowLook(key)
	local theme = ns.PlateThemeByKey(key)
	if not theme then return nil end
	local look = { LookTexture = theme.texture, LookBorder = theme.border }
	if theme.border == "custom" then
		look.LookBorderSize = theme.size
		look.LookBorderR, look.LookBorderG, look.LookBorderB = theme.color[1], theme.color[2], theme.color[3]
	end
	return look
end

-- A strip of theme tiles for a page: kind "plate" (Nameplate Style) or
-- "name" (Name Style). First the one that follows the main theme, then
-- each theme, the one in use edged in gold. Each tile shows what it gives:
-- a little bar, or a name in its font and colors. kit: the page's;
-- changed() after a pick. Gives the strip, its Refresh for the page.
local TILE_W, TILE_H, GAP, ACROSS = 112, 40, 6, 4
function ns.MakePartThemeStrip(kit, parent, kind, changed)
	local key = kind == "plate" and "plateTheme" or "nameTheme"
	local function Themes()
		local themes = { { key = "main", name = kind == "plate" and L["Follow General"] or L["Follow main theme"] } }
		local source = kind == "plate" and ns.PlateThemeList() or ns.NameThemeList()
		-- (The game's second, right after Follow, 2026-11-16: the plain one easy to find.)
		for _, theme in ipairs(source) do
			if theme.key == "game" then table.insert(themes, 2, theme) else themes[#themes + 1] = theme end
		end
		return themes
	end
	local strip = CreateFrame("Frame", nil, parent)
	strip:SetSize(ACROSS * TILE_W + (ACROSS - 1) * GAP, TILE_H)
	local tiles = {}
	for _, theme in ipairs(Themes()) do
		local tile = CreateFrame("Button", nil, strip)
		tile:SetSize(TILE_W, TILE_H)
		local back = tile:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0.1, 0.1, 0.12, 0.95)
		tile.edges = ns.MakeStyleEdges(tile)
		local glow = tile:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 1, 1, 0.07)
		tile.words = tile:CreateFontString(nil, "OVERLAY", ns.LOOK_TEXT)
		tile.words:SetPoint("TOPLEFT", 7, -5)
		tile.words:SetPoint("TOPRIGHT", -7, -5)
		tile.words:SetJustifyH("LEFT")
		tile.words:SetWordWrap(false)
		tile.words:SetText(theme.key == "main" and theme.name or L[theme.name])
		tile.searchLabel = theme.key == "main" and theme.name or L[theme.name]
		-- (What it gives: a little bar for plates, a name for names.)
		if kind == "plate" then
			-- (Tall enough to see its texture, its shape and ground on it.)
			tile.bar = CreateFrame("StatusBar", nil, tile)
			tile.bar:SetSize(TILE_W - 18, 12)
			tile.bar:SetPoint("BOTTOMLEFT", 9, 6)
			tile.bar:SetMinMaxValues(0, 1)
			tile.bar:SetValue(0.7)
			tile.ground = tile.bar:CreateTexture(nil, "BACKGROUND")
			tile.ground:SetAllPoints()
			tile.barEdges = ns.MakeStyleEdges(tile.bar)
		else
			tile.sample = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			tile.sample:SetPoint("BOTTOMLEFT", 9, 5)
		end
		tile:SetScript("OnClick", function()
			ns.GetDB()[key] = theme.key
			changed()
			kit.Refresh()
		end)
		tile:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local tip = theme.key == "main" and (kind == "plate"
				and L["The bar as set on the Style hub's Quick Settings tab."]
				or L["The names of the main theme picked on the Style hub's Themes tab."])
				or (theme.tip and L[theme.tip]) or ""
			if theme.family then tip = (L["%s's own, made from its colors and art."]):format(L[theme.name]) end
			GameTooltip:SetText(L[theme.name] or theme.name, 1, 1, 1)
			GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)
		tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
		tile.theme = theme
		tiles[#tiles + 1] = tile
	end
	-- One row to start with (2026-11-16): the theme in use first, then the
	-- next ones, the last cell a More tile that shows them all (and Fewer
	-- after them, to fold them back). Open or not: kept while the session lasts.
	local more = CreateFrame("Button", nil, strip)
	more:SetSize(TILE_W, TILE_H)
	local moreBack = more:CreateTexture(nil, "BACKGROUND")
	moreBack:SetAllPoints()
	moreBack:SetColorTexture(0.1, 0.1, 0.12, 0.95)
	ns.DressStyleEdges(ns.MakeStyleEdges(more), 1, 0.24, 0.24, 0.28, 1)
	local moreGlow = more:CreateTexture(nil, "HIGHLIGHT")
	moreGlow:SetAllPoints()
	moreGlow:SetColorTexture(1, 1, 1, 0.07)
	more.words = more:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	more.words:SetPoint("CENTER")
	more.words.searchSkip = true
	-- (The plates' strip all out, no More: its tab has the room, 2026-11-16.)
	local always = kind == "plate"
	local open = always
	local function Arrange(picked)
		-- (Kept in their places, 2026-11-16: the first (the default) stays
		-- first. Folded, the one in use comes second if it'd be out of sight.)
		local shown = open and #tiles or math.min(#tiles, ACROSS - 1)
		local order = {}
		for i, tile in ipairs(tiles) do order[i] = tile end
		if not open then
			for i = shown + 1, #order do
				if order[i].theme.key == picked then
					table.insert(order, 2, table.remove(order, i))
					break
				end
			end
		end
		for _, tile in ipairs(tiles) do tile:Hide() end
		for i = 1, shown do
			local tile = order[i]
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", ((i - 1) % ACROSS) * (TILE_W + GAP), -math.floor((i - 1) / ACROSS) * (TILE_H + GAP))
			tile:Show()
		end
		local cells = always and shown or shown + 1
		more:SetShown(not always)
		more:ClearAllPoints()
		more:SetPoint("TOPLEFT", (shown % ACROSS) * (TILE_W + GAP), -math.floor(shown / ACROSS) * (TILE_H + GAP))
		more.words:SetText(open and L["Fewer"] or (L["More (%d)"]):format(#order - shown))
		local lines = math.ceil(cells / ACROSS)
		strip:SetHeight(lines * TILE_H + (lines - 1) * GAP)
	end
	more:SetScript("OnClick", function()
		open = not open
		local db = ns.GetDB()
		Arrange(db and db[key] or "main")
		if ns.GRID_KIT and ns.GRID_KIT.FitContentHeight then ns.GRID_KIT.FitContentHeight(parent) end
	end)
	more:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(open and L["Show just the one in use and a few more."] or L["Show every theme."], 1, 1, 1)
		GameTooltip:Show()
	end)
	more:SetScript("OnLeave", function() GameTooltip:Hide() end)
	Arrange("main")
	function strip.Refresh()
		local db = ns.GetDB()
		local picked = db and db[key] or "main"
		Arrange(picked)
		local on = db and db.styleGeneral and (kind == "plate" or db.plateNameStyle) and true or false
		for _, tile in ipairs(tiles) do
			local theme = tile.theme
			if theme.key == picked then
				ns.DressStyleEdges(tile.edges, 2, 1, 0.82, 0, 1)
			else
				ns.DressStyleEdges(tile.edges, 1, 0.24, 0.24, 0.28, 1)
			end
			tile:SetEnabled(on)
			tile:SetAlpha(on and 1 or 0.45)
			if kind == "plate" then
				local texture, edge, size, r, g, b
				if theme.key == "main" then
					local general = db and db.styleGeneral and db or ns.DEFAULTS
					texture = general.styleTexture
					edge, size, r, g, b = ns.StyleBorder(general, "styleBorder")
				else
					texture = theme.texture
					edge, size, r, g, b = ns.StyleBorder({ b = theme.border, bSize = theme.size,
						bR = theme.color and theme.color[1], bG = theme.color and theme.color[2],
						bB = theme.color and theme.color[3] }, "b")
				end
				if not (texture and texture ~= "game" and ns.SetBarTexture(tile.bar, texture, true)) then
					tile.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
				end
				tile.bar:SetStatusBarColor(0.85, 0.15, 0.1)
				local hr, hg, hb = ns.ThemeReactionColor("hostile")
				ns.DressPlateFullColor(tile.bar, ns.StyleTextureFull(texture), hr or 0.85, hg or 0.15, hb or 0.1)
				local ground = theme.key ~= "main" and theme.ground or { 0, 0, 0, 0.6 }
				tile.ground:SetColorTexture(ground[1], ground[2], ground[3], ground[4] or 0.6)
				ns.DressBarShape(tile.bar, tile.ground, theme.key == "main" or not theme.shape, nil, nil, theme.shape)
				tile.barEdges:SetShown(edge == "line")
				if edge == "line" then ns.DressStyleEdges(tile.barEdges, size, r, g, b, 1, true) end
			else
				-- (Its name sample: the theme's font and its hostile color.)
				local look = theme.key == "main" and ns.NameThemeLook and ns.NameThemeLook("main") or theme.look or {}
				local file, height = _G.GameFontNormal:GetFont()
				local font = look.Font
				if font and font ~= "game" and font ~= "usual" and ns.StyleFontFile(font)
					and not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""] then
					file = ns.StyleFontFile(font)
				end
				tile.sample:SetFont(file, (height or 12) * (tonumber(look.Size) or 1), (tonumber(look.Outline) or 0) > 0
					and "OUTLINE" or "")
				if look.Hostile == "custom" then
					tile.sample:SetTextColor(look.HostileR, look.HostileG, look.HostileB)
				elseif look.Colour == "one" then
					tile.sample:SetTextColor(look.ColourR or 1, look.ColourG or 1, look.ColourB or 1)
				else
					tile.sample:SetTextColor(1, 0.25, 0.2)
				end
				tile.sample:SetText(L["Gnoll Brute"])
			end
		end
	end
	strip.pageSwitch = false
	kit.AddControl(strip)
	return strip
end
