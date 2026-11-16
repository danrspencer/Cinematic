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
-- Keep Character Centered and the motion sickness option go back to yours at
-- every logout and reload, and off again as the next session starts
-- (GiveBackForLogout), so Cinematic not loading again never leaves them off.
--
-- It's a held setting, not a camera: it doesn't move the view, so it doesn't
-- claim the camera lock. It goes to 0 (paused) where its Show in row's off
-- (indoors, in an instance or mounted to start with: ROW_KEY's rule) and while one of Cinematic's cameras that frame you
-- runs, unless its tick on the Cameras tab allows it (shoulderCamAllow<Cam>,
-- ALLOW_OF below: all off to start with): the standing-still ones (cozy,
-- vista, fish, AFK, teleport), the flight camera and its fly-bys, the death
-- camera, and your own, whose shots were built around you in the middle;
-- and wherever its Show in row (shoulder:cam) has it off. The quest cam and
-- Chat Cam keep it: an over-the-shoulder dialogue shot is the look they're
-- after. (Allowed, a turn round you keeps you on your spot: the offset is
-- across the camera's own view, so only their zooms move you, and the
-- offset follows those. A flight's mount scales the offset as a mount does,
-- not measured yet: the "cams" sim session.)
local _, ns = ...
local L = ns.L

-- Soft release 2026-11-13 to 2026-11-15: locked in the player copy, page and
-- all, till a tester typed /cine testshoulder. Everyone's since; kept as a
-- function for the places that asked.
function ns.ShoulderCamUnlocked()
	return true
end

-- On, and not standing aside for another addon that owns the shoulder offset
-- (DynamicCam writes it with every situation change: Support/DynamicCam.lua).
-- (demo: the welcome window's See it first test running, ns.ShoulderCamDemo
-- below: on for it with the setting off, nothing of yours changed.)
local demo
local function ShoulderOn()
	if not ns.ShoulderCamUnlocked() then return false end
	if ns.FeatureYieldedTo and ns.FeatureYieldedTo("shoulderCam") then return false end
	return demo ~= nil or ns.Setting("shoulderCam")
end

local POLL = 0.2 -- seconds between checks for a pause (mounting, a camera starting)

-- Where: its Show in row. Off there, it's paused (back behind you) as any
-- other pause. Its rule to start with: not on a mount (a big mount's head
-- fills the shot from the side) and not indoors (walls push the camera in,
-- and off to the side it jerks: DynamicCam's help says so too). Those were
-- two Pause boxes till 2026-11-13 (shoulderCamNotMounted, NotIndoors): moved
-- into the rule once (MovePauseBoxes).
local ROW_KEY = "shoulder:cam"
ns.CINE_SHOW_SETTING[ROW_KEY] = "shoulderCamAlways"
ns.RULE_DEFAULTS[ROW_KEY] = "not indoors and not instance and not mounted"
local function MovePauseBoxes(db)
	if db.shoulderPauseMoved then return end
	db.shoulderPauseMoved = true
	local mounted, indoors = db.shoulderCamNotMounted ~= false, db.shoulderCamNotIndoors ~= false
	db.shoulderCamNotMounted, db.shoulderCamNotIndoors = nil, nil
	-- (Always ticked, as it started: the boxes were all there was. Ticks of
	-- your own: kept as they are.)
	if db.shoulderCamAlways == false then return end
	db.shoulderCamAlways = false
	db.frameRules = db.frameRules or {}
	db.frameRules[ROW_KEY] = (mounted and indoors and "not mounted and not indoors") or (mounted and "not mounted")
		or (indoors and "not indoors") or "always"
end
-- Whether its row turns it off on a mount here (as if you were mounted): a
-- mount being cast eases it out early then.
function ns.ShoulderPausedMounted()
	if ns.db.shoulderCamAlways or not (ns.RuleFactsNow and ns.RuleShows) then return false end
	local ok, off = pcall(function()
		local facts = ns.RuleFactsNow()
		local was = facts.mounted
		facts.mounted = true
		local shows = ns.RuleShows(ROW_KEY, facts)
		facts.mounted = was
		return shows == false
	end)
	return ok and off or false
end

-- Each of our cameras (its key as ns.ScriptStandIn gives it, "yours" for any
-- other script or shot) and the setting that keeps the Shoulder Cam on through
-- it. The quest cam and Chat Cam always do; the RP walk and auto-run cameras
-- play while you move, never a pause.
local ALLOW_OF = { vista = "shoulderCamAllowVista", fish = "shoulderCamAllowFish", cozy = "shoulderCamAllowCozy",
	idle = "shoulderCamAllowAFK", tele = "shoulderCamAllowTele", flight = "shoulderCamAllowFlight",
	death = "shoulderCamAllowDeath", yours = "shoulderCamAllowYours",
	-- (Always kept till 2026-11-15; a tick each since, walk and run on: user.)
	walk = "shoulderCamAllowWalk", run = "shoulderCamAllowRun", quest = "shoulderCamAllowQuest",
	chatcam = "shoulderCamAllowChat" }
local PLAYING_CAMS = { walk = true, run = true, quest = true, chatcam = true } -- (by ns.activeCam: PauseReason)
local function CameraKey(camera)
	if camera == "afk" then return "idle" end
	if camera == "script:flyby" then return "flight" end -- (a fly-by of its own: the flight camera's)
	local key = ns.ScriptStandIn and ns.ScriptStandIn(camera) or ALLOW_OF[camera] and camera
	return key or "yours"
end

local function Same(a, b)
	return a == b or (tonumber(a) ~= nil and tonumber(a) == tonumber(b))
end

-- Why it's paused now, or nil.
-- With you as your own target the game puts you back in the middle by itself,
-- the offset setting untouched (2026-11-11, Forever: the log kept 2.02 while a
-- recording showed you ease to the middle over ~0.5 s): the frames go with you.
-- It's not a setting: nothing of the camera's changes, and the offset's not
-- used at all then, even doubled (the selftarget run, 2026-11-15). So it's a
-- pause of ours ("yourself"): the offset eased out unseen, and as the target
-- goes, eased back in over shoulderCamSelfTime instead of the game's snap.
local function YouAreTarget()
	return UnitIsUnit and ns.Flag(UnitIsUnit("target", "player")) or false
end

local function PauseReason()
	local db = ns.db
	-- (Forever's gamepad UI holds Keep Character Centered on inside the game:
	-- written 0, it reads 1 at once, no code of anyone's writing it, and no
	-- setting of the 105 about the gamepad, centering or following changes
	-- that (padscan, 2026-11-13). With it on, the offset does nothing.)
	if not ns.isRetail and ns.IsGamePadOn and ns.IsGamePadOn() then
		return "gamepad"
	end
	-- (The test: wherever you are, till it eases back out at its end.)
	if demo then
		return demo.ending and "demo" or nil
	end
	MovePauseBoxes(db)
	if not db.shoulderCamAlways then
		local ok, here = pcall(ns.RowOnNow, ROW_KEY, false, true)
		if not (ok and here) then
			-- (ns.Flag: either can be secret on Forever. The likely why, for the log.)
			if IsMounted and ns.Flag(IsMounted()) then return "mounted" end
			if IsIndoors and ns.Flag(IsIndoors()) then return "indoors" end
			return "show in"
		end
	end
	-- (Casting a mount its row's off on: already easing out, so you're behind
	-- it by the time the mount's size comes in (it swings the offset out 2-5
	-- times: the "mounts" run). A cast that's stopped puts it back.)
	if C_MountJournal and C_MountJournal.GetMountFromSpell then
		local okCast, spell = pcall(function() return select(9, UnitCastingInfo("player")) end)
		local okMount, mount = pcall(C_MountJournal.GetMountFromSpell, okCast and spell or nil)
		if okCast and spell and okMount and ns.Flag(mount ~= nil) and ns.ShoulderPausedMounted() then
			return "mounting"
		end
	end
	if not db.shoulderCamAllowFlight and UnitOnTaxi and ns.Flag(UnitOnTaxi("player")) then
		return "flight"
	end
	if not db.shoulderCamAllowDeath and UnitIsDead and ns.Flag(UnitIsDead("player")) then
		return "dead"
	end
	local camera = ns.ActiveEvent and select(2, ns.ActiveEvent())
	if camera then
		local key = CameraKey(camera)
		if not db[ALLOW_OF[key] or ALLOW_OF.yours] then
			return camera
		end
	end
	-- (The walk, auto-run, quest and chat cameras aren't events: the camera
	-- playing now, ns.activeCam ("quest", or "script:quest" as its script).
	-- Always kept till 2026-11-15, nothing asked; the today run's quest step
	-- never paused.)
	local playing = ns.activeCam
	local playingKey = type(playing) == "string" and CameraKey(playing)
	if PLAYING_CAMS[playingKey] and not db[ALLOW_OF[playingKey]] then
		return playing
	end
	if YouAreTarget() then
		return "yourself"
	end
end

-- The offset to write: yards, negative for the left shoulder; "0" paused.
local SPOT_EASE_FROM, SPOT_EASE_TO = 1, 4 -- yards: in the middle at 1, eased out to your spot by 4
local OFFSET_MOST = 15 -- yards (DynamicCam's range too)
-- Near walls the game pulls the camera in, out of our sight (the walls run,
-- 2026-11-12: GetCameraZoom read 15.0 all through, no setting stops it), and
-- an offset sized for the full distance then threw you far to the side,
-- behind a tree or off screen (3.3 yards at 15 away). So the offset stops
-- growing: zoomed far out you sit nearer the middle than your spot, and a
-- pull-in throws you less far (right up close it still can).
-- (Counted in how far it moves you, a Dwarf's yards, so over the model's size
-- factor: capped in plain offset yards, a Night Elf held at 1.50 sat on ~12%
-- while her cat, not capped, sat on her 20% spot: each shift jumped between
-- them (the forms run, 2026-11-14).)
-- Held as a distance since 2026-11-15, not as yards of offset: the spot's
-- kept out to SPOT_HOLD yards away, the offset held past that. 1.5 yards
-- capped every spot alike, so on a wide screen (more yards to the same share)
-- past about 14% at zoom 8 the slider did nothing ("doesn't work past 20%",
-- user). SPOT_HOLD is where 1.5 yards was the cap for 20% on a 16:9 screen,
-- so that's as before; a wall's pull-in throws you the same share past your
-- spot whatever it is.
local SPOT_HOLD = 7.5 -- yards away
ns.SHOULDER_SPOT_HOLD = SPOT_HOLD
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
-- (The cat, the zoomcurve run 2026-11-12, standing still with the elf's
-- offset held: the elf on 10.8% of the way to the edge, the cat on 20.3%,
-- so 0.82 x 20.3 / 10.8 = 1.55.)
-- (Mounts change it too: not measured yet.)
-- (Human-3: the offset sweep, Forever, 2026-11-13. Skyborne-2 and -3, Gnome-2 and -3, NightElf-2, Dwarf-3, Human-2, Orc-2 and -3, Scourge-2 and -3, Tauren-2 and -3, Troll-2 and -3: the calibrate run, spreads 0.025 or less. NightElf-3 again, 2026-11-14: 0.88, not the 0.82 read off a recording.)
local MEASURED_SCALES = { ["Dwarf-2"] = 1, ["Dwarf-3"] = 0.82, ["Skyborne-2"] = 0.88, ["Skyborne-3"] = 0.85, ["Gnome-2"] = 0.90, ["Human-2"] = 0.94, ["Gnome-3"] = 0.84, ["NightElf-2"] = 1.00, ["NightElf-3"] = 0.88, ["Human-3"] = 0.81,
	["Orc-2"] = 1.23, ["Orc-3"] = 0.96, ["Scourge-2"] = 0.99, ["Scourge-3"] = 0.90, ["Tauren-2"] = 1.68, ["Tauren-3"] = 1.27,
	["Troll-2"] = 1.22, ["Troll-3"] = 0.95,
	-- (Druid forms, per race, both sexes alike (ScaleOf): the calibrate run
	-- in each, 2026-11-14, a Night Elf female and then male.)
	["NightElf-form1"] = 1.63, ["NightElf-form5"] = 1.76,
	-- (Form 4: 2.32 in five runs, 2.29 at 8 yards and 2.35 at 12, just over
	-- the spread a run calls good; one run said 2.20, the odd one out.)
	["NightElf-form4"] = 2.32 }
local BORROW_FORMS_FROM = "NightElf" -- (a form not measured for your race: this race's, ScaleOf)
-- bear, cat, dire bear: off the recordings till the sweep's run in them
local FORM_SCALES = { [5] = 1.70, [1] = 1.55, [8] = 1.70 }
-- Forms that keep your own model (warrior stances 17-19, shadowform 28,
-- stealth 30): read as on foot. (A Human warrior's calibrate run came back
-- "Human-2-form17", 2026-11-13.)
local SAME_MODEL = { [17] = true, [18] = true, [19] = true, [28] = true, [30] = true }
local SWAP_WAIT = 0.4 -- seconds: the longest the old form's factor is kept without the model's event
local lastForm -- (the form at the last plain read: kept if a read comes back secret)
local function FormNow()
	if not GetShapeshiftFormID then return nil end
	local ok, form = pcall(function()
		local id = GetShapeshiftFormID()
		if id == nil then return false end
		if id + 0 ~= id then return nil end -- (a secret one errors here: the last one's kept)
		return not SAME_MODEL[id] and id
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
-- (Every form since 2026-11-14: the cat's 15% each way, in and out. The
-- push is a share of the offset's change, so it goes with each form's size
-- on its own; the bear's 35% was tuned before the cap counted how far you're
-- moved, the old jump it made up for gone.)
local SWAP_PUSH, SWAP_PUSH_FOR = 0.15, 0.035
local SWAP_PUSH_OUT = 0.15
-- (Per form, where measured: the shift run, a Night Elf's cat, 2026-11-14,
-- with the cap counted in how far you're moved. In, from where you stood:
-- 35% went 1 point out as the model came, then 1-1.4 in as the push landed;
-- no push 1 out, creeping back; 15% 0.7 out and 0.2-0.3 in, the least. The
-- first frame out is the model come before any offset can follow it.)
local SWAP_PUSH_OF = { [1] = 0.15 }
local shownKnown, shownForm, swapBy, swapLed
local lastYards, boostFrom, boostUntil, boostBy = 0, nil, nil, nil -- (yards at the last frame; a push's start, end and share)
local steadyYards = 0 -- (the offset without a push: the frames that follow you go by it, TargetShift)
local pushOver = 0 -- (till when they do: the push's end and a moment more, till the setting's rewritten)
-- (Out of a form (was: the form left): no push unless one's set for that
-- form, SWAP_PUSH_OUT_OF, or the shift run's boostOut.)
-- (The cat, the shift runs, 2026-11-14, from where you stood: no push 0 and
-- -0.6; 15% +0.1 and -0.4, the least; 35% +0.6 and -0.2; 50% +1.1; 35% for
-- twice as long +1.3.)
local SWAP_PUSH_OUT_OF = { [1] = 0.15 }
local function Swapped(was)
	local knobs = ns.shoulderSwap
	if shownForm == nil then
		local by = knobs and knobs.boostOut or SWAP_PUSH_OUT_OF[was] or (was and SWAP_PUSH_OUT)
		if not by or by <= 0 then return end
		boostBy = by
		boostFrom, boostUntil = lastYards, GetTime() + (knobs and knobs.boostOutFor or SWAP_PUSH_FOR)
		pushOver = boostUntil + 0.1
		return
	end
	boostBy = knobs and knobs.boost or SWAP_PUSH_OF[shownForm] or SWAP_PUSH
	boostFrom, boostUntil = lastYards, GetTime() + (knobs and knobs.boostFor or SWAP_PUSH_FOR)
	pushOver = boostUntil + 0.1
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
			local was = shownForm
			shownForm, swapBy = form, nil
			Swapped(was)
		end
	end
	return shownForm
end
local function ModelSwapped()
	local was, now = shownForm, FormNow()
	shownKnown, shownForm, swapBy = true, now, nil
	if was ~= now then Swapped(was) end
	ns.Log("shoulder", ("model changed: form %s (was %s)"):format(tostring(shownForm), tostring(was)))
end
function ns.ShoulderModelKey()
	local _, race = UnitRace("player")
	local foot = ("%s-%s"):format(tostring(race), tostring(UnitSex("player")))
	local form = ModelForm()
	return form and ("%s-form%d"):format(foot, form) or foot, form, foot
end
-- The size factor for a form (nil: on foot), and where it's from.
local function ScaleOf(form, foot)
	local key = form and ("%s-form%d"):format(foot, form) or foot
	local scales = ns.db and ns.db.shoulderCamScales
	local saved = scales and scales[key]
	if type(saved) == "number" and saved > 0.2 then return saved, "measured here" end
	if MEASURED_SCALES[key] then return MEASURED_SCALES[key], "built in" end
	if form then
		-- (A form's one model for both sexes of a race: a Night Elf male's
		-- cat 1.62 and bear 1.76, the female's 1.63 and 1.76, 2026-11-14. So
		-- the table has it once, race-formN.)
		local race = foot:match("^(.-)%-%d+$") or foot
		local both = MEASURED_SCALES[("%s-form%d"):format(race, form)]
		if both then return both, "built in, this race's" end
		-- (Not measured for this race: the Night Elf's, the one race measured
		-- so far, 2026-11-14. Closer than the race's on-foot size (a Troll in
		-- form 4 went by 0.95 for a form near 2.3) while the others wait for
		-- a druid of theirs.)
		local borrowed = MEASURED_SCALES[("%s-form%d"):format(BORROW_FORMS_FROM, form)]
		if borrowed then return borrowed, ("built in, the %s's: not measured for this race"):format(BORROW_FORMS_FROM) end
		if FORM_SCALES[form] then return FORM_SCALES[form], "estimated for this form" end
		saved = scales and scales[foot]
		if type(saved) == "number" and saved > 0.2 then return saved, "on-foot one: form not measured" end
		if MEASURED_SCALES[foot] then return MEASURED_SCALES[foot], "on-foot one: form not measured" end
	end
	return 1, "not measured"
end
-- Shifting, the model not changed yet: the old model's factor, or with an
-- early share (ns.shoulderSwap.early, the shift run's timings) part of the
-- way to the new one's offset already, the game's own ease given a head
-- start. (The offset goes as 1 / the factor, its cap too: so the share's of
-- the offset, 1/f = (1 - share)/old + share/new.)
-- (None for now. The cat, the shift runs, 2026-11-14, with its 15% push,
-- from where you stood: none early about +0.5 then -0.5 every time; a third
-- or half early +0.3 to +0.4 and -0.2 at most while the game swapped the
-- model 0.03-0.05 s after the form, but -0.9 to -1.4 at 0.06-0.07 s (the elf
-- slid in before the cat showed). That wait varies by session (0.03-0.10 s
-- that day), so a share written up front can't fit it.)
local SWAP_EARLY_OF = {} -- (form -> share, into it)
function ns.ShoulderModelScale()
	local _, form, foot = ns.ShoulderModelKey()
	local scale, from = ScaleOf(form, foot)
	if swapBy then
		local knobs = ns.shoulderSwap
		local coming = FormNow()
		local share = knobs and knobs.early or SWAP_EARLY_OF[coming]
		-- (Into a form only: out, the game says "no form" ~0.17 s before the
		-- model's back, and a third written then slid you from 12.5% out to
		-- 15.9% of the screen first: the shift run, 2026-11-14.)
		if share and share > 0 and coming then
			local new = ScaleOf(coming, foot)
			return 1 / ((1 - share) / scale + share / new), ("%s, %d%% of the way to the new model's"):format(from, share * 100)
		end
	end
	return scale, from
end

-- The camera's distance as it is on screen. GetCameraZoom gives where a zoom
-- is going, at once, and the game glides the camera there (the zoomcurve run,
-- 2026-11-12, offset held: 2 yards in or out ~90% done in 0.4-0.5 s, about
-- an ease of 0.19 s), while a written offset settles in about 0.1 s. An
-- offset for the zoom's end written at once ran ahead of the camera: you went
-- sideways fast, stopped, then the zoom caught up ("staircase like"). So the
-- offset follows this, eased toward the zoom's end by ZOOM_EASE (the glide's
-- 0.19 less the offset's own 0.04). Started fresh, or after a pause, it's the
-- zoom's end at once.
local ZOOM_EASE = 0.15
local seenZoom, seenAt
local function SeenZoom()
	local target = GetCameraZoom and GetCameraZoom() or 8
	local now = GetTime()
	if not seenZoom or now - seenAt > 0.5 then
		seenZoom = target
	else
		seenZoom = target + (seenZoom - target) * math.exp(-(now - seenAt) / ZOOM_EASE)
	end
	seenAt = now
	return seenZoom
end

local function SpotYards()
	local distance = SeenZoom()
	local scale = ns.ShoulderModelScale()
	local yards = (ns.db.shoulderCamSpot or 0.2) * math.min(distance, SPOT_HOLD) * ns.ShoulderViewWidth() / scale
	local k = math.min(1, math.max(0, (distance - SPOT_EASE_FROM) / (SPOT_EASE_TO - SPOT_EASE_FROM)))
	yards = math.min(OFFSET_MOST, yards * k * k * (3 - 2 * k))
	steadyYards = yards
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

-- In and out gently: a pause (a mount, indoors, our cameras) and its end used
-- to write the whole offset at once, which the game crosses in about 0.3 s:
-- "so fast and jarring" (2026-11-13). So the offset's taken in and out over
-- BLEND_TIME, eased at both ends; turned on fresh, it eases in too.
-- One of our cameras' pauses: the seconds typed in its box on the Cameras
-- tab instead, out as it starts and back in as it ends (empty: BLEND_TIME).
local BLEND_TIME = 0.9
ns.SHOULDER_BLEND_TIME = BLEND_TIME
local blend, blendAt = 0, nil
local blendTime = BLEND_TIME
-- (Pauses that aren't one of our cameras: PauseReason's own words.)
local NOT_A_CAMERA = { gamepad = true, mounted = true, indoors = true, ["show in"] = true, mounting = true,
	yourself = true, demo = true }
local function TimeKey(key)
	return ALLOW_OF[key] and (ALLOW_OF[key]:gsub("Allow", "Time"))
end
ns.ShoulderTimeKey = TimeKey
local function PauseTime(reason)
	if reason == "yourself" then
		return math.max(0, tonumber(ns.db.shoulderCamSelfTime) or 1)
	end
	local key = reason == "dead" and "death" or reason == "flight" and "flight"
		or not NOT_A_CAMERA[reason] and CameraKey(reason)
	local seconds = key and tonumber(ns.db[TimeKey(key) or ""])
	if seconds and seconds >= 0 then return seconds end
	-- (Indoors, mounted, Show in, the gamepad: the slider's time, shoulderCamPauseTime.)
	if NOT_A_CAMERA[reason] then
		return math.max(0, tonumber(ns.db.shoulderCamPauseTime) or BLEND_TIME)
	end
	return BLEND_TIME
end
local function Blend(toward)
	local now = GetTime()
	local step = blendAt and math.min(0.25, now - blendAt) / math.max(0.01, blendTime) or 0
	-- (Resting all the way out, it's not asked every frame: no clock kept, so
	-- the way back in starts from its first frame, not with a jump.)
	blendAt = not (blend <= 0 and toward <= 0) and now or nil
	blend = toward > blend and math.min(toward, blend + step) or math.max(toward, blend - step)
	return blend * blend * (3 - 2 * blend)
end

-- (How far in the offset is, 0 to 1: the sim skips the ease's samples.)
function ns.ShoulderBlendShare() return blend end

-- Swapping shoulders: the side as -1 (left) to 1 (right), crossing over
-- shoulderCamSwapTime seconds, eased at both ends. At 0 it's the new side at
-- once, and the game's own ease takes it across (about 0.3 s). Started
-- fresh, or after a while not asked (paused all the way out), it's the side
-- at once.
local sideNow, sideAt
local function SideFactor()
	local want = ((demo and demo.side) or ns.db.shoulderCamSide) == "left" and -1 or 1
	local now = GetTime()
	local time = tonumber(ns.db.shoulderCamSwapTime) or 1.5
	if not sideNow or time <= 0 or not sideAt or now - sideAt > 0.5 then
		sideNow = want
	else
		local step = (now - sideAt) * 2 / time
		sideNow = want > sideNow and math.min(want, sideNow + step) or math.max(want, sideNow - step)
	end
	sideAt = now
	local p = (sideNow + 1) / 2
	return 2 * p * p * (3 - 2 * p) - 1
end

-- You're moving the camera: a mouse button held on it, or camera input under
-- YOURS_QUIET ago (Core.lua's PLAYER_HOLD).
-- (Your camera always wins: the way back in after the quest cam slid the view
-- sideways under a drag, "my mouse and the addon moving the camera were
-- competing", user 2026-11-15. So it waits where it got to till you let go.)
local YOURS_QUIET = 0.5
local heldForYou -- (the way back in waiting for you, for the log)
local function YouMoveCamera()
	if ns.IsMouseOnCamera and ns.IsMouseOnCamera() then return true end
	local last = ns.GetLastCameraInput and ns.GetLastCameraInput() or -math.huge
	return GetTime() - last < YOURS_QUIET
end

local function ShoulderValue(again)
	if not again then paused = PauseReason() end
	-- (A pause's time is kept as it ends, for the way back in.)
	if paused then
		blendTime = PauseTime(paused)
	elseif blend >= 1 then
		blendTime = BLEND_TIME
	end
	local toward = paused and 0 or 1
	-- (Only the way back in waits: easing out for a pause goes on.)
	local wait = toward > blend and YouMoveCamera()
	if wait ~= (heldForYou or false) then
		heldForYou = wait or nil
		ns.Log("shoulder", wait and ("coming back in waits: you're moving the camera (%d%% in)"):format(blend * 100)
			or (paused and "coming back in stopped: paused again (%d%% in)"
				or "you've let go of the camera: coming back in from %d%%"):format(blend * 100))
	end
	if wait then toward = blend end
	local k = Blend(toward)
	if k <= 0 then
		return "0"
	end
	return ("%.2f"):format(SpotYards() * k * SideFactor())
end

-- Glides (the offset, and quiet ones: the talk and target turns' strengths)
-- are logged as one line once they settle, from where to where over how long,
-- not a line a frame (user, 2026-11-16: they filled 5,000-line logs). Settled
-- = no step for GLIDE_QUIET seconds; any other Shoulder Cam CVar line, and
-- the log being saved, write the open ones first so the order stays right.
local GLIDE_QUIET = 0.3
local glides, glideTicker = {}, nil
local function FlushGlides(all)
	local now, open = GetTime(), false
	for cvar, g in pairs(glides) do
		if all or now - g.last >= GLIDE_QUIET then
			glides[cvar] = nil
			ns.Log("cvar", ("Shoulder Cam: %s %s -> %s over %.2f s (%d steps)"):format(
				cvar, g.from, g.to, g.last - g.start, g.steps))
		else
			open = true
		end
	end
	if not open and glideTicker then
		glideTicker:Cancel()
		glideTicker = nil
	end
end
local function GlideStep(cvar, from, to)
	local now = GetTime()
	local g = glides[cvar]
	if not g then
		g = { from = from, start = now, steps = 0 }
		glides[cvar] = g
	end
	g.to, g.last, g.steps = to, now, g.steps + 1
	if not glideTicker then
		glideTicker = C_Timer.NewTicker(0.1, function() FlushGlides() end)
	end
end
do -- (a glide still going as you log out or /reload)
	local saver = CreateFrame("Frame")
	saver:RegisterEvent("PLAYER_LOGOUT")
	saver:SetScript("OnEvent", function() FlushGlides(true) end)
end

local function Write(yours, cvar, value, quiet)
	local now = GetCVar(cvar)
	if now ~= nil and not Same(now, value) then
		if yours[cvar] == nil then
			yours[cvar] = now
		end
		if quiet or cvar == "test_cameraOverShoulder" then
			GlideStep(cvar, now, value)
		else
			FlushGlides(true)
			ns.Log("cvar", ("Shoulder Cam: %s %s -> %s"):format(cvar, now, value))
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
-- The question answered yes without it: the welcome window's Shoulder Cam
-- card and its See it first test say why on themselves (Welcome.lua).
function ns.ShoulderCamAgree()
	if ns.db then ns.db.shoulderCamNoticed = true end
	if asking then
		if _G.StaticPopup_Hide then _G.StaticPopup_Hide("CINEMATIC_SHOULDER_NOTICE") end
		asking = nil
		-- (Held back for the question: on now.)
		ns.ApplyShoulderCam()
	end
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
-- shoulderCamTalkIn seconds, eased (back down: shoulderCamTalkOut). While one of Cinematic's cameras holds
-- the view (the quest or chat camera) they're held where they are, and glide
-- back as the window closes (stepped down under it till 2026-11-16, so the
-- close had nothing left to turn back: user). The way back as the window closes is
-- the game's 0.2 s, a snap: closed, the focus has no one to turn to, and
-- nothing turns the camera beforehand (the "back" run, 2026-11-12: camera
-- follow didn't move it), so the close is held while they glide back down
-- (ns.ShoulderTalkClose). (A time on them before gliding back with the window
-- still open, shoulderCamTalkHold, removed 2026-11-16: user.) A new
-- window (the quest's text after the gossip) turns to them again. They go
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
	back = false, fullAt = nil, -- (gliding back now; when the turn got all the way there)
	-- A held close waits this long before the glide back starts: going from
	-- one window to the next (a quest greeting to its text, Accept to the next
	-- quest), the panel's close comes first and the next window ~0.1-0.3 s
	-- after. Gliding back at once turned out and in again each time (user,
	-- 2026-11-14: "when you accept 2 quests it snaps out and in").
	swapWait = 0.4, backAt = nil, -- (when a held close's glide back starts)
	-- Accept and Complete end the talk on the game's side (QUEST_FINISHED),
	-- and the game's focus snaps back then, the next quest's window snapping
	-- it in again 0.25 s on (the log and the user, 2026-11-14). A drift back
	-- while you read (8 s) didn't help: Accept came 0.45-0.8 s in, the turn
	-- still 0.8-0.9 there. So those calls are held too (ns.ShoulderTalkClose with
	-- quick: the glide back at once, no swapWait), then they go. Over
	-- NPC turn back takes, as every close (user, 2026-11-16: "when i close the
	-- window i expect it to turn back over 3 seconds"); quickTime (0.5 s)
	-- till then. quickTime's only for walking off now.
	quickTime = 0.5, quick = false, -- (quick: a held Accept, Complete or Decline)
}

-- Seconds the turn toward them takes (shoulderCamTalkIn), and the glide back
-- (shoulderCamTalkOut), each its own slider since 2026-11-14.
local function TalkInTime() return math.max(0.1, ns.db.shoulderCamTalkIn or 3) end
local function TalkOutTime() return math.max(0.1, ns.db.shoulderCamTalkOut or 3) end

-- Turn to NPCs' Show in row (user, 2026-11-16: "turning inside can be a bit
-- much"): where it turns, not indoors or in fights to start with. Read 4 times a second,
-- as Turn to enemy's (rules aren't cheap). Its Always: shoulderCamTalkTurnAlways.
ns.SHOULDER_TALK_ROW = "shoulder:talkturn"
ns.CINE_SHOW_SETTING[ns.SHOULDER_TALK_ROW] = "shoulderCamTalkTurnAlways"
ns.RULE_DEFAULTS[ns.SHOULDER_TALK_ROW] = "not indoors and not combat"
for _, list in ipairs({ "combatShow", "worldShow", "cityShow", "bgShow", "instanceShow", "groupShow" }) do
	ns.LIST_DEFAULTS[list][ns.SHOULDER_TALK_ROW] = true
end
local talkRead = { at = -1, on = true }
local function TalkHere()
	local now = GetTime()
	if now - talkRead.at >= 0.25 then
		talkRead.at = now
		local ok, on = pcall(ns.RowOnNow, ns.SHOULDER_TALK_ROW, ns.db.shoulderCamTalkTurnAlways, true)
		talkRead.on = not ok or on and true or false
	end
	return talkRead.on
end

local function TalkOn()
	return ShoulderOn() and ns.db.shoulderCamTalkTurn and paused ~= "show in" and TalkHere()
end

-- Who the window's with, only a living creature: a mailbox, a wanted poster,
-- a chest (their GUIDs say GameObject, or there's no "npc" at all) and the
-- dead are left alone. (Read as plain values where it can be: anything secret
-- or unreadable counts as a creature, as before.)
local function TalkingToLiving()
	local okExists, exists = pcall(UnitExists, "npc")
	if okExists and not exists and not (issecretvalue and issecretvalue(exists)) then return false, "no one" end
	local okGuid, guid = pcall(function()
		local g = UnitGUID("npc")
		return type(g) == "string" and g:match("^(%a+)") or nil
	end)
	if okGuid and guid and guid ~= "Creature" and guid ~= "Vehicle" and guid ~= "Pet" then
		return false, guid
	end
	local okDead, dead = pcall(UnitIsDeadOrGhost, "npc")
	if okDead and ns.Flag(dead) then return false, "dead" end
	return true
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
				FlushGlides(true)
				ns.Log("cvar", ("Shoulder Cam: %s back to %s"):format(cvar, yours[cvar]))
				SetCVar(cvar, yours[cvar])
			end
			yours[cvar] = nil
		end
	end
end

-- Closing slowly. Closing the panel before the glide back's done still
-- snapped the rest (user, 2026-11-12: "it glides back in .5 seconds"; the
-- game's 0.2 s). So the call that ends the conversation is held back: the
-- conversation stays open while the turn glides back at its own pace, then
-- the held call goes. Walking off ends it on the game's side: that still
-- snaps. A new window meanwhile (another NPC, the vendor after the gossip)
-- drops the held calls (the game's moved on to it; ending it would close the
-- new one). Never in a fight; a timer ends it if the glide can't finish.
-- Each is logged ("shoulder").
-- Only through Cinematic's own quest bubble (QuestTalk.lua calls
-- ns.ShoulderTalkClose for its Goodbye, Accept and Complete). Till
-- 2026-11-14 the game's own CloseGossip, CloseQuest, AcceptQuest and
-- GetQuestReward were replaced to hold them from the game's windows too,
-- which taints every bit of the game's code that calls them (the user
-- chose this over it). The game's windows close at once and snap back.
-- Every NPC window since 2026-11-16 (user: no snap anywhere): held open
-- unseen it'd still take a click (an item sold or banked, a spell bought),
-- so gameEsc.Guard covers it and keeps your bags closed till it goes.
local closing = {
	held = {}, since = nil,
	-- (Which hold a safety timer's for: an old one, its calls dropped as the
	-- next window opened, ended a later hold 0.36 s in, a snap (the log,
	-- 2026-11-14).)
	token = 0,
}

local function CloseNow(why)
	local held = closing.held
	if #held == 0 then return end
	closing.held = {}
	ns.Log("shoulder", ("talk close: ending the conversation now (%s, turn at %.2f, %.2f s held)"):format(why,
		talk.share, GetTime() - (closing.since or GetTime())))
	closing.passing = true
	for _, call in ipairs(held) do
		local ok, err = pcall(call.fn, unpack(call.args, 1, call.n))
		if not ok then ns.Log("shoulder", ("talk close: %s failed: %s"):format(call.label, tostring(err))) end
	end
	closing.passing = nil
end

-- (A talk's end held now, for the camera's glide back: QuestTalk.lua fades
-- its bubble out at once then.)
function ns.ShoulderTalkHeld() return #closing.held > 0 end

-- The quest bubble's end of a talk (QuestTalk.lua): fn(...) now, or held
-- while the turn glides back. label: what it is, for the log; quick: Accept
-- or Complete, the quick glide back.
function ns.ShoulderTalkClose(label, fn, quick, ...)
	if type(fn) ~= "function" then return end
	if closing.passing or ns.shoulderTestHold or not (TalkOn() and talk.on and talk.share > 0.02)
		or InCombatLockdown() then
		return fn(...)
	end
	local held = closing.held
	-- (Accept clicked twice while held: once is enough.)
	for _, call in ipairs(held) do
		if call.label == label then return end
	end
	held[#held + 1] = { fn = fn, args = { ... }, n = select("#", ...), label = label }
	-- (Accept or Complete: the quick glide back, at once.)
	if quick then talk.quick, talk.back, talk.backAt = true, true, nil end
	if #held == 1 then
		closing.since = GetTime()
		if not quick then talk.backAt = GetTime() + talk.swapWait end
		closing.token = closing.token + 1
		local token = closing.token
		ns.Log("shoulder", ("talk close: %s held while the camera glides back (turn at %.2f)"):format(
			label, talk.share))
		local wait = (quick and 0 or talk.swapWait) + TalkOutTime() + 1
		C_Timer.After(wait, function()
			if closing.token == token then CloseNow("timer") end
		end)
	else
		ns.Log("shoulder", ("talk close: %s held too"):format(label))
	end
end

-- Escape in the game's own NPC windows (2026-11-15, no Quest Vision
-- needed): bound to a secure button while one's open and the talk turn is
-- on. Its /cleartarget clears your target (shoulderCamEscTarget; the game's
-- Escape would close the window first), and its PostClick closes the window
-- through the slow glide back (ns.ShoulderTalkClose), fading it out
-- meanwhile. The game's close is only called, never replaced (what tainted,
-- till 2026-11-14). With Cinematic's own dialogue up, Escape's left to it.
-- Every NPC window since 2026-11-16 (user: no snap anywhere), gossip and
-- quest text before (then a vendor too). A held window is kept from clicks
-- (gameEsc.Guard: a cover over it, your bags closed and kept closed), so
-- nothing's bought, sold, banked, sent or flown to while it fades. The
-- game's X, Goodbye and Decline buttons have covers of ours over them
-- (gameEsc.Covers) that do the same, as MultiQuestFix.lua's over Accept.
-- The frame's name, the game's close call (for the log, and the call).
local GAME_TALK = {
	{ "GossipFrame", "CloseGossip", function() (C_GossipInfo and C_GossipInfo.CloseGossip or _G.CloseGossip)() end },
	{ "QuestFrame", "CloseQuest", function() CloseQuest() end },
	{ "MerchantFrame", "CloseMerchant", function() CloseMerchant() end },
	{ "ClassTrainerFrame", "CloseTrainer", function() CloseTrainer() end },
	{ "BankFrame", "CloseBankFrame", function() CloseBankFrame() end },
	{ "GuildBankFrame", "CloseGuildBankFrame", function() CloseGuildBankFrame() end },
	{ "TaxiFrame", "CloseTaxiMap", function() CloseTaxiMap() end },
	{ "FlightMapFrame", "CloseTaxiMap", function() CloseTaxiMap() end },
	{ "MailFrame", "CloseMail", function() CloseMail() end },
	{ "AuctionHouseFrame", "CloseAuctionHouse", function() C_AuctionHouse.CloseAuctionHouse() end },
	{ "AuctionFrame", "CloseAuctionHouse", function() CloseAuctionHouse() end },
	{ "PetStableFrame", "ClosePetStables", function() ClosePetStables() end },
	{ "StableFrame", "ClosePetStables", function() ClosePetStables() end },
}
local gameEsc = CreateFrame("Button", "CinematicShoulderEscapeButton", UIParent, "SecureActionButtonTemplate")
gameEsc:SetAttribute("type", "macro")
gameEsc:SetAttribute("macrotext", "")
gameEsc:RegisterEvent("PLAYER_LOGIN")
gameEsc:RegisterEvent("PLAYER_REGEN_ENABLED")
-- (Right-clicking them again while the close is held: the talk goes on,
-- ns.ShoulderTalkKeep. The window's still open, faded out, so the game
-- opens nothing new, and the close came after: user, 2026-11-15.)
pcall(gameEsc.RegisterEvent, gameEsc, "GLOBAL_MOUSE_UP")
gameEsc:SetScript("OnEvent", function(self, event, button)
	if event == "PLAYER_LOGIN" then
		-- (On key down or up as the game's action buttons are, not both: it'd go twice.)
		self:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- (Out of a fight: a binding the fight kept, with the poller stopped
		-- (the Shoulder Cam turned off in it), given back now.)
		if self.Sync then self.Sync() end
	elseif button == "RightButton" and #closing.held > 0 then
		local ok, again = pcall(function()
			return UnitExists("mouseover") and UnitIsUnit("mouseover", "npc")
		end)
		if ok and ns.Flag(again) and ns.ShoulderTalkKeep then ns.ShoulderTalkKeep("right-clicked them again") end
	end
end)
gameEsc.bound = false
-- The open NPC window: its frame, name, close call's label and the call.
local function GameTalkWindow()
	for _, entry in ipairs(GAME_TALK) do
		local frame = _G[entry[1]]
		if frame and ns.Flag(frame:IsShown()) then return frame, entry[1], entry[2], entry[3] end
	end
end
-- Your bags closed while a close is held, and closed again if one opens
-- before it goes (a bag key). (Post-hooks only: nothing of the game's replaced.)
function gameEsc.HoldBags()
	gameEsc.bagsHeld = true
	if CloseAllBags then pcall(CloseAllBags) end
	if gameEsc.bagHooks then return end
	gameEsc.bagHooks = true
	local function Shut()
		if not gameEsc.bagsHeld then return end
		if #closing.held == 0 then
			gameEsc.bagsHeld = nil
			return
		end
		ns.Log("shoulder", "talk close: a bag opened while the close is held, closed again")
		if CloseAllBags then pcall(CloseAllBags) end
	end
	for _, name in ipairs({ "OpenAllBags", "ToggleAllBags", "OpenBag", "ToggleBag", "ToggleBackpack", "OpenBackpack" }) do
		if type(_G[name]) == "function" then hooksecurefunc(name, Shut) end
	end
end
-- A cover over the held (faded) window that takes its clicks, gone once
-- nothing's held. (Ours, over it: nothing of the game's window is changed.)
local guard = CreateFrame("Frame", "CinematicShoulderTalkGuard", UIParent)
guard:EnableMouse(true)
pcall(guard.EnableMouseWheel, guard, true)
guard:SetFrameStrata("FULLSCREEN")
guard:Hide()
guard:SetScript("OnUpdate", function(self)
	if #closing.held == 0 or not (self.window and self.window:IsVisible()) then
		self:Hide()
		self.window = nil
	end
end)
function gameEsc.Guard(frame)
	guard:ClearAllPoints()
	guard:SetAllPoints(frame)
	guard.window = frame
	guard:Show()
	gameEsc.HoldBags()
end
-- The window faded out over gameEsc.fadeTime while the camera glides back;
-- its alpha back as it hides. (Our own steps: the game's UIFrameFade on its
-- frames can spread taint.)
gameEsc.fadeTime = 0.2
local function FadeGameWindow(frame)
	if not frame.cinematicEscHooked then
		frame.cinematicEscHooked = true
		frame:HookScript("OnHide", function(self)
			gameEsc.fading = nil
			self:SetAlpha(1)
		end)
	end
	gameEsc.fading = frame
	ns.SetOnUpdate(gameEsc, function(_, elapsed)
		local fading = gameEsc.fading
		if not fading then
			ns.SetOnUpdate(gameEsc, nil)
			return
		end
		local alpha = math.max(0, (fading:GetAlpha() or 1) - elapsed / gameEsc.fadeTime)
		fading:SetAlpha(alpha)
		if alpha <= 0 then ns.SetOnUpdate(gameEsc, nil) end
	end)
end
-- A close through the glide back: held (ns.ShoulderTalkClose), the window
-- faded and kept from clicks; or at once if nothing holds it (no turn, a fight).
function gameEsc.HeldClose(frame, label, close, quick)
	ns.ShoulderTalkClose(label, close, quick)
	if #closing.held > 0 then
		FadeGameWindow(frame)
		gameEsc.Guard(frame)
	end
end
-- (A popup up over it, "Sell this?" and the like: Escape's the game's, for the popup.)
function gameEsc.PopupUp()
	for i = 1, 4 do
		local popup = _G["StaticPopup" .. i]
		if popup and ns.Flag(popup:IsShown()) then return true end
	end
	return false
end
-- (MultiQuestFix.lua: the game's Accept held for the glide back, its window
-- faded and guarded the same way.)
ns.ShoulderFadeGameWindow = function(frame)
	FadeGameWindow(frame)
	if #closing.held > 0 then gameEsc.Guard(frame) end
end
gameEsc:SetScript("PostClick", function()
	local frame, name, label, close = GameTalkWindow()
	if not frame then return end
	ns.Log("shoulder", ("escape: the game's %s, closing after the glide back"):format(name))
	gameEsc.HeldClose(frame, label, close)
end)

-- Covers over the game's own close buttons (X, Goodbye, Decline): plain
-- buttons of ours on top that close through the glide back. The game's button
-- under it is lit and pressed as ours is, so it looks the same. Each found by
-- its name on either client; the ones found are logged as the window opens.
-- { path from _G (dots for keys), the call's label, the call, quick } (no
-- call: the window's own close).
local COVER_BUTTONS = {
	all = { ".CloseButton", "CloseButton", ".BorderFrame.CloseButton" },
	GossipFrame = { { "GossipFrame.GreetingPanel.GoodbyeButton" }, { "GossipFrameGreetingGoodbyeButton" } },
	QuestFrame = { { "QuestFrameGoodbyeButton" }, { "QuestFrameGreetingGoodbyeButton" }, { "QuestFrameCancelButton" },
		-- (Decline: its glide back at once, as Accept's.)
		{ "QuestFrameDeclineButton", "DeclineQuest", function() DeclineQuest() end, true } },
	ClassTrainerFrame = { { "ClassTrainerCancelButton" } },
	TaxiFrame = { { "TaxiCloseButton" } },
	MailFrame = { { "InboxCloseButton" } },
}
local function Resolve(path)
	local node = _G
	for key in path:gmatch("[^%.]+") do
		if type(node) ~= "table" then return nil end
		node = node[key]
	end
	if type(node) ~= "table" or not node.IsObjectType then return nil end
	local ok, button = pcall(node.IsObjectType, node, "Button")
	return ok and button and node or nil
end
gameEsc.covers = {} -- [the game's button] = our cover
gameEsc.coveredFor = nil -- (the window and buttons covers were laid for, logged once)
local function Cover(target, frame, label, close, quick)
	local cover = gameEsc.covers[target]
	if not cover then
		cover = CreateFrame("Button", nil, UIParent)
		cover:RegisterForClicks("LeftButtonUp")
		cover:SetScript("OnEnter", function(self) pcall(self.target.LockHighlight, self.target) end)
		cover:SetScript("OnLeave", function(self)
			pcall(self.target.UnlockHighlight, self.target)
			pcall(self.target.SetButtonState, self.target, "NORMAL")
		end)
		cover:SetScript("OnMouseDown", function(self) pcall(self.target.SetButtonState, self.target, "PUSHED") end)
		cover:SetScript("OnMouseUp", function(self) pcall(self.target.SetButtonState, self.target, "NORMAL") end)
		cover:SetScript("OnClick", function(self)
			pcall(self.target.UnlockHighlight, self.target)
			ns.Log("shoulder", ("talk close: the game's %s, closing after the glide back"):format(self.which))
			gameEsc.HeldClose(self.frame, self.label, self.close, self.quick)
		end)
		-- (Gone with the button: never left over a closed window, taking clicks.)
		cover:SetScript("OnUpdate", function(self)
			if not self.target:IsVisible() then self:Hide() end
		end)
		cover.target = target
		gameEsc.covers[target] = cover
	end
	-- (Already over it for this window: nothing to do, every frame.)
	if cover:IsShown() and cover.frame == frame and cover.label == (label or cover.label) then return end
	cover.frame, cover.label, cover.close, cover.quick = frame, label, close, quick
	cover.which = target:GetName() or label
	cover:ClearAllPoints()
	cover:SetAllPoints(target)
	cover:SetFrameStrata(target:GetFrameStrata() or "HIGH")
	cover:SetFrameLevel((target:GetFrameLevel() or 1) + 20)
	cover:Show()
end
function gameEsc.Covers(frame, name, label, close)
	local seen, laid = {}, {}
	local function Try(path, coverLabel, coverClose, quick)
		local target = Resolve(path)
		if target and not seen[target] and ns.Flag(target:IsVisible()) then
			seen[target] = true
			Cover(target, frame, coverLabel or label, coverClose or close, quick)
			laid[#laid + 1] = path
		end
	end
	for _, suffix in ipairs(COVER_BUTTONS.all) do Try(name .. suffix) end
	for _, entry in ipairs(COVER_BUTTONS[name] or {}) do Try(entry[1], entry[2], entry[3], entry[4]) end
	local key = name .. ":" .. table.concat(laid, ",")
	if gameEsc.coveredFor ~= key then
		gameEsc.coveredFor = key
		ns.Log("shoulder", ("covers over the game's %s buttons: %s"):format(name,
			#laid > 0 and table.concat(laid, ", ") or "none found"))
	end
end
function gameEsc.Uncover()
	for _, cover in pairs(gameEsc.covers) do cover:Hide() end
	gameEsc.coveredFor = nil
end

-- The held close called off: the window (faded out) back, the turn back
-- toward them, and the talk goes on as if Escape hadn't been pressed.
function ns.ShoulderTalkKeep(why)
	if #closing.held == 0 then return end
	closing.held = {}
	closing.token = closing.token + 1 -- (its safety timer ends nothing now)
	talk.back, talk.quick, talk.backAt, talk.fullAt = false, false, nil, nil
	local frame = gameEsc.fading
	if frame then
		gameEsc.fading = nil
		frame:SetAlpha(1)
	end
	if ns.QuestTalkKeep then ns.QuestTalkKeep() end
	ns.Log("shoulder", ("talk close: called off (%s), the talk goes on"):format(why))
end

-- (Every frame from the poller, and as the Shoulder Cam's applied: out of fights only.)
local function SyncGameEscape()
	if InCombatLockdown() then return end
	-- want: "talk" (an NPC window: the glide back), or false.
	local want, window, name, label, close = false, nil, nil, nil, nil
	if ShoulderOn() and TalkOn() and talk.on and not (ns.QuestTalkActive and ns.QuestTalkActive()) then
		window, name, label, close = GameTalkWindow()
		if window ~= nil then want = "talk" end
	end
	-- (The game's buttons covered while it's open; a button that shows later,
	-- the next quest panel's Goodbye, covered as it does. Not while held.)
	if want and #closing.held == 0 then
		gameEsc.Covers(window, name, label, close)
	elseif not want and gameEsc.coveredFor then
		gameEsc.Uncover()
	end
	-- (A popup up, "Sell this?" and the like: Escape's the game's, for it.)
	if want and gameEsc.PopupUp() then want = false end
	if want == gameEsc.bound then return end
	gameEsc.bound = want
	if want then
		gameEsc:SetAttribute("macrotext", ns.Setting("shoulderCamEscTarget") and "/cleartarget" or "")
		SetOverrideBindingClick(gameEsc, true, "ESCAPE", gameEsc:GetName())
	else
		ClearOverrideBindings(gameEsc)
	end
	ns.Log("shoulder", want and ("escape: bound for the game's %s"):format(tostring(name))
		or "escape: back to the game's")
end
gameEsc.Sync = SyncGameEscape -- (its PLAYER_REGEN_ENABLED, above)

-- Turn to your target (shoulderCamTargetTurn, off by default). The game's
-- enemy focus (test_cameraTargetFocusEnemy...) turns the camera toward an
-- enemy you target, but out of combat at fixed strengths it does nothing: it
-- moves only while its strengths are changing, and holds the turn after the
-- target's gone till they come back down (the "enemy" map run, retail dummy,
-- 2026-11-12, Tools/shoulder-test-plan.md). So, as with the talk turn, it's on
-- with them at 0, eased up to the game's own (aim.yaw, aim.pitch) over
-- shoulderCamTalkTime while an enemy's targeted, and down again over
-- a time of its own (shoulderCamTargetBack) once it isn't: a slow turn there and a glide back. In a fight it's
-- untested. A target the game won't say is an enemy (secret) counts as none.
local aim = {
	enable = "test_cameraTargetFocusEnemyEnable",
	yawCVar = "test_cameraTargetFocusEnemyStrengthYaw",
	pitchCVar = "test_cameraTargetFocusEnemyStrengthPitch",
	yaw = 0.5, pitch = 0.4, -- (the game's defaults, Forever and retail)
	share = 0, had = nil, -- (how far the turn is, 0-1; whether an enemy was targeted at the last frame)
}

local function AimOn()
	return ShoulderOn() and ns.db.shoulderCamTargetTurn and paused ~= "show in"
end

local function SetAimShare(yours, share)
	local k = share * share * (3 - 2 * share)
	Write(yours, aim.yawCVar, ("%.3f"):format(k * aim.yaw), true)
	Write(yours, aim.pitchCVar, ("%.3f"):format(k * aim.pitch), true)
end

-- (A dead one isn't: you target those to loot them, 2026-11-13.)
local function HasEnemy()
	return UnitExists("target") and ns.Flag(UnitCanAttack("player", "target"))
		and not ns.Flag(UnitIsDeadOrGhost("target")) or false
end

-- The game's soft enemy target, held on while the camera's turned (user,
-- 2026-11-16: "yes"). Esc clears your target and the game drops its turn at
-- once, a snap, whatever the strengths (the "soft" run, Forever trial 2:
-- kept full, gone by 0.2 s). With the soft target on that enemy, the turn
-- stays on it after the clear (Forever trial 2: still turned 1.2 s on), and
-- eases back with the strengths (retail tank dummy, same day). Clearing a
-- target can't be held (protected), so this is the only way to a glide.
-- Raised to these only where yours are lower, given back once the glide's
-- done (or a fight turns it back with the target kept: no glide to hold).
-- In those 1.5 s, attacks with no target can go to the soft one.
aim.soft = { SoftTargetEnemy = 3, SoftTargetEnemyArc = 2, SoftTargetEnemyRange = 45 }
local function SoftHold(yours, on)
	-- SoftTarget CVars are protected in fights: a SetCVar there isn't an
	-- error pcall catches but an ADDON_ACTION_BLOCKED, once a frame (680 in
	-- 8 s, Forever 2026-11-16). Not touched in fights; given back after.
	if InCombatLockdown() then
		if not on and not aim.softSaid then
			for cvar in pairs(aim.soft) do
				if yours[cvar] ~= nil then
					aim.softSaid = true
					ns.Log("cvar", "Shoulder Cam: soft target given back once the fight ends")
					break
				end
			end
		end
		return
	end
	for cvar, want in pairs(aim.soft) do
		local now = GetCVar(cvar)
		if now == nil then
			-- (Not on this client.)
		elseif on then
			if (tonumber(now) or 0) < want then
				if yours[cvar] == nil then yours[cvar] = now end
				local ok = pcall(SetCVar, cvar, tostring(want))
				ns.Log("cvar", ("Shoulder Cam: %s %s -> %s, the soft target for the glide back%s"):format(cvar, now,
					want, ok and "" or " (refused)"))
			end
		elseif yours[cvar] ~= nil then
			-- (Refused: it's tried again each frame, out of fights.)
			local back = yours[cvar]
			local ok = pcall(SetCVar, cvar, back)
			if ok and Same(GetCVar(cvar), back) then
				yours[cvar] = nil
				ns.Log("cvar", ("Shoulder Cam: %s back to %s"):format(cvar, back))
			elseif not aim.softSaid then
				aim.softSaid = true
				ns.Log("cvar", ("Shoulder Cam: %s back to %s refused (in a fight %s): tried again"):format(cvar, back,
					tostring(InCombatLockdown())))
			end
		end
	end
	if on then aim.softSaid = nil end
end
-- Turn to your target's Show in row (Frames.lua's rows): where it turns, and
-- whether in fights. Every place and fights ticked to start with (it turned
-- everywhere before); Not in fights, a box till 2026-11-13, is its Combat
-- tick now. Read 4 times a second (rules aren't cheap). Its Always
-- (shoulderCamTargetTurnAlways, on to start with, 2026-11-14) turns it
-- everywhere; the row had no Always column before, so an Always set by its
-- rule (cineShow) wasn't seen, its ticks all off: it never turned.
ns.SHOULDER_TURN_ROW = "shoulder:targetturn"
ns.CINE_SHOW_SETTING[ns.SHOULDER_TURN_ROW] = "shoulderCamTargetTurnAlways"
-- (Out of fights to start with, its Always off: user, 2026-11-15; and not indoors, 2026-11-16.)
ns.RULE_DEFAULTS[ns.SHOULDER_TURN_ROW] = "not indoors and not combat"
for _, list in ipairs({ "combatShow", "worldShow", "cityShow", "bgShow", "instanceShow", "groupShow" }) do
	ns.LIST_DEFAULTS[list][ns.SHOULDER_TURN_ROW] = true
end
local turnRead = { at = -1, on = true }
local function TurnHere()
	local now = GetTime()
	if now - turnRead.at >= 0.25 then
		turnRead.at = now
		if ns.db.shoulderCamTargetTurnNoFight then -- (the old box, once)
			ns.db.combatShow[ns.SHOULDER_TURN_ROW] = false
			ns.db.shoulderCamTargetTurnNoFight = nil
		end
		local ok, on = pcall(ns.RowOnNow, ns.SHOULDER_TURN_ROW, ns.db.shoulderCamTargetTurnAlways, true)
		turnRead.on = not ok or on and true or false
	end
	return turnRead.on
end

-- Frames follow you through the turn. The game won't say how far it turned
-- (or where the target is), but a click does: the target was under the
-- cursor. You slide the other way by about aim.slide of the click's x (both as
-- shares of the half-width), eased in with the turn ("aimclick" run, retail,
-- 2026-11-13: dummy at -0.8 or 0.85, you slid 13% of the width; in the middle,
-- none). Picked with a targeting key (Tab), from a unit frame or any other
-- way: no clue, so the frames stay where the offset puts you, as before.
aim.slide = 0.32
aim.turnBy = 0.47 -- (the share of the target's x the game's turn takes off, at full)
aim.farthest = 0.85 -- (the click's x it's never taken past: the furthest measured)
-- (Over the world or a nameplate: forbidden ones can't be asked, so count as a plate.)
function aim.OverWorld()
	local ok, focus = pcall(function()
		if GetMouseFoci then return GetMouseFoci()[1] end
		return GetMouseFocus and GetMouseFocus()
	end)
	if not ok or focus == nil or focus == WorldFrame then return true end
	if focus.IsForbidden and focus:IsForbidden() then return true end
	local okName, name = pcall(focus.GetName, focus)
	return okName and type(name) == "string" and name:find("^NamePlate") ~= nil or false
end
aim.mouse = CreateFrame("Frame")
pcall(aim.mouse.RegisterEvent, aim.mouse, "GLOBAL_MOUSE_DOWN")
aim.mouse:SetScript("OnEvent", function(_, _, button)
	if button ~= "LeftButton" and button ~= "RightButton" then return end
	local x = GetCursorPosition()
	local width = UIParent:GetWidth() * UIParent:GetEffectiveScale()
	aim.downAt, aim.downX, aim.downWorld = GetTime(), (x / width - 0.5) * 2, aim.OverWorld()
	aim.downButton = button
end)
for _, name in ipairs({ "TargetNearestEnemy", "TargetNearestEnemyPlayer", "TargetNearest", "TargetNearestFriend",
	"TargetNearestPartyMember", "TargetNearestRaidMember", "TargetLastTarget", "TargetLastEnemy", "TargetUnit" }) do
	if type(_G[name]) == "function" then hooksecurefunc(name, function() aim.keyAt = GetTime() end) end
end
-- (At each target change: a click's x, or none.)
function aim.Picked()
	if not HasEnemy() then return end -- (cleared: the slide eases back with the turn)
	local now, how = GetTime(), "no click or key"
	if aim.keyAt and now - aim.keyAt < 0.5 then
		aim.clickX, how = nil, "a targeting key"
	elseif aim.downAt and now - aim.downAt < 1 then
		aim.clickX = aim.downWorld and aim.downX or nil
		how = aim.downWorld and "a click" or "a click off the world (a unit frame?)"
	else
		aim.clickX = nil
	end
	aim.dragged, aim.fixedX = nil, nil
	aim.Mark()
	ns.Log("shoulder", ("target turn: picked by %s (cursor x %s, so you slide %s of the half-width) | facing %s, " ..
		"at %s, guessed %s yards away"):format(how,
		aim.clickX and ("%.3f"):format(aim.clickX) or "-", aim.clickX and ("%.3f"):format(-aim.slide * aim.clickX) or "none",
		aim.facing0 and ("%.3f"):format(aim.facing0) or "can't be read",
		aim.spot and ("%.1f, %.1f"):format(aim.spot[1], aim.spot[2]) or "can't be read", tostring(aim.yards)))
end

-- Then, as you turn and move: where the target is from you now. At the click
-- it's put in the world: the cursor's x gives its direction (the camera looking
-- your way then), and how far it is is a guess (between your spells' ranges
-- that do and don't reach it; else the game's interact ranges, out of a
-- fight; else 20 yards). Your facing (GetPlayerFacing) and where you are
-- (UnitPosition: north first, then west; facing 0 north and counting to the left) then
-- give its direction from you as you go. Either one unreadable (in an
-- instance): turning only, or just the click.
function aim.Facing()
	local ok, facing = pcall(GetPlayerFacing)
	if not ok then return nil end
	local okNumber, number = pcall(function() return facing + 0 end)
	return okNumber and number or nil
end
function aim.Spot()
	-- (Its first number is the north one: a strafe left, facing 5.13, moved it
	-- 5.0 and the second 2.2, retail 2026-11-13; the other way round reads a
	-- strafe as walking toward or away.)
	local ok, north, west = pcall(UnitPosition, "player")
	if not ok then return nil end
	local okNumber, spot = pcall(function() return { north + 0, west + 0 } end)
	return okNumber and spot or nil
end
function aim.Yards()
	-- (Your spells' ranges first: they answer in a fight too, Frames.lua.)
	local spells = ns.TargetSpellYards and ns.TargetSpellYards()
	if spells then return spells end
	if InCombatLockdown() then return 20 end
	for _, band in ipairs({ { 3, 7 }, { 2, 10 }, { 4, 20 } }) do
		local ok, near = pcall(CheckInteractDistance, "target", band[1])
		if ok and near ~= nil and not (issecretvalue and issecretvalue(near)) then
			if near then return band[2] end
		else
			return 20
		end
	end
	return 35
end
function aim.Mark()
	aim.facing0, aim.spot, aim.yards, aim.where = nil, nil, nil, nil
	if not aim.clickX then return end
	aim.facing0, aim.spot, aim.yards = aim.Facing(), aim.Spot(), aim.Yards()
	if aim.facing0 and aim.spot then
		local toward = aim.facing0 - math.atan(aim.clickX * ns.ShoulderViewWidth())
		aim.where = { aim.spot[1] + aim.yards * math.cos(toward), aim.spot[2] + aim.yards * math.sin(toward) }
	end
end
-- The click's x as it would be now (shares of the half-width; nil: none).
-- The target's direction from your facing now (radians, + right, -pi to pi),
-- or nil: no click, or your facing can't be read. (Also for ShoulderCamTest.lua.)
function aim.Angle()
	if not aim.clickX then return nil end
	local width = ns.ShoulderViewWidth()
	local facing = aim.facing0 and aim.Facing()
	if not facing then return nil end
	local angle
	local spot = aim.where and aim.Spot()
	if spot then
		local toward = math.atan2(aim.where[2] - spot[2], aim.where[1] - spot[1])
		angle = facing - toward
	else
		angle = facing - aim.facing0 + math.atan(aim.clickX * width)
	end
	return (angle + math.pi) % (2 * math.pi) - math.pi
end
ns.ShoulderAimAngle = aim.Angle

-- How far you slide with the game's turn, by how far round the target is
-- (degrees off your facing, either side), in shares of the half-width:
-- measured ("angles" run, retail, 2026-11-13, zoom 9, turning with the keys
-- and holding still at each). It grows to about 75 degrees, holds to 110 and
-- eases off behind you (160 degrees: 0.17). But near straight behind, which
-- side the target's on is a few degrees either way, and the guess (its
-- distance only a guess) put it on the wrong one: the PRD went 0.3 the other
-- way from you (2026-11-13). So from 135 degrees it eases to nothing by 165:
-- on your spot there, never on the wrong side.
aim.CURVE = { { 0, 0 }, { 15, 0.04 }, { 30, 0.12 }, { 45, 0.16 }, { 60, 0.24 }, { 75, 0.29 }, { 90, 0.29 },
	{ 110, 0.30 }, { 135, 0.24 }, { 165, 0 }, { 180, 0 } }
function aim.Slide(degrees)
	local from = aim.CURVE[1]
	for i = 2, #aim.CURVE do
		local to = aim.CURVE[i]
		if degrees <= to[1] then
			return from[2] + (to[2] - from[2]) * (degrees - from[1]) / (to[1] - from[1])
		end
		from = to
	end
	return 0
end

-- The click's x as it would be now (shares of the half-width, the one the
-- slide's worked out from: aim.slide of it; nil: none).
function aim.NowX()
	if not aim.clickX then return nil end
	local angle = aim.Angle()
	-- (No facing to go by: the click as it was, read off the same curve.)
	if not angle then angle = math.atan(aim.clickX * ns.ShoulderViewWidth()) end
	local degrees = math.deg(angle)
	local x = aim.Slide(math.abs(degrees)) / aim.slide
	return degrees < 0 and -x or x
end

local function AimTick(elapsed)
	local yours = ns.db and ns.db.shoulderCamYours
	if not (yours and AimOn()) or ns.shoulderTestHold or (ns.DialogueUICameraOn and ns.DialogueUICameraOn()) then
		return
	end
	-- (Its Show in row off here, e.g. Combat unticked in a fight: as if none
	-- were targeted, so it glides back, and turns again after.)
	local enemy = HasEnemy() and TurnHere()
	-- (The turn in and the glide back each their own time since 2026-11-16,
	-- as the NPC turn's: one time for both before.)
	local step = elapsed / math.max(0.1, (enemy and ns.db.shoulderCamTalkTime or ns.db.shoulderCamTargetBack) or 3)
	if enemy ~= aim.had then
		aim.had = enemy
		ns.Log("shoulder", ("target turn: %s (target %s, attackable %s; enemy focus %s, turn %s, tilt %s, share %.2f)"):format(
			enemy and "an enemy targeted, turning to it"
				or HasEnemy() and ("an enemy targeted but its Show in row is off here (%s), gliding back"):format(
					InCombatLockdown() and "in a fight" or "not here")
				or ("no enemy, gliding back (soft target %s)"):format(
					select(2, pcall(function() return tostring(ns.Flag(UnitExists("softenemy"))) end)) or "?"),
			UnitExists("target") and "yes" or "none", select(2, pcall(tostring, UnitCanAttack("player", "target"))) or "secret",
			tostring(GetCVar(aim.enable)), tostring(GetCVar(aim.yawCVar)), tostring(GetCVar(aim.pitchCVar)), aim.share))
	end
	if aim.share >= 1 and not aim.full and enemy then
		aim.full = true
		ns.Log("shoulder", ("target turn: full (enemy focus %s, turn %s, tilt %s)"):format(tostring(GetCVar(aim.enable)),
			tostring(GetCVar(aim.yawCVar)), tostring(GetCVar(aim.pitchCVar))))
	elseif not enemy then
		aim.full = nil
	end
	if enemy then
		aim.share = math.min(1, aim.share + step)
	else
		aim.share = math.max(0, aim.share - step)
		-- (Gone back for a fight with the target kept: its click kept for after.)
		if aim.share == 0 and not HasEnemy() then aim.clickX = nil end
	end
	-- (The left button held on the world: the camera's being turned by itself,
	-- which nothing tells an addon (your facing stays), so the guess is lost:
	-- the frames go back to the offset's place till the next click. A plain
	-- click's down for well under 0.3 seconds.)
	-- The right button too ("follow" run, retail 2026-11-13): turning with it
	-- drops the game's turn toward the target, the camera going straight
	-- behind you (you were back on your spot a second after), so the guess,
	-- which counted on the turn, went the wrong way.
	if aim.clickX and aim.downButton and aim.downWorld and aim.downAt
		and GetTime() - aim.downAt > 0.3 and IsMouseButtonDown and IsMouseButtonDown(aim.downButton) then
		ns.Log("shoulder", ("target turn: the camera turned with the mouse (%s), the frames let go of the guess"):format(
			aim.downButton))
		aim.clickX, aim.dragged = nil, true
	end
	-- Your mouse over your target: where it is on screen now, a fresh fix
	-- (picked with Tab, it's the only one). The cursor's x is where the target
	-- sits with the game's turn partway: that turn takes off aim.turnBy of its x
	-- at full ("aimclick": 0.86 went to 0.46), so the x without it is put back.
	-- Not after a drag: that undid the game's turn (the camera stays behind
	-- you), so there's no turn left to follow.
	aim.hoverClock = (aim.hoverClock or 0) + elapsed
	if enemy and not aim.dragged and aim.hoverClock >= 0.2 and IsMouseButtonDown
		and not IsMouseButtonDown("LeftButton") and not IsMouseButtonDown("RightButton") then
		aim.hoverClock = 0
		if UnitExists("mouseover") and ns.Flag(UnitIsUnit("mouseover", "target")) and aim.OverWorld() then
			local x = GetCursorPosition()
			local seen = (x / (UIParent:GetWidth() * UIParent:GetEffectiveScale()) - 0.5) * 2
			local k = aim.share * aim.share * (3 - 2 * aim.share)
			local without = seen / math.max(0.3, 1 - aim.turnBy * k)
			without = math.max(-aim.farthest, math.min(aim.farthest, without))
			local was = aim.NowX()
			aim.clickX = without
			aim.Mark()
			if not aim.fixedX or math.abs(aim.fixedX - without) > 0.05 then
				ns.Log("shoulder", ("target turn: your mouse is over it: seen at x %.3f with the turn at %.2f, so %.3f " ..
					"without it (the guess had %s) | %s yards"):format(seen, aim.share, without,
					was and ("%.3f"):format(was) or "none", tostring(aim.yards)))
			end
			aim.fixedX = without
		end
	end
	-- (Following a click: where it thinks the target is, twice a second.)
	aim.logClock = (aim.logClock or 0) + elapsed
	if aim.clickX and aim.logClock >= 0.5 then
		aim.logClock = 0
		local facing, spot, nowX = aim.Facing(), aim.Spot(), aim.NowX()
		ns.Log("shoulder", ("target turn: following, x now %s (click %.3f), share %.2f | facing %s, at %s"):format(
			nowX and ("%.3f"):format(nowX) or "-", aim.clickX, aim.share, facing and ("%.3f"):format(facing) or "-",
			spot and ("%.1f, %.1f"):format(spot[1], spot[2]) or "-"))
	end
	-- (The soft target: on while turned to an enemy; kept through the glide
	-- after a clear; off once it's all the way back, or with the target kept
	-- but the turn going back (a fight, its row off): nothing to hold then.)
	-- (Its own box, shoulderCamSoftGlide: off, the soft target's never touched.)
	if enemy and ns.db.shoulderCamSoftGlide then
		aim.softHeld = true
	elseif HasEnemy() or aim.share <= 0 or not ns.db.shoulderCamSoftGlide then
		aim.softHeld = nil
	end
	SoftHold(yours, aim.softHeld)
	SetAimShare(yours, aim.share)
end

-- Every frame while the Shoulder Cam's on.
local function TalkTick(elapsed)
	local yours = ns.db and ns.db.shoulderCamYours
	if not (yours and TalkOn()) or ns.shoulderTestHold or (ns.DialogueUICameraOn and ns.DialogueUICameraOn()) then
		CloseNow("talk turn off")
		return
	end
	-- (The last window closed talk.grace ago: glide back from wherever the turn
	-- is, and it's over once it's all the way back. Dropped to 0 at once
	-- before, a snap: after Accept the game closes the quest itself
	-- (QUEST_FINISHED with the close still held), and 0.6 s on the glide back
	-- was cut off at 0.61 s held (the log, 2026-11-14).)
	if talk.on and talk.closedAt and GetTime() - talk.closedAt >= talk.grace then
		if talk.share <= 0 then
			talk.on, talk.closedAt = false, nil
		elseif not talk.back then
			talk.back, talk.backAt = true, nil
		end
	end
	if not talk.on then
		talk.share, talk.back, talk.fullAt, talk.backAt = 0, false, nil, nil
		talk.quick, talk.heldByCam = false, nil
	else
		-- (A held close with no new window after talk.swapWait: the glide back.)
		if talk.backAt and GetTime() >= talk.backAt then
			talk.back, talk.backAt = true, nil
		end
		local holder = ns.CameraHolder and ns.CameraHolder("talk")
		-- (Walking off with the window open: glide back now, at the quick
		-- pace. The game ends the talk once you're out of reach, and its
		-- 0.2 s snap then has nothing left to undo (user, 2026-11-15: "it
		-- will just instantly snap back"). Stopped with it still open: back
		-- toward them.)
		local ok, away = pcall(function() return GetUnitSpeed("player") > 0 end)
		away = ok and away == true
		if away ~= (talk.walkingOff or false) then
			talk.walkingOff = away
			ns.LogDetail("cvar", away and "Shoulder Cam: talk turn glides back, walking off"
				or "Shoulder Cam: stopped, talk turn back toward them")
		end
		-- (One of our cameras holding the view (the quest or chat camera): the
		-- turn's held where it is till the window closes, then glides back at
		-- NPC turn back takes. Stepped down under it before, so the window
		-- closed with nothing left to turn back (user, 2026-11-16: "Hold till
		-- close").)
		local held = holder ~= nil and holder ~= "you" -- (a plain true/false: nil ~= false logged every frame)
		if held ~= (talk.heldByCam or false) then
			talk.heldByCam = held
			ns.LogDetail("cvar", held and ("Shoulder Cam: talk turn held at %.2f, the %s camera has the view"):format(
				talk.share, tostring(holder)) or "Shoulder Cam: talk turn free again")
		end
		if talk.back or away then
			local time = away and talk.quickTime or TalkOutTime()
			talk.share = math.max(0, talk.share - elapsed / time)
		elseif not held then
			talk.share = math.min(1, talk.share + elapsed / TalkInTime())
		end
	end
	SetTalkShare(yours, talk.share)
	if #closing.held > 0 and talk.share <= 0 then CloseNow("glided back") end
end

local poller = CreateFrame("Frame")
poller:Hide()

function ns.ApplyShoulderCam()
	if not ns.db then
		return
	end
	local yours = ns.db.shoulderCamYours
	if ShoulderOn() and not ns.db.shoulderCamNoticed then
		AskNotice() -- (nothing written till it's answered)
	elseif ShoulderOn() then
		QuietWarning()
		yours = yours or {}
		ns.db.shoulderCamYours = yours
		-- (DialogueUI's camera sets the same offset for its talks, and puts
		-- back what it found: hands off till it's done. Support/DialogueUI.lua.)
		if not (ns.shoulderTestHold or (ns.DialogueUICameraOn and ns.DialogueUICameraOn())) then
			-- (Gamepad mode on Forever: the game holds centering on, so these
			-- are given back rather than written five times a second, and it
			-- says why once a session.)
			if PauseReason() == "gamepad" then
				GiveBack(yours, "CameraKeepCharacterCentered", "CameraReduceUnexpectedMovement")
				if not ns.shoulderPadSaid then
					ns.shoulderPadSaid = true
					ns.Log("shoulder", "paused: Forever's gamepad UI keeps your character centered, so the offset can't work")
					ns.Print(L["Shoulder Cam is paused while the gamepad UI is on: the game keeps your character centered in it."])
				end
			else
				Write(yours, "CameraKeepCharacterCentered", "0")
				Write(yours, "CameraReduceUnexpectedMovement", "0")
			end
			Write(yours, "test_cameraOverShoulder", ShoulderValue())
			-- (The strengths at 0 before the focus goes on, so it can't snap.)
			if TalkOn() then
				SetTalkShare(yours, talk.share)
				Write(yours, talk.enable, "1")
			else
				talk.share = 0
				GiveBack(yours, talk.enable, talk.yawCVar, talk.pitchCVar)
			end
			-- (The same for the enemy focus: at 0 before it goes on.)
			if AimOn() then
				SetAimShare(yours, aim.share)
				Write(yours, aim.enable, "1")
			else
				aim.share, aim.softHeld = 0, nil
				GiveBack(yours, aim.enable, aim.yawCVar, aim.pitchCVar)
				SoftHold(yours, false)
			end
		end
		poller:Show()
	else
		CloseNow("Shoulder Cam off")
		SyncGameEscape() -- (off: Escape the game's again)
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
-- The welcome window's See it first test (ShowMe.lua's "shoulder"): the
-- Shoulder Cam on for a few seconds whatever its setting, wherever you are:
-- it eases in over your shoulder, swaps sides once (at Swap takes' pace),
-- then eases back out ("demo", a pause) and stops. Nothing saved changes:
-- the side swaps on the demo's own, and with the setting off your camera
-- settings come back after as they do whenever it goes off (a reload in the
-- middle too: shoulderCamYours). Picking it is the one-time question's yes.
local DEMO_IN, DEMO_SWAP_AT, DEMO_OUT_AT = 0.9, 2.2, 5.2 -- seconds from the start
function ns.ShoulderCamDemoBlocked()
	if InCombatLockdown() then return L["Not in a fight: try it once the fight ends."] end
	if not ns.isRetail and ns.IsGamePadOn and ns.IsGamePadOn() then
		return L["Shoulder Cam is paused while the gamepad UI is on: the game keeps your character centered in it."]
	end
	if ns.FeatureYieldedTo and ns.FeatureYieldedTo("shoulderCam") then
		return L["Another addon has the shoulder camera (DynamicCam): the Shoulder Cam stands aside for it."]
	end
end
function ns.ShoulderCamDemo()
	if demo or ns.ShoulderCamDemoBlocked() or not ns.db then return false end
	if ns.ShoulderCamAgree then ns.ShoulderCamAgree() end
	-- (Always the right shoulder first, the default, then the left: user,
	-- 2026-11-15. Your own side's untouched, and back after if it's on.)
	demo = { side = "right", swapTo = "left", began = GetTime() }
	ns.Log("shoulder", "demo: starts (the welcome window's test)")
	ns.ApplyShoulderCam()
	return true
end
function ns.ShoulderCamDemoRunning() return demo ~= nil end
-- (Ended early, Stop: eased out as at its end.)
function ns.StopShoulderCamDemo()
	-- (With the Shoulder Cam on anyway: no glide out and back in, just back
	-- to your side at Swap takes' pace: the first run, 2026-11-15.)
	if demo and ns.Setting("shoulderCam") then
		demo = nil
		ns.Log("shoulder", "demo: done, back to your side")
		ns.ApplyShoulderCam()
		return
	end
	if demo and not demo.ending then
		demo.ending = true
		ns.ApplyShoulderCam()
	end
end
local function DemoTick()
	if not demo then return end
	local at = GetTime() - demo.began
	if not demo.swapped and at >= DEMO_SWAP_AT then
		demo.swapped, demo.side = true, demo.swapTo
	end
	if not demo.ending and at >= DEMO_OUT_AT then
		ns.StopShoulderCamDemo()
		if not demo then return end
	end
	-- (All the way back out, or stuck past its time: done.)
	if demo.ending and (blend <= 0 or at >= DEMO_OUT_AT + 4) then
		demo = nil
		ns.Log("shoulder", "demo: done")
		ns.ApplyShoulderCam()
	end
end
ns.SHOULDER_DEMO_SECONDS = DEMO_OUT_AT + DEMO_IN + 1

ns.SetOnUpdate(poller, function(_, elapsed)
	SyncGameEscape()
	DemoTick()
	TalkTick(elapsed)
	AimTick(elapsed)
	waited = waited + elapsed
	if waited >= POLL then
		waited = 0
		ns.ApplyShoulderCam()
		return
	end
	local yours = ns.db and ns.db.shoulderCamYours
	-- (Paused but still easing out: on, till it's all the way back.)
	if paused and blend <= 0 or not yours or ns.shoulderTestHold
		or (ns.DialogueUICameraOn and ns.DialogueUICameraOn()) then
		return
	end
	local value = ShoulderValue(true)
	if math.abs((tonumber(GetCVar("test_cameraOverShoulder")) or 0) - tonumber(value)) >= OFFSET_STEP then
		Write(yours, "test_cameraOverShoulder", value)
	end
end)

-- The swap shoulders key: a button its key binding clicks, bound on the
-- Shoulder Cam page or in the game's Key Bindings (Bindings.xml, since
-- 2026-11-15). Its name's fixed, as Bindings.xml names it (the dev copy's
-- was CinematicDevShoulderSwapButton before: bound again once there).
ns.OnLanguage(function()
	_G["BINDING_NAME_CLICK CinematicShoulderSwapButton:LeftButton"] = L["Swap shoulders (Shoulder Cam)"]
end)
local swap = CreateFrame("Button", "CinematicShoulderSwapButton", UIParent)
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
ns.ShoulderSwapButton = swap -- (ShoulderCamTest.lua's "today" run presses it)

-- The on/off key (Bindings.xml CINEMATIC_SHOULDERCAM, 2026-11-16): flips the
-- page's Enable switch, as clicking it does (the one-time question included).
local TOGGLE_ACTION = "CINEMATIC_SHOULDERCAM"
ns.OnLanguage(function()
	_G.BINDING_NAME_CINEMATIC_SHOULDERCAM = L["Toggle Shoulder Cam"]
end)
function Cinematic_ToggleShoulderCam() -- luacheck: ignore 111 (the key binding's global)
	local db = ns.db
	if not db or not ns.ShoulderCamUnlocked() then return end
	db.shoulderCam = not db.shoulderCam
	ns.ApplyShoulderCam()
	ns.Print((db.shoulderCam and L["%s on"] or L["%s off"]):format(L["Shoulder Cam"]))
	if ns.RefreshOptions then ns.RefreshOptions() end
end

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
-- moves while Edit Mode is open, nor a protected frame in a fight (one
-- that a portrait hangs on: it holds still and catches up after). The
-- player, target and focus frames aren't offered: the game locks them in
-- every fight (tested on retail, 2026-11-13: /cine debug shoulder lock).
-- Which follow is the player's pick, a setting each (shoulderCamFollow<key>,
-- all on by default); one not picked that hangs on a picked
-- one still rides along with it.
local FOLLOW_GROUPS = {
	{ key = "shoulderCamFollowCast", frames = { "PlayerCastingBarFrame", "CastingBarFrame",
		"GamepadPlayerCastingBarFrame" } },
	{ key = "shoulderCamFollowPRD", frames = { "PersonalResourceDisplayFrame", "CinematicPersonalResource" } },
	-- (The swing timers, main hand, off hand and ranged: Edit Mode's, often
	-- chained one under the other, so the first slides the rest.)
	{ key = "shoulderCamFollowSwing", frames = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame",
		"SwingTimerRangedFrame" } },
	{ key = "shoulderCamFollowEssential", frames = { "EssentialCooldownViewer" } },
	{ key = "shoulderCamFollowUtility", frames = { "UtilityCooldownViewer" } },
	{ key = "shoulderCamFollowBuffIcons", frames = { "BuffIconCooldownViewer" } },
	{ key = "shoulderCamFollowBuffBars", frames = { "BuffBarCooldownViewer" } },
	-- (The proc alerts round the middle (Lava Surge's curves...): not protected.)
	{ key = "shoulderCamFollowSpellAlerts", frames = { "SpellActivationOverlayFrame" } },
}
local FOLLOW_EASE = 12     -- how quickly the frames catch up (per second; the game eases over in ~0.3 s)
local FOLLOW_MAX = 0.3     -- never more than this share of the screen's width
local FOLLOW_MIN_ZOOM = 3 -- (closer, as this: in a 2026-11-07 recording at ~1.5 yards the bar went
                           -- to where your head-top is, well past your body; first person has no side)
local followed = {}        -- frame -> { points = the game's, ours = what we put on, shift = ours in UI units }
local followShift = 0      -- the slide now (UIParent units, + right), easing to the target
-- Height (shoulderCamFramesHeight, UI units, + up): the picked frames lifted
-- together, each with its own on top (<key>Height), while the camera's over
-- your shoulder; share eases 0 to 1 and back with it. A frame riding along on
-- another gets only its own (the one it rides on brings the rest).
-- (align: the PRD lined up with the cast bar, 0-1, eased: on while Frames
-- follow you is, paused too: user, 2026-11-15, "it's switching back" on a mount.)
local followLift = { share = 0, align = 0 }

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

-- The frames picked now (name -> its group's setting), from FOLLOW_GROUPS'.
local FOLLOWS = {}
local function PickFollows()
	local db = ns.db
	for name in pairs(FOLLOWS) do FOLLOWS[name] = nil end
	for _, group in ipairs(FOLLOW_GROUPS) do
		if db and db[group.key] then
			for _, name in ipairs(group.frames) do FOLLOWS[name] = group.key end
		end
	end
end

-- What a frame hangs on, up its chain of anchors (first points): "plate" if
-- a nameplate (it follows you already), another picked one (it rides
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

-- (shift across, lift up, in UI units. False: not moved, a protected frame in a fight.)
local function Place(frame, entry, shift, lift)
	if ns.Flag(frame:IsProtected()) and InCombatLockdown() then return false end
	lift = lift or 0
	local scale = UIParent:GetEffectiveScale() / math.max(0.01, frame:GetEffectiveScale())
	local ours = {}
	frame:ClearAllPoints()
	for i, p in ipairs(entry.points) do
		ours[i] = { p[1], p[2], p[3], p[4] + shift * scale, p[5] + lift * scale }
		frame:SetPoint(p[1], p[2] or UIParent, p[3], ours[i][4], ours[i][5])
	end
	-- (Read back: what the game reports for them, to see when it moves them.)
	entry.ours, entry.shift, entry.lift = ReadPoints(frame) or ours, shift, lift
	return true
end

local function Home(entry) return entry.shift == 0 and (entry.lift or 0) == 0 end

-- A frame's middle across the screen, in UI units from the screen's middle
-- (nil: can't be read). Taken as the game places it (an entry's homeX).
local function CenterX(frame)
	local ok, x = pcall(frame.GetCenter, frame)
	if not ok or type(x) ~= "number" or (issecretvalue and issecretvalue(x)) then return nil end
	return x * frame:GetEffectiveScale() / UIParent:GetEffectiveScale() - UIParent:GetWidth() / 2
end

-- Every followed frame back where the game had it, and forgotten; with keep
-- (a set of names), all but those. One that can't move yet (protected, in a
-- fight) is kept, to go back once it can.
local function PutBack(keep)
	for frame, entry in pairs(followed) do
		if not (keep and keep[frame:GetName() or ""])
			and (Home(entry) or Place(frame, entry, 0, 0)) then
			followed[frame] = nil
		end
	end
	if not keep then followShift, followLift.share, followLift.align = 0, 0, 0 end
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
	if not (db and ShoulderOn() and db.shoulderCamFrames) then return 0 end
	if YouAreTarget() then return 0 end
	local yards = tonumber(GetCVar("test_cameraOverShoulder")) or 0
	if yards == 0 then return 0 end
	-- (A shift's push past the new offset is for the game's ease, which it
	-- cancels: on screen you hardly move. Read as written, it slid the PRD a
	-- point the other way as you shifted, running: the moving shift run,
	-- 2026-11-14. So the push is left out here, and a moment past its end: the
	-- setting still held it for a frame then, and the PRD hopped 0.3.)
	if GetTime() < pushOver and steadyYards > 0 then
		yards = yards < 0 and -steadyYards or steadyYards
	end
	-- (The camera as it glides, as the offset follows it (SeenZoom): the
	-- zoom's end at once put the PRD where it'd be at zoom 4 while you were
	-- still small at 15, "prdcheck", Forever, 2026-11-13.)
	local distance = math.max(FOLLOW_MIN_ZOOM, SeenZoom())
	local half = UIParent:GetWidth() / 2
	local shift = -yards * ns.ShoulderModelScale() / (distance * ns.ShoulderViewWidth()) * half
		* (db.shoulderCamFramesStrength or 1)
	-- (Turned toward a target you clicked: the other way by a share of the click's x, aim above.)
	local nowX = aim.clickX and AimOn() and db.shoulderCamTargetFollow ~= false and aim.NowX()
	if nowX then
		local k = aim.share * aim.share * (3 - 2 * aim.share)
		shift = shift - aim.slide * nowX * k * half * (db.shoulderCamFramesStrength or 1)
	end
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
	-- (Height: in while over your shoulder, at the slide's pace. Crossing to
	-- the other shoulder the offset's 0 at the middle: still over it then.)
	local db = ns.db
	local swapping = sideNow and math.abs(sideNow) < 1 and blend > 0
	local over = db and ShoulderOn() and db.shoulderCamFrames
		and ((tonumber(GetCVar("test_cameraOverShoulder")) or 0) ~= 0 or swapping) and 1 or 0
	followLift.share = followLift.share + (over - followLift.share) * math.min(1, elapsed * FOLLOW_EASE)
	if math.abs(over - followLift.share) < 0.01 then followLift.share = over end
	local master = db and db.shoulderCamFramesHeight or 0
	PickFollows()
	-- (No longer picked: back on its place.)
	PutBack(FOLLOWS)
	-- The cast bar's own place across (moved by itself, not riding on the
	-- PRD): the PRD lines up under it, wherever the layout has the PRD
	-- across (retail's own layout: 410 UI units to the left, 2026-11-15:
	-- "it should be in line with the cast bar"). Kept while Frames follow
	-- you is on, the camera behind you too (followLift.align).
	local alignTo = db and ShoulderOn() and db.shoulderCamFrames and 1 or 0
	followLift.align = followLift.align + (alignTo - followLift.align) * math.min(1, elapsed * FOLLOW_EASE)
	if math.abs(alignTo - followLift.align) < 0.01 then followLift.align = alignTo end
	local castX
	if FOLLOWS.PlayerCastingBarFrame or FOLLOWS.CastingBarFrame then
		for _, name in ipairs({ "PlayerCastingBarFrame", "CastingBarFrame", "GamepadPlayerCastingBarFrame" }) do
			local bar = _G[name]
			local barEntry = type(bar) == "table" and followed[bar]
			if barEntry and barEntry.homeX and Mover(bar) then
				castX = barEntry.homeX
				break
			end
		end
	end
	for name, key in pairs(FOLLOWS) do
		local frame = _G[name]
		if type(frame) == "table" and frame.GetPoint then
			local entry, now = followed[frame], ReadPoints(frame)
			-- (Moved by the game since: its new place.)
			if now and (not entry or not SamePoints(now, entry.ours)) then
				entry = { points = now, ours = now, shift = 0, lift = 0, homeX = CenterX(frame) }
				followed[frame] = entry
			end
			-- (Riding along with another, or on a plate: only its own height;
			-- none: back on its own place, kept till it can go if protected in a fight.)
			local mover = Mover(frame)
			local own = db and db[key .. "Height"] or 0
			local shift = mover and followShift or 0
			if mover and castX and key == "shoulderCamFollowPRD" and entry and entry.homeX then
				shift = shift + (castX - entry.homeX) * followLift.align
			end
			local lift = ((mover and master or 0) + own) * followLift.share
			if entry and not mover and math.abs(lift) < 0.5 then
				if Home(entry) or Place(frame, entry, 0, 0) then followed[frame] = nil end
				entry = nil
			end
			if entry and (math.abs(entry.shift - shift) >= 0.5 or math.abs((entry.lift or 0) - lift) >= 0.5) then
				Place(frame, entry, shift, lift)
			end
		end
	end
	-- (Back home and nothing more wanted: stop; not while one is still out.)
	if target == 0 and followShift == 0 and followLift.share == 0 and followLift.align == 0 then
		PutBack()
		if not next(followed) then self:Hide() end
	end
end)

function UpdateFollow()
	if ns.db and ShoulderOn() and ns.db.shoulderCamFrames or next(followed) then
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
		followLift = followLift.share, followHeight = db and db.shoulderCamFramesHeight,
		youTarget = YouAreTarget(),
		picked = (function()
			local keys = {}
			for _, group in ipairs(FOLLOW_GROUPS) do
				if db and db[group.key] then keys[#keys + 1] = group.key:gsub("^shoulderCamFollow", "") end
			end
			return #keys > 0 and table.concat(keys, ", ") or "none"
		end)(),
		followed = (function()
			local names = {}
			for frame in pairs(followed) do names[#names + 1] = frame:GetName() or "?" end
			return #names > 0 and table.concat(names, ", ") or "none"
		end)(),
		paused = db and PauseReason() or "no", always = db and db.shoulderCamAlways, key = GetBindingKey(SWAP_ACTION) or "none",
		talkTurn = db and db.shoulderCamTalkTurn, talking = talk.on, talkShare = talk.share, talkBack = talk.back, talkQuick = talk.quick,
		targetTurn = db and db.shoulderCamTargetTurn, aimShare = aim.share, enemyTargeted = HasEnemy(), aimClickX = aim.clickX, aimNowX = aim.NowX(),
		enemyFocus = GetCVar(aim.enable), enemyYaw = GetCVar(aim.yawCVar), enemyPitch = GetCVar(aim.pitchCVar),
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

-- Logging out or reloading: Keep Character Centered and the motion sickness
-- option go back to yours as the game saves them, and come off again as the
-- next session starts (the offset's written fresh each session anyway). So
-- they're never left off by Cinematic not loading again (disabled,
-- uninstalled, a crash before then aside). yours keeps them meanwhile.
local ACCESSIBILITY = { "CameraKeepCharacterCentered", "CameraReduceUnexpectedMovement" }
local function GiveBackForLogout()
	local yours = ns.db and ns.db.shoulderCamYours
	if not yours then return end
	for _, cvar in ipairs(ACCESSIBILITY) do
		if yours[cvar] ~= nil and not Same(GetCVar(cvar), yours[cvar]) then
			SetCVar(cvar, yours[cvar])
		end
	end
	-- (The soft target too: a logout mid-glide mustn't keep it on.)
	for cvar in pairs(aim.soft) do
		if yours[cvar] ~= nil then
			pcall(SetCVar, cvar, yours[cvar])
			yours[cvar] = nil
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
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
	if event == "PLAYER_LOGOUT" then
		GiveBackForLogout()
		return
	end
	if TALK_EVENT[event] == "open" then
		local living, why = TalkingToLiving()
		if not living then
			ns.LogDetail("cvar", ("Shoulder Cam: no talk turn (%s: %s)"):format(event, tostring(why)))
			return
		end
		if not talk.on then ns.LogDetail("cvar", ("Shoulder Cam: talk turn starts (%s)"):format(event)) end
		if #closing.held > 0 then
			ns.Log("shoulder", ("talk close: %d held call(s) dropped, %s opened"):format(#closing.held, event))
			closing.held = {}
		end
		-- (A new window: toward them again, from wherever the turn is.)
		talk.on, talk.closedAt, talk.back, talk.fullAt, talk.backAt, talk.quick = true, nil, false, nil, nil, false
	elseif TALK_EVENT[event] == "close" then
		if talk.on and not talk.closedAt then talk.closedAt = GetTime() end
	elseif event == "UNIT_MODEL_CHANGED" then
		ModelSwapped()
		ns.ApplyShoulderCam()
	elseif event == "PLAYER_TARGET_CHANGED" then
		-- (Yourself targeted or not: the pause for it at once, not at the next
		-- poll (the game's own full offset for a moment first), and the frames.)
		if AimOn() then aim.Picked() end
		ns.ApplyShoulderCam()
	else
		if event == "PLAYER_ENTERING_WORLD" then talk.on, talk.closedAt = false, nil end
		ns.ApplyShoulderCam()
	end
end)

function ns.CreateShoulderCamPanel(kit)
	if not ns.ShoulderCamUnlocked() then return end -- (no page: locked, above)
	-- (A check given its own change function saves nothing itself: this saves, then runs it.)
	-- (Saved, then the page refreshed: a control greyed by another one follows
	-- it at once.)
	local function SaveThen(key, fn)
		return function(value)
			ns.GetDB()[key] = value
			fn()
			if ns.RefreshOptions then ns.RefreshOptions() end
		end
	end
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Shoulder Cam"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["The camera sits over your shoulder, with you to one side of the screen."])
	local switch = kit.PageSwitch(content, "shoulderCam", L["Enable Page"],
		L["On: the camera moves over your shoulder. This uses one of Blizzard's experimental " ..
		"camera settings: Cinematic asks once, then keeps the game's experimental camera warning away " ..
		"while it's on. The game's Keep Character Centered and motion sickness options stop it, so those " ..
		"are turned off meanwhile. Off: your own settings come back."], intro, function()
			ns.ApplyShoulderCam()
			-- (No profile offered any more: the camera works on any profile, and
			-- the Follow HUD tab puts the frames that follow you on yours.)
		end)
	local function IfOn() return ns.PageSetting("shoulderCam") end
	-- (Three folder tabs: the camera's settings, built on content as before and
	-- moved onto the first tab (Adopt, below), the frames that follow you, and
	-- which of our cameras it stays on through.)
	-- (A fourth on Forever, which has a gamepad UI: why it's not for that yet.)
	local tabList = {
		{ L["Shoulder Cam"], L["Where the camera sits, when it turns, and when it steps back behind you."] },
		{ L["Follow HUD"], L["The frames that follow you: which slide with you as the camera sits over your shoulder."] },
		{ L["Cameras"], L["Which of Cinematic's cameras the Shoulder Cam stays on through."] },
	}
	if not ns.isRetail then
		tabList[4] = { L["Gamepad"], L["Playing with the gamepad UI on."] }
	end
	-- (Last: measuring your race, sex and form, ShoulderCalibrate.lua.)
	tabList[#tabList + 1] = { L["Calibrate"], L["Measure where you sit for your race, sex and form, and share it."] }
	local calibrateTab = #tabList
	local tabHosts, _, TabsShown, Adopt = ns.PageTabsBelow(content, switch, tabList, "Shoulder Cam/page", nil, nil, 1)
	local stack = kit.Stack(switch, "check", true)

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
	-- The on/off key (user 2026-11-16), the same binding as the Keybinds page's
	-- row: an inline row, its button in the sliders' column. Never greyed: it's
	-- how the camera comes on.
	local toggleKey = kit.CreateKeybindButton(content, TOGGLE_ACTION, 1)
	toggleKey.inlineName = L["Toggle Shoulder Cam"]
	stack:Add(toggleKey, "dropdown")
	-- (One tick for the side, user 2026-11-15: ticked over the left shoulder.)
	local left = kit.Check(content, "shoulderCamSide", L["Left shoulder"],
		L["Over your left shoulder, you on the right of the screen. Unticked, over your right. " ..
		"The swap key beside it flips it."], function(value)
			ns.GetDB().shoulderCamSide = value and "left" or "right"
			ns.ApplyShoulderCam()
		end)
	left.Refresh = function(self) self:SetChecked(ns.GetDB().shoulderCamSide == "left") end
	kit.GreyUnless(stack:Add(left, "check"), IfOn)
	-- (The swap key on the tick's line, user 2026-11-15.)
	local key = kit.CreateKeybindButton(content, SWAP_ACTION, 1)
	key:SetPoint("LEFT", left, "LEFT", 200, 0)
	local spot = stack:Add(kit.Slider(content, "shoulderCamSpot", L["Spot on screen"], 5, 40, 1, "%d%%", 100),
		"slider")
	kit.Tooltip(spot, L["How far off the middle of the screen you sit, as a share of the way to its edge. " ..
		"The camera moves as you zoom to keep you there, and eases you back to the middle when you zoom " ..
		"right in. 33% puts you on the line a third of the way across."])
	kit.GreyUnless(spot, IfOn)
	local swapTime = stack:Add(kit.Slider(content, "shoulderCamSwapTime", L["Swap takes"], 0, 3, 0.1,
		L["%.1f sec"]), "slider")
	kit.Tooltip(swapTime, L["How long the camera takes to cross to your other shoulder as you swap sides. " ..
		"At 0 it's the game's own quick swap."])
	kit.GreyUnless(swapTime, IfOn)
	local selfTime = stack:Add(kit.Slider(content, "shoulderCamSelfTime", L["Back from targeting yourself"], 0, 3,
		0.1, L["%.1f sec"]), "slider")
	kit.Tooltip(selfTime, L["With yourself targeted the game puts you in the middle of the screen, at once. " ..
		"This is how long the camera takes to go back over your shoulder as you clear the target."])
	kit.GreyUnless(selfTime, IfOn)
	local pauseTime = stack:Add(kit.Slider(content, "shoulderCamPauseTime", L["Off and on again takes"], 0, 3,
		0.1, L["%.1f sec"]), "slider")
	kit.Tooltip(pauseTime, L["How long the camera takes to go back behind you as you go indoors, mount, or leave " ..
		"where Show in has it, and back over your shoulder after. Cinematic's own cameras have their own " ..
		"times on the Cameras tab."])
	kit.GreyUnless(pauseTime, IfOn)

	-- Turn to NPCs and Turn to your target: Show in rows, each one's box before
	-- the name (on at all), Combat and the places after (where it turns). (Turn
	-- to NPCs a plain tick till 2026-11-16: user, "turning inside can be a bit much".)
	local turningHeader = stack:Header(content, L["Turning"])
	local function IfTalk() return ns.PageSetting("shoulderCam") and ns.GetDB().shoulderCamTalkTurn end
	local talkRow = ns.ShowTable(content, turningHeader, {
		opts = { anyFight = true }, underHeader = true, layout = ns.GRID_PLACE_COMBAT_EDIT_LAYOUT,
		{ key = ns.SHOULDER_TALK_ROW, label = L["Turn to NPCs you talk to"], showKey = "shoulderCamTalkTurn",
			alwaysKey = "shoulderCamTalkTurnAlways",
			alwaysOn = function() return ns.GetDB().shoulderCamTalkTurnAlways end,
			setAlways = function(value) ns.GetDB().shoulderCamTalkTurnAlways = value talkRead.at = -1 end,
			alwaysTip = L["Turns to who you talk to wherever you are. (The other columns then have nothing to add.)"],
			showTip = L["As you talk to an NPC (or a vendor, banker, trainer or flight master), the camera turns " ..
			"slowly to bring them toward the middle of the screen, and stays there while the window's open. " ..
			"Close it (Escape, its X or Goodbye, Accept, Complete or Decline) and the window fades while the " ..
			"camera glides back, then it closes. Walking away turns back quickly."],
			showChanged = function() if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end end,
			apply = function() talkRead.at = -1 end,
			tip = L["Where the camera turns to who you talk to. Unticked here (indoors and in fights, to start with), " ..
			"it stays over your shoulder as you talk."] },
	}, "Shoulder Cam")
	stack:Continue(talkRow, "label")
	-- (Under it, indented: Escape in a talk window, the game's or Cinematic's own, 2026-11-15.)
	local escTarget = stack:Add(kit.Check(content, "shoulderCamEscTarget", L["Clear target on Esc while interacting with an NPC"],
		L["With an NPC's window open (talk, vendor, trainer, banker, flight master, auctioneer, stable master)," ..
		"Escape clears your target and closes the window in the same press. Off: Escape only closes it, and " ..
		"your target stays."]), "check", 16)
	kit.GreyUnless(escTarget, IfTalk)
	-- (Dev copy only, a test: MultiQuestFix.lua, user 2026-11-15.)
	if ns.isDev then
		stack:Add(kit.Check(content, "shoulderCamMultiQuestFix", L["Multi Quest fix"],
			L["Test (dev copy only). In the game's quest window, at a quest giver with more quests: Accept " ..
			"clears your target first, then press your Interact key to talk to them again. Each step goes " ..
			"in the log."]), "check", 16)
	end
	-- (The NPC turn's times with it, under its ticks: under Turn to enemy till
	-- 2026-11-16, they read as its own.)
	local talkIn = stack:Add(kit.Slider(content, "shoulderCamTalkIn", L["NPC turn takes"], 0.5, 4, 0.5,
		L["%.1f sec"]), "slider")
	kit.Tooltip(talkIn, L["How long the turn toward who you talk to takes as the window opens."])
	kit.GreyUnless(talkIn, IfTalk)
	local talkOut = stack:Add(kit.Slider(content, "shoulderCamTalkOut", L["NPC turn back takes"], 0.5, 4, 0.5,
		L["%.1f sec"]), "slider")
	kit.Tooltip(talkOut, L["How long the glide back over your shoulder takes as you close the window. " ..
		"Going from one window to the next with them (a quest's text, the next quest) it stays on them."])
	kit.GreyUnless(talkOut, IfTalk)
	-- Turn to enemy, under them: its own table, back out at the header's
	-- edge, with no column headings of its own (the NPC row's above say them).
	local turnTop = CreateFrame("Frame", nil, content)
	turnTop:SetSize(1, 1)
	turnTop:SetPoint("LEFT", turningHeader, "LEFT")
	turnTop:SetPoint("TOP", stack.last.stackSpot or stack.last, "BOTTOM", 0, (ns.GRID_KIT.headingHeight or 24) - 4)
	local turnRow = ns.ShowTable(content, turnTop, {
		opts = { anyFight = true }, underHeader = true, noHeadings = true, layout = ns.GRID_PLACE_COMBAT_EDIT_LAYOUT,
		{ key = ns.SHOULDER_TURN_ROW, label = L["Turn to enemy"], showKey = "shoulderCamTargetTurn",
			alwaysKey = "shoulderCamTargetTurnAlways",
			alwaysOn = function() return ns.GetDB().shoulderCamTargetTurnAlways end,
			setAlways = function(value) ns.GetDB().shoulderCamTargetTurnAlways = value turnRead.at = -1 end,
			alwaysTip = L["Turns to your target wherever you are, in fights too. (The other columns then have nothing to add.)"],
			showTip = L["As you target an enemy, the camera turns slowly toward it, and glides back at the same " ..
			"pace once you clear your target, pick a friendly one or it dies."],
			showChanged = function() if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end end,
			apply = function() turnRead.at = -1 end,
			tip = L["Where the camera turns to your target, and whether in fights. Unticked here, it glides " ..
			"back over your shoulder, and turns again once you're somewhere ticked."] },
	}, "Shoulder Cam")
	stack:Continue(turnRow, "label")
	local talkTime = stack:Add(kit.Slider(content, "shoulderCamTalkTime", L["Enemy turn takes"], 0.5, 4, 0.5,
		L["%.1f sec"]), "slider")
	kit.Tooltip(talkTime, L["How long the turn toward your target takes."])
	local function IfTurn() return ns.PageSetting("shoulderCam") and ns.GetDB().shoulderCamTargetTurn end
	kit.GreyUnless(talkTime, IfTurn)
	local turnBack = stack:Add(kit.Slider(content, "shoulderCamTargetBack", L["Enemy turn back takes"], 0.5, 4, 0.5,
		L["%.1f sec"]), "slider")
	kit.Tooltip(turnBack, L["How long the glide back over your shoulder takes as you clear your target, pick a " ..
		"friendly one or it dies."])
	kit.GreyUnless(turnBack, IfTurn)
	-- (The soft target trick, SoftHold: its own box so it can be turned off. User, 2026-11-16.)
	local softGlide = stack:Add(kit.Check(content, "shoulderCamSoftGlide", L["Glide back when you clear your target"],
		L["Clearing your target (Esc) makes the game drop its turn at once, a snap. With this on, the game's " ..
		"soft enemy target is kept on while the camera's turned, which holds the turn so it can glide back. " ..
		"For that moment, an attack with no target can go to the enemy in front of you; if a fight starts " ..
		"while you're turned, it stays on till the fight ends. Off: it snaps back, and soft targeting is " ..
		"left alone."]), "check", 16)
	kit.GreyUnless(softGlide, IfTurn)

	Adopt(switch) -- (all of the above onto the first tab)

	-- The Frames tab: built on its own frame, from its top.
	local frames = tabHosts[2]
	local top = CreateFrame("Frame", nil, frames)
	top:SetSize(1, 1)
	top:SetPoint("TOPLEFT", frames, "TOPLEFT", 0, 1)
	local fstack = kit.Stack(top, "check", true)
	-- (Dev only for now: setting the Follow HUD up on the profile, FollowHud.lua.)
	if ns.BuildFollowHudSetup then ns.BuildFollowHudSetup(frames, fstack, kit) end
	local followCheck = fstack:Add(kit.Check(frames, "shoulderCamFrames", L["Frames follow you"],
		L["The frames ticked below slide over to where you are on the screen, and " ..
		"glide back as the camera goes behind you. Edit Mode still places them: this moves them from " ..
		"there."], SaveThen("shoulderCamFrames", UpdateFollow)), "check")
	kit.GreyUnless(followCheck, IfOn)
	local function IfFollow() return ns.PageSetting("shoulderCam") and ns.GetDB().shoulderCamFrames end
	-- (Under it, indented: it adds to it, with Turn to enemy on the first tab. Beside it till
	-- 2026-11-15, it read as a choice between the two: user.)
	local turnFollow = kit.Check(frames, "shoulderCamTargetFollow", L["Frames follow the turn"],
		L["Your cast bar and Personal Resource Display slide along with you as the camera turns toward " ..
		"your target. The game doesn't say how far it turned, so this works it out from where you clicked: " ..
		"picked with Tab, they join in once your mouse passes over it. Experimental: dragging the camera " ..
		"with the mouse loses it till you pick a target again."], SaveThen("shoulderCamTargetFollow", UpdateFollow))
	fstack:Add(turnFollow, "check", 16)
	kit.GreyUnless(turnFollow, function()
		local db = ns.GetDB()
		return ns.PageSetting("shoulderCam") and db.shoulderCamTargetTurn and db.shoulderCamFrames
	end)
	local FRAME_TIP = L["Slides with you. A frame placed on it in Edit Mode slides along with it, ticked or not."]
	local labels = {
		shoulderCamFollowCast = L["Cast bar"],
		shoulderCamFollowPRD = L["Personal Resource Display"],
		shoulderCamFollowSwing = L["Swing timers"],
		shoulderCamFollowEssential = L["Cooldowns: essential"],
		shoulderCamFollowUtility = L["Cooldowns: utility"],
		shoulderCamFollowBuffIcons = L["Tracked buffs: icons"],
		shoulderCamFollowBuffBars = L["Tracked buffs: bars"],
		shoulderCamFollowSpellAlerts = L["Spell alerts"],
	}
	local height = fstack:Add(kit.Slider(frames, "shoulderCamFramesHeight", L["Height (all)"], -200, 200, 5, "%+d"),
		"slider")
	kit.Tooltip(height, L["Raises (or lowers) all the ticked frames together while the camera is over your " ..
		"shoulder; they glide back down as it goes behind you. Each one's own slider, on its row, adds to this."])
	kit.GreyUnless(height, IfFollow)
	-- (Its own line under Height (all), each with its name: user, 2026-11-15.)
	local strength = fstack:Add(kit.Slider(frames, "shoulderCamFramesStrength", L["Follow strength"], 0, 200, 5,
		"%d%%", 100), "slider")
	kit.Tooltip(strength, L["How far they slide. Where you are on the screen is worked out from the camera, " ..
		"not read: if they land short of you or past you, turn this up or down."])
	kit.GreyUnless(strength, IfFollow)
	local OWN_TIP = L["This frame's own height, on top of Height (all). A frame placed on it in Edit Mode moves " ..
		"with it."]
	for _, group in ipairs(FOLLOW_GROUPS) do
		local key = group.key
		local check = fstack:Add(kit.Check(frames, key, labels[key], FRAME_TIP,
			SaveThen(key, function()
				UpdateFollow()
				kit.Refresh() -- (its height slider greys out or back)
			end)), "check", 16)
		kit.GreyUnless(check, IfFollow)
		-- (Its own height, on its row: the value to the slider's right.)
		local own = kit.Slider(frames, key .. "Height", "", -100, 100, 5, "%+d")
		own:SetWidth(120)
		own:SetPoint("LEFT", check, "LEFT", 250, 0)
		own.title:ClearAllPoints()
		own.title:SetPoint("LEFT", own, "RIGHT", 8, 0)
		kit.Tooltip(own, OWN_TIP)
		kit.GreyUnless(own, function() return IfFollow() and ns.GetDB()[key] end)
	end

	-- Beside each camera's tick: the seconds it takes to go back behind you as
	-- that camera starts, and back over your shoulder as it ends. Empty: the
	-- usual time (shown greyed in it). Greyed while ticked: no pause then.
	local TIME_TIP = L["How many seconds the camera takes to go back behind you as this camera starts, " ..
		"and back over your shoulder as it ends. Leave it empty for the usual %s seconds."]:format(BLEND_TIME)
	local function TimeBox(parent, check, timeKey, allowKey)
		kit.RecordKey(parent, timeKey)
		local box = ns.SkinEditBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
		box:SetSize(40, 20)
		box:SetAutoFocus(false)
		box:SetMaxLetters(5)
		box:SetJustifyH("RIGHT")
		box:SetPoint("LEFT", check, "LEFT", 250, 0)
		box.settingKey, box.searchLabel = timeKey, L["Transition"]
		local unit = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		unit:SetPoint("LEFT", box, "RIGHT", 4, 0)
		unit:SetText(L["sec"])
		local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("RIGHT", box, "RIGHT", -2, 0)
		hint:SetText(tostring(BLEND_TIME))
		local function Now()
			local seconds = tonumber(ns.GetDB()[timeKey])
			return seconds and tostring(seconds) or ""
		end
		local function Save(self)
			local typed = self:GetText():match("^%s*(.-)%s*$")
			local seconds = tonumber(typed)
			if typed == "" then
				ns.GetDB()[timeKey] = false
			elseif seconds and seconds >= 0 then
				ns.GetDB()[timeKey] = math.min(30, seconds)
			end
			self:SetText(Now())
		end
		box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		box:SetScript("OnEscapePressed", function(self)
			self.cancelled = true
			self:ClearFocus()
		end)
		box:SetScript("OnEditFocusLost", function(self)
			if self.cancelled then
				self.cancelled = nil
				self:SetText(Now())
			else
				Save(self)
			end
		end)
		box:HookScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
		local setEnabled = box.SetEnabled
		function box.SetEnabled(self, enabled)
			if setEnabled then setEnabled(self, enabled) end
			local alpha = enabled and 1 or 0.5
			self:SetAlpha(alpha)
			unit:SetAlpha(alpha)
		end
		box.Refresh = function(self)
			if not self:HasFocus() then self:SetText(Now()) end
		end
		kit.Tooltip(box, TIME_TIP)
		kit.AddControl(box)
		kit.GreyUnless(box, function(db) return IfOn() and not db[allowKey] end)
		return box
	end

	-- The Cameras tab: a tick each for the cameras it stays on through (ALLOW_OF).
	local cams = tabHosts[3]
	local camTop = CreateFrame("Frame", nil, cams)
	camTop:SetSize(1, 1)
	camTop:SetPoint("TOPLEFT", cams, "TOPLEFT", 0, 1)
	local cstack = kit.Stack(camTop, "check", true)
	local allowHead = cstack:Header(cams, L["Allow the Shoulder Cam"])
	cstack:Note(cams, L["Unticked, the camera goes back behind you while that camera plays and comes back over " ..
		"your shoulder as it ends. Ticked, it stays: you keep your spot on the screen as the camera turns round you."],
		440)
	local ALLOW_TIP = L["Keeps the camera over your shoulder while this camera plays."]
	local timeHead
	for _, row in ipairs({
		{ "shoulderCamAllowVista", L["Vista camera"] },
		{ "shoulderCamAllowFish", L["Fish camera"] },
		{ "shoulderCamAllowCozy", L["Cozy camera"] },
		{ "shoulderCamAllowAFK", L["AFK camera"] },
		{ "shoulderCamAllowTele", L["Tele camera"], L["Your Hearthstone and teleports."] },
		{ "shoulderCamAllowFlight", L["Flight camera"], L["Flight paths and their fly-bys. The flight's mount " ..
			"pushes you further aside than your spot, and the frames that follow you don't know by how much yet."] },
		{ "shoulderCamAllowDeath", L["Death camera"], L["While you're dead, until you release."] },
		{ "shoulderCamAllowWalk", L["Walk camera"] },
		{ "shoulderCamAllowRun", L["Auto-run camera"] },
		{ "shoulderCamAllowQuest", L["Quest camera"], L["While you talk to a quest giver."] },
		{ "shoulderCamAllowChat", L["Chat camera"] },
		{ "shoulderCamAllowYours", L["Your own cameras"], L["Your scripts and shots, and cameras started from " ..
			"the camera wheel or a key."] },
	}) do
		local key = row[1]
		local check = kit.Check(cams, key, row[2], row[3] and (ALLOW_TIP .. " " .. row[3]) or ALLOW_TIP,
			SaveThen(key, ns.ApplyShoulderCam))
		kit.GreyUnless(cstack:Add(check, "check"), IfOn)
		local box = TimeBox(cams, check, (key:gsub("Allow", "Time")), key)
		if not timeHead then -- (the column's name, over its first box)
			timeHead = kit.Label(cams, "GameFontNormal", L["Transition"])
			-- (Level with the section's header: the note's between it and the rows.)
			timeHead:SetPoint("TOP", allowHead, "TOP", 0, 0)
			timeHead:SetPoint("LEFT", box, "LEFT", -4, 0)
		end
	end

	-- The Gamepad tab (Forever): not supported at the moment. The game keeps
	-- your character centered while its gamepad UI is on, so the Shoulder Cam
	-- pauses then (PauseReason, "gamepad").
	if ns.BuildShoulderCalibrateTab then ns.BuildShoulderCalibrateTab(tabHosts[calibrateTab], kit) end

	if tabHosts[4] and calibrateTab ~= 4 then
		local pad = tabHosts[4]
		local padTop = CreateFrame("Frame", nil, pad)
		padTop:SetSize(1, 1)
		padTop:SetPoint("TOPLEFT", pad, "TOPLEFT", 0, 1)
		local pstack = kit.Stack(padTop, "check", true)
		pstack:Header(pad, L["Not supported at the moment"])
		pstack:Note(pad, L["The Shoulder Cam doesn't work with the gamepad UI yet. While it's on, the game keeps your " ..
			"character in the middle of the screen, so the Shoulder Cam waits behind you and comes back by itself when " ..
			"you turn the gamepad UI off (Options > Gamepad (Beta) > Enable Gamepad UI)."], 440)
	end

	canvas:SetScript("OnShow", kit.PageShown(function()
		kit.Refresh()
		kit.RefreshKeybinds()
		TabsShown()
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Shoulder Cam")
end
