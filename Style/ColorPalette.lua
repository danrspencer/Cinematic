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

ns.ColorPalette = palette
