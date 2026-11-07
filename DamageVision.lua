-- Damage Vision (the dev copy's, CinematicDev.toc): not the meter's numbers,
-- but your race with the player ahead of you (#1), or
-- your lead over #2 once you're #1. Read from the game's own damage meter
-- (C_DamageMeter, retail). In fights its totals are secret, but the list's
-- order and which row is you stay plain, and bars and text take secret values
-- (tested 2026-11-02), so: your place from your row, the gap drawn by a bar
-- (max = the one ahead, value = the one behind), never worked out here.
-- Styles: a gap bar, a race track (dots on the bar's edge) and a rank ladder.
-- Boss fights: shown only then if you like, and counted from 0 (the meter
-- keeps a session per fight, so the boss's own is Current). After a boss and
-- at the end of a dungeon, a recap (out of combat: plain again). Its page is
-- at the bottom.

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.damageVision = false              -- at all (its page's switch)
DEFAULTS.damageVisionStyle = "gap"         -- "gap", "race" or "ladder"
DEFAULTS.damageVisionCount = "role"        -- "damage", "healing", or "role" (healing for healers)
DEFAULTS.damageVisionDuring = "all"        -- "all" fights or "boss" fights only
DEFAULTS.damageVisionFrom = "boss"         -- "run" (the meter's Overall), "boss" (a boss's own, else the run), "fight"
DEFAULTS.damageVisionOnlyCine = false      -- only while CineMode is on
DEFAULTS.damageVisionPlace = true          -- your place over it...
DEFAULTS.damageVisionPlaceOf = false       -- ...as "#2 of 5" (else just "#2")
DEFAULTS.damageVisionLadderRows = 3        -- the rank ladder: at most this many rows (#1 down, you last if further down)
DEFAULTS.damageVisionLadderNames = false   -- the rank ladder: the players' names on their rows
DEFAULTS.damageVisionAlways = false        -- its Show in row's Always: in every fight, wherever you are
DEFAULTS.damageVisionHold = 5              -- seconds it stays after a fight
DEFAULTS.damageVisionSize = 1              -- its size, times its own
-- Where it sits: X right and Y up from the middle of the screen, in the UI's
-- units, by its top edge. The recap takes the same spot (the display fading
-- out while it's up). Typed on the Style tab or dragged with its mover.
DEFAULTS.damageVisionX = -861     -- (top left, beside the game's damage meter window)
DEFAULTS.damageVisionY = 545
DEFAULTS.damageVisionRecapBoss = true      -- a recap as a boss dies
DEFAULTS.damageVisionRecapRun = true       -- ...and as a dungeon's done
-- The look (the Style tab's; its switch damageVisionLook, off: these defaults).
DEFAULTS.damageVisionLook = true
DEFAULTS.damageVisionTexture = "general"   -- the bars' texture (ns.StyleTexturePath; general: General's)
DEFAULTS.damageVisionBarHeight = 14        -- the gap bar's height (the race's half, a ladder row's +2)
DEFAULTS.damageVisionWidth = 260           -- how wide it is
DEFAULTS.damageVisionOpacity = 1           -- the whole display's
DEFAULTS.damageVisionTrack = 0.45          -- how dark it is behind the bars
DEFAULTS.damageVisionPanel = 0             -- a dark panel behind it all (0: none)
DEFAULTS.damageVisionColors = "status"     -- the bar: "status" (amber behind, teal ahead), "class" (yours), "custom"
DEFAULTS.damageVisionChaseR, DEFAULTS.damageVisionChaseG, DEFAULTS.damageVisionChaseB = 0.94, 0.62, 0.15
DEFAULTS.damageVisionLeadR, DEFAULTS.damageVisionLeadG, DEFAULTS.damageVisionLeadB = 0.11, 0.62, 0.46
DEFAULTS.damageVisionBorder = "thin"       -- round the bars: "none", "thin" or "thick"
DEFAULTS.damageVisionBorderR, DEFAULTS.damageVisionBorderG, DEFAULTS.damageVisionBorderB = 0, 0, 0
DEFAULTS.damageVisionSmooth = true         -- the bars glide to their new value
DEFAULTS.damageVisionSpark = true          -- a spark at the filled part's edge
DEFAULTS.damageVisionCrown = true          -- the crown as you take #1
DEFAULTS.damageVisionDots = "portrait"     -- the race track's dots: "circle", "portrait" (you; them: their class icon) or "class"
DEFAULTS.damageVisionTotal = false         -- your total in the gap bar
DEFAULTS.damageVisionRivalName = false     -- the name of the one you race (off by default)
DEFAULTS.damageVisionFont = "general"      -- the words' font (general: General's)
DEFAULTS.damageVisionTextSize = 1          -- ...times their usual size
DEFAULTS.damageVisionOutline = -1          -- ...outline: 0 none, 1 thin, 2 thick (-1: General's)
DEFAULTS.damageVisionShadow = "general"    -- ...shadow: "game", "on" or "none" (general: General's)
DEFAULTS.damageVisionTextColor = "gold"    -- the place's color: "gold", "white" or "custom"
DEFAULTS.damageVisionTextR, DEFAULTS.damageVisionTextG, DEFAULTS.damageVisionTextB = 1, 0.82, 0
-- (The texture, font, outline and shadow start on the Style hub's General page's.)
ns.SHARED_STYLE.damageVisionTexture = { kind = "texture", own = "game" }
ns.SHARED_STYLE.damageVisionFont = { kind = "font", own = "game" }
ns.SHARED_STYLE.damageVisionOutline = { kind = "outline", own = 1 }
ns.SHARED_STYLE.damageVisionShadow = { kind = "shadow", own = "game" }

-- Where: its Show in row (GridRows.lua's, as a card's), Instances (dungeons,
-- scenarios and raids) ticked to start with.
local ROW_KEY = "damage:vision"
ns.CINE_SHOW_SETTING[ROW_KEY] = "damageVisionAlways"
ns.LIST_DEFAULTS.instanceShow[ROW_KEY] = true

local WIDTH = 260
local LADDER_ROWS = 20    -- the most rows a ladder can show (Rows: how many it does)
local RECAP_ROWS = 5
local RECAP_TIME = 8     -- seconds a recap stays
local READ_EVERY = 1     -- seconds between reads of the meter (sooner as it says it changed)
local RESTRICTION_WAIT = 3 -- seconds a recap waits for the game's restrictions to lift (a key's last all of it)
local FADE_TIME = 0.4    -- seconds it takes to fade in or out
local TEST_TIME = 25     -- seconds the test runs for
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local CROWN = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local CHASE = { 0.94, 0.62, 0.15 } -- behind: amber
local LEAD = { 0.11, 0.62, 0.46 }  -- ahead: teal

local db, frame, recap
local shown = 0        -- the whole display's opacity as it fades (0-1)
local nextRead = 0
local encounter        -- the boss fight on now: its name (ENCOUNTER_START to _END)
local lastFight = 0    -- GetTime() a fight last ended
local lastRank         -- for the crown: your place last read
local test             -- the test: { ends, rows (plain, made up) }
local pending          -- a recap waiting for the fight to end: { kind, name }
local state = { why = "not started" } -- the last read, for the debug command

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

local function HasMeter()
	return C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum.DamageMeterSessionType
		and Enum.DamageMeterType and true or false
end

-- Whether the game's meter is on (Options > Gameplay Enhancements > Enable
-- Damage Meter: off, it keeps nothing). Ours to ask, not to turn on. (Its
-- Auto Reset starts the meter afresh, which is when The whole run starts.)
-- (IsDamageMeterAvailable says the meter can run here, not that it's ticked:
-- the tick is its own CVar, so that's asked first.)
local METER_CVAR = "damageMeterEnabled"
local function MeterCVar()
	local value = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(METER_CVAR)
	if type(value) ~= "string" then return nil end
	return value ~= "0"
end

local function MeterOn()
	if MeterCVar() == false then return false end
	if not C_DamageMeter.IsDamageMeterAvailable then return true end
	local ok, available = pcall(C_DamageMeter.IsDamageMeterAvailable)
	return not ok or available ~= false
end

-- Healing for healers (Count: by role), else damage done.
local function MeterType()
	local count = db.damageVisionCount
	if count == "role" then
		local spec = GetSpecialization and GetSpecialization()
		local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
		count = role == "HEALER" and "healing" or "damage"
	end
	return count == "healing" and Enum.DamageMeterType.HealingDone or Enum.DamageMeterType.DamageDone
end

-- The session counted now, by Count from: the boss fight's own (Current while
-- one's on), this fight's, or the whole run's (Overall).
local function SessionType()
	local from = db.damageVisionFrom
	-- (Just after a boss, while it stays up: still the boss's, Current until the next pull.)
	local boss = encounter or (state.boss and not InCombatLockdown())
	if from == "fight" or (from == "boss" and boss) then
		return Enum.DamageMeterSessionType.Current, from == "fight" and "this fight" or "this boss"
	end
	return Enum.DamageMeterSessionType.Overall, "the whole run"
end

-- A session's rows, biggest first (the meter's own order, plain in fights),
-- players only (a companion, like a delve's, has no class but a
-- classification), and the top total: the session's own (maxAmount) while no
-- row was left out, else the first player's.
local function Rows(sessionType, meterType, sessionID)
	local ok, session
	if sessionID then
		ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, meterType)
	else
		ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, meterType)
	end
	local rows = ok and type(session) == "table" and session.combatSources
	if type(rows) ~= "table" or (issecrettable and issecrettable(rows)) then return nil end
	local players, left = {}, false
	for i = 1, #rows do
		local row = rows[i]
		local class, kind = row.classFilename, row.classification
		if not Secret(class) and class == "" and not Secret(kind) and kind ~= nil and kind ~= "" then
			left = true
		else
			players[#players + 1] = row
		end
	end
	local top = not left and session.maxAmount or (players[1] and players[1].totalAmount)
	return players, top
end

-- Your place in the rows (isLocalPlayer stays plain in fights).
local function Rank(rows)
	for i = 1, #rows do
		local mine = rows[i].isLocalPlayer
		if not Secret(mine) and mine == true then return i end
	end
end

-- The row you race: #1, or #2 when you lead.
local function Rival(rank)
	return rank == 1 and 2 or 1
end

local function ClassColor(row)
	local class = row.classFilename
	local color = not Secret(class) and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then return color.r, color.g, color.b end
	return 0.7, 0.7, 0.7
end

-- A total as text, shortened (3.7M): the game's AbbreviateNumbers takes a
-- secret one too. (Else as it is.)
local function SetTotal(text, value)
	if value == nil then text:SetText("") return end
	local abbreviate = AbbreviateNumbers or AbbreviateLargeNumbers
	local ok, short = false, nil
	if abbreviate then ok, short = pcall(abbreviate, value) end
	if not (ok and short ~= nil and pcall(text.SetText, text, short)) then
		pcall(text.SetText, text, value)
	end
end

-- Which of the game's restrictions on addons is on now, if any (its values
-- secret while it is): a fight, a boss, a Mythic+ key (the whole key), a PvP
-- match. False with none, or on a client without them.
local RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" }
local function Restricted()
	if not (C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum.AddOnRestrictionType) then
		return false
	end
	for _, name in ipairs(RESTRICTIONS) do
		local kind = Enum.AddOnRestrictionType[name]
		local ok, on = false, nil
		if kind then ok, on = pcall(C_RestrictedActions.GetAddOnRestrictionState, kind) end
		if ok and type(on) == "number" and not Secret(on) and on > 0 then return name end
	end
	return false
end

-- For the full report (DamageReport.lua).
ns.DamageVisionMeter = { HasMeter = HasMeter, MeterType = MeterType, Rows = Rows, Restricted = Restricted }

-- Whether it shows now, and why not (for the debug command).
local function Allowed()
	if test then return true end
	if recap and recap:IsShown() then return false, "its recap is up (in the same spot)" end
	if not db.damageVision then return false, "the page is off" end
	if not HasMeter() then return false, "no damage meter on this client" end
	if not MeterOn() then return false, "the game's damage meter is off (Gameplay Enhancements: Enable Damage Meter)" end
	if db.damageVisionOnlyCine and not ns.lastCinematic then return false, "only in CineMode" end
	local ok, here = pcall(ns.RowOnNow, ROW_KEY, nil, true)
	if not ok then return false, "its Show in row errored" end
	if not here then return false, "its Show in row says not here" end
	local fighting = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	if not fighting and GetTime() - lastFight > db.damageVisionHold then return false, "not in a fight" end
	if db.damageVisionDuring == "boss" and not encounter and fighting then return false, "not a boss fight" end
	if db.damageVisionDuring == "boss" and not fighting and not state.boss then return false, "not a boss fight" end
	return true
end

-- The display -----------------------------------------------------------------

-- The look (the Style tab's): its own while that tab's on, else the defaults.
local function Look()
	return ns.StyleLook("damageVisionLook")
end

-- Text in the look's font, size, outline and shadow (the client's own font
-- where its letters need it: Cyrillic, Korean, Chinese show boxes in ours).
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]
local function StyleText(text, look)
	text.base = text.base or { text:GetFont() }
	local file, size, flags = text.base[1], text.base[2], text.base[3]
	if not (file and size) then return end
	if ROMAN then file = ns.StyleFontFile(look.damageVisionFont) or file end
	text:SetFont(file, size * (look.damageVisionTextSize or 1), ns.OutlinedFlags(flags, look.damageVisionOutline))
	ns.SetTextShadow(text, look.damageVisionShadow)
end

-- The words' color (the place over it).
local function TextColor(look)
	local pick = look.damageVisionTextColor
	if pick == "white" then return 1, 1, 1 end
	if pick == "custom" then return look.damageVisionTextR, look.damageVisionTextG, look.damageVisionTextB end
	return 1, 0.82, 0
end

-- The bar's colors: behind and ahead (Colors: status, your class's, or your own).
local function BarColors(look)
	local pick = look.damageVisionColors
	if pick == "class" then
		local _, class = UnitClass("player")
		local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if color then
			local mine = { color.r, color.g, color.b }
			return mine, mine
		end
	elseif pick == "custom" then
		return { look.damageVisionChaseR, look.damageVisionChaseG, look.damageVisionChaseB },
			{ look.damageVisionLeadR, look.damageVisionLeadG, look.damageVisionLeadB }
	end
	return CHASE, LEAD
end

-- A bar's value, gliding there when Smooth is ticked (the game does the
-- glide: works with secret values too). Max and value may be secret.
local function SetBar(bar, max, value)
	pcall(bar.SetMinMaxValues, bar, 0, max)
	local smooth = Look().damageVisionSmooth and Enum.StatusBarInterpolation
		and Enum.StatusBarInterpolation.ExponentialEaseOut
	if not (smooth and pcall(bar.SetValue, bar, value, smooth)) then
		pcall(bar.SetValue, bar, value)
	end
end

local function NewBar(parent, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(WIDTH, height)
	bar:SetStatusBarTexture(BAR_TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar.track = bar:CreateTexture(nil, "BACKGROUND")
	bar.track:SetAllPoints()
	bar.track:SetColorTexture(0, 0, 0, 0.45)
	-- A spark at the filled part's edge (it follows the fill, secret or not).
	bar.spark = bar:CreateTexture(nil, "OVERLAY")
	bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	bar.spark:SetBlendMode("ADD")
	bar.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
	bar.edges = ns.MakeStyleEdges(bar)
	return bar
end

-- A bar dressed as the look says: texture, the dark behind it, spark, border.
local function DressBar(bar, look, height)
	if not ns.SetBarTexture(bar, look.damageVisionTexture) then bar:SetStatusBarTexture(BAR_TEXTURE) end
	bar.spark:ClearAllPoints()
	bar.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
	bar.spark:SetSize(height * 1.4, height * 2.4)
	bar.spark:SetShown(look.damageVisionSpark and true or false)
	bar.track:SetColorTexture(0, 0, 0, look.damageVisionTrack or 0.45)
	local border = look.damageVisionBorder
	if border == "none" then
		bar.edges:Hide()
	else
		bar.edges:Show()
		ns.DressStyleEdges(bar.edges, border == "thick" and 2 or 1, look.damageVisionBorderR,
			look.damageVisionBorderG, look.damageVisionBorderB, 1, true)
	end
end

-- A race track's dot: a round one in full color (a white disc, tinted), on
-- a dark ring so it shows over any ground. Each its own frame, above the
-- bar's border (its lines would cross it), so one dot covers the other,
-- ring and all, where they meet (dot:Front(), the one on top).
local DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- (a round mask every client has)
local function NewDot(parent, size)
	local dot = CreateFrame("Frame", nil, parent)
	dot:SetSize(size, size)
	dot.ring = dot:CreateTexture(nil, "ARTWORK")
	dot.ring:SetTexture(DISC)
	dot.ring:SetVertexColor(0, 0, 0, 0.9)
	dot.ring:SetPoint("TOPLEFT", -2, 2)
	dot.ring:SetPoint("BOTTOMRIGHT", 2, -2)
	dot.disc = dot:CreateTexture(nil, "OVERLAY")
	dot.disc:SetTexture(DISC)
	dot.disc:SetAllPoints()
	-- Its arrow, on a pin at its spot on the track (the pin follows the bar,
	-- secret totals or not): above the track pointing down at it, or below
	-- pointing up (dot:Pin()), the disc on the arrow's far side. Above and
	-- below, so in a close race the two never cover each other.
	dot.pin = CreateFrame("Frame", nil, parent)
	dot.pin:SetSize(1, 1)
	dot.arrow = dot.pin:CreateTexture(nil, "OVERLAY")
	dot.arrow:SetSize(14, 14)
	dot.arrow:SetDesaturated(true)
	function dot.SetVertexColor(_, r, g, b)
		dot.disc:SetVertexColor(r, g, b)
		dot.arrow:SetVertexColor(r, g, b)
	end
	function dot.Front(_, front)
		dot:SetFrameLevel(parent:GetFrameLevel() + (front and 6 or 5))
		dot.pin:SetFrameLevel(parent:GetFrameLevel() + (front and 6 or 5))
	end
	-- anchor, point: its spot (the filled part's edge, or the track's end);
	-- up: above the track; half: half the track's height; bare: no arrow,
	-- the dot right against the track (a portrait or icon says who's who).
	function dot.Pin(_, anchor, point, up, half, bare)
		dot.pin:ClearAllPoints()
		dot.pin:SetPoint("CENTER", anchor, point, 0, 0)
		dot.arrow:ClearAllPoints()
		dot:ClearAllPoints()
		dot.arrow:SetShown(not bare)
		if bare then
			dot:SetPoint(up and "BOTTOM" or "TOP", dot.pin, "CENTER", 0, up and half + 2 or -half - 2)
		elseif up then
			dot.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
			dot.arrow:SetPoint("BOTTOM", dot.pin, "CENTER", 0, half - 3)
			dot:SetPoint("BOTTOM", dot.arrow, "TOP", 0, -4)
		else
			dot.arrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
			dot.arrow:SetPoint("TOP", dot.pin, "CENTER", 0, -half + 3)
			dot:SetPoint("TOP", dot.arrow, "BOTTOM", 0, 4)
		end
	end
	-- In place of the disc (Race dots): "portrait" (yours: the game draws it
	-- round), "class" (their class's round icon; class stays plain in fights),
	-- else the plain disc.
	dot.face = dot:CreateTexture(nil, "OVERLAY", nil, 1)
	dot.face:SetAllPoints()
	dot.face:Hide()
	function dot.Face(_, kind, class)
		local coords = kind == "class" and not Secret(class) and type(class) == "string"
			and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
		if kind == "portrait" and SetPortraitTexture then
			SetPortraitTexture(dot.face, "player")
			dot.face:SetTexCoord(0, 1, 0, 1)
		elseif coords then
			dot.face:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
			dot.face:SetTexCoord(unpack(coords))
		else
			dot.face:Hide()
			dot.disc:Show()
			return
		end
		dot.face:Show()
		dot.disc:Hide()
	end
	dot:Front(false)
	return dot
end

-- The ladder's rows (and the recap's): a name, a bar and a total.
local function NewLadderRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(WIDTH, 16)
	row.bar = NewBar(row, 16)
	row.bar:SetAllPoints()
	row.name = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 4, 0)
	row.total = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.total:SetPoint("RIGHT", -4, 0)
	return row
end

local function DressLadderRow(row, look, width, height)
	row:SetSize(width, height)
	DressBar(row.bar, look, height)
	row.bar.spark:Hide()
	StyleText(row.name, look)
	StyleText(row.total, look)
end

-- Rows filled from the meter's: names and bars, each against the top total.
-- (Yours in the look's colors, the rest in their class's.)
-- count: how many rows to fill (the rest hidden), else all of list's.
-- classes: yours in your class's color too (brighter than the rest).
-- noNames: no names on the rows (just your place, when you're below the rows).
local function FillRows(list, rows, mine, top, count, classes, noNames)
	local first = rows[1]
	local behind, ahead = BarColors(Look())
	count = math.min(count or #list, #list)
	for i, row in ipairs(list) do
		-- (You below the last row: you in the last row, with your place.)
		local index = i
		if i == count and mine and mine > count then index = mine end
		local source = i <= count and rows[index]
		if source and first then
			row:Show()
			if noNames then
				row.name:SetText(index ~= i and (index .. ".") or "")
			else
				pcall(row.name.SetText, row.name, source.name)
				if index ~= i then
					pcall(row.name.SetFormattedText, row.name, "%d. %s", index, source.name)
				end
			end
			SetTotal(row.total, source.totalAmount)
			SetBar(row.bar, top or first.totalAmount, source.totalAmount)
			if index == mine and classes then
				local r, g, b = ClassColor(source)
				row.bar:SetStatusBarColor(r, g, b, 1)
			elseif index == mine then
				local color = mine == 1 and ahead or behind
				row.bar:SetStatusBarColor(color[1], color[2], color[3], 1)
			else
				local r, g, b = ClassColor(source)
				row.bar:SetStatusBarColor(r, g, b, 0.55)
			end
		else
			row:Hide()
		end
	end
end

local function Create()
	frame = CreateFrame("Frame", "CinematicDamageVision", UIParent)
	frame:SetClampedToScreen(true) -- (the defaults are near the edges: kept on smaller screens)
	frame:SetSize(WIDTH, 40)
	frame:SetFrameStrata("MEDIUM")
	frame:EnableMouse(false)
	frame:SetAlpha(0)
	frame:Hide()
	ns.AddOverlay(frame)
	-- (A panel behind it all: Panel's opacity, 0 none.)
	frame.panel = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	frame.panel:SetPoint("TOPLEFT", -8, 24)
	frame.panel:SetPoint("BOTTOMRIGHT", 8, -6)

	frame.place = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.place:SetPoint("BOTTOM", frame, "TOP", 0, 2)
	frame.crown = frame:CreateTexture(nil, "OVERLAY")
	frame.crown:SetSize(20, 20)
	frame.crown:SetTexture(CROWN)
	frame.crown:SetPoint("RIGHT", frame.place, "LEFT", -4, 0)
	frame.crown:Hide()
	local pop = frame.crown:CreateAnimationGroup()
	local grow = pop:CreateAnimation("Scale")
	grow:SetScaleFrom(0.3, 0.3)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(0.35)
	grow:SetSmoothing("OUT")
	local fade = pop:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(0.2)
	frame.crown.pop = pop

	-- Gap bar: full = the one ahead, filled = the one behind. Your total in
	-- it (Your total), the one you race at its end (Their name).
	frame.gap = NewBar(frame, 14)
	frame.gap:SetPoint("TOP")
	frame.gap.total = frame.gap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.gap.total:SetPoint("LEFT", 4, 0)
	frame.gap.rival = frame.gap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.gap.rival:SetPoint("RIGHT", -4, 0)

	-- Race track: a bar the same way, an arrow for each of you (one on the
	-- filled part's edge, the leader at the end): yours above, your rival's
	-- below. The stretch between them is the gap, in your colors (amber: how
	-- far behind; teal: your lead); the track up to the back one plain.
	frame.race = NewBar(frame, 6)
	frame.race:SetPoint("TOP", 0, -6)
	local fill = frame.race:GetStatusBarTexture()
	frame.race.between = frame.race:CreateTexture(nil, "ARTWORK")
	frame.race.between:SetPoint("TOPLEFT", fill, "TOPRIGHT")
	frame.race.between:SetPoint("BOTTOMRIGHT", frame.race, "BOTTOMRIGHT")
	frame.race.ahead = NewDot(frame.race, 18)
	frame.race.behind = NewDot(frame.race, 18)
	frame.race.rival = frame.race:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

	-- Rank ladder: the top rows, yours lit and a marker sliding to it.
	frame.ladder = CreateFrame("Frame", nil, frame)
	frame.ladder:SetSize(WIDTH, LADDER_ROWS * 18)
	frame.ladder:SetPoint("TOP")
	frame.ladder.rows = {}
	for i = 1, LADDER_ROWS do
		frame.ladder.rows[i] = NewLadderRow(frame.ladder)
	end
	frame.ladder.mark = frame.ladder:CreateTexture(nil, "OVERLAY")
	frame.ladder.mark:SetSize(6, 16)
	frame.ladder.mark:SetColorTexture(1, 0.82, 0, 1)
	frame.ladder.markY = 0

	if ns.WhyRegister then
		ns.WhyRegister(frame, L["Damage Vision"], "Damage Vision", function()
			return { test and L["its test"] or L["you're in a fight, and the page is on"] }
		end)
	end
end

-- The heights the look gives: the gap bar's, a ladder row's and its step.
local function Heights(look)
	local bar = look.damageVisionBarHeight or 14
	local row = math.max(12, bar + 2)
	return bar, row, row + 2
end

-- The race track's room above (and below) its line: an arrow (14, less the
-- 7 it overlaps the line and its dot) and a dot (bar + 4), a little spare.
local function RaceRoom(bar)
	return bar + 4 + 14 - 7 + 2
end

-- Everything dressed as the look says (made again as a setting changes).
local function Dress()
	local look = Look()
	local width = look.damageVisionWidth or WIDTH
	local bar, row, step = Heights(look)
	frame:SetWidth(width)
	frame.panel:SetColorTexture(0, 0, 0, look.damageVisionPanel or 0)
	frame.panel:SetShown((look.damageVisionPanel or 0) > 0)
	StyleText(frame.place, look)
	frame.place:SetTextColor(TextColor(look))
	frame.crown:SetSize(20 * (look.damageVisionTextSize or 1), 20 * (look.damageVisionTextSize or 1))
	frame.gap:SetSize(width, bar)
	DressBar(frame.gap, look, bar)
	StyleText(frame.gap.total, look)
	StyleText(frame.gap.rival, look)
	frame.race:SetSize(width, math.max(3, math.floor(bar / 2)))
	DressBar(frame.race, look, bar)
	frame.race.spark:Hide()
	-- (The gap's stretch in the bars' texture; DressBar may have swapped the fill, so anchored again.)
	local between = frame.race.between
	if not ns.SetStyleTexture(between, look.damageVisionTexture) then between:SetTexture(BAR_TEXTURE) end
	between:ClearAllPoints()
	between:SetPoint("TOPLEFT", frame.race:GetStatusBarTexture(), "TOPRIGHT")
	between:SetPoint("BOTTOMRIGHT", frame.race, "BOTTOMRIGHT")
	frame.race.rival:Hide() -- (no name on the race track: the arrows say who's who)
	for _, dot in ipairs({ frame.race.ahead, frame.race.behind }) do dot:SetSize(bar + 4, bar + 4) end
	-- (The track in the middle: room above and below it for an arrow and its dot.)
	frame.race:ClearAllPoints()
	frame.race:SetPoint("TOP", 0, -RaceRoom(bar))
	frame.ladder:SetSize(width, LADDER_ROWS * step)
	for i, each in ipairs(frame.ladder.rows) do
		DressLadderRow(each, look, width, row)
		each:ClearAllPoints()
		each:SetPoint("TOP", 0, -(i - 1) * step)
	end
	frame.ladder.mark:SetHeight(row)
	frame.ladder.step = step
end

-- A frame's point x right and y up from the middle of the screen. (Offsets
-- go by the frame's own scale: divided by it, they stay put as it grows.)
local function SpotPoint(target, x, y, scale, point)
	target:ClearAllPoints()
	target:SetPoint(point, UIParent, "CENTER", (tonumber(x) or 0) / scale, (tonumber(y) or 0) / scale)
end

local function Place()
	frame:SetScale(db.damageVisionSize)
	SpotPoint(frame, db.damageVisionX, db.damageVisionY, db.damageVisionSize, "TOP")
end

-- The crown: popping in as you take #1, gone as you lose it (or with Crown unticked).
local function Crown(rank)
	if not Look().damageVisionCrown then
		frame.crown:Hide()
	elseif rank == 1 and lastRank ~= 1 then
		frame.crown:Show()
		frame.crown.pop:Stop()
		frame.crown.pop:Play()
	elseif rank ~= 1 then
		frame.crown:Hide()
	end
	lastRank = rank
end

-- Where your place sits: above the bar, or on the race track on your dot's
-- line (your dot slides over it, drawn on top: its frame is above the text).
local function PlacePlace(look)
	local key = "top"
	if db.damageVisionStyle == "race" then
		local bare = look.damageVisionDots == "portrait" or look.damageVisionDots == "class"
		local half = frame.race:GetHeight() / 2
		local size = (Heights(look)) + 4
		-- (The dot's bottom over the line's middle, as dot:Pin() puts it.)
		key = (bare and half + 2 or half + 7) + size / 2
	end
	if frame.place.at == key then return end
	frame.place.at = key
	frame.place:ClearAllPoints()
	if key == "top" then
		frame.place:SetPoint("BOTTOM", frame, "TOP", 0, 2)
	else
		frame.place:SetPoint("CENTER", frame.race, "CENTER", 0, key)
	end
end

local function Draw(rows, top)
	local look = Look()
	local style = db.damageVisionStyle
	PlacePlace(look)
	frame.gap:SetShown(style == "gap")
	frame.race:SetShown(style == "race")
	frame.ladder:SetShown(style == "ladder")
	local rank = rows and Rank(rows)
	state.rank, state.count = rank, rows and #rows or 0
	if not rank then
		frame.place:SetText(rows and L["You're not on the meter yet"] or "")
		frame.crown:Hide()
		lastRank = nil
		return
	end
	frame.place:SetShown(db.damageVisionPlace)
	if db.damageVisionPlaceOf then
		frame.place:SetFormattedText(L["#%d of %d"], rank, #rows)
	else
		frame.place:SetFormattedText("#%d", rank)
	end
	Crown(rank)
	local barHeight, _, step = Heights(look)
	if style == "ladder" then
		-- (At most Rows: #1 down, and you in the last one if you're further down.)
		local count = math.max(1, math.min(tonumber(db.damageVisionLadderRows) or 3, LADDER_ROWS))
		FillRows(frame.ladder.rows, rows, rank, top, count, nil, not db.damageVisionLadderNames)
		frame.ladder.target = math.min(rank, count)
		frame:SetHeight(math.min(#rows, count) * step)
		return
	end
	frame:SetHeight(style == "race" and RaceRoom(barHeight) * 2 + math.max(3, math.floor(barHeight / 2))
		or barHeight)
	local rival = rows[Rival(rank)]
	local mine = rows[rank]
	local bar = style == "race" and frame.race or frame.gap
	local behindColor, aheadColor = BarColors(look)
	if not rival then
		SetBar(bar, 1, 1)
		bar:SetStatusBarColor(aheadColor[1], aheadColor[2], aheadColor[3])
		frame.gap.total:SetText("")
		frame.gap.rival:SetText("")
		frame.race.between:Hide()
		return
	end
	local leading = rank == 1
	local ahead, behind = mine, rival
	if not leading then ahead, behind = rival, mine end
	SetBar(bar, ahead.totalAmount, behind.totalAmount)
	local color = leading and aheadColor or behindColor
	if style == "race" then
		-- (The track up to the back dot plain, the gap in your color.)
		bar:SetStatusBarColor(0.55, 0.55, 0.55, 0.6)
		frame.race.between:SetVertexColor(color[1], color[2], color[3], 1)
		frame.race.between:Show()
	else
		bar:SetStatusBarColor(color[1], color[2], color[3], 1)
	end
	-- (Words on it: your total, and who you race, as the game gives them.)
	if look.damageVisionTotal then SetTotal(frame.gap.total, mine.totalAmount) else frame.gap.total:SetText("") end
	if look.damageVisionRivalName then
		pcall(frame.gap.rival.SetText, frame.gap.rival, rival.name)
		frame.gap.rival:SetTextColor(ClassColor(rival))
	else
		frame.gap.rival:SetText("")
	end
	if style == "race" then
		local race = frame.race
		local fill = race:GetStatusBarTexture()
		-- You in your color, above; your rival in theirs, below.
		local youDot, themDot = leading and race.ahead or race.behind, leading and race.behind or race.ahead
		local half = race:GetHeight() / 2
		-- (Race dots: your portrait or class icon, theirs their class icon, with
		-- no arrows; else plain discs on arrows.)
		local dots = look.damageVisionDots
		local bare = dots == "portrait" or dots == "class"
		race.ahead:Pin(race, "RIGHT", race.ahead == youDot, half, bare)
		race.behind:Pin(fill, "RIGHT", race.behind == youDot, half, bare)
		youDot:SetVertexColor(color[1], color[2], color[3])
		themDot:SetVertexColor(ClassColor(rival))
		youDot:Front(true)
		themDot:Front(false)
		youDot:Face(dots, mine.classFilename)
		themDot:Face(dots ~= "circle" and "class" or nil, rival.classFilename)
	end
end

-- The test's made-up fight: you and four others, plain numbers.
local function TestRows()
	for i, row in ipairs(test.rows) do
		local rate = row.rate * (0.8 + math.random() * 0.4)
		if i == 1 and test.burst then rate = rate * 1.8 end
		row.totalAmount = row.totalAmount + rate * 1000
	end
	local sorted = {}
	for i, row in ipairs(test.rows) do sorted[i] = row end
	table.sort(sorted, function(a, b) return a.totalAmount > b.totalAmount end)
	return sorted
end

local function Read()
	if test then
		if GetTime() > test.ends then
			test = nil
		else
			test.burst = (GetTime() % 12) > 8 -- (you pop cooldowns now and then)
			Draw(TestRows())
			return
		end
	end
	local sessionType, label = SessionType()
	state.session = label
	Draw(Rows(sessionType, MeterType()))
end

local function Update(_, elapsed)
	local want, why = Allowed()
	state.why = want and "showing" or why
	local target = want and 1 or 0
	if shown ~= target then
		shown = target > shown and math.min(1, shown + elapsed / FADE_TIME) or math.max(0, shown - elapsed / FADE_TIME)
	end
	frame:SetAlpha(shown * (Look().damageVisionOpacity or 1))
	if shown == 0 and not want then
		frame:Hide()
		return
	end
	local now = GetTime()
	if want and now >= nextRead then
		nextRead = now + READ_EVERY
		Read()
	end
	-- (The ladder's marker slides to your row.)
	local ladder = frame.ladder
	if ladder:IsShown() and ladder.target then
		local goal = -(ladder.target - 1) * (ladder.step or 18)
		ladder.markY = ladder.markY + (goal - ladder.markY) * math.min(1, elapsed * 10)
		ladder.mark:ClearAllPoints()
		ladder.mark:SetPoint("TOPRIGHT", ladder, "TOPLEFT", -3, ladder.markY)
	end
end

local function Wake()
	if not frame then return end
	Place()
	Dress()
	frame:Show()
end

-- Recaps ----------------------------------------------------------------------

local function CreateRecap()
	recap = CreateFrame("Frame", "CinematicDamageRecap", UIParent)
	recap:SetClampedToScreen(true) -- (the defaults are near the edges: kept on smaller screens)
	recap:SetSize(WIDTH + 20, 40)
	recap:SetFrameStrata("MEDIUM")
	recap:EnableMouse(false)
	recap:Hide()
	ns.AddOverlay(recap)
	local back = recap:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.55)
	-- (Dungeon done: a Full report button at its top, the one bit you can
	-- click. Over it, the recap waits.)
	local report = CreateFrame("Button", nil, recap, "UIPanelButtonTemplate")
	report:SetSize(120, 22)
	report:SetPoint("TOP", 0, -8)
	report:SetText(L["Full report"])
	if ns.SkinButton then ns.SkinButton(report) end
	report:SetScript("OnClick", function()
		ns.StopDamageRecap()
		if ns.ShowDamageReport then ns.ShowDamageReport(recap.test) end
	end)
	report:SetScript("OnEnter", function() recap.anim:Pause() end)
	report:SetScript("OnLeave", function()
		if recap:IsShown() and recap.anim:IsPaused() then recap.anim:Play() end
	end)
	report:Hide()
	recap.report = report
	recap.title = recap:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	recap.title:SetPoint("TOP", 0, -8)
	recap.place = recap:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	recap.place:SetPoint("TOP", recap.title, "BOTTOM", 0, -2)
	recap.rows = {}
	for i = 1, RECAP_ROWS do
		local row = NewLadderRow(recap)
		row:SetPoint("TOP", recap.place, "BOTTOM", 0, -6 - (i - 1) * 18)
		recap.rows[i] = row
	end
	local anim = recap:CreateAnimationGroup()
	local fadeIn = anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.4)
	fadeIn:SetOrder(1)
	local hold = anim:CreateAnimation("Alpha")
	hold:SetFromAlpha(1)
	hold:SetToAlpha(1)
	hold:SetDuration(RECAP_TIME)
	hold:SetOrder(2)
	local fadeOut = anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(0.8)
	fadeOut:SetOrder(3)
	anim:SetScript("OnFinished", function()
		recap:Hide()
		Wake() -- (the display back in its spot, if it's still wanted)
	end)
	recap.anim = anim
end

-- A recap of rows (a session's, read out of combat: plain). report: with the
-- Full report button (test: it opens the test report, made-up bosses
-- unless the meter has some).
local function ShowRecap(title, rows, top, report, test)
	if not rows or #rows == 0 then return end
	if not recap then CreateRecap() end
	local button = report and ns.ShowDamageReport ~= nil
	recap.report:SetShown(button)
	recap.test = test and "test" or nil
	recap.title:ClearAllPoints()
	recap.title:SetPoint("TOP", 0, button and -36 or -8)
	local look = Look()
	local _, row, step = Heights(look)
	for i, each in ipairs(recap.rows) do
		DressLadderRow(each, look, WIDTH, row)
		each:ClearAllPoints()
		each:SetPoint("TOP", recap.place, "BOTTOM", 0, -6 - (i - 1) * step)
	end
	StyleText(recap.title, look)
	StyleText(recap.place, look)
	recap.title:SetTextColor(TextColor(look))
	local rank = Rank(rows)
	recap.title:SetText(title)
	recap.place:SetText(rank and L["#%d of %d"]:format(rank, #rows) or L["You're not on the meter"])
	FillRows(recap.rows, rows, rank, top, nil, true)
	recap:SetHeight(64 + (button and 28 or 0) + math.min(#rows, RECAP_ROWS) * step)
	recap:SetScale(db.damageVisionSize)
	SpotPoint(recap, db.damageVisionX, db.damageVisionY, db.damageVisionSize, "TOP")
	recap:SetAlpha(0)
	recap:Show()
	recap.anim:Stop()
	recap.anim:Play()
end

-- The boss's own session: the newest named after it ("(!) <boss>").
local function BossSession(name)
	local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
	if not ok or type(sessions) ~= "table" or (issecrettable and issecrettable(sessions)) then return end
	for i = #sessions, 1, -1 do
		local session = sessions[i]
		local sessionName = type(session) == "table" and session.name
		if type(sessionName) == "string" and not Secret(sessionName) and name
			and sessionName:find(name, 1, true) then
			return session.sessionID
		end
	end
end

-- late: waited long enough for the restrictions to lift.
local function RunPending(late)
	if not pending or InCombatLockdown() then return end
	-- (Totals still secret after the fight, a key or a match on: wait a few
	-- seconds for that to lift, then show it anyway, drawn from the secret
	-- totals, as in a fight.)
	if late ~= true and Restricted() then
		if not pending.waiting then
			pending.waiting = true
			C_Timer.After(RESTRICTION_WAIT, function() RunPending(true) end)
		end
		return
	end
	local kind, name = pending.kind, pending.name
	pending = nil
	if not HasMeter() then return end
	if kind == "boss" then
		local id = BossSession(name)
		local rows = id and Rows(nil, MeterType(), id) or Rows(Enum.DamageMeterSessionType.Current, MeterType())
		ShowRecap(L["%s down"]:format(name or L["Boss"]), rows)
	else
		local rows, top = Rows(Enum.DamageMeterSessionType.Overall, MeterType())
		ShowRecap(L["Dungeon done"], rows, top, true)
	end
end

-- Hold a recap until the fight's over (the totals plain again, mostly).
local function Queue(kind, name)
	if not (db.damageVision and HasMeter()) then return end
	if kind == "boss" and not db.damageVisionRecapBoss then return end
	if kind == "run" and not db.damageVisionRecapRun then return end
	pending = { kind = kind, name = name }
	C_Timer.After(1, RunPending)
end

-- Tests, refresh and the debug command ----------------------------------------

function ns.RefreshDamageVision()
	db = ns.GetDB()
	Wake()
	-- (A recap up, or the mover out: to the X and Y as typed.)
	if recap and recap:IsShown() then
		SpotPoint(recap, db.damageVisionX, db.damageVisionY, db.damageVisionSize, "TOP")
	end
	if ns.SnapDamageMovers then ns.SnapDamageMovers() end
end

-- quiet: no line in chat (Show me, with nothing to close).
function ns.TestDamageVision(quiet)
	if not frame then return end
	local mine = UnitName("player")
	local _, class = UnitClass("player")
	test = { ends = GetTime() + TEST_TIME, rows = {
		{ name = mine, isLocalPlayer = true, classFilename = class, totalAmount = 0, rate = 1 },
		{ name = "Mage", isLocalPlayer = false, classFilename = "MAGE", totalAmount = 0, rate = 1.06 },
		{ name = "Rogue", isLocalPlayer = false, classFilename = "ROGUE", totalAmount = 0, rate = 0.97 },
		{ name = "Hunter", isLocalPlayer = false, classFilename = "HUNTER", totalAmount = 0, rate = 0.88 },
		{ name = "Priest", isLocalPlayer = false, classFilename = "PRIEST", totalAmount = 0, rate = 0.5 },
	} }
	lastRank = nil
	Wake()
	if quiet then return end
	ns.Print(L["Damage Vision test: a made-up fight for 25 seconds. Close the settings to see it."])
end

function ns.TestDamageRecap()
	local rows = HasMeter() and Rows(Enum.DamageMeterSessionType.Overall, MeterType())
	if not rows or #rows == 0 or InCombatLockdown() then
		local mine = UnitName("player")
		local _, class = UnitClass("player")
		rows = { { name = "Mage", classFilename = "MAGE", totalAmount = 5400000 },
			{ name = mine, isLocalPlayer = true, classFilename = class, totalAmount = 4900000 },
			{ name = "Rogue", classFilename = "ROGUE", totalAmount = 4100000 },
			{ name = "Priest", classFilename = "PRIEST", totalAmount = 1200000 } }
	end
	ShowRecap(L["Dungeon done"], rows, nil, true, true)
end

-- The tests running (for their buttons, Stop while they are), and stopping them.
function ns.DamageVisionTesting()
	return test ~= nil
end
function ns.StopDamageVisionTest()
	test = nil
	lastRank = nil
end
function ns.DamageRecapShowing()
	return recap ~= nil and recap:IsShown()
end
function ns.StopDamageRecap()
	if not recap then return end
	recap.anim:Stop()
	recap:Hide()
	Wake()
end

-- Movers (as speech from behind's, Speech.lua): a box where the display (and
-- its recap) sits, its size. Drag it, left-click to set (and see a test),
-- right-click to put it back where it started.
local MOVERS = {
	display = { x = "damageVisionX", y = "damageVisionY", point = "TOP", height = 60,
		text = "Damage Vision and its recap show here.\nDrag it where you want it, left-click to set, right-click to reset.",
		editText = "Damage Vision\nDrag to move, right-click to reset" },
}
local movers = {}

-- inEditMode: shown by the game's Edit Mode (Core.lua's ns.OnEditMode): in its
-- blue, no close button, a click doesn't close it; it goes as Edit Mode closes.
function ns.MoveDamageVision(which, inEditMode)
	db = ns.GetDB()
	local info = MOVERS[which]
	if not info then return end
	local mover = movers[which]
	if not mover then
		mover = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
		mover:SetFrameStrata("FULLSCREEN_DIALOG")
		mover:SetClampedToScreen(true)
		mover:SetMovable(true)
		mover:RegisterForDrag("LeftButton")
		mover:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		mover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1 })
		mover:SetBackdropColor(0, 0, 0, 0.6)
		mover:SetBackdropBorderColor(1, 0.82, 0, 1)
		local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("CENTER")
		mover.label = label
		local close = CreateFrame("Button", nil, mover, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 4, 4)
		mover.close = close
		function mover.Snap()
			local size = db.damageVisionSize
			mover:SetSize((Look().damageVisionWidth or WIDTH) * size, info.height * size)
			SpotPoint(mover, db[info.x], db[info.y], 1, info.point)
		end
		-- (Moved: the page's X and Y boxes show it, if the settings are open.)
		local function Moved()
			mover.Snap()
			if frame then Place() end
			if ns.RefreshOptions then pcall(ns.RefreshOptions) end
		end
		mover:SetScript("OnDragStart", mover.StartMoving)
		mover:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			if self.SetUserPlaced then self:SetUserPlaced(false) end
			local left, right, top, bottom = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
			local width, height = UIParent:GetWidth(), UIParent:GetHeight()
			if type(left) == "number" and type(top) == "number" and width > 0 and height > 0 then
				local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
				local y = info.point == "TOP" and top or (top + bottom) / 2
				db[info.x] = math.floor((left + right) / 2 * scale - width / 2 + 0.5)
				db[info.y] = math.floor(y * scale - height / 2 + 0.5)
			end
			Moved()
			self.draggedAt = GetTime() -- (the button-up ending a drag isn't a click)
		end)
		mover:SetScript("OnClick", function(self, button)
			if self.draggedAt and GetTime() - self.draggedAt < 0.2 then
				return
			elseif button == "RightButton" then
				db[info.x], db[info.y] = ns.DEFAULTS[info.x], ns.DEFAULTS[info.y]
				Moved()
			elseif not self.inEditMode then
				self:Hide()
				ns.TestDamageVision()
			end
		end)
		movers[which] = mover
	end
	if not inEditMode and mover.inEditMode and mover:IsShown() then
		inEditMode = true -- (the Move button while Edit Mode has it up: keep it Edit Mode's)
	end
	mover.inEditMode = inEditMode or nil
	mover.label:SetText(inEditMode and ns.EditModeName(L[info.editText]) or L[info.text])
	mover.close:SetShown(not inEditMode)
	ns.EditModeLook(mover, inEditMode)
	mover.Snap()
	mover:Show()
end

ns.OnEditMode(function()
	db = ns.GetDB()
	if ns.Setting("damageVision") and HasMeter() then
		for which in pairs(MOVERS) do ns.MoveDamageVision(which, true) end
	end
end, function()
	for _, mover in pairs(movers) do
		if mover.inEditMode then
			mover:Hide()
			mover.inEditMode = nil
		end
	end
end)

function ns.SnapDamageMovers()
	for _, mover in pairs(movers) do
		if mover:IsShown() then mover.Snap() end
	end
end

-- /cine debug damagevision: shown or why not, the session and meter it reads,
-- your place, and what's secret.
function ns.DamageVisionDebug()
	db = ns.GetDB()
	local want, why = Allowed()
	local _, kind = GetInstanceInfo()
	ns.Print(("damagevision: %s; page %s, style %s, client meter %s"):format(want and "showing" or ("hidden: " .. why),
		tostring(db.damageVision), tostring(db.damageVisionStyle), HasMeter() and "yes" or "no"))
	ns.Print(("  combat %s, boss fight %s, here %s, CineMode %s, test %s"):format(tostring(InCombatLockdown()),
		tostring(encounter), tostring(kind), tostring(ns.lastCinematic and true or false), test and "on" or "off"))
	if not HasMeter() then return end
	local ok, available, reason = pcall(C_DamageMeter.IsDamageMeterAvailable)
	ns.Print(("  game's meter available: %s%s; %s CVar: %s"):format(ok and tostring(available) or "error",
		reason ~= nil and (" (" .. tostring(reason) .. ")") or "", METER_CVAR,
		tostring(C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(METER_CVAR))))
	local sessionType, label = SessionType()
	local rows = Rows(sessionType, MeterType())
	ns.Print(("  counting %s (%s), %s"):format(label, MeterType() == Enum.DamageMeterType.HealingDone and "healing"
		or "damage", rows and (#rows .. " on the list") or "no list (secret or missing)"))
	if rows then
		local rank = Rank(rows)
		local mine = rank and rows[rank]
		ns.Print(("  you: %s; totals %s; racing #%s"):format(rank and ("#" .. rank) or "not on it",
			mine and (Secret(mine.totalAmount) and "secret" or "plain") or "-", rank and tostring(Rival(rank)) or "-"))
	end
	ns.Print(("  restriction on: %s; meter last reset: %s"):format(tostring(Restricted()), state.reset or "not seen"))
	if pending then ns.Print("  recap waiting: " .. pending.kind) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, ...)
	-- (The meter changed: read it next frame. Often, so nothing else.)
	if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
		nextRead = 0
		return
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		C_Timer.After(0.2, RunPending)
		return
	elseif event == "DAMAGE_METER_RESET" then
		state.reset = date("%H:%M:%S") -- (Auto Reset, or a reset by hand: The whole run starts again)
		lastRank = nil
		nextRead = 0
		return
	end
	if event == "PLAYER_LOGIN" then
		db = ns.GetDB()
		Create()
		ns.SetOnUpdate(frame, Update)
		for _, other in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ENCOUNTER_START", "ENCOUNTER_END",
			"PLAYER_ENTERING_WORLD", "LFG_COMPLETION_REWARD", "CHALLENGE_MODE_COMPLETED",
			"DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_RESET", "ADDON_RESTRICTION_STATE_CHANGED", "CVAR_UPDATE" }) do
			pcall(events.RegisterEvent, events, other)
		end
	elseif event == "ENCOUNTER_START" then
		local _, name = ...
		encounter = name or true
		state.boss = true
	elseif event == "ENCOUNTER_END" then
		local _, name, _, _, success = ...
		encounter = nil
		if success == 1 then Queue("boss", name) end
	elseif event == "PLAYER_REGEN_DISABLED" then
		state.boss = encounter and true or false
		lastRank = nil
	elseif event == "PLAYER_REGEN_ENABLED" then
		lastFight = GetTime()
		C_Timer.After(0.5, RunPending)
	elseif event == "LFG_COMPLETION_REWARD" or event == "CHALLENGE_MODE_COMPLETED" then
		Queue("run")
	elseif event == "PLAYER_ENTERING_WORLD" then
		encounter = nil
	end
	Wake()
end)

-- The Damage Vision pages (in the Visions hub, the dev copy's), three folder
-- tabs under one icon. Vision: its switch, when it shows (its Show in row),
-- what it counts and the recaps. Settings: its type (picture tiles), what
-- shows over it, and the settings of the type picked (only that type's).
-- Look: its colors, bars, words and where it sits. Options.lua calls them
-- with the page helpers it shares.

local function DamageTabs(content, title, picked)
	local panel = ns.PageTabs(content, {
		{ L["Vision"], "Damage Vision", L["Turning it on, when it shows, what it counts, its tests and the " ..
			"picked type's settings."] },
		{ L["Look"], "Damage Vision Look", L["Its type, colors, bars and words, and where it sits."] },
	}, picked)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
end

-- Rows for a page's stack, each a name in a column 150 wide and its control
-- after it, so every control on the page starts at the same place. enabled:
-- a test(db) greying a control (nil: never greyed). Each gives what it made
-- (to show or hide together).
local NAME_W = 150
local function Builder(kit, content, stack, Changed)
	local b = {}
	function b.Button(parent, text, width, tip, onClick)
		local button = ns.PanelButton(parent)
		button:SetSize(width, 22)
		button:SetText(text)
		if tip then kit.Tooltip(button, tip) end
		button:SetScript("OnClick", onClick)
		return button
	end
	-- A line: its name at the left. Gives the line and the name.
	function b.Row(label, height)
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(560, height or 26)
		stack:Add(row, "label", 2)
		local name = kit.Label(row, "GameFontHighlight", label)
		name:SetPoint("LEFT")
		name:SetWidth(NAME_W)
		name:SetJustifyH("LEFT")
		return row, name
	end
	-- A number box in the column. unit: after the box ("px", "%").
	function b.Number(label, key, minV, maxV, step, scale, unit, tip, enabled)
		local row, name = b.Row(label)
		local line = kit.BoxLine(content) -- (the page's: its Reset puts it back)
		line:SetPoint("LEFT", name, "RIGHT", 4, 0)
		local box = line:Box("", key, minV, maxV, step, "%d", scale, tip, Changed, 52, unit)
		if enabled then
			kit.GreyUnless(box, enabled)
			local refresh = box.Refresh
			box.Refresh = function(self)
				refresh(self)
				local on = enabled(ns.GetDB()) and 1 or 0.5
				self:SetAlpha(on)
				name:SetAlpha(on)
			end
		end
		return { row, line }
	end
	-- Ticks in a line in the column: { key, text, tip, enabled } each.
	function b.Toggles(label, list, enabled)
		local row, name = b.Row(label)
		local made, last = { row }, nil
		for _, info in ipairs(list) do
			local key = info[1]
			local check = kit.Check(content, key, info[2], info[3], function(value)
				ns.GetDB()[key] = value
				Changed()
				kit.Refresh()
			end)
			if last then
				check:SetPoint("LEFT", last.Text or last.text or last, "RIGHT", 16, 0)
			else
				check:SetPoint("LEFT", name, "RIGHT", 0, 0)
			end
			local test = info[4] or enabled
			if test then kit.GreyUnless(check, test) end
			made[#made + 1] = check
			last = check
		end
		return made
	end
	-- Choices in a line in the column: { value, text, tip } each.
	function b.Choices(label, key, list, enabled)
		local row, name = b.Row(label)
		local made, last = { row }, nil
		for _, info in ipairs(list) do
			local choice = kit.Choice(content, key, info[1], info[2], info[3])
			choice:HookScript("OnClick", Changed)
			if last then
				choice:SetPoint("LEFT", last.Text or last.text or last, "RIGHT", 16, 0)
			else
				choice:SetPoint("LEFT", name, "RIGHT", 0, 0)
			end
			if enabled then kit.GreyUnless(choice, enabled) end
			made[#made + 1] = choice
			last = choice
		end
		return made, last
	end
	return b
end
ns.VisionRows = Builder -- (the other Visions' pages, laid out the same: EmoteVision.lua)

local TypeSettings -- (below: the tests and the picked type's settings)
function ns.CreateDamageVisionPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Damage Vision"])
	DamageTabs(content, title, 1)
	local intro = kit.PageIntro(content, title,
		L["Not the damage meter's numbers: your race with the player ahead of you, or your lead over #2 once " ..
		"you're #1. It reads the game's own damage meter, so that needs to be on (Options, Gameplay " ..
		"Enhancements: Enable Damage Meter). Its type and how it looks: the Look tab."])
	local function Changed()
		ns.RefreshDamageVision()
	end
	local switch = kit.PageSwitch(content, "damageVision", L["Enable Page"],
		L["On: everything below works as ticked. Off: none of it does, and each keeps its tick for " ..
		"when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local b = Builder(kit, content, stack, Changed)
	local rows = ns.StyleRows(kit, content, stack, Changed, "damageVision")
	local function Any() return true end

	-- Where: its Show in row (the default one, as Vitals Vision's), Instances
	-- ticked to start with.
	local header = stack:Header(content, L["Show in"])
	local lastRow = ns.ShowTable(content, header, {
		opts = { anyFight = true }, underHeader = true,
		{ key = ROW_KEY, label = L["Damage Vision"], alwaysKey = "damageVisionAlways",
			alwaysOn = function() return ns.GetDB().damageVisionAlways end,
			setAlways = function(value) ns.GetDB().damageVisionAlways = value Changed() end,
			alwaysTip = L["Shows in every fight, wherever you are. (The other columns then have nothing to add.)"],
			apply = Changed },
	}, L["Damage Vision"])
	stack:Continue(lastRow, "label")

	stack:Header(content, L["When"])
	rows.Dropdown(L["Show during:"], "damageVisionDuring", {
		{ value = "all", text = L["Every fight"] },
		{ value = "boss", text = L["Boss fights only"] },
	}, nil, Any)
	b.Toggles(L["Only:"], {
		{ "damageVisionOnlyCine", L["In CineMode"], L["Ticked, only while the UI is faded."] },
	})
	b.Number(L["Stays after a fight:"], "damageVisionHold", 0, 30, 1, 1, L["sec"],
		L["How long it stays up once a fight is over."])

	stack:Header(content, L["What it counts"])
	rows.Dropdown(L["Count:"], "damageVisionCount", {
		{ value = "role", text = L["By role (healing for healers)"] },
		{ value = "damage", text = L["Damage"] },
		{ value = "healing", text = L["Healing"] },
	}, nil, Any)
	rows.Dropdown(L["Count from:"], "damageVisionFrom", {
		{ value = "boss", text = L["This boss only"] },
		{ value = "run", text = L["The whole run"] },
		{ value = "fight", text = L["Each fight"] },
	}, L["This boss only: everyone starts at 0 as a boss is pulled, and when it dies it's back to the " ..
		"whole run. The whole run: the meter's Overall. Each fight: every pull starts at 0."], Any)

	stack:Header(content, L["Recaps"])
	b.Toggles(L["Recap after:"], {
		{ "damageVisionRecapBoss", L["A boss"], L["Ticked, how you did on that boss as it dies."] },
		{ "damageVisionRecapRun", L["A dungeon"], L["Ticked, how you did on the whole run as it's done."] },
	})

	TypeSettings(kit, content, stack, b)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Damage Vision")
end

-- The types, as the Look tab's tiles show them: a little picture of
-- each (Draw: its textures on the tile's picture area, 100 x 40).
local TYPES = {
	{ value = "gap", name = "Gap bar", tip = "One bar: full is the player ahead, filled is the one behind.",
		Draw = function(area)
			local track = area:CreateTexture(nil, "ARTWORK")
			track:SetColorTexture(0, 0, 0, 0.6)
			track:SetSize(100, 12)
			track:SetPoint("CENTER")
			local fill = area:CreateTexture(nil, "OVERLAY")
			fill:SetColorTexture(CHASE[1], CHASE[2], CHASE[3], 1)
			fill:SetSize(64, 12)
			fill:SetPoint("LEFT", track, "LEFT")
		end },
	{ value = "race", name = "Race track", tip = "A track with you above it and your rival below; the gap between "
		.. "you in color.",
		Draw = function(area)
			local line = area:CreateTexture(nil, "ARTWORK")
			line:SetColorTexture(0.55, 0.55, 0.55, 0.8)
			line:SetSize(100, 4)
			line:SetPoint("CENTER")
			local gap = area:CreateTexture(nil, "OVERLAY")
			gap:SetColorTexture(LEAD[1], LEAD[2], LEAD[3], 1)
			gap:SetSize(26, 4)
			gap:SetPoint("RIGHT", line, "RIGHT")
			for _, each in ipairs({ { 50, 10, LEAD }, { 24, -10, { 0.41, 0.8, 0.94 } } }) do
				local dot = area:CreateTexture(nil, "OVERLAY", nil, 1)
				dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
				dot:SetSize(12, 12)
				dot:SetVertexColor(each[3][1], each[3][2], each[3][3])
				dot:SetPoint("CENTER", line, "CENTER", each[1], each[2])
			end
		end },
	{ value = "ladder", name = "Rank ladder", tip = "The top players as rows, your row lit.",
		Draw = function(area)
			local widths, colors = { 100, 80, 66, 48 }, { LEAD, { 0.41, 0.8, 0.94 }, { 1, 0.96, 0.41 }, { 0.67, 0.83, 0.45 } }
			for i, width in ipairs(widths) do
				local bar = area:CreateTexture(nil, "ARTWORK")
				local color = colors[i]
				bar:SetColorTexture(color[1], color[2], color[3], i == 1 and 1 or 0.55)
				bar:SetSize(width, 7)
				bar:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -2 - (i - 1) * 10)
			end
		end },
}

-- The look's settings the presets set (the rest as their defaults).
local PRESET_KEYS = { "damageVisionTexture", "damageVisionBarHeight", "damageVisionWidth", "damageVisionOpacity",
	"damageVisionTrack", "damageVisionPanel", "damageVisionColors", "damageVisionChaseR", "damageVisionChaseG",
	"damageVisionChaseB", "damageVisionLeadR", "damageVisionLeadG", "damageVisionLeadB", "damageVisionBorder",
	"damageVisionBorderR", "damageVisionBorderG", "damageVisionBorderB", "damageVisionSmooth", "damageVisionSpark",
	"damageVisionTextSize", "damageVisionOutline", "damageVisionTextColor" }

-- The type as picture tiles (a click picks it), under a Type header: the
-- Look tab's first row. (Not page controls: the Look switch leaves them be.)
local function TypeTiles(kit, content, stack, Changed)
	stack:Header(content, L["Type"])
	local tileRow = CreateFrame("Frame", nil, content)
	tileRow:SetSize(560, 84)
	stack:Add(tileRow, "label", 2)
	local last
	for _, info in ipairs(TYPES) do
		local tile = CreateFrame("Button", nil, tileRow)
		tile:SetSize(124, 80)
		if last then tile:SetPoint("LEFT", last, "RIGHT", 10, 0) else tile:SetPoint("LEFT") end
		local back = tile:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0, 0, 0, 0.45)
		local lit = tile:CreateTexture(nil, "BORDER")
		lit:SetAllPoints()
		lit:SetColorTexture(1, 0.82, 0, 0.08)
		local area = CreateFrame("Frame", nil, tile)
		area:SetSize(100, 40)
		area:SetPoint("TOP", 0, -10)
		info.Draw(area)
		local name = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("BOTTOM", 0, 8)
		name:SetText(L[info.name])
		local edges = ns.MakeStyleEdges(tile)
		kit.Tooltip(tile, L[info.tip])
		tile:SetScript("OnClick", function()
			ns.GetDB().damageVisionStyle = info.value
			Changed()
			kit.Refresh()
		end)
		tile.Refresh = function()
			local picked = ns.GetDB().damageVisionStyle == info.value
			ns.DressStyleEdges(edges, picked and 2 or 1, picked and 1 or 0.4, picked and 0.82 or 0.4,
				picked and 0 or 0.4, 1)
			lit:SetShown(picked)
			name:SetTextColor(picked and 1 or 0.8, picked and 0.82 or 0.8, picked and 0 or 0.8)
		end
		tile.pageSwitch = false
		kit.AddControl(tile)
		last = tile
	end
end

-- The tests, under the Look tab's type tiles: each Stop while it runs (a click
-- stops it), its own name again as it ends. (Not page controls: they work
-- with the page off.)
local function TestButtons(stack, content, b)
	stack:Header(content, L["Test"])
	local tests = b.Row("")
	local function RunButton(width, text, tip, Running, Start, Stop)
		local button = b.Button(tests, text, width, tip, function()
			if Running() then Stop() else Start() end
		end)
		local shown
		ns.SetOnUpdate(button, function(self)
			local running = Running()
			if running ~= shown then
				shown = running
				self:SetText(running and L["Stop"] or text)
			end
		end)
		return button
	end
	local testButton = RunButton(100, L["Test"],
		L["A made-up fight for 25 seconds, to see how it looks (Stop ends it). It works with the page off " ..
		"too. Close the settings to see it."], ns.DamageVisionTesting, ns.TestDamageVision, ns.StopDamageVisionTest)
	testButton:SetPoint("LEFT")
	local recapButton = RunButton(110, L["Test recap"],
		L["The recap card, with the meter's whole run if you've one, else made up (Stop hides it)."],
		ns.DamageRecapShowing, ns.TestDamageRecap, ns.StopDamageRecap)
	recapButton:SetPoint("LEFT", testButton, "RIGHT", 8, 0)
	local reportButton = b.Button(tests, L["Full report"], 110,
		L["The full report: how you did on the run, boss by boss and the rest, with the whole party " ..
		"(/cine report). Made-up bosses while the meter has none."], function() ns.ToggleDamageReport("test") end)
	reportButton:SetPoint("LEFT", recapButton, "RIGHT", 8, 0)
end

-- The Vision tab's last rows: what shows over it, then the picked
-- type's own settings (the type itself: the Look tab's tiles; the others'
-- hidden: each type's start at the same place, last on the page, so
-- nothing's left with a gap).
TypeSettings = function(kit, content, stack, b)
	local sections = {} -- the type's value -> what its settings made

	local function ShowType()
		local picked = ns.GetDB().damageVisionStyle
		for value, made in pairs(sections) do
			for _, each in ipairs(made) do each:SetShown(value == picked) end
		end
	end

	stack:Header(content, L["Over it"])
	b.Toggles(L["Show:"], {
		{ "damageVisionPlace", L["Your place"], L["Ticked, your place over it (#2)."] },
		{ "damageVisionPlaceOf", L["Out of how many"], L["Ticked, \"#2 of 5\". Unticked, just \"#2\"."],
			function(d) return d.damageVisionPlace end },
		{ "damageVisionCrown", L["Crown"], L["Ticked, a crown pops in as you take #1."] },
	})

	-- Each type's own settings, from the same place.
	local from, fromKind = stack.last, stack.kind
	local function Section(value, name, build)
		stack:Continue(from, fromKind)
		local made = { stack:Header(content, name) }
		for _, list in ipairs({ build() }) do
			for _, each in ipairs(list) do made[#made + 1] = each end
		end
		sections[value] = made
	end
	Section("gap", L["Gap bar"], function()
		return b.Toggles(L["On the bar:"], {
			{ "damageVisionRivalName", L["Their name"], L["Ticked, the name of the one you race, in their " ..
				"class's color."] },
			{ "damageVisionTotal", L["Your total"], L["Ticked, your damage (or healing) so far."] },
		})
	end)
	Section("race", L["Race track"], function()
		return (b.Choices(L["Dots:"], "damageVisionDots", {
			{ "circle", L["Circles"], L["Plain discs on arrows: you in your color, them in their class's."] },
			{ "portrait", L["Your portrait"], L["Your face on your dot, their class icon on theirs."] },
			{ "class", L["Class icons"], L["Each dot its player's class icon."] },
		}))
	end)
	Section("ladder", L["Rank ladder"], function()
		return b.Number(L["Rows:"], "damageVisionLadderRows", 2, LADDER_ROWS, 1, 1, nil,
			L["At most this many rows: #1 on down, and you in the last row if you're further down than that."]),
			b.Toggles(L["On the rows:"], {
				{ "damageVisionLadderNames", L["Names"], L["Ticked, each player's name on their row."] },
			})
	end)
	local holder = CreateFrame("Frame", nil, content)
	holder:Hide()
	holder.pageSwitch = false
	holder.Refresh = ShowType
	kit.AddControl(holder)
end

-- Look: a switch of its own (off: the plain look), presets, then the bar,
-- what's behind it, its words, and where it sits.
function ns.CreateDamageVisionLookPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Damage Vision"])
	DamageTabs(content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["Its type, how it looks and where it sits. Press Test and close the settings " ..
		"to see it."])
	local function Changed()
		ns.RefreshDamageVision()
	end
	local switch = kit.PageSwitch(content, "damageVisionLook", L["Enable Page"],
		L["On: it looks as this page says. Off: Cinematic's plain look (the defaults). Each setting keeps its " ..
		"value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "damageVisionLook")
	local b = Builder(kit, content, stack, Changed)
	local On = rows.On

	TypeTiles(kit, content, stack, Changed)
	TestButtons(stack, content, b)
	stack:Header(content, L["Look"])
	rows.PresetMenu({
		{ L["Cinematic's"], L["As it comes: amber when you're behind, teal when you lead, a thin border."], {} },
		{ L["Minimal"], L["A thin line, no border or spark."],
			{ damageVisionBarHeight = 6, damageVisionBorder = "none", damageVisionSpark = false, damageVisionTrack = 0.25,
				damageVisionTextSize = 0.9 } },
		{ L["Arcade"], L["A big bar in a gold frame, red when you're behind, gold when you lead, loud words."],
			{ damageVisionBarHeight = 22, damageVisionWidth = 320, damageVisionBorder = "thick", damageVisionBorderR = 1,
				damageVisionBorderG = 0.82, damageVisionBorderB = 0, damageVisionColors = "custom",
				damageVisionChaseR = 0.9, damageVisionChaseG = 0.2, damageVisionChaseB = 0.2, damageVisionLeadR = 1,
				damageVisionLeadG = 0.82, damageVisionLeadB = 0, damageVisionPanel = 0.4,
				damageVisionTextSize = 1.2, damageVisionOutline = 2 } },
		{ L["Your class"], L["The bar in your class's color, whether you lead or chase."],
			{ damageVisionColors = "class" } },
		{ L["Ghost"], L["Half see-through, no border or spark: there, but out of the way."],
			{ damageVisionOpacity = 0.5, damageVisionTrack = 0.2, damageVisionBorder = "none",
				damageVisionSpark = false } },
	}, PRESET_KEYS)

	stack:Header(content, L["Bar"])
	rows.Texture(L["Texture:"], "damageVisionTexture", L["The bars' fill."], nil, { 0.94, 0.62, 0.15 }, L["Cinematic's"])
	local _, colorsLast = b.Choices(L["Colors:"], "damageVisionColors", {
		{ "status", L["Behind and ahead"], L["Amber while you're behind, teal once you lead (or your own two)."] },
		{ "class", L["Your class"], L["Your class's color, whether you lead or chase."] },
		{ "custom", L["Your own"], L["The two colors after it."] },
	}, On)
	local chase = rows.Swatch(colorsLast, "damageVisionColors",
		{ "damageVisionChaseR", "damageVisionChaseG", "damageVisionChaseB" },
		L["The bar's color while you're behind. Picking one turns Colors to Your own."])
	rows.Swatch(chase, "damageVisionColors", { "damageVisionLeadR", "damageVisionLeadG", "damageVisionLeadB" },
		L["The bar's color once you lead. Picking one turns Colors to Your own."])
	local _, borderLast = b.Choices(L["Border:"], "damageVisionBorder", {
		{ "none", L["None"] }, { "thin", L["Thin"] }, { "thick", L["Thick"] },
	}, On)
	rows.Swatch(borderLast, nil, { "damageVisionBorderR", "damageVisionBorderG", "damageVisionBorderB" },
		L["The border's color."])
	b.Number(L["Height:"], "damageVisionBarHeight", 4, 32, 1, 1, "px",
		L["How tall the bar is (the race track's line is half that, the ladder's rows a little more)."], On)
	b.Number(L["Width:"], "damageVisionWidth", 120, 500, 10, 1, "px", L["How wide it is."], On)
	b.Toggles(L["Extras:"], {
		{ "damageVisionSmooth", L["Smooth"], L["Ticked, the bars glide to each new value instead of jumping."] },
		{ "damageVisionSpark", L["Spark"], L["Ticked, a bright spark at the edge of the filled part."] },
	}, On)

	stack:Header(content, L["See-through"])
	b.Number(L["Opacity:"], "damageVisionOpacity", 20, 100, 5, 100, "%", L["How see-through the whole of it is."], On)
	b.Number(L["Behind the bar:"], "damageVisionTrack", 0, 100, 5, 100, "%",
		L["How dark the empty part of the bar is."], On)
	b.Number(L["Panel:"], "damageVisionPanel", 0, 100, 5, 100, "%",
		L["A dark panel behind it all, this dark. 0: none."], On)

	stack:Header(content, L["Words"])
	rows.Font("damageVisionFont")
	b.Number(L["Size:"], "damageVisionTextSize", 70, 160, 5, 100, "%", L["The words' size, next to their own."], On)
	rows.Outline("damageVisionOutline", L["Outline"], 2, { [0] = L["None"], L["Thin"], L["Thick"] })
	b.Choices(L["Shadow:"], "damageVisionShadow", {
		{ "general", L["General"] }, { "game", L["The game's"] }, { "on", L["Shadow"] }, { "none", L["None"] },
	}, On)
	local _, textLast = b.Choices(L["Color:"], "damageVisionTextColor", {
		{ "gold", L["Gold"] }, { "white", L["White"] }, { "custom", L["Your own"] },
	}, On)
	rows.Swatch(textLast, "damageVisionTextColor", { "damageVisionTextR", "damageVisionTextG", "damageVisionTextB" },
		L["The place's color (and the recap's title). Picking one turns it to Your own."])

	stack:Header(content, L["Position"])
	b.Number(L["Scale:"], "damageVisionSize", 50, 200, 10, 100, "%", L["Everything at once, bars and words."])
	-- Its X and Y from the middle of the screen (the recap's too), and its mover.
	local XY_TIP = L["How far right (X) and up (Y) from the middle of the screen it sits; below 0, left or down. " ..
		"Dragging it with Move fills these in."]
	local function Spot(label, xKey, yKey, buttonText, buttonTip, which)
		local row, name = b.Row(label)
		local line = kit.BoxLine(content) -- (the page's: its Reset puts them back)
		line:SetPoint("LEFT", name, "RIGHT", 4, 0)
		line:Box("X", xKey, -2000, 2000, 1, "%d", 1, XY_TIP, Changed, 52)
		local yBox = line:Box("Y", yKey, -1200, 1200, 1, "%d", 1, XY_TIP, Changed, 52)
		local button = b.Button(row, buttonText, 110, buttonTip, function() ns.MoveDamageVision(which) end)
		button:SetPoint("LEFT", yBox, "RIGHT", 16, 0)
	end
	Spot(L["Damage Vision:"], "damageVisionX", "damageVisionY", L["Move"],
		L["A box where it and its recap show: drag it where you want it, left-click to set, right-click to put " ..
		"it back. Close the settings to see it."], "display")

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Damage Vision Look")
end
