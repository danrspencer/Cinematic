-- /cine debug corpse: one run on what addons can learn about a dead mob
-- (2026-11-20). Dead units get no nameplate, and the game draws their names
-- over the body itself (no frame to read), so the only ways in are the unit
-- names the game gives out (target, mouseover, soft interact) and the death
-- itself (the combat log). Steps on screen, each waiting as long as it takes
-- (type the command again to stop):
--   1 kill   target an enemy and kill it (its GUID kept while it lives)
--   2 calm   the fight over: the corpse as your target, a screenshot
--   3 mouse  Esc, mouse over the body: the corpse as mouseover, a screenshot
--   4 soft   mouse off, walk up and right-click it: what soft interact picks
--            on the way, then the loot window or the corpse targeted
--   5 after  loot closed (or 3 s on): the corpse once more, looted
-- Logged: each read (name, GUID, level, dead, tapped, lootable, health,
-- tooltip lines, plate) for each unit name, with <secret> where secret;
-- death lines from the combat log; plates added or removed for it; every
-- client setting with Dead or Corpse in its name. A RESULT line per question
-- at the end, and on screen. Soft interact held on (SoftTargetInteract 3) for
-- the run and put back; CineMode off for the run and put back. Into
-- CinematicDB.corpseLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local CVARS = { "SoftTargetInteract", "SoftTargetEnemy", "SoftTargetFriend", "UnitNameNPC", "UnitNameHostleNPC",
	"nameplateShowEnemies", "nameplateShowAll" }
local SOFT = ns.CVarSet("Corpse test: soft interact", "/cine debug corpse: soft interact on for the run",
	{ values = { SoftTargetInteract = "3" } })
local TOKENS = { "softinteract", "softenemy", "softfriend" }
local AFTER_WAIT = 3 -- seconds after the loot window or the corpse targeted, if no loot window closes
local DEATH_LINES = 40 -- combat log lines kept

local run -- { at, step, guid, name, results, events, ticker, cineWas, soft, deathLines }

local function Say(text)
	local log = CinematicDB and CinematicDB.corpseLog
	if log then log[#log + 1] = ("%.2f %s"):format(run and GetTime() - run.at or 0, text) end
end

local function Secret(value)
	return ns.Check.Secret(value)
end
local function Show(value)
	if Secret(value) then return "<secret>" end
	return tostring(value)
end
-- fn(...) by its path, in a pcall (some reads may be refused on a corpse):
-- its first two returns, or "none" without the function, "error: ..." on one.
local function Ask(path, ...)
	local fn = ns.Check.Api(path)
	if not fn then return "none" end
	local ok, a, b = pcall(fn, ...)
	if not ok then return "error: " .. tostring(a) end
	if b ~= nil then return Show(a) .. "," .. Show(b) end
	return Show(a)
end
local function Guid(unit)
	local ok, guid = pcall(UnitGUID, unit)
	if not ok or Secret(guid) then return nil end
	return guid
end
local function Dead(unit)
	local ok, dead = pcall(UnitIsDead, unit)
	return ok and not Secret(dead) and dead and true or false
end

local function CVarLine()
	local parts = {}
	for _, cvar in ipairs(CVARS) do parts[#parts + 1] = cvar .. "=" .. tostring(GetCVar(cvar)) end
	return table.concat(parts, " ")
end

-- Every client setting with Dead or Corpse in its name, and its value.
local function DeadCVars()
	local list = ns.Check.Api("C_Console.GetAllCommands")
	if not list then return "no list of settings on this client" end
	local ok, commands = pcall(list)
	if not ok or type(commands) ~= "table" then return "the list of settings didn't come" end
	local found = {}
	for _, info in ipairs(commands) do
		local name = type(info) == "table" and info.command
		if type(name) == "string" and (name:lower():find("dead") or name:lower():find("corpse")) then
			found[#found + 1] = name .. "=" .. tostring(GetCVar(name))
		end
	end
	table.sort(found)
	return #found > 0 and table.concat(found, " ") or "none"
end

-- The tooltip's lines for the unit, as the game's tooltip data gives them.
local function TooltipLines(unit)
	local get = ns.Check.Api("C_TooltipInfo.GetUnit")
	if not get then return "no tooltip data on this client" end
	local ok, data = pcall(get, unit)
	if not ok then return "error: " .. tostring(data) end
	if type(data) ~= "table" or type(data.lines) ~= "table" then return "none" end
	local lines = {}
	for _, line in ipairs(data.lines) do
		local left, right = line.leftText, line.rightText
		local text = Show(left)
		if right ~= nil and right ~= "" then text = text .. " | " .. Show(right) end
		lines[#lines + 1] = "'" .. text .. "'"
	end
	return #lines > 0 and table.concat(lines, ", ") or "none"
end

-- One line of everything readable about unit; whether its name read as text.
local function Dump(unit, label)
	local guid = Guid(unit)
	local ok, name = pcall(UnitName, unit)
	local nameRead = ok and not Secret(name) and type(name) == "string" and name ~= ""
	local plateFor = ns.Check.Api("C_NamePlate.GetNamePlateForUnit")
	local plate = plateFor and select(2, pcall(plateFor, unit))
	Say(("  %s %s: exists %s, name %s, guid %s (the kill %s), level %s, classification %s, type %s, dead %s,"
		.. " corpse %s, ghost %s, tapped by others %s, can attack %s, reaction %s, health %s/%s, visible %s,"
		.. " in interact range %s, loot (has, can) %s, plate %s"):format(label, unit, Ask("UnitExists", unit),
		ok and Show(name) or "error", tostring(guid), tostring(guid ~= nil and guid == run.guid),
		Ask("UnitLevel", unit), Ask("UnitClassification", unit), Ask("UnitCreatureType", unit), Ask("UnitIsDead", unit),
		Ask("UnitIsCorpse", unit), Ask("UnitIsGhost", unit), Ask("UnitIsTapDenied", unit),
		Ask("UnitCanAttack", "player", unit), Ask("UnitReaction", unit, "player"), Ask("UnitHealth", unit),
		Ask("UnitHealthMax", unit), Ask("UnitIsVisible", unit), Ask("CheckInteractDistance", unit, 3),
		guid and Ask("CanLootUnit", guid) or "no guid", plate and "yes" or "none"))
	Say(("  %s %s tooltip: %s"):format(label, unit, guid and TooltipLines(unit) or "(no unit)"))
	return nameRead, guid
end

-- Plates up now with a dead unit on them, and whether the kill's is one.
local function DeadPlates(label)
	local dead, ours = 0, false
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and Dead(unit) then
			dead = dead + 1
			local guid = Guid(unit)
			ours = ours or (guid ~= nil and guid == run.guid)
			Say(("  %s dead unit on a plate: %s %s guid %s"):format(label, unit, Ask("UnitName", unit), tostring(guid)))
		end
	end
	Say(("  %s: %d plates up, %d with a dead unit, the kill's %s"):format(label, #(C_NamePlate.GetNamePlates() or {}),
		dead, tostring(ours)))
	return ours
end

local function Shot(what)
	if ns.PadTestBoxHide then ns.PadTestBoxHide() end
	local ok = pcall(function() Screenshot() end)
	Say(ok and ("  screenshot (%s) at %s"):format(what, date("%m%d%y_%H%M%S")) or "  screenshot failed")
end

local function Prompt(text, sub)
	ns.PadTestBox(text, sub or "", 1, 0.82, 0)
end

local function CineOn()
	return ns.IsCineModeOn and ns.IsCineModeOn() and true or false
end
local function SetCine(on)
	if CineOn() ~= on and _G.Cinematic_ToggleCineMode then
		_G.Cinematic_ToggleCineMode()
		Say("  CineMode turned " .. (on and "ON" or "OFF") .. " by the test")
	end
end

local function Result(key, text)
	run.results[#run.results + 1] = text
	Say("RESULT " .. key .. ": " .. text)
end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	run.events:UnregisterAllEvents()
	run.events:SetScript("OnEvent", nil)
	local r = run.found
	if done then
		Result("target", r.target and "the corpse's name reads as your target" or "no name read on the corpse as target")
		Result("mouseover", r.mouseover and "the corpse's name reads on mouseover" or "no name read on mouseover")
		Result("soft", r.soft and ("soft interact picked the corpse (%s)"):format(r.soft)
			or "soft interact never picked the corpse")
		Result("death", r.death and ("the death came in the combat log (%s)"):format(r.death)
			or "no death line for it in the combat log")
		Result("plate", r.plate and "a plate stayed on the corpse" or "no plate on the corpse")
	end
	ns.ApplyCVarSet(SOFT, false)
	if run.cineWas then SetCine(true) end
	Say("settings after: " .. CVarLine())
	Say(done and "done" or "stopped early")
	local lines = run.results
	run = nil
	ns.PadTestBox(done and "Corpse test DONE. /reload, then say \"check log\"." or "Corpse test stopped.",
		table.concat(lines, "\n"), 1, 1, 1)
	C_Timer.After(30, function() if not run then ns.PadTestBoxHide() end end)
end

-- What soft interact and the other soft names hold, logged when it changes.
local function WatchSoft()
	local now = {}
	for _, token in ipairs(TOKENS) do
		local guid = Guid(token)
		now[#now + 1] = token .. "=" .. (guid and (Ask("UnitName", token) .. " " .. guid
			.. (guid == run.guid and " (the kill)" or "") .. (Dead(token) and " dead" or "")) or "none")
		if token == "softinteract" and guid and guid == run.guid and not run.found.soft then
			run.found.soft = run.step
			Say("  soft interact picked the kill's corpse in step " .. run.step)
			Dump(token, "picked")
		end
	end
	local line = table.concat(now, ", ")
	if line ~= run.soft then
		run.soft = line
		Say("  soft names: " .. line)
	end
end

local function Go(step)
	run.step, run.stepAt = step, GetTime()
	Say(("--- step %s (fight %s, target %s) ---"):format(step, tostring(InCombatLockdown()),
		tostring(Guid("target"))))
end

local function Tick()
	WatchSoft()
	local step = run.step
	if step == "kill" then
		local guid = Guid("target")
		if guid and not Dead("target") and Ask("UnitCanAttack", "player", "target") == "true" then
			if guid ~= run.guid then
				run.guid = guid
				local _, name = pcall(UnitName, "target")
				run.name = not Secret(name) and name or nil
				Say(("  the kill: %s %s, level %s"):format(Ask("UnitName", "target"), guid, Ask("UnitLevel", "target")))
				Dump("target", "alive")
			end
		elseif guid and guid == run.guid and Dead("target") then
			Say("  the kill died (target reads dead)")
			Dump("target", "just dead")
			Go("calm")
		end
		Prompt("1/4: Target an enemy you can kill quickly, and KILL it. Stay close to its body.",
			run.guid and ("Your kill: " .. tostring(run.name or run.guid)) or "No enemy targeted yet")
	elseif step == "calm" then
		if InCombatLockdown() then
			Prompt("2/4: Killed. Finish the fight. Stay by the body and keep it targeted.", "Waiting for the fight to end")
			return
		end
		if not run.calmSettled then
			run.calmSettled = GetTime()
			Prompt("2/4: Stand still, keep the body targeted.", "Recording")
			return
		end
		if GetTime() - run.calmSettled < 1.5 then return end
		local guid = Guid("target")
		if guid and guid == run.guid then
			run.found.target = Dump("target", "corpse as target")
		else
			Say("  the corpse wasn't your target after the fight (target " .. tostring(guid) .. ")")
		end
		run.found.plate = DeadPlates("after the fight") or run.found.plate
		Shot("corpse targeted")
		Go("mouse")
	elseif step == "mouse" then
		local guid = Guid("mouseover")
		if guid and guid == run.guid then
			run.found.mouseover = Dump("mouseover", "corpse as mouseover")
			Shot("corpse under the mouse")
			Go("soft")
			return
		end
		Prompt("3/4: Press ESC to clear your target, then hold the MOUSE over the body.",
			guid and ("Under the mouse: " .. Ask("UnitName", "mouseover") .. " (not your kill)") or "Waiting for the mouse")
	elseif step == "soft" then
		local guid = Guid("target")
		if guid and guid == run.guid then
			Say("  right-click targeted the corpse")
			Dump("target", "right-clicked")
			Go("after")
			return
		end
		Prompt("4/4: Move the mouse OFF the body. Walk right up to it, then RIGHT-CLICK it.",
			run.found.soft and "Soft interact picked it" or "Waiting for the right-click")
	elseif step == "after" then
		if run.lootOpen or GetTime() - run.stepAt < AFTER_WAIT then
			Prompt("Close the loot window (take it or not).", "Almost done")
			return
		end
		Dump("target", "after")
		Dump("softinteract", "after")
		run.found.plate = DeadPlates("at the end") or run.found.plate
		Finish(true)
	end
end

local function OnEvent(_, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local info = ns.Check.Api("CombatLogGetCurrentEventInfo")
		if not info then return end
		local ok, _, sub, _, _, _, _, _, destGUID, destName = pcall(info)
		if not ok or Secret(sub) then return end
		if sub == "UNIT_DIED" or sub == "PARTY_KILL" or sub == "UNIT_DESTROYED" then
			local ours = not Secret(destGUID) and destGUID == run.guid
			if ours and not run.found.death then run.found.death = sub end
			-- (Its death heard before the target read dead, or with the target gone.)
			if ours and run.step == "kill" then
				Say("  the kill died (combat log)")
				Go("calm")
			end
			if run.deathLines < DEATH_LINES then
				run.deathLines = run.deathLines + 1
				Say(("  log %s: %s %s%s"):format(sub, Show(destName), Show(destGUID), ours and " (the kill)" or ""))
			end
		end
	elseif event == "COMBAT_LOG_MESSAGE" then
		-- (Forever's text lines: kept when they say something died, or name the kill.)
		local parts, hit = {}, false
		for i = 1, math.min(select("#", ...), 6) do
			local value = select(i, ...)
			parts[#parts + 1] = Show(value)
			if type(value) == "string" and not Secret(value) then
				local low = value:lower()
				hit = hit or low:find("die") or low:find("slain") or low:find("kill")
					or (run.name and value:find(run.name, 1, true))
			end
		end
		if hit and run.deathLines < DEATH_LINES then
			run.deathLines = run.deathLines + 1
			Say("  log message: " .. table.concat(parts, " | "))
			if run.name and table.concat(parts, " "):find(run.name, 1, true) and not run.found.death then
				run.found.death = "COMBAT_LOG_MESSAGE"
			end
		end
	elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
		local unit = ...
		local guid = unit and not Secret(unit) and Guid(unit)
		if guid and guid == run.guid then
			Say(("  %s for the kill: %s, dead %s"):format(event, tostring(unit), tostring(Dead(unit))))
			if event == "NAME_PLATE_UNIT_ADDED" and Dead(unit) then run.found.plate = true end
		end
	elseif event == "LOOT_OPENED" then
		run.lootOpen = true
		Say(("  loot window open: %s items"):format(Ask("GetNumLootItems")))
		if run.step == "soft" then
			Dump("softinteract", "looting")
			Dump("target", "looting")
			Go("after")
		end
	elseif event == "LOOT_CLOSED" then
		run.lootOpen = false
		run.stepAt = GetTime()
	elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
		local old, new = ...
		Say(("  soft interact changed: %s -> %s"):format(Show(old), Show(new)))
	end
end

function ns.CorpseTest()
	ns.debugNoCopyWindow = true
	if run then
		Say("stopped: command typed again")
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("corpse test: not in a fight")
		return
	end
	CinematicDB.corpseLog = {}
	run = { at = GetTime(), results = {}, found = {}, deathLines = 0 }
	Say(("start: %s (game %s), version %s, target %s"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), Ask("C_AddOns.GetAddOnMetadata", "CinematicDev", "Version"),
		tostring(Guid("target"))))
	Say("settings at the start: " .. CVarLine())
	Say("settings with Dead or Corpse in the name: " .. DeadCVars())
	Say("combat log restricted: " .. Ask("C_CombatLog.IsCombatLogRestricted"))
	run.cineWas = CineOn()
	SetCine(false)
	ns.ApplyCVarSet(SOFT, true)
	Say("settings held: " .. CVarLine())
	run.events = CreateFrame("Frame")
	local registered = {}
	for _, event in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "COMBAT_LOG_MESSAGE", "NAME_PLATE_UNIT_ADDED",
		"NAME_PLATE_UNIT_REMOVED", "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_SOFT_INTERACT_CHANGED" }) do
		registered[#registered + 1] = event .. "=" .. tostring(ns.Check.RegisterEvent(run.events, event))
	end
	Say("events: " .. table.concat(registered, ", "))
	run.events:SetScript("OnEvent", function(...)
		local ok, err = pcall(OnEvent, ...)
		if not ok and run then Say("event error: " .. tostring(err)) end
	end)
	Go("kill")
	run.ticker = C_Timer.NewTicker(0.25, function()
		if not run then return end
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.TestPrompt("Corpse test: follow the box (type it again to stop)")
end
