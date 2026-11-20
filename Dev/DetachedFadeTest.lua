-- /cine debug detached: parts that ignore their frame's alpha follow our fade
-- (FadeDetached.lua). Found by a player on Forever with FlareUI 6.13, which
-- makes bar 1's gryphons ignore EndCaps' alpha: our hide stopped reaching
-- them. Hands off, about 15 s; CineMode off meanwhile; everything put back at
-- the end. Another addon is played by code loaded under a made-up addon's
-- path (the call stack is how we tell ours from theirs).
--   1 any frame   a test panel faded: another addon's detached part fades
--                 with it, one detached later too, ours stays, all back after
--   2 gryphons    the Overrides tab's Action bar art: Hide. Each gryphon
--                 gone (detached by FlareUI if it's on, else by the stand-in
--                 addon), and kept gone when that addon raises it; screenshot
--   3 back        the row as it was: the gryphons back; screenshot
-- Into CinematicDB.detachedFadeLog, with the main log's fade lines.
local _, ns = ...

local WAIT = 1
local run

local function Log(text)
	local log = CinematicDB and CinematicDB.detachedFadeLog
	if log then log[#log + 1] = ("%s %s"):format(date("%H:%M:%S"), text) end
end
local function Verdict(ok, text)
	if ok then run.pass = run.pass + 1 else run.fail = run.fail + 1 end
	Log(("  verdict %s: %s"):format(ok and "PASS" or "FAIL", text))
end
local function Plain(value)
	if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
	return value
end
local function Describe(region)
	if not region then return "missing" end
	return ("alpha %s, effective %s, ignores parent %s, visible %s"):format(tostring(Plain(region:GetAlpha())),
		tostring(Plain(region:GetEffectiveAlpha())), tostring(region:IsIgnoringParentAlpha()),
		tostring(region:IsVisible()))
end
local function Shot()
	pcall(function() Screenshot() end)
end
local function CineOn() return ns.IsCineModeOn and ns.IsCineModeOn() and true or false end
local function SetCine(on)
	if Cinematic_ToggleCineMode and CineOn() ~= on then Cinematic_ToggleCineMode() end
end
local function Later(seconds, fn)
	C_Timer.After(seconds, function()
		if run then ns.Guard(fn) end
	end)
end

-- "Another addon": a function made under a made-up addon's file path, so the
-- call stack names it and not us.
local theirs = loadstring([[
	local region, on, alpha = ...
	if on ~= nil then region:SetIgnoreParentAlpha(on) end
	if alpha then region:SetAlpha(alpha) end
]], "@Interface\\AddOns\\CinematicStandInAddon\\Bars.lua")

local function Caps()
	local bar = _G.MainActionBar or _G.MainMenuBar
	local caps = bar and bar.EndCaps
	return caps, caps and caps.LeftEndCap, caps and caps.RightEndCap
end
local function LogCaught(label)
	local caught = ns.DetachedFor and ns.barArtStandIn and ns.DetachedFor(ns.barArtStandIn) or {}
	local parts = {}
	for _, part in ipairs(caught) do
		parts[#parts + 1] = ("%s by %s drawn %s"):format(part.name, tostring(part.by), tostring(part.drawn))
	end
	Log(("  %s: /cine why's list for the art: %s"):format(label, #parts > 0 and table.concat(parts, "; ") or "none"))
end
local function LogHas(text, from)
	for i = from + 1, #(ns.db.log or {}) do
		local line = ns.db.log[i]
		if type(line) == "string" and line:find(text, 1, true) then return true end
	end
	return false
end

local function PutBack()
	if not run or run.putBack then return end
	run.putBack = true
	for key, value in pairs(run.kept) do ns.db[key] = value end
	if ns.ApplyBarArtOverride then ns.ApplyBarArtOverride() end
	-- (Gryphons we detached as the stand-in addon: as they were.)
	for region, was in pairs(run.ignoreWas) do theirs(region, was) end
	if run.panel then run.panel:Hide() end
	SetCine(run.cineWasOn)
end

local function Finish()
	local caps, left, right = Caps()
	Log(("  after putting back: EndCaps %s | left %s | right %s"):format(Describe(caps), Describe(left), Describe(right)))
	local line = ("done: %d pass, %d fail"):format(run.pass, run.fail)
	Log(line)
	run = nil
	ns.TestPrompt(("Detached parts test DONE: %s. Say \"check log\"."):format(line), 15)
end

local function StepBack()
	Log("--- 3 of 3: the Action bar art row as it was ---")
	for key, value in pairs(run.kept) do ns.db[key] = value end
	run.kept = {}
	ns.ApplyBarArtOverride()
	Later(WAIT, function()
		local _, left, right = Caps()
		Log(("  left %s | right %s"):format(Describe(left), Describe(right)))
		for _, cap in ipairs({ left, right }) do
			local was = run.ownWas[cap]
			Verdict(Plain(cap:GetAlpha()) == was, ("%s back at its own alpha %s"):format(cap == left and "left" or
				"right", tostring(was)))
		end
		ns.TestPrompt("Detached parts test: the gryphons should be back.", 3)
		Shot()
		Log("  screenshot: gryphons back")
		PutBack()
		Later(WAIT, Finish)
	end)
end

local function StepGryphons()
	Log("--- 2 of 3: Overrides > Action bar art: Hide ---")
	local caps, left, right = Caps()
	if not (caps and left and right) then
		Log("  verdict INFO: no gryphons on this client (EndCaps.LeftEndCap/RightEndCap): step skipped")
		PutBack()
		return Later(WAIT, Finish)
	end
	local flare = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("FlareUI")
	Log(("  FlareUI loaded %s | EndCaps %s | left %s | right %s"):format(tostring(flare), Describe(caps),
		Describe(left), Describe(right)))
	for _, cap in ipairs({ left, right }) do
		run.ownWas[cap] = Plain(cap:GetAlpha())
		if not cap:IsIgnoringParentAlpha() then
			-- (No addon detached it here: the stand-in addon does, as FlareUI would.)
			run.ignoreWas[cap] = false
			theirs(cap, true)
			Log(("  %s detached by the stand-in addon"):format(cap == left and "left" or "right"))
		else
			Log(("  %s already ignores EndCaps' alpha (FlareUI or the game)"):format(cap == left and "left" or "right"))
		end
	end
	local logFrom = #(ns.db.log or {})
	local function Keep(key, value)
		if run.kept[key] == nil then run.kept[key] = ns.db[key] == nil and false or ns.db[key] end
		ns.db[key] = value
	end
	-- (The Overrides tab and the switches over it on: Style switch chain.)
	Keep("styleGeneral", true)
	Keep("styleOverrides", true)
	Keep("tabOn:Style Overrides:5", true)
	Keep("styleOver_barArt", "hide")
	ns.ApplyBarArtOverride()
	Later(WAIT, function()
		Log(("  EndCaps %s | left %s | right %s"):format(Describe(caps), Describe(left), Describe(right)))
		Verdict(Plain(left:GetEffectiveAlpha()) == 0 and Plain(right:GetEffectiveAlpha()) == 0,
			"both gryphons at 0 while they ignore EndCaps' alpha")
		LogCaught("hidden")
		Log(("  verdict INFO: a new catch line in /cine log %s (once per part a session)"):format(
			tostring(LogHas("ignores its frame's alpha", logFrom))))
		theirs(left, nil, 1)
		Log("  the stand-in addon raised the left gryphon to 1")
		Later(WAIT / 2, function()
			Log(("  left %s"):format(Describe(left)))
			Verdict(Plain(left:GetEffectiveAlpha()) == 0, "raised by another addon while hidden: kept at 0")
			ns.TestPrompt("Detached parts test: the gryphons should be gone.", 3)
			Shot()
			Log("  screenshot: gryphons gone")
			Later(WAIT, StepBack)
		end)
	end)
end

local function StepAnyFrame()
	Log("--- 1 of 3: a faded test panel ---")
	local panel = CreateFrame("Frame", nil, UIParent)
	run.panel = panel
	panel:SetSize(10, 10)
	panel:SetPoint("CENTER")
	local loose = CreateFrame("Frame", nil, panel)
	local late = CreateFrame("Frame", nil, panel)
	local own = CreateFrame("Frame", nil, panel)
	for _, part in ipairs({ loose, late, own }) do part:SetSize(4, 4) part:SetPoint("CENTER") end
	theirs(loose, true)
	own:SetIgnoreParentAlpha(true) -- (ours: from this file's call)
	panel:SetAlpha(0)
	ns.SyncDetached(panel)
	theirs(late, true) -- (detached after the fade: by the hook)
	Log(("  loose %s | late %s | ours %s"):format(Describe(loose), Describe(late), Describe(own)))
	Verdict(Plain(loose:GetAlpha()) == 0, "another addon's detached part faded with the panel")
	Verdict(Plain(late:GetAlpha()) == 0, "one detached while it's faded: faded too (the shared hook)")
	Verdict(Plain(own:GetAlpha()) == 1, "a part Cinematic detached left as it is")
	panel:SetAlpha(1)
	ns.SyncDetached(panel)
	Verdict(Plain(loose:GetAlpha()) == 1 and Plain(late:GetAlpha()) == 1, "the panel back up: theirs back at 1")
	panel:Hide()
	Later(WAIT, StepGryphons)
end

function ns.DetachedFadeTest()
	if not CinematicDB then return end
	if run then
		PutBack()
		run = nil
		ns.TestPrompt("Detached parts test stopped; your settings are back.", 4)
		return
	end
	CinematicDB.detachedFadeLog = {}
	run = { pass = 0, fail = 0, kept = {}, ignoreWas = {}, ownWas = {}, cineWasOn = CineOn() }
	Log(("start: %s (game %s), in a fight %s, CineMode %s, hook in %s"):format(ns.isRetail and "retail" or
		"Forever", tostring((select(4, GetBuildInfo()))), tostring(InCombatLockdown()), tostring(run.cineWasOn),
		tostring(ns.OnIgnoreParentAlpha ~= nil)))
	if InCombatLockdown() then
		Log("  verdict INFO: in a fight: run it again after")
		run = nil
		return ns.TestPrompt("Detached parts test: run it out of a fight.", 5)
	end
	SetCine(false)
	ns.TestPrompt("Detached parts test: hands off, about 15 seconds.", 5)
	StepAnyFrame()
end
