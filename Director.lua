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

local function Changed(key, value)
	if seen[key] ~= value then
		seen[key] = value
		return true
	end
	return false
end

-- The cheap things, looked at every frame: the first changed one, or nil.
local function WhatChanged()
	local why
	local function Look(key, value)
		if Changed(key, value) and not why then why = key end
	end
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
	return why
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
local function OnUpdate()
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
