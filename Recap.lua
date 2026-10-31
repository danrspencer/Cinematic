-- Story Vision's Last time: as you log in, a line under the zone name (and
-- the time of day's title) saying what you did in your last session, such as
-- "Last time: Darkshore · 3 quests done · reached level 24". Tint.lua draws
-- it; this file keeps the counts.
--
-- A session's counts live in CinematicCharDB.session and are written as they
-- change (no polling: a few events), so a crash that skips PLAYER_LOGOUT
-- keeps them. A /reload carries on the same session; a real login makes the
-- one there last session's, and starts a new one.

local _, ns = ...
local L = ns.L
local DEFAULTS = ns.DEFAULTS

DEFAULTS.storyRecap = true -- Story Vision's Last time row

local MAX_AGE = 14 * 24 * 3600 -- seconds: an older last session isn't worth recalling
local SEPARATOR = " · "

-- The zone shown is the one you spent the most time in, not the last one:
-- you often log out in a city or an inn, which says little about what you
-- did. Each zone's time is added up as you leave it (or log out); the zone
-- you're in now goes in as soon as you leave it.
local zoneNow, zoneSince
local started -- (events before the login's RecapLogin are last session's business: left alone)

local function Session()
	local chardb = ns.chardb
	if not chardb then return nil end
	chardb.session = chardb.session or { zones = {} }
	return chardb.session
end

-- The time in the zone you're in, added to its total; then counting again
-- from now (in the zone you're in now, if it changed).
local function CountZone()
	local session = Session()
	if not session then return end
	local now = GetTime()
	if zoneNow and zoneSince then
		session.zones[zoneNow] = (session.zones[zoneNow] or 0) + (now - zoneSince)
	end
	local zone = GetRealZoneText and GetRealZoneText() or ""
	if type(zone) == "string" and zone ~= "" then
		zoneNow, zoneSince = zone, now
		session.lastZone = zone -- (the zone if no time got counted: a crash in the first zone)
	end
	session.saved = time()
end

-- (Each count also adds up the zone's time so far, so a crash loses little of it.)
local function Count(key, by)
	CountZone()
	local session = Session()
	if not session then return end
	session[key] = (session[key] or 0) + (by or 1)
end

-- The line for a finished session, or nil if nothing worth saying happened
-- (a quick look at the auction house) or it was too long ago.
local function RecapLine(session)
	if type(session) ~= "table" or not session.saved or time() - session.saved > MAX_AGE then
		return nil
	end
	local parts = {}
	local quests, bosses = session.quests or 0, session.bosses or 0
	if quests > 0 then
		parts[#parts + 1] = (quests == 1 and L["%d quest done"] or L["%d quests done"]):format(quests)
	end
	if session.level then
		parts[#parts + 1] = L["reached level %d"]:format(session.level)
	end
	if bosses > 0 then
		parts[#parts + 1] = (bosses == 1 and L["%d boss down"] or L["%d bosses down"]):format(bosses)
	end
	if #parts == 0 then
		return nil
	end
	local zone, most = session.lastZone, 0
	for name, seconds in pairs(session.zones or {}) do
		if seconds > most then zone, most = name, seconds end
	end
	if zone then
		table.insert(parts, 1, zone)
	end
	return L["Last time: %s"]:format(table.concat(parts, SEPARATOR))
end

-- Core.lua, at PLAYER_ENTERING_WORLD after a login or /reload. A real login
-- (initial) starts a new session and returns the last one's line, if any.
function ns.RecapLogin(initial)
	local chardb = ns.chardb
	if not chardb then return nil end
	local line
	if initial then
		line = RecapLine(chardb.session)
		chardb.session = nil
	end
	zoneNow, zoneSince, started = nil, nil, true
	CountZone()
	return line
end

-- /cine recaptest: the line as your next login would show it (this
-- session's so far), and what it's made of.
function ns.RecapPreview()
	CountZone()
	local session = Session()
	return RecapLine(session), session
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "ENCOUNTER_END",
		"PLAYER_LOGOUT" }) do
	frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", ns.Profiled("Last time", function(_, event, ...)
	if not started then
		return
	elseif event == "QUEST_TURNED_IN" then
		Count("quests")
	elseif event == "PLAYER_LEVEL_UP" then
		local level = ...
		CountZone()
		local session = Session()
		if session and type(level) == "number" then
			session.level = level
		end
	elseif event == "ENCOUNTER_END" then
		local success = select(5, ...)
		if not (issecretvalue and issecretvalue(success)) and success == 1 then
			Count("bosses")
		end
	else -- (a new zone, or logging out: the time in the last one counted)
		CountZone()
	end
end))
