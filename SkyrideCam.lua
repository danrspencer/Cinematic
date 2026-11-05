-- Skyriding Cam (skyrideCam, retail): skyriding through the air,
-- the camera zooms out so you can see where you're going, each skyriding
-- ability you cast gets a move of its own (its moment: a surge zooms out, a
-- halt swings round you...), and landing brings it all back. It plays the
-- built-in Skyriding zoom camera script (CameraScripts.lua, made from this
-- page's settings; its runner's travel rules: steering doesn't stop it, its
-- zoom carries on as you steer with the mouse, but your mouse stops its turns
-- and tilts, and scrolling the zoom yourself stops its zoom). "In the air" is the game's gliding info, on once
-- you've been up skyrideCamStart seconds and off once you've been down
-- skyrideCamLand (ns.SkyridingNow, CameraScripts.lua).
-- Where: its Show in row (Always ticked to start with: everywhere).
-- /cine debug skyride logs what the game says while you fly.
local _, ns = ...
local L = ns.L

-- (Only where there's skyriding: retail's gliding info.)
if not (ns.isRetail and C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then return end
ns.SKYRIDE_CAM = true -- (it's here: /cine debug skyride says so)

local ROW_KEY = "skyride:cam"
ns.CINE_SHOW_SETTING[ROW_KEY] = "skyrideCamAlways"

-- Whether the camera may play now: the page on, and its Show in row here.
function ns.SkyrideCamOn()
	local db = ns.db
	if not (db and ns.Setting("skyrideCam")) then return false end
	if db.skyrideCamAlways then return true end
	local ok, here = pcall(ns.RowOnNow, ROW_KEY, false, true)
	return ok and here and true or false
end

-- The moments. Each plays its moves in place of whatever the camera was
-- doing (ns.CameraScriptPlaySteps), so every move goes to a place, not by an
-- amount. Each of the three (zoom, tilt, turn) has a base: your cruise
-- distance from take-off (pose.cruise), the tilt climbing or diving asks
-- for, the turn a turn asks for. A moment holds one somewhere else for a
-- while (pose.plans: a Surge's zoom out, Skyward Ascent's tilt up, Aerial
-- Halt's swing round and zoom in): there, held, then back to its base. Every
-- time anything plays, each of the three goes on from where it is along its
-- plan, or to its base, so a hold isn't cut short by climbing coming on
-- (Skyward Ascent makes you climb), and a move cut short by the next doesn't
-- leave the camera tilted or turned. Landing (the script's When it ends) puts
-- it all back. Turns and tilts count from where the script started: a turn
-- left is positive, and a positive tilt LOWERS the camera (MoveViewDown, as the
-- quest cam's Lower the camera), so it looks up at you. So a climb, looking up
-- with you, is positive, and a dive, the camera rising to look down after you,
-- negative. (Backwards at first: dives never followed, and a camera lowered
-- into the ground stops there while the count goes on, so undoing it left the
-- camera far above your head on landing.)
local function Zoom() return GetCameraZoom and GetCameraZoom() or 15 end
local FARTHEST = 39 -- yards: the game's farthest zoom
local POSE_SECS = 2 -- seconds: easing to a base beside a moment's own move
local pose = { climb = false, dive = false, turn = 0, cruise = nil, plans = {} } -- (turn: 1 left, -1 right, 0 none)
-- Climbing and diving tilt with you: ANGLE_SHARE of how steep you go (pose.angle,
-- degrees, smoothed; STEEP_START until it's read), up to the page's setting,
-- moved on again whenever that's ANGLE_STEP off what was played (pose.playedPitch).
-- (ANGLE_EVERY: seconds at least between those, or each would restart the
-- last before it got going: the tilt crept and lagged behind the dive.)
local ANGLE_SHARE, ANGLE_STEP, STEEP_START, ANGLE_EVERY = 0.75, 8, 45, 1
-- (pose.following: the last steps played had Follow your turns in them, so it's under way.)

-- The bases.
local function BasePitch(db)
	-- (Following how steep you go, pose.angle: ANGLE_SHARE of it, up to the setting.)
	local follow = math.floor((pose.angle or STEEP_START) * ANGLE_SHARE + 0.5)
	return (pose.climb and db.skyrideClimb and math.min(db.skyrideClimbDeg, follow))
		or (pose.dive and db.skyrideDive and -math.min(db.skyrideDiveDeg, follow)) or 0
end
local function BaseYaw(db)
	return db.skyrideTurn and not db.skyrideFollow and pose.turn * db.skyrideTurnDeg or 0
end
local function BaseZoom(db)
	return pose.cruise or db.skyrideCamDistance
end
-- The Blend section's caps: a move that would go faster than its Fastest
-- (at its top speed, halfway through: the runner's ease puts that at
-- distance / (secs * (1 - ease))) takes longer instead. Eases: the step
-- kinds' own (turns and tilts smooth, zooms gentle).
local SMOOTH, GENTLE = 0.5, 0.35
local function Capped(secs, distance, capKey, ease)
	local cap = ns.db and ns.db[capKey]
	if type(cap) ~= "number" or cap <= 0 then return secs end
	return math.max(secs, math.abs(distance) / (cap * (1 - ease)))
end
local function Blend() return ns.db and ns.db.skyrideBlend or 0 end
-- Steps from one place to another (nil when it's already there).
local function TiltStep(from, to, secs)
	local d = to - from
	if math.abs(d) < 0.5 then return nil end
	-- (Gentle: under way sooner than smooth's, so a dive's tilt doesn't lag behind it.)
	return { k = "tilt", deg = d, secs = Capped(secs, d, "skyrideMaxTilt", GENTLE), blend = Blend(), ease = "gentle" }
end
local function TurnStep(from, to, secs)
	local d = to - from
	if math.abs(d) < 1 then return nil end
	return { k = "rotate", deg = math.abs(d), way = d > 0 and "left" or "right",
		secs = Capped(secs, d, "skyrideMaxTurn", SMOOTH), blend = Blend() }
end
-- (snap: one speed throughout, no easing in or out: Whirling Surge's zoom out.
-- "smooth": the landing's, easing in and out over its whole length.)
local function ZoomStep(from, to, secs, snap)
	to = math.max(1, math.min(FARTHEST, to))
	if math.abs(to - from) < 0.3 then return nil end
	-- (A snap isn't held to the Fastest zoom: it's meant to be quicker than the rest.)
	if snap == "smooth" then
		return { k = "zoom", to = to, secs = Capped(secs, to - from, "skyrideMaxZoom", SMOOTH), ease = "smooth" }
	end
	return { k = "zoom", to = to, secs = snap and secs or Capped(secs, to - from, "skyrideMaxZoom", GENTLE), past = "yes",
		ease = snap and "none" or nil }
end
-- A list without its gaps.
local function List(...)
	local steps = {}
	for i = 1, select("#", ...) do
		local step = select(i, ...)
		if step then steps[#steps + 1] = step end
	end
	return steps
end
-- Several at once (the runner turns and tilts one after the other inside).
local function Together(...)
	local steps = List(...)
	if #steps == 0 then return nil end
	if #steps == 1 then return steps[1] end
	return { k = "together", steps = steps }
end
-- Several one after another, as one step (a Repeat once).
local function Seq(...)
	local steps = List(...)
	if #steps == 0 then return nil end
	if #steps == 1 then return steps[1] end
	return { k = "repeat", times = 1, steps = steps }
end
-- Where the script has the camera now (turn, tilt from its start).
local function Now()
	local state = ns.CameraScriptState and ns.CameraScriptState()
	return state and state.yaw or 0, state and state.pitch or 0
end

-- A moment's hold on one of the three (by: whose, "halt" for Aerial Halt's).
local function Hold(axis, to, secs, hold, back, by, snap)
	local now = GetTime()
	pose.plans[axis] = { to = to, at = now, secs = secs, untilT = now + secs + hold, back = back, by = by, snap = snap }
end
-- The plan still holding (or on its way there), or nil.
local function Holding(axis)
	local plan = pose.plans[axis]
	return plan and GetTime() < plan.untilT and plan or nil
end
local MAKE = { tilt = TiltStep, turn = TurnStep, zoom = ZoomStep }
-- One of the three from where it is: along its plan (there, the rest of its
-- hold, back), or to its base over secs.
local function Track(axis, from, base, secs)
	local make, plan, now = MAKE[axis], pose.plans[axis], GetTime()
	if plan and now < plan.untilT then
		local left = plan.at + plan.secs - now
		local first = make(from, plan.to, left > 0 and math.max(plan.snap and 0.5 or 1, left) or POSE_SECS,
			plan.snap and left > 0)
		local wait = plan.untilT - now - (first and first.secs or 0)
		return Seq(first, wait > 0.05 and { k = "wait", secs = wait } or nil, make(plan.to, base, plan.back))
	end
	if plan and now < plan.untilT + plan.back then
		return make(from, base, math.max(1, plan.untilT + plan.back - now))
	end
	pose.plans[axis] = nil
	return make(from, base, secs or POSE_SECS)
end
-- Follow your turns, as the auto-run camera's (and the built-in script's
-- own, CameraScripts.lua): in every moment's steps too, so it carries on.
-- (Not while Aerial Halt swings round: the follow would hold the turn, its
-- swing waiting. Stopped, the turns it made stay counted, so the swing goes
-- from where the view is; it's back with the next thing that plays.)
local function Follow(db)
	if not db.skyrideFollow then return nil end
	local halt = pose.plans.turn
	if halt and GetTime() < halt.untilT + halt.back then return nil end
	return { k = "follow", after = db.skyrideFollowAfter, lazy = 1, top = 70, accel = 60, corners = "yes",
		most = db.skyrideFollowMost }
end
-- All three, together, from where they are now (secs: the bases' own times).
local function Steps(db, tiltSecs, turnSecs)
	local yaw, pitch = Now()
	pose.playedPitch, pose.playedAt = BasePitch(db), GetTime()
	-- (Following, the follow has the turn: ours only for a moment's own, Aerial
	-- Halt's swing, and back behind you as the follow starts again after it.
	-- Worked out while the follow holds the view off, a turn back would go too
	-- far once it had glided back.)
	local follow = Follow(db)
	local turn = (not follow or pose.plans.turn or not pose.following) and Track("turn", yaw, BaseYaw(db), turnSecs)
		or nil
	pose.following = follow ~= nil
	return List(Together(Track("zoom", Zoom(), BaseZoom(db)), Track("tilt", pitch, BasePitch(db), tiltSecs),
		turn, follow))
end
-- Flying off again: Aerial Halt's holds are over.
local function EndHalt()
	for axis, plan in pairs(pose.plans) do
		if plan.by == "halt" then pose.plans[axis] = nil end
	end
end

local MOMENTS = {
	[372608] = { key = "skyrideSurge", name = "Surge Forward", plan = function(db)
		EndHalt()
		local out, plan = math.min(FARTHEST, BaseZoom(db) + db.skyrideSurgeYards), Holding("zoom")
		if plan and plan.to >= out then -- (out farther already, a Whirling Surge's: held longer)
			plan.untilT = math.max(plan.untilT, GetTime() + db.skyrideSurgeTime + db.skyrideSurgeHold)
		else
			Hold("zoom", out, db.skyrideSurgeTime, db.skyrideSurgeHold, db.skyrideSurgeBack)
		end
	end },
	[372610] = { key = "skyrideAscent", name = "Skyward Ascent", plan = function(db)
		Hold("tilt", db.skyrideAscentDeg, db.skyrideAscentTime, db.skyrideAscentHold, db.skyrideAscentTime)
	end },
	[361584] = { key = "skyrideWhirl", name = "Whirling Surge", plan = function(db)
		EndHalt()
		Hold("zoom", db.skyrideWhirlYards, db.skyrideWhirlTime, db.skyrideWhirlHold, db.skyrideWhirlBack, nil, true)
	end },
	[403092] = { key = "skyrideHalt", name = "Aerial Halt", plan = function(db)
		local secs, hold = db.skyrideHaltTime, db.skyrideHaltHold
		Hold("turn", BaseYaw(db) + db.skyrideHaltDeg, secs, hold, secs, "halt")
		if db.skyrideHaltYards > 0 then Hold("zoom", db.skyrideHaltYards, secs, hold, secs, "halt") end
	end },
	[425782] = { key = "skyrideWind", name = "Second Wind", plan = function(db)
		local plan = Holding("zoom")
		Hold("zoom", math.max(1, (plan and plan.to or BaseZoom(db)) - db.skyrideWindYards), db.skyrideWindTime, 0,
			db.skyrideWindTime)
	end },
}
local function Play(steps, why)
	if #steps == 0 then return end
	ns.CameraScriptPlaySteps("Skyride", steps, why, Blend())
end
local casts = CreateFrame("Frame")
casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
casts:SetScript("OnEvent", function(_, _, _, _, spellID)
	if type(spellID) ~= "number" or (issecretvalue and issecretvalue(spellID)) then return end
	local moment = MOMENTS[spellID]
	local db = ns.db
	if not (moment and db and db[moment.key] and ns.SkyrideCamOn()) then return end
	-- (Only while its script plays, in the air and out of a fight: else nothing.)
	if not (ns.CameraScriptState and ns.CameraScriptState()) then return end
	pose.castAt = GetTime() -- (its speed jump isn't a dive: Sample)
	moment.plan(db)
	Play(Steps(db), moment.name)
end)

-- Climbing, diving and turning: worked out every SAMPLE seconds in the air
-- (Tools/skyride-test-plan.md has the numbers they're from). How steep you
-- go is the flat speed from your position against the glide's speed (your
-- height and pitch can't be read); climbing loses speed, diving gains it (or
-- holds at the 55 cap: a climb above it is losing speed). Each comes on after ON_SAMPLES in a row and goes off
-- after OFF_SAMPLES without, so a wobble doesn't flip it; coming on or going
-- off moves the camera to the pose it asks for. (Not in instances: no
-- position there, so no climbing or diving.)
local SAMPLE, ON_SAMPLES, OFF_SAMPLES = 0.25, 2, 4
local STEEP = 25 -- degrees: steeper than this, climbing or diving (Run 2's climb read 24-33)
local TREND = 4 -- yards a second, each second: speed falling (climbing) or rising (diving) faster than this
local DIVE_CAP = 54 -- yards a second: about the most a dive reaches without a surge (55.2)
local SLOWEST = 15 -- yards a second: slower, steepness can't be told
local TURNING = 90 -- degrees a second: your facing turning faster than this
local watch = { since = 0, count = {} }
local function Facing()
	local ok, facing = pcall(GetPlayerFacing)
	return ok and type(facing) == "number" and not (issecretvalue and issecretvalue(facing)) and math.deg(facing) or nil
end
local function Plain(value) return type(value) == "number" and not (issecretvalue and issecretvalue(value)) end
-- The pitch keys (Pitch Up / Pitch Down, as you steer a skyriding mount with
-- the keyboard: the 14:03 flight log, 2026-11-05). The game gives no pitch to
-- read (GetUnitPitch is nil on retail), but its key bindings call these, so a
-- press is known at once, a second or more before the speed shows it.
-- watch.keys[way] = { down, at }: held, and when it was last pressed or let go.
local KEY_GRACE = 1.5     -- seconds after letting go the key still holds its climb or dive on
local KEY_TURN_OVER = 0.75 -- seconds held past a pull out (or push out) before it's the other one
local TAKEOFF_GRACE = 2   -- seconds after take-off the speed's guess is ignored
local CAST_GRACE = 1.5    -- seconds after a cast, the same
watch.keys = { up = { down = false, at = -math.huge }, down = { down = false, at = -math.huge } }
local function KeyRecent(way, now)
	local key = watch.keys[way]
	return key.down or now - key.at < KEY_GRACE
end
local function KeyHeldFor(way, now)
	local key = watch.keys[way]
	return key.down and now - key.at or 0
end
-- One state's sample: raw now or not; on or off once it's held long enough.
local function Settle(name, raw)
	local count = watch.count
	local on = pose[name] and pose[name] ~= 0 and true or false
	if raw == on then
		count[name] = 0
		return false
	end
	count[name] = (count[name] or 0) + 1
	if count[name] < (raw and ON_SAMPLES or OFF_SAMPLES) then return false end
	count[name] = 0 -- (flipped: counting afresh, so one odd sample can't flip it straight back)
	return true
end
local function Sample(db)
	local ok, _, _, speed = pcall(C_PlayerInfo.GetGlidingInfo)
	local okPos, y, x = pcall(UnitPosition, "player")
	local facing = Facing()
	local dt = watch.since
	local steep, trend, rate
	if ok and Plain(speed) and okPos and Plain(y) and Plain(x) and watch.y and speed >= SLOWEST then
		local flat = math.sqrt((x - watch.x) ^ 2 + (y - watch.y) ^ 2) / dt
		steep = math.deg(math.acos(math.min(1, flat / speed)))
	end
	if ok and Plain(speed) and watch.speed then trend = (speed - watch.speed) / dt end
	if facing and watch.facing then rate = ((facing - watch.facing + 540) % 360 - 180) / dt end
	watch.y, watch.x = okPos and Plain(y) and y or nil, okPos and Plain(x) and x or nil
	watch.speed, watch.facing = ok and Plain(speed) and speed or nil, facing
	local dive = steep ~= nil and steep >= STEEP and ((trend or 0) >= TREND or (speed >= DIVE_CAP and (trend or 0) >= -1))
	local climb = steep ~= nil and steep >= STEEP and not dive and (trend or 0) <= -TREND
	local now = GetTime()
	if watch.keysSeen then
		-- Steering with the pitch keys (OnPitchKey): they start climbing and
		-- diving. The speed's guess only ends them, once you've levelled out,
		-- and not while the key's held or just let go (KEY_GRACE): the speed
		-- takes a moment to show a dive.
		dive = pose.dive and (dive or KeyRecent("down", now))
		climb = pose.climb and (climb or KeyRecent("up", now))
		-- (Held on past a pull out of a dive, or a push out of a climb: the other one.)
		if not pose.dive and not pose.climb then
			dive = dive or KeyHeldFor("down", now) >= KEY_TURN_OVER
			climb = climb or KeyHeldFor("up", now) >= KEY_TURN_OVER
		end
	end
	-- (Just off the ground: the launch speeds you up as a dive would. Nothing
	-- from the speed till TAKEOFF_GRACE has passed.)
	if now - (watch.upAt or 0) < TAKEOFF_GRACE and not watch.keysSeen then dive, climb = pose.dive, pose.climb end
	-- (Nor just after a cast: its speed jumps at once and your position catches
	-- up after, which reads as steep and speeding up. A Surge read as a dive,
	-- tilting the camera down all the way in to a landing.)
	local casting = now - (pose.castAt or 0) < CAST_GRACE
	if casting then dive, climb, steep = pose.dive, pose.climb, nil end
	local side = rate and math.abs(rate) >= TURNING and (rate > 0 and 1 or -1) or 0
	-- (How steep, smoothed: the flat speed jitters sample to sample.)
	if steep then pose.angle = pose.angle and (pose.angle + steep) / 2 or steep end
	local changed
	local by = watch.keysSeen and " (by speed, after your keys)" or " (by speed)"
	if Settle("dive", dive) then pose.dive, changed = dive, (dive and "diving" or "level (dive over)") .. by end
	if Settle("climb", climb) then pose.climb, changed = climb, (climb and "climbing" or "level (climb over)") .. by end
	-- (A turn the other way straight after: the new side.)
	if Settle("turn", side ~= 0) or (side ~= 0 and pose.turn ~= 0 and side ~= pose.turn) then
		pose.turn = side
		changed = side == 0 and "straight (turn over)" or (side > 0 and "turning left" or "turning right")
		watch.count.turn = 0
	end
	-- (Steeper or shallower while climbing or diving: the tilt goes with you.)
	if not changed and (pose.dive or pose.climb) and math.abs(BasePitch(db) - (pose.playedPitch or 0)) >= ANGLE_STEP
		and now - (pose.playedAt or 0) >= ANGLE_EVERY then
		changed = ("%s, %d degrees steep (by %s)"):format(pose.dive and "diving" or "climbing",
			math.floor(pose.angle or 0), "speed")
	end
	if not (pose.dive or pose.climb) then pose.angle = nil end
	if not changed then return end
	Play(Steps(db, (pose.dive and db.skyrideDiveTime) or db.skyrideClimbTime, db.skyrideTurnTime), changed)
end
-- Landed: back to your distance, level and behind you, all as one move over
-- skyrideCamBackTime, starting skyrideCamLand after you touch down. (The
-- script's When it ends then has nothing left to do. A zoom of yours stops
-- this one's and stays: its stop rules.)
local LAND_ZOOM_SPEED = 8 -- yards a second: the landing zoom's path at its fastest (the runner's headroom takes it to about 10)
local LAND_LOWERED = 15 -- degrees: the most a camera can have come down before the ground stops it, about
local function Land(db)
	local state = ns.CameraScriptState and ns.CameraScriptState()
	if not state then return end
	pose.landing, pose.climb, pose.dive, pose.turn, pose.angle = true, false, false, 0, nil
	wipe(pose.plans)
	local secs = db.skyrideCamBackTime
	local home = state.startZoom or Zoom()
	-- (From far out it takes as long as it needs: a set time rushed 24 yards in 2 s.)
	local zoomSecs = math.max(secs, math.abs(Zoom() - home) / (LAND_ZOOM_SPEED * (1 - SMOOTH)))
	local yaw = (state.yaw + 180) % 360 - 180 -- (the short way round)
	-- (You've zoomed yourself since touching down: that's where it stays.)
	local yours = ns.lastPlayerZoomAt and watch.downAt and ns.lastPlayerZoomAt >= watch.downAt
	pose.landedBy = GetTime() + math.max(secs, zoomSecs) + 0.5
	-- (A camera lowered as you land stops at the ground, so it's come down less
	-- than counted: taking the whole count off would lift it over your head.)
	local tilt = math.min(state.pitch, LAND_LOWERED)
	if ns.CameraScriptSetTilt then ns.CameraScriptSetTilt(tilt) end
	Play(List(Together(not yours and ZoomStep(Zoom(), home, zoomSecs, "smooth") or nil,
		TiltStep(tilt, 0, secs), TurnStep(yaw, 0, secs))), "landing")
end
-- (Whether the landing's still coming back, a long way in: SkyridingNow waits for it.)
function ns.SkyrideLandingBusy()
	return pose.landing and GetTime() < (pose.landedBy or 0)
end
local watcher = CreateFrame("Frame")
ns.SetOnUpdate(watcher, function(_, elapsed)
	local db = ns.db
	local flying = db and ns.SkyridingNow and ns.SkyridingNow()
	if not flying then
		if watch.flying then
			watch.flying, watch.y, watch.speed, watch.facing = false, nil, nil, nil
			pose.cruise, pose.climb, pose.dive, pose.turn, pose.landing = nil, false, false, 0, false
			watch.downAt = nil
			wipe(pose.plans)
			wipe(watch.count)
		end
		return
	end
	if not watch.flying then
		watch.flying, watch.since, watch.upAt = true, 0, GetTime()
		pose.cruise = db.skyrideCamDistance -- (the take-off zoom's)
		pose.following = db.skyrideFollow and true or false -- (the built-in script's own follow)
	end
	watch.since = watch.since + elapsed
	if watch.since < SAMPLE then return end
	-- (Touched down, the camera waiting skyrideCamLand to end: nothing new plays,
	-- so a zoom of yours as you land stays. Back up: sampling afresh.)
	if ns.GlidingSpeed and ns.GlidingSpeed() == nil then
		watch.y, watch.speed, watch.facing, watch.since = nil, nil, nil, 0
		watch.downAt = watch.downAt or GetTime()
		if not pose.landing and GetTime() - watch.downAt >= db.skyrideCamLand then Land(db) end
		return
	end
	watch.downAt = nil
	-- (Off again before it's back: on as you were.)
	if pose.landing then
		pose.landing = false
		Play(Steps(db), "off again")
	end
	if db.skyrideClimb or db.skyrideDive or db.skyrideTurn then Sample(db) end
	watch.since = 0
end)

-- A pitch key pressed or let go (way "up" or "down"). Pressed in the air with
-- the camera playing: diving or climbing at once, or, the other way, levelling
-- out of the one you're in (held on past KEY_TURN_OVER, Sample makes it the
-- other one). From the first press on, the keys start these, not the speed.
local function OnPitchKey(way, down)
	local key, now = watch.keys[way], GetTime()
	key.down, key.at = down, now
	if not down then return end
	watch.keysSeen = true
	local db = ns.db
	if not (db and watch.flying and ns.CameraScriptState and ns.CameraScriptState()) then return end
	if ns.GlidingSpeed and ns.GlidingSpeed() == nil then return end -- (on the ground)
	if not (way == "down" and db.skyrideDive or way == "up" and db.skyrideClimb) then return end
	local changed
	if way == "down" then
		if pose.climb then pose.climb, changed = false, "level (climb over) (by your key)"
		elseif not pose.dive then pose.dive, changed = true, "diving (by your key)" end
	else
		if pose.dive then pose.dive, changed = false, "level (dive over) (by your key)"
		elseif not pose.climb then pose.climb, changed = true, "climbing (by your key)" end
	end
	if not changed then return end
	watch.count.dive, watch.count.climb = 0, 0
	Play(Steps(db, (pose.dive and db.skyrideDiveTime) or db.skyrideClimbTime, db.skyrideTurnTime), changed)
end
for name, hook in pairs({ PitchUpStart = { "up", true }, PitchUpStop = { "up", false },
	PitchDownStart = { "down", true }, PitchDownStop = { "down", false } }) do
	if type(_G[name]) == "function" then
		hooksecurefunc(name, function() OnPitchKey(hook[1], hook[2]) end)
	end
end

function ns.CreateSkyrideCamPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Skyriding Cam"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["While you skyride through the air, the camera zooms out so you can see where you're going, and each " ..
		"skyriding ability you cast gets a shot of its own."])
	local switch = kit.PageSwitch(content, "skyrideCam", L["Enable Page"],
		L["On: taking to the air on a skyriding mount zooms the camera out, each ability below moves it as you " ..
		"cast it, and landing brings it back to your own distance. Steering with the mouse stops a turn or tilt " ..
		"but not a zoom; scrolling the zoom yourself stops that. It plays the Skyriding zoom camera script, made " ..
		"from the settings below."], intro)
	local function IfOn() return ns.Setting("skyrideCam") end
	local stack = kit.Stack(switch, "check")

	local header = stack:Header(content, L["Show in"])
	local lastRow = ns.ShowTable(content, header, {
		opts = { quiet = true, cam = true, anyFight = true }, underHeader = true,
		{ key = ROW_KEY, label = L["Skyriding Cam"], alwaysKey = "skyrideCamAlways",
			alwaysOn = function() return ns.GetDB().skyrideCamAlways end,
			setAlways = function(value) ns.GetDB().skyrideCamAlways = value end,
			alwaysTip = L["Wherever you skyride. (The other columns then have nothing to add.)"] },
	}, L["Skyriding Cam"])

	-- The rest in folder tabs, a group each (two rows of them), as the Game
	-- Frames page's sections: the panel under the tabs, each group's settings
	-- in a body of its own, the one picked shown. The tab last picked is kept
	-- across reloads; /cine find opens the tab a setting's on.
	local SECTION_WIDTH = 560
	local sections, section = {}, nil
	local picked = { id = "Skyriding Cam/tab", open = "takeoff" }
	local panelTop = CreateFrame("Frame", nil, content)
	panelTop:SetSize(1, 1)
	local panel, ShowTab
	local function Layout()
		kit.SectionState.Restore(picked)
		local shown = 1
		for i, each in ipairs(sections) do
			if each.key == picked.open then shown = i end
		end
		for i, each in ipairs(sections) do each.body:SetShown(i == shown) end
		ShowTab(shown)
		panel:SetPoint("BOTTOMRIGHT", sections[shown].last, "BOTTOMLEFT", SECTION_WIDTH + 12, -12)
		kit.FitContentHeight(content)
	end
	local function Pick(each)
		kit.SectionState.Save(picked, each.key)
		Layout()
	end
	-- A tab: what's added next goes on it.
	local function Section(key, label)
		section = { key = key, tab = label }
		local each = section
		section.body = CreateFrame("Frame", nil, content)
		section.body:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12, -12)
		section.body:SetSize(1, 1)
		section.body.searchAlways = true
		section.body.openSection = function() Pick(each) end
		section.last = section.body
		stack = kit.Stack(section.body, "label")
		sections[#sections + 1] = section
	end
	-- A control on the tab being made.
	local function Put(control, kind)
		stack:Add(control, kind)
		control:SetParent(section.body)
		section.last = control
		return control
	end

	-- A slider of the page (greyed with the page off, or its moment unticked).
	-- (unless: a setting that takes its place while on: Follow your turns, Swing into the turn's.)
	local function Slider(key, label, min, max, step, fmt, tip, moment, unless)
		local slider = Put(kit.Slider(content, key, label, min, max, step, fmt), "slider")
		if tip then kit.Tooltip(slider, tip) end
		kit.GreyUnless(slider, function()
			local db = ns.GetDB()
			return IfOn() and (not moment or db[moment]) and not (unless and db[unless]) and true or false
		end)
		return slider
	end
	-- A moment's tick: its move on or off.
	local function Tick(key, label, tip, unless)
		kit.GreyUnless(Put(kit.Check(content, key, label, tip), "check"), function()
			return IfOn() and not (unless and ns.GetDB()[unless]) and true or false
		end)
	end
	local YARDS, DEGREES, SECS = L["%d yards"], L["%d degrees"], L["%.1f sec"]
	local HOLD_TIP = L["How long the camera stays there before going back."]

	Section("takeoff", L["Take off"])
	Slider("skyrideCamDistance", L["Zoom out to"], 10, 39, 1, YARDS,
		L["How far out the camera goes as you take to the air: your cruise distance. Surges go out from here and " ..
		"come back to it. 39 is as far as the game allows, past your own max camera distance for the flight."])
	Slider("skyrideCamZoomTime", L["Over"], 1, 10, 0.5, SECS)
	Slider("skyrideCamStart", L["Start after"], 0, 3, 0.25, L["%.2f sec"],
		L["How long you're in the air before the camera zooms out, so a hop doesn't start it."])

	Section("surge", L["Surge Forward"])
	Tick("skyrideSurge", L["Zoom out"], L["Surge Forward pulls the camera out past your cruise distance, holds " ..
		"it there, then lets it drift back. Another Surge meanwhile holds it out longer; it doesn't go further."])
	Slider("skyrideSurgeYards", L["By"], 1, 15, 1, YARDS, L["How far past your cruise distance (Take off's)."],
		"skyrideSurge")
	Slider("skyrideSurgeTime", L["Over"], 1, 5, 0.5, SECS, nil, "skyrideSurge")
	Slider("skyrideSurgeHold", L["Hold"], 0, 5, 0.5, SECS, HOLD_TIP, "skyrideSurge")
	Slider("skyrideSurgeBack", L["Back over"], 1, 10, 0.5, SECS, L["How long it takes to drift back to your " ..
		"cruise distance."], "skyrideSurge")

	Section("ascent", L["Skyward Ascent"])
	Tick("skyrideAscent", L["Tilt up"], L["Skyward Ascent tilts the camera up as you climb, then back."])
	Slider("skyrideAscentDeg", L["By"], 5, 60, 5, DEGREES, nil, "skyrideAscent")
	Slider("skyrideAscentTime", L["Over"], 1, 5, 0.5, SECS, nil, "skyrideAscent")
	Slider("skyrideAscentHold", L["Hold"], 0, 5, 0.5, SECS, HOLD_TIP, "skyrideAscent")

	Section("whirl", L["Whirling Surge"])
	Tick("skyrideWhirl", L["Zoom out"], L["Whirling Surge throws the camera out fast, as if you're going too fast " ..
		"for it to keep up, holds it there, then lets it catch up slowly."])
	Slider("skyrideWhirlYards", L["To"], 10, 39, 1, YARDS, nil, "skyrideWhirl")
	Slider("skyrideWhirlTime", L["Over"], 0.5, 5, 0.5, SECS, L["0.5: a snap, as quick as the game's zoom goes."],
		"skyrideWhirl")
	Slider("skyrideWhirlHold", L["Hold"], 0, 5, 0.5, SECS, HOLD_TIP, "skyrideWhirl")
	Slider("skyrideWhirlBack", L["Back over"], 1, 10, 0.5, SECS, L["How long it takes to come back to your " ..
		"cruise distance."], "skyrideWhirl")

	Section("halt", L["Aerial Halt"])
	Tick("skyrideHalt", L["Swing around and zoom in"], L["Aerial Halt swings the camera around you and in close for " ..
		"a shot of you hovering, holds it, then swings back. A Surge to fly off ends the shot."])
	Slider("skyrideHaltDeg", L["By"], 30, 180, 10, DEGREES, nil, "skyrideHalt")
	Slider("skyrideHaltYards", L["Zoom in to"], 0, 25, 1, YARDS, L["How close the camera comes in meanwhile. " ..
		"0: it stays at the distance it's at."], "skyrideHalt")
	Slider("skyrideHaltTime", L["Over"], 1, 5, 0.5, SECS, nil, "skyrideHalt")
	Slider("skyrideHaltHold", L["Hold"], 0, 5, 0.5, SECS, HOLD_TIP, "skyrideHalt")

	Section("wind", L["Second Wind"])
	Tick("skyrideWind", L["Zoom in and back"], L["Second Wind takes the camera in a little, like a breath, " ..
		"then back out."])
	Slider("skyrideWindYards", L["By"], 1, 10, 1, YARDS, nil, "skyrideWind")
	Slider("skyrideWindTime", L["Over"], 1, 5, 0.5, SECS, L["Each way."], "skyrideWind")

	local SHAPE_TIP = L["Worked out from your speed and where you are, so it comes on half a second in and " ..
		"goes off about a second after. Not in instances: the game doesn't say where you are there."]
	Section("climb", L["Climbing"])
	Tick("skyrideClimb", L["Tilt up"], L["While you climb steeply, the camera tilts up with you, as steep as you " ..
		"go (three quarters of it, up to the setting below), and levels " ..
		"out again as you do."] .. " " .. SHAPE_TIP)
	Slider("skyrideClimbDeg", L["Up to"], 5, 80, 5, DEGREES, nil, "skyrideClimb")
	Slider("skyrideClimbTime", L["Over"], 1, 5, 0.5, SECS, nil, "skyrideClimb")

	Section("dive", L["Diving"])
	Tick("skyrideDive", L["Tilt down"], L["While you dive, the camera tilts down to where you're heading, as " ..
		"steep as you go (three quarters of it, up to the setting below: a nose-dive looks down after you), and " ..
		"levels out again as you do."] .. " " .. SHAPE_TIP)
	Slider("skyrideDiveDeg", L["Up to"], 5, 80, 5, DEGREES, nil, "skyrideDive")
	Slider("skyrideDiveTime", L["Over"], 1, 5, 0.5, SECS, nil, "skyrideDive")

	Section("turn", L["Turning"])
	Tick("skyrideTurn", L["Swing into the turn"], L["While you turn hard, the camera swings around toward where " ..
		"you're turning, and back behind you as you straighten out. Steering with the mouse moves the camera " ..
		"yourself, so this only shows when you turn with the keys."], "skyrideFollow")
	Slider("skyrideTurnDeg", L["By"], 5, 60, 5, DEGREES, nil, "skyrideTurn", "skyrideFollow")
	Slider("skyrideTurnTime", L["Over"], 1, 5, 0.5, SECS, nil, "skyrideTurn", "skyrideFollow")
	kit.GreyUnless(Put(kit.Check(content, "skyrideFollow", L["Follow your turns"],
		L["As the auto-run camera does: while you turn, the camera holds its direction, so you bank across the " ..
		"screen, then glides around behind you once you straighten out. In place of Swing into the turn. Steering " ..
		"with the mouse keeps the camera behind you, as ever."]), "check"), IfOn)
	Slider("skyrideFollowAfter", L["Glide back after"], 0, 3, 0.25, L["%.2f sec"],
		L["How long after you stop turning the camera starts gliding back behind you."], "skyrideFollow")
	Slider("skyrideFollowMost", L["Fall behind at most"], 10, 120, 5, DEGREES,
		L["The furthest the camera lets you turn away from it. Past it, it turns with you, so a long turn " ..
		"never ends with it in front of you."], "skyrideFollow")

	Section("land", L["Landing"])
	Slider("skyrideCamBackTime", L["Back to your distance over"], 0.5, 10, 0.5, SECS,
		L["How long the camera takes to come back to your own distance (and any turn or tilt undone) after " ..
		"you land, as one smooth move."])
	Slider("skyrideCamLand", L["Start after landing"], 0, 5, 0.25, L["%.2f sec"],
		L["How long you're on the ground before the camera starts coming back, so touching down between flaps " ..
		"doesn't bounce it. Off again before it's back: it goes back out with you."])

	local FASTEST_TIP = L["The fastest the camera goes at the height of a move. A moment that would go faster takes " ..
		"longer instead, so moments firing close together never whip the camera around."]
	Section("blend", L["Blend"])
	Slider("skyrideMaxTurn", L["Fastest turn"], 30, 360, 10, L["%d degrees a second"], FASTEST_TIP)
	Slider("skyrideMaxTilt", L["Fastest tilt"], 10, 90, 5, L["%d degrees a second"], FASTEST_TIP)
	Slider("skyrideMaxZoom", L["Fastest zoom"], 5, 40, 1, L["%d yards a second"], FASTEST_TIP)
	Slider("skyrideBlend", L["Blend into the next move"], 0, 2, 0.25, L["%.2f sec"],
		L["When a moment starts while the camera is still moving the same way, the move carries on and slides " ..
		"into the new one's speed over this long, instead of stopping first. 0: it stops, then starts the new one."])

	Section("cine", L["CineMode"])
	kit.GreyUnless(Put(kit.Check(content, "skyrideCine", L["CineMode while skyriding"],
		L["With \"Start in CineMode\" off (Cinematic's main page), skyriding brings CineMode on (the UI " ..
		"fades as your Show in rows say) until you land."]), "check"), IfOn)

	-- The tabs, as high as their rows, under the Show in row.
	local list = {}
	for i, each in ipairs(sections) do list[i] = { each.tab } end
	local base, height
	panel, _, ShowTab, base, height = ns.FolderTabs(content, list, function(i) Pick(sections[i]) end, nil, SECTION_WIDTH + 8)
	panelTop:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -16 - height)
	panel:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
	base:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
	Layout()
	kit.OnReset(content, Layout)

	canvas:SetScript("OnShow", kit.PageShown(function()
		kit.Refresh()
		Layout() -- (as last left, once the settings have loaded)
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Skyriding Cam")
end

-- ---------------------------------------------------------------------------
-- /cine debug skyride: finding out what we can read and control while you
-- skyride (Tools/skyride-test-plan.md says what to fly for each).
--   skyride          what the game says now; again to start or stop the
--                    flight log: a line every LOG_EVERY seconds in the air,
--                    and the game's events as they come (gliding, casts,
--                    charges, settings the game changes itself, bars, fights)
--   skyride view     whether a saved camera view gives away the camera's tilt
--   skyride frames   the frames up now that look like skyriding's (vigor,
--                    widgets, the skyriding bar): shown, alpha, protected
--   skyride probe <zoom|turn|tilt|fov|follow>
--                    one of our camera moves or settings, tried now, before
--                    and after logged (for a macro, mid-flight)
-- All of it goes to the saved log (/reload to save it).
-- ---------------------------------------------------------------------------
do
	local LOG_EVERY, LOG_FOR = 0.25, 300
	local function V(value, fmt)
		if value == nil then return "nil" end
		if issecretvalue and issecretvalue(value) then return "secret" end
		if fmt and type(value) == "number" then return fmt:format(value) end
		return tostring(value)
	end
	local function Plain(value) return type(value) == "number" and not (issecretvalue and issecretvalue(value)) end
	local function Zoom() return GetCameraZoom and GetCameraZoom() end
	local function Glide()
		local ok, gliding, can, speed = pcall(C_PlayerInfo.GetGlidingInfo)
		if not ok then return "gliding info error", nil, nil, nil end
		return ("gliding %s, can %s, speed %s"):format(V(gliding), V(can), V(speed, "%.1f")), gliding, can, speed
	end
	local function Call(name, ...)
		local fn = _G[name]
		if not fn then return "nil" end
		local ok, a = pcall(fn, ...)
		return ok and V(a) or "error"
	end
	local function Facing()
		local ok, facing = pcall(GetPlayerFacing)
		return ok and Plain(facing) and math.deg(facing) or nil
	end
	-- The skyriding abilities (as their casts logged them, retail 12.1.5), for
	-- their charges and cooldowns: the skyriding bar's slots gave none (tested).
	local SKY_SPELLS = { { 372608, "surge" }, { 372610, "ascent" }, { 361584, "whirl" }, { 403092, "halt" },
		{ 425782, "wind" } }
	-- Vigor: the game's vigor widget (FillUpFrames, widget 4460 in set 283, as
	-- UPDATE_UI_WIDGET showed on take-off): full swirls of total, and the next one filling.
	local VIGOR_WIDGET = 4460
	local function Vigor()
		local manager = C_UIWidgetManager
		local get = manager and manager.GetFillUpFramesWidgetVisualizationInfo
		if not get then return "vigor: no widget API" end
		local ok, info = pcall(get, VIGOR_WIDGET)
		if not ok or type(info) ~= "table" then return "vigor: none" end
		return ("vigor %s/%s, filling %s of %s-%s, shown %s"):format(V(info.numFullFrames), V(info.numTotalFrames),
			V(info.fillValue, "%.1f"), V(info.fillMin), V(info.fillMax), V(info.shownState))
	end
	-- Each ability's charges (or cooldown left), compact.
	local function Charges()
		local parts = {}
		for _, spell in ipairs(SKY_SPELLS) do
			local charges = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spell[1])
			local text
			if type(charges) == "table" then
				text = ("%s/%s"):format(V(charges.currentCharges), V(charges.maxCharges))
			else
				local cd = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spell[1])
				local left = type(cd) == "table" and Plain(cd.startTime) and Plain(cd.duration) and cd.duration > 0
					and cd.startTime + cd.duration - GetTime()
				text = left and ("cd %.0f"):format(left) or (type(cd) == "table" and "ready" or "-")
			end
			parts[#parts + 1] = spell[2] .. " " .. text
		end
		return table.concat(parts, ", ")
	end
	-- The skyriding bar (the bonus bar while you skyride): what its slots hold.
	-- compact: the abilities' charges and vigor instead.
	local function Bar(compact)
		if compact then return Charges() .. " | " .. Vigor() end
		local index = _G.GetBonusBarIndex and _G.GetBonusBarIndex()
		if not Plain(index) or index == 0 then return ("bonus bar %s | %s"):format(V(index), Vigor()) end
		local first = ((_G.NUM_ACTIONBAR_PAGES or 6) + index - 1) * 12
		local parts = {}
		for slot = first + 1, first + 12 do
			local ok, kind, id = pcall(GetActionInfo, slot)
			if ok and kind then
				local name = kind == "spell" and Plain(id) and C_Spell and C_Spell.GetSpellName
					and C_Spell.GetSpellName(id)
				parts[#parts + 1] = ("%d %s %s%s"):format(slot, V(kind), V(id), name and (" " .. name) or "")
			end
		end
		return ("bonus bar %d (slots %d-%d): %s | %s"):format(index, first + 1, first + 12,
			#parts > 0 and table.concat(parts, ", ") or "empty", Vigor())
	end
	local function Where()
		local ok, y, x, z, instance = pcall(UnitPosition, "player")
		if not ok then return nil end
		return y, x, z, instance
	end
	local function Ours()
		local state = ns.CameraScriptState and ns.CameraScriptState()
		return ("Skyriding Cam page %s, may play here %s, cine %s; skyriding now %s; script %s; zoom %s, zoom speed %s, max factor %s, fov %s, follow %s"):format(
			ns.Setting("skyrideCam") and "on" or "off", tostring(ns.SkyrideCamOn()), tostring(ns.db.skyrideCine),
			tostring(ns.SkyridingNow and ns.SkyridingNow()),
			state and ("%s (%s)"):format(state.script and state.script.name or "?", tostring(state.phase)) or "none",
			V(Zoom(), "%.1f"), tostring(GetCVar("cameraZoomSpeed")), tostring(GetCVar("cameraDistanceMaxZoomFactor")),
			tostring(GetCVar("cameraFov")), tostring(GetCVar("cameraSmoothStyle")))
	end
	local function Log(text) ns.Log("skyride", text) end

	-- The flight log: a line LOG_EVERY seconds while you're in the air (and at
	-- once as gliding or can-glide changes), the events as they come.
	local logger = CreateFrame("Frame")
	local log = { on = false, widgets = {} }
	logger:Hide()
	-- The keys you steer with, as the log runs: which of them pitch you while
	-- you skyride (Pitch Up/Down, or forward/back, by your pitch setting). The
	-- bindings call these functions; hooked once (a hook can't come off), logged
	-- only while the log runs. (As Camera.lua's turn keys.)
	for _, name in ipairs({ "PitchUpStart", "PitchUpStop", "PitchDownStart", "PitchDownStop", "MoveForwardStart",
		"MoveForwardStop", "MoveBackwardStart", "MoveBackwardStop", "JumpOrAscendStart", "AscendStop",
		"SitStandOrDescendStart", "DescendStop" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function()
				if log.on then
					local ok, pitch = pcall(_G.GetUnitPitch or error, "player")
					Log(("key %s | %s, pitch %s"):format(name, (Glide()),
						ok and Plain(pitch) and ("%+.0f deg"):format(math.deg(pitch)) or "-"))
				end
			end)
		end
	end
	-- (pcall: an event this client hasn't got would error.)
	local EVENTS = { "PLAYER_IS_GLIDING_CHANGED", "PLAYER_CAN_GLIDE_CHANGED", "UNIT_SPELLCAST_SUCCEEDED",
		"SPELL_UPDATE_CHARGES", "CVAR_UPDATE", "UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
		"ACTIONBAR_PAGE_CHANGED", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"ZONE_CHANGED_NEW_AREA", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE", "UPDATE_UI_WIDGET" }
	local lastCharges -- (SPELL_UPDATE_CHARGES comes often: logged only as the charges change)
	logger:SetScript("OnEvent", function(_, event, ...)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			local unit, _, spellID = ...
			if unit ~= "player" then return end
			local name = Plain(spellID) and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
			Log(("event cast %s %s | %s"):format(V(name), V(spellID), (Glide())))
		elseif event == "SPELL_UPDATE_CHARGES" then
			local charges = Charges()
			if charges ~= lastCharges then
				lastCharges = charges
				Log("event charges " .. charges .. " | " .. Vigor())
			end
		elseif event == "UPDATE_UI_WIDGET" then
			local info = ...
			local id = type(info) == "table" and info.widgetID
			if id and not log.widgets[id] then
				log.widgets[id] = true -- (once each: they update every frame or so)
				Log(("event widget %s (type %s, set %s)"):format(V(id), V(info.widgetType), V(info.widgetSetID)))
			end
		else
			local a, b = ...
			Log(("event %s %s %s | %s, mouselook %s"):format(event, V(a), V(b), (Glide()),
				Call("IsMouselooking")))
		end
	end)
	ns.SetOnUpdate(logger, function(_, elapsed)
		local now = GetTime()
		if now - log.started >= LOG_FOR then
			log.on = false
			logger:Hide()
			logger:UnregisterAllEvents()
			Log("log over (time up)")
			ns.Print("skyride log over (5 minutes): /reload to save it")
			return
		end
		local text, gliding, can, speed = Glide()
		local changed = gliding ~= log.gliding or can ~= log.can
		log.gliding, log.can = gliding, can
		log.since = log.since + elapsed
		local flying = IsFlying and IsFlying()
		if not changed and (log.since < LOG_EVERY or not (gliding or flying)) then return end
		-- (Your height and pitch can't be read, and the unit speed is 0 while
		-- gliding: tested. The flat speed from your position against the
		-- glide's speed gives how steep you go, not which way; the glide speed
		-- falling says climbing, rising without a surge diving.)
		local y, x = Where()
		local shape = ""
		if Plain(y) and Plain(x) and log.y and log.since > 0 then
			local flat = math.sqrt((x - log.x) ^ 2 + (y - log.y) ^ 2) / log.since
			local steep = Plain(speed) and speed > 5 and math.deg(math.acos(math.min(1, flat / speed)))
			local trend = Plain(speed) and Plain(log.speed) and (speed - log.speed) / log.since
			shape = (" | flat %.1f, steep %s, speed %s/s"):format(flat, steep and ("%.0f deg"):format(steep) or "-",
				trend and ("%+.1f"):format(trend) or "-")
		end
		if Plain(y) and Plain(x) then log.y, log.x = y, x else log.y = nil end
		log.speed = Plain(speed) and speed or nil
		-- (Your facing, and how fast it turns: steering.)
		local facing = Facing()
		local turn = facing and log.facing and ((facing - log.facing + 540) % 360 - 180) / log.since
		log.facing = facing
		local okPitch, pitch = pcall(_G.GetUnitPitch or error, "player")
		Log(("%s%s%s | %s | falling %s, mouselook %s, facing %s, turning %s/s, pitch %s | combat %s | zoom %s, fov %s, saved pitch %s, saved distance %s | ours: sky %s"):format(
			changed and "CHANGED " or "", text, shape, Bar(true), Call("IsFalling"), Call("IsMouselooking"),
			V(facing, "%.0f"), V(turn, "%+.0f"),
			_G.GetUnitPitch and (okPitch and Plain(pitch) and ("%+.0f deg"):format(math.deg(pitch)) or "error") or "no function", V(InCombatLockdown()), V(Zoom(), "%.1f"), tostring(GetCVar("cameraFov")),
			tostring(GetCVar("cameraSavedPitch")), tostring(GetCVar("cameraSavedDistance")),
			tostring(ns.SkyridingNow and ns.SkyridingNow())))
		-- (The bar in full as you take off: its spells by name.)
		if changed and gliding == true then Log(Bar()) end
		log.since = 0
	end)

	local function Snapshot()
		local build, _, _, toc = GetBuildInfo()
		ns.Print(("skyride: %s | flying %s, falling %s, mounted %s, taxi %s, skyriding zone %s, flyable %s, indoors %s, combat %s (%s, %s)"):format(
			(Glide()), Call("IsFlying"), Call("IsFalling"), Call("IsMounted"), Call("UnitOnTaxi", "player"),
			Call("IsAdvancedFlyableArea"), Call("IsFlyableArea"), Call("IsIndoors"), V(InCombatLockdown()),
			tostring(build), tostring(toc)))
		local _, speed, run, flight, swim = pcall(GetUnitSpeed, "player")
		local y, x, z, instance = Where()
		ns.Print(("  unit speed %s (run %s, flight %s, swim %s); position %s, %s, height %s (instance %s); facing %s"):format(
			V(speed, "%.1f"), V(run, "%.1f"), V(flight, "%.1f"), V(swim, "%.1f"), V(x, "%.1f"), V(y, "%.1f"),
			V(z, "%.1f"), V(instance), V(Facing(), "%.0f")))
		ns.Print("  " .. Bar())
		ns.Print("  " .. Ours())
	end

	local function ToggleLog()
		log.on = not log.on
		if log.on then
			log.started, log.since, log.gliding, log.can, log.y, log.speed, log.facing = GetTime(), 0, nil, nil, nil, nil, nil
			log.widgets, lastCharges = {}, nil
			for _, event in ipairs(EVENTS) do pcall(logger.RegisterEvent, logger, event) end
			Log("log started: " .. Ours())
			ns.Print("  logging while you're in the air (5 minutes, or /cine debug skyride again): /reload after to save it")
		else
			logger:UnregisterAllEvents()
			Log("log stopped")
			ns.Print("  log stopped: /reload to save it")
		end
		logger:SetShown(log.on)
	end

	-- The frames up now that look like skyriding's: by name (vigor, widgets,
	-- the bars it swaps in), with whether we could fade them (protected ones
	-- can't be touched in a fight).
	local FRAME_WORDS = { "vigor", "glid", "dragon", "skyrid", "powerbar", "uiwidget", "override", "bonusaction",
		"encounterbar", "vehicle", "mainactionbar", "mainmenubar" }
	local function IsFrame(value)
		local ok, isFrame = pcall(function() return value.IsObjectType and value:IsObjectType("Frame") end)
		return ok and isFrame == true
	end
	local function Frames()
		local found = {}
		for name, value in pairs(_G) do
			if type(name) == "string" and type(value) == "table" and not name:find("^Cinematic") then
				local lower = name:lower()
				for _, word in ipairs(FRAME_WORDS) do
					if lower:find(word, 1, true) then
						if IsFrame(value) then found[#found + 1] = name end
						break
					end
				end
			end
		end
		table.sort(found)
		local shown = 0
		for _, name in ipairs(found) do
			local frame = _G[name]
			local okShown, visible = pcall(frame.IsVisible, frame)
			if okShown and visible == true then
				shown = shown + 1
				local _, alpha = pcall(frame.GetEffectiveAlpha, frame)
				local _, protected = pcall(frame.IsProtected, frame)
				local _, forbidden = pcall(frame.IsForbidden, frame)
				local okParent, parent = pcall(frame.GetParent, frame)
				local parentName = okParent and parent and parent.GetName and parent:GetName()
				Log(("frame %s: visible, alpha %s, protected %s, forbidden %s, parent %s"):format(name,
					V(alpha, "%.2f"), V(protected), V(forbidden), V(parentName)))
			end
		end
		Log(("frames: %d named like skyriding's, %d visible | %s, combat %s"):format(#found, shown, (Glide()),
			V(InCombatLockdown())))
		ns.Print(("skyride frames: %d visible of %d named like skyriding's (in /cine log)"):format(shown, #found))
	end

	-- Probes: one of our camera moves or settings, tried now. Settings tried
	-- are put back after, and at the next login if you /reload meanwhile
	-- (db.skyrideProbeRestore).
	local function Hold(cvar, value)
		local db = ns.db
		db.skyrideProbeRestore = db.skyrideProbeRestore or {}
		if db.skyrideProbeRestore[cvar] == nil then db.skyrideProbeRestore[cvar] = GetCVar(cvar) end
		SetCVar(cvar, value)
	end
	local function Restore(cvar)
		local saved = ns.db.skyrideProbeRestore
		if saved and saved[cvar] ~= nil then
			SetCVar(cvar, saved[cvar])
			saved[cvar] = nil
			if not next(saved) then ns.db.skyrideProbeRestore = nil end
		end
	end
	local function State()
		local script = ns.PlayingCameraScript and ns.PlayingCameraScript()
		return ("%s, mouselook %s, facing %s, pitch %s, zoom %s, script %s"):format((Glide()), Call("IsMouselooking"),
			V(Facing(), "%.0f"), Call("GetUnitPitch", "player"), V(Zoom(), "%.1f"), tostring(script and script.name))
	end
	local function Move(name) if _G[name] then ns.CallCameraFunction(name, 1) end end
	local function Stop(name) if _G[name] then ns.CallCameraFunction(name) end end
	local PROBES = {
		-- Our zoom commands: does the game take them in the air?
		zoom = function()
			local z0 = Zoom()
			ns.CallCameraFunction("CameraZoomOut", 10)
			C_Timer.After(1.5, function()
				local z1 = Zoom()
				ns.CallCameraFunction("CameraZoomIn", 10)
				C_Timer.After(1.5, function()
					Log(("probe zoom: %s out 10 -> %s, in 10 -> %s | %s"):format(V(z0, "%.1f"), V(z1, "%.1f"),
						V(Zoom(), "%.1f"), State()))
				end)
			end)
		end,
		-- A turn of the view: does it turn the view, you (your facing), or neither?
		turn = function()
			local f0 = Facing()
			Move("MoveViewLeftStart")
			C_Timer.After(1, function()
				Stop("MoveViewLeftStop")
				local f1 = Facing()
				C_Timer.After(1, function()
					Log(("probe turn: facing %s, after 1 s turning the view %s, 1 s later %s | %s"):format(V(f0, "%.0f"),
						V(f1, "%.0f"), V(Facing(), "%.0f"), State()))
				end)
			end)
		end,
		-- A tilt of the view up (watch: does the view tilt, or your flight?).
		tilt = function()
			local before = State()
			Move("MoveViewUpStart")
			C_Timer.After(1, function()
				Stop("MoveViewUpStop")
				Log(("probe tilt: tilted the view up 1 s | before %s | after %s"):format(before, State()))
			end)
		end,
		-- The field of view, 20 narrower for 4 s: does it take, or does the game's own flight FOV win?
		fov = function()
			local f0 = tonumber(GetCVar("cameraFov"))
			if not f0 then
				Log("probe fov: no cameraFov here")
				return
			end
			local want = math.max(30, f0 - 20)
			Hold("cameraFov", want)
			local f1 = GetCVar("cameraFov")
			C_Timer.After(4, function()
				local f2 = GetCVar("cameraFov")
				Restore("cameraFov")
				Log(("probe fov: %s -> set %s, read %s, 4 s later %s, back to %s | %s"):format(tostring(f0), tostring(want),
					tostring(f1), tostring(f2), tostring(GetCVar("cameraFov")), State()))
			end)
		end,
		-- Camera follow flipped for 6 s (yours off: on, "2" always, as our
		-- recenter has it; yours on: off, "0"): does it change how the camera
		-- swings behind you in the air?
		follow = function()
			local s0 = GetCVar("cameraSmoothStyle")
			local want = s0 == "0" and "2" or "0"
			Hold("cameraSmoothStyle", want)
			C_Timer.After(6, function()
				local s1 = GetCVar("cameraSmoothStyle")
				Restore("cameraSmoothStyle")
				Log(("probe follow: cameraSmoothStyle %s -> %s for 6 s (read %s at the end), back to %s | %s"):format(
					tostring(s0), want, tostring(s1), tostring(GetCVar("cameraSmoothStyle")), State()))
			end)
		end,
	}
	-- (A probe's setting left over from a /reload mid-probe: put back now.)
	local restorer = CreateFrame("Frame")
	restorer:RegisterEvent("PLAYER_LOGIN")
	restorer:SetScript("OnEvent", function()
		local saved = ns.db and ns.db.skyrideProbeRestore
		if type(saved) ~= "table" then return end
		for _, cvar in ipairs({ "cameraFov", "cameraSmoothStyle" }) do
			if saved[cvar] ~= nil then
				Log(("probe: %s put back to %s (left over)"):format(cvar, tostring(saved[cvar])))
				Restore(cvar)
			end
		end
	end)

	-- /cine debug skyride view: can the camera's tilt be read? The game won't say
	-- where the camera points, but saving a view (SaveView, the Save View keys)
	-- may write it into a setting. Saves to view VIEW_SLOT, looks a moment later
	-- for any camera setting that changed, and puts those back. Press it, move
	-- the camera up or down, press again: a value that follows the camera is
	-- the tilt. What it finds goes to the log and chat.
	local VIEW_SLOT, VIEW_WAIT = 4, 0.2
	local viewLast -- (what the settings read after the last save)
	local function CameraSettings()
		local values = {}
		local list = C_Console and C_Console.GetAllCommands and select(2, pcall(C_Console.GetAllCommands))
			or (_G.ConsoleGetAllCommands and select(2, pcall(_G.ConsoleGetAllCommands)))
		for _, info in ipairs(type(list) == "table" and list or {}) do
			local name = type(info) == "table" and info.command
			if type(name) == "string" and name:lower():find("camera", 1, true) then
				local ok, value = pcall(GetCVar, name)
				if ok and value ~= nil then values[name] = tostring(value) end
			end
		end
		-- (Lists can leave some out: the likely names by hand.)
		for slot = 1, 5 do
			for _, part in ipairs({ "Pitch", "Yaw", "Distance" }) do
				local name = ("cameraView%d%s"):format(slot, part)
				local ok, value = pcall(GetCVar, name)
				if ok and value ~= nil then values[name] = tostring(value) end
			end
		end
		for _, name in ipairs({ "cameraSavedPitch", "cameraSavedDistance", "cameraSavedVehicleDistance" }) do
			local ok, value = pcall(GetCVar, name)
			if ok and value ~= nil then values[name] = tostring(value) end
		end
		return values
	end
	local function ViewProbe()
		if not _G.SaveView then
			ns.Print("skyride view: no SaveView here")
			return
		end
		local before = CameraSettings()
		local count = 0
		for _ in pairs(before) do count = count + 1 end
		local ok, err = pcall(_G.SaveView, VIEW_SLOT)
		if not ok then
			Log("view: SaveView error: " .. tostring(err))
			ns.Print("skyride view: SaveView failed: " .. tostring(err))
			return
		end
		C_Timer.After(VIEW_WAIT, function()
			local after, changed, moved = CameraSettings(), {}, {}
			for name, value in pairs(after) do
				if before[name] ~= value then changed[#changed + 1] = ("%s %s -> %s"):format(name, tostring(before[name]), value) end
				if viewLast and viewLast[name] ~= value then
					moved[#moved + 1] = ("%s %s -> %s"):format(name, tostring(viewLast[name]), value)
				end
			end
			table.sort(changed)
			table.sort(moved)
			viewLast = after
			local text = ("view: %d camera settings read, zoom %s | saving changed: %s | since the last press: %s"):format(
				count, V(Zoom(), "%.1f"), #changed > 0 and table.concat(changed, ", ") or "nothing",
				#moved > 0 and table.concat(moved, ", ") or "nothing")
			Log(text)
			ns.Print(("skyride view: saving changed %d, %d moved since the last press (in the log: /reload to save it)"):format(
				#changed, #moved))
			for _, line in ipairs(moved) do ns.Print("  " .. line) end
			-- (Yours back: only what saving changed.)
			for name, value in pairs(after) do
				if before[name] ~= nil and before[name] ~= value then pcall(SetCVar, name, before[name]) end
			end
		end)
	end

	function ns.SkyrideDebug(arg)
		arg = arg or ""
		if arg == "frames" then
			Frames()
			return
		end
		if arg == "view" then
			ViewProbe()
			return
		end
		local probe = arg:match("^probe%s+(%a+)")
		if probe or arg == "probe" then
			if not PROBES[probe or ""] then
				ns.Print("skyride probe: zoom, turn, tilt, fov or follow")
				return
			end
			Log(("probe %s starting | %s"):format(probe, State()))
			PROBES[probe]()
			ns.Print(("skyride probe %s: logged in a few seconds (/reload after to save it)"):format(probe))
			return
		end
		Snapshot()
		ToggleLog()
	end
end
