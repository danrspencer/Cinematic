-- /cine debug namestest [steps]: one run on a player's report (2026-11-14):
-- with Cinematic on, even on Blank Slate, names over heads show only near
-- them, with a band further out where units have no name at all. Stand in a
-- busy city with players near and far on screen; each timed step in the big
-- test box (Frames.lua's ns.PadTestBox) takes a screenshot 3 seconds in, and
-- the log gets every name and plate setting (yours, the game's default,
-- saved by us, which of our sets holds it) and each plate up now (kind,
-- distance, plate and name shown/alpha).
--   1 as is:       Cinematic running as it is now;
--   2 no sight:    Cinematic running, its sight check off (PlateParts.lua's
--                  sight: a name-only plate's name hides while the game dims
--                  its plate, and a new plate's starts hidden till it's
--                  clear). If the game also dims plates by distance, the
--                  band past ~28 yards has plates (so no game names) and no
--                  names of ours: do they come up in this step?
--   3 paused:      Cinematic stopped (ns.Suspend, every setting of ours put
--                  back), through step 5, started again as the test ends:
--                  do the far names come back?
--   4 plates off:  friendly nameplates switched off for the step;
--   5 plates on:   friendly nameplates switched on for the step.
-- Each plate's line has its own alpha, sight and our text (2nd report,
-- Ironforge 2026-11-14: near names ours, far ones the game's, a band of
-- none between, 9 friendly plates up showing only names). 4 and 5 show the game's own rule: a unit with a plate loses its name over
-- its head. The settings are put back after each. Into its own saved list,
-- CinematicDB.namesTestLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETUP, STEP, SHOT = 12, 10, 4 -- seconds: setup, each step, the screenshot into a step

local FRIEND_PLATES = { "nameplateShowFriends", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNPCs" }

-- The settings logged: every UnitName*/nameplate* one the client lists, else these.
local FALLBACK = { "UnitNameOwn", "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC",
	"UnitNameFriendlySpecialNPCName", "UnitNameNonCombatCreatureName", "UnitNameFriendlyPlayerName",
	"UnitNameEnemyPlayerName", "UnitNamePlayerGuild", "UnitNamePlayerPVPTitle", "UnitNameFocused",
	"UnitNameFriendlyMinionName", "UnitNameFriendlyPetName", "UnitNameEnemyMinionName", "UnitNameForceHideMinus",
	"nameplateShowAll", "nameplateShowFriends", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNPCs",
	"nameplateShowEnemies", "nameplateShowEnemyPlayers", "nameplateShowOnlyNames",
	"nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateForceShowUnitName", "nameplateMaxDistance",
	"nameplateShowOffscreen", "nameplateOccludedAlphaMult" }

local STEPS = {
	{ key = "as is", say = "%d/%d: AS IS. Don't move. Screenshot in %d sec." },
	{ key = "no sight", say = "%d/%d: Cinematic's SIGHT CHECK OFF for this step. Don't move. Screenshot in %d sec." },
	{ key = "paused", say = "%d/%d: Cinematic PAUSED (a red chat line says so, it starts again after). " ..
		"Don't move. Screenshot in %d sec." },
	{ key = "plates off", say = "%d/%d: Friendly NAMEPLATES OFF for this step. Don't move. Screenshot in %d sec." },
	{ key = "plates on", say = "%d/%d: Friendly NAMEPLATES ON for this step. Don't move. Screenshot in %d sec." },
}

local run -- { at, steps, step, undo, notes }

local function Say(text)
	local log = CinematicDB and CinematicDB.namesTestLog
	if log then
		log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text)
	end
end

local function Plain(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end

local function Call(f, ...)
	if not f then return nil end
	local ok, a, b = pcall(f, ...)
	if ok then return a, b end
	return nil
end

-- Our own function calling Screenshot (handed to a timer it's refused).
local function Shot(what)
	ns.PadTestBoxHide()
	local ok, err = pcall(function() Screenshot() end)
	return ok and ("screenshot %s at %s"):format(what, date("%m%d%y_%H%M%S")) or ("screenshot failed: " .. tostring(err))
end

local function CVarNames()
	local names, seen = {}, {}
	local all = C_Console and Call(C_Console.GetAllCommands)
	if type(all) == "table" then
		for _, info in ipairs(all) do
			local name = type(info) == "table" and info.command
			if type(name) == "string" and (name:find("^UnitName") or name:find("^nameplateShow")
				or name:find("^nameplateForceShow") or name == "nameplateMaxDistance") and not seen[name:lower()] then
				seen[name:lower()] = true
				names[#names + 1] = name
			end
		end
	end
	for _, name in ipairs(FALLBACK) do
		if not seen[name:lower()] and GetCVar(name) ~= nil then
			seen[name:lower()] = true
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

-- Every name and plate setting: its value, and where it isn't the game's
-- default, the default; saved by us, held by which set, kept as yours.
local function LogCVars(title)
	Say("  " .. title .. " (value [default] [saved by us] [held by] [kept yours]):")
	local db = ns.db or {}
	local line = {}
	for _, name in ipairs(CVarNames()) do
		local value = GetCVar(name)
		local default = Call(GetCVarDefault, name)
		local parts = { name .. "=" .. Plain(value) }
		if default ~= nil and tostring(default) ~= tostring(value) then parts[#parts + 1] = "[default " .. Plain(default) .. "]" end
		local saved = db.savedCVars and db.savedCVars[name]
		if saved ~= nil then parts[#parts + 1] = "[saved " .. Plain(saved) .. "]" end
		local holder = ns.CVarHolder and ns.CVarHolder(name)
		if holder then parts[#parts + 1] = "[held: " .. tostring(holder.label) .. "]" end
		if db.cvarsLeftAlone and db.cvarsLeftAlone[name] then parts[#parts + 1] = "[kept yours]" end
		line[#line + 1] = table.concat(parts, " ")
		if #line == 4 then
			Say("    " .. table.concat(line, ", "))
			line = {}
		end
	end
	if #line > 0 then Say("    " .. table.concat(line, ", ")) end
end

local function LogState()
	local db = ns.db or {}
	Say(("  state: profile %s, enabled %s, CineMode %s, paused %s, Nameplates page %s, outside CineMode %s, " ..
		"Chat Cam immersive %s, Name Style %s, combat %s"):format(tostring(ns.ActiveProfile and ns.ActiveProfile()),
		tostring(db.enabled), tostring(ns.lastCinematic), tostring(ns.IsSuspended and ns.IsSuspended()),
		tostring(db.handlePlates), tostring(db.outsideCinePlates),
		tostring(ns.ChatCamImmersive and ns.ChatCamImmersive() or false), tostring(db.plateNameStyle),
		tostring(InCombatLockdown())))
	local held = {}
	for _, set in ipairs(ns.cvarSets or {}) do
		if set.active then held[#held + 1] = tostring(set.label) end
	end
	Say("  our sets holding now: " .. (#held > 0 and table.concat(held, "; ") or "none"))
end

local function Kind(unit)
	local player = Call(UnitIsPlayer, unit)
	local friend = Call(UnitIsFriend, "player", unit)
	local reaction = Call(UnitReaction, unit, "player")
	return ("%s %s%s"):format(Plain(friend) == "true" and "friendly" or (Plain(friend) == "false" and "hostile" or "?"),
		Plain(player) == "true" and "player" or "npc", reaction and (" r" .. Plain(reaction)) or "")
end

local function Distance(unit)
	local squared, checked = Call(UnitDistanceSquared, unit)
	if type(squared) == "number" and not (issecretvalue and issecretvalue(squared)) and checked then
		return ("%.0fyd"):format(math.sqrt(squared))
	end
	-- (Bands: 3 = 10 yards, 4 = 28.)
	for _, band in ipairs({ { 3, "<10yd" }, { 4, "<28yd" } }) do
		if Call(CheckInteractDistance, unit, band[1]) == true then return band[2] end
	end
	return ">28yd?"
end

local function Visible(region)
	if not region then return "none" end
	if region.IsForbidden and Call(region.IsForbidden, region) then return "forbidden" end
	return ("%s a%s"):format(Plain(Call(region.IsVisible, region)), Plain(Call(region.GetEffectiveAlpha, region)))
end

-- Each plate up now: its unit's kind and distance, the plate and its name.
local function LogPlates()
	local plates = C_NamePlate and Call(C_NamePlate.GetNamePlates) or {}
	local named, total = 0, 0
	Say(("  plates up: %d"):format(#plates))
	for i, plate in ipairs(plates) do
		total = total + 1
		local forbidden = plate.IsForbidden and Call(plate.IsForbidden, plate)
		if forbidden then
			Say(("    %d: forbidden plate"):format(i))
		else
			local frame = plate.UnitFrame
			local unit = plate.namePlateUnitToken or (frame and frame.unit)
			local name = frame and frame.name
			local alpha = name and Call(name.GetEffectiveAlpha, name)
			alpha = type(alpha) == "number" and not (issecretvalue and issecretvalue(alpha)) and alpha or 1
			-- (Ours counts too: the game's own sits at 0 under it, PlateParts.lua.)
			local okSight, sightInfo, ours = false, nil, false
			if ns.DescribePlateSight then okSight, sightInfo, ours = pcall(ns.DescribePlateSight, plate) end
			local nameShown = name and Call(name.IsVisible, name) == true and alpha > 0.05 or (okSight and ours)
			if nameShown then named = named + 1 end
			Say(("    %d: %s, %s, plate %s, name %s, bar %s | %s"):format(i,
				unit and Kind(unit) or "no unit", unit and Distance(unit) or "?", Visible(plate), Visible(name),
				Visible(frame and (frame.healthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar))),
				okSight and tostring(sightInfo) or "no sight info"))
		end
	end
	return named, total
end

-- Sets settings for a step; returns how to put them back.
local function SetCVars(names, value)
	local old = {}
	for _, name in ipairs(names) do
		local now = GetCVar(name)
		if now ~= nil then
			old[name] = now
			if not pcall(SetCVar, name, value) then Say("  couldn't set " .. name) end
		end
	end
	return function()
		for name, was in pairs(old) do pcall(SetCVar, name, was) end
	end
end

-- Steps 3 to 5 run with Cinematic stopped, started again as the test ends:
-- 4 and 5 only ask the game, and with CineMode holding the plate settings
-- it saved the test's 0 as yours (2026-11-14 run: friendly plates saved 0).
local function Pause(why)
	if ns.Suspend and not (ns.IsSuspended and ns.IsSuspended()) then
		ns.Suspend(why)
		run.paused = true
	end
end
local APPLY = {
	["as is"] = function() return nil end,
	["no sight"] = function()
		ns.namesTestNoSight = true
		return function() ns.namesTestNoSight = nil end
	end,
	["paused"] = function() Pause("names test, step 3") end,
	["plates off"] = function()
		Pause("names test, step 4")
		return SetCVars(FRIEND_PLATES, "0")
	end,
	["plates on"] = function()
		Pause("names test, step 5")
		return SetCVars(FRIEND_PLATES, "1")
	end,
}

local function Undo()
	if run and run.undo then
		local ok, err = pcall(run.undo)
		Say("  put back" .. (ok and "" or (": " .. tostring(err))))
		run.undo = nil
	end
end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	Undo()
	if run.paused and ns.Resume then
		ns.Resume()
		Say("  Cinematic started again")
	end
	for _, index in ipairs(run.steps) do
		local note = run.notes[index] or {}
		local line = ("%d %s: %s"):format(index, STEPS[index].key, note.shot and
			("%d of %d plates with a name showing; %s"):format(note.named or 0, note.total or 0, note.shot) or "not run")
		Say("verdict " .. line)
	end
	LogCVars("settings after")
	run = nil
	ns.PadTestBox(done and "Names test done." or "Names test stopped.",
		"/reload, then say \"check log\" (the screenshots tell me the rest)", 1, 0.82, 0)
	C_Timer.After(15, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local now = GetTime() - run.at
	if now < SETUP then
		ns.PadTestBox("Stand in a BUSY CITY, zoomed out, looking down a street with players and NPCs both NEAR and " ..
			"FAR (60+ yards). Out of combat. Then don't move or turn till the end.",
			("Starts in %d"):format(math.ceil(SETUP - now)), 1, 0.82, 0)
		return
	end
	local index = math.floor((now - SETUP) / STEP) + 1
	if index > #run.steps then
		Finish(true)
		return
	end
	local number = run.steps[index]
	local step = STEPS[number]
	local into = now - SETUP - (index - 1) * STEP
	if index ~= run.step then
		Undo()
		run.step = index
		run.notes[number] = {}
		Say(("--- step %d: %s ---"):format(number, step.key))
		local ok, undo = pcall(APPLY[step.key])
		if not ok then Say("  error: " .. tostring(undo)) else run.undo = undo end
	end
	local note = run.notes[number]
	if into < SHOT then
		ns.PadTestBox(step.say:format(index, #run.steps, math.ceil(SHOT - into)), "GET READY: don't move", 1, 0.82, 0)
	elseif not note.shot then
		note.shot = Shot(("step %d %s"):format(number, step.key))
		Say("  " .. note.shot)
		LogState()
		LogCVars("settings now")
		note.named, note.total = LogPlates()
	else
		ns.PadTestBox(step.say:format(index, #run.steps, 0), ("RECORDED. Next in %d"):format(math.ceil(STEP - into)),
			0.3, 1, 0.3)
	end
end

-- Typed again while running: stops.
function ns.NamesTest(args)
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("names test: out of combat please (plate settings can't change in a fight).")
		return
	end
	local steps = {}
	for number in (args or ""):gmatch("%d+") do
		number = tonumber(number)
		if STEPS[number] then steps[#steps + 1] = number end
	end
	if #steps == 0 then
		for i = 1, #STEPS do steps[i] = i end
	end
	CinematicDB.namesTestLog = {}
	run = { at = GetTime(), steps = steps, step = -1, notes = {} }
	Say(("start: %s (game %s), Cinematic %s, steps %s"):format(ns.isRetail and "retail" or "not retail",
		tostring((select(4, GetBuildInfo()))), tostring(C_AddOns and C_AddOns.GetAddOnMetadata and Call(C_AddOns.GetAddOnMetadata, "Cinematic", "Version")), table.concat(steps, " ")))
	LogState()
	LogCVars("settings at start")
	run.ticker = C_Timer.NewTicker(0.5, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print(("names test: %d sec, follow the box (type it again to stop)"):format(SETUP + #steps * STEP))
end
