-- Cinematic: scenes of your own, and triggers of yours on any scene. A scene
-- (a Cameras page row: CameraRows.lua's camera, music, CineMode, When,
-- copies) plays its camera when any of its triggers happens: an emote, a
-- spell cast, a buff, a place, a moment (leveling up...), a state
-- (mounted...) or one of five key bindings. Built-in scenes whose camera runs
-- while you stand still can take triggers of yours beside their own. Each
-- trigger is one of the library's (TriggerLibrary.lua, the Triggers page),
-- with its own phase, Only if, endings, timing and priority: each takes its
-- place in the priority list (Triggers.lua) by its number.
--
-- Saved in db.cameraRows with the rows (so profiles, Save/Reset and share
-- strings carry them): "custom" the ids of yours (MineA, MineB...: letters
-- only, as a row id is a scene key and a copy number), "extras" the built-in
-- scenes with triggers of yours, and per scene:
--   triggers  "|" between sources: "t:<id>", a trigger of the library. Written
--             before the library (moved into it as the scenes sync,
--             TriggerLibrary.lua's MigrateSceneTriggers), "<kind>:<what>": emote:cheer,
--             spell:7620 or spell:fishing, aura:<id or name>,
--             place:<zone or subzone name>,
--             moment:levelup|achievement|quest|boss|alive,
--             state:mounted|swimming|flying|indoors|outdoors|resting|stealthed|night,
--             interact:mail|bank|auction|map|npc (its window open: these
--             play with it open, where other cameras wait for it to close),
--             key:1-5 (a scene of yours from before: one in "source")
--   until     (yours, before the library) move (nil), ends, time:<sec>, key
--   after     (yours, before the library) the built-in source it comes after
--
-- Each trigger is on for an episode: it starts as its thing happens (a state:
-- as it becomes true, or false for its other phase) and lasts until one of
-- its endings, or until you move (moving ends every standing-still camera).
-- A state still true after its episode ended doesn't start another until
-- it's been false (unless its "rearm" is off).
local _, ns = ...
local L = ns.L

ns.CUSTOM_TRIGGER_MAX = 20 -- (scenes of your own)
ns.SCENE_TRIGGER_MAX = 6 -- (triggers in a scene)
-- What can start one, in the editor's order (CameraTriggerEditor.lua), with
-- the choices of the kinds that have a fixed list.
ns.CUSTOM_TRIGGER_KINDS = {
	{ value = "emote", text = L["Emote"] }, { value = "spell", text = L["Spell cast"] },
	{ value = "aura", text = L["Buff on you"] }, { value = "place", text = L["Place"] },
	{ value = "moment", text = L["Moment"] }, { value = "state", text = L["State"] },
	{ value = "interact", text = L["Interaction"] }, { value = "key", text = L["Key binding"] },
}
ns.CUSTOM_TRIGGER_MOMENTS = {
	{ value = "levelup", text = L["You level up"] }, { value = "achievement", text = L["You earn an achievement"] },
	{ value = "quest", text = L["You turn in a quest"] }, { value = "boss", text = L["Your group kills a boss"] },
	{ value = "alive", text = L["You come back to life"] },
}
ns.CUSTOM_TRIGGER_STATES = {
	{ value = "mounted", text = L["Mounted"] }, { value = "swimming", text = L["Swimming"] },
	{ value = "flying", text = L["Flying"] }, { value = "indoors", text = L["Indoors"] },
	{ value = "outdoors", text = L["Outdoors"] }, { value = "resting", text = L["Resting (an inn or a city)"] },
	{ value = "stealthed", text = L["Stealthed"] }, { value = "night", text = L["Night (game time)"] },
}
ns.CUSTOM_TRIGGER_INTERACTIONS = {
	{ value = "mail", text = L["At a mailbox"] }, { value = "bank", text = L["At the bank"] },
	{ value = "auction", text = L["At the auction house"] }, { value = "map", text = L["World map open"] },
	{ value = "npc", text = L["Talking to an NPC (chat, vendor, trainer)"] },
}
ns.CUSTOM_TRIGGER_KEYS = {}
for n = 1, 5 do
	ns.CUSTOM_TRIGGER_KEYS[n] = { value = tostring(n), text = (L["Custom camera trigger %d"]):format(n) }
end
ns.OnLanguage(function()
	for _, list in ipairs({ ns.CUSTOM_TRIGGER_KINDS, ns.CUSTOM_TRIGGER_MOMENTS, ns.CUSTOM_TRIGGER_STATES,
		ns.CUSTOM_TRIGGER_INTERACTIONS }) do
		ns.TranslateFields(list, "text")
	end
	for n, each in ipairs(ns.CUSTOM_TRIGGER_KEYS) do each.text = (L["Custom camera trigger %d"]):format(n) end
end)
local function ChoiceText(list, value)
	for _, each in ipairs(list) do
		if each.value == value then return each.text end
	end
end
-- The cameras one can play: those that run where you stand (the tele
-- camera with a pretend cast, the death camera as its test runs it), and
-- camera scripts (CameraScripts.lua puts them in before "none").
local CAMERAS = { "cozy", "vista", "fish", "afk", "tele", "death", "none" }
ns.CUSTOM_TRIGGER_CAMERAS = CAMERAS
local DEATH_FOR = 3600 -- seconds: the death camera's run with no time of its own (moving or Stop ends it)
local DEFAULT_SECS = 5 -- a moment's (or an instant cast's) camera, when its until doesn't say
local TICK = 0.1 -- seconds between looks at the states
local SLOW_LOOK = 1 -- seconds between looks at buffs and places with no event

-- Moments: their game events (a boss only when the fight was won).
local MOMENT_EVENTS = {
	levelup = { "PLAYER_LEVEL_UP" }, achievement = { "ACHIEVEMENT_EARNED" }, quest = { "QUEST_TURNED_IN" },
	boss = { "ENCOUNTER_END" }, alive = { "PLAYER_UNGHOST", "PLAYER_ALIVE" },
}
local SPELL_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }
local PLACE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }
local CAST_START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true }
local CAST_END = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_FAILED = true }

-- States: read on the tick, by the game's function's name (a client may lack one).
local STATE_API = { mounted = "IsMounted", swimming = "IsSwimming", flying = "IsFlying", indoors = "IsIndoors",
	outdoors = "IsOutdoors", resting = "IsResting", stealthed = "IsStealthed" }
local function StateNow(what)
	if what == "night" then
		local hour = GetGameTime and GetGameTime()
		return type(hour) == "number" and (hour >= 21 or hour < 6)
	end
	local fn = _G[STATE_API[what] or ""]
	if not fn then return false end
	local ok, value = pcall(fn)
	return ok and ns.Flag(value) or false
end
-- Interactions: their windows (each client names some differently; some
-- load only when first opened), read on the tick as the states are.
local INTERACT_FRAMES = { mail = { "MailFrame" }, bank = { "BankFrame" },
	auction = { "AuctionHouseFrame", "AuctionFrame" }, map = { "WorldMapFrame" },
	npc = { "GossipFrame", "MerchantFrame", "ClassTrainerFrame" } }
local function InteractNow(what)
	for _, name in ipairs(INTERACT_FRAMES[what] or {}) do
		local frame = _G[name]
		if type(frame) == "table" and frame.IsShown then
			local ok, shown = pcall(frame.IsShown, frame)
			if ok and ns.Flag(shown) then return true end
		end
	end
	return false
end

-- A buff on you by spell ID or name (lower case). On retail your own buffs
-- can't be read in fights: false then (the camera waits out a fight anyway).
local function ScanAuras(what, id)
	if id and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		return C_UnitAuras.GetPlayerAuraBySpellID(id) ~= nil
	end
	for i = 1, 40 do
		local name, spellID
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
			if not aura then return false end
			name, spellID = aura.name, aura.spellId
		else
			local _
			name, _, _, _, _, _, _, _, _, spellID = UnitBuff("player", i)
			if not name then return false end
		end
		if (id and spellID == id) or (not id and type(name) == "string" and name:lower() == what) then
			return true
		end
	end
	return false
end
-- You're in a zone or subzone of that name (lower case).
local PLACE_TEXT = { "GetSubZoneText", "GetZoneText", "GetMinimapZoneText", "GetRealZoneText" }
local function ScanPlace(what)
	for _, fnName in ipairs(PLACE_TEXT) do
		local fn = _G[fnName]
		local name = fn and fn()
		if type(name) == "string" and name ~= "" and name:lower() == what then return true end
	end
	return false
end
-- A cast is the trigger's: by ID, or by its name in your game language.
local function ScanSpell(spellID, wantID, wantName)
	if wantID then return spellID == wantID end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
		or (GetSpellInfo and GetSpellInfo(spellID))
	return type(name) == "string" and name:lower() == wantName
end
local function Safe(ok, value) return ok and value or false end

local function Rows()
	local db = ns.db
	return db and type(db.cameraRows) == "table" and db.cameraRows or nil
end

-- An emote as its token, lower case: "/lol" or "lol" -> "laugh", by the
-- game's own emote commands (any language, any alias); else as typed.
local emoteTokens -- ("/lol" -> "laugh", built on first use)
function ns.EmoteToken(text)
	text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if not emoteTokens then
		emoteTokens = {}
		for i = 1, 1000 do
			local token = _G["EMOTE" .. i .. "_TOKEN"]
			if type(token) == "string" then
				emoteTokens["/" .. token:lower()] = token:lower()
				for j = 1, 10 do
					local cmd = _G["EMOTE" .. i .. "_CMD" .. j]
					if type(cmd) == "string" then emoteTokens[cmd:lower()] = token:lower() end
				end
			end
		end
	end
	local slashed = text:find("^/") and text or "/" .. text
	return emoteTokens[slashed] or text:gsub("^/", "")
end

-- A scene's triggers: a list of sources ("<kind>:<what>"). A scene of yours
-- keeps them in "<id>.triggers" ("|" between; an older one's single
-- "<id>.source" reads as a list of one); a built-in scene its extra ones (its
-- own, the game's, isn't in the list), with "extras" naming those scenes.
-- Worked out again only when the text changes; not to be changed in place.
local listCache = {}
local EMPTY = {}
function ns.SceneTriggers(key)
	local rows = Rows()
	if not rows then return EMPTY end
	local text = tostring(rows[key .. ".triggers"] or rows[key .. ".source"] or "")
	local cached = listCache[key]
	if cached and cached.text == text then return cached.list end
	local list = {}
	for source in text:gmatch("[^|]+") do
		if #list < ns.SCENE_TRIGGER_MAX then list[#list + 1] = source end
	end
	listCache[key] = { text = text, list = list }
	return list
end

-- The built-in scenes that can take triggers of yours: those whose camera
-- runs while you stand still (or the tele camera's, a Hearthstone's).
function ns.SceneTakesTriggers(key)
	local trigger = ns.CAMERA_TRIGGER and ns.CAMERA_TRIGGER[key]
	if not trigger then return false end
	if trigger.custom then return true end
	for _, value in ipairs(trigger.cameras or EMPTY) do
		if value == "cozy" or value == "tele" then return true end
	end
	return false
end

-- Sets a scene's triggers (a list of sources; a built-in scene's extra ones).
function ns.SetSceneTriggers(key, list)
	local rows = ns.GetDB().cameraRows
	local clean = {}
	for _, source in ipairs(list) do
		source = tostring(source):gsub("|", "")
		if source:find("^%a+:") and #clean < ns.SCENE_TRIGGER_MAX then clean[#clean + 1] = source end
	end
	rows[key .. ".triggers"] = #clean > 0 and table.concat(clean, "|") or nil
	rows[key .. ".source"] = nil
	local trigger = ns.CAMERA_TRIGGER[key]
	if trigger and not trigger.custom then
		local extras = {}
		for _, each in ipairs(ns.CAMERA_TRIGGERS) do
			if not each.custom and rows[each.key .. ".triggers"] then extras[#extras + 1] = each.key end
		end
		rows.extras = #extras > 0 and table.concat(extras, ",") or nil
	end
	ns.CustomTriggersChanged()
end

-- Each trigger of a scene is a unit, on for an episode of its own; a scene is
-- on while any of its units is. A unit's trigger is one of the library's
-- ("t:<id>", TriggerLibrary.lua: its parts read from there) or, written
-- before the library, its own "<kind>:<what>" with its scene's until. Unit:
-- { scene, index, custom (a scene of yours), source, lib, label, kind, what,
-- spellID, at, inverted, ends, hasEnd, secs, refs, delay, hold, cd, chance,
-- rearm, condText, test, pri; on, since, cond, done, casting, dirty,
-- lookedAt, found, death, tele, walks, pendingAt, stopAt, stopWhy,
-- lastStart, skipWhy, lostLogged, tested }.
local units = {}
local sceneUnits = {} -- scene key -> its units
local needSync = false
local HELD = ns.TRIGGER_HELD_KINDS
local INVERTED = { lose = true, leave = true, ["false"] = true, close = true }

-- (A trigger written before the library: its scene's until, or its kind's.)
local KIND_UNTIL = { emote = "move", spell = "ends", aura = "ends", place = "ends", moment = "time:5", state = "ends",
	interact = "ends", key = "key" }
local function OldEnds(untilText)
	local secs = tonumber(tostring(untilText):match("^time:(%d+%.?%d*)$"))
	if secs then return { { kind = "time", secs = secs } } end
	if untilText == "ends" or untilText == "key" then return { { kind = untilText } } end
	return { { kind = "never" } }
end
-- (Its place in the priority list, written before the library: after the
-- built-in source a scene of yours named, a built-in scene's just after its own.)
local BUILT_IN_ORDER = {}
for _, source in ipairs(ns.TRIGGER_SOURCES) do BUILT_IN_ORDER[source.id] = source.order end
local SCENE_SOURCE = { Hearth = "depart", Teleport = "depart", Logout = "logout", AFK = "afk", Weapon = "weapon",
	Campfire = "campfire", Still = "still" }
local function OldOrder(unit)
	if unit.custom then
		local after = Rows()[unit.scene .. ".after"]
		local base = after == "" and 0 or BUILT_IN_ORDER[after or "emote"] or BUILT_IN_ORDER.emote
		return base + 1
	end
	return (BUILT_IN_ORDER[SCENE_SOURCE[unit.scene] or "emote"] or BUILT_IN_ORDER.emote) + 0.5
end

-- Reads a unit's trigger (again only when it, or the library, changed).
local function Parse(unit)
	local rows = Rows()
	if not rows then return end
	local source = ns.SceneTriggers(unit.scene)[unit.index]
	if source ~= unit.source and unit.source ~= nil then
		needSync = true -- (its scene's list changed under it: units made afresh)
		return
	end
	local lib = tostring(source or ""):match("^t:(Trig%a+)$")
	local untilText = not lib and (unit.custom and tostring(rows[unit.scene .. ".until"] or "move")
		or KIND_UNTIL[tostring(source or ""):match("^(%a+):") or ""] or "move") or nil
	if unit.parsed and unit.parsedAt == ns.triggerLibVersion and unit.untilText == untilText then return end
	unit.source, unit.untilText, unit.parsed, unit.parsedAt = source, untilText, true, ns.triggerLibVersion
	unit.lib = lib
	local src = lib and ns.TriggerField(lib, "src") or source
	local kind, what = tostring(src or ""):match("^(%a+):(.*)$")
	unit.kind, unit.what = kind, what and what:lower() or ""
	if kind == "emote" then unit.what = ns.EmoteToken(unit.what) end
	if kind == "ours" then unit.what = what end -- (a key: Hearth, Dance...)
	unit.spellID = (kind == "spell" or kind == "aura") and tonumber(unit.what) or nil
	unit.label = lib and ns.TriggerLabel(lib) or ns.DescribeTriggerSource(source)
	local phases = ns.TRIGGER_PHASES[kind or ""]
	unit.at = lib and ns.TriggerField(lib, "at") or (phases and phases[1].value) or nil
	unit.inverted = INVERTED[unit.at or ""] == true
	unit.ends = lib and ns.TriggerEnds(lib) or OldEnds(untilText)
	unit.hasEnd, unit.refs, unit.secs = {}, {}, nil
	for _, each in ipairs(unit.ends) do
		unit.hasEnd[each.kind] = true
		if each.kind == "time" then unit.secs = math.min(unit.secs or each.secs, each.secs) end
		if each.kind == "trig" then unit.refs[each.ref] = true end
	end
	local function Num(field, default, low, high)
		local value = lib and tonumber(ns.TriggerField(lib, field)) or default
		return math.max(low, math.min(high, value))
	end
	unit.delay, unit.hold, unit.cd = Num("delay", 0, 0, 600), Num("hold", 0, 0, 600), Num("cd", 0, 0, 86400)
	unit.chance = Num("chance", 100, 1, 100)
	unit.rearm = not (lib and ns.TriggerField(lib, "rearm") == "no")
	local condText = lib and ns.TriggerField(lib, "cond") or nil
	if type(condText) ~= "string" or not condText:find("%S") then condText = nil end
	if condText ~= unit.condText or unit.test == nil then
		unit.condText = condText
		unit.test, unit.badCond = nil, false
		if condText and ns.CompileRule then
			local test = ns.CompileRule(condText)
			unit.test, unit.badCond = test, test == nil
		end
	end
	unit.pri = lib and ns.TriggerPri(lib) or OldOrder(unit)
	unit.on, unit.cond, unit.done, unit.dirty = false, nil, false, true
	unit.pendingAt, unit.stopAt = nil, nil
end

local function Log(what, unit, why)
	if ns.TriggerLogAdd then ns.TriggerLogAdd(what, unit.label, why) end
end
-- A start held back: logged once for each new reason, until it starts.
local function Skip(unit, why)
	if unit.skipWhy ~= why then
		unit.skipWhy = why
		Log("skipped", unit, why)
	end
end

-- Starting one: the tele camera needs a cast to spin and zoom over (a pretend
-- one, its time long), the death camera runs as its test does (no event of
-- its own: the unit's Key leaves it out, or the AFK camera would run too).
local Stop -- (below)
local function Start(unit, tested)
	local now = GetTime()
	unit.on, unit.since, unit.done, unit.tested = true, now, false, tested or false
	unit.lastStart, unit.skipWhy, unit.lostLogged = now, nil, false
	unit.pendingAt, unit.stopAt = nil, nil
	local camera = ns.TriggerSetting(unit.scene, "camera")
	unit.death, unit.tele = camera == "death", camera == "tele"
	-- (A script: moving doesn't end it here, its stop rules do; auto-walk
	-- and auto-run carry it on, as they do our cameras.)
	unit.walks = ns.IsScriptCamera and ns.IsScriptCamera(camera) or false
	if camera == "tele" and ns.PretendDepartCast then
		ns.PretendDepartCast(unit.secs or 10)
	elseif unit.death then
		ns.deathTestUntil, ns.deathTestLoud = GetTime() + (unit.secs or DEATH_FOR), false
	end
	Log("fired", unit, (L["%s. Scene: %s, camera: %s"]):format(tested and L["Fire now"] or L["Started"],
		ns.SceneDisplayName(unit.scene), ns.CameraName and ns.CameraName(camera) or tostring(camera)))
	-- (Triggers that end as this one starts.)
	if unit.lib then
		for _, other in ipairs(units) do
			if other.on and other ~= unit and other.refs and other.refs[unit.lib] then
				Stop(other, (L["%s started"]):format(unit.label))
			end
		end
	end
end
function Stop(unit, why)
	if unit.on and why then Log("ended", unit, why) end
	unit.on, unit.done, unit.stopAt, unit.tested = false, true, nil, false
	-- (May start again while its thing is still on.)
	if not unit.rearm and HELD[unit.kind] then unit.done = false end
	if unit.death then
		unit.death = false
		ns.deathTestUntil = 0
	end
end
-- Its own ending: kept on to its least time ("Keep going at least").
local function EndSoon(unit, now, why)
	if not unit.on then return end
	if unit.hold > 0 and now < unit.since + unit.hold then
		unit.stopAt, unit.stopWhy = unit.since + unit.hold, why
	else
		Stop(unit, why)
	end
end
-- Something says start: its cooldown, Only if and chance first, then its wait.
local function TryStart(unit, now)
	if unit.on or unit.pendingAt then return end
	if unit.cd > 0 and unit.lastStart and now - unit.lastStart < unit.cd then
		Skip(unit, (L["Cooldown: %d of %d sec left"]):format(math.ceil(unit.cd - (now - unit.lastStart)), unit.cd))
		return
	end
	if unit.badCond then
		Skip(unit, L["Its Only if rule can't be read: fix it on its page"])
		return
	end
	if unit.test and not unit.test(ns.RuleFactsNow()) then
		Skip(unit, (L["Only if is false: %s"]):format(unit.condText))
		return
	end
	if unit.chance < 100 and math.random(100) > unit.chance then
		Skip(unit, (L["Chance: not this time (%d%%)"]):format(unit.chance))
		unit.done = true -- (a held one: not again until its thing stops)
		return
	end
	if unit.delay > 0 then
		unit.pendingAt = now + unit.delay
		return
	end
	Start(unit)
end
-- The states you travel in: a scene of yours on through one of them, its
-- camera a script, carries on while you move (a skyriding zoom-out), and
-- ends as the state does (moving can't end it: moving is the point).
local TRAVEL_STATES = { mounted = true, flying = true, swimming = true }
local function Travels(unit)
	return unit.kind == "state" and TRAVEL_STATES[unit.what] and unit.walks or false
end

-- That scene on now (not on a flight path: the flight camera has those), or nil.
function ns.CustomTravelScene()
	if ns.OnTaxi and ns.Flag(ns.OnTaxi()) then return nil end
	for _, unit in ipairs(units) do
		if unit.on and Travels(unit) then return unit.scene end
	end
end
-- A scene you started with its key (Custom camera trigger N) that's on now,
-- or nil: a camera script asks first (CameraScripts.lua's TriggerNow), so it
-- plays with a window open or you walking, as the key says to.
function ns.CustomKeyScene()
	for _, unit in ipairs(units) do
		if unit.on and unit.kind == "key" and not unit.death then return unit.scene end
	end
end
-- A scene an interaction started that's on now, or nil: it plays with its
-- window open (Camera.lua's CurrentEvent and CameraScripts.lua's TriggerNow
-- ask before waiting for windows to close), as that window is the point.
function ns.CustomInteractScene()
	for _, unit in ipairs(units) do
		if unit.on and unit.kind == "interact" and not unit.inverted and not unit.death then return unit.scene end
	end
end
-- Its script over by its own stop rules: the key's scene ends too, so one
-- press starts it again.
function ns.EndCustomKeyScene(scene)
	for _, unit in ipairs(units) do
		if unit.on and unit.kind == "key" and unit.scene == scene then Stop(unit) end
	end
end
-- Whether one of these plays the tele camera now (its pretend cast holds
-- while it does, Camera.lua's DepartTimeLeft).
function ns.CustomTeleOn()
	for _, unit in ipairs(units) do
		if unit.on and unit.tele then return true end
	end
	return false
end
-- Whether one of these runs the death camera now (CameraRows' CameraRowsOff:
-- its own Die row needn't be set to it).
function ns.CustomDeathOn()
	if GetTime() >= (ns.deathTestUntil or 0) then return false end
	for _, unit in ipairs(units) do
		if unit.on and unit.death then return true end
	end
	return false
end

-- The game events the units need now, registered only while one does.
local watcher = CreateFrame("Frame")
local function Watch()
	watcher:UnregisterAllEvents()
	local need = {}
	for _, unit in ipairs(units) do
		if unit.kind == "spell" then
			for _, event in ipairs(SPELL_EVENTS) do need[event] = true end
		elseif unit.kind == "aura" then
			need.UNIT_AURA = true
		elseif unit.kind == "place" then
			for _, event in ipairs(PLACE_EVENTS) do need[event] = true end
		elseif unit.kind == "moment" then
			for _, event in ipairs(MOMENT_EVENTS[unit.what] or EMPTY) do need[event] = true end
		end
	end
	for event in pairs(need) do
		if event:find("^UNIT_") then
			pcall(watcher.RegisterUnitEvent, watcher, event, "player")
		else
			pcall(watcher.RegisterEvent, watcher, event)
		end
	end
end

local function MomentMatches(unit, event, ...)
	for _, each in ipairs(MOMENT_EVENTS[unit.what] or EMPTY) do
		if each == event then
			if event == "ENCOUNTER_END" then return select(5, ...) == 1 end -- (won)
			if event == "PLAYER_ALIVE" then return not ns.Flag(UnitIsDeadOrGhost("player")) end
			return true
		end
	end
	return false
end

watcher:SetScript("OnEvent", function(_, event, ...)
	local isCast = CAST_START[event] or CAST_END[event] or event == "UNIT_SPELLCAST_SUCCEEDED"
	local now = GetTime()
	for _, unit in ipairs(units) do
		if unit.kind == "spell" and isCast then
			if Safe(pcall(ScanSpell, (select(3, ...)), unit.spellID, unit.what)) then
				if unit.at == "success" then
					-- (Its cast landing starts it; its time ends it, as a moment's.)
					if event == "UNIT_SPELLCAST_SUCCEEDED" then TryStart(unit, now) end
				elseif CAST_START[event] then
					unit.casting = true
					TryStart(unit, now)
				elseif CAST_END[event] then
					unit.casting = false
					unit.pendingAt = nil
					if unit.on and unit.hasEnd.ends then EndSoon(unit, now, L["The cast ended"]) end
				elseif not unit.casting and not unit.on then
					TryStart(unit, now) -- (an instant cast: "ends" times out, as a moment)
				end
			end
		elseif unit.kind == "moment" and MomentMatches(unit, event, ...) then
			TryStart(unit, now)
		elseif unit.kind == "aura" or unit.kind == "place" then
			unit.dirty = true
		end
	end
end)

-- A held kind's condition now, the other way round for a phase that starts
-- as it stops (nil for the ones an event starts). Buffs and places are
-- looked at again on their events, or every SLOW_LOOK.
local function Condition(unit, now)
	local kind, raw = unit.kind, nil
	if kind == "ours" then
		raw = ns.OursOnNow and ns.OursOnNow(unit.what) or false -- (Triggers.lua: our camera code's say)
	elseif kind == "state" then
		raw = StateNow(unit.what)
	elseif kind == "interact" then
		raw = InteractNow(unit.what)
	elseif kind == "aura" or kind == "place" then
		if unit.dirty or not unit.lookedAt or now - unit.lookedAt >= SLOW_LOOK then
			unit.dirty, unit.lookedAt = false, now
			if kind == "aura" then
				unit.found = Safe(pcall(ScanAuras, unit.what, unit.spellID))
			else
				unit.found = Safe(pcall(ScanPlace, unit.what))
			end
		end
		raw = unit.found
	end
	if raw == nil then return nil end
	if unit.inverted then return not raw end
	return raw
end

-- Whether an episode on now has run its time: a set time, or "ends" for
-- what has no end of its own (a moment, an instant or landed cast).
local function TimedOut(unit, now)
	if unit.secs and now - unit.since >= unit.secs then return true end
	local noEnd = unit.kind == "moment" or (unit.kind == "spell" and not unit.casting)
	return unit.hasEnd.ends and noEnd and now - unit.since >= DEFAULT_SECS
end

local lastEmoteAt -- (the last emote's time already looked at)
local function Tick()
	local now = GetTime()
	local emote = ns.lastEmote
	local newEmote = emote and emote.at ~= lastEmoteAt and type(emote.token) == "string" and emote.token:lower()
	lastEmoteAt = emote and emote.at
	local moving = ns.playerMoving and not (ns.OnTaxi and ns.OnTaxi())
	for _, unit in ipairs(units) do
		Parse(unit)
		local cond = Condition(unit, now)
		if cond ~= nil then
			-- (Starting as it stops: not at the first look, only once it has been on.)
			if unit.cond == nil and unit.inverted and cond then unit.done = true end
			if cond and not unit.done then TryStart(unit, now) end
			if not cond then
				unit.pendingAt, unit.skipWhy = nil, nil
				if unit.on and not unit.tested and (unit.hasEnd.ends or Travels(unit)) then
					EndSoon(unit, now, L["It ended"])
				end
				unit.done = false
			end
			unit.cond = cond
		end
		if newEmote and unit.kind == "emote" then
			-- (Another emote ends it, as the built-in emotes' cameras end.)
			if newEmote == unit.what then
				TryStart(unit, now)
			elseif unit.on then
				EndSoon(unit, now, L["Another emote"])
			end
		end
		if unit.pendingAt then
			if moving and not unit.walks then
				unit.pendingAt = nil
			elseif now >= unit.pendingAt then
				unit.pendingAt = nil
				if unit.test and not unit.test(ns.RuleFactsNow()) then
					Skip(unit, (L["Only if is false: %s"]):format(unit.condText))
				elseif cond ~= false then
					Start(unit)
				end
			end
		end
		if unit.on then
			if moving and not unit.walks then
				Stop(unit, L["You moved"])
			elseif unit.stopAt and now >= unit.stopAt then
				Stop(unit, unit.stopWhy)
			elseif TimedOut(unit, now) then
				Stop(unit, L["Its time ran out"])
			end
		end
	end
	if needSync then
		needSync = false
		ns.CustomTriggersChanged()
	end
end
if ns.Profiled then Tick = ns.Profiled("CustomTriggers", Tick) end

local ticker = CreateFrame("Frame")
local sinceTick = 0
ticker:Hide()
ns.SetOnUpdate(ticker, function(_, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick >= TICK then
		sinceTick = 0
		Tick()
	end
end)

-- Brings the scenes and their units in line with the profile when it
-- changes (one added or taken off, a trigger added, a profile loaded).
-- Each unit takes its place in the priority list (Triggers.lua) by its
-- trigger's priority, a scene's own order breaking a tie.
local synced = { rows = false }
local registered = {} -- (our scenes on the page, and our priority sources)
local sources = {}
local function SyncNow(force)
	local rows = Rows()
	if not rows then return end
	if not force and synced.rows == rows and synced.custom == rows.custom and synced.extras == rows.extras then return end
	if synced.rows ~= rows then ns.triggerLibVersion = ns.triggerLibVersion + 1 end -- (another profile)
	synced.rows, synced.custom, synced.extras = rows, rows.custom, rows.extras
	if ns.ApplyBuiltInOrders then ns.ApplyBuiltInOrders() end
	if ns.MigrateSceneTriggers then ns.MigrateSceneTriggers() end
	synced.custom, synced.extras = rows.custom, rows.extras
	local ids, seen = {}, {}
	for id in tostring(rows.custom or ""):gmatch("[^,]+") do
		-- (Never over a built-in scene.)
		local taken = ns.CAMERA_TRIGGER[id] and not ns.CAMERA_TRIGGER[id].custom
		if id:find("^%a+$") and not taken and not seen[id] and #ids < ns.CUSTOM_TRIGGER_MAX then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	for id in pairs(registered) do
		if not seen[id] then
			ns.UnregisterCameraTrigger(id)
			registered[id] = nil
		end
	end
	for _, id in ipairs(sources) do ns.UnregisterTriggerSource(id) end
	wipe(sources)
	-- (Units kept where their trigger's the same: an episode on carries on.)
	local old = {}
	for _, unit in ipairs(units) do old[unit.scene .. "#" .. unit.index .. "#" .. tostring(unit.source)] = unit end
	wipe(units)
	wipe(sceneUnits)
	local sceneNumber = 0
	local function AddUnits(key, custom)
		local list = {}
		sceneNumber = sceneNumber + 1
		for index, source in ipairs(ns.SceneTriggers(key)) do
			local unit = old[key .. "#" .. index .. "#" .. source] or { scene = key, index = index }
			unit.custom = custom
			list[#list + 1] = unit
			units[#units + 1] = unit
			Parse(unit)
			local id = "unit:" .. key .. "#" .. index
			sources[#sources + 1] = id
			ns.RegisterTriggerSource({ id = id, order = unit.pri + sceneNumber / 1000 + index / 100000, unit = unit,
				label = unit.label, Key = function() return unit.on and not unit.death and key or nil end })
		end
		sceneUnits[key] = list
	end
	for _, id in ipairs(ids) do
		if not ns.CAMERA_TRIGGER[id] then
			ns.RegisterCameraTrigger({ key = id, custom = true, cameras = CAMERAS, off = "none", music = true,
				cine = true })
		end
		registered[id] = true
		AddUnits(id, true)
	end
	for key in tostring(rows.extras or ""):gmatch("[^,]+") do
		if ns.SceneTakesTriggers(key) and not sceneUnits[key] then AddUnits(key, false) end
	end
	Watch()
	ticker:SetShown(#units > 0)
end
-- (Moving old scenes over adds to the library, which asks for this again:
-- asked while it runs, it runs once more after.)
local syncing, again = false, false
function ns.SyncCustomTriggers(force)
	if syncing then
		again = again or force or false
		return
	end
	syncing = true
	local ok, err = pcall(SyncNow, force)
	if ok and again then
		again = false
		ok, err = pcall(SyncNow, true)
	end
	syncing, again = false, false
	if not ok then error(err, 0) end
end

-- (A scene's triggers or place in the list changed: worked out afresh.)
function ns.CustomTriggersChanged()
	ns.SyncCustomTriggers(true)
end

-- What starts a trigger, in words: "/cheer", "Cast Fishing", "Mounted"...
function ns.DescribeTriggerSource(source)
	local lib = tostring(source or ""):match("^t:(Trig%a+)$")
	if lib then
		return (ns.IsLibTrigger(lib) or ns.OursTrigger(lib)) and ns.TriggerLabel(lib) or L["(a deleted trigger)"]
	end
	local ours = tostring(source or ""):match("^ours:(%a+)$")
	if ours then
		local each = ns.OursTrigger(ours)
		return each and each.name or ours
	end
	local kind, what = tostring(source or ""):match("^(%a+):(.*)$")
	what = what or ""
	if kind == "emote" then
		return "/" .. ns.EmoteToken(what)
	elseif kind == "spell" then
		local id = tonumber(what)
		local name = id and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
			or (GetSpellInfo and GetSpellInfo(id)))
		return (L["Cast %s"]):format(type(name) == "string" and name or what)
	elseif kind == "aura" then
		return (L["Buff: %s"]):format(what)
	elseif kind == "place" then
		return (L["In %s"]):format(what)
	elseif kind == "moment" then
		return ChoiceText(ns.CUSTOM_TRIGGER_MOMENTS, what) or what
	elseif kind == "state" then
		return ChoiceText(ns.CUSTOM_TRIGGER_STATES, what) or what
	elseif kind == "interact" then
		return ChoiceText(ns.CUSTOM_TRIGGER_INTERACTIONS, what) or what
	elseif kind == "key" then
		return (L["Custom camera trigger %d"]):format(tonumber(what) or 1)
	end
	return tostring(source or "?")
end

-- A scene of yours' name for the page and logs: your own, else what starts it.
function ns.CustomTriggerLabel(id)
	local rows = Rows()
	local name = rows and rows[id .. ".name"]
	if type(name) == "string" and name:find("%S") then return name end
	return ns.DescribeTriggerSource(ns.SceneTriggers(id)[1])
end

-- Whether a spell trigger is on with its cast going: the cast isn't busy
-- casting then (as fishing isn't), so its scene's camera can run.
function ns.CustomCastCounts()
	for _, unit in ipairs(units) do
		if unit.kind == "spell" and unit.on and unit.casting and ns.TriggerHasCamera(unit.scene) then return true end
	end
	return false
end

-- The key bindings (Cinematic custom trigger 1-5): start the triggers set
-- to that key, or stop them if they're on.
function Cinematic_CustomTrigger(n)
	local what = tostring(n)
	for _, unit in ipairs(units) do
		if unit.kind == "key" and unit.what == what then
			if unit.on then
				Stop(unit, L["Its key was pressed again"])
			else
				TryStart(unit, GetTime())
			end
		end
	end
end

-- The Triggers page's Fire now: the trigger's units started now, whatever
-- its Only if, cooldown and chance say (or stopped, if one is on). With no
-- scene using it, only the log hears it (and it shows as on for a moment).
local firedAlone = {}
function ns.FireLibTrigger(id)
	local any, on = false, false
	for _, unit in ipairs(units) do
		if unit.lib == id then
			any = true
			on = on or unit.on
		end
	end
	if on then
		for _, unit in ipairs(units) do
			if unit.lib == id and unit.on then Stop(unit, L["Stopped on the Triggers page"]) end
		end
	elseif any then
		for _, unit in ipairs(units) do
			if unit.lib == id then Start(unit, true) end
		end
	elseif (firedAlone[id] or 0) > GetTime() then
		firedAlone[id] = nil
	else
		firedAlone[id] = GetTime() + 3
		if ns.TriggerLogAdd then ns.TriggerLogAdd("fired", ns.TriggerLabel(id), L["Fire now. Nothing uses it yet"]) end
	end
end
-- Whether a trigger of the library is on now (any scene's).
function ns.LibTriggerOn(id)
	if (firedAlone[id] or 0) > GetTime() then return true end
	for _, unit in ipairs(units) do
		if unit.lib == id and (unit.on or unit.pendingAt) then return true end
	end
	return false
end

-- For the camera mode log: what set a scene's trigger of yours off.
function ns.CustomTriggerDetail(key)
	for _, unit in ipairs(sceneUnits[key] or EMPTY) do
		if unit.on then
			return ("trigger %s of %s (until %s), %.0f sec in"):format(tostring(unit.source),
				ns.CAMERA_TRIGGER[key] and ns.CAMERA_TRIGGER[key].custom and ns.CustomTriggerLabel(key) or key,
				tostring(unit.untilText), GetTime() - (unit.since or GetTime()))
		end
	end
	return nil
end

-- A new scene of yours with one trigger: its id (nil with all taken). Starts
-- with the camera given (cozy), no music, anywhere but battlegrounds and
-- arenas, out of fights.
function ns.AddCustomTrigger(source, untilText, camera, name)
	local db = ns.GetDB()
	local rows = db.cameraRows
	local taken, count = {}, 0
	for id in tostring(rows.custom or ""):gmatch("[^,]+") do
		taken[id] = true
		count = count + 1
	end
	if count >= ns.CUSTOM_TRIGGER_MAX then return nil end
	local id
	for n = 0, 701 do
		local letters = n < 26 and string.char(65 + n) or string.char(64 + math.floor(n / 26), 65 + n % 26)
		if not taken["Mine" .. letters] and not ns.CAMERA_TRIGGER["Mine" .. letters] then
			id = "Mine" .. letters
			break
		end
	end
	if not id then return nil end
	-- (A source written the old way: into the library, with its until.)
	source = tostring(source or ""):gsub("|", "")
	if not source:find("^t:") then
		local lib = ns.LibTriggerFor(source, untilText or "move", ns.TRIGGER_DEFAULT_PRI)
		if not lib then return nil end
		source = "t:" .. lib
	end
	rows[id .. ".triggers"] = source
	rows[id .. ".camera"] = camera or "cozy"
	rows[id .. ".name"] = name
	local key = ns.CameraRowKey(id)
	for _, list in ipairs({ "worldShow", "cityShow", "instanceShow", "groupShow", "bgShow", "combatShow" }) do
		if type(db[list]) ~= "table" then db[list] = {} end
		db[list][key] = list ~= "bgShow" and list ~= "combatShow"
	end
	rows.custom = (rows.custom and rows.custom ~= "" and rows.custom .. "," or "") .. id
	ns.SyncCustomTriggers()
	return id
end

-- Takes a scene of yours off, with its copies and all their settings.
function ns.RemoveCustomTrigger(id)
	local db = ns.GetDB()
	local rows = db.cameraRows
	if ns.CAMERA_TRIGGER[id] then
		for _, each in ipairs(ns.TriggerRowIds(id)) do
			if each ~= id then ns.RemoveCameraRow(each) end
		end
	end
	for _, field in ipairs({ "camera", "music", "cine", "name", "always", "calm", "off", "source", "triggers", "until",
		"after" }) do
		rows[id .. "." .. field] = nil
	end
	for _, list in ipairs(ns.CAMERA_ROW_LISTS) do
		if type(db[list]) == "table" then db[list][ns.CameraRowKey(id)] = nil end
	end
	ns.DropCameraRowFollowers(id)
	local list = {}
	for each in tostring(rows.custom or ""):gmatch("[^,]+") do
		if each ~= id then list[#list + 1] = each end
	end
	rows.custom = #list > 0 and table.concat(list, ",") or nil
	-- (Out of a row order of your own, if there is one.)
	if rows.order then
		local order = {}
		for _, each in ipairs(ns.CameraRowOrder()) do
			if each ~= id then order[#order + 1] = each end
		end
		ns.SetCameraRowOrder(order)
	else
		ns.SyncCustomTriggers()
	end
end

-- For /cine debug triggers: each trigger of yours (and the extra ones on
-- built-in scenes), whether it's on and why, its scene's place in the
-- priority list and the row it goes by.
function ns.DescribeCustomTriggers()
	local lines = {}
	for _, unit in ipairs(units) do
		local order = "-"
		for _, each in ipairs(ns.TRIGGER_SOURCES) do
			if each.unit == unit then order = ("%.3f"):format(each.order) end
		end
		local ends = {}
		for _, each in ipairs(unit.ends or EMPTY) do
			ends[#ends + 1] = each.kind .. (each.secs and ":" .. each.secs or "") .. (each.ref and ":" .. each.ref or "")
		end
		lines[#lines + 1] = ("%s #%d \"%s\": %s (%s) at %s ends %s, only if %s (order %s) - %s%s%s, cond %s, row %s -> %s"):format(
			unit.scene, unit.index, unit.custom and ns.CustomTriggerLabel(unit.scene) or "built-in", tostring(unit.source),
			tostring(unit.label), tostring(unit.at), table.concat(ends, ","), tostring(unit.condText or "always"),
			order, unit.on and "ON" or "off", unit.done and ", done" or "",
			unit.casting and ", casting" or "", tostring(unit.cond), tostring(ns.TriggerRowNow(unit.scene)),
			tostring(ns.TriggerSetting(unit.scene, "camera")))
	end
	return lines
end

-- (Once the profile's there, and every second after: a profile loaded or
-- reset with nothing else asking for the rows.)
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	ns.SyncCustomTriggers()
	if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, ns.SyncCustomTriggers) end
end)
