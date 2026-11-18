-- The Cards page (Cards.lua's), in the Visions hub under one icon with two
-- folder tabs. Events: a row for each event, its tick and its Show in row
-- (GridRows.lua), as the frames pages' grids, and under each the style it
-- uses, with buttons to its own pages. Card Types: the styles the cards start
-- from, each changed for every card using it. An event's own pages, opened
-- from its row (no tabs on the page's: their own three, and a way back):
-- Settings, what's its alone (when it fires, its lines, its words); Style,
-- its look (the style it starts from, each setting following it until it's
-- given its own); Sounds.

local _, ns = ...
local L = ns.L

local NOTE_W = 440
-- The event an event's own pages show (the buttons under the Events tab's
-- rows and the links on other pages pick one), and the style the Card Types
-- tab shows.
local CARD = { now = "combatIn", style = "third" }

-- The page's tabs, picked 1 to 3. title: the page's, put under them.
local function CardTabs(content, title, picked)
	local panel = ns.PageTabs(content, {
		{ L["Events"], "Card Vision", L["Each event's card on or off, and where it shows."] },
		{ L["Card Types"], "Card Styles", L["The card types the cards start from: change one for every card using it."] },
		{ L["Settings"], "Card General", L["Settings for every card."] },
	}, picked)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
end

-- An event's own pages' top: the page's two tabs, Events lit (it's under
-- it; a click goes back to it), the event's icon and name as the title, and
-- under them a row of smaller folder tabs, one for each of its three pages
-- (picked 1 to 3). Gives a frame to put the page under (kit.PageIntro's
-- under).
local PAGES = {
	{ "Settings", "Card Settings", "What's this card's alone: when it shows, its lines, its words." },
	{ "Style", "Card Style", "How this card looks, with a preview." },
	{ "Sounds", "Card Sounds", "What this card plays as it shows." },
}
local function CardTop(kit, content, title, picked)
	local panel = ns.PageTabs(content, {
		{ L["Events"], "Card Vision", L["Back to every card's row."], true },
		{ L["Card Types"], "Card Styles", L["The card types the cards start from: change one for every card using it."] },
	}, 1)
	local icon = content:CreateTexture(nil, "ARTWORK")
	icon:SetSize(24, 24)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -10)
	title:ClearAllPoints()
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	local list = {}
	for i, page in ipairs(PAGES) do list[i] = { L[page[1]], L[page[3]] } end
	local sub, subTabs, ShowSub, subBase, subH = ns.FolderTabs(content, list, function(i)
		if i ~= picked then ns.ShowHubPage(PAGES[i][2]) end
	end)
	-- (Each tab a container for the event shown, 2026-11-17: its own switch
	-- per event, "tabOn:Card:<id>:<part>": off, no card, its card type's
	-- look, or no sound (Cards.lua's ns.CardPartOff); this page greyed with it.)
	local PARTS = { "settings", "style", "sounds" }
	local checks = {}
	local function PartKey(id, i) return ("tabOn:Card:%s:%s"):format(id, PARTS[i]) end
	local function PartSwitches(id)
		for i, tab in ipairs(subTabs) do
			local key = PartKey(id, i)
			if not checks[key] then
				local frame = CreateFrame("Frame", nil, content)
				frame:SetSize(1, 1)
				checks[key] = kit.PageSwitch(frame, key, L["Enable Page"], L["Turns this tab of the card on or off."], frame)
				ns.SetPageMaster({ key }, "cards")
				ns.DEFAULTS[key] = true -- (on to start; /cine debug sweep: not a leak)
				if ns.db and ns.db[key] == nil then ns.db[key] = true end
			end
			tab:SetFlip(key)
		end
		ns.SetPageGate(content, PartKey(id, picked))
	end
	subBase:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -(44 + subH))
	sub:SetPoint("TOPLEFT", subBase, "TOPLEFT")
	sub:SetPoint("RIGHT", content, "RIGHT", -8, 0)
	sub:SetHeight(1) -- (just its top edge, a line under the tabs)
	ShowSub(picked)
	local under = CreateFrame("Frame", nil, content)
	under:SetSize(1, 1)
	under:SetPoint("TOPLEFT", subBase, "TOPLEFT", 8, -6)
	local holder = CreateFrame("Frame", nil, content)
	holder:SetSize(1, 1)
	holder:Hide()
	holder.pageSwitch = false
	holder.Refresh = function()
		local event = ns.CARD_BY_ID[CARD.now] or ns.CARD_EVENTS[1]
		icon:SetTexture(event.icon)
		title:SetText(L[event.name])
		PartSwitches(event.id)
	end
	kit.AddControl(holder)
	return under
end

-- For the pages its moments used to be on: a line saying where they are
-- now, and a button there (event: the Settings tab with that one picked).
-- A frame holding both, to anchor or stack.
function ns.CardsLink(content, text, event)
	local kit = ns.lowHealthKit
	local holder = CreateFrame("Frame", nil, content)
	holder:SetSize(420, 22)
	local label = kit.Label(holder, "GameFontHighlightSmall", text)
	label:SetPoint("LEFT", 2, 0)
	local button = ns.PanelButton(holder)
	button:SetSize(110, 22)
	button:SetText(L["Card Vision"])
	kit.Tooltip(button, L["Opens the Card Vision page."])
	button:SetScript("OnClick", function()
		if event then CARD.now = event end
		ns.OpenOptions(event and "Card Settings" or "Card Vision")
	end)
	button:SetPoint("LEFT", label, "RIGHT", 10, 0)
	return holder
end

-- Where a played card's parts are on its stage (from its bottom left), left
-- right bottom top; nil with none. Parts nearly the stage's size (a screen
-- edge pulse, a full-width bar) aren't counted: they'd hide how small it is.
local function CardBounds(stage)
	local sl, sb, ss = stage:GetLeft(), stage:GetBottom(), stage:GetEffectiveScale()
	if not (sl and sb and ss and ss > 0) then return end
	local W, H = stage:GetSize()
	local l, r, b, t
	local function Take(object, k)
		if not object:IsVisible() then return end
		local ol, orr, ob, ot = object:GetLeft(), object:GetRight(), object:GetBottom(), object:GetTop()
		if not (ol and orr and ob and ot) then return end
		ol, orr, ob, ot = ol * k - sl, orr * k - sl, ob * k - sb, ot * k - sb
		local w, h = orr - ol, ot - ob
		if w <= 0 or h <= 0 or w > W * 0.8 or h > H * 0.8 then return end
		l, r = math.min(l or ol, ol), math.max(r or orr, orr)
		b, t = math.min(b or ob, ob), math.max(t or ot, ot)
	end
	local function Walk(frame, depth)
		local k = frame:GetEffectiveScale() / ss
		for _, region in ipairs({ frame:GetRegions() }) do Take(region, k) end
		if depth < 4 then
			for _, child in ipairs({ frame:GetChildren() }) do Walk(child, depth + 1) end
		end
	end
	Walk(stage, 0)
	return l, r, b, t
end

-- The preview: the screen's shape (or a height given), the scene behind, a
-- card played on it, the event which() gives (nil: the Zone's, the zone
-- you're in), in the look lookOf() gives (nil: the event's). The General
-- page's screen too. Zoomed in on the card (2026-11-17: it's drawn the size
-- it is on your screen, a sliver in the preview): up to CARD_ZOOM times, till
-- it's half the preview's width or height, as near its middle as the stage
-- still covering the preview allows.
-- opts: { zoom, share } in place of those two; loop = true: the card plays
-- again after it's gone; zoomBy(): the card's size next to how it comes, so
-- the zoom fits the card as it comes and a bigger one shows bigger;
-- noCaption = true: no "Preview" in its corner.
local CARD_ZOOM, CARD_SHARE = 2, 0.5
function ns.MakeCardPreview(parent, width, fixedH, which, lookOf, opts)
	opts = opts or {}
	local maxZoom, share = opts.zoom or CARD_ZOOM, opts.share or CARD_SHARE
	local preview = CreateFrame("Frame", nil, parent)
	preview:SetSize(width, fixedH or 270)
	if preview.SetClipsChildren then preview:SetClipsChildren(true) end
	-- (The lens: the preview's window onto the stage, clipping it. The stage
	-- zoomed is the screen's size times the zoom, nearly all of it cut off;
	-- but a scroll frame's length counts what's cut off too (the Events tab's
	-- jumbotron scrolled 600 past its last row, and let go as it moved to the
	-- hub's corner, the length coming back with it, 2026-11-18). So on a
	-- scrolling page the lens is the scroll frame's, not in what it scrolls,
	-- laid over the preview, its level, alpha and showing kept to the
	-- preview's; elsewhere (held in the hub's corner, popped out) the
	-- preview's own.)
	local lens = CreateFrame("Frame", nil, preview)
	lens:SetAllPoints(preview)
	if lens.SetClipsChildren then lens:SetClipsChildren(true) end
	local stage = CreateFrame("Frame", nil, lens)
	stage:SetAllPoints()
	local function ScrollOf()
		local each = preview:GetParent()
		while each and each ~= UIParent do
			if each.GetObjectType and each:GetObjectType() == "ScrollFrame" then return each end
			each = each:GetParent()
		end
	end
	-- (A scroll frame cuts off only what it scrolls: the lens goes on a frame
	-- over its view that cuts off the rest, one for each scroll frame.)
	local function ViewClip(scroll)
		local clip = scroll.cardLensClip
		if not clip then
			clip = CreateFrame("Frame", nil, scroll)
			clip:SetAllPoints(scroll)
			if clip.SetClipsChildren then clip:SetClipsChildren(true) end
			clip.searchSkip = true
			scroll.cardLensClip = clip
		end
		return clip
	end
	-- (The screen's own buttons: its zoomSkip children (arrows, lock, pop out,
	-- zoom, Test), a jumbotron's (holder.prevArrow: GeneralStyle.lua) or the
	-- preview's own, listed on it once it has some, as they move off it.)
	local holder
	local function Buttons()
		holder = holder or (preview:GetParent().prevArrow and preview:GetParent() or preview)
		if not holder.lensButtons or #holder.lensButtons == 0 then
			holder.lensButtons = {}
			for _, child in ipairs({ holder:GetChildren() }) do
				if child.zoomSkip and child ~= preview then table.insert(holder.lensButtons, child) end
			end
		end
		return holder.lensButtons
	end
	local function Host()
		local scroll = ScrollOf()
		local host = scroll and ViewClip(scroll) or preview
		if lens:GetParent() ~= host then
			lens:SetParent(host)
			lens:ClearAllPoints()
			lens:SetAllPoints(preview)
		end
		if host ~= preview then
			-- (A clipping frame's children draw at its own level among its
			-- siblings, whatever theirs: the clip made at the scroll frame's
			-- level drew the card under the page, the preview's scene over it,
			-- 2026-11-18. So the clip is kept over the preview; it takes no
			-- clicks.)
			local over = preview:GetFrameLevel() + 2
			if host:GetFrameLevel() < over then host:SetFrameLevel(over) end
			if host:GetFrameStrata() ~= preview:GetFrameStrata() then host:SetFrameStrata(preview:GetFrameStrata()) end
			lens:SetFrameStrata(preview:GetFrameStrata())
			lens:SetFrameLevel(preview:GetFrameLevel() + 2)
			lens:SetAlpha(preview:GetEffectiveAlpha() / math.max(host:GetEffectiveAlpha(), 0.01))
			-- (The screen's own buttons (a jumbotron's arrows, lock, pop out and
			-- zoom: zoomSkip) kept over the card: what a scroll frame scrolls
			-- draws as one layer, under the clip, so raising them there did
			-- nothing. They go on the clip too while the lens is on it, over
			-- it, shown and faded with their screen.)
			local top = host:GetFrameLevel()
			local function Deepest(frame, depth)
				local level = frame:GetFrameLevel()
				if level > top then top = level end
				if depth < 4 then
					for _, child in ipairs({ frame:GetChildren() }) do Deepest(child, depth + 1) end
				end
			end
			Deepest(lens, 0)
			local buttons = Buttons()
			if #buttons > 0 then
				local carrier = holder.lensCarrier
				if not carrier then
					carrier = CreateFrame("Frame", nil, host)
					carrier:SetAllPoints(holder)
					holder.lensCarrier = carrier
				end
				if carrier:GetParent() ~= host then
					carrier:SetParent(host)
					carrier:ClearAllPoints()
					carrier:SetAllPoints(holder)
				end
				carrier:SetFrameStrata(preview:GetFrameStrata())
				if carrier:GetFrameLevel() <= top then carrier:SetFrameLevel(top + 1) end
				carrier:SetAlpha(holder:GetEffectiveAlpha() / math.max(host:GetEffectiveAlpha(), 0.01))
				carrier:SetShown(holder:IsVisible())
				for _, button in ipairs(buttons) do
					if button:GetParent() ~= carrier then button:SetParent(carrier) end
					if button:GetFrameLevel() <= carrier:GetFrameLevel() then button:SetFrameLevel(carrier:GetFrameLevel() + 5) end
				end
			end
		else
			lens:SetFrameLevel(preview:GetFrameLevel() + 2)
			lens:SetAlpha(1)
			-- (Its screen's buttons back on it, over the card.)
			for _, button in ipairs(Buttons()) do
				if button:GetParent() ~= holder then button:SetParent(holder) end
				button:SetFrameLevel(holder:GetFrameLevel() + 30)
			end
			if holder.lensCarrier then holder.lensCarrier:Hide() end
		end
		lens:SetShown(preview:IsVisible())
	end
	-- (/cine debug cardpage: where the lens is and how it's drawn.)
	function preview.LensState()
		local host = lens:GetParent()
		local function Box(f)
			local l, b, w, h = f:GetRect()
			return l and ("%.0f,%.0f %.0fx%.0f"):format(l, b, w, h) or "none"
		end
		return ("lens on %s lvl %d/%s, shown %s visible %s alpha %.2f; host lvl %d/%s; preview lvl %d/%s %s; stage %s x%.2f, %d parts")
			:format(host == preview and "preview" or "scroll clip", lens:GetFrameLevel(), lens:GetFrameStrata(),
			tostring(lens:IsShown()), tostring(lens:IsVisible()), lens:GetEffectiveAlpha(), host:GetFrameLevel(),
			host:GetFrameStrata(), preview:GetFrameLevel(), preview:GetFrameStrata(), Box(preview), Box(stage),
			stage:GetScale(), select("#", stage:GetChildren()) + select("#", stage:GetRegions()))
	end
	-- (Kept up each frame while the preview shows: a jumbotron fades its
	-- screens in and out, and the sticky preview moves to the hub and back.)
	local watch = CreateFrame("Frame", nil, preview)
	watch:SetSize(1, 1)
	watch:SetScript("OnShow", Host)
	watch:SetScript("OnHide", function()
		lens:Hide()
		-- (Only with the whole screen: the next card's lens shows them again.)
		if holder and holder.lensCarrier and not holder:IsVisible() then holder.lensCarrier:Hide() end
	end)
	ns.SetOnUpdate(watch, Host)
	if not opts.noCaption then
		local caption = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		caption:SetText(L["Preview"])
		caption:SetPoint("TOPLEFT", 6, -5)
		caption.searchSkip = true
	end
	function preview:Refresh()
		if not self:IsVisible() then
			return -- (the kit refreshes every page's controls)
		end
		if ns.FitStylePreview(self) then return end -- (resized: it played from there)
		Host() -- (the lens in place and shown first: the card's measured on it)
		local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
		local previewH = fixedH or math.floor(width * screenH / math.max(screenW, 1) + 0.5)
		self:SetHeight(previewH)
		ns.StyleScene(self)
		local id = which and which() or "zone"
		local card = ns.CardSample(id)
		if id == "zone" and not card.name then card.name = GetRealZoneText and GetRealZoneText() or "Darkshore" end
		card.sound = nil
		local look = lookOf and lookOf() or ns.CardLook(id)
		stage:SetScale(1)
		stage:ClearAllPoints()
		stage:SetAllPoints()
		local W = self:GetWidth()
		-- (opts.loop: played again a moment after it's gone, while it's on
		-- screen, so it's there whenever you look; one cut short by a new
		-- play doesn't call this.)
		local after
		if opts.loop then
			after = function()
				C_Timer.After(1.2, function()
					if self:IsVisible() then self:Refresh() end
				end)
			end
		end
		ns.PlayCard(stage, look, W, previewH, previewH / math.max(screenH, 1), card, after)
		local l, r, b, t = CardBounds(stage)
		if not l then return end
		local fit = math.min(W * share / math.max(r - l, 1), previewH * share / math.max(t - b, 1))
		-- (zoomBy's share is the card's size next to how it comes: the fit
		-- times it is the fit of the card as it comes, so a card made bigger
		-- shows bigger. Capped after.)
		if opts.zoomBy then fit = fit * math.max(opts.zoomBy(), 0.05) end
		local f = math.max(1, math.min(maxZoom, fit))
		if f <= 1.01 then return end
		-- (Its top left, down from the preview's, so the card's middle comes as
		-- near the preview's as can be with no edge of the stage showing.)
		local cx, cd = (l + r) / 2, previewH - (b + t) / 2
		local ox = math.max(W - W * f, math.min(0, W / 2 - cx * f))
		local od = math.max(previewH - previewH * f, math.min(0, previewH / 2 - cd * f))
		stage:ClearAllPoints()
		stage:SetSize(W, previewH)
		stage:SetScale(f)
		stage:SetPoint("TOPLEFT", self, "TOPLEFT", ox / f, -od / f)
	end
	return preview
end

-- (Dropdowns: { value, text, tip } each, read as it opens.)
local function List(choices)
	return function()
		local list = {}
		for i, choice in ipairs(choices) do list[i] = { value = choice[1], text = choice[2], tip = choice[3] } end
		return list
	end
end

-- The settings an event can have of its own, as the Style tab lists them.
local GROUPS = {
	{ "Place", { "Place" } }, { "Position", { "OffsetX", "OffsetY" } }, { "In the bar", { "Align" } }, { "Letterbox scale", { "BarScale" } },
	{ "No letterbox", { "BarFallback" } }, { "Style", { "Style" } }, { "Animation", { "Anim" } },
	{ "Font", { "Font" } }, { "Size", { "Size" } }, { "Capitals", { "Caps" } }, { "Word per line", { "Stack" } },
	{ "Outline", { "Outline" } },
	{ "Outline color", { "OutlineR", "OutlineG", "OutlineB" } }, { "Shadow", { "Shadow" } },
	{ "Color", { "R", "G", "B" } }, { "Small lines' font", { "SmallFont" } }, { "Small lines' size", { "SmallSize" } },
	{ "Small lines' color", { "SmallColor", "SmallR", "SmallG", "SmallB" } },
	{ "Stays", { "Hold" } }, { "Edge pulse", { "Pulse" } },
	{ "Pulse color", { "PulseR", "PulseG", "PulseB" } }, { "Icon", { "IconShow" } }, { "Icon picture", { "Icon" } },
}
local function OwnGroup(id, group)
	for _, field in ipairs(group[2]) do
		if ns.CardIsOwn(id, field) then return true end
	end
	return false
end
local function Follow(id, group)
	local db = ns.GetDB()
	for _, field in ipairs(group[2]) do db[ns.CardKey(field, id)] = "default" end
end
-- The names of an event's own settings, in the list's order.
local function OwnNames(id)
	local names = {}
	for _, group in ipairs(GROUPS) do
		if OwnGroup(id, group) then names[#names + 1] = L[group[1]] end
	end
	return names
end

-- The look's settings on one screen, for the Style and Card Types tabs: two
-- columns of small groups under the preview, each setting's choices in sight.
-- Each row is an ordinary style row (ns.StyleRows), placed by the grid instead
-- of a stack. fieldOf: the tab's (the picked event's or style's settings). own:
-- { Is(group), Put(group), tip }: a setting changed here shows a gold dot, and
-- a click on it puts that one back. icon: a button for an event's own icon,
-- after the Icon tick.
local CELL_ROW, CELL_W, CELL_GAP = 28, 280, 26
local CELL_NAMES = { 78, 66 }              -- the names' width in each column: controls start past it
local CELL_LEFT = 12                       -- (room for the dots, left of each column)
local CELL_RIGHT = CELL_LEFT + CELL_W + CELL_GAP
local CELL_PAD, CELL_HEAD = 7, 22          -- a group's panel round it, its name's height
local CELL_SPLIT = 6                       -- the gap between two groups' panels
local CELL_BOX_NUDGE = 5                   -- a number box draws this far left of where it's put
local CELL_TICK_NUDGE = 5                  -- ...and a tick's box this far right
local CELL_SECOND_X, CELL_SECOND_W = 136, 66 -- a second number on a row: its name's place and width
local function LookGrid(kit, content, stack, fieldOf, changed, own, icon)
	local grid = CreateFrame("Frame", nil, content)
	stack:Add(grid, "label")
	-- (What the rows place themselves with, in stack's place.)
	local at = { x = CELL_LEFT, y = CELL_PAD, name = CELL_NAMES[1] }
	function at:Add(control)
		control:SetPoint("TOPLEFT", grid, "TOPLEFT", self.x, -self.y)
		self.last = control
		self.y = self.y + CELL_ROW
		return control
	end
	local rows = ns.StyleRows(kit, content, at, changed, "cards", fieldOf)
	local On, Get = rows.On, rows.Get
	local function Banner() return Get("cardStyle") == "banner" end
	local function BarUp()
		local place = Get("cardPlace")
		return not Banner() and (place == "top" or place == "bottom")
	end
	local function InBar(db) return On(db) and BarUp() end

	-- A group's name and, later, the panel behind it (on the page itself:
	-- under every control).
	local function Head(text)
		local head = kit.Label(content, "GameFontNormal", text)
		head:SetPoint("TOPLEFT", grid, "TOPLEFT", at.x, -at.y)
		at.y = at.y + CELL_HEAD
		return head
	end
	local function Panel(x, top, bottom)
		local panel = content:CreateTexture(nil, "BACKGROUND")
		panel:SetPoint("TOPLEFT", grid, "TOPLEFT", x - CELL_LEFT + 1, -(top - CELL_PAD))
		panel:SetSize(CELL_W + CELL_LEFT + 8, bottom - top + CELL_PAD * 2)
		panel:SetColorTexture(1, 1, 1, 0.045)
		panel.top = top
		return panel
	end
	local function PanelTo(panel, bottom) panel:SetHeight(bottom - panel.top + CELL_PAD * 2) end
	-- A control's width after a row's name, in the column it's in.
	local function Field() return CELL_W - at.name - 4 end
	-- This row's dot (the groups it stands for by their names in GROUPS),
	-- shown while any has a value of its own. only: and while this holds.
	local function Dot(names, only)
		local dot = CreateFrame("Button", nil, content)
		dot:SetSize(9, 9)
		dot:SetPoint("TOPLEFT", grid, "TOPLEFT", at.x - 12, -(at.y + 7))
		local mark = dot:CreateTexture(nil, "ARTWORK")
		mark:SetAllPoints()
		mark:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		mark:SetVertexColor(1, 0.82, 0, 1)
		kit.Tooltip(dot, own.tip)
		dot.pageSwitch = false
		dot.searchSkip = true
		local function Each(fn)
			for _, group in ipairs(GROUPS) do
				for _, name in ipairs(names) do
					if group[1] == name and fn(group) then return true end
				end
			end
		end
		dot:SetScript("OnClick", function()
			Each(function(group) own.Put(group) end)
			changed()
			kit.Refresh()
		end)
		dot.Refresh = function(self)
			self:SetShown((not only or only()) and Each(own.Is) or false)
		end
		kit.AddControl(dot)
		return dot
	end
	local function Name(label)
		local name = at:Add(kit.Label(content, "GameFontHighlight", label))
		name:SetSize(at.name, 24)
		name:SetJustifyH("LEFT")
		name:SetJustifyV("MIDDLE")
		return name
	end
	-- A row's name as a style row left it, narrowed; dropdown: its dropdown.
	-- label: the name, where the row has its own way of writing it.
	local function Narrow(dropdown, width, label)
		if not dropdown then return end
		at.last:SetSize(at.name, 24)
		if label then at.last:SetText(label) end
		dropdown:SetWidth(width or Field())
		return dropdown
	end
	-- A number with its name at the left, its box where the column's controls
	-- start. second: the second on the row just made, in a place of its own,
	-- so the numbers line up from row to row. Gives its line and name.
	local dimmed = {}
	local function Number(key, label, minV, maxV, step, fmt, scale, tip, test, second)
		local x, width = at.x, at.name
		if second then
			at.x, at.y, width = x + CELL_SECOND_X, at.y - CELL_ROW, CELL_SECOND_W
		end
		local name = Name(label)
		name:SetWidth(width)
		if second then name:SetJustifyH("RIGHT") end
		at.x, at.y = at.x + width + 4 + CELL_BOX_NUDGE, at.y - CELL_ROW + 1
		local line = rows.Slider(key, "", minV, maxV, step, fmt, scale, tip, test)
		at.x, at.y = x, at.y - 1
		if test then dimmed[#dimmed + 1] = { name, test } end
		return line, name
	end
	-- A tick, its box in line with the rows' names.
	local function Tick(key, label, tip, test)
		at.x = at.x - CELL_TICK_NUDGE
		local check = rows.Check(key, label, tip, test)
		at.x = at.x + CELL_TICK_NUDGE
		return check
	end
	-- A flat button for one value of key, lit while it's picked.
	local function Flat(width, height, key, value, text, tip, test)
		local button = CreateFrame("Button", nil, content)
		button:SetSize(width, height)
		local level = button:GetFrameLevel()
		local edge = button:CreateTexture(nil, "BACKGROUND")
		edge:SetAllPoints()
		local fill = button:CreateTexture(nil, "BORDER")
		fill:SetPoint("TOPLEFT", 1, -1)
		fill:SetPoint("BOTTOMRIGHT", -1, 1)
		local glow = button:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints(fill)
		glow:SetColorTexture(1, 1, 1, 0.08)
		local label = kit.Label(button, "GameFontHighlightSmall", text)
		label:SetPoint("BOTTOMLEFT", 2, 5)
		label:SetPoint("BOTTOMRIGHT", -2, 5)
		label:SetJustifyH("CENTER")
		label:SetWordWrap(false)
		label.searchSkip = true
		button.searchLabel = text
		if tip then kit.Tooltip(button, tip) end
		button:SetScript("OnClick", function()
			rows.Put(key, value)
			changed()
			kit.Refresh()
		end)
		button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
		button:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
		button.Refresh = function()
			local on = Get(key) == value
			button:SetFrameLevel(level + (on and 1 or 0)) -- (over its neighbors, whose edges overlap its)
			edge:SetColorTexture(on and 1 or 0.34, on and 0.82 or 0.29, on and 0 or 0.2, 1)
			fill:SetColorTexture(on and 0.3 or 0, on and 0.23 or 0, on and 0.05 or 0, 0.85)
			local r, g, b = 0.75, 0.72, 0.65
			if on then r, g, b = 1, 0.85, 0.4 end
			label:SetTextColor(r, g, b, 1)
			label:SetVertexColor(r, g, b, 1) -- (one and the same on Forever)
		end
		kit.GreyUnless(button, test or On)
		kit.AddControl(button)
		return button
	end
	-- A row of them: { value, text, tip } each, after a row's name. Gives what
	-- to put more after, and its buttons.
	local function Buttons(name, key, list, test, width)
		width = width or Field()
		local each = (width + #list - 1) / #list -- (their edges overlap by 1)
		local holder = CreateFrame("Frame", nil, content)
		holder:SetSize(width, 22)
		holder:SetPoint("LEFT", name, "RIGHT", 4, 0)
		local made = {}
		for i, choice in ipairs(list) do
			made[i] = Flat(each, 22, key, choice[1], choice[2], choice[3], test)
			made[i]:SetPoint("LEFT", holder, "LEFT", (i - 1) * (each - 1), 0)
		end
		return holder, made
	end

	-- Left: where it goes.
	local top = at.y
	Head(L["Where"])
	Dot({ "Place" })
	local TILE_H, TILE_GAP = 52, 5
	local tileW = (CELL_W - TILE_GAP * 3) / 4
	-- { value, name, tip, the picture's bar: left and width of the screen, up its height, its height }
	local tiles = {
		{ "screen", L["Screen"], L["In the middle of the screen (a subtitle: low on it)."], 0.3, 0.4, 0.42, 0.16 },
		{ "top", L["Top bar"], L["Top letterbox bar"], 0, 1, 0.76, 0.24 },
		{ "bottom", L["Bottom bar"], L["Bottom letterbox bar"], 0, 1, 0, 0.24 },
		{ "third", L["Lower third"], L["Low on the left of the screen, as a film names someone, its line fading " ..
			"out to the right."], 0.08, 0.42, 0.2, 0.16 },
	}
	local function PlaceOn(db) return On(db) and not Banner() end
	local SCREEN_H = 28
	for i, tile in ipairs(tiles) do
		local button = Flat(tileW, TILE_H, "cardPlace", tile[1], tile[2], tile[3], PlaceOn)
		button:SetPoint("TOPLEFT", grid, "TOPLEFT", at.x + (i - 1) * (tileW + TILE_GAP), -at.y)
		local screen = button:CreateTexture(nil, "ARTWORK")
		screen:SetPoint("TOPLEFT", 5, -5)
		screen:SetPoint("TOPRIGHT", -5, -5)
		screen:SetHeight(SCREEN_H)
		screen:SetColorTexture(0.17, 0.21, 0.26, 1)
		local spot = button:CreateTexture(nil, "OVERLAY")
		local wide = tileW - 10
		spot:SetSize(wide * tile[5], SCREEN_H * tile[7])
		spot:SetPoint("BOTTOMLEFT", screen, "BOTTOMLEFT", wide * tile[4], SCREEN_H * tile[6])
		spot:SetColorTexture(0.95, 0.75, 0.25, 1)
	end
	at.y = at.y + TILE_H + 6
	Dot({ "Position" })
	Number("cardOffsetX", L["Move across"], -50, 50, 0.5, "%.1f%%", 100,
		L["Moves the card right, or left below 0."])
	Number("cardOffsetY", L["Move up"], -50, 50, 0.5, "%.1f%%", 100,
		L["Moves the card up, or down below 0."],
		nil, true)
	Panel(at.x, top, at.y - 4)

	-- ...how long, and what comes with it.
	at.y = at.y + CELL_PAD * 2 + CELL_SPLIT
	top = at.y
	Head(L["Timing and extras"])
	Dot({ "Stays", "Edge pulse", "Pulse color" })
	Number("cardHold", L["Stays"], 0.5, 12, 0.5, "%.1f s", 1,
		L["How long the card stays between fading in and out (Typewriter: once typed)."])
	local pulse = Number("cardPulse", L["Edge pulse"], 0, 100, 1, "%d%%", 100,
		L["How strongly the screen edges flash as the card shows; 0 for none."], nil, true)
	-- (At the column's end, where the Text column's swatches are at theirs.)
	local pulseColor = rows.Swatch(pulse, nil, { "cardPulseR", "cardPulseG", "cardPulseB" },
		L["Pick the pulse's color."], function(db) return On(db) and (tonumber(Get("cardPulse")) or 0) > 0 end)
	pulseColor:ClearAllPoints()
	pulseColor:SetPoint("TOPLEFT", grid, "TOPLEFT", at.x + CELL_W - 18, -(at.y - CELL_ROW + 3))
	Dot({ "Icon", "Icon picture" })
	local iconCheck = Tick("cardIconShow", L["Icon"], L["Shows an icon before the words."])
	iconCheck.noSettingId = true -- (the picked style's: no one setting for /cine find)
	if icon then icon(iconCheck) end
	local timingEnd = at.y - 4
	local timingPanel = Panel(at.x, top, timingEnd)

	-- ...and in a bar, with a bar picked: its group goes with it.
	at.y = at.y + CELL_PAD * 2 + CELL_SPLIT
	top = at.y
	local barParts = { Head(L["In the bar"]) }
	Dot({ "In the bar" }, BarUp)
	local barName = Name(L["Align"])
	local barAlign, barButtons = Buttons(barName, "cardAlign", {
		{ "left", L["Left"] },
		{ "center", L["Center"] },
		{ "right", L["Right"] },
	}, InBar)
	Dot({ "Letterbox scale" }, BarUp)
	local barScale, barScaleName = Number("cardBarScale", L["Scale"], 20, 100, 1, "%d%%", 100,
		L["The words' size compared to the letterbox bar."], InBar)
	Dot({ "No letterbox" }, BarUp)
	local barFallback = Narrow(rows.Dropdown(L["No letterbox"], "cardBarFallback", List({
		{ "bar", L["Its own bar"], L["A bar as tall as your letterbox's comes in for the card."] },
		{ "third", L["Lower third"], L["The card shows in the lower third."] },
		{ "screen", L["Screen center"], L["The card shows in the middle of the screen."] },
		{ "none", L["Don't show"], L["The card shows only while a letterbox is up."] },
	}), L["Where the card shows while no letterbox is up."], InBar))
	local barFallbackName = at.last
	local barEnd = at.y - 4
	local barPanel = Panel(at.x, top, barEnd)
	for _, part in ipairs({ barPanel, barName, barAlign, barScale, barScaleName, barFallback, barFallbackName }) do
		barParts[#barParts + 1] = part
	end
	for _, part in ipairs(barButtons) do barParts[#barParts + 1] = part end

	-- Right: the words.
	at.x, at.y, at.name = CELL_RIGHT, CELL_PAD, CELL_NAMES[2]
	Head(L["Text"])
	Dot({ "Style" })
	Buttons(Name(L["Style"]), "cardStyle", {
		{ "title", L["Title"], L["Big words in the middle of the screen, the rest under them."] },
		{ "subtitle", L["Subtitle"], L["A small line low on the screen, where a film's subtitles go."] },
		{ "chapter", L["Chapter"], L["The words over a line that draws out, as a new scene starts."] },
		{ "banner", L["Banner"], L["Big words across the middle of the screen on a dark band."] },
	})
	Dot({ "Animation" })
	-- (Two rows of them: five buttons on one cut their names short.)
	Buttons(Name(L["Animation"]), "cardAnim", {
		{ "fade", L["Fade"], L["The card fades in and out."] },
		{ "reveal", L["Reveal"], L["The words open out from their middle."] },
		{ "track", L["Tracking"], L["The letters start spread apart and close up, like a film title."] },
	})
	Buttons(Name(""), "cardAnim", {
		{ "type", L["Type"], L["The words appear a letter at a time, as if typed."] },
		{ "slam", L["Slam"], L["The words start big and slam down to size."] },
	}, nil, (Field() + 2) * 2 / 3 - 1)
	Dot({ "Font" })
	Narrow(rows.Font("cardFont", L["Words in Russian, Korean or Chinese keep the game's font, so their letters show."],
		nil, nil, L["Font"]))
	Dot({ "Size" })
	Number("cardSize", L["Size"], 14, 140, 1, "%d", 1,
		L["How tall the words are."], function(db) return On(db) and not BarUp() end)
	Dot({ "Capitals" })
	local caps = Tick("cardCaps", L["Capitals"], L["Shows the words in capital letters."])
	if caps then caps.noSettingId = true end
	Dot({ "Word per line" })
	local stacked = Tick("cardStack", L["Word per line"], L["Puts each word on a line of its own."])
	if stacked then stacked.noSettingId = true end
	-- (On its row, its swatch under the row's end, over the Outline's.)
	local COLOR_NAME = 60
	at.x, at.y = CELL_RIGHT + CELL_W - 28 - COLOR_NAME, at.y - CELL_ROW
	Dot({ "Color" })
	rows.Color(L["Color"], { "cardR", "cardG", "cardB" },
		L["The words' color; the lines with them in a lighter shade."])
	at.last:SetSize(COLOR_NAME, 24)
	at.last:SetJustifyH("RIGHT")
	at.last:SetJustifyV("MIDDLE")
	at.x = CELL_RIGHT
	Dot({ "Outline", "Outline color" })
	local outline = Narrow(rows.Outline("cardOutline", L["Outline"], 2, { [0] = L["None"], L["Thin"], L["Thick"] },
		L["A border around the letters."]), Field() - 28, L["Outline"])
	if outline then
		local after = CreateFrame("Frame", nil, content)
		after:SetSize(1, 1)
		after:SetPoint("LEFT", outline, "RIGHT", 0, 0)
		rows.Swatch(after, nil, { "cardOutlineR", "cardOutlineG", "cardOutlineB" }, L["Pick the outline's color."],
			function(db)
				local value = Get("cardOutline")
				if value == -1 then value = ns.GeneralStyleValue("cardOutline") end
				return On(db) and (tonumber(value) or 0) > 0
			end)
	end
	Dot({ "Shadow" })
	Narrow(rows.Dropdown(L["Shadow"], "cardShadow", function()
		return {
			{ value = "general", text = ns.SharedStyleSource("cardShadow") },
			{ value = "game", text = L["The game's"] },
			{ value = "on", text = L["Shadow"], tip = L["A dark copy of the letters just behind them, down and to " ..
				"the right."] },
			{ value = "none", text = L["None"] },
		}
	end))
	at.y = at.y + 6
	Head(L["Small lines"])
	Dot({ "Small lines' font" })
	Narrow(rows.Font("cardSmallFont", L["The small lines' font, over and under the words."], nil,
		{ "same", L["Same as the words"] }, L["Font"]))
	Dot({ "Small lines' size" })
	Number("cardSmallSize", L["Size"], 50, 250, 5, "%d%%", 100,
		L["Makes the small lines bigger or smaller."])
	Dot({ "Small lines' color" })
	local smallColor = Buttons(Name(L["Color"]), "cardSmallColor", {
		{ "auto", L["Automatic"], L["Picks a matching color automatically."] },
		{ "custom", L["Custom"], L["A color of your own (the swatch), for both lines."] },
	}, nil, Field() - 28)
	rows.Swatch(smallColor, "cardSmallColor", { "cardSmallR", "cardSmallG", "cardSmallB" },
		L["Pick the small lines' color."])
	local textEnd = at.y - 4
	local textPanel = Panel(at.x, CELL_PAD, textEnd)

	grid:SetSize(CELL_RIGHT + CELL_W, math.max(barEnd, textEnd) + CELL_PAD * 2)
	-- (The bar's group, only with a bar: at the column's bottom, so no gap's
	-- left. The two columns' panels end level, whichever's longer.)
	local watch = CreateFrame("Frame", nil, content)
	watch:SetSize(1, 1)
	watch:Hide()
	watch.pageSwitch = false
	watch.Refresh = function()
		local shown = BarUp()
		for _, part in ipairs(barParts) do part:SetShown(shown) end
		local bottom = math.max(textEnd, shown and barEnd or timingEnd)
		PanelTo(textPanel, bottom)
		PanelTo(barPanel, bottom)
		PanelTo(timingPanel, shown and timingEnd or bottom)
		grid:SetHeight(bottom + CELL_PAD * 2)
		for _, each in ipairs(dimmed) do each[1]:SetAlpha(each[2](ns.GetDB()) and 1 or 0.5) end
	end
	kit.AddControl(watch)
end

-- "2 of its own" and a button putting them all back, after after (x past it).
-- Count(): how many; Text(count): the words; All(): puts them back.
local function OwnLine(kit, content, after, x, width, Count, Text, All, tip, changed, On)
	local label = kit.Label(content, "GameFontHighlightSmall", "")
	label:SetWidth(width)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	label:SetPoint("LEFT", after, "RIGHT", x, 0)
	local reset = ns.PanelButton(content)
	reset:SetSize(80, 22)
	reset:SetText(L["Reset all"])
	reset:SetPoint("LEFT", label, "RIGHT", 6, 0)
	reset.pageSwitch = false
	kit.Tooltip(reset, tip)
	reset:SetScript("OnClick", function()
		All()
		changed()
		kit.Refresh()
	end)
	label.pageSwitch = false
	label.Refresh = function(self)
		local count = Count()
		self:SetText(Text(count))
		reset:SetShown(count > 0)
		reset:SetEnabled(On(ns.GetDB()))
	end
	kit.AddControl(label)
end

-- The preview on these tabs: low, so the settings fit under it. (As the screen
-- it's the page's width: the words are as big as in a taller one.)
local CARD_PREVIEW_H = 170
local function LowPreview(preview)
	local refresh = preview.Refresh
	preview.headHeight = CARD_PREVIEW_H - ns.StylePreviewHeight()
	function preview.Refresh(self)
		self.headHeight = CARD_PREVIEW_H - ns.StylePreviewHeight()
		return refresh(self)
	end
end

-- The style an event starts from, by name: a ready-made one (Cards.lua's
-- CARD_STYLES), or for a subzone following the zone, the zone's.
local function BaseName(id)
	local event = ns.CARD_BY_ID[id]
	local db = ns.GetDB()
	if event and event.parent and (db["cardBase_" .. id] or "follow") == "follow" then
		return L["Follows %s"]:format(L[ns.CARD_BY_ID[event.parent].name])
	end
	local base = ns.CardBase(id)
	local style = ns.CARD_STYLE_BY_ID[base]
	return style and L[style.name] or L["Lower third"]
end


-- The styles an event can start from, for a dropdown: the ready-made ones,
-- and for a subzone its zone's first.
local function StyleChoices(id)
	local list = {}
	local event = ns.CARD_BY_ID[id]
	if event and event.parent then
		list[#list + 1] = { value = "follow", text = L["Follows %s"]:format(L[ns.CARD_BY_ID[event.parent].name]),
			tip = L["Whatever card type that event starts from."] }
	end
	for _, style in ipairs(ns.CARD_STYLES) do list[#list + 1] = { value = style.id, text = L[style.name] } end
	return list
end
-- An event's starting style as a setting, for a dropdown.
local function BaseField(id)
	local key = "cardBase_" .. id
	return { get = function() return ns.GetDB()[key] end, set = function(value) ns.GetDB()[key] = value end }
end

-- Events: each event's tick and Show in row.
local TIPS = {
	combatIn = "As a fight starts: a word (Combat), a pulse around the screen's edges and a sound.",
	combatOut = "As a fight ends: a word (Respite) and a sound. Not after a fight shorter than its setting on " ..
		"the Settings tab.",
	boss = "A boss's name as its fight starts (or before it, as you first target it or come near it), the " ..
		"dungeon under it and \"Boss 2 of 3\" over it. Once a run for each boss, in place of Entering combat's.",
	zone = "As you come into a new zone, its name as a card in place of the game's own. The time of day at " ..
		"login goes on it.",
	subzone = "As you come into a subzone (a town, a camp, a landing) too, the zone's name small under it. Only " ..
		"with Zone ticked.",
	login = "On a real login (not a reload), what you did last time you played: where you spent the most time, " ..
		"quests done, a level reached and bosses killed. Only what happened, and nothing if nothing did; never " ..
		"in a fight, nor after more than two weeks away.",
	time = "When the time of day changes during play (not in combat), its name with a fitting sound: a rooster " ..
		"at dawn, a horse in the morning, your faction's bell at midday, frogs in the evening, an owl at dusk and " ..
		"a wolf at night.",
	attack = "When the LocalDefense channel says a place is under attack (\"Dun Algaz is under attack!\"), with " ..
		"your faction's city bell. The same place at most once every 90 seconds.",
	duel = "Your own duels: as you challenge someone or they challenge you, as it starts, and who won. Which of " ..
		"those and their words: the Settings tab.",
	cleared = "As a dungeon's or raid's last boss goes down: its name, the time since you came in and how many " ..
		"times you died.",
	discover = "A place new to you: a zone the first time you're there, a subzone as the game says you " ..
		"discovered it, a dungeon or raid the first time you go in. In place of the Zone or Subzone card.",
	newZone = "A whole zone new to you (Westfall, Duskwood) gets a card of its own: its name big in the middle of " ..
		"the screen, in place of Discovered's. Subzones, dungeons and raids stay on Discovered. Only with " ..
		"Discovered ticked.",
	departure = "As a flight takes off: where it's taking you, and about how long it takes on a route you've " ..
		"flown before. With a line along the top or bottom of the screen filling up on the way, if you like.",
	arrival = "As a flight lands: where it took you, and how long the flight took.",
	rested = "As you come into an inn or a city (not at login, not in a fight): the place's name. The same " ..
		"place at most once every 10 minutes.",
	levelUp = "As you reach a new level (after the fight, if you're in one): the level, the zone and how long " ..
		"it took this session. Max level at the cap.",
	achievement = "An achievement you earn: its name and points.",
	explore = "How much of a zone you've explored (\"The Barrens: 7 of 25 explored\"), as you discover one of its " ..
		"areas and as you come into it (once a session, until it's all done). At most once every 10 minutes.",
	almost = "An achievement with one step left after you do one: which step it is (\"1 left: Camp Taurajo\"). At most once every 10 minutes.",
	step = "A step of an achievement done (a dungeon for Classic Dungeoneer, a quest for a zone's quests): the " ..
		"achievement, the step and how many are done. Explore achievements' areas: Explore progress. At most " ..
		"once every 10 minutes.",
	reputation = "As your standing with a faction changes (\"Honored\", with whom under it), a Renown level " ..
		"or a friendship's rank: small in the top bar, but Exalted, Hated, the last Renown level and a " ..
		"friendship's top rank big, as Level up looks.",
	collect = "A new mount in your collection, big as Level up looks; a new pet, small in the top bar.",
	profession = "A profession learned, or its cap raised (Journeyman, Expert...).",
	quest = "As you turn in a story quest (campaign, important or legendary) or a dungeon, raid or elite one: " ..
		"its title.",
	rare = "A rare's name as you first target it, point at it or (out of fights) its nameplate shows. Once " ..
		"each a session.",
	battleground = "A battleground's or arena's name as the gates open, then Victory or Defeat.",
	streak = "Other players you kill without dying, at 2, 3, 5 and every 5 after.",
	death = "Shortly after the death camera starts: YOU DIED across the middle of the screen, \"wasted\" or " ..
		"words of your own. Only with the death camera on (the Die row on the Scenes page).",
	bossDown = "As a dungeon or raid boss goes down, or a world boss you fought: VICTORY ACHIEVED in the top " ..
		"bar in gold, its name under it. Its words: the Settings tab.",
	felled = "As a rare you have targeted dies (yours, not someone else's): ENEMY FELLED across the middle of " ..
		"the screen in gold, its name under it. Its words: the Settings tab.",
	revived = "As you come back to life, resurrected or back in your body: VITALITY RESTORED across the middle " ..
		"of the screen in gold, YOU DIED's other side.",
}
local FIGHT_OPTS = { anyFight = true, omit = { combatShow = true, enemyShow = true, friendlyShow = true } }
local STORY_OPTS = { anyFight = true, quiet = true, omit = { enemyShow = true, friendlyShow = true } }

-- The lists a Show in row's ticks are kept in (its Always: cardAlways_<id>).
local ROW_LISTS = { "combatShow", "calmShow", "quietShow", "camShow", "enemyShow", "friendlyShow", "bgShow",
	"worldShow", "cityShow", "groupShow", "instanceShow", "frameRules" }

-- A Test button says Stop while its card's moments play in turn (Now: its
-- event's id).
local function TestStops(button, Now)
	local wait = 0
	ns.HookOnUpdate(button, function(self, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.2
		self:SetText(ns.CardTestRunning(Now()) and L["Stop"] or L["Test"])
	end)
end

-- The Events tab's sections, one for each card type (2026-11-18): the nine
-- families always, in this order, each with a line on where and how it
-- shows; the other ready-made types only while an event uses them.
local TYPE_ORDER = { "danger", "respite", "ticker", "milestone", "place", "rare", "triumph", "victory", "death" }
local TYPE_LINES = {
	danger = "The top bar's middle, in red: a fight or a threat.",
	respite = "The top bar's middle, calm: a fight is over.",
	ticker = "The top bar's left end, small: news as you play.",
	milestone = "The middle of the screen, in gold: a big moment.",
	place = "The lower third, pale gold: where you are.",
	rare = "The middle of the screen, in blue: a rare.",
	triumph = "The top bar's middle, in gold: a win on the way.",
	victory = "Across the screen, in gold: a big win.",
	death = "Across the screen, in red: you died.",
}
local function TypeSections()
	local users, sections, listed = {}, {}, {}
	for _, event in ipairs(ns.CardEventsGrouped()) do
		local base = ns.CardBase(event.id)
		users[base] = users[base] or {}
		table.insert(users[base], event.id)
	end
	local function Add(id, always)
		local style = ns.CARD_STYLE_BY_ID[id]
		if listed[id] or not style or not (always or users[id]) then return end
		listed[id] = true
		sections[#sections + 1] = { key = id, title = L[style.name], ids = users[id] or {} }
	end
	for _, id in ipairs(TYPE_ORDER) do Add(id, true) end
	for _, style in ipairs(ns.CARD_STYLES) do Add(style.id) end
	return sections
end
-- The card a type's preview and Test play: the first event using it, else
-- the first that starts in it, else the zone's.
local function TypeSample(style)
	local users = ns.CardStyleUsers(style)
	if users[1] then return users[1].id end
	for _, event in ipairs(ns.CARD_EVENTS) do
		if ns.DEFAULTS["cardBase_" .. event.id] == style then return event.id end
	end
	return "zone"
end

-- Events: a section for each card type (TypeSections), its preview zoomed in
-- on the card, then a row for each event using it, as the Scenes page's: its
-- tick, name and chips (its own settings over the type, and where it shows
-- when not everywhere), an arrow to move it to another type, and its settings
-- in a drawer under it (When: its Show in row; Style: the one it starts from,
-- Style, Sounds and Test).
local LIST_W_RIGHT = 500 -- (a type's line's width, in its section)
function ns.CreateCardsPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	CardTabs(content, title, 1)
	local intro = kit.PageIntro(content, title,
		L["Cards that put words on your screen for moments like fights, zones and duels."])
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["Turns all cards on or off."], intro)
	-- (Everything below is made the first time the page is needed: Options.lua's lazyPages.)
	local function MakeBody()
		local stack = kit.Stack(switch, "check")
		kit.RecordKey(content, "cardThirdX") -- (the lower third's spot, moved in Edit Mode: Reset puts it back)
		kit.RecordKey(content, "cardThirdY")
		stack:Header(content, L["Events"])
		local grid = ns.GRID_KIT
		local columns = ns.FRAME_COLUMNS
		local items = {}
		local rowList
		-- (An event given another type: its row moves to that section, scrolled
		-- to and flashed.)
		local function Moved(id)
			kit.Refresh()
			if rowList then rowList:Flash(id) end
		end
		local function SetBase(id, value)
			ns.GetDB()["cardBase_" .. id] = value
			Moved(id)
		end
		for i, event in ipairs(ns.CardEventsGrouped()) do
			local id, key, alwaysKey = event.id, "card:" .. event.id, "cardAlways_" .. event.id
			local opts = event.fight and FIGHT_OPTS or STORY_OPTS
			local function Key() return key end
			local function SetAlways(value) ns.GetDB()[alwaysKey] = value end
			local parts = ns.ListRowParts(Key, columns, nil, SetAlways, opts)
			-- (What the page's Reset puts back.)
			kit.RecordKey(content, alwaysKey)
			kit.RecordKey(content, "cardBase_" .. id)
			for _, list in ipairs(ROW_LISTS) do
				kit.RecordKey(content, list)
				grid.RecordRow(content, list, key)
			end
			items[i] = {
				id = id, label = L[event.name], tip = L[TIPS[id]], on = event.on, group = L[event.group],
				onTip = L["Shows this card."],
				dim = function()
					return not (ns.GetDB()[event.on] and (not event.needs or ns.GetDB()[ns.CARD_BY_ID[event.needs].on]))
				end,
				menuTip = L["Moves this card to another card type."],
				menu = MenuUtil and MenuUtil.CreateContextMenu and function(button)
					ns.ContextMenu(button, function(_, root)
						for _, choice in ipairs(StyleChoices(id)) do
							root:CreateRadio(choice.text, function() return ns.GetDB()["cardBase_" .. id] == choice.value end,
								function() SetBase(id, choice.value) end)
						end
					end)
				end or nil,
				chips = function()
					local db = ns.GetDB()
					local own = #OwnNames(id)
					-- (Its type is its section's title; a chip only for a follower, and
					-- for its own settings over the type.)
					local list = {}
					if event.parent and (db["cardBase_" .. id] or "follow") == "follow" then
						list[#list + 1] = { BaseName(id), ns.ROW_CHIP.plain }
					end
					if own > 0 then list[#list + 1] = { L["+%d own"]:format(own), ns.ROW_CHIP.gold } end
					local rule = db.frameRules and db.frameRules[key]
					if type(rule) == "string" and rule:find("%S") then
						list[#list + 1] = { rule, ns.ROW_CHIP.when }
					elseif not db[alwaysKey] then
						local names = {}
						for c = 2, #columns do
							if not opts.omit[columns[c][3]] and columns[c][2](key) then names[#names + 1] = columns[c][1] end
						end
						if opts.quiet and ns.IsQuietShowOn(key) then names[#names + 1] = L["Out of combat"] end
						list[#list + 1] = #names == 0 and { L["Never"], ns.ROW_CHIP.never }
							or { table.concat(names, ", "), ns.ROW_CHIP.when }
					end
					return list
				end,
				lines = {
					{ name = L["When"], build = function(drawer, At)
						local layout = { groups = event.fight and { ns.GRID_LOCATION } or { ns.GRID_COMBAT, ns.GRID_LOCATION },
							edit = true }
						At(ns.GridRow(grid, drawer, 0, layout, {
							band = 1,
							always = { isOn = function() return ns.GetDB()[alwaysKey] and true or false end, set = SetAlways,
								tip = L["Shows wherever you are. (The other columns then have nothing to add.)"] },
							menus = parts.menus,
							rule = { key = Key, label = function() return L[event.name] end, grid = parts.grid,
								words = parts.words, apply = parts.apply },
						}))
					end },
					{ name = L["Style"], build = function(drawer, At)
						local base = kit.Dropdown(drawer, BaseField(id), function() return StyleChoices(id) end, 170,
							function() Moved(id) end)
						if base then
							At(base)
							kit.Tooltip(base, L["The card type this card starts from."])
						end
						-- (Buttons to it on the Settings, Style and Sounds tabs.)
						for n, link in ipairs({ { L["Settings"], "Card Settings",
							L["Opens the Settings tab with this event picked."] },
							{ L["Style"], "Card Style", L["Opens the Style tab with this event picked."] },
							{ L["Sounds"], "Card Sounds", L["Opens the Sounds tab with this event picked."] } }) do
							local button = ns.PanelButton(drawer)
							button:SetSize(70, 22)
							button:SetText(link[1])
							At(button, ns.ROW_LIST_LABEL_W + 180 + (n - 1) * 76)
							kit.Tooltip(button, link[3])
							button:SetScript("OnClick", function()
								CARD.now = id
								ns.ShowHubPage(link[2])
							end)
						end
						local test = ns.PanelButton(drawer)
						test:SetSize(60, 22)
						test:SetText(L["Test"])
						At(test, ns.ROW_LIST_LABEL_W + 408)
						kit.Tooltip(test, ns.CardSequences[id]
							and L["Shows each of its cards in turn; close the settings to see them."]
							or L["Shows its card now, to see how it looks (close the settings to see it)."])
						test:SetScript("OnClick", function() ns.CardTest(id) end)
						TestStops(test, function() return id end)
					end },
				},
			}
		end
		-- The jumbotron at the top (2026-11-18, in place of a small preview in
		-- each type's section): one big screen playing each card type's card in
		-- turn, as the Style hub's General page's (GeneralStyle.lua's
		-- ns.MakeStyleJumbotron), its arrows and lock with it; opening a type's
		-- section, or changing its Size, turns it to that type. Zoomed in on the
		-- card as it comes (up to 6 times, till it's 70% of the screen), so a
		-- Size changed shows bigger or smaller.
		local jumbo
		local function SizeShare(style)
			local shipped = tonumber(ns.CardStyleRaw(style, "Size", true)) or 36
			return (tonumber(ns.CardStyleRaw(style, "Size")) or shipped) / math.max(shipped, 1)
		end
		local cells, screens = {}, {}
		for _, section in ipairs(TypeSections()) do
			local style = section.key
			cells[#cells + 1] = { section.title, key = style, sized = true, make = function(parent, width, height)
				screens[#screens + 1] = ns.MakeCardPreview(parent, width, height, function() return TypeSample(style) end,
					function() return ns.CardStyleLook(style, TypeSample(style)) end,
					{ zoom = 6, share = 0.7, loop = true, zoomBy = function() return SizeShare(style) end, noCaption = true })
				return screens[#screens]
			end }
		end
		jumbo = ns.MakeStyleJumbotron(kit, content, stack, 480, cells)
		jumbo.pageSwitch = false
		local function Show(style)
			if not jumbo then return end
			jumbo:Jump(style)
			jumbo:Refresh()
		end
		-- Each type's header: its line, saying where it shows; Test, Edit and
		-- its Size (the Card Types tab's Size, 2026-11-18: in place of the one
		-- Card size for all).
		local HEADER_H = 100
		local function TypeHeader(style, header)
			local sizeKey = ns.CardStyleKey("Size", style)
			kit.RecordKey(content, sizeKey)
			local line = kit.Label(header, "GameFontHighlightSmall", L[TYPE_LINES[style] or "A ready-made card type."])
			line:SetPoint("TOPLEFT", header, "TOPLEFT", 16, -4)
			line:SetWidth(LIST_W_RIGHT)
			line:SetJustifyH("LEFT")
			line.searchSkip = true
			local test = ns.PanelButton(header)
			test:SetSize(70, 22)
			test:SetText(L["Test"])
			test:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -10)
			kit.Tooltip(test, L["Plays a card of this type on your screen."])
			test:SetScript("OnClick", function()
				Show(style)
				local id = TypeSample(style)
				local card = ns.CardSample(id)
				if id == "zone" and not card.name then card.name = GetRealZoneText and GetRealZoneText() or "Darkshore" end
				card.look = ns.CardStyleLook(style, id)
				ns.Cards.Fire(id, card, true)
			end)
			local edit = ns.PanelButton(header)
			edit:SetSize(130, 22)
			edit:SetText(L["Edit card type"])
			edit:SetPoint("LEFT", test, "RIGHT", 6, 0)
			kit.Tooltip(edit, L["Opens the Card Types tab with this type picked."])
			edit:SetScript("OnClick", function()
				CARD.style = style
				-- (In the Style hub since 2026-11-17: ShowHubPage stays in this one.)
				ns.OpenOptions("Card Styles")
			end)
			local size = kit.Slider(header, {
				key = sizeKey, -- (its id for /cine find: the type's Size)
				get = function() return tonumber(ns.CardStyleRaw(style, "Size")) or 36 end,
				set = function(value) ns.GetDB()[sizeKey] = value end,
			}, L["Size"], 14, 140, 1, "%d", 1, function() Show(style) end)
			size:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 2, -24)
			kit.Tooltip(size, L["How big the words are on every card of this type."])
		end
		rowList = ns.RowList(kit, content, items, { sections = TypeSections, header = TypeHeader, headerH = HEADER_H,
			empty = L["No events use this card type."], collapsible = true, onOpen = Show,
			count = function(n) return n == 1 and L["1 card"] or L["%d cards"]:format(n) end })
		stack:Add(rowList, "label")
		stack:Note(content, L["+2 own: the card has two settings of its own over its card type (the Style tab marks " ..
			"them with gold dots). The arrow on a row moves it to another card type."], NOTE_W)

		canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))

		-- (/cine debug cardpage: its height, the scroll, and the lowest shown
		-- widgets, to find what stretches its scroll: 600 past its last row in
		-- the game, the sticky jumbotron let go as it fitted again, 2026-11-18.
		-- Printed and logged.)
		function ns.CardPageDepth()
			local top = content:GetTop()
			if not top then ns.Print("Card Vision: not laid out yet (open its Events tab first)") return end
			local function Say(text)
				ns.Print(text)
				ns.Log("cardpage", text)
			end
			local found = {}
			local function Consider(object, path)
				if object.IsShown and object:IsShown() and object.GetBottom and object:GetBottom() then
					found[#found + 1] = { top - object:GetBottom(), path, object }
				end
			end
			local function Named(object)
				local text = object.GetText and object:GetText()
				return (object:GetName() or object:GetObjectType()) .. (text and (" '" .. tostring(text):sub(1, 30) .. "'") or "")
			end
			for c, child in ipairs({ content:GetChildren() }) do
				local name = c .. " " .. Named(child)
				Consider(child, name)
				if child:IsShown() then
					for g, grand in ipairs({ child:GetChildren() }) do Consider(grand, name .. " > " .. g .. " " .. Named(grand)) end
					for _, region in ipairs({ child:GetRegions() }) do Consider(region, name .. " > " .. Named(region)) end
				end
			end
			for _, region in ipairs({ content:GetRegions() }) do Consider(region, Named(region)) end
			table.sort(found, function(a, b) return a[1] > b[1] end)
			local scroll = content:GetParent()
			local pin = jumbo and jumbo.pin
			Say(("Card Vision: content %.0f tall, list %.0f, scroll %s of %s, view %s; jumbotron on %s %.0fx%.0f, held %s; %d shown")
				:format(content:GetHeight(), rowList:GetHeight(),
				scroll.GetVerticalScroll and ("%.0f"):format(scroll:GetVerticalScroll()) or "-",
				scroll.GetVerticalScrollRange and ("%.0f"):format(scroll:GetVerticalScrollRange()) or "-",
				scroll.GetHeight and ("%.0f"):format(scroll:GetHeight()) or "-",
				jumbo and jumbo:GetParent() == content and "page" or "hub", jumbo and jumbo:GetWidth() or 0,
				jumbo and jumbo:GetHeight() or 0, tostring(pin and pin.on), #found))
			for _, screen in ipairs(screens) do
				if screen:IsShown() then Say("  screen: " .. screen.LensState()) end
			end
			for i = 1, math.min(10, #found) do
				local f = found[i]
				local w, h = f[3]:GetSize()
				Say(("  %.0f down: %s (%.0f x %.0f)"):format(f[1], f[2], w or 0, h or 0))
			end
		end
	end
	ns.LazyPageBody(canvas, "Card Vision", MakeBody)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card Vision")
end

-- What a page builds for each event, shown only while it's the one picked
-- (Now()): Part(id, build) then Finish() once the page is built. Each part
-- starts where the first began. A control that shows and hides itself
-- (ownVisibility) is left to do so on its event.
local function Parts(kit, content, stack, Now)
	local owner, hidden, start = {}, {}, nil
	local function Each(fn)
		for _, object in ipairs({ content:GetChildren() }) do fn(object) end
		for _, object in ipairs({ content:GetRegions() }) do fn(object) end
	end
	local parts = {}
	function parts.Part(id, build)
		if start then stack:Continue(start[1], start[2]) else start = { stack.last, stack.kind } end
		local before = {}
		Each(function(object) before[object] = true end)
		build()
		Each(function(object) if not before[object] then owner[object] = id end end)
	end
	function parts.Finish()
		local apply = CreateFrame("Frame", nil, content)
		apply:SetSize(1, 1)
		apply:Hide()
		apply.pageSwitch = false
		apply.Refresh = function()
			local now = Now()
			Each(function(object)
				local id = owner[object]
				if id == now then
					if hidden[object] then
						hidden[object] = nil
						if not object.ownVisibility then object:Show() end
					end
				elseif id and object:IsShown() then
					hidden[object] = true
					object:Hide()
				end
			end)
		end
		kit.AddControl(apply)
	end
	return parts
end

-- A row with an edit box for words (key: "" for none; the defaults shown
-- and kept as such in any language).
local function WordsRow(kit, content, stack, key, label, tip)
	local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
	name:SetSize(150, 22)
	local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	if ns.SkinEditBox then ns.SkinEditBox(box) end
	box:SetSize(180, 22)
	box:SetAutoFocus(false)
	box:SetMaxLetters(40)
	box:SetPoint("LEFT", name, "LEFT", 160, 0)
	kit.Tooltip(box, tip)
	kit.RecordKey(content, key)
	local default = ns.DEFAULTS[key]
	local function Save(self)
		local words = (self:GetText() or ""):match("^%s*(.-)%s*$")
		ns.GetDB()[key] = (default ~= "" and words == L[default]) and default or words
		self:ClearFocus()
	end
	box:SetScript("OnEnterPressed", Save)
	box:SetScript("OnEditFocusLost", Save)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.CardWords(key))
		self:ClearFocus()
	end)
	box.Refresh = function(self)
		if not self:HasFocus() then self:SetText(default == "" and (ns.GetDB()[key] or "") or ns.CardWords(key)) end
	end
	kit.AddControl(box)
	return box
end

-- Style: an event's look (opened from its row).
function ns.CreateCardStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	local under = CardTop(kit, content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["How this card looks."], under)
	local preview
	local function Changed()
		if preview then preview:Refresh() end
	end
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["Turns all cards on or off."], intro, Changed)
	local stack = kit.Stack(switch, "check")

	-- The look's rows edit the picked event's own settings (showing what
	-- shows: its own, else what it follows; a change makes it its own).
	local isField = {}
	for _, field in ipairs(ns.CARD_FIELDS) do isField[field[1]] = true end
	local fields = {}
	local function FieldOf(key)
		local name = type(key) == "string" and key:match("^card(%u%w*)$")
		if not (name and isField[name]) then return key end
		fields[name] = fields[name] or {
			get = function() return ns.CardRaw(CARD.now, name) end,
			set = function(value) ns.GetDB()[ns.CardKey(name, CARD.now)] = value end,
		}
		return fields[name]
	end
	for _, field in ipairs(ns.CARD_FIELDS) do
		kit.RecordKey(content, ns.CardKey(field[1]))
		for _, event in ipairs(ns.CARD_EVENTS) do kit.RecordKey(content, ns.CardKey(field[1], event.id)) end
	end
	for _, event in ipairs(ns.CARD_EVENTS) do kit.RecordKey(content, "cardBase_" .. event.id) end
	local rows = ns.StyleRows(kit, content, stack, Changed, "cards", FieldOf)

	preview = ns.MakeCardPreview(content, 480, CARD_PREVIEW_H, function() return CARD.now end)
	preview.pageSwitch = false
	LowPreview(preview)
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)
	local styleTest = ns.StylePreviewTest(preview, kit, L["Plays the card in the preview and on your screen."], function()
			preview:Refresh()
			ns.CardTest(CARD.now)
		end)
	TestStops(styleTest, function() return CARD.now end)

	-- The style the event starts from, and a button to change that style
	-- itself (the Card Types tab, it picked).
	local base = rows.Dropdown(L["Starts from"], { get = function() return ns.GetDB()["cardBase_" .. CARD.now] end,
		set = function(value) ns.GetDB()["cardBase_" .. CARD.now] = value end },
		function() return StyleChoices(CARD.now) end,
		L["The card type this card starts from."])
	if base then
		stack.last:SetSize(84, 30)
		base:SetWidth(170)
		local edit = ns.PanelButton(content)
		edit:SetSize(110, 22)
		edit:SetText(L["Edit card type"])
		edit:SetPoint("LEFT", base, "RIGHT", 10, 0)
		edit.pageSwitch = false
		kit.Tooltip(edit, L["Opens this card type on the Card Types tab: a change there is for every card using it."])
		edit:SetScript("OnClick", function()
			CARD.style = ns.CardBase(CARD.now)
			ns.OpenOptions("Card Styles") -- (another hub's: ShowHubPage stays in this one)
		end)
		-- How many it has of its own (each with a gold dot beside it), and all back.
		OwnLine(kit, content, edit, 12, 110, function() return #OwnNames(CARD.now) end, function(count)
			return count == 0 and L["None of its own"] or L["%d of its own"]:format(count)
		end, function()
			for _, group in ipairs(GROUPS) do Follow(CARD.now, group) end
		end, L["Puts all of this card's own settings back, to come from its card type again."], Changed, rows.On)
	end

	-- The icon's own picture: a button after the Icon tick opening every icon
	-- the game has (IconBrowser.lua). Right-click: back to the event's own.
	local browser = ns.IconBrowser(canvas, function(key, icon)
		ns.GetDB()[key] = icon
		Changed()
		kit.Refresh()
	end)
	local function IconButton(after)
		local button = CreateFrame("Button", nil, content)
		button:SetSize(22, 22)
		button:SetPoint("LEFT", after.Text or after.text or after, "RIGHT", 10, 0)
		local border = button:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.45, 0.38, 0.2, 1)
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", -2, 2)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local hl = button:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(icon)
		hl:SetColorTexture(1, 1, 1, 0.2)
		kit.Tooltip(button, L["Click to pick an icon; right-click to reset it."])
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", function(self, mouse)
			local key = ns.CardKey("Icon", CARD.now)
			if mouse == "RightButton" then
				ns.GetDB()[key] = "default"
				Changed()
				kit.Refresh()
				return
			end
			browser:Open(self, key, ns.CardLook(CARD.now).combatIconIn)
		end)
		button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
		button:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
		button.Refresh = function()
			icon:SetTexture(ns.CardLook(CARD.now).combatIconIn)
		end
		kit.GreyUnless(button, function(db) return rows.On(db) and ns.CardRaw(CARD.now, "IconShow") end)
		kit.AddControl(button)
	end
	LookGrid(kit, content, stack, FieldOf, Changed, {
		Is = function(group) return OwnGroup(CARD.now, group) end,
		Put = function(group) Follow(CARD.now, group) end,
		tip = L["This card's own setting; click to reset it."],
	}, IconButton)


	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content)) -- (its refresh plays the preview)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card Style", L["Card Vision"])
end

-- Card Types: a style picked from a dropdown and its look, for every card that
-- starts from it (each card's own settings over it).
function ns.CreateCardStylesPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	CardTabs(content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["The card types that cards start from."])
	local preview
	local function Changed()
		if preview then preview:Refresh() end
	end
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["Turns all cards on or off."], intro, Changed)
	local stack = kit.Stack(switch, "check")

	-- The look's rows edit the picked style (showing what shows: your change,
	-- else how it comes; a change is yours).
	local isField = {}
	for _, field in ipairs(ns.CARD_FIELDS) do isField[field[1]] = true end
	local fields = {}
	local function FieldOf(key)
		local name = type(key) == "string" and key:match("^card(%u%w*)$")
		if not (name and isField[name]) then return key end
		fields[name] = fields[name] or {
			get = function() return ns.CardStyleRaw(CARD.style, name) end,
			set = function(value) ns.GetDB()[ns.CardStyleKey(name, CARD.style)] = value end,
		}
		return fields[name]
	end
	for _, field in ipairs(ns.CARD_FIELDS) do
		for _, style in ipairs(ns.CARD_STYLES) do kit.RecordKey(content, ns.CardStyleKey(field[1], style.id)) end
	end
	local rows = ns.StyleRows(kit, content, stack, Changed, "cards", FieldOf)

	-- The settings changed from how the style comes, by the list's names.
	local function Changes(style)
		local names = {}
		for _, group in ipairs(GROUPS) do
			for _, field in ipairs(group[2]) do
				if ns.CardStyleIsOwn(style, field) then
					names[#names + 1] = L[group[1]]
					break
				end
			end
		end
		return names
	end
	-- The card it plays: the first one using it, else the zone's.
	local function Sample()
		local users = ns.CardStyleUsers(CARD.style)
		return users[1] and users[1].id or "zone"
	end

	-- What it shows: "Editing", the dropdown and a line saying which cards
	-- use it.
	local bar = CreateFrame("Frame", nil, content)
	bar:SetSize(480, 30)
	stack:Add(bar, "label")
	local editing = kit.Label(bar, "GameFontNormalLarge", L["Editing"])
	editing:SetPoint("LEFT", 2, 0)
	local barLine = kit.Label(bar, "GameFontHighlightSmall", "")
	barLine:SetWidth(320)
	barLine:SetJustifyH("LEFT")
	barLine:SetWordWrap(false)
	local picker = kit.Dropdown(content, { get = function() return CARD.style end,
		set = function(id) CARD.style = id end }, function()
			local list = {}
			for _, style in ipairs(ns.CARD_STYLES) do list[#list + 1] = { value = style.id, text = L[style.name] } end
			return list
		end, 200, function() kit.Refresh() end)
	if picker then
		picker:SetPoint("LEFT", editing, "RIGHT", 12, 0)
		picker:SetFrameLevel(bar:GetFrameLevel() + 3)
		picker.pageSwitch = false
		kit.Tooltip(picker, L["The card type this tab shows and sets."])
		barLine:SetPoint("LEFT", picker, "RIGHT", 12, 0)
	else
		barLine:SetPoint("LEFT", editing, "RIGHT", 12, 0)
	end
	bar.pageSwitch = false
	bar.Refresh = function()
		local names = {}
		for _, event in ipairs(ns.CardStyleUsers(CARD.style)) do names[#names + 1] = L[event.name] end
		barLine:SetText(#names > 0 and L["Used by: %s"]:format("|cffffd100" .. table.concat(names, ", ") .. "|r")
			or L["No card uses it yet."])
	end
	kit.AddControl(bar)

	preview = ns.MakeCardPreview(content, 480, CARD_PREVIEW_H, Sample,
		function() return ns.CardStyleLook(CARD.style, Sample()) end)
	preview.pageSwitch = false
	LowPreview(preview)
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)
	ns.StylePreviewTest(preview, kit, L["Plays a card in this style in the preview and on your screen."], function()
			preview:Refresh()
			local id = Sample()
			local card = ns.CardSample(id)
			if id == "zone" and not card.name then card.name = GetRealZoneText and GetRealZoneText() or "Darkshore" end
			card.look = ns.CardStyleLook(CARD.style, id)
			ns.Cards.Fire(id, card, true)
		end)

	-- How many are changed from how it comes (each with a gold dot beside it),
	-- and all back.
	local function PutBack(group)
		local db = ns.GetDB()
		for _, field in ipairs(group[2]) do db[ns.CardStyleKey(field, CARD.style)] = "default" end
	end
	local ownRow = CreateFrame("Frame", nil, content)
	ownRow:SetSize(1, 22)
	stack:Add(ownRow, "label")
	OwnLine(kit, content, ownRow, 0, 200, function() return #Changes(CARD.style) end, function(count)
		return count == 0 and L["As it comes: nothing changed."] or L["%d changed"]:format(count)
	end, function()
		for _, group in ipairs(GROUPS) do PutBack(group) end
	end, L["Puts all your changes to this card type back, as it comes."], Changed, rows.On)

	LookGrid(kit, content, stack, FieldOf, Changed, {
		Is = function(group)
			for _, field in ipairs(group[2]) do
				if ns.CardStyleIsOwn(CARD.style, field) then return true end
			end
			return false
		end,
		Put = PutBack,
		tip = L["Changed from the card type; click to reset it."],
	})

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content)) -- (its refresh plays the preview)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card Styles", L["Card Vision"])
end

-- Settings: what's an event's alone (opened from its row): when it fires,
-- its lines, its words.
function ns.CreateCardSettingsPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	local under = CardTop(kit, content, title, 1)
	local intro = kit.PageIntro(content, title,
		L["This card's own settings and words."], under)
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["Turns all cards on or off."], intro)
	local stack = kit.Stack(switch, "check")
	local function Now() return CARD.now end

	-- What's each event's alone.
	local parts = Parts(kit, content, stack, Now)
	local function Check(key, label, tip, test)
		local check = stack:Add(kit.Check(content, key, label, tip), "check")
		if test then kit.GreyUnless(check, test) end
		return check
	end
	local function Header(text) stack:Header(content, text) end
	-- Zone's and Subzone's gap: one setting, on both their tabs.
	local function GapRow()
		local gap = stack:Add(kit.Slider(content, "storyZoneGap", L["Not again within"], 0, 30, 1, "%d s"), "slider")
		kit.Tooltip(gap, L["No new Zone or Subzone card for this long after one; 0 for every time."])
	end
	-- In a fight (or just out of one): shown now, held till after, or not at
	-- all. (Not for the fight's own cards.)
	local function FightRow(id)
		if not (ns.CARD_BY_ID[id] and ns.CARD_BY_ID[id].inFight) then return end
		Header(L["In a fight"])
		local choice = kit.Dropdown(content, "cardFight_" .. id, List({
			{ "show", L["Show it now"] },
			{ "wait", L["Wait till after"], L["Waits until you've been out of the fight for 5 seconds."] },
			{ "skip", L["Skip it"], L["Not shown at all in a fight, or in the 5 seconds after one."] },
		}), 200)
		if choice then
			local name = stack:Add(kit.Label(content, "GameFontHighlight", L["In a fight:"]), "label")
			name:SetSize(150, 30)
			name:SetJustifyV("MIDDLE")
			choice:SetPoint("LEFT", name, "RIGHT", 4, 0)
			kit.Tooltip(choice, L["What this card does if it comes while you're in a fight, or in the 5 seconds " ..
				"after one."])
		end
	end
	parts.Part("combatIn", function()
		Header(L["Words"])
		WordsRow(kit, content, stack, "combatTextIn", L["Words:"],
			L["The words as you go into a fight; leave empty for none."])
	end)
	parts.Part("combatOut", function()
		Header(L["Words"])
		WordsRow(kit, content, stack, "combatTextOut", L["Words:"],
			L["The words as you leave a fight; leave empty for none."])
		Header(L["When"])
		local minFight = stack:Add(kit.Slider(content, "combatMinFight", L["Not after fights under"], 0, 10, 1,
			"%d s"), "slider")
		kit.Tooltip(minFight, L["No card after fights shorter than this; 0 for every fight."])
	end)
	parts.Part("boss", function()
		Header(L["When"])
		Check("combatBossPull", L["Boss pulled"], L["Shows the boss's name as its fight starts."])
		Check("combatBossTarget", L["Boss targeted"], L["Shows the boss's name when you first target it."])
		Check("combatBossNear", L["Boss nearby"], L["Shows the boss's name when you first get near it."])
		Header(L["Lines"])
		Check("combatBossSub", L["Dungeon line"],
			L["Shows the dungeon or raid and its difficulty under the boss's name."])
		if EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex then
			Check("combatBossCount", L["Boss number"],
				L["Shows \"Boss 2 of 3\" over the name."])
		end
	end)
	parts.Part("zone", function()
		Header(L["Lines"])
		Check("storyZoneTerritory", L["Territory"], L["Shows the zone's type under its name, such as Sanctuary."])
		Check("timeOfDayMessage", L["Time of day at login"], L["Shows the time of day when you log in."])
		Header(L["When"])
		GapRow()
		Check("storyZoneNotFlying", L["Not on flights"], L["No Zone or Subzone cards while on a flight path."])
		FightRow("zone")
	end)
	parts.Part("subzone", function()
		stack:Note(content, L["Only with Zone ticked: it takes the game's zone text away. Its look follows Zone's " ..
			"until it's given its own here; its lines are Zone's."], NOTE_W)
		Header(L["When"])
		GapRow()
		FightRow("subzone")
	end)
	parts.Part("login", function()
		Header(L["Where"])
		Check("storyRecapUnder", L["Under the zone name"], L["Shows one line under the game's zone name instead of a card."])
		stack:Add(kit.Slider(content, "storyRecapDelay", L["After"], 0, 8, 0.5, "%.1f s"), "slider")
		Header(L["Details"])
		local heading = kit.Dropdown(content, "storyRecapHeading", List({
			{ "lasttime", L["Last time"] },
			{ "previously", L["Previously"] },
			{ "previouslyon", L["Previously, on %s"]:format(UnitName("player") or "...") },
			{ "sofar", L["Your story so far"] },
			{ "none", L["None"] },
		}), 200)
		if heading then
			local name = stack:Add(kit.Label(content, "GameFontHighlight", L["Heading:"]), "label")
			name:SetSize(150, 30)
			name:SetJustifyV("MIDDLE")
			heading:SetPoint("LEFT", name, "RIGHT", 4, 0)
			kit.Tooltip(heading, L["The words before it all (on a card, over the zone name)."])
		end
		for _, pair in ipairs({
			{ "storyRecapZone", L["Zone"], L["The zone you spent the most time in (on a card, its big name)."] },
			{ "storyRecapPlayed", L["Time played"], L["How long the session was."] },
			{ "storyRecapQuests", L["Quests done"], L["How many quests you turned in."] },
			{ "storyRecapLevel", L["Level reached"], L["The level you reached, if you went up."] },
			{ "storyRecapBosses", L["Bosses down"], L["How many dungeon or raid bosses you killed."] },
			{ "storyRecapDeaths", L["Deaths"], L["How many times you died."] },
			{ "storyRecapGold", L["Gold earned"], L["How much richer you came out, if you did."] },
			{ "storyRecapIcons", L["Icons"], L["A little icon before each detail: a map, a watch, a quest mark, a " ..
				"skull, coins..."] },
		}) do
			Check(pair[1], pair[2], pair[3])
		end
		stack:Note(content, L["It shows only if something happened that's ticked here: quests, a level, bosses, " ..
			"deaths or gold. The zone and time played come with it."], NOTE_W)
		FightRow("login")
	end)
	parts.Part("attack", function()
		stack:Note(content, L["The same place shows at most once every 90 seconds."], NOTE_W)
	end)
	-- A dropdown on a row of its own, its label before it.
	local function PickRow(key, label, items, tip)
		local box = kit.Dropdown(content, key, List(items), 200)
		if not box then return end
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(150, 30)
		name:SetJustifyV("MIDDLE")
		box:SetPoint("LEFT", name, "RIGHT", 4, 0)
		kit.Tooltip(box, tip)
	end
	-- A win's (and loss's) card as it was or as a souls banner (Cards.lua's
	-- ns.SoulsCard).
	local function SoulsRow(id, tip)
		Header(L["Banner"])
		PickRow("cardSouls_" .. id, L["Shows as:"], {
			{ "usual", L["Its card"], L["As it always has, in its own look (the Style tab)."] },
			{ "souls", L["Souls banner"], L["Big words across the middle of the screen, like YOU DIED."] },
		}, tip)
	end
	-- Boss defeated's, Rare felled's and Revived's words (SOULS_WORDS, or your
	-- own).
	local function SoulsWordsRows(id)
		Header(L["Words"])
		local items = {}
		for _, entry in ipairs(ns.SOULS_WORDS[id]) do
			items[#items + 1] = { entry[1], L[entry[2]]:format(L["<NAME>"]) }
		end
		items[#items + 1] = { "custom", L["Custom"], L["Your own words."] }
		PickRow(id .. "Words", L["Banner words:"], items,
			L["The big words across the screen."])
		local box = WordsRow(kit, content, stack, id .. "Text", L["Your words:"],
			L["Your own words for the banner."])
		kit.GreyUnless(box, function(db) return db[id .. "Words"] == "custom" end)
	end
	-- (The wins that can show as a souls banner, and their Banner's tooltip.)
	local SOULS_TIPS = {
		cleared = "How the dungeon's end shows: its card, or a souls banner: VICTORY ACHIEVED across the " ..
			"middle of the screen, its name, the time and deaths under it (in place of the last boss's own card).",
		battleground = "How the result shows: its card in the top bar, or a souls banner: VICTORY ACHIEVED or " ..
			"DEFEATED across the middle of the screen (where the game's scoreboard may cover it).",
		streak = "How it shows: its card, or a souls banner: PREY SLAUGHTERED across the middle of the screen, " ..
			"the count and who under it.",
	}
	parts.Part("duel", function()
		Header(L["When"])
		Check("cardDuelAsk", L["You challenge"], L["The other player's name as you challenge them to a duel."])
		Check("cardDuelAsked", L["You're challenged"], L["The other player's name as they challenge you to a duel."])
		Check("cardDuelStart", L["Duel starts"], L["Both names as the duel is accepted and its countdown starts."])
		Check("cardDuelResult", L["Result"], L["Whether you won or lost (or someone fled) as the duel ends."])
		Header(L["Words"])
		local start = WordsRow(kit, content, stack, "duelTextStart", L["Starts:"],
			L["The words under both names as the duel starts."])
		kit.GreyUnless(start, function(db) return db.cardDuelStart end)
		for _, row in ipairs({ { "duelTextWon", L["Won:"], L["The big words as you win a duel."] },
			{ "duelTextLost", L["Lost:"], L["The big words as you lose a duel."] } }) do
			local box = WordsRow(kit, content, stack, row[1], row[2], row[3])
			kit.GreyUnless(box, function(db) return db.cardDuelResult end)
		end
		SoulsRow("duel", L["Shows the result as its card or as a big banner."])
	end)
	for _, id in ipairs({ "bossDown", "felled", "revived" }) do
		parts.Part(id, function()
			SoulsWordsRows(id)
			if ns.CARD_BY_ID[id].inFight then FightRow(id) end
			stack:Note(content, id == "bossDown"
				and L["Its look is the Triumph card type's (the Style tab), its sound on the Sounds tab."]
				or L["Its look is the Victory card type's (the Style tab), its sound on the Sounds tab."], NOTE_W)
		end)
	end
	parts.Part("death", function()
		Header(L["Words"])
		local banner = kit.Dropdown(content, "deathBannerStyle", List({
			{ "youdied", L["YOU DIED"] },
			{ "wasted", L["wasted"], L["A picture: red with a dark outline, on a flat black band, its own colors."] },
			{ "custom", L["Custom"], L["Your own words."] },
		}), 200)
		if banner then
			local name = stack:Add(kit.Label(content, "GameFontHighlight", L["Death banner:"]), "label")
			name:SetSize(150, 30)
			name:SetJustifyV("MIDDLE")
			banner:SetPoint("LEFT", name, "RIGHT", 4, 0)
			kit.Tooltip(banner, L["YOU DIED, \"wasted\" (a picture) or words of your own."])
		end
		local box = WordsRow(kit, content, stack, "deathBannerText", L["Your words:"],
			L["Your own words for the banner; blank shows YOU DIED."])
		kit.GreyUnless(box, function(db) return db.deathBannerStyle == "custom" end)
		stack:Note(content, L["Only with the death camera on (the Die row on the Scenes page)."], NOTE_W)
	end)
	parts.Part("time", function()
		FightRow("time")
		stack:Note(content, L["Its look is on the Style tab, a sound for each time of day on the Sounds tab."], NOTE_W)
	end)
	parts.Part("departure", function()
		FightRow("departure")
		Header(L["Progress line"])
		Check("cardDepartureLine", L["Show a line as you fly"],
			L["Shows a line that fills up as you fly a route you've flown before."])
		local where = kit.Dropdown(content, "cardDepartureLinePlace", List({
			{ "top", L["Top bar"] },
			{ "bottom", L["Bottom bar"] },
		}), 200)
		if where then
			local name = stack:Add(kit.Label(content, "GameFontHighlight", L["Where:"]), "label")
			name:SetSize(150, 30)
			name:SetJustifyV("MIDDLE")
			where:SetPoint("LEFT", name, "RIGHT", 4, 0)
			kit.Tooltip(where, L["The letterbox bar the line and its time go in (no letterbox up: that edge of " ..
				"the screen)."])
			kit.GreyUnless(where, function(db) return db.cardDepartureLine end)
		end
		local edges = stack:Add(kit.Slider(content, "cardDepartureLineEdges", L["Only at the start and end"], 0, 30, 1,
			"%d s"), "slider")
		kit.Tooltip(edges, L["Shows the line only this long at the start and end; 0 for the whole way."])
		kit.GreyUnless(edges, function(db) return db.cardDepartureLine end)
		local clock = kit.Dropdown(content, "cardDepartureClock", List({
			{ "minutes", L["Minutes only"], L["\"2 min\", rounded up, then \"under a minute\"."] },
			{ "clock", L["Minutes and seconds"], L["\"1:12\", counting down."] },
			{ "none", L["Don't show"], L["Just the line."] },
		}), 200)
		if clock then
			local name = stack:Add(kit.Label(content, "GameFontHighlight", L["Time left:"]), "label")
			name:SetSize(150, 30)
			name:SetJustifyV("MIDDLE")
			clock:SetPoint("LEFT", name, "RIGHT", 4, 0)
			kit.Tooltip(clock, L["The time left at the line's end."])
			kit.GreyUnless(clock, function(db) return db.cardDepartureLine end)
		end
		stack:Note(content, L["Its look is on the Style tab, its sound on the Sounds tab."], NOTE_W)
	end)
	for _, id in ipairs({ "cleared", "discover", "newZone", "arrival", "rested", "levelUp", "achievement", "explore", "almost", "step",
		"reputation", "collect",
		"profession", "quest", "rare", "battleground", "streak" }) do
		parts.Part(id, function()
			if SOULS_TIPS[id] then SoulsRow(id, L[SOULS_TIPS[id]]) end
			-- (Whose alert a rare RareScanner finds shows as: only with it
			-- loaded. Support/RareScanner.lua.)
			if id == "rare" and ns.AddOnWillLoad("RareScanner") then
				Header(L["RareScanner"])
				stack:Note(content, L["Whose alert a rare RareScanner finds shows as (this card, or its own " ..
					"button) is its row on Addons > Conflicts."], NOTE_W)
			end
			if ns.CARD_BY_ID[id] and ns.CARD_BY_ID[id].inFight then
				FightRow(id)
				stack:Note(content, L["Its look is on the Style tab, its sound on the Sounds tab."], NOTE_W)
			else
				stack:Note(content, L["Nothing of its own here: its look is on the Style tab, its sound on the Sounds " ..
					"tab."], NOTE_W)
			end
		end)
	end
	parts.Finish()

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card Settings", L["Card Vision"])
end

-- Settings (2026-11-18): what's for every card, not one event or type: Move
-- cards clear of the chat (from the Events tab's top).
function ns.CreateCardGeneralPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	CardTabs(content, title, 3)
	local intro = kit.PageIntro(content, title, L["Settings for every card."])
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["Turns all cards on or off."], intro)
	local stack = kit.Stack(switch, "check")
	stack:Add(kit.Check(content, "cardClearChat", L["Move cards clear of the chat"],
		L["Moves lower third cards up so they don't cover the chat."]), "check")
	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card General", L["Card Vision"])
end

-- Sounds: an event's sounds (opened from its row).
function ns.CreateCardSoundsPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	local under = CardTop(kit, content, title, 3)
	local intro = kit.PageIntro(content, title, L["What this card plays as it shows."], under)
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["Turns all cards on or off."], intro)
	-- (Everything below is made the first time the page is needed: Options.lua's lazyPages.)
	local function MakeBody()
		local stack = kit.Stack(switch, "check")

		-- (Each event's sound rules: CombatSoundRules.lua. Entering and Leaving
		-- combat's one list, shown on both; Boss's its own; Time of day's a rule for each time; the rest's
		-- own, read as the card shows.)
		local parts = Parts(kit, content, stack, function() return CARD.now end)
		parts.Part("combatIn", function() ns.CombatSoundRulesSection(kit, content, stack) end)
		parts.Part("combatOut", function() ns.CombatSoundRulesSection(kit, content, stack) end)
		parts.Part("boss", function() ns.CombatSoundRulesSection(kit, content, stack, true) end)
		parts.Part("time", function() ns.CombatSoundRulesSection(kit, content, stack, "time") end)
		for _, id in ipairs(ns.CARD_SOUND_LISTS) do
			parts.Part(id, function() ns.CombatSoundRulesSection(kit, content, stack, id) end)
		end
		parts.Finish()

		canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	end
	ns.LazyPageBody(canvas, "Card Sounds", MakeBody)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card Sounds", L["Card Vision"])
end
