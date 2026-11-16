-- /cine debug followtest: one run checking the Follow HUD in the game
-- (FollowHud.lua), both roots, on the profile you're on. Each Set Up makes
-- its Edit Mode layout again, which needs a reload (Layouts.lua madeNow), so
-- the run goes across two reloads by itself (CinematicDB.followTest keeps
-- where it is): you click Reload on the game's window and it goes on.
--   start:   what you have now noted (profile, layout, the layout's every
--            frame), then Set Up with the personal resource display root;
--   1 still: out of a fight, no target: where the frames are, and which of
--            the layout's frames differ from yours (only the Follow HUD's
--            should);
--   2 enemy: an enemy targeted: the personal resource display up, your
--            portrait down (CineMode on); then Set Up with the player frame;
--   3 still: the player frame's place, clear of the swing timers and cast bar;
--   4 enemy: the player frame up;
--   end:     put back as it was (Undo, or your own Set Up again), and checked:
--            your own layout on again and untouched, the settings back.
-- A screenshot each step (the box hidden for it), named in the log; a
-- verdict per check. Into its own saved list, CinematicDB.followTestLog.
-- Dev copy only (CinematicDev.toc).
local _, ns = ...

local WAIT, STEP = 4, 14 -- seconds: to read the box, each step
local RESUME = 6 -- seconds after the reload before it goes on

local run -- { stage, step, at, ticker }

local function Saved() return CinematicDB and CinematicDB.followTest end

local function Log(text)
	local log = CinematicDB and CinematicDB.followTestLog
	if not log then return end
	local saved = Saved()
	log[#log + 1] = ("%s %s"):format(saved and saved.stage or "-", text)
end

local function Bool(value) return value and "yes" or "no" end
local function Num(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.1f"):format(value) end
	return tostring(value)
end
local function Plain(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value)) and value or nil
end

local function Verdict(name, ok, detail)
	Log(("VERDICT %s: %s%s"):format(name, ok == nil and "CAN'T TELL" or (ok and "PASS" or "FAIL"),
		detail and (" (" .. detail .. ")") or ""))
end

local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	Log(ok and ("screenshot %s at %s"):format(what, date("%m%d%y_%H%M%S")) or "screenshot failed")
end

-- A frame's place on the screen in UI units from the bottom middle: its
-- middle x, its bottom and top, its width; nil when it can't be read.
local function Place(frame)
	if not (frame and frame.GetRect) then return nil end
	local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
	left, bottom, width, height = Plain(left), Plain(bottom), Plain(width), Plain(height)
	if not (ok and left and bottom and width and height) then return nil end
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local middle = UIParent:GetWidth() / 2
	return { x = (left + width / 2) * scale - middle, bottom = bottom * scale, top = (bottom + height) * scale,
		width = width * scale }
end
local function PlaceText(place)
	if not place then return "not readable" end
	return ("x %s, bottom %s, top %s, width %s"):format(Num(place.x), Num(place.bottom), Num(place.top),
		Num(place.width))
end
local function Alpha(frame)
	if not frame then return nil end
	local okShown, shown = pcall(frame.IsVisible, frame)
	local okAlpha, alpha = pcall(frame.GetEffectiveAlpha, frame)
	if not (okShown and okAlpha) then return nil end
	if shown ~= true then return 0 end
	return Plain(alpha)
end

local FRAMES = {
	{ "PRD", "PersonalResourceDisplayFrame" },
	{ "cast bar", "PlayerCastingBarFrame" },
	{ "essential row", "EssentialCooldownViewer" },
	{ "utility row", "UtilityCooldownViewer" },
	{ "main hand swing", "SwingTimerMainHandFrame" },
	{ "off hand swing", "SwingTimerOffHandFrame" },
	{ "ranged swing", "SwingTimerRangedFrame" },
	{ "player frame", "PlayerFrame" },
	{ "target frame", "TargetFrame" },
}
local function LogPlaces()
	local places = {}
	for _, entry in ipairs(FRAMES) do
		local frame = _G[entry[2]]
		places[entry[1]] = Place(frame)
		Log(("  %s: %s, shown %s, alpha %s"):format(entry[1], PlaceText(places[entry[1]]),
			frame and Bool(frame:IsShown()) or "no frame", Num(Alpha(frame))))
	end
	return places
end

-- A layout's frames as text, one line each by system:index (nil: not one of
-- the saved ones, a preset).
local function Frames(name)
	if not (C_EditMode and C_EditMode.GetLayouts and name) then return nil end
	for _, layout in ipairs(C_EditMode.GetLayouts().layouts) do
		if layout.layoutName == name then
			local out = {}
			for _, system in ipairs(layout.systems or {}) do
				local anchor = system.anchorInfo or {}
				local settings = {}
				for _, setting in ipairs(system.settings or {}) do
					settings[#settings + 1] = tostring(setting.setting) .. "=" .. tostring(setting.value)
				end
				table.sort(settings)
				out[tostring(system.system) .. ":" .. tostring(system.systemIndex)] = ("%s %s %s %s %s|%s"):format(
					tostring(anchor.point), tostring(anchor.relativeTo), tostring(anchor.relativePoint),
					Num(anchor.offsetX), Num(anchor.offsetY), table.concat(settings, ","))
			end
			return out
		end
	end
	return nil
end

-- The Follow HUD's frames differing from yours: only its own should.
local function CheckLayout(picks)
	local base = ns.chardb and ns.chardb.followHudBase
	local ours, theirs = Frames("Follow HUD"), Frames(base)
	Log(("layout: on %s, made on %s"):format(tostring(ns.ActiveLayoutName()), tostring(base)))
	Verdict("on the Follow HUD layout", ns.ActiveLayoutName() == "Follow HUD", tostring(ns.ActiveLayoutName()))
	if not (ours and theirs) then
		Verdict("only the Follow HUD's frames changed", nil,
			not ours and "no Follow HUD layout" or (tostring(base) .. " is one of the game's own: not compared"))
		return
	end
	local expected = {}
	for _, row in ipairs(ns.FollowHudDesign(picks)) do expected[tostring(row[1]) .. ":" .. tostring(row[2])] = true end
	local changed, wrong = {}, {}
	for key, text in pairs(ours) do
		if theirs[key] ~= text then
			changed[#changed + 1] = key
			if not expected[key] then wrong[#wrong + 1] = key end
			Log(("  %s: yours %s, Follow HUD %s"):format(key, tostring(theirs[key]), text))
		end
	end
	table.sort(changed)
	table.sort(wrong)
	Verdict("only the Follow HUD's frames changed", #wrong == 0,
		("changed %s; not its own: %s"):format(table.concat(changed, " "), #wrong > 0 and table.concat(wrong, " ") or "none"))
end

-- The run's state each step: CineMode, the fight, the target.
local function LogState()
	local hostile = UnitExists("target") and UnitCanAttack("player", "target")
	Log(("CineMode %s, Shoulder Cam %s, in combat %s, target %s (enemy %s), profile %s, prdOn %s, nameplateShowSelf %s"):format(
		Bool(ns.lastCinematic), Bool(ns.db.shoulderCam), Bool(InCombatLockdown()), tostring(UnitName("target")), Bool(hostile),
		tostring(ns.ActiveProfile()), tostring(ns.db.prdOn), tostring(GetCVar("nameplateShowSelf"))))
	return hostile
end

local STEPS
local function Finish(text, sub)
	if run and run.ticker then run.ticker:Cancel() end
	run = nil
	ns.PadTestBox(text, sub, 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
end

-- Set Up, its reload offered by the game's window: the run goes on after it.
local function SetUp(picks, nextStage)
	local ok, reason = ns.FollowHudSetUp(picks)
	Log(("set up root %s: %s"):format(tostring(picks.root), ok and "done" or ("not done, " .. tostring(reason))))
	if not ok then
		Saved().stage = nil
		Finish("Test stopped: the Follow HUD couldn't be set up.", tostring(reason) .. ". Say 'check log'.")
		return
	end
	Saved().stage = nextStage
	if run and run.ticker then run.ticker:Cancel() end
	run = nil
	ns.PadTestBox("Click RELOAD on the game's window (or type /reload).",
		"The test goes on by itself a few seconds after.", 1, 0.82, 0)
end

-- Put back as it was, then checked once the layout's switched back.
local function PutBack()
	local saved = Saved()
	local ok, reason
	if saved.oldPicks then
		ok, reason = ns.FollowHudSetUp(saved.oldPicks)
	else
		ok, reason = ns.FollowHudUndo()
	end
	Log(("put back (%s): %s"):format(saved.oldPicks and "your own Set Up again" or "Undo",
		ok and "done" or ("not done, " .. tostring(reason))))
	ns.PadTestBox("Putting things back as they were...", "Stand still for a few seconds.", 1, 1, 1)
	local tries = 0
	local function Check()
		tries = tries + 1
		local before = saved.before
		local active = ns.ActiveLayoutName()
		if active ~= before.layout and tries < 40 and not saved.oldPicks then
			C_Timer.After(0.5, Check)
			return
		end
		Log(("after: profile %s, layout %s, prdOn %s"):format(tostring(ns.ActiveProfile()), tostring(active),
			tostring(ns.db.prdOn)))
		Verdict("your layout on again", saved.oldPicks and nil or active == before.layout,
			("was %s, now %s"):format(tostring(before.layout), tostring(active)))
		local now = Frames(before.layout)
		local same = true
		if now and before.frames then
			for key, text in pairs(before.frames) do
				if now[key] ~= text then same = false; Log(("  %s: was %s, now %s"):format(key, text, tostring(now[key]))) end
			end
		end
		Verdict("your layout untouched", (now and before.frames) and same or nil,
			not (now and before.frames) and "one of the game's own: not compared" or nil)
		local back = true
		for key, value in pairs(before.settings) do
			local now = ns.SerialValue(ns.db[key])
			if now ~= value then back = false; Log(("  %s: was %s, now %s"):format(key, value, now)) end
		end
		Verdict("settings back as they were", saved.oldPicks and nil or back)
		saved.stage = nil
		Finish("Test done. Type /reload to save it, then say 'check log'.")
	end
	C_Timer.After(1, Check)
end

local SETTINGS = { "prdOn", "combatShow", "enemyShow", "prHealthPlayer", "prPowerPlayer", "prHealthPrd", "prPowerPrd",
	"shoulderCamFrames", "editModeLayout" }

STEPS = {
	{ say = "%d/4: Stand STILL, OUT OF A FIGHT, with NO TARGET (Escape clears it). CineMode ON.",
		check = function(picks)
			LogState()
			CheckLayout(picks)
			local places = LogPlaces()
			local prd, cast = places["PRD"], places["cast bar"]
			-- (Lined up, not "in the middle": over your shoulder Frames follow you slides them aside.)
			Verdict("cast bar lined up over the PRD", (prd and cast) and math.abs(cast.x - prd.x) < 2
				and cast.bottom >= prd.top - 1 or nil, (prd and cast) and ("x %s and %s"):format(Num(prd.x), Num(cast.x)) or nil)
			Shot("1 prd still")
		end },
	{ say = "%d/4: TARGET AN ENEMY (a red name) but DON'T attack it. Stand still. CineMode ON.",
		check = function(picks)
			local hostile = LogState()
			LogPlaces()
			local prd, player = Alpha(_G.PersonalResourceDisplayFrame), Alpha(_G.PlayerFrame)
			local tell = hostile and ns.lastCinematic
			Verdict("PRD up with an enemy targeted", tell and (prd or 0) > 0.5 or nil, Num(prd))
			-- (Only with In place of your portrait picked: else your portrait's the profile's.)
			if picks and picks.noPortrait then
				Verdict("your portrait down with an enemy targeted", tell and (player or 1) < 0.5 or nil, Num(player))
			else
				Log(("your portrait (the profile's to say): alpha %s"):format(Num(player)))
			end
			Shot("2 prd enemy")
		end,
		after = function()
			local picks = ns.FollowHudDefaultPicks()
			picks.root = "player"
			SetUp(picks, "player")
		end },
	{ say = "%d/4: CLEAR YOUR TARGET (Escape) and stand STILL, out of a fight. CineMode ON.",
		check = function(picks)
			LogState()
			CheckLayout(picks)
			local places = LogPlaces()
			local player, cast = places["player frame"], places["cast bar"]
			local lowest = cast and cast.bottom
			for _, name in ipairs({ "main hand swing", "off hand swing", "ranged swing" }) do
				local swing = places[name]
				if swing and swing.width > 1 and (not lowest or swing.bottom < lowest) then lowest = swing.bottom end
			end
			Verdict("player frame in the middle", player and math.abs(player.x) < 2 or nil, player and Num(player.x) or nil)
			Verdict("player frame clear under the cast bar and swing timers", (player and lowest) and player.top <= lowest or nil,
				player and lowest and ("its top %s, lowest above it %s"):format(Num(player.top), Num(lowest)) or nil)
			Shot("3 player still")
		end },
	{ say = "%d/4: TARGET AN ENEMY (a red name) but DON'T attack it. Stand still. CineMode ON.",
		check = function()
			local hostile = LogState()
			LogPlaces()
			local player = Alpha(_G.PlayerFrame)
			Verdict("player frame up with an enemy targeted", hostile and ns.lastCinematic and (player or 0) > 0.5 or nil,
				Num(player))
			Shot("4 player enemy")
		end,
		after = function() PutBack() end },
}

-- A stage's steps in turn: the box up the whole step, the check at its end.
local function RunSteps(first, last)
	local picks = ns.FollowHudPicks()
	run = { step = first, at = GetTime() }
	Log(("set up: %s"):format(ns.SerialValue(picks)))
	run.ticker = C_Timer.NewTicker(0.25, function()
		if not run then return end
		local step = STEPS[run.step]
		local into = GetTime() - run.at
		if into < WAIT then
			ns.PadTestBox(step.say:format(run.step), ("GET READY: starts in %d"):format(math.ceil(WAIT - into)), 1, 0.82, 0)
		elseif into < STEP then
			ns.PadTestBox(step.say:format(run.step), ("CHECKING: %d sec left"):format(math.ceil(STEP - into)), 0.2, 1, 0.2)
		else
			Log(("step %d"):format(run.step))
			local ok, err = pcall(step.check, picks)
			if not ok then Log("step error: " .. tostring(err)) end
			if run.step >= last then
				local after = step.after
				-- (Not in a fight: Set Up and Undo wait for it.)
				if InCombatLockdown() then
					ns.PadTestBox("Leave the fight to go on.", "", 1, 0.3, 0.3)
					return
				end
				run.ticker:Cancel()
				run = nil
				if after then after() end
				return
			end
			run.step, run.at = run.step + 1, GetTime()
		end
	end)
end

function ns.FollowHudTest()
	if run or (Saved() and Saved().stage) then
		if run and run.ticker then run.ticker:Cancel() end
		run = nil
		if Saved() then Saved().stage = nil end
		ns.PadTestBoxHide()
		ns.Print("follow hud test stopped (your Follow HUD set up as the test left it: /cine debug followhud)")
		return
	end
	if InCombatLockdown() then ns.Print("follow hud test: not in a fight") return end
	if not ns.EDIT_MODE_LAYOUTS["Follow HUD"] then ns.Print("follow hud test: no Follow HUD on this client") return end
	CinematicDB.followTestLog = {}
	local settings = {}
	for _, key in ipairs(SETTINGS) do settings[key] = ns.SerialValue(ns.db[key]) end
	local layout = ns.ActiveLayoutName()
	local oldPicks = ns.FollowHudPicks()
	-- (Set up already: the layout it was made on is yours.)
	local mine = oldPicks and ns.chardb.followHudBase or layout
	CinematicDB.followTest = { stage = "start", oldPicks = oldPicks,
		before = { layout = layout, frames = Frames(mine), settings = settings } }
	Log(("start: %s, profile %s, layout %s (yours %s), set up already %s, Shoulder Cam %s"):format(
		date("%Y-%m-%d %H:%M"), tostring(ns.ActiveProfile()), tostring(layout), tostring(mine),
		ns.SerialValue(oldPicks), Bool(ns.db.shoulderCam)))
	SetUp(ns.FollowHudDefaultPicks(), "prd")
end

-- After a reload: on where it was. (On ns for the offline check.)
function ns.FollowHudTestResume()
	local saved = Saved()
	if not (saved and (saved.stage == "prd" or saved.stage == "player")) or run then return end
	C_Timer.After(RESUME, function()
		saved = Saved()
		if not (saved and saved.stage) or run then return end
		Log(("go on after the reload: layout %s"):format(tostring(ns.ActiveLayoutName())))
		if saved.stage == "prd" then RunSteps(1, 2) else RunSteps(3, 4) end
	end)
end
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function() ns.FollowHudTestResume() end)
