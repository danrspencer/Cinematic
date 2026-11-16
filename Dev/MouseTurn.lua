-- Mouse Turn cap (dev copy's Camera Settings page, its Mouse Turn tab; off
-- to start with): turning with the right mouse button held never goes faster
-- than a set speed, so a quick swipe turns smoothly instead of whipping round.
-- The game gives an addon no say over the mouse itself, so this measures how
-- fast you're turning (your facing: under right-click it follows the camera)
-- and turns the mouse look speed down (cameraYawMoveSpeed, the game's Mouse
-- Look Speed) while you go over the cap, easing it back to yours after.
-- The speed you'd turn without us = what's measured / the share of your speed
-- set when it was, so turning it down doesn't make it look like you slowed.
-- Ramp up (its own tick box): each right-click turn starts at a share of your
-- speed and climbs to all of it over a set time; stopping a moment (or letting
-- go) starts the next turn slow again. With both on, the slower one wins.
-- Untested in game (2026-11-11): one frame behind the mouse, so a swipe's
-- first frame still gets through.
local _, ns = ...

local WHO = "mouseturn"
local YAW, PITCH = "cameraYawMoveSpeed", "cameraPitchMoveSpeed"
local LOWEST = 0.05 -- (never quite stops the mouse)

local state = {
	scale = 1,      -- share of your speed set now (the lower of the two below)
	capScale = 1,   -- the cap's share
	turning = 0,    -- seconds into this turn (the ramp)
	still = 0,      -- seconds since you last turned
	want = 0,       -- your turn speed (deg/sec) without us, smoothed
	facing = nil,   -- last frame's facing (radians)
	held = false,   -- whether we hold the speed settings
	pitchHeld = false,
}

local function Readable(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

local function On()
	local db = ns.db
	return db and db.cameraModes ~= false and (db.mouseTurnCap or db.mouseTurnRamp) and true or false
end

local function Release()
	if state.held then
		ns.ReleaseSpeed(WHO, YAW)
		state.held = false
	end
	if state.pitchHeld then
		ns.ReleaseSpeed(WHO, PITCH)
		state.pitchHeld = false
	end
end

local function Reset()
	Release()
	state.scale, state.capScale, state.want, state.facing = 1, 1, 0, nil
	state.turning, state.still = 0, 0
end

-- One of our cameras holds the turn speed (a script turning it): theirs.
local function OthersHold(cvar)
	return ns.SpeedHeld(cvar) and not ns.SpeedHeld(cvar, WHO)
end

local function Apply(db)
	if state.scale >= 0.995 then
		if state.held or state.pitchHeld then
			ns.Log("state", "mouse turn: back to your speed")
		end
		Release()
		return
	end
	if not state.held then
		ns.Log("state", "mouse turn: slowing the mouse turn")
	end
	ns.SetHeldSpeed(WHO, YAW, ns.HoldSpeed(WHO, YAW) * state.scale)
	state.held = true
	if db.mouseTurnCapPitch and not OthersHold(PITCH) then
		ns.SetHeldSpeed(WHO, PITCH, ns.HoldSpeed(WHO, PITCH) * state.scale)
		state.pitchHeld = true
	elseif state.pitchHeld then
		ns.ReleaseSpeed(WHO, PITCH)
		state.pitchHeld = false
	end
end

local function Update(_, elapsed)
	local db = ns.db
	if not db or not On() or not (IsMouselooking and IsMouselooking()) or not IsMouseButtonDown("RightButton")
		or OthersHold(YAW) or elapsed <= 0 then
		Reset()
		return
	end
	local ok, facing = pcall(GetPlayerFacing)
	if not ok or not Readable(facing) then -- (somewhere it's hidden: leave it be)
		Reset()
		return
	end
	local last = state.facing
	state.facing = facing
	if last then
		local turn = facing - last
		if turn > math.pi then turn = turn - 2 * math.pi elseif turn < -math.pi then turn = turn + 2 * math.pi end
		local measured = math.abs(math.deg(turn)) / elapsed
		-- (your speed without us; smoothed over about 0.05 sec against jitter)
		local want = measured / math.max(state.scale, LOWEST)
		state.want = state.want + (want - state.want) * math.min(1, elapsed / 0.05)
	end

	-- The cap.
	local capScale = 1
	if db.mouseTurnCap then
		local cap = tonumber(db.mouseTurnCapSpeed) or 180
		local target = state.want > cap and math.max(LOWEST, cap / state.want) or 1
		if target < state.capScale then
			capScale = target -- (slows at once: the cap is a cap)
		else
			local ease = math.max(0.01, tonumber(db.mouseTurnCapEase) or 0.3)
			capScale = state.capScale + (target - state.capScale) * math.min(1, elapsed / ease)
		end
	end
	state.capScale = capScale

	-- The ramp: time into this turn, back to the start once still a moment.
	local rampScale = 1
	if db.mouseTurnRamp then
		if state.want > 15 then
			state.turning, state.still = state.turning + elapsed, 0
		else
			state.still = state.still + elapsed
			if state.still >= 0.25 then state.turning = 0 end
		end
		local start = math.max(LOWEST, (tonumber(db.mouseTurnRampStart) or 30) / 100)
		local t = math.min(1, state.turning / math.max(0.05, tonumber(db.mouseTurnRampTime) or 0.5))
		rampScale = start + (1 - start) * t * t -- (creeps at first, faster near the top)
	end

	state.scale = math.min(capScale, rampScale)
	Apply(db)
end

local frame = CreateFrame("Frame")
ns.FeatureLoop(frame, ns.Profiled("Mouse turn cap", Update), function()
	if On() then return true end
	Reset() -- (turned off: yours back)
	return false
end)

-- (For a debug look; the log's "state" lines show it slowing and back.)
ns.mouseTurnState = state
