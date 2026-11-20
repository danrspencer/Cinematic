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
local THEMES = { label = "Theme", page = "Style Themes", question = "How should your UI look?",
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
-- (Its edge one whole screen pixel, and its pieces not snapped to the pixel
-- grid: snapped, an edge that thin can round to nothing where it lands
-- between two pixels, so some boxes and buttons lost a side: the cards' and
-- See it first buttons' tops, the description box's bottom.)
local FLAT_BY_SIZE = {}
local BACKDROP_PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
	"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }
local function NoSnap(frame)
	for _, key in ipairs(BACKDROP_PIECES) do
		local piece = frame[key]
		if piece and piece.SetSnapToPixelGrid then
			piece:SetSnapToPixelGrid(false)
			if piece.SetTexelSnappingBias then piece:SetTexelSnappingBias(0) end
		end
	end
end
local function Flat(frame, bg, edge)
	local size = 1
	if PixelUtil and PixelUtil.GetNearestPixelSize then
		size = PixelUtil.GetNearestPixelSize(1, frame:GetEffectiveScale(), 1)
	end
	local backdrop = FLAT_BY_SIZE[size]
	if not backdrop then
		backdrop = { bgFile = FLAT.bgFile, edgeFile = FLAT.edgeFile, edgeSize = size }
		FLAT_BY_SIZE[size] = backdrop
	end
	frame:SetBackdrop(backdrop)
	NoSnap(frame)
	frame.cineFlat = backdrop
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
		self:SetBackdrop(not sd and (self.cineFlat or FLAT) or plain and SD_PLAIN or SD_EDGED)
		if not sd then NoSnap(self) end
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
		about:SetText("|cffffd100" .. level.label .. "|r   " .. level.tip .. (level.note and ("  " .. level.note) or ""))
	else
		-- (And what it changes in the game, said before anything's picked: a
		-- player's report 2026-11-17 found settings and layouts left after
		-- removing the addon. Reset addon puts them back.)
		about:SetText(L["Pick a level to try it now. You can change it any time, here or on the Profiles page."]
			.. "\n" .. L["A level may change some game settings, like nameplates and names, which go back when you " ..
			"log out, and add an Edit Mode layout, which Reset addon on the main settings page deletes."])
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
	-- (The first pick asks about game settings first; Continue picks it again.)
	if ns.GameSettingsAgreed and not ns.GameSettingsAgreed(function() Pick(name, level) end) then return end
	if not ns.db.enabled then ns.SetEnabled(true) end
	-- (The Shoulder Cam's card: picking it is the yes to its one-time
	-- question, the card's line saying why. Before and after the switch: the
	-- profile's settings are loaded over db.)
	if level and level.shoulderCam and ns.ShoulderCamAgree then ns.ShoulderCamAgree() end
	ns.SetProfile(name)
	if level and level.shoulderCam and ns.ShoulderCamAgree then ns.ShoulderCamAgree() end
	-- (the shelf's Turn on marks were the last level's)
	if demoRow and demoRow.LevelPicked then demoRow:LevelPicked() end
	-- (the profile's tint strength on the slider)
	if demoRow and demoRow.ShowStrength then demoRow.ShowStrength() end
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
	sub:SetSpacing(2)
	sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
	-- (how tall the card needs to be for its line, with room under it)
	card.need = 16 + 44 + 8 + title:GetStringHeight() + 4 + sub:GetStringHeight() + 14
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
-- of one look (ShowMe.lua), Stop while it runs. Under each, when the
-- level hovered (else the one picked) shows it (In CineMode, 4 scenes, Off:
-- ns.ShowMeWhen), and hovered, that in words in the description box. A Vision's test plays with
-- its switch off too: trying it is the point. Its last slot, See all, opens
-- the shelf in place (docs/design/welcome-shelf.md): every feature with
-- something to play, by the settings hub it's in.
local DEMO_ROW = {
	-- (each its settings page's icon, or its Vision's; tip: the description
	-- box's words while it's hovered; group: its hub on the shelf)
	-- (Fading UI: CineMode itself, the first thing a player expects. The HUD's
	-- icon is your faction's banner: Lesser Invisibility here, the UI going.)
	{ key = "fadeUI", label = "Fading UI", icon = "Interface\\Icons\\Spell_Magic_LesserInvisibilty", group = "ui",
		tip = "Your UI fades away between fights and comes back when you need it." },
	{ key = "bars", label = "Letterbox", icon = "Interface\\Icons\\Spell_Shadow_ShadesOfDarkness", group = "atmo",
		tip = "Black bars at the top and bottom of the screen, as in a film." },
	{ key = "tint", label = "Tint", icon = "Interface\\Icons\\INV_Misc_Gem_Variety_02", group = "atmo",
		tip = "A color wash over the world that follows the time of day and the zone, with soft dark edges " ..
			"and weather to match." },
	{ key = "camera", label = "Camera", icon = "Interface\\Icons\\INV_Misc_Spyglass_03", group = "cam",
		tip = "The camera moves on its own at quiet moments: on flights, when you go AFK, by a campfire. " ..
			"This shows a half turn around you; move the camera yourself to stop it." },
	{ key = "vitals", label = "Vitals", icon = "Interface\\Icons\\Spell_Shadow_LifeDrain02", group = "vis",
		tip = "As your health drops, the screen's edges close in, so you feel a fight without watching " ..
			"your health bar." },
	-- (Its test turns it on for a few seconds, whatever the level: ShowMe.lua's
	-- "shoulder". Running it is the Shoulder Cam's one-time question's yes,
	-- its tip says why.)
	{ key = "shoulder", label = "Shoulder Cam", icon = "Interface\\Icons\\INV_Shoulder_02", group = "cam",
		tip = "The camera moves over your shoulder, with you to one side of the screen. This glides in, swaps " ..
			"shoulders once and glides back. It uses one of Blizzard's experimental camera settings: trying it " ..
			"agrees to that, and your own camera settings come back after." },
	-- (Emote Vision in Teleport's place, the user's pick 2026-11-20: Teleport
	-- on the shelf.)
	{ key = "emote", label = "Emote Vision", icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", group = "vis",
		tip = "Other players' emotes show as film dialogue over their heads." },
}
-- The shelf's groups, the settings hubs, each in its hub's band color
-- (Options.lua's HUBS); a group with nothing to play is left out.
local SHELF_GROUPS = {
	{ key = "atmo", label = "Atmosphere", color = { 0.65, 0.45, 0.9 } },
	{ key = "cam", label = "Cameras", color = { 0.35, 0.6, 0.9 } },
	{ key = "vis", label = "Visions", color = { 0.85, 0.3, 0.25 } },
	{ key = "ui", label = "Interface", color = { 0.35, 0.7, 0.45 } },
	{ key = "style", label = "Style", color = { 0.85, 0.55, 0.25 } },
}
-- The shelf's tiles besides the row's: only what plays (each feature's own
-- Test, ShowMe.lua). Tips one sentence: they're translated.
local SHELF_MORE = {
	{ key = "weather", label = "Weather", icon = "Interface\\Icons\\Spell_Frost_IceStorm", group = "atmo",
		tip = "Rain, snow and dust drift across the screen to match the zone's weather." },
	{ key = "timeTitle", label = "Time of day title", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", group = "vis",
		tip = "A title card as dusk or dawn comes in." },
	{ key = "audio", label = "Audio", icon = "Interface\\Icons\\INV_Misc_Drum_01", group = "atmo",
		tip = "Music fades in as a camera starts in CineMode, and out as your UI returns." },
	{ key = "afk", label = "AFK Cam", icon = "Interface\\Icons\\Spell_Nature_Sleep", group = "cam",
		tip = "Go AFK and the camera sweeps slowly around you." },
	{ key = "questCam", label = "Quest Cam", icon = "Interface\\Icons\\INV_Misc_Note_01", group = "cam",
		tip = "The camera frames you and the quest giver as you talk, as in a cutscene." },
	{ key = "flight", label = "Flight Cam", icon = "Interface\\Icons\\Ability_Hunter_EagleEye", group = "cam",
		tip = "Wide, slow shots of the land as you fly a flight path." },
	{ key = "cozy", label = "Cozy Cam", icon = "Interface\\Icons\\Spell_Fire_Fire", group = "cam",
		tip = "Sit by a campfire and the camera settles in close." },
	{ key = "vista", label = "Vista Cam", icon = "Interface\\Icons\\INV_Misc_Spyglass_02", group = "cam",
		tip = "Stare at a view and the camera pulls back to take it in." },
	{ key = "fish", label = "Fish Cam", icon = "Interface\\Icons\\Trade_Fishing", group = "cam",
		tip = "The camera moves in on your bobber while you fish." },
	{ key = "deathCam", label = "Death Cam", icon = "Interface\\Icons\\Ability_Rogue_FeignDeath", group = "cam",
		tip = "The camera pulls up and away from you when you die." },
	{ key = "walk", label = "RP Walk Cam", icon = "Interface\\Icons\\INV_Boots_01", group = "cam",
		tip = "A walking shot as you auto-walk through a town." },
	{ key = "run", label = "Auto-run Cam", icon = "Interface\\Icons\\Ability_Rogue_Sprint", group = "cam",
		tip = "A tracking shot that follows you as you auto-run." },
	{ key = "heal", label = "Heal Vision", icon = "Interface\\Icons\\Spell_Holy_FlashHeal", group = "vis",
		tip = "Party and raid frames show only who needs healing, so a healer can keep the UI hidden." },
	{ key = "damage", label = "Damage Vision", icon = "Interface\\Icons\\Ability_Warrior_Rampage", group = "vis",
		tip = "Your race with the top of the damage meter, live through a fight." },
	{ key = "recap", label = "Fight Recap", icon = "Interface\\Icons\\INV_Scroll_03", group = "vis",
		tip = "After a boss or a dungeon, a short card of who did what." },
	{ key = "deathVision", label = "Death Vision", icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", group = "vis",
		tip = "The world dims and goes cold while you're dead." },
	{ key = "roll", label = "Roll Vision", icon = "Interface\\Icons\\INV_Misc_Dice_01", group = "vis",
		tip = "Group loot rolls in a window: who picked what." },
	{ key = "tele", label = "Teleport", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", group = "vis",
		tip = "As you cast your Hearthstone or a teleport, a portal opens around you and the world fades " ..
			"out as you leave." },
	{ key = "cards", label = "Card Vision", icon = "Interface\\Icons\\INV_Misc_Book_09", group = "vis",
		tip = "Title cards for the moments of your day: a new zone, a level, a fight." },
	{ key = "plates", label = "Nameplates", icon = "Interface\\Icons\\Ability_Hunter_SniperShot", group = "ui",
		tip = "Nameplates that show only for what matters: your target, a mob on you, a friend in need." },
	{ key = "bubbles", label = "Chat Bubbles", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", group = "ui",
		tip = "Chat bubbles restyled, so talk stays readable with your UI gone." },
	{ key = "combatText", label = "Combat Text", icon = "Interface\\Icons\\Ability_Warrior_Riposte", group = "style",
		tip = "Damage and heal numbers in a cleaner style." },
	-- (the Mouseover page's own icon, a pointing hand)
	{ key = "mouseover", label = "Mouseover", icon = "Interface\\Cursor\\Point", group = "ui",
		tip = "Point at where a faded frame lives and it comes back, with its group." },
	{ key = "cdflash", label = "Cooldown Flash", icon = "Interface\\Icons\\Spell_Nature_TimeStop", group = "ui",
		tip = "A spell's icon flashes in the middle of the screen as it comes off cooldown." },
	{ key = "speech", label = "Speech", icon = "Interface\\Icons\\Ability_Warrior_RallyingCry", group = "ui",
		tip = "What's said behind you shows as a bubble, so you don't miss it." },
}
-- While one plays, the notice at the top of the screen says what it is in a
-- line (the plan's, docs/design/welcome-shelf.md; others: their tip's first
-- sentence).
local NOTICE_LINES = {
	fadeUI = "Your UI fades away between fights and comes back when you need it.",
	bars = "Black bars at the top and bottom, as in a film.",
	tint = "A color wash that follows the time of day, the zone and the weather.",
	afk = "Go AFK and the camera sweeps slowly around you.",
	shoulder = "The camera sits over your shoulder, with you to one side.",
	vitals = "The screen's edges close in as your health drops.",
	emote = "Other players' emotes show as film dialogue over their heads.",
	cards = "Title cards for the moments of your day: a new zone, a level, a fight.",
	tele = "A portal opens as you hearth or teleport, and the world fades out.",
}
-- The tour, in the plan's order: the highlights one after another. Emote
-- Vision's card stays up till it goes (up to 60 s): 15 here. The Shoulder Cam
-- only once you've said yes to its experimental setting: a tour mustn't say
-- it for you. (Quest and Damage Vision left out on purpose: few use them.)
local TOUR = { { key = "fadeUI" }, { key = "bars" }, { key = "tint" }, { key = "afk" }, { key = "shoulder" },
	{ key = "vitals" }, { key = "emote", seconds = 15 }, { key = "cards" }, { key = "tele" } }
-- The features with nothing to play: a line of links under the grid, "Also
-- in Cinematic", each opening its settings page (by its English name, as
-- ns.OpenOptions takes it) over the welcome window, closing back to it. The
-- one waiting for a demo of its own (Skyriding Cam) is here till it has one.
local SHELF_LINKS = {
	{ page = "Graphics+", label = "Graphics Boost", group = "atmo",
		tip = "Raises the game's view distance and shadows in quiet moments, and lowers them for a fight." },
	{ page = "Skyriding Cam", label = "Skyriding Cam", group = "cam",
		tip = "Pulls the camera back and widens the view as you pick up speed skyriding." },
	{ page = "Camera Scripts", label = "Camera Scripts", group = "cam",
		tip = "Chains of camera moves you write and play back." },
	{ page = "My Shots", label = "My Shots", group = "cam",
		tip = "Your own saved camera shots, played from a key or a wheel." },
	{ page = "Quest Vision", label = "Quest Vision", group = "vis",
		tip = "Quest mobs keep their nameplates, with a quest mark." },
	{ page = "Duel Vision", label = "Duel Vision", group = "vis",
		tip = "In CineMode, the nameplates of two players dueling near you show." },
	{ page = "Tooltips", label = "Tooltips", group = "ui", tip = "Which parts of a tooltip show, and where it sits." },
	{ page = "Cursor Hide", label = "Cursor Hide", group = "ui", tip = "Hides the mouse cursor when you aren't using it." },
	{ page = "Style Themes", label = "Themes", group = "style", tip = "One look for your whole UI: fonts, borders, colors." },
	{ page = "Unit Style", label = "Unit Frames Style", group = "style",
		tip = "Restyles your player, target and focus frames." },
	{ page = "Nameplate Style", label = "Nameplate Style", group = "style",
		tip = "Shapes, bars and cast bars for nameplates." },
	{ page = "Your wheels", label = "Wheels", group = "qol",
		tip = "Radial menus on a key: cameras, menus, raid markers, Visions." },
	{ page = "Keyboard Map", label = "Keyboard Map", group = "qol",
		tip = "Your keybinds drawn on a keyboard, to see what's free." },
	{ page = "Fishing", label = "Fishing", group = "qol", tip = "Fish with one key, with louder splashes." },
	{ page = "Hunter", label = "Hunter", group = "qol", tip = "Pet and ammo reminders for hunters." },
}
-- Each demo by key (the notice's name and line).
local DEMO_BY_KEY = {}
for _, demo in ipairs(DEMO_ROW) do DEMO_BY_KEY[demo.key] = demo end
for _, demo in ipairs(SHELF_MORE) do DEMO_BY_KEY[demo.key] = demo end
-- The steps for keys (a tour), the Shoulder Cam left out until it's had its yes.
local function TourSteps(steps)
	local out = {}
	for _, step in ipairs(steps) do
		out[#out + 1] = { key = step.key, seconds = step.seconds,
			skip = step.key == "shoulder" and not (ns.db and ns.db.shoulderCamNoticed) or nil }
	end
	return out
end

-- The notice: what's playing, at the top of the screen, over the faded window
-- and the world: its name, "n of N" in a tour, its line, and Stop. Not a
-- child of UIParent: the Fading UI demo fades all of that.
local notice
local function UpdateNotice()
	-- (not "a and f()": that keeps only the first of its returns)
	local key, n, total
	if ns.ShowMeNow then key, n, total = ns.ShowMeNow() end
	local demo = key and DEMO_BY_KEY[key]
	if not (demo and window and window:IsShown()) then
		if notice then notice:Hide() end
		return
	end
	if not notice then
		notice = CreateFrame("Frame", nil, nil, BackdropTemplateMixin and "BackdropTemplate")
		notice:SetFrameStrata("FULLSCREEN_DIALOG")
		notice:SetPoint("TOP", UIParent, "TOP", 0, -60)
		Flat(notice, BG, GOLD)
		notice.title = Text(notice, "GameFontNormal", "", WHITE)
		notice.title:SetPoint("TOPLEFT", 14, -10)
		notice.line = Text(notice, "GameFontHighlightSmall", "", SOFT)
		notice.line:SetPoint("TOPLEFT", notice.title, "BOTTOMLEFT", 0, -5)
		notice.stop = FlatButton(notice, L["Stop"], "box", function() ns.StopShowMe() end)
		notice.stop:SetSize(72, 24)
		notice.stop:SetPoint("RIGHT", -12, 0)
	end
	notice:SetScale(UIParent:GetEffectiveScale())
	local name = "|cffffd100" .. L[demo.label] .. "|r"
	notice.title:SetText(n and (L["Playing %s, %d of %d"]):format(name, n, total) or (L["Playing %s"]):format(name))
	local line = NOTICE_LINES[key] and L[NOTICE_LINES[key]] or (L[demo.tip]:match("^(.-[%.!])%s") or L[demo.tip])
	notice.line:SetWidth(0)
	notice.line:SetText(line)
	local w = math.max(notice.title:GetStringWidth(), math.min(460, notice.line:GetStringWidth()))
	notice.line:SetWidth(w)
	notice:SetSize(w + 14 + 12 + 72 + 16, notice.title:GetStringHeight() + notice.line:GetStringHeight() + 25)
	notice:Show()
end

local OpenPageFromWelcome -- (below, with the window's close: a settings page over it, and back)
local DEMO_ROW_H = 74
local SHELF_H = 222   -- the shelf open: the grid scrolls inside it
local TILE_H, TILE_GAP = 38, 6
local function BuildDemoRow(page, width)
	local row = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate")
	row:SetSize(width, DEMO_ROW_H)
	Flat(row, BG)
	local head = Text(row, "GameFontNormalSmall", L["Feature List: Click to preview"], GOLD)
	head:SetPoint("TOPLEFT", 12, -9)
	-- (On the right, only in a fight: why they're all grey. The header says
	-- to click, 2026-11-20: "Click one to see it for a few seconds" dropped.)
	local hint = Text(row, "GameFontHighlightSmall", "", DIM)
	hint:SetJustifyH("RIGHT")
	hint:SetPoint("TOPRIGHT", -12, -9)
	-- Watch the tour, on the right of the header: there before the shelf's
	-- open (Stop the tour while it plays; gone in a fight, the hint says why).
	local tourButton = FlatButton(row, L["Watch the tour \194\183 1\194\189 min"], nil, function()
		if ns.ShowMeTouring and ns.ShowMeTouring() then
			ns.StopShowMe()
		elseif ns.ShowMeTour then
			ns.ShowMeTour(TourSteps(TOUR), window)
		end
	end)
	tourButton:SetPoint("TOPRIGHT", -8, -4)
	Color(tourButton.text, GOLD)
	tourButton:SetScript("OnEnter", function(self)
		Color(self.text, WHITE)
		about:SetText("|cffffd100" .. L["Watch the tour"] .. "|r   " ..
			L["The highlights one after another: your UI fading, the letterbox and tint, a camera, the Shoulder Cam if " ..
			"you've said yes to it, Vitals, Emote and Card Visions, a teleport. Stop any time."])
	end)
	tourButton:SetScript("OnLeave", function(self)
		Color(self.text, GOLD)
		Describe(levelOf[Active()])
	end)
	local list, all = {}, {}
	for _, demo in ipairs(DEMO_ROW) do
		if ns.ShowMeAvailable and ns.ShowMeAvailable(demo.key) then
			list[#list + 1] = demo
			all[#all + 1] = demo
		end
	end
	for _, demo in ipairs(SHELF_MORE) do
		if ns.ShowMeAvailable and ns.ShowMeAvailable(demo.key) then all[#all + 1] = demo end
	end
	-- (Saved for the account: open or closed, the last group. Not a setting.)
	local saved = type(ns.db.welcomeShelf) == "table" and ns.db.welcomeShelf or {}
	ns.db.welcomeShelf = saved
	-- Under the buttons, a line of settings. On the left, Start in CineMode:
	-- the level's the tags are for (hovered, else picked), a tick to change
	-- for the one picked (a hovered card has the mouse: its own is only
	-- shown). None hovered or picked: dim and empty till one is (hidden, the
	-- strength sat alone on the right).
	local strengthH = 24
	local start = CreateFrame("Button", nil, row, BackdropTemplateMixin and "BackdropTemplate")
	start:SetSize(14, 14)
	start:SetPoint("BOTTOMLEFT", 12, 10)
	Flat(start, BG, EDGE)
	start.tick = start:CreateTexture(nil, "ARTWORK")
	start.tick:SetColorTexture(unpack(GOLD))
	start.tick:SetPoint("TOPLEFT", 3, -3)
	start.tick:SetPoint("BOTTOMRIGHT", -3, 3)
	start.label = Text(start, "GameFontHighlightSmall", L["Start in CineMode"], SOFT)
	start.label:SetPoint("LEFT", start, "RIGHT", 8, 0)
	-- (the words click too)
	start:SetHitRectInsets(0, -(start.label:GetStringWidth() + 8), -4, -4)
	local startFor -- (the profile it shows: nil for none)
	local function StartOn()
		if not startFor then return false end
		if startFor == Active() then return ns.db.fadeUI ~= false end
		return ns.ProfileSettings(startFor).fadeUI ~= false
	end
	local function ShowStart()
		start.tick:SetShown(StartOn())
		Color(start.label, startFor and SOFT or DIM)
	end
	start:SetScript("OnClick", function()
		if startFor ~= Active() then return end
		ns.db.fadeUI = not StartOn()
		if ns.RestartTimers then ns.RestartTimers() end
		-- (and the Fading UI button's tag, which goes by it)
		row:Update(nil, true)
	end)
	start:SetScript("OnEnter", function(self)
		if startFor then self:SetBackdropBorderColor(unpack(LIT)) end
		about:SetText("|cffffd100" .. L["Start in CineMode"] .. "|r   " ..
			L["On: CineMode comes in by itself between fights, fading your UI. Off: your UI stays as it is, " ..
			"unless a camera brings CineMode on."] .. (startFor and "" or " " .. L["Pick a profile first."]))
	end)
	start:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(unpack(EDGE))
		Describe(levelOf[Active()])
	end)
	-- On the right, with the Tint demo: the tint's strength (the
	-- profile's). Dragging it plays the Tint demo, or keeps
	-- it playing, so you see the strength you pick.
	if ns.ShowMeAvailable and ns.ShowMeAvailable("tint") and ns.db then
		local value = Text(row, "GameFontHighlightSmall", "", SOFT)
		value:SetJustifyH("LEFT")
		value:SetWidth(40)
		value:SetPoint("BOTTOMRIGHT", -12, 12)
		local slider = CreateFrame("Slider", nil, row)
		slider:SetOrientation("HORIZONTAL")
		slider:SetHeight(14)
		-- (short: a full-width line made small changes look like nothing)
		slider:SetWidth(200)
		slider:SetPoint("RIGHT", value, "LEFT", -10, 0)
		local label = Text(row, "GameFontHighlightSmall", L["Tint strength"], SOFT)
		label:SetPoint("RIGHT", slider, "LEFT", -12, 0)
		local track = slider:CreateTexture(nil, "BACKGROUND")
		track:SetColorTexture(unpack(EDGE))
		track:SetHeight(4)
		track:SetPoint("LEFT")
		track:SetPoint("RIGHT")
		local thumb = slider:CreateTexture(nil, "OVERLAY")
		thumb:SetColorTexture(unpack(GOLD))
		thumb:SetSize(8, 14)
		slider:SetThumbTexture(thumb)
		slider:SetMinMaxValues(5, 100)
		slider:SetValueStep(1)
		if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
		slider:EnableMouseWheel(true)
		local setting -- (set from the setting: not a drag, so no demo)
		local function Show()
			setting = true
			slider:SetValue(math.floor((ns.db.tintStrength or 1) * 100 + 0.5))
			setting = false
			value:SetText(("%d%%"):format(slider:GetValue()))
		end
		slider:SetScript("OnValueChanged", function(_, v)
			v = math.floor(v + 0.5)
			value:SetText(("%d%%"):format(v))
			if setting then return end
			ns.db.tintStrength = v / 100
			if ns.RefreshTint then ns.RefreshTint() end
			if ns.ShowMeRunning("tint") then
				ns.ShowMeKeep("tint", 3)
			elseif not ns.ShowMeBlocked("tint", true) then
				ns.ShowMe("tint", window, true)
			end
		end)
		slider:SetScript("OnMouseWheel", function(self, delta)
			self:SetValue(math.max(5, math.min(100, self:GetValue() + delta)))
		end)
		slider:SetScript("OnEnter", function()
			thumb:SetColorTexture(unpack(WHITE))
			about:SetText("|cffffd100" .. L["Tint strength"] .. "|r   " ..
				L["How strongly the tint colors the world."])
		end)
		slider:SetScript("OnLeave", function()
			thumb:SetColorTexture(unpack(GOLD))
			Describe(levelOf[Active()])
		end)
		row.ShowStrength = Show
		Show()
	end
	local closedH = DEMO_ROW_H + strengthH
	row:SetHeight(closedH)
	local gap = 6
	-- (the See all button narrower: two short words, no icon)
	local moreW = 74
	local buttonW = math.floor((width - 24 - moreW - gap * #list) / math.max(1, #list))
	local buttons = {}
	local show -- (the level the tags are for: Describe's, nil for none)
	local turned = {} -- (features Turned on in the level picked: key -> true, till another's picked)
	-- The level the Turn on buttons are for: the one picked, none hovered (a
	-- hovered card's tags are only shown), not Blank Slate (everything off on
	-- purpose: no Customize either).
	local function TurnOnLevel()
		local active = Active()
		local level = active and levelOf[active]
		if not level or show ~= level or level.noCustomize then return nil end
		return active
	end
	-- One demo's button: the row's, or a tile on the shelf (the same, with
	-- Turn on). Its icon, rounded as the level cards' are; its name and when
	-- it shows beside it.
	local function DemoButton(parent, demo, w)
		local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
		b:SetSize(w, TILE_H)
		Flat(b, RAISED, EDGE)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(24, 24)
		b.icon:SetPoint("LEFT", 6, 0)
		b.icon:SetTexture(demo.icon)
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		Rounded(b, b.icon)
		b.name = Text(b, "GameFontHighlightSmall", L[demo.label], SOFT, w - 38)
		b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, 0)
		b.name:SetWordWrap(false)
		b.tag = Text(b, "GameFontDisableSmall", "", DIM, w - 38)
		b.tag:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
		b.tag:SetWordWrap(false)
		b:SetScript("OnClick", function() ns.ShowMe(demo.key, window, true) end)
		b:SetScript("OnEnter", function(self)
			if self:IsEnabled() then self:SetBackdropBorderColor(unpack(LIT)) end
			-- (and when it shows in the level the tags are for)
			local when
			if show then
				local _, _, sentence = ns.ShowMeWhen(demo.key, show.profile)
				if turned[demo.key] and TurnOnLevel() then sentence = L["You turned it on."] end
				when = sentence and "\n|cffffd100" .. (L["In %s"]):format(show.label) .. ":|r " .. sentence
			end
			about:SetText("|cffffd100" .. L[demo.label] .. "|r   " .. L[demo.tip] .. (when or ""))
			-- (Why it can't play, on its own: not in a fight, which the shelf
			-- and the row's hint say for all of them at once.)
			local why = not InCombatLockdown() and ns.ShowMeBlocked(demo.key, true)
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
		b.width = w
		buttons[#buttons + 1] = b
		return b
	end
	-- (A tile's Turn on: small, on its right, the name narrower beside it.)
	local function TurnOnButton(b)
		local on = FlatButton(b, L["Turn on"], nil, function()
			if ns.ShowMeTurnOn(b.demo.key) then
				turned[b.demo.key] = true
				row:Update(nil, true)
			end
		end)
		on:SetPoint("RIGHT", -4, 0)
		on:SetScript("OnEnter", function(self)
			Color(self.text, GOLD)
			local level = levelOf[Active()]
			about:SetText("|cffffd100" .. (L["Turn on %s"]):format(L[b.demo.label]) .. "|r   " ..
				(L["Adds it to %s, the profile you're trying."]):format(level and level.label or ""))
		end)
		on:SetScript("OnLeave", function(self)
			Color(self.text, DIM)
			Describe(levelOf[Active()])
		end)
		on:Hide()
		b.turnOn = on
	end
	for i, demo in ipairs(list) do
		local b = DemoButton(row, demo, buttonW)
		b:SetPoint("TOPLEFT", 12 + (i - 1) * (buttonW + gap), -26)
	end

	-- See all: the row's last slot, dashed gold (an edge of gold dashes), its
	-- count and "n more" under it; open, Fewer.
	local more = CreateFrame("Button", nil, row, BackdropTemplateMixin and "BackdropTemplate")
	more:SetSize(moreW, TILE_H)
	more:SetPoint("TOPLEFT", 12 + #list * (buttonW + gap), -26)
	Flat(more, BG, BG)
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local across = side == "TOP" or side == "BOTTOM"
		local steps = math.floor((across and moreW or TILE_H) / 8)
		for n = 0, steps - 1 do
			local dash = more:CreateTexture(nil, "BORDER")
			dash:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.7)
			if across then
				dash:SetSize(4, 1)
				dash:SetPoint(side .. "LEFT", n * 8 + 2, 0)
			else
				dash:SetSize(1, 4)
				dash:SetPoint("TOP" .. side, 0, -(n * 8 + 2))
			end
		end
	end
	more.name = Text(more, "GameFontHighlightSmall", "", GOLD, moreW - 8)
	more.name:SetJustifyH("CENTER")
	more.name:SetPoint("TOP", 0, -7)
	more.tag = Text(more, "GameFontDisableSmall", "", DIM, moreW - 8)
	more.tag:SetJustifyH("CENTER")
	more.tag:SetPoint("TOP", more.name, "BOTTOM", 0, -3)
	more:SetScript("OnEnter", function(self)
		self:SetBackdropColor(unpack(RAISED))
		about:SetText("|cffffd100" .. L["See all"] .. "|r   " ..
			L["Everything Cinematic can show you, by where you'll find it in the settings. Click any to see it."])
	end)
	more:SetScript("OnLeave", function(self)
		self:SetBackdropColor(unpack(BG))
		Describe(levelOf[Active()])
	end)

	-- The shelf: the groups down the left (All, then each hub with something
	-- to play, in its color), a search box over the grid, the grid of tiles
	-- (a fixed height, scrolling). In a fight, one line in the search's place.
	local shelf = CreateFrame("Frame", nil, row)
	shelf:SetPoint("TOPLEFT", 12, -26 - TILE_H - 10)
	shelf:SetSize(width - 24, SHELF_H)
	shelf:Hide()
	local rule = shelf:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(unpack(EDGE))
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	local NAV_W = 132
	local groups, groupButtons = {}, {}
	local count = {}
	for _, demo in ipairs(all) do count[demo.group] = (count[demo.group] or 0) + 1 end
	groups[1] = { key = "all", label = "All", color = GOLD }
	for _, group in ipairs(SHELF_GROUPS) do
		if count[group.key] then groups[#groups + 1] = group end
	end
	count.all = #all
	local groupOf = {}
	for _, group in ipairs(groups) do groupOf[group.key] = group end
	if not groupOf[saved.group or ""] then saved.group = "all" end
	local Layout -- (below: the grid for the group picked or the words searched)
	for i, group in ipairs(groups) do
		local g = CreateFrame("Button", nil, shelf, BackdropTemplateMixin and "BackdropTemplate")
		g:SetSize(NAV_W, 24)
		g:SetPoint("TOPLEFT", 0, -10 - (i - 1) * 26)
		Flat(g, BG, BG)
		local swatch = g:CreateTexture(nil, "ARTWORK")
		swatch:SetColorTexture(unpack(group.color))
		swatch:SetSize(3, 16)
		swatch:SetPoint("LEFT", 6, 0)
		g.label = Text(g, "GameFontHighlightSmall", L[group.label], SOFT)
		g.label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
		g.n = Text(g, "GameFontDisableSmall", tostring(count[group.key]), DIM)
		g.n:SetJustifyH("RIGHT")
		g.n:SetPoint("RIGHT", -8, 0)
		g:SetScript("OnClick", function()
			saved.group = group.key
			Layout()
		end)
		g:SetScript("OnEnter", function(self) if saved.group ~= group.key then self:SetBackdropColor(unpack(RAISED)) end end)
		g:SetScript("OnLeave", function(self) if saved.group ~= group.key then self:SetBackdropColor(unpack(BG)) end end)
		g.group = group
		groupButtons[i] = g
	end
	local gridX = NAV_W + 12
	local gridW = width - 24 - gridX
	-- (The search box: flat, a grey hint inside while empty.)
	-- (Play all, on the search's right: the tour for All, the group's tiles in
	-- turn for a group, or the ones found by a search. Stop the tour meanwhile.)
	local PLAY_W = 168
	local play = FlatButton(shelf, "", "box", function() end)
	play:SetSize(PLAY_W, 22)
	play:SetPoint("TOPRIGHT", 0, -10)
	local search = CreateFrame("EditBox", nil, shelf, BackdropTemplateMixin and "BackdropTemplate")
	search:SetSize(gridW - PLAY_W - 8, 22)
	search:SetPoint("TOPLEFT", gridX, -10)
	Flat(search, RAISED, EDGE)
	search:SetFontObject("GameFontHighlightSmall")
	search:SetTextInsets(8, 8, 0, 0)
	search:SetAutoFocus(false)
	search:SetMaxLetters(40)
	local searchHint = Text(search, "GameFontDisableSmall", L["Find a feature: fishing, duel, camera..."], DIM)
	searchHint:SetPoint("LEFT", 8, 0)
	search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	search:SetScript("OnTextChanged", function(self)
		searchHint:SetShown(self:GetText() == "")
		if Layout then Layout() end
	end)
	local fightLine = Text(shelf, "GameFontHighlightSmall", L["You're in a fight. The demos come back when it ends."], GOLD)
	fightLine:SetPoint("LEFT", search, "LEFT", 8, 0)
	fightLine:Hide()
	-- The grid: tiles 3 across (2 on a narrow window), each group's under its
	-- name when more than one shows; the wheel scrolls it, a thin thumb on
	-- its right says where.
	local scroll = CreateFrame("ScrollFrame", nil, shelf)
	scroll:SetPoint("TOPLEFT", gridX, -10 - 22 - 8)
	scroll:SetSize(gridW - 8, SHELF_H - 10 - 22 - 8 - 4)
	local grid = CreateFrame("Frame", nil, scroll)
	grid:SetSize(gridW - 8, 1)
	scroll:SetScrollChild(grid)
	local bar = shelf:CreateTexture(nil, "ARTWORK")
	bar:SetColorTexture(unpack(EDGE))
	bar:SetWidth(3)
	local function ScrollTo(y)
		local most = math.max(0, grid:GetHeight() - scroll:GetHeight())
		y = math.max(0, math.min(most, y))
		scroll:SetVerticalScroll(y)
		bar:SetShown(most > 0)
		if most > 0 then
			local viewH = scroll:GetHeight()
			local h = math.max(16, viewH * viewH / grid:GetHeight())
			bar:SetHeight(h)
			bar:ClearAllPoints()
			bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 8, -(viewH - h) * (y / most))
		end
	end
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		ScrollTo(scroll:GetVerticalScroll() - delta * (TILE_H + TILE_GAP))
	end)
	local cols = gridW >= 520 and 3 or 2
	local tileW = math.floor((gridW - 8 - TILE_GAP * (cols - 1)) / cols)
	local tiles, labels = {}, {}
	for _, demo in ipairs(all) do
		local b = DemoButton(grid, demo, tileW)
		if ns.ShowMeCanTurnOn and ns.ShowMeCanTurnOn(demo.key) then TurnOnButton(b) end
		b:Hide()
		tiles[#tiles + 1] = b
	end
	for _, group in ipairs(SHELF_GROUPS) do
		local label = Text(grid, "GameFontNormalSmall", L[group.label], group.color)
		label:Hide()
		labels[group.key] = label
	end
	local empty = Text(grid, "GameFontHighlightSmall", "", DIM, gridW - 16)
	empty:SetPoint("TOPLEFT", 4, -6)
	-- Also in Cinematic: a link per page, flowed across the grid's width.
	local alsoHead = Text(grid, "GameFontNormalSmall", L["Also in Cinematic:"], GOLD)
	alsoHead:Hide()
	local links = {}
	for _, link in ipairs(SHELF_LINKS) do
		local a = CreateFrame("Button", nil, grid)
		a.text = Text(a, "GameFontHighlightSmall", L[link.label], SOFT)
		a.text:SetPoint("LEFT")
		a:SetSize(a.text:GetStringWidth() + 2, 16)
		a:SetScript("OnClick", function() if OpenPageFromWelcome then OpenPageFromWelcome(link.page) end end)
		a:SetScript("OnEnter", function(self)
			Color(self.text, GOLD)
			about:SetText("|cffffd100" .. L[link.label] .. "|r   " .. L[link.tip] .. "\n" ..
				L["Nothing to play: click to open its settings. Closing them brings you back here."])
		end)
		a:SetScript("OnLeave", function(self)
			Color(self.text, SOFT)
			Describe(levelOf[Active()])
		end)
		a.link = link
		a:Hide()
		links[#links + 1] = a
	end
	-- (the words searched, in this language, against each tile's name and tip)
	local function Matches(demo, words)
		if words == "" then return saved.group == "all" or demo.group == saved.group end
		return (L[demo.label] .. " " .. L[demo.tip]):lower():find(words, 1, true) ~= nil
	end
	function Layout()
		local words = (search:GetText() or ""):match("^%s*(.-)%s*$"):lower()
		for _, g in ipairs(groupButtons) do
			local on = words == "" and saved.group == g.group.key
			g:SetBackdropColor(unpack(on and RAISED or BG))
			Color(g.label, on and WHITE or SOFT)
		end
		for _, label in pairs(labels) do label:Hide() end
		local y, shown = 0, 0
		local several = words ~= "" or saved.group == "all"
		for _, group in ipairs(SHELF_GROUPS) do
			local n = 0
			for _, b in ipairs(tiles) do
				if b.demo.group == group.key and Matches(b.demo, words) then
					if n == 0 and several then
						local label = labels[group.key]
						label:ClearAllPoints()
						label:SetPoint("TOPLEFT", 2, -y - 2)
						label:Show()
						y = y + 18
					end
					b:ClearAllPoints()
					b:SetPoint("TOPLEFT", (n % cols) * (tileW + TILE_GAP), -y - math.floor(n / cols) * (TILE_H + TILE_GAP))
					b:Show()
					n = n + 1
				end
			end
			for _, b in ipairs(tiles) do
				if b.demo.group == group.key and not Matches(b.demo, words) then b:Hide() end
			end
			if n > 0 then
				y = y + math.ceil(n / cols) * (TILE_H + TILE_GAP) + 4
				shown = shown + n
			end
		end
		-- (the links that match, after the tiles; pages this client has)
		alsoHead:Hide()
		local x, linkCount = 0, 0
		for _, a in ipairs(links) do
			local fits = Matches(a.link, words) and (not ns.HasOptionsPage or ns.HasOptionsPage(a.link.page))
			a:SetShown(fits and true or false)
			if fits then
				if linkCount == 0 then
					y = y + (shown > 0 and 6 or 24)
					alsoHead:ClearAllPoints()
					alsoHead:SetPoint("TOPLEFT", 2, -y)
					alsoHead:Show()
					x = alsoHead:GetStringWidth() + 10
				end
				if x + a:GetWidth() > gridW - 12 then
					x, y = 2, y + 18
				end
				a:ClearAllPoints()
				a:SetPoint("TOPLEFT", x, -y)
				x = x + a:GetWidth() + 14
				linkCount = linkCount + 1
			end
		end
		if linkCount > 0 then y = y + 22 end
		empty:SetText(shown > 0 and "" or linkCount > 0 and L["Nothing to play for that: it's a setting, below."]
			or (L["Nothing called \"%s\" plays here."]):format(search:GetText() or ""))
		grid:SetHeight(math.max(1, y))
		ScrollTo(0)
		if row.Update then row:Update(nil, true) end
	end

	-- (The notice follows every demo, the window's row shown or not.)
	if ns.ShowMeListen then ns.ShowMeListen(UpdateNotice) end
	play:SetScript("OnClick", function()
		if ns.ShowMeTouring and ns.ShowMeTouring() then
			ns.StopShowMe()
			return
		end
		local words = (search:GetText() or ""):match("^%s*(.-)%s*$")
		if words == "" and saved.group == "all" then
			ns.ShowMeTour(TourSteps(TOUR), window)
			return
		end
		local steps = {}
		for _, b in ipairs(tiles) do
			if b:IsShown() then steps[#steps + 1] = { key = b.demo.key } end
		end
		ns.ShowMeTour(TourSteps(steps), window)
	end)
	play:SetScript("OnEnter", function(self)
		if self:IsEnabled() then self:SetBackdropBorderColor(unpack(LIT)) Color(self.text, WHITE) end
		about:SetText("|cffffd100" .. self.text:GetText() .. "|r   " ..
			L["Plays each in turn, a few seconds each. Stop any time."])
	end)
	play:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(unpack(EDGE))
		Color(self.text, SOFT)
		Describe(levelOf[Active()])
	end)

	local function Paint(b)
		local key = b.demo.key
		local running = ns.ShowMeRunning(key)
		local blocked = not running and ns.ShowMeBlocked(key, true)
		b:SetEnabled(not blocked)
		b.name:SetText(running and L["Stop"] or L[b.demo.label])
		Color(b.name, blocked and DIM or running and GOLD or SOFT)
		b.icon:SetDesaturated(blocked and true or false)
		b.icon:SetAlpha(blocked and 0.5 or 1)
		b:SetBackdropBorderColor(unpack(running and GOLD or EDGE))
		-- (when it shows in that level: In CineMode, 4 scenes, Off...; turned
		-- on here: says so)
		local tag, has = nil, nil
		local level = TurnOnLevel()
		if level and turned[key] then
			tag, has = L["On: you turned it on"], true
		elseif show then
			tag, has = ns.ShowMeWhen(key, show.profile)
		end
		b.tag:SetText(tag or "")
		if tag then Color(b.tag, has and GOLD or DIM) end
		-- (Turn on: for the level picked when it hasn't it, not mid-demo or in a fight)
		if b.turnOn then
			local offer = level ~= nil and tag ~= nil and not has and not running and not InCombatLockdown()
			b.turnOn:SetShown(offer)
			local w = b.width - 38 - (offer and b.turnOn:GetWidth() + 8 or 0)
			b.name:SetWidth(w)
			b.tag:SetWidth(w)
		end
	end
	-- keep: the same level as last time (a demo started or ended, a fight).
	function row:Update(level, keep)
		if not keep then show = level end
		startFor = show and (show.profile or ns.DEFAULT_PROFILE) or nil
		ShowStart()
		local fight = InCombatLockdown()
		hint:SetText(fight and L["In a fight: demos wait till it ends."] or "")
		fightLine:SetShown(fight)
		search:SetShown(not fight)
		-- (the tour buttons: Stop the tour while one plays; none in a fight)
		local touring = ns.ShowMeTouring and ns.ShowMeTouring()
		tourButton:SetShown(not fight)
		tourButton:SetLabel(touring and L["Stop the tour"] or L["Watch the tour \194\183 1\194\189 min"])
		play:SetShown(not fight)
		local words = (search:GetText() or ""):match("^%s*(.-)%s*$")
		local group = groupOf[saved.group]
		play:SetLabel(touring and L["Stop the tour"] or words ~= "" and L["Play these"]
			or (not group or group.key == "all") and L["Watch the tour"] or (L["Play all in %s"]):format(L[group.label]))
		UpdateNotice()
		for _, b in ipairs(buttons) do
			if b:IsShown() then Paint(b) end
		end
	end
	-- A new level picked: what was turned on was that one's.
	function row:LevelPicked()
		wipe(turned)
	end
	-- Open or closed (saved): the row grows by the shelf, the window with it
	-- (row.OnHeight, the levels page's).
	local function SetOpen(open)
		local was = shelf:IsShown()
		shelf:SetShown(open)
		saved.open = open or nil
		more.name:SetText(open and L["Fewer"] or (L["See all %d"]):format(#all))
		more.tag:SetText(open and "" or (L["%d more"]):format(#all - #list))
		local h = closedH + (open and SHELF_H + 10 or 0)
		row:SetHeight(h)
		if open then
			if not search:HasFocus() then search:SetText("") end
			Layout()
		else
			search:ClearFocus()
		end
		if was ~= open and row.OnHeight then row.OnHeight(open and SHELF_H + 10 or -(SHELF_H + 10)) end
		row:Update(nil, true)
	end
	more:SetScript("OnClick", function() SetOpen(not shelf:IsShown()) end)
	row.SetShelfOpen = SetOpen
	row.ShelfTiles = function() return tiles end
	-- (for Dev/ShelfTest.lua: the tour's buttons, its keys, the notice, the links)
	row.TourButton, row.PlayButton, row.ShelfLinks = tourButton, play, links
	row.TourKeys = function()
		local keys = {}
		for _, step in ipairs(TourSteps(TOUR)) do
			if not step.skip and ns.ShowMeAvailable(step.key) and not ns.ShowMeBlocked(step.key, true) then
				keys[#keys + 1] = step.key
			end
		end
		return keys
	end
	row.Notice = function() return notice end
	SetOpen(saved.open == true)

	local function Recheck() if row:IsVisible() then row:Update(nil, true) end end
	if ns.ShowMeListen then ns.ShowMeListen(Recheck) end
	row:RegisterEvent("PLAYER_REGEN_DISABLED")
	row:RegisterEvent("PLAYER_REGEN_ENABLED")
	-- (PLAYER_REGEN_DISABLED comes before the lock: a moment on, the fight's begun)
	row:SetScript("OnEvent", function() C_Timer.After(0.1, Recheck) end)
	row:SetScript("OnShow", function()
		-- (the strength changed on the Tint page meanwhile)
		if row.ShowStrength then row.ShowStrength() end
		Recheck()
	end)
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
	-- (All cards as tall as the one with the longest line, in this language,
	-- so no line runs into a card's bottom edge.)
	local cardH = 124
	for i, level in ipairs(LEVELS) do
		local profile = byName[level.profile or ns.DEFAULT_PROFILE]
		if profile then
			local card = Card(page, profile, level)
			card:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", (i - 1) * (CARD_W + GAP), -18)
			cards[profile.name], levelOf[profile.name] = card, level
			cardH = math.max(cardH, math.ceil(card.need))
		end
	end
	for _, card in pairs(cards) do card:SetHeight(cardH) end

	-- See it first, then the description box, under the cards.
	local rowH = 0
	if ns.ShowMe then
		demoRow = BuildDemoRow(page, WIDTH - 2 * PAD)
		demoRow:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -18 - cardH - 12)
		rowH = demoRow:GetHeight() + 12
	end
	local box = CreateFrame("Frame", nil, page, BackdropTemplateMixin and "BackdropTemplate")
	-- (under the row: it grows as See all opens its shelf, the window with it)
	if demoRow then
		box:SetPoint("TOPLEFT", demoRow, "BOTTOMLEFT", 0, -12)
		demoRow.OnHeight = function(delta)
			page.height = page.height + delta
			if window and window.page == 1 then window:SetHeight(page.height) end
		end
	else
		box:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -18 - cardH - 12)
	end
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
	page.height = 380 + boxH - 56 + rowH + cardH - 124
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
			GameTooltip:SetText(L["Rebuilds this layout, undoing your Edit Mode changes to it."], 1, 1, 1, 1, true)
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
	-- (Taller, to fill the room it has: the Profiles page's Customize tab
	-- reaches the bottom of the window. Never less than it's made.)
	function holder:SetPanelHeight(height)
		height = math.max(360, math.floor(height))
		if height == PANEL_H then return end
		PANEL_H = height
		holder:SetHeight(height)
		panel:SetHeight(height)
		if shown then Show(shown.index, true) end
	end
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
local toSettings, afterClose

-- The shelf's page links: the welcome window closes onto that settings page
-- (no chat line, as for Settings), with a Back button over its top-left;
-- Back, or closing the settings any way, brings the welcome window back.
local backButton, backTo
function OpenPageFromWelcome(page)
	if InCombatLockdown() or not window then return end
	local panel = SettingsPanel or InterfaceOptionsFrame
	toSettings = true
	window:Hide()
	ns.OpenOptions(page)
	if not (panel and ns.Flag(panel:IsShown())) then
		ns.ShowWelcome() -- (it didn't open: straight back)
		return
	end
	if not backButton then
		backButton = FlatButton(nil, L["< Back to the welcome window"], "box", function()
			if panel.Close then panel:Close(true) else HideUIPanel(panel) end
		end)
		backButton:SetFrameStrata("FULLSCREEN_DIALOG")
		backButton:SetSize(backButton.text:GetStringWidth() + 28, 26)
		panel:HookScript("OnHide", function()
			if not backTo then return end
			backTo = false
			backButton:Hide()
			C_Timer.After(0, function() if not InCombatLockdown() then ns.ShowWelcome() end end)
		end)
	end
	backButton:SetScale(UIParent:GetEffectiveScale()) -- (no parent: the UI's scale, as the test box takes it)
	backButton:ClearAllPoints()
	backButton:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 6)
	backTo = true
	backButton:Show()
end
local function OnHide()
	-- (A window waiting its turn, the conflicts one: opened once this has
	-- closed, a moment on so See Profile's settings open first.)
	if afterClose then
		local fn = afterClose
		afterClose = nil
		C_Timer.After(0.2, function() fn() end)
	end
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
	-- (kept on the screen: taller with the shelf open, at a big UI scale its top went off it)
	window:SetClampedToScreen(true)
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
	-- Done on the last. Beside it Settings (Cinematic's main page) and, quietly, Done (or
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
	-- (Settings: Cinematic's main page, on its first tab, from any step.)
	settings = FlatButton(window, L["Settings"], "box", function()
		toSettings = true
		window:Hide()
		if ns.OpenCineModeOverview then ns.OpenCineModeOverview() else ns.OpenOptions() end
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

-- Runs fn once the welcome window closes (Customize included), instead of
-- over it. False when it isn't open: the caller goes ahead now.
function ns.AfterWelcome(fn)
	if not (window and window:IsShown()) then return false end
	afterClose = fn
	return true
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
