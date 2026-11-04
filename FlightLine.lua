-- The Flight departure card's progress line (the Cards page's departure
-- row, its Show a line as you fly: cardDepartureLine). On a route flown
-- before (ns.FlightDuration, Camera.lua), a thin line across the top (or
-- bottom) letterbox bar fills up from the left as you fly, the time left at
-- its end ("2 min"). With no bar up: just inside that edge of the screen. It shows
-- while the UI is faded (CineMode) and the card's row allows it, and fades
-- out GONE_BEFORE seconds before landing, as the flight camera settles.
-- With cardDepartureLineEdges over 0, only for the flight's first and last
-- that many seconds; in between, the mouse over its place brings it back
-- (read from the cursor, so nothing takes the mouse's clicks there).

local _, ns = ...
local L = ns.L

local FADE = 0.6       -- seconds a fade in or out takes
local GONE_BEFORE = 2  -- seconds before landing it's gone by
local CHECK = 0.5      -- seconds between asks of whether it may show
local THICK = 2        -- the line's thickness
local SIDE = 0.2       -- the room left at each end, a share of the screen's width
local LOW = 0.012      -- with no bar: its height over the bottom, a share of the screen's
local GOLD = { 0.95, 0.88, 0.65 } -- (the Place style's pale gold)
local HOVER_Y = 20     -- the mouse this near the line (up or down) brings it back
local HOVER_X = 60     -- ...or this far past its ends (its time's on the right)

local line = CreateFrame("Frame", nil, UIParent)
line:SetFrameStrata("BACKGROUND")
line:SetFrameLevel(3) -- (over the letterbox: Effects.lua's, level 2)
line:EnableMouse(false)
line:SetHeight(THICK)
line:Hide()
local track = line:CreateTexture(nil, "ARTWORK")
track:SetAllPoints()
track:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
local fill = line:CreateTexture(nil, "OVERLAY")
fill:SetPoint("TOPLEFT")
fill:SetPoint("BOTTOMLEFT")
fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)
local left = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
left:SetPoint("LEFT", line, "RIGHT", 8, 0)
left:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
left:SetShadowColor(0, 0, 0, 1)
left:SetShadowOffset(1, -1)
if ns.AddOverlay then ns.AddOverlay(line) end -- (stays up with Hide the UI, as the letterbox)
-- (Told to Inspect, Why.lua, as it first shows: Why.lua loads after this,
-- and the words are in your language by then.)
local registered = false
local function Register()
	if registered or not ns.WhyRegister then return end
	registered = true
	ns.WhyRegister(line, L["Flight progress line"], "Card Vision", {
		L["The Flight departure card's line is on: on a route you've flown before, it fills up as you fly"] })
end

local function Flying() return ns.Flag(ns.OnTaxi()) and true or false end

-- The card's Test (Cards.lua's ns.CardTest): a made-up flight of TEST_TIME
-- seconds from now, shown whatever the flight and CineMode.
local TEST_TIME = 15
local test -- { start = GetTime() }
-- The flight's length in all and how long it's been going: the test's, else
-- the real one's (nil: not known).
local function Progress()
	if test then return TEST_TIME, GetTime() - test.start end
	return ns.FlightDuration()
end

-- Whether it may show now (asked every CHECK seconds, not every frame).
local function Wanted()
	if not (ns.db and ns.db.cardDepartureLine) then return false end
	if test then return TEST_TIME - (GetTime() - test.start) > GONE_BEFORE end
	if not (ns.lastCinematic and Flying()) then return false end
	local duration, gone = ns.FlightDuration()
	if not duration or duration - gone <= GONE_BEFORE then return false end
	return ns.CardAllowed("departure") and true or false
end

-- Whether it's in the flight's first or last cardDepartureLineEdges seconds
-- (0: always).
local function InEdges()
	local edge = tonumber(ns.db.cardDepartureLineEdges) or 0
	if edge <= 0 then return true end
	local duration, gone = Progress()
	if not duration then return true end
	return gone < edge or duration - gone < edge
end

-- Whether the mouse is over its place (shown or not).
local function Hovered()
	local l, r, t, b = line:GetLeft(), line:GetRight(), line:GetTop(), line:GetBottom()
	if not (l and r and t and b) then return false end
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	x, y = x / scale, y / scale
	return x >= l - HOVER_X and x <= r + HOVER_X and math.abs(y - (t + b) / 2) <= HOVER_Y
end

-- Its place: the middle of the top or bottom bar (cardDepartureLinePlace)
-- while the letterbox is up, else just inside that edge of the screen.
local function Place()
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local top = ns.db.cardDepartureLinePlace == "top"
	local side = ns.letterbox and ns.letterbox:IsShown() and ns.letterbox[top and "top" or "bottom"]
	local bar = side and side:GetHeight()
	local y = (bar and bar >= 8) and bar / 2 or height * LOW
	line:ClearAllPoints()
	if top then
		line:SetPoint("TOPLEFT", UIParent, "TOPLEFT", width * SIDE, -(y - THICK / 2))
	else
		line:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", width * SIDE, y - THICK / 2)
	end
	line:SetWidth(width * (1 - 2 * SIDE))
end

local alpha, wanted, sinceCheck = 0, false, CHECK
local function Update(_, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck >= CHECK then
		sinceCheck = 0
		local ok, yes = pcall(Wanted)
		wanted = ok and yes or false
		if wanted then Place() end
	end
	-- (Wanted, and at the flight's start or end, or the mouse over it.)
	local shows = wanted and (InEdges() or Hovered())
	alpha = ns.Approach(alpha, shows and 1 or 0, elapsed, FADE)
	-- (Faded out but still flying: kept going, for the UI fading later on.)
	if alpha <= 0 and not shows then
		line:SetAlpha(0)
		if test and GetTime() - test.start > TEST_TIME then test = nil end
		if not (test or Flying()) then line:Hide() end
		return
	end
	line:SetAlpha(alpha)
	local duration, gone = Progress()
	if duration and duration > 0 then
		local share = math.max(0, math.min(1, gone / duration))
		fill:SetWidth(math.max(0.01, line:GetWidth() * share))
		local rest, clock = duration - gone, ns.db.cardDepartureClock
		if clock == "clock" then
			left:SetText(ns.FlightClock(rest))
		elseif clock == "none" then
			left:SetText("")
		else
			-- (Whole minutes, rounded to the nearest like the departure card's
			-- "about 1 min" (CardMoments.lua), so the two agree at takeoff:
			-- "1 min" from 1:00 to 1:29, "2 min" from 1:30 to 2:29.)
			left:SetText(rest < 60 and L["under a minute"] or L["%d min"]:format(math.floor(rest / 60 + 0.5)))
		end
	end
end
ns.SetOnUpdate(line, Update)

-- The line's frame shows (and so updates) only on a flight or a Test: from
-- the flight camera's takeoff (CardMoments.lua's ns.OnTakeoff), and on
-- coming into the world still in the air (a /reload on the way).
local function Start()
	if not (ns.db and ns.db.cardDepartureLine) or line:IsShown() then return end
	Register()
	alpha, wanted, sinceCheck = 0, false, CHECK
	line:SetAlpha(0)
	line:Show()
end
function ns.FlightLineStart() Start() end
-- (The Test: a made-up flight from now, started over if one's on.)
function ns.FlightLineTest()
	test = { start = GetTime() }
	Start()
end
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function()
	C_Timer.After(1, function()
		if Flying() then Start() end
	end)
end)
