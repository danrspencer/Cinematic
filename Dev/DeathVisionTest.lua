-- /cine debug deathtest: one run checking the Death Vision page (2026-11-19,
-- a player couldn't find the corpse-run vignette's settings), about 1.5 minutes,
-- alive and out of fights. CineMode off for the run, back after.
--   1 wiring: the page is in the Visions hub (World) with its switch, and a
--     right-click on its icon turns it off and on again.
--   2 page:   the page opens (screenshot); you close the settings.
--   3 test:   its Test as it starts (wash and edges creeping in), at full
--             (screenshot) and gone after.
--   4 sliders: Strength 30% and Edges reach in 50% (screenshot), then Stop
--             ends it early.
--   5 off:    with the page off, Test shows nothing.
--   6 death:  a pretend death brings it with the death camera (screenshot);
--             the page off mid-death clears it.
-- Your settings are put back after (and at the next login after a /reload
-- mid-run). A verdict per check, into CinematicDB.deathTestLog. Dev copy only.
local ADDON_NAME, ns = ...

local KEYS = { "deathScreen", "deathScreenStrength", "deathVignetteTime", "deathVignetteSize", "deathCorpseRun" }
local CREEP = 4      -- seconds: the edges' creep for the run (yours put back after)
local run

local function Log(text)
	local log = CinematicDB and CinematicDB.deathTestLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.startAt or 0, text) end
end
local function Verdict(name, ok, detail)
	Log(("%s %s: %s"):format(ok and "PASS" or "FAIL", name, detail))
	ns.Print(("%s %s"):format(ok and "|cff40ff40PASS|r" or "|cffff4040FAIL|r", name))
end
local function Shot(name)
	local ok = pcall(function() Screenshot() end)
	Log(("SHOT %s (%s, %s)"):format(name, date("%H:%M:%S"), ok and "taken" or "failed"))
end
local function Num(value) return type(value) == "number" and ("%.2f"):format(value) or tostring(value) end
local function State(label)
	local s = ns.GetCorpseDebug()
	Log(("%s: shown %s, wash %s, creep %s, edgeSize %s, testing %s"):format(label, tostring(s.shown), Num(s.wash),
		Num(s.creep), Num(s.edgeSize), tostring(ns.DeathVisionTesting())))
	return s
end

local function PutBack()
	local db, kept = ns.GetDB(), CinematicDB and CinematicDB.deathTestKept
	if not (db and kept) then return end
	for key, value in pairs(kept) do
		if value == "__nil" then db[key] = nil else db[key] = value end
	end
	CinematicDB.deathTestKept = nil
	if ns.RefreshOptions then pcall(ns.RefreshOptions) end
end
local loginWatch = CreateFrame("Frame")
loginWatch:RegisterEvent("PLAYER_LOGIN")
loginWatch:SetScript("OnEvent", function()
	if CinematicDB and CinematicDB.deathTestKept and not run then
		C_Timer.After(1, function() ns.Guard(PutBack) end)
	end
end)

-- The steps, one after another: each gets next() to call when it's done.
local function Wiring(next)
	ns.TestPrompt("Death Vision test, step 1 of 6: checking the menu. Stay out of fights.", 3)
	if ns.MakeLazyPages then ns.MakeLazyPages("death test") end
	local found
	for _, page in ipairs(ns.HubPageStates("Visions") or {}) do
		if page.name == "Death Vision" then found = page end
	end
	Verdict("1a in the Visions hub", found ~= nil and found.section == "World" and found.hasSwitch,
		found and ("section %s, switch %s, on %s, intro %q"):format(tostring(found.section),
		tostring(found.hasSwitch), tostring(found.on), tostring(found.intro)) or "not listed")
	local db = ns.GetDB()
	local was = db.deathScreen
	ns.FlipTabSwitch("Death Vision")
	local off = db.deathScreen
	ns.FlipTabSwitch("Death Vision")
	Verdict("1b right-click turns it off and on", was == true and off == false and db.deathScreen == true,
		("was %s, after one flip %s, after two %s"):format(tostring(was), tostring(off), tostring(db.deathScreen)))
	db.deathScreen = true
	C_Timer.After(1, next)
end

local function Page(next)
	ns.OpenOptions("Death Vision")
	ns.TestPrompt("Step 2 of 6: the Death Vision page. Close the settings (Esc) once it's up.", 6)
	C_Timer.After(2.5, function()
		local panel = _G.SettingsPanel
		Verdict("2a page opens", panel ~= nil and panel:IsShown(), "settings shown " ..
			tostring(panel and panel:IsShown()))
		Shot("2 page")
		local waited = 0
		local ticker
		ticker = C_Timer.NewTicker(0.5, function()
			waited = waited + 0.5
			if not (panel and panel:IsShown()) or waited >= 30 then
				ticker:Cancel()
				Verdict("2b settings closed", not (panel and panel:IsShown()), ("after %.1f sec"):format(waited))
				C_Timer.After(1.5, next)
			end
		end)
	end)
end

local function TestRun(next)
	local db = ns.GetDB()
	db.deathScreen, db.deathScreenStrength, db.deathVignetteTime, db.deathVignetteSize = true, 1, CREEP, 0.35
	ns.TestPrompt("Step 3 of 6: the death screen at full. Just watch.", 3)
	ns.TestDeathVision()
	local early
	C_Timer.After(0.6, function() early = State("3 at 0.6 sec") end)
	C_Timer.After(CREEP + 0.6, function()
		local s = State("3 at full")
		Shot("3 full")
		Verdict("3a creeps in", early ~= nil and early.shown and early.creep < 0.4,
			("at 0.6 sec shown %s, creep %s"):format(tostring(early and early.shown), Num(early and early.creep)))
		Verdict("3b at full", s.shown and s.wash > 0.95 and s.creep > 0.95 and math.abs(s.edgeSize - 0.35) < 0.03,
			("wash %s, creep %s, edgeSize %s (want 0.35)"):format(Num(s.wash), Num(s.creep), Num(s.edgeSize)))
	end)
	C_Timer.After(CREEP + 5 + 2, function()
		local s = State("3 after")
		Verdict("3c gone after", not s.shown and not ns.DeathVisionTesting(),
			("shown %s, testing %s, creep %s"):format(tostring(s.shown), tostring(ns.DeathVisionTesting()), Num(s.creep)))
		next()
	end)
end

local function Sliders(next)
	local db = ns.GetDB()
	db.deathScreenStrength, db.deathVignetteSize = 0.3, 0.5
	ns.TestPrompt("Step 4 of 6: lighter, with wider edges. Then it's stopped early.", 3)
	ns.TestDeathVision()
	C_Timer.After(CREEP + 0.6, function()
		local s = State("4 at full")
		Shot("4 lighter, wider")
		Verdict("4a edges reach 50%", s.shown and math.abs(s.edgeSize - 0.5) < 0.03,
			("edgeSize %s (want 0.50), wash %s"):format(Num(s.edgeSize), Num(s.wash)))
		ns.TestDeathVision() -- (Stop)
		Log("4: Stop")
	end)
	C_Timer.After(CREEP + 3, function()
		local s = State("4 after Stop")
		Verdict("4b Stop ends it", not s.shown and not ns.DeathVisionTesting(),
			("shown %s, testing %s"):format(tostring(s.shown), tostring(ns.DeathVisionTesting())))
		next()
	end)
end

local function Off(next)
	local db = ns.GetDB()
	db.deathScreen, db.deathScreenStrength, db.deathVignetteSize = false, 1, 0.35
	ns.TestPrompt("Step 5 of 6: with the page off, nothing should show.", 3)
	ns.TestDeathVision()
	C_Timer.After(2.5, function()
		local s = State("5 page off")
		Shot("5 page off")
		Verdict("5 page off shows nothing", not s.shown, ("shown %s, wash %s"):format(tostring(s.shown), Num(s.wash)))
		if ns.DeathVisionTesting() then ns.TestDeathVision() end
		next()
	end)
end

-- 6 death: a pretend death (as /cine deathtest), so the screen comes the
-- way it does when you die (with the death camera), then the page off
-- mid-death clears it. Skipped when the death camera's off here.
local function Death(next)
	local db = ns.GetDB()
	db.deathScreen, db.deathScreenStrength, db.deathVignetteSize = true, 1, 0.35
	local camOn = db.enabled and db.deathOrbit and ns.TriggerAnyRow and ns.TriggerAnyRow("Death")
	if not camOn then
		Log(("6 skipped: death camera off (enabled %s, deathOrbit %s, Death row %s)"):format(tostring(db.enabled),
			tostring(db.deathOrbit), tostring(ns.TriggerAnyRow and ns.TriggerAnyRow("Death"))))
		return next()
	end
	ns.TestPrompt("Step 6 of 6: a pretend death. The camera circles you. Stand still.", 4)
	ns.deathTestUntil, ns.deathTestLoud = GetTime() + 12, nil
	C_Timer.After(CREEP + 1, function()
		local s = State("6 dead")
		Shot("6 pretend death")
		Verdict("6a shows when you die", s.shown and s.creep > 0.9 and ns.DeathCinematicWanted(),
			("death camera wanted %s, shown %s, creep %s"):format(tostring(ns.DeathCinematicWanted()),
			tostring(s.shown), Num(s.creep)))
		db.deathScreen = false
		Log("6: page off")
	end)
	C_Timer.After(CREEP + 3.5, function()
		local s = State("6 page off while dead")
		Verdict("6b page off clears it", not s.shown, ("shown %s, wash %s"):format(tostring(s.shown), Num(s.wash)))
		ns.deathTestUntil = 0
		C_Timer.After(2, next)
	end)
end

local function Done()
	ns.deathTestUntil = 0
	PutBack()
	if run.cineWasOn and ns.IsCineModeOn and not ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		Cinematic_ToggleCineMode()
	end
	Log("done")
	run = nil
	ns.TestPrompt("Death Vision test done. /reload, then say \"check log\".", 12)
end

function ns.DeathVisionTest()
	if run then return ns.Print("the death test is already running") end
	if InCombatLockdown() then return ns.Print("not in a fight") end
	if not (ns.TestDeathVision and ns.GetCorpseDebug and ns.HubPageStates) then
		return ns.Print("Death Vision isn't loaded")
	end
	local db = ns.GetDB()
	run = { startAt = GetTime() }
	CinematicDB.deathTestLog = {}
	local kept = {}
	for _, key in ipairs(KEYS) do kept[key] = db[key] == nil and "__nil" or db[key] end
	CinematicDB.deathTestKept = kept
	run.cineWasOn = ns.IsCineModeOn and ns.IsCineModeOn() or false
	if run.cineWasOn and Cinematic_ToggleCineMode then Cinematic_ToggleCineMode() end
	local yours = {}
	for _, key in ipairs(KEYS) do yours[#yours + 1] = key .. "=" .. tostring(db[key]) end
	local okVersion, version = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version")
	Log(("start %s, client %s, version %s; CineMode was %s; Death row on %s, death camera now %s, dead %s, ghost %s")
		:format(date("%Y-%m-%d %H:%M:%S"), tostring(ns.CLIENT), okVersion and tostring(version) or "?", tostring(run.cineWasOn),
		tostring(ns.TriggerAnyRow and ns.TriggerAnyRow("Death")), tostring(ns.DeathCinematicWanted and
		ns.DeathCinematicWanted()), tostring(ns.Flag(UnitIsDead("player"))), tostring(ns.Flag(UnitIsGhost("player")))))
	Log("yours: " .. table.concat(yours, ", "))
	local steps, at = { Wiring, Page, TestRun, Sliders, Off, Death, Done }, 0
	local function Next()
		at = at + 1
		local step = steps[at]
		if step and run then ns.Guard(function() step(Next) end) end
	end
	C_Timer.After(0.5, Next)
end
