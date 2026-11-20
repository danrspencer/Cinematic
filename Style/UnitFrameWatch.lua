-- /cine debug ufwatch: a light watch on the player, target and focus frames
-- for players, for "the unit frames get messed up after some combat, /reload
-- fixes it" (2026-11-18, 2026-11-20), which is hard to make happen on purpose.
-- On until the same command turns it off, at every login too. It changes
-- nothing on screen.
--
-- How: each frame's parts (bars, name, level and its badge, portrait, the
-- theme's plate and bridge) are read once they've settled out of combat, the
-- first time each unit is seen: where each sits from the frame's top left
-- corner, its size, whether it shows and its first anchor. 2 s after a fight
-- (past the restyle a fight's end sets off) the frames are read again, and a
-- frame still on the same unit is compared with that first reading. Anything
-- moved goes in /cine log as "ufwatch:" lines, with the unit, the theme and
-- what happened in the fight; chat says so once per session.
-- (The dev copy's /cine debug ufdrift records much more, every region.)
local _, ns = ...

local FRAMES = { "PlayerFrame", "TargetFrame", "FocusFrame" }
local SLACK = 1.5 -- pixels a part may differ by and still count as in place
local SETTLE = 1 -- seconds after a new unit before its first reading
local AFTER_FIGHT = 2 -- seconds after a fight before the check
local MAX_UNITS = 60 -- first readings kept per session, then started over
local MAX_REPORTS = 3 -- per frame per session: the first are what matter

local clean = {} -- [frameName .. unitKey] = reading
local cleanCount = 0
local reports = {} -- [frameName] = count
local told = false
local fight -- { n, targets, changes = { [what] = count } } while in one
local fights = 0

local function Secret(value) return issecretvalue and issecretvalue(value) or false end
local function Readable(value) return value ~= nil and not Secret(value) end
local function On() return CinematicDB and CinematicDB.unitWatch == true end

local function Say(text) ns.Log("ufwatch", text) end

local function NameOf(object)
	if not object then return "nil" end
	local ok, name = pcall(function() return object.GetDebugName and object:GetDebugName() or object:GetName() end)
	if ok and Readable(name) and name ~= "" then return tostring(name) end
	return "unnamed"
end

-- Which unit a frame shows, as a key that stays the same while it's that unit.
local function UnitKey(frame)
	local unit = frame.unit
	if frame == _G.PlayerFrame then return "player" end
	if type(unit) ~= "string" or not UnitExists(unit) then return nil end
	local ok, guid = pcall(UnitGUID, unit)
	if ok and Readable(guid) then return guid end
	return nil
end

local function UnitWords(frame)
	local unit = frame.unit
	if type(unit) ~= "string" or not UnitExists(unit) then return "no unit" end
	local okName, name = pcall(UnitName, unit)
	local okPower, powerName = pcall(function() return select(2, UnitPowerType(unit)) end)
	local level, kind = UnitLevel(unit), UnitClassification(unit)
	return ("%s lvl %s %s %s power %s"):format(okName and Readable(name) and tostring(name) or "?",
		Readable(level) and tostring(level) or "?", Readable(kind) and tostring(kind) or "?",
		UnitIsPlayer(unit) and "player" or "npc", okPower and Readable(powerName) and tostring(powerName) or "?")
end

-- The parts read, by a name each keeps all session.
local function PartsOf(frame)
	local list = {}
	local function Add(key, region) if region then list[#list + 1] = { key, region } end end
	Add("health", frame.healthbar or frame.HealthBar)
	Add("power", frame.manabar or frame.ManaBar)
	Add("name", frame.name or frame.Name)
	Add("portrait", frame.portrait or frame.Portrait)
	if ns.UnitPartRegions then
		for i, region in ipairs(ns.UnitPartRegions(frame, "Level")) do Add("level" .. i, region) end
		for i, region in ipairs(ns.UnitPartRegions(frame, "LevelBack")) do Add("levelBack" .. i, region) end
	end
	if ns.UnitThemeArt then
		for i, region in ipairs(ns.UnitThemeArt(frame)) do Add("themeArt" .. i, region) end
	end
	return list
end

-- One part: its middle from the frame's top left, its size, shown, first anchor.
-- Any read that's secret or missing is left out (nil), never guessed.
local function ReadPart(region, left, top)
	local part = {}
	pcall(function()
		local x, y = region:GetCenter()
		if Readable(x) and Readable(y) then part.x, part.y = x - left, y - top end
		local wide, tall = region:GetSize()
		if Readable(wide) and Readable(tall) then part.w, part.h = wide, tall end
		local shown = region:IsShown()
		if Readable(shown) then part.shown = shown and true or false end
		local point, to, toPoint, ox, oy = region:GetPoint(1)
		if Readable(point) and Readable(toPoint) and Readable(ox) and Readable(oy) then
			part.anchor = ("%s>%s.%s %.1f,%.1f"):format(point, NameOf(to), toPoint, ox, oy)
		end
	end)
	-- (A text's width is its words': only its height and place count.)
	if region.GetFont then part.w = nil end
	return part
end

function ns.UnitWatchRead(frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not (Readable(left) and Readable(top)) then return nil end
	local reading = {}
	for _, entry in ipairs(PartsOf(frame)) do reading[entry[1]] = ReadPart(entry[2], left, top) end
	return reading
end

local function Near(a, b) return math.abs(a - b) <= SLACK end
local function Spot(part)
	local words = {}
	if part.x then words[#words + 1] = ("at %.1f,%.1f"):format(part.x, part.y) end
	if part.w then words[#words + 1] = ("%.1fx%.1f"):format(part.w, part.h) end
	if part.h and not part.w then words[#words + 1] = ("h %.1f"):format(part.h) end
	if part.shown ~= nil then words[#words + 1] = part.shown and "shown" or "hidden" end
	if part.anchor then words[#words + 1] = part.anchor end
	return #words > 0 and table.concat(words, " ") or "unreadable"
end

-- What's not as it was: a list of "key: now (was ...)" lines.
function ns.UnitWatchDiff(before, now)
	local out, keys = {}, {}
	for key in pairs(before) do keys[#keys + 1] = key end
	for key in pairs(now) do if before[key] == nil then keys[#keys + 1] = key end end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local was, is = before[key], now[key]
		local moved
		if not was or not is then
			moved = true
		else
			if was.x and is.x and not (Near(was.x, is.x) and Near(was.y, is.y)) then moved = true end
			if was.w and is.w and not (Near(was.w, is.w) and Near(was.h, is.h)) then moved = true end
			if was.h and is.h and not Near(was.h, is.h) then moved = true end
			if was.shown ~= nil and is.shown ~= nil and was.shown ~= is.shown then moved = true end
			if was.anchor and is.anchor and was.anchor ~= is.anchor then moved = true end
		end
		if moved then
			out[#out + 1] = ("%s: %s (was %s)"):format(key, is and Spot(is) or "gone", was and Spot(was) or "not there")
		end
	end
	return out
end

-- The first reading of each unit on each frame, once it's settled.
local function Learn(id)
	if not On() or InCombatLockdown() then return end
	local frame = _G[id]
	if not frame then return end
	local key = UnitKey(frame)
	if not key or clean[id .. key] then return end
	local shown = frame:IsShown()
	if not (Readable(shown) and shown) then return end
	local reading = ns.UnitWatchRead(frame)
	if not reading then return end
	if cleanCount >= MAX_UNITS then wipe(clean) cleanCount = 0 end
	clean[id .. key] = reading
	cleanCount = cleanCount + 1
end
local function LearnAll()
	for _, id in ipairs(FRAMES) do Learn(id) end
end

local function Settings()
	local db = ns.db or {}
	return ("theme %s layout %s, unit frames %s shape %s nameBack %s texture %s"):format(tostring(db.styleTheme),
		tostring(ns.ThemeLayout and ns.ThemeLayout()), tostring(ns.StyleOn and ns.StyleOn("ufStyle")),
		tostring(db.ufShape), tostring(db.ufNameBack), tostring(db.ufTexture))
end

local function Check(done)
	if not On() or InCombatLockdown() then return end
	local found = false
	for _, id in ipairs(FRAMES) do
		local frame = _G[id]
		local key = frame and UnitKey(frame)
		local before = key and clean[id .. key]
		local shown = frame and frame:IsShown()
		if before and Readable(shown) and shown and (reports[id] or 0) < MAX_REPORTS then
			local now = ns.UnitWatchRead(frame)
			local lines = now and ns.UnitWatchDiff(before, now) or {}
			if #lines > 0 then
				found = true
				reports[id] = (reports[id] or 0) + 1
				local changes = {}
				for what, count in pairs(done.changes) do changes[#changes + 1] = what .. " " .. count end
				table.sort(changes)
				Say(("%s not as before fight %d: %s; %s; in the fight: %s"):format(id, done.n, UnitWords(frame),
					Settings(), #changes > 0 and table.concat(changes, ", ") or "nothing changed"))
				for _, line in ipairs(lines) do Say("  " .. id .. " " .. line) end
			end
		end
	end
	if found and not told then
		told = true
		ns.Print("unit frame watch: a unit frame changed after that fight. It's saved in /cine log.")
	end
	-- (A unit first seen in the fight: learned now, as it is.)
	LearnAll()
end

local function Count(what)
	if fight then fight.changes[what] = (fight.changes[what] or 0) + 1 end
end

local WATCHED = { target = true, focus = true, player = true }
function ns.UnitWatchOnEvent(event, unit)
	if not On() then return end
	if event == "PLAYER_REGEN_DISABLED" then
		fights = fights + 1
		fight = { n = fights, changes = {} }
	elseif event == "PLAYER_REGEN_ENABLED" then
		local done = fight or { n = fights, changes = {} }
		fight = nil
		C_Timer.After(AFTER_FIGHT, function() Check(done) end)
	elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
		Count(event == "PLAYER_TARGET_CHANGED" and "target changes" or "focus changes")
		C_Timer.After(SETTLE, LearnAll)
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- (Our own passes run up to 2 s after a login or /reload.)
		C_Timer.After(3, LearnAll)
	elseif type(unit) == "string" and WATCHED[unit] then
		Count(event:lower():gsub("^unit_", ""):gsub("_", " ") .. " " .. unit)
	end
end

local watcher = CreateFrame("Frame")
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
	"PLAYER_ENTERING_WORLD", "UNIT_DISPLAYPOWER", "UNIT_CLASSIFICATION_CHANGED", "UNIT_LEVEL",
	"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }
for _, event in ipairs(EVENTS) do pcall(watcher.RegisterEvent, watcher, event) end
watcher:SetScript("OnEvent", function(_, event, unit)
	local ok, err = pcall(ns.UnitWatchOnEvent, event, unit)
	if not ok then Say("failed on " .. tostring(event) .. ": " .. tostring(err)) end
end)

function ns.UnitWatchToggle()
	if not CinematicDB then return end
	if On() then
		CinematicDB.unitWatch = nil
		ns.Print("unit frame watch: off.")
		return
	end
	CinematicDB.unitWatch = true
	wipe(clean)
	cleanCount, told, fight = 0, false, nil
	wipe(reports)
	Say("on: " .. (ns.isRetail and "retail" or "classic") .. " game " .. tostring((select(4, GetBuildInfo())))
		.. "; " .. Settings())
	LearnAll()
	ns.Print("unit frame watch: on, at every login too, until you run /cine debug ufwatch again. "
		.. "Play as usual. When your unit frames look wrong after a fight, type /cine log and send what it shows.")
end

-- (For the offline test: the first readings and reports start over.)
function ns.UnitWatchReset()
	wipe(clean)
	wipe(reports)
	cleanCount, told, fight, fights = 0, false, nil, 0
end
