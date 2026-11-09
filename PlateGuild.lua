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
-- [plate] = how much of its name's own text shows (nil: all). Less with the
-- Service NPCs row showing titles alone: the title moves up into its place.
local textShares = {}
-- [plate] = its NPC's title, or false for none; nil not read yet (or the
-- game wouldn't say: read again in a while, or after the fight).
local titles = {}
local titleTried = {} -- [plate] = when its title was last asked for and not given
local titleUnit = {} -- [plate] = the GUID its title is for (a plate given a new unit reads it anew)
local serviceMatch = {} -- [plate] = whether its title fits a Service NPCs kind ticked; nil not worked out yet
local TITLE_RETRY = 2 -- seconds

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
	return ("title=%s kinds=%s %s"):format(title, table.concat(kinds, ","), quest)
end

-- From the Kinds menu (and a new language): every plate's match worked out again.
function ns.ServiceKindsChanged()
	wipe(serviceMatch)
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
			for key in pairs(ns.TitleKinds(title)) do
				if ns.db["nameService" .. key] then
					match = true
					break
				end
			end
			serviceMatch[plate] = match
		end
		-- (No title, or not known yet: asked again in a while.)
	end
	if match then
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
	local text, guild = LineText(plate, unit)
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
	line:ClearAllPoints()
	local alone = 1 - (textShares[plate] or 1)
	local height = 0
	if alone > 0 then
		local okHeight, value = pcall(name.GetStringHeight, name)
		height = okHeight and Known(value) and type(value) == "number" and value or 10
	end
	line:SetPoint("TOP", name, "BOTTOM", 0, -1 + (height + 1) * alone)
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
		local r, g, b = name:GetTextColor()
		line:SetTextColor(r, g, b)
		if line.SetVertexColor then line:SetVertexColor(r, g, b) end
		if name.GetScale then line:SetScale(name:GetScale()) end
	end)
	line:SetText(text)
	line:SetAlpha(share)
	line:Show()
end

-- From PlateParts, each time it lays out a plate: how far its name shows
-- while the plate shows its name alone (0: not name-only), and how much of
-- that the name's own text gets (text: Service NPCs' titles alone, less).
function ns.SetPlateGuild(plate, share, text)
	shares[plate] = share > 0 and share or nil
	textShares[plate] = text and text < 1 and text or nil
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
		shares[plate], textShares[plate] = nil, nil
		Hide(plate)
	elseif shares[plate] then
		Refresh(plate)
	end
end)
