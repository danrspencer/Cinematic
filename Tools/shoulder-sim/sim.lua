-- Shoulder Cam simulator (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
-- plays a made-up session (DAY below) through the real ShoulderCam.lua and
-- ShoulderCamTest.lua, on a stand-in for the game's camera (GAME below). Writes
-- what happened, every TICK seconds, as JSON for build_sim.py's page.
--
--   python -I Tools/offline/run.py Tools/shoulder-sim/sim.lua <variant> <out.json> [SavedVariables]
--
-- variant: "page" (the page's defaults), "mounted" (Not while mounted off, so
-- the game's mount scaling shows), "tall" (a model the game scales 1.4x),
-- "relog" (a session where the game forgets the offset at login), "fight" (the
-- frames protected in a fight, Shoulder Cam switched off in it), "sweep" (the
-- test commands against a stand-in chat bubble), "yours" (your saved settings
-- as they are: the third argument), "hud" (the Shoulder Cam layout, Layouts.lua:
-- everything hung off the PRD on the screen's bottom, the portraits too, so
-- protected in fights).
--
-- GUESSES, each to be replaced by a measured number (Tools/shoulder-test-plan.md):
-- GAME.mountScale and GAME.tallScale. Measured (Run 3): the ease, and that the
-- screen shift goes as offset / distance at the field of view.
-- Not modelled: walls, the pivot, head movement, dynamic pitch.
-- luacheck: ignore 111 121 122 (it stands in for the game's functions on purpose)
local variant, outPath, savedPath = ...
variant = variant or "page"

package.path = "Tools/offline/?.lua;" .. package.path
local wow = dofile("Tools/offline/wow.lua")
wow.Install("retail")

local TICK = 0.02
local now = 100
local SHOULDER, CENTERED = "test_cameraOverShoulder", "CameraKeepCharacterCentered"

-- (ease: measured in Run 3, over in about 0.3 s; the sizes are still guesses.)
local GAME = { ease = 12, mountScale = 1.6, tallScale = 1.4, bearScale = 1.70, swapLag = 0.16, swapLagIn = 0.08 } -- (bear: a 2026-11-11 recording)
local UI_WIDTH, UI_HEIGHT = 1707, 960

-- The game: time, settings. A write to a test_ setting brings up the warning
-- until it's been accepted this session (tested on retail), unless its event's
-- been stopped (GameEvent, as Forever's: Run 2b). Our own notice is answered
-- Accept, or Cancel in the "decline" session.
GetTime = function() return now end
local timers = {}
C_Timer.After = function(secs, fn) timers[#timers + 1] = { at = now + secs, fn = fn } end
local cvars = { [SHOULDER] = "0.000000", [CENTERED] = "1", CameraReduceUnexpectedMovement = "1", cameraFov = "90", test_cameraHeadMovementStrength = "0" }
local writes = { total = 0, popups = 0 }
local accepted, stopped = false, false
local notices = 0
GameEvent = { UnregisterInternalEvent = function(event)
	if event == "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED" then stopped = true end
end }
local events = {}
local function Note(kind, text) events[#events + 1] = { t = now - 100, kind = kind, text = text } end
GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value)
	cvars[name] = tostring(value)
	if name:find("^test_") then
		writes.total = writes.total + 1
		if not accepted and not stopped then
			accepted = true
			writes.popups = writes.popups + 1
			Note("popup", "The game's warning comes up (Accept)")
		end
	end
end
C_CVar = C_CVar or {}
C_CVar.GetCVar, C_CVar.SetCVar = GetCVar, SetCVar
C_CVar.GetCVarDefault = function() return "0" end

-- You and the world.
local me = { mounted = false, taxi = false, dead = false, fight = false, editMode = false, camera = nil,
	row = true, scale = variant == "tall" and GAME.tallScale or 1, indoors = false, selfTarget = false }
UnitIsUnit = function(a, b) return me.selfTarget and a == "target" and b == "player" end
InCombatLockdown = function() return me.fight end
UnitAffectingCombat = function() return me.fight end
IsMounted = function() return me.mounted end
UnitOnTaxi = function() return me.taxi end
UnitIsDead = function() return me.dead end
IsIndoors = function() return me.indoors end
UnitRace = function() return "Dwarf", "Dwarf" end -- (Dwarf-2: 1.00 built in, as me.scale)
UnitSex = function() return 2 end
GetShapeshiftFormID = function() return me.form end -- (me.model: the form on screen)
_G.EditModeManagerFrame = { IsEditModeActive = function() return me.editMode end }
StaticPopup_Visible = function() return nil end
GetBindingKey = function() return nil end
debugstack = debugstack or function() return "" end

-- The camera: distance, and the offset the game eases to. It goes by the
-- setting scaled by what you're standing as or riding (GAME), and is ignored
-- while Keep Character Centered is on.
local cam = { zoom = 12, goal = 12, offset = 0 }
GetCameraZoom = function() return cam.zoom end
CameraZoomIn = function(yards) cam.goal = cam.goal - (yards or 0) end
CameraZoomOut = function(yards) cam.goal = cam.goal + (yards or 0) end
local function MoveCamera(dt)
	cam.goal = math.max(1, math.min(39, cam.goal))
	local step = 20 * dt
	local d = cam.goal - cam.zoom
	cam.zoom = math.abs(d) <= step and cam.goal or cam.zoom + (d > 0 and step or -step)
	local want = tonumber(cvars[SHOULDER]) or 0
	if cvars[CENTERED] == "1" or cvars.CameraReduceUnexpectedMovement == "1" then want = 0 end
	-- (You as your own target: the game puts you in the middle, the setting kept. 2026-11-11, Forever.)
	if me.selfTarget then want = 0 end
	-- (A form is its own model: its factor in place of yours.)
	want = want * (me.model and GAME.bearScale or me.scale) * (me.mounted and GAME.mountScale or 1)
	-- (cams: a flight path's mount is a model too, its factor a guess like a mount's.)
	if me.taxi and variant:find("^cams") then want = want * GAME.mountScale end
	cam.offset = cam.offset + (want - cam.offset) * math.min(1, dt * GAME.ease)
end
-- Where you really are on screen: -1 left edge, 1 right edge.
local function YouOnScreen()
	-- (As measured in Run 3: cameraFov across a 16:9 screen, the height kept.)
	local fov = tonumber(cvars.cameraFov) or 90
	local width = math.tan(math.rad(fov / 2)) * (UI_WIDTH / UI_HEIGHT) / (16 / 9)
	return -cam.offset / (math.max(1.5, cam.zoom) * width)
end

-- The frames that follow you: stand-ins with real anchors.
local function StandIn(name, x, y, protectedInFights)
	local f = { name = name, points = { { "BOTTOM", nil, "BOTTOM", x, y } } }
	function f:GetName() return name end
	function f:GetNumPoints() return #self.points end
	function f:GetPoint(i)
		local p = self.points[i or 1]
		return p[1], p[2], p[3], p[4], p[5]
	end
	function f:ClearAllPoints() self.points = {} end
	function f:SetPoint(a, b, c, x2, y2) self.points[#self.points + 1] = { a, b, c, x2, y2 } end
	function f:IsProtected() return protectedInFights end
	function f:IsShown() return true end
	function f:GetEffectiveScale() return 1 end
	_G[name] = f
	return f
end
local protected = variant == "fight" or variant == "hud"
local bar = StandIn("PlayerCastingBarFrame", 0, 180, protected)
local prd = StandIn("PersonalResourceDisplayFrame", 0, 240, protected)
-- chained: Forever's layout (Run 1): the cast bar on the PRD, the PRD on the
-- cooldowns, which stay put.
local cooldowns = StandIn("EssentialCooldownViewer", 0, 300, false)
-- hud: the rest of the Shoulder Cam layout's stack, riding on the PRD. (The
-- portraits are pinned to the screen since 2026-11-13: hung on the PRD, being
-- protected, they locked it in fights.)
local riders = {}
if variant == "hud" then
	for _, name in ipairs({ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame",
		"SwingTimerRangedFrame", "UtilityCooldownViewer", "BuffIconCooldownViewer" }) do
		riders[#riders + 1] = StandIn(name, 0, 0, true)
	end
	riders[#riders + 1], riders[#riders + 2] = bar, cooldowns
end
local function Layout(x)
	if variant == "hud" then
		prd.points = { { "BOTTOM", nil, "BOTTOM", x or 0, 210 } }
		bar.points = { { "BOTTOM", prd, "TOP", 0, 4 } }
		cooldowns.points = { { "BOTTOM", bar, "TOP", 0, 6 } }
		local on = { SwingTimerMainHandFrame = { "TOP", prd, "BOTTOM", 0, -4 },
			SwingTimerOffHandFrame = { "TOP", _G.SwingTimerMainHandFrame, "BOTTOM", 0, -4 },
			SwingTimerRangedFrame = { "TOP", _G.SwingTimerOffHandFrame, "BOTTOM", 0, -4 },
			UtilityCooldownViewer = { "BOTTOM", cooldowns, "TOP", 0, 4 },
			BuffIconCooldownViewer = { "BOTTOM", _G.UtilityCooldownViewer, "TOP", 0, 4 } }
		for _, f in ipairs(riders) do
			if on[f.name] then f.points = { on[f.name] } end
		end
	elseif variant == "chained" then
		prd.points = { { "BOTTOM", cooldowns, "TOP", x or 0, 4 } }
		bar.points = { { "BOTTOM", prd, "TOP", 0, 4 } }
	else
		bar.points = { { "BOTTOM", nil, "BOTTOM", x or 0, 180 } }
	end
end
Layout()
-- Where a stand-in is across the screen: its offset, plus its anchor's.
local function ScreenX(f)
	local p = f.points[1]
	if not p then return 0 end
	return p[4] + (type(p[2]) == "table" and p[2].points and ScreenX(p[2]) or 0)
end
local home = { bar = ScreenX(bar), prd = ScreenX(prd) }
local function RiderHomes()
	for _, f in ipairs(riders) do home[f.name] = ScreenX(f) end
end
RiderHomes()
-- (hud: how far any rider strayed from moving with the PRD, and how far the PRD went.)
local hud = { worst = 0, worstName = "-", most = 0 }

-- Only the two files' frames tick (the rest of the addon idles).
local mine = {}
local realCreate = CreateFrame
CreateFrame = function(...)
	local f = realCreate(...)
	local level = 2
	local src
	repeat
		local info = debug.getinfo(level, "S")
		src = info and info.source or ""
		level = level + 1
	until not info or not src:find("shoulder%-sim")
	if src:find("ShoulderCam") then mine[#mine + 1] = f end
	return f
end
if variant == "yours" then
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
UIParent.GetWidth = function() return UI_WIDTH end
UIParent.GetHeight = function() return UI_HEIGHT end
UIParent.GetEffectiveScale = function() return 1 end
WorldFrame.GetWidth = function() return UI_WIDTH end
WorldFrame.GetHeight = function() return UI_HEIGHT end
WorldFrame.GetEffectiveScale = function() return 1 end
ns.ActiveEvent = function() return me.camera and "Sim", me.camera end
-- (The Shoulder Cam row's rule to start with, (not indoors and not mounted) or
-- instance (the sim never enters an instance), unless a variant takes one out.)
local pauseMounted, pauseIndoors = variant ~= "mounted", variant ~= "indoors"
ns.RowOnNow = function()
	return me.row and not (me.mounted and pauseMounted) and not (me.indoors and pauseIndoors)
end
ns.ShoulderPausedMounted = function() return pauseMounted end
ns.DialogueUICameraOn = function() return false end
ns.RefreshOptions = function() end
if variant ~= "yours" then
	ns.db.enabled, ns.db.cameraModes = true, true
end
StaticPopup_Show = function(name)
	local dialog = StaticPopupDialogs[name]
	if not dialog then return end
	notices = notices + 1
	Note("notice", ("Our notice: %s"):format(variant == "decline" and "Cancel" or "Accept"))
	if variant == "decline" then dialog.OnCancel() else dialog.OnAccept() end
end
-- cams: Cinematic's own cameras played with every one ticked on the Cameras
-- tab (camsPaused: none, as it ships), the frames following you.
if variant:find("^cams") then
	for _, cam in ipairs({ "Vista", "Fish", "Cozy", "AFK", "Tele", "Flight", "Death", "Yours" }) do
		ns.db["shoulderCamAllow" .. cam] = variant == "cams"
	end
	ns.db.shoulderCamFrames = true
end
local noticedAtStart = ns.db.shoulderCamNoticed
-- (tall: its size factor measured, as a sweep on it would have saved.)
if variant == "tall" then ns.db.shoulderCamScales = { ["Dwarf-2"] = GAME.tallScale } end

local realLog = ns.Log
ns.Log = function(kind, text, ...)
	if type(text) == "string" and (kind == "cvar" and text:find("^Shoulder Cam") or kind == "shoulder") then
		Note(kind == "cvar" and "write" or "test", (text:gsub("^Shoulder Cam: ", "")))
	end
	if realLog then return realLog(kind, text, ...) end
end
ns.Print = function() end

-- A chat bubble of yours (sweep): over you, for BUBBLE_LIFE seconds.
local BUBBLE_LIFE = 7
local bubble
SendChatMessage = function(text) bubble = { text = text, untilAt = now + BUBBLE_LIFE } end
C_ChatInfo = { SendChatMessage = SendChatMessage }
local function BubbleFrame()
	local inside = { String = { GetText = function() return bubble.text end } }
	function inside:IsForbidden() return false end
	local b = {}
	function b:IsForbidden() return false end
	function b:GetChildren() return inside end
	function b:GetCenter() return (YouOnScreen() / 2 + 0.5) * UI_WIDTH, UI_HEIGHT * 0.62 end
	function b:GetEffectiveScale() return 1 end
	return b
end
C_ChatBubbles = { GetAllChatBubbles = function()
	if bubble and now < bubble.untilAt then return { BubbleFrame() } end
	return {}
end }

local samples, segments = {}, {}
local function Share(frame, base)
	return (ScreenX(frame) - base) / (UI_WIDTH / 2)
end
local function Tick()
	now = now + TICK
	for i = #timers, 1, -1 do
		if timers[i].at <= now then
			local fn = table.remove(timers, i).fn
			pcall(fn)
		end
	end
	for _, f in ipairs(mine) do
		local fn = f._scripts.OnUpdate
		if fn and f._shown then
			local ok, err = pcall(fn, f, TICK)
			if not ok then Note("error", tostring(err)) end
		end
	end
	MoveCamera(TICK)
	local prdMoved = ScreenX(prd) - home.prd
	hud.most = math.max(hud.most, math.abs(prdMoved))
	for _, f in ipairs(riders) do
		local off = math.abs(ScreenX(f) - home[f.name] - prdMoved)
		if off > hud.worst then hud.worst, hud.worstName = off, f.name end
	end
	samples[#samples + 1] = { now - 100, tonumber(cvars[SHOULDER]) or 0, cam.offset, cam.zoom, YouOnScreen(),
		Share(bar, home.bar), Share(prd, home.prd), me.mounted and 1 or 0, ns.ShoulderBlendShare and ns.ShoulderBlendShare() or 1 }
end

local function Wait(secs)
	for _ = 1, math.floor(secs / TICK + 0.5) do Tick() end
end
local function Part(label) segments[#segments + 1] = { t = now - 100, label = label } end

local Slash = ns.ShoulderTest
local function Switch(on)
	ns.db.shoulderCam = on
	ns.ApplyShoulderCam()
end

-- DAY: what the player does.
local bearDip -- (the nearest the middle you got between the form and its model coming)
local bearBefore -- (how far off the middle you sat just before: below your spot when the offset's at its cap)
local bearSwing -- (the furthest off the middle the bear got between "no form" and its model going)
local bearEnd -- (how far off the middle you sat after 3 s in bear form)
local indoorsEnd -- (where the camera and frames were after 3 s indoors)
local function Day()
	Part("Shoulder Cam off")
	Wait(1.5)
	Part("Turned on")
	Switch(true)
	Wait(3)
	Part("You zoom out to 22")
	cam.goal = 22
	Wait(3)
	Part("You zoom in to 6")
	cam.goal = 6
	Wait(3)
	cam.goal = 12
	Part("Swap shoulders")
	_G.CinematicDevShoulderSwapButton:GetScript("OnClick")()
	Wait(3)
	_G.CinematicDevShoulderSwapButton:GetScript("OnClick")()
	Wait(2)
	Part("You target yourself")
	me.selfTarget = true
	wow.Fire("PLAYER_TARGET_CHANGED")
	Wait(3)
	me.selfTarget = false
	wow.Fire("PLAYER_TARGET_CHANGED")
	Part("Target cleared")
	Wait(3)
	Part("Bear form")
	-- (In: the model's 0.06 to 0.1 s behind the form. 2026-11-11 log.)
	bearBefore = math.abs(YouOnScreen())
	me.form = 5
	wow.Fire("UPDATE_SHAPESHIFT_FORM")
	bearDip = 1
	for _ = 1, math.floor(GAME.swapLagIn / TICK + 0.5) do
		Tick()
		bearDip = math.min(bearDip, math.abs(YouOnScreen()))
	end
	me.model = 5
	wow.Fire("UNIT_MODEL_CHANGED", "player")
	Wait(3)
	bearEnd = math.abs(YouOnScreen())
	-- (Out: the game says "no form" a moment before the bear's gone. 2026-11-11 recording.)
	me.form = nil
	wow.Fire("UPDATE_SHAPESHIFT_FORM")
	Part("Out of bear form")
	bearSwing = 0
	for _ = 1, math.floor(GAME.swapLag / TICK + 0.5) do
		Tick()
		bearSwing = math.max(bearSwing, math.abs(YouOnScreen()))
	end
	me.model = nil
	wow.Fire("UNIT_MODEL_CHANGED", "player")
	Wait(3)
	Part("You go indoors")
	me.indoors = true
	wow.Fire("ZONE_CHANGED_INDOORS")
	Wait(3)
	indoorsEnd = { offset = cam.offset, bar = Share(bar, home.bar), prd = Share(prd, home.prd) }
	me.indoors = false
	wow.Fire("ZONE_CHANGED_INDOORS")
	Part("Back outdoors")
	Wait(3)
	Part("Mounted")
	me.mounted = true
	Wait(4)
	Part("Dismounted")
	me.mounted = false
	Wait(3)
	Part("Standing-still camera")
	me.camera = "cozy"
	Wait(4)
	me.camera = nil
	Part("It ends")
	Wait(3)
	Part("Quest cam (keeps the shoulder)")
	me.camera = "quest"
	Wait(3)
	me.camera = nil
	Part("You type /console test_cameraOverShoulder 0")
	SetCVar(SHOULDER, "0")
	Wait(2)
	Part("The game lays out its frames again")
	Layout()
	Wait(2)
	Part("Edit Mode")
	me.editMode = true
	Wait(3)
	Layout(120) -- (you drag the cast bar, or the PRD with it on a chain)
	home.bar, home.prd = ScreenX(bar), ScreenX(prd)
	RiderHomes()
	Wait(1)
	me.editMode = false
	Part("Edit Mode closed")
	Wait(3)
	Part("A fight")
	me.fight = true
	Wait(2)
	if variant == "fight" then
		Part("Turned off in the fight")
		Switch(false)
		Wait(3)
		Part("The fight ends")
		me.fight = false
		Wait(3)
		Switch(true)
		Wait(2)
	else
		me.fight = false
		Wait(1)
	end
	Part("Flight path")
	me.taxi = true
	Wait(3)
	me.taxi = false
	Wait(3)
	Part("Dead")
	me.dead = true
	Wait(3)
	me.dead = false
	Wait(3)
	if variant == "relog" then
		Part("Logs in again (the game has forgotten the offset)")
		cvars[SHOULDER], accepted, stopped = "0.000000", false, false
		ns.ResetShoulderSession()
		wow.Fire("PLAYER_ENTERING_WORLD")
		Wait(3)
	end
	Part("Turned off")
	Switch(false)
	Wait(4)
end

local function Sweep()
	Part("Shoulder Cam on")
	Switch(true)
	Wait(3)
	Part("sweep offsets")
	Slash("sweep offsets")
	for _ = 1, 8 do
		Wait(BUBBLE_LIFE + 1)
		Part("sweep next")
		Slash("sweep next")
	end
	Wait(4)
	Part("sweep zoom")
	Slash("sweep zoom")
	for _ = 1, 8 do
		Wait(BUBBLE_LIFE + 1)
		Slash("sweep next")
	end
	Wait(4)
	Part("try head, then off")
	Slash("try head")
	Wait(1)
	Slash("try off")
	Slash("scan")
	Slash("frames")
	Slash("watch")
	Wait(1)
	Slash("watch")
	Switch(false)
	Wait(2)
end

-- cams: each of Cinematic's cameras that pause it, as its built-in script
-- moves the view with the defaults (CameraScripts.lua's BUILT_IN; Core.lua),
-- from your own zoom of 12. Only the zoom reaches you on screen: the offset's
-- across the camera's own view, so a turn or tilt round you keeps you on
-- your spot (yaw and pitch are kept for the page only). Random zooms are
-- played as fixed picks within their ranges. camStats: each camera's numbers.
local camStats = {}
local function Smooth(a, b, t) t = math.max(0, math.min(1, t)) return a + (b - a) * t * t * (3 - 2 * t) end
-- Zoom moves one after another: { to, secs, pause after }, from where the last ended.
local function ZoomPath(from, moves)
	return function(t)
		local z, at = from, 0
		for _, m in ipairs(moves) do
			if t < at + m[2] then return Smooth(z, m[1], (t - at) / m[2]) end
			z, at = m[1], at + m[2] + (m[3] or 0)
			if t < at then return z end
		end
		return z
	end
end
local function Play(name, secs, zoomAt, setUp, tearDown)
	Part(name)
	if setUp then setUp() end
	local spot = ns.db.shoulderCamSpot or 0.2
	local st = { name = name, youMin = math.huge, youMax = 0, offMin = math.huge, offMax = 0, zoomMin = math.huge, zoomMax = 0,
		pausedSecs = 0, worstMiss = 0, worstPast = 0, framesMiss = 0, secs = secs }
	local t = 0
	while t < secs do
		cam.goal = zoomAt(t)
		Tick()
		t = t + TICK
		local you, off = math.abs(YouOnScreen()), math.abs(tonumber(cvars[SHOULDER]) or 0)
		if off == 0 then st.pausedSecs = st.pausedSecs + TICK end
		if t > 1.2 then -- (the blend in over)
			st.youMin, st.youMax = math.min(st.youMin, you), math.max(st.youMax, you)
			st.offMin, st.offMax = math.min(st.offMin, off), math.max(st.offMax, off)
			st.zoomMin, st.zoomMax = math.min(st.zoomMin, cam.zoom), math.max(st.zoomMax, cam.zoom)
			-- (Where ShoulderCam.lua means you to be at this distance: your spot,
			-- nearer the middle at the offset's cap or right up close.)
			local width = 1 -- (cameraFov 90 on 16:9)
			local yards = spot * cam.zoom * width / me.scale
			local k = math.max(0, math.min(1, (cam.zoom - 1) / 3))
			yards = math.min(1.5, yards * k * k * (3 - 2 * k))
			local meant = yards * me.scale / (math.max(1.5, cam.zoom) * width)
			st.worstMiss = math.max(st.worstMiss, math.abs(you - meant))
			st.worstPast = math.max(st.worstPast, you - spot)
			if you > 0.01 then st.framesMiss = math.max(st.framesMiss, math.abs(Share(prd, home.prd) - YouOnScreen()) / 2) end
		end
	end
	if tearDown then tearDown() end
	if st.youMin == math.huge then st.youMin, st.offMin, st.zoomMin = 0, 0, 0 end
	camStats[#camStats + 1] = st
	Wait(3)
end
local function Cams()
	Part("Shoulder Cam on")
	Switch(true)
	Wait(3)
	local z0 = 12
	-- Vista (/stare): sways 30 either side behind you; the zoom out 4 over 16 s,
	-- 8 s pause, then random between 2 in and 4 out (past your max).
	Play("Vista", 60, ZoomPath(z0, { { z0 + 4, 16, 8 }, { z0 - 2, 16, 8 }, { z0 + 3, 16, 8 } }),
		function() me.camera = "vista" end, function() me.camera = nil end)
	-- Fish: the same, narrower: out 2, then 2 in to 2 out.
	Play("Fish", 50, ZoomPath(z0, { { z0 + 2, 16, 8 }, { z0 - 2, 16, 8 } }),
		function() me.camera = "fish" end, function() me.camera = nil end)
	-- Cozy: a half turn round to face you over 14 s, in to 8 over 9 s; then
	-- random between 6.5 and 8.5 every 12 s (4 s pauses).
	Play("Cozy", 50, ZoomPath(z0, { { 8, 9, 4 }, { 6.5, 12, 4 }, { 8.5, 12, 4 } }),
		function() me.camera = "cozy" end, function() me.camera = nil end)
	-- AFK (and standing still 2 minutes): 40 degree sweeps; out 6 over 20 s
	-- (past your max), 10 s pause, then random 2 in to 6 out.
	Play("AFK", 70, ZoomPath(z0, { { z0 + 6, 20, 10 }, { z0 - 2, 20, 10 } }),
		function() me.camera = "afk" end, function() me.camera = nil end)
	-- Tele (Hearthstone, teleport): half round to face you, then a spin
	-- speeding up to 120 a second, in to 4 over the 10 s cast.
	Play("Tele (Hearthstone)", 10, ZoomPath(z0, { { 4, 10 } }),
		function() me.camera = "tele" end, function() me.camera = nil end)
	-- Flight: behind you, sways 70 either side, the standing-still zoom (out
	-- 6, past your max), a fly-by 160 round at 30 s; landing back to yours.
	Play("Flight path", 60, ZoomPath(z0, { { z0 + 6, 20, 10 }, { z0 - 2, 20, 7 }, { z0, 3 } }),
		function() me.taxi = true end, function() me.taxi = false end)
	-- Death: up 30 to look down on you, out 4 over 8 s, a slow 5/s turn.
	Play("Death", 30, ZoomPath(z0, { { z0 + 4, 8, 20 }, { z0, 2 } }),
		function() me.dead = true end, function() me.dead = false end)
	-- A script of your own (the Scripts page's example, Slow orbit): 360 round
	-- over 40 s, in to 6 over 12 s.
	Play("Your script (Slow orbit)", 45, ZoomPath(z0, { { 6, 12, 28 }, { z0, 3 } }),
		function() me.camera = "script:u1" end, function() me.camera = nil end)
	Part("Turned off")
	Switch(false)
	Wait(3)
end

if variant == "sweep" then Sweep() elseif variant:find("^cams") then Cams() else Day() end

-- The checks: what must be true when it's over.
local checks = {}
local function Check(name, ok, detail) checks[#checks + 1] = { name = name, ok = ok and true or false, detail = detail } end
local function Num(v) return tonumber(v) or 0 end
Check("Offset back to yours after turning off", Num(cvars[SHOULDER]) == 0, "reads " .. tostring(cvars[SHOULDER]))
Check("Keep Character Centered back to yours", cvars[CENTERED] == "1", "reads " .. tostring(cvars[CENTERED]))
Check("Reduce Unexpected Movement back to yours", cvars.CameraReduceUnexpectedMovement == "1", "reads " .. tostring(cvars.CameraReduceUnexpectedMovement))
Check("Cast bar back on its place", math.abs(Share(bar, home.bar)) < 0.001, ("%.1f UI units off"):format(Share(bar, home.bar) * UI_WIDTH / 2))
Check("PRD back on its place", math.abs(Share(prd, home.prd)) < 0.001, ("%.1f UI units off"):format(Share(prd, home.prd) * UI_WIDTH / 2))
-- Your spot held (Phase 3): how far you sat from it while it was on and the
-- game had caught up, 4 to 30 yards away, on a standard model on foot. With
-- the offset held (past SPOT_HOLD yards away in ShoulderCam.lua, near walls, since
-- 2026-11-12; a distance since 2026-11-15) you're meant to sit nearer the middle: those only must not go
-- past your spot (once the offset's glide after a zoom is done: 0.6 s).
local SPOT_HOLD = (ns.SHOULDER_SPOT_HOLD or 7.5) / (ns.ShoulderViewWidth and ns.ShoulderViewWidth() or 1) -- (in zoom: held over the view width since 2026-11-16)
local spotMiss, spotCount, pastSpot = 0, 0, 0
local zoomWas, zoomedAt = nil, -math.huge
-- (Within BLEND of a pause, the offset's easing in or out (BLEND_TIME in
-- ShoulderCam.lua, since 2026-11-13): off your spot by design, so skipped.
-- One of our cameras' pauses eases over its Transition box's seconds (the
-- Cameras tab, 5 to 10 to start with), longer than many a camera plays: a
-- sample taken while it's not all the way in (row[9]) is skipped too.)
local BLEND = 1.2
local zeroAt = {}
for _, row in ipairs(samples) do
	if row[2] == 0 then zeroAt[#zeroAt + 1] = row[1] end
end
local function NearPause(at)
	for _, zero in ipairs(zeroAt) do
		if math.abs(zero - at) < BLEND then return true end
	end
end
for _, row in ipairs(samples) do
	if row[4] ~= zoomWas then zoomWas, zoomedAt = row[4], row[1] end
	local caught = math.abs(row[3] - row[2] * me.scale) < 0.05
	if row[2] ~= 0 and not NearPause(row[1]) and row[9] >= 1 and caught and row[4] >= 4 and row[4] <= 30 and row[8] == 0 then
		local spot = ns.db.shoulderCamSpot or 0.2
		if row[4] > SPOT_HOLD then
			if row[1] - zoomedAt < 0.6 then row = nil end
		end
		if not row then -- (just zoomed, held: skipped)
		elseif row[4] > SPOT_HOLD then
			pastSpot = math.max(pastSpot, math.abs(row[5]) - spot)
		else
			spotMiss, spotCount = spotMiss + math.abs(math.abs(row[5]) - spot), spotCount + 1
		end
	end
end
if variant == "sweep" then
	local saved = ns.db.shoulderCamScales and ns.db.shoulderCamScales["Dwarf-2"]
	Check("The offset sweep saved the size factor", saved and math.abs(saved - me.scale) < 0.03, "saved " .. tostring(saved))
end
if variant ~= "decline" and variant ~= "sweep" then
	Check("Your spot held as you zoom", spotCount > 0 and spotMiss / spotCount < 0.01,
		spotCount > 0 and ("%.2f%% off it on average"):format(spotMiss / spotCount * 100) or "never on")
	Check("Never past your spot at the offset's cap", pastSpot < 0.01, ("%.2f%% past it at most"):format(pastSpot * 100))
end
if bearEnd and variant ~= "decline" then
	local spot = ns.db.shoulderCamSpot or 0.2
	-- (Where you sat on foot just before: your spot, or nearer the middle
	-- held by the offset's cap, which counts how far it moves you, so the
	-- bear sits there too. 2026-11-14.)
	local foot = math.min(spot, bearBefore or spot)
	Check("Bear form: where you sat on foot", math.abs(bearEnd - foot) < 0.01,
		("%.1f%% off the middle, on foot %.1f%%, your spot %.0f%%"):format(bearEnd * 100, foot * 100, spot * 100))
	local level = math.min(spot, bearBefore or spot)
	Check("Into bear form: no dip in first", bearDip > level - 0.01,
		("%.1f%% off the middle at least, %.1f%% before it"):format(bearDip * 100, level * 100))
	Check("Out of bear form: no swing out first", bearSwing < spot + 0.01,
		("%.1f%% off the middle at most, your spot %.0f%%"):format(bearSwing * 100, spot * 100))
end
if indoorsEnd then
	local middle = math.abs(indoorsEnd.offset) < 0.05
		and math.abs(indoorsEnd.bar) < 0.001 and math.abs(indoorsEnd.prd) < 0.001
	local detail = ("offset %.2f, cast bar %.1f, PRD %.1f UI units off"):format(indoorsEnd.offset,
		indoorsEnd.bar * UI_WIDTH / 2, indoorsEnd.prd * UI_WIDTH / 2)
	if variant == "indoors" then
		Check("Indoors kept the shoulder (Not indoors off)", not middle, detail)
	else
		Check("Indoors: camera and frames back in the middle", middle, detail)
	end
end
if variant == "hud" then
	Check("The HUD slid with you (the PRD, its root)", hud.most > 20, ("%.0f UI units at most"):format(hud.most))
	Check("Swing timers and cooldowns moved with it", hud.worst < 0.01,
		("%.2f UI units off at worst (%s)"):format(hud.worst, hud.worstName))
end
local errors = 0
for _, e in ipairs(events) do if e.kind == "error" then errors = errors + 1 end end
Check("No errors", errors == 0, errors .. " errors")
local ours = 0
for _, e in ipairs(events) do if e.kind == "write" then ours = ours + 1 end end
if variant == "decline" then
	-- (Your own /console write in DAY still brings the game's warning: nothing's kept quiet.)
	Check("Declined: nothing written by us", ours == 0, ours .. " writes")
	Check("Declined: switched off", ns.db.shoulderCam == false, "switch " .. tostring(ns.db.shoulderCam))
else
	Check("The game's warning never shows", writes.popups == 0, writes.popups .. " warnings")
	-- (Answered before, in your saved settings: not again.)
	local want = noticedAtStart and 0 or 1
	Check(want == 1 and "Our notice once" or "No notice: answered before", notices == want, notices .. " notices")
end

-- How far the frames were from you, in share of the screen's width, while
-- the camera was off to the side.
local worst, sum, count, worstAt = 0, 0, 0, 0
for _, row in ipairs(samples) do
	if math.abs(row[5]) > 0.01 then
		local miss = math.abs(row[6] - row[5]) / 2
		sum, count = sum + miss, count + 1
		if miss > worst then worst, worstAt = miss, row[1] end
	end
end

local function Encode(v)
	local kind = type(v)
	if kind == "number" then
		return (("%.4f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
	elseif kind == "string" then
		return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("[%c]", " ") .. '"'
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
local out = { variant = variant, tick = TICK, events = events, segments = segments, samples = samples, checks = checks,
	writes = writes.total, popups = writes.popups, missMean = count > 0 and sum / count or 0, missWorst = worst,
	missWorstAt = worstAt, guesses = GAME, spot = ns.db.shoulderCamSpot, side = ns.db.shoulderCamSide,
	columns = { "t", "setting", "offset", "zoom", "you", "bar", "prd", "mounted" }, cams = camStats }
local file = assert(io.open(outPath or ("shoulder-sim-" .. variant .. ".json"), "wb"))
file:write(Encode(out))
file:close()
print(("%s: %.0f s, %d test_ writes, %d warnings, frames miss you by %.1f%% of the screen on average, %.1f%% at worst (%.1f s)")
	:format(variant, now - 100, writes.total, writes.popups, (count > 0 and sum / count or 0) * 100, worst * 100, worstAt))
for _, c in ipairs(checks) do
	print(("  %s %s (%s)"):format(c.ok and "ok  " or "FAIL", c.name, c.detail))
end
if variant == "sweep" then
	for _, e in ipairs(events) do
		if e.kind == "test" and (e.text:find("^step") or e.text:find("^sweep") or e.text:find("^try")) then print("  " .. e.text) end
	end
end

for _, st in ipairs(camStats) do
	print(("  %-26s you %4.1f-%4.1f%% (spot %.0f%%), offset %.2f-%.2f yd, zoom %4.1f-%4.1f, paused %4.1f of %d s, off where meant %.1f%%, past spot %.1f%%, frames off you %.1f%%")
		:format(st.name, st.youMin * 100, st.youMax * 100, (ns.db.shoulderCamSpot or 0.2) * 100, st.offMin, st.offMax,
		st.zoomMin, st.zoomMax, st.pausedSecs, st.secs, st.worstMiss * 100, math.max(0, st.worstPast) * 100, st.framesMiss * 100))
end
