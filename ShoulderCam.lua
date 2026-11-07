-- Shoulder Cam (shoulderCam): the camera sits over your shoulder (right, or
-- left: shoulderCamSide), you to the side of the screen. It's the game's
-- test_cameraOverShoulder offset (yards, negative for the left), which it
-- eases over to on its own (in about 0.3 s: Run 3). That's a fixed distance,
-- so the closer the camera the further aside it pushes you: 1 yard is 5% of
-- the way to the screen's edge at 15 yards away, 41% at 2 (Run 3b). So you
-- pick a spot instead (shoulderCamSpot: that share of the way from the middle
-- to the edge) and the offset follows your zoom to hold you there, eased back
-- to the middle closer than SPOT_EASE_TO yards. The game ignores that while Keep
-- Character Centered (Accessibility) is on, so that's turned off meanwhile, and
-- CameraReduceUnexpectedMovement too (the same since 11.0.2, as DynamicCam found).
-- It's one of Blizzard's experimental camera settings: writing it brings up
-- their warning, once a session, and the game clears the offset at every
-- reload and login (Forever, Run 2 of Tools/shoulder-test-plan.md), so theirs
-- would come every session. Ours instead, once ever (db.shoulderCamNoticed,
-- not part of a profile): until it's accepted nothing's written, and Cancel
-- turns the Shoulder Cam off. After that the game's warning is kept quiet
-- while it's on: its event stopped, as DynamicCam and DialogueUI do (Run 2b:
-- none at the write, a reload or a relog). The game can't be told to hear it
-- again, so after turning off it's back from the next /reload.
-- Your own settings (db.shoulderCamYours) come back as it's turned off.
-- Disable (ResetTestCvars) turns it off here too.
-- (Not ns.ApplyCVarSet: Keep Character Centered would be put back on logout.)
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
local SPOT_EASE_FROM, SPOT_EASE_TO = 1, 4 -- yards: in the middle at 1, eased out to your spot by 4
local OFFSET_MOST = 15 -- yards (DynamicCam's range too)
local OFFSET_STEP = 0.02 -- yards: a smaller change to the offset isn't written
local paused -- (PauseReason at the last check, every POLL)

-- The offset that holds you at your spot at this distance (Run 3: you sit
-- yards / (distance x view width) of the way to the edge).
local function SpotYards()
	local distance = GetCameraZoom and GetCameraZoom() or 8
	local yards = (ns.db.shoulderCamSpot or 0.2) * distance * ns.ShoulderViewWidth()
	local k = math.min(1, math.max(0, (distance - SPOT_EASE_FROM) / (SPOT_EASE_TO - SPOT_EASE_FROM)))
	return math.min(OFFSET_MOST, yards * k * k * (3 - 2 * k))
end

local function ShoulderValue(again)
	if not again then paused = PauseReason() end
	if paused then
		return "0"
	end
	local yards = SpotYards()
	return ("%.2f"):format(ns.db.shoulderCamSide == "left" and -yards or yards)
end

-- (The offset's following your zoom: logged in full only to the detail log.)
local function Write(yours, cvar, value)
	local now = GetCVar(cvar)
	if now ~= nil and not Same(now, value) then
		if yours[cvar] == nil then
			yours[cvar] = now
		end
		local text = ("Shoulder Cam: %s %s -> %s"):format(cvar, now, value)
		if cvar == "test_cameraOverShoulder" and tonumber(now) ~= 0 and tonumber(value) ~= 0 then
			ns.LogDetail("cvar", text)
		else
			ns.Log("cvar", text)
		end
		SetCVar(cvar, value)
	end
end

local UpdateFollow -- (below: the frames that follow you)

-- The game's warning kept quiet (since WoW 12.1 its event goes through
-- GameEvent; before, UIParent heard it).
local WARNING_EVENT = "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED"
local quieted
local function QuietWarning()
	if quieted then return end
	quieted = true
	local game = _G.GameEvent
	if game and game.UnregisterInternalEvent then pcall(game.UnregisterInternalEvent, WARNING_EVENT) end
	pcall(UIParent.UnregisterEvent, UIParent, WARNING_EVENT)
	ns.Log("cvar", "Shoulder Cam: the game's experimental camera warning kept quiet")
end

-- (Tools/shoulder-sim: a new session, as a reload starts this file again.)
function ns.ResetShoulderSession() quieted = nil end

-- Our notice, once: Accept and it starts; Cancel turns it off.
local asking
local function Answered(yes)
	asking = nil
	if yes then
		ns.db.shoulderCamNoticed = true
	else
		ns.db.shoulderCam = false
	end
	ns.ApplyShoulderCam()
	if ns.RefreshOptions then ns.RefreshOptions() end
end
local function AskNotice()
	if asking then return end
	asking = true
	if not StaticPopupDialogs.CINEMATIC_SHOULDER_NOTICE then
		StaticPopupDialogs.CINEMATIC_SHOULDER_NOTICE = {
			text = L["The Shoulder Cam uses one of Blizzard's experimental camera settings. The game would " ..
				"warn about it every time you log in, so Cinematic keeps that warning away while the Shoulder " ..
				"Cam is on. If the camera ever acts up, turn the Shoulder Cam off and your own camera " ..
				"settings come back."],
			button1 = ACCEPT or L["Accept"], button2 = CANCEL or L["Cancel"],
			OnAccept = function() Answered(true) end,
			OnCancel = function() Answered(false) end,
			timeout = 0, whileDead = true, hideOnEscape = false,
		}
	end
	StaticPopup_Show("CINEMATIC_SHOULDER_NOTICE")
end

local poller = CreateFrame("Frame")
poller:Hide()

function ns.ApplyShoulderCam()
	if not ns.db then
		return
	end
	local yours = ns.db.shoulderCamYours
	if ns.Setting("shoulderCam") and not ns.db.shoulderCamNoticed then
		AskNotice() -- (nothing written till it's answered)
	elseif ns.Setting("shoulderCam") then
		QuietWarning()
		yours = yours or {}
		ns.db.shoulderCamYours = yours
		-- (DialogueUI's camera sets the same offset for its talks, and puts
		-- back what it found: hands off till it's done. Support/DialogueUI.lua.)
		if not (ns.shoulderTestHold or (ns.DialogueUICameraOn and ns.DialogueUICameraOn())) then
			Write(yours, "CameraKeepCharacterCentered", "0")
			Write(yours, "CameraReduceUnexpectedMovement", "0")
			Write(yours, "test_cameraOverShoulder", ShoulderValue())
		end
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

-- (Picks up pauses, and the page's sliders and ticks, a moment later; the
-- offset follows your zoom every frame in between.)
local waited = 0
ns.SetOnUpdate(poller, function(_, elapsed)
	waited = waited + elapsed
	if waited >= POLL then
		waited = 0
		ns.ApplyShoulderCam()
		return
	end
	local yours = ns.db and ns.db.shoulderCamYours
	if paused or not yours or ns.shoulderTestHold or (ns.DialogueUICameraOn and ns.DialogueUICameraOn()) then return end
	local value = ShoulderValue(true)
	if math.abs((tonumber(GetCVar("test_cameraOverShoulder")) or 0) - tonumber(value)) >= OFFSET_STEP then
		Write(yours, "test_cameraOverShoulder", value)
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
-- view (ns.ShoulderViewWidth). Right shoulder: you're left of the middle.
-- Measured with your chat bubble (Run 3): it holds for a standard model.
-- shoulderCamFramesStrength scales it.
-- A frame on a nameplate stays (retail's PRD on your own plate already
-- follows you), and of a chain (cast bar on the PRD, the PRD on the cooldowns:
-- Forever, Run 1) only the first of ours moves; the rest ride along. Points are kept as the game set them and
-- given back with the slide added; when the game sets them again (its
-- layout, Edit Mode), that's taken as their place from then on. Nothing
-- moves while Edit Mode is open, nor a protected frame in a fight.
local FOLLOW_FRAMES = { "PlayerCastingBarFrame", "CastingBarFrame", "GamepadPlayerCastingBarFrame",
	"PersonalResourceDisplayFrame", "CinematicPersonalResource" }
local FOLLOW_EASE = 12     -- how quickly the frames catch up (per second; the game eases over in ~0.3 s)
local FOLLOW_MAX = 0.3     -- never more than this share of the screen's width
local FOLLOW_MIN_ZOOM = 3 -- (closer, as this: in a 2026-11-07 recording at ~1.5 yards the bar went
                           -- to where your head-top is, well past your body; first person has no side)
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

local FOLLOWS = {}
for _, name in ipairs(FOLLOW_FRAMES) do FOLLOWS[name] = true end

-- What a frame hangs on, up its chain of anchors (first points): "plate" if
-- a nameplate (it follows you already), another of FOLLOW_FRAMES (it rides
-- along when that one moves: never moved twice), else nil (the screen, or a
-- frame that stays put, as Forever's PRD on EssentialCooldownViewer: Run 1).
local function Hangs(frame)
	local at = frame
	for _ = 1, 8 do
		local ok, _, to = pcall(at.GetPoint, at, 1)
		if not ok or type(to) ~= "table" or to == UIParent then return nil end
		local okName, name = pcall(to.GetName, to)
		name = okName and type(name) == "string" and name or ""
		if name:find("^NamePlate") or to.UnitFrame or to.namePlateUnitToken then return "plate" end
		if FOLLOWS[name] and to ~= frame then return to end
		at = to
	end
end

-- Whether this frame is the one to move: not on a plate, and not riding
-- along with another of ours that moves.
local function Mover(frame)
	local hangs = Hangs(frame)
	if hangs == "plate" then return false end
	if hangs then return not (Hangs(hangs) ~= "plate" and ReadPoints(hangs)) end
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

-- How wide the view is: the tangent of half the field of view across the
-- screen. cameraFov is across a 16:9 screen; a wider or narrower one keeps its
-- height (Run 3, Forever: a 2.39:1 ultrawide measured 0.73-0.77 of the plain
-- 16:9 sum, which says 0.74).
function ns.ShoulderViewWidth()
	local fov = math.min(120, math.max(30, tonumber(GetCVar("cameraFov")) or 90))
	local aspect = WorldFrame:GetWidth() / math.max(1, WorldFrame:GetHeight())
	return math.tan(math.rad(fov / 2)) * aspect / (16 / 9)
end

local function TargetShift()
	local db = ns.db
	if not (db and ns.Setting("shoulderCam") and db.shoulderCamFrames) then return 0 end
	local yards = tonumber(GetCVar("test_cameraOverShoulder")) or 0
	if yards == 0 then return 0 end
	local distance = math.max(FOLLOW_MIN_ZOOM, GetCameraZoom and GetCameraZoom() or 5)
	local half = UIParent:GetWidth() / 2
	local shift = -yards / (distance * ns.ShoulderViewWidth()) * half * (db.shoulderCamFramesStrength or 1)
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
				entry = { points = now, ours = now, shift = 0 }
				followed[frame] = entry
			end
			-- (Riding along with another, or on a plate: back on its own place.)
			if entry and not Mover(frame) then
				if entry.shift ~= 0 then Place(frame, entry, 0) end
				entry, followed[frame] = nil, nil
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
		side = db and db.shoulderCamSide, spot = db and db.shoulderCamSpot,
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
		"The game's Keep Character Centered and motion sickness options stop it, so those are turned " ..
		"off meanwhile. Off: your own settings come back."], intro, ns.ApplyShoulderCam)
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
	local spot = stack:Add(kit.Slider(content, "shoulderCamSpot", L["Spot on screen"], 5, 40, 1, "%d%%", 100),
		"slider")
	kit.Tooltip(spot, L["How far off the middle of the screen you sit, as a share of the way to its edge. " ..
		"The camera moves as you zoom to keep you there, and eases you back to the middle when you zoom " ..
		"right in. 33% puts you on the line a third of the way across."])
	kit.GreyUnless(spot, IfOn)
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
