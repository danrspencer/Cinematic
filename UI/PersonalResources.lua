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

local ADDON_NAME, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.personalResources = true   -- the page's switch: off, none of the below works
DEFAULTS.fightWaitPull = true       -- Wait at pull: each bar waits for what it shows to change at a fight's start
DEFAULTS.drainWhenNotEmpty = true   -- "not full" also waits for rage, runic power and the like to drain to 0
-- Keep up, by row: kept up while its health or power is under a share, one
-- per column: In combat (the key itself), After combat (key .. "Calm": the
-- Calm Timer after a fight, a fall, Life Tap or resurrecting) and Out of
-- combat (key .. "Always": neither; named so before 2026-11-15, when it
-- counted any time). One column at a time. 0: never; 0.99: while it isn't
-- full; 1: always. A column linked (key .. "LinkCalm", key .. "LinkAlways"; nil:
-- linked) goes by the one to its left. (An addon's power bar: by addon, its
-- support file.)
-- (A row's three columns, and their links: linked where they match.)
function ns.KeepUpDefaults(key, combat, calm, always)
	if calm == nil then calm = combat end
	if always == nil then always = calm end
	DEFAULTS[key], DEFAULTS[key .. "Calm"], DEFAULTS[key .. "Always"] = combat, calm, always
	DEFAULTS[key .. "LinkCalm"], DEFAULTS[key .. "LinkAlways"] = calm == combat, always == calm
end
-- (A profile's: a row's three columns through its set, linked where they match.)
function ns.SetKeepUp(set, key, combat, calm, always)
	if calm == nil then calm = combat end
	if always == nil then always = calm end
	set(key, combat)
	set(key .. "Calm", calm)
	set(key .. "Always", always)
	set(key .. "LinkCalm", calm == combat)
	set(key .. "LinkAlways", always == calm)
end
-- Every profile's rows (user's pick, 2026-11-15): always in fights, while not
-- full after combat, and out of combat under 95% (health) or 50% (power).
ns.KEEP_UP_HEALTH = { 1, 0.99, 0.95 }
ns.KEEP_UP_POWER = { 1, 0.99, 0.5 }
ns.KeepUpDefaults("prHealthPlayer", unpack(ns.KEEP_UP_HEALTH)) -- the player frame, health
ns.KeepUpDefaults("prPowerPlayer", unpack(ns.KEEP_UP_POWER))   -- ...power
ns.KeepUpDefaults("prPetHealth", unpack(ns.KEEP_UP_POWER))     -- the pet frame, its health (50% out of combat)
ns.KeepUpDefaults("prHealthPrd", unpack(ns.KEEP_UP_HEALTH))    -- the personal health bar (as the player frame's)
ns.KeepUpDefaults("prPowerPrd", unpack(ns.KEEP_UP_POWER))      -- the personal power bar
ns.KeepUpDefaults("prPowerMana", unpack(ns.KEEP_UP_POWER))     -- the Cine Mana Bar, your mana
-- Fade to, the health rows' (player frame, PRD): under the row's share now
-- the frame fades in as your health drops, fully up at this share. 0: none,
-- fully up as soon as it's under. (Vitals Vision's Health bars till
-- 2026-11-17: two settings for one bar, Keep up's always won.)
DEFAULTS.prHealthPlayerFade = 0
DEFAULTS.prHealthPrdFade = 0
-- (Other addons' power bars, their support files' rows, loaded before this: as ours.)
for _, bar in ipairs(ns.ADDON_POWER_ROWS or {}) do
	ns.KeepUpDefaults("prPower" .. bar.addon, unpack(ns.KEEP_UP_POWER))
end
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
-- now: Wait at pull is on (one for every row since 2026-11-15) and what it
-- shows has been at rest since the fight started. Out of a fight (casting at
-- an enemy, the pull), while it's at rest now.
local ROW_WAIT = {
	player = { "fightWaitPull", "health", "power" },
	prd = { "fightWaitPull", "health" },
	prdpower = { "fightWaitPull", "power" },
	prdmana = { "fightWaitPull", "mana" },
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

-- Keep up, by row: a share of health or power (0-1). 0: never kept up by
-- it; 100%: always; 99% (NOT_FULL) and up: while it isn't full at all (rage
-- and the like: until drained, Rage counts until 0); under that: while it's
-- under the share. Held back at the pull by Wait at pull.
local NOT_FULL = 0.99
local function Rule(value)
	value = tonumber(value) or 0
	if value <= 0 then return "off" end
	if value >= 1 then return "always" end
	if value >= NOT_FULL - 1e-6 then return "notfull" end
	return "below"
end
ns.PR_NOT_FULL = NOT_FULL

-- A row's columns: 1 In combat, 2 After combat, 3 Out of combat. The setting a
-- column goes by: its own, or (linked) the one to its left's.
local COLUMN_SUFFIX = { "", "Calm", "Always" }
local LINK_SUFFIX = { nil, "LinkCalm", "LinkAlways" }
local function ColumnKey(db, key, col)
	if col == 3 and db[key .. "LinkAlways"] ~= false then col = 2 end
	if col == 2 and db[key .. "LinkCalm"] ~= false then col = 1 end
	return key .. COLUMN_SUFFIX[col]
end
local function ColumnShare(db, key, col)
	return tonumber(db[ColumnKey(db, key, col)]) or 0
end
ns.PrColumnKey, ns.PrColumnShare = ColumnKey, ColumnShare
ns.PR_COLUMN_SUFFIX, ns.PR_LINK_SUFFIX = COLUMN_SUFFIX, LINK_SUFFIX
-- In a fight now, and in the after-combat window (Frames.lua's
-- ns.AfterFightCause), for the passes that aren't told.
local function PhaseNow()
	local fighting = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	return fighting, not fighting and ns.AfterFightCause ~= nil and ns.AfterFightCause() ~= nil
end
-- A row's share now (nil: no such key): its column for now's, In combat
-- in a fight, After combat after one, else Out of combat. Also which
-- column.
local function ShareNow(db, key, fighting, afterFight)
	if not key then return nil end
	local col = fighting and 1 or afterFight and 2 or 3
	return ColumnShare(db, key, col), col
end

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
-- breaks on (NO_SECRET_ALPHA). (Only while its column for now says so:
-- each pass asks again.)
local function HealthNotFullByCurve(entry)
	return UnitHealthPercent ~= nil and not HealthShare("player")
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

-- A row's rules now, by its shares now (ShareNow): health's and power's
-- (Rule), and whether each goes by Not full.
local function RowRules(row, healthShare, powerShare)
	local health = Rule(healthShare)
	local power = Rule(powerShare)
	local nfHealth = health == "notfull"
	local nfPower = power == "notfull" or power == "below" and PowerRestsAtZero(row)
	return health, power, nfHealth, nfPower
end

-- A health row's Fade to under its share now: the share it fades in from
-- and the one it's fully up at, or nil (no fade: not a "below" share, Fade
-- to Off, or at or over the share).
local function FadeRange(db, healthKey, hShare)
	if not healthKey or Rule(hShare) ~= "below" then return nil end
	local full = tonumber(db[healthKey .. "Fade"]) or 0
	if full <= 0 or full >= hShare then return nil end
	return hShare, full
end

-- Whether your player frame, personal resource display or pet frame stays up
-- now in CineMode, shown like a fight's frames. setting: the frame's kind
-- (Frames.lua's PORTRAIT_FRAMES; nil for the pet frame); afterFight: within
-- the Calm Timer of a fight, fall or other health loss (Life Tap), or coming
-- back to life. Each row's share: the page's table (ROW_KEYS).
-- (Dead or a ghost: no personal resource display, whatever its rows say.
-- Your health isn't full then, so Not full kept it up, empty bars and all.)
local function PrdWhileDead(setting)
	return setting == "prdWhenNotFull" and ns.Flag(UnitIsDeadOrGhost("player")) and true or false
end
function ns.KeepYourFrameUp(setting, entry, afterFight, fighting)
	local db = ns.db
	if not ns.PersonalResourcesOn(db) or PrdWhileDead(setting) then
		return false
	end
	local pet = ns.PET_FRAMES[entry.name]
	if not pet and not setting then
		return false
	end
	local row = pet and "petframe" or RowOf(setting, entry)
	local healthKey, powerKey = RowKeys(row, entry)
	local manaBar = ns.PersonalManaShown and ns.PersonalManaShown()
	local hShare, pShare = ShareNow(db, healthKey, fighting, afterFight), ShareNow(db, powerKey, fighting, afterFight)
	local health, power, nfHealth, nfPower = RowRules(row, hShare, pShare)
	if health == "always" or power == "always" then
		return true
	end
	-- (Wait at pull: held back at a fight's start, whatever the share.)
	if fighting and not pet and ns.FightHold(row) then
		return false
	end
	if health == "below" then
		local share = HealthShare(pet and "pet" or "player")
		-- (Fade to: fully up only at it; above, ns.KeepUpFadeLevel's share.)
		local _, full = FadeRange(db, healthKey, hShare)
		if share and share < (full or hShare) then return true end
	end
	if power == "below" and not nfPower and PowerBelow(row, pShare, manaBar) then
		return true
	end
	-- (WoW Forever's personal health bar is your nameplate, faded through a
	-- stand-in whose alpha the plates work with: no curve for it. Secret
	-- health there: up while it isn't full, as at 99%.)
	if health == "below" and entry.name == "CinematicPersonalResource" and not HealthShare("player") then
		nfHealth = true
	end
	if not (nfHealth or nfPower) then
		return false
	end
	if pet then
		return nfHealth and ns.IsPetRecovering() or false
	end
	-- (Secret health: the game's curve sets the alpha instead, ThresholdSecret.)
	return nfHealth and not HealthNotFullByCurve(entry) and HealthNotFull()
		or nfPower and PowerNotFull(db, row, manaBar) or false
end

-- In a fight and held back at its start (Wait at pull), for the passes that
-- aren't told whether you're fighting.
local function HeldAtPull(row)
	return (InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))) and ns.FightHold(row)
end

-- Fade to (FadeRange): how far up (0-1) your player frame or PRD's health
-- bar is while CineMode would hide it (KeepYourFrameUp said no), by your
-- health between its row's share and Fade to. nil: no fade now (or secret
-- health: ThresholdSecret's curve does it). Frames.lua asks, each tick.
function ns.KeepUpFadeLevel(setting, entry, afterFight, fighting)
	local db = ns.db
	if not setting or not ns.PersonalResourcesOn(db) or ns.Flag(UnitIsDeadOrGhost("player")) then return nil end
	local row = RowOf(setting, entry)
	if row ~= "player" and row ~= "prd" then return nil end
	local healthKey = RowKeys(row, entry)
	local start, full = FadeRange(db, healthKey, ShareNow(db, healthKey, fighting, afterFight))
	if not start or (fighting and ns.FightHold(row)) then return nil end
	local share = HealthShare("player")
	if not share or share >= start then return nil end
	return math.min(1, (start - share) / (start - full))
end

-- How much of a frame shows while CineMode would hide it (KeepYourFrameUp
-- said no): none. (Opacity while hidden and Fade range: gone 2026-11-15,
-- for the In combat / After combat / Out of combat columns.)
function ns.YourFrameLevel()
	return 0
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
	if not setting or ns.NO_SECRET_ALPHA[entry.name] or not ns.PersonalResourcesOn(db) or PrdWhileDead(setting) then
		return false
	end
	local row = RowOf(setting, entry)
	if HeldAtPull(row) then return false end
	local healthKey, powerKey = RowKeys(row, entry)
	local manaBar = ns.PersonalManaShown and ns.PersonalManaShown()
	local fighting, afterFight = PhaseNow()
	local hShare, pShare = ShareNow(db, healthKey, fighting, afterFight), ShareNow(db, powerKey, fighting, afterFight)
	local health, power, nfHealth, nfPower = RowRules(row, hShare, pShare)
	local spec = secretSpecs[row]
	if not spec then
		spec = {}
		secretSpecs[row] = spec
	end
	spec.range, spec.floor = 0, 0
	-- (Health and power both secret: one curve per frame, so the one that's
	-- changing now. Health at rest out of a fight is full (it regenerates
	-- till it is), so its curve would show nothing: power's then. 2026-11-13:
	-- health first always left the player frame deaf to low mana.)
	-- (Fade to: fully up under it, fading out to none at the share.)
	local fadeStart, fadeFull = FadeRange(db, healthKey, hShare)
	local healthShare, healthRange = hShare, spec.range
	if fadeStart then healthShare, healthRange = fadeFull, fadeStart - fadeFull end
	local healthSecret = health == "below" and UnitHealthPercent and not HealthShare("player")
		and CurveAt(healthShare, healthRange, spec.floor) and true or false
	-- (Not full the same way, at just short of full: KeepYourFrameUp leaves it
	-- to the curve, HealthNotFullByCurve.)
	if not healthSecret and nfHealth and HealthNotFullByCurve(entry)
		and CurveAt(NOT_FULL_CURVE, 0, spec.floor) then
		healthSecret, healthShare, healthRange = true, NOT_FULL_CURVE, 0
	end
	local powerType
	if power == "below" and not nfPower and UnitPowerPercent then
		local below, unknown = PowerBelow(row, pShare, manaBar)
		if below == nil and CurveAt(pShare, spec.range, spec.floor) then
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
		spec.health, spec.powerType, spec.share = nil, powerType, pShare
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
local function PlayerPowerShareNow()
	local fighting, afterFight = PhaseNow()
	return ShareNow(ns.db, "prPowerPlayer", fighting, afterFight) or 0
end
function ns.LowManaNow()
	local share = PlayerPowerShareNow()
	if Rule(share) ~= "below" then return false end
	return (Share(UnitPower("player", 0), UnitPowerMax("player", 0)) or 1) < share
end
function ns.SetLowManaSecretAlpha(frame)
	ns.SetThresholdSecretAlpha(frame, { powerType = 0, share = PlayerPowerShareNow() })
end

-- The Why line for a row going by its After combat column now: what opened
-- the window (Frames.lua's ns.AfterFightCause).
local function CalmCauseText()
	local cause, ago = nil, nil
	if ns.AfterFightCause then cause, ago = ns.AfterFightCause() end
	local text
	if cause == "resurrect" then
		return L["In Calm Timer now: you came back to life, until your health and power are full"]
	elseif cause == "fall" then
		text = L["In Calm Timer now: you fell, %d sec ago (till the Calm Timer runs out)"]
	elseif cause == "lifetap" then
		text = L["In Calm Timer now: you cast a spell that costs health, %d sec ago (till the Calm Timer runs out)"]
	elseif cause == "health" then
		text = L["In Calm Timer now: you lost health out of a fight, %d sec ago (till the Calm Timer runs out)"]
	elseif cause == "fight" then
		text = L["In Calm Timer now: your last fight, %d sec ago (till the Calm Timer runs out)"]
	else
		return L["In Calm Timer now: after a fight, a fall, Life Tap or resurrecting"]
	end
	return text:format(math.floor((ago or 0) + 0.5))
end

-- A share in words, as the page's boxes show it: Off, < 30%, < 100%, Always.
local function ShareText(share)
	share = tonumber(share) or 0
	if share <= 0 then return L["Off"] end
	if share >= 1 then return L["Always"] end
	if share >= NOT_FULL - 1e-6 then return "< 100%" end
	return ("< %d%%"):format(math.floor(share * 100 + 0.5))
end
local COLUMN_NAMES = { L["In combat"], L["In Calm Timer"], L["Out of combat"] }
local COLUMN_WHEN = { L["In a fight it goes by %s for %s"], L["In the Calm Timer it goes by %s for %s"],
	L["Out of combat it goes by %s for %s"] }

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
	local hShare, hCol = ShareNow(db, healthKey, fighting, afterFight)
	local pShare, pCol = ShareNow(db, powerKey, fighting, afterFight)
	local health, power, nfHealth, nfPower = RowRules(row, hShare, pShare)
	if not ns.PersonalResourcesOn(db) then
		if health ~= "off" or power ~= "off" then
			add("off", L["The %s page is off, so its settings don't keep this up"]:format(page), "personalResources")
		end
		return
	end
	-- (Each line links to the column it goes by: its own setting, or the one
	-- it's linked to.)
	local hKey = healthKey and ColumnKey(db, healthKey, hCol)
	local pKey = powerKey and ColumnKey(db, powerKey, pCol)
	local function Tag(col, share) return ("%s: %s"):format(COLUMN_NAMES[col], ShareText(share)) end
	-- (A column not in play now that would keep it up more: when it would.)
	local nowCol = fighting and 1 or afterFight and 2 or 3
	for _, key in ipairs({ healthKey or false, powerKey or false }) do
		if key then
			local shareNow = key == healthKey and hShare or pShare
			for col = 1, 3 do
				local share = ColumnShare(db, key, col)
				if col ~= nowCol and share > shareNow then
					local what = key == healthKey and (pet and L["your pet's health"] or L["your health"]) or L["your power"]
					add("off", COLUMN_WHEN[col]:format(Tag(col, share), what), ColumnKey(db, key, col))
				end
			end
		end
	end
	if health == "off" and power == "off" then return end
	local hTag, pTag = Tag(hCol, hShare), Tag(pCol, pShare)
	if health == "always" then
		add("on", L["Kept up always (%s)"]:format(hTag), hKey)
	end
	if power == "always" then
		add("on", L["Kept up always (%s)"]:format(pTag), pKey)
	end
	if health == "always" or power == "always" then return end
	if fighting and not pet and ns.FightHold(row) then
		add("off", L["Held back at the fight's start while you're at rest (Wait at pull)"],
			health ~= "off" and hKey or pKey)
		return
	end
	local calmKey -- (a line shown by the After combat column: what opened it, after)
	if health == "below" then
		local share = HealthShare(pet and "pet" or "player")
		local text
		local fadeStart, fadeFull = FadeRange(db, healthKey, hShare)
		if fadeStart then
			add("off", L["Fades in as your health drops under %s, fully up at %d%% (Fade to)"]:format(
				ShareText(hShare):gsub("^< ", ""), math.floor(fadeFull * 100 + 0.5)), healthKey .. "Fade")
		end
		if share and share < hShare then
			text = pet and L["Your pet's health is under %s (%s)"] or L["Your health is under %s (%s)"]
			add("on", text:format(ShareText(hShare):gsub("^< ", ""), hTag), hKey)
			if hCol == 2 then calmKey = hKey end
		elseif share or pet then
			text = pet and L["Shows while your pet's health is under %s (%s)"]
				or L["Shows while your health is under %s (%s)"]
			add("off", text:format(ShareText(hShare):gsub("^< ", ""), hTag), hKey)
		else
			add("off", L["Shows while your health is under %s (%s): the game won't say your health, so it " ..
				"sets the opacity itself"]:format(ShareText(hShare):gsub("^< ", ""), hTag), hKey)
		end
	end
	if power == "below" and not nfPower then
		local below = PowerBelow(row, pShare, manaBar)
		if below then
			add("on", L["Your power is under %s (%s)"]:format(ShareText(pShare):gsub("^< ", ""), pTag), pKey)
			if pCol == 2 then calmKey = calmKey or pKey end
		elseif below == false then
			add("off", L["Shows while your power is under %s (%s)"]:format(ShareText(pShare):gsub("^< ", ""), pTag), pKey)
		else
			add("off", L["Shows while your power is under %s (%s): the game won't say your power, so it " ..
				"sets the opacity itself"]:format(ShareText(pShare):gsub("^< ", ""), pTag), pKey)
		end
	end
	if nfHealth or nfPower then
		local key = nfHealth and hKey or pKey
		local shown = false
		if nfHealth then
			if pet and ns.IsPetRecovering() then
				add("on", L["Your pet's health isn't full yet (%s)"]:format(hTag), hKey)
				shown = true
			elseif not pet and HealthNotFullByCurve(entry) then
				add("off", L["Shows while your health isn't full (%s): the game won't say your health, so it " ..
					"sets the opacity itself"]:format(hTag), hKey)
				shown = true
			elseif not pet and HealthNotFull() then
				add("on", L["Your health isn't full yet (%s)"]:format(hTag), hKey)
				shown = true
			end
			if shown and hCol == 2 then calmKey = calmKey or hKey end
		end
		if nfPower and PowerNotFull(db, row, manaBar) then
			add("on", (row == "prdmana" and L["Your mana isn't full yet (%s)"]
				or L["Your power isn't full yet, or your rage or the like isn't drained (%s)"]):format(pTag), pKey)
			shown = true
			if pCol == 2 then calmKey = calmKey or pKey end
		end
		if not shown then
			add("off", pet and L["Stays up while your pet's health isn't full (%s): it is"]:format(hTag)
				or L["Stays up while its health or power isn't full (%s): it is"]:format(nfHealth and hTag or pTag), key)
		end
	end
	if calmKey then
		add("on", CalmCauseText(), calmKey)
	end
end

-- The page.
function ns.CreatePersonalResourcesPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	-- (The Unit Frames icon's Keep up and Frame Links tabs, 2026-11-16: its
	-- Show in tab is the HUD page's. Its title is the tab shown, so the On/Off
	-- by it reads as Keep up's own switch.)
	-- (Two icons' tabs over the title since 2026-11-17, as the Nameplates
	-- page's: Unit Frames' (the player and pet frames' rows and links) and
	-- Personal Resources' (the PRD's), only the picked icon's shown.)
	local title = kit.Label(content, "GameFontNormalLarge", L["Keep up while low"])
	local hasDisplay = _G.CinematicPersonalPower ~= nil
	local outerPanel, ShowUnitTab = ns.PageTabs(content, ns.ShowInTabs("units"), ns.ShowInIndex("units", "Personal Resources"))
	local unitSet = content.pageTabs
	local ShowPrdTab, prdSet
	if hasDisplay then
		ShowPrdTab = select(2, ns.PageTabs(content, ns.ShowInTabs("prd"), ns.ShowInIndex("prd", "PRD Keep Up")))
		prdSet = content.pageTabs
	end
	content.pageTabs = unitSet
	title:SetPoint("TOPLEFT", outerPanel, "BOTTOMLEFT", 8, -14)
	local intro = kit.PageIntro(content, title,
		L["Brings your hidden player and pet frames back in CineMode while your health or power runs low."])
	-- (Their look: the Unit Frames icon's Resource Style tab.)
	local switch = kit.PageSwitch(content, "personalResources", L["Enable Page"],
		L["Turns this page's player frame, pet frame and resource display settings on or off."], intro, function()
		if ns.UpdatePersonalMana then ns.UpdatePersonalMana() end
		if ns.RefreshPersonalStyle then ns.RefreshPersonalStyle() end
		if ns.UpdateManaCost then ns.UpdateManaCost() end
	end)
	-- Its part (Options.lua's ns.PageTabsBelow, its own tabs not drawn: the
	-- Unit Frames tabs over the title pick it): Keep up. (Its Frame Links,
	-- the unit frames' and the bars': the Addons hub's Links page, 2026-11-17.)
	-- (The PRD's: its grid and Cine Mana Bar's settings, shown on its icon only. Below.)
	local unitGrid, prdGrid, holder
	local prdParts = {}
	local _, PickPart, TabsShown, AdoptTab = ns.PageTabsBelow(content, switch, {
		{ L["Show Advanced"], L["Brings your hidden frame and resource bars back while your health or power is low."] },
	}, "Personal Resources/page", nil, nil, 1, nil, true)
	ns.LinkPointer(content, { "units", "prd" })
	-- Which icon's this page is now: the Unit Frames icon's (the player and
	-- pet frames) or the Personal Resources icon's (the PRD), 2026-11-17: its
	-- tabs and its Keep up rows.
	local function SetIcon(prd)
		prd = prd and prdSet ~= nil
		for _, set in ipairs({ unitSet, prdSet or false }) do
			if set then
				local mine = (set == prdSet) == prd
				set.panel:SetShown(mine)
				for _, tab in ipairs(set.frames) do tab:SetShown(mine) end
			end
		end
		content.pageTabs = prd and prdSet or unitSet
		if unitGrid then unitGrid:SetShown(not prd) end
		if prdGrid then prdGrid:SetShown(prd) end
		local grid = prd and prdGrid or unitGrid
		if holder and grid then holder:SetHeight(grid:GetHeight()) end
		for _, part in ipairs(prdParts) do part:SetShown(prd) end
		return prd
	end
	-- Each part a hidden hub tile under its icon (its tabOf: HUBS', or the
	-- tab's), picked by its tab: Keep up's title and switch.
	local function ShowPart(prd)
		PickPart(1)
		prd = SetIcon(prd)
		if prd then
			ShowPrdTab(ns.ShowInIndex("prd", "PRD Keep Up"))
		else
			ShowUnitTab(ns.ShowInIndex("units", "Personal Resources"))
		end
		title:SetText(L["Keep up while low"])
	end
	local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\PersonalResources" -- (Media/make_prd_icon.py)
	canvas.hubTabs = {
		{ name = "Personal Resources", icon = ICON, label = "Unit Frames", switchLabel = "Keep up while low",
			onSelect = function() ShowPart(false) end },
	}
	-- (The PRD's, under the HUD's Personal Resources icon: tabOf.)
	if prdSet then
		local list = canvas.hubTabs
		list[#list + 1] = { name = "PRD Keep Up", icon = ICON, label = "Personal Resources", own = true,
			tabOf = "HUD:prd", switchLabel = "Keep up while low", onSelect = function() ShowPart(true) end }
	end
	local stack = kit.Stack(switch, "check")
	local function Tick(key, label, tip, enabledBy)
		local check = stack:Add(kit.Check(content, key, label, tip), "check")
		if enabledBy then kit.GreyUnless(check, enabledBy) end
		return check
	end
	-- Keep up: a row per bar, kept up while what it shows is under its share
	-- (as Heal Vision's roles are), a share per column, one at a time: In
	-- combat, After combat, Out of combat. A link between two columns: the right one goes by the
	-- left one's. A frame this client hasn't, no row.
	stack:Header(content, L["Keep up"])
	local function Fights(db) return db.stayInCombat end
	local SHARES = L["Stays up while it's under this share."]
	local COLUMNS = {
		{ L["In combat"], L["While you're in a fight."] .. " " .. SHARES .. " " ..
			L["Wait at pull holds it back at a fight's start."] },
		{ L["In Calm Timer"], L["After a fight, a fall or coming back to life, until the Calm Timer runs out."] .. " " .. SHARES },
		{ L["Out of combat"], L["Neither in a fight nor after one: drinking in town, say."] .. " " .. SHARES },
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
	-- { label (a function: named by your power), tip, share key (In combat's;
	-- the others' are named after it, KeepUpDefaults) }. Each frame its own
	-- rows (one set for the player frame and PRD till 2026-11-15: profiles
	-- now pick which is kept up).
	-- (Two sets since 2026-11-17: the Unit Frames icon's rows, the PRD's.)
	local rows = {
		{ L["Player Frame: Health"], L["Your player frame, by your health."], "prHealthPlayer", true },
		{ function() return L["Player Frame: %s"]:format(PowerName()) end,
			L["Your player frame, kept up by your power."], "prPowerPlayer" },
	}
	if _G.PetFrame then
		rows[#rows + 1] = { L["Pet Frame: Health"], L["Your pet frame, by your pet's health."], "prPetHealth" }
	end
	local prdRows = {}
	local function AddRow(row)
		prdRows[#prdRows + 1] = row
	end
	if hasDisplay then
		AddRow({ L["PRD: Health"], L["The game's personal resource display (PRD): its health bar."],
			"prHealthPrd", true })
		AddRow({ function() return L["PRD: %s"]:format(PowerName()) end,
			L["The game's personal resource display (PRD): its power bar (mana, rage, energy...)."],
			"prPowerPrd" })
	end
	if ns.PERSONAL_MANA then
		AddRow({ L["Cine Mana Bar"], L["Our mana bar under the resource display, kept up by your mana."], "prPowerMana" })
	end
	-- (Other addons' power bars standing in for these: their own rows, by addon.)
	for _, bar in ipairs(ns.ADDON_POWER_ROWS or {}) do
		if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(bar.addon) then
			AddRow({ L["Power bar (%s)"]:format(bar.addon), bar.tip, "prPower" .. bar.addon })
		end
	end
	-- (Columns: In combat, After combat, Out of combat, a link button between each.)
	local LABEL_W, ROW_H, HEAD_H, COL_W, LINK_W = 170, 26, 22, 104, 28
	local left, total = {}, LABEL_W
	for c = 1, #COLUMNS do
		if c > 1 then total = total + LINK_W end
		left[c] = total
		total = total + COL_W
	end
	-- (Fade to after them, the health rows': row[4]. Not linked, one per row.)
	local FADE_W = 76
	local fadeLeft = total + LINK_W / 2
	total = fadeLeft + FADE_W
	local FADE_TIP = L["Fades it in as your health drops, fully up at this share."]
	local function CenterX(c) return left[c] + COL_W / 2 end
	holder = CreateFrame("Frame", nil, content)
	holder:SetSize(total, 1)
	local named = {} -- { [label] = function } (the power rows: named again as the page shows)
	local LINK_TEX = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Link" -- (Media/make_link.py)
	local function BuildGrid(rows)
		local grid = CreateFrame("Frame", nil, holder)
		grid:SetPoint("TOPLEFT")
		grid:SetSize(total, HEAD_H + #rows * ROW_H + 8)
		for c, column in ipairs(COLUMNS) do
			local head = CreateFrame("Frame", nil, grid)
			head:SetSize(COL_W, 20)
			head:SetPoint("BOTTOMLEFT", grid, "TOPLEFT", left[c], -HEAD_H)
			local text = kit.Label(head, "GameFontNormalSmall", column[1])
			text:SetPoint("CENTER")
			text.searchSkip = true
			kit.Tooltip(head, column[2])
		end
		do
			local head = CreateFrame("Frame", nil, grid)
			head:SetSize(FADE_W, 20)
			head:SetPoint("BOTTOMLEFT", grid, "TOPLEFT", fadeLeft, -HEAD_H)
			local text = kit.Label(head, "GameFontNormalSmall", L["Fade to"])
			text:SetPoint("CENTER")
			text.searchSkip = true
			kit.Tooltip(head, FADE_TIP)
		end
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
			local key = row[3]
			local boxes, links = {}, {}
			-- (The row drawn as it is now: each box's value, the links lit or
			-- not, a linked box's text paler.)
			local function Draw()
				local db = ns.GetDB() or ns.db
				if not db then return end
				for c, box in ipairs(boxes) do
					box:Refresh()
					local linked = c > 1 and db[key .. LINK_SUFFIX[c]] ~= false
					box:SetTextColor(linked and 0.6 or 1, linked and 0.6 or 1, linked and 0.6 or 1)
					if links[c] then
						links[c].icon:SetVertexColor(linked and 1 or 0.4, linked and 0.82 or 0.4, linked and 0 or 0.4)
					end
				end
			end
			for c, column in ipairs(COLUMNS) do
				-- (A Show below box, Options.lua's ShareBox: a linked column shows
				-- and sets the one it goes by.)
				local line = kit.BoxLine(grid)
				local own = key .. COLUMN_SUFFIX[c]
				local tip = ("%s: %s. %s"):format(label, column[1], column[2])
				local box = line:ShareBox({
					get = function() return ColumnShare(ns.GetDB(), key, c) end,
					set = function(value) local db = ns.GetDB(); db[ColumnKey(db, key, c)] = value end,
				}, tip, function() Draw() end, NOT_FULL, 70)
				line:SetPoint("CENTER", grid, "TOPLEFT", CenterX(c), y - ROW_H / 2)
				box.searchLabel = ("%s: %s"):format(label, column[1])
				box.settingKey = own -- (/cine find, the Why window's links)
				kit.RecordKey(grid, own) -- (the page's Reset, profiles)
				boxes[c] = box
				if c > 1 then
					local link = CreateFrame("Button", nil, grid)
					link:SetSize(18, 18)
					link:SetPoint("CENTER", grid, "TOPLEFT", left[c] - LINK_W / 2, y - ROW_H / 2)
					link.icon = link:CreateTexture(nil, "ARTWORK")
					link.icon:SetAllPoints()
					link.icon:SetTexture(LINK_TEX)
					link:SetHighlightTexture(LINK_TEX, "ADD")
					local linkKey = key .. LINK_SUFFIX[c]
					kit.RecordKey(grid, linkKey)
					link:SetScript("OnClick", function()
						local db = ns.GetDB()
						if db[linkKey] ~= false then
							-- (Unlinked: it keeps the share it showed, its own now.)
							db[own] = ColumnShare(db, key, c)
							db[linkKey] = false
						else
							db[linkKey] = true
						end
						Draw()
					end)
					kit.Tooltip(link, L["Click to link or unlink these two columns."])
					links[c] = link
				end
			end
			-- (Fade to: Off at 0, else the share it's fully up at.)
			if row[4] then
				local fadeKey = key .. "Fade"
				local line = kit.BoxLine(grid)
				local box = line:Box("", fadeKey, 0, 95, 5, function(value)
					if value <= 0 then return L["Off"] end
					return ("%d%%"):format(math.floor(value + 0.5))
				end, 100, ("%s: %s. %s"):format(label, L["Fade to"], FADE_TIP), nil, 56)
				line:SetPoint("CENTER", grid, "TOPLEFT", fadeLeft + FADE_W / 2, y - ROW_H / 2)
				box.searchLabel = ("%s: %s"):format(label, L["Fade to"])
				box.settingKey = fadeKey
				kit.RecordKey(grid, fadeKey)
			end
			-- (And after the page's Reset, or a profile loaded.)
			local drawer = CreateFrame("Frame", nil, grid)
			drawer.Refresh = Draw
			kit.AddControl(drawer)
		end
		return grid
	end
	unitGrid = BuildGrid(rows)
	if #prdRows > 0 then
		prdGrid = BuildGrid(prdRows)
		prdGrid:Hide()
	end
	holder:SetHeight(unitGrid:GetHeight())
	stack:Add(holder, "label")
	-- (One for every row: each bar waits for what it shows.)
	Tick("fightWaitPull", L["Wait at pull"],
		L["At a fight's start, each bar waits until your health or power changes."], Fights)
	-- (Both bars' mana numbers, the PRD's and the player frame's: PersonalManaText.lua.)
	stack:Add(kit.Check(content, "manaAfterCast", L["Mana text"],
		L["While casting, your mana numbers show what you'll have left, paler."],
		function(value)
			ns.GetDB().manaAfterCast = value
			Redraw()
		end), "check")
	Tick("drainWhenNotEmpty", L["Rage counts until 0"],
		L["Rage and similar resources keep the frame up until they drain to 0."])

	-- Mana under the power bar, when it isn't your power (PersonalMana.lua; its
	-- look: the Style hub's Personal Resource Style page).
	-- (What's made from here to the end of Cine Mana Bar's settings: the PRD
	-- icon's only, prdParts.)
	local before = {}
	for _, object in ipairs({ content:GetChildren() }) do before[object] = true end
	for _, object in ipairs({ content:GetRegions() }) do before[object] = true end
	if ns.PERSONAL_MANA then
		stack:Header(content, L["Cine Mana Bar"])
		local function Update()
			if ns.UpdatePersonalMana then ns.UpdatePersonalMana() end
		end
		stack:Add(kit.Check(content, "prdMana", L["Show Cine Mana Bar"],
			L["Adds a mana bar under your main power bar."], function(value)
			ns.GetDB().prdMana = value
			if ns.RefreshPersonalStyle then ns.RefreshPersonalStyle() end -- (shown and dressed)
			kit.Refresh()
		end), "check")
		local recentLine = kit.BoxLine(content)
		stack:Add(recentLine, "label", 20)
		local recentBox = recentLine:Box(L["After using mana for"], "prdManaRecent", 0, 60, 1, "%d", 1,
			L["Shows the mana bar for this many seconds after you spend mana; 0 means always."], Update, 40, L["sec"])
		kit.GreyUnless(recentBox, function(db) return db.prdMana end)
		-- (And after the page's Reset, or a profile loaded: shown as the settings are now.)
		local updater = CreateFrame("Frame", nil, content)
		updater.Refresh = Update
		kit.AddControl(updater)
	end
	for _, set in ipairs({ { content:GetChildren() }, { content:GetRegions() } }) do
		for _, object in ipairs(set) do
			if not before[object] then
				prdParts[#prdParts + 1] = object
				object:Hide()
			end
		end
	end

	-- (And after the page's Reset, or a profile loaded: drawn as the settings are now.)
	local redrawer = CreateFrame("Frame", nil, content)
	redrawer.Refresh = Redraw -- (the grid's Mana text)
	kit.AddControl(redrawer)

	AdoptTab(switch) -- (everything above onto the Settings tab)
	SetIcon(false) -- (the Unit Frames icon's to start with: the PRD's parts put away)

	canvas:SetScript("OnShow", kit.PageShown(function()
		for text, Name in pairs(named) do text:SetText(Name()) end
		kit.Refresh()
		TabsShown()
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Personal Resources", L["Health & Resources"])
end
