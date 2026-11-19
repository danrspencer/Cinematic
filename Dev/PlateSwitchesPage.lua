-- The dev copy's Plate Switches page (the Dev hub): which kinds of nameplates
-- the game builds, now and in each place, and what turns each on (2026-11-19:
-- Heal Vision and Emote Vision's Buff card found no plates in CineMode, and
-- nothing showed why). One row per kind, live:
--   Now               the game's settings now, the sets of ours holding
--                     them (ns.cvarSets), and how many of its plates are up
--   Outside CineMode  your own settings (CineMode's put away while it's on)
--   one per place     CineMode there, worked out from the code's own rules:
--                     Effects.lua's PlatesForcedHere, FORCED_PLATE_CVARS and
--                     FriendWants (rows, group, target, Emote Vision's cards,
--                     Heal Vision), and the offscreen tick
-- A cell's mouseover: every reason. Only in CinematicDev.toc.
local _, ns = ...

local REFRESH = 0.5
local ROW_H = 18
local ON, OFF, SOME, YOURS, GREY = "|cff40ff40", "|cffff5050", "|cffffcc33", "|cff66ccff", "|cff888888"

-- The places as the plate code names them (PlateSuffix: nil = the open world).
local PLACES = {
	{ label = "Open world", suffix = nil, list = "worldShow" },
	{ label = "Cities", suffix = "Cities", list = "cityShow" },
	{ label = "PvP zones", suffix = "PvP", list = "worldShow" },
	{ label = "Battlegrounds", suffix = "BGs", list = "bgShow" },
	{ label = "Dungeons, raids", suffix = "Instances", list = "instanceShow" },
}

-- The kinds: their game settings (any on = on; invert: on at "0"), the plate
-- kinds counted as up (Effects.lua's PlateKind), and how CineMode treats them.
local KINDS = {
	{ label = "Enemy players", cvars = { "nameplateShowEnemies", "nameplateShowEnemyPlayers" }, up = { Enemies = true },
		how = "forced" },
	{ label = "Enemy + neutral NPCs", cvars = { "nameplateShowEnemies" }, up = { EnemyNPCs = true, NeutralNPCs = true },
		how = "forced" },
	{ label = "Critters, minor mobs", cvars = { "nameplateShowEnemyMinus" }, up = { EnemyMinor = true, NeutralMinor = true },
		how = "forced" },
	{ label = "Enemy pets, totems", cvars = { "nameplateShowEnemyMinions", "nameplateShowEnemyPets",
		"nameplateShowEnemyGuardians", "nameplateShowEnemyTotems" }, up = { EnemyMinions = true }, how = "forced" },
	{ label = "Friendly NPCs", cvars = { "nameplateShowFriendlyNPCs" }, up = { FriendlyNPCs = true }, how = "forced" },
	{ label = "Friendly players", cvars = { "nameplateShowFriends", "nameplateShowFriendlyPlayers" },
		up = { Friends = true }, how = "players" },
	{ label = "  their health bars", cvars = { "nameplateShowOnlyNameForFriendlyPlayerUnits" }, invert = true,
		how = "bars", tip = "Off: friendly players' plates are names only." },
	{ label = "Friendly pets, totems", cvars = { "nameplateShowFriendlyMinions", "nameplateShowFriendlyPets",
		"nameplateShowFriendlyGuardians", "nameplateShowFriendlyTotems", "nameplateShowFriendlyPlayerMinions",
		"nameplateShowFriendlyPlayerPets", "nameplateShowFriendlyPlayerGuardians", "nameplateShowFriendlyPlayerTotems" },
		up = { FriendlyMinions = true }, how = "minions" },
	{ label = "Offscreen plates", cvars = { "nameplateShowOffscreen" }, how = "offscreen",
		tip = "On: units out of view keep their plate (pinned to the edge). Off: no plate, so no unit for anyone out of view." },
	{ label = "All plates switch", cvars = { "nameplateShowAll" }, how = "forced",
		tip = "The game's master switch for plates (Shift+V's)." },
}

-- A kind's settings on this client, and whether they're on.
local function Present(kind)
	local out = {}
	for _, cvar in ipairs(kind.cvars) do
		if GetCVar(cvar) ~= nil then out[#out + 1] = cvar end
	end
	return out
end
local function IsOn(kind, value)
	if value == nil then return nil end
	if kind.invert then return tostring(value) == "0" end
	return tostring(value) == "1"
end
local function State(kind, read)
	local on, off = 0, 0
	for _, cvar in ipairs(Present(kind)) do
		local value = IsOn(kind, read(cvar))
		if value then on = on + 1 elseif value == false then off = off + 1 end
	end
	if on + off == 0 then return GREY .. "n/a", "Not on this client." end
	if off == 0 then return ON .. "on" end
	if on == 0 then return OFF .. "off" end
	return SOME .. ("%d of %d on"):format(on, on + off)
end
-- Your own value: saved while one of ours holds it, else the game's now.
local function Yours(cvar)
	local saved = ns.db and ns.db.savedCVars and ns.db.savedCVars[cvar]
	if saved ~= nil then return saved end
	return GetCVar(cvar)
end

-- Emote Vision's plate cards whose Show row is on at a place (none: nil).
local function EmoteCardsAt(place)
	if not (ns.EmotePlateMoments and ns.Setting("emoteVision") and ns.PageOn and ns.PageOn("emoteVisionPlates")) then
		return nil
	end
	local names = {}
	for _, moment in ipairs(ns.EmotePlateMoments()) do
		if moment.on then
			local rule = ns.db.frameRules and ns.db.frameRules[moment.key]
			if type(rule) == "string" and rule:find("%S") then
				names[#names + 1] = moment.name .. " (by its rule: now " .. tostring(ns.RuleTest(moment.key)) .. ")"
			elseif ns.IsCineShowOn(moment.key) or ns.IsPlaceShowOn(place.list, moment.key) then
				names[#names + 1] = moment.name
			end
		end
	end
	return #names > 0 and table.concat(names, ", ") or nil
end

-- CineMode at a place: the cell's text and every reason.
local function CineCell(kind, place)
	local db = ns.db
	if #Present(kind) == 0 then return GREY .. "n/a", { "Not on this client." } end
	if not db.handlePlates then
		return YOURS .. "yours", { "The Nameplates page is off: CineMode leaves plates to your settings." }
	end
	if kind.how == "offscreen" then
		-- (Effects.lua's OffscreenWhy: here exactly; elsewhere by the same rules.)
		if db.plateShowOffscreen then return ON .. "on", { "Nameplates page's Show Offscreen tick (plateShowOffscreen)." } end
		local off = { "Off: anyone out of view has no plate (no unit for the cards or Heal Vision)." }
		if place.suffix == "Instances" then
			return OFF .. "off", { off[1], "CineMode doesn't hold plates here: only your tick turns it on." }
		end
		local isHere = place.suffix == (ns.PlateSuffix and ns.PlateSuffix())
		local noEnemy = "Not while you target an enemy (a fight's plates stay in view only: plate settings can't "
			.. "change in fights)."
		if isHere then
			local why = ns.plates and ns.plates.OffscreenWhy and ns.plates.OffscreenWhy(true)
			if why then return ON .. "on", { "On for " .. why .. ".", noEnemy } end
			return OFF .. "off", { off[1], noEnemy }
		end
		local cards = EmoteCardsAt(place)
		if cards then return ON .. "on*", { "On for Emote Vision's cards: " .. cards .. ".", noEnemy } end
		if ns.Setting("healVisionPlates") then
			return OFF .. "off*", { off[1], "Only while: Heal Vision's Nameplates tick, where its row's rule says." }
		end
		return OFF .. "off", off
	end
	if place.suffix == "Instances" then
		local why = { "CineMode doesn't hold plates in dungeons and raids (PlatesForcedHere): your settings." }
		if kind.how ~= "forced" then why[2] = "The game locks friendly plates there anyway." end
		return YOURS .. "yours", why
	end
	if kind.how == "forced" then
		return ON .. "on", { "CineMode turns every plate of this kind on here (FORCED_PLATE_CVARS); the Nameplates "
			.. "rows fade them." }
	end
	local p = ns.plates
	local rows = p and p.FRIEND_ROWS
	if not (p and rows and p.FriendRowWanted) then return GREY .. "?", { "Effects.lua's plate code isn't loaded." } end
	local always, only = {}, {}
	-- (Heal Vision's tick goes by its own row's rule: known only where you are.)
	local healTick = ns.Setting("healVisionPlates") and true or false
	local isHere = place.suffix == (ns.PlateSuffix and ns.PlateSuffix())
	local heal = healTick and isHere and ns.HealVisionPlatesOn and ns.HealVisionPlatesOn()
	local healMaybe = healTick and not isHere
	if kind.how == "players" then
		if p.FriendRowWanted(rows.players, true, place.suffix) then always[#always + 1] = "a Friends Nameplates or Names row" end
		local cards = EmoteCardsAt(place)
		if cards then always[#always + 1] = "Emote Vision: " .. cards end
		if heal then always[#always + 1] = "Heal Vision's Nameplates tick" end
		if healMaybe then only[#only + 1] = "Heal Vision's Nameplates tick, where its row's rule says" end
		if p.FriendRowWanted(rows.group, true, place.suffix) then only[#only + 1] = "in a group (Group members rows)" end
		if p.FriendRowWanted(rows.target, true, place.suffix) then only[#only + 1] = "targeting a friendly player" end
	elseif kind.how == "bars" then
		if p.FriendRowWanted(rows.body, false, place.suffix) then
			always[#always + 1] = "a Friends or Group members Nameplates row"
		end
		if heal then always[#always + 1] = "Heal Vision's Nameplates tick" end
		if healMaybe then only[#only + 1] = "Heal Vision's Nameplates tick, where its row's rule says" end
		if p.FriendRowWanted(rows.target, false, place.suffix) then only[#only + 1] = "targeting a friendly player" end
	elseif kind.how == "minions" then
		if p.FriendRowWanted(rows.minions, true, place.suffix) then
			always[#always + 1] = "a friendly pets, group pets or My pet row"
		end
		if heal then always[#always + 1] = "Heal Vision's Nameplates tick" end
		if healMaybe then only[#only + 1] = "Heal Vision's Nameplates tick, where its row's rule says" end
		only[#only + 1] = "targeting a friendly pet, guardian, totem or minion (with a Your target row)"
	end
	only[#only + 1] = "a duel (Duel plates)"
	local why = {}
	for _, text in ipairs(always) do why[#why + 1] = "On: " .. text end
	for _, text in ipairs(only) do why[#why + 1] = "Only while: " .. text end
	if #always > 0 then return ON .. "on", why end
	table.insert(why, 1, kind.how == "minions" and "Otherwise your settings." or "Otherwise off (names only for bars).")
	if kind.how == "minions" then return YOURS .. "yours*", why end
	return OFF .. (#only > 0 and "off*" or "off"), why
end

-- Now: the settings, the sets of ours holding them, the plates up.
local function NowCell(kind, counts)
	local text, note = State(kind, GetCVar)
	local why = { note or "The game's settings now." }
	local holders = {}
	for _, set in ipairs(ns.cvarSets or {}) do
		if set.active then
			for _, cvar in ipairs(kind.cvars) do
				if set.values[cvar] ~= nil then
					holders[#holders + 1] = ("%s (%s = %s)"):format(set.label or "?", cvar, tostring(set.values[cvar]))
					break
				end
			end
		end
	end
	why[#why + 1] = #holders > 0 and ("Held by: " .. table.concat(holders, "; ")) or "Held by: nothing of ours (yours)."
	for _, cvar in ipairs(Present(kind)) do why[#why + 1] = ("  %s = %s"):format(cvar, tostring(GetCVar(cvar))) end
	local up = 0
	for name in pairs(kind.up or {}) do up = up + (counts[name] or 0) end
	if kind.up then text = text .. GREY .. (" (%d up)"):format(up) end
	return text, why
end

local function Counts()
	local counts = {}
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken
		local kind = type(unit) == "string" and ns.PlateKind and ns.PlateKind(unit)
		if kind then counts[kind] = (counts[kind] or 0) + 1 end
	end
	return counts
end

function ns.CreatePlateSwitchesPage(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", "Plate Switches")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title, "Which nameplates the game builds, now and in each place in CineMode, "
		.. "and why. No plate = no unit: Heal Vision, Emote Vision's cards and the plate rows can't see that unit. "
		.. "Hover a cell for every reason. * = only at times (hover).")
	local summary = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	summary:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
	summary:SetJustifyH("LEFT")

	local grid = CreateFrame("Frame", nil, content)
	grid:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -8)
	grid:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	grid:SetHeight((#KINDS + 1) * ROW_H + 6)

	local columns = { { "Kind", 0.19 }, { "Now", 0.15 }, { "Outside CineMode", 0.13 } }
	for _, place in ipairs(PLACES) do columns[#columns + 1] = { place.label, 0.106 } end

	local function Cell(parent, index, font)
		local button = CreateFrame("Button", nil, parent)
		button:SetHeight(ROW_H)
		local text = button:CreateFontString(nil, "ARTWORK", font)
		text:SetAllPoints()
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		button.text = text
		button:SetScript("OnEnter", function(self)
			if not self.lines then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.head or "", 1, 0.82, 0)
			for _, line in ipairs(self.lines) do GameTooltip:AddLine(line, 1, 1, 1, true) end
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		button.index = index
		return button
	end
	local function Lay(cells, parent)
		local width = grid:GetWidth() or 0
		local x = 0
		for i, column in ipairs(columns) do
			cells[i]:ClearAllPoints()
			cells[i]:SetPoint("LEFT", parent, "LEFT", x + 2, 0)
			cells[i]:SetWidth(math.max(1, width * column[2] - 4))
			x = x + width * column[2]
		end
	end

	local head = CreateFrame("Frame", nil, grid)
	head:SetPoint("TOPLEFT")
	head:SetPoint("TOPRIGHT")
	head:SetHeight(ROW_H + 4)
	local line = head:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetColorTexture(0.45, 0.38, 0.2, 0.8)
	local heads = {}
	for i, column in ipairs(columns) do
		heads[i] = Cell(head, i, "GameFontNormalSmall")
		heads[i].text:SetText(column[1])
	end

	local rowFrames = {}
	for index, kind in ipairs(KINDS) do
		local row = CreateFrame("Frame", nil, grid)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", 0, -(ROW_H + 6) - (index - 1) * ROW_H)
		row:SetPoint("RIGHT")
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)
		local cells = {}
		for i in ipairs(columns) do cells[i] = Cell(row, i, "GameFontHighlightSmall") end
		cells[1].text:SetText(kind.label)
		cells[1].head, cells[1].lines = kind.label, { kind.tip or "The game's settings: " .. table.concat(kind.cvars, ", ") }
		row.cells, row.kind = cells, kind
		rowFrames[index] = row
	end

	local function Refresh()
		local here = ns.PlateSuffix and ns.PlateSuffix()
		local counts = Counts()
		local wants = ns.plates and ns.plates.friendWants or {}
		summary:SetText(("CineMode %s, here: %s, in a fight %s, in a group %s. Live FriendWants: players %s, bars %s, "
			.. "minions %s, cards %s."):format(ns.lastCinematic and ON .. "on|r" or "off", tostring(here or "open world"),
			InCombatLockdown() and OFF .. "yes|r" or "no", IsInGroup() and "yes" or "no", tostring(wants.shownPlayers),
			tostring(wants.shownBody), tostring(wants.shownMinions), tostring(wants.plateCards)))
		Lay(heads, head)
		for _, row in ipairs(rowFrames) do
			local kind, cells = row.kind, row.cells
			Lay(cells, row)
			local text, why = NowCell(kind, counts)
			cells[2].text:SetText(text)
			cells[2].head, cells[2].lines = kind.label .. ": now", why
			local yours = State(kind, Yours)
			cells[3].text:SetText((kind.how == "offscreen" or #Present(kind) == 0) and yours or (yours .. GREY .. " (yours)"))
			cells[3].head, cells[3].lines = kind.label .. ": outside CineMode",
				{ "Your own settings: CineMode never turns these on outside it (Shift+V and the game's Nameplates options)." }
			for p, place in ipairs(PLACES) do
				local cellText, reasons = CineCell(kind, place)
				local cell = cells[3 + p]
				local isHere = place.suffix == here
				cell.text:SetText(cellText .. (isHere and GREY .. " <" or ""))
				cell.head, cell.lines = kind.label .. ": CineMode, " .. place.label .. (isHere and " (you're here)" or ""),
					reasons
			end
		end
	end

	local since = 0
	ns.SetOnUpdate(canvas, function(_, elapsed)
		since = since + elapsed
		if since < REFRESH then return end
		since = 0
		Refresh()
		kit.FitContentHeight(content)
	end)
	grid:SetScript("OnSizeChanged", function() if canvas:IsShown() then Refresh() end end)
	canvas:SetScript("OnShow", kit.PageShown(Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Plate Switches", "Plate Switches")
end
