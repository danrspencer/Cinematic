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
-- first frame); a turn and a tilt can go together (a move's start stops the
-- other axis's, so that one is sent again: as Camera.lua's orbit sways), with
-- a short gap between one axis's moves; the zoom steered toward its eased path. Camera follow is off while
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
local MAX_DEPTH = 8         -- Together, Repeat and Wait until inside each other (the flight cruise goes 7 deep)
local MAX_SCRIPTS = 30
local MAX_PLAYS = 3         -- Play steps inside each other (a camera playing itself, say)
-- Each: the share of a move spent speeding up and slowing down (both ends
-- alike), or { speeding up, slowing down } for one end only: in eases in and
-- ends at full speed (to hand over to the next turn the same way), out sets
-- off at full speed and eases to a stop.
local EASES = { smooth = 0.5, gentle = 0.35, steady = 0.15, none = 0, ["in"] = { 0.5, 0 }, out = { 0, 0.5 } }
local FOLLOW_CVARS = ns.CVarSet("Follow off: camera script", "camera follow off while a script plays",
	{ values = { cameraSmoothStyle = "0" } }) -- camera follow off meanwhile
-- Speed up and Slow down (speedUp, slowDown): each end's ramp on its own,
-- as a share of the move (none: full speed at that end).
local RAMP = { none = 0, short = 0.15, medium = 0.35, long = 0.5 }
ns.CAMERA_SCRIPT_RAMPS = { "none", "short", "medium", "long" }
-- An Ease from before (and a sway's, which keeps one: its drift follows on
-- from its own end) as Speed up and Slow down.
local EASE_RAMPS = { smooth = { "long", "long" }, gentle = { "medium", "medium" }, steady = { "short", "short" },
	["in"] = { "long", "none" }, out = { "none", "long" }, none = { "none", "none" } }
ns.CAMERA_SCRIPT_EASES = { "smooth", "gentle", "steady", "none" }
local SWAY_EASES = ns.CAMERA_SCRIPT_EASES

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
	-- (blend: seconds its speed slides from what the turn before it was going
	-- at, when that one handed straight over to it, the same way: Handover.
	-- 0: its own speed straight away.)
	-- (speedUp, slowDown: see RAMP. Their places on the page: two to a row.)
	rotate = { fields = { { "deg", "num", 1, 3600, 45 }, { "secs", "num", 0.5, 600, 4 },
		{ "way", "pick", { "left", "right", "random", "once" }, "left" }, { "blend", "num", 0, 10, 0 },
		{ "speedUp", "pick", ns.CAMERA_SCRIPT_RAMPS, "long" }, { "slowDown", "pick", ns.CAMERA_SCRIPT_RAMPS, "long" } } },
	-- (rand "give": to deg from where the scene started, give or take up
	-- (higher) and down (lower), picked each time: was Tilt at random. Else
	-- deg more from where it is.)
	tilt = { fields = { { "deg", "num", -80, 80, 10 }, { "secs", "num", 0.5, 600, 3 },
		{ "rand", "pick", { "no", "give" }, "no" }, { "blend", "num", 0, 10, 0 },
		{ "up", "num", 0, 80, 5 }, { "down", "num", 0, 80, 3 },
		{ "speedUp", "pick", ns.CAMERA_SCRIPT_RAMPS, "long" }, { "slowDown", "pick", ns.CAMERA_SCRIPT_RAMPS, "long" } } },
	-- (fit "cast": over the time a Hearthstone or teleport cast has left
	-- instead of secs, as the tele camera's zoom in goes. speed: yards a
	-- second at its fastest, secs then the longest it takes; 0 goes by secs.
	-- past "yes": the game's max zoom distance raised meanwhile, as far as 2.6
	-- times, so a zoom out isn't cut short at yours.)
	-- (rand "between": somewhere from to to max, picked each time: was Zoom
	-- at random.)
	zoom = { fields = { { "rand", "pick", { "no", "between" }, "no" }, { "of", "pick", { "yards", "yours" }, "yards" },
		{ "to", "num", -50, 50, 5 }, { "max", "num", -50, 50, 8 },
		{ "secs", "num", 0.5, 600, 3 }, { "fit", "pick", { "secs", "cast" }, "secs" },
		{ "speed", "num", 0, 20, 0 }, { "past", "pick", { "no", "yes" }, "no" },
		{ "speedUp", "pick", ns.CAMERA_SCRIPT_RAMPS, "medium" }, { "slowDown", "pick", ns.CAMERA_SCRIPT_RAMPS, "medium" } } },
	-- Waits for something: secs going by (time; rand "between": somewhere
	-- from secs to max, picked each time), a cast secs from done (cast),
	-- landing in secs (landing: a route flown before; else touchdown), coming
	-- back to life (alive), or someone other than the one last aimed at
	-- saying something (talk). With steps of its own, it runs them meanwhile
	-- and, once it's time, eases them to a stop and goes on. (No cast, flight
	-- or death under way: nothing to end, it waits on, running them.) Was
	-- Wait, Wait at random and Wait until.
	wait = { group = true, fields = { { "what", "pick", { "time", "cast", "landing", "alive", "talk" }, "time" },
		{ "rand", "pick", { "no", "between" }, "no" }, { "secs", "num", 0, 3600, 2 }, { "max", "num", 0, 3600, 6 } } },
	emote = { fields = { { "token", "text", "wave" } } },
	-- Undo its turns: every turn and tilt the scene made taken back, by the
	-- running total of them (the game never says where the camera points:
	-- each turn is sent as a speed for a time, and added up). Your own camera
	-- input starts the total again from where you leave it (ForgetTurns).
	-- (zoom "no": the zoom left where it is, a zoom step beside it say.)
	putback = { fields = { { "secs", "num", 0.5, 600, 3 }, { "zoom", "pick", { "yes", "no" }, "yes" } } },
	-- (No Turn to or Line up: the game never says which way the camera
	-- points, let alone where you are on screen, so "face you" was only 180
	-- degrees from the start and "behind you" only back to it. Older ones
	-- become a Rotate 180 and an Undo its turns, CleanSteps.)
	-- A random spot within arc degrees of where it was as this sway first ran
	-- in the scene (SwayCenter), at least min from where it is (favor: nearer the middle, as the vista and fish cameras
	-- like), over secs; then creeping on the same way at drift degrees a second
	-- through pause seconds, flowing straight out of the turn and easing off
	-- before the arc's edge.
	sway = { fields = { { "arc", "num", 1, 180, 30 },
		{ "min", "num", 0, 180, 10 }, { "secs", "num", 0.5, 600, 10 }, { "ease", "pick", SWAY_EASES, "smooth" },
		{ "drift", "num", 0, 30, 0.5 }, { "pause", "num", 0, 600, 15 }, { "favor", "pick", { "no", "yes" }, "no" } } },
	-- Round and round, from start degrees a second (0: from still), speeding
	-- up accel degrees a second each second to max; secs 0: until the camera ends.
	spin = { fields = { { "start", "num", 0, 360, 0 }, { "accel", "num", 0.5, 100, 8 }, { "max", "num", 1, 360, 120 }, { "secs", "num", 0, 3600, 0 },
		{ "way", "pick", { "left", "right", "random", "once" }, "left" }, { "blend", "num", 0, 10, 0 } } },
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
		{ "speed", "num", 0, 90, 0 },
		{ "speedUp", "pick", ns.CAMERA_SCRIPT_RAMPS, "long" }, { "slowDown", "pick", ns.CAMERA_SCRIPT_RAMPS, "long" } } },
	-- Another camera's steps, here (not its stop rules or When it ends), as
	-- they are now: a built-in one follows your settings. Cameras playing
	-- cameras go MAX_PLAYS deep at most.
	play = { fields = { { "script", "script", "flyby" } } },
	-- Music a camera started fades out over secs and ends (your own game music
	-- is left alone). It doesn't wait: the steps after it go on meanwhile.
	endMusic = { fields = { { "secs", "num", 0, 60, 3 } } },
	-- Follow your turns, until the camera ends (beside the rest in a
	-- Together): while you turn, the view is turned back as far, so it holds
	-- its direction instead of swinging round with you; after seconds
	-- of not turning, it glides round behind your new facing, lazy seconds
	-- of laziness (the further off, the quicker), top degrees a second at
	-- most, speeding up and slowing down by accel. corners "yes": bigger turns
	-- glide back quicker, small ones gentler. steer "yes": several turns in
	-- a row (steering) glide sooner and quicker. most (degrees, 0: none):
	-- the furthest it lets the view fall behind a turn; past it, the view
	-- turns with you (a long skyriding turn would put it in front of you).
	-- Its own turns go out
	-- meanwhile: the script's other turns wait for it (a sway carries on
	-- after). (The RP walk and auto-run cameras' turn follow, Camera.lua's
	-- UpdateTurnFollow.)
	follow = { fields = { { "after", "num", 0, 10, 1.5 }, { "lazy", "num", 0.2, 10, 1.6 }, { "top", "num", 5, 180, 40 },
		{ "accel", "num", 5, 360, 30 }, { "corners", "pick", { "no", "yes" }, "no" },
		{ "steer", "pick", { "yes", "no" }, "yes" }, { "most", "num", 0, 180, 0 } } },
	together = { group = true, fields = {} },
	["repeat"] = { group = true, fields = { { "times", "num", 0, 100, 2 } } },
}
-- The page's add buttons, in their groups (headers: CameraScriptsPage.lua).
ns.CAMERA_SCRIPT_ADD_GROUPS = {
	{ key = "move", kinds = { "rotate", "tilt", "zoom", "spin", "sway", "aim", "follow", "putback" } },
	{ key = "wait", kinds = { "wait" } },
	{ key = "group", kinds = { "together", "repeat" } },
	{ key = "other", kinds = { "emote", "play", "endMusic" } },
}
ns.CAMERA_SCRIPT_ADDABLE = {}
for _, group in ipairs(ns.CAMERA_SCRIPT_ADD_GROUPS) do
	for _, kind in ipairs(group.kinds) do ns.CAMERA_SCRIPT_ADDABLE[#ns.CAMERA_SCRIPT_ADDABLE + 1] = kind end
end
local KINDS = ns.CAMERA_SCRIPT_KINDS

-- The stop rules: each event's actions (the first is its default).
ns.CAMERA_SCRIPT_RULES = {
	{ key = "camera", actions = { "stop", "putback", "pause", "restart" } },
	{ key = "fight", actions = { "putback", "stop" } },
	{ key = "walk", actions = { "putback", "stop", "pause", "restart", "ignore" } },
	{ key = "zoom", actions = { "ignore", "stop", "putback", "pause" } },
	{ key = "ends", actions = { "putback", "stop" } },
	-- (A cast or channel of yours ending or cancelled while it plays: a
	-- Hearthstone's, however long haste makes it. Carry on unless set.)
	{ key = "cast", actions = { "ignore", "putback", "stop" } },
}
local RULE_ACTIONS = {}
for _, rule in ipairs(ns.CAMERA_SCRIPT_RULES) do
	RULE_ACTIONS[rule.key] = {}
	for _, action in ipairs(rule.actions) do RULE_ACTIONS[rule.key][action] = true end
end

-- A step's Ease from before (or a built-in's, written that way) as its
-- Speed up and Slow down, in place, for kinds that have them now.
local function HasRamps(kind)
	local def = KINDS[kind]
	if not def then return false end
	for _, field in ipairs(def.fields) do
		if field[1] == "speedUp" then return true end
	end
	return false
end
local function TakeOldEase(step)
	if type(step) ~= "table" or step.ease == nil or not HasRamps(step.k) then return step end
	local ramps = EASE_RAMPS[step.ease]
	if ramps then
		if step.speedUp == nil then step.speedUp = ramps[1] end
		if step.slowDown == nil then step.slowDown = ramps[2] end
	end
	step.ease = nil
	return step
end
ns.UpgradeCameraScriptStep = TakeOldEase

-- How a step's move speeds up and slows down: { speeding up, slowing down }
-- shares (Speed up and Slow down), or a sway's one Ease.
local function StepEase(step)
	if step.speedUp ~= nil or step.slowDown ~= nil then
		return { RAMP[step.speedUp] or RAMP.long, RAMP[step.slowDown] or RAMP.long }
	end
	local ramps = EASE_RAMPS[step.ease]
	if ramps then return { RAMP[ramps[1]], RAMP[ramps[2]] } end
	return EASES.smooth
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
-- An old step that's gone, as what it really did: Turn to (face you) a
-- Rotate 180 either way, Line up (behind you) an Undo its turns leaving the
-- zoom be. A turn behind you, from before that: dropped (it leaned on camera
-- follow, which does nothing), as Follow is by having no kind now.
-- Steps folded into others (2026-11-05): Zoom at random a Zoom with
-- Random, Tilt at random a Tilt with Random, Wait at random and Wait until
-- a Wait. A copy, the old one's settings carried over.
local FOLDED = {
	zoomRand = function(old, new)
		new.k, new.rand, new.to, new.max, new.min = "zoom", "between", old.min, old.max, nil
	end,
	tiltRand = function(old, new)
		new.k, new.rand = "tilt", "give"
		if old.ease == nil and old.speedUp == nil then new.speedUp, new.slowDown = "long", "long" end
	end,
	waitRand = function(old, new)
		new.k, new.rand, new.secs, new.max, new.min = "wait", "between", old.min, old.max, nil
	end,
	["until"] = function(_, new) new.k = "wait" end,
}
local function Unfold(step)
	local fold = type(step) == "table" and FOLDED[step.k]
	if not fold then return step end
	local copy = {}
	for k, v in pairs(step) do copy[k] = v end
	fold(step, copy)
	return copy
end

local function OldStep(step)
	if type(step) ~= "table" then return step end
	step = Unfold(step)
	if step.ease ~= nil and HasRamps(step.k) then
		local copy = {}
		for k, v in pairs(step) do copy[k] = v end
		step = TakeOldEase(copy)
	end
	if step.k == "turnTo" then
		if step.to == "behind" then return nil end
		return { k = "rotate", deg = 180, secs = step.fit ~= "cast" and step.secs or 6, way = "random",
			speedUp = "long", slowDown = "long", set = step.set, off = step.off }
	elseif step.k == "lineup" then
		return { k = "putback", secs = step.secs, zoom = "no", set = step.set, off = step.off }
	end
	return step
end

local function CleanSteps(list, depth, budget, keepSet, paths, prefix)
	local out = {}
	if type(list) ~= "table" then return out end
	for i, step in ipairs(list) do
		step = OldStep(step)
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
	local raw = { k = kind }
	for k, v in pairs(fields or {}) do raw[k] = v end
	raw = Unfold(raw)
	local step = ns.NewCameraScriptStep(raw.k)
	if raw.ease ~= nil and HasRamps(raw.k) then step.speedUp, step.slowDown = nil, nil end
	for k, v in pairs(raw) do step[k] = v end
	return TakeOldEase(step)
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
-- PitchUp) and a sway within BackArc of where it first was (front: the cozy
-- camera's, after its half turn; no leaning to the middle), at least MinChange on, over MoveTime, drifting on at DriftSpeed (Drift)
-- through Pause; the height and the sway together.
local function SwayLoop(o, level, levelKey, front)
	-- (The height over the sway's turn, beside it: as the cameras' own code
	-- tilts and turns in one sweep.)
	local height = S("tiltRand", { deg = level, down = Db(o .. "PitchDown", 3), up = Db(o .. "PitchUp", 5),
		secs = Db(o .. "MoveTime", 10) })
	if levelKey then Set(height, levelKey, o .. "PitchDown", o .. "PitchUp") else Set(height, o .. "PitchDown", o .. "PitchUp") end
	-- (Auto-run's lowest tilt: the real camera's, while you steer; shown here.)
	if o == "runOrbit" then table.insert(height.set, "runOrbitPitchFloor") end
	local sway = Set(S("sway", { arc = Db(o .. "BackArc", 30),
		min = Db(o .. "MinChange", 10), secs = Db(o .. "MoveTime", 10), ease = NearestEase(Db(o .. "Ease", 0.5)),
		drift = Switch(o .. "Drift") and Db(o .. "DriftSpeed", 0.5) or 0, pause = Db(o .. "Pause", 15),
		favor = front and "no" or "yes" }), o .. "BackArc", o .. "MinChange", o .. "MoveTime", o .. "Ease", o .. "Pause",
		o .. "Drift", o .. "DriftSpeed")
	table.insert(height.set, o .. "MoveTime")
	return On(Set(S("repeat", { times = 0, steps = { S("together", { steps = { height, sway } }) } }), o), Switch(o))
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
-- (<cam>Orbit..., <cam>Level, <cam>Zoom...). Vista and fish: the sways round
-- Level beside the slow zoom, from where the camera is.
-- Cozy: half a turn round (180 degrees from where it started) while zooming in to cozyZoomClose,
-- then the same round your front, its zoom drifting about the close-up.
-- Leaving, the zoom goes back to where it began; the turn stays (as theirs
-- do). (Not the same yet: the cozy camera doesn't keep clear of Camp Tents.)
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
		steps = { S("together", { steps = { S("rotate", { deg = 180, secs = 14, way = "random" }),
				On(Set(S("zoom", { to = close, secs = 9 }), z, "cozyZoomClose"), Switch(z)) } }),
			S("together", { steps = { loop, drifts } }) }
	else
		-- (No line-up behind you first: camera follow never turns a camera
		-- while you stand still, so it was only a wait.)
		steps = { S("together", { steps = { loop, ZoomGroup(z) } }) }
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

-- The RP walk and auto-run cameras (walkOrbit, runOrbit): swaying and
-- zooming, and following your turns (<cam>SwingBehind: held, then a glide
-- back behind you <cam>GlideDelay after; auto-run's quicker, and quicker
-- still round corners). Stopping: the zoom goes back. (Not the same yet:
-- auto-run steering lower and closer, and the walk camera handing over to
-- standing still.) No line-up behind you: that leaned on the game's camera
-- follow, which doesn't turn the camera (user, 2026-11-05).
local FOLLOW_OF = { walk = { lazy = 1.6, top = 40, accel = 30, corners = "no" },
	run = { lazy = 1, top = 70, accel = 60, corners = "yes" } }
function MovingCamera(cam)
	local glide = FOLLOW_OF[cam]
	local follow = On(Set(S("follow", { after = Db(cam .. "GlideDelay", cam == "run" and 0.5 or 1.5), lazy = glide.lazy,
		top = glide.top, accel = glide.accel, corners = glide.corners }), cam .. "SwingBehind", cam .. "GlideDelay"),
		Switch(cam .. "SwingBehind"))
	return {
		steps = { S("together", { steps = { SwayLoop(cam .. "Orbit", 0), ZoomGroup(cam .. "Zoom"), follow } }) },
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
	-- The tele camera (a Hearthstone or teleport cast, about 10 seconds): over
	-- 5 seconds, comes down teleLevel as it turns half round (180 degrees) to
	-- the left, building up and ending at full speed (48 degrees a second),
	-- then spins on from that speed for 5 seconds, speeding up by
	-- teleSpinAccel to teleSpinMax, while zooming in to teleZoomClose
	-- (teleZoom). (As the user set it up on retail, 2026-11-05.) A plain 10 seconds, not timed
	-- to the cast: the scene starts it, the script plays as listed, and the
	-- Your cast ends rule ends it with the cast (a quicker one with haste too). Cancelled: it turns back (teleReturn) and zooms back over
	-- teleZoomBackTime.
	{ id = "tele", name = "Tele camera", make = function()
		-- (The turns one after another, beside the zoom over the whole cast: a Repeat once.)
		-- (The tilt down beside the half turn, both at once.)
		local turns = S("repeat", { times = 1, steps = {
			S("together", { steps = { Set(S("tilt", { deg = Db("teleLevel", 15), secs = 5 }), "teleLevel"),
				S("rotate", { deg = 180, secs = 5, way = "left", speedUp = "long", slowDown = "none" }) } }),
			-- (Start: the half turn's speed as it ends, 180 degrees in 5 seconds with
			-- the first half building up: one turn, no change of speed.)
			Set(S("spin", { start = 48, accel = Db("teleSpinAccel", 14), max = Db("teleSpinMax", 120), secs = 5,
				way = "left" }), "teleSpinAccel", "teleSpinMax") } })
		local zoom = On(Set(S("zoom", { to = Db("teleZoomClose", 4), secs = 10 }), "teleZoom", "teleZoomClose"),
			Switch("teleZoom"))
		local back = math.max(0.5, Db("teleZoomBackTime", 0.5))
		return {
			steps = { S("together", { steps = { turns, zoom } }) },
			ending = { Switch("teleReturn") and Set(S("putback", { secs = back }), "teleReturn", "teleZoomBackTime")
				or Set(S("zoom", { to = 0, secs = back, of = "yours" }), "teleReturn", "teleZoomBackTime") },
			rules = { camera = "stop", fight = "putback", walk = "putback", zoom = "ignore", ends = "putback",
				cast = "putback" },
		}
	end },
	-- The flight camera (taxiOrbit, "back" mode): swaying and zooming until it's time to settle (taxiSettle,
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
			steps = { Set(S("until", { what = "landing", secs = settle and Db("taxiSettleLead", 5) + 12 + 3 or 0, steps = {
					cruise } }), "taxiSettle", "taxiSettleLead"),
				On(Set(S("zoom", { to = 0, secs = 3, of = "yours" }), "taxiSettle"), settle),
				On(Set(S("putback", { secs = 12, zoom = "no" }), "taxiSettle"), settle) },
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
		-- (Start after: a wait first, only when it's set: no Wait 0 s.)
		local steps = {}
		if Db("deathOrbitDelay", 0) > 0 then
			steps[1] = Set(S("wait", { secs = Db("deathOrbitDelay", 0) }), "deathOrbitDelay")
		end
		for _, step in ipairs({
				S("together", { steps = { Set(S("tilt", { deg = -Db("deathLevel", 30), secs = 6 }), "deathLevel"),
					Set(S("zoom", { to = Db("deathZoom", 4), secs = 8, of = "yours" }), "deathZoom") } }),
				Set(S("spin", { accel = 2, max = Db("deathOrbitSpeed", 5), secs = 0, way = way }), "deathOrbitSpeed",
					"deathOrbitRandomDir", "deathOrbitRight") }) do steps[#steps + 1] = step end
		return {
			steps = steps,
			ending = { S("putback", { secs = 2 }) },
			rules = { camera = "pause", cameraSecs = 5, fight = "ignore", walk = "ignore", zoom = "ignore", ends = "putback" },
			button = Switch("deathExitButton"),
			ruleSet = { button = { "deathExitButton" } },
		}
	end },
	-- A fly-by (the flight camera's): a /look as it starts (flyByLook), the
	-- flight's turns undone, round flyByAngle over flyByTurnTime, looking back
	-- flyByHold, then its turns undone again over flyByBackTime.
	{ id = "flyby", name = "Fly-by", make = function()
		return {
			steps = { On(Set(S("emote", { token = "look" }), "flyByLook"), Switch("flyByLook")),
				S("wait", { secs = 1 }), S("putback", { secs = 1.5, zoom = "no" }),
				Set(S("rotate", { deg = Db("flyByAngle", 160), secs = Db("flyByTurnTime", 8), way = "random" }), "flyByAngle",
					"flyByTurnTime"),
				Set(S("wait", { secs = Db("flyByHold", 5) }), "flyByHold"),
				Set(S("putback", { secs = Db("flyByBackTime", 6), zoom = "no" }), "flyByBackTime") },
			ending = {},
			rules = { camera = "stop", fight = "stop", walk = "stop", zoom = "ignore", ends = "stop" },
		}
	end },
	-- Skyriding (retail, the Skyriding Cam page, SkyrideCam.lua):
	-- out to skyrideCamDistance over skyrideCamZoomTime as you take to the
	-- air, back over skyrideCamBackTime once you've landed. (Steering doesn't
	-- stop it, nor walking: see Start's travel.)
	{ id = "skyride", name = "Skyriding zoom", retail = true, make = function()
		return {
			steps = { S("together", { steps = {
				On(Set(S("zoom", { to = Db("skyrideCamDistance", 20), secs = Db("skyrideCamZoomTime", 4),
					past = "yes" }), "skyrideCamZoomOut", "skyrideCamDistance", "skyrideCamZoomTime"),
					Switch("skyrideCamZoomOut")),
				-- (Follow your turns, as the auto-run camera's: SkyrideCam.lua's moments carry it on.)
				On(Set(S("follow", { after = Db("skyrideFollowAfter", 0.5), lazy = 1, top = 70, accel = 60,
					corners = "yes", most = Db("skyrideFollowMost", 50) }), "skyrideFollow", "skyrideFollowAfter",
					"skyrideFollowMost"),
					Switch("skyrideFollow")) } }) },
			ending = { Set(S("putback", { secs = Db("skyrideCamBackTime", 3),
				zoom = Switch("skyrideCamZoomBack") and "yes" or "no" }), "skyrideCamBackTime", "skyrideCamZoomBack") },
			rules = { camera = "pause", cameraSecs = 3, fight = "putback", walk = "ignore", zoom = "ignore",
				ends = "putback" },
		}
	end },
	-- The quest cam (once its row's wait is over: QuestCam.lua's
	-- ns.QuestTalkNow): in to questCamDistance, then questCamAngle
	-- round to the side over questCamTurnTime (questCamSide: where you clicked
	-- them, at random, or always one way), down questCamLower, then a slow
	-- drift to and fro of questCamDrift about there. The zooms go at
	-- questCamZoomSpeed and questCamZoomOutSpeed (0: it stays in), taking
	-- questCamZoomMaxTime at most. Leaving, it all goes back, once you've walked
	-- off, with another quest giver near (QuestCam.lua's cam.held).
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
			-- (No swing behind you while it zooms in: camera follow never turns a
			-- camera while you stand still.)
			steps = { Set(S("zoom", { to = Db("questCamDistance", 4), secs = Db("questCamZoomMaxTime", 8),
					speed = Db("questCamZoomSpeed", 0.5) }), "questCamDistance", "questCamZoomSpeed", "questCamZoomMaxTime"),
				On(Set(turn, "questCamAngle", "questCamTurnTime", "questCamSide"), angle > 0),
				On(Set(S("tilt", { deg = Db("questCamLower", 0), secs = 2 }), "questCamLower"), Db("questCamLower", 0) ~= 0),
				On(Set(S("repeat", { times = 0, steps = {
					S("rotate", { deg = math.max(1, drift), secs = 7, way = "left", ease = "gentle" }),
					S("rotate", { deg = math.max(1, drift), secs = 7, way = "right", ease = "gentle" }) } }), "questCamDrift"),
					drift > 0) },
			ending = ZoomOutEnding("questCam"),
			-- (Walking: its trigger says, QuestCam.lua's ns.QuestTalkNow. It stays
			-- on as you walk to another quest giver, a few steps away.)
			rules = { camera = "stop", fight = "putback", walk = "ignore", zoom = "stop", ends = "putback" },
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
-- (Skyriding's only where there's skyriding: retail.)
if not (ns.isRetail and C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then
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

-- The seconds of the first End music step in a list of steps (groups too,
-- not ones switched off), or nil.
local function EndMusicIn(list)
	for _, step in ipairs(type(list) == "table" and list or {}) do
		if type(step) == "table" and not step.off then
			if step.k == "endMusic" then return tonumber(step.secs) or 0 end
			local inside = EndMusicIn(step.steps)
			if inside then return inside end
		end
	end
end

-- A built-in camera's End music in your edit of its When it ends: the
-- camera itself still runs its own code (not the script, outside the dev
-- copy's /cine script builtins), so Effects.lua ends the music as it ends.
function ns.BuiltinEndMusicSecs(id)
	local edits = BuiltinEdits()
	local script = edits and edits[id]
	return type(script) == "table" and EndMusicIn(script.ending) or nil
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

-- Our cameras play their scripts: a row set to one of our cameras runs that
-- camera's script (CameraRows.lua's ns.TriggerSetting asks), so your edits
-- to a built-in script are what plays. The Scenes page still shows the
-- camera. (Dev copy: /cine script builtins switches back to the cameras' own
-- code, db.scriptBuiltIns false, to compare.)
local BUILT_IN_OF = { cozy = "cozy", vista = "vista", fish = "fish", afk = "afk", tele = "tele", flight = "flight",
	walk = "walk", run = "run", quest = "quest", chat = "chat", [true] = "death", death = "death" }
function ns.ScriptBuiltInsOn()
	return ns.db ~= nil and not (ns.isDev and ns.db.scriptBuiltIns == false)
end
function ns.BuiltInAsScript(value)
	local id = BUILT_IN_OF[value]
	return id and "script:" .. id or value
end
-- The camera a built-in script stands in for, by its key in ns.activeCam
-- ("idle", "fish", "chatcam"...): from a script id or a "script:<id>" value.
-- nil for any other script (yours, the fly-by, Skyriding).
local CAMERA_KEY_OF = { afk = "idle", cozy = "cozy", vista = "vista", fish = "fish", tele = "tele", flight = "flight",
	walk = "walk", run = "run", quest = "quest", chat = "chatcam", death = "death" }
function ns.ScriptStandIn(value)
	if type(value) ~= "string" then return nil end
	return CAMERA_KEY_OF[value:match("^script:(.+)$") or value]
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
		-- (Not the Skyriding Cam page's own: that page plays it, no scene.)
		if script.id ~= "skyride" then values[#values + 1] = value end
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
-- (One of ours: the rows set to its camera too, which play it.)
function ns.CameraScriptTriggers(id)
	local value, keys, seen = "script:" .. id, {}, {}
	local builtins = ns.ScriptBuiltInsOn()
	for _, row in ipairs(ns.CameraRowOrder()) do
		local trigger = ns.CameraRowTrigger(row)
		local camera = trigger and ns.CameraRowValue(row, "camera")
		if builtins then camera = ns.BuiltInAsScript(camera) end
		if trigger and not seen[trigger.key] and camera == value then
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

-- An ease's ramps, as shares of the move: speeding up, slowing down.
local function Ramps(ease)
	if type(ease) == "table" then return ease[1], ease[2] end
	return ease, ease
end
-- The share of a move's time it would take at full speed throughout: its
-- full speed is the distance over T times this.
local function Flat(ease)
	local up, down = Ramps(ease)
	return 1 - (up + down) / 2
end
-- An ease with neither ramp longer than most's.
local function ShorterEase(ease, most)
	local up, down = Ramps(ease)
	return { math.min(up, most), math.min(down, most) }
end

-- Share (0-1) of a move covered at t along T seconds, with half-cosine
-- ramps at either end (as QuestCam.lua's EaseProgress; one end only for in
-- and out).
local function EaseProgress(t, T, ease)
	if t <= 0 then return 0 end
	if t >= T then return 1 end
	local up, down = Ramps(ease)
	local A, B = up * T, down * T
	local total = T - (A + B) / 2
	if total <= 0 then return t / T end
	local function ramp(u, R)
		if R <= 0 then return u end
		return u / 2 - R / (2 * math.pi) * math.sin(math.pi * u / R)
	end
	local covered
	if t < A then
		covered = ramp(t, A)
	elseif t <= T - B then
		covered = A / 2 + (t - A)
	else
		covered = total - ramp(T - t, B)
	end
	return covered / total
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
	local up, down = Ramps(ease)
	local A, B = up * T, down * T
	if A > 0 and t < A then
		return (1 - math.cos(math.pi * t / A)) / 2
	elseif B > 0 and t > T - B then
		return (1 - math.cos(math.pi * (T - t) / B)) / 2
	end
	return 1
end

-- How far a speed curve goes in T seconds (degrees).
local function CurveDistance(curve, T)
	local sum, dt = 0, 0.05
	for t = dt / 2, T, dt do sum = sum + curve(t) * dt end
	return sum
end

-- A sway's turn from amount: a random spot within its arc of center (where
-- it was as the sway first ran), at least min from where it is, the shorter
-- way (as Camera.lua's PickBackTarget, and the vista and fish cameras'
-- leaning toward the middle with favor). random: math.random or the plan's own.
local function SwayTurn(step, amount, random, center)
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
local function SwayCurve(step, delta, from, center)
	local v, P = step.drift, step.pause
	if v <= 0 or P <= 0 or math.abs(delta) < 0.5 then return nil end
	local T, e = step.secs, EASES[step.ease]
	local c = math.abs(delta) / (T * (1 - e))
	local R = e * T
	local dir = delta >= 0 and 1 or -1
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
	local accel, top, from = step.accel, step.max, step.start
	return function(t) return math.min(top, from + accel * t) end
end

-- A Zoom's yards (Random: somewhere from to to max, picked now), a Random
-- Tilt's height from where the scene started (deg, give or take up and
-- down), a Wait's seconds (Random: secs to max). random: math.random or
-- the plan's own.
local function ZoomYards(step, random)
	if step.rand ~= "between" then return step.to end
	local low, high = math.min(step.to, step.max), math.max(step.to, step.max)
	return low + random() * (high - low)
end
local function TiltTarget(step, random)
	return step.deg - step.up + random() * (step.up + step.down)
end
local function WaitSecs(step, random)
	if step.rand ~= "between" then return step.secs end
	local low, high = math.min(step.secs, step.max), math.max(step.secs, step.max)
	return low + random() * (high - low)
end

local function ZoomGoal(step, yards, startZoom)
	if step.of == "yours" then yards = startZoom + yards end
	return math.max(0.5, math.min(50, yards))
end
-- A zoom's seconds from distance yards: its own, or (speed) shorter if its
-- top speed gets there sooner.
local function ZoomSecs(step, secs, distance)
	if step.speed <= 0 then return secs end
	return math.min(secs, math.abs(distance) / (step.speed * Flat(StepEase(step))))
end
-- An Aim at's seconds for a turn: its own, or (speed) longer if the turn
-- would go faster than that.
local function AimSecs(step, turn)
	if step.speed <= 0 then return step.secs end
	return math.max(step.secs, math.abs(turn) / (step.speed * Flat(StepEase(step))))
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
	local plays = 0 -- (Play steps inside each other)
	local swayCenters = {} -- (each sway's middle: where it was as it first ran)
	local stepNow -- (the step whose moves these are, for CameraStepSpeeds)
	local One
	local function Run(list, t, top)
		for _, step in ipairs(list) do t = One(step, t, top or step) end
		return t
	end
	local function Move(axis, to, t, secs, ease, top)
		secs = math.max(MOVE_MIN_TIME, secs or 0)
		moves[#moves + 1] = { axis = axis, from = state[axis], to = to, t0 = t, t1 = t + secs, ease = ease, top = top,
			step = stepNow }
		state[axis] = to
		return t + secs
	end
	local function Hold(t, secs, top)
		moves[#moves + 1] = { axis = "none", t0 = t, t1 = t + secs, top = top }
		return t + secs
	end
	-- (A turn along a speed curve: where it is at each moment is worked out as it's drawn.)
	local function Curve(growing, curve, t, secs, top)
		local dist = CurveDistance(curve, secs)
		moves[#moves + 1] = { axis = "yaw", from = state.yaw, to = state.yaw + (growing and dist or -dist), t0 = t,
			t1 = t + secs, curve = curve, sign = growing and 1 or -1, top = top, step = stepNow }
		state.yaw = state.yaw + (growing and dist or -dist)
		return t + secs
	end
	function One(step, t, top)
		stepNow = step
		local from, ending = t, t
		local k = not step.off and step.k
		if k == "rotate" then
			local way = Way(step, Random, onceLeft)
			ending = Move("yaw", state.yaw + (way == "left" and step.deg or -step.deg), t, step.secs, StepEase(step), top)
		elseif k == "tilt" and step.rand == "give" then
			ending = Move("pitch", start.pitch + TiltTarget(step, Random), t, step.secs, StepEase(step), top)
		elseif k == "tilt" then
			ending = step.deg ~= 0 and Move("pitch", state.pitch + step.deg, t, step.secs, StepEase(step), top) or t
		elseif k == "zoom" then
			local goal = ZoomGoal(step, ZoomYards(step, Random), start.zoom)
			ending = Move("zoom", goal, t, ZoomSecs(step, step.secs, goal - state.zoom), StepEase(step), top)
		elseif k == "sway" then
			swayCenters[step] = swayCenters[step] or state.yaw
			local center = swayCenters[step]
			local delta = SwayTurn(step, state.yaw, Random, center)
			local curve, secs, _, still = SwayCurve(step, delta, state.yaw, center)
			if curve then
				ending = Curve(delta >= 0, curve, t, secs, top)
				if still > 0 then ending = Hold(ending, still, top) end
			else
				ending = Move("yaw", state.yaw + delta, t, step.secs, EASES[step.ease], top)
				if step.pause > 0 then ending = Hold(ending, step.pause, top) end
			end
		elseif k == "spin" then
			local secs = step.secs > 0 and step.secs or 20
			ending = Curve(Way(step, Random, onceLeft) == "left", SpinCurve(step), t, secs, top)
		elseif k == "wait" then
			-- (The preview can't know when a cast ends or you land: a stand-in time.)
			local secs = step.what == "time" and WaitSecs(step, Random) or PREVIEW_UNTIL[step.what] or 10
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
			end
			ending = Hold(t, secs, top)
		elseif k == "aim" then
			-- (Either side at random: the preview can't know where they are.)
			local turn = step.at == "click" and step.deg
				or math.min(AIM_MOST, math.max(0, PREVIEW_SPEAKER - step.deg) / AIM_GAIN)
			if Random() < 0.5 then turn = -turn end
			ending = math.abs(turn) >= 0.5 and Move("yaw", state.yaw + turn, t, AimSecs(step, turn), StepEase(step), top)
				or t
		elseif k == "putback" then
			local turned = Move("yaw", state.yaw - Wrap(state.yaw), t, step.secs, 0.5, top)
			if step.zoom == "yes" then Move("zoom", start.zoom, t, step.secs, EASES.gentle, top) end
			ending = math.max(turned, Move("pitch", start.pitch, t, step.secs, 0.5, top))
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
-- A planned move's speed t seconds in (degrees, or yards, a second), and
-- its way (1 or -1).
local function PlannedSpeed(move, t)
	if move.curve then return math.max(0, move.curve(t)) end
	local T, dist = move.t1 - move.t0, math.abs(move.to - move.from)
	if T <= 0 or dist == 0 then return 0 end
	local ease = move.ease or 0.5
	return dist / (T * Flat(ease)) * EaseShape(t, T, ease)
end
local function PlannedWay(move)
	if move.curve then return move.sign end
	return move.to >= move.from and 1 or -1
end

-- For a step's speed graph (the Scripts page): its move in the plan, as
-- { axis, T (seconds), Speed(t) its own speed, from: the speed of the turn
-- before it that hands straight over to it (the same axis, the same way,
-- ending at speed just as it starts; nil for none: Speed match does
-- nothing then) }. Repeated, the first time it's handed over to (else its
-- first). nil: no move of its own.
local HANDOVER_AT = 0.02 -- seconds: a move ending this close to another's start hands over to it
function ns.CameraStepSpeeds(plan, step)
	if not plan then return nil end
	local first, fed, from
	for _, move in ipairs(plan.moves) do
		if move.step == step and move.axis ~= "none" then
			first = first or move
			for _, before in ipairs(plan.moves) do
				if before ~= move and before.axis == move.axis and math.abs(before.t1 - move.t0) < HANDOVER_AT
					and PlannedWay(before) == PlannedWay(move) then
					local speed = PlannedSpeed(before, before.t1 - before.t0 - 0.001)
					if speed > MIN_SPEED then
						fed, from = move, speed
						break
					end
				end
			end
			if fed then break end
		end
	end
	local move = fed or first
	if not move then return nil end
	return { axis = move.axis, T = move.t1 - move.t0, from = from,
		Speed = function(t) return PlannedSpeed(move, t) end }
end

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
for _, m in pairs(movers) do m.lastStop = -math.huge end -- (when its last move stopped)

local function Command(m)
	return m.growing and m.grow or m.shrink
end

-- Follow your turns (STEP.follow): its own turn of the view, outside the
-- yaw mover. drive: what it has the game doing (moving, left, speed: the
-- MoveView amount sent, at).
local follower = { drive = { moving = false }, offset = 0, glide = 0, rate = 0, starts = {},
	lastTurnAt = -math.huge, lastAnyTurnAt = -math.huge }

-- A move's start stops the other axis's move in the game (a tilt held the
-- turn), and its stop may too: sent again then, at the speed it's going, as Camera.lua's orbit
-- keeps both going in one sweep. (Handed over, still turning: the same.)
local function Resend(m)
	local o = m.other
	local drive = follower.drive
	if o == movers.yaw and drive.moving then -- (Follow your turns has the turn)
		Send((drive.left and o.grow or o.shrink) .. "Start", drive.speed)
		return
	end
	if o.held then
		Send((o.held.growing and o.grow or o.shrink) .. "Start", o.held.share)
		return
	end
	if not o.moving then return end
	if o.sent then
		Send(Command(o) .. "Start", o.share)
	elseif o.creeping then
		Send(Command(o) .. "Start", PRIME_SHARE)
	end
end

-- Your speed setting back, a moment after a move stopped (now: at once).
local function Release(m, now)
	if now then
		ns.ReleaseSpeed(m.who, m.cvar)
		return
	end
	restoring = restoring + 1
	C_Timer.After(RESTORE_DELAY, function()
		restoring = restoring - 1
		if not (m.moving or m.held) then ns.ReleaseSpeed(m.who, m.cvar) end
	end)
end

-- Handover: a turn or tilt done, the game's move is left going a frame
-- (m.held: its way, speed setting and share), in case the next step turns
-- the same way at once; Begin then carries it on at a new speed, with no
-- stop, no STEP_GAP and no creep start. Nothing taking it over: DropHeld.
local function DropHeld(m, now)
	m.keepHeld = nil
	local held = m.held
	if not held then return end
	m.held = nil
	Send((held.growing and m.grow or m.shrink) .. "Stop")
	Resend(m)
	m.lastStop = GetTime()
	Release(m, now)
end

-- (now: you took the camera, your speed back this moment, not after a wait.
-- keepHeld: a new move for this axis, which may take over a handed-over one.)
local function StopMove(m, now, keepHeld)
	m.pending = false
	if not keepHeld then DropHeld(m, now) end
	if not m.moving then return end
	if m.sent or m.creeping then
		Send(Command(m) .. "Stop")
		Resend(m)
	end
	m.moving, m.sent, m.creeping = false, nil, nil
	m.lastStop = GetTime()
	Release(m, now)
end

-- A move come to its end by itself: handed over (see DropHeld) if it's
-- really going, else stopped.
local function EndMove(m)
	if not (m.moving and m.sent and m.share) then
		StopMove(m)
		return
	end
	m.held = { growing = m.growing, sent = m.sent, share = m.share }
	m.moving, m.sent, m.creeping, m.pending = false, nil, nil, false
end

-- Moves to target degrees over T seconds (it sets off once it can: see
-- Begin). blend: seconds sliding in from a handed-over move's speed.
local function MoveTo(m, target, T, ease, blend)
	StopMove(m, nil, true)
	m.blend = blend or 0
	m.suspended, m.curve = nil, nil
	m.target, m.t, m.T, m.ease = target, 0, math.max(MOVE_MIN_TIME, T or 0), ease or EASES.smooth
	m.pending = math.abs(target - m.amount) >= 0.5
end

-- A move along a speed curve instead: curve(t) degrees a second (top: its
-- fastest), growing or not, for T seconds; it goes as far as that takes it.
local function MoveCurve(m, growing, curve, T, top, blend)
	StopMove(m, nil, true)
	m.blend = blend or 0
	m.suspended = nil
	m.curve, m.top, m.curveGrowing, m.t, m.T = curve, math.max(0.05, top), growing, 0, T
	m.target = m.amount + (growing and 1 or -1) * 1e6 -- (never reached: the time ends it)
	m.pending = T > 0
end

-- Sets a pending move off: not within STEP_GAP of this axis's last move
-- stopping, nor without the view.
local function Begin(m)
	if m.blocked then return end -- (Follow your turns has the turn: this one waits)
	local now = GetTime()
	m.keepHeld = nil
	local held = m.held
	if held then
		-- (Handed over: the same way carries straight on, the other way stops first.)
		local growing
		if m.curve then growing = m.curveGrowing else growing = m.target > m.amount end
		if growing ~= held.growing or not ns.ClaimCamera(WHO) then DropHeld(m) end
	end
	if not m.held and (now - m.lastStop < STEP_GAP or not ns.ClaimCamera(WHO)) then return end
	local yours = ns.HoldSpeed(m.who, m.cvar)
	if m.curve then
		m.share = m.top / yours
		m.growing = m.curveGrowing
	else
		m.cruise = math.abs(m.target - m.amount) / (m.T * Flat(m.ease))
		m.share = m.cruise / yours
		m.growing = m.target > m.amount
	end
	if m.held then
		-- On at the speed it was going (Speed match, its blend field, slides from it; else this
		-- move's own speed from the next frame), sent with this move's share.
		local speed = held.sent * held.share
		m.held = nil
		m.blendFrom = speed
		m.sent = math.max(MIN_SETTING, speed / m.share)
		m.pending, m.creeping, m.moving, m.t, m.primedUntil = false, nil, true, 0, 0
		ns.SetHeldSpeed(m.who, m.cvar, m.sent)
		Send(Command(m) .. "Start", m.share)
		Resend(m)
		return
	end
	m.blendFrom = nil
	ns.SetHeldSpeed(m.who, m.cvar, MIN_SETTING)
	m.primedUntil = now + PRIME_TIME
	m.pending = false
	if Send(Command(m) .. "Start", PRIME_SHARE) then
		m.creeping, m.moving, m.sent, m.t = true, true, nil, 0
		Resend(m)
	else
		m.pending = true
		ns.ReleaseSpeed(m.who, m.cvar)
	end
end

-- A move come to its end in a frame of its own: handed over still going, the
-- game turns it this frame too, so it's counted (the next frame's count goes
-- to whatever takes it over, or comes off as it's stopped: StepMove).
local function EndInFrame(m, elapsed)
	if m.moving and m.sent and m.share then
		m.amount = m.amount + (m.growing and 1 or -1) * m.sent * m.share * elapsed
	end
	EndMove(m)
end

local function StepMove(m, elapsed)
	local held = m.held
	if held then
		-- (Still going in the game: counted on. Nothing took it over last frame: stopped.)
		local speed = held.sent * held.share
		local step = (held.growing and speed or -speed) * elapsed
		m.amount = m.amount + step
		-- (keepHeld: steps played in place of the script's own, not begun yet:
		-- a frame more for them to take it over, CameraScriptPlaySteps.)
		if not m.pending then
			if m.keepHeld then
				m.keepHeld = nil
			else
				DropHeld(m)
				m.amount = m.amount - step -- (stopped this frame: the game doesn't move it)
			end
		end
	end
	if m.pending then
		Begin(m)
		-- (Not taken over, the other way: stopped this frame, not moved.)
		if held and not m.held and m.lastStop == GetTime() then
			m.amount = m.amount - (held.growing and 1 or -1) * held.sent * held.share * elapsed
		end
		return
	end
	if not m.moving or GetTime() < m.primedUntil then return end
	m.t = m.t + elapsed
	local speed
	if m.curve then
		if m.t >= m.T then
			EndInFrame(m, elapsed)
			return
		end
		speed = math.max(0, m.curve(m.t))
	else
		if (m.target > m.amount) ~= m.growing or math.abs(m.target - m.amount) < 0.05 or m.t > m.T + 3 then
			EndInFrame(m, elapsed)
			return
		end
		speed = math.max(MIN_SPEED, m.cruise * EaseShape(math.min(m.t, m.T), m.T, m.ease))
	end
	-- (Speed match, blend: from the handed-over move's speed to this one's, over blend seconds.)
	if m.blendFrom and m.blend > 0 and m.t < m.blend then
		speed = m.blendFrom + (speed - m.blendFrom) * EaseShape(m.t, 2 * m.blend, 0.5)
	end
	local setting = math.max(MIN_SETTING, speed / m.share)
	if not m.sent then
		Send(Command(m) .. "Start", m.share)
		m.sent = MIN_SETTING
		Resend(m)
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

-- One mover's move put off, what's left of it kept to carry on with (now:
-- your speed back this moment); and carried on.
local function SuspendMover(m, now)
	if m.pending or m.moving then
		m.suspended = { target = m.target, T = math.max(MOVE_MIN_TIME, (m.T or 0) - (m.t or 0)), curve = m.curve,
			at = m.t or 0, total = m.T, top = m.top, growing = m.curveGrowing }
		StopMove(m, now)
	elseif m.held then
		DropHeld(m, now)
	end
end
local function ResumeMover(m)
	local left = m.suspended
	if left and left.curve then
		-- (On along its curve from where it was: the rest of it, eased in again over a second.)
		local at, curve = left.at, left.curve
		MoveCurve(m, left.growing, function(t) return curve(at + t) * math.min(1, t) end, left.total - at, left.top)
	elseif left then
		MoveTo(m, left.target, left.T, m.ease)
	end
end

-- ---------------------------------------------------------------------------
-- Follow your turns (KINDS.follow), as Camera.lua's UpdateTurnFollow: offset
-- is how far the view is from behind you (degrees, left positive), rate
-- your turn speed (smoothed), glide the speed gliding it back.
-- ---------------------------------------------------------------------------
local FOLLOW_TURN_RATE = 20   -- degrees a second: turning faster than this is a turn
local FOLLOW_ARM = 0.6        -- seconds of not turning before it takes a turn (not one already under way)
local FOLLOW_SMOOTH = 0.08    -- seconds of smoothing on your turn speed's jitter
local FOLLOW_JUMP = 15        -- degrees a second: bigger changes are followed at once
local FOLLOW_DONE = 0.5       -- degrees: close enough to behind you
local FOLLOW_BRAKE = 0.8      -- share of the full stopping speed allowed (some slack)
local FOLLOW_BURST, FOLLOW_BURST_SECS = 3, 4 -- turns started within these seconds: steering
local FOLLOW_STEER_AFTER, FOLLOW_STEER_BOOST = 0.3, 1.5 -- steering: glide after this at most, this much quicker
local FOLLOW_SMALL, FOLLOW_PER, FOLLOW_BOOST_MAX, FOLLOW_GENTLE = 15, 50, 1.5, 0.5 -- corners (Camera.lua's TURN_SIZE_*)

local function StopFollowDrive()
	local drive = follower.drive
	if not drive.moving then return end
	local m = movers.yaw
	Send((drive.left and m.grow or m.shrink) .. "Stop")
	drive.moving = false
	Resend(m) -- (the tilt, if one's going)
end

-- The view turned at cmd degrees a second (left positive), as Camera.lua's
-- MoveAxis: restarted only for changes that show.
local function DriveFollow(cmd)
	local drive, m = follower.drive, movers.yaw
	-- (By your turn speed setting, which TakeYaw puts back: worked out from
	-- a held one, it would spin as yours came back.)
	local base = ns.YourSpeed and ns.YourSpeed(m.cvar) or tonumber(GetCVar(m.cvar)) or 180
	local speed = math.abs(cmd) / math.max(1, base)
	if math.abs(cmd) < 0.1 then
		StopFollowDrive()
		return
	end
	local left = cmd > 0
	if drive.moving and drive.left ~= left then StopFollowDrive() end
	local now = GetTime()
	if drive.moving then
		local change = math.abs(speed - drive.speed)
		if change <= drive.speed * 0.02 or (now - drive.at < 0.05 and change <= drive.speed * 0.3) then return end
	end
	if Send((left and m.grow or m.shrink) .. "Start", speed) then
		drive.moving, drive.left, drive.speed, drive.at = true, left, speed, now
		Resend(m)
	else
		drive.moving = false
	end
end

-- The script's other turns wait while it glides (theirs put off, your speed
-- setting back at once: its own turn goes by yours), and carry on after.
local function TakeYaw()
	if follower.took then return end
	follower.took = true
	local m = movers.yaw
	SuspendMover(m, true)
	m.blocked = true
	ns.ReleaseSpeed(m.who, m.cvar) -- (a move just ended holds it a moment more: Release)
end
local function GiveYaw()
	if not follower.took then return end
	follower.took = false
	movers.yaw.blocked = nil
	ResumeMover(movers.yaw)
end

-- Let go: its turn stopped where it is, the others carry on (resume: from
-- where they were; else they're stopped or put off by the caller).
local function ReleaseFollow(resume)
	StopFollowDrive()
	follower.offset, follower.glide, follower.rate = 0, 0, 0
	if resume then
		GiveYaw()
	else
		follower.took, movers.yaw.blocked = false, nil
	end
end
-- Stopped, paused or ended: let go, and start afresh next time (a stale
-- facing would read as a big turn).
local function StopFollow()
	ReleaseFollow(false)
	follower.lastFacing, follower.armed, follower.carry = nil, false, nil
end

local function FollowFrame(step, dt)
	local f = follower
	local now = GetTime()
	-- Your turn this frame (degrees, left positive; 0 with the facing hidden).
	local turned = 0
	local ok, facing = pcall(GetPlayerFacing)
	if ok and type(facing) == "number" and not (issecretvalue and issecretvalue(facing)) then
		if f.lastFacing and dt > 0 then
			turned = math.deg((facing - f.lastFacing + math.pi) % (2 * math.pi) - math.pi)
		end
		f.lastFacing = facing
	else
		f.lastFacing = nil
	end
	local turning = (ns.TurnKeyHeld and ns.TurnKeyHeld()) or (dt > 0 and math.abs(turned) / dt > FOLLOW_TURN_RATE)
	-- Steering: several turns started in quick succession.
	if turning and not f.wasTurning then f.starts[#f.starts + 1] = now end
	f.wasTurning = turning
	while f.starts[1] and now - f.starts[1] > FOLLOW_BURST_SECS do table.remove(f.starts, 1) end
	local steering = step.steer == "yes" and #f.starts >= FOLLOW_BURST
	if turning then f.lastAnyTurnAt = now end
	-- (The mouse on the camera, or steering with it: mouselook keeps the
	-- camera behind you.) Only taking a turn once you've stopped turning a
	-- moment: catching one under way would stop the camera dead mid-swing.
	local allowed = not (ns.IsMouseOnCamera and ns.IsMouseOnCamera()) and not ns.mouseSteering
	if not allowed then
		f.armed = false
	elseif not f.armed and now - f.lastAnyTurnAt >= FOLLOW_ARM then
		f.armed = true
	end
	if not (allowed and f.armed) then
		if f.took or f.offset ~= 0 then ReleaseFollow(true) end
		return
	end
	-- Your turn speed, smoothed (the raw figure jitters with frame times);
	-- starting, stopping or reversing followed at once.
	local measured = dt > 0 and turned / dt or 0
	local diff = measured - f.rate
	if math.abs(diff) > math.max(FOLLOW_JUMP, math.abs(f.rate) * 0.15) then
		f.rate = measured
	else
		f.rate = f.rate + diff * math.min(1, dt / FOLLOW_SMOOTH)
	end
	if measured == 0 and math.abs(f.rate) < 1 then f.rate = 0 end
	local after = steering and math.min(step.after, FOLLOW_STEER_AFTER) or step.after
	if turning then
		f.glide, f.lastTurnAt = 0, now -- (held until the turn ends)
	elseif f.glide == 0 and now - f.lastTurnAt < after then
		-- (Just stopped turning: held a moment longer, in case of more.)
	elseif math.abs(f.offset) > FOLLOW_DONE or f.glide ~= 0 then
		-- The glide: the further off, the quicker, capped, its speed eased.
		local lazy, top, accel = step.lazy, step.top, step.accel
		if steering then
			lazy, top, accel = lazy / FOLLOW_STEER_BOOST, top * FOLLOW_STEER_BOOST, accel * FOLLOW_STEER_BOOST
		end
		if step.corners == "yes" then
			local size = math.abs(f.offset)
			local boost = size < FOLLOW_SMALL and FOLLOW_GENTLE + (1 - FOLLOW_GENTLE) * size / FOLLOW_SMALL
				or 1 + math.min(FOLLOW_BOOST_MAX, (size - FOLLOW_SMALL) / FOLLOW_PER)
			lazy, top, accel = lazy / boost, top * boost, accel * boost
		end
		local target = math.max(-top, math.min(top, -f.offset / lazy))
		-- (Always room to stop: no faster than it can brake in the distance left.)
		local brake = math.sqrt(2 * accel * math.abs(f.offset)) * FOLLOW_BRAKE
		target = math.max(-brake, math.min(brake, target))
		local stepBy = accel * dt
		f.glide = f.glide + math.max(-stepBy, math.min(stepBy, target - f.glide))
	end
	-- The view's offset from your facing: the counter-turn plus the glide,
	-- the short way round (a full spin leaves it where it was).
	local rate = -f.rate + f.glide
	local offset = ((f.offset + rate * dt) + 180) % 360 - 180
	local most = step.most or 0
	if most > 0 and math.abs(offset) > most and dt > 0 then
		offset = math.max(-most, math.min(most, offset))
		rate = (offset - f.offset) / dt
	end
	f.offset = offset
	if f.rate == 0 and math.abs(f.offset) <= FOLLOW_DONE and math.abs(f.glide) < 2 then
		if f.took or f.offset ~= 0 then ReleaseFollow(true) end
		return
	end
	TakeYaw()
	-- (Flipped: the camera's "left" turns the view as turning you right does.)
	DriveFollow(-rate)
	if follower.drive.moving then movers.yaw.amount = movers.yaw.amount - rate * dt end
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

local function StopZoom(now)
	zoomer.pending = false
	if now and zoomer.release then -- (easing back: yours now)
		zoomer.release, zoomer.sent = nil, nil
		ns.ReleaseSpeed(ZOOM_WHO, ZOOM_CVAR)
	end
	if not zoomer.moving then return end
	zoomer.moving = false
	local yours = ns.SpeedHeld(ZOOM_CVAR, ZOOM_WHO) and ns.YourSpeed(ZOOM_CVAR)
	if not now and yours and zoomer.sent and yours > zoomer.sent then
		zoomer.release = { from = zoomer.sent, to = yours, t = 0 }
	else
		zoomer.sent = nil
		ns.ReleaseSpeed(ZOOM_WHO, ZOOM_CVAR)
	end
end

-- (ease: the share of it spent speeding up and slowing down, gentle unless
-- given. As short as ZOOM_MIN_TIME: a zoom can snap out, Skyriding Cam's
-- Whirling Surge, where a turn or tilt that quick would jerk.)
local ZOOM_MIN_TIME = 0.5
local function ZoomTo(distance, T, ease)
	StopZoom()
	zoomer.suspended = nil
	local now = Zoom()
	if math.abs(distance - now) < ZOOM_DONE then return end
	zoomer.goal, zoomer.T, zoomer.ease = distance, math.max(ZOOM_MIN_TIME, T or 0), ease or EASES.gentle
	zoomer.pending = true
end

local function BeginZoom()
	if not ns.ClaimCamera(WHO, ns.zoomWhileSteering[WHO]) then return end
	local now = Zoom()
	-- (Blend: a zoom handed straight over to this one, the same way: its speed
	-- slides from that one's, CameraScriptPlaySteps.)
	local from = zoomer.handover
	zoomer.handover, zoomer.blendFrom = nil, nil
	if from and GetTime() - from.at < 0.5 and (zoomer.goal > now) == from.out then
		-- (Its path up to speed quickly too, not from a standstill.)
		-- (At most half the zoom: a short one blended its whole way never got up to speed.)
		from.secs = math.min(from.secs, zoomer.T * 0.5)
		zoomer.blendFrom, zoomer.ease = from, ShorterEase(zoomer.ease, EASES.steady)
	end
	zoomer.release, zoomer.yours = nil, nil
	ns.HoldSpeed(ZOOM_WHO, ZOOM_CVAR)
	zoomer.from, zoomer.t = now, 0
	zoomer.cruise = math.abs(zoomer.goal - now) / (zoomer.T * Flat(zoomer.ease))
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
	local blend = zoomer.blendFrom
	if blend and t < blend.secs then
		speed = blend.speed + (speed - blend.speed) * EaseShape(t, 2 * blend.secs, 0.5)
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
	StopFollow()
	StopMove(movers.yaw)
	StopMove(movers.pitch)
	movers.yaw.suspended, movers.pitch.suspended = nil, nil
	StopZoom()
	zoomer.suspended = nil
end

-- Paused: each move stopped, what's left of it kept to carry on with (now:
-- you took the camera, every speed yours this moment).
local function Suspend(now)
	StopFollow() -- (a turn it put off stays put off, for Resume)
	for _, m in pairs(movers) do SuspendMover(m, now) end
	if zoomer.pending or zoomer.moving then
		zoomer.suspended = { goal = zoomer.goal, T = math.max(MOVE_MIN_TIME, zoomer.T - (zoomer.t or 0)), ease = zoomer.ease }
	end
	StopZoom(now)
end

-- Your own camera input: the running totals of the turn and tilt start
-- again from where you leave the camera (the game never says how far you
-- turned it), so Undo its turns takes back only what the scene turns from
-- here, and a sway's middle is picked again. A move put off meanwhile
-- keeps the rest of its turn.
local function ForgetTurns()
	for _, m in pairs(movers) do
		local off = m.amount
		m.amount = 0
		if m.target then m.target = m.target - off end
		if m.suspended and m.suspended.target then m.suspended.target = m.suspended.target - off end
	end
	if run then run.swayCenters = {} end
end

local function Resume()
	for _, m in pairs(movers) do ResumeMover(m) end
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
	MoveTo(m, m.amount + (way == "left" and step.deg or -step.deg), step.secs, StepEase(step), step.blend)
	WaitMover(m)
end
function STEP.tilt(step)
	local m = movers.pitch
	if step.rand == "give" then
		MoveTo(m, TiltTarget(step, math.random), step.secs, StepEase(step), step.blend)
		WaitMover(m)
		return
	end
	if step.deg == 0 then return end
	MoveTo(m, m.amount + step.deg, step.secs, StepEase(step), step.blend)
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
	ZoomTo(goal, ZoomSecs(step, secs, goal - Zoom()), StepEase(step))
	WaitZoom()
end
function STEP.zoom(step)
	local secs = step.fit == "cast" and ns.DepartCastLeft and ns.DepartCastLeft() or step.secs
	ZoomStep(step, ZoomGoal(step, ZoomYards(step, math.random), run.startZoom), secs)
end
-- (Its middle: where the camera was as this sway first ran in the scene,
-- by the running total; again from where you leave it after you move the
-- camera, ForgetTurns.)
function STEP.sway(step)
	local m = movers.yaw
	run.swayCenters[step] = run.swayCenters[step] or m.amount
	local center = run.swayCenters[step]
	local delta = SwayTurn(step, m.amount, math.random, center)
	local curve, secs, top, still = SwayCurve(step, delta, m.amount, center)
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
function STEP.spin(step)
	local m = movers.yaw
	MoveCurve(m, Way(step, math.random, run.onceLeft) == "left", SpinCurve(step), step.secs > 0 and step.secs or 1e7,
		step.max, step.blend)
	WaitMover(m)
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
-- Undo its turns: everything this script turned, tilted and zoomed undone,
-- by the running totals, all at once (the turn and the tilt kept going
-- together as a Together's are: Resend). A turn or tilt that only just
-- stopped holds the others back till its STEP_GAP is up, so all three set
-- off together.
function STEP.putback(step)
	local yaw, pitch = movers.yaw, movers.pitch
	DropHeld(yaw)
	DropHeld(pitch)
	while GetTime() - math.max(yaw.lastStop, pitch.lastStop) < STEP_GAP do Yield() end
	MoveTo(yaw, yaw.amount - Wrap(yaw.amount), step.secs, EASES.smooth)
	MoveTo(pitch, 0, step.secs, EASES.smooth)
	if step.zoom == "yes" then ZoomTo(run.startZoom, step.secs) end
	WaitMover(yaw)
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
	StopFollow()
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

-- What a Wait until waits on is under way: a cast going, a flight, a death.
-- Until it is, there's nothing to end: no landing without a flight, so it
-- runs its steps on (played from its page, say), as long as the script does.
local UNDER_WAY = {
	cast = function() return ns.DepartCastLeft ~= nil and ns.DepartCastLeft() ~= nil end,
	landing = function() return ns.OnTaxi() end,
	alive = function() return ns.IsDead() end,
}
function STEP.wait(step)
	local secs = step.what == "time" and WaitSecs(step, math.random) or step.secs
	if step.what == "time" and #step.steps == 0 then
		WaitSeconds(secs)
		return
	end
	local check = step.what == "time" and function() return false end or UNTIL[step.what]
	local underWay = UNDER_WAY[step.what]
	local seen = not underWay
	local function done()
		if not seen then
			seen = underWay()
			if not seen then return false end
		end
		return check(step)
	end
	local untilT = step.what == "time" and run.t + secs or math.huge
	local kid = #step.steps > 0 and coroutine.create(function() DoSteps(step.steps) end)
	while not done() and run.t < untilT do
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
function STEP.endMusic(step)
	if ns.EndSceneMusic then ns.EndSceneMusic(step.secs) end
end
-- Follow your turns: every frame until the camera ends (FollowFrame).
function STEP.follow(step)
	-- (carry: steps played in place of the script's own, with a Follow your
	-- turns of their own, CameraScriptPlaySteps: it goes on as it was.)
	if follower.carry then follower.carry = nil else StopFollow() end
	while true do
		FollowFrame(step, run.dt or 0)
		Yield()
	end
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
		MoveTo(m, m.amount + way * LOOK_STEP, AimSecs(step, LOOK_STEP), StepEase(step))
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
	MoveTo(m, m.amount + turn, AimSecs(step, turn), StepEase(step))
	WaitMover(m)
	if step.at == "speaker" then
		-- (Still well off, a swing cut short by how far it may go: one more.)
		WaitSeconds(0.3)
		local again, off = SpeakerTurn(step, 0)
		if again and off > AIM_CORRECT and math.abs(again) >= 0.5 then
			MoveTo(m, m.amount + again, AimSecs(step, again), StepEase(step))
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

local function IsQuestTrigger(trigger)
	return trigger == "Quest" or trigger == "QuestGossip"
end

-- A script cut off before its When it ends zoomed back (zoomer.left: where it
-- left the camera, and the distance it was going back to). That's no distance
-- of yours, so the next script's start is the one it was going back to: taking
-- off just after, the Skyriding Cam's landing went back in to a scene's close
-- up. Not once you've zoomed, or the camera's moved on since.
-- (On zoomer, as this file's main chunk is at Lua's 200 locals.)
function zoomer.StartDistance()
	local left, zoom = zoomer.left, Zoom()
	zoomer.left = nil
	if left and math.abs(zoom - left.at) < 1 and (ns.lastPlayerZoomAt or -math.huge) < left.when then
		return left.home
	end
	return zoom
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
		startZoom = IsQuestTrigger(trigger) and ns.QuestCamTakeHeldZoom() or zoomer.StartDistance(),
		startedAt = GetTime(), inputSeen = ns.GetLastCameraInput and ns.GetLastCameraInput() or 0,
		triggerOn = trigger ~= nil, onceLeft = math.random() < 0.5, swayCenters = {},
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

local function HasKind(list, kind)
	for _, step in ipairs(list) do
		if not step.off and (step.k == kind or (step.steps and HasKind(step.steps, kind))) then return true end
	end
	return false
end

-- Whether a list of steps zooms: a zoom, or a Put back with its zoom.
function zoomer.GoesBack(list)
	for _, step in ipairs(list) do
		if not step.off and (step.k == "zoom" or (step.k == "putback" and step.zoom == "yes")
			or (step.steps and zoomer.GoesBack(step.steps))) then
			return true
		end
	end
	return false
end

local function Finish(why)
	if not run then return end
	StopAll()
	-- (Its When it ends never got the camera back: zoomer.StartDistance.)
	if not run.endingDone and zoomer.GoesBack(run.script.ending) and math.abs(Zoom() - run.startZoom) > 0.5 then
		zoomer.left = { at = Zoom(), home = run.startZoom, when = GetTime() }
	end
	-- (You took the camera from a quest script whose When it ends zooms back: the
	-- turn's yours, but the zoom back out still comes as you walk off, or a
	-- right-drag away from a quest giver left you close in.)
	if why == "camera" and IsQuestTrigger(run.trigger) and HasKind(run.script.ending, "zoom")
		and math.abs(Zoom() - run.startZoom) > 0.5 then
		ns.QuestCamHoldZoomOut(run.startZoom, math.max(0.25, Db("questCamZoomOutSpeed", 0.5)))
	end
	if run.raisedMax and ns.LowerZoomMax then
		if Zoom() > run.startZoom + 0.5 then maxHeldTo = run.startZoom else ns.LowerZoomMax() end
	end
	if exitBox then exitBox:Hide() end
	ns.ApplyCVarSet(FOLLOW_CVARS, false)
	ns.Log("state", ("camera script %s ended (%s)"):format(run.script.name, why or "done"))
	-- (Not the Skyriding Cam's own end with you back in the air: that's a new
	-- flight, not one to sit out with no camera.)
	if run.trigger and run.triggerOn and not (why == "ends" and run.trigger == "Skyride") then
		stoppedFor = run.trigger .. run.camera
	end
	-- (Stopped before its When it ends ran, or partway through: its End music
	-- still ends the music.)
	local endMusic = EndMusicIn(run.script.ending)
	if endMusic and ns.EndSceneMusic then ns.EndSceneMusic(endMusic) end
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
		if not run.pausedUntil then Suspend(event == "camera") end
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
-- Your casts ending (the Your cast ends rule): noted for the running script.
local castFrame = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
	castFrame:RegisterUnitEvent(event, "player")
end
castFrame:SetScript("OnEvent", function()
	if run then run.castEnded = true end
end)
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
		elseif now - (talk.stillSince or now) < Db("chatNearbyDelay", 3) then
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
		-- (Past coming back too: SkyrideCam.lua's landing plays it all back, from
		-- skyrideCamLand on, so its When it ends finds nothing left to move.
		-- Landing's zoom off: only as long as its turn and tilt take, so a scene of
		-- yours can follow on; the half second is the landing's time to start.)
		local back = Switch("skyrideCamZoomBack") and Db("skyrideCamBackTime", 3) or 0.5
		if now - sky.downSince >= Db("skyrideCamLand", 0.5) + back + 0.5
			and not (ns.SkyrideLandingBusy and ns.SkyrideLandingBusy()) then
			sky.on = false
		end
	end
	return sky.on
end

-- The trigger running a script camera now, and that camera: a standing-still
-- trigger's (or your own's, or a cast's), else a flight's, death's, walking's,
-- running's, a quest giver's or chat's.
local OWN_CAM = { "flight", "death", "walk", "run", "quest", "chatcam" } -- (TriggerNow's own list, in order)
local function TriggerNow()
	if not ns.db or not ns.db.enabled or not ns.ActiveEvent then return nil end
	-- (A scene of yours its key started: first, a window open or walking.)
	local scene = ns.CustomKeyScene and ns.CustomKeyScene()
	if scene then
		local camera = ns.TriggerSetting(scene, "camera")
		if IsScript(camera) then return scene, camera end
	end
	-- (One an interaction started, the mailbox say: with its window open too.)
	scene = ns.CustomInteractScene and ns.CustomInteractScene()
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
	local now = GetTime()
	local key, camera = ns.ActiveEvent()
	-- (The Calm Timer after a fight, as the cameras' own code waits it out:
	-- the event's row says.)
	if IsScript(camera) then
		if ns.CombatWaitOver and not ns.CombatWaitOver(ns.ScriptStandIn(camera) or "event", now) then return nil end
		return key, camera
	end
	local triggers = ns.CAMERA_TRIGGER
	if not triggers then return nil end
	-- (A trigger with a camera of its own, its row set to a script: its own
	-- camera is off then, CameraRows.lua's ns.CameraRowsOff. Each goes by what
	-- its own camera would: Enable Cameras, Stop camera, the auto-walk and
	-- auto-run waits, the Calm Timer; dying, by the Death Cam's conditions.)
	local own = { ns.OnTaxi() and "Flight",
		(ns.DeathCinematicWanted and ns.DeathCinematicWanted() or false) and "Death",
		ns.IsRPWalking and ns.IsRPWalking() and "Walk", ns.IsAutoRunning and ns.IsAutoRunning() and "Run",
		ns.QuestTalkNow and ns.QuestTalkNow() or false, ChatNow() or false }
	for i = 1, 6 do
		local each = own[i]
		local cam = OWN_CAM[i]
		if each and triggers[each] and not (ns.CameraOffBesidesRows and ns.CameraOffBesidesRows(cam))
			and (cam == "death" or not ns.CombatWaitOver or ns.CombatWaitOver(cam, now)) then
			camera = ns.TriggerSetting(each, "camera")
			if IsScript(camera) then return each, camera end
		end
	end
end

local function InFight()
	return InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
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
		-- (Its zoom speed still eases back to yours meanwhile: left at the crawl,
		-- every pause of a steered auto-run kept your zoom creeping.)
		if not zoomer.moving and zoomer.release then StepZoom(elapsed) end
		if now < run.pausedUntil then return end
		run.pausedUntil = nil
		Resume()
	end
	if moved and run.travel then
		StopMove(movers.yaw, true) -- (yours: its turns and tilts give way, its zoom carries on)
		StopMove(movers.pitch, true)
		movers.yaw.suspended, movers.pitch.suspended = nil, nil
		moved = false
	end
	if moved and Act("camera") then return end
	if InFight() and Act("fight") then return end
	if ns.playerMoving and not run.travel and (not ns.MovingManually or ns.MovingManually()) and Act("walk") then
		return
	end
	if zoomed then
		if not Act("zoom") then -- (yours wins: its zoom gives up, a paused one too)
			StopZoom()
			zoomer.suspended = nil
		end
		if not run or run.pausedUntil then return end
	end
	if run.phase == "steps" and run.trigger and not run.triggerOn then
		Act("ends")
		if not run then return end
	end
	if run.castEnded then
		run.castEnded = nil
		if Act("cast") and (not run or run.pausedUntil) then return end
	end
	if run.pausedUntil then return end
	StepMove(movers.yaw, elapsed)
	StepMove(movers.pitch, elapsed)
	StepZoom(elapsed)
	run.t, run.dt = run.t + elapsed, elapsed
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
			run.endingDone = true
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
	-- (Your zoom is the script's new start: its drifts and its zoom back at the
	-- end go from where you put the camera, never back to where it began.)
	-- (Not a scroll in the air on the Skyriding Cam: the camera's out where the
	-- moments put it, so that's no distance of yours, and landing went back to
	-- it: 39 yards after a scroll during a Whirling Surge. On the ground it counts.)
	if run and yourZoom and yourZoom ~= run.rebasedFor and run.trigger == "Skyride" and ns.GlidingSpeed
		and ns.GlidingSpeed() ~= nil then
		run.rebasedFor, run.rebaseStill, run.rebaseLast = yourZoom, nil, nil
	end
	if run and yourZoom and yourZoom > run.startedAt and yourZoom ~= run.rebasedFor then
		local zoom = Zoom()
		run.rebaseStill = math.abs(zoom - (run.rebaseLast or zoom)) < ZOOM_STILL and (run.rebaseStill or 0) + elapsed or 0
		run.rebaseLast = zoom
		if run.rebaseStill >= ZOOM_SETTLED and GetTime() - yourZoom >= ZOOM_SETTLED then
			run.rebasedFor, run.rebaseStill, run.rebaseLast = yourZoom, nil, nil
			ns.LogDetail("state", ("camera script: you zoomed, its start now %.1f (was %.1f)"):format(zoom, run.startZoom))
			run.startZoom = zoom
		end
	end
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
			ForgetTurns()
			if run.travel then
				StopMove(movers.yaw, true) -- (the zoom goes on: see Start)
				StopMove(movers.pitch, true)
				return
			end
			if run.pausedUntil then return end
			Suspend(true)
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
	turn.deg, turn.secs, turn.way = deg, secs, angle < 0 and "right" or "left"
	turn.speedUp, turn.slowDown = "short", "short"
	local ok, why = ns.PlayCameraScript({ id = ORBIT_ID, name = L["Orbit"], steps = { turn }, ending = {},
		rules = { camera = "stop", fight = "stop", walk = "stop", zoom = "ignore", ends = "stop" } })
	if ok then
		ns.Print(L["orbit: %d degrees over %s seconds (/cine orbit again stops it)"]:format(deg, tostring(secs)))
	else
		ns.Print(L["orbit can't start: %s"]:format(tostring(why)))
	end
end

-- Steps played now in place of the running script's own, while it's in its
-- steps for trigger: the Skyriding Cam's moments (SkyrideCam.lua: a
-- surge zooms out, a halt swings round...). What it was doing stops where it
-- is; once these are done it holds there, as it does after its own steps,
-- until its trigger's over and When it ends puts everything back. False if
-- no script is running its steps for that trigger. blend (seconds, 0 or
-- nil: none): a turn, tilt or zoom going now is handed over (Handover) to
-- the new steps' first move of it the same way, its speed sliding into the
-- new one's over that long, instead of stopping dead first.
function ns.CameraScriptPlaySteps(trigger, steps, why, blend)
	if not run or run.trigger ~= trigger or run.phase ~= "steps" then return false end
	local clean = ns.CleanCameraScript({ steps = steps }, "moment").steps
	-- (A Follow your turns in them carries on the one going: no starting over.)
	local keepFollow = HasKind(clean, "follow")
	if not keepFollow then StopFollow() end
	if blend and blend > 0 then
		for _, m in pairs(movers) do
			m.suspended = nil
			if m.moving and m.sent and m.share then
				EndMove(m)
				m.keepHeld = true
			elseif m.held and not m.moving then
				m.pending = false
				m.keepHeld = true
			else
				StopMove(m)
			end
		end
		if zoomer.moving and zoomer.sent then
			zoomer.handover = { speed = zoomer.sent, out = zoomer.goal > Zoom(), secs = blend, at = GetTime() }
		end
		StopZoom()
		zoomer.suspended = nil
	elseif keepFollow then
		StopMove(movers.yaw)
		StopMove(movers.pitch)
		movers.yaw.suspended, movers.pitch.suspended = nil, nil
		StopZoom()
		zoomer.suspended = nil
	else
		StopAll()
	end
	follower.carry = keepFollow or nil
	run.pausedUntil, run.pausedBy = nil, nil
	run.co = coroutine.create(function() DoSteps(clean) end)
	ns.Log("state", ("camera script %s: %s"):format(run.script.name, why or "steps played"))
	return true
end

-- Corrects the running tilt total (a positive tilt lowers the camera): the
-- Skyriding Cam's landing, the ground having stopped a lowered camera short of
-- what was counted, so When it ends doesn't take off more than it came down.
function ns.CameraScriptSetTilt(amount)
	movers.pitch.amount = amount
end

-- The script playing now, or nil (the minimap button's menu lists it).
function ns.PlayingCameraScript()
	return run and run.script
end

-- The camera a playing built-in script stands in for, by its key in
-- ns.activeCam ("idle", "vista", "flight"...), or nil: the rules' cam_*
-- words (Frames.lua). Run as its script, a camera leaves ns.activeCam unset.
-- (triggered: only one a trigger started, not Run on its page. Our cameras'
-- keys only: not the fly-by or Skyriding.)
function ns.PlayingCameraKey(triggered)
	local id = run and run.builtinId
	if type(id) ~= "string" or (triggered and not run.trigger) then return nil end
	return ns.ScriptStandIn(id)
end

-- A script playing its steps for this trigger now (not yet in When it ends).
function ns.CameraScriptRunning(trigger)
	return run ~= nil and trigger ~= nil and run.trigger == trigger and run.phase == "steps"
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
		yaw = movers.yaw.amount, pitch = movers.pitch.amount, startZoom = run.startZoom,
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
		if ns.db.scriptBuiltIns == false then ns.db.scriptBuiltIns = nil else ns.db.scriptBuiltIns = false end
		ns.CameraRowsChanged()
		if ns.ScriptBuiltInsOn() then
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
		scene = ns.CustomInteractScene and ns.CustomInteractScene()
		ns.Print(("scene started by a window (Interaction): %s%s; NPC window open %s, menu window open %s"):format(
			tostring(scene), scene and (" (camera %s)"):format(tostring(ns.TriggerSetting(scene, "camera"))) or "",
			tostring(ns.NPCWindowOpen and ns.NPCWindowOpen()), tostring(ns.MenuWindowOpen and ns.MenuWindowOpen())))
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
