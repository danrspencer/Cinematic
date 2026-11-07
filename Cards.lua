-- Cards: every moment that puts words on your screen, one kind of card on
-- one page (Battle Vision's and Story Vision's moments before). Each moment
-- is an event (CARD_EVENTS). The code that hears it (CombatVision.lua's
-- fights and bosses, ZoneCard.lua, Recap.lua, Tint.lua's time of day and
-- death, Chat.lua's attacks) calls ns.Cards.Fire(id, card), and this file
-- does the rest: the page's switch and the event's own tick, its Show in row
-- (GridRows.lua's, "card:<id>"), its look, and one card at a time on the
-- screen (a more important one cuts in, a less important one waits), drawn
-- by CombatVision.lua (ns.PlayCard).
--
-- The look: each event's own settings where it has them (card<Field>_<id>;
-- "default": its parent's, else the style it starts from's), over the style
-- it starts from: your changes to it (cardLook<Field>_<style>; "default":
-- as it comes), over its ready-made look (STYLES), over the base look
-- (card<Field>: not on the page, kept at its defaults). Setting by setting:
-- an event can have its own color and still follow its style's font. (The
-- CardsPage.lua pages edit them.)

local _, ns = ...
local L = ns.L
local DEFAULTS = ns.DEFAULTS

DEFAULTS.cards = true      -- the page's switch
DEFAULTS.cardDeathOn = false -- the Death row (on in Cinema: YOU DIED as the death camera starts)
DEFAULTS.timeOfDayChange = true -- the Time of day row: its name and sound as it changes
DEFAULTS.cardDuelOn = false -- the Duel row: your own duels (on in every built-in profile)
-- Its moments, each a tick on its Settings tab (Effects.lua hears them), and
-- its words.
DEFAULTS.cardDuelAsk = true    -- you challenge someone
DEFAULTS.cardDuelAsked = true  -- someone challenges you
DEFAULTS.cardDuelStart = true  -- it starts
DEFAULTS.cardDuelResult = true -- you win or lose
DEFAULTS.duelTextStart = "Duel"
DEFAULTS.duelTextWon = "Victory"
DEFAULTS.duelTextLost = "Defeat"
-- Souls banners (a souls-like's VICTORY ACHIEVED, as Death's YOU DIED): the
-- words Boss defeated, Rare felled and Revived show (SOULS_WORDS' or
-- "custom": <id>Text), and whether Duel, Battleground, Dungeon cleared and
-- Kill streak's wins and losses show as one ("souls") or as they were.
DEFAULTS.bossDownWords = "victory"
DEFAULTS.bossDownText = ""
DEFAULTS.felledWords = "felled"
DEFAULTS.felledText = ""
DEFAULTS.revivedWords = "restored"
DEFAULTS.revivedText = ""
for _, id in ipairs({ "duel", "battleground", "cleared", "streak" }) do DEFAULTS["cardSouls_" .. id] = "usual" end

local BOOK = "Interface\\Icons\\INV_Misc_Book_09"
local MAP = "Interface\\Icons\\INV_Misc_Map_01"
local ROW = "card:" -- (each event's Show in row: ROW .. id)
local WAIT_MAX = 6  -- seconds a card waits behind a more important one before it's dropped
local CALM_AFTER = 5 -- seconds out of a fight before the cards held through it show (back in it: longer)
local HELD_MAX = 300 -- a card held through a fight longer than this is dropped

-- The events, in the page's order: name, its row's tick (on: a setting of
-- its own, kept from before the page), priority (a higher one cuts in, the
-- same replaces, a lower one waits), its icon, the one it follows for its
-- look (parent) and the one it needs on to show at all (needs). has = false:
-- the client can't tell (no row). inFight: what it does in a fight to start
-- with ("show", "wait" till after it, "skip"; cardFight_<id>), none: always
-- shows (it's about the fight). (CardMoments.lua hears the ones from Level up
-- on.)
local EVENTS = {
	{ id = "combatIn", name = "Entering combat", on = "combatOnEnter", priority = 50,
		icon = "Interface\\Icons\\Ability_DualWield", fight = true },
	{ id = "combatOut", name = "Leaving combat", on = "combatOnLeave", priority = 50, icon = 132320, fight = true },
	{ id = "boss", name = "Boss", on = "cardBossOn", priority = 80,
		icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", fight = true },
	-- (Over Dungeon cleared's: the kill's own banner first, the run's after.)
	{ id = "bossDown", name = "Boss defeated", on = "cardBossDownOn", priority = 85,
		icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", inFight = "wait" },
	{ id = "cleared", name = "Dungeon cleared", on = "cardClearedOn", priority = 75,
		icon = "Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster",
		has = EJ_GetInstanceForMap ~= nil, inFight = "wait" },
	{ id = "zone", name = "Zone", on = "storyZoneCard", priority = 40, icon = MAP, inFight = "skip" },
	{ id = "subzone", name = "Subzone", on = "storyZoneSubzones", priority = 40, icon = MAP, parent = "zone",
		needs = "zone", inFight = "skip" },
	-- (A notch over Zone's: it cuts in on the card it'd come with.)
	{ id = "discover", name = "Discovered", on = "cardDiscoverOn", priority = 45,
		icon = "Interface\\Icons\\INV_Misc_Spyglass_03", parent = "zone", inFight = "show" },
	-- (Over Zone's and Subzone's: a city hop crosses subzones as it takes off,
	-- their cards would keep it waiting till it's dropped.)
	{ id = "departure", name = "Flight departure", on = "cardDepartureOn", priority = 42,
		icon = "Interface\\Icons\\Ability_Mount_Gryphon_01", parent = "zone", inFight = "show" },
	{ id = "arrival", name = "Flight arrival", on = "cardArrivalOn", priority = 30,
		icon = "Interface\\Icons\\Ability_Mount_Gryphon_01", parent = "zone", inFight = "show" },
	{ id = "rested", name = "Rested", on = "cardRestedOn", priority = 25,
		icon = "Interface\\Icons\\Spell_Nature_Sleep", inFight = "show" },
	{ id = "login", name = "Last time", on = "storyRecap", priority = 35, icon = BOOK, inFight = "show" },
	{ id = "time", name = "Time of day", on = "timeOfDayChange", priority = 20,
		icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", inFight = "wait" },
	{ id = "levelUp", name = "Level up", on = "cardLevelUpOn", priority = 70,
		icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight", inFight = "wait" },
	{ id = "achievement", name = "Achievement", on = "cardAchievementOn", priority = 65,
		icon = "Interface\\Icons\\Achievement_General", has = GetAchievementInfo ~= nil, inFight = "wait" },
	{ id = "reputation", name = "Reputation", on = "cardReputationOn", priority = 45,
		icon = "Interface\\Icons\\INV_Misc_Note_02", inFight = "wait" },
	{ id = "collect", name = "New mount or pet", on = "cardCollectOn", priority = 45,
		icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
		has = C_MountJournal ~= nil or C_PetJournal ~= nil, inFight = "wait" },
	{ id = "profession", name = "Profession rank", on = "cardProfessionOn", priority = 45,
		icon = "Interface\\Icons\\Trade_BlackSmithing", inFight = "wait" },
	{ id = "quest", name = "Story quest", on = "cardQuestOn", priority = 55,
		icon = "Interface\\Icons\\INV_Misc_Book_07", inFight = "wait" },
	{ id = "rare", name = "Rare spotted", on = "cardRareOn", priority = 60,
		icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath", inFight = "show" },
	{ id = "felled", name = "Rare felled", on = "cardFelledOn", priority = 62,
		icon = "Interface\\Icons\\Ability_BackStab", inFight = "show" },
	{ id = "attack", name = "Under attack", on = "chatAttackAlert", priority = 60,
		icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
	-- (Combat's priority: a duel's cards and its fight's replace each other,
	-- the newest showing.)
	{ id = "duel", name = "Duel", on = "cardDuelOn", priority = 50,
		icon = "Interface\\Icons\\Ability_Warrior_Challange" },
	{ id = "battleground", name = "Battleground", on = "cardBattlegroundOn", priority = 60,
		icon = "Interface\\Icons\\Ability_Warrior_OffensiveStance", inFight = "show" },
	{ id = "streak", name = "Kill streak", on = "cardStreakOn", priority = 55,
		icon = "Interface\\Icons\\Ability_Warrior_Rampage", fight = true },
	{ id = "death", name = "Death", on = "cardDeathOn", priority = 100,
		icon = "Interface\\Icons\\Ability_Rogue_FeignDeath" },
	{ id = "revived", name = "Revived", on = "cardRevivedOn", priority = 100,
		icon = "Interface\\Icons\\Spell_Holy_Resurrection" },
}
for i = #EVENTS, 1, -1 do
	if EVENTS[i].has == false then table.remove(EVENTS, i) end
end
ns.CARD_EVENTS = EVENTS
local BY_ID = {}
for _, event in ipairs(EVENTS) do BY_ID[event.id] = event end
ns.CARD_BY_ID = BY_ID

-- The Events tab's groups, in its order, a title over each (as the emote
-- page's moments). An event left out of them goes in the last.
ns.CARD_GROUPS = {
	{ name = "Combat", "combatIn", "combatOut", "attack", "streak", "death", "revived" },
	{ name = "Bosses and rares", "boss", "bossDown", "cleared", "rare", "felled" },
	{ name = "Places and travel", "zone", "subzone", "discover", "departure", "arrival", "rested" },
	{ name = "Your story", "login", "time", "quest" },
	{ name = "Progress", "levelUp", "achievement", "reputation", "collect", "profession" },
	{ name = "Player vs. player", "duel", "battleground" },
}
-- The events in the tab's order, each with its group's name (event.group).
function ns.CardEventsGrouped()
	local list, placed = {}, {}
	for _, group in ipairs(ns.CARD_GROUPS) do
		for _, id in ipairs(group) do
			local event = BY_ID[id]
			if event and not placed[id] then
				placed[id] = true
				event.group = group.name
				list[#list + 1] = event
			end
		end
	end
	for _, event in ipairs(EVENTS) do
		if not placed[event.id] then
			event.group = ns.CARD_GROUPS[#ns.CARD_GROUPS].name
			list[#list + 1] = event
		end
	end
	return list
end

-- The look's settings: each field, the card drawing's settings it gives
-- (CombatVision.lua's: going in, coming out), and the base look's value.
local FIELDS = {
	{ "Place", { "combatPlace" }, "third" },     -- "screen", "top" or "bottom" bar, "third"
	{ "Align", { "combatAlign" }, "center" },    -- in a bar: "left", "center" or "right"
	{ "OffsetX", { "combatOffsetX" }, 0 },       -- moved right (left below 0), a share of the screen's width
	{ "OffsetY", { "combatOffsetY" }, 0 },       -- ...and up, a share of its height
	{ "BarScale", { "combatBarScale" }, 0.5 },   -- in a bar: the words' height, a share of the bar's
	{ "BarFallback", { "combatBarFallback" }, true }, -- in a bar with no letterbox up: the lower third
	{ "Style", { "combatStyle" }, "chapter" },   -- "title", "subtitle", "chapter" or "banner"
	{ "Anim", { "combatAnim" }, "track" },       -- "fade", "reveal", "track" or "type"
	{ "Font", { "combatFont" }, "general" },     -- QUEST_ITEM_FONTS (general: General's)
	{ "Size", { "combatSize" }, 36 },            -- the words' height on the screen
	{ "Outline", { "combatOutline" }, -1 },      -- 0 none, 1 thin, 2 thick (-1: General's)
	{ "OutlineR", { "combatOutlineR" }, 0 },
	{ "OutlineG", { "combatOutlineG" }, 0 },
	{ "OutlineB", { "combatOutlineB" }, 0 },
	{ "Shadow", { "combatShadow" }, "general" }, -- "game", "on" or "none" (general: General's)
	{ "R", { "combatInR", "combatOutR" }, 1 },   -- the words' color, the zone's gold (the lines under it lighter)
	{ "G", { "combatInG", "combatOutG" }, 0.82 },
	{ "B", { "combatInB", "combatOutB" }, 0 },
	{ "Hold", { "combatHoldIn", "combatHoldOut" }, 3 }, -- seconds it stays, between its fades
	{ "Pulse", { "combatPulseIn", "combatPulseOut" }, 0 }, -- the screen's edges flash, this strong
	{ "PulseR", { "combatPulseInR", "combatPulseOutR" }, 0.89 },
	{ "PulseG", { "combatPulseInG", "combatPulseOutG" }, 0.79 },
	{ "PulseB", { "combatPulseInB", "combatPulseOutB" }, 0.34 },
	-- The small lines over and under the words: their font ("same": the
	-- words'), their size (times the one they'd have) and color ("auto": the
	-- words' in a lighter shade under, a pale gray over; "custom": SmallR...).
	{ "SmallFont", { "combatSmallFont" }, "same" },
	{ "SmallSize", { "combatSmallSize" }, 1 },
	{ "SmallColor", { "combatSmallColor" }, "auto" },
	{ "SmallR", { "combatSmallR" }, 0.8 },
	{ "SmallG", { "combatSmallG" }, 0.78 },
	{ "SmallB", { "combatSmallB" }, 0.72 },
	{ "IconShow", { "combatIconShowIn", "combatIconShowOut" }, false }, -- an icon before the words
	{ "Icon", { "combatIconIn", "combatIconOut" }, "event" }, -- ...a file or ID ("event": the event's own)
}
ns.CARD_FIELDS = FIELDS
local FIELD_OF = {}
for _, field in ipairs(FIELDS) do
	for _, key in ipairs(field[2]) do FIELD_OF[key] = field[1] end
end

-- The styles an event can start from, ready made: its settings that differ
-- from the base look's (the rest follow it). The Lower third is the base
-- look itself (the Zone name's); then the looks the events had on Battle
-- Vision's and Story Vision's Style tabs, each event starting from its own;
-- the rest the presets those tabs had.
local STYLES = {
	-- The four families every card starts in, one font (General's) and one
	-- thin outline among them, their place and color telling what kind of
	-- moment it is: Milestone (rare and big: the middle of the screen, gold),
	-- Place (where you are: the lower third, pale gold), Ticker (small news:
	-- the top bar's left end, pale gold, gold small lines) and Danger (the
	-- top bar's middle, red). Respite is Danger's calm other side.
	{ id = "milestone", name = "Milestone", look = { Place = "screen", Style = "title", Anim = "fade", Size = 44,
		Outline = 1, Hold = 3.5, SmallSize = 1.4, R = 1, G = 0.82, B = 0.35, PulseR = 1, PulseG = 0.82,
		PulseB = 0.35 } },
	-- (A rare: seldom, so its own and the biggest of them, the letters
	-- closing in, in the blue of a rare item's name (lighter, to read on
	-- a bright sky), the edges flashing.)
	{ id = "rare", name = "Rare", look = { Place = "screen", Style = "title", Anim = "track", Size = 60,
		Outline = 1, Hold = 4.5, SmallSize = 1.3, Pulse = 0.35, IconShow = true, R = 0.35, G = 0.65, B = 1,
		PulseR = 0, PulseG = 0.44, PulseB = 0.87 } },
	-- (Its words drawn at the chapter line's 65%: 52 for them to read.)
	{ id = "place", name = "Place", look = { Size = 52, Outline = 1, SmallSize = 1.3, R = 0.95, G = 0.88, B = 0.65,
		PulseR = 0.95, PulseG = 0.88, PulseB = 0.65 } },
	{ id = "ticker", name = "Ticker", look = { Place = "top", Align = "left", BarScale = 0.55, BarFallback = false,
		Style = "title", Anim = "fade", Outline = 1, Hold = 2.5, SmallColor = "custom", SmallR = 1, SmallG = 0.82,
		SmallB = 0.35, R = 0.95, G = 0.88, B = 0.65 } },
	{ id = "danger", name = "Danger", look = { Place = "top", BarScale = 0.62, BarFallback = false, Style = "title",
		Anim = "fade", Size = 34, Outline = 1, R = 0.89, G = 0.13, B = 0.22, Hold = 1.5, Pulse = 0.03 } },
	{ id = "third", name = "Lower third", look = { Outline = 0 } },
	{ id = "combat", name = "Combat", look = { Place = "top", BarScale = 0.62, BarFallback = false, Style = "title",
		Anim = "fade", Size = 34, R = 0.89, G = 0.13, B = 0.22, Hold = 1, Pulse = 0.03 } },
	{ id = "respite", name = "Respite", look = { Place = "top", BarScale = 0.62, BarFallback = false, Style = "title",
		Anim = "fade", Size = 34, Outline = 1, R = 0.71, G = 0.73, B = 0.51, Hold = 1, Pulse = 0.01, PulseR = 0.71, PulseG = 0.73,
		PulseB = 0.51 } }, -- (#B5BA81)
	{ id = "boss", name = "Boss", look = { BarScale = 0.62, Size = 44, Outline = 0, R = 0.85, G = 0.71, B = 0.35,
		Hold = 2.5, PulseR = 0.85, PulseG = 0.71, PulseB = 0.35 } },
	{ id = "journal", name = "Journal", look = { Anim = "type", Size = 30, Outline = 0, Hold = 10, R = 0.85, G = 0.78,
		B = 0.6 } },
	{ id = "title", name = "Title", look = { Place = "screen", Style = "title", Anim = "fade", Size = 32, Hold = 4,
		R = 1, G = 0.86, B = 0.6 } },
	{ id = "alert", name = "Alert", look = { Place = "screen", Style = "title", Anim = "fade", Size = 32, Hold = 4,
		R = 1, G = 0.3, B = 0.2 } },
	{ id = "death", name = "Death", look = { Style = "banner", Anim = "fade", Size = 60, Hold = 4,
		R = 0.72, G = 0.11, B = 0.14 } },
	-- (Death's gold other side: a win, or coming back.)
	{ id = "victory", name = "Victory", look = { Style = "banner", Anim = "fade", Size = 60, Hold = 4,
		R = 0.93, G = 0.76, B = 0.3 } },
	{ id = "film", name = "Film", look = { Place = "screen", Style = "title", Anim = "fade", Font = "morpheus",
		Size = 40 } },
	{ id = "reel", name = "Reel", look = { Place = "bottom", Style = "title", Anim = "reveal" } },
	-- (A thin dark outline and bigger small lines: Morpheus is thin, and
	-- hard to read on a bright sky without them.)
	{ id = "storybook", name = "Storybook", look = { Place = "screen", Font = "morpheus", Outline = 1, Shadow = "on",
		Anim = "type", Size = 40, SmallSize = 1.4, R = 0.96, G = 0.88, B = 0.7 } },
	{ id = "minimal", name = "Minimal", look = { Place = "screen", Style = "subtitle", Font = "friz", Anim = "fade" } },
	{ id = "arcade", name = "Arcade", look = { Place = "screen", Style = "title", Font = "skurri", Size = 46,
		Outline = 2, Pulse = 0.9, IconShow = true, R = 0.94, G = 0.62, B = 0.15, PulseR = 0.94, PulseG = 0.62,
		PulseB = 0.15 } },
	{ id = "quiet", name = "Quiet", look = { Place = "top", Align = "right", Style = "chapter", BarScale = 0.45,
		Hold = 2 } },
}
ns.CARD_STYLES = STYLES
local STYLE_BY_ID = {}
for _, style in ipairs(STYLES) do STYLE_BY_ID[style.id] = style end
ns.CARD_STYLE_BY_ID = STYLE_BY_ID
-- The style each event starts from ("follow": the one its parent starts
-- from).
local BASES = { combatIn = "danger", combatOut = "respite", attack = "danger", death = "death",
	levelUp = "milestone", achievement = "milestone", cleared = "milestone", discover = "milestone",
	quest = "milestone", battleground = "place",
	zone = "place", subzone = "follow", departure = "follow", arrival = "follow", login = "place", boss = "place", duel = "place",
	time = "milestone",
	reputation = "ticker", collect = "ticker", profession = "ticker", rested = "ticker",
	streak = "ticker", rare = "rare", bossDown = "victory", felled = "victory", revived = "victory" }
-- (What each started from before the families, for the update moving
-- yours onto them: Core.lua's cardsV7.)
ns.CARD_OLD_BASES = { combatIn = "combat", boss = "boss", zone = "third", login = "journal", time = "title",
	attack = "alert", duel = "third", cleared = "boss", discover = "storybook", rested = "quiet", levelUp = "title",
	achievement = "title", reputation = "quiet", collect = "quiet", profession = "quiet", quest = "journal",
	rare = "alert", battleground = "title", streak = "combat" }
for _, field in ipairs(FIELDS) do
	DEFAULTS["card" .. field[1]] = field[3]
	for _, event in ipairs(EVENTS) do DEFAULTS["card" .. field[1] .. "_" .. event.id] = "default" end
	for _, style in ipairs(STYLES) do DEFAULTS["cardLook" .. field[1] .. "_" .. style.id] = "default" end
end
for _, event in ipairs(EVENTS) do DEFAULTS["cardBase_" .. event.id] = BASES[event.id] end
for _, event in ipairs(EVENTS) do
	if event.inFight then DEFAULTS["cardFight_" .. event.id] = event.inFight end
end
DEFAULTS.cardAlign_rested = "center" -- (the Ticker's top bar, in its middle)
DEFAULTS.cardAlign_streak = "center"

-- All the cards bigger or smaller (their words' size, not a bar's): for a
-- big or wide screen.
DEFAULTS.cardScale = 1
-- Each row's Always (its Show in row's: ns.CINE_SHOW_SETTING), on to start with.
for _, event in ipairs(EVENTS) do
	DEFAULTS["cardAlways_" .. event.id] = true
	ns.CINE_SHOW_SETTING[ROW .. event.id] = "cardAlways_" .. event.id
end
-- The font, outline and shadow start on the Style hub's General page's.
do
	local shared = ns.SHARED_STYLE
	local suffixes = { "" }
	for _, event in ipairs(EVENTS) do suffixes[#suffixes + 1] = "_" .. event.id end
	for _, suffix in ipairs(suffixes) do
		shared["cardFont" .. suffix] = { kind = "font", own = "game" }
		shared["cardOutline" .. suffix] = { kind = "outline", own = 1 }
		shared["cardShadow" .. suffix] = { kind = "shadow", own = "game" }
	end
	for _, style in ipairs(STYLES) do
		shared["cardLookFont_" .. style.id] = { kind = "font", own = "game" }
		shared["cardLookOutline_" .. style.id] = { kind = "outline", own = 1 }
		shared["cardLookShadow_" .. style.id] = { kind = "shadow", own = "game" }
	end
end

-- A look setting's key for an event (nil: the base look's).
local function Key(field, id)
	return id and "card" .. field .. "_" .. id or "card" .. field
end
ns.CardKey = Key

-- A style's setting's key (your change to it).
local function StyleKey(field, style)
	return "cardLook" .. field .. "_" .. style
end
ns.CardStyleKey = StyleKey

-- Whether a style has a setting changed from how it comes.
function ns.CardStyleIsOwn(style, field, db)
	local value = (db or ns.db or DEFAULTS)[StyleKey(field, style)]
	return value ~= nil and value ~= "default"
end

-- Whether an event has a setting of its own (else it follows).
-- (One it comes with isn't yours: Rested's place in the middle of the bar.)
function ns.CardIsOwn(id, field, db)
	local key = Key(field, id)
	local value = (db or ns.db or DEFAULTS)[key]
	return value ~= nil and value ~= "default" and value ~= DEFAULTS[key]
end

-- The style an event starts from (a STYLES id): its own, else its
-- parent's. ("default", the Default style's, was the Lower third's look.)
-- source: the settings to read (else the saved ones).
function ns.CardBase(id, source)
	source = source or ns.GetDB() or DEFAULTS
	local event = BY_ID[id]
	while event do
		local base = source["cardBase_" .. event.id]
		if base ~= nil and base ~= "follow" then return STYLE_BY_ID[base] and base or "third" end
		event = BY_ID[event.parent]
	end
	return "third"
end

-- The events that start from a style (a subzone following the zone's too).
function ns.CardStyleUsers(style)
	local list = {}
	for _, event in ipairs(EVENTS) do
		if ns.CardBase(event.id) == style then list[#list + 1] = event end
	end
	return list
end

-- A style's setting from source: your change, else as it comes, else the
-- base look's.
local function ResolveStyle(source, style, field)
	local value = source[StyleKey(field, style)]
	if value ~= nil and value ~= "default" then return value end
	local look = STYLE_BY_ID[style] and STYLE_BY_ID[style].look
	if look and look[field] ~= nil then return look[field] end
	return source[Key(field)]
end

-- A look setting from source for an event (nil: the base look's): its own,
-- else its parent's, else the style it starts from's.
local function Resolve(source, id, field)
	local event = BY_ID[id]
	while event do
		local value = source[Key(field, event.id)]
		if value ~= nil and value ~= "default" then return value end
		event = BY_ID[event.parent]
	end
	if not id then return source[Key(field)] end
	return ResolveStyle(source, ns.CardBase(id, source), field)
end

-- A look setting's value for an event, as it shows (General's where it's on
-- General). The defaults while Style's off.
function ns.CardValue(id, field)
	return Resolve(ns.StyleLook("cards"), id, field)
end

-- A look setting as saved, for the options' controls (General's "general"
-- kept).
function ns.CardRaw(id, field)
	return Resolve(ns.GetDB() or DEFAULTS, id, field)
end

-- A style's setting as saved, for the Card Types tab's controls (shipped: as it
-- comes, your changes left out).
function ns.CardStyleRaw(style, field, shipped)
	if shipped then
		local look = STYLE_BY_ID[style] and STYLE_BY_ID[style].look
		if look and look[field] ~= nil then return look[field] end
		return DEFAULTS[Key(field)]
	end
	return ResolveStyle(ns.GetDB() or DEFAULTS, style, field)
end

-- A style's look as the card drawing reads it, for the Card Types tab's preview
-- (each made once). id: the event whose card it plays (for its icon).
-- (A field's value as the drawing reads it: the event's icon for "event";
-- sized: times the cards' scale, for a card on the screen.)
local function Drawn(field, value, id, sized)
	if field == "Icon" and value == "event" then value = BY_ID[id] and BY_ID[id].icon or MAP end
	if field == "Outline" then value = tonumber(value) or 0 end
	if sized and field == "Size" then
		value = (tonumber(value) or 36) * (tonumber(ns.db and ns.db.cardScale) or 1) * ns.VisionTextScale()
	end
	return value
end

local styleLooks = {}
function ns.CardStyleLook(style, id)
	local look = styleLooks[style .. ":" .. (id or "")]
	if not look then
		look = setmetatable({}, { __index = function(_, key)
			local field = FIELD_OF[key]
			if not field then return nil end
			return Drawn(field, ResolveStyle(ns.StyleLook("cards"), style, field), id)
		end })
		styleLooks[style .. ":" .. (id or "")] = look
	end
	return look
end

-- ...and as a real card of id's draws it, sized as the cards are: a card
-- playing in another style than its event's (a souls banner on a Duel card).
local cardLooks = {}
function ns.CardStyleCardLook(style, id)
	local look = cardLooks[style .. ":" .. (id or "")]
	if not look then
		look = setmetatable({}, { __index = function(_, key)
			local field = FIELD_OF[key]
			if not field then return nil end
			return Drawn(field, ResolveStyle(ns.StyleLook("cards"), style, field), id, true)
		end })
		cardLooks[style .. ":" .. (id or "")] = look
	end
	return look
end

-- An event's look as the card drawing reads it (its settings' names:
-- FIELDS), made once for each.
local looks = {}
function ns.CardLook(id)
	local look = looks[id or ""]
	if not look then
		look = setmetatable({}, { __index = function(_, key)
			local field = FIELD_OF[key]
			if not field then return nil end
			return Drawn(field, ns.CardValue(id, field), id, true)
		end })
		looks[id or ""] = look
	end
	return look
end

-- An event's look with some of its settings swapped for one card ({ field =
-- value }, by FIELDS' names): a moment that can't show where its event's
-- others do (a battleground's result, with the game's scoreboard in the
-- middle of the screen).
function ns.CardLookWith(id, swap)
	local own = {}
	for _, field in ipairs(FIELDS) do
		if swap[field[1]] ~= nil then
			for _, key in ipairs(field[2]) do own[key] = swap[field[1]] end
		end
	end
	return setmetatable(own, { __index = ns.CardLook(id) })
end

-- Whether an event's row is ticked (the page on, and what it needs).
function ns.CardOn(id)
	local event = BY_ID[id]
	if not (event and ns.Setting("cards") and ns.Setting(event.on)) then return false end
	return not event.needs or ns.CardOn(event.needs)
end

-- Whether an event's card may show now, and why not: its row ticked, and its
-- Show in row (read with the rules' entering or leaving true for a fight's
-- edge, and cine: CineMode as the fight began).
function ns.CardAllowed(id, edge, cine)
	local event = BY_ID[id]
	if not event then return false, "no such card" end
	if not ns.Setting("cards") then return false, "Card Vision is off" end
	if not ns.Setting(event.on) then return false, event.name .. " is unticked" end
	if event.needs and not ns.CardOn(event.needs) then return false, BY_ID[event.needs].name .. " is unticked" end
	if cine == nil then cine = ns.lastCinematic and true or false end
	ns.combatEdge, ns.combatEdgeCine = edge, cine
	local ok, shows = pcall(ns.RowOnNow, ROW .. id, nil, true)
	ns.combatEdge = nil
	if not ok then return false, "its Show in row errored" end
	if not shows then return false, "its Show in row says not now" end
	return true
end

-- The real cards, one at a time over the whole screen (an overlay, kept with
-- the UI hidden).
local screen, current
local waiting = {}
ns.Cards = {}
local function Screen()
	if not screen then
		screen = CreateFrame("Frame", "CinematicCard", UIParent)
		screen:SetAllPoints(UIParent)
		screen:SetFrameStrata("LOW")
		screen:EnableMouse(false)
		ns.AddOverlay(screen)
	end
	return screen
end

local Show
-- The card done (or cut short): the next one waiting, if not waiting too long
-- (one held through a fight waits its turn however long).
local function Next()
	current = nil
	while #waiting > 0 do
		local card = table.remove(waiting, 1)
		if card.afterFight or GetTime() - card.at <= WAIT_MAX then
			Show(card)
			return
		end
	end
end
function Show(card)
	current = card
	local look = card.look or ns.CardLook(card.id) -- (look: the Card Types tab's Test, a style's)
	ns.PlayCard(Screen(), look, UIParent:GetWidth(), UIParent:GetHeight(), 1, card, Next)
	-- (Its own sound, or its event's rules on the Sounds tab: CombatSoundRules.lua.)
	if card.sound then pcall(card.sound) elseif ns.PlayCardCueSound then pcall(ns.PlayCardCueSound, card.id) end
end

-- Cards held through a fight (its In a fight: Wait till after), the newest
-- of each event's: they show CALM_AFTER seconds out of it, so a feign death
-- or vanish straight back into the fight holds them on. fightAt: the last
-- moment seen in one.
local held, fightAt, checking = {}, -math.huge, false
local function Fighting()
	if (InCombatLockdown and InCombatLockdown()) or ns.Flag(UnitAffectingCombat("player")) then
		fightAt = GetTime()
		return true
	end
	return false
end
-- In a fight, or not yet CALM_AFTER seconds out of one.
local function Unsettled()
	return Fighting() or GetTime() - fightAt < CALM_AFTER
end
local function Release()
	local list = {}
	for id, card in pairs(held) do
		held[id] = nil
		if GetTime() - card.heldAt <= HELD_MAX then list[#list + 1] = card end
	end
	-- (The most important first, the rest waiting behind it in turn.)
	table.sort(list, function(a, b) return BY_ID[a.id].priority > BY_ID[b.id].priority end)
	for _, card in ipairs(list) do
		card.afterFight = true
		ns.Cards.Fire(card.id, card)
	end
end
local function Check()
	checking = false
	if not next(held) then return end
	local wait = Fighting() and 1 or CALM_AFTER - (GetTime() - fightAt)
	if wait > 0 then
		checking = true
		C_Timer.After(math.max(wait, 0.1), Check)
	else
		Release()
	end
end
local fights = CreateFrame("Frame")
fights:RegisterEvent("PLAYER_REGEN_ENABLED")
fights:SetScript("OnEvent", function() fightAt = GetTime() end)

-- An event's card: card { name, sub, meta, picture..., sound = function()
-- played with it, delay = seconds before it fires, edge and cine for a
-- fight's }. force: whatever the page says (a Test, or already asked:
-- ns.CardAllowed). True if it shows or waits to.
function ns.Cards.Fire(id, card, force)
	local event = BY_ID[id]
	if not (event and card) then return false end
	if card.delay and card.delay > 0 then
		local delay = card.delay
		card.delay = nil
		C_Timer.After(delay, function() ns.Cards.Fire(id, card, force) end)
		return true
	end
	if not force and not ns.CardAllowed(id, card.edge, card.cine) then return false end
	-- (In a fight or just out of one: shown now, held till after, or not at all.)
	local inFight = not force and not card.afterFight and event.inFight and ns.db["cardFight_" .. id]
	if inFight and inFight ~= "show" and Unsettled() then
		if inFight ~= "wait" then return false end
		card.id, card.heldAt = id, GetTime()
		held[id] = card
		if not checking then Check() end
		return true
	end
	card.id, card.priority, card.at = id, event.priority, GetTime()
	-- (A more important one playing, or this one held through a fight: it
	-- waits, in place of one of its own.)
	if current and (current.priority > card.priority or card.afterFight) then
		for i = #waiting, 1, -1 do
			if waiting[i].id == id then table.remove(waiting, i) end
		end
		waiting[#waiting + 1] = card
		return true
	end
	-- (One playing: it fades out quickly first, then this one shows.)
	if current and screen and screen:GetScript("OnUpdate") then
		for i = #waiting, 1, -1 do
			if waiting[i].id == id then table.remove(waiting, i) end
		end
		table.insert(waiting, 1, card)
		ns.CutCard(screen)
		return true
	end
	Show(card)
	return true
end

-- The cards held through a fight now ({ id = card }), and seconds till they
-- show (nil: none held, or still in the fight), for /cine debug cards.
function ns.Cards.Held()
	if not next(held) then return held, nil end
	return held, not Fighting() and math.max(0, CALM_AFTER - (GetTime() - fightAt)) or nil
end

-- An event's card cut short if it's playing, dropped if it's waiting.
function ns.Cards.Cut(id)
	for i = #waiting, 1, -1 do
		if waiting[i].id == id then table.remove(waiting, i) end
	end
	if current and current.id == id then ns.CutCard(screen) end
end

-- The card playing now ({ id, name... }), for Inspect (Why.lua).
function ns.Cards.Current()
	return current
end

-- Each event's made-up card, for the Test buttons and the previews: each
-- file hearing an event puts its own in (ns.CardSamples[id] = function()).
ns.CardSamples = ns.CardSamples or {}
local samples = ns.CardSamples
samples.combatIn = function()
	return { name = ns.CardWords("combatTextIn"),
		sound = function() ns.PlayCombatCueSound("enter", ns.lastCinematic and true or false) end }
end
samples.combatOut = function()
	return { name = ns.CardWords("combatTextOut"),
		sound = function() ns.PlayCombatCueSound("leave", ns.lastCinematic and true or false) end }
end
samples.boss = function()
	local card = ns.BossSampleCard()
	card.sound = function() ns.PlayCombatCueSound("enter", ns.lastCinematic and true or false) end
	return card
end

-- Each souls event's words to pick from, in its Settings tab's order (%s:
-- its name in capitals; the first one's while it isn't known).
ns.SOULS_WORDS = {
	bossDown = { { "victory", "VICTORY ACHIEVED" }, { "vanquished", "FOE VANQUISHED" },
		{ "felled", "ENEMY FELLED" }, { "named", "%s FELLED" } },
	felled = { { "felled", "ENEMY FELLED" }, { "vanquished", "FOE VANQUISHED" }, { "named", "%s FELLED" } },
	revived = { { "restored", "VITALITY RESTORED" }, { "returned", "RETURNED FROM DEATH" } },
}
-- A souls event's words (great: a raid's or world boss's, ENEMY FELLED
-- growing to GREAT ENEMY FELLED), and whether the name's in them.
function ns.SoulsWords(id, name, great)
	local db = ns.GetDB() or DEFAULTS
	local pick = db[id .. "Words"]
	if pick == "custom" then
		local own = type(db[id .. "Text"]) == "string" and db[id .. "Text"]:match("^%s*(.-)%s*$") or ""
		if own ~= "" then return own, false end
	end
	local list = ns.SOULS_WORDS[id]
	local words = list[1][2]
	for _, entry in ipairs(list) do
		if entry[1] == pick then words = entry[2] end
	end
	if words:find("%s", 1, true) then
		if name and name ~= "" then return L[words]:format(name:upper()), true end
		words = list[1][2]
	end
	if great and words == "ENEMY FELLED" then words = "GREAT ENEMY FELLED" end
	return L[words], false
end

-- A win's (or lost: a loss's) card as a souls banner if its event says so
-- (its Settings tab's Banner): words big, its own small line under them, in
-- the Victory style's look (Death's for a loss).
function ns.SoulsCard(id, card, words, lost)
	if (ns.GetDB() or DEFAULTS)["cardSouls_" .. id] ~= "souls" then return card end
	card.name, card.meta = L[words], nil
	card.look = ns.CardStyleCardLook(lost and "death" or "victory", id)
	return card
end

-- The Duel card at a moment: "ask" (you challenge), "asked" (you're
-- challenged), "start", "won" or "lost". other: the other duelist's name
-- (nil: not known); fled: the loser ran.
local DUEL_MOMENT = { ask = "cardDuelAsk", asked = "cardDuelAsked", start = "cardDuelStart", won = "cardDuelResult",
	lost = "cardDuelResult" }
ns.DUEL_MOMENT = DUEL_MOMENT
-- (Each with its moment's sound: its rule on the Sounds tab.)
function ns.DuelCard(moment, other, fled)
	local name = other or L["Duel"]
	local card
	if moment == "ask" then
		card = { name = name, sub = L["You challenge them to a duel"] }
	elseif moment == "asked" then
		card = { name = name, sub = L["Challenges you to a duel"] }
	elseif moment == "start" then
		local me = UnitName("player") or ""
		card = { name = other and L["%s vs %s"]:format(me, other) or me, sub = ns.CardWords("duelTextStart") }
	elseif moment == "won" then
		card = { name = ns.CardWords("duelTextWon"),
			sub = fled and L["%s fled"]:format(name) or L["Over %s"]:format(name) }
	else
		card = { name = ns.CardWords("duelTextLost"),
			sub = fled and L["You fled from %s"]:format(name) or L["By %s"]:format(name) }
	end
	if moment == "won" then
		ns.SoulsCard("duel", card, "VICTORY ACHIEVED")
	elseif moment == "lost" then
		ns.SoulsCard("duel", card, "DEFEATED", true)
	end
	card.sound = function() ns.PlayCardCueSound("duel", moment) end
	return card
end
-- (Made up: your target's name if it's a player.)
local function SampleRival()
	local other = UnitExists("target") and UnitIsPlayer("target") and UnitName("target") or "Unholy"
	if issecretvalue and issecretvalue(other) then other = "Unholy" end
	return other
end
samples.duel = function() return ns.DuelCard("won", SampleRival()) end

-- A card with moments plays each in turn on its Test (the Duel card's).
ns.CardSequences = {}
ns.CardSequences.duel = function()
	local other = SampleRival()
	local list = {}
	for _, moment in ipairs({ "ask", "asked", "start", "won", "lost" }) do
		list[#list + 1] = ns.DuelCard(moment, other)
	end
	return list
end

function ns.CardSample(id)
	local make = samples[id]
	return make and make() or { name = L[BY_ID[id] and BY_ID[id].name or "Cards"] }
end

-- Test: an event's made-up card on your screen now, whatever the page says.
-- A card with moments plays each in turn, its hold and 2 seconds apart; its
-- Test again meanwhile stops it (ns.CardTestRunning: its button says Stop).
local testRun
function ns.CardTestRunning(id)
	return testRun ~= nil and testRun.id == id
end
function ns.CardTest(id)
	local sequence = ns.CardSequences[id]
	if testRun then
		local was = testRun.id
		testRun.stopped, testRun = true, nil
		ns.Cards.Cut(was)
		if was == id then return end
	end
	-- (Flight departure's Test plays its progress line too, on a made-up flight: FlightLine.lua.)
	if id == "departure" and ns.FlightLineTest then ns.FlightLineTest() end
	if not sequence then
		ns.Cards.Fire(id, ns.CardSample(id), true)
		return
	end
	local run, list, i = { id = id }, sequence(), 0
	testRun = run
	local function Step()
		if run.stopped then return end
		i = i + 1
		if not list[i] then
			testRun = nil
			return
		end
		ns.Cards.Fire(id, list[i], true)
		C_Timer.After((tonumber(ns.CardLook(id).combatHoldIn) or 3) + 2, Step)
	end
	Step()
end

-- Battle Vision's and Story Vision's settings, onto the Cards page's: their
-- switches into the rows' ticks, their Show in rows to the rows', and each
-- look setting you'd changed onto its event (the font, outline and shadow
-- Story Vision's moments shared, onto the base look: ns.SpreadCardBase
-- moves them onto the events after). t: the saved
-- settings, or a saved profile (only what it has); main: the saved ones.
local OLD_LOOKS = {
	combatIn = { Place = { "combatPlace", "top" }, BarScale = { "combatBarScale", 0.62 },
		Align = { "combatAlign", "center" }, Style = { "combatStyle", "title" }, Anim = { "combatAnim", "fade" },
		BarFallback = { "combatBarFallback", false }, Font = { "combatFont", "general" }, Size = { "combatSize", 34 },
		Outline = { "combatOutline", -1 }, Shadow = { "combatShadow", "general" },
		OutlineRGB = { "combatOutline", { 0, 0, 0 } }, RGB = { "combatIn", { 0.89, 0.13, 0.22 } },
		Hold = { "combatHoldIn", 1 }, Pulse = { "combatPulseIn", 0.03 },
		PulseRGB = { "combatPulseIn", { 0.89, 0.79, 0.34 } }, IconShow = { "combatIconShowIn", false },
		Icon = { "combatIconIn", "Interface\\Icons\\Ability_DualWield" } },
	combatOut = { Place = { "combatPlace", "top" }, BarScale = { "combatBarScale", 0.62 },
		Align = { "combatAlign", "center" }, Style = { "combatStyle", "title" }, Anim = { "combatAnim", "fade" },
		BarFallback = { "combatBarFallback", false }, Font = { "combatFont", "general" }, Size = { "combatSize", 34 },
		Outline = { "combatOutline", -1 }, Shadow = { "combatShadow", "general" },
		OutlineRGB = { "combatOutline", { 0, 0, 0 } }, RGB = { "combatOut", { 0.49, 0.67, 0.73 } },
		Hold = { "combatHoldOut", 1 }, Pulse = { "combatPulseOut", 0.01 },
		PulseRGB = { "combatPulseOut", { 0.49, 0.67, 0.73 } }, IconShow = { "combatIconShowOut", false },
		Icon = { "combatIconOut", 132320 } },
	boss = { Place = { "combatBossPlace", "third" }, BarScale = { "combatBossBarScale", 0.62 },
		Align = { "combatBossAlign", "center" }, Style = { "combatBossStyle", "chapter" },
		Anim = { "combatBossAnim", "track" }, BarFallback = { "combatBossBarFallback", true },
		Font = { "combatBossFont", "general" }, Size = { "combatBossSize", 44 }, Outline = { "combatBossOutline", -1 },
		Shadow = { "combatBossShadow", "general" }, OutlineRGB = { "combatBossOutline", { 0, 0, 0 } },
		RGB = { "combatBoss", { 0.85, 0.71, 0.35 } }, Hold = { "combatBossHold", 2.5 }, Pulse = { "combatBossPulse", 0 },
		PulseRGB = { "combatBossPulse", { 0.85, 0.71, 0.35 } }, IconShow = { "combatBossIconShow", false },
		Icon = { "combatBossIcon", "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" } },
	zone = { Place = { "storyZonePlace", "third" }, Align = { "storyZoneAlign", "center" },
		Style = { "storyZoneStyle", "chapter" }, Anim = { "storyZoneAnim", "track" }, Size = { "storyZoneSize", 36 },
		Hold = { "storyZoneHold", 3 }, RGB = { "storyZone", { 1, 0.82, 0 } }, IconShow = { "storyZoneIcon", false } },
	login = { Place = { "storyRecapPlace", "third" }, Align = { "storyRecapAlign", "center" },
		Style = { "storyRecapStyle", "chapter" }, Anim = { "storyRecapAnim", "type" }, Size = { "storyRecapSize", 30 },
		Hold = { "storyRecapHold", 10 }, RGB = { "storyRecap", { 0.85, 0.78, 0.6 } },
		IconShow = { "storyRecapBook", false } },
	time = { Hold = { "storyTimeHold", 4 }, RGB = { "storyTime", { 1, 0.86, 0.6 } } },
	attack = { Hold = { "storyAttackHold", 4 }, RGB = { "storyAttack", { 1, 0.3, 0.2 } } },
	death = { Hold = { "storyBannerHold", 4 }, RGB = { "storyBanner", { 0.72, 0.11, 0.14 } } },
	[""] = { Font = { "storyFont", "general" }, Outline = { "storyOutline", -1 }, Shadow = { "storyShadow", "general" },
		OutlineRGB = { "storyOutline", { 0, 0, 0 } } },
}
-- (A color's three settings: the old ones' prefix and R, G, B; new ones' names.)
local TRIPLES = { RGB = { "R", "G", "B" }, OutlineRGB = { "OutlineR", "OutlineG", "OutlineB" },
	PulseRGB = { "PulseR", "PulseG", "PulseB" } }
local OLD_ROWS = { ["vision:combat"] = { "combatIn", "combatOut" }, ["vision:boss"] = { "boss" } }
local STORY_ROWS = { "storyRecap", "storyZoneCard", "timeOfDayMessage", "timeOfDayChange", "chatAttackAlert",
	"cardDeathOn" }

function ns.MigrateCards(t, main)
	-- Each look setting changed from its old default: onto the event (or the
	-- base look).
	for id, olds in pairs(OLD_LOOKS) do
		local suffix = id ~= "" and "_" .. id or ""
		for name, old in pairs(olds) do
			local triple = TRIPLES[name]
			if triple then
				local values, changed = {}, false
				for i, channel in ipairs({ "R", "G", "B" }) do
					values[i] = t[old[1] .. channel]
					if values[i] ~= nil and values[i] ~= old[2][i] then changed = true end
				end
				if changed then
					for i, field in ipairs(triple) do
						if values[i] ~= nil then t["card" .. field .. suffix] = values[i] end
					end
				end
			else
				local value = t[old[1]]
				if value ~= nil and value ~= old[2] then
					-- (Last time under the zone name: a place of its own then; now a tick.)
					if name == "Place" and value == "zone" then
						t.storyRecapUnder = true
					else
						t["card" .. name .. suffix] = value
					end
				end
			end
		end
	end
	-- Battle Vision's Show in rows, each onto its events'; its Always too.
	for old, ids in pairs(OLD_ROWS) do
		for _, list in pairs(t) do
			if type(list) == "table" and list[old] ~= nil then
				for _, id in ipairs(ids) do list[ROW .. id] = list[old] end
			end
		end
	end
	if t.combatAlways ~= nil then
		t.cardAlways_combatIn, t.cardAlways_combatOut = t.combatAlways, t.combatAlways
	end
	if t.combatBossAlways ~= nil then t.cardAlways_boss = t.combatBossAlways end
	-- The death banner's None: its row unticked (its words as they were, else YOU DIED).
	if t.deathBannerStyle ~= nil then
		t.cardDeathOn = t.deathBannerStyle ~= "none"
		if t.deathBannerStyle == "none" then t.deathBannerStyle = "youdied" end
	end
	if not main then return end
	-- The two pages' switches: Battle Vision's into its rows' ticks, Story
	-- Vision's into its; the page on if either was.
	local battle, story = t.combatVision == true, t.storyVision ~= false
	if not battle then
		t.combatOnEnter, t.combatOnLeave, t.cardBossOn = false, false, false
	else
		if t.combatOnEnter == nil then t.combatOnEnter = true end
		if t.combatOnLeave == nil then t.combatOnLeave = true end
		t.cardBossOn = t.combatBossPull ~= false or t.combatBossTarget == true or t.combatBossNear == true
	end
	if not story then
		for _, key in ipairs(STORY_ROWS) do t[key] = false end
	end
	t.cards = battle or story
end

-- Entering and Leaving combat were one Combat card for a while (1.9.12),
-- going in and coming out its ticks (combatOnEnter, combatOnLeave); two
-- again. Its look, starting style, Always and Show in rows onto both
-- (Leaving's starting style stays Respite unless Combat's was changed); its
-- row and ticks onto their rows' ticks. t: the saved settings or a saved
-- profile (only what it has; raw).
function ns.SplitCombatCard(t)
	local function Copy(old, inKey, outKey)
		local value = rawget(t, old)
		if value == nil then return end
		if rawget(t, inKey) == nil then t[inKey] = value end
		if outKey and rawget(t, outKey) == nil then t[outKey] = value end
		t[old] = nil
	end
	for _, field in ipairs(FIELDS) do
		Copy(Key(field[1], "combat"), Key(field[1], "combatIn"), Key(field[1], "combatOut"))
	end
	local base = rawget(t, "cardBase_combat")
	Copy("cardBase_combat", "cardBase_combatIn", base ~= "combat" and "cardBase_combatOut" or nil)
	Copy("cardAlways_combat", "cardAlways_combatIn", "cardAlways_combatOut")
	for _, list in pairs(t) do
		if type(list) == "table" and list[ROW .. "combat"] ~= nil then
			local value = list[ROW .. "combat"]
			if list[ROW .. "combatIn"] == nil then list[ROW .. "combatIn"] = value end
			if list[ROW .. "combatOut"] == nil then list[ROW .. "combatOut"] = value end
			list[ROW .. "combat"] = nil
		end
	end
	-- (Its ticks were on to start with; the rows start off.)
	local on, enter, leave = rawget(t, "cardCombatOn"), rawget(t, "combatOnEnter"), rawget(t, "combatOnLeave")
	if on == true then
		t.combatOnEnter, t.combatOnLeave = enter ~= false, leave ~= false
	elseif on == false then
		t.combatOnEnter, t.combatOnLeave = false, false
	elseif enter ~= nil or leave ~= nil then
		t.combatOnEnter, t.combatOnLeave = nil, nil
	end
	t.cardCombatOn = nil
end

-- The Default style (the base look, on the Style tab until 1.9.13) is gone
-- from the page, and the Lower third is a style of its own: each card's
-- setting that would look different now (one it took from the Default
-- style, changed or not) becomes its own, so nothing does; the base look
-- back at its defaults, and a starting style of "default" the Lower third.
-- t: the saved settings, a saved profile or an imported one (only what it
-- has; raw).
local OLD_OWN = { cardOutline_zone = 0 } -- (own settings' old defaults: a profile without one had that)
function ns.SpreadCardBase(t)
	local function Get(key)
		local value = rawget(t, key)
		if value == nil then return DEFAULTS[key] end
		return value
	end
	for _, event in ipairs(EVENTS) do
		local baseKey = "cardBase_" .. event.id
		local base = Get(baseKey)
		-- (A subzone following the zone: it gets it from there.)
		if not (event.parent and base == "follow") then
			-- (Before: the Default style's ("default", "third" for a while) had no
			-- look of its own: the base look's.)
			local was = (base ~= "default" and base ~= "third" and STYLE_BY_ID[base]) and STYLE_BY_ID[base].look or {}
			local now = STYLE_BY_ID[base == "default" and "third" or base]
			now = now and now.look or {}
			for _, field in ipairs(FIELDS) do
				local name = field[1]
				local own = rawget(t, Key(name, event.id))
				if own == nil then own = OLD_OWN[Key(name, event.id)] or DEFAULTS[Key(name, event.id)] end
				if own == nil or own == "default" then
					local before = was[name]
					if before == nil then before = Get(Key(name)) end
					local after = now[name]
					if after == nil then after = DEFAULTS[Key(name)] end
					if before ~= after then t[Key(name, event.id)] = before end
				end
			end
		end
		if base == "default" then t[baseKey] = "third" end
	end
	-- (The zone's no outline, its own for a while: the Lower third's now.)
	local zoneOutline = rawget(t, "cardOutline_zone")
	if zoneOutline == nil then zoneOutline = OLD_OWN.cardOutline_zone end
	if zoneOutline == 0 and Get("cardBase_zone") == "third" then t.cardOutline_zone = nil end
	for _, field in ipairs(FIELDS) do t[Key(field[1])] = nil end
end
