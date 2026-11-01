-- Story Vision's Zone name: the game's zone name, as you come into a new
-- zone (or subzone), drawn as a card of its own in its place: Battle Vision's
-- boss card (ns.PlayVisionCard), as Last time's is (Recap.lua). Its place,
-- style, animation and color are on Story Vision's Style tab; off, the game's
-- own shows as it always does.
--
-- The game's lines stay where they are, only see-through (the time of day's
-- and Last time's lines go by them: Tint.lua): its zone text frames are plain,
-- not secure, and their alpha is the game's to fade, so their text's is ours.

local _, ns = ...
local DEFAULTS = ns.DEFAULTS

DEFAULTS.storyZoneCard = false        -- Story Vision's Zone name row (off: the game's own)
DEFAULTS.storyZoneSubzones = true     -- ...a card as you come into a subzone, too
DEFAULTS.storyZonePlace = "third"     -- "screen", "top" or "bottom" bar, "third" (Battle Vision's)
DEFAULTS.storyZoneStyle = "chapter"   -- "title", "subtitle" or "chapter"
DEFAULTS.storyZoneAnim = "track"      -- "fade", "reveal", "track" or "type"
DEFAULTS.storyZoneAlign = "center"    -- in a bar: "left", "center" or "right"
DEFAULTS.storyZoneSize = 36           -- the name's height on the screen
DEFAULTS.storyZoneHold = 3            -- seconds it stays, between its fades
DEFAULTS.storyZoneR, DEFAULTS.storyZoneG, DEFAULTS.storyZoneB = 1, 0.82, 0 -- the game's zone gold
DEFAULTS.storyZoneIcon = false        -- a map before the name
DEFAULTS.storyZoneTerritory = false   -- "Contested Territory" and such under it, as the game says

local MAP = "Interface\\Icons\\INV_Misc_Map_01"
local SEPARATOR = " · "
-- The game's lines: zone, PvP status, arena/sanctuary note, subzone.
local LINES = { "ZoneTextString", "PVPInfoTextString", "PVPArenaTextString", "SubZoneTextString" }

local function On() return ns.Setting("storyZoneCard") and true or false end

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

-- The Zone name look, read as Battle Vision's cue settings (ns.PlayVisionCard).
local CARD_FIELDS = {
	combatPlace = "storyZonePlace", combatStyle = "storyZoneStyle", combatAnim = "storyZoneAnim",
	combatAlign = "storyZoneAlign", combatSize = "storyZoneSize", combatHoldIn = "storyZoneHold",
	combatInR = "storyZoneR", combatInG = "storyZoneG", combatInB = "storyZoneB",
	combatFont = "storyFont", combatOutline = "storyOutline", combatShadow = "storyShadow",
	combatOutlineR = "storyOutlineR", combatOutlineG = "storyOutlineG", combatOutlineB = "storyOutlineB",
	combatIconShowIn = "storyZoneIcon",
}
local CARD_FIXED = { combatBarScale = 0.5, combatBarFallback = true, combatPulseIn = 0, combatIconIn = MAP }
function ns.ZoneCardLook(look)
	look = look or ns.StyleLook("storyVision")
	return setmetatable({}, { __index = function(_, key)
		if CARD_FIXED[key] ~= nil then return CARD_FIXED[key] end
		local value = look[CARD_FIELDS[key] or key]
		if key == "combatOutline" then value = tonumber(value) or 0 end
		return value
	end })
end

-- A card { name, sub, meta }: a new zone's name, its subzone and territory
-- under it; or a subzone's name, the zone and territory under it. meta: over
-- the name (the time of day, at login). territory: nil, the game's.
function ns.ZoneCardText(look, zone, subzone, territory, newArea, meta)
	look = look or ns.StyleLook("storyVision")
	territory = territory or Text(PVPInfoTextString)
	local under = {}
	local name = zone
	if newArea then
		if subzone ~= "" and subzone ~= zone then under[#under + 1] = subzone end
	else
		name = subzone ~= "" and subzone or zone
		if zone ~= "" and zone ~= name then under[#under + 1] = zone end
	end
	if look.storyZoneTerritory and territory ~= "" then under[#under + 1] = territory end
	if name == "" then return nil end
	return { name = name, sub = table.concat(under, SEPARATOR), meta = meta }
end

-- The real card, over the whole screen (an overlay, kept with the UI hidden).
local screen, last
local timeUntil = 0 -- (until then, the next new zone's card carries the time of day: a login's)
local function Play(card)
	if not ns.PlayVisionCard then return end
	if not screen then
		screen = CreateFrame("Frame", "CinematicZoneCard", UIParent)
		screen:SetAllPoints(UIParent)
		screen:SetFrameStrata("LOW")
		screen:EnableMouse(false)
		ns.AddOverlay(screen)
	end
	card.at = GetTime()
	last = card
	ns.PlayVisionCard(screen, ns.ZoneCardLook(), UIParent:GetWidth(), UIParent:GetHeight(), 1, card)
end

-- What the game just showed (a frame later, so both its frames are set).
local zoneShown, subShown, waiting = false, false, false
local function Shows()
	waiting = false
	local newArea, sub = zoneShown, subShown
	zoneShown, subShown = false, false
	HideGame()
	if not On() then return end
	local look = ns.StyleLook("storyVision")
	if not newArea and not (sub and look.storyZoneSubzones) then return end
	local meta
	if newArea and GetTime() < timeUntil and ns.TimeTitleNow then
		meta, timeUntil = ns.TimeTitleNow(), 0
	end
	local card = ns.ZoneCardText(look, Text(ZoneTextString), Shown(SubZoneTextFrame) and Text(SubZoneTextString) or "",
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
	if last and last.newArea and not last.timed and GetTime() - last.at < 2 and ns.TimeTitleNow then
		last.meta, last.timed = ns.TimeTitleNow(), true
		Play(last)
	else
		timeUntil = GetTime() + 10
	end
	return true
end

-- The Test button: the zone you're in, as you'd come into it.
function ns.TestZoneCard()
	local zone = GetRealZoneText and GetRealZoneText() or ""
	local card = ns.ZoneCardText(nil, zone ~= "" and zone or "Darkshore", GetSubZoneText and GetSubZoneText() or "",
		nil, true)
	if card then Play(card) end
end
