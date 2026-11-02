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

local SEPARATOR = " · "
-- The game's lines: zone, PvP status, arena/sanctuary note, subzone.
local LINES = { "ZoneTextString", "PVPInfoTextString", "PVPArenaTextString", "SubZoneTextString" }

local function On() return ns.CardOn("zone") end

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
	if fading or not On() then return end
	fading = true
	line:SetAlpha(0)
	fading = false
end
local function HideGame()
	local on = On()
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

-- What the game just showed (a frame later, so both its frames are set).
local zoneShown, subShown, waiting = false, false, false
local function Shows()
	waiting = false
	local newArea, sub = zoneShown, subShown
	zoneShown, subShown = false, false
	HideGame()
	if not On() then return end
	if not newArea and not (sub and ns.CardOn("subzone")) then return end
	local meta
	if newArea and GetTime() < timeUntil and ns.TimeTitleNow then
		meta, timeUntil = ns.TimeTitleNow(), 0
	end
	local card = ns.ZoneCardText(Text(ZoneTextString), Shown(SubZoneTextFrame) and Text(SubZoneTextString) or "",
		nil, newArea, meta)
	if card then
		card.newArea = newArea
		Play(card)
	end
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
