-- /cine debug themeart: one run on a style theme's own frame art (the plate,
-- bridge, shadow and portrait ring it draws in place of the game's) going with
-- the unit frames' Frame art rows and their Style Overrides (a player's
-- question, 2026-11-20: the Pet Frame's Frame art row unticked, the theme's
-- box stayed drawn round the pet frame). Out of a fight, no target; a pet out
-- adds the pet frame (the player frame is checked either way). CineMode off,
-- Crimson Vanguard on (its pages switched on, every switch above them too),
-- the HUD's Unit frames section and the Overrides tabs on. Steps, a screenshot
-- and a verdict each, for every frame checked:
--   1 row ticked, override Interface page: the theme's box drawn
--   2 row unticked (every column off), override Interface page: box hidden
--     with the game's art (the bug: it stayed)
--   3 row ticked, override Hide: box hidden
--   4 row unticked, override Show: box drawn
--   5 back as step 1: box drawn again
-- Verdicts against what the Why window says of the Art part
-- (ns.UnitPartsWhy): hidden there = every theme piece at alpha 0 or not
-- shown. Each piece's shown and alpha logged. Your theme, rows, overrides and
-- switches put back at the end, and at the next login if a /reload cuts it
-- short. Into CinematicDB.themeArtLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETUP, STEP, SETTLE = 8, 7, 3 -- seconds
local LISTS = { "combatShow", "quietShow", "camShow", "enemyShow", "friendlyShow" }
local FRAMES = { { "PlayerFrame", "Player" }, { "PetFrame", "Pet" } }

local STEPS = {
	{ key = "row ticked", row = true, over = "row", drawn = true },
	{ key = "row unticked", row = false, over = "row", drawn = false },
	{ key = "override hide", row = true, over = "hide", drawn = false },
	{ key = "override show", row = false, over = "show", drawn = true },
	{ key = "back", row = true, over = "row", drawn = true },
}

local run -- { at, index, step, frames, pass, fail, ticker }

local function Say(text)
	local log = CinematicDB and CinematicDB.themeArtLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end

-- (What it changes, kept to put back, here and at the next login: db keys with
-- their values, a list's entries as { list, key, value }.)
local function PutBack()
	local kept = CinematicDB.themeArtPending
	if type(kept) ~= "table" then return end
	CinematicDB.themeArtPending = nil
	local db = ns.GetDB()
	for _, each in ipairs(kept.lists or {}) do
		if type(db[each[1]]) == "table" then db[each[1]][each[2]] = each[3] end
	end
	for key, value in pairs(kept.keys or {}) do
		if value == "nil" then db[key] = nil else db[key] = value end
	end
	if kept.snapshot and ns.RestoreStyleSnapshot then ns.RestoreStyleSnapshot(kept.snapshot) end
	if ns.ApplyUnitFrameParts then ns.ApplyUnitFrameParts() end
	if kept.cineWasOn and ns.IsCineModeOn and not ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		Cinematic_ToggleCineMode()
	end
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function()
	if type(CinematicDB and CinematicDB.themeArtPending) == "table" then
		PutBack()
		ns.Print("theme art test was cut short: your theme and rows are back")
	end
end)

local function Keep(key, value)
	local kept = CinematicDB.themeArtPending.keys
	if kept[key] == nil then
		local was = ns.db[key]
		kept[key] = was == nil and "nil" or was
	end
	ns.db[key] = value
end
local function KeepList(list, key, value)
	local db = ns.db
	if type(db[list]) ~= "table" then return end
	local kept = CinematicDB.themeArtPending.lists
	kept[#kept + 1] = { list, key, db[list][key] }
	db[list][key] = value
end

-- The Art part as the Why window has it: hidden, override, held.
local function ArtWhy(name)
	for _, part in ipairs(ns.UnitPartsWhy and ns.UnitPartsWhy(name) or {}) do
		if part.part == "Art" then return part end
	end
end
-- Each theme piece: shown and alpha; drawn = any shown above 0.01.
local function Pieces(frame)
	local list, drawn, count = {}, false, 0
	for i, region in ipairs(ns.UnitThemeArt(frame)) do
		count = count + 1
		local shown, alpha = region:IsShown(), region:GetAlpha()
		if issecretvalue and issecretvalue(alpha) then alpha = -1 end
		if shown and alpha > 0.01 then drawn = true end
		list[#list + 1] = ("%d %s a%.2f"):format(i, shown and "shown" or "hidden", alpha)
	end
	return drawn, count, table.concat(list, ", ")
end

local function SetStep(spec)
	for _, each in ipairs(run.frames) do
		local key = "unitPart" .. each[2] .. "Art"
		Keep(key, spec.row)
		Keep("styleOver_" .. key, spec.over)
	end
	if ns.ApplyUnitFrameParts then ns.ApplyUnitFrameParts() end
	if ns.RefreshAllStyles then ns.RefreshAllStyles() end
end

local function Check(spec)
	for _, each in ipairs(run.frames) do
		local frame = _G[each[1]]
		local why = ArtWhy(each[1]) or {}
		local drawn, count, line = Pieces(frame)
		-- (The game's art hidden or not, as the row and override say; the box with it.)
		local ok = count > 0 and drawn == spec.drawn and (not why.hidden) == spec.drawn
		if ok then run.pass = run.pass + 1 else run.fail = run.fail + 1 end
		Say(("  %s %s: box %s (want %s), Why: hidden %s over %s held %s; %d pieces: %s"):format(
			ok and "PASS" or "FAIL", each[1], drawn and "drawn" or "hidden", spec.drawn and "drawn" or "hidden",
			tostring(why.hidden), tostring(why.over), tostring(why.held), count, line))
		if count == 0 then Say("    no theme pieces on this frame: the theme's shape isn't drawn") end
	end
end

local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	Say(("  screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	PutBack()
	Say(("done: %d PASS, %d FAIL%s"):format(run.pass, run.fail, done and "" or " (stopped early)"))
	run = nil
	ns.PadTestBox(done and "Test done: your theme is back. /reload, then say \"check log\"." or "Test stopped.",
		"", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local now = GetTime() - run.at
	if InCombatLockdown() then
		Say("stopped: a fight started")
		Finish(false)
		return
	end
	if now < SETUP then
		ns.PadTestBox("Stand somewhere calm, OUT OF A FIGHT, NO target. Call your pet if you have one. "
			.. "The test changes the settings itself. Just watch your frames at the bottom left.",
			("Starts in %d"):format(math.ceil(SETUP - now)), 1, 0.82, 0)
		return
	end
	local step = run.step
	if not step or GetTime() - step.at >= STEP then
		run.index = run.index + 1
		local spec = STEPS[run.index]
		if not spec then
			Finish(true)
			return
		end
		SetStep(spec)
		run.step = { spec = spec, at = GetTime() }
		Say(("--- step %d: %s (row %s, override %s, target %s) ---"):format(run.index, spec.key,
			tostring(spec.row), spec.over, tostring(UnitExists("target"))))
		step = run.step
	end
	local into = GetTime() - step.at
	if into >= SETTLE and not step.checked then
		step.checked = true
		Check(step.spec)
		Shot(("step %d %s"):format(run.index, step.spec.key))
		return
	end
	if into >= SETTLE and into < SETTLE + 1 then return end -- (the screenshot's moment: no box)
	ns.PadTestBox(("%d/%d: Frame art %s, override %s. The theme's box should be %s."):format(run.index, #STEPS,
		step.spec.row and "ticked" or "unticked", step.spec.over, step.spec.drawn and "DRAWN" or "GONE"),
		("RECORDING: %d sec left"):format(math.ceil(STEP - into)), 0.3, 1, 0.3)
end

function ns.ThemeArtTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("theme art test: not in a fight")
		return
	end
	if type(CinematicDB.themeArtPending) == "table" then PutBack() end
	CinematicDB.themeArtLog = {}
	CinematicDB.themeArtPending = { keys = {}, lists = {}, snapshot = ns.StyleSnapshot(),
		cineWasOn = ns.IsCineModeOn() }
	run = { at = GetTime(), index = 0, pass = 0, fail = 0, frames = {} }
	for _, each in ipairs(FRAMES) do
		if each[1] == "PlayerFrame" or UnitExists("pet") then run.frames[#run.frames + 1] = each end
	end
	Say(("start: %s (game %s), version %s, theme %s, pet %s, target %s"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), tostring(C_AddOns.GetAddOnMetadata("CinematicDev", "Version")),
		tostring(ns.GetDB().styleTheme), tostring(UnitExists("pet")), tostring(UnitExists("target"))))
	for _, each in ipairs(run.frames) do
		local key = "unitPart" .. each[2] .. "Art"
		Say(("  %s: row %s, override %s, rule %s"):format(key, tostring(ns.db[key]),
			tostring(ns.db["styleOver_" .. key]), tostring(ns.RuleTest and ns.RuleTest(key))))
	end
	if ns.IsCineModeOn() and Cinematic_ToggleCineMode then Cinematic_ToggleCineMode() end
	-- (The theme, then every switch its unit frames, the HUD's unit rows and the
	-- Overrides tabs are under: Style switch chain.)
	ns.ApplyStyleTheme("vanguard", true)
	for _, start in ipairs({ "ufStyle", "showInUnits", "styleOverrides", "tabOn:Style Overrides:1",
		"tabOn:Style Overrides:3" }) do
		local switch = start
		while switch do
			Keep(switch, true)
			switch = ns.PageSwitchOf(switch)
		end
	end
	-- (Unticked = every column off too, so only Always decides: nothing brings it up.)
	for _, each in ipairs(run.frames) do
		for _, list in ipairs(LISTS) do KeepList(list, "unitPart" .. each[2] .. "Art", false) end
	end
	Say(("theme now %s, shape %s, layout %s, CineMode %s"):format(tostring(ns.GetDB().styleTheme),
		tostring(ns.db.ufShape), tostring(ns.ThemeLayout and ns.ThemeLayout()), tostring(ns.IsCineModeOn())))
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.TestPrompt("Theme art test: follow the box (type it again to stop)")
end
