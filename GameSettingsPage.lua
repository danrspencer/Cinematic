-- The Help hub's Game Settings page: every game setting Cinematic
-- changes for a while where your own change wins (sets marked playerWins,
-- ns.ApplyCVarSet; and the profiles' Cooldown Manager and personal resource
-- display switches, Profiles.lua), one row each: what it's for, ours, yours
-- and now. Keep yours puts yours back and Cinematic leaves it alone for good
-- (db.cvarsLeftAlone, kept by Reset Settings); Use ours writes ours again at
-- once if it's in use now (also after you changed it yourself), else next
-- time. Lives as you look at it.
local _, ns = ...
local L = ns.L

local REFRESH = 0.5 -- seconds between updates while shown
local ROW_H = 22
local OURS_COLOR, YOURS_COLOR, DIM_COLOR = "|cff40ff40", "|cff66ccff", "|cff888888"

-- The sections, in order, by the setting's name.
local SECTIONS = {
	{ "^UnitName", "Names over heads" },
	{ "^nameplate", "Nameplates" },
	{ "[Cc]ombatText", "Combat text" },
	{ "", "Other" },
}

-- Each setting's name as the game's options call it (else the setting's own).
local NAMES = {
	UnitNameOwn = "My name", UnitNameNPC = "All NPC names", UnitNameHostleNPC = "Enemy NPC names",
	UnitNameInteractiveNPC = "Interactive NPC names", UnitNameFriendlySpecialNPCName = "Special NPC names",
	UnitNameNonCombatCreatureName = "Critter and companion names", UnitNameFriendlyPlayerName = "Friendly player names",
	UnitNameFriendlyPetName = "Friendly pet names", UnitNameFriendlyGuardianName = "Friendly guardian names",
	UnitNameFriendlyTotemName = "Friendly totem names", UnitNameFriendlyMinionName = "Friendly minion names",
	UnitNameEnemyPlayerName = "Enemy player names", UnitNameEnemyPetName = "Enemy pet names",
	UnitNameEnemyGuardianName = "Enemy guardian names", UnitNameEnemyTotemName = "Enemy totem names",
	UnitNameEnemyMinionName = "Enemy minion names", UnitNamePlayerGuild = "Guild names",
	UnitNameFocused = "Target's name",
	nameplateShowAll = "Always show nameplates", nameplateForceShowUnitName = "Always show names on nameplates",
	nameplateShowEnemies = "Enemy nameplates", nameplateShowEnemyPlayers = "Enemy player nameplates",
	nameplateShowEnemyMinions = "Enemy minion nameplates", nameplateShowEnemyPets = "Enemy pet nameplates",
	nameplateShowEnemyGuardians = "Enemy guardian nameplates", nameplateShowEnemyTotems = "Enemy totem nameplates",
	nameplateShowEnemyMinus = "Minor enemy nameplates", nameplateShowFriends = "Friendly nameplates",
	nameplateShowFriendlyPlayers = "Friendly player nameplates", nameplateShowFriendlyNPCs = "Friendly NPC nameplates",
	nameplateShowFriendlyMinions = "Friendly minion nameplates", nameplateShowFriendlyPets = "Friendly pet nameplates",
	nameplateShowFriendlyGuardians = "Friendly guardian nameplates",
	nameplateShowFriendlyTotems = "Friendly totem nameplates",
	nameplateShowFriendlyPlayerMinions = "Friendly minion nameplates",
	nameplateShowFriendlyPlayerPets = "Friendly pet nameplates",
	nameplateShowFriendlyPlayerGuardians = "Friendly guardian nameplates",
	nameplateShowFriendlyPlayerTotems = "Friendly totem nameplates",
	nameplateShowOnlyNameForFriendlyPlayerUnits = "Only names on friendly player nameplates",
	nameplateShowOffscreen = "Show offscreen nameplates", nameplateStyle = "Nameplate style",
	nameplateUseClassColorForFriendlyPlayerUnitNames = "Class colors for friendly names",
	nameplateShowSelf = "Personal resource display",
	enableFloatingCombatText = "Floating combat text", floatingCombatTextCombatDamage = "Damage numbers",
	floatingCombatTextCombatHealing = "Healing numbers", floatingCombatTextPetMeleeDamage = "Pet melee damage",
	floatingCombatTextPetSpellDamage = "Pet spell damage",
	floatingCombatTextCombatHealingAbsorbSelf = "Shields on you",
	floatingCombatTextCombatHealingAbsorbTarget = "Shields on your target",
	floatingCombatTextCombatDamage_v2 = "Damage numbers", floatingCombatTextCombatHealing_v2 = "Healing numbers",
	floatingCombatTextPetMeleeDamage_v2 = "Pet melee damage", floatingCombatTextPetSpellDamage_v2 = "Pet spell damage",
	floatingCombatTextCombatHealingAbsorbSelf_v2 = "Shields on you",
	floatingCombatTextCombatHealingAbsorbTarget_v2 = "Shields on your target",
	ObjectSelectionCircle = "Target circle", findYourselfAnywhere = "Self highlight",
	findYourselfInRaid = "Self highlight in raids", findYourselfInBG = "Self highlight in battlegrounds",
	raidFramesDisplayBuffs = "Raid frame buffs",
	raidFramesDisplayDebuffs = "Raid frame debuffs", cooldownViewerEnabled = "Cooldown Manager",
}

-- What each set is for, by its label (the dev copy's Held Game Settings names).
local PURPOSES = {
	{ "^Names", "CineMode hides names" },
	{ "^Plates off$", "Faded nameplates can't be clicked" },
	{ "^Combat text off$", "CineMode out of fights" },
	{ "^Target circle off$", "CineMode hides the target circle" },
	{ "^Self highlight off$", "CineMode hides your self highlight" },
	{ "^Duel plates$", "Duel Vision" },
	{ "^Instance plates off", "CineMode in dungeons and raids" },
	{ "^All plates on$", "CineMode fades nameplates" },
	{ "^Offscreen plates", "Nameplates page: offscreen plates" },
	{ "^Raid ", "Raid frame auras fade" },
	{ "^Game's damage numbers off$", "Combat Text Style" },
	{ "^Nameplate style$", "Style: nameplate style" },
	{ "^Class color names$", "Name Style: class colors" },
}
local SWITCH_PURPOSES = {
	cooldownViewerEnabled = "Profile: Cooldown Manager", nameplateShowSelf = "Profile: personal resource display",
}

local COLUMNS = { -- heading, share of the width
	{ "Setting", 0.25 }, { "Used for", 0.27 }, { "Ours", 0.09 }, { "Yours", 0.09 }, { "Now", 0.08 }, { "", 0.22 },
}

ns.OnLanguage(function()
	for _, section in ipairs(SECTIONS) do section[2] = L[section[2]] end
	for cvar, name in pairs(NAMES) do NAMES[cvar] = L[name] end
	for _, purpose in ipairs(PURPOSES) do purpose[2] = L[purpose[2]] end
	for cvar, purpose in pairs(SWITCH_PURPOSES) do SWITCH_PURPOSES[cvar] = L[purpose] end
	for _, column in ipairs(COLUMNS) do column[1] = column[1] ~= "" and L[column[1]] or "" end
end)

local function Same(a, b)
	return a == b or (tonumber(a) ~= nil and tonumber(a) == tonumber(b))
end

-- A value as the options show it: on and off for switches, a style's name.
local function Shown(cvar, value)
	if value == nil then
		return ""
	end
	value = tostring(value)
	if cvar == "nameplateStyle" then
		local names = ns.GamePlateStyles and ns.GamePlateStyles()
		local name = names and names[(tonumber(value) or -1) + 1]
		if name then return name end
	elseif value == "0" then
		return L["Off"]
	elseif value == "1" then
		return L["On"]
	end
	return value
end

local function Purpose(label)
	for _, purpose in ipairs(PURPOSES) do
		if tostring(label or ""):find(purpose[1]) then return purpose[2] end
	end
	return label or ""
end

-- The rows as they are now, in sections: { cvar, name, purposes, ours,
-- yours, now, state, canYours, canOurs, switch }.
local function Gather()
	local lone = ns.db and ns.db.cvarsLeftAlone or {}
	local saved = ns.db and ns.db.savedCVars or {}
	local byCVar, list = {}, {}
	local function Row(cvar)
		local row = byCVar[cvar]
		if not row then
			row = { cvar = cvar, name = NAMES[cvar] or cvar, purposes = {}, seen = {}, values = {} }
			byCVar[cvar] = row
			list[#list + 1] = row
		end
		return row
	end
	for _, set in ipairs(ns.cvarSets or {}) do
		if set.playerWins then
			for cvar, value in pairs(set.values) do
				if GetCVar(cvar) ~= nil then
					local row = Row(cvar)
					local purpose = Purpose(set.label)
					if not row.seen[purpose] then
						row.seen[purpose] = true
						row.purposes[#row.purposes + 1] = purpose
					end
					row.values[tostring(value)] = true
				end
			end
		end
	end
	for _, switch in ipairs(ns.ProfileSwitchRows and ns.ProfileSwitchRows() or {}) do
		if GetCVar(switch.cvar) ~= nil then
			local row = Row(switch.cvar)
			row.switch = switch
			row.purposes[#row.purposes + 1] = SWITCH_PURPOSES[switch.cvar] or switch.name
			row.values["1"] = true
		end
	end
	for _, row in ipairs(list) do
		local cvar = row.cvar
		row.now = GetCVar(cvar)
		local holder = ns.CVarHolder and ns.CVarHolder(cvar)
		local switch = row.switch
		if holder then
			row.ours = holder.values[cvar]
		elseif switch and switch.wanted then
			row.ours = "1"
		else
			-- (In use now by none: what the sets would write.)
			local values = {}
			for value in pairs(row.values) do values[#values + 1] = Shown(cvar, value) end
			table.sort(values)
			row.oursText = table.concat(values, " / ")
		end
		local inUse = holder ~= nil or (switch and switch.wanted and ns.db.enabled) or false
		if lone[cvar] then
			row.yours, row.state = row.now, "kept"
		elseif saved[cvar] ~= nil then
			row.yours = saved[cvar]
		elseif switch and switch.turnedOn then
			row.yours = "0" -- (Cinematic turned it on: it was off)
		else
			row.yours = row.now
		end
		if not row.state then
			if inUse and row.ours ~= nil and Same(row.now, row.ours) then
				row.state = "ours"
			elseif inUse then
				row.state = "changed"
			else
				row.state = "idle"
			end
		end
		row.canYours = not lone[cvar]
		row.canOurs = lone[cvar] or (row.state == "changed") or false
		local section = #SECTIONS
		for i, info in ipairs(SECTIONS) do
			if cvar:find(info[1]) then section = i break end
		end
		row.section = section
		row.purpose = table.concat(row.purposes, ", ")
	end
	table.sort(list, function(a, b)
		if a.section ~= b.section then return a.section < b.section end
		if a.name ~= b.name then return a.name < b.name end
		return a.cvar < b.cvar
	end)
	return list
end

local STATE_TIPS = {
	ours = "Cinematic's value is in use now. Yours comes back when it's done, or when you pick Keep yours.",
	changed = "In use by Cinematic, but you changed it yourself, so yours stands for now. Cinematic changes it " ..
		"again next time it needs it, unless you pick Keep yours. Use ours puts ours back now.",
	idle = "Yours. Cinematic changes it only while it needs it, then puts yours back.",
	kept = "Kept as yours: Cinematic never changes it. Some of its features may look different. Use ours lets " ..
		"Cinematic change it again.",
}
ns.OnLanguage(function()
	for key, tip in pairs(STATE_TIPS) do STATE_TIPS[key] = L[tip] end
end)

local function Pick(row, ours)
	local ok
	if ours then
		if row.switch and row.switch.leftAloneKey then (ns.ProfileSwitchMarks and ns.ProfileSwitchMarks() or ns.db)[row.switch.leftAloneKey] = nil end
		ok = ns.UseOurCVar(row.cvar)
	else
		ok = ns.KeepYourCVar(row.cvar)
	end
	return ok
end
local function FightNote()
	ns.Print(L["the game won't change nameplate and name settings in a fight: try again once it's over"])
end

function ns.CreateGameSettingsPage(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", L["Game Settings"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title, L["Game settings Cinematic changes while it needs them, then puts back to yours."])

	local allOurs = ns.PanelButton(content)
	allOurs:SetSize(170, 24)
	allOurs:SetText(L["Use ours for all"])
	allOurs:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
	local allYours = ns.PanelButton(content)
	allYours:SetSize(170, 24)
	allYours:SetText(L["Keep yours for all"])
	allYours:SetPoint("LEFT", allOurs, "RIGHT", 8, 0)
	local summary = kit.Label(content, "GameFontHighlightSmall", "")
	summary:SetPoint("LEFT", allYours, "RIGHT", 12, 0)
	summary:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	summary:SetJustifyH("LEFT")

	local grid = CreateFrame("Frame", nil, content)
	grid:SetPoint("TOPLEFT", allOurs, "BOTTOMLEFT", 0, -10)
	grid:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	grid:SetHeight(ROW_H)

	local Refresh
	local function Lay(cells, parent)
		local width = grid:GetWidth() or 0
		local x = 0
		for i, column in ipairs(COLUMNS) do
			local cell = cells[i]
			if cell then
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", parent, "LEFT", x + 2, 0)
				cell:SetWidth(math.max(1, width * column[2] - 4))
			end
			x = x + width * column[2]
		end
		return width
	end

	local head = CreateFrame("Frame", nil, grid)
	head:SetPoint("TOPLEFT")
	head:SetPoint("TOPRIGHT")
	head:SetHeight(ROW_H)
	local headCells = {}
	for i, column in ipairs(COLUMNS) do
		local text = head:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		text:SetText(column[1])
		headCells[i] = text
	end

	-- Lines: a section heading or a setting's row, made as needed.
	local lines = {}
	local function Line(index)
		local line = lines[index]
		if line then return line end
		line = CreateFrame("Frame", nil, grid)
		line:SetHeight(ROW_H)
		line:SetPoint("TOPLEFT", 0, -index * ROW_H)
		line:SetPoint("RIGHT")
		line:EnableMouse(true)
		line.stripe = line:CreateTexture(nil, "BACKGROUND")
		line.stripe:SetAllPoints()
		line.heading = line:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		line.heading:SetPoint("LEFT", 2, 0)
		line.cells = {}
		for i = 1, 5 do
			local cell = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			cell:SetJustifyH("LEFT")
			cell:SetWordWrap(false)
			line.cells[i] = cell
		end
		-- (Small text, set before the words: Cyrillic needs the font first.)
		for key, label in pairs({ yours = L["Keep yours"], ours = L["Use ours"] }) do
			local button = ns.PanelButton(line)
			button:SetNormalFontObject("GameFontNormalSmall")
			button:SetHighlightFontObject("GameFontHighlightSmall")
			button:SetDisabledFontObject("GameFontDisableSmall")
			button:SetHeight(ROW_H - 2)
			button:SetText(label)
			line[key] = button
		end
		line.yours:SetScript("OnClick", function()
			if line.row and not Pick(line.row, false) then FightNote() end
			Refresh()
		end)
		line.ours:SetScript("OnClick", function()
			if line.row and not Pick(line.row, true) then FightNote() end
			Refresh()
		end)
		line:SetScript("OnEnter", function(self)
			local row = self.row
			if not row then return end
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
			GameTooltip:SetText(row.name, 1, 0.82, 0)
			GameTooltip:AddLine(STATE_TIPS[row.state], 1, 1, 1, true)
			GameTooltip:AddLine(L["Used for:"] .. " " .. row.purpose, 0.8, 0.8, 0.8, true)
			GameTooltip:AddLine(row.cvar, 0.5, 0.5, 0.5)
			GameTooltip:Show()
		end)
		line:SetScript("OnLeave", function() GameTooltip:Hide() end)
		lines[index] = line
		return line
	end

	function Refresh()
		local rows = Gather()
		Lay(headCells, head)
		local index, lastSection, inUse, kept = 0, nil, 0, 0
		for _, row in ipairs(rows) do
			if row.state == "ours" then inUse = inUse + 1 elseif row.state == "kept" then kept = kept + 1 end
			if row.section ~= lastSection then
				lastSection = row.section
				index = index + 1
				local line = Line(index)
				line.row = nil
				line.heading:SetText(SECTIONS[row.section][2])
				line.heading:Show()
				line.stripe:SetColorTexture(0.45, 0.38, 0.2, 0.25)
				for _, cell in ipairs(line.cells) do cell:Hide() end
				line.yours:Hide()
				line.ours:Hide()
				line:Show()
			end
			index = index + 1
			local line = Line(index)
			line.row = row
			line.heading:Hide()
			line.stripe:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)
			local width = Lay(line.cells, line)
			local c = line.cells
			c[1]:SetText(row.name)
			c[2]:SetText(DIM_COLOR .. row.purpose)
			c[3]:SetText((row.state == "ours" and OURS_COLOR or "") .. (row.oursText or Shown(row.cvar, row.ours)))
			c[4]:SetText((row.state ~= "ours" and YOURS_COLOR or "") .. Shown(row.cvar, row.yours)
				.. (row.state == "kept" and " " .. L["(kept)"] or ""))
			c[5]:SetText(Shown(row.cvar, row.now))
			for _, cell in ipairs(c) do cell:Show() end
			-- (The buttons in the last column, each half its width: Keep yours,
			-- then Use ours, the one shown alone taking the first spot.)
			local x = width * (1 - COLUMNS[#COLUMNS][2]) + 2
			local half = math.max(1, math.floor((width * COLUMNS[#COLUMNS][2] - 6) / 2))
			line.yours:SetWidth(half)
			line.ours:SetWidth(half)
			line.yours:ClearAllPoints()
			line.yours:SetPoint("LEFT", line, "LEFT", x, 0)
			line.ours:ClearAllPoints()
			line.ours:SetPoint("LEFT", line, "LEFT", row.canYours and x + half + 2 or x, 0)
			line.yours:SetShown(row.canYours)
			line.ours:SetShown(row.canOurs)
			line:Show()
		end
		for i = index + 1, #lines do
			lines[i]:Hide()
			lines[i].row = nil
		end
		grid:SetHeight(ROW_H * (index + 1))
		summary:SetText((L["%d settings: %s%d Cinematic's now|r, %s%d kept as yours|r."]):format(#rows, OURS_COLOR,
			inUse, YOURS_COLOR, kept))
		allYours.rows, allOurs.rows = rows, rows
	end

	allOurs:SetScript("OnClick", function(self)
		local blocked
		for _, row in ipairs(self.rows or {}) do
			if row.canOurs and not Pick(row, true) then blocked = true end
		end
		if blocked then FightNote() end
		Refresh()
	end)
	allYours:SetScript("OnClick", function(self)
		local blocked
		for _, row in ipairs(self.rows or {}) do
			if row.canYours and not Pick(row, false) then blocked = true end
		end
		if blocked then FightNote() end
		Refresh()
	end)

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
	kit.RegisterSubpage(canvas, "Game settings", L["Game Settings"])
end
