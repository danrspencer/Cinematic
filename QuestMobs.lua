-- Cinematic: which units count for a quest objective you haven't finished
-- (a mob to kill, an NPC to talk to). For the Vision page's Quest Vision: their
-- plates kept up (see Effects), a quest icon on them (see PlateParts) and on the target frame.
-- Read from the unit's tooltip lines without showing the tooltip
-- (C_TooltipInfo.GetUnit): a quest objective line ("5/7 Thistle Boar slain")
-- not yet done. Where the lines can't be read, C_QuestLog.UnitIsRelatedToActiveQuest
-- (which can't tell a finished objective). Unreadable (secret) counts as no.
local _, ns = ...

-- Answers by GUID: true/false and when they were read. A yes holds until the
-- quest log changes; a no is read again after a while (a unit's tooltip lines
-- can be missing for a moment after its plate appears).
local answers = {} -- [guid] = { quest = bool, at = time, noes = nos in a row }
local RECHECK_NO = 2
-- A no read twice in a row is read again after RECHECK_SETTLED instead: in
-- cities new plates kept every NPC's tooltip being read every 2 seconds (a
-- table of lines each time). Only the quest log makes one a quest mob, and
-- its changes forget every answer.
local RECHECK_SETTLED = 30
-- Where the GUID is secret (retail's instances): by unit token for
-- TOKEN_HOLD seconds, forgotten as soon as a token may point at someone else.
local tokenAnswers = {} -- [unit token] = { quest = bool, at = time }
local TOKEN_HOLD = 1
-- Tokens whose change the token watcher below hears (nameplateN too).
local TOKEN_EVENT_UNITS = { target = true, mouseover = true, focus = true, softenemy = true, softfriend = true,
	softinteract = true }
-- The game drops a unit's quest line a moment after the quest log changes
-- (an NPC you've just questioned): answers read within SETTLE seconds of a
-- change are read once more after it.
local SETTLE = 2
local settleAt = 0
local passiveAnswers = {} -- [guid] = { passive = bool, at = time } (see IsPassiveQuestMob)
local spent = {} -- [guid] = questID: NPCs you've used that quest's item on (see below)
local spentNames = {} -- [name] = until (time): the same, by name, for SPENT_NAME_TIME seconds
local SPENT_NAME_TIME = 60
local lastSpent -- (for /cine debug questmob: the last one, { guid, name })

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function NameOf(unit)
	local ok, name = pcall(UnitName, unit)
	return ok and type(name) == "string" and Known(name) and name or nil
end

-- Whether an objective line's text says it's done: "7/7" or "100%".
local function TextDone(text)
	if type(text) ~= "string" or not Known(text) then
		return nil
	end
	local have, need = text:match("(%d+)%s*/%s*(%d+)")
	if have then
		return tonumber(have) >= tonumber(need)
	end
	local percent = text:match("(%d+)%%")
	if percent then
		return tonumber(percent) >= 100
	end
	return nil
end

-- A friendly NPC whose only open objective is a progress bar ("Rout the
-- Lightbloom Frenzy", 85%) gets no mark: the bar moves for the enemies you
-- kill around it, and there's nothing to do with the NPC itself. Bar
-- objectives are told by their text, as the quest log has them (rebuilt as
-- it changes); a line that's just a percentage is one too.
local barTexts -- [normalized text] = true, or nil until needed

local function Normalize(text)
	-- (A bracketed note goes too: "(Optional)" can be on the log's line and not the tooltip's.)
	text = text:lower():gsub("%d+%s*/%s*%d+", ""):gsub("%d+%s*%%", ""):gsub("%b()", ""):gsub("[%(%)%-:]", "")
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function BarTexts()
	if barTexts then
		return barTexts
	end
	barTexts = {}
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives) then
		return barTexts
	end
	pcall(function()
		for i = 1, log.GetNumQuestLogEntries() do
			local info = log.GetInfo(i)
			local questID = info and not info.isHeader and info.questID
			for _, objective in ipairs(type(questID) == "number" and log.GetQuestObjectives(questID) or {}) do
				local text = objective.text
				if objective.type == "progressbar" and type(text) == "string" and Known(text) then
					barTexts[Normalize(text)] = true
				end
			end
		end
	end)
	return barTexts
end

-- Whether a quest is ready to hand in. Its other objectives can go back to
-- not done after ("Just In Case...": 0/8 Fragmented Keystone (Optional) once
-- they're combined, the quest complete): nothing more to do for them. Also for QuestGlow.
function ns.QuestDone(questID)
	local log = C_QuestLog
	for _, ask in ipairs({ log and log.ReadyForTurnIn, log and log.IsComplete }) do
		local ok, done = pcall(ask, questID)
		if ok and Known(done) and done then
			return true
		end
	end
	return false
end

-- The objectives of quests ready to hand in, by text as Normalize has it
-- (rebuilt as the quest log changes): their lines on a unit's tooltip don't count.
local doneTexts -- [normalized text] = true, or nil until needed

local function DoneTexts()
	if doneTexts then
		return doneTexts
	end
	doneTexts = {}
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives) then
		return doneTexts
	end
	pcall(function()
		for i = 1, log.GetNumQuestLogEntries() do
			local info = log.GetInfo(i)
			local questID = info and not info.isHeader and info.questID
			if type(questID) == "number" and ns.QuestDone(questID) then
				for _, objective in ipairs(log.GetQuestObjectives(questID) or {}) do
					local text = objective.text
					if type(text) == "string" and Known(text) then
						doneTexts[Normalize(text)] = true
					end
				end
			end
		end
	end)
	return doneTexts
end

local function IsDoneQuestLine(text)
	return type(text) == "string" and Known(text) and DoneTexts()[Normalize(text)] == true
end

local function IsBarLine(text)
	if type(text) ~= "string" or not Known(text) then
		return false
	end
	if text:find("%d+%s*/%s*%d+") then
		return false -- (counted: not a bar)
	end
	local key = Normalize(text)
	return key == "" or BarTexts()[key] == true
end

local function IsFriendly(unit)
	local ok, can = pcall(UnitCanAttack, "player", unit)
	return ok and Known(can) and not can
end

-- true / false from the tooltip lines, or nil when they can't say.
local function FromTooltip(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return nil
	end
	local objective = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
	local friendly = IsFriendly(unit)
	local ok, found = pcall(function()
		local data = C_TooltipInfo.GetUnit(unit)
		local lines = data and data.lines
		if type(lines) ~= "table" then
			return nil
		end
		for _, line in ipairs(lines) do
			local text = line.leftText
			if objective and line.type == objective then
				local done = line.completed
				if done == nil then
					done = TextDone(text)
				end
				if not done and not (friendly and IsBarLine(text)) and not IsDoneQuestLine(text) then
					return true
				end
			elseif type(text) == "string" and Known(text) and text:find("^%s*%-%s*%d+%s*/%s*%d+") then
				-- (Clients without line kinds: " - 5/7 Thistle Boar slain".)
				if not TextDone(text) and not IsDoneQuestLine(text) then
					return true
				end
			end
		end
		return false
	end)
	if ok then
		return found
	end
	return nil
end

-- Classic gives units no quest lines (and UnitIsRelatedToActiveQuest says no):
-- there, the kill objectives in the log not yet done ("Young Nightsaber slain:
-- 3/7"), by the mob's name. Items that drop from mobs ("Fel Moss: 3/8") don't
-- name the mob: an enemy counts for one when the quest's text names it ("...the
-- grell and grellkin"), or once you've looted that item from its kind (learned
-- by NPC ID, kept in CinematicDB.questDrops: the next ones count too).
local killNames -- [name] = true, or nil until needed (itemNames, itemTexts with it)
local itemNames -- [item name] = true: item objectives not yet done
local itemTexts -- { lowercase quest text, ... } of quests with one of those

local function KillName(text)
	if type(text) ~= "string" or not Known(text) then
		return nil
	end
	local name = text:match("^(.-):%s*%d+%s*/%s*%d+")
	if not name then
		return nil
	end
	-- (" slain", from the game's own "%s slain: %d/%d".)
	local suffix = type(QUEST_MONSTERS_KILLED) == "string" and QUEST_MONSTERS_KILLED:match("^%%s(.-):")
	if suffix and suffix ~= "" and name:sub(-#suffix) == suffix then
		name = name:sub(1, -#suffix - 1)
	end
	return name ~= "" and name or nil
end

-- One objective of the quest at log index i: a kill or item name noted.
-- Returns whether it's an item not yet done.
local function NoteObjective(kind, finished, text)
	local name = not finished and KillName(text)
	if name and kind == "monster" then
		killNames[name] = true
	elseif name and kind == "item" then
		itemNames[name] = true
		return true
	end
	return false
end

local function NoteQuestText(i)
	if not GetQuestLogQuestText then
		return
	end
	local ok, description, objectives = pcall(GetQuestLogQuestText, i)
	local text = ""
	for _, part in ipairs(ok and { description, objectives } or {}) do
		if type(part) == "string" and Known(part) then
			text = text .. " " .. part:lower()
		end
	end
	if text ~= "" then
		itemTexts[#itemTexts + 1] = text
	end
end

local function KillNames()
	if killNames then
		return killNames
	end
	killNames, itemNames, itemTexts = {}, {}, {}
	pcall(function()
		local log = C_QuestLog
		if log and log.GetInfo and log.GetQuestObjectives then
			for i = 1, log.GetNumQuestLogEntries() do
				local info = log.GetInfo(i)
				local questID = info and not info.isHeader and info.questID
				local open = type(questID) == "number" and not ns.QuestDone(questID)
				local items = false
				for _, objective in ipairs(open and log.GetQuestObjectives(questID) or {}) do
					items = NoteObjective(objective.type, objective.finished, objective.text) or items
				end
				if items then
					NoteQuestText(i)
				end
			end
		elseif GetQuestLogTitle and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
			for i = 1, GetNumQuestLogEntries() do
				local _, _, _, isHeader = GetQuestLogTitle(i)
				local items = false
				for j = 1, not isHeader and GetNumQuestLeaderBoards(i) or 0 do
					local text, kind, finished = GetQuestLogLeaderBoard(j, i)
					items = NoteObjective(kind, finished, text) or items
				end
				if items then
					NoteQuestText(i)
				end
			end
		end
	end)
	return killNames
end

local function NpcID(guid)
	if type(guid) ~= "string" or not Known(guid) then
		return nil
	end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return (kind == "Creature" or kind == "Vehicle") and tonumber(id) or nil
end

local function UnitNpcID(unit)
	local ok, guid = pcall(UnitGUID, unit)
	return ok and NpcID(guid) or nil
end

-- Whether the enemy drops an item objective not yet done (see above): "learned",
-- "text" (named by the quest's text), or nil.
local function FromItemLog(unit)
	if ns.isRetail or IsFriendly(unit) then
		return nil
	end
	KillNames()
	if not next(itemNames) then
		return nil
	end
	local drops = CinematicDB and CinematicDB.questDrops
	local learned = drops and drops[UnitNpcID(unit) or 0]
	for item in pairs(learned or {}) do
		if itemNames[item] then
			return "learned"
		end
	end
	local name = NameOf(unit)
	if not name then
		return nil
	end
	local pattern = "%f[%w]" .. name:lower():gsub("%p", "%%%0") .. "s?%f[%W]"
	for _, text in ipairs(itemTexts) do
		if text:find(pattern) then
			return "text"
		end
	end
	return nil
end

-- Whether the unit is an enemy named by a kill objective not yet done, or
-- one that drops an item for one (see above).
local function FromKillLog(unit)
	if ns.isRetail or IsFriendly(unit) then
		return false
	end
	local name = NameOf(unit)
	return (name and KillNames()[name] == true) or FromItemLog(unit) ~= nil
end

-- Learning drops (Classic, see above): an item objective not yet done in the
-- loot window, kept for the NPC IDs it came from.
local looter = CreateFrame("Frame")
if not ns.isRetail and GetLootSourceInfo then
	looter:RegisterEvent("LOOT_OPENED")
end
looter:SetScript("OnEvent", function()
	KillNames()
	if not (CinematicDB and next(itemNames)) then
		return
	end
	local learnedAny = false
	pcall(function()
		for slot = 1, GetNumLootItems() do
			local _, item = GetLootSlotInfo(slot)
			if type(item) == "string" and Known(item) and itemNames[item] then
				local sources = { GetLootSourceInfo(slot) }
				for k = 1, #sources, 2 do
					local id = NpcID(sources[k])
					if id then
						CinematicDB.questDrops = CinematicDB.questDrops or {}
						CinematicDB.questDrops[id] = CinematicDB.questDrops[id] or {}
						if not CinematicDB.questDrops[id][item] then
							CinematicDB.questDrops[id][item] = true
							learnedAny = true
						end
					end
				end
			end
		end
	end)
	if learnedAny then
		wipe(answers)
	end
end)

local function Read(unit)
	local ok, isPlayer = pcall(UnitIsPlayer, unit)
	if not ok or not Known(isPlayer) or isPlayer then
		return false
	end
	local found = FromTooltip(unit)
	if found then
		return true
	end
	local related = found == nil and C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
	if related then
		local okRelated, yes = pcall(related, unit)
		if okRelated and Known(yes) and yes then
			return true
		end
	end
	return FromKillLog(unit)
end

-- Whether a unit counts for a quest objective you haven't finished.
function ns.IsQuestMob(unit)
	if not unit then
		return false
	end
	-- (Asked every time, not kept: a mob killed with others in the fight
	-- doesn't always change the quest log, and its yes would keep its plate up.)
	local okDead, dead = pcall(UnitIsDead, unit)
	if okDead and Known(dead) and dead then
		return false
	end
	local ok, guid = pcall(UnitGUID, unit)
	if not (ok and type(guid) == "string" and Known(guid)) then
		-- (No GUID to keep it by, as in retail's instances: by the unit token,
		-- briefly. Read every time, its tooltip made heaps of garbage a frame.)
		-- Tokens the watcher below forgets as they change (plates, target...)
		-- hold like GUIDs: a party's 8 plates were read every second, 35 KB/s.
		local now = GetTime()
		local held = tokenAnswers[unit]
		local hold = TOKEN_HOLD
		if held and type(unit) == "string" and (TOKEN_EVENT_UNITS[unit] or unit:find("^nameplate%d+$")) then
			hold = held.quest and math.huge or (held.noes or 0) >= 2 and RECHECK_SETTLED or RECHECK_NO
		end
		if held and (held.at >= settleAt or now < settleAt) and now - held.at < hold then
			return held.quest
		end
		held = held or {}
		held.quest, held.at = Read(unit), now
		held.noes = not held.quest and (held.noes or 0) + 1 or 0
		tokenAnswers[unit] = held
		return held.quest
	end
	if spent[guid] then
		local okOn, on = pcall(C_QuestLog.IsOnQuest, spent[guid])
		if okOn and on then
			return false
		end
		spent[guid] = nil
	end
	-- (By name for a while too: the game can swap an NPC you've used the item
	-- on for a fresh copy of it, with a new GUID.)
	if next(spentNames) then
		local name = NameOf(unit)
		local untilTime = name and spentNames[name]
		if untilTime and GetTime() < untilTime then
			return false
		elseif untilTime then
			spentNames[name] = nil
		end
	end
	local now = GetTime()
	local answer = answers[guid]
	-- (A no read twice holds longer: its tooltip was there by then.)
	local recheck = answer and (answer.noes or 0) >= 2 and RECHECK_SETTLED or RECHECK_NO
	if answer and (answer.at >= settleAt or now < settleAt) and (answer.quest or now - answer.at < recheck) then
		return answer.quest
	end
	answer = answer or {}
	answer.quest, answer.at = Read(unit), now
	answer.noes = not answer.quest and (answer.noes or 0) + 1 or 0
	answers[guid] = answer
	return answer.quest
end

-- NPCs you use a quest's item on ("Renewal for the Weary": 1/10 Sunwell
-- Channeler renewed) keep the objective line on their tooltip after, so they'd
-- keep the !. An NPC counts as done (spent, at the top) once a cast aimed at
-- it is followed, within SPENT_WAIT seconds, by progress on a quest with an
-- item to use: the quest whose item has that spell, else (an item can cast
-- some other spell) any of them, if the NPC was a quest mob. Until the quest
-- leaves the log. Its name too, for SPENT_NAME_TIME seconds. /cine debug questitem prints each step.
local SPENT_WAIT = 15
local CAST_UNITS = { "target", "softinteract", "softfriend", "mouseover", "focus" }
local itemQuests -- { [spellID] = questID, all = { questID, ... } }, or nil until needed
local aimed -- UNIT_SPELLCAST_SENT's: { id = castGUID, guid, mob = quest mob, have = { [questID] = count } }
local pending = {} -- { guid, name, quest, have, at }

local function Report(text)
	if ns.questItemDebug then
		ns.Print("quest item: " .. text)
	end
end

-- The quests in your log with an item to use (the square beside them in the
-- quest tracker): { questID, index (quest log), link, itemID, icon,
-- showComplete, complete } each. Also for QuestItemButton. say: a function
-- told what each quest gives back (/cine debug questitem).
local function ReadQuestLogItems(say)
	local found = {}
	local log = C_QuestLog
	local SpecialItem = _G.GetQuestLogSpecialItemInfo or (log and log.GetQuestLogSpecialItemInfo)
	if not (log and log.GetNumQuestLogEntries and log.GetInfo and SpecialItem) then
		if say then
			say(("can't read quest items: quest log %s, item reader %s"):format(tostring(log and log.GetInfo ~= nil),
				tostring(SpecialItem ~= nil)))
		end
		return found
	end
	local okCount, entries = pcall(log.GetNumQuestLogEntries)
	for index = 1, okCount and type(entries) == "number" and entries or 0 do
		local ok, problem = pcall(function()
			-- (Its item first: most quests have none, and GetInfo makes a
			-- big new table each time.)
			local link, icon, _, showComplete = SpecialItem(index)
			if link == nil then
				return
			end
			local info = log.GetInfo(index)
			local questID = info and not info.isHeader and info.questID
			if type(questID) ~= "number" then
				return
			end
			local readable = type(link) == "string" and Known(link)
			local itemID = readable and tonumber(link:match("item:(%d+)"))
			local complete = log.IsComplete and log.IsComplete(questID) or false
			if say then
				say(("quest %s (%s): item %s%s"):format(questID, tostring(info.title),
					readable and link or ("unreadable (" .. type(link) .. ")"), complete and ", complete" or ""))
			end
			if itemID then
				found[#found + 1] = { questID = questID, index = index, link = link, itemID = itemID, icon = icon,
					showComplete = showComplete, complete = complete }
			end
		end)
		if not ok and say then
			say(("quest log entry %d: error %s"):format(index, tostring(problem)))
		end
	end
	return found
end

-- (Asked every couple of seconds and on many events, and reading the whole
-- log makes a lot of garbage: the list is kept until the quest log, your
-- bags or a fight change, or for ten seconds at most. Callers only read it.)
local KEEP_ITEMS = 10
local keptItems, keptAt
function ns.ForgetQuestLogItems()
	keptItems = nil
end
function ns.QuestLogItems(say)
	if say then
		return ReadQuestLogItems(say) -- (/cine debug questitem: read afresh, step by step)
	end
	local now = GetTime()
	if not keptItems or now - keptAt >= KEEP_ITEMS then
		keptItems, keptAt = ReadQuestLogItems(), now
	end
	return keptItems
end
do
	local forgetter = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
		"QUEST_WATCH_LIST_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
		"PLAYER_REGEN_ENABLED" }) do
		pcall(forgetter.RegisterEvent, forgetter, event)
	end
	forgetter:SetScript("OnEvent", ns.ForgetQuestLogItems)
end

local function ItemQuests()
	if itemQuests then
		return itemQuests
	end
	itemQuests = { all = {} }
	local GetItemSpell = C_Item and C_Item.GetItemSpell or _G.GetItemSpell
	for _, quest in ipairs(ns.QuestLogItems()) do
		local all = itemQuests.all
		all[#all + 1] = quest.questID
		local ok, _, spellID = pcall(GetItemSpell or error, quest.itemID)
		if ok and type(spellID) == "number" and Known(spellID) then
			itemQuests[spellID] = quest.questID
		end
	end
	return itemQuests
end

-- How many of the quest's objectives' steps are done, all told.
local function Fulfilled(questID)
	local total = 0
	pcall(function()
		for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
			if type(objective.numFulfilled) == "number" and Known(objective.numFulfilled) then
				total = total + objective.numFulfilled
			end
		end
	end)
	return total
end

-- The unit a cast is aimed at: of the ones SENT named (any, with no name: an
-- item used on your soft target can come with none), a quest mob first.
local function AimedAt(name)
	local first
	for _, unit in ipairs(CAST_UNITS) do
		local okName, unitName = pcall(UnitName, unit)
		local ok, guid = pcall(UnitGUID, unit)
		if ok and type(guid) == "string" and Known(guid)
			and (name == nil or (okName and Known(unitName) and unitName == name)) then
			if ns.IsQuestMob(unit) then
				return guid, true, unit
			end
			first = first or unit
		end
	end
	return first and UnitGUID(first), false, first
end

local function CheckPending()
	local now = GetTime()
	for i = #pending, 1, -1 do
		local cast = pending[i]
		if now - cast.at > SPENT_WAIT then
			Report(("no progress on quest %s in %d sec: the ! stays"):format(tostring(cast.quest), SPENT_WAIT))
			table.remove(pending, i)
		elseif Fulfilled(cast.quest) > cast.have then
			spent[cast.guid] = cast.quest
			if cast.name then
				spentNames[cast.name] = now + SPENT_NAME_TIME
			end
			lastSpent = { guid = cast.guid, name = cast.name }
			Report(("progress on quest %s: %s is done (%s)"):format(tostring(cast.quest), tostring(cast.name),
				tostring(cast.guid)))
			table.remove(pending, i)
		end
	end
end

local castWatcher = CreateFrame("Frame")
castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castWatcher:SetScript("OnEvent", function(_, event, _, a, b, c)
	if event == "UNIT_SPELLCAST_SENT" then
		-- (unit, target name, castGUID, spellID)
		local name = type(a) == "string" and Known(a) and a ~= "" and a or nil
		local guid, mob, unit = AimedAt(name)
		-- (Each item quest's count now, before the cast: the game can move it
		-- before SUCCEEDED reaches us.)
		aimed = guid and { id = b, guid = guid, name = unit and NameOf(unit), mob = mob, have = {} }
		for _, questID in ipairs(guid and ItemQuests().all or {}) do
			aimed.have[questID] = Fulfilled(questID)
		end
		Report(("cast %s sent at %s: %s (%s)"):format(tostring(c), tostring(name or "no name"),
			tostring(unit or "no unit found"), mob and "a quest mob" or "not a quest mob"))
		return
	end
	-- (unit, castGUID, spellID)
	if not (aimed and Known(a) and a == aimed.id) then
		return
	end
	local quests = ItemQuests()
	local quest = type(b) == "number" and Known(b) and quests[b]
	local list = quest and { quest } or (aimed.mob and quests.all) or {}
	Report(("cast %s done: %s"):format(tostring(b), quest and ("the item spell of quest " .. quest)
		or (#list > 0 and ("not an item spell; watching %d quests with items"):format(#list))
		or "not an item spell, not at a quest mob: ignored"))
	for _, questID in ipairs(list) do
		pending[#pending + 1] = { guid = aimed.guid, name = aimed.name, quest = questID, have = aimed.have[questID] or Fulfilled(questID),
			at = GetTime() }
	end
	aimed = nil
	CheckPending()
end)

-- The quest log changed (progress made, a quest taken or handed in): every
-- answer is read again.
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
	"QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function()
	if #pending > 0 then
		CheckPending()
	end
	itemQuests = nil
	wipe(answers)
	wipe(tokenAnswers)
	wipe(passiveAnswers)
	settleAt = GetTime() + SETTLE
	barTexts = nil
	doneTexts = nil
	killNames = nil
end)

-- A unit token now on someone else: its kept answer goes (see tokenAnswers).
local tokenWatcher = CreateFrame("Frame")
local TOKEN_EVENTS = {
	NAME_PLATE_UNIT_ADDED = true, NAME_PLATE_UNIT_REMOVED = true,
	PLAYER_TARGET_CHANGED = "target", UPDATE_MOUSEOVER_UNIT = "mouseover", PLAYER_FOCUS_CHANGED = "focus",
	PLAYER_SOFT_ENEMY_CHANGED = "softenemy", PLAYER_SOFT_FRIEND_CHANGED = "softfriend",
	PLAYER_SOFT_INTERACT_CHANGED = "softinteract",
}
for event in pairs(TOKEN_EVENTS) do
	pcall(tokenWatcher.RegisterEvent, tokenWatcher, event)
end
tokenWatcher:SetScript("OnEvent", function(_, event, unit)
	local token = TOKEN_EVENTS[event]
	if token == true then token = unit end
	if type(token) == "string" then
		tokenAnswers[token] = nil
	end
	-- (targettarget and the like follow the target: those go too.)
	if event == "PLAYER_TARGET_CHANGED" then
		for kept in pairs(tokenAnswers) do
			if kept:find("target", 1, true) then tokenAnswers[kept] = nil end
		end
	end
end)

-- The golden exclamation mark shown for them (plates' Quest Icon row, the
-- target frame's, below, and Quest Glow's): the map's sharp quest mark, or the
-- old gossip one with Forever's Character Models on Standard Definition (its
-- proxy setting is true then) or where a client lacks that atlas. Marks follow
-- the setting as it changes.
ns.QUEST_MOB_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"
local MODELS_SETTING = "PROXY_CHARACTER_MODELS_TOGGLE" -- (to follow it as it changes)
local marks = setmetatable({}, { __mode = "k" })

local function StandardModels()
	return ns.StandardModels() == true
end

local function HasAtlas(name)
	return type(name) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- A quest mob you can't do anything with yourself (friendly, and the game
-- gives it just the plain pointer: one you eavesdrop on or protect) gets the
-- quest log's "in progress" mark (gold, three dots) instead: part of a quest
-- you're on, nothing to click. The atlas as retail's quest log picks it, else
-- by name; where there's none, the ! greyed.
local PROGRESS_ATLASES = { "Quest-In-Progress-Icon-yellow", "QuestInProgress", "Quest-InProgress" }
local progressAtlas -- false: none

function ns.QuestProgressAtlas()
	if progressAtlas ~= nil then
		return progressAtlas or nil
	end
	progressAtlas = false
	local util = _G.QuestUtil
	if util and util.GetQuestIconActive then
		local ok, atlas = pcall(util.GetQuestIconActive, false)
		if ok and HasAtlas(atlas) then
			progressAtlas = atlas
			return atlas
		end
	end
	for _, name in ipairs(PROGRESS_ATLASES) do
		if HasAtlas(name) then
			progressAtlas = name
			break
		end
	end
	return progressAtlas or nil
end

-- The mark's look, Quest Vision's "Quest mark icon": questMarkStyle for
-- friendly NPCs (and the quest object's glow), questMarkStyleEnemy for
-- enemies. Either one of QUEST_MARK_ICONS (QuestMarkIcons.lua): an atlas
-- name, or a texture path (holding a \). "questnormal" is the ! above, as it
-- always was; any other is that icon, greyed for one you can't do anything
-- with. One this client lacks (or a value it doesn't know): the !.
local function IsFile(icon)
	return icon:find("\\", 1, true) ~= nil
end

local usable = {} -- [icon] = whether this client has it
local function Usable(icon)
	if type(icon) ~= "string" then
		return false
	end
	if usable[icon] == nil then
		if not IsFile(icon) then
			usable[icon] = HasAtlas(icon)
		elseif GetFileIDFromPath then
			local ok, id = pcall(GetFileIDFromPath, icon)
			usable[icon] = ok and id ~= nil
		else
			usable[icon] = true -- (can't tell: offered)
		end
	end
	return usable[icon]
end

-- For the pickers (IconBrowser's source): the icons this client has.
local available
ns.QuestMarkIconSource = {
	list = function()
		if not available then
			available = {}
			for _, icon in ipairs(ns.QUEST_MARK_ICONS or {}) do
				if Usable(icon) then
					available[#available + 1] = icon
				end
			end
		end
		return available
	end,
	atlas = function(icon) return not IsFile(icon) end,
	usable = Usable,
	name = function(icon) return (icon:match("[^\\]*$")) end,
}

local function PaintMark(texture)
	local passive = marks[texture] == "passive"
	texture:SetDesaturated(false)
	texture:SetVertexColor(1, 1, 1)
	local look = ns.Setting(marks[texture] == "enemy" and "questMarkStyleEnemy" or "questMarkStyle")
	if type(look) == "string" and look:lower() ~= "questnormal" and Usable(look)
		and (IsFile(look) or pcall(texture.SetAtlas, texture, look)) then
		if IsFile(look) then
			texture:SetTexture(look)
			texture:SetTexCoord(0, 1, 0, 1)
		end
		if passive then
			texture:SetDesaturated(true)
			texture:SetVertexColor(0.8, 0.8, 0.8)
		end
		return
	end
	local atlas = passive and not StandardModels() and ns.QuestProgressAtlas()
	if atlas and pcall(texture.SetAtlas, texture, atlas) then
		return
	end
	if StandardModels() or not (texture.SetAtlas and HasAtlas("QuestNormal")
		and pcall(texture.SetAtlas, texture, "QuestNormal")) then
		texture:SetTexture(ns.QUEST_MOB_TEXTURE)
		texture:SetTexCoord(0, 1, 0, 1) -- undo the atlas's, if it had one
	end
	if passive then
		texture:SetDesaturated(true)
		texture:SetVertexColor(0.8, 0.8, 0.8)
	end
end

-- The plain pointer, as a texture reads it back (file numbers, made once) or
-- by name (retail's crosshair atlases: "Crosshair_Point_64").
local cursorProbe = CreateFrame("Frame"):CreateTexture()
local pointerFiles

local function IsPointer(cursor)
	if type(cursor) == "string" then
		return cursor:lower():find("point", 1, true) ~= nil
	end
	if type(cursor) ~= "number" then
		return false
	end
	if not pointerFiles then
		pointerFiles = {}
		for _, path in ipairs({ "Interface\\Cursor\\Point", "Interface\\Cursor\\Crosshair\\Point" }) do
			cursorProbe:SetTexture(nil)
			pcall(cursorProbe.SetTexture, cursorProbe, path)
			local file = cursorProbe:GetTexture()
			if type(file) == "number" and Known(file) then
				pointerFiles[file] = true
			end
		end
	end
	return pointerFiles[cursor] or false
end

-- The cursor the game would show over the unit (file or atlas), or nil.
function ns.UnitCursor(unit)
	if not SetUnitCursorTexture then
		return nil
	end
	cursorProbe:SetTexture(nil)
	if not pcall(SetUnitCursorTexture, cursorProbe, unit, nil, true) then
		return nil
	end
	local file = cursorProbe:GetTexture()
	if file ~= nil and Known(file) then
		return file
	end
	local atlas = cursorProbe.GetAtlas and cursorProbe:GetAtlas()
	if atlas ~= nil and Known(atlas) then
		return atlas
	end
	return nil
end

-- Whether a quest mob is one you can't do anything with (see above). By GUID
-- until the quest log changes (passiveAnswers, at the top); a yes is read
-- again after a while: an enemy that turns friendly when beaten (to be
-- questioned) shows the plain pointer for a moment before you can talk to it.
-- Where the game won't say: no (the !).
function ns.IsPassiveQuestMob(unit)
	if not (unit and IsFriendly(unit)) then
		return false
	end
	local ok, guid = pcall(UnitGUID, unit)
	guid = ok and type(guid) == "string" and Known(guid) and guid or nil
	local now = GetTime()
	local answer = guid and passiveAnswers[guid]
	if answer and not (answer.passive and now - answer.at >= RECHECK_NO) then
		return answer.passive
	end
	local passive = IsPointer(ns.UnitCursor(unit))
	if guid then
		passiveAnswers[guid] = { passive = passive, at = now }
	end
	return passive
end

local watching
-- unit: the quest mob it's for, nil for none (the quest object's glow). One
-- you can't do anything with gets the "in progress" mark (see above), an enemy
-- the enemies' icon, else the friendly one. Painted again only when that changes.
function ns.SetQuestMark(texture, unit)
	local kind = "normal"
	if unit and ns.IsPassiveQuestMob(unit) then
		kind = "passive"
	elseif unit then
		local ok, can = pcall(UnitCanAttack, "player", unit)
		if ok and Known(can) and can then
			kind = "enemy"
		end
	end
	if marks[texture] == kind then
		return
	end
	marks[texture] = kind
	PaintMark(texture)
	if not watching and Settings and Settings.SetOnValueChangedCallback then
		watching = true
		pcall(Settings.SetOnValueChangedCallback, MODELS_SETTING, ns.RepaintQuestMarks)
	end
end

-- Every mark painted again (the models setting or questMarkStyle changed).
function ns.RepaintQuestMarks()
	for mark in pairs(marks) do
		PaintMark(mark)
	end
end

-- The target frame's quest icon (targetQuestIcon, Vision page's Quest Vision): the
-- same mark left of the target frame's health bar while your target is a
-- quest mob. Part of the frame, so it fades with it. Looked at again as the
-- target or the quest log changes, and now and then (progress can land a
-- moment after the event).
local targetIcon
local function TargetIcon()
	local frame = _G.TargetFrame
	if targetIcon or not (frame and frame.CreateTexture) then
		return targetIcon
	end
	local bar = frame.healthbar or frame.HealthBar or frame
	targetIcon = CreateFrame("Frame", nil, frame)
	targetIcon:SetSize(24, 24)
	if bar == frame then
		targetIcon:SetPoint("RIGHT", frame, "LEFT", 4, 0)
	else
		targetIcon:SetPoint("RIGHT", bar, "LEFT", -4, 0)
	end
	targetIcon:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 5)
	local texture = targetIcon:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints()
	ns.SetQuestMark(texture)
	targetIcon.texture = texture
	return targetIcon
end

function ns.RefreshTargetQuestIcon()
	local db = ns.db
	local on = db and ns.QuestVisionSetting("targetQuestIcon")
	local ok, exists = pcall(UnitExists, "target")
	local show = on and ok and Known(exists) and exists and ns.IsQuestMob("target")
		and not ns.QuestieMarks("target", true)
	if show then
		local icon = TargetIcon()
		if icon then
			ns.SetQuestMark(icon.texture, "target")
			icon:Show()
		end
	elseif targetIcon then
		targetIcon:Hide()
	end
end

-- Whether Quest Vision is showing anything now (the minimap button's glow):
-- the target frame's icon, an object's glow, or a quest mob's plate.
function ns.QuestVisionActive()
	if not ns.Setting("questVision") then
		return false
	end
	if (targetIcon and ns.Flag(targetIcon:IsShown())) or (ns.QuestGlowShown and ns.QuestGlowShown()) then
		return true
	end
	if not (ns.QuestMobsShow() and C_NamePlate and C_NamePlate.GetNamePlates) then
		return false
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and ns.IsQuestMob(unit) then
			return true
		end
	end
	return false
end

local TARGET_EVERY = 0.5
local targetWatcher = CreateFrame("Frame")
targetWatcher.at = 0
targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
targetWatcher:SetScript("OnEvent", ns.RefreshTargetQuestIcon)
-- (Runs only while the target's quest icon is on, or still shows: no loop
-- at all otherwise.)
ns.FeatureLoop(targetWatcher, function(self)
	local now = GetTime()
	if now >= self.at then
		self.at = now + TARGET_EVERY
		if (ns.db and ns.db.targetQuestIcon) or (targetIcon and targetIcon:IsShown()) then
			ns.RefreshTargetQuestIcon()
		end
	end
end, function()
	return (ns.db and ns.db.targetQuestIcon) or (targetIcon and targetIcon:IsShown()) and true or false
end)

-- For /cine debug plates: what the target's quest lines say.
function ns.DescribeQuestMob(unit)
	return ("quest mob=%s (tooltip=%s)"):format(tostring(ns.IsQuestMob(unit)), tostring(FromTooltip(unit)))
end

-- For /cine debug questmob: what the tooltip says, and the kill objectives in the log (Classic).
function ns.DescribeQuestKills(unit)
	local names = {}
	for name in pairs(KillNames()) do
		names[#names + 1] = name
	end
	table.sort(names)
	local done = {}
	for text in pairs(DoneTexts()) do
		done[#done + 1] = text
	end
	table.sort(done)
	local items = {}
	for name in pairs(itemNames) do
		items[#items + 1] = name
	end
	table.sort(items)
	local drops = CinematicDB and CinematicDB.questDrops
	local learned = {}
	for item in pairs(drops and drops[UnitNpcID(unit) or 0] or {}) do
		learned[#learned + 1] = item
	end
	table.sort(learned)
	return ("tooltip says=%s, kill log match=%s, drop match=%s (npc %s drops: %s), kill objectives: %s; item objectives:"
		.. " %s (%d quest texts); ignored (quest ready to hand in): %s"):format(
		tostring(FromTooltip(unit)), tostring(FromKillLog(unit)), tostring(FromItemLog(unit)), tostring(UnitNpcID(unit)),
		#learned > 0 and table.concat(learned, ", ") or "none known", #names > 0 and table.concat(names, ", ") or "none",
		#items > 0 and table.concat(items, ", ") or "none", #itemTexts,
		#done > 0 and table.concat(done, ", ") or "none")
end

-- For /cine debug questmob: the unit's GUID and whether it counts as done.
function ns.DescribeQuestSpent(unit)
	local ok, guid = pcall(UnitGUID, unit)
	guid = ok and type(guid) == "string" and Known(guid) and guid or nil
	local name = NameOf(unit)
	local untilTime = name and spentNames[name]
	return ("guid=%s, item used on it=%s, by name for %s, last done: %s (%s)"):format(tostring(guid),
		tostring(guid and spent[guid] ~= nil), untilTime and ("%.0f more sec"):format(math.max(0, untilTime - GetTime()))
		or "no", tostring(lastSpent and lastSpent.name), tostring(lastSpent and lastSpent.guid))
end
