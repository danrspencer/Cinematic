-- /cine debug mythemes [steps]: one run checking themes (Style > Themes,
-- StyleThemes.lua) in the game: changing, saving, describing, sharing,
-- importing, backups and deleting. Timed steps in the big test box
-- (Frames.lua's ns.PadTestBox); each does what a click would, takes a
-- screenshot (the box hidden for it, named in the log) and logs a verdict:
--   1 the Themes tab opens: 5 cards a row, every name fits its card;
--   2 a change over Crimson Vanguard (bar texture): "(changed)" on its card;
--   3 Silver Screen's card pointed at: the box under the grids describes it;
--   4 + New theme: one of yours with that change in it, nothing "(changed)";
--   5 its Health and Accent colors changed: the bars' and menus' colors follow;
--   6 Started from changed to Fel Pact: its shapes and font, your colors kept;
--   7 a description written: the box shows it for its card;
--   8 another change, then Save changes: a backup of the saved version taken;
--   9 Share: the window with its text, read back with its description;
--  10 Share on one of ours (Crimson Vanguard): read back as that theme;
--  11 Import of the step 9 text: a second theme of yours just like it, used;
--  12 Backups of yours: the window with the step 8 backup;
--  13 both deleted: back on Fel Pact, both under Recently deleted;
--  14 the first restored from Recently deleted: description and colors back.
-- Your theme, settings, themes of yours and their backups are put back at the
-- end, and at the next login if a /reload cuts it short. Into
-- CinematicDB.myThemesLog. Dev copy only (CinematicDev.toc).
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
	CinematicDB.styleThemeBackups, CinematicDB.styleThemesDeleted = kept.backups, kept.deleted
	for _, name in ipairs({ "CinematicCameraShareWindow", "CinematicBackupsWindow" }) do
		if _G[name] then _G[name]:Hide() end
	end
	if ns.MyStyleThemesChanged then ns.MyStyleThemesChanged() end
	if kept.snapshot and ns.RestoreStyleSnapshot then ns.RestoreStyleSnapshot(kept.snapshot) end
	ns.GetDB().styleThemeKept = kept.undo
	CinematicDB.myThemesPending = nil
	if kept.cineWasOn and ns.IsCineModeOn and not ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		Cinematic_ToggleCineMode()
	end
	if ns.themePicker and ns.themePicker:IsVisible() then ns.themePicker:Refresh() end
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function()
	if type(CinematicDB and CinematicDB.myThemesPending) == "table" then
		PutBack()
		ns.Print("themes test was cut short: your theme and settings are back")
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
	for _, card in pairs(parts.cards) do
		local theme = card.theme or ns.StyleThemeByKey("game")
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

local NOTE = "Test theme: teal health, pink titles"

-- (A card's words in the box: pointed at, read, let go.)
local function Hover(key)
	local parts = Parts()
	local card = parts and parts.cards[key]
	if not (card and card:IsShown()) then return nil end
	local enter = card:GetScript("OnEnter")
	if enter then enter(card) end
	return parts.about:GetText()
end
local function Unhover(key)
	local parts = Parts()
	local card = parts and parts.cards[key]
	local leave = card and card:GetScript("OnLeave")
	if leave then leave(card) end
end
-- Which cards show "(changed)".
local function Tagged()
	local list = {}
	for key, card in pairs(Parts().cards) do
		if card:IsShown() and card.changedTag and card.changedTag:IsShown() then list[#list + 1] = key end
	end
	table.sort(list)
	return table.concat(list, ",")
end
local function Has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
-- A bar texture that isn't the one on now (a change of yours).
local function OtherTexture()
	local now = ns.GetDB().styleTexture
	for _, each in ipairs({ "flat", "gilt", "reel" }) do
		if each ~= now then return each end
	end
end
local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end
local function BackupsOf(key)
	for _, each in ipairs((ns.StyleThemeBackups())) do
		if each.key == key then return each.backups end
	end
	return {}
end
local function CloseWindows()
	for _, name in ipairs({ "CinematicCameraShareWindow", "CinematicBackupsWindow" }) do
		if _G[name] then _G[name]:Hide() end
	end
end

local STEPS = {
	{ key = "open", say = "%d/%d: The settings open on Style > Themes. Just watch.",
		act = function()
			if InCombatLockdown() then return "in a fight: not opened" end
			ns.OpenOptions("Style Themes")
			return "opened"
		end,
		after = Grid },
	{ key = "changed", say = "%d/%d: The bar texture changes (a change of yours). Crimson Vanguard's card " ..
		"gets a small (changed) at its bottom right.",
		act = function()
			if ns.GetDB().styleTheme ~= "vanguard" then ns.ApplyStyleTheme("vanguard", true) end
			run.texture = OtherTexture()
			ns.GetDB().styleTexture = run.texture
			if ns.RefreshAllStyles then ns.RefreshAllStyles() end
			Refresh()
			return "texture now " .. tostring(run.texture)
		end,
		after = function()
			local text = Parts().about:GetText()
			local ok = ns.StyleThemeEdited() and Tagged() == "vanguard" and Has(text, "(changed)")
			return Verdict(ok, ("edited %s, tagged '%s' (want vanguard), box '%s', status '%s'"):format(
				tostring(ns.StyleThemeEdited()), Tagged(), tostring(text), tostring(Parts().status:GetText())))
		end },
	{ key = "hover", say = "%d/%d: The mouse points at SILVER SCREEN's card (top row, second): the box under the " ..
		"cards says what it is and \"Click to use it.\"",
		act = function()
			run.hovered = Hover("reel")
			return "hovered: " .. tostring(run.hovered ~= nil)
		end,
		after = function()
			local text = run.hovered
			Unhover("reel")
			local back = Parts().about:GetText()
			local ok = Has(text, ns.StyleThemeName(ns.StyleThemeByKey("reel"))) and Has(text, "Click to use it")
				and Has(back, ns.StyleThemeName(ns.StyleThemeByKey("vanguard")))
			return Verdict(ok, ("pointed at '%s'; let go '%s'; box %.0f high"):format(tostring(text), tostring(back),
				Parts().box:GetHeight()))
		end },
	{ key = "new", say = "%d/%d: + New theme is pressed: a theme of yours appears under Yours with your " ..
		"texture in it, and no card says (changed).",
		act = function()
			Parts().newCard:Click()
			run.key = ns.GetDB().styleTheme
			return "clicked; theme now " .. tostring(run.key)
		end,
		after = function()
			local theme = run.key and ns.StyleThemeByKey(run.key)
			local ok = run.key and run.key:find("^u:") and Parts().editor:IsShown() and theme
				and theme.settings.styleTexture == run.texture and not ns.StyleThemeEdited() and Tagged() == ""
			return Verdict(ok, ("yours %d, theme %s, its texture %s (want %s), edited %s, tagged '%s', editor %s"):format(
				#ns.MyStyleThemes(), tostring(run.key), tostring(theme and theme.settings.styleTexture),
				tostring(run.texture), tostring(ns.StyleThemeEdited()), Tagged(), tostring(Parts().editor:IsShown())))
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
	{ key = "note", say = "%d/%d: A description is written for your theme, and the mouse points at its card: " ..
		"the box shows \"" .. NOTE .. "\".",
		act = function()
			if not run.key then return "no theme of yours" end
			ns.SetMyStyleThemeNote(run.key, NOTE)
			Refresh()
			run.hovered = Hover(run.key)
			return "written; hovered " .. tostring(run.hovered ~= nil)
		end,
		after = function()
			Unhover(run.key)
			local ok = ns.MyStyleThemeNote(run.key) == NOTE and Has(run.hovered, NOTE)
			return Verdict(ok, ("note '%s', box '%s'"):format(tostring(ns.MyStyleThemeNote(run.key)), tostring(run.hovered)))
		end },
	{ key = "save", say = "%d/%d: The bar texture changes again ((changed) on your card), then Save changes is pressed.",
		act = function()
			if not run.key then return "no theme of yours" end
			run.texture = OtherTexture()
			ns.GetDB().styleTexture = run.texture
			if ns.RefreshAllStyles then ns.RefreshAllStyles() end
			Refresh()
			local tagged, shown, edited = Tagged(), Parts().save:IsShown(), ns.StyleThemeEdited()
			Parts().save:Click()
			return ("before: edited %s, tagged '%s', Save changes shown %s"):format(tostring(edited), tagged, tostring(shown))
		end,
		after = function()
			local theme = ns.StyleThemeByKey(run.key)
			local backups = BackupsOf(run.key)
			local ok = not ns.StyleThemeEdited() and theme and theme.settings.styleTexture == run.texture
				and backups[1] and backups[1].why == "save" and Tagged() == ""
			return Verdict(ok, ("after: edited %s, saved texture %s (want %s), tagged '%s', backups %d, newest %s"):format(
				tostring(ns.StyleThemeEdited()), tostring(theme and theme.settings.styleTexture), tostring(run.texture),
				Tagged(), #backups, tostring(backups[1] and backups[1].why)))
		end },
	{ key = "share", say = "%d/%d: Share: a window opens with your theme as a line of text.",
		act = function()
			if not run.key then return "no theme of yours" end
			run.text = ns.ExportStyleTheme(run.key)
			ns.ShowCameraShare(run.text, "Share test")
			return "text " .. tostring(run.text and #run.text) .. " letters"
		end,
		after = function()
			local info = run.text and ns.ReadSharedStyleTheme(run.text)
			local ok = info and info.base == "fel" and info.settings.styleTexture == run.texture and info.colors.health
				and info.note == NOTE and info.skipped == 0
			return Verdict(ok, ("read back: name %s, base %s, texture %s, note '%s', skipped %s"):format(
				tostring(info and info.name), tostring(info and info.base), tostring(info and info.settings.styleTexture),
				tostring(info and info.note), tostring(info and info.skipped)))
		end },
	{ key = "shareours", say = "%d/%d: Share on one of ours: the window shows CRIMSON VANGUARD as text.",
		act = function()
			CloseWindows()
			run.oursText = ns.ExportStyleTheme("vanguard")
			ns.ShowCameraShare(run.oursText, "Share test (ours)")
			return "text " .. tostring(run.oursText and #run.oursText) .. " letters"
		end,
		after = function()
			local info = run.oursText and ns.ReadSharedStyleTheme(run.oursText)
			local ok = info and info.base == "vanguard" and info.skipped == 0
			return Verdict(ok, ("read back: name %s, base %s, settings %d"):format(tostring(info and info.name),
				tostring(info and info.base), info and Count(info.settings) or -1))
		end },
	{ key = "import", say = "%d/%d: Your theme's text is imported: a second theme just like it appears under " ..
		"Yours and is used.",
		act = function()
			CloseWindows()
			local info, why = ns.ReadSharedStyleTheme(run.text)
			if not info then return "not read: " .. tostring(why) end
			local key
			key, why = ns.AddSharedStyleTheme(info)
			if not key then return "not added: " .. tostring(why) end
			run.imported = key
			ns.ApplyStyleTheme(key)
			Refresh()
			return "added " .. key
		end,
		after = function()
			local a, b = ns.StyleThemeByKey(run.key), run.imported and ns.StyleThemeByKey(run.imported)
			local ok = a and b and run.imported ~= run.key and ns.GetDB().styleTheme == run.imported
				and ns.MyStyleThemeNote(run.imported) == NOTE and b.base == a.base
				and b.settings.styleTexture == a.settings.styleTexture
				and Same(ns.MyStyleThemeColor(run.imported, "health"), ns.MyStyleThemeColor(run.key, "health"))
			return Verdict(ok, ("imported %s as '%s', in use %s, note '%s', base %s, texture %s, yours %d"):format(
				tostring(run.imported), tostring(b and b.name), tostring(ns.GetDB().styleTheme),
				tostring(run.imported and ns.MyStyleThemeNote(run.imported)), tostring(b and b.base),
				tostring(b and b.settings.styleTexture), #ns.MyStyleThemes()))
		end },
	{ key = "backups", say = "%d/%d: The Backups window opens for your first theme: a row saying Before save.",
		act = function()
			if not run.key then return "no theme of yours" end
			ns.ShowStyleThemeBackups(run.key)
			return "opened"
		end,
		after = function()
			local window = _G.CinematicBackupsWindow
			local rows = 0
			for _, row in ipairs(window and window.rows or {}) do
				if row:IsShown() then rows = rows + 1 end
			end
			local ok = window and window:IsShown() and rows >= 1
			return Verdict(ok, ("window shown %s, title '%s', rows %d, backups %d"):format(
				tostring(window and window:IsShown()), tostring(window and window.title:GetText()), rows,
				#BackupsOf(run.key)))
		end },
	{ key = "delete", say = "%d/%d: Both themes of yours are deleted: back on Fel Pact. The Backups window " ..
		"lists both under Recently deleted.",
		act = function()
			CloseWindows()
			if run.imported then ns.DeleteMyStyleTheme(run.imported) end
			if run.key then ns.DeleteMyStyleTheme(run.key) end
			Refresh()
			ns.ShowStyleThemeBackups(nil)
			return "deleted"
		end,
		after = function()
			local _, deleted = ns.StyleThemeBackups()
			local ok = ns.GetDB().styleTheme == "fel" and not ns.StyleThemeByKey(run.key)
				and not (run.imported and ns.StyleThemeByKey(run.imported)) and #deleted >= 2
			return Verdict(ok, ("theme now %s, yours %d, recently deleted %d (newest '%s')"):format(
				tostring(ns.GetDB().styleTheme), #ns.MyStyleThemes(), #deleted, tostring(deleted[1] and deleted[1].name)))
		end },
	{ key = "restore", say = "%d/%d: Your first theme comes back from Recently deleted and is used: pink and " ..
		"green-blue again.",
		act = function()
			CloseWindows()
			local key, why = ns.RestoreDeletedStyleTheme(1)
			if not key then return "not restored: " .. tostring(why) end
			run.restored = key
			ns.ApplyStyleTheme(key)
			Refresh()
			return "restored " .. key
		end,
		after = function()
			local theme = run.restored and ns.StyleThemeByKey(run.restored)
			local health = run.restored and ns.MyStyleThemeColor(run.restored, "health") or {}
			local ok = theme and theme.base == "fel" and ns.MyStyleThemeNote(run.restored) == NOTE
				and math.abs((health[1] or 0) - 0.1) < 0.01 and #BackupsOf(run.restored) >= 1
			return Verdict(ok, ("restored %s '%s', base %s, note '%s', health %s, its backups %d"):format(
				tostring(run.restored), tostring(theme and theme.name), tostring(theme and theme.base),
				tostring(run.restored and ns.MyStyleThemeNote(run.restored)), N(health[1]),
				run.restored and #BackupsOf(run.restored) or 0))
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
		ns.Print("themes test: not in a fight")
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
		undo = Copy(db.styleThemeKept), backups = Copy(CinematicDB.styleThemeBackups),
		deleted = Copy(CinematicDB.styleThemesDeleted), cineWasOn = ns.IsCineModeOn() }
	run = { at = GetTime(), steps = steps, step = -1, notes = {} }
	-- (CineMode off for the run, as the Toggle CineMode key does it, so the
	-- frames and bars the steps change are on screen and in the screenshots.
	-- Back on at the end; a /reload brings it back by itself.)
	if ns.IsCineModeOn() and Cinematic_ToggleCineMode then Cinematic_ToggleCineMode() end
	-- (On Crimson Vanguard as it comes, so step 2's change is the only one.)
	ns.ApplyStyleTheme("vanguard", true)
	Say(("start: %s (game %s), theme %s, yours %d, steps %s"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), tostring(ns.GetDB().styleTheme), #ns.MyStyleThemes(),
		table.concat(steps, " ")))
	Say(("CineMode was on %s, now on %s"):format(tostring(CinematicDB.myThemesPending.cineWasOn),
		tostring(ns.IsCineModeOn())))
	run.ticker = C_Timer.NewTicker(0.5, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print(("themes test: %d sec, follow the box (type it again to stop)"):format(SETUP + #steps * STEP))
end
