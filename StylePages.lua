-- What the Style hub's pages made in their own files share (LetterboxStyle.lua,
-- QuestItemStyle.lua): rows of choices, color swatches, sliders and a row of
-- presets, each greyed out unless the page's switch (or its own test) says,
-- and each change shown at once (changed()).

local ADDON_NAME, ns = ...

-- The Style hub's General page: a switch for every Style page at once (off:
-- each shows the game's look), and settings the pages share. A page's
-- shared setting (ns.ShareStyle) starts on General ("general", or -1 for an
-- outline): it follows General's value until it's given one of its own.
-- General's own "game" (texture, font) and -1 (outline) leave each page at
-- its own default.
ns.DEFAULTS.styleGeneral = true
ns.DEFAULTS.styleTexture = "game"
ns.DEFAULTS.styleFont = "game"
ns.DEFAULTS.styleOutline = -1
ns.DEFAULTS.styleShadow = "game"     -- "game" (each page's own), "on" or "none" (ns.SetTextShadow)

ns.DEFAULTS.styleBorder = "game"     -- "game" (each page's own), "none", "thin", "thick" or "custom":
ns.DEFAULTS.styleBorderSize = 1      -- ...custom's thickness, in pixels
ns.DEFAULTS.styleBorderR, ns.DEFAULTS.styleBorderG, ns.DEFAULTS.styleBorderB = 0, 0, 0 -- ...and color

local GENERAL_KEYS = { texture = "styleTexture", font = "styleFont", outline = "styleOutline", shadow = "styleShadow",
	border = "styleBorder",
	borderSize = "styleBorderSize", borderR = "styleBorderR", borderG = "styleBorderG", borderB = "styleBorderB" }
-- The pages' shared settings (each defaults to General in its own file):
-- [key] = { kind, own: its value with General at the game's (its default
-- before General), map: General's value as the page takes it }.
local CAST_OUTLINES = { [0] = "none", "thin", "thick" }
local shared = {
	prdTexture = { kind = "texture", own = "game" },
	tooltipBarTexture = { kind = "texture", own = "game" },
	rollBarTexture = { kind = "texture", own = "flat" },
	plateCastFill = { kind = "texture", own = "game" },
	bubblesFont = { kind = "font", own = "game" },
	tooltipFont = { kind = "font", own = "game" },
	questTalkFont = { kind = "font", own = "game" },
	rollFont = { kind = "font", own = "game" },
	questItemFont = { kind = "font", own = "game" },
	plateCastFont = { kind = "font", own = "game" },
	bubblesOutline = { kind = "outline", own = 0 },
	tooltipOutline = { kind = "outline", own = 0 },
	questTalkOutline = { kind = "outline", own = 0 },
	rollOutline = { kind = "outline", own = 0 },
	questItemOutline = { kind = "outline", own = 1 },
	plateCastOutline = { kind = "outline", own = "game", map = function(value) return CAST_OUTLINES[value] end },
	tooltipShadow = { kind = "shadow", own = "game" },
	questTalkShadow = { kind = "shadow", own = "game" },
	rollShadow = { kind = "shadow", own = "game" },
	questItemShadow = { kind = "shadow", own = "game" },
	plateCastShadow = { kind = "shadow", own = "game" },
	-- (The Cards page's, each event's too: Cards.lua puts them in.)
}
-- Borders: each page's border (its own default "own"), and its Custom's
-- thickness and color (<key>Size, <key>R/G/B), which follow General's while
-- the border's on General.
for key, own in pairs({ prdBorder = "game", tooltipEdge = "game", bubblesEdge = "thin", plateCastBorder = "game",
	questItemFrame = "game" }) do
	shared[key] = { kind = "border", own = own }
	ns.DEFAULTS[key .. "Size"] = ns.DEFAULTS[key .. "Size"] or 1
	shared[key .. "Size"] = { kind = "borderSize", follows = key }
	for _, channel in ipairs({ "R", "G", "B" }) do
		ns.DEFAULTS[key .. channel] = ns.DEFAULTS[key .. channel] or 0
		shared[key .. channel] = { kind = "border" .. channel, follows = key }
	end
end
-- The Visions hub's Style page (VisionsStyle.lua): a step between the
-- Visions' shared settings and General. A Vision's setting on "general"
-- follows it; its own start on General ("general", -1) and follow that, and
-- its "game" leaves each Vision at its own default.
ns.DEFAULTS.visionStyleTexture = "general"
ns.DEFAULTS.visionStyleFont = "general"
ns.DEFAULTS.visionStyleOutline = -1
ns.DEFAULTS.visionStyleShadow = "general"
ns.DEFAULTS.visionStyleBorder = "general"
ns.DEFAULTS.visionStyleBorderSize = 1
ns.DEFAULTS.visionStyleBorderR, ns.DEFAULTS.visionStyleBorderG, ns.DEFAULTS.visionStyleBorderB = 0, 0, 0
ns.DEFAULTS.visionStyleTextSize = 1 -- times each Vision's own text size
local VISION_KEYS = { texture = "visionStyleTexture", font = "visionStyleFont", outline = "visionStyleOutline",
	shadow = "visionStyleShadow", border = "visionStyleBorder", borderSize = "visionStyleBorderSize",
	borderR = "visionStyleBorderR", borderG = "visionStyleBorderG", borderB = "visionStyleBorderB" }
-- Its own follow General as a page's do (shown "Interface Style (X)").
shared.visionStyleTexture = { kind = "texture", own = "game", visionsHub = true }
shared.visionStyleFont = { kind = "font", own = "game", visionsHub = true }
shared.visionStyleOutline = { kind = "outline", own = "game", visionsHub = true }
shared.visionStyleShadow = { kind = "shadow", own = "game", visionsHub = true }
shared.visionStyleBorder = { kind = "border", own = "game", visionsHub = true }
shared.visionStyleBorderSize = { kind = "borderSize", follows = "visionStyleBorder" }
for _, channel in ipairs({ "R", "G", "B" }) do
	shared["visionStyleBorder" .. channel] = { kind = "border" .. channel, follows = "visionStyleBorder" }
end
-- The Visions' shared settings, by how their keys start: Damage Vision's,
-- Roll Vision's, Quest Vision's two Style tabs' and Card Vision's (theirs
-- put in later, by their own files, marked as they come).
local VISION_PREFIXES = { "damageVision", "roll", "questTalk", "questItem", "card", "emote" }
local function MarkVision(key, entry)
	if type(entry) ~= "table" or type(key) ~= "string" then return end
	for _, prefix in ipairs(VISION_PREFIXES) do
		if key:sub(1, #prefix) == prefix then entry.visions = true return end
	end
end
for key, entry in pairs(shared) do MarkVision(key, entry) end
setmetatable(shared, { __newindex = function(list, key, entry)
	MarkVision(key, entry)
	rawset(list, key, entry)
end })
-- Each Vision's text size, times Visions Style's (Cards.lua's cardScale too).
local VISION_SIZES = { damageVisionTextSize = true, questTalkTextSize = true, rollTextSize = true }
function ns.VisionTextScale()
	local db = ns.db
	return db and db.styleGeneral and tonumber(db.visionStyleTextSize) or 1
end
ns.SHARED_STYLE = shared -- (the General page's list of who follows it)

local function IsGeneral(value)
	return value == "general" or value == -1
end
ns.IsGeneralStyle = IsGeneral

-- Where a shared setting's "general" takes it, for its first choice's name:
-- a Vision's to Visions Style, Visions Style's own to the Style hub's General.
function ns.SharedStyleSource(key)
	local entry = shared[key]
	if entry and entry.visions then return ns.L["Visions Style"] end
	if entry and entry.visionsHub then return ns.L["Interface Style"] end
	return ns.L["General"]
end

-- What General (and for a Vision, Visions Style first) gives a shared setting
-- now (gameOnly: General off, or the page: its own default).
local function FromGeneral(entry, gameOnly)
	local db = ns.db
	if gameOnly or not (db and db.styleGeneral) then return entry.own end
	local value = entry.visions and db[VISION_KEYS[entry.kind]] or nil
	if value == nil or IsGeneral(value) then value = db[GENERAL_KEYS[entry.kind]] end
	if value == nil or value == "game" or value == -1 then
		return entry.own
	end
	return entry.map and entry.map(value) or value
end

-- Whether a Style page (its switch's key) is on: General's and its own.
-- (db: the settings to ask, for the options' tests; else the saved ones.)
function ns.StyleOn(switchKey, db)
	-- (Live, a page standing aside for another addon's own look: Addon Conflicts' Theirs.)
	if switchKey and (db == nil or db == ns.db) and ns.StyleSwitchYielded(switchKey) then return false end
	db = db or ns.db
	return db and db.styleGeneral and (not switchKey or db[switchKey]) and true or false
end

-- A page's look, read as its code reads the settings: its own while it's
-- on, else its defaults; a shared setting on General as General says.
-- (off: its defaults whatever the switch says, for a part the page leaves be.)
local looks = {}
function ns.StyleLook(switchKey, off)
	local pair = looks[switchKey]
	if not pair then
		local function Proxy(on)
			return setmetatable({}, { __index = function(_, key)
				local source = on and ns.db or ns.DEFAULTS
				local value = source and source[key]
				local entry = shared[key]
				if entry and entry.follows then
					-- (A border's thickness or color: General's while that border's on
					-- General, or Visions Style's while a Vision's is on one of its own.)
					local db = ns.db
					if on and db and db.styleGeneral and IsGeneral(source[entry.follows]) then
						local from = (entry.visions and not IsGeneral(db.visionStyleBorder)) and VISION_KEYS or GENERAL_KEYS
						if db[from.border] == "custom" then return db[from[entry.kind]] end
					end
					return value
				end
				if entry and IsGeneral(value) then
					return FromGeneral(entry, not on)
				end
				if on and VISION_SIZES[key] then
					return (tonumber(value) or 1) * ns.VisionTextScale()
				end
				return value
			end })
		end
		pair = { on = Proxy(true), off = Proxy(false) }
		looks[switchKey] = pair
	end
	return (not off and ns.StyleOn(switchKey)) and pair.on or pair.off
end

-- A page's border as look says (key: its border setting): "game", "none",
-- "colored" (Tooltips: the unit's or item's color) or "line", then a line's
-- thickness and color. Thin and Thick: 1 and 2 pixels, in thinColor (black
-- if not given); Custom: the page's own (or General's) thickness and color.
function ns.StyleBorder(look, key, thinColor)
	local value = look[key]
	local color = thinColor or { 0, 0, 0 }
	if value == "thin" or value == "thick" then
		return "line", value == "thick" and 2 or 1, color[1], color[2], color[3]
	elseif value == "custom" then
		return "line", math.max(1, math.floor(tonumber(look[key .. "Size"]) or 1)),
			tonumber(look[key .. "R"]) or 0, tonumber(look[key .. "G"]) or 0, tonumber(look[key .. "B"]) or 0
	elseif value == "colored" then
		return "colored", 1
	end
	return value or "game", 0
end

-- Four lines round a frame (made once: ns.DressStyleEdges places them).
local EDGE_SIDES = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
	{ "TOPRIGHT", "BOTTOMRIGHT" } }
function ns.MakeStyleEdges(around, layer)
	local holder = CreateFrame("Frame", nil, around)
	holder:SetAllPoints()
	holder:SetFrameLevel(around:GetFrameLevel() + 2)
	holder.lines = {}
	for i = 1, 4 do
		local line = holder:CreateTexture(nil, layer or "OVERLAY")
		line:SetTexture("Interface\\Buttons\\WHITE8X8")
		holder.lines[i] = line
	end
	return holder
end

-- size pixels thick, in r, g, b (a: its alpha); outside: just outside the
-- frame (else just inside it).
function ns.DressStyleEdges(holder, size, r, g, b, a, outside)
	local key = ("%s:%s"):format(size, outside and 1 or 0)
	if holder.placed ~= key then
		holder.placed = key
		local out = outside and size or 0
		for i, side in ipairs(EDGE_SIDES) do
			local line = holder.lines[i]
			line:ClearAllPoints()
			if i <= 2 then
				local y = i == 1 and out or -out
				line:SetPoint(side[1], holder, side[1], -out, y)
				line:SetPoint(side[2], holder, side[2], out, y)
				line:SetHeight(size)
			else
				local x = i == 3 and -out or out
				line:SetPoint(side[1], holder, side[1], x, 0)
				line:SetPoint(side[2], holder, side[2], x, 0)
				line:SetWidth(size)
			end
		end
	end
	for _, line in ipairs(holder.lines) do line:SetVertexColor(r, g, b, a or 1) end
	-- (Round a panel, marked by whoever made it: the style theme's ornament.)
	if holder.ornate and ns.DressThemeCorners then ns.DressThemeCorners(holder, a) end
end

-- A shared setting's value as a page would show it now (for the options:
-- "General (Glass)").
function ns.GeneralStyleValue(key)
	local entry = shared[key]
	return entry and FromGeneral(entry, false)
end

-- The previews' backdrop: a lake at dusk, 2:1 (Media/make_letterbox_scene.py).
local SCENE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\LetterboxScene"

local scenes = setmetatable({}, { __mode = "k" }) -- (frame -> { focus, shade })

-- The scene behind frame (made once, then cut again: call it as frame's size
-- changes), cut to frame's shape from its middle, never stretched: a wide
-- strip shows the band at focus (0 top, 1 bottom: the hills and the lake,
-- 0.55, by default). shade: darker, for text over it (1: as it is).
-- (Cut again for a frame's new size, as it was set up: the General page's
-- previews, held to one size.)
function ns.RecutStyleScene(frame)
	local how = scenes[frame]
	if how then ns.StyleScene(frame, how[1], how[2]) end
end

function ns.StyleScene(frame, focus, shade)
	scenes[frame] = { focus, shade }
	local scene = frame.styleScene
	if not scene then
		scene = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		scene:SetAllPoints()
		frame.styleScene = scene
		-- (Cut again at each new size: one sized by its anchors, as General's
		-- screens, is cut before it has its width.)
		frame:HookScript("OnSizeChanged", ns.RecutStyleScene)
	end
	scene:SetTexture(SCENE)
	shade = shade or 1
	scene:SetVertexColor(shade, shade, shade, 1)
	local width, height = frame:GetWidth(), frame:GetHeight()
	local aspect = (width and height and height > 0) and width / height or 2
	if aspect >= 2 then
		local part = 2 / aspect
		local top = math.min(math.max((focus or 0.55) - part / 2, 0), 1 - part)
		scene:SetTexCoord(0, 1, top, top + part)
	else
		local cut = (1 - aspect / 2) / 2
		scene:SetTexCoord(cut, 1 - cut, 0, 1)
	end
	return scene
end

-- A toggle button's look: its text gold while it's on, grey while it's off
-- (its normal font: the mouse over it still lights it, as any button).
function ns.StyleToggle(button, on)
	button:SetNormalFontObject(on and "GameFontNormal" or "GameFontDisable")
end

-- A Visions hub page's link to its Style hub page: a small Style button right
-- of the page's title, past its "?" (PageIntro). page: the Style page's name,
-- as ns.OpenOptions takes it. Tooltip: the page's (Options.lua's). label: its
-- text when not just Style (a page with more than one Style page), after: the
-- link it goes right of (else the title).
function ns.StyleLink(content, title, page, tip, Tooltip, label, after)
	local button = ns.PanelButton(content)
	button:SetSize(70, 20)
	button:SetText(label or ns.L["Style"])
	button:SetWidth(math.max(70, button:GetFontString():GetStringWidth() + 24))
	if after then
		button:SetPoint("LEFT", after, "RIGHT", 6, 0)
	else
		button:SetPoint("LEFT", title, "RIGHT", 44, 0)
		-- (moved right of the page's on/off switch, if it has one: Options.lua)
		button.linkTitle = title
		if not content.titleLink then content.titleLink = button end
	end
	Tooltip(button, tip)
	button:SetScript("OnClick", function() ns.OpenOptions(page) end)
	return button
end

-- Folder tabs at the top of a page split into pages (Vitals Vision's Vision
-- and Style, each its own hub page with one icon: tabOf in Options.lua's
-- HUBS). list: { label, page, tip } each (page: its English name), picked:
-- this page's. Gives the panel (its line); the page's title goes under it.
function ns.PageTabs(content, list, picked)
	local tabs = {}
	for i, each in ipairs(list) do tabs[i] = { each[1], each[3] } end
	local panel, tabFrames, Show, base = ns.FolderTabs(content, tabs, function(i)
		-- (list[i][4]: opens its page even while picked, from a page under it)
		if i ~= picked or list[i][4] then ns.ShowHubPage(list[i][2]) end
	end, nil, nil, function(i) ns.FlipPageSwitch(list[i][2]) end)
	tabFrames.shotSkip = true -- (each its own page: PageShots.lua shoots those on their own)
	-- (A right-click flips that tab's page switch: on or off on its tip.)
	for i, tab in ipairs(tabFrames) do
		tab:HookScript("OnEnter", function(self) ns.PageSwitchTip(self, list[i][2]) end)
	end
	base:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -(ns.FOLDER_TAB_HEIGHT + 16))
	-- (the panel: just its top edge, a line across the page under the tabs)
	panel:SetPoint("TOPLEFT", base)
	panel:SetPoint("RIGHT", content, "RIGHT", -8, 0)
	panel:SetHeight(1)
	Show(picked)
	-- (kept on screen over the page's off card, to reach the other tabs)
	content.pageTabs = { panel = panel, frames = tabFrames }
	return panel
end

-- A Vision page's two tabs: Vision (vision, its page) and Style (style's),
-- picked 1 or 2, a tip each. title: the page's, put under them.
function ns.VisionTabs(content, title, vision, style, picked, visionTip, styleTip)
	local L = ns.L
	local panel = ns.PageTabs(content, {
		{ L["Vision"], vision, visionTip },
		{ L["Style"], style, styleTip },
	}, picked)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
	return panel
end

-- Quest Vision's three tabs: Vision, Dialogue and Quest Item Button
-- (picked 1, 2 or 3). title: the page's, put under them.
function ns.QuestTabs(content, title, picked)
	local L = ns.L
	local panel = ns.PageTabs(content, {
		{ L["Vision"], "Quest Vision", L["Quest mobs' nameplates and marks, the quest item button, the glow on " ..
			"quest objects, and where the dialogue sits."] },
		{ L["Dialogue"], "Quest Talk Style", L["How the dialogue looks, the \"Show the game's window\" link and " ..
			"the number keys."] },
		{ L["Quest Item Button"], "Quest Item Style", L["How the quest item button looks."] },
	}, picked)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
	return panel
end

-- A page's one Test button, in its preview's top right corner (over what the
-- preview draws). tip: its tooltip. kit: the page's (Tooltip, AddControl).
-- Works with the page's switch off too; give it a Refresh to grey it.
function ns.StylePreviewTest(preview, kit, tip, onClick)
	local button = ns.PanelButton(preview)
	button:SetSize(70, 20)
	button:SetText(ns.L["Test"])
	button:SetPoint("TOPRIGHT", -6, -6)
	button:SetFrameLevel(preview:GetFrameLevel() + 20)
	kit.Tooltip(button, tip)
	button:SetScript("OnClick", onClick)
	button.Refresh = function() end
	button.pageSwitch = false
	kit.AddControl(button)
	-- (A Pop out button already there moves left of it: StylePopout.)
	local pop = preview.popButton or (preview:GetParent() and preview:GetParent().popButton)
	preview.styleTest = button
	if pop then
		pop:ClearAllPoints()
		pop:SetPoint("RIGHT", button, "LEFT", -6, 0)
	end
	return button
end

-- Pop out: a preview's button that lifts the preview itself into a window of
-- its own, larger, that you can drag anywhere and resize from its corner, so
-- it stays in sight as you scroll down its page; it plays on as it does on
-- the page. Again (or the window's X, Escape, or leaving the page) puts it
-- back. While it's out, a dark frame of its size holds its place (click it to
-- put it back), and what was placed from it is placed from that instead. One
-- preview out at a time; the size you give the window is kept for the next.
-- The window sits docked beside the settings to start with; its own Pop out
-- lets you drag it anywhere (kept for next time, stylePreviewPos), Dock puts
-- it back beside them (as the camera script preview does).
-- tooltip: the page's (kit.Tooltip, Options.lua's Tooltip).
local POPOUT_SCALE = 1.5
local POPOUT_MIN_SCALE = 0.75
local popWindow, popped, popScale, popTooltip

-- Everything on parent placed from from, placed from to instead.
local function Repoint(parent, from, to)
	local function Swap(object)
		if object == from or object == to or not object.GetNumPoints then return end
		local moved = {}
		for i = 1, object:GetNumPoints() do
			local point, relative, relPoint, x, y = object:GetPoint(i)
			if relative == from then moved[#moved + 1] = { point, relPoint, x, y } end
		end
		for _, each in ipairs(moved) do object:SetPoint(each[1], to, each[2], each[3], each[4]) end
	end
	for _, child in ipairs({ parent:GetChildren() }) do Swap(child) end
	for _, region in ipairs({ parent:GetRegions() }) do Swap(region) end
end

local function PutBack()
	local preview = popped
	if not preview then return end
	popped = nil
	local slot = preview.popSlot
	preview:SetScale(1)
	preview:SetParent(slot:GetParent())
	preview:ClearAllPoints()
	for _, each in ipairs(slot.points) do preview:SetPoint(unpack(each)) end
	Repoint(slot:GetParent(), slot, preview)
	slot:Hide()
	preview.popButton:SetText(ns.L["Pop out"])
	popWindow:Hide()
	if preview.Refresh then preview:Refresh() end
end

-- The settings window a preview's page is in (to dock beside).
local function SettingsWindow(frame)
	while frame and frame:GetParent() and frame:GetParent() ~= UIParent do frame = frame:GetParent() end
	return frame
end

-- Docked beside the settings, or where you dragged it (popped out).
local function PlaceWindow()
	local saved = ns.db and ns.db.stylePreviewPos
	popWindow:ClearAllPoints()
	if type(saved) == "table" and saved.x and saved.y then
		popWindow:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
		popWindow.dock:SetText(ns.L["Dock"])
		return
	end
	local settings = popped and popped.popSlot and SettingsWindow(popped.popSlot)
	if settings and settings ~= UIParent and settings:IsShown() then
		popWindow:SetPoint("TOPLEFT", settings, "TOPRIGHT", 4, 0)
	else
		popWindow:SetPoint("TOP", UIParent, "TOP", 0, -60)
	end
	popWindow.dock:SetText(ns.L["Pop out"])
end

-- The window's size: the preview's, scaled, with room for the title.
local function FitWindow()
	if not popped then return end
	local scale = popped:GetScale()
	popWindow:SetSize(popped:GetWidth() * scale + 24, popped:GetHeight() * scale + 42)
	popped.popSlot:SetHeight(popped:GetHeight())
end

-- The popped preview at scale (kept between the smallest and what the screen
-- holds), in the window's top left.
local function ScalePopped(scale)
	local width, height = math.max(popped:GetWidth(), 1), math.max(popped:GetHeight(), 1)
	local most = math.min(UIParent:GetWidth() * 0.95 / width, (UIParent:GetHeight() - 60) / height)
	local least = math.min(POPOUT_MIN_SCALE, most)
	scale = math.max(least, math.min(scale, most))
	-- (The window's corner can't go past the preview's own smallest and largest.)
	local minW, minH = width * least + 24, height * least + 42
	local maxW, maxH = width * most + 24, height * most + 42
	if popWindow.SetResizeBounds then
		popWindow:SetResizeBounds(minW, minH, maxW, maxH)
	elseif popWindow.SetMinResize then
		popWindow:SetMinResize(minW, minH)
		popWindow:SetMaxResize(maxW, maxH)
	end
	popped:SetScale(scale)
	popped:ClearAllPoints()
	popped:SetPoint("TOPLEFT", popWindow, "TOPLEFT", 12 / scale, -30 / scale)
	return scale
end

-- While you drag the corner, the preview grows to fill what the window
-- allows; letting go fits the window back around it.
local function Resizing(window)
	if not (popped and window.sizing) then return end
	local width, height = window:GetSize()
	popScale = ScalePopped(math.min((width - 24) / math.max(popped:GetWidth(), 1),
		(height - 42) / math.max(popped:GetHeight(), 1)))
end

local function Window()
	if popWindow then return popWindow end
	popWindow = CreateFrame("Frame", "CinematicPreviewWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	popWindow:SetFrameStrata("DIALOG")
	popWindow:SetToplevel(true)
	popWindow:SetClampedToScreen(true)
	popWindow:EnableMouse(true)
	popWindow:SetMovable(true)
	popWindow:RegisterForDrag("LeftButton")
	-- (Docked, it stays beside the settings: Pop out first to drag it.)
	popWindow:SetScript("OnDragStart", function(self)
		local saved = ns.db and ns.db.stylePreviewPos
		if type(saved) == "table" and saved.x then self:StartMoving() end
	end)
	popWindow:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if ns.db then ns.db.stylePreviewPos = { x = self:GetLeft(), y = self:GetTop() } end
		PlaceWindow()
	end)
	popWindow:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	if ns.SkinWindow then ns.SkinWindow(popWindow) end
	tinsert(UISpecialFrames, "CinematicPreviewWindow") -- Escape closes it
	ns.CloseWithSettings(popWindow) -- (and closing the settings)
	popWindow.title = popWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	popWindow.title:SetPoint("TOPLEFT", 14, -10)
	local close = CreateFrame("Button", nil, popWindow, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	popWindow.dock = ns.PanelButton(popWindow)
	popWindow.dock:SetSize(70, 20)
	popWindow.dock:SetPoint("TOPRIGHT", -28, -6)
	popWindow.dock:SetText(ns.L["Pop out"])
	popWindow.dock:SetScript("OnClick", function()
		if not ns.db then return end
		local saved = ns.db.stylePreviewPos
		if type(saved) == "table" and saved.x then
			ns.db.stylePreviewPos = nil
		else
			ns.db.stylePreviewPos = { x = popWindow:GetLeft() + 30, y = popWindow:GetTop() - 30 }
		end
		PlaceWindow()
	end)
	if popTooltip then
		popTooltip(popWindow.dock, ns.L["Pop out: drag the window anywhere (by its edge). Dock: back beside the settings."])
	end
	-- The corner grip (the chat frames' own) resizes it.
	popWindow:SetResizable(true) -- (its bounds: ScalePopped)
	local grip = CreateFrame("Button", nil, popWindow)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel(popWindow:GetFrameLevel() + 40)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnMouseDown", function()
		popWindow.sizing = true
		popWindow:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		popWindow:StopMovingOrSizing()
		popWindow.sizing = nil
		FitWindow()
		PlaceWindow() -- (sizing moved its anchor: back where it goes, docked or not)
	end)
	popWindow:SetScript("OnSizeChanged", Resizing)
	popWindow:SetScript("OnHide", function()
		if popWindow.sizing then
			popWindow:StopMovingOrSizing()
			popWindow.sizing = nil
		end
		PutBack()
	end)
	popWindow:Hide()
	return popWindow
end

local function PopOut(preview)
	PutBack()
	local window = Window()
	local parent = preview:GetParent()
	local slot = preview.popSlot
	if not slot then
		slot = CreateFrame("Button", nil, parent)
		-- (leaving the page puts it back: the slot hides with the page)
		slot:SetScript("OnHide", function() if popped == preview then PutBack() end end)
		slot:SetScript("OnClick", function() if popped == preview then PutBack() end end)
		local bg = slot:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.6)
		local hover = slot:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.05)
		slot.label = slot:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		slot.label:SetPoint("CENTER")
		preview.popSlot = slot
		preview:HookScript("OnSizeChanged", FitWindow)
	end
	slot.points = {}
	for i = 1, preview:GetNumPoints() do slot.points[i] = { preview:GetPoint(i) } end
	slot:ClearAllPoints()
	for _, each in ipairs(slot.points) do slot:SetPoint(unpack(each)) end
	slot:SetSize(preview:GetWidth(), preview:GetHeight())
	slot.label:SetText(ns.L["Showing in its own window. Click here to put it back."])
	slot:Show()
	Repoint(parent, preview, slot)
	popped = preview
	window.title:SetText(preview.popTitle or ns.L["Preview"])
	preview:SetParent(window)
	ScalePopped(popScale or POPOUT_SCALE)
	preview.popButton:SetText(ns.L["Put back"])
	window:Show()
	FitWindow()
	PlaceWindow()
	if preview.Refresh then preview:Refresh() end
end

-- Every preview the page's width (from the column's edge to the page's right,
-- less a margin), 270 high at 16:9: the height a 480-wide one has at the
-- screen's shape (as the full-screen ones need). headHeight: room over the
-- screen (General's, its name). A spot of its size holds where the stack put
-- it (the stack places what's next from the spot: stackSpot), the preview on
-- its top left. Set again as it shows (and a frame later, once the page is
-- laid out) and when the page is resized.
local PREVIEW_W, PAGE_MARGIN = 480, 16
function ns.StylePreviewHeight()
	return math.floor(PREVIEW_W * UIParent:GetHeight() / math.max(UIParent:GetWidth(), 1) + 0.5)
end
-- Gives true if it was resized and refreshed.
local function FitPreview(preview)
	if popped == preview or not preview.stackSpot then return end
	local left, right = preview.stackSpot:GetLeft(), preview.stackSpot:GetParent():GetRight()
	-- (Not laid out yet: left as it is, not shrunk back; OnShow fits it again.)
	if not (left and right) then return end
	local width = math.max(PREVIEW_W, math.floor(right - left - PAGE_MARGIN))
	local height = ns.StylePreviewHeight() + (preview.headHeight or 0)
	if math.abs(preview:GetWidth() - width) < 0.5 and math.abs(preview:GetHeight() - height) < 0.5 then return end
	preview:SetSize(width, height)
	ns.RecutStyleScene(preview)
	-- (Not before the settings are there to draw from: the pages are built
	-- while the addon loads, and count as shown then. Its OnShow fits it again.)
	if preview.Refresh and ns.db and preview:IsVisible() then
		preview:Refresh()
		return true
	end
end
-- (A preview's own Refresh fits it first: one left narrow is caught on a replay.)
ns.FitStylePreview = FitPreview

local function WidePreview(preview)
	local parent = preview:GetParent()
	local spot = CreateFrame("Frame", nil, parent)
	for i = 1, preview:GetNumPoints() do spot:SetPoint(preview:GetPoint(i)) end
	spot:SetSize(preview:GetWidth(), preview:GetHeight())
	preview.stackSpot = spot
	preview:ClearAllPoints()
	preview:SetPoint("TOPLEFT", spot, "TOPLEFT")
	preview:HookScript("OnSizeChanged", function(self, width, height)
		if popped ~= self then spot:SetSize(width, height) end
	end)
	FitPreview(preview)
	preview:HookScript("OnShow", function(self)
		FitPreview(self)
		C_Timer.After(0, function() FitPreview(self) end)
	end)
	parent:HookScript("OnSizeChanged", function()
		if preview:IsVisible() then FitPreview(preview) end
	end)
end

function ns.StylePopout(preview, tooltip, title)
	popTooltip = popTooltip or tooltip
	WidePreview(preview)
	local button = ns.PanelButton(preview)
	button:SetSize(80, 20)
	button:SetText(ns.L["Pop out"])
	button:SetFrameLevel(preview:GetFrameLevel() + 30)
	if preview.styleTest then
		button:SetPoint("RIGHT", preview.styleTest, "LEFT", -6, 0)
	else
		button:SetPoint("TOPRIGHT", -6, -6)
	end
	tooltip(button, ns.L["Shows the preview larger, in a window of its own beside the settings (its Pop out lets " ..
		"you move it anywhere) that you can resize from its corner, so you can watch it while you scroll down the " ..
		"page. Click again to put it back."])
	button:SetScript("OnClick", function()
		if popped == preview then PutBack() else PopOut(preview) end
	end)
	preview.popButton, preview.popTitle = button, title
	return button
end

-- The bar textures the Style pages offer: the game's own files, its modern
-- frames' fills (atlases: only those this client has), our own
-- (Media/make_bar_textures.py), then any that other addons share through
-- LibSharedMedia (none of theirs bundled). Each setting holds a value:
-- "game" (the part's own, left alone), one of these by name, or
-- "lsm:<its name>". { value, name, file or atlas, atlas = true } each. The
-- game's modern fills come in their own colors (mana's blue, the cast bars'
-- gold): turned grey, so they take the bar's color as the rest do.
local OURS = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Bars\\"
local TEXTURES = {
	{ "flat", "Flat", "Interface\\Buttons\\WHITE8X8" },
	{ "smooth", "Smooth", "Interface\\TargetingFrame\\UI-StatusBar" },
	{ "raid", "Raid frame", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
	{ "raidpower", "Raid frame power", "Interface\\RaidFrame\\Raid-Bar-Resource-Fill" },
	{ "oldtarget", "Old target frame", "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
	{ "skills", "Skill bar", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
	{ "playerhealth", "Player frame health", "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health", atlas = true },
	{ "playermana", "Player frame mana", "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana", atlas = true },
	{ "targethealth", "Target frame health", "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health", atlas = true },
	-- (Retail's nameplates' fill, the same in every one of its Styles, and the Cooldown Manager's.)
	{ "platemodern", "Nameplate", "UI-HUD-CoolDownManager-Bar", atlas = true },
	{ "castbar", "Cast bar", "UI-CastingBar-Filling-Standard", atlas = true },
	{ "channelbar", "Channel bar", "UI-CastingBar-Filling-Channel", atlas = true },
	{ "glass", "Glass", OURS .. "Glass" },
	{ "soft", "Soft", OURS .. "Soft" },
	{ "striped", "Striped", OURS .. "Striped" },
	{ "minimal", "Minimal", OURS .. "Minimal" },
	{ "rounded", "Rounded", OURS .. "Rounded" },
	-- (The style themes': StyleThemes.lua, Media/make_theme_art.py.)
	{ "gilt", "Gilt", OURS .. "Gilt" },
	{ "forged", "Forged", OURS .. "Forged" },
	{ "lunar", "Lunar", OURS .. "Lunar" },
	{ "rime", "Rime", OURS .. "Rime" },
	{ "reel", "Reel", OURS .. "Reel" },
	{ "tile", "Tile", OURS .. "Tile" }, -- (smooth, for tall bars: the themes' raid frames)
	-- (Quiet ones that hold up on a big bar: Media/make_shape_art.py.)
	{ "brushed", "Brushed", OURS .. "Brushed" },
	{ "worn", "Worn", OURS .. "Worn" },
	{ "linen", "Linen", OURS .. "Linen" },
	{ "satin", "Satin", OURS .. "Satin" },
	{ "hammered", "Hammered", OURS .. "Hammered" },
}

-- Whether this client has a texture (an atlas: the game says; a file: assumed).
local function Has(info)
	if not info.atlas then return true end
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(info[3]) ~= nil or false
end

local function SharedMedia()
	local stub = _G.LibStub
	return stub and stub("LibSharedMedia-3.0", true)
end

-- A texture value's file or atlas, whether it's an atlas, and whether it's
-- to be turned grey (nil: the game's own, or one this client doesn't have,
-- or a shared one no longer there).
function ns.StyleTexturePath(value)
	if type(value) ~= "string" or value == "game" then return nil end
	for _, info in ipairs(TEXTURES) do
		if info[1] == value then
			if Has(info) then return info[3], info.atlas or false, info.atlas or false end
			return nil
		end
	end
	local name = value:match("^lsm:(.+)")
	local media = name and SharedMedia()
	if media then
		local ok, path = pcall(media.Fetch, media, "statusbar", name, true)
		if ok and path then return path, false, false end
	end
end

-- A status bar's fill as a value says (turned grey where it's to be);
-- false if the value has no texture (the game's own: left alone).
function ns.SetBarTexture(bar, value)
	local path, _, grey = ns.StyleTexturePath(value)
	if not path then return false end
	bar:SetStatusBarTexture(path)
	local fill = bar:GetStatusBarTexture()
	if fill and fill.SetDesaturated then fill:SetDesaturated(grey) end
	return true
end

-- A texture (a strip, say) showing a value's texture; false if none.
function ns.SetStyleTexture(texture, value)
	local path, atlas, grey = ns.StyleTexturePath(value)
	if not path then return false end
	if atlas then texture:SetAtlas(path) else texture:SetTexture(path) end
	texture:SetDesaturated(grey)
	return true
end

-- A texture value's name, as the lists show it.
local function TextureName(value)
	if value == nil or value == "game" then return ns.L["The game's"] end
	for _, info in ipairs(TEXTURES) do
		if info[1] == value then return ns.L[info[2]] end
	end
	return type(value) == "string" and value:match("^lsm:(.+)") or tostring(value)
end
ns.StyleTextureName = TextureName -- (PlateRowLook.lua's Usual tiles)

-- The list, for a dropdown: { value, text, texture, atlas } each, the
-- game's first. game: the first entry's name for the part's own ("The game's").
-- key: a page's shared setting, for a General entry first (named for what
-- General gives it now).
function ns.StyleTextureChoices(game, key)
	local list = {}
	if key and ns.GeneralStyleValue(key) ~= nil then
		local value = ns.GeneralStyleValue(key)
		local path, atlas = ns.StyleTexturePath(value)
		list[1] = { value = "general", text = ns.SharedStyleSource(key) .. " (" .. (value == "game" and (game or
			ns.L["The game's"]) or TextureName(value)) .. ")", texture = path, atlas = atlas }
	end
	list[#list + 1] = { value = "game", text = game or ns.L["The game's"] }
	local known = {}
	for _, info in ipairs(TEXTURES) do
		if Has(info) then
			list[#list + 1] = { value = info[1], text = ns.L[info[2]], texture = info[3], atlas = info.atlas }
			known[info[3]] = true
		end
	end
	local media = SharedMedia()
	if media and media.List then
		local ok, names = pcall(media.List, media, "statusbar")
		local shared = {}
		for _, name in ipairs(ok and names or {}) do
			local path = ns.StyleTexturePath("lsm:" .. name)
			if path and not known[path] then shared[#shared + 1] = { value = "lsm:" .. name, text = name, texture = path } end
		end
		table.sort(shared, function(a, b) return a.text:lower() < b.text:lower() end)
		for _, choice in ipairs(shared) do list[#list + 1] = choice end
	end
	return list
end

-- /cine debug textures: a strip of every texture in the list (tinted green),
-- with its name, to see which this client really has (a file it doesn't
-- shows as a plain green block). Again, or a click, to close.
local sampler
function ns.ShowStyleTextures()
	if sampler and sampler:IsShown() then
		sampler:Hide()
		return
	end
	if not sampler then
		sampler = CreateFrame("Button", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
		sampler:SetFrameStrata("DIALOG")
		sampler:SetPoint("CENTER")
		if sampler.SetBackdrop then
			sampler:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
				edgeSize = 1 })
			sampler:SetBackdropColor(0, 0, 0, 0.9)
			sampler:SetBackdropBorderColor(1, 0.82, 0, 1)
		end
		sampler:SetScript("OnClick", sampler.Hide)
		sampler.rows = {}
	end
	local choices = ns.StyleTextureChoices()
	for _, row in ipairs(sampler.rows) do row.name:Hide(); row.strip:Hide() end
	local missing = {}
	for _, info in ipairs(TEXTURES) do
		if not Has(info) then missing[#missing + 1] = info[3] end
	end
	for i = 2, #choices do
		local row = sampler.rows[i]
		if not row then
			row = { name = sampler:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
				strip = sampler:CreateTexture(nil, "ARTWORK") }
			row.name:SetPoint("TOPLEFT", sampler, "TOPLEFT", 10, -10 - (i - 2) * 18)
			row.strip:SetSize(200, 12)
			row.strip:SetPoint("LEFT", sampler, "TOPLEFT", 190, -10 - (i - 2) * 18 - 6)
			sampler.rows[i] = row
		end
		local choice = choices[i]
		row.name:SetText(choice.text)
		if choice.atlas then row.strip:SetAtlas(choice.texture) else row.strip:SetTexture(choice.texture) end
		row.strip:SetDesaturated(choice.atlas and true or false)
		row.strip:SetVertexColor(0.3, 0.8, 0.35, 1)
		row.name:Show()
		row.strip:Show()
	end
	sampler:SetSize(410, 20 + (#choices - 1) * 18)
	sampler:Show()
	ns.Print(("Textures: %d in the list (%s); click the box or run this again to close."):format(#choices - 1,
		SharedMedia() and "with other addons' shared ones" or "no LibSharedMedia addon loaded"))
	if #missing > 0 then
		ns.Print("Atlases this client doesn't have (left out): " .. table.concat(missing, ", "))
	end
end

-- /cine debug platetextures: the textures your target's nameplate (or the
-- nearest one up) is drawn with: each bar's fill, and every other shown
-- texture's atlas or file, to find the game's nameplate Style looks (switch
-- the game's Style and run it again). which "prd": the personal resource
-- display's instead (/cine debug prdtextures), each texture's alpha too, to
-- find its border pieces.
function ns.ReportPlateTextures(which)
	local function Plain(value)
		return value ~= nil and not (issecretvalue and issecretvalue(value))
	end
	local function Asset(texture)
		local ok, atlas = pcall(function() return texture.GetAtlas and texture:GetAtlas() end)
		if ok and Plain(atlas) and atlas ~= "" then return "atlas " .. atlas end
		local fileOk, file = pcall(texture.GetTexture, texture)
		if fileOk and Plain(file) then return "file " .. tostring(file) end
		return "?"
	end
	local function Name(region)
		local ok, name = pcall(region.GetDebugName, region)
		name = ok and Plain(name) and name or "?"
		return (name:gsub("^NamePlate%d+%.", ""):gsub("^PersonalResourceDisplayFrame%.", ""))
	end
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
	plate = plate or plates[1]
	local style = {}
	for _, cvar in ipairs({ "nameplateStyle", "NamePlateStyle", "nameplateHealthBarStyle" }) do
		local ok, value = pcall(GetCVar, cvar)
		if ok and value ~= nil then style[#style + 1] = cvar .. "=" .. tostring(value) end
	end
	local root
	if which == "prd" then
		root = _G.PersonalResourceDisplayFrame
		local look = ns.StyleLook("prdStyle")
		ns.Print(("Personal resource textures: %s, %s, page %s, border %s (%s), texture %s"):format(
			ns.isRetail and "retail" or "classic", InCombatLockdown() and "in combat" or "out of combat",
			ns.StyleOn("prdStyle") and "on" or "off", tostring(look.prdBorder), tostring(ns.GetDB().prdBorder),
			tostring(look.prdTexture)))
		if not root then
			ns.Print("No personal resource display on this client.")
			return
		end
	else
		ns.Print(("Plate textures: %s, %s, %d plates up, target %s; %s"):format(ns.isRetail and "retail" or "classic",
			InCombatLockdown() and "in combat" or "out of combat", #plates, UnitExists("target") and "yes" or "no",
			#style > 0 and table.concat(style, " ") or "no style CVar found"))
		if not plate then
			ns.Print("No nameplate up: target an enemy (with its plate showing) and run it again.")
			return
		end
		root = plate.UnitFrame or plate
	end
	if root.IsForbidden and root:IsForbidden() then
		ns.Print("This plate is closed to addons (a friendly plate in an instance?): try an enemy's.")
		return
	end
	local lines, seen = 0, {}
	local function Line(text)
		lines = lines + 1
		if lines <= 40 then ns.Print("  " .. text) end
	end
	-- (A plate's: each texture's edges from its health bar's, + out, - in,
	-- for the Look panels' preview, PlateRowLook.lua's ns.GamePlateTrim.)
	local unitFrame = which ~= "prd" and root
	local container = unitFrame and unitFrame.HealthBarsContainer
	local health = unitFrame and ((container and container.healthBar) or unitFrame.healthBar)
	local edges
	if health then
		local ok, l, r, t, b = pcall(function() return health:GetLeft(), health:GetRight(), health:GetTop(), health:GetBottom() end)
		if ok and Plain(l) and Plain(r) and Plain(t) and Plain(b) then
			edges = { l, r, t, b }
			ns.Print(("  health bar %s: %.1f x %.1f; preview copy: %s"):format(Name(health), r - l, t - b,
				ns.GamePlateTrimReport and ns.GamePlateTrimReport() or "?"))
		else
			ns.Print("  health bar's place unreadable; preview copy: " .. (ns.GamePlateTrimReport and
				ns.GamePlateTrimReport() or "?"))
		end
	end
	-- (How it's pinned: each point, on what. Readable where places aren't.)
	local function Pins(region)
		local ok, text = pcall(function()
			local list = {}
			for i = 1, region:GetNumPoints() do
				local point, relativeTo, relativePoint, x, y = region:GetPoint(i)
				local on = relativeTo == health and "bar" or relativeTo == nil and "parent"
					or (Plain(relativeTo) and relativeTo.GetDebugName and Name(relativeTo)) or "?"
				list[#list + 1] = ("%s>%s %s %s,%s"):format(tostring(point), on, tostring(relativePoint),
					Plain(x) and ("%.1f"):format(x) or "?", Plain(y) and ("%.1f"):format(y) or "?")
			end
			return table.concat(list, " ")
		end)
		return ok and (" pinned " .. text) or " pins ?"
	end
	local function Where(region)
		if not edges then return Pins(region) end
		local ok, l, r, t, b = pcall(function() return region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom() end)
		if not (ok and Plain(l) and Plain(r) and Plain(t) and Plain(b)) then return " at ?" end
		return (" at L%+.1f R%+.1f T%+.1f B%+.1f"):format(edges[1] - l, r - edges[2], t - edges[3], edges[4] - b)
	end
	local function Walk(frame, depth)
		if depth > 5 or seen[frame] then return end
		seen[frame] = true
		local shownOk, shown = pcall(frame.IsShown, frame)
		if shownOk and Plain(shown) and not shown then return end
		if frame.GetStatusBarTexture then
			local fill = frame:GetStatusBarTexture()
			if fill then
				seen[fill] = true
				Line(("bar %s: fill %s%s; bar%s"):format(Name(frame), Asset(fill), Where(fill), Where(frame)))
			end
		end
		for _, region in ipairs({ frame:GetRegions() }) do
			if not seen[region] and region:GetObjectType() == "Texture" then
				local ok, regionShown = pcall(region.IsShown, region)
				if ok and Plain(regionShown) and regionShown then
					local alphaOk, alpha = pcall(region.GetEffectiveAlpha or region.GetAlpha, region)
					local shownAlpha = alphaOk and Plain(alpha) and (" alpha %.2f"):format(alpha) or ""
					Line(("%s: %s%s%s"):format(Name(region), Asset(region), which == "prd" and shownAlpha or "", Where(region)))
				end
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			if not (child.IsForbidden and child:IsForbidden()) then Walk(child, depth + 1) end
		end
	end
	pcall(Walk, root, 0)
	if lines > 40 then ns.Print(("  ...and %d more."):format(lines - 40)) end
end

-- A text's shadow as a part's Shadow setting says: "on" a dark one down and
-- right, "none" none, "game" (or nil) the text's own (put back if we changed
-- it). Call it after the text's font is set: a font object brings its own.
local function PlainNumber(value) return type(value) == "number" and not (issecretvalue and issecretvalue(value)) end
function ns.SetTextShadow(text, value)
	if not (text and text.SetShadowOffset) then return end
	local own = text.cineShadow
	if value == "on" or value == "none" or value == "soft" then
		if not own then
			local _, x, y = pcall(text.GetShadowOffset, text)
			local _, r, g, b, a = pcall(text.GetShadowColor, text)
			own = PlainNumber(x) and PlainNumber(y) and PlainNumber(r) and PlainNumber(a) and { x, y, r, g, b, a } or { 1, -1, 0, 0, 0, 1 }
			text.cineShadow = own
		end
		if value == "on" then
			text:SetShadowOffset(1, -1)
			text:SetShadowColor(0, 0, 0, 1)
		elseif value == "soft" then -- (a theme's: barely there, for clean lettering)
			text:SetShadowOffset(0.5, -0.5)
			text:SetShadowColor(0, 0, 0, 0.45)
		else
			text:SetShadowOffset(0, 0)
		end
	elseif own then
		text:SetShadowOffset(own[1], own[2])
		text:SetShadowColor(own[3], own[4], own[5], own[6])
		text.cineShadow = nil
	end
end

-- A text's color as a part's Text color setting says: "custom" r, g, b
-- (its alpha kept), "game" (or nil) its own (put back if we changed it).
-- Text and vertex color both: one and the same on WoW Forever.
function ns.SetTextColorOf(text, value, r, g, b)
	if not (text and text.SetTextColor) then return end
	local own = text.cineColor
	if value == "custom" then
		if not own then
			local _, or_, og, ob, oa = pcall(text.GetTextColor, text)
			own = PlainNumber(or_) and PlainNumber(og) and PlainNumber(ob) and { or_, og, ob, PlainNumber(oa) and oa or 1 }
				or { 1, 1, 1, 1 }
			text.cineColor = own
		end
		text:SetTextColor(r or 1, g or 1, b or 1, own[4])
		if text.SetVertexColor then text:SetVertexColor(r or 1, g or 1, b or 1, own[4]) end
	elseif own then
		text:SetTextColor(own[1], own[2], own[3], own[4])
		if text.SetVertexColor then text:SetVertexColor(own[1], own[2], own[3], own[4]) end
		text.cineColor = nil
	end
end

-- A colored outline round a text (the game's is always black): the text
-- again eight times behind it, nudged each way, in r, g, b, kept to its
-- words, shown state and alpha. level 1 thin, 2 thick; 0 or nil: none.
-- Call it after the text's font is set (without an outline of its own:
-- the copies take its font as it is). As Battle Vision's rim.
function ns.SetTextRim(text, level, r, g, b)
	local rim = text and text.cineRim
	if not (text and level and level > 0 and r) then
		if rim then
			rim.on = false
			for _, each in ipairs(rim) do each:Hide() end
		end
		return
	end
	if not rim then
		rim = {}
		local parent = text:GetParent()
		local layer, sub = text:GetDrawLayer()
		for i = 1, 8 do
			rim[i] = parent:CreateFontString(nil, layer)
			rim[i]:SetDrawLayer(layer, math.max(-8, (sub or 0) - 1))
		end
		function rim.Sync()
			if not rim.on then return end
			local words, shown, alpha = text:GetText(), text:IsShown(), text:GetAlpha()
			for _, each in ipairs(rim) do
				each:SetText(words or "")
				each:SetShown(shown)
				each:SetAlpha(alpha)
			end
		end
		for _, method in ipairs({ "SetText", "SetFormattedText", "Show", "Hide", "SetShown", "SetAlpha" }) do
			if text[method] then hooksecurefunc(text, method, rim.Sync) end
		end
		text.cineRim = rim
	end
	rim.on = true
	local file, size = text:GetFont()
	local nudge = level >= 2 and 2 or 1
	for i, each in ipairs(rim) do
		local angle = (i - 1) * math.pi / 4
		local dx, dy = math.cos(angle) * nudge, math.sin(angle) * nudge
		each:ClearAllPoints()
		each:SetPoint("TOPLEFT", text, "TOPLEFT", dx, dy)
		each:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", dx, dy)
		each:SetJustifyH(text:GetJustifyH())
		each:SetJustifyV(text:GetJustifyV())
		if file and size then each:SetFont(file, size, "") end
		each:SetShadowOffset(0, 0)
		each:SetTextColor(r, g or 0, b or 0, 1)
		if each.SetVertexColor then each:SetVertexColor(r, g or 0, b or 0, 1) end -- (one and the same on Forever)
	end
	rim.Sync()
end

-- The Look panels' small words (tiles, the preview's picks, the footer): the
-- game's Arial Narrow, crisp at small sizes, 12 high; the game's own small
-- font on clients whose letters it lacks (Chinese, Korean).
local function LookFont(name, r, g, b, own)
	local font = _G.CreateFont(name)
	if ({ koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""] then
		font:CopyFontObject(own)
	else
		font:SetFont("Fonts\\ARIALN.TTF", 12, "")
		font:SetShadowOffset(1, -1)
		font:SetShadowColor(0, 0, 0, 0.9)
	end
	font:SetTextColor(r, g, b)
	return name
end
ns.LOOK_TEXT = LookFont("CinematicLookText", 0.92, 0.92, 0.92, _G.GameFontHighlightSmall)
ns.LOOK_DIM = LookFont("CinematicLookDim", 0.6, 0.6, 0.6, _G.GameFontDisableSmall)

-- The Look panel shown now (one at a time), and where it was popped out to
-- (nil: docked beside the settings).
local openLook
-- A look copied (Copy look, in a tabbed Look panel): { kind (the panels it
-- pastes into: spec.tabs.copyKind), from (its row's name), values }.
local lookClip
local function LookSpot()
	local db = ns.GetDB()
	local spot = db and db.lookPanel
	return type(spot) == "table" and tonumber(spot.x) and tonumber(spot.y) and spot or nil
end

-- Every way a part can be styled, in the order a Look box (rows.Look) shows
-- them: { group's name, { { option, its name (the dev copy's red rows) } } }.
local LOOK_GROUPS = {
	{ "Bar", { { "texture", "Texture" }, { "barColor", "Color" }, { "ground", "Dark ground" } } },
	-- (Personal Resource Style: each bar's width and height.)
	{ "Size", { { "size", "Size" } } },
	-- (Cast Bar Style's rows: the spell's icon, its size and the marks on it.)
	{ "Icon", { { "icon", "Icon" } } },
	-- (Unit Frame Style's rows: the portrait and its shape.)
	{ "Portrait", { { "portrait", "Portrait" } } },
	{ "Text", { { "font", "Font" }, { "textSize", "Size" }, { "textColor", "Color" }, { "outline", "Outline" },
		{ "outlineColor", "Outline color" }, { "shadow", "Shadow" } } },
	-- (Name Style's rows: the name's colors, a glow behind it. Left out where
	-- no part has them.)
	{ "Color", { { "nameColor", "Color by" } } },
	{ "Glow", { { "glow", "Glow" } } },
	{ "Border", { { "border", "Border" } } },
	{ "Background", { { "backColor", "Color" }, { "backAlpha", "Opacity" } } },
	-- (Name Style's rows: the guild or title under the name.)
	{ "Second line", { { "line2", "Second line" } } },
	-- (A Nameplate Style row's: Forever's level box. Left out where no part has it.)
	{ "Level", { { "level", "Level box" } } },
}
-- The options a Look box makes from { key, tip, ... } (the rest, from a
-- function of the page's): texture { label, test, tint, game }, font
-- { test }, outline { names, max, test, own }, border { label, opts, test }.
local LOOK_BUILD = {
	texture = function(look, made)
		return look.Texture(made.label or ns.L["Texture:"], made[1], made[2], made.test, made.tint, made.game)
	end,
	font = function(look, made) return look.Font(made[1], made[2], made.test) end,
	outline = function(look, made)
		return look.Outline(made[1], ns.L["Outline"], made.max or 2, made.names, made[2], made.test, made.own)
	end,
	border = function(look, made)
		return look.Border(made.label or ns.L["Border:"], made[1], made.opts, made[2], made.test)
	end,
	-- (A Text color setting: "game" or "custom", its swatch's keys made.keys,
	-- for ns.SetTextColorOf.)
	textColor = function(look, made)
		local last = look.Choices(ns.L["Color:"], made[1], {
			{ "game", ns.L["The game's"] },
			{ "custom", ns.L["Custom"], ns.L["A color of your own (the swatch)."] },
		}, made.test)
		return look.Swatch(last, made[1], made.keys, made[2] or ns.L["Pick the text's color."], made.test)
	end,
	-- (A Shadow setting: "game", "on" or "none", for ns.SetTextShadow;
	-- General first where it's shared.)
	shadow = function(look, made)
		local list = {}
		if shared[made[1]] then
			list[1] = { "general", ns.SharedStyleSource(made[1]), shared[made[1]].visions
				and ns.L["As the Visions Style page says."] or ns.L["As the Style hub's General page says."] }
		end
		list[#list + 1] = { "game", ns.L["The game's"] }
		list[#list + 1] = { "on", ns.L["Shadow"], ns.L["A dark copy of the letters just behind them, down and to " ..
			"the right."] }
		list[#list + 1] = { "none", ns.L["None"] }
		return look.Choices(ns.L["Shadow:"], made[1], list, made.test)
	end,
}

-- Where a one-look page's setting comes from (its on-page Look panel's tags,
-- spec.tabs.source): Set here, General's, or Set by theme: <name> while it's
-- what the main theme wrote; nil as it starts.
function ns.PageLookSource(key)
	local L = ns.L
	local db = ns.GetDB() or {}
	local value = db[key]
	if ns.IsGeneralStyle and ns.IsGeneralStyle(value) then return { text = L["General's"] } end
	if ns.ThemeSetting then
		local themed = ns.ThemeSetting(key)
		local theme = ns.ActiveStyleTheme and ns.ActiveStyleTheme()
		if themed ~= nil and themed == value and theme then
			return { text = L["Set by theme: %s"]:format(L[theme.name]) }
		end
	end
	if value ~= nil and value ~= ns.DEFAULTS[key] then return { text = L["Set here"], own = true } end
	return nil
end

-- The rows for a page: kit (Options.lua's ns.lowHealthKit), its content and
-- stack, changed() after each change, and its switch's key. fieldOf: for a
-- page with tabs (the Unit frames page), a setting's key -> the field its
-- controls edit now (Options.lua's KeyGet/KeyPut); the key itself if not.
-- panel: a tabbed Look panel's page (rows.Look): { pictures = true (its
-- dropdowns and choices as tiles and buttons), hover = fn(key, value) (a
-- tile pointed at, nil once left: shown, never saved), usual = fn(key, value)
-- (what a value that's the part's usual gives: its name and value, or nil) }.
function ns.StyleRows(kit, content, stack, changed, switchKey, fieldOf, panel)
	local rows = {}
	local pictures = panel and panel.pictures
	local function On(db) return ns.StyleOn(switchKey, db) end
	rows.On = On
	-- (A field already, like the Preset: row's, goes through as it is.)
	local K = function(key)
		if fieldOf and type(key) ~= "table" then return fieldOf(key) end
		return key
	end
	local function Get(key) return ns.StyleKeyGet(K(key)) end
	local function Put(key, value) ns.StyleKeyPut(K(key), value) end
	rows.Get, rows.Put, rows.K = Get, Put, K -- (K: a key as its page's fieldOf gives it, for a line's :Box)

	-- A row of choices for key, after its name: { value, text, tip } each.
	-- Gives the last, to put a color swatch after.
	function rows.Choices(label, key, list, test)
		if pictures then
			-- (As buttons; a Shadow row's each word in its shadow.)
			return rows.Segments(label, key, list, nil, test, tostring(key):find("Shadow") and "shadow" or nil)
		end
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetWidth(150)
		-- (A long row goes on over more lines, each under the first's choices:
		-- the Unit Frame Style page's 13 shapes ran off the page's edge.)
		local ROOM = 420
		local last, used = nil, 0
		for _, info in ipairs(list) do
			local choice = kit.Choice(content, K(key), info[1], info[2], info[3])
			choice:HookScript("OnClick", changed)
			local words = choice.Text or choice.text
			local textW = words and words:GetStringWidth()
			local wide = choice:GetWidth() + (type(textW) == "number" and textW or 60) + 16
			if last and used + wide > ROOM then
				local line = CreateFrame("Frame", nil, content)
				line:SetSize(150, 18)
				stack:Add(line, "label")
				choice:SetPoint("LEFT", line, "RIGHT", 4, 0)
				used = 0
			elseif last then
				choice:SetPoint("LEFT", last.Text or last.text, "RIGHT", 16, 0)
			else
				choice:SetPoint("LEFT", name, "RIGHT", 4, 0)
			end
			used = used + wide
			kit.GreyUnless(choice, test or On)
			last = choice
		end
		return last
	end

	-- A color's swatch after a row of choices: its R, G and B settings (keys);
	-- a pick puts key on Custom (key nil: a color of its own, no choices).
	function rows.Swatch(after, key, keys, tip, test)
		local swatch = CreateFrame("Button", nil, content)
		swatch:SetSize(18, 18)
		swatch:SetPoint("LEFT", after.Text or after.text or after, "RIGHT", 10, 0)
		local border = swatch:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.6, 0.6, 0.6, 1)
		local color = swatch:CreateTexture(nil, "ARTWORK")
		color:SetPoint("TOPLEFT", 2, -2)
		color:SetPoint("BOTTOMRIGHT", -2, 2)
		kit.Tooltip(swatch, tip)
		swatch:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
		swatch:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
		swatch.Refresh = function()
			color:SetColorTexture(Get(keys[1]) or 0, Get(keys[2]) or 0, Get(keys[3]) or 0, 1)
		end
		swatch:SetScript("OnClick", function()
			kit.OpenColorPicker(Get(keys[1]) or 0, Get(keys[2]) or 0, Get(keys[3]) or 0, function(r, g, b)
				Put(keys[1], r)
				Put(keys[2], g)
				Put(keys[3], b)
				if key then Put(key, "custom") end
				changed()
				kit.Refresh()
			end)
		end)
		kit.GreyUnless(swatch, test or On)
		kit.AddControl(swatch)
		return swatch
	end

	-- A color on a row of its own: its name, then its swatch.
	function rows.Color(label, keys, tip, test)
		if pictures then return rows.Chips(label, keys, tip, test) end
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(150, 22) -- (room for the swatch, rows of them one under another)
		return rows.Swatch(name, nil, keys, tip, test)
	end

	-- A Font: row, its dropdown (ns.StyleFontChoices: ours, then other addons'
	-- shared ones) lined up with the other rows' dropdowns; the row as tall as
	-- the dropdown, so the next row clears it.
	-- (A shared one: General first, named for the font it gives the page.)
	-- first: a choice ahead of the fonts ({ value, text }); label: the row's
	-- name, if not Font:.
	local function FontList(key, first)
		local list, choices = {}, ns.StyleFontChoices()
		if first then list[1] = { value = first[1], text = first[2] } end
		local general = ns.GeneralStyleValue(key)
		if general ~= nil then
			local entry = { value = "general", text = ns.SharedStyleSource(key) .. " (" .. ns.StyleFontName(general) .. ")" }
			list[#list + 1] = entry
			for _, choice in ipairs(choices) do
				if choice.value == general then entry.font = choice.font end -- (drawn in General's font)
			end
		end
		for _, choice in ipairs(choices) do list[#list + 1] = choice end
		return list
	end
	function rows.Font(key, tip, test, first, label)
		if pictures then
			return rows.Tiles(label or ns.L["Font:"], key, function() return FontList(key, first) end, tip, test)
		end
		local font = kit.Dropdown(content, K(key), function() return FontList(key, first) end, 200, changed)
		if not font then return end
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label or ns.L["Font:"]), "label")
		name:SetSize(150, 30)
		name:SetJustifyV("MIDDLE")
		font:SetPoint("LEFT", name, "RIGHT", 4, 0)
		kit.GreyUnless(font, test or On)
		if tip then kit.Tooltip(font, tip) end
		return font
	end

	-- A texture row: its name, then a dropdown of the textures with a strip of
	-- each, the one picked shown in the closed dropdown too. tint: the
	-- strips' color ({ r, g, b }).
	-- game: the first entry's name for the part's own ("The game's").
	function rows.Texture(label, key, tip, test, tint, game)
		local function List()
			local list = ns.StyleTextureChoices(game, key)
			for _, choice in ipairs(list) do choice.tint = tint end
			return list
		end
		if pictures then return rows.Tiles(label, key, List, tip, test, tint) end
		local dropdown = kit.Dropdown(content, K(key), List, 200, changed)
		if not dropdown then return end
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(150, 30)
		name:SetJustifyV("MIDDLE")
		dropdown:SetPoint("LEFT", name, "RIGHT", 4, 0)
		-- (The picked one's strip, just right of the dropdown: its name has the
		-- dropdown's whole width.)
		local strip = dropdown:CreateTexture(nil, "ARTWORK")
		strip:SetSize(80, 12)
		strip:SetPoint("LEFT", dropdown, "RIGHT", 8, 0)
		local refresh = dropdown.Refresh
		dropdown.Refresh = function(self)
			refresh(self)
			local value = ns.GetDB() and Get(key)
			if ns.IsGeneralStyle(value) then value = ns.GeneralStyleValue(key) end
			local shown = value ~= nil and ns.SetStyleTexture(strip, value) or false
			strip:SetShown(shown)
			if shown then
				local t = tint or { 0.3, 0.75, 0.35 }
				strip:SetVertexColor(t[1], t[2], t[3], 1)
			end
		end
		kit.GreyUnless(dropdown, test or On)
		if tip then kit.Tooltip(dropdown, tip) end
		return dropdown
	end

	-- A dropdown row: its name, then the dropdown (list: a function giving
	-- { value, text } each, read as it opens).
	local function DropdownRow(label, key, list, tip, test)
		if pictures then return rows.Tiles(label, key, list, tip, test) end
		local dropdown = kit.Dropdown(content, K(key), list, 200, changed)
		if not dropdown then return end
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(150, 30)
		name:SetJustifyV("MIDDLE")
		dropdown:SetPoint("LEFT", name, "RIGHT", 4, 0)
		kit.GreyUnless(dropdown, test or On)
		if tip then kit.Tooltip(dropdown, tip) end
		return dropdown
	end
	rows.Dropdown = DropdownRow

	-- An outline: names[0..maxV] ("None", "Thin"...); a shared one has General
	-- first (named for the outline it gives); own: an entry at -1 by that
	-- name (General's own "Each page's own").
	function rows.Outline(key, label, maxV, names, tip, test, own)
		if pictures then
			-- (As buttons, each word in its outline.)
			local list = {}
			local general = ns.GeneralStyleValue(key)
			if general ~= nil then
				list[1] = { -1, ns.SharedStyleSource(key), ns.SharedStyleSource(key) .. " (" .. (names[general] or "") .. ")" }
			elseif own then
				list[1] = { -1, own }
			end
			for value = 0, maxV do list[#list + 1] = { value, names[value] or tostring(value) } end
			return rows.Segments(label .. ":", key, list, tip, test, "outline")
		end
		return DropdownRow(label .. ":", key, function()
			local list = {}
			local general = ns.GeneralStyleValue(key)
			if general ~= nil then
				list[1] = { value = -1, text = ns.SharedStyleSource(key) .. " (" .. (names[general] or "") .. ")" }
			elseif own then
				list[1] = { value = -1, text = own }
			end
			for value = 0, maxV do list[#list + 1] = { value = value, text = names[value] or tostring(value) } end
			return list
		end, tip, test)
	end

	-- A border: its dropdown (General first where it's shared; opts.game: the
	-- game's own, by that name if a string; opts.colored: Tooltips' In its
	-- color), then Custom's thickness and color on a line under it.
	local BORDER_NAMES = { game = "The game's", none = "None", thin = "Thin", thick = "Thick", custom = "Custom",
		colored = "In its color" }
	function rows.Border(label, key, opts, tip, test)
		opts = opts or {}
		local function Name(value)
			if value == "game" and type(opts.game) == "string" then return opts.game end
			if value == "colored" and type(opts.colored) == "string" then return opts.colored end
			return ns.L[BORDER_NAMES[value] or "None"]
		end
		local dropdown = DropdownRow(label, key, function()
			local list = {}
			local general = ns.GeneralStyleValue(key)
			if general ~= nil then
				list[1] = { value = "general", text = ns.SharedStyleSource(key) .. " (" .. Name(general) .. ")" }
			end
			if opts.game then list[#list + 1] = { value = "game", text = Name("game"), edge = true } end
			for _, value in ipairs({ "none", "thin", "thick" }) do
				list[#list + 1] = { value = value, text = Name(value), edge = true }
			end
			if opts.colored then list[#list + 1] = { value = "colored", text = Name("colored") } end
			list[#list + 1] = { value = "custom", text = Name("custom"), edge = true }
			return list
		end, tip, test)
		-- (Custom's: greyed unless it's picked.)
		local function Custom(db) return (test or On)(db) and Get(key) == "custom" end
		local line = rows.Boxes()
		line:Box(ns.L["Thickness"], K(key .. "Size"), 1, 10, 1, "%d", 1, ns.L["How thick the border is, in pixels."],
			Custom, "px")
		local color = kit.Label(content, "GameFontHighlight", ns.L["Color"])
		color:SetPoint("LEFT", line, "RIGHT", 6, 0)
		rows.Swatch(color, key, { key .. "R", key .. "G", key .. "B" },
			ns.L["The border's color. Picking one turns it to Custom."], test)
		return dropdown
	end

	-- A number: a box with its name before it (the Style pages' sliders, as
	-- boxes, to save room). fmt: "%d%%" and the like (what's after the number
	-- shown after the box), or a function for the box's text.
	function rows.Slider(key, label, minV, maxV, step, fmt, scale, tip, test)
		if pictures and type(fmt) ~= "function" then return rows.Slide(key, label, minV, maxV, step, fmt, scale, tip, test) end
		local unit, shown, width
		if type(fmt) == "function" then
			shown, width = fmt, 70
		else
			local number, after = tostring(fmt):match("^(%%[%d%.]*[df])%s*(.*)$")
			shown = number or "%d"
			unit = after and after:gsub("%%%%", "%%") or nil
			if unit == "" then unit = nil end
		end
		local line = rows.Boxes()
		line:Box(label, K(key), minV, maxV, step, shown, scale, tip, test, unit, width)
		return line
	end

	-- A line of small number boxes (Options.lua's BoxLine), on a line of its
	-- own, or beside after (a check, say). Its :Box(label, key, min, max,
	-- step, fmt, scale, tip, test, unit) adds one, greyed as the rest.
	function rows.Boxes(after)
		local line = kit.BoxLine(content)
		if after then
			line:SetPoint("LEFT", after.Text or after.text or after, "RIGHT", 24, 0)
		else
			stack:Add(line, "label")
		end
		local add = line.Box
		function line.Box(_, label, key, minV, maxV, step, fmt, scale, tip, test, unit, width)
			local box, name = add(line, label, key, minV, maxV, step, fmt, scale, tip, changed, width, unit)
			kit.GreyUnless(box, test or On)
			local refresh = box.Refresh
			box.Refresh = function(self)
				refresh(self)
				local on = (test or On)(ns.GetDB()) and 1 or 0.5
				self:SetAlpha(on)
				name:SetAlpha(on)
			end
			return box
		end
		-- (A round pick before a box, greyed as the rest: :Pick(label, key,
		-- value, tip, test, onPick).)
		local pick = line.Pick
		function line.Pick(_, label, key, value, tip, test, onPick)
			-- (The page's controls again after: the other pick, the boxes' greying.)
			local button = pick(line, label, key, value, tip, function(v)
				changed(v)
				kit.Refresh()
			end, onPick)
			kit.GreyUnless(button, test or On)
			return button
		end
		return line
	end

	-- Colors on one line: { name, keys, tip } each, its name then its swatch.
	function rows.Colors(label, list, test)
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(150, 22)
		local last = name
		for i, info in ipairs(list) do
			local each = kit.Label(content, "GameFontHighlightSmall", info[1])
			each:SetPoint("LEFT", last, "RIGHT", i == 1 and 4 or 14, 0)
			each.searchLabel = info[1]
			last = rows.Swatch(each, nil, info[2], info[3], test)
		end
		return last
	end

	function rows.Check(key, label, tip, test)
		if pictures then return rows.Toggle(key, label, tip, test) end
		local check = stack:Add(kit.Check(content, K(key), label, tip, function(value)
			Put(key, value)
			changed()
			kit.Refresh()
		end), "check")
		kit.GreyUnless(check, test or On)
		return check
	end

	-- (A tabbed Look panel's: what the part's usual gives, for a value that's
	-- its usual: its name and value, else nil.)
	local function Usual(key, value)
		if panel and panel.usual then return panel.usual(key, value) end
	end
	local function Hover(key, value)
		if panel and panel.hover then panel.hover(key, value) end
	end
	-- (Where a setting's value comes from: { text = its tag (This row, Default
	-- row's, General's, The game's...), own = the row's own, parent = the tag
	-- of what it'd inherit, short = that in a word (nil: the game's) }, or nil
	-- where the page gives none.)
	local function Source(key)
		if key and panel and panel.source then return panel.source(key) end
	end
	local function TipOn(frame, text)
		if not text then return end
		GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
		GameTooltip:SetText(text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end

	-- Tiles (a tabbed Look panel's dropdowns): the row's name over a grid of
	-- tiles, one per choice, each showing what it gives (a texture's strip, a
	-- font's name in that font, a border round a little bar), the picked one
	-- edged in gold, the usual one saying what it is. Pointed at: shown on the
	-- panel's preview, never saved. Past 12, the rest behind More (open while
	-- one of them is picked). list: { value, text, texture, atlas, font, edge,
	-- tip, enabled } each, or a function giving them, read on each refresh.
	local TILE_W, TILE_GAP, TILES_ACROSS, TILES_SHOWN = 118, 8, 4, 12
	local ROW_W = TILE_W * TILES_ACROSS + TILE_GAP * (TILES_ACROSS - 1)

	-- A tabbed Look panel's row heading: its name in gold, what it's set to
	-- after it (head:Set, from the row's control), where that comes from (the
	-- page's source: This row, Default row's, The game's...; Off while the
	-- setting can't apply), and Reset at the right while it isn't its usual
	-- (key nil: none).
	local function Heading(label, key, tip, test)
		local head = CreateFrame("Frame", nil, content)
		head:SetSize(ROW_W, 16)
		stack:Add(head, "label")
		local name = kit.Label(head, "GameFontNormal", (tostring(label):gsub(":%s*$", "")))
		name:SetPoint("LEFT", 0, 0)
		name.searchTip = tip
		local reset = CreateFrame("Button", nil, head)
		reset:SetSize(58, 16)
		reset:SetPoint("RIGHT", 0, 0)
		local source = head:CreateFontString(nil, "OVERLAY", ns.LOOK_DIM)
		source:SetPoint("RIGHT", reset, "LEFT", -6, 0)
		source:SetJustifyH("RIGHT")
		source:SetWordWrap(false)
		source.searchSkip = true
		local value = head:CreateFontString(nil, "OVERLAY", ns.LOOK_DIM)
		value:SetPoint("LEFT", name, "RIGHT", 8, 0)
		value:SetPoint("RIGHT", source, "LEFT", -8, 0)
		value:SetJustifyH("LEFT")
		value:SetWordWrap(false)
		local icon = reset:CreateTexture(nil, "ARTWORK")
		icon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
		icon:SetSize(12, 12)
		icon:SetPoint("RIGHT", 0, 0)
		local words = reset:CreateFontString(nil, "OVERLAY", ns.LOOK_DIM)
		words:SetPoint("RIGHT", icon, "LEFT", -3, 0)
		words:SetText(ns.L["Reset"])
		reset:SetScript("OnEnter", function(self)
			words:SetTextColor(1, 0.82, 0)
			TipOn(self, ns.L["This setting back to its usual."])
		end)
		reset:SetScript("OnLeave", function()
			words:SetTextColor(0.6, 0.6, 0.6)
			GameTooltip:Hide()
		end)
		local function Default()
			return key and panel and panel.default and panel.default(key)
		end
		reset:SetScript("OnClick", function()
			local default = Default()
			if default == nil then return end
			Put(key, default)
			changed(default)
			kit.Refresh()
		end)
		function head.Set(_, text) value:SetText(text or "") end
		head.Refresh = function()
			local default = Default()
			local db = ns.GetDB()
			reset:SetShown(db and default ~= nil and Get(key) ~= default and On(db) or false)
			-- (Where it comes from: the row's own in gold, else dim; Off while it
			-- can't apply and isn't the row's own.)
			local from = db and Source(key)
			if from and test and not test(db) and not from.own then from = { text = ns.L["Off"] } end
			source:SetText(from and from.text or "")
			if from and from.own then source:SetTextColor(1, 0.82, 0) else source:SetTextColor(0.6, 0.6, 0.6) end
		end
		kit.AddControl(head)
		return head
	end

	function rows.Tiles(label, key, list, tip, test, tint)
		local head = Heading(label, key, tip, test)
		local grid = CreateFrame("Frame", nil, content)
		grid:SetSize(TILE_W * TILES_ACROSS + TILE_GAP * (TILES_ACROSS - 1), 1)
		stack:Add(grid, "label")
		local tiles, open, enabled = {}, false, true
		local function MakeTile()
			local tile = CreateFrame("Button", nil, grid)
			local back = tile:CreateTexture(nil, "BACKGROUND")
			back:SetAllPoints()
			back:SetColorTexture(0.1, 0.1, 0.12, 0.95)
			tile.edges = ns.MakeStyleEdges(tile)
			local glow = tile:CreateTexture(nil, "HIGHLIGHT")
			glow:SetAllPoints()
			glow:SetColorTexture(1, 1, 1, 0.07)
			tile.strip = tile:CreateTexture(nil, "ARTWORK")
			tile.strip:SetSize(TILE_W - 16, 9)
			tile.strip:SetPoint("TOP", 0, -8)
			-- (A border's: a little bar with it round.)
			tile.bar = CreateFrame("Frame", nil, tile)
			tile.bar:SetSize(TILE_W - 28, 8)
			tile.bar:SetPoint("TOP", 0, -9)
			local fill = tile.bar:CreateTexture(nil, "ARTWORK")
			fill:SetAllPoints()
			fill:SetColorTexture(0.3, 0.68, 0.32, 1)
			tile.ground = tile.bar:CreateTexture(nil, "BACKGROUND")
			tile.ground:SetPoint("TOPLEFT", -2, 2)
			tile.ground:SetPoint("BOTTOMRIGHT", 2, -2)
			tile.ground:SetColorTexture(0, 0, 0, 0.85)
			tile.barEdges = ns.MakeStyleEdges(tile.bar)
			tile.words = tile:CreateFontString(nil, "OVERLAY", ns.LOOK_TEXT)
			tile.words:SetPoint("LEFT", 7, 0)
			tile.words:SetPoint("RIGHT", -7, 0)
			tile.words:SetJustifyH("LEFT")
			tile.words:SetWordWrap(false)
			tile.sub = tile:CreateFontString(nil, "OVERLAY", ns.LOOK_DIM)
			tile.sub:SetPoint("LEFT", 7, 0)
			tile.sub:SetPoint("RIGHT", -7, 0)
			tile.sub:SetJustifyH("LEFT")
			tile.sub:SetWordWrap(false)
			tile:SetScript("OnEnter", function(self)
				if not self.isMore and self:IsEnabled() then Hover(key, self.value) end
				TipOn(self, self.tip)
			end)
			tile:SetScript("OnLeave", function()
				Hover(nil)
				GameTooltip:Hide()
			end)
			tile:SetScript("OnClick", function(self)
				if self.isMore then
					open = not open
					grid:Refresh()
					return
				end
				Put(key, self.value)
				changed(self.value)
				kit.Refresh()
			end)
			return tile
		end
		-- (One tile as its choice: what it shows, how high the grid's are.)
		local function Dress(tile, item, kind, height, picked)
			tile.value, tile.tip, tile.isMore = item.value, item.tip, item.isMore
			tile.itemOn = not (item.enabled and not item.enabled())
			tile:SetSize(TILE_W, height)
			local usualText, usualValue = Usual(key, item.value)
			local shows = usualValue ~= nil and usualValue or item.value
			-- Its picture.
			local strip = kind == "texture" and not item.isMore and ns.SetStyleTexture(tile.strip, shows) or false
			tile.strip:SetShown(strip)
			if strip then
				local t = item.tint or tint or { 0.3, 0.75, 0.35 }
				tile.strip:SetVertexColor(t[1], t[2], t[3], 1)
			end
			local edgeKind, size, r, g, b = "none", 0, 0, 0, 0
			if kind == "border" and not item.isMore then
				edgeKind, size, r, g, b = ns.StyleBorder({ b = shows, bSize = Get(key .. "Size"), bR = Get(key .. "R"),
					bG = Get(key .. "G"), bB = Get(key .. "B") }, "b")
			end
			tile.bar:SetShown(kind == "border" and not item.isMore)
			tile.ground:SetShown(edgeKind == "game")
			tile.barEdges:SetShown(edgeKind == "line")
			if edgeKind == "line" then ns.DressStyleEdges(tile.barEdges, size, r, g, b, 1, true) end
			-- Its name (in its own font, set before the text: else other
			-- alphabets show boxes), and what the usual one gives under it.
			local file = kind == "font" and not item.isMore and (item.font or (usualValue ~= nil and item.fontUsual))
			if file then
				tile.words:SetFont(file, 13, "")
			else
				tile.words:SetFontObject(ns.LOOK_TEXT)
			end
			tile.words:SetText(item.text or tostring(item.value))
			-- (The inherited one: what it gives and where from, in a word:
			-- Default row, General, theme. Nothing more for the game's own.)
			local from = usualText and Source(key)
			if from and from.short then usualText = usualText .. " · " .. from.short end
			tile.sub:SetText(usualText or "")
			local top = (kind == "texture" or kind == "border") and -22 or -9
			tile.words:ClearAllPoints()
			tile.words:SetPoint("TOPLEFT", 9, top)
			tile.words:SetPoint("TOPRIGHT", -9, top)
			tile.sub:ClearAllPoints()
			tile.sub:SetPoint("TOPLEFT", tile.words, "BOTTOMLEFT", 0, -2)
			tile.sub:SetPoint("TOPRIGHT", tile.words, "BOTTOMRIGHT", 0, -2)
			if item.isMore then tile.words:SetTextColor(1, 0.82, 0) else tile.words:SetTextColor(0.92, 0.92, 0.92) end
			-- The picked one in gold.
			if picked then
				ns.DressStyleEdges(tile.edges, 2, 1, 0.82, 0, 1)
			else
				ns.DressStyleEdges(tile.edges, 1, 0.24, 0.24, 0.28, 1)
			end
		end
		function grid.Refresh()
			local items = (type(list) == "function" and list() or list) or {}
			local picked = ns.GetDB() and Get(key)
			if ns.IsGeneralStyle and ns.IsGeneralStyle(picked) then picked = "general" end
			local count = #items
			if count > TILES_SHOWN then
				for i = TILES_SHOWN, count do
					if items[i].value == picked then open = true end
				end
				if not open then count = TILES_SHOWN - 1 end
			end
			-- (What it's set to, after its name.)
			for _, item in ipairs(items) do
				if item.value == picked then
					local usualText = Usual(key, item.value)
					head:Set((item.text or tostring(item.value)) .. (usualText and (" · " .. usualText) or ""))
				end
			end
			-- (What the grid's tiles show, and so how high they are.)
			local kind, subs = nil, false
			for i = 1, count do
				local item = items[i]
				if item.texture or item.atlas then kind = "texture" end
				if item.font and kind ~= "texture" then kind = "font" end
				if item.edge then kind = "border" end
				if Usual(key, item.value) then subs = true end
			end
			-- (The usual one in the font it gives.)
			if kind == "font" then
				for i = 1, count do
					local _, usualValue = Usual(key, items[i].value)
					if usualValue ~= nil and usualValue ~= "game" then
						items[i].fontUsual = ns.StyleFontFile and ns.StyleFontFile(usualValue) or nil
					end
				end
			end
			local height = ((kind == "texture" or kind == "border") and 40 or kind == "font" and 32 or 28) + (subs and 11 or 0)
			local shown = {}
			for i = 1, count do shown[i] = items[i] end
			if #items > TILES_SHOWN then
				shown[#shown + 1] = { isMore = true, text = open and ns.L["Fewer"] or (ns.L["More (%d)"]):format(#items -
					TILES_SHOWN + 1) }
			end
			for i, item in ipairs(shown) do
				local tile = tiles[i] or MakeTile()
				tiles[i] = tile
				Dress(tile, item, kind, height, not item.isMore and item.value == picked)
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", grid, "TOPLEFT", ((i - 1) % TILES_ACROSS) * (TILE_W + TILE_GAP),
					-math.floor((i - 1) / TILES_ACROSS) * (height + TILE_GAP))
				tile:Show()
			end
			for i = #shown + 1, #tiles do tiles[i]:Hide() end
			local lines = math.max(1, math.ceil(#shown / TILES_ACROSS))
			local tall = lines * (height + TILE_GAP) - TILE_GAP
			if math.abs(grid:GetHeight() - tall) > 0.5 then
				grid:SetHeight(tall)
				if panel and panel.resized then panel.resized() end -- (the panel as tall as its pages again)
			end
			grid:SetEnabled(enabled)
		end
		-- (Greyed with the page's switch: each tile, and a choice that can't be
		-- picked now.)
		function grid.SetEnabled(_, on)
			enabled = on
			for _, tile in ipairs(tiles) do
				local can = on and (tile.isMore or tile.itemOn ~= false)
				tile:SetEnabled(can)
				tile:SetAlpha(can and 1 or 0.4)
			end
		end
		kit.GreyUnless(grid, test or On)
		kit.AddControl(grid)
		return grid
	end

	-- Buttons in a row (a tabbed Look panel's choices): the row's name, then
	-- one joined button per choice ({ value, text, tip } each), the picked one
	-- gold. sample: "outline" (each word in its outline) or "shadow" (in its
	-- shadow). Gives the last, to put a swatch after.
	function rows.Segments(label, key, list, tip, test, sample)
		local head = Heading(label, key, tip, test)
		local last
		for _, info in ipairs(list) do
			local button = CreateFrame("Button", nil, content)
			button.value = info[1]
			local back = button:CreateTexture(nil, "BACKGROUND")
			back:SetAllPoints()
			local line = button:CreateTexture(nil, "ARTWORK")
			line:SetPoint("BOTTOMLEFT")
			line:SetPoint("BOTTOMRIGHT")
			line:SetHeight(2)
			line:SetColorTexture(1, 0.82, 0, 1)
			local glow = button:CreateTexture(nil, "HIGHLIGHT")
			glow:SetAllPoints()
			glow:SetColorTexture(1, 1, 1, 0.07)
			local words = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			words:SetPoint("CENTER", 0, 1)
			-- (Its sample: the usual one as what it gives. The font before the text.)
			local _, usualValue = Usual(key, info[1])
			local shows = usualValue ~= nil and usualValue or info[1]
			if sample == "outline" and ns.OutlinedFlags and tonumber(shows) and tonumber(shows) >= 0 then
				local file, height, flags = words:GetFont()
				if file then words:SetFont(file, height, ns.OutlinedFlags(flags, tonumber(shows)) or "") end
			end
			words:SetText(info[2])
			if sample == "shadow" then
				if shows == "on" then
					words:SetShadowOffset(1.5, -1.5)
					words:SetShadowColor(0, 0, 0, 1)
				elseif shows == "none" then
					words:SetShadowOffset(0, 0)
				end
			end
			button:SetSize(math.max(48, words:GetStringWidth() + 20), 22)
			if last then
				button:SetPoint("LEFT", last, "RIGHT", 1, 0)
			else
				stack:Add(button, "label")
			end
			button:SetScript("OnClick", function(self)
				Put(key, self.value)
				changed(self.value)
				kit.Refresh()
			end)
			button:SetScript("OnEnter", function(self)
				if self:IsEnabled() then Hover(key, self.value) end
				local usualText = Usual(key, self.value)
				TipOn(self, info[3] or (usualText and ns.L["%s: %s"]:format(info[2], usualText)) or tip)
			end)
			button:SetScript("OnLeave", function()
				Hover(nil)
				GameTooltip:Hide()
			end)
			button.Refresh = function(self)
				local on = ns.GetDB() and Get(key) == self.value
				if on then
					local usualText = Usual(key, self.value)
					head:Set(info[2] .. (usualText and (" · " .. usualText) or ""))
				end
				back:SetColorTexture(on and 0.2 or 0.1, on and 0.17 or 0.1, on and 0.08 or 0.12, 0.95)
				line:SetShown(on and true or false)
				if on then words:SetTextColor(1, 0.82, 0) else words:SetTextColor(0.85, 0.85, 0.85) end
			end
			button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
			button:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
			kit.GreyUnless(button, test or On)
			kit.AddControl(button)
			last = button
		end
		return last
	end

	-- A slider (a tabbed Look panel's numbers): the heading, then a gold
	-- track with marks under it at a quarter, a half and three quarters'
	-- way. Values as rows.Slider's (shown = saved * scale, fmt "%d%%").
	function rows.Slide(key, label, minV, maxV, step, fmt, scale, tip, test)
		scale = scale or 1
		local head = Heading(label, key, tip, test)
		local holder = CreateFrame("Frame", nil, content)
		holder:SetSize(ROW_W, 30)
		stack:Add(holder, "label")
		local slider = CreateFrame("Slider", nil, holder)
		slider:SetOrientation("HORIZONTAL")
		slider:SetPoint("TOPLEFT", 0, 0)
		slider:SetPoint("TOPRIGHT", 0, 0)
		slider:SetHeight(16)
		slider:SetMinMaxValues(minV, maxV)
		slider:SetValueStep(step)
		if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
		local track = slider:CreateTexture(nil, "BACKGROUND")
		track:SetPoint("LEFT", 0, 0)
		track:SetPoint("RIGHT", 0, 0)
		track:SetHeight(4)
		track:SetColorTexture(0.22, 0.22, 0.26, 1)
		local thumb = slider:CreateTexture(nil, "OVERLAY")
		thumb:SetColorTexture(1, 0.82, 0, 1)
		thumb:SetSize(8, 16)
		slider:SetThumbTexture(thumb)
		local fill = slider:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("LEFT", track, "LEFT")
		fill:SetPoint("RIGHT", thumb, "CENTER")
		fill:SetHeight(4)
		fill:SetColorTexture(1, 0.82, 0, 0.7)
		for i = 0, 3 do
			local mark = holder:CreateFontString(nil, "OVERLAY", ns.LOOK_DIM)
			mark:SetText(fmt:format(minV + (maxV - minV) * i / 3))
			local x = 4 + (ROW_W - 8) * i / 3
			mark:SetPoint(i == 0 and "TOPLEFT" or i == 3 and "TOPRIGHT" or "TOP", holder, "TOPLEFT",
				i == 3 and ROW_W or (i == 0 and 0 or x), -18)
		end
		local setting = false
		local function Shown(value) return fmt:format(value) end
		slider:SetScript("OnValueChanged", function(_, value)
			if setting then return end
			value = math.floor(value / step + 0.5) * step
			Put(key, value / scale)
			head:Set(Shown(value))
			changed(value / scale)
		end)
		slider:SetScript("OnMouseUp", function() kit.Refresh() end)
		slider:SetScript("OnEnter", function(self) TipOn(self, tip) end)
		slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
		slider.Refresh = function(self)
			-- (A value handed on, "inherit": the one it gives, from panel.resolved.)
			local own = tonumber(ns.GetDB() and Get(key))
			if own == nil and panel and panel.resolved then own = tonumber(panel.resolved(key)) end
			local value = (own or (minV / scale)) * scale
			setting = true
			self:SetValue(value)
			setting = false
			head:Set(Shown(value))
		end
		kit.GreyUnless(slider, test or On)
		local refresh = slider.Refresh
		slider.Refresh = function(self)
			refresh(self)
			holder:SetAlpha((test or On)(ns.GetDB()) and 1 or 0.4)
		end
		kit.AddControl(slider)
		return slider
	end

	-- A color (a tabbed Look panel's): the heading, then chips of ready
	-- colors and one of your own (the color picker), the one it is edged gold.
	local CHIPS = { { 1, 0.3, 0.23 }, { 1, 0.62, 0.1 }, { 1, 0.88, 0.3 }, { 0.37, 0.88, 0.37 }, { 0.25, 0.78, 0.92 },
		{ 0.56, 0.49, 1 }, { 1, 0.44, 0.85 }, { 1, 1, 1 } }
	function rows.Chips(label, keys, tip, test)
		Heading(label, nil, tip)
		local holder = CreateFrame("Frame", nil, content)
		holder:SetSize(ROW_W, 24)
		stack:Add(holder, "label")
		local function Now()
			return tonumber(Get(keys[1])) or 1, tonumber(Get(keys[2])) or 1, tonumber(Get(keys[3])) or 1
		end
		local function Same(color)
			local r, g, b = Now()
			return math.abs(r - color[1]) < 0.01 and math.abs(g - color[2]) < 0.01 and math.abs(b - color[3]) < 0.01
		end
		local function Set(r, g, b)
			Put(keys[1], r)
			Put(keys[2], g)
			Put(keys[3], b)
			changed()
			kit.Refresh()
		end
		local chips = {}
		local function Chip(i)
			local chip = CreateFrame("Button", nil, holder)
			chip:SetSize(22, 22)
			chip:SetPoint("LEFT", (i - 1) * 28, 0)
			chip.swatch = chip:CreateTexture(nil, "ARTWORK")
			chip.swatch:SetPoint("TOPLEFT", 2, -2)
			chip.swatch:SetPoint("BOTTOMRIGHT", -2, 2)
			chip.edges = ns.MakeStyleEdges(chip)
			chips[i] = chip
			return chip
		end
		for i, color in ipairs(CHIPS) do
			local chip = Chip(i)
			chip.swatch:SetColorTexture(color[1], color[2], color[3], 1)
			chip:SetScript("OnClick", function() Set(color[1], color[2], color[3]) end)
		end
		-- (Your own: the color now when it's none of these; a + to pick one.)
		local own = Chip(#CHIPS + 1)
		-- (Outlined: it shows over any color.)
		local plus = own:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		local file, height = plus:GetFont()
		if file then plus:SetFont(file, height + 2, "OUTLINE") end
		plus:SetPoint("CENTER", 0, 0)
		plus:SetText("+")
		own:SetScript("OnClick", function()
			local r, g, b = Now()
			kit.OpenColorPicker(r, g, b, function(nr, ng, nb) Set(nr, ng, nb) end)
		end)
		own:SetScript("OnEnter", function(self) TipOn(self, tip or ns.L["Pick any color."]) end)
		own:SetScript("OnLeave", function() GameTooltip:Hide() end)
		holder.Refresh = function()
			if not ns.GetDB() then return end
			local mine = true
			for i, color in ipairs(CHIPS) do
				local on = Same(color)
				mine = mine and not on
				ns.DressStyleEdges(chips[i].edges, on and 2 or 1, on and 1 or 0, on and 0.82 or 0, 0, 1)
			end
			local r, g, b = Now()
			own.swatch:SetColorTexture(mine and r or 0.15, mine and g or 0.15, mine and b or 0.17, 1)
			ns.DressStyleEdges(own.edges, mine and 2 or 1, mine and 1 or 0.4, mine and 0.82 or 0.4, mine and 0 or 0.4, 1)
		end
		function holder.SetEnabled(_, on)
			for _, chip in ipairs(chips) do chip:SetEnabled(on) end
			holder:SetAlpha(on and 1 or 0.4)
		end
		kit.GreyUnless(holder, test or On)
		kit.AddControl(holder)
		return own
	end

	-- A tick (a tabbed Look panel's): a toggle with a box, side by side with
	-- the ticks just before it.
	local lastToggle, toggleRow
	function rows.Toggle(key, label, tip, test)
		local toggle = CreateFrame("Button", nil, content)
		local back = toggle:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0.1, 0.1, 0.12, 0.95)
		local edges = ns.MakeStyleEdges(toggle)
		local box = toggle:CreateTexture(nil, "ARTWORK")
		box:SetSize(10, 10)
		box:SetPoint("LEFT", 8, 0)
		local boxEdges = CreateFrame("Frame", nil, toggle)
		boxEdges:SetAllPoints(box)
		boxEdges = ns.MakeStyleEdges(boxEdges)
		ns.DressStyleEdges(boxEdges, 1, 0.45, 0.45, 0.5, 1)
		local glow = toggle:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 1, 1, 0.07)
		local words = toggle:CreateFontString(nil, "OVERLAY", ns.LOOK_TEXT)
		words:SetPoint("LEFT", box, "RIGHT", 7, 0)
		words:SetText(label)
		toggle:SetSize(words:GetStringWidth() + 36, 24)
		if lastToggle and stack.last == toggleRow then
			toggle:SetPoint("LEFT", lastToggle, "RIGHT", 6, 0)
		else
			stack:Add(toggle, "label")
			toggleRow = toggle
		end
		lastToggle = toggle
		toggle.searchLabel = label
		toggle:SetScript("OnClick", function()
			Put(key, not Get(key))
			changed()
			kit.Refresh()
		end)
		toggle:SetScript("OnEnter", function(self) TipOn(self, tip) end)
		toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
		toggle:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
		toggle:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
		toggle.Refresh = function()
			local on = ns.GetDB() and Get(key) and true or false
			box:SetColorTexture(1, 0.82, 0, on and 1 or 0)
			ns.DressStyleEdges(edges, 1, on and 0.66 or 0.24, on and 0.54 or 0.24, on and 0.17 or 0.28, 1)
		end
		kit.GreyUnless(toggle, test or On)
		kit.AddControl(toggle)
		return toggle
	end

	-- Presets: { name, tip, settings } each; a pick turns the page on and sets
	-- keys as its settings say, the rest as their defaults.
	local function Matches(preset, keys)
		local db = ns.GetDB()
		if not (db and db[switchKey]) then return false end
		for _, key in ipairs(keys) do
			local value = preset[3][key]
			if value == nil then value = ns.DEFAULTS[key] end
			if db[key] ~= value then return false end
		end
		return true
	end
	-- The presets as a dropdown (Preset:), each with its tip; Custom shows
	-- while the settings match none. Picking a preset from your own settings
	-- keeps them (db.presetCustom, by the page's switch and the menu's first
	-- key: a page can have more than one menu), and Custom puts them back.
	function rows.PresetMenu(presets, keys)
		local id = switchKey .. ":" .. tostring(keys[1])
		local function Kept()
			local db = ns.GetDB()
			return db and db.presetCustom and db.presetCustom[id]
		end
		local field
		field = {
			get = function()
				for i, preset in ipairs(presets) do
					if Matches(preset, keys) then return i end
				end
				return "custom"
			end,
			set = function(i)
				local db = ns.GetDB()
				if i == "custom" then
					local kept = Kept()
					if not kept then return end
					db[switchKey] = true
					for _, key in ipairs(keys) do
						if kept[key] ~= nil then db[key] = kept[key] end
					end
					return
				end
				local preset = presets[i]
				if not preset then return end
				-- (Your own, before a preset goes over them.)
				if field.get() == "custom" then
					local kept = {}
					for _, key in ipairs(keys) do kept[key] = db[key] end
					db.presetCustom = db.presetCustom or {}
					db.presetCustom[id] = kept
				end
				db[switchKey] = true
				for _, key in ipairs(keys) do
					local value = preset[3][key]
					if value == nil then value = ns.DEFAULTS[key] end
					db[key] = value
				end
			end,
		}
		return DropdownRow(ns.L["Preset:"], field, function()
			local list = {}
			for i, preset in ipairs(presets) do list[i] = { value = i, text = preset[1], tip = preset[2] } end
			list[#list + 1] = { value = "custom", text = ns.L["Custom"],
				tip = ns.L["Your own settings, as they were before you picked a preset."],
				enabled = function() return Kept() ~= nil end }
			return list
		end, ns.L["A whole look in one pick. Changing a setting after it shows Custom; picking Custom puts back " ..
			"your own settings from before the preset."])
	end

	-- A Look row: a button naming the part's look, and a click opens every
	-- way to style it in a panel docked beside the settings (or popped out),
	-- the same options in the same order on every page (LOOK_GROUPS). spec[option]:
	-- { key, tip, ... } for the ones LOOK_BUILD makes, function(look)
	-- making its rows with look (the box's own rows), or false: one that
	-- can't apply to the part. A group shows if the part has any of its
	-- options; the dev copy lists, in red, the ones of it the part lacks.
	-- spec.inline: on the page itself, in its stack (a page with one look:
	-- Personal Resources, Tooltips...), always open, with no button, X or
	-- Pop out.
	function rows.Look(label, title, spec)
		local inline = spec.inline
		local name
		if not inline then
			name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
			name:SetSize(150, 30)
			name:SetJustifyV("MIDDLE")
		end
		local button = ns.PanelButton(content)
		button:SetHeight(22)
		if inline then button:Hide() else button:SetPoint("LEFT", name, "RIGHT", 4, 0) end
		button.searchLabel = label
		kit.Tooltip(button, ns.L["Every way to style this part, in a panel beside the settings. Pop out to drag " ..
			"it anywhere; Escape or its X closes it."])

		-- (Docked to the settings window's right, as the camera previewer is;
		-- popped out, where it was dragged: one place for every Look panel.)
		local canvas = content:GetParent() and content:GetParent():GetParent() or content
		local pop = CreateFrame("Frame", nil, inline and content or UIParent)
		pop:EnableMouse(true)
		pop:SetSize(470, 400)
		if inline then
			stack:Add(pop, "label")
		else
			pop:SetFrameStrata("DIALOG")
			pop:Hide()
			pop:SetMovable(true)
			pop:SetClampedToScreen(true)
			pop:RegisterForDrag("LeftButton")
			pop:SetScript("OnDragStart", function(self)
				if LookSpot() then self:StartMoving() end
			end)
			pop:SetScript("OnDragStop", function(self)
				self:StopMovingOrSizing()
				ns.GetDB().lookPanel = { x = self:GetLeft(), y = self:GetTop() }
			end)
		end
		pop.recordAs = content -- (its settings are the page's: its Reset puts them back)
		-- (Every Look panel made, by its title: Tools/style-lab draws one open.)
		ns.LOOK_PANELS = ns.LOOK_PANELS or {}
		ns.LOOK_PANELS[#ns.LOOK_PANELS + 1] = { title = title, pop = pop }
		local bg = pop:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.97)
		local edge = pop:CreateTexture(nil, "BACKGROUND", nil, -1)
		edge:SetPoint("TOPLEFT", -1, 1)
		edge:SetPoint("BOTTOMRIGHT", 1, -1)
		edge:SetColorTexture(0.4, 0.4, 0.4, 1)
		local heading = kit.Label(pop, "GameFontHighlightLarge", title)
		heading:SetPoint("TOPLEFT", 12, -10)
		local close = ns.SkinClose(CreateFrame("Button", nil, pop, "UIPanelCloseButton"))
		close:SetPoint("TOPRIGHT", 0, 0)
		local dock = ns.PanelButton(pop)
		dock:SetSize(70, 20)
		dock:SetPoint("TOPRIGHT", -28, -6)
		kit.Tooltip(dock, ns.L["Pop out: drag the window anywhere (by its edge). Dock: back beside the settings."])
		if inline then
			close:Hide()
			dock:Hide()
		end
		local popStack = kit.Stack(heading, "label") -- (a header's room under the title)

		-- Tabbed (spec.tabs): a tab per group under the title, each group's rows
		-- on a page of their own, a gold dot on a tab whose settings aren't
		-- their defaults, and a footer saying what's changed, with Reset all.
		-- spec.tabs: true (defaults: ns.DEFAULTS), or { default = fn(key) }
		-- giving a key's default (nil: not counted nor reset, as a row's color).
		local tabbed = spec.tabs
		local DefaultOf = type(tabbed) == "table" and tabbed.default or function(key) return ns.DEFAULTS[key] end
		local tabs, pages, current = {}, {}, 1
		local strip, footer, summary, resetAll
		-- (spec.preview(parent, width): the part as it looks now, a frame with
		-- :Refresh(), between the title and the tabs; drawn again on each change.)
		local preview = tabbed and spec.preview and spec.preview(pop, 496)
		local function Field(key) return fieldOf and fieldOf(key) or key end
		local function PageChanged(page)
			for _, key in ipairs(page.keys) do
				local default = DefaultOf(key)
				if default ~= nil then
					local value = ns.StyleKeyGet(Field(key))
					if value ~= nil and value ~= default then return true end
				end
			end
			return false
		end
		local function AnyChanged()
			for _, page in ipairs(pages) do
				if PageChanged(page) then return true end
			end
			return false
		end
		local function PaintTabs()
			if not tabbed then return end
			local names = {}
			for i, tab in ipairs(tabs) do
				local on = i == current
				if on then tab.text:SetTextColor(1, 0.82, 0) else tab.text:SetTextColor(0.62, 0.62, 0.62) end
				tab.line:SetShown(on)
				local moved = ns.GetDB() and PageChanged(pages[i]) or false
				tab.dot:SetShown(moved)
				if moved then names[#names + 1] = tab.name end
				pages[i]:SetShown(on)
			end
			-- (A page whose settings inherit: said so.)
			local inherits = type(tabbed) == "table" and tabbed.source
			summary:SetText(#names > 0 and ns.L[inherits and "Changed here: %s" or "Changed: %s"]:format(
				table.concat(names, " · ")) or ns.L[inherits and "Nothing changed here: all inherited" or "Nothing changed"])
			if preview and preview:IsVisible() then preview:Refresh() end
		end
		-- (Its pages' rows as tiles and buttons: one pointed at shows on the
		-- preview, never saved; the usual one says what it gives, from
		-- spec.tabs.usual(key): its name and value.)
		local refit -- (Fit, once it's made: a page grown or shrunk)
		local pictured = tabbed and {
			pictures = true,
			default = function(key) return DefaultOf(key) end,
			resized = function()
				if refit then C_Timer.After(0, refit) end
			end,
			hover = function(key, value)
				if preview then preview:Refresh(key and { [key] = value } or nil) end
			end,
			usual = function(key, value)
				if type(tabbed) == "table" and tabbed.usual and value ~= nil and DefaultOf(key) == value then
					return tabbed.usual(key)
				end
			end,
			-- (Where each setting's value comes from: spec.tabs.source(key).)
			source = type(tabbed) == "table" and tabbed.source or nil,
			-- (What a setting handed on gives, for a slider: spec.tabs.resolved(key).)
			resolved = type(tabbed) == "table" and tabbed.resolved or nil,
		}
		-- (Every setting the panel counts: those with a default, its row's color
		-- and paint ticks left out. Known once its pages are made.)
		local function LookKeys()
			local list = {}
			for _, page in ipairs(pages) do
				for _, key in ipairs(page.keys) do
					if DefaultOf(key) ~= nil then list[#list + 1] = key end
				end
			end
			return list
		end
		-- (A change on a tab's page: its dot and the footer too.)
		local function TabChanged(...)
			changed(...)
			PaintTabs()
		end
		if tabbed then
			strip = CreateFrame("Frame", nil, pop)
			strip:SetHeight(26)
			if preview then
				preview:SetPoint("TOPLEFT", pop, "TOPLEFT", 12, -36)
				preview:SetPoint("RIGHT", pop, "RIGHT", -12, 0)
			end
			-- (A line of tools under the sample: Hold to compare, Copy look,
			-- Paste, Start from a theme. Then the tabs.)
			local toolsTop = preview and (36 + preview:GetHeight() + 8) or 36
			local tools = CreateFrame("Frame", nil, pop)
			tools:SetHeight(22)
			tools:SetPoint("TOPLEFT", pop, "TOPLEFT", 12, -toolsTop)
			tools:SetPoint("RIGHT", pop, "RIGHT", -12, 0)
			strip:SetPoint("TOPLEFT", pop, "TOPLEFT", 0, -(toolsTop + 22 + 8))
			local function Tool(text, width, tip)
				local tool = ns.PanelButton(tools)
				tool:SetSize(width, 20)
				tool:SetText(text)
				tool:SetScript("OnEnter", function(self) TipOn(self, type(tip) == "function" and tip() or tip) end)
				tool:SetScript("OnLeave", function() GameTooltip:Hide() end)
				tool.Refresh = function() end
				kit.AddControl(tool)
				return tool
			end
			-- (Every counted setting as it starts, then values over it: changed.)
			local function Load(values)
				for _, key in ipairs(LookKeys()) do ns.StyleKeyPut(Field(key), DefaultOf(key)) end
				for key, value in pairs(values) do ns.StyleKeyPut(Field(key), value) end
				changed()
				kit.Refresh()
				PaintTabs()
			end
			local last
			-- Hold to compare: held down, the sample without this row's own
			-- changes (every counted setting as it starts); let go, as it is.
			if preview then
				local compare = Tool(ns.L["Hold to compare"], 124,
					ns.L["Hold it down to see the sample without this row's own changes: before, then after."])
				compare:SetPoint("LEFT", tools, "LEFT", 0, 0)
				local holding = false
				local function Hold(on)
					if holding == on then return end
					holding = on
					compare:SetText(on and ns.L["Showing: before"] or ns.L["Hold to compare"])
					if on then
						local over = {}
						for _, key in ipairs(LookKeys()) do over[key] = DefaultOf(key) end
						preview:Refresh(over, ns.L["Before this row's changes"])
					else
						preview:Refresh()
					end
				end
				compare:SetScript("OnMouseDown", function(self)
					if self:IsEnabled() then Hold(true) end
				end)
				compare:SetScript("OnMouseUp", function() Hold(false) end)
				compare:HookScript("OnLeave", function() Hold(false) end)
				compare:HookScript("OnHide", function() Hold(false) end)
				kit.GreyUnless(compare, On)
				last = compare
			end
			-- Copy look / Paste: this panel's settings, into another panel of
			-- the same kind (Target's into Focus', say).
			local copyKind = tabbed.copyKind or title
			local copy = Tool(ns.L["Copy look"], 86, ns.L["Keep this look, to paste into another row."])
			if last then copy:SetPoint("LEFT", last, "RIGHT", 6, 0) else copy:SetPoint("LEFT", tools, "LEFT", 0, 0) end
			local paste = Tool(ns.L["Paste"], 64, function()
				if lookClip and lookClip.kind == copyKind then
					return ns.L["This row's look as %s's, copied."]:format(lookClip.from)
				end
				return ns.L["Copy a look first (Copy look, in another row's panel)."]
			end)
			paste:SetPoint("LEFT", copy, "RIGHT", 6, 0)
			copy:SetScript("OnClick", function(self)
				local values = {}
				for _, key in ipairs(LookKeys()) do values[key] = ns.StyleKeyGet(Field(key)) end
				lookClip = { kind = copyKind, from = tabbed.copyName or title, values = values }
				self:SetText(ns.L["Copied"])
				C_Timer.After(0.9, function() self:SetText(ns.L["Copy look"]) end)
				kit.Refresh()
			end)
			paste:SetScript("OnClick", function()
				if lookClip and lookClip.kind == copyKind then Load(lookClip.values) end
			end)
			kit.GreyUnless(copy, On)
			kit.GreyUnless(paste, function(db) return On(db) and lookClip ~= nil and lookClip.kind == copyKind end)
			-- Start from a theme: a theme's look in just this panel (spec.tabs.
			-- themeLook(theme's key): its { key = value }), to change from there.
			-- The themes: spec.tabs.themeList() ({ key, name } each), else the
			-- main ones.
			if tabbed.themeLook then
				local start = Tool(ns.L["Start from a theme"], 130,
					ns.L["This row's look as a theme has it, to change from there. Only this row: the theme in use stays."])
				start:SetPoint("RIGHT", tools, "RIGHT", 0, 0)
				start:SetScript("OnClick", function(self)
					ns.ContextMenu(self, function(_, root)
						for _, theme in ipairs((tabbed.themeList or ns.StyleThemeList)()) do
							root:CreateButton(theme.name, function()
								local values = tabbed.themeLook(theme.key)
								if values then Load(values) end
							end)
						end
					end)
				end)
				kit.GreyUnless(start, On)
			end
			strip:SetPoint("RIGHT", pop, "RIGHT")
			local band = strip:CreateTexture(nil, "BACKGROUND")
			band:SetAllPoints()
			band:SetColorTexture(1, 1, 1, 0.04)
			local rule = strip:CreateTexture(nil, "BORDER")
			rule:SetPoint("BOTTOMLEFT")
			rule:SetPoint("BOTTOMRIGHT")
			rule:SetHeight(1)
			rule:SetColorTexture(1, 1, 1, 0.12)

			footer = CreateFrame("Frame", nil, pop)
			footer:SetHeight(34)
			footer:SetPoint("BOTTOMLEFT")
			footer:SetPoint("BOTTOMRIGHT")
			local line = footer:CreateTexture(nil, "BORDER")
			line:SetPoint("TOPLEFT")
			line:SetPoint("TOPRIGHT")
			line:SetHeight(1)
			line:SetColorTexture(1, 1, 1, 0.12)
			resetAll = ns.PanelButton(footer)
			resetAll:SetSize(100, 20)
			resetAll:SetPoint("RIGHT", -10, 0)
			resetAll:SetText(ns.L["Reset all"])
			-- (Its name: spec.tabs.resetLabel, a word or a function giving one:
			-- Clear this row on a row that inherits.)
			local function ResetLabel()
				local word = type(tabbed) == "table" and tabbed.resetLabel
				if type(word) == "function" then word = word() end
				return word or ns.L["Reset all"]
			end
			resetAll:SetScript("OnEnter", function(self)
				TipOn(self, ResetLabel() == ns.L["Reset all"] and ns.L["Every setting in this panel back to how it starts."]
					or ns.L["Every setting in this panel back to inherited: the row takes its look from above again."])
			end)
			resetAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
			resetAll:SetScript("OnClick", function()
				for _, page in ipairs(pages) do
					for _, key in ipairs(page.keys) do
						local default = DefaultOf(key)
						if default ~= nil then ns.StyleKeyPut(Field(key), default) end
					end
				end
				changed()
				kit.Refresh()
				PaintTabs()
			end)
			resetAll.Refresh = function(self)
				self:SetText(ResetLabel())
				PaintTabs()
			end
			kit.GreyUnless(resetAll, function(db) return On(db) and AnyChanged() end)
			kit.AddControl(resetAll)
			summary = kit.Label(footer, ns.LOOK_DIM, "")
			summary:SetPoint("LEFT", 12, 0)
			summary:SetPoint("RIGHT", resetAll, "LEFT", -8, 0)
			summary:SetJustifyH("LEFT")
			summary:SetWordWrap(false)
		end

		local look = not tabbed and ns.StyleRows(kit, pop, popStack, changed, switchKey, fieldOf)
		for _, group in ipairs(LOOK_GROUPS) do
			local has = false
			for _, option in ipairs(group[2]) do has = has or (spec[option[1]] and true) end
			if has then
				local into, stackNow, lookNow = pop, popStack, look
				if tabbed then
					-- (Its page: under the tabs, its own stack, the keys its rows use.)
					local page = CreateFrame("Frame", nil, pop)
					page.recordAs = content
					page:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, 0)
					page:SetPoint("RIGHT", pop, "RIGHT")
					page:SetHeight(1)
					page.keys, page.seen = {}, {}
					local top = kit.Label(page, "GameFontNormal", "")
					top:SetPoint("TOPLEFT", 12, -2)
					page.stack = kit.Stack(top, "header")
					page.look = ns.StyleRows(kit, page, page.stack, TabChanged, switchKey, function(key)
						if not page.seen[key] then
							page.seen[key] = true
							page.keys[#page.keys + 1] = key
						end
						return Field(key)
					end, pictured)
					pages[#pages + 1] = page
					into, stackNow, lookNow = page, page.stack, page.look

					local index = #pages
					local tab = CreateFrame("Button", nil, strip)
					tab.name = ns.L[group[1]]
					tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
					tab.text:SetPoint("LEFT", 12, 1)
					tab.text:SetText(tab.name)
					tab.dot = tab:CreateTexture(nil, "OVERLAY")
					tab.dot:SetSize(6, 6)
					tab.dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
					tab.dot:SetVertexColor(1, 0.82, 0)
					tab.dot:SetPoint("LEFT", tab.text, "RIGHT", 5, 0)
					tab.line = tab:CreateTexture(nil, "OVERLAY")
					tab.line:SetPoint("BOTTOMLEFT", 4, 0)
					tab.line:SetPoint("BOTTOMRIGHT", -4, 0)
					tab.line:SetHeight(2)
					tab.line:SetColorTexture(1, 0.82, 0)
					local glow = tab:CreateTexture(nil, "HIGHLIGHT")
					glow:SetAllPoints()
					glow:SetColorTexture(1, 1, 1, 0.06)
					tab:SetSize(tab.text:GetStringWidth() + 35, 26)
					local before = tabs[#tabs]
					if before then
						tab:SetPoint("LEFT", before, "RIGHT", 0, 0)
					else
						tab:SetPoint("LEFT", strip, "LEFT", 4, 0)
					end
					tab:SetScript("OnClick", function()
						current = index
						PaintTabs()
					end)
					tabs[#tabs + 1] = tab
				else
					popStack:Add(kit.Label(pop, "GameFontNormal", ns.L[group[1]]), "header")
				end
				for _, option in ipairs(group[2]) do
					local made = spec[option[1]]
					if type(made) == "function" then
						made(lookNow)
					elseif made then
						LOOK_BUILD[option[1]](lookNow, made)
					elseif made == nil and ns.isDev then
						local missing = stackNow:Add(kit.Label(into, "GameFontHighlight",
							option[2] .. ": not wired on this part (dev copy only)"), "label")
						missing:SetHeight(22)
						missing:SetTextColor(1, 0.25, 0.25)
					end
				end
			end
		end

		-- Use General: the part's shared settings back on General (only where
		-- it has some).
		local sharedKeys = {}
		for option in pairs(LOOK_BUILD) do
			local made = spec[option]
			if type(made) == "table" and shared[made[1]] then sharedKeys[#sharedKeys + 1] = made[1] end
		end
		if #sharedKeys > 0 then
			local back = ns.PanelButton(pop)
			back:SetSize(110, 20)
			if tabbed then
				-- (In the footer, before what's changed.)
				back:SetParent(footer)
				back:SetPoint("LEFT", footer, "LEFT", 10, 0)
				summary:SetPoint("LEFT", back, "RIGHT", 10, 0)
			else
				popStack:Add(back, "label")
			end
			if shared[sharedKeys[1]].visions then
				back:SetWidth(140)
				back:SetText(ns.L["Use Visions Style"])
				kit.Tooltip(back, ns.L["These settings back on the Visions Style page."])
			else
				back:SetText(ns.L["Use General"])
				kit.Tooltip(back, ns.L["These settings back on General."])
			end
			back:SetScript("OnClick", function()
				for _, key in ipairs(sharedKeys) do Put(key, shared[key].kind == "outline" and -1 or "general") end
				changed()
				kit.Refresh()
			end)
			back.Refresh = function() end
			kit.GreyUnless(back, On)
			kit.AddControl(back)
		end

		-- (As tall and wide as what's in it, once it's laid out.)
		-- (Tabbed: as tall as its tallest page and as wide as its widest, so it
		-- doesn't jump as tabs change; at least 520 wide.)
		local function FitTabbed()
			local top, left, under = pop:GetTop(), pop:GetLeft(), strip:GetBottom()
			if not (top and left and under) then return end
			local tallest, right = 0, 0
			local function Reach(each)
				if each:IsShown() and each:GetRight() then right = math.max(right, each:GetRight()) end
			end
			for _, page in ipairs(pages) do
				page:Show()
				local bottom = page.stack.last and page.stack.last:GetBottom()
				if bottom then tallest = math.max(tallest, under - bottom) end
				for _, child in ipairs({ page:GetChildren() }) do
					Reach(child)
					if child.Text or child.text then Reach(child.Text or child.text) end -- (a check's words)
				end
				for _, region in ipairs({ page:GetRegions() }) do Reach(region) end
			end
			for _, tab in ipairs(tabs) do Reach(tab) end
			PaintTabs() -- (back to the one page shown)
			local titleRight = heading:GetRight()
			if titleRight then right = math.max(right, titleRight + 100) end -- (the buttons past the title)
			pop:SetWidth(math.max(520, right - left + 12))
			pop:SetHeight(top - under + tallest + 10 + footer:GetHeight())
		end
		refit = function()
			if pop:IsShown() then FitTabbed() end
		end
		local function Fit()
			if tabbed then return FitTabbed() end
			local top, bottom = pop:GetTop(), popStack.last:GetBottom()
			if top and bottom then pop:SetHeight(top - bottom + 12) end
			local left, right = pop:GetLeft(), 0
			if not left then return end
			local function Reach(each)
				if each ~= bg and each ~= edge and each ~= close and each ~= dock and each:IsShown() and each:GetRight() then
					right = math.max(right, each:GetRight() + (each == heading and 100 or 0)) -- (the buttons past the title)
				end
			end
			for _, child in ipairs({ pop:GetChildren() }) do
				Reach(child)
				if child.Text or child.text then Reach(child.Text or child.text) end -- (a check's words)
			end
			for _, region in ipairs({ pop:GetRegions() }) do Reach(region) end
			pop:SetWidth(math.max(470, right - left + 12))
		end
		local function Place()
			local spot = LookSpot()
			pop:ClearAllPoints()
			if spot then
				pop:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", spot.x, spot.y)
				dock:SetText(ns.L["Dock"])
			else
				local window = canvas
				while window:GetParent() and window:GetParent() ~= UIParent do window = window:GetParent() end
				pop:SetPoint("TOPLEFT", window, "TOPRIGHT", 4, 0)
				dock:SetText(ns.L["Pop out"])
			end
		end
		dock:SetScript("OnClick", function()
			ns.GetDB().lookPanel = not LookSpot() and { x = pop:GetLeft() + 30, y = pop:GetTop() - 30 } or nil
			Place()
		end)
		pop:SetScript("OnShow", function(self)
			-- (One panel at a time; one on the page stays where it is.)
			if not inline then
				if openLook and openLook ~= self then openLook:Hide() end
				openLook = self
				Place()
			end
			-- (Titled with where the part is, the page's place dimmed before it:
			-- known once the page is in its hub, after it's built.)
			local path = canvas.hubPath or (canvas.name and { canvas.name })
			-- (On the page itself: its name alone, the page's place is all round it.)
			if path and not inline then
				heading:SetText("|cff9a9a9a" .. table.concat(path, " > ") .. " >|r " .. title)
			end
			Fit()
			C_Timer.After(0, Fit)
		end)
		-- (Not while one of its menus or the color picker is open: theirs first.)
		local function Busy()
			local manager = Menu and Menu.GetManager and Menu.GetManager()
			if manager and manager.GetOpenMenu and manager:GetOpenMenu() then return true end
			return ColorPickerFrame and ColorPickerFrame:IsShown()
		end
		if not inline then canvas:HookScript("OnHide", function() pop:Hide() end) end
		-- Escape closes it before the settings window (not in a fight, where
		-- keys can't be held back; not while its menu or the color picker is
		-- open: theirs first).
		if pop.SetPropagateKeyboardInput and not inline then
			pop:HookScript("OnShow", function(self)
				if InCombatLockdown() then return end
				self:EnableKeyboard(true)
				self:SetPropagateKeyboardInput(true)
			end)
			pop:SetScript("OnKeyDown", function(self, key)
				if key ~= "ESCAPE" or InCombatLockdown() or Busy() then return end
				self:SetPropagateKeyboardInput(false)
				self:Hide()
				C_Timer.After(0, function()
					if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
				end)
			end)
		end
		button:SetScript("OnClick", function() pop:SetShown(not pop:IsShown()) end)

		-- The button's words: what the part has that isn't the game's own.
		local function Shown(key)
			local value = ns.GetDB() and Get(key)
			if IsGeneral(value) then value = ns.GeneralStyleValue(key) end
			return value
		end
		local function Summary()
			local parts = {}
			local made = spec.texture
			local value = type(made) == "table" and Shown(made[1])
			if value and value ~= "game" then parts[#parts + 1] = TextureName(value) end
			made = spec.font
			value = type(made) == "table" and Shown(made[1])
			if value and value ~= "game" then parts[#parts + 1] = ns.StyleFontName(value) end
			made = spec.outline
			value = type(made) == "table" and Shown(made[1])
			if type(value) == "number" and value > 0 and made.names[value] then
				parts[#parts + 1] = ns.L["%s outline"]:format(made.names[value])
			end
			made = spec.border
			value = type(made) == "table" and Shown(made[1])
			if value and value ~= "game" and value ~= "none" and BORDER_NAMES[value] then
				parts[#parts + 1] = ns.L["%s border"]:format(ns.L[BORDER_NAMES[value]])
			end
			return #parts > 0 and table.concat(parts, " · ") or ns.L["The game's"]
		end
		button.Refresh = function(self)
			self:SetText(Summary())
			self:SetWidth(math.max(120, self:GetFontString():GetStringWidth() + 30))
		end
		kit.GreyUnless(button, On)
		kit.AddControl(button)
		return button, pop
	end

	return rows
end
