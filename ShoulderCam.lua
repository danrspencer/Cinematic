-- Shoulder Cam (shoulderCam): the camera sits over your shoulder (right, or
-- left: shoulderCamSide), you to the side of the screen. It's the game's
-- test_cameraOverShoulder offset (yards: shoulderCamOffset, negative for the
-- left), which it eases over to on its own. The game ignores that while Keep
-- Character Centered (Accessibility) is on, so that's turned off meanwhile.
-- It's one of Blizzard's experimental camera settings: writing it brings up
-- their warning. Accept saves nothing; it's the write that brings it up. So
-- while it's on, the settings stay as they are over logout (the game keeps
-- them), and are only written when they differ: Accept once, not each login.
-- (Tested: once accepted, 0 and back again in the same session brings no
-- warning, so pausing below is fine.)
-- Your own settings (db.shoulderCamYours) come back as it's turned off.
-- Disable (ResetTestCvars) turns it off here too.
-- (Not ns.ApplyCVarSet: that puts them back on logout and writes them again
-- on login, the warning each time.)
--
-- It's a held setting, not a camera: it doesn't move the view, so it doesn't
-- claim the camera lock. It goes to 0 (paused) while mounted
-- (shoulderCamNotMounted) and while one of Cinematic's cameras that frame you
-- runs (shoulderCamPause): the standing-still ones (cozy, vista, fish, AFK,
-- teleport), the flight camera and its fly-bys, and the death camera, whose
-- shots are built around you in the middle, and wherever its Show in row
-- (shoulder:cam) has it off. The quest cam and Chat Cam keep
-- it: an over-the-shoulder dialogue shot is the look they're after.
local ADDON_NAME, ns = ...
local L = ns.L

local POLL = 0.2 -- seconds between checks for a pause (mounting, a camera starting)

-- Where: its Show in row (Always ticked to start with: everywhere). Off
-- there, it's paused (back behind you) as any other pause.
local ROW_KEY = "shoulder:cam"
ns.CINE_SHOW_SETTING[ROW_KEY] = "shoulderCamAlways"

local function Same(a, b)
	return a == b or (tonumber(a) ~= nil and tonumber(a) == tonumber(b))
end

-- Why it's paused now, or nil.
local function PauseReason()
	local db = ns.db
	if not db.shoulderCamAlways then
		local ok, here = pcall(ns.RowOnNow, ROW_KEY, false, true)
		if not (ok and here) then
			return "show in"
		end
	end
	-- (ns.Flag: any of these can be secret on Forever.)
	if db.shoulderCamNotMounted and IsMounted and ns.Flag(IsMounted()) then
		return "mounted"
	end
	if db.shoulderCamPause then
		if UnitOnTaxi and ns.Flag(UnitOnTaxi("player")) then
			return "flight"
		end
		if UnitIsDead and ns.Flag(UnitIsDead("player")) then
			return "dead"
		end
		local camera = ns.ActiveEvent and select(2, ns.ActiveEvent())
		if camera and camera ~= "quest" then
			return camera
		end
	end
end

-- The offset to write: yards, negative for the left shoulder; "0" paused.
local function ShoulderValue()
	if PauseReason() then
		return "0"
	end
	local offset = ns.db.shoulderCamOffset or 1
	return ("%.2f"):format(ns.db.shoulderCamSide == "left" and -offset or offset)
end

local function Write(yours, cvar, value)
	local now = GetCVar(cvar)
	if now ~= nil and not Same(now, value) then
		if yours[cvar] == nil then
			yours[cvar] = now
		end
		ns.Log("cvar", ("Shoulder Cam: %s %s -> %s"):format(cvar, now, value))
		SetCVar(cvar, value)
	end
end

local UpdateFollow -- (below: the frames that follow you)

local poller = CreateFrame("Frame")
poller:Hide()

function ns.ApplyShoulderCam()
	if not ns.db then
		return
	end
	local yours = ns.db.shoulderCamYours
	if ns.Setting("shoulderCam") then
		yours = yours or {}
		ns.db.shoulderCamYours = yours
		Write(yours, "CameraKeepCharacterCentered", "0")
		Write(yours, "test_cameraOverShoulder", ShoulderValue())
		poller:Show()
	else
		poller:Hide()
		if yours then
			for cvar, value in pairs(yours) do
				if not Same(GetCVar(cvar), value) then
					ns.Log("cvar", ("Shoulder Cam: %s back to %s"):format(cvar, value))
					SetCVar(cvar, value)
				end
			end
			ns.db.shoulderCamYours = nil
		end
	end
	if UpdateFollow then UpdateFollow() end
end

-- (Picks up pauses, and the page's sliders and ticks, a moment later.)
local waited = 0
ns.SetOnUpdate(poller, function(_, elapsed)
	waited = waited + elapsed
	if waited >= POLL then
		waited = 0
		ns.ApplyShoulderCam()
	end
end)

-- The swap shoulders key: a button its key binding clicks (bound on the
-- Shoulder Cam page; no entry in Bindings.xml, as the page is the dev copy's).
local swap = CreateFrame("Button", ADDON_NAME .. "ShoulderSwapButton", UIParent)
swap:RegisterForClicks("AnyDown")
swap:SetScript("OnClick", function()
	if not ns.db then
		return
	end
	ns.db.shoulderCamSide = ns.db.shoulderCamSide == "left" and "right" or "left"
	ns.ApplyShoulderCam()
	if ns.RefreshOptions then ns.RefreshOptions() end
end)
local SWAP_ACTION = "CLICK " .. swap:GetName() .. ":LeftButton"

-- Frames follow you (shoulderCamFrames): with you off to one side, the cast
-- bar and the Personal Resource Display slide over with you. Where you are
-- on screen can't be read (plates can't be measured), so it's worked out:
-- the game's offset now (test_cameraOverShoulder, 0 while paused) over the
-- camera's distance, as a share of half the screen's width at its field of
-- view (cameraFov, across). Right shoulder: you're left of the middle.
-- shoulderCamFramesStrength scales it (the sum's a guess: tune in game).
-- Only frames anchored to the screen move (retail's PRD on your own plate
-- already follows you). Their points are kept as the game set them and
-- given back with the slide added; when the game sets them again (its
-- layout, Edit Mode), that's taken as their place from then on. Nothing
-- moves while Edit Mode is open, nor a protected frame in a fight.
local FOLLOW_FRAMES = { "PlayerCastingBarFrame", "CastingBarFrame", "GamepadPlayerCastingBarFrame",
	"PersonalResourceDisplayFrame", "CinematicPersonalResource" }
local FOLLOW_EASE = 4      -- how quickly the frames catch up (per second)
local FOLLOW_MAX = 0.3     -- never more than this share of the screen's width
local FOLLOW_MIN_ZOOM = 1.5 -- (closer than this, as this: first person has no side)
local followed = {}        -- frame -> { points = the game's, ours = what we put on, shift = ours in UI units }
local followShift = 0      -- the slide now (UIParent units, + right), easing to the target

local function EditModeOpen()
	local editMode = _G.EditModeManagerFrame
	return editMode and editMode.IsEditModeActive and ns.Flag(editMode:IsEditModeActive()) or false
end

-- A frame's points, or nil if any can't be read plainly (secret, restricted).
local function ReadPoints(frame)
	local ok, count = pcall(frame.GetNumPoints, frame)
	if not ok or type(count) ~= "number" or count == 0 then return nil end
	local points = {}
	for i = 1, count do
		local okPoint, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, i)
		if not okPoint or type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then
			return nil
		end
		points[i] = { point, relativeTo, relativePoint, x, y }
	end
	return points
end

local function SamePoints(a, b)
	if not (a and b) or #a ~= #b then return false end
	for i = 1, #a do
		for j = 1, 3 do if a[i][j] ~= b[i][j] then return false end end
		if math.abs(a[i][4] - b[i][4]) > 0.01 or math.abs(a[i][5] - b[i][5]) > 0.01 then return false end
	end
	return true
end

-- On the screen: every point on UIParent (or nothing), not a nameplate.
local function OnScreen(points)
	for _, p in ipairs(points) do
		if p[2] ~= nil and p[2] ~= UIParent then return false end
	end
	return true
end

local function Place(frame, entry, shift)
	if ns.Flag(frame:IsProtected()) and InCombatLockdown() then return end
	local scale = UIParent:GetEffectiveScale() / math.max(0.01, frame:GetEffectiveScale())
	local ours = {}
	frame:ClearAllPoints()
	for i, p in ipairs(entry.points) do
		ours[i] = { p[1], p[2], p[3], p[4] + shift * scale, p[5] }
		frame:SetPoint(p[1], p[2] or UIParent, p[3], ours[i][4], p[5])
	end
	-- (Read back: what the game reports for them, to see when it moves them.)
	entry.ours, entry.shift = ReadPoints(frame) or ours, shift
end

-- Every followed frame back where the game had it, and forgotten.
local function PutBack()
	for frame, entry in pairs(followed) do
		if entry.shift ~= 0 then Place(frame, entry, 0) end
		followed[frame] = nil
	end
	followShift = 0
end

local function TargetShift()
	local db = ns.db
	if not (db and ns.Setting("shoulderCam") and db.shoulderCamFrames) then return 0 end
	local yards = tonumber(GetCVar("test_cameraOverShoulder")) or 0
	if yards == 0 then return 0 end
	local distance = math.max(FOLLOW_MIN_ZOOM, GetCameraZoom and GetCameraZoom() or 5)
	local fov = math.min(120, math.max(30, tonumber(GetCVar("cameraFov")) or 90))
	local half = UIParent:GetWidth() / 2
	local shift = -yards / (distance * math.tan(math.rad(fov / 2))) * half * (db.shoulderCamFramesStrength or 1)
	local most = UIParent:GetWidth() * FOLLOW_MAX
	return math.max(-most, math.min(most, shift))
end

local follower = CreateFrame("Frame")
follower:Hide()
ns.SetOnUpdate(follower, function(self, elapsed)
	if EditModeOpen() then
		PutBack()
		return
	end
	local target = TargetShift()
	followShift = followShift + (target - followShift) * math.min(1, elapsed * FOLLOW_EASE)
	if math.abs(target - followShift) < 0.25 then followShift = target end
	for _, name in ipairs(FOLLOW_FRAMES) do
		local frame = _G[name]
		if frame and frame.GetPoint then
			local entry, now = followed[frame], ReadPoints(frame)
			-- (Moved by the game since: its new place.)
			if now and (not entry or not SamePoints(now, entry.ours)) then
				if OnScreen(now) then
					entry = { points = now, ours = now, shift = 0 }
					followed[frame] = entry
				else
					entry, followed[frame] = nil, nil
				end
			end
			if entry and math.abs(entry.shift - followShift) >= 0.5 then
				Place(frame, entry, followShift)
			end
		end
	end
	-- (Back home and nothing more wanted: stop.)
	if target == 0 and followShift == 0 then
		PutBack()
		self:Hide()
	end
end)

function UpdateFollow()
	if ns.db and ns.Setting("shoulderCam") and ns.db.shoulderCamFrames or next(followed) then
		follower:Show()
	end
end

-- For /cine debug shoulder.
function ns.GetShoulderCamDebug()
	local db = ns.db
	return {
		setting = db and db.shoulderCam, applied = db and db.shoulderCamYours ~= nil,
		shoulder = GetCVar("test_cameraOverShoulder"), centered = GetCVar("CameraKeepCharacterCentered"),
		side = db and db.shoulderCamSide, offset = db and db.shoulderCamOffset,
		follow = db and db.shoulderCamFrames, followShift = followShift, followTarget = TargetShift(),
		followed = (function()
			local names = {}
			for frame in pairs(followed) do names[#names + 1] = frame:GetName() or "?" end
			return #names > 0 and table.concat(names, ", ") or "none"
		end)(),
		paused = db and PauseReason() or "no", always = db and db.shoulderCamAlways, key = GetBindingKey(SWAP_ACTION) or "none",
	}
end

-- The warning's Disable: the game has put the experimental settings back
-- itself, so the switch goes off and the rest of yours come back.
if ResetTestCvars then
	hooksecurefunc("ResetTestCvars", function()
		if ns.db and ns.db.shoulderCam then
			ns.db.shoulderCam = false
			if ns.db.shoulderCamYours then
				ns.db.shoulderCamYours.test_cameraOverShoulder = nil
			end
			ns.ApplyShoulderCam()
			ns.Print(L["Shoulder Cam turned off: the game's experimental camera warning was disabled."])
			if ns.RefreshOptions then ns.RefreshOptions() end
		end
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", ns.ApplyShoulderCam)

function ns.CreateShoulderCamPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Shoulder Cam"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["The camera sits over your shoulder, with you to one side of the screen."])
	local switch = kit.PageSwitch(content, "shoulderCam", L["Enable Page"],
		L["On: the camera moves over your shoulder. This uses one of Blizzard's experimental " ..
		"camera settings: the game shows its experimental camera warning (Accept keeps it working). " ..
		"The game's Keep Character Centered option (Accessibility) stops it, so that's turned off " ..
		"meanwhile. Off: your own settings come back."], intro, ns.ApplyShoulderCam)
	local function IfOn() return ns.Setting("shoulderCam") end
	local stack = kit.Stack(switch, "check")

	local header = stack:Header(content, L["Show in"])
	local lastRow = ns.ShowTable(content, header, {
		opts = { quiet = true, cam = true, anyFight = true }, underHeader = true,
		{ key = ROW_KEY, label = L["Shoulder Cam"], alwaysKey = "shoulderCamAlways",
			alwaysOn = function() return ns.GetDB().shoulderCamAlways end,
			setAlways = function(value) ns.GetDB().shoulderCamAlways = value ns.ApplyShoulderCam() end,
			alwaysTip = L["Over your shoulder wherever you are. (The other columns then have nothing to add.)"],
			apply = ns.ApplyShoulderCam },
	}, L["Shoulder Cam"])
	stack:Continue(lastRow, "label")

	stack:Header(content, L["Shoulder"])
	local offset = stack:Add(kit.Slider(content, "shoulderCamOffset", L["Offset"], 0.25, 2, 0.25,
		L["%.2f yards"]), "slider")
	kit.Tooltip(offset, L["How far to the side the camera moves. About 1 is subtle; 1.5 to 2 is a strong " ..
		"over-the-shoulder look."])
	kit.GreyUnless(offset, IfOn)
	stack:Add(kit.Label(content, "GameFontHighlight", L["Side"]), "label")
	for _, side in ipairs({ { "right", L["Right shoulder"] }, { "left", L["Left shoulder"] } }) do
		kit.GreyUnless(stack:Add(kit.Choice(content, "shoulderCamSide", side[1], side[2],
			L["Which shoulder the camera looks over. The swap key below flips it."]), "check"), IfOn)
	end
	local keyLabel = stack:Add(kit.Label(content, "GameFontHighlight", L["Swap shoulders key"]), "label")
	local key = kit.CreateKeybindButton(content, SWAP_ACTION, 1)
	key:SetPoint("LEFT", keyLabel, "LEFT", 200, 0)

	stack:Header(content, L["Frames"])
	kit.GreyUnless(stack:Add(kit.Check(content, "shoulderCamFrames", L["Frames follow you"],
		L["Your cast bar and Personal Resource Display slide over to where you are on the screen, and " ..
		"glide back as the camera goes behind you. Edit Mode still places them: this moves them from " ..
		"there."], UpdateFollow), "check"), IfOn)
	local strength = stack:Add(kit.Slider(content, "shoulderCamFramesStrength", L["Follow strength"], 0, 200, 5,
		"%d%%", 100), "slider")
	kit.Tooltip(strength, L["How far they slide. Where you are on the screen is worked out from the camera, " ..
		"not read: if they land short of you or past you, turn this up or down."])
	kit.GreyUnless(strength, function() return ns.Setting("shoulderCam") and ns.GetDB().shoulderCamFrames end)

	stack:Header(content, L["Pause"])
	kit.GreyUnless(stack:Add(kit.Check(content, "shoulderCamNotMounted", L["Not while mounted"],
		L["On a mount the camera stays straight behind you: a big mount's head fills the shot from " ..
		"the side."]), "check"), IfOn)
	kit.GreyUnless(stack:Add(kit.Check(content, "shoulderCamPause", L["Not during Cinematic's cameras that frame you"],
		L["While the standing-still, AFK, flight, fly-by or death camera runs, the camera goes back " ..
		"behind you, as their shots are built around you in the middle. It comes back as they end. " ..
		"The quest and chat cameras keep it."]), "check"), IfOn)

	canvas:SetScript("OnShow", kit.PageShown(function()
		kit.Refresh()
		kit.RefreshKeybinds()
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Shoulder Cam")
end
