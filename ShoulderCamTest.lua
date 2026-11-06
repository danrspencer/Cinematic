-- Shoulder Cam tests (dev copy only): /cine debug shoulder <what>, each a line
-- or more in the saved log (category "shoulder"), so a run's read from the
-- file after a /reload. Tools/shoulder-test-plan.md has the runs.
--
-- on, off, left, right, offset <yards>, strength <percent>: set it from chat.
-- scan: every camera setting the client has, its default, who you are.
-- frames: where the frames that follow you are anchored, and can they move.
-- watch: (again to stop; stays on over a reload) every change to a camera
--   setting and who made it, the warning popup, mounts and forms, and each
--   session's values at login. For "what keeps writing that?".
-- sweep offsets|zoom|ease|next|stop: measures where you really are on screen.
--   It says a line (the game puts your chat bubble right over you), then steps
--   the offset or the zoom and reads the bubble. A bubble doesn't last: when
--   it's gone the sweep waits, and "sweep next" says another line and goes on.
-- try pitch|head|enemy|interact|off: one of the game's other experimental
--   camera settings on (again: off), for a look. "try off" puts all back.
local _, ns = ...

local SETTLE = 1.6     -- seconds a step waits for the game to ease over
local EASE_TIME = 3    -- seconds the ease run follows one step for
local SAMPLE = 0.05    -- seconds between bubble reads
local LINE = "Testing my camera, please ignore this line of text for a moment."
local SHOULDER, CENTERED = "test_cameraOverShoulder", "CameraKeepCharacterCentered"

local CAMERA_CVARS = { SHOULDER, CENTERED, "test_cameraDynamicPitch", "test_cameraDynamicPitchBaseFovPad",
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
}

local function Log(text) ns.Log("shoulder", text) end
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

local function Frames()
	for _, name in ipairs(FOLLOW_FRAMES) do
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
			Log(("frames: %s: shown %s, protected %s, scale %s, points: %s"):format(name, Text(ns.Flag(frame:IsShown())),
				Text(ns.Flag(frame:IsProtected())), Text(frame:GetEffectiveScale()),
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
	local stack = debugstack and debugstack(3, 2, 0) or ""
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
local function Values(when)
	Log(("watch: %s: offset %s, centered %s, switch %s, yours kept %s | %s"):format(when, Text(GetCVar(SHOULDER)),
		Text(GetCVar(CENTERED)), Text(ns.db and ns.db.shoulderCam), Text(ns.db and ns.db.shoulderCamYours ~= nil), Who()))
end
watcher:SetScript("OnEvent", function(self, event, name, value)
	if not self.on then return end
	if event == "CVAR_UPDATE" then
		if type(name) == "string" and WATCHED[name:lower()] then
			Log(("watch: CVAR_UPDATE %s = %s (reads %s)"):format(name, Text(value), Text(GetCVar(name))))
		end
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
			"PLAYER_MOUNT_DISPLAY_CHANGED", "UPDATE_SHAPESHIFT_FORM" }) do
			pcall(watcher.RegisterEvent, watcher, event)
		end
		watcher:Show()
	else
		watcher:UnregisterAllEvents()
		watcher:Hide()
	end
end
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self)
	if ns.db then
		self:UnregisterAllEvents()
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
			local okSame, same = pcall(function() return says == LINE end)
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
	local fov = tonumber(GetCVar("cameraFov")) or 90
	return -yards / (math.max(1.5, Zoom()) * math.tan(math.rad(fov / 2)))
end

-- A sweep: steps of { offset, zoom (or nil) }, run in turn while a bubble's up.
local sweep -- { name, steps, at, waited, baseline, held = your settings, readings }
local stepper = CreateFrame("Frame")
stepper:Hide()

local function SendLine()
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	if send then send(LINE, "SAY") end
end

local function EndSweep()
	stepper:Hide()
	if not sweep then return end
	SetCVar(SHOULDER, sweep.held.offset)
	SetCVar(CENTERED, sweep.held.centered)
	ns.shoulderTestHold = nil
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	local total, count = 0, 0
	for _, factor in ipairs(sweep.readings) do
		total, count = total + factor, count + 1
	end
	Say(("sweep %s done: %d steps, real/worked-out mean %s | %s (/reload to save it)"):format(sweep.name,
		sweep.at - 1, count > 0 and ("%.2f"):format(total / count) or "none", Who()))
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
		if sweep.hadBubble or sweep.waited > 1 then
			sweep.paused = true
			stepper:Hide()
			Say(("sweep waiting at step %d of %d: %s. Type /cine debug shoulder sweep next"):format(sweep.at, #sweep.steps,
				tostring(y)))
		end
		return
	end
	sweep.hadBubble = true
	if sweep.last and math.abs(x - sweep.last) > 0.001 then sweep.moved = sweep.waited end
	sweep.last = x
	if sweep.name == "ease" then
		Log(("ease: step %d, %.2f s: bubble x %.4f"):format(sweep.at, sweep.waited, x))
	end
	if sweep.waited >= (sweep.name == "ease" and EASE_TIME or SETTLE) then
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
	zoom = { { 0, 15 }, { 1, 15 }, { 1, 5 }, { 1, 8 }, { 1, 12 }, { 1, 20 }, { 1, 28 } },
	ease = { { 0 }, { 2 }, { -2 } },
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
	sweep = { name = what, steps = steps, at = 1, readings = {},
		held = { offset = GetCVar(SHOULDER), centered = GetCVar(CENTERED) } }
	ns.shoulderTestHold = true -- (ShoulderCam.lua keeps its hands off meanwhile)
	SetCVar(CENTERED, "0")
	Log(("sweep %s starting: %s | offset %s, zoom %.2f, cameraFov %s, chatBubbles %s"):format(what, Who(),
		Text(sweep.held.offset), Zoom(), Text(GetCVar("cameraFov")), Text(GetCVar("chatBubbles"))))
	SendLine()
	BeginStep(steps[1])
	stepper:Show()
	ns.Print(("shoulder sweep %s: stand still and leave the camera alone"):format(what))
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
		ns.Print("shoulder try: pitch, head, enemy, interact or off")
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
	elseif what == "sweep" then Sweep(rest)
	elseif what == "try" then Try(rest)
	elseif what == "on" then Set("shoulderCam", true)
	elseif what == "off" then Set("shoulderCam", false)
	elseif what == "left" or what == "right" then Set("shoulderCamSide", what)
	elseif what == "offset" and tonumber(rest) then Set("shoulderCamOffset", tonumber(rest))
	elseif what == "strength" and tonumber(rest) then Set("shoulderCamFramesStrength", tonumber(rest) / 100)
	else
		ns.Print("shoulder: scan, frames, watch, sweep offsets|zoom|ease|next|stop, try pitch|head|enemy|interact|off, " ..
			"on, off, left, right, offset <yards>, strength <percent>")
	end
end
