-- Cinematic: the Cameras page's rows. Each row is a trigger (an emote, a
-- campfire, going AFK, a flight, dying...) and the camera it starts, with its
-- music and CineMode switches, and When it may start (as the Standard Frames
-- page's rows: Always, the places, a rule, the roles; and its own Calm Timer
-- wait). A trigger's own row keeps the settings it always had (eventAFKCamera,
-- walkCamera, deathOrbit...); copies of it (AFK2...) are rows of their own,
-- in db.cameraRows. When a trigger happens, its rows are tried in their order
-- and the first whose When fits picks the camera: none fitting, no camera.
--
-- db.cameraRows (a profile table, flat): "order" the rows in their order
-- (comma separated; nil: each trigger's own row alone), and "<id>.<field>":
-- camera, music, cine (a copy's; nil: its trigger's own row's), name (one of
-- your own), off (true: unticked, passed over), always and calm (the When's Always and the Calm Timer wait; nil
-- on a trigger's own row: its camera's, below). A row's place ticks and rule
-- are under "trig:<id>" in the shared lists (cityShow..., frameRules).
-- A built-in trigger's own row is ticked off by its setting sceneOff<key>
-- instead: a setting, so a built-in profile can have a scene off with its
-- camera still on it (a saved cameraRows replaces the built-in's whole).
--
-- Triggers of your own (CustomTriggers.lua: custom = true) keep all of theirs
-- in it too, their own row's included: "custom" their ids, and
-- "<id>.source", "<id>.until", "<id>.after" what starts and ends them.
--
-- Before the page was one, each camera had its When (the Camera Modes page's
-- "cam:<cam>" rows, camAlways<cam>, <cam>CalmWait). A trigger's own row
-- follows its camera's until it's given a When of its own, so nothing
-- changes for settings and profiles from before.
local _, ns = ...
local L = ns.L

ns.CAMERA_ROW_COPIES = 5 -- (a trigger's own row and four copies: <key>2 to <key>5)

-- The triggers in the order the page lists them: the order they win in when
-- two are on (Camera.lua's CurrentEvent), then the ones with cameras of
-- their own. Each: key, its settings (camera, music, cine: nil for none),
-- its cameras (value, name), the value that's no camera.
local EVENT_CAMERAS = { "cozy", "vista", "fish", "afk", "none" }
local function Event(key, cameras)
	local music = ns.DEFAULTS["event" .. key .. "Music"] ~= nil and "event" .. key .. "Music" or nil
	return { key = key, camera = "event" .. key .. "Camera", music = music, cine = "event" .. key .. "Cine",
		cameras = cameras or EVENT_CAMERAS, off = "none" }
end
local TRIGGERS, TRIGGER = {}, {}
ns.CAMERA_TRIGGERS, ns.CAMERA_TRIGGER = TRIGGERS, TRIGGER
local orderCache, triggerRows -- (below: worked out again when a trigger's added)

-- Adds a trigger's rows to the page (key: letters only, as a row id is the
-- key and a copy number), at the end of the list. Again with the same key:
-- its fields replaced, in its place.
function ns.RegisterCameraTrigger(trigger)
	local old = TRIGGER[trigger.key]
	if old then
		for i, each in ipairs(TRIGGERS) do
			if each == old then TRIGGERS[i] = trigger end
		end
	else
		TRIGGERS[#TRIGGERS + 1] = trigger
	end
	TRIGGER[trigger.key] = trigger
	if orderCache then
		orderCache.text, orderCache.list = false, nil
		wipe(triggerRows)
	end
	if ns.CameraRowsChanged then ns.CameraRowsChanged() end
end
-- Takes a trigger's rows off the page (its settings stay). Its rows' ids
-- still name it (RETIRED), for a page's controls made for them before.
local RETIRED = {}
function ns.UnregisterCameraTrigger(key)
	local old = TRIGGER[key]
	if not old then return end
	RETIRED[key] = old
	for i = #TRIGGERS, 1, -1 do
		if TRIGGERS[i] == old then table.remove(TRIGGERS, i) end
	end
	TRIGGER[key] = nil
	orderCache.text, orderCache.list = false, nil
	wipe(triggerRows)
	ns.CameraRowsChanged()
end

-- A built-in trigger, its own row ticked off (off true) or on to start with.
local function OwnScene(trigger, off)
	trigger.sceneOff = "sceneOff" .. trigger.key
	ns.DEFAULTS[trigger.sceneOff] = off
	ns.RegisterCameraTrigger(trigger)
end

-- (A WoW Forever event has no row on retail.)
local FOREVER_ONLY = {}
for _, event in ipairs(ns.EVENTS) do
	if event.forever then FOREVER_ONLY[event.key] = true end
end
for _, trigger in ipairs({
	Event("Hearth", { "tele", "none" }), Event("Teleport", { "tele", "none" }), Event("Logout"), Event("AFK"),
	Event("Sit"), Event("SitButton"), Event("Sleep"), Event("Dance"), Event("Kneel"), Event("Stare"),
	Event("Chair"), Event("Weapon"), Event("Campfire"), Event("Fishing"), Event("Still"),
	Event("Flight", { "flight", "none" }), Event("Quest", { "quest", "none" }),
	Event("QuestGossip", { "quest", "none" }),
	{ key = "Walk", camera = "walkCamera", music = "musicCamWalk", cine = "walkCine", cameras = { "walk", "none" },
		off = "none" },
	{ key = "Run", camera = "runCamera", music = "musicCamRun", cine = "runCine", cameras = { "run", "none" },
		off = "none" },
	{ key = "Death", camera = "deathOrbit", music = "deathSong", cine = "deathCine", cameras = { true, false },
		off = false },
}) do
	-- (A flight's music is the flight camera's own switch.)
	if trigger.key == "Flight" then trigger.music = "musicCamFlight" end
	if not (FOREVER_ONLY[trigger.key] and ns.isRetail) then OwnScene(trigger, false) end
end
-- (The chat camera: ChatCam.lua; no music switch yet.)
if ns.ChatCamCommand then
	-- (Ticked off to start with: the Cinema profile's cameras tick them on.)
	OwnScene({ key = "Chat", camera = "chatCamera", cine = "chatCine", cameras = { "chat", "none" }, off = "none" }, true)
	OwnScene({ key = "ChatNearby", camera = "chatNearbyCamera", cine = "chatNearbyCine",
		cameras = { "chat", "none" }, off = "none" }, true)
	-- Capital cities' citizens never stop chatting: that row's Cities unticked
	-- to start with (its other ticks follow the chat camera's).
	ns.LIST_DEFAULTS.cityShow["trig:ChatNearby"] = false
end

-- Each camera's name, and its row on the old Camera Modes page (ns.CAMERA_OFF_CAMS).
-- (death: the death camera as a trigger of your own plays it; the Die row's is true.)
ns.CAMERA_NAMES = { cozy = L["Cozy camera"], vista = L["Vista camera"], fish = L["Fish camera"], death = L["Death camera"],
	afk = L["AFK camera"], tele = L["Tele camera"], flight = L["Flight camera"], quest = L["Quest camera"],
	walk = L["RP walk camera"], run = L["Auto-run camera"], [true] = L["Death camera"], chat = L["Chat camera"],
	none = L["No camera"], [false] = L["No camera"] }
ns.OnLanguage(function()
	for value, name in pairs(ns.CAMERA_NAMES) do ns.CAMERA_NAMES[value] = L[name] end
end)
local CAM_OF = { cozy = "cozy", vista = "vista", fish = "fish", afk = "idle", tele = "tele", flight = "flight",
	quest = "quest", walk = "walk", run = "run", [true] = "death", chat = "chatcam", death = "death" }
-- A camera value's mode (as ns.CAMERA_OFF_CAMS names it), or nil for none.
-- (A shot: its camera's, Shots.lua.)
local function CamOf(value)
	if ns.ShotBase then value = ns.ShotBase(value) end
	return CAM_OF[value]
end
function ns.CameraValueMode(value) return CamOf(value) end

-- A row's trigger and its number (nil: the trigger's own row).
function ns.CameraRowTrigger(id)
	local key, copy = tostring(id):match("^(%a+)(%d?)$")
	return key and (TRIGGER[key] or RETIRED[key]), tonumber(copy)
end

local function Rows()
	local db = ns.db or ns.GetDB()
	local rows = db and db.cameraRows
	return type(rows) == "table" and rows or {}
end

-- Built-in triggers you've deleted ("deleted": their keys, comma separated):
-- no rows, no camera; their settings stay for Add back (or a Reset).
local deletedCache = { text = false, set = {} }
local function DeletedSet()
	local text = Rows().deleted
	if deletedCache.text ~= text then
		local set = {}
		for key in tostring(text or ""):gmatch("[^,]+") do set[key] = true end
		deletedCache.text, deletedCache.set = text, set
	end
	return deletedCache.set
end
function ns.TriggerDeleted(key) return DeletedSet()[key] == true end
-- The deleted ones, in the page's order.
function ns.DeletedTriggers()
	local list, set = {}, DeletedSet()
	local hidden = ns.SceneGroupState and ns.SceneGroupState().hidden or {}
	for _, trigger in ipairs(TRIGGERS) do
		if set[trigger.key] and not hidden[trigger.key] then list[#list + 1] = trigger.key end
	end
	return list
end
function ns.SetTriggerDeleted(key, deleted)
	local trigger = TRIGGER[key]
	if not trigger or trigger.custom then return end
	local set, list = DeletedSet(), {}
	for _, each in ipairs(TRIGGERS) do
		local on = set[each.key]
		if each.key == key then on = deleted end
		if on then list[#list + 1] = each.key end
	end
	ns.GetDB().cameraRows.deleted = #list > 0 and table.concat(list, ",") or nil
	ns.CameraRowsChanged()
end

-- Built-in triggers taken off their scene's Triggers list ("dropped": their
-- keys, comma separated): they start nothing, the scene's others carry on.
-- Unlike deleting, they stay in their scene (its settings, its group), ready
-- to add back with the + on their line.
local droppedCache = { text = false, set = {} }
local function DroppedSet()
	local text = Rows().dropped
	if droppedCache.text ~= text then
		local set = {}
		for key in tostring(text or ""):gmatch("[^,]+") do set[key] = true end
		droppedCache.text, droppedCache.set = text, set
	end
	return droppedCache.set
end
function ns.TriggerDropped(key) return DroppedSet()[key] == true end
function ns.SetTriggerDropped(key, dropped)
	local trigger = TRIGGER[key]
	if not trigger or trigger.custom then return end
	local set, list = DroppedSet(), {}
	for _, each in ipairs(TRIGGERS) do
		local on = set[each.key]
		if each.key == key then on = dropped end
		if on then list[#list + 1] = each.key end
	end
	ns.GetDB().cameraRows.dropped = #list > 0 and table.concat(list, ",") or nil
	ns.CameraRowsChanged()
end

-- Every row in order: each trigger's own and its copies, the triggers as
-- TRIGGERS has them (a copy before its own row comes first for it), less
-- the deleted ones.
-- Worked out again only when the order changes. (Triggers of your own
-- brought up to date first: a profile loaded has its own.)
orderCache = { text = false }
function ns.CameraRowOrder()
	if ns.SyncCustomTriggers then ns.SyncCustomTriggers() end
	local text = Rows().order
	local deleted = DeletedSet()
	local groups = ns.SceneGroupState()
	if orderCache.text == text and orderCache.deleted == deleted and orderCache.groups == groups.version
		and orderCache.list then
		return orderCache.list
	end
	local byTrigger, seen = {}, {}
	for id in tostring(text or ""):gmatch("[^,]+") do
		local trigger, copy = ns.CameraRowTrigger(id)
		if trigger and not seen[id] and (not copy or (copy >= 2 and copy <= ns.CAMERA_ROW_COPIES)) then
			seen[id] = true
			byTrigger[trigger.key] = byTrigger[trigger.key] or {}
			table.insert(byTrigger[trigger.key], id)
		end
	end
	local list = {}
	for _, trigger in ipairs(TRIGGERS) do
		if not deleted[trigger.key] and not groups.hidden[trigger.key] then
			local own = byTrigger[trigger.key] or {}
			if not seen[trigger.key] then table.insert(own, 1, trigger.key) end
			for _, id in ipairs(own) do list[#list + 1] = id end
		end
	end
	orderCache.text, orderCache.deleted, orderCache.groups, orderCache.list = text, deleted, groups.version, list
	return list
end
-- A trigger's rows, in order.
triggerRows = {}
function ns.TriggerRowIds(key)
	local list = ns.CameraRowOrder()
	local cached = triggerRows[key]
	if cached and cached.from == list then return cached end
	cached = { from = list }
	for _, id in ipairs(list) do
		local trigger = ns.CameraRowTrigger(id)
		if trigger and trigger.key == key then cached[#cached + 1] = id end
	end
	triggerRows[key] = cached
	return cached
end

-- A row's setting (camera, music, cine): a copy's own, else its trigger's
-- own row's. False for a setting the trigger hasn't (no music for it).
function ns.CameraRowValue(id, field)
	local trigger, copy = ns.CameraRowTrigger(id)
	if not trigger then return nil end
	local db = ns.db or ns.GetDB()
	if copy then
		local value = Rows()[id .. "." .. field]
		if value ~= nil then return value end
	end
	if trigger.custom then
		local value = Rows()[trigger.key .. "." .. field]
		if value == nil then return field == "camera" and trigger.off or false end
		return value
	end
	local key = trigger[field]
	if not key then return field == "camera" and trigger.off or false end
	local value = db[key]
	if field == "camera" and (trigger.key == "Hearth" or trigger.key == "Teleport") and value ~= "none" then
		return "tele" -- (its only camera; early test versions saved "cozy")
	end
	return value
end
function ns.SetCameraRowValue(id, field, value)
	local trigger, copy = ns.CameraRowTrigger(id)
	if not trigger then return end
	local db = ns.GetDB()
	if copy or trigger.custom then
		db.cameraRows[id .. "." .. field] = value
	elseif trigger[field] then
		db[trigger[field]] = value
	end
end

-- Whether a row's ticked on (its tick at the start of the row): off, its
-- trigger passes it over, as if its When didn't fit.
-- (A built-in trigger's own row: its setting. Its "off" from before there was
-- one, in a shared profile say, still counts, and goes when it's ticked.)
local function SceneOffKey(id)
	local trigger, copy = ns.CameraRowTrigger(id)
	return trigger and not copy and trigger.sceneOff or nil
end
function ns.CameraRowOn(id)
	if Rows()[id .. ".off"] then return false end
	local key, db = SceneOffKey(id), ns.db or ns.GetDB()
	return not (key and db and db[key])
end
function ns.SetCameraRowOn(id, on)
	local db, key = ns.GetDB(), SceneOffKey(id)
	if key then
		db[key] = not on
		db.cameraRows[id .. ".off"] = nil
	else
		db.cameraRows[id .. ".off"] = not on or nil
	end
	ns.CameraRowsChanged()
end

-- The camera row (Camera Modes' cam:<cam>) a trigger's own row follows, by
-- its camera now; nil for a copy, or with no camera.
local function Leader(id)
	local trigger, copy = ns.CameraRowTrigger(id)
	if copy or not trigger or trigger.custom then return nil end
	return CamOf(ns.CameraRowValue(id, "camera"))
end

-- The lists a row's When is in, and its key in them. (rowFollow: the row it
-- follows, picked in the rule editor's Follow a row.)
ns.CAMERA_ROW_LISTS = { "combatShow", "calmShow", "quietShow", "camShow", "enemyShow", "friendlyShow", "bgShow",
	"worldShow", "cityShow", "groupShow", "instanceShow", "frameRules", "rowFollow" }
local ROW_KEY = setmetatable({}, { __index = function(keys, id)
	local key = "trig:" .. id
	keys[id] = key
	return key
end })
function ns.CameraRowKey(id) return ROW_KEY[id] end

-- The row whose When a row goes by: the one it follows (db.rowFollow, through
-- a chain of them: its ticks, rule, Always and Calm Timer wait all that
-- row's; its own kept for when it stops), else itself.
local function WhenRow(id)
	local db = ns.db or ns.GetDB()
	if not (db and db.rowFollow and db.rowFollow[ROW_KEY[id]]) then return id end
	return ns.FollowKey(ROW_KEY[id]):match("^trig:(.+)$") or id
end
ns.CameraWhenRow = WhenRow
-- A row gone: the rows that followed it go by their own When again.
function ns.DropCameraRowFollowers(id)
	local follow = ns.GetDB().rowFollow
	for key, leader in pairs(follow or {}) do
		if leader == ROW_KEY[id] then follow[key] = nil end
	end
end

-- Whether a trigger's own row has a When of its own yet (else its camera's
-- counts, rule, roles and all, as before the page was one). A tick it starts
-- with (ns.LIST_DEFAULTS) counts.
local function OwnWhen(id)
	local db, key = ns.db or ns.GetDB(), ROW_KEY[id]
	if Rows()[id .. ".always"] ~= nil or Rows()[id .. ".calm"] ~= nil then return true end
	for _, list in ipairs(ns.CAMERA_ROW_LISTS) do
		if type(db[list]) == "table" and db[list][key] ~= nil then return true end
		if ns.LIST_DEFAULTS[list] and ns.LIST_DEFAULTS[list][key] ~= nil then return true end
	end
	return false
end

-- Keeps a trigger's own row's unset ticks following its camera's (the
-- lists' ns.ROW_FALLBACK), for the page and for the rows' When.
function ns.CameraRowFollow(id)
	local leader = Leader(id)
	if ns.ROW_FALLBACK then ns.ROW_FALLBACK[ROW_KEY[id]] = leader and ("cam:" .. leader) or nil end
	return leader
end

-- A row's Always and Calm Timer wait: its own, else (a trigger's own row)
-- its camera's. (Following a row: that row's.)
function ns.CameraRowAlways(id)
	id = WhenRow(id)
	local own = Rows()[id .. ".always"]
	if own ~= nil then return own end
	local leader = Leader(id)
	return leader and ns.GetDB()["camAlways" .. leader] and true or false
end
function ns.CameraRowCalm(id)
	-- (The death camera never waits, following a row that does or not.)
	local trigger = ns.CameraRowTrigger(id)
	if trigger and trigger.key == "Death" then return false end
	id = WhenRow(id)
	local own = Rows()[id .. ".calm"]
	if own ~= nil then return own end
	local leader = Leader(id)
	return leader and not ns.CALM_WAIT_NEVER[leader] and ns.GetDB()[leader .. "CalmWait"] and true or false
end

-- Whether a row's When fits now. A flight's places are where it took off: a
-- capital city or the open world (its rule aside).
local function Fits(key, always, flight)
	if flight and ns.OnTaxi() and not ns.RuleTest(key) then
		if always then return true end
		return ns.IsPlaceShowOn(ns.db.takeoffInCity and "cityShow" or "worldShow", key)
	end
	return ns.RowOnNow(key, always, true)
end
-- In a fight a row fits only with In combat ticked (or Always, or by its
-- rule); the death camera's aside: you die in one.
local function FightFits(key, always)
	if always or ns.RuleTest(key) ~= nil or not ns.Flag(UnitAffectingCombat("player")) then return true end
	return ns.IsCombatShowOn(key) and true or false
end
local function RowFits(id)
	local trigger = ns.CameraRowTrigger(id)
	id = WhenRow(id) -- (following another row: its When)
	local leader = ns.CameraRowFollow(id)
	if trigger.key ~= "Death" then
		local key, always = ROW_KEY[id], ns.CameraRowAlways(id)
		if leader and not OwnWhen(id) then key, always = "cam:" .. leader, ns.db["camAlways" .. leader] and true or false end
		if not FightFits(key, always) then return false end
	end
	local flight = trigger.key == "Flight"
	if leader and not OwnWhen(id) then
		return Fits("cam:" .. leader, ns.db["camAlways" .. leader] and true or false, flight)
	end
	return Fits(ROW_KEY[id], ns.CameraRowAlways(id), flight)
end

-- The row a trigger goes by now: the first of its rows whose When fits, or
-- nil (no camera). Worked out once a frame for each trigger.
local nowCache = { at = -1 }
function ns.TriggerRowNow(key)
	if ns.db and DroppedSet()[key] then return nil end -- (taken off its scene's Triggers)
	if ns.db and TRIGGER[key] then key = ns.SceneLead(key) end -- (a group's member: its lead's rows)
	if not ns.db or not TRIGGER[key] or DeletedSet()[key] then return nil end
	local now = GetTime()
	if nowCache.at ~= now then
		wipe(nowCache)
		nowCache.at = now
	end
	local id = nowCache[key]
	if id == nil then
		id = false
		for _, each in ipairs(ns.TriggerRowIds(key)) do
			if ns.CameraRowOn(each) and RowFits(each) then
				id = each
				break
			end
		end
		nowCache[key] = id
	end
	return id or nil
end
-- (Settings changed: worked out afresh.)
function ns.CameraRowsChanged()
	wipe(nowCache)
	nowCache.at = -1
	if ns.InvalidateSceneGroups then ns.InvalidateSceneGroups() end
end

-- A trigger's setting now (camera, music, cine), from the row it goes by:
-- with none fitting, no camera, and off.
function ns.TriggerSetting(key, field)
	local id = ns.TriggerRowNow(key)
	if not id then
		return field == "camera" and TRIGGER[key] and TRIGGER[key].off or false
	end
	-- (Dev copy: our cameras run as their scripts, CameraScripts.lua.)
	if field == "camera" and ns.ScriptBuiltInsOn and ns.ScriptBuiltInsOn() then
		return ns.BuiltInAsScript(ns.CameraRowValue(id, field))
	end
	return ns.CameraRowValue(id, field)
end
-- Whether a trigger's camera now is one (and not none).
function ns.TriggerHasCamera(key)
	local camera = ns.TriggerSetting(key, "camera")
	return camera ~= nil and camera ~= false and camera ~= "none"
end

-- Whether any of a trigger's rows, here or anywhere, has a camera (or a
-- setting, field, ticked): for greying a camera's settings out.
function ns.TriggerAnyRow(key, field)
	local trigger = TRIGGER[key]
	if not trigger or not ns.GetDB() then return false end
	key = ns.SceneLead(key) -- (a group's member: its lead's rows)
	for _, id in ipairs(ns.TriggerRowIds(key)) do
		local value = ns.CameraRowOn(id) and ns.CameraRowValue(id, field or "camera")
		if field and value then return true end
		if not field and ns.CameraRowOn(id) and value ~= trigger.off then return true end
	end
	return false
end

-- The trigger a camera mode is running for: its own (flights, auto-walk...),
-- or the event that picked it (the AFK, cozy, vista, fish and tele cameras).
local MODE_TRIGGER = { flight = "Flight", taxi = "Flight", walk = "Walk", run = "Run", death = "Death",
	chatcam = "Chat" }
function ns.CameraModeTrigger(mode)
	if mode == "quest" then return ns.QuestCamEvent and ns.QuestCamEvent() or "Quest" end
	if MODE_TRIGGER[mode] then return MODE_TRIGGER[mode] end
	local key = ns.ActiveEvent and ns.ActiveEvent()
	if key and TRIGGER[key] then return key end
	return mode == "idle" and "Still" or nil
end

-- The cameras with a trigger of their own: off here unless the row their
-- trigger goes by now is set to them. (The chat camera: either of its rows.)
local OWN_TRIGGER = { flight = { "Flight" }, walk = { "Walk" }, run = { "Run" }, death = { "Death" },
	chatcam = { "Chat", "ChatNearby" } }
function ns.CameraRowsOff(cam)
	local keys = OWN_TRIGGER[cam]
	if cam == "quest" then keys = { ns.QuestCamEvent and ns.QuestCamEvent() or "Quest" } end
	-- (A trigger of your own running it: CustomTriggers.lua.)
	if cam == "death" and ns.CustomDeathOn and ns.CustomDeathOn() then return false end
	if not keys then return false end -- (the event cameras: their rows decide as an event picks one)
	for _, key in ipairs(keys) do
		if TRIGGER[key] and CamOf(ns.TriggerSetting(key, "camera")) == cam then return false end
	end
	return true
end

-- Whether a camera with a trigger of its own plays as its script now: the
-- row its trigger goes by set to it while our cameras play their scripts
-- (CameraScripts.lua). Its own code is off then (ns.CameraRowsOff), but it's
-- still that camera: the death song, the ghost screen...
local SCRIPT_OF = { flight = "flight", walk = "walk", run = "run", death = "death", chatcam = "chat", quest = "quest" }
function ns.CameraRowsScripted(cam)
	local keys = OWN_TRIGGER[cam]
	if cam == "quest" then keys = { ns.QuestCamEvent and ns.QuestCamEvent() or "Quest" } end
	if not keys or not SCRIPT_OF[cam] then return false end
	for _, key in ipairs(keys) do
		if TRIGGER[key] and ns.TriggerSetting(key, "camera") == "script:" .. SCRIPT_OF[cam] then return true end
	end
	return false
end

-- The same in words, for /cine debug mode: each of its trigger's rows, and
-- why it isn't the one (ticked off, its When, or another camera).
local PLACE_LISTS = { "worldShow", "cityShow", "instanceShow", "bgShow", "groupShow" }
function ns.CameraRowsOffWhy(cam)
	local keys = OWN_TRIGGER[cam]
	if cam == "quest" then keys = { ns.QuestCamEvent and ns.QuestCamEvent() or "Quest" } end
	if not keys then return "its event's row decides (see the event line)" end
	local why = {}
	for _, key in ipairs(keys) do
		local lead = TRIGGER[key] and ns.SceneLead(key)
		for _, id in ipairs(lead and ns.TriggerRowIds(lead) or {}) do
			local whenId = WhenRow(id)
			local leader = ns.CameraRowFollow(whenId)
			local when = (leader and not OwnWhen(whenId)) and ("cam:" .. leader) or ROW_KEY[whenId]
			local places = {}
			for _, list in ipairs(PLACE_LISTS) do
				if ns.IsPlaceShowOn(list, when) then places[#places + 1] = list:gsub("Show$", "") end
			end
			local state = not ns.CameraRowOn(id) and "ticked off"
				or not RowFits(id) and ("When doesn't fit (always %s, in combat %s, rule %s, places %s)"):format(
					tostring(ns.CameraRowAlways(id)), tostring(ns.IsCombatShowOn(when) and true or false),
					tostring(ns.RuleTest(when) ~= nil), #places > 0 and table.concat(places, "/") or "none")
				or ("fits, plays %s"):format(tostring(ns.CameraRowValue(id, "camera")))
			why[#why + 1] = ("%s row %s %s"):format(key, id, state)
		end
	end
	return #why > 0 and table.concat(why, "; ") or "no row"
end

-- A camera's Calm Timer wait now: the row its trigger goes by.
function ns.CameraWaitsForCalm(mode)
	local key = ns.CameraModeTrigger(mode)
	local id = key and ns.TriggerRowNow(key)
	return id and ns.CameraRowCalm(id) or false
end

-- A copy of a row: the next free number of its trigger, nil with all taken.
function ns.FreeCameraRow(key)
	local on = {}
	for _, id in ipairs(ns.CameraRowOrder()) do on[id] = true end
	for copy = 2, ns.CAMERA_ROW_COPIES do
		if not on[key .. copy] then return key .. copy end
	end
end

-- Puts the rows in this order (a list of ids).
function ns.SetCameraRowOrder(list)
	ns.GetDB().cameraRows.order = table.concat(list, ",")
	ns.CameraRowsChanged()
end

-- A copy of row id, just below it: its camera, music, CineMode, name and
-- When written out (its trigger's own row's, its camera's where it follows
-- it). Gives the copy's id, or nil.
function ns.CopyCameraRow(id)
	local trigger = ns.CameraRowTrigger(id)
	local new = trigger and ns.FreeCameraRow(trigger.key)
	if not new then return nil end
	local db, rows = ns.GetDB(), ns.GetDB().cameraRows
	for _, field in ipairs({ "camera", "music", "cine" }) do
		rows[new .. "." .. field] = ns.CameraRowValue(id, field)
	end
	local own = rows[id .. ".name"]
	rows[new .. ".name"] = type(own) == "string" and own:find("%S") and (L["%s (copy)"]):format(own):sub(1, 40) or nil
	ns.CameraRowFollow(id)
	local from = (Leader(id) and not OwnWhen(id)) and ("cam:" .. Leader(id)) or ROW_KEY[id]
	if from == ROW_KEY[id] then
		rows[new .. ".always"] = ns.CameraRowAlways(id)
	else
		rows[new .. ".always"] = db["camAlways" .. Leader(id)] and true or false
	end
	rows[new .. ".calm"] = ns.CameraRowCalm(id)
	rows[new .. ".off"] = not ns.CameraRowOn(id) or nil
	local IS_ON = { combatShow = ns.IsCombatShowOn, calmShow = ns.IsCalmShowOn, quietShow = ns.IsQuietShowOn,
		camShow = ns.IsCamShowOn, enemyShow = ns.IsEnemyShowOn, friendlyShow = ns.IsFriendlyShowOn }
	for _, list in ipairs(ns.CAMERA_ROW_LISTS) do
		if type(db[list]) ~= "table" then db[list] = {} end
		if IS_ON[list] then
			db[list][ROW_KEY[new]] = IS_ON[list](from) and true or false
		elseif list:find("Show$") then
			db[list][ROW_KEY[new]] = ns.IsPlaceShowOn(list, from) and true or false
		else
			db[list][ROW_KEY[new]] = db[list][from]
		end
	end
	local order = ns.CameraRowOrder()
	local list, at = {}, nil
	for i, each in ipairs(order) do
		list[i] = each
		if each == id then at = i + 1 end
	end
	table.insert(list, at or #list + 1, new)
	ns.SetCameraRowOrder(list)
	return new
end

-- Takes a copy off (a trigger's own row stays: its camera goes to none).
function ns.RemoveCameraRow(id)
	local _, copy = ns.CameraRowTrigger(id)
	if not copy then return end
	local db, rows = ns.GetDB(), ns.GetDB().cameraRows
	for _, field in ipairs({ "camera", "music", "cine", "name", "always", "calm", "off" }) do
		rows[id .. "." .. field] = nil
	end
	for _, list in ipairs(ns.CAMERA_ROW_LISTS) do
		if type(db[list]) == "table" then db[list][ROW_KEY[id]] = nil end
	end
	ns.DropCameraRowFollowers(id)
	local list = {}
	for _, each in ipairs(ns.CameraRowOrder()) do
		if each ~= id then list[#list + 1] = each end
	end
	ns.SetCameraRowOrder(list)
end

-- Moves a row up (by -1) or down among its trigger's rows.
function ns.MoveCameraRow(id, by)
	local trigger = ns.CameraRowTrigger(id)
	local list = {}
	for i, each in ipairs(ns.CameraRowOrder()) do list[i] = each end
	for i, each in ipairs(list) do
		local other = list[i + by]
		if each == id and other and ns.CameraRowTrigger(other) == trigger then
			list[i], list[i + by] = other, each
			break
		end
	end
	ns.SetCameraRowOrder(list)
end

-- Built-in scenes with several triggers: triggers that play the same camera
-- with the same settings, differing only in what starts them, are one scene
-- on the page, its row the first member's (the lead's). A member goes by the
-- lead's rows (copies too). Who's in which scene is fixed: worked out once
-- for a profile from who matches (FixScenes: "scenesFixed", and "scene:<key>"
-- for a trigger not in its group: "" a scene of its own, or the key of the
-- trigger whose scene it's in), then changed only by moving a trigger
-- (ns.MoveTriggerToScene, the Triggers page). Changing a scene writes every
-- member (SyncSceneGroup), and each keeps its own settings for older versions.
ns.SCENE_GROUPS = {
	{ key = "Cozy", name = L["Cozy moments"],
		members = { "Campfire", "SitButton", "Sleep", "Dance", "Kneel", "Chair", "Weapon", "Logout" } },
	{ key = "Vista", name = L["Looking out"], members = { "Sit", "Stare" } },
	{ key = "Away", name = L["Away"], members = { "AFK", "Still" } },
	{ key = "Depart", name = L["Departing"], members = { "Hearth", "Teleport" } },
	{ key = "QuestGivers", name = L["Quest givers"], members = { "Quest", "QuestGossip" } },
}
ns.OnLanguage(function() ns.TranslateFields(ns.SCENE_GROUPS, "name") end)

local ROW_FIELDS = { "camera", "music", "cine" }
local WHEN_ON = { combatShow = "IsCombatShowOn", calmShow = "IsCalmShowOn", quietShow = "IsQuietShowOn",
	camShow = "IsCamShowOn", enemyShow = "IsEnemyShowOn", friendlyShow = "IsFriendlyShowOn" }
-- A row's When in one list, as it goes by it (its camera's, while it follows it).
local function WhenOf(id, list)
	local leader = ns.CameraRowFollow(id)
	local from = (leader and not OwnWhen(id)) and ("cam:" .. leader) or ROW_KEY[id]
	local on = ns[WHEN_ON[list] or ""]
	if on then return on(from) and true or false end
	if list:find("Show$") then return ns.IsPlaceShowOn(list, from) and true or false end
	local db = ns.db
	return type(db[list]) == "table" and db[list][from] or nil
end
-- Whether a trigger has copies of its own (the row order's text, as saved).
local function HasCopies(key)
	return ("," .. tostring(Rows().order or "") .. ","):find("," .. key .. "[2-5],") ~= nil
end
local function SameRow(member, lead)
	local deleted = DeletedSet()
	if HasCopies(member) or deleted[member] ~= deleted[lead] then return false end
	if ns.CameraRowOn(member) ~= ns.CameraRowOn(lead) then return false end
	for _, field in ipairs(ROW_FIELDS) do
		if ns.CameraRowValue(member, field) ~= ns.CameraRowValue(lead, field) then return false end
	end
	if ns.CameraRowAlways(member) ~= ns.CameraRowAlways(lead) or ns.CameraRowCalm(member) ~= ns.CameraRowCalm(lead) then
		return false
	end
	for _, list in ipairs(ns.CAMERA_ROW_LISTS) do
		if WhenOf(member, list) ~= WhenOf(lead, list) then return false end
	end
	return true
end

-- A profile's scenes fixed, once: a group's member that doesn't match its
-- first (another camera, say) gets a scene of its own, as it had while
-- groups were worked out each time.
local function FixScenes(rows)
	if rows.scenesFixed then return end
	rows.scenesFixed = true
	for _, group in ipairs(ns.SCENE_GROUPS) do
		local first
		for _, key in ipairs(group.members) do
			if TRIGGER[key] then
				if not first then
					first = key
				elseif not SameRow(key, first) then
					rows["scene:" .. key] = ""
				end
			end
		end
	end
end

-- Who's in each scene now: lead[key] (a member's lead), members[lead] (the
-- lead and those with it), hidden[key] (members off the page). Worked out
-- again after a change, or each second (a profile loaded elsewhere); version
-- counts the times it came out different. members stays as last worked out
-- until then, for SyncSceneGroup after an edit.
local groupState = { valid = false, at = -1, version = 0, sig = false, lead = {}, members = {}, hidden = {},
	groupOf = {} }
local function GroupState()
	local rows, now = Rows(), GetTime()
	if groupState.valid and groupState.rows == rows and now - groupState.at < 1 then return groupState end
	groupState.valid, groupState.rows, groupState.at = true, rows, now
	if not ns.db then return groupState end
	FixScenes(rows)
	local lead, members, hidden, groupOf, sig = {}, {}, {}, {}, {}
	for _, group in ipairs(ns.SCENE_GROUPS) do
		local first
		for _, key in ipairs(group.members) do
			if TRIGGER[key] and rows["scene:" .. key] == nil then
				if not first then
					first = key
					lead[key], members[key], groupOf[key] = key, { key }, group
				else
					lead[key], hidden[key] = first, true
					table.insert(members[first], key)
				end
			end
		end
	end
	-- (Those moved into another's scene: into its lead's, it a scene of its
	-- own till now if it's in no group.)
	for _, trigger in ipairs(TRIGGERS) do
		local key = trigger.key
		local target = rows["scene:" .. key]
		if type(target) == "string" and target ~= "" and target ~= key and TRIGGER[target]
			and rows["scene:" .. target] ~= key then
			local first = lead[target] or target
			if first ~= key then
				if not members[first] then lead[first], members[first] = first, { first } end
				lead[key], hidden[key] = first, true
				table.insert(members[first], key)
			end
		end
	end
	for first, list in pairs(members) do sig[#sig + 1] = first .. "=" .. table.concat(list, ",") end
	table.sort(sig)
	sig = table.concat(sig, ";")
	if sig ~= groupState.sig then
		groupState.sig, groupState.version = sig, groupState.version + 1
		groupState.lead, groupState.members, groupState.hidden, groupState.groupOf = lead, members, hidden, groupOf
	end
	return groupState
end
ns.SceneGroupState = GroupState
function ns.InvalidateSceneGroups() groupState.valid = false end

-- A trigger's lead: the one whose rows it goes by (itself, out of a group).
function ns.SceneLead(key)
	return GroupState().lead[key] or key
end
-- A lead's group (with more than itself in it), or nil.
function ns.SceneGroupOf(key)
	local state = GroupState()
	local members = state.members[key]
	return members and #members > 1 and state.groupOf[key] or nil
end
-- A lead and the members with it (as last worked out), or { key }.
function ns.SceneGroupMembers(key)
	return groupState.members[key] or { key }
end

-- Copies a lead's own row to the members with it: camera, music, CineMode,
-- on or off, its When (as saved: following its camera stays so).
function ns.SyncSceneGroup(key)
	local list = groupState.members[key]
	if not list or #list < 2 then return end
	local db, rows = ns.GetDB(), ns.GetDB().cameraRows
	for _, member in ipairs(list) do
		if member ~= key then
			for _, field in ipairs(ROW_FIELDS) do
				if TRIGGER[member][field] then ns.SetCameraRowValue(member, field, ns.CameraRowValue(key, field)) end
			end
			for _, field in ipairs({ "off", "always", "calm" }) do
				rows[member .. "." .. field] = rows[key .. "." .. field]
			end
			if TRIGGER[member].sceneOff then db[TRIGGER[member].sceneOff] = not ns.CameraRowOn(key) end
			for _, each in ipairs(ns.CAMERA_ROW_LISTS) do
				if type(db[each]) == "table" then db[each][ROW_KEY[member]] = db[each][ROW_KEY[key]] end
			end
		end
	end
end
-- After a change on the page: every scene's members follow their lead.
function ns.SyncAllSceneGroups()
	for key in pairs(groupState.members) do ns.SyncSceneGroup(key) end
end
-- A change to a lead's own row (fn makes it) that its members follow.
function ns.EditScene(key, fn)
	GroupState() -- (who's with it now, before the change)
	fn()
	ns.SyncSceneGroup(key)
	ns.CameraRowsChanged()
end
-- Moves one of our triggers to another's scene (to: any key in it), or to a
-- scene of its own (""). It takes on that scene's settings; its old scene
-- carries on without it. Back in its own group, nothing's saved for it.
function ns.MoveTriggerToScene(key, to)
	if not TRIGGER[key] or TRIGGER[key].custom then return end
	local rows = Rows()
	GroupState()
	to = to ~= "" and to ~= nil and ns.SceneLead(to) or ""
	if to == key then return end
	-- (Leaving a scene it leads: the next member leads it, by its group's
	-- order, or by the first one moved in.)
	local stayers = {}
	for _, member in ipairs(ns.SceneGroupMembers(key)) do
		if member ~= key then stayers[#stayers + 1] = member end
	end
	local home
	for _, group in ipairs(ns.SCENE_GROUPS) do
		for _, member in ipairs(group.members) do
			if member == key then home = group end
		end
	end
	local homeLead
	if home then
		for _, member in ipairs(home.members) do
			if member ~= key and TRIGGER[member] and rows["scene:" .. member] == nil then
				homeLead = member
				break
			end
		end
	end
	local wasLead = ns.SceneLead(key) == key
	if homeLead ~= nil and to == homeLead then
		rows["scene:" .. key] = nil
	else
		rows["scene:" .. key] = to
	end
	-- (Members moved in behind it stay with the rest of its scene.)
	if wasLead and #stayers > 0 then
		local heir = stayers[1]
		for _, member in ipairs(stayers) do
			if rows["scene:" .. member] == key then rows["scene:" .. member] = member ~= heir and heir or "" end
		end
	end
	groupState.valid = false
	GroupState()
	if to ~= "" then ns.SyncSceneGroup(ns.SceneLead(to)) end
	ns.CameraRowsChanged()
end

-- The scenes one of our triggers can move to: the leads of built-in scenes
-- with the same cameras to pick from (a Hearthstone's tele camera needs a
-- cast: it can't go in with the emotes), not the one it's in.
local function SameCameras(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
	for i, each in ipairs(a) do
		if b[i] ~= each then return false end
	end
	return true
end
function ns.SceneMoveTargets(key)
	local list, trigger = {}, TRIGGER[key]
	if not trigger or trigger.custom then return list end
	local now = ns.SceneLead(key)
	for _, each in ipairs(TRIGGERS) do
		if not each.custom and ns.SceneLead(each.key) == each.key and each.key ~= now
			and not DeletedSet()[each.key] and SameCameras(each.cameras, trigger.cameras) then
			list[#list + 1] = each.key
		end
	end
	return list
end

-- Deleting or bringing back a scene: a group's members with it.
function ns.SetSceneDeleted(key, deleted)
	GroupState()
	for _, member in ipairs(ns.SceneGroupMembers(key)) do ns.SetTriggerDeleted(member, deleted) end
end

-- For /cine debug: each trigger's rows, and the one it goes by now.
function ns.DescribeCameraRows()
	local lines = {}
	for _, trigger in ipairs(TRIGGERS) do
		local ids = ns.TriggerRowIds(trigger.key)
		local now = ns.TriggerRowNow(trigger.key)
		lines[#lines + 1] = ("%s: %s -> %s (%s)"):format(trigger.key, table.concat(ids, ","), tostring(now),
			tostring(ns.TriggerSetting(trigger.key, "camera")))
	end
	return lines
end

-- Scenes a profile had off used to lose their camera (No camera) or, for RP
-- walk, auto-run and the death camera, every place tick: now they keep their
-- camera and ticks and are ticked off, so each camera stays in its scene. t: a
-- profile's settings, live or saved (nil: its base's). A camera on a row that
-- played it stays on, its scene ticked on.
local PLACE_OFF = { Walk = true, Run = true, Death = true }
local PLACES = { "worldShow", "cityShow", "instanceShow" }
local function OwnWhenIn(t, id)
	local rows = type(t.cameraRows) == "table" and t.cameraRows or {}
	if rows[id .. ".always"] ~= nil or rows[id .. ".calm"] ~= nil then return true end
	for _, list in ipairs(ns.CAMERA_ROW_LISTS) do
		if type(t[list]) == "table" and t[list][ROW_KEY[id]] ~= nil then return true end
	end
	return false
end
local function NoPlaces(t, key)
	for _, list in ipairs(PLACES) do
		if type(t[list]) ~= "table" then return false end
		local tick = t[list][key]
		if tick == nil then tick = ns.LIST_DEFAULTS[list][key] end
		if tick then return false end
	end
	return true
end
function ns.ScenesOffKeepCameras(t)
	if type(t) ~= "table" then return end
	for _, trigger in ipairs(TRIGGERS) do
		local own = trigger.sceneOff and ns.DEFAULTS[trigger.camera]
		if own ~= nil and own ~= trigger.off then
			local value, placed = t[trigger.camera], PLACE_OFF[trigger.key] and not OwnWhenIn(t, trigger.key)
			local rowKey = placed and "cam:" .. CamOf(own)
			if value == trigger.off then
				t[trigger.camera], t[trigger.sceneOff] = own, true
			elseif placed and NoPlaces(t, rowKey) then
				t[trigger.sceneOff] = true
				for _, list in ipairs(PLACES) do t[list][rowKey] = nil end
			elseif value ~= nil or (placed and type(t.worldShow) == "table") then
				t[trigger.sceneOff] = false
			end
		end
	end
end

-- Dev copy, once (2026-11-03): the built-in rows a profile's Cameras off part
-- left on No camera (ProfileModules.lua's CamsOff) back on their cameras, the
-- chat rows on Chat Cam.
if ns.isDev then
	local once = CreateFrame("Frame")
	once:RegisterEvent("PLAYER_LOGIN")
	once:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		local db = ns.db
		if not db or db.devRowCamerasBack then return end
		db.devRowCamerasBack = true
		if ns.newInstall then return end -- (nothing left on No camera by a profile yet)
		for _, trigger in ipairs(TRIGGERS) do
			local key = not trigger.custom and type(trigger.camera) == "string" and trigger.camera
			if key and db[key] == "none" then
				local own = (trigger.key == "Chat" or trigger.key == "ChatNearby") and "chat" or ns.DEFAULTS[key]
				if own ~= nil and own ~= "none" then db[key] = own end
			end
		end
		if ns.CameraRowsChanged then ns.CameraRowsChanged() end
	end)
end
