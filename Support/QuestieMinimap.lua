-- Cinematic: Questie's minimap icons for the Minimap page's Reveal ("Use
-- Questie DB"). The game's own "!" for quests on offer can't be read on WoW
-- Forever (NodeSweep.lua: its pretend mouse is only heard where the real
-- mouse is, and no function lists them), but Questie draws its own icons on
-- the minimap from its quest database, as frames: each one's kind
-- ("available" for a quest on offer, "complete" for a turn-in) and where it
-- is can be read. Nothing of Questie's is copied: this only reads the icons it
-- already put up, following its own settings (an icon it hides by them, such
-- as a quest under its level filter, doesn't count).
--
-- What brings the minimap up, every second:
-- - a "!" within the minimap's view radius of you (C_Minimap.GetViewRadius,
--   in yards), or a "?" with Quest turn-ins ticked;
-- - a point of a walking quest giver's route (Questie keeps the routes of
--   NPCs that move; their "!" sits at the route's start);
-- - a friendly NPC's nameplate with the name of a quest giver that has a "!"
--   up (that giver is right there, wherever they've walked to).
--
-- Questie isn't ours and can change any time: every read is guarded, an
-- error only counts against it (after a few in a row it's off for the login,
-- /cine debug questie says why), and unknown shapes count as nothing.
-- What's read (Questie 12.6.3, read 2026-11-07):
-- - LibStub("HereBeDragonsQuestie-Pins-2.0").minimapPins: icon frame ->
--   { x, y (world yards), instanceID }; its HereBeDragonsQuestie-2.0
--   :GetPlayerWorldPosition() gives yours in the same units.
-- - icon.data.Type / .Name (the giver) / .QuestData.name / .waypointPaths
--   ({ instanceId, world = { {x, y}, ... } } per route); icon.hidden is true
--   while Questie's settings hide it (its FakeHide).
-- - Fallback for the icons: QuestieLoader._modules.QuestieMap.questIdFrames
--   (quest -> frame names), placed from icon.x, icon.y (percent) on icon.UiMapID.
local _, ns = ...

local LOOK_EVERY = 1   -- seconds between two looks
local HOLD = 3         -- seconds the minimap stays up after the last look that found one
local MAX_ERRORS = 5   -- looks in a row failing before it's off for this login
local NAMEPLATES = 40

local look = {
	at = -math.huge, seenAt = -math.huge, names = nil,
	why = "hasn't looked yet", errors = 0, broken = nil, lastError = nil, joined = nil,
}

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

local function Plain(value, kind)
	if value == nil or Secret(value) or type(value) ~= kind then return nil end
	return value
end

-- Whether Questie is loaded at all (the Use Questie DB box greys out without it).
local function AskLoaded()
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded("Questie") end
	return IsAddOnLoaded and IsAddOnLoaded("Questie")
end
function ns.QuestieLoaded()
	local ok, loaded = pcall(AskLoaded) -- (no closure a call: this is asked every few frames)
	return ok and loaded == true or (ok and loaded == 1) or false
end

-- Whether the box could ever be used here: Questie is made for the classic
-- clients only (WoW Forever, Classic Era...), never retail.
function ns.QuestieMinimapPossible()
	return not ns.isRetail
end

function ns.QuestieMinimapOn()
	local db = ns.db
	return db ~= nil and db.handleMinimap ~= false and db.minimapQuestie == true and not look.broken
		and ns.QuestieLoaded()
end

local function Libs()
	local libStub = _G.LibStub
	if not libStub then return nil end
	local pins = libStub("HereBeDragonsQuestie-Pins-2.0", true)
	local hbd = libStub("HereBeDragonsQuestie-2.0", true)
	return pins, hbd
end

-- Calls each(frame, spot) for every Questie minimap icon frame, spot being
-- HereBeDragons' world spot when it has one (nil: FrameSpot). Makes no tables
-- (this runs every second over hundreds of icons). Returns the count and the
-- source, or nil and why there's none.
local function ForEachIcon(each)
	local count = 0
	local pins = Libs()
	local registered = pins and Plain(pins.minimapPins, "table")
	if registered then
		for frame, spot in pairs(registered) do
			if type(frame) == "table" then
				count = count + 1
				each(frame, type(spot) == "table" and spot or nil)
			end
		end
		return count, "pins"
	end
	-- (Fallback: Questie's own list of its icons by quest, as frame names.)
	local loader = Plain(_G.QuestieLoader, "table")
	local modules = loader and Plain(loader._modules, "table")
	local map = modules and Plain(modules.QuestieMap, "table")
	local byQuest = map and Plain(map.questIdFrames, "table")
	if not byQuest then return nil, "no Questie icon list found" end
	for _, names in pairs(byQuest) do
		if type(names) == "table" then
			for name in pairs(names) do
				local frame = type(name) == "string" and _G[name]
				if type(frame) == "table" and frame.miniMapIcon == true then
					count = count + 1
					each(frame, nil)
				end
			end
		end
	end
	return count, "frames"
end

-- Every icon as a list of { frame, spot }, for /cine debug questie only.
local function Icons()
	local list = {}
	local count, source = ForEachIcon(function(frame, spot) list[#list + 1] = { frame = frame, spot = spot } end)
	if not count then return nil, source end
	return list, source
end

-- A frame icon's world spot from its zone percent, for the fallback list.
local spots = setmetatable({}, { __mode = "k" })
local function FrameSpot(frame)
	local x, y, mapID = Plain(frame.x, "number"), Plain(frame.y, "number"), Plain(frame.UiMapID, "number")
	if not (x and y and mapID and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
	local cached = spots[frame]
	if cached and cached.x0 == x and cached.y0 == y and cached.map == mapID then return cached end
	local instance, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x / 100, y / 100))
	if not (pos and Plain(pos.x, "number")) then return nil end
	-- (C_Map's world x and y are UnitPosition's, the other way round from HereBeDragons'.)
	cached = { x0 = x, y0 = y, map = mapID, x = pos.y, y = pos.x, instanceID = instance }
	spots[frame] = cached
	return cached
end

local function Within(spot, px, py, instance, reach)
	local x, y = Plain(spot.x, "number"), Plain(spot.y, "number")
	if not (x and y) then return false end
	local id = spot.instanceID or spot.instanceId
	if id ~= nil and instance ~= nil and id ~= instance then return false end
	return (x - px) ^ 2 + (y - py) ^ 2 <= reach * reach
end

-- A route's box: { minX, maxX, minY, maxY } of its points, made once per
-- route (Questie's tables, weak keys: gone with them). Every point was gone
-- over for every giver out of reach, every look: 1.2 ms looks, /cine debug
-- framepass 2026-11-11. Now a route whose box is out of reach is skipped.
local routeBoxes = setmetatable({}, { __mode = "k" })
local function RouteBox(world)
	local box = routeBoxes[world]
	if box == nil then
		local minX, maxX, minY, maxY
		for _, point in ipairs(world) do
			local x = type(point) == "table" and Plain(point.x, "number")
			local y = type(point) == "table" and Plain(point.y, "number")
			if x and y then
				minX, maxX = math.min(minX or x, x), math.max(maxX or x, x)
				minY, maxY = math.min(minY or y, y), math.max(maxY or y, y)
			end
		end
		box = minX and { minX, maxX, minY, maxY } or false
		routeBoxes[world] = box
	end
	return box
end

-- A walking giver's route: any point of it in reach.
local function RouteWithin(data, px, py, instance, reach)
	local paths = Plain(data.waypointPaths, "table")
	if not paths then return false end
	for _, path in ipairs(paths) do
		local world = type(path) == "table" and Plain(path.world, "table")
		local box = world and RouteBox(world)
		if box and (path.instanceId == nil or path.instanceId == instance)
			and px >= box[1] - reach and px <= box[2] + reach and py >= box[3] - reach and py <= box[4] + reach then
			for _, point in ipairs(world) do
				if type(point) == "table" and Within(point, px, py, nil, reach) then return true end
			end
		end
	end
	return false
end

local function Label(data)
	local quest = Plain(data.QuestData, "table")
	local title = quest and Plain(quest.name, "string")
	local giver = Plain(data.Name, "string")
	if title and giver then return ("%s (%s)"):format(title, giver) end
	return title or giver or "a quest"
end

-- What one look works with, kept from look to look (no tables made per look):
-- found = icon data -> true (labels made only for these few), givers = giver
-- name -> that giver's icon data.
local found, givers, names = {}, {}, {}
local counts = { available = 0, complete = 0, hidden = 0, route = 0, plate = 0 }
local lookX, lookY, lookInstance, lookRadius, lookTurnIns
local lookIcons, lookSource -- (the last look's icon count and source, for its report)
local PLATE_UNITS = {}
for i = 1, NAMEPLATES do PLATE_UNITS[i] = "nameplate" .. i end

local function Consider(frame, spot)
	local data = Plain(frame.data, "table")
	local kind = data and Plain(data.Type, "string")
	if kind ~= "available" and kind ~= "complete" then return end
	if frame.hidden == true then
		counts.hidden = counts.hidden + 1
		return
	end
	spot = spot or FrameSpot(frame)
	local wanted = kind == "available" or lookTurnIns
	if wanted and spot and Within(spot, lookX, lookY, lookInstance, lookRadius) then
		counts[kind] = counts[kind] + 1
		found[data] = true
	elseif kind == "available" and RouteWithin(data, lookX, lookY, lookInstance, lookRadius) then
		counts.route = counts.route + 1
		found[data] = true
	end
	-- (Any map's: Questie puts the "!" of a giver inside a place it counts
	-- as a dungeon, such as the Deeprun Tram, at its entrances outside,
	-- on another map than where they stand. A nameplate is near you.)
	local giver = kind == "available" and Plain(data.Name, "string")
	if giver and not givers[giver] then givers[giver] = data end
end

-- One look: the names that reveal the minimap now (nil if none; a list kept
-- for the next look, so read it straight away), and a report.
local function Look()
	local db = ns.db
	local _, hbd = Libs()
	local px, py, instance
	if hbd and hbd.GetPlayerWorldPosition then px, py, instance = hbd:GetPlayerWorldPosition() end
	if not (Plain(px, "number") and Plain(py, "number")) then
		-- (No HereBeDragons: C_Map's, turned the same way as FrameSpot's.)
		local y, x, _, id = UnitPosition("player")
		px, py, instance = Plain(x, "number"), Plain(y, "number"), id
	end
	if not (px and py) then return nil, "no position for you here (in an instance?)" end
	local ok, radius = pcall(C_Minimap.GetViewRadius)
	if not (ok and Plain(radius, "number")) then return nil, "no minimap view radius" end
	wipe(found)
	wipe(givers)
	for kind in pairs(counts) do counts[kind] = 0 end
	lookX, lookY, lookInstance, lookRadius = px, py, instance, radius
	lookTurnIns = db.minimapRevealTurnIns == true
	local iconCount, source = ForEachIcon(Consider)
	lookIcons, lookSource = iconCount, source
	if not iconCount then return nil, source end
	-- (A giver with a "!" up, near you by their nameplate: wherever they walked to.)
	if next(givers) then
		for i = 1, NAMEPLATES do
			local unit = PLATE_UNITS[i]
			if UnitExists(unit) and not ns.Flag(UnitIsPlayer(unit)) then
				local name = Plain(UnitName(unit), "string")
				if name and givers[name] then
					counts.plate = counts.plate + 1
					found[givers[name]] = true
				end
			end
		end
	end
	wipe(names)
	local seen = givers -- (reused: giver lists are done with; labels can repeat across icons)
	wipe(seen)
	for data in pairs(found) do
		local label = Label(data)
		if not seen[label] then
			seen[label] = true
			names[#names + 1] = label
		end
	end
	if #names == 0 then return nil end
	table.sort(names)
	return names
end

-- The report line for the last look that got as far as the icons (made only
-- when asked: otherwise a string a second).
local function LookReport()
	return ("%s icons (%s), view radius %.0f yd: %d on offer, %d turn-ins, %d by route, %d by nameplate, %d hidden by Questie"):format(
		tostring(lookIcons), tostring(lookSource), lookRadius or 0, counts.available, counts.complete, counts.route,
		counts.plate, counts.hidden)
end

-- For NodeSweep.lua's ns.IsMinimapRevealed: whether Questie's icons hold the
-- minimap up now, and what (names joined), looking every LOOK_EVERY seconds.
-- (Standing still, the look is done again only every STILL_EVERY seconds:
-- going over every one of Questie's icons cost about 1 ms a look, /cine
-- debug framepass 2026-11-11, and CineMode is mostly up while you stand.
-- Still: within STILL_YARDS of the last look's spot, same instance. The
-- longer wait still catches a quest taken or a giver walking up.)
local STILL_EVERY, STILL_YARDS = 5, 2
local function StandingStill(now)
	local y, x, _, instance = UnitPosition("player")
	x, y = Plain(x, "number"), Plain(y, "number")
	local still = x and y and look.stillX and instance == look.stillInstance
		and (x - look.stillX) ^ 2 + (y - look.stillY) ^ 2 <= STILL_YARDS * STILL_YARDS
		and now - look.at < STILL_EVERY
	if not still then
		look.stillX, look.stillY, look.stillInstance = x, y, instance
	end
	return still
end

function ns.QuestieMinimapRevealed(now)
	if not ns.QuestieMinimapOn() then return false end
	if now - look.at >= LOOK_EVERY and not StandingStill(now) then
		look.at = now
		local ok, names, why = pcall(Look)
		if ok then
			look.errors = 0
			look.why = why -- (nil: it looked at the icons; LookReport tells what it saw)
			if names then
				look.seenAt = now
				-- (A new string only when what's in view changed.)
				local joined = look.joined
				local same = joined ~= nil and #joined == #names
				if same then
					for i = 1, #names do
						if joined[i] ~= names[i] then same = false break end
					end
				end
				if not same then
					look.joined = { unpack(names) }
					look.names = table.concat(names, ", ")
				end
			end
		else
			look.errors = look.errors + 1
			look.lastError = tostring(names)
			look.why = "failed: " .. look.lastError
			if look.errors >= MAX_ERRORS then
				look.broken = look.lastError
				ns.Log("questie", "Questie's minimap icons can't be read (a Questie update?), off this login: " .. look.lastError)
			end
		end
	end
	if now - look.seenAt < HOLD then return true, look.names end
	return false
end

-- For the Names grid's Service NPCs row's Quest givers kind with Use Questie
-- DB ticked (PlateGuild): the names of the NPCs Questie shows a "!" or "?"
-- for, on any map, its own settings deciding (an icon it hides doesn't
-- count). A set, gathered again every GIVERS_EVERY seconds; nil while Questie
-- can't be read.
local GIVERS_EVERY = 2
local giverSet, giverSetAt, giverErrors, giverSetRead = {}, -math.huge, 0, false
local function AddGiver(frame)
	if frame.hidden == true then return end
	local data = Plain(frame.data, "table")
	local kind = data and Plain(data.Type, "string")
	local name = (kind == "available" or kind == "complete") and Plain(data.Name, "string")
	if name then giverSet[name] = true end
end
function ns.QuestieGiverNames()
	if look.broken or not ns.QuestieLoaded() then return nil end
	local now = GetTime()
	if now - giverSetAt >= GIVERS_EVERY then
		giverSetAt = now
		wipe(giverSet)
		local ok, count, why = pcall(ForEachIcon, AddGiver)
		if not ok then
			giverSetRead = false
			giverErrors = giverErrors + 1
			look.lastError = tostring(count)
			if giverErrors >= MAX_ERRORS then
				look.broken = look.lastError
				ns.Log("questie", "Questie's icons can't be read (a Questie update?), off this login: " .. look.lastError)
			end
			return nil
		end
		giverErrors = 0
		giverSetRead = count ~= nil
		if not count then look.why = why end
	end
	return giverSetRead and giverSet or nil
end

-- For /cine debug questie: what kinds of icon there are, and the nearest
-- quests on offer with their distance, whatever the reach.
local function Survey(lines)
	local _, hbd = Libs()
	local px, py, instance
	if hbd and hbd.GetPlayerWorldPosition then px, py, instance = hbd:GetPlayerWorldPosition() end
	lines[#lines + 1] = ("you: %s, %s, instance %s"):format(tostring(px), tostring(py), tostring(instance))
	local icons, source = Icons()
	if not icons then
		lines[#lines + 1] = "no icons: " .. tostring(source)
		return
	end
	local kinds, near, noData, sample = {}, {}, 0, nil
	for _, entry in ipairs(icons) do
		local frame = entry.frame
		local data = frame.data
		if type(data) ~= "table" then
			noData = noData + 1
		else
			local kind = tostring(data.Type) .. (frame.hidden == true and " (hidden)" or "")
			kinds[kind] = (kinds[kind] or 0) + 1
			local spot = entry.spot or FrameSpot(frame)
			if not sample and spot then
				sample = ("first icon: %s at %s, %s, instance %s; frame x %s y %s map %s"):format(kind,
					tostring(spot.x), tostring(spot.y), tostring(spot.instanceID or spot.instanceId),
					tostring(frame.x), tostring(frame.y), tostring(frame.UiMapID))
			end
			-- (Only where you are: another instance's yards mean nothing here.)
			local id = spot and (spot.instanceID or spot.instanceId)
			if data.Type == "available" and spot and px and Plain(spot.x, "number") and Plain(spot.y, "number")
				and (id == nil or id == instance) then
				near[#near + 1] = { yards = math.sqrt((spot.x - px) ^ 2 + (spot.y - py) ^ 2),
					label = Label(data), instance = spot.instanceID or spot.instanceId, hidden = frame.hidden == true }
			end
		end
	end
	local list = {}
	for kind, count in pairs(kinds) do list[#list + 1] = ("%s %d"):format(kind, count) end
	table.sort(list)
	lines[#lines + 1] = ("kinds: %s; no data %d"):format(#list > 0 and table.concat(list, ", ") or "none", noData)
	if sample then lines[#lines + 1] = sample end
	table.sort(near, function(a, b) return a.yards < b.yards end)
	for i = 1, math.min(5, #near) do
		local n = near[i]
		lines[#lines + 1] = ("  ! %.0f yd: %s (instance %s%s)"):format(n.yards, n.label, tostring(n.instance),
			n.hidden and ", hidden by Questie" or "")
	end
	if #near == 0 then lines[#lines + 1] = ("  no \"!\" icons in instance %s (where you are)"):format(tostring(instance)) end
end

-- /cine debug questie: what the last look saw, and a fresh one.
function ns.QuestieMinimapReport()
	local lines = {}
	local okSurvey, surveyError = pcall(Survey, lines)
	if not okSurvey then lines[#lines + 1] = "survey failed: " .. tostring(surveyError) end
	lines[#lines + 1] = ("Questie loaded %s, Use Questie DB %s, on now %s%s"):format(tostring(ns.QuestieLoaded()),
		tostring(ns.db and ns.db.minimapQuestie), tostring(ns.QuestieMinimapOn()),
		look.broken and (", OFF this login: " .. look.broken) or "")
	local pins, hbd = Libs()
	lines[#lines + 1] = ("HereBeDragonsQuestie pins %s, core %s, QuestieLoader %s"):format(tostring(pins ~= nil),
		tostring(hbd ~= nil), tostring(_G.QuestieLoader ~= nil))
	local ok, names, why = pcall(Look)
	if ok then
		lines[#lines + 1] = "look now: " .. (why or LookReport())
		lines[#lines + 1] = "reveals: " .. (names and table.concat(names, ", ") or "nothing")
	else
		lines[#lines + 1] = "look now failed: " .. tostring(names)
	end
	lines[#lines + 1] = ("last reveal %s"):format(look.seenAt > -math.huge
		and ("%.1fs ago: %s"):format(GetTime() - look.seenAt, tostring(look.names)) or "never")
	return lines
end
