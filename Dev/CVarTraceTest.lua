-- /cine debug cvartrace: what Cinematic changes as you log in that brings up
-- friendly NPCs' plates (2026-11-20: with Cinematic off, no friendly plates
-- and an NPC's name and title over its head at any range; with it loaded,
-- friendly NPCs get plates with their names only, the title gone, though the
-- plate settings read the same both ways: the first trace, plate, name and
-- soft target settings only, found Cinematic only writing them as they were).
-- Stand near friendly NPCs (vendors, trainers). The command arms it and
-- reloads; from then on, hands off. Loaded near the top of CinematicDev.toc,
-- so its hooks are in before the rest of Cinematic's files run. Recorded:
--   every game setting as this file loads (C_Console's list), and at the
--     end every one that differs: whatever changed, hooked or not
--   every change for WATCH_FOR s after entering the world, any setting: old
--     and new value and who made it (the calling addon, file and line; a
--     change with no Lua call, CVAR_UPDATE alone: the game or the console);
--     writes of the value it already had counted, not listed
--   every C_NamePlate Set* call, its arguments and caller
--   CineMode turned off a second in (CineMode on brings every plate up by
--     design), and each time it turns on or off after; put back at the end
--   each second: NPC plates up, friendly ones, and how many show a name
-- At the end: the plate and name settings, which of our sets hold each, and
-- the values Cinematic keeps for you. Into CinematicDB.cvarTraceLog. Dev copy
-- only.
local _, ns = ...

local WATCH_FOR = 30 -- seconds after entering the world
local SNAPSHOT = { "nameplateShowAll", "nameplateShowFriendlyNPCs", "nameplateShowFriends",
	"nameplateShowFriendlyPlayers", "nameplateShowEnemies", "nameplateShowOnlyNames", "nameplateForceShowUnitName",
	"nameplateMaxDistance", "nameplateShowOffscreen", "UnitNameNPC", "UnitNameInteractiveNPC",
	"UnitNameFriendlySpecialNPCName", "UnitNameHostleNPC", "UnitNameFriendlyPlayerName", "UnitNameOwn",
	"SoftTargetInteract", "SoftTargetNameplateInteract", "SoftTargetIconInteract" }

local buffer = {} -- (lines before the saved settings load)
local recording = true -- (till ADDON_LOADED says whether it's armed)
local startAt = GetTime()
local stopAt
local rewrites = {} -- [name] = writes of the value it already had

local function Say(text)
	local line = ("%.2f %s"):format(GetTime() - startAt, text)
	local log = CinematicDB and CinematicDB.cvarTraceLog
	if log then log[#log + 1] = line elseif buffer then buffer[#buffer + 1] = line end
end

local function Snapshot(label)
	local parts = {}
	for _, cvar in ipairs(SNAPSHOT) do parts[#parts + 1] = cvar .. "=" .. tostring(GetCVar(cvar)) end
	Say(label .. ": " .. table.concat(parts, " "))
end

-- Every game setting's name (C_Console's list), or nil where there's none.
local function AllCVars()
	if not (C_Console and C_Console.GetAllCommands) then return nil end
	local ok, list = pcall(C_Console.GetAllCommands)
	if not ok or type(list) ~= "table" then return nil end
	local cvarType = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar or 0
	local names = {}
	for _, info in ipairs(list) do
		if info.commandType == cvarType and type(info.command) == "string" then names[#names + 1] = info.command end
	end
	return names
end

-- The calling lines, file:line, the addon folder too where there is one.
local function Callers()
	local stack = debugstack(4, 10, 0) or ""
	local lines = {}
	for raw in stack:gmatch("[^\n]+") do
		local addon, file, line = raw:match("AddOns[/\\]([^/\\]+)[/\\]([^\"%]]-%.lua)\"?%]?:(%d+)")
		if addon then
			lines[#lines + 1] = ("%s/%s:%s"):format(addon, file:gsub("\\", "/"), line)
		else
			local other, otherLine = raw:match("([%w_]+%.lua)\"?%]?:(%d+)")
			if other then lines[#lines + 1] = other .. ":" .. otherLine end
		end
		if #lines >= 6 then break end
	end
	return #lines > 0 and table.concat(lines, " < ") or "no Lua caller (the game)"
end

-- Every setting as this file loads, and each one's last known value.
-- (Its events registered first, and each load step guarded: a step that
-- fails is logged, the rest still runs. The first widened run left no log at
-- all, 2026-11-20: an error as the file loads is lost, the saved settings not
-- loaded yet.)
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CVAR_UPDATE")
local function Step(label, fn)
	local ok, err = pcall(fn)
	if not ok then Say(("load step failed (%s): %s"):format(label, tostring(err))) end
end
local start, known = {}, {}
local allNames
local unreadable = 0
Step("every setting's value", function()
	allNames = AllCVars()
	for _, cvar in ipairs(allNames or SNAPSHOT) do
		local ok, value = pcall(GetCVar, cvar)
		if ok then
			start[cvar] = value
			known[cvar:lower()] = value
		else
			unreadable = unreadable + 1
		end
	end
end)

local function Same(a, b)
	if a == b then return true end
	local x, y = tonumber(a), tonumber(b)
	return x ~= nil and x == y
end

local function Noted(name, value, how)
	if not recording or type(name) ~= "string" then return end
	if stopAt and GetTime() > stopAt then return end
	local key = name:lower()
	local was = known[key]
	local now = value ~= nil and tostring(value) or GetCVar(name)
	if was ~= nil and Same(was, now) then
		rewrites[name] = (rewrites[name] or 0) + 1
		return
	end
	known[key] = now
	Say(("  %s %s -> %s (%s)%s"):format(name, tostring(was == nil and "?" or was), tostring(now), how,
		how == "CVAR_UPDATE" and "" or (": " .. Callers())))
end

Step("SetCVar hooks", function()
	hooksecurefunc("SetCVar", function(name, value) Noted(name, value, "SetCVar") end)
	if C_CVar and C_CVar.SetCVar then
		hooksecurefunc(C_CVar, "SetCVar", function(name, value) Noted(name, value, "C_CVar.SetCVar") end)
	end
end)

-- Every C_NamePlate Set* call.
-- (Names gathered first, hooked after: not while going through the table.)
local plateCalls = {}
Step("C_NamePlate hooks", function()
	if not C_NamePlate then return end
	for name, fn in pairs(C_NamePlate) do
		if type(fn) == "function" and name:find("^Set") then plateCalls[#plateCalls + 1] = name end
	end
	table.sort(plateCalls)
	for _, name in ipairs(plateCalls) do
		Step("hook C_NamePlate." .. name, function()
			hooksecurefunc(C_NamePlate, name, function(...)
				if not recording or (stopAt and GetTime() > stopAt) then return end
				local args = {}
				for i = 1, select("#", ...) do args[i] = tostring((select(i, ...))) end
				Say(("  C_NamePlate.%s(%s): %s"):format(name, table.concat(args, ", "), Callers()))
			end)
		end)
	end
end)
Step("first snapshot", function() Snapshot("as this file loads") end)
-- (The game's own defaults: a setting at its default isn't in config-cache.wtf,
-- so a fresh start without Cinematic has these. And whether this is a fresh
-- start: settings live on through a /reload, so after one the values above
-- are whatever the last session left, Cinematic's holds included.)
Step("defaults", function()
	local parts = {}
	local Default = C_CVar and C_CVar.GetCVarDefault or GetCVarDefault
	for _, cvar in ipairs(SNAPSHOT) do
		local ok, value = pcall(Default, cvar)
		parts[#parts + 1] = cvar .. "=" .. tostring(ok and value or "?")
	end
	Say("the game's defaults: " .. table.concat(parts, " "))
end)

local function CineOn()
	return ns.IsCineModeOn and ns.IsCineModeOn() and true or false
end

-- NPC plates up now: all, friendly, and how many show their name.
local function PlateCount()
	local npcs, friendly, named = 0, 0, 0
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		local okGuid, guid = pcall(UnitGUID, unit)
		local player = okGuid and type(guid) == "string" and not (issecretvalue and issecretvalue(guid))
			and guid:find("^Player%-")
		if unit and not player and plate:IsVisible() then
			npcs = npcs + 1
			local okFriend, isFriend = pcall(UnitIsFriend, "player", unit)
			if okFriend and isFriend == true then friendly = friendly + 1 end
			local name = plate.UnitFrame and plate.UnitFrame.name
			local okShown, shown = pcall(function() return name and name:IsVisible() and name:GetAlpha() > 0.05 end)
			if okShown and shown then named = named + 1 end
		end
	end
	return npcs, friendly, named
end

local watch -- (the per-second ticker)
local cineWas, lastCine, lastPlates

local function Finish()
	if not recording then return end
	if watch then watch:Cancel() end
	Snapshot("at the end")
	-- Every setting that isn't as it was when this file loaded.
	local changed = {}
	for cvar, was in pairs(start) do
		local now = GetCVar(cvar)
		if not Same(was, now) then changed[#changed + 1] = ("%s %s -> %s"):format(cvar, tostring(was), tostring(now)) end
	end
	table.sort(changed)
	Say(("settings changed since this file loaded (of %d %s): %d"):format(#(allNames or SNAPSHOT),
		allNames and "in the game's list" or "snapshotted, no list on this client", #changed))
	for _, line in ipairs(changed) do Say("  " .. line) end
	local again = {}
	for name, count in pairs(rewrites) do again[#again + 1] = ("%s x%d"):format(name, count) end
	table.sort(again)
	Say("written again with the value they had: " .. (#again > 0 and table.concat(again, ", ") or "none"))
	for _, cvar in ipairs(SNAPSHOT) do
		local holder = ns.CVarHolder and ns.CVarHolder(cvar)
		local keep = ns.chardb or ns.db or {}
		local saved = ns.db and ns.db.savedCVars and ns.db.savedCVars[cvar]
		local before = keep.cvarsBefore and keep.cvarsBefore[cvar]
		local ours = keep.cvarsOurs and keep.cvarsOurs[cvar]
		if holder or saved ~= nil or before ~= nil or ours ~= nil then
			Say(("  %s: held by %s; saved %s; yours before Cinematic %s, Cinematic's %s"):format(cvar,
				holder and tostring(holder.label) or "none", tostring(saved), tostring(before), tostring(ours)))
		end
	end
	Say(("pages: Nameplates %s, Names %s; CineMode %s"):format(tostring(ns.db and ns.db.handlePlates),
		tostring(ns.db and ns.db.handleNames), tostring(CineOn())))
	if cineWas and not CineOn() and _G.Cinematic_ToggleCineMode then
		_G.Cinematic_ToggleCineMode()
		Say("CineMode turned back on")
	end
	Say("done")
	recording = false
	if ns.TestPrompt then ns.TestPrompt("CVar trace done. /reload, then say \"check log\".", 15) end
end

-- Each second: CineMode turning on or off, and the NPC plates up.
local function Watch()
	local cine = CineOn()
	if cine ~= lastCine then
		Say(("  CineMode %s%s"):format(cine and "ON" or "OFF", lastCine == nil and " (at the start)" or ""))
		lastCine = cine
	end
	local npcs, friendly, named = PlateCount()
	local plates = ("%d/%d/%d"):format(npcs, friendly, named)
	if plates ~= lastPlates then
		Say(("  NPC plates up %d, friendly %d, showing a name %d"):format(npcs, friendly, named))
		lastPlates = plates
	end
end

events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if not (CinematicDB and type(CinematicDB) == "table") then return end
		self:UnregisterEvent("ADDON_LOADED")
		if not CinematicDB.cvarTraceArmed then
			recording = false
			buffer, start, known = nil, nil, {}
			self:UnregisterAllEvents()
			return
		end
		CinematicDB.cvarTraceArmed = nil
		CinematicDB.cvarTraceLog = buffer
		buffer = nil
		Say(("armed: %s loaded (game %s); %s settings in the game's list (%d unreadable); C_NamePlate Set calls hooked:"
			.. " %s"):format(tostring(arg1), tostring((select(4, GetBuildInfo()))), allNames and tostring(#allNames) or "no",
			unreadable,
			#plateCalls > 0 and table.concat(plateCalls, ", ") or "none"))
		Snapshot("at our ADDON_LOADED")
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not recording then return end
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		Snapshot(("entering the world (%s)"):format(arg1 and "a fresh login: the values above are as saved"
			or "after a /reload: the values above are what the last session left"))
		stopAt = GetTime() + WATCH_FOR
		watch = C_Timer.NewTicker(1, function() pcall(Watch) end)
		C_Timer.After(1, function()
			-- (CineMode keeps every plate on by design: off for the run, so
			-- what's left is what Cinematic does outside it.)
			cineWas = CineOn()
			if cineWas and _G.Cinematic_ToggleCineMode then
				_G.Cinematic_ToggleCineMode()
				Say("CineMode turned OFF by the test")
			end
			if ns.TestPrompt then
				ns.TestPrompt(("CVar trace: hands off, recording %d sec."):format(WATCH_FOR), 6)
			end
		end)
		C_Timer.After(WATCH_FOR, Finish)
	elseif event == "CVAR_UPDATE" then
		-- (Changes made without a Lua call: the game's own, the console. A Lua
		-- one fires this too, after its hook: then the value's already known.)
		if recording and type(arg1) == "string" then
			local now = GetCVar(arg1)
			if not Same(known[arg1:lower()], now) then Noted(arg1, now, "CVAR_UPDATE") end
		end
	end
end)

-- The command: armed, then a reload starts it.
function ns.CVarTraceTest()
	CinematicDB.cvarTraceArmed = true
	CinematicDB.cvarTraceLog = nil
	-- (Not ns.ReloadOrAsk: its Reload popup's cover errors on Forever as it
	-- anchors to the popup's button, QoL/Reload.lua:229, 2026-11-20. Where
	-- our code can't reload, you type it.)
	if not ns.reloadBlocked then
		ReloadUI()
		return
	end
	if ns.TestPrompt then
		ns.TestPrompt("CVar trace armed. Stand near friendly NPCs, then type /reload", 10)
	else
		ns.Print("cvar trace armed: stand near friendly NPCs, then type /reload")
	end
end
