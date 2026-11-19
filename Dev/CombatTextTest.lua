-- /cine debug cttest [steps]: which way of moving the game's floating combat
-- text works (Shoulder Cam's "Floating combat text" row, 2026-11-18). Its
-- messages have a secret text and place on Forever, and hanging them on a
-- stand-in hid them. So one run tries each way in turn, each step just "heal
-- yourself": the text is pushed 300 UI units right of the middle (Shoulder
-- Cam not needed), a screenshot is taken 0.5 s after each heal or hit on you,
-- and the step's own numbers go in the log (SetPoint calls the hook saw, how
-- many it moved, secret places, errors, what the texts hang on).
--   1 game     nothing moved: the text where the game puts it (to compare with)
--   2 sum      put again with the push added to the game's x, y (skipped when secret)
--   3 adjust   AdjustPointsOffset by the push (the game sums it)
--   4 stand    hung on a stand-in frame over the game's, pushed
--   5 frame    the CombatText frame itself pushed (moves them if they hang on it)
--   6 table    the game's start and end places (COMBAT_TEXT_LOCATIONS) pushed
-- Into CinematicDB.combatTextTestLog. Puts everything back after each step.
-- Dev copy only.
local _, ns = ...

local PUSH = 300  -- UI units right of where the game puts it
local WAIT = 4    -- seconds to read a step
local STEP = 16   -- seconds a step lasts in all

local STEPS = {
	{ key = "game", say = "the game's own place: the text should be in the MIDDLE" },
	{ key = "sum", say = "way 2 of 6: the text should be far RIGHT of the middle" },
	{ key = "adjust", say = "way 3 of 6: the text should be far RIGHT of the middle" },
	{ key = "stand", say = "way 4 of 6: the text should be far RIGHT of the middle" },
	{ key = "frame", say = "way 5 of 6: the text should be far RIGHT of the middle" },
	{ key = "table", say = "way 6 of 6: the text should be far RIGHT of the middle" },
}

local run -- { at, steps, step, notes, ticker, keptCT, keptTable }

local function Say(text)
	local log = CinematicDB and CinematicDB.combatTextTestLog
	if log then log[#log + 1] = ("%s %.1f %s"):format(date("%H:%M:%S"), run and GetTime() - run.at or 0, text) end
end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function T(v)
	if Secret(v) then return "secret" end
	if type(v) == "number" then return ("%.1f"):format(v) end
	if type(v) == "table" then
		local ok, name = pcall(function() return v.GetName and v:GetName() end)
		return ok and name and not Secret(name) and tostring(name) or "table"
	end
	return tostring(v)
end
local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Say(("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end

-- The texts showing now: words, place, what they hang on (each value plain or "secret").
local function Showing()
	local frame = _G.CombatText
	if type(frame) ~= "table" then return end
	for i, r in ipairs({ frame:GetRegions() }) do
		local shown = r.IsShown and r:IsShown()
		if Secret(shown) or shown then
			local okText, text = pcall(r.GetText, r)
			local ok, point, to, relPoint, x, y = pcall(r.GetPoint, r, 1)
			local okLeft, left = pcall(r.GetLeft, r)
			Say(("  text %d: %s at %s %s %s %s %s left %s alpha %s hooked %s"):format(i, okText and T(text) or "error",
				ok and T(point) or "error", T(to), T(relPoint), T(x), T(y), okLeft and T(left) or "error",
				T(r:GetAlpha()), tostring(ns.CombatTextFollow.Hooked(r))))
		end
	end
end

-- What the game's combat text has to work with, once at the start.
local function Survey()
	local frame = _G.CombatText
	Say(("CombatText %s, loaded %s, enableFloatingCombatText %s, texts %s"):format(type(frame),
		tostring(C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_CombatText")),
		T(GetCVar("enableFloatingCombatText")), tostring(ns.CombatTextFollow.HookTexts())))
	if type(frame) == "table" then
		local okPoint, point, to, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
		Say(("  frame at %s %s %s %s %s, %s points, size %s x %s, OnUpdate %s, protected %s"):format(
			okPoint and T(point) or "error", T(to), T(relPoint), T(x), T(y), T(frame:GetNumPoints()),
			T(frame:GetWidth()), T(frame:GetHeight()), tostring(frame:GetScript("OnUpdate") ~= nil),
			T(frame:IsProtected())))
		local region = select(1, frame:GetRegions())
		Say("  AdjustPointsOffset on its texts: " .. tostring(region and region.AdjustPointsOffset ~= nil))
	end
	for _, name in ipairs({ "COMBAT_TEXT_LOCATIONS", "CombatText_StandardScroll", "CombatText_AddMessage",
		"CombatText_OnUpdate", "COMBAT_TEXT_SCROLLSPEED", "COMBAT_TEXT_X_ADJUSTMENT", "COMBAT_TEXT_Y_SCALE",
		"COMBAT_TEXT_TO_ANIMATE", "COMBAT_TEXT_FLOAT_MODE" }) do
		Say(("  %s: %s"):format(name, type(_G[name]) == "table" and "table" or T(_G[name])))
	end
	if type(_G.COMBAT_TEXT_LOCATIONS) == "table" then
		for key, value in pairs(_G.COMBAT_TEXT_LOCATIONS) do Say(("    COMBAT_TEXT_LOCATIONS.%s = %s"):format(T(key), T(value))) end
	end
end

-- A step's own setup and putting it back (frame, table); the hook's way for the rest.
local function Begin(key)
	local follow = ns.CombatTextFollow
	follow.ResetStats()
	follow.testShift = PUSH
	follow.method = (key == "sum" or key == "adjust" or key == "stand") and key or nil
	if key == "frame" then
		local frame = _G.CombatText
		local points = {}
		for i = 1, frame:GetNumPoints() do points[i] = { frame:GetPoint(i) } end
		run.keptCT = points
		frame:ClearAllPoints()
		for _, p in ipairs(points) do frame:SetPoint(p[1], p[2], p[3], (p[4] or 0) + PUSH, p[5] or 0) end
		return ("pushed the frame (%d points)"):format(#points)
	elseif key == "table" then
		local places = _G.COMBAT_TEXT_LOCATIONS
		if type(places) ~= "table" then return "no COMBAT_TEXT_LOCATIONS on this client" end
		run.keptTable = { startX = places.startX, endX = places.endX }
		for _, field in ipairs({ "startX", "endX" }) do
			if type(places[field]) == "number" and not Secret(places[field]) then places[field] = places[field] + PUSH end
		end
		return ("pushed startX %s -> %s, endX %s -> %s"):format(T(run.keptTable.startX), T(places.startX),
			T(run.keptTable.endX), T(places.endX))
	end
	return "hook way: " .. tostring(follow.method)
end

local function PutBack()
	local follow = ns.CombatTextFollow
	follow.testShift, follow.method = nil, follow.normal
	if run and run.keptCT then
		local frame = _G.CombatText
		frame:ClearAllPoints()
		for _, p in ipairs(run.keptCT) do frame:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
		run.keptCT = nil
	end
	if run and run.keptTable then
		local places = _G.COMBAT_TEXT_LOCATIONS
		places.startX, places.endX = run.keptTable.startX, run.keptTable.endX
		run.keptTable = nil
	end
end

local function Verdict(index)
	local step = STEPS[index]
	local note = run.notes[index]
	if not note then return end
	local stats = ns.CombatTextFollow.stats
	local verdict
	if note.hits == 0 then
		verdict = "NO HEAL OR HIT SEEN (redo: /cine debug cttest " .. index .. ")"
	elseif stats.err then
		verdict = "ERROR " .. stats.err
	elseif ns.CombatTextFollow.method and stats.slid == 0 then
		verdict = "NOT MOVED (" .. (stats.skipped > 0 and "every place was secret" or "the hook never moved one") .. ")"
	else
		verdict = "ran; see the screenshot"
	end
	Say(("verdict %d %s: %s | heals/hits %d, in combat %s, SetPoint seen %d, moved %d, secret places %d, skipped %d, hang on %s; %s"):format(
		index, step.key, verdict, note.hits, tostring(note.combat), stats.seen, stats.slid, stats.secret, stats.skipped,
		tostring(stats.anchor), note.setup or "-"))
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function()
	if not (run and run.recording) then return end
	local index = run.step
	local note = run.notes[index]
	note.hits = note.hits + 1
	note.combat = note.combat or InCombatLockdown()
	if note.hits <= 2 then
		local hit = note.hits
		C_Timer.After(0.5, function()
			if run and run.step == index then
				Say(("step %d %s, heal/hit %d:"):format(index, STEPS[index].key, hit))
				pcall(Showing)
				Shot(("step %d %s hit %d"):format(index, STEPS[index].key, hit))
			end
		end)
	end
end)

local function Finish(done)
	if not run then return end
	if run.step and run.notes[run.step] then Verdict(run.step) end
	PutBack()
	if run.ticker then run.ticker:Cancel() end
	watcher:UnregisterAllEvents()
	run = nil
	ns.PadTestBox(done and "Combat text test done. /reload, then say \"check log\"." or "Combat text test stopped.", "",
		1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local now = GetTime() - run.at
	local slot = math.floor(now / STEP) + 1
	if slot > #run.steps then
		Finish(true)
		return
	end
	local index = run.steps[slot]
	local into = now - (slot - 1) * STEP
	if index ~= run.step then
		if run.step and run.notes[run.step] then Verdict(run.step) end
		PutBack()
		run.step, run.recording = index, false
		run.notes[index] = { hits = 0 }
		Say(("--- step %d %s (in combat %s) ---"):format(index, STEPS[index].key, tostring(InCombatLockdown())))
		local ok, setup = pcall(Begin, STEPS[index].key)
		run.notes[index].setup = ok and setup or ("setup error: " .. tostring(setup))
		Say("  " .. run.notes[index].setup)
	end
	local say = ("Step %d of %d: HEAL YOURSELF (or take a hit).\n%s"):format(slot, #run.steps, STEPS[index].say)
	if into < WAIT then
		ns.PadTestBox(say, ("GET READY: starts in %d"):format(math.ceil(WAIT - into)), 1, 0.82, 0)
	else
		run.recording = true
		ns.PadTestBox(say, ("RECORDING: %d sec left"):format(math.ceil(STEP - into)), 0.3, 1, 0.3)
	end
end

function ns.CombatTextTest(args)
	if run then
		Finish(false)
		return
	end
	if not ns.CombatTextFollow then
		ns.Print("combat text test: Shoulder Cam isn't loaded")
		return
	end
	local steps = {}
	for number in (args or ""):gmatch("%d+") do
		number = tonumber(number)
		if STEPS[number] then steps[#steps + 1] = number end
	end
	if #steps == 0 then for i = 1, #STEPS do steps[i] = i end end
	CinematicDB.combatTextTestLog = {}
	run = { at = GetTime(), steps = steps, notes = {} }
	Say(("start: %s (game %s), in combat %s, steps %s"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), tostring(InCombatLockdown()), table.concat(steps, " ")))
	pcall(Survey)
	watcher:RegisterUnitEvent("UNIT_COMBAT", "player")
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			Finish(false)
		end
	end)
end
