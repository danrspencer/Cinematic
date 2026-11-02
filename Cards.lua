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
-- The look: the Default style's settings (card<Field>), and each event's own
-- where it has one (card<Field>_<id>; "default": its parent's, else the
-- Default style's). As Heal Vision's roles have theirs (<key>_<ROLE>), but
-- setting by setting: an event can have its own color and still follow the
-- Default style's font. (The CardsPage.lua pages edit them.)

local _, ns = ...
local L = ns.L
local DEFAULTS = ns.DEFAULTS

DEFAULTS.cards = true      -- the page's switch (off in Subtle: the no-visions module)
DEFAULTS.cardDeathOn = false -- the Death row (on in Cinema: YOU DIED as the death camera starts)
DEFAULTS.timeOfDayChange = true -- the Time of day row: its name and sound as it changes (off in Subtle, with the page)

local BOOK = "Interface\\Icons\\INV_Misc_Book_09"
local MAP = "Interface\\Icons\\INV_Misc_Map_01"
local ROW = "card:" -- (each event's Show in row: ROW .. id)
local WAIT_MAX = 6  -- seconds a card waits behind a more important one before it's dropped

-- The events, in the page's order: name, its row's tick (on: a setting of
-- its own, kept from before the page), priority (a higher one cuts in, the
-- same replaces, a lower one waits), its icon, the one it follows for its
-- look (parent) and the one it needs on to show at all (needs).
local EVENTS = {
	{ id = "combatIn", name = "Entering combat", on = "combatOnEnter", priority = 50,
		icon = "Interface\\Icons\\Ability_DualWield", fight = true },
	{ id = "combatOut", name = "Leaving combat", on = "combatOnLeave", priority = 50, icon = 132320, fight = true },
	{ id = "boss", name = "Boss", on = "cardBossOn", priority = 80,
		icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", fight = true },
	{ id = "zone", name = "Zone", on = "storyZoneCard", priority = 40, icon = MAP },
	{ id = "subzone", name = "Subzone", on = "storyZoneSubzones", priority = 40, icon = MAP, parent = "zone",
		needs = "zone" },
	{ id = "login", name = "Last time", on = "storyRecap", priority = 35, icon = BOOK },
	{ id = "time", name = "Time of day", on = "timeOfDayChange", priority = 20,
		icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
	{ id = "attack", name = "Under attack", on = "chatAttackAlert", priority = 60,
		icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
	{ id = "death", name = "Death", on = "cardDeathOn", priority = 100,
		icon = "Interface\\Icons\\Ability_Rogue_FeignDeath" },
}
ns.CARD_EVENTS = EVENTS
local BY_ID = {}
for _, event in ipairs(EVENTS) do BY_ID[event.id] = event end
ns.CARD_BY_ID = BY_ID

-- The look's settings: each field, the card drawing's settings it gives
-- (CombatVision.lua's: going in, coming out), and its Default style default.
local FIELDS = {
	{ "Place", { "combatPlace" }, "third" },     -- "screen", "top" or "bottom" bar, "third"
	{ "Align", { "combatAlign" }, "center" },    -- in a bar: "left", "center" or "right"
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
	{ "IconShow", { "combatIconShowIn", "combatIconShowOut" }, false }, -- an icon before the words
	{ "Icon", { "combatIconIn", "combatIconOut" }, "event" }, -- ...a file or ID ("event": the event's own)
}
ns.CARD_FIELDS = FIELDS
local FIELD_OF = {}
for _, field in ipairs(FIELDS) do
	for _, key in ipairs(field[2]) do FIELD_OF[key] = field[1] end
end

-- The styles an event can start from, ready made: its settings that differ
-- from the Default style's (the rest follow it). The first ones are the
-- looks the events had on Battle Vision's and Story Vision's Style tabs, each
-- event starting from its own (the Default style is the Zone name's look,
-- the Lower third); the rest the presets those tabs had.
local STYLES = {
	{ id = "combat", name = "Combat", look = { Place = "top", BarScale = 0.62, BarFallback = false, Style = "title",
		Anim = "fade", Size = 34, R = 0.89, G = 0.13, B = 0.22, Hold = 1, Pulse = 0.03 } },
	{ id = "respite", name = "Respite", look = { Place = "top", BarScale = 0.62, BarFallback = false, Style = "title",
		Anim = "fade", Size = 34, R = 0.49, G = 0.67, B = 0.73, Hold = 1, Pulse = 0.01, PulseR = 0.49, PulseG = 0.67,
		PulseB = 0.73 } },
	{ id = "boss", name = "Boss", look = { BarScale = 0.62, Size = 44, R = 0.85, G = 0.71, B = 0.35, Hold = 2.5,
		PulseR = 0.85, PulseG = 0.71, PulseB = 0.35 } },
	{ id = "journal", name = "Journal", look = { Anim = "type", Size = 30, Hold = 10, R = 0.85, G = 0.78, B = 0.6 } },
	{ id = "title", name = "Title", look = { Place = "screen", Style = "title", Anim = "fade", Size = 32, Hold = 4,
		R = 1, G = 0.86, B = 0.6 } },
	{ id = "alert", name = "Alert", look = { Place = "screen", Style = "title", Anim = "fade", Size = 32, Hold = 4,
		R = 1, G = 0.3, B = 0.2 } },
	{ id = "death", name = "Death", look = { Style = "banner", Anim = "fade", Size = 60, Hold = 4,
		R = 0.72, G = 0.11, B = 0.14 } },
	{ id = "film", name = "Film", look = { Place = "screen", Style = "title", Anim = "fade", Font = "morpheus",
		Size = 40 } },
	{ id = "reel", name = "Reel", look = { Place = "bottom", Style = "title", Anim = "reveal" } },
	{ id = "storybook", name = "Storybook", look = { Place = "screen", Font = "morpheus", Outline = 0, Shadow = "on",
		Anim = "type", R = 0.96, G = 0.88, B = 0.7 } },
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
-- The style each event starts from ("default": the Default style; "follow":
-- the one its parent starts from).
local BASES = { combatIn = "combat", combatOut = "respite", boss = "boss", zone = "default", subzone = "follow",
	login = "journal", time = "title", attack = "alert", death = "death" }
for _, field in ipairs(FIELDS) do
	DEFAULTS["card" .. field[1]] = field[3]
	for _, event in ipairs(EVENTS) do DEFAULTS["card" .. field[1] .. "_" .. event.id] = "default" end
end
for _, event in ipairs(EVENTS) do DEFAULTS["cardBase_" .. event.id] = BASES[event.id] end
-- Each row's Always (its Show in row's: ns.CINE_SHOW_SETTING), on to start with.
for _, event in ipairs(EVENTS) do
	DEFAULTS["cardAlways_" .. event.id] = true
	ns.CINE_SHOW_SETTING[ROW .. event.id] = "cardAlways_" .. event.id
end
-- The font, outline and shadow start on the Style hub's General page's.
do
	local shared = ns.SHARED_STYLE
	for _, suffix in ipairs({ "", "_combatIn", "_combatOut", "_boss", "_zone", "_subzone", "_login", "_time",
			"_attack", "_death" }) do
		shared["cardFont" .. suffix] = { kind = "font", own = "game" }
		shared["cardOutline" .. suffix] = { kind = "outline", own = 1 }
		shared["cardShadow" .. suffix] = { kind = "shadow", own = "game" }
	end
end

-- A look setting's key for an event (nil: the Default style's).
local function Key(field, id)
	return id and "card" .. field .. "_" .. id or "card" .. field
end
ns.CardKey = Key

-- Whether an event has a setting of its own (else it follows).
function ns.CardIsOwn(id, field, db)
	local value = (db or ns.db or DEFAULTS)[Key(field, id)]
	return value ~= nil and value ~= "default"
end

-- The style an event starts from ("default", or a STYLES id): its own,
-- else its parent's. source: the settings to read (else the saved ones).
function ns.CardBase(id, source)
	source = source or ns.GetDB() or DEFAULTS
	local event = BY_ID[id]
	while event do
		local base = source["cardBase_" .. event.id]
		if base ~= nil and base ~= "follow" then return STYLE_BY_ID[base] and base or "default" end
		event = BY_ID[event.parent]
	end
	return "default"
end

-- A look setting from source for an event (nil: the Default style's): its
-- own, else its parent's, else the style it starts from, else the Default
-- style's.
local function Resolve(source, id, field)
	local event = BY_ID[id]
	while event do
		local value = source[Key(field, event.id)]
		if value ~= nil and value ~= "default" then return value end
		event = BY_ID[event.parent]
	end
	local style = id and STYLE_BY_ID[ns.CardBase(id, source)]
	if style and style.look[field] ~= nil then return style.look[field] end
	return source[Key(field)]
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

-- An event's look as the card drawing reads it (its settings' names:
-- FIELDS), made once for each.
local looks = {}
function ns.CardLook(id)
	local look = looks[id or ""]
	if not look then
		look = setmetatable({}, { __index = function(_, key)
			local field = FIELD_OF[key]
			if not field then return nil end
			local value = ns.CardValue(id, field)
			if field == "Icon" and value == "event" then value = BY_ID[id] and BY_ID[id].icon or MAP end
			if field == "Outline" then value = tonumber(value) or 0 end
			return value
		end })
		looks[id or ""] = look
	end
	return look
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
-- The card done (or cut short): the next one waiting, if not waiting too long.
local function Next()
	current = nil
	while #waiting > 0 do
		local card = table.remove(waiting, 1)
		if GetTime() - card.at <= WAIT_MAX then
			Show(card)
			return
		end
	end
end
function Show(card)
	current = card
	local look = ns.CardLook(not card.defaultLook and card.id or nil) -- (defaultLook: the Default style's Test)
	ns.PlayCard(Screen(), look, UIParent:GetWidth(), UIParent:GetHeight(), 1, card, Next)
	if card.sound then pcall(card.sound) end
end

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
	card.id, card.priority, card.at = id, event.priority, GetTime()
	-- (A more important one playing: this one waits, in place of one of its own.)
	if current and current.priority > card.priority then
		for i = #waiting, 1, -1 do
			if waiting[i].id == id then table.remove(waiting, i) end
		end
		waiting[#waiting + 1] = card
		return true
	end
	Show(card)
	return true
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
function ns.CardSample(id)
	local make = samples[id]
	return make and make() or { name = L[BY_ID[id] and BY_ID[id].name or "Cards"] }
end

-- Test: an event's made-up card on your screen now, whatever the page says.
function ns.CardTest(id)
	ns.Cards.Fire(id, ns.CardSample(id), true)
end

-- Battle Vision's and Story Vision's settings, onto the Cards page's: their
-- switches into the rows' ticks, their Show in rows to the rows', and each
-- look setting you'd changed onto its event (the font, outline and shadow
-- Story Vision's moments shared, onto the Default style). t: the saved
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
	-- Default style).
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
