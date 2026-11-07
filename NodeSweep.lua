-- Cinematic minimap sweep: what's on the minimap, for its Reveal boxes
-- (Minimap page: nearby ore, herbs and treasure, quests, other icons).
local ADDON_NAME, ns = ...

-- The game doesn't tell addons where the tracking dots are, but it answers a
-- pretend mouse on the minimap (Minimap:UpdateMouseoverAtPoint, in screen
-- pixels) with what its tooltip would say there
-- (C_TooltipInfo.GetMinimapMouseover): the names of the dots under it. So a
-- grid of points is tried, and each name heard is sorted (ns.NodeKind). The
-- minimap has to be full size and on the screen for that, faded or not: see
-- ns.KeepMinimapFullSize. (Shrunk, it can be grown for the sweep only and
-- put back in the same call, before the screen is drawn again, but the game
-- adds no new dots to it while it's shrunk: grow is for /cine debug nodes.)

local STEP = 12          -- minimap units between two points of the grid (each sweep sets it: SweepStep)
local RIM_BAND = 24      -- minimap units in from the rim: a quest name heard only there is its rim arrow
local RIM_PROBE_IN = 4   -- minimap units in from the rim: the full sweep's ring of points (Probe)
local hearRadius         -- (set with the dot hearing, further down: OnlyAtRim reads it)
local SWEEP_EVERY = 1.5  -- seconds between two sweeps
local HOLD = 3           -- seconds the answer stays yes after the last sweep that found one

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

-- What a name on the minimap is (ns.NodeKind): "group" (you, someone in
-- your group, or a pet), "turnin" (a quest of yours that's done), "objective" (one of yours
-- that isn't: its area), "line" (one of that area's objectives), "herb", "ore",
-- "treasure", or "other" (quest givers among
-- them: their mark's name is just the NPC's, tested). A herb's dot has the name of
-- the herb it gives, so the client names them (item IDs, Classic's herbs); a
-- vein's or chest's name has a word for vein, deposit or chest in the client's
-- language.
local HERB_ITEMS = {
	2447, 765, 2449, 785, 2450, 3820, 2453, 3355, 3369, 3356, 3357, 3818, 3821, 3358,
	3819, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13464, 13463, 13465, 13466, 13467, 13468,
}
local WORDS = {
	enUS = { ore = { "Vein", "Deposit" }, treasure = { "Chest", "Trunk", "Strongbox" } },
	esES = { ore = { "Filón", "Depósito", "filón" }, treasure = { "Cofre", "cofre", "Baúl", "baúl" } },
	deDE = { ore = { "ader", "vorkommen", "Ader", "Vorkommen" }, treasure = { "truhe", "Truhe", "kiste", "Kiste" } },
	frFR = { ore = { "Filon", "Gisement", "filon" }, treasure = { "Coffre", "coffre", "Malle", "malle" } },
	itIT = { ore = { "Vena", "Deposito", "vena" }, treasure = { "Forziere", "forziere", "Baule", "baule" } },
	ptBR = { ore = { "Veio", "Depósito", "veio" }, treasure = { "Baú", "baú", "Arca", "arca" } },
	ruRU = { ore = { "жила", "Жила", "залежи", "Залежи" }, treasure = { "сундук", "Сундук" } },
	koKR = { ore = { "광맥", "광상" }, treasure = { "상자", "궤짝" } },
	zhCN = { ore = { "矿" }, treasure = { "箱" } },
	zhTW = { ore = { "礦" }, treasure = { "箱" } },
}
WORDS.enGB, WORDS.esMX = WORDS.enUS, WORDS.esES
local words = WORDS[GetLocale and GetLocale()] or WORDS.enUS
local herbNames, herbsMissing = {}, true

-- (Item names come from the server: ones not loaded yet are asked for, and
-- read again on a later call.)
local function LoadHerbNames()
	herbsMissing = false
	for _, id in ipairs(HERB_ITEMS) do
		local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
			or GetItemInfo and GetItemInfo(id)
		if type(name) == "string" and not Secret(name) then
			herbNames[name] = id -- (its item: the mark's icon, NodeIcon)
		else
			herbsMissing = true
			if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		end
	end
end

-- Group members' names and your quests (title -> done), read again once
-- something changed.
local groupNames, questTitles = {}, {}
local listsChanged = true
local function Plain(value)
	return type(value) == "string" and not Secret(value) and value or nil
end

local function ReadQuestLog()
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
		for i = 1, ok and type(count) == "number" and count or 0 do
			local okInfo, info = pcall(C_QuestLog.GetInfo, i)
			if okInfo and type(info) == "table" and not info.isHeader and Plain(info.title) then
				local done = C_QuestLog.IsComplete and info.questID and C_QuestLog.IsComplete(info.questID)
				questTitles[info.title] = done == true
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		for i = 1, GetNumQuestLogEntries() do
			local title, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
			if not isHeader and Plain(title) then questTitles[title] = isComplete == 1 end
		end
	end
end

local function ReadLists()
	listsChanged = false
	wipe(groupNames)
	wipe(questTitles)
	-- (Pets too: a warlock's demon is on the minimap the whole time; and you:
	-- your arrow's tooltip has your name, tested.)
	local raid = IsInRaid and IsInRaid()
	local units = { "player", "pet" }
	for i = 1, GetNumGroupMembers and GetNumGroupMembers() or 0 do
		units[#units + 1] = raid and ("raid" .. i) or ("party" .. i)
		units[#units + 1] = raid and ("raidpet" .. i) or ("partypet" .. i)
	end
	for _, unit in ipairs(units) do
		local name = Plain(UnitName(unit))
		if name then groupNames[name] = true end
	end
	-- (The raid roster too, in case a unit's name comes back secret.)
	if raid and GetRaidRosterInfo then
		for i = 1, GetNumGroupMembers() do
			local ok, name = pcall(GetRaidRosterInfo, i)
			name = ok and Plain(name)
			if name then groupNames[name] = true end
		end
	end
	pcall(ReadQuestLog)
end

local listWatcher = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_ENTERING_WORLD", "UNIT_PET" }) do
	pcall(listWatcher.RegisterEvent, listWatcher, event)
end
listWatcher:SetScript("OnEvent", function() listsChanged = true end)

local function HasWord(name, list)
	for _, word in ipairs(list) do
		if name:find(word, 1, true) then return true end
	end
	return false
end

-- The icon on a node's mark (Mark where it is): a herb's own item; a vein's
-- ore, the ore item whose name shares the most of its words' starts with the
-- vein's (Copper Vein: Copper Ore; Dark Iron Deposit: Dark Iron Ore, not Iron
-- Ore; Kupferader: Kupfererz), in any language; a chest's a chest. The trade's
-- icon when nothing fits.
local ORE_ITEMS = {
	2770, 2771, 2772, 2775, 2776, 3858, 7911, 10620, 11370, -- copper, tin, iron, silver, gold, mithril, truesilver, thorium, dark iron
	3340, 4278, 5833, -- incendicite, lesser bloodstone, indurium
}
local ICONS = {
	herb = "Interface\\Icons\\Trade_Herbalism", ore = "Interface\\Icons\\Trade_Mining",
	treasure = "Interface\\Icons\\INV_Box_01",
}
local function ItemIcon(id)
	local get = C_Item and C_Item.GetItemIconByID or GetItemIcon
	local ok, icon = pcall(get or error, id)
	return ok and (type(icon) == "number" or type(icon) == "string") and not Secret(icon) and icon or nil
end
local function SharedStart(a, b)
	local i = 0
	while i < #a and i < #b and a:byte(i + 1) == b:byte(i + 1) do i = i + 1 end
	return i
end
local function OreIcon(vein)
	local best, bestScore = nil, 0
	for _, id in ipairs(ORE_ITEMS) do
		local ore = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or GetItemInfo and GetItemInfo(id)
		if type(ore) == "string" and not Secret(ore) then
			local score = 0
			for veinWord in vein:lower():gmatch("%S+") do
				local most, whole = 0, false
				for oreWord in ore:lower():gmatch("%S+") do
					local shared = SharedStart(veinWord, oreWord)
					most = math.max(most, shared)
					whole = whole or (shared == #veinWord and shared == #oreWord)
				end
				-- (Not "de", "of"...; a whole short word does: Tin Vein, Tin Ore.)
				if most >= 4 or (whole and most >= 3) then score = score + most end
			end
			if score > bestScore then best, bestScore = id, score end
		elseif C_Item and C_Item.RequestLoadItemDataByID then
			pcall(C_Item.RequestLoadItemDataByID, id)
		end
	end
	return best and ItemIcon(best)
end
local function NodeIcon(name, kind)
	local icon
	if kind == "herb" and type(herbNames[name]) == "number" then icon = ItemIcon(herbNames[name]) end
	if kind == "ore" then icon = OreIcon(name) end
	return icon or ICONS[kind] or ICONS.treasure
end

function ns.NodeKind(name)
	if listsChanged then ReadLists() end
	if herbsMissing then LoadHerbNames() end
	-- (Forever's players have a surname: "Sapo Corto" on the minimap, just
	-- "Sapo" from UnitName.)
	if groupNames[name] or groupNames[name:match("^(%S+) ") or ""] then return "group" end
	-- (Under a quest area's title, its objectives: "- 0/12 Kobold Laborer slain", tested.)
	if name:sub(1, 2) == "- " then return "line" end
	local done = questTitles[name]
	if done ~= nil then return done and "turnin" or "objective" end
	if herbNames[name] then return "herb" end
	if HasWord(name, words.ore) then return "ore" end
	if HasWord(name, words.treasure) then return "treasure" end
	return "other"
end

local function MinimapEntry()
	for _, entry in ipairs(ns.managed or {}) do
		if entry.frame == Minimap then return entry end
	end
end

-- The faded minimap's size and place back (see the top). Returns what puts it
-- back as it was, or nil when it isn't shrunk or moved off the screen.
-- (Kept full size, it's moved off the screen while faded with a quest area on it, Frames.lua
-- ns.ParkFullSize: the sweep hears nothing out there, tested, so it's put
-- back in its place for the sweep too.)
local function Grow()
	local entry = MinimapEntry()
	if not (entry and (entry.shrunk or entry.parkedFullSize)) then return nil end
	local scale, points = Minimap:GetScale(), {}
	for i = 1, Minimap:GetNumPoints() do points[i] = { Minimap:GetPoint(i) } end
	if entry.shrunk then Minimap:SetScale(entry.savedScale or 1) end
	if entry.savedPoints then
		Minimap:ClearAllPoints()
		for _, p in ipairs(entry.savedPoints) do Minimap:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
	end
	return function()
		Minimap:SetScale(scale)
		Minimap:ClearAllPoints()
		for _, p in ipairs(points) do Minimap:SetPoint(unpack(p)) end
	end
end

-- Whether this client lets the minimap be swept at all (retail doesn't,
-- tested: its Reveal boxes that need a sweep are hidden, Options.lua).
local function HasSweepApi()
	return Minimap.UpdateMouseoverAtPoint ~= nil and Minimap.SetUsingSoftCursor ~= nil
		and C_TooltipInfo ~= nil and C_TooltipInfo.GetMinimapMouseover ~= nil
end

-- Whether the game answers the pretend mouse at all (answer.state: nil not
-- known yet, "yes", "no"). WoW Forever's game 70862 has the functions but
-- answers only for where the real mouse is (tested: every point heard what the
-- real mouse was on, and nothing with it off the minimap, whatever the point's
-- units). Asked again each login, at your arrow in the minimap's middle while
-- it's shown (AnswerCheck, further down); a sweep that hears anything is a yes.
local answer = { state = nil, fails = 0 }
local ANSWER_TRIES = 3
-- (Known up front from WoW Forever's game 70862 on, so the Minimap page never
-- offers what can't work, even opened in the first seconds: no tries. If a
-- later patch answers again, /cine debug nodes spaces shows it: then raise
-- this to the build that broke it for good, or drop it.)
local NO_ANSWER_FROM = 70862
do
	local build = GetBuildInfo and tonumber((select(2, GetBuildInfo())))
	if not ns.isRetail and not ns.isClassicEra and build and build >= NO_ANSWER_FROM then
		answer.state = "no"
	end
end

-- One more try that heard nothing; enough of them and it's a no.
function ns.CountNoAnswer()
	answer.fails = answer.fails + 1
	if answer.fails >= ANSWER_TRIES and not answer.state then
		answer.state = "no"
		ns.Log("nodes", "the game doesn't answer the pretend mouse: minimap Reveal is off this login")
	end
end

-- Whether the minimap can be swept here: the functions, and the game answering
-- (retail has no such functions, tested: Reveal boxes that need a sweep are
-- hidden there, Options.lua; nor once the game doesn't answer).
function ns.CanSweepMinimap()
	return HasSweepApi() and answer.state ~= "no"
end

-- The pretend mouse's turn on the minimap (OnMinimap): the faded minimap
-- grown or back on the screen for it (Grow) and the soft cursor on, then
-- both put back. The Reveal sweep runs as a job over several frames
-- (sweepJob, a coroutine: PER_FRAME points a frame, not ~400 at once, a
-- stutter every sweep): between frames the minimap is put back and the
-- cursor off, and the turn ends if a fight starts or your mouse comes onto
-- the minimap meanwhile.
local PER_FRAME = 60
local session -- the turn going on: { grow, putBack, chunk (in the job) }
local framePoints = 0 -- points the job has tried this frame (all its turns)
local sweepJob -- the Reveal sweep's coroutine while it runs

-- Why the pretend mouse can't have the minimap now, or nil.
local function NotReady()
	-- (Not ns.CanSweepMinimap: /cine debug nodes still tries once the game stopped answering.)
	if not HasSweepApi() then return "this client can't move a pretend mouse over the minimap" end
	-- (Not in combat; nor with your own mouse there, whose tooltip it would change.)
	if InCombatLockdown() then return "in combat" end
	-- (/cine debug nodes mouse: tried with your mouse there anyway.)
	if ns.Flag(Minimap:IsMouseOver()) and not ns.sweepWithMouse then return "your mouse is over the minimap" end
	local entry = MinimapEntry()
	if entry and entry.parkedFullSize and ns.IsEntryHovered(entry) then return "your mouse is over the minimap" end
end

local function Enter(turn)
	local entry = MinimapEntry()
	turn.parked = entry and entry.parkedFullSize
	if turn.grow or turn.parked then
		local ok, result = pcall(Grow)
		if not ok then return "couldn't grow the minimap: " .. tostring(result) end
		turn.putBack = result
		turn.grown = turn.grown or (result ~= nil and not turn.parked)
	end
	pcall(Minimap.SetUsingSoftCursor, Minimap, true)
end

local function Leave(turn)
	pcall(Minimap.SetUsingSoftCursor, Minimap, false)
	if turn.putBack then
		local ok, err = pcall(turn.putBack)
		if not ok then ns.Log("nodes", "couldn't put the minimap back: " .. tostring(err)) end
		turn.putBack = nil
	end
end

-- After each point: in the job, once PER_FRAME are done, the rest waits for
-- the next frame. (An error ends the job: it's not a pcall's, which can't
-- wait across frames in Lua 5.1.)
local function Pause()
	local turn = session
	if not (turn and turn.chunk and sweepJob and coroutine.running() == sweepJob) then return end
	framePoints = framePoints + 1
	if framePoints < PER_FRAME then return end
	framePoints = 0
	Leave(turn)
	coroutine.yield()
	local why = NotReady() or Enter(turn)
	if why then error({ stopped = why }) end
end

-- The names the pretend mouse hears at px, py (minimap units from the middle),
-- as the tooltip lines; nil and why if the game refused.
local NO_LINES = {} -- (read only)
local function MouseoverAt(x, y)
	Minimap:UpdateMouseoverAtPoint(x, y)
	return C_TooltipInfo.GetMinimapMouseover()
end
local function Listen(px, py)
	local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
	local scale, width = Minimap:GetEffectiveScale(), Minimap:GetWidth()
	if not (left and bottom and scale and width) or width <= 0 then return nil, "the minimap has no place" end
	local half = width / 2
	if ns.profiling then ns.ProfileCount("minimap points") end
	local ok, data = pcall(MouseoverAt, (left + half + px) * scale, (bottom + half + py) * scale)
	Pause()
	if not ok then return nil, "the game refused: " .. tostring(data) end
	local lines = not Secret(data) and type(data) == "table" and data.lines
	return type(lines) == "table" and not Secret(lines) and lines or NO_LINES
end

-- Whether the game wrote a tooltip line gray: a dot on the other side of
-- indoors and outdoors from you (in a cave while you're out, or the other way
-- round), drawn grayed on the minimap too.
local function GrayLine(text, color)
	if type(color) == "table" and not Secret(color) and type(color.r) == "number"
		and math.abs(color.r - color.g) < 0.05 and math.abs(color.g - color.b) < 0.05 and color.r < 0.8 then
		return true
	end
	return type(text) == "string" and text:find("|cff7f7f7f") ~= nil
end

-- Tries a grid of points over the minimap as it is now. Each name heard goes
-- to found[name] = { points, gray, list } (gray: a dot in a cave; list: the
-- points' offsets from the minimap's centre, x, y pairs); stop(name), when
-- given, ends the sweep at the first name it says yes to. radius, when given:
-- only that far from the middle (minimap units).
-- (cx, cy, when given: the grid's middle instead of the minimap's, its
-- points still only on the minimap.)
local function Probe(step, found, stop, radius, cx, cy)
	local width = Minimap:GetWidth()
	if not width or width <= 0 then return nil, "the minimap has no place" end
	local probes = 0
	local half = width / 2
	local reach = math.min(radius or half, half)
	-- One point: what it hears goes into found. Returns true to stop (stop
	-- said yes), or nil and why the game refused.
	local function Hear(dx, dy)
		probes = probes + 1
		local lines, why = Listen(dx, dy)
		if not lines then return nil, why end
		for _, line in ipairs(lines) do
			local text, color = line.leftText, line.leftColor
			if type(text) == "string" and not Secret(text) then
				local gray = GrayLine(text, color)
				-- (Colour codes and icons out, one name a line.)
				local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
					:gsub("|T.-|t", ""):gsub("|A.-|a", "")
				for name in plain:gmatch("[^\n]+") do
					name = name:match("^%s*(.-)%s*$")
					if name ~= "" then
						local entry = found[name] or { points = 0 }
						entry.points = entry.points + 1
						-- (Each point, offset from the minimap's centre: where its dots are.)
						entry.list = entry.list or {}
						entry.list[#entry.list + 1], entry.list[#entry.list + 2] = dx, dy
						entry.gray = entry.gray or gray
						-- (The line as the game wrote it, and its colour: for /cine debug nodes raw.)
						entry.raw = entry.raw or text
						entry.color = entry.color or (type(color) == "table" and not Secret(color)
							and type(color.r) == "number" and ("%02x%02x%02x"):format(color.r * 255,
							color.g * 255, color.b * 255)) or nil
						found[name] = entry
						if stop and stop(name, entry) then return true end
					end
				end
			end
		end
		return false
	end
	local full = not radius and not cx
	cx, cy = cx or 0, cy or 0
	for gx = -reach, reach, step do
		for gy = -reach, reach, step do
			local dx, dy = cx + gx, cy + gy
			if gx * gx + gy * gy <= reach * reach and dx * dx + dy * dy <= half * half then
				local done, why = Hear(dx, dy)
				if done == nil then return nil, why end
				if done then return found, probes end
			end
		end
	end
	-- (The whole minimap: a ring just inside its rim too. A quest's area that
	-- only just reaches over the rim is a thin sliver the grid can miss, and
	-- its outline still shows on a faded full-size minimap.)
	if full then
		local r = half - RIM_PROBE_IN
		local count = math.max(8, math.ceil(2 * math.pi * r / step))
		for i = 0, count - 1 do
			local angle = 2 * math.pi * i / count
			local done, why = Hear(r * math.cos(angle), r * math.sin(angle))
			if done == nil then return nil, why end
			if done then return found, probes end
		end
	end
	return found, probes
end

-- The minimap made ready for the pretend mouse, fn() run on it, and the
-- minimap put back. Returns fn's two results and whether it was grown, or
-- nil and why not. (grow: a shrunk faded minimap is grown for it; refresh:
-- the game places its dots first, Minimap:UpdateBlips.)
local function OnMinimap(grow, refresh, fn)
	local why = NotReady()
	if why then return nil, why end
	local turn = { grow = grow, chunk = sweepJob ~= nil and coroutine.running() == sweepJob }
	why = Enter(turn)
	if why then return nil, why end
	local before = session
	session = turn
	if refresh and Minimap.UpdateBlips then pcall(Minimap.UpdateBlips, Minimap) end
	local ok, first, second
	if turn.chunk then
		ok, first, second = true, fn() -- (an error here ends the job, which puts the minimap back)
	else
		ok, first, second = pcall(fn)
	end
	Leave(turn)
	session = before
	if not ok then return nil, "the game refused: " .. tostring(first) end
	return first, second, turn.grown == true
end

-- One sweep: found (name -> { points, gray }), points tried, and whether the
-- faded minimap was grown for it (grow); or nil and why not. (refresh: has
-- the game place its dots first, Minimap:UpdateBlips, for /cine debug nodes
-- update; radius: only that far from the middle, as Probe.)
function ns.SweepMinimap(step, grow, stop, refresh, radius, cx, cy)
	return OnMinimap(grow, refresh, function() return Probe(step or STEP, {}, stop, radius, cx, cy) end)
end

-- /cine debug nodes spaces: the grid tried in each way the game might want
-- Minimap:UpdateMouseoverAtPoint's point (game 70862 stopped hearing screen
-- pixels: every point heard what the real mouse was on). Returns a line each.
function ns.NodeSpacesTest()
	local why = NotReady()
	if why then return { "can't: " .. why } end
	local turn = { grow = true }
	why = Enter(turn)
	if why then return { "can't: " .. why } end
	local lines = {}
	local ok, err = pcall(function()
		local w, left, bottom = Minimap:GetWidth(), Minimap:GetLeft(), Minimap:GetBottom()
		local s, half = Minimap:GetEffectiveScale(), Minimap:GetWidth() / 2
		local spaces = {
			{ "screen pixels", function(x, y) return (left + half + x) * s, (bottom + half + y) * s end },
			{ "UI units", function(x, y) return left + half + x, bottom + half + y end },
			{ "from the middle", function(x, y) return x, y end },
			{ "from the middle, y down", function(x, y) return x, -y end },
			{ "from bottom-left", function(x, y) return half + x, half + y end },
			{ "from top-left", function(x, y) return half + x, half - y end },
			{ "0 to 1", function(x, y) return (half + x) / w, (half + y) / w end },
			{ "0 to 1, y down", function(x, y) return (half + x) / w, (half - y) / w end },
			{ "-1 to 1", function(x, y) return x / half, y / half end },
		}
		for _, space in ipairs(spaces) do
			local heard, points = {}, 0
			for x = -half, half, 12 do
				for y = -half, half, 12 do
					if x * x + y * y <= half * half then
						points = points + 1
						local px, py = space[2](x, y)
						local data = select(2, pcall(MouseoverAt, px, py))
						local got = not Secret(data) and type(data) == "table" and data.lines
						if type(got) == "table" and not Secret(got) then
							for _, line in ipairs(got) do
								local text = line.leftText
								if type(text) == "string" and not Secret(text) then
									text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
									for name in text:gmatch("[^\n]+") do heard[name] = (heard[name] or 0) + 1 end
								end
							end
						end
					end
				end
			end
			local names = {}
			for name, count in pairs(heard) do names[#names + 1] = ("%s (%d)"):format(name, count) end
			table.sort(names)
			lines[#lines + 1] = ("%s: %s of %d points"):format(space[1],
				#names > 0 and table.concat(names, ", ") or "nothing", points)
		end
	end)
	Leave(turn)
	if not ok then lines[#lines + 1] = "stopped: " .. tostring(err) end
	-- (Without the soft cursor too, at your arrow in the middle.)
	local left, bottom, half = Minimap:GetLeft(), Minimap:GetBottom(), Minimap:GetWidth() / 2
	local s = Minimap:GetEffectiveScale()
	local data = select(2, pcall(MouseoverAt, (left + half) * s, (bottom + half) * s))
	local got = not Secret(data) and type(data) == "table" and data.lines
	lines[#lines + 1] = ("no soft cursor, middle: %s line(s)"):format(type(got) == "table" and #got or 0)
	-- (What else this build has to ask the minimap with.)
	local found = {}
	for key, value in pairs(getmetatable(Minimap).__index) do
		if type(value) == "function" and (key:find("Mouse") or key:find("Cursor") or key:find("Blip")
			or key:find("Point") or key:find("Tooltip") or key:find("Track") or key:find("Ping")) then
			found[#found + 1] = key
		end
	end
	table.sort(found)
	lines[#lines + 1] = "Minimap functions: " .. table.concat(found, ", ")
	found = {}
	for key in pairs(C_Minimap or {}) do found[#found + 1] = key end
	table.sort(found)
	lines[#lines + 1] = "C_Minimap: " .. (#found > 0 and table.concat(found, ", ") or "none")
	local vignettes = _G.C_VignetteInfo and _G.C_VignetteInfo.GetVignettes and _G.C_VignetteInfo.GetVignettes()
	lines[#lines + 1] = ("vignettes now: %s"):format(type(vignettes) == "table" and #vignettes or "no such function")
	return lines
end

-- Reveal (Minimap page): which kinds of name bring the minimap up. (Group
-- members and a quest area's objective lines count as nothing: the first are
-- on the minimap all the time, the second come with their quest's title.)
local REVEAL = {
	herb = "minimapRevealNodes", ore = "minimapRevealNodes", treasure = "minimapRevealNodes",
	turnin = "minimapRevealTurnIns",
	objective = "minimapRevealAreas", other = "minimapRevealIcons",
}
-- (A quest's area off the minimap has an arrow on its rim pointing to it,
-- named like the quest, there the whole time (Track Quest POIs): a quest name
-- heard only near the rim is that arrow, and counts as nothing. The area
-- counts once it reaches further in.)
local QUEST_KINDS = { objective = true, turnin = true }
local function OnlyAtRim(entry)
	local half = (Minimap:GetWidth() or 0) / 2
	local list = entry and entry.list
	if not list or half <= 0 then return false end
	local inner = (half - RIM_BAND) ^ 2
	for i = 1, #list, 2 do
		if list[i] ^ 2 + list[i + 1] ^ 2 < inner then return false end
	end
	-- (Heard along more of the rim than one arrow can be, every point being
	-- within hearRadius of it: the edge of an area reaching over the rim.)
	local span = (2 * (hearRadius or 15) + 10) ^ 2
	for i = 1, #list, 2 do
		for j = i + 2, #list, 2 do
			if (list[i] - list[j]) ^ 2 + (list[i + 1] - list[j + 1]) ^ 2 > span then return false end
		end
	end
	return true
end

local function Wanted(name, entry)
	local kind = ns.NodeKind(name)
	local option = REVEAL[kind]
	if not (option ~= nil and ns.db[option] == true) then return false end
	return not (QUEST_KINDS[kind] and OnlyAtRim(entry))
end

local function AnyReveal()
	local db = ns.db
	return db and db.handleMinimap ~= false and ns.CanSweepMinimap() and (db.minimapRevealNodes
		or db.minimapRevealTurnIns or db.minimapRevealAreas or db.minimapRevealIcons) or false
end

-- While a reveal is ticked, the faded minimap isn't shrunk and moved off the
-- screen as usual (the game stops adding dots to it then, tested): it stays
-- full size in its place at alpha 0, with its icons shrunk to nothing
-- (Minimap:SetIconScale), which hides its player arrow and dots too. They get
-- their size back as soon as it fades in. (Frames.lua, ns.SetEntryAlpha.)
-- (0.01 still left the arrow as one pixel in the middle: 0, or as near it as
-- the client takes.)
local ICON_TINY = { 0, 0.0001 }
local iconScale, iconsHidden, settingIcons, tinyUsed = 1, false, false, nil
if Minimap.SetIconScale then
	-- (Another addon's own icon scale is what's put back.)
	hooksecurefunc(Minimap, "SetIconScale", function(_, scale)
		if not settingIcons and type(scale) == "number" then iconScale = scale end
	end)
end

-- (In combat the minimap can't be shrunk: the answer from before the fight
-- stands, so its arrow doesn't show meanwhile.)
local keep = false
function ns.KeepMinimapFullSize()
	if not (InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))) then
		keep = ns.minimapStayFullSize -- (/cine debug nodes stay)
			or (Minimap.SetIconScale ~= nil and AnyReveal())
	end
	return keep or false
end

function ns.SetMinimapIconsHidden(hidden)
	if hidden == iconsHidden or not Minimap.SetIconScale then return end
	iconsHidden = hidden
	settingIcons = true
	if hidden then
		tinyUsed = nil
		for _, scale in ipairs(ICON_TINY) do
			if pcall(Minimap.SetIconScale, Minimap, scale) then
				tinyUsed = scale
				break
			end
		end
	else
		pcall(Minimap.SetIconScale, Minimap, iconScale)
	end
	settingIcons = false
end

-- For /cine debug minimap.
function ns.MinimapIconState()
	local methods = {}
	for method in pairs(ns.BLOB_ALPHAS) do methods[#methods + 1] = method:gsub("^Set", ""):gsub("Alpha$", "") end
	table.sort(methods)
	return ("icons hidden %s (scale %s, put back to %s), kept full size %s; quest areas hidden %s (%s)"):format(
		tostring(iconsHidden), tostring(iconsHidden and tinyUsed or iconScale), tostring(iconScale),
		tostring(ns.KeepMinimapFullSize()), tostring(ns.minimapBlobsHidden or false),
		#methods > 0 and table.concat(methods, ", ") or "none on this client")
end

-- The quest, task and dig site areas (the blue shapes) ignore the minimap's
-- alpha as well: their own alphas go to 0 while it's faded full size. The
-- game can't say what they were, and Blizzard's UI never sets them (so 1),
-- unless another addon did: its value is what's put back.
local BLOB_ALPHAS = {}
ns.BLOB_ALPHAS = BLOB_ALPHAS -- (for /cine debug minimap)
for _, kind in ipairs({ "Quest", "Task", "Arch" }) do
	for _, part in ipairs({ "Inside", "Outside", "Ring" }) do
		local method = "Set" .. kind .. "Blob" .. part .. "Alpha"
		if Minimap[method] then BLOB_ALPHAS[method] = 1 end
	end
end
local blobsHidden, settingBlobs = false, false
for method in pairs(BLOB_ALPHAS) do
	hooksecurefunc(Minimap, method, function(_, alpha)
		if settingBlobs or type(alpha) ~= "number" or Secret(alpha) then return end
		BLOB_ALPHAS[method] = alpha
		-- (Set while hidden: back to 0, the value kept for later.)
		if blobsHidden then
			settingBlobs = true
			pcall(Minimap[method], Minimap, 0)
			settingBlobs = false
		end
	end)
end

function ns.SetMinimapBlobsHidden(hidden)
	if hidden == blobsHidden then return end
	blobsHidden = hidden
	ns.minimapBlobsHidden = hidden
	settingBlobs = true
	for method, alpha in pairs(BLOB_ALPHAS) do
		pcall(Minimap[method], Minimap, hidden and 0 or alpha)
	end
	settingBlobs = false
end

-- From the Frames.lua tick: whether something ticked under Reveal is on the
-- minimap. Swept every SWEEP_EVERY seconds while the minimap is faded (or
-- fading), or up for what the last sweep found; between sweeps, and while one
-- can't run (in combat, the mouse on the minimap), the last answer stands.
local sweptAt, seenAt = -math.huge, -math.huge
local revealedBy -- the names that last revealed it, for /cine why (Why.lua)
local last = {} -- the last sweep, for /cine debug tracking
-- Whether the last sweep heard a quest's area on the minimap (not just its
-- arrow on the rim): the faded minimap waits off the screen meanwhile
-- (Frames.lua), since its blue outline shows through alpha 0. Elsewhere it
-- stays in its place: off the screen the game adds no new dots, tested.
local areaShown = false
function ns.MinimapAreaShown()
	return areaShown
end

-- Nearby ore, herbs and treasure's Mark where it is (minimapNodeMark): our
-- ring where a node shows up (MarkNode below), or a minimap ping, the same as
-- clicking the minimap (so your group sees it too). A node is the middle of the points that heard
-- its name next to each other: two dots of the same name are two nodes,
-- unless they touch. One counts as new unless a node of its name was close by
-- in the sweep before, in world yards where the client says where you are (so
-- walking past one doesn't ping it again).
local NODE_KINDS = { herb = true, ore = true, treasure = true }
-- The nodes the last sweep found: { name, x, y (offset from the minimap's
-- centre, its units), n, w (yards north and west in the world, when known) }.
local nodes = {}
local MATCH_YARDS, MATCH_UNITS = 30, 20 -- this close to one found before, of the same name: the same node
-- Nodes pinged lately, the same way (and when): one a sweep missed (its dot at
-- the minimap's edge, or hardly heard) isn't pinged again when it's back.
local pinged, PING_MEMORY = {}, 60 -- seconds

-- Yards per minimap unit and the minimap's turn (radians, 0 unless it
-- rotates), or nil where they can't be read.
local function View()
	local ok, radius = pcall(C_Minimap and C_Minimap.GetViewRadius or error)
	local width = Minimap:GetWidth()
	if not ok or type(radius) ~= "number" or Secret(radius) or radius <= 0 or not width or width <= 0 then return nil end
	local facing = 0
	if GetCVar("rotateMinimap") == "1" then
		facing = GetPlayerFacing and GetPlayerFacing()
		if type(facing) ~= "number" or Secret(facing) then return nil end
	end
	return radius / (width / 2), facing
end

-- Where you are: yards north and west (nil in instances, where it's hidden).
local function Here()
	local n, w = UnitPosition("player")
	if type(n) ~= "number" or Secret(n) or type(w) ~= "number" or Secret(w) then return nil end
	return n, w
end

-- One name's points (x, y pairs) split into nodes: points next to each
-- other on the grid are one dot's; each group's middle is where it is.
local function Groups(points, step)
	local count, group, list = #points / 2, {}, {}
	local reach = (step * 1.5) ^ 2
	for i = 1, count do
		if not group[i] then
			local sx, sy, size, queue, members = 0, 0, 0, { i }, {}
			group[i] = true
			while #queue > 0 do
				local j = table.remove(queue)
				local jx, jy = points[j * 2 - 1], points[j * 2]
				sx, sy, size = sx + jx, sy + jy, size + 1
				members[#members + 1] = j
				for k = 1, count do
					if not group[k] and (points[k * 2 - 1] - jx) ^ 2 + (points[k * 2] - jy) ^ 2 <= reach then
						group[k] = true
						queue[#queue + 1] = k
					end
				end
			end
			-- (Its third: how far its furthest point is from the middle.)
			local mx, my, far = sx / size, sy / size, 0
			for _, j in ipairs(members) do
				far = math.max(far, ((points[j * 2 - 1] - mx) ^ 2 + (points[j * 2] - my) ^ 2) ^ 0.5)
			end
			-- (Its fourth: the points' numbers.)
			list[#list + 1] = { mx, my, far, members }
		end
	end
	return list
end

-- Where the dots of one name really are, near x, y (minimap units from the
-- middle). The pretend mouse hears a dot over a disc some 15 units around it
-- (twice the real mouse's), so the middle of what heard it is only right
-- for a dot on its own, whole; two veins side by side are one patch whose
-- middle is the gap between them (marks sat there, tested). So, on a grid
-- LOOK apart:
-- - a patch one dot's size: its four edges are found (halving the step each
--   time), and the dot is halfway between each pair, to about a unit;
-- - a bigger patch: discs of the dot's size are fitted to its outline, each
--   where the most of the outline lies one radius off, as few as explain
--   it; two dots leave two arcs, however close.
-- The disc's radius is learned from the dots found whole (hearRadius).
-- Returns { { x, y }, ... }, or nil and why.
local LOOK = 3 -- minimap units between points
hearRadius = 15 -- minimap units a dot is heard around it (11 to 24; declared at the top)
local EDGE_STEPS = 5 -- halvings when finding an edge (to under a unit)
local ARC = 2 -- minimap units an outline point may be off a fitted disc
local MIN_ARC = 6 -- outline points a fitted disc has to explain
local ENOUGH = 0.85 -- of the best fit's explained outline: the fewest discs that reach it win
local MOST_DOTS = 6
local lastLocate -- (for /cine debug tracking)

local function Locate(name, x, y, reach)
	return OnMinimap(true, true, function()
		local width = Minimap:GetWidth()
		if not width or width <= 0 then return nil, "the minimap has no place" end
		local rim = (width / 2 - 1) ^ 2
		local probes = 0
		-- (Whether the pretend mouse hears the name at px, py; nil off the minimap.
		-- Second: whether the game wrote it gray, GrayLine.)
		local function Hears(px, py)
			if px * px + py * py > rim then return nil end
			probes = probes + 1
			local lines = Listen(px, py)
			if not lines then error("the game refused the pretend mouse") end
			for _, line in ipairs(lines) do
				local text = line.leftText
				if type(text) == "string" and not Secret(text) then
					local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
					for each in plain:gmatch("[^\n]+") do
						if each:match("^%s*(.-)%s*$") == name then return true, GrayLine(text, line.leftColor) end
					end
				end
			end
			return false
		end
		local spots = (function()
			-- The grid: cells i, j (LOOK apart round x, y) heard (true), not (false),
			-- or off the minimap (nil).
			local cells, grays, n = {}, {}, math.ceil(reach / LOOK)
			local function Key(i, j) return (i + 500) * 1000 + j + 500 end
			for i = -n, n do
				for j = -n, n do
					if i * i + j * j <= n * n then
						local key = Key(i, j)
						cells[key], grays[key] = Hears(x + i * LOOK, y + j * LOOK)
					end
				end
			end
			-- Patches: heard cells touching (sides or corners).
			local seen, patches = {}, {}
			for key, heard in pairs(cells) do
				if heard and not seen[key] then
					seen[key] = true
					local stack, patch = { key }, {}
					while #stack > 0 do
						local k = table.remove(stack)
						patch[#patch + 1] = k
						for _, d in ipairs({ -1001, -1000, -999, -1, 1, 999, 1000, 1001 }) do
							if cells[k + d] and not seen[k + d] then
								seen[k + d] = true
								stack[#stack + 1] = k + d
							end
						end
					end
					patches[#patches + 1] = patch
				end
			end
			local function Place(k) return x + (math.floor(k / 1000) - 500) * LOOK, y + (k % 1000 - 500) * LOOK end
			local found = {}
			for _, patch in ipairs(patches) do
				local first = #found + 1
				local area = #patch * LOOK * LOOK
				local sx, sy = 0, 0
				for _, k in ipairs(patch) do
					local px, py = Place(k)
					sx, sy = sx + px, sy + py
				end
				local mx, my = sx / #patch, sy / #patch
				local several = area > 1.35 * math.pi * hearRadius ^ 2
				local single
				if not several then
					-- One dot: its edges either way from the middle, halfway between.
					local function Edge(dx, dy)
						local inside, outside = 0, hearRadius * 1.7
						local at = Hears(mx + dx * outside, my + dy * outside)
						if at ~= false then return nil end -- (still heard, or off the minimap: no edge to trust)
						if not Hears(mx, my) then return nil end
						for _ = 1, EDGE_STEPS do
							local mid = (inside + outside) / 2
							if Hears(mx + dx * mid, my + dy * mid) then inside = mid else outside = mid end
						end
						return (inside + outside) / 2
					end
					local west, east = Edge(-1, 0), Edge(1, 0)
					if west and east then mx = mx + (east - west) / 2 end
					local south, north = Edge(0, -1), Edge(0, 1)
					if south and north then my = my + (north - south) / 2 end
					local whole = (west and east and south and north) ~= nil
					single = { mx, my, whole = whole, area = area }
					-- (Wider one way than the other, or than a dot: two close together,
					-- heard as one patch, tested; else what it's heard over teaches the
					-- radius, slowly.)
					if whole then
						local across, up = (west + east) / 2, (south + north) / 2
						if math.abs(across - up) > 2.5 or math.max(across, up) > hearRadius + 3 then
							several = true
						else
							hearRadius = math.max(11, math.min(24, hearRadius + ((across + up) / 2 - hearRadius) / 4))
						end
					end
				end
				if not several then
					found[#found + 1] = single
				else
					-- Several: the outline (heard cells next to one not heard),
					-- each point half a cell out; and each heard cell's room to
					-- the nearest one not heard (a disc's middle has a radius of it).
					local outline, misses = {}, {}
					for _, k in ipairs(patch) do
						local px, py = Place(k)
						for _, d in ipairs({ { -1000, -1, 0 }, { 1000, 1, 0 }, { -1, 0, -1 }, { 1, 0, 1 } }) do
							if cells[k + d[1]] == false then
								outline[#outline + 1] = { px + d[2] * LOOK / 2, py + d[3] * LOOK / 2 }
								misses[#misses + 1] = { px + d[2] * LOOK, py + d[3] * LOOK }
							end
						end
					end
					local centers = {}
					for _, k in ipairs(patch) do
						local px, py = Place(k)
						local room = math.huge
						for _, m in ipairs(misses) do room = math.min(room, (px - m[1]) ^ 2 + (py - m[2]) ^ 2) end
						centers[#centers + 1] = { px, py, room ^ 0.5 }
					end
					local most = math.min(MOST_DOTS, math.max(2, math.floor(area / (math.pi * hearRadius ^ 2) + 1)))
					local function Fit(r)
						local open, discs, explained = outline, {}, 0
						local function Votes(cx, cy)
							local votes = 0
							for _, o in ipairs(open) do
								if math.abs(((cx - o[1]) ^ 2 + (cy - o[2]) ^ 2) ^ 0.5 - r) <= ARC then votes = votes + 1 end
							end
							return votes
						end
						for _ = 1, most do
							local best, bx, by = 0, 0, 0
							for _, c in ipairs(centers) do
								if c[3] >= r - ARC - LOOK then
									local votes = Votes(c[1], c[2])
									if votes > best then best, bx, by = votes, c[1], c[2] end
								end
							end
							if best < MIN_ARC then break end
							-- (A unit either way, in case it fits better between cells.)
							local cx, cy = bx, by
							for ox = -1, 1 do
								for oy = -1, 1 do
									local votes = Votes(bx + ox, by + oy)
									if votes > best then best, cx, cy = votes, bx + ox, by + oy end
								end
							end
							discs[#discs + 1] = { cx, cy }
							explained = explained + best
							local rest = {}
							for _, o in ipairs(open) do
								if math.abs(((cx - o[1]) ^ 2 + (cy - o[2]) ^ 2) ^ 0.5 - r) > ARC then rest[#rest + 1] = o end
							end
							open = rest
						end
						return discs, explained
					end
					local fits, top = {}, 0
					for _, r in ipairs({ hearRadius, hearRadius - 1.5, hearRadius + 1.5, hearRadius - 3, hearRadius + 3 }) do
						local discs, explained = Fit(r)
						fits[#fits + 1] = { discs = discs, explained = explained }
						top = math.max(top, explained)
					end
					local pick
					for _, fit in ipairs(fits) do
						if #fit.discs > 0 and fit.explained >= ENOUGH * top and (not pick or #fit.discs < #pick.discs
							or (#fit.discs == #pick.discs and fit.explained > pick.explained)) then
							pick = fit
						end
					end
					if pick and not (single and #pick.discs < 2) then
						for _, disc in ipairs(pick.discs) do found[#found + 1] = { disc[1], disc[2], fitted = true, area = area } end
					else
						-- (Nothing fitted, or one disc where the edges had one: those.)
						found[#found + 1] = single or { mx, my, area = area }
					end
				end
				-- (Gray where most of its patch was heard gray: indoors from you or
				-- outdoors, as the game's own dot.)
				local grayCells = 0
				for _, k in ipairs(patch) do
					if grays[k] then grayCells = grayCells + 1 end
				end
				for i = first, #found do found[i].gray = grayCells * 2 > #patch end
			end
			return found
		end)()
		local parts = {}
		for _, spot in ipairs(spots) do
			parts[#parts + 1] = ("%.1f, %.1f (%s, %.0f units sq)"):format(spot[1], spot[2],
				spot.fitted and "fitted" or spot.whole and "edges" or "middle", spot.area)
		end
		lastLocate = ("%s: from %.1f, %.1f (reach %.0f, %d probes): %s; heard %.1f around a dot"):format(name, x, y,
			reach, probes, #parts > 0 and table.concat(parts, " / ") or "nothing", hearRadius)
		return spots
	end)
end

local function Near(node, before)
	if before.name ~= node.name then return false end
	if node.n and before.n then
		return (node.n - before.n) ^ 2 + (node.w - before.w) ^ 2 <= MATCH_YARDS ^ 2
	end
	return (node.x - before.x) ^ 2 + (node.y - before.y) ^ 2 <= MATCH_UNITS ^ 2
end

-- The node pinged or marked lately that this one is (pinged's: the nearest
-- not claimed yet this sweep, so two veins side by side don't both take one
-- mark), or true for one only in the sweep before, or nil for a new one.
local function SeenBefore(node, now, claimed)
	local best, bestD
	for i = #pinged, 1, -1 do
		local record = pinged[i]
		if now - (record.seenAt or record.at) > PING_MEMORY then
			table.remove(pinged, i)
		elseif not (claimed and claimed[record]) and Near(node, record) then
			local d = (node.x - record.x) ^ 2 + (node.y - record.y) ^ 2
			if not bestD or d < bestD then best, bestD = record, d end
		end
	end
	if best then
		if claimed then claimed[best] = true end
		return best
	end
	for _, before in ipairs(nodes) do
		if Near(node, before) then return true end
	end
	return nil
end

-- Where a node is on the minimap now: from its place in the world, where you
-- are and the minimap's turn (PingNodes' sums the other way round), else where
-- it was seen.
local function ToMinimap(node, yards, facing, n, w)
	if node.n and yards and n then
		local cos, sin = math.cos(facing), math.sin(facing)
		local dn, dw = node.n - n, node.w - w
		return (sin * dn - cos * dw) / yards, (cos * dn + sin * dw) / yards
	end
	local scale = (node.yards and yards) and node.yards / yards or 1
	return node.x * scale, node.y * scale
end

-- Mark where it is's own mark ("mark"): a ring on the minimap, tinted by
-- kind, pulsing for MARK_TIME and then fading. It's ours (no sound, nobody
-- else sees it), and kept on the node each frame from its place in the world
-- as you walk and turn (where that's known: else where it was seen).
-- Node icons (minimapNodeIcons): the kinds ticked there get their icon on
-- the node itself, kept there for as long as the sweep still finds it.
local MarkNode, IconNode, IconWanted
local lastIcon -- (the last icon put on a node, for /cine debug tracking)
local lastSweepAt = -math.huge -- (the last sweep that heard anything: PingNodes)
do
	local RING = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\NodeRing" -- (Media/make_node_ring.py)
	local DISC = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\HelpDisc" -- (a round, soft-edged disc)
	local TINT = { herb = { 0.45, 0.95, 0.3 }, ore = { 1, 0.55, 0.25 }, treasure = { 1, 0.82, 0.1 } }
	local MARK_TIME, FADE, PULSE = 5, 1.2, 0.9 -- seconds: shown, its fade at the end, one pulse
	local SIZE, GROW = 13, 16 -- the ring's size and how much a pulse grows past it (minimap units)
	local ICON = 15 -- a node icon's disc (minimap units; the picture is most of it)
	local GONE = 4 -- seconds of sweeps not finding a node before its icon goes (gathered, or gone)
	local marks, icons, pool, driver = {}, {}, {}, nil

	function IconWanted(kind)
		local list = ns.db and ns.db.minimapNodeIcons
		return type(list) == "string" and kind ~= nil and (list .. ","):find(kind .. ",", 1, true) ~= nil
	end

	local function Place(pin, yards, facing, n, w)
		local x, y = ToMinimap(pin.node, yards, facing, n, w)
		local frame = pin.frame
		local edge = (Minimap:GetWidth() or 0) / 2 - 4
		if x * x + y * y > edge * edge then
			frame:Hide()
			return
		end
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", Minimap, "CENTER", x, y)
		frame:Show()
	end

	-- (An icon grayed, as the game's own dot, while its node is on the other side
	-- of indoors and outdoors from you: PingNodes' close looks tell, GrayLine.)
	local GRAY = { 0.6, 0.6, 0.6 }
	local function Shade(pin)
		local gray = pin.node.gray == true
		if pin.gray == gray then return end
		pin.gray = gray
		local frame, tint = pin.frame, gray and GRAY or pin.tint
		frame.icon:SetDesaturated(gray)
		frame.icon:SetVertexColor(gray and 0.75 or 1, gray and 0.75 or 1, gray and 0.75 or 1, 1)
		frame.edge:SetVertexColor(tint[1], tint[2], tint[3], 1)
	end

	local function Free(list, i)
		local frame = list[i].frame
		frame:Hide()
		pool[#pool + 1] = frame
		table.remove(list, i)
	end

	local function Update()
		local now = GetTime()
		local yards, facing = View()
		local n, w = Here()
		for i = #marks, 1, -1 do
			local mark = marks[i]
			local age = now - mark.at
			if age >= MARK_TIME or not (ns.db and ns.db.minimapNodeMark == "mark") then
				Free(marks, i)
			else
				local fade = age > MARK_TIME - FADE and (MARK_TIME - age) / FADE or 1
				local frame = mark.frame
				frame.ring:SetAlpha(fade)
				for k, pulse in ipairs(frame.pulses) do
					local p = (age / PULSE + (k - 1) / #frame.pulses) % 1
					pulse:SetSize(SIZE + p * GROW, SIZE + p * GROW)
					pulse:SetAlpha(fade * (1 - p) * 0.9)
				end
				Place(mark, yards, facing, n, w)
			end
		end
		for i = #icons, 1, -1 do
			local pin = icons[i]
			-- (Gone once sweeps have gone on without it: with none running, the
			-- minimap shown, it stays.)
			if not IconWanted(pin.kind) or not (ns.db and ns.db.minimapRevealNodes)
				or lastSweepAt - (pin.node.seenAt or pin.at) > GONE then
				pin.node.icon = nil
				Free(icons, i)
			else
				Shade(pin)
				Place(pin, yards, facing, n, w)
			end
		end
		if #marks == 0 and #icons == 0 then driver:Hide() end
	end

	-- (One frame for either: a ring with its pulses, or an icon on a dark disc
	-- edged with the kind's tint; the parts the other uses hidden.)
	local function NewFrame(icon)
		local frame = table.remove(pool)
		if not frame then
			frame = CreateFrame("Frame", nil, Minimap)
			frame:SetSize(SIZE + GROW, SIZE + GROW)
			frame:SetFrameLevel(Minimap:GetFrameLevel() + 6) -- (over the dots and blips)
			frame.ring = frame:CreateTexture(nil, "OVERLAY")
			frame.ring:SetTexture(RING)
			frame.ring:SetSize(SIZE, SIZE)
			frame.ring:SetPoint("CENTER")
			frame.pulses = {}
			for k = 1, 2 do
				local pulse = frame:CreateTexture(nil, "OVERLAY")
				pulse:SetTexture(RING)
				pulse:SetPoint("CENTER")
				frame.pulses[k] = pulse
			end
			frame.disc = frame:CreateTexture(nil, "OVERLAY", nil, 1)
			frame.disc:SetTexture(DISC)
			frame.disc:SetVertexColor(0, 0, 0, 0.85)
			frame.disc:SetSize(ICON, ICON)
			frame.disc:SetPoint("CENTER")
			-- (Square, inside the round edge: masked round with the disc it came out
			-- in orange and black bands, tested on Forever.)
			frame.icon = frame:CreateTexture(nil, "OVERLAY", nil, 2)
			frame.icon:SetSize(ICON * 0.72, ICON * 0.72)
			frame.icon:SetPoint("CENTER")
			frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			frame.edge = frame:CreateTexture(nil, "OVERLAY", nil, 3)
			frame.edge:SetTexture(RING)
			frame.edge:SetSize(ICON + 2, ICON + 2)
			frame.edge:SetPoint("CENTER")
		end
		frame.ring:SetShown(not icon)
		for _, pulse in ipairs(frame.pulses) do pulse:SetShown(not icon) end
		frame.disc:SetShown(icon)
		frame.icon:SetShown(icon)
		frame.edge:SetShown(icon)
		-- (An icon over a ring, where both are on one node.)
		frame:SetFrameLevel(Minimap:GetFrameLevel() + (icon and 7 or 6))
		frame:SetAlpha(1)
		return frame
	end

	local function Start()
		if not driver then
			driver = CreateFrame("Frame")
			ns.SetOnUpdate(driver, Update)
		end
		driver:Show()
		Update()
	end

	function MarkNode(node)
		local frame = NewFrame(false)
		local tint = TINT[ns.NodeKind(node.name)] or TINT.treasure
		frame.ring:SetVertexColor(tint[1], tint[2], tint[3], 1)
		for _, pulse in ipairs(frame.pulses) do pulse:SetVertexColor(tint[1], tint[2], tint[3], 1) end
		marks[#marks + 1] = { frame = frame, node = node, at = GetTime() }
		node.markedUntil = GetTime() + MARK_TIME -- (PingNodes keeps it on its dot till then)
		Start()
	end

	-- (node.icon: it has one, so PingNodes keeps the node and its place.)
	function IconNode(node)
		if node.icon then return end
		local kind = ns.NodeKind(node.name)
		local frame = NewFrame(true)
		local tint = TINT[kind] or TINT.treasure
		local icon = NodeIcon(node.name, kind)
		frame.icon:SetTexture(icon)
		lastIcon = { name = node.name, kind = kind, icon = icon, gray = node.gray }
		node.icon = true
		local pin = { frame = frame, node = node, kind = kind, tint = tint, at = GetTime() }
		Shade(pin)
		icons[#icons + 1] = pin
		Start()
	end
end

-- Where the dots of a patch the sweep heard really are (Locate, over the
-- whole of it): the sweep's points are STEP apart, so its middle can be most
-- of a step off a dot, or the gap between two. nil when it hears nothing.
local lastAnchor -- (for /cine debug tracking)
local function CloseLook(name, x, y, far)
	if ns.profiling then ns.ProfileCount("minimap close looks") end
	local spots = Locate(name, x, y, math.min(48, far + hearRadius + LOOK))
	return type(spots) == "table" and #spots > 0 and spots or nil
end

local ICON_LOOK = 6 -- seconds between close looks at a node with an icon on it
local function PingNodes(found)
	local db, now, claimed, at = ns.db, {}, {}, GetTime()
	lastSweepAt = at
	local style = db.minimapNodeMark
	local marking = style == "mark" or (style == "ping" and Minimap.PingLocation)
	local yards, facing = View()
	local n, w = Here()
	local function InWorld(record)
		record.yards = yards
		if yards and n then
			-- (Turned back from the minimap's turn into yards east and north.)
			local cos, sin = math.cos(facing), math.sin(facing)
			local sx, sy = record.x * yards, record.y * yards
			record.n, record.w = n + sx * sin + sy * cos, w - (sx * cos - sy * sin)
		end
	end
	-- (x, y: where the pretend mouse heard it; the node: where it's drawn.)
	local function Node(name, x, y)
		local node = { name = name, x = x, y = y }
		InWorld(node)
		return node
	end
	-- (Its dot looked at again near there: a mark still showing, put back on it
	-- each sweep, not left to drift (the yards per minimap unit aren't exact);
	-- an icon now and then; a node to get an icon now.)
	local function LookNear(node, far, iconWanted)
		for _, record in ipairs(pinged) do
			if record.name == node.name and (node.x - record.x) ^ 2 + (node.y - record.y) ^ 2 <= (far + MATCH_UNITS) ^ 2
				and ((record.markedUntil or 0) > at or (record.icon and at - (record.lookedAt or 0) > ICON_LOOK)
				or (iconWanted and not record.icon)) then
				return true
			end
		end
	end
	for name, entry in pairs(found or {}) do
		local kind = ns.NodeKind(name)
		if NODE_KINDS[kind] and db.minimapRevealNodes and entry.list then
			local iconWanted = IconWanted(kind)
			local tracking = marking or iconWanted
			for _, group in ipairs(Groups(entry.list, STEP)) do
				local coarse = Node(name, group[1], group[2])
				-- (A close look only where something's new, or a mark or icon's to
				-- be kept on its dot; else the sweep's middle does, to know it again.)
				local spots, looked = { group }, false
				-- (Heard over more than one dot's worth: likely two veins, one maybe new.)
				if tracking and (not SeenBefore(coarse, at) or LookNear(coarse, group[3], iconWanted) or group[3] > STEP) then
					local close = CloseLook(name, group[1], group[2], group[3])
					if close then spots, looked = close, true end
				end
				for _, spot in ipairs(spots) do
					local node = Node(name, spot[1], spot[2])
					node.gray = looked and spot.gray or nil
					local before = SeenBefore(node, at, claimed)
					if type(before) == "table" then
						-- (One pinged, marked or with an icon: still there, and its place
						-- from now on; one with an icon only from a close look, the
						-- sweep's middle being up to a step off.)
						before.seenAt = at
						if looked or not before.icon then
							if looked and (before.markedUntil or 0) > at then
								local px, py = ToMinimap(before, yards, facing, n, w)
								lastAnchor = ("%s: mark was at %.1f, %.1f, dot at %.1f, %.1f (%.1f off)"):format(name,
									px, py, node.x, node.y, ((px - node.x) ^ 2 + (py - node.y) ^ 2) ^ 0.5)
							end
							before.x, before.y = node.x, node.y
							InWorld(before)
							if looked then before.lookedAt, before.gray = at, node.gray end
						end
						if iconWanted and looked then IconNode(before) end
					-- (A new one only from a close look: the sweep's middle of two
					-- veins close together is the gap between them, where a mark or
					-- icon sat, tested; no close look, it waits for the next sweep.)
					elseif tracking and not before and looked then
						if style == "mark" then
							MarkNode(node)
						elseif style == "ping" and Minimap.PingLocation then
							ns.nodePingAt = at -- (not a ping of yours for Pings, Minimap page)
							pcall(Minimap.PingLocation, Minimap, node.x, node.y)
						end
						node.at, node.seenAt = at, at
						if looked then node.lookedAt = at end
						if iconWanted then IconNode(node) end
						pinged[#pinged + 1] = node
						claimed[node] = true
					end
					now[#now + 1] = node
				end
			end
		end
	end
	nodes = now
end

-- Quest cam (QuestCam.lua): whether a quest giver's mark (or a quest of yours
-- to hand in) is on the minimap within yards of you, not counting one named
-- skip; nil when it can't tell (retail, in combat, the mouse on the minimap,
-- no scale). Only the points that near the middle are tried, close together:
-- a mark heard there is near enough (one just beyond, heard at its edge, keeps
-- the old wait, nothing worse).
local NEAR_STEP = 3 -- minimap units between points
local GIVER_KINDS = { other = true, turnin = true }
function ns.QuestGiverNear(yards, skip)
	local perUnit = View()
	if not perUnit then return nil end
	local found = ns.SweepMinimap(NEAR_STEP, true, function(name)
		return name ~= skip and GIVER_KINDS[ns.NodeKind(name)] == true
	end, nil, yards / perUnit)
	if not found then return nil end
	for name in pairs(found) do
		if name ~= skip and GIVER_KINDS[ns.NodeKind(name)] then return true end
	end
	return false
end

-- The sweep's grid: points as far apart as can't miss a dot (each is
-- heard hearRadius around it: no spot further than step / sqrt 2 from a
-- point), 2 to spare; 12 to 20 units.
local function SweepStep()
	return math.max(12, math.min(20, math.floor((hearRadius - 2) * math.sqrt(2))))
end

-- The Reveal sweep, run as sweepJob (OnMinimap's turns wait across frames
-- in it): the grid, what's on it, then PingNodes' marks and close looks.
local function Sweep()
	local now = GetTime()
	STEP = SweepStep()
	-- (The ping needs every point that hears a node: no stopping at the first.)
	local marking = ns.db.minimapRevealNodes and ((ns.db.minimapNodeMark or "off") ~= "off"
		or (ns.db.minimapNodeIcons or "") ~= "")
	local found, probes, grown = ns.SweepMinimap(STEP, true, not marking and Wanted or nil)
	if ns.profiling then ns.ProfileCount("minimap sweeps") end
	last.at, last.why, last.grown, last.names = now, nil, grown, nil
	if not found then
		last.why = probes
		return
	end
	-- (A whole sweep hearing nothing, not even your arrow in the middle, counts as
	-- a try of the answer check too: the minimap may be faded the whole time.)
	if next(found) then
		answer.state = "yes"
	elseif not answer.state then
		ns.CountNoAnswer()
	end
	local names, wantedNames = {}, {}
	areaShown = false
	for name, entry in pairs(found) do
		local wanted = Wanted(name, entry)
		local kind = ns.NodeKind(name)
		if kind == "objective" and not OnlyAtRim(entry) then areaShown = true end
		names[#names + 1] = ("%s (%s%s%s)"):format(name, kind,
			QUEST_KINDS[kind] and OnlyAtRim(entry) and ", at the rim" or "", wanted and ", reveals" or "")
		if wanted then
			seenAt = GetTime()
			wantedNames[#wantedNames + 1] = name
		end
	end
	if #wantedNames > 0 then
		table.sort(wantedNames)
		revealedBy = table.concat(wantedNames, ", ")
	end
	last.names, last.probes, last.step = table.concat(names, ", "), probes, STEP
	PingNodes(found)
end

-- One frame of the job; done or failed, it's dropped (a turn left half way
-- is put back: the minimap where it was, the cursor off).
local function RunSweep()
	if not sweepJob then return end
	framePoints = 0
	local ok, err = coroutine.resume(sweepJob)
	if coroutine.status(sweepJob) == "dead" then
		sweepJob = nil
		if session then
			Leave(session)
			session = nil
		end
		if not ok then
			if type(err) == "table" and err.stopped then
				last.why = err.stopped
			else
				last.why = "error: " .. tostring(err)
				ns.Log("nodes", "the minimap sweep failed: " .. tostring(err))
			end
		end
	end
end
RunSweep = ns.Profiled("Minimap sweep", RunSweep)
local sweepDriver = CreateFrame("Frame")
sweepDriver:Hide()
ns.SetOnUpdate(sweepDriver, function(self)
	RunSweep()
	if not sweepJob then self:Hide() end
end)

-- Does the game answer the pretend mouse (answer, at the top)? Every few
-- seconds after login until it's known: with the minimap shown, its icons at
-- their size and your mouse off it, a few points on your arrow in its middle,
-- which always has your name. Three tries hearing nothing and it's a no for
-- this login: Reveal stops (the faded minimap shrinks away as usual, nothing
-- shows through it) and its boxes are hidden.
local ANSWER_EVERY = 4
local answerCheck = CreateFrame("Frame")
local answerWait = ANSWER_EVERY
ns.SetOnUpdate(answerCheck, function(self, elapsed)
	if answer.state or not HasSweepApi() then
		self:Hide()
		return
	end
	answerWait = answerWait - elapsed
	if answerWait > 0 then return end
	answerWait = ANSWER_EVERY
	if sweepJob or iconsHidden or InCombatLockdown() or not ns.Flag(Minimap:IsVisible())
		or Minimap:GetEffectiveAlpha() < 0.9 or ns.Flag(Minimap:IsMouseOver()) or not Minimap:GetLeft() then
		return
	end
	local heard = false
	local turn = {}
	if Enter(turn) then return end
	pcall(function()
		for _, point in ipairs({ { 0, 0 }, { 1.5, 1.5 }, { -1.5, -1.5 }, { 0, 2.5 }, { 0, -2.5 } }) do
			local lines = Listen(point[1], point[2])
			if lines and #lines > 0 then
				heard = true
				return
			end
		end
	end)
	Leave(turn)
	if heard then
		answer.state = "yes"
	else
		ns.CountNoAnswer()
	end
end)

-- Without the sweep (the game not answering it, above): Quest areas and Quest
-- turn-ins from the quest log instead. Each quest's spot on the zone map
-- (C_QuestLog.GetQuestsOnMap: the middle of its area, or where it's handed in
-- once done), how far it is from you in yards, and the minimap's view radius:
-- within it, it's on the minimap. (An area reaches a little past its middle:
-- QUEST_AREA_REACH yards more for those.)
local QUEST_AREA_REACH = 25
local questLook = { at = -math.huge, report = "hasn't looked yet" }

function ns.CanRevealQuestsOnly()
	return HasSweepApi() and answer.state == "no" and C_QuestLog ~= nil and C_QuestLog.GetQuestsOnMap ~= nil
		and C_Map ~= nil and C_Map.GetWorldPosFromMapPos ~= nil
end

local function QuestReveal()
	local db = ns.db
	return db and db.handleMinimap ~= false and ns.CanRevealQuestsOnly()
		and (db.minimapRevealAreas or db.minimapRevealTurnIns) or false
end

local function Known(value)
	return value ~= nil and not Secret(value)
end

-- The quests on the minimap now: names that reveal it, and a report line.
local function QuestsOnMinimap()
	local db = ns.db
	local mapID = C_Map.GetBestMapForUnit("player")
	if not Known(mapID) or not mapID then return nil, "no map here" end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil, "no position on the map here" end
	local _, here = C_Map.GetWorldPosFromMapPos(mapID, pos)
	local ok, radius = pcall(C_Minimap.GetViewRadius)
	if not (here and Known(here.x) and ok and type(radius) == "number") then return nil, "no world position" end
	local quests = C_QuestLog.GetQuestsOnMap(mapID)
	if type(quests) ~= "table" then return nil, "no quests on the map" end
	local wanted, parts = {}, {}
	for _, quest in ipairs(quests) do
		local id, x, y = quest.questID, quest.x, quest.y
		if Known(id) and Known(x) and Known(y) then
			local _, there = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
			if there and Known(there.x) then
				local yards = math.sqrt((here.x - there.x) ^ 2 + (here.y - there.y) ^ 2)
				local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) == true
				local reach = done and radius or radius + QUEST_AREA_REACH
				local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id) or tostring(id)
				local on = yards <= reach
				local reveals = on and (done and db.minimapRevealTurnIns or not done and db.minimapRevealAreas)
				if reveals then wanted[#wanted + 1] = title end
				parts[#parts + 1] = ("%s (%s, %.0f yd%s)"):format(title, done and "done" or "area", yards,
					reveals and ", reveals" or on and ", on it" or "")
			end
		end
	end
	return wanted, ("view radius %.0f yd: %s"):format(radius, #parts > 0 and table.concat(parts, "; ") or "no quests")
end

local function QuestReveals(now)
	if now - questLook.at >= SWEEP_EVERY then
		questLook.at = now
		local ok, wanted, report = pcall(QuestsOnMinimap)
		questLook.report = ok and report or ("failed: " .. tostring(wanted))
		if ok and wanted and #wanted > 0 then
			table.sort(wanted)
			seenAt = now
			revealedBy = table.concat(wanted, ", ")
		end
	end
	return now - seenAt < HOLD
end

-- For /cine debug tracking: what the quest log look last saw.
function ns.QuestRevealReport()
	if not ns.CanRevealQuestsOnly() then return nil end
	return ("minimap quests (no sweep): %s, %.1fs ago; last reveal %s"):format(questLook.report,
		GetTime() - (questLook.at > -math.huge and questLook.at or GetTime()),
		seenAt > -math.huge and ("%.1fs ago"):format(GetTime() - seenAt) or "never")
end

-- (A fight stops the sweep, SweepMinimap: a minimap revealed as it started
-- stays up through it, rather than fading once the hold runs out and coming
-- back as it ends. nil out of fights; true or false, latched at its start.)
local heldIntoFight
function ns.IsMinimapRevealed(now)
	if QuestReveal() then return QuestReveals(now) end
	if not AnyReveal() then
		nodes = {}
		heldIntoFight = nil
		return false
	end
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		if heldIntoFight == nil then heldIntoFight = now - seenAt < HOLD end
		if heldIntoFight then
			seenAt = now
			return true
		end
	else
		heldIntoFight = nil
	end
	-- (A sweep due: started as a job, its first points now, the rest over the
	-- next frames; what it finds counts once it's done.)
	if not sweepJob and now - sweptAt >= SWEEP_EVERY and (Minimap:GetEffectiveAlpha() < 0.99 or now - seenAt < HOLD) then
		sweptAt = now
		sweepJob = coroutine.create(Sweep)
		RunSweep()
		if sweepJob then sweepDriver:Show() end
	end
	return now - seenAt < HOLD
end

-- For /cine why: whether a reveal holds the minimap up now, what the sweep
-- last found that revealed it (names, or nil), and whether it's held up
-- through a fight it was up at the start of.
function ns.MinimapRevealWhy(now)
	if not (AnyReveal() or QuestReveal()) or now - seenAt >= HOLD then return false end
	return true, revealedBy, heldIntoFight == true
end

-- /cine debug nodeoffset: how far what the pretend mouse hears sits from
-- what's drawn (marks sat up and left of the veins, tested). For 20 seconds,
-- the real mouse resting on a dot: each name its tooltip gives, at the
-- middle of where it gave it. Once the mouse is off the minimap, the pretend
-- mouse's close look around each of those, and how far off what it hears is.
do
	local watcher, untilAt, heard
	local function Report()
		local any = false
		for name, list in pairs(heard) do
			any = true
			local rx, ry = 0, 0
			for i = 1, #list, 2 do rx, ry = rx + list[i], ry + list[i + 1] end
			rx, ry = rx / (#list / 2), ry / (#list / 2)
			local found, why = Locate(name, rx, ry, 40)
			local spots = type(found) == "table" and found or {}
			local best, bestD
			for _, spot in ipairs(spots) do
				local d = (spot[1] - rx) ^ 2 + (spot[2] - ry) ^ 2
				if not bestD or d < bestD then best, bestD = spot, d end
			end
			-- (Kept, to fit what's heard against what's drawn: nodeOffsetSamples; the
			-- first ones, nodeOffsets, came before Locate split pairs and aren't read.)
			if best and ns.db then
				ns.db.nodeOffsetSamples = ns.db.nodeOffsetSamples or {}
				table.insert(ns.db.nodeOffsetSamples, { drawn = { rx, ry }, heard = { best[1], best[2] },
					width = Minimap:GetWidth(), scale = Minimap:GetEffectiveScale(),
					left = Minimap:GetLeft(), bottom = Minimap:GetBottom(), height = Minimap:GetHeight() })
			end
			ns.Print(("nodeoffset: %s: your mouse got it around %.1f, %.1f (%d spots); pretend mouse %s"):format(name,
				rx, ry, #list / 2, best and ("around %.1f, %.1f: off by %.1f across, %.1f up"):format(best[1], best[2],
				best[1] - rx, best[2] - ry) or ("hears nothing there (" .. tostring(why or "no answer") .. ")")))
		end
		if not any then ns.Print("nodeoffset: your mouse got no tooltip on the minimap") end
		-- (Each axis on its own, drawn = a * heard + b, by least squares over all kept.)
		local kept = ns.db and ns.db.nodeOffsetSamples or {}
		local fits = {}
		for axis = 1, 2 do
			local n, sh, sd, shh, shd = #kept, 0, 0, 0, 0
			for _, s in ipairs(kept) do
				local h, d = s.heard[axis], s.drawn[axis]
				sh, sd, shh, shd = sh + h, sd + d, shh + h * h, shd + h * d
			end
			local den = n * shh - sh * sh
			if n >= 2 and math.abs(den) > 1e-6 then
				local a = (n * shd - sh * sd) / den
				fits[axis] = ("%.2f x heard %+.1f"):format(a, (sd - a * sh) / n)
			else
				fits[axis] = "needs samples further apart"
			end
		end
		ns.Print(("nodeoffset: %d kept; drawn across = %s, drawn up = %s; Minimap %.0f x %.0f"):format(#kept, fits[1],
			fits[2], Minimap:GetWidth() or 0, Minimap:GetHeight() or 0))
		heard = {}
	end
	function ns.NodeOffsetWatch()
		if not watcher then
			watcher = CreateFrame("Frame")
			ns.SetOnUpdate(watcher, function(self)
				local over = ns.Flag(Minimap:IsMouseOver())
				if not over and (next(heard) or GetTime() > untilAt) then
					self:Hide()
					Report()
					return
				end
				if not over then return end
				local cx, cy = GetCursorPosition()
				local scale, left, bottom = Minimap:GetEffectiveScale(), Minimap:GetLeft(), Minimap:GetBottom()
				if not (cx and scale and left and bottom) then return end
				local half = (Minimap:GetWidth() or 0) / 2
				local ux, uy = cx / scale - left - half, cy / scale - bottom - half
				local data = C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover and C_TooltipInfo.GetMinimapMouseover()
				local lines = type(data) == "table" and not Secret(data) and data.lines
				for _, line in ipairs(type(lines) == "table" and not Secret(lines) and lines or {}) do
					local text = line.leftText
					if type(text) == "string" and not Secret(text) then
						local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
						for name in plain:gmatch("[^\n]+") do
							name = name:match("^%s*(.-)%s*$")
							if NODE_KINDS[ns.NodeKind(name)] then
								heard[name] = heard[name] or {}
								local list = heard[name]
								list[#list + 1], list[#list + 2] = ux, uy
							end
						end
					end
				end
			end)
		end
		untilAt, heard = GetTime() + 20, {}
		watcher:Show()
		local entry = MinimapEntry()
		ns.Print(("nodeoffset: 20 seconds: stand still, rest your mouse on a vein's dot, then move it off the minimap. " ..
			"Minimap %.0f wide, scale %.2f; faded: shrunk %s, off the screen %s"):format(Minimap:GetWidth() or 0,
			Minimap:GetEffectiveScale() or 0, tostring(entry and entry.shrunk or false),
			tostring(entry and entry.parkedFullSize or false)))
	end
end

function ns.NodeSweepReport()
	if not HasSweepApi() then return "minimap sweep: this client can't move a pretend mouse over the minimap" end
	if answer.state == "no" then
		return answer.fails >= ANSWER_TRIES
			and "minimap sweep: off this login, the game doesn't answer the pretend mouse (nothing at your arrow, 3 tries)"
			or ("minimap sweep: off, game %d and later don't answer the pretend mouse (tested)"):format(NO_ANSWER_FROM)
	end
	if not answer.state then
		ns.Print(("minimap sweep: does the game answer it? not known yet, %d of %d tries heard nothing"):format(
			answer.fails, ANSWER_TRIES))
	end
	if not last.at then return "minimap sweep: hasn't run (needs a Reveal box ticked, Minimap page)" end
	-- (Each node's place in the world should stay put as you move: if it drifts,
	-- the sums turning minimap offsets into yards are off.)
	local places = {}
	for _, node in ipairs(nodes) do
		places[#places + 1] = node.n and ("%s at %.0f N %.0f W"):format(node.name, node.n, node.w)
			or ("%s at %.0f, %.0f on the minimap (no world place)"):format(node.name, node.x, node.y)
	end
	if #places > 0 then ns.Print("nodes: " .. table.concat(places, "; ")) end
	if lastLocate then ns.Print("last close look, minimap units from the middle: " .. lastLocate) end
	if lastIcon then
		-- (The icon itself, big in the chat line, to see what the mark's badge shows.)
		ns.Print(("last mark's icon: |T%s:40:40|t %s (%s%s): %s"):format(tostring(lastIcon.icon), lastIcon.name,
			lastIcon.kind, lastIcon.gray and ", gray: other side of indoors/outdoors" or "", tostring(lastIcon.icon)))
	end
	if lastAnchor then ns.Print("last mark put back on its dot, minimap units: " .. lastAnchor) end
	local ok, radius = pcall(C_Minimap and C_Minimap.GetViewRadius or error)
	ns.Print(("minimap: view radius %s yards, width %.1f, so %s yards a unit; zoom %s"):format(tostring(ok and radius),
		Minimap:GetWidth() or 0, tostring(View()), tostring(Minimap:GetZoom())))
	return ("minimap sweep: %.1fs ago%s%s: %s; last reveal %s"):format(GetTime() - last.at,
		last.grown and ", minimap grown for it" or "",
		areaShown and ", a quest area on it (waits off the screen while faded)" or "",
		last.why and ("couldn't sweep (" .. tostring(last.why) .. ")")
			or (("%d points %d apart (over a few frames), heard %s"):format(last.probes or 0, last.step or STEP,
				last.names ~= "" and last.names or "nothing")),
		seenAt > -math.huge and ("%.1fs ago"):format(GetTime() - seenAt) or "never")
end
