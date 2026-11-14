-- Personal Resources: your player frame and personal resource display, kept
-- up while you recover after a fight (Frames.lua's PORTRAIT_FRAMES), and
-- held back at the start of a fight until there's something to see. A fight
-- you go into with your power at rest (rage or runic power at 0, mana or
-- energy full...) brings up the bars only once it changes; the same for
-- health. Shown or not, the bars' rows on the Standard Frames page say when
-- they come up: this only holds back the fight's.
-- Health and power can be secret (WoW Forever, even out of combat), so rest
-- goes by their change events: they keep firing while either regenerates or
-- drains, and stop once it's back at rest.

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.personalResources = true   -- the page's switch: off, none of the below works
DEFAULTS.fightWaitPower = true      -- the resource bar waits for your power to change at a fight's start
DEFAULTS.fightWaitHealth = false    -- ...the health bar for your health
DEFAULTS.fightWaitPortrait = false  -- ...the player frame for either
DEFAULTS.fightWaitMana = true       -- ...our mana bar for your mana
DEFAULTS.drainWhenNotEmpty = true   -- "not full" also waits for rage, runic power and the like to drain to 0
DEFAULTS.notFullAfterFight = false  -- "not full" counts only within the Calm Timer of a fight (or a fall, resurrecting)
-- Show below, by row: kept up while its health or power is under this share
-- (0: never; 0.99: while it isn't full; 1: always). (An addon's power bar:
-- by addon, its support file.)
DEFAULTS.prHealthPlayer = 0.99      -- the player frame, health
DEFAULTS.prPowerPlayer = 0.99       -- ...power
DEFAULTS.prPetHealth = 0            -- the pet frame, its health
DEFAULTS.prHealthPrd = 0.99         -- the personal health bar
DEFAULTS.prPowerPrd = 0.99          -- the personal power bar
DEFAULTS.prPowerMana = 0.99         -- the Cine Mana Bar, your mana
DEFAULTS.prFadeRange = 0            -- ...fading in over this much above a share under 99% (0: all at once)
-- How much of each still shows while CineMode hides it (0: none).
DEFAULTS.prAlphaPlayer = 0          -- the player frame
DEFAULTS.prAlphaPet = 0             -- the pet frame
DEFAULTS.prAlphaPrd = 0             -- the personal health bar
DEFAULTS.prAlphaPrdPower = 0        -- the personal power bar
DEFAULTS.prAlphaMana = 0            -- the Cine Mana Bar
DEFAULTS.prdMana = true             -- a mana bar of ours under them, when mana isn't your power (PersonalMana.lua)
DEFAULTS.prdManaRecent = 3          -- ...only for this many seconds after you use mana (0: always)

-- Whether the page's switch is on (PersonalMana*.lua ask too).
function ns.PersonalResourcesOn(db)
	db = db or ns.db
	return db ~= nil and db.personalResources ~= false
end

-- No change for this long: at rest. (Regeneration ticks every 2 seconds.)
local REST_WINDOW = 3

local lastChange = { health = -math.huge, power = -math.huge, mana = -math.huge }
-- In a fight: whether each is still at rest since it started (nil: not in one).
local waiting

local watcher = CreateFrame("Frame")
watcher:RegisterUnitEvent("UNIT_HEALTH", "player")
watcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
watcher:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player") -- (a druid's form: a power of its own)
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event, _, powerToken)
	-- (Each fight looks afresh, on the first check in it.)
	if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		waiting = nil
		return
	end
	local kind = event == "UNIT_HEALTH" and "health" or "power"
	lastChange[kind] = GetTime()
	if waiting then
		waiting[kind] = false
	end
	-- (Mana apart, for the mana bar's row. A secret token: maybe mana.)
	if event == "UNIT_POWER_UPDATE" and (issecretvalue and issecretvalue(powerToken) or powerToken == "MANA") then
		lastChange.mana = GetTime()
		if waiting then
			waiting.mana = false
		end
	end
end)

local function RestedNow(kind, now)
	return now - lastChange[kind] >= REST_WINDOW
end

-- A row (Standard Frames' player, prd, prdpower) to hold back from the fight
-- now: its setting is on and what it shows has been at rest since the fight
-- started. Out of a fight (casting at an enemy, the pull), while it's at rest now.
local ROW_WAIT = {
	player = { "fightWaitPortrait", "health", "power" },
	prd = { "fightWaitHealth", "health" },
	prdpower = { "fightWaitPower", "power" },
	prdmana = { "fightWaitMana", "mana" },
}
function ns.FightHold(row)
	local wait = ROW_WAIT[row]
	if not wait or not ns.db[wait[1]] or not ns.PersonalResourcesOn() then
		return false
	end
	local now = GetTime()
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		if not waiting then
			waiting = { health = RestedNow("health", now), power = RestedNow("power", now), mana = RestedNow("mana", now) }
		end
		return waiting[wait[2]] and (not wait[3] or waiting[wait[3]])
	end
	waiting = nil
	return RestedNow(wait[2], now) and (not wait[3] or RestedNow(wait[3], now))
end

local function Readable(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

-- Show below, by row: a share of health or power (0-1). 0: never kept up by
-- it; 100%: always; 99% (NOT_FULL) and up: while it isn't full at all (rage
-- and the like: until drained, Rage counts until 0), only after fights with
-- Not full: only during Calm Timer, held back at the pull by Wait at pull;
-- under that: while it's under the share, any time.
local NOT_FULL = 0.99
local function Rule(value)
	value = tonumber(value) or 0
	if value <= 0 then return "off" end
	if value >= 1 then return "always" end
	if value >= NOT_FULL - 1e-6 then return "notfull" end
	return "below"
end
ns.PR_NOT_FULL = NOT_FULL

-- A share of a number and its max. nil: secret (or no max).
local function Share(value, max)
	if Readable(value) and Readable(max) and max > 0 then return value / max end
end

local function RestsAtZero(token)
	return type(token) == "string" and not (issecretvalue and issecretvalue(token)) and ns.EMPTY_AT_REST[token] or false
end

-- Rage, runic power and the others that rest at 0 (Frames.lua's
-- EMPTY_AT_REST) not drained yet. Secret: still changing.
local function PowerDraining()
	local _, token = UnitPowerType("player")
	if not RestsAtZero(token) then
		return false
	end
	local power = UnitPower("player")
	if Readable(power) then
		return power > 0
	end
	return not RestedNow("power", GetTime())
end

-- A frame's row on the page's table: player, prd (health), prdpower, prdmana,
-- or an addon's power bar ("addon").
local function RowOf(setting, entry)
	if ns.ADDON_POWER_BARS[entry.name] then return "addon" end
	return setting == "prdWhenNotFull" and entry.group or "player"
end
-- Its Show below settings, health and power (false: no such row). An
-- addon's power bar: its own, by addon (ns.AddPowerBarFrame).
local ROW_KEYS = {
	player = { "prHealthPlayer", "prPowerPlayer" },
	prd = { "prHealthPrd", false },
	prdpower = { false, "prPowerPrd" },
	prdmana = { false, "prPowerMana" },
	petframe = { "prPetHealth", false },
}
local function RowKeys(row, entry)
	if row == "addon" then
		return nil, "prPower" .. ns.ADDON_POWER_BARS[entry.name]
	end
	local keys = ROW_KEYS[row]
	if keys then return keys[1] or nil, keys[2] or nil end
end

-- The power a row's Show below goes by: the Cine Mana Bar's, your mana
-- (while it's up); the others', the power they show. nil: none, or secret.
local function RowPower(row, manaBar)
	if row == "prdmana" then
		if manaBar then return 0, "MANA" end
		return nil
	end
	local powerType, token = UnitPowerType("player")
	if not Readable(powerType) then return nil end
	return powerType, token
end

-- The lowest share of the powers a row goes by now, and the power type the
-- game won't say (secret; nil: none). Rage and the like aren't counted
-- (they rest at 0: Not full's drain). The player frame: your mana too while
-- it isn't your power (the Cine Mana Bar up for it).
local function PowerShareNow(row, manaBar)
	local powerType, token = RowPower(row, manaBar)
	local low, unknown
	if powerType ~= nil and not RestsAtZero(token) then
		local now = Share(UnitPower("player", powerType), UnitPowerMax("player", powerType))
		if now then low = now else unknown = powerType end
	end
	if row == "player" and manaBar and powerType ~= 0 then
		local mana = Share(UnitPower("player", 0), UnitPowerMax("player", 0))
		if mana then
			low = low and math.min(low, mana) or mana
		elseif unknown == nil then
			unknown = 0
		end
	end
	return low, unknown
end
-- Whether a row's power is under the share: true, false, or nil and the
-- power type when the game won't say.
local function PowerBelow(row, share, manaBar)
	local low, unknown = PowerShareNow(row, manaBar)
	if low and low < share then return true end
	if unknown ~= nil then return nil, unknown end
	return false
end

local function HealthShare(unit)
	return Share(UnitHealth(unit), UnitHealthMax(unit))
end

-- Mana not full, for the Cine Mana Bar's row. Secret: still changing.
local function ManaRecovering()
	local mana, maxMana = UnitPower("player", 0), UnitPowerMax("player", 0)
	if Readable(mana) and Readable(maxMana) then
		return maxMana > 0 and mana < maxMana
	end
	return not RestedNow("mana", GetTime())
end

-- Your health not full. Secret: still changing.
local function HealthNotFull()
	local health, maxHealth = UnitHealth("player"), UnitHealthMax("player")
	if Readable(health) and Readable(maxHealth) then
		return maxHealth > 0 and health < maxHealth
	end
	return not RestedNow("health", GetTime())
end

-- Your power not full: the Cine Mana Bar's row, your mana; rage, runic
-- power and the like (resting at 0), not drained yet (Rage counts until 0).
-- Secret: still changing.
local function PowerNotFull(db, row, manaBar)
	if row == "prdmana" then
		return manaBar and ManaRecovering() or false
	end
	local _, token = UnitPowerType("player")
	if RestsAtZero(token) then
		return db.drainWhenNotEmpty and PowerDraining() or false
	end
	local power, maxPower = UnitPower("player"), UnitPowerMax("player")
	if Readable(power) and Readable(maxPower) then
		return maxPower > 0 and power < maxPower
	end
	return not RestedNow("power", GetTime())
end

-- Whether a frame's Not full health the game won't say goes by the game's
-- curve (ThresholdSecret) rather than the guess from health's change events:
-- the guess comes and goes between them (up 3 seconds after each change),
-- so a frame not full but not regenerating (a ghost, slow ticks) flickered
-- up and down. Not the PRD's stand-in nor frames an addon's alpha hook
-- breaks on (NO_SECRET_ALPHA), nor with Not full: only during Calm Timer
-- (the curve can't tell a fight's aftermath).
local function HealthNotFullByCurve(db, entry)
	return not db.notFullAfterFight and UnitHealthPercent ~= nil and not HealthShare("player")
		and entry.name ~= "CinematicPersonalResource" and not ns.NO_SECRET_ALPHA[entry.name]
		and ns.HealthCurveReady() or false
end

-- Whether a row's power goes by Not full now though its share is under 99%:
-- rage and the like (they rest at 0, so "under" means nothing for them).
local function PowerRestsAtZero(row)
	if row == "prdmana" then return false end
	local _, token = UnitPowerType("player")
	return RestsAtZero(token)
end

-- Whether Not full may count now: not held to after a fight (Not full: only
-- during Calm Timer), nor back at a fight's start (Wait at pull).
local function NotFullAllowed(db, row, afterFight, fighting)
	if db.notFullAfterFight and not afterFight then return false end
	return not (fighting and ns.FightHold(row))
end

-- A row's rules now: health's and power's (Rule), and whether each goes by
-- Not full.
local function RowRules(db, row, healthKey, powerKey)
	local health = Rule(healthKey and db[healthKey])
	local power = Rule(powerKey and db[powerKey])
	local nfHealth = health == "notfull"
	local nfPower = power == "notfull" or power == "below" and PowerRestsAtZero(row)
	return health, power, nfHealth, nfPower
end

-- Whether your player frame, personal resource display or pet frame stays up
-- now in CineMode, shown like a fight's frames. setting: the frame's kind
-- (Frames.lua's PORTRAIT_FRAMES; nil for the pet frame); afterFight: within
-- the Calm Timer of a fight, fall or other health loss (Life Tap), or coming
-- back to life. Each row's share: the page's table (ROW_KEYS).
function ns.KeepYourFrameUp(setting, entry, afterFight, fighting)
	local db = ns.db
	if not ns.PersonalResourcesOn(db) then
		return false
	end
	local pet = ns.PET_FRAMES[entry.name]
	if not pet and not setting then
		return false
	end
	local row = pet and "petframe" or RowOf(setting, entry)
	local healthKey, powerKey = RowKeys(row, entry)
	local manaBar = ns.PersonalManaShown and ns.PersonalManaShown()
	local health, power, nfHealth, nfPower = RowRules(db, row, healthKey, powerKey)
	if health == "always" or power == "always" then
		return true
	end
	-- (Wait at pull: held back at a fight's start, whatever the share.)
	if fighting and not pet and ns.FightHold(row) then
		return false
	end
	if health == "below" then
		local share = HealthShare(pet and "pet" or "player")
		if share and share < db[healthKey] then return true end
	end
	if power == "below" and not nfPower and PowerBelow(row, db[powerKey], manaBar) then
		return true
	end
	-- (WoW Forever's personal health bar is your nameplate, faded through a
	-- stand-in whose alpha the plates work with: no curve for it. Secret
	-- health there: up while it isn't full, as at 99%.)
	if health == "below" and entry.name == "CinematicPersonalResource" and not HealthShare("player") then
		nfHealth = true
	end
	if not (nfHealth or nfPower) or not NotFullAllowed(db, row, afterFight, fighting) then
		return false
	end
	if pet then
		return nfHealth and ns.IsPetRecovering() or false
	end
	-- (Secret health: the game's curve sets the alpha instead, ThresholdSecret.)
	return nfHealth and not HealthNotFullByCurve(db, entry) and HealthNotFull()
		or nfPower and PowerNotFull(db, row, manaBar) or false
end

-- In a fight and held back at its start (Wait at pull), for the passes that
-- aren't told whether you're fighting.
local function HeldAtPull(row)
	return (InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))) and ns.FightHold(row)
end

-- Each frame's Opacity while hidden (the player frame's two rows: one frame).
local ALPHA_KEYS = { player = "prAlphaPlayer", prd = "prAlphaPrd", prdpower = "prAlphaPrdPower",
	prdmana = "prAlphaMana", petframe = "prAlphaPet" }
local function AlphaKey(row, entry)
	if row == "addon" then return "prAlpha" .. ns.ADDON_POWER_BARS[entry.name] end
	return ALPHA_KEYS[row]
end
-- How far into a share's Fade range a value is: 0 above it, 1 at the share.
local function Ramp(now, line, range)
	if not now or now >= line + range then return 0 end
	if range <= 0 or now <= line then return 1 end
	return (line + range - now) / range
end
local function FadeRange(db)
	return math.max(0, tonumber(db.prFadeRange) or 0)
end

-- How much of a frame shows while CineMode would hide it (KeepYourFrameUp
-- said no): its Opacity while hidden, or more as what it shows nears a
-- share under 99% (Fade range). 0: hidden. Readable values only: the
-- game's own secret ones go through the curve (ns.ThresholdSecret).
function ns.YourFrameLevel(setting, entry)
	local db = ns.db
	if not ns.PersonalResourcesOn(db) then return 0 end
	local pet = ns.PET_FRAMES[entry.name]
	if not pet and not setting then return 0 end
	local row = pet and "petframe" or RowOf(setting, entry)
	local floor = tonumber(db[AlphaKey(row, entry)]) or 0
	local range = FadeRange(db)
	if range <= 0 or not pet and HeldAtPull(row) then return floor end
	local healthKey, powerKey = RowKeys(row, entry)
	local health, power, _, nfPower = RowRules(db, row, healthKey, powerKey)
	local ramp = 0
	if health == "below" then
		ramp = math.max(ramp, Ramp(HealthShare(pet and "pet" or "player"), db[healthKey], range))
	end
	if power == "below" and not nfPower then
		local low = PowerShareNow(row, ns.PersonalManaShown and ns.PersonalManaShown())
		ramp = math.max(ramp, Ramp(low, db[powerKey], range))
	end
	-- (From the opacity up to full, as the game's curve does.)
	return floor + ramp * (1 - floor)
end

-- Health or power the game won't say (WoW Forever: health in fights, mana
-- even out of them, tested 2026-11-13): the game works out "under the
-- share" itself, through a curve (1 below the share, 0 above), and its
-- secret answer goes straight into the frame's alpha, as Vitals Vision does
-- with health (LowHealth.lua). nil: no curve API here.
-- (By share, fade range and opacity while hidden: 1 under the share, down
-- over the range to the opacity.)
local curves = {}
local function CurveAt(share, range, floor)
	range, floor = range or 0, floor or 0
	local key = ("%.4f:%.4f:%.4f"):format(share, range, floor)
	if curves[key] ~= nil then return curves[key] or nil end
	curves[key] = false
	if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum.LuaCurveType) then
		return nil
	end
	local ok, curve = pcall(C_CurveUtil.CreateCurve)
	if ok and curve then
		curve:SetType(Enum.LuaCurveType.Linear)
		curve:AddPoint(0, 1)
		if range > 0 then
			curve:AddPoint(share, 1)
			local top = math.min(1, share + range)
			if top < 1 then
				curve:AddPoint(top, floor)
				curve:AddPoint(1, floor)
			else
				curve:AddPoint(1, 1 - (1 - share) / range * (1 - floor))
			end
		else
			curve:AddPoint(math.max(0, share - 0.005), 1)
			curve:AddPoint(share, floor)
			curve:AddPoint(1, floor)
		end
		curves[key] = curve
	end
	return curves[key] or nil
end
function ns.ManaCurveReady()
	return CurveAt(0.5) ~= nil and UnitPowerPercent ~= nil
end
-- Not full's share on the game's health curve: just short of full.
local NOT_FULL_CURVE = 0.999
function ns.HealthCurveReady()
	return CurveAt(NOT_FULL_CURVE) ~= nil and UnitHealthPercent ~= nil
end
local function SecretHealthAlpha(frame, curve)
	frame:SetAlpha(UnitHealthPercent("player", true, curve))
end
local function SecretPowerAlpha(frame, curve, powerType)
	frame:SetAlpha(UnitPowerPercent("player", powerType, false, curve))
end

-- Whether a frame's Show below can't be told because the game won't say,
-- so the game sets its alpha (ns.SetThresholdSecretAlpha): what it goes by
-- ({ health = true } or { powerType = n }, and the share), or false. Health
-- first (a fight's). As KeepYourFrameUp picks the rows. (One table per row,
-- filled again: asked for every frame, every pass.)
local secretSpecs = {}
function ns.ThresholdSecret(setting, entry)
	local db = ns.db
	if not setting or ns.NO_SECRET_ALPHA[entry.name] or not ns.PersonalResourcesOn(db) then
		return false
	end
	local row = RowOf(setting, entry)
	if HeldAtPull(row) then return false end
	local healthKey, powerKey = RowKeys(row, entry)
	local manaBar = ns.PersonalManaShown and ns.PersonalManaShown()
	local health, power, nfHealth, nfPower = RowRules(db, row, healthKey, powerKey)
	local spec = secretSpecs[row]
	if not spec then
		spec = {}
		secretSpecs[row] = spec
	end
	spec.range, spec.floor = FadeRange(db), tonumber(db[AlphaKey(row, entry)]) or 0
	-- (Health and power both secret: one curve per frame, so the one that's
	-- changing now. Health at rest out of a fight is full (it regenerates
	-- till it is), so its curve would show nothing: power's then. 2026-11-13:
	-- health first always left the player frame deaf to low mana.)
	local healthSecret = health == "below" and UnitHealthPercent and not HealthShare("player")
		and CurveAt(db[healthKey], spec.range, spec.floor) and true or false
	-- (Not full the same way, at just short of full: KeepYourFrameUp leaves it
	-- to the curve, HealthNotFullByCurve.)
	local healthShare, healthRange = db[healthKey], spec.range
	if not healthSecret and nfHealth and HealthNotFullByCurve(db, entry)
		and CurveAt(NOT_FULL_CURVE, 0, spec.floor) then
		healthSecret, healthShare, healthRange = true, NOT_FULL_CURVE, 0
	end
	local powerType
	if power == "below" and not nfPower and UnitPowerPercent then
		local below, unknown = PowerBelow(row, db[powerKey], manaBar)
		if below == nil and CurveAt(db[powerKey], spec.range, spec.floor) then
			powerType = unknown
		end
	end
	-- (Health's curve while it changes, or changed after power last did:
	-- power's only once power is the one changing. Health resting between
	-- regen ticks swapped to a full mana's curve and back, so the frame went
	-- up and down (shares under 99% for both, 2026-11-14). A ghost's health
	-- doesn't regenerate and isn't full: health's.)
	local now = GetTime()
	if healthSecret and (powerType == nil or not RestedNow("health", now)
		or lastChange.health >= lastChange.power or ns.Flag(UnitIsDeadOrGhost("player"))) then
		spec.health, spec.powerType, spec.share, spec.range = true, nil, healthShare, healthRange
		return spec
	end
	if powerType ~= nil then
		spec.health, spec.powerType, spec.share = nil, powerType, db[powerKey]
		return spec
	end
	return false
end
function ns.SetThresholdSecretAlpha(frame, spec)
	local curve = spec and CurveAt(spec.share, spec.range, spec.floor)
	if not curve then return end
	local ok, err
	if spec.health then
		ok, err = pcall(SecretHealthAlpha, frame, curve)
	else
		ok, err = pcall(SecretPowerAlpha, frame, curve, spec.powerType)
	end
	ns.lowManaSecretError = not ok and tostring(err) or nil
end

-- (The low mana test's: /cine debug lowmana, LowManaTest.lua. Your mana
-- under the player frame's share now; the game's answer on a frame.)
function ns.LowManaNow()
	local share = ns.db.prPowerPlayer or 0
	if Rule(share) ~= "below" then return false end
	return (Share(UnitPower("player", 0), UnitPowerMax("player", 0)) or 1) < share
end
function ns.SetLowManaSecretAlpha(frame)
	ns.SetThresholdSecretAlpha(frame, { powerType = 0, share = ns.db.prPowerPlayer or 0 })
end

-- The same, in words, for the Why window (Why.lua): each of this page's
-- settings that can keep this frame up, and whether it is now, every one
-- that applies (overlapping too). add(state, text, settingKey): "on" keeping
-- it up, "off" set but not now. As KeepYourFrameUp works it out.
function ns.YourFrameWhy(setting, entry, afterFight, fighting, add)
	local db = ns.db
	local page = L["Health & Resources"]
	local pet = ns.PET_FRAMES[entry.name] or false
	if not pet and not setting then return end
	local row = pet and "petframe" or RowOf(setting, entry)
	local healthKey, powerKey = RowKeys(row, entry)
	local manaBar = ns.PersonalManaShown and ns.PersonalManaShown()
	local health, power, nfHealth, nfPower = RowRules(db, row, healthKey, powerKey)
	if health == "off" and power == "off" then return end
	if not ns.PersonalResourcesOn(db) then
		add("off", L["The %s page is off, so its settings don't keep this up"]:format(page), "personalResources")
		return
	end
	local function Percent(key) return ("%d%%"):format(math.floor(db[key] * 100 + 0.5)) end
	if health == "always" then
		add("on", L["Kept up always (Show below health: Always)"], healthKey)
	end
	if power == "always" then
		add("on", L["Kept up always (Show below power: Always)"], powerKey)
	end
	if health == "always" or power == "always" then return end
	if fighting and not pet and ns.FightHold(row) then
		add("off", L["Held back at the fight's start while you're at rest (Wait at pull)"],
			health ~= "off" and healthKey or powerKey)
		return
	end
	if health == "below" then
		local share = HealthShare(pet and "pet" or "player")
		local text
		if share and share < db[healthKey] then
			text = pet and L["Your pet's health is under %s (Show below)"] or L["Your health is under %s (Show below)"]
			add("on", text:format(Percent(healthKey)), healthKey)
		elseif share or pet then
			text = pet and L["Shows while your pet's health is under %s (Show below)"]
				or L["Shows while your health is under %s (Show below)"]
			add("off", text:format(Percent(healthKey)), healthKey)
		else
			add("off", L["Shows while your health is under %s (Show below): the game won't say your health, so it " ..
				"sets the opacity itself"]:format(Percent(healthKey)), healthKey)
		end
	end
	if power == "below" and not nfPower then
		local below = PowerBelow(row, db[powerKey], manaBar)
		if below then
			add("on", L["Your power is under %s (Show below)"]:format(Percent(powerKey)), powerKey)
		elseif below == false then
			add("off", L["Shows while your power is under %s (Show below)"]:format(Percent(powerKey)), powerKey)
		else
			add("off", L["Shows while your power is under %s (Show below): the game won't say your power, so it " ..
				"sets the opacity itself"]:format(Percent(powerKey)), powerKey)
		end
	end
	if not (nfHealth or nfPower) then return end
	local key = nfHealth and healthKey or powerKey
	if db.notFullAfterFight and not afterFight then
		add("off", L["Not full counts only after a fight, a fall, Life Tap or resurrecting (Not full: only during Calm Timer)"],
			"notFullAfterFight")
		return
	end
	if fighting and not pet and ns.FightHold(row) then
		add("off", L["Held back at the fight's start while you're at rest (Wait at pull)"], key)
		return
	end
	local shown = false
	if nfHealth then
		if pet and ns.IsPetRecovering() then
			add("on", L["Your pet's health isn't full yet (Show below: < 100%)"], healthKey)
			shown = true
		elseif not pet and HealthNotFullByCurve(db, entry) then
			add("off", L["Shows while your health isn't full (Show below: < 100%): the game won't say your health, so it " ..
				"sets the opacity itself"], healthKey)
			shown = true
		elseif not pet and HealthNotFull() then
			add("on", L["Your health isn't full yet (Show below: < 100%)"], healthKey)
			shown = true
		end
	end
	if nfPower and PowerNotFull(db, row, manaBar) then
		add("on", row == "prdmana" and L["Your mana isn't full yet (Show below: < 100%)"]
			or L["Your power isn't full yet, or your rage or the like isn't drained (Show below: < 100%)"], powerKey)
		shown = true
	end
	if not shown then
		add("off", pet and L["Stays up while your pet's health isn't full (Show below: < 100%): it is"]
			or L["Stays up while its health or power isn't full (Show below: < 100%): it is"], key)
	end
end

-- The page.
function ns.CreatePersonalResourcesPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Health & Resources"])
	title:SetPoint("TOPLEFT", 16, -16)
	local hasDisplay = _G.CinematicPersonalPower ~= nil
	local intro = kit.PageIntro(content, title,
		L["Your player frame, pet frame and personal resource display in CineMode: kept up while your health " ..
		"or power is under each row's share (as Heal Vision's roles are), and held back at the start of a fight until there's something " ..
		"to see. Hover a row or column for what it does. When they come up at all (always, in fights, in places) " ..
		"is their rows' on the HUD page."])
	-- Their look: the Style hub's Personal Resource Style page (PersonalStyle.lua).
	local styleLink = ns.StyleLink(content, title, "Personal Style", L["Opens the Personal Resource Style page: how the bars look."], kit.Tooltip)
	ns.FramesLink(content, title, "prd", styleLink)
	local switch = kit.PageSwitch(content, "personalResources", L["Enable Page"],
		L["On: your player frame, pet frame and personal resource display stay up or wait as this page says, " ..
		"and its mana bar and remaining mana text show. Off: none of it; they come up only as their HUD " ..
		"rows say."], intro, function()
		if ns.UpdatePersonalMana then ns.UpdatePersonalMana() end
		if ns.RefreshPersonalStyle then ns.RefreshPersonalStyle() end
		if ns.UpdateManaCost then ns.UpdateManaCost() end
	end)
	-- Two tabs (Options.lua's ns.PageTabsBelow): the page's settings, and Addon Frame Links.
	local _, _, TabsShown, AdoptTab = ns.PageTabsBelow(content, switch, {
		{ L["Settings"], L["When your player frame, pet frame and personal resource display stay up or wait."] },
		{ L["Frame Links"], L["Which supported addon's frames stand in for these bars."] },
	}, "Personal Resources/page", 2, "prd", 1)
	local stack = kit.Stack(switch, "check")
	local function Tick(key, label, tip, enabledBy)
		local check = stack:Add(kit.Check(content, key, label, tip), "check")
		if enabledBy then kit.GreyUnless(check, enabledBy) end
		return check
	end

	-- Keep up: a row per bar, kept up while what it shows is under its share
	-- (as Heal Vision's roles are). A cell a row can't have is left empty; a
	-- frame this client hasn't, no row.
	stack:Header(content, L["Keep up"])
	local function Fights(db) return db.stayInCombat end
	local COLUMNS = {
		{ L["Show below"], L["It stays up while what it shows (health, or your power) is under this. < 100%: " ..
			"while it isn't full at all, even by a hair (rage and the like: until they're back to 0, Rage counts until 0); " ..
			"only after fights with the tick under this table. Lower: only while it's under this, any time: drinking, " ..
			"or saving mana for the pull. Always: always up. Off: never kept up by it. Wait at pull holds either back " ..
			"at a fight's start."] },
		{ L["Opacity while hidden"], L["How much of it still shows while CineMode hides it. 0%: hidden completely."] },
		{ L["Wait at pull"], L["At a fight's start, it comes up only once your health or power changes: your " ..
			"first cast, your first hit. Only while fights bring frames up (In combat on the CineMode page)."] },
		{ L["Mana text"], L["While you cast a spell that costs mana, your mana's numbers on the bar show what " ..
			"you'll have once the cast is done, paler. The amount and the percent, whichever the game shows there " ..
			"(its Status Text setting); with the game's numbers off, the amount in the middle of the bar."] },
	}
	-- (The mana text's: redrawn as it's ticked, PersonalManaCost.lua.)
	local function Redraw()
		if ns.UpdateManaCost then ns.UpdateManaCost() end
	end
	-- Your power's name for the power rows: Mana, Rage, Energy... (as you
	-- are when the page shows: a druid's form changes it).
	local function PowerName()
		local _, token = UnitPowerType("player")
		local name = type(token) == "string" and not (issecretvalue and issecretvalue(token)) and _G[token]
		return type(name) == "string" and name ~= "" and name or L["Power"]
	end
	-- { label (a function: named by your power), tip, share key, Wait at pull key, Mana text key,
	-- Opacity while hidden key (a frame's first row) }
	local rows = {
		{ L["Player Frame: Health"], L["Your player frame, by your health."], "prHealthPlayer", "fightWaitPortrait", nil, "prAlphaPlayer" },
		{ function() return L["Player Frame: %s"]:format(PowerName()) end,
			L["Your player frame, by your power (mana, rage, energy...). One frame with the row above: up when " ..
			"either says so."], "prPowerPlayer", nil, "manaAfterPortrait" },
	}
	if _G.PetFrame then
		rows[#rows + 1] = { L["Pet Frame: Health"], L["Your pet frame, by your pet's health."], "prPetHealth", nil, nil,
			"prAlphaPet" }
	end
	if hasDisplay then
		rows[#rows + 1] = { L["PRD: Health"], L["The game's personal resource display (PRD): its health bar."],
			"prHealthPrd", "fightWaitHealth", nil, "prAlphaPrd" }
		rows[#rows + 1] = { function() return L["PRD: %s"]:format(PowerName()) end,
			L["The game's personal resource display (PRD): its power bar (mana, rage, energy...)."],
			"prPowerPrd", "fightWaitPower", "manaAfterDisplay", "prAlphaPrdPower" }
	end
	if ns.PERSONAL_MANA then
		rows[#rows + 1] = { L["Cine Mana Bar"], L["Ours, under the PRD's power bar, while mana isn't your power " ..
			"(forms, Shadow, Elemental): by your mana."], "prPowerMana", "fightWaitMana", nil, "prAlphaMana" }
	end
	-- (Other addons' power bars standing in for these: their own rows, by addon.)
	for _, bar in ipairs(ns.ADDON_POWER_ROWS or {}) do
		if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(bar.addon) then
			rows[#rows + 1] = { L["Power bar (%s)"]:format(bar.addon), bar.tip, "prPower" .. bar.addon, nil, nil,
				"prAlpha" .. bar.addon }
		end
	end
	-- (Columns: Show below, Opacity while hidden, Wait at pull, Mana text.)
	local LABEL_W, ROW_H, HEAD_H = 170, 26, 22
	local WIDTHS = { 90, 130, 90, 90 }
	local left, total = {}, LABEL_W
	for c, width in ipairs(WIDTHS) do
		left[c] = total
		total = total + width
	end
	local function CenterX(c) return left[c] + WIDTHS[c] / 2 end
	local grid = CreateFrame("Frame", nil, content)
	grid:SetSize(total, HEAD_H + (#rows + 1) * ROW_H + 8)
	for c, column in ipairs(COLUMNS) do
		local head = CreateFrame("Frame", nil, grid)
		head:SetSize(WIDTHS[c], 20)
		head:SetPoint("BOTTOMLEFT", grid, "TOPLEFT", left[c], -HEAD_H)
		local text = kit.Label(head, "GameFontNormalSmall", column[1])
		text:SetPoint("CENTER")
		text.searchSkip = true
		kit.Tooltip(head, column[2])
	end
	-- A % box in a column (as Heal Vision's).
	local function Box(c, y, key, label, tip)
		local line = kit.BoxLine(grid)
		local box = line:Box("", key, 0, 100, 1, "%d%%", 100, tip, nil, 40)
		line:SetPoint("CENTER", grid, "TOPLEFT", CenterX(c), y - ROW_H / 2)
		box.searchLabel = label
		return box
	end
	-- A Show below box (< 50%, < 100%: not full, Off, Always): Options.lua's ShareBox.
	local function ShareBox(c, y, key, label, tip)
		local line = kit.BoxLine(grid)
		local box = line:ShareBox(key, tip, nil, NOT_FULL)
		line:SetPoint("CENTER", grid, "TOPLEFT", CenterX(c), y - ROW_H / 2)
		box.searchLabel = label
		return box
	end
	local named = {} -- { [label] = function } (the power rows: named again as the page shows)
	for r, row in ipairs(rows) do
		local y = -HEAD_H - (r - 1) * ROW_H
		local name = CreateFrame("Frame", nil, grid)
		name:SetSize(LABEL_W, ROW_H)
		name:SetPoint("TOPLEFT", 0, y)
		local label = type(row[1]) == "function" and row[1]() or row[1]
		local text = kit.Label(name, "GameFontHighlight", label)
		text:SetPoint("LEFT")
		text.searchSkip = true
		if type(row[1]) == "function" then named[text] = row[1] end
		if row[2] then kit.Tooltip(name, row[2]) end
		ShareBox(1, y, row[3], ("%s: %s"):format(label, COLUMNS[1][1]),
			("%s: %s. %s"):format(label, COLUMNS[1][1], COLUMNS[1][2]))
		if row[6] then
			Box(2, y, row[6], ("%s: %s"):format(label, COLUMNS[2][1]),
				("%s: %s. %s"):format(label, COLUMNS[2][1], COLUMNS[2][2]))
		end
		for c = 3, 4 do
			local key = row[c + 1]
			if key then
				local column = COLUMNS[c]
				local cell = kit.Check(grid, key, "", ("%s: %s. %s"):format(label, column[1], column[2]),
					c == 4 and function(value)
						ns.GetDB()[key] = value
						Redraw()
					end or nil)
				cell:SetPoint("CENTER", grid, "TOPLEFT", CenterX(c), y - ROW_H / 2)
				cell.searchLabel = ("%s: %s"):format(label, column[1])
				if c == 3 then kit.GreyUnless(cell, Fights) end
			end
		end
	end
	-- Fade range: one for every row, under Show below.
	do
		local y = -HEAD_H - #rows * ROW_H - 8
		local name = CreateFrame("Frame", nil, grid)
		name:SetSize(LABEL_W, ROW_H)
		name:SetPoint("TOPLEFT", 0, y)
		local text = kit.Label(name, "GameFontHighlight", L["Fade range"])
		text:SetPoint("LEFT")
		text.searchSkip = true
		local tip = L["Each row set to a share (not < 100%, Always or Off) fades in gradually as what it shows nears its share, instead of " ..
			"popping in all at once. With Show below < 30% and 5% here, it starts showing at 35% and is fully up " ..
			"at 30%. 0%: at the share, all at once."]
		kit.Tooltip(name, tip)
		Box(1, y, "prFadeRange", L["Fade range"], tip)
	end
	stack:Add(grid, "label")
	Tick("notFullAfterFight", L["Not full: only during Calm Timer"],
		L["Ticked, a row at < 100% (while it isn't full) comes up only after a fight, a fall, a spell that costs you " ..
		"health (Life Tap) or resurrecting, until the Calm Timer runs out: casting or drinking in town brings " ..
		"nothing up. Unticked, it works any time. Lower shares always work any time."])
	Tick("drainWhenNotEmpty", L["Rage counts until 0"],
		L["Rage, runic power and the other resources that drain away out of combat: a power row keeps its " ..
		"frame up until they're back to 0. Unticked, they never keep it up."])

	-- Mana under the power bar, when it isn't your power (PersonalMana.lua; its
	-- look: the Style hub's Personal Resource Style page).
	if ns.PERSONAL_MANA then
		stack:Header(content, L["Cine Mana Bar"])
		local function Update()
			if ns.UpdatePersonalMana then ns.UpdatePersonalMana() end
		end
		stack:Add(kit.Check(content, "prdMana", L["Show Cine Mana Bar"],
			L["The game shows only your main power under your character: Maelstrom, Insanity, Astral Power, " ..
			"rage or energy in a form. Ticked, your mana gets a bar of its own under it. When it comes up is the " ..
			"Cine Mana Bar row on the HUD page."], function(value)
			ns.GetDB().prdMana = value
			if ns.RefreshPersonalStyle then ns.RefreshPersonalStyle() end -- (shown and dressed)
			kit.Refresh()
		end), "check")
		local recentLine = kit.BoxLine(content)
		stack:Add(recentLine, "label", 20)
		local recentBox = recentLine:Box(L["After using mana for"], "prdManaRecent", 0, 60, 1, "%d", 1,
			L["The mana bar shows for this many seconds after you spend mana, then fades out until you spend " ..
			"some again. 0: whenever it's up."], Update, 40, L["sec"])
		kit.GreyUnless(recentBox, function(db) return db.prdMana end)
		-- (And after the page's Reset, or a profile loaded: shown as the settings are now.)
		local updater = CreateFrame("Frame", nil, content)
		updater.Refresh = Update
		kit.AddControl(updater)
	end

	-- (And after the page's Reset, or a profile loaded: drawn as the settings are now.)
	local redrawer = CreateFrame("Frame", nil, content)
	redrawer.Refresh = Redraw -- (the grid's Mana text)
	kit.AddControl(redrawer)

	AdoptTab(switch) -- (everything above onto the Settings tab)

	canvas:SetScript("OnShow", kit.PageShown(function()
		for text, Name in pairs(named) do text:SetText(Name()) end
		kit.Refresh()
		TabsShown()
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Personal Resources", L["Health & Resources"])
end
