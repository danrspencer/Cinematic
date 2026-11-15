-- /cine debug flickertest [steps]: one run checking that your player frame
-- stays up while your health isn't full (Health & Resources' Show below at
-- 99%) and doesn't go up and down (a player's report 2026-11-14: hurt or a
-- ghost, it flickered). Sets the page's settings itself and puts yours back
-- after (or at the next login, if you /reload mid-run). Timed steps in the
-- big test box (ns.PadTestBox); every change of the frame's state goes to
-- the log ("flickertest") with a screenshot every 5 seconds and a verdict per
-- step. "flickertest 2": only that step. Typed again while running: stops.
-- Dev copy only (CinematicDev.toc).
local _, ns = ...

local READ = 5          -- seconds to read the step
local SAMPLE = 0.1      -- seconds between samples
local SHOT_EVERY = 5    -- seconds between screenshots
local KEYS = { "personalResources", "prHealthPlayer", "prPowerPlayer", "prFadeRange", "prAlphaPlayer",
	"fightWaitPull" }
local PLAYER_FRAMES = { PlayerFrame = true, ElvUF_Player = true, DaylightUIFrame_player = true,
	EllesmereUIUnitFrames_Player = true, FlareUI_UF_Player = true }

local run
local function Log(text) ns.Log("flickertest", text) end
local function Secret(value) return issecretvalue and issecretvalue(value) or false end
local function Num(value)
	if value == nil then return "nil" end
	if Secret(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Dead() return ns.Flag(UnitIsDeadOrGhost("player")) and true or false end
-- (Wrapped: C_Timer refused the game's Screenshot itself on WoW Forever.)
local function Shot() Screenshot() end

-- The page as it starts out: up while health or power isn't full.
-- (share95: as profiles updated in v2.0.97 have it, health and power 95%
-- with a 5% Fade range: two secret curves, health's and mana's.)
local function NotFullRules(db, share95)
	db.personalResources = true
	db.prHealthPlayer, db.prPowerPlayer = share95 and 0.95 or 0.99, share95 and 0.95 or 0.99
	db.prFadeRange, db.prAlphaPlayer = share95 and 0.05 or 0, 0
	db.fightWaitPull = false
end

local STEPS = {
	{ key = "hurt", length = 40, say = "1/3 HURT: out of combat, lose some health (jump from a height), then " ..
		"stand still, mouse away from your frames. Your player frame should come up and STAY up, no blinking, " ..
		"until your health is full again" },
	{ key = "share95", length = 40, share95 = true, say = "2/3 HURT AT 95%: mana FULL, out of combat, lose a LOT " ..
		"of health (a big fall, under 90%), then stand still, mouse away. Your player frame should come up and " ..
		"STAY up, no blinking, fading out as you near 100%" },
	{ key = "ghost", length = 30, ghost = true, say = "3/3 GHOST: as a ghost (released), stand still, mouse " ..
		"away from your frames. Your player frame should stay up, no blinking" },
}

local function Restore()
	local db = ns.db
	local saved = db and db.flickerTestBackup
	if type(saved) ~= "table" then return end
	for _, key in ipairs(KEYS) do db[key] = saved[key] end
	db.flickerTestBackup = nil
end
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	if ns.db and ns.db.flickerTestBackup then
		Restore()
		ns.Print("Flicker test: your settings are back (the test didn't finish)")
	end
end)

-- The player frame the game draws (ours or an addon's).
local function PlayerEntry()
	local first
	for _, entry in ipairs(ns.managed or {}) do
		if entry.name and PLAYER_FRAMES[entry.name] then
			local ok, visible = pcall(entry.frame.IsVisible, entry.frame)
			if ok and visible == true then return entry end
			first = first or entry
		end
	end
	return first
end

-- One sample: whether the frame is up now, and why. Up: a share keeps it up
-- (KeepYourFrameUp), the game's health curve sets its alpha (hurt: drawn),
-- or its fade alpha is over half.
local function Sample(step, now)
	local entry = PlayerEntry()
	if not entry then
		step.missing = true
		return
	end
	local fighting = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	local okKeep, keep = pcall(ns.KeepYourFrameUp, "portraitWhenNotFull", entry, false, fighting)
	local spec = entry.manaSecret
	local curve = spec and (spec.health and ("health at " .. Num(spec.share)) or ("power " .. Num(spec.powerType)))
	local alpha = entry.alpha
	local up = (okKeep and keep == true) or (spec and spec.health and true) or (type(alpha) == "number"
		and not Secret(alpha) and alpha > 0.5) or false
	local health, max = UnitHealth("player"), UnitHealthMax("player")
	local secret = Secret(health)
	step.secretSeen = step.secretSeen or secret
	step.readableSeen = step.readableSeen or not secret
	step.fighting = step.fighting or fighting
	step.ghostSeen = step.ghostSeen or Dead()
	local okEff, drawn = pcall(entry.frame.GetEffectiveAlpha, entry.frame)
	local state = ("%s up %s, keep %s, game curve %s, fade %s, drawn %s, health %s/%s, dead/ghost %s, fight %s, CineMode %s")
		:format(entry.name, tostring(up), okKeep and tostring(keep) or ("error " .. tostring(keep)), curve or "no",
		Num(alpha), okEff and Num(drawn) or "?", Num(health), Num(max), tostring(Dead()), tostring(fighting),
		tostring(ns.lastCinematic and true or false))
	if state ~= step.last then
		step.last = state
		Log(("%s %.1fs %s"):format(step.key, now - step.at - READ, state))
	end
	-- (Flicker: down after being up, then up again.)
	if up ~= step.up then
		if up then
			step.ups = (step.ups or 0) + 1
			if step.wentDown then
				step.flickers = (step.flickers or 0) + 1
				Log(("%s FLICKER %d: back up %.1fs after going down"):format(step.key, step.flickers, now - step.downAt))
			end
		elseif step.up then
			step.wentDown, step.downAt = true, now
		end
		step.up = up
	end
	step.endUp = up
	step.cine = step.cine and (ns.lastCinematic and true or false)
end

local function Verdict(step)
	if step.skip then return ("%s: SKIPPED, %s"):format(step.key, step.skip) end
	if step.missing then return ("%s: FAILED, no player frame found among the faded frames"):format(step.key) end
	if not step.cine then return ("%s: NOT CHECKED, CineMode was off at some point"):format(step.key) end
	local path = step.secretSeen and (step.readableSeen and "health secret part of the time" or "health secret (the fix's path)")
		or "health readable (the fix's path not reached: try again in a group)"
	local fight = step.fighting and ", a fight came in (not a fair test)" or ""
	if not step.ups then
		return ("%s: FAILED, the frame never came up (%s%s)"):format(step.key, path, fight)
	end
	if (step.flickers or 0) > 0 then
		return ("%s: FAILED, flickered %d times (%s%s)"):format(step.key, step.flickers, path, fight)
	end
	return ("%s: PASS, came up and stayed (%s%s), %d screenshots"):format(step.key, path, fight, step.shots or 0)
end

local function Finish(stopped)
	if not run then return end
	run.ticker:Cancel()
	Restore()
	ns.Print(("Flicker test %s: your settings are back"):format(stopped and "stopped" or "done"))
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
	if not run.step then
		if not ns.lastCinematic then
			ns.PadTestBox("Turn CineMode ON, then stand still with your mouse away from your frames",
				"waiting for CineMode", 1, 0.82, 0)
			return
		end
		run.index = run.index + 1
		local spec = run.steps[run.index]
		if not spec then return Finish(false) end
		local step = { key = spec.key, at = now, cine = true, spec = spec }
		if spec.ghost and not Dead() then
			step.skip = "you weren't dead or a ghost: as a ghost, type /cine debug flickertest 3"
			Log(("%s skipped: %s"):format(step.key, step.skip))
		else
			NotFullRules(ns.db, spec.share95)
			Log(("%s start"):format(step.key))
		end
		run.step, run.done[#run.done + 1] = step, step
	end
	local step = run.step
	local spec = step.spec
	local left = READ + spec.length - (now - step.at)
	if step.skip then
		ns.PadTestBox(spec.say, "SKIPPED: " .. step.skip, 1, 0.3, 0.3)
		if now - step.at >= 4 then run.step = nil end
		return
	end
	if now - step.at < READ then
		ns.PadTestBox(spec.say, ("GET READY: starts in %d"):format(math.ceil(READ - (now - step.at))), 1, 0.82, 0)
		return
	end
	ns.PadTestBox(spec.say, ("RECORDING: %d sec left%s"):format(math.ceil(left),
		step.flickers and (", FLICKERS: %d"):format(step.flickers) or ""), 0.2, 1, 0.2)
	Sample(step, now)
	if now - (step.shotAt or 0) >= SHOT_EVERY then
		step.shotAt = now
		step.shots = (step.shots or 0) + 1
		Log(("%s screenshot %d at %s"):format(step.key, step.shots, date("%H:%M:%S")))
		pcall(Shot)
	end
	if left <= 0 then run.step = nil end
end

function ns.FlickerTest(only)
	if run then return Finish(true) end
	local db = ns.db
	if not db then return end
	local steps = {}
	if type(only) == "string" then
		for number in only:gmatch("%d") do
			if STEPS[tonumber(number)] then steps[#steps + 1] = STEPS[tonumber(number)] end
		end
	end
	if #steps == 0 then steps = STEPS end
	if not db.flickerTestBackup then
		local saved = {}
		for _, key in ipairs(KEYS) do saved[key] = db[key] end
		db.flickerTestBackup = saved
	end
	run = { steps = steps, index = 0, done = {} }
	Log(("start: %d steps, client %s"):format(#steps, ns.isRetail and "retail" or "Forever/Classic"))
	run.ticker = C_Timer.NewTicker(SAMPLE, function()
		local ok, err = pcall(Tick)
		if not ok then
			Log("error: " .. tostring(err))
			ns.Print("Flicker test error: " .. tostring(err))
			Finish(true)
		end
	end)
	ns.Print(("Flicker test: %d steps, follow the box (type it again to stop)"):format(#steps))
end
