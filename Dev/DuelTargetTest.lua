-- /cine debug dueltarget: a duelist you have targeted keeps a whole plate
-- while the Target section's Nameplates row (Your Target) hides your target's
-- plate (user, Forever 2026-11-20: after a fight, one duelist's plate showed
-- empty, every part held at 0 under a name-only look). One run: CineMode on,
-- pretend duels started (friendly players near you, a city is best), you
-- target a player with a duel border, then hands off: their plate read as it
-- is, then with Your Target hiding your target's plate (3 s to settle), then
-- with it let go again. Per read: the plate's alpha, its body share (the
-- parts other than the name), the fade's own account, the duel level, Your
-- Target's hold, and its parts' alphas. Verdicts at the end, a screenshot
-- while the hide is on. CineMode and pretend duels put back as they were.
-- Logged into CinematicDB.duelTargetLog. Dev copy only.
local _, ns = ...

local SETTLE = 3
local run -- { cineWasOn, duelsWereOn, reads = {}, ticker }

local function Log(text)
	local log = CinematicDB and CinematicDB.duelTargetLog
	if not log then return end
	log[#log + 1] = ("%s %s"):format(date("%H:%M:%S"), text)
end

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end
local function Say(value)
	if value == nil then return "nil" end
	if not Known(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function CineOn() return ns.IsCineModeOn and ns.IsCineModeOn() and true or false end
local function SetCine(on)
	if not (ns.IsCineModeOn and Cinematic_ToggleCineMode) then return end
	if CineOn() ~= on then Cinematic_ToggleCineMode() end
end
local function TargetPlate()
	local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
	local ok, plate = pcall(get, "target")
	return ok and plate or nil
end
local function Alpha(frame)
	if not frame then return nil end
	local ok, value = pcall(frame.GetAlpha, frame)
	return ok and Known(value) and value or nil
end

-- One read of your target's plate.
local function Read(label)
	local plate = TargetPlate()
	local facts = { label = label, plate = plate ~= nil }
	local parts = { ("%s: target %s, plate %s, CineMode %s, combat %s"):format(label, Say(UnitName("target")),
		plate and (plate.namePlateUnitToken or "?") or "NONE", tostring(CineOn()), tostring(InCombatLockdown())) }
	if plate and plate.UnitFrame then
		local frame = plate.UnitFrame
		facts.alpha = Alpha(frame)
		facts.body = frame.cinematicBodyAlpha -- (nil: the whole plate at its alpha)
		facts.health = Alpha(frame.HealthBarsContainer or frame.healthBar)
		facts.duel, facts.held, facts.holdLevel = ns.DuelTargetState(plate)
		parts[#parts + 1] = ("frame alpha %s, body %s, health part %s, duel level %s, Your Target holding it %s (level %s)")
			:format(Say(facts.alpha), Say(facts.body), Say(facts.health), Say(facts.duel), tostring(facts.held),
			Say(facts.holdLevel))
		local unit = plate.namePlateUnitToken or frame.unit
		if ns.DescribePlateNameKept and unit then
			local ok, text = pcall(ns.DescribePlateNameKept, unit, plate)
			parts[#parts + 1] = "fade: " .. (ok and tostring(text) or ("error " .. tostring(text)))
		end
		if ns.DescribePlateParts then
			local ok, text = pcall(ns.DescribePlateParts, frame)
			parts[#parts + 1] = "parts: " .. (ok and tostring(text) or ("error " .. tostring(text)))
		end
	end
	Log(table.concat(parts, " | "))
	run.reads[label] = facts
	return facts
end

local function Verdict(ok, text)
	Log(((ok == nil) and "SKIP " or ok and "PASS " or "FAIL ") .. text)
end

local function Whole(facts)
	return facts and facts.plate and (facts.alpha or 0) >= 0.99 and facts.body == nil
		and (facts.health == nil or facts.health >= 0.99)
end

local function PutBack()
	ns.testTargetHeldDown = nil
	if run.ticker then run.ticker:Cancel() end
	if not run.duelsWereOn and ns.ToggleDuelTest then
		local on = ns.ToggleDuelTest()
		if on then ns.ToggleDuelTest() end -- (it was ours: off again)
	end
	SetCine(run.cineWasOn)
	Log(("put back: CineMode %s, pretend duels %s"):format(run.cineWasOn and "on" or "off",
		run.duelsWereOn and "left on" or "off"))
end

local function Finish()
	local before, hidden, after = run.reads["duelist targeted"], run.reads["Your Target hiding it"],
		run.reads["hide let go"]
	Verdict(before and before.plate, "your target's plate there, a duelist's")
	Verdict(Whole(before), "the duelist's plate whole before the hide")
	if hidden then
		-- (Proof the hide was on: else the next verdict proves nothing.)
		Verdict(hidden.held == true and (hidden.holdLevel or 1) <= 0.01,
			"Your Target holding your target's plate down to 0 (the hide that emptied it)")
		Verdict(Whole(hidden), "the duelist's plate still whole with Your Target hiding it (was: body 0, parts 0)")
	end
	Verdict(Whole(after), "the duelist's plate whole with the hide let go")
	PutBack()
	run = nil
	ns.TestPrompt("Duel target check DONE. /reload, then tell Claude 'check log'.", 30)
end

local function Steps()
	Read("duelist targeted")
	ns.TestPrompt("Duel target check: HANDS OFF, keep your target. Hiding your target's plate.", SETTLE)
	ns.testTargetHeldDown = true
	C_Timer.After(SETTLE, function()
		if not run then return end
		Read("Your Target hiding it")
		pcall(Screenshot)
		Log("screenshot taken with the hide on")
		C_Timer.After(0.5, function()
			if not run then return end
			ns.TestPrompt("Duel target check: hands off, letting the hide go.", SETTLE)
			ns.testTargetHeldDown = nil
			C_Timer.After(SETTLE, function()
				if not run then return end
				Read("hide let go")
				Finish()
			end)
		end)
	end)
end

function ns.DuelTargetTest()
	if run then
		PutBack()
		run = nil
		ns.TestPrompt("Duel target check stopped.", 3)
		return
	end
	if not (ns.ToggleDuelTest and ns.DuelTargetState) then
		ns.Print("/cine debug dueltarget: this copy has no pretend duels.")
		return
	end
	CinematicDB.duelTargetLog = {}
	run = { cineWasOn = CineOn(), duelsWereOn = false, reads = {} }
	Log(("start: interface %s, CineMode %s, in a fight %s, Duel Vision %s"):format(
		tostring(select(4, GetBuildInfo())), tostring(run.cineWasOn), tostring(InCombatLockdown()),
		tostring(ns.Setting and ns.Setting("duelPlates"))))
	SetCine(true)
	-- (Pretend duels on: turned on here, or already on from /cine debug duels test.)
	local on, why = ns.ToggleDuelTest(900)
	if not on then
		run.duelsWereOn = true
		_, why = ns.ToggleDuelTest(900)
	end
	Log("pretend duels on" .. (why and (", not shown now: " .. why) or ""))
	ns.TestPrompt("Duel target check: TARGET A PLAYER WITH A DUEL BORDER (no time limit; the command again stops it).",
		600)
	-- (Waits for your target to be a duelist whose plate has faded fully in.)
	run.ticker = C_Timer.NewTicker(0.5, function()
		if not run then return end
		local plate = TargetPlate()
		if plate and ns.DuelTargetState(plate) >= 1 then
			run.ticker:Cancel()
			run.ticker = nil
			C_Timer.After(1, function() if run then Steps() end end)
		end
	end)
end
