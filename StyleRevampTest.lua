-- /cine debug stylerevamp [steps]: one run checking the style revamp's
-- releases 1-4 in the game (Tools/style-revamp). Timed steps in the big
-- test box (Frames.lua's ns.PadTestBox); each sets what it shows, takes a
-- screenshot just before the change and 2 seconds into it (the box hidden
-- for them, named in the log), and everything is put back at the end:
--   1 sort:     CineMode on, names on plates: which Name Style row each
--               name goes by (your target, group, players, NPCs...);
--   2 dress:    every name a red outline (the colored outline: its cost,
--               names up and frame rate, before and after), your target's
--               bigger with a gold glow and a dark band;
--   3 theme:    the Subtitle name theme: white names on dark bands;
--   4 main:     Gilded Codex picked on General (then Undo): names in its
--               name theme, plates in its bar; Names unticked on the Pages
--               tab keeps the names it had;
--   5 full:     CineMode off: full plates' names take All names' thick
--               outline and shadow;
--   6 plate:    the Clean plate theme: flat bars with a thin black line;
--   7 panel:    Nameplate Style with a row's Look panel open;
--   8 names:    Name Style;
--   9 pages:    General's Pages tab (the Theme column).
-- (Step 5 waits 8 seconds: you target an NPC first.)
-- Steps as arguments (stylerevamp 2 3) redo just those. Into its own saved
-- list, CinematicDB.styleRevampLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETUP, STEP, WAIT = 12, 14, 4 -- seconds: the first step, each one's, before the change

local run -- { at, steps, step, notes, saved = { key = old }, cine, kept, fps }

local function Say(text)
	local log = CinematicDB and CinematicDB.styleRevampLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end

local function Plain(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Known(value) return value ~= nil and not (issecretvalue and issecretvalue(value)) end

-- A screenshot, the box hidden for it, named in the log by its time as
-- the game names the file (WoWScrnShot_MMDDYY_HHMMSS). From our own
-- function: handed to a timer itself it was refused on Forever.
local function Shot(what)
	ns.PadTestBoxHide()
	local ok, err = pcall(function() Screenshot() end)
	return ok and ("screenshot %s at %s"):format(what, date("%m%d%y_%H%M%S")) or ("screenshot failed: " .. tostring(err))
end

-- A setting for the run, its old value kept to put back. Kept in the saved
-- settings too (CinematicDB.styleRevampPending): a run cut short by a
-- /reload (2026-11-14: left the Subtitle name theme on, every name white)
-- gets them back at the next login.
local function Set(key, value)
	local db = ns.GetDB()
	if run.saved[key] == nil then
		run.saved[key] = { db[key] }
		CinematicDB.styleRevampPending = CinematicDB.styleRevampPending or {}
		local pending = CinematicDB.styleRevampPending
		if pending[key] == nil then pending[key] = { value = db[key] } end
	end
	db[key] = value
end
local function Redraw()
	if ns.NameRowsChanged then ns.NameRowsChanged() end
	if ns.RefreshPlateNameStyle then ns.RefreshPlateNameStyle() end
	if ns.RefreshTargetArrows then ns.RefreshTargetArrows() end
	if ns.RefreshPlateHealthStyle then ns.RefreshPlateHealthStyle() end
	if ns.RefreshPlateGuilds then ns.RefreshPlateGuilds() end
end
local function PutBack()
	local db = ns.GetDB()
	for key, old in pairs(run.saved) do db[key] = old[1] end
	run.saved = {}
	CinematicDB.styleRevampPending = nil
	Redraw()
end

-- A run cut short (a /reload, a disconnect): its settings back at login.
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function()
	local pending = CinematicDB and CinematicDB.styleRevampPending
	if type(pending) ~= "table" then return end
	local db = ns.GetDB()
	local names = {}
	for key, old in pairs(pending) do
		if type(old) == "table" then
			db[key] = old.value
			names[#names + 1] = key
		end
	end
	CinematicDB.styleRevampPending = nil
	if #names > 0 then
		table.sort(names)
		Redraw()
		ns.Print("style revamp test was cut short: put back " .. table.concat(names, ", "))
	end
end)

-- CineMode on or off for a step (names on faded plates need it on); put
-- back as it was at the end.
local function CineMode(on)
	if (ns.lastCinematic and true or false) == on then return end
	if run.cine == nil then run.cine = ns.lastCinematic and true or false end
	if Cinematic_ToggleCineMode then pcall(Cinematic_ToggleCineMode) end
	Say("  CineMode toggled " .. (on and "on" or "off"))
end

-- Every plate on the screen: its unit, kind, Name Style row, and our name
-- text (shown, its width readable, its glow and band, its outline copies).
local function Plates(tag)
	local counts, shown, secretWidths, total = {}, 0, 0, 0
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates() or {}) do
		local unitFrame = plate.UnitFrame
		local forbidden = plate.IsForbidden and plate:IsForbidden()
		if unitFrame and not forbidden then
			total = total + 1
			local unit = plate.namePlateUnitToken or unitFrame.unit
			local okName, name = pcall(UnitName, unit or "")
			local kind = unit and ns.PlateKind and ns.PlateKind(unit)
			local row = ns.NameRowOf and ns.NameRowOf(unitFrame, unit) or "?"
			counts[row] = (counts[row] or 0) + 1
			local text = ns.PlateNameText and ns.PlateNameText(plate)
			local width = text and select(2, pcall(text.GetStringWidth, text))
			if text then shown = shown + 1 end
			if text and not Known(width) then secretWidths = secretWidths + 1 end
			local dress = text and text.cineDress
			Say(("  %s %s: %s kind %s row %s, our text %s width %s, glow %s band %s, outline copies %s"):format(tag,
				tostring(unit), okName and Plain(name) or "error", tostring(kind), tostring(row), text and "shown" or "no",
				Plain(width), tostring(dress and dress.glow:IsShown()), tostring(dress and dress.back:IsShown()),
				tostring(text and text.cineRim and text.cineRim.on)))
		end
	end
	local rows = {}
	for row, count in pairs(counts) do rows[#rows + 1] = row .. " " .. count end
	table.sort(rows)
	return total, shown, secretWidths, table.concat(rows, ", ")
end

-- The frame rate over the last second (the cost of the colored outline).
local function FPS() return GetFramerate and GetFramerate() or 0 end

-- Your target's full plate name: its font flags and shadow (step 5).
local function TargetName()
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
	local name = plate and plate.UnitFrame and plate.UnitFrame.name
	if not name or (plate.IsForbidden and plate:IsForbidden()) then return "no target plate name" end
	local ok, file, size, flags = pcall(name.GetFont, name)
	local okS, sx, sy = pcall(name.GetShadowOffset, name)
	return ("target name font %s size %s flags %s, shadow %s,%s"):format(ok and Plain(file) or "error",
		ok and Plain(size) or "", ok and Plain(flags) or "", okS and Plain(sx) or "?", okS and Plain(sy) or "?")
end

-- A Look panel or page, open, for the panel steps.
local function OpenPage(page)
	if InCombatLockdown() then return "in a fight: not opened" end
	local ok, err = pcall(ns.OpenOptions, page)
	return ok and ("opened " .. page) or ("couldn't open " .. page .. ": " .. tostring(err))
end

-- The steps: what the box says, what changes (APPLY), what's logged after.
local STEPS = {
	{ key = "sort", say = "%d/%d: CineMode is on. Look at the NAMES over heads. Nothing should change: " ..
		"the test reads which kind each name is.",
		apply = function()
			CineMode(true)
			-- (A row with a setting of its own, the same value: names get sorted.)
			Set("nameLookHostileNPCsAlpha", 1)
			Redraw()
		end,
		after = function(note)
			local total, shown, secret, rows = Plates("sort")
			note.verdict = ("plates %d, our names shown %d (secret widths %d), rows: %s"):format(total, shown, secret, rows)
			run.fps = FPS()
		end },
	{ key = "dress", say = "%d/%d: In %d sec EVERY NAME gets a RED OUTLINE, and NPC names get BIGGER with a GOLD " ..
		"GLOW and a DARK BAND behind them.",
		apply = function()
			CineMode(true)
			Set("nameLookHostileNPCsAlpha", 1)
			Set("plateNameOutline", 1)
			Set("plateNameOutlineColor", "custom")
			Set("plateNameOutlineR", 1)
			Set("plateNameOutlineG", 0)
			Set("plateNameOutlineB", 0)
			for _, row in ipairs({ "Target", "FriendlyNPCs", "NeutralNPCs", "HostileNPCs", "ServiceNPCs" }) do
				Set("nameLook" .. row .. "Size", 1.3)
				Set("nameLook" .. row .. "Glow", "soft")
				Set("nameLook" .. row .. "Back", "band")
			end
			local before = debugprofilestop()
			Redraw()
			run.redrawMs = debugprofilestop() - before
		end,
		after = function(note)
			local total, shown, secret, rows = Plates("dress")
			note.verdict = ("names shown %d of %d plates (secret widths %d: their glow and band use one width), " ..
				"rows %s; frame rate %.0f before, %.0f with red outlines; redraw %.1f ms"):format(shown, total, secret,
				rows, run.fps or 0, FPS(), run.redrawMs or 0)
		end },
	{ key = "theme", say = "%d/%d: In %d sec the NAMES turn WHITE on DARK BANDS, like film subtitles.",
		apply = function()
			CineMode(true)
			Set("nameTheme", "subtitle")
			Redraw()
		end,
		after = function(note)
			local _, shown = Plates("theme")
			local theme = ns.NameThemeNow and ns.NameThemeNow()
			note.verdict = ("name theme %s, names shown %d"):format(theme and theme.key or "none", shown)
		end },
	{ key = "main", say = "%d/%d: In %d sec the whole look turns to GILDED CODEX (bars, frames). Names and plates " ..
		"should follow it. Then it's undone.",
		apply = function()
			CineMode(true)
			if InCombatLockdown() then return "in a fight" end
			local db = ns.GetDB()
			run.kept = { db.styleThemeKept }
			Set("nameTheme", "main")
			Set("plateTheme", "main")
			ns.ApplyStyleTheme("codex")
			Redraw()
		end,
		after = function(note)
			local db = ns.GetDB()
			local theme = ns.NameThemeNow and ns.NameThemeNow()
			local texture = ns.PlateThemeBar and ns.PlateThemeBar()
			local _, shown = Plates("main")
			-- (Names unticked on the Pages tab: a pick keeps the names it had.)
			local reachBefore = db.styleThemeReachNames
			db.styleThemeReachNames = false
			ns.ApplyStyleTheme("forge", true)
			local pinned = db.nameTheme
			db.styleThemeReachNames = reachBefore
			ns.UndoStyleTheme()
			db.styleThemeKept = run.kept and run.kept[1]
			note.verdict = ("names follow %s (want codex), plate bar %s (want gilt), names shown %d; Names unticked " ..
				"then Emberforge picked: name theme %s (want codex); undone, theme now %s"):format(theme and theme.key
				or "none", tostring(texture), shown, tostring(pinned), tostring(db.styleTheme))
		end },
	{ key = "full", wait = 8, say = "%d/%d: CLICK an NPC to TARGET it now. CineMode turns OFF. In %d sec the names " ..
		"on the FULL NAMEPLATES get a THICK black OUTLINE and a shadow.",
		apply = function()
			CineMode(false)
			Say("  before: " .. TargetName())
			Set("handlePlateStyle", true)
			Set("plateNameOutline", 2)
			Set("plateNameShadow", true)
			Redraw()
			-- (Ours set? Then whether the game puts its own back: read again later.)
			local plate = C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
			local look = plate and ns.PlateLookNow and ns.PlateLookNow(plate)
			Say(("  just after: looks on %s, target's look outline %s shadow %s, %s"):format(
				tostring(ns.PlateLooksOn and ns.PlateLooksOn()), tostring(look and look.outline),
				tostring(look and look.shadow), TargetName()))
		end,
		after = function(note)
			note.verdict = TargetName() .. " (want THICKOUTLINE in its flags; see 'just after' above: set then put back " ..
				"by the game, or never set)"
		end },
	{ key = "plate", say = "%d/%d: In %d sec the HEALTH BARS on the plates turn FLAT with a THIN BLACK LINE round them.",
		apply = function()
			CineMode(false)
			Set("plateTheme", "clean")
			Redraw()
		end,
		after = function(note)
			local texture, kind, size = ns.PlateThemeBar()
			note.verdict = ("plate theme bar: %s, border %s %s (want flat, line 1)"):format(tostring(texture),
				tostring(kind), tostring(size))
		end },
	{ key = "panel", say = "%d/%d: The settings open on NAMEPLATE STYLE with a row's LOOK panel beside them. Just watch.",
		apply = function()
			local opened = OpenPage("Nameplate Style")
			for _, each in ipairs(ns.LOOK_PANELS or {}) do
				if tostring(each.title):find(" - ", 1, true) and not each.pop:IsShown() then
					each.pop:Show()
					break
				end
			end
			Say("  " .. opened)
		end,
		after = function(note) note.verdict = "see the AFTER screenshot (tags, Hold to compare, Copy look, Paste, Start from a theme)" end },
	{ key = "names", say = "%d/%d: The settings show NAME STYLE. Just watch.",
		apply = function() Say("  " .. OpenPage("Name Style")) end,
		after = function(note)
			-- (A kind's row with nothing of its own: All names' and the game's, never false.)
			local values = {}
			for _, setting in ipairs({ "Colour", "Friends", "Glow", "Back", "Outline" }) do
				local value, from = ns.NameLookValue("GroupMembers", setting)
				values[#values + 1] = ("%s=%s (%s)"):format(setting, tostring(value), tostring(from))
			end
			note.verdict = "Group members row: " .. table.concat(values, ", ") ..
				" (want true, blue, none, none, 0); see the AFTER screenshot (theme strip, scene, rows)"
		end },
	{ key = "pages", say = "%d/%d: The settings show the Style hub's PAGES tab. Just watch.",
		apply = function() Say("  " .. OpenPage("Style Pages")) end,
		after = function(note) note.verdict = "see the AFTER screenshot (the Theme column at the right)" end },
}

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	PutBack()
	if run.cine ~= nil then CineMode(run.cine) end
	local lines = {}
	for _, index in ipairs(run.steps) do
		local step = STEPS[index]
		local note = run.notes[step.key]
		lines[#lines + 1] = ("%d %s: %s"):format(index, step.key, note and (note.skipped and ("COULDN'T: " .. note.skipped)
			or note.verdict) or "not run")
	end
	for _, line in ipairs(lines) do Say("verdict " .. line) end
	ns.Print(("style revamp test %s: %d steps logged"):format(done and "done" or "stopped", #lines))
	run = nil
	ns.PadTestBox(done and "Test done. Close the settings, then /reload." or "Test stopped.",
		"Then say \"check log\"", 1, 0.82, 0)
	C_Timer.After(15, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local now = GetTime() - run.at
	if now < SETUP then
		local plates = C_NamePlate and #C_NamePlate.GetNamePlates() or 0
		ns.PadTestBox("Go where AT LEAST 4 NPCs or players stand near you, their names over their heads (a busy " ..
			"street), OUT OF A FIGHT. Don't target anyone. The test turns CineMode on and off by itself.",
			("%d nameplates on screen (want 4 or more). Starts in %d"):format(plates, math.ceil(SETUP - now)),
			plates >= 4 and 0.3 or 1, plates >= 4 and 1 or 0.6, 0.3)
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
		-- (Each step on its own: the last one's settings put back first.)
		PutBack()
		run.step = index
		run.notes[step.key] = {}
		Say(("--- step %d: %s (in combat %s, CineMode %s) ---"):format(run.steps[index], step.key,
			tostring(InCombatLockdown()), tostring(ns.lastCinematic)))
	end
	local note = run.notes[step.key]
	local wait = step.wait or WAIT -- (a step with something to do first waits longer)
	if into < wait then
		ns.PadTestBox(step.say:format(index, #run.steps, math.ceil(wait - into)), "GET READY: keep watching",
			1, 0.82, 0)
	else
		ns.PadTestBox(step.say:format(index, #run.steps, 0), ("RECORDING: %d sec left"):format(math.ceil(STEP - into)),
			0.3, 1, 0.3)
	end
	if not note.shotBefore and into >= wait - 0.6 and into < wait then
		note.shotBefore = true
		Say("  " .. Shot(("step %d %s BEFORE"):format(run.steps[index], step.key)))
	elseif into >= wait and not note.applied then
		note.applied = true
		local ok, why = pcall(step.apply)
		if not ok then note.skipped = "error: " .. tostring(why) elseif why then note.skipped = why end
		if note.skipped then Say("  couldn't: " .. note.skipped) end
	elseif not note.shotAfter and note.applied and into >= wait + 2.5 then
		note.shotAfter = true
		Say("  " .. Shot(("step %d %s AFTER"):format(run.steps[index], step.key)))
	elseif not note.logged and note.shotAfter and into >= wait + 3.5 then
		note.logged = true
		if not note.skipped then
			local ok, err = pcall(step.after, note)
			if not ok then note.verdict = "error: " .. tostring(err) end
			Say("  " .. tostring(note.verdict))
		end
	end
end

-- Typed again while running: stops.
function ns.StyleRevampTest(args)
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
	CinematicDB.styleRevampLog = {}
	run = { at = GetTime(), steps = steps, step = -1, notes = {}, saved = {} }
	local db = ns.GetDB()
	Say(("start: %s (game %s), CineMode %s, in combat %s, steps %s"):format(ns.isRetail and "retail" or "not retail",
		tostring((select(4, GetBuildInfo()))), tostring(ns.lastCinematic), tostring(InCombatLockdown()),
		table.concat(steps, " ")))
	Say(("settings: style on %s, theme %s, plate theme %s, name theme %s, Name Style page %s, Nameplate Style " ..
		"page %s, moved to inherit %s, game's names kept %s"):format(tostring(db.styleGeneral), tostring(db.styleTheme),
		tostring(db.plateTheme), tostring(db.nameTheme), tostring(db.plateNameStyle), tostring(db.handlePlateStyle),
		tostring(db.nameInheritV1), tostring(db.nameThemeGameV1)))
	local raw = {}
	for _, setting in ipairs({ "Colour", "Friends", "Outline", "Size", "Alpha", "Shadow", "ShadowAlpha", "Font" }) do
		raw[#raw + 1] = setting .. "=" .. tostring(db["plateName" .. setting])
	end
	Say("All names saved: " .. table.concat(raw, " "))
	local reach = {}
	for _, part in ipairs(ns.THEME_PARTS or {}) do reach[#reach + 1] = part .. "=" .. tostring(db["styleThemeReach" .. part]) end
	Say("Theme reaches: " .. table.concat(reach, " "))
	run.ticker = C_Timer.NewTicker(0.5, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print(("style revamp test: %d sec, follow the box (type it again to stop)"):format(SETUP + #steps * STEP))
end
