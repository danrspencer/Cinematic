-- /cine debug hrtest [steps]: one run checking Health & Resources' table
-- in game (PersonalResources.lua): Opacity while hidden, Show below with
-- Fade range by your health, and by your mana (secret on WoW Forever: the
-- game's curve sets the alpha). It sets the page's settings for each step
-- itself, and puts yours back after (or at the next login, if you /reload
-- mid-run). Timed steps in the big test box (ns.PadTestBox); every frame's
-- numbers go to the log ("hrtest") with a verdict per step and frame.
-- "hrtest 2 3": only those steps. Typed again while running: stops.
-- Dev copy only (CinematicDev.toc).
local _, ns = ...

local READ, LENGTH = 4, 12 -- seconds: to read the step, then recording
local TOLERANCE = 0.08
-- The frames: their kind (Frames.lua's PORTRAIT_FRAMES; the pet frame: none).
local WATCH = {
	PlayerFrame = "portraitWhenNotFull", ElvUF_Player = "portraitWhenNotFull",
	DaylightUIFrame_player = "portraitWhenNotFull", EllesmereUIUnitFrames_Player = "portraitWhenNotFull",
	FlareUI_UF_Player = "portraitWhenNotFull",
	PetFrame = false,
	PersonalResourceDisplayFrame = "prdWhenNotFull", CinematicPersonalResource = "prdWhenNotFull",
	CinematicPersonalPower = "prdWhenNotFull", CinematicPersonalMana = "prdWhenNotFull",
}
-- Every setting a step changes: saved first, put back after.
local KEYS = { "personalResources", "prHealthPlayer", "prPowerPlayer", "prPetHealth", "prHealthPrd", "prPowerPrd",
	"prPowerMana", "prFadeRange", "prAlphaPlayer", "prAlphaPet", "prAlphaPrd", "prAlphaPrdPower", "prAlphaMana" }

local run
-- The player frames: the game's and other addons' (whichever is drawn is checked).
local PLAYER_FRAMES = { "PlayerFrame", "ElvUF_Player", "DaylightUIFrame_player", "EllesmereUIUnitFrames_Player",
	"FlareUI_UF_Player" }
local function PlayerWants(alpha)
	local want = {}
	for _, name in ipairs(PLAYER_FRAMES) do want[name] = alpha end
	return want
end

local function Log(text) ns.Log("hrtest", text) end
local function Readable(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end
local function Num(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Share(value, max)
	if Readable(value) and Readable(max) and max > 0 then return value / max end
end

-- A frame's parents up to UIParent: name(shown, alpha); why it isn't drawn.
local function Chain(frame)
	local out = {}
	for _ = 1, 5 do
		if not frame or frame == UIParent then break end
		local okName, name = pcall(frame.GetName, frame)
		local okShown, shown = pcall(frame.IsShown, frame)
		local okAlpha, alpha = pcall(frame.GetAlpha, frame)
		out[#out + 1] = ("%s(shown %s, alpha %s)"):format(okName and tostring(name) or "?",
			okShown and tostring(shown) or "?", okAlpha and Num(alpha) or "?")
		local okParent, parent = pcall(frame.GetParent, frame)
		frame = okParent and parent or nil
	end
	return table.concat(out, " < ")
end

-- Nothing kept up by a share, nothing showing while hidden: each step
-- changes only what it tests.
local function Quiet(db)
	db.personalResources = true
	for _, key in ipairs({ "prHealthPlayer", "prPowerPlayer", "prPetHealth", "prHealthPrd", "prPowerPrd",
		"prPowerMana", "prAlphaPlayer", "prAlphaPet", "prAlphaPrd", "prAlphaPrdPower", "prAlphaMana" }) do
		db[key] = 0
	end
	db.prFadeRange = 0
end

-- The game's own answer to "is mana under the share?", shown: a sign whose
-- alpha it sets through the same curve the frames get. Not a child of
-- UIParent (CineMode can't hide it).
local sign
local function Sign(show, share)
	if not sign then
		sign = CreateFrame("Frame")
		sign:SetFrameStrata("FULLSCREEN_DIALOG")
		sign:SetSize(460, 44)
		sign:SetPoint("TOP", UIParent, "TOP", 0, -300)
		local back = sign:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0.6, 0, 0, 0.9)
		sign.text = sign:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		sign.text:SetPoint("CENTER")
		sign.text:SetTextColor(1, 1, 1)
	end
	sign:SetShown(show)
	if not show then return end
	sign:SetScale(UIParent:GetEffectiveScale())
	sign.text:SetText(("MANA UNDER %d%% (the game says so)"):format(math.floor(share * 100 + 0.5)))
	ns.SetThresholdSecretAlpha(sign, { powerType = 0, share = share, range = 0.05, floor = 0 })
end
-- (Wrapped: C_Timer refused the game's Screenshot itself on WoW Forever.)
local function Shot() Screenshot() end

-- Each step: what to do, its settings (setup returns what each frame should
-- show: { [name] = alpha }, or a note why it can't), and what it checks.
local STEPS = {
	{ key = "opacity", say = "1/4 OPACITY: stand still, mouse away from your frames. Your player frame and " ..
		"resource bars should be FAINT (40%), not gone, not full",
		setup = function(db)
			Quiet(db)
			for _, key in ipairs({ "prAlphaPlayer", "prAlphaPet", "prAlphaPrd", "prAlphaPrdPower", "prAlphaMana" }) do
				db[key] = 0.4
			end
			local want = {}
			for name in pairs(WATCH) do want[name] = 0.4 end
			return want
		end },
	{ key = "health", say = "2/4 HEALTH FADE: stand still with your health FULL, mouse away. Your player frame should be HALF see-through " ..
		"(fading in by your health)",
		setup = function(db)
			Quiet(db)
			local health = Share(UnitHealth("player"), UnitHealthMax("player"))
			if health and health < 0.06 then return nil, "health too low for the test" end
			-- (Health 2.5% over the share, with 5% of range: halfway in. Secret
			-- (WoW Forever, even out of fights): taken as full, the game's
			-- curve sets the alpha.)
			db.prHealthPlayer = math.min(0.975, (health or 1) - 0.025)
			db.prFadeRange = 0.05
			local want = (db.prHealthPlayer + 0.05 - (health or 1)) / 0.05
			return PlayerWants(want), nil, health == nil
		end },
	{ key = "mana", say = "3/4 MANA FADE: stand still with your mana FULL, mouse away. Your player frame should be " ..
		"HALF see-through (fading in by your mana)",
		setup = function(db)
			Quiet(db)
			local powerType = UnitPowerType("player")
			if Readable(powerType) and powerType ~= 0 then
				return nil, "your power isn't mana now (form or class): log a mana user, or change form"
			end
			local mana = Share(UnitPower("player", 0), UnitPowerMax("player", 0))
			-- (Secret: mana taken as full, the game's curve sets the alpha.)
			db.prPowerPlayer = math.min(0.975, (mana or 1) - 0.025)
			db.prFadeRange = 0.05
			local want = (db.prPowerPlayer + 0.05 - (mana or 1)) / 0.05
			return PlayerWants(want), nil, mana == nil
		end },
	{ key = "drain", length = 60, say = "4/4 MANA DRAIN: cast spells on YOURSELF (heals, buffs), not at enemies, " ..
		"till your mana is well under half. Mouse away from your frames. Your player frame AND the mana bar under " ..
		"your character should fade in as mana nears 50%, with the red sign below. Screenshots every 5 sec",
		setup = function(db)
			Quiet(db)
			local powerType = UnitPowerType("player")
			if Readable(powerType) and powerType ~= 0 then
				return nil, "your power isn't mana now (form or class): log a mana user, or change form"
			end
			db.prPowerPlayer = 0.5
			db.prPowerPrd = 0.5
			-- (Health's shares as they start out too: the frame has both, as in
			-- play. Only mana at 0 once let health's curve win, 2026-11-13.)
			db.prHealthPlayer = 0.95
			db.prHealthPrd = 0.95
			db.prFadeRange = 0.05
			return {}, nil, true
		end,
		tick = function(step, now)
			Sign(true, 0.5)
			if now - (step.shotAt or 0) >= 5 then
				step.shotAt = now
				step.shots = (step.shots or 0) + 1
				Log(("drain screenshot %d at %s"):format(step.shots, date("%H:%M:%S")))
				pcall(Shot)
			end
			-- (Every 2 seconds whatever changed: mana is secret, so the line may not.)
			if now - (step.loggedAt or 0) >= 2 then
				step.loggedAt, step.last = now, nil
			end
		end,
		verdict = function(step)
			return ("drain: %d screenshots taken (Screenshots folder), curve error %s: say check log and I'll " ..
				"look at them"):format(step.shots or 0, tostring(ns.lowManaSecretError))
		end },
}

local function Restore()
	local db = ns.db
	local saved = db and db.hrTestBackup
	if type(saved) ~= "table" then return end
	for _, key in ipairs(KEYS) do
		db[key] = saved[key]
	end
	db.hrTestBackup = nil
end
-- (A /reload mid-run: yours back at the next login.)
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	if ns.db and ns.db.hrTestBackup then
		Restore()
		ns.Print("Health & Resources test: your settings are back (the test didn't finish)")
	end
end)

local function Entries()
	local out = {}
	for _, entry in ipairs(ns.managed or {}) do
		if entry.name and WATCH[entry.name] ~= nil then out[#out + 1] = entry end
	end
	return out
end

-- One sample of every watched frame, logged when it changes; the settled
-- readings (the last 4 seconds) kept for the verdict.
local function Sample(step, settled)
	local parts = {}
	for _, entry in ipairs(Entries()) do
		local setting = WATCH[entry.name] or nil
		local frame = entry.frame
		local okVis, visible = pcall(frame.IsVisible, frame)
		local okEff, effective = pcall(frame.GetEffectiveAlpha, frame)
		local okKeep, keep = pcall(ns.KeepYourFrameUp, setting, entry, false, false)
		local okLevel, level = pcall(ns.YourFrameLevel, setting, entry)
		local spec = entry.manaSecret
		if not (okVis and visible) then
			parts[#parts + 1] = ("%s: NOT VISIBLE, %s, fade %s"):format(entry.name, Chain(frame), Num(entry.alpha))
		else parts[#parts + 1] = ("%s: visible %s, fade %s, drawn %s, keep %s, level %s, vitals secret %s, game curve %s"):format(
			entry.name, okVis and tostring(visible) or "?", Num(entry.alpha), okEff and Num(effective) or "?",
			okKeep and tostring(keep) or ("error " .. tostring(keep)), okLevel and Num(level) or ("error " .. tostring(level)),
			tostring(entry.vitalsSecret or false),
			spec and (spec.health and "health" or ("power " .. Num(spec.powerType))) .. (" at %s, range %s, floor %s"):format(
				Num(spec.share), Num(spec.range), Num(spec.floor)) or "no")
		end
		if settled then
			local seen = step.seen[entry.name] or { n = 0 }
			step.seen[entry.name] = seen
			seen.n = seen.n + 1
			seen.visible = seen.visible or (okVis and visible == true)
			if not (okVis and visible) then seen.hidden = Chain(frame) end
			if Readable(entry.alpha) then
				seen.low = math.min(seen.low or 1, entry.alpha)
				seen.high = math.max(seen.high or 0, entry.alpha)
			end
			if okEff and Readable(effective) then seen.drawn = effective end
			seen.curve = seen.curve or spec ~= nil
			seen.keep = seen.keep or (okKeep and keep == true)
			seen.level = okLevel and level or seen.level
		end
	end
	local line = ("CineMode %s, health %s/%s, mana %s/%s, power type %s, curve error %s | %s"):format(
		tostring(ns.lastCinematic and true or false), Num(UnitHealth("player")), Num(UnitHealthMax("player")),
		Num(UnitPower("player", 0)), Num(UnitPowerMax("player", 0)), Num(UnitPowerType("player")),
		tostring(ns.lowManaSecretError), table.concat(parts, "; "))
	if line ~= step.last then
		step.last = line
		Log(("%s %.1fs %s"):format(step.key, GetTime() - step.at, line))
	end
end

-- The step's verdict, per frame it expected something of.
local function Verdict(step)
	if step.skip then return ("%s: SKIPPED, %s"):format(step.key, step.skip) end
	if not step.cine then return ("%s: FAILED, CineMode was off"):format(step.key) end
	if step.spec and step.spec.verdict then return step.spec.verdict(step) end
	local out = {}
	for name, want in pairs(step.want or {}) do
		local seen = step.seen[name]
		if seen and not seen.visible then
			out[#out + 1] = ("%s NOT CHECKED: the game doesn't draw it (%s)"):format(name, tostring(seen.hidden))
		elseif seen then
			local result
			if seen.curve then
				result = ("GAME'S CURVE set the alpha (secret), wanted %.2f: did it look half see-through? Tell me"):format(want)
			elseif seen.keep then
				result = "FAILED: a share kept it fully up (KeepYourFrameUp)"
			elseif not seen.low then
				result = "FAILED: its fade alpha was secret"
			elseif math.abs(seen.low - want) <= TOLERANCE and math.abs(seen.high - want) <= TOLERANCE then
				result = ("PASS (%.2f, wanted %.2f)"):format(seen.high, want)
			elseif seen.low >= 0.99 then
				result = ("FAILED: fully up (something else showed it: its HUD row, hover, a fight), wanted %.2f"):format(want)
			else
				result = ("FAILED: fade %.2f-%.2f, wanted %.2f (our level said %s)"):format(seen.low, seen.high, want,
					Num(seen.level))
			end
			out[#out + 1] = ("%s %s"):format(name, result)
		end
	end
	if #out == 0 then return ("%s: no watched frame was shown by the game"):format(step.key) end
	table.sort(out)
	return ("%s: %s"):format(step.key, table.concat(out, "; "))
end

local function Finish(stopped)
	if not run then return end
	run.ticker:Cancel()
	Sign(false)
	Restore()
	ns.Print(("Health & Resources test %s: your settings are back"):format(stopped and "stopped" or "done"))
	for _, step in ipairs(run.done) do
		local verdict = Verdict(step)
		Log("verdict " .. verdict)
		ns.Print("  " .. verdict)
	end
	ns.PadTestBox(stopped and "Test stopped." or "Test done.", "/reload, then say: check log", 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
	run = nil
end

local function Tick()
	local now = GetTime()
	-- Waiting for CineMode first.
	if not run.step then
		if not ns.lastCinematic then
			ns.PadTestBox("Turn CineMode ON, then stand still with your mouse away from your frames",
				"waiting for CineMode", 1, 0.82, 0)
			return
		end
		run.index = run.index + 1
		local spec = run.steps[run.index]
		if not spec then return Finish(false) end
		local step = { key = spec.key, at = now, seen = {}, cine = true }
		step.want, step.skip, step.secret = spec.setup(ns.db)
		if step.want then
			local parts = {}
			for name, alpha in pairs(step.want) do parts[#parts + 1] = ("%s %.2f"):format(name, alpha) end
			Log(("%s start: wanted %s%s"):format(step.key, table.concat(parts, ", "),
				step.secret and " (secret: the game's curve, taken as full)" or ""))
		else
			Log(("%s skipped: %s"):format(step.key, tostring(step.skip)))
		end
		step.length, step.spec = spec.length or LENGTH, spec
		run.step, run.say = step, spec.say
		run.done[#run.done + 1] = step
	end
	local step = run.step
	local left = READ + step.length - (now - step.at)
	if step.skip then
		left = math.min(left, 3)
		ns.PadTestBox(run.say, "SKIPPED: " .. step.skip, 1, 0.3, 0.3)
	elseif now - step.at < READ then
		ns.PadTestBox(run.say, ("GET READY: starts in %d"):format(math.ceil(READ - (now - step.at))), 1, 0.82, 0)
	else
		ns.PadTestBox(run.say, ("RECORDING: %d sec left"):format(math.ceil(left)), 0.2, 1, 0.2)
		step.cine = step.cine and (ns.lastCinematic and true or false)
		if step.spec.tick then step.spec.tick(step, now) end
		Sample(step, left <= 4)
	end
	if left <= 0 or step.skip and now - step.at >= 3 then
		Sign(false)
		run.step = nil
	end
end

function ns.ThresholdTest(only)
	if run then return Finish(true) end
	local db = ns.db
	if not db then return end
	local steps = {}
	if type(only) == "string" and only:find("%d") then
		for number in only:gmatch("%d") do
			if STEPS[tonumber(number)] then steps[#steps + 1] = STEPS[tonumber(number)] end
		end
	end
	if #steps == 0 then steps = STEPS end
	-- (Yours, kept: put back after, or at the next login.)
	if not db.hrTestBackup then
		local saved = {}
		for _, key in ipairs(KEYS) do saved[key] = db[key] end
		db.hrTestBackup = saved
	end
	run = { steps = steps, index = 0, done = {} }
	Log(("start: %d steps, client %s"):format(#steps, tostring(ns.isRetail and "retail" or "Forever/Classic")))
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Log("error: " .. tostring(err))
			ns.Print("Health & Resources test error: " .. tostring(err))
			Finish(true)
		end
	end)
	ns.Print(("Health & Resources test: %d steps, follow the box (type it again to stop)"):format(#steps))
end
