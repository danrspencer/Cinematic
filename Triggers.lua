-- Cinematic: which standing-still trigger wins when several are on at once.
-- Each source names the trigger it has on now (from the state Camera.lua's
-- CurrentEvent works out each time, its side effects done first), and the
-- first in order whose trigger has a camera here picks it. One trigger can
-- come from two sources at different places (a campfire buff while sitting
-- by the fire comes before the emotes; standing by it, after them).
local _, ns = ...

-- The sources in order: { id, order, Key(state) -> trigger key or nil }.
ns.TRIGGER_SOURCES = {}

-- Adds a source (or replaces one with the same id), kept in order; a tie
-- goes after the ones already there.
function ns.RegisterTriggerSource(source)
	local list = ns.TRIGGER_SOURCES
	for i = #list, 1, -1 do
		if list[i].id == source.id then table.remove(list, i) end
	end
	local at = #list + 1
	for i, each in ipairs(list) do
		if each.order > source.order then
			at = i
			break
		end
	end
	table.insert(list, at, source)
end

function ns.UnregisterTriggerSource(id)
	local list = ns.TRIGGER_SOURCES
	for i = #list, 1, -1 do
		if list[i].id == id then table.remove(list, i) end
	end
end

-- The trigger that has a camera (cameraOf(key): its camera here and now,
-- or nil) and comes first, and that camera; nil for none. Each source's
-- place is its order; one of ours (a key a built-in source names) goes by
-- its own priority where you gave it one (TriggerLibrary.lua's OursPri), a
-- tie going to the source listed first. Ours are held back by their Only
-- if, wait, cooldown and chance (Gate) until they win; once one plays, it
-- carries on. (The Triggers page's log: one of ours winning, and a trigger
-- of yours on but under the one that won, once each time.)
local lastPicked
local seenAt = {} -- (ours: key -> when a source last named it)
local episodes = {} -- (ours: key -> { since, rolled, why } while a source keeps naming it)
local lastStart = {} -- (ours: key -> when it last won)
local gateCache = { version = false, list = {} }

-- One of ours' own parts (read again when the library changes).
local function Parts(key)
	local version = ns.triggerLibVersion or 0
	if gateCache.version ~= version then gateCache.version, gateCache.list = version, {} end
	local parts = gateCache.list[key]
	if parts then return parts end
	local id = ns.OursTriggerId and ns.OursTriggerId(key)
	local function Num(field, default, low, high)
		local value = id and tonumber(ns.TriggerField(id, field)) or default
		return math.max(low, math.min(high, value))
	end
	parts = { delay = Num("delay", 0, 0, 600), cd = Num("cd", 0, 0, 86400), chance = Num("chance", 100, 1, 100),
		pri = id and tonumber(ns.TriggerField(id, "pri")) or nil }
	local cond = id and ns.TriggerField(id, "cond")
	if type(cond) == "string" and cond:find("%S") and ns.CompileRule then
		parts.condText = cond
		parts.test = ns.CompileRule(cond)
		parts.bad = parts.test == nil
	end
	parts.gated = parts.delay > 0 or parts.cd > 0 or parts.chance < 100 or parts.condText ~= nil
	gateCache.list[key] = parts
	return parts
end
local function Held(key, episode, why)
	if episode.why ~= why then
		episode.why = why
		if ns.TriggerLogAdd then
			local each = ns.OursTrigger and ns.OursTrigger(key)
			ns.TriggerLogAdd("skipped", each and each.name or key, why)
		end
	end
	return false
end
-- Whether one of ours may start now (always, while it's the one playing).
local function Gate(key, parts, now)
	if key == lastPicked or not parts.gated then return true end
	local episode = episodes[key]
	local L = ns.L
	if parts.delay > 0 and now - episode.since < parts.delay then return false end
	if parts.cd > 0 and lastStart[key] and now - lastStart[key] < parts.cd then
		return Held(key, episode, (L["Cooldown: %d of %d sec left"]):format(
			math.ceil(parts.cd - (now - lastStart[key])), parts.cd))
	end
	if parts.bad then return Held(key, episode, L["Its Only if rule can't be read: fix it on its page"]) end
	if parts.test and not parts.test(ns.RuleFactsNow()) then
		return Held(key, episode, (L["Only if is false: %s"]):format(parts.condText))
	end
	if parts.chance < 100 then
		if episode.rolled == nil then episode.rolled = math.random(100) <= parts.chance end
		if not episode.rolled then
			return Held(key, episode, (L["Chance: not this time (%d%%)"]):format(parts.chance))
		end
	end
	return true
end
-- Whether a built-in source names one of ours now (whatever its camera, or
-- its gate): a scene using that trigger is on while it does.
function ns.OursOnNow(key)
	local at = seenAt[key]
	return at ~= nil and GetTime() - at < 0.5
end

local named = {}
function ns.PickTrigger(state, cameraOf)
	local now = GetTime()
	local pickedKey, pickedCamera, winner, winnerOrder
	wipe(named)
	local candidates
	for _, source in ipairs(ns.TRIGGER_SOURCES) do
		local key = source.Key(state)
		if key and not source.unit then
			named[key] = true
			seenAt[key] = now
			if not episodes[key] then episodes[key] = { since = now } end
		end
		local camera = key and cameraOf(key)
		if camera then
			local order, ok = source.order, true
			if not source.unit then
				local parts = Parts(key)
				order = parts.pri or order
				ok = Gate(key, parts, now)
			end
			if ok then
				if not pickedKey or order < winnerOrder then
					pickedKey, pickedCamera, winner, winnerOrder = key, camera, source, order
				end
				if source.unit then
					candidates = candidates or {}
					candidates[#candidates + 1] = { source = source, key = key, order = order }
				end
			end
		end
	end
	-- (Episodes of ours no source names any more: over.)
	for key in pairs(episodes) do
		if not named[key] then episodes[key] = nil end
	end
	for _, each in ipairs(candidates or {}) do
		local unit = each.source.unit
		if each.source ~= winner and not unit.lostLogged and each.key ~= pickedKey and ns.TriggerLogAdd then
			unit.lostLogged = true
			ns.TriggerLogAdd("lost", unit.label, (ns.L["%s is higher (%s beats %s)"]):format(
				winner.label or (ns.SceneDisplayName and ns.SceneDisplayName(pickedKey)) or tostring(pickedKey),
				("%.0f"):format(winnerOrder), ("%.0f"):format(each.order)))
		end
	end
	if pickedKey ~= lastPicked then
		lastPicked = pickedKey
		if pickedKey and winner and not winner.unit then
			lastStart[pickedKey] = now
			if ns.TriggerLogAdd then
				ns.TriggerLogAdd("fired", ns.SceneDisplayName and ns.SceneDisplayName(pickedKey) or pickedKey,
					(ns.L["Ours. Camera: %s"]):format(ns.CameraName and ns.CameraName(pickedCamera) or tostring(pickedCamera)))
			end
		end
	end
	return pickedKey, pickedCamera
end

-- The built-in ones. A Hearthstone or teleport cast first (it calls a logout
-- off anyway), then logging out, then going AFK (it comes after whatever you
-- were doing: AFK while sitting is the AFK camera), then the rest, and
-- standing still last. The state's fields: departing ("Hearth", "Teleport"
-- or false), logout, afk, byFire (sitting by a campfire), emote (the emote
-- or seat's event, or nil), weapon, campfire, still.
local BUILT_IN = {
	{ id = "depart", order = 100, Key = function(state) return state.departing or nil end },
	{ id = "logout", order = 200, Key = function(state) return state.logout and "Logout" or nil end },
	{ id = "afk", order = 300, Key = function(state) return state.afk and "AFK" or nil end },
	{ id = "byFire", order = 400, Key = function(state) return state.byFire and "Campfire" or nil end },
	{ id = "emote", order = 500, Key = function(state) return state.emote end },
	{ id = "weapon", order = 600, Key = function(state) return state.weapon and "Weapon" or nil end },
	{ id = "campfire", order = 700, Key = function(state) return state.campfire and "Campfire" or nil end },
	{ id = "still", order = 800, Key = function(state) return state.still and "Still" or nil end },
}
-- (Their places as we ship them; "prio.<id>" in the rows: moved on the
-- Triggers page's Priority tab. ApplyBuiltInOrders puts them in again.)
ns.BUILT_IN_SOURCE_ORDER = {}
for _, source in ipairs(BUILT_IN) do
	ns.BUILT_IN_SOURCE_ORDER[source.id] = source.order
	ns.RegisterTriggerSource(source)
end
function ns.BuiltInSourceOrder(id)
	local rows = ns.db and ns.db.cameraRows
	return tonumber(rows and rows["prio." .. id]) or ns.BUILT_IN_SOURCE_ORDER[id]
end
function ns.ApplyBuiltInOrders()
	for _, source in ipairs(BUILT_IN) do
		local order = ns.BuiltInSourceOrder(source.id)
		if order ~= source.order then
			source.order = order
			ns.RegisterTriggerSource(source) -- (taken out and put back in its new place)
		end
	end
end
function ns.SetBuiltInSourceOrder(id, order)
	if not ns.BUILT_IN_SOURCE_ORDER[id] then return end
	ns.GetDB().cameraRows["prio." .. id] = order ~= ns.BUILT_IN_SOURCE_ORDER[id] and order or nil
	ns.ApplyBuiltInOrders()
end
