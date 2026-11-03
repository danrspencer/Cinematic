-- Emote Vision: when someone buffs you, brings you back to life or emotes
-- at you, a small card shows who it was and what they did, with a few
-- emotes to answer in one click (/thank, /bow, the same emote back...). It
-- never shows in a fight: a moment from one waits for the fight to end and
-- is dropped if it's grown old by then. One card at a time, the rest
-- queued; once per person a minute, so a raid's buffer doesn't flood you.
-- Its look follows Visions Style (font, outline, shadow, border). Its page
-- is at the bottom.

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.emoteVision = false           -- at all (its page's switch)
DEFAULTS.emoteVisionAlways = false     -- its Show in row's Always: everywhere
DEFAULTS.emoteVisionBuffs = true       -- someone buffs you (a buff of a minute or more)
DEFAULTS.emoteVisionRes = true         -- someone brings you back to life
DEFAULTS.emoteVisionEmotes = true      -- someone emotes at you (/wave, /bow, /hug...)
DEFAULTS.emoteVisionGroup = true       -- who: your party or raid...
DEFAULTS.emoteVisionGuild = true       -- ...your guild
DEFAULTS.emoteVisionFriends = true     -- ...your friends (and Battle.net friends)
DEFAULTS.emoteVisionStrangers = false  -- ...anyone else
DEFAULTS.emoteVisionHold = 8           -- seconds a card stays (paused while the mouse is over it)
DEFAULTS.emoteVisionScale = 1
DEFAULTS.emoteVisionPortrait = true    -- their face (or class icon) on the card
DEFAULTS.emoteVisionX = 0              -- from the bottom middle of the screen
DEFAULTS.emoteVisionY = 260
-- (Its look: on Visions Style to start with, StylePages.lua's "emote" prefix.)
DEFAULTS.emoteFont = "general"
DEFAULTS.emoteTextSize = 1
DEFAULTS.emoteOutline = -1
DEFAULTS.emoteShadow = "general"
DEFAULTS.emoteBorder = "general"
DEFAULTS.emoteBorderSize = 1
DEFAULTS.emoteBorderR, DEFAULTS.emoteBorderG, DEFAULTS.emoteBorderB = 0, 0, 0
ns.SHARED_STYLE.emoteFont = { kind = "font", own = "game" }
ns.SHARED_STYLE.emoteOutline = { kind = "outline", own = 0 }
ns.SHARED_STYLE.emoteShadow = { kind = "shadow", own = "game" }
ns.SHARED_STYLE.emoteBorder = { kind = "border", own = "thin" }
ns.SHARED_STYLE.emoteBorderSize = { kind = "borderSize", follows = "emoteBorder" }
for _, channel in ipairs({ "R", "G", "B" }) do
	ns.SHARED_STYLE["emoteBorder" .. channel] = { kind = "border" .. channel, follows = "emoteBorder" }
end

-- Where: its Show in row, the open world, cities and instances ticked to
-- start with (not battlegrounds: strangers' buffs and emotes there are noise).
local ROW_KEY = "emote:vision"
ns.CINE_SHOW_SETTING[ROW_KEY] = "emoteVisionAlways"
ns.LIST_DEFAULTS.worldShow[ROW_KEY] = true
ns.LIST_DEFAULTS.cityShow[ROW_KEY] = true
ns.LIST_DEFAULTS.instanceShow[ROW_KEY] = true

local WIDTH = 300
local FADE_IN, FADE_OUT = 0.25, 0.4
local PER_PERSON = 60      -- seconds before the same person can bring up another card
local MAX_AGE = 20         -- a queued moment older than this (a long fight) is dropped
local MAX_QUEUE = 4
local MIN_BUFF = 60        -- a buff shorter than this (a heal over time, a shield) isn't a card
local GOLD = { 1, 0.82, 0 }
local BORDER_GOLD = { 0.55, 0.42, 0.16 }

-- The emotes the buttons play: their tokens (DoEmote) and names.
local EMOTE_NAMES = {
	THANK = "Thank", BOW = "Bow", SALUTE = "Salute", KNEEL = "Kneel", CHEER = "Cheer", WAVE = "Wave",
	HELLO = "Hello", SMILE = "Smile", HUG = "Hug", APPLAUD = "Applaud", KISS = "Kiss", DANCE = "Dance",
}
local BUFF_EMOTES = { "THANK", "BOW", "SALUTE" }
local RES_EMOTES = { "THANK", "KNEEL", "CHEER" }
local BACK_EMOTES = { "WAVE", "SMILE", "BOW" }
-- An emote at you, by the words in it (English), for the same one back first.
local EMOTE_WORDS = {
	{ "wave", "WAVE" }, { "bow", "BOW" }, { "hug", "HUG" }, { "thank", "THANK" }, { "cheer", "CHEER" },
	{ "greet", "HELLO" }, { "hello", "HELLO" }, { "salute", "SALUTE" }, { "smile", "SMILE" },
	{ "kiss", "KISS" }, { "dance", "DANCE" }, { "applaud", "APPLAUD" }, { "clap", "APPLAUD" },
}

local card, queue, lastFrom = nil, {}, {}
local showing -- (the moment on the card: { name, unit, guid, class, line, emotes, test })
local moving   -- (Move: the card held up to drag)
local resFrom  -- (who offered to bring you back: { name, at })
local dead = false

local function Plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local function DB() return ns.GetDB() or DEFAULTS end

local function Look()
	return ns.StyleLook("emoteVision")
end

local function Fighting()
	return InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
end

-- The unit someone is now, if any (their face, and the emote aimed at them).
local function UnitFor(guid, name)
	if not guid and not name then return nil end
	local function Is(unit)
		local each = Plain(UnitGUID(unit))
		if guid then return each == guid end
		return each and Plain(UnitName(unit)) == name
	end
	for _, unit in ipairs({ "target", "mouseover", "focus" }) do
		if Is(unit) then return unit end
	end
	if guid and UnitTokenFromGUID then
		local ok, token = pcall(UnitTokenFromGUID, guid)
		if ok and Plain(token) then return token end
	end
	local group = IsInRaid() and "raid" or "party"
	for i = 1, IsInRaid() and 40 or 4 do
		if Is(group .. i) then return group .. i end
	end
	for i = 1, 40 do
		if Is("nameplate" .. i) then return "nameplate" .. i end
	end
end

-- Who they are to you: "group", "guild", "friend" or "stranger".
local function Relation(guid, name)
	if guid and IsGUIDInGroup and ns.Flag(IsGUIDInGroup(guid)) then return "group" end
	if name and (ns.Flag(UnitInParty(name)) or ns.Flag(UnitInRaid(name))) then return "group" end
	if guid and IsGuildMember then
		local ok, yes = pcall(IsGuildMember, guid)
		if ok and ns.Flag(yes) then return "guild" end
	end
	if guid and C_FriendList and C_FriendList.IsFriend then
		local ok, yes = pcall(C_FriendList.IsFriend, guid)
		if ok and ns.Flag(yes) then return "friend" end
	end
	if guid and C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
		local ok, info = pcall(C_BattleNet.GetAccountInfoByGUID, guid)
		if ok and info then return "friend" end
	end
	return "stranger"
end
local RELATION_KEY = { group = "emoteVisionGroup", guild = "emoteVisionGuild", friend = "emoteVisionFriends",
	stranger = "emoteVisionStrangers" }

---------------------------------------------------------------------------
-- The card.

local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]
local function StyleText(text, look)
	text.base = text.base or { text:GetFont() }
	local file, size, flags = text.base[1], text.base[2], text.base[3]
	if not (file and size) then return end
	if ROMAN then file = ns.StyleFontFile(look.emoteFont) or file end
	text:SetFont(file, size * (tonumber(look.emoteTextSize) or 1) * ns.VisionTextScale(),
		ns.OutlinedFlags(flags, look.emoteOutline))
	ns.SetTextShadow(text, look.emoteShadow)
end

local Hide, Next

local function Place()
	local db = DB()
	local scale = tonumber(db.emoteVisionScale) or 1
	card:SetScale(scale)
	card:ClearAllPoints()
	card:SetPoint("BOTTOM", UIParent, "BOTTOM", (tonumber(db.emoteVisionX) or 0) / scale,
		(tonumber(db.emoteVisionY) or 260) / scale)
end

local function Restyle()
	local look = Look()
	for _, text in ipairs({ card.name, card.line }) do StyleText(text, look) end
	for _, button in ipairs(card.buttons) do StyleText(button:GetFontString(), look) end
	local kind, size, r, g, b = ns.StyleBorder(look, "emoteBorder", BORDER_GOLD)
	if kind == "line" then
		card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = size })
		card:SetBackdropBorderColor(r, g, b, 1)
	elseif kind == "game" then
		card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		card:SetBackdropBorderColor(BORDER_GOLD[1], BORDER_GOLD[2], BORDER_GOLD[3], 1)
	else
		card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	end
	card:SetBackdropColor(0.04, 0.04, 0.05, 0.9)
end

-- Plays emote at the one on the card (a test: says so in chat instead).
local function Answer(token)
	local moment = showing
	if not moment then return end
	if moment.test then
		ns.Print(L["Emote Vision test: you'd /%s %s."]:format(L[EMOTE_NAMES[token]]:lower(), moment.name))
	else
		local unit = UnitFor(moment.guid, moment.name) or moment.name
		pcall(DoEmote, token, unit)
	end
	Hide()
end

local function Create()
	card = CreateFrame("Frame", "CinematicEmoteVision", UIParent, "BackdropTemplate")
	card:SetSize(WIDTH, 96)
	card:SetFrameStrata("DIALOG")
	card:SetClampedToScreen(true)
	card:EnableMouse(true)
	card:SetMovable(true)
	card:RegisterForDrag("LeftButton")
	card:Hide()

	card.portrait = card:CreateTexture(nil, "ARTWORK")
	card.portrait:SetSize(40, 40)
	card.portrait:SetPoint("TOPLEFT", 12, -10)
	-- (A ring round it in their class's color: a circle a little bigger, under it.)
	card.ring = card:CreateTexture(nil, "BORDER")
	card.ring:SetSize(44, 44)
	card.ring:SetPoint("CENTER", card.portrait, "CENTER")
	card.ring:SetColorTexture(1, 1, 1, 1)
	-- (Both round: mask textures, not SetMask, which forbids the icons' tex coords.)
	if card.CreateMaskTexture then
		for _, texture in ipairs({ card.portrait, card.ring }) do
			local mask = card:CreateMaskTexture()
			mask:SetAllPoints(texture)
			mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIONAL",
				"CLAMPTOBLACKADDITIONAL")
			texture:AddMaskTexture(mask)
		end
	end

	card.name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	card.name:SetJustifyH("LEFT")
	card.name:SetWordWrap(false)
	card.line = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	card.line:SetJustifyH("LEFT")
	card.line:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	card.close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	card.close:SetScale(0.7)
	card.close:SetPoint("TOPRIGHT", 2, 2)
	card.close:SetScript("OnClick", function() Hide() end)

	card.buttons = {}
	for i = 1, 3 do
		local button = ns.PanelButton(card)
		button:SetSize(84, 24)
		button:SetScript("OnClick", function(self) Answer(self.token) end)
		card.buttons[i] = button
	end

	card.bar = card:CreateTexture(nil, "ARTWORK")
	card.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
	card.bar:SetHeight(2)
	card.bar:SetPoint("BOTTOMLEFT", 8, 5)

	-- (Moving it: dragged where you want it, kept from the bottom middle.)
	card:SetScript("OnDragStart", function(self) if moving then self:StartMoving() end end)
	card:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if self.SetUserPlaced then self:SetUserPlaced(false) end
		local left, right, bottom = self:GetLeft(), self:GetRight(), self:GetBottom()
		if type(left) == "number" and type(bottom) == "number" then
			local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
			local db = ns.GetDB()
			db.emoteVisionX = math.floor((left + right) / 2 * scale - UIParent:GetWidth() / 2 + 0.5)
			db.emoteVisionY = math.floor(bottom * scale + 0.5)
		end
		Place()
		if ns.RefreshOptions then pcall(ns.RefreshOptions) end
	end)
	card:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then Hide() end
	end)

	card:SetScript("OnUpdate", function(self, elapsed)
		if moving then self:SetAlpha(1) return end
		-- (The mouse over it: its time stands still.)
		if not ns.Flag(self:IsMouseOver()) then self.age = self.age + elapsed end
		local hold = tonumber(DB().emoteVisionHold) or 8
		local age = self.age
		if self.leaving then
			self.leaving = self.leaving + elapsed
			if self.leaving >= FADE_OUT then
				self:Hide()
				return
			end
			self:SetAlpha(1 - self.leaving / FADE_OUT)
			return
		end
		self:SetAlpha(math.min(1, age / FADE_IN))
		self.bar:SetWidth(math.max(1, (WIDTH - 16) * (1 - math.min(1, age / hold))))
		if age >= hold then self.leaving = 0 end
	end)
	card:SetScript("OnHide", function()
		showing = nil
		if not moving then C_Timer.After(0.3, function() Next() end) end
	end)

	if ns.WhyRegister then
		ns.WhyRegister(card, L["Emote Vision"], "Emote Vision", function()
			return { showing and showing.test and L["its test"] or L["someone did something for you (or at you)"] }
		end)
	end
end

-- The card for moment: its face, name, line and buttons, laid out to fit.
local function Show(moment)
	if not card then Create() end
	showing = moment
	Restyle()
	Place()
	local db = DB()
	local face = db.emoteVisionPortrait
	card.portrait:SetShown(face)
	card.ring:SetShown(face)
	if face then
		local unit = moment.unit and Plain(UnitExists(moment.unit)) and moment.unit
		if unit then
			SetPortraitTexture(card.portrait, unit)
			card.portrait:SetTexCoord(0, 1, 0, 1)
		elseif moment.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[moment.class] then
			card.portrait:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
			card.portrait:SetTexCoord(unpack(CLASS_ICON_TCOORDS[moment.class]))
		else
			card.portrait:SetTexture(moment.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			card.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
	end
	local left = face and 62 or 12
	card.name:ClearAllPoints()
	card.name:SetPoint("TOPLEFT", left, -12)
	card.name:SetPoint("RIGHT", -24, 0)
	card.line:ClearAllPoints()
	card.line:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
	card.line:SetPoint("RIGHT", -12, 0)
	card.name:SetText(moment.name)
	local color = moment.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[moment.class]
	if color then
		card.name:SetTextColor(color.r, color.g, color.b)
		card.ring:SetVertexColor(color.r, color.g, color.b, 1)
	else
		card.name:SetTextColor(1, 1, 1)
		card.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	end
	card.line:SetText(moment.line)

	-- Its buttons in a row under the words, centered.
	local count = #moment.emotes
	local gap = 8
	local width = 84
	local total = count * width + (count - 1) * gap
	local top = math.max(face and 56 or 0, 14 + card.name:GetStringHeight() + 3 + card.line:GetStringHeight()) + 8
	for i, button in ipairs(card.buttons) do
		local token = moment.emotes[i]
		button:SetShown(token ~= nil)
		if token then
			button.token = token
			button:SetText(L[EMOTE_NAMES[token]])
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", (WIDTH - total) / 2 + (i - 1) * (width + gap), -top)
		end
	end
	card:SetHeight(top + 24 + 14)
	card.age, card.leaving = 0, nil
	card:SetAlpha(0)
	card:Show()
end

function Hide()
	moving = nil -- (closed while moving it: let go too)
	if card and card:IsShown() and not card.leaving then card.leaving = 0 end
end

-- Whether it shows here now (its page, its Show in row).
local function Allowed()
	if not ns.Setting("emoteVision") then return false end
	local ok, here = pcall(ns.RowOnNow, ROW_KEY, nil, true)
	return ok and here and true or false
end

-- The next queued moment, once out of a fight (the old ones dropped).
function Next()
	if card and card:IsShown() then return end
	if Fighting() then return end
	local now = GetTime()
	while queue[1] do
		local moment = table.remove(queue, 1)
		if now - moment.at <= MAX_AGE and Allowed() then
			Show(moment)
			return
		end
	end
end

-- A moment worth a card: who, what (its line) and the emotes to answer with.
local function Fire(moment, anyone)
	if not ns.Setting("emoteVision") then return end
	local db = DB()
	local who = moment.guid or moment.name
	if not who then return end
	if not anyone and not db[RELATION_KEY[Relation(moment.guid, moment.name)]] then return end
	local now = GetTime()
	if lastFrom[who] and now - lastFrom[who] < PER_PERSON then return end
	lastFrom[who] = now
	moment.at = now
	if not Fighting() and not (card and card:IsShown()) then
		if Allowed() then Show(moment) end
		return
	end
	if #queue < MAX_QUEUE then queue[#queue + 1] = moment end
end

-- Their class (for the name's color and the icon), from their GUID.
local function ClassOf(guid, unit)
	if unit then
		local _, class = UnitClass(unit)
		if Plain(class) then return class end
	end
	if guid and GetPlayerInfoByGUID then
		local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
		if ok and Plain(class) then return class end
	end
end

-- (A name without its realm, for the card.)
local function Short(name)
	return name and (name:match("^([^%-]+)") or name)
end

---------------------------------------------------------------------------
-- The moments.

-- A buff someone else put on you (a minute or more: not a heal over time).
local function Buffed(aura)
	if not DB().emoteVisionBuffs then return end
	local unit = Plain(aura.sourceUnit)
	local name = Plain(aura.name)
	local duration = Plain(aura.duration)
	if not (unit and name and type(duration) == "number" and duration >= MIN_BUFF) then return end
	if Plain(aura.isHelpful) == false then return end
	if unit == "player" or unit == "pet" or unit == "vehicle" or ns.Flag(UnitIsUnit(unit, "player")) then return end
	local guid = Plain(UnitGUID(unit))
	-- (By GUID: UnitIsPlayer can say false for players after a buff on Forever.)
	if not (guid and guid:find("^Player%-")) then return end
	Fire({ name = Short(Plain(UnitName(unit))) or "?", unit = unit, guid = guid, class = ClassOf(guid, unit),
		icon = Plain(aura.icon), line = L["gave you %s"]:format(name), emotes = BUFF_EMOTES })
end

-- Old clients' auras with no list of the new ones: what's new since last time.
local seenAuras
local function ScanOld(silent)
	if not UnitAura then return end
	local now = {}
	for i = 1, 40 do
		local name, icon, _, _, duration, expires, source = UnitAura("player", i, "HELPFUL")
		if not name then break end
		local key = tostring(name) .. ":" .. tostring(source) .. ":" .. tostring(expires)
		now[key] = true
		if not silent and seenAuras and not seenAuras[key] and source then
			Buffed({ sourceUnit = source, name = name, duration = duration, icon = icon })
		end
	end
	seenAuras = now
end

local function AurasChanged(info)
	-- (In a fight they're secret on retail: learnt again, quietly, after it.)
	if Fighting() then return end
	if type(info) ~= "table" then
		ScanOld(false)
		return
	end
	-- (Can be secret out of a fight too, in instances: skipped then.)
	local full, added = info.isFullUpdate, info.addedAuras
	if issecretvalue and (issecretvalue(full) or issecretvalue(added)) then return end
	if full or type(added) ~= "table" then return end
	for _, aura in ipairs(added) do
		if type(aura) == "table" then Buffed(aura) end
	end
end

-- Back from death, raised by someone who offered (not a spirit healer or your
-- own soulstone: no one to thank, or the soulstone's buff did already).
local function AliveCheck()
	local now = ns.Flag(UnitIsDeadOrGhost("player")) and true or false
	if dead and not now and resFrom and GetTime() - resFrom.at < 120 and DB().emoteVisionRes then
		local name = resFrom.name
		local unit = UnitFor(nil, name)
		local guid = unit and Plain(UnitGUID(unit))
		Fire({ name = Short(name), unit = unit, guid = guid, class = ClassOf(guid, unit),
			icon = "Interface\\Icons\\Spell_Holy_Resurrection", line = L["brought you back to life"],
			emotes = RES_EMOTES }, true)
	end
	if not now then resFrom = nil end
	dead = now
end

-- An emote aimed at you: "Pip waves at you." (the word "you" in it, or the
-- language's own: L["you"]).
local YOU = L["you"]
local function AtYou(text)
	local lower = text:lower()
	if lower:find("%f[%a]you%f[%A]") then return true end
	return YOU ~= "you" and lower:find("%f[%a]" .. YOU:lower() .. "%f[%A]") ~= nil
end
local function Emoted(text, author, guid)
	if not DB().emoteVisionEmotes then return end
	text, author, guid = Plain(text), Plain(author), Plain(guid)
	if type(text) ~= "string" or type(author) ~= "string" then return end
	if guid == Plain(UnitGUID("player")) then return end
	if guid and not guid:find("^Player%-") then return end
	if not AtYou(text) then return end
	-- (The same one back first, then the usual few.)
	local emotes, lower = {}, text:lower()
	for _, pair in ipairs(EMOTE_WORDS) do
		if lower:find(pair[1], 1, true) then
			emotes[1] = pair[2]
			break
		end
	end
	for _, token in ipairs(BACK_EMOTES) do
		if #emotes < 3 and token ~= emotes[1] then emotes[#emotes + 1] = token end
	end
	local name = Short(author)
	local line = text
	if line:sub(1, #name) == name then line = line:sub(#name + 1):gsub("^%s+", "") end
	local unit = UnitFor(guid, name)
	Fire({ name = name, unit = unit, guid = guid, class = ClassOf(guid, unit), line = line, emotes = emotes })
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "RESURRECT_REQUEST", "PLAYER_DEAD",
	"PLAYER_ALIVE", "PLAYER_UNGHOST", "CHAT_MSG_TEXT_EMOTE" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
pcall(watcher.RegisterUnitEvent, watcher, "UNIT_AURA", "player")
watcher:SetScript("OnEvent", function(_, event, ...)
	if event == "UNIT_AURA" then
		AurasChanged(select(2, ...))
	elseif event == "CHAT_MSG_TEXT_EMOTE" then
		local text, author = ...
		Emoted(text, author, (select(12, ...)))
	elseif event == "RESURRECT_REQUEST" then
		local name = Plain((...))
		if type(name) == "string" then resFrom = { name = name, at = GetTime() } end
	elseif event == "PLAYER_DEAD" then
		dead = true
	elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		C_Timer.After(0, AliveCheck)
	elseif event == "PLAYER_REGEN_ENABLED" then
		ScanOld(true)
		C_Timer.After(1, Next)
	elseif event == "PLAYER_ENTERING_WORLD" then
		dead = ns.Flag(UnitIsDeadOrGhost("player")) and true or false
		ScanOld(true)
	end
end)

---------------------------------------------------------------------------
-- The page's test and mover.

local SAMPLES = {
	{ name = "Aelwyn", class = "PRIEST", line = "gave you %s", spell = "Power Word: Fortitude", emotes = BUFF_EMOTES,
		icon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
	{ name = "Thornbrook", class = "DRUID", line = "brought you back to life", emotes = RES_EMOTES },
	{ name = "Pip", class = "MAGE", line = "waves at you.", emotes = { "WAVE", "SMILE", "BOW" } },
}
local nextSample = 1
function ns.TestEmoteVision()
	local sample = SAMPLES[nextSample]
	nextSample = nextSample % #SAMPLES + 1
	moving = nil
	if card then card:Hide() end
	Show({ name = sample.name, class = sample.class, icon = sample.icon, emotes = sample.emotes, test = true,
		line = sample.spell and L[sample.line]:format(L[sample.spell]) or L[sample.line] })
end

-- Move: the card held up to drag where you want it; again to let go.
function ns.MoveEmoteVision()
	if moving then
		moving = nil
		Hide()
		return
	end
	ns.TestEmoteVision()
	moving = true
	card:SetAlpha(1)
end
function ns.EmoteVisionMoving() return moving and true or false end

function ns.RefreshEmoteVision()
	if not card then return end
	if not ns.Setting("emoteVision") then
		moving = nil
		wipe(queue)
		card:Hide()
		return
	end
	if card:IsShown() then
		Restyle()
		Place()
	end
end

-- /cine debug emotevision: what it would do now, and why.
function ns.EmoteVisionDebug()
	local ok, here = pcall(ns.RowOnNow, ROW_KEY, nil, true)
	ns.Print(("emotevision: page %s; here %s; fighting %s; queued %d; card %s; dead %s; res offer %s"):format(
		tostring(ns.Setting("emoteVision")), ok and tostring(here) or ("error: " .. tostring(here)),
		tostring(Fighting()), #queue, card and card:IsShown() and tostring(showing and showing.name) or "hidden",
		tostring(dead), resFrom and resFrom.name or "none"))
	local target = Plain(UnitGUID("target"))
	if target then
		ns.Print(("  target %s: %s, unit %s"):format(tostring(Plain(UnitName("target"))),
			Relation(target, Plain(UnitName("target"))), tostring(UnitFor(target))))
	end
end

---------------------------------------------------------------------------
-- The page (Visions, World).

function ns.CreateEmoteVisionPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Emote Vision"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["When someone buffs you, brings you back to life or emotes at you, a small card shows who it was, " ..
		"with a few emotes to answer in one click. It waits out fights and fades away by itself."])
	local function Changed() ns.RefreshEmoteVision() end
	local switch = kit.PageSwitch(content, "emoteVision", L["Enable Page"],
		L["On: the cards show as ticked below. Off: none do, and it keeps its settings for when you turn " ..
		"this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "emoteVision")
	local function On() return ns.GetDB() and ns.GetDB().emoteVision end

	local header = stack:Header(content, L["Show in"])
	local lastRow = ns.ShowTable(content, header, {
		underHeader = true,
		{ key = ROW_KEY, label = L["Emote Vision"], alwaysKey = "emoteVisionAlways",
			alwaysOn = function() return ns.GetDB().emoteVisionAlways end,
			setAlways = function(value) ns.GetDB().emoteVisionAlways = value Changed() end,
			alwaysTip = L["Shows wherever you are. (Never in a fight: a card from one waits for it to end.)"],
			apply = Changed },
	}, L["Emote Vision"])
	stack:Continue(lastRow, "label")

	stack:Header(content, L["Moments"])
	rows.Check("emoteVisionBuffs", L["Someone buffs you"], L["A buff of a minute or more someone else puts on " ..
		"you (Fortitude, Arcane Intellect, a blessing...): Thank, Bow or Salute. Not heals over time."], On)
	rows.Check("emoteVisionRes", L["You're brought back to life"], L["Someone resurrects you and you accept: " ..
		"Thank, Kneel or Cheer. Whoever it is, Who below or not."], On)
	rows.Check("emoteVisionEmotes", L["Someone emotes at you"], L["Someone waves, bows, hugs or the like at " ..
		"you: the same back, Wave, Smile or Bow."], On)

	stack:Header(content, L["Who"])
	rows.Check("emoteVisionGroup", L["Your party or raid"], nil, On)
	rows.Check("emoteVisionGuild", L["Your guild"], nil, On)
	rows.Check("emoteVisionFriends", L["Your friends"], L["Friends and Battle.net friends."], On)
	rows.Check("emoteVisionStrangers", L["Anyone else"], L["Everyone not above: strangers in a city buffing " ..
		"everyone near them too."], On)

	stack:Header(content, L["Card"])
	local hold = stack:Add(kit.Slider(content, "emoteVisionHold", L["Stays for"], 3, 20, 1, "%d sec", 1, Changed),
		"slider")
	kit.Tooltip(hold, L["How long a card stays before it fades. The mouse over it holds it."])
	kit.GreyUnless(hold, On)
	local size = stack:Add(kit.Slider(content, "emoteVisionScale", L["Size"], 50, 150, 5, "%d%%", 100, Changed),
		"slider")
	kit.GreyUnless(size, On)
	rows.Check("emoteVisionPortrait", L["Their face"], L["Their portrait on the card (their class's icon when " ..
		"they're out of sight)."], On)

	-- Test and Move, on a row of their own.
	local row = CreateFrame("Frame", nil, content)
	row:SetSize(300, 26)
	stack:Add(row, "label")
	local test = ns.PanelButton(content)
	test:SetSize(100, 22)
	test:SetPoint("LEFT", row, "LEFT")
	test:SetText(L["Test"])
	test:SetScript("OnClick", function() ns.TestEmoteVision() end)
	test.Refresh = function() end -- (before GreyUnless, which wraps it)
	kit.Tooltip(test, L["Shows a pretend card (close the settings to see it). Its buttons only say in chat " ..
		"what they'd do."])
	kit.GreyUnless(test, On)
	kit.AddControl(test)
	local move = ns.PanelButton(content)
	move:SetSize(100, 22)
	move:SetPoint("LEFT", test, "RIGHT", 8, 0)
	local function Label() move:SetText(ns.EmoteVisionMoving() and L["Done"] or L["Move"]) end
	move:SetScript("OnClick", function()
		ns.MoveEmoteVision()
		Label()
	end)
	move:SetScript("OnUpdate", Label)
	move.Refresh = Label
	kit.Tooltip(move, L["Holds the card up so you can drag it where you want it; Done lets it go."])
	kit.GreyUnless(move, On)
	kit.AddControl(move)
	local reset = ns.PanelButton(content)
	reset:SetSize(100, 22)
	reset:SetPoint("LEFT", move, "RIGHT", 8, 0)
	reset:SetText(L["Reset"])
	reset:SetScript("OnClick", function()
		local db = ns.GetDB()
		db.emoteVisionX, db.emoteVisionY = DEFAULTS.emoteVisionX, DEFAULTS.emoteVisionY
		Changed()
	end)
	reset.Refresh = function() end -- (before GreyUnless, which wraps it)
	kit.Tooltip(reset, L["Puts the card back where it starts, low in the middle of the screen."])
	kit.GreyUnless(reset, On)
	kit.AddControl(reset)

	stack:Header(content, L["Look"])
	rows.Font("emoteFont")
	local textSize = stack:Add(kit.Slider(content, "emoteTextSize", L["Text size"], 70, 150, 5, "%d%%", 100,
		Changed), "slider")
	kit.GreyUnless(textSize, On)
	rows.Outline("emoteOutline", L["Outline"], 2, { [0] = L["None"], L["Thin"], L["Thick"] })
	rows.Choices(L["Shadow:"], "emoteShadow", {
		{ "general", ns.SharedStyleSource("emoteShadow") }, { "game", L["The game's"] }, { "on", L["Shadow"] },
		{ "none", L["None"] },
	})
	rows.Border(L["Border:"], "emoteBorder", { game = L["The game's"] })

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Emote Vision")
end
