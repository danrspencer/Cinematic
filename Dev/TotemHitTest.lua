-- /cine debug totemhit: one recorder run on a shaman's totem hits with the
-- Combat Text Style (2026-11-20). A player's totem numbers never showed with
-- our numbers on, and showed with the game's. Our numbers show a hit as yours
-- when a combat log line comes with it, and a hit with none as your pet's only
-- when you have a pet (CombatTextStyle.lua, PetHit): a totem isn't one. This
-- finds out what a totem's hit brings: a log line or none, which school, the
-- pet unit, a cast event, and what our numbers made of it. Steps on screen,
-- each waiting as long as it takes (type the command again to stop):
--   1 target  a training dummy no one else is hitting, its plate up
--   2 totem   put down a totem that attacks, then don't attack: only its hits
--   3 both    attack the dummy too, the totem still up: yours and its at once
-- The /cine debug combattext recorder (Diagnostics.lua) logs every plate hit,
-- log line, cast and what our numbers did with each; this adds the totems up
-- (GetTotemInfo, each change) and a verdict per step. The Combat Text Style
-- held on for the run (your pet's numbers: ours), CineMode off; both put back.
-- And the totem's own shots (2026-11-20, the first run: its Fire hits came
-- with no log line, every one left out): your totem is the plate of its name
-- that comes just after you cast it; every cast event from it is logged with
-- its target, and each totem hit with how long after its last cast it landed,
-- to see whether its casts can mark its hits as a pet's do. Friendly plates
-- and totem plates held on for the run, so the totem has a plate to hear.
-- Into CinematicDB.combatTextLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local LINES = 25000   -- the recorder's cap (busy dummies: 4000 in 26 s)
local SECONDS = 1800  -- the recorder's own stop: the steps wait as long as they take
local TOTEM_HITS = 8  -- step 2: totem hits on the dummy (no cast of yours just before)
local BOTH_HITS = 12  -- step 3: hits on the dummy
local BOTH_CASTS = 4  -- step 3: casts of yours
local YOUR_CAST = 1.5 -- seconds after a cast of yours a hit may be its
local HELD = { "styleGeneral", "combatTextStyle", "combatTextNumbers", "combatTextPetBy" }
local NEW_PLATE = 2   -- seconds after your totem cast its plate may come
local MATCH = 3       -- seconds after a totem cast its hit counts as matched
local PLATES = ns.CVarSet("Totem test: totem plates", "/cine debug totemhit: your totem gets a plate",
	{ values = { nameplateShowFriends = "1", nameplateShowFriendlyTotems = "1" } })
local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP" }

local run -- { step, saved, cineWas, frame, ticker, count, verdicts, lastCast, totems }

local function Plain(value)
	return not (issecretvalue and issecretvalue(value))
end
local function Show(value)
	if not Plain(value) then return "<secret>" end
	return tostring(value)
end

local function Rec(text)
	local rec = ns.combatTextRecord
	if rec then rec("TOTEMHIT " .. text) end
end

local function Prompt(text)
	ns.TestPrompt(text, 600)
end

-- The totems up now, one per slot, and whether any is.
local function Totems()
	local get = ns.Check.Api("GetTotemInfo")
	if not get then return "no GetTotemInfo", false end
	local parts, any = {}, false
	for slot = 1, 4 do
		local ok, have, name, start, duration = pcall(get, slot)
		if ok and Plain(have) and have then
			any = true
			parts[#parts + 1] = ("%d=%s (start %s, %s s)"):format(slot, Show(name), Show(start), Show(duration))
		elseif not ok then
			parts[#parts + 1] = slot .. "=error"
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or "none", any
end

local function Is(a, b)
	local ok, same = pcall(UnitIsUnit, a, b)
	return ok and Plain(same) and same and true or false
end

local function PetLine()
	local okE, has = pcall(UnitExists, "pet")
	local okN, name = pcall(UnitName, "pet")
	return ("pet unit %s (%s)"):format(okE and Show(has) or "error", okN and Show(name) or "error")
end

local function ZeroCount()
	return { hits = 0, totemHits = 0, lines = 0, drawn = 0, leftOut = 0, petChecks = 0, pets = 0, casts = 0,
		schools = {}, totemCasts = 0, totemSpells = {}, matched = 0, gaps = {}, targetRead = 0, onYours = 0 }
end

local function Schools(count)
	local list = {}
	for school, n in pairs(count.schools) do list[#list + 1] = ("%s x%d"):format(school, n) end
	table.sort(list)
	return #list > 0 and table.concat(list, ", ") or "none"
end

local function Spells(count)
	local list = {}
	for spell, n in pairs(count.totemSpells) do list[#list + 1] = ("%s x%d"):format(spell, n) end
	table.sort(list)
	return table.concat(list, ", ")
end

local function Verdict(key, text)
	run.verdicts[#run.verdicts + 1] = text
	Rec("VERDICT " .. key .. ": " .. text)
end

local function Restore()
	for key, value in pairs(run.saved) do ns.db[key] = value end
	-- (A key that was nil: back to nil, the default.)
	for _, key in ipairs(HELD) do
		if run.saved[key] == nil then ns.db[key] = nil end
	end
	if ns.RefreshCombatTextStyle then pcall(ns.RefreshCombatTextStyle) end
	ns.ApplyCVarSet(PLATES, false)
	if run.cineWas and _G.Cinematic_ToggleCineMode and not (ns.IsCineModeOn and ns.IsCineModeOn()) then
		_G.Cinematic_ToggleCineMode()
	end
end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	run.frame:UnregisterAllEvents()
	run.frame:SetScript("OnEvent", nil)
	Rec((done and "done" or "stopped early") .. "; totems " .. (Totems()))
	Restore()
	local lines = run.verdicts
	local stillRecording = ns.combatTextRecord == run.rec
	run = nil
	if stillRecording then ns.CombatTextProbe() end -- (run again: the recorder stops)
	if done then
		ns.TestPrompt("Totem test DONE.\n" .. table.concat(lines, "\n") .. "\n\nNow /reload, then tell Claude 'check log'.",
			30)
	else
		ns.TestPrompt("Totem test stopped. /reload, then tell Claude 'check log'.", 10)
	end
end

local function Go(step)
	run.step = step
	run.count = ZeroCount()
	Rec(("--- step %s (fight %s); totems %s; %s ---"):format(step, tostring(InCombatLockdown()), (Totems()),
		PetLine()))
end

local function StepVerdict(key)
	local c = run.count
	if key == "totem" then
		Verdict("totem log", c.lines > 0 and ("%d combat log lines came with %d totem hits"):format(c.lines, c.totemHits)
			or ("NO combat log line came with %d totem hits"):format(c.totemHits))
		Verdict("totem numbers", c.drawn >= c.totemHits and ("PASS: %d numbers drawn for %d totem hits"):format(c.drawn,
			c.totemHits) or ("FAIL: %d numbers drawn for %d totem hits, %d left out"):format(c.drawn, c.totemHits,
			c.leftOut))
		local plates = 0
		for _ in pairs(run.totemGuids) do plates = plates + 1 end
		Verdict("totem casts", c.totemCasts > 0 and ("%d cast events from your totems (%s)"):format(c.totemCasts,
			Spells(c)) or ("NO cast events from your totems (%d totem plates found)"):format(plates))
		Verdict("totem match", ("%d of %d totem hits landed within %d s of a totem cast; gaps %s"):format(c.matched,
			c.totemHits, MATCH, #c.gaps > 0 and table.concat(c.gaps, " ") or "none"))
		Verdict("totem target", ("its target read on %d of %d casts, %d of them your target"):format(c.targetRead,
			c.totemCasts, c.onYours))
		Verdict("totem schools", Schools(c) .. "; " .. PetLine() .. "; pet checks " .. c.petChecks .. ", taken as pet's "
			.. c.pets)
	else
		Verdict("both", ("%d hits on the dummy, %d casts of yours, %d log lines, %d drawn, %d left out; schools %s")
			:format(c.hits, c.casts, c.lines, c.drawn, c.leftOut, Schools(c)))
	end
end

local function TargetReady()
	local okC, can = pcall(UnitCanAttack, "player", "target")
	if not (okC and Plain(can) and can) then return false end
	local get = ns.Check.Api("C_NamePlate.GetNamePlateForUnit")
	local okP, plate = pcall(get or function() end, "target")
	return okP and plate ~= nil
end

local function Tick()
	local step = run.step
	local totems, any = Totems()
	if totems ~= run.totems then
		run.totems = totems
		Rec("totems now: " .. totems)
	end
	if step == "target" then
		if TargetReady() then
			Rec("target: " .. Show((select(2, pcall(UnitName, "target")))) .. " " .. Show((select(2, pcall(UnitGUID,
				"target")))))
			Go("totem")
			return
		end
		Prompt("Totem test 1/3: target a training dummy NO ONE else is hitting, close enough to see its nameplate.")
	elseif step == "totem" then
		local c = run.count
		if c.totemHits >= TOTEM_HITS then
			StepVerdict("totem")
			Go("both")
			return
		end
		if not any then
			Prompt("Totem test 2/3: stand about 20 yards from the dummy and put down Searing Totem there (far: its bolts fly longest).")
		else
			Prompt(("Totem test 2/3: DON'T attack. Let the totem hit the dummy (%d of %d hits).")
				:format(c.totemHits, TOTEM_HITS))
		end
	elseif step == "both" then
		local c = run.count
		if c.hits >= BOTH_HITS and c.casts >= BOTH_CASTS then
			StepVerdict("both")
			Finish(true)
			return
		end
		Prompt(("Totem test 3/3: now attack the dummy with your spells too, totem still up (%d of %d hits, %d of %d casts)%s.")
			:format(math.min(c.hits, BOTH_HITS), BOTH_HITS, math.min(c.casts, BOTH_CASTS), BOTH_CASTS,
			any and "" or ". Put a totem down again"))
	end
end

-- A cast event from a unit: yours (counted, a totem's name kept for its
-- plate), or your totem's (logged, its target read, kept for its hit).
local function OnCast(event, unit, spell)
	if type(unit) ~= "string" or not Plain(unit) then return end
	local name = C_Spell and C_Spell.GetSpellName or GetSpellInfo
	local okN, spellName = pcall(name, spell)
	spellName = okN and Plain(spellName) and spellName or nil
	if unit == "player" then
		if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
		run.lastCast = GetTime()
		if run.step == "both" then run.count.casts = run.count.casts + 1 end
		if spellName and spellName:find("Totem", 1, true) then run.totemName, run.totemAt = spellName, GetTime() end
		return
	end
	if not unit:find("^nameplate") then return end
	local okG, guid = pcall(UnitGUID, unit)
	if not (okG and Plain(guid) and guid and run.totemGuids[guid]) then return end
	local c = run.count
	local okT, targetGuid = pcall(UnitGUID, unit .. "target")
	local read = okT and Plain(targetGuid) and targetGuid ~= nil
	local onYours = Is(unit .. "target", "target")
	Rec(("TOTEM CAST %s by %s (%s): %s (%s); its target %s%s"):format(event, unit, run.totemGuids[guid],
		Show(spellName), Show(spell), okT and Show(targetGuid) or "error", onYours and " (your target)" or ""))
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
	c.totemCasts = c.totemCasts + 1
	local key = tostring(spellName) .. " " .. Show(spell)
	c.totemSpells[key] = (c.totemSpells[key] or 0) + 1
	if read then c.targetRead = c.targetRead + 1 end
	if onYours then c.onYours = c.onYours + 1 end
	run.totemCastAt = GetTime()
end

-- A plate that comes just after your totem cast, by its name: your totem.
local function OnPlate(unit)
	if type(unit) ~= "string" or not Plain(unit) then return end
	local okN, name = pcall(UnitName, unit)
	local okG, guid = pcall(UnitGUID, unit)
	if not (okN and Plain(name) and okG and Plain(guid) and guid) then return end
	if run.totemName and name == run.totemName and GetTime() - run.totemAt <= NEW_PLATE then
		run.totemGuids[guid] = name
		local owner = ns.Check.Api("UnitIsOwnerOrControllerOfUnit")
		Rec(("your totem's plate: %s %s %s, yours by the game %s"):format(unit, name, guid,
			owner and Show(select(2, pcall(owner, "player", unit))) or "no API"))
	end
end

local function OnEvent(_, event, ...)
	local c = run.count
	if event:find("^UNIT_SPELLCAST") then
		local unit, _, spell = ...
		OnCast(event, unit, spell)
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		OnPlate((...))
	elseif event == "COMBAT_LOG_MESSAGE" then
		c.lines = c.lines + 1
	elseif event == "PLAYER_TOTEM_UPDATE" then
		local slot = ...
		Rec(("PLAYER_TOTEM_UPDATE slot %s; totems %s; %s"):format(Show(slot), (Totems()), PetLine()))
	elseif event == "UNIT_COMBAT" then
		local unit, action, _, _, school = ...
		if type(unit) ~= "string" or not Plain(unit) or not unit:find("^nameplate") then return end
		if not Is(unit, "target") then return end
		c.hits = c.hits + 1
		local key = Plain(school) and tostring(school) or "<secret>"
		c.schools[key] = (c.schools[key] or 0) + 1
		local yours = run.lastCast and GetTime() - run.lastCast <= YOUR_CAST
		-- (A totem's: not a swing, no cast of yours just before.)
		if Plain(action) and action == "WOUND" and not yours and not (Plain(school) and school == 1) then
			c.totemHits = c.totemHits + 1
			local gap = run.totemCastAt and GetTime() - run.totemCastAt
			if gap then
				c.gaps[#c.gaps + 1] = ("%.2f"):format(gap)
				if gap <= MATCH then c.matched = c.matched + 1 end
			end
			Rec(("totem hit %d on the dummy, school %s, %s"):format(c.totemHits, key,
				gap and ("%.2f s after its last cast"):format(gap) or "no totem cast yet"))
		end
	end
end

function ns.TotemHitTest()
	if run then
		Rec("stopped: command typed again")
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("totemhit: not in a fight.")
		return
	end
	local okClass, _, class = pcall(UnitClass, "player")
	if not okClass or class ~= "SHAMAN" then
		ns.Print("totemhit: this test needs a shaman (log in on one and type it again).")
		return
	end
	run = { saved = {}, verdicts = {}, count = ZeroCount(), totemGuids = {} }
	for _, key in ipairs(HELD) do run.saved[key] = ns.db[key] end
	ns.db.styleGeneral, ns.db.combatTextStyle, ns.db.combatTextNumbers, ns.db.combatTextPetBy = true, true, true, "ours"
	if ns.RefreshCombatTextStyle then pcall(ns.RefreshCombatTextStyle) end
	ns.ApplyCVarSet(PLATES, true)
	run.cineWas = ns.IsCineModeOn and ns.IsCineModeOn() and true or false
	if run.cineWas and _G.Cinematic_ToggleCineMode then _G.Cinematic_ToggleCineMode() end
	if ns.combatTextRecord then ns.CombatTextProbe() end -- (one already running: stopped, fresh one below)
	ns.CombatTextProbe(LINES, SECONDS)
	run.rec = ns.combatTextRecord
	if not run.rec then
		Restore()
		run = nil
		ns.Print("totemhit: the recorder didn't start.")
		return
	end
	-- (Counted as the recorder hears our numbers' steps, for the verdicts.)
	local original = run.rec
	run.rec = function(text)
		if run and type(text) == "string" then
			local c = run.count
			if text:find("^DRAWN ") then c.drawn = c.drawn + 1
			elseif text:find("LEFT OUT", 1, true) then c.leftOut = c.leftOut + 1
			elseif text:find("^pet check:") then c.petChecks = c.petChecks + 1
			elseif text:find("^PET'S") then c.pets = c.pets + 1 end
		end
		return original(text)
	end
	ns.combatTextRecord = run.rec
	local okOn, on = pcall(ns.StyleOn, "combatTextStyle")
	Rec(("start: %s (game %s), Combat Text Style on %s, held back by %s, CineMode was %s; totems %s; %s"):format(
		ns.isRetail and "retail" or "Forever", tostring((select(4, GetBuildInfo()))), okOn and tostring(on) or "error",
		tostring(ns.combatTextBlocked), tostring(run.cineWas), (Totems()), PetLine()))
	run.frame = CreateFrame("Frame")
	local registered = {}
	local events = { "UNIT_COMBAT", "COMBAT_LOG_MESSAGE", "PLAYER_TOTEM_UPDATE", "NAME_PLATE_UNIT_ADDED" }
	for _, event in ipairs(CAST_EVENTS) do events[#events + 1] = event end -- (every unit's: the totem's too)
	for _, event in ipairs(events) do
		registered[#registered + 1] = event .. "=" .. tostring(ns.Check.RegisterEvent(run.frame, event))
	end
	Rec("events: " .. table.concat(registered, ", "))
	Rec(("plates: nameplateShowFriends=%s nameplateShowFriendlyTotems=%s"):format(
		tostring(GetCVar("nameplateShowFriends")), tostring(GetCVar("nameplateShowFriendlyTotems"))))
	run.frame:SetScript("OnEvent", function(...)
		local ok, err = pcall(OnEvent, ...)
		if not ok then Rec("event error: " .. tostring(err)) end
	end)
	Go("target")
	run.ticker = C_Timer.NewTicker(0.25, function()
		if not run then return end
		local ok, err = pcall(Tick)
		if not ok then
			Rec("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
end
