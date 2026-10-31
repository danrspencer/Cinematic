-- Cinematic: scenes of your own, and triggers of yours on any scene. A scene
-- (a Cameras page row: CameraRows.lua's camera, music, CineMode, When,
-- copies) plays its camera when any of its triggers happens: an emote, a
-- spell cast, a buff, a place, a moment (leveling up...), a state
-- (mounted...) or one of five key bindings. Built-in scenes whose camera runs
-- while you stand still can take triggers of yours beside their own. Each
-- scene of yours takes its place in the priority list (Triggers.lua) after a
-- built-in source; a built-in scene's extra triggers sit just after its own.
--
-- Saved in db.cameraRows with the rows (so profiles, Save/Reset and share
-- strings carry them): "custom" the ids of yours (MineA, MineB...: letters
-- only, as a row id is a scene key and a copy number), "extras" the built-in
-- scenes with triggers of yours, and per scene:
--   triggers  "|" between sources, each "<kind>:<what>": emote:cheer,
--             spell:7620 or spell:fishing, aura:<id or name>,
--             place:<zone or subzone name>,
--             moment:levelup|achievement|quest|boss|alive,
--             state:mounted|swimming|flying|indoors|outdoors|resting|stealthed|night,
--             key:1-5 (a scene of yours from before: one in "source")
--   until     (yours) move (nil), ends (as the trigger that started it ends),
--             time:<sec>, key (pressed again); a built-in scene's extra
--             triggers end as their kind does on its own (KIND_UNTIL)
--   after     (yours) the built-in source it comes after (nil: "emote"; "": first)
--
-- Each trigger is on for an episode: it starts as its thing happens (a state:
-- as it becomes true) and lasts until its until, or until you move (moving
-- ends every standing-still camera). A state still true after its episode
-- ended doesn't start another until it's been false.
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
	{ value = "key", text = L["Key binding"] },
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
ns.CUSTOM_TRIGGER_KEYS = {}
for n = 1, 5 do
	ns.CUSTOM_TRIGGER_KEYS[n] = { value = tostring(n), text = (L["Custom camera trigger %d"]):format(n) }
end
ns.OnLanguage(function()
	for _, list in ipairs({ ns.CUSTOM_TRIGGER_KINDS, ns.CUSTOM_TRIGGER_MOMENTS, ns.CUSTOM_TRIGGER_STATES }) do
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
-- on while any of its units is. Unit: { scene, index, custom (a scene of
-- yours), source, kind, what, spellID, untilText, untilKind, secs, on, since,
-- cond, done, casting, dirty, lookedAt, found, death, tele }.
local units = {}
local sceneUnits = {} -- scene key -> its units
local needSync = false

-- A built-in scene's extra trigger ends as its kind would on its own.
local KIND_UNTIL = { emote = "move", spell = "ends", aura = "ends", place = "ends", moment = "time:5", state = "ends",
	key = "key" }

-- Reads a unit's source and until (again only when their text changes).
local function Parse(unit)
	local rows = Rows()
	if not rows then return end
	local source = ns.SceneTriggers(unit.scene)[unit.index]
	if source ~= unit.source and unit.source ~= nil then
		needSync = true -- (its scene's list changed under it: units made afresh)
		return
	end
	local kind = tostring(source or ""):match("^(%a+):")
	local untilText = unit.custom and tostring(rows[unit.scene .. ".until"] or "move") or KIND_UNTIL[kind] or "move"
	if unit.parsed and unit.untilText == untilText then return end
	unit.source, unit.untilText, unit.parsed = source, untilText, true
	local what
	kind, what = tostring(source or ""):match("^(%a+):(.*)$")
	unit.kind, unit.what = kind, what and what:lower() or ""
	if kind == "emote" then unit.what = ns.EmoteToken(unit.what) end
	unit.spellID = (kind == "spell" or kind == "aura") and tonumber(unit.what) or nil
	local secs = tonumber(untilText:match("^time:(%d+%.?%d*)$"))
	unit.untilKind = secs and "time" or untilText
	unit.secs = secs or DEFAULT_SECS
	unit.on, unit.cond, unit.done, unit.dirty = false, nil, false, true
end

-- Starting one: the tele camera needs a cast to spin and zoom over (a pretend
-- one, its time long), the death camera runs as its test does (no event of
-- its own: SceneOn leaves it out, or the AFK camera would run too).
local function Start(unit)
	unit.on, unit.since, unit.done = true, GetTime(), false
	local camera = ns.TriggerSetting(unit.scene, "camera")
	unit.death, unit.tele = camera == "death", camera == "tele"
	if camera == "tele" and ns.PretendDepartCast then
		ns.PretendDepartCast(unit.untilKind == "time" and unit.secs or 10)
	elseif unit.death then
		ns.deathTestUntil, ns.deathTestLoud = GetTime() + (unit.untilKind == "time" and unit.secs or DEATH_FOR), false
	end
end
local function Stop(unit)
	unit.on, unit.done = false, true
	if unit.death then
		unit.death = false
		ns.deathTestUntil = 0
	end
end
-- A scene's key while one of its units is on (and not the death camera's).
local function SceneOn(key)
	for _, unit in ipairs(sceneUnits[key] or EMPTY) do
		if unit.on and not unit.death then return key end
	end
	return nil
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
	for _, unit in ipairs(units) do
		if unit.kind == "spell" and isCast then
			if Safe(pcall(ScanSpell, (select(3, ...)), unit.spellID, unit.what)) then
				if CAST_START[event] then
					unit.casting = true
					Start(unit)
				elseif CAST_END[event] then
					unit.casting = false
					if unit.on and unit.untilKind == "ends" then Stop(unit) end
				elseif not unit.casting and not unit.on then
					Start(unit) -- (an instant cast: "ends" times out, as a moment)
				end
			end
		elseif unit.kind == "moment" and MomentMatches(unit, event, ...) then
			Start(unit)
		elseif unit.kind == "aura" or unit.kind == "place" then
			unit.dirty = true
		end
	end
end)

-- A state source's condition now (nil for the ones an event starts). Buffs
-- and places are looked at again on their events, or every SLOW_LOOK.
local function Condition(unit, now)
	local kind = unit.kind
	if kind == "state" then
		return StateNow(unit.what)
	elseif kind == "aura" or kind == "place" then
		if unit.dirty or not unit.lookedAt or now - unit.lookedAt >= SLOW_LOOK then
			unit.dirty, unit.lookedAt = false, now
			if kind == "aura" then
				unit.found = Safe(pcall(ScanAuras, unit.what, unit.spellID))
			else
				unit.found = Safe(pcall(ScanPlace, unit.what))
			end
		end
		return unit.found
	end
end

-- Whether an episode on now has run its time: a set time, or "ends" for
-- what has no end of its own (a moment, an instant cast).
local function TimedOut(unit, now)
	local timed = unit.untilKind == "time"
		or (unit.untilKind == "ends" and (unit.kind == "moment" or (unit.kind == "spell" and not unit.casting)))
	return timed and now - unit.since >= unit.secs
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
			if cond and not unit.cond and not unit.done then Start(unit) end
			if not cond then
				if unit.on and unit.untilKind == "ends" then unit.on = false end
				unit.done = false
			end
			unit.cond = cond
		end
		if newEmote and unit.kind == "emote" then
			-- (Another emote ends it, as the built-in emotes' cameras end.)
			if newEmote == unit.what then
				Start(unit)
			elseif unit.on then
				Stop(unit)
			end
		end
		if unit.on and (moving or TimedOut(unit, now)) then Stop(unit) end
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
ticker:SetScript("OnUpdate", function(_, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick >= TICK then
		sinceTick = 0
		Tick()
	end
end)

-- Where a scene of yours sits in the priority list: just after the built-in
-- source it names, in the order they're listed. A built-in scene's extra
-- triggers sit just after its own source.
local BUILT_IN_ORDER = {}
for _, source in ipairs(ns.TRIGGER_SOURCES) do BUILT_IN_ORDER[source.id] = source.order end
local function OrderOf(id, index)
	local after = Rows()[id .. ".after"]
	local base = after == "" and 0 or BUILT_IN_ORDER[after or "emote"] or BUILT_IN_ORDER.emote
	return base + 1 + math.min(index, 98) / 100
end
local SCENE_SOURCE = { Hearth = "depart", Teleport = "depart", Logout = "logout", AFK = "afk", Weapon = "weapon",
	Campfire = "campfire", Still = "still" }
local function ExtraOrder(key)
	return (BUILT_IN_ORDER[SCENE_SOURCE[key] or "emote"] or BUILT_IN_ORDER.emote) + 0.5
end

-- Brings the scenes and their units in line with the profile when it
-- changes (one added or taken off, a trigger added, a profile loaded).
local synced = { rows = false }
local registered = {} -- (our scenes on the page, and our priority sources)
local sources = {}
function ns.SyncCustomTriggers(force)
	local rows = Rows()
	if not rows then return end
	if not force and synced.rows == rows and synced.custom == rows.custom and synced.extras == rows.extras then return end
	synced.rows, synced.custom, synced.extras = rows, rows.custom, rows.extras
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
	local function AddUnits(key, custom)
		local list = {}
		for index, source in ipairs(ns.SceneTriggers(key)) do
			local unit = old[key .. "#" .. index .. "#" .. source] or { scene = key, index = index }
			unit.custom = custom
			list[#list + 1] = unit
			units[#units + 1] = unit
			Parse(unit)
		end
		sceneUnits[key] = list
	end
	for i, id in ipairs(ids) do
		if not ns.CAMERA_TRIGGER[id] then
			ns.RegisterCameraTrigger({ key = id, custom = true, cameras = CAMERAS, off = "none", music = true,
				cine = true })
		end
		registered[id] = true
		AddUnits(id, true)
		sources[#sources + 1] = "custom:" .. id
		ns.RegisterTriggerSource({ id = "custom:" .. id, order = OrderOf(id, i), custom = id,
			Key = function() return SceneOn(id) end })
	end
	for key in tostring(rows.extras or ""):gmatch("[^,]+") do
		if ns.SceneTakesTriggers(key) and not sceneUnits[key] then
			AddUnits(key, false)
			sources[#sources + 1] = "extra:" .. key
			ns.RegisterTriggerSource({ id = "extra:" .. key, order = ExtraOrder(key), extra = key,
				Key = function() return SceneOn(key) end })
		end
	end
	Watch()
	ticker:SetShown(#units > 0)
end
-- (A scene's triggers or place in the list changed: worked out afresh.)
function ns.CustomTriggersChanged()
	ns.SyncCustomTriggers(true)
end

-- What starts a trigger, in words: "/cheer", "Cast Fishing", "Mounted"...
function ns.DescribeTriggerSource(source)
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
			if unit.on then Stop(unit) else Start(unit) end
		end
	end
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
	rows[id .. ".triggers"] = tostring(source):gsub("|", "")
	rows[id .. ".until"] = untilText ~= "move" and untilText or nil
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
			if each.custom == unit.scene or each.extra == unit.scene then order = ("%.2f"):format(each.order) end
		end
		lines[#lines + 1] = ("%s #%d \"%s\": %s until %s (order %s) - %s%s%s, cond %s, row %s -> %s"):format(
			unit.scene, unit.index, unit.custom and ns.CustomTriggerLabel(unit.scene) or "built-in", tostring(unit.source),
			tostring(unit.untilText), order, unit.on and "ON" or "off", unit.done and ", done" or "",
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
