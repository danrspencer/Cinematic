-- /cine debug fadedemo: one run checking the welcome window's Fading UI demo
-- (ShowMe.lua's fadeUI, first in the See it first row). It opens the welcome
-- window and clicks the row's Fading UI button itself, twice:
--   1. level: as the demo picks it now (with a level picked whose frames are
--      looked after, that level's own CineMode fade: ns.fadeDemo);
--   2. whole: the whole UI's fade, as before a level's picked (the demo told
--      no frames are looked after, just as it starts; nothing else changed).
-- Every 0.25 s it logs ("fadedemo") the demo's state, UIParent's alpha, the
-- window's (own, ignoring its parent's, on screen, taking the mouse) and a
-- few frames' alpha on screen, with a screenshot in the hold. Its verdicts:
-- the UI went (frames under 0.1; the whole UI's: every one), each frame that
-- went came back (over 0.9), the window stayed at about 0.3, and everything
-- put back after (UIParent's alpha, the window's alpha, its parent's alpha
-- and its mouse). CineMode is switched off while it runs and back after
-- (else the bars fade again after the demo, as CineMode has them); no
-- settings changed. The mouse is left where it is: on the window, over the
-- bars, it brought them up for the whole demo (fixed, Frames.lua).
-- Typed again while running: stops. Dev copy only (CinematicDev.toc).
local _, ns = ...

local RUNS = { "level", "whole" }
local SAMPLE = 0.25
local SHOT_AT = 3.5   -- seconds into a run: the hold
local AFTER = 3       -- seconds watched after the demo ends
local WATCH = { "PlayerFrame", "Minimap", "ChatFrame1", "ActionButton1", "MainMenuBar", "MainActionBar" }

local run
local ticker
local function Log(text) ns.Log("fadedemo", text) end
local function Plain(value) return not (issecretvalue and issecretvalue(value)) end
local function Num(value)
	if type(value) ~= "number" then return tostring(value) end
	return Plain(value) and ("%.2f"):format(value) or "secret"
end
local function Effective(frame)
	local alpha = frame and frame.GetEffectiveAlpha and frame:GetEffectiveAlpha()
	return type(alpha) == "number" and Plain(alpha) and alpha or nil
end

-- The row's Fading UI button, a few levels down in the window.
local function FindButton(frame, depth)
	if frame.demo and frame.demo.key == "fadeUI" then return frame end
	if depth > 6 then return nil end
	for _, child in ipairs({ frame:GetChildren() }) do
		local found = FindButton(child, depth + 1)
		if found then return found end
	end
end

-- The frames watched that are on screen at the start (shown, alpha > 0.5).
local function Watched()
	local list = {}
	for _, name in ipairs(WATCH) do
		local frame = _G[name]
		if frame and frame.IsVisible and ns.Flag(frame:IsVisible()) and (Effective(frame) or 0) > 0.5 then
			list[#list + 1] = name
		end
	end
	return list
end

local function Sample(part, t)
	local window = _G.CinematicWelcome
	local alphas = {}
	for _, name in ipairs(part.frames) do
		local alpha = Effective(_G[name])
		alphas[#alphas + 1] = name .. " " .. Num(alpha)
		if alpha then
			if ns.ShowMeRunning("fadeUI") then part.low[name] = math.min(part.low[name] or 1, alpha) end
			part.last[name] = alpha
		end
	end
	local windowAlpha = Effective(window)
	Log(("%s +%.2f: running %s, ns.fadeDemo %s, CineMode %s, UIParent %s, window own %s on screen %s ignores " ..
		"parent %s mouse %s; %s"):format(part.name, t, tostring(ns.ShowMeRunning("fadeUI")), tostring(ns.fadeDemo),
		tostring(ns.lastCinematic), Num(UIParent:GetAlpha()), Num(window and window:GetAlpha()), Num(windowAlpha),
		tostring(window and window.IsIgnoringParentAlpha and window:IsIgnoringParentAlpha()),
		tostring(window and window:IsMouseEnabled()), table.concat(alphas, ", ")))
	if ns.ShowMeRunning("fadeUI") and windowAlpha then
		part.windowLow, part.windowHigh = math.min(part.windowLow, windowAlpha), math.max(part.windowHigh, windowAlpha)
	end
end

local Next
local function Verdicts(part)
	local window = _G.CinematicWelcome
	local out = {}
	local function Check(ok, what) out[#out + 1] = (ok and "PASS " or "FAIL ") .. what end
	Check(part.started, "the button started the demo")
	-- (Each frame on its own: a level may keep one up in CineMode, the
	-- Shoulder Cam level's minimap. The UI went: at least one frame did, and
	-- each one that went came back. The whole UI's: every one goes.)
	local went, kept = {}, {}
	for _, name in ipairs(part.frames) do
		if (part.low[name] or 1) < 0.1 then
			went[#went + 1] = name
			Check((part.last[name] or 0) > 0.9, ("%s came back (%s after)"):format(name, Num(part.last[name])))
		else
			kept[#kept + 1] = ("%s (darkest %s)"):format(name, Num(part.low[name]))
		end
	end
	if #part.frames == 0 then
		out[#out + 1] = "NOTE no watched frame was on screen to fade"
	elseif part.name == "whole" then
		Check(#kept == 0, "every frame went" .. (#kept > 0 and ", not " .. table.concat(kept, ", ") or ""))
	else
		Check(#went > 0, "the UI went: " .. (#went > 0 and table.concat(went, ", ") or "nothing"))
		if #kept > 0 then out[#out + 1] = "NOTE kept up by the level: " .. table.concat(kept, ", ") end
	end
	Check(part.windowLow > 0.2 and part.windowHigh < 0.45,
		("the window stayed faded, not gone (%s to %s)"):format(Num(part.windowLow), Num(part.windowHigh)))
	Check(math.abs(UIParent:GetAlpha() - part.uiAlpha) < 0.01, "UIParent's alpha put back " .. Num(UIParent:GetAlpha()))
	Check(window and math.abs(window:GetAlpha() - part.windowAlpha) < 0.01, "the window's alpha put back")
	Check(window and window.IsIgnoringParentAlpha and window:IsIgnoringParentAlpha() == part.ignored,
		"the window's parent alpha put back")
	Check(window and window:IsMouseEnabled(), "the window takes the mouse again")
	Check(ns.fadeDemo == nil, "ns.fadeDemo cleared")
	for _, line in ipairs(out) do Log(part.name .. " verdict: " .. line) end
	return out
end

local function Finish(stopped)
	if not run then return end
	if ticker then ticker:Cancel() ticker = nil end
	if ns.ShowMeRunning("fadeUI") then ns.StopShowMe() end
	if run.enabled and not ns.db.enabled then ns.SetEnabled(true) end
	local fails = 0
	for _, part in ipairs(run.parts) do
		for _, line in ipairs(part.verdicts or {}) do
			if line:find("^FAIL") then fails = fails + 1 end
		end
	end
	local summary = stopped and "stopped" or (fails == 0 and "all PASS" or ("%d FAIL"):format(fails))
	Log("summary: " .. summary)
	ns.Print("Fading UI demo test: " .. summary)
	ns.PadTestBox(stopped and "Test stopped." or "Test done.", "/reload, then say: check log", 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
	run = nil
end

local function Start(name)
	local window = _G.CinematicWelcome
	local button = window and FindButton(window, 0)
	local part = { name = name, frames = Watched(), low = {}, last = {}, windowLow = 1, windowHigh = 0,
		uiAlpha = UIParent:GetAlpha(), windowAlpha = window and window:GetAlpha(),
		ignored = window and window.IsIgnoringParentAlpha and window:IsIgnoringParentAlpha() }
	run.parts[#run.parts + 1] = part
	Log(("%s start: profile chosen %s, active %s, frame pages on %s, tag \"%s\", blocked %s, watching %s"):format(name,
		tostring(ns.ProfileChosen()), tostring(ns.ActiveProfile()), tostring(ns.AnyFramePageOn and ns.AnyFramePageOn()),
		tostring(button and button.tag and button.tag:GetText()), tostring((ns.ShowMeBlocked("fadeUI", true))), -- (nothing returned when it can run: one value)
		#part.frames > 0 and table.concat(part.frames, ", ") or "none"))
	if not button then
		Log(name .. ": no Fading UI button in the welcome window")
		part.verdicts = { "FAIL no Fading UI button in the welcome window" }
		return Next()
	end
	ns.TestPrompt(("Fading UI demo, run %d of %d (%s): hands off, watch the UI fade, hold and come back."):format(
		#run.parts, #RUNS, name == "level" and "your level's fade" or "the whole UI"), 6)
	-- (The whole UI's: the demo told nothing's looked after, as before a pick, just while it starts.)
	local real = ns.AnyFramePageOn
	if name == "whole" then ns.AnyFramePageOn = function() return false end end
	local ok, err = pcall(button.Click, button)
	ns.AnyFramePageOn = real
	if not ok then Log(name .. " click error: " .. tostring(err)) end
	part.started = ns.ShowMeRunning("fadeUI")
	local began, ended, shot = GetTime(), nil, false
	ticker = C_Timer.NewTicker(SAMPLE, function()
		local t = GetTime() - began
		local okSample, why = pcall(Sample, part, t)
		if not okSample then Log("sample error: " .. tostring(why)) end
		if not shot and t >= SHOT_AT then
			shot = true
			pcall(Screenshot)
			Log(("%s screenshot at %s"):format(name, date("%H:%M:%S")))
		end
		if not ended and not ns.ShowMeRunning("fadeUI") then ended = GetTime() end
		if ended and GetTime() - ended >= AFTER then
			ticker:Cancel()
			ticker = nil
			part.verdicts = Verdicts(part)
			Next()
		end
	end)
end

function Next()
	if not run then return end
	local name = RUNS[#run.parts + 1]
	if not name then return Finish(false) end
	C_Timer.After(1, function() if run then Start(name) end end)
end

function ns.FadeDemoTest()
	-- (Never the Ctrl+C copy window over the game: the user's rule; its lines
	-- are in chat and the log.)
	ns.debugNoCopyWindow = true
	if run then return Finish(true) end
	if InCombatLockdown() then
		ns.Print("Fading UI demo test: not in a fight.")
		return
	end
	-- (CineMode off for the test, the user's rule: the UI up as you play
	-- without it, so the demo's fade and its coming back are its own. Put back.)
	run = { parts = {}, enabled = ns.db.enabled and true or false }
	Log(("start: client %s, UI scale %s, CineMode switched %s, mouseover %s"):format(tostring(ns.CLIENT),
		Num(UIParent:GetEffectiveScale()), run.enabled and "on" or "off", tostring(ns.db.mouseover)))
	ns.ShowWelcome()
	if run.enabled then ns.SetEnabled(false) end
	ns.Print("Fading UI demo test: two runs of about 10 seconds, hands off (type it again to stop)")
	-- (the UI's time to come up from CineMode first)
	C_Timer.After(2, Next)
end
