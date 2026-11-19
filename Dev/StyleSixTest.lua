-- /cine debug release6 [steps]: one run checking the style revamp's release
-- 6 in the game (every Style page on the Look panel template) and the plate
-- themes' shapes. Timed steps in the big test box (Frames.lua's
-- ns.PadTestBox); each opens what it shows, takes a screenshot (the box
-- hidden for it, named in the log) and logs what it found:
--   1-7  each Style page opened: Unit Frames and Raid Frames with their
--        Default row's Look panel opened by its button; Personal Resources,
--        Tooltips, Chat Bubbles, Action Bars and Combat Text with their
--        panel on the page. Logged: the page shown, the panels showing,
--        their size and tabs, errors;
--   8    you close the settings window (the game won't let addons close it);
--   9-10 plate themes Emberforge (Chisel shape) and Silver Screen (Bevel),
--        CineMode off so plates show their bars: logged, each plate's fill
--        masks (ours or the game's), its ground, texture.
-- What it changes (plate theme, CineMode) is put back at the end, and at
-- the next login if a /reload cuts it short. Into CinematicDB.styleSixLog.
-- Dev copy only (CinematicDev.toc).
local _, ns = ...
local L = ns.L

local SETUP, STEP, WAIT = 8, 11, 4 -- seconds: the first step, each one's, before it acts

local run -- { at, steps, step, notes, cine }

local function Say(text)
	local log = CinematicDB and CinematicDB.styleSixLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Plain(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.0f"):format(value) end
	return tostring(value)
end
local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end

-- (Settings it changes, kept to put back, here and at the next login.)
local function Set(key, value)
	local db = ns.GetDB()
	CinematicDB.styleSixPending = CinematicDB.styleSixPending or {}
	local pending = CinematicDB.styleSixPending
	if pending[key] == nil then pending[key] = { value = db[key] } end
	db[key] = value
end
local function PutBack()
	local pending = CinematicDB.styleSixPending
	if type(pending) ~= "table" then return end
	local db = ns.GetDB()
	for key, old in pairs(pending) do db[key] = old.value end
	CinematicDB.styleSixPending = nil
	if ns.RefreshPlateHealthStyle then ns.RefreshPlateHealthStyle() end
	if ns.RefreshTargetArrows then ns.RefreshTargetArrows() end
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function()
	if type(CinematicDB and CinematicDB.styleSixPending) == "table" then
		PutBack()
		ns.Print("release 6 test was cut short: its settings are back")
	end
end)

-- Every frame under a frame (for a page's buttons).
local function Each(frame, fn, depth)
	depth = depth or 0
	if depth > 12 then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		fn(child)
		Each(child, fn, depth + 1)
	end
end

-- A page opened, and for one with rows, its Default row's Look panel opened
-- by its button (as a click does). Gives what it found.
local function OpenPage(pageName, rowPage)
	if InCombatLockdown() then return "in a fight: not opened" end
	local ok, err = pcall(ns.OpenOptions, pageName)
	if not ok then return "couldn't open: " .. tostring(err) end
	local canvas = ns.SettingsPageCanvas and ns.SettingsPageCanvas(pageName)
	if not canvas then return "no page named " .. pageName end
	local clicked = 0
	if rowPage then
		Each(canvas, function(child)
			if clicked == 0 and child.searchLabel == L["Default"] and child.Click and child:IsShown()
				and child.GetScript and child:GetScript("OnClick") then
				local okClick, why = pcall(child.Click, child)
				clicked = okClick and 1 or -1
				if not okClick then Say("  click error: " .. tostring(why)) end
			end
		end)
	end
	return ("opened, page shown %s, Default row's button %s"):format(tostring(canvas:IsVisible()),
		not rowPage and "-" or clicked == 1 and "clicked" or clicked == -1 and "errored" or "not found")
end

-- The Look panels showing now: their titles, sizes and tabs.
local function Panels()
	local seen = {}
	for _, each in ipairs(ns.LOOK_PANELS or {}) do
		local pop = each.pop
		if pop:IsVisible() then
			local tabs = 0
			Each(pop, function(child)
				if child.dot and child.line and child.text then tabs = tabs + 1 end
			end, 2)
			seen[#seen + 1] = ("'%s' %sx%s, %d tabs"):format(tostring(each.title), Plain(pop:GetWidth()),
				Plain(pop:GetHeight()), tabs)
		end
	end
	return #seen > 0 and table.concat(seen, "; ") or "none showing"
end

-- Each plate's bar: its fill's masks (ours: a plate theme's shape), ground and texture.
local function Plates()
	local lines, shaped, total = {}, 0, 0
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates() or {}) do
		local unitFrame = plate.UnitFrame
		local forbidden = plate.IsForbidden and plate:IsForbidden()
		local container = unitFrame and unitFrame.HealthBarsContainer
		local bar = unitFrame and ((container and container.healthBar) or unitFrame.healthBar)
		local fill = not forbidden and bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
		if fill then
			total = total + 1
			local count = fill.GetNumMaskTextures and fill:GetNumMaskTextures() or 0
			local ours = false
			for i = 1, (type(count) == "number" and count or 0) do
				local mask = fill:GetMaskTexture(i)
				if mask and mask.cineBarShape then ours = true end
			end
			if ours then shaped = shaped + 1 end
			if #lines < 4 then
				local okTex, texture = pcall(fill.GetTexture, fill)
				lines[#lines + 1] = ("masks %s (ours %s), texture %s, visible %s"):format(Plain(count), tostring(ours),
					okTex and Plain(texture) or "?", tostring(bar:IsVisible()))
			end
		end
	end
	return ("%d of %d plates shaped; %s"):format(shaped, total, table.concat(lines, " | "))
end

local function CineMode(on)
	if (ns.lastCinematic and true or false) == on then return end
	if run.cine == nil then run.cine = ns.lastCinematic and true or false end
	if Cinematic_ToggleCineMode then pcall(Cinematic_ToggleCineMode) end
end

local function PageStep(key, page, title, rowPage)
	return { key = key, say = ("%%d/%%d: The settings open on %s%s. Just watch."):format(title,
		rowPage and ", with its Default row's Look panel beside them" or ", its Look tabs on the page"),
		act = function() return OpenPage(page, rowPage) end,
		after = function() return Panels() end }
end

local function PlateStep(key, theme, name, shape)
	return { key = key, say = ("%%d/%%d: CineMode turns off. In %%d sec the nameplates' health bars take the %s plate " ..
		"theme: a %s shape and a dark ground behind them."):format(name, shape),
		act = function()
			CineMode(false)
			Set("plateTheme", theme)
			if ns.RefreshPlateHealthStyle then ns.RefreshPlateHealthStyle() end
			if ns.RefreshTargetArrows then ns.RefreshTargetArrows() end
			return "plate theme " .. theme
		end,
		after = function() return Plates() end }
end

local STEPS = {
	PageStep("unit", "Unit Style", "UNIT FRAME STYLE", true),
	PageStep("raid", "Raid Style", "RAID FRAME STYLE", true),
	PageStep("prd", "Personal Style", "PERSONAL RESOURCE STYLE", false),
	PageStep("tooltip", "Tooltip Style", "TOOLTIP STYLE", false),
	PageStep("bubble", "Bubble Style", "CHAT BUBBLE STYLE", false),
	PageStep("action", "Action Style", "ACTION BAR STYLE", false),
	PageStep("combattext", "Combat Text Style", "COMBAT TEXT STYLE", false),
	{ key = "close", say = "%d/%d: CLOSE the settings window now (Escape), and any Look panel beside it. Stand " ..
		"where nameplates show (a town).", act = function() return "waiting for you" end,
		after = function()
			local panel = SettingsPanel or InterfaceOptionsFrame
			return "settings still open: " .. tostring(panel and panel:IsShown())
		end },
	PlateStep("forge", "forge", "EMBERFORGE", "CHISEL (cut corners)"),
	PlateStep("reel", "reel", "SILVER SCREEN", "BEVEL"),
}

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	PutBack()
	if run.cine ~= nil then CineMode(run.cine) end
	for _, index in ipairs(run.steps) do
		local step = STEPS[index]
		local note = run.notes[step.key]
		Say(("verdict %d %s: %s; %s"):format(index, step.key, note and note.acted or "not run",
			note and note.found or "-"))
	end
	run = nil
	ns.MenuTestBackdrop("release6", false)
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped.", "", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local now = GetTime() - run.at
	if now < SETUP then
		ns.PadTestBox("Stand somewhere calm, OUT OF A FIGHT. The test opens each Style page by itself, then asks " ..
			"you to close the settings for the nameplate steps.", ("Starts in %d"):format(math.ceil(SETUP - now)),
			1, 0.82, 0)
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
		Say(("--- step %d: %s (in combat %s, CineMode %s) ---"):format(run.steps[index], step.key,
			tostring(InCombatLockdown()), tostring(ns.lastCinematic)))
	end
	local note = run.notes[step.key]
	if into < WAIT then
		ns.PadTestBox(step.say:format(index, #run.steps, math.ceil(WAIT - into)), "GET READY", 1, 0.82, 0)
	else
		ns.PadTestBox(step.say:format(index, #run.steps, 0), ("RECORDING: %d sec left"):format(math.ceil(STEP - into)),
			0.3, 1, 0.3)
	end
	if not note.acted and into >= WAIT then
		local ok, result = pcall(step.act)
		note.acted = ok and tostring(result) or ("error: " .. tostring(result))
		Say("  " .. note.acted)
	elseif note.acted and not note.shot and into >= WAIT + 3 then
		note.shot = true
		Say("  " .. Shot(("step %d %s"):format(run.steps[index], step.key)))
	elseif note.shot and not note.found and into >= WAIT + 4 then
		local ok, result = pcall(step.after)
		note.found = ok and tostring(result) or ("error: " .. tostring(result))
		Say("  " .. note.found)
	end
end

function ns.StyleSixTest(args)
	if run then
		Finish(false)
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
	CinematicDB.styleSixLog = {}
	run = { at = GetTime(), steps = steps, step = -1, notes = {} }
	ns.MenuTestBackdrop("release6", true) -- (gone for the plate steps: the settings are closed)
	ns.debugNoCopyWindow = true -- (its copy window would sit over the shots)
	local db = ns.GetDB()
	Say(("start: %s (game %s), CineMode %s, in combat %s, theme %s, plate theme %s, steps %s"):format(
		ns.isRetail and "retail" or "Forever", tostring((select(4, GetBuildInfo()))), tostring(ns.lastCinematic),
		tostring(InCombatLockdown()), tostring(db.styleTheme), tostring(db.plateTheme), table.concat(steps, " ")))
	run.ticker = C_Timer.NewTicker(0.5, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print(("release 6 test: %d sec, follow the box (type it again to stop)"):format(SETUP + #steps * STEP))
end
