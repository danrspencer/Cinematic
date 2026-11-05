-- Cinematic: the trigger library (the Triggers page, Camera hub). Every
-- trigger of yours is one entry here, named, with the same parts as every
-- other: what starts it (its source and when in it), Only if (a CQL rule),
-- what ends it, its timing (a wait, a least time, a cooldown, a chance) and
-- its priority. Scenes pick triggers from here (their lists hold "t:<id>");
-- CustomTriggers.lua plays them. Our own triggers (Hearthstone, AFK, the
-- emotes...) are listed too, with their place in the priority list; their
-- other parts are still written into the cameras' code (moved here later).
--
-- Saved in db.cameraRows with the scenes (profiles, Save/Reset and share
-- strings carry them): "lib" the ids (TrigA, TrigB...), and per trigger:
--   name    your name for it (nil: what starts it)
--   src     "<kind>:<what>" (CustomTriggers.lua's kinds)
--   at      when in it: spell start|success, aura gain|lose, place
--           arrive|leave, state true|false, interact open|close (nil: the first)
--   cond    a CQL rule it needs to start (nil: always)
--   ends    "|" between: ends (the trigger itself ends), time:<sec>, key
--           (pressed again), trig:<id> (that trigger starts), never (only
--           moving or the camera's own rules); nil: its kind's (KIND_ENDS)
--   delay, hold, cd  seconds: wait before starting, keep going at least, cooldown
--   chance  1-100 (nil: 100)    rearm  "no": may start again while still true
--   pri     its place in the priority list (lower first; nil: 510)
-- And "prio.<source>": a built-in source's place, moved (Triggers.lua).
local _, ns = ...
local L = ns.L

ns.TRIGGER_LIB_MAX = 60
ns.TRIGGER_DEFAULT_PRI = 510 -- (just after the emotes and seats)
ns.TRIGGER_ENDS_MAX = 3
local EMPTY = {}

local function Rows()
	local db = ns.db
	return db and type(db.cameraRows) == "table" and db.cameraRows or nil
end

-- Each kind's phases (the first is its default) and what ends it to start with.
ns.TRIGGER_PHASES = {
	spell = { { value = "start", text = L["The cast starts"] }, { value = "success", text = L["The cast succeeds"] } },
	aura = { { value = "gain", text = L["You gain it"] }, { value = "lose", text = L["It fades"] } },
	place = { { value = "arrive", text = L["You arrive"] }, { value = "leave", text = L["You leave"] } },
	state = { { value = "true", text = L["It becomes true"] }, { value = "false", text = L["It stops being true"] } },
	interact = { { value = "open", text = L["The window opens"] }, { value = "close", text = L["The window closes"] } },
}
ns.OnLanguage(function()
	for _, list in pairs(ns.TRIGGER_PHASES) do ns.TranslateFields(list, "text") end
end)
local KIND_ENDS = { emote = "never", spell = "ends", aura = "ends", place = "ends", moment = "time:5", state = "ends",
	interact = "ends", key = "key", ours = "ends" }
ns.TRIGGER_KIND_ENDS = KIND_ENDS
-- (The kinds read over and over, true while their thing is: these may start
-- again once it has stopped; the rest start on an event.)
ns.TRIGGER_HELD_KINDS = { aura = true, place = true, state = true, interact = true, ours = true }

-- The ids, in order (worked out again only when the text changes).
local libCache = { text = false, list = EMPTY, set = {} }
function ns.TriggerLibList()
	local rows = Rows()
	local text = rows and rows.lib or nil
	if libCache.text ~= text then
		local list, set = {}, {}
		for id in tostring(text or ""):gmatch("[^,]+") do
			if id:find("^Trig%a+$") and not set[id] and #list < ns.TRIGGER_LIB_MAX then
				list[#list + 1], set[id] = id, true
			end
		end
		libCache.text, libCache.list, libCache.set = text, list, set
	end
	return libCache.list, libCache.set
end
function ns.IsLibTrigger(id) return (select(2, ns.TriggerLibList()))[id] == true end

-- Changed by anything here: the units read their triggers again (CustomTriggers.lua).
ns.triggerLibVersion = 0
local function Changed()
	ns.triggerLibVersion = ns.triggerLibVersion + 1
	if ns.CustomTriggersChanged then ns.CustomTriggersChanged() end
end
ns.TriggerLibChanged = Changed

function ns.TriggerField(id, field)
	local rows = Rows()
	-- (One of ours starts as its camera's code says: "ours:<key>".)
	if field == "src" and ns.OursKeyOf(id) then return "ours:" .. ns.OursKeyOf(id) end
	return rows and id and rows[id .. "." .. field] or nil
end
function ns.SetTriggerField(id, field, value)
	ns.GetDB().cameraRows[id .. "." .. field] = value
	Changed()
end

-- Its endings, a list: { kind = "ends"|"time"|"key"|"trig"|"never", secs, ref }.
function ns.TriggerEnds(id)
	local src = tostring(ns.TriggerField(id, "src") or "")
	local text = ns.TriggerField(id, "ends")
	if type(text) ~= "string" or text == "" then text = KIND_ENDS[src:match("^(%a+):") or "emote"] or "never" end
	local list = {}
	for each in text:gmatch("[^|]+") do
		local secs = tonumber(each:match("^time:(%d+%.?%d*)$"))
		local ref = each:match("^trig:(Trig%a+)$")
		if secs then
			list[#list + 1] = { kind = "time", secs = secs }
		elseif ref then
			list[#list + 1] = { kind = "trig", ref = ref }
		elseif each == "ends" or each == "key" or each == "never" then
			list[#list + 1] = { kind = each }
		end
		if #list >= ns.TRIGGER_ENDS_MAX then break end
	end
	if #list == 0 then list[1] = { kind = "never" } end
	return list
end
function ns.SetTriggerEnds(id, list)
	local out = {}
	for _, each in ipairs(list) do
		if each.kind == "time" then out[#out + 1] = "time:" .. (tonumber(each.secs) or 5)
		elseif each.kind == "trig" and each.ref then out[#out + 1] = "trig:" .. each.ref
		elseif each.kind then out[#out + 1] = each.kind end
	end
	local text = table.concat(out, "|")
	local src = tostring(ns.TriggerField(id, "src") or "")
	if text == KIND_ENDS[src:match("^(%a+):") or "emote"] then text = nil end
	ns.SetTriggerField(id, "ends", text ~= "" and text or nil)
end

function ns.TriggerPri(id)
	local ours = ns.OursKeyOf(id)
	if ours then return ns.OursPri(ours) or ns.TRIGGER_DEFAULT_PRI end
	return tonumber(ns.TriggerField(id, "pri")) or ns.TRIGGER_DEFAULT_PRI
end
function ns.TriggerNumber(id, field, default) return tonumber(ns.TriggerField(id, field)) or default end

-- Its name: yours, else what starts it.
function ns.TriggerLabel(id)
	local ours = ns.OursKeyOf(id) and ns.OursTrigger(id)
	if ours then return ours.name end
	local name = ns.TriggerField(id, "name")
	if type(name) == "string" and name:find("%S") then return name end
	return ns.DescribeTriggerSource and ns.DescribeTriggerSource(ns.TriggerField(id, "src")) or tostring(id)
end

-- A free id (nil with all taken).
local function FreeId()
	local _, set = ns.TriggerLibList()
	for n = 0, 701 do
		local letters = n < 26 and string.char(65 + n) or string.char(64 + math.floor(n / 26), 65 + n % 26)
		if not set["Trig" .. letters] then return "Trig" .. letters end
	end
end
-- A new trigger: its id, or nil with the library full. fields: name, at,
-- cond, ends, delay, hold, cd, chance, rearm, pri (as saved).
function ns.AddLibTrigger(src, fields)
	local list = ns.TriggerLibList()
	if #list >= ns.TRIGGER_LIB_MAX then return nil end
	local id = FreeId()
	if not id then return nil end
	local rows = ns.GetDB().cameraRows
	rows[id .. ".src"] = tostring(src or "emote:cheer"):gsub("|", "")
	for field, value in pairs(fields or EMPTY) do rows[id .. "." .. field] = value end
	rows.lib = (rows.lib and rows.lib ~= "" and rows.lib .. "," or "") .. id
	Changed()
	return id
end
local FIELDS = { "name", "src", "at", "cond", "ends", "delay", "hold", "cd", "chance", "rearm", "pri" }
ns.TRIGGER_FIELDS = FIELDS
-- A copy of one, named "<name> (copy)": its id, or nil.
function ns.CopyLibTrigger(id)
	local fields = {}
	for _, field in ipairs(FIELDS) do fields[field] = ns.TriggerField(id, field) end
	fields.name = (L["%s (copy)"]):format(ns.TriggerLabel(id))
	local src = fields.src
	fields.src = nil
	return ns.AddLibTrigger(src, fields)
end

-- The scenes that use it, in the page's order: their keys.
function ns.TriggerUsers(id)
	local list, ref = {}, "t:" .. id
	for _, trigger in ipairs(ns.CAMERA_TRIGGERS or EMPTY) do
		for _, source in ipairs(ns.SceneTriggers and ns.SceneTriggers(trigger.key) or EMPTY) do
			if source == ref then
				list[#list + 1] = trigger.key
				break
			end
		end
	end
	return list
end

-- Takes it out of the library: off every scene and every other trigger's
-- endings too. (A scene of yours left with none starts nothing.)
function ns.RemoveLibTrigger(id)
	local rows = ns.GetDB().cameraRows
	for _, key in ipairs(ns.TriggerUsers(id)) do
		local kept = {}
		for _, source in ipairs(ns.SceneTriggers(key)) do
			if source ~= "t:" .. id then kept[#kept + 1] = source end
		end
		ns.SetSceneTriggers(key, kept)
	end
	for _, other in ipairs(ns.TriggerLibList()) do
		local text = rows[other .. ".ends"]
		if type(text) == "string" and text:find("trig:" .. id, 1, true) then
			local kept = {}
			for _, each in ipairs(ns.TriggerEnds(other)) do
				if each.ref ~= id then kept[#kept + 1] = each end
			end
			ns.SetTriggerEnds(other, kept)
		end
	end
	for _, field in ipairs(FIELDS) do rows[id .. "." .. field] = nil end
	local list = {}
	for _, each in ipairs(ns.TriggerLibList()) do
		if each ~= id then list[#list + 1] = each end
	end
	rows.lib = #list > 0 and table.concat(list, ",") or nil
	Changed()
end
-- Every trigger of yours gone (the Cameras page's Reset).
function ns.ClearTriggerLib()
	local rows = Rows()
	if not rows then return end
	for _, id in ipairs(ns.TriggerLibList()) do
		for _, field in ipairs(FIELDS) do rows[id .. "." .. field] = nil end
	end
	rows.lib = nil
	for key in pairs(rows) do
		if type(key) == "string" and key:find("^TrigOurs%a+%.") then rows[key] = nil end
	end
	for key in pairs(ns.BUILT_IN_SOURCE_ORDER or EMPTY) do rows["prio." .. key] = nil end
	Changed()
end

-- One with these parts already (for scenes moved over, and shared ones): its id, or nil.
local function Same(src, ends, pri)
	for _, id in ipairs(ns.TriggerLibList()) do
		if ns.TriggerField(id, "src") == src and ns.TriggerField(id, "ends") == ends and ns.TriggerPri(id) == pri
			and not ns.TriggerField(id, "name") and not ns.TriggerField(id, "cond") and not ns.TriggerField(id, "at")
			and not ns.TriggerField(id, "delay") and not ns.TriggerField(id, "hold") and not ns.TriggerField(id, "cd")
			and not ns.TriggerField(id, "chance") then
			return id
		end
	end
end
-- A trigger for a source written the old way (a scene's own "<kind>:<what>",
-- its until and its place after a built-in source): one already in the
-- library with the same parts, or a new one. Its id, or nil (full).
function ns.LibTriggerFor(src, untilText, pri)
	local kind = tostring(src):match("^(%a+):") or "emote"
	local ends
	if untilText == "move" then ends = "never"
	elseif untilText == "ends" or untilText == "key" or (type(untilText) == "string" and untilText:find("^time:%d")) then
		ends = untilText
	end
	if ends == KIND_ENDS[kind] then ends = nil end
	if pri == ns.TRIGGER_DEFAULT_PRI then pri = nil end
	local found = Same(src, ends, pri or ns.TRIGGER_DEFAULT_PRI)
	if found then return found end
	return ns.AddLibTrigger(src, { ends = ends, pri = pri })
end

-- Scenes written before the library: each trigger in a scene's list as its
-- own "<kind>:<what>" moved into the library (one per source, until and
-- priority), the list then naming it ("t:<id>"); a scene of yours' until
-- and after go with it. Done as the scenes are synced, once per change.
local BASE = { [""] = 0, depart = 100, logout = 200, afk = 300, byFire = 400, emote = 500, weapon = 600,
	campfire = 700, still = 800 }
local SCENE_SOURCE = { Hearth = "depart", Teleport = "depart", Logout = "logout", AFK = "afk", Weapon = "weapon",
	Campfire = "campfire", Still = "still" }
function ns.MigrateSceneTriggers()
	local rows = Rows()
	if not rows or not ns.SceneTriggers then return end
	local keys = {}
	for id in tostring(rows.custom or ""):gmatch("[^,]+") do keys[#keys + 1] = { id, true } end
	for key in tostring(rows.extras or ""):gmatch("[^,]+") do keys[#keys + 1] = { key, false } end
	for _, each in ipairs(keys) do
		local key, custom = each[1], each[2]
		local list, moved = ns.SceneTriggers(key), false
		for _, source in ipairs(list) do
			if not source:find("^t:") then moved = true end
		end
		if moved then
			local untilText = custom and (rows[key .. ".until"] or "move") or nil
			local pri
			if custom then
				local after = rows[key .. ".after"]
				pri = (BASE[after == nil and "emote" or after] or BASE.emote) + 10
			else
				pri = (BASE[SCENE_SOURCE[key] or "emote"] or BASE.emote) + 5
			end
			local out = {}
			for _, source in ipairs(list) do
				if source:find("^t:") then
					out[#out + 1] = source
				else
					local id = ns.LibTriggerFor(source, untilText, pri)
					if id then out[#out + 1] = "t:" .. id end
				end
			end
			ns.SetSceneTriggers(key, out)
			if custom then
				rows[key .. ".until"], rows[key .. ".after"] = nil, nil
			end
		end
	end
end

-- Our own triggers, for the page: { key, name (short), starts (what starts
-- it, in words), icon, group, kind, source (the priority source it's under,
-- or nil: a camera that takes turns by its own rules) }. Each is its
-- built-in scene's (CameraRows.lua).
local I = "Interface\\Icons\\"
local BUILT_IN = {
	{ "Hearth", "Hearthstone", "You cast your Hearthstone", "INV_Misc_Rune_01", "Departures", "spell", "depart" },
	{ "Teleport", "Teleport", "You cast a teleport or portal", "Spell_Arcane_TeleportStormWind", "Departures", "spell",
		"depart" },
	{ "Logout", "Log out", "The 20-second logout countdown", "INV_Misc_PocketWatch_01", "Departures", "moment",
		"logout" },
	{ "AFK", "Go AFK", "You're flagged AFK", "Spell_Nature_Sleep", "Resting", "state", "afk" },
	{ "Campfire", "Campfire", "Resting with a campfire buff", "Spell_Fire_Fire", "Resting", "aura", "campfire" },
	{ "Sit", "/sit", "You sit (or press the sit key)", "Spell_Holy_PrayerOfFortitude", "Resting", "emote", "emote" },
	{ "SitButton", "Campfire button", "You press Cinematic's campfire button", "Spell_Fire_Fire", "Resting", "key",
		"emote" },
	{ "Sleep", "/sleep", "You /sleep or /lie down", "Spell_Nature_Sleep", "Resting", "emote", "emote" },
	{ "Chair", "Chair", "You sit in a chair or on a bench", "INV_Misc_Bag_07", "Resting", "state", "emote" },
	{ "Still", "Stand still", "You stand still a while", "Spell_Holy_MindVision", "Resting", "state", "still" },
	{ "Dance", "/dance", "You /dance", "Spell_Holy_PrayerOfFortitude", "Emotes", "emote", "emote" },
	{ "Kneel", "/kneel", "You /kneel", "Spell_Holy_PrayerOfHealing", "Emotes", "emote", "emote" },
	{ "Stare", "/stare", "You /stare", "INV_Misc_Spyglass_02", "Emotes", "emote", "emote" },
	{ "Weapon", "Draw your weapon", "You unsheathe (sheathe key)", "INV_Sword_04", "Emotes", "state", "weapon" },
	{ "Fishing", "Fishing", "You cast Fishing", "Trade_Fishing", "Life", "spell", "emote" },
	{ "Death", "Die", "You die", "Ability_Rogue_FeignDeath", "Life", "moment" },
	{ "Flight", "Flight path", "You take a flight", "Ability_Mount_Wyvern_01", "Travel", "state" },
	{ "Walk", "RP walk", "You walk (walk mode on)", "Ability_Rogue_Sprint", "Travel", "state" },
	{ "Run", "Auto-run", "You auto-run", "Ability_Rogue_Sprint", "Travel", "state" },
	{ "Quest", "Quest giver", "You talk to a quest giver", "INV_Misc_Note_01", "Talk", "interact" },
	{ "QuestGossip", "Quest talk", "You talk about a quest", "INV_Scroll_02", "Talk", "interact" },
	{ "Chat", "Talked to", "Someone talks to you", "INV_Scroll_03", "Talk", "chat" },
	{ "ChatNearby", "Talk nearby", "Someone talks nearby", "Ability_Warrior_BattleShout", "Talk", "chat" },
}
function ns.BuiltInTriggers()
	local list = {}
	for _, each in ipairs(BUILT_IN) do
		local key = each[1]
		if ns.CAMERA_TRIGGER and ns.CAMERA_TRIGGER[key] and not ns.TriggerDeleted(key) then
			list[#list + 1] = { key = key, name = L[each[2]], starts = L[each[3]], icon = I .. each[4], group = each[5],
				kind = each[6], source = each[7] }
		end
	end
	return list
end

-- Our triggers as library entries ("TrigOurs<key>": no id of yours is that
-- long). What starts and ends them is still their cameras' code; their Only
-- if, wait, cooldown, chance and priority are yours to set (saved as yours
-- are, under that id; Reset clears them). A scene can use one ("t:<id>")
-- if it's one of the standing-still ones (it has a priority source).
local OURS_PREFIX = "TrigOurs"
ns.OURS_TRIGGER_FIELDS = { "cond", "delay", "cd", "chance", "pri" }
function ns.OursTriggerId(key) return OURS_PREFIX .. key end
function ns.OursKeyOf(id) return type(id) == "string" and id:match("^" .. OURS_PREFIX .. "(%a+)$") or nil end
-- One of ours by key or id: its BuiltInTriggers entry, or nil.
function ns.OursTrigger(keyOrId)
	local key = ns.OursKeyOf(keyOrId) or keyOrId
	for _, each in ipairs(ns.BuiltInTriggers()) do
		if each.key == key then return each end
	end
end
-- Its priority: yours for it, else its source's (moved or as we ship it);
-- nil for one whose camera takes turns by its own rules.
function ns.OursPri(key)
	local own = tonumber(ns.TriggerField(OURS_PREFIX .. key, "pri"))
	if own then return own end
	local each = ns.OursTrigger(key)
	return each and each.source and ns.BuiltInSourceOrder(each.source) or nil
end
-- Whether you've changed anything of it (Reset shows).
function ns.OursChanged(key)
	for _, field in ipairs(ns.OURS_TRIGGER_FIELDS) do
		if ns.TriggerField(OURS_PREFIX .. key, field) ~= nil then return true end
	end
	return false
end
function ns.ResetOursTrigger(key)
	local rows = ns.GetDB().cameraRows
	for _, field in ipairs(ns.OURS_TRIGGER_FIELDS) do rows[OURS_PREFIX .. key .. "." .. field] = nil end
	Changed()
end
-- Every one of ours back as we ship them (their fields and their sources' places).
function ns.ResetAllOurs()
	local rows = ns.GetDB().cameraRows
	for _, each in ipairs(BUILT_IN) do
		for _, field in ipairs(ns.OURS_TRIGGER_FIELDS) do rows[OURS_PREFIX .. each[1] .. "." .. field] = nil end
	end
	for key in pairs(ns.BUILT_IN_SOURCE_ORDER or EMPTY) do rows["prio." .. key] = nil end
	if ns.ApplyBuiltInOrders then ns.ApplyBuiltInOrders() end
	Changed()
end

-- The built-in priority sources' names (Triggers.lua's), for the Priority tab.
ns.BUILT_IN_SOURCE_NAMES = { depart = "Hearthstones and teleports", logout = "Logging out", afk = "Going AFK",
	byFire = "Sitting by a campfire", emote = "Emotes and seats (sit, dance, chair, Fishing...)",
	weapon = "A drawn weapon", campfire = "A campfire buff", still = "Standing still" }

-- A scene's name as the Scenes page has it: a group's, yours, or our trigger's.
function ns.SceneDisplayName(key)
	local trigger = ns.CAMERA_TRIGGER and ns.CAMERA_TRIGGER[key]
	if trigger and trigger.custom then return ns.CustomTriggerLabel(key) end
	local lead = ns.SceneLead and ns.SceneLead(key) or key
	local group = ns.SceneGroupOf and ns.SceneGroupOf(lead)
	if group then return group.name end
	for _, each in ipairs(ns.BuiltInTriggers()) do
		if each.key == lead then return each.name end
	end
	return tostring(key)
end

-- The log: what fired, what was skipped and why, what lost to another, what
-- ended. Newest last; at most LOG_MAX. version: counts the entries added.
local LOG_MAX = 60
ns.triggerLog = { version = 0 }
function ns.TriggerLogAdd(what, name, why)
	local log = ns.triggerLog
	log[#log + 1] = { clock = date and date("%H:%M:%S") or "", what = what, name = tostring(name or "?"),
		why = tostring(why or "") }
	if #log > LOG_MAX then table.remove(log, 1) end
	log.version = log.version + 1
end
function ns.ClearTriggerLog()
	local log = ns.triggerLog
	for i = #log, 1, -1 do log[i] = nil end
	log.version = log.version + 1
end
