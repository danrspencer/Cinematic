-- Cinematic: the Cooldown Manager page's numbered lines (2026-11-20, in place
-- of situations). A spell, a tracked buff or a bar's row can have lines of
-- its own, each "Icon shows X | where": a Combat (any, in a fight, out of
-- one) and a Location (anywhere, or one place), or a CQL rule written in the
-- rule editor (its Edit). They're read top to bottom and the first that fits
-- now decides; none fits: the row's own dropdown, its last line (Everywhere
-- else). A spell's lines come before its own dropdown and its bar's lines.
-- Kept in db.cooldownSpellRules (spell ID ->), cooldownBuffRules (tracked
-- buff's spell ID ->) and cooldownGroupRules (bar ->): a list of
-- { show = mode, combat = "any"|"in"|"out", place = "any"|place } or
-- { show = mode, cql = text }. (Frames.lua's ns.CooldownSpellMode and the
-- rest ask ns.CooldownRuleMode; the lines on the page are built here too,
-- ns.CooldownRuleLines.)
local _, ns = ...
local L = ns.L

-- The places, each moment in exactly one (Spot below), and the combats.
local PLACES = {
	{ "world", L["Open world"] }, { "city", L["Cities"] }, { "inn", L["Inns"] }, { "dungeon", L["Dungeons"] },
	{ "raid", L["Raids"] }, { "bg", L["BGs & arenas"] },
}
local PLACE_NAME = { any = L["Anywhere"] }
for _, place in ipairs(PLACES) do PLACE_NAME[place[1]] = place[2] end
local COMBATS = { { "any", L["Any"] }, { "in", L["In combat"] }, { "out", L["Out of combat"] } }
local COMBAT_NAME = {}
for _, combat in ipairs(COMBATS) do COMBAT_NAME[combat[1]] = combat[2] end
-- (In combat: the Calm Timer after a fight too, as everywhere since 2026-11-10.)
local COMBAT_WORDS = { ["in"] = "(combat or calm)", out = "nocombat" }
ns.COOLDOWN_RULE_PLACES, ns.COOLDOWN_RULE_COMBATS = PLACES, COMBATS

local TABLES = { spell = "cooldownSpellRules", buff = "cooldownBuffRules", group = "cooldownGroupRules" }
ns.COOLDOWN_RULE_TABLES = TABLES

-- A line as it should be (from a profile or an import: bad parts mended), or
-- nil for one that can't be.
local function Mend(rule)
	if type(rule) ~= "table" or type(rule.show) ~= "string" then return nil end
	if type(rule.cql) == "string" then
		rule.combat, rule.place = nil, nil
		return rule
	end
	rule.cql = nil
	if not COMBAT_NAME[rule.combat] then rule.combat = "any" end
	if not PLACE_NAME[rule.place] then rule.place = "any" end
	return rule
end

-- A row's lines (kind "spell", "buff" or "group"; key its spell ID or bar),
-- mended, or nil with none. make: an empty list made for it if it has none.
-- A spell or buff's are kept under its ID, else its base spell's.
function ns.CooldownRules(kind, key, make)
	local db = ns.db
	local name = TABLES[kind]
	if not (db and name) or key == nil then return nil end
	if type(db[name]) ~= "table" then db[name] = {} end
	local all = db[name]
	local list = all[key]
	if list == nil and kind ~= "group" and ns.BaseSpell then
		local base = ns.BaseSpell(key)
		if base ~= key and all[base] ~= nil then key, list = base, all[base] end
	end
	if type(list) ~= "table" then
		list = nil
		all[key] = nil
	end
	if list then
		for i = #list, 1, -1 do
			if not Mend(list[i]) then table.remove(list, i) end
		end
		if not list[1] and not make then
			all[key] = nil
			list = nil
		end
	end
	if not list and make then
		list = {}
		all[key] = list
	end
	return list
end

-- A line's where as a CQL rule: its own, or its dropdowns' ("" for anywhere, any).
function ns.CooldownRuleText(rule)
	if rule.cql then return rule.cql end
	local words = {}
	if rule.place ~= "any" then words[#words + 1] = rule.place end
	if COMBAT_WORDS[rule.combat] then words[#words + 1] = COMBAT_WORDS[rule.combat] end
	return table.concat(words, " and ")
end

-- A rule typed in the editor, put on a line: back in its dropdowns when it's
-- one they can say (a place, a combat, or both), else kept as the line's CQL.
-- Gives false (and why) for one that doesn't read, leaving the line as it was.
local function Squash(text) return (text:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end
function ns.SetCooldownRuleText(rule, text)
	text = text or ""
	if not text:find("%S") then
		rule.cql, rule.combat, rule.place = nil, "any", "any"
		return true
	end
	local _, err = ns.CompileRule(text)
	if err then return false, err end
	local want = Squash(text)
	for _, place in ipairs({ "any", "world", "city", "inn", "dungeon", "raid", "bg" }) do
		for _, combat in ipairs({ "any", "in", "out" }) do
			local probe = { place = place, combat = combat }
			local said = Squash(ns.CooldownRuleText(probe))
			-- (Either way round: "dungeon and nocombat" or "nocombat and dungeon".)
			local swapped = place ~= "any" and COMBAT_WORDS[combat] and Squash(COMBAT_WORDS[combat] .. " and " .. place)
			if said ~= "" and (want == said or want == swapped) then
				rule.cql, rule.combat, rule.place = nil, combat, place
				return true
			end
		end
	end
	rule.cql, rule.combat, rule.place = text, nil, nil
	return true
end

-- Where you are now: one of PLACES, and whether it's a fight (the Calm Timer
-- after one too), from the rules' facts.
local function Spot(facts)
	local place = facts.bg and "bg" or facts.dungeon and "dungeon" or facts.raid and "raid"
		or facts.city and "city" or facts.inn and "inn" or "world"
	return place, not facts.nocombat
end

-- The facts the lines are read against, once per moment (each icon of each
-- bar asks, every pass).
local factsAt, factsNow
function ns.CooldownRuleFacts()
	local now = GetTime()
	if factsAt ~= now or not factsNow then
		factsAt, factsNow = now, ns.RuleFactsNow()
	end
	return factsNow
end
-- (A change on the page, or a test faking a place: read again at once.)
function ns.CooldownRuleFactsStale() factsAt = nil end

-- Whether a line fits now. (A CQL rule that doesn't read never fits.)
function ns.CooldownRuleFits(rule, facts)
	facts = facts or ns.CooldownRuleFacts()
	if rule.cql then
		local test = ns.CompileRule(rule.cql)
		return test ~= nil and test(facts) and true or false
	end
	local place, fight = Spot(facts)
	if rule.place ~= "any" and rule.place ~= place then return false end
	return rule.combat == "any" or (rule.combat == "in") == fight
end

-- The mode of a row's first line that fits now, and its number; nil with
-- none (the row's own dropdown then, or what it follows).
function ns.CooldownRuleMode(kind, key, facts)
	local list = ns.CooldownRules(kind, key)
	if not list then return nil end
	facts = facts or ns.CooldownRuleFacts()
	for i, rule in ipairs(list) do
		if ns.CooldownRuleFits(rule, facts) then return rule.show, i end
	end
	return nil
end

-- Whether any row has lines (the ready check runs while one does).
function ns.CooldownRulesAny()
	local db = ns.db
	for _, name in pairs(TABLES) do
		if type(db[name]) == "table" and next(db[name]) then return true end
	end
	return false
end

-- A line's where as words for people: "Dungeons, In combat", or its rule.
function ns.CooldownRuleWhere(rule)
	if rule.cql then return rule.cql end
	if rule.place == "any" and rule.combat == "any" then return L["Anywhere"] end
	if rule.place == "any" then return COMBAT_NAME[rule.combat] end
	if rule.combat == "any" then return PLACE_NAME[rule.place] end
	return PLACE_NAME[rule.place] .. ", " .. COMBAT_NAME[rule.combat]
end

-- /cine debug cooldowns' first lines: where you are, and each row's lines
-- with the one that fits now.
function ns.ReportCooldownRules()
	local db = ns.db
	local facts = ns.RuleFactsNow()
	local place, fight = Spot(facts)
	ns.Print(("cooldown lines: you're in %s, %s"):format(place, fight and "in a fight" or "out of fights"))
	local any = false
	for kind, name in pairs(TABLES) do
		for key in pairs(type(db[name]) == "table" and db[name] or {}) do
			local list = ns.CooldownRules(kind, key)
			if list then
				any = true
				local _, hit = ns.CooldownRuleMode(kind, key, facts)
				print(("  %s %s:"):format(kind, tostring(key)))
				for i, rule in ipairs(list) do
					print(("    %d. %s | %s%s"):format(i, rule.show, ns.CooldownRuleWhere(rule),
						i == hit and " [FITS]" or ""))
				end
				print(("    %d. own dropdown | everywhere else%s"):format(#list + 1, hit and "" or " [IN USE]"))
			end
		end
	end
	if not any then print("  none: each row's own dropdown") end
end

-- ---------------------------------------------------------------------------
-- The page's part: a row's lines, under its name. ns.CooldownRuleLines(parent,
-- opts) gives a block; block.Set(kind, key, label, modes) and block.Layout()
-- (its height: the lines, then the Everywhere else line's room, where the
-- page puts the row's own dropdown). opts: { Tooltip(frame, text), Enabled(),
-- Changed() after a change (the page lists its spells again) }.
-- Each line: its number, Icon shows, a bar, Combat and Location (or its CQL
-- rule), Edit, move up and down, delete.

ns.COOLDOWN_LINE_H = 26
local LINE_H = ns.COOLDOWN_LINE_H
-- (Icon shows under the row's own dropdown, the page's Icon shows column, so
-- every line's reads down one column; its where to the right, where the
-- Everywhere else line has the row's When ready parts.)
local SHOW_X, SHOW_W, BAR_X = 180, 135, 318
-- (Each number right beside its dropdown, its lit band from there: under the
-- spell's name, 160 px off, they read as loose, 2026-11-20.)
local NUM_R, LIT_X = SHOW_X - 6, SHOW_X - 26
-- (Move up and down stacked in one column, and the delete inside the panel:
-- side by side the arrows were hard to tell apart and pushed the delete past
-- the panel's edge, cut off, in the first game test, 2026-11-20.)
local COMBAT_X, COMBAT_W, PLACE_X, PLACE_W = 326, 94, 424, 96
local EDIT_X, EDIT_W, UP_X, DOWN_X, DELETE_X = 524, 38, 566, 566, 582

-- A dropdown (or, on clients without the modern one, a button stepping through
-- the choices): List() its choices ({ value, text }), Get() the one picked.
local function Pick(parent, width, List, Get, Set)
	local ok, dropdown = ns.MenuDropdown(parent)
	local control
	if ok and dropdown and dropdown.SetupMenu then
		dropdown:SetWidth(width)
		dropdown:SetupMenu(function(_, root)
			for _, choice in ipairs(List()) do
				root:CreateRadio(choice.text, function() return Get() == choice.value end,
					function() Set(choice.value) end)
			end
		end)
		control = dropdown
	else
		control = ns.PanelButton(parent)
		control:SetSize(width, 22)
		control:SetScript("OnClick", function()
			local list, now = List(), Get()
			for i, choice in ipairs(list) do
				if choice.value == now then
					Set(list[i % #list + 1].value)
					return
				end
			end
			if list[1] then Set(list[1].value) end
		end)
	end
	control.searchSkip, control.cdmLinePick = true, true -- (cdmLinePick: for tests)
	function control.Show_()
		if control.GenerateMenu then
			control:GenerateMenu()
		else
			local now = Get()
			for _, choice in ipairs(List()) do
				if choice.value == now then control:SetText(choice.text) end
			end
		end
	end
	return control
end

local COMBAT_LIST, PLACE_LIST = {}, { { value = "any", text = L["Anywhere"] } }
for _, combat in ipairs(COMBATS) do COMBAT_LIST[#COMBAT_LIST + 1] = { value = combat[1], text = combat[2] } end
for _, place in ipairs(PLACES) do PLACE_LIST[#PLACE_LIST + 1] = { value = place[1], text = place[2] } end

-- (Every block made, for the in-game test to read the page: Dev/CdmLinesTest.lua.)
ns.cooldownLineBlocks = setmetatable({}, { __mode = "k" })
function ns.CooldownRuleLines(parent, opts)
	local block = CreateFrame("Frame", nil, parent)
	block:SetSize(DELETE_X + 24, 1)
	ns.cooldownLineBlocks[block] = true
	local kind, key, label, modes
	local lines = {}

	local function List() return ns.CooldownRules(kind, key) or {} end
	local function Tip(frame, text) if text and opts.Tooltip then opts.Tooltip(frame, text) end end
	local function Enabled() return not opts.Enabled or opts.Enabled() end
	local function Changed()
		ns.CooldownRuleFactsStale()
		if ns.readyPace then ns.readyPace.due = true end
		opts.Changed()
	end

	local function Line(n)
		if lines[n] then return lines[n] end
		local line = CreateFrame("Frame", nil, block)
		line:SetSize(DELETE_X + 24, LINE_H)
		line.n = n
		local function Rule() return List()[line.n] end
		-- (The one that fits where you are now: lit gold, as the mockup had it.)
		line.lit = line:CreateTexture(nil, "BACKGROUND")
		line.lit:SetPoint("TOPLEFT", LIT_X, -1)
		line.lit:SetPoint("BOTTOMRIGHT", 0, 1)
		line.lit:SetColorTexture(1, 0.82, 0, 0.14)
		line.number = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		line.number:SetPoint("RIGHT", line, "LEFT", NUM_R, 0)
		line.number:SetJustifyH("RIGHT")
		line.show = Pick(line, SHOW_W, function() return modes end,
			function() local rule = Rule() return rule and rule.show end,
			function(value)
				local rule = Rule()
				if rule then rule.show = value end
				Changed()
			end)
		line.show:SetPoint("LEFT", line, "LEFT", SHOW_X, 0)
		Tip(line.show, L["What the icon shows while this line fits."])
		line.bar = line:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		line.bar:SetPoint("LEFT", line, "LEFT", BAR_X, 0)
		line.bar:SetText("|")
		line.combat = Pick(line, COMBAT_W, function() return COMBAT_LIST end,
			function() local rule = Rule() return rule and rule.combat end,
			function(value)
				local rule = Rule()
				if rule then rule.combat = value end
				Changed()
			end)
		line.combat:SetPoint("LEFT", line, "LEFT", COMBAT_X, 0)
		Tip(line.combat, L["In a fight (the Calm Timer after one too), out of one, or either."])
		line.place = Pick(line, PLACE_W, function() return PLACE_LIST end,
			function() local rule = Rule() return rule and rule.place end,
			function(value)
				local rule = Rule()
				if rule then rule.place = value end
				Changed()
			end)
		line.place:SetPoint("LEFT", line, "LEFT", PLACE_X, 0)
		Tip(line.place, L["Where this line fits."])
		-- (A rule of its own: its words, colored as the editor has them, in place of the two.)
		-- (In a box as wide as the two, so the line reads as even as the
		-- others; clicked, it edits, as Edit does. Loose small text, it looked
		-- unfinished, 2026-11-20.)
		line.cqlBox = CreateFrame("Button", nil, line)
		line.cqlBox:SetSize(PLACE_X + PLACE_W - COMBAT_X, 22)
		line.cqlBox:SetPoint("LEFT", line, "LEFT", COMBAT_X, 0)
		local fill = line.cqlBox:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		fill:SetColorTexture(0.06, 0.05, 0.04, 0.9)
		for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", false },
			{ "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true } }) do
			local edge = line.cqlBox:CreateTexture(nil, "BORDER")
			edge:SetPoint(side[1])
			edge:SetPoint(side[2])
			if side[3] then edge:SetWidth(1) else edge:SetHeight(1) end
			edge:SetColorTexture(0.45, 0.38, 0.2, 1)
		end
		local glow = line.cqlBox:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 1, 1, 0.06)
		line.cql = line.cqlBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		line.cql:SetPoint("LEFT", line.cqlBox, "LEFT", 8, 0)
		line.cql:SetPoint("RIGHT", line.cqlBox, "RIGHT", -6, 0)
		line.cql:SetJustifyH("LEFT")
		line.cql:SetWordWrap(false)
		Tip(line.cqlBox, L["This line's rule (CQL). Click to edit it."])
		line.cqlBox:SetScript("OnClick", function()
			local click = line.edit and line.edit:GetScript("OnClick")
			if click then click(line.edit) end
		end)

		line.edit = ns.PanelButton(line)
		line.edit:SetSize(EDIT_W, 20)
		line.edit:SetPoint("LEFT", line, "LEFT", EDIT_X, 0)
		line.edit:SetText(L["Edit"])
		line.edit.searchSkip = true
		Tip(line.edit, L["Write where this line fits as a rule (CQL). Empty it to go back to the dropdowns."])
		line.edit:SetScript("OnClick", function()
			local rule = Rule()
			if not rule then return end
			local was = ns.CooldownRuleText(rule)
			ns.OpenRuleEditor({
				key = "cdm",
				label = ("%s, %s %d"):format(label or "", L["line"], line.n),
				Text = function() return ns.CooldownRuleText(rule) end,
				SetText = function() end,
				Close = function(text)
					if not ns.SetCooldownRuleText(rule, text) then ns.SetCooldownRuleText(rule, was) end
					Changed()
				end,
			})
		end)

		local function Move(by)
			local list, i = List(), line.n
			local j = i + by
			if j < 1 or j > #list then return end
			list[i], list[j] = list[j], list[i]
			Changed()
		end
		for _, which in ipairs({ { "up", -1, UP_X, "Interface\\Buttons\\Arrow-Up-",
			L["Moves this line up, so it's checked sooner."] },
			{ "down", 1, DOWN_X, "Interface\\Buttons\\Arrow-Down-", L["Moves this line down, so it's checked later."] } }) do
			local button = CreateFrame("Button", nil, line)
			button:SetSize(14, 14)
			button:SetPoint("LEFT", line, "LEFT", which[3], which[2] < 0 and 6 or -6)
			button:SetNormalTexture(which[4] .. "Up")
			button:SetPushedTexture(which[4] .. "Down")
			button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			button:HookScript("OnDisable", function(self) self:SetAlpha(0.3) end)
			button:HookScript("OnEnable", function(self) self:SetAlpha(1) end)
			Tip(button, which[5])
			button:SetScript("OnClick", function() Move(which[2]) end)
			line[which[1]] = button
		end
		-- (A plain grey X, red under the pointer: the game's red close
		-- buttons were the loudest thing on the page, 2026-11-20.)
		line.delete = CreateFrame("Button", nil, line)
		line.delete:SetSize(18, 20)
		line.delete:SetPoint("LEFT", line, "LEFT", DELETE_X + 2, 0)
		local cross = line.delete:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		cross:SetPoint("CENTER")
		cross:SetText("X")
		cross:SetTextColor(0.6, 0.6, 0.6)
		line.delete:HookScript("OnEnter", function() cross:SetTextColor(1, 0.3, 0.25) end)
		line.delete:HookScript("OnLeave", function() cross:SetTextColor(0.6, 0.6, 0.6) end)
		line.delete:HookScript("OnDisable", function(self) self:SetAlpha(0.3) end)
		line.delete:HookScript("OnEnable", function(self) self:SetAlpha(1) end)
		Tip(line.delete, L["Deletes this line."])
		line.delete:SetScript("OnClick", function()
			local list = List()
			if list[line.n] then table.remove(list, line.n) end
			ns.CooldownRules(kind, key) -- (an empty list dropped)
			Changed()
		end)
		lines[n] = line
		return line
	end

	-- The Everywhere else line: its number and words; the page puts the
	-- row's own dropdown beside them.
	-- (Its words where a line's where goes, after a bar as theirs, full size
	-- in a soft color: small and grey, it was the faintest thing on the page.)
	local elseNumber = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	elseNumber:SetJustifyH("RIGHT")
	local elseBar = block:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	elseBar:SetText("|")
	local elseText = block:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	elseText:SetTextColor(0.78, 0.74, 0.64)
	elseText:SetText(L["Everywhere else"])
	local elseLit = block:CreateTexture(nil, "BACKGROUND")
	elseLit:SetColorTexture(1, 0.82, 0, 0.14)

	function block.Set(newKind, newKey, newLabel, newModes)
		kind, key, label, modes = newKind, newKey, newLabel, newModes
	end
	-- What it's for, and how many lines it shows (for tests).
	function block.For() return kind, key end
	function block.Shown()
		local count = 0
		for _, line in ipairs(lines) do
			if line:IsShown() then count = count + 1 end
		end
		return count
	end
	-- Whether the row has lines to show.
	function block.Has() return ns.CooldownRules(kind, key) ~= nil end
	-- A new line at the bottom: Always, anywhere (so it's plain it needs a where).
	function block.Add()
		local list = ns.CooldownRules(kind, key, true)
		list[#list + 1] = { show = modes and modes[1] and modes[1].value or "always", combat = "any", place = "any" }
		Changed()
	end

	-- Lays the lines out from the top; gives the height, the Everywhere else
	-- line's included (0 with no lines: the row as it always was).
	function block.Layout()
		local list = ns.CooldownRules(kind, key)
		local count = list and #list or 0
		local enabled = Enabled()
		local _, hit = ns.CooldownRuleMode(kind, key)
		for i = 1, count do
			local line, rule = Line(i), list[i]
			line.n = i
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -(i - 1) * LINE_H)
			line:Show()
			line.lit:SetShown(i == hit)
			line.number:SetText(tostring(i))
			line.show.Show_()
			local own = rule.cql ~= nil
			line.combat:SetShown(not own)
			line.place:SetShown(not own)
			line.cqlBox:SetShown(own)
			if own then
				line.cql:SetText(ns.ColoredRule and ns.ColoredRule(rule.cql) or rule.cql)
			else
				line.combat.Show_()
				line.place.Show_()
			end
			for _, control in ipairs({ line.show, line.combat, line.place, line.edit, line.delete, line.cqlBox }) do
				if control.SetEnabled then control:SetEnabled(enabled) end
			end
			line.up:SetEnabled(enabled and i > 1)
			line.down:SetEnabled(enabled and i < count)
		end
		for i = count + 1, #lines do lines[i]:Hide() end
		if count == 0 then
			elseNumber:Hide()
			elseBar:Hide()
			elseText:Hide()
			elseLit:Hide()
			block:SetHeight(1)
			return 0
		end
		local y = -count * LINE_H
		elseNumber:ClearAllPoints()
		elseNumber:SetPoint("RIGHT", block, "TOPLEFT", NUM_R, y - LINE_H / 2)
		elseNumber:SetText(tostring(count + 1))
		elseNumber:Show()
		elseText:ClearAllPoints()
		elseBar:ClearAllPoints()
		elseBar:SetPoint("LEFT", block, "TOPLEFT", BAR_X, y - LINE_H / 2)
		elseBar:Show()
		elseText:SetPoint("LEFT", block, "TOPLEFT", COMBAT_X + 8, y - LINE_H / 2)
		elseText:Show()
		elseLit:ClearAllPoints()
		elseLit:SetPoint("TOPLEFT", block, "TOPLEFT", LIT_X, y - 1)
		elseLit:SetPoint("BOTTOMRIGHT", block, "TOPLEFT", DELETE_X + 24, y - LINE_H + 1)
		elseLit:SetShown(hit == nil)
		block:SetHeight((count + 1) * LINE_H)
		return (count + 1) * LINE_H
	end
	return block
end
