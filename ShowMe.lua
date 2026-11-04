-- Cinematic: Show me, the welcome window's Customize choices tried for a few
-- seconds (and the Profiles page's, the same panel: Welcome.lua). A choice
-- with something to see has a demo: the letterbox and tint, a camera, a
-- Vision's test. One runs at a time; its button says Stop while it does.
--
-- ns.ShowMeFor(slot, choice): the demo key for a choice, or nil.
-- ns.ShowMe(key, hideFrame, force): start it (again: stop). A camera demo
--   fades hideFrame to FADED_ALPHA while the camera moves, and lets clicks
--   and camera drags through it to the world; as it was after. force: a
--   Vision's test with its switch off (the levels page's See it first row).
-- ns.ShowMeRunning(key), ns.ShowMeBlocked(key) (why it can't run now, or
-- nil), ns.StopShowMe(), ns.ShowMeListen(fn) (fn runs when one starts or
-- stops), ns.ShowMeInProfile(key, profile) (whether a profile has that look).
--
-- The effects demos set ns.effectsDemo, which Core.lua's effects step reads
-- in place of the effects' own Show in rows (Effects.lua's letterbox shows
-- for it with its setting off, too). The camera demos are a slow orbit of
-- their own (below), not one of Cinematic's cameras: those need their own
-- moment (standing still a while, a campfire), and Cinematic switched on.
local _, ns = ...
local L = ns.L

local ALL_EFFECTS = { letterbox = true, tint = true, vignette = true, weather = true }

-- seconds: how long it runs; effects: which effects show; camera: the
-- orbit runs (stopped by your input too); start, stop, running: a
-- Vision's own test; once: a test that shows and is done (no Stop);
-- setting: the Vision's switch, which has to be on.
local DEMOS = {
	bars = { seconds = 6, effects = { letterbox = true } },
	letterbox = { seconds = 6, effects = ALL_EFFECTS },
	tint = { seconds = 6, effects = { tint = true, vignette = true, weather = true } },
	cameraLook = { seconds = 5, camera = true, effects = ALL_EFFECTS },
	camera = { seconds = 5, camera = true },
	vitals = { seconds = 5, setting = "lowHealth",
		start = function() ns.FlashVitals(3) end,
		stop = function() if ns.StopVitalsFlash then ns.StopVitalsFlash() end end },
	tele = { seconds = 30, setting = "teleportVision",
		-- (3 seconds into its pretend cast: the portal's already opening; no
		-- timer in the middle, the settings page's)
		start = function() ns.TestTeleportVision(3, true) end,
		running = function() return ns.TeleportVisionTesting() end,
		-- (its test again: it stops)
		stop = function() if ns.TeleportVisionTesting() then ns.TestTeleportVision() end end },
	emote = { once = true, setting = "emoteVision", start = function() ns.TestEmoteVision() end },
	roll = { once = true, setting = "rollWindow", start = function() ns.TestRollWindow() end },
}
-- Each test's function, which a client without that Vision lacks.
local NEEDS = { vitals = "FlashVitals", tele = "TestTeleportVision", emote = "TestEmoteVision",
	roll = "TestRollWindow" }
function ns.ShowMeAvailable(key)
	return DEMOS[key] ~= nil and not (NEEDS[key] and not ns[NEEDS[key]])
end

-- Which choices have one: a slot's parts, and the Visions by key.
local BY_PART = {
	vfx = { standard = "letterbox", pure = "letterbox", noletterbox = "tint", cameras = "cameraLook" },
	camera = { pure = "camera", immersive = "camera", lite = "camera" },
}

function ns.ShowMeFor(slot, choice)
	local key
	if choice.vision then
		key = DEMOS[choice.vision.key] and choice.vision.key
	elseif slot and BY_PART[slot] then
		key = BY_PART[slot][choice.part]
	end
	if key and NEEDS[key] and not ns[NEEDS[key]] then return nil end
	return key
end

local current -- { key, def, untilAt, hidden, alpha, mice }
local FADED_ALPHA = 0.3 -- the window's while a camera demo runs

-- A frame and every frame in it no longer taking the mouse (each one's
-- setting kept in mice, to put back): a faded window still takes the clicks
-- and camera drags over it, its buttons too. And the backgrounds inside it
-- (not its own) cleared while it's faded: each a layer over the window's,
-- the boxes showed darker than the window round them, uneven.
local function MouseOff(frame, mice, inside)
	if inside and frame.GetBackdropColor and frame:GetBackdrop() then
		local r, g, b, a = frame:GetBackdropColor()
		if a and a > 0 then
			mice[#mice + 1] = { frame = frame, backdrop = { r, g, b, a } }
			frame:SetBackdropColor(r, g, b, 0)
		end
	end
	if frame.IsMouseEnabled then
		local click, wheel = frame:IsMouseEnabled(), frame.IsMouseWheelEnabled and frame:IsMouseWheelEnabled()
		if click or wheel then
			mice[#mice + 1] = { frame = frame, click = click, wheel = wheel }
			if click then frame:EnableMouse(false) end
			if wheel then frame:EnableMouseWheel(false) end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do MouseOff(child, mice, true) end
end
local ticker
local listeners = {}

local function Notify()
	for _, fn in ipairs(listeners) do pcall(fn) end
end

function ns.ShowMeListen(fn)
	listeners[#listeners + 1] = fn
end

function ns.ShowMeRunning(key)
	return current ~= nil and current.key == key
end

-- (force: a Vision's test with its switch off too, the welcome window's
-- See it first row: its tests show without it)
function ns.ShowMeBlocked(key, force)
	local def = DEMOS[key]
	if not def then return L["Nothing to show here."] end
	if def.camera and InCombatLockdown() then return L["Not in a fight: try it once the fight ends."] end
	if def.setting and not force and not ns.Setting(def.setting) then
		return L["Click the row to turn it on first."]
	end
end

-- Whether a profile has a demo's look (the See it first row's In and Not in):
-- its settings, under their pages' switches. Every level moves the camera.
local IN_PROFILE = { bars = { "letterboxPage", "letterbox" }, tint = { "tintPage" }, camera = {},
	vitals = { "lowHealth" }, tele = { "teleportVision" } }
local function On(base, key)
	local page = ns.PageSwitchOf(key)
	while page do
		if base[page] == false then return false end
		page = ns.PageSwitchOf(page)
	end
	return base[key] and true or false
end
function ns.ShowMeInProfile(key, name)
	local keys = IN_PROFILE[key]
	local base = keys and name and ns.ProfileBase and ns.ProfileBase(name)
	if not base then return nil end
	if base.visualEffects == false and (key == "bars" or key == "tint") then return false end
	if key == "tint" and base.tintPreset == "none" then return false end
	for _, each in ipairs(keys) do
		if not On(base, each) then return false end
	end
	return true
end

-- The orbit: the camera turns round you, easing in and out. It claims the
-- view as Cinematic's cameras do (Core.lua's camera lock), and turns by
-- stepping your turn speed setting, held while it does and put back after,
-- as Chat Cam does (ChatCam.lua, which has the why of each step): from rest
-- the lowest setting goes in with a creep too slow to see, the move sent
-- over it a moment later (a move started at speed jumps a frame); the
-- setting's sent only once it's changed enough, and never under 1 (lower,
-- the game turns at full speed); your setting's back a moment after the
-- move stops (else its last frame can run at yours). Your own camera input
-- stops it at once.
local WHO, YAW = "showme", "cameraYawMoveSpeed"
local ORBIT_TURN = 180    -- degrees, over the demo's seconds
local ORBIT_EASE = 1      -- seconds to full speed, and from it at the end
local MIN_SETTING = 1     -- the lowest speed setting sent
local PRIME_SHARE = 0.001 -- the creep's share of the setting
local PRIME_TIME = 0.2    -- seconds the creep runs before the move
local SETTING_CHANGE = 0.02 -- setting changes smaller than this share aren't sent
local RESTORE_DELAY = 0.3 -- seconds after the move stops before your setting's back
local orbitFrame = CreateFrame("Frame")
local orbit -- { startAt, endAt, speed, moving, sent }
local restoring = 0 -- (stops whose setting isn't back yet: the lock counts them)

local function StopOrbit()
	if not orbit then return end
	orbit = nil
	ns.SetOnUpdate(orbitFrame, nil)
	ns.CallCameraFunction("MoveViewRightStop")
	restoring = restoring + 1
	C_Timer.After(RESTORE_DELAY, function()
		restoring = restoring - 1
		-- (not if another orbit's begun: it holds the setting now)
		if not orbit then ns.ReleaseSpeed(WHO, YAW) end
	end)
end

local function OrbitStep()
	local now = GetTime()
	if now >= orbit.endAt then
		StopOrbit()
		return
	end
	if not orbit.moving then
		-- (the creep's run long enough: the move over it, at full share)
		if now < orbit.startAt then return end
		if not ns.CameraCall(WHO, "MoveViewRightStart", 1) then
			StopOrbit()
			return
		end
		orbit.moving = true
	end
	local p = math.max(0, math.min(1, (now - orbit.startAt) / ORBIT_EASE, (orbit.endAt - now) / ORBIT_EASE))
	p = p * p * (3 - 2 * p)
	local setting = math.max(MIN_SETTING, orbit.speed * p)
	if math.abs(setting - orbit.sent) > orbit.sent * SETTING_CHANGE then
		ns.SetHeldSpeed(WHO, YAW, setting)
		orbit.sent = setting
	end
end

local function StartOrbit(seconds)
	if not ns.ClaimCamera(WHO) then return false end
	ns.SetHeldSpeed(WHO, YAW, MIN_SETTING)
	if not ns.CameraCall(WHO, "MoveViewRightStart", PRIME_SHARE) then
		ns.ReleaseSpeed(WHO, YAW)
		return false
	end
	local now = GetTime()
	-- (Full speed for ORBIT_TURN in all: each ease covers half its time's
	-- worth, so the two together one ease's.)
	local turning = seconds - PRIME_TIME
	orbit = { startAt = now + PRIME_TIME, endAt = now + seconds, sent = MIN_SETTING,
		speed = ORBIT_TURN / math.max(1, turning - ORBIT_EASE) }
	ns.SetOnUpdate(orbitFrame, OrbitStep)
	return true
end

if ns.RegisterCamera then
	ns.RegisterCamera(WHO, function() return orbit ~= nil or restoring > 0 end, StopOrbit)
end

function ns.StopShowMe()
	local run = current
	if not run then return end
	current = nil
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if run.def.effects then
		ns.effectsDemo = nil
		ns.letterboxDirty = true
		if ns.RefreshTint then ns.RefreshTint() end
	end
	if run.def.camera then StopOrbit() end
	if run.def.stop then pcall(run.def.stop) end
	if run.hidden then
		run.hidden:SetAlpha(run.alpha)
		for _, each in ipairs(run.mice) do
			if each.click then each.frame:EnableMouse(true) end
			if each.wheel then each.frame:EnableMouseWheel(true) end
			if each.backdrop then each.frame:SetBackdropColor(unpack(each.backdrop)) end
		end
	end
	Notify()
end

local function Tick()
	local run = current
	if not run then return end
	if GetTime() >= run.untilAt or (run.def.camera and not orbit)
		or (run.def.running and not run.def.running()) then
		ns.StopShowMe()
	end
end

function ns.ShowMe(key, hideFrame, force)
	if ns.ShowMeRunning(key) then
		ns.StopShowMe()
		return
	end
	ns.StopShowMe()
	local def = DEMOS[key]
	if not def or ns.ShowMeBlocked(key, force) then return end
	-- (Another camera of ours moving the view, or you: none.)
	if def.camera and not StartOrbit(def.seconds) then return end
	if def.start and not pcall(def.start) then return end
	if def.once then return end
	if def.effects then
		ns.effectsDemo = def.effects
		ns.letterboxDirty = true
		if ns.RefreshTint then ns.RefreshTint() end
	end
	current = { key = key, def = def, untilAt = GetTime() + def.seconds }
	if def.camera and hideFrame then
		-- (Faded, the world showing through, and the mouse passing through
		-- it to the world: Escape still closes it.)
		current.hidden, current.alpha, current.mice = hideFrame, hideFrame:GetAlpha(), {}
		hideFrame:SetAlpha(FADED_ALPHA)
		MouseOff(hideFrame, current.mice)
		GameTooltip:Hide()
	end
	ticker = C_Timer.NewTicker(0.2, Tick)
	Notify()
end
