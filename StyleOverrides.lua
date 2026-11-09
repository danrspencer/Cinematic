-- The Style hub's Overrides tab: a look can hide or show parts of the unit
-- frames and nameplates over what their Show in rows on the Interface pages
-- say, so a theme or a profile can drop the portrait or a background without
-- anything being hardcoded for it. One setting a row, styleOver_<row's key>:
-- "row" goes by the Interface page, "hide" and "show" win over it. The Interface
-- row then says it's overridden, and its own ticks wait underneath, untouched.

local _, ns = ...
local L = ns.L

local PREFIX = "styleOver_"
local DEFAULTS = ns.DEFAULTS

for _, frame in ipairs(ns.UNIT_PART_FRAMES) do
	for _, part in ipairs(ns.UNIT_PARTS) do
		local only = ns.UNIT_PART_ONLY[part]
		if not only or only[frame] then DEFAULTS[PREFIX .. "unitPart" .. frame .. part] = "row" end
	end
end
for _, part in ipairs(ns.PLATE_PARTS) do DEFAULTS[PREFIX .. "platePart" .. part] = "row" end

-- (The frames that go as the target's do so here too, set apart from it or not:
-- the tab has the one Target section.)
local function Own(db, key)
	local value = db[PREFIX .. key]
	if value == "hide" or value == "show" then return value end
	local part = key:match("^unitPartFocusToT(.+)") or key:match("^unitPartFocus(.+)") or key:match("^unitPartToT(.+)")
	value = part and db[PREFIX .. "unitPartTarget" .. part]
	if value == "hide" or value == "show" then return value end
end

-- "hide", "show" or nil (the row says). key: the row's: unitPart<frame><part>,
-- platePart<part>. Only with Style on: off, everything's as the game has it.
function ns.StyleOverride(key)
	local db = ns.db
	if not (db and key and db.styleGeneral ~= false and db.enabled ~= false) then return nil end
	return Own(db, key)
end

-- What an Interface row says in place of its ticks (nil: nothing's overriding it).
function ns.StyleOverrideText(key)
	local over = ns.StyleOverride(key)
	if over == "hide" then return L["Overridden: hidden"] end
	if over == "show" then return L["Overridden: shown"] end
end

local function Sections()
	local UNIT = {
		{ "Portrait", L["Portrait"] }, { "Name", L["Name"] }, { "NameBack", L["Name background"] }, { "Level", L["Level"] },
		{ "LevelBack", L["Level background"] }, { "Health", L["Health bar"] }, { "Power", L["Power bar"] }, { "Numbers", L["Bar numbers"] },
		{ "Art", L["Frame art"] }, { "PvP", L["PvP icon"] }, { "Icons", L["Icons"] }, { "Auras", L["Auras"] },
		{ "CombatText", L["Hit text"] }, { "Threat", L["Threat"] }, { "CastBar", L["Cast bar"] },
	}
	local PLATE = {
		{ "Health", L["Health bar"] }, { "Name", L["Name"] }, { "CastBar", L["Cast bar"] }, { "Buffs", L["Buffs"] },
		{ "Debuffs", L["Debuffs"] }, { "RaidMarker", L["Raid marker"] }, { "Classification", L["Elite/rare icon"] },
		{ "Level", L["Level"] }, { "Threat", L["Threat glow"] }, { "Highlight", L["Target highlight"] },
		{ "Widgets", L["Quest/widget icons"] },
	}
	local list = {}
	for _, section in ipairs({ { L["You"], "Player", ns.UNIT_PARTS_PLAYER }, { L["Target"], "Target", ns.UNIT_PARTS_TARGET },
		{ L["Your pet"], "Pet", ns.UNIT_PARTS_PET } }) do
		local rows = {}
		for _, part in ipairs(UNIT) do
			local key = "unitPart" .. section[2] .. part[1]
			if section[3] and section[3][part[1]] ~= nil and DEFAULTS[PREFIX .. key] ~= nil then
				rows[#rows + 1] = { key, part[2] }
			end
		end
		list[#list + 1] = { section[1], rows }
	end
	local plates = {}
	for _, part in ipairs(PLATE) do
		if not (part[1] == "Level" and ns.isRetail) then plates[#plates + 1] = { "platePart" .. part[1], part[2] } end
	end
	list[#list + 1] = { L["Nameplates"], plates }
	return list
end

function ns.CreateStyleOverridesPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Overrides"])
	ns.StyleTabs(content, title, 3)
	local intro = kit.PageIntro(content, title,
		L["Hide or show parts of the unit frames and nameplates whatever their Show in rows say. Themes use these " ..
		"too. An overridden row on the Interface pages says so, and goes back to its own ticks when you set it to " ..
		"Interface page here. The focus and target of target frames go as Target does."])
	local parts = {} -- (each row, to show its pick again)
	local function Changed()
		if ns.ApplyUnitFrameParts then ns.ApplyUnitFrameParts() end
		kit.Refresh()
		for _, row in ipairs(parts) do row:Refresh() end
	end
	local stack = kit.Stack(intro, "label")

	local clear = ns.PanelButton(content)
	clear:SetSize(130, 22)
	clear:SetText(L["Clear overrides"])
	kit.Tooltip(clear, L["Every part back to what its row on the UI Visibility pages says."])
	clear:SetScript("OnClick", function()
		local db = ns.GetDB()
		for key, value in pairs(DEFAULTS) do
			if type(key) == "string" and key:sub(1, #PREFIX) == PREFIX then db[key] = value end
		end
		Changed()
	end)
	stack:Add(clear, "label")

	-- A row: its name and the three picks side by side, so the whole tab reads at a glance.
	local CHOICES = { { "row", L["UI Visibility page"], 120 }, { "hide", L["Hide"], 60 }, { "show", L["Show"], 60 } }
	local ROW_H, NAME_W = 25, 170
	local function PartRow(holder, index, name, key)
		local row = CreateFrame("Frame", nil, holder)
		row:SetSize(NAME_W + 240, ROW_H)
		row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
		local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT")
		label:SetText(name)
		local buttons, x = {}, NAME_W
		for i, choice in ipairs(CHOICES) do
			local button = ns.PanelButton(row)
			button:SetSize(choice[3], 21)
			button:SetPoint("LEFT", x, 0)
			button:SetText(choice[2])
			button:SetScript("OnClick", function()
				ns.GetDB()[key] = choice[1]
				Changed()
			end)
			buttons[i] = button
			x = x + choice[3] + 4
		end
		function row:Refresh()
			local db = ns.GetDB()
			local value = db and db[key] or "row"
			for i, choice in ipairs(CHOICES) do
				local words = buttons[i]:GetFontString()
				if words then
					if choice[1] == value then words:SetTextColor(1, 0.82, 0) else words:SetTextColor(0.55, 0.55, 0.55) end
				end
			end
		end
		row:Refresh()
		parts[#parts + 1] = row
	end
	-- Each section a folder tab, on the panel under them, down to its last row. The
	-- tab last picked is kept across reloads (SectionState).
	local sections, tabs, holders = Sections(), {}, {}
	local picked = { id = "Style Overrides/tab", open = sections[1][1] }
	local panel, ShowTab
	local function Layout()
		local shown = 1
		for i, section in ipairs(sections) do
			if section[1] == picked.open then shown = i end
		end
		for i, holder in ipairs(holders) do holder:SetShown(i == shown) end
		ShowTab(shown)
		panel:SetPoint("BOTTOMRIGHT", holders[shown], "BOTTOMRIGHT", 12, -12)
		kit.FitContentHeight(content)
	end
	for i, section in ipairs(sections) do tabs[i] = { section[1] } end
	local _, base, height
	panel, _, ShowTab, base, height = ns.FolderTabs(content, tabs, function(i)
		kit.SectionState.Save(picked, sections[i][1])
		Layout()
	end, nil, NAME_W + 264)
	local panelTop = CreateFrame("Frame", nil, content)
	panelTop:SetSize(1, 1)
	panelTop:SetPoint("TOPLEFT", clear, "BOTTOMLEFT", 0, -14 - height)
	panel:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
	base:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
	for i, section in ipairs(sections) do
		local holder = CreateFrame("Frame", nil, content)
		holder:SetSize(NAME_W + 240, #section[2] * ROW_H)
		holder:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12, -10)
		holders[i] = holder
		for r, row in ipairs(section[2]) do PartRow(holder, r, row[2], PREFIX .. row[1]) end
	end
	kit.SectionState.Restore(picked)
	Layout()
	local shown = kit.PageShown(kit.Refresh, content)
	canvas:SetScript("OnShow", function()
		kit.SectionState.Restore(picked) -- (the page is built before the settings load)
		Layout()
		for _, row in ipairs(parts) do row:Refresh() end
		shown()
	end)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Style Overrides", L["Overrides"])
end
