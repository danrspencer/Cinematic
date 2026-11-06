-- The Style hub's General page: a switch for every Style page at once (off:
-- each shows the game's look), the settings the pages share (bar texture,
-- font, outline: StylePages.lua's ns.StyleLook), a preview of several pages'
-- parts in turn, and which pages follow it or have a setting of their own.

local _, ns = ...
local L = ns.L

-- The list on the Pages tab, in the hubs' order: name, the page to open
-- (ns.OpenOptions), its shared settings. fixed: what it says instead, for a
-- page with no shared settings of its own. group: a heading over it. visions:
-- it follows the Visions hub's Style page first.
local PAGES = {
	{ "Unit Frames", "Unit Style", { "ufTexture", "ufFont", "ufOutline", "ufShadow", "ufBorder" }, group = "Interface" },
	{ "Raid Frames", "Raid Style", { "rfTexture", "rfFont", "rfOutline", "rfShadow", "rfBorder" } },
	{ "Action Bars", "Action Style", {}, fixed = "Its own settings" },
	{ "Personal Resource Display", "Personal Style", { "prdTexture", "prdBorder" } },
	{ "Tooltips", "Tooltip Style", { "tooltipBarTexture", "tooltipFont", "tooltipOutline", "tooltipShadow", "tooltipEdge" } },
	-- (These two read General directly: PlateHealthStyle.lua, PlateParts.lua.)
	{ "Nameplates", "Nameplate Style", {}, fixed = "Follows General" },
	{ "Names", "Name Style", {}, fixed = "Follows General" },
	{ "Cast Bars", "Cast Bar Style", { "plateCastFill", "plateCastFont", "plateCastOutline", "plateCastShadow", "plateCastBorder" } },
	{ "Chat Bubbles", "Bubble Style", { "bubblesFont", "bubblesOutline", "bubblesEdge" } },
	{ "Visions Style", "Visions Style", { "visionStyleTexture", "visionStyleFont", "visionStyleOutline", "visionStyleShadow",
		"visionStyleBorder" }, group = "Visions" },
	{ "Damage Vision", "Damage Vision Look", { "damageVisionTexture", "damageVisionFont", "damageVisionOutline",
		"damageVisionShadow" }, visions = true },
	{ "Dialogue", "Quest Talk Style", { "questTalkFont", "questTalkOutline", "questTalkShadow" }, visions = true },
	{ "Quest Item Button", "Quest Item Style", { "questItemFont", "questItemOutline", "questItemShadow", "questItemFrame" },
		visions = true },
	{ "Roll Vision", "Roll Style", { "rollBarTexture", "rollFont", "rollOutline", "rollShadow" }, visions = true },
	{ "Card Vision", "Card Styles", { "cardFont", "cardOutline", "cardShadow" }, visions = true },
	{ "Emote Vision", "Emote Vision Style", { "emoteFont", "emoteOutline", "emoteShadow", "emoteBorder" }, visions = true },
}
local KIND_NAMES = { texture = "Texture", font = "Font", outline = "Outline", shadow = "Shadow", border = "Border" }

-- Every page's look again (General's settings changing).
local function RefreshAll()
	for _, refresh in ipairs({ ns.RefreshPersonalStyle, ns.RefreshTooltipStyle, ns.RefreshBubbleStyle,
		ns.RefreshQuestTalkStyle, ns.RefreshQuestItemStyle, ns.RefreshRollStyle, ns.RefreshPlateCastStyle,
		ns.RefreshUnitStyle, ns.RefreshRaidStyle, ns.RefreshTargetArrows, ns.RefreshPlateNameStyle,
		ns.RefreshActionBarStyle, ns.RefreshPlateHealthStyle }) do
		if refresh then
			-- (Kept going past a page's error, but said: a page that fails here just
			-- looks unstyled, with nothing else to show why.)
			local ok, err = pcall(refresh)
			if not ok then ns.Log("style", "refresh failed: " .. tostring(err)) end
		end
	end
end
ns.RefreshAllStyles = RefreshAll

-- A nameplate, for the preview: an enemy's name in General's font and
-- outline, its health bar in General's texture and border (the game's
-- nameplate fill and its dark ground with General at the game's), and a
-- cast bar under it as the Cast bars page dresses it.
local PLATE_FILL, PLATE_GROUND = "UI-HUD-CoolDownManager-Bar", "UI-HUD-CoolDownManager-Bar-BG"
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

function ns.MakeGeneralPlatePreview(parent, width)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 200)
	if holder.SetClipsChildren then holder:SetClipsChildren(true) end
	local caption = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetPoint("TOPLEFT", 6, -5)
	caption:SetText(L["Preview"])
	caption.searchSkip = true
	local plate = CreateFrame("Frame", nil, holder)
	plate:SetSize(140, 40)
	plate:SetScale(1.6)
	plate:SetPoint("CENTER", holder, "CENTER", 0, 10)
	local health = CreateFrame("StatusBar", nil, plate)
	health:SetSize(140, 10)
	health:SetPoint("TOP", plate, "TOP", 0, -14)
	health:SetMinMaxValues(0, 1)
	health:SetValue(0.7)
	local ground = health:CreateTexture(nil, "BACKGROUND")
	ground:SetPoint("TOPLEFT", -2, 2)
	ground:SetPoint("BOTTOMRIGHT", 2, -2)
	local back = health:CreateTexture(nil, "BACKGROUND", nil, -1)
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.6)
	local border = ns.MakeStyleEdges(health)
	local name = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("BOTTOM", health, "TOP", 0, 3)
	name:SetText(L["Gnoll Brute"])
	name.searchSkip = true
	local own = { name:GetFont() }
	local cast = ns.MakePlateCastSample and ns.MakePlateCastSample(plate)
	if cast then cast:SetPoint("TOP", health, "BOTTOM", 0, -3) end
	function holder:Refresh()
		ns.StyleScene(self, 0.55, 0.85)
		local db = ns.db
		local on = db and db.styleGeneral
		local general = on and db or ns.DEFAULTS
		-- (Its fill: General's texture, or the game's nameplate fill.)
		if not ns.SetBarTexture(health, on and general.styleTexture or "game") then
			local game = HasAtlas(PLATE_FILL) and PLATE_FILL or "Interface\\TargetingFrame\\UI-StatusBar"
			health:SetStatusBarTexture(game)
			health:GetStatusBarTexture():SetDesaturated(false)
		end
		health:SetStatusBarColor(0.85, 0.12, 0.1)
		ns.DressThemeVeil(health, "plate")
		-- (Its border: General's, or the game's ground with its outline.)
		local kind, size, r, g, b = ns.StyleBorder(general, "styleBorder")
		local game = kind == "game"
		ground:SetShown(game)
		if game then
			if HasAtlas(PLATE_GROUND) then ground:SetAtlas(PLATE_GROUND) else ground:SetColorTexture(0, 0, 0, 0.7) end
		end
		back:SetShown(not game)
		border:SetShown(kind == "line")
		if kind == "line" then ns.DressStyleEdges(border, size, r, g, b, 1, true) end
		-- (Its name: General's font and outline.)
		local file, height, flags = own[1], own[2], own[3]
		if file and height then
			local font, outline = general.styleFont, tonumber(general.styleOutline) or -1
			if ROMAN then
				file = ns.StyleFontFile(font) or file
			end
			if outline >= 0 and ns.OutlinedFlags then flags = ns.OutlinedFlags(flags, outline) end
			name:SetFont(file, height, flags or "")
			name:SetText(L["Gnoll Brute"])
		end
		name:SetTextColor(1, 0.25, 0.2)
		if cast then cast:Refresh() end
	end
	holder:SetScript("OnShow", holder.Refresh)
	return holder
end

-- The preview: one big screen showing the pages' own previews in turn, in
-- this order, a new one every few seconds fading in over the last; arrows
-- step back and forth (and start the wait again). Each is held to one size
-- (what's past it clipped). (The Visions hub's Style page shows its own
-- list: ns.MakeStyleJumbotron.)
local CELLS = {
	{ "Unit frames", "MakeUnitStylePreview" },
	{ "Raid frames", "MakeRaidStylePreview" },
	{ "Nameplate", "MakeGeneralPlatePreview" },
	{ "Personal Resource Display", "MakePersonalPreview" },
	{ "Tooltips", "MakeTooltipPreview" },
	{ "Chat bubbles", "MakeBubblePreview" },
	-- (The Visions' own are on the Visions hub's Style page. sized: a cell
	-- given the screen's height, as Card Vision's there.)
}
local ROTATE_SECONDS, FADE_SECONDS = 6, 0.6
local NAME_H = 24 -- (the page's name over the screen; the screen as high as every Style preview's)

local function MakePreview(parent, width, list)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, NAME_H + ns.StylePreviewHeight())
	local name = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("TOPLEFT", 0, -5)
	name.searchSkip = true
	local count = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	count:SetPoint("LEFT", name, "RIGHT", 6, 0)
	count.searchSkip = true
	local cells = {}
	for _, info in ipairs(list or CELLS) do
		local make = ns[info[2]]
		if make then
			local cell = make(holder, width, info.sized and ns.StylePreviewHeight() or nil)
			cell:SetScript("OnShow", nil) -- (drawn by holder:Refresh)
			cell:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -NAME_H)
			cell:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -NAME_H) -- (as wide as the page makes it)
			if cell.SetClipsChildren then cell:SetClipsChildren(true) end
			-- (Held to the screen's size after each drawing, its own too: Roll
			-- Vision's sizes itself to its cards as they tick.)
			local own = cell.Refresh
			function cell:Refresh(...)
				if own then own(self, ...) end
				local height = ns.StylePreviewHeight()
				if math.abs(self:GetHeight() - height) > 0.5 then
					self:SetHeight(height)
				end
				ns.RecutStyleScene(self) -- (its shape: the screen's width may have changed too)
			end
			cell:Hide()
			cells[#cells + 1] = { frame = cell, name = L[info[1]] }
		end
	end
	local current, waited, fading = 1, 0, nil -- (fading: the one going, under the one coming in)
	local function ShowOnly(index)
		for i, other in ipairs(cells) do
			other.frame:SetShown(i == index or (fading and i == fading.index))
		end
	end
	function holder:Refresh()
		local cell = cells[current]
		if not cell then return end
		ShowOnly(current)
		name:SetText(cell.name)
		count:SetText(("%d / %d"):format(current, #cells))
		cell.frame:Refresh()
	end
	local function EndFade()
		if not fading then return end
		cells[fading.index].frame:Hide()
		fading = nil
		local cell = cells[current]
		if cell then cell.frame:SetAlpha(1) end
	end
	local function Step(by)
		if #cells < 2 then return end
		EndFade()
		local was = current
		current = (current - 1 + by) % #cells + 1
		waited = 0
		-- (The new one over the old, from clear.)
		local base = holder:GetFrameLevel()
		cells[was].frame:SetFrameLevel(base + 1)
		cells[current].frame:SetFrameLevel(base + 10)
		cells[current].frame:SetAlpha(0)
		fading = { index = was, time = 0 }
		holder:Refresh()
	end
	-- (The arrows, in the screen's top right as the other previews' buttons,
	-- over the pages fading in.)
	for _, side in ipairs({ { 30, "Prev", -1 }, { 6, "Next", 1 } }) do
		local arrow = CreateFrame("Button", nil, holder)
		arrow:SetSize(24, 24)
		arrow:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -side[1], -NAME_H - 4)
		arrow:SetFrameLevel(holder:GetFrameLevel() + 30)
		local art = "Interface\\Buttons\\UI-SpellbookIcon-" .. side[2] .. "Page-"
		arrow:SetNormalTexture(art .. "Up")
		arrow:SetPushedTexture(art .. "Down")
		arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		arrow:SetScript("OnClick", function() Step(side[3]) end)
		if side[3] < 0 then holder.prevArrow = arrow end
	end
	holder:SetScript("OnShow", function(self) EndFade(); waited = 0; self:Refresh() end)
	ns.SetOnUpdate(holder, function(_, elapsed)
		if fading then
			fading.time = fading.time + elapsed
			local cell = cells[current]
			if fading.time >= FADE_SECONDS then
				EndFade()
			elseif cell then
				cell.frame:SetAlpha(fading.time / FADE_SECONDS)
			end
		end
		waited = waited + elapsed
		if waited >= ROTATE_SECONDS then Step(1) end
	end)
	return holder
end

-- A page's rotating preview of the given cells ({ name, maker, sized = }),
-- with Pop out left of its arrows, on the page's stack.
function ns.MakeStyleJumbotron(kit, content, stack, width, list)
	local preview = MakePreview(content, width, list)
	preview.headHeight = NAME_H -- (its name over the screen: StylePages.lua)
	stack:Add(preview, "label")
	local pop = ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	-- (left of the arrows, not over them)
	pop:ClearAllPoints()
	pop:SetPoint("RIGHT", preview.prevArrow, "LEFT", -6, 0)
	kit.AddControl(preview)
	return preview
end

-- The pages list: each page, whether it follows General, and a button to
-- put it back on General. Gives what's the page's own, and whether any of it
-- is as the theme set it (that isn't yours: the themes' raid names, say).
local function PageStatus(keys)
	local db = ns.GetDB()
	local own, themed = {}, false
	for _, key in ipairs(keys) do
		if db and not ns.IsGeneralStyle(db[key]) then
			local theme = ns.ThemeSetting(key)
			if theme ~= nil and db[key] == theme then
				themed = true
			else
				local entry = ns.SHARED_STYLE[key]
				own[#own + 1] = L[KIND_NAMES[entry and entry.kind] or "Texture"]
			end
		end
	end
	return own, themed
end


-- General's two folder tabs: General and Pages (picked 1 or 2). title: the
-- page's, put under them.
local function StyleTabs(content, title, picked)
	local panel = ns.PageTabs(content, {
		{ L["General"], "Style General", L["The theme, quick settings and the switch for every Style page."] },
		{ L["Pages"], "Style Pages", L["Which Style pages follow General, and which have settings of their own."] },
		{ L["Overrides"], "Style Overrides", L["Hide or show parts of the unit frames and nameplates, whatever the Interface pages' rows say."] },
	}, picked)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
end

ns.StyleTabs = StyleTabs -- (StyleOverrides.lua)

function ns.CreateGeneralStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["General"])
	StyleTabs(content, title, 1)
	local intro = kit.PageIntro(content, title,
		L["Every Style page at once: a switch for them all, and the settings they share. Each page's shared " ..
		"settings start on General and follow it; change one on its page and it's that page's own."])

	local preview, sample -- (below: drawn again as each setting changes)
	local function Changed()
		RefreshAll()
		ns.ApplyMenuSkin() -- (Style off or on: the theme's menu colors go or come back)
		if preview then preview:Refresh() end
		if sample then sample:Refresh() end
	end

	local switch = kit.PageSwitch(content, "styleGeneral", L["Enable Style"],
		L["On: every Style page looks as it says. Off: none of them do; everything shows the game's look. " ..
		"Each page keeps its settings for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "styleGeneral")

	preview = ns.MakeStyleJumbotron(kit, content, stack, 480)

	-- (The whole look in one pick: StyleThemes.lua.)
	stack:Header(content, L["Theme"])
	stack:Help(content, L["A whole look for the addon: bars, fonts, borders, panels, colors and these menus. Every " ..
		"setting below stays yours to change after you pick one. Undo puts back what you had."])
	stack:Add(ns.MakeThemePicker(kit, content, 480, function() Changed() end), "label")

	-- (On top of whichever theme's picked: each shows as the theme's "with your changes".)
	stack:Header(content, L["Quick settings"])
	stack:Help(content, L["Make a theme your own. These stay until you pick a theme or use Reapply theme."])
	local titleFont = ns.ThemeTitleFontField()
	rows.Font(ns.ThemeQuickField("styleFont"), L["The words on every page that follows General. Russian, Korean or " ..
		"Chinese text keeps the game's, so its letters show."], nil, nil, L["Text font:"])
	rows.Font(titleFont, L["The big words on cards, like a zone's name. Cards with a look of their own keep it."],
		nil, nil, L["Title font:"])
	rows.Font(ns.ThemeSmallFontField(), L["The names on unit and raid frames. They're small, so a sturdy font reads " ..
		"best."], nil, nil, L["Small names font:"])
	rows.Texture(L["Bar texture:"], ns.ThemeQuickField("styleTexture"), L["Every page's bars that follow General. The game's: each " ..
		"page's own. Below the game's own few: any other addon shares (through LibSharedMedia)."], nil,
		{ 0.25, 0.75, 0.3 })
	rows.Dropdown(L["Panel shape:"], ns.ThemeQuickField("stylePanel"), function()
		return { { value = "square", text = L["Square"] }, { value = "round", text = L["Rounded"] },
			{ value = "chamfer", text = L["Chamfered"] }, { value = "blade", text = L["Blade"] },
			{ value = "notch", text = L["Notched"] }, { value = "sigil", text = L["Sigil"] },
			{ value = "veil", text = L["Veil"] }, { value = "deco", text = L["Stepped"] },
			{ value = "plate", text = L["Plate"] }, { value = "leaf", text = L["Leaf"] },
			{ value = "facet", text = L["Faceted"] }, { value = "soft", text = L["Soft"] } }
	end, L["The outline of tooltips, chat bubbles, dialogue and roll panels."])
	rows.Dropdown(L["Bar shape:"], ns.ThemeQuickField("styleBarShape"), function()
		return { { value = "square", text = L["Square"] }, { value = "capsule", text = L["Capsule"] },
			{ value = "chisel", text = L["Chiseled"] }, { value = "soft", text = L["Soft"] },
			{ value = "bevel", text = L["Beveled"] } }
	end, L["The ends of unit frame and personal resource bars. A straight border can't follow a shape, so it goes " ..
		"while one's picked. Raid tiles and nameplates stay square."])
	-- (The game's own nameplate Style, retail's Options > Nameplates: held while
	-- one's picked, yours back after, PlateHealthStyle.lua. Only where the client
	-- has it: the classic clients keep the CVar, 6 there, with no such option.)
	local styles = ns.GamePlateStyles()
	if styles then
		rows.Dropdown(L["Nameplate style:"], "stylePlate", function()
			local list = { { value = "game", text = L["The game's"], tip = L["Whatever the game's own Options have."] } }
			for i, name in ipairs(styles) do list[#list + 1] = { value = i - 1, text = L[name] } end
			return list
		end, L["The size and shape of the game's nameplates (Options, Nameplates, Style). Your own setting comes " ..
			"back if you pick The game's or turn Style off, and changing it in the game's Options wins."])
	end

	-- (The fonts as they'll look, here and now: a card only shows when one plays.)
	sample = CreateFrame("Frame", nil, content)
	sample:SetSize(480, 62)
	local sampleTitle = sample:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	sampleTitle:SetPoint("TOPLEFT", 0, -6)
	sampleTitle.searchSkip = true
	local sampleText = sample:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sampleText:SetPoint("TOPLEFT", sampleTitle, "BOTTOMLEFT", 0, -6)
	sampleText.searchSkip = true
	local titleSize, textSize = select(2, sampleTitle:GetFont()), select(2, sampleText:GetFont())
	local gameTitle, gameText = sampleTitle:GetFont(), sampleText:GetFont()
	function sample:Refresh()
		local db = ns.GetDB()
		if ROMAN and db then
			sampleTitle:SetFont(ns.StyleFontFile(titleFont.get()) or gameTitle, titleSize * 1.5, "")
			sampleText:SetFont(ns.StyleFontFile(db.styleFont) or gameText, textSize, "")
		end
		sampleTitle:SetText(L["Windrunner Spire"])
		sampleText:SetText(L["Something has been taking the turnips at night."])
	end
	sample.pageSwitch = false
	stack:Add(sample, "label")
	kit.AddControl(sample)

	rows.Look(L["Outline and border:"], L["Shared look"], {
		texture = false,
		font = false,
		outline = { "styleOutline", L["A black border around the letters, on every page that follows General. " ..
			"The game's: as each page's default has it."], names = { [0] = L["None"], L["Thin"], L["Thick"] },
			own = L["The game's"] },
		outlineColor = false, -- (most pages' text is the game's: its outline is always black)
		shadow = { "styleShadow" },
		-- (Each page's own: its colors and sizes mean its own parts.)
		barColor = false, ground = false, textSize = false, textColor = false,
		border = { "styleBorder", L["The border round every page's bars, panels and buttons that follow " ..
			"General. The game's: as each page's default has it. Custom: its thickness and color under it."],
			opts = { game = true } },
	})

	-- (Reset page: the theme's palette and art as the profile has them; every
	-- other page's own settings stay theirs.)
	kit.OnReset(content, function()
		ns.GetDB().styleTheme = ns.ResetBase().styleTheme
		Changed()
	end)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Style General", L["General"])
end

-- The Pages tab: which pages follow General, kept off the General tab to keep
-- that one simple.
function ns.CreateStylePagesPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Pages"])
	StyleTabs(content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["Which pages follow General, or the Visions' Style page. From the theme: as the theme you picked set " ..
		"it. A page with a setting of your own shows which; Use General puts them back. The page's name opens it."])
	local stack = kit.Stack(intro, "label")
	local pageRows = {}
	local function Changed()
		RefreshAll()
		for _, row in ipairs(pageRows) do row:Refresh() end
	end

	-- (Only the pages this client has: one it lacks, like Roll Vision with no
	-- loot history, never set its defaults.)
	local pages = {}
	for _, page in ipairs(PAGES) do
		if not page[3][1] or ns.DEFAULTS[page[3][1]] ~= nil then pages[#pages + 1] = page end
	end
	for _, page in ipairs(pages) do
		if page.group then stack:Header(content, L[page.group]) end
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(480, 22)
		stack:Add(row, "label")
		local open = CreateFrame("Button", nil, row)
		open:SetSize(160, 22)
		open:SetPoint("LEFT")
		local name = open:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("LEFT")
		name:SetText(L[page[1]])
		open:SetScript("OnClick", function() ns.OpenOptions(page[2]) end)
		open:SetScript("OnEnter", function() name:SetTextColor(1, 0.82, 0) end)
		open:SetScript("OnLeave", function() name:SetTextColor(1, 1, 1) end)
		local status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		status:SetPoint("LEFT", open, "RIGHT", 4, 0)
		status.searchSkip = true
		local back = ns.PanelButton(row)
		back:SetSize(100, 20)
		back:SetPoint("LEFT", status, "RIGHT", 10, 0)
		back:SetText(L["Use General"])
		kit.Tooltip(back, L["This page's shared settings back on General, or as the theme set them."])
		back:SetScript("OnClick", function()
			local db = ns.GetDB()
			for _, key in ipairs(page[3]) do
				local theme = ns.ThemeSetting(key)
				if theme ~= nil then db[key] = theme else db[key] = ns.DEFAULTS[key] end
			end
			Changed()
			kit.Refresh()
		end)
		function row:Refresh()
			local own, themed = PageStatus(page[3])
			if #own == 0 then
				local follows = page.visions and L["Follows Visions Style"] or L["Follows General"]
				status:SetText(page.fixed and L[page.fixed] or themed and L["From the theme"] or follows)
				status:SetTextColor(0.6, 0.6, 0.6)
				back:Hide()
			else
				status:SetText(L["Its own:"] .. " " .. table.concat(own, ", "))
				status:SetTextColor(1, 0.82, 0)
				back:Show()
			end
		end
		pageRows[#pageRows + 1] = row
	end

	-- (Reset page: the pages listed back on General, as the profile has them.)
	kit.OnReset(content, function()
		local db, base = ns.GetDB(), ns.ResetBase()
		for _, page in ipairs(pages) do
			for _, key in ipairs(page[3]) do db[key] = base[key] end
		end
		Changed()
	end)

	local shown = kit.PageShown(kit.Refresh, content)
	canvas:SetScript("OnShow", function()
		for _, row in ipairs(pageRows) do row:Refresh() end
		shown()
	end)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Style Pages", L["Pages"])
end
