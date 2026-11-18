-- /cine debug mythemes [steps]: one run checking themes of yours (Style >
-- Themes, StyleThemes.lua) in the game. Timed steps in the big test box
-- (Frames.lua's ns.PadTestBox); each does what a click would, takes a
-- screenshot (the box hidden for it, named in the log) and logs a verdict:
--   1 the Themes tab opens: 5 cards a row, every name fits its card;
--   2 + New theme: one of yours made and picked, the editor under the grid;
--   3 its Health and Accent colors changed: the bars' and menus' colors follow;
--   4 Started from changed to Fel Pact: its shapes and font, your colors kept;
--   5 a change of yours (bar texture), then Save changes: no longer "with
--     your changes";
--   6 Share: the window with its text, read back the same;
--   7 Delete: back on Fel Pact, gone from Yours.
-- Your theme, settings and themes of yours are put back at the end, and at
-- the next login if a /reload cuts it short. Into CinematicDB.myThemesLog.
-- Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETUP, STEP, WAIT = 8, 11, 4 -- seconds: the first step, each one's, before it acts

local run -- { at, steps, step, notes, key }

local function Say(text)
	local log = CinematicDB and CinematicDB.myThemesLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function N(value)
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end
local function Copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for key, each in pairs(value) do out[key] = Copy(each) end
	return out
end

-- (What it changes, kept to put back, here and at the next login.)
local function PutBack()
	local kept = CinematicDB.myThemesPending
	if type(kept) ~= "table" then return end
	CinematicDB.styleMyThemes = kept.store
	if ns.MyStyleThemesChanged then ns.MyStyleThemesChanged() end
	if kept.snapshot and ns.RestoreStyleSnapshot then ns.RestoreStyleSnapshot(kept.snapshot) end
	ns.GetDB().styleThemeKept = kept.undo
	CinematicDB.myThemesPending = nil
	if ns.themePicker and ns.themePicker:IsVisible() then ns.themePicker:Refresh() end
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function()
	if type(CinematicDB and CinematicDB.myThemesPending) == "table" then
		PutBack()
		ns.Print("themes of yours test was cut short: your theme and settings are back")
	end
end)

local function Picker() return ns.themePicker end
local function Parts() return Picker() and Picker().testParts end
local function Refresh()
	if Picker() then Picker():Refresh() end
end
local function Verdict(ok, text) return (ok and "PASS " or "FAIL ") .. text end

-- The grid: cards a row (by their tops), names that don't fit.
local function Grid()
	local parts = Parts()
	if not parts then return Verdict(false, "no picker made") end
	local rows, tooWide, shown, sizes = {}, {}, 0, {}
	for theme, card in pairs(parts.cards) do
		if card:IsShown() then
			shown = shown + 1
			local top = card:GetTop() and math.floor(card:GetTop() + 0.5) or 0
			rows[top] = (rows[top] or 0) + 1
			for _, region in ipairs({ card:GetRegions() }) do
				if region.GetStringWidth and region:GetText() == ns.StyleThemeName(theme) then
					local wide = region.GetUnboundedStringWidth and region:GetUnboundedStringWidth()
						or region:GetStringWidth()
					-- (Against its own box: wider than that is cut off with "...".)
					if wide > region:GetWidth() then
						tooWide[#tooWide + 1] = ("%s %.0f>%.0f"):format(region:GetText(), wide, region:GetWidth())
					end
					sizes[#sizes + 1] = ("%s %.0f"):format(region:GetText(), select(2, region:GetFont()) or 0)
				end
			end
		end
	end
	local most = 0
	for _, count in pairs(rows) do most = math.max(most, count) end
	return Verdict(most == 5 and #tooWide == 0, ("%d cards shown, most in a row %d (want 5), card %.0f wide, " ..
		"picker %.0f wide, names too wide: %s"):format(shown, most, parts.cardW, Picker():GetWidth(),
		#tooWide > 0 and table.concat(tooWide, ", ") or "none")) .. "; sizes " .. table.concat(sizes, ", ")
end

local STEPS = {
	{ key = "open", say = "%d/%d: The settings open on Style > Themes. Just watch.",
		act = function()
			if InCombatLockdown() then return "in a fight: not opened" end
			ns.OpenOptions("Style Themes")
			return "opened"
		end,
		after = Grid },
	{ key = "new", say = "%d/%d: + New theme is pressed: a theme of yours appears under Yours, picked, " ..
		"with its editor under the grid.",
		act = function()
			local parts = Parts()
			if not parts then return "no picker" end
			parts.newCard:Click()
			run.key = ns.GetDB().styleTheme
			return "clicked; theme now " .. tostring(run.key)
		end,
		after = function()
			local parts = Parts()
			local mine = ns.MyStyleThemes()
			local ok = run.key and run.key:find("^u:") and parts.editor:IsShown()
			return Verdict(ok, ("yours %d, theme %s, editor shown %s, status '%s'"):format(#mine, tostring(run.key),
				tostring(parts.editor:IsShown()), tostring(parts.status:GetText())))
		end },
	{ key = "colors", say = "%d/%d: Its Health turns GREEN-BLUE and its Accent PINK: health bars, titles and " ..
		"the menus' highlights follow.",
		act = function()
			if not run.key then return "no theme of yours" end
			ns.SetMyStyleThemeColor(run.key, "health", { 0.1, 0.8, 0.7 })
			ns.SetMyStyleThemeColor(run.key, "accent", { 1, 0.3, 0.7 })
			Refresh()
			return "set"
		end,
		after = function()
			local db = ns.GetDB()
			local accent = ns.ThemeAccent() or {}
			local ok = math.abs((db.ufHealthR or 0) - 0.1) < 0.01 and math.abs((accent[1] or 0) - 1) < 0.01
				and math.abs((accent[2] or 0) - 0.3) < 0.01
			return Verdict(ok, ("ufHealth %s %s %s, accent %s %s %s, palette key %s"):format(N(db.ufHealthR),
				N(db.ufHealthG), N(db.ufHealthB), N(accent[1]), N(accent[2]), N(accent[3]), tostring(ns.MenuPaletteKey())))
		end },
	{ key = "base", say = "%d/%d: Started from turns to FEL PACT: its shapes and lettering, your green-blue " ..
		"health and pink kept.",
		act = function()
			if not run.key then return "no theme of yours" end
			ns.SetMyStyleThemeBase(run.key, "fel")
			Refresh()
			return "set"
		end,
		after = function()
			local db, theme = ns.GetDB(), ns.StyleThemeByKey(run.key)
			local fel = ns.StyleThemeByKey("fel")
			local ok = theme and theme.base == "fel" and db.stylePanel == fel.settings.stylePanel
				and math.abs((db.ufHealthR or 0) - 0.1) < 0.01
			return Verdict(ok, ("base %s, panel %s (Fel's %s), font %s, ufHealthR %s"):format(tostring(theme and theme.base),
				tostring(db.stylePanel), tostring(fel.settings.stylePanel), tostring(db.styleFont), N(db.ufHealthR)))
		end },
	{ key = "save", say = "%d/%d: The bar texture changes to Flat (a change of yours), then Save changes is pressed.",
		act = function()
			if not run.key then return "no theme of yours" end
			ns.GetDB().styleTexture = "flat"
			if ns.RefreshAllStyles then ns.RefreshAllStyles() end
			Refresh()
			local parts = Parts()
			local shown = parts.save:IsShown()
			local edited = ns.StyleThemeEdited()
			parts.save:Click()
			return ("before: edited %s, Save changes shown %s"):format(tostring(edited), tostring(shown))
		end,
		after = function()
			local entry = ns.StyleThemeByKey(run.key)
			local ok = not ns.StyleThemeEdited() and entry and entry.settings.styleTexture == "flat"
			return Verdict(ok, ("after: edited %s, saved texture %s, status '%s'"):format(tostring(ns.StyleThemeEdited()),
				tostring(entry and entry.settings.styleTexture), tostring(Parts().status:GetText())))
		end },
	{ key = "share", say = "%d/%d: Share: a window opens with the theme as a line of text.",
		act = function()
			if not run.key then return "no theme of yours" end
			run.text = ns.ExportMyStyleTheme(run.key)
			ns.ShowCameraShare(run.text, "Share test")
			return "text " .. tostring(run.text and #run.text) .. " letters"
		end,
		after = function()
			local info = run.text and ns.ReadSharedStyleTheme(run.text)
			local ok = info and info.base == "fel" and info.settings.styleTexture == "flat" and info.colors.health
				and info.skipped == 0
			return Verdict(ok, ("read back: name %s, base %s, texture %s, skipped %s"):format(tostring(info and info.name),
				tostring(info and info.base), tostring(info and info.settings.styleTexture), tostring(info and info.skipped)))
		end },
	{ key = "delete", say = "%d/%d: The share window closes and the theme of yours is deleted: back on Fel Pact.",
		act = function()
			local window = _G.CinematicCameraShareWindow
			if window then window:Hide() end
			if not run.key then return "no theme of yours" end
			ns.DeleteMyStyleTheme(run.key)
			Refresh()
			return "deleted"
		end,
		after = function()
			local db = ns.GetDB()
			local ok = db.styleTheme == "fel" and not ns.StyleThemeByKey(run.key) and not Parts().editor:IsShown()
			return Verdict(ok, ("theme now %s, still there %s, editor shown %s, yours %d"):format(tostring(db.styleTheme),
				tostring(ns.StyleThemeByKey(run.key) ~= nil), tostring(Parts().editor:IsShown()), #ns.MyStyleThemes()))
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
	ns.PadTestBox(done and "Test done: your theme is back. /reload, then say \"check log\"." or "Test stopped.",
		"", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local now = GetTime() - run.at
	if now < SETUP then
		ns.PadTestBox("Stand somewhere calm, OUT OF A FIGHT. The test opens Style > Themes and does each click " ..
			"itself. Just watch. Your theme comes back at the end.", ("Starts in %d"):format(math.ceil(SETUP - now)),
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
		Say(("--- step %d: %s (in combat %s, theme %s) ---"):format(run.steps[index], step.key,
			tostring(InCombatLockdown()), tostring(ns.GetDB().styleTheme)))
	end
	local note = run.notes[step.key]
	if into < WAIT then
		ns.PadTestBox(step.say:format(index, #run.steps), "GET READY", 1, 0.82, 0)
	else
		ns.PadTestBox(step.say:format(index, #run.steps), ("RECORDING: %d sec left"):format(math.ceil(STEP - into)),
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

function ns.MyThemesTest(args)
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("themes of yours test: not in a fight")
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
	local db = ns.GetDB()
	CinematicDB.myThemesLog = {}
	CinematicDB.myThemesPending = { store = Copy(CinematicDB.styleMyThemes), snapshot = ns.StyleSnapshot(),
		undo = Copy(db.styleThemeKept) }
	run = { at = GetTime(), steps = steps, step = -1, notes = {} }
	-- (Picked on one of ours, so + New theme copies it with its art.)
	if not db.styleGeneral or (db.styleTheme or "game") == "game" or tostring(db.styleTheme):find("^u:") then
		ns.ApplyStyleTheme("vanguard", true)
	end
	Say(("start: %s (game %s), theme %s, yours %d, steps %s"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), tostring(ns.GetDB().styleTheme), #ns.MyStyleThemes(),
		table.concat(steps, " ")))
	run.ticker = C_Timer.NewTicker(0.5, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print(("themes of yours test: %d sec, follow the box (type it again to stop)"):format(SETUP + #steps * STEP))
end
