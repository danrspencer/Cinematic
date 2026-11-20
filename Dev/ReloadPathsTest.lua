-- /cine debug reloadpaths: does each of our reloads reload, or does the game
-- block it? Forever blocks ReloadUI from addon code (2026-11-20), so there
-- the player's reloads go through a secure /reload button (QoL/Reload.lua).
-- One step a reload; the test waits for your click or key each time (no time
-- limit), then sees whether the UI came back reloaded:
--   1 timer      ReloadUI from a timer, no click: the old way (INFO; Forever
--                blocks it, retail reloads)
--   2 old popup  a popup with OnAccept = ReloadUI, as ours were (INFO)
--   3 button     the Reload button (Quality of life > General), on for the test
--   4 key        the Reload key (a free one bound for the test if none is)
--   5 language   the language popup's Reload
--   6 turn off   Turn off and reload (Cinematic is kept on for the test)
--   7 reset      Reset Cinematic > Reset Settings (nothing reset for the test)
--   8 ask        the "Reload now?" popup (/cine debug solo's)
-- 3-8: PASS when the UI reloads. Each step logs any ADDON_ACTION_BLOCKED and
-- the "Type /reload" fallback. Into CinematicDB.reloadPathsLog, with the
-- client, ActionButtonUseKeyDown and the key used. CineMode off for the
-- run, back after; the Reload button and the test key put back. Run again to
-- stop. Dev copy only.
local _, ns = ...

local WAIT = 4 -- seconds after a click with no reload: not reloaded
local TEST_KEYS = { "CTRL-SHIFT-F9", "CTRL-SHIFT-F10", "CTRL-SHIFT-F11", "CTRL-ALT-SHIFT-F9" }

local function State() return CinematicDB and CinematicDB.reloadPathsTest end

local function Say(text)
	local log = CinematicDB and CinematicDB.reloadPathsLog
	if log then log[#log + 1] = ("%s %s"):format(date("%H:%M:%S"), text) end
end
local function Prompt(text)
	ns.TestPrompt("Reload test: " .. text, 3600)
end
local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Say(("  screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end

-- The step running now (this load's): what it showed, so a click is told.
local live

local function Clicked(what)
	local state = State()
	if not (state and state.pending and live) then return end
	Say("  clicked: " .. what .. (InCombatLockdown() and " (in a fight)" or ""))
	if live.clicked then return end
	live.clicked = GetTime()
	state.pending.clicked = true
	local step = live
	-- (Still here a while later: the reload didn't happen.)
	C_Timer.After(WAIT, function()
		if live ~= step or not State() then return end
		state.pending = nil
		local reason = step.blocked and ("blocked: " .. step.blocked) or step.fallback and "the \"Type /reload\" message"
			or "nothing blocked, no message"
		if step.info then
			Say(("  result INFO: not reloaded (%s)"):format(reason))
		else
			state.fail = state.fail + 1
			Say(("  verdict FAIL: not reloaded (%s)"):format(reason))
		end
		Shot(step.id)
		if step.undo then pcall(step.undo) end
		live = nil
		state.pos = state.pos + 1
		C_Timer.After(1, ns.ReloadPathsNext)
	end)
end

local function HookOnce(frame, script, what)
	if frame and not frame.cineReloadTestHooked then
		frame.cineReloadTestHooked = true
		frame:HookScript(script, function() Clicked(what) end)
	end
end

-- Watches the cover (the popup's secure Reload) once a popup made it.
local function HookCover(what)
	local cover = ns.ReloadCover and ns.ReloadCover()
	if cover then HookOnce(cover, "PreClick", "the secure Reload over the popup") end
	return cover and cover:IsShown() and "covered" or "not covered (" .. tostring(what) .. ")"
end

local function PopupStep(id, title, which, show, button, patch)
	return { id = id, title = title, run = function(step)
		show()
		-- What the button does, watched (a plain click, or the cover's PreClick
		-- running it), or with patch a stand-in for it (nothing turned off or
		-- reset). Put back after; made again with the popup, it's new anyway.
		local info = StaticPopupDialogs[which]
		local key = button == 3 and "OnAlt" or "OnAccept"
		if info and not info.cineReloadTest then
			local real = info[key]
			info.cineReloadTest = true
			info[key] = function(...)
				Clicked(key .. " ran" .. (patch and " (the test's stand-in)" or ""))
				if patch then return patch(...) end
				if real then return real(...) end
			end
			step.undo = function()
				info[key], info.cineReloadTest = real, nil
			end
		end
		local dialog
		for i = 1, (_G.STATICPOPUP_NUMDIALOGS or 4) do
			local d = _G["StaticPopup" .. i]
			if d and d:IsShown() and d.which == which then dialog = d end
		end
		Say(("  popup %s %s, cover %s"):format(which, dialog and "up" or "NOT up", HookCover(which)))
		Prompt(("click %s on the window (step %d: %s)."):format(button == 3 and "Reset Settings" or "Reload",
			step.n, title))
		-- (Closed with no click: up again.)
		local ticker
		ticker = C_Timer.NewTicker(0.5, function()
			if live ~= step or step.clicked then return ticker:Cancel() end
			if dialog and not dialog:IsShown() then
				ticker:Cancel()
				Say("  window closed with no reload click: up again")
				step.clicked = nil
				C_Timer.After(0.5, function() if live == step then step.run(step) end end)
			end
		end)
	end }
end

local STEPS = {
	{ id = "timer", title = "ReloadUI from a timer (the old way)", info = true, run = function()
		Prompt("step 1: ReloadUI from a timer, no click. Just watch.")
		C_Timer.After(1, function()
			Clicked("(none: a timer)")
			ReloadUI()
		end)
	end },
	PopupStep("oldpopup", "a popup with OnAccept = ReloadUI (how ours were)", "CINEMATIC_RELOADTEST_OLD", function()
		StaticPopupDialogs.CINEMATIC_RELOADTEST_OLD = {
			text = "Reload test: the old popup (OnAccept = ReloadUI).", button1 = RELOADUI or "Reload",
			OnAccept = ReloadUI, timeout = 0, whileDead = true,
		}
		StaticPopup_Show("CINEMATIC_RELOADTEST_OLD")
	end, 1),
	{ id = "button", title = "the Reload button", run = function(step)
		ns.reloadTestShowButton = true -- (QoL/Reload.lua: up whatever its setting and page say)
		step.undo = function() ns.reloadTestShowButton = nil end
		local button = _G.CinematicReloadButton
		C_Timer.After(0.6, function()
			if live ~= step then return end
			HookOnce(button, ns.reloadBlocked and "PreClick" or "OnClick", "the Reload button")
			Say(("  button shown %s, secure %s, at %s"):format(tostring(button and button:IsShown()),
				tostring(button and button:IsProtected()), button and table.concat({ tostring(button:GetLeft()),
				tostring(button:GetTop()) }, ",") or "?"))
			Prompt("step 3: click the Reload button at the top of the screen.")
		end)
	end },
	{ id = "key", title = "the Reload key", run = function(step)
		local state = State()
		local key = GetBindingKey("CINEMATIC_RELOAD")
		if not key then
			for _, free in ipairs(TEST_KEYS) do
				if (GetBindingAction(free) or "") == "" then key = free break end
			end
			if key then
				SetBinding(key, "CINEMATIC_RELOAD")
				SaveBindings(GetCurrentBindingSet())
				state.testKey = key
				Say("  bound " .. key .. " for the test")
			end
		end
		if not key then
			Say("  verdict FAIL: no key bound and no free one to bind")
			Shot("key")
			state.fail = state.fail + 1
			live = nil
			state.pending, state.pos = nil, state.pos + 1
			return C_Timer.After(1, ns.ReloadPathsNext)
		end
		C_Timer.After(1, function() -- (the override is set within half a second)
			if live ~= step then return end
			HookOnce(_G.CinematicReloadKey, "PreClick", "the Reload key (secure)")
			Say(("  key %s: does %s (override %s)"):format(key, tostring(GetBindingAction(key)),
				tostring(GetBindingAction(key, true))))
			if not ns.reloadBlocked then
				-- (retail: the binding's own code, Cinematic_Reload)
				hooksecurefunc("Cinematic_Reload", function() Clicked("the Reload key (Cinematic_Reload)") end)
			end
			Prompt(("step 4: press %s (the Reload key)."):format(GetBindingText and GetBindingText(key) or key))
		end)
	end },
	PopupStep("language", "the language popup", "CINEMATIC_LANGUAGE_RELOAD",
		function() StaticPopup_Show("CINEMATIC_LANGUAGE_RELOAD") end, 1),
	PopupStep("turnoff", "Turn off and reload (kept on for the test)", "CINEMATIC_TURN_OFF",
		function() ns.TurnOffCompletely() end, 1, function() ns.Reload() end),
	PopupStep("reset", "Reset Cinematic > Reset Settings (nothing reset)", "CINEMATIC_ADDON_RESET",
		function() StaticPopup_Show("CINEMATIC_ADDON_RESET") end, 3, function() ns.Reload() end),
	PopupStep("ask", "the Reload now? popup (solo's)", "CINEMATIC_RELOAD_NOW",
		function() ns.ReloadOrAsk("Reload test: click Reload.") end, 1),
}

local function CineOff()
	if ns.IsCineModeOn and ns.IsCineModeOn() and Cinematic_ToggleCineMode then Cinematic_ToggleCineMode() end
end

local function Finish(text)
	local state = State()
	if not state then return end
	CinematicDB.reloadPathsTest = nil
	live = nil
	ns.reloadTestShowButton = nil
	if state.testKey and not InCombatLockdown() then
		SetBinding(state.testKey)
		SaveBindings(GetCurrentBindingSet())
		Say("  test key " .. state.testKey .. " unbound")
	end
	if state.cineWasOn and ns.IsCineModeOn and not ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		Cinematic_ToggleCineMode()
	end
	local line = ("%s: %d pass, %d fail"):format(text, state.pass, state.fail)
	Say(line)
	ns.TestPrompt(("Reload test %s. Say \"check log\"."):format(line), 15)
end

function ns.ReloadPathsNext()
	local state = State()
	if not state then return end
	local step = STEPS[state.pos]
	if not step then return Finish("DONE") end
	if InCombatLockdown() then
		Prompt("end the fight first; the test waits.")
		return C_Timer.After(1, ns.ReloadPathsNext)
	end
	CineOff()
	live = { id = step.id, n = state.pos, info = step.info, run = step.run }
	state.pending = { pos = state.pos, at = time() }
	Say(("step %d %s: %s"):format(state.pos, step.id, step.title))
	step.run(live)
end

-- (Blocked, or our "Type /reload" line: put on the step running.)
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, addon, fn)
	local state = State()
	if not state then return end
	if event == "PLAYER_ENTERING_WORLD" then
		-- (After each reload the test made: what it was, then the next step.
		-- A loading screen with no reload: nothing.)
		if live or not (addon or fn) then return end
		local pending = state.pending
		if pending and state.loads ~= nil then
			local step = STEPS[pending.pos]
			if step and step.info then
				Say("  result INFO: reloaded" .. (pending.clicked and "" or " (no click seen)"))
			elseif step then
				state.pass = state.pass + 1
				Say("  verdict PASS: reloaded" .. (pending.clicked and "" or " (no click seen)"))
			end
			state.pending = nil
			state.pos = pending.pos + 1
		end
		state.loads = (state.loads or 0) + 1
		C_Timer.After(3, ns.ReloadPathsNext)
		return
	end
	local text = ("%s %s %s"):format(event, tostring(addon), tostring(fn))
	if live then live.blocked = text end
	Say("  " .. text)
end)
hooksecurefunc(ns, "ReloadFallback", function()
	if live then live.fallback = true end
	Say("  fallback: \"Type /reload to finish.\" said")
end)

function ns.ReloadPathsTest()
	if State() then return Finish("stopped") end
	if not CinematicDB then return end
	if InCombatLockdown() then return ns.Print("/cine debug reloadpaths: not in a fight.") end
	CinematicDB.reloadPathsLog = {}
	CinematicDB.reloadPathsTest = { pos = 1, pass = 0, fail = 0, loads = 0,
		cineWasOn = ns.IsCineModeOn and ns.IsCineModeOn() or false }
	local build, _, _, toc = GetBuildInfo()
	Say(("start: client %s (build %s, toc %s), reloadBlocked %s, ActionButtonUseKeyDown %s, Reload key %s, " ..
		"Reload button %s, CineMode %s"):format(ns.isRetail and "retail" or ns.isClassicEra and "Classic Era" or "Forever",
		tostring(build), tostring(toc), tostring(ns.reloadBlocked), tostring(GetCVarBool("ActionButtonUseKeyDown")),
		tostring(GetBindingKey("CINEMATIC_RELOAD")), tostring(ns.db and ns.db.reloadButton),
		tostring(CinematicDB.reloadPathsTest.cineWasOn)))
	Say("  " .. #STEPS .. " steps, each a reload; the dev error window's BLOCKED lines also go to CinematicDB.log")
	ns.ReloadPathsNext()
end
