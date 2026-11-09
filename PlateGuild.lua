-- Cinematic: players' guilds and NPCs' titles under their names on plates
-- showing their name alone (CineMode, away from dungeons and raids). There
-- the name sits on the plate in place of the one over the unit's head, which
-- the game takes away with its second line: this puts that line back. A
-- guild as far as the Names grid's Guild names row keeps guilds up
-- (ns.plateGuildLevel, from Effects) and the name shows; an NPC's title
-- (<Innkeeper>) wherever its name shows, as over heads. Drawn like the name
-- above it: its font, colour, shadow and size.
local _, ns = ...
local L = ns.L

local lines = {} -- [plate] = guild text
local shares = {} -- [plate] = how far its name shows on a name-only plate (0 to 1)
-- [plate] = its NPC's title, or false for none; nil not read yet (or the
-- game wouldn't say: read again in a while, or after the fight).
local titles = {}
local titleTried = {} -- [plate] = when its title was last asked for and not given
local titleUnit = {} -- [plate] = the GUID its title is for (a plate given a new unit reads it anew)
local serviceMatch = {} -- [plate] = whether its title fits a Service NPCs kind ticked; nil not worked out yet
local TITLE_RETRY = 2 -- seconds
local ServiceIcon -- (below: the Icons tick's icon for a title)
local titleIcons = {} -- [title] = its Icons tick's icon file, or false for none
local SERVICE_ICON_SIZE = 20 -- (its height on plates, before the name's scale)
-- (Times Service NPCs' Icons size slider, nameServiceIconScale.)
local function IconSize()
	local scale = tonumber(ns.db.nameServiceIconScale) or 1
	return math.max(4, math.floor(SERVICE_ICON_SIZE * scale + 0.5))
end

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function Usable(frame)
	return type(frame) == "table" and frame.SetAlpha and not (frame.IsForbidden and frame:IsForbidden())
end

-- The unit's guild as the game writes it under names, or nil.
local function GuildText(unit)
	local ok, guild = pcall(GetGuildInfo, unit)
	if not ok or type(guild) ~= "string" then
		return nil
	end
	if issecretvalue and issecretvalue(guild) then
		return nil
	end
	return guild ~= "" and ("<" .. guild .. ">") or nil
end

-- Whether a unit is a player (by its GUID: on WoW Forever UnitIsPlayer can
-- say no for players after a buff).
local function IsPlayer(unit)
	local ok, guid = pcall(UnitGUID, unit)
	if ok and Known(guid) and type(guid) == "string" then
		return guid:find("^Player%-") ~= nil
	end
	local okPlayer, player = pcall(UnitIsPlayer, unit)
	return okPlayer and Known(player) and player and true or false
end

-- Where the game has no tooltip data (Classic Era): a hidden tooltip of our
-- own, its second line read straight after.
local scanTip
local function ScanLine2(unit)
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "CinematicTitleScanTip", nil, "GameTooltipTemplate")
	end
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanTip:SetUnit(unit)
	local line = _G.CinematicTitleScanTipTextLeft2
	local text = scanTip:NumLines() >= 2 and line and line:GetText() or nil
	scanTip:Hide()
	return text
end

-- An NPC's title as the game writes it under its name (<Innkeeper>): the
-- second line of its tooltip, unless that's its level line ("Level 30
-- Humanoid": no title). false for none, nil when the game won't say (no
-- tooltip data, a secret line). Pets, totems and other units players control
-- have none (their second line is their owner's).
local function NPCTitle(unit)
	local tooltipData = C_TooltipInfo and C_TooltipInfo.GetUnit
	if not tooltipData and not (GameTooltip and GameTooltip.SetUnit) then
		return false
	end
	local okControlled, controlled = pcall(UnitPlayerControlled, unit)
	if okControlled and Known(controlled) and controlled then
		return false
	end
	local ok, title = pcall(function()
		local text
		if tooltipData then
			local data = C_TooltipInfo.GetUnit(unit)
			local line = data and type(data.lines) == "table" and data.lines[2]
			if not line then
				return false
			end
			text = line.leftText
		else
			text = ScanLine2(unit)
		end
		if not Known(text) then
			return nil
		end
		if type(text) ~= "string" or text == "" or (LEVEL and text:find(LEVEL, 1, true)) then
			return false
		end
		return "<" .. text .. ">"
	end)
	if ok then
		return title
	end
	return nil
end

-- A plate's NPC's title (<Innkeeper>), read once per unit it's given (again
-- in a while if the game wouldn't say). nil for none, or not known yet.
local function PlateTitle(plate, unit)
	-- (Asked before the plate's new-unit event reaches us: its last unit's forgotten here.)
	local ok, guid = pcall(UnitGUID, unit)
	guid = ok and Known(guid) and guid or nil
	if guid and titleUnit[plate] ~= guid then
		titles[plate], titleTried[plate], serviceMatch[plate] = nil, nil, nil
		titleUnit[plate] = guid
	end
	if titles[plate] == nil and GetTime() - (titleTried[plate] or -TITLE_RETRY) >= TITLE_RETRY then
		titles[plate] = NPCTitle(unit)
		titleTried[plate] = titles[plate] == nil and GetTime() or nil
	end
	return titles[plate] or nil
end

-- The line under a plate's name: its player's guild or its NPC's title, and
-- whether it's a guild (with the Guild names row, then).
local function LineText(plate, unit)
	if IsPlayer(unit) then
		return GuildText(unit), true
	end
	local title = PlateTitle(plate, unit)
	-- (Service NPCs' Icons ticked: its kind's icon in its place; a title of
	-- no kind with one, none: just the name.)
	if title and ns.db.nameServiceIcons then
		local icon = ServiceIcon(title)
		if not icon then
			return nil, false
		end
		-- (One size for all, IconSize: not by the name's font, which
		-- differs plate to plate, or can't be read and left the icon small.)
		return icon, false, true
	end
	-- (Service NPCs' Brackets unticked: Baker, not <Baker>.)
	if title and not ns.db.nameServiceBrackets then
		title = title:sub(2, -2)
	end
	return title, false
end

-- The Names grid's Service NPCs row's kinds (its Kinds menu, settings
-- nameService<key>), each with the words that mark it in a title: a comma
-- list, matched anywhere in the title, Latin letters in any case. Other: any
-- title none of the others' words are in.
-- (Translators: the words as the game's NPC titles have them in your
-- language, comma separated: "Repair Vendor", "Innkeeper"...)
ns.SERVICE_KINDS = {
	{ key = "Vendor", label = L["Vendors"], words = L["vendor,merchant,goods,supplies,supplier,provisions," ..
		"provisioner,quartermaster,reagents,trader,armorer,weaponsmith,bowyer,gunsmith,butcher,baker,food,drink,wine"] },
	{ key = "Repair", label = L["Repair"], words = L["repair"] },
	-- (Weapon Masters teach weapon skills but have no "trainer" in their title.)
	{ key = "Trainer", label = L["Trainers"], words = L["trainer,weapon master"] },
	-- (Word stems: Fisherman and Fishing, Enchanter and Enchanting...)
	{ key = "Profession", label = L["Professions"], words = L["fish,cook,first aid,alchem,herbal,mining,miner," ..
		"skinn,blacksmith,leatherwork,tailor,enchant,engineer,jewelcraft,inscription,scribe,archaeolog"] },
	{ key = "Flight", label = L["Flight masters"], words = L["flight,gryphon master,wind rider master," ..
		"hippogryph master,bat handler,dragonhawk master"] },
	{ key = "Inn", label = L["Innkeepers"], words = L["innkeeper"] },
	{ key = "Bank", label = L["Bankers and auctioneers"], words = L["banker,auctioneer,bank,auction"] },
	{ key = "Stable", label = L["Stable masters"], words = L["stable"] },
	{ key = "Other", label = L["Other titles"] },
	-- Not by title (most quest givers have none): an NPC with a quest for you
	-- to pick up or hand in, by the game's quest cursor over them (QuestGlow's
	-- ns.UnitQuestGiver), or by Questie's "!" and "?" with Use Questie DB
	-- ticked (nameServiceQuestie). See PlateQuestGiver.
	{ key = "Quest", label = L["Quest givers"], noTitle = true },
}
-- (For /cine debug names: a plate's title and the kinds it fits.)
function ns.DescribePlateTitle(plate, unit)
	if not plate or not unit then
		return "title=?"
	end
	local cursor = ns.UnitQuestGiver and ns.UnitQuestGiver(unit)
	local questie = ns.QuestieGiverNames and ns.QuestieGiverNames()
	local okName, name = pcall(UnitName, unit)
	local inQuestie = questie and okName and Known(name) and questie[name] == true
	local quest = ("quest=%s cursor=%s questie=%s"):format(ns.db.nameServiceQuest and "+" or "-", tostring(cursor),
		questie and tostring(inQuestie) .. (ns.db.nameServiceQuestie and "(used)" or "(not used)") or "n/a")
	local title = PlateTitle(plate, unit)
	if not title then
		return "title=" .. tostring(titles[plate]) .. " " .. quest
	end
	local kinds, fits = {}, ns.TitleKinds(title)
	for _, kind in ipairs(ns.SERVICE_KINDS) do
		if fits[kind.key] then
			kinds[#kinds + 1] = kind.key .. (ns.db["nameService" .. kind.key] and "+" or "-")
		end
	end
	return ("title=%s kinds=%s icon=%s %s"):format(title, table.concat(kinds, ","),
		tostring(ns.db.nameServiceIcons and ServiceIcon(title) or "-"), quest)
end

-- From the Kinds menu (and a new language): every plate's match worked out again.
function ns.ServiceKindsChanged()
	wipe(serviceMatch)
	wipe(titleIcons)
end

ns.OnLanguage(function()
	ns.TranslateFields(ns.SERVICE_KINDS, "label", "words")
	for _, kind in ipairs(ns.SERVICE_KINDS) do
		kind.list = nil -- (read again in the new language)
	end
	ns.ServiceKindsChanged()
end)

-- The kinds a title fits, each one's key true (none: Other).
function ns.TitleKinds(title)
	local lower, fits = title:lower(), {}
	for _, kind in ipairs(ns.SERVICE_KINDS) do
		if kind.words and not kind.list then
			kind.list = {}
			for word in kind.words:gmatch("[^,]+") do
				word = word:match("^%s*(.-)%s*$")
				if word ~= "" then
					kind.list[#kind.list + 1] = word:lower()
				end
			end
		end
		for _, word in ipairs(kind.list or {}) do
			if lower:find(word, 1, true) then
				fits[kind.key] = true
				break
			end
		end
	end
	if next(fits) == nil then
		fits.Other = true
	end
	return fits
end

-- Trainers' Your class only (nameServiceClassOnly): whether a title names a
-- class other than yours (<Hunter Trainer> for a druid), by the game's class
-- names, longest first and taken out as found ("Demon Hunter" isn't a
-- hunter's). Pet and demon trainers go with hunters and warlocks.
local classWords
local function OtherClassTitle(title)
	if not classWords then
		classWords = {}
		for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
			for class, name in pairs(names) do
				if type(name) == "string" and name ~= "" then
					classWords[#classWords + 1] = { word = name:lower(), class = class }
				end
			end
		end
		classWords[#classWords + 1] = { word = L["pet trainer"]:lower(), class = "HUNTER" }
		classWords[#classWords + 1] = { word = L["demon trainer"]:lower(), class = "WARLOCK" }
		table.sort(classWords, function(a, b) return #a.word > #b.word end)
	end
	local _, mine = UnitClass("player")
	local lower, other = title:lower(), false
	for _, entry in ipairs(classWords) do
		local from, to = lower:find(entry.word, 1, true)
		if from then
			if entry.class == mine then
				return false
			end
			other = true
			lower = lower:sub(1, from - 1) .. lower:sub(to + 1)
		end
	end
	return other
end
ns.OnLanguage(function() classWords = nil end)

-- Service NPCs' Icons tick (nameServiceIcons): each kind's icon, shown in
-- place of the title. Picked in this order where a title fits more than one
-- (<Repair Vendor>: Repair), among the kinds ticked; Other has none (just the
-- name shows). Each a list of files, the first this client has: the minimap
-- tracking menu's icons, else the game's cursors.
local TRACKING, CURSOR = "Interface\\Minimap\\Tracking\\", "Interface\\Cursor\\"
local SERVICE_ICONS = {
	{ "Repair", { TRACKING .. "Repair", CURSOR .. "Repair" } },
	-- (Before Trainers: <Blacksmithing Trainer> gets the anvil, not the book.)
	{ "Profession", { TRACKING .. "Profession", CURSOR .. "Trainer" } },
	{ "Trainer", { TRACKING .. "Class", CURSOR .. "Trainer" } },
	{ "Flight", { TRACKING .. "FlightMaster", CURSOR .. "Taxi" } },
	{ "Inn", { TRACKING .. "Innkeeper", CURSOR .. "Innkeeper" } },
	{ "Bank", { TRACKING .. "Banker", TRACKING .. "Auctioneer", CURSOR .. "Buy" } },
	{ "Stable", { TRACKING .. "StableMaster", CURSOR .. "Interact" } },
	{ "Vendor", { CURSOR .. "Buy" } },
}
-- Professions: each its own icon (the game's spell icons, edges cropped), by
-- the words of its title (as the Professions kind's words; translators: as
-- your language's titles have them). One none fits: the kind's icon.
local ICONS = "Interface\\Icons\\"
local PROFESSION_ICONS = {
	{ L["alchem"], { ICONS .. "Trade_Alchemy" } },
	{ L["blacksmith"], { ICONS .. "Trade_BlackSmithing" } },
	{ L["enchant"], { ICONS .. "Trade_Engraving" } },
	{ L["engineer"], { ICONS .. "Trade_Engineering" } },
	{ L["herbal"], { ICONS .. "Trade_Herbalism", ICONS .. "Spell_Nature_NatureTouchGrow" } },
	{ L["inscription,scribe"], { ICONS .. "INV_Inscription_Tradeskill01", ICONS .. "INV_Feather_05" } },
	{ L["jewelcraft"], { ICONS .. "INV_Misc_Gem_01" } },
	{ L["leatherwork"], { ICONS .. "Trade_LeatherWorking", ICONS .. "INV_Misc_ArmorKit_17" } },
	{ L["mining,miner"], { ICONS .. "Trade_Mining" } },
	{ L["skinn"], { ICONS .. "INV_Misc_Pelt_Wolf_01" } },
	{ L["tailor"], { ICONS .. "Trade_Tailoring" } },
	{ L["fish"], { ICONS .. "Trade_Fishing" } },
	{ L["cook"], { ICONS .. "INV_Misc_Food_15" } },
	{ L["first aid"], { ICONS .. "Spell_Holy_SealOfSacrifice" } },
	{ L["archaeolog"], { ICONS .. "Trade_Archaeology" } },
}
local CROP = ":0:0:64:64:5:59:5:59" -- (a spell icon's border trimmed)

-- The first of a list of files this client has, or nil.
local fileFound = {} -- [list] = its file, or false
local function FirstFile(list)
	if fileFound[list] == nil then
		fileFound[list] = false
		for _, file in ipairs(list) do
			local ok, id = true, true
			if GetFileIDFromPath then
				ok, id = pcall(GetFileIDFromPath, file)
			end
			if ok and id then
				fileFound[list] = file
				break
			end
		end
	end
	return fileFound[list] or nil
end

local function ProfessionIcon(lower)
	for _, entry in ipairs(PROFESSION_ICONS) do
		for word in entry[1]:gmatch("[^,]+") do
			word = word:match("^%s*(.-)%s*$"):lower()
			if word ~= "" and lower:find(word, 1, true) then
				local file = FirstFile(entry[2])
				return file and ("|T%s:%d:%d" .. CROP .. "|t"):format(file, IconSize(), IconSize())
			end
		end
	end
end

-- The icon for a title, as text for a font string ("|T...|t"), or nil.
function ServiceIcon(title)
	local icon = titleIcons[title]
	if icon == nil then
		icon = false
		local fits = ns.TitleKinds(title)
		local otherClass = ns.db.nameServiceClassOnly and OtherClassTitle(title)
		for _, entry in ipairs(SERVICE_ICONS) do
			local key = entry[1]
			if fits[key] and ns.db["nameService" .. key] and not (key == "Trainer" and otherClass) then
				icon = key == "Profession" and ProfessionIcon(title:lower()) or false
				if not icon then
					local file = FirstFile(entry[2])
					icon = file and ("|T%s:%d:%d|t"):format(file, IconSize(), IconSize()) or false
				end
				if icon then break end
			end
		end
		titleIcons[title] = icon
	end
	return icon or nil
end

-- The Quest givers kind: whether a plate's NPC has a quest for you, to pick up
-- or hand in. Asked again every QUEST_EVERY seconds (taking or handing in a
-- quest changes it), or as the plate gets a new unit.
local QUEST_EVERY = 1
local questAt, questIs, questUnit = {}, {}, {}
local function PlateQuestGiver(plate, unit)
	local ok, guid = pcall(UnitGUID, unit)
	guid = ok and Known(guid) and guid or nil
	local now = GetTime()
	if questUnit[plate] == guid and now - (questAt[plate] or -QUEST_EVERY) < QUEST_EVERY then
		return questIs[plate]
	end
	questUnit[plate], questAt[plate] = guid, now
	local giver = false
	local questie = ns.db.nameServiceQuestie == true and ns.QuestieGiverNames and ns.QuestieGiverNames()
	if questie then
		-- (Questie's own settings decide: its level filter, for one.)
		local okName, name = pcall(UnitName, unit)
		giver = okName and Known(name) and type(name) == "string" and questie[name] == true or false
	elseif ns.UnitQuestGiver then
		giver = ns.UnitQuestGiver(unit) ~= nil
	end
	questIs[plate] = giver
	return giver
end

-- Whether a plate's NPC is of a kind the Service NPCs row keeps (for
-- Effects: friendly and neutral NPCs): a title of a ticked kind (known titles
-- only), or a quest for you with Quest givers ticked. Its second value: true
-- when only the quest counts, so its name shows rather than its title (most
-- quest givers have none).
function ns.PlateServiceMatch(plate, unit)
	if not plate or not unit then
		return false
	end
	local match = serviceMatch[plate]
	if match == nil then
		local title = PlateTitle(plate, unit)
		if title then
			match = false
			local otherClass = ns.db.nameServiceClassOnly and OtherClassTitle(title)
			for key in pairs(ns.TitleKinds(title)) do
				if ns.db["nameService" .. key] and not (key == "Trainer" and otherClass) then
					match = true
					break
				end
			end
			serviceMatch[plate] = match
		end
		-- (No title, or not known yet: asked again in a while.)
	end
	if match then
		-- (Icons ticked: a title without one, Other's, shows the name instead.)
		if ns.db.nameServiceIcons then
			local title = PlateTitle(plate, unit)
			return true, not (title and ServiceIcon(title))
		end
		return true, false
	end
	if ns.db.nameServiceQuest and PlateQuestGiver(plate, unit) then
		return true, true
	end
	return false
end

local function Hide(plate)
	if lines[plate] then
		lines[plate]:Hide()
	end
end

local function Refresh(plate)
	local share = shares[plate] or 0
	local unitFrame = plate.UnitFrame
	-- (Under our own text for the name where it's drawn: PlateParts.)
	local name = Usable(unitFrame) and (ns.PlateNameText and ns.PlateNameText(plate) or unitFrame.name)
	local unit = plate.namePlateUnitToken or (Usable(unitFrame) and unitFrame.unit)
	if share <= 0 or not unit or not Usable(name) or not name.GetFont then
		Hide(plate)
		return
	end
	local text, guild, isIcon = LineText(plate, unit)
	if guild then
		share = share * (ns.plateGuildLevel or 0)
	end
	if not text or share <= 0 then
		Hide(plate)
		return
	end
	local line = lines[plate]
	if not line then
		line = unitFrame:CreateFontString(nil, "OVERLAY")
		lines[plate] = line
	end
	-- (Its parent can change with the plate's unit frame: anchored anew each time.)
	-- Always under the name, even while the name's text is faded out (Titles
	-- only): it stays put as the name comes up (your target), rather than
	-- moving up into the name's place and back down a line.
	line:ClearAllPoints()
	line:SetPoint("TOP", name, "BOTTOM", 0, -1)
	-- (Its font object, not its file: a file has one alphabet, and a guild in
	-- another, Cyrillic say, would show as boxes. The name's is a family.)
	local object = name.GetFontObject and name:GetFontObject()
	if object then
		line:SetFontObject(object)
	else
		local file, size, flags = name:GetFont()
		if file then
			pcall(line.SetFont, line, file, size, flags)
		end
	end
	pcall(function()
		line:SetShadowOffset(name:GetShadowOffset())
		line:SetShadowColor(name:GetShadowColor())
		-- (With the name's health fill on, its own text is the grey part: the
		-- colored copy's color instead.)
		local source = ns.PlateNameLit and ns.PlateNameLit(name) or name
		local r, g, b = source:GetTextColor()
		-- (An icon in its own colors.)
		if isIcon then r, g, b = 1, 1, 1 end
		line:SetTextColor(r, g, b)
		if line.SetVertexColor then line:SetVertexColor(r, g, b) end
		if name.GetScale then line:SetScale(name:GetScale()) end
	end)
	line:SetText(text)
	line:SetAlpha(share)
	line:Show()
end

-- From PlateParts, each time it lays out a plate: how far its name shows
-- while the plate shows its name alone (0: not name-only). (Its name's own
-- text faded for Service NPCs' Titles only is PlateParts' doing: the line
-- stays under it either way.)
function ns.SetPlateGuild(plate, share)
	shares[plate] = share > 0 and share or nil
	if shares[plate] or lines[plate] then
		Refresh(plate)
	end
end

-- From Effects, as the Guild names row fades guilds up or down.
function ns.RefreshPlateGuilds()
	for plate in pairs(shares) do
		Refresh(plate)
	end
end

-- A plate let go of hides its line; a guild read late (or changed) shows.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watcher:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
watcher:RegisterEvent("UNIT_NAME_UPDATE")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event, unit)
	-- (After a fight: titles the game wouldn't give in it, asked for again.)
	if event == "PLAYER_REGEN_ENABLED" then
		wipe(titleTried)
		for plate in pairs(shares) do
			Refresh(plate)
		end
		return
	end
	if not (type(unit) == "string" and unit:find("^nameplate") and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end
	-- (A plate given a new unit, or let go of: its title read afresh.)
	if event ~= "UNIT_NAME_UPDATE" then
		titles[plate], titleTried[plate], serviceMatch[plate], titleUnit[plate] = nil, nil, nil, nil
	end
	if event == "NAME_PLATE_UNIT_REMOVED" then
		shares[plate] = nil
		Hide(plate)
	elseif shares[plate] then
		Refresh(plate)
	end
end)
