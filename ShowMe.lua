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
-- stops), ns.ShowMeInProfile(key, profile) (whether a profile has that look),
-- ns.ShowMeWhen(key, profile) (when it shows there: the row's tags).
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
	-- (Emote and Roll: up until they go as they would, or Stop)
	emote = { seconds = 60, setting = "emoteVision", start = function() ns.TestEmoteVision() end,
		running = function() return ns.EmoteCardShown() end,
		stop = function() ns.HideEmoteCard() end },
	roll = { seconds = 60, setting = "rollWindow", start = function() ns.TestRollWindow(true) end,
		running = function() return ns.RollVisionActive() end,
		stop = function() ns.CloseRollWindow() end },
	damage = { seconds = 30, setting = "damageVision", start = function() ns.TestDamageVision(true) end,
		running = function() return ns.DamageVisionTesting() end,
		stop = function() ns.StopDamageVisionTest() end },
}
-- Each test's function, which a client without that Vision lacks.
local NEEDS = { vitals = "FlashVitals", tele = "TestTeleportVision", emote = "TestEmoteVision",
	roll = "TestRollWindow", damage = "TestDamageVision" }
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
-- its settings, under their pages' switches. Camera: the Cameras page's
-- Enable switch (off on Blank Slate, which leaves the camera as the game has it).
local IN_PROFILE = { bars = { "letterboxPage", "letterbox" }, tint = { "tintPage" }, camera = { "cameraModes" },
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

-- When a profile's look shows (the See it first row's tags): ns.ShowMeWhen(key,
-- profile) gives the tag ("In CineMode", "4 scenes", "Off"...), whether the
-- profile has it, and a sentence for the description box (nil for none).
-- The letterbox and tint by their Show in rows: Always, the CineMode tick
-- alone, Out of fights alone, else Sometimes. The camera by its scenes ticked
-- on (a built-in's own rows: copies and triggers of your own aren't in a profile).
local SHOW_LISTS = { "combatShow", "calmShow", "quietShow", "camShow", "worldShow", "cityShow", "bgShow",
	"instanceShow", "groupShow", "enemyShow", "friendlyShow" }
local EFFECT_OF = { bars = "letterbox", tint = "tint" }
local function Ticked(base, list, key)
	local on = type(base[list]) == "table" and base[list][key]
	if on == nil then on = ns.LIST_DEFAULTS[list] and ns.LIST_DEFAULTS[list][key] end
	return on and true or false
end
-- The names in a list, "A, B and C" (past max: "A, B and 3 more").
local function Names(list, max)
	if #list > max then
		local shown = {}
		for i = 1, max - 1 do shown[i] = list[i] end
		return (L["%s and %d more"]):format(table.concat(shown, ", "), #list - max + 1)
	end
	if #list == 1 then return list[1] end
	return (L["%s and %s"]):format(table.concat(list, ", ", 1, #list - 1), list[#list])
end
-- A profile's scenes ticked on, by name; cine: those that bring CineMode on;
-- picks: up to three of these to name for many (the scenes' own names don't
-- all read in a sentence: "resting with a listed buff (campfire)").
local PICKS = { { "Campfire", "sit by a campfire" }, { "Flight", "take a flight" }, { "Dance", "dance" },
	{ "Fishing", "fish" }, { "Sit", "sit down" } }
local function Scenes(base)
	local all, cine, on = {}, {}, {}
	for _, trigger in ipairs(ns.CAMERA_TRIGGERS or {}) do
		if trigger.sceneOff and not base[trigger.sceneOff] and base[trigger.camera] ~= trigger.off then
			-- (its name, "Take a flight", mid-sentence: "take a flight")
			local name = ns.CameraTriggerName and ns.CameraTriggerName(trigger.key) or trigger.key
			name = tostring(name):gsub("^%u%l", string.lower)
			all[#all + 1] = name
			on[trigger.key] = true
			if trigger.cine and base[trigger.cine] then cine[#cine + 1] = name end
		end
	end
	local picks = {}
	for _, pick in ipairs(PICKS) do
		if on[pick[1]] and #picks < 3 then picks[#picks + 1] = L[pick[2]] end
	end
	return all, cine, picks
end
function ns.ShowMeWhen(key, name)
	local has = ns.ShowMeInProfile(key, name)
	if has == nil then return nil end
	if not has then return L["Off"], false, L["Not in this profile."] end
	local base = ns.ProfileBase(name)
	local effect = EFFECT_OF[key]
	if effect then
		local row = "effect:" .. effect
		local rule = type(base.frameRules) == "table" and base.frameRules[row]
		if base[effect .. "Always"] then return L["Always"], true, L["All the time."] end
		local others = type(rule) == "string" and rule:find("%S") and true or false
		local quiet = false
		for _, list in ipairs(SHOW_LISTS) do
			if Ticked(base, list, row) then
				if list == "quietShow" then quiet = true else others = true end
			end
		end
		local cine = Ticked(base, "cineModeShow", row)
		if not others and cine and not quiet then
			local _, cineScenes = Scenes(base)
			if #cineScenes > 0 then
				return L["In CineMode"], true,
					(L["Only in CineMode, which comes on when you %s."]):format(Names(cineScenes, 5))
			end
			return L["In CineMode"], true, L["Only while CineMode is on."]
		end
		if quiet and not others and not cine then
			return L["Out of fights"], true, L["Whenever you're out of a fight."]
		end
		if not (others or quiet or cine) then return L["Off"], false, L["Not in this profile."] end
		return L["Sometimes"], true, L["At the moments its Show in row ticks."]
	end
	if key == "camera" then
		local scenes, _, picks = Scenes(base)
		if #scenes == 0 then return L["Off"], false, L["Not in this profile."] end
		local tag = #scenes == 1 and L["1 scene"] or (L["%d scenes"]):format(#scenes)
		if #scenes > 5 and #picks > 0 then
			return tag, true, (L["Plays at %d moments, like when you %s."]):format(#scenes, Names(picks, 3))
		end
		return tag, true, (L["Plays when you %s."]):format(Names(scenes, 5))
	end
	if key == "vitals" then return L["Low health"], true, L["As your health drops."] end
	if key == "tele" then return L["On hearth"], true, L["As you hearth or teleport."] end
	return L["On"], true, nil
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

-- A demo running for at least seconds more (the welcome window's tint
-- strength slider, dragged while the Tint demo plays).
function ns.ShowMeKeep(key, seconds)
	local run = current
	if run and run.key == key then run.untilAt = math.max(run.untilAt, GetTime() + seconds) end
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
