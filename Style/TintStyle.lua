-- The Atmosphere hub's Tint Style page: the look of the color grading over
-- the world. Pictures of each look (a gray scale graded as the world
-- would be), your own tints, one Strength slider, the day cycle as a bar
-- and the place you're standing in. (The tint itself: Tint.lua. Where and
-- when it shows: the Tint tab, LetterboxStyle.lua.)
local _, ns = ...
local L = ns.L

ns.DEFAULTS.tintStyle = true -- this page at all (its switch; off: the tint's plain look, Tint.lua's Look)

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PAGE_W = 600
local GAP = 6
local SECTION_GAP = 22
local GREY_EDGE = { 0.32, 0.3, 0.27 }
-- The main looks (None: the way to turn it off), then the one-color looks,
-- shown among your own tints as more looks.
local LIVING = { "zonetime", "timeofday", "zone", "none" }
local FIXED = { "warm", "cool", "night", "dusk", "sepia", "dreamy" }
local TIME_LOOKS = { timeofday = true, zonetime = true }
local ZONE_LOOKS = { zone = true, zonetime = true }
local STRENGTH_CHIPS = { { "Subtle", 0.4 }, { "Medium", 0.7 }, { "Strong", 1 } }
-- Quick colors for a tint of your own (any other: the color picker).
local PALETTE = {
	{ 1, 0.82, 0.6 }, { 1, 0.7, 0.5 }, { 1, 0.62, 0.62 }, { 0.95, 0.72, 0.88 }, { 0.79, 0.63, 1 },
	{ 0.62, 0.7, 1 }, { 0.62, 0.85, 1 }, { 0.66, 0.9, 0.81 }, { 0.78, 0.94, 0.63 }, { 0.94, 0.9, 0.55 },
	{ 0.75, 0.75, 0.75 }, { 0.54, 0.59, 0.66 },
}

local function Copy(color) return color and { color[1], color[2], color[3] } end

-- A color as the tint grades it at strength (Tint.lua's ApplyTint): multiply
-- blends from white toward it, a glow adds it.
local function Grade(color, strength, mode)
	local out = { 1, 1, 1, 1 }
	for c = 1, 3 do
		if mode == "ADD" then
			out[c] = math.min(1, color[c] * strength)
		else
			out[c] = math.max(0, 1 - (1 - color[c]) * strength)
		end
	end
	return out
end

local function Edges(frame)
	frame.edges = ns.MakeStyleEdges(frame)
	function frame.Ring(_, on)
		if on then
			ns.DressStyleEdges(frame.edges, 2, 1, 0.82, 0, 1)
		else
			ns.DressStyleEdges(frame.edges, 1, GREY_EDGE[1], GREY_EDGE[2], GREY_EDGE[3], 1)
		end
	end
	frame:Ring(false)
end

local function Text(parent, font, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	fs:SetText(text or "")
	return fs
end

local function TipOn(widget, tip)
	widget:HookScript("OnEnter", function(self)
		local shown = type(tip) == "function" and tip() or tip
		if not shown or shown == "" then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(shown, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A color panel: a soft gray scale, dark on the left to light on the right,
-- with a wash over it graded as the world would be (the way a color grading
-- tool shows a look): panel:Tint(top, bottom, mode, strength) or :Tint(nil).
-- Coloring shows on the light end, a glow lifts the dark end. from: how far
-- from the left the wash starts (0-1), for a before and after.
local RAMP_DARK, RAMP_LIGHT = 0.1, 0.86
local function Scene(parent, width, height, from)
	local scene = CreateFrame("Frame", nil, parent)
	scene:SetSize(width, height)
	local ramp = scene:CreateTexture(nil, "BACKGROUND")
	ramp:SetTexture(WHITE)
	ramp:SetAllPoints()
	ns.TintSetGradient(ramp, "HORIZONTAL", { RAMP_DARK, RAMP_DARK, RAMP_DARK, 1 },
		{ RAMP_LIGHT, RAMP_LIGHT, RAMP_LIGHT, 1 })
	local wash = scene:CreateTexture(nil, "ARTWORK")
	wash:SetTexture(WHITE)
	wash:SetPoint("TOPRIGHT")
	wash:SetPoint("BOTTOMRIGHT")
	wash:SetWidth(width * (1 - (from or 0)))
	wash:Hide()
	-- A faint line along the top: the panel's edge on the dark menu.
	local edge = scene:CreateTexture(nil, "OVERLAY")
	edge:SetColorTexture(1, 1, 1, 0.08)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("TOPRIGHT")
	edge:SetHeight(1)
	function scene.Tint(_, top, bottom, mode, strength)
		if not top or not strength or strength <= 0 then
			wash:Hide()
			return
		end
		wash:SetBlendMode(mode == "ADD" and "ADD" or "MOD")
		ns.TintSetGradient(wash, "VERTICAL", Grade(bottom or top, strength, mode), Grade(top, strength, mode))
		wash:Show()
	end
	return scene
end

-- A look's tile: its scene, its name under it; ring gold while picked.
local function Tile(parent, width, height, sceneHeight)
	local tile = CreateFrame("Button", nil, parent)
	tile:SetSize(width, height)
	local back = tile:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.1, 0.095, 0.085, 0.95)
	tile.scene = Scene(tile, width - 4, sceneHeight)
	tile.scene:SetPoint("TOP", 0, -2)
	tile.scene:EnableMouse(false)
	tile.name = Text(tile, ns.LOOK_TEXT)
	tile.name:SetPoint("TOPLEFT", tile.scene, "BOTTOMLEFT", 5, -5)
	tile.name:SetPoint("TOPRIGHT", tile.scene, "BOTTOMRIGHT", -5, -5)
	tile.name:SetWordWrap(false)
	local glow = tile:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 1, 1, 0.08)
	Edges(tile)
	return tile
end

-- A plain button that rings gold while picked (the strength chips, clocks...).
local function Chip(parent, text, width)
	local button = ns.PanelButton(parent)
	button:SetSize(width or 80, 22)
	button:SetText(text)
	Edges(button)
	button.Ring(button, false)
	button.edges:SetShown(false)
	function button.Pick(self, on)
		self.edges:SetShown(on)
		if on then self:Ring(true) end
	end
	return button
end

-- A color square that opens the color picker.
local function Swatch(parent, size)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(size, size)
	local border = swatch:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0, 0, 0, 0.9)
	swatch.fill = swatch:CreateTexture(nil, "ARTWORK")
	swatch.fill:SetPoint("TOPLEFT", 1, -1)
	swatch.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	swatch.fill:SetColorTexture(1, 1, 1, 1)
	local glow = swatch:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 1, 1, 0.15)
	function swatch.SetColor(_, color)
		swatch.fill:SetColorTexture(color[1], color[2], color[3], 1)
	end
	Edges(swatch)
	swatch.edges:Hide()
	function swatch.Pick(self, on)
		self.edges:SetShown(on)
		if on then self:Ring(true) end
	end
	return swatch
end

-- A section: a frame the page stacks under the one before (Layout).
local function Section(content, height)
	local section = CreateFrame("Frame", nil, content)
	section:SetSize(PAGE_W, height)
	section.recordAs = content -- (its settings are the page's: Reset page)
	return section
end

local function Heading(kit, section, text, note)
	local head = kit.Header(section, text, section, 0)
	head:ClearAllPoints()
	head:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
	if note then
		local small = Text(section, "GameFontHighlightSmall", note)
		small:SetPoint("LEFT", head, "RIGHT", 10, 0)
		small:SetPoint("RIGHT", section, "RIGHT", 0, 0)
		small:SetWordWrap(false)
		small:SetTextColor(0.66, 0.63, 0.59)
		head.note = small
	end
	return head
end

local function GroupLabel(section, text)
	return Text(section, ns.LOOK_DIM, text)
end

function ns.CreateTintStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Tint"])
	ns.EffectTabs(content, title, "tint", 2)
	local intro = kit.PageIntro(content, title,
		L["The color grading over the game world."])
	-- (Off: the tint keeps to its plain look, the defaults: Tint.lua's Look.)
	local switch = kit.PageSwitch(content, "tintStyle", L["Enable Page"],
		L["When on, the tint looks the way this page sets it. When off, it uses the plain look: the " ..
			"default preset, with none of your own zone, area or time of day colors. This page keeps its " ..
			"settings for when you turn it back on."],
		intro, function() ns.RefreshTint() end)
	for _, key in ipairs({ "tintPreset", "timeTintStrength", "tintClock" }) do kit.RecordKey(content, key) end

	local presetInfo = {}
	for _, preset in ipairs(ns.TINT_PRESETS) do presetInfo[preset.key] = preset end

	local sections = {}
	local hoverKey, draft -- a tile under the mouse; the tint you're making (or editing)
	local editing -- another place being edited on the Zones tab (its name), or nil: where you stand
	local tab = "look" -- the tab shown: "look", "zones" or "time"
	local pickedPhase -- the phase picked to change (and shown), or nil
	local RefreshAll, UpdatePreview, RefreshRecipe

	-- Sections stack in order: those of the tab shown (section.tab) and the
	-- ones above the tabs, each unless it's not wanted now (section.wanted).
	local function Layout()
		local above
		for _, section in ipairs(sections) do
			section:ClearAllPoints()
			section:SetShown((section.tab == nil or section.tab == tab) and section.wanted ~= false)
			if section:IsShown() then
				if above then
					section:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SECTION_GAP)
				else
					section:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 2, 0) -- (the hidden switch: 1px under the intro)
				end
				above = section
			end
		end
		kit.FitContentHeight(content)
	end

	-- (Every control redrawn: the sliders too, then the page, through master.)
	local function Changed()
		ns.RefreshTint()
		kit.Refresh()
	end

	-- ── The preview: the scene without and with the look ──────────────────
	local preview = Section(content, 92)
	sections[#sections + 1] = preview
	local SPLIT = 0.38
	local scene = Scene(preview, PAGE_W, 44, SPLIT)
	scene:SetPoint("TOPLEFT")
	local line = scene:CreateTexture(nil, "OVERLAY")
	line:SetColorTexture(1, 0.82, 0, 1)
	line:SetSize(2, 44)
	line:SetPoint("TOPLEFT", PAGE_W * SPLIT - 1, 0)
	local function Badge(text, point, x, gold)
		local back = scene:CreateTexture(nil, "OVERLAY")
		back:SetColorTexture(0, 0, 0, 0.6)
		local words = Text(scene, ns.LOOK_TEXT, text)
		words:SetPoint(point, scene, point, x, -6)
		back:SetPoint("TOPLEFT", words, "TOPLEFT", -5, 3)
		back:SetPoint("BOTTOMRIGHT", words, "BOTTOMRIGHT", 5, -3)
		if gold then words:SetTextColor(1, 0.82, 0) end
	end
	Badge(L["Without"], "TOPLEFT", 10)
	Badge(L["With tint"], "TOPRIGHT", -10, true)
	local status = Text(preview, "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", scene, "BOTTOMLEFT", 0, -8)
	status:SetWidth(PAGE_W)
	status:SetWordWrap(false)
	-- What the look is made of, by the names of the parts below that change
	-- each: Zone mood × Time of day = what you see.
	local recipe = CreateFrame("Frame", nil, preview)
	recipe:SetSize(PAGE_W, 16)
	recipe:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -7)
	local recipeParts = {}
	local function RecipePart(after)
		local part = {}
		part.op = Text(recipe, "GameFontHighlight")
		part.op:SetTextColor(0.66, 0.63, 0.59)
		if after then
			part.op:SetPoint("LEFT", after.text, "RIGHT", 10, 0)
		else
			part.op:SetPoint("LEFT", recipe, "LEFT", 0, 0)
		end
		part.swatch = recipe:CreateTexture(nil, "ARTWORK")
		part.swatch:SetSize(12, 12)
		part.swatch:SetPoint("LEFT", part.op, "RIGHT", after and 10 or 0, 0)
		part.text = Text(recipe, "GameFontHighlightSmall")
		part.text:SetPoint("LEFT", part.swatch, "RIGHT", 6, 0)
		part.text:SetWordWrap(false)
		recipeParts[#recipeParts + 1] = part
		return part
	end
	local zonePart = RecipePart()
	local timePart = RecipePart(zonePart)
	local resultPart = RecipePart(timePart)

	-- ── The tabs: Look, Zones, Time of day ────────────────────────────────
	local tabBar = Section(content, 30)
	sections[#sections + 1] = tabBar
	local tabLine = tabBar:CreateTexture(nil, "BACKGROUND")
	tabLine:SetColorTexture(GREY_EDGE[1], GREY_EDGE[2], GREY_EDGE[3], 1)
	tabLine:SetPoint("BOTTOMLEFT")
	tabLine:SetPoint("BOTTOMRIGHT")
	tabLine:SetHeight(1)
	local tabButtons = {}
	for i, info in ipairs({
		{ "look", L["Look"], L["Pick the look, make your own and set how strong it is."] },
		{ "zones", L["Zones"], L["Each zone's and area's mood: the zone part of the look."] },
		{ "time", L["Time of day"], L["The color for each part of the day: the time part of the look."] },
	}) do
		local button = CreateFrame("Button", nil, tabBar)
		button.key = info[1]
		button.words = Text(button, "GameFontNormal", info[2])
		button.words:SetPoint("CENTER", 0, 1)
		button:SetSize(button.words:GetStringWidth() + 28, 30)
		if i == 1 then
			button:SetPoint("BOTTOMLEFT")
		else
			button:SetPoint("BOTTOMLEFT", tabButtons[i - 1], "BOTTOMRIGHT", 4, 0)
		end
		button.mark = button:CreateTexture(nil, "ARTWORK")
		button.mark:SetColorTexture(1, 0.82, 0, 1)
		button.mark:SetPoint("BOTTOMLEFT")
		button.mark:SetPoint("BOTTOMRIGHT")
		button.mark:SetHeight(2)
		local glow = button:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 1, 1, 0.05)
		TipOn(button, info[3])
		button:SetScript("OnClick", function(self)
			tab = self.key
			draft, hoverKey = nil, nil
			kit.Refresh()
		end)
		tabButtons[i] = button
	end
	-- Said on the Zones and Time of day tabs when the look doesn't use that part.
	local tabNote = Text(tabBar, ns.LOOK_DIM)
	tabNote:SetPoint("BOTTOMLEFT", tabButtons[#tabButtons], "BOTTOMRIGHT", 14, 9)
	tabNote:SetPoint("RIGHT", tabBar, "RIGHT", 0, 0)
	tabNote:SetJustifyH("RIGHT")
	tabNote:SetWordWrap(false)

	-- ── Choose a look ─────────────────────────────────────────────────────
	local looks = Section(content, 100)
	looks.tab = "look"
	sections[#sections + 1] = looks
	Heading(kit, looks, L["Choose a look"])
	local tiles = {}
	local function PickLook(key)
		ns.GetDB().tintPreset = key
		draft = nil
		Changed()
	end
	local function LookTile(key, width, height, sceneHeight)
		local tile = Tile(looks, width, height, sceneHeight)
		tile.key = key
		tile:SetScript("OnClick", function(self)
			if self.key:find("^mine") and ns.GetDB().tintPreset == self.key and not draft then
				-- (A picked tint of yours, clicked again: edit it.)
				local mine = ns.GetMyTint(self.key)
				if mine then
					draft = { key = mine.key, name = mine.name, color = Copy(mine.color), color2 = Copy(mine.color2),
						glow = mine.glow }
					RefreshAll()
					return
				end
			end
			PickLook(self.key)
		end)
		tile:SetScript("OnEnter", function(self)
			hoverKey = self.key
			UpdatePreview()
		end)
		tile:SetScript("OnLeave", function()
			hoverKey = nil
			UpdatePreview()
		end)
		tiles[#tiles + 1] = tile
		return tile
	end

	local livingLabel = GroupLabel(looks, L["Main looks"])
	livingLabel:SetPoint("TOPLEFT", 0, -24)
	local LIVING_W = math.floor((PAGE_W - 3 * GAP) / 4)
	for i, key in ipairs(LIVING) do
		local tile = LookTile(key, LIVING_W, 60, 34)
		tile:SetPoint("TOPLEFT", livingLabel, "BOTTOMLEFT", (i - 1) * (LIVING_W + GAP), -5)
		tile.name:SetText(presetInfo[key].label)
		TipOn(tile, presetInfo[key].tip)
		if key == "zonetime" then
			local badge = tile.scene:CreateTexture(nil, "OVERLAY")
			badge:SetColorTexture(1, 0.82, 0, 1)
			local words = Text(tile.scene, ns.LOOK_TEXT, L["Recommended"])
			words:SetTextColor(0.1, 0.08, 0)
			words:SetPoint("TOPRIGHT", -8, -6)
			badge:SetPoint("TOPLEFT", words, "TOPLEFT", -4, 2)
			badge:SetPoint("BOTTOMRIGHT", words, "BOTTOMRIGHT", 4, -2)
		end
	end
	local livingBottom = tiles[1]

	-- More looks: the one-color ones, your own tints, + New tint (placed by RefreshLooks).
	local SMALL_W = math.floor((PAGE_W - 6 * GAP) / 7)
	local mineLabel = GroupLabel(looks, L["More looks"])
	mineLabel:SetPoint("TOPLEFT", livingBottom, "BOTTOMLEFT", 0, -12)
	local function ShortName(key)
		return (presetInfo[key].label:gsub(" /.*", ""):gsub("%-ish$", ""):gsub(" gradient$", ""))
	end
	local fixedTiles = {}
	for i, key in ipairs(FIXED) do
		local tile = LookTile(key, SMALL_W, 50, 24)
		tile.name:SetText(ShortName(key))
		TipOn(tile, presetInfo[key].label .. "\n" .. presetInfo[key].tip)
		fixedTiles[i] = tile
	end
	local mineTiles = {}
	local newTile = CreateFrame("Button", nil, looks)
	newTile:SetSize(SMALL_W, 50)
	local newBack = newTile:CreateTexture(nil, "BACKGROUND")
	newBack:SetAllPoints()
	newBack:SetColorTexture(0.07, 0.065, 0.06, 0.9)
	Edges(newTile)
	local plus = Text(newTile, "GameFontNormalLarge", "+")
	plus:SetPoint("CENTER", 0, 7)
	local newWords = Text(newTile, ns.LOOK_TEXT, L["New tint"])
	newWords:SetPoint("TOP", plus, "BOTTOM", 0, -4)
	newWords:SetTextColor(1, 0.82, 0)
	local newGlow = newTile:CreateTexture(nil, "HIGHLIGHT")
	newGlow:SetAllPoints()
	newGlow:SetColorTexture(1, 1, 1, 0.08)
	TipOn(newTile, L["Make your own tint with your own colors."])
	newTile:SetScript("OnClick", function()
		draft = { name = L["My tint"], color = { 0.79, 0.63, 1 } }
		RefreshAll()
	end)

	-- ── Your own tint: making or editing one ──────────────────────────────
	local editor = Section(content, 182)
	sections[#sections + 1] = editor
	editor.tab = "look"
	local editorBack = editor:CreateTexture(nil, "BACKGROUND")
	editorBack:SetAllPoints()
	editorBack:SetColorTexture(0.11, 0.1, 0.08, 0.95)
	Edges(editor)
	editor:Ring(true)
	local editorTitle = Text(editor, "GameFontNormal", L["Make your own tint"])
	editorTitle:SetPoint("TOPLEFT", 12, -10)
	local editorNote = Text(editor, "GameFontHighlightSmall", L["The scene above shows it as you choose."])
	editorNote:SetPoint("LEFT", editorTitle, "RIGHT", 10, 0)
	editorNote:SetTextColor(0.66, 0.63, 0.59)

	local nameLabel = Text(editor, "GameFontHighlightSmall", L["Name"])
	nameLabel:SetPoint("TOPLEFT", 12, -36)
	local nameBox = ns.SkinEditBox(CreateFrame("EditBox", nil, editor, "InputBoxTemplate"))
	nameBox:SetSize(150, 20)
	nameBox:SetAutoFocus(false)
	nameBox:SetMaxLetters(24)
	nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
	nameBox:SetScript("OnTextChanged", function(self, typed)
		if typed and draft then draft.name = self:GetText() end
	end)
	nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	local function DraftCheck(text, tip, x, y)
		local check = ns.SkinCheck(CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate"))
		check:SetSize(22, 22)
		check:SetPoint("TOPLEFT", x, y)
		local words = Text(editor, "GameFontHighlightSmall", text)
		words:SetPoint("LEFT", check, "RIGHT", 2, 0)
		check.words = words
		TipOn(check, tip)
		return check
	end
	local glowCheck = DraftCheck(L["Soft glow"], L["Adds a soft light over the world instead of coloring it."], 300, -34)
	glowCheck:SetScript("OnClick", function(self)
		if draft then draft.glow = self:GetChecked() or nil end
		RefreshAll()
	end)

	local colorLabel = Text(editor, "GameFontHighlightSmall", L["Color"])
	colorLabel:SetPoint("TOPLEFT", 12, -70)
	local mainSwatch = Swatch(editor, 22)
	mainSwatch:SetPoint("LEFT", colorLabel, "RIGHT", 12, 0)
	TipOn(mainSwatch, L["Any color: opens the color picker."])
	mainSwatch:SetScript("OnClick", function()
		if not draft then return end
		local c = draft.color
		kit.OpenColorPicker(c[1], c[2], c[3], function(r, g, b)
			if draft then draft.color = { r, g, b } end
			RefreshAll()
		end)
	end)
	local paletteSwatches = {}
	for i, color in ipairs(PALETTE) do
		local swatch = Swatch(editor, 18)
		swatch:SetPoint("LEFT", mainSwatch, "RIGHT", 14 + (i - 1) * 22, 0)
		swatch:SetColor(color)
		swatch.color = color
		swatch:SetScript("OnClick", function(self)
			if draft then draft.color = Copy(self.color) end
			RefreshAll()
		end)
		paletteSwatches[i] = swatch
	end

	local fadeCheck = DraftCheck(L["A second color at the bottom"], L["Fades the tint to a second color at the bottom of the screen."],
		10, -98)
	local bottomSwatch = Swatch(editor, 18)
	bottomSwatch:SetPoint("LEFT", fadeCheck.words, "RIGHT", 10, 0)
	TipOn(bottomSwatch, L["The bottom color: opens the color picker."])
	fadeCheck:SetScript("OnClick", function(self)
		if draft then draft.color2 = self:GetChecked() and { 1, 1, 1 } or nil end
		RefreshAll()
	end)
	bottomSwatch:SetScript("OnClick", function()
		if not draft or not draft.color2 then return end
		local c = draft.color2
		kit.OpenColorPicker(c[1], c[2], c[3], function(r, g, b)
			if draft then draft.color2 = { r, g, b } end
			RefreshAll()
		end)
	end)

	-- Start from one of the one-color looks, then change it.
	local startLabel = Text(editor, "GameFontHighlightSmall", L["Start from"])
	startLabel:SetPoint("TOPLEFT", 12, -132)
	for i, key in ipairs(FIXED) do
		local start = ns.PanelButton(editor)
		start:SetSize(68, 20)
		start:SetPoint("LEFT", startLabel, "RIGHT", 12 + (i - 1) * 72, 0)
		start:SetText(ShortName(key))
		TipOn(start, L["Fills in %s's colors, to change from there."]:format(presetInfo[key].label))
		start:SetScript("OnClick", function()
			if not draft then return end
			local top, bottom, mode = ns.GetTintPictureColors(key)
			if not top then return end
			local function own(c)
				-- (A glow keeps about a third of its color: Tint.lua's GLOW_SCALE.)
				if mode ~= "ADD" then return Copy(c) end
				return { math.min(1, c[1] / 0.35), math.min(1, c[2] / 0.35), math.min(1, c[3] / 0.35) }
			end
			draft.color = own(top)
			local same = bottom[1] == top[1] and bottom[2] == top[2] and bottom[3] == top[3]
			draft.color2 = not same and own(bottom) or nil
			draft.glow = mode == "ADD" or nil
			-- A new tint not named yet takes the look's name.
			if not draft.key and (draft.name == L["My tint"] or draft.started) then
				draft.name, draft.started = L["My %s"]:format(ShortName(key):lower()), true
				nameBox:SetText(draft.name)
			end
			RefreshAll()
		end)
	end

	local saveButton = ns.PanelButton(editor)
	saveButton:SetSize(90, 22)
	saveButton:SetPoint("BOTTOMRIGHT", -12, 10)
	saveButton:SetText(L["Save tint"])
	saveButton:SetScript("OnClick", function()
		if not draft then return end
		local name = (nameBox:GetText() or ""):match("^%s*(.-)%s*$")
		local fields = { name = name ~= "" and name or L["My tint"], color = draft.color,
			color2 = draft.color2 or false, glow = draft.glow or nil }
		local key = draft.key
		if key then
			ns.UpdateMyTint(key, fields)
		else
			fields.color2 = draft.color2
			key = ns.AddMyTint(fields)
		end
		ns.GetDB().tintPreset = key
		draft = nil
		nameBox:ClearFocus()
		Changed()
	end)
	local cancelButton = ns.PanelButton(editor)
	cancelButton:SetSize(80, 22)
	cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -6, 0)
	cancelButton:SetText(CANCEL or L["Cancel"])
	cancelButton:SetScript("OnClick", function()
		draft = nil
		nameBox:ClearFocus()
		RefreshAll()
	end)
	local deleteButton = ns.PanelButton(editor)
	deleteButton:SetSize(80, 22)
	deleteButton:SetPoint("BOTTOMLEFT", 12, 10)
	deleteButton:SetText(DELETE or L["Delete"])
	TipOn(deleteButton, L["Deletes this tint for good."])
	deleteButton:SetScript("OnClick", function()
		if draft and draft.key then ns.DeleteMyTint(draft.key) end
		draft = nil
		nameBox:ClearFocus()
		Changed()
	end)

	-- ── Strength ──────────────────────────────────────────────────────────
	local strength = Section(content, 100)
	sections[#sections + 1] = strength
	strength.tab = "look"
	Heading(kit, strength, L["Strength"], L["Applies to every look. A place can have its own on Zone mood."])
	local strengthSlider = kit.Slider(strength, "tintStrength", L["Strength"], 5, 100, 1, "%d%%", 100, function()
		ns.RefreshTint()
		UpdatePreview()
		RefreshAll()
	end)
	strengthSlider:SetWidth(300)
	strengthSlider:SetPoint("TOPLEFT", 2, -46)
	kit.Tooltip(strengthSlider, L["How strongly the tint colors the world, for every look."])
	local chips = {}
	for i, chip in ipairs(STRENGTH_CHIPS) do
		local button = Chip(strength, L[chip[1]], 76)
		button:SetPoint("LEFT", strengthSlider, "RIGHT", 18 + (i - 1) * 82, 0)
		button.value = chip[2]
		button:SetScript("OnClick", function(self)
			ns.GetDB().tintStrength = self.value
			Changed()
		end)
		chips[i] = button
	end

	-- ── Time of day: the look's time part (Time of day, Zone + time of day) ─
	local day = Section(content, 240)
	sections[#sections + 1] = day
	day.tab = "time"
	local dayHead = Heading(kit, day, L["Time of day"], L["The time-of-day part of the look; click the bar to preview any hour."])
	local clockGame = Chip(day, L["Game time"], 90)
	local clockLocal = Chip(day, L["My clock"], 90)
	clockLocal:SetPoint("TOPRIGHT", day, "TOPRIGHT", 0, 2)
	clockGame:SetPoint("RIGHT", clockLocal, "LEFT", -4, 0)
	TipOn(clockGame, L["Follows the game's own day and night."])
	TipOn(clockLocal, L["Follows your computer's clock."])
	clockGame:SetScript("OnClick", function() ns.GetDB().tintClock = "game"; Changed() end)
	clockLocal:SetScript("OnClick", function() ns.GetDB().tintClock = "local"; Changed() end)
	dayHead.note:SetPoint("RIGHT", clockGame, "LEFT", -8, 0) -- (stops short of the clock buttons)
	local CELL_W = PAGE_W / 24
	local bar = CreateFrame("Frame", nil, day)
	bar:SetSize(PAGE_W, 28)
	bar:SetPoint("TOPLEFT", 0, -30)
	local cells = {}
	for hour = 0, 23 do
		local cell = CreateFrame("Button", nil, bar)
		cell:SetSize(CELL_W, 28)
		cell:SetPoint("TOPLEFT", hour * CELL_W, 0)
		cell.fill = cell:CreateTexture(nil, "ARTWORK")
		cell.fill:SetAllPoints()
		cell.fill:SetTexture(WHITE)
		local glow = cell:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 1, 1, 0.25)
		cell.hour = hour
		TipOn(cell, function()
			return ("%02d:00 - %s"):format(hour, L[ns.GetTimeOfDayPhaseAt(hour)]) .. "\n" ..
				L["Click to preview the tint at this hour; click again to go back."]
		end)
		-- A click previews the hour; the same hour again goes back to the real time.
		cell:SetScript("OnClick", function(self)
			local db = ns.GetDB()
			db.tintPreviewHour = db.tintPreviewHour == self.hour and -1 or self.hour
			pickedPhase = nil -- (an hour, not a phase: none picked)
			Changed()
		end)
		cells[hour] = cell
	end
	local barEdges = CreateFrame("Frame", nil, bar)
	barEdges:SetAllPoints()
	Edges(barEdges)
	local marker = bar:CreateTexture(nil, "OVERLAY")
	marker:SetColorTexture(0.08, 0.06, 0, 1)
	marker:SetSize(3, 28)
	local markerTop = bar:CreateTexture(nil, "OVERLAY")
	markerTop:SetColorTexture(1, 0.82, 0, 1)
	markerTop:SetSize(9, 4)
	markerTop:SetPoint("BOTTOM", marker, "TOP", 0, 0)
	for i, text in ipairs({ "00:00", "06:00", "12:00", "18:00", "24:00" }) do
		local fs = Text(day, ns.LOOK_DIM, text)
		local x = (i - 1) * PAGE_W / 4
		if i == 1 then fs:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -3)
		elseif i == 5 then fs:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -3)
		else fs:SetPoint("TOP", bar, "BOTTOMLEFT", x, -3) end
	end
	local dayNow = Text(day, "GameFontHighlightSmall")
	dayNow:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -20)
	-- While an hour's previewed: where the real time is on the bar, and a
	-- button back to it.
	local nowMark = bar:CreateTexture(nil, "OVERLAY")
	nowMark:SetColorTexture(1, 1, 1, 0.9)
	nowMark:SetSize(1, 28)
	-- (Its label inside the bar, dark on the light colors: above it, the clock buttons.)
	local nowWords = Text(bar, ns.LOOK_TEXT, L["now"])
	nowWords:SetPoint("TOPLEFT", nowMark, "TOPRIGHT", 3, -3)
	nowWords:SetTextColor(0.08, 0.06, 0.04)

	local phaseCards = {}
	local CARD_W = math.floor((PAGE_W - 4 * GAP) / 5)
	for i, phase in ipairs(ns.GetTimePhases()) do
		local card = CreateFrame("Button", nil, day)
		card:SetSize(CARD_W, 38)
		card:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", (i - 1) * (CARD_W + GAP), -42)
		local back = card:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0.1, 0.095, 0.085, 0.95)
		local glow = card:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 1, 1, 0.08)
		card.swatch = card:CreateTexture(nil, "ARTWORK")
		card.swatch:SetSize(22, 22)
		card.swatch:SetPoint("LEFT", 8, 0)
		card.label = Text(card, ns.LOOK_TEXT, L[phase.name])
		card.label:SetPoint("TOPLEFT", card.swatch, "TOPRIGHT", 7, 1)
		card.sub = Text(card, ns.LOOK_DIM)
		card.sub:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -2)
		Edges(card)
		card.name, card.hour = phase.name, phase.hour
		TipOn(card, L["Click to change %s and see it; click again to go back."]:format(
			L[phase.name]))
		-- A click picks the phase and shows it; again (while shown), back to the real time.
		card:SetScript("OnClick", function(self)
			local db = ns.GetDB()
			if pickedPhase == self.name then
				pickedPhase, db.tintPreviewHour = nil, -1
			else
				pickedPhase = self.name
				db.tintPreviewHour = self.hour
			end
			Changed()
		end)
		phaseCards[i] = card
	end

	local phaseRow = CreateFrame("Frame", nil, day)
	phaseRow:SetSize(PAGE_W, 40)
	phaseRow:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -88)
	local phaseHint = Text(day, "GameFontHighlightSmall", L["Click a phase above to change its color and strength."])
	phaseHint:SetPoint("LEFT", phaseRow, "LEFT", 0, -6)
	phaseHint:SetTextColor(0.66, 0.63, 0.59)
	phaseRow.recordAs = content
	local phaseName = Text(phaseRow, "GameFontNormal")
	phaseName:SetPoint("LEFT", 0, -6)
	phaseName:SetWidth(90)
	local phaseSwatch = Swatch(phaseRow, 22)
	phaseSwatch:SetPoint("LEFT", 92, -6)
	TipOn(phaseSwatch, L["Click to choose this phase's color."])
	local function PhaseOf(name)
		for _, p in ipairs(ns.GetTimePhases()) do
			if p.name == name then return p end
		end
	end
	phaseSwatch:SetScript("OnClick", function()
		local phase = PhaseOf(pickedPhase)
		if not phase then return end
		local c = phase.color
		kit.OpenColorPicker(c[1], c[2], c[3], function(r, g, b)
			ns.SetTimePhaseColor(pickedPhase, { r, g, b })
			RefreshAll()
		end)
	end)
	local phaseSlider = kit.Slider(phaseRow, {
		noSettingId = true, -- (a time of day's: no one setting for /cine find)
		get = function() local p = PhaseOf(pickedPhase); return p and p.strength or 1 end,
		set = function(value) ns.SetTimePhaseStrength(pickedPhase, value) end,
	}, L["Strength"], 0, 100, 5, "%d%%", 100, function()
		ns.RefreshTint()
		UpdatePreview()
	end)
	phaseSlider:SetWidth(200)
	phaseSlider:SetPoint("LEFT", phaseSwatch, "RIGHT", 22, 0)
	local phaseReset = ns.PanelButton(phaseRow)
	phaseReset:SetSize(80, 22)
	phaseReset:SetPoint("LEFT", phaseSlider, "RIGHT", 20, 0)
	phaseReset:SetText(L["Reset"])
	TipOn(phaseReset, L["Back to the built-in color and strength."])
	phaseReset:SetScript("OnClick", function()
		ns.SetTimePhaseColor(pickedPhase, nil)
		ns.SetTimePhaseStrength(pickedPhase, nil)
		Changed()
	end)
	-- How strong the whole time part is (each phase has its own above).
	local timeSlider = kit.Slider(day, "timeTintStrength", L["Time of day strength"], 0, 100, 5, "%d%%", 100,
		function()
			ns.RefreshTint()
			UpdatePreview()
			RefreshAll()
		end)
	timeSlider:SetWidth(300)
	timeSlider:SetPoint("TOPLEFT", phaseRow, "BOTTOMLEFT", 2, -26)
	kit.Tooltip(timeSlider, L["How strongly the time-of-day part applies."])

	-- ── Zone mood: the look's zone part, for where you're standing ────────
	local place = Section(content, 250)
	sections[#sections + 1] = place
	place.tab = "zones"
	local placeHead = Heading(kit, place, L["Zone mood"], L["The zone part of the look, kept for every visit."])
	local card = CreateFrame("Frame", nil, place)
	card:SetPoint("TOPLEFT", 0, -32)
	card:SetPoint("BOTTOMRIGHT", 0, 0)
	card.recordAs = content
	local cardBack = card:CreateTexture(nil, "BACKGROUND")
	cardBack:SetAllPoints()
	cardBack:SetColorTexture(0.1, 0.095, 0.085, 0.95)
	Edges(card)
	local hereSwatch = card:CreateTexture(nil, "ARTWORK")
	hereSwatch:SetSize(30, 30)
	hereSwatch:SetPoint("TOPLEFT", 12, -12)
	local hereName = Text(card, "GameFontHighlight")
	hereName:SetPoint("TOPLEFT", hereSwatch, "TOPRIGHT", 10, 0)
	local hereMood = Text(card, "GameFontHighlightSmall")
	hereMood:SetPoint("TOPLEFT", hereName, "BOTTOMLEFT", 0, -3)
	hereMood:SetTextColor(0.66, 0.63, 0.59)

	-- What the choices below change: where you stand (the zone, or the area
	-- you're in), or another place picked from the list (editing: its name).
	local target = "zone"
	local function TargetName()
		if editing then return editing end
		local area = ns.GetAreaTintInfo()
		if target == "area" and area then return area end
		return GetRealZoneText() or ""
	end
	local function TargetColor()
		if editing then
			local _, _, _, color = ns.GetZoneTintInfo(editing)
			return color
		end
		local area, _, _, areaColor = ns.GetAreaTintInfo()
		if target == "area" and area then return areaColor end
		local _, _, _, color = ns.GetZoneTintInfo()
		return color
	end
	-- Edit a place: where you stand when it's your zone or area, else that place.
	local function Edit(name)
		local area = ns.GetAreaTintInfo()
		if name == nil or name == GetRealZoneText() then
			editing, target = nil, "zone"
		elseif name == area then
			editing, target = nil, "area"
		else
			editing = name
		end
		kit.Refresh()
	end
	local function ChangedPlaces()
		local db, list, listed = ns.GetDB(), {}, {}
		-- (The menu is first built with the page, before the saved settings
		-- are loaded: nothing changed yet then. It errored each login.)
		if not db then return list end
		for _, source in ipairs({ db.zoneTints or {}, db.zoneTintStrength or {}, db.zonePresets or {} }) do
			for zone in pairs(source) do
				if not listed[zone] then
					listed[zone] = true
					list[#list + 1] = zone
				end
			end
		end
		table.sort(list)
		return list
	end
	-- Any other place: the ones you've changed, then every zone with a mood.
	local picker
	local okPicker, pickerMenu = ns.MenuDropdown(place)
	if okPicker and pickerMenu and pickerMenu.SetupMenu then
		picker = pickerMenu
		picker:SetWidth(210)
		picker:SetPoint("TOPRIGHT", place, "TOPRIGHT", 0, 6)
		placeHead.note:SetPoint("RIGHT", picker, "LEFT", -8, 0)
		picker:SetupMenu(function(_, root)
			root:CreateRadio(L["Where you are"], function() return editing == nil end, function() Edit(nil) end)
			local changed = ChangedPlaces()
			if #changed > 0 then
				if root.CreateTitle then root:CreateTitle(L["Places you've changed"]) end
				for _, name in ipairs(changed) do
					root:CreateRadio(name, function() return editing == name end, function() Edit(name) end)
				end
			end
			if root.CreateTitle then root:CreateTitle(L["All zones"]) end
			for _, zone in ipairs(ns.GetMoodZones()) do
				root:CreateRadio(zone.name, function() return editing == zone.name end,
					function() Edit(zone.name) end)
			end
		end)
		TipOn(picker, L["Edit another place's mood without going there."])
	end
	local backHere = Chip(card, L["Back to where you are"], 160)
	backHere:SetPoint("TOPRIGHT", -12, -14)
	backHere:SetScript("OnClick", function() Edit(nil) end)
	local scopeArea = Chip(card, "", 150)
	scopeArea:SetPoint("TOPRIGHT", -12, -14)
	local scopeZone = Chip(card, L["Whole zone"], 100)
	scopeZone:SetPoint("RIGHT", scopeArea, "LEFT", -4, 0)
	TipOn(scopeZone, L["The choices below change the whole zone."])
	TipOn(scopeArea, L["The choices below change just the area you're in, over the zone's."])
	scopeZone:SetScript("OnClick", function() target = "zone"; kit.Refresh() end)
	scopeArea:SetScript("OnClick", function() target = "area"; kit.Refresh() end)

	local function SetHere(value)
		local name = TargetName()
		if name ~= "" then
			ns.SetZoneTint(name, value)
			Changed()
		end
	end
	local moodLabel = Text(card, "GameFontHighlightSmall", L["Mood"])
	moodLabel:SetPoint("TOPLEFT", 12, -54)
	local moodChips = {}
	local MOOD_ACROSS = 5
	local MOOD_W = math.floor((PAGE_W - 24 - (MOOD_ACROSS - 1) * 4) / MOOD_ACROSS)
	for i, mood in ipairs(ns.GetZoneMoods()) do
		local chip = CreateFrame("Button", nil, card)
		chip:SetSize(MOOD_W, 20)
		local col, row = (i - 1) % MOOD_ACROSS, math.floor((i - 1) / MOOD_ACROSS)
		chip:SetPoint("TOPLEFT", moodLabel, "BOTTOMLEFT", col * (MOOD_W + 4), -5 - row * 23)
		local back = chip:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0.06, 0.055, 0.05, 0.95)
		local dot = chip:CreateTexture(nil, "ARTWORK")
		dot:SetSize(13, 13)
		dot:SetPoint("LEFT", 4, 0)
		dot:SetColorTexture(mood.color[1], mood.color[2], mood.color[3], 1)
		local words = Text(chip, ns.LOOK_TEXT, mood.label)
		words:SetPoint("LEFT", dot, "RIGHT", 6, 0)
		words:SetPoint("RIGHT", -3, 0)
		words:SetWordWrap(false)
		local glow = chip:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 1, 1, 0.08)
		Edges(chip)
		chip.key = mood.key
		chip:SetScript("OnClick", function(self) SetHere(self.key) end)
		moodChips[i] = chip
	end
	local moodRows = math.ceil(#moodChips / MOOD_ACROSS)
	local builtIn = ns.PanelButton(card)
	builtIn:SetSize(110, 22)
	builtIn:SetPoint("TOPLEFT", moodLabel, "BOTTOMLEFT", 0, -10 - moodRows * 23)
	builtIn:SetText(L["Built-in mood"])
	TipOn(builtIn, L["Back to the mood Cinematic gives this place."])
	builtIn:SetScript("OnClick", function() SetHere(nil) end)
	local noTint = ns.PanelButton(card)
	noTint:SetSize(110, 22)
	noTint:SetPoint("LEFT", builtIn, "RIGHT", 6, 0)
	noTint:SetText(L["No tint here"])
	noTint:SetScript("OnClick", function() SetHere("none") end)
	local anyColor = ns.PanelButton(card)
	anyColor:SetSize(110, 22)
	anyColor:SetPoint("LEFT", noTint, "RIGHT", 6, 0)
	anyColor:SetText(L["Any color..."])
	TipOn(anyColor, L["Choose your own color for this place."])
	anyColor:SetScript("OnClick", function()
		local name = TargetName()
		if name == "" then return end
		local color = TargetColor()
		kit.OpenColorPicker(color[1], color[2], color[3], function(r, g, b)
			ns.SetZoneTint(name, { r, g, b })
			Changed()
		end)
	end)

	local function TargetStrength()
		if editing then return ns.GetZoneTintStrength(editing) end
		local area, _, _, _, areaStrength, _, areaOwn = ns.GetAreaTintInfo()
		if target == "area" and area then return areaStrength, areaOwn end
		return ns.GetZoneTintStrength(GetRealZoneText() or "")
	end
	local hereSlider = kit.Slider(card, {
		noSettingId = true, -- (a zone's: no one setting for /cine find)
		get = function() return (TargetStrength()) end,
		set = function(value)
			local name = TargetName()
			if name ~= "" then ns.SetZoneTintStrength(name, value) end
		end,
	}, L["Strength here"], 0, 100, 5, "%d%%", 100, function()
		ns.RefreshTint()
		UpdatePreview()
	end)
	hereSlider:SetWidth(200)
	hereSlider:SetPoint("TOPLEFT", builtIn, "BOTTOMLEFT", 2, -28)
	kit.Tooltip(hereSlider, L["How strong the zone looks are in this place."])
	local sameStrength = ns.PanelButton(card)
	sameStrength:SetSize(140, 22)
	sameStrength:SetPoint("LEFT", hereSlider, "RIGHT", 14, 0)
	sameStrength:SetText(L["Same as everywhere"])
	TipOn(sameStrength, L["Back to the main Strength in this place."])
	sameStrength:SetScript("OnClick", function()
		local name = TargetName()
		if name ~= "" then ns.SetZoneTintStrength(name, nil) end
		Changed()
	end)

	-- Another look in this place (left out on clients without the menu).
	local lookHere
	local ok, dropdown = ns.MenuDropdown(card)
	if ok and dropdown and dropdown.SetupMenu then
		lookHere = dropdown
		lookHere:SetWidth(170)
		lookHere:SetPoint("RIGHT", card, "RIGHT", -12, 0)
		lookHere:SetPoint("TOP", hereSlider, "TOP", 0, 4)
		lookHere:SetupMenu(function(_, root)
			local function current() return ns.GetZonePreset(TargetName()) end
			local function set(value)
				local name = TargetName()
				if name ~= "" then
					ns.SetZonePreset(name, value)
					Changed()
				end
			end
			local isArea = target == "area" and ns.GetAreaTintInfo()
			root:CreateRadio(isArea and L["Same as the zone"] or L["Same as everywhere"],
				function() return current() == nil end, function() set(nil) end)
			for _, key in ipairs(LIVING) do
				root:CreateRadio(presetInfo[key].label, function() return current() == key end, function() set(key) end)
			end
			for _, key in ipairs(FIXED) do
				root:CreateRadio(presetInfo[key].label, function() return current() == key end, function() set(key) end)
			end
			for _, mine in ipairs(ns.GetMyTints()) do
				root:CreateRadio(mine.name or "?", function() return current() == mine.key end,
					function() set(mine.key) end)
			end
		end)
		local lookLabel = Text(card, "GameFontHighlightSmall", L["Look here"])
		lookLabel:SetPoint("BOTTOMLEFT", lookHere, "TOPLEFT", 2, 3)
		TipOn(lookHere, L["A look of its own for this place, used instead of your main look."])
	end
	place:SetHeight(32 + 54 + 15 + moodRows * 23 + 10 + 22 + 28 + 16 + 18)

	-- ── Places you've changed ─────────────────────────────────────────────
	local places = Section(content, 60)
	sections[#sections + 1] = places
	places.tab = "zones"
	local placesHead = Heading(kit, places, L["Places you've changed"])
	local MAX_ROWS = 15
	local placeRows = {}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Frame", nil, places)
		row:SetSize(PAGE_W, 24)
		row:SetPoint("TOPLEFT", 0, -24 - (i - 1) * 24)
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.02 or 0.045)
		row.swatch = row:CreateTexture(nil, "ARTWORK")
		row.swatch:SetSize(14, 14)
		row.swatch:SetPoint("LEFT", 8, 0)
		row.name = Text(row, "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", row.swatch, "RIGHT", 8, 0)
		row.name:SetWidth(170)
		row.name:SetWordWrap(false)
		row.desc = Text(row, ns.LOOK_DIM)
		row.desc:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
		row.desc:SetPoint("RIGHT", row, "RIGHT", -140, 0)
		row.desc:SetWordWrap(false)
		row.stripe = stripe
		row.edit = ns.PanelButton(row)
		row.edit:SetSize(56, 20)
		row.edit:SetPoint("RIGHT", -76, 0)
		row.edit:SetText(L["Edit"])
		TipOn(row.edit, L["Loads this place into the editor above, wherever you are."])
		row.edit:SetScript("OnClick", function() if row.zone then Edit(row.zone) end end)
		row.reset = ns.PanelButton(row)
		row.reset:SetSize(66, 20)
		row.reset:SetPoint("RIGHT", -4, 0)
		row.reset:SetText(L["Reset"])
		row.reset:SetScript("OnClick", function()
			if row.zone then
				ns.SetZoneTint(row.zone, nil)
				ns.SetZoneTintStrength(row.zone, nil)
				ns.SetZonePreset(row.zone, nil)
				Changed()
			end
		end)
		row:Hide()
		placeRows[i] = row
	end
	local placesMore = Text(places, "GameFontHighlightSmall")

	-- ── Refreshing ────────────────────────────────────────────────────────
	local function PaintTile(tile, key)
		local top, bottom, mode = ns.GetTintPictureColors(key)
		local db = ns.GetDB()
		local shown = math.max(math.min(1, db.tintStrength or 1), 0.8)
		tile.scene:Tint(top, bottom, mode, top and shown)
	end

	local function DraftColors()
		local function shade(c)
			if not draft.glow then return c end
			return { c[1] * 0.35, c[2] * 0.35, c[3] * 0.35 }
		end
		return shade(draft.color), shade(draft.color2 or draft.color), draft.glow and "ADD" or "MOD"
	end

	local function Mul(a, b) return { a[1] * b[1], a[2] * b[2], a[3] * b[3] } end

	-- What the preview and the line under it show: the place being edited on
	-- the Zones tab, else where you stand. Returns the look there, the
	-- place's zone color, its strength for the zone looks (another place's),
	-- how the zone part reads, whether it's another place, and whether the
	-- look is the place's own.
	local function Shown()
		local db = ns.GetDB()
		if editing and tab == "zones" then
			local _, label, _, color = ns.GetZoneTintInfo(editing)
			return ns.GetZonePreset(editing) or db.tintPreset, color, (ns.GetZoneTintStrength(editing)),
				label .. " (" .. editing .. ")", true, ns.GetZonePreset(editing) ~= nil
		end
		local here, from = ns.GetTintPresetHere()
		local area, areaLabel, areaOwn = ns.GetAreaTintInfo()
		local zone, label = ns.GetZoneTintInfo()
		return here or db.tintPreset, (ns.GetTintPictureColors("zone")), nil,
			(areaOwn and areaLabel or label) .. " (" .. (areaOwn and area or zone) .. ")", false, from ~= nil
	end

	UpdatePreview = function()
		local db = ns.GetDB()
		if not db then return end
		if draft then
			local top, bottom, mode = DraftColors()
			scene:Tint(top, bottom, mode, math.min(1, db.tintStrength or 1))
			return
		end
		local key, zoneColor, zoneStrength, _, other = Shown()
		key = hoverKey or key
		if other and ZONE_LOOKS[key] then
			-- (Another place: its own mood and strength, with the time of day as it is now.)
			local top = zoneColor
			if key == "zonetime" then top = Mul(zoneColor, (ns.GetTintPictureColors("timeofday"))) end
			scene:Tint(top, top, "MOD", math.min(1, zoneStrength or db.tintStrength or 1))
			return
		end
		local top, bottom, mode = ns.GetTintPictureColors(key)
		scene:Tint(top, bottom, mode, top and math.min(1, ns.GetTintStrengthFor(key) or 1))
	end

	local function StatusText(key, own, other)
		local look = "|cffffd100" .. ns.GetTintPresetLabel(key) .. "|r"
		local text = other and L["In %s: %s"]:format(editing, look) or L["Right now: %s"]:format(look)
		if own then
			text = text .. " " .. L["(this place's own look)"]
		end
		return text
	end

	-- The recipe line: each part the look uses, its color and what it is now.
	local function ShowPart(part, op, color, name, value)
		part.op:SetText(op or "")
		if color then
			part.swatch:SetColorTexture(color[1], color[2], color[3], 1)
		end
		part.swatch:SetShown(color ~= nil)
		part.text:SetText("|cffffd100" .. name .. "|r" .. (value and ("  " .. value) or ""))
		part.op:Show()
		part.text:Show()
	end
	local function HidePart(part)
		part.op:Hide()
		part.swatch:Hide()
		part.text:Hide()
	end
	function RefreshRecipe(db, key, zoneColor, zoneValue, other)
		local usesZone, usesTime = ZONE_LOOKS[key], TIME_LOOKS[key]
		recipe:SetShown(usesZone or usesTime or false)
		preview:SetHeight((usesZone or usesTime) and 92 or 70)
		if not (usesZone or usesTime) then return end
		local timeValue
		if usesTime then
			local phase, hour, minute = ns.GetTimeOfDayInfo()
			if (db.tintPreviewHour or -1) >= 0 then
				timeValue = L[phase] .. (" (%02d:00, %s)"):format(hour, L["preview"])
			else
				timeValue = L[phase] .. (" (%02d:%02d)"):format(hour, minute)
			end
		end
		local timeColor = usesTime and (ns.GetTintPictureColors("timeofday")) or nil
		if usesZone and usesTime then
			local result = other and Mul(zoneColor, timeColor) or (ns.GetTintPictureColors("zonetime"))
			ShowPart(zonePart, nil, zoneColor, L["Zone mood"], zoneValue)
			ShowPart(timePart, "×", timeColor, L["Time of day"], timeValue)
			ShowPart(resultPart, "=", result, L["what you see"])
		elseif usesZone then
			ShowPart(zonePart, nil, zoneColor, L["Zone mood"], zoneValue)
			HidePart(timePart)
			HidePart(resultPart)
		else
			ShowPart(zonePart, nil, timeColor, L["Time of day"], timeValue)
			HidePart(timePart)
			HidePart(resultPart)
		end
	end

	local function RefreshTabs(key)
		for _, button in ipairs(tabButtons) do
			local on = button.key == tab
			button.mark:SetShown(on)
			if on then button.words:SetTextColor(1, 0.82, 0) else button.words:SetTextColor(0.66, 0.63, 0.59) end
		end
		if tab == "zones" and not ZONE_LOOKS[key] then
			tabNote:SetText(L["Not in your look: pick Zone or Zone + time of day."])
		elseif tab == "time" and not TIME_LOOKS[key] then
			tabNote:SetText(L["Not in your look: pick Time of day or Zone + time of day."])
		else
			tabNote:SetText("")
		end
	end

	local function RefreshLooks(db)
		for _, tile in ipairs(tiles) do
			PaintTile(tile, tile.key)
			tile:Ring(not draft and db.tintPreset == tile.key)
		end
		local mine = ns.GetMyTints()
		local across = 7
		local function Place(frame, slot)
			local col, row = (slot - 1) % across, math.floor((slot - 1) / across)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", mineLabel, "BOTTOMLEFT", col * (SMALL_W + GAP), -5 - row * (50 + GAP))
		end
		for i, tile in ipairs(fixedTiles) do Place(tile, i) end
		local first = #fixedTiles
		for i, tint in ipairs(mine) do
			local tile = mineTiles[i]
			if not tile then
				tile = LookTile(tint.key, SMALL_W, 50, 24)
				TipOn(tile, function()
					return (tile.tintName or "") .. "\n" .. L["Your own tint. Once it's picked, click it again to change it."]
				end)
				mineTiles[i] = tile
				tiles[#tiles] = nil -- (painted below, not with the built-in ones)
			end
			tile.key, tile.tintName = tint.key, tint.name
			tile.name:SetText(tint.name or "?")
			Place(tile, first + i)
			PaintTile(tile, tint.key)
			tile:Ring(db.tintPreset == tint.key and (not draft or draft.key == tint.key))
			tile:Show()
		end
		for i = #mine + 1, #mineTiles do mineTiles[i]:Hide() end
		local slots = first + #mine + 1
		Place(newTile, slots)
		newTile:Ring(draft ~= nil and draft.key == nil)
		local rows = math.ceil(slots / across)
		looks:SetHeight(24 + 17 + 60 + 12 + 17 + rows * 50 + (rows - 1) * GAP + 4)
	end

	local function RefreshEditor()
		editor.wanted = draft ~= nil
		if not draft then return end
		editorTitle:SetText(draft.key and L["Change your tint"] or L["Make your own tint"])
		if not nameBox:HasFocus() then nameBox:SetText(draft.name or "") end
		mainSwatch:SetColor(draft.color)
		for _, swatch in ipairs(paletteSwatches) do
			local c = swatch.color
			swatch:Pick(math.abs(c[1] - draft.color[1]) + math.abs(c[2] - draft.color[2])
				+ math.abs(c[3] - draft.color[3]) < 0.01)
		end
		glowCheck:SetChecked(draft.glow and true or false)
		fadeCheck:SetChecked(draft.color2 ~= nil)
		bottomSwatch:SetShown(draft.color2 ~= nil)
		if draft.color2 then bottomSwatch:SetColor(draft.color2) end
		deleteButton:SetShown(draft.key ~= nil)
	end

	local function RefreshStrength(db)
		for _, chip in ipairs(chips) do
			chip:Pick(math.abs((db.tintStrength or 1) - chip.value) < 0.005)
		end
		strength:SetHeight(66)
	end

	local function RefreshDay(db)
		clockGame:Pick(db.tintClock ~= "local")
		clockLocal:Pick(db.tintClock == "local")
		for hour = 0, 23 do
			local c = ns.GetTimeOfDayColorAt(hour)
			cells[hour].fill:SetVertexColor(c[1], c[2], c[3], 1)
		end
		local previewing = (db.tintPreviewHour or -1) >= 0
		local phase, hour, minute = ns.GetTimeOfDayInfo()
		marker:ClearAllPoints()
		marker:SetPoint("TOPLEFT", bar, "TOPLEFT", (hour + (minute or 0) / 60) * CELL_W - 1, 0)
		if previewing then
			dayNow:SetText("|cffffd100" .. L["Previewing: %s (%02d:00)"]:format(L[phase], hour) .. "|r  " ..
				L["(click it again for the real time)"])
		else
			dayNow:SetText((db.tintClock == "local" and L["Now: %s (%02d:%02d your time)"]
				or L["Now: %s (%02d:%02d game time)"]):format(L[phase], hour, minute))
		end
		nowMark:SetShown(previewing)
		nowWords:SetShown(previewing)
		if previewing then
			local realHour, realMinute
			if db.tintClock == "local" then
				local now = date("*t")
				realHour, realMinute = now.hour, now.min
			else
				realHour, realMinute = GetGameTime()
			end
			nowMark:ClearAllPoints()
			nowMark:SetPoint("TOPLEFT", bar, "TOPLEFT", ((realHour or 0) + (realMinute or 0) / 60) * CELL_W, 0)
		end
		for _, c in ipairs(phaseCards) do
			local p = PhaseOf(c.name)
			c.swatch:SetColorTexture(p.color[1], p.color[2], p.color[3], 1)
			c.sub:SetText(("%d%%"):format(p.strength * 100 + 0.5) .. ((p.own or p.ownStrength) and
				("  ·  " .. L["yours"]) or ""))
			c:Ring(c.name == pickedPhase)
		end
		-- The phase row only with a phase picked; else a hint in its place.
		local p = pickedPhase and PhaseOf(pickedPhase)
		phaseRow:SetShown(p and true or false)
		phaseHint:SetShown(not p)
		if p then
			phaseName:SetText(L[pickedPhase])
			phaseSwatch:SetColor(p.color)
			phaseReset:SetEnabled(p.own or p.ownStrength)
		end
	end

	local function RefreshPlace(db)
		local area = ns.GetAreaTintInfo()
		if not area then target = "zone" end
		local name, moodText, own, color
		if editing then
			local _, label, isOverride, c = ns.GetZoneTintInfo(editing)
			name, moodText, own, color = editing, label, isOverride, c
		else
			local zone, label, isOverride, c = ns.GetZoneTintInfo()
			name, moodText, own, color = zone ~= "" and zone or "?", label, isOverride, c
			if target == "area" and area then
				local _, areaLabel, areaOwn, areaColor = ns.GetAreaTintInfo()
				name, moodText, own, color = area .. "  (" .. zone .. ")", areaLabel, areaOwn, areaColor
			end
		end
		hereSwatch:SetColorTexture(color[1], color[2], color[3], 1)
		hereName:SetText(name)
		hereMood:SetText(moodText .. "  ·  " .. (own and L["your choice"] or L["built in"]) ..
			(editing and ("  ·  " .. L["not where you are"]) or ""))
		backHere:SetShown(editing ~= nil)
		scopeArea:SetShown(not editing and area ~= nil)
		scopeZone:SetShown(not editing and area ~= nil)
		if area and not editing then
			scopeArea:SetText(L["Just %s"]:format(area))
			scopeZone:Pick(target == "zone")
			scopeArea:Pick(target == "area")
		end
		local current = db.zoneTints and db.zoneTints[TargetName()]
		for _, chip in ipairs(moodChips) do chip:Ring(current == chip.key) end
		local _, ownStrength = TargetStrength()
		sameStrength:SetShown(ownStrength and true or false)
		if lookHere then lookHere:GenerateMenu() end
		if picker then picker:GenerateMenu() end
	end

	local function RefreshPlaces()
		local list = ChangedPlaces()
		local editingName = TargetName()
		placesHead:SetText(L["Places you've changed"] .. ((#list > 0) and ("  |cff8a8478(" .. #list .. ")|r") or ""))
		for i, row in ipairs(placeRows) do
			local zone = list[i]
			row.zone = zone
			if zone then
				local _, label, _, color = ns.GetZoneTintInfo(zone)
				row.swatch:SetColorTexture(color[1], color[2], color[3], 1)
				local strengthHere, ownStrength = ns.GetZoneTintStrength(zone)
				local preset = ns.GetZonePreset(zone)
				row.name:SetText(zone)
				row.desc:SetText(("%s%s%s"):format(
					preset and L["%s look, "]:format(ns.GetTintPresetLabel(preset)) or "", label,
					ownStrength and (L[", %d%% strength"]):format(strengthHere * 100 + 0.5) or ""))
				-- (The one in the editor above: marked gold.)
				if zone == editingName then
					row.stripe:SetColorTexture(1, 0.82, 0, 0.12)
				else
					row.stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.02 or 0.045)
				end
			end
			row:SetShown(zone ~= nil)
		end
		local shownRows = math.min(#list, MAX_ROWS)
		placesMore:ClearAllPoints()
		placesMore:SetPoint("TOPLEFT", places, "TOPLEFT", 0, -28 - shownRows * 24)
		if #list == 0 then
			placesMore:SetText(L["None yet. Pick a mood or a look above and the place shows here."])
		elseif #list > MAX_ROWS then
			placesMore:SetText((L["...and %d more."]):format(#list - MAX_ROWS))
		else
			placesMore:SetText("")
		end
		places:SetHeight(28 + shownRows * 24 + 18)
	end

	-- Above the tabs: the preview and the tabs; then each tab's own.
	sections = { preview, tabBar, looks, editor, strength, place, places, day }

	RefreshAll = function()
		local db = ns.GetDB()
		if not db then return end
		local key, zoneColor, _, zoneValue, other, own = Shown()
		status:SetText(StatusText(key, own, other))
		RefreshTabs(key)
		RefreshLooks(db)
		RefreshEditor()
		RefreshStrength(db)
		RefreshRecipe(db, key, zoneColor, zoneValue, other)
		RefreshDay(db)
		RefreshPlace(db)
		RefreshPlaces()
		UpdatePreview()
		Layout()
		-- (Page off: its tiles and pickers, not kit controls, dim and take no clicks.)
		local on = ns.PageOn("tintStyle")
		for _, section in ipairs(sections) do section:SetAlpha(on and 1 or 0.45) end
		if not on and not content.offBlock then
			local block = CreateFrame("Frame", nil, content)
			block:SetFrameLevel(content:GetFrameLevel() + 100)
			block:EnableMouse(true)
			if block.EnableMouseWheel then block:EnableMouseWheel(false) end
			content.offBlock = block
		end
		if content.offBlock then
			local block = content.offBlock
			block:ClearAllPoints()
			block:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 0, 0)
			block:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")
			block:SetShown(not on)
		end
	end
	-- One control for the whole page: kit.Refresh (a profile switch, Reset page) redraws it.
	local master = CreateFrame("Frame", nil, content)
	master:SetSize(1, 1)
	master:SetPoint("TOPLEFT")
	master.Refresh = function() RefreshAll() end
	kit.AddControl(master)

	-- Keep "Zone mood" up to date crossing a border with the page open.
	local watcher = CreateFrame("Frame", nil, canvas)
	watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	watcher:RegisterEvent("ZONE_CHANGED")
	watcher:SetScript("OnEvent", function()
		if canvas:IsVisible() then RefreshAll() end
	end)

	canvas:SetScript("OnShow", kit.PageShown(function()
		ns.SetTintPreview(true)
		kit.Refresh()
	end, content))
	canvas:SetScript("OnHide", function()
		ns.SetTintPreview(false)
		draft, hoverKey, editing, pickedPhase = nil, nil, nil, nil
	end)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Tint Style", L["Tint"])
end
