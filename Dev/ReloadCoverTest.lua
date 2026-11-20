-- /cine debug reloadcover: is the secure Reload laid over each popup that
-- reloads, on its button, with no error? (Forever: QoL/Reload.lua's cover.
-- It was anchored to the popup's button, which Forever refuses: "Cannot
-- anchor protected frames to regions", 2026-11-20.) Runs itself, no clicks:
-- our settings open (as when you press Reset addon), then each popup is shown,
-- checked a second later (after it settles: the Reset one widens), shot, and
-- closed with nothing run. Per popup PASS when the cover is up on that popup,
-- within 1 px of its reload button, and hides with it; FAIL on any new
-- Reload.lua error in the log. Into CinematicDB.reloadCoverLog. CineMode off
-- for the run, back after. Run again to stop. Dev copy only.
local _, ns = ...

local POPUPS = {
	{ which = "CINEMATIC_ADDON_RESET", show = function() ns.ShowResetPopup() end },
	{ which = "CINEMATIC_ADDON_RESET_ALL" },
	{ which = "CINEMATIC_LANGUAGE_RELOAD" },
	{ which = "CINEMATIC_RELOAD_NOW", show = function() ns.ReloadOrAsk("Reload cover test: nothing is clicked.") end },
}

local run -- (this run's state)

local function Say(text)
	local log = CinematicDB and CinematicDB.reloadCoverLog
	if log then log[#log + 1] = ("%s %s"):format(date("%H:%M:%S"), text) end
end
local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Say(("  screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end

-- Screen rect in UIParent's units.
local function Rect(frame)
	local ok, l, b, w, h, s = pcall(function()
		return frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight(),
			frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	end)
	if not (ok and l and b and w and h) then return nil end
	return l * s, b * s, w * s, h * s
end
local function RectText(l, b, w, h)
	if not l then return "unreadable" end
	return ("%.1f,%.1f %.1fx%.1f"):format(l, b, w, h)
end

local function FindPopup(which)
	if StaticPopup_FindVisible then return StaticPopup_FindVisible(which) end
	for i = 1, (_G.STATICPOPUP_NUMDIALOGS or 4) do
		local dialog = _G["StaticPopup" .. i]
		if dialog and dialog:IsShown() and dialog.which == which then return dialog end
	end
end
local function PopupButton(dialog, index)
	return dialog["button" .. index] or (dialog.GetButton and dialog:GetButton(index))
		or (dialog.ButtonContainer and dialog.ButtonContainer["Button" .. index])
end

-- New log lines since the run started that name Reload.lua or the cover.
local function NewErrors()
	local log, found = ns.db and ns.db.log, {}
	if not log then return found end
	for i = (run.logFrom or #log) + 1, #log do
		local line = log[i]
		if type(line) == "string" and (line:find("Reload%.lua") or line:find("CinematicReloadCover")) then
			found[#found + 1] = line:sub(1, 300)
		end
	end
	run.logFrom = #log
	return found
end

local function Finish(text)
	if not run then return end
	local done = run
	run = nil
	CinematicDB.reloadCoverTest = nil
	if done.cineWasOn and ns.IsCineModeOn and not ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		Cinematic_ToggleCineMode()
	end
	local line = ("%s: %d pass, %d fail"):format(text, done.pass, done.fail)
	Say(line)
	ns.TestPrompt(("Reload cover test %s. Say \"check log\"."):format(line), 15)
end

local Step
Step = function()
	if not run then return end
	if InCombatLockdown() then
		ns.TestPrompt("Reload cover test: end the fight first; the test waits.", 3600)
		return C_Timer.After(1, Step)
	end
	local entry = POPUPS[run.pos]
	if not entry then return Finish("DONE") end
	-- (Shown first: some are made only as they're shown, the "Reload now?" one.)
	ns.TestPrompt(("Reload cover test: popup %d of %d (%s). Nothing to click."):format(run.pos, #POPUPS,
		entry.which), 3600)
	if entry.show then entry.show() elseif StaticPopupDialogs[entry.which] then StaticPopup_Show(entry.which) end
	local info = StaticPopupDialogs[entry.which]
	if not info then
		run.fail = run.fail + 1
		Say(("popup %d %s: not made (verdict FAIL)"):format(run.pos, entry.which))
		run.pos = run.pos + 1
		return C_Timer.After(0.2, Step)
	end
	Say(("popup %d %s (button %s reloads)"):format(run.pos, entry.which, tostring(info.cineReload)))
	C_Timer.After(1, function()
		if not run then return end
		local problems = {}
		local dialog = FindPopup(entry.which)
		local cover = ns.ReloadCover and ns.ReloadCover()
		local target = dialog and info.cineReload and PopupButton(dialog, info.cineReload)
		local tl, tb, tw, th, cl, cb, cw, ch
		if target then tl, tb, tw, th = Rect(target) end
		if cover then cl, cb, cw, ch = Rect(cover) end
		Say(("  popup %s, button %s at %s"):format(dialog and "up" or "NOT up", target and "found" or "NOT found",
			RectText(tl, tb, tw, th)))
		Say(("  cover %s, shown %s, protected %s, for %s, at %s, strata %s level %s (popup level %s)"):format(
			cover and "made" or "NOT made", tostring(cover and cover:IsShown()),
			tostring(cover and cover:IsProtected()), tostring(cover and cover.which), RectText(cl, cb, cw, ch),
			tostring(cover and cover:GetFrameStrata()), tostring(cover and cover:GetFrameLevel()),
			tostring(dialog and dialog:GetFrameLevel())))
		if not dialog then problems[#problems + 1] = "popup not up" end
		if not (cover and cover:IsShown()) then problems[#problems + 1] = "no cover shown" end
		if cover and cover.which ~= entry.which then problems[#problems + 1] = "cover on another popup" end
		if not (tl and cl) then
			problems[#problems + 1] = "places unreadable"
		elseif math.abs(tl - cl) > 1 or math.abs(tb - cb) > 1 or math.abs(tw - cw) > 1 or math.abs(th - ch) > 1 then
			problems[#problems + 1] = "cover not on the button"
		end
		Shot(entry.which)
		-- Closed with nothing run (Hide, not a button): the cover should go too.
		-- (Half a second on: the shot is taken as the frame ends, so a popup
		-- closed now wouldn't be in it.)
		C_Timer.After(0.5, function()
			if dialog then dialog:Hide() end
		end)
		C_Timer.After(1.1, function()
			if not run then return end
			if cover and cover:IsShown() then problems[#problems + 1] = "cover still up after the popup closed" end
			for _, line in ipairs(NewErrors()) do
				problems[#problems + 1] = "error: " .. line
			end
			if #problems == 0 then
				run.pass = run.pass + 1
				Say("  verdict PASS")
			else
				run.fail = run.fail + 1
				Say("  verdict FAIL: " .. table.concat(problems, "; "))
			end
			run.pos = run.pos + 1
			C_Timer.After(0.4, Step)
		end)
	end)
end

function ns.ReloadCoverTest()
	if run then return Finish("stopped") end
	if not CinematicDB then return end
	if InCombatLockdown() then return ns.Print("/cine debug reloadcover: not in a fight.") end
	local cineWasOn = ns.IsCineModeOn and ns.IsCineModeOn() or false
	if cineWasOn and Cinematic_ToggleCineMode then Cinematic_ToggleCineMode() end
	CinematicDB.reloadCoverLog = {}
	CinematicDB.reloadCoverTest = true
	run = { pos = 1, pass = 0, fail = 0, cineWasOn = cineWasOn, logFrom = ns.db and ns.db.log and #ns.db.log }
	local build, _, _, toc = GetBuildInfo()
	Say(("start: client %s (build %s, toc %s), reloadBlocked %s, UI scale %.3f, CineMode was %s"):format(
		ns.isRetail and "retail" or ns.isClassicEra and "Classic Era" or "Forever", tostring(build), tostring(toc),
		tostring(ns.reloadBlocked), UIParent:GetEffectiveScale(), tostring(cineWasOn)))
	if not ns.reloadBlocked then
		Say("  this client reloads from addon code: no cover is made, nothing to check")
		return Finish("DONE (nothing to check here)")
	end
	-- (As when you press Reset addon: our settings open under the popups.)
	if ns.OpenOptions then pcall(ns.OpenOptions) end
	C_Timer.After(1, Step)
end
