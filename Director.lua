local _, ns = ...

-- The camera director: the one place that works out the scene the cameras
-- go by (ns.DecideScene, Camera.lua: standing still, an event, travel,
-- death...), about 10 times a second and at once when something it goes by
-- changes, instead of every frame. The orbit reads ns.scene
-- (Tools/camera-director-plan.md).
--
-- "At once": a few cheap things are looked at every frame (moving, taxi,
-- turning or the mouse on the camera, CineMode, a fight, the emote, a
-- camera started or stopped by hand, the quest and chat cameras, a script),
-- and some events wake it (AFK, casts, auras, death, logging out). Anything
-- else (a window opening, the standing-still timer running out) is seen on
-- the next tick, at most 0.1 s later.

local TICK = 0.1 -- seconds between decisions with nothing changed

local frame = CreateFrame("Frame")
ns.directorFrame = frame
local sinceTick = math.huge -- (first step decides)
local stepAt = -1 -- the frame (GetTime) it last stepped in
local wake -- why it's to decide on its next step, or nil
local seen = {} -- what it last saw of the cheap things above
local stats = { decides = 0, wakes = 0, ticks = 0, tickChanges = 0, since = GetTime() }
ns.directorStats = stats

-- Something the scene goes by changed: decided on the next step (this
-- frame's, for the orbit).
function ns.WakeDirector(why)
	wake = wake or why or "?"
end
-- A scene or trigger setting changed (ns.CameraRowsChanged): what's kept per
-- decision (ns.ActiveEvent, ns.PerDecision's) is worked out afresh as next
-- asked, and the scene on the next step.
function ns.DirectorSettingsChanged()
	ns.directorGen = (ns.directorGen or 0) + 1
	ns.WakeDirector("settings")
end

local function Changed(key, value)
	if seen[key] ~= value then
		seen[key] = value
		return true
	end
	return false
end

-- The cheap things, looked at every frame: the first changed one, or nil.
-- (Look is made once: a closure made each frame was garbage every frame.)
local why
local function Look(key, value)
	if Changed(key, value) and not why then why = key end
end
local function WhatChanged()
	why = nil
	Look("cinematic", ns.lastCinematic or false)
	Look("moving", ns.playerMoving or false)
	Look("taxi", ns.OnTaxi() and true or false)
	Look("active", ns.IsPlayerActive() and true or false)
	Look("fight", (InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))) and true or false)
	Look("emote", ns.EmoteEventNow() or false)
	Look("manual", ns.manualCam or false)
	Look("stopped", ns.stoppedCam or false)
	Look("still", ns.stillSince or false) -- (set from elsewhere: a loading screen, a test)
	Look("quest", (ns.QuestCamActive and ns.QuestCamActive()) and true or false)
	Look("chat", (ns.ChatCamActive and ns.ChatCamActive()) and true or false)
	Look("questtalk", (ns.QuestTalkNow and ns.QuestTalkNow()) or false) -- (quest camera scripts)
	Look("skyride", (ns.SkyridingNow and ns.SkyridingNow()) and true or false) -- (the Skyriding Cam)
	Look("glide", (ns.GlidingSpeed and ns.GlidingSpeed() ~= nil) and true or false) -- (taking off, landing)
	Look("script", (ns.PlayingCameraKey and ns.PlayingCameraKey(true)) or false)
	Look("test", ns.testTravel or ns.cameraTesting or false)
	local changed = why
	why = nil
	return changed
end

ns.directorGen = 0 -- decisions so far: ns.ActiveEvent works itself out again on each
local function Decide(why, onTick)
	local before = ns.scene.cam
	ns.directorGen = ns.directorGen + 1
	local scene = ns.DecideScene(ns.lastCinematic, GetTime(), ns.OnTaxi(), ns.IsPlayerActive())
	stats.decides = stats.decides + 1
	seen.still = ns.stillSince or false -- (its own change isn't news)
	if onTick then
		stats.ticks = stats.ticks + 1
		-- A change only a tick saw: nothing woke it, up to 0.1 s late.
		if scene.cam ~= before then
			stats.tickChanges = stats.tickChanges + 1
			if ns.directorDebug then
				ns.Print(("director: %s -> %s on a tick (nothing woke it)"):format(tostring(before), tostring(scene.cam)))
			end
			ns.Log("director", ("%s -> %s on a tick"):format(tostring(before), tostring(scene.cam)))
		end
	else
		stats.wakes = stats.wakes + 1
		if ns.directorDebug and scene.cam ~= before then
			ns.Print(("director: %s -> %s (%s)"):format(tostring(before), tostring(scene.cam), why))
		end
	end
	return scene
end

-- One step: at most once a frame, from the director's own frame or the
-- orbit, whichever runs first. Gives the scene.
function ns.DirectorStep()
	local now = GetTime()
	if stepAt == now then
		return ns.scene
	end
	local elapsed = stepAt >= 0 and now - stepAt or 0
	stepAt = now
	sinceTick = sinceTick + elapsed
	local why = WhatChanged() or wake
	wake = nil
	local scene = ns.scene
	if why then
		sinceTick = 0
		scene = Decide(why, false)
	elseif sinceTick >= TICK then
		sinceTick = 0
		scene = Decide("tick", true)
	end
	-- The orbit asleep (Camera.lua): woken once a camera of its may have
	-- something to do; meanwhile the mouse held on the camera is noted for it.
	if ns.OrbitAsleep() then
		ns.NoteHeldCameraInput()
		-- (Steering with the mouse while a travel camera plays as its script:
		-- the script's turns go by it.)
		if ns.PlayingCameraScript() ~= nil then ns.UpdateMouseSteer() end
		if not ns.OrbitQuiet(scene) then
			ns.WakeOrbit()
			if ns.directorDebug then ns.Print("director: orbit awake (" .. tostring(why or "tick") .. ")") end
		end
	end
	return scene
end
ns.DirectorStep = ns.Profiled("Camera director", ns.DirectorStep)

-- (Its frame runs with the addon: Core.lua starts and stops it with the
-- orbit's, ns.SetDirectorRunning.)
-- With the orbit asleep (no camera of ours moving the view) and no script
-- steering with the mouse, its own frame steps it IDLE_STEP apart rather
-- than every frame: what it looks at changes far slower than a frame, and a
-- wake (an event) still steps it on the next frame. Awake, the orbit steps it
-- every frame itself.
local IDLE_STEP = 1 / 30 -- seconds
local sinceStep = 0
local function OnUpdate(_, elapsed)
	sinceStep = sinceStep + (elapsed or 0)
	if sinceStep < IDLE_STEP and not wake and ns.OrbitAsleep() and ns.PlayingCameraScript() == nil then
		return
	end
	sinceStep = 0
	ns.DirectorStep()
end
-- (A plain flag: asked several times a frame.)
local running = false
function ns.DirectorRunning()
	return running
end
function ns.SetDirectorRunning(on)
	on = on and true or false
	if on and not running then
		-- (Counted from here for /cine debug director, not from loading in.)
		stats.decides, stats.wakes, stats.ticks, stats.tickChanges, stats.since = 0, 0, 0, 0, GetTime()
	end
	running = on
	frame:SetScript("OnUpdate", on and OnUpdate or nil)
end

local WAKE_EVENTS = {
	"PLAYER_FLAGS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
	"PLAYER_CAMPING", "PLAYER_QUITING", "LOGOUT_CANCEL",
	"PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "LOADING_SCREEN_DISABLED",
	"PLAYER_MOUNT_DISPLAY_CHANGED",
}
local UNIT_WAKE_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_AURA",
}
for _, event in ipairs(WAKE_EVENTS) do
	pcall(frame.RegisterEvent, frame, event)
end
for _, event in ipairs(UNIT_WAKE_EVENTS) do
	pcall(frame.RegisterUnitEvent, frame, event, "player")
end
frame:SetScript("OnEvent", function(_, event)
	ns.WakeDirector(event)
end)

-- Worked out once per decision (once a frame while it isn't running):
-- questions about the scene that are asked every frame. fn(key) by its key.
function ns.PerDecision(fn)
	local gen, at, answers = -1, -1, {}
	return function(key)
		local now = GetTime()
		local fresh
		if running then fresh = gen == ns.directorGen else fresh = at == now end
		if not fresh then
			gen, at = ns.directorGen, now
			wipe(answers)
		end
		local answer = answers[key]
		if answer == nil then
			answer = fn(key) and true or false
			answers[key] = answer
		end
		return answer
	end
end
-- (The orbit's mouse steering asked it every frame: 0.1 ms in a profile.)
ns.CameraPlaysHere = ns.PerDecision(ns.CameraPlaysHere)

-- /cine debug cvarcost: what one camera speed write costs, as camera scripts
-- make them (ns.SetHeldSpeed: 1.8 ms each in a profile, restyling bars and
-- text). Writes it 20 times (your own value back after), counting the style
-- calls it sets off, and logs the first caller's stack to see whose they are.
function ns.DebugCVarCost()
	local cvar = "cameraYawMoveSpeed"
	local yours = GetCVar(cvar)
	if not yours or InCombatLockdown() then ns.Print("cvarcost: not now (in a fight, or no such setting)") return end
	local names = { "DressStyleEdges", "SetBarTexture", "OutlinedFlags", "StyleFontFile", "SetTextShadow", "RefreshPlate" }
	local kept, counts, stack = {}, {}, nil
	for _, name in ipairs(names) do
		local fn = ns[name]
		if type(fn) == "function" then
			kept[name], counts[name] = fn, 0
			ns[name] = function(...)
				counts[name] = counts[name] + 1
				if not stack then stack = debugstack and debugstack(2, 12, 0) or "?" end
				return fn(...)
			end
		end
	end
	local start = debugprofilestop and debugprofilestop() or 0
	for i = 1, 20 do
		SetCVar(cvar, (tonumber(yours) or 180) + (i % 2 == 1 and 1 or 0))
	end
	SetCVar(cvar, yours)
	local ms = (debugprofilestop and debugprofilestop() or 0) - start
	for name, fn in pairs(kept) do ns[name] = fn end
	local parts = {}
	for _, name in ipairs(names) do
		if counts[name] then parts[#parts + 1] = name .. " " .. counts[name] end
	end
	local line = ("cvarcost: 21 writes of %s took %.2f ms (%.3f each); style calls: %s"):format(cvar, ms, ms / 21,
		table.concat(parts, ", "))
	ns.Print(line)
	ns.Log("cvarcost", line)
	ns.Log("cvarcost", "first style call from: " .. (tostring(stack):gsub("%c+", " | ")))
end

-- /cine debug director: its counts, and each scene change in chat (again to stop).
function ns.DirectorDebug()
	ns.directorDebug = not ns.directorDebug
	local secs = math.max(1, GetTime() - stats.since)
	ns.Print(("director: %d decisions in %.0f s (%.1f a second): %d woken, %d ticks; %d scene changes only a tick saw. Scene now: %s. Changes in chat %s"):format(
		stats.decides, secs, stats.decides / secs, stats.wakes, stats.ticks, stats.tickChanges,
		tostring(ns.scene.cam), ns.directorDebug and "on (again to stop)" or "off"))
	ns.Print(("director: the orbit is %s (woken %d times)"):format(ns.OrbitAsleep() and "asleep" or "awake",
		ns.orbitSleeps or 0))
end
