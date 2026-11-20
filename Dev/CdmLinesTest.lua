-- /cine debug cdmlines [steps]: one self-running check of the Cooldown Manager
-- page's numbered lines (UI/CooldownRules.lua, in place of situations,
-- 2026-11-20). It picks a spell in your Essential or Utility bar, sets it
-- Always on its own, then timed steps with big text mid-screen, each setting
-- lines on it and logging the icon (the ready pass's target, the line in use)
-- with a screenshot and its own verdict:
--   1 line 1 Never | where you are now: faded
--   2 line 1 Never | another place: shown (its own Always, Everywhere else)
--   3 line 1 Always | Anywhere over line 2 Never | here: shown (first wins)
--   4 line 1 Never as CQL "<here> and nocombat": faded
--   5 the page opens on the spell's bar: its lines drawn under it (a screenshot)
--   6 its own settings open, its dropdown When ready: Flash, then When ready's
--     Resources, Out of fights and Show early in them (no columns across the page)
--   7 Open CDM clicked: the game's Cooldown Manager window opens and the button
--     says Close CDM; clicked again, it shuts and says Open CDM
--   8 a new, empty line on the page: "Pick one" and "Pick a place" in its
--     dropdowns, and it counts nowhere (Everywhere else stays Active)
-- CineMode is off while it runs (back after). Stand still out of a fight; nothing to press. Its settings are put back at
-- the end, and at the next login if a /reload cuts it short. Into
-- CinematicDB.cdmLinesLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETUP, STEP, WAIT = 6, 10, 3 -- seconds: before the first step, each one's, before it acts
local KEYS = { "cooldownReadyOnly", "cooldownEarlyOn", "cooldownReadyEarly", "cooldownNeedsPower",
	"cooldownReadyAnyTime", "cooldownRechargeOnly", "cooldownProcOnly", "cooldownAlwaysShow",
	"cooldownNeverShow", "cooldownSpellRules", "cooldownGroupRules" }
local PLACES = { "world", "city", "inn", "dungeon", "raid", "bg" }

local run -- { at, steps, step, notes, spell, group, name, here }

local function Say(text)
	local log = CinematicDB and CinematicDB.cdmLinesLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end
-- (The step's text stays in the shot: it says what was set.)
local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end
local function Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = Copy(v) end
	return copy
end

-- (The page's settings it changes, kept whole to put back, here and at the next
-- login; and CineMode, switched off for the run so the bars are up and each
-- icon's fade shows: the user's rule for tests. Its first run had it on, the
-- bar faded by CineMode, nothing to see, 2026-11-20.)
local function Keep()
	local kept = {}
	for _, key in ipairs(KEYS) do kept[key] = Copy(ns.db[key]) end
	kept.cineOn = ns.db.enabled and true or false
	CinematicDB.cdmLinesPending = kept
	if kept.cineOn then ns.SetEnabled(false) end
end
local function PutBack()
	local kept = CinematicDB.cdmLinesPending
	if type(kept) ~= "table" then return end
	for _, key in ipairs(KEYS) do
		if type(kept[key]) == "table" then ns.db[key] = kept[key] end
	end
	CinematicDB.cdmLinesPending = nil
	if kept.cineOn and not ns.db.enabled then ns.SetEnabled(true) end
	ns.CooldownRuleFactsStale()
	ns.readyPace.due = true
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function()
	if type(CinematicDB and CinematicDB.cdmLinesPending) == "table" then
		PutBack()
		ns.Print("Numbered lines test was cut short: your Cooldown Manager settings and CineMode are back")
	end
end)

-- The place you're in now (the one a line with it alone fits).
local function PlaceNow()
	local facts = ns.RuleFactsNow()
	for _, place in ipairs(PLACES) do
		if ns.CooldownRuleFits({ show = "always", place = place, combat = "any" }, facts) then return place end
	end
	return "world"
end

-- The spell Always on its own, with these lines.
local function Lines(list)
	local db, id = ns.db, run.spell
	db.cooldownReadyOnly[id], db.cooldownRechargeOnly[id], db.cooldownProcOnly[id] = nil, nil, nil
	db.cooldownNeverShow[id] = nil
	db.cooldownAlwaysShow[id] = true
	db.cooldownSpellRules[id] = list
	ns.CooldownRuleFactsStale()
	ns.readyPace.due = true
end

-- The icon now, and whether it's as expected ("shown" or "faded").
local function Look(expect)
	local probe = ns.ReadyIconProbe(run.spell)
	if not probe then return "FAIL: the spell's icon isn't in the Essential or Utility bar" end
	local shown, faded = probe.target ~= 0, probe.target == 0
	local pass = (expect == "shown" and shown) or (expect == "faded" and faded)
	local mode, own = ns.CooldownSpellMode(run.spell, run.group)
	local _, line = ns.CooldownRuleMode("spell", run.spell)
	return ("%s (want %s): target %s, alpha %.2f, mode %s (own %s), line in use %s, in combat %s"):format(
		pass and "PASS" or "FAIL", expect, tostring(probe.target), probe.alpha or -1, tostring(mode), tostring(own),
		tostring(line or "none: its own dropdown"), tostring(InCombatLockdown()))
end

local function Other() return run.here == "city" and "raid" or "city" end
local STEPS = {
	{ key = "here", say = "%d/%d: %s gets line 1: Never | where you are. Its icon should FADE. Just watch.",
		act = function()
			Lines({ { show = "never", combat = "any", place = run.here } })
			return "line 1 Never | " .. run.here
		end,
		after = function() return Look("faded") end },
	{ key = "elsewhere", say = "%d/%d: Line 1 is now for another place, so its own Always decides. It should SHOW.",
		act = function()
			Lines({ { show = "never", combat = "any", place = Other() } })
			return "line 1 Never | " .. Other()
		end,
		after = function() return Look("shown") end },
	{ key = "order", say = "%d/%d: Line 1 Always | Anywhere, line 2 Never | here. Line 1 wins: it should SHOW.",
		act = function()
			Lines({ { show = "always", combat = "any", place = "any" }, { show = "never", combat = "any", place = run.here } })
			return "line 1 Always anywhere, line 2 Never here"
		end,
		after = function() return Look("shown") end },
	{ key = "cql", say = "%d/%d: Line 1 is a CQL rule: Never in \"%s and nocombat\". It should FADE.",
		act = function()
			local line = { show = "never" }
			ns.SetCooldownRuleText(line, "nocombat and " .. run.here .. " and not taxi")
			Lines({ line })
			return "line 1 Never, rule: " .. tostring(line.cql)
		end,
		after = function() return Look("faded") end },
	{ key = "page", say = "%d/%d: The Cooldown Manager page opens on %s's bar: two numbered lines under it. Just watch.",
		act = function()
			Lines({ { show = "never", combat = "in", place = "dungeon" },
				{ show = "recharge", cql = "raid and not group" } })
			if InCombatLockdown() then return "in a fight: not opened" end
			-- (The CDM part on the spell's bar: its first run opened on Settings,
			-- by Smart set's key, with no spells to see, 2026-11-20.)
			local ok, err = pcall(ns.OpenOptionsAt, "Cooldown Manager")
			if not ok then return "couldn't open: " .. tostring(err) end
			C_Timer.After(0.3, function()
				if ns.CdmShowSpells then pcall(ns.CdmShowSpells, run and run.group) end
			end)
			return "page opened on the CDM part, " .. tostring(run.group) .. " bar"
		end,
		after = function()
			local found
			for block in pairs(ns.cooldownLineBlocks or {}) do
				local kind, key = block.For()
				if kind == "spell" and key == run.spell and block:IsVisible() then found = block end
			end
			if not found then
				return "FAIL: no lines block shown for the spell (is its bar's tab picked? settings open "
					.. tostring((SettingsPanel or InterfaceOptionsFrame) and (SettingsPanel or InterfaceOptionsFrame):IsShown()) .. ")"
			end
			local count = found.Shown()
			return ("%s: lines block shown, %d lines (want 2) plus Everywhere else, height %d"):format(
				count == 2 and "PASS" or "FAIL", count, math.floor(found:GetHeight() + 0.5))
		end },
	{ key = "settings", say = "%d/%d: %s's own settings open, set When ready: Flash and a When ready part " ..
		"(Resources, Out of fights, Show early) in them. Just watch.",
		act = function()
			Lines({ { show = "never", combat = "in", place = "dungeon" } })
			local db, id = ns.db, run.spell
			db.cooldownAlwaysShow[id], db.cooldownReadyOnly[id], db.cooldownEarlyOn[id] = nil, true, true
			if InCombatLockdown() then return "in a fight: not opened" end
			local ok, err = pcall(ns.OpenOptionsAt, "Cooldown Manager")
			if not ok then return "couldn't open: " .. tostring(err) end
			C_Timer.After(0.3, function()
				if not (run and ns.CdmPageRows) then return end
				local _, _, open = ns.CdmPageRows()
				open[run.spell] = true
				-- (Its bar's settings shut: open, they pushed the spell's below the
				-- page's bottom, out of the screenshot, in its first run, 2026-11-20.)
				open[run.group] = nil
				pcall(ns.CdmShowSpells, run.group)
			end)
			return "own When ready, its settings opened"
		end,
		after = function()
			local rows = ns.CdmPageRows and ns.CdmPageRows() or {}
			for _, row in ipairs(rows) do
				if row.key == run.spell then
					local inside = row.power:GetParent() == row.drawer and row.flashPick and row.flashPick:GetParent() == row.drawer
					local seen = row.drawer:IsVisible() and row.power:IsVisible() and row.early:IsVisible()
						and row.anyTime:IsVisible() and row.flashPick:IsVisible()
					return ("%s: settings open %s, Flash and When ready parts inside %s and shown %s, height %d"):format(
						(inside and seen) and "PASS" or "FAIL", tostring(row.drawer:IsVisible()), tostring(inside),
						tostring(seen), math.floor(row.drawer:GetHeight() + 0.5))
				end
			end
			return "FAIL: the spell's row isn't on the page"
		end },
	{ key = "button", say = "%d/%d: Open CDM is clicked: the game's Cooldown Manager opens and the button says " ..
		"Close CDM. Then it's clicked again: it shuts and says Open CDM. Just watch.",
		act = function()
			if InCombatLockdown() then return "in a fight: not opened" end
			local ok, err = pcall(ns.OpenOptionsAt, "Cooldown Manager")
			if not ok then return "couldn't open: " .. tostring(err) end
			C_Timer.After(0.3, function()
				if not (run and ns.CdmPageRows) then return end
				pcall(ns.CdmShowSpells, run.group)
				local button = select(4, ns.CdmPageRows())
				if not button then return end
				button:Click()
				local window = _G.CooldownViewerSettings
				run.buttonOpen = ("%s, window %s"):format(tostring(button:GetText()),
					tostring(window and window:IsShown()))
			end)
			return "page opened, Open CDM clicked"
		end,
		after = function()
			local button = ns.CdmPageRows and select(4, ns.CdmPageRows())
			if not button then return "FAIL: no Open CDM button" end
			local opened = run.buttonOpen or "not clicked"
			local openOk = opened:find("^" .. ns.L["Close CDM"] .. ", window true") ~= nil
			-- (Clicked again a moment later: the screenshot, taken now, shows Close CDM.)
			C_Timer.After(1, function()
				button:Click()
				local window = _G.CooldownViewerSettings
				local shutOk = button:GetText() == ns.L["Open CDM"] and not (window and window:IsShown())
				Say(("  %s: clicked again: %s, window %s"):format(shutOk and "PASS" or "FAIL",
					tostring(button:GetText()), tostring(window and window:IsShown())))
			end)
			return ("%s: after the click: %s"):format(openOk and "PASS" or "FAIL", opened)
		end },
	{ key = "empty", say = "%d/%d: %s gets a new, empty line: its dropdowns say Pick one and Pick a place, and " ..
		"Everywhere else stays Active. Just watch.",
		act = function()
			Lines({ { show = "", combat = "any", place = "none" } })
			if InCombatLockdown() then return "in a fight: not opened" end
			local ok, err = pcall(ns.OpenOptionsAt, "Cooldown Manager")
			if not ok then return "couldn't open: " .. tostring(err) end
			C_Timer.After(0.3, function()
				if run and ns.CdmShowSpells then pcall(ns.CdmShowSpells, run.group) end
			end)
			return "one empty line, page opened"
		end,
		after = function()
			local found
			for block in pairs(ns.cooldownLineBlocks or {}) do
				local kind, key = block.For()
				if kind == "spell" and key == run.spell and block:IsVisible() then found = block end
			end
			local mode, line = ns.CooldownRuleMode("spell", run.spell)
			local own = ns.CooldownSpellMode(run.spell, run.group)
			local ok = found and found.Shown() == 1 and mode == nil and own == "always"
			return ("%s: empty line drawn %s, it decides %s (line %s), the icon goes by %s"):format(ok and "PASS" or "FAIL",
				tostring(found and found.Shown() == 1), tostring(mode), tostring(line), tostring(own))
		end },
}

-- The big mid-screen text, put up again only when it changes (it prints to chat too).
local function Prompt(text, seconds)
	if run and run.prompt == text then return end
	if run then run.prompt = text end
	ns.TestPrompt(text, seconds)
end

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
	ns.TestPrompt(done and "DONE. /reload, then say \"check log\"." or "Test stopped.", 12)
end

local function Tick()
	local now = GetTime() - run.at
	if now < SETUP then
		Prompt(("Numbered lines test with %s: watch its icon in your Essential or Utility bar. CineMode is off " ..
			"till it's done. Stand still OUT OF A FIGHT; nothing to press."):format(run.name), SETUP + 1)
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
	local text = step.say:format(index, #run.steps, step.key == "cql" and run.here or run.name)
	Prompt(text, STEP + 1)
	if not note.acted and into >= WAIT then
		local ok, result = pcall(step.act)
		note.acted = ok and tostring(result) or ("error: " .. tostring(result))
		Say("  " .. note.acted)
	elseif note.acted and not note.found and into >= STEP - 2 then
		-- (Read first, then the shot: the prompt hides for it.)
		local ok, result = pcall(step.after)
		note.found = ok and tostring(result) or ("error: " .. tostring(result))
		Say("  " .. note.found)
		Say("  " .. Shot(("step %d %s"):format(run.steps[index], step.key)))
	end
end

-- A spell in the Essential or Utility bar (the first), its group and name.
local function PickSpell()
	local GetName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
	for _, spell in ipairs(ns.CooldownManagerSpells()) do
		if (spell.group == "essential" or spell.group == "utility") and ns.ReadyIconProbe(spell.id) then
			local okName, name = pcall(GetName, spell.id)
			return spell.id, spell.group, okName and type(name) == "string" and name or ("spell " .. spell.id)
		end
	end
end

function ns.CdmLinesTest(args)
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("Numbered lines test: start it out of a fight")
		return
	end
	if not ns.PageOn("handleCooldowns") then
		ns.Print("Numbered lines test: turn the Cooldown Manager page on first")
		return
	end
	local spell, group, name = PickSpell()
	if not spell then
		ns.Print("Numbered lines test: no spell in your Essential or Utility bar (is the game's Cooldown Manager on?)")
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
	CinematicDB.cdmLinesLog = {}
	run = { at = GetTime(), steps = steps, step = -1, notes = {}, spell = spell, group = group, name = name }
	Keep()
	run.here = PlaceNow()
	Say(("start: %s (game %s), spell %s %d (%s), place %s, CineMode %s, steps %s"):format(
		ns.isRetail and "retail" or "Forever", tostring((select(4, GetBuildInfo()))), name, spell, group,
		run.here, tostring(ns.lastCinematic), table.concat(steps, " ")))
	run.ticker = C_Timer.NewTicker(0.5, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print(("Numbered lines test with %s: %d sec (type it again to stop)"):format(name, SETUP + #steps * STEP))
end
