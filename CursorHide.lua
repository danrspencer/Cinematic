-- Cursor Hide (Interface hub, Overhead): in CineMode, the cursor gets out of
-- the way, where its Show in row says. Three ways:
--   tiny: swapped for the game's tiniest cursor (SetCursor; just a corner).
--     SetCursor takes only the game's own Interface\Cursor files (tested: our
--     files, other textures and missing files all draw a black square; none
--     of its 389 cursors is blank). The game puts its own world cursor back
--     nearly every frame, but not over a frame: a screen-wide one that takes
--     mouse movement only (clicks go through) is up meanwhile.
--   steer: gone, by mouse-steering mode (as holding the right button). It
--     turns you as the mouse moves at your turn speeds (not mouseSpeed:
--     tested), so those are held at 0.1 meanwhile (the game refuses 0),
--     through Core.lua's shared speed hold. It takes its turn as a camera
--     (ns.RegisterCamera): none of ours moves the view while it's hidden, and
--     it waits for theirs and for our camera to be behind you (switching it
--     on turns you to face the camera). Camera.lua and Effects.lua leave its
--     steering out of "you moving" (ns.cursorSteering). Any turn at all
--     brings the cursor back (GetCursorDelta missed moves: tested); a mouse
--     moved only up or down can't be seen.
--   both (Tiny, then gone): tiny all the time, and gone (steering) once the
--     mouse has been still for the delay; moving brings back the tiny one.
-- Back as the mouse moves, a button's pressed, the cursor picks something up,
-- you type, or the row stops showing; not again till the mouse has moved.
-- /cine debug cursor: its state. The Cinema profile has it on flights
-- (ProfileModules.lua's cursor-hide).
local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.cursorHide = false        -- at all (its page's switch)
DEFAULTS.cursorHideAlways = true   -- ...all through CineMode: its Show in row's Always (the rest: ROW_KEY's)
DEFAULTS.cursorHideMethod = "tiny" -- "tiny": the tiniest cursor; "steer": gone; "both": tiny, then gone once still
DEFAULTS.cursorHideDelay = 5       -- seconds the mouse is still first (3 at least: DELAY_MIN)

local ROW_KEY = "cursor:hide"
local TINY = "Interface\\Cursor\\UnableItem"
local WHO = "cursorhide" -- (its name as a camera, and on the turn speeds it holds)
local TURN_SPEEDS = { "cameraYawMoveSpeed", "cameraPitchMoveSpeed" }
local LOWEST = { 0, 0.1, 1 } -- (the lowest turn speed the game takes: 0.1, tested)
local BEHIND = 3 -- degrees our camera may be off straight behind you, for steering to start
local GRACE = 0.15 -- seconds after steering starts that its own jolt is let be
local LAND = 0.3 -- seconds after it lets go that the cursor landing a pixel off isn't a move
local ROW_EVERY = 0.25 -- seconds between reads of the Show in row (rules aren't cheap)
local DELAY_MIN, DELAY_MAX = 3, 10 -- (the slider; a saved one under 3, from before, counts as 3)

-- The tiny cursor all the time, as you move and click too (only something on
-- the cursor or the row turning off brings yours): Tiny, then gone ("both").
local function TinyAlways()
	return ns.db.cursorHideMethod == "both"
end
local function Delay()
	return math.max(DELAY_MIN, tonumber(ns.db.cursorHideDelay) or DELAY_MIN)
end

ns.cursorHidden = false
ns.cursorSteering = false
local cursorX, cursorY, stillSince = nil, nil, 0
local hiddenAt, hiddenFacing, shownAt
local needMove -- (after it came back: not again till the mouse has moved)
local lastBlock, lastShowWhy
local rowShows, rowReadAt = false, -1

local function Facing()
	local ok, facing = pcall(GetPlayerFacing)
	if ok and type(facing) == "number" and not (issecretvalue and issecretvalue(facing)) then
		return facing
	end
end

-- Whether the mouse moved this frame while steering (the cursor stays put).
local function SteerMoved()
	if not GetCursorDelta then return false end
	local ok, dx, dy = pcall(GetCursorDelta)
	return ok and type(dx) == "number" and type(dy) == "number" and (dx ~= 0 or dy ~= 0)
end

local function HoldTurns(hold)
	for _, cvar in ipairs(TURN_SPEEDS) do
		if hold then
			for _, value in ipairs(LOWEST) do
				ns.SetHeldSpeed(WHO, cvar, value)
				local got = tonumber(GetCVar(cvar))
				if got and got <= value + 0.001 then break end
			end
		else
			ns.ReleaseSpeed(WHO, cvar)
		end
	end
end

local cover
local function Cover()
	if cover then return cover end
	cover = CreateFrame("Frame", nil, WorldFrame)
	cover:SetAllPoints(WorldFrame)
	cover:SetFrameStrata("FULLSCREEN_DIALOG")
	if cover.EnableMouseMotion then
		cover:EnableMouseMotion(true)
		if cover.EnableMouseClicks then cover:EnableMouseClicks(false) end
		if cover.SetPropagateMouseClicks then cover:SetPropagateMouseClicks(true) end
		cover.motionOnly = true
	end
	cover:Hide()
	return cover
end

-- Whether its Show in row has it on here and now: Always, else its rule or
-- its ticks (as Vitals Vision's row reads). (Rule first, tested: a row the
-- rule editor had been through keeps a blank rule, "never", and Always then
-- did nothing.)
local function RowShows(now)
	if ns.db.cursorHideAlways then return true end
	if now - rowReadAt >= ROW_EVERY then
		rowReadAt = now
		local ok, shows = pcall(ns.RowOnNow, ROW_KEY, false, true)
		rowShows = ok and shows and true or false
	end
	return rowShows
end

-- Why it can't hide at all now (or nil): yours is wanted.
local function Blocked(now)
	if not ns.db.cursorHide then return "off" end
	if not ns.lastCinematic then return "CineMode off" end
	if not RowShows(now) then return "its Show in row is off here" end
	if GetCursorInfo() ~= nil then return "cursor holding something" end
end
-- Why the cursor's wanted for a moment (or nil): typing, a click, your own
-- steering. Not for the tiny cursor all the time (it clicks fine).
local function Busy()
	if ns.IsChatActive and ns.IsChatActive() then return "typing in chat" end
	if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then return "mouse button down" end
	if IsMouselooking() and not ns.cursorSteering then return "you're steering" end
end

local function Show(why)
	if not ns.cursorHidden then return end
	ns.cursorHidden, needMove, shownAt, lastShowWhy = false, true, GetTime(), why
	if ns.cursorSteering then
		ns.cursorSteering = false
		if IsMouselooking() then pcall(MouselookStop) end
		HoldTurns(false)
	else
		if cover then cover:Hide() end
		pcall(ResetCursor)
	end
	ns.LogDetail("cursor", "back: " .. why)
end

local function HideTiny(now)
	if Cover().motionOnly then cover:Show() end
	if pcall(SetCursor, TINY) then
		ns.cursorHidden, hiddenAt = true, now
		ns.LogDetail("cursor", "tiny")
	else
		cover:Hide()
		lastBlock, stillSince = "SetCursor failed", now
	end
end

-- Why steering can't start now (or nil): our camera off to one side (it
-- would turn you to face it), or one of ours moving the view.
local function SteerHeld()
	local angle = ns.orbit and ns.orbit.angle or 0
	if math.abs(angle) > BEHIND then return ("the camera's %.0f degrees off behind you"):format(angle) end
	local holder = ns.CameraHolder and ns.CameraHolder(WHO)
	if holder then return "the " .. tostring(holder) .. " camera has the view" end
end

local function HideSteer(now)
	if not ns.ClaimCamera(WHO) then return end
	HoldTurns(true)
	if pcall(MouselookStart) and IsMouselooking() then
		ns.cursorHidden, ns.cursorSteering, hiddenAt, hiddenFacing = true, true, now, nil
		ns.LogDetail("cursor", "gone (steering)")
	else
		HoldTurns(false)
		lastBlock, stillSince = "steering wouldn't start", now
	end
end

-- Whether the mouse has been still long enough for steering (and nothing in
-- its way): sets lastBlock when something is.
local function SteerDue(now)
	if needMove then
		lastBlock = "waiting for the mouse to move first"
		return false
	end
	if now - stillSince < Delay() then return false end
	local held = SteerHeld()
	if held then lastBlock = held end
	return not held
end

local driver = CreateFrame("Frame")
local function Update()
	local now = GetTime()
	local x, y = GetCursorPosition()
	local moved = x ~= cursorX or y ~= cursorY
	if moved then
		cursorX, cursorY, stillSince = x, y, now
		if not ns.cursorSteering and now - (shownAt or 0) > LAND then needMove = nil end
	end
	local method, always = ns.db.cursorHideMethod, TinyAlways()
	local blocked = Blocked(now)
	local busy = blocked or Busy()
	lastBlock = always and blocked or busy
	if ns.cursorSteering then
		local facing = Facing()
		local settled = now - hiddenAt > GRACE
		if settled and not hiddenFacing then hiddenFacing = facing end -- (after steering's own turn)
		if busy then
			Show(busy)
		elseif not IsMouselooking() then
			Show("steering ended")
		elseif settled and SteerMoved() then
			Show("mouse moved")
		elseif settled and facing and hiddenFacing and math.abs(facing - hiddenFacing) > 0.000001
			and not (ns.OnTaxi and ns.OnTaxi()) then
			-- (Not on a flight: the taxi turns you along its route all the
			-- time, and brought it back a moment after it went, tested. There
			-- only the mouse itself, a click or typing do.)
			Show("you turned")
		end
		return -- (Tiny, then gone: the tiny one's back next frame)
	end
	if ns.cursorHidden then -- (the tiny one)
		if blocked then
			Show(blocked)
		elseif not always and (moved or busy) then
			Show(moved and "mouse moved" or busy)
		elseif method == "both" and not busy and SteerDue(now) then
			-- (still long enough: from tiny to gone)
			ns.cursorHidden = false
			cover:Hide()
			HideSteer(now)
		else
			pcall(SetCursor, TINY) -- (each frame: the game sets its own when something comes under it)
		end
		return
	end
	if blocked then return end
	if always then
		HideTiny(now)
		return
	end
	if busy then return end
	if method == "steer" then
		if SteerDue(now) then HideSteer(now) end
	elseif not needMove and now - stillSince >= Delay() then
		HideTiny(now)
	elseif needMove then
		lastBlock = "waiting for the mouse to move first"
	end
end

ns.RegisterCamera(WHO, function() return ns.cursorSteering end, function() Show("you took the camera") end)

-- Runs while it's on (its page's switch), stops when off.
local function Apply()
	if ns.db and ns.db.cursorHide then
		ns.SetOnUpdate(driver, Update)
	else
		Show("turned off")
		ns.SetOnUpdate(driver, nil)
	end
end
ns.ApplyCursorHide = Apply

-- (a profile loaded or a page reset: Options' Refresh calls each page's apply)
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_LOGOUT")
loader:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		-- (the test page's old settings, before it had its own)
		if CinematicDB then CinematicDB.debugCursorHide = nil end
		if ns.db then ns.db.debugCursorHideOn = nil end
		Apply()
	else
		Show("logout")
	end
end)

-- /cine debug cursor: what it's doing and why, with what's around it.
function ns.CursorHideDebug()
	local db, now = ns.db, GetTime()
	local p = ns.Print
	p(("Cursor Hide: %s, method %s, delay %.1f s, Always %s, row on here %s"):format(
		db.cursorHide and "on" or "off", tostring(db.cursorHideMethod), Delay(),
		tostring(db.cursorHideAlways), tostring(RowShows(now))))
	p(("  now: %s; held back by: %s; still %.1f s; last back: %s"):format(
		ns.cursorSteering and "gone (steering)" or ns.cursorHidden and "tiny" or "shown",
		needMove and "waiting for the mouse to move" or lastBlock or "nothing", now - stillSince,
		tostring(lastShowWhy)))
	p(("  CineMode %s, fight %s, steering %s, facing %s, orbit %.1f, camera holder %s"):format(
		ns.lastCinematic and "on" or "off", InCombatLockdown() and "yes" or "no",
		IsMouselooking() and "yes" or "no", Facing() and "plain" or "secret/none",
		ns.orbit and ns.orbit.angle or 0, tostring(ns.CameraHolder and ns.CameraHolder(WHO) or "-")))
	p(("  turn speeds %s / %s (held by us %s); cover %s; GetCursorDelta %s; client %s"):format(
		tostring(GetCVar("cameraYawMoveSpeed")), tostring(GetCVar("cameraPitchMoveSpeed")),
		tostring(ns.SpeedHeld and ns.SpeedHeld("cameraYawMoveSpeed", WHO)),
		Cover().motionOnly and (cover:IsShown() and "up" or "down") or "not on this client",
		GetCursorDelta and "yes" or "no", ns.isRetail and "retail" or "classic"))
	-- (The row's rule and the camera facts it reads.)
	local rules = db.frameRules
	local rule = type(rules) == "table" and rules[ROW_KEY]
	local facts = ns.RuleFactsNow and ns.RuleFactsNow() or {}
	local script = ns.PlayingCameraScript and ns.PlayingCameraScript()
	p(("  rule %s -> %s; camera running %s, script %s; on a flight %s; facts camera %s cam_flight %s cam_script %s"):format(
		type(rule) == "string" and ('"' .. rule .. '"') or "none", tostring(ns.RuleShows(ROW_KEY, facts)),
		tostring(ns.activeCam), type(script) == "table" and tostring(script.name or script.key or "?") or tostring(script),
		tostring(ns.OnTaxi and ns.OnTaxi()), tostring(facts.camera), tostring(facts.cam_flight),
		tostring(facts.cam_script)))
end

-- /cine debug cursor log [seconds]: a record of all the above for that long
-- (30 by default), into CinematicDB.debugCursorLog (kept apart from the log:
-- too many lines for it), to read after a /reload. A line each time
-- something changes, and one a second regardless.
local recorder
function ns.CursorHideRecord(seconds)
	seconds = tonumber(seconds) or 30
	CinematicDB.debugCursorLog = {}
	local lines = CinematicDB.debugCursorLog
	local started, lastKey, lastAt = GetTime(), nil, -1
	local lastX, lastY, lastFacing
	recorder = recorder or CreateFrame("Frame")
	local function Snapshot(now)
		local x, y = GetCursorPosition()
		local mouseMoved = x ~= lastX or y ~= lastY
		lastX, lastY = x, y
		local facing = Facing()
		local turned = facing and lastFacing and math.abs(facing - lastFacing) > 0.000001
		lastFacing = facing
		local script = ns.PlayingCameraScript and ns.PlayingCameraScript()
		local db = ns.db
		-- (What decides it, without the times: a line when any of it changes.)
		local key = table.concat({
			"state=" .. (ns.cursorSteering and "gone" or ns.cursorHidden and "tiny" or "shown"),
			"block=" .. tostring(needMove and "needMove" or lastBlock), "back=" .. tostring(lastShowWhy),
			"row=" .. tostring(RowShows(now)), "method=" .. tostring(db.cursorHideMethod),
			"cine=" .. tostring(ns.lastCinematic and true or false),
			"fight=" .. tostring(InCombatLockdown()), "taxi=" .. tostring(ns.OnTaxi and ns.OnTaxi() or false),
			"cam=" .. tostring(ns.activeCam),
			"script=" .. (type(script) == "table" and tostring(script.name or script.key or "?") or tostring(script)),
			"holder=" .. tostring(ns.CameraHolder and ns.CameraHolder(WHO) or "-"),
			"orbit=" .. ("%.0f"):format(ns.orbit and ns.orbit.angle or 0),
			"steering=" .. tostring(IsMouselooking()), "mouse=" .. (mouseMoved and "moving" or "still"),
			"turning=" .. tostring(turned or false), "moving=" .. tostring(ns.playerMoving or false),
			"yaw=" .. tostring(GetCVar("cameraYawMoveSpeed")),
			"cover=" .. tostring(cover and cover:IsShown() or false),
			"item=" .. tostring(GetCursorInfo() ~= nil), "chat=" .. tostring(ns.IsChatActive and ns.IsChatActive() or false),
		}, " ")
		return key
	end
	ns.Print(("Cursor Hide: recording for %d s. /reload after so it's saved."):format(seconds))
	ns.SetOnUpdate(recorder, function()
		local now = GetTime()
		local t = now - started
		if t > seconds then
			ns.SetOnUpdate(recorder, nil)
			lines[#lines + 1] = ("%.2f done"):format(t)
			ns.Print(("Cursor Hide: recorded %d lines. /reload to save them."):format(#lines))
			return
		end
		local key = Snapshot(now)
		if key ~= lastKey or now - lastAt >= 1 then
			lines[#lines + 1] = ("%.2f still=%.1f %s"):format(t, now - stillSince, key)
			lastKey, lastAt = key, now
		end
	end)
end

-- The page ------------------------------------------------------------------

function ns.CreateCursorHidePage(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Cursor Hide"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title, L["In CineMode, the cursor gets out of the way: tiny, gone once " ..
		"the mouse has been still a while, or tiny and then gone. Moving the mouse brings it back."])
	local switch = kit.PageSwitch(content, "cursorHide", L["Enable Page"],
		L["On: the cursor gets out of the way where its Show in row says."], intro, Apply)
	local stack = kit.Stack(switch, "check")
	local header = stack:Header(content, L["Show in"])
	local lastRow = ns.ShowTable(content, header, {
		opts = { anyFight = true }, underHeader = true,
		{ key = ROW_KEY, label = L["Cursor Hide"], alwaysKey = "cursorHideAlways",
			alwaysOn = function() return ns.GetDB().cursorHideAlways end,
			setAlways = function(value) ns.GetDB().cursorHideAlways = value end,
			alwaysTip = L["All through CineMode. (The other columns then have nothing to add.)"],
			apply = function() rowReadAt = -1 end },
	}, L["Cursor Hide"])
	stack:Continue(lastRow, "label")

	stack:Header(content, L["Cursor"])
	stack:Add(kit.Choice(content, "cursorHideMethod", "tiny", L["Tiny"],
		L["Once the mouse has been still a while, the cursor shrinks to a tiny corner. Moving the mouse " ..
		"brings yours back."]), "check")
	stack:Add(kit.Choice(content, "cursorHideMethod", "steer", L["Hide completely"],
		L["Once the mouse has been still a while, the cursor's gone (the game's mouse steering, as holding the " ..
		"right button, with your turn speeds held right down so a nudge doesn't turn you). Only starts with " ..
		"the camera behind you. Moving the mouse a little sideways brings it back (only up or down may not)."]),
		"check")
	stack:Add(kit.Choice(content, "cursorHideMethod", "both", L["Tiny, then gone"],
		L["The tiny cursor all the time, as you move and click too, and gone once the mouse has been still a " ..
		"while (as Hide completely). Moving the mouse brings the tiny one back, not yours."]), "check")
	stack:Add(kit.Slider(content, "cursorHideDelay", L["After the mouse is still for"], DELAY_MIN, DELAY_MAX,
		0.5, "%.1f s"), "slider")

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Cursor Hide")
end
