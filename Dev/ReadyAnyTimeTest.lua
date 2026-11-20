-- /cine debug anytime [steps] [spell name]: one run checking the Cooldown Manager page's
-- When ready > Out of fights tick, out of a fight. It picks a spell in your
-- Essential or Utility bar with a cooldown (20 sec or more) that's ready now,
-- then timed steps in the big test box (Frames.lua's ns.PadTestBox), each
-- setting what it checks, then logging the icon (its alpha, the ready pass's
-- target, time left) with a screenshot and its own verdict:
--   1 When ready, Out of fights off: faded
--   2 Out of fights ticked: shown
--   3 the spell follows its group, the group When ready with Out of fights: shown
--   4 its own off, a numbered line Always | Anywhere above it: shown
--   5 a line Always for another place than this one: faded (its own dropdown's)
--   6 the page opens on the spell icons: a screenshot of the new column
--   7 you cast the spell: faded while it recharges, even with Out of fights
-- The page's spell settings are put back at the end, and at the next login
-- if a /reload cuts it short. Into CinematicDB.anyTimeLog.
-- Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETUP, STEP, WAIT = 8, 12, 4 -- seconds: the first step, each one's, before it acts
local KEYS = { "cooldownReadyOnly", "cooldownReadyEarly", "cooldownEarlyOn", "cooldownRechargeOnly",
	"cooldownNeedsPower", "cooldownReadyAnyTime", "cooldownProcOnly", "cooldownAlwaysShow", "cooldownNeverShow",
	"cooldownGroupDefaults", "cooldownSpellRules" }
local PLACES = { "world", "city", "inn", "dungeon", "raid", "bg" }

local run -- { at, steps, step, notes, spell, group, name }

local function Say(text)
	local log = CinematicDB and CinematicDB.anyTimeLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end
local function Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = Copy(v) end
	return copy
end

-- (The page's spell settings, kept whole to put back, here and at the next login.)
local function Keep()
	local kept = {}
	for _, key in ipairs(KEYS) do kept[key] = Copy(ns.db[key]) end
	CinematicDB.anyTimePending = kept
end
local function PutBack()
	local kept = CinematicDB.anyTimePending
	if type(kept) ~= "table" then return end
	for _, key in ipairs(KEYS) do
		if type(kept[key]) == "table" then ns.db[key] = kept[key] end
	end
	CinematicDB.anyTimePending = nil
	ns.readyPace.due = true
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function()
	if type(CinematicDB and CinematicDB.anyTimePending) == "table" then
		PutBack()
		ns.Print("Out of fights test was cut short: your Cooldown Manager settings are back")
	end
end)

-- The spell on its own: When ready, Out of fights as asked; no numbered lines.
local function OwnReady(anyTime)
	local db, id = ns.db, run.spell
	db.cooldownSpellRules[id] = nil
	db.cooldownRechargeOnly[id], db.cooldownProcOnly[id], db.cooldownAlwaysShow[id] = nil, nil, nil
	db.cooldownNeverShow[id] = nil
	db.cooldownReadyOnly[id] = true
	db.cooldownNeedsPower[id] = nil
	db.cooldownEarlyOn[id], db.cooldownReadyEarly[id] = true, nil
	db.cooldownReadyAnyTime[id] = anyTime or nil
	ns.readyPace.due = true
end
-- A numbered line on the spell, Always in place ("any": anywhere), its own
-- dropdown When ready with Out of fights off under it.
local function Line(place)
	OwnReady(false)
	ns.db.cooldownSpellRules[run.spell] = { { show = "always", combat = "any", place = place } }
	ns.CooldownRuleFactsStale()
	ns.readyPace.due = true
end
-- The place you're in now (the one a line with it alone fits).
local function PlaceNow()
	local facts = ns.RuleFactsNow()
	for _, place in ipairs(PLACES) do
		if ns.CooldownRuleFits({ show = "always", place = place, combat = "any" }, facts) then return place end
	end
end

-- The icon now, and whether it's as expected ("shown" or "faded").
local function Look(expect)
	local probe = ns.ReadyIconProbe(run.spell)
	if not probe then return "FAIL: the spell's icon isn't in the Essential or Utility bar" end
	local shown = probe.target ~= 0 and probe.alpha > 0.9
	local faded = probe.target == 0 and probe.alpha < 0.5
	local pass = (expect == "shown" and shown) or (expect == "faded" and faded)
	return ("%s (want %s): alpha %.2f, target %s, left %s, mode %s, out of fights %s, line %s, in combat %s"):format(
		pass and "PASS" or "FAIL", expect, probe.alpha, tostring(probe.target),
		probe.left and ("%.1f"):format(probe.left) or "can't tell", tostring(probe.mode), tostring(probe.anyTime),
		tostring(select(2, ns.CooldownRuleMode("spell", run.spell)) or "own"), tostring(InCombatLockdown()))
end

local STEPS = {
	{ key = "faded", say = "%d/%d: %s is set to When ready, Out of fights OFF. Its icon should fade. Just watch.",
		act = function() OwnReady(false) return "own When ready, out of fights off" end,
		after = function() return Look("faded") end },
	{ key = "shown", say = "%d/%d: Out of fights is ticked for %s. Its icon should come back. Just watch.",
		act = function() OwnReady(true) return "own When ready, out of fights on" end,
		after = function() return Look("shown") end },
	{ key = "group", say = "%d/%d: %s follows its group, set to When ready with Out of fights. It should stay up.",
		act = function()
			local db, id = ns.db, run.spell
			OwnReady(false)
			db.cooldownReadyOnly[id], db.cooldownEarlyOn[id], db.cooldownReadyAnyTime[id] = nil, nil, nil
			db.cooldownGroupDefaults[run.group] = db.cooldownGroupDefaults[run.group] or {}
			local group = db.cooldownGroupDefaults[run.group]
			group.mode, group.anyTime, group.power, group.early = "ready", true, nil, nil
			ns.readyPace.due = true
			return "group " .. run.group .. " When ready, out of fights on"
		end,
		after = function() return Look("shown") end },
	{ key = "lineOn", say = "%d/%d: %s gets a line 1, Always | Anywhere, over its own When ready. It should show.",
		act = function()
			Line("any")
			return "line Always anywhere, own When ready out of fights off"
		end,
		after = function() return Look("shown") end },
	{ key = "lineOff", say = "%d/%d: The line is for another place than here, so its own dropdown decides: %s fades.",
		act = function()
			local now = PlaceNow()
			Line(now == "city" and "raid" or "city")
			return "line Always for another place than " .. tostring(now)
		end,
		after = function() return Look("faded") end },
	{ key = "page", say = "%d/%d: The Cooldown Manager page opens on the spell icons, %s on When ready with Out of " ..
		"fights. Just watch: a screenshot of the columns.",
		act = function()
			OwnReady(true)
			if InCombatLockdown() then return "in a fight: not opened" end
			local ok, err = pcall(ns.OpenOptionsAt, "Cooldown Manager", nil, "cooldownSmartDefaults")
			return ok and "page opened" or ("couldn't open: " .. tostring(err))
		end,
		after = function()
			local panel = SettingsPanel or InterfaceOptionsFrame
			return "settings open " .. tostring(panel and panel:IsShown()) .. "; " .. Look("shown")
		end },
	{ key = "cast", say = "%d/%d: CAST %s NOW (Out of fights stays on). While it recharges its icon should fade.",
		act = function() OwnReady(true) return "waiting for your cast" end,
		after = function()
			-- (Whether the cast was seen: the last few casts' spell IDs.)
			local casts = {}
			for _, cast in ipairs(ns.recentCasts or {}) do
				casts[#casts + 1] = ("%s %.0fs ago"):format(tostring(cast.id), GetTime() - (cast.at or 0))
			end
			return Look("faded") .. "; last casts: " .. (#casts > 0 and table.concat(casts, ", ") or "none")
		end },
}

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	PutBack()
	for _, index in ipairs(run.steps) do
		local step = STEPS[index]
		local note = run.notes[step.key]
		Say(("verdict %d %s: %s; %s"):format(index, step.key, note and note.acted or "not run",
			note and note.found or "-"))
	end
	run = nil
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped.", "", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local now = GetTime() - run.at
	if now < SETUP then
		ns.PadTestBox(("Stand somewhere calm, OUT OF A FIGHT. The test uses %s from your Cooldown Manager; " ..
			"keep it ready (don't cast it) until the last step asks you to."):format(run.name),
			("Starts in %d"):format(math.ceil(SETUP - now)), 1, 0.82, 0)
		return
	end
	local index = math.floor((now - SETUP) / STEP) + 1
	if index > #run.steps then
		Finish(true)
		return
	end
	local step = STEPS[run.steps[index]]
	local into = now - SETUP - (index - 1) * STEP
	if index ~= run.step then
		run.step = index
		run.notes[step.key] = {}
		Say(("--- step %d: %s (in combat %s) ---"):format(run.steps[index], step.key, tostring(InCombatLockdown())))
	end
	local note = run.notes[step.key]
	local text = step.say:format(index, #run.steps, run.name)
	if into < WAIT then
		ns.PadTestBox(text, ("GET READY: starts in %d"):format(math.ceil(WAIT - into)), 1, 0.82, 0)
	else
		ns.PadTestBox(text, ("RECORDING: %d sec left"):format(math.ceil(STEP - into)), 0.3, 1, 0.3)
	end
	if not note.acted and into >= WAIT then
		local ok, result = pcall(step.act)
		note.acted = ok and tostring(result) or ("error: " .. tostring(result))
		Say("  " .. note.acted)
	elseif note.acted and not note.found and into >= STEP - 2 then
		-- (Read first, then the shot: the box hides for it.)
		local ok, result = pcall(step.after)
		note.found = ok and tostring(result) or ("error: " .. tostring(result))
		Say("  " .. note.found)
		Say("  " .. Shot(("step %d %s"):format(run.steps[index], step.key)))
	end
end

-- A spell in the Essential or Utility bar with a cooldown of 20 sec or more,
-- one charge, ready now, castable as you are with no target (not Bash out
-- of Bear Form, not Rebirth with no one dead). wanted: a spell's name to use
-- instead (any cooldown, target or not). Gives its ID, group and name, or nil and why.
local function PickSpell(wanted)
	local GetName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
	local HasRange = (C_Spell and C_Spell.SpellHasRange) or _G.SpellHasRange
	local IsUsable = (C_Spell and C_Spell.IsSpellUsable) or _G.IsUsableSpell
	local names = {}
	for _, spell in ipairs(ns.CooldownManagerSpells()) do
		if spell.group == "essential" or spell.group == "utility" then
			local okName, name = pcall(GetName, spell.id)
			name = okName and type(name) == "string" and name or ("spell " .. spell.id)
			names[#names + 1] = name
			local probe = ns.ReadyIconProbe(spell.id)
			if wanted then
				if name:lower() == wanted:lower() then
					if not (probe and probe.left == 0) then return nil, name .. " isn't ready now: wait for it" end
					return spell.id, spell.group, name
				end
			else
				local base = GetSpellBaseCooldown and GetSpellBaseCooldown(spell.id)
				local charges = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spell.id)
				local many = type(charges) == "table" and type(charges.maxCharges) == "number" and charges.maxCharges > 1
				local ranged = HasRange and HasRange(spell.id)
				if type(base) == "number" and base >= 20000 and not many and probe and probe.left == 0
					and IsUsable(spell.id) and not ranged then
					return spell.id, spell.group, name
				end
			end
		end
	end
	if wanted then
		return nil, ("%s isn't in your Essential or Utility bar. In them: %s"):format(wanted,
			#names > 0 and table.concat(names, ", ") or "nothing")
	end
	return nil, ("none of the spells in your Essential and Utility bars (%s) has a 20 sec or longer cooldown, " ..
		"is ready now and casts on yourself as you are (form, stance). Name one: /cine debug anytime 6 7 <spell name>"):format(
		table.concat(names, ", "))
end

function ns.ReadyAnyTimeTest(args)
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("Out of fights test: start it out of a fight")
		return
	end
	if not ns.PageOn("handleCooldowns") then
		ns.Print("Out of fights test: turn the Cooldown Manager page on first")
		return
	end
	-- (Steps first as numbers, then a spell's name if you name one.)
	local wanted = (args or ""):gsub("^[%d%s]+", ""):gsub("%s+$", "")
	local spell, group, name = PickSpell(wanted ~= "" and wanted or nil)
	if not spell then
		ns.Print("Out of fights test: " .. group)
		return
	end
	local steps = {}
	for number in (args or ""):match("^[%d%s]*"):gmatch("%d+") do
		number = tonumber(number)
		if STEPS[number] then steps[#steps + 1] = number end
	end
	if #steps == 0 then
		for i = 1, #STEPS do steps[i] = i end
	end
	CinematicDB.anyTimeLog = {}
	run = { at = GetTime(), steps = steps, step = -1, notes = {}, spell = spell, group = group, name = name }
	Keep()
	Say(("start: %s (game %s), spell %s %d (%s, base cooldown %s ms), place %s, CineMode %s, steps %s"):format(
		ns.isRetail and "retail" or "Forever", tostring((select(4, GetBuildInfo()))), name, spell, group,
		tostring(GetSpellBaseCooldown and GetSpellBaseCooldown(spell)), tostring(PlaceNow()),
		tostring(ns.lastCinematic), table.concat(steps, " ")))
	run.ticker = C_Timer.NewTicker(0.5, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print(("Out of fights test with %s: %d sec, follow the box (type it again to stop)"):format(name,
		SETUP + #steps * STEP))
end
