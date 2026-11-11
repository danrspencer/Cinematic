-- Skyriding Cam flight simulator (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
-- flies a made-up flight (FLIGHT below, its speeds and turn rates from the
-- Run 2/3 logs in Tools/skyride-test-plan.md) through the real SkyrideCam.lua
-- and CameraScripts.lua code, and plays the camera commands they send on a
-- stand-in for the game's camera (CAMERA below). Writes what the camera did,
-- every TICK seconds, as JSON for build.py's page.
--
--   python -I Tools/offline/run.py Tools/skyride-sim/sim.lua <variant> <out.json>
--
-- variant "yours" <out.json> <SavedVariables\CinematicDev.lua>: flies with your
-- saved settings as they are (nothing switched on for it), so a setting that
-- keeps the camera from starting shows up here before you fly; "yoursReset":
-- the same after the Skyriding Cam page's Reset.
-- variant: "page" (the page's defaults: Follow your turns), "plain" (no
-- Blend: caps off, blend 0, how moments played before the Blend section) or
-- "swing" (the defaults with Swing into the turn in place of the follow) or
-- "mouse" (the defaults, steering with the mouse: no pitch keys pressed).
-- Not modelled: your mouse (steering with it stops our turns and tilts in
-- game), fights, instances, and whether the game takes turns and tilts
-- mid-flight at all (Run 4's probes).
-- luacheck: ignore 111 121 122 (it stands in for the game's functions on purpose)
local variant, outPath, savedPath = ...
variant = variant or "page"

package.path = "Tools/offline/?.lua;" .. package.path
local wow = dofile("Tools/offline/wow.lua")
wow.Install("retail")

local TICK = 0.02
local now = 100

-- The game: time, timers, settings.
GetTime = function() return now end
local timers = {}
C_Timer.After = function(secs, fn) timers[#timers + 1] = { at = now + secs, fn = fn } end
local cvars = { cameraYawMoveSpeed = "180", cameraPitchMoveSpeed = "90", cameraZoomSpeed = "20",
	cameraSmoothStyle = "0", cameraDistanceMaxZoomFactor = "2.6" }
GetCVar = function(name) return cvars[name] or "0" end
SetCVar = function(name, value) cvars[name] = tostring(value) end
C_CVar = C_CVar or {}
C_CVar.GetCVar, C_CVar.SetCVar = GetCVar, SetCVar
InCombatLockdown = function() return false end
UnitAffectingCombat = function() return false end
-- (Not AFK: as the stub it counted as AFK, and the AFK camera played through the flight's first
-- seconds, holding the Skyriding Cam off till 3.5 s after the launch.)
UnitIsAFK = function() return false end
IsIndoors = function() return false end

-- CAMERA: the game's camera, moved only by the commands sent. A turn or tilt
-- goes at the Start's share of its speed setting, read each frame (the game
-- does). Starting one axis stops the other unless that one was started this
-- same frame too (the runner sends it again straight after, as Camera.lua's
-- orbit does to keep both going). Zooms add up into a goal the camera moves
-- toward at the zoom speed setting. Turn: left positive; tilt: down positive
-- (the runner's).
local cam = { yaw = 0, pitch = 0, zoom = 15, goal = 15, yawRate = 0, pitchRate = 0, sends = 0, stops = 0,
	frame = 0, startedAt = {} }
local function Axis(axis, sign, start)
	local other = axis == "yaw" and "pitch" or "yaw"
	return function(share)
		cam.sends = cam.sends + 1
		if start then
			cam[axis .. "Rate"] = sign * (share or 1)
			cam.startedAt[axis] = cam.frame
			if cam.startedAt[other] ~= cam.frame then cam[other .. "Rate"] = 0 end
		else
			cam[axis .. "Rate"] = 0
			cam.stops = cam.stops + 1
		end
	end
end
MoveViewLeftStart, MoveViewLeftStop = Axis("yaw", 1, true), Axis("yaw", 1, false)
MoveViewRightStart, MoveViewRightStop = Axis("yaw", -1, true), Axis("yaw", -1, false)
MoveViewDownStart, MoveViewDownStop = Axis("pitch", 1, true), Axis("pitch", 1, false)
MoveViewUpStart, MoveViewUpStop = Axis("pitch", -1, true), Axis("pitch", -1, false)
CameraZoomIn = function(yards) cam.goal = cam.goal - (yards or 0) end
CameraZoomOut = function(yards) cam.goal = cam.goal + (yards or 0) end
GetCameraZoom = function() return cam.zoom end
-- (A positive tilt LOWERS the camera: MoveViewDown, as the quest cam's tested
-- Lower the camera. It starts HEIGHT degrees above you; on the ground it stops
-- at ground level however long the move goes on, and it stops short of
-- straight overhead, while the runner goes on counting.)
local HEIGHT, OVERHEAD = 15, 88
local function MoveCamera(dt)
	cam.yaw = cam.yaw + cam.yawRate * tonumber(cvars.cameraYawMoveSpeed) * dt
	cam.pitch = cam.pitch + cam.pitchRate * tonumber(cvars.cameraPitchMoveSpeed) * dt
	if cam.onGround then cam.pitch = math.min(cam.pitch, HEIGHT) end
	cam.pitch = math.max(cam.pitch, HEIGHT - OVERHEAD)
	cam.goal = math.max(1, math.min(39, cam.goal))
	local step = tonumber(cvars.cameraZoomSpeed) * dt
	local d = cam.goal - cam.zoom
	cam.zoom = math.abs(d) <= step and cam.goal or cam.zoom + (d > 0 and step or -step)
end

-- The player: gliding, speed, where and which way.
local me = { gliding = false, speed = 0, x = 0, y = 0, facing = 0 }
C_PlayerInfo = C_PlayerInfo or {}
C_PlayerInfo.GetGlidingInfo = function() return me.gliding, true, me.speed end
UnitPosition = function() return me.y, me.x, 0, 0 end
GetPlayerFacing = function() return math.rad(me.facing % 360) end

-- hooksecurefunc as the game's: the function runs, then the hook. (The
-- stand-in's did nothing: the pitch keys would never reach SkyrideCam.lua.)
hooksecurefunc = function(a, b, c)
	local tbl, name, fn = _G, a, b
	if type(a) == "table" then tbl, name, fn = a, b, c end
	local orig = rawget(tbl, name)
	if type(orig) ~= "function" then return end
	tbl[name] = function(...)
		local results = { orig(...) }
		pcall(fn, ...) -- (as the game: a hook's error doesn't stop the function it's on)
		return unpack(results, 1, table.maxn(results))
	end
end
debugstack = debugstack or function() return "" end
-- The keys you steer with: the bindings call these.
for _, name in ipairs({ "PitchUpStart", "PitchUpStop", "PitchDownStart", "PitchDownStop", "JumpOrAscendStart",
	"AscendStop" }) do
	_G[name] = function() end
end

-- Only the frames of the files flown (the rest of the addon idles).
local mine = {}
local realCreate = CreateFrame
CreateFrame = function(...)
	local f = realCreate(...)
	-- (The first caller outside this file: a hook on CreateFrame wraps it here.)
	local src, level
	level = 2
	repeat
		local info = debug.getinfo(level, "S")
		src = info and info.source or ""
		level = level + 1
	until not info or not src:find("skyride%-sim")
	-- (The camera director too: the scripts take their trigger from its decisions.)
	if src:find("CameraScripts") or src:find("SkyrideCam") or src:find("Director") then mine[#mine + 1] = f end
	return f
end
-- (yours: the saved settings in place before the addon loads, as in game.)
if variant == "yours" or variant == "yoursReset" then
	local chunk = assert(loadfile(assert(savedPath, "yours needs the SavedVariables file")))
	local saved = {}
	setfenv(chunk, saved)
	chunk()
	rawset(_G, "CinematicDB", saved.CinematicDB)
end
local ns = {}
for line in io.lines("CinematicDev.toc") do
	line = line:gsub(string.char(13), "")
	if line ~= "" and not line:find("^#") then
		local chunk = loadfile((line:gsub("\\", "/")))
		if chunk then
			local ok, err = pcall(chunk, "CinematicDev", ns)
			if not ok and os.getenv("SIMDEBUG") then print("load error: " .. tostring(err)) end
		end
	end
end
wow.Fire("ADDON_LOADED", "CinematicDev")
wow.Fire("PLAYER_LOGIN")
ns.OnTaxi = function() return false end
-- (Your own camera input: a scroll in FLIGHT, as Camera.lua's OnPlayerZoom notes it.)
local yourInput = 0
ns.GetLastCameraInput = function() return yourInput end
ns.IsMouseOnCamera = function() return false end
if variant == "yoursReset" then
	-- (The Skyriding Cam page's Reset: each of its settings back to its default.)
	for key, value in pairs(ns.DEFAULTS) do
		if type(key) == "string" and key:find("^skyride") then ns.db[key] = value end
	end
elseif variant ~= "yours" then
	ns.db.enabled, ns.db.cameraModes, ns.db.skyrideCam, ns.db.skyrideCamAlways = true, true, true, true
end
if variant == "plain" then
	ns.db.skyrideMaxTurn, ns.db.skyrideMaxTilt, ns.db.skyrideMaxZoom, ns.db.skyrideBlend = 0, 0, 0, 0
elseif variant == "swing" then
	ns.db.skyrideFollow = false
end

-- What happened, for the page: the script's and the moments' log lines.
local events = {}
local realLog = ns.Log
ns.Log = function(kind, text, ...)
	if type(text) == "string" and text:find("^camera script") then
		events[#events + 1] = { t = now - 100, kind = "camera", text = (text:gsub("^camera script [^:]*: ", "")) }
	end
	if realLog then return realLog(kind, text, ...) end
end

-- FLIGHT: { seconds, what }. what: ground; fly with rate (speed change a
-- second), flat (share of the speed along the ground: 1 level, 0.15 a steep
-- dive), spin (degrees a second your facing turns, left positive); a cast
-- by name at that moment; a key you press (the function its binding calls);
-- or a scroll of your own (yards, in negative).
local CASTS = { ["Surge Forward"] = 372608, ["Skyward Ascent"] = 372610, ["Whirling Surge"] = 361584,
	["Aerial Halt"] = 403092, ["Second Wind"] = 425782 }
local FLIGHT = {
	{ 2, "ground", label = "On the ground, mounted" },
	{ 0, "key", "JumpOrAscendStart" },
	{ 1.3, "fly", rate = 22, flat = 0.8, label = "Launch (speeds you up as a dive would)" },
	{ 3.7, "fly", rate = 6, flat = 1, label = "Level" },
	{ 0, "key", "PitchDownStart" },
	{ 0.5, "fly", rate = 2, flat = 0.75, label = "Nose down (Pitch Down held)" },
	{ 1, "fly", rate = 17.8, flat = 0.15, label = "Steep dive" },
	{ 0, "key", "PitchDownStop" },
	{ 0, "cast", "Surge Forward" },
	{ 1.5, "fly", rate = 0, flat = 0.2, label = "Dive at the cap, key let go" },
	{ 0, "key", "PitchUpStart" },
	{ 0.4, "fly", rate = -1.1, flat = 0.7, label = "Pull out (Pitch Up)" },
	{ 0, "key", "PitchUpStop" },
	{ 2.1, "fly", rate = -1.1, flat = 1, label = "Level" },
	{ 0, "cast", "Surge Forward" },
	{ 0.6, "fly", rate = -7, flat = 1, label = "Two Surges and a Whirling Surge, close together" },
	{ 0, "cast", "Surge Forward" },
	{ 0.6, "fly", rate = -7, flat = 1 },
	{ 0, "cast", "Whirling Surge" },
	{ 2.5, "fly", rate = -7, flat = 1, label = "Level" },
	{ 0, "key", "PitchUpStart" },
	{ 0.6, "fly", rate = -12, flat = 0.85, label = "Steep climb (Pitch Up held)" },
	{ 0, "cast", "Skyward Ascent" },
	{ 1, "fly", rate = -12, flat = 0.85 },
	{ 0, "key", "PitchUpStop" },
	{ 1.4, "fly", rate = -12, flat = 0.85, label = "Still climbing, key let go" },
	{ 0, "key", "PitchDownStart" },
	{ 0.3, "fly", rate = -1.1, flat = 0.9, label = "Push over (Pitch Down)" },
	{ 0, "key", "PitchDownStop" },
	{ 1.2, "fly", rate = -1.1, flat = 1, label = "Level" },
	{ 2.5, "fly", rate = -1.1, flat = 1, spin = 135, label = "Hard left turn (keys)" },
	{ 1.5, "fly", rate = -1.1, flat = 1, label = "Straight" },
	{ 0, "cast", "Aerial Halt" },
	{ 3, "fly", rate = 0, flat = 0, speed = 8, label = "Aerial Halt, hovering" },
	{ 0, "cast", "Surge Forward" },
	{ 2.5, "fly", rate = 6, flat = 1, label = "Off again" },
	{ 2, "fly", rate = -1.1, flat = 1, spin = -135, label = "Hard right turn (keys)" },
	{ 2.5, "fly", rate = -1.1, flat = 0.8, label = "Glide down" },
	{ 0, "key", "PitchDownStart" },
	{ 1.5, "fly", rate = 17.8, flat = 0.15, label = "Dive into the landing (Pitch Down held)" },
	{ 0, "key", "PitchDownStop" },
	{ 0.6, "ground", label = "Landed, diving" },
	{ 0, "scroll", -10, label = "You scroll in 10 yards just after landing" },
	{ 5.4, "ground" },
	{ 0, "key", "JumpOrAscendStart" },
	{ 1.3, "fly", rate = 22, flat = 0.8, label = "Off again: launch" },
	{ 3.7, "fly", rate = 6, flat = 1 },
	{ 0, "cast", "Whirling Surge" },
	{ 1.5, "fly", rate = -7, flat = 1, label = "Whirling Surge, out at 39 yards" },
	{ 0, "scroll", 1, label = "A small scroll in the air, the camera out at 39" },
	{ 3, "fly", rate = -7, flat = 1 },
	{ 11, "ground", label = "Landed: back to the distance you took off at" },
}

-- Landings (variant "land:<name>": Tools/skyride-sim/landings.py runs them
-- all): a short flight, then one way of coming down.
local function Up()
	return { { 2, "ground", label = "On the ground, mounted" }, { 0, "key", "JumpOrAscendStart" },
		{ 1.3, "fly", rate = 22, flat = 0.8, label = "Launch" }, { 5, "fly", rate = 3, flat = 1, label = "Level" } }
end
local function Then(...)
	local list = Up()
	for i = 1, select("#", ...) do list[#list + 1] = select(i, ...) end
	list[#list + 1] = { 9, "ground", label = "Landed" }
	return list
end
local LANDINGS = {
	cruise = Then(),
	surge = Then({ 0, "cast", "Surge Forward" }, { 0.6, "fly", rate = -7, flat = 1 }),
	whirl = Then({ 0, "cast", "Whirling Surge" }, { 1.5, "fly", rate = -7, flat = 1 }),
	glide = Then({ 0, "cast", "Surge Forward" }, { 3, "fly", rate = -7, flat = 0.95, label = "Surge, then a gentle glide in" }),
	dive = Then({ 0, "key", "PitchDownStart" }, { 2, "fly", rate = 17.8, flat = 0.15, label = "Dive in" },
		{ 0, "key", "PitchDownStop" }),
	turning = Then({ 1.5, "fly", rate = -1.1, flat = 1, spin = 135, label = "Turning as you land" }),
	halt = Then({ 0, "cast", "Aerial Halt" }, { 1, "fly", rate = 0, flat = 0, speed = 8, label = "Aerial Halt, then down" }),
	touch = Then({ 1, "ground", label = "Touch down" }, { 3, "fly", rate = 6, flat = 1, label = "Off again at once" }),
	touchlate = Then({ 2, "ground", label = "Down, coming back" }, { 3, "fly", rate = 6, flat = 1, label = "Off again" }),
	again = Then({ 5.5, "ground", label = "Down, nearly back" }, { 0, "key", "JumpOrAscendStart" },
		{ 1.3, "fly", rate = 22, flat = 0.8, label = "Off again as the camera finishes" },
		{ 6, "fly", rate = 3, flat = 1, label = "Level" }),
	climbing = Then({ 0, "key", "PitchUpStart" }, { 2, "fly", rate = -6, flat = 0.8, label = "Climbing as you land" },
		{ 0, "key", "PitchUpStop" }),
	ascent = Then({ 0, "cast", "Skyward Ascent" }, { 1.5, "fly", rate = -6, flat = 0.85, label = "Skyward Ascent, then straight down" }),
	scroll = Then({ 0.3, "ground", label = "Down" }, { 0, "scroll", -10, label = "You scroll in at once" }),
	scrolllate = Then({ 1.5, "ground", label = "Down" }, { 0, "scroll", -3, label = "You scroll in as it comes back" }),
}
-- (Scenes: "scene" plays a script zooming to part[3], its When it ends zooming
-- back if part.back; "drag" is your mouse on the camera, which stops a When it
-- ends under way.)
local function Before(...)
	local list = { ... }
	for _, part in ipairs(Then()) do list[#list + 1] = part end
	return list
end
local function After(...)
	local list = Then()
	for i = 1, select("#", ...) do list[#list + 1] = select(i, ...) end
	return list
end
local CUT_OFF = { { 0, "scene", 3, back = true, label = "A scene zooms in" }, { 2.5, "ground", label = "It starts back" },
	{ 0, "drag", label = "You drag the camera: the scene's cut off" }, { 1, "ground", label = "Left close in" } }
LANDINGS.cutoff = Before(unpack(CUT_OFF))
local cutScroll = { unpack(CUT_OFF) }
cutScroll[#cutScroll + 1] = { 0, "scroll", 2, label = "You scroll: this is your distance now" }
cutScroll[#cutScroll + 1] = { 1, "ground" }
LANDINGS.cutscroll = Before(unpack(cutScroll))
LANDINGS.sceneset = Before({ 0, "scene", 8, label = "A scene sets a distance and ends" }, { 3, "ground" })
-- (Take off's and Landing's zooms off.)
LANDINGS.keepzoom = Then()
LANDINGS.keepsurge = Then({ 0, "cast", "Surge Forward" }, { 0.6, "fly", rate = -7, flat = 1 })
LANDINGS.keepdive = LANDINGS.dive
LANDINGS.keepscene = After({ 0, "scene", 12, label = "Your scene sets the distance" }, { 4, "ground" })
LANDINGS.notakeoff = Then()
LANDINGS.notakeoffsurge = Then({ 0, "cast", "Surge Forward" }, { 0.6, "fly", rate = -7, flat = 1 })
local landing = variant:match("^land:(.+)$")
if landing then
	FLIGHT = assert(LANDINGS[landing], "no such landing")
	if landing:find("^keep") then ns.db.skyrideCamZoomBack = false end
	if landing:find("^notakeoff") then ns.db.skyrideCamZoomOut = false end
end

local samples, segments = {}, {}
local function Tick()
	now = now + TICK
	cam.frame = cam.frame + 1
	for i = #timers, 1, -1 do
		local timer = timers[i]
		if timer.at <= now then
			table.remove(timers, i)
			pcall(timer.fn)
		end
	end
	for _, f in ipairs(mine) do
		local fn = f._scripts.OnUpdate
		if fn and f._shown then -- (as the game: hidden frames don't update)
			local ok, err = pcall(fn, f, TICK)
			if not ok then events[#events + 1] = { t = now - 100, kind = "error", text = tostring(err) } end
		end
	end
	cam.onGround = not me.gliding
	MoveCamera(TICK)
	local state = ns.CameraScriptState and ns.CameraScriptState()
	samples[#samples + 1] = { now - 100, cam.yaw, cam.pitch, cam.zoom, me.facing, me.speed, me.gliding and 1 or 0,
		state and 1 or 0, state and state.yaw or 0, state and state.pitch or 0 }
end

for _, part in ipairs(FLIGHT) do
	local secs, what = part[1], part[2]
	if part.label then segments[#segments + 1] = { t = now - 100, label = part.label } end
	if what == "key" then
		-- (mouse: steering with the mouse, so no keys: only the launch's jump.)
		if variant ~= "mouse" or part[3] == "JumpOrAscendStart" then
			events[#events + 1] = { t = now - 100, kind = "key", text = "Key " .. part[3] }
			_G[part[3]]()
		end
	elseif what == "scene" then
		events[#events + 1] = { t = now - 100, kind = "cast", text = part.label or "A scene" }
		ns.PlayCameraScript({ id = "simscene", name = "Sim scene", steps = { { k = "zoom", to = part[3], secs = 1 } },
			ending = part.back and { { k = "putback", secs = 4 } } or {} })
	elseif what == "drag" then
		yourInput = now
	elseif what == "scroll" then
		events[#events + 1] = { t = now - 100, kind = "cast", text = ("You scroll %+d yards"):format(part[3]) }
		cam.goal = cam.goal + part[3]
		yourInput, ns.lastPlayerZoomAt = now, now
	elseif what == "cast" then
		events[#events + 1] = { t = now - 100, kind = "cast", text = part[3] }
		for _, f in ipairs(mine) do
			local fn = f._scripts.OnEvent
			if fn and f._events.UNIT_SPELLCAST_SUCCEEDED then
				pcall(fn, f, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", CASTS[part[3]])
			end
		end
		if part[3] == "Surge Forward" then me.speed = me.speed + 17
		elseif part[3] == "Skyward Ascent" then me.speed = me.speed + 10
		elseif part[3] == "Whirling Surge" then me.speed = me.speed + 30 end
	else
		if what == "ground" then
			me.gliding, me.speed = false, 0
		elseif not me.gliding then
			me.gliding, me.speed = true, 14
		end
		if part.speed then me.speed = part.speed end
		for _ = 1, math.floor(secs / TICK + 0.5) do
			if what == "fly" then
				me.speed = math.max(8, math.min(85, me.speed + (part.rate or 0) * TICK))
				local along = me.speed * (part.flat or 1) * TICK
				me.x = me.x + along * math.sin(math.rad(me.facing))
				me.y = me.y + along * math.cos(math.rad(me.facing))
				me.facing = me.facing + (part.spin or 0) * TICK
			end
			Tick()
		end
	end
end

-- JSON out.
local function Encode(v)
	local kind = type(v)
	if kind == "number" then
		return (("%.3f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
	elseif kind == "string" then
		return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", " ") .. '"'
	elseif kind == "boolean" then
		return tostring(v)
	elseif kind == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for i = 1, #v do parts[i] = Encode(v[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, val in pairs(v) do parts[#parts + 1] = Encode(tostring(k)) .. ":" .. Encode(val) end
		table.sort(parts)
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end
local settings = {}
for _, key in ipairs({ "skyrideMaxTurn", "skyrideMaxTilt", "skyrideMaxZoom", "skyrideBlend", "skyrideCamDistance",
	"skyrideSurgeYards", "skyrideWhirlYards", "skyrideHaltDeg", "skyrideTurnDeg", "skyrideClimbDeg", "skyrideDiveDeg" }) do
	settings[key] = ns.db[key]
end
local out = { variant = variant, tick = TICK, settings = settings, events = events, segments = segments,
	samples = samples, stops = cam.stops, sends = cam.sends,
	columns = { "t", "turn", "tilt", "zoom", "facing", "speed", "gliding", "script", "runnerTurn", "runnerTilt" } }
local file = assert(io.open(outPath or ("skyride-sim-" .. variant .. ".json"), "wb"))
file:write(Encode(out))
file:close()
print(("%s: %d samples, %d events, %d camera stops, %s"):format(variant, #samples, #events, cam.stops,
	outPath or "written"))
local ran = 0
for _, row in ipairs(samples) do ran = ran + row[8] end
print(("camera script ran %.1f s of the flight; Cinematic on %s, Skyriding Cam page %s, Show in Always %s, follow %s")
	:format(ran * TICK, tostring(ns.db.enabled), tostring(ns.db.skyrideCam), tostring(ns.db.skyrideCamAlways),
	tostring(ns.db.skyrideFollow)))
