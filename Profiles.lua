-- Profiles: named sets of settings to switch between.
--
-- The settings themselves stay where they always were (ns.db, flat), so the
-- rest of the addon never knows about profiles. Each profile is stored as the
-- settings that differ from its base: the built-in profile's own values (the
-- defaults with its changes on top), or the defaults for the player's own.
-- Switching saves the one you're leaving and loads the next; so does logging
-- out. Every character uses the account's profile (db.profile) unless it's
-- been given one of its own (CinematicCharDB.profile); db.liveProfile is the
-- one whose settings are live, so logging in on a character with a different
-- one swaps them over. Built-in profiles keep your changes too, until you reset them, and
-- settings you never changed follow the built-in's values as they're updated.
--
-- Not part of a profile: the minimap button and its position, the on/off
-- switch, debug options, frames you added or stopped fading, zone and time
-- tint colours you picked, the master wheel's wheels and your own wheels, and things the addon keeps for itself (flight
-- times, the log, game settings it's holding).

local _, ns = ...
local L = ns.L

local GLOBAL_KEYS = {
	enabled = true, minimapButton = true, minimapAngle = true, logDetail = true, language = true,
	masterWheelOrder = true, masterWheelOff = true, customWheels = true, wheelExtras = true, -- (Wheels pages)
	cameraScripts = true, -- (CameraScripts.lua: your scripts, the same in every profile)
	stylePreviewPos = true, -- (StylePages.lua: where you dragged the Style preview window)
	dockSpots = true, -- (Skin.lua's DockBeside: where you dragged popped-out windows)
	peeksLog = true, -- (/cine debug peeks log)
}
-- Lists kept as tables that belong to a profile (their defaults are in code;
-- see EnsureTables in Core.lua). Missing from a profile: emptied, which means defaults.
local PROFILE_TABLES = {
	"chatPeekTypes", "chatPeekChannelList", "combatShow", "calmShow", "quietShow", "camShow", "cineShow", "targetShow", "enemyShow",
	"friendlyShow", "bgShow", "worldShow", "cityShow", "groupShow", "instanceShow", "addonFrames", "gamepadPressButtons",
	"hoverGroups", "cooldownReadyOnly", "cooldownReadyEarly", "cooldownEarlyOn", "cooldownRechargeOnly", "cooldownNeedsPower",
	"cooldownGroupDefaults", "cooldownProcOnly", "cooldownAlwaysShow", "cooldownBuffMode", "cooldownFlashReady",
	"frameRules", -- (none in any built-in profile: each starts with no Custom Visibility Rules)
	"rowFollow", -- (the grids' Follow: which row each follows; Cinema's mana bar its resource bar)
	"tankHide", "healerHide", "damageHide", -- (the old Roles column's: loaded to become rules, ns.MigrateRoleHides)
	"markNames", -- (the Nameplates page's rows' own names)
	"cameraRows", -- (the Cameras page's rows: CameraRows.lua)
	"lowHealthThemeEdits", "lowHealthMyThemes", -- (Vitals Vision's themes: players' versions of ours, and their own)
	"lowHealthFromTheme", -- (which of the profile's Vitals settings its theme put on, not the player)
}
ns.PROFILE_TABLES = PROFILE_TABLES
ns.IS_PROFILE_TABLE = {}
for _, key in ipairs(PROFILE_TABLES) do ns.IS_PROFILE_TABLE[key] = true end

local DEFAULT_PROFILE -- (this client's default built-in: set after the list)

-- The built-in profiles (ns.BUILTIN_PROFILES) are in ProfileChoices.lua.
-- Each client's order, by name, where it isn't the list's (those not in it
-- come after, in the list's order).
-- (e.g. retail = { "Immersive (CDM)", "Immersive" }: those two first on retail)
local BUILTIN_ORDER = {}

-- Every client's (ALL_BUILTIN_PROFILES, for the dev build), and this one's
-- in its order (BUILTIN_PROFILES). The default is the one marked so, else
-- the first.
ns.ALL_BUILTIN_PROFILES = ns.BUILTIN_PROFILES
do
	local order, list = {}, {}
	for i, name in ipairs(BUILTIN_ORDER[ns.CLIENT] or {}) do order[name] = i end
	for i, profile in ipairs(ns.ALL_BUILTIN_PROFILES) do
		if (not profile.client or profile.client == ns.CLIENT) and (not profile.dev or ns.isDev)
			and not profile.hidden then
			list[#list + 1] = { profile = profile, rank = order[profile.name] or 1000 + i }
		end
	end
	table.sort(list, function(a, b) return a.rank < b.rank end)
	ns.BUILTIN_PROFILES = {}
	for i, entry in ipairs(list) do ns.BUILTIN_PROFILES[i] = entry.profile end
end
DEFAULT_PROFILE = ns.BUILTIN_PROFILES[1].name
for _, profile in ipairs(ns.BUILTIN_PROFILES) do
	if profile.default then DEFAULT_PROFILE = profile.name end
end
ns.DEFAULT_PROFILE = DEFAULT_PROFILE
ns.OnLanguage(function() ns.TranslateFields(ns.ALL_BUILTIN_PROFILES, "tip", "label") end)
local builtinByName, allBuiltinNames, allBuiltinByName = {}, {}, {}
for _, profile in ipairs(ns.BUILTIN_PROFILES) do builtinByName[profile.name] = profile end
for _, profile in ipairs(ns.ALL_BUILTIN_PROFILES) do
	allBuiltinNames[profile.name] = true
	allBuiltinByName[profile.name] = profile
end
ns.ALL_BUILTIN_BY_NAME = allBuiltinByName
-- Retired built-ins (ns.RETIRED_PROFILES) and old names, this client's:
-- what was saved under one is a change from its values until it's moved
-- over at login (ns.InitProfiles).
local retiredByName, retiredHere, oldNameOf, otherClientRetired = {}, {}, {}, {}
for _, profile in ipairs(ns.RETIRED_PROFILES or {}) do
	retiredByName[profile.name] = profile
	if not profile.client or profile.client == ns.CLIENT then
		retiredHere[#retiredHere + 1] = profile
	else
		otherClientRetired[profile.name] = true
	end
end
for _, profile in ipairs(ns.BUILTIN_PROFILES) do
	for _, old in ipairs(profile.oldNames or {}) do oldNameOf[old] = profile end
end

-- Just switched to a profile (Profiles page, welcome window): a built-in
-- with a preview shows its mouseover group of that preset for a few
-- seconds, as its settings and layout have it now, with the rest of the UI
-- faded (Core.lua, Frames.lua). Another profile: none.
local PREVIEW_TIME = 3
function ns.PreviewProfile(name)
	local builtin = builtinByName[name]
	ns.previewRows = nil
	if not (builtin and builtin.preview) then return end
	-- (The UI fading out for a layout change first: once it's switched, Layouts.lua.)
	if ns.layoutFadeUntil then
		ns.pendingPreview = name
		return
	end
	local rows = {}
	for _, group in ipairs(ns.GetHoverGroups()) do
		if group.preset == builtin.preview then
			for _, member in ipairs(group.members or {}) do rows[member] = true end
		end
	end
	ns.previewRows, ns.previewUntil = rows, GetTime() + PREVIEW_TIME
end

-- The name a profile is shown by: a built-in's label, or its name.
function ns.ProfileLabel(name)
	local builtin = builtinByName[name]
	return builtin and builtin.label or name
end

function ns.IsBuiltinProfile(name)
	return builtinByName[name] ~= nil
end

local function IsProfileKey(key)
	-- (Graphics+ is the machine's: a shared or switched profile leaves it as it is.)
	return not GLOBAL_KEYS[key] and not key:find("^debug") and not key:find("^graphicsPlus")
end
ns.IsProfileKey = IsProfileKey

local function CopyTable(source)
	if type(source) ~= "table" then return source end
	local result = {}
	for k, v in pairs(source) do result[k] = CopyTable(v) end
	return result
end

-- A built-in's modules on this client, resolved (ns.ResolveModules), with
-- the dev build's Module Editor changes (ns.DevEdits).
function ns.BuiltinModules(profile)
	local edits = ns.DevEdits()
	return ns.ResolveModules(profile, ns.CLIENT, allBuiltinByName, function(name)
		return edits and edits.profiles and edits.profiles[name]
	end)
end

-- A profile's built-in modules: a built-in's, or (until moved over at
-- login) an old name's or a retired built-in's. nil: your own.
local function ModulesFor(name)
	local builtin = builtinByName[name]
	if builtin then return ns.BuiltinModules(builtin) end
	local db = ns.db or {}
	builtin = oldNameOf[name]
	if builtin and not (db.profiles and db.profiles[builtin.name]) then return ns.BuiltinModules(builtin) end
	local retired = retiredByName[name]
	if retired and not (db.retiredProfiles and db.retiredProfiles[name]) then
		return ns.ResolveModules(retired, ns.CLIENT, retiredByName)
	end
end

-- The rows' default rules (ns.RULE_DEFAULTS) put into values.frameRules where
-- it has none for the row (a copy: the table may be a built-in's or a reset
-- point's). A row's rule cleared on purpose ("") stays cleared.
local function WithRuleDefaults(values)
	local rules = type(values.frameRules) == "table" and values.frameRules or nil
	local copy
	for key, rule in pairs(ns.RULE_DEFAULTS or {}) do
		if not (rules and rules[key] ~= nil) then
			copy = copy or CopyTable(rules or {})
			copy[key] = rule
		end
	end
	if copy then values.frameRules = copy end
	return values
end

-- The values a profile starts from: the defaults, with a built-in's modules.
local baseCache = {}
function ns.ProfileBase(name)
	name = name or ns.ActiveProfile()
	if baseCache[name] then return baseCache[name] end
	local base = {}
	for k, v in pairs(ns.DEFAULTS) do base[k] = v end
	local modules = ModulesFor(name)
	if modules then ns.ApplyModules(modules, base, ns.CLIENT) end
	WithRuleDefaults(base)
	baseCache[name] = base
	return base
end

-- The same before the old grids' settings go over (ns.ConvertOffGrids, Core.lua):
-- what a profile saved before they did was a change from. Not kept.
function ns.RawProfileBase(name)
	local base = {}
	for k, v in pairs(ns.DEFAULTS) do base[k] = v end
	local modules = ModulesFor(name)
	if modules then ns.ApplyModules(modules, base, ns.CLIENT, nil, true) end
	return WithRuleDefaults(base)
end

-- After a built-in's modules change (Module Editor): worked out again when
-- next wanted. The live settings stay as they are.
function ns.ForgetProfileBases()
	wipe(baseCache)
	if ns.ForgetPartValues then ns.ForgetPartValues() end
end

-- The settings of rows added on the Style hub's Nameplates page in a
-- table (no defaults of their own: Core's MarkRowDefault): fn(key, value).
local function EachRowSetting(t, fn)
	local keys = {}
	for k in pairs(t) do
		if ns.MarkRowDefault(k) ~= nil then keys[#keys + 1] = k end
	end
	for _, k in ipairs(keys) do fn(k, t[k]) end
end

-- A profile's settings as they'd be live: the active one's are; another's,
-- its base with its saved changes (for comparing them).
function ns.ProfileSettings(name)
	local settings = {}
	if name == ns.ActiveProfile() then
		for k in pairs(ns.DEFAULTS) do settings[k] = ns.db[k] end
		for _, k in ipairs(PROFILE_TABLES) do settings[k] = ns.db[k] end
		EachRowSetting(ns.db, function(k, v) settings[k] = v end)
		return settings
	end
	local base, saved = ns.ProfileBase(name), ns.db.profiles[name] or {}
	for k in pairs(ns.DEFAULTS) do
		if saved[k] ~= nil then settings[k] = saved[k] else settings[k] = base[k] end
	end
	for _, k in ipairs(PROFILE_TABLES) do settings[k] = saved[k] or base[k] end
	EachRowSetting(base, function(k, v) settings[k] = v end)
	EachRowSetting(saved, function(k, v) settings[k] = v end)
	return settings
end

-- A new player has none until they pick one (Welcome.lua): Cinematic does
-- nothing meanwhile. (The default profile's settings are the live ones.)
function ns.ProfileChosen()
	return not ns.db or ns.db.profileChosen ~= false
end

-- Until then every page's switch is off too, so nothing of Cinematic's runs
-- or shows as on in the settings (db.offUntilPicked: each one's value from
-- before, put back as a profile's picked, then the profile loaded over it).
-- Kept: the switches that only change a look of Cinematic's own (the
-- letterbox's, Vitals', a Vision's), which do nothing with their feature off
-- and give the welcome window's demos (ShowMe.lua) their proper look.
local OFF_UNTIL_PICKED = {
	"handleFrames", "handleAddonFrames", "mouseover", "handleGamepad", "handleUnitFrames", "personalResources",
	"handleBuffs", "handleCooldowns", "handleSwing", "handleMinimap", "handleQuests", "handleTooltips",
	"handleChat", "handlePlates", "handleBubbles",
	"cameraModes", "shoulderCam",
	"visualEffects", "letterboxPage", "tintPage", "graphicsPlus", "musicInCinematic",
	"styleGeneral", "ufStyle", "rfStyle", "prdStyle", "tooltipStyle", "handlePlateStyle", "plateNameStyle",
	"plateCastStyle", "bubblesStyle",
	"handleHealVision", "damageVision", "lowHealth", "questVision", "questTalk", "rollWindow", "teleportVision",
	"duelPlates", "emoteVision", "cards", "windGuide",
	"handleQuality", "handleFishing", "handleHunter",
	"cooldownManagerOn", "prdOn", "prdOnFights", -- (the game switches a profile turns on: ApplyProfileSwitches)
}
ns.OFF_UNTIL_PICKED = OFF_UNTIL_PICKED

function ns.SwitchOffUntilPicked()
	local db = ns.db
	if not db or db.offUntilPicked then return end
	local before = {}
	for _, key in ipairs(OFF_UNTIL_PICKED) do
		if ns.DEFAULTS[key] ~= nil then
			before[key] = db[key]
			db[key] = false
		end
	end
	db.offUntilPicked = before
end

-- Picking a profile (or making one of your own) while they're off: back as
-- they were first, so the live settings are the profile's again.
local function LeaveOffState()
	local db = ns.db
	local before = db and db.offUntilPicked
	if type(before) ~= "table" then
		if db then db.offUntilPicked = nil end
		return false
	end
	db.offUntilPicked = nil
	for key, value in pairs(before) do db[key] = value end
	return true
end

function ns.ActiveProfile()
	return ns.db and ns.db.liveProfile or DEFAULT_PROFILE
end

-- This character has a profile of its own (not the account's).
function ns.IsCharacterProfile()
	return ns.chardb ~= nil and ns.chardb.profile ~= nil
end

-- Makes name the active one: this character's, or the account's.
local function Choose(name)
	if ns.IsCharacterProfile() then
		ns.chardb.profile = name
	else
		ns.db.profile = name
	end
	ns.db.liveProfile = name
end

-- The live settings as a profile: what differs from the base, and the lists.
local function Snapshot(name)
	local db, base = ns.db, ns.ProfileBase(name)
	local saved = {}
	for k in pairs(ns.DEFAULTS) do
		if IsProfileKey(k) and db[k] ~= base[k] then
			saved[k] = db[k]
		end
	end
	for _, k in ipairs(PROFILE_TABLES) do
		if type(db[k]) == "table" and next(db[k]) ~= nil then saved[k] = CopyTable(db[k]) end
	end
	-- (The Style hub's Nameplates page's added rows: all of theirs.)
	EachRowSetting(db, function(k, v) saved[k] = v end)
	return saved
end

-- Puts a profile's settings into the live ones.
local function Load(name)
	local db, base = ns.db, ns.ProfileBase(name)
	local saved = db.profiles[name] or {}
	-- (The Style hub's Nameplates page's added rows: the built-in's and the
	-- profile's, none else.)
	EachRowSetting(db, function(k) db[k] = nil end)
	EachRowSetting(base, function(k, v) db[k] = v end)
	EachRowSetting(saved, function(k, v) db[k] = v end)
	for k in pairs(ns.DEFAULTS) do
		if IsProfileKey(k) then
			if saved[k] ~= nil then
				db[k] = saved[k]
			else
				db[k] = base[k]
			end
		end
	end
	for _, k in ipairs(PROFILE_TABLES) do
		-- (A built-in's own list when it has one; a copy, so the base isn't changed.)
		db[k] = CopyTable(saved[k] or base[k])
	end
	ns.EnsureTables()
	ns.MigrateRoleHides()
	if ns.ResyncVitalsLook then ns.ResyncVitalsLook() end -- (its theme's own look onto settings at their defaults)
end

-- Game switches for profiles that use them: the Cooldown Manager
-- (db.cooldownManagerOn, the CDM part; cooldownViewerEnabled, the same on
-- both clients) and the personal resource display (db.prdOn, the Personal
-- Resource Centered layout, or also db.prdOnFights, Cinema's fights;
-- nameplateShowSelf). Each turned on if it's off, and back off on switching to a profile without it, if Cinematic turned it
-- on (db[turnedOn]). The player's own choice stands: switched by them
-- meanwhile, it's left as they put it (db[leftAlone]) until they're on a
-- profile without it again. Not in fights: once one ends.
local PROFILE_SWITCHES = {
	{ key = "cooldownManagerOn", cvar = "cooldownViewerEnabled", turnedOn = "cdmTurnedOn",
		leftAlone = "cdmLeftAlone", name = "cooldown manager" },
	{ key = "prdOn", also = "prdOnFights", cvar = "nameplateShowSelf", turnedOn = "prdTurnedOn",
		leftAlone = "prdLeftAlone", name = "personal resource display" },
}
local switchFrame = CreateFrame("Frame")
local switchWritten = {} -- (by cvar, the value just written: its CVAR_UPDATE isn't the player's)
-- Whether the profile wants a switch on.
local function Wanted(db, switch)
	return db[switch.key] or (switch.also and db[switch.also]) or false
end
local function ApplyProfileSwitches()
	local db = ns.db
	if not db then return end
	if InCombatLockdown() then
		switchFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	for _, switch in ipairs(PROFILE_SWITCHES) do
		local cvar = switch.cvar
		if GetCVar(cvar) ~= nil then
			local on = GetCVar(cvar) == "1"
			local want
			if Wanted(db, switch) and db.enabled then
				-- (Our turnedOn with it off: switched off where its CVAR_UPDATE wasn't
				-- seen, e.g. logged out. Stale: on again.)
				if not on and not db[switch.leftAlone] then want = "1" end
			else
				db[switch.leftAlone] = nil
				if db[switch.turnedOn] then
					db[switch.turnedOn] = nil
					if on then want = "0" end
				end
			end
			if want then
				switchWritten[cvar] = want
				SetCVar(cvar, want)
				db[switch.turnedOn] = want == "1" or nil
				ns.Log("state", switch.name .. (want == "1" and " turned on for the profile" or " back off"))
			end
		end
	end
end
switchFrame:RegisterEvent("PLAYER_LOGIN")
switchFrame:RegisterEvent("CVAR_UPDATE")
switchFrame:SetScript("OnEvent", function(self, event, name)
	if event == "CVAR_UPDATE" then
		if type(name) ~= "string" or not ns.db then return end
		for _, switch in ipairs(PROFILE_SWITCHES) do
			local cvar = switch.cvar
			if name:lower() == cvar:lower() then
				if switchWritten[cvar] and GetCVar(cvar) == switchWritten[cvar] then
					switchWritten[cvar] = nil -- (ours)
					return
				end
				-- (the player switching it themselves: theirs from now on)
				switchWritten[cvar] = nil
				ns.db[switch.turnedOn] = nil
				if Wanted(ns.db, switch) then ns.db[switch.leftAlone] = true end
				return
			end
		end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then self:UnregisterEvent(event) end
	ApplyProfileSwitches()
end)

-- Everything that reads settings once picks up the new ones. (optionsMs:
-- how long the settings pages took to refresh, for SetProfile's log line.)
local optionsMs = 0
local function SettingsChanged()
	ns.letterboxDirty = true
	if ns.RestartTimers then ns.RestartTimers() end
	if ns.RefreshTint then ns.RefreshTint() end
	if ns.BuildManagedList then ns.BuildManagedList() end
	if ns.ApplyBubbles then ns.ApplyBubbles() end
	if ns.ApplyUnitFrameParts then ns.ApplyUnitFrameParts() end
	if ns.SwitchProfileLayout then ns.SwitchProfileLayout() end
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	ApplyProfileSwitches()
	local started = debugprofilestop()
	if ns.RefreshOptions then ns.RefreshOptions() end
	optionsMs = debugprofilestop() - started
end

-- Keeps the live settings in the active profile (on switching and logout).
function ns.SaveProfile()
	-- (Not while the pages' switches are off for no profile picked: they're
	-- not the profile's.)
	if ns.db and ns.db.profiles and not ns.db.offUntilPicked then
		ns.db.profiles[ns.ActiveProfile()] = Snapshot(ns.ActiveProfile())
	end
end

function ns.ProfileExists(name)
	return builtinByName[name] ~= nil or (ns.db.profiles[name] ~= nil)
end

-- Every profile's name: the built-in ones in order, then the player's A to Z.
function ns.ProfileNames()
	local names, own = {}, {}
	for _, profile in ipairs(ns.BUILTIN_PROFILES) do names[#names + 1] = profile.name end
	for name in pairs(ns.db.profiles) do
		-- (Not one of the other built-ins: another client's, or hidden. Their
		-- settings stay saved for when they're listed again.)
		if not builtinByName[name] and not allBuiltinNames[name] and not otherClientRetired[name] then
			own[#own + 1] = name
		end
	end
	table.sort(own, function(a, b) return a:lower() < b:lower() end)
	for _, name in ipairs(own) do names[#names + 1] = name end
	return names
end

-- Finds a profile by its name or label, ignoring case (for /cine profile).
function ns.FindProfile(text)
	text = text:lower()
	for _, name in ipairs(ns.ProfileNames()) do
		if name:lower() == text or ns.ProfileLabel(name):lower() == text then return name end
	end
end

-- Not in fights: a switch reloads every setting and restyles the UI, which
-- the game's protected frames refuse mid-fight (left half-switched). Says so.
function ns.ProfileSwitchBlocked()
	if not InCombatLockdown() then return false end
	ns.Print(L["can't switch profiles in a fight: try again once it's over"])
	if ns.PeekChat then ns.PeekChat(DEFAULT_CHAT_FRAME, 8) end -- (up through CineMode, to be seen)
	return true
end

-- True once on that profile (false: no such profile, or in a fight).
function ns.SetProfile(name)
	if not ns.ProfileExists(name) then return false end
	if ns.ProfileSwitchBlocked() then return false end
	local first = not ns.ProfileChosen()
	-- (the pages' switches off till now: the active profile's again, loaded
	-- below if it's the one picked)
	local wasOff = LeaveOffState()
	ns.db.profileChosen = true
	if name == ns.ActiveProfile() then
		if wasOff then Load(name) end
		if first or wasOff then SettingsChanged() end -- (the first pick: Cinematic starts)
		return true
	end
	-- (How long it took, in the log: the settings pages' refresh is most of it.)
	local started = debugprofilestop()
	ns.SaveProfile()
	Choose(name)
	Load(name)
	local loaded = debugprofilestop()
	SettingsChanged()
	local applied = debugprofilestop() - loaded
	ns.Log("state", ("profile: %s (%.0f ms: load %.0f, apply %.0f, settings pages %.0f)"):format(name,
		debugprofilestop() - started, loaded - started, applied - optionsMs, optionsMs))
	return true
end

-- One choice on its own over the live settings (the welcome window's
-- Customize pages, the Profiles demo): just its slot's settings (the ones
-- any of the slot's choices change, ns.SettingSlot, and their rows of shared
-- lists) are set as the choice has them, the rest left as they are.
do
	-- The settings with that choice: the defaults, with its modules on top.
	-- Kept (by slot and part): matching every choice on the Profiles page's
	-- Customize took ~6 ms each. Not to be changed by whoever asks for it.
	local partCache, slotKeys = {}, {}
	local function PartValues(slot, part)
		local id = slot .. "|" .. tostring(part)
		if partCache[id] then return partCache[id] end
		local values = {}
		for k, v in pairs(ns.DEFAULTS) do values[k] = v end
		values = ns.ApplyModules(ns.ChoiceModules(slot, part, ns.CLIENT) or {}, values, ns.CLIENT)
		partCache[id] = values
		return values
	end
	-- (After a built-in's modules change: ns.ForgetProfileBases.)
	ns.ForgetPartValues = function() wipe(partCache) end
	-- fn(key, row, value) for each of the slot's settings and list rows.
	local function EachInSlot(slot, values, fn)
		-- (The slot's settings, found once.)
		local keys = slotKeys[slot]
		if not keys then
			keys = {}
			for k in pairs(ns.DEFAULTS) do
				if IsProfileKey(k) and ns.SettingSlot(k) == slot then keys[#keys + 1] = k end
			end
			slotKeys[slot] = keys
		end
		for _, k in ipairs(keys) do
			if type(values[k]) ~= "table" then fn(k, nil, values[k]) end
		end
		-- (The Nameplates page's added rows' settings: the choice's, and the
		-- live ones it hasn't got, which go.)
		local rowKeys = {}
		EachRowSetting(values, function(k) rowKeys[k] = true end)
		EachRowSetting(ns.db, function(k) rowKeys[k] = true end)
		for k in pairs(rowKeys) do
			if IsProfileKey(k) and ns.SettingSlot(k) == slot then fn(k, nil, values[k]) end
		end
		for _, k in ipairs(PROFILE_TABLES) do
			local want, live, seen = values[k], ns.db[k], {}
			for _, list in ipairs({ type(want) == "table" and want or {}, type(live) == "table" and live or {} }) do
				for row in pairs(list) do
					if not seen[row] and ns.SettingSlot(k, row) == slot then
						seen[row] = true
						-- (Not want[row] or nil: a row turned off is false.)
						local value
						if type(want) == "table" then value = want[row] end
						fn(k, row, value)
					end
				end
			end
		end
	end

	-- The live settings are that part's, in its slot. (A list row holding a
	-- table isn't compared.)
	function ns.SlotPartMatches(slot, part)
		local same = true
		EachInSlot(slot, PartValues(slot, part), function(k, row, value)
			local live = ns.db[k]
			if row ~= nil then
				local list = live
				live = nil
				if type(list) == "table" then live = list[row] end
			end
			if type(value) ~= "table" and live ~= value then same = false end
		end)
		return same
	end

	-- Worked out ahead (ns.InitProfiles): every choice's settings, one a
	-- moment, so the Profiles page's Customize is quick the first time too.
	-- (Not in fights: it waits.)
	local WARM_DELAY, WARM_STEP = 15, 0.1 -- seconds after login; between choices
	function ns.WarmPartValues()
		local todo = {}
		for _, slot in ipairs(ns.PROFILE_SLOTS or {}) do
			for _, choice in ipairs(ns.SlotChoices(slot.key) or {}) do
				todo[#todo + 1] = { slot.key, choice.part }
			end
		end
		local i = 0
		local function Step()
			if InCombatLockdown() then return C_Timer.After(1, Step) end
			i = i + 1
			local item = todo[i]
			if not item then return end
			EachInSlot(item[1], PartValues(item[1], item[2]), function() end)
			C_Timer.After(WARM_STEP, Step)
		end
		C_Timer.After(WARM_DELAY, Step)
	end

	-- On a built-in, a profile of your own (named ownName, numbered if
	-- taken) from it, switched to, so a change leaves the built-in as it is.
	function ns.EnsureOwnProfile(ownName)
		if builtinByName[ns.ActiveProfile()] and ownName then
			local name, n = ownName, 1
			while ns.ProfileExists(name) do
				n = n + 1
				name = ownName .. " " .. n
			end
			ns.NewProfile(name)
		end
	end

	function ns.ApplyPart(slot, part, ownName)
		ns.EnsureOwnProfile(ownName)
		EachInSlot(slot, PartValues(slot, part), function(k, row, value)
			if row == nil then
				ns.db[k] = value
			else
				if type(ns.db[k]) ~= "table" then ns.db[k] = {} end
				ns.db[k][row] = CopyTable(value)
			end
		end)
		ns.SaveProfile()
		SettingsChanged()
		ns.Log("state", ("part: %s %s on %s"):format(slot, part, ns.ActiveProfile()))
	end
end

-- Swapping sets of settings, for any page that offers choices:
--   ns.ApplyChoice(slot, part[, ownName]): the slot's settings as the choice
--     has them, the rest as they are (on a built-in, first a profile of your
--     own called ownName, if given).
--   ns.LiveChoice(slot): the offered choice the live settings match (the
--     first, as two can match), or nil: a mix of its own.
--   ns.ApplyModulesLive(keys[, ownName]): just what the modules change
--     (module keys), over the live settings, the rest as they are.
ns.ApplyChoice = function(slot, part, ownName) return ns.ApplyPart(slot, part, ownName) end

function ns.LiveChoice(slot)
	for _, choice in ipairs(ns.SlotChoices(slot) or {}) do
		if ns.SlotPartMatches(slot, choice.part) then return choice end
	end
end

function ns.ApplyModulesLive(keys, ownName)
	ns.EnsureOwnProfile(ownName)
	local resolved = {}
	for _, key in ipairs(keys) do
		local module = ns.GetModule(key)
		if module then resolved[#resolved + 1] = { key = key, module = module } end
	end
	for _, change in ipairs(ns.ModuleEffect(resolved, ns.CLIENT)) do
		local key, row, value = change[1], change[2], change[3]
		if row == nil then
			ns.db[key] = CopyTable(value)
		else
			if type(ns.db[key]) ~= "table" then ns.db[key] = {} end
			ns.db[key][row] = CopyTable(value)
		end
	end
	ns.SaveProfile()
	SettingsChanged()
	ns.Log("state", ("modules: %s on %s"):format(table.concat(keys, ", "), ns.ActiveProfile()))
end

-- A profile of your own's description (db.profileNotes: kept apart from its
-- settings, which are written over each time it's saved).
function ns.ProfileNote(name)
	return ns.db.profileNotes[name]
end

function ns.SetProfileNote(name, text)
	if builtinByName[name] then return end
	ns.db.profileNotes[name] = text ~= "" and text or nil
end

-- A profile's icon: a built-in's own, or the one picked for yours
-- (db.profileIcons: any of the game's icons, picked on the Profiles page).
function ns.ProfileIcon(name)
	local builtin = builtinByName[name]
	return builtin and builtin.icon or ns.db.profileIcons[name] or ns.HOVER_GROUP_ICONS[1]
end

function ns.SetProfileIcon(name, file)
	if builtinByName[name] then return end
	ns.db.profileIcons[name] = file
end

-- A random icon no profile has yet (for a new one), else any.
function ns.UnusedProfileIcon()
	local used, free = {}, {}
	for _, name in ipairs(ns.ProfileNames()) do used[ns.ProfileIcon(name)] = true end
	for i = 2, #ns.HOVER_GROUP_ICONS do
		if not used[ns.HOVER_GROUP_ICONS[i]] then free[#free + 1] = ns.HOVER_GROUP_ICONS[i] end
	end
	if #free == 0 then free = ns.HOVER_GROUP_ICONS end
	return free[math.random(#free)]
end

-- A new profile of your own from the current settings.
function ns.NewProfile(name)
	if ns.ProfileExists(name) then return false end
	LeaveOffState() -- (from the profile's settings, not the switches off for none picked)
	local saved = Snapshot(ns.ActiveProfile())
	-- Stored against the defaults (a player's profile has no built-in under it).
	local base, own = ns.ProfileBase(ns.ActiveProfile()), ns.ProfileBase(name)
	for k in pairs(ns.DEFAULTS) do
		if IsProfileKey(k) then
			local value = saved[k]
			if value == nil then value = base[k] end
			if value == own[k] then value = nil end
			saved[k] = value
		end
	end
	ns.SaveProfile()
	ns.db.profiles[name] = saved
	ns.db.profileNotes[name] = L["Started from %s."]:format(ns.ProfileLabel(ns.ActiveProfile()))
	ns.db.profileIcons[name] = ns.UnusedProfileIcon()
	Choose(name)
	ns.db.profileChosen = true
	return true
end

function ns.RenameProfile(old, new)
	if builtinByName[old] or ns.ProfileExists(new) then return false end
	if old == ns.ActiveProfile() then ns.SaveProfile() end
	if ns.RenameBackups then ns.RenameBackups(old, new) end -- (Backups.lua)
	ns.db.profiles[new], ns.db.profiles[old] = ns.db.profiles[old], nil
	ns.db.profileNotes[new], ns.db.profileNotes[old] = ns.db.profileNotes[old], nil
	ns.db.profileIcons[new], ns.db.profileIcons[old] = ns.db.profileIcons[old], nil
	local points = ns.db.profileResetPoints
	if points then points[new], points[old] = points[old], nil end
	-- (Other characters with it as their own go back to the account's next login.)
	for _, holder in ipairs({ ns.db, ns.chardb }) do
		if holder.profile == old then holder.profile = new end
	end
	if ns.db.liveProfile == old then ns.db.liveProfile = new end
	return true
end

-- Deleting the active one switches to the default profile first.
function ns.DeleteProfile(name)
	if builtinByName[name] then return false end
	if name == ns.ActiveProfile() and ns.ProfileSwitchBlocked() then return false end
	if ns.BackupDeleted then ns.BackupDeleted(name) end -- (its last copy kept a while: Backups.lua)
	if name == ns.ActiveProfile() then ns.SetProfile(DEFAULT_PROFILE) end
	if ns.db.profile == name then ns.db.profile = DEFAULT_PROFILE end
	ns.db.profiles[name] = nil
	ns.db.profileNotes[name] = nil
	ns.db.profileIcons[name] = nil
	ns.ForgetResetPoint(name)
	return true
end

local AgainstDefaults -- (below)

-- Reset points: a profile's settings as the player saved them, for Reset
-- profile and each page's Reset to go back to instead of the profile's
-- base. db.profileResetPoints[name] is stored as the profile is (changes
-- from its base, and its lists), so settings it doesn't change still follow
-- a built-in's values as they're updated.
function ns.HasResetPoint(name)
	local points = ns.db and ns.db.profileResetPoints
	return points ~= nil and points[name or ns.ActiveProfile()] ~= nil
end

function ns.SaveResetPoint(name)
	name = name or ns.ActiveProfile()
	if name == ns.ActiveProfile() then ns.SaveProfile() end
	ns.db.profileResetPoints = ns.db.profileResetPoints or {}
	-- (The one it replaces kept among the backups, to go back to: Backups.lua.)
	local old = ns.db.profileResetPoints[name]
	if old and ns.BackupProfile then
		ns.BackupProfile(name, "save", AgainstDefaults(old, ns.ProfileBase(name)))
	end
	ns.db.profileResetPoints[name] = CopyTable(ns.db.profiles[name] or {})
	ns.Log("state", "reset point saved: " .. name)
end

function ns.ForgetResetPoint(name)
	if ns.db.profileResetPoints then ns.db.profileResetPoints[name or ns.ActiveProfile()] = nil end
end

-- What a Reset goes back to: the profile's base, with its reset point on top.
function ns.ResetBase(name)
	name = name or ns.ActiveProfile()
	local base = ns.ProfileBase(name)
	local point = ns.db.profileResetPoints and ns.db.profileResetPoints[name]
	if not point then return base end
	local values = {}
	for k, v in pairs(base) do values[k] = v end
	for k, v in pairs(point) do values[k] = v end
	return WithRuleDefaults(values) -- (a point saved before a row had its rule)
end

-- Back to the profile's reset point if it has one, else its base: a
-- built-in's own values, or the defaults. True once done (false: in a fight).
function ns.ResetProfile()
	if ns.ProfileSwitchBlocked() then return false end
	local name = ns.ActiveProfile()
	if ns.BackupProfile then ns.BackupProfile(name, "reset") end -- (Backups.lua)
	local point = ns.db.profileResetPoints and ns.db.profileResetPoints[name]
	ns.db.profiles[name] = point and CopyTable(point) or nil
	-- (The game switches back to the profile's too: the Cooldown Manager or
	-- personal resource display turned on again if the player had switched it off.)
	for _, switch in ipairs(PROFILE_SWITCHES) do ns.db[switch.leftAlone] = nil end
	Load(name)
	SettingsChanged()
	return true
end

-- Kept by Reset Settings: what you made, and what the addon learned as you
-- played (not settings: losing them only makes it learn again).
local RESET_KEEPS = {
	"profileBackups", "deletedProfiles", "profileBackupsKeep", "profileBackupsDaily", -- (Backups.lua)
	"profileResetPoints", -- (your profiles' reset points)
	"cameraScripts", "customWheels", -- (your scripts, your own wheels)
	"zoneTints", "zonePresets", "zoneTintStrength", "timePhaseColors", "timePhaseStrength", -- (tints you picked)
	"extraFrames", -- (frames you added)
	"devEdits", -- (the dev copy's Module Editor)
	"flightTimes", "questDrops", "frameAddons", "smartFindLooks", "goodSpeeds", "selfTest",
}
-- What a built-in profile keeps of your changes on Reset Settings: the lists
-- you made in it (its settings go back to the built-in's).
local RESET_PROFILE_KEEPS = {
	"cameraRows", -- (your cameras and triggers)
	-- (Not frameRules: every Show in row's rule is a setting now, reset with
	-- the rest, at the user's ask.)
	"lowHealthMyThemes", "lowHealthThemeEdits", -- (your Vitals themes, and your versions of ours)
	"markNames", -- (the Nameplates page's rows' own names)
}

-- Back to a fresh install, and the UI reloads so it starts over (the welcome
-- window too). Every character back on the default profile, the account's
-- next login. settingsOnly (Reset Settings): every setting goes back, but
-- nothing you made: your own profiles stay as they are, the built-ins keep
-- the cameras, rules, themes and nameplate rows you made in them (their
-- changes backed up first), and your scripts, wheels, tints, backups and what
-- the addon learned stay. Without it (Reset Everything): all of it goes.
function ns.ResetAddon(settingsOnly)
	-- (Not in a fight: Edit Mode's layouts can't change then.)
	if ns.ResetLayouts and not ns.ResetLayouts() then
		ns.Print(L["can't reset Cinematic in a fight: try again once it's over"])
		return
	end
	-- The Cooldown Manager and personal resource display off again if a
	-- profile turned them on.
	for _, switch in ipairs(PROFILE_SWITCHES) do
		if ns.db[switch.turnedOn] and GetCVar(switch.cvar) == "1" then SetCVar(switch.cvar, "0") end
	end
	-- The game's own settings put back first: Graphics+'s and those held for
	-- a feature (savedCVars). Wiped unrestored, ours stayed written for good
	-- and Graphics+ took them for the game's own.
	if ns.GraphicsPlusPutBack then ns.GraphicsPlusPutBack() end
	if ns.db.savedCVars then
		local held = {}
		for cvar in pairs(ns.db.savedCVars) do held[#held + 1] = cvar end
		for _, cvar in ipairs(held) do ns.RestoreCVar(cvar) end
	end
	-- (The dev copy keeps the Vitals Vision theme looks made with DEV SET
	-- DEFAULT: work for LowHealthThemes.lua, not settings. resetKept: still a
	-- fresh install to Core.lua.)
	local kept = {}
	kept.vitalsThemeEdits = ns.isDev and CinematicDB and CinematicDB.vitalsThemeEdits or nil
	-- (The dev copy keeps the flight times learned, Reset Everything too: each
	-- route takes a flight to learn again. The speed scale goes with them, as
	-- the times are saved at it: Camera.lua's RecordFlightTime.)
	if ns.isDev and type(ns.db.flightTimes) == "table" and next(ns.db.flightTimes) ~= nil then
		kept.flightTimes = ns.db.flightTimes
		kept.flightSpeedScale = ns.db.flightSpeedScale
	end
	if settingsOnly then
		ns.SaveProfile()
		local profiles = {}
		for name, saved in pairs(ns.db.profiles) do
			if type(saved) ~= "table" then
				-- (nothing to keep)
			elseif not builtinByName[name] and not allBuiltinNames[name] and not otherClientRetired[name] then
				profiles[name] = saved -- (your own: as it is)
			else
				-- A built-in: its changes backed up, then only what you made in it.
				if next(saved) and ns.BackupProfile and builtinByName[name] then ns.BackupProfile(name, "reset") end
				local mine = {}
				for _, k in ipairs(RESET_PROFILE_KEEPS) do
					if type(saved[k]) == "table" and next(saved[k]) ~= nil then mine[k] = saved[k] end
				end
				EachRowSetting(saved, function(k, v) mine[k] = v end) -- (Nameplates rows you added)
				if next(mine) then
					-- (With the once-only marks, as below: some updates mark each
					-- profile, Core.lua's TargetUpgrades. Built-ins' saved changes
					-- carry none, so the db's.)
					for k, v in pairs(ns.db) do
						if v == true and type(k) == "string" and k:find("V%d+$") and ns.DEFAULTS[k] == nil then mine[k] = v end
					end
					profiles[name] = mine
				end
			end
		end
		kept.profiles = profiles
		for _, k in ipairs(RESET_KEEPS) do
			local v = ns.db[k]
			if type(v) == "table" and next(v) ~= nil then kept[k] = v end
		end
		-- The once-only updates done (Core.lua's ...V1, ...V2 marks): the kept
		-- profiles have them already. Without the marks they ran again at the
		-- reload, writing their old values into the built-ins (the profile came
		-- up "(changed)" straight after a reset) and over your own profiles.
		for k, v in pairs(ns.db) do
			if v == true and type(k) == "string" and k:find("V%d+$") and ns.DEFAULTS[k] == nil then kept[k] = v end
		end
	end
	if next(kept) then kept.resetKept = true end
	CinematicDB = next(kept) and kept or nil
	-- (The character's memory of play stays: places Discovered's card has
	-- shown, talking heads heard. Not settings, and losing them replays them.)
	local char = CinematicCharDB
	CinematicCharDB = char and (char.cardSeen or char.talkingHeadSeen)
		and { cardSeen = char.cardSeen, talkingHeadSeen = char.talkingHeadSeen } or nil
	ns.db.profiles = {} -- (so logout's ns.SaveProfile writes into nothing kept)
	ReloadUI()
end

-- Settings changed from the active profile's base, for the Profiles page's
-- "(changed)". (Not the lists: those are tables whatever's in them. Nor what
-- the Vitals theme put on: LowHealth.lua's SyncThemeLook, not the player.)
function ns.ProfileChanged()
	local base = ns.ProfileBase()
	local fromTheme = type(ns.db.lowHealthFromTheme) == "table" and ns.db.lowHealthFromTheme.values or {}
	for k in pairs(ns.DEFAULTS) do
		if IsProfileKey(k) and ns.db[k] ~= base[k] and not (fromTheme[k] ~= nil and fromTheme[k] == ns.db[k]) then
			return true
		end
	end
	return false
end

-- /cine debug changed: what makes the Profiles page say "(changed)", each
-- setting with its value, the profile's and the default.
function ns.ProfileChangedDebug()
	local base = ns.ProfileBase()
	local fromTheme = type(ns.db.lowHealthFromTheme) == "table" and ns.db.lowHealthFromTheme.values or {}
	local keys = {}
	for k in pairs(ns.DEFAULTS) do
		if IsProfileKey(k) and ns.db[k] ~= base[k] and not (fromTheme[k] ~= nil and fromTheme[k] == ns.db[k]) then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys)
	local head = ("profile %s, changed %s, picked %s, new install %s, Vitals theme %s: %d setting(s) differ")
		:format(tostring(ns.ActiveProfile()), tostring(ns.ProfileChanged()), tostring(ns.db.profileChosen), tostring(ns.newInstall),
			tostring(ns.db.lowHealthTheme), #keys)
	ns.Print(head) -- (printed lines go in the log too: Diagnostics.lua)
	for _, k in ipairs(keys) do
		ns.Print(("%s = %s (profile's %s, default %s)"):format(k, tostring(ns.db[k]), tostring(base[k]),
			tostring(ns.DEFAULTS[k])))
	end
end

-- A profile's saved changes over its base, as changes from the defaults
-- (as your own profiles are stored), and its lists.
function AgainstDefaults(saved, base)
	local shared = {}
	for k, default in pairs(ns.DEFAULTS) do
		if IsProfileKey(k) then
			local value = saved[k]
			if value == nil then value = base[k] end
			if value ~= default then shared[k] = CopyTable(value) end
		end
	end
	for _, k in ipairs(PROFILE_TABLES) do
		local list = saved[k] or base[k]
		if type(list) == "table" and next(list) ~= nil then shared[k] = CopyTable(list) end
	end
	EachRowSetting(saved, function(k, v) shared[k] = v end)
	return shared
end

-- A profile's settings for sharing (Share.lua): what differs from the
-- defaults, and its lists. (Against the defaults, not a built-in's values,
-- so it comes out the same on a version whose built-ins have changed.)
function ns.ProfileForSharing(name)
	if name == ns.ActiveProfile() then ns.SaveProfile() end
	return AgainstDefaults(ns.db.profiles[name] or {}, ns.ProfileBase(name))
end

-- Whether a shared setting is one this version has: a list, or a setting
-- of the same kind as its default. (The rest are skipped on import.)
function ns.KnownProfileSetting(key, value)
	if type(key) ~= "string" then return false end
	for _, k in ipairs(PROFILE_TABLES) do
		if k == key then return type(value) == "table" end
	end
	local default = ns.DEFAULTS[key]
	-- (An old grid's setting, from before they went over: kept, to go over as it's added.)
	if default == nil then default = ns.OldGridDefault(key) end
	-- (A row added on the Style hub's Nameplates page: as its kind's.)
	if default == nil then default = ns.MarkRowDefault(key) end
	return default ~= nil and IsProfileKey(key) and type(value) == type(default)
end

-- A new profile of your own from shared settings (stored against the
-- defaults, as your own are), switched to.
function ns.AddSharedProfile(name, settings, note, icon)
	if ns.ProfileExists(name) then return false end
	if ns.ProfileSwitchBlocked() then return false end -- (switched to below)
	-- (One shared from before the old grids went over: theirs go over now.)
	ns.ConvertOffGrids(settings, ns.OldGridDefault, { switches = true })
	ns.db.profileIcons[name] = icon or ns.UnusedProfileIcon()
	ns.db.profiles[name] = settings
	ns.db.profileNotes[name] = note
	ns.SetProfile(name)
	ns.Log("state", "profile imported: " .. name)
	return true
end

-- Ticked: this character keeps the profile it's on as its own, and
-- switching changes only its. Unticked: back to the account's profile.
function ns.SetCharacterProfile(own)
	if own then
		ns.chardb.profile = ns.ActiveProfile()
	elseif ns.IsCharacterProfile() then
		-- (Back to the account's: a switch, so not in a fight.)
		if ns.db.profile ~= ns.ActiveProfile() and ns.ProfileSwitchBlocked() then return end
		ns.chardb.profile = nil
		if ns.db.profile ~= ns.ActiveProfile() then
			ns.SaveProfile()
			ns.db.liveProfile = ns.db.profile
			Load(ns.db.profile)
			SettingsChanged()
		end
	end
end

-- After the settings load (Core.lua). Settings from before profiles become
-- the default profile's, changes and all.
function ns.InitProfiles()
	CinematicCharDB = CinematicCharDB or {}
	ns.chardb = CinematicCharDB
	local db, chardb = ns.db, ns.chardb
	db.profiles = db.profiles or {}
	db.profileNotes = db.profileNotes or {}
	db.profileIcons = db.profileIcons or {}
	db.devRecipes, db.devModules = nil, nil -- (the Profile Builder's changes, from before the Module Editor)
	-- Built-ins called something else before (retired ones' too): their
	-- settings and picks move over.
	local liveRenamed = false
	local renaming = {}
	for _, list in ipairs({ ns.BUILTIN_PROFILES, retiredHere }) do
		for _, profile in ipairs(list) do renaming[#renaming + 1] = profile end
	end
	for _, profile in ipairs(renaming) do
		for _, old in ipairs(profile.oldNames or {}) do
			if db.profiles[old] and not db.profiles[profile.name] then
				db.profiles[profile.name], db.profiles[old] = db.profiles[old], nil
			end
			for _, holder in ipairs({ db, chardb }) do
				if holder.profile == old then holder.profile = profile.name end
			end
			if db.liveProfile == old then
				db.liveProfile = profile.name
				liveRenamed = true
			end
		end
	end
	-- Built-ins no longer offered (ns.RETIRED_PROFILES): one you're on or
	-- have saved becomes a profile of your own, named as it was shown, its
	-- settings as they were. Characters with it as theirs follow when they
	-- next log in (db.retiredProfiles: the old name, and what it's called now).
	db.retiredProfiles = db.retiredProfiles or {}
	for _, profile in ipairs(retiredHere) do
		local old = profile.name
		local inUse = db.profile == old or db.liveProfile == old or chardb.profile == old
		if profile.client == "forever" then
			-- (Forever's old built-ins date from before it was out: nobody's to
			-- keep, so only the three built-ins show. Ones kept before go too;
			-- whoever was on one gets the default profile, below.)
			local kept = db.retiredProfiles[old]
			if kept and db.profileNotes[kept]
				and db.profileNotes[kept]:find(profile.label or old, 1, true) then
				db.profiles[kept], db.profileIcons[kept], db.profileNotes[kept] = nil, nil, nil
			end
			db.profiles[old], db.retiredProfiles[old] = nil, nil
		elseif (db.profiles[old] or inUse) and not db.retiredProfiles[old] then
			-- (The live one's settings as they are now; others' as saved.)
			local saved = db.liveProfile == old and Snapshot(old) or db.profiles[old] or {}
			local own = AgainstDefaults(saved, ns.ProfileBase(old))
			db.profiles[old] = nil
			local label = profile.label or old
			local name, n = label, 1
			while ns.ProfileExists(name) do
				n = n + 1
				name = label .. " " .. n
			end
			db.profiles[name] = own
			db.profileIcons[name] = profile.icon
			db.profileNotes[name] = L["Kept from the %s profile, which Cinematic no longer has."]:format(label)
			db.retiredProfiles[old] = name
		end
		local moved = db.retiredProfiles[old]
		if moved then
			for _, holder in ipairs({ db, chardb }) do
				if holder.profile == old then holder.profile = moved end
			end
			if db.liveProfile == old then db.liveProfile = moved end
		end
	end
	wipe(baseCache) -- (worked out under the old names before)
	-- Your own profiles made before they had icons get one each.
	for _, name in ipairs(ns.ProfileNames()) do
		if not builtinByName[name] and not db.profileIcons[name] then
			db.profileIcons[name] = ns.UnusedProfileIcon()
		end
	end
	-- Only a new player is asked to pick one (Welcome.lua); everyone else has
	-- their settings already.
	if db.profileChosen == nil then
		db.profileChosen = not ns.newInstall
	end
	if not db.profile or not ns.ProfileExists(db.profile) then
		db.profile = DEFAULT_PROFILE
	end
	-- (One deleted or renamed on another character: the account's again.)
	if chardb.profile and not ns.ProfileExists(chardb.profile) then
		chardb.profile = nil
	end
	db.liveProfile = db.liveProfile or db.profile
	local wanted = chardb.profile or db.profile
	if wanted ~= db.liveProfile then
		LeaveOffState() -- (loaded over below: switched off again after)
		if ns.ProfileExists(db.liveProfile) then ns.SaveProfile() end
		db.liveProfile = wanted
		Load(wanted)
	elseif liveRenamed or ns.newInstall then
		LeaveOffState()
		-- (The one in use renamed: loaded again from its saved changes, so what
		-- its new built-in adds, like retail's own action bar groups, comes in.
		-- A fresh install or Reset addon too: the default profile's own lists,
		-- like those groups, aren't in the defaults the live settings start from.)
		Load(wanted)
	end
	-- (No profile picked yet: every page off till one is.)
	if not db.profileChosen then ns.SwitchOffUntilPicked() end
	ns.WarmPartValues()
end
