-- Name Style's rows: All names (the page's own plateName<setting> keys),
-- then a row per kind of unit whose names plates draw (ns.NAME_GROUPS'
-- plate rows), each with settings of its own (nameLook<row><setting>).
-- A setting goes row -> All names -> the name theme (NameThemes.lua) -> the
-- game's: a row's or All names' "inherit" hands it on. Colors (<setting>R, G, B) come from the same
-- place as the setting that picks them (Outline color's Custom, say).
-- PlateParts draws names by it (ns.NameLookValue), PlateGuild the line
-- under them; the Name Style page edits it (Options.lua).

local _, ns = ...
local L = ns.L

-- The rows, in the page's order: key (NAME_GROUPS' key; "all": All names),
-- label, and the row each goes by where it sets nothing (parent; none:
-- Default). In order of what they go by (2026-11-16), each under the row it
-- inherits from; depth: how far down (Default 0). Which row a unit takes is
-- decided elsewhere (its group), not by this order.
ns.NAME_ROWS = {
	{ key = "all", label = L["Default"] }, -- (All names until 2026-11-16: the Default row, as the other Style pages')
	{ key = "Target", label = L["Your target"] },
	{ key = "Friends", label = L["Friendly players"] },
	{ key = "GroupMembers", label = L["Group members"], parent = "Friends" },
	{ key = "GroupMinions", label = L["Group members' minions"], parent = "GroupMembers" },
	{ key = "FriendlyMinions", label = L["Friendly players' minions"], parent = "Friends" },
	{ key = "Enemies", label = L["Enemy players"] },
	{ key = "EnemyMinions", label = L["Enemy players' minions"], parent = "Enemies" },
	{ key = "HostileNPCs", label = L["Hostile NPCs"] },
	{ key = "NeutralNPCs", label = L["Neutral NPCs"] },
	{ key = "FriendlyNPCs", label = L["Friendly NPCs"] },
	{ key = "ServiceNPCs", label = L["Service NPCs"], parent = "FriendlyNPCs" },
	-- (Each kind of service NPC by its title, under Service NPCs, 2026-11-16:
	-- PlateGuild's SERVICE_KINDS, "Service" .. its key.)
	{ key = "ServiceVendor", label = L["Vendors"], parent = "ServiceNPCs", service = "Vendor" },
	{ key = "ServiceRepair", label = L["Repair"], parent = "ServiceNPCs", service = "Repair" },
	{ key = "ServiceTrainer", label = L["Trainers"], parent = "ServiceNPCs", service = "Trainer" },
	{ key = "ServiceProfession", label = L["Professions"], parent = "ServiceNPCs", service = "Profession" },
	{ key = "ServiceFlight", label = L["Flight masters"], parent = "ServiceNPCs", service = "Flight" },
	{ key = "ServiceInn", label = L["Innkeepers"], parent = "ServiceNPCs", service = "Inn" },
	{ key = "ServiceBank", label = L["Bankers and auctioneers"], parent = "ServiceNPCs", service = "Bank" },
	{ key = "ServiceStable", label = L["Stable masters"], parent = "ServiceNPCs", service = "Stable" },
	{ key = "ServiceOther", label = L["Other titles"], parent = "ServiceNPCs", service = "Other" },
	{ key = "ServiceQuest", label = L["Quest givers"], parent = "ServiceNPCs", service = "Quest" },
}
local ROW_PARENT, ROW_LABEL = {}, {}
for _, row in ipairs(ns.NAME_ROWS) do ROW_PARENT[row.key] = row.parent end
for _, row in ipairs(ns.NAME_ROWS) do
	local depth, at = 0, row.key
	while at ~= "all" do
		depth = depth + 1
		at = ROW_PARENT[at] or "all"
	end
	row.depth = depth
end
ns.NAME_ROW_PARENT = ROW_PARENT
-- A row's label by key (as shown).
function ns.NameRowLabel(key)
	if not next(ROW_LABEL) then
		for _, row in ipairs(ns.NAME_ROWS) do ROW_LABEL[row.key] = row.label end
	end
	return ROW_LABEL[key]
end
ns.OnLanguage(function()
	ns.TranslateFields(ns.NAME_ROWS, "label")
	ROW_LABEL = {}
end)

-- The settings a row can hand on, and what the game's look gives each (the
-- last step). Font "usual": General's font while the Style hub is on (as
-- these names have always had), else the plate's own.
local GAME = {
	Font = "usual", Size = 1, Alpha = 1, Outline = 0, OutlineColor = "black", Shadow = false, ShadowAlpha = 1,
	Colour = true, Friends = "blue", Enemies = "react", Hostile = "game", Neutral = "game", Friendly = "game",
	Glow = "none", Back = "none", BackAlpha = 0.6, Line2Size = 1, Line2Color = "name",
	-- (2026-11-16: the glow's opacity and size; the band's border, its thickness.)
	GlowAlpha = 0.7, GlowSize = 1, BackBorder = "none", BackBorderSize = 1,
	-- (2026-11-17, the Name / Second line / Behind panel: the second line's
	-- own opacity, and its own letters once it stops matching the name; the
	-- glow and band round the name alone or both lines.)
	Line2Match = true, Line2Alpha = 1, Line2Font = "usual", Line2Outline = 0, Line2OutlineColor = "black",
	Line2Shadow = false, Line2ShadowAlpha = 1, GlowAround = "both", BackAround = "both",
}
ns.NAME_LOOK_GAME = GAME
-- The colors, by the setting that picks them, as they start.
local COLORS = {
	OutlineColor = { 0, 0, 0 }, Colour = { 1, 1, 1 }, Hostile = { 1, 0.25, 0.2 }, Neutral = { 1, 0.9, 0.3 },
	Friendly = { 0.4, 1, 0.4 }, Glow = { 1, 0.82, 0 }, Back = { 0, 0, 0 }, BackBorder = { 1, 0.82, 0 },
	Line2OutlineColor = { 0, 0, 0 }, Line2Color = { 0.72, 0.72, 0.72 },
}
ns.NAME_LOOK_COLORS = COLORS
-- (A color's keys: Outline color's are <prefix>OutlineR..., the rest
-- <prefix><setting>R...)
local function ColorBase(setting) return setting == "OutlineColor" and "Outline" or setting end

-- All names' keys: today's settings (plateNameColour...) and the new ones,
-- every one "inherit" to start (D12: the game's shows through); their
-- colors as COLORS has them.
for setting in pairs(GAME) do ns.DEFAULTS["plateName" .. setting] = "inherit" end
for setting, color in pairs(COLORS) do
	local base = ColorBase(setting)
	ns.DEFAULTS["plateName" .. base .. "R"], ns.DEFAULTS["plateName" .. base .. "G"],
		ns.DEFAULTS["plateName" .. base .. "B"] = color[1], color[2], color[3]
end
-- (Every kind's own settings as they start: "inherit", the colors as All
-- names'. Profiles and the modules ask this for keys with no default:
-- Core's MarkRowDefault.)
local ROW_DEFAULTS = {}
for _, row in ipairs(ns.NAME_ROWS) do
	if row.key ~= "all" then
		for setting in pairs(GAME) do ROW_DEFAULTS["nameLook" .. row.key .. setting] = "inherit" end
		for setting, color in pairs(COLORS) do
			local base = ColorBase(setting)
			for i, part in ipairs({ "R", "G", "B" }) do ROW_DEFAULTS["nameLook" .. row.key .. base .. part] = color[i] end
		end
	end
end
function ns.NameRowDefault(key) return ROW_DEFAULTS[key] end
-- (A row's settings' keys, for its page's RecordKey.)
function ns.NameRowKeys(row)
	local list = {}
	local prefix = row == "all" and "plateName" or "nameLook" .. row
	for setting in pairs(GAME) do list[#list + 1] = prefix .. setting end
	for setting in pairs(COLORS) do
		local base = ColorBase(setting)
		for _, part in ipairs({ "R", "G", "B" }) do list[#list + 1] = prefix .. base .. part end
	end
	table.sort(list)
	return list
end

-- A setting's key on a row.
function ns.NameLookKey(row, setting)
	return (row == "all" and "plateName" or "nameLook" .. row) .. setting
end

local function Raw(row, setting)
	local key = ns.NameLookKey(row, setting)
	local value = ns.db and ns.db[key]
	if value == nil then
		if row == "all" then value = ns.DEFAULTS[key] else value = ROW_DEFAULTS[key] end
	end
	return value
end

-- A setting as a row has it: row -> All names -> the name theme -> the
-- game's. Gives the value and where it's from: the row's key, "all",
-- "theme" or "game". row nil: All names'.
-- over: { setting = value } on top of the row's own (the Look panel's
-- preview: never saved; "inherit" there hands on as saved).
-- (Up the rows it inherits from before Default (2026-11-16): Service NPCs
-- by Friendly NPCs', Group members by Friendly players'...: NAME_ROWS' parent.)
-- (Your target over its own kind's row, 2026-11-16: "Target:HostileNPCs"
-- is your target that's a hostile NPC: Your target's, then Hostile NPCs' and
-- the rows above it, then Default's.)
function ns.NameLookValue(row, setting, over)
	local under
	if type(row) == "string" then
		local target, kind = row:match("^(Target):(.+)$")
		if target then row, under = target, kind end
	end
	local at = row ~= "all" and row or nil
	while at do
		local value
		if at == row and over then value = over[setting] end
		if value == nil then value = Raw(at, setting) end
		if value ~= "inherit" then return value, at end
		at = ROW_PARENT[at] or (at == row and under) or nil
	end
	-- (over only for All names' own panel. Not "row == 'all' and over and ...":
	-- for a kind's row that's false, not nil, and every setting came out false.)
	local value
	if row == "all" and over then value = over[setting] end
	if value == nil then value = Raw("all", setting) end
	if value ~= "inherit" then return value, "all" end
	local themed = ns.NameThemeLook and ns.NameThemeLook()
	if themed and themed[setting] ~= nil then return themed[setting], "theme" end
	return GAME[setting], "game"
end

-- A color as the row has it: from the same place as the setting that picks
-- it (a row's Custom outline: that row's color). over as NameLookValue's.
function ns.NameLookColor(row, setting, over)
	local _, from = ns.NameLookValue(row, setting, over)
	local color = COLORS[setting]
	if from == "game" then return color[1], color[2], color[3] end
	local base = ColorBase(setting)
	if from == "theme" then
		local themed = ns.NameThemeLook()
		return tonumber(themed[base .. "R"]) or color[1], tonumber(themed[base .. "G"]) or color[2],
			tonumber(themed[base .. "B"]) or color[3]
	end
	local function Part(i, part)
		local value
		if over and from == (row or "all") then value = over[base .. part] end
		if value == nil then value = ns.db and ns.db[ns.NameLookKey(from, base .. part)] end
		return tonumber(value) or color[i]
	end
	return Part(1, "R"), Part(2, "G"), Part(3, "B")
end

-- Whether any kind's row has a setting of its own (none: every name goes by
-- All names, no unit sorted). Worked out again after a change.
local anyOwn
function ns.NameRowsChanged()
	anyOwn = nil
	if ns.ResetNameRows then ns.ResetNameRows() end
end
function ns.NameRowsOwn()
	if anyOwn == nil then
		anyOwn = false
		local db = ns.db or {}
		for key, default in pairs(ROW_DEFAULTS) do
			if default == "inherit" and db[key] ~= nil and db[key] ~= "inherit" then
				anyOwn = true
				break
			end
		end
	end
	return anyOwn
end

-- Which row a unit's name goes by: your target, a group member or their
-- minion, a Service NPC, else its kind's row; "all" when the game won't say
-- (secret values). Kept per unit frame until the target, the group or the
-- plate's unit changes.
local function Known(value) return not (issecretvalue and issecretvalue(value)) end
local function Ask(fn, ...)
	local ok, value = pcall(fn, ...)
	return ok and Known(value) and value and true or false
end
local KIND_ROW = {
	Friends = "Friends", FriendlyMinions = "FriendlyMinions", Enemies = "Enemies", EnemyMinions = "EnemyMinions",
	EnemyNPCs = "HostileNPCs", NeutralNPCs = "NeutralNPCs", EnemyMinor = "HostileNPCs", NeutralMinor = "NeutralNPCs",
	FriendlyNPCs = "FriendlyNPCs",
}
local rowOf = setmetatable({}, { __mode = "k" }) -- [unit frame] = { unit, row }
local function KindRow(plate, unit)
	local kind = ns.PlateKind and ns.PlateKind(unit)
	if not kind then return "all" end
	if (kind == "Friends" or kind == "FriendlyMinions") and not Ask(UnitIsUnit, unit, "pet")
		and (Ask(UnitPlayerOrPetInParty, unit) or Ask(UnitPlayerOrPetInRaid, unit)) then
		return kind == "Friends" and "GroupMembers" or "GroupMinions"
	end
	if (kind == "FriendlyNPCs" or kind == "NeutralNPCs" or kind == "NeutralMinor") and ns.PlateServiceMatch then
		local ok, match = pcall(ns.PlateServiceMatch, plate, unit)
		if ok and match then
			-- (Its kind's row by its title, else Service NPCs': PlateGuild.lua.)
			local okKind, service = pcall(ns.PlateServiceKind or function() end, plate, unit)
			return okKind and service and "Service" .. service or "ServiceNPCs"
		end
	end
	return KIND_ROW[kind] or "all"
end
-- (Your target: on top of its kind's row, "Target:<row>" (NameLookValue).)
local function Sort(plate, unit)
	if Ask(UnitIsUnit, unit, "target") then
		local under = KindRow(plate, unit)
		return under ~= "all" and "Target:" .. under or "Target"
	end
	return KindRow(plate, unit)
end
function ns.NameRowOf(unitFrame, unit)
	if not ns.NameRowsOwn() or not unit then return "all" end
	local kept = rowOf[unitFrame]
	if kept and kept.unit == unit then return kept.row end
	local row = Sort(unitFrame and unitFrame:GetParent(), unit)
	-- (Not kept while the game won't say: asked again next time.)
	if row ~= "all" then rowOf[unitFrame] = { unit = unit, row = row } end
	return row
end
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "NAME_PLATE_UNIT_ADDED",
	"NAME_PLATE_UNIT_REMOVED" }) do
	watcher:RegisterEvent(event)
end
watcher:SetScript("OnEvent", function(_, event, unit)
	if not next(rowOf) then return end
	-- (A plate coming or going: only its own row asked again, its name drawn
	-- anew. Every plate's, each of the ~100 a second turning in a crowd, was
	-- the top cost there: 2026-11-17.)
	if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
		local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
		local plate = get and get(unit)
		local unitFrame = plate and plate.UnitFrame
		if unitFrame and rowOf[unitFrame] then
			rowOf[unitFrame] = nil
			if event == "NAME_PLATE_UNIT_ADDED" and ns.DirtyPlateName then
				ns.DirtyPlateName(plate)
				if ns.ApplyPlateNow then ns.ApplyPlateNow(plate) end
			end
		end
		return
	end
	wipe(rowOf)
	-- (Our names drawn again, in their new rows' looks.)
	if ns.RefreshPlateNameStyle then ns.RefreshPlateNameStyle() end
end)
function ns.ResetNameRows() wipe(rowOf) end

-- D12: today's settings with an "inherit" value of their own now: a value
-- still at the old default goes to it (nothing seen changes: the game's
-- look gives the same), in every profile. Once.
local OLD = { plateNameColour = true, plateNameFriends = "blue", plateNameOutline = 0, plateNameSize = 1,
	plateNameAlpha = 1, plateNameShadow = false, plateNameShadowAlpha = 1 }
function ns.MigrateNameInherit()
	local db = ns.db
	if not db or db.nameInheritV1 then return end
	local function Move(t)
		if type(t) ~= "table" then return end
		for key, old in pairs(OLD) do
			if t[key] == old then t[key] = nil end
		end
	end
	Move(db)
	for _, saved in pairs(db.profiles or {}) do
		if type(saved) == "table" then Move(type(saved.settings) == "table" and saved.settings or saved) end
	end
	db.nameInheritV1 = true
end

-- The second line's letters as a row has them (the plates' and the Name
-- Style preview's, 2026-11-17): the name's while it matches the name
-- (Line2Match), else its own. S(setting): the row's value. Gives { font,
-- outline, rim (an outline in a color of its own), colorSetting (the rim's:
-- NameLookColor's), shadow, shadowAlpha, alpha }.
function ns.NameLine2Look(S)
	local own = S("Line2Match") == false
	local prefix = own and "Line2" or ""
	local outline = tonumber(S(prefix .. "Outline")) or 0
	return {
		own = own,
		font = S(prefix .. "Font"),
		outline = outline,
		rim = outline > 0 and S(prefix .. "OutlineColor") == "custom",
		colorSetting = prefix .. "OutlineColor",
		shadow = S(prefix .. "Shadow") == true,
		shadowAlpha = tonumber(S(prefix .. "ShadowAlpha")) or 1,
		alpha = tonumber(S("Line2Alpha")) or 1,
	}
end

-- A name's glow, band and the band's border, placed round its text (the
-- plates' and the Name Style preview's, 2026-11-16). parts: { glow, back,
-- edges (four textures, made here) } on owner; S(setting): the row's value;
-- Color(setting): its r, g, b. width, height: the text's, scaled.
-- below: the second line under it, { width, height, nameHidden } scaled,
-- or nil: the glow and band round what shows while GlowAround / BackAround
-- say so ("both", What shows): both lines, or the line alone while the name
-- is hidden (a Service NPC's title shown alone; your target's name comes in
-- over it). A piece round the line alone gets .followsLine: it fades with
-- the line, not the hidden name (PlateParts' DressShown). 2026-11-17.
-- (Glow strength past 100%: a second glow over the first, 2026-11-17.)
function ns.DressNameParts(owner, parts, text, width, height, S, Color, below)
	local glow, back = S("Glow"), S("Back")
	-- (Round both lines: as wide as the wider, as tall as both, its middle
	-- between them. The line hangs 1 under the name. Round the line alone:
	-- its middle a half name, the gap and a half line down. Gives the box,
	-- how far down its middle is, the glow's padding and whether it's the
	-- line's alone.)
	local function Box(around)
		if below and around ~= "name" then
			if below.nameHidden then
				return below.width, below.height, -(height / 2 + 1 + below.height / 2), below.height, true
			end
			return math.max(width, below.width), height + below.height + 1, -(below.height + 1) / 2, height, false
		end
		return width, height, 0, height, false
	end
	parts.glow:SetShown(glow ~= "none")
	local strength = tonumber(S("GlowAlpha")) or 0.7
	if strength > 1 and glow ~= "none" and not parts.glow2 then
		local layer, sub = parts.glow:GetDrawLayer()
		parts.glow2 = owner:CreateTexture(nil, layer, nil, sub)
		parts.glow2:SetTexture(ns.NAME_GLOW)
		parts.glow2:SetBlendMode("ADD")
	end
	if parts.glow2 then parts.glow2:SetShown(glow ~= "none" and strength > 1) end
	if glow ~= "none" then
		local r, g, b = Color("Glow")
		local size = tonumber(S("GlowSize")) or 1
		local w, h, y, pad, lineOnly = Box(S("GlowAround"))
		local pieces = { parts.glow }
		if strength > 1 then pieces[2] = parts.glow2 end
		for i, piece in ipairs(pieces) do
			piece:SetVertexColor(r, g, b, i == 1 and math.min(1, strength) or strength - 1)
			piece:ClearAllPoints()
			piece:SetPoint("CENTER", text, "CENTER", 0, y)
			piece:SetSize(w + pad * 3 * size, (h + pad * 2) * size)
			piece.followsLine = lineOnly
		end
	end
	parts.back:SetShown(back ~= "none")
	if back ~= "none" then
		local r, g, b = Color("Back")
		local w, h, y, _, lineOnly = Box(S("BackAround"))
		parts.back:SetColorTexture(r, g, b, tonumber(S("BackAlpha")) or 0.6)
		parts.back:ClearAllPoints()
		parts.back:SetPoint("CENTER", text, "CENTER", 0, y)
		parts.back:SetSize(w + 14, h + 6)
		parts.back.followsLine = lineOnly
	end
	-- (The band's border: a line round it, its thickness and color.)
	local edged = back ~= "none" and S("BackBorder") == "line"
	if edged and not parts.edges then
		parts.edges = {}
		for i = 1, 4 do parts.edges[i] = owner:CreateTexture(nil, "BACKGROUND", nil, 3) end
	end
	for i, edge in ipairs(parts.edges or {}) do
		edge:SetShown(edged)
		edge.followsLine = parts.back.followsLine -- (faded with the band)
		if edged then
			local r, g, b = Color("BackBorder")
			local thick = math.max(1, tonumber(S("BackBorderSize")) or 1)
			edge:SetColorTexture(r, g, b, 1)
			edge:ClearAllPoints()
			if i <= 2 then
				edge:SetPoint(i == 1 and "BOTTOMLEFT" or "TOPLEFT", parts.back, i == 1 and "TOPLEFT" or "BOTTOMLEFT", -thick, 0)
				edge:SetPoint(i == 1 and "BOTTOMRIGHT" or "TOPRIGHT", parts.back, i == 1 and "TOPRIGHT" or "BOTTOMRIGHT", thick, 0)
				edge:SetHeight(thick)
			else
				edge:SetPoint(i == 3 and "TOPRIGHT" or "TOPLEFT", parts.back, i == 3 and "TOPLEFT" or "TOPRIGHT", 0, 0)
				edge:SetPoint(i == 3 and "BOTTOMRIGHT" or "BOTTOMLEFT", parts.back, i == 3 and "BOTTOMLEFT" or "BOTTOMRIGHT", 0, 0)
				edge:SetWidth(thick)
			end
		end
	end
end
