-- Cinematic: the Cooldown Manager page's situations. Default is the page's
-- settings as they always were; each situation is a numbered row of its own
-- with a Where (places) and a Combat (any, in a fight, out of one), and its
-- own spell, buff and group settings: only those it changes. The rows are
-- looked at in their order and the first that fits now is used (Default
-- when none does); a spell or group it doesn't set goes by Default's.
-- A place and combat (a spot) belongs to one row at most: taken by a row
-- above, it's greyed in the rows below, and taking it higher up (a tick, a
-- move up) takes it off the row that had it. So no two rows ever fit at once.
-- (Frames.lua's ns.CooldownSpellMode and the rest ask the one in use,
-- ns.cooldownSitNow; the page's table is built here too, ns.BuildCooldownSituations.)
local _, ns = ...
local L = ns.L

-- The settings a situation keeps, as Default keeps them (Core's EnsureTables).
-- (No Close the gaps: where the icons sit is the bar's, the same in each.)
local SET_KEYS = { "cooldownReadyOnly", "cooldownReadyEarly", "cooldownEarlyOn", "cooldownRechargeOnly",
	"cooldownNeedsPower", "cooldownReadyAnyTime", "cooldownProcOnly", "cooldownAlwaysShow", "cooldownGroupDefaults", "cooldownBuffMode",
	"cooldownFlashReady" }
ns.COOLDOWN_SIT_KEYS = SET_KEYS

-- The places, each moment in exactly one (Spot below), and the combats.
local PLACES = {
	{ "world", L["Open world"] }, { "city", L["Cities"] }, { "inn", L["Inns"] }, { "dungeon", L["Dungeons"] },
	{ "raid", L["Raids"] }, { "bg", L["BGs & arenas"] },
}
local PLACE_NAME = {}
for _, place in ipairs(PLACES) do PLACE_NAME[place[1]] = place[2] end
local COMBATS = { { "any", L["Any"] }, { "in", L["In combat"] }, { "out", L["Out of combat"] } }
local COMBAT_NAME = {}
for _, combat in ipairs(COMBATS) do COMBAT_NAME[combat[1]] = combat[2] end

local function DeepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = DeepCopy(v) end
	return copy
end

-- The situations, in their order (db.cooldownSituations: each { name,
-- places = { place -> true }, combat = "any", "in" or "out", set = {
-- SET_KEYS -> table } }), each's tables made as asked for (from a profile or
-- an import: any missing).
function ns.CooldownSituations()
	local db = ns.db
	if type(db.cooldownSituations) ~= "table" then db.cooldownSituations = {} end
	local list = db.cooldownSituations
	for i = #list, 1, -1 do
		if type(list[i]) ~= "table" then table.remove(list, i) end
	end
	for _, sit in ipairs(list) do
		if type(sit.places) ~= "table" then
			-- (A test build's When ticks: its places, and In or Out of combat.)
			local when = type(sit.when) == "table" and sit.when or {}
			sit.places = {}
			for place in pairs(PLACE_NAME) do
				if when[place] then sit.places[place] = true end
			end
			sit.combat = when.combat and not when.nocombat and "in" or when.nocombat and not when.combat and "out"
				or "any"
			sit.when, sit.rule = nil, nil
		end
		if not COMBAT_NAME[sit.combat] then sit.combat = "any" end
		if type(sit.set) ~= "table" then sit.set = {} end
		for _, key in ipairs(SET_KEYS) do
			if type(sit.set[key]) ~= "table" then sit.set[key] = {} end
		end
		if type(sit.name) ~= "string" then sit.name = L["Situation"] end
	end
	return list
end

-- Where you are now (one of PLACES) and whether it's a fight (the Calm
-- Timer after one too, as everywhere since 2026-11-10), from the rules' facts.
local function Spot(facts)
	local place = facts.bg and "bg" or facts.dungeon and "dungeon" or facts.raid and "raid"
		or facts.city and "city" or facts.inn and "inn" or "world"
	return place, not facts.nocombat
end

-- Whether a situation fits now: in one of its places, in its combat.
function ns.CooldownSitFits(sit, facts)
	local place, fight = Spot(facts)
	if not sit.places[place] then return false end
	return sit.combat == "any" or (sit.combat == "in") == fight
end

-- The situation in use now, or nil for Default: the first that fits.
function ns.CooldownSituationNow(facts)
	local list = ns.db and ns.db.cooldownSituations
	if type(list) ~= "table" or not list[1] then return nil end
	facts = facts or ns.RuleFactsNow()
	for _, sit in ipairs(ns.CooldownSituations()) do
		if ns.CooldownSitFits(sit, facts) then return sit end
	end
	return nil
end

-- Worked out again (each pass of the ready check, Frames.lua): ns.cooldownSitNow
-- the situation in use, or nil. Gives whether it changed.
function ns.UpdateCooldownSituation()
	local now = ns.CooldownSituationNow()
	local changed = now ~= ns.cooldownSitNow
	ns.cooldownSitNow = now
	return changed
end

-- Two combats share a spot: Any shares with both.
local function Overlap(a, b) return a == "any" or b == "any" or a == b end
-- The row above index i that has place in a combat sharing combat's, or nil.
function ns.CooldownSitOwner(i, place, combat)
	local list = ns.CooldownSituations()
	for j = 1, i - 1 do
		if list[j].places[place] and Overlap(list[j].combat, combat) then return j end
	end
end
-- Takes off each row the places a row above has: gives what moved, as text
-- ("" for nothing).
function ns.CooldownSitSweep()
	local list, moved = ns.CooldownSituations(), {}
	for i, sit in ipairs(list) do
		for _, place in ipairs(PLACES) do
			local owner = sit.places[place[1]] and ns.CooldownSitOwner(i, place[1], sit.combat)
			if owner then
				sit.places[place[1]] = nil
				moved[#moved + 1] = (L["%s (%s) left row %d, %s: row %d, %s, has it now."]):format(place[2],
					COMBAT_NAME[sit.combat], i, sit.name, owner, list[owner].name)
			end
		end
	end
	return table.concat(moved, " ")
end

-- What a situation sets itself, else nil (Default's then). Each gives where
-- it came from too: "spell" (set for it) or "group" (its group's, set here).
-- (Set under what it's turned into, from before settings went by the base,
-- or its base: as Default's, ns.CooldownSpellMode.)
local function OwnKey(set, id)
	if set.cooldownReadyOnly[id] or set.cooldownRechargeOnly[id] or set.cooldownProcOnly[id]
		or set.cooldownAlwaysShow[id] then
		return id
	end
	return ns.BaseSpell(id)
end

-- A spell's mode, and for "ready" its Resources, Show early on, seconds and Out of fights.
function ns.CooldownSitSpellMode(sit, id, group)
	local set = sit.set
	local key = OwnKey(set, id)
	if set.cooldownReadyOnly[key] then
		return "ready", "spell", set.cooldownNeedsPower[key], set.cooldownEarlyOn[key], set.cooldownReadyEarly[key],
			set.cooldownReadyAnyTime[key]
	elseif set.cooldownRechargeOnly[key] then
		return "recharge", "spell"
	elseif set.cooldownProcOnly[key] then
		return "proc", "spell"
	elseif set.cooldownAlwaysShow[key] then
		return "always", "spell"
	end
	local own = set.cooldownGroupDefaults[group or "other"]
	if own and own.mode then
		return own.mode, "group", own.power, true, own.early, own.anyTime
	end
end

-- A group's mode, Resources, Show early seconds and Out of fights set here (mode nil: not set).
function ns.CooldownSitGroup(sit, group)
	local own = sit.set.cooldownGroupDefaults[group or "other"]
	if own then return own.mode, own.power, own.early, own.anyTime end
end

-- A tracked buff's or bar's mode.
function ns.CooldownSitBuffMode(sit, id, group)
	local set = sit.set
	local own = set.cooldownBuffMode[id] or set.cooldownBuffMode[ns.BaseSpell(id)]
	if own then return own, "spell" end
	local mode = ns.CooldownSitGroup(sit, group or "buffs")
	if mode then return mode, "group" end
end

-- A group's Flash (true or false), set here.
function ns.CooldownSitGroupFlash(sit, group)
	local own = sit.set.cooldownGroupDefaults[group or "other"]
	if own and own.flash ~= nil then return own.flash end
end

-- A spell's Flash (true or false): its own, else its group's, set here.
function ns.CooldownSitSpellFlash(sit, id, group)
	local own = sit.set.cooldownFlashReady
	local value = own[id]
	if value == nil then value = own[ns.BaseSpell(id)] end
	if value ~= nil then return value end
	return ns.CooldownSitGroupFlash(sit, group)
end

-- A new situation after the one at index (nil: at the end), copying from
-- (a situation, or nil for Default) its settings and its Combat, but no
-- places: those stay its source's. Gives it.
function ns.CopyCooldownSituation(from, index)
	local list = ns.CooldownSituations()
	local sit = { places = {}, set = {}, combat = from and from.combat or "any" }
	if from then
		sit.name = (L["Copy of %s"]):format(from.name)
		sit.set = DeepCopy(from.set)
	else
		sit.name = (L["Copy of %s"]):format(L["Default"])
		for _, key in ipairs(SET_KEYS) do sit.set[key] = DeepCopy(ns.db[key] or {}) end
	end
	table.insert(list, index and index + 1 or #list + 1, sit)
	ns.CooldownSituations() -- (its tables made)
	if ns.readyPace then ns.readyPace.due = true end
	return sit
end

-- A new situation at the end that sets nothing (all Default's to start
-- with), Any, no places. Gives it.
function ns.NewCooldownSituation()
	local list = ns.CooldownSituations()
	local sit = { name = L["New situation"], places = {}, combat = "any", set = {} }
	list[#list + 1] = sit
	ns.CooldownSituations() -- (its tables made)
	return sit
end

-- A row's places as text: "Dungeons, Raids", or nil with none.
local function PlacesText(sit)
	local names = {}
	for _, place in ipairs(PLACES) do
		if sit.places[place[1]] then names[#names + 1] = place[2] end
	end
	return #names > 0 and table.concat(names, ", ") or nil
end

-- /cine debug cooldowns' first lines: where you are, each situation, and the one in use.
function ns.ReportCooldownSituations()
	local list = ns.db and ns.db.cooldownSituations
	if type(list) ~= "table" or not list[1] then
		ns.Print("cooldown situations: none (Default's settings)")
		return
	end
	local facts = ns.RuleFactsNow()
	local place, fight = Spot(facts)
	ns.Print(("cooldown situations: you're in %s, %s"):format(place, fight and "in a fight" or "out of fights"))
	local using = ns.CooldownSituationNow(facts)
	for i, sit in ipairs(ns.CooldownSituations()) do
		local count = 0
		for _, key in ipairs(SET_KEYS) do
			for _ in pairs(sit.set[key]) do count = count + 1 end
		end
		print(("  %d. %s: %s, %s -> %s, %d settings of its own%s"):format(i, sit.name, PlacesText(sit) or "nowhere",
			sit.combat, ns.CooldownSitFits(sit, facts) and "fits" or "doesn't fit", count,
			sit == using and " [IN USE]" or ""))
	end
	print(("  in use: %s (the ready check's: %s)"):format(using and using.name or "Default",
		ns.cooldownSitNow and ns.cooldownSitNow.name or "Default"))
end

-- ---------------------------------------------------------------------------
-- The page's part: the numbered rows (as the Nameplates style page's), each
-- with its move arrows, name, a Show in row's Combat and Location
-- dropdowns (GridRows.lua), Copy and delete; Default last; a note of places that moved;
-- Add row. A row is picked by clicking it (or using its name or menus): the
-- spell tabs below show the picked one's settings. opts: { width,
-- Changed() after a pick or a change (the page lists its spells again),
-- Tooltip(frame, text), Enabled() whether the page's switch is on }. Gives
-- the block (its Refresh, and View(): the situation the spell grid shows,
-- nil for Default).

local MODE_TEXT = {
	always = L["Always"], ready = L["When ready"], recharge = L["While recharging"], proc = L["When it procs"],
	combat = L["In combat"], quiet = L["Out of combat"], hidden = L["Hidden"],
}
ns.COOLDOWN_MODE_TEXT = MODE_TEXT

StaticPopupDialogs["CINEMATIC_COOLDOWN_SIT_DELETE"] = {
	text = "%s",
	button1 = YES, button2 = NO,
	OnAccept = function(_, data) data.Delete() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function ns.BuildCooldownSituations(parent, opts)
	local WIDTH = opts.width or 610
	local ROW_H = 28
	local LAYOUT = ns.GRID_PLACE_COMBAT_LAYOUT -- (a Show in row's Combat and Location, as Nearby Dots')
	-- Columns: number and arrows, name and In use, the Show in row's two
	-- dropdowns, Copy, delete.
	local NAME_X, NAME_W, IN_USE_X = 40, 118, 162
	local GRID_X = 212
	local COPY_X = GRID_X + ns.GridWidth(LAYOUT) + 8
	local COPY_W = 56
	local DELETE_X = COPY_X + COPY_W + 4
	local block = CreateFrame("Frame", nil, parent)
	block:SetSize(WIDTH, 1)
	local view -- (the situation the grid shows; nil: Default)
	local note = "" -- (places that moved with the last change)

	local function List() return ns.CooldownSituations() end
	local function IndexOf(sit)
		for i, each in ipairs(List()) do
			if each == sit then return i end
		end
	end
	-- (A profile loaded or a Reset: the one picked may be gone.)
	function block.View()
		if view and not IndexOf(view) then view = nil end
		return view
	end

	local Layout
	-- After a change to the rows: what a row above has taken off those below,
	-- the ready check asked again, and the page's spells listed again.
	local function Changed(noSweep)
		if not noSweep then note = ns.CooldownSitSweep() end
		if ns.readyPace then ns.readyPace.due = true end
		Layout()
		opts.Changed()
	end

	local heading = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
	heading:SetText(L["Situations"])
	local intro = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
	intro:SetWidth(WIDTH)
	intro:SetJustifyH("LEFT")
	intro:SetText(L["Different spell settings for different places: in a dungeon out of combat, say. A row is used " ..
		"while you're in one of its places, in its combat; Default when none fits. Each place and combat belongs " ..
		"to one row at most, so a spot a row above has is greyed in the rows below. Click a row to show its settings " ..
		"in the tabs below: it changes just what you set there, and the rest follows Default."])

	-- The Show in rows' look (GridRows.lua): the page's helpers, with the
	-- row's changes going through Changed here (the page refreshed there).
	local kit = setmetatable({ Refresh = function() end }, { __index = ns.GRID_KIT })
	local columnTop = CreateFrame("Frame", nil, block)
	columnTop:SetSize(1, 1)
	local gridHeadings = ns.GridHeadings(kit, block, columnTop, GRID_X, LAYOUT)
	local headings = {}
	local function Heading(text, x)
		local label = block:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetText(text)
		headings[#headings + 1] = { label, x }
	end
	Heading("#", 4)
	Heading(L["Name"], NAME_X)

	local function Tip(frame, text)
		if text then opts.Tooltip(frame, text) end
	end

	-- The rows, made as needed: row.sit what it's for (set on each Layout).
	local rows = {}
	-- (A row picked: its settings in the tabs below.)
	local function Select(row)
		if view == row.sit then return end
		view = row.sit
		Changed(true)
	end
	local function MoveButton(row, by)
		local button = CreateFrame("Button", nil, row)
		button:SetSize(14, 14)
		button:SetPoint("LEFT", row, "LEFT", 20, by < 0 and 6 or -6)
		local art = by < 0 and "Interface\\Buttons\\Arrow-Up-" or "Interface\\Buttons\\Arrow-Down-"
		button:SetNormalTexture(art .. "Up")
		button:SetPushedTexture(art .. "Down")
		button:HookScript("OnDisable", function(self) self:SetAlpha(0.3) end)
		button:HookScript("OnEnable", function(self) self:SetAlpha(1) end)
		button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		Tip(button, by < 0 and L["Move this row up: it's looked at sooner, and takes any spot it shares with the " ..
			"row above."] or L["Moves this row down so it's checked later."])
		button:SetScript("OnClick", function()
			local list, i = List(), IndexOf(row.sit)
			local j = i and i + by
			if not j or j < 1 or j > #list then return end
			list[i], list[j] = list[j], list[i]
			Changed()
		end)
		return button
	end

	-- The place or combat a row above has that sharing combat would clash
	-- with: the first of the row's places (as text) and that row's number.
	local function Blocked(sit, combat)
		local index = IndexOf(sit) or 1
		for _, place in ipairs(PLACES) do
			if sit.places[place[1]] then
				local owner = ns.CooldownSitOwner(index, place[1], combat)
				if owner then return place[2], owner end
			end
		end
	end
	-- The Show in row's dropdowns' entries ({ name, isOn(), toggle(),
	-- usable(), tip }), for the row's situation (row.sit, as laid out):
	-- Combat's In combat and Out of combat (both ticked: Any; the last one
	-- stays), Location's places. One a row above has is greyed, named so.
	local function Entries(row)
		local combat = {}
		for _, which in ipairs({ { "in", "out" }, { "out", "in" } }) do
			local mine, other = which[1], which[2]
			combat[#combat + 1] = {
				COMBAT_NAME[mine],
				function() return row.sit ~= nil and row.sit.combat ~= other end,
				function()
					local sit = row.sit
					if not sit then return end
					if sit.combat == "any" then
						sit.combat = other
					elseif sit.combat == other then
						sit.combat = "any"
					end
				end,
				function()
					local sit = row.sit
					return sit ~= nil and (sit.combat ~= other or not Blocked(sit, mine))
				end,
			}
		end
		local places = {}
		for _, place in ipairs(PLACES) do
			local key = place[1]
			places[#places + 1] = {
				place[2],
				function() return row.sit ~= nil and row.sit.places[key] and true or false end,
				function()
					local sit = row.sit
					if sit then sit.places[key] = not sit.places[key] or nil end
				end,
				function()
					local sit = row.sit
					return sit ~= nil and (sit.places[key] or not ns.CooldownSitOwner(IndexOf(sit) or 1, key, sit.combat))
						and true or false
				end,
			}
		end
		return { [ns.GRID_COMBAT] = combat, [ns.GRID_LOCATION] = places }
	end
	-- (Each layout: the greyed ones' names say whose they are.)
	local function NameEntries(row)
		local sit = row.sit
		if not sit then return end
		local index = IndexOf(sit) or 1
		for i, place in ipairs(PLACES) do
			local owner = not sit.places[place[1]] and ns.CooldownSitOwner(index, place[1], sit.combat)
			local entry = row.menus[ns.GRID_LOCATION][i]
			entry[1] = owner and (L["%s (row %d has it)"]):format(place[2], owner) or place[2]
			entry[5] = owner and (L["Row %d, %s, has it. Move this row above it to take it."]):format(owner,
				List()[owner].name) or nil
		end
		for i, which in ipairs({ { "in", "out" }, { "out", "in" } }) do
			local entry = row.menus[ns.GRID_COMBAT][i]
			local placeName, owner = nil, nil
			if sit.combat == which[2] then placeName, owner = Blocked(sit, which[1]) end
			entry[1] = owner and (L["%s (%s: row %d has it)"]):format(COMBAT_NAME[which[1]], placeName, owner)
				or COMBAT_NAME[which[1]]
			entry[5] = owner and (L["Row %d, %s, has %s %s."]):format(owner, List()[owner].name, placeName,
				COMBAT_NAME[which[1]]:lower()) or nil
		end
	end

	local function Row(n)
		local row = rows[n]
		if row then return row end
		row = CreateFrame("Frame", nil, block)
		row:SetSize(WIDTH, ROW_H)
		row.back = row:CreateTexture(nil, "BACKGROUND")
		row.back:SetAllPoints()
		-- (The picked row: lit gold, with gold edges and a bar at its left.)
		row.edges = {}
		for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
			{ "TOPLEFT", "BOTTOMLEFT", 3, 0 } }) do
			local line = row:CreateTexture(nil, "BORDER")
			line:SetColorTexture(1, 0.82, 0, 0.9)
			line:SetPoint(edge[1])
			line:SetPoint(edge[2])
			if edge[3] > 0 then line:SetWidth(edge[3]) else line:SetHeight(edge[4]) end
			row.edges[#row.edges + 1] = line
		end
		-- (The row in use where you are now: "In use" in green after its name.)
		row.inUse = row:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
		row.inUse:SetPoint("LEFT", row, "LEFT", IN_USE_X, 0)
		row.inUse:SetText(L["In use"])
		-- (Clicked anywhere not on a control: picked. Lit faintly under the mouse.)
		row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
		row.hover:SetAllPoints()
		row.hover:SetColorTexture(1, 1, 1, 0.06)
		row.hover:Hide()
		row:EnableMouse(true)
		row:SetScript("OnMouseDown", function(self) Select(self) end)
		row:SetScript("OnEnter", function(self)
			self.hover:Show()
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:SetText(L["Click to show this row's settings in the tabs below."], 1, 1, 1, 1, true)
			if self.inUse:IsShown() then
				GameTooltip:AddLine(L["In use: where you are now, this row's settings are the ones that count."],
					0.4, 1, 0.4, true)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function(self)
			self.hover:Hide()
			GameTooltip:Hide()
		end)
		row.number = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.number:SetPoint("LEFT", row, "LEFT", 4, 0)
		row.up, row.down = MoveButton(row, -1), MoveButton(row, 1)

		local name = ns.SkinEditBox(CreateFrame("EditBox", nil, row, "InputBoxTemplate"))
		name:SetSize(NAME_W, 20)
		name:SetAutoFocus(false)
		name:SetMaxLetters(40)
		name:SetPoint("LEFT", row, "LEFT", NAME_X + 6, 0)
		local function SaveName(self)
			self:ClearFocus()
			local text = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
			if row.sit and text ~= "" then row.sit.name = text end
			Changed(true)
		end
		name:SetScript("OnEnterPressed", SaveName)
		name:SetScript("OnEditFocusLost", function(self)
			if self.saving then return end
			self.saving = true
			SaveName(self)
			self.saving = nil
		end)
		name:SetScript("OnEditFocusGained", function() Select(row) end)
		name:SetScript("OnEscapePressed", function(self)
			if row.sit then self:SetText(row.sit.name) end
			self:ClearFocus()
		end)
		row.name = name

		-- Combat and Location: a Show in row's (ns.GridRow), its dropdowns
		-- picking the row too.
		row.menus = Entries(row)
		row.grid = ns.GridRow(kit, row, GRID_X, LAYOUT, {
			menus = row.menus,
			help = {
				[ns.GRID_COMBAT] = L["Used in a fight (the Calm Timer after one too), out of one, or both ticked: " ..
					"either."],
				[ns.GRID_LOCATION] = L["Used while you're in any of these places."],
			},
			enabled = function() return not opts.Enabled or opts.Enabled() end,
			changed = function() Changed() end,
		})
		row.grid:SetPoint("LEFT", row, "LEFT", GRID_X, 0)
		for _, child in ipairs({ row.grid:GetChildren() }) do
			if child.GetObjectType and child:GetObjectType() == "Button" then
				child:HookScript("OnClick", function() Select(row) end)
			end
		end

		-- Copy: a new row just under this one with its spell settings and
		-- Combat, no places (they stay this row's).
		row.copy = ns.PanelButton(row)
		row.copy:SetSize(COPY_W, 20)
		row.copy:SetPoint("LEFT", row, "LEFT", COPY_X, 0)
		row.copy:SetText(L["Copy"])
		row.copy.searchSkip = true
		Tip(row.copy, L["Adds a copy of this row below it, with no places picked yet."])
		row.copy:SetScript("OnClick", function()
			local from = row.sit
			view = ns.CopyCooldownSituation(from, from and IndexOf(from) or nil)
			note = L["The copy has no places yet: pick where it's used."]
			Changed(true)
		end)

		row.delete = CreateFrame("Button", nil, row, "UIPanelCloseButton")
		row.delete:SetSize(22, 22)
		row.delete:SetPoint("LEFT", row, "LEFT", DELETE_X, 0)
		Tip(row.delete, L["Deletes this row."])
		row.delete:SetScript("OnClick", function()
			local sit = row.sit
			if not sit then return end
			StaticPopup_Show("CINEMATIC_COOLDOWN_SIT_DELETE", (L["Delete the situation %s?"]):format(sit.name), nil, {
				Delete = function()
					local i = IndexOf(sit)
					if i then table.remove(List(), i) end
					if view == sit then view = nil end
					Changed(true)
				end })
		end)

		-- (Default's row: its own label in place of the name and dropdowns.)
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.label:SetPoint("LEFT", row, "LEFT", NAME_X + 6, 0)
		row.label:SetText(L["Default"])
		row.everywhere = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.everywhere:SetPoint("LEFT", row, "LEFT", GRID_X + 6, 0)
		row.everywhere:SetText(L["Everywhere else"])
		rows[n] = row
		return row
	end

	local noteText = block:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	noteText:SetWidth(WIDTH)
	noteText:SetJustifyH("LEFT")
	noteText:SetTextColor(1, 0.82, 0)
	local add = ns.PanelButton(block)
	add:SetHeight(22)
	add.searchSkip = true
	add:SetText("+ " .. L["Add row"])
	add:SetWidth((add:GetFontString() and add:GetFontString():GetStringWidth() or 80) + 24)
	Tip(add, L["Adds an empty row at the bottom; pick where it's used."])
	add:SetScript("OnClick", function()
		view = ns.NewCooldownSituation()
		note = ""
		Changed(true)
	end)

	function Layout()
		local list = List()
		local picked = block.View()
		local using = ns.CooldownSituationNow()
		local enabled = not opts.Enabled or opts.Enabled()
		local y = -(heading:GetStringHeight() + 4 + intro:GetStringHeight() + 8)
		columnTop:ClearAllPoints()
		columnTop:SetPoint("TOPLEFT", block, "TOPLEFT", 0, y)
		local headingHeight = kit.headingHeight or 24
		for _, each in ipairs(headings) do
			each[1]:ClearAllPoints()
			each[1]:SetPoint("BOTTOMLEFT", block, "TOPLEFT", each[2], y - headingHeight)
		end
		for _, each in ipairs(gridHeadings) do each:SetShown(true) end
		y = y - headingHeight - 4
		local function Place(row, sit, i)
			row.sit = sit
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", block, "TOPLEFT", 0, y)
			row:Show()
			local isDefault = sit == nil
			local inUse = sit == using
			-- (The picked row lit gold; the one in use says so after its name.)
			local isPicked = sit == picked
			row.back:SetColorTexture(1, 0.82, 0, isPicked and 0.22 or 0)
			for _, line in ipairs(row.edges) do line:SetShown(isPicked) end
			row.inUse:SetShown(inUse)
			row.number:SetText(isDefault and "" or tostring(i))
			row.up:SetShown(not isDefault)
			row.down:SetShown(not isDefault)
			row.name:SetShown(not isDefault)
			row.grid:SetShown(not isDefault)
			row.delete:SetShown(not isDefault)
			row.label:SetShown(isDefault)
			row.everywhere:SetShown(isDefault)
			if not isDefault then
				row.up:SetEnabled(enabled and i > 1)
				row.down:SetEnabled(enabled and i < #list)
				if not row.name:HasFocus() then row.name:SetText(sit.name) end
				row.name:SetEnabled(enabled)
				NameEntries(row)
				row.grid:Refresh()
				row.delete:SetEnabled(enabled)
			end
			row.copy:SetEnabled(enabled)
			y = y - ROW_H - 2
		end
		for i, sit in ipairs(list) do Place(Row(i), sit, i) end
		Place(Row(#list + 1), nil, nil)
		for i = #list + 2, #rows do
			rows[i].sit = nil
			rows[i]:Hide()
		end
		noteText:ClearAllPoints()
		if note ~= "" then
			noteText:SetPoint("TOPLEFT", block, "TOPLEFT", 4, y - 2)
			noteText:SetText(note)
			noteText:Show()
			y = y - noteText:GetStringHeight() - 6
		else
			noteText:Hide()
		end
		add:ClearAllPoints()
		add:SetPoint("TOPLEFT", block, "TOPLEFT", 0, y - 4)
		add:SetEnabled(enabled)
		y = y - 4 - 22
		block:SetHeight(-y)
	end
	block.Refresh = function() Layout() end

	-- (The row in use kept up while it's open, as you move about.)
	local since = 0
	ns.SetOnUpdate(block, function(_, elapsed)
		since = since + elapsed
		if since < 0.5 then return end
		since = 0
		for _, row in ipairs(rows) do
			if row.name:HasFocus() then return end
		end
		Layout()
	end)
	block:SetScript("OnShow", function()
		note = ""
		ns.CooldownSitSweep() -- (from a profile or an import: no two rows sharing a spot)
		Layout()
	end)
	return block
end
