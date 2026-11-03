-- The Cards page's moments of a character's story (Cards.lua's events from
-- Level up on, and Discovered, Flight arrival, Rested, Dungeon cleared, Rare
-- spotted, Battleground and Kill streak): each heard here and fired as a
-- card (ns.Cards.Fire), with its made-up one for the Test buttons
-- (ns.CardSamples). The page's tick for each is its row's; all off to start
-- with (on in Cinema: ProfileModules.lua's "story-cards").

local _, ns = ...
local L = ns.L
local DEFAULTS = ns.DEFAULTS

DEFAULTS.cardLevelUpOn = false
DEFAULTS.cardDiscoverOn = false
DEFAULTS.cardArrivalOn = false
DEFAULTS.cardRestedOn = false
DEFAULTS.cardAchievementOn = false
DEFAULTS.cardReputationOn = false
DEFAULTS.cardCollectOn = false
DEFAULTS.cardProfessionOn = false
DEFAULTS.cardQuestOn = false
DEFAULTS.cardClearedOn = false
DEFAULTS.cardRareOn = false
DEFAULTS.cardBattlegroundOn = false
DEFAULTS.cardStreakOn = false

local SEPARATOR = " · "
local samples = ns.CardSamples

-- A plain string or number (nil: none, or one the game keeps secret).
local function Plain(value)
	if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
	local kind = type(value)
	if kind ~= "string" and kind ~= "number" then return nil end
	return value
end

-- A game format string ("Discovered: %s") as a pattern catching its %s and %d.
local function Pattern(format)
	if type(format) ~= "string" or format == "" then return nil end
	local pattern = format:gsub("%%%d?%$?([sd])", "\1%1"):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	pattern = pattern:gsub("\1s", "(.+)"):gsub("\1d", "(%%d+)")
	return "^" .. pattern .. "$"
end

local function Fight()
	return (InCombatLockdown and InCombatLockdown()) or ns.Flag(UnitAffectingCombat("player"))
end

local function Zone()
	return Plain(GetRealZoneText and GetRealZoneText()) or ""
end
local function Subzone()
	return Plain(GetSubZoneText and GetSubZoneText()) or ""
end

-- "1 h 20 min", "42 min" or "under a minute".
local function Span(seconds)
	local minutes = math.floor((seconds or 0) / 60)
	if minutes < 1 then return L["under a minute"] end
	if minutes < 60 then return L["%d min"]:format(minutes) end
	return L["%d h %d min"]:format(math.floor(minutes / 60), minutes % 60)
end

-- The character's places already seen (Discovered), kept between sessions.
local function Seen()
	local char = ns.chardb
	if not char then return nil end
	char.cardSeen = char.cardSeen or { zones = {}, instances = {} }
	return char.cardSeen
end

---------------------------------------------------------------------------
-- Level up: "Level 42", the zone (and the time it took, if it was this
-- session); "Max level" at the cap.
local levelAt -- (GetTime of this session's last level)
local function MaxLevel()
	if GetMaxLevelForPlayerExpansion then
		local ok, max = pcall(GetMaxLevelForPlayerExpansion)
		if ok and Plain(max) then return max end
	end
	return MAX_PLAYER_LEVEL
end
local function LevelCard(level, took)
	local under = {}
	if level == MaxLevel() then
		under[1] = L["Max level"]
	else
		under[1] = Zone()
		if took then under[#under + 1] = L["took %s"]:format(Span(took)) end
	end
	return { meta = L["Level up"], name = L["Level %d"]:format(level), sub = table.concat(under, SEPARATOR) }
end
samples.levelUp = function()
	return LevelCard((Plain(UnitLevel("player")) or 41) + 1, 42 * 60)
end

---------------------------------------------------------------------------
-- Discovered: a zone you're in for the first time, a subzone the game says
-- you discovered ("Discovered: Goldshire"), a dungeon or raid you're in for
-- the first time. A new zone's beats the subzone found with it.
local DISCOVERED = { Pattern(ERR_ZONE_EXPLORED), Pattern(ERR_ZONE_EXPLORED_XP) }
local zoneFoundAt, lastFound, lastFoundAt = 0, nil, 0
local function DiscoverCard(name, sub)
	return { meta = L["Discovered"], name = name, sub = sub or "" }
end
local function Discovered(name, sub)
	if name == "" or (name == lastFound and GetTime() - lastFoundAt < 10) then return end
	lastFound, lastFoundAt = name, GetTime()
	ns.Cards.Cut("zone")
	ns.Cards.Cut("subzone")
	ns.Cards.Fire("discover", DiscoverCard(name, sub))
end
-- (The game's own exploration where it has it: a zone with at most the one
-- area you just found explored is new to you. Else, ours: a zone not seen
-- before since this was installed.)
local function ExploredCount()
	if not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures and C_Map) then return nil end
	local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if not Plain(mapID) then return nil end
	local ok, list = pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID)
	if not ok or type(list) ~= "table" then return nil end
	return #list
end
local function ZoneEntered()
	local seen = Seen()
	if not seen then return end
	local inInstance, kind = IsInInstance()
	if ns.Flag(inInstance) and (kind == "party" or kind == "raid") then
		local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
		name, instanceID = Plain(name), Plain(instanceID)
		local key = instanceID or name
		if key and not seen.instances[key] then
			seen.instances[key] = true
			if ns.CardOn("discover") and name then
				zoneFoundAt = GetTime()
				Discovered(name, kind == "raid" and L["Raid"] or L["Dungeon"])
			end
		end
		return
	end
	if ns.Flag(inInstance) then return end -- (battlegrounds, arenas, scenarios: theirs)
	local zone = Zone()
	if zone == "" or seen.zones[zone] then return end
	local first = next(seen.zones) == nil -- (the very first: just counted, nothing shown)
	seen.zones[zone] = true
	local count = ExploredCount()
	local new
	if count then new = count <= 1 else new = not first end
	if new and ns.CardOn("discover") then
		zoneFoundAt = GetTime()
		Discovered(zone)
	end
end
local function InfoLine(text)
	text = Plain(text)
	if not (text and ns.CardOn("discover")) then return end
	for _, pattern in ipairs(DISCOVERED) do
		local place = text:match(pattern)
		if place then
			if GetTime() - zoneFoundAt < 5 then return end -- (the new zone's card has it)
			local zone = Zone()
			Discovered(place, zone ~= place and zone or "")
			return
		end
	end
end
samples.discover = function()
	local sub, zone = Subzone(), Zone()
	if zone == "" then zone = "Elwynn Forest" end
	if sub == "" then sub = "Goldshire" end
	return DiscoverCard(sub, zone)
end
ns.CardSequences.discover = function()
	local zone = Zone() ~= "" and Zone() or "Elwynn Forest"
	return { DiscoverCard(zone), samples.discover(), DiscoverCard(L["The Deadmines"], L["Dungeon"]) }
end

---------------------------------------------------------------------------
-- Flight arrival: where a flight took you, as you land (the flight
-- camera's arrival shot is over by then). The place: the flight master's
-- node you picked ("Booty Bay, Stranglethorn"), else where you are.
local onTaxi, destination = false, nil
local function ArrivalCard(place)
	local name, sub = (place or ""):match("^(.-),%s*(.+)$")
	if not name then name, sub = place or "", "" end
	return { meta = L["Arrived"], name = name, sub = sub }
end
local function Landed()
	local place = destination
	destination = nil
	if not place then
		local sub, zone = Subzone(), Zone()
		place = sub ~= "" and sub ~= zone and (sub .. ", " .. zone) or zone
	end
	if place ~= "" then ns.Cards.Fire("arrival", ArrivalCard(place)) end
end
if TakeTaxiNode then
	hooksecurefunc("TakeTaxiNode", function(index)
		destination = TaxiNodeName and Plain(TaxiNodeName(index)) or nil
	end)
end
samples.arrival = function() return ArrivalCard("Booty Bay, Stranglethorn") end

---------------------------------------------------------------------------
-- Rested: coming into an inn or a city (not at login, not in a fight), the
-- place's name. The same place at most once every 10 minutes.
local resting, calmAfter = false, 0
local restedAt = {}
-- (Rested under it too: in a bar the line over a card isn't drawn.)
local function RestedCard(place)
	return { meta = L["Rested"], name = place, sub = L["Rested"] }
end
local function RestChanged()
	local now = ns.Flag(IsResting())
	if now == resting then return end
	resting = now
	if not now or GetTime() < calmAfter or Fight() then return end
	local place = Subzone()
	if place == "" then place = Zone() end
	if place == "" or GetTime() - (restedAt[place] or -math.huge) < 600 then return end
	restedAt[place] = GetTime()
	ns.Cards.Fire("rested", RestedCard(place))
end
samples.rested = function()
	local place = Subzone()
	return RestedCard(place ~= "" and place or "Lion's Pride Inn")
end

---------------------------------------------------------------------------
-- Achievement: its name, and its points (or what it's for).
local function AchievementCard(id)
	local ok, _, name, points, _, _, _, _, description = pcall(GetAchievementInfo, id)
	name, points, description = Plain(name), Plain(points), Plain(description)
	if not (ok and name) then return nil end
	return { meta = L["Achievement"], name = name,
		sub = points and points > 0 and L["%d points"]:format(points) or description or "" }
end
samples.achievement = function()
	return { meta = L["Achievement"], name = L["Explore Elwynn Forest"], sub = L["%d points"]:format(10) }
end

---------------------------------------------------------------------------
-- Reputation: a new standing ("Honored"), with whom under it, up or down
-- (the game's "You are now ... with ..."); a Renown level (retail's newer
-- factions); a friendship's rank ("Good Friend"). The ends a big moment, as
-- the Level up card looks: Exalted, Hated, the last Renown level, a
-- friendship's top rank. The rest small.
local STANDING = Pattern(FACTION_STANDING_CHANGED)
local GAINED = Pattern(FACTION_STANDING_INCREASED)
local ENDS = {}
for _, label in ipairs({ "FACTION_STANDING_LABEL8", "FACTION_STANDING_LABEL8_FEMALE", "FACTION_STANDING_LABEL1",
	"FACTION_STANDING_LABEL1_FEMALE" }) do
	if _G[label] then ENDS[_G[label]] = true end
end
local function ReputationCard(standing, faction, big)
	return { meta = L["Reputation"], name = standing, sub = L["with %s"]:format(faction),
		look = big and ns.CardLook("levelUp") or nil }
end
local shownFor = {} -- faction -> GetTime of its last card (a friendship's rank and its standing line, one card)
local function Reputation(standing, faction, big)
	if GetTime() - (shownFor[faction] or -math.huge) < 5 then return end
	shownFor[faction] = GetTime()
	ns.Cards.Fire("reputation", ReputationCard(standing, faction, big))
end
local function SystemLine(text)
	text = Plain(text)
	if not (text and STANDING and ns.CardOn("reputation")) then return end
	local standing, faction = text:match(STANDING)
	if standing then Reputation(standing, faction, ENDS[standing]) end
end
-- (Renown: retail's MAJOR_FACTION_RENOWN_LEVEL_CHANGED.)
local function Renown(factionID, level)
	factionID, level = Plain(factionID), Plain(level)
	if not (factionID and level and C_MajorFactions and C_MajorFactions.GetMajorFactionData) then return end
	local ok, data = pcall(C_MajorFactions.GetMajorFactionData, factionID)
	local faction = ok and type(data) == "table" and Plain(data.name)
	if not faction then return end
	local okMax, max = pcall(C_MajorFactions.HasMaximumRenown, factionID)
	Reputation(L["Renown %d"]:format(level), faction, okMax and max == true)
end
-- (A friendship's rank: none of the game's events tells it, so each one's
-- read as its reputation goes up, and kept: a card as it's higher.)
local friendRank, factionID = {}, {}
local function FindFaction(name)
	if factionID[name] or not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then
		return factionID[name]
	end
	for i = 1, C_Reputation.GetNumFactions() do
		local ok, data = pcall(C_Reputation.GetFactionDataByIndex, i)
		if ok and type(data) == "table" and Plain(data.name) and Plain(data.factionID) then
			factionID[data.name] = data.factionID
		end
	end
	return factionID[name]
end
local function Friendship(id)
	if not (C_GossipInfo and C_GossipInfo.GetFriendshipReputationRanks and C_GossipInfo.GetFriendshipReputation) then
		return nil
	end
	local ok, ranks = pcall(C_GossipInfo.GetFriendshipReputationRanks, id)
	local okRep, rep = pcall(C_GossipInfo.GetFriendshipReputation, id)
	if not (ok and okRep and type(ranks) == "table" and type(rep) == "table") then return nil end
	local level, max, reaction = Plain(ranks.currentLevel), Plain(ranks.maxLevel), Plain(rep.reaction)
	if not (level and max and max > 0 and reaction) then return nil end
	return level, max, reaction
end
local function Gained(text)
	text = Plain(text)
	if not (text and GAINED and ns.CardOn("reputation")) then return end
	local faction = text:match(GAINED)
	local id = faction and FindFaction(faction)
	if not id then return end
	local level, max, reaction = Friendship(id)
	if not level then return end
	local before = friendRank[id]
	friendRank[id] = level
	if before and level > before then Reputation(reaction, faction, level == max) end
end
samples.reputation = function()
	return ReputationCard(FACTION_STANDING_LABEL8 or L["Exalted"], L["Stormwind"], true)
end
ns.CardSequences.reputation = function()
	return { ReputationCard(FACTION_STANDING_LABEL5 or L["Honored"], L["Stormwind"]),
		ReputationCard(FACTION_STANDING_LABEL8 or L["Exalted"], L["Stormwind"], true),
		ReputationCard(L["Renown %d"]:format(12), L["Council of Dornogal"]),
		ReputationCard(FACTION_STANDING_LABEL1 or L["Hated"], L["Bloodsail Buccaneers"], true) }
end

---------------------------------------------------------------------------
-- New mount or pet: its name. (Not the ones the game hands over as you log
-- in.)
-- (A mount a big moment, as the Level up card looks; a pet small, what it
-- is beside it: in a bar the line over a card isn't drawn.)
local function CollectCard(kind, name)
	if kind == "mount" then
		return { meta = L["New mount"], name = name, sub = "", look = ns.CardLook("levelUp") }
	end
	return { meta = L["New pet"], name = name, sub = L["New pet"] }
end
local function NewMount(mountID)
	if not (C_MountJournal and C_MountJournal.GetMountInfoByID) then return end
	local ok, name = pcall(C_MountJournal.GetMountInfoByID, mountID)
	name = ok and Plain(name)
	if name then ns.Cards.Fire("collect", CollectCard("mount", name)) end
end
local function NewPet(petID)
	if not (C_PetJournal and C_PetJournal.GetPetInfoByPetID) then return end
	local ok, _, custom, _, _, _, _, _, name = pcall(C_PetJournal.GetPetInfoByPetID, petID)
	name = ok and (Plain(custom) ~= "" and Plain(custom) or Plain(name))
	if name then ns.Cards.Fire("collect", CollectCard("pet", name)) end
end
samples.collect = function() return CollectCard("mount", L["Swift Gray Gryphon"]) end
ns.CardSequences.collect = function()
	return { CollectCard("mount", L["Swift Gray Gryphon"]), CollectCard("pet", L["Mechanical Squirrel"]) }
end

---------------------------------------------------------------------------
-- Profession rank: a profession learned, or its cap raised ("Journeyman").
-- (Classic's caps have names; retail's each expansion's own, so a number.)
local TIERS = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan", [375] = "Master",
	[450] = "Grand Master", [525] = "Illustrious", [600] = "Zen Master" }
local professions -- name -> its cap (nil until first read)
local function ReadProfessions()
	local list = {}
	if GetProfessions and GetProfessionInfo then
		for _, index in ipairs({ GetProfessions() }) do
			local ok, name, _, _, max = pcall(GetProfessionInfo, index)
			if ok and Plain(name) and Plain(max) then list[name] = max end
		end
	elseif GetNumSkillLines and GetSkillLineInfo then
		local under
		for i = 1, GetNumSkillLines() do
			local name, header, _, _, _, _, max = GetSkillLineInfo(i)
			if header then
				under = name == TRADE_SKILLS or name == SECONDARY_SKILLS
			elseif under and Plain(name) and Plain(max) then
				list[name] = max
			end
		end
	end
	return list
end
local function ProfessionCard(name, max, learned)
	local tier = TIERS[max]
	return { meta = L["Profession"], name = name,
		sub = learned and L["Learned"] or (tier and L[tier] or L["Can now reach %d"]:format(max)) }
end
local function SkillsChanged()
	local now = ReadProfessions()
	local before = professions
	professions = now
	if not before or not ns.CardOn("profession") then return end
	for name, max in pairs(now) do
		if not before[name] then
			ns.Cards.Fire("profession", ProfessionCard(name, max, true))
		elseif max > before[name] then
			ns.Cards.Fire("profession", ProfessionCard(name, max))
		end
	end
end
samples.profession = function() return ProfessionCard(L["Tailoring"], 150) end

---------------------------------------------------------------------------
-- Story quest: a campaign, important or legendary quest, or a dungeon, raid
-- or elite one, as you turn it in. (Its title and kind read as its reward
-- window opens: it's gone from the log by the turn-in.)
local TAGS = { [1] = "Elite", [62] = "Raid", [81] = "Dungeon", [83] = "Legendary", [85] = "Heroic", [88] = "Raid",
	[89] = "Raid" }
local reward -- { id, title, kind }
local function QuestKind(id)
	local classes = Enum and Enum.QuestClassification
	if classes and C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
		local ok, class = pcall(C_QuestInfoSystem.GetQuestClassification, id)
		if ok and class == classes.Campaign then return "Campaign" end
		if ok and class == classes.Legendary then return "Legendary" end
		if ok and class == classes.Important then return "Important" end
	end
	if C_CampaignInfo and C_CampaignInfo.IsCampaignQuest then
		local ok, campaign = pcall(C_CampaignInfo.IsCampaignQuest, id)
		if ok and campaign == true then return "Campaign" end
	end
	local tag
	if C_QuestLog and C_QuestLog.GetQuestTagInfo then
		local ok, info = pcall(C_QuestLog.GetQuestTagInfo, id)
		tag = ok and type(info) == "table" and info.tagID
	elseif GetQuestTagInfo then
		local ok, tagID = pcall(GetQuestTagInfo, id)
		tag = ok and tagID
	end
	return TAGS[Plain(tag) or 0]
end
local function QuestCard(title, kind)
	return { meta = L["Quest complete"], name = title, sub = L[kind] }
end
local function RewardShown()
	local id = GetQuestID and Plain(GetQuestID())
	local title = GetTitleText and Plain(GetTitleText())
	reward = id and title and { id = id, title = title, kind = QuestKind(id) } or nil
end
local function TurnedIn(id)
	local quest = reward
	reward = nil
	if quest and quest.id == Plain(id) and quest.kind then
		ns.Cards.Fire("quest", QuestCard(quest.title, quest.kind))
	end
end
samples.quest = function() return QuestCard(L["The Defias Brotherhood"], "Dungeon") end

---------------------------------------------------------------------------
-- Dungeon cleared: its last boss down (the Journal's last), with the time
-- since you came in and your deaths.
local run = { at = GetTime(), deaths = 0 }
local function ClearedCard(name, seconds, deaths)
	local under = { Span(seconds) }
	under[2] = deaths == 0 and L["no deaths"] or deaths == 1 and L["1 death"] or L["%d deaths"]:format(deaths)
	return { meta = L["Cleared"], name = name, sub = table.concat(under, SEPARATOR) }
end
local function EncounterEnd(encounterID, success)
	encounterID, success = Plain(encounterID), Plain(success)
	if not (encounterID and success == 1 and ns.EncounterIndex and ns.CardOn("cleared")) then return end
	local index, count = ns.EncounterIndex(encounterID)
	if not (index and index == count) then return end
	local name = Plain((GetInstanceInfo())) or ""
	if name == "" then return end
	local card = ClearedCard(name, GetTime() - run.at, run.deaths)
	card.delay = 3 -- (the kill's own moment first)
	ns.Cards.Fire("cleared", card)
end
samples.cleared = function() return ClearedCard(L["The Deadmines"], 34 * 60, 1) end

---------------------------------------------------------------------------
-- Rare spotted: a rare's name as you first target it, point at it or (out
-- of fights: nameplates in fights are the game's) its plate shows. Once
-- each a session.
local raresSeen = {}
-- (Its portrait as its icon, from whichever unit it still is as the card
-- shows: target, mouseover, focus, or (out of fights) its nameplate. Gone:
-- the look's icon. key: its GUID, else its name.)
local function SameUnit(unit, key)
	if not ns.Flag(UnitExists(unit)) then return false end
	return Plain(UnitGUID(unit)) == key or Plain(UnitName(unit)) == key
end
local function Portrait(key)
	return function(texture)
		local units = { "target", "mouseover", "focus" }
		if not Fight() then
			for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
		end
		for _, unit in ipairs(units) do
			if SameUnit(unit, key) then return pcall(SetPortraitTexture, texture, unit) end
		end
		return false
	end
end
local function RareCard(name, elite, key)
	return { meta = elite and L["Rare elite"] or L["Rare"], name = name, sub = "", portrait = key and Portrait(key) }
end
local function Spot(unit)
	if not ns.CardOn("rare") or not ns.Flag(UnitExists(unit)) then return end
	if ns.Flag(UnitIsPlayer(unit)) or ns.Flag(UnitIsDead(unit)) then return end
	local class = Plain(UnitClassification(unit))
	if class ~= "rare" and class ~= "rareelite" then return end
	local name = Plain(UnitName(unit))
	local key = Plain(UnitGUID(unit)) or name
	if not (name and key) or raresSeen[key] then return end
	raresSeen[key] = true
	ns.Cards.Fire("rare", RareCard(name, class == "rareelite", key))
end
-- (Made up: your target's portrait if you have one, so the Test shows it.)
samples.rare = function()
	local key = ns.Flag(UnitExists("target")) and (Plain(UnitGUID("target")) or Plain(UnitName("target")))
	return RareCard(L["Mor'Ladim"], true, key or nil)
end

---------------------------------------------------------------------------
-- Battleground: its name as the gates open (in the lower third, its
-- style's), then Victory or Defeat (arenas too).
local match = { started = false, ended = false }
-- (The result in the top bar's middle: the game's scoreboard takes the
-- middle of the screen as a match ends.)
local RESULT_LOOK = { Place = "top", Align = "center", BarScale = 0.62, BarFallback = false }
local function BattleCard(moment, name)
	if moment == "start" then return { meta = L["Battleground"], name = name, sub = L["The battle begins"] } end
	return { meta = name, name = moment == "won" and L["Victory"] or L["Defeat"], sub = name,
		look = ns.CardLookWith("battleground", RESULT_LOOK) }
end
local function PvPName()
	local inInstance, kind = IsInInstance()
	if not (ns.Flag(inInstance) and (kind == "pvp" or kind == "arena")) then return nil end
	return Plain((GetInstanceInfo()))
end
local function MatchStarts()
	local name = PvPName()
	if not name or match.started then return end
	match.started = true
	ns.Cards.Fire("battleground", BattleCard("start", name))
end
local function MatchEnds()
	local name = PvPName()
	if not name or match.ended or not GetBattlefieldWinner then return end
	local winner = Plain(GetBattlefieldWinner())
	if not winner then return end
	match.ended = true
	local mine = GetBattlefieldArenaFaction and Plain(GetBattlefieldArenaFaction())
	if mine == nil then mine = UnitFactionGroup("player") == "Alliance" and 1 or 0 end
	if winner ~= 0 and winner ~= 1 then return end -- (a draw)
	ns.Cards.Fire("battleground", BattleCard(winner == mine and "won" or "lost", name))
end
samples.battleground = function() return BattleCard("won", L["Warsong Gulch"]) end
ns.CardSequences.battleground = function()
	return { BattleCard("start", L["Warsong Gulch"]), BattleCard("won", L["Warsong Gulch"]),
		BattleCard("lost", L["Warsong Gulch"]) }
end

---------------------------------------------------------------------------
-- Kill streak: other players you kill without dying, at 2, 3, 5 and every
-- 5 after: your killing blows where the combat log is ours, and the
-- game's honorable kills it doesn't tell of.
local streak, logKillAt = 0, -math.huge
local function StreakCard(count, victim)
	return { meta = L["Kill streak"], name = L["%d in a row"]:format(count), sub = victim or "" }
end
local function Killed(victim)
	streak = streak + 1
	if streak == 2 or streak == 3 or streak % 5 == 0 then
		ns.Cards.Fire("streak", StreakCard(streak, victim))
	end
end
samples.streak = function() return StreakCard(3, "Unholy") end

---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
	"UI_INFO_MESSAGE", "CHAT_MSG_SYSTEM", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_UPDATE_RESTING",
	"ACHIEVEMENT_EARNED", "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "SKILL_LINES_CHANGED", "QUEST_COMPLETE",
	"QUEST_TURNED_IN", "ENCOUNTER_END", "PLAYER_DEAD", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
	"NAME_PLATE_UNIT_ADDED", "START_TIMER", "PVP_MATCH_ACTIVE", "UPDATE_BATTLEFIELD_STATUS", "PVP_MATCH_COMPLETE",
	"PLAYER_PVP_KILLS_CHANGED", "CHAT_MSG_COMBAT_FACTION_CHANGE", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" }) do
	pcall(watcher.RegisterEvent, watcher, event) -- (each client that has it)
end
-- (Not on clients with secret values: there addons may not register the
-- combat log, and asking is a forbidden action. PvP kills come from
-- PLAYER_PVP_KILLS_CHANGED there.)
if not issecretvalue then
	pcall(watcher.RegisterEvent, watcher, "COMBAT_LOG_EVENT_UNFILTERED")
end
local loginAt = 0
watcher:SetScript("OnEvent", function(_, event, ...)
	if not ns.db then return end
	if event == "PLAYER_ENTERING_WORLD" then
		local login, reload = ...
		if login or reload then
			loginAt, calmAfter = GetTime(), GetTime() + 15
			resting = ns.Flag(IsResting())
			professions = ReadProfessions()
		end
		local inInstance = ns.Flag(IsInInstance())
		local key = inInstance and (Plain(select(8, GetInstanceInfo())) or Plain((GetInstanceInfo()))) or nil
		if key ~= run.key then run = { key = key, at = GetTime(), deaths = 0 } end
		match = { started = false, ended = false }
		C_Timer.After(1, ZoneEntered)
	elseif event == "PLAYER_LEVEL_UP" then
		local level = Plain(...)
		if level then
			local took = levelAt and GetTime() - levelAt
			levelAt = GetTime()
			if ns.CardOn("levelUp") then ns.Cards.Fire("levelUp", LevelCard(level, took)) end
		end
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		C_Timer.After(0.5, ZoneEntered)
	elseif event == "UI_INFO_MESSAGE" then
		local first, second = ...
		InfoLine(type(first) == "number" and second or first)
	elseif event == "CHAT_MSG_SYSTEM" then
		InfoLine(...)
		SystemLine(...)
	elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
		Gained(...)
	elseif event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
		if ns.CardOn("reputation") then Renown(...) end
	elseif event == "PLAYER_CONTROL_LOST" then
		C_Timer.After(1, function() onTaxi = ns.Flag(UnitOnTaxi("player")) and true or false end)
	elseif event == "PLAYER_CONTROL_GAINED" then
		if onTaxi then
			onTaxi = false
			if ns.CardOn("arrival") then C_Timer.After(0.5, Landed) else destination = nil end
		end
	elseif event == "PLAYER_UPDATE_RESTING" then
		if ns.CardOn("rested") then RestChanged() else resting = ns.Flag(IsResting()) end
	elseif event == "ACHIEVEMENT_EARNED" then
		local id, already = ...
		if ns.CardOn("achievement") and Plain(id) and not already then
			local card = AchievementCard(id)
			if card then ns.Cards.Fire("achievement", card) end
		end
	elseif event == "NEW_MOUNT_ADDED" or event == "NEW_PET_ADDED" then
		if GetTime() - loginAt < 30 or not ns.CardOn("collect") then return end
		if event == "NEW_MOUNT_ADDED" then NewMount(...) else NewPet(...) end
	elseif event == "SKILL_LINES_CHANGED" then
		SkillsChanged()
	elseif event == "QUEST_COMPLETE" then
		RewardShown()
	elseif event == "QUEST_TURNED_IN" then
		if ns.CardOn("quest") then TurnedIn(...) else reward = nil end
	elseif event == "ENCOUNTER_END" then
		local encounterID, _, _, _, success = ...
		EncounterEnd(encounterID, success)
	elseif event == "PLAYER_DEAD" then
		run.deaths = run.deaths + 1
		streak = 0
	elseif event == "PLAYER_TARGET_CHANGED" then
		Spot("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		Spot("mouseover")
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		if not Fight() then Spot((...)) end
	elseif event == "START_TIMER" then
		local kind, remaining = ...
		local pvp = Enum and Enum.StartTimerType and Enum.StartTimerType.PvPBeginTimer or 0
		if ns.CardOn("battleground") and kind == pvp and Plain(remaining) then
			C_Timer.After(remaining, MatchStarts)
		end
	elseif event == "PVP_MATCH_ACTIVE" then
		if ns.CardOn("battleground") then MatchStarts() end
	elseif event == "UPDATE_BATTLEFIELD_STATUS" or event == "PVP_MATCH_COMPLETE" then
		if ns.CardOn("battleground") then MatchEnds() end
	elseif event == "PLAYER_PVP_KILLS_CHANGED" then
		-- (Not one the combat log just told of.)
		if ns.CardOn("streak") then
			C_Timer.After(0.3, function()
				if GetTime() - logKillAt > 1 then Killed() end
			end)
		end
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if not (ns.CardOn("streak") and CombatLogGetCurrentEventInfo) then return end
		local _, sub, _, source, _, _, _, dest, victim = CombatLogGetCurrentEventInfo()
		if sub == "PARTY_KILL" and source == UnitGUID("player") and type(dest) == "string"
			and dest:find("^Player%-") then
			logKillAt = GetTime()
			Killed(Plain(victim) and Plain(victim):match("^[^%-]+"))
		end
	end
end)
