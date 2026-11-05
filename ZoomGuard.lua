local _, ns = ...

-- Zoom guard: a safety net for our cameras' zooms. Every zoom of ours goes
-- through ns.CameraCall / ns.CallCameraFunction (Camera.lua); this watches the
-- real camera distance each frame while one of ours is zooming. The camera
-- swinging in and out again and again (SWINGS turns of direction, each over
-- SWING_SIZE yards, inside WINDOW seconds) with you not zooming yourself is a
-- zoom gone wrong: two cameras fighting over it, or one chasing its own
-- overshoot. Then our zooms are held for a while (HOLD seconds, doubled for
-- each trip soon after another, up to HOLD_MAX); the slow zoom waits where it
-- is meanwhile (StepIdleZoom), and the trip is logged ("zoom") with who was
-- zooming. /cine debug zoom shows it too.
local SWING_SIZE = 0.75  -- yards back the other way that count as a turn of direction
local SWINGS = 3         -- turns of direction...
local WINDOW = 3         -- ...inside this many seconds trip the guard
local OURS_RECENT = 0.6  -- seconds after one of our zoom commands that the camera counts as ours
local YOURS_RECENT = 1.5 -- seconds after your own zooming that nothing counts
local HOLD = 8           -- seconds our zooms are held after a trip
local HOLD_MAX = 60
local CALM_RESET = 120   -- seconds without a trip before the hold is back to HOLD

local guard = { holdUntil = 0, hold = HOLD, trips = 0, lastTripAt = -math.huge,
	turns = {}, senders = {}, oursAt = -math.huge }
ns.zoomGuard = guard

-- Held now: our zooms are refused.
function ns.ZoomGuardHolds()
	return GetTime() < guard.holdUntil
end

local function IsZoom(name)
	return type(name) == "string" and name:find("^CameraZoom") ~= nil
end

local function NoteOurs(who, name, amount)
	local now = GetTime()
	guard.oursAt = now
	guard.senders[who or "?"] = now
	guard.lastSent = ("%s %s(%.2f)"):format(tostring(who or "?"), name, tonumber(amount) or 0)
end

-- Wrapped once Camera.lua has made them (this file loads after it).
local cameraCall = ns.CameraCall
if cameraCall then
	function ns.CameraCall(who, name, ...)
		if IsZoom(name) then
			if ns.ZoomGuardHolds() then
				return false -- (refused like a claim another camera holds)
			end
			guard.sendingWho = who
		end
		local ok = cameraCall(who, name, ...)
		guard.sendingWho = nil
		return ok
	end
end
local callCamera = ns.CallCameraFunction
if callCamera then
	function ns.CallCameraFunction(name, ...)
		if IsZoom(name) then
			NoteOurs(guard.sendingWho or "direct", name, ...)
		end
		return callCamera(name, ...)
	end
end

local function Trip(now, zoom)
	local who = {}
	for name, at in pairs(guard.senders) do
		if now - at < WINDOW then who[#who + 1] = name end
	end
	table.sort(who)
	if now - guard.lastTripAt > CALM_RESET then
		guard.hold = HOLD
	else
		guard.hold = math.min(HOLD_MAX, guard.hold * 2)
	end
	guard.trips = guard.trips + 1
	guard.lastTripAt = now
	guard.holdUntil = now + guard.hold
	guard.lastWho = table.concat(who, ", ")
	guard.turns = {}
	ns.Log("zoom", ("zoom guard: the camera swung in and out %d times in %d sec (now %.1f yards; zooming: %s; last %s; camera %s): our zooms held %d sec"):format(
		SWINGS, WINDOW, zoom, guard.lastWho ~= "" and guard.lastWho or "?", tostring(guard.lastSent),
		tostring(ns.activeCam or "none"), guard.hold))
end

local function Watch()
	if not GetCameraZoom then return end
	local now = GetTime()
	local zoom = GetCameraZoom()
	if type(zoom) ~= "number" then return end
	local ours = now - guard.oursAt < OURS_RECENT
	local yours = now - (ns.lastPlayerZoomAt or -math.huge) < YOURS_RECENT
	if not ours or yours then
		-- Not ours to judge: start afresh from here.
		guard.extreme, guard.dir, guard.turns = zoom, nil, {}
		return
	end
	guard.extreme = guard.extreme or zoom
	local moved = zoom - guard.extreme
	if not guard.dir then
		if math.abs(moved) >= SWING_SIZE then
			guard.dir, guard.extreme = moved > 0 and 1 or -1, zoom
		end
		return
	end
	if (guard.dir > 0 and zoom > guard.extreme) or (guard.dir < 0 and zoom < guard.extreme) then
		guard.extreme = zoom -- still going the same way: the furthest it's got
	elseif math.abs(moved) >= SWING_SIZE then
		-- Back the other way by enough: a turn of direction.
		guard.dir, guard.extreme = -guard.dir, zoom
		local turns = guard.turns
		turns[#turns + 1] = now
		while turns[1] and now - turns[1] > WINDOW do
			table.remove(turns, 1)
		end
		if #turns >= SWINGS then
			Trip(now, zoom)
		end
	end
end

local frame = CreateFrame("Frame")
ns.SetOnUpdate(frame, Watch)

-- For /cine debug zoom.
function ns.ZoomGuardDebug()
	local now = GetTime()
	local held = guard.holdUntil - now
	return ("zoom guard: %s; trips %d%s; turns of direction just now %d; last zoom sent %s"):format(
		held > 0 and ("holding our zooms %.0f more sec"):format(held) or "not holding",
		guard.trips, guard.trips > 0 and (" (last %.0f sec ago, zooming: %s)"):format(now - guard.lastTripAt,
			guard.lastWho ~= "" and guard.lastWho or "?") or "",
		#guard.turns, tostring(guard.lastSent or "none"))
end
