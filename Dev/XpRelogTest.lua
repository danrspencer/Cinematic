-- /cine debug xprelog: does a relog (out to character select and back in,
-- no game restart) change the font the game draws its floating text in (the
-- "XP: 58" over you, and its damage numbers: one font, DAMAGE_TEXT_FONT)?
-- We only ever tested /reload, which keeps the font from the game's start.
-- A player saw XP text come back "sometimes after a relog" (2026-11-20).
--   1 now:    you kill one enemy; screenshots of the XP text as the game
--             draws it now (the font from the game's start, or last login).
--   2 relog:  the test sets the OTHER font (blank if it's the game's, the
--             game's if it's blank) for that one login only, at the addon's
--             load, after each addon loads and at login (as Core does).
--             You log out to character select and back in.
--   3 after:  you kill one more enemy; screenshots again. XP text changed
--             between 1 and 3 = the game reads the font at each login, so
--             the "needs a full restart" note is wrong for relogs.
-- Into CinematicDB.xpRelogTestLog; the screenshots are named in it, and I
-- read them. The next login after the test uses your settings again. Run
-- again to stop it. Dev copy only.
local ADDON_NAME, ns = ...

local BLANK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\Blank.ttf"
local SHOT_TIMES = { 0.3, 1.0 } -- seconds after the XP comes in
local CHECK = 1 -- seconds between CineMode checks while waiting

local run -- this session's part: { stage, at, cineWasOn }

local function Saved() return CinematicDB and CinematicDB.xpRelogTest end
local function Say(text)
	local log = CinematicDB and CinematicDB.xpRelogTestLog
	if log then log[#log + 1] = ("%s %s"):format(date("%H:%M:%S"), text) end
end
local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Say(("  screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end
local function IsBlank(font)
	return type(font) == "string" and font:lower() == BLANK:lower()
end
local function FontName(font)
	if IsBlank(font) then return "blank (ours)" end
	return tostring(font)
end
local function CVar(name)
	local value = GetCVar and GetCVar(name)
	return value == nil and "-" or tostring(value)
end

-- Everything that decides the font, as a line.
local function State(label)
	local db = ns.db or {}
	Say(("%s: DAMAGE_TEXT_FONT %s; game's own %s; Core's blank %s; hideWorldText %s, combatTextStyle %s,"
		.. " styleGeneral %s, worldTextLive %s; damage numbers %s/%s, enableFloatingCombatText %s;"
		.. " level %s of %s, CineMode %s"):format(label, FontName(DAMAGE_TEXT_FONT), tostring(ns.gameDamageTextFont),
		tostring(ns.blankWorldFont ~= nil), tostring(db.hideWorldText), tostring(db.combatTextStyle),
		tostring(db.styleGeneral), tostring(db.worldTextLive), CVar("floatingCombatTextCombatDamage"),
		CVar("floatingCombatTextCombatDamage_v2"), CVar("enableFloatingCombatText"), tostring(UnitLevel("player")),
		tostring(GetMaxPlayerLevel and GetMaxPlayerLevel()), tostring(ns.IsCineModeOn and ns.IsCineModeOn())))
end

local function CineOff()
	if ns.IsCineModeOn and ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		Cinematic_ToggleCineMode()
		Say("  CineMode came on: turned off for the test")
	end
end

local waiter = CreateFrame("Frame")

local function Finish(done)
	local saved = Saved()
	waiter:UnregisterAllEvents()
	waiter:SetScript("OnUpdate", nil)
	if saved then
		-- (What the game drew before the test's login: its login noted the
		-- font Core set, not the test's.)
		ns.db.worldTextLive = saved.worldTextLive
		CinematicDB.xpRelogTest = nil
	end
	if run and run.cineWasOn and ns.IsCineModeOn and not ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		Cinematic_ToggleCineMode()
	end
	run = nil
	Say(done and "DONE" or "stopped")
	ns.TestPrompt(done and "XP relog test DONE. If the XP text changed, log out and in once more to put it back."
		.. " /reload, then say \"check log\"." or "XP relog test stopped. /reload, then say \"check log\".", 600)
end

-- Waits (no time limit) for the next XP gain, takes the shots, then next().
local function WaitForXp(step, prompt, next)
	ns.TestPrompt(prompt, 3600)
	local elapsed = 0
	waiter:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= CHECK then
			elapsed = 0
			CineOff()
		end
	end)
	waiter:RegisterEvent("PLAYER_XP_UPDATE")
	waiter:SetScript("OnEvent", function()
		waiter:UnregisterAllEvents()
		waiter:SetScript("OnUpdate", nil)
		Say(("  XP came in (step %d): %d now"):format(step, UnitXP("player") or -1))
		State(("  step %d at the kill"):format(step))
		for index, delay in ipairs(SHOT_TIMES) do
			C_Timer.After(delay, function()
				if not run then return end
				Shot(("step %d, %.1f s after the XP"):format(step, delay))
				if index == #SHOT_TIMES then ns.Guard(next) end
			end)
		end
	end)
end

local function AfterRelog()
	local saved = Saved()
	Say(("verdict INFO: XP text in step 1 shots drawn in %s; in step 3 shots in %s (set at this login)."
		.. " Shown in one and gone in the other = a relog reads the font again; the same in both = it keeps"
		.. " the one from the game's start"):format(FontName(saved.before), FontName(saved.flipTo)))
	Finish(true)
end

local function BeforeRelog()
	local saved = Saved()
	saved.stage = "relog"
	Say(("--- 2 of 3: relog. Next login draws in %s ---"):format(FontName(saved.flipTo)))
	ns.TestPrompt("XP relog test 2 of 3: log out to character select and log back in (not /reload)."
		.. " The test carries on by itself.", 3600)
end

-- After the test's login: the other font, set at every point Core sets its own.
local hook = CreateFrame("Frame")
hook:RegisterEvent("ADDON_LOADED")
hook:RegisterEvent("PLAYER_LOGIN")
hook:RegisterEvent("PLAYER_ENTERING_WORLD")
hook:SetScript("OnEvent", function(self, event, arg1, arg2)
	local saved = Saved()
	if not (saved and saved.stage == "relog") then
		if event == "PLAYER_ENTERING_WORLD" then self:UnregisterAllEvents() end
		return
	end
	if event ~= "PLAYER_ENTERING_WORLD" then
		DAMAGE_TEXT_FONT = saved.flipTo
		return
	end
	self:UnregisterAllEvents()
	DAMAGE_TEXT_FONT = saved.flipTo
	saved.stage = "after"
	run = { at = GetTime(), cineWasOn = saved.cineWasOn }
	Say(("logged in again: initial login %s, reloading UI %s%s"):format(tostring(arg1), tostring(arg2),
		arg2 and " (a /reload, not a relog: this still tells whether a /reload reads the font)" or ""))
	C_Timer.After(3, function()
		if not run then return end
		CineOff()
		State("after the relog")
		Say("--- 3 of 3: after the relog ---")
		WaitForXp(3, "XP relog test 3 of 3: kill one more enemy that gives XP. Just that.", AfterRelog)
	end)
end)

function ns.XpRelogTest()
	ns.debugNoCopyWindow = true
	if Saved() or run then
		Finish(false)
		return
	end
	if GetMaxPlayerLevel and UnitLevel("player") >= GetMaxPlayerLevel() then
		ns.Print("/cine debug xprelog: you're at the top level, so no XP text shows. Try a lower character.")
		return
	end
	CinematicDB.xpRelogTestLog = {}
	local before = DAMAGE_TEXT_FONT
	local db = ns.db or {}
	CinematicDB.xpRelogTest = {
		stage = "now", before = before,
		flipTo = IsBlank(before) and (ns.gameDamageTextFont or "Fonts\\FRIZQT__.TTF") or BLANK,
		worldTextLive = db.worldTextLive,
		cineWasOn = ns.IsCineModeOn and ns.IsCineModeOn() or false,
	}
	run = { at = GetTime(), cineWasOn = CinematicDB.xpRelogTest.cineWasOn }
	Say(("start %s, %s (game %s), dev %s"):format(date("%Y-%m-%d"), ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), ADDON_NAME))
	CineOff()
	State("before")
	Say("--- 1 of 3: XP text now ---")
	WaitForXp(1, "XP relog test 1 of 3: kill one enemy that gives XP. Just that.", BeforeRelog)
end
