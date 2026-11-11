-- Camera simulator (dev tool, offline): plays made-up moments (a Hearthstone
-- cast, /sit, a flight, your mouse on the camera mid-scene, a lost mouse
-- release, a loading screen...) through the addon's real camera code on
-- world.lua's stand-in, and checks each for what a player would call a camera
-- bug:
--   your speed settings not put back, the camera still turning after a scene,
--   a scene that never starts or starts over and over, our moves sent while
--   you hold the camera, a whip (a fast turn or zoom of ours), Lua errors.
--
--   python -I Tools/offline/run.py Tools/camera-sim/sim.lua [client] [scenario|all|fuzz] [seed] [count]
--
-- client: forever (default) or retail. Prints one line per scenario and the
-- failures; "-v" as scenario prints a scenario's log (sim.lua forever -v:sit).
-- luacheck: ignore 111 112 113 121 122
local client, which, seedArg, countArg = ...
client = client or "forever"
which = which or "all"
local verbose = which:match("^%-v:(.+)$")
if verbose then which = verbose end

local WORLD = "Tools/camera-sim/world.lua"
local results = {}

-- One run: a fresh world, the scenario, then nothing for a while and the checks.
local function Play(name, opts, body)
	local W = dofile(WORLD)(client, opts)
	local ns, cam, me = W.ns, W.cam, W.me
	ns.db.cameraModes = true
	ns.db.questCamNotDaily = false -- (the stand-in can't say what's a daily)
	if opts.settings then opts.settings(ns.db, ns) end
	if ns.CameraRowsChanged then ns.CameraRowsChanged() end
	local fails, notes = {}, {}
	local function Fail(text) fails[#fails + 1] = ("%.2f %s"):format(W.now - 1000, text) end
	local T = { W = W, ns = ns, cam = cam, me = me, Fail = Fail, notes = notes }
	-- Every frame: ours turning the view while you've held it a moment, and whips.
	local holdSince, lastZoom = nil, cam.zoom
	local stats = { fightFrames = 0, maxTurn = 0, maxZoomRate = 0, yourScrollAt = -math.huge }
	T.stats = stats
	W.AfterTick = function()
		local holding = W.Holding()
		if holding then holdSince = holdSince or W.now else holdSince = nil end
		local ourTurn = math.abs(cam.yawRate * (tonumber(W.cvars.cameraYawMoveSpeed) or 0))
		local ourTilt = math.abs(cam.pitchRate * (tonumber(W.cvars.cameraPitchMoveSpeed) or 0))
		if holding and W.now - holdSince > 0.45 and (ourTurn > 0.01 or ourTilt > 0.01) then
			stats.fightFrames = stats.fightFrames + 1
			if not stats.fightAt then stats.fightAt = W.now - 1000 end
		end
		if ourTurn > stats.maxTurn then stats.maxTurn, stats.maxTurnAt = ourTurn, W.now - 1000 end
		if ourTilt > (stats.maxTilt or 0) then stats.maxTilt, stats.maxTiltAt = ourTilt, W.now - 1000 end
		local zoomRate = math.abs(cam.zoom - lastZoom) / W.TICK
		if W.now - stats.yourScrollAt > 3 and zoomRate > stats.maxZoomRate then
			stats.maxZoomRate, stats.maxZoomAt = zoomRate, W.now - 1000
		end
		lastZoom = cam.zoom
	end
	local scroll = W.Scroll
	W.Scroll = function(yards) stats.yourScrollAt = W.now return scroll(yards) end
	function T.Count(pattern)
		local n = 0
		for _, line in ipairs(W.log) do if line.text:find(pattern) then n = n + 1 end end
		return n
	end
	function T.Playing()
		local run = ns.PlayingCameraScript and ns.PlayingCameraScript()
		return run and (type(run) == "table" and (run.name or (run.script and run.script.name)) or tostring(run)) or nil
	end
	-- Runs until a script named like `pattern` plays (or secs pass): how long it took, or nil.
	function T.WaitFor(pattern, secs)
		local t0 = W.now
		local before = T.Count("camera script " .. pattern .. " started")
		while W.now - t0 < secs do
			W.Tick()
			if T.Count("camera script " .. pattern .. " started") > before then return W.now - t0 end
		end
		return nil
	end
	function T.Expect(cond, text) if not cond then Fail(text) end end

	W.Run(2)
	local startZoom = cam.zoom
	T.startZoom = startZoom
	local ok, err = pcall(body, T)
	if not ok then Fail("scenario error: " .. tostring(err)) end

	-- Everything let go, then quiet.
	if me.left then W.Let("left") end
	if me.right then W.Let("right") end
	for k in pairs(me.pad) do me.pad[k] = nil end
	cam.yourYawRate = 0
	if me.cast then W.CastEnd("stop") end
	if me.combat then W.Fight(false) end
	if me.afk then W.AFK(false) end
	if me.taxi then W.Taxi(false) end
	if me.dead or me.ghost then me.dead, me.ghost = false, false W.Fire("PLAYER_ALIVE") W.Fire("PLAYER_UNGHOST") end
	if not opts.keepStill then
		W.Move(true) W.Run(1.5) W.Move(false)
	end
	W.Run(opts.settle or 40)

	-- The checks.
	if not opts.noCvarCheck then
		for key, yours in pairs(W.YOURS) do
			if key:find("^camera") and key:find("Speed") and tonumber(W.cvars[key]) ~= tonumber(yours) then
				Fail(("your %s left at %s (yours %s)"):format(key, tostring(W.cvars[key]), yours))
			end
		end
	end
	if cam.yawRate ~= 0 or cam.pitchRate ~= 0 then
		Fail(("the camera is still turning after it all (turn %s, tilt %s)"):format(cam.yawRate, cam.pitchRate))
	end
	if T.Playing() and not opts.playingAtEnd then Fail("a script is still playing: " .. tostring(T.Playing())) end
	local holder = ns.CameraHolder and ns.CameraHolder(nil)
	if holder and not opts.playingAtEnd then Fail("the camera lock is still held by " .. tostring(holder)) end
	if math.abs(cam.goal - cam.zoom) > 0.05 then Fail("a zoom is still under way at the end") end
	if not opts.zoomMoves and math.abs(cam.zoom - startZoom) > 0.75 then
		Fail(("zoom left at %.1f (started at %.1f)"):format(cam.zoom, startZoom))
	end
	if stats.fightFrames > 0 then
		Fail(("ours kept turning the view for %d frames while you held the camera (first at %.2f)"):format(
			stats.fightFrames, stats.fightAt))
	end
	if stats.maxTurn > (opts.maxTurn or 100) then
		Fail(("a whip: ours turned at %.0f deg/s (at %.2f)"):format(stats.maxTurn, stats.maxTurnAt))
	end
	if (stats.maxTilt or 0) > (opts.maxTilt or 60) then
		Fail(("a whip: ours tilted at %.0f deg/s (at %.2f)"):format(stats.maxTilt, stats.maxTiltAt))
	end
	if stats.maxZoomRate > (opts.maxZoomRate or 12) then
		Fail(("a zoom snap: %.0f yards/s with no scroll of yours (at %.2f)"):format(stats.maxZoomRate, stats.maxZoomAt))
	end
	local starts = T.Count("camera script .- started")
	if starts > (opts.maxStarts or 6) then Fail(("scripts started %d times"):format(starts)) end
	for _, line in ipairs(W.log) do
		if line.kind == "safety" then Fail("safety: " .. line.text) end
		if line.kind == "ERROR" and line.text:find("Camera") then Fail("error: " .. line.text:match("^[^\n]*")) end
	end
	for _, key in ipairs(W.errors) do
		if key:find("Camera") or key:find("Director") or key:find("QuestCam") or key:find("ChatCam")
			or key:find("Triggers") or key:find("Skyride") or key:find("ZoomGuard") or key:find("Core%.lua") then
			Fail(("Lua error x%d: %s"):format(W.errors[key].n, key))
		end
	end
	results[#results + 1] = { name = name, fails = fails, notes = notes, starts = starts, stats = stats }
	if verbose then
		for _, line in ipairs(W.log) do
			if line.kind ~= "manacost" and line.kind ~= "style" then
				print(("  %7.2f %s: %s"):format(line.t, line.kind, (line.text:gsub("\n.*", ""))))
			end
		end
		print(("  zoom %.2f yaw %.1f pitch %.1f; sends %d zoomSends %d; max turn %.0f tilt %.0f zoom %.1f"):format(
			cam.zoom, cam.yaw, cam.pitch, cam.sends, cam.zoomSends, stats.maxTurn, stats.maxTilt or 0, stats.maxZoomRate))
	end
	return fails
end

local HEARTH = 8690
local S = {}
local order = {}
local function Scenario(name, opts, body)
	if not body then opts, body = {}, opts end
	-- (The Tele camera's own way back is quick by design: half a second, teleZoomBackTime.)
	if name:find("hearth") then opts.maxTurn, opts.maxTilt, opts.maxZoomRate = opts.maxTurn or 400, 200, 60 end
	S[name] = { opts = opts, body = body }
	order[#order + 1] = name
end

-- A window the cameras wait for (the Escape menu).
local function Window(_, on)
	local f = rawget(_G, "GameMenuFrame")
	if type(f) ~= "table" or not rawget(f, "_scripts") then
		f = CreateFrame("Frame", "GameMenuFrame")
		f:Hide()
	end
	if on then f:Show() else f:Hide() end
end

Scenario("hearth", function(T)
	local W = T.W
	W.Cast(HEARTH, 10)
	local took = T.WaitFor("Tele camera", 3)
	T.Expect(took, "the Tele camera never started on a Hearthstone cast")
	T.notes[#T.notes + 1] = took and ("started %.2fs after the cast"):format(took)
	W.Run(10 - (took or 3))
	T.Expect(T.Count("Tele camera ended") == 0, "the Tele camera ended before the cast did")
	W.CastEnd("done")
	W.Loading()
end)

Scenario("hearth, gamepad + ConsolePort (mouselook reported for the cast)", { consolePort = true }, function(T)
	local W = T.W
	W.Pad(true)
	W.Run(1)
	W.Cast(HEARTH, 10)
	local took = T.WaitFor("Tele camera", 3)
	T.Expect(took, "the Tele camera never started (gamepad cast)")
	W.Run(6)
	T.Expect(T.Count("Tele camera ended") == 0, "the Tele camera ended mid-cast (gamepad): " .. tostring(T.Playing()))
	W.Run(1)
	W.CastEnd("done")
	W.Loading()
end)

Scenario("hearth, gamepad right stick mid-cast", { consolePort = true }, function(T)
	local W = T.W
	W.Pad(true)
	W.Cast(HEARTH, 10)
	T.Expect(T.WaitFor("Tele camera", 3), "the Tele camera never started (gamepad cast)")
	W.Run(2)
	W.Stick("LEFT", true)
	W.Run(2)
	T.Expect(T.Count("Tele camera ended") > 0, "the right stick didn't take the camera from the Tele camera")
	W.Stick("LEFT", false)
	W.Run(3)
	W.CastEnd("done")
end)

Scenario("hearth cancelled by walking", function(T)
	local W = T.W
	W.Cast(HEARTH, 10)
	T.Expect(T.WaitFor("Tele camera", 3), "the Tele camera never started")
	W.Run(3)
	W.Move(true)
	W.CastEnd("stop")
	W.Run(2)
	W.Move(false)
end)

Scenario("hearth, you drag the camera mid-cast", function(T)
	local W = T.W
	W.Cast(HEARTH, 10)
	T.Expect(T.WaitFor("Tele camera", 3), "the Tele camera never started")
	W.Run(2)
	W.Press("left", 40)
	W.Run(2)
	W.Let("left")
	W.Run(5)
	T.Expect(T.Count("Tele camera started") == 1, "the Tele camera started again after you took the camera")
	W.CastEnd("done")
end)

Scenario("hearth, a quick click on the world mid-cast", function(T)
	local W = T.W
	W.Cast(HEARTH, 10)
	T.Expect(T.WaitFor("Tele camera", 3), "the Tele camera never started")
	W.Run(2)
	W.Press("left", 0)
	W.Run(0.06)
	W.Let("left")
	W.Run(6)
	T.Expect(T.Count("Tele camera ended") == 0, "a quick click on the world ended the Tele camera")
	W.CastEnd("done")
end)

Scenario("hearth, a fight starts mid-cast", function(T)
	local W = T.W
	W.Cast(HEARTH, 10)
	T.Expect(T.WaitFor("Tele camera", 3), "the Tele camera never started")
	W.Run(3)
	W.Fight(true)
	W.CastEnd("stop")
	W.Run(6)
	W.Fight(false)
end)

Scenario("hearth while sitting (one scene taking over from another)", function(T)
	local W = T.W
	W.Emote("SIT")
	T.Expect(T.WaitFor("Vista camera", 3), "the Vista camera never started on /sit")
	W.Run(8)
	W.Cast(HEARTH, 10)
	local took = T.WaitFor("Tele camera", 10)
	T.Expect(took, "the Tele camera never took over from the Vista camera")
	if took then
		T.notes[#T.notes + 1] = ("Tele started %.1fs into a 10s cast"):format(took)
		T.Expect(took <= 2.5, ("the Tele camera started %.1fs into the 10s cast: it waits for the other scene's When it ends"):format(took))
	end
	W.Run(10 - (took or 10))
	W.CastEnd("done")
	W.Loading()
end)

Scenario("sit, then walk off", function(T)
	local W = T.W
	W.Emote("SIT")
	local took = T.WaitFor("Vista camera", 3)
	T.Expect(took, "the Vista camera never started on /sit")
	W.Run(20)
	T.Expect(T.Count("Vista camera ended") == 0, "the Vista camera ended while you sat")
end)

Scenario("sit, drag the camera, let go", function(T)
	local W = T.W
	W.Emote("SIT")
	T.Expect(T.WaitFor("Vista camera", 3), "the Vista camera never started")
	W.Run(6)
	W.Press("left", 50)
	W.Run(3)
	W.Let("left")
	W.Run(12)
	T.Expect(T.Count("Vista camera started") == 1, "the Vista camera started over after your drag (rule: Pause)")
end)

Scenario("sit, right-drag (mouselook), let go", function(T)
	local W = T.W
	W.Emote("SIT")
	T.Expect(T.WaitFor("Vista camera", 3), "the Vista camera never started")
	W.Run(6)
	W.Press("right", 50)
	W.Run(3)
	W.Let("right")
	W.Run(12)
end)

Scenario("sit, you scroll in mid-scene", { zoomMoves = true }, function(T)
	local W = T.W
	W.Emote("SIT")
	T.Expect(T.WaitFor("Vista camera", 3), "the Vista camera never started")
	W.Run(8)
	W.Scroll(-4)
	W.Run(10)
	local zoomAfter = T.cam.zoom
	T.after = function() end
	T.notes[#T.notes + 1] = ("zoom %.1f after your scroll, started %.1f"):format(zoomAfter, T.startZoom)
end)

Scenario("mouse release lost (alt-tab), then /sit", function(T)
	local W = T.W
	W.Press("left", 0)
	W.Run(0.3)
	W.Let("left", true) -- the game never sends the Stop
	W.Run(5)
	W.Emote("SIT")
	local took = T.WaitFor("Vista camera", 6)
	T.Expect(took, "no scene starts after a lost mouse release: the press is still counted as held")
end)

Scenario("mouse release lost during a loading screen, then hearth", function(T)
	local W = T.W
	W.Press("right", 0)
	W.Run(0.2)
	W.Let("right", true)
	W.Loading()
	W.Run(3)
	W.Cast(HEARTH, 10)
	T.Expect(T.WaitFor("Tele camera", 3), "no Tele camera after a release lost in a loading screen")
	W.Run(5)
	W.CastEnd("done")
end)

Scenario("mouse release lost mid-scene", function(T)
	local W = T.W
	W.Emote("SIT")
	T.Expect(T.WaitFor("Vista camera", 3), "the Vista camera never started")
	W.Run(5)
	W.Press("left", 30)
	W.Run(1)
	W.Let("left", true)
	W.Run(20)
	local paused = T.ns.CameraScriptState and T.ns.CameraScriptState()
	T.Expect(T.stats.maxTurnAt and T.stats.maxTurnAt > 9 or T.cam.sends > 0 and T.cam.starts[#T.cam.starts].t - 1000 > 12,
		"the scene never carried on after a lost mouse release mid-scene")
	local _ = paused
end)

Scenario("afk, then move", function(T)
	local W = T.W
	W.AFK(true)
	T.Expect(T.WaitFor("AFK camera", 3), "the AFK camera never started")
	W.Run(30)
	T.Expect(T.Count("AFK camera ended") == 0, "the AFK camera ended while you were AFK")
	W.Move(true)
	W.AFK(false)
	W.Run(1)
	W.Move(false)
end)

Scenario("afk, a fight starts", function(T)
	local W = T.W
	W.AFK(true)
	T.Expect(T.WaitFor("AFK camera", 3), "the AFK camera never started")
	W.Run(10)
	W.Fight(true)
	W.Run(8)
	W.AFK(false)
	W.Fight(false)
end)

Scenario("afk, the Escape menu opens and closes", function(T)
	local W = T.W
	W.AFK(true)
	T.Expect(T.WaitFor("AFK camera", 3), "the AFK camera never started")
	W.Run(8)
	Window(T, true)
	W.Run(6)
	Window(T, false)
	W.Run(10)
	T.Expect(T.Count("AFK camera started") == 1, "the AFK camera started over after a window closed")
	T.Expect(T.Playing(), "the AFK camera didn't carry on after the window closed")
end)

Scenario("afk, loading screen mid-scene", function(T)
	local W = T.W
	W.AFK(true)
	T.Expect(T.WaitFor("AFK camera", 3), "the AFK camera never started")
	W.Run(8)
	W.Loading()
	W.Run(8)
end)

Scenario("afk, /reload mid-scene (settings at logout)", { maxZoomRate = 25 }, function(T)
	local W = T.W
	W.AFK(true)
	T.Expect(T.WaitFor("AFK camera", 3), "the AFK camera never started")
	W.Run(8)
	W.Fire("PLAYER_LOGOUT")
	for key, yours in pairs(W.YOURS) do
		if key:find("Speed") and tonumber(W.cvars[key]) ~= tonumber(yours) then
			T.Fail(("at logout your %s was %s (yours %s): the game saves that"):format(key, W.cvars[key], yours))
		end
	end
	-- (Back in: the camera where the scene left it.)
	T.me.afk = false
	W.Fire("PLAYER_LOGIN")
	W.Run(3)
end)

Scenario("afk, Cinematic turned off mid-scene", { maxZoomRate = 25 }, function(T)
	local W = T.W
	W.AFK(true)
	T.Expect(T.WaitFor("AFK camera", 3), "the AFK camera never started")
	W.Run(8)
	T.ns.db.enabled = false
	W.Run(5)
	for key, yours in pairs(W.YOURS) do
		if key:find("Speed") and tonumber(W.cvars[key]) ~= tonumber(yours) then
			T.Fail(("5s after turning Cinematic off your %s was %s (yours %s)"):format(key, W.cvars[key], yours))
		end
	end
	T.ns.db.enabled = true
	W.AFK(false)
end)

Scenario("flight", { settle = 40 }, function(T)
	local W = T.W
	W.Taxi(true)
	local took = T.WaitFor("Flight camera", 5)
	T.Expect(took, "the Flight camera never started on a flight")
	W.Run(60)
	W.Taxi(false)
end)

Scenario("flight, you drag mid-flight", function(T)
	local W = T.W
	W.Taxi(true)
	T.Expect(T.WaitFor("Flight camera", 5), "the Flight camera never started on a flight")
	W.Run(15)
	W.Press("left", 40)
	W.Run(3)
	W.Let("left")
	W.Run(40)
	W.Taxi(false)
end)

Scenario("flight, short hop (lands mid-opening)", function(T)
	local W = T.W
	W.Taxi(true)
	W.Run(2.5)
	W.Taxi(false)
end)

Scenario("flight into a loading screen", function(T)
	local W = T.W
	W.Taxi(true)
	T.Expect(T.WaitFor("Flight camera", 5), "the Flight camera never started on a flight")
	W.Run(12)
	W.Loading()
	W.Run(10)
	W.Taxi(false)
end)

Scenario("death, then release", function(T)
	local W = T.W
	T.me.dead = true
	W.Fire("PLAYER_DEAD")
	local took = T.WaitFor("Death camera", 8)
	T.notes[#T.notes + 1] = took and ("Death camera after %.1fs"):format(took) or "no Death camera (its conditions)"
	W.Run(20)
	T.me.dead, T.me.ghost = false, true
	W.Fire("PLAYER_ALIVE")
	W.Run(10)
	T.me.ghost = false
	W.Fire("PLAYER_UNGHOST")
end)

Scenario("RP walk (auto-run while walking)", function(T)
	local W = T.W
	W.Key("ToggleRun")
	T.me.walkMode = true
	W.AutoRun(true)
	local took = T.WaitFor("RP walk camera", 12)
	T.notes[#T.notes + 1] = took and ("RP walk camera after %.1fs"):format(took) or "no RP walk camera"
	W.Run(25)
	W.Press("right", 30) -- steering
	W.Run(3)
	W.Let("right")
	W.Run(15)
	W.AutoRun(false)
	W.Key("ToggleRun")
end)

Scenario("sit / stand flapping", { maxStarts = 14 }, function(T)
	local W = T.W
	for _ = 1, 6 do
		W.Emote("SIT")
		W.Run(1.2)
		W.Move(true) W.Run(0.4) W.Move(false)
		W.Run(0.6)
	end
end)

Scenario("afk on/off flapping with drags", { maxStarts = 14 }, function(T)
	local W = T.W
	for i = 1, 6 do
		W.AFK(true)
		W.Run(2.5)
		if i % 2 == 0 then W.Press("left", 30) W.Run(0.5) W.Let("left") end
		W.AFK(false)
		W.Run(0.7)
	end
end)

Scenario("hearth cast twice in a row (cancel, recast)", function(T)
	local W = T.W
	W.Cast(HEARTH, 10)
	T.Expect(T.WaitFor("Tele camera", 3), "the Tele camera never started")
	W.Run(2)
	W.CastEnd("stop")
	W.Run(1)
	W.Cast(HEARTH, 10)
	local took = T.WaitFor("Tele camera", 9)
	T.Expect(took, "the Tele camera didn't start for the recast")
	if took then
		T.notes[#T.notes + 1] = ("recast: Tele after %.1fs"):format(took)
		T.Expect(took <= 2.5, ("a recast's Tele camera started %.1fs into the cast"):format(took))
	end
	W.Run(10 - (took or 9))
	W.CastEnd("done")
	W.Loading()
end)

Scenario("sit in a fight (no start), fight ends", function(T)
	local W = T.W
	W.Fight(true)
	W.Emote("SIT")
	W.Run(5)
	T.Expect(T.Count("camera script .- started") == 0, "a scene started in a fight")
	W.Fight(false)
	W.Run(70)
	T.notes[#T.notes + 1] = ("after the fight: %d scene starts"):format(T.Count("camera script .- started"))
end)

Scenario("sit, gamepad right stick turns the camera (no cast)", function(T)
	local W = T.W
	W.Pad(true)
	W.Emote("SIT")
	T.Expect(T.WaitFor("Vista camera", 3), "the Vista camera never started")
	W.Run(6)
	W.Stick("LEFT", true)
	W.Run(3)
	W.Stick("LEFT", false)
	W.Run(8)
end)

Scenario("mouse held as the trigger comes on, then let go", function(T)
	local W = T.W
	W.Press("left", 20)
	W.Run(1)
	W.Emote("SIT")
	W.Run(3)
	T.Expect(T.Count("camera script .- started") == 0, "a scene started with your mouse down on the camera")
	W.Let("left")
	local took = T.WaitFor("Vista camera", 20)
	T.Expect(took, "the scene never started after you let the mouse go")
	T.notes[#T.notes + 1] = took and ("started %.1fs after letting go"):format(took)
	W.Run(5)
end)

Scenario("Escape menu open as the trigger comes on, then closed", function(T)
	local W = T.W
	Window(T, true)
	W.Run(1)
	W.AFK(true)
	W.Run(4)
	T.Expect(T.Count("camera script .- started") == 0, "a scene started with a window open")
	Window(T, false)
	T.Expect(T.WaitFor("AFK camera", 5), "the AFK camera never started after the window closed")
	W.Run(5)
end)

Scenario("sit, then AFK, then hearth (three scenes in a row)", function(T)
	local W = T.W
	W.Emote("SIT")
	T.Expect(T.WaitFor("Vista camera", 3), "the Vista camera never started")
	W.Run(10)
	W.AFK(true)
	local took = T.WaitFor("AFK camera", 15)
	T.notes[#T.notes + 1] = took and ("AFK camera took over after %.1fs"):format(took) or "AFK camera never took over from Vista"
	W.Run(10)
	W.Cast(HEARTH, 10)
	took = T.WaitFor("Tele camera", 10)
	T.Expect(took, "the Tele camera never took over")
	if took then T.Expect(took <= 2.5, ("the Tele camera started %.1fs into the 10s cast"):format(took)) end
	W.Run(10 - (took or 10))
	W.CastEnd("done")
	W.Loading()
	W.AFK(false)
end)

Scenario("fishing, clicking the bobber and recasting", function(T)
	local W = T.W
	for i = 1, 3 do
		W.Cast(7620, 20, true)
		if i == 1 then T.Expect(T.WaitFor("Fish camera", 3), "the Fish camera never started") end
		W.Run(8)
		W.Press("right", 0) -- a quick right-click on the bobber
		W.Run(0.1)
		W.Let("right")
		W.CastEnd("stop")
		W.Run(1.5)
	end
	T.Expect(T.Count("Fish camera started") == 1, ("the Fish camera started %d times over 3 casts"):format(T.Count("Fish camera started")))
	T.Expect(T.Count("Fish camera ended") == 0, "the Fish camera ended while you fished")
end)

Scenario("quest giver's window, accept, walk off", function(T)
	local W = T.W
	W.Quest("QUEST_DETAIL")
	local took = T.WaitFor("Quest camera", 6)
	T.Expect(took, "the Quest camera never started at a quest giver")
	T.notes[#T.notes + 1] = took and ("Quest camera after %.1fs"):format(took)
	W.Run(8)
	W.Quest("accept")
	W.Run(4)
	W.Move(true) W.Run(3) W.Move(false)
end)

Scenario("quest giver's window, you drag mid-conversation", function(T)
	local W = T.W
	W.Quest("QUEST_DETAIL")
	T.Expect(T.WaitFor("Quest camera", 6), "the Quest camera never started at a quest giver")
	W.Run(4)
	W.Press("left", 40)
	W.Run(2)
	W.Let("left")
	W.Run(6)
	T.Expect(T.Count("Quest camera started") == 1, "the Quest camera started over after you took the camera")
	W.Quest("accept")
	W.Run(2)
	W.Move(true) W.Run(4) W.Move(false)
end)

Scenario("quest giver's window, three quests in a row", function(T)
	local W = T.W
	for i = 1, 3 do
		W.Quest("QUEST_DETAIL")
		if i == 1 then T.Expect(T.WaitFor("Quest camera", 6), "the Quest camera never started at a quest giver") end
		W.Run(4)
		W.Quest("accept")
		W.Run(0.6)
	end
	T.Expect(T.Count("Quest camera started") == 1, ("the Quest camera started %d times for one conversation"):format(T.Count("Quest camera started")))
	W.Run(6)
	W.Move(true) W.Run(3) W.Move(false)
end)

Scenario("quest giver's window, a fight starts", function(T)
	local W = T.W
	W.Quest("QUEST_DETAIL")
	T.Expect(T.WaitFor("Quest camera", 6), "the Quest camera never started at a quest giver")
	W.Run(5)
	W.Fight(true)
	W.Quest("accept")
	W.Run(8)
	W.Fight(false)
end)

Scenario("death, you drag the camera", function(T)
	local W = T.W
	T.me.dead = true
	W.Fire("PLAYER_DEAD")
	T.Expect(T.WaitFor("Death camera", 8), "the Death camera never started")
	W.Run(6)
	W.Press("left", 40)
	W.Run(2)
	W.Let("left")
	W.Run(15)
	T.me.dead, T.me.ghost = false, true
	W.Fire("PLAYER_ALIVE")
	W.Run(5)
end)

Scenario("hearth during the AFK camera, cancelled (the turn goes all the way back)", function(T)
	local W = T.W
	W.AFK(true)
	T.Expect(T.WaitFor("AFK camera", 3), "the AFK camera never started")
	W.Run(12)
	W.Cast(HEARTH, 10)
	local took = T.WaitFor("Tele camera", 10)
	T.Expect(took and took <= 1, ("the Tele camera started %s s into the cast"):format(tostring(took)))
	W.Run(4)
	W.AFK(false)
	W.Move(true)
	W.CastEnd("stop")
	W.Run(3)
	W.Move(false)
	W.Run(3)
	T.Expect(math.abs(T.cam.yaw) < 3 and math.abs(T.cam.pitch) < 3,
		("the camera was left turned %.0f, tilted %.0f after the cancelled cast"):format(T.cam.yaw, T.cam.pitch))
end)

Scenario("sit, a fight starts mid-scene", function(T)
	local W = T.W
	W.Emote("SIT")
	T.Expect(T.WaitFor("Vista camera", 3), "the Vista camera never started")
	W.Run(10)
	W.Fight(true)
	W.Run(6)
	W.Fight(false)
end)

-- Random moments, one after another, checked the same way.
local function Fuzz(seed)
	return function(T)
		local W, me = T.W, T.me
		local state = seed
		local function Rand(n) -- (its own generator: the addon uses math.random too)
			state = (state * 1103515245 + 12345) % 2147483648
			return state % n + 1
		end
		local did = {}
		local actions = {
			function() W.Emote("SIT") return "sit" end,
			function() W.Emote("DANCE") return "dance" end,
			function() if not me.cast then W.Cast(HEARTH, 10) return "hearth" end end,
			function() if me.cast then W.CastEnd(Rand(2) == 1 and "done" or "stop") return "cast end" end end,
			function() W.AFK(not me.afk) return "afk " .. tostring(me.afk) end,
			function() W.Move(not me.moving) return "move " .. tostring(me.moving) end,
			function() if not me.left then W.Press("left", 30) else W.Let("left", Rand(6) == 1) end return "left " .. tostring(me.left) end,
			function() if not me.right then W.Press("right", 30) else W.Let("right", Rand(6) == 1) end return "right " .. tostring(me.right) end,
			function() W.Scroll(Rand(2) == 1 and -2 or 2) return "scroll" end,
			function() W.Fight(not me.combat) return "fight " .. tostring(me.combat) end,
			function() if not me.cast then W.Taxi(not me.taxi) return "taxi " .. tostring(me.taxi) end end,
			function() W.Loading() return "loading" end,
			function() Window(T, Rand(2) == 1) return "window" end,
			function() W.Key("JumpOrAscendStart") return "jump" end,
		}
		for _ = 1, 60 do
			local what = actions[Rand(#actions)]()
			if what then did[#did + 1] = ("%.1f %s"):format(W.now - 1000, what) end
			W.Run(Rand(40) / 10)
		end
		Window(T, false)
		if me.moving then W.Move(false) end
		T.notes[#T.notes + 1] = table.concat(did, "; ")
	end
end

local seed = tonumber(seedArg) or 1
local count = tonumber(countArg) or 40
if which == "fuzz" then
	for i = seed, seed + count - 1 do
		Play("fuzz " .. i, { zoomMoves = true, maxStarts = 60, consolePort = i % 4 == 0, maxTurn = 400, maxTilt = 200,
			maxZoomRate = 60 }, Fuzz(i))
	end
else
	for _, name in ipairs(order) do
		if which == "all" or name == which or name:find(which, 1, true) then
			Play(name, S[name].opts, S[name].body)
		end
	end
	if which:match("^fuzz (%d+)$") then
		local i = tonumber(which:match("^fuzz (%d+)$"))
		Play("fuzz " .. i, { zoomMoves = true, maxStarts = 60, consolePort = i % 4 == 0, maxTurn = 400, maxTilt = 200,
			maxZoomRate = 60 }, Fuzz(i))
	end
end

local bad = 0
for _, r in ipairs(results) do
	local ok = #r.fails == 0
	if not ok then bad = bad + 1 end
	print(("%s  %s  (%d scene starts; max turn %.0f, tilt %.0f deg/s, zoom %.1f y/s)"):format(ok and "ok  " or "FAIL", r.name,
		r.starts, r.stats.maxTurn, r.stats.maxTilt or 0, r.stats.maxZoomRate))
	for _, f in ipairs(r.fails) do print("        - " .. f) end
	if which ~= "fuzz" or not ok then
		for _, n in ipairs(r.notes) do if n then print("        . " .. tostring(n):sub(1, which == "fuzz" and 1500 or 300)) end end
	end
end
print(("%s: %d of %d failed"):format(client, bad, #results))
