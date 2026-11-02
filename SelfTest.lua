-- Cinematic: /cine selftest, a quick look at whether the game still is as the
-- addon expects, on whichever client it runs.
--
-- Each check only reads (nothing is changed, loaded or hooked) and comes out
-- as a short value ("yes", "nil", "secret", "35/0"...). A check with a
-- tested value for this client (expect) passes or fails by it; one without
-- is compared with the last run on this client, so a change after a game
-- patch shows as "changed". Checks that need a situation (a target, out of
-- combat) are skipped without it. Every result goes in the log (and the
-- copy window); the values are kept in CinematicDB.selfTest[client] for the
-- next run's comparison.
local _, ns = ...

-- The client by game number (GetBuildInfo's fourth value): retail, Classic
-- Era (11509) or WoW Forever (16001). Another game number goes by its own.
local function Client()
	local _, build, _, interface = GetBuildInfo()
	interface = tonumber(interface) or 0
	local key = interface >= 100000 and "retail" or (interface >= 16000 and interface < 20000) and "forever"
		or (interface >= 10000 and interface < 16000) and "era" or ("game" .. interface)
	return key, interface, build
end

-- A value as a short text; secret values say so without being read.
local function Show(value)
	if issecretvalue and issecretvalue(value) then return "secret" end
	local kind = type(value)
	if kind == "nil" or kind == "boolean" then return tostring(value) end
	if kind == "number" then return ("%g"):format(value) end
	if kind == "string" then return value end
	return kind
end

-- A dotted path ("C_Spell.GetSpellInfo", "Minimap.PingLocation") from _G, or nil.
local function Lookup(path)
	local value = _G
	for part in path:gmatch("[^.]+") do
		if type(value) ~= "table" then return nil end
		local ok, field = pcall(function() return value[part] end)
		if not ok then return nil end
		value = field
	end
	return value
end

local function Exists(path)
	return Lookup(path) ~= nil and "yes" or "no"
end

-- Plain or secret, as a boolean is read now (nil when there's no API).
local function Plainness(read)
	local ok, value = pcall(read)
	if not ok then return "error" end
	if value == nil then return "nil" end
	return (issecretvalue and issecretvalue(value)) and "secret" or "plain"
end

-- Our lines in the log since this session started.
local function CountLogged(category)
	local log, count = ns.db and ns.db.log or {}, 0
	local pattern = " " .. category .. ": "
	for i = #log, 1, -1 do
		local line = log[i]
		if line:find(" session: ---- ", 1, true) then break end
		if line:find(pattern, 1, true) then count = count + 1 end
	end
	return tostring(count)
end

local function TargetPlate()
	if not UnitExists("target") or not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	return ok and plate and plate.UnitFrame or nil
end

local function NeedsTargetPlate()
	if not UnitExists("target") then return "needs a target" end
	if not TargetPlate() then return "needs your target's nameplate on screen" end
end

local function NeedsCalm()
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then return "needs you out of combat" end
end

local ALL_YES = { retail = "yes", forever = "yes", era = "yes" }

-- { group, name, run, expect = { client = value }, needs = fn -> reason or nil }
local CHECKS = {}
local function Check(group, name, run, expect, needs)
	CHECKS[#CHECKS + 1] = { group = group, name = name, run = run, expect = expect, needs = needs }
end

-- The addon itself.
Check("addon", "stopped (/cine panic or a looping error)", function() return Show(ns.IsSuspended()) end,
	{ retail = "false", forever = "false", era = "false" })
Check("addon", "our Lua errors this session", function() return CountLogged("ERROR") end,
	{ retail = "0", forever = "0", era = "0" })
Check("addon", "our blocked actions this session", function() return CountLogged("BLOCKED") end,
	{ retail = "0", forever = "0", era = "0" })
-- (A word default can also take a number: menus of "auto" or "none" and file
-- numbers, such as lowHealthGameMask.)
Check("addon", "settings of the wrong type", function()
	local wrong = {}
	for key, default in pairs(ns.DEFAULTS) do
		local value = ns.db[key]
		local kind = type(value)
		if value ~= nil and kind ~= type(default) and not (type(default) == "string" and kind == "number") then
			wrong[#wrong + 1] = key
		end
	end
	table.sort(wrong)
	return #wrong == 0 and "none" or table.concat(wrong, ", ")
end, { retail = "none", forever = "none", era = "none" })
Check("addon", "client flags (isRetail, isClassicEra)", function()
	return Show(ns.isRetail) .. ", " .. Show(ns.isClassicEra)
end, { retail = "true, false", forever = "false, false", era = "false, true" })

-- Game functions the addon calls without asking first: every client has them.
for _, path in ipairs({
	"hooksecurefunc", "C_Timer.After", "C_Timer.NewTicker", "GetCVar", "SetCVar", "GetCameraZoom",
	"CameraZoomIn", "CameraZoomOut", "MoveViewLeftStart", "MoveViewLeftStop", "MoveViewRightStart",
	"MoveViewUpStart", "SetView", "SaveView", "InCombatLockdown", "UnitAffectingCombat", "GetUnitSpeed",
	"IsMounted", "UnitOnTaxi", "IsResting", "C_NamePlate.GetNamePlateForUnit", "CheckInteractDistance",
}) do
	Check("game API", path, function() return Exists(path) end, ALL_YES)
end

-- Game functions the addon asks for first, as they differ by client.
local API_EXPECT = {
	C_LootHistory = { forever = "yes" },
	C_Console = { forever = "no" },
	issecretvalue = { forever = "yes", retail = "yes" },
	["Settings.GetSetting"] = { forever = "yes", retail = "yes" },
	FCF_StartAlertFlash = { forever = "yes" },
	["C_Spell.GetSpellInfo"] = { era = "yes" },
}
for _, path in ipairs({
	"issecretvalue", "C_Secrets.ShouldAurasBeSecret", "C_LootHistory", "C_Console", "C_CooldownViewer",
	"C_GamePad.GetDeviceMappedState", "C_DamageMeter", "C_UnitAuras.GetAuraDataByIndex", "UnitAura", "UnitDebuff",
	"CombatLogGetCurrentEventInfo", "UnitHealthPercent", "CurveConstants", "C_Spell.GetSpellInfo",
	"C_Spell.GetSpellCooldown", "Settings.GetSetting", "FCF_StartAlertFlash", "UnitCastingDuration",
	"UnitDistanceSquared", "C_AddOns.GetAddOnMetadata",
}) do
	Check("client API", path, function() return Exists(path) end, API_EXPECT[path])
end

-- Blizzard frames and fields we fade or hook.
local FRAME_EXPECT = {
	PersonalResourceDisplayFrame = { forever = "yes" },
	["PersonalResourceDisplayFrame.PowerBar"] = { forever = "yes" },
	["PersonalResourceDisplayFrame.ClassFrameContainer"] = { forever = "yes" },
	["PersonalResourceDisplayFrame.HealthBarsContainer"] = { forever = "yes" },
	GamepadMainActionBarFrame = { forever = "yes" },
	GroupLootHistoryFrame = { forever = "yes" },
	CHAT_FRAMES = ALL_YES,
	ChatFrame1Tab = ALL_YES,
	Minimap = ALL_YES,
}
for _, path in ipairs({
	"PersonalResourceDisplayFrame", "PersonalResourceDisplayFrame.PowerBar",
	"PersonalResourceDisplayFrame.ClassFrameContainer", "PersonalResourceDisplayFrame.HealthBarsContainer",
	"GamepadMainActionBarFrame", "GroupLootHistoryFrame", "EssentialCooldownViewer", "Minimap",
	"Minimap.PingLocation", "CHAT_FRAMES", "ChatFrame1Tab", "LootHistoryFrame", "DebuffFrame",
}) do
	Check("frames", path, function() return Exists(path) end, FRAME_EXPECT[path])
end

-- Known quirks (see each note): a change means a workaround may be wrong, or no longer needed.
for _, name in ipairs({ "DUEL_WINNER", "DUEL_FLED" }) do
	Check("quirks", name .. " text", function() return _G[name] == nil and "nil" or "set" end,
		{ forever = "nil" })
end
Check("quirks", "Character Models setting (PROXY_CHARACTER_MODELS_TOGGLE)", function()
	if not (Settings and Settings.GetSetting) then return "no API" end
	local ok, setting = pcall(Settings.GetSetting, "PROXY_CHARACTER_MODELS_TOGGLE")
	return (ok and setting) and "yes" or "no"
end, { forever = "yes" })
for _, cvar in ipairs({ "nameplateSelectedAlpha", "nameplateNotSelectedAlpha", "nameplateMinAlpha",
	"nameplateMaxAlpha" }) do
	Check("quirks", cvar .. " exists", function()
		local ok, value = pcall(GetCVar, cvar)
		return (ok and value ~= nil) and "yes" or "no"
	end, { forever = "yes" })
end
Check("quirks", "GamePadEnable", function() return Show(GetCVar("GamePadEnable")) end)
Check("quirks", "Auto Shot range (min/max)", function()
	if not (C_Spell and C_Spell.GetSpellInfo) then return "no API" end
	local info = C_Spell.GetSpellInfo(75)
	if not info then return "nil" end
	return Show(info.minRange) .. "/" .. Show(info.maxRange)
end, { era = "35/0" })
Check("quirks", "auras secret out of combat", function()
	local secrets = _G.C_Secrets
	if not (secrets and secrets.ShouldAurasBeSecret) then return "no API" end
	return Show(secrets.ShouldAurasBeSecret())
end, { retail = "false", forever = "false" }, NeedsCalm)

-- What reads secret now (no tested values: compared with the last run).
Check("secret now", "UnitHealth player", function() return Plainness(function() return UnitHealth("player") end) end)
Check("secret now", "EssentialCooldownViewer:IsShown()", function()
	local frame = _G.EssentialCooldownViewer
	if not frame then return "no frame" end
	return Plainness(function() return frame:IsShown() end)
end)
Check("secret now", "UnitName target", function() return Plainness(function() return UnitName("target") end) end,
	nil, function() if not UnitExists("target") then return "needs a target" end end)

-- Your target's nameplate parts (PlateParts.lua and the plate styles go by these).
local PLATE_EXPECT = {
	PlayerLevelDiffFrame = { forever = "yes" },
	CastBarsContainer = ALL_YES,
	["CastBarsContainer.castBar"] = ALL_YES,
	HealthBarsContainer = { forever = "yes" },
	healthBar = { forever = "yes" },
	["healthBar.selectedBorder"] = { forever = "yes" },
	AurasFrame = { forever = "yes" },
	ClassificationFrame = { forever = "yes" },
}
for _, path in ipairs({
	"PlayerLevelDiffFrame", "LevelFrame", "CastBarsContainer", "CastBarsContainer.castBar", "HealthBarsContainer",
	"healthBar", "healthBar.selectedBorder", "AurasFrame", "ClassificationFrame", "SoftTargetFrame", "name",
}) do
	Check("target plate", path, function()
		local value = TargetPlate()
		for part in path:gmatch("[^.]+") do
			if type(value) ~= "table" then return "no" end
			value = value[part]
		end
		return value ~= nil and "yes" or "no"
	end, PLATE_EXPECT[path], NeedsTargetPlate)
end

local COLORS = { failed = "ff4040", error = "ff4040", changed = "ffd100", skipped = "909090" }

function ns.SelfTest()
	local client, interface, build = Client()
	ns.db.selfTest = ns.db.selfTest or {}
	local last = ns.db.selfTest[client] and ns.db.selfTest[client].results or {}
	local results, counts, shown = {}, { ok = 0, failed = 0, changed = 0, skipped = 0, error = 0 }, {}

	for _, check in ipairs(CHECKS) do
		local key = check.group .. ": " .. check.name
		local status, value, note
		local reason = check.needs and check.needs()
		if reason then
			status, note = "skipped", reason
		else
			local ok, got = pcall(check.run)
			if not ok then
				status, value, note = "error", "error", tostring(got)
			else
				value = got
				local expected = check.expect and check.expect[client]
				if expected then
					status = value == expected and "ok" or "failed"
					if status == "failed" then note = "expected " .. expected end
				elseif last[key] ~= nil and last[key] ~= value then
					status, note = "changed", "was " .. last[key]
				else
					status = "ok"
				end
			end
			results[key] = value
		end
		-- (A skipped check keeps its last value for next time.)
		if status == "skipped" then results[key] = last[key] end
		counts[status] = counts[status] + 1
		local line = ("%s: %s%s"):format(key, value or "-", note and (" (" .. note .. ")") or "")
		ns.Log("selftest", status .. "  " .. line)
		if status ~= "ok" and status ~= "skipped" then
			shown[#shown + 1] = ("  |cff%s%s|r %s"):format(COLORS[status], status, line)
		end
	end

	ns.db.selfTest[client] = { when = date("%Y-%m-%d %H:%M"), build = tostring(build), game = interface,
		results = results }
	ns.Print(("selftest on %s (game %d, build %s): %d ok, %d failed, %d changed, %d skipped%s"):format(client,
		interface, tostring(build), counts.ok, counts.failed + counts.error, counts.changed, counts.skipped,
		counts.error > 0 and (" (" .. counts.error .. " of them errors)") or ""))
	for _, line in ipairs(shown) do print(line) end
	if counts.skipped > 0 then
		print("  skipped checks need a situation (a target with its nameplate, out of combat): run it again then")
	end
end
