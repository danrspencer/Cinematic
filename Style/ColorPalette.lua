local _, ns = ...

-- The named color palette (a Look panel's color rows, rows.Chips): families
-- of five shades, light to dark, each with a name of its own, and the quick
-- row's picks out of them. Saved colors stay R, G, B: a color's name is found
-- by matching it here (NameOf), so an old save gets one too.
-- (2026-11-19. The quick row's first eight are the old row's colors, exactly,
-- so a color picked from it before keeps its name.)

local FAMILIES = {
	{ "Blood", { { "Rosethorn", "F4A3A3" }, { "Phoenix", "FF4D3B" }, { "Bloodfang", "C62828" },
		{ "Horde Crimson", "8E1B1B" }, { "Bloodmoon", "5A1010" } } },
	{ "Fire", { { "Sunfruit", "FFC48A" }, { "Firebloom", "FF9E1A" }, { "Ragefire", "E86A10" },
		{ "Molten Core", "A8480C" }, { "Searing Gorge", "6B2E08" } } },
	{ "Light", { { "Holy Light", "FFF1B8" }, { "Sunwell", "FFE04D" }, { "Alliance Gold", "E0A800" },
		{ "Goblin Gold", "A87A10" }, { "Bronzebeard", "6B4E0A" } } },
	{ "Nature", { { "Nagrand", "C8EE9A" }, { "Elwynn", "5EE05E" }, { "Ashenvale", "4E9A2A" },
		{ "Feralas", "2E6B1C" }, { "Duskwood", "1B4012" } } },
	{ "Fel", { { "Felspark", "D4FF7A" }, { "Felfire", "9EF01A" }, { "Fel", "5FC80A" },
		{ "Legion", "3A8A06" }, { "Shadowmoon", "1F4A04" } } },
	{ "Tide", { { "Sea Spray", "9EF0D8" }, { "Zangarmarsh", "3ECFA0" }, { "Murloc", "1A9E86" },
		{ "Vashj'ir", "0E6B66" }, { "Abyssal Maw", "08403F" } } },
	{ "Frost", { { "Winterspring", "C8EEFF" }, { "Frostbolt", "40C7EB" }, { "Northrend", "2A8AE0" },
		{ "Stormwind", "1A5AA8" }, { "Kul Tiras", "0E3566" } } },
	{ "Arcane", { { "Mana Pearl", "D5C8FF" }, { "Dalaran", "8F7DFF" }, { "Arcane", "6E48D8" },
		{ "Karazhan", "4A2C9A" }, { "Twisting Nether", "2A1858" } } },
	{ "Bloom", { { "Peacebloom", "FFC8E8" }, { "Kingsblood", "FF70D9" }, { "Netherbloom", "D63A9A" },
		{ "Bloodvine", "93216A" }, { "Nightmare Vine", "5A1240" } } },
	{ "Earth", { { "Westfall", "EAD9B0" }, { "Tanaris", "C8A86A" }, { "Kodo Hide", "8E6A3A" },
		{ "Durotar", "5E4224" }, { "Deepholm", "3A2814" } } },
	{ "Stone", { { "Elune", "FFFFFF" }, { "Mithril", "BDBDB8" }, { "Ironforge", "808080" },
		{ "Thorium", "4A4A4E" }, { "Blackrock", "1E1E22" } } },
}

local QUICK = { "Phoenix", "Firebloom", "Sunwell", "Elwynn", "Felfire", "Zangarmarsh", "Frostbolt", "Dalaran",
	"Kingsblood", "Elune" }

local palette = { families = {}, quick = {}, byName = {} }
for _, family in ipairs(FAMILIES) do
	local shades = {}
	for i, each in ipairs(family[2]) do
		local hex = each[2]
		local color = {
			name = each[1], hex = hex,
			tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255,
		}
		shades[i] = color
		palette.byName[color.name] = color
	end
	palette.families[#palette.families + 1] = { name = family[1], shades = shades }
end
for i, name in ipairs(QUICK) do palette.quick[i] = palette.byName[name] end

local function Near(color, r, g, b)
	return math.abs(color[1] - r) < 0.01 and math.abs(color[2] - g) < 0.01 and math.abs(color[3] - b) < 0.01
end
palette.Near = Near

-- The palette color this is (within a hundredth each way), or nil.
function palette.Find(r, g, b)
	if not (r and g and b) then return nil end
	for _, family in ipairs(palette.families) do
		for _, color in ipairs(family.shades) do
			if Near(color, r, g, b) then return color end
		end
	end
end

-- Its name to show: the palette's (translated), else "Custom #RRGGBB".
function palette.NameOf(r, g, b)
	local color = palette.Find(r, g, b)
	if color then return ns.L[color.name] end
	local function Byte(v) return math.max(0, math.min(255, math.floor((v or 0) * 255 + 0.5))) end
	return ns.L["Custom %s"]:format(("#%02X%02X%02X"):format(Byte(r), Byte(g), Byte(b)))
end

-- The last colors picked on any color row (newest first, up to 8), kept in
-- the saved settings as { r, g, b } each.
local RECENT_MAX = 8
function palette.Recent()
	local db = ns.GetDB()
	local list = db and db.colorRecent
	return type(list) == "table" and list or {}
end
function palette.Remember(r, g, b)
	local db = ns.GetDB()
	if not (db and r and g and b) then return end
	local list = { { r, g, b } }
	for _, each in ipairs(palette.Recent()) do
		if type(each) == "table" and #list < RECENT_MAX and not Near(each, r, g, b) then list[#list + 1] = each end
	end
	db.colorRecent = list
end

-- The palette's frames (StylePages' edges and fonts, read when built).
local function Gold(edges, on) ns.DressStyleEdges(edges, on and 2 or 1, on and 1 or 0, on and 0.82 or 0, 0, 1) end
palette.Gold = Gold
local function TipOn(frame, text)
	if not text then return end
	GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
	GameTooltip:SetText(text, 1, 1, 1, 1, true)
	GameTooltip:Show()
end
palette.TipOn = TipOn

-- A chip: a square of a color, edged. hover(chip, color or nil) as it's
-- pointed at and left; pick(r, g, b) on a click.
function palette.Chip(parent, size, hover, pick)
	local chip = CreateFrame("Button", nil, parent)
	chip:SetSize(size, size)
	chip.swatch = chip:CreateTexture(nil, "ARTWORK")
	chip.swatch:SetPoint("TOPLEFT", 2, -2)
	chip.swatch:SetPoint("BOTTOMRIGHT", -2, 2)
	chip.edges = ns.MakeStyleEdges(chip)
	chip:SetScript("OnEnter", function(self) hover(self, self.color) end)
	chip:SetScript("OnLeave", function(self)
		hover(self, nil)
		GameTooltip:Hide()
	end)
	chip:SetScript("OnClick", function(self)
		local c = self.color
		if c then pick(c[1], c[2], c[3]) end
	end)
	return chip
end
function palette.Dress(chip, color)
	chip.color = color
	chip.swatch:SetColorTexture(color[1], color[2], color[3], 1)
end

-- The box: a line with the name of the color pointed at (else the one now),
-- every family's shades with their names, Recent, and Custom... now() gives
-- the color now; pick(r, g, b) sets one; custom() opens the color wheel.
-- box:Refresh(), box:ShowName(color), box.buttons (to grey together).
function palette.MakeBox(parent, width, now, pick, custom)
	local box = CreateFrame("Frame", nil, parent)
	box:SetWidth(width)
	box.buttons = {}
	local back = box:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.07, 0.07, 0.08, 0.96)
	ns.DressStyleEdges(ns.MakeStyleEdges(box), 1, 0.42, 0.33, 0.13, 1)
	local nameLine = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	nameLine:SetPoint("TOPLEFT", 10, -8)
	nameLine:SetPoint("RIGHT", -34, 0)
	nameLine:SetJustifyH("LEFT")
	nameLine:SetWordWrap(false)
	function box.ShowName(_, color)
		if color and color.custom then
			nameLine:SetText(palette.NameOf(color[1], color[2], color[3]))
		elseif color then
			nameLine:SetText(ns.L[color.name] .. "  |cff8c8c8c#" .. color.hex .. "|r")
		else
			nameLine:SetText(palette.NameOf(now()))
		end
	end
	local function Hover(_, color) box:ShowName(color) end
	local function Chip(size)
		local chip = palette.Chip(box, size, Hover, pick)
		box.buttons[#box.buttons + 1] = chip
		return chip
	end
	local cells = {}
	local cellW = math.floor((width - 82) / 5)
	local y = -28
	for _, family in ipairs(palette.families) do
		local name = box:CreateFontString(nil, "OVERLAY", ns.LOOK_DIM)
		name:SetPoint("TOPLEFT", 10, y - 4)
		name:SetWidth(60)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		name:SetText(ns.L[family.name])
		for i, color in ipairs(family.shades) do
			-- (A cell: its chip and its name; the whole of it clicks.)
			local cell = Chip(18)
			cell:SetPoint("TOPLEFT", 72 + (i - 1) * cellW, y)
			cell:SetHitRectInsets(0, -(cellW - 22), 0, 0)
			palette.Dress(cell, color)
			local words = cell:CreateFontString(nil, "OVERLAY", ns.LOOK_DIM)
			words:SetPoint("LEFT", cell, "RIGHT", 4, 0)
			words:SetWidth(cellW - 24)
			words:SetJustifyH("LEFT")
			words:SetWordWrap(false)
			words:SetText(ns.L[color.name])
			cells[#cells + 1] = cell
		end
		y = y - 20
	end
	y = y - 6
	local recentHead = box:CreateFontString(nil, "OVERLAY", ns.LOOK_DIM)
	recentHead:SetPoint("TOPLEFT", 10, y)
	recentHead:SetText(ns.L["Recent"])
	local recentNone = box:CreateFontString(nil, "OVERLAY", ns.LOOK_DIM)
	recentNone:SetPoint("TOPLEFT", 10, y - 20)
	recentNone:SetText(ns.L["Colors you pick show here."])
	local recent = {}
	for i = 1, RECENT_MAX do
		local chip = Chip(22)
		chip:SetPoint("TOPLEFT", 10 + (i - 1) * 28, y - 14)
		chip:Hide()
		recent[i] = chip
	end
	local button = CreateFrame("Button", nil, box)
	button:SetSize(90, 22)
	button:SetPoint("TOPRIGHT", -10, y - 14)
	ns.DressStyleEdges(ns.MakeStyleEdges(button), 1, 0.5, 0.5, 0.5, 1)
	local words = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	words:SetPoint("CENTER", 0, 0)
	words:SetText(ns.L["Custom..."])
	button:SetScript("OnClick", function() custom() end)
	button:SetScript("OnEnter", function(self) TipOn(self, ns.L["Pick any color."]) end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	box.buttons[#box.buttons + 1] = button
	box:SetHeight(-(y - 14) + 22 + 10)

	function box.Refresh()
		local r, g, b = now()
		local named = palette.Find(r, g, b)
		for _, cell in ipairs(cells) do Gold(cell.edges, cell.color == named) end
		local list = palette.Recent()
		for i, chip in ipairs(recent) do
			local each = list[i]
			if type(each) == "table" and tonumber(each[1]) and tonumber(each[2]) and tonumber(each[3]) then
				palette.Dress(chip, palette.Find(each[1], each[2], each[3]) or { each[1], each[2], each[3], custom = true })
				Gold(chip.edges, r and Near(chip.color, r, g, b))
				chip:Show()
			else
				chip:Hide()
			end
		end
		recentNone:SetShown(not list[1])
		box:ShowName(nil)
	end
	return box
end

-- The pop-up: the box on its own, at the cursor, for a single swatch
-- (ns.OpenColorPicker, so every swatch that opened the game's color wheel).
-- A pick applies at once; Custom... closes it and opens the wheel (wheel:
-- Options' OpenWheel). A click outside it or Esc closes it.
-- (2026-11-19.)
local pop
function palette.IsOpen() return pop and pop:IsShown() or false end
function palette.Close() if pop then pop:Hide() end end
function palette.Pop(r, g, b, onChange, wheel)
	if not pop then
		pop = CreateFrame("Frame", "CinematicColorPalette", UIParent)
		pop:SetFrameStrata("FULLSCREEN_DIALOG")
		pop:SetClampedToScreen(true)
		pop:EnableMouse(true)
		pop:Hide()
		pop.box = palette.MakeBox(pop, 480, function() return pop.r, pop.g, pop.b end, function(nr, ng, nb)
			pop.r, pop.g, pop.b = nr, ng, nb
			palette.Remember(nr, ng, nb)
			pop.onChange(nr, ng, nb)
			pop.box:Refresh()
		end, function()
			local wr, wg, wb, done, open = pop.r, pop.g, pop.b, pop.onChange, pop.wheel
			pop:Hide()
			open(wr, wg, wb, function(nr, ng, nb)
				palette.Remember(nr, ng, nb)
				done(nr, ng, nb)
			end)
		end)
		pop.box:SetPoint("TOPLEFT", 0, 0)
		pop:SetSize(480, pop.box:GetHeight())
		local close = CreateFrame("Button", nil, pop.box, "UIPanelCloseButton")
		close:SetSize(24, 24)
		close:SetPoint("TOPRIGHT", 0, 0)
		close:SetScript("OnClick", function() pop:Hide() end)
		-- (A click anywhere else: closed. Down, so the click that opened it,
		-- whose OnClick comes on the way up, never closes it.)
		pop:SetScript("OnEvent", function(self)
			if not self:IsMouseOver() then self:Hide() end
		end)
		-- (Esc: closed, and kept from the options behind. Keyboard input is
		-- locked in fights: there, only a click closes it.)
		pop:SetScript("OnKeyDown", function(self, key)
			if InCombatLockdown() then return end
			local esc = key == "ESCAPE"
			pcall(self.SetPropagateKeyboardInput, self, not esc)
			if esc then self:Hide() end
		end)
		pop:SetScript("OnShow", function(self)
			self:RegisterEvent("GLOBAL_MOUSE_DOWN")
			if not InCombatLockdown() then pcall(self.EnableKeyboard, self, true) end
		end)
		pop:SetScript("OnHide", function(self)
			self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
			if not InCombatLockdown() then pcall(self.EnableKeyboard, self, false) end
		end)
	end
	pop.r, pop.g, pop.b = tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1
	pop.onChange, pop.wheel = onChange, wheel
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	pop:ClearAllPoints()
	pop:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale - 4)
	pop.box:Refresh()
	pop:Show()
	pop:Raise()
end

ns.ColorPalette = palette
