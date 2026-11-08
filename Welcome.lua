-- The welcome window: the first time Cinematic runs, it asks the player to
-- pick a level (Subtle, Balanced, Cinema: each a built-in profile), so they
-- start from a setup they chose. Until they pick one, Cinematic does nothing
-- and this comes back at each login (Decide later), unless they turn
-- Cinematic off from it. Picking one switches to its profile at once, behind
-- the window, so they can try each in turn; the X, Escape or Done keep it.
-- Customize has pages that change one part of it. /cine welcome and the
-- minimap button (with no profile picked) bring it back. Everything's drawn
-- flat (its own buttons, X and descriptions, no Blizzard templates or
-- tooltip), so the old and new styles don't mix.

local ADDON_NAME, ns = ...
local L = ns.L

-- (A card per level, 3 to a 560 wide window; each one more, 120 wider.)
local COLS = math.max(3, #ns.WELCOME_LEVELS)
local WIDTH, PAD, GAP = 560 + (COLS - 3) * 120, 22, 14
local CARD_W = (WIDTH - 2 * PAD - (COLS - 1) * GAP) / COLS
local MASK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\RoundIcon" -- soft rounded corners

-- Colours: the window, an edge, a lit edge (hovered), gold (picked, the main
-- button) and text greys.
local BG = { 0.07, 0.07, 0.08 }
local RAISED = { 0.11, 0.11, 0.12 }
local EDGE = { 0.24, 0.24, 0.26 }
local LIT = { 0.55, 0.55, 0.58 }
local GOLD = { 1, 0.82, 0 }
local BUTTON, BUTTON_LIT = { 0.5, 0.38, 0.05 }, { 0.62, 0.48, 0.08 }
local WHITE, SOFT, DIM = { 1, 1, 1 }, { 0.78, 0.78, 0.78 }, { 0.5, 0.5, 0.52 }

-- The levels (ns.WELCOME_LEVELS), and each slot's question and
-- choices (ns.SLOT_CHOICES, ns.SlotChoices): ProfileChoices.lua.
local LEVELS = ns.WELCOME_LEVELS

-- The Customize pages: a slot's (its question and choices), or just a question.
-- (the profile of your own a change on a built-in starts: in your language here)
local OWN_PROFILE = "My setup"
local SECTIONS = {}
local VISIONS = { label = "Visions", page = "Heal Vision", question = "Which Visions do you want?",
	about = "Helpers you tick on: each shows you something only when it matters.", visions = true }
-- (The Style hub's themes, a row each: StyleThemes.lua. Not a slot: a theme is
-- its own set of settings, which no slot's choices touch.)
local THEMES = { label = "Theme", page = "Style General", question = "How should your UI look?",
	about = "A ready-made look for your frames, bars and fonts, in one click.", themes = true }
-- What each Vision does, in a line (the vision wheel's list: MarkerWheel.lua).
local VISION_LINES = {
	heal = "Party and raid frames show only who needs healing",
	quest = "Quest mobs keep their nameplates, with a quest mark",
	duel = "Watch duels near you: the duelists' health shows",
	roll = "Group loot rolls in a window: who picked what",
	vitals = "The screen's edges close in as your health drops",
	tele = "A portal opens around you as you hearth or teleport",
	emote = "A card shows who buffed you or emoted at you",
	damage = "Your race with the top of the meter, in dungeons and raids",
}
-- (Visions the vision wheel doesn't have, ticked here as the wheel's are:
-- their setting on or off. The profiles turn them on: ProfileChoices.lua.)
-- (A slot with no choices on this client isn't listed: Layout on retail.)
for _, slot in ipairs({ "frames", "layout", "bars", "camera", "vfx", "themes", "visions", "chat", "sound" }) do
	if slot == "visions" then
		tinsert(SECTIONS, VISIONS)
	elseif slot == "themes" then
		tinsert(SECTIONS, THEMES)
	elseif ns.SlotChoices(slot) then
		tinsert(SECTIONS, setmetatable({ slot = slot }, { __index = ns.SLOT_CHOICES[slot] }))
	end
end
ns.OnLanguage(function()
	OWN_PROFILE = L[OWN_PROFILE]
	ns.TranslateFields({ VISIONS, THEMES }, "label", "question", "about")
	for key, line in pairs(VISION_LINES) do VISION_LINES[key] = L[line] end
end)

local window, pages, status, about, demoRow
local cards = {} -- profile name -> its card
local levelOf = {} -- profile name -> its level

-- (Forever keeps a FontString's text and vertex colour as one: set both.)
local function Color(s, c)
	s:SetTextColor(c[1], c[2], c[3])
	s:SetVertexColor(c[1], c[2], c[3])
end

local FLAT = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local function Flat(frame, bg, edge)
	frame:SetBackdrop(FLAT)
	frame:SetBackdropColor(unpack(bg or RAISED))
	frame:SetBackdropBorderColor(unpack(edge or EDGE))
end

-- SD (the menu look, Skin.lua), for the Profiles settings page: a Flat frame
-- with the game's tooltip edge and background instead, the colours given for
-- the flat look standing in for the game's: gold stays gold, a lit edge is
-- white, any other a soft grey. plain: no edge (a list's row: the one shown
-- tinted gold). The welcome window itself is always flat.
local SD_EDGED = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local SD_PLAIN = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" }
local function Is(c, r, g, b) return c[1] == r and c[2] == g and c[3] == b end
local function Skinnable(frame, plain)
	local SetBg, SetEdge = frame.SetBackdropColor, frame.SetBackdropBorderColor
	local bg, edge = { frame:GetBackdropColor() }, { frame:GetBackdropBorderColor() }
	local sd, applying
	-- (Applying a backdrop, the game sets its colours white through these:
	-- not ours, so they're passed by, and ours put back after.)
	local Apply = frame.ApplyBackdrop
	if Apply then
		function frame:ApplyBackdrop(...)
			applying = true
			Apply(self, ...)
			applying = false
			self:SetBackdropColor(unpack(bg))
			self:SetBackdropBorderColor(unpack(edge))
		end
	end
	function frame:SetBackdropColor(r, g, b, a)
		if applying then return end
		bg = { r, g, b, a or 1 }
		if not sd then
			SetBg(self, r, g, b, a or 1)
		elseif Is(RAISED, r, g, b) then
			SetBg(self, unpack(plain and { GOLD[1], GOLD[2], GOLD[3], 0.18 } or { 0.1, 0.1, 0.1, 0.85 }))
		else
			SetBg(self, 0, 0, 0, plain and 0 or 0.55)
		end
	end
	function frame:SetBackdropBorderColor(r, g, b, a)
		if applying then return end
		edge = { r, g, b, a or 1 }
		if not sd then
			SetEdge(self, r, g, b, a or 1)
		elseif Is(GOLD, r, g, b) or Is(LIT, r, g, b) then
			SetEdge(self, unpack(Is(GOLD, r, g, b) and GOLD or WHITE))
		else
			SetEdge(self, 0.6, 0.6, 0.6)
		end
	end
	ns.OnMenuSkin(frame, function(self, skin)
		sd = skin ~= "HD"
		self:SetBackdrop(not sd and FLAT or plain and SD_PLAIN or SD_EDGED)
		self:SetBackdropColor(unpack(bg))
		self:SetBackdropBorderColor(unpack(edge))
	end)
	return frame
end

local function Text(parent, font, text, color, width)
	local s = parent:CreateFontString(nil, "OVERLAY", font)
	s:SetJustifyH("LEFT")
	s:SetJustifyV("TOP")
	if width then s:SetWidth(width) end
	s:SetText(text)
	Color(s, color or WHITE)
	return s
end

local function Rounded(parent, texture)
	if not parent.CreateMaskTexture then return end
	local mask = parent:CreateMaskTexture()
	mask:SetAllPoints(texture)
	mask:SetTexture(MASK, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
	texture:AddMaskTexture(mask)
end

-- A flat button: "main" gold, "box" outlined (the other buttons beside it),
-- otherwise just text that lights up.
local function FlatButton(parent, text, style, onClick)
	local main = style == "main" or style == "box"
	local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
	local s = Text(b, main and "GameFontHighlight" or "GameFontHighlightSmall", text,
		style == "main" and WHITE or style == "box" and SOFT or DIM)
	s:SetPoint("CENTER")
	b.text = s
	if style == "main" then
		b:SetSize(120, 30)
		Flat(b, BUTTON, BUTTON)
		b:SetScript("OnEnter", function() if b:IsEnabled() then b:SetBackdropColor(unpack(BUTTON_LIT)) end end)
		b:SetScript("OnLeave", function() if b:IsEnabled() then b:SetBackdropColor(unpack(BUTTON)) end end)
		-- (a plain box, as Settings beside it, while it can't be used: Next
		-- before a level's picked; gold once it can)
		function b:SetUsable(on)
			b:SetEnabled(on)
			Flat(b, on and BUTTON or RAISED, on and BUTTON or EDGE)
			Color(s, on and WHITE or SOFT)
		end
	elseif style == "box" then
		b:SetSize(120, 30)
		Flat(b, RAISED, EDGE)
		b:SetScript("OnEnter", function()
			if not b:IsEnabled() then return end
			b:SetBackdropBorderColor(unpack(LIT))
			Color(s, WHITE)
		end)
		b:SetScript("OnLeave", function()
			if not b:IsEnabled() then return end
			b:SetBackdropBorderColor(unpack(EDGE))
			Color(s, SOFT)
		end)
	else
		b:SetSize(s:GetStringWidth() + 6, 20)
		b:SetScript("OnEnter", function() Color(s, WHITE) end)
		b:SetScript("OnLeave", function() Color(s, DIM) end)
	end
	b:SetScript("OnClick", onClick)
	function b:SetLabel(label)
		s:SetText(label)
		if not main then b:SetWidth(s:GetStringWidth() + 6) end
	end
	return b
end

-- The same look for the Profiles settings page (Options.lua).
ns.FlatStyle = {
	Flat = Flat, Skinnable = Skinnable, Text = Text, Color = Color, Rounded = Rounded, Button = FlatButton,
	BG = BG, RAISED = RAISED, EDGE = EDGE, LIT = LIT, GOLD = GOLD, WHITE = WHITE, SOFT = SOFT, DIM = DIM,
}

-- The close X, two thin lines.
local function CloseX(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(28, 28)
	local lines = {}
	if b.CreateLine then
		for i, ends in ipairs({ { 9, 9, 19, 19 }, { 9, 19, 19, 9 } }) do
			local line = b:CreateLine(nil, "OVERLAY")
			line:SetThickness(2)
			line:SetStartPoint("BOTTOMLEFT", b, ends[1], ends[2])
			line:SetEndPoint("BOTTOMLEFT", b, ends[3], ends[4])
			line:SetColorTexture(unpack(DIM))
			lines[i] = line
		end
	else
		local s = Text(b, "GameFontHighlightLarge", "x", DIM)
		s:SetPoint("CENTER")
		b:SetScript("OnEnter", function() Color(s, WHITE) end)
		b:SetScript("OnLeave", function() Color(s, DIM) end)
	end
	if lines[1] then
		b:SetScript("OnEnter", function() for _, l in ipairs(lines) do l:SetColorTexture(unpack(WHITE)) end end)
		b:SetScript("OnLeave", function() for _, l in ipairs(lines) do l:SetColorTexture(unpack(DIM)) end end)
	end
	b:SetScript("OnClick", function() parent:Hide() end)
	return b
end

-- What the description box says: the hovered level's, else the picked one's.
local function Describe(level)
	if demoRow then demoRow:Update(level) end
	if level then
		about:SetText("|cffffd100" .. level.label .. "|r   " .. level.tip)
	else
		about:SetText(L["Pick a level to try it now. You can change it any time, here or on the Profiles page."])
	end
end

local function Active()
	return ns.ProfileChosen() and ns.db.enabled and ns.ActiveProfile()
end

local primary, finish, settings, off, back

-- Gold edge on the level being tried, the lines saying so, and the way out:
-- Decide later (none picked yet) or Done.
local function UpdatePicked()
	local active = Active()
	for name, card in pairs(cards) do
		card.active = name == active
		card:SetBackdropBorderColor(unpack(card.active and GOLD or EDGE))
	end
	if active then
		local name = levelOf[active] and levelOf[active].label or ns.ProfileLabel(active)
		status:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t "
			.. L["Trying %s. Close this window to keep it."]:format("|cffffd100" .. name .. "|r"))
	elseif not ns.db.enabled then
		status:SetText(L["Cinematic is off. Pick a level, or Turn on, to start it again."])
	else
		status:SetText(L["Nothing runs until you pick one."])
	end
	finish:SetLabel(ns.ProfileChosen() and L["See Profile"] or L["Decide later"])
	-- (Next only once a level's picked: Customize changes a level. Not for
	-- one with noCustomize, Blank Slate: its parts are all off.)
	local level = levelOf[active]
	if pages[1]:IsShown() then primary:SetUsable(active and not (level and level.noCustomize) and true or false) end
	Describe(levelOf[active])
end

local function Pick(name, level)
	if InCombatLockdown() then ns.ProfileSwitchBlocked() return end -- (says so)
	if not ns.db.enabled then ns.SetEnabled(true) end
	ns.SetProfile(name)
	if ns.RestartTimers then ns.RestartTimers() end
	ns.PreviewProfile(name)
	-- (Cinema: Vitals Vision's screen edges for a moment, too. Another level
	-- ends that look at once.)
	if ns.StopVitalsFlash then ns.StopVitalsFlash() end
	if level and level.flash == "vitals" and ns.FlashVitals then ns.FlashVitals(2) end
	UpdatePicked()
end

-- A level's card: its profile's icon, the level's name and a short line.
local function Card(parent, profile, level)
	local card = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
	card:SetSize(CARD_W, 124)
	Flat(card)
	local icon = card:CreateTexture(nil, "ARTWORK")
	icon:SetSize(44, 44)
	icon:SetPoint("TOP", 0, -16)
	icon:SetTexture(profile.icon)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	Rounded(card, icon)
	local title = Text(card, "GameFontHighlightLarge", level.label)
	title:SetPoint("TOP", icon, "BOTTOM", 0, -8)
	local sub = Text(card, "GameFontHighlightSmall", level.line, SOFT, CARD_W - 20)
	sub:SetJustifyH("CENTER")
	sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
	card:SetScript("OnEnter", function(self)
		if not self.active then self:SetBackdropBorderColor(unpack(LIT)) end
		Describe(level)
	end)
	card:SetScript("OnLeave", function(self)
		if not self.active then self:SetBackdropBorderColor(unpack(EDGE)) end
		Describe(levelOf[Active()])
	end)
	card:SetScript("OnClick", function() Pick(profile.name, level) end)
	return card
end

-- See it first: a row of demos under the level cards, each a few seconds
-- of one look (ShowMe.lua), Stop while it runs. Under each, whether the
-- level hovered (else the one picked) has it. A Vision's test plays with
-- its switch off too: trying it is the point.
local DEMO_ROW = {
	-- (each its settings page's icon, or its Vision's; tip: the description
	-- box's words while it's hovered)
	{ key = "bars", label = "Letterbox", icon = "Interface\\Icons\\Spell_Shadow_ShadesOfDarkness",
		tip = "Black bars at the top and bottom of the screen, as in a film." },
	{ key = "tint", label = "Tint", icon = "Interface\\Icons\\INV_Misc_Gem_Variety_02",
		tip = "A color wash over the world that follows the time of day and the zone, with soft dark edges " ..
			"and weather to match." },
	{ key = "camera", label = "Camera", icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
		tip = "The camera moves on its own at quiet moments: on flights, when you go AFK, by a campfire. " ..
			"This shows a half turn around you; move the camera yourself to stop it." },
	{ key = "vitals", label = "Vitals", icon = "Interface\\Icons\\Spell_Shadow_LifeDrain02",
		tip = "As your health drops, the screen's edges close in, so you feel a fight without watching " ..
			"your health bar." },
	{ key = "tele", label = "Teleport", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind",
		tip = "As you cast your Hearthstone or a teleport, a portal opens around you and the world fades " ..
			"out as you leave." },
}
local DEMO_ROW_H = 74
local function BuildDemoRow(page, width)
	local row = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate")
	row:SetSize(width, DEMO_ROW_H)
	Flat(row, BG)
	local head = Text(row, "GameFontNormalSmall", L["See it first"], GOLD)
	head:SetPoint("TOPLEFT", 12, -9)
	local hint = Text(row, "GameFontHighlightSmall", L["Click one to see it for a few seconds."], DIM)
	hint:SetJustifyH("RIGHT")
	hint:SetPoint("TOPRIGHT", -12, -9)
	local list = {}
	for _, demo in ipairs(DEMO_ROW) do
		if ns.ShowMeAvailable and ns.ShowMeAvailable(demo.key) then list[#list + 1] = demo end
	end
	local gap = 6
	local buttonW = (width - 24 - gap * math.max(0, #list - 1)) / math.max(1, #list)
	local buttons = {}
	for i, demo in ipairs(list) do
		local b = CreateFrame("Button", nil, row, BackdropTemplateMixin and "BackdropTemplate")
		b:SetSize(buttonW, 38)
		b:SetPoint("BOTTOMLEFT", 12 + (i - 1) * (buttonW + gap), 10)
		Flat(b, RAISED, EDGE)
		-- (its icon on the left, rounded as the level cards' are; the name
		-- and its In or Not in beside it)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(26, 26)
		b.icon:SetPoint("LEFT", 6, 0)
		b.icon:SetTexture(demo.icon)
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		Rounded(b, b.icon)
		b.name = Text(b, "GameFontHighlightSmall", L[demo.label], SOFT, buttonW - 40)
		b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, 0)
		b.name:SetWordWrap(false)
		b.tag = Text(b, "GameFontDisableSmall", "", DIM, buttonW - 40)
		b.tag:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
		b.tag:SetWordWrap(false)
		b:SetScript("OnClick", function() ns.ShowMe(demo.key, window, true) end)
		b:SetScript("OnEnter", function(self)
			if self:IsEnabled() then self:SetBackdropBorderColor(unpack(LIT)) end
			about:SetText("|cffffd100" .. L[demo.label] .. "|r   " .. L[demo.tip])
			local why = ns.ShowMeBlocked(demo.key, true)
			if why then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(why, 1, 1, 1, 1, true)
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function(self)
			self:SetBackdropBorderColor(unpack(ns.ShowMeRunning(demo.key) and GOLD or EDGE))
			GameTooltip:Hide()
			Describe(levelOf[Active()])
		end)
		b.demo = demo
		buttons[i] = b
	end
	local show -- (the level the tags are for: Describe's, nil for none)
	-- keep: the same level as last time (a demo started or ended, a fight).
	function row:Update(level, keep)
		if not keep then show = level end
		for _, b in ipairs(buttons) do
			local key = b.demo.key
			local running = ns.ShowMeRunning(key)
			local blocked = not running and ns.ShowMeBlocked(key, true)
			b:SetEnabled(not blocked)
			b.name:SetText(running and L["Stop"] or L[b.demo.label])
			Color(b.name, blocked and DIM or running and GOLD or SOFT)
			b.icon:SetDesaturated(blocked and true or false)
			b.icon:SetAlpha(blocked and 0.5 or 1)
			b:SetBackdropBorderColor(unpack(running and GOLD or EDGE))
			local has = show and ns.ShowMeInProfile(key, show.profile)
			if has == nil then
				b.tag:SetText("")
			else
				b.tag:SetText((has and L["In %s"] or L["Not in %s"]):format(show.label))
				Color(b.tag, has and GOLD or DIM)
			end
		end
	end
	local function Recheck() if row:IsVisible() then row:Update(nil, true) end end
	if ns.ShowMeListen then ns.ShowMeListen(Recheck) end
	row:RegisterEvent("PLAYER_REGEN_DISABLED")
	row:RegisterEvent("PLAYER_REGEN_ENABLED")
	row:SetScript("OnEvent", Recheck)
	row:SetScript("OnShow", Recheck)
	row:SetScript("OnHide", function() if ns.StopShowMe then ns.StopShowMe() end end)
	return row
end

-- Page 1: the levels.
local function BuildLevels(page)
	local title = Text(page, "GameFontNormalHuge", L["Welcome to Cinematic"], GOLD)
	title:SetPoint("TOPLEFT")
	local sub = Text(page, "GameFontHighlight", L["Select a profile that suits you."], SOFT)
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

	local byName = {}
	for _, profile in ipairs(ns.BUILTIN_PROFILES) do byName[profile.name] = profile end
	for i, level in ipairs(LEVELS) do
		local profile = byName[level.profile or ns.DEFAULT_PROFILE]
		if profile then
			local card = Card(page, profile, level)
			card:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", (i - 1) * (CARD_W + GAP), -18)
			cards[profile.name], levelOf[profile.name] = card, level
		end
	end

	-- See it first, then the description box, under the cards.
	local rowH = 0
	if ns.ShowMe then
		demoRow = BuildDemoRow(page, WIDTH - 2 * PAD)
		demoRow:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -18 - 124 - 12)
		rowH = DEMO_ROW_H + 12
	end
	local box = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate")
	box:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -18 - 124 - 12 - rowH)
	box:SetSize(WIDTH - 2 * PAD, 56)
	Flat(box, BG)
	about = Text(box, "GameFontHighlightSmall", "", SOFT, WIDTH - 2 * PAD - 24)
	about:SetPoint("TOPLEFT", 12, -10)
	about:SetSpacing(2)
	-- (As tall as the longest description, in this language, so none runs
	-- out of it; the window grows to match.)
	local tallest = 0
	for _, level in ipairs(LEVELS) do
		Describe(level)
		tallest = math.max(tallest, about:GetStringHeight())
	end
	Describe(nil)
	tallest = math.max(tallest, about:GetStringHeight())
	local boxH = math.max(56, math.ceil(tallest) + 20)
	box:SetHeight(boxH)

	status = Text(page, "GameFontHighlightSmall", "", SOFT)
	status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
	page.height = 380 + boxH - 56 + rowH
end

-- The Customize panel: a list of parts on the left and the one shown on the
-- right, width wide. The welcome window's Customize page has it, and so does
-- the Profiles settings page (Options.lua). onChange runs when the player
-- changes something or shows another part. Its frame has :Refresh() (the
-- choices as the live settings have them now), :Next() (the part after this
-- one, false on the last), :IsLast() and :SettingsPage(). skinned: in the
-- menu look, SD too (the Profiles page; Skinnable above).
function ns.CustomizePanel(parent, width, onChange, skinned)
	-- (Rows past the panel's height scroll: the Visions page has more than fit.)
	local NAV_W, PANEL_H, FOOT_H = 140, 360, 36
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, PANEL_H)
	local rows, question, about, soon, saved, panel, scroll, list
	local options = {} -- the choices shown, as rows
	local panelW = width - NAV_W - GAP
	local shown -- (the section shown)
	local function Changed() if onChange then onChange() end end

	-- Gold edge on the choice the live settings match (none: your own mix),
	-- or on each Vision that's on, and which profile a change goes in.
	local building = true
	local function UpdateChoices()
		-- (built before the settings load, at the language, or with the
		-- window: the page's refresh as it's shown does it. Matching every
		-- choice is slow, too much on top of the build on a slower client.)
		if not ns.db or building then return end
		-- (A theme since changed: its row stays gold, and the note says it's a mix.)
		local any = shown.visions or shown.themes and not ns.StyleThemeEdited()
		for _, option in ipairs(options) do
			local vision = option.choice and option.choice.vision
			if vision then
				option.active = option:IsShown() and ns.VisionOn(vision)
			elseif option.choice.theme then
				option.active = option:IsShown() and option.choice.theme == ns.ActiveStyleTheme().key
			elseif option.choice.custom then
				-- (Custom, last: shown and gold only when no choice matches)
				option.active = not any
				option:SetShown(option.active)
			else
				-- (the first that matches: two parts can set a slot the same way)
				option.active = not any and option:IsShown() and ns.SlotPartMatches(shown.slot, option.choice.part)
				any = any or option.active
			end
			option:SetBackdropBorderColor(unpack(option.active and GOLD or EDGE))
		end
		local active = ns.ActiveProfile()
		if not shown.slot and not shown.visions and not shown.themes then
			saved:SetText("")
		elseif ns.IsBuiltinProfile(active) then
			saved:SetText(L["A change here starts a profile of your own, %s."]:format(OWN_PROFILE))
		else
			saved:SetText((any and L["Changes go in your profile %s."]
				or L["Changes go in your profile %s. This part is a mix of its own."])
				:format("|cffffd100" .. active .. "|r"))
		end
		-- (Show me: Stop while its demo runs, greyed while it can't run)
		for _, option in ipairs(options) do
			if option.demo and option:IsShown() then
				local running = ns.ShowMeRunning(option.demo)
				local blocked = not running and ns.ShowMeBlocked(option.demo, true)
				option.show:SetLabel(running and L["Stop"] or L["Show me"])
				option.show:SetEnabled(not blocked)
				Color(option.show.text, blocked and DIM or running and GOLD or SOFT)
			end
		end
	end

	-- The Edit Mode layout of Cinematic's a choice switches to (its layout
	-- module's), nil for none.
	local function MadeLayout(choice)
		for _, key in ipairs(choice.modules or {}) do
			if type(key) == "table" then key = key[ns.CLIENT] end
			local module = key and ns.GetModule(key)
			if module and ns.EDIT_MODE_LAYOUTS[module.editMode or ""] then return module.editMode end
		end
	end

	-- A choice's row: an icon, its name and a line, gold when it's the live one.
	local function Option(i)
		local option = CreateFrame("Button", nil, list, BackdropTemplateMixin and "BackdropTemplate")
		option:SetSize(panelW - 28, 40)
		Flat(option, BG)
		if skinned then Skinnable(option) end
		option.icon = option:CreateTexture(nil, "ARTWORK")
		option.icon:SetSize(28, 28)
		option.icon:SetPoint("LEFT", 8, 0)
		option.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		Rounded(option, option.icon)
		option.name = Text(option, "GameFontHighlight", "")
		option.name:SetPoint("TOPLEFT", 10, -6)
		option.name:SetWordWrap(false)
		-- (a layout Cinematic makes for you: a gold tag beside its name)
		option.tag = Text(option, "GameFontHighlightSmall", "Cinematic", GOLD)
		option.tag:SetPoint("LEFT", option.name, "RIGHT", 8, 0)
		option.line = Text(option, "GameFontHighlightSmall", "", SOFT, panelW - 28 - 60)
		option.line:SetPoint("TOPLEFT", option.name, "BOTTOMLEFT", 0, -3)
		option.line:SetWordWrap(true) -- (wrapped: the row grows to fit it)
		option.line:SetJustifyH("LEFT")
		-- (a theme's colors, at the end of its name's line)
		option.chips = {}
		for j = 1, 3 do
			local chip = option:CreateTexture(nil, "ARTWORK")
			chip:SetSize(16, 5)
			chip:SetPoint("TOPRIGHT", -10 - (3 - j) * 19, -11)
			option.chips[j] = chip
		end
		-- (and once it's in Edit Mode, Regenerate: made again from the code,
		-- Edit Mode then back on the profile's layout if this isn't it)
		option.regenerate = FlatButton(option, L["Regenerate"], "box", function()
			local name = option.layout
			if not (name and ns.RegenerateLayout(name)) then return end
			if (ns.db.editModeLayout or "") ~= name then
				ns.chardb.layoutPending = nil
				ns.ApplyProfileLayout()
			end
			Changed()
		end)
		option.regenerate:SetSize(96, 24)
		option.regenerate:SetPoint("RIGHT", -8, 0)
		if skinned then Skinnable(option.regenerate) end
		option.regenerate:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["Make this layout again as Cinematic has it, undoing any changes you " ..
				"made to it in Edit Mode."], 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		option.regenerate:HookScript("OnLeave", function() GameTooltip:Hide() end)
		-- (Show me: the choice tried for a few seconds, Stop while it runs;
		-- greyed, with why, while it can't run: ShowMe.lua)
		option.show = FlatButton(option, L["Show me"], "box", function()
			-- (The welcome window steps aside for a camera; the Settings
			-- window stays, as on the Cameras page's Test buttons.)
			local top
			if not skinned then
				top = holder
				while top:GetParent() and top:GetParent() ~= UIParent do top = top:GetParent() end
			end
			ns.ShowMe(option.demo, top, true)
		end)
		option.show:SetSize(84, 24)
		option.show:SetPoint("RIGHT", -8, 0)
		if skinned then Skinnable(option.show) end
		option.show:HookScript("OnEnter", function(self)
			local why = option.demo and ns.ShowMeBlocked(option.demo, true)
			if not why then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(why, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		option.show:HookScript("OnLeave", function() GameTooltip:Hide() end)
		option:SetScript("OnEnter", function(self)
			if not self.active then self:SetBackdropBorderColor(unpack(LIT)) end
		end)
		option:SetScript("OnLeave", function(self)
			if not self.active then self:SetBackdropBorderColor(unpack(EDGE)) end
		end)
		option:SetScript("OnClick", function(self)
			local vision = self.choice.vision
			if vision then
				-- (A Vision: on or off, any number of them, in a profile of your own.)
				ns.EnsureOwnProfile(OWN_PROFILE)
				ns.ToggleVision(vision, true)
				ns.SaveProfile()
				UpdateChoices()
				Changed()
				return
			end
			local theme = self.choice.theme
			if theme then
				if self.active then return end
				if not ns.db.enabled then ns.SetEnabled(true) end
				ns.EnsureOwnProfile(OWN_PROFILE)
				ns.ApplyStyleTheme(theme)
				ns.SaveProfile()
				UpdateChoices()
				Changed()
				ns.PlayThemeCard()
				return
			end
			if self.active or self.choice.custom then return end -- (already so: no profile of your own for nothing)
			if not ns.db.enabled then ns.SetEnabled(true) end
			ns.ApplyPart(shown.slot, self.choice.part, OWN_PROFILE)
			UpdateChoices()
			Changed() -- (a profile's picked now: Done, not Decide later)
		end)
		options[i] = option
		return option
	end

	local Lay -- (below: the rows laid out)
	local function Show(i, quiet)
		for j, row in ipairs(rows) do
			row.on = i == j
			row:SetBackdropColor(unpack(row.on and RAISED or BG))
			Color(row.text, row.on and WHITE or SOFT)
		end
		shown = SECTIONS[i]
		question:SetText(shown.question)
		about:SetText(shown.about or "")
		local choices = shown.slot and ns.SlotChoices(shown.slot) or {}
		if shown.visions then
			-- (each a row that's ticked on or off, its icon as the vision wheel has it)
			choices = {}
			for _, vision in ipairs(ns.VISION_LIST or {}) do
				if not vision.notWelcome then
					choices[#choices + 1] = { vision = vision, label = L[vision.label], icon = vision.icon,
						line = VISION_LINES[vision.key] }
				end
			end
		elseif shown.themes then
			choices = {}
			for _, theme in ipairs(ns.StyleThemeList()) do
				choices[#choices + 1] = { theme = theme.key, label = theme.name, line = theme.tip, swatch = theme.swatch }
			end
		elseif #choices > 0 then
			-- (and Custom, for settings none of them has)
			local own = {}
			for j, choice in ipairs(choices) do own[j] = choice end
			own[#own + 1] = { custom = true, label = L["Custom"], line = L["Your own mix of this part's settings"] }
			choices = own
		end
		soon:SetShown(#choices == 0)
		-- (rows under the question, each as tall as its line wrapped needs;
		-- when they don't all fit, the list scrolls and its bar takes room
		-- off the rows' right: laid out again that much narrower)
		local fits = PANEL_H - 14 - math.ceil(question:GetStringHeight()) - 4 - math.ceil(about:GetStringHeight())
			- 12 - FOOT_H
		local total = Lay(choices, panelW - 28)
		local overflow = total > fits
		if overflow then total = Lay(choices, panelW - 28 - 22) end
		scroll:ClearAllPoints()
		scroll:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -12)
		scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14 - (overflow and 22 or 0), FOOT_H)
		if scroll.ScrollBar then scroll.ScrollBar:SetShown(overflow) end
		list:SetSize(panelW - 28 - (overflow and 22 or 0), math.max(1, total))
		scroll:SetVerticalScroll(0)
		for j = #choices + 1, #options do options[j]:Hide() end
		UpdateChoices()
		if not quiet then Changed() end
	end
	-- The choices' rows, rowW wide, one under another; their height in all.
	function Lay(choices, rowW)
		local y = 0
		for j, choice in ipairs(choices) do
			local option = options[j] or Option(j)
			option:SetWidth(rowW)
			option:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
			option.choice = choice
			-- (an icon when the choice has one, the text beside it)
			option.icon:SetTexture(choice.icon)
			option.icon:SetShown(choice.icon ~= nil)
			local nameX = choice.icon and 46 or 10
			option.name:SetPoint("TOPLEFT", nameX, -6)
			option.name:SetWidth(0)
			option.name:SetText(choice.label)
			option.tag:SetShown(choice.made == true)
			-- (The swatch's first color is the theme's panel: the rest are what show on it.)
			for k, chip in ipairs(option.chips) do
				local color = choice.swatch and choice.swatch[k + 1]
				if color then chip:SetColorTexture(color[1], color[2], color[3], 1) end
				chip:SetShown(color ~= nil)
			end
			option.layout = choice.made and MadeLayout(choice) or nil
			local regenerate = option.layout ~= nil and ns.LayoutState(option.layout) ~= nil
			option.regenerate:SetShown(regenerate)
			-- (Regenerate as wide as its word, and the name cut short before the
			-- tag would slip under it)
			local regenW = math.max(64, math.ceil(option.regenerate.text:GetStringWidth()) + 20)
			option.regenerate:SetWidth(regenW)
			local room = rowW - nameX - (regenerate and regenW + 16 or 8)
				- (choice.made and math.ceil(option.tag:GetStringWidth()) + 8 or 0)
			if option.name:GetStringWidth() > room then option.name:SetWidth(room) end
			option.demo = not regenerate and ns.ShowMeFor and ns.ShowMeFor(shown.slot, choice) or nil
			option.show:SetShown(option.demo ~= nil)
			if option.demo then room = room - 92 end
			if option.name:GetStringWidth() > room then option.name:SetWidth(room) end
			option.line:SetWidth(rowW - (choice.icon and 56 or 20) - (regenerate and regenW + 8 or 0)
				- (option.demo and 92 or 0))
			option.line:SetText(choice.line or "")
			local height = math.max(40, math.ceil(6 + option.name:GetStringHeight() + 3
				+ (choice.line and option.line:GetStringHeight() or 0) + 7))
			option:SetHeight(height)
			option:Show()
			y = y + height + 4
		end
		return math.max(0, y - 4)
	end
	function holder:Refresh() if shown then Show(shown.index, true) end end
	function holder:Next()
		if shown.index >= #SECTIONS then return false end
		Show(shown.index + 1)
		return true
	end
	function holder:IsLast() return shown.index >= #SECTIONS end
	function holder:SettingsPage() return shown and shown.page end
	rows = {}
	for i, section in ipairs(SECTIONS) do
		section.index = i
		local row = CreateFrame("Button", nil, holder, BackdropTemplateMixin and "BackdropTemplate")
		row:SetSize(NAV_W, 26)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
		Flat(row, BG, BG)
		if skinned then Skinnable(row, true) end
		row.text = Text(row, "GameFontHighlight", section.label, SOFT)
		row.text:SetPoint("LEFT", 10, 0)
		row:SetScript("OnEnter", function() if not row.on then Color(row.text, WHITE) end end)
		row:SetScript("OnLeave", function() if not row.on then Color(row.text, SOFT) end end)
		row:SetScript("OnClick", function() Show(i) end)
		rows[i] = row
	end

	panel = CreateFrame("Frame", nil, holder, BackdropTemplateMixin and "BackdropTemplate")
	panel:SetPoint("TOPLEFT", NAV_W + GAP, 0)
	panel:SetSize(panelW, PANEL_H)
	Flat(panel)
	if skinned then Skinnable(panel) end
	question = Text(panel, "GameFontHighlightLarge", "", WHITE, panelW - 28)
	question:SetPoint("TOPLEFT", 14, -14)
	-- (under the question, a line on what the section does)
	about = Text(panel, "GameFontHighlightSmall", "", DIM, panelW - 28)
	about:SetPoint("TOPLEFT", question, "BOTTOMLEFT", 0, -4)
	scroll = ns.SkinScroll(CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate"))
	list = CreateFrame("Frame", nil, scroll)
	list:SetSize(1, 1)
	scroll:SetScrollChild(list)
	soon = Text(panel, "GameFontHighlightSmall", L["Its choices come next."], DIM)
	soon:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -8)
	saved = Text(panel, "GameFontHighlightSmall", "", DIM, panelW - 28)
	saved:SetPoint("BOTTOMLEFT", 14, 12)
	Show(1, true)
	building = false
	-- (Show me's buttons kept up to date: a demo starting or ending, a
	-- fight; and a demo stops as the panel goes)
	local function Recheck() if holder:IsVisible() then UpdateChoices() end end
	if ns.ShowMeListen then ns.ShowMeListen(Recheck) end
	holder:RegisterEvent("PLAYER_REGEN_DISABLED")
	holder:RegisterEvent("PLAYER_REGEN_ENABLED")
	holder:SetScript("OnEvent", Recheck)
	holder:HookScript("OnHide", function() if ns.StopShowMe then ns.StopShowMe() end end)
	return holder
end

-- Page 2: Customize, the panel above.
local function BuildCustomize(page)
	local title = Text(page, "GameFontNormalHuge", L["Customize"], GOLD)
	title:SetPoint("TOPLEFT")
	local sub = Text(page, "GameFontHighlight", L["Change one part of your level. Each change shows straight away."],
		SOFT)
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	local panel = ns.CustomizePanel(page, WIDTH - 2 * PAD, function()
		if page.OnShow then page.OnShow() end
	end)
	panel:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -18)
	page.Refresh = function()
		panel:Refresh()
		if page.OnShow then page.OnShow() end
	end
	page.Next = function() return panel:Next() end
	page.IsLast = function() return panel:IsLast() end
	page.settingsPage = function() return panel:SettingsPage() end
	page.height = 536 -- (the Customize panel's 360, and the title above it)
end

local function ShowPage(n)
	for i, page in ipairs(pages) do page:SetShown(i == n) end
	if n == 1 then
		primary:SetLabel(L["Next"])
		finish:Show()
		UpdatePicked()
	elseif pages[n].Refresh then
		pages[n].Refresh()
	end
	off:SetShown(n == 1)
	off:SetLabel(ns.db.enabled and L["Turn off"] or L["Turn on"])
	back:SetShown(n > 1)
	window.page = n
	window:SetHeight(pages[n].height)
end

-- Closed (the X, Escape, Done or Decide later): what's on now, in chat.
-- (Not on the way to the settings: those say it.)
local toSettings
local function OnHide()
	if toSettings then
		toSettings = false
	elseif not ns.db.enabled then -- (closed after Turn off)
		ns.Print(L["turned off. /cine brings this window back to pick a profile."])
	elseif not ns.ProfileChosen() then
		ns.Print(L["off until you pick a profile. This window comes back next login, or now with /cine welcome."])
	else
		ns.Print(L["profile: %s. Change it any time on the Profiles settings page, or with /cine profile."]
			:format(ns.ProfileLabel(ns.ActiveProfile())))
	end
end

local function CreateWindow()
	window = CreateFrame("Frame", "CinematicWelcome", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	window:SetWidth(WIDTH)
	window:SetPoint("CENTER", 0, 60)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetScript("OnHide", OnHide)
	Flat(window, { BG[1], BG[2], BG[3], 0.97 })
	tinsert(UISpecialFrames, "CinematicWelcome") -- Escape closes it, as the X does

	-- The X keeps the level picked (and with none, Cinematic stays off).
	CloseX(window):SetPoint("TOPRIGHT", -8, -8)

	pages = {}
	for i, build in ipairs({ BuildLevels, BuildCustomize }) do
		local page = CreateFrame("Frame", nil, window)
		page:SetPoint("TOPLEFT", PAD, -PAD)
		page:SetPoint("BOTTOMRIGHT", -PAD, PAD)
		build(page)
		pages[i] = page
	end
	-- On Customize the main button steps through the parts: Next, then Done
	-- (or Decide later) on the last.
	pages[2].OnShow = function()
		local out = ns.ProfileChosen() and L["See Profile"] or L["Decide later"]
		local last = pages[2].IsLast()
		primary:SetUsable(true)
		primary:SetLabel(last and out or L["Next"])
		-- (the quiet way out too, but not twice on the last)
		finish:SetLabel(out)
		finish:SetShown(not last)
	end

	-- Footer: a quiet link on the left (Turn off, or Back); on the right
	-- Next, the way on: from the levels to Customize, then through its parts,
	-- Done on the last. Beside it Settings (the options at the page for
	-- what's shown: the Profiles page, or the part's) and, quietly, Done (or
	-- Decide later): out at any point, keeping what's picked, as the X does.
	-- See Profile (once one's picked) closes onto the CineMode page's
	-- Overview: everything the profile turned on, page by page.
	local function Finish()
		if ns.ProfileChosen() then
			-- (the chat line naming the profile still prints: the Overview
			-- doesn't name it)
			window:Hide()
			if ns.OpenCineModeOverview then ns.OpenCineModeOverview() else ns.OpenOptions("CineMode") end
		else
			window:Hide()
		end
	end
	primary = FlatButton(window, L["Next"], "main", function()
		if window.page == 1 then
			ShowPage(2)
		elseif not pages[2].Next() then
			Finish()
		end
	end)
	primary:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	finish = FlatButton(window, L["See Profile"], nil, Finish)
	settings = FlatButton(window, L["Settings"], "box", function()
		local page = window.page == 2 and pages[2].settingsPage() or "Profiles"
		toSettings = true
		window:Hide()
		ns.OpenOptions(page)
	end)
	settings:SetPoint("RIGHT", primary, "LEFT", -8, 0)
	finish:SetPoint("RIGHT", settings, "LEFT", -12, 0)
	-- Turn off (or on again): Cinematic, not the window, which stays open to
	-- pick a level.
	off = FlatButton(window, L["Turn off"], nil, function()
		local on = not ns.db.enabled
		ns.SetEnabled(on)
		off:SetLabel(on and L["Turn off"] or L["Turn on"])
		UpdatePicked()
	end)
	off:SetPoint("BOTTOMLEFT", PAD - 3, PAD + 5)
	back = FlatButton(window, L["< Back"], nil, function() ShowPage(1) end)
	back:SetPoint("BOTTOMLEFT", PAD - 3, PAD + 5)
end

function ns.ShowWelcome()
	-- (A build an error stopped halfway: thrown away and made again.)
	if window and not back then
		window:SetScript("OnHide", nil)
		window:Hide()
		window = nil
	end
	if not window then CreateWindow() end
	window:Show()
	ShowPage(1)
end

-- The level cards in their order (the Demo Hub's welcome tour clicks them).
function ns.WelcomeCards()
	local list = {}
	for _, level in ipairs(LEVELS) do
		local card = cards[level.profile or ns.DEFAULT_PROFILE]
		if card then list[#list + 1] = card end
	end
	return list
end

-- At login (and /reload), until a profile's been picked.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(_, _, isLogin, isReload)
	if (isLogin or isReload) and ns.db and not ns.db.profileChosen and ns.db.enabled then
		C_Timer.After(1, ns.ShowWelcome)
	end
end)
