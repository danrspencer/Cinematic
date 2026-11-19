-- /cine debug gradtest [steps]: the bar gradients, By health and the pop-up
-- color palette, in one run (2026-11-19). Each step sets what it needs (the
-- Unit Frames, Raid Frames, Personal Resources and Tooltips pages on, frames
-- following their Default tab) and puts every setting back after; a /reload
-- in the middle puts them back at the next login. Two screenshots a step,
-- what the bars' fills read back, and By health's counts (curve colors drawn
-- as a gradient or flat: does the game take a curve's color in SetGradient?)
-- go in CinematicDB.gradientTestLog.
--   1 palette   the pop-up palette opened in the middle
--   2 your      health red to blue, left to right (Unit Frames)
--   3 darker    health and power each to a darker one of their color, top to bottom
--   4 health    By health, flat: green full, yellow half, red empty (take damage)
--   5 healthgr  By health with a gradient to black (take damage)
--   6 raid      party/raid frames: By health and Darker (in a group only)
--   7 personal  the bars under your character: red to blue, power darker
--   8 tooltip   the tooltip's health bar: Darker, top to bottom (point at someone)
-- Dev copy only.
local _, ns = ...

local WAIT = 4    -- seconds to read a step
local STEP = 16   -- seconds a step lasts in all

local RED, BLUE, BLACK = { 1, 0.2, 0.2 }, { 0.1, 0.3, 1 }, { 0, 0, 0 }
local GREEN, YELLOW = { 0.2, 0.85, 0.3 }, { 1, 0.85, 0.1 }

-- (Every setting the steps touch: kept at the start, put back after each step.)
local KEYS = { "ufStyle", "rfStyle", "prdStyle", "tooltipStyle",
	"ufHealthColor", "ufHealthR", "ufHealthG", "ufHealthB", "ufHealthMidR", "ufHealthMidG", "ufHealthMidB",
	"ufHealthLowR", "ufHealthLowG", "ufHealthLowB", "ufGradient", "ufGradR", "ufGradG", "ufGradB", "ufGradDir",
	"ufPowerGradient", "ufPowerGradR", "ufPowerGradG", "ufPowerGradB",
	"rfHealthColor", "rfHealthR", "rfHealthG", "rfHealthB", "rfHealthMidR", "rfHealthMidG", "rfHealthMidB",
	"rfHealthLowR", "rfHealthLowG", "rfHealthLowB", "rfGradient", "rfGradDir",
	"prdHealthColor", "prdHealthR", "prdHealthG", "prdHealthB", "prdGradient", "prdGradR", "prdGradG", "prdGradB",
	"prdPowerGradient", "prdGradDir",
	"tooltipGradient", "tooltipGradDir" }
for _, id in ipairs({ "PLAYER", "TARGET", "FOCUS", "PET", "TOT", "PARTY" }) do KEYS[#KEYS + 1] = "ufOwn_" .. id end
for _, id in ipairs({ "RAID", "PARTY", "ARENA" }) do KEYS[#KEYS + 1] = "rfOwn_" .. id end

local function Set(db, list)
	for key, value in pairs(list) do db[key] = value end
end
local function Color(db, stem, c) db[stem .. "R"], db[stem .. "G"], db[stem .. "B"] = c[1], c[2], c[3] end

local STEPS = {
	{ key = "palette", say = "A box of NAMED COLORS should be open in the middle of the screen.\nJust look.",
		begin = function()
			ns.OpenColorPicker(1, 0.3, 0.23, function() end)
			return "opened at the cursor"
		end },
	{ key = "your", say = "Your PLAYER FRAME's health bar: RED at the left, BLUE at the right.\nJust look.",
		begin = function(db)
			Set(db, { ufStyle = true, ufHealthColor = "custom", ufGradient = "on", ufGradDir = "right" })
			Color(db, "ufHealth", RED)
			Color(db, "ufGrad", BLUE)
		end },
	{ key = "darker", say = "Your PLAYER FRAME's health and power bars: their color at the TOP,\ndarker at the bottom. Just look.",
		begin = function(db)
			Set(db, { ufStyle = true, ufHealthColor = "class", ufGradient = "shade", ufPowerGradient = "shade",
				ufGradDir = "down" })
		end },
	{ key = "health", say = "TAKE SOME DAMAGE (jump off something, or hit a training dummy).\nYour health bar: green when full, yellow at half, red when low.",
		hurt = true,
		begin = function(db)
			Set(db, { ufStyle = true, ufHealthColor = "health", ufGradient = "off" })
			Color(db, "ufHealth", GREEN)
			Color(db, "ufHealthMid", YELLOW)
			Color(db, "ufHealthLow", RED)
		end },
	{ key = "healthgr", say = "TAKE SOME DAMAGE again.\nYour health bar: as before, darkening toward the bar's RIGHT END (a low bar keeps its color).",
		hurt = true,
		begin = function(db)
			Set(db, { ufStyle = true, ufHealthColor = "health", ufGradient = "on", ufGradDir = "right" })
			Color(db, "ufHealth", GREEN)
			Color(db, "ufHealthMid", YELLOW)
			Color(db, "ufHealthLow", RED)
			Color(db, "ufGrad", BLACK)
		end },
	{ key = "raid", say = "Your PARTY or RAID frames: health by health (green, yellow, red),\ndarker at the right. Only in a group: else just wait.",
		begin = function(db)
			Set(db, { rfStyle = true, rfHealthColor = "health", rfGradient = "shade", rfGradDir = "right" })
			Color(db, "rfHealth", GREEN)
			Color(db, "rfHealthMid", YELLOW)
			Color(db, "rfHealthLow", RED)
			return ("in a group %s, %d members"):format(tostring(IsInGroup()), GetNumGroupMembers())
		end },
	{ key = "personal", say = "The bars UNDER YOUR CHARACTER: health RED to BLUE,\npower darker at the right. Just look.",
		begin = function(db)
			Set(db, { prdStyle = true, prdHealthColor = "custom", prdGradient = "on", prdPowerGradient = "shade",
				prdGradDir = "right" })
			Color(db, "prdHealth", RED)
			Color(db, "prdGrad", BLUE)
			local root = _G.PersonalResourceDisplayFrame
			return ("personal bars %s, shown %s"):format(type(root), tostring(root and root:IsShown()))
		end },
	{ key = "tooltip", say = "POINT THE MOUSE AT ANY PLAYER OR NPC.\nThe tooltip's health bar: its color at the top, darker at the bottom.",
		tooltip = true,
		begin = function(db)
			Set(db, { tooltipStyle = true, tooltipGradient = "shade", tooltipGradDir = "down" })
		end },
}

local run -- { at, steps, step, notes, ticker, recording }

local function Say(text)
	local log = CinematicDB and CinematicDB.gradientTestLog
	if log then log[#log + 1] = ("%s %.1f %s"):format(date("%H:%M:%S"), run and GetTime() - run.at or 0, text) end
end
local function T(v)
	if issecretvalue and issecretvalue(v) then return "secret" end
	if type(v) == "number" then return ("%.2f"):format(v) end
	return tostring(v)
end
local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Say(("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end

local function Refresh()
	for _, name in ipairs({ "RefreshUnitStyle", "RefreshRaidStyle", "RefreshPersonalStyle", "RefreshTooltipStyle" }) do
		if ns[name] then
			local ok, err = pcall(ns[name])
			if not ok then Say(("  %s error: %s"):format(name, tostring(err))) end
		end
	end
end

-- (Frames follow their Default tab, where the steps set things: again on
-- each step, as putting things back between steps puts these back too.)
local function Follow(db)
	for _, key in ipairs(KEYS) do
		if key:find("^ufOwn_") or key:find("^rfOwn_") then db[key] = false end
	end
end

local function Keep(db)
	local kept = {}
	for _, key in ipairs(KEYS) do kept[key] = db[key] == nil and "__nil" or db[key] end
	CinematicDB.gradientTestKept = kept
end
local function PutBack()
	local db = ns.GetDB()
	local kept = CinematicDB and CinematicDB.gradientTestKept
	if not (db and kept) then return end
	for key, value in pairs(kept) do
		if value == "__nil" then db[key] = nil else db[key] = value end
	end
	if ns.ColorPalette then ns.ColorPalette.Close() end
	Refresh()
end
-- (A /reload in the middle: put back at the next login.)
local loginWatch = CreateFrame("Frame")
loginWatch:RegisterEvent("PLAYER_LOGIN")
loginWatch:SetScript("OnEvent", function()
	if CinematicDB and CinematicDB.gradientTestKept and not run then
		C_Timer.After(1, function()
			PutBack()
			CinematicDB.gradientTestKept = nil
		end)
	end
end)

-- What a bar's fill reads back (a gradient reads as its first color, or white).
local function Fill(name, bar)
	if not (bar and bar.GetStatusBarTexture) then return ("%s: none"):format(name) end
	local fill = bar:GetStatusBarTexture()
	if not fill then return ("%s: no fill"):format(name) end
	local r, g, b = fill:GetVertexColor()
	local okBar, br, bg, bb = pcall(bar.GetStatusBarColor, bar)
	local value, most = bar:GetValue(), select(2, bar:GetMinMaxValues())
	local okLayer, layer = pcall(function() return ns.UnitStyleLayerReport and ns.UnitStyleLayerReport(fill) end)
	return ("%s: fill %s %s %s, bar %s %s %s, value %s of %s, shown %s, desat %s | %s"):format(name, T(r), T(g), T(b),
		okBar and T(br) or "error", T(bg), T(bb), T(value), T(most), T(bar:IsVisible()),
		T(fill.IsDesaturated and fill:IsDesaturated()), okLayer and tostring(layer) or ("layer report error " .. tostring(layer)))
end
local function Bars()
	local player = _G.PlayerFrame
	local content = player and player.PlayerFrameContent and player.PlayerFrameContent.PlayerFrameContentMain
	local health = content and content.HealthBarsContainer and content.HealthBarsContainer.HealthBar
		or _G.PlayerFrameHealthBar
	local power = content and content.ManaBarArea and content.ManaBarArea.ManaBar or _G.PlayerFrameManaBar
	Say("  " .. Fill("player health", health))
	Say("  " .. Fill("player power", power))
	local member = _G.CompactPartyFrameMember1 or _G.CompactRaidFrame1
	if member then Say("  " .. Fill("first group frame health", member.healthBar)) end
	local root = _G.PersonalResourceDisplayFrame
	local holder = root and root.HealthBarsContainer
	Say("  " .. Fill("personal health", holder and holder.healthBar or root and (root.healthbar or root.healthBar)))
	Say("  " .. Fill("personal power", root and root.PowerBar))
	Say("  " .. Fill("tooltip health", _G.GameTooltipStatusBar))
	local okHealth, now = pcall(UnitHealth, "player")
	local okMax, most = pcall(UnitHealthMax, "player")
	Say(("  your health %s of %s, in combat %s"):format(okHealth and T(now) or "error", okMax and T(most) or "error",
		tostring(InCombatLockdown())))
end

local function Stats()
	local s = ns.ByHealthStats
	if not s then return "no By health counts" end
	return ("By health: curve colors %d, as a gradient %d, flat %d, failed %d%s%s"):format(s.curve, s.grad, s.flat,
		s.fail, s.err and (", last error " .. s.err) or "", s.gradErr and (", gradient refused: " .. s.gradErr) or "")
end
local function ResetStats()
	local s = ns.ByHealthStats
	if not s then return end
	s.curve, s.grad, s.flat, s.fail, s.err, s.gradErr = 0, 0, 0, 0, nil, nil
end

local function Verdict(index)
	local step, note = STEPS[index], run.notes[index]
	if not note then return end
	local s = ns.ByHealthStats or {}
	local verdict = "ran; see the screenshots"
	if note.err then
		verdict = "ERROR " .. note.err
	elseif step.key == "palette" then
		verdict = note.open and "PASS: the palette opened" or "FAIL: the palette never showed"
	elseif step.hurt then
		if not ns.CanColorByHealth then
			verdict = "SKIPPED: this client has no color curves"
		elseif (s.curve or 0) == 0 then
			verdict = "FAIL: By health never drew (" .. tostring(s.err) .. ")"
		elseif step.key == "healthgr" then
			verdict = (s.grad or 0) > 0 and "PASS: the game takes a curve's color in a gradient"
				or ("NO GRADIENT: drawn flat (" .. tostring(s.gradErr) .. ")")
		else
			verdict = "drew " .. s.curve .. " times; see the screenshots"
		end
		if not note.hurt then verdict = verdict .. " | NO DAMAGE SEEN (redo: /cine debug gradtest " .. index .. ")" end
	elseif step.tooltip and not note.tip then
		verdict = "NO TOOLTIP ON A UNIT SEEN (redo: /cine debug gradtest " .. index .. ")"
	end
	Say(("verdict %d %s: %s | %s; %s"):format(index, step.key, verdict, Stats(), note.setup or "-"))
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, _, unit)
	if not (run and run.recording and unit == "player") then return end
	local note = run.notes[run.step]
	if note then note.hurt = true end
end)

local function Finish(done)
	if not run then return end
	if run.step and run.notes[run.step] then Verdict(run.step) end
	if run.ticker then run.ticker:Cancel() end
	watcher:UnregisterAllEvents()
	local cineWasOn = run.cineWasOn
	run = nil
	PutBack()
	if cineWasOn and ns.IsCineModeOn and not ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		Cinematic_ToggleCineMode()
	end
	CinematicDB.gradientTestKept = nil
	Say(done and "done: every setting put back" or "stopped: every setting put back")
	ns.TestPrompt(done and "Gradient test done. /reload, then say \"check log\"." or "Gradient test stopped.", 12)
	ns.PadTestBox(done and "Gradient test done. /reload, then say \"check log\"." or "Gradient test stopped.", "",
		1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local now = GetTime() - run.at
	local slot = math.floor(now / STEP) + 1
	if slot > #run.steps then
		Finish(true)
		return
	end
	local index = run.steps[slot]
	local step = STEPS[index]
	local into = now - (slot - 1) * STEP
	if index ~= run.step then
		if run.step and run.notes[run.step] then Verdict(run.step) end
		PutBack()
		run.step, run.recording, run.shots = index, false, 0
		run.notes[index] = {}
		ResetStats()
		Say(("--- step %d %s (in combat %s) ---"):format(index, step.key, tostring(InCombatLockdown())))
		local db = ns.GetDB()
		Follow(db)
		local ok, setup = pcall(step.begin, db)
		if not ok then run.notes[index].err = tostring(setup) end
		run.notes[index].setup = ok and (setup or "set") or ("setup error: " .. tostring(setup))
		Refresh()
		Say("  " .. run.notes[index].setup)
		ns.TestPrompt(("Step %d of %d: %s"):format(slot, #run.steps, (step.say:gsub("\n", " "))), WAIT)
	end
	-- (CineMode come back on by itself, its own triggers: off again.)
	if ns.IsCineModeOn and ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		Cinematic_ToggleCineMode()
		Say("  CineMode came back on: turned off again")
	end
	local note = run.notes[index]
	if step.key == "palette" and ns.ColorPalette and ns.ColorPalette.IsOpen() then note.open = true end
	if step.tooltip then
		local ok, _, unit = pcall(GameTooltip.GetUnit, GameTooltip)
		if ok and unit and GameTooltip:IsShown() and not note.tip then
			note.tip = true
			C_Timer.After(0.3, function()
				if run and run.step == index then
					Bars()
					Shot(("step %d %s tooltip"):format(index, step.key))
				end
			end)
		end
	end
	local say = ("Step %d of %d:\n%s"):format(slot, #run.steps, step.say)
	if into < WAIT then
		ns.PadTestBox(say, ("GET READY: starts in %d"):format(math.ceil(WAIT - into)), 1, 0.82, 0)
	else
		run.recording = true
		ns.PadTestBox(say, ("RECORDING: %d sec left"):format(math.ceil(STEP - into)), 0.3, 1, 0.3)
		-- (Two screenshots: 2 s in, and near the end, with what the bars read back.)
		local due = run.shots == 0 and WAIT + 2 or run.shots == 1 and STEP - 2 or nil
		if due and into >= due then
			run.shots = run.shots + 1
			Say(("step %d %s, shot %d:"):format(index, step.key, run.shots))
			pcall(Bars)
			Say("  " .. Stats())
			Shot(("step %d %s %d"):format(index, step.key, run.shots))
		end
	end
end

function ns.GradientTest(args)
	if run then
		Finish(false)
		return
	end
	local db = ns.GetDB()
	if not db then return end
	local steps = {}
	for number in (args or ""):gmatch("%d+") do
		number = tonumber(number)
		if STEPS[number] then steps[#steps + 1] = number end
	end
	if #steps == 0 then for i = 1, #STEPS do steps[i] = i end end
	CinematicDB.gradientTestLog = {}
	run = { at = GetTime(), steps = steps, notes = {}, shots = 0 }
	Keep(db)
	-- (CineMode off for the run, as the Toggle CineMode key does it: it hides
	-- the frames, bars and tooltips the steps change. Back on at the end; a
	-- /reload brings it back by itself.)
	run.cineWasOn = ns.IsCineModeOn and ns.IsCineModeOn() or false
	if run.cineWasOn and Cinematic_ToggleCineMode then Cinematic_ToggleCineMode() end
	Say(("start: %s (game %s), in combat %s, color curves %s, CineMode was on %s (now %s), steps %s"):format(
		ns.isRetail and "retail" or "Forever", tostring((select(4, GetBuildInfo()))), tostring(InCombatLockdown()),
		tostring(ns.CanColorByHealth), tostring(run.cineWasOn), tostring(ns.IsCineModeOn and ns.IsCineModeOn()),
		table.concat(steps, " ")))
	watcher:RegisterUnitEvent("UNIT_HEALTH", "player")
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			Finish(false)
		end
	end)
end
