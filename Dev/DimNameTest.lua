-- /cine debug dimname [steps]: one run checking the Action Bar Style page's
-- Opacity and the Unit Frames page's Name background (a player's two asks,
-- 2026-11-18), in the game. Timed steps in the big test box (Frames.lua's
-- ns.PadTestBox); each acts, takes a screenshot (the box hidden for it, named
-- in the log) and logs what it found:
--   1 CineMode off, buttons at 50%: each bar's first button's alpha;
--   2 back to 100%: the game's alpha back;
--   3 circle portrait, Name background Auto: the strip hidden;
--   4 Custom purple, you Tab to someone new: the color held;
--   5 The game's: its color back;
--   6 Hidden;
--   7 50% with CineMode on, you hit a dummy: the buttons' and bars' alpha in
--     the fight (last: a fight carried on into the next steps skipped them).
-- What it changes is put back at the end, and at the next login if a /reload
-- cuts it short. Into CinematicDB.dimNameLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETUP, STEP, WAIT = 10, 12, 4 -- seconds: before the first step, a step's usual length, before it acts

local run -- { at, steps, step, notes, starts, cine }

local function Say(text)
	local log = CinematicDB and CinematicDB.dimNameLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Plain(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end

-- Settings it changes, kept to put back (here and at the next login).
local function Set(key, value)
	local db = ns.GetDB()
	CinematicDB.dimNamePending = CinematicDB.dimNamePending or {}
	local pending = CinematicDB.dimNamePending
	if pending[key] == nil then pending[key] = { value = db[key] } end
	db[key] = value
end
local function Refresh()
	if ns.RefreshActionBarStyle then ns.RefreshActionBarStyle() end
	if ns.RefreshUnitStyle then ns.RefreshUnitStyle() end
end
local function CineMode(on)
	if (ns.lastCinematic and true or false) == on then return end
	if run.cine == nil then run.cine = ns.lastCinematic and true or false end
	if Cinematic_ToggleCineMode then pcall(Cinematic_ToggleCineMode) end
end
local function PutBack()
	local pending = CinematicDB.dimNamePending
	if type(pending) ~= "table" then return end
	local db = ns.GetDB()
	for key, old in pairs(pending) do db[key] = old.value end
	CinematicDB.dimNamePending = nil
	Refresh()
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function()
	if type(CinematicDB and CinematicDB.dimNamePending) == "table" then
		PutBack()
		ns.Print("opacity and name test was cut short: its settings are back")
	end
end)

-- Each bar's first button: its alpha, its bar's, what it shows as.
local BUTTONS = { "ActionButton1", "MultiBarBottomLeftButton1", "MultiBarBottomRightButton1", "MultiBarRightButton1",
	"MultiBar5Button1", "PetActionButton1", "StanceButton1" }
local function Buttons()
	local list = {}
	local function Add(name, button)
		if not button then return end
		local parent = button:GetParent()
		list[#list + 1] = ("%s %s (bar %s, on screen %s, shown %s)"):format(name, Plain(button:GetAlpha()),
			parent and Plain(parent:GetEffectiveAlpha()) or "-", Plain(button:GetEffectiveAlpha()),
			tostring(button:IsVisible()))
	end
	for _, name in ipairs(BUTTONS) do Add(name, _G[name]) end
	local pad = _G.GamepadMainActionBarFrame
	if pad and type(pad.actionButtons) == "table" then Add("gamepad 1", pad.actionButtons[1]) end
	return ("%s || in fight %s, CineMode %s"):format(table.concat(list, "; "), tostring(InCombatLockdown()),
		tostring(ns.lastCinematic and true or false))
end

-- The target's (and focus's) name strip: shown, alpha, color, what we hold.
local function Strips()
	local list = {}
	for _, name in ipairs({ "TargetFrame", "FocusFrame" }) do
		local frame = _G[name]
		local strip, cleared, tint = ns.UnitNameStrip(frame) -- (a plain call: "a and f()" keeps only its first value)
		if strip then
			local r, g, b = strip:GetVertexColor()
			-- (A texture has no GetEffectiveAlpha: its own times its frame's.)
			local holder = strip:GetParent()
			local alpha, frameAlpha = strip:GetAlpha(), holder and holder:GetEffectiveAlpha()
			local onScreen = (Plain(alpha) ~= "secret" and Plain(frameAlpha) ~= "secret" and frameAlpha)
				and alpha * frameAlpha or nil
			list[#list + 1] = ("%s strip shown %s alpha %s on screen %s color %s %s %s, ours: cleared %s tint %s"):format(name,
				Plain(strip:IsVisible()), Plain(alpha), Plain(onScreen), Plain(r), Plain(g),
				Plain(b), Plain(cleared), tint and ("%s %s %s"):format(Plain(tint[1]), Plain(tint[2]), Plain(tint[3])) or "none")
		elseif frame then
			list[#list + 1] = name .. ": no strip found"
		end
	end
	local view = ns.UnitStyleView and ns.UnitStyleView("TARGET")
	return ("target %s (%s); %s || page on %s, nameBack %s, shape %s, override %s"):format(
		Plain(UnitName("target")), Plain(UnitReaction and UnitReaction("player", "target")),
		table.concat(list, "; "), tostring(ns.StyleOn and ns.StyleOn("ufStyle")), tostring(view and view.ufNameBack),
		tostring(view and view.ufShape), tostring(ns.StyleOverride and ns.StyleOverride("unitPartTargetNameBack")))
end
-- (The player's setup: the game's frames, no theme, a round portrait. A theme
-- draws its own band behind the name and hides the game's strip by the Overrides
-- tab: under one, every step looked the same, 2026-11-18 on Forever.)
local function NameBack(mode)
	Set("styleTheme", "game")
	Set("styleOver_unitPartTargetNameBack", false)
	Set("styleOver_unitPartFocusNameBack", false)
	Set("ufStyle", true)
	Set("ufOwn_TARGET", false)
	Set("ufOwn_FOCUS", false)
	Set("ufShape", "circle")
	Set("ufNameBack", mode)
	Set("ufNameBackR", 0.6)
	Set("ufNameBackG", 0.1)
	Set("ufNameBackB", 0.8)
	Refresh()
end

local STEPS = {
	{ key = "half", say = "%d/%d: CineMode turns off and your ACTION BUTTONS go HALF see-through. Just watch.",
		act = function()
			CineMode(false)
			Set("abStyle", true)
			Set("abAlpha", 0.5)
			Refresh()
			return "opacity 50%"
		end,
		after = Buttons },
	{ key = "full", say = "%d/%d: The action buttons go back to FULL. Just watch.",
		act = function()
			Set("abAlpha", 1)
			Refresh()
			return "opacity 100%"
		end,
		after = Buttons },
	{ key = "auto", seconds = 16, say = "%d/%d: TARGET an NPC who has a colored strip behind their " ..
		"name (any mob or vendor). Your target's portrait goes ROUND and the strip should go away.",
		act = function()
			NameBack("auto")
			return "circle, Auto"
		end,
		shotAt = 11,
		after = Strips },
	{ key = "custom", seconds = 16, say = "%d/%d: The strip turns PURPLE. When the box turns green, press TAB to " ..
		"target someone else: it should stay purple.",
		act = function()
			NameBack("custom")
			return "Custom purple"
		end,
		shotAt = 11,
		after = Strips },
	{ key = "game", say = "%d/%d: The strip goes back to the GAME'S color (red, yellow or green). Just watch.",
		act = function()
			NameBack("game")
			return "the game's"
		end,
		after = Strips },
	{ key = "hide", say = "%d/%d: The strip is HIDDEN. Just watch.",
		act = function()
			NameBack("hide")
			return "hidden"
		end,
		after = Strips },
	{ key = "fight", seconds = 35, fightShot = true, say = "%d/%d: CineMode turns on, buttons at half. ATTACK the " ..
		"training dummy now so your bars come up, and KEEP HITTING it until the test says done.",
		act = function()
			Set("abAlpha", 0.5)
			Refresh()
			CineMode(true)
			return "opacity 50%, CineMode on"
		end,
		shotAt = 30,
		after = Buttons },
}

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	PutBack()
	if run.cine ~= nil then CineMode(run.cine) end
	Say("put back: settings" .. (InCombatLockdown() and " (buttons after the fight)" or ""))
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
		ns.PadTestBox("Stand somewhere calm, OUT OF A FIGHT, near something you can attack (a training dummy is " ..
			"best). Follow the box: some steps ask you to do one thing.", ("Starts in %d"):format(math.ceil(SETUP - now)),
			1, 0.82, 0)
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
	elseif not note.shot or into >= (note.fightAt or shotAt) + 1 then
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
	elseif note.acted and not note.shot and (into >= shotAt
		or (step.fightShot and InCombatLockdown() and into >= WAIT + 4)) then
		-- (A fight step: its shot and reading a few seconds into the fight.)
		if step.fightShot then note.fightAt = into end
		note.shot = true
		Say("  " .. Shot(("step %d %s"):format(run.steps[index], step.key)))
	elseif note.shot and not note.found and (into >= length - 1.5 or (note.fightAt and into >= note.fightAt + 2)) then
		local ok, result = pcall(step.after)
		note.found = ok and tostring(result) or ("error: " .. tostring(result))
		Say("  " .. note.found)
	end
end

function ns.DimNameTest(args)
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("opacity and name test: not in a fight")
		return
	end
	if not (ns.RefreshActionBarStyle and ns.RefreshUnitStyle and ns.UnitNameStrip) then
		ns.Print("opacity and name test: the Action Bars or Unit Frames page isn't loaded")
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
	CinematicDB.dimNameLog = {}
	run = { at = GetTime(), steps = steps, step = -1, notes = {}, starts = {} }
	local at = SETUP
	for i, index in ipairs(steps) do
		run.starts[i] = at
		at = at + (STEPS[index].seconds or STEP)
	end
	run.starts[#steps + 1] = at
	local db = ns.GetDB()
	local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	Say(("start: %s (game %s), bars page %s opacity %s, unit page %s shape %s nameBack %s, theme %s, " ..
		"Dominos/Masque %s, steps %s"):format(ns.isRetail and "retail" or "classic", tostring((select(4, GetBuildInfo()))),
		tostring(db.abStyle), tostring(db.abAlpha), tostring(db.ufStyle), tostring(db.ufShape), tostring(db.ufNameBack),
		tostring(db.styleTheme), tostring(IsLoaded("Dominos") or IsLoaded("Masque")), table.concat(steps, " ")))
	-- (Caught: an error here left the run half started, and the next try only stopped it.)
	for _, Read in ipairs({ Buttons, Strips }) do
		local ok, result = pcall(Read)
		Say("before: " .. (ok and tostring(result) or ("error: " .. tostring(result))))
	end
	run.ticker = C_Timer.NewTicker(0.5, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
end
