-- Sleeping plates. In CineMode every plate is kept switched on (Effects.lua's
-- FORCED_PLATE_CVARS) and most sit faded to nothing. A plate that shows
-- nothing at all (alpha 0, no name or raid marker kept on it) is put to
-- sleep: Cinematic skips its parts, icons and looks (ns.PlateAsleep, asked
-- by PlateParts and the Style hub's plate pages) and, by ns.plateSleep.mode,
-- the game's own unit frame on it is hidden, or hidden and its events taken
-- away. As anything of it is to show again (its fade rising, a fight
-- starting, CineMode ending) it wakes: the game's frame back at once, ours
-- done again a few plates a frame (ns.plateSleep.OnWake).
-- Why: turning the camera in a crowd brings ~100 plates a second; each got
-- the full work only to stay invisible. /cine debug platecost (2026-11-17,
-- Forever, Trade District): CineMode 49 ms a frame vs 44 off; the game's frame
-- stripped saved ~4 ms, Cinematic's own work 1-4 ms.
-- Never in fights (fades change in them, and the game's health is secret
-- then: nothing here calls the game's own plate code, only Show/Hide and
-- its events), never on your target's, focus's, mouseover's, soft target's or
-- your own plate, nor with a nameplate addon drawing the plates.
local _, ns = ...

ns.plateSleep = {
	-- "off": nothing sleeps. "ours": only Cinematic's work skipped. "hide":
	-- and the game's frame hidden. "strip": and its events taken away too
	-- (given back on waking, as they were).
	mode = "hide",
	asleep = {}, -- [plate] = true
	stash = {},  -- [unit frame] = { { event, unit1, unit2 }, ... } its events taken away ("strip")
	pending = {}, -- [plate] = true: woken, our work still to do
	count = { slept = 0, woke = 0, stripped = 0, events = 0 },
}
local sleep = ns.plateSleep
local wakers = {} -- functions(plate): each part's work done again on waking

-- A part's work for a plate woken (fn(plate)).
function sleep.OnWake(fn)
	wakers[#wakers + 1] = fn
end

function ns.PlateAsleep(plate)
	return plate ~= nil and sleep.asleep[plate] == true
end

-- (The game's frame's events that matter to a plate: CompactUnitFrame's and
-- the nameplate's on the clients we know. One not listed is lost until the
-- plate gets its next unit, which registers them all again.)
local EVENTS = {
	"PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_ENABLED",
	"PLAYER_REGEN_DISABLED", "PLAYER_ROLES_ASSIGNED", "PLAYER_FLAGS_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED",
	"PLAYER_SOFT_FRIEND_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_TARGET_INTERACTION", "RAID_TARGET_UPDATE",
	"GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED",
	"INCOMING_RESURRECT_CHANGED", "INCOMING_SUMMON_CHANGED", "CVAR_UPDATE", "VARIABLES_LOADED", "DISPLAY_SIZE_CHANGED",
	"UI_SCALE_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UPDATE_MOUSEOVER_UNIT",
	"UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT",
	"UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE", "UNIT_NAME_UPDATE",
	"UNIT_AURA", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_HEAL_PREDICTION",
	"UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_PHASE", "UNIT_CONNECTION", "UNIT_PET",
	"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "UNIT_FLAGS", "UNIT_FACTION", "UNIT_OTHER_PARTY_CHANGED",
	"UNIT_CLASSIFICATION_CHANGED", "UNIT_LEVEL", "UNIT_TARGET", "UNIT_CTR_OPTIONS", "UNIT_DISTANCE_CHECK_UPDATE",
	"UNIT_IN_RANGE_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_TARGETABLE_CHANGED",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	"LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE",
}

local function Strip(frame)
	local kept = {}
	for _, event in ipairs(EVENTS) do
		local ok, on, unit1, unit2 = pcall(frame.IsEventRegistered, frame, event)
		if ok and on then
			kept[#kept + 1] = { event, unit1, unit2 }
		end
	end
	if not pcall(frame.UnregisterAllEvents, frame) then return end
	sleep.stash[frame] = kept
	sleep.count.stripped = sleep.count.stripped + 1
	sleep.count.events = sleep.count.events + #kept
end

local function Unstrip(frame)
	local kept = sleep.stash[frame]
	if not kept then return end
	sleep.stash[frame] = nil
	for _, entry in ipairs(kept) do
		if entry[2] then
			pcall(frame.RegisterUnitEvent, frame, entry[1], entry[2], entry[3])
		else
			pcall(frame.RegisterEvent, frame, entry[1])
		end
	end
end

local function Fighting()
	return InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
end

-- (The plates of these units, read once a frame: the fade asks per plate.)
local KEEP_UNITS = { "target", "focus", "mouseover", "softenemy", "softfriend", "softinteract", "player" }
local kept, keptAt = {}, -1
local function Kept(plate)
	local now = GetTime()
	if keptAt ~= now then
		keptAt = now
		wipe(kept)
		local get = C_NamePlate.GetNamePlateForUnit
		for _, unit in ipairs(KEEP_UNITS) do
			local ok, other = pcall(get, unit)
			if ok and other then kept[other] = true end
		end
	end
	return kept[plate] == true
end
-- (Your target or the mouse changing: that plate shows at once.)
local keptWatch = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
	"PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED" }) do
	pcall(keptWatch.RegisterEvent, keptWatch, event)
end
keptWatch:SetScript("OnEvent", function()
	keptAt = -1
	if not next(ns.plateSleep.asleep) then return end
	for plate in pairs(ns.plateSleep.asleep) do
		if Kept(plate) then ns.plateSleep.Wake(plate) end
	end
end)

local function CanSleep(plate)
	if sleep.mode == "off" or not plate or Fighting() then return false end
	if ns.addonPlateAlpha or ns.addonPlateHidden then return false end -- (a nameplate addon draws them)
	if plate.IsForbidden and plate:IsForbidden() then return false end
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return false end
	return not Kept(plate)
end

local function Sleep(plate)
	if sleep.asleep[plate] then return end
	sleep.asleep[plate] = true
	sleep.pending[plate] = nil
	sleep.count.slept = sleep.count.slept + 1
	local frame = plate.UnitFrame
	if not frame or sleep.mode == "ours" then return end
	if sleep.mode == "strip" and not sleep.stash[frame] then Strip(frame) end
	pcall(frame.Hide, frame)
end

local driver = CreateFrame("Frame")
driver:Hide()

-- Awake again: the game's frame back now, ours queued (a few a frame).
function sleep.Wake(plate)
	if not (plate and sleep.asleep[plate]) then return end
	sleep.asleep[plate] = nil
	sleep.count.woke = sleep.count.woke + 1
	local frame = plate.UnitFrame
	if frame then
		Unstrip(frame)
		pcall(frame.Show, frame)
	end
	sleep.pending[plate] = true
	driver:Show()
end

-- A plate given some alpha (or let go of, at full): awake and drawn.
function sleep.Shown(plate)
	if not plate then return end
	sleep.after[plate] = nil
	sleep.Wake(plate)
	sleep.drawn[plate] = true
end

function sleep.WakeAll()
	for plate in pairs(sleep.asleep) do
		sleep.Wake(plate)
	end
end

-- From Effects' plate fade, before it sets a plate's alphas: whether the
-- plate shows anything (alpha, its name or raid marker kept up). A plate
-- drawn since it came gets this pass in full first (its icons and parts
-- faded out with it), then sleeps (sleep.After); a new one sleeps at once.
sleep.drawn = {} -- [plate] = true: drawn awake since its unit came
sleep.after = {} -- [plate] = true: asleep once this pass is done
function sleep.Decide(plate, alpha, name, mark)
	if not plate then return end
	local nothing = (alpha or 1) <= 0 and (name or 0) <= 0 and (mark or 0) <= 0
	if nothing and CanSleep(plate) then
		if sleep.asleep[plate] then return end
		if sleep.drawn[plate] then
			sleep.after[plate] = true
		else
			Sleep(plate)
		end
	else
		sleep.after[plate] = nil
		sleep.Wake(plate)
		sleep.drawn[plate] = true
	end
end
function sleep.After(plate)
	if plate and sleep.after[plate] then
		sleep.after[plate], sleep.drawn[plate] = nil, nil
		Sleep(plate)
	end
end

local PER_FRAME = 6
ns.SetOnUpdate(driver, ns.Profiled("Plate wake", function(self)
	local done = 0
	for plate in pairs(sleep.pending) do
		sleep.pending[plate] = nil
		if not sleep.asleep[plate] and plate.UnitFrame then
			for _, fn in ipairs(wakers) do
				local ok, err = pcall(fn, plate)
				if not ok and ns.Log then ns.Log("plates", "plate wake error: " .. tostring(err)) end
			end
		end
		done = done + 1
		if done >= PER_FRAME then return end
	end
	self:Hide()
end))

-- A plate let go of: forgotten (the game sets its frame up afresh for its
-- next unit, events and all; shown here in case it isn't).
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_REGEN_DISABLED" then
		-- (Just before the fight's lockdown: every plate as the game has it.)
		sleep.WakeAll()
		return
	end
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end
	sleep.pending[plate], sleep.drawn[plate], sleep.after[plate] = nil, nil, nil
	if sleep.asleep[plate] then
		sleep.asleep[plate] = nil
		local frame = plate.UnitFrame
		if frame then
			sleep.stash[frame] = nil -- (its next unit registers them all again)
			pcall(frame.Show, frame)
		end
	end
end)

-- For /cine debug plates and the plate cost test.
function sleep.Describe()
	local n = 0
	for _ in pairs(sleep.asleep) do n = n + 1 end
	local c = sleep.count
	return ("plate sleep: mode %s, %d asleep now; slept %d, woke %d, stripped %d (%d events kept)"):format(
		sleep.mode, n, c.slept, c.woke, c.stripped, c.events)
end
