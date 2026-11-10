-- The Cards page's Zone and Subzone: the game's zone name, as you come into
-- a new zone (or subzone), drawn as a card in its place (Cards.lua fires and
-- draws it: its look is the page's); off, the game's own shows as it always
-- does.
--
-- The game's lines stay where they are, only see-through (the time of day's
-- and Last time's lines go by them: Tint.lua): its zone text frames are plain,
-- not secure, and their alpha is the game's to fade, so their text's is ours.

local _, ns = ...
local DEFAULTS = ns.DEFAULTS

DEFAULTS.storyZoneCard = false        -- the Zone row (off: the game's own)
DEFAULTS.storyZoneSubzones = true     -- the Subzone row: a card as you come into a subzone, too
DEFAULTS.storyZoneTerritory = false   -- "Contested Territory" and such under it, as the game says
DEFAULTS.storyZoneGap = 10            -- seconds after a Zone or Subzone card before the next can come
DEFAULTS.storyZoneNotFlying = true    -- none on a flight path (the Flight departure and arrival cards say where)

local SEPARATOR = " · "
-- The game's lines: zone, PvP status, arena/sanctuary note, subzone.
local LINES = { "ZoneTextString", "PVPInfoTextString", "PVPArenaTextString", "SubZoneTextString" }
-- Seconds a card waits for the game's "Discovered:" line, which the server
-- sends after the place's name: a place known to you, and one new to this
-- character (once each, so the Discovered card can have it alone).
local KNOWN_WAIT, NEW_WAIT = 0.5, 3

local function On() return ns.CardOn("zone") end
-- (Discovered's card playing for the place: the game's lines go for that
-- showing too, Zone's card on or not. Asked again as the game next shows.)
local discovered = false
local function Hiding() return On() or discovered end

-- A line's text, or "" (none, or one the game keeps secret).
local function Text(line)
	if not line then return "" end
	local ok, text = pcall(line.GetText, line)
	if not ok or (issecretvalue and issecretvalue(text)) or type(text) ~= "string" then return "" end
	return text
end
local function Shown(frame)
	return frame and ns.Flag(frame:IsShown()) and true or false
end

-- The game's lines see-through while the card's on (back as they were when
-- it's turned off, as they next show). The game recolors them as they show:
-- on Forever a color can carry the alpha, so it's kept clear after each.
local hooked, fading = {}, false
local function Keep(line)
	if fading or not Hiding() then return end
	fading = true
	line:SetAlpha(0)
	fading = false
end
local function HideGame()
	local on = Hiding()
	for _, name in ipairs(LINES) do
		local line = _G[name]
		if line then
			if on and not hooked[line] then
				hooked[line] = true
				hooksecurefunc(line, "SetTextColor", Keep)
				hooksecurefunc(line, "SetVertexColor", Keep)
			end
			line:SetAlpha(on and 0 or 1)
		end
	end
end

-- A card { name, sub, meta }: a new zone's name, its subzone and territory
-- under it; or a subzone's name, the zone and territory under it. meta: over
-- the name (the time of day, at login). territory: nil, the game's.
function ns.ZoneCardText(zone, subzone, territory, newArea, meta)
	territory = territory or Text(PVPInfoTextString)
	local under = {}
	local name = zone
	if newArea then
		if subzone ~= "" and subzone ~= zone then under[#under + 1] = subzone end
	else
		name = subzone ~= "" and subzone or zone
		if zone ~= "" and zone ~= name then under[#under + 1] = zone end
	end
	if ns.db.storyZoneTerritory and territory ~= "" then under[#under + 1] = territory end
	if name == "" then return nil end
	return { name = name, sub = table.concat(under, SEPARATOR), meta = meta }
end

-- The card, as Cards.lua plays it (Zone's, or Subzone's).
local last
local timeUntil = 0 -- (until then, the next new zone's card carries the time of day: a login's)
local function Play(card)
	last = card
	card.played = GetTime()
	ns.Cards.Fire(card.newArea and "zone" or "subzone", card)
end

-- The card for what the game showed, unless one came too soon before it.
local function Card(zone, subzone, newArea)
	local meta
	if newArea and GetTime() < timeUntil and ns.TimeTitleNow then
		meta, timeUntil = ns.TimeTitleNow(), 0
	end
	-- (On a flight path: none, the places flown over coming one after another.)
	if ns.db.storyZoneNotFlying and ns.Flag(ns.OnTaxi()) then return end
	-- (Passing through places quickly: none until the gap since the last's up.)
	if last and GetTime() - last.played < (tonumber(ns.db.storyZoneGap) or 0) then return end
	local card = ns.ZoneCardText(zone, subzone, nil, newArea, meta)
	if card then
		card.newArea = newArea
		Play(card)
	end
end

-- What the game just showed (a frame later, so both its frames are set).
-- Stepping out of a subzone back into the zone, the game shows the zone's
-- name again (as the subzone line, or as the zone line once more): no card
-- for a zone you're already in.
local zoneShown, subShown, waiting = false, false, false
local lastZone -- (the zone the last Zone card was for)
-- The card waiting to see if Discovered's has the place, as { place }.
local holding
local function Hold(place, seconds, zone, subzone, newArea)
	local hold = { place = place }
	holding = hold
	C_Timer.After(seconds, function()
		if holding ~= hold then return end -- (you've moved on)
		holding = nil
		if ns.DiscoverHasIt() then return end
		ns.Log("card", ("no Discovered line for %s after %.1f sec: its Zone card plays"):format(place, seconds))
		Card(zone, subzone, newArea)
	end)
end
local function Shows()
	waiting = false
	local newArea, sub = zoneShown, subShown
	zoneShown, subShown = false, false
	-- (A place new to you, Discovered's card has it: none of the game's.)
	discovered = ns.DiscoverHasIt and ns.CardOn("discover") and ns.DiscoverHasIt() or false
	HideGame()
	if not On() then return end
	local zone = Text(ZoneTextString)
	local subzone = Shown(SubZoneTextFrame) and Text(SubZoneTextString) or ""
	if subzone == zone then subzone = "" end
	local place = subzone ~= "" and subzone or zone
	-- (The same name shown again keeps its wait going; any other ends it.)
	if holding and holding.place == place then return end
	holding = nil
	if newArea and zone ~= "" and zone == lastZone then
		-- (The same zone's line again: a subzone's card if it's a new one.)
		newArea = false
		sub = subzone ~= ""
	end
	if not newArea and not (sub and subzone ~= "" and ns.CardOn("subzone")) then return end
	if newArea then lastZone = zone end
	-- (A place new to you: Discovered's card in place of this one, so this
	-- one waits, as the game's "Discovered:" line comes after its name.)
	if ns.DiscoverHasIt and ns.CardOn("discover") then
		if ns.DiscoverHasIt() then return end
		local new = ns.PlaceIsNew(zone, place)
		ns.Log("card", ("%s shown (%s): Zone card waits for a Discovered line"):format(place, new and "new here" or "known"))
		Hold(place, new and NEW_WAIT or KNOWN_WAIT, zone, subzone, newArea)
		return
	end
	Card(zone, subzone, newArea)
end
local function Showing(frame)
	if frame == ZoneTextFrame then
		zoneShown = true
	elseif frame == SubZoneTextFrame then
		subShown = true
	else
		return
	end
	HideGame()
	if not waiting then
		waiting = true
		C_Timer.After(0, Shows)
	end
end
if FadingFrame_Show then
	hooksecurefunc("FadingFrame_Show", Showing)
else
	for _, frame in ipairs({ ZoneTextFrame, SubZoneTextFrame }) do
		frame:HookScript("OnShow", Showing)
	end
end

-- CardMoments.lua, as Discovered's card plays: the game's own lines for the
-- place go (its zone text, and its yellow "Discovered:" line in the middle
-- of the screen, a frame later so the game has added it).
function ns.HideGameDiscovered()
	discovered = true
	HideGame()
	C_Timer.After(0, function()
		if UIErrorsFrame and UIErrorsFrame.Clear then pcall(UIErrorsFrame.Clear, UIErrorsFrame) end
	end)
end

-- Core.lua at login (and the Last time Test): the time of day goes on the
-- login's zone card, over its name, rather than under the game's. True if
-- it does (the card's on): the one just played gets it, or the next.
function ns.ZoneCardTime()
	if not On() then return false end
	if last and last.newArea and not last.timed and GetTime() - last.played < 2 and ns.TimeTitleNow then
		last.meta, last.timed = ns.TimeTitleNow(), true
		Play(last)
	else
		timeUntil = GetTime() + 10
	end
	return true
end

-- The Tests and previews: the zone you're in, as you'd come into it (sub:
-- the subzone you're in, as you'd come into that).
local function Sample(sub)
	local zone = GetRealZoneText and GetRealZoneText() or ""
	local subzone = GetSubZoneText and GetSubZoneText() or ""
	if zone == "" then zone = "Darkshore" end
	if sub and subzone == "" then subzone = "Auberdine" end
	local card = ns.ZoneCardText(zone, subzone, nil, not sub)
	if card then card.newArea = not sub end
	return card
end
ns.CardSamples = ns.CardSamples or {}
ns.CardSamples.zone = function() return Sample(false) end
ns.CardSamples.subzone = function() return Sample(true) end
