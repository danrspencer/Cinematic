-- /cine debug listfold: proves our settings' left list is never made again in
-- a fight (Options.lua Fold). Made again then, every line's gamepad cursor call
-- is blocked: a yellow "Interface action failed" per line (Forever, 2041 in one
-- fight, 2026-11-20). It sets itself up (CineMode off, settings closed); you
-- only start a fight and end it when the box says so:
--   1 calm      pages in three hubs picked out of a fight: the list folds
--               (made again at least once) and nothing blocked (PASS/FAIL)
--   2 fight     waits for you to start a fight (no time limit)
--   3 control   the list made again once by hand in the fight: how many lines
--               it blocks, to show the trigger is live (INFO)
--   4 picks     the same pages picked 6 times in the fight: list never made
--               again, nothing blocked, the fold waiting for the end (PASS/FAIL)
--   5 after     waits for the fight to end: the waiting fold done, nothing
--               blocked (PASS/FAIL)
-- Into CinematicDB.listFoldTestLog, a verdict a step, a screenshot a step.
-- Run again to stop it. Dev copy only.
local _, ns = ...

local HOOK = "blocked (no event)"
-- (Interface, Visions and Style hubs in turn, each opening its own group and
-- folding the others; two pages a hub, so each pick is a new page there: a
-- page already shown in its hub isn't picked again.)
local PAGES = { "Chat", "Card Vision", "Style General", "Nameplates", "Death Vision", "Style Themes" }

local run
local made = 0 -- (times the game's list was made again while a run is on)

local function Say(text)
	local log = CinematicDB and CinematicDB.listFoldTestLog
	if log then log[#log + 1] = ("%s %.1f %s"):format(date("%H:%M:%S"), run and GetTime() - run.at or 0, text) end
end
local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Say(("  screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end
local function Blocked() return (ns.DevErrorCount(HOOK)) end
local function List()
	local panel = _G.SettingsPanel
	return panel and panel.GetCategoryList and panel:GetCategoryList()
end
local function Verdict(ok, text)
	if ok then run.pass = run.pass + 1 else run.fail = run.fail + 1 end
	Say(("  verdict %s: %s"):format(ok and "PASS" or "FAIL", text))
end
local picked = 0
local function Pick(times)
	for _ = 1, times do
		picked = picked + 1
		local name = PAGES[(picked - 1) % #PAGES + 1]
		local ok, hub = pcall(ns.ShowHubPage, name)
		if not ok or not hub then Say(("  %s: not picked (%s)"):format(name, tostring(hub))) end
	end
end
local function StackIfAny(before)
	if Blocked() > before then
		local _, stack = ns.DevErrorCount(HOOK)
		if stack then Say("  newest blocked stack:\n" .. stack) end
	end
end

local function Finish(done)
	if not run then return end
	local this = run
	run = nil
	if this.watch then this.watch:SetScript("OnUpdate", nil) end
	if this.cineWasOn and ns.IsCineModeOn and not ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		pcall(Cinematic_ToggleCineMode)
	end
	local line = ("%s: %d pass, %d fail, %d info"):format(done and "DONE" or "stopped", this.pass, this.fail, this.info)
	Say(line)
	ns.TestPrompt(("Left list test %s. /reload, then say \"check log\"."):format(line), 12)
end

-- Waits (no time limit) till test() is true, the box saying what to do.
local function WaitFor(prompt, test, after)
	ns.TestPrompt(prompt, 3600)
	run.watch = run.watch or CreateFrame("Frame")
	local wait = 0
	run.watch:SetScript("OnUpdate", function(self, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.2
		if not run then return self:SetScript("OnUpdate", nil) end
		if test() then
			self:SetScript("OnUpdate", nil)
			local ok, err = pcall(after)
			if not ok then
				Say("error: " .. tostring(err))
				Finish(false)
			end
		end
	end)
end

local AfterFight, InFight

local function Calm()
	Say("--- 1 of 5: pages in three hubs picked out of a fight ---")
	ns.TestPrompt("Left list test: 1 of 5, picking pages. Just watch.", 3)
	local made0, blocked0 = made, Blocked()
	Pick(3)
	C_Timer.After(1, function()
		if not run then return end
		Shot("step 1")
		StackIfAny(blocked0)
		Verdict(made > made0 and Blocked() == blocked0, ("list made again %d time(s) (1+ wanted: it folds), blocked +%d (0 wanted)")
			:format(made - made0, Blocked() - blocked0))
		Say("--- 2 of 5: waiting for a fight ---")
		WaitFor("Left list test: 2 of 5. Start a fight: attack any enemy or a training dummy. The test waits.",
			InCombatLockdown, InFight)
	end)
end

function InFight()
	Say("--- 3 of 5: control, the list made again by hand in the fight ---")
	ns.TestPrompt("Left list test: 3 of 5. Keep fighting, the test is working.", 3600)
	local list = List()
	local blocked0 = Blocked()
	if list and list.CreateCategories then pcall(list.CreateCategories, list) end
	C_Timer.After(0.5, function()
		if not run then return end
		local new = Blocked() - blocked0
		run.info = run.info + 1
		Say(("  verdict INFO: made again by hand in a fight blocked %d time(s) (gamepad UI %s, GamePadEnable %s)")
			:format(new, _G.SmartNavigation and "there" or "not there", tostring(GetCVar and GetCVar("GamePadEnable"))))
		StackIfAny(blocked0)
		Shot("step 3")
		Say("--- 4 of 5: the pages picked 6 times in the fight ---")
		local made0, blocked1 = made, Blocked()
		Pick(6)
		C_Timer.After(1, function()
			if not run then return end
			Shot("step 4")
			StackIfAny(blocked1)
			local waiting = ns.LeftListFoldWaiting and ns.LeftListFoldWaiting()
			Say(("  still in a fight: %s"):format(tostring(InCombatLockdown())))
			Verdict(made == made0 and Blocked() == blocked1 and waiting ~= nil,
				("list made again %d time(s) (0 wanted), blocked +%d (0 wanted), fold waiting for the end: %s")
					:format(made - made0, Blocked() - blocked1, waiting and "yes" or "NO"))
			Say("--- 5 of 5: waiting for the fight to end ---")
			run.made5, run.blocked5 = made, Blocked()
			WaitFor("Left list test: 5 of 5. End the fight now (win it or run off). The test waits.",
				function() return not InCombatLockdown() end, AfterFight)
		end)
	end)
end

function AfterFight()
	ns.TestPrompt("Left list test: 5 of 5, fight over. Just watch.", 3)
	C_Timer.After(1, function()
		if not run then return end
		Shot("step 5")
		StackIfAny(run.blocked5)
		local waiting = ns.LeftListFoldWaiting and ns.LeftListFoldWaiting()
		Verdict(waiting == nil and Blocked() == run.blocked5,
			("fold waiting: %s (none wanted), list made again %d time(s) after, blocked +%d (0 wanted)")
				:format(waiting and "still" or "none", made - run.made5, Blocked() - run.blocked5))
		Finish(true)
	end)
end

function ns.ListFoldTest()
	if run then return Finish(false) end
	if not (CinematicDB and ns.DevErrorCount and ns.ShowHubPage and ns.LeftListFoldWaiting) then
		ns.Print("/cine debug listfold: the dev error box or the settings pages aren't loaded.")
		return
	end
	if InCombatLockdown() then
		ns.Print("/cine debug listfold: start it out of a fight.")
		return
	end
	local list = List()
	if not (list and list.CreateCategories) then
		ns.Print("/cine debug listfold: this client's settings have no left list to fold.")
		return
	end
	if not list.cineFoldTestHooked then
		list.cineFoldTestHooked = true
		hooksecurefunc(list, "CreateCategories", function() if run then made = made + 1 end end)
	end
	CinematicDB.listFoldTestLog = {}
	run = { at = GetTime(), pass = 0, fail = 0, info = 0 }
	run.cineWasOn = ns.IsCineModeOn and ns.IsCineModeOn() or false
	if run.cineWasOn and Cinematic_ToggleCineMode then pcall(Cinematic_ToggleCineMode) end
	local panel = _G.SettingsPanel
	if panel and panel:IsShown() and HideUIPanel then pcall(HideUIPanel, panel) end
	Say(("start: %s (game %s), CineMode was %s, box has %d blocked entries"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), run.cineWasOn and "on" or "off", Blocked()))
	C_Timer.After(0.5, Calm)
end
