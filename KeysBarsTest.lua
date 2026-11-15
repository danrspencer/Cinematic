-- /cine debug keysbars [steps]: one run checking the Keyboard Map, the Action
-- Bars style page and the style themes' way back to the game's look, in the
-- game. Timed steps in the big test box (Frames.lua's ns.PadTestBox); each
-- acts, takes a screenshot (the box hidden for it, named in the log) and logs
-- what it found:
--   1 the Keyboard Map opened: its layout, size, strata, each kind's count and
--     the names cut off on their keys;
--   2 the same on the German layout (its letters drawn by the font);
--   3 you open the spellbook and drop a spell on a dark key: what got bound,
--     and whether the map was over the spellbook;
--   4 you right-click that key and click Yes: whether it's unbound again;
--   5 you close the spellbook; the action buttons go square with a dark line;
--   6 round, and you press an ability with a cooldown: the sweep against the
--     icon;
--   7 back to the game's look, no /reload: the game's art back;
--   8 /cine debug themecheck: every theme pair, then the game's.
-- What it changes (map layout, action bar look, CineMode, keys bound on the map) is put
-- back at the end, and at the next login if a /reload cuts it short. Into
-- CinematicDB.keysBarsLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETUP, STEP, WAIT = 10, 12, 4 -- seconds: before the first step, a step's usual length, before it acts

local run -- { at, steps, step, notes, starts, keys, boundCombo }

local function Say(text)
	local log = CinematicDB and CinematicDB.keysBarsLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Plain(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.1f"):format(value) end
	return tostring(value)
end
local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end

-- Settings it changes, kept to put back (here and at the next login); keys
-- bound from the map, kept by combo (false: was unbound).
local function Set(key, value)
	local db = ns.GetDB()
	CinematicDB.keysBarsPending = CinematicDB.keysBarsPending or {}
	local pending = CinematicDB.keysBarsPending
	if pending[key] == nil then pending[key] = { value = db[key] } end
	db[key] = value
end
-- (CineMode fades the action bars: off for the bar steps, back at the end.)
local function CineMode(on)
	if (ns.lastCinematic and true or false) == on then return end
	if run.cine == nil then run.cine = ns.lastCinematic and true or false end
	if Cinematic_ToggleCineMode then pcall(Cinematic_ToggleCineMode) end
end
local function Bars(shape, edge)
	CineMode(false)
	Set("abStyle", true)
	Set("abShape", shape)
	Set("abEdge", edge)
	if ns.RefreshActionBarStyle then ns.RefreshActionBarStyle() end
end
local function PutBackKeys()
	local kept = CinematicDB.keysBarsKeys
	if type(kept) ~= "table" or InCombatLockdown() then return 0 end
	local count = 0
	for combo, action in pairs(kept) do
		if (GetBindingAction(combo, true) or "") ~= (action or "") then
			if action then SetBinding(combo, action) else SetBinding(combo) end
			count = count + 1
		end
	end
	if count > 0 and SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
	CinematicDB.keysBarsKeys = nil
	return count
end
local function PutBack()
	local pending = CinematicDB.keysBarsPending
	if type(pending) == "table" then
		local db = ns.GetDB()
		for key, old in pairs(pending) do db[key] = old.value end
		CinematicDB.keysBarsPending = nil
		if ns.RefreshActionBarStyle then ns.RefreshActionBarStyle() end
		if ns.KeyboardMapChanged then ns.KeyboardMapChanged() end
	end
	return PutBackKeys()
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function()
	if type(CinematicDB and (CinematicDB.keysBarsPending or CinematicDB.keysBarsKeys)) == "table" then
		PutBack()
		ns.Print("keys and bars test was cut short: its settings and keys are back")
	end
end)

-- Every map key's binding now (combo = action, false for none).
local function Bindings()
	local out = {}
	for _, combo in ipairs(ns.KeyboardMapCombos and ns.KeyboardMapCombos() or {}) do
		local action = GetBindingAction(combo, true)
		out[combo] = (action and action ~= "") and action or false
	end
	return out
end
-- Each action slot's icon (a drop on a gold key puts the spell on its button).
local function Slots()
	local out = {}
	for slot = 1, 180 do out[slot] = GetActionTexture(slot) or false end
	return out
end
-- (Kept before the first step that can bind a key, here and for the next login.)
local function KeepKeys()
	run.slots = run.slots or Slots()
	run.keys = run.keys or Bindings()
	CinematicDB.keysBarsKeys = CinematicDB.keysBarsKeys or run.keys
end
local function Changed()
	local now, list = Bindings(), {}
	for combo, was in pairs(run.keys or {}) do
		if now[combo] ~= was then list[#list + 1] = { combo = combo, was = was, now = now[combo] } end
	end
	return list
end

-- The spellbook's window (retail's or the classic clients').
local function Spellbook()
	for _, name in ipairs({ "PlayerSpellsFrame", "SpellBookFrame" }) do
		local frame = _G[name]
		if frame and frame:IsShown() then return frame, name end
	end
end
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7,
	TOOLTIP = 8 }
local function MapOverBook()
	local book, name = Spellbook()
	local map = _G.CinematicKeyboardMap
	if not book then return "spellbook not open" end
	if not (map and map:IsShown()) then return name .. " open, map not shown" end
	local over = (STRATA[map:GetFrameStrata()] or 0) > (STRATA[book:GetFrameStrata()] or 0)
		or (map:GetFrameStrata() == book:GetFrameStrata() and map:GetFrameLevel() > book:GetFrameLevel())
	return ("%s %s/%d, map %s/%d: map on top %s"):format(name, book:GetFrameStrata(), book:GetFrameLevel(),
		map:GetFrameStrata(), map:GetFrameLevel(), tostring(over))
end

-- A button's region against its icon: how far in each edge sits (+ = inside).
local function Against(region, icon)
	local l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
	local il, ir, it, ib = icon:GetLeft(), icon:GetRight(), icon:GetTop(), icon:GetBottom()
	if not (l and il) then return "no spot" end
	return ("in by left %s right %s top %s bottom %s"):format(Plain(l - il), Plain(ir - r), Plain(it - t), Plain(b - ib))
end
-- Bar 1's buttons with a cooldown sweep showing: the sweep against the icon.
local function Sweeps()
	local lines = {}
	for i = 1, 12 do
		local button = _G["ActionButton" .. i]
		local cd = button and button.cooldown
		local shown = cd and cd:IsShown()
		if shown and issecretvalue and issecretvalue(shown) then shown = true end
		if shown and button.icon then
			local okMask, masks = pcall(function() return cd.GetNumMaskTextures and cd:GetNumMaskTextures() end)
			lines[#lines + 1] = ("button %d sweep %s, masks %s"):format(i, Against(cd, button.icon),
				okMask and Plain(masks) or "?")
		end
	end
	return #lines > 0 and table.concat(lines, "; ") or "no sweep showing on bar 1"
end
local function BarState()
	local state = ns.ActionBarState and ns.ActionBarState() or "no ActionBarState"
	local layers = ns.ButtonLayers and ns.ButtonLayers() or ""
	local button = _G.ActionButton1
	local normal = button and button.GetNormalTexture and button:GetNormalTexture()
	local border = _G.MainMenuBar and _G.MainMenuBar.BorderArt
	return ("%s; %s; normal shown %s; bar 1 border art alpha %s"):format(state, layers,
		normal and tostring(normal:IsShown()) or "-", border and Plain(border:GetAlpha()) or "-")
end

-- themecheck's last line (its result), caught as it prints.
local function CatchPrints(on)
	if on and not run.print then
		run.print = ns.Print
		ns.Print = function(msg, ...)
			if type(msg) == "string" and msg:find("^themecheck:") then
				run.themecheck = msg
				Say("  " .. msg)
			end
			return run.print(msg, ...)
		end
	elseif not on and run.print then
		ns.Print, run.print = run.print, nil
	end
end

local STEPS = {
	{ key = "map", say = "%d/%d: The KEYBOARD MAP opens on your keyboard. Just watch.",
		act = function()
			KeepKeys()
			ns.KeyboardMapOpen(true)
			return "opened, layout setting " .. tostring(ns.GetDB().kbLayout)
		end,
		after = function() return ns.KeyboardMapTestInfo() end },
	{ key = "german", say = "%d/%d: The map changes to the GERMAN keyboard (ß, Ü, Ö, Ä keys). Just watch.",
		act = function()
			Set("kbLayout", "de")
			ns.KeyboardMapChanged()
			return "layout de"
		end,
		after = function()
			local info = ns.KeyboardMapTestInfo()
			local pending = CinematicDB.keysBarsPending and CinematicDB.keysBarsPending.kbLayout
			ns.GetDB().kbLayout = pending and pending.value or "auto"
			ns.KeyboardMapChanged()
			return info
		end },
	{ key = "drop", seconds = 30, say = "%d/%d: Press P for your SPELLBOOK. DRAG any spell from it and DROP it on a " ..
		"DARK key on the map (one with nothing on it). Leave the spellbook open.",
		act = function()
			KeepKeys()
			ns.KeyboardMapOpen(true)
			return "waiting for the drop; " .. MapOverBook()
		end,
		after = function()
			local list = Changed()
			local lines = {}
			for _, each in ipairs(list) do
				lines[#lines + 1] = ("%s: %s > %s"):format(each.combo, tostring(each.was), tostring(each.now))
				if not each.was and each.now and not run.boundCombo then run.boundCombo = each.combo end
			end
			local slots, now = {}, Slots()
			for slot, was in pairs(run.slots or {}) do
				if now[slot] ~= was then slots[#slots + 1] = ("slot %d %s > %s"):format(slot, tostring(was), tostring(now[slot])) end
			end
			return ("%d keys changed%s; %d action slots changed%s; %s"):format(#list,
				#lines > 0 and (" (" .. table.concat(lines, ", ") .. ")") or "", #slots,
				#slots > 0 and (" (" .. table.concat(slots, ", ") .. ")") or "", MapOverBook())
		end },
	{ key = "clear", seconds = 20, say = "%d/%d: RIGHT-CLICK the key you just dropped the spell on, then click YES " ..
		"in the box that asks.",
		act = function()
			return run.boundCombo and ("watching " .. run.boundCombo) or "nothing was bound in the last step"
		end,
		after = function()
			if not run.boundCombo then return "no key to check" end
			local now = GetBindingAction(run.boundCombo, true)
			local popup = StaticPopup_Visible and StaticPopup_Visible("CINEMATIC_KEYMAP_CLEAR")
			return ("%s now %s (cleared %s), clear box still up %s"):format(run.boundCombo, tostring(now),
				tostring(not now or now == ""), tostring(popup and true or false))
		end },
	{ key = "square", say = "%d/%d: CLOSE the spellbook. The map closes, CineMode turns off, and your action " ..
		"buttons go SQUARE with a dark line round them. Just watch.",
		act = function()
			ns.KeyboardMapClose()
			Bars("square", "thin")
			return "square, thin line"
		end,
		after = function() return BarState() end },
	{ key = "round", seconds = 16, say = "%d/%d: The buttons go ROUND. When the box turns green, PRESS one ability " ..
		"that has a COOLDOWN (not just the short one every spell has).",
		act = function()
			Bars("round", "game")
			return "round, game's outline"
		end,
		shotAt = 8,
		after = function() return BarState() .. " || " .. Sweeps() end },
	{ key = "game", say = "%d/%d: The buttons go back to the GAME'S look, without a reload. Just watch.",
		act = function()
			Bars("game", "game")
			return "game's shape and outline"
		end,
		after = function() return BarState() .. " || " .. Sweeps() end },
	{ key = "themecheck", seconds = 80, say = "%d/%d: Every style THEME is tried and taken off again, about a " ..
		"minute. Your frames flicker: that's it working. Just watch.",
		act = function()
			if not ns.ThemeCheck then return "no ThemeCheck" end
			CatchPrints(true)
			ns.ThemeCheck()
			return "themecheck started, target " .. tostring(UnitExists("target"))
		end,
		shotAt = 30,
		after = function() return run.themecheck or "themecheck hadn't finished" end },
}

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	CatchPrints(false)
	if ns.KeyboardMapClose then ns.KeyboardMapClose() end
	local keys = PutBack()
	if run.cine ~= nil then CineMode(run.cine) end
	Say(("put back: settings, %d keys"):format(keys))
	for _, index in ipairs(run.steps) do
		local step = STEPS[index]
		local note = run.notes[step.key]
		Say(("verdict %d %s: %s; %s"):format(index, step.key, note and note.acted or "not run", note and note.found or "-"))
	end
	run = nil
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped.", "", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local now = GetTime() - run.at
	if now < SETUP then
		ns.PadTestBox("Stand somewhere calm, OUT OF A FIGHT, and TARGET anyone (or yourself, F1). Follow the box: " ..
			"some steps ask you to do one thing.", ("Starts in %d"):format(math.ceil(SETUP - now)), 1, 0.82, 0)
		return
	end
	local index
	for i = #run.starts, 1, -1 do
		if now >= run.starts[i] then
			index = i
			break
		end
	end
	if not index then return end
	if index > #run.steps then
		Finish(true)
		return
	end
	local step = STEPS[run.steps[index]]
	local length = step.seconds or STEP
	local into = now - run.starts[index]
	if index ~= run.step then
		run.step = index
		run.notes[step.key] = {}
		Say(("--- step %d: %s (in combat %s) ---"):format(run.steps[index], step.key, tostring(InCombatLockdown())))
	end
	local note = run.notes[step.key]
	local shotAt = step.shotAt or (length - 5)
	if into < WAIT then
		ns.PadTestBox(step.say:format(index, #run.steps), "GET READY", 1, 0.82, 0)
	elseif not note.shot or into >= shotAt + 1 then
		ns.PadTestBox(step.say:format(index, #run.steps), ("RECORDING: %d sec left"):format(math.ceil(length - into)),
			0.3, 1, 0.3)
	end
	if not note.acted and into >= WAIT then
		if InCombatLockdown() then
			note.acted = "skipped: in a fight"
		else
			local ok, result = pcall(step.act)
			note.acted = ok and tostring(result) or ("error: " .. tostring(result))
		end
		Say("  " .. note.acted)
	elseif note.acted and not note.shot and into >= shotAt then
		note.shot = true
		Say("  " .. Shot(("step %d %s"):format(run.steps[index], step.key)))
	elseif note.shot and not note.found and into >= length - 1.5 then
		local ok, result = pcall(step.after)
		note.found = ok and tostring(result) or ("error: " .. tostring(result))
		Say("  " .. note.found)
	end
end

function ns.KeysBarsTest(args)
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("keys and bars test: not in a fight")
		return
	end
	if not (ns.KeyboardMapOpen and ns.KeyboardMapTestInfo and ns.RefreshActionBarStyle) then
		ns.Print("keys and bars test: the Keyboard Map or Action Bars page isn't loaded")
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
	CinematicDB.keysBarsLog = {}
	run = { at = GetTime(), steps = steps, step = -1, notes = {}, starts = {} }
	local at = SETUP
	for i, index in ipairs(steps) do
		run.starts[i] = at
		at = at + (STEPS[index].seconds or STEP)
	end
	run.starts[#steps + 1] = at
	local db = ns.GetDB()
	Say(("start: %s (game %s), locale %s, map layout %s, bars %s/%s/%s, theme %s, Dominos/Masque %s, steps %s"):format(
		ns.isRetail and "retail" or "classic", tostring((select(4, GetBuildInfo()))), tostring(GetLocale()),
		tostring(db.kbLayout), tostring(db.abStyle), tostring(db.abShape), tostring(db.abEdge), tostring(db.styleTheme),
		tostring((C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)("Dominos") or
			(C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)("Masque")), table.concat(steps, " ")))
	run.ticker = C_Timer.NewTicker(0.5, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print(("keys and bars test: %d sec, follow the box (type it again to stop)"):format(math.floor(at)))
end
