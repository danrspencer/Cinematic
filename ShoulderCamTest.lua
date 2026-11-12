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
	return -yards / (math.max(1.5, Zoom()) * ns.ShoulderViewWidth())
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
			Say(("sweep waiting at step %d of %d: %s. Type /cine debug shoulder sweep next"):format(sweep.at, #sweep.steps,
				tostring(y)))
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
	-- (Steps past the farthest the camera goes here left out: 15 yards times
	-- cameraDistanceMaxZoomFactor, 1 on Forever.)
	local farthest = 15 * (tonumber(GetCVar("cameraDistanceMaxZoomFactor")) or 1) + 0.5
	local kept = {}
	for _, step in ipairs(steps) do
		if not step[2] or step[2] <= farthest then kept[#kept + 1] = step end
	end
	sweep = { name = what, steps = kept, at = 1, readings = {},
		held = { offset = GetCVar(SHOULDER), centered = GetCVar(CENTERED), zoom = Zoom() } }
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
	Log(("walls: VERDICT wall setting: pull-ins %d -> %d (%s)"):format(a.pullIns, b.pullIns,
		b.pullIns < a.pullIns * 0.6 and "FEWER" or "no real change"))
	ns.Print("shoulder walls: done, check log (/reload to save it)")
end
local function WallsBegin(index)
	local labels = { "as it is", "with the wall setting" }
	if index == 2 then
		for cvar, value in pairs(TRIES.walls) do
			if GetCVar(cvar) ~= nil then
				wallRun.kept[cvar] = wallRun.kept[cvar] or GetCVar(cvar)
				SetCVar(cvar, value)
			end
		end
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
		ns.PadTestBox(head, "SHIFT INTO BEAR FORM now (stand still, hands off the camera)", 0.3, 1, 0.3)
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
		ns.PadTestBox(("%d/2: WALK in and out of that doorway, past the wall, a few times"):format(#run.walks),
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
			TalkBox("RIGHT-CLICK THE NPC now (then hands off)", 0.3, 1, 0.3)
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
			if into >= (trial.hold or TALK_HOLD) then
				run.phase, run.began = "return", GetTime()
				TalkClose()
				Log(("map: talk %d closed, facing %s; written (s in: turn/tilt strength): %s"):format(run.at, Facing(),
					#run.writes > 0 and table.concat(run.writes, " ") or "nothing"))
				TalkBox("wait...", 0.7, 0.7, 0.7)
			end
		elseif run.phase == "return" then
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
		Change({ [I .. "StrengthYaw"] = GetCVar(I .. "StrengthYaw"), [I .. "StrengthPitch"] = GetCVar(I .. "StrengthPitch") })
		run = { ticker = C_Timer.NewTicker(0.05, TalkTick), view = _G.SaveView and pcall(_G.SaveView, VIEW_SLOT) or false,
			events = CreateFrame("Frame"), list = list }
		for _, event in ipairs(TALK_EVENTS) do pcall(run.events.RegisterEvent, run.events, event) end
		local this = run
		run.events:SetScript("OnEvent", function(_, event)
			if run ~= this or run.phase ~= "click" then return end
			run.phase, run.began = "open", GetTime()
			Log(("map: talk %d opened (%s) by %s, facing %s (at the click %s)"):format(run.at, event,
				Text(UnitName("npc")), Facing(), run.clickFacing or "?"))
			TalkBox("hands off...", 1, 0.82, 0)
		end)
		Log(("map: %s run, %d trials | %s | screen %.0f x %.0f, view saved %s, zoom %.2f"):format(label, #list, Who(),
			WorldFrame:GetWidth(), WorldFrame:GetHeight(), Text(run.view), Zoom()))
		ns.Print(("shoulder map: record your screen; %d right-clicks on the NPC, told when; type it again to stop"):format(
			#list))
		C_Timer.After(1, function() if run == this and not run.at then TalkBegin(1) end end)
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
		if kind ~= "still" then return ns.Print("shoulder map: still [first trial], talk, ramp, back") end
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
	elseif what == "try" then Try(rest)
	elseif what == "walls" then Walls()
	elseif what == "forms" then Forms()
	elseif what == "cams" then Cams()
	elseif what == "map" then ns.ShoulderMap(rest)
	elseif what == "on" then Set("shoulderCam", true)
	elseif what == "off" then Set("shoulderCam", false)
	elseif what == "left" or what == "right" then Set("shoulderCamSide", what)
	elseif what == "spot" and tonumber(rest) then Set("shoulderCamSpot", tonumber(rest) / 100)
	elseif what == "strength" and tonumber(rest) then Set("shoulderCamFramesStrength", tonumber(rest) / 100)
	-- (The Shoulder Cam layout, Layouts.lua: made, or made again from the code, and switched to; offers the reload.)
	elseif what == "layout" then ns.RegenerateLayout("Shoulder Cam")
	else
		ns.Print("shoulder: scan, frames, watch, quiet, sweep offsets|zoom|ease|next|stop, try pitch|head|enemy|interact|walls|off, walls, forms, cams, map still|talk|ramp|back, " ..
			"on, off, left, right, spot <percent>, strength <percent>, layout")
	end
end
