-- Cinematic: chat. Which new messages briefly show the chat window (by message
-- type and by channel), and typing detection.
local _, ns = ...
local L = ns.L

function ns.IsChatActive()
	return ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() ~= nil
end

-- Chat messages that briefly reveal the chat window they land in (only that
-- window and its tabs: not the input bar or the rest of the UI).
-- Message types the player can switch on or off individually (db.chatPeekTypes,
-- missing = the type's default, on unless it says otherwise: their Always
-- column; their rows' other columns are below). Numbered channels
-- are chosen one by one instead (db.chatPeekChannelList by channel name,
-- missing = db.chatPeekChannels). "game" types are game events rather than
-- conversation; the noisy ones default off.
ns.CHAT_PEEK_TYPES = {
	{ key = "say", label = L["Say"], events = { "CHAT_MSG_SAY" } },
	{ key = "yell", label = L["Yell"], events = { "CHAT_MSG_YELL" } },
	{ key = "emote", label = L["Emotes"], events = { "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" } },
	{ key = "whisper", label = L["Whispers"], events = { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
		"CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM" } },
	{ key = "party", label = L["Party"], events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" } },
	{ key = "raid", label = L["Raid"], events = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" } },
	{ key = "raidwarning", label = L["Raid warnings"], events = { "CHAT_MSG_RAID_WARNING" } },
	-- The ping system's chat line ("Attack" on a target...). Clients without pings
	-- never send the event, so the row just never fires there.
	{ key = "pings", label = L["Pings"], tip = L["Someone in your group pings (attack, assist, warning...)."],
		events = { "CHAT_MSG_PING" } },
	{ key = "instance", label = L["Instance"],
		events = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" } },
	{ key = "guild", label = L["Guild"], events = { "CHAT_MSG_GUILD" } },
	{ key = "officer", label = L["Officer"], events = { "CHAT_MSG_OFFICER" } },
	{ key = "npc", label = L["NPC speech"], events = {
		"CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_WHISPER",
		"CHAT_MSG_MONSTER_EMOTE" } },
	{ key = "boss", label = L["Boss emotes"],
		events = { "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_RAID_BOSS_WHISPER" } },
	-- Anyone's line naming or linking a quest in your log, in any chat or
	-- channel, even ones that are off above; see MentionsYourQuest below.
	{ key = "quests", label = L["Your quests"],
		tip = L["Someone links or names a quest you're on, in any chat."], events = {} },

	-- Guild members' comings and goings arrive as system messages; see IsGuildLine below.
	{ key = "guildmembers", label = L["Guild members"], section = "game",
		tip = L["Guild members coming online, going offline, joining and leaving."],
		events = {} },
	-- Group members' comings and goings likewise; see IsGroupLine below.
	{ key = "groupmembers", label = L["Group members"], section = "game",
		tip = L["People joining and leaving your group."], events = {} },
	-- Server announcements ("[SERVER] Shutdown in 9:00"); see the AddMessage hook below.
	{ key = "server", label = L["Server messages"], section = "game",
		tip = L["Server shutdowns and restarts."], events = {} },
	-- Level ups arrive as a system message; see LEVEL_UP_WINDOW below.
	{ key = "levelup", label = L["Level ups"], section = "game", events = {} },
	-- /who replies (shift-clicking a name in the guild list, too); see WHO_WINDOW below.
	{ key = "who", label = L["/who results"], section = "game",
		tip = L["Replies to a /who, shift-clicking a name in the guild list too."], events = {} },
	{ key = "skill", label = L["Skill ups"], section = "game", default = false, events = { "CHAT_MSG_SKILL" } },
	{ key = "achievement", label = L["Achievements"], section = "game", default = false,
		events = { "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT" } },
	{ key = "xp", label = L["Experience"], section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_XP_GAIN" } },
	{ key = "reputation", label = L["Reputation"], section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_FACTION_CHANGE" } },
	{ key = "honor", label = L["Honor"], section = "game", default = false,
		events = { "CHAT_MSG_COMBAT_HONOR_GAIN" } },
	{ key = "battleground", label = L["BG objectives"], section = "game",
		tip = L["Battleground assaults, captures and flags."],
		events = { "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_NEUTRAL" } },
	-- Group loot rolls arrive as loot messages; see IsLootRollLine below.
	{ key = "rolls", label = L["Loot rolls"], section = "game", default = false,
		tip = L["Need, greed and who won."], events = {} },
	{ key = "loot", label = L["All loot"], section = "game", default = false, events = { "CHAT_MSG_LOOT" } },
	{ key = "money", label = L["Money"], section = "game", default = false, events = { "CHAT_MSG_MONEY" } },
	{ key = "tradeskill", label = L["Other players' crafting"], section = "game", default = false,
		events = { "CHAT_MSG_TRADESKILLS" } },
	{ key = "system", label = L["All other system messages"], section = "game", default = false,
		events = { "CHAT_MSG_SYSTEM" } },
}
ns.OnLanguage(function() ns.TranslateFields(ns.CHAT_PEEK_TYPES, "label", "tip") end)
local PEEK_TYPE_DEFAULT = {}
for _, peekType in ipairs(ns.CHAT_PEEK_TYPES) do
	PEEK_TYPE_DEFAULT[peekType.key] = peekType.default ~= false
end

-- A type's Always tick on the Chat page (shows chat for it whenever).
function ns.IsPeekTypeAlways(key)
	local on = ns.db.chatPeekTypes[key]
	if on == nil then
		return PEEK_TYPE_DEFAULT[key]
	end
	return on
end
-- Each type is a row on the Chat page's grids ("chat:<type>"): its other
-- columns, roles and rule say when else it shows chat.
local PEEK_ROW = {}
for _, peekType in ipairs(ns.CHAT_PEEK_TYPES) do
	PEEK_ROW[peekType.key] = "chat:" .. peekType.key
end
-- Players' yells: not in cities, where people yell their trade all day
-- (user, 2026-11-17). NPCs' yells are the NPC speech row's.
ns.RULE_DEFAULTS[PEEK_ROW.yell] = "not city"
local function IsPeekTypeOn(key)
	return PEEK_ROW[key] ~= nil and ns.RowOnNow(PEEK_ROW[key], ns.IsPeekTypeAlways(key))
end

-- The level-up line is a plain system message among many, and matching its
-- text would break in other languages. So a system message arriving within
-- LEVEL_UP_WINDOW seconds of PLAYER_LEVEL_UP counts as the level-up line.
ns.LEVEL_UP_WINDOW = 2
ns.levelUpUntil = 0
-- /who replies are system messages too, so likewise: ones arriving within
-- WHO_WINDOW seconds of a /who being sent (typed, or by shift-clicking a name).
local WHO_WINDOW = 3
local whoUntil = 0
local function WhoSent()
	whoUntil = GetTime() + WHO_WINDOW
end
if C_FriendList and C_FriendList.SendWho then
	hooksecurefunc(C_FriendList, "SendWho", WhoSent)
end
if _G.SendWho then
	hooksecurefunc("SendWho", WhoSent)
end
local EVENT_PEEK_TYPE = {}
local CHAT_PEEK_EVENTS = { "CHAT_MSG_CHANNEL" }
for _, peekType in ipairs(ns.CHAT_PEEK_TYPES) do
	for _, event in ipairs(peekType.events) do
		EVENT_PEEK_TYPE[event] = peekType.key
		CHAT_PEEK_EVENTS[#CHAT_PEEK_EVENTS + 1] = event
	end
end

-- Roll lines are told apart from other loot lines by the game's own
-- (localised) format strings, turned into patterns. Missing ones (not on this
-- client) are skipped.
local LOOT_ROLL_FORMATS = {
	"LOOT_ROLL_NEED", "LOOT_ROLL_NEED_SELF", "LOOT_ROLL_GREED", "LOOT_ROLL_GREED_SELF",
	"LOOT_ROLL_DISENCHANT", "LOOT_ROLL_DISENCHANT_SELF", "LOOT_ROLL_TRANSMOG", "LOOT_ROLL_TRANSMOG_SELF",
	"LOOT_ROLL_PASSED", "LOOT_ROLL_PASSED_SELF", "LOOT_ROLL_PASSED_AUTO", "LOOT_ROLL_PASSED_AUTO_FEMALE",
	"LOOT_ROLL_PASSED_SELF_AUTO", "LOOT_ROLL_ALL_PASSED",
	"LOOT_ROLL_ROLLED_NEED", "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "LOOT_ROLL_ROLLED_GREED",
	"LOOT_ROLL_ROLLED_DE", "LOOT_ROLL_ROLLED_TRANSMOG", "LOOT_ROLL_WON", "LOOT_ROLL_YOU_WON",
}
local lootRollPatterns

-- (capture: the first %s slot captured, for the name it holds.)
local function FormatToPattern(format, capture)
	-- Mark the %s / %d / %1$s slots, escape the rest, then fill the slots in.
	local pattern = format:gsub("%%%d*%$?([sd])", "\1%1")
	pattern = pattern:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
	if capture then
		pattern = pattern:gsub("\1s", "(.-)", 1)
	end
	pattern = pattern:gsub("\1s", ".+"):gsub("\1d", "%%d+")
	return "^" .. pattern .. "$"
end

-- A whisper to someone not online: the game sends only this system line back,
-- no line of your whisper.
local function IsWhisperToNoOne(text)
	local format = _G.ERR_CHAT_PLAYER_NOT_FOUND_S
	return type(format) == "string" and type(text) == "string" and not (issecretvalue and issecretvalue(text))
		and text:find(FormatToPattern(format)) ~= nil
end

local function IsLootRollLine(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return false
	end
	if not lootRollPatterns then
		lootRollPatterns = {}
		for _, name in ipairs(LOOT_ROLL_FORMATS) do
			local format = _G[name]
			if type(format) == "string" and format:find("%", 1, true) then
				lootRollPatterns[#lootRollPatterns + 1] = FormatToPattern(format)
			end
		end
	end
	for _, pattern in ipairs(lootRollPatterns) do
		if text:find(pattern) then
			return true
		end
	end
	return false
end

-- Guild members coming online, going offline, joining, leaving, removed,
-- promoted or demoted: told apart from other system messages the same way.
-- Coming online and going offline use the same lines as friends', so a name
-- on your friends list only counts if it's in the guild roster too (the
-- roster may leave out offline members, so a name not on it isn't enough).
local GUILD_FORMATS = {
	"ERR_FRIEND_ONLINE_SS", "ERR_FRIEND_OFFLINE_S", "ERR_GUILD_JOIN_S", "ERR_GUILD_LEAVE_S",
	"ERR_GUILD_REMOVE_SS", "ERR_GUILD_PROMOTE_SSS", "ERR_GUILD_DEMOTE_SSS", "ERR_GUILD_LEADER_CHANGED_SS",
}
local FRIEND_LINES = { ERR_FRIEND_ONLINE_SS = true, ERR_FRIEND_OFFLINE_S = true }
local guildPatterns

-- "Name-Realm" (or a link's "Name:12") -> "Name".
local function ShortName(name)
	return name:match("^[^%-:]+") or name
end

local function IsFriend(name)
	if not (C_FriendList and C_FriendList.GetFriendInfo) then
		return false
	end
	local ok, info = pcall(C_FriendList.GetFriendInfo, name)
	return ok and info ~= nil
end

local function InGuildRoster(name)
	local ok, total = pcall(GetNumGuildMembers)
	if not ok or type(total) ~= "number" then
		return false
	end
	for i = 1, total do
		local member = GetGuildRosterInfo(i)
		if type(member) == "string" and ShortName(member) == name then
			return true
		end
	end
	return false
end

local function IsGuildLine(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or not IsInGuild() then
		return false
	end
	if not guildPatterns then
		guildPatterns = {}
		for _, name in ipairs(GUILD_FORMATS) do
			local format = _G[name]
			if type(format) == "string" and format:find("%", 1, true) then
				guildPatterns[#guildPatterns + 1] = { pattern = FormatToPattern(format, true), friendLine = FRIEND_LINES[name] }
			end
		end
	end
	for _, line in ipairs(guildPatterns) do
		local name = text:match(line.pattern)
		if name then
			if not line.friendLine then
				return true
			end
			name = ShortName(name)
			return not IsFriend(name) or InGuildRoster(name)
		end
	end
	return false
end

-- Party, raid and instance group members joining and leaving, and you
-- joining, leaving or being removed, the group disbanding or becoming a
-- raid: system messages, told apart by the game's own (localised) lines.
-- (Ones a client doesn't have are skipped.)
local GROUP_FORMATS = {
	"ERR_JOINED_GROUP_S", "ERR_LEFT_GROUP_S", "ERR_RAID_MEMBER_ADDED_S", "ERR_RAID_MEMBER_REMOVED_S",
	"ERR_INSTANCE_GROUP_ADDED_S", "ERR_INSTANCE_GROUP_REMOVED_S", "ERR_LEFT_GROUP_YOU", "ERR_UNINVITE_YOU",
	"ERR_RAID_YOU_JOINED", "ERR_RAID_YOU_LEFT", "ERR_GROUP_DISBANDED", "ERR_PARTY_CONVERTED_TO_RAID",
}
local groupPatterns

local function IsGroupLine(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return false
	end
	if not groupPatterns then
		groupPatterns = {}
		for _, name in ipairs(GROUP_FORMATS) do
			local format = _G[name]
			if type(format) == "string" and format ~= "" then
				groupPatterns[#groupPatterns + 1] = FormatToPattern(format)
			end
		end
	end
	for _, pattern in ipairs(groupPatterns) do
		if text:find(pattern) then
			return true
		end
	end
	return false
end

-- Players' lines that a quest of yours in them shows chat for (the "quests"
-- type): links to it (|Hquest:<id>), or its name typed out as whole words,
-- case ignored. Names shorter than QUEST_NAME_MIN letters count only as links
-- ("Bounty" turns up in too much chat). The log is read again after it changes.
local QUEST_LINE_EVENTS = {
	CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true,
	CHAT_MSG_WHISPER = true, CHAT_MSG_BN_WHISPER = true,
	CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
	CHAT_MSG_RAID_WARNING = true, CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
	CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_CHANNEL = true,
}
local QUEST_NAME_MIN = 6
local yourQuests -- { ids = { [questID] = true }, names = { lower-case name, ... } }, nil = read again

local function ReadYourQuests()
	local ids, names = {}, {}
	local function Add(title, questID)
		if type(questID) == "number" then
			ids[questID] = true
		end
		if type(title) == "string" and #title >= QUEST_NAME_MIN then
			names[#names + 1] = title:lower()
		end
	end
	pcall(function()
		if C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries then
			for i = 1, C_QuestLog.GetNumQuestLogEntries() do
				local info = C_QuestLog.GetInfo(i)
				if info and not info.isHeader and not info.isHidden then
					Add(info.title, info.questID)
				end
			end
		elseif GetQuestLogTitle and GetNumQuestLogEntries then
			for i = 1, GetNumQuestLogEntries() do
				local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
				if title and not isHeader then
					Add(title, questID)
				end
			end
		end
	end)
	return { ids = ids, names = names }
end

do
	local questWatch = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
			"PLAYER_ENTERING_WORLD" }) do
		pcall(questWatch.RegisterEvent, questWatch, event)
	end
	questWatch:SetScript("OnEvent", function() yourQuests = nil end)
end

-- (A letter or digit on either side: part of a longer word, not the name.)
local function WholeWordAt(text, first, last)
	return not text:sub(first - 1, first - 1):find("%w") and not text:sub(last + 1, last + 1):find("%w")
end

local function MentionsYourQuest(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return false
	end
	yourQuests = yourQuests or ReadYourQuests()
	for id in text:gmatch("|Hquest:(%d+)") do
		if yourQuests.ids[tonumber(id)] then
			return true
		end
	end
	if #yourQuests.names == 0 then
		return false
	end
	local lower = text:lower()
	for _, name in ipairs(yourQuests.names) do
		local start = 1
		while true do
			local first, last = lower:find(name, start, true)
			if not first then
				break
			end
			if WholeWordAt(lower, first, last) then
				return true
			end
			start = first + 1
		end
	end
	return false
end

-- A channel's Always tick on the Chat page.
function ns.IsChannelPeekOn(name)
	local on = ns.db.chatPeekChannelList[name]
	if on == nil then
		return ns.db.chatPeekChannels
	end
	return on
end
-- ...and whether a message in it shows chat now: its row ("chan:<name>")
-- says when else, as the message types' do.
local CHANNEL_ROW = setmetatable({}, { __index = function(keys, name)
	local key = "chan:" .. name
	keys[name] = key
	return key
end })
function ns.ChannelRowKey(name)
	return CHANNEL_ROW[name]
end
-- General: not in cities, like players' yells (user, 2026-11-17). Rows go by
-- the game's own channel name, so also the client's word for it (zone channel
-- 1) where that isn't "General".
ns.RULE_DEFAULTS[CHANNEL_ROW.General] = "not city"
do
	local getName = C_ChatInfo and C_ChatInfo.GetChannelShortcutForChannelID
	local ok, name = false, nil
	if getName then ok, name = pcall(getName, 1) end
	if ok and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
		ns.RULE_DEFAULTS[CHANNEL_ROW[name]] = "not city"
	end
end
local function IsChannelPeekNow(name)
	return ns.RowOnNow(CHANNEL_ROW[name], ns.IsChannelPeekOn(name))
end

-- Channels the player has joined, by name (e.g. "General", "Trade"). Depending
-- on the client GetChannelList returns id, name pairs or id, name, disabled
-- triples, so walk it by type.
function ns.GetJoinedChannels()
	local list, values = {}, { GetChannelList() }
	local i = 1
	while i <= #values do
		if type(values[i]) == "number" and type(values[i + 1]) == "string" then
			list[#list + 1] = values[i + 1]
			i = i + ((type(values[i + 2]) == "boolean") and 3 or 2)
		else
			i = i + 1
		end
	end
	return list
end

-- "1. General - Elwynn Forest" -> "General", to match GetChannelList's names.
-- Some clients don't pass the channel's base name with the message, and some
-- (Classic) pass it with the zone still attached, so trim either.
local function ChannelBaseName(baseName, channelString)
	local name = (baseName and baseName ~= "") and baseName or channelString or ""
	name = name:gsub("^%d+%.%s*", ""):gsub("%s+%-%s+.*$", "")
	return name
end

-- The Chat page's rows use GetChannelList's names, which a message's can
-- differ from ("Trade (Services)" for "Services"): when the name isn't one
-- of them, the channel's number finds it. (Cached: only found names.)
local channelAliases = {}
local function ChannelPeekName(number, baseName, channelString)
	local name = ChannelBaseName(baseName, channelString)
	if channelAliases[name] then
		return channelAliases[name]
	end
	if type(number) ~= "number" or (issecretvalue and issecretvalue(number)) then
		return name
	end
	local values = { GetChannelList() }
	for i = 1, #values - 1 do
		if values[i] == number and type(values[i + 1]) == "string" then
			channelAliases[name] = values[i + 1]
			return values[i + 1]
		end
	end
	return name
end
ns.chatPeekUntil = {} -- [chat frame] = GetTime() when it may fade again
ns.chatPeekHolders = {} -- [frame] = true: holds a peeking chat window (Frames.lua)
-- [chat frame] = the frame that draws its lines instead, where an addon draws
-- them on a panel of its own (EllesmereUI's chat): peeking the window brings
-- that panel up too, or nothing shows. Filled by the Addon Frame Links
-- (FrameLinks.lua), as the window part's pick says.
ns.chatPeekPanels = {}
-- Whether a chat window's lines show: the window, or its linked panel (Glass
-- keeps the game's windows hidden and draws the selected tab's lines on its
-- own frame: Support/Glass.lua).
function ns.ChatWindowShown(chatFrame)
	if ns.Flag(chatFrame:IsShown()) then return true end
	local panel = ns.chatPeekPanels[chatFrame]
	return panel ~= nil and ns.Flag(panel:IsShown())
end
function ns.MarkChatHolders(frame)
	local panel = ns.chatPeekPanels[frame]
	if panel then
		ns.chatPeekHolders[panel] = true
		ns.MarkChatHolders(panel)
	end
	local parent = frame:GetParent()
	while parent and parent ~= UIParent do
		ns.chatPeekHolders[parent] = true
		parent = parent:GetParent()
	end
end
ns.chatTypingUntil = 0 -- typing shows the whole chat group without leaving cinematic

-- Only a window you'd see peeks: a docked tab that isn't the selected one is
-- hidden, and peeking it would bring up just the dock's tabs.
-- (The frames' pass at once, Core.lua, only for a window not already up: a
-- busy city's channels kept waking it for windows already peeking.)
-- "Show just those messages" (db.chatPeekLinesOnly): instead of the window,
-- a copy of the line that peeked shows where the window sits, on a message
-- frame of ours (one per window, over it), and fades after the reveal time.
-- The line is read back from the window once the game has added it (filters
-- run just before), as the window drew it: name, channel, colors, timestamp.
-- A line that can't be found or read there (another addon rewrote it, a
-- secret text) peeks the whole window as before. The copies go as soon as
-- the window itself comes up (hovered, typed in, out of CineMode).
local LINE_LOOKBACK = 20 -- newest window lines searched for the one that peeked
local lineCopies = {} -- [chat frame] = { frame = our message frame, untilTime = when its last line is gone }
local copyWatch = CreateFrame("Frame")
local PeekWindow

local function Plain(value)
	return type(value) == "string" and not (issecretvalue and issecretvalue(value))
end

-- A line's text as it reads on screen: colors, link codes, icons taken out.
local function StripCodes(s)
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
		:gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

-- The message's own words between its links: another addon may rewrite a
-- link (Questie turns [Quest] into [[32+] Quest]), the words stay as typed.
local function PlainParts(text)
	local parts = {}
	for part in (StripCodes(text:gsub("|H.-|h.-|h", "\n")) .. "\n"):gmatch("([^\n]*)\n") do
		local words = part:match("^%s*(.-)%s*$")
		if #words >= 2 then parts[#parts + 1] = words end
	end
	return parts
end

-- Whether a window line is the message, read loosely: it has every one of
-- the message's own words, and is by its author when there's one.
local function LooseMatch(line, parts, name)
	local shown = StripCodes(line)
	if name and not (line:find("|Hplayer:" .. name, 1, true) or shown:find(name, 1, true)) then
		return false
	end
	for _, part in ipairs(parts) do
		if not shown:find(part, 1, true) then return false end
	end
	return true
end

-- A window's line as it drew it, with its color: the newest of its last
-- lines with text in it, else (an addon rewrote its links) the newest one by
-- its author with all its own words (nil if none, or it can't be read).
local function FindWindowLine(chatFrame, text, author)
	if not (chatFrame.GetNumMessages and chatFrame.GetMessageInfo) then return nil end
	local count = chatFrame:GetNumMessages()
	if not (type(count) == "number" and not (issecretvalue and issecretvalue(count))) then return nil end
	local last = math.max(1, count - LINE_LOOKBACK + 1)
	for i = count, last, -1 do
		local line, r, g, b = chatFrame:GetMessageInfo(i)
		if Plain(line) and line:find(text, 1, true) then
			return line, r, g, b
		end
	end
	local name = Plain(author) and author:match("^[^-]+") or nil
	if name == "" then name = nil end
	local parts = PlainParts(text)
	if not name and #parts == 0 then return nil end
	for i = count, last, -1 do
		local line, r, g, b = chatFrame:GetMessageInfo(i)
		if Plain(line) and LooseMatch(line, parts, name) then
			return line, r, g, b
		end
	end
end

local function CopyFrame(chatFrame)
	local copy = lineCopies[chatFrame]
	if copy then return copy end
	local frame = CreateFrame("ScrollingMessageFrame", nil, UIParent)
	frame:EnableMouse(false)
	frame:SetInsertMode(_G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM or "BOTTOM")
	frame:SetMaxLines(LINE_LOOKBACK)
	frame:SetFading(true)
	frame:SetFontObject(ChatFontNormal)
	if ns.WhyRegister then
		ns.WhyRegister(frame, L["Chat message"], "Chat", {
			L["Show just those messages is on: a message that shows chat comes up here on its own, " ..
				"without the chat window"] })
	end
	-- (Hidden till its first line: a new frame starts shown, and ShowCopy
	-- takes the window's alpha as base only for a hidden one.)
	frame:Hide()
	copy = { frame = frame, untilTime = 0, base = 0 }
	lineCopies[chatFrame] = copy
	return copy
end

-- Lays our frame over the window (or the panel that draws its lines) with the
-- window's font and look, before a line goes in. (Font set only when it
-- changed: set again after lines are in, Russian ones turn to boxes.)
-- How far in from the window's left and right edges its lines draw (0, 0 if
-- it can't be read): read off one of its own line font strings.
local function LineInsets(chatFrame)
	local fontString = type(chatFrame.visibleLines) == "table" and chatFrame.visibleLines[1]
	if not (fontString and fontString.GetLeft) then return 0, 0 end
	local left, right = fontString:GetLeft(), fontString:GetRight()
	local frameLeft, frameRight = chatFrame:GetLeft(), chatFrame:GetRight()
	for _, v in ipairs({ left or false, right or false, frameLeft or false, frameRight or false }) do
		if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return 0, 0 end
	end
	local scale = fontString:GetEffectiveScale() / chatFrame:GetEffectiveScale()
	return math.max(0, left * scale - frameLeft), math.max(0, frameRight - right * scale)
end

-- (Its lines wrap where the window's do: same text width, scale, indent and
-- spacing, or the copy and the window's own line don't match as they cross.)
local function DressCopy(copy, chatFrame)
	local frame, panel = copy.frame, ns.chatPeekPanels[chatFrame]
	local shown = panel or chatFrame
	frame:ClearAllPoints()
	local scale = shown:GetEffectiveScale() / UIParent:GetEffectiveScale()
	if type(scale) == "number" and scale > 0 and not (issecretvalue and issecretvalue(scale)) then
		frame:SetScale(scale)
	end
	local left, right = 0, 0
	if not panel then left, right = LineInsets(chatFrame) end
	frame:SetPoint("TOPLEFT", shown, "TOPLEFT", left, 0)
	frame:SetPoint("BOTTOMRIGHT", shown, "BOTTOMRIGHT", -right, 0)
	if chatFrame.GetIndentedWordWrap and frame.SetIndentedWordWrap then
		frame:SetIndentedWordWrap(ns.Flag(chatFrame:GetIndentedWordWrap()) and true or false)
	end
	if chatFrame.GetSpacing and frame.SetSpacing then
		local spacing = chatFrame:GetSpacing()
		if type(spacing) == "number" and not (issecretvalue and issecretvalue(spacing)) then frame:SetSpacing(spacing) end
	end
	frame:SetFrameStrata(shown:GetFrameStrata())
	frame:SetFrameLevel(shown:GetFrameLevel() + 5)
	local file, size, flags = chatFrame:GetFont()
	if Plain(file) and (copy.file ~= file or copy.size ~= size or copy.flags ~= flags) then
		frame:SetFont(file, size, flags or "")
		copy.file, copy.size, copy.flags = file, size, flags
	end
	if chatFrame.GetJustifyH then frame:SetJustifyH(chatFrame:GetJustifyH()) end
	local x, y = chatFrame:GetShadowOffset()
	if type(x) == "number" then frame:SetShadowOffset(x, y) end
	local hold = ns.HoldTime("chatPeekTime")
	frame:SetTimeVisible(hold)
	-- (Fading out like the window would: the Fade out time.)
	frame:SetFadeDuration(math.max(0.2, tonumber(ns.FadeOutTime()) or 0.5))
	copy.untilTime = GetTime() + hold + frame:GetFadeDuration()
end

-- How far up the window (or the panel drawing its lines) is now: 0 to 1, nil
-- if it can't be read.
local function WindowAlpha(chatFrame)
	local shown = chatFrame
	if not ns.Flag(chatFrame:IsVisible()) then
		shown = ns.chatPeekPanels[chatFrame]
		if not (shown and ns.Flag(shown:IsVisible())) then return 0 end
	end
	local alpha = shown:GetEffectiveAlpha()
	if type(alpha) == "number" and not (issecretvalue and issecretvalue(alpha)) then return alpha end
end

-- How many lines a window has (nil if it can't be read).
local function WindowCount(chatFrame)
	if not chatFrame.GetNumMessages then return nil end
	local count = chatFrame:GetNumMessages()
	if type(count) == "number" and not (issecretvalue and issecretvalue(count)) then return count end
end

-- Whether the copy's lines still sit where the window draws its own: no
-- line came into the window after the last one copied (loot, another
-- channel) and it's scrolled to the bottom.
local function CopyLinesUp(chatFrame, copy)
	local count = WindowCount(chatFrame)
	if not (count and copy.count == count) then return false end
	if chatFrame.AtBottom and not ns.Flag(chatFrame:AtBottom()) then return false end
	return true
end

local QUICK_FADE = 0.15 -- seconds a copy takes to go when its lines don't match the window's

-- While copies are up: gone once their time is over, or when the window
-- itself comes up (hovered, typed in). When their lines sit on the window's
-- own they fade out as it fades in, from how far up it was when they showed
-- (copy.base), so its lines and theirs cross over each other; when they
-- don't (a newer line came in under the copied one) they go at once, in a
-- quick fade, as soon as the window starts coming up.
local function WatchCopies()
	local now, any = GetTime(), false
	for chatFrame, copy in pairs(lineCopies) do
		if copy.frame:IsShown() then
			local alpha = WindowAlpha(chatFrame) or 1
			local base = copy.base or 0
			local rise = (alpha - base) / math.max(0.05, 1 - base)
			local fade = 1 - math.max(0, rise)
			if not copy.quickFrom and rise > 0.02 and not CopyLinesUp(chatFrame, copy) then
				copy.quickFrom, copy.quickAlpha = now, copy.frame:GetAlpha()
			end
			if copy.quickFrom then
				fade = math.min(fade, (copy.quickAlpha or 1) * (1 - (now - copy.quickFrom) / QUICK_FADE))
			end
			local seen = not ns.ChatPeekLinesOnly() or now >= copy.untilTime
				or not ns.ChatWindowShown(chatFrame) or rise >= 0.9 or fade <= 0
			if seen then
				copy.frame:Clear()
				copy.frame:Hide()
				copy.quickFrom = nil
			else
				copy.frame:SetAlpha(fade)
				any = true
			end
		end
	end
	if not any then ns.SetOnUpdate(copyWatch, nil) end
end
local OnCopyWatch = ns.Profiled("Chat line copies", WatchCopies)

-- Whether two frames cover some of the same screen (false if unreadable).
local function Overlap(a, b)
	local al, ab, aw, ah = a:GetRect()
	local bl, bb, bw, bh = b:GetRect()
	for _, v in ipairs({ al, ab, aw, ah, bl, bb, bw, bh }) do
		if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return false end
	end
	return al < bl + bw and bl < al + aw and ab < bb + bh and bb < ab + ah
end

-- The message filters run once per window the message goes to: a line two
-- windows both show (System in two tabs, or two windows an addon draws on one
-- panel) is copied once where they overlap, not once per window.
local SAME_LINE_TIME = 1 -- seconds a line counts as the same message
local function CopiedNearby(chatFrame, text)
	local shown, now = ns.chatPeekPanels[chatFrame] or chatFrame, GetTime()
	for other, copy in pairs(lineCopies) do
		if other ~= chatFrame and copy.lastText == text and now - (copy.lastTime or 0) < SAME_LINE_TIME
				and copy.frame:IsShown() and copy.place and Overlap(copy.place, shown) then
			return true
		end
	end
	return false
end

local function ShowCopy(chatFrame, line, r, g, b, text)
	if CopiedNearby(chatFrame, text or line) then return end
	local copy = CopyFrame(chatFrame)
	copy.lastText, copy.lastTime = text or line, GetTime()
	copy.place = ns.chatPeekPanels[chatFrame] or chatFrame
	DressCopy(copy, chatFrame)
	-- (A copy already up keeps its base: the window has only risen since.)
	if not copy.frame:IsShown() then
		copy.base = math.min(WindowAlpha(chatFrame) or 0, 0.9)
		copy.frame:SetAlpha(1)
	end
	copy.frame:Show()
	copy.frame:AddMessage(line, r, g, b)
	-- (The window's line count once this line is in it: a newer one after
	-- means the copy no longer sits on the window's lines. Nil when this line
	-- isn't the window's newest already: another came in the same frame.)
	local count = WindowCount(chatFrame)
	local newest = count and count > 0 and chatFrame.GetMessageInfo and chatFrame:GetMessageInfo(count)
	copy.count = Plain(newest) and newest == line and count or nil
	ns.SetOnUpdate(copyWatch, OnCopyWatch)
end

-- Whether a peek shows just its line (the setting, with the Chat page on).
function ns.ChatPeekLinesOnly()
	return ns.db and ns.db.chatPeekLinesOnly and ns.PageOn("handleChat") and true or false
end

-- A peek in lines-only mode. formatted: text is the window's line already
-- (server lines); else it's the message's own text, and the window's line
-- holding it is looked up once the game has added it (the next frame).
local function PeekLine(chatFrame, text, formatted, author)
	if formatted then
		local line, r, g, b = FindWindowLine(chatFrame, text) -- (for its color)
		ShowCopy(chatFrame, line or text, r, g, b, text)
		return
	end
	C_Timer.After(0, function()
		local line, r, g, b = FindWindowLine(chatFrame, text, author)
		if line then
			ShowCopy(chatFrame, line, r, g, b, text)
		else
			PeekWindow(chatFrame) -- (not found: the whole window, as before)
		end
	end)
end

-- (text, formatted: the line that peeked, for Show just those messages;
-- author: who sent it, to find it in the window when an addon rewrote it.)
PeekWindow = function(chatFrame, text, formatted, author)
	if chatFrame.IsShown and ns.ChatWindowShown(chatFrame) then
		if text ~= nil and Plain(text) and text ~= "" and ns.ChatPeekLinesOnly()
				and not (ns.ChatSeen and ns.ChatSeen(chatFrame)) then
			PeekLine(chatFrame, text, formatted, author)
			return
		end
		local now = GetTime()
		if (ns.chatPeekUntil[chatFrame] or 0) <= now then ns.framesWake = "chat message" end
		ns.chatPeekUntil[chatFrame] = now + ns.HoldTime("chatPeekTime")
	end
end

-- For /cine debug chatreveal (dev copy): peeks a line already in the window,
-- as a server line does, and reads back its copy's state.
function ns.ChatTestPeek(chatFrame, line)
	PeekWindow(chatFrame, line, true)
end
function ns.ChatCopyState(chatFrame)
	local copy = lineCopies[chatFrame]
	if not copy then return nil end
	return { shown = copy.frame:IsShown(), alpha = copy.frame:GetAlpha(), quick = copy.quickFrom ~= nil,
		count = copy.count, windowCount = WindowCount(chatFrame), windowAlpha = WindowAlpha(chatFrame),
		base = copy.base, linesUp = CopyLinesUp(chatFrame, copy) }
end

-- Shows a chat window for at least seconds, whatever the Chat page's peek
-- settings (our own lines worth reading: the update notice).
function ns.PeekChat(chatFrame, seconds)
	if chatFrame and ns.ChatWindowShown(chatFrame) then
		local untilTime = GetTime() + math.max(seconds, ns.HoldTime("chatPeekTime"))
		ns.chatPeekUntil[chatFrame] = math.max(ns.chatPeekUntil[chatFrame] or 0, untilTime)
		ns.framesWake = "chat notice" -- (the frames' pass at once: Core.lua)
	end
end

-- A chat window scrolled up to read older lines stays up, and fades after the
-- peek time once it's back at the bottom. (Run by the frames' pass itself,
-- which reads the hold straight after: it wakes the next pass only as the
-- hold starts. Woken every time, a window left scrolled up could run the
-- whole pass every other frame. 2026-11-15.)
function ns.HoldScrolledChat(now)
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local chatFrame = _G["ChatFrame" .. i]
		if chatFrame and chatFrame.AtBottom and ns.Flag(chatFrame:IsShown()) then
			-- (Only a plain false: a secret answer mustn't keep chat up for good.)
			local atBottom = chatFrame:AtBottom()
			if not (issecretvalue and issecretvalue(atBottom)) and atBottom == false then
				if (ns.chatPeekUntil[chatFrame] or 0) <= now then ns.framesWake = "chat scrolled up" end
				ns.chatPeekUntil[chatFrame] = now + ns.HoldTime("chatPeekTime")
			end
		end
	end
end

-- With "Hide your messages" (db.chatHideOwn), your own lines don't peek: your
-- emotes ("You bow.", the campfire button's sit or kneel), says, party lines...
-- You know you did them. Told by the sender's GUID, or by name where a client
-- doesn't pass one. With "Except lines with no bubble" (db.chatOwnNoBubble), a
-- line you typed still peeks unless its bubble shows: Enter otherwise shows
-- you nothing at all.

-- Whispers you sent: these name who they went to, not you.
local SENT_LINES = { CHAT_MSG_WHISPER_INFORM = true, CHAT_MSG_BN_WHISPER_INFORM = true }
-- Lines you type (not your emotes, or your loot and the like): the game setting
-- for their bubble, or true for none ever.
local TYPED_LINES = {
	CHAT_MSG_SAY = "chatBubbles", CHAT_MSG_YELL = "chatBubbles",
	CHAT_MSG_PARTY = "chatBubblesParty", CHAT_MSG_PARTY_LEADER = "chatBubblesParty",
	CHAT_MSG_WHISPER_INFORM = true, CHAT_MSG_BN_WHISPER_INFORM = true,
	CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
	CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
	CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_CHANNEL = true,
}

local function IsFromPlayer(author, guid)
	if type(guid) == "string" and guid ~= "" and not (issecretvalue and issecretvalue(guid)) then
		return guid == UnitGUID("player")
	end
	if type(author) ~= "string" or (issecretvalue and issecretvalue(author)) then
		return false
	end
	local name = UnitName("player")
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	return author == name or (realm ~= nil and author == name .. "-" .. realm)
end

-- With "Hide speech you can see as a bubble" (db.chatHideBubbled), speech you
-- can see as a bubble on screen (a yell from someone in view) doesn't need the
-- chat window: such a line waits BUBBLE_WAIT seconds for its
-- bubble (it shows a frame or so after the message), and peeks only if none
-- with its text showed on screen. Bubbles kept from addons (in instances, on
-- retail) can't be read: a new one turning up counts as the line's. Bubbles
-- switched off peek as before. With "Show speech from behind
-- you" (db.chatSpeechBehind, with the Chat bubbles page on), one with no
-- bubble shows low on the screen instead (Speech.lua), while its chat window
-- is faded, and never keeps chat up.
local BUBBLE_SPEECH = {
	CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_MONSTER_SAY = true, CHAT_MSG_MONSTER_YELL = true,
}
local BUBBLE_WAIT = 0.3
local waiting = {} -- { chatFrame, text, until }
-- A speaker saying more while their bubble is still up gets the same bubble
-- back (the Headless Horseman's summoning lines): kept from addons, no new
-- one turns up to count. A speaker whose line was taken as bubbled that way
-- keeps their bubble for SPEAKER_BUBBLE seconds, while no bubble has gone.
local SPEAKER_BUBBLE = 8
local bubbledSpeakers = {} -- [GUID or name] = { when, unreadable bubbles then }
local bubbleWatch = CreateFrame("Frame")

-- A chat window you can't read now: faded or fading (in CineMode), or hidden
-- with the UI.
local function ChatUnseen(chatFrame)
	if not ns.Flag(chatFrame:IsVisible()) then
		-- (Its lines on a linked panel instead, Glass's: that one's seen or not.)
		local panel = ns.chatPeekPanels[chatFrame]
		if not (panel and ns.Flag(panel:IsVisible())) then
			return true
		end
		chatFrame = panel
	end
	local alpha = chatFrame:GetEffectiveAlpha()
	return type(alpha) == "number" and not (issecretvalue and issecretvalue(alpha)) and alpha < 0.95
end
-- (The window up enough to read: its own lines show, no copies needed.)
function ns.ChatSeen(chatFrame)
	return not ChatUnseen(chatFrame)
end

-- /cine debug speech: prints what happens to each say and yell.
local function SpeechTrace(text)
	if ns.speechWatch then
		ns.Print("speech: " .. text)
	end
end

local function SpeakOrPeek(line)
	local chatFrame = line[1]
	if ns.speechWatch then
		SpeechTrace(("no bubble on screen; %s shown %s visible %s alpha %s; option %s"):format(
			tostring(chatFrame:GetName()), tostring(chatFrame:IsShown()), tostring(chatFrame:IsVisible()),
			tostring(chatFrame:GetEffectiveAlpha()), tostring(ns.db.chatSpeechBehind)))
	end
	if not (ns.db.handleBubbles and ns.db.chatSpeechBehind and ns.ShowSpeechBehind
			and ns.ChatWindowShown(chatFrame)) then
		PeekWindow(chatFrame, line[2], nil, line[5])
	elseif ChatUnseen(chatFrame) then
		ns.ShowSpeechBehind(line[4], line[5], line[2], line[6])
		if ns.HideOffScreenBubble then ns.HideOffScreenBubble(line[2]) end
	end
	-- (Otherwise chat is up and the line is in it. Either way it doesn't keep
	-- chat up: in a busy place the speech never stops, and chat never faded.)
end

-- Who said a line: their GUID, else their name (nil if neither can be read).
local function Speaker(line)
	local guid, author = line[6], line[5]
	if type(guid) == "string" and guid ~= "" and not (issecretvalue and issecretvalue(guid)) then
		return guid
	end
	if type(author) == "string" and not (issecretvalue and issecretvalue(author)) then
		return author
	end
end

-- Whether the line's speaker still has a bubble kept from addons up (one
-- taken as theirs a moment ago, with none gone since).
local function SpeakerBubbleUp(line, now, unreadable)
	local speaker = Speaker(line)
	local seen = speaker and bubbledSpeakers[speaker]
	if not seen then
		return false
	end
	if now - seen[1] >= SPEAKER_BUBBLE or unreadable < seen[2] then
		bubbledSpeakers[speaker] = nil
		return false
	end
	return true
end

local function NoteSpeakerBubble(line, now, unreadable)
	local speaker = Speaker(line)
	if speaker then
		bubbledSpeakers[speaker] = { now, unreadable }
	end
end

local function WatchBubbles()
	local now = GetTime()
	for i = #waiting, 1, -1 do
		local line = waiting[i]
		local unreadable = ns.UnreadableBubbles and ns.UnreadableBubbles() or 0
		if ns.IsBubbleOnScreen and ns.IsBubbleOnScreen(line[2]) then
			SpeechTrace("its bubble is on screen")
			table.remove(waiting, i)
		elseif unreadable > line[7] then
			-- (A bubble kept from addons turned up after it: taken as its own.)
			SpeechTrace("a bubble kept from addons showed up")
			NoteSpeakerBubble(line, now, unreadable)
			table.remove(waiting, i)
		elseif now >= line[3] and unreadable > 0 and SpeakerBubbleUp(line, now, unreadable) then
			SpeechTrace("its speaker's bubble kept from addons is still up")
			NoteSpeakerBubble(line, now, unreadable)
			table.remove(waiting, i)
		elseif now >= line[3] then
			table.remove(waiting, i)
			if line[8] then
				PeekWindow(line[1], line[2], nil, line[5]) -- (your own line: chat, not speech from behind you)
			else
				SpeakOrPeek(line)
			end
		end
	end
	if #waiting == 0 then
		ns.SetOnUpdate(bubbleWatch, nil)
	end
end
local OnBubbleWatch = ns.Profiled("Bubble watch", WatchBubbles)

local function PeekUnlessBubble(chatFrame, event, text, author, guid)
	-- (An emote never has a bubble: with "Show emotes" too, it shows with the
	-- off-screen bubbles while its chat window is faded, as speech does.)
	if ns.SPEECH_EMOTES and ns.SPEECH_EMOTES[event] and ns.db.chatSpeechEmotes and ns.db.chatHideBubbled
			and type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
		SpeakOrPeek({ chatFrame, text, 0, event, author, guid })
		return
	end
	-- (Its kind off on the Chat bubbles page: no bubble to wait for.)
	local kind = ns.BUBBLE_KIND_OF and ns.BUBBLE_KIND_OF[event]
	if not (ns.db.chatHideBubbled and BUBBLE_SPEECH[event] and type(text) == "string" and not (issecretvalue and issecretvalue(text))
			and GetCVarBool and GetCVarBool("chatBubbles") and not (kind and ns.BubbleKindOff(kind))) then
		if BUBBLE_SPEECH[event] then
			SpeechTrace(("not waiting for a bubble (hide bubbled %s, bubbles CVar %s)"):format(
				tostring(ns.db.chatHideBubbled), tostring(GetCVar("chatBubbles"))))
		end
		PeekWindow(chatFrame, text, nil, author)
		return
	end
	waiting[#waiting + 1] = { chatFrame, text, GetTime() + BUBBLE_WAIT, event, author, guid,
		ns.UnreadableBubbles and ns.UnreadableBubbles() or 0 }
	ns.SetOnUpdate(bubbleWatch, OnBubbleWatch)
end

-- A line you typed, with Hide your messages on and its exception ticked: peeks
-- unless its bubble shows, whatever Hide speech you can see as a bubble says.
-- bubbleCVar: from TYPED_LINES.
local function PeekOwnLine(chatFrame, event, text, author, guid, bubbleCVar)
	local kind = ns.BUBBLE_KIND_OF and ns.BUBBLE_KIND_OF[event]
	if bubbleCVar == true or type(text) ~= "string" or (issecretvalue and issecretvalue(text))
			or not (GetCVarBool and GetCVarBool(bubbleCVar)) or (kind and ns.BubbleKindOff(kind)) then
		PeekWindow(chatFrame, text, nil, author)
		return
	end
	waiting[#waiting + 1] = { chatFrame, text, GetTime() + BUBBLE_WAIT, event, author, guid,
		ns.UnreadableBubbles and ns.UnreadableBubbles() or 0, true }
	ns.SetOnUpdate(bubbleWatch, OnBubbleWatch)
end

-- Message filters run once per chat window that will show the message, which
-- tells us exactly which window to reveal. Never filters anything out.
local function ChatPeekFilter(chatFrame, event, text, author, _, channelString, _, _, _, channelNumber, channelBaseName,
		_, _, guid)
	-- (WIM runs the filters with its own table, not a chat window: nothing to peek.)
	if type(chatFrame) ~= "table" or not chatFrame.IsShown then return false end
	if not ns.db.chatPeek or not ns.PageOn("handleChat") then
		if BUBBLE_SPEECH[event] then SpeechTrace("\"Show chat when a message arrives\" or the Chat page is off") end
		return false
	end
	local wanted
	local hiddenOwn = ns.db.chatHideOwn and (SENT_LINES[event] or IsFromPlayer(author, guid))
	local typedOwn = hiddenOwn and ns.db.chatOwnNoBubble and TYPED_LINES[event]
	if typedOwn then
		wanted = true -- (rows that are off are for other people's lines)
	elseif hiddenOwn then
		wanted = false
	elseif event == "CHAT_MSG_SYSTEM" and (ns.db.chatOwnNoBubble or not ns.db.chatHideOwn)
			and IsWhisperToNoOne(text) then
		wanted = true
	elseif QUEST_LINE_EVENTS[event] and IsPeekTypeOn("quests") and not IsFromPlayer(author, guid)
			and MentionsYourQuest(text) then
		wanted = true
	elseif event == "CHAT_MSG_CHANNEL" then
		wanted = IsChannelPeekNow(ChannelPeekName(channelNumber, channelBaseName, channelString))
	elseif event == "CHAT_MSG_SYSTEM" and GetTime() < ns.levelUpUntil and IsPeekTypeOn("levelup") then
		wanted = true
	elseif event == "CHAT_MSG_SYSTEM" and GetTime() < whoUntil and IsPeekTypeOn("who") then
		wanted = true
	elseif event == "CHAT_MSG_LOOT" and IsPeekTypeOn("rolls") and IsLootRollLine(text) then
		wanted = true
	elseif event == "CHAT_MSG_SYSTEM" and IsPeekTypeOn("guildmembers") and IsGuildLine(text) then
		wanted = true
	elseif event == "CHAT_MSG_SYSTEM" and IsPeekTypeOn("groupmembers") and IsGroupLine(text) then
		wanted = true
	else
		wanted = IsPeekTypeOn(EVENT_PEEK_TYPE[event])
	end
	if wanted and typedOwn then
		PeekOwnLine(chatFrame, event, text, author, guid, typedOwn)
	elseif wanted then
		PeekUnlessBubble(chatFrame, event, text, author, guid)
	elseif BUBBLE_SPEECH[event] then
		SpeechTrace(event .. " not shown here (your own line, or that message type is off on the Chat page)")
	end
	return false
end

-- Server announcements don't arrive as a chat event addons can filter, so
-- look at the newest lines in each chat window for ones starting with the
-- game's own (localised) "[SERVER]" prefix. Checked a few times a second
-- rather than by hooking AddMessage: hooking a game frame's methods breaks
-- the game's own calls to them ("attempt to call a nil value").
local SERVER_CHECK_INTERVAL = 0.25
local LINES_CHECKED = 10 -- newest lines looked at each check, at most
local serverWatch = {} -- [chat frame] = { newest = newest line already looked at, server = last [SERVER] line peeked for }

local function Readable(text)
	return type(text) == "string" and not (issecretvalue and issecretvalue(text))
end

local function CheckServerLines(chatFrame, watch, peekOn)
	local count = chatFrame:GetNumMessages()
	local newest
	for i = count, math.max(1, count - LINES_CHECKED + 1), -1 do
		local text = chatFrame:GetMessageInfo(i)
		if Readable(text) then
			if text == watch.newest then
				break
			end
			newest = newest or text
			local prefix = SERVER_MESSAGE_PREFIX or "[SERVER]"
			if peekOn and watch.newest ~= nil and text ~= watch.server and text:find(prefix, 1, true) then
				watch.server = text
				PeekWindow(chatFrame, text, true)
			end
		end
	end
	-- (The first check only notes where chat is up to: no peeking at old lines.)
	watch.newest = newest or watch.newest or false
end

local function WatchServerMessages()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local chatFrame = _G["ChatFrame" .. i]
		if chatFrame and chatFrame.GetNumMessages and chatFrame.GetMessageInfo then
			serverWatch[chatFrame] = {}
		end
	end
	if not next(serverWatch) then
		return
	end
	local watcher = CreateFrame("Frame")
	-- (Runs only while server messages peek: no loop at all otherwise. Off,
	-- where chat's up to is forgotten, so turning it on peeks at nothing old.)
	ns.FeatureLoop(watcher, ns.Profiled("Server message watch", function()
		local peekOn = ns.db.chatPeek and ns.PageOn("handleChat") and IsPeekTypeOn("server")
		for chatFrame, watch in pairs(serverWatch) do
			CheckServerLines(chatFrame, watch, peekOn)
		end
	end), function()
		local on = ns.db and ns.db.chatPeek and ns.PageOn("handleChat") and IsPeekTypeOn("server") and true or false
		if not on then
			for _, watch in pairs(serverWatch) do watch.newest, watch.server = nil, nil end
		end
		return on
	end, SERVER_CHECK_INTERVAL)
end

-- Whisper tabs (the ones the game opens for each conversation) with a whisper
-- you haven't read: the game flashes such a tab until you click it, so its
-- flash starting and stopping says when. (The tab's own "alerting" field
-- isn't set on every client.) [chat frame] = true.
local unreadWhispers = {}

local function IsWhisperTab(chatFrame)
	return chatFrame ~= nil and chatFrame.isTemporary
		and (chatFrame.chatType == "WHISPER" or chatFrame.chatType == "BN_WHISPER")
end

if FCF_StartAlertFlash and FCF_StopAlertFlash then
	hooksecurefunc("FCF_StartAlertFlash", function(chatFrame)
		if IsWhisperTab(chatFrame) then
			unreadWhispers[chatFrame] = true
		end
	end)
	-- (Also called for any tab you click, flashing or not.)
	hooksecurefunc("FCF_StopAlertFlash", function(chatFrame)
		unreadWhispers[chatFrame] = nil
	end)
end

-- Whether a whisper tab is waiting to be read. Closed tabs drop out.
function ns.HasUnreadWhisper()
	for chatFrame in pairs(unreadWhispers) do
		local tab = _G[chatFrame:GetName() .. "Tab"]
		if IsWhisperTab(chatFrame) and tab and ns.Flag(tab:IsShown()) then
			return true
		end
		unreadWhispers[chatFrame] = nil
	end
	return false
end

-- LocalDefense warnings ("Dun Algaz is under attack!") also show as a title
-- where the zone name appears (the Cards page's Under attack: chatAttackAlert). The channel is told by its
-- zone channel number, which every language shares, or else its English name;
-- the game sends these with no sender, so players' lines there are skipped.
-- The same place repeats at most once every ATTACK_REPEAT seconds.
do
	local LOCAL_DEFENSE_ID = 22
	local ATTACK_REPEAT = 90
	local shownAt = {} -- [text] = GetTime() it last showed

	local function OnChannelMessage(_, _, text, _, _, channelString, _, _, zoneChannelID, _, channelBaseName,
			_, _, guid)
		if not ns.Setting("chatAttackAlert") or not Readable(text) then
			return
		end
		if guid ~= nil and not (Readable(guid) and guid == "") then
			return -- (a player, not the game)
		end
		if not (type(zoneChannelID) == "number" and not (issecretvalue and issecretvalue(zoneChannelID))
				and zoneChannelID == LOCAL_DEFENSE_ID)
			and ChannelBaseName(Readable(channelBaseName) and channelBaseName or nil,
				Readable(channelString) and channelString or nil) ~= "LocalDefense" then
			return
		end
		local now = GetTime()
		if shownAt[text] and now - shownAt[text] < ATTACK_REPEAT then
			return
		end
		shownAt[text] = now
		ns.ShowAlertTitle(text)
	end

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("CHAT_MSG_CHANNEL")
	frame:SetScript("OnEvent", ns.Profiled("Attack alert", OnChannelMessage))
end

-- A chat tab's tooltip ("General Tab") without its green "<Right click for
-- Tab Settings>" line (chatHideTabHint, with the Chat page on).
-- After the game shows it, it's set again with every line but the green
-- "<...>" ones. (Our own Show, to fit it: rebuilding.)
do
	local rebuilding = false

	local function IsTabHint(fs)
		local text = fs and fs:GetText()
		if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or not text:find("^<.*>$") then
			return false
		end
		local r, g, b = fs:GetTextColor()
		if issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then
			return false
		end
		local c = _G.GREEN_FONT_COLOR
		local gr, gg, gb = c and c.r or 0.1, c and c.g or 1, c and c.b or 0.1
		return math.abs(r - gr) < 0.03 and math.abs(g - gg) < 0.03 and math.abs(b - gb) < 0.03
	end

	-- A nameplate's tooltip: the game's locked friendly plates in dungeons
	-- (forbidden, so GetName can't be asked) and open plates' frames.
	-- (plateHideTipHint, hidden setting, on by default.)
	local function NameOf(frame)
		local ok, name = pcall(frame.GetName, frame)
		return ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name or nil
	end

	local function PlateOwner(owner)
		if type(owner) ~= "table" then return false, "no owner" end
		local okF, forbidden = pcall(function() return owner.IsForbidden and owner:IsForbidden() end)
		if okF and forbidden == true then return true, "forbidden" end
		local frame = owner
		for _ = 1, 3 do
			local name = NameOf(frame)
			if name and name:find("^NamePlate") then return true, name end
			local ok, parent = pcall(frame.GetParent, frame)
			if not ok or type(parent) ~= "table" then break end
			frame = parent
		end
		return false, NameOf(owner) or "unnamed"
	end

	-- What the last tooltip with a hint line was (/cine debug tiphint).
	local last

	local function DropTabHint(tooltip)
		local owner = tooltip:GetOwner()
		local name = owner and NameOf(owner)
		local isTab = type(name) == "string" and name:find("^ChatFrame%d+Tab$")
			and ns.db.chatHideTabHint and ns.PageOn("handleChat")
		local isPlate, why = false, "no"
		if not isTab and ns.db.plateHideTipHint ~= false then
			isPlate, why = PlateOwner(owner)
		end
		local count = tooltip:NumLines()
		local hinted = false
		for i = 1, count do
			if IsTabHint(_G["GameTooltipTextLeft" .. i]) then hinted = true break end
		end
		if hinted then
			last = { owner = why, plate = isPlate, tab = isTab and true or false, lines = count,
				mouseover = ns.Flag(UnitExists("mouseover")), result = "not ours" }
		end
		if not (isTab or isPlate) then
			return
		end
		if last and hinted then last.result = "kept (a line couldn't be copied)" end
		local keep, dropped = {}, false
		for i = 1, count do
			local fs = _G["GameTooltipTextLeft" .. i]
			if IsTabHint(fs) then
				dropped = true
			else
				local text = fs and fs:GetText()
				if type(text) ~= "string" then
					return -- (a line we can't copy: left as it is)
				end
				keep[#keep + 1] = { text, fs:GetTextColor() }
			end
		end
		-- (Blank spacer lines left at the bottom go too.)
		while #keep > 1 and not keep[#keep][1]:find("%S") do
			keep[#keep] = nil
		end
		if not dropped or #keep == 0 then
			return
		end
		tooltip:SetText(keep[1][1], keep[1][2], keep[1][3], keep[1][4])
		for i = 2, #keep do
			local line = keep[i]
			tooltip:AddLine(line[1], line[2], line[3], line[4], true)
		end
		tooltip:Show()
		if last and hinted then last.result = "dropped" end
	end

	hooksecurefunc(GameTooltip, "Show", function(tooltip)
		if rebuilding or not ns.db then
			return
		end
		rebuilding = true
		local ok, err = pcall(DropTabHint, tooltip)
		if not ok and last then last.result = "error: " .. tostring(err) end
		rebuilding = false
	end)

	-- /cine debug tiphint: the last tooltip that had a green "<...>" line.
	function ns.TipHintDebug()
		ns.Print(("tiphint: setting plateHideTipHint %s, chatHideTabHint %s, in combat %s, client %s"):format(
			tostring(ns.db.plateHideTipHint ~= false), tostring(ns.db.chatHideTabHint),
			tostring(InCombatLockdown()), ns.isRetail and "retail" or "classic/Forever"))
		if not last then
			ns.Print("tiphint: no tooltip with a hint line seen since /reload (hover the NPC's plate first)")
			return
		end
		ns.Print(("tiphint: owner %s, plate %s, chat tab %s, %d lines, mouseover unit %s -> %s"):format(
			tostring(last.owner), tostring(last.plate), tostring(last.tab), last.lines,
			tostring(last.mouseover), tostring(last.result)))
	end
end

function ns.RegisterChatPeek()
	local addFilter = ChatFrame_AddMessageEventFilter
		or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if not addFilter then
		return
	end
	for _, event in ipairs(CHAT_PEEK_EVENTS) do
		addFilter(event, ns.Profiled("Chat filter", ChatPeekFilter))
	end
	WatchServerMessages()
end
