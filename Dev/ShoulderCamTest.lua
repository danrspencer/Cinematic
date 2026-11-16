-- Shoulder Cam tests (dev copy only): /cine debug shoulder <what>, each a line
-- or more in the saved log (category "shoulder"), so a run's read from the
-- file after a /reload. Tools/shoulder-test-plan.md has the runs.
--
-- on, off, left, right, spot <percent>, strength <percent>: set it from chat.
-- scan: every camera setting the client has, its default, who you are.
-- frames: where the frames that follow you are anchored, and can they move.
-- watch: (again to stop; stays on over a reload) every change to a camera
--   setting and who made it, the warning popup, mounts and forms, and each
--   session's values at login. For "what keeps writing that?".
-- sweep offsets|zoom|ease|next|stop: measures where you really are on screen.
--   It says a line (the game puts your chat bubble right over you), then steps
--   the offset or the zoom and reads the bubble. A bubble doesn't last: when
--   it's gone the sweep waits, and "sweep next" says another line and goes on.
-- quiet: (stays on over a reload; again and /reload to stop) stops the game
--   hearing the event that brings up the experimental warning, as DynamicCam
--   and DialogueUI do, to see if that keeps it away here. For testing so far.
-- try pitch|head|enemy|interact|walls|off: one of the game's other experimental
--   camera settings on (again: off), for a look. "try off" puts all back.
-- walls: two timed doorway walks (as is, then the wall setting), every frame's
--   distance and offset, then verdicts: "check log".
local _, ns = ...

local SETTLE = 0.6     -- seconds a step waits at least (the game eases over in about 0.3: Run 3)
local STILL = 0.3      -- ...and until the bubble's been still this long (a zoom takes longer)
local SETTLE_MOST = 4  -- ...but never longer than this
local EASE_TIME = 1.2  -- seconds the ease run follows one step for
local SAMPLE = 0.05    -- seconds between bubble reads
-- (Long, in case a longer line's bubble lasts longer: each sweep logs how long it did.)
local LINE = "Testing my camera, please ignore this line of text for a moment. I am measuring where my " ..
	"character sits on the screen while the camera moves over my shoulder, so it needs a bubble that " ..
	"stays up a little while. Thanks for your patience!"
local SHOULDER, CENTERED = "test_cameraOverShoulder", "CameraKeepCharacterCentered"
local REDUCE = "CameraReduceUnexpectedMovement"

local CAMERA_CVARS = { SHOULDER, CENTERED, REDUCE, "test_cameraDynamicPitch", "test_cameraDynamicPitchBaseFovPad",
	"test_cameraDynamicPitchBaseFovPadDownScale", "test_cameraDynamicPitchBaseFovPadFlying",
	"test_cameraDynamicPitchSmartPivotCutoffDist", "test_cameraHeadMovementStrength",
	"test_cameraHeadMovementRangeScale", "test_cameraHeadMovementMovingStrength",
	"test_cameraHeadMovementStandingStrength", "test_cameraHeadMovementMovingDampRate",
	"test_cameraHeadMovementStandingDampRate", "test_cameraHeadMovementFirstPersonDampRate",
	"test_cameraHeadMovementDeadZone", "test_cameraTargetFocusEnemyEnable",
	"test_cameraTargetFocusEnemyStrengthPitch", "test_cameraTargetFocusEnemyStrengthYaw",
	"test_cameraTargetFocusInteractEnable", "test_cameraTargetFocusInteractStrengthPitch",
	"test_cameraTargetFocusInteractStrengthYaw", "cameraFov", "cameraDistanceMaxZoomFactor",
	"cameraZoomSpeed", "cameraSmoothStyle", "cameraPivot", "cameraIndirectVisibility", "cameraIndirectOffset" }
local WATCHED = {}
for _, name in ipairs(CAMERA_CVARS) do WATCHED[name:lower()] = true end

local FOLLOW_FRAMES = { "PlayerCastingBarFrame", "CastingBarFrame", "GamepadPlayerCastingBarFrame",
	"PersonalResourceDisplayFrame", "CinematicPersonalResource" }

local TRIES = {
	pitch = { test_cameraDynamicPitch = "1" }, head = { test_cameraHeadMovementStrength = "1" },
	enemy = { test_cameraTargetFocusEnemyEnable = "1" }, interact = { test_cameraTargetFocusInteractEnable = "1" },
	-- (Walls: the camera may sit this far into what's between you and it before
	-- it's pushed in, so a wall beside you no longer jerks it in and out.)
	walls = { cameraIndirectVisibility = "1", cameraIndirectOffset = "10" },
}

local function Log(text) ns.Log("shoulder", text) end
local Forms -- (below)
local function Say(text)
	Log(text)
	ns.Print("shoulder: " .. text)
end
-- (Any of what's read here can be secret on some clients: never compared.)
local function Text(value)
	local ok, text = pcall(tostring, value)
	return ok and text or "secret"
end

-- Who you are now: what the game's offset scales with (race, mount, form).
local function Who()
	local _, race = UnitRace("player")
	local form = GetShapeshiftFormID and GetShapeshiftFormID()
	local mounted = IsMounted and ns.Flag(IsMounted())
	local mount = ""
	if mounted and C_MountJournal and C_MountJournal.GetMountIDs then
		for _, id in ipairs(C_MountJournal.GetMountIDs()) do
			local name, _, _, active = C_MountJournal.GetMountInfoByID(id)
			if ns.Flag(active) then
				mount = " " .. Text(name)
				break
			end
		end
	end
	return ("%s sex %s, form %s, %s%s, indoors %s, in combat %s"):format(Text(race), Text(UnitSex("player")), Text(form),
		mounted and "mounted" or "on foot", mount, Text(IsIndoors and ns.Flag(IsIndoors())), Text(InCombatLockdown()))
end

local function Zoom() return GetCameraZoom and GetCameraZoom() or 0 end

local function Scan()
	Log(("scan: game build %s | %s | zoom %.2f, screen %.0f x %.0f, UI scale %.3f"):format(Text(select(4, GetBuildInfo())),
		Who(), Zoom(), WorldFrame:GetWidth(), WorldFrame:GetHeight(), UIParent:GetEffectiveScale()))
	local missing = {}
	for _, name in ipairs(CAMERA_CVARS) do
		local value = GetCVar(name)
		if value == nil then
			missing[#missing + 1] = name
		else
			local default = C_CVar and C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name)
			Log(("scan: %s = %s (default %s)"):format(name, Text(value), Text(default)))
		end
	end
	Log("scan: not on this client: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
	Log(("scan: ResetTestCvars %s, GetCameraZoom %s, C_ChatBubbles %s, warning popup up %s"):format(
		Text(ResetTestCvars ~= nil), Text(GetCameraZoom ~= nil), Text(C_ChatBubbles ~= nil),
		Text(StaticPopup_Visible and StaticPopup_Visible("EXPERIMENTAL_CVAR_WARNING") and true or false)))
	ns.Print(("shoulder scan: %d settings read, %d not here (in the log: /reload to save it)"):format(
		#CAMERA_CVARS - #missing, #missing))
end

-- (frames: also where these are, for the layout's centre stack and what a
-- sliding frame might cover.)
local NEIGHBOURS = { "PlayerFrame", "TargetFrame", "FocusFrame", "EssentialCooldownViewer", "UtilityCooldownViewer",
	"BuffIconCooldownViewer" }
local function Rect(frame)
	local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
	if not ok or type(left) ~= "number" then return "can't read" end
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return ("left %.0f bottom %.0f top %.0f width %.0f (UI units)"):format(left * scale, bottom * scale,
		(bottom + height) * scale, width * scale)
end

local function Frames()
	local list = {}
	for _, name in ipairs(FOLLOW_FRAMES) do list[#list + 1] = name end
	for _, name in ipairs(NEIGHBOURS) do list[#list + 1] = name end
	Log(("frames: screen %.0f x %.0f UI units, in combat %s"):format(UIParent:GetWidth(), UIParent:GetHeight(),
		Text(InCombatLockdown())))
	-- (What the follow does with them: the PRD on retail, 2026-11-15.)
	local d = ns.GetShoulderCamDebug and ns.GetShoulderCamDebug() or {}
	Log(("frames: client %s, profile %s, layout %s | offset %s, side %s, zoom %.2f, size %s, view width %.3f | " ..
		"follow %s, slide now %s, wants %s, lift %s | picked %s | moving %s"):format(ns.isRetail and "retail" or "forever",
		Text(ns.ActiveProfile and ns.ActiveProfile()), Text(ns.ActiveLayoutName and ns.ActiveLayoutName()),
		Text(d.shoulder), Text(d.side), Zoom(), Text(d.scale), ns.ShoulderViewWidth and ns.ShoulderViewWidth() or 0,
		Text(d.follow), Text(d.followShift), Text(d.followTarget), Text(d.followLift), Text(d.picked), Text(d.followed)))
	for _, name in ipairs(list) do
		local frame = _G[name]
		if not frame then
			Log(("frames: %s: not on this client"):format(name))
		else
			local parts = {}
			local okCount, count = pcall(frame.GetNumPoints, frame)
			for i = 1, okCount and type(count) == "number" and count or 0 do
				local ok, point, to, toPoint, x, y = pcall(frame.GetPoint, frame, i)
				local toName = ok and to and to.GetName and to:GetName() or (ok and to and "unnamed") or "screen"
				parts[i] = ok and ("%s on %s %s %s,%s"):format(Text(point), Text(toName), Text(toPoint), Text(x), Text(y))
					or "can't read"
			end
			Log(("frames: %s: shown %s, protected %s, scale %s, %s, points: %s"):format(name, Text(ns.Flag(frame:IsShown())),
				Text(ns.Flag(frame:IsProtected())), Text(frame:GetEffectiveScale()), Rect(frame),
				#parts > 0 and table.concat(parts, "; ") or "none"))
		end
	end
	ns.Print("shoulder frames: in the log (/reload to save it)")
end

-- watch: on from the moment the addon's up when it was left on, so a
-- session's first values and the warning at login are caught.
local watcher = CreateFrame("Frame")
watcher:Hide()
local hooked, popupUp
local function Caller()
	local stack = debugstack and debugstack(4, 2, 0) or ""
	return (stack:gsub("\n.*", ""):gsub("^.-AddOns[/\\]", ""):sub(1, 90))
end
local function Hook()
	if hooked then return end
	hooked = true
	local function Heard(how)
		return function(name, value)
			if watcher.on and type(name) == "string" and WATCHED[name:lower()] then
				Log(("watch: %s %s = %s from %s"):format(how, name, Text(value), Caller()))
			end
		end
	end
	hooksecurefunc("SetCVar", Heard("SetCVar"))
	if C_CVar and C_CVar.SetCVar then hooksecurefunc(C_CVar, "SetCVar", Heard("C_CVar.SetCVar")) end
	if ConsoleExec then
		hooksecurefunc("ConsoleExec", function(line)
			if watcher.on and type(line) == "string" and line:lower():find("camera") then
				Log(("watch: ConsoleExec %s from %s"):format(line:sub(1, 80), Caller()))
			end
		end)
	end
	if ResetTestCvars then
		hooksecurefunc("ResetTestCvars", function()
			if watcher.on then Log("watch: ResetTestCvars (the warning's Disable)") end
		end)
	end
end
-- Your target (target changes: "it goes back to the middle when I target myself"),
-- the game's target focus settings, and our Frames follow you slide.
local function TargetNow()
	if not (UnitExists and ns.Flag(UnitExists("target"))) then return "no target" end
	local follow = ns.GetShoulderCamDebug and ns.GetShoulderCamDebug() or {}
	return ("target %s (you %s, friend %s, player %s), focus enemy %s interact %s, reduce movement %s, " ..
		"frames slide %s of %s"):format(Text(UnitName("target")), Text(ns.Flag(UnitIsUnit("target", "player"))),
		Text(ns.Flag(UnitIsFriend("player", "target"))), Text(ns.Flag(UnitIsPlayer("target"))),
		Text(GetCVar("test_cameraTargetFocusEnemyEnable")), Text(GetCVar("test_cameraTargetFocusInteractEnable")),
		Text(GetCVar(REDUCE)), Text(follow.followShift), Text(follow.followTarget))
end
local function Values(when)
	Log(("watch: %s: offset %s, centered %s, switch %s, yours kept %s | %s | %s"):format(when, Text(GetCVar(SHOULDER)),
		Text(GetCVar(CENTERED)), Text(ns.db and ns.db.shoulderCam), Text(ns.db and ns.db.shoulderCamYours ~= nil), Who(),
		TargetNow()))
end
watcher:SetScript("OnEvent", function(self, event, name, value)
	if not self.on then return end
	if event == "CVAR_UPDATE" then
		if type(name) == "string" and WATCHED[name:lower()] then
			Log(("watch: CVAR_UPDATE %s = %s (reads %s)"):format(name, Text(value), Text(GetCVar(name))))
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		Values(event)
		-- (and once the game's had time to ease the camera over)
		C_Timer.After(1, function() if self.on then Values("1 s after the target change") end end)
	else
		Values(event)
	end
end)
ns.SetOnUpdate(watcher, function(self)
	if not self.on then return end
	local up = StaticPopup_Visible and StaticPopup_Visible("EXPERIMENTAL_CVAR_WARNING") and true or false
	if up ~= popupUp then
		popupUp = up
		Log(("watch: the warning popup %s (offset %s)"):format(up and "is up" or "is gone", Text(GetCVar(SHOULDER))))
	end
end)
local function SetWatch(on)
	watcher.on = on
	if on then
		Hook()
		for _, event in ipairs({ "CVAR_UPDATE", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
			"PLAYER_MOUNT_DISPLAY_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_TARGET_CHANGED" }) do
			pcall(watcher.RegisterEvent, watcher, event)
		end
		watcher:Show()
	else
		watcher:UnregisterAllEvents()
		watcher:Hide()
	end
end
-- quiet: whether the warning stays away with the game not told to show it.
local WARNING_EVENT = "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED"
local function SetQuiet(on)
	-- (Since 12.1 the game hears it through GameEvent, not UIParent.)
	local game = _G.GameEvent
	local internal = game and game.UnregisterInternalEvent
	local was = UIParent:IsEventRegistered(WARNING_EVENT)
	local ok, err = true, nil
	if on then
		if internal then ok, err = pcall(internal, WARNING_EVENT) end
		UIParent:UnregisterEvent(WARNING_EVENT)
	elseif not internal then
		UIParent:RegisterEvent(WARNING_EVENT)
	end
	Log(("quiet %s: GameEvent way here %s, UIParent was listening %s, now %s%s"):format(on and "on" or "off",
		Text(internal ~= nil), Text(was), Text(UIParent:IsEventRegistered(WARNING_EVENT)),
		ok and "" or (", error " .. Text(err))))
end
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self)
	if ns.db then
		self:UnregisterAllEvents()
		if ns.db.shoulderTestQuiet then SetQuiet(true) end
		if ns.db.shoulderTestWatch then
			SetWatch(true)
			Values("addon loaded")
		end
	end
end)

-- The text in a bubble, if it can be read.
local function BubbleText(bubble)
	local inside = bubble:GetChildren()
	if not inside or (inside.IsForbidden and inside:IsForbidden()) then return nil end
	if inside.String and inside.String.GetText then return inside.String:GetText() end
	for _, region in ipairs({ inside:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" then return region:GetText() end
	end
end

-- The bubble over you: its x and y as shares of the screen (-1 to 1 from the
-- middle), or nil and why.
local function BubbleSpot()
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then return nil, "no bubbles on this client" end
	local okAll, all = pcall(C_ChatBubbles.GetAllChatBubbles, false)
	if not okAll or not all then return nil, "bubbles can't be read here" end
	for _, bubble in ipairs(all) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) then
			local okText, says = pcall(BubbleText, bubble)
			local okSame, same = pcall(function() return type(says) == "string" and says:sub(1, #LINE) == LINE end)
			if okText and okSame and same then
				local ok, x, y = pcall(bubble.GetCenter, bubble)
				if ok and type(x) == "number" and type(y) == "number" then
					local scale = bubble:GetEffectiveScale() / WorldFrame:GetEffectiveScale()
					return (x * scale / WorldFrame:GetWidth() - 0.5) * 2, (y * scale / WorldFrame:GetHeight() - 0.5) * 2
				end
				return nil, "the bubble can't be measured here"
			end
		end
	end
	return nil, "no bubble of yours up"
end

-- What the Frames follow you sum says for an offset at this zoom, as a share
-- of the screen (-1 to 1): what a sweep's readings are checked against.
local function WorkedOut(yards)
	return -yards / (math.max(1.5, Zoom()) * ns.ShoulderViewWidth())
end

-- A sweep: steps of { offset, zoom (or nil) }, run in turn while a bubble's up.
local sweep -- { name, steps, at, waited, baseline, held = your settings, readings }
local stepper = CreateFrame("Frame")
stepper:Hide()

-- (tag: a few words after it, so a line said again isn't the same line.)
local function SendLine(tag)
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	if send then send(tag and (LINE .. " " .. tag) or LINE, "SAY") end
end

local function EndSweep()
	stepper:Hide()
	if not sweep then return end
	SetCVar(SHOULDER, sweep.held.offset)
	SetCVar(CENTERED, sweep.held.centered)
	if sweep.held.bubbles then SetCVar("chatBubbles", sweep.held.bubbles) end
	if sweep.held.reduce then SetCVar(REDUCE, sweep.held.reduce) end
	if ns.shoulderCalibrateButton then ns.shoulderCalibrateButton:Hide() end
	-- (Your zoom back as it was.)
	local delta = sweep.held.zoom - Zoom()
	if math.abs(delta) > 0.1 then
		ns.CallCameraFunction(delta > 0 and "CameraZoomOut" or "CameraZoomIn", math.abs(delta))
	end
	ns.shoulderTestHold = nil
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	local total, count = 0, 0
	for _, factor in ipairs(sweep.readings) do
		total, count = total + factor, count + 1
	end
	Say(("sweep %s done: %d steps, real/worked-out mean %s | %s (/reload to save it)"):format(sweep.name,
		sweep.at - 1, count > 0 and ("%.2f"):format(total / count) or "none", Who()))
	-- (offsets, off a mount: the mean's the size factor of your model, or of
	-- the form you're in, ShoulderCam.lua.)
	local onFoot = not (IsMounted and ns.Flag(IsMounted()))
	if sweep.name == "offsets" and count >= 3 and onFoot and ns.ShoulderModelKey then
		local key, factor = ns.ShoulderModelKey(), tonumber(("%.2f"):format(total / count))
		ns.db.shoulderCamScales = ns.db.shoulderCamScales or {}
		ns.db.shoulderCamScales[key] = factor
		if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
		Say(("size factor for %s saved: %.2f"):format(key, factor))
	elseif sweep.name == "offsets" then
		Say("size factor not saved: off a mount only, for now")
	end
	if sweep.name == "calibrate" and ns.ShoulderCalibrated then ns.ShoulderCalibrated(sweep) end
	sweep = nil
end

local function BeginStep(step)
	sweep.waited, sweep.last, sweep.moved = 0, nil, 0
	SetCVar(SHOULDER, ("%.2f"):format(step[1]))
	if step[2] then
		local delta = step[2] - Zoom()
		if math.abs(delta) > 0.1 then
			ns.CallCameraFunction(delta > 0 and "CameraZoomOut" or "CameraZoomIn", math.abs(delta))
		end
	end
end

local function Reading(step, x, y)
	if step[1] == 0 then sweep.baseline = x end
	local shift = sweep.baseline and x - sweep.baseline
	local want = WorkedOut(step[1])
	local factor = shift and math.abs(want) > 0.001 and shift / want or nil
	if factor then sweep.readings[#sweep.readings + 1] = factor end
	Say(("step %d: offset %.2f zoom %.2f: bubble x %.3f y %.3f, shift %s, worked out %.3f, real/worked-out %s, last moved %.2f s in"):format(
		sweep.at, step[1], Zoom(), x, y, shift and ("%.3f"):format(shift) or "?", want,
		factor and ("%.2f"):format(factor) or "?", sweep.moved))
end

ns.SetOnUpdate(stepper, function(_, elapsed)
	if not sweep then
		stepper:Hide()
		return
	end
	sweep.tick = (sweep.tick or 0) + elapsed
	if sweep.tick < SAMPLE then return end
	local dt = sweep.tick
	sweep.tick = 0
	if InCombatLockdown() then
		Say("sweep stopped: a fight started")
		EndSweep()
		return
	end
	local x, y = BubbleSpot()
	sweep.waited = sweep.waited + dt
	if not x then
		if sweep.bubbleAt then
			Log(("sweep: the bubble lasted %.1f s"):format(GetTime() - sweep.bubbleAt))
			sweep.bubbleAt = nil
		end
		if sweep.hadBubble or sweep.waited > 1 then
			sweep.paused = true
			stepper:Hide()
			if sweep.name == "calibrate" and ns.ShoulderCalibrateWait then
				ns.ShoulderCalibrateWait(sweep.at, #sweep.steps, tostring(y))
			else
				Say(("sweep waiting at step %d of %d: %s. Type /cine debug shoulder sweep next"):format(sweep.at,
					#sweep.steps, tostring(y)))
			end
		end
		return
	end
	sweep.hadBubble = true
	sweep.bubbleAt = sweep.bubbleAt or GetTime()
	if sweep.last and math.abs(x - sweep.last) > 0.001 then sweep.moved = sweep.waited end
	sweep.last = x
	if sweep.name == "ease" then
		Log(("ease: step %d, %.2f s: bubble x %.4f"):format(sweep.at, sweep.waited, x))
	end
	local settled = sweep.waited >= SETTLE and (sweep.waited - sweep.moved >= STILL or sweep.waited >= SETTLE_MOST)
	if sweep.name == "ease" and sweep.waited >= EASE_TIME or sweep.name ~= "ease" and settled then
		Reading(sweep.steps[sweep.at], x, y)
		sweep.at = sweep.at + 1
		if sweep.steps[sweep.at] then
			BeginStep(sweep.steps[sweep.at])
		else
			EndSweep()
		end
	end
end)

local SWEEPS = {
	offsets = { { 0 }, { 0.5 }, { 1 }, { 1.5 }, { 2 }, { -1 }, { -2 } },
	zoom = { { 0, 15 }, { 1, 15 }, { 1, 12 }, { 1, 8 }, { 1, 6 }, { 1, 5 }, { 1, 4 }, { 1, 3 }, { 1, 2 },
		{ 1, 20 }, { 1, 28 } },
	ease = { { 0 }, { 2 }, { -2 } },
	-- (calibrate: both sides at two zooms, each zoom from its own 0. Small
	-- offsets keep the bubble on screen up close and clear of walls.)
	calibrate = { { 0, 8 }, { 1 }, { 2 }, { 0 }, { -1 }, { -2 }, { 0, 12 }, { 1.5 }, { 2.5 }, { 0 }, { -1.5 }, { -2.5 } },
}

local function Sweep(what)
	if what == "next" then
		if not (sweep and sweep.paused) then
			ns.Print("shoulder sweep: nothing waiting")
			return
		end
		sweep.paused, sweep.hadBubble = nil, nil
		SendLine()
		BeginStep(sweep.steps[sweep.at])
		stepper:Show()
		return
	end
	if what == "stop" then
		EndSweep()
		return
	end
	local steps = SWEEPS[what or ""]
	if not steps then
		ns.Print("shoulder sweep: offsets, zoom, ease, next or stop")
		return
	end
	if sweep then EndSweep() end
	if InCombatLockdown() then
		ns.Print("shoulder sweep: not in a fight")
		return
	end
	-- (calibrate: on foot, nothing targeted: yourself targeted, the game puts
	-- you in the middle whatever the offset.)
	if what == "calibrate" then
		if IsMounted and ns.Flag(IsMounted()) then return ns.Print("shoulder calibrate: on foot, please") end
		if UnitExists("target") then return ns.Print("shoulder calibrate: clear your target first (Esc)") end
	end
	-- (Steps past the farthest the camera goes here left out: 15 yards times
	-- cameraDistanceMaxZoomFactor, 1 on Forever.)
	local farthest = 15 * (tonumber(GetCVar("cameraDistanceMaxZoomFactor")) or 1) + 0.5
	local kept = {}
	for _, step in ipairs(steps) do
		if not step[2] or step[2] <= farthest then kept[#kept + 1] = step end
	end
	sweep = { name = what, steps = kept, at = 1, readings = {},
		held = { offset = GetCVar(SHOULDER), centered = GetCVar(CENTERED), zoom = Zoom(),
			bubbles = what == "calibrate" and GetCVar("chatBubbles") or nil,
			reduce = what == "calibrate" and GetCVar(REDUCE) or nil } }
	-- (calibrate: bubbles on, and the motion sickness setting that cancels the
	-- offset off, both back after: it works with the Shoulder Cam off too.)
	if what == "calibrate" then
		SetCVar("chatBubbles", "1")
		SetCVar(REDUCE, "0")
	end
	ns.shoulderTestHold = true -- (ShoulderCam.lua keeps its hands off meanwhile)
	SetCVar(CENTERED, "0")
	Log(("sweep %s starting: %s | offset %s, zoom %.2f, cameraFov %s, chatBubbles %s"):format(what, Who(),
		Text(sweep.held.offset), Zoom(), Text(GetCVar("cameraFov")), Text(GetCVar("chatBubbles"))))
	SendLine()
	BeginStep(kept[1])
	stepper:Show()
	if what == "calibrate" then
		ns.PadTestBox("Calibrating: " .. Who():match("^(%S+ sex %S+)"), "stand still, hands off the camera", 0.7, 0.7, 0.7)
	end
	ns.Print(("shoulder sweep %s: stand still and leave the camera alone"):format(what))
end
ns.ShoulderSweep = Sweep

-- calibrate: the size factor of your race and sex (or the form you're in),
-- in one go, for the built-in table (MEASURED_SCALES, ShoulderCam.lua), so
-- players never need to: the offset sweep's readings at two zooms, both sides,
-- each step's own real/worked-out; the middle one saved (to you at once, and to
-- db.shoulderCalibrations with its spread, client and date, read after a
-- /reload), and called good if they all agree within CALIBRATE_SPREAD. When the
-- bubble runs out, a button says the line again (a click lets an addon talk).
local CALIBRATE_SPREAD = 0.06
function ns.ShoulderCalibrateWait(at, of, why)
	local button = ns.shoulderCalibrateButton
	if not button then
		button = CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
		button:SetFrameStrata("FULLSCREEN_DIALOG")
		button:SetSize(220, 32)
		button:SetText("Say it again and go on")
		button:SetScript("OnClick", function(self)
			self:Hide()
			ns.PadTestBox("Calibrating", "stand still, hands off the camera", 0.7, 0.7, 0.7)
			Sweep("next")
		end)
		ns.shoulderCalibrateButton = button
	end
	button:ClearAllPoints()
	button:SetPoint("TOP", UIParent, "TOP", 0, -260)
	button:SetScale(UIParent:GetEffectiveScale())
	button:Show()
	ns.PadTestBox(("Calibrating: step %d of %d"):format(at, of), "the bubble's gone: CLICK the button below to go on",
		0.3, 1, 0.3)
	Log(("calibrate: waiting at step %d of %d (%s)"):format(at, of, why))
end
function ns.ShoulderCalibrated(run)
	local list = {}
	for _, factor in ipairs(run.readings) do list[#list + 1] = factor end
	table.sort(list)
	local key = ns.ShoulderModelKey and ns.ShoulderModelKey() or "?"
	if #list < 6 then
		ns.PadTestBox("Calibration: not enough readings", ("%d of 8; run it again"):format(#list), 1, 0.3, 0.3)
		Log(("calibrate: %s: only %d readings"):format(key, #list))
		return
	end
	local middle = #list % 2 == 1 and list[(#list + 1) / 2] or (list[#list / 2] + list[#list / 2 + 1]) / 2
	local spread = list[#list] - list[1]
	local good = spread <= CALIBRATE_SPREAD
	local factor = tonumber(("%.2f"):format(middle))
	ns.db.shoulderCamScales = ns.db.shoulderCamScales or {}
	ns.db.shoulderCamScales[key] = factor
	ns.db.shoulderCalibrations = ns.db.shoulderCalibrations or {}
	ns.db.shoulderCalibrations[key] = { factor = factor, spread = tonumber(("%.3f"):format(spread)), readings = #list,
		good = good, client = ns.CLIENT, when = date("%Y-%m-%d %H:%M"), zoom = ("%.1f"):format(run.held.zoom) }
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	Log(("calibrate: %s = %.2f (%s: readings %s, spread %.3f) | %s"):format(key, factor, good and "good" or "redo",
		table.concat((function() local t = {} for i, f in ipairs(list) do t[i] = ("%.2f"):format(f) end return t end)(), " "),
		spread, Who()))
	ns.PadTestBox(("%s: %.2f"):format(key, factor), good and "good: saved. /reload so I can read it, then the next one"
		or ("readings disagree (%.2f apart): run it again somewhere open and flat"):format(spread),
		good and 0.3 or 1, good and 1 or 0.3, good and 0.3 or 0.3)
	C_Timer.After(15, function() if not sweep then ns.PadTestBoxHide() end end)
end

local function Try(what)
	local db = ns.db
	db.shoulderTestTried = db.shoulderTestTried or {}
	local tried = db.shoulderTestTried
	if what == "off" then
		for cvar, value in pairs(tried) do
			SetCVar(cvar, value)
			Log(("try: %s back to %s"):format(cvar, Text(value)))
		end
		db.shoulderTestTried = nil
		ns.Print("shoulder try: all back")
		return
	end
	local set = TRIES[what or ""]
	if not set then
		ns.Print("shoulder try: pitch, head, enemy, interact, walls or off")
		return
	end
	for cvar, value in pairs(set) do
		if GetCVar(cvar) == nil then
			Say(("try %s: %s isn't on this client"):format(what, cvar))
		elseif tried[cvar] ~= nil then
			SetCVar(cvar, tried[cvar])
			tried[cvar] = nil
			Say(("try %s: off (%s %s)"):format(what, cvar, Text(GetCVar(cvar))))
		else
			tried[cvar] = GetCVar(cvar)
			SetCVar(cvar, value)
			Say(("try %s: on (%s %s, was %s)"):format(what, cvar, Text(GetCVar(cvar)), Text(tried[cvar])))
		end
	end
end

-- walls: one run for "the camera jerks near walls". Two timed walks through a
-- doorway (as it is, then with "try walls" on), every frame's camera distance
-- (GetCameraZoom), offset, indoors and the frames' slide logged when they
-- change, then per walk: the pull-ins (the distance dropping a yard or more in
-- a frame, not by your wheel), offset writes, indoors flips, and verdicts.
-- Puts the wall settings back after. Typed again while running: stops.
local WALL_STEP = 20
local wallRun
local function WallsEnd(why)
	if not wallRun then return end
	wallRun.frame:Hide()
	for cvar, value in pairs(wallRun.kept) do SetCVar(cvar, value) end
	ns.shoulderTestHold = nil
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	ns.PadTestBoxHide()
	Log(("walls: %s; wall settings back (%s)"):format(why, Text(GetCVar("cameraIndirectVisibility"))))
	wallRun = nil
end
local function WallsVerdict()
	local a, b = wallRun.walks[1], wallRun.walks[2]
	for i, w in ipairs(wallRun.walks) do
		Log(("walls: walk %d (%s): %d pull-ins (biggest %.1f yd), %d push-outs, distance %.1f-%.1f yd, " ..
			"%d offset changes, indoors flips %d"):format(i, w.label, w.pullIns, w.biggest, w.pushOuts, w.low,
			w.high, w.offsets, w.flips))
	end
	local sees = (a.pullIns + b.pullIns) > 0
	Log(("walls: VERDICT distance read sees the wall pull-in: %s (%s)"):format(sees and "YES" or "NO",
		sees and "the offset follows every pull-in: smoothing it is ours to do"
		or "the game pulls in out of our sight: only its own settings can help"))
	if a.flips + b.flips == 0 then
		Log("walls: VERDICT indoors never flipped: that doorway counts as outdoors")
	end
	Log("walls: VERDICT the game alone against as built: read off the recording")
	ns.Print("shoulder walls: done, check log (/reload to save it)")
end
local function WallsBegin(index)
	-- (Second run, 2026-11-12: the game's wall setting is on by default and
	-- raising it changed nothing, so the walks now tell the game's own wall
	-- bumps from ours: the first with no offset at all, the second as built.)
	local labels = { "no offset (the game alone)", "as built" }
	if index == 1 then
		ns.shoulderTestHold = true
		SetCVar(SHOULDER, "0")
	else
		ns.shoulderTestHold = nil
		if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	end
	wallRun.walk = { label = labels[index], pullIns = 0, pushOuts = 0, biggest = 0, low = math.huge, high = 0,
		offsets = 0, flips = 0, ends = GetTime() + WALL_STEP }
	wallRun.walks[index] = wallRun.walk
	Log(("walls: walk %d (%s) starts | %s | offset %s, zoom %.2f, cameraIndirectVisibility %s, cameraIndirectOffset %s")
		:format(index, labels[index], Who(), Text(GetCVar(SHOULDER)), Zoom(), Text(GetCVar("cameraIndirectVisibility")),
		Text(GetCVar("cameraIndirectOffset"))))
end
-- forms: one run for "the view bumps as you shift form". You shift in and out
-- once per timing (FORM_TIMINGS: the game alone with the offset at 0, as
-- built, the offset a little after the form's change, and pushed past for a
-- moment), told when by the box, while recording the screen; each timing and
-- every form and model change is logged, and the bump's read off the
-- recording after. Typed again while running: stops.
local FORM_TIMINGS = {
	-- (Second run: small pushes past, into a form only. The first run's
	-- timings and what they did: ShoulderCam.lua, by ns.shoulderSwap.)
	{ "the game alone (offset 0)", off = true },
	{ "as built: 35% past for 0.035 s" },
	{ "no push", boost = 0, boostFor = 0 },
	{ "50% past for 0.02 s", boost = 0.5, boostFor = 0.02 },
	{ "as built again", again = true },
}
local FORM_SETTLE = 2.5 -- seconds between a timing going on (or a shift back) and "shift now"
local formRun
local function FormsEnd(why)
	if not formRun then return end
	formRun.frame:UnregisterAllEvents()
	formRun = nil
	ns.shoulderSwap, ns.shoulderTestHold = nil, nil
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	ns.PadTestBoxHide()
	Log(("forms: %s"):format(why))
end
local function FormsBox()
	local run = formRun
	local timing = FORM_TIMINGS[run.at]
	local head = ("%d/%d  %s"):format(run.at, #FORM_TIMINGS, timing[1])
	if run.phase == "wait" then
		ns.PadTestBox(head, "wait...", 0.7, 0.7, 0.7)
	elseif run.phase == "in" then
		ns.PadTestBox(head, "SHIFT INTO YOUR FORM now (cat, bear...: the same one each time; stand still, hands off the camera)", 0.3, 1, 0.3)
	else
		ns.PadTestBox(head, "count to 2, then SHIFT BACK OUT", 1, 0.82, 0)
	end
end
local function FormsStart(at)
	local run = formRun
	if at > #FORM_TIMINGS then
		FormsEnd("done")
		ns.PadTestBox("Forms run done", "stop the recording, then /reload", 0.3, 1, 0.3)
		C_Timer.After(8, function() if not formRun then ns.PadTestBoxHide() end end)
		return
	end
	local timing = FORM_TIMINGS[at]
	run.at, run.phase = at, "wait"
	ns.shoulderSwap = (timing.lead or timing.boost) and timing or nil
	ns.shoulderTestHold = timing.off or nil
	if timing.off then SetCVar(SHOULDER, "0") elseif ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	Log(("forms: timing %d (%s) on | %s | offset %s, zoom %.2f"):format(at, timing[1], Who(), Text(GetCVar(SHOULDER)), Zoom()))
	FormsBox()
	C_Timer.After(FORM_SETTLE, function()
		if formRun ~= run or run.at ~= at then return end
		run.phase = "in"
		FormsBox()
	end)
end
function Forms()
	if formRun then
		FormsEnd("stopped")
		ns.Print("shoulder forms: stopped")
		return
	end
	if GetShapeshiftFormID and GetShapeshiftFormID() then
		ns.Print("shoulder forms: start out of your forms")
		return
	end
	local run = { frame = CreateFrame("Frame") }
	formRun = run
	run.frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	run.frame:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
	run.frame:SetScript("OnEvent", function(_, event)
		if formRun ~= run then return end
		local form = GetShapeshiftFormID and GetShapeshiftFormID()
		Log(("forms: timing %d %s, form %s, offset %s"):format(run.at, event, Text(form), Text(GetCVar(SHOULDER))))
		if event ~= "UPDATE_SHAPESHIFT_FORM" then return end
		if form and run.phase == "in" then
			run.phase = "out"
			FormsBox()
		elseif not form and run.phase == "out" then
			local at = run.at
			run.phase = "wait"
			FormsBox()
			C_Timer.After(FORM_SETTLE, function()
				if formRun == run and run.at == at then FormsStart(at + 1) end
			end)
		end
	end)
	ns.Print("shoulder forms: record your screen; type it again to stop")
	FormsStart(1)
end

-- shift: the bump as you shift into a form and back out, measured, no
-- recording: it says a line (the typed command lets it talk), you shift in
-- and out while the bubble's up, and your bubble's spot on screen is logged
-- every frame from each shift till SHIFT_TAIL after the model's changed, with
-- the offset and the events, then a summary each way: where you were before,
-- the furthest out and in on the way, and where you settled. Each run tries
-- the next of SHIFT_TIMINGS (the push into a form, ns.shoulderSwap); typed
-- again mid-run, it stops.
-- (2026-11-14, a Night Elf's cat, as built: out 1 point as the model came,
-- then in 1 point as the push landed: about twice too much. So smaller ones.)
-- (Then, with the cat at 15%: part of the new offset written early, at the
-- form's change, ahead of the model (ShoulderModelScale's early share; into
-- a form only).)
-- (Then, out of the cat: a push past the elf's offset as her model comes
-- back (boostOut). 15% won, 2026-11-14 (ShoulderCam.lua's SWAP_PUSH_OUT_OF).)
-- (Then the bear, 2026-11-14: out, 15% the least again; in, +1.1 out over
-- 2-3 frames after the model came, the push on: stronger ones in.)
local SHIFT_TIMINGS = {
	{ "as built (15% push in, 15% out)" },
	{ "in: 25% past for 0.035 s", boost = 0.25, boostFor = 0.035 },
	{ "in: 35% past for 0.035 s", boost = 0.35, boostFor = 0.035 },
	{ "in: 25% past for 0.07 s", boost = 0.25, boostFor = 0.07 },
	{ "in: 50% past for 0.035 s", boost = 0.5, boostFor = 0.035 },
}
local SHIFT_TAIL = 0.8 -- seconds logged after the model's change
local shiftRun, shiftNext = nil, 1
local function ShiftEnd(why)
	local run = shiftRun
	if not run then return end
	shiftRun = nil
	run.frame:UnregisterAllEvents()
	run.frame:Hide()
	ns.shoulderSwap = nil
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	if run.bubbles then SetCVar("chatBubbles", run.bubbles) end
	Log(("shift: %s"):format(why))
	C_Timer.After(20, function() if not shiftRun then ns.PadTestBoxHide() end end)
end
-- (A frame's middle across the screen, -1 to 1, or nil: hidden, unreadable.)
local function FrameAcross(name)
	local frame = _G[name]
	if not (frame and frame.GetCenter and frame:IsShown()) then return nil end
	local ok, x = pcall(frame.GetCenter, frame)
	if not ok or type(x) ~= "number" then return nil end
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return (x * scale / UIParent:GetWidth() - 0.5) * 2
end
local function ShiftSummary(run, leg)
	local list = run.legs[leg]
	if not list or #list == 0 then
		Log(("shift: %s: no bubble readings"):format(leg))
		return
	end
	local before, last = run.before[leg], list[#list].x
	local most, least = -math.huge, math.huge
	for _, row in ipairs(list) do
		most, least = math.max(most, row.x), math.min(least, row.x)
	end
	Log(("shift: %s summary (%s%s): before %s, furthest out %.1f%%, furthest in %.1f%%, settled %.1f%%, %d frames"):format(
		leg, run.timing[1], run.moving and ", moving" or "", before and ("%.1f%%"):format(before * 100) or "?",
		most * 100, least * 100, last * 100, #list))
	-- (Your frames: how far the PRD's middle sat from you, in points of the
	-- screen's half-width, the same as above.)
	local gaps, gapMost, gapLast = 0, 0, nil
	for _, row in ipairs(list) do
		if row.prd then
			gaps, gapMost, gapLast = gaps + 1, math.max(gapMost, math.abs(row.prd)), row.prd
		end
	end
	if gaps > 0 then
		Log(("shift: %s summary, PRD from you: before %s, furthest %.1f, settled %+.1f (%d frames)"):format(leg,
			run.prdBefore and run.prdBefore[leg] and ("%+.1f"):format(run.prdBefore[leg] * 100) or "?",
			gapMost * 100, gapLast * 100, gaps))
	end
end
local Shift
function Shift(at, moving)
	if shiftRun then
		ShiftEnd("stopped")
		ns.Print("shoulder shift: stopped")
		return
	end
	if GetShapeshiftFormID and GetShapeshiftFormID() then
		return ns.Print("shoulder shift: start out of your forms")
	end
	if UnitExists("target") then return ns.Print("shoulder shift: clear your target first (Esc)") end
	shiftNext = SHIFT_TIMINGS[at or 1] and at or 1
	local timing = SHIFT_TIMINGS[shiftNext]
	local run = { timing = timing, legs = { ["in"] = {}, out = {} }, before = {}, prdBefore = {}, moving = moving,
		frame = CreateFrame("Frame") }
	shiftRun = run
	ns.shoulderSwap = (timing.boost or timing.early or timing.boostOut) and timing or nil
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	run.bubbles = GetCVar("chatBubbles")
	SetCVar("chatBubbles", "1")
	SendLine(("(run %d)"):format(shiftNext))
	Log(("shift: %s on | %s | offset %s, zoom %.2f, side %s"):format(timing[1], Who(), Text(GetCVar(SHOULDER)), Zoom(),
		Text(ns.db.shoulderCamSide)))
	if moving then
		ns.PadTestBox("Shift while running", "RUN straight ahead (autorun's fine), then SHIFT INTO YOUR FORM", 0.3, 1, 0.3)
	else
		ns.PadTestBox(("Shift %d/%d: %s"):format(shiftNext, #SHIFT_TIMINGS, timing[1]),
			"SHIFT INTO YOUR FORM now (stand still, hands off the camera)", 0.3, 1, 0.3)
	end
	local startedAt = GetTime()
	run.frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	run.frame:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
	run.frame:SetScript("OnEvent", function(_, event)
		if shiftRun ~= run then return end
		local form = GetShapeshiftFormID and GetShapeshiftFormID()
		local now = GetTime()
		Log(("shift: %s, form %s, offset %s"):format(event, Text(form), Text(GetCVar(SHOULDER))))
		if event == "UPDATE_SHAPESHIFT_FORM" then
			local leg = form and "in" or "out"
			-- (The game says "no form" once more as you shift in: no leg yet.)
			if leg == "out" and run.leg ~= "in" then return end
			if run.leg ~= leg then
				if run.leg and not run.inDone then
					run.inDone = true
					ShiftSummary(run, run.leg)
				end
				run.leg, run.legAt, run.modelAt = leg, now, nil
				local x = BubbleSpot()
				run.before[leg] = x and math.abs(x) or run.lastX
				local prd = FrameAcross("PersonalResourceDisplayFrame")
				run.prdBefore[leg] = x and prd and (prd - x) * (x < 0 and -1 or 1) or nil
			end
		elseif run.leg and not run.modelAt then
			run.modelAt = now
		end
	end)
	ns.SetOnUpdate(run.frame, function()
		if shiftRun ~= run then return end
		local now = GetTime()
		local x, why = BubbleSpot()
		if x then run.lastX = math.abs(x) end
		if not run.leg then
			if now - startedAt > 15 then
				ShiftEnd("no shift in 15 s")
				ns.PadTestBox("Shift: nothing happened", "type the command again and shift within 15 s", 1, 0.3, 0.3)
			end
			return
		end
		if run.modelAt and now - run.modelAt > SHIFT_TAIL then
			if run.leg == "in" and not run.inDone then
				run.inDone = true
				ShiftSummary(run, "in")
				ns.PadTestBox(moving and "Shift while running" or ("Shift: %s"):format(timing[1]),
					moving and "keep running, now SHIFT BACK OUT" or "now SHIFT BACK OUT", 1, 0.82, 0)
			elseif run.leg == "out" then
				ShiftSummary(run, "out")
				ShiftEnd("done")
				if moving then
					ns.PadTestBox("Shift while running done", "stop running; type it again for another, or /reload and say check log",
						0.3, 1, 0.3)
				elseif SHIFT_TIMINGS[shiftNext + 1] then
					-- (Said again too soon, the game blocks an addon's line:
					-- ADDON_ACTION_BLOCKED 1.2 s after a run, 2026-11-14.)
					-- (A button's click got the line blocked, ADDON_ACTION_BLOCKED,
					-- 1.2 and 11 s after a run, 2026-11-14; typed, it's never been.)
					ns.PadTestBox(("Shift %d/%d done"):format(shiftNext, #SHIFT_TIMINGS),
						("next: TYPE /cine debug shoulder shift %d"):format(shiftNext + 1), 0.3, 1, 0.3)
				else
					ns.PadTestBox("Shift runs all done", "/reload and say check log", 0.3, 1, 0.3)
				end
			end
			return
		end
		if x then
			local list = run.legs[run.leg]
			-- (Your frames from you, toward your side positive: the PRD's and,
			-- while casting, the cast bar's.)
			local side = x < 0 and -1 or 1
			local prd, cast = FrameAcross("PersonalResourceDisplayFrame"), FrameAcross("PlayerCastingBarFrame")
			local row = { t = now - run.legAt, x = math.abs(x), prd = prd and (prd - x) * side or nil }
			list[#list + 1] = row
			Log(("shift: %s +%.3f s you %.1f%%, offset %s%s | PRD %s, cast %s, slide %s%s"):format(run.leg, now - run.legAt,
				math.abs(x) * 100, Text(GetCVar(SHOULDER)), run.modelAt and "" or ", model not changed yet",
				row.prd and ("%+.1f"):format(row.prd * 100) or "-", cast and ("%+.1f"):format((cast - x) * side * 100) or "-",
				Text((ns.GetShoulderCamDebug and ns.GetShoulderCamDebug() or {}).followShift),
				IsPlayerMoving and IsPlayerMoving() and ", moving" or ""))
		elseif not run.saidGone then
			run.saidGone = true
			Log(("shift: no reading (%s)"):format(tostring(why)))
		end
	end)
	run.frame:Show()
end

local function Walls()
	if wallRun then WallsEnd("stopped") return end
	wallRun = { kept = {}, walks = {}, frame = wallRun and wallRun.frame or CreateFrame("Frame") }
	local run = wallRun
	WallsBegin(1)
	local last = {}
	ns.SetOnUpdate(run.frame, function(_, elapsed)
		if wallRun ~= run then return end
		local walk, now = run.walk, GetTime()
		local left = walk.ends - now
		ns.PadTestBox(("%d/2: WALK along that wall and past the tree, the same way, a few times"):format(#run.walks),
			("%s - %d s left"):format(walk.label, math.max(0, math.ceil(left))))
		local zoom, offset = Zoom(), Text(GetCVar(SHOULDER))
		local indoors = IsIndoors and ns.Flag(IsIndoors()) or false
		local debug = ns.GetShoulderCamDebug and ns.GetShoulderCamDebug() or {}
		local shift = type(debug.followShift) == "number" and debug.followShift or 0
		local wheel = now - (ns.lastPlayerZoomAt or -math.huge) < 1
		if last.zoom then
			local dz = zoom - last.zoom
			if math.abs(dz) >= 1 and not wheel then
				if dz < 0 then
					walk.pullIns = walk.pullIns + 1
					walk.biggest = math.max(walk.biggest, -dz)
				else
					walk.pushOuts = walk.pushOuts + 1
				end
			end
			if offset ~= last.offset then walk.offsets = walk.offsets + 1 end
			if indoors ~= last.indoors then walk.flips = walk.flips + 1 end
		end
		walk.low, walk.high = math.min(walk.low, zoom), math.max(walk.high, zoom)
		if not last.zoom or math.abs(zoom - last.zoom) >= 0.05 or offset ~= last.offset or indoors ~= last.indoors
			or math.abs(shift - (last.shift or 0)) >= 2 then
			Log(("walls: %5.2f zoom %.2f offset %s indoors %s slide %.0f%s%s"):format(WALL_STEP - left, zoom, offset,
				Text(indoors), shift, wheel and " wheel" or "", elapsed > 0.05 and (" frame %.0f ms"):format(elapsed * 1000) or ""))
			last.zoom, last.offset, last.indoors, last.shift = zoom, offset, indoors, shift
		end
		if left <= 0 then
			last.zoom = nil
			if #run.walks == 1 then
				WallsBegin(2)
			else
				WallsVerdict()
				WallsEnd("done")
			end
		end
	end)
	run.frame:Show()
	ns.Print("shoulder walls: 2 walks of 20 s; type it again to stop")
end

-- cams: one run for "what cameras does the game have, and what does its
-- ActionCam command set". Logs every console setting and command with "cam"
-- in its name (value, default, the game's own help line), then types each
-- ActionCam word (CAM_WORDS) from "off" and logs what changed, and puts every
-- setting back as it was. Nothing to do but wait for the box to say done.
-- (Not "default": on Forever it left unreadable text in five settings, run of
-- 2026-11-11, till the next "off".)
local CAM_WORDS = { "on", "basic", "full", "focusOn", "focusOff", "headMove", "heavyHeadMove", "lowHeadMove",
	"noHeadMove" }
local CAM_WAIT = 0.4 -- seconds for a word's settings to land
local camRun
local function CamNames()
	local names, seen, others = {}, {}, {}
	local list = C_Console and C_Console.GetAllCommands and select(2, pcall(C_Console.GetAllCommands))
		or (_G.ConsoleGetAllCommands and select(2, pcall(_G.ConsoleGetAllCommands)))
	for _, info in ipairs(type(list) == "table" and list or {}) do
		local name = type(info) == "table" and info.command
		if type(name) == "string" and name:lower():find("cam", 1, true) then
			local ok, value = pcall(GetCVar, name)
			if ok and value ~= nil then
				if not seen[name] then seen[name], names[#names + 1] = info, name end
			else
				others[#others + 1] = info
			end
		end
	end
	for _, name in ipairs(CAMERA_CVARS) do
		if not seen[name] and GetCVar(name) ~= nil then seen[name], names[#names + 1] = {}, name end
	end
	table.sort(names)
	return names, seen, others, type(list) == "table" and #list or nil
end
local function CamRead(names)
	local values = {}
	for _, name in ipairs(names) do values[name] = Text(GetCVar(name)) end
	return values
end
local function CamExec(word)
	if not ConsoleExec then return "no ConsoleExec" end
	local ok, err = pcall(ConsoleExec, "ActionCam " .. word)
	return ok and "ran" or ("failed: " .. Text(err))
end
local function CamEnd()
	local run = camRun
	camRun = nil
	local back = 0
	for _, name in ipairs(run.names) do
		if Text(GetCVar(name)) ~= run.start[name] then
			pcall(SetCVar, name, run.start[name])
			back = back + 1
		end
	end
	ns.shoulderTestHold = nil
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	Log(("cams: done, %d settings put back"):format(back))
	ns.PadTestBox("Cams run done", "check log: /reload", 0.3, 1, 0.3)
	C_Timer.After(8, function() if not camRun then ns.PadTestBoxHide() end end)
end
local function CamStep(at)
	local run = camRun
	local word = CAM_WORDS[at]
	if not word then return CamEnd() end
	ns.PadTestBox(("Cams %d/%d"):format(at, #CAM_WORDS), "ActionCam " .. word .. " (just wait)", 0.7, 0.7, 0.7)
	local off = CamExec("off")
	C_Timer.After(CAM_WAIT, function()
		if camRun ~= run then return end
		local before = CamRead(run.names)
		local result = CamExec(word)
		C_Timer.After(CAM_WAIT, function()
			if camRun ~= run then return end
			local after, changed = CamRead(run.names), {}
			for _, name in ipairs(run.names) do
				if after[name] ~= before[name] then
					changed[#changed + 1] = ("%s %s -> %s"):format(name, before[name], after[name])
				end
			end
			Log(("cams: ActionCam %s (off %s, it %s): %d changed from off"):format(word, off, result, #changed))
			for _, line in ipairs(changed) do Log("cams:   " .. line) end
			CamStep(at + 1)
		end)
	end)
end
local function Cams()
	if camRun then return ns.Print("shoulder cams: already running") end
	local names, seen, others, total = CamNames()
	Log(("cams: %s | console list %s entries, %d settings and %d commands with 'cam'"):format(Who(), Text(total), #names, #others))
	for _, name in ipairs(names) do
		local default = C_CVar and C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name)
		Log(("cams: setting %s = %s (default %s) | %s"):format(name, Text(GetCVar(name)), Text(default), Text(seen[name].help)))
	end
	for _, info in ipairs(others) do
		Log(("cams: command %s (type %s) | %s"):format(Text(info.command), Text(info.commandType), Text(info.help)))
	end
	camRun = { names = names, start = CamRead(names) }
	ns.shoulderTestHold = true
	-- (What "off" itself changes from how things are now.)
	local result = CamExec("off")
	C_Timer.After(CAM_WAIT, function()
		local run = camRun
		if not run then return end
		local after, count = CamRead(run.names), 0
		for _, name in ipairs(run.names) do
			if after[name] ~= run.start[name] then
				count = count + 1
				Log(("cams:   off: %s %s -> %s"):format(name, run.start[name], after[name]))
			end
		end
		Log(("cams: ActionCam off (%s): %d changed from how it was"):format(result, count))
		CamStep(1)
	end)
	ns.Print("shoulder cams: running, about 10 s; the warning popup may come up, leave it")
end

-- map: mapping what each of the game's camera settings does. Run 1, "still":
-- you stand still and touch nothing while recording the screen. Per trial
-- (MAP_STILL) the settings named go on over a plain camera (ActionCam off),
-- then the same moves each time: wait, zoom in 3 and back out; then the
-- settings go back. Each
-- trial's start and its zoom every 0.05 s are logged; the view's moves are
-- read off the recording. Typed again while running: stops. What was changed
-- is kept in the saved settings till it's back, so a reload mid-run can't
-- leave it on.
-- (The first run, 2026-11-11: 2 minutes in, at trial 22, the standing-still
-- camera took the view and turned and zoomed through the rest. So while a run
-- is on it holds the view as a camera of its own ("maptest"), and keeps
-- "stood still since" at now. "map still 22" starts at trial 22.
-- And from its first trials the view's tilt wandered off, to the sky by trial
-- 10: the turn and tilt moves went at your full speed (MoveView's number
-- does nothing), 72 and 36 degrees each way, and didn't come back to where
-- they began. The second run held the turn and tilt speed settings at 10 and
-- set the saved view at each trial's start: the turns were as big as before
-- (a speed setting written low is put back as yours by Core.lua's watch,
-- unless held with ns.SetHeldSpeed), and SetView blends over about a second,
-- into the trial. So this run makes no turn or tilt at all, only the zoom
-- (turning's for the walking run, with held speeds), and the saved view
-- (view VIEW_SLOT) is set as each trial's settings go back, with
-- TRIAL_LENGTH - TRIAL_BACK seconds for its blend before the next.)
do
	local VIEW_SLOT = 4
	local P, H, F = "test_cameraDynamicPitch", "test_cameraHeadMovementStrength", "test_cameraTargetFocus"
	local PLAIN = { [SHOULDER] = "0", [P] = "0", [H] = "0", [F .. "EnemyEnable"] = "0", [F .. "InteractEnable"] = "0" }
	local MAP_STILL = {
		{ "plain camera" },
		{ "shoulder 2", { [SHOULDER] = "2" } },
		{ "shoulder 2 + keep character centered", { [SHOULDER] = "2", [CENTERED] = "1" } },
		{ "shoulder 2 + reduce unexpected movement", { [SHOULDER] = "2", [REDUCE] = "1" } },
		{ "tilt", { [P] = "1" } },
		{ "tilt + feet pad 0.2", { [P] = "1", [P .. "BaseFovPad"] = "0.2" } },
		{ "tilt + feet pad 0.7", { [P] = "1", [P .. "BaseFovPad"] = "0.7" } },
		{ "tilt + down scale 1", { [P] = "1", [P .. "BaseFovPadDownScale"] = "1" } },
		{ "tilt + flying pad 0.2", { [P] = "1", [P .. "BaseFovPadFlying"] = "0.2" } },
		{ "tilt + smart pivot cutoff 30", { [P] = "1", [P .. "SmartPivotCutoffDist"] = "30" } },
		{ "tilt + keep character centered", { [P] = "1", [CENTERED] = "1" } },
		{ "head movement 2", { [H] = "2" } },
		{ "head 2 + standing strength 1", { [H] = "2", test_cameraHeadMovementStandingStrength = "1" } },
		{ "head 2 + standing damp rate 1", { [H] = "2", test_cameraHeadMovementStandingDampRate = "1" } },
		{ "head 2 + range scale 20", { [H] = "2", test_cameraHeadMovementRangeScale = "20" } },
		{ "head 2 + dead zone 0.2", { [H] = "2", test_cameraHeadMovementDeadZone = "0.2" } },
		{ "bobbing", { cameraBobbing = "1" } },
		{ "bobbing + smooth speed 0.1", { cameraBobbing = "1", cameraBobbingSmoothSpeed = "0.1" } },
		{ "custom view smoothing", { cameraCustomViewSmoothing = "1" } },
		{ "distance rate x3", { cameraDistanceRateMult = "3" } },
		{ "zoom speed 5", { cameraZoomSpeed = "5" } },
		{ "zoom speed 50", { cameraZoomSpeed = "50" } },
		{ "field of view 60", { cameraFov = "60" } },
		{ "field of view 60, smooth speed 0.05", { cameraFov = "60", cameraFoVSmoothSpeed = "0.05" } },
		{ "ground smooth speed 1", { cameraGroundSmoothSpeed = "1" } },
		{ "yaw smooth speed 20", { cameraYawSmoothSpeed = "20" } },
		{ "yaw smooth min/max 10/30", { cameraYawSmoothMin = "10", cameraYawSmoothMax = "30" } },
		{ "pitch smooth speed 5", { cameraPitchSmoothSpeed = "5" } },
		{ "pitch smooth min/max 10/60", { cameraPitchSmoothMin = "10", cameraPitchSmoothMax = "60" } },
		{ "pivot off", { cameraPivot = "0" } },
		{ "pivot DX max 0.5", { cameraPivotDXMax = "0.5" } },
		{ "pivot DY min 0.5", { cameraPivotDYMin = "0.5" } },
		{ "smooth off", { cameraSmooth = "0" } },
		{ "smooth pitch off", { cameraSmoothPitch = "0" } },
		{ "smooth yaw off", { cameraSmoothYaw = "0" } },
		{ "follow style 1", { cameraSmoothStyle = "1" } },
		{ "follow style 2", { cameraSmoothStyle = "2" } },
		{ "follow style 4", { cameraSmoothStyle = "4" } },
		{ "smooth time min/max 2/2", { cameraSmoothTimeMin = "2", cameraSmoothTimeMax = "2" } },
		{ "tracking style 1", { cameraSmoothTrackingStyle = "1" } },
		{ "target smooth speed 10", { cameraTargetSmoothSpeed = "10" } },
		{ "terrain tilt", { cameraTerrainTilt = "1" } },
		{ "Z smooth 2", { cameraZSmooth = "2" } },
		{ "Z smooth 0", { cameraZSmooth = "0" } },
		{ "action combat camera", { ActionCombatCameraEnable = "1" } },
		{ "follow on stick", { CameraFollowOnStick = "1" } },
		{ "max zoom factor 2.6", { cameraDistanceMaxZoomFactor = "2.6" } },
		{ "plain camera again" },
	}
	-- (Seconds into a trial; each move's the same in every trial.)
	local MOVES = {
		{ 1.0, "CameraZoomIn", 3 }, { 2.0, "CameraZoomOut", 3 },
	}
	local TRIAL_BACK, TRIAL_LENGTH = 3.0, 4.5
	local run
	local function Put(values)
		for name, value in pairs(values) do
			if GetCVar(name) ~= nil then pcall(SetCVar, name, value) end
		end
	end
	-- Sets these, remembering (in the saved settings too) what each was.
	local function Change(values)
		local keep = ns.db.shoulderMapKeep or {}
		ns.db.shoulderMapKeep = keep
		for name, value in pairs(values) do
			local now = GetCVar(name)
			if now ~= nil then
				if keep[name] == nil then keep[name] = Text(now) end
				pcall(SetCVar, name, value)
			end
		end
	end
	local function AllBack()
		local keep = ns.db and ns.db.shoulderMapKeep
		if not keep then return 0 end
		local count = 0
		for name, value in pairs(keep) do
			pcall(SetCVar, name, value)
			count = count + 1
		end
		ns.db.shoulderMapKeep = nil
		return count
	end
	local function End(why)
		if not run then return end
		run.ticker:Cancel()
		if run.events then run.events:UnregisterAllEvents() end
		if run.view then ns.CallCameraFunction("SetView", VIEW_SLOT) end
		run = nil
		local count = AllBack()
		ns.shoulderTestHold = nil
		if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
		Log(("map: %s, %d settings back"):format(why, count))
	end
	local function Begin(at)
		local trial = MAP_STILL[at]
		if not trial then
			End("done")
			ns.PadTestBox("Map run done", "stop the recording, then /reload", 0.3, 1, 0.3)
			C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
			return
		end
		local missing = {}
		for name in pairs(trial[2] or {}) do
			if GetCVar(name) == nil then missing[#missing + 1] = name end
		end
		run.at, run.began, run.move, run.back, run.zooms = at, GetTime(), 1, false, {}
		Change(trial[2] or {})
		Log(("map: trial %d (%s) starts, zoom %.2f%s"):format(at, trial[1], Zoom(),
			#missing > 0 and (", not on this client: " .. table.concat(missing, ", ")) or ""))
		ns.PadTestBox(("Map %d/%d  %s"):format(at, #MAP_STILL, trial[1]), "stand still, hands off", 0.7, 0.7, 0.7)
	end
	local function Tick()
		if not run then return end
		ns.stillSince = GetTime()
		if not run.at then return end
		local into = GetTime() - run.began
		while MOVES[run.move] and into >= MOVES[run.move][1] do
			local move = MOVES[run.move]
			ns.CallCameraFunction(move[2], move[3])
			run.move = run.move + 1
		end
		if into >= 1.0 and into < TRIAL_BACK then run.zooms[#run.zooms + 1] = ("%.2f"):format(Zoom()) end
		if not run.back and into >= TRIAL_BACK then
			run.back = true
			Log(("map: trial %d zoom from 1.0 s, every 0.05 s: %s"):format(run.at, table.concat(run.zooms, " ")))
			-- (This trial's settings back to how they were; the plain camera stays.)
			local keep, back = ns.db.shoulderMapKeep or {}, {}
			for name in pairs(MAP_STILL[run.at][2] or {}) do
				back[name] = PLAIN[name] or keep[name]
			end
			Put(back)
			if run.view then ns.CallCameraFunction("SetView", VIEW_SLOT) end
		end
		if into >= TRIAL_LENGTH then Begin(run.at + 1) end
	end
	-- Run 2, "talk": the camera's turn to whoever you talk to
	-- (test_cameraTargetFocusInteract...). You stand near an NPC that opens a
	-- window (a vendor, a quest giver), it well off to one side of the screen,
	-- and right-click it once per trial when the box says; the window's closed
	-- for you TALK_HOLD later, and the view's given TALK_RETURN to come back.
	-- Logged per trial: when the window opened and closed, and the NPC's
	-- nameplate's spot every 0.05 s where the game lets it be read; the turn's
	-- read off the recording.
	local I = F .. "Interact"
	local MAP_TALK = {
		{ "focus off" },
		{ "focus on", { [I .. "Enable"] = "1" } },
		{ "turn strength 0.3", { [I .. "Enable"] = "1", [I .. "StrengthYaw"] = "0.3" } },
		{ "turn strength 2", { [I .. "Enable"] = "1", [I .. "StrengthYaw"] = "2" } },
		{ "tilt strength 0", { [I .. "Enable"] = "1", [I .. "StrengthPitch"] = "0" } },
		{ "tilt strength 2", { [I .. "Enable"] = "1", [I .. "StrengthPitch"] = "2" } },
		{ "target smooth speed 10", { [I .. "Enable"] = "1", cameraTargetSmoothSpeed = "10" } },
		{ "target smooth speed 400", { [I .. "Enable"] = "1", cameraTargetSmoothSpeed = "400" } },
		{ "yaw smooth speed 20", { [I .. "Enable"] = "1", cameraYawSmoothSpeed = "20" } },
		{ "pitch smooth speed 5", { [I .. "Enable"] = "1", cameraPitchSmoothSpeed = "5" } },
		{ "smooth off", { [I .. "Enable"] = "1", cameraSmooth = "0" } },
		{ "follow style 4", { [I .. "Enable"] = "1", cameraSmoothStyle = "4" } },
		{ "with shoulder 2", { [I .. "Enable"] = "1", [SHOULDER] = "2" } },
		{ "focus on again", { [I .. "Enable"] = "1" } },
	}
	-- Run 3, "ramp": whether the turn follows its strength while the window's
	-- already open, so a slow turn can be made by stepping it (the talk run,
	-- 2026-11-11: no speed setting, the turn's always about 0.2 s; strength is
	-- a straight share). step = the strengths jump from 0 to full this long
	-- after the window opens; ramp = they go from 0 to full over this long
	-- (eased); yawOnly = the tilt strength stays 0; enableAt = focus itself
	-- switched on this long after. Each write is logged.
	local MAP_RAMP = {
		{ "focus on, as before", { [I .. "Enable"] = "1" }, hold = 4 },
		{ "0, then full at once after 1.5 s", { [I .. "Enable"] = "1", [I .. "StrengthYaw"] = "0",
			[I .. "StrengthPitch"] = "0" }, step = 1.5, hold = 4 },
		{ "0 to full over 2 s", { [I .. "Enable"] = "1", [I .. "StrengthYaw"] = "0", [I .. "StrengthPitch"] = "0" },
			ramp = 2, hold = 4 },
		{ "0 to full over 2 s, turn only", { [I .. "Enable"] = "1", [I .. "StrengthYaw"] = "0",
			[I .. "StrengthPitch"] = "0" }, ramp = 2, yawOnly = true, hold = 4 },
		{ "focus switched on 1.5 s in", { [I .. "Enable"] = "0" }, enableAt = 1.5, hold = 4 },
	}
	-- Run 4, "back": the way back as the window closes is the game's 0.2 s snap
	-- (2026-11-12: "when you stop talking it's really fast"); once closed the
	-- focus has no one to turn to, so slowing it means the camera itself being
	-- where the focus points before the close. swing = { at, for, degrees a
	-- second, ramp }: camera follow swings it round behind you (ns.CenterCamera,
	-- as the quest cam does: you face whoever you talk to); down = { at, over }:
	-- the strengths eased back to 0 (what a slow way back looks like, if the
	-- close were known ahead). The run closes each window at hold; your facing
	-- is logged at the open, the close and 2.5 s after.
	local SWING = 45 -- degrees a second at most (the quest cam's)
	local MAP_BACK = {
		{ "as built", { [I .. "Enable"] = "1", [I .. "StrengthYaw"] = "0", [I .. "StrengthPitch"] = "0" },
			ramp = 1.5, hold = 4.5 },
		{ "swing behind you, focus kept", { [I .. "Enable"] = "1", [I .. "StrengthYaw"] = "0",
			[I .. "StrengthPitch"] = "0" }, ramp = 1.5, swing = { 1.6, 2.6, SWING, 1 }, hold = 4.5 },
		{ "swing behind you, focus eased off", { [I .. "Enable"] = "1", [I .. "StrengthYaw"] = "0",
			[I .. "StrengthPitch"] = "0" }, ramp = 1.5, swing = { 1.6, 2.6, SWING, 1 }, down = { 1.6, 2.4 }, hold = 4.5 },
		{ "eased back before the close", { [I .. "Enable"] = "1", [I .. "StrengthYaw"] = "0",
			[I .. "StrengthPitch"] = "0" }, ramp = 1.5, down = { 2.5, 1.5 }, hold = 4.5 },
		{ "as built again", { [I .. "Enable"] = "1", [I .. "StrengthYaw"] = "0", [I .. "StrengthPitch"] = "0" },
			ramp = 1.5, hold = 4.5 },
	}
	local function Facing()
		local ok, facing = pcall(GetPlayerFacing)
		local made, text = pcall(string.format, "%.1f", ok and facing and math.deg(facing) or -1)
		return made and text or "secret"
	end
	-- Run 6, "friend" (2026-11-14): can the turn stay on whoever you talk to
	-- once the talk's over? The talk turn is the game's and goes with the talk
	-- (Accept ends it, then the next quest's window opens: the camera goes to
	-- the middle and back). The game's turn to your target (the enemy focus)
	-- stayed turned after a clear on retail, no snap ("enemy" run), but it was
	-- only ever tried on enemies. So, with the NPC targeted: does it turn to a
	-- friendly target at all (3), and does it keep the view on them when the
	-- talk's closed (2, 4) where the talk turn alone snaps back (1)? Both are
	-- eased in over 1.5 s (out of combat it only moves while its strengths
	-- change). Screenshots: at the open, just before the close, 0.4 s and 2 s
	-- after it; read off those.
	local TE = F .. "Enemy"
	local TALK_OFF = { [I .. "Enable"] = "1", [I .. "StrengthYaw"] = "0", [I .. "StrengthPitch"] = "0" }
	local AIM_OFF = { [TE .. "Enable"] = "1", [TE .. "StrengthYaw"] = "0", [TE .. "StrengthPitch"] = "0" }
	local function Both(a, b)
		local both = {}
		for k, v in pairs(a) do both[k] = v end
		for k, v in pairs(b) do both[k] = v end
		return both
	end
	local MAP_FRIEND = {
		{ "talk turn only (as now)", TALK_OFF, ramp = 1.5, hold = 4, shots = true },
		{ "talk turn + target turn", Both(TALK_OFF, AIM_OFF), ramp = 1.5, aimRamp = true, hold = 4, shots = true },
		{ "target turn only", Both({ [I .. "Enable"] = "0" }, AIM_OFF), ramp = 1.5, aimRamp = true, hold = 4,
			shots = true },
		{ "talk turn + target turn again", Both(TALK_OFF, AIM_OFF), ramp = 1.5, aimRamp = true, hold = 4, shots = true },
	}
	-- (Who the target is, against who you talk to, and the turn settings now.)
	local function FriendState()
		local function Read(fn, ...)
			local ok, value = pcall(fn, ...)
			if not ok then return "error" end
			if issecretvalue and issecretvalue(value) then return "secret" end
			return tostring(value)
		end
		return ("target %s (is the NPC %s, attackable %s, friend %s), npc %s | talk focus %s %s/%s, target focus %s %s/%s"):format(
			Read(UnitName, "target"), Read(UnitIsUnit, "target", "npc"), Read(UnitCanAttack, "player", "target"),
			Read(UnitIsFriend, "player", "target"), Read(UnitName, "npc"), Text(GetCVar(I .. "Enable")),
			Text(GetCVar(I .. "StrengthYaw")), Text(GetCVar(I .. "StrengthPitch")), Text(GetCVar(TE .. "Enable")),
			Text(GetCVar(TE .. "StrengthYaw")), Text(GetCVar(TE .. "StrengthPitch")))
	end
	-- A screenshot, the box hidden for it (back 0.2 s on), named in the log by
	-- the file's time (WoWScrnShot_MMDDYY_HHMMSS). Called from our own
	-- function: handed to a timer itself it was refused on Forever.
	local function Shot(what, line)
		ns.PadTestBoxHide()
		local ok, err = pcall(function() Screenshot() end)
		Log(ok and ("map: screenshot %s at %s | %s"):format(what, date("%m%d%y_%H%M%S"), FriendState())
			or ("map: screenshot %s failed: %s"):format(what, tostring(err)))
		local this = run
		C_Timer.After(0.2, function()
			if run == this and run.at then
				ns.PadTestBox(("Talk %d/%d  %s"):format(run.at, #run.list, run.list[run.at][1]), line, 1, 0.82, 0)
			end
		end)
	end
	local PITCH_FULL = "0.75" -- (the game's default tilt strength)
	local TALK_SETTLE, TALK_HOLD, TALK_RETURN = 1.5, 2.5, 2.5
	local TALK_EVENTS = { "GOSSIP_SHOW", "MERCHANT_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
		"QUEST_COMPLETE", "TRAINER_SHOW" }
	-- (The NPC's nameplate can't be measured on Forever: GetCenter refused, the
	-- talk run. So the turn's read off the recording only.)
	local function TalkClose()
		if C_GossipInfo and C_GossipInfo.CloseGossip then pcall(C_GossipInfo.CloseGossip) end
		for _, name in ipairs({ "CloseMerchant", "CloseQuest", "CloseTrainer" }) do
			if _G[name] then pcall(_G[name]) end
		end
	end
	local function TalkBox(line, r, g, b)
		ns.PadTestBox(("Talk %d/%d  %s"):format(run.at, #run.list, run.list[run.at][1]), line, r, g, b)
	end
	local function TalkBegin(at)
		local trial = run.list[at]
		if not trial then
			End("done")
			ns.PadTestBox("Talk run done", "stop the recording, then /reload", 0.3, 1, 0.3)
			C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
			return
		end
		run.at, run.phase, run.began, run.writes = at, "settle", GetTime(), {}
		run.lastYaw, run.lastPitch, run.enabled, run.swung = nil, nil, nil, nil
		run.shotOpen, run.shotTurned, run.shotClosed, run.shotAfter = nil, nil, nil, nil
		Change(trial[2] or {})
		Log(("map: talk %d (%s) on, zoom %.2f"):format(at, trial[1], Zoom()))
		TalkBox("wait...", 0.7, 0.7, 0.7)
	end
	local function TalkTick()
		if not run then return end
		ns.stillSince = GetTime()
		if not run.at then return end
		local into = GetTime() - run.began
		if run.phase == "settle" and into >= TALK_SETTLE then
			run.phase, run.clickFacing = "click", Facing()
			TalkBox(run.friend and "LEFT-CLICK THE NPC to target them, then RIGHT-CLICK them (then hands off)"
				or "RIGHT-CLICK THE NPC now (then hands off)", 0.3, 1, 0.3)
		elseif run.phase == "open" then
			local trial = run.list[run.at]
			if trial.ramp or trial.step then
				local k
				if trial.ramp then
					k = math.min(1, into / trial.ramp)
					k = k * k * (3 - 2 * k)
				else
					k = into >= trial.step and 1 or 0
				end
				if trial.down and into >= trial.down[1] then
					local d = math.min(1, (into - trial.down[1]) / trial.down[2])
					k = k * (1 - d * d * (3 - 2 * d))
				end
				local yaw = ("%.3f"):format(k)
				local pitch = ("%.3f"):format(trial.yawOnly and 0 or k * tonumber(PITCH_FULL))
				if yaw ~= run.lastYaw or pitch ~= run.lastPitch then
					pcall(SetCVar, I .. "StrengthYaw", yaw)
					pcall(SetCVar, I .. "StrengthPitch", pitch)
					-- (The target turn too, to the same strengths as the talk's.)
					if trial.aimRamp then
						pcall(SetCVar, TE .. "StrengthYaw", yaw)
						pcall(SetCVar, TE .. "StrengthPitch", pitch)
					end
					run.lastYaw, run.lastPitch = yaw, pitch
					run.writes[#run.writes + 1] = ("%.2f:%s/%s"):format(into, yaw, pitch)
				end
			end
			if trial.swing and not run.swung and into >= trial.swing[1] then
				run.swung = true
				ns.CenterCamera(trial.swing[2], trial.swing[3], 0, trial.swing[4])
				run.writes[#run.writes + 1] = ("%.2f:swing"):format(into)
			end
			if trial.enableAt and not run.enabled and into >= trial.enableAt then
				run.enabled = true
				pcall(SetCVar, I .. "Enable", "1")
				run.writes[#run.writes + 1] = ("%.2f:on"):format(into)
			end
			if trial.shots and not run.shotOpen and into >= 0.1 then
				run.shotOpen = true
				Shot(("%d open"):format(run.at), "hands off...")
			end
			if trial.shots and not run.shotTurned and into >= (trial.hold or TALK_HOLD) - 0.3 then
				run.shotTurned = true
				Shot(("%d turned, before the close"):format(run.at), "hands off: the window closes now")
			end
			if into >= (trial.hold or TALK_HOLD) then
				run.phase, run.began = "return", GetTime()
				TalkClose()
				Log(("map: talk %d closed, facing %s; written (s in: turn/tilt strength): %s"):format(run.at, Facing(),
					#run.writes > 0 and table.concat(run.writes, " ") or "nothing"))
				TalkBox("wait...", 0.7, 0.7, 0.7)
			end
		elseif run.phase == "return" then
			local trial = run.list[run.at]
			if trial.shots and not run.shotClosed and into >= 0.4 then
				run.shotClosed = true
				Shot(("%d closed 0.4 s"):format(run.at), "hands off...")
			end
			if trial.shots and not run.shotAfter and into >= 2 then
				run.shotAfter = true
				Shot(("%d closed 2 s"):format(run.at), "hands off...")
			end
			if into >= TALK_RETURN then
				Log(("map: talk %d back, facing %s"):format(run.at, Facing()))
				local keep, back = ns.db.shoulderMapKeep or {}, {}
				for name in pairs(run.list[run.at][2] or {}) do
					back[name] = PLAIN[name] or keep[name]
				end
				Put(back)
				if run.view then ns.CallCameraFunction("SetView", VIEW_SLOT) end
				TalkBegin(run.at + 1)
			end
		end
	end
	local function TalkStart(list, label)
		ns.shoulderTestHold = true
		Change(PLAIN)
		-- (Ramps: the strengths go back too, whichever trial ends the run.)
		Change({ [I .. "StrengthYaw"] = GetCVar(I .. "StrengthYaw"), [I .. "StrengthPitch"] = GetCVar(I .. "StrengthPitch"),
			[TE .. "StrengthYaw"] = GetCVar(TE .. "StrengthYaw"), [TE .. "StrengthPitch"] = GetCVar(TE .. "StrengthPitch") })
		run = { ticker = C_Timer.NewTicker(0.05, TalkTick), view = _G.SaveView and pcall(_G.SaveView, VIEW_SLOT) or false,
			events = CreateFrame("Frame"), list = list }
		for _, event in ipairs(TALK_EVENTS) do pcall(run.events.RegisterEvent, run.events, event) end
		local this = run
		run.events:SetScript("OnEvent", function(_, event)
			if run ~= this or run.phase ~= "click" then return end
			run.phase, run.began = "open", GetTime()
			Log(("map: talk %d opened (%s) by %s, facing %s (at the click %s) | %s"):format(run.at, event,
				Text(UnitName("npc")), Facing(), run.clickFacing or "?", FriendState()))
			TalkBox("hands off...", 1, 0.82, 0)
		end)
		Log(("map: %s run, %d trials | %s | screen %.0f x %.0f, view saved %s, zoom %.2f"):format(label, #list, Who(),
			WorldFrame:GetWidth(), WorldFrame:GetHeight(), Text(run.view), Zoom()))
		ns.Print(("shoulder map: record your screen; %d right-clicks on the NPC, told when; type it again to stop"):format(
			#list))
		C_Timer.After(1, function() if run == this and not run.at then TalkBegin(1) end end)
	end
	-- Run 5, "walk": what the game's settings do while you move (2026-11-12),
	-- over the Shoulder Cam as built. Per trial you're told, by the box: stand,
	-- WALK forward, keep walking and TURN LEFT (hold A), STOP; then its
	-- settings go back to yours. Logged per trial: its start and, every 0.1 s,
	-- your speed and facing (to line the recording up); the view's moves are
	-- read off the recording. A setting this client hasn't got is named in the
	-- trial's start line.
	-- (First run, 2026-11-12, Stormwind streets: trials with the same settings
	-- came out as far apart as any two settings, the walks too uneven (mouse
	-- turns, a turn or none, slopes). So the second: on flat open ground, no
	-- mouse, and as built three times through it, to show how far apart the
	-- same settings come out; a setting counts only if it's further off.)
	local MAP_WALK = {
		{ "as built" },
		{ "follow style 2 (always)", { cameraSmoothStyle = "2" } },
		{ "follow style 4 (smart)", { cameraSmoothStyle = "4" } },
		{ "terrain tilt", { cameraTerrainTilt = "1" } },
		{ "as built (2nd)" },
		{ "tilt (dynamic pitch)", { [P] = "1" } },
		{ "head movement 1", { [H] = "1" } },
		{ "bobbing", { cameraBobbing = "1" } },
		{ "as built (3rd)" },
	}
	-- (Seconds into a trial: what the box says from then.)
	local WALK_STEPS = {
		{ 0, "stand still, hands off the mouse", 0.7, 0.7, 0.7 }, { 1.5, "WALK FORWARD (hold W only)", 0.3, 1, 0.3 },
		{ 4.5, "keep walking + TURN LEFT (W and your turn key, no mouse)", 1, 0.82, 0 }, { 7, "STOP, hands off", 1, 0.3, 0.3 },
	}
	local WALK_LENGTH, WALK_BACK = 10, 8.5
	local function WalkBegin(at)
		local trial = MAP_WALK[at]
		if not trial then
			End("done")
			ns.PadTestBox("Walk run done", "stop the recording, then /reload", 0.3, 1, 0.3)
			C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
			return
		end
		local missing = {}
		for name in pairs(trial[2] or {}) do
			if GetCVar(name) == nil then missing[#missing + 1] = name end
		end
		run.at, run.began, run.step, run.track, run.back = at, GetTime(), 0, {}, false
		Change(trial[2] or {})
		Log(("map: walk %d (%s) starts, zoom %.2f, offset %s%s"):format(at, trial[1], Zoom(), Text(GetCVar(SHOULDER)),
			#missing > 0 and (", not on this client: " .. table.concat(missing, ", ")) or ""))
	end
	local function WalkTick()
		if not run then return end
		ns.stillSince = GetTime()
		if not run.at then return end
		local into = GetTime() - run.began
		local step = WALK_STEPS[run.step + 1]
		if step and into >= step[1] then
			run.step = run.step + 1
			ns.PadTestBox(("Walk %d/%d  %s"):format(run.at, #MAP_WALK, MAP_WALK[run.at][1]), step[2], step[3], step[4], step[5])
			Log(("map: walk %d: %s"):format(run.at, step[2]))
		end
		if into < WALK_BACK and #run.track < into * 10 then
			local ok, speed = pcall(GetUnitSpeed, "player")
			local made, text = pcall(string.format, "%.1f", ok and speed or -1)
			run.track[#run.track + 1] = ("%.1f:%s:%s"):format(into, made and text or "?", Facing())
		end
		if not run.back and into >= WALK_BACK then
			run.back = true
			Log(("map: walk %d track (s in:speed:facing): %s"):format(run.at, table.concat(run.track, " ")))
			local keep, back = ns.db.shoulderMapKeep or {}, {}
			for name in pairs(MAP_WALK[run.at][2] or {}) do back[name] = keep[name] end
			Put(back)
		end
		if into >= WALK_LENGTH then WalkBegin(run.at + 1) end
	end
	local function WalkStart()
		run = { ticker = C_Timer.NewTicker(0.05, WalkTick) }
		Log(("map: walk run, %d trials of %d s | %s | offset %s, zoom %.2f"):format(#MAP_WALK, WALK_LENGTH, Who(),
			Text(GetCVar(SHOULDER)), Zoom()))
		ns.Print(("shoulder map: record your screen; about %d minutes in the open, walk and turn when told; " ..
			"type it again to stop"):format(math.ceil(#MAP_WALK * WALK_LENGTH / 60)))
		local this = run
		C_Timer.After(1, function() if run == this and not run.at then WalkBegin(1) end end)
	end
	-- Run 6, "enemy": the camera's turn to an enemy you target
	-- (test_cameraTargetFocusEnemy..., what "ActionCam full" adds), over the
	-- Shoulder Cam as built. You stand with an enemy well off to one side of
	-- the screen (one that won't attack: a training dummy, or a low one) and
	-- per trial target it when the box says, then clear it (Esc) when told.
	-- ramp = the strengths go 0 to full over this long once targeted (the talk
	-- turn's way); down = { at, over }: eased back to 0 before the clear.
	-- Logged per trial: when it was targeted and cleared, what was written,
	-- your facing; the turn's read off the recording.
	local E = F .. "Enemy"
	local MAP_ENEMY = {
		{ "focus off", { [E .. "Enable"] = "0" } },
		{ "focus on", { [E .. "Enable"] = "1" } },
		{ "turn strength 0.3", { [E .. "Enable"] = "1", [E .. "StrengthYaw"] = "0.3" } },
		{ "tilt strength 0", { [E .. "Enable"] = "1", [E .. "StrengthPitch"] = "0" } },
		{ "eased in over 1.5 s", { [E .. "Enable"] = "1", [E .. "StrengthYaw"] = "0", [E .. "StrengthPitch"] = "0" },
			ramp = 1.5 },
		{ "eased in, eased back before the clear", { [E .. "Enable"] = "1", [E .. "StrengthYaw"] = "0",
			[E .. "StrengthPitch"] = "0" }, ramp = 1.5, down = { 3, 1.5 } },
		{ "focus on again", { [E .. "Enable"] = "1" } },
	}
	local ENEMY_SETTLE, ENEMY_HOLD, ENEMY_RETURN = 2.5, 5, 3 -- seconds: before "target", targeted till "clear", after
	local function EnemyBox(line, r, g, b)
		ns.PadTestBox(("Enemy %d/%d  %s"):format(run.at, #MAP_ENEMY, MAP_ENEMY[run.at][1]), line, r, g, b)
	end
	local function EnemyBegin(at)
		local trial = MAP_ENEMY[at]
		if not trial then
			End("done")
			ns.PadTestBox("Enemy run done", "stop the recording, then /reload", 0.3, 1, 0.3)
			C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
			return
		end
		run.at, run.phase, run.began, run.writes, run.lastYaw, run.lastPitch = at, "settle", GetTime(), {}, nil, nil
		Change(trial[2] or {})
		Log(("map: enemy %d (%s) on, zoom %.2f, offset %s, focus %s turn %s tilt %s"):format(at, trial[1], Zoom(),
			Text(GetCVar(SHOULDER)), Text(GetCVar(E .. "Enable")), Text(GetCVar(E .. "StrengthYaw")),
			Text(GetCVar(E .. "StrengthPitch"))))
		EnemyBox("wait... (no target)", 0.7, 0.7, 0.7)
	end
	local function EnemyTick()
		if not run then return end
		ns.stillSince = GetTime()
		if not run.at then return end
		local into = GetTime() - run.began
		local trial = MAP_ENEMY[run.at]
		if run.phase == "settle" and into >= ENEMY_SETTLE then
			run.phase, run.clickFacing = "target", Facing()
			EnemyBox("TARGET THE ENEMY now (click it or Tab), then hands off", 0.3, 1, 0.3)
		elseif run.phase == "on" then
			if trial.ramp then
				local k = math.min(1, into / trial.ramp)
				k = k * k * (3 - 2 * k)
				if trial.down and into >= trial.down[1] then
					local d = math.min(1, (into - trial.down[1]) / trial.down[2])
					k = k * (1 - d * d * (3 - 2 * d))
				end
				local yaw, pitch = ("%.3f"):format(k * run.fullYaw), ("%.3f"):format(k * run.fullPitch)
				if yaw ~= run.lastYaw or pitch ~= run.lastPitch then
					pcall(SetCVar, E .. "StrengthYaw", yaw)
					pcall(SetCVar, E .. "StrengthPitch", pitch)
					run.lastYaw, run.lastPitch = yaw, pitch
					run.writes[#run.writes + 1] = ("%.2f:%s/%s"):format(into, yaw, pitch)
				end
			end
			if into >= ENEMY_HOLD and not run.told then
				run.told = true
				EnemyBox("CLEAR THE TARGET now (Esc), then hands off", 1, 0.82, 0)
			end
		elseif run.phase == "back" and into >= ENEMY_RETURN then
			Log(("map: enemy %d back, facing %s"):format(run.at, Facing()))
			local keep, back = ns.db.shoulderMapKeep or {}, {}
			for name in pairs(trial[2] or {}) do back[name] = keep[name] end
			Put(back)
			EnemyBegin(run.at + 1)
		end
	end
	local function EnemyStart()
		-- (The strengths go back too, whichever trial ends the run; full = the game's own, read now.)
		Change({ [E .. "Enable"] = GetCVar(E .. "Enable"), [E .. "StrengthYaw"] = GetCVar(E .. "StrengthYaw"),
			[E .. "StrengthPitch"] = GetCVar(E .. "StrengthPitch") })
		run = { ticker = C_Timer.NewTicker(0.05, EnemyTick), events = CreateFrame("Frame"),
			fullYaw = tonumber(GetCVar(E .. "StrengthYaw")) or 1, fullPitch = tonumber(GetCVar(E .. "StrengthPitch")) or 0.75 }
		pcall(run.events.RegisterEvent, run.events, "PLAYER_TARGET_CHANGED")
		local this = run
		run.events:SetScript("OnEvent", function()
			if run ~= this or not run.at then return end
			local has = UnitExists("target") and ns.Flag(UnitCanAttack("player", "target"))
			if has and run.phase == "target" then
				run.phase, run.began, run.told = "on", GetTime(), nil
				Log(("map: enemy %d targeted %s, facing %s (at the box %s)"):format(run.at, Text(UnitName("target")),
					Facing(), run.clickFacing or "?"))
				EnemyBox("hands off...", 1, 0.82, 0)
			elseif not UnitExists("target") and run.phase == "on" then
				Log(("map: enemy %d cleared %.1f s in, facing %s; written (s in: turn/tilt strength): %s"):format(run.at,
					GetTime() - run.began, Facing(), #run.writes > 0 and table.concat(run.writes, " ") or "nothing"))
				run.phase, run.began = "back", GetTime()
				EnemyBox("hands off...", 0.7, 0.7, 0.7)
			end
		end)
		Log(("map: enemy run, %d trials | %s | offset %s, zoom %.2f, the game's strengths turn %s tilt %s"):format(
			#MAP_ENEMY, Who(), Text(GetCVar(SHOULDER)), Zoom(), Text(run.fullYaw), Text(run.fullPitch)))
		ns.Print(("shoulder map: record your screen; %d targets, told when; type it again to stop"):format(#MAP_ENEMY))
		C_Timer.After(1, function() if run == this and not run.at then EnemyBegin(1) end end)
	end
	-- Run 7, "soft" (2026-11-16): Esc clears your target and the game's turn
	-- to it snaps back at once (Forever, user: "it comes back instant"), the
	-- strengths' 1.5 s glide back too late (they glide with no one to turn
	-- to). Clearing a target can't be held (protected), so: does the turn keep
	-- to the soft enemy target (SoftTargetEnemy), the one in front of you the
	-- game picks itself, once the hard one's gone? 1: as now (soft off), 2:
	-- soft on, strengths kept full after Esc (does it stay turned at all?),
	-- 3: soft on, eased back over 1.5 s (does it glide?). The soft target's
	-- logged every 0.1 s after Esc (the same enemy or not), with screenshots
	-- at full, then 0.1, 0.5, 1.0, 1.6 and 3 s after; read off those.
	local SE = "SoftTargetEnemy"
	local SOFT_ON = { [SE] = "3", [SE .. "Arc"] = "2", [SE .. "Range"] = "45" }
	local MAP_SOFT = {
		{ "as now: soft target off, eased back after Esc", { [SE] = "0" }, ease = true },
		{ "soft target on, the turn kept full after Esc", SOFT_ON },
		{ "soft target on, eased back after Esc", SOFT_ON, ease = true },
	}
	local SOFT_RAMP, SOFT_HOLD, SOFT_EASE, SOFT_AFTER = 1.5, 4, 1.5, 3.5
	-- (A second apart: the game names them by the second, so two in one second
	-- were one file, the run of 2026-11-16.)
	local SOFT_SHOTS = { 0.2, 1.2, 2.2, 3.2 }
	local function SoftBox(line, r, g, b)
		ns.PadTestBox(("Soft %d/%d  %s"):format(run.at, #MAP_SOFT, MAP_SOFT[run.at][1]), line, r, g, b)
	end
	local function Plain(fn, ...)
		local ok, value = pcall(fn, ...)
		if not ok then return nil, "error" end
		if issecretvalue and issecretvalue(value) then return nil, "secret" end
		return value
	end
	-- Who the soft enemy target is now, and whether it's the one you cleared.
	local function SoftNow()
		local exists, why = Plain(UnitExists, "softenemy")
		if why then return "soft " .. why, nil end
		if not exists then return "no soft target", false end
		local guid = Plain(UnitGUID, "softenemy")
		local same = guid and run.guid and guid == run.guid
		if same == nil then same = run.name and Plain(UnitName, "softenemy") == run.name or false end
		return ("soft %s (%s)"):format(Text(Plain(UnitName, "softenemy")), same and "the same one" or "another"), same
	end
	local function SoftStrengths(k)
		k = k * k * (3 - 2 * k)
		local yaw, pitch = ("%.3f"):format(k * run.fullYaw), ("%.3f"):format(k * run.fullPitch)
		if yaw ~= run.lastYaw or pitch ~= run.lastPitch then
			pcall(SetCVar, E .. "StrengthYaw", yaw)
			pcall(SetCVar, E .. "StrengthPitch", pitch)
			run.lastYaw, run.lastPitch = yaw, pitch
		end
	end
	local function SoftShot(what, line)
		ns.PadTestBoxHide()
		local ok, err = pcall(function() Screenshot() end)
		Log(ok and ("map: soft %d screenshot %s at %s | %s | strengths %s/%s"):format(run.at, what,
			date("%m%d%y_%H%M%S"), (SoftNow()), Text(GetCVar(E .. "StrengthYaw")), Text(GetCVar(E .. "StrengthPitch")))
			or ("map: soft %d screenshot %s failed: %s"):format(run.at, what, tostring(err)))
		local this = run
		C_Timer.After(0.2, function() if run == this and run.at then SoftBox(line, 1, 0.82, 0) end end)
	end
	local function SoftBegin(at)
		local trial = MAP_SOFT[at]
		if not trial then
			local lines = {}
			for i, verdict in ipairs(run.verdicts) do lines[#lines + 1] = ("%d: %s"):format(i, verdict) end
			Log("map: soft verdicts | " .. table.concat(lines, " | "))
			End("done")
			ns.PadTestBox("Soft run done", "/reload and say check log", 0.3, 1, 0.3)
			C_Timer.After(10, function() if not run then ns.PadTestBoxHide() end end)
			return
		end
		run.at, run.phase, run.began, run.lastYaw, run.lastPitch = at, "settle", GetTime(), nil, nil
		run.guid, run.name, run.shots, run.kept, run.lost, run.seen = nil, nil, {}, nil, nil, {}
		Put(trial[2])
		SoftStrengths(0)
		Log(("map: soft %d (%s) on | %s %s, arc %s, range %s | focus %s"):format(at, trial[1], SE, Text(GetCVar(SE)),
			Text(GetCVar(SE .. "Arc")), Text(GetCVar(SE .. "Range")), Text(GetCVar(E .. "Enable"))))
		SoftBox("wait... (no target)", 0.7, 0.7, 0.7)
	end
	local function SoftTick()
		if not run then return end
		ns.stillSince = GetTime()
		if not run.at then return end
		local into = GetTime() - run.began
		local trial = MAP_SOFT[run.at]
		if run.phase == "settle" and into >= 2 then
			if UnitExists("target") then
				SoftBox("CLEAR YOUR TARGET first (Esc)", 1, 0.3, 0.3)
			else
				run.phase = "target"
				-- (The view with no turn, to read the others against.)
				SoftShot("before targeting", "TAB to the enemy (well off to one side), then hands off")
			end
		elseif run.phase == "on" then
			SoftStrengths(math.min(1, into / SOFT_RAMP))
			if into >= SOFT_HOLD - 0.5 and not run.shots.full then
				run.shots.full = true
				SoftShot("at full", "hands off...")
			elseif into >= SOFT_HOLD and not run.told then
				run.told = true
				-- (The soft target on it while it's still targeted: without that
				-- there's nothing to test. A sheep, 2026-11-16: never picked.)
				local text, same = SoftNow()
				run.softBefore = same
				Log(("map: soft %d before Esc: %s"):format(run.at, text))
				SoftBox(same == false and trial[2] == SOFT_ON
					and "no soft target on it (try a RED enemy in front of you); PRESS ESC ONCE anyway"
					or "PRESS ESC ONCE now, then hands off", 1, 0.82, 0)
			end
		elseif run.phase == "back" then
			if trial.ease then SoftStrengths(1 - math.min(1, into / SOFT_EASE)) end
			for _, at in ipairs(SOFT_SHOTS) do
				if into >= at and not run.shots[at] then
					run.shots[at] = true
					SoftShot(("%.1f s after Esc"):format(at), "hands off...")
					break
				end
			end
			local slot = math.floor(into * 10)
			if not run.seen[slot] then
				run.seen[slot] = true
				local text, same = SoftNow()
				if same and not run.lost then run.kept = into elseif not same and not run.lost then run.lost = into end
				Log(("map: soft %d +%.1f s: %s | strengths %s/%s"):format(run.at, into, text,
					Text(GetCVar(E .. "StrengthYaw")), Text(GetCVar(E .. "StrengthPitch"))))
			end
			if into >= SOFT_AFTER then
				local verdict = trial[2] == SOFT_ON and not run.softBefore
					and "the soft target never picked it, even targeted: nothing tested (a critter? try a red enemy)"
					or run.kept and not run.lost and "the soft target kept the same enemy the whole time"
					or run.kept and ("the soft target kept the same enemy for %.1f s, then lost it"):format(run.lost)
					or "no soft target on that enemy after Esc"
				run.verdicts[#run.verdicts + 1] = trial[1] .. ": " .. verdict
				Log(("map: soft %d verdict: %s (the camera: read the screenshots)"):format(run.at, verdict))
				SoftBegin(run.at + 1)
			end
		end
	end
	-- from: the trial to start at (soft 3: the eased one only).
	local function SoftStart(from)
		if InCombatLockdown() then return ns.Print("shoulder map: out of a fight, please") end
		ns.shoulderTestHold = true -- (ShoulderCam.lua keeps its hands off the strengths meanwhile)
		-- (All of these go back at the end; full = the game's own strengths, read now.)
		Change({ [E .. "Enable"] = "1", [E .. "StrengthYaw"] = GetCVar(E .. "StrengthYaw"),
			[E .. "StrengthPitch"] = GetCVar(E .. "StrengthPitch"), [SE] = GetCVar(SE) or "0",
			[SE .. "Arc"] = GetCVar(SE .. "Arc") or "0", [SE .. "Range"] = GetCVar(SE .. "Range") or "0" })
		local yours = ns.db.shoulderCamYours or {}
		run = { ticker = C_Timer.NewTicker(0.05, SoftTick), events = CreateFrame("Frame"), verdicts = {},
			fullYaw = tonumber(yours[E .. "StrengthYaw"] or GetCVar(E .. "StrengthYaw")) or 0.5,
			fullPitch = tonumber(yours[E .. "StrengthPitch"] or GetCVar(E .. "StrengthPitch")) or 0.4 }
		-- (The Shoulder Cam keeps its own at 0 while nothing's targeted: the game's full is 0.5/0.4.)
		if run.fullYaw <= 0 then run.fullYaw = 0.5 end
		if run.fullPitch <= 0 then run.fullPitch = 0.4 end
		pcall(run.events.RegisterEvent, run.events, "PLAYER_TARGET_CHANGED")
		local this = run
		run.events:SetScript("OnEvent", function()
			if run ~= this or not run.at then return end
			local has = UnitExists("target") and ns.Flag(UnitCanAttack("player", "target"))
			if has and run.phase == "target" then
				run.phase, run.began, run.told = "on", GetTime(), nil
				run.guid, run.name = Plain(UnitGUID, "target"), Plain(UnitName, "target")
				Log(("map: soft %d targeted %s (guid %s), facing %s | %s"):format(run.at, Text(run.name),
					run.guid and "readable" or "unreadable", Facing(), (SoftNow())))
				SoftBox("hands off...", 1, 0.82, 0)
			elseif not UnitExists("target") and run.phase == "on" then
				Log(("map: soft %d cleared %.1f s in, facing %s | %s"):format(run.at, GetTime() - run.began, Facing(),
					(SoftNow())))
				run.phase, run.began = "back", GetTime()
				SoftBox("hands off...", 0.7, 0.7, 0.7)
			end
		end)
		Log(("map: soft run, %d trials | %s | offset %s, zoom %.2f, full strengths %s/%s"):format(#MAP_SOFT, Who(),
			Text(GetCVar(SHOULDER)), Zoom(), Text(run.fullYaw), Text(run.fullPitch)))
		ns.Print("shoulder map: soft run, 3 targets; do what the box says. Type it again to stop.")
		C_Timer.After(1, function() if run == this and not run.at then SoftBegin(from) end end)
	end
	-- Run 8, "switch" (2026-11-16): from one enemy to another, the game's
	-- turn jumps to the new one at once, a snap (user), the strengths full
	-- through it. A target change can't be held (protected), so: what if the
	-- strengths are dropped at the switch and eased back up? 1: as now (kept
	-- full), 2: to 0, eased up over 1.5 s, 3: to 30%, eased up over 1.5 s.
	-- Two enemies side by side, off to one side (a row of dummies). Screenshots
	-- on the first at full, then 0.2, 1.2, 2.2 and 3.2 s after the switch
	-- (a second apart: named by the second).
	local MAP_SWITCH = {
		{ "as now: kept full at the switch" },
		{ "dropped to 0 at the switch, eased up over 1.5 s", from = 0, ease = 1.5 },
		{ "dropped to 30% at the switch, eased up over 1.5 s", from = 0.3, ease = 1.5 },
		-- (4-6, the same day: 2 and 3 glided, but with a small turn back toward
		-- you first, a dip (user). Shallower drops, judged by eye: "switch 4".
		-- from is the share; the strength's eased from it, so 0.5, 0.6355 and
		-- 0.7555 are 50%, 70% and 85% of the strength.)
		{ "dropped to 50% at the switch, eased up over 1.5 s", from = 0.5, ease = 1.5, eye = true },
		{ "dropped to 70% at the switch, eased up over 1.5 s", from = 0.6355, ease = 1.5, eye = true },
		{ "dropped to 85% at the switch, eased up over 1.5 s", from = 0.7555, ease = 1.5, eye = true },
	}
	local SWITCH_SHOTS = { 0.2, 1.2, 2.2, 3.2 }
	local function SwitchBox(line, r, g, b)
		ns.PadTestBox(("Switch %d/%d  %s"):format(run.at, #MAP_SWITCH, MAP_SWITCH[run.at][1]), line, r, g, b)
	end
	local function SwitchShot(what, line)
		ns.PadTestBoxHide()
		local ok, err = pcall(function() Screenshot() end)
		Log(ok and ("map: switch %d screenshot %s at %s | target %s | strengths %s/%s"):format(run.at, what,
			date("%m%d%y_%H%M%S"), Text(Plain(UnitName, "target")), Text(GetCVar(E .. "StrengthYaw")),
			Text(GetCVar(E .. "StrengthPitch")))
			or ("map: switch %d screenshot %s failed: %s"):format(run.at, what, tostring(err)))
		local this = run
		C_Timer.After(0.2, function() if run == this and run.at then SwitchBox(line, 1, 0.82, 0) end end)
	end
	local function SwitchBegin(at)
		if not MAP_SWITCH[at] then
			End("done")
			ns.PadTestBox("Switch run done", "/reload and say check log", 0.3, 1, 0.3)
			C_Timer.After(10, function() if not run then ns.PadTestBoxHide() end end)
			return
		end
		run.at, run.phase, run.began, run.lastYaw, run.lastPitch = at, "settle", GetTime(), nil, nil
		run.guid, run.shots, run.told = nil, {}, nil
		SoftStrengths(0)
		Log(("map: switch %d (%s) on"):format(at, MAP_SWITCH[at][1]))
		SwitchBox("wait... (no target)", 0.7, 0.7, 0.7)
	end
	local function SwitchTick()
		if not run then return end
		ns.stillSince = GetTime()
		if not run.at then return end
		local into = GetTime() - run.began
		local trial = MAP_SWITCH[run.at]
		if run.phase == "settle" and into >= 2 then
			if UnitExists("target") then
				SwitchBox("CLEAR YOUR TARGET first (Esc)", 1, 0.3, 0.3)
			else
				run.phase = "first"
				SwitchBox("TAB to the FIRST enemy (off to one side), then hands off", 0.3, 1, 0.3)
			end
		elseif run.phase == "on" then
			SoftStrengths(math.min(1, into / SOFT_RAMP))
			if into >= SOFT_HOLD - 0.5 and not run.shots.full then
				run.shots.full = true
				SwitchShot("on the first at full", "hands off...")
			elseif into >= SOFT_HOLD and not run.told then
				run.told = true
				SwitchBox("TAB ONCE to the NEXT enemy (the one beside it), then hands off", 1, 0.82, 0)
			end
		elseif run.phase == "switched" then
			if trial.ease then
				SoftStrengths(trial.from + (1 - trial.from) * math.min(1, into / trial.ease))
			end
			for _, at in ipairs(SWITCH_SHOTS) do
				if into >= at and not run.shots[at] then
					run.shots[at] = true
					SwitchShot(("%.1f s after the switch"):format(at), "hands off...")
					break
				end
			end
			local slot = math.floor(into * 10)
			if slot % 2 == 0 and not run.shots["s" .. slot] then
				run.shots["s" .. slot] = true
				Log(("map: switch %d +%.1f s: strengths %s/%s"):format(run.at, into, Text(GetCVar(E .. "StrengthYaw")),
					Text(GetCVar(E .. "StrengthPitch"))))
			end
			if into >= 3.5 then
				run.phase, run.began = "clear", GetTime()
				SwitchBox(trial.eye and ("Trial %d: snap, dip or smooth? Remember it, then PRESS ESC"):format(run.at)
					or "PRESS ESC to clear it", 1, 0.82, 0)
			end
		elseif run.phase == "clear" and not UnitExists("target") then
			SoftStrengths(0)
			SwitchBegin(run.at + 1)
		end
	end
	local function SwitchStart(from)
		if InCombatLockdown() then return ns.Print("shoulder map: out of a fight, please") end
		ns.shoulderTestHold = true -- (ShoulderCam.lua keeps its hands off the strengths meanwhile)
		Change({ [E .. "Enable"] = "1", [E .. "StrengthYaw"] = GetCVar(E .. "StrengthYaw"),
			[E .. "StrengthPitch"] = GetCVar(E .. "StrengthPitch") })
		local yours = ns.db.shoulderCamYours or {}
		run = { ticker = C_Timer.NewTicker(0.05, SwitchTick), events = CreateFrame("Frame"),
			fullYaw = tonumber(yours[E .. "StrengthYaw"] or GetCVar(E .. "StrengthYaw")) or 0.5,
			fullPitch = tonumber(yours[E .. "StrengthPitch"] or GetCVar(E .. "StrengthPitch")) or 0.4 }
		if run.fullYaw <= 0 then run.fullYaw = 0.5 end
		if run.fullPitch <= 0 then run.fullPitch = 0.4 end
		pcall(run.events.RegisterEvent, run.events, "PLAYER_TARGET_CHANGED")
		local this = run
		run.events:SetScript("OnEvent", function()
			if run ~= this or not run.at then return end
			local has = UnitExists("target") and ns.Flag(UnitCanAttack("player", "target"))
			if not has then return end
			local guid, name = Plain(UnitGUID, "target"), Plain(UnitName, "target")
			if run.phase == "first" then
				run.phase, run.began, run.guid = "on", GetTime(), guid or name
				Log(("map: switch %d first %s, facing %s"):format(run.at, Text(name), Facing()))
				SwitchBox("hands off...", 1, 0.82, 0)
			elseif run.phase == "on" and run.told and (guid or name) ~= run.guid then
				local trial = MAP_SWITCH[run.at]
				-- (At once, in the same frame as the switch.)
				if trial.ease then SoftStrengths(trial.from) end
				Log(("map: switch %d switched to %s, facing %s; strengths now %s/%s"):format(run.at, Text(name), Facing(),
					Text(GetCVar(E .. "StrengthYaw")), Text(GetCVar(E .. "StrengthPitch"))))
				run.phase, run.began = "switched", GetTime()
			end
		end)
		Log(("map: switch run, %d trials | %s | offset %s, zoom %.2f, full strengths %s/%s"):format(#MAP_SWITCH, Who(),
			Text(GetCVar(SHOULDER)), Zoom(), Text(run.fullYaw), Text(run.fullPitch)))
		ns.Print(("shoulder map: switch run, trials %d-%d; do what the box says. Type it again to stop."):format(from,
			#MAP_SWITCH))
		C_Timer.After(1, function() if run == this and not run.at then SwitchBegin(from) end end)
	end
	function ns.ShoulderMap(which)
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder map: stopped")
		end
		local kind, from = (which or ""):match("^(%S+)%s*(%d*)$")
		if kind == "talk" then return TalkStart(MAP_TALK, "talk") end
		if kind == "ramp" then return TalkStart(MAP_RAMP, "ramp") end
		if kind == "back" then return TalkStart(MAP_BACK, "back") end
		if kind == "friend" then
			TalkStart(MAP_FRIEND, "friend")
			if run then run.friend = true end
			return
		end
		if kind == "walk" then return WalkStart() end
		if kind == "enemy" then return EnemyStart() end
		if kind == "soft" then return SoftStart(math.max(1, math.min(3, tonumber(from) or 1))) end
		if kind == "switch" then return SwitchStart(math.max(1, math.min(#MAP_SWITCH, tonumber(from) or 1))) end
		if kind ~= "still" then
			return ns.Print("shoulder map: still [first trial], talk, ramp, back, friend, walk, enemy, soft, switch")
		end
		from = math.max(1, math.min(#MAP_STILL, tonumber(from) or 1))
		ns.shoulderTestHold = true
		Change(PLAIN)
		run = { ticker = C_Timer.NewTicker(0.05, Tick), view = _G.SaveView and pcall(_G.SaveView, VIEW_SLOT) or false }
		Log(("map: still run, trials %d-%d of %.1f s | %s | screen %.0f x %.0f, view saved %s, zoom %.2f"):format(from,
			#MAP_STILL, TRIAL_LENGTH, Who(), WorldFrame:GetWidth(), WorldFrame:GetHeight(), Text(run.view), Zoom()))
		ns.Print(("shoulder map: record your screen; about %d minutes; type it again to stop"):format(
			math.ceil((#MAP_STILL - from + 1) * TRIAL_LENGTH / 60)))
		local this = run
		C_Timer.After(1, function() if run == this and not run.at then Begin(from) end end)
	end
	if ns.RegisterCamera then ns.RegisterCamera("maptest", function() return run ~= nil end) end
	-- (A reload or logout mid-run: what it changed goes back at the next login.)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function()
		local count = AllBack()
		if count > 0 then Log(("map: %d settings from a cut-short run put back"):format(count)) end
	end)
end

-- zoomcurve: one run for "zooming feels like a staircase: you slide right
-- fast, then stop" (2026-11-12) and "cat form needs the bear's treatment".
-- GetCameraZoom gives where the zoom is going, not where the camera is (the
-- still map run: the full 4 yards read 0.05 s after the zoom was asked; the
-- recording took ~0.5 s), so the offset for the new distance goes in at once
-- and the game eases over to it (~0.3 s) ahead of the camera. This measures
-- both curves off a recording, with our own writes held: zooms in and out by
-- 2 and 5 yards, and a 1-yard offset step at a still zoom, all on their own;
-- then you shift into cat form and out, twice, when the box says. Every
-- frame's zoom read is logged for 1.5 s after each zoom; each step's moment
-- and every form and model change too. Typed again while running: stops.
do
	local STEPS = {
		{ 2, "zoom in 2", "CameraZoomIn", 2 }, { 4.5, "zoom out 2", "CameraZoomOut", 2 },
		{ 7, "zoom in 5", "CameraZoomIn", 5 }, { 10, "zoom out 5", "CameraZoomOut", 5 },
		{ 13, "offset +1 yard", offset = 1 }, { 15.5, "offset back", offset = 0 },
	}
	local CAT_AT, CAT_FORM, CAT_TIMES = 18, 1, 2
	local run
	local function Box(line, r, g, b) ns.PadTestBox("Zoom curve", line, r, g, b) end
	local function End(why)
		if not run then return end
		run.frame:UnregisterAllEvents()
		run.frame:SetScript("OnUpdate", nil)
		pcall(SetCVar, SHOULDER, run.offset)
		run = nil
		ns.shoulderTestHold = nil
		if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
		Log(("zoomcurve: %s"):format(why))
	end
	local function Tick()
		if not run then return end
		ns.stillSince = GetTime()
		local into = GetTime() - run.began
		local step = STEPS[run.step]
		if step and into >= step[1] then
			run.step = run.step + 1
			if step.offset then
				pcall(SetCVar, SHOULDER, ("%.2f"):format(tonumber(run.offset) + step.offset))
			else
				ns.CallCameraFunction(step[3], step[4])
			end
			run.reads, run.readFrom = {}, GetTime()
			Log(("zoomcurve: %s now (zoom %.2f, offset %s)"):format(step[2], Zoom(), Text(GetCVar(SHOULDER))))
		end
		if run.reads then
			local since = GetTime() - run.readFrom
			if since <= 1.5 then
				run.reads[#run.reads + 1] = ("%.3f:%.2f"):format(since, Zoom())
			else
				Log("zoomcurve:   zoom read each frame: " .. table.concat(run.reads, " "))
				run.reads = nil
			end
		end
		if run.phase == "auto" and into >= CAT_AT then
			run.phase, run.shifts = "in", 0
			Box("SHIFT INTO CAT FORM now (stand still, hands off the camera)", 0.3, 1, 0.3)
		end
	end
	function ns.ShoulderZoomCurve()
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder zoomcurve: stopped")
		end
		local offset = tonumber(GetCVar(SHOULDER)) or 0
		if offset == 0 then return ns.Print("shoulder zoomcurve: turn the Shoulder Cam on first, out of your forms") end
		if GetShapeshiftFormID and GetShapeshiftFormID() then
			return ns.Print("shoulder zoomcurve: start out of your forms")
		end
		ns.shoulderTestHold = true
		run = { frame = CreateFrame("Frame"), began = GetTime(), step = 1, phase = "auto", offset = GetCVar(SHOULDER) }
		run.frame:SetScript("OnUpdate", Tick)
		run.frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		run.frame:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
		run.frame:SetScript("OnEvent", function(_, event)
			if not run then return end
			local form = GetShapeshiftFormID and GetShapeshiftFormID()
			Log(("zoomcurve: %s, form %s, offset %s, zoom %.2f"):format(event, Text(form), Text(GetCVar(SHOULDER)), Zoom()))
			if event ~= "UPDATE_SHAPESHIFT_FORM" then return end
			if form == CAT_FORM and run.phase == "in" then
				run.phase = "out"
				Box("count to 2, then SHIFT BACK OUT", 1, 0.82, 0)
			elseif not form and run.phase == "out" then
				run.shifts = run.shifts + 1
				if run.shifts >= CAT_TIMES then
					End("done")
					Box("done: stop the recording, then /reload", 0.3, 1, 0.3)
					C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
				else
					run.phase = "wait"
					Box("wait...", 0.7, 0.7, 0.7)
					C_Timer.After(2.5, function()
						if run and run.phase == "wait" then
							run.phase = "in"
							Box("SHIFT INTO CAT FORM now (stand still, hands off the camera)", 0.3, 1, 0.3)
						end
					end)
				end
			end
		end)
		Log(("zoomcurve: starts | %s | offset %s, zoom %.2f, cameraZoomSpeed %s, screen %.0f x %.0f"):format(Who(),
			Text(run.offset), Zoom(), Text(GetCVar("cameraZoomSpeed")), WorldFrame:GetWidth(), WorldFrame:GetHeight()))
		Box("hands off: zooms and a sideways step on their own...", 0.7, 0.7, 0.7)
		ns.Print("shoulder zoomcurve: record your screen; about 30 s; type it again to stop")
	end
	if ns.RegisterCamera then ns.RegisterCamera("zoomcurve", function() return run ~= nil end) end
end

-- A ruler over the screen while a run that's read off the recording goes:
-- a line every tenth of the width (brighter at the middle and the quarters),
-- labeled in shares of the half-width (-1 to 1, as the logs give x), so a
-- spot can be read off any frame, however busy. Not under UIParent: CineMode
-- hiding the interface can't take it.
function ns.ShoulderTestGrid(on)
	local grid = ns.shoulderTestGrid
	if not on then
		if grid then grid:Hide() end
		return
	end
	if not grid then
		grid = CreateFrame("Frame")
		grid:SetFrameStrata("FULLSCREEN_DIALOG")
		grid:SetAllPoints(WorldFrame)
		for i = 0, 10 do
			local line = grid:CreateTexture(nil, "OVERLAY")
			local strong = i == 5 and 0.7 or (i == 0 or i == 10) and 0 or (i % 5 == 0 and 0.5) or 0.3
			line:SetColorTexture(1, 1, 1, strong)
			line:SetWidth(i == 5 and 2 or 1)
			line:SetPoint("TOP", grid, "TOPLEFT", grid:GetWidth() * i / 10, 0)
			line:SetPoint("BOTTOM", grid, "BOTTOMLEFT", grid:GetWidth() * i / 10, 0)
			local label = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
			label:SetPoint("BOTTOM", line, "BOTTOM", 0, 6)
			label:SetText(("%+.1f"):format((i - 5) / 5))
			label:SetTextColor(1, 1, 1, 0.8)
		end
		ns.shoulderTestGrid = grid
	end
	grid:Show()
end

-- mounts: one run for "how much does a mount scale the offset". Recording the
-- screen, you stand still; the offset steps 0, +1, 0, -1, 0 on its own on
-- foot, then the box says mount up and the same steps run on the mount, then
-- dismount (and again on another mount, if you like). Every step, mount and
-- model change is logged; the shift's read off the recording after (the same
-- view, so mounted against on foot is the mount's scale). Typed again: stops.
do
	local STEPS = { 0, 1, 0, -1, 0 } -- (small: 2 yards on a big mount hit the hillside, first run)
	local STEP_TIME = 2      -- seconds each offset's held (it eases over in about 0.3)
	local MOUNT_SETTLE = 3   -- seconds after mounting before the steps (the mount-up animation)
	local WAIT_MOST = 40     -- seconds the box waits for a mount before ending the run
	local run
	local function MountNow()
		if not (C_MountJournal and C_MountJournal.GetMountIDs) then return "?" end
		for _, id in ipairs(C_MountJournal.GetMountIDs()) do
			local name, spell, _, active = C_MountJournal.GetMountInfoByID(id)
			if ns.Flag(active) then
				local display = C_MountJournal.GetMountInfoExtraByID and C_MountJournal.GetMountInfoExtraByID(id)
				return ("%s (mount %s, spell %s, display %s)"):format(Text(name), Text(id), Text(spell), Text(display))
			end
		end
		return "none found"
	end
	local function Mounted() return IsMounted and ns.Flag(IsMounted()) or false end
	local function Box(line, r, g, b)
		ns.PadTestBox(("Mounts  %s"):format(run.label), line, r, g, b)
	end
	local function End(why)
		if not run then return end
		run.frame:SetScript("OnUpdate", nil)
		run.frame:UnregisterAllEvents()
		SetCVar(SHOULDER, run.held.offset)
		SetCVar(CENTERED, run.held.centered)
		run = nil
		ns.ShoulderTestGrid(false)
		ns.shoulderTestHold = nil
		if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
		Log(("mounts: %s"):format(why))
	end
	local function Finish()
		End("done")
		ns.PadTestBox("Mounts run done", "stop the recording, then /reload", 0.3, 1, 0.3)
		C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
	end
	local function Steps(label)
		run.phase, run.step, run.clock, run.label = "steps", 1, 0, label
		SetCVar(SHOULDER, tostring(STEPS[1]))
		Log(("mounts: %s steps start | %s | %s | offset %s, zoom %.2f"):format(label, Who(),
			Mounted() and MountNow() or "on foot", Text(GetCVar(SHOULDER)), Zoom()))
		Box(("hands off: the camera steps sideways on its own (1/%d)"):format(#STEPS), 0.7, 0.7, 0.7)
	end
	local function Tick(_, elapsed)
		run.clock = run.clock + elapsed
		local mounted = Mounted()
		if mounted ~= run.mounted then
			run.mounted = mounted
			Log(("mounts: %s | %s | offset %s, zoom %.2f"):format(mounted and "mounted" or "dismounted",
				mounted and MountNow() or "on foot", Text(GetCVar(SHOULDER)), Zoom()))
			if mounted and (run.phase == "mount" or run.phase == "again") then
				run.rides = run.rides + 1
				run.phase, run.clock = "settle", 0
				Box("stay still, hands off...", 1, 0.82, 0)
			elseif not mounted and run.phase == "dismount" then
				run.phase, run.clock = "again", 0
				Box("MOUNT UP on a DIFFERENT-SIZE mount now, or wait to finish", 0.3, 1, 0.3)
			end
		end
		if run.phase == "steps" and run.clock >= STEP_TIME then
			Log(("mounts: %s step %d held: offset %s, zoom %.2f"):format(run.label, run.step, Text(GetCVar(SHOULDER)), Zoom()))
			run.step, run.clock = run.step + 1, 0
			if STEPS[run.step] then
				SetCVar(SHOULDER, tostring(STEPS[run.step]))
				Box(("hands off: the camera steps sideways on its own (%d/%d)"):format(run.step, #STEPS), 0.7, 0.7, 0.7)
			elseif run.mounted then
				run.phase = "dismount"
				Box("DISMOUNT now", 0.3, 1, 0.3)
			else
				run.phase, run.clock = "mount", 0
				Box("MOUNT UP now (stay on the ground, don't turn)", 0.3, 1, 0.3)
			end
		elseif run.phase == "settle" and run.clock >= MOUNT_SETTLE then
			Steps(("mount %d"):format(run.rides))
		elseif (run.phase == "mount" or run.phase == "again") and run.clock >= WAIT_MOST then
			Finish()
		end
	end
	function ns.ShoulderMounts()
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder mounts: stopped")
		end
		if InCombatLockdown() then return ns.Print("shoulder mounts: not in a fight") end
		if Mounted() then return ns.Print("shoulder mounts: start on foot") end
		run = { frame = CreateFrame("Frame"), rides = 0, mounted = false,
			held = { offset = GetCVar(SHOULDER), centered = GetCVar(CENTERED) } }
		ns.shoulderTestHold = true -- (ShoulderCam.lua keeps its hands off meanwhile)
		SetCVar(CENTERED, "0")
		run.frame:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
		run.frame:SetScript("OnEvent", function(_, event)
			if run then Log(("mounts: %s, mounted %s, offset %s"):format(event, Text(Mounted()), Text(GetCVar(SHOULDER)))) end
		end)
		run.frame:SetScript("OnUpdate", Tick)
		Log(("mounts: starts | screen %.0f x %.0f, cameraFov %s, %s %s"):format(WorldFrame:GetWidth(), WorldFrame:GetHeight(),
			Text(GetCVar("cameraFov")), REDUCE, Text(GetCVar(REDUCE))))
		Steps("on foot")
		ns.ShoulderTestGrid(true)
		ns.Print("shoulder mounts: record your screen; type it again to stop")
	end
end

-- aimclick: one run for "how far does Turn to your target turn the camera,
-- by where the target was when you clicked it" (so the frames that follow
-- you can guess the turn from the click). For each spot (AIM_SPOTS) you turn
-- till the dummy sits there, click it, keep hands off while the camera
-- turns, then clear it and keep hands off while it glides back; the cursor
-- at the click, your facing (if the game gives it here) and the turn's share
-- are logged, and the turn's read off the recording after. Typed again: stops.
do
	local AIM_SPOTS = { "FAR LEFT", "LEFT", "MIDDLE", "RIGHT", "FAR RIGHT" }
	local AIM_TURNED = 1   -- seconds after the turn's full before "clear it"
	local AIM_BACK = 1     -- ...and after the glide back's done before the next spot
	local AIM_LOG = 0.1    -- seconds between log lines while it turns
	local run
	local function Box(line, r, g, b)
		ns.PadTestBox(("Aim %d/%d  dummy at the %s"):format(run.at, #AIM_SPOTS, AIM_SPOTS[run.at]), line, r, g, b)
	end
	local function Facing()
		local ok, facing = pcall(GetPlayerFacing)
		if not ok then return "error" end
		local okText, text = pcall(function() return ("%.3f"):format(facing) end)
		return okText and text or Text(facing)
	end
	local function Enemy() return UnitExists("target") and ns.Flag(UnitCanAttack("player", "target")) or false end
	local function Share()
		local debug = ns.GetShoulderCamDebug and ns.GetShoulderCamDebug()
		return debug and debug.aimShare or -1
	end
	local function End(why)
		if not run then return end
		run.frame:SetScript("OnUpdate", nil)
		run.frame:UnregisterAllEvents()
		run = nil
		ns.ShoulderTestGrid(false)
		Log(("aimclick: %s"):format(why))
	end
	local function Place()
		run.phase = "place"
		if Enemy() then
			Box("CLEAR YOUR TARGET first (Esc)", 1, 0.82, 0)
		else
			Box(("TURN till the dummy is at the %s of the screen, then CLICK IT"):format(AIM_SPOTS[run.at]), 0.3, 1, 0.3)
		end
	end
	local function Tick(_, elapsed)
		run.clock, run.logClock = run.clock + elapsed, run.logClock + elapsed
		local share = Share()
		if (run.phase == "turning" or run.phase == "back") and run.logClock >= AIM_LOG then
			run.logClock = 0
			Log(("aimclick: %d %s %.2f s: share %.2f, facing %s, turn %s"):format(run.at, run.phase, run.clock, share,
				Facing(), Text(GetCVar("test_cameraTargetFocusEnemyStrengthYaw"))))
		end
		if run.phase == "turning" then
			if share >= 1 then run.fullFor = run.fullFor + elapsed end
			if run.fullFor >= AIM_TURNED then
				run.phase = "clear"
				Box("CLEAR THE TARGET now (Esc), then hands off", 1, 0.82, 0)
			end
		elseif run.phase == "back" then
			if share <= 0 then run.backFor = run.backFor + elapsed end
			if run.backFor >= AIM_BACK then
				Log(("aimclick: %d back | facing %s"):format(run.at, Facing()))
				run.at = run.at + 1
				if not AIM_SPOTS[run.at] then
					End("done")
					ns.PadTestBox("Aim run done", "stop the recording, then /reload", 0.3, 1, 0.3)
					C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
					return
				end
				Place()
			end
		end
	end
	local function OnTarget()
		local enemy = Enemy()
		if run.phase == "place" and enemy then
			local x, y = GetCursorPosition()
			local w, h = UIParent:GetWidth() * UIParent:GetEffectiveScale(), UIParent:GetHeight() * UIParent:GetEffectiveScale()
			local _, instance = IsInInstance()
			Log(("aimclick: %d targeted at the %s | cursor x %.4f, y %.4f (-1 to 1 from the middle), mouse over it %s | " ..
				"facing %s, instance %s, in combat %s | offset %s, zoom %.2f, share %.2f"):format(run.at, AIM_SPOTS[run.at],
				(x / w - 0.5) * 2, (y / h - 0.5) * 2, Text(UnitExists("mouseover") and ns.Flag(UnitIsUnit("mouseover", "target"))),
				Facing(), Text(instance), Text(InCombatLockdown()), Text(GetCVar(SHOULDER)), Zoom(), Share()))
			run.phase, run.clock, run.logClock, run.fullFor = "turning", 0, 0, 0
			Box("hands off (the camera turns)...", 0.7, 0.7, 0.7)
		elseif run.phase == "clear" and not enemy then
			Log(("aimclick: %d cleared | facing %s, share %.2f"):format(run.at, Facing(), Share()))
			run.phase, run.clock, run.logClock, run.backFor = "back", 0, 0, 0
			Box("hands off (the camera glides back)...", 0.7, 0.7, 0.7)
		elseif run.phase == "place" then
			Place()
		end
	end
	function ns.ShoulderAimClick()
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder aimclick: stopped")
		end
		if not (ns.Setting("shoulderCam") and ns.db.shoulderCamTargetTurn) then
			return ns.Print("shoulder aimclick: turn on the Shoulder Cam and Turn to your target first")
		end
		run = { frame = CreateFrame("Frame"), at = 1, clock = 0, logClock = 0 }
		run.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
		run.frame:SetScript("OnEvent", function() if run then OnTarget() end end)
		run.frame:SetScript("OnUpdate", Tick)
		Log(("aimclick: starts | %s | screen %.0f x %.0f, cameraFov %s, turn takes %s s, offset %s, zoom %.2f, facing %s"):format(
			Who(), WorldFrame:GetWidth(), WorldFrame:GetHeight(), Text(GetCVar("cameraFov")), Text(ns.db.shoulderCamTalkTime),
			Text(GetCVar(SHOULDER)), Zoom(), Facing()))
		Place()
		ns.ShoulderTestGrid(true)
		ns.Print("shoulder aimclick: record your screen; type it again to stop")
	end
end

-- drag: one run for "can an addon see how far you turn the camera with the
-- mouse?". You drag the camera (DRAG_STEPS), told which button and how far by
-- the box; every frame a button's down, what the game reports of the mouse
-- (GetCursorDelta, if it's there; the cursor's place) and your facing are
-- added up, and each drag's totals logged as it ends. The right button turns
-- you too, so its facing change says how far a mouse unit turns; the left
-- button's turn is read off the recording. Typed again: stops.
do
	local DRAG_STEPS = {
		{ "RightButton", "a little (about a quarter of the screen)" },
		{ "RightButton", "more (about half the screen)" },
		{ "LeftButton", "a little (about a quarter of the screen)" },
		{ "LeftButton", "more (about half the screen)" },
		{ "LeftButton", "a little the OTHER way" },
	}
	local BUTTON = { RightButton = "RIGHT", LeftButton = "LEFT" }
	local MOUSE_CVARS = { "cameraYawMoveSpeed", "cameraPitchMoveSpeed", "cameraYawSmoothSpeed", "mouseSpeed",
		"cameraSmoothStyle", "mouseInvertYaw", "rawMouseEnable", "enableMouseSpeed" }
	local CursorDelta = _G["GetCursorDelta"] -- (retail; may not be there)
	local run
	local function Box(line, r, g, b)
		ns.PadTestBox(("Drag %d/%d"):format(run.at, #DRAG_STEPS), line, r, g, b)
	end
	local function Facing()
		local ok, facing = pcall(GetPlayerFacing)
		local okNumber, number = pcall(function() return facing + 0 end)
		return ok and okNumber and number or nil
	end
	local function Delta()
		if not CursorDelta then return nil end
		local ok, x, y = pcall(CursorDelta)
		local okNumber, both = pcall(function() return { x + 0, y + 0 } end)
		return ok and okNumber and both or nil
	end
	local function End(why)
		if not run then return end
		run.frame:SetScript("OnUpdate", nil)
		run = nil
		ns.ShoulderTestGrid(false)
		Log(("drag: %s"):format(why))
	end
	local function Ask()
		local step = DRAG_STEPS[run.at]
		run.drag = nil
		Box(("hold the %s mouse button on the world and DRAG %s to the right, then let go"):format(BUTTON[step[1]],
			step[2]), 0.3, 1, 0.3)
	end
	local function Tick()
		local step = DRAG_STEPS[run.at]
		local down = IsMouseButtonDown(step[1])
		local drag = run.drag
		if down and not drag then
			local x, y = GetCursorPosition()
			drag = { began = GetTime(), facing = Facing(), x = x, y = y, dx = 0, dy = 0, frames = 0, moved = 0,
				mouselook = IsMouselooking and IsMouselooking() and true or false }
			run.drag = drag
			Box("dragging...", 0.7, 0.7, 0.7)
		end
		if drag and down then
			drag.frames = drag.frames + 1
			local delta = Delta()
			if delta then
				drag.dx, drag.dy = drag.dx + delta[1], drag.dy + delta[2]
				if delta[1] ~= 0 or delta[2] ~= 0 then drag.moved = drag.moved + 1 end
			else
				drag.noDelta = true
			end
			if IsMouselooking and IsMouselooking() then drag.mouselook = true end
		elseif drag and not down then
			local x, y = GetCursorPosition()
			local facing = Facing()
			local turned = facing and drag.facing and ((facing - drag.facing + math.pi) % (2 * math.pi) - math.pi)
			Log(("drag: %d %s %s: %.2f s, %d frames | GetCursorDelta %s: x %.2f, y %.2f, moving on %d frames | " ..
				"cursor moved x %.1f, y %.1f | mouselook %s | facing %s -> %s (turned %s rad)"):format(run.at,
				step[1], step[2], GetTime() - drag.began, drag.frames, CursorDelta and (drag.noDelta and "unreadable" or "read") or "missing",
				drag.dx, drag.dy, drag.moved, x - drag.x, y - drag.y, Text(drag.mouselook),
				drag.facing and ("%.3f"):format(drag.facing) or "-", facing and ("%.3f"):format(facing) or "-",
				turned and ("%.3f"):format(turned) or "-"))
			if GetTime() - drag.began < 0.2 then
				Ask() -- (a click, not a drag: again)
				return
			end
			run.at = run.at + 1
			if not DRAG_STEPS[run.at] then
				End("done")
				ns.PadTestBox("Drag run done", "stop the recording, then /reload", 0.3, 1, 0.3)
				C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
				return
			end
			Ask()
		end
	end
	function ns.ShoulderDrag()
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder drag: stopped")
		end
		run = { frame = CreateFrame("Frame"), at = 1 }
		local cvars = {}
		for _, name in ipairs(MOUSE_CVARS) do cvars[#cvars + 1] = name .. " " .. Text(GetCVar(name)) end
		Log(("drag: starts | GetCursorDelta %s, IsMouselooking %s | %s | facing %s"):format(
			CursorDelta and "there" or "missing", IsMouselooking and "there" or "missing", table.concat(cvars, ", "),
			Facing() and ("%.3f"):format(Facing()) or "-"))
		run.frame:SetScript("OnUpdate", Tick)
		Ask()
		ns.ShoulderTestGrid(true)
		ns.Print("shoulder drag: record your screen; type it again to stop")
	end
end

-- follow: the one run for Frames follow the turn (ShoulderCam.lua, aim):
-- everything it guesses from and everything that throws it, in one go. Clicks
-- at the edges, then from the middle: turning with keys, strafing, walking,
-- dragging with each mouse button, Tab, the mouse over it after Tab or a
-- drag, a target behind you, and a fight. The box says what to do
-- (FOLLOW_TRIALS); every 0.1 s your facing, where you are, the mouse (buttons,
-- GetCursorDelta, mouselook), the turn, the guess and where the PRD and cast
-- bar really are go into their own saved list (db.shoulderFollowRun, so the
-- log's limit can't cut it), read after a /reload with the recording and its
-- ruler. Turn to your target and Frames follow the turn are on for the run,
-- yours back after. Typed again: stops.
do
	local MIDDLE = "TURN till a dummy is near the MIDDLE of the screen, then CLICK it"
	local HANDS_OFF, BACK = { "wait", 3, "hands off (the camera turns)" }, { "wait", 2.5, "hands off (it glides back)" }
	local CLEAR = { "clear", "CLEAR THE TARGET (Esc)" }
	local FOLLOW_TRIALS = {
		{ "click far left", { { "target", "TURN till a dummy is at the FAR LEFT of the screen, then CLICK it" },
			HANDS_OFF, CLEAR, BACK } },
		{ "click far right", { { "target", "TURN till a dummy is at the FAR RIGHT of the screen, then CLICK it" },
			HANDS_OFF, CLEAR, BACK } },
		{ "turning", { { "target", MIDDLE }, HANDS_OFF, { "do", 2, "TURN LEFT a little: TAP your turn key (an eighth of a turn)" },
			{ "wait", 2.5, "hands off" }, { "do", 2, "TURN RIGHT back: TAP the other turn key" }, { "wait", 2.5, "hands off" },
			CLEAR, BACK } },
		{ "strafing", { { "target", MIDDLE }, HANDS_OFF, { "do", 1.5, "STRAFE LEFT" }, { "wait", 2.5, "hands off" },
			{ "do", 1.5, "STRAFE RIGHT" }, { "wait", 2.5, "hands off" }, CLEAR, BACK } },
		{ "walking", { { "target", MIDDLE }, HANDS_OFF, { "do", 1.5, "WALK FORWARD" }, { "wait", 2.5, "hands off" },
			{ "do", 1.5, "WALK BACKWARD" }, { "wait", 2.5, "hands off" }, CLEAR, BACK } },
		{ "right button", { { "target", MIDDLE }, HANDS_OFF,
			{ "do", 2, "HOLD the RIGHT mouse button and drag a little to the RIGHT, then let go" },
			{ "wait", 2.5, "hands off" }, CLEAR, BACK } },
		{ "left button", { { "target", MIDDLE }, HANDS_OFF,
			{ "do", 2, "HOLD the LEFT mouse button and drag a little to the RIGHT, then let go" },
			{ "wait", 3, "hands off" }, CLEAR, BACK } },
		{ "tab", { { "target", "press TAB to target a dummy (no clicking)" }, HANDS_OFF, CLEAR, BACK } },
		{ "tab hover", { { "target", "press TAB to target a dummy (no clicking)" }, HANDS_OFF,
			{ "do", 2.5, "MOVE your mouse onto the dummy (no clicking) and leave it there" }, { "wait", 2.5, "hands off" },
			CLEAR, BACK } },
		{ "drag hover", { { "target", MIDDLE }, HANDS_OFF,
			{ "do", 2, "HOLD the LEFT mouse button and drag a little to the RIGHT, then let go" },
			{ "wait", 2.5, "hands off" }, { "do", 2.5, "MOVE your mouse onto the dummy (no clicking)" },
			{ "wait", 2.5, "hands off" }, CLEAR, BACK } },
		{ "behind", { { "target", MIDDLE }, HANDS_OFF,
			{ "do", 3, "TURN with your turn key till the dummy is BEHIND you" }, { "wait", 3, "hands off" },
			{ "do", 3, "TURN back till you face it" }, { "wait", 2.5, "hands off" }, CLEAR, BACK } },
		-- (After a right-button turn: does the game's turn toward the target
		-- come back by itself, standing, strafing or turning with the keys?
		-- The follow's let go by then, so the PRD marks your no-turn spot.)
		{ "right after", { { "target", MIDDLE }, HANDS_OFF,
			{ "do", 2, "HOLD the RIGHT mouse button and turn a little to the LEFT, then let go" },
			{ "wait", 4, "hands off" }, { "do", 1.5, "STRAFE LEFT" }, { "wait", 3, "hands off" },
			{ "do", 1.5, "TURN LEFT a little: TAP your turn key" }, { "wait", 3, "hands off" }, CLEAR, BACK } },
		-- (On a gamepad: targeted with its buttons (no click to go by), the
		-- camera stick, then the move stick. Does the game's turn survive the
		-- camera stick, and does walking with the stick turn you?)
		{ "gamepad", { { "target", "TARGET a dummy near the MIDDLE with your GAMEPAD (no mouse)" }, HANDS_OFF,
			{ "do", 2, "TURN THE CAMERA a little LEFT with the RIGHT STICK, then let go" }, { "wait", 4, "hands off" },
			{ "do", 1.5, "WALK FORWARD a little with the LEFT STICK" }, { "wait", 3, "hands off" },
			{ "do", 2, "WALK in a small curve to the LEFT with the LEFT STICK" }, { "wait", 3, "hands off" },
			{ "clear", "CLEAR THE TARGET (Esc, or your gamepad's)" }, BACK } },
		-- (In a fight: the game's enemy focus may act otherwise than out of one,
		-- where every other trial ran. Casting keeps you in it throughout.)
		{ "fight", { { "target", "TURN till a dummy is a little to the RIGHT of the middle, then CLICK it" },
			HANDS_OFF, { "do", 6, "ATTACK IT: cast at it a few times (stand still)" }, { "wait", 3, "hands off" },
			{ "do", 1.5, "STRAFE LEFT (keep casting if you can)" }, { "wait", 3, "hands off" },
			{ "do", 1.5, "STRAFE RIGHT, back" }, { "wait", 3, "hands off" },
			{ "do", 2, "TURN LEFT a little: TAP your turn key" }, { "wait", 3, "hands off" },
			{ "do", 2, "TURN RIGHT back: TAP the other turn key" }, { "wait", 3, "hands off" },
			CLEAR, BACK } },
	}
	-- (Each thing to do is read out first, then done: a "do" step on its own
	-- went by before it could be read, 2026-11-13.)
	for _, trial in ipairs(FOLLOW_TRIALS) do
		local steps = {}
		for _, step in ipairs(trial[2]) do
			if step[1] == "do" then steps[#steps + 1] = { "ready", 3, "NEXT: " .. step[3] } end
			steps[#steps + 1] = step
		end
		trial[2] = steps
	end
	local ALL_TRIALS = FOLLOW_TRIALS
	local SAMPLE_EVERY = 0.1
	local MOST_LINES = 6000
	-- (The gamepad's sticks, by their names (ns.PadStickName, Frames.lua):
	-- "Left 0.00,0.00 Right 0.50,0.00"; "-" with no pad on.)
	local function Pad()
		if not (C_GamePad and C_GamePad.GetDeviceMappedState and GetCVarBool("GamePadEnable")) then return "-" end
		local ok, state = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID
			and C_GamePad.GetActiveDeviceID() or nil)
		if not ok or type(state) ~= "table" or type(state.sticks) ~= "table" then return "?" end
		local parts = {}
		for index, stick in ipairs(state.sticks) do
			if type(stick) == "table" and type(stick.x) == "number" and type(stick.y) == "number" then
				parts[#parts + 1] = ("%s %.2f,%.2f"):format(ns.PadStickName and ns.PadStickName(index) or index,
					stick.x, stick.y)
			end
		end
		return table.concat(parts, " ")
	end
	local CursorDelta = _G["GetCursorDelta"] -- (retail; may not be there)
	local run
	local function Number(fn, ...)
		local ok, a, b = pcall(fn, ...)
		local okNumber, both = pcall(function() return { a + 0, b ~= nil and b + 0 or nil } end)
		return ok and okNumber and both or nil
	end
	-- (A frame's middle as a share of the half-width, -1 to 1; "-" not shown, "?" unreadable.)
	local function Across(name)
		local frame = _G[name]
		if not (frame and frame.GetCenter and frame:IsShown()) then return "-" end
		local center = Number(frame.GetCenter, frame)
		if not center then return "?" end
		local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		return ("%.3f"):format((center[1] * scale / UIParent:GetWidth() - 0.5) * 2)
	end
	local function Write(text)
		local lines = ns.db.shoulderFollowRun
		if #lines < MOST_LINES then lines[#lines + 1] = ("%.2f %s"):format(GetTime() - run.began, text) end
	end
	local function Box(line, r, g, b, left)
		ns.PadTestBox(("Follow %d/%d  %s"):format(run.at, #FOLLOW_TRIALS, FOLLOW_TRIALS[run.at][1]),
			left and ("%s  (%.0f)"):format(line, math.max(0, math.ceil(left))) or line, r, g, b)
	end
	local function Enemy() return UnitExists("target") and ns.Flag(UnitCanAttack("player", "target")) or false end
	local function End(why)
		if not run then return end
		run.frame:SetScript("OnUpdate", nil)
		run.frame:UnregisterAllEvents()
		ns.db.shoulderCamTargetTurn, ns.db.shoulderCamTargetFollow = run.kept[1], run.kept[2]
		Write("end: " .. why)
		Log(("follow: %s, %d lines in db.shoulderFollowRun"):format(why, #ns.db.shoulderFollowRun))
		run = nil
		ns.ShoulderTestGrid(false)
		if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	end
	local function Step()
		local trial = FOLLOW_TRIALS[run.at]
		if not trial then
			End("done")
			ns.PadTestBox("Follow run done", "stop the recording, then /reload", 0.3, 1, 0.3)
			C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
			return
		end
		local step = trial[2][run.step]
		if not step then
			run.at, run.step = run.at + 1, 1
			return Step()
		end
		run.clock = 0
		Write(("step: %s %d: %s %s"):format(trial[1], run.step, step[1], step[3] or step[2]))
		if step[1] == "target" then
			if Enemy() then return Box("CLEAR YOUR TARGET first (Esc)", 1, 0.82, 0) end
			Box(step[2], 0.3, 1, 0.3)
		elseif step[1] == "clear" then
			Box(step[2], 1, 0.82, 0)
		elseif step[1] == "do" then
			Box("NOW: " .. step[3], 0.3, 1, 0.3, step[2])
		elseif step[1] == "ready" then
			Box(step[3], 1, 0.82, 0, step[2])
		else
			Box(step[3], 0.7, 0.7, 0.7, step[2])
		end
	end
	local function Next()
		run.step = run.step + 1
		Step()
	end
	local function Tick(_, elapsed)
		run.clock, run.sampleClock = run.clock + elapsed, run.sampleClock + elapsed
		local delta = CursorDelta and Number(CursorDelta)
		if delta then run.dx, run.dy = run.dx + delta[1], run.dy + (delta[2] or 0) end
		local trial = FOLLOW_TRIALS[run.at]
		local step = trial and trial[2][run.step]
		if step and (step[1] == "wait" or step[1] == "do" or step[1] == "ready") then
			if run.clock >= step[2] then return Next() end
			if math.floor(run.clock) ~= math.floor(run.clock - elapsed) then
				local doing, ready = step[1] == "do", step[1] == "ready"
				Box(doing and "NOW: " .. step[3] or step[3], (doing or ready) and (ready and 1 or 0.3) or 0.7, doing and 1 or (ready and 0.82 or 0.7),
					doing and 0.3 or (ready and 0 or 0.7), step[2] - run.clock)
			end
		end
		if run.sampleClock < SAMPLE_EVERY then return end
		run.sampleClock = 0
		local facing = Number(GetPlayerFacing)
		local spot = Number(UnitPosition, "player")
		local cursor = Number(GetCursorPosition)
		local d = ns.GetShoulderCamDebug and ns.GetShoulderCamDebug() or {}
		Write(("s %s | facing %s at %s | L %d R %d look %d delta %s cursor %s | share %.2f click %s now %s slide %.1f | " ..
			"PRD %s cast %s | target %s combat %s | pad %s"):format(trial and trial[1] or "-",
			facing and ("%.3f"):format(facing[1]) or "-", spot and ("%.1f,%.1f"):format(spot[1], spot[2]) or "-",
			IsMouseButtonDown("LeftButton") and 1 or 0, IsMouseButtonDown("RightButton") and 1 or 0,
			IsMouselooking and IsMouselooking() and 1 or 0,
			CursorDelta and (delta and ("%.1f,%.1f"):format(run.dx, run.dy) or "unreadable") or "missing",
			cursor and ("%.0f,%.0f"):format(cursor[1], cursor[2] or 0) or "-", d.aimShare or 0,
			d.aimClickX and ("%.3f"):format(d.aimClickX) or "-", d.aimNowX and ("%.3f"):format(d.aimNowX) or "-",
			d.followShift or 0, Across("PersonalResourceDisplayFrame"), Across("PlayerCastingBarFrame"),
			Enemy() and "enemy" or (UnitExists("target") and "other" or "none"), Text(InCombatLockdown()), Pad()))
	end
	local function OnTarget()
		local trial = FOLLOW_TRIALS[run.at]
		local step = trial and trial[2][run.step]
		local enemy = Enemy()
		Write(("target changed: %s"):format(enemy and "an enemy" or (UnitExists("target") and "not an enemy" or "none")))
		if not step then return end
		if step[1] == "target" and enemy then
			Next()
		elseif step[1] == "target" then
			Step()
		elseif step[1] == "clear" and not enemy then
			Next()
		end
	end
	-- (With a trial's name, or the start of it, only that one: "follow turning".)
	function ns.ShoulderFollow(only)
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder follow: stopped")
		end
		if not (ns.Setting("shoulderCam") and ns.db.shoulderCamFrames) then
			return ns.Print("shoulder follow: turn on the Shoulder Cam and Frames follow you first")
		end
		FOLLOW_TRIALS = ALL_TRIALS
		if only then
			local kept = {}
			for _, trial in ipairs(ALL_TRIALS) do
				if trial[1]:find(only, 1, true) == 1 then kept[#kept + 1] = trial end
			end
			if #kept == 0 then return ns.Print("shoulder follow: no trial called " .. only) end
			FOLLOW_TRIALS = kept
		end
		run = { frame = CreateFrame("Frame"), at = 1, step = 1, clock = 0, sampleClock = 0, began = GetTime(),
			dx = 0, dy = 0, kept = { ns.db.shoulderCamTargetTurn, ns.db.shoulderCamTargetFollow } }
		ns.db.shoulderCamTargetTurn, ns.db.shoulderCamTargetFollow = true, true
		if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
		ns.db.shoulderFollowRun = {}
		local cvars = {}
		for _, name in ipairs({ "cameraYawMoveSpeed", "cameraSmoothStyle", "mouseSpeed", "cameraFov",
			"test_cameraOverShoulder", "test_cameraTargetFocusEnemyStrengthYaw" }) do
			cvars[#cvars + 1] = name .. " " .. Text(GetCVar(name))
		end
		Write(("start | %s | screen %.0f x %.0f, UI %.0f wide | zoom %.2f | GetCursorDelta %s | %s"):format(Who(),
			WorldFrame:GetWidth(), WorldFrame:GetHeight(), UIParent:GetWidth(), Zoom(), CursorDelta and "there" or "missing",
			table.concat(cvars, ", ")))
		Log("follow: starts (lines go into db.shoulderFollowRun)")
		run.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
		run.frame:SetScript("OnEvent", function() if run then OnTarget() end end)
		run.frame:SetScript("OnUpdate", Tick)
		Step()
		ns.ShoulderTestGrid(true)
		ns.Print("shoulder follow: record your screen; about 3 minutes; type it again to stop")
	end
end

-- Lock run (/cine debug shoulder lock): whether the game lets an addon move
-- the player, target and focus frames in a fight (for Frames follow you's
-- ticks). Out of a fight, in one, and after: each frame's first point nudged
-- 20 units right and put back, read back to see if it went, with any
-- ADDON_ACTION_BLOCKED/FORBIDDEN the game sends for it. Lines in
-- db.shoulderLockRun; the verdict in the box.
do
	local LOCK_FRAMES = { "PlayerFrame", "TargetFrame", "FocusFrame" }
	local ALSO = { "PersonalResourceDisplayFrame", "PlayerCastingBarFrame" } -- (read only: protected by a portrait on them?)
	local run
	local function Write(text)
		local lines = ns.db.shoulderLockRun
		if #lines < 400 then lines[#lines + 1] = ("%.2f %s"):format(GetTime() - run.began, text) end
	end
	local function Box(line, r, g, b) ns.PadTestBox("Lock run", line, r, g, b) end
	local function Protected(frame)
		local ok, protected, explicit = pcall(frame.IsProtected, frame)
		if not ok then return "unreadable" end
		return ("%s%s"):format(Text(ns.Flag(protected)), ns.Flag(explicit) and " (explicit)" or "")
	end
	local function FirstX(frame)
		local ok, point, to, toPoint, x, y = pcall(frame.GetPoint, frame, 1)
		if not ok or type(x) ~= "number" then return nil end
		return point, to, toPoint, x, y
	end
	local function Try(when)
		for _, name in ipairs(LOCK_FRAMES) do
			local frame = _G[name]
			if not (type(frame) == "table" and frame.SetPoint) then
				Write(("%s %s: not on this client"):format(when, name))
			else
				local point, to, toPoint, x, y = FirstX(frame)
				if not point then
					Write(("%s %s: points unreadable, protected %s"):format(when, name, Protected(frame)))
					run.result[when .. name] = "unreadable"
				else
					local set = pcall(frame.SetPoint, frame, point, to or UIParent, toPoint, x + 20, y)
					local _, _, _, after = FirstX(frame)
					local moved = after and math.abs(after - x - 20) < 0.5
					if moved then pcall(frame.SetPoint, frame, point, to or UIParent, toPoint, x, y) end
					local _, _, _, back = FirstX(frame)
					run.result[when .. name] = moved and "moved" or "held"
					Write(("%s %s: protected %s, combat %s, SetPoint call %s, %s (x %.1f -> %s), back %s"):format(when, name,
						Protected(frame), Text(InCombatLockdown()), set and "ran" or "errored", moved and "MOVED" or "did NOT move",
						x, after and ("%.1f"):format(after) or "?", back and ("%.1f"):format(back) or "?"))
				end
			end
		end
		for _, name in ipairs(ALSO) do
			local frame = _G[name]
			if type(frame) == "table" and frame.IsProtected then
				Write(("%s %s (read only): protected %s"):format(when, name, Protected(frame)))
			end
		end
	end
	local function Verdict()
		local parts = {}
		for _, name in ipairs(LOCK_FRAMES) do
			local fight, out = run.result["in a fight" .. name], run.result["out of a fight" .. name]
			parts[#parts + 1] = ("%s: %s"):format(name:gsub("Frame$", ""),
				fight == "held" and "LOCKED in fights" or fight == "moved" and "moves in fights" or "?")
				.. (out == "held" and " (and out of them!)" or "")
		end
		return table.concat(parts, "  |  ")
	end
	local function End(why)
		run.frame:SetScript("OnUpdate", nil)
		run.frame:UnregisterAllEvents()
		Write("end: " .. why)
		Log(("lock: %s, %d lines in db.shoulderLockRun"):format(why, #ns.db.shoulderLockRun))
		run = nil
	end
	local function Tick(_, elapsed)
		run.clock = run.clock + elapsed
		local fighting = InCombatLockdown()
		if run.phase == "out" then
			if fighting then return Box("LEAVE THE FIGHT first, then wait", 1, 0.82, 0) end
			if run.clock < 2 then return end
			Try("out of a fight")
			run.phase, run.clock = "fight", 0
			Box("ATTACK THE TRAINING DUMMY now (target it, keep fighting)", 0.3, 1, 0.3)
		elseif run.phase == "fight" then
			if not fighting then
				run.clock = 0
				if run.waited and GetTime() - run.waited > 120 then
					End("no fight in 2 minutes")
					return Box("No fight in 2 minutes: type the command again to retry", 1, 0.3, 0.3)
				end
				run.waited = run.waited or GetTime()
				return
			end
			if run.clock < 1.5 then return end
			Try("in a fight")
			run.phase, run.clock = "leave", 0
			Box("STOP ATTACKING: walk away and wait for the fight to end", 1, 0.82, 0)
		elseif run.phase == "leave" then
			if fighting then run.clock = 0 return end
			if run.clock < 1.5 then return end
			Try("after the fight")
			local verdict = Verdict()
			Write("verdict: " .. verdict)
			End("done")
			ns.PadTestBox("Lock run done: check log (/reload)", verdict, 0.3, 1, 0.3)
			C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
		end
	end
	function ns.ShoulderLock()
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder lock: stopped")
		end
		ns.db.shoulderLockRun = {}
		run = { frame = CreateFrame("Frame"), phase = "out", clock = 0, began = GetTime(), result = {} }
		Write(("start | %s | retail %s"):format(Who(), Text(ns.isRetail)))
		run.frame:RegisterEvent("ADDON_ACTION_BLOCKED")
		run.frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
		run.frame:SetScript("OnEvent", function(_, event, addon, what)
			if run then Write(("event %s: %s %s"):format(event, Text(addon), Text(what))) end
		end)
		run.frame:SetScript("OnUpdate", Tick)
		Box("hands off: trying them out of a fight...", 0.7, 0.7, 0.7)
		ns.Print("shoulder lock: follow the box; type it again to stop")
	end
end

-- angles: how far the game's turn toward your target goes, by how far round
-- from your facing the target is (the curve the follow's guess needs; at 90
-- degrees it "goes kind of wild", 2026-11-13). You click a dummy ahead, then
-- turn left a little at a time; at each of ANGLE_STEPS the box says HOLD and
-- you stand still while the turn settles. Frames follow the turn is off for
-- the run, so the PRD sits where you'd be with no turn at all: on the
-- recording, how far you are from it is the game's turn. Every 0.1 s the
-- angle, your facing and the PRD go into db.shoulderAngleRun. Typed again: stops.
do
	local ANGLE_STEPS = { 15, 30, 45, 60, 75, 90, 110, 135, 160 }
	local NEAR = 4      -- degrees either side of a step that count as there
	local HOLD = 3      -- seconds held still at each step
	local run
	local function Write(text)
		local lines = ns.db.shoulderAngleRun
		if #lines < 6000 then lines[#lines + 1] = ("%.2f %s"):format(GetTime() - run.began, text) end
	end
	local function Angle()
		local angle = ns.ShoulderAimAngle and ns.ShoulderAimAngle()
		return angle and math.deg(angle)
	end
	local function Across(name)
		local frame = _G[name]
		if not (frame and frame.GetCenter and frame:IsShown()) then return "-" end
		local ok, x = pcall(frame.GetCenter, frame)
		local okNumber, share = pcall(function()
			local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
			return (x * scale / UIParent:GetWidth() - 0.5) * 2
		end)
		return ok and okNumber and ("%.3f"):format(share) or "?"
	end
	local function Box(head, line, r, g, b)
		ns.PadTestBox(head, line, r, g, b)
	end
	local function End(why)
		if not run then return end
		run.frame:SetScript("OnUpdate", nil)
		run.frame:UnregisterAllEvents()
		ns.db.shoulderCamTargetTurn, ns.db.shoulderCamTargetFollow = run.kept[1], run.kept[2]
		Write("end: " .. why)
		Log(("angles: %s, %d lines in db.shoulderAngleRun"):format(why, #ns.db.shoulderAngleRun))
		run = nil
		ns.ShoulderTestGrid(false)
		if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	end
	local function Tick(_, elapsed)
		run.clock, run.sampleClock = run.clock + elapsed, run.sampleClock + elapsed
		local angle = Angle()
		local want = ANGLE_STEPS[run.at]
		if run.phase == "turn" and angle then
			if math.abs(angle - want) <= NEAR then
				run.phase, run.clock = "hold", 0
				Write(("hold %d: at %.1f degrees"):format(want, angle))
			elseif math.floor(run.clock * 4) ~= math.floor((run.clock - elapsed) * 4) then
				Box(("Angles %d/%d: %d degrees"):format(run.at, #ANGLE_STEPS, want),
					("TURN LEFT slowly (tap your turn key): now %.0f, stop at %d"):format(angle, want), 1, 0.82, 0)
			end
		elseif run.phase == "hold" then
			if not angle or math.abs(angle - want) > NEAR + 2 then
				run.phase = "turn"
				Write(("hold %d: moved off (%.1f)"):format(want, angle or 0))
			elseif run.clock >= HOLD then
				Write(("held %d: at %.1f degrees"):format(want, angle))
				run.at, run.phase, run.clock = run.at + 1, "turn", 0
				if not ANGLE_STEPS[run.at] then
					run.phase = "back"
					Box("Angles: last one", "TURN BACK till you face the dummy, then CLEAR THE TARGET (Esc)", 0.3, 1, 0.3)
				end
			elseif math.floor(run.clock * 4) ~= math.floor((run.clock - elapsed) * 4) then
				Box(("Angles %d/%d: %d degrees"):format(run.at, #ANGLE_STEPS, want),
					("HOLD STILL  (%.0f)"):format(math.ceil(HOLD - run.clock)), 0.3, 1, 0.3)
			end
		end
		if run.sampleClock < 0.1 or run.phase == "click" then return end
		run.sampleClock = 0
		local d = ns.GetShoulderCamDebug and ns.GetShoulderCamDebug() or {}
		Write(("s %s %s | angle %s | PRD %s | share %.2f"):format(run.phase, tostring(want or "-"),
			angle and ("%.1f"):format(angle) or "-", Across("PersonalResourceDisplayFrame"), d.aimShare or 0))
	end
	local function OnTarget()
		local enemy = UnitExists("target") and ns.Flag(UnitCanAttack("player", "target"))
		Write("target changed: " .. (enemy and "an enemy" or "none"))
		if run.phase == "click" and enemy then
			if not Angle() then
				Box("Angles", "CLICK the dummy (not Tab): Esc and click it again", 1, 0.3, 0.3)
				return
			end
			run.phase, run.clock = "turn", 0
		elseif run.phase == "back" and not enemy then
			End("done")
			ns.PadTestBox("Angles run done", "stop the recording, then /reload", 0.3, 1, 0.3)
			C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
		end
	end
	function ns.ShoulderAngles()
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder angles: stopped")
		end
		if not (ns.Setting("shoulderCam") and ns.db.shoulderCamFrames) then
			return ns.Print("shoulder angles: turn on the Shoulder Cam and Frames follow you first")
		end
		run = { frame = CreateFrame("Frame"), at = 1, phase = "click", clock = 0, sampleClock = 0, began = GetTime(),
			kept = { ns.db.shoulderCamTargetTurn, ns.db.shoulderCamTargetFollow } }
		ns.db.shoulderCamTargetTurn, ns.db.shoulderCamTargetFollow = true, false
		if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
		ns.db.shoulderAngleRun = {}
		Write(("start | %s | zoom %.2f, offset %s, cameraFov %s"):format(Who(), Zoom(), Text(GetCVar(SHOULDER)),
			Text(GetCVar("cameraFov"))))
		Log("angles: starts (lines go into db.shoulderAngleRun)")
		run.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
		run.frame:SetScript("OnEvent", function() if run then OnTarget() end end)
		run.frame:SetScript("OnUpdate", Tick)
		Box("Angles", "TURN till a dummy is in the MIDDLE of the screen, then CLICK it (stay put after)", 0.3, 1, 0.3)
		ns.ShoulderTestGrid(true)
		ns.Print("shoulder angles: record your screen; about a minute; type it again to stop")
	end
end

-- padscan: every console setting about the gamepad, centering or following,
-- with its value, its default and its help line, and whether the gamepad UI
-- is up: for "Keep Character Centered won't stay off with the gamepad on"
-- (Forever, 2026-11-13: written 0, it reads 1 at once, nothing else writing it).
function ns.ShoulderPadScan()
	local list = C_Console and C_Console.GetAllCommands and select(2, pcall(C_Console.GetAllCommands))
		or (_G.ConsoleGetAllCommands and select(2, pcall(_G.ConsoleGetAllCommands)))
	local found = 0
	Log(("padscan: gamepad UI %s, GamePadEnable %s, CameraKeepCharacterCentered %s"):format(
		Text(ns.IsGamePadOn and ns.IsGamePadOn()), Text(GetCVar("GamePadEnable")), Text(GetCVar("CameraKeepCharacterCentered"))))
	for _, info in ipairs(type(list) == "table" and list or {}) do
		local name = type(info) == "table" and info.command
		local lower = type(name) == "string" and name:lower() or ""
		if lower:find("gamepad", 1, true) or lower:find("center", 1, true) or lower:find("follow", 1, true)
			or lower:find("pad", 1, true) and lower:find("cam", 1, true) then
			local ok, value = pcall(GetCVar, name)
			if ok and value ~= nil then
				found = found + 1
				local default = C_CVar and C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name)
				Log(("padscan: %s = %s (default %s) %s"):format(name, Text(value), Text(default), Text(info.help)))
			end
		end
	end
	ns.Print(("shoulder padscan: %d settings logged (/reload to save it)"):format(found))
end

-- prdcheck: is the personal resource display under you? You stand still with
-- nothing targeted; the zoom steps through PRD_ZOOMS on its own and holds
-- each, with the Shoulder Cam working as it does in play. Every 0.1 s the
-- offset, zoom, size factor (and where it's from), your spot, the slide and
-- where the PRD and cast bar really are go into db.shoulderPrdRun; you're
-- read off the recording with its ruler. Typed again: stops.
do
	local PRD_ZOOMS = { 6, 9, 12, 15, 4, 8 }
	local PRD_HOLD = 3 -- seconds at each (the zoom's glide and the frames' ease settled)
	local run
	local function Write(text)
		local lines = ns.db.shoulderPrdRun
		if #lines < 4000 then lines[#lines + 1] = ("%.2f %s"):format(GetTime() - run.began, text) end
	end
	local function Across(name)
		local frame = _G[name]
		if not (frame and frame.GetCenter and frame:IsShown()) then return "-" end
		local ok, x = pcall(frame.GetCenter, frame)
		local okNumber, share = pcall(function()
			local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
			return (x * scale / UIParent:GetWidth() - 0.5) * 2
		end)
		return ok and okNumber and ("%.3f"):format(share) or "?"
	end
	local function End(why)
		if not run then return end
		run.frame:SetScript("OnUpdate", nil)
		Write("end: " .. why)
		Log(("prdcheck: %s, %d lines in db.shoulderPrdRun"):format(why, #ns.db.shoulderPrdRun))
		run = nil
		ns.ShoulderTestGrid(false)
	end
	local function ZoomTo(yards)
		local delta = yards - Zoom()
		if math.abs(delta) > 0.1 then
			ns.CallCameraFunction(delta > 0 and "CameraZoomOut" or "CameraZoomIn", math.abs(delta))
		end
	end
	local function Tick(_, elapsed)
		run.clock, run.sampleClock = run.clock + elapsed, run.sampleClock + elapsed
		if run.clock >= PRD_HOLD then
			run.at, run.clock = run.at + 1, 0
			if not PRD_ZOOMS[run.at] then
				End("done")
				ns.PadTestBox("PRD check done", "stop the recording, then /reload", 0.3, 1, 0.3)
				C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
				return
			end
			ZoomTo(PRD_ZOOMS[run.at])
			Write(("zoom to %d"):format(PRD_ZOOMS[run.at]))
			ns.PadTestBox(("PRD check %d/%d: zoom %d"):format(run.at, #PRD_ZOOMS, PRD_ZOOMS[run.at]),
				"hands off, stand still", 0.7, 0.7, 0.7)
		end
		if run.sampleClock < 0.1 then return end
		run.sampleClock = 0
		local d = ns.GetShoulderCamDebug and ns.GetShoulderCamDebug() or {}
		Write(("s %d | offset %s zoom %.2f | scale %.2f (%s) spot %s | slide %.1f target %.1f | PRD %s cast %s"):format(
			run.at, Text(GetCVar(SHOULDER)), Zoom(), d.scale or 0, Text(d.scaleFrom), Text(ns.db.shoulderCamSpot),
			d.followShift or 0, d.followTarget or 0, Across("PersonalResourceDisplayFrame"),
			Across("PlayerCastingBarFrame")))
	end
	function ns.ShoulderPrdCheck()
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder prdcheck: stopped")
		end
		if not (ns.Setting("shoulderCam") and ns.db.shoulderCamFrames) then
			return ns.Print("shoulder prdcheck: turn on the Shoulder Cam and Frames follow you first")
		end
		run = { frame = CreateFrame("Frame"), at = 1, clock = 0, sampleClock = 0, began = GetTime() }
		ns.db.shoulderPrdRun = {}
		Write(("start | %s | screen %.0f x %.0f, UI %.0f wide, view width %.3f | layout %s | side %s"):format(Who(),
			WorldFrame:GetWidth(), WorldFrame:GetHeight(), UIParent:GetWidth(),
			ns.ShoulderViewWidth and ns.ShoulderViewWidth() or 0, Text(ns.db.editModeLayout), Text(ns.db.shoulderCamSide)))
		Log("prdcheck: starts (lines go into db.shoulderPrdRun)")
		ZoomTo(PRD_ZOOMS[1])
		run.frame:SetScript("OnUpdate", Tick)
		ns.PadTestBox(("PRD check 1/%d: zoom %d"):format(#PRD_ZOOMS, PRD_ZOOMS[1]), "hands off, stand still",
			0.7, 0.7, 0.7)
		ns.ShoulderTestGrid(true)
		ns.Print("shoulder prdcheck: record your screen; about 20 seconds; type it again to stop")
	end
end

-- sizes (swingsize too): what Edit Mode lets the cast bar, personal
-- resource display and swing timers set (width? height? scale?), each
-- setting's name, range and value now, and the frames' real sizes, their
-- bars' too. Into the log; read after a /reload.
function ns.ShoulderSwingSize()
	local systems = Enum.EditModeSystem or {}
	local manager = _G["EditModeSettingDisplayInfoManager"]
	local infos = manager and manager.systemSettingDisplayInfo or {}
	local function Dump(label, system, names)
		ns.Log("shoulder", ("sizes: %s system %s"):format(label, Text(system)))
		for _, info in ipairs(system and infos[system] or {}) do
			ns.Log("shoulder", ("sizes:   setting %s %s | type %s min %s max %s step %s"):format(Text(info.setting),
				Text(info.name), Text(info.type), Text(info.minValue), Text(info.maxValue), Text(info.stepSize)))
		end
		for _, name in ipairs(names) do
			local frame = _G[name]
			if frame then
				local values = {}
				for _, info in ipairs(system and infos[system] or {}) do
					local ok, value = pcall(frame.GetSettingValue, frame, info.setting)
					values[#values + 1] = ("%s=%s"):format(Text(info.setting), ok and Text(value) or "?")
				end
				ns.Log("shoulder", ("sizes:   %s %.1f x %.1f scale %.2f eff %.2f shown %s | %s"):format(name,
					frame:GetWidth(), frame:GetHeight(), frame:GetScale(), frame:GetEffectiveScale(),
					Text(frame:IsShown()), table.concat(values, " ")))
				local function Kids(parent, depth)
					for _, child in ipairs({ parent:GetChildren() }) do
						ns.Log("shoulder", ("sizes:   %s%s %s %.1f x %.1f eff %.2f"):format(("  "):rep(depth),
							Text(child:GetName() or child:GetDebugName()), child:GetObjectType(), child:GetWidth(),
							child:GetHeight(), child:GetEffectiveScale()))
						if depth < 2 then Kids(child, depth + 1) end
					end
				end
				Kids(frame, 1)
			end
		end
	end
	Dump("cast bar", systems.CastBar, { "PlayerCastingBarFrame" })
	Dump("personal resource display", systems.PersonalResourceDisplay, { "PersonalResourceDisplayFrame" })
	Dump("swing timers", systems.SwingTimer, { "SwingTimerMainHandFrame" })
	ns.Log("shoulder", ("sizes: UIParent eff %.2f, layout %s"):format(UIParent:GetEffectiveScale(),
		Text(ns.db.editModeLayout)))
	ns.Print("shoulder sizes: logged; /reload and say check log")
end

-- selftarget: why the camera goes back to the middle with yourself targeted
-- (user, 2026-11-15, Forever: the offset kept, you centered). One run: no
-- target, then yourself targeted with the Shoulder Cam as it plays, then our
-- writes held (shoulderTestHold) and one setting after another tried, each
-- kept on top of the last, HOLD seconds and a screenshot each. The step
-- where you go back aside is the cause. Every camera setting is listed with
-- nothing targeted and with yourself, and any change between them logged;
-- the offset sampled every 0.2 s. Into db.shoulderSelfRun. Typed again: stops.
do
	local HOLD = 3
	local STEPS = {
		{ "rewrite: the offset written again", function(v) return { [SHOULDER] = ("%.2f"):format(v + 0.01) } end },
		{ "enemy focus off", function() return { test_cameraTargetFocusEnemyEnable = "0" } end },
		{ "interact focus off", function() return { test_cameraTargetFocusInteractEnable = "0" } end },
		{ "centering off again", function() return { [CENTERED] = "0", [REDUCE] = "0" } end },
		{ "dynamic pitch off", function() return { test_cameraDynamicPitch = "0" } end },
		{ "head movement off", function() return { test_cameraHeadMovementStrength = "0" } end },
		{ "offset doubled", function(v) return { [SHOULDER] = ("%.2f"):format(v * 2) } end },
	}
	local run
	local function Write(text)
		local lines = ns.db.shoulderSelfRun
		if #lines < 4000 then lines[#lines + 1] = ("%.2f %s"):format(GetTime() - run.began, text) end
	end
	local function Self() return UnitExists("target") and ns.Flag(UnitIsUnit("target", "player")) end
	-- (Every console setting with "camera" or "focus" in its name.)
	local function Snapshot()
		local all = {}
		local list = C_Console and C_Console.GetAllCommands and select(2, pcall(C_Console.GetAllCommands))
		for _, info in ipairs(type(list) == "table" and list or {}) do
			local name = type(info) == "table" and info.command
			local lower = type(name) == "string" and name:lower() or ""
			if lower:find("camera", 1, true) or lower:find("focus", 1, true) then
				local ok, value = pcall(GetCVar, name)
				if ok and value ~= nil then all[name] = Text(value) end
			end
		end
		for _, name in ipairs(CAMERA_CVARS) do all[name] = Text(GetCVar(name)) end
		return all
	end
	local function Shot(what)
		ns.PadTestBoxHide()
		C_Timer.After(0.1, function()
			local ok = pcall(function() Screenshot() end)
			Write(("screenshot %s at %s: %s"):format(what, date("%m%d%y_%H%M%S"), ok and "taken" or "failed"))
		end)
	end
	local function End(why)
		if not run then return end
		run.frame:SetScript("OnUpdate", nil)
		run.frame:UnregisterAllEvents()
		for name, value in pairs(run.kept or {}) do SetCVar(name, value) end
		ns.shoulderTestHold = nil
		Write("end: " .. why)
		Log(("selftarget: %s, %d lines in db.shoulderSelfRun"):format(why, #ns.db.shoulderSelfRun))
		run = nil
		if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	end
	local function Box(head, line, r, g, b) ns.PadTestBox(head, line, r or 1, g or 0.82, b or 0) end
	local function Try(i)
		local step = STEPS[i]
		local sets = step[2](tonumber(GetCVar(SHOULDER)) or 0)
		local said = {}
		for name, value in pairs(sets) do
			if run.kept[name] == nil then run.kept[name] = GetCVar(name) end
			SetCVar(name, value)
			said[#said + 1] = ("%s %s -> %s (reads %s)"):format(name, Text(run.kept[name]), value, Text(GetCVar(name)))
		end
		Write(("step %d %s: %s"):format(i, step[1], table.concat(said, ", ")))
		Box(("Self target %d/%d: %s"):format(i, #STEPS, step[1]), "hands off, keep yourself targeted", 0.7, 0.7, 0.7)
	end
	local function Tick(_, elapsed)
		run.clock, run.sampleClock = run.clock + elapsed, run.sampleClock + elapsed
		if run.sampleClock >= 0.2 then
			run.sampleClock = 0
			Write(("s %s | offset %s centered %s | zoom %.2f | self %s"):format(run.phase, Text(GetCVar(SHOULDER)),
				Text(GetCVar(CENTERED)), Zoom(), Text(Self())))
		end
		-- (Nothing targeted: read at once, half a second in, so targeting
		-- yourself straight after can't leave it waiting: the first run, 2026-11-15.)
		if run.phase == "none" then
			if UnitExists("target") then run.clock = 0 return end
			if run.clock < 0.5 then return end
			run.none = Snapshot()
			Shot("1 nothing targeted")
			run.phase, run.clock = "wantSelf", 0
			C_Timer.After(0.5, function() if run then Box("Self target", "TARGET YOURSELF (F1), then hands off") end end)
		elseif run.phase == "wantSelf" then
			if not Self() then run.clock = 0 return end
			if run.clock < HOLD then return end
			local now = Snapshot()
			local changed = 0
			for name, value in pairs(now) do
				if run.none[name] ~= value then
					changed = changed + 1
					Write(("changed with yourself targeted: %s %s -> %s"):format(name, Text(run.none[name]), value))
				end
			end
			Write(("%d camera settings changed with yourself targeted"):format(changed))
			Shot("2 yourself, as it plays")
			run.phase, run.clock, run.at = "steps", 0, 1
			ns.shoulderTestHold = true
			C_Timer.After(0.5, function() if run then Try(1) end end)
			run.clock = -0.5
		elseif run.phase == "steps" then
			if not Self() then
				Box("Self target", "TARGET YOURSELF again (F1)", 1, 0.3, 0.3)
				run.clock = 0
				return
			end
			if run.clock < HOLD then return end
			Shot(("%d %s"):format(run.at + 2, STEPS[run.at][1]))
			run.at, run.clock = run.at + 1, -0.5
			if not STEPS[run.at] then
				run.phase, run.clock = "clear", 0
				for name, value in pairs(run.kept) do SetCVar(name, value) end
				run.kept = {}
				ns.shoulderTestHold = nil
				if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
				C_Timer.After(0.5, function() if run then Box("Self target", "CLEAR YOUR TARGET (Esc)") end end)
				return
			end
			local at = run.at
			C_Timer.After(0.5, function() if run and run.at == at then Try(at) end end)
		elseif run.phase == "clear" then
			if UnitExists("target") then run.clock = 0 return end
			if run.clock < HOLD then return end
			Shot(("%d cleared again"):format(#STEPS + 3))
			End("done")
			C_Timer.After(0.5, function()
				ns.PadTestBox("Self target run done", "/reload, then say check log", 0.3, 1, 0.3)
				C_Timer.After(15, function() if not run then ns.PadTestBoxHide() end end)
			end)
		end
	end
	function ns.ShoulderSelfTarget()
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder selftarget: stopped")
		end
		if not ns.Setting("shoulderCam") then
			return ns.Print("shoulder selftarget: turn on the Shoulder Cam first")
		end
		ns.db.shoulderSelfRun = {}
		run = { frame = CreateFrame("Frame"), phase = "none", clock = 0, sampleClock = 0, began = GetTime(), kept = {} }
		Write(("start | %s | zoom %.2f | side %s | talk turn %s, target turn %s, frames %s | paused %s"):format(Who(),
			Zoom(), Text(ns.db.shoulderCamSide), Text(ns.db.shoulderCamTalkTurn), Text(ns.db.shoulderCamTargetTurn),
			Text(ns.db.shoulderCamFrames), Text(ns.GetShoulderCamDebug and ns.GetShoulderCamDebug().paused)))
		run.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
		run.frame:SetScript("OnEvent", function()
			if run then Write("target changed: " .. (Self() and "yourself" or UnitExists("target") and "other" or "none")) end
		end)
		run.frame:SetScript("OnUpdate", Tick)
		Box("Self target", "CLEAR YOUR TARGET (Esc), stand still, WAIT for the next box")
		ns.Print("shoulder selftarget: follow the box, about 40 seconds; type it again to stop")
	end
end

-- today: one run over the Shoulder Cam changes of 2026-11-15, each with its
-- own verdict and screenshots, into db.shoulderTodayRun:
--   swap:   the swap key pressed for you: the offset glides across over
--           Swap takes (not the game's 0.3 s snap), the frames' height kept up
--           all the way (at the middle the offset's 0); then back;
--   self:   yourself targeted, then cleared: the offset starts near 0 and
--           glides back out over Back from targeting yourself;
--   spot:   Spot on screen at 35% then 20% at zoom 8: the offset is what the
--           spot asks for (it stopped at 1.5 yards before, so past ~14% did nothing);
--   indoor: in and out of a building: out and back in over Off and on again takes;
--   quest:  talking to a quest giver: with Quest camera unticked, the camera
--           goes behind you over its 2 s and comes back as it ends.
-- A step waiting on you gives up after 60 s (CAN'T TELL) and the run goes on.
-- Your spot, side and zoom are put back. Typed again: stops.
do
	local WAIT = 60
	local run
	local function Write(text)
		local lines = ns.db.shoulderTodayRun
		if #lines < 8000 then lines[#lines + 1] = ("%.2f %s"):format(GetTime() - run.began, text) end
	end
	local function Verdict(name, ok, detail)
		Write(("VERDICT %s: %s%s"):format(name, ok == nil and "CAN'T TELL" or (ok and "PASS" or "FAIL"),
			detail and (" (" .. detail .. ")") or ""))
		run.verdicts[#run.verdicts + 1] = ok == nil and "?" or (ok and "ok" or "X")
	end
	local function Box(head, line, r, g, b)
		run.boxShown = { head, line, r or 1, g or 0.82, b or 0 }
		ns.PadTestBox(head, line, r or 1, g or 0.82, b or 0)
	end
	local function Shot(what)
		ns.PadTestBoxHide()
		C_Timer.After(0.05, function()
			if not run then return end
			local ok = pcall(function() Screenshot() end)
			Write(("screenshot %s at %s: %s"):format(what, date("%m%d%y_%H%M%S"), ok and "taken" or "failed"))
			C_Timer.After(0.3, function()
				if run and run.boxShown then ns.PadTestBox(unpack(run.boxShown)) end
			end)
		end)
	end
	local function Offset() return tonumber(GetCVar(SHOULDER)) or 0 end
	local function Self() return UnitExists("target") and ns.Flag(UnitIsUnit("target", "player")) end
	local function Debug() return ns.GetShoulderCamDebug and ns.GetShoulderCamDebug() or {} end
	local function ZoomTo(yards)
		local delta = yards - Zoom()
		if math.abs(delta) > 0.1 then
			ns.CallCameraFunction(delta > 0 and "CameraZoomOut" or "CameraZoomIn", math.abs(delta))
		end
	end
	-- A watch over the offset from a moment on: the last time it moved (by
	-- 0.02 or more, a write's step) and its smallest and largest size.
	local function Watch()
		local value = Offset()
		return { from = GetTime(), first = value, last = value, movedAt = nil, least = math.abs(value),
			most = math.abs(value), samples = 0, between = 0 }
	end
	local function Follow(w, low, high)
		local value = Offset()
		if math.abs(value - w.last) >= 0.02 then w.movedAt = GetTime() end
		w.last = value
		w.least, w.most = math.min(w.least, math.abs(value)), math.max(w.most, math.abs(value))
		w.samples = w.samples + 1
		if low and high and math.abs(value) > low and math.abs(value) < high then w.between = w.between + 1 end
	end
	local function Took(w) return w.movedAt and (w.movedAt - w.from) or 0 end
	local function Near(a, b, by) return math.abs(a - b) <= by end

	-- The steps, in turn. Each: start(s), tick(s, elapsed) returning true when done.
	local STEPS = {}
	STEPS[1] = { name = "swap",
		start = function(s)
			Box("Today 1/5: swap", "hands off, stand still, nothing targeted", 0.7, 0.7, 0.7)
			s.phase = "ready"
		end,
		tick = function(s)
			if s.phase == "ready" then
				local d = Debug()
				if UnitExists("target") or d.paused ~= "no" or math.abs(Offset()) < 0.3 then
					if s.clock > WAIT then
						Verdict("swap glides", nil, ("never ready: paused %s, offset %.2f"):format(Text(d.paused), Offset()))
						return true
					end
					if s.clock > 2 then Box("Today 1/5: swap", "CLEAR YOUR TARGET, outdoors, on foot, Shoulder Cam on") end
					return
				end
				s.want = tonumber(ns.db.shoulderCamSwapTime) or 0
				s.size, s.side = math.abs(Offset()), ns.db.shoulderCamSide
				Write(("swap: offset %.2f, side %s, Swap takes %.1f, lift %.2f"):format(Offset(), Text(s.side), s.want,
					d.followLift or 0))
				s.w, s.lowLift = Watch(), d.followLift or 0
				s.liftWas = s.lowLift
				ns.ShoulderSwapButton:Click()
				s.phase, s.at, s.shot = "going", 0, false
			elseif s.phase == "going" or s.phase == "back" then
				s.at = s.at + s.dt
				Follow(s.w, 0.05, s.size * 0.9)
				local lift = Debug().followLift or 0
				s.lowLift = math.min(s.lowLift, lift)
				if s.sample <= 0 then
					s.sample = 0.05
					Write(("swap %s: %.2f s offset %.2f lift %.2f"):format(s.phase, s.at, Offset(), lift))
				end
				if s.phase == "going" and not s.shot and s.at >= s.want / 2 then
					s.shot = true
					Shot("1 mid swap")
				end
				if s.at < s.want + 1.5 then return end
				if s.phase == "going" then
					-- (s.side: the side before: flipped, the offset's on the other one.)
					local took, flipped = Took(s.w), Offset() * (s.side == "left" and 1 or -1) > 0
					local okTime = s.want > 0 and Near(took, s.want, 0.45)
					Verdict("swap glides", flipped and okTime and s.w.between >= 5,
						("took %.2f s for %.1f, %d samples between, flipped %s, size %.2f -> %.2f"):format(took, s.want,
						s.w.between, Text(flipped), s.size, math.abs(Offset())))
					-- (No lift to keep with Frames follow you off: can't tell.)
					local kept
					if s.liftWas >= 0.95 then kept = s.lowLift >= 0.95 end
					Verdict("swap keeps the height", kept, ("lift %.2f before, lowest %.2f"):format(s.liftWas, s.lowLift))
					Shot("2 swapped")
					s.w = Watch()
					ns.ShoulderSwapButton:Click()
					s.phase, s.at = "back", 0
					return
				end
				Write(("swap back: took %.2f s, side %s"):format(Took(s.w), Text(ns.db.shoulderCamSide)))
				return true
			end
		end }
	STEPS[2] = { name = "self",
		start = function(s)
			s.want = tonumber(ns.db.shoulderCamSelfTime) or 1
			s.steady = math.abs(Offset())
			Box("Today 2/5: yourself", "TARGET YOURSELF (F1), then wait for the next box")
			s.phase = "target"
		end,
		tick = function(s)
			if s.phase == "target" then
				if not Self() then
					if s.clock > WAIT then Verdict("self glides back", nil, "never targeted yourself") return true end
					return
				end
				s.phase, s.at = "held", 0
				Write(("self: targeted, offset %.2f, paused %s"):format(Offset(), Text(Debug().paused)))
			elseif s.phase == "held" then
				s.at = s.at + s.dt
				if s.at < 2.5 then return end
				Write(("self: after 2.5 s offset %.2f, paused %s"):format(Offset(), Text(Debug().paused)))
				Box("Today 2/5: yourself", "CLEAR YOUR TARGET (Esc)")
				s.phase = "clear"
			elseif s.phase == "clear" then
				if UnitExists("target") then
					if s.clock > WAIT * 2 then Verdict("self glides back", nil, "target never cleared") return true end
					return
				end
				s.start, s.w, s.at, s.phase = math.abs(Offset()), Watch(), 0, "back"
				Box("Today 2/5: yourself", "hands off", 0.7, 0.7, 0.7)
			elseif s.phase == "back" then
				s.at = s.at + s.dt
				Follow(s.w)
				if s.sample <= 0 then
					s.sample = 0.05
					Write(("self back: %.2f s offset %.2f"):format(s.at, Offset()))
				end
				if not s.shot and s.at >= 0.3 then s.shot = true Shot("3 self, 0.3 s after clearing") end
				if s.at < s.want + 1.5 then return end
				local took = Took(s.w)
				Verdict("self glides back", s.start < s.steady * 0.3 and Near(took, s.want, 0.4),
					("started at %.2f of %.2f, took %.2f s for %.1f"):format(s.start, s.steady, took, s.want))
				Shot("4 self, back")
				return true
			end
		end }
	STEPS[3] = { name = "spot",
		start = function(s)
			s.keptSpot, s.keptZoom = ns.db.shoulderCamSpot, Zoom()
			Box("Today 3/5: spot", "hands off, nothing targeted (the zoom moves by itself)", 0.7, 0.7, 0.7)
			ZoomTo(8)
			s.phase, s.at, s.i = "spot", 0, 1
			s.spots = { 0.35, 0.20 }
			ns.db.shoulderCamSpot = s.spots[1]
		end,
		tick = function(s)
			s.at = s.at + s.dt
			if s.at < 2.5 then return end
			local spot = s.spots[s.i]
			local d = Debug()
			local view = ns.ShoulderViewWidth and ns.ShoulderViewWidth() or 1
			local want = spot * math.min(Zoom() * view, ns.SHOULDER_SPOT_HOLD or 7.5) / (d.scale or 1)
			local fits
			if d.paused == "no" then fits = Near(math.abs(Offset()), want, want * 0.06) end
			Verdict(("spot %d%%"):format(spot * 100), fits,
				("offset %.2f, wanted %.2f (zoom %.2f, view width %.3f, size %.2f, paused %s)"):format(math.abs(Offset()),
				want, Zoom(), view, d.scale or 0, Text(d.paused)))
			Shot(("%d spot %d%%"):format(4 + s.i, spot * 100))
			s.i, s.at = s.i + 1, 0
			if s.spots[s.i] then
				ns.db.shoulderCamSpot = s.spots[s.i]
				return
			end
			ns.db.shoulderCamSpot = s.keptSpot
			ZoomTo(s.keptZoom)
			return true
		end }
	-- (Indoors and the quest camera: a pause starting, then ending. kind:
	-- PauseReason's word; want: the seconds it should take.)
	local function PauseStep(index, name, kind, want, go, back)
		return { name = name,
			start = function(s)
				s.want = want()
				Box(("Today %d/5: %s"):format(index, name), go .. "  (or wait 60 s to skip)")
				s.phase = "wait"
			end,
			tick = function(s)
				local paused = Debug().paused
				-- (Our cameras play as their scripts: "script:quest" is the quest camera too.)
				if paused == "script:" .. kind then paused = kind end
				if s.phase == "wait" then
					if paused ~= kind then
						if s.clock > WAIT then Verdict(name .. " out", nil, "never paused for " .. kind) return true end
						return
					end
					s.w, s.at, s.phase = Watch(), 0, "out"
					s.size = math.abs(s.w.first)
					Write(("%s: paused, offset %.2f, wants %.1f s"):format(name, Offset(), s.want))
				elseif s.phase == "out" or s.phase == "in" then
					s.at = s.at + s.dt
					Follow(s.w)
					if s.sample <= 0 then
						s.sample = 0.05
						Write(("%s %s: %.2f s offset %.2f paused %s"):format(name, s.phase, s.at, Offset(), Text(paused)))
					end
					if not s.shot and s.at >= s.want / 2 then
						s.shot = true
						Shot(("%s %s, halfway"):format(name, s.phase))
					end
					if s.phase == "out" then
						if paused ~= kind and s.at < s.want then
							Write(name .. ": pause ended early")
						end
						if s.at < s.want + 1 then return end
						local took = Took(s.w)
						Verdict(name .. " out", s.size > 0.3 and Near(took, s.want, math.max(0.4, s.want * 0.25))
							and math.abs(Offset()) < 0.05,
							("took %.2f s for %.1f, from %.2f to %.2f"):format(took, s.want, s.size, math.abs(Offset())))
						Box(("Today %d/5: %s"):format(index, name), back)
						s.phase = "end"
					end
				end
				if s.phase == "end" then
					if paused == kind then
						if s.clock > WAIT * 3 then Verdict(name .. " back in", nil, "never ended") return true end
						return
					end
					Box(("Today %d/5: %s"):format(index, name), "hands off", 0.7, 0.7, 0.7)
					s.w, s.at, s.phase, s.shot = Watch(), 0, "in", false
				elseif s.phase == "in" and s.at >= s.want + 1 then
					local took = Took(s.w)
					Verdict(name .. " back in", math.abs(Offset()) > 0.3 and Near(took, s.want, math.max(0.4, s.want * 0.25)),
						("took %.2f s for %.1f, now %.2f"):format(took, s.want, math.abs(Offset())))
					return true
				end
			end }
	end
	STEPS[4] = PauseStep(4, "indoors", "indoors", function() return tonumber(ns.db.shoulderCamPauseTime) or 1.5 end,
		"WALK INTO A BUILDING (an inn), then stand still", "WALK BACK OUTSIDE, then stand still")
	STEPS[5] = PauseStep(5, "quest", "quest", function() return tonumber(ns.db.shoulderCamTimeQuest) or 2 end,
		"TALK TO A QUEST GIVER (open a quest)", "CLOSE THE QUEST WINDOW")

	local function End(why)
		if not run then return end
		run.frame:SetScript("OnUpdate", nil)
		ns.db.shoulderCamSide = run.kept.side
		ns.db.shoulderCamSpot = run.kept.spot
		Write(("end: %s | verdicts %s"):format(why, table.concat(run.verdicts, " ")))
		Log(("today: %s, %d lines in db.shoulderTodayRun"):format(why, #ns.db.shoulderTodayRun))
		run = nil
		if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	end
	local function Begin(i)
		local step = STEPS[i]
		run.step = { clock = 0, sample = 0, dt = 0 }
		run.at = i
		Write(("step %d %s"):format(i, step.name))
		step.start(run.step)
	end
	local function Tick(_, elapsed)
		local s = run.step
		s.clock, s.dt, s.sample = s.clock + elapsed, elapsed, s.sample - elapsed
		if STEPS[run.at].tick(s) then
			if STEPS[run.at + 1] and not run.only then
				Begin(run.at + 1)
			else
				local verdicts = table.concat(run.verdicts, " ")
				End("done")
				ns.PadTestBox("Today run done: /reload, then say check log", verdicts, 0.3, 1, 0.3)
				C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
			end
		end
	end
	-- (only: a step's name, "quest"..., to run just that one.)
	function ns.ShoulderToday(only)
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder today: stopped")
		end
		if not ns.Setting("shoulderCam") then
			return ns.Print("shoulder today: turn on the Shoulder Cam first")
		end
		ns.db.shoulderTodayRun = {}
		run = { frame = CreateFrame("Frame"), began = GetTime(), verdicts = {},
			kept = { side = ns.db.shoulderCamSide, spot = ns.db.shoulderCamSpot } }
		Write(("start | %s | zoom %.2f | side %s, spot %s | swap %s, self %s, pause %s, quest allowed %s time %s | " ..
			"frames %s, screen %.0f x %.0f"):format(Who(), Zoom(), Text(ns.db.shoulderCamSide), Text(ns.db.shoulderCamSpot),
			Text(ns.db.shoulderCamSwapTime), Text(ns.db.shoulderCamSelfTime), Text(ns.db.shoulderCamPauseTime),
			Text(ns.db.shoulderCamAllowQuest), Text(ns.db.shoulderCamTimeQuest), Text(ns.db.shoulderCamFrames),
			WorldFrame:GetWidth(), WorldFrame:GetHeight()))
		local first = 1
		for i, step in ipairs(STEPS) do
			if step.name == only then first, run.only = i, true end
		end
		run.frame:SetScript("OnUpdate", Tick)
		Begin(first)
		ns.Print("shoulder today: outdoors in a town, on foot; follow the box, a few minutes; type it again to stop")
	end
end

-- profiletest: one run over the Shoulder Cam welcome level (2026-11-15),
-- verdicts and screenshots into db.shoulderProfileRun:
--   cinema: the welcome window opened and its Cinema card clicked, what it
--           leaves noted (layout, camera settings) for the end;
--   demo:   See it first's Shoulder Cam test (as its button runs it): in over
--           your shoulder, a swap, back out; the setting never on, no question;
--   pick:   the Shoulder Cam card clicked: the Shoulder Cam and Frames follow
--           you on, no question, the personal resource display on and up in
--           fights and with an enemy, your portrait not; Forever: its layout;
--   fight:  you fight something: the personal resource display up, your
--           portrait down;
--   back:   Cinema again: the Shoulder Cam off, the camera settings and
--           layout as Cinema had them. Then the profile you started on.
-- A step waiting on you gives up after 2 minutes (CAN'T TELL). Typed again: stops.
do
	local WAIT = 120
	local run
	local function Write(text)
		local lines = ns.db.shoulderProfileRun
		if #lines < 6000 then lines[#lines + 1] = ("%.2f %s"):format(GetTime() - run.began, text) end
	end
	local function Verdict(name, ok, detail)
		Write(("VERDICT %s: %s%s"):format(name, ok == nil and "CAN'T TELL" or (ok and "PASS" or "FAIL"),
			detail and (" (" .. detail .. ")") or ""))
		run.verdicts[#run.verdicts + 1] = ok == nil and "?" or (ok and "ok" or "X")
	end
	local function Box(head, line, r, g, b)
		run.boxShown = { head, line, r or 1, g or 0.82, b or 0 }
		ns.PadTestBox(head, line, r or 1, g or 0.82, b or 0)
	end
	local function Shot(what)
		ns.PadTestBoxHide()
		C_Timer.After(0.05, function()
			if not run then return end
			local ok = pcall(function() Screenshot() end)
			Write(("screenshot %s at %s: %s"):format(what, date("%m%d%y_%H%M%S"), ok and "taken" or "failed"))
			C_Timer.After(0.3, function() if run and run.boxShown then ns.PadTestBox(unpack(run.boxShown)) end end)
		end)
	end
	local function Offset() return tonumber(GetCVar(SHOULDER)) or 0 end
	local function Alpha(name)
		local frame = _G[name]
		if not frame then return "none" end
		local okShown, shown = pcall(frame.IsVisible, frame)
		local okAlpha, alpha = pcall(frame.GetEffectiveAlpha, frame)
		if not (okShown and okAlpha) then return "?" end
		if shown ~= true then return "hidden" end
		if issecretvalue and issecretvalue(alpha) then return "secret" end
		-- (Nothing given back, the PRD in a fight on Forever: the first run, 2026-11-15.)
		return type(alpha) == "number" and ("%.2f"):format(alpha) or "?"
	end
	local function Seen(name)
		local value = Alpha(name)
		return tonumber(value) and tonumber(value) > 0.5
	end
	local function Popup()
		return StaticPopup_Visible and StaticPopup_Visible("CINEMATIC_SHOULDER_NOTICE") and true or false
	end
	local CAMERA_SETTINGS = { SHOULDER, CENTERED, REDUCE, "test_cameraTargetFocusInteractEnable",
		"test_cameraTargetFocusEnemyEnable" }
	local function Camera()
		local values = {}
		for _, name in ipairs(CAMERA_SETTINGS) do values[name] = Text(GetCVar(name)) end
		return values
	end
	local function CameraText(values)
		local parts = {}
		for _, name in ipairs(CAMERA_SETTINGS) do parts[#parts + 1] = name .. " " .. Text(values[name]) end
		return table.concat(parts, ", ")
	end
	local function State(label)
		local db = ns.db
		local d = ns.GetShoulderCamDebug and ns.GetShoulderCamDebug() or {}
		Write(("%s: profile %s, layout %s (own %s), shoulderCam %s, noticed %s, popup %s, paused %s | prdOn %s, " ..
			"combat prd %s player %s, enemy prd %s player %s, frames %s | %s"):format(label, Text(ns.ActiveProfile()),
			Text(ns.ActiveLayoutName and ns.ActiveLayoutName()), Text(ns.chardb and ns.chardb.layoutOwn),
			Text(db.shoulderCam), Text(db.shoulderCamNoticed), Text(Popup()), Text(d.paused), Text(db.prdOn),
			Text(db.combatShow and db.combatShow.prd), Text(db.combatShow and db.combatShow.player),
			Text(db.enemyShow and db.enemyShow.prd), Text(db.enemyShow and db.enemyShow.player),
			Text(db.shoulderCamFrames), CameraText(Camera())))
	end
	local function Card(profile)
		for i, level in ipairs(ns.WELCOME_LEVELS) do
			if level.profile == profile then return ns.WelcomeCards()[i] end
		end
	end
	local function Click(profile)
		local card = Card(profile)
		if not card then return false end
		card:Click()
		Write("clicked the " .. profile .. " card")
		return true
	end

	local STEPS = {}
	STEPS[1] = { name = "cinema",
		start = function(s)
			ns.ShowWelcome()
			s.clicked = Click("Cinema")
			Box("Profile 1/5: Cinema", "hands off: the welcome window tries Cinema", 0.7, 0.7, 0.7)
		end,
		tick = function(s)
			if not s.clicked then Verdict("cinema card", false, "no Cinema card") return true end
			if s.clock < 4 then return end
			State("cinema")
			run.cinema = { layout = ns.ActiveLayoutName and ns.ActiveLayoutName(), camera = Camera(),
				shoulderCam = ns.db.shoulderCam }
			Verdict("cinema picked", ns.ActiveProfile() == "Cinema", Text(ns.ActiveProfile()))
			Shot("1 cinema")
			return true
		end }
	STEPS[2] = { name = "demo",
		start = function(s)
			s.wasOn, s.most, s.signs, s.samples = ns.db.shoulderCam, 0, {}, 0
			ns.ShowMe("shoulder", nil, true)
			s.started = ns.ShowMeRunning and ns.ShowMeRunning("shoulder")
			Write(("demo: started %s, blocked %s"):format(Text(s.started), Text(ns.ShowMeBlocked("shoulder", true))))
			Box("Profile 2/5: the test", "hands off: See it first's Shoulder Cam test plays", 0.7, 0.7, 0.7)
		end,
		tick = function(s)
			if not s.started then Verdict("demo runs", nil, "didn't start") return true end
			local value = Offset()
			s.most = math.max(s.most, math.abs(value))
			if math.abs(value) > 0.3 then s.signs[value > 0 and "right" or "left"] = true end
			s.popup = s.popup or Popup()
			s.settingOn = s.settingOn or ns.db.shoulderCam ~= s.wasOn
			if s.sample <= 0 then
				s.sample = 0.1
				Write(("demo: %.1f s offset %s"):format(s.clock, Text(GetCVar(SHOULDER))))
			end
			if not s.shot and s.clock >= 1.5 then s.shot = true Shot("2 demo, over the shoulder") end
			if (ns.ShowMeRunning and ns.ShowMeRunning("shoulder")) and s.clock < 14 then
				s.endedAt = nil
				return
			end
			if s.clock < 2 then return end
			-- (Settled: with the Shoulder Cam on there, it glides back to your side.)
			s.endedAt = s.endedAt or s.clock
			if s.clock - s.endedAt < 2.5 then return end
			Verdict("demo over the shoulder and swapped", s.most > 0.3 and s.signs.left and s.signs.right and true or false,
				("largest %.2f, sides %s%s"):format(s.most, s.signs.left and "left " or "", s.signs.right and "right" or ""))
			local before = tonumber(run.cinema.camera[SHOULDER]) or 0
			Verdict("demo back as before, nothing saved", math.abs(Offset() - before) < 0.05 and not s.settingOn
				and not s.popup, ("offset now %s (before %.2f), setting changed %s, question shown %s"):format(
				Text(GetCVar(SHOULDER)), before, Text(s.settingOn), Text(s.popup)))
			local now, same = Camera(), true
			for _, name in ipairs(CAMERA_SETTINGS) do
				if now[name] ~= run.cinema.camera[name] then same = false end
			end
			Verdict("demo gives the camera back", same, CameraText(now))
			return true
		end }
	STEPS[3] = { name = "pick",
		start = function(s)
			s.clicked = Click("Shoulder Cam")
			Box("Profile 3/5: Shoulder Cam", "hands off: the welcome window tries Shoulder Cam (a reload offer? say no)",
				0.7, 0.7, 0.7)
		end,
		tick = function(s)
			if not s.clicked then Verdict("shoulder card", false, "no Shoulder Cam card") return true end
			s.popup = s.popup or Popup()
			if s.clock < 5 then return end
			State("shoulder")
			local db = ns.db
			Verdict("shoulder picked, no question", ns.ActiveProfile() == "Shoulder Cam" and db.shoulderCam == true
				and db.shoulderCamNoticed == true and not s.popup,
				("profile %s, shoulderCam %s, noticed %s, question %s"):format(Text(ns.ActiveProfile()),
				Text(db.shoulderCam), Text(db.shoulderCamNoticed), Text(s.popup)))
			Verdict("PRD in fights, portrait not", db.prdOn == true and db.combatShow.prd == true
				and db.combatShow.player == false and db.enemyShow.prd == true and db.enemyShow.player == false
				and db.shoulderCamFrames == true)
			local layout = ns.ActiveLayoutName and ns.ActiveLayoutName()
			if ns.isRetail then
				Verdict("retail keeps your layout", layout == run.cinema.layout or layout == (ns.chardb and ns.chardb.layoutOwn),
					("now %s, Cinema's %s"):format(Text(layout), Text(run.cinema.layout)))
			else
				Verdict("Forever: the Shoulder Cam layout", layout == "Shoulder Cam", Text(layout))
			end
			local d = ns.GetShoulderCamDebug and ns.GetShoulderCamDebug() or {}
			if d.paused == "no" then
				Verdict("over your shoulder now", math.abs(Offset()) > 0.3, Text(GetCVar(SHOULDER)))
			else
				Verdict("over your shoulder now", nil, "paused: " .. Text(d.paused))
			end
			Shot("3 shoulder cam picked")
			return true
		end }
	STEPS[4] = { name = "fight",
		start = function()
			Box("Profile 4/5: a fight", "CLOSE the welcome window (X), then ATTACK something and keep fighting")
		end,
		tick = function(s)
			if not InCombatLockdown() then
				if s.clock > WAIT then Verdict("fight", nil, "no fight in 2 minutes") return true end
				s.fightAt = nil
				return
			end
			s.fightAt = s.fightAt or s.clock
			if s.clock - s.fightAt < 3 then return end
			local prd = Alpha("PersonalResourceDisplayFrame")
			local player = Alpha("PlayerFrame")
			Write(("fight: PRD %s, our health bar %s, player frame %s, CineMode %s"):format(prd,
				Alpha("CinematicPersonalResource"), player, Text(ns.cinematic)))
			local prdUp = Seen("PersonalResourceDisplayFrame") or Seen("CinematicPersonalResource")
			Verdict("fight: PRD up, portrait down", prdUp and not Seen("PlayerFrame"),
				("PRD %s, player frame %s"):format(prd, player))
			Shot("4 in a fight")
			return true
		end }
	STEPS[5] = { name = "back",
		start = function()
			Box("Profile 5/5: back to Cinema", "STOP fighting and wait for the fight to end")
		end,
		tick = function(s)
			if not s.switched then
				if InCombatLockdown() then
					if s.clock > WAIT then Verdict("back to Cinema", nil, "the fight never ended") return true end
					s.calmAt = nil
					return
				end
				s.calmAt = s.calmAt or s.clock
				if s.clock - s.calmAt < 2 then return end
				ns.SetProfile("Cinema")
				s.switched, s.at = true, s.clock
				Box("Profile 5/5: back to Cinema", "hands off (a reload offer? say no)", 0.7, 0.7, 0.7)
				return
			end
			if s.clock - s.at < 5 then return end
			State("back")
			local now, same = Camera(), true
			for _, name in ipairs(CAMERA_SETTINGS) do
				if now[name] ~= run.cinema.camera[name] then same = false end
			end
			-- (Your Cinema may have the Shoulder Cam on too: as it had it.)
			Verdict("back: Shoulder Cam and camera as Cinema had them", ns.db.shoulderCam == run.cinema.shoulderCam and same,
				("shoulderCam %s | now %s | Cinema %s"):format(Text(ns.db.shoulderCam), CameraText(now),
				CameraText(run.cinema.camera)))
			local layout = ns.ActiveLayoutName and ns.ActiveLayoutName()
			Verdict("back: Cinema's layout", layout == run.cinema.layout,
				("now %s, Cinema's %s"):format(Text(layout), Text(run.cinema.layout)))
			Shot("5 back on cinema")
			return true
		end }

	local function End(why)
		if not run then return end
		run.frame:SetScript("OnUpdate", nil)
		Write(("end: %s | verdicts %s"):format(why, table.concat(run.verdicts, " ")))
		Log(("profiletest: %s, %d lines in db.shoulderProfileRun"):format(why, #ns.db.shoulderProfileRun))
		local startedOn = run.startedOn
		run = nil
		-- (The profile you were on, back.)
		if startedOn and ns.ActiveProfile() ~= startedOn and not InCombatLockdown() then ns.SetProfile(startedOn) end
	end
	local function Begin(i)
		run.step, run.at = { clock = 0, sample = 0 }, i
		Write(("step %d %s"):format(i, STEPS[i].name))
		STEPS[i].start(run.step)
	end
	local function Tick(_, elapsed)
		local s = run.step
		s.clock, s.sample = s.clock + elapsed, s.sample - elapsed
		if STEPS[run.at].tick(s) then
			if STEPS[run.at + 1] then
				Begin(run.at + 1)
			else
				local verdicts = table.concat(run.verdicts, " ")
				End("done")
				ns.PadTestBox("Profile run done: /reload, then say check log", verdicts, 0.3, 1, 0.3)
				C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
			end
		end
	end
	function ns.ShoulderProfileTest()
		if run then
			End("stopped")
			ns.PadTestBoxHide()
			return ns.Print("shoulder profiletest: stopped")
		end
		if InCombatLockdown() then return ns.Print("shoulder profiletest: not in a fight") end
		ns.db.shoulderProfileRun = {}
		run = { frame = CreateFrame("Frame"), began = GetTime(), verdicts = {}, startedOn = ns.ActiveProfile() }
		Write(("start | %s | client %s | profile %s, layout %s (own %s), noticed %s | %s"):format(Who(),
			ns.isRetail and "retail" or "forever", Text(ns.ActiveProfile()),
			Text(ns.ActiveLayoutName and ns.ActiveLayoutName()), Text(ns.chardb and ns.chardb.layoutOwn),
			Text(ns.db.shoulderCamNoticed), CameraText(Camera())))
		run.frame:SetScript("OnUpdate", Tick)
		Begin(1)
		ns.Print("shoulder profiletest: outdoors, on foot, near something to fight; follow the box; type it again to stop")
	end
end

local function Set(key, value)
	ns.db[key] = value
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	if ns.RefreshOptions then ns.RefreshOptions() end
	ns.Print(("shoulder: %s %s; offset now %s"):format(key, tostring(value), Text(GetCVar(SHOULDER))))
end

-- /cine debug shoulder <what>.
function ns.ShoulderTest(arg)
	local what, rest = arg:match("^(%S+)%s*(.-)%s*$")
	rest = rest ~= "" and rest or nil
	if what == "scan" then Scan()
	elseif what == "frames" then Frames()
	elseif what == "watch" then
		ns.db.shoulderTestWatch = not ns.db.shoulderTestWatch or nil
		SetWatch(ns.db.shoulderTestWatch and true or false)
		if watcher.on then Values("watch on") end
		ns.Print(("shoulder watch %s (stays over a reload; /reload saves the log)"):format(watcher.on and "on" or "off"))
	elseif what == "quiet" then
		ns.db.shoulderTestQuiet = not ns.db.shoulderTestQuiet or nil
		SetQuiet(ns.db.shoulderTestQuiet and true or false)
		ns.Print(("shoulder quiet %s (stays over a reload; off takes a /reload)"):format(ns.db.shoulderTestQuiet and "on" or "off"))
	elseif what == "sweep" then Sweep(rest)
	-- (The player copy's now, ShoulderCalibrate.lua: typed, so no popup.)
	elseif what == "calibrate" then
		local why = ns.ShoulderCalibrateCantStart and ns.ShoulderCalibrateCantStart()
		if why then ns.Print(why) elseif ns.ShoulderCalibrateStart then ns.ShoulderCalibrateStart() end
	elseif what == "try" then Try(rest)
	elseif what == "walls" then Walls()
	elseif what == "forms" then Forms()
	elseif what == "shift" then
		if rest == "move" then Shift(1, true) else Shift(tonumber(rest) or 1) end
	elseif what == "cams" then Cams()
	elseif what == "map" then ns.ShoulderMap(rest)
	elseif what == "zoomcurve" then ns.ShoulderZoomCurve()
	elseif what == "mounts" then ns.ShoulderMounts()
	elseif what == "aimclick" then ns.ShoulderAimClick()
	elseif what == "drag" then ns.ShoulderDrag()
	elseif what == "follow" then ns.ShoulderFollow(rest)
	elseif what == "angles" then ns.ShoulderAngles()
	elseif what == "padscan" then ns.ShoulderPadScan()
	elseif what == "prdcheck" then ns.ShoulderPrdCheck()
	elseif what == "swingsize" or what == "sizes" then ns.ShoulderSwingSize()
	elseif what == "lock" then ns.ShoulderLock()
	elseif what == "selftarget" then ns.ShoulderSelfTarget()
	elseif what == "today" then ns.ShoulderToday(rest)
	elseif what == "profiletest" then ns.ShoulderProfileTest()
	elseif what == "on" then Set("shoulderCam", true)
	elseif what == "off" then Set("shoulderCam", false)
	elseif what == "left" or what == "right" then Set("shoulderCamSide", what)
	elseif what == "spot" and tonumber(rest) then Set("shoulderCamSpot", tonumber(rest) / 100)
	elseif what == "strength" and tonumber(rest) then Set("shoulderCamFramesStrength", tonumber(rest) / 100)
	-- (The Shoulder Cam layout, Layouts.lua: made, or made again from the code, and switched to; offers the reload.)
	elseif what == "layout" then ns.RegenerateLayout("Shoulder Cam")
	else
		ns.Print("shoulder: scan, frames, watch, quiet, sweep offsets|zoom|ease|next|stop, try pitch|head|enemy|interact|walls|off, walls, forms, shift [n|move], cams, map still|talk|ramp|back|walk|enemy, zoomcurve, mounts, aimclick, drag, follow [trial], angles, padscan, prdcheck, calibrate, lock, selftarget, today, profiletest, " ..
			"on, off, left, right, spot <percent>, strength <percent>, layout")
	end
end
