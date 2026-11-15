-- /cine debug iconcrop: which crop round action buttons need. Some icons'
-- art has a thicker dark frame of its own (Evocation): with the round shape's
-- crop (ActionBarStyle.lua, 0.07 a side) it shows as dark arcs inside the ring.
-- Every icon on your action bars, then the rest of your spellbook, shown round
-- as the buttons draw them (our mask, a 1 pixel gray ring) in three columns:
-- crop 0.07 (today's), 0.10 and 0.12, same order in each. A page of 64 at a
-- time, a screenshot of each (named in the log), the last page left up with a
-- Close button. Logged into CinematicDB.iconCropLog: each icon's number, name
-- and texture, so the shots can be read. Changes no settings. Dev copy only.
--   /cine debug iconcrop all: every spell icon the game has (the macro icon
--     list, no character needed), today's crop only, 24 a row, to find the
--     icons with rims;
--   /cine debug iconcrop <texture ids>: just those, at the three crops.
local ADDON_NAME, ns = ...

local ROUND_MASK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\ActionRoundMask"
local RING = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\ActionRing1"
local ALL_CROPS = { 0.07, 0.10, 0.12 }
local CROPS, COLS, ROWS
local SIZE, GAP, PANEL_GAP, PAD = 40, 6, 28, 16
local SHOT_WAIT = 1.5 -- seconds: a page up, before its screenshot

local box, run

local function Say(text)
	local log = CinematicDB and CinematicDB.iconCropLog
	if log then log[#log + 1] = text end
end

-- (Screenshot() from a function of ours: a C_Timer won't take it directly.)
local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end

local function SpellName(id)
	if not id then return nil end
	if C_Spell and C_Spell.GetSpellName then
		local ok, name = pcall(C_Spell.GetSpellName, id)
		if ok and name then return name end
	end
	if GetSpellInfo then
		local ok, name = pcall(GetSpellInfo, id)
		if ok and name then return name end
	end
	return nil
end

-- Every icon to show, once each by texture: the action bars first (what
-- players see), then the spellbook's others.
local function Gather()
	local list, seen = {}, {}
	local function Add(texture, name, from)
		if texture == nil or (issecretvalue and issecretvalue(texture)) or seen[texture] then return end
		seen[texture] = true
		list[#list + 1] = { texture = texture, name = name or "?", from = from }
	end
	for slot = 1, 180 do
		local okTex, texture = pcall(GetActionTexture, slot)
		if okTex and texture then
			local okInfo, kind, id = pcall(GetActionInfo, slot)
			local name
			if okInfo and kind == "spell" then name = SpellName(id)
			elseif okInfo and kind == "item" and C_Item and C_Item.GetItemNameByID then
				local okItem, itemName = pcall(C_Item.GetItemNameByID, id)
				name = okItem and itemName or nil
			elseif okInfo and kind == "macro" then
				local okMacro, macroName = pcall(GetActionText, slot)
				name = okMacro and macroName and ("macro " .. macroName) or nil
			end
			Add(texture, name, "slot " .. slot)
		end
	end
	local book = C_SpellBook
	if book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemTexture then
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		local okLines, lines = pcall(book.GetNumSpellBookSkillLines)
		for line = 1, okLines and lines or 0 do
			local okLine, info = pcall(book.GetSpellBookSkillLineInfo, line)
			if okLine and type(info) == "table" then
				for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
					local okTex, texture = pcall(book.GetSpellBookItemTexture, i, bank)
					local okName, name = pcall(book.GetSpellBookItemName, i, bank)
					if okTex then Add(texture, okName and name or nil, "book " .. i) end
				end
			end
		end
	elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellTexture then
		for tab = 1, GetNumSpellTabs() do
			local _, _, offset, count = GetSpellTabInfo(tab)
			for i = offset + 1, offset + count do
				local okTex, texture = pcall(GetSpellTexture, i, "spell")
				local okName, name = pcall(GetSpellBookItemName, i, "spell")
				if okTex then Add(texture, okName and name or nil, "book " .. i) end
			end
		end
	end
	return list
end

-- Every spell icon the game has: the macro icon picker's list.
local function GatherAll()
	local list, seen, icons = {}, {}, {}
	if not GetMacroIcons then return list end
	local ok, back = pcall(GetMacroIcons, icons)
	if ok and type(back) == "table" then icons = back end
	for _, texture in ipairs(icons) do
		if type(texture) == "string" and not texture:find("\\", 1, true) then
			texture = "Interface\\Icons\\" .. texture
		end
		if texture and not seen[texture] then
			seen[texture] = true
			list[#list + 1] = { texture = texture, name = tostring(texture), from = "macro icons" }
		end
	end
	return list
end

local function GatherIds(text)
	local list = {}
	for id in text:gmatch("%d+") do
		list[#list + 1] = { texture = tonumber(id), name = "texture " .. id, from = "asked" }
	end
	return list
end

local function PanelWidth() return COLS * SIZE + (COLS - 1) * GAP end

local function Build()
	if box then box:Hide() end
	box = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	box:SetFrameStrata("FULLSCREEN_DIALOG")
	box:SetPoint("CENTER")
	local wide = PAD * 2 + 24 + #CROPS * PanelWidth() + (#CROPS - 1) * PANEL_GAP
	local high = PAD * 2 + 56 + ROWS * SIZE + (ROWS - 1) * GAP + 30
	box:SetSize(wide, high)
	local room = UIParent:GetWidth() - 40
	if room < wide then box:SetScale(room / wide) end
	box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	-- (A mid gray ground, as a field or the sky behind a bar: dark rims show on it.)
	box:SetBackdropColor(0.35, 0.33, 0.28, 1)
	box:SetBackdropBorderColor(0, 0, 0, 1)
	box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	box.title:SetPoint("TOP", 0, -PAD)
	box.rowLabels, box.cells, box.heads = {}, {}, {}
	local top = -PAD - 46
	for row = 1, ROWS do
		local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("RIGHT", box, "TOPLEFT", PAD + 20, top - (row - 1) * (SIZE + GAP) - SIZE / 2)
		box.rowLabels[row] = label
	end
	for p, crop in ipairs(CROPS) do
		local left = PAD + 24 + (p - 1) * (PanelWidth() + PANEL_GAP)
		local head = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		head:SetPoint("BOTTOM", box, "TOPLEFT", left + PanelWidth() / 2, top + 6)
		head:SetText(("crop %.2f%s"):format(crop, p == 1 and " (now)" or ""))
		box.heads[p] = head
		box.cells[p] = {}
		for i = 1, COLS * ROWS do
			local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
			local cell = CreateFrame("Frame", nil, box)
			cell:SetSize(SIZE, SIZE)
			cell:SetPoint("TOPLEFT", box, "TOPLEFT", left + col * (SIZE + GAP), top - row * (SIZE + GAP))
			cell.icon = cell:CreateTexture(nil, "ARTWORK")
			cell.icon:SetAllPoints()
			cell.icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
			cell.mask = cell:CreateMaskTexture()
			cell.mask:SetAllPoints()
			cell.mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
			cell.icon:AddMaskTexture(cell.mask)
			cell.ring = cell:CreateTexture(nil, "OVERLAY")
			cell.ring:SetAllPoints()
			cell.ring:SetTexture(RING)
			cell.ring:SetVertexColor(0.4, 0.4, 0.4, 1)
			cell:EnableMouse(true)
			cell:SetScript("OnEnter", function(self)
				if not self.entry then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(("%d. %s"):format(self.number, self.entry.name))
				GameTooltip:AddLine(("%s, texture %s"):format(self.entry.from, tostring(self.entry.texture)), 1, 1, 1)
				GameTooltip:Show()
			end)
			cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
			box.cells[p][i] = cell
		end
	end
	box.close = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
	box.close:SetSize(90, 22)
	box.close:SetPoint("BOTTOMRIGHT", -PAD, PAD - 6)
	box.close:SetText(CLOSE or "Close")
	box.close:SetScript("OnClick", function() box:Hide() end)
	box.prev = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
	box.prev:SetSize(60, 22)
	box.prev:SetPoint("BOTTOMLEFT", PAD, PAD - 6)
	box.prev:SetText("<")
	box.next = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
	box.next:SetSize(60, 22)
	box.next:SetPoint("LEFT", box.prev, "RIGHT", 6, 0)
	box.next:SetText(">")
	box.prev:SetScript("OnClick", function() if box.page > 1 then box.ShowPage(box.page - 1) end end)
	box.next:SetScript("OnClick", function() if box.page < box.pages then box.ShowPage(box.page + 1) end end)
end

local function ShowPage(page)
	local per = COLS * ROWS
	box.page = page
	box.title:SetText(("Round icon crop  -  page %d of %d  (%d icons)"):format(page, box.pages, #box.list))
	for row = 1, ROWS do
		local first = (page - 1) * per + (row - 1) * COLS + 1
		box.rowLabels[row]:SetText(first <= #box.list and tostring(first) or "")
	end
	for p = 1, #CROPS do
		for i, cell in ipairs(box.cells[p]) do
			local number = (page - 1) * per + i
			local entry = box.list[number]
			cell.entry, cell.number = entry, number
			if entry then cell.icon:SetTexture(entry.texture) end
			cell:SetShown(entry ~= nil)
		end
	end
	box.prev:SetShown(page > 1)
	box.next:SetShown(page < box.pages)
end

function ns.IconCropTest(args)
	if run then return end
	args = args or ""
	CinematicDB.iconCropLog = {}
	local list
	if args:find("^all") then
		CROPS, COLS, ROWS = { ALL_CROPS[1] }, 24, 8
		list = GatherAll()
	elseif args:find("%d") then
		CROPS, COLS, ROWS = ALL_CROPS, 8, 8
		list = GatherIds(args)
	else
		CROPS, COLS, ROWS = ALL_CROPS, 8, 8
		list = Gather()
	end
	Build()
	box.ShowPage = ShowPage
	box.list = list
	if #box.list == 0 then
		ns.Print("icon crop test: no icons found on your bars or in your spellbook")
		return
	end
	box.pages = math.ceil(#box.list / (COLS * ROWS))
	Say(("start: %s (game %s), %d icons, %d pages, crops %s; rows of %d, numbers row-major, same order in each column"):format(
		ns.isRetail and "retail" or ns.isClassicEra and "Classic Era" or "Forever", tostring((select(4, GetBuildInfo()))),
		#box.list, box.pages, table.concat(CROPS, " "), COLS))
	for number, entry in ipairs(box.list) do
		Say(("%d. %s (%s, texture %s)"):format(number, tostring(entry.name), entry.from, tostring(entry.texture)))
	end
	box:Show()
	ShowPage(1)
	run = { page = 1 }
	ns.Print(("icon crop test: %d pages, about %d sec; leave it be till it says done"):format(box.pages,
		math.ceil(box.pages * SHOT_WAIT * 2)))
	local function Next()
		Say(Shot("page " .. run.page))
		if run.page >= box.pages then
			run = nil
			Say("done")
			ns.Print("icon crop test done: look the columns over (hover an icon for its name), then say check log")
			return
		end
		C_Timer.After(SHOT_WAIT, function()
			run.page = run.page + 1
			ShowPage(run.page)
			C_Timer.After(SHOT_WAIT, Next)
		end)
	end
	C_Timer.After(SHOT_WAIT, Next)
end
