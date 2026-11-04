-- Cinematic: camera scripts (the Scripts page). A camera written as a list of
-- small steps: rotate, tilt, zoom (to a distance, or somewhere at random),
-- wait, line up behind you, do an emote, put everything back; Together runs
-- its steps side by side, Repeat runs them again (or until the camera ends).
-- Stop rules say what happens when you move the camera, a fight starts, you
-- walk, you zoom, or its trigger ends; When it ends is a list of steps of its
-- own (usually Put back). CameraScriptsPage.lua is the page that writes them.
--
-- A script is a camera like the built-in ones: a Cameras page row set to it
-- starts it (a standing-still trigger, one of your own, a Hearthstone or
-- teleport cast, or a flight), or Run on its page, or /cine script play.
-- The built-in ones are examples: the steps our own cameras take (fly-by,
-- quest cam, Chat Cam, AFK camera), with your settings, to copy.
--
-- The moves go out as the quest cam's do (QuestCam.lua says why at length):
-- one held turn, tilt or zoom per move, its speed setting stepped along an
-- eased curve, sent at the share of your speed setting that makes it the
-- move's top speed; a creep start under the lowest setting (no jump on the
-- first frame); a turn and a tilt never at once, with a short gap between
-- moves; the zoom steered toward its eased path. Camera follow is off while
-- one runs. One camera at a time (ns.ClaimCamera): it holds the view from
-- start to end, and your camera input stops its moves at once.
--
-- Saved in db.cameraScripts (all profiles share it): list (your scripts),
-- nextId, preview (the preview window's place). A row's camera value for a
-- script is "script:<id>".
local _, ns = ...
local L = ns.L

local WHO = "script"
local MOVE_MIN_TIME = 1     -- seconds: the shortest turn, tilt or zoom
local MIN_SETTING = 1       -- the lowest speed setting sent (lower, the game uses its full speed)
local MIN_SPEED = 1         -- degrees a second: the slowest a move goes (its end creeps in at this)
local CHANGE = 0.02         -- speed setting changes smaller than this share aren't sent
local PRIME_TIME = 0.2      -- seconds the lowest setting goes in before a move starts...
local PRIME_SHARE = 0.001   -- ...creeping meanwhile at this share of it (see FLYBY.PRIME_SHARE)
local RESTORE_DELAY = 0.3   -- seconds after a move stops before your speed setting comes back
local STEP_GAP = 0.6        -- seconds between a turn or tilt stopping and the next starting
local MAX_STEPS = 80        -- steps in a script, all lists and depths together
local MAX_DEPTH = 4         -- Together and Repeat inside each other
local MAX_SCRIPTS = 30
local MAX_PLAYS = 3         -- Play steps inside each other (a camera playing itself, say)
local EASES = { smooth = 0.5, gentle = 0.35, steady = 0.15 } -- share of a move spent speeding up (and slowing down)
local FOLLOW_CVARS = ns.CVarSet("Follow off: camera script", "camera follow off while a script plays",
	{ values = { cameraSmoothStyle = "0" } }) -- camera follow off meanwhile
ns.CAMERA_SCRIPT_EASES = { "smooth", "gentle", "steady" }

-- ---------------------------------------------------------------------------
-- The steps
-- ---------------------------------------------------------------------------

-- Each kind: its fields { key, kind ("num" min max, "pick" choices, "text",
-- or "script": a camera's id), default }.
-- group: holds steps of its own.
ns.CAMERA_SCRIPT_KINDS = {
	-- (way "once": either way, picked as the script starts and the same for
	-- every such turn in it. of "yours": yards from your own distance as it
	-- started, out positive, rather than from you.)
	rotate = { fields = { { "deg", "num", 1, 3600, 45 }, { "secs", "num", 0.5, 600, 4 },
		{ "way", "pick", { "left", "right", "random", "once" }, "left" },
		{ "ease", "pick", ns.CAMERA_SCRIPT_EASES, "smooth" } } },
	tilt = { fields = { { "deg", "num", -80, 80, 10 }, { "secs", "num", 0.5, 600, 3 } } },
	-- (fit "cast": over the time a Hearthstone or teleport cast has left
	-- instead of secs, as the tele camera's zoom in goes. speed: yards a
	-- second at its fastest, secs then the longest it takes; 0 goes by secs.
	-- past "yes": the game's max zoom distance raised meanwhile, as far as 2.6
	-- times, so a zoom out isn't cut short at yours.)
	zoom = { fields = { { "to", "num", -50, 50, 5 }, { "secs", "num", 0.5, 600, 3 },
		{ "of", "pick", { "yards", "yours" }, "yards" }, { "fit", "pick", { "secs", "cast" }, "secs" },
		{ "speed", "num", 0, 20, 0 }, { "ease", "pick", ns.CAMERA_SCRIPT_EASES, "gentle" },
		{ "past", "pick", { "no", "yes" }, "no" } } },
	zoomRand = { fields = { { "min", "num", -50, 50, 3 }, { "max", "num", -50, 50, 8 }, { "secs", "num", 0.5, 600, 6 },
		{ "of", "pick", { "yards", "yours" }, "yards" }, { "speed", "num", 0, 20, 0 },
		{ "ease", "pick", ns.CAMERA_SCRIPT_EASES, "gentle" }, { "past", "pick", { "no", "yes" }, "no" } } },
	lineup = { fields = { { "secs", "num", 0.5, 600, 3 } } },
	wait = { fields = { { "secs", "num", 0, 3600, 2 } } },
	emote = { fields = { { "token", "text", "wave" } } },
	-- (zoom "no": the zoom left where it is, a zoom step beside it say.)
	putback = { fields = { { "secs", "num", 0.5, 600, 3 }, { "zoom", "pick", { "yes", "no" }, "yes" } } },
	-- (Turn to behind: the game's camera follow brings it round, as the vista
	-- camera lines up; the counts start again from there. In front: counted
	-- from where the script started, or that line-up.)
	-- (fit "cast": there by the time a cast is teleArriveEarly from done, as
	-- the tele camera swings round.)
	turnTo = { fields = { { "to", "pick", { "behind", "front" }, "behind" },
		{ "secs", "num", 0.5, 600, 6 }, { "fit", "pick", { "secs", "cast" }, "secs" } } },
	-- A random spot within arc degrees of behind (or in front), at least min
	-- from where it is (favor: nearer the middle, as the vista and fish cameras
	-- like), over secs; then creeping on the same way at drift degrees a second
	-- through pause seconds, flowing straight out of the turn and easing off
	-- before the arc's edge.
	sway = { fields = { { "around", "pick", { "behind", "front" }, "behind" }, { "arc", "num", 1, 180, 30 },
		{ "min", "num", 0, 180, 10 }, { "secs", "num", 0.5, 600, 10 }, { "ease", "pick", ns.CAMERA_SCRIPT_EASES, "smooth" },
		{ "drift", "num", 0, 30, 0.5 }, { "pause", "num", 0, 600, 15 }, { "favor", "pick", { "no", "yes" }, "no" } } },
	-- A random height: deg down from where it started (negative: up), give or
	-- take down and up.
	tiltRand = { fields = { { "deg", "num", -80, 80, 5 }, { "down", "num", 0, 80, 3 }, { "up", "num", 0, 80, 5 },
		{ "secs", "num", 0.5, 600, 3 } } },
	-- Round and round, speeding up accel degrees a second each second to max;
	-- secs 0: until the camera ends.
	spin = { fields = { { "accel", "num", 0.5, 100, 8 }, { "max", "num", 1, 360, 120 }, { "secs", "num", 0, 3600, 0 },
		{ "way", "pick", { "left", "right", "random", "once" }, "left" } } },
	-- Waits for something: a cast secs from done (cast), landing in secs
	-- (landing: a route flown before; else touchdown), coming back to life
	-- (alive), or secs going by (time). With steps of its own, it runs them
	-- meanwhile and, once it's time, eases them to a stop and goes on.
	-- (talk: someone other than the one last aimed at says something.)
	["until"] = { group = true, fields = { { "what", "pick", { "cast", "landing", "alive", "talk", "time" }, "time" },
		{ "secs", "num", 0, 3600, 5 } } },
	-- Waits somewhere between min and max seconds, picked each time.
	waitRand = { fields = { { "min", "num", 0, 3600, 20 }, { "max", "num", 0, 3600, 60 } } },
	-- From here on: after you turn, once you've held still that long, camera
	-- follow glides the camera back behind you (as the RP walk and auto-run
	-- cameras do), and the script's counts start again from there.
	follow = { fields = { { "after", "num", 0, 30, 1.5 } } },
	-- Toward who you're talking to. at "click": deg degrees round to the side
	-- of the screen you clicked them on, as the quest cam turns (opened with
	-- a key, no click: miss). at "speaker": toward the one talking now, by
	-- their chat bubble, leaving them deg degrees off the middle, as Chat Cam
	-- swings (no bubble on screen: miss). miss "random": deg (or a short
	-- turn) either way; "stay": no turn; "look": turns round you, a full turn
	-- at most, until their bubble shows (back where it was if it never does).
	-- speed: degrees a second at its fastest, secs then the shortest it takes;
	-- 0 goes by secs.
	aim = { fields = { { "at", "pick", { "click", "speaker" }, "click" }, { "deg", "num", 0, 90, 30 },
		{ "secs", "num", 0.5, 600, 4 }, { "miss", "pick", { "random", "stay", "look" }, "random" },
		{ "ease", "pick", ns.CAMERA_SCRIPT_EASES, "smooth" }, { "speed", "num", 0, 90, 0 } } },
	-- Another camera's steps, here (not its stop rules or When it ends), as
	-- they are now: a built-in one follows your settings. Cameras playing
	-- cameras go MAX_PLAYS deep at most.
	play = { fields = { { "script", "script", "flyby" } } },
	together = { group = true, fields = {} },
	["repeat"] = { group = true, fields = { { "times", "num", 0, 100, 2 } } },
}
ns.CAMERA_SCRIPT_ADDABLE = { "rotate", "tilt", "zoom", "zoomRand", "lineup", "wait", "together", "repeat", "emote",
	"putback", "turnTo", "sway", "tiltRand", "spin", "until", "waitRand", "follow", "aim", "play" }
local KINDS = ns.CAMERA_SCRIPT_KINDS

-- The stop rules: each event's actions (the first is its default).
ns.CAMERA_SCRIPT_RULES = {
	{ key = "camera", actions = { "stop", "putback", "pause", "restart" } },
	{ key = "fight", actions = { "putback", "stop" } },
	{ key = "walk", actions = { "putback", "stop", "pause", "restart", "ignore" } },
	{ key = "zoom", actions = { "ignore", "stop", "putback", "pause" } },
	{ key = "ends", actions = { "putback", "stop" } },
}
local RULE_ACTIONS = {}
for _, rule in ipairs(ns.CAMERA_SCRIPT_RULES) do
	RULE_ACTIONS[rule.key] = {}
	for _, action in ipairs(rule.actions) do RULE_ACTIONS[rule.key][action] = true end
end

-- A step with its kind's defaults.
function ns.NewCameraScriptStep(kind)
	local def = KINDS[kind]
	if not def then return nil end
	local step = { k = kind }
	for _, field in ipairs(def.fields) do
		step[field[1]] = field[#field]
	end
	if def.group then step.steps = {} end
	return step
end

-- A field's value made safe: a number in its range, a choice it has, a short
-- word for an emote.
local function CleanField(field, value)
	local kind = field[2]
	if kind == "num" then
		value = tonumber(value)
		if not value or value ~= value then return field[5] end
		return math.max(field[3], math.min(field[4], value))
	elseif kind == "pick" then
		for _, choice in ipairs(field[3]) do
			if value == choice then return value end
		end
		return field[4]
	elseif kind == "script" then
		value = type(value) == "string" and value:match("^%w+$")
		return value and #value <= 24 and value or field[3]
	end
	value = type(value) == "string" and value:lower():match("^%s*(%a+)%s*$")
	return value and #value <= 24 and value or field[3]
end
ns.CleanCameraScriptField = CleanField

-- A list of steps made safe (from a share string, or saved by an older
-- version): unknown kinds dropped, fields in range, depth and count capped.
-- keepSet: a built-in camera's, its steps' settings kept (step.set: the
-- setting keys it's made from, for its page; a copy has none), and steps
-- switched off by one (step.off: shown greyed, not run; a copy leaves them out).
-- (paths: given, each step kept is noted in it with its place in the list as
-- its page shows it, prefix first: "2.1".)
local function CleanSteps(list, depth, budget, keepSet, paths, prefix)
	local out = {}
	if type(list) ~= "table" then return out end
	for i, step in ipairs(list) do
		local def = type(step) == "table" and KINDS[step.k]
		if def and budget.left > 0 and not (def.group and depth >= MAX_DEPTH) and (keepSet or not step.off) then
			budget.left = budget.left - 1
			local clean = { k = step.k }
			for _, field in ipairs(def.fields) do
				clean[field[1]] = CleanField(field, step[field[1]])
			end
			local at = paths and (prefix == "" and tostring(i) or (prefix .. "." .. i))
			if at then paths[clean] = at end
			if def.group then clean.steps = CleanSteps(step.steps, depth + 1, budget, keepSet, paths, at) end
			if keepSet and type(step.set) == "table" then clean.set = step.set end
			if keepSet and step.off then clean.off = true end
			out[#out + 1] = clean
		end
	end
	return out
end

local function CleanName(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|", ""):gsub("%c", " "):match("^%s*(.-)%s*$")
	if #text > 40 then text = text:sub(1, 40):gsub("[\192-\255][\128-\191]*$", "") end
	return text ~= "" and text or nil
end

-- A whole script made safe; its id kept if given. (keepSet: see CleanSteps.)
-- An icon: a game icon's path (Interface\Icons\...) or file id, else nil.
local function CleanIcon(icon)
	if type(icon) == "number" and icon > 0 then return math.floor(icon) end
	if type(icon) == "string" and icon:lower():find("^interface\\icons\\[^\\|]+$") then return icon end
end
-- A description: up to 200 letters, nil for none.
local function CleanDesc(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("|", ""):sub(1, 200):match("^%s*(.-)%s*$")
	return text ~= "" and text or nil
end

function ns.CleanCameraScript(script, id, keepSet, paths)
	if type(script) ~= "table" then return nil end
	local budget = { left = MAX_STEPS }
	local rules = {}
	local given = type(script.rules) == "table" and script.rules or {}
	for _, rule in ipairs(ns.CAMERA_SCRIPT_RULES) do
		local action = given[rule.key]
		rules[rule.key] = RULE_ACTIONS[rule.key][action] and action or rule.actions[1]
		local secs = tonumber(given[rule.key .. "Secs"])
		rules[rule.key .. "Secs"] = secs and math.max(1, math.min(60, secs)) or 5
		-- (Its tick: off, the event leaves it running; see Act.)
		rules[rule.key .. "On"] = given[rule.key .. "On"] ~= false
	end
	return {
		id = id or script.id,
		name = CleanName(script.name) or L["My camera"],
		steps = CleanSteps(script.steps, 1, budget, keepSet, paths, ""),
		ending = CleanSteps(script.ending, 1, budget, keepSet, paths, "e.1"), -- (its page's When it ends row)
		rules = rules,
		-- (Yours: the icon and words the General page shows for it.)
		icon = CleanIcon(script.icon),
		desc = CleanDesc(script.desc),
		-- (A built-in camera's stop rules and options made from settings:
		-- { [rule or "haze" or "button"] = { keys } }.)
		ruleSet = keepSet and type(script.ruleSet) == "table" and script.ruleSet or nil,
		-- Edge haze while it runs (0-1, the Visual Effects page's Camera haze
		-- scaling it), and a Stop button on screen meanwhile.
		haze = math.max(0, math.min(1, tonumber(script.haze) or 0)),
		button = script.button == true or nil,
	}
end

-- ---------------------------------------------------------------------------
-- The scripts: the built-in examples and yours
-- ---------------------------------------------------------------------------

local function S(kind, fields)
	local step = ns.NewCameraScriptStep(kind)
	for k, v in pairs(fields or {}) do step[k] = v end
	return step
end

local RestCamera, MovingCamera -- (below)
-- The built-in ones, from your settings now (each a function: they follow them).
-- A built-in step made from these settings (shown with it on its page).
local function Set(step, ...)
	step.set = { ... }
	return step
end
-- Switched off (on false): the step stays, greyed, not run (see CleanSteps),
-- so it can be switched back on from it.
local function On(step, on)
	step.off = not on or nil
	return step
end

local function Db(key, fallback)
	local value = ns.db and tonumber(ns.db[key])
	return value or fallback
end
-- A switch setting: on unless set false.
local function Switch(key)
	return not ns.db or ns.db[key] ~= false
end
-- The nearest of the named eases to a share (an orbit's Ease setting).
local function NearestEase(share)
	share = tonumber(share) or 0.5
	return share >= 0.42 and "smooth" or share >= 0.25 and "gentle" or "steady"
end

-- Over and over (o: the camera's orbit setting prefix, a switch itself): a
-- random height (level degrees down, levelKey's, give or take PitchDown and
-- PitchUp) and a sway within BackArc of behind (front: of your front), at
-- least MinChange on, over MoveTime, drifting on at DriftSpeed (Drift)
-- through Pause.
local function SwayLoop(o, level, levelKey, front)
	local height = S("tiltRand", { deg = level, down = Db(o .. "PitchDown", 3), up = Db(o .. "PitchUp", 5), secs = 3 })
	if levelKey then Set(height, levelKey, o .. "PitchDown", o .. "PitchUp") else Set(height, o .. "PitchDown", o .. "PitchUp") end
	-- (Auto-run's lowest tilt: the real camera's, while you steer; shown here.)
	if o == "runOrbit" then table.insert(height.set, "runOrbitPitchFloor") end
	local sway = Set(S("sway", { around = front and "front" or "behind", arc = Db(o .. "BackArc", 30),
		min = Db(o .. "MinChange", 10), secs = Db(o .. "MoveTime", 10), ease = NearestEase(Db(o .. "Ease", 0.5)),
		drift = Switch(o .. "Drift") and Db(o .. "DriftSpeed", 0.5) or 0, pause = Db(o .. "Pause", 15),
		favor = front and "no" or "yes" }), o .. "BackArc", o .. "MinChange", o .. "MoveTime", o .. "Ease", o .. "Pause",
		o .. "Drift", o .. "DriftSpeed")
	return On(Set(S("repeat", { times = 0, steps = { height, sway } }), o), Switch(o))
end

-- The slow zoom beside it (z: the zoom setting prefix, a switch itself):
-- out Distance from your distance over Time, then (Random) every Pause
-- (give or take PauseVary) somewhere from In closer to Distance further.
-- A Repeat once: its steps one after another, beside the sways. Each zoom
-- eases as Ease says, past your max distance with PastMax.
local function ZoomStepOf(z, kind, fields)
	fields.ease = NearestEase(Db(z .. "Ease", 0.5))
	fields.past = ns.db and ns.db[z .. "PastMax"] and "yes" or "no"
	return S(kind, fields)
end
local function ZoomGroup(z)
	local far, time = Db(z .. "Distance", 2), Db(z .. "Time", 10)
	local pause, vary = Db(z .. "Pause", 4), Db(z .. "PauseVary", 0)
	local wait = Set(vary > 0 and S("waitRand", { min = math.max(0, pause - vary), max = pause + vary })
		or S("wait", { secs = pause }), z .. "Pause", z .. "PauseVary")
	local drifts = On(Set(S("repeat", { times = 0, steps = { wait,
		Set(ZoomStepOf(z, "zoomRand", { min = -Db(z .. "In", 2), max = far, secs = time, of = "yours" }), z .. "In",
			z .. "Distance", z .. "Time", z .. "Ease", z .. "PastMax") } }), z .. "Random"), Switch(z .. "Random"))
	return On(Set(S("repeat", { times = 1, steps = {
		Set(ZoomStepOf(z, "zoom", { to = far, secs = time, of = "yours" }), z .. "Distance", z .. "Time", z .. "Ease",
			z .. "PastMax"), drifts } }), z), Switch(z))
end

-- A standing-still camera that sways (vista, fish, cozy), from its settings
-- (<cam>Orbit..., <cam>Level, <cam>Zoom...). Vista and fish: line up behind
-- you with camera follow, then the sways round Level beside the slow zoom.
-- Cozy: swings round in front of you while zooming in to cozyZoomClose,
-- then the same round your front, its zoom drifting about the close-up.
-- Leaving, the zoom goes back to where it began; the turn stays (as theirs
-- do). (Not the same yet: a height and a sway go one after the other, the
-- game won't do both at once with these moves; and the cozy camera doesn't
-- keep clear of Camp Tents.)
function RestCamera(cam)
	local o, z = cam .. "Orbit", cam .. "Zoom"
	local front = cam == "cozy"
	local loop = SwayLoop(o, Db(cam .. "Level", 5), cam .. "Level", front)
	local steps
	if front then
		local close, near, far, time = Db("cozyZoomClose", 10), Db(z .. "In", 2), Db(z .. "Distance", 2), Db(z .. "Time", 10)
		local pause, vary = Db(z .. "Pause", 4), Db(z .. "PauseVary", 0)
		local wait = Set(vary > 0 and S("waitRand", { min = math.max(0, pause - vary), max = pause + vary })
			or S("wait", { secs = pause }), z .. "Pause", z .. "PauseVary")
		local drifts = On(Set(S("repeat", { times = 0, steps = { wait,
			Set(ZoomStepOf(z, "zoomRand", { min = close - near, max = close + far, secs = time }), "cozyZoomClose",
				z .. "In", z .. "Distance", z .. "Time", z .. "Ease", z .. "PastMax") } }), z .. "Random"),
			Switch(z) and Switch(z .. "Random"))
		steps = { S("together", { steps = { S("turnTo", { to = "front", secs = 14 }),
				On(Set(S("zoom", { to = close, secs = 9 }), z, "cozyZoomClose"), Switch(z)) } }),
			S("together", { steps = { loop, drifts } }) }
	else
		steps = { S("turnTo", { to = "behind", secs = 8 }), S("together", { steps = { loop, ZoomGroup(z) } }) }
	end
	local dof = "dof" .. cam:sub(1, 1):upper() .. cam:sub(2)
	return {
		steps = steps,
		ending = { On(Set(S("zoom", { to = 0, secs = 2, of = "yours" }), z), Switch(z)) },
		rules = { camera = "pause", cameraSecs = Db(cam .. "InputPause", 2), fight = "stop", walk = "putback",
			zoom = "ignore", ends = "putback" },
		haze = Db(dof, 0),
		ruleSet = { camera = { cam .. "InputPause" }, haze = { dof } },
	}
end

-- The RP walk and auto-run cameras (walkOrbit, runOrbit): line up behind
-- you with camera follow, then glide back behind you after each turn of
-- yours (Follow, after <cam>GlideDelay; <cam>SwingBehind), swaying and
-- zooming meanwhile. Stopping: the zoom goes back. (Not the same yet:
-- auto-run steering lower and closer, and the walk camera handing over to
-- standing still.) The line-up is part of the sway (Camera.lua lines up only
-- as its orbit starts): with the sway off, it's off too.
function MovingCamera(cam)
	return {
		steps = { On(Set(S("turnTo", { to = "behind", secs = 5 }), cam .. "Orbit"), Switch(cam .. "Orbit")),
			On(Set(S("follow", { after = Db(cam .. "GlideDelay", 1.5) }), cam .. "SwingBehind", cam .. "GlideDelay"),
				Switch(cam .. "SwingBehind")),
			S("together", { steps = { SwayLoop(cam .. "Orbit", 0), ZoomGroup(cam .. "Zoom") } }) },
		ending = { On(Set(S("zoom", { to = 0, secs = 2, of = "yours" }), cam .. "Zoom"), Switch(cam .. "Zoom")) },
		rules = { camera = "pause", cameraSecs = Db(cam .. "InputPause", 2), fight = "stop", walk = "ignore", zoom = "ignore",
			ends = "putback" },
		haze = Db(cam == "run" and "dofRun" or "dofWalk", 0),
		ruleSet = { camera = { cam .. "InputPause" }, haze = { cam == "run" and "dofRun" or "dofWalk" } },
	}
end

-- The quest cam's and Chat Cam's When it ends (c: their setting prefix):
-- back out to your distance at <c>ZoomOutSpeed (0: it stays in), in
-- <c>ZoomMaxTime at most, while the turn and tilt go back.
local function ZoomOutEnding(c)
	local out = Db(c .. "ZoomOutSpeed", 0.5)
	return { S("together", { steps = {
		On(Set(S("zoom", { to = 0, of = "yours", secs = Db(c .. "ZoomMaxTime", 8), speed = math.max(0.25, out) }),
			c .. "ZoomOutSpeed", c .. "ZoomMaxTime"), out > 0),
		S("putback", { secs = 4, zoom = "no" }) } }) }
end

local BUILT_IN = {
	-- The AFK camera (Camera.lua's idleOrbit, "sweep" mode) with the standing-
	-- still zoom alongside, as their settings have them: a turn of Step degrees
	-- one way (picked as it starts, unless you set a way) at Speed degrees a
	-- second at most, then a pause of Pause seconds, creeping on at
	-- DriftSpeed meanwhile (Drift), round and round; and the slow zoom
	-- (ZoomGroup). Leaving, it turns back and zooms back to where it began.
	-- (Not the same yet: the real one's turn flows into its drift without the
	-- short gap between moves, and turns a little slower as it starts after a
	-- turn of yours.)
	{ id = "afk", name = "AFK camera", make = function()
		local step, speed, ease = Db("idleOrbitStep", 40), Db("idleOrbitSpeed", 6), Db("idleOrbitEase", 0.5)
		local pause = Db("idleOrbitPause", 20)
		local way = "once"
		if ns.db and not ns.db.idleOrbitRandomDir then way = ns.db.idleOrbitRight and "right" or "left" end
		local turn = Set(S("rotate", { deg = step, secs = step / math.max(0.5, speed * (1 - math.min(0.9, ease))), way = way,
			ease = NearestEase(ease) }), "idleOrbitStep", "idleOrbitSpeed", "idleOrbitEase", "idleOrbitRandomDir",
			"idleOrbitRight")
		local hold = Set(Switch("idleOrbitDrift")
			and S("rotate", { deg = math.max(1, Db("idleOrbitDriftSpeed", 1) * pause), secs = pause, way = way,
				ease = "steady" })
			or S("wait", { secs = pause }), "idleOrbitPause", "idleOrbitDrift", "idleOrbitDriftSpeed")
		local sweeps = On(Set(S("repeat", { times = 0, steps = { turn, hold } }), "idleOrbit"), Switch("idleOrbit"))
		return {
			steps = { S("together", { steps = { sweeps, ZoomGroup("idleZoom") } }) },
			ending = { S("putback", { secs = 4 }) },
			rules = { camera = "pause", cameraSecs = Db("idleInputPause", 15), fight = "putback", walk = "putback",
				zoom = "ignore", ends = "putback" },
			haze = Db("dofIdle", 0),
			ruleSet = { camera = { "idleInputPause" }, haze = { "dofIdle" } },
		}
	end },
	-- The vista, fish and cozy cameras (Camera.lua's vistaOrbit, fishOrbit and
	-- cozyOrbit, "back" mode) as their settings have them: see RestCamera.
	{ id = "vista", name = "Vista camera", make = function() return RestCamera("vista") end },
	{ id = "fish", name = "Fish camera", make = function() return RestCamera("fish") end },
	{ id = "cozy", name = "Cozy camera", make = function() return RestCamera("cozy") end },
	-- The tele camera (a Hearthstone or teleport cast): comes down teleLevel,
	-- swings round in front of you by teleArriveEarly before the cast ends
	-- while zooming in to teleZoomClose over the whole cast (teleZoom), then
	-- spins round you, speeding up by teleSpinAccel to teleSpinMax, until
	-- you're gone. Cancelled: it turns back (teleReturn) and zooms back over
	-- teleZoomBackTime. (Arriving, the real camera swings round behind you,
	-- teleBehind, shown with When it ends.)
	{ id = "tele", name = "Tele camera", make = function()
		-- (The turns one after another, beside the zoom over the whole cast: a Repeat once.)
		local turns = S("repeat", { times = 1, steps = {
			Set(S("tilt", { deg = Db("teleLevel", 15), secs = 1.5 }), "teleLevel"),
			Set(S("turnTo", { to = "front", secs = 6, fit = "cast" }), "teleArriveEarly"),
			Set(S("spin", { accel = Db("teleSpinAccel", 8), max = Db("teleSpinMax", 120), secs = 0, way = "random" }),
				"teleSpinAccel", "teleSpinMax") } })
		local zoom = On(Set(S("zoom", { to = Db("teleZoomClose", 4), secs = 8, fit = "cast" }), "teleZoom", "teleZoomClose"),
			Switch("teleZoom"))
		local back = math.max(0.5, Db("teleZoomBackTime", 0.5))
		return {
			steps = { S("until", { what = "cast", secs = 0, steps = { S("together", { steps = { turns, zoom } }) } }) },
			ending = { Switch("teleReturn") and Set(S("putback", { secs = back }), "teleReturn", "teleZoomBackTime", "teleBehind")
				or Set(S("zoom", { to = 0, secs = back, of = "yours" }), "teleReturn", "teleZoomBackTime", "teleBehind") },
			rules = { camera = "stop", fight = "putback", walk = "putback", zoom = "ignore", ends = "putback" },
		}
	end },
	-- The flight camera (taxiOrbit, "back" mode): round behind you at takeoff
	-- (taxiCenter), swaying and zooming until it's time to settle (taxiSettle,
	-- on a route flown before: taxiSettleLead before landing, with time for
	-- the zoom and the turn), then the zoom back and the turn back behind you.
	-- Landing, the zoom goes back to your distance (taxiLandZoom). With
	-- taxiFlyBy, a fly-by (the Fly-by camera, played) each taxiFlyByEvery
	-- seconds of it. (Not the same yet: the fly-bys come at even times, not
	-- at random ones kept clear of takeoff and landing, taxiFlyByFrom/To; and
	-- the sway's tracking of the flight's turns.)
	{ id = "flight", name = "Flight camera", make = function()
		local settle = Switch("taxiSettle")
		local cruise = S("together", { steps = { SwayLoop("taxiOrbit", 0), ZoomGroup("taxiZoom") } })
		if Switch("taxiFlyBy") then
			cruise = S("repeat", { times = 0, steps = {
				Set(S("until", { what = "time", secs = Db("taxiFlyByEvery", 60), steps = { cruise } }), "taxiFlyByEvery"),
				Set(S("play", { script = "flyby" }), "taxiFlyBy") } })
		else
			Set(cruise, "taxiFlyBy")
		end
		return {
			steps = { On(Set(S("turnTo", { to = "behind", secs = 5 }), "taxiCenter"), Switch("taxiCenter")),
				Set(S("until", { what = "landing", secs = settle and Db("taxiSettleLead", 5) + 12 + 3 or 0, steps = {
					cruise } }), "taxiSettle", "taxiSettleLead"),
				On(Set(S("zoom", { to = 0, secs = 3, of = "yours" }), "taxiSettle"), settle),
				On(Set(S("lineup", { secs = 12 }), "taxiSettle"), settle) },
			ending = { On(Set(S("zoom", { to = 0, secs = 3, of = "yours" }), "taxiLandZoom"), Switch("taxiLandZoom")) },
			rules = { camera = "pause", cameraSecs = Db("taxiInputPause", 15), fight = "stop", walk = "ignore", zoom = "ignore",
				ends = "putback" },
			haze = Db("dofFlight", 0),
			ruleSet = { camera = { "taxiInputPause" }, haze = { "dofFlight" } },
		}
	end },
	{ id = "walk", name = "RP walk camera", make = function() return MovingCamera("walk") end },
	{ id = "run", name = "Auto-run camera", make = function() return MovingCamera("run") end },
	-- The death camera: after deathOrbitDelay, up deathLevel to look down on
	-- you while pulling back deathZoom, then a steady turn round you at
	-- deathOrbitSpeed until you release or are brought back. A Stop button
	-- meanwhile with deathExitButton.
	{ id = "death", name = "Death camera", make = function()
		local way = "left"
		if ns.db and ns.db.deathOrbitRandomDir then way = "random" elseif ns.db and ns.db.deathOrbitRight then way = "right" end
		return {
			steps = { Set(S("wait", { secs = Db("deathOrbitDelay", 0) }), "deathOrbitDelay"),
				S("together", { steps = { Set(S("tilt", { deg = -Db("deathLevel", 30), secs = 6 }), "deathLevel"),
					Set(S("zoom", { to = Db("deathZoom", 4), secs = 8, of = "yours" }), "deathZoom") } }),
				Set(S("spin", { accel = 2, max = Db("deathOrbitSpeed", 5), secs = 0, way = way }), "deathOrbitSpeed",
					"deathOrbitRandomDir", "deathOrbitRight") },
			ending = { S("putback", { secs = 2 }) },
			rules = { camera = "pause", cameraSecs = 5, fight = "ignore", walk = "ignore", zoom = "ignore", ends = "putback" },
			button = Switch("deathExitButton"),
			ruleSet = { button = { "deathExitButton" } },
		}
	end },
	-- A fly-by (the flight camera's): a /look as it starts (flyByLook), round
	-- flyByAngle from behind you over flyByTurnTime, looking back flyByHold,
	-- then back behind you over flyByBackTime.
	{ id = "flyby", name = "Fly-by", make = function()
		return {
			steps = { On(Set(S("emote", { token = "look" }), "flyByLook"), Switch("flyByLook")),
				S("wait", { secs = 1 }), S("lineup", { secs = 1.5 }),
				Set(S("rotate", { deg = Db("flyByAngle", 160), secs = Db("flyByTurnTime", 8), way = "random" }), "flyByAngle",
					"flyByTurnTime"),
				Set(S("wait", { secs = Db("flyByHold", 5) }), "flyByHold"),
				Set(S("lineup", { secs = Db("flyByBackTime", 6) }), "flyByBackTime") },
			ending = {},
			rules = { camera = "stop", fight = "stop", walk = "stop", zoom = "ignore", ends = "stop" },
		}
	end },
	-- Skyriding (retail, the dev copy's Skyriding Cam page, SkyrideCam.lua):
	-- out to skyrideCamDistance over skyrideCamZoomTime as you take to the
	-- air, back over skyrideCamBackTime once you've landed. (Steering doesn't
	-- stop it, nor walking: see Start's travel.)
	{ id = "skyride", name = "Skyriding zoom", retail = true, make = function()
		return {
			steps = { Set(S("zoom", { to = Db("skyrideCamDistance", 39), secs = Db("skyrideCamZoomTime", 3),
				past = "yes" }), "skyrideCamDistance", "skyrideCamZoomTime") },
			ending = { Set(S("putback", { secs = Db("skyrideCamBackTime", 2.5) }), "skyrideCamBackTime") },
			rules = { camera = "pause", cameraSecs = 3, fight = "putback", walk = "ignore", zoom = "ignore",
				ends = "putback" },
		}
	end },
	-- The quest cam (once its row's wait is over: QuestCam.lua's
	-- ns.QuestTalkNow): in to questCamDistance while
	-- camera follow swings it behind you over questCamTime, then questCamAngle
	-- round to the side over questCamTurnTime (questCamSide: where you clicked
	-- them, at random, or always one way), down questCamLower, then a slow
	-- drift to and fro of questCamDrift about there. The zooms go at
	-- questCamZoomSpeed and questCamZoomOutSpeed (0: it stays in), taking
	-- questCamZoomMaxTime at most. Leaving, it all goes back. (Not the same
	-- yet: the zoom back out waits till you walk off, and only if no other
	-- quest giver's near.)
	{ id = "quest", name = "Quest camera", make = function()
		local side, angle = ns.db and ns.db.questCamSide or "click", Db("questCamAngle", 30)
		local turn
		if side == "click" then
			turn = S("aim", { at = "click", deg = angle, secs = Db("questCamTurnTime", 4), miss = "random", ease = "gentle" })
		else
			-- (The quest cam's "left" turns the view right: QuestCam.lua's Command.)
			turn = S("rotate", { deg = math.max(1, angle), secs = Db("questCamTurnTime", 4),
				way = side == "random" and "random" or side == "left" and "right" or "left", ease = "gentle" })
		end
		local drift = Db("questCamDrift", 4)
		return {
			steps = { S("together", { steps = {
					Set(S("zoom", { to = Db("questCamDistance", 4), secs = Db("questCamZoomMaxTime", 8),
						speed = Db("questCamZoomSpeed", 0.5) }), "questCamDistance", "questCamZoomSpeed", "questCamZoomMaxTime"),
					Set(S("turnTo", { to = "behind", secs = Db("questCamTime", 3) }), "questCamTime") } }),
				On(Set(turn, "questCamAngle", "questCamTurnTime", "questCamSide"), angle > 0),
				Set(S("tilt", { deg = Db("questCamLower", 0), secs = 2 }), "questCamLower"),
				On(Set(S("repeat", { times = 0, steps = {
					S("rotate", { deg = math.max(1, drift), secs = 7, way = "left", ease = "gentle" }),
					S("rotate", { deg = math.max(1, drift), secs = 7, way = "right", ease = "gentle" }) } }), "questCamDrift"),
					drift > 0) },
			ending = ZoomOutEnding("questCam"),
			rules = { camera = "stop", fight = "putback", walk = "putback", zoom = "stop", ends = "putback" },
		}
	end },
	-- Chat Cam: in to chatCamDistance while swinging toward whoever's talking
	-- (chatCamFrame off the middle, by their bubble), then holding there,
	-- drifting chatCamDrift to and fro, until someone else talks, and
	-- swinging to them (chatCamSwingSpeed at most; chatCamSearch: looking
	-- round for one off screen). Over (chatCamQuiet with no one talking): it
	-- all goes back. (Not the same yet: no keeping up with one walking off, no
	-- learning how far a swing moves them.)
	{ id = "chat", name = "Chat camera", make = function()
		local function Aim()
			return Set(S("aim", { at = "speaker", deg = Db("chatCamFrame", 6), secs = 3, speed = Db("chatCamSwingSpeed", 15),
				miss = ns.db and ns.db.chatCamSearch == false and "stay" or "look" }), "chatCamFrame", "chatCamSwingSpeed",
				"chatCamSearch")
		end
		local drift = Db("chatCamDrift", 0)
		local hold = On(Set(S("repeat", { times = 0, steps = {
			S("rotate", { deg = math.max(1, drift), secs = 7, way = "left", ease = "gentle" }),
			S("rotate", { deg = math.max(1, drift), secs = 7, way = "right", ease = "gentle" }) } }), "chatCamDrift"), drift > 0)
		return {
			steps = { S("together", { steps = { Set(S("zoom", { to = Db("chatCamDistance", 4),
				secs = Db("chatCamZoomMaxTime", 8), speed = Db("chatCamZoomSpeed", 0.5) }), "chatCamDistance",
				"chatCamZoomSpeed", "chatCamZoomMaxTime"), Aim() } }),
				S("repeat", { times = 0, steps = { S("until", { what = "talk", secs = 0, steps = { hold } }), Aim() } }) },
			ending = ZoomOutEnding("chatCam"),
			rules = { camera = "stop", fight = "putback", walk = "stop", zoom = "stop", ends = "putback" },
		}
	end },
}

-- Your first script, there to start from (and change): a slow orbit, added
-- to yours the first time they're looked at (seeded: not again, even if you
-- delete it).
local function Example()
	return {
		name = L["Slow orbit"],
		steps = { S("wait", { secs = 1 }),
			S("together", { steps = { S("rotate", { deg = 360, secs = 40, ease = "steady" }),
				S("zoom", { to = 6, secs = 12 }) } }),
			S("wait", { secs = 2 }) },
		ending = { S("putback", { secs = 3 }) },
		rules = { camera = "pause", cameraSecs = 5, fight = "putback", walk = "putback", zoom = "ignore",
			ends = "putback" },
	}
end
-- (Skyriding's only where there's skyriding: retail; and in the dev copy only for now.)
if not (ns.isDev and ns.isRetail and C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then
	for i = #BUILT_IN, 1, -1 do
		if BUILT_IN[i].retail then table.remove(BUILT_IN, i) end
	end
end
ns.OnLanguage(function()
	for _, each in ipairs(BUILT_IN) do each.name = L[each.name] end
end)

local function Store()
	local db = ns.db or (ns.GetDB and ns.GetDB())
	if not db then return nil end
	if type(db.cameraScripts) ~= "table" then db.cameraScripts = {} end
	local store = db.cameraScripts
	if type(store.list) ~= "table" then store.list = {} end
	store.nextId = tonumber(store.nextId) or 1
	if not store.seeded then
		store.seeded = true
		local script = ns.CleanCameraScript(Example(), "u" .. store.nextId)
		store.nextId = store.nextId + 1
		table.insert(store.list, 1, script)
	end
	return store
end

-- A built-in camera's stop rules you changed on its page ({ [id] = { [rule
-- or rule.."Secs"] = value } }): they count when its script runs (Run, or a
-- row set to it), not for the camera's own code.
local function RuleEdits(id)
	local store = Store()
	if not store then return nil end
	if type(store.ruleEdits) ~= "table" then store.ruleEdits = {} end
	if id and type(store.ruleEdits[id]) ~= "table" then store.ruleEdits[id] = {} end
	return id and store.ruleEdits[id] or store.ruleEdits
end
local function WithRuleEdits(made, id)
	local edits = RuleEdits(id)
	if edits and next(edits) then
		for key, value in pairs(edits) do made.rules[key] = value end
	end
	return made
end
-- Sets one (key: a rule, or rule.."Secs"); back to the built-in's own drops it.
function ns.SetBuiltinCameraRule(id, key, value)
	for _, each in ipairs(BUILT_IN) do
		if each.id == id then
			local edits = RuleEdits(id)
			if not edits then return end
			local own = ns.CleanCameraScript(each.make(), id, true).rules[key]
			if value == own then edits[key] = nil else edits[key] = value end
			return
		end
	end
end

-- A built-in camera's script you changed ({ [id] = script }): plain numbers
-- from then on, not its settings, until Reset (ns.ResetBuiltinCameraScript).
local function BuiltinEdits()
	local store = Store()
	if not store then return nil end
	if type(store.builtinEdits) ~= "table" then store.builtinEdits = {} end
	return store.builtinEdits
end
-- Keeps script (a built-in one, just changed) as yours of it; gives the one kept.
function ns.EditBuiltinCameraScript(script)
	local edits = BuiltinEdits()
	if not edits then return script end
	local kept = ns.CleanCameraScript(script, script.id)
	kept.icon, kept.desc = nil, nil
	edits[script.id] = kept
	return ns.FindCameraScript(script.id) or kept
end
function ns.ResetBuiltinCameraScript(id)
	local edits = BuiltinEdits()
	if edits then edits[id] = nil end
	local rules = RuleEdits()
	if rules then rules[id] = nil end
end

-- Every script: the built-in ones (builtin = true; edited: yours of it) then
-- yours, in order.
function ns.CameraScripts()
	local list = {}
	local edits = BuiltinEdits() or {}
	for _, each in ipairs(BUILT_IN) do
		local script = edits[each.id]
		if type(script) == "table" then
			script.edited = true -- (the table kept: the page changes it as it does yours)
		else
			script = ns.CleanCameraScript(WithRuleEdits(each.make(), each.id), each.id, true)
		end
		script.name, script.builtin = each.name, true
		list[#list + 1] = script
	end
	local store = Store()
	for _, script in ipairs(store and store.list or {}) do
		if type(script) == "table" and script.id then list[#list + 1] = script end
	end
	return list
end

-- The settings a built-in camera's script is made from (its steps' and
-- stop rules', switched off or not), as a set of keys; nil for none.
function ns.CameraScriptSettingKeys(id)
	for _, each in ipairs(BUILT_IN) do
		if each.id == id then
			local script, keys, any = each.make(), {}, false
			local function Walk(list)
				for _, step in ipairs(list or {}) do
					for _, key in ipairs(step.set or {}) do keys[key], any = true, true end
					Walk(step.steps)
				end
			end
			Walk(script.steps)
			Walk(script.ending)
			for _, set in pairs(script.ruleSet or {}) do
				for _, key in ipairs(set) do keys[key], any = true, true end
			end
			return any and keys or nil
		end
	end
end

-- My Shots (Shots.lua) is retired where scripts are: a copy of a camera's
-- script with your own numbers does what a shot did, and more. Its page and
-- New shot... go; rows already set to a shot still run it.
ns.SHOTS_RETIRED = true

-- The Camera Settings page's sections (Options.lua's CameraSection keys) and
-- the scripts of the cameras each is for: the settings those scripts are made
-- from are left out of it (on their script pages instead).
local SECTION_SCRIPTS = { ["AFK Cam"] = { "afk" }, ["Flight Cam"] = { "flight", "flyby" },
	["Auto-run Cam"] = { "run" }, ["Cozy Cam"] = { "cozy" }, ["Vista Cam"] = { "vista" }, ["Fish Cam"] = { "fish" },
	["RP Walk Cam"] = { "walk" }, ["Death Cam"] = { "death" }, ["Chat Cam"] = { "chat" }, ["Quest Cam"] = { "quest" },
	["Tele Cam"] = { "tele" } }
function ns.CameraSectionMoved(section)
	local keys
	for _, id in ipairs(SECTION_SCRIPTS[section] or {}) do
		for key in pairs(ns.CameraScriptSettingKeys(id) or {}) do
			keys = keys or {}
			keys[key] = true
		end
	end
	return keys
end

function ns.FindCameraScript(id)
	for _, script in ipairs(ns.CameraScripts()) do
		if script.id == id then return script end
	end
end

-- Yours (the table saved), or nil for a built-in one.
local function Mine(id)
	local store = Store()
	for i, script in ipairs(store and store.list or {}) do
		if script.id == id then return script, i end
	end
end
ns.MyCameraScript = Mine

-- A new script of yours: a copy of from (any script), or a few steps to start
-- with. Gives it, or nil with all MAX_SCRIPTS made.
function ns.AddCameraScript(from, name)
	local store = Store()
	if not store or #store.list >= MAX_SCRIPTS then return nil end
	local id = "u" .. store.nextId
	store.nextId = store.nextId + 1
	local script = ns.CleanCameraScript(from or {
		steps = { S("wait", { secs = 1 }), S("rotate", { deg = 90, secs = 8 }), S("wait", { secs = 2 }) },
		ending = { S("putback", { secs = 3 }) },
	}, id)
	script.name = CleanName(name) or (from and L["%s (copy)"]:format(from.name):sub(1, 40)) or L["My camera"]
	store.list[#store.list + 1] = script
	ns.SyncScriptCameras()
	return script
end

-- Deletes one of yours; rows of this profile set to it go back to no camera.
function ns.DeleteCameraScript(id)
	local _, at = Mine(id)
	if not at then return end
	table.remove(Store().list, at)
	local value = "script:" .. id
	for _, row in ipairs(ns.CameraRowOrder()) do
		if ns.CameraRowValue(row, "camera") == value then
			ns.SetCameraRowValue(row, "camera", ns.CameraRowTrigger(row).off)
		end
	end
	ns.CameraRowsChanged()
	ns.SyncScriptCameras()
end

-- A script's settings changed (its name, or a step): the Cameras page's
-- names follow.
function ns.CameraScriptChanged()
	ns.SyncScriptCameras()
end

-- ---------------------------------------------------------------------------
-- Scripts as cameras on the Cameras page
-- ---------------------------------------------------------------------------

function ns.IsScriptCamera(value)
	return type(value) == "string" and value:sub(1, 7) == "script:"
end
local IsScript = ns.IsScriptCamera

-- Dev copy, for bringing the scripts up to our cameras: with db.scriptBuiltIns
-- on (/cine script builtins), a row set to one of our cameras runs that
-- camera's script instead (CameraRows.lua's ns.TriggerSetting asks), so each
-- can be compared in game with the camera's own code. The Scenes page still
-- shows the camera.
local BUILT_IN_OF = { cozy = "cozy", vista = "vista", fish = "fish", afk = "afk", tele = "tele", flight = "flight",
	walk = "walk", run = "run", quest = "quest", chat = "chat", [true] = "death", death = "death" }
function ns.ScriptBuiltInsOn()
	return ns.isDev and ns.db ~= nil and ns.db.scriptBuiltIns == true
end
function ns.BuiltInAsScript(value)
	local id = BUILT_IN_OF[value]
	return id and "script:" .. id or value
end

-- The triggers whose rows may pick a script: those with a standing-still
-- camera (theirs or your own triggers'), a Hearthstone or teleport's, a
-- flight's, walking, running, death, a quest giver's or chat's.
local TAKES = { afk = true, tele = true, flight = true, walk = true, run = true, quest = true, chat = true,
	[true] = true }
local function TakesScripts(list)
	for _, value in ipairs(list) do
		if TAKES[value] then return true end
	end
	return false
end
function ns.TriggerTakesScripts(trigger)
	return type(trigger.cameras) == "table" and TakesScripts(trigger.cameras)
end

-- Puts every script in those triggers' camera lists (before "none") and
-- its name in ns.CAMERA_NAMES. (The lists are shared between triggers: each
-- done once.)
function ns.SyncScriptCameras()
	if not ns.CAMERA_TRIGGERS or not ns.CAMERA_NAMES then return end
	for value in pairs(ns.CAMERA_NAMES) do
		if IsScript(value) then ns.CAMERA_NAMES[value] = nil end
	end
	local values = {}
	for _, script in ipairs(ns.CameraScripts()) do
		local value = "script:" .. script.id
		values[#values + 1] = value
		ns.CAMERA_NAMES[value] = L["Script: %s"]:format(script.name)
	end
	-- (Your own scenes' Camera menu too, before any scene of yours uses it.)
	local lists = { ns.CUSTOM_TRIGGER_CAMERAS }
	for _, trigger in ipairs(ns.CAMERA_TRIGGERS) do lists[#lists + 1] = trigger.cameras end
	local done = {}
	for _, list in pairs(lists) do
		if type(list) == "table" and not done[list] and TakesScripts(list) then
			done[list] = true
			for i = #list, 1, -1 do
				if IsScript(list[i]) then table.remove(list, i) end
			end
			local at = #list + 1
			for i, value in ipairs(list) do
				if value == "none" then at = i break end
			end
			for i, value in ipairs(values) do table.insert(list, at + i - 1, value) end
		end
	end
end
-- (A trigger added later, one of your own say: its list too.)
if ns.RegisterCameraTrigger then
	hooksecurefunc(ns, "RegisterCameraTrigger", function() ns.SyncScriptCameras() end)
end

-- A trigger's name, as the Cameras page shows it.
function ns.CameraTriggerName(key)
	local trigger = ns.CAMERA_TRIGGER and ns.CAMERA_TRIGGER[key]
	if not trigger then return tostring(key) end
	if trigger.custom and ns.CustomTriggerLabel then return ns.CustomTriggerLabel(key) end
	if key == "Skyride" then return L["Skyriding Cam"] end
	for _, event in ipairs(ns.EVENTS or {}) do
		if event.key == key then return event.label end
	end
	return key
end

-- The Cameras page rows set to a script: their trigger keys, each once.
function ns.CameraScriptTriggers(id)
	local value, keys, seen = "script:" .. id, {}, {}
	for _, row in ipairs(ns.CameraRowOrder()) do
		local trigger = ns.CameraRowTrigger(row)
		if trigger and not seen[trigger.key] and ns.CameraRowValue(row, "camera") == value then
			seen[trigger.key] = true
			keys[#keys + 1] = trigger.key
		end
	end
	return keys
end

-- ---------------------------------------------------------------------------
-- The plan: a script laid out in time, for the preview (no camera moves)
-- ---------------------------------------------------------------------------

local function Wrap(angle)
	return (angle + 180) % 360 - 180
end

-- Share (0-1) of a move covered at t along T seconds, with ease*T ramps at
-- either end (as QuestCam.lua's EaseProgress).
local function EaseProgress(t, T, ease)
	if t <= 0 then return 0 end
	if t >= T then return 1 end
	local R = ease * T
	if R <= 0 then return t / T end
	local function ramp(u) return u / 2 - R / (2 * math.pi) * math.sin(math.pi * u / R) end
	local covered
	if t < R then
		covered = ramp(t)
	elseif t <= T - R then
		covered = R / 2 + (t - R)
	else
		covered = (T - R) - ramp(T - t)
	end
	return covered / (T - R)
end
ns.CameraScriptEase = EaseProgress

-- A turn's way: left or right (random: picked now; once: the script's own
-- pick, onceLeft).
local function Way(step, random, onceLeft)
	if step.way == "random" then return random() < 0.5 and "left" or "right" end
	if step.way == "once" then return onceLeft and "left" or "right" end
	return step.way
end
-- A zoom's goal in yards from you: its yards, or (of "yours") that many from
-- the distance the script started at; never closer than half a yard.
-- Speed (0-1) at t along a move of T seconds: half-cosine ramps of ease*T at
-- either end (as Camera.lua's).
local function EaseShape(t, T, ease)
	local R = ease * T
	if R <= 0 then
		return 1
	elseif t < R then
		return (1 - math.cos(math.pi * t / R)) / 2
	elseif t > T - R then
		return (1 - math.cos(math.pi * (T - t) / R)) / 2
	end
	return 1
end

-- How far a speed curve goes in T seconds (degrees).
local function CurveDistance(curve, T)
	local sum, dt = 0, 0.05
	for t = dt / 2, T, dt do sum = sum + curve(t) * dt end
	return sum
end

-- A sway's turn from amount: a random spot within its arc of the middle
-- (behind 0, in front 180), at least min from where it is, the shorter way
-- (as Camera.lua's PickBackTarget, and the vista and fish cameras' leaning
-- toward the middle with favor). random: math.random or the plan's own.
local function SwayTurn(step, amount, random)
	local center = step.around == "front" and 180 or 0
	local arc, min = step.arc, step.min
	local here = Wrap(amount - center)
	local lowEnd, highStart = math.min(here - min, arc), math.max(here + min, -arc)
	local lowLength, highLength = math.max(0, lowEnd + arc), math.max(0, arc - highStart)
	local target
	if lowLength + highLength <= 0 then
		target = here >= 0 and -arc or arc
	else
		local r = random() * (lowLength + highLength)
		target = r < lowLength and -arc + r or highStart + (r - lowLength)
	end
	if step.favor == "yes" and arc > 0 then target = target * (0.4 + 0.6 * math.abs(target) / arc) end
	return Wrap(center + target - amount)
end

-- A sway with a drift: one speed curve for the turn and the creep after it
-- (the turn slows to the drift's speed rather than stopping; the drift eases
-- to a stop before the arc's edge). Gives the curve, its seconds, its top
-- speed, and the still time left of the pause; nil without a drift.
local DRIFT_STOP = 1.5 -- seconds a drift takes to ease to a stop
local function SwayCurve(step, delta, from)
	local v, P = step.drift, step.pause
	if v <= 0 or P <= 0 or math.abs(delta) < 0.5 then return nil end
	local T, e = step.secs, EASES[step.ease]
	local c = math.abs(delta) / (T * (1 - e))
	local R = e * T
	local dir = delta >= 0 and 1 or -1
	local center = step.around == "front" and 180 or 0
	-- (Room to the edge of the arc, the way it's going, after the turn.)
	local room = step.arc - dir * Wrap(from + delta - center)
	room = math.max(0, room - v * R / 2)
	local stopT = math.min(DRIFT_STOP, P)
	local driftT = math.max(0, math.min(P - stopT, room / v - stopT / 2))
	local function curve(t)
		if t < T - R then return c * EaseShape(t, T, e) end
		if t < T then return v + (c - v) * EaseShape(t, T, e) end
		if t < T + driftT then return v end
		return v * (1 + math.cos(math.pi * math.min(1, (t - T - driftT) / stopT))) / 2
	end
	return curve, T + driftT + stopT, math.max(c, v), math.max(0, P - driftT - stopT)
end

local function SpinCurve(step)
	local accel, top = step.accel, step.max
	return function(t) return math.min(top, accel * t) end
end

local function ZoomGoal(step, yards, startZoom)
	if step.of == "yours" then yards = startZoom + yards end
	return math.max(0.5, math.min(50, yards))
end
-- A zoom's seconds from distance yards: its own, or (speed) shorter if its
-- top speed gets there sooner.
local function ZoomSecs(step, secs, distance)
	if step.speed <= 0 then return secs end
	return math.min(secs, math.abs(distance) / (step.speed * (1 - EASES[step.ease])))
end
-- An Aim at's seconds for a turn: its own, or (speed) longer if the turn
-- would go faster than that.
local function AimSecs(step, turn)
	if step.speed <= 0 then return step.secs end
	return math.max(step.secs, math.abs(turn) / (step.speed * (1 - EASES[step.ease])))
end

-- Aim at a speaker (as ChatCam.lua's swing): the camera turns round you, not
-- on the spot, so a speaker moves across the screen about AIM_GAIN degrees
-- for each degree it turns; a swing goes AIM_MOST at most, and the camera
-- no more than AIM_MOST from where the script started.
local AIM_GAIN, AIM_MOST = 0.35, 30
local AIM_WAIT = 2 -- seconds a speaker's bubble is waited for
local heard = { at = -math.huge } -- the last line an NPC said: text, name, at (see TriggerNow)

-- { moves = { axis, from, to, t0, t1, ease, top }, spans = { step, t0, t1 },
-- endStart, total }. Repeat-until-it-ends goes three times. start: { yaw,
-- pitch, zoom } as it begins.
local PREVIEW_REPEATS = 3
local PREVIEW_UNTIL = { cast = 10, landing = 90, alive = 40, talk = 8 } -- (seconds a Wait until stands in for)
local PREVIEW_SPEAKER = 10 -- degrees off the middle the preview's speaker stands (Aim at a speaker)
function ns.PlanCameraScript(script, start)
	local moves, spans = {}, {}
	local seed = 7
	local function Random()
		seed = (seed * 9301 + 49297) % 233280
		return seed / 233280
	end
	local state = { yaw = start.yaw, pitch = start.pitch, zoom = start.zoom }
	local onceLeft = Random() < 0.5
	local busyUntil = { yaw = 0, pitch = 0 } -- (a turn and a tilt one at a time)
	local plays = 0 -- (Play steps inside each other)
	local One
	local function Run(list, t, top)
		for _, step in ipairs(list) do t = One(step, t, top or step) end
		return t
	end
	local function Move(axis, to, t, secs, ease, top)
		if axis == "yaw" or axis == "pitch" then
			local other = axis == "yaw" and "pitch" or "yaw"
			if busyUntil[other] > t then t = busyUntil[other] + STEP_GAP end
		end
		secs = math.max(MOVE_MIN_TIME, secs or 0)
		moves[#moves + 1] = { axis = axis, from = state[axis], to = to, t0 = t, t1 = t + secs, ease = ease, top = top }
		state[axis] = to
		if busyUntil[axis] then busyUntil[axis] = t + secs end
		return t + secs
	end
	local function Hold(t, secs, top)
		moves[#moves + 1] = { axis = "none", t0 = t, t1 = t + secs, top = top }
		return t + secs
	end
	-- (A turn along a speed curve: where it is at each moment is worked out as it's drawn.)
	local function Curve(growing, curve, t, secs, top)
		if busyUntil.pitch > t then t = busyUntil.pitch + STEP_GAP end
		local dist = CurveDistance(curve, secs)
		moves[#moves + 1] = { axis = "yaw", from = state.yaw, to = state.yaw + (growing and dist or -dist), t0 = t,
			t1 = t + secs, curve = curve, sign = growing and 1 or -1, top = top }
		state.yaw = state.yaw + (growing and dist or -dist)
		busyUntil.yaw = t + secs
		return t + secs
	end
	function One(step, t, top)
		local from, ending = t, t
		local k = not step.off and step.k
		if k == "rotate" then
			local way = Way(step, Random, onceLeft)
			ending = Move("yaw", state.yaw + (way == "left" and step.deg or -step.deg), t, step.secs, EASES[step.ease], top)
		elseif k == "tilt" then
			ending = step.deg ~= 0 and Move("pitch", state.pitch + step.deg, t, step.secs, 0.5, top) or t
		elseif k == "zoom" or k == "zoomRand" then
			local goal
			if k == "zoom" then
				goal = ZoomGoal(step, step.to, start.zoom)
			else
				local low, high = math.min(step.min, step.max), math.max(step.min, step.max)
				goal = ZoomGoal(step, low + Random() * (high - low), start.zoom)
			end
			ending = Move("zoom", goal, t, ZoomSecs(step, step.secs, goal - state.zoom), EASES[step.ease], top)
		elseif k == "turnTo" then
			local center = step.to == "front" and 180 or 0
			ending = Move("yaw", state.yaw - Wrap(state.yaw - center), t, step.secs, 0.5, top)
		elseif k == "sway" then
			local delta = SwayTurn(step, state.yaw, Random)
			local curve, secs, _, still = SwayCurve(step, delta, state.yaw)
			if curve then
				ending = Curve(delta >= 0, curve, t, secs, top)
				if still > 0 then ending = Hold(ending, still, top) end
			else
				ending = Move("yaw", state.yaw + delta, t, step.secs, EASES[step.ease], top)
				if step.pause > 0 then ending = Hold(ending, step.pause, top) end
			end
		elseif k == "tiltRand" then
			local target = step.deg - step.up + Random() * (step.up + step.down)
			ending = Move("pitch", target, t, step.secs, 0.5, top)
		elseif k == "spin" then
			local secs = step.secs > 0 and step.secs or 20
			ending = Curve(Way(step, Random, onceLeft) == "left", SpinCurve(step), t, secs, top)
		elseif k == "until" then
			-- (The preview can't know when a cast ends or you land: a stand-in time.)
			local secs = step.what == "time" and step.secs or PREVIEW_UNTIL[step.what] or 10
			if #step.steps > 0 then
				-- (Its steps run till then, cut off there: the part of them that fits.)
				local keep = #moves
				Run(step.steps, t, top)
				for i = #moves, keep + 1, -1 do
					local move = moves[i]
					if move.t0 >= t + secs then
						table.remove(moves, i)
					elseif move.t1 > t + secs and move.axis == "none" then
						move.t1 = t + secs
					elseif move.t1 > t + secs then
						if move.curve then
							move.to = move.from + move.sign * CurveDistance(move.curve, t + secs - move.t0)
						else
							move.to = move.from + (move.to - move.from) * EaseProgress(t + secs - move.t0, move.t1 - move.t0,
								move.ease or 0.5)
						end
						move.t1, move.curve, move.ease = t + secs, nil, 0
					end
				end
				-- (Where everything is once they're cut off.)
				for _, axis in ipairs({ "yaw", "pitch", "zoom" }) do
					for i = #moves, keep + 1, -1 do
						if moves[i].axis == axis then state[axis] = moves[i].to break end
					end
				end
				busyUntil.yaw, busyUntil.pitch = math.min(busyUntil.yaw, t + secs), math.min(busyUntil.pitch, t + secs)
			end
			ending = Hold(t, secs, top)
		elseif k == "waitRand" then
			local low, high = math.min(step.min, step.max), math.max(step.min, step.max)
			ending = Hold(t, low + Random() * (high - low), top)
		elseif k == "follow" then
			ending = t
		elseif k == "aim" then
			-- (Either side at random: the preview can't know where they are.)
			local turn = step.at == "click" and step.deg
				or math.min(AIM_MOST, math.max(0, PREVIEW_SPEAKER - step.deg) / AIM_GAIN)
			if Random() < 0.5 then turn = -turn end
			ending = math.abs(turn) >= 0.5 and Move("yaw", state.yaw + turn, t, AimSecs(step, turn), EASES[step.ease], top)
				or t
		elseif k == "lineup" then
			ending = Move("yaw", state.yaw - Wrap(state.yaw), t, step.secs, 0.5, top)
		elseif k == "putback" then
			local turned = Move("yaw", state.yaw - Wrap(state.yaw), t, step.secs, 0.5, top)
			if step.zoom == "yes" then Move("zoom", start.zoom, t, step.secs, EASES.gentle, top) end
			ending = math.max(turned, Move("pitch", start.pitch, turned, step.secs, 0.5, top))
		elseif k == "wait" then
			ending = Hold(t, step.secs, top)
		elseif k == "emote" then
			ending = Hold(t, 0.5, top)
		elseif k == "together" then
			for _, child in ipairs(step.steps) do ending = math.max(ending, One(child, t, top)) end
		elseif k == "play" then
			local played = plays < MAX_PLAYS and ns.FindCameraScript(step.script)
			if played then
				plays = plays + 1
				ending = Run(ns.CleanCameraScript(played, played.id, played.builtin).steps, t, top)
				plays = plays - 1
			end
		elseif k == "repeat" then
			for _ = 1, step.times > 0 and step.times or PREVIEW_REPEATS do
				local before = t
				t = Run(step.steps, t, top)
				if t == before then break end
			end
			ending = t
		end
		if top == step then spans[#spans + 1] = { step = step, t0 = from, t1 = ending } end
		return ending
	end
	local endStart = Run(script.steps, 0)
	local total = Run(script.ending, endStart)
	return { moves = moves, spans = spans, endStart = endStart, total = math.max(total, 1) }
end

-- Where the plan has the camera at t: yaw, pitch, zoom, and the top-level
-- step under way (nil between them).
function ns.SampleCameraPlan(plan, t, start)
	local yaw, pitch, zoom, active = start.yaw, start.pitch, start.zoom, nil
	for _, move in ipairs(plan.moves) do
		if move.t0 <= t then
			if t < move.t1 then active = move.top end
			if move.curve then
				yaw = move.from + move.sign * CurveDistance(move.curve, math.min(t, move.t1) - move.t0)
			elseif move.axis ~= "none" then
				local value = move.from + (move.to - move.from) * EaseProgress(t - move.t0, move.t1 - move.t0, move.ease or 0.5)
				if move.axis == "yaw" then yaw = value elseif move.axis == "pitch" then pitch = value else zoom = value end
			end
		end
	end
	return yaw, pitch, zoom, active
end

-- ---------------------------------------------------------------------------
-- The runner: moving the real camera
-- ---------------------------------------------------------------------------

local run -- the script running: see Start
local restoring = 0 -- speed settings still to come back (a moment after each move)

local function Send(name, amount)
	return ns.CameraCall(WHO, name, amount)
end

-- The turn and the tilt. amount: degrees counted from where the script
-- started (yaw: the view turned left; pitch: down).
local movers = {
	yaw = { name = "yaw", amount = 0, cvar = "cameraYawMoveSpeed", who = "script:yaw",
		grow = "MoveViewLeft", shrink = "MoveViewRight" },
	pitch = { name = "pitch", amount = 0, cvar = "cameraPitchMoveSpeed", who = "script:pitch",
		grow = "MoveViewDown", shrink = "MoveViewUp" },
}
movers.yaw.other, movers.pitch.other = movers.pitch, movers.yaw
local lastStop = -math.huge -- when a turn or tilt last stopped

local function Command(m)
	return m.growing and m.grow or m.shrink
end

local function StopMove(m)
	m.pending = false
	if not m.moving then return end
	if m.sent or m.creeping then Send(Command(m) .. "Stop") end
	m.moving, m.sent, m.creeping = false, nil, nil
	lastStop = GetTime()
	restoring = restoring + 1
	C_Timer.After(RESTORE_DELAY, function()
		restoring = restoring - 1
		if not m.moving then ns.ReleaseSpeed(m.who, m.cvar) end
	end)
end

-- Moves to target degrees over T seconds (it sets off once it can: see Begin).
local function MoveTo(m, target, T, ease)
	StopMove(m)
	m.suspended, m.curve = nil, nil
	m.target, m.t, m.T, m.ease = target, 0, math.max(MOVE_MIN_TIME, T or 0), ease or EASES.smooth
	m.pending = math.abs(target - m.amount) >= 0.5
end

-- A move along a speed curve instead: curve(t) degrees a second (top: its
-- fastest), growing or not, for T seconds; it goes as far as that takes it.
local function MoveCurve(m, growing, curve, T, top)
	StopMove(m)
	m.suspended = nil
	m.curve, m.top, m.curveGrowing, m.t, m.T = curve, math.max(0.05, top), growing, 0, T
	m.target = m.amount + (growing and 1 or -1) * 1e6 -- (never reached: the time ends it)
	m.pending = T > 0
end

-- Sets a pending move off: not with the other axis moving, nor within
-- STEP_GAP of a move stopping, nor without the view.
local function Begin(m)
	local now = GetTime()
	if m.other.moving or now - lastStop < STEP_GAP or not ns.ClaimCamera(WHO) then return end
	local yours = ns.HoldSpeed(m.who, m.cvar)
	if m.curve then
		m.share = m.top / yours
		m.growing = m.curveGrowing
	else
		m.cruise = math.abs(m.target - m.amount) / (m.T * (1 - m.ease))
		m.share = m.cruise / yours
		m.growing = m.target > m.amount
	end
	ns.SetHeldSpeed(m.who, m.cvar, MIN_SETTING)
	m.primedUntil = now + PRIME_TIME
	m.pending = false
	if Send(Command(m) .. "Start", PRIME_SHARE) then
		m.creeping, m.moving, m.sent, m.t = true, true, nil, 0
	else
		m.pending = true
		ns.ReleaseSpeed(m.who, m.cvar)
	end
end

local function StepMove(m, elapsed)
	if m.pending then
		Begin(m)
		return
	end
	if not m.moving or GetTime() < m.primedUntil then return end
	m.t = m.t + elapsed
	local speed
	if m.curve then
		if m.t >= m.T then
			StopMove(m)
			return
		end
		speed = math.max(0, m.curve(m.t))
	else
		if (m.target > m.amount) ~= m.growing or math.abs(m.target - m.amount) < 0.05 or m.t > m.T + 3 then
			StopMove(m)
			return
		end
		speed = math.max(MIN_SPEED, m.cruise * EaseShape(math.min(m.t, m.T), m.T, m.ease))
	end
	local setting = math.max(MIN_SETTING, speed / m.share)
	if not m.sent then
		Send(Command(m) .. "Start", m.share)
		m.sent = MIN_SETTING
	elseif math.abs(setting - m.sent) > m.sent * CHANGE then
		ns.SetHeldSpeed(m.who, m.cvar, setting)
		m.sent = setting
	end
	speed = m.sent * m.share
	m.amount = m.amount + (m.growing and speed or -speed) * elapsed
end

local function MoverDone(m)
	return not (m.pending or m.moving or m.suspended)
end

-- The zoom: steered along its eased path (as the quest cam's: the game
-- doesn't go exactly the distance asked, so commands toward where the path
-- will be shortly, from where the camera is; the zoom speed setting just
-- above the path's speed meanwhile, then eased back to yours).
local ZOOM_CVAR, ZOOM_WHO = "cameraZoomSpeed", "script:zoom"
local ZOOM_DONE, ZOOM_STILL, ZOOM_SETTLED, ZOOM_GIVE_UP = 0.05, 0.002, 0.4, 4
local ZOOM_SEND_EVERY, ZOOM_LEAD, ZOOM_GAIN = 0.1, 0.25, 0.6
local ZOOM_HEADROOM, ZOOM_EXTRA, ZOOM_MIN_SPEED, ZOOM_SETTLE_SPEED = 1.3, 0.3, 0.3, 0.5
local ZOOM_RELEASE_TIME = 1.5
local zoomer = { moving = false }

local function Zoom()
	return GetCameraZoom and GetCameraZoom() or 0
end

local function StopZoom()
	zoomer.pending = false
	if not zoomer.moving then return end
	zoomer.moving = false
	local yours = ns.SpeedHeld(ZOOM_CVAR, ZOOM_WHO) and ns.YourSpeed(ZOOM_CVAR)
	if yours and zoomer.sent and yours > zoomer.sent then
		zoomer.release = { from = zoomer.sent, to = yours, t = 0 }
	else
		zoomer.sent = nil
		ns.ReleaseSpeed(ZOOM_WHO, ZOOM_CVAR)
	end
end

-- (ease: the share of it spent speeding up and slowing down, gentle unless given.)
local function ZoomTo(distance, T, ease)
	StopZoom()
	zoomer.suspended = nil
	local now = Zoom()
	if math.abs(distance - now) < ZOOM_DONE then return end
	zoomer.goal, zoomer.T, zoomer.ease = distance, math.max(MOVE_MIN_TIME, T or 0), ease or EASES.gentle
	zoomer.pending = true
end

local function BeginZoom()
	if not ns.ClaimCamera(WHO, ns.zoomWhileSteering[WHO]) then return end
	local now = Zoom()
	zoomer.release, zoomer.yours = nil, nil
	ns.HoldSpeed(ZOOM_WHO, ZOOM_CVAR)
	zoomer.from, zoomer.t = now, 0
	zoomer.cruise = math.abs(zoomer.goal - now) / (zoomer.T * (1 - zoomer.ease))
	zoomer.last, zoomer.sentAt, zoomer.stillSince, zoomer.sent, zoomer.asked = now, 0, nil, nil, 0
	zoomer.pending, zoomer.moving = false, true
end

local function StepZoom(elapsed)
	if zoomer.pending then BeginZoom() end
	if not zoomer.moving then
		local release = zoomer.release
		if release then
			release.t = release.t + elapsed
			local f = release.t / ZOOM_RELEASE_TIME
			if f >= 1 or not ns.SpeedHeld(ZOOM_CVAR, ZOOM_WHO) then
				zoomer.release, zoomer.sent = nil, nil
				ns.ReleaseSpeed(ZOOM_WHO, ZOOM_CVAR)
			else
				ns.SetHeldSpeed(ZOOM_WHO, ZOOM_CVAR, release.from * (release.to / release.from) ^ (f * f))
			end
		end
		return
	end
	local now, zoom = GetTime(), Zoom()
	zoomer.t = zoomer.t + elapsed
	local t, T = zoomer.t, zoomer.T
	local still = math.abs(zoom - zoomer.last) < ZOOM_STILL
	zoomer.last = zoom
	if t >= T and math.abs(zoomer.goal - zoom) < ZOOM_DONE and still then
		zoomer.stillSince = zoomer.stillSince or now
		if now - zoomer.stillSince >= ZOOM_SETTLED then
			StopZoom()
			return
		end
	else
		zoomer.stillSince = nil
	end
	if t >= T + ZOOM_GIVE_UP then
		StopZoom()
		return
	end
	local speed = ZOOM_SETTLE_SPEED
	if t < T then
		speed = math.max(ZOOM_MIN_SPEED, zoomer.cruise * EaseShape(t, T, zoomer.ease) * ZOOM_HEADROOM + ZOOM_EXTRA)
	end
	if not zoomer.sent or math.abs(speed - zoomer.sent) > zoomer.sent * CHANGE then
		ns.SetHeldSpeed(ZOOM_WHO, ZOOM_CVAR, speed)
		zoomer.sent = speed
	end
	-- (Never asking past the path from where the commands sent already have
	-- it heading: they add up in the game.)
	if now - zoomer.sentAt >= ZOOM_SEND_EVERY then
		local point = zoomer.from + (zoomer.goal - zoomer.from) * EaseProgress(math.min(T, t + ZOOM_LEAD), T, zoomer.ease)
		local miss = point - zoom
		local ahead = point - (zoomer.from + zoomer.asked)
		local ask = (ahead > 0) == (miss > 0) and math.min(math.abs(miss) * ZOOM_GAIN, math.abs(ahead)) or 0
		if math.abs(miss) > ZOOM_DONE and ask > 0 then
			zoomer.sentAt = now
			Send(miss < 0 and "CameraZoomIn" or "CameraZoomOut", ask)
			zoomer.asked = zoomer.asked + (miss < 0 and -ask or ask)
		end
	end
end

local function ZoomDone()
	return not (zoomer.pending or zoomer.moving or zoomer.suspended)
end

-- You zoomed while ours zooms (or its speed eases back after). The game
-- takes your scroll at the speed set right then and keeps it going that
-- long: the speed raised back meanwhile ran a scroll taken at the crawl many
-- times too far (out to your max). So the speed stays where it is till the
-- camera's settled from your scrolling, then yours comes back (as the quest
-- cam does, QuestCam.lua's StopZoomForYou).
local YOUR_ZOOM_HOLD_MAX = 6 -- seconds at most the speed's held for your zoom
local function HoldForYourZoom()
	local held = ns.SpeedHeld(ZOOM_CVAR, ZOOM_WHO) and tonumber(GetCVar(ZOOM_CVAR))
	local yours = held and ns.YourSpeed(ZOOM_CVAR)
	zoomer.moving, zoomer.pending, zoomer.release = false, false, nil
	if not (held and yours and held < yours) then
		zoomer.sent = nil
		ns.ReleaseSpeed(ZOOM_WHO, ZOOM_CVAR)
		return
	end
	local zoom = Zoom()
	zoomer.yours = { last = zoom, at = GetTime(), still = 0 }
	ns.Log("state", ("camera script: you zoomed, its zoom speed held at %.2f till your zoom's done"):format(held))
end
local function StepYourZoom(elapsed)
	local yz = zoomer.yours
	if not yz then return end
	if not ns.SpeedHeld(ZOOM_CVAR, ZOOM_WHO) then -- (put back by something else)
		zoomer.yours = nil
		return
	end
	local now, zoom = GetTime(), Zoom()
	yz.still = math.abs(zoom - yz.last) < ZOOM_STILL and yz.still + elapsed or 0
	yz.last = zoom
	local lastScroll = ns.lastPlayerZoomAt or yz.at
	if (yz.still >= ZOOM_SETTLED and now - lastScroll >= ZOOM_SETTLED) or now - yz.at >= YOUR_ZOOM_HOLD_MAX then
		zoomer.yours, zoomer.sent = nil, nil
		ns.ReleaseSpeed(ZOOM_WHO, ZOOM_CVAR)
	end
end

-- Every move stopped where it is (nothing kept to carry on with).
local function StopAll()
	StopMove(movers.yaw)
	StopMove(movers.pitch)
	movers.yaw.suspended, movers.pitch.suspended = nil, nil
	StopZoom()
	zoomer.suspended = nil
end

-- Paused: each move stopped, what's left of it kept to carry on with.
local function Suspend()
	for _, m in pairs(movers) do
		if m.pending or m.moving then
			m.suspended = { target = m.target, T = math.max(MOVE_MIN_TIME, (m.T or 0) - (m.t or 0)), curve = m.curve,
				at = m.t or 0, total = m.T, top = m.top, growing = m.curveGrowing }
			StopMove(m)
		end
	end
	if zoomer.pending or zoomer.moving then
		zoomer.suspended = { goal = zoomer.goal, T = math.max(MOVE_MIN_TIME, zoomer.T - (zoomer.t or 0)), ease = zoomer.ease }
		StopZoom()
	end
end

local function Resume()
	for _, m in pairs(movers) do
		local left = m.suspended
		if left and left.curve then
			-- (On along its curve from where it was: the rest of it, eased in again over a second.)
			local at, curve = left.at, left.curve
			MoveCurve(m, left.growing, function(t) return curve(at + t) * math.min(1, t) end, left.total - at, left.top)
		elseif left then
			MoveTo(m, left.target, left.T, m.ease)
		end
	end
	local left = zoomer.suspended
	if left then ZoomTo(left.goal, left.T, left.ease) end
end

-- The steps, run in a coroutine: each yields a frame at a time until done.
local Yield = coroutine.yield
local function WaitSeconds(secs)
	local untilT = run.t + secs
	while run.t < untilT do Yield() end
end
local function WaitMover(m)
	while not MoverDone(m) do Yield() end
end
local function WaitZoom()
	while not ZoomDone() do Yield() end
end

local DoStep
local function DoSteps(list)
	for _, step in ipairs(list) do DoStep(step) end
end

local STEP = {}
function STEP.rotate(step)
	local way = Way(step, math.random, run.onceLeft)
	local m = movers.yaw
	MoveTo(m, m.amount + (way == "left" and step.deg or -step.deg), step.secs, EASES[step.ease])
	WaitMover(m)
end
function STEP.tilt(step)
	if step.deg == 0 then return end
	local m = movers.pitch
	MoveTo(m, m.amount + step.deg, step.secs, EASES.smooth)
	WaitMover(m)
end
-- A zoom to goal yards: over secs, or (speed) as quick as its top speed
-- goes, secs at most; the game's max distance raised first (past), not
-- indoors, where the camera would only bump into the walls.
local function ZoomStep(step, goal, secs)
	if step.past == "yes" and not (IsIndoors and IsIndoors()) and ns.RaiseZoomMax then
		ns.RaiseZoomMax()
		run.raisedMax = true
	end
	ZoomTo(goal, ZoomSecs(step, secs, goal - Zoom()), EASES[step.ease])
	WaitZoom()
end
function STEP.zoom(step)
	local secs = step.fit == "cast" and ns.DepartCastLeft and ns.DepartCastLeft() or step.secs
	ZoomStep(step, ZoomGoal(step, step.to, run.startZoom), secs)
end
function STEP.zoomRand(step)
	local low, high = math.min(step.min, step.max), math.max(step.min, step.max)
	ZoomStep(step, ZoomGoal(step, low + math.random() * (high - low), run.startZoom), step.secs)
end
-- Behind you: camera follow brings it round (as the vista camera lines up:
-- ns.CenterCamera, Camera.lua), our own follow-off set out of its way
-- meanwhile; then everything counts from there. In front: counted.
function STEP.turnTo(step)
	if step.to == "front" then
		local m = movers.yaw
		local secs = step.fit == "cast" and ns.DepartTimeLeft and ns.DepartTimeLeft() or step.secs
		MoveTo(m, m.amount - Wrap(m.amount - 180), secs, EASES.smooth)
		WaitMover(m)
		return
	end
	ns.ApplyCVarSet(FOLLOW_CVARS, false)
	ns.CenterCamera(step.secs, 30, 20, math.min(3, step.secs / 2))
	WaitSeconds(step.secs)
	local giveUp = run.t + 2
	while ns.RECENTER_CVARS and ns.RECENTER_CVARS.active and run.t < giveUp do Yield() end
	ns.ApplyCVarSet(FOLLOW_CVARS, true)
	movers.yaw.amount, movers.pitch.amount = 0, 0
end
function STEP.sway(step)
	local m = movers.yaw
	local delta = SwayTurn(step, m.amount, math.random)
	local curve, secs, top, still = SwayCurve(step, delta, m.amount)
	if curve then
		MoveCurve(m, delta >= 0, curve, secs, top)
		WaitMover(m)
		WaitSeconds(still)
	else
		if math.abs(delta) >= 0.5 then
			MoveTo(m, m.amount + delta, step.secs, EASES[step.ease])
			WaitMover(m)
		end
		WaitSeconds(step.pause)
	end
end
function STEP.tiltRand(step)
	local m = movers.pitch
	MoveTo(m, step.deg - step.up + math.random() * (step.up + step.down), step.secs, EASES.smooth)
	WaitMover(m)
end
function STEP.spin(step)
	local m = movers.yaw
	MoveCurve(m, Way(step, math.random, run.onceLeft) == "left", SpinCurve(step), step.secs > 0 and step.secs or 1e7,
		step.max)
	WaitMover(m)
end
function STEP.lineup(step)
	local m = movers.yaw
	MoveTo(m, m.amount - Wrap(m.amount), step.secs, EASES.smooth)
	WaitMover(m)
end
function STEP.wait(step)
	WaitSeconds(step.secs)
end
function STEP.emote(step)
	local token = step.token:upper()
	if DoEmote then
		pcall(DoEmote, token, "none")
	elseif C_ChatInfo and C_ChatInfo.PerformEmote then
		pcall(C_ChatInfo.PerformEmote, token, "none")
	end
	WaitSeconds(0.5)
end
-- Everything this script turned, tilted and zoomed undone: the turn and the
-- zoom together, then the tilt (the game won't turn and tilt at once).
function STEP.putback(step)
	local yaw, pitch = movers.yaw, movers.pitch
	MoveTo(yaw, yaw.amount - Wrap(yaw.amount), step.secs, EASES.smooth)
	if step.zoom == "yes" then ZoomTo(run.startZoom, step.secs) end
	WaitMover(yaw)
	MoveTo(pitch, 0, step.secs, EASES.smooth)
	WaitMover(pitch)
	if step.zoom == "yes" then WaitZoom() end
end
-- Whether a Wait until's moment has come.
local UNTIL = {
	cast = function(step)
		local left = ns.DepartCastLeft and ns.DepartCastLeft()
		return not left or left <= step.secs
	end,
	landing = function(step)
		if not ns.OnTaxi() then return true end
		local left = ns.FlightTimeLeft and ns.FlightTimeLeft()
		return left ~= nil and left <= step.secs
	end,
	alive = function() return not ns.IsDead() end,
	-- (Someone other than the one last aimed at.)
	talk = function() return heard.at > run.startedAt and heard.name ~= run.aimedAt end,
}

-- Every move eased to a stop over a moment, from the speed it's going (a
-- Wait until cutting its steps short: stopped dead, it jolted).
local BRAKE_TIME = 1.2
local function BrakeAll()
	for _, m in pairs(movers) do
		m.suspended = nil
		if m.moving and m.sent and m.share then
			-- (The held move carries on, its curve swapped: no stop and start.)
			local speed = m.sent * m.share
			m.curve = function(t) return speed * (1 + math.cos(math.pi * math.min(1, t / BRAKE_TIME))) / 2 end
			m.top, m.curveGrowing, m.t, m.T = speed, m.growing, 0, BRAKE_TIME
			m.target = m.amount + (m.growing and 1e6 or -1e6)
		else
			StopMove(m)
		end
	end
	StopZoom()
	zoomer.suspended = nil
end

STEP["until"] = function(step)
	local done = step.what == "time" and function() return false end or UNTIL[step.what]
	local untilT = step.what == "time" and run.t + step.secs or math.huge
	local kid = #step.steps > 0 and coroutine.create(function() DoSteps(step.steps) end)
	while not done(step) and run.t < untilT do
		if kid and coroutine.status(kid) ~= "dead" then
			local ok, err = coroutine.resume(kid)
			if not ok then error(err, 0) end
		end
		Yield()
	end
	if kid and coroutine.status(kid) ~= "dead" then
		BrakeAll()
		while not (MoverDone(movers.yaw) and MoverDone(movers.pitch)) do Yield() end
	end
end
function STEP.waitRand(step)
	local low, high = math.min(step.min, step.max), math.max(step.min, step.max)
	WaitSeconds(low + math.random() * (high - low))
end
function STEP.follow(step)
	run.follow = step.after
	run.facing = nil
end
-- Aim at: see KINDS.aim. (Where a bubble is goes stale as the camera
-- turns: read before each swing, with the camera still.)
local AIM_CORRECT = 6 -- degrees still off past deg after a swing at a speaker: one more (as ChatCam.lua's CORRECT)
-- The turn toward the speaker's bubble: 0 if they're within deg of the
-- middle already, nil with no bubble (waited for up to wait seconds), and
-- how far off they are past deg.
local function SpeakerTurn(step, wait)
	local angle
	local giveUp = run.t + wait
	while heard.text and ns.ChatBubbleAngle do
		angle = ns.ChatBubbleAngle(heard.text)
		if angle or run.t >= giveUp then break end
		Yield()
	end
	if not angle then return nil end
	if math.abs(angle) <= step.deg then return 0, 0 end
	-- (MoveViewLeft, ours growing, brings what's on the right toward the
	-- middle: ChatCam.lua's Command.)
	-- (AIM_MOST from where it started, or from where a look round found them.)
	local m, center = movers.yaw, run.aimCenter or 0
	local off = angle - (angle > 0 and step.deg or -step.deg)
	local turn = math.max(-AIM_MOST, math.min(AIM_MOST, off / AIM_GAIN))
	return math.max(-AIM_MOST, math.min(AIM_MOST, m.amount + turn - center)) + center - m.amount, math.abs(off)
end
-- Looking round for a speaker off screen (miss "look"): LOOK_STEP at a time
-- one way, a full turn at most (ending where it began), until their bubble
-- shows. Gives the turn toward them then, or nil.
local LOOK_STEP = 45
local function LookRound(step)
	local m = movers.yaw
	local way = math.random() < 0.5 and 1 or -1
	for _ = 1, 360 / LOOK_STEP do
		MoveTo(m, m.amount + way * LOOK_STEP, AimSecs(step, LOOK_STEP), EASES[step.ease])
		WaitMover(m)
		WaitSeconds(0.3)
		run.aimCenter = m.amount
		local turn = SpeakerTurn(step, 0)
		if turn then return turn end
	end
	run.aimCenter = nil
end
function STEP.aim(step)
	local m = movers.yaw
	local turn
	if step.at == "click" then
		local side = ns.QuestTalkNow and select(2, ns.QuestTalkNow())
		-- (QuestCam.lua's PickSide and Command: a click on the right turns the
		-- view right.)
		if side then turn = side == "right" and -step.deg or step.deg end
	else
		run.aimedAt = heard.name
		turn = SpeakerTurn(step, AIM_WAIT)
		if not turn and step.miss == "look" and heard.text then turn = LookRound(step) end
	end
	if not turn and step.miss == "random" then
		local deg = step.at == "click" and step.deg or 12
		turn = math.random() < 0.5 and deg or -deg
	end
	if not turn or math.abs(turn) < 0.5 then return end
	MoveTo(m, m.amount + turn, AimSecs(step, turn), EASES[step.ease])
	WaitMover(m)
	if step.at == "speaker" then
		-- (Still well off, a swing cut short by how far it may go: one more.)
		WaitSeconds(0.3)
		local again, off = SpeakerTurn(step, 0)
		if again and off > AIM_CORRECT and math.abs(again) >= 0.5 then
			MoveTo(m, m.amount + again, AimSecs(step, again), EASES[step.ease])
			WaitMover(m)
		end
	end
end

function STEP.play(step)
	local played = (run.plays or 0) < MAX_PLAYS and ns.FindCameraScript(step.script)
	if not played then return end
	run.plays = (run.plays or 0) + 1
	DoSteps(ns.CleanCameraScript(played, played.id, played.builtin).steps)
	run.plays = run.plays - 1
end

function STEP.together(step)
	local kids = {}
	for _, child in ipairs(step.steps) do
		kids[#kids + 1] = coroutine.create(function() DoStep(child) end)
	end
	while true do
		local alive = false
		for _, kid in ipairs(kids) do
			if coroutine.status(kid) ~= "dead" then
				local ok, err = coroutine.resume(kid)
				if not ok then error(err, 0) end
				if coroutine.status(kid) ~= "dead" then alive = true end
			end
		end
		if not alive then return end
		Yield()
	end
end
STEP["repeat"] = function(step)
	local count = 0
	while step.times == 0 or count < step.times do
		count = count + 1
		local before = run.t
		DoSteps(step.steps)
		if run.t == before then Yield() end -- (nothing in it took any time: never spin within a frame)
	end
end

function DoStep(step)
	local action = not step.off and STEP[step.k]
	if action then
		run.step = step
		-- (The steps under way, for its page to light up: Together runs several.)
		local active = run.active
		active[step] = (active[step] or 0) + 1
		action(step)
		active[step] = active[step] > 1 and active[step] - 1 or nil
	end
end

-- Starts a script (trigger: the trigger key it's running for; nil, played
-- from its page or /cine script play).
local function Start(script, trigger, camera)
	if run then StopAll() end
	-- (A copy: editing it on its page meanwhile can't trip it up. A built-in
	-- one's switched-off steps kept, to be passed by.)
	local paths = {}
	local builtinId = script.builtin and script.id or nil -- (the copy below doesn't keep builtin: PlayingCameraKey)
	script = ns.CleanCameraScript(script, script.id, script.builtin, paths)
	run = {
		script = script, trigger = trigger, camera = camera, t = 0, phase = "steps", paths = paths, active = {},
		builtinId = builtinId,
		startZoom = Zoom(), startedAt = GetTime(), inputSeen = ns.GetLastCameraInput and ns.GetLastCameraInput() or 0,
		triggerOn = trigger ~= nil, onceLeft = math.random() < 0.5,
		-- (Played for Skyriding, or a scene of yours on the move, mounted or flying: walking
		-- and steering are what you do then. Walk doesn't stop it, and your
		-- turning the camera stops only its turns and tilts: its zoom goes on.)
		travel = trigger == "Skyride"
			or (trigger ~= nil and ns.CustomTravelScene ~= nil and ns.CustomTravelScene() == trigger),
	}
	ns.zoomWhileSteering[WHO] = run.travel or nil
	movers.yaw.amount, movers.pitch.amount = 0, 0
	run.co = coroutine.create(function() DoSteps(script.steps) end)
	ns.ApplyCVarSet(FOLLOW_CVARS, true)
	ns.Log("state", ("camera script %s started (%s)"):format(script.name, trigger or "played"))
end

local stoppedFor -- trigger..camera a script was stopped for: not again until that trigger's over
-- A Past max zoom's raised limit kept after its script, while the camera's
-- still out past where it started (putting it back then snaps the camera in).
local maxHeldTo
local exitBox -- the Stop button (a script's button option)

local function Finish(why)
	if not run then return end
	StopAll()
	if run.raisedMax and ns.LowerZoomMax then
		if Zoom() > run.startZoom + 0.5 then maxHeldTo = run.startZoom else ns.LowerZoomMax() end
	end
	if exitBox then exitBox:Hide() end
	run.follow, run.glideUntil = nil, nil
	ns.ApplyCVarSet(FOLLOW_CVARS, false)
	ns.Log("state", ("camera script %s ended (%s)"):format(run.script.name, why or "done"))
	if run.trigger and run.triggerOn then stoppedFor = run.trigger .. run.camera end
	-- (A scene its key started: over too, so the next press starts it again.)
	local trigger = run.trigger
	run = nil
	ns.zoomWhileSteering[WHO] = nil
	if trigger and ns.EndCustomKeyScene then ns.EndCustomKeyScene(trigger) end
end

local function BeginEnding(why)
	StopAll()
	if #run.script.ending == 0 then
		Finish(why)
		return
	end
	run.phase, run.pausedUntil, run.why = "ending", nil, why
	run.co = coroutine.create(function() DoSteps(run.script.ending) end)
end

-- How long a pause for event lasts (its rule off: a moment after you let go).
local function PauseSecs(rules, event)
	return rules[event .. "On"] == false and 1 or rules[event .. "Secs"]
end

-- What a stop rule says to do. Off, its event carries on, except your
-- camera input: that's still yours, carrying on a moment after you let go.
local function Act(event)
	local rules = run.script.rules
	local action = rules[event]
	if rules[event .. "On"] == false then
		if event ~= "camera" then return false end
		action = "pause"
	end
	if action == "ignore" then return false end
	-- (Its When it ends under way: only your camera input or a fight stops
	-- that; walking on, say, it carries on turning back.)
	if run.phase == "ending" and event ~= "camera" and event ~= "fight" then return false end
	if run.phase == "ending" or action == "stop" then
		Finish(event)
	elseif action == "putback" then
		BeginEnding(event)
	elseif action == "pause" then
		if not run.pausedUntil then Suspend() end
		run.pausedUntil = GetTime() + PauseSecs(rules, event)
		run.pausedBy = event
	elseif action == "restart" then
		StopAll()
		run.pausedUntil, run.phase = nil, "steps"
		run.co = coroutine.create(function() DoSteps(run.script.steps) end)
	end
	return true
end

-- NPCs talking (Chat Cam's rows, as ChatCam.lua takes its lines): the last
-- line heard (text, name, at), and the conversation going (its trigger,
-- since, lastAt). A line from an NPC you're talking to (a gossip or quest
-- window open, or shut under TALKED_WINDOW ago), your target or a party NPC
-- is "Chat"'s; others "ChatNearby"'s, once you've stood still
-- chatNearbyDelay seconds. Not while you're moving. Over chatCamQuiet
-- seconds after the last line.
local TALKED_WINDOW = 30
local talk = { open = false, closedAt = -math.huge, stillSince = 0 }
local convo -- { key, lastAt }
local function Plain(value)
	return type(value) == "string" and not (issecretvalue and issecretvalue(value)) and value or nil
end
local function ScriptRow(key)
	return ns.CAMERA_TRIGGER and ns.CAMERA_TRIGGER[key] and IsScript(ns.TriggerSetting(key, "camera")) or false
end
local heardFrame = CreateFrame("Frame")
for _, event in ipairs({ "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY",
	"PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_ENTERING_WORLD", "GOSSIP_SHOW", "GOSSIP_CLOSED",
	"QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED" }) do
	heardFrame:RegisterEvent(event)
end
heardFrame:SetScript("OnEvent", function(_, event, text, name)
	local now = GetTime()
	if event == "PLAYER_STARTED_MOVING" then
		talk.stillSince = nil
	elseif event == "PLAYER_STOPPED_MOVING" or event == "PLAYER_ENTERING_WORLD" then
		talk.stillSince = now
	elseif event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
		talk.open, talk.closedAt = false, now
	elseif event:sub(1, 5) == "GOSSIP" or event:sub(1, 5) == "QUEST" then
		talk.open = true
	else
		text, name = Plain(text), Plain(name) or "?"
		if not text or not ns.db or not ns.db.enabled then return end
		heard.text, heard.name, heard.at = text, name, now
		if convo and now - convo.lastAt < Db("chatCamQuiet", 20) then
			convo.lastAt = now -- (any line carries a conversation on)
			return
		end
		if ns.playerMoving then return end
		local key = "ChatNearby"
		if event == "CHAT_MSG_MONSTER_PARTY" or talk.open or now - talk.closedAt < TALKED_WINDOW
			or (name ~= "?" and Plain(UnitName("target")) == name) then
			key = "Chat"
		elseif now - (talk.stillSince or now) < Db("chatNearbyDelay", 10) then
			return
		end
		if ScriptRow(key) then convo = { key = key, lastAt = now } end
	end
end)
local function ChatNow()
	if convo and GetTime() - convo.lastAt >= Db("chatCamQuiet", 20) then convo = nil end
	return convo and ScriptRow(convo.key) and convo.key or nil
end

-- Skyriding in the air now (retail's gliding info), for the Skyriding Cam
-- page (SkyrideCam.lua: on, and its Show in row here): on once you've been
-- up skyrideCamStart seconds (not for a hop), off once you've been down
-- skyrideCamLand (not for a touch on the ground between flaps).
local sky = { on = false }
function ns.SkyridingNow()
	if not (ns.SkyrideCamOn and ns.SkyrideCamOn()) then
		sky.on, sky.upSince, sky.downSince = false, nil, nil
		return false
	end
	local now, up = GetTime(), ns.GlidingSpeed and ns.GlidingSpeed() ~= nil
	if up then
		sky.downSince = nil
		sky.upSince = sky.upSince or now
		if now - sky.upSince >= Db("skyrideCamStart", 0.5) then sky.on = true end
	else
		sky.upSince = nil
		sky.downSince = sky.downSince or now
		if now - sky.downSince >= Db("skyrideCamLand", 2) then sky.on = false end
	end
	return sky.on
end

-- The trigger running a script camera now, and that camera: a standing-still
-- trigger's (or your own's, or a cast's), else a flight's, death's, walking's,
-- running's, a quest giver's or chat's.
local function TriggerNow()
	if not ns.db or not ns.db.enabled or not ns.ActiveEvent then return nil end
	-- (A scene of yours its key started: first, a window open or walking.)
	local scene = ns.CustomKeyScene and ns.CustomKeyScene()
	if scene then
		local camera = ns.TriggerSetting(scene, "camera")
		if IsScript(camera) then return scene, camera end
	end
	-- (One of yours on while you're mounted, flying or swimming: on the move too.)
	scene = ns.CustomTravelScene and ns.CustomTravelScene()
	if scene then
		local camera = ns.TriggerSetting(scene, "camera")
		if IsScript(camera) then return scene, camera end
	end
	-- (Skyriding Cam's page: its own script, made from its settings.)
	if not ns.OnTaxi() and ns.SkyridingNow() then return "Skyride", "script:skyride" end
	local key, camera = ns.ActiveEvent()
	if IsScript(camera) then return key, camera end
	local triggers = ns.CAMERA_TRIGGER
	if not triggers then return nil end
	-- (A trigger with a camera of its own, its row set to a script: its own
	-- camera is off then, CameraRows.lua's ns.CameraRowsOff.)
	local own = { ns.OnTaxi() and "Flight", ns.IsDead and ns.IsDead() and "Death",
		ns.IsRPWalking and ns.IsRPWalking() and "Walk", ns.IsAutoRunning and ns.IsAutoRunning() and "Run",
		ns.QuestTalkNow and ns.QuestTalkNow() or false, ChatNow() or false }
	for i = 1, 6 do
		local each = own[i]
		if each and triggers[each] then
			camera = ns.TriggerSetting(each, "camera")
			if IsScript(camera) then return each, camera end
		end
	end
end

local function InFight()
	return InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
end

-- Follow on (STEP.follow): your facing watched; after a turn of more than
-- FOLLOW_TURN, held still run.follow seconds, the script's moves stop and
-- camera follow glides the camera behind you over FOLLOW_GLIDE seconds (the
-- script holds meanwhile), then the counts start from there. True while
-- gliding. (Your facing can't be read in some places: no follow there.)
local FOLLOW_TURN, FOLLOW_GLIDE = 15, 2.5
local function StepFollow(now)
	if run.glideUntil then
		if now < run.glideUntil or (ns.RECENTER_CVARS and ns.RECENTER_CVARS.active and now < run.glideUntil + 2) then
			return true
		end
		run.glideUntil = nil
		ns.ApplyCVarSet(FOLLOW_CVARS, true)
		movers.yaw.amount, movers.pitch.amount = 0, 0
		return false
	end
	if not run.follow then return false end
	local ok, facing = pcall(GetPlayerFacing)
	if not ok or type(facing) ~= "number" or (issecretvalue and issecretvalue(facing)) then return false end
	facing = math.deg(facing)
	if not run.facing then
		run.facing, run.facingAt, run.turnedFrom = facing, now, nil
		return false
	end
	if math.abs(Wrap(facing - run.facing)) > 0.5 then
		run.turnedFrom = run.turnedFrom or run.facing
		run.facing, run.facingAt = facing, now
		return false
	end
	if run.turnedFrom and now - run.facingAt >= run.follow then
		local turned = math.abs(Wrap(facing - run.turnedFrom))
		run.turnedFrom = nil
		if turned >= FOLLOW_TURN then
			StopAll()
			ns.ApplyCVarSet(FOLLOW_CVARS, false)
			ns.CenterCamera(FOLLOW_GLIDE, 40, 25, 1)
			run.glideUntil = now + FOLLOW_GLIDE
			return true
		end
	end
	return false
end

local function Update(elapsed)
	local now = GetTime()
	if not ns.db.enabled then
		Finish("Cinematic off")
		return
	end
	-- Your camera input since the last look: the zoom or the rest.
	local input = ns.GetLastCameraInput and ns.GetLastCameraInput() or 0
	local zoomed, moved = false, false
	if input > run.inputSeen then
		run.inputSeen = input
		if ns.lastPlayerZoomAt == input then zoomed = true else moved = true end
	end
	if run.tookAt then
		moved, run.tookAt = true, nil
	end
	if run.pausedUntil then
		-- Paused: more input keeps it paused; then it carries on.
		if (run.pausedBy == "camera" and (moved or zoomed)) or (run.pausedBy == "zoom" and zoomed)
			or (run.pausedBy == "walk" and ns.playerMoving) then
			run.pausedUntil = now + PauseSecs(run.script.rules, run.pausedBy)
		end
		if InFight() and Act("fight") then return end
		if run.trigger and not run.triggerOn and Act("ends") then return end
		if now < run.pausedUntil then return end
		run.pausedUntil = nil
		Resume()
	end
	if moved and run.travel then
		StopMove(movers.yaw) -- (yours: its turns and tilts give way, its zoom carries on)
		StopMove(movers.pitch)
		movers.yaw.suspended, movers.pitch.suspended = nil, nil
		moved = false
	end
	if moved and Act("camera") then return end
	if InFight() and Act("fight") then return end
	if ns.playerMoving and not run.travel and (not ns.MovingManually or ns.MovingManually()) and Act("walk") then
		return
	end
	if zoomed then
		if not Act("zoom") then StopZoom() end -- (yours wins: its zoom gives up)
		if not run or run.pausedUntil then return end
	end
	if run.phase == "steps" and run.trigger and not run.triggerOn then
		Act("ends")
		if not run then return end
	end
	if run.pausedUntil then return end
	if StepFollow(now) then return end
	StepMove(movers.yaw, elapsed)
	StepMove(movers.pitch, elapsed)
	StepZoom(elapsed)
	run.t = run.t + elapsed
	if coroutine.status(run.co) ~= "dead" then
		local ok, err = coroutine.resume(run.co)
		if not ok then
			ns.Print(L["camera script %s stopped: %s"]:format(run.script.name, tostring(err)))
			Finish("error")
			return
		end
	end
	if coroutine.status(run.co) == "dead" then
		if run.phase == "ending" then
			Finish(run.why)
		elseif not run.trigger then
			BeginEnding("done")
		end
		-- (Run for a trigger: it holds where it got to until the trigger's over.)
	end
end

local watcher = CreateFrame("Frame")
ns.SetOnUpdate(watcher, function(_, elapsed)
	if not ns.db then return end
	local key, camera = TriggerNow()
	if run and run.trigger then
		run.triggerOn = key == run.trigger and camera == run.camera
	end
	if not key then
		stoppedFor = nil
	elseif not run and stoppedFor ~= key .. camera and not InFight() then
		local script = ns.FindCameraScript(camera:sub(8))
		if script then Start(script, key, camera) end
	end
	-- (You zoomed while ours zooms or its speed eases back: held for yours.)
	local yourZoom = ns.lastPlayerZoomAt
	if yourZoom and yourZoom ~= zoomer.seenYourZoom then
		zoomer.seenYourZoom = yourZoom
		if zoomer.moving or zoomer.release then HoldForYourZoom() end
	end
	StepYourZoom(elapsed)
	if run then
		Update(elapsed)
	elseif zoomer.release then
		StepZoom(elapsed) -- (the zoom speed easing back after it ended)
	end
	if maxHeldTo and not run and Zoom() <= maxHeldTo + 0.5 then
		maxHeldTo = nil
		if ns.LowerZoomMax then ns.LowerZoomMax() end
	end
	-- (The Stop button while its steps run; not in When it ends.)
	if run and run.script.button and run.phase == "steps" and ns.ExitCameraBox then
		exitBox = exitBox or ns.ExitCameraBox(L["Stop camera"], function() ns.StopCameraScript() end)
		exitBox:Place()
	elseif exitBox and exitBox:IsShown() then
		exitBox:Hide()
	end
end)

-- The running script's Edge haze (0-1), or nil (Focus.lua asks).
function ns.CameraScriptHaze()
	return run and run.script.haze > 0 and run.script.haze or nil
end
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_LOGOUT")
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		ns.SyncScriptCameras()
	else
		Finish("logging out")
	end
end)

if ns.RegisterCamera then
	ns.RegisterCamera(WHO, function()
		return run ~= nil or restoring > 0 or zoomer.moving or zoomer.release ~= nil or zoomer.yours ~= nil
	end, function()
		-- You took the camera: every move stops now (the rules decide next frame).
		if run then
			run.tookAt = GetTime()
			if run.travel then
				StopMove(movers.yaw) -- (the zoom goes on: see Start)
				StopMove(movers.pitch)
				return
			end
			if run.pausedUntil then return end
			Suspend()
			local rules = run.script.rules
			if rules.camera ~= "pause" and rules.cameraOn ~= false then StopAll() end
		end
	end)
end

-- Plays a script now, from its page or a command. False and why if it can't.
function ns.PlayCameraScript(script)
	if not ns.db.enabled then return false, L["Cinematic is off (/cine turns it on)"] end
	if InFight() then return false, L["not in combat"] end
	stoppedFor = nil
	Start(script, nil, nil)
	return true
end

-- /cine orbit [angle] [secs]: the camera turns once round you, 360 degrees
-- over 10 seconds unless given (a negative angle goes the other way), as a
-- one-step script: the rotate step's camera lock, speed hold and creep start.
-- Again while it turns: stops it. Moving, a fight or your own camera stop it.
local ORBIT_ID = "orbit"
function ns.OrbitCommand(arg)
	local playing = run and run.script
	if playing and playing.id == ORBIT_ID then
		ns.StopCameraScript()
		ns.Print(L["orbit stopped"])
		return
	end
	local angle, secs = (arg or ""):match("^%s*(%S*)%s*(%S*)")
	angle, secs = tonumber(angle) or 360, tonumber(secs) or 10
	local deg = math.max(1, math.min(3600, math.abs(angle)))
	secs = math.max(0.5, math.min(600, secs))
	local turn = ns.NewCameraScriptStep("rotate")
	turn.deg, turn.secs, turn.way, turn.ease = deg, secs, angle < 0 and "right" or "left", "steady"
	local ok, why = ns.PlayCameraScript({ id = ORBIT_ID, name = L["Orbit"], steps = { turn }, ending = {},
		rules = { camera = "stop", fight = "stop", walk = "stop", zoom = "ignore", ends = "stop" } })
	if ok then
		ns.Print(L["orbit: %d degrees over %s seconds (/cine orbit again stops it)"]:format(deg, tostring(secs)))
	else
		ns.Print(L["orbit can't start: %s"]:format(tostring(why)))
	end
end

-- The script playing now, or nil (the minimap button's menu lists it).
function ns.PlayingCameraScript()
	return run and run.script
end

-- The camera a playing built-in script stands in for, by its key in
-- ns.activeCam ("idle", "vista", "flight"...), or nil: the rules' cam_*
-- words (Frames.lua). Run as its script, a camera leaves ns.activeCam unset.
local CAMERA_KEY_OF = { afk = "idle", chat = "chatcam" }
function ns.PlayingCameraKey()
	local id = run and run.builtinId
	if type(id) ~= "string" then return nil end
	return CAMERA_KEY_OF[id] or id
end

function ns.StopCameraScript()
	if run then Finish("stopped") return true end
	return false
end

-- The steps under way now (not the groups they're in), by their place in the
-- script as its page lists them ("2.1"; When it ends' "e.1.1"), and the
-- script's id: for its page to light them up.
function ns.CameraScriptActivePaths()
	if not run then return nil end
	local lit = run.lit or {}
	run.lit = lit
	wipe(lit)
	for step in pairs(run.active) do
		local at = not step.steps and run.paths[step]
		if at then lit[at] = true end
	end
	return lit, run.script.id
end

-- The one running: its script, phase ("steps" or "ending"), the step under
-- way, seconds in, paused (seconds left), and the trigger.
function ns.CameraScriptState()
	if not run then return nil end
	return {
		script = run.script, phase = run.phase, step = run.step, t = run.t, trigger = run.trigger,
		paused = run.pausedUntil and math.max(0, run.pausedUntil - GetTime()) or nil,
		yaw = movers.yaw.amount, pitch = movers.pitch.amount,
	}
end

-- /cine script: what's running and why (or why not), and the commands.
function ns.CameraScriptCommand(arg)
	local cmd, rest = (arg or ""):match("^(%S*)%s*(.-)$")
	if cmd == "play" then
		local want = rest:lower()
		for _, script in ipairs(ns.CameraScripts()) do
			if script.name:lower() == want or script.id == want then
				local ok, why = ns.PlayCameraScript(script)
				ns.Print(ok and L["playing camera script %s"]:format(script.name) or why)
				return
			end
		end
		ns.Print(L["no camera script called %s"]:format(rest))
	elseif cmd == "stop" then
		ns.Print(ns.StopCameraScript() and L["camera script stopped"] or L["no camera script is running"])
	elseif cmd == "builtins" and ns.isDev and ns.db then
		ns.db.scriptBuiltIns = not ns.db.scriptBuiltIns or nil
		ns.CameraRowsChanged()
		if ns.db.scriptBuiltIns then
			ns.Print("our cameras run as their scripts: ON (Cozy, AFK, Flight... rows play the built-in script; " ..
				"the cameras' own code stays off). /cine script builtins again for the old cameras.")
		else
			if run and run.trigger then ns.StopCameraScript() end -- (the old camera takes over)
			ns.Print("our cameras run as their scripts: OFF (the cameras' own code again)")
		end
	elseif cmd == "list" then
		for _, script in ipairs(ns.CameraScripts()) do
			local keys = ns.CameraScriptTriggers(script.id)
			ns.Print(("%s [%s]%s: %s"):format(script.name, script.id, script.builtin and " (built-in)" or "",
				#keys > 0 and table.concat(keys, ", ") or "no trigger"))
		end
	else
		local key, camera = TriggerNow()
		local active, activeCam
		if ns.ActiveEvent then active, activeCam = ns.ActiveEvent() end
		ns.Print(("camera scripts: Cinematic %s; trigger now %s (%s); event %s (%s); flight %s; combat %s; view held by %s"):format(
			ns.db.enabled and "on" or "OFF (/cine: no script plays)",
			tostring(key), tostring(camera), tostring(active), tostring(activeCam), tostring(ns.OnTaxi()),
			tostring(InFight()), tostring(ns.CameraHolder and ns.CameraHolder(WHO) or "?")))
		local scene = ns.CustomKeyScene and ns.CustomKeyScene()
		ns.Print(("scene started by its key: %s%s"):format(tostring(scene), scene and (" (row now %s, camera %s)"):format(
			tostring(ns.TriggerRowNow(scene)), tostring(ns.TriggerSetting(scene, "camera"))) or ""))
		if ns.isDev then
			ns.Print(("our cameras as scripts (/cine script builtins): %s"):format(
				ns.ScriptBuiltInsOn() and "ON" or "off"))
		end
		if run then
			local step = run.step
			-- (Where the step is in the script: 3, or 2.1 inside a group or repeat.)
			local function Find(steps, path)
				for i, each in ipairs(steps or {}) do
					local at = path and (path .. "." .. i) or tostring(i)
					if each == step then return at end
					local inner = Find(each.steps, at)
					if inner then return inner end
				end
			end
			local where = step and ((Find(run.script.steps) or "?") .. " " .. tostring(step.k)) or "-"
			ns.Print(("running %s for %s: %s, step %s of %d, %.1f s in%s; counted turn %.1f, tilt %.1f; zoom %.1f (started %.1f)%s"):format(
				run.script.name, tostring(run.trigger or "a play"), run.phase, where, #run.script.steps, run.t,
				run.pausedUntil and (", paused %.1f s (%s)"):format(run.pausedUntil - GetTime(), run.pausedBy) or "",
				movers.yaw.amount, movers.pitch.amount, Zoom(), run.startZoom,
				run.trigger and (run.triggerOn and ", trigger on" or ", trigger over") or ""))
			ns.Print(("moves: turn %s, tilt %s, zoom %s; speeds %s / %s / %s"):format(
				movers.yaw.moving and "moving" or movers.yaw.pending and "waiting" or "-",
				movers.pitch.moving and "moving" or movers.pitch.pending and "waiting" or "-",
				zoomer.moving and "moving" or zoomer.pending and "waiting" or "-",
				tostring(GetCVar("cameraYawMoveSpeed")), tostring(GetCVar("cameraPitchMoveSpeed")),
				tostring(GetCVar("cameraZoomSpeed"))))
		else
			ns.Print(("not running%s"):format(stoppedFor and (" (stopped for %s until it's over)"):format(stoppedFor) or ""))
		end
		ns.Print("/cine script list | play <name> | stop" .. (ns.isDev and " | builtins" or ""))
	end
end
