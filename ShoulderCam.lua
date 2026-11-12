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
-- (shoulderCamNotMounted), indoors (shoulderCamNotIndoors) and while one of Cinematic's cameras that frame you
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
	-- (Indoors the game pushes the camera in off the walls, and the offset jerks
	-- with each push: DynamicCam's help says so too. Back in the middle there.)
	if db.shoulderCamNotIndoors and IsIndoors and ns.Flag(IsIndoors()) then
		return "indoors"
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
-- The model's size factor (Run 4): how far the game moves you for an offset,
-- as a share of how far it moves a Dwarf (a Skyborne 0.86). Ours, measured
-- (never another addon's tables): each `/cine debug shoulder sweep offsets`
-- on foot saves the one for your race and sex (db.shoulderCamScales, not part
-- of a profile), over the ones measured so far here. 1 until measured.
-- A shapeshift form is another model with its own factor: a Night Elf's bear
-- sat about twice as far out as the elf for the same offset (a 2026-11-11
-- recording: ~18% of the way to the edge, then ~35% each time bear form went
-- on, back each time it came off). So a form has its own key (race-sex-formN),
-- measured by the same sweep in that form; until then a bear goes by
-- FORM_SCALES, read off recordings, and other forms by the on-foot factor.
-- (A second recording, 18:46 that day, with 1.75 for the bear and 1 for the
-- elf and the spot at 20%: the bear rested at 21%, the elf at 16.5%.)
-- The model changes later than the form does on the way out: the game says
-- "no form" about 0.15 s before the bear's gone (that recording: with the
-- elf's offset written at once the bear swung out to ~40%, then the elf
-- snapped back to 16%). Into a form it's 0.06 to 0.1 s later (the log), and
-- an offset written at the form's change, ahead of it, jumped the whole view
-- sideways in one frame and crept back (a third recording, 18:51: a stump
-- beside you jumped 6% of the screen's width). Written in the model's own
-- frame (UNIT_MODEL_CHANGED) the game's change of factor and its ease to the
-- new offset cancel: out of bear form that way the view hardly moved. So at
-- any change of form the old factor's kept till the model's changed, or
-- SWAP_WAIT at most.
-- (That third recording, standing still: the elf rested on 20.1% with 0.82,
-- the bear on 18.4% with 1.85, so 1.70.)
-- (Mounts change it too: not measured yet.)
local MEASURED_SCALES = { ["Dwarf-2"] = 1, ["Skyborne-2"] = 0.86, ["NightElf-3"] = 0.82 }
local FORM_SCALES = { [5] = 1.70, [8] = 1.70 } -- bear, dire bear: off the recordings till the sweep's run in it
local SWAP_WAIT = 0.4 -- seconds: the longest the old form's factor is kept without the model's event
local lastForm -- (the form at the last plain read: kept if a read comes back secret)
local function FormNow()
	if not GetShapeshiftFormID then return nil end
	local ok, form = pcall(function()
		local id = GetShapeshiftFormID()
		if id == nil then return false end
		return id + 0 == id and id -- (a secret one errors here: the last one's kept)
	end)
	if ok then lastForm = form or nil end
	return lastForm
end
-- The form whose model is on screen.
-- (ns.shoulderSwap: knobs for ShoulderCamTest.lua's "forms" run, which tries
-- other timings to find the one with the least bump: lead = the offset goes
-- in this long after the form's change on the way INTO a form, not at the
-- model's; boost = into a form it's pushed this share past the new offset for
-- boostFor seconds, to hurry the game's ease.
-- The first run (19:11 that day, the view's sideways move read off a fence
-- post, in 945ths of the screen's width): the game alone 1 either way; at
-- the model's change 11 one way for 8 frames going in, 4 coming out; 0.03 s
-- after the form's change (a frame or two ahead of the model) 15 the other
-- way; 50% past for 0.06 s cut the 11 short after 2 frames, then threw it 19
-- the other way, and coming out made 4 into 11. The up and down move, 12 of
-- 397, is the game's own: the same with the offset at 0.)
-- The second run (21:04, six small pushes): as built 8-9 for some 9 frames;
-- 35% past for 0.035 s and 50% past for 0.02 s both 7 for 2 frames, then
-- level, with nothing past the other way; 25% for 0.05 s and 50% for 0.035 s
-- went 5 and 7 past. Out of a form the pushes changed nothing (4-5 for 6
-- frames, as before). So SWAP_PUSH: into a form the offset's pushed that
-- share past for SWAP_PUSH_FOR. Those first 2 frames are the model already
-- changed with our offset not yet in, and no earlier write helps (above).
local SWAP_PUSH, SWAP_PUSH_FOR = 0.35, 0.035
local shownKnown, shownForm, swapBy, swapLed
local lastYards, boostFrom, boostUntil, boostBy = 0, nil, nil, nil -- (yards at the last frame; a push's start, end and share)
local function Swapped()
	if shownForm == nil then return end
	local knobs = ns.shoulderSwap
	boostBy = knobs and knobs.boost or SWAP_PUSH
	boostFrom, boostUntil = lastYards, GetTime() + (knobs and knobs.boostFor or SWAP_PUSH_FOR)
end
local function ModelForm()
	local form = FormNow()
	if not shownKnown then shownKnown, shownForm = true, form end
	if form == shownForm then
		swapBy = nil
	else
		if not swapBy then
			local knobs = ns.shoulderSwap
			local lead = knobs and shownForm == nil and knobs.lead or nil
			swapBy, swapLed = GetTime() + (lead or SWAP_WAIT), lead ~= nil
			ns.Log("shoulder", ("form: %s -> %s, waiting for %s"):format(tostring(shownForm), tostring(form),
				lead and ("%.2f s"):format(lead) or "the model"))
		elseif GetTime() >= swapBy then
			ns.Log("shoulder", swapLed and ("form: going by form %s now"):format(tostring(form))
				or ("form: no model event in %.1f s, going by form %s"):format(SWAP_WAIT, tostring(form)))
			shownForm, swapBy = form, nil
			Swapped()
		end
	end
	return shownForm
end
local function ModelSwapped()
	local was, now = shownForm, FormNow()
	shownKnown, shownForm, swapBy = true, now, nil
	if was ~= now then Swapped() end
	ns.Log("shoulder", ("model changed: form %s (was %s)"):format(tostring(shownForm), tostring(was)))
end
function ns.ShoulderModelKey()
	local _, race = UnitRace("player")
	local foot = ("%s-%s"):format(tostring(race), tostring(UnitSex("player")))
	local form = ModelForm()
	return form and ("%s-form%d"):format(foot, form) or foot, form, foot
end
function ns.ShoulderModelScale()
	local key, form, foot = ns.ShoulderModelKey()
	local scales = ns.db and ns.db.shoulderCamScales
	local saved = scales and scales[key]
	if type(saved) == "number" and saved > 0.2 then return saved, "measured here" end
	if MEASURED_SCALES[key] then return MEASURED_SCALES[key], "built in" end
	if form then
		if FORM_SCALES[form] then return FORM_SCALES[form], "estimated for this form" end
		saved = scales and scales[foot]
		if type(saved) == "number" and saved > 0.2 then return saved, "on-foot one: form not measured" end
		if MEASURED_SCALES[foot] then return MEASURED_SCALES[foot], "on-foot one: form not measured" end
	end
	return 1, "not measured"
end

local function SpotYards()
	local distance = GetCameraZoom and GetCameraZoom() or 8
	local yards = (ns.db.shoulderCamSpot or 0.2) * distance * ns.ShoulderViewWidth() / ns.ShoulderModelScale()
	local k = math.min(1, math.max(0, (distance - SPOT_EASE_FROM) / (SPOT_EASE_TO - SPOT_EASE_FROM)))
	yards = math.min(OFFSET_MOST, yards * k * k * (3 - 2 * k))
	-- (Just into a form: past the new offset for a moment, SWAP_PUSH.)
	if boostUntil then
		if GetTime() < boostUntil then
			return math.max(0, math.min(OFFSET_MOST, yards + boostBy * (yards - boostFrom)))
		end
		boostUntil = nil
	end
	lastYards = yards
	return yards
end

local function ShoulderValue(again)
	if not again then paused = PauseReason() end
	if paused then
		return "0"
	end
	local yards = SpotYards()
	return ("%.2f"):format(ns.db.shoulderCamSide == "left" and -yards or yards)
end

-- (The offset's following your zoom, and quiet ones (the talk turn's steps):
-- logged in full only to the detail log.)
local function Write(yours, cvar, value, quiet)
	local now = GetCVar(cvar)
	if now ~= nil and not Same(now, value) then
		if yours[cvar] == nil then
			yours[cvar] = now
		end
		local text = ("Shoulder Cam: %s %s -> %s"):format(cvar, now, value)
		if quiet or cvar == "test_cameraOverShoulder" and tonumber(now) ~= 0 and tonumber(value) ~= 0 then
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

-- Turn to who you talk to (shoulderCamTalkTurn). The game's own interact
-- focus (test_cameraTargetFocusInteract...) turns the camera to whoever you
-- talk to, but in about 0.2 s, a snap, and nothing sets its speed (the "talk"
-- map run, 2026-11-11, Tools/shoulder-test-plan.md). Its strengths are a
-- straight share of the turn, and it follows them while the window's open
-- (the "ramp" run): so the focus stays on with them at 0, and as a window
-- opens they're stepped up to the game's own (talk.yaw, talk.pitch) over
-- shoulderCamTalkTime seconds, eased. While one of Cinematic's cameras holds
-- the view (the quest or chat camera) they're stepped back down over the same
-- time, and up again once it's done. The way back as the window closes is
-- still the game's 0.2 s: closed, the focus has no one to turn to. They go
-- back to 0 talk.grace after the last window closes (from gossip to a quest's
-- text, one window closes before the next opens). Its own Show in row off
-- (shoulder:cam) turns it off too; mounted, indoors and the rest don't.
local talk = {
	enable = "test_cameraTargetFocusInteractEnable",
	yawCVar = "test_cameraTargetFocusInteractStrengthYaw",
	pitchCVar = "test_cameraTargetFocusInteractStrengthPitch",
	yaw = 1, pitch = 0.75, -- (the game's defaults)
	grace = 0.6,
	open = { "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "MERCHANT_SHOW",
		"TRAINER_SHOW", "BANKFRAME_OPENED", "TAXIMAP_OPENED", "AUCTION_HOUSE_SHOW", "MAIL_SHOW",
		"GUILDBANKFRAME_OPENED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" },
	close = { "GOSSIP_CLOSED", "QUEST_FINISHED", "MERCHANT_CLOSED", "TRAINER_CLOSED", "BANKFRAME_CLOSED",
		"TAXIMAP_CLOSED", "AUCTION_HOUSE_CLOSED", "MAIL_CLOSED", "GUILDBANKFRAME_CLOSED",
		"PLAYER_INTERACTION_MANAGER_FRAME_HIDE" },
	on = false, closedAt = nil, share = 0, -- (a window open; when the last closed; how far the turn is, 0-1)
}

local function TalkOn()
	return ns.Setting("shoulderCam") and ns.db.shoulderCamTalkTurn and paused ~= "show in"
end

local function SetTalkShare(yours, share)
	local k = share * share * (3 - 2 * share)
	Write(yours, talk.yawCVar, ("%.3f"):format(k * talk.yaw), true)
	Write(yours, talk.pitchCVar, ("%.3f"):format(k * talk.pitch), true)
end

-- Yours back for these (the rest of the Shoulder Cam staying on).
local function GiveBack(yours, ...)
	for i = 1, select("#", ...) do
		local cvar = select(i, ...)
		if yours[cvar] ~= nil then
			if not Same(GetCVar(cvar), yours[cvar]) then
				ns.Log("cvar", ("Shoulder Cam: %s back to %s"):format(cvar, yours[cvar]))
				SetCVar(cvar, yours[cvar])
			end
			yours[cvar] = nil
		end
	end
end

-- Every frame while the Shoulder Cam's on.
local function TalkTick(elapsed)
	local yours = ns.db and ns.db.shoulderCamYours
	if not (yours and TalkOn()) or ns.shoulderTestHold or (ns.DialogueUICameraOn and ns.DialogueUICameraOn()) then
		return
	end
	if talk.on and talk.closedAt and GetTime() - talk.closedAt >= talk.grace then
		talk.on, talk.closedAt = false, nil
	end
	if not talk.on then
		talk.share = 0
	else
		local step = elapsed / math.max(0.1, ns.db.shoulderCamTalkTime or 1.5)
		local holder = ns.CameraHolder and ns.CameraHolder("talk")
		if holder and holder ~= "you" then
			talk.share = math.max(0, talk.share - step)
		else
			talk.share = math.min(1, talk.share + step)
		end
	end
	SetTalkShare(yours, talk.share)
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
			-- (The strengths at 0 before the focus goes on, so it can't snap.)
			if TalkOn() then
				SetTalkShare(yours, talk.share)
				Write(yours, talk.enable, "1")
			else
				talk.share = 0
				GiveBack(yours, talk.enable, talk.yawCVar, talk.pitchCVar)
			end
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
	TalkTick(elapsed)
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

-- With you as your own target the game puts you back in the middle by itself,
-- the offset setting untouched (2026-11-11, Forever: the log kept 2.02 while a
-- recording showed you ease to the middle over ~0.5 s): the frames go with you.
local function YouAreTarget()
	return UnitIsUnit and ns.Flag(UnitIsUnit("target", "player")) or false
end

local function TargetShift()
	local db = ns.db
	if not (db and ns.Setting("shoulderCam") and db.shoulderCamFrames) then return 0 end
	if YouAreTarget() then return 0 end
	local yards = tonumber(GetCVar("test_cameraOverShoulder")) or 0
	if yards == 0 then return 0 end
	local distance = math.max(FOLLOW_MIN_ZOOM, GetCameraZoom and GetCameraZoom() or 5)
	local half = UIParent:GetWidth() / 2
	local shift = -yards * ns.ShoulderModelScale() / (distance * ns.ShoulderViewWidth()) * half
		* (db.shoulderCamFramesStrength or 1)
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
		side = db and db.shoulderCamSide, spot = db and db.shoulderCamSpot, model = ns.ShoulderModelKey(),
		scale = (ns.ShoulderModelScale()), scaleFrom = select(2, ns.ShoulderModelScale()),
		follow = db and db.shoulderCamFrames, followShift = followShift, followTarget = TargetShift(),
		youTarget = YouAreTarget(),
		followed = (function()
			local names = {}
			for frame in pairs(followed) do names[#names + 1] = frame:GetName() or "?" end
			return #names > 0 and table.concat(names, ", ") or "none"
		end)(),
		paused = db and PauseReason() or "no", always = db and db.shoulderCamAlways, key = GetBindingKey(SWAP_ACTION) or "none",
		talkTurn = db and db.shoulderCamTalkTurn, talking = talk.on, talkShare = talk.share,
		focus = GetCVar(talk.enable), focusYaw = GetCVar(talk.yawCVar), focusPitch = GetCVar(talk.pitchCVar),
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
events:RegisterEvent("PLAYER_TARGET_CHANGED")
-- (Going in or out: at once, not at the next poll.)
pcall(events.RegisterEvent, events, "ZONE_CHANGED_INDOORS")
pcall(events.RegisterEvent, events, "ZONE_CHANGED")
-- (Into or out of a form: the game moves you at once, so the new offset goes
-- in at once too, not at the next poll.)
pcall(events.RegisterEvent, events, "UPDATE_SHAPESHIFT_FORM")
pcall(events.RegisterUnitEvent, events, "UNIT_MODEL_CHANGED", "player")
-- (A window open with an NPC, or something to use: the talk turn.)
local TALK_EVENT = {}
for _, event in ipairs(talk.open) do
	if pcall(events.RegisterEvent, events, event) then TALK_EVENT[event] = "open" end
end
for _, event in ipairs(talk.close) do
	if pcall(events.RegisterEvent, events, event) then TALK_EVENT[event] = "close" end
end
events:SetScript("OnEvent", function(_, event)
	if TALK_EVENT[event] == "open" then
		if not talk.on then ns.LogDetail("cvar", ("Shoulder Cam: talk turn starts (%s)"):format(event)) end
		talk.on, talk.closedAt = true, nil
	elseif TALK_EVENT[event] == "close" then
		if talk.on and not talk.closedAt then talk.closedAt = GetTime() end
	elseif event == "UNIT_MODEL_CHANGED" then
		ModelSwapped()
		ns.ApplyShoulderCam()
	elseif event == "PLAYER_TARGET_CHANGED" then
		-- (Yourself targeted or not: the frames glide to the middle or back.)
		if UpdateFollow then UpdateFollow() end
	else
		if event == "PLAYER_ENTERING_WORLD" then talk.on, talk.closedAt = false, nil end
		ns.ApplyShoulderCam()
	end
end)

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

	stack:Header(content, L["Talking"])
	kit.GreyUnless(stack:Add(kit.Check(content, "shoulderCamTalkTurn", L["Turn to who you talk to"],
		L["As you talk to an NPC (or open a vendor, bank, flight master or mailbox), the camera turns " ..
		"slowly to bring them toward the middle of the screen, and goes back as the window closes. It " ..
		"steps aside while Cinematic's quest or chat camera moves the view."], ns.ApplyShoulderCam), "check"), IfOn)
	local talkTime = stack:Add(kit.Slider(content, "shoulderCamTalkTime", L["Turn takes"], 0.5, 4, 0.5,
		L["%.1f sec"]), "slider")
	kit.Tooltip(talkTime, L["How long the turn toward them takes. The way back, as the window closes, is " ..
		"the game's own and always quick."])
	kit.GreyUnless(talkTime, function() return ns.Setting("shoulderCam") and ns.GetDB().shoulderCamTalkTurn end)

	stack:Header(content, L["Pause"])
	kit.GreyUnless(stack:Add(kit.Check(content, "shoulderCamNotMounted", L["Not while mounted"],
		L["On a mount the camera stays straight behind you: a big mount's head fills the shot from " ..
		"the side."]), "check"), IfOn)
	kit.GreyUnless(stack:Add(kit.Check(content, "shoulderCamNotIndoors", L["Not indoors"],
		L["Inside buildings and caves the camera goes back behind you, and comes back out over your " ..
		"shoulder as you step outside. Near walls the game pushes the camera in, and with it off to " ..
		"the side it jerks."]), "check"), IfOn)
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
