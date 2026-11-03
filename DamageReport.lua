-- Damage Vision's full report (DamageVision.lua's): a window with how you did
-- on the whole run, on its bosses and on the rest, a row per boss, and the
-- party's standings for the row you pick. Opened by the Dungeon done recap's
-- Full report button, its page's button or /cine report (/cine report test:
-- made up). Read from the game's meter out of fights only (its totals are
-- secret in them, and for a whole key): the meter's Overall, and its session
-- per fight (GetAvailableCombatSessions: a boss's named "(!) <boss>", the
-- rest unnamed). Not bosses = Overall less the bosses, player by player.

local _, ns = ...
local L = ns.L

local PAD = 16
local GAP = 10
local WIDTH = 800
local TABLE_WIDTH = 560
local PARTY_WIDTH = WIDTH - PAD * 3 - TABLE_WIDTH
local TILE_WIDTH = math.floor((WIDTH - PAD * 2 - GAP * 2) / 3)
local TOP = 58          -- the tiles' top, under the title
local TABLE_TOP = 168   -- the table's and party's top
local ROW = 24          -- a table row's height
local MEMBER = 20       -- a party row's step
local PARTY_ROWS = 10   -- the most of the party listed (you last if further down)
local BOSS_ROWS = 12    -- the most bosses listed (the newest)
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local LEAD = { 0.44, 0.76, 1 }     -- ahead: blue
local CHASE = { 0.94, 0.64, 0.37 } -- behind: orange
local BOSSES = { 0.88, 0.72, 0.29 }
local REST = { 0.36, 0.56, 0.84 }
-- The table's columns: x from its left, width, justified (numbers to the right).
local COLUMNS = { { 0, 206, "LEFT" }, { 212, 48, "RIGHT" }, { 266, 60, "RIGHT" }, { 332, 56, "RIGHT" },
	{ 406, 50, "LEFT" }, { 458, 94, "LEFT" } }

local window, report, picked, sample
local Draw

local function Plain(value)
	return not (issecretvalue and issecretvalue(value))
end

-- A total, shortened the same way everywhere (47.3M, 674K): the game's
-- AbbreviateNumbers rounds some to whole millions and not others.
local function Short(value)
	local size = math.abs(value)
	if size >= 1e9 then return ("%.1fB"):format(value / 1e9) end
	if size >= 1e6 then return ("%.1fM"):format(value / 1e6) end
	if size >= 1e3 then return ("%.0fK"):format(value / 1e3) end
	return ("%d"):format(math.floor(value + 0.5))
end

local function Clock(seconds)
	seconds = math.floor(seconds + 0.5)
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- Reading ---------------------------------------------------------------------

-- A session's rows (DamageVision's Rows: players only) as
-- { key, name, class, mine, amount }; nil if any of it's secret.
local function Players(rows)
	if type(rows) ~= "table" then return end
	local list = {}
	for _, row in ipairs(rows) do
		local amount, name, guid, mine = row.totalAmount, row.name, row.sourceGUID, row.isLocalPlayer
		if not (Plain(amount) and Plain(name) and Plain(mine)) or type(amount) ~= "number" then return end
		list[#list + 1] = { key = Plain(guid) and guid or name, name = name, class = row.classFilename,
			mine = mine == true, amount = amount }
	end
	return list
end

local function Copy(player, amount)
	return { key = player.key, name = player.name, class = player.class, mine = player.mine, amount = amount }
end

-- A row of the report: its label, everyone's totals (biggest first), its time in combat.
local function Scope(label, players, seconds, kind)
	table.sort(players, function(a, b) return a.amount > b.amount end)
	return { label = label, players = players, seconds = seconds and seconds > 0 and seconds or nil, kind = kind }
end

-- The report from the bosses ({ label, players, seconds }) and the whole run.
local function Build(bosses, overall, allTime)
	local scopes, sums, bossTime = {}, {}, 0
	for _, boss in ipairs(bosses) do
		scopes[#scopes + 1] = Scope(boss.label, boss.players, boss.seconds, "boss")
		bossTime = bossTime + (boss.seconds or 0)
		for _, player in ipairs(boss.players) do
			local have = sums[player.key]
			if have then have.amount = have.amount + player.amount else sums[player.key] = Copy(player, player.amount) end
		end
	end
	while #scopes > BOSS_ROWS do table.remove(scopes, 1) end
	local all, rest = {}, {}
	for _, player in pairs(sums) do all[#all + 1] = player end
	for _, player in ipairs(overall) do
		local boss = sums[player.key]
		rest[#rest + 1] = Copy(player, math.max(0, player.amount - (boss and boss.amount or 0)))
	end
	local bossesScope = Scope(L["All bosses"], all, bossTime, "sum")
	local restScope = Scope(L["Not bosses"], rest, allTime - bossTime, "sum")
	local run = Scope(L["Whole run"], overall, allTime, "run")
	return { bossScopes = scopes, bosses = bossesScope, rest = restScope, run = run,
		sums = { bossesScope, restScope, run } }
end

-- Made up (/cine report test, or the recap's test): you and four others,
-- four bosses (totals in millions) and the rest.
local SAMPLE = {
	classes = { "HUNTER", "WARRIOR", "PALADIN", "PRIEST" },
	bosses = {
		{ 112, 4.82, 5.10, 4.60, 2.70, 0.85 }, { 141, 6.10, 5.40, 4.90, 2.90, 0.95 },
		{ 125, 5.35, 5.20, 4.50, 2.70, 0.85 }, { 132, 5.90, 5.70, 4.90, 2.90, 0.95 },
	},
	rest = { 880, 31.4, 34.8, 30.9, 19.8, 5.8 },
}

local function Sample()
	local _, class = UnitClass("player")
	local people = { { key = "you", name = UnitName("player"), class = class, mine = true } }
	for i, other in ipairs(SAMPLE.classes) do
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[other] or other
		people[i + 1] = { key = other, name = name, class = other }
	end
	local function Amounts(amounts)
		local list = {}
		for i, person in ipairs(people) do list[i] = Copy(person, amounts[i + 1] * 1000000) end
		return list
	end
	local bosses, overall, allTime = {}, Amounts(SAMPLE.rest), SAMPLE.rest[1]
	for i, boss in ipairs(SAMPLE.bosses) do
		bosses[i] = { label = L["Boss %d"]:format(i), players = Amounts(boss), seconds = boss[1] }
		allTime = allTime + boss[1]
		for j, player in ipairs(overall) do player.amount = player.amount + boss[j + 1] * 1000000 end
	end
	local built = Build(bosses, overall, allTime)
	built.where = L["Made up"]
	return built
end

local function Read()
	if sample then return Sample() end
	local meter = ns.DamageVisionMeter
	if not (meter and meter.HasMeter()) then return { message = L["This client has no damage meter."] } end
	if InCombatLockdown() or meter.Restricted() then
		return { message = L["The meter's totals are hidden in a fight (and for a whole key). " ..
			"The report fills in once it's over."], wait = true }
	end
	local meterType = meter.MeterType()
	local overall = Players(meter.Rows(Enum.DamageMeterSessionType.Overall, meterType))
	if not overall or #overall == 0 then return { message = L["Nothing on the meter yet."] } end
	local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
	if not ok or type(sessions) ~= "table" or (issecrettable and issecrettable(sessions)) then sessions = {} end
	local bosses, pulls, allTime = {}, {}, 0
	for _, session in ipairs(sessions) do
		local name, seconds = session.name, session.durationSeconds
		if not (Plain(seconds) and type(seconds) == "number") then seconds = nil end
		allTime = allTime + (seconds or 0)
		if Plain(name) and type(name) == "string" and name:find("^%(!%)") then
			local players = Players(meter.Rows(nil, meterType, session.sessionID))
			if players then
				local label = name:gsub("^%(!%)%s*", "")
				pulls[label] = (pulls[label] or 0) + 1
				if pulls[label] > 1 then label = L["%s (pull %d)"]:format(label, pulls[label]) end
				bosses[#bosses + 1] = { label = label, players = players, seconds = seconds }
			end
		end
	end
	local built = Build(bosses, overall, allTime)
	built.healing = meterType == Enum.DamageMeterType.HealingDone
	local where, _, _, difficulty = GetInstanceInfo()
	built.where = where and difficulty and difficulty ~= "" and (where .. " · " .. difficulty) or where
	return built
end

-- How you did in a scope: total, per second, place and the gap (to #1, or your lead over #2).
local function Info(scope)
	local players = scope.players
	for i, player in ipairs(players) do
		if player.mine then
			local info = { total = Short(player.amount), place = L["#%d of %d"]:format(i, #players) }
			info.rate = scope.seconds and Short(player.amount / scope.seconds) or "-"
			if i == 1 and players[2] then
				info.gap, info.color = L["+%s ahead"]:format(Short(player.amount - players[2].amount)), LEAD
			elseif i > 1 then
				info.gap, info.color = L["-%s behind"]:format(Short(players[1].amount - player.amount)), CHASE
			end
			return info
		end
	end
	return { total = "-", rate = "-", place = players[1] and L["Not on it"] or "-" }
end

-- The window -----------------------------------------------------------------

local function Text(parent, font, justify)
	local text = parent:CreateFontString(nil, "OVERLAY", font)
	text:SetJustifyH(justify or "LEFT")
	text:SetWordWrap(false)
	return text
end

local function NewTile(index)
	local tile = CreateFrame("Frame", nil, window.content)
	tile:SetSize(TILE_WIDTH, 68)
	tile:SetPoint("TOPLEFT", PAD + (index - 1) * (TILE_WIDTH + GAP), -TOP)
	if ns.SkinWindow then ns.SkinWindow(tile, true) end
	tile.label = Text(tile, "GameFontDisableSmall")
	tile.label:SetPoint("TOPLEFT", 10, -8)
	tile.total = Text(tile, "GameFontHighlightLarge")
	tile.total:SetPoint("TOPLEFT", tile.label, "BOTTOMLEFT", 0, -4)
	tile.rate = Text(tile, "GameFontDisableSmall")
	tile.rate:SetPoint("BOTTOMLEFT", tile.total, "BOTTOMRIGHT", 8, 1)
	tile.place = Text(tile, "GameFontNormal")
	tile.place:SetPoint("TOPLEFT", tile.total, "BOTTOMLEFT", 0, -5)
	tile.gap = Text(tile, "GameFontHighlightSmall")
	tile.gap:SetPoint("LEFT", tile.place, "RIGHT", 8, 0)
	return tile
end

local function NewRow()
	local row = CreateFrame("Button", nil, window.grid)
	row:SetSize(TABLE_WIDTH, ROW)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.picked = row:CreateTexture(nil, "BACKGROUND")
	row.picked:SetAllPoints()
	row.picked:SetColorTexture(1, 0.82, 0, 0.12)
	row.cells = {}
	for c, column in ipairs(COLUMNS) do
		local cell = Text(row, c == 1 and "GameFontHighlight" or "GameFontHighlightSmall", column[3])
		cell:SetPoint("LEFT", column[1] + 6, 0)
		cell:SetWidth(column[2])
		row.cells[c] = cell
	end
	row:SetScript("OnClick", function(self)
		picked = self.scope
		Draw()
	end)
	return row
end

local function NewMember()
	local bar = CreateFrame("StatusBar", nil, window.party)
	bar:SetSize(PARTY_WIDTH, MEMBER - 2)
	bar:SetStatusBarTexture(BAR_TEXTURE)
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.45)
	bar.name = Text(bar, "GameFontHighlightSmall")
	bar.name:SetPoint("LEFT", 4, 0)
	bar.name:SetPoint("RIGHT", -56, 0)
	bar.total = Text(bar, "GameFontHighlightSmall", "RIGHT")
	bar.total:SetPoint("RIGHT", -4, 0)
	return bar
end

local function Create()
	window = CreateFrame("Frame", "CinematicDamageReport", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	window:SetSize(WIDTH, 300)
	window:SetPoint("CENTER", 0, 60)
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if self.SetUserPlaced then self:SetUserPlaced(false) end
	end)
	if window.SetBackdrop then
		window:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
	end
	if ns.SkinWindow then ns.SkinWindow(window) end
	window:Hide()
	tinsert(UISpecialFrames, "CinematicDamageReport") -- Escape closes it
	ns.AddOverlay(window) -- (up with the UI hidden too)

	window.title = Text(window, "GameFontNormalLarge")
	window.title:SetPoint("TOPLEFT", PAD, -14)
	window.where = Text(window, "GameFontDisableSmall")
	window.where:SetPoint("TOPLEFT", window.title, "BOTTOMLEFT", 0, -4)
	window.where:SetWidth(WIDTH - PAD * 2 - 30)
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	if ns.SkinClose then ns.SkinClose(close) end
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() window:Hide() end)

	window.message = Text(window, "GameFontHighlight", "CENTER")
	window.message:SetPoint("TOP", 0, -TOP - 30)
	window.message:SetWidth(WIDTH - PAD * 4)
	window.message:SetWordWrap(true)

	local content = CreateFrame("Frame", nil, window)
	content:SetAllPoints()
	window.content = content
	window.tiles = { NewTile(1), NewTile(2), NewTile(3) }

	-- Where yours came from: a bar, bosses and the rest.
	local share = CreateFrame("Frame", nil, content)
	share:SetPoint("TOPLEFT", PAD, -TOP - 78)
	share:SetSize(WIDTH - PAD * 2, 24)
	share.label = Text(share, "GameFontDisableSmall")
	share.label:SetPoint("TOPLEFT")
	share.legend = Text(share, "GameFontDisableSmall", "RIGHT")
	share.legend:SetPoint("TOPRIGHT")
	share.bosses = share:CreateTexture(nil, "ARTWORK")
	share.bosses:SetPoint("BOTTOMLEFT")
	share.bosses:SetHeight(8)
	share.bosses:SetColorTexture(BOSSES[1], BOSSES[2], BOSSES[3], 1)
	share.rest = share:CreateTexture(nil, "ARTWORK")
	share.rest:SetPoint("BOTTOMRIGHT")
	share.rest:SetHeight(8)
	share.rest:SetColorTexture(REST[1], REST[2], REST[3], 1)
	window.share = share

	local grid = CreateFrame("Frame", nil, content)
	grid:SetPoint("TOPLEFT", PAD, -TABLE_TOP)
	grid:SetSize(TABLE_WIDTH, 100)
	if ns.SkinWindow then ns.SkinWindow(grid, true) end
	grid.heads = {}
	for c, column in ipairs(COLUMNS) do
		local head = Text(grid, "GameFontDisableSmall", column[3])
		head:SetPoint("TOPLEFT", column[1] + 6, -6)
		head:SetWidth(column[2])
		grid.heads[c] = head
	end
	grid.rows = {}
	grid.hint = Text(grid, "GameFontDisableSmall")
	grid.hint:SetText(L["Click a row to see the whole party for it."])
	window.grid = grid

	local party = CreateFrame("Frame", nil, content)
	party:SetPoint("TOPLEFT", grid, "TOPRIGHT", PAD, 0)
	party:SetSize(PARTY_WIDTH, 100)
	party.label = Text(party, "GameFontDisableSmall")
	party.label:SetPoint("TOPLEFT", 0, -6)
	party.label:SetText(L["Party"])
	party.scope = Text(party, "GameFontNormal")
	party.scope:SetPoint("TOPLEFT", party.label, "BOTTOMLEFT", 0, -3)
	party.scope:SetWidth(PARTY_WIDTH)
	party.members = {}
	window.party = party
end

-- The party in the picked row: biggest first, you in the last row if further down.
local function DrawParty(scope)
	local party = window.party
	local players = scope.players
	party.scope:SetText(scope.label)
	local mine
	for i, player in ipairs(players) do
		if player.mine then mine = i end
	end
	local count = math.min(#players, PARTY_ROWS)
	local top = players[1] and players[1].amount or 0
	for i = 1, math.max(count, #party.members) do
		local bar = party.members[i]
		if i <= count then
			bar = bar or NewMember()
			party.members[i] = bar
			local index = (i == count and mine and mine > count) and mine or i
			local player = players[index]
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", 0, -42 - (i - 1) * MEMBER)
			bar:SetMinMaxValues(0, math.max(top, 1))
			bar:SetValue(player.amount)
			local color = player.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[player.class]
			local r, g, b = color and color.r or 0.7, color and color.g or 0.7, color and color.b or 0.7
			bar:SetStatusBarColor(r, g, b, player.mine and 1 or 0.6)
			local name = player.mine and L["You"] or tostring(player.name)
			if not player.mine and Ambiguate then
				local ok, short = pcall(Ambiguate, name, "short")
				if ok and type(short) == "string" then name = short end
			end
			bar.name:SetText(("%d. %s"):format(index, name))
			bar.total:SetText(Short(player.amount))
			bar:Show()
		elseif bar then
			bar:Hide()
		end
	end
	return 42 + count * MEMBER
end

local function FillRow(row, scope)
	local info = Info(scope)
	row.scope = scope
	local cells = row.cells
	cells[1]:SetText(scope.label)
	cells[1]:SetTextColor(1, scope.kind == "run" and 0.82 or 1, scope.kind == "run" and 0 or 1)
	cells[2]:SetText(scope.seconds and Clock(scope.seconds) or "-")
	cells[3]:SetText(info.total)
	cells[4]:SetText(info.rate)
	cells[5]:SetText(info.place)
	cells[6]:SetText(info.gap or "")
	local color = info.color or LEAD
	cells[6]:SetTextColor(color[1], color[2], color[3])
	row.picked:SetShown(scope == picked)
	row:Show()
end

function Draw()
	if not window then return end
	window.title:SetText(report and report.healing and L["Healing report"] or L["Damage report"])
	window.where:SetText(report and report.where or "")
	local hasReport = report and report.run
	window.content:SetShown(hasReport and true or false)
	window.message:SetShown(not hasReport)
	if not hasReport then
		window.message:SetText(report and report.message or "")
		window:SetHeight(TOP + 30 + window.message:GetStringHeight() + 40)
		return
	end
	picked = picked or report.run
	local rateName = report.healing and L["HPS"] or L["DPS"]

	for i, scope in ipairs({ report.run, report.bosses, report.rest }) do
		local tile, info = window.tiles[i], Info(scope)
		tile.label:SetText(scope == report.rest and L["Not bosses"] or scope == report.bosses and L["Bosses"]
			or L["Whole run"])
		tile.total:SetText(info.total)
		tile.rate:SetText(info.rate .. " " .. rateName)
		tile.place:SetText(info.place)
		tile.gap:SetText(info.gap or "")
		local color = info.color or LEAD
		tile.gap:SetTextColor(color[1], color[2], color[3])
	end

	local share = window.share
	local runInfo, bossesInfo = report.run, report.bosses
	local mineRun, mineBosses = 0, 0
	for _, player in ipairs(runInfo.players) do if player.mine then mineRun = player.amount end end
	for _, player in ipairs(bossesInfo.players) do if player.mine then mineBosses = player.amount end end
	local fraction = mineRun > 0 and math.min(1, mineBosses / mineRun) or 0
	local width = WIDTH - PAD * 2
	share.label:SetText(report.healing and L["Where your healing came from"] or L["Where your damage came from"])
	share.legend:SetText(L["Bosses %d%%   Not bosses %d%%"]:format(math.floor(fraction * 100 + 0.5),
		100 - math.floor(fraction * 100 + 0.5)))
	share.bosses:SetShown(fraction > 0)
	share.bosses:SetWidth(math.max(1, width * fraction))
	share.rest:SetShown(fraction < 1)
	share.rest:SetWidth(math.max(1, width * (1 - fraction)))

	local grid = window.grid
	local heads = { L["Encounter"], L["Time"], L["Yours"], rateName, L["Place"], L["Gap"] }
	for c, head in ipairs(grid.heads) do head:SetText(heads[c]) end
	local y, used = -22, 0
	local function Place(scope)
		used = used + 1
		local row = grid.rows[used] or NewRow()
		grid.rows[used] = row
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, y)
		FillRow(row, scope)
		y = y - ROW
	end
	for _, scope in ipairs(report.bossScopes) do Place(scope) end
	y = y - 6 -- (a gap before the totals)
	for _, scope in ipairs(report.sums) do Place(scope) end
	for i = used + 1, #grid.rows do grid.rows[i]:Hide() end
	grid.hint:ClearAllPoints()
	grid.hint:SetPoint("TOPLEFT", 6, y - 6)
	local tableHeight = -y + 24
	grid:SetHeight(tableHeight)

	local partyHeight = DrawParty(picked)
	window:SetHeight(TABLE_TOP + math.max(tableHeight, partyHeight) + PAD)
end

-- Opening and closing ---------------------------------------------------------

-- made: true for the made-up report; "test" for the meter's if it has a
-- boss, else the made-up one (its bosses, to see a row per boss).
function ns.ShowDamageReport(made)
	if not window then Create() end
	sample = made == true
	report = Read()
	if made == "test" and not (report.bossScopes and #report.bossScopes > 0) then
		sample = true
		report = Read()
	end
	picked = nil
	Draw()
	window:Show()
end

function ns.HideDamageReport()
	if window then window:Hide() end
end

function ns.ToggleDamageReport(made)
	if window and window:IsShown() then window:Hide() else ns.ShowDamageReport(made) end
end

-- (Up while it waits for a fight or key to end, or the meter changes: read again.)
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED", "DAMAGE_METER_RESET" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function()
	if not (window and window:IsShown()) or sample then return end
	C_Timer.After(0.5, function()
		if window:IsShown() and not InCombatLockdown() then
			report = Read()
			picked = nil
			Draw()
		end
	end)
end)
