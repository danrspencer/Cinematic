-- The Cards page's Last time: as you log in, what you did in your last
-- session, such as "Last time: Darkshore · 3 quests done · reached level 24".
-- A card (Cards.lua fires and draws it: its look is the page's), or a line
-- under the zone name (Tint.lua draws it); its heading and which details on
-- the page's Last time event. This file keeps the counts.
--
-- A session's counts live in CinematicCharDB.session and are written as they
-- change (no polling: a few events), so a crash that skips PLAYER_LOGOUT
-- keeps them. A /reload carries on the same session; a real login makes the
-- one there last session's, and starts a new one.

local _, ns = ...
local L = ns.L
local DEFAULTS = ns.DEFAULTS

DEFAULTS.storyRecap = true -- the Last time row
DEFAULTS.storyRecapUnder = false       -- a line under the zone name, not a card
DEFAULTS.storyRecapDelay = 2           -- the card: seconds after the zone name comes in
DEFAULTS.storyRecapHeading = "lasttime" -- "lasttime", "previously", "previouslyon", "sofar" or "none"
-- Which details (in this order), and a little icon before each.
DEFAULTS.storyRecapZone = true
DEFAULTS.storyRecapPlayed = true
DEFAULTS.storyRecapQuests = true
DEFAULTS.storyRecapLevel = true
DEFAULTS.storyRecapBosses = true
DEFAULTS.storyRecapDeaths = false
DEFAULTS.storyRecapGold = false
DEFAULTS.storyRecapIcons = false
DEFAULTS.storyRecapSound = true        -- a page turning as it shows

local MAX_AGE = 14 * 24 * 3600 -- seconds: an older last session isn't worth recalling
local SEPARATOR = " · "
local PAGE_TURN = 836 -- (SOUNDKIT.IG_ABILITY_PAGE_TURN)

-- The zone shown is the one you spent the most time in, not the last one:
-- you often log out in a city or an inn, which says little about what you
-- did. Each zone's time is added up as you leave it (or log out); the zone
-- you're in now goes in as soon as you leave it.
local zoneNow, zoneSince
local started -- (events before the login's RecapLogin are last session's business: left alone)
local lastParts -- (the last session's, from the login: the card plays them)

local function Session()
	local chardb = ns.chardb
	if not chardb then return nil end
	if not chardb.session then
		chardb.session = { zones = {}, begun = time(), moneyStart = GetMoney and GetMoney() or nil }
	end
	return chardb.session
end

-- The time in the zone you're in, added to its total; then counting again
-- from now (in the zone you're in now, if it changed).
local function CountZone()
	local session = Session()
	if not session then return end
	local now = GetTime()
	if zoneNow and zoneSince then
		session.zones[zoneNow] = (session.zones[zoneNow] or 0) + (now - zoneSince)
	end
	local zone = GetRealZoneText and GetRealZoneText() or ""
	if type(zone) == "string" and zone ~= "" then
		zoneNow, zoneSince = zone, now
		session.lastZone = zone -- (the zone if no time got counted: a crash in the first zone)
	end
	session.saved = time()
end

-- (Each count also adds up the zone's time so far, so a crash loses little of it.)
local function Count(key, by)
	CountZone()
	local session = Session()
	if not session then return end
	session[key] = (session[key] or 0) + (by or 1)
end

-- A finished session's counts, or nil if it was too long ago: the zone, quests,
-- level reached, bosses, deaths, seconds played and copper earned.
local function RecapParts(session)
	if type(session) ~= "table" or not session.saved or time() - session.saved > MAX_AGE then
		return nil
	end
	local zone, most = session.lastZone, 0
	for name, seconds in pairs(session.zones or {}) do
		if seconds > most then zone, most = name, seconds end
	end
	return { zone = zone, quests = session.quests or 0, level = session.level, bosses = session.bosses or 0,
		deaths = session.deaths or 0, played = session.begun and session.saved - session.begun or nil,
		gold = session.moneyStart and session.money and session.money - session.moneyStart or 0 }
end

-- Made up, for the Test and the preview while this session has nothing yet.
local function SampleParts()
	local zone = GetRealZoneText and GetRealZoneText() or ""
	return { zone = zone ~= "" and zone or "Darkshore", quests = 3, level = UnitLevel("player") or 24, bosses = 1,
		deaths = 2, played = 5400, gold = 123456 }
end

local function Icon(file) return ("|T%s:0|t "):format(file) end
local ICONS = {
	zone = "Interface\\Icons\\INV_Misc_Map_01", played = "Interface\\Icons\\INV_Misc_PocketWatch_01",
	quests = "Interface\\GossipFrame\\ActiveQuestIcon", level = "Interface\\Icons\\Spell_Holy_InnerFire",
	bosses = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", deaths = "Interface\\Icons\\Ability_Rogue_FeignDeath",
	gold = "Interface\\Icons\\INV_Misc_Coin_01",
}

local function Played(seconds)
	local minutes = math.floor(seconds / 60 + 0.5)
	if minutes < 60 then return L["%d min played"]:format(math.max(minutes, 1)) end
	return L["%s h played"]:format(("%.1f"):format(minutes / 60))
end

-- The details shown, in order (each with its icon, if ticked), without the
-- zone if noZone; nil if none of what happened is shown.
local function Details(parts, look, noZone)
	local list, happened = {}, false
	local function Add(key, text)
		list[#list + 1] = (look.storyRecapIcons and Icon(ICONS[key]) or "") .. text
	end
	if look.storyRecapZone and parts.zone and not noZone then Add("zone", parts.zone) end
	if look.storyRecapPlayed and parts.played and parts.played >= 60 then Add("played", Played(parts.played)) end
	if look.storyRecapQuests and parts.quests > 0 then
		Add("quests", (parts.quests == 1 and L["%d quest done"] or L["%d quests done"]):format(parts.quests))
		happened = true
	end
	if look.storyRecapLevel and parts.level then
		Add("level", L["reached level %d"]:format(parts.level))
		happened = true
	end
	if look.storyRecapBosses and parts.bosses > 0 then
		Add("bosses", (parts.bosses == 1 and L["%d boss down"] or L["%d bosses down"]):format(parts.bosses))
		happened = true
	end
	if look.storyRecapDeaths and parts.deaths > 0 then
		Add("deaths", (parts.deaths == 1 and L["%d death"] or L["%d deaths"]):format(parts.deaths))
		happened = true
	end
	if look.storyRecapGold and parts.gold > 0 then
		local coins = GetCoinTextureString and GetCoinTextureString(parts.gold)
			or ("%dg"):format(math.floor(parts.gold / 10000))
		Add("gold", L["%s earned"]:format(coins))
		happened = true
	end
	return happened and list or nil
end

-- The heading picked: "Last time", "Previously", "Previously, on <you>"...
local function Heading(look)
	local heading = look.storyRecapHeading
	if heading == "none" then return nil end
	if heading == "previously" then return L["Previously"] end
	if heading == "previouslyon" then return L["Previously, on %s"]:format(UnitName("player") or "") end
	if heading == "sofar" then return L["Your story so far"] end
	return L["Last time"]
end

-- One line under the zone name, or nil.
local function RecapText(parts, look)
	local list = parts and Details(parts, look)
	if not list then return nil end
	local body, heading = table.concat(list, SEPARATOR), Heading(look)
	if look.storyRecapHeading == "lasttime" or look.storyRecapHeading == nil then
		return L["Last time: %s"]:format(body)
	end
	return heading and heading .. ": " .. body or body
end

-- (The line under the zone name for parts.)
function ns.RecapLineFor(parts)
	return RecapText(parts, ns.db)
end

-- A card: the zone big, the heading over it, the rest under it (the heading
-- big if the zone isn't shown); nil if nothing to say.
function ns.RecapCardText(parts, look)
	local zone = look.storyRecapZone and parts.zone or nil
	local list = Details(parts, look, true)
	if not list then return nil end
	local heading = Heading(look)
	local name = zone or heading or ""
	return { name = name, sub = table.concat(list, SEPARATOR), meta = zone and heading or nil }
end

local function PageTurn()
	if ns.db.storyRecapSound then
		pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN or PAGE_TURN, "SFX")
	end
end

-- Plays the Last time card for parts (default: the login's) a moment after
-- the zone name, unless it's a line under the zone name; true if it did.
-- Under the zone name, the page turning just plays.
local played = 0
function ns.RecapCard(parts)
	parts = parts or lastParts
	local db = ns.db
	if db.storyRecapUnder or not parts then
		if parts then PageTurn() end
		return false
	end
	local card = ns.RecapCardText(parts, db)
	if not card then return false end
	card.sound = PageTurn
	played = played + 1
	local this = played
	C_Timer.After(tonumber(db.storyRecapDelay) or 0, function()
		if this ~= played or InCombatLockdown() then return end
		ns.Cards.Fire("login", card)
	end)
	return true
end

-- The Test and preview's card: this session's so far, else made up.
ns.CardSamples = ns.CardSamples or {}
ns.CardSamples.login = function()
	local card = ns.RecapCardText(ns.RecapPartsNow(), ns.db) or { name = "Darkshore", sub = "" }
	card.sound = PageTurn
	return card
end

-- Core.lua, at PLAYER_ENTERING_WORLD after a login or /reload. A real login
-- (initial) starts a new session and returns the last one's line, if any
-- (ns.RecapCard then plays it as a card, if it goes on one).
function ns.RecapLogin(initial)
	local chardb = ns.chardb
	if not chardb then return nil end
	local line
	if initial then
		lastParts = RecapParts(chardb.session)
		line = RecapText(lastParts, ns.db)
		if not line then lastParts = nil end
		chardb.session = nil
	end
	zoneNow, zoneSince, started = nil, nil, true
	CountZone()
	return line
end

-- /cine recaptest: the line as your next login would show it (this
-- session's so far), and what it's made of.
function ns.RecapPreview()
	CountZone()
	local session = Session()
	return RecapText(RecapParts(session), ns.db), session
end

-- What the preview and the Test show: this session's so far, else made up
-- (second: true).
function ns.RecapPartsNow()
	CountZone()
	local look = ns.db
	local parts = RecapParts(Session())
	if parts and RecapText(parts, look) then return parts, false end
	return SampleParts(), true
end

-- The Test button and /cine recaptest: plays the login now, without logging
-- out: the zone name fades in as it does when you enter the world, with the
-- time of day (if ticked) and the Last time line under it, or its card. This
-- session's if there is one, else a made-up one in the zone you're in
-- (returned second: true), so there's always something to look at.
function ns.RecapDemo()
	local parts, sample = ns.RecapPartsNow()
	local line = RecapText(parts, ns.db) or L["Last time: %s"]:format(parts.zone)
	-- The game's own zone name, as at login (its frame is plain, not secure).
	local onEvent = ZoneTextFrame and ZoneTextFrame:GetScript("OnEvent")
	if onEvent then
		pcall(onEvent, ZoneTextFrame, "ZONE_CHANGED_NEW_AREA")
	end
	local carded = ns.RecapCard(parts)
	if ns.ShowTimeOfDayTitle then
		local showTime = ns.Setting("timeOfDayMessage") and not (ns.ZoneCardTime and ns.ZoneCardTime())
		ns.ShowTimeOfDayTitle(showTime, not carded and line or nil)
	end
	return line, sample
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "ENCOUNTER_END",
		"PLAYER_DEAD", "PLAYER_MONEY", "PLAYER_LOGOUT" }) do
	frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", ns.Profiled("Last time", function(_, event, ...)
	if not started then
		return
	elseif event == "QUEST_TURNED_IN" then
		Count("quests")
	elseif event == "PLAYER_DEAD" then
		Count("deaths")
	elseif event == "PLAYER_MONEY" then
		local session = Session()
		if session and GetMoney then session.money = GetMoney() end
	elseif event == "PLAYER_LEVEL_UP" then
		local level = ...
		CountZone()
		local session = Session()
		if session and type(level) == "number" then
			session.level = level
		end
	elseif event == "ENCOUNTER_END" then
		local success = select(5, ...)
		if not (issecretvalue and issecretvalue(success)) and success == 1 then
			Count("bosses")
		end
	else -- (a new zone, or logging out: the time in the last one counted)
		CountZone()
	end
end))
