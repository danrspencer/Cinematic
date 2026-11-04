-- Emote Vision: when someone buffs you, brings you back to life, emotes at
-- you, summons you, trades with you, levels up in your group, or you clear a
-- dungeon or finish a duel, a small card shows who it was and what they did,
-- with up to three emotes to answer in one click (each moment's picked on
-- its page: /thank, /bow, the same emote back...). It never shows in a
-- fight: a moment from one waits for the fight to end and is dropped if it's
-- grown old by then. One card at a time, the rest queued; repeats from the
-- same person (the same moment) ignored for a while, so a raid's buffer
-- doesn't flood you. Its look follows Visions Style (font, outline, shadow,
-- border). Its pages are at the bottom.

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.emoteVision = false           -- at all (its page's switch)
DEFAULTS.emoteVisionAlways = false     -- its Show in row's Always: everywhere
DEFAULTS.emoteVisionStill = false      -- only while you stand still (moving: it waits)
DEFAULTS.emoteVisionRepeats = true     -- the same person's same moment again ignored...
DEFAULTS.emoteVisionRepeatMins = 1     -- ...for this many minutes
DEFAULTS.emoteVisionGroupBuffs = false -- buffs from your own party or raid ignored (no card)
DEFAULTS.emoteVisionHold = 8           -- seconds a card stays (paused while the mouse is over it)
DEFAULTS.emoteVisionScale = 1
DEFAULTS.emoteVisionPortrait = true    -- their face (or class icon) on the card
DEFAULTS.emoteVisionSpot = "speech"   -- "speech": just above the lines from behind you (Speech.lua's spot); "own": X, Y
DEFAULTS.emoteVisionX = 0              -- ...own: from the bottom middle of the screen (dragging it with Move)
DEFAULTS.emoteVisionY = 260
-- (Its look: on Visions Style to start with, StylePages.lua's "emote" prefix.)
DEFAULTS.emoteFont = "general"
DEFAULTS.emoteTextSize = 1
DEFAULTS.emoteOutline = -1
DEFAULTS.emoteShadow = "general"
DEFAULTS.emoteBorder = "general"
DEFAULTS.emoteBorderSize = 1
DEFAULTS.emoteBorderR, DEFAULTS.emoteBorderG, DEFAULTS.emoteBorderB = 0, 0, 0
ns.SHARED_STYLE.emoteFont = { kind = "font", own = "game" }
ns.SHARED_STYLE.emoteOutline = { kind = "outline", own = 0 }
ns.SHARED_STYLE.emoteShadow = { kind = "shadow", own = "game" }
ns.SHARED_STYLE.emoteBorder = { kind = "border", own = "thin" }
ns.SHARED_STYLE.emoteBorderSize = { kind = "borderSize", follows = "emoteBorder" }
for _, channel in ipairs({ "R", "G", "B" }) do
	ns.SHARED_STYLE["emoteBorder" .. channel] = { kind = "border" .. channel, follows = "emoteBorder" }
end

-- The common emotes, the add menu's first list: their tokens (DoEmote) and
-- names. The game says each one's own words in chat. (All the game's, and
-- its voice emotes, come from its own lists: GameEmotes.)
local EMOTES = {
	{ "THANK", "Thank" }, { "BOW", "Bow" }, { "SALUTE", "Salute" }, { "KNEEL", "Kneel" }, { "CURTSEY", "Curtsey" },
	{ "CHEER", "Cheer" }, { "APPLAUD", "Applaud" }, { "CONGRATULATE", "Congratulate" }, { "WAVE", "Wave" },
	{ "HELLO", "Hello" }, { "WELCOME", "Welcome" }, { "BYE", "Bye" }, { "SMILE", "Smile" }, { "GRIN", "Grin" },
	{ "WINK", "Wink" }, { "LAUGH", "Laugh" }, { "GIGGLE", "Giggle" }, { "HUG", "Hug" }, { "KISS", "Kiss" },
	{ "LOVE", "Love" }, { "DANCE", "Dance" }, { "FLEX", "Flex" }, { "ROAR", "Roar" }, { "APOLOGIZE", "Sorry" },
	{ "HIGHFIVE", "High five" },
}
local EMOTE_NAMES = {}
for _, each in ipairs(EMOTES) do EMOTE_NAMES[each[1]] = each[2] end
local SAME = "SAME" -- (in a list: "Same back", the emote they did at you)
local MAX_EMOTES = 6   -- buttons a card can have (three to a row)

-- The game's emotes: every one it has a slash command for (EMOTE<n>_TOKEN
-- and _CMD1, its own numbering: several hundred; the chat menu's Emote list,
-- EmoteList, is only a short pick of them), and its voice ones (the Voice
-- Emote list, TextEmoteSpeechList), each token's command ("/thank", in your
-- language). Made once, when first asked.
local EMOTE_INDEX_MOST = 1000 -- (the numbering has gaps: looked through this far)
local gameEmotes
local function GameEmotes()
	if gameEmotes then return gameEmotes end
	gameEmotes = { text = {}, voice = {}, command = {}, isVoice = {} }
	local last = math.max(tonumber(_G.MAXEMOTEINDEX) or 0, EMOTE_INDEX_MOST)
	for i = 1, last do
		local token = _G["EMOTE" .. i .. "_TOKEN"]
		local command = _G["EMOTE" .. i .. "_CMD1"]
		if type(token) == "string" and type(command) == "string" and not gameEmotes.command[token] then
			gameEmotes.command[token] = command
			gameEmotes.text[#gameEmotes.text + 1] = token
		end
	end
	local voice = _G.TextEmoteSpeechList
	if type(voice) == "table" then
		for _, token in ipairs(voice) do
			if type(token) == "string" then
				gameEmotes.voice[#gameEmotes.voice + 1] = token
				gameEmotes.isVoice[token] = true
			end
		end
	end
	return gameEmotes
end

-- An emote's command ("/thank") and its name on a card's button ("Thank").
local function Command(token)
	return GameEmotes().command[token] or ("/" .. token:lower())
end
local function EmoteName(token)
	if token == SAME then return L["Same back"] end
	if EMOTE_NAMES[token] then return L[EMOTE_NAMES[token]] end
	local word = Command(token):gsub("^/", "")
	return word:sub(1, 1):upper() .. word:sub(2)
end

-- What each emote does, from recording every one of them played at no one
-- (retail, 2026-11-03, /cine debug emotescan): moves your character, makes a
-- sound (voice ones: the game's own list), loops till you move (or
-- CancelEmote), or holds a pose till you /stand or move. Not listed: chat
-- words only. (Another race, or with a target, may differ a little.)
local EMOTE_MOVES, EMOTE_SOUND, EMOTE_LOOPS = {}, {}, {}
for token in ("ANGRY APPLAUD ATTACKMYTARGET BASHFUL BEG BLAME BLUSH BOGGLE BOOP BOW BYE CACKLE CHARGE CHEER " ..
	"CHICKEN CHUCKLE CLAP COMMEND CONFUSED CONGRATULATE COWER CRY CURIOUS CURTSEY DANCE DRINK EAT FLEE FLEX FLIRT " ..
	"FOLLOW FORTHEALLIANCE FORTHEHORDE GASP GIGGLE GLOAT GOLFCLAP GREET GROVEL GROWL GUFFAW HAIL HEALME HELLO " ..
	"HELPME HUZZAH IMPRESSED INCOMING INSULT JOKE KISS KNEEL LAUGH LAYDOWN LEAN LOST MAGNIFICENT MASSAGE MERCY " ..
	"MOURN OBJECT OOM OOPS OPENFIRE PANIC PEER PLEAD POINT PONDER PRAY PROUD PUZZLE QUACK RASP READ ROAR ROFL " ..
	"RUDE SALUTE SCARED SHOUT SHRUG SHY SING SIT SLEEP SNARL SURRENDER TALK TALKEX TALKQ TAUNT THANK TRAIN " ..
	"VICTORY VIOLIN WAIT WAVE WELCOME WHOA YW"):gmatch("%S+") do EMOTE_MOVES[token] = true end
for token in ("APOLOGIZE APPLAUD BORED CACKLE CHICKEN CHUCKLE CLAP COMMEND CRY GIGGLE GLOAT GOLFCLAP GUFFAW " ..
	"IMPRESSED KISS LAUGH MOURN OOPS ROAR ROFL SIGH TAUNT THREATEN VIOLIN WHISTLE WHOA YAWN YW"):gmatch("%S+") do
	EMOTE_SOUND[token] = true
end
for token, how in pairs({ DANCE = "loops", COWER = "loops", KNEEL = "holds", LAYDOWN = "holds", SIT = "holds",
	SLEEP = "holds", LEAN = "holds", READ = "holds" }) do EMOTE_LOOPS[token] = how end
-- ...of the ones that move you, the full-body ones (the whole character changes
-- pose: kneels, sits, lies, bows, dances, cowers, flexes...), picked by eye from
-- the recordings; the rest are gestures (hands, arms, head).
local EMOTE_BODY = {}
for token in ("ANGRY BASHFUL BEG BLUSH BOW CHEER CHICKEN COWER CURTSEY DANCE FLEX GROVEL HUZZAH INSULT KNEEL " ..
	"LAYDOWN LEAN MERCY MOURN PLEAD PRAY ROAR RUDE SCARED SHY SIT SLEEP SURRENDER VICTORY"):gmatch("%S+") do
	EMOTE_BODY[token] = true
end

-- An emote's tags as colored words after its name: full body or gesture,
-- voice or sound, loops or holds (none: chat words only).
local function EmoteTags(token)
	local tags = {}
	if EMOTE_BODY[token] then tags[#tags + 1] = "|cff7fd88f" .. L["full body"] .. "|r"
	elseif EMOTE_MOVES[token] then tags[#tags + 1] = "|cff7fd88f" .. L["gesture"] .. "|r" end
	if GameEmotes().isVoice[token] then tags[#tags + 1] = "|cff8fb8ff" .. L["voice"] .. "|r"
	elseif EMOTE_SOUND[token] then tags[#tags + 1] = "|cff8fb8ff" .. L["sound"] .. "|r" end
	if EMOTE_LOOPS[token] then tags[#tags + 1] = "|cffffb060" .. L[EMOTE_LOOPS[token]] .. "|r" end
	return table.concat(tags, " ")
end

-- Plays an emote to try it (the page's > buttons, a right-click in the
-- picker): at no one, so your target isn't bothered. (Same back: nothing to play.)
local function TryEmote(token)
	if not token or token == SAME then return end
	pcall(DoEmote, token, "none")
end

-- A moment's emotes, saved as "THANK,BOW,SALUTE" (emoteVision<Id>Emotes).
local function ParseEmotes(text)
	local list = {}
	for token in tostring(text or ""):gmatch("[%w_]+") do
		if #list < MAX_EMOTES then list[#list + 1] = token:upper() end
	end
	return list
end

-- The moments, in the page's order: id, its switch, name, tip, the emotes
-- it starts with (its list: emoteVision<Id>Emotes), whether it can play the
-- same back, and a pretend one for Test.
local MOMENTS = {
	{ id = "Buff", on = "emoteVisionBuffs", name = "Someone buffs you", emotes = { "THANK", "BOW", "SALUTE" },
		tip = "A buff of a minute or more someone else puts on you (Fortitude, Arcane Intellect, a blessing...). " ..
			"Not heals over time.",
		sample = { name = "Aelwyn", class = "PRIEST", line = "gave you %s", spell = "Power Word: Fortitude",
			icon = "Interface\\Icons\\Spell_Holy_WordFortitude" } },
	{ id = "Res", on = "emoteVisionRes", name = "You're brought back to life", emotes = { "THANK", "KNEEL", "CHEER" },
		tip = "Someone resurrects you and you accept.",
		sample = { name = "Thornbrook", class = "DRUID", line = "brought you back to life" } },
	{ id = "Emote", on = "emoteVisionEmotes", name = "Someone emotes at you", emotes = { SAME, "WAVE", "SMILE" },
		same = true, tip = "Someone waves, bows, hugs or the like at you. Same back: the one they did.",
		sample = { name = "Pip", class = "MAGE", line = "waves at you.", same = "WAVE" } },
	{ id = "Summon", on = "emoteVisionSummon", name = "You're summoned", emotes = { "THANK", "WAVE" },
		tip = "A warlock's summon, or a meeting stone's, that you accept: once you're there.",
		sample = { name = "Velmora", class = "WARLOCK", line = "summoned you" } },
	{ id = "Trade", on = "emoteVisionTrade", name = "A trade goes through", emotes = { "THANK", "BOW" },
		tip = "A trade with someone finishes (both of you clicked Trade).",
		sample = { name = "Brakka", class = "WARRIOR", line = "traded with you" } },
	{ id = "Level", on = "emoteVisionLevel", name = "Someone in your group levels up",
		emotes = { "CONGRATULATE", "CHEER", "APPLAUD" }, near = true,
		tip = "Your party or raid's members, not you. Only when they're near you.",
		sample = { name = "Brakka", class = "WARRIOR", line = "reached level %d", level = 42 } },
	{ id = "Dungeon", on = "emoteVisionDungeon", name = "You clear a dungeon", emotes = { "THANK", "BOW", "CHEER" },
		journal = true, tip = "Its last boss down, in a group: the emotes go to everyone, not one person.",
		sample = { name = "The Deadmines", line = "cleared with your group", group = true,
			icon = "Interface\\Icons\\INV_Misc_Key_03" } },
	{ id = "Duel", on = "emoteVisionDuel", name = "A duel ends", emotes = { "BOW", "SALUTE", "CONGRATULATE" },
		tip = "Won or lost, against whoever it was.",
		sample = { name = "Kargash", class = "ROGUE", line = "lost a duel to you" } },
	{ id = "Join", on = "emoteVisionJoin", name = "Someone joins your group", emotes = { "WELCOME", "WAVE", "HELLO" },
		near = true, tip = "Someone new in your party or raid (not a whole raid filling at once), near you.",
		sample = { name = "Thornbrook", class = "DRUID", line = "joined your group" } },
	{ id = "Leave", on = "emoteVisionLeave", name = "Someone leaves your group", emotes = { "BYE", "WAVE", "THANK" },
		near = true, tip = "Someone near you leaves your party or raid.",
		sample = { name = "Velmora", class = "WARLOCK", line = "left your group" } },
	{ id = "Joined", on = "emoteVisionJoined", name = "You join a group", emotes = { "HELLO", "WAVE" },
		tip = "You join someone's party or raid with one of them near you: the emotes go to everyone, not " ..
			"one person.",
		sample = { name = "Your group", line = "you joined a group", group = true,
			icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" } },
	{ id = "Achievement", on = "emoteVisionAchievement", name = "Someone earns an achievement",
		emotes = { "CONGRATULATE", "CHEER", "APPLAUD" },
		near = true, tip = "Someone near you earns an achievement (a stranger, someone in your group or in " ..
			"your guild).",
		sample = { name = "Aelwyn", class = "PRIEST", line = "earned %s", spell = "Explore Elwynn Forest" } },
	{ id = "Boss", on = "emoteVisionBoss", name = "Your group kills a boss", emotes = { "CHEER", "ROAR", "VICTORY" },
		tip = "A boss down in a dungeon or raid with your group (each one, not just the last): the emotes go to " ..
			"everyone.",
		sample = { name = "Edwin VanCleef", line = "defeated with your group", group = true,
			icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" } },
	{ id = "Wipe", on = "emoteVisionWipe", name = "Your group wipes", emotes = { "SIGH", "CRY", "FACEPALM" },
		maxAge = 300, tip = "A boss fight lost with your group: the emotes go to everyone. If you died, the " ..
			"card waits until you're alive again (you can't emote while dead).",
		sample = { name = "Edwin VanCleef", line = "your group wiped", group = true,
			icon = "Interface\\Icons\\Ability_Rogue_FeignDeath" } },
	{ id = "Guild", on = "emoteVisionGuild", name = "You run into a guild member", emotes = { "WAVE", "HELLO", "HUG" },
		tip = "Someone from your guild (not in your group) comes into view: with friendly nameplates on, as " ..
			"soon as you see them; otherwise when you mouse over or target them. Once an hour per person.",
		sample = { name = "Brakka", class = "WARRIOR", line = "is in your guild" } },
	{ id = "Ally", on = "emoteVisionAlly", name = "You run into a recent ally", emotes = { "WAVE", "HELLO", "SALUTE" },
		ally = true,
		tip = "Someone you grouped with lately (the game's Recent Allies, not in your group now) comes into " ..
			"view: with friendly nameplates on, as soon as you see them; otherwise when you mouse over or " ..
			"target them. Once an hour per person.",
		sample = { name = "Thornbrook", class = "DRUID", line = "grouped with you before" } },
	{ id = "YouLevel", on = "emoteVisionYouLevel", name = "You level up", emotes = { "CHEER", "DANCE", "FLEX" },
		tip = "You reach a new level: the emotes go to everyone, to celebrate.",
		sample = { name = "You", line = "reached level %d", level = 42, group = true,
			icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight" } },
}
-- (No Encounter Journal, as on Classic Era: no telling a dungeon's last boss,
-- so no Dungeon moment there.)
if not (EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex) then
	for i = #MOMENTS, 1, -1 do
		if MOMENTS[i].journal then table.remove(MOMENTS, i) end
	end
end
-- (No Recent Allies on this client: no Ally moment.)
if not (C_RecentAllies and C_RecentAllies.IsRecentAllyByGUID) then
	for i = #MOMENTS, 1, -1 do
		if MOMENTS[i].ally then table.remove(MOMENTS, i) end
	end
end
local MOMENT = {}
for _, moment in ipairs(MOMENTS) do
	MOMENT[moment.id] = moment
	DEFAULTS[moment.on] = not moment.off
	moment.key = "emoteVision" .. moment.id .. "Emotes"
	DEFAULTS[moment.key] = table.concat(moment.emotes, ",")
end

-- Where: its Show in row, Out of combat ticked to start with (anywhere, so
-- long as you're not fighting or just out of a fight).
local ROW_KEY = "emote:vision"
ns.CINE_SHOW_SETTING[ROW_KEY] = "emoteVisionAlways"
ns.LIST_DEFAULTS.quietShow[ROW_KEY] = true
-- ...and its rule, given once (yours kept if you've written one): out of a
-- fight, anywhere.
local DEFAULT_RULE = "not combat"
local OLD_RULE = "not combat and world" -- (the first one given: changed to the new one if still unedited)
local function GiveRule()
	local db = ns.db
	if not db then return end
	-- (Your group wipes started off in the dev copy, then on: on, once.)
	if not db.emoteVisionWipeOnV1 then
		db.emoteVisionWipeOnV1 = true
		db.emoteVisionWipe = true
	end
	-- (Repeats were ignored for 10 minutes to start with, then 1: moved once
	-- if still 10.)
	if not db.emoteVisionRepeatV2 then
		db.emoteVisionRepeatV2 = true
		if db.emoteVisionRepeatMins == 10 then db.emoteVisionRepeatMins = 1 end
	end
	if db.emoteVisionRuleV1 and not db.emoteVisionRuleV2 and db.frameRules
		and db.frameRules[ROW_KEY] == OLD_RULE then
		db.frameRules[ROW_KEY] = DEFAULT_RULE
	end
	db.emoteVisionRuleV2 = true
	if db.emoteVisionRuleV1 then return end
	db.emoteVisionRuleV1 = true
	db.frameRules = db.frameRules or {}
	if db.frameRules[ROW_KEY] == nil then db.frameRules[ROW_KEY] = DEFAULT_RULE end
end

local WIDTH = 300
local FADE_IN, FADE_OUT = 0.25, 0.4
local AGAIN_SOON = 5       -- with repeats not ignored: the same moment this soon is still one (a doubled event)
local MAX_AGE = 20         -- a queued moment older than this (a long fight) is dropped
local MAX_QUEUE = 4
local SPEECH_GAP = 24      -- the card this far above the box where speech from behind you shows
local MIN_BUFF = 60        -- a buff shorter than this (a heal over time, a shield) isn't a card
local GOLD = { 1, 0.82, 0 }
local BORDER_GOLD = { 0.55, 0.42, 0.16 }

-- An emote at you, by the words in it (English), for Same back.
local EMOTE_WORDS = {
	{ "thank", "THANK" }, { "high", "HIGHFIVE" }, { "wave", "WAVE" }, { "bow", "BOW" }, { "hug", "HUG" },
	{ "cheer", "CHEER" }, { "greet", "HELLO" }, { "hello", "HELLO" }, { "salute", "SALUTE" }, { "smile", "SMILE" },
	{ "kiss", "KISS" }, { "dance", "DANCE" }, { "applaud", "APPLAUD" }, { "clap", "APPLAUD" },
	{ "curtsey", "CURTSEY" }, { "congratulat", "CONGRATULATE" }, { "welcome", "WELCOME" }, { "farewell", "BYE" },
	{ "goodbye", "BYE" }, { "grin", "GRIN" }, { "wink", "WINK" }, { "laugh", "LAUGH" }, { "giggle", "GIGGLE" },
	{ "love", "LOVE" }, { "flex", "FLEX" }, { "roar", "ROAR" }, { "apolog", "APOLOGIZE" }, { "kneel", "KNEEL" },
}

local card, queue, lastFrom = nil, {}, {}
local showing -- (the moment on the card: { kind, name, unit, guid, class, line, same, group, test })
local moving   -- (Move: the card held up to drag)
local resFrom  -- (who offered to bring you back: { name, at })
local summonFrom -- (who's summoning you: { name, at })
local tradeWith  -- (who the trade window's with: { name, guid, class })
local levels = {} -- (your group's levels, by GUID: who went up)
local dead = false

local function Plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local function DB() return ns.GetDB() or DEFAULTS end

local function Look()
	return ns.StyleLook("emoteVision")
end

local function Fighting()
	return InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
end

-- The unit someone is now, if any (their face, and the emote aimed at them).
-- (By name: "Name" or, from another realm, "Name-Realm".)
local function UnitFor(guid, name)
	if not guid and not name then return nil end
	local function Is(unit)
		local each = Plain(UnitGUID(unit))
		if guid then return each == guid end
		if not each then return false end
		local own, realm = UnitName(unit)
		own, realm = Plain(own), Plain(realm)
		return own == name or (type(own) == "string" and type(realm) == "string" and realm ~= ""
			and own .. "-" .. realm == name)
	end
	for _, unit in ipairs({ "target", "mouseover", "focus" }) do
		if Is(unit) then return unit end
	end
	if guid and UnitTokenFromGUID then
		local ok, token = pcall(UnitTokenFromGUID, guid)
		if ok and Plain(token) then return token end
	end
	local group = IsInRaid() and "raid" or "party"
	for i = 1, IsInRaid() and 40 or 4 do
		if Is(group .. i) then return group .. i end
	end
	for i = 1, 40 do
		if Is("nameplate" .. i) then return "nameplate" .. i end
	end
end

-- The emotes a moment's buttons play, as its list says (same: the one done
-- at you, for Same back; none of them twice). own: a list to use instead.
-- Whether this client has the emote (one picked on another client, or a
-- default newer than it, isn't a button: it would do nothing). With no list
-- of the game's to ask (its globals gone), all are kept.
local function HasEmote(token)
	local game = GameEmotes()
	if #game.text == 0 then return true end
	return game.command[token] ~= nil or game.isVoice[token] == true
end

local function EmotesFor(kind, same, own)
	local moment = MOMENT[kind]
	local list, seen = {}, {}
	for _, token in ipairs(own or ParseEmotes(moment and DB()[moment.key])) do
		if token == SAME then token = same end
		if token and not seen[token] and HasEmote(token) then
			seen[token] = true
			list[#list + 1] = token
		end
	end
	return list
end

---------------------------------------------------------------------------
-- The card, in one of six styles (emoteVisionLook, its Style tab):
--   classic    a dark panel, its border Visions Style's, buttons in a row
--   parchment  a letter: cream paper, a brown double edge, the name in
--              Morpheus, a red seal round the face, the emotes underlined words
--   bubble     the game's own chat bubble (as speech from behind you), its
--              tail at their face beside it, the emotes small tabs
--   subtitle   no panel: outlined words, the emotes gold words in a row
--   banner     a dark band between two gold lines, the moment's heading
--              over the name (A KINDNESS...), the emotes in gold boxes
--   wheel      their face in a dark disc, the emotes round it, as our wheels
-- layout: "left" (face on the left, words beside it), "center" (no face,
-- everything centered) or "wheel"; buttons: "panel" (the game's buttons),
-- "link" (words), "tab" (words on a dark tab) or "box" (words in a frame).
local LOOKS = {
	classic = { layout = "left", width = 300, panel = "visions", buttons = "panel", bar = GOLD, close = true },
	-- (Its words nearly black-brown: lighter browns were hard to read on the paper.)
	parchment = { layout = "left", width = 290, buttons = "tab", tab = { 0.42, 0.27, 0.1, 0.3 }, close = true,
		tabEdge = { 0.3, 0.18, 0.06 },
		panel = { paper = true, edge = { 0.36, 0.22, 0.09 } },
		name = { 0.14, 0.08, 0.02 }, line = { 0.2, 0.12, 0.04 }, link = { 0.16, 0.08, 0.02 },
		ring = { 0.6, 0.16, 0.13 }, bar = { 0.42, 0.29, 0.14 }, rule = { 0.62, 0.5, 0.31 },
		nameFont = "Fonts\\MORPHEUS.TTF", noShadow = true },
	bubble = { layout = "left", width = 316, panel = "bubble", buttons = "tab", faceOut = 58, barInset = 14,
		line = { 1, 1, 1 }, link = GOLD, bar = { 0.75, 0.75, 0.75 } },
	subtitle = { layout = "center", width = 320, panel = "shade", buttons = "tab", tab = { 0, 0, 0, 0.55 },
		outline = true, name = { 1, 1, 1 }, link = GOLD, bar = { 1, 0.82, 0, 0.5 }, barShare = 0.3 },
	banner = { layout = "center", width = 280, buttons = "box", heading = true, close = true,
		panel = { bg = { 0.04, 0.04, 0.05, 0.92 } }, lines = { 0.79, 0.64, 0.29 },
		name = { 1, 1, 1 }, line = { 0.75, 0.71, 0.6 }, link = { 0.79, 0.64, 0.29 }, bar = { 0.79, 0.64, 0.29 } },
	wheel = { layout = "wheel", width = 200, buttons = "panel", fit = true, face = 56, outline = true },
}
local LOOK_ORDER = { "classic", "parchment", "bubble", "subtitle", "banner", "wheel" }
local LOOK_NAMES = { classic = "Classic", parchment = "Parchment letter", bubble = "Speech bubble",
	subtitle = "Subtitle", banner = "Banner", wheel = "Wheel" }
local LOOK_TIPS = {
	classic = "A dark panel, its border Visions Style's, the emotes as buttons.",
	parchment = "A letter on the game's own mail paper, a brown edge, a red seal round their face, the emotes on " ..
		"brown tabs.",
	bubble = "The game's own chat bubble, as speech from behind you, pointing at their face.",
	subtitle = "Outlined words on a dark band that fades out at both ends, as a film's subtitles, the emotes on " ..
		"dark tabs. Their face isn't shown.",
	banner = "A dark band between two gold lines, a heading for the moment over the name (A KINDNESS, SAVED...). " ..
		"Their face isn't shown.",
	wheel = "Their face in a dark disc, the emotes round it, as Cinematic's wheels.",
}
DEFAULTS.emoteVisionLook = "classic"
-- The banner's heading over the name, by moment.
local HEADINGS = { Buff = "A KINDNESS", Res = "SAVED", Emote = "A GREETING", Summon = "SUMMONED",
	Trade = "A FAIR TRADE", Level = "LEVEL UP", Dungeon = "VICTORY", Duel = "THE DUEL", Join = "WELCOME",
	Leave = "FAREWELL", Joined = "WELL MET", Achievement = "WELL DONE", Boss = "VICTORY", Wipe = "NEXT TIME",
	YouLevel = "LEVEL UP", Guild = "WELL MET", Ally = "WELL MET" }
local BUTTON_W, BUTTON_H, BUTTON_GAP, ROW_GAP = 84, 24, 8, 6
local WHEEL_DISC, WHEEL_REACH = 170, 74 -- the wheel's disc, and how far out its emotes sit (on its edge)

local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]
local function StyleText(text, look, outline)
	text.base = text.base or { text:GetFont() }
	local file, size, flags = text.base[1], text.base[2], text.base[3]
	if not (file and size) then return end
	if ROMAN then file = ns.StyleFontFile(look.emoteFont) or file end
	flags = ns.OutlinedFlags(flags, look.emoteOutline)
	-- (No panel behind it: an outline always, to read over the world.)
	if outline and not tostring(flags or ""):find("OUTLINE") then flags = "OUTLINE" end
	text:SetFont(file, size * (tonumber(look.emoteTextSize) or 1) * ns.VisionTextScale(), flags)
	ns.SetTextShadow(text, look.emoteShadow)
end
local function Color(text, color)
	if color then text:SetTextColor(color[1], color[2], color[3], 1) end
end

local Hide, Next

local function LookNow()
	return LOOKS[DB().emoteVisionLook] or LOOKS.classic
end

local function Place()
	local db = DB()
	local scale = tonumber(db.emoteVisionScale) or 1
	card:SetScale(scale)
	card:ClearAllPoints()
	-- (To start with: its left edge on theirs, a little above their box.)
	if db.emoteVisionSpot ~= "own" and ns.SpeechBehindSpot then
		local left, bottom, _, height = ns.SpeechBehindSpot()
		if type(left) == "number" and type(bottom) == "number" then
			-- (Whole units: a card between pixels draws its thin edges broken.)
			card:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", math.floor(left / scale + 0.5),
				math.floor((bottom + height + SPEECH_GAP) / scale + 0.5))
			return
		end
	end
	card:SetPoint("BOTTOM", UIParent, "BOTTOM", math.floor((tonumber(db.emoteVisionX) or 0) / scale + 0.5),
		math.floor((tonumber(db.emoteVisionY) or 260) / scale + 0.5))
end

-- The panel behind the words, as the style says (classic: Visions Style's
-- border).
local function Panel(style)
	local panel = card.panel
	panel:SetShown(style.panel ~= nil and style.panel ~= "bubble" and style.panel ~= "shade")
	card.bubble:SetShown(style.panel == "bubble")
	if panel.wash then panel.wash:SetShown(type(style.panel) == "table" and style.panel.paper == true) end
	for _, half in ipairs(card.shade) do half:SetShown(style.panel == "shade") end
	if style.panel == "visions" then
		local kind, size, r, g, b = ns.StyleBorder(Look(), "emoteBorder", BORDER_GOLD)
		if kind == "line" then
			panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
				edgeSize = size })
			panel:SetBackdropBorderColor(r, g, b, 1)
		elseif kind == "game" then
			panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
				insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			panel:SetBackdropBorderColor(BORDER_GOLD[1], BORDER_GOLD[2], BORDER_GOLD[3], 1)
		else
			panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
		end
		panel:SetBackdropColor(0.04, 0.04, 0.05, 0.9)
	elseif type(style.panel) == "table" and style.panel.paper then
		-- (The letter's: the game's own mail paper, the rounded tooltip edge in brown.)
		panel:SetBackdrop({ bgFile = "Interface\\Stationery\\StationeryTest1",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		panel:SetBackdropColor(1, 1, 1, 1)
		local edge = style.panel.edge
		panel:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
		-- (A cream wash over the paper, evening out its darker patches so the
		-- words read.)
		if not panel.wash then
			panel.wash = panel:CreateTexture(nil, "BORDER")
			panel.wash:SetPoint("TOPLEFT", 4, -4)
			panel.wash:SetPoint("BOTTOMRIGHT", -4, 4)
		end
		panel.wash:SetColorTexture(0.96, 0.91, 0.79, 0.55)
	elseif type(style.panel) == "table" then
		local own = style.panel
		if own.edge then
			panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
				edgeSize = own.edgeSize or 1 })
			panel:SetBackdropBorderColor(own.edge[1], own.edge[2], own.edge[3], 1)
		else
			panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
		end
		panel:SetBackdropColor(own.bg[1], own.bg[2], own.bg[3], own.bg[4] or 1)
	end
	for _, line in ipairs({ card.lineTop, card.lineBottom }) do
		line:SetShown(style.lines ~= nil)
		if style.lines then line:SetColorTexture(style.lines[1], style.lines[2], style.lines[3], 1) end
	end
	card.rule:SetShown(style.rule ~= nil)
	if style.rule then card.rule:SetColorTexture(style.rule[1], style.rule[2], style.rule[3], 0.45) end
	card.disc:SetShown(style.layout == "wheel")
	card.discEdge:SetShown(style.layout == "wheel")
end

-- Plays emote at the one on the card ("none": at no one, for the group's
-- cards; a test: says so in chat instead).
local function Answer(token)
	local moment = showing
	if not moment then return end
	if moment.test then
		ns.Print(L["Emote Vision test: you'd %s %s."]:format(Command(token), moment.name))
	elseif moment.group then
		pcall(DoEmote, token, "none")
	else
		local name = moment.fullName or moment.name
		local unit = UnitFor(moment.guid, name) or name
		pcall(DoEmote, token, unit)
	end
	Hide()
end

-- A word button (the styles but Classic's): its words, a tab or frame behind
-- them if the style has one, a line under them for the letter's.
local function WordButton()
	local button = CreateFrame("Button", nil, card.front)
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	button.text:SetPoint("CENTER")
	button.back = button:CreateTexture(nil, "BACKGROUND")
	button.back:SetAllPoints()
	button.edges = {}
	for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
		{ "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local edge = button:CreateTexture(nil, "BORDER")
		edge:SetPoint(side[1])
		edge:SetPoint(side[2])
		-- (At least one real pixel at any UI scale: a 1-unit line can round to
		-- nothing, leaving the frame broken.)
		local set = PixelUtil and (i <= 2 and PixelUtil.SetHeight or PixelUtil.SetWidth)
		if set then set(edge, 1, 1) elseif i <= 2 then edge:SetHeight(1) else edge:SetWidth(1) end
		button.edges[i] = edge
	end
	button.under = button:CreateTexture(nil, "ARTWORK")
	button.under:SetHeight(1)
	button.under:SetPoint("TOPLEFT", button.text, "BOTTOMLEFT", 0, -1)
	button.under:SetPoint("TOPRIGHT", button.text, "BOTTOMRIGHT", 0, -1)
	button:SetScript("OnEnter", function(self) self.text:SetAlpha(0.7) end)
	button:SetScript("OnLeave", function(self) self.text:SetAlpha(1) end)
	button:SetScript("OnClick", function(self) Answer(self.token) end)
	return button
end

local function Create()
	card = CreateFrame("Frame", "CinematicEmoteVision", UIParent)
	card:SetSize(WIDTH, 96)
	card:SetFrameStrata("DIALOG")
	card:SetClampedToScreen(true)
	card:EnableMouse(true)
	card:SetMovable(true)
	card:RegisterForDrag("LeftButton")
	card:Hide()

	-- (What's behind the words: a panel, the game's chat bubble, a banner's
	-- lines, a letter's rule, a wheel's disc. Each style shows its own.)
	card.panel = CreateFrame("Frame", nil, card, "BackdropTemplate")
	card.panel:SetFrameLevel(card:GetFrameLevel() + 1)
	card.bubble = ns.MakeGameBubble and ns.MakeGameBubble(card) or CreateFrame("Frame", nil, card)
	card.bubble:SetFrameLevel(card:GetFrameLevel() + 1)
	-- (Its tail turned to point left, at the face: its texture's corners moved
	-- round a quarter turn and its width and height swapped, as Speech.lua turns
	-- its tails. SetRotation turns it inside its own box, squashing it.)
	local tail = card.bubble.tail
	if tail then
		local c = { tail:GetTexCoord() } -- upper left, lower left, upper right, lower right: x, y each
		if #c >= 8 then
			-- (A quarter turn clockwise: its bottom, the tip, becomes its left side.)
			tail:SetTexCoord(c[3], c[4], c[7], c[8], c[1], c[2], c[5], c[6])
			local w, h = tail:GetSize()
			if w and h and w > 0 and h > 0 then tail:SetSize(h, w) end
		end
	end
	-- (Everything else on a frame above them: a backdrop or the bubble's art,
	-- frames of their own, would cover what's drawn on the card itself.)
	card.front = CreateFrame("Frame", nil, card)
	card.front:SetAllPoints()
	card.front:SetFrameLevel(card:GetFrameLevel() + 5)
	local front = card.front
	card.lineTop = front:CreateTexture(nil, "ARTWORK")
	card.lineBottom = front:CreateTexture(nil, "ARTWORK")
	card.rule = front:CreateTexture(nil, "ARTWORK")
	card.rule:SetHeight(1)
	-- (The subtitle's: a dark band behind the words, fading out to both ends,
	-- as a film's subtitles have. Flat where the client can't fade a texture.)
	card.shade = {}
	for i, side in ipairs({ "LEFT", "RIGHT" }) do
		local half = card:CreateTexture(nil, "BACKGROUND")
		half:SetColorTexture(1, 1, 1, 1)
		half:SetPoint("TOP")
		half:SetPoint("BOTTOM")
		half:SetPoint(side)
		half:SetPoint(i == 1 and "RIGHT" or "LEFT", card, "CENTER")
		local clear, dark = 0, 0.6
		local fromA, toA = i == 1 and clear or dark, i == 1 and dark or clear
		if not (CreateColor and pcall(half.SetGradient, half, "HORIZONTAL", CreateColor(0, 0, 0, fromA),
			CreateColor(0, 0, 0, toA))) then
			half:SetColorTexture(0, 0, 0, 0.35)
		end
		half:Hide()
		card.shade[i] = half
	end
	card.discEdge = card:CreateTexture(nil, "BACKGROUND", nil, -1)
	card.discEdge:SetColorTexture(0.79, 0.64, 0.29, 0.7) -- (a whole circle under the disc: only its rim shows)
	card.disc = card:CreateTexture(nil, "BACKGROUND")
	card.disc:SetColorTexture(0.05, 0.05, 0.06, 0.9) -- (dark enough that the gold under it doesn't tint it)

	card.portrait = front:CreateTexture(nil, "ARTWORK")
	card.portrait:SetSize(40, 40)
	-- (A ring round it in their class's color: a circle a little bigger, under it.)
	card.ring = front:CreateTexture(nil, "BORDER")
	card.ring:SetSize(44, 44)
	card.ring:SetPoint("CENTER", card.portrait, "CENTER")
	card.ring:SetColorTexture(1, 1, 1, 1)
	-- (All round: mask textures, not SetMask, which forbids the icons' tex coords.)
	if card.CreateMaskTexture then
		for _, texture in ipairs({ card.portrait, card.ring, card.disc, card.discEdge }) do
			local mask = texture:GetParent():CreateMaskTexture()
			mask:SetAllPoints(texture)
			mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIONAL",
				"CLAMPTOBLACKADDITIONAL")
			texture:AddMaskTexture(mask)
		end
	end

	card.heading = front:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.name = front:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	card.name:SetWordWrap(false)
	card.line = front:CreateFontString(nil, "OVERLAY", "GameFontNormal")

	card.close = CreateFrame("Button", nil, front, "UIPanelCloseButton")
	card.close:SetScale(0.7)
	card.close:SetScript("OnClick", function() Hide() end)

	card.buttons, card.words = {}, {}
	for i = 1, MAX_EMOTES do
		local button = ns.PanelButton(front)
		button:SetSize(BUTTON_W, BUTTON_H)
		button:SetScript("OnClick", function(self) Answer(self.token) end)
		card.buttons[i] = button
		card.words[i] = WordButton()
	end

	card.bar = front:CreateTexture(nil, "ARTWORK")
	card.bar:SetHeight(2)

	-- (Moving it: any card dragged where you want it, Move's or a real one, kept
	-- from the bottom middle; one fading away is brought back first.)
	card:SetScript("OnDragStart", function(self)
		self.leaving, self.dragging = nil, true
		self:SetAlpha(1)
		self:StartMoving()
	end)
	card:SetScript("OnDragStop", function(self)
		self.dragging = nil
		self:StopMovingOrSizing()
		if self.SetUserPlaced then self:SetUserPlaced(false) end
		local left, right, bottom = self:GetLeft(), self:GetRight(), self:GetBottom()
		if type(left) == "number" and type(bottom) == "number" then
			local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
			local db = ns.GetDB()
			db.emoteVisionX = math.floor((left + right) / 2 * scale - UIParent:GetWidth() / 2 + 0.5)
			db.emoteVisionY = math.floor(bottom * scale + 0.5)
			db.emoteVisionSpot = "own"
		end
		Place()
		if ns.RefreshOptions then pcall(ns.RefreshOptions) end
	end)
	card:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then Hide() end
	end)

	card:SetScript("OnUpdate", function(self, elapsed)
		if moving or self.dragging then self:SetAlpha(1) return end
		-- (The mouse over it: its time stands still.)
		if not ns.Flag(self:IsMouseOver()) then self.age = self.age + elapsed end
		local hold = tonumber(DB().emoteVisionHold) or 8
		local age = self.age
		if self.leaving then
			self.leaving = self.leaving + elapsed
			if self.leaving >= FADE_OUT then
				self:Hide()
				return
			end
			self:SetAlpha(1 - self.leaving / FADE_OUT)
			return
		end
		self:SetAlpha(math.min(1, age / FADE_IN))
		self.bar:SetWidth(math.max(1, (self.barWidth or 100) * (1 - math.min(1, age / hold))))
		if age >= hold then self.leaving = 0 end
	end)
	card:SetScript("OnHide", function()
		showing = nil
		if not moving then C_Timer.After(0.3, function() Next() end) end
	end)

	if ns.WhyRegister then
		ns.WhyRegister(card, L["Emote Vision"], "Emote Vision", function()
			return { showing and (showing.test or showing.tried) and L["its test"]
				or L["someone did something for you (or at you)"] }
		end)
	end
end

-- The face: their portrait when in sight, else their class's icon, else the
-- moment's own icon.
local function Face(moment)
	local unit = moment.unit and Plain(UnitExists(moment.unit)) and moment.unit
	if unit then
		SetPortraitTexture(card.portrait, unit)
		card.portrait:SetTexCoord(0, 1, 0, 1)
	elseif moment.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[moment.class] then
		card.portrait:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		card.portrait:SetTexCoord(unpack(CLASS_ICON_TCOORDS[moment.class]))
	else
		card.portrait:SetTexture(moment.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		card.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

-- The emotes' buttons as the style has them, each with its token and width.
local function EmoteButtons(style, emotes, look)
	local list = {}
	for i = 1, MAX_EMOTES do
		local panelButton, word = card.buttons[i], card.words[i]
		panelButton:Hide()
		word:Hide()
		local token = emotes[i]
		if token then
			local button
			if style.buttons == "panel" then
				button = panelButton
				StyleText(button:GetFontString(), look)
				button:SetText(EmoteName(token))
				-- (fit: as wide as its name, the wheel's, not all the same width)
				button.width = style.fit and math.max(56, math.ceil(button:GetFontString():GetStringWidth()) + 22)
					or BUTTON_W
				button:SetWidth(button.width)
			else
				button = word
				StyleText(button.text, look, style.outline)
				button.text:SetText(EmoteName(token))
				Color(button.text, style.link)
				local tab, box = style.buttons == "tab", style.buttons == "box"
				button.back:SetShown(tab)
				local back = style.tab or { 0, 0, 0, 0.45 }
				if tab then button.back:SetColorTexture(back[1], back[2], back[3], back[4]) end
				-- (A frame: the banner's boxes, or a tab's own edge, the letter's.)
				local color = style.tabEdge or style.link or GOLD
				for _, edge in ipairs(button.edges) do
					edge:SetShown(box or style.tabEdge ~= nil)
					edge:SetColorTexture(color[1], color[2], color[3], 0.9)
				end
				button.under:SetShown(style.underline == true)
				button.under:SetColorTexture(color[1], color[2], color[3], 0.8)
				button.width = math.ceil(button.text:GetStringWidth()) + ((tab or box) and 22 or 8)
				button:SetSize(button.width, BUTTON_H - 2)
			end
			button.token = token
			list[#list + 1] = button
		end
	end
	return list
end

-- buttons in rows of three, each row centered on middle; gives the height.
local function Rows(buttons, middle, top, room)
	-- (Rows of up to three, fewer where long names wouldn't fit in room.)
	local lines, line, used = {}, {}, 0
	for _, button in ipairs(buttons) do
		local need = button.width + (#line > 0 and BUTTON_GAP or 0)
		if #line > 0 and (#line == 3 or used + need > room) then
			lines[#lines + 1], line, used = line, {}, 0
			need = button.width
		end
		line[#line + 1] = button
		used = used + need
	end
	if #line > 0 then lines[#lines + 1] = line end
	for row, each in ipairs(lines) do
		local total = 0
		for _, button in ipairs(each) do total = total + button.width + BUTTON_GAP end
		local x = math.floor(middle - (total - BUTTON_GAP) / 2 + 0.5) -- (whole pixels: crisp edges)
		for _, button in ipairs(each) do
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", card, "TOPLEFT", x, -top - (row - 1) * (BUTTON_H + ROW_GAP))
			button:Show()
			x = x + button.width + BUTTON_GAP
		end
	end
	return #lines * BUTTON_H + (#lines - 1) * ROW_GAP
end

-- The card for moment: its face, name, line and buttons (its emotes as its
-- list says now), in the style picked, laid out to fit. False if it has no
-- buttons to show.
local function Show(moment)
	local emotes = EmotesFor(moment.kind, moment.same, moment.emotes)
	if #emotes == 0 then return false end
	if not card then Create() end
	showing = moment
	local style, look, db = LookNow(), Look(), DB()
	Panel(style)
	Place()

	-- Words: Visions Style's look, then the style's own colors (and font).
	for _, text in ipairs({ card.name, card.line, card.heading }) do StyleText(text, look, style.outline) end
	if style.nameFont and ROMAN then
		local _, size, flags = card.name:GetFont()
		card.name:SetFont(style.nameFont, (size or 16) + 2, flags)
	end
	if style.noShadow then
		for _, text in ipairs({ card.name, card.line }) do text:SetShadowOffset(0, 0) end
	end
	card.name:SetText(moment.name)
	card.line:SetText(moment.line)
	local class = moment.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[moment.class]
	if style.name then Color(card.name, style.name)
	elseif class then card.name:SetTextColor(class.r, class.g, class.b, 1)
	else Color(card.name, { 1, 1, 1 }) end
	Color(card.line, style.line or GOLD)
	local ring = style.ring or (class and { class.r, class.g, class.b }) or GOLD
	card.ring:SetVertexColor(ring[1], ring[2], ring[3], 1)
	card.heading:SetShown(style.heading == true)
	if style.heading then
		card.heading:SetText(L[HEADINGS[moment.kind] or "A KINDNESS"])
		Color(card.heading, style.lines or GOLD)
	end
	local face = db.emoteVisionPortrait and style.layout ~= "center"
	-- (Its size: the style's, the wheel's bigger in its middle.)
	local faceSize = style.face or 40
	card.portrait:SetSize(faceSize, faceSize)
	card.ring:SetSize(faceSize + 4, faceSize + 4)
	card.portrait:SetShown(face)
	card.ring:SetShown(face)
	if face then Face(moment) end
	card.close:SetShown(style.close == true)
	local buttons = EmoteButtons(style, emotes, look)
	local width = style.width
	local height
	for _, text in ipairs({ card.name, card.line, card.heading }) do text:ClearAllPoints() end
	card.portrait:ClearAllPoints()
	card.bar:ClearAllPoints()
	card.bar:SetShown(style.bar ~= nil)
	if style.bar then card.bar:SetColorTexture(style.bar[1], style.bar[2], style.bar[3], 0.8) end

	if style.layout == "left" then
		-- Face on the left (outside the panel for the bubble), the words beside it.
		local out = style.faceOut or 0
		local inside = out > 0 and out or 0 -- (where the panel starts)
		if face then card.portrait:SetPoint("TOPLEFT", card, "TOPLEFT", out > 0 and 4 or 12, -10) end
		local left = inside + ((face and out == 0) and 62 or 14)
		card.name:SetJustifyH("LEFT")
		card.line:SetJustifyH("LEFT")
		card.name:SetPoint("TOPLEFT", card, "TOPLEFT", left, -12)
		card.name:SetPoint("RIGHT", card, "RIGHT", -24, 0)
		card.line:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
		card.line:SetPoint("RIGHT", card, "RIGHT", -12, 0)
		local top = 14 + card.name:GetStringHeight() + 3 + card.line:GetStringHeight()
		if face and out == 0 then top = math.max(top, 56) end
		top = top + 8
		if style.rule then
			card.rule:ClearAllPoints()
			card.rule:SetPoint("TOPLEFT", card, "TOPLEFT", inside + 14, -top + 2)
			card.rule:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -top + 2)
			top = top + 6
		end
		top = top + Rows(buttons, inside + (width - inside) / 2, top, width - inside - 24 - (style.barInset or 0) * 2)
		local barIn = style.barInset or 0 -- (the bubble's: clear of its rounded edge)
		height = top + 14 + barIn / 2
		card.panel:ClearAllPoints()
		card.panel:SetPoint("TOPLEFT", card, "TOPLEFT", inside, 0)
		card.panel:SetPoint("BOTTOMRIGHT")
		card.bubble:ClearAllPoints()
		card.bubble:SetPoint("TOPLEFT", card, "TOPLEFT", inside, 0)
		card.bubble:SetPoint("BOTTOMRIGHT")
		if card.bubble.tail then
			card.bubble.tail:ClearAllPoints()
			card.bubble.tail:SetPoint("RIGHT", card.bubble, "LEFT", card.bubble.tailInto or 3, 0)
			card.bubble.tail:SetPoint("TOP", card, "TOP", 0, -24)
		end
		card.barWidth = width - inside - 16 - barIn * 2
		card.bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", inside + 8 + barIn, 5 + barIn / 2)
		card.close:ClearAllPoints()
		card.close:SetPoint("TOPRIGHT", card, "TOPRIGHT", 2, 2)
	elseif style.layout == "center" then
		-- No face: a heading (the banner's), the name and line, the buttons,
		-- all centered.
		local top = 10
		card.heading:SetJustifyH("CENTER")
		if style.heading then
			card.heading:SetPoint("TOP", card, "TOP", 0, -top)
			top = top + card.heading:GetStringHeight() + 3
		end
		card.name:SetJustifyH("CENTER")
		card.line:SetJustifyH("CENTER")
		card.name:SetPoint("TOP", card, "TOP", 0, -top)
		card.name:SetWidth(width - 40)
		top = top + card.name:GetStringHeight() + 3
		card.line:SetPoint("TOP", card, "TOP", 0, -top)
		card.line:SetWidth(width - 24)
		top = top + card.line:GetStringHeight() + 10
		top = top + Rows(buttons, width / 2, top, width - 24)
		height = top + 14
		card.panel:ClearAllPoints()
		card.panel:SetAllPoints()
		card.lineTop:ClearAllPoints()
		card.lineTop:SetPoint("TOPLEFT")
		card.lineTop:SetPoint("TOPRIGHT")
		card.lineTop:SetHeight(2)
		card.lineBottom:ClearAllPoints()
		card.lineBottom:SetPoint("BOTTOMLEFT")
		card.lineBottom:SetPoint("BOTTOMRIGHT")
		card.lineBottom:SetHeight(2)
		card.barWidth = width * (style.barShare or 1) - (style.barShare and 0 or 16)
		card.bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", (width - card.barWidth) / 2, 6)
		card.close:ClearAllPoints()
		card.close:SetPoint("TOPRIGHT", card, "TOPRIGHT", 2, 2)
	else
		-- The wheel: a disc, the face in its middle and the name under it, the
		-- emotes round it (the first at the top), the line under the disc.
		local middle = width / 2
		card.discEdge:ClearAllPoints()
		card.discEdge:SetSize(WHEEL_DISC + 4, WHEEL_DISC + 4)
		card.discEdge:SetPoint("CENTER", card, "TOPLEFT", middle, -middle)
		card.disc:ClearAllPoints()
		card.disc:SetSize(WHEEL_DISC, WHEEL_DISC)
		card.disc:SetPoint("CENTER", card, "TOPLEFT", middle, -middle)
		if face then
			card.portrait:SetPoint("CENTER", card, "TOPLEFT", middle, -middle)
		end
		-- (The name under the disc, whole: inside it a long one was cut short.)
		card.name:SetJustifyH("CENTER")
		card.name:SetWidth(width + 60)
		card.name:SetPoint("TOP", card, "TOPLEFT", middle, -width - 2)
		for i, button in ipairs(buttons) do
			local angle = math.pi / 2 - (i - 1) * 2 * math.pi / #buttons
			button:ClearAllPoints()
			button:SetPoint("CENTER", card, "TOPLEFT", middle + math.cos(angle) * WHEEL_REACH,
				-middle + math.sin(angle) * WHEEL_REACH)
			button:Show()
		end
		card.line:SetJustifyH("CENTER")
		card.line:SetWidth(width + 60)
		card.line:SetPoint("TOP", card.name, "BOTTOM", 0, -2)
		height = width + 8 + card.name:GetStringHeight() + card.line:GetStringHeight()
	end
	-- (Whole pixels: the bubble's and the letter's tiled edges went crooked, seams
	-- showing, on a size from the words' heights.)
	card:SetSize(math.floor(width + 0.5), math.floor(height + 0.5))
	card.age, card.leaving = 0, nil
	card:SetAlpha(0)
	card:Show()
	return true
end

function Hide()
	moving = nil -- (closed while moving it: let go too)
	if card and card:IsShown() and not card.leaving then card.leaving = 0 end
end

-- Whether it shows here now (its page, its Show in row, standing still if
-- it says so).
local function Allowed()
	if not ns.Setting("emoteVision") then return false end
	if Fighting() then return false end
	-- (No emoting while dead or a ghost: a wipe's card waits until you're back.)
	if ns.Flag(UnitIsDeadOrGhost("player")) then return false end
	if DB().emoteVisionStill and ns.playerMoving then return false end
	local ok, here = pcall(ns.RowOnNow, ROW_KEY, nil, true)
	return ok and here and true or false
end

-- The next queued moment once it can show (out of a fight and the calm
-- after it, standing still...); the old ones dropped. Asks again each
-- second while any wait.
local retry
function Next()
	if card and card:IsShown() then return end
	local now = GetTime()
	for i = #queue, 1, -1 do
		local kind = MOMENT[queue[i].kind]
		if now - queue[i].at > (kind and kind.maxAge or MAX_AGE) then table.remove(queue, i) end
	end
	while queue[1] and Allowed() do
		local moment = table.remove(queue, 1)
		if Show(moment) then
			-- (Repeats count from a card shown: one dropped unseen doesn't hold the next back.)
			if moment.key then lastFrom[moment.key] = GetTime() end
			return
		end
	end
	if queue[1] and not retry then
		retry = C_Timer.NewTimer(1, function()
			retry = nil
			Next()
		end)
	end
end

-- A moment worth a card: its kind (MOMENTS' id), who, what (its line).
-- The same person's same moment again within the page's minutes of its card
-- showing is ignored (with that off, only a doubled event's), and so is one
-- already waiting in the queue.
local function Fire(moment)
	if not ns.Setting("emoteVision") then return end
	local db = DB()
	local kind = MOMENT[moment.kind]
	if not (kind and db[kind.on]) then return end
	local who = moment.guid or moment.name
	if not who then return end
	local key = moment.kind .. ":" .. who
	local now = GetTime()
	local wait = db.emoteVisionRepeats and (tonumber(db.emoteVisionRepeatMins) or 10) * 60 or AGAIN_SOON
	if lastFrom[key] and now - lastFrom[key] < wait then return end
	for _, each in ipairs(queue) do
		if each.key == key then return end
	end
	moment.key, moment.at = key, now
	if #queue < MAX_QUEUE then queue[#queue + 1] = moment end
	Next()
end

-- Whether unit is near enough to see your emote (in view of you, as the game
-- draws them: about 100 yards).
local function Near(unit)
	return unit ~= nil and ns.Flag(UnitIsVisible(unit)) and true or false
end

-- Whether anyone in your group is near you.
local function GroupNear()
	local group = IsInRaid() and "raid" or "party"
	for i = 1, IsInRaid() and 40 or 4 do
		local unit = group .. i
		if not ns.Flag(UnitIsUnit(unit, "player")) and Near(unit) then return true end
	end
	return false
end

-- Their class (for the name's color and the icon), from their GUID.
local function ClassOf(guid, unit)
	if unit then
		local _, class = UnitClass(unit)
		if Plain(class) then return class end
	end
	if guid and GetPlayerInfoByGUID then
		local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
		if ok and Plain(class) then return class end
	end
end

-- (A name without its realm, for the card.)
local function Short(name)
	return name and (name:match("^([^%-]+)") or name)
end

-- Someone by name (and GUID, if known) as a moment of kind: their unit,
-- class and line.
local function FireFor(kind, name, guid, line, extra)
	local unit = UnitFor(guid, name)
	-- (Emotes only reach those near you: someone far away is no moment.)
	if MOMENT[kind] and MOMENT[kind].near and not Near(unit) then return end
	guid = guid or (unit and Plain(UnitGUID(unit)))
	local moment = extra or {}
	moment.kind, moment.name, moment.unit, moment.guid = kind, Short(name), unit, guid
	moment.fullName = name -- (with its realm, if from another: who the emote goes to)
	moment.class = moment.class or ClassOf(guid, unit)
	moment.line = line
	Fire(moment)
end

---------------------------------------------------------------------------
-- The moments.

-- Whether the one with this GUID is in your party or raid.
local function InGroup(guid)
	if not IsInGroup() then return false end
	local group = IsInRaid() and "raid" or "party"
	for i = 1, IsInRaid() and 40 or 4 do
		if Plain(UnitGUID(group .. i)) == guid then return true end
	end
	return false
end

-- A buff someone else put on you (a minute or more: not a heal over time).
local lastBuff -- (for /cine debug emote: the last buff seen, and what came of it)
local function Buffed(aura, refresh)
	local unit = Plain(aura.sourceUnit)
	local name = Plain(aura.name)
	local duration = Plain(aura.duration)
	local function Skip(why)
		lastBuff = ("%s%s from %s: %s"):format(tostring(name), refresh and " (refreshed)" or "", tostring(unit), why)
	end
	if not (unit and name and type(duration) == "number" and duration >= MIN_BUFF) then
		return Skip(not unit and "no caster unit" or "under a minute or unreadable")
	end
	if Plain(aura.isHelpful) == false then return Skip("not a buff") end
	if unit == "player" or unit == "pet" or unit == "vehicle" or ns.Flag(UnitIsUnit(unit, "player")) then
		return Skip("yours")
	end
	local guid = Plain(UnitGUID(unit))
	-- (By GUID: UnitIsPlayer can say false for players after a buff on Forever.)
	if not (guid and guid:find("^Player%-")) then return Skip("not a player") end
	if DB().emoteVisionGroupBuffs and InGroup(guid) then return Skip("your group's, ignored") end
	Skip("card")
	Fire({ kind = "Buff", name = Short(Plain(UnitName(unit))) or "?", unit = unit, guid = guid,
		class = ClassOf(guid, unit), icon = Plain(aura.icon), line = L["gave you %s"]:format(name) })
end

-- Old clients' auras with no list of the new ones: what's new since last time.
local seenAuras
local function ScanOld(silent)
	if not UnitAura then return end
	local now = {}
	for i = 1, 40 do
		local name, icon, _, _, duration, expires, source = UnitAura("player", i, "HELPFUL")
		if not name then break end
		local key = tostring(name) .. ":" .. tostring(source) .. ":" .. tostring(expires)
		now[key] = true
		if not silent and seenAuras and not seenAuras[key] and source then
			Buffed({ sourceUnit = source, name = name, duration = duration, icon = icon })
		end
	end
	seenAuras = now
end

-- New clients: each of your buffs' end time, by its instance id, to tell a
-- refresh (someone casting it again while it's on you: an update, not a new
-- buff) by its end time jumping on. Learnt again, quietly, after a fight or
-- a full update.
local ends = {}
local function EndOf(aura)
	local at = type(aura) == "table" and Plain(aura.expirationTime)
	return type(at) == "number" and at or nil
end
local function LearnEnds()
	wipe(ends)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	for i = 1, 80 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not (ok and type(aura) == "table") then break end
		local id = Plain(aura.auraInstanceID)
		if id then ends[id] = EndOf(aura) end
	end
end

local auraSeen = { events = 0 } -- (for /cine debug emotevision: what the game's aura events looked like)
local function Count(list) return type(list) == "table" and #list or 0 end
local function AurasChanged(info)
	auraSeen.events = auraSeen.events + 1
	auraSeen.last = type(info) ~= "table" and "no info (old client: scanned)"
		or (issecretvalue and (issecretvalue(info.addedAuras) or issecretvalue(info.updatedAuraInstanceIDs)))
		and "secret" or ("full %s, added %d, updated %d, removed %d"):format(tostring(info.isFullUpdate),
			Count(info.addedAuras), Count(info.updatedAuraInstanceIDs), Count(info.removedAuraInstanceIDs))
	-- (In a fight they're secret on retail: learnt again, quietly, after it.)
	if Fighting() then
		auraSeen.last = auraSeen.last .. "; skipped, fighting"
		return
	end
	if type(info) ~= "table" then
		ScanOld(false)
		return
	end
	-- (Can be secret out of a fight too, in instances: skipped then.)
	local full, added, updated, removed = info.isFullUpdate, info.addedAuras, info.updatedAuraInstanceIDs,
		info.removedAuraInstanceIDs
	if issecretvalue and (issecretvalue(full) or issecretvalue(added) or issecretvalue(updated)
		or issecretvalue(removed)) then return end
	if full then
		LearnEnds()
		return
	end
	if type(removed) == "table" then
		for _, id in ipairs(removed) do ends[id] = nil end
	end
	if type(added) == "table" then
		for _, aura in ipairs(added) do
			if type(aura) == "table" then
				local id = Plain(aura.auraInstanceID)
				if id then ends[id] = EndOf(aura) end
				Buffed(aura)
			end
		end
	end
	if type(updated) == "table" and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
		for _, id in ipairs(updated) do
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", id)
			if ok and type(aura) == "table" and Plain(aura.isHelpful) ~= false then
				local was, now = ends[id], EndOf(aura)
				ends[id] = now
				-- (Its end a second or more on: cast again, a refresh. Not a
				-- stack's change or a tick, which leave the end as it was.)
				if was and now and now > was + 1 then Buffed(aura, true) end
			end
		end
	end
end

-- Back from death, raised by someone who offered (not a spirit healer or your
-- own soulstone: no one to thank, or the soulstone's buff did already).
local function AliveCheck()
	local now = ns.Flag(UnitIsDeadOrGhost("player")) and true or false
	if dead and not now and resFrom and GetTime() - resFrom.at < 120 then
		FireFor("Res", resFrom.name, nil, L["brought you back to life"],
			{ icon = "Interface\\Icons\\Spell_Holy_Resurrection" })
	end
	if not now then resFrom = nil end
	dead = now
end

-- An emote aimed at you: "Pip waves at you." (the word "you" in it, or the
-- language's own: L["you"]).
local YOU = L["you"]
local function AtYou(text)
	local lower = text:lower()
	if lower:find("%f[%a]you%f[%A]") then return true end
	return YOU ~= "you" and lower:find("%f[%a]" .. YOU:lower() .. "%f[%A]") ~= nil
end
local function Emoted(text, author, guid)
	text, author, guid = Plain(text), Plain(author), Plain(guid)
	if type(text) ~= "string" or type(author) ~= "string" then return end
	if guid == Plain(UnitGUID("player")) then return end
	if guid and not guid:find("^Player%-") then return end
	if not AtYou(text) then return end
	-- (Which one it was, for Same back.)
	local same, lower = nil, text:lower()
	for _, pair in ipairs(EMOTE_WORDS) do
		if lower:find(pair[1], 1, true) then
			same = pair[2]
			break
		end
	end
	local name = Short(author)
	local line = text
	if line:sub(1, #name) == name then line = line:sub(#name + 1):gsub("^%s+", "") end
	FireFor("Emote", name, guid, line, { same = same })
end

-- A summon you accepted: its card a moment later, once you're there (after
-- the loading screen, if there is one).
local loading -- (a loading screen up)
local arriving -- (a summon accepted: { name, at }, its card once you're there)
local function SummonerName()
	local get = C_SummonInfo and C_SummonInfo.GetSummonConfirmSummoner or GetSummonConfirmSummoner
	if not get then return nil end
	local ok, name = pcall(get)
	return ok and Plain(name) or nil
end
local function Arrived()
	if loading or not arriving then return end
	local from = arriving
	arriving = nil
	if GetTime() - from.at < 180 then FireFor("Summon", from.name, nil, L["summoned you"]) end
end
local function Summoned()
	local from = summonFrom
	summonFrom = nil
	if not (from and GetTime() - from.at < 180) then return end
	arriving = { name = from.name, at = GetTime() }
	C_Timer.After(3, Arrived)
end
if C_SummonInfo and C_SummonInfo.ConfirmSummon then
	hooksecurefunc(C_SummonInfo, "ConfirmSummon", Summoned)
elseif ConfirmSummon then
	hooksecurefunc("ConfirmSummon", Summoned)
end

-- Your group's levels, learnt again (who's in it now); one gone up: a card.
local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, 40 do units[#units + 1] = "raid" .. i end
	else
		for i = 1, 4 do units[#units + 1] = "party" .. i end
	end
	return units
end
local function LearnLevels()
	wipe(levels)
	for _, unit in ipairs(GroupUnits()) do
		local guid = Plain(UnitGUID(unit))
		local level = Plain(UnitLevel(unit))
		if guid and type(level) == "number" and level > 0 then levels[guid] = level end
	end
end
local function LevelChanged(unit)
	if not (type(unit) == "string" and (unit:find("^party%d") or unit:find("^raid%d"))) then return end
	if ns.Flag(UnitIsUnit(unit, "player")) then return end
	local guid = Plain(UnitGUID(unit))
	local level = Plain(UnitLevel(unit))
	if not (guid and type(level) == "number" and level > 0) then return end
	local was = levels[guid]
	levels[guid] = level
	if was and level > was then
		FireFor("Level", Plain(UnitName(unit)), guid, L["reached level %d"]:format(level))
	end
end

-- Who's in your group (GUID -> name and class), to tell who joined and who
-- left. Learnt quietly at login and on loading screens.
local roster, grouped
local function Roster()
	local now = {}
	for _, unit in ipairs(GroupUnits()) do
		local guid = Plain(UnitGUID(unit))
		if guid and not ns.Flag(UnitIsUnit(unit, "player")) then
			now[guid] = { name = Plain(UnitName(unit)), class = ClassOf(guid, unit) }
		end
	end
	return now
end
local function RosterChanged(quiet)
	local now, inGroup = Roster(), IsInGroup() and true or false
	local was, wasGrouped = roster, grouped
	roster, grouped = now, inGroup
	if quiet or not was then return end
	if inGroup and not wasGrouped then
		if not GroupNear() then return end -- (joined from across the world: no one to greet)
		Fire({ kind = "Joined", name = L["Your group"], line = L["you joined a group"], group = true,
			icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" })
		return
	end
	if not (inGroup and wasGrouped) then return end -- (you left: everyone did, for you)
	-- (A few at a time: a raid filling or emptying at once isn't a moment each.)
	local joined, left = {}, {}
	for guid, who in pairs(now) do if not was[guid] then joined[#joined + 1] = { guid, who } end end
	for guid, who in pairs(was) do if not now[guid] then left[#left + 1] = { guid, who } end end
	if #joined <= 2 then
		for _, each in ipairs(joined) do
			if each[2].name then
				FireFor("Join", each[2].name, each[1], L["joined your group"], { class = each[2].class })
			end
		end
	end
	if #left <= 2 then
		for _, each in ipairs(left) do
			if each[2].name then
				FireFor("Leave", each[2].name, each[1], L["left your group"], { class = each[2].class })
			end
		end
	end
end

-- A boss fight's end in a group, in a dungeon or raid: a kill (the card for
-- all of you; a dungeon's last boss: the Dungeon moment's, a moment later)
-- or a wipe.
local function EncounterEnded(encounterID, encounterName, success)
	encounterID, success = Plain(encounterID), Plain(success)
	if not (encounterID and IsInGroup()) then return end
	local _, kind = IsInInstance()
	if kind ~= "party" and kind ~= "raid" then return end
	local name = Plain(encounterName)
	if not name and EJ_GetEncounterInfo then name = Plain((EJ_GetEncounterInfo(encounterID))) end
	name = name or L["A boss"]
	if success ~= 1 then
		Fire({ kind = "Wipe", name = name, line = L["your group wiped"], group = true,
			icon = "Interface\\Icons\\Ability_Rogue_FeignDeath" })
		return
	end
	local last
	if kind == "party" and ns.EncounterIndex then
		local index, count = ns.EncounterIndex(encounterID)
		last = index and index == count
	end
	local place = Plain((GetInstanceInfo()))
	if last and place and place ~= "" and MOMENT.Dungeon and DB()[MOMENT.Dungeon.on] then
		-- (After the kill's own banner and the Dungeon cleared card.)
		C_Timer.After(6, function()
			Fire({ kind = "Dungeon", name = place, line = L["cleared with your group"], group = true,
				icon = "Interface\\Icons\\INV_Misc_Key_03" })
		end)
		return
	end
	Fire({ kind = "Boss", name = name, line = L["defeated with your group"], group = true,
		icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" })
end

-- An achievement someone else earned (near you, your group, your guild):
-- "Aelwyn has earned the achievement [Explore Elwynn Forest]!".
local function Achieved(text, author, guid)
	text, author, guid = Plain(text), Plain(author), Plain(guid)
	if type(text) ~= "string" or type(author) ~= "string" then return end
	if guid and guid == Plain(UnitGUID("player")) then return end
	if Short(author) == Short(Plain(UnitName("player"))) then return end
	local what = text:match("%[(.-)%]") or L["an achievement"]
	FireFor("Achievement", author, guid, L["earned %s"]:format(what))
end

-- Someone you know (your guild's, or a recent ally) seen near you: on a
-- nameplate showing, your mouseover or your target. Each one once an hour,
-- whatever the repeats setting (a guild city would flood you otherwise).
local MET_AGAIN = 3600
local met = {}
local function Known(unit)
	local guid = Plain(UnitGUID(unit))
	if not (guid and guid:find("^Player%-")) then return end
	if guid == Plain(UnitGUID("player")) then return end
	if ns.Flag(UnitInParty(unit)) or ns.Flag(UnitInRaid(unit)) then return end
	if UnitIsInMyGuild and ns.Flag(UnitIsInMyGuild(unit)) then return guid, "Guild" end
	if MOMENT.Ally then
		local ok, ally = pcall(C_RecentAllies.IsRecentAllyByGUID, guid)
		if ok and ns.Flag(ally) then return guid, "Ally" end
	end
end
local function Spotted(unit)
	if loading or Fighting() then return end
	local guid, kind = Known(unit)
	if not guid or not DB()[MOMENT[kind].on] then return end
	local now = GetTime()
	if met[guid] and now - met[guid] < MET_AGAIN then return end
	met[guid] = now
	FireFor(kind, Plain(UnitName(unit)), guid,
		kind == "Guild" and L["is in your guild"] or L["grouped with you before"])
end

-- Your own level up: a card for everyone around, to celebrate.
local function LeveledUp(level)
	level = Plain(level)
	if type(level) ~= "number" then return end
	local _, class = UnitClass("player")
	Fire({ kind = "YouLevel", name = Short(Plain(UnitName("player"))) or L["You"], class = Plain(class),
		unit = "player", line = L["reached level %d"]:format(level), group = true })
end

-- Your duel's end (Effects.lua's duel line): moment "won" or "lost", other
-- the one you fought.
function ns.EmoteVisionDuel(moment, other)
	if type(other) ~= "string" then return end
	FireFor("Duel", other, nil, moment == "won" and L["lost a duel to you"] or L["beat you in a duel"])
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "RESURRECT_REQUEST", "PLAYER_DEAD",
	"PLAYER_ALIVE", "PLAYER_UNGHOST", "CHAT_MSG_TEXT_EMOTE", "PLAYER_STOPPED_MOVING", "CONFIRM_SUMMON",
	"TRADE_SHOW", "UI_INFO_MESSAGE", "GROUP_ROSTER_UPDATE", "UNIT_LEVEL", "ENCOUNTER_END", "LOADING_SCREEN_ENABLED",
	"LOADING_SCREEN_DISABLED", "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT", "PLAYER_LEVEL_UP",
	"NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
pcall(watcher.RegisterUnitEvent, watcher, "UNIT_AURA", "player")
watcher:SetScript("OnEvent", function(_, event, ...)
	if event == "UNIT_AURA" then
		AurasChanged(select(2, ...))
	elseif event == "CHAT_MSG_TEXT_EMOTE" then
		local text, author = ...
		Emoted(text, author, (select(12, ...)))
	elseif event == "RESURRECT_REQUEST" then
		local name = Plain((...))
		if type(name) == "string" then resFrom = { name = name, at = GetTime() } end
	elseif event == "CONFIRM_SUMMON" then
		local name = SummonerName()
		if name then summonFrom = { name = name, at = GetTime() } end
	elseif event == "TRADE_SHOW" then
		local name, guid = Plain(UnitName("NPC")), Plain(UnitGUID("NPC"))
		tradeWith = name and { name = name, guid = guid, class = ClassOf(guid, "NPC") } or nil
	elseif event == "UI_INFO_MESSAGE" then
		-- ((type, message) on newer clients, (message) on older ones.)
		local first, second = ...
		local done = ERR_TRADE_COMPLETE
		if tradeWith and done and (Plain(first) == done or Plain(second) == done) then
			local with = tradeWith
			tradeWith = nil
			FireFor("Trade", with.name, with.guid, L["traded with you"], { class = with.class })
		end
	elseif event == "UNIT_LEVEL" then
		LevelChanged(...)
	elseif event == "GROUP_ROSTER_UPDATE" then
		LearnLevels()
		RosterChanged(loading)
	elseif event == "ENCOUNTER_END" then
		local encounterID, encounterName, _, _, success = ...
		EncounterEnded(encounterID, encounterName, success)
	elseif event == "CHAT_MSG_ACHIEVEMENT" or event == "CHAT_MSG_GUILD_ACHIEVEMENT" then
		local text, author = ...
		Achieved(text, author, (select(12, ...)))
	elseif event == "PLAYER_LEVEL_UP" then
		LeveledUp((...))
	elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" then
		if ns.Setting("emoteVision") then
			local unit = event == "NAME_PLATE_UNIT_ADDED" and Plain((...))
				or (event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or "target")
			if unit then Spotted(unit) end
		end
	elseif event == "LOADING_SCREEN_ENABLED" then
		loading = true
	elseif event == "LOADING_SCREEN_DISABLED" then
		loading = nil
		if arriving then C_Timer.After(2, Arrived) end
	elseif event == "PLAYER_DEAD" then
		dead = true
	elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		C_Timer.After(0, AliveCheck)
	elseif event == "PLAYER_STOPPED_MOVING" then
		C_Timer.After(0.2, Next) -- (once ns.playerMoving has caught up)
	elseif event == "PLAYER_REGEN_ENABLED" then
		ScanOld(true)
		LearnEnds()
		C_Timer.After(1, Next)
	elseif event == "PLAYER_ENTERING_WORLD" then
		GiveRule()
		dead = ns.Flag(UnitIsDeadOrGhost("player")) and true or false
		ScanOld(true)
		LearnEnds()
		LearnLevels()
		RosterChanged(true)
	end
end)

---------------------------------------------------------------------------
-- The page's test and mover.

-- Test: each moment's pretend card in turn (the next moment ticked on).
local nextSample = 1
function ns.TestEmoteVision()
	local db = DB()
	local kind
	for _ = 1, #MOMENTS do
		local each = MOMENTS[nextSample]
		nextSample = nextSample % #MOMENTS + 1
		if db[each.on] and #EmotesFor(each.id, each.sample.same) > 0 then
			kind = each
			break
		end
	end
	kind = kind or MOMENTS[1]
	local sample = kind.sample
	moving = nil
	if card then card:Hide() end
	local line = L[sample.line]
	if sample.spell then line = line:format(L[sample.spell]) elseif sample.level then line = line:format(sample.level) end
	local moment = { kind = kind.id, name = L[sample.name], class = sample.class, icon = sample.icon, test = true,
		line = line, same = sample.same, group = sample.group }
	-- (Someone targeted: the card's theirs, its face and name, and its buttons
	-- really emote at them; a group's card stays the group's.)
	local name = not sample.group and ns.Flag(UnitExists("target")) and not ns.Flag(UnitIsUnit("target", "player"))
		and Plain(UnitName("target"))
	if name then
		local guid = Plain(UnitGUID("target"))
		moment.name, moment.unit, moment.guid, moment.test, moment.tried = name, "target", guid, nil, true
		moment.class = guid and guid:find("^Player%-") and ClassOf(guid, "target") or nil
	end
	if not Show(moment) then
		-- (No moment with emotes on: the first one's as they come, so Test
		-- still shows one.)
		local first = MOMENTS[1]
		moment.kind, moment.emotes = first.id, ParseEmotes(DEFAULTS[first.key])
		Show(moment)
	end
end

-- Move: the card held up to drag where you want it; again to let go.
function ns.MoveEmoteVision()
	if moving then
		moving = nil
		Hide()
		return
	end
	ns.TestEmoteVision()
	moving = true
	if card then card:SetAlpha(1) end
end
function ns.EmoteVisionMoving() return moving and true or false end

function ns.RefreshEmoteVision()
	if not card then return end
	if not ns.Setting("emoteVision") then
		moving = nil
		wipe(queue)
		card:Hide()
		return
	end
	-- (Up: drawn again in the look now, its time and fade kept.)
	if card:IsShown() and showing and not card.leaving then
		local age, wasMoving = card.age, moving
		Show(showing)
		card.age, moving = age, wasMoving
		card:SetAlpha(1)
	end
end

-- /cine debug emotescan [first]: every emote of the game's in turn, at no
-- one, for a recording to tell which animate and which make a sound. Each
-- one's number, command and token big at the top of the screen (shown with
-- the UI hidden too), a square in the top left switching color with each,
-- and a log in CinematicDB.emoteScan (each one's GetTime, and the clock's at
-- the start). Between them, /stand, so a dance or a sit doesn't carry on.
-- Again to stop.
-- /cine debug emotestop [emote]: which way stops a looping emote (/dance,
-- /map, /read...). It plays the emote, then tries each way 4 seconds apart,
-- saying in chat which it's trying: watch which one ends it. Again to stop.
local STOP_STEP = 4
local stopTest
function ns.EmoteStopTest(arg)
	if stopTest then
		stopTest:Cancel()
		stopTest = nil
		ns.Print("emotestop: stopped.")
		return
	end
	local token = (arg and arg ~= "" and arg or "DANCE"):upper():gsub("^/", "")
	local function Try(name, run)
		return { name = name, run = run }
	end
	local steps = {
		Try("/" .. token:lower() .. " (start it)", function() DoEmote(token, "none") end),
		Try("CancelEmote()", function()
			if not CancelEmote then error("no CancelEmote on this client") end
			CancelEmote()
		end),
		Try("/" .. token:lower() .. " (start it again)", function() DoEmote(token, "none") end),
		Try("/stand", function() DoEmote("STAND", "none") end),
		Try("/" .. token:lower() .. " (start it again)", function() DoEmote(token, "none") end),
		Try("/" .. token:lower() .. " again (does a second one toggle it off?)", function() DoEmote(token, "none") end),
		Try("/" .. token:lower() .. " (start it again)", function() DoEmote(token, "none") end),
		Try("another emote, /wave", function() DoEmote("WAVE", "none") end),
		Try("/" .. token:lower() .. " (start it again)", function() DoEmote(token, "none") end),
		Try("/sit then /stand", function()
			DoEmote("SIT", "none")
			C_Timer.After(1, function() DoEmote("STAND", "none") end)
		end),
	}
	ns.Print(("emotestop: %s, then each way to stop it, %d seconds apart. CancelEmote %s. Again to stop."):format(
		"/" .. token:lower(), STOP_STEP, CancelEmote and "is here" or "is NOT on this client"))
	local n = 0
	stopTest = C_Timer.NewTicker(STOP_STEP, function()
		n = n + 1
		local step = steps[n]
		if not step then
			stopTest:Cancel()
			stopTest = nil
			ns.Print("emotestop: done. Which ones stopped it?")
			return
		end
		local ok, why = pcall(step.run)
		local verb = step.name:find("start it") and "" or "trying "
		ns.Print(("emotestop %d/%d: %s%s%s"):format(n, #steps, verb, step.name, ok and "" or (" - failed: " .. tostring(why))))
	end)
end

local SCAN_STEP = 5    -- seconds each emote gets
local SCAN_STAND = 4   -- ...the /stand this far into it
local SCAN_CANCEL = 0.5 -- ...CancelEmote() this long before it
local SCAN_READY = 5   -- seconds before the first, to start recording
-- "/cine debug emotescan more": what the full scan left to check, 10 seconds
-- each (a loop shows as still going near the end): the ones a stuck /kneel
-- spoilt (#60-68), and the ones still moving at 4 seconds, maybe looping.
local SCAN_MORE = { "KNEEL", "LAUGH", "LAYDOWN", "MASSAGE", "MOON", "MOURN", "NO", "NOD", "NOSEPICK",
	"DANCE", "SHY", "BASHFUL", "BLUSH", "COWER", "FLIRT", "READ", "LEAN", "MAP", "SIT", "SLEEP", "GOING", "STARE",
	"ROLLEYES" }
local SCAN_MORE_STEP = 10
local scan
function ns.EmoteScan(arg)
	if scan then
		scan.timer:Cancel()
		scan.frame:Hide()
		if scan.wasOn and ns.SetEnabled then ns.SetEnabled(true) end
		ns.Print(("emotescan: stopped at %d of %d."):format(scan.at, #scan.list))
		scan = nil
		return
	end
	if Fighting() then
		ns.Print("emotescan: not in a fight.")
		return
	end
	-- (The game's text emotes, then the voice ones not among them.)
	local game, list, seen = GameEmotes(), {}, {}
	for _, group in ipairs({ game.text, game.voice }) do
		for _, token in ipairs(group) do
			if not seen[token] then
				seen[token] = true
				list[#list + 1] = token
			end
		end
	end
	if #list == 0 then
		ns.Print("emotescan: this client has no emote lists (EmoteList, TextEmoteSpeechList).")
		return
	end
	-- (arg: "first" or "first last", to play again only a stretch of them;
	-- "more", SCAN_MORE's, longer each.)
	local step, stand = SCAN_STEP, SCAN_STAND
	local first = 1
	if arg == "more" then
		list, step, stand = {}, SCAN_MORE_STEP, SCAN_MORE_STEP - 1
		for _, token in ipairs(SCAN_MORE) do list[#list + 1] = token end
	else
		local from, to = tostring(arg or ""):match("^(%d*)%s*(%d*)$")
		first = math.max(1, math.min(#list, tonumber(from) or 1))
		local last = math.max(first, math.min(#list, tonumber(to) or #list))
		for k = #list, last + 1, -1 do list[k] = nil end
	end
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	if ns.AddOverlay then ns.AddOverlay(frame) end
	local back = frame:CreateTexture(nil, "BACKGROUND")
	back:SetColorTexture(0, 0, 0, 0.75)
	back:SetPoint("TOP", 0, -40)
	back:SetSize(900, 70)
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetFont((text:GetFont()), 32, "OUTLINE")
	text:SetPoint("CENTER", back, "CENTER")
	local square = frame:CreateTexture(nil, "OVERLAY")
	square:SetSize(60, 60)
	square:SetPoint("TOPLEFT", 20, -20)
	local db = ns.GetDB()
	db.emoteScan = { started = date("%Y-%m-%d %H:%M:%S"), startedAt = GetTime(), step = step,
		stand = stand, ready = SCAN_READY, client = select(4, GetBuildInfo()), emotes = {} }
	-- (Cinematic off while it runs, back on after: its AFK and cozy cameras
	-- would swing round you as you stand there and /sit, /dance...)
	local wasOn = ns.db and ns.db.enabled and true or false
	if wasOn and ns.SetEnabled then ns.SetEnabled(false) end
	scan = { list = list, at = first - 1, frame = frame, wasOn = wasOn }
	text:SetText(("Emote scan: %d emotes from #%d, %d sec each. Starting in %d..."):format(#list - first + 1, first,
		step, SCAN_READY))
	square:SetColorTexture(1, 1, 1, 1)
	ns.Print(("emotescan: %d emotes (%d of them voice ones), from #%d, %d sec each; about %d min. /cine debug " ..
		"emotescan again to stop."):format(#list, #game.voice, first, step,
		math.ceil((#list - first + 1) * step / 60)))
	ns.Print(("emotescan: between emotes, %s then /stand (looping ones like /dance stop only if it works)."):format(
		CancelEmote and "CancelEmote()" or "no CancelEmote() on this client, only"))
	local function Step()
		if not scan then return end
		scan.at = scan.at + 1
		local i = scan.at
		local token = list[i]
		if not token then
			text:SetText(("Emote scan: done, %d emotes."):format(#list))
			square:SetColorTexture(1, 1, 1, 1)
			ns.Print("emotescan: done. The log is in CinematicDB.emoteScan (saved on /reload or logout).")
			scan.timer:Cancel()
			if scan.wasOn and ns.SetEnabled then ns.SetEnabled(true) end
			C_Timer.After(5, function() frame:Hide() end)
			scan = nil
			return
		end
		local voice = game.isVoice[token] and "  voice" or ""
		text:SetText(("#%d / %d    %s    %s%s"):format(i, #list, Command(token), token, voice))
		if i % 2 == 0 then square:SetColorTexture(1, 0, 1, 1) else square:SetColorTexture(0, 1, 0, 1) end
		local fighting = Fighting()
		db.emoteScan.emotes[#db.emoteScan.emotes + 1] = { i = i, token = token, command = Command(token),
			voice = game.isVoice[token] or nil, at = GetTime(), skipped = fighting or nil }
		if not fighting then pcall(DoEmote, token, "none") end
		-- (Then stopped: a looping one, /dance or /map, carries on through the
		-- next emotes and even /stand, till you move; the game's CancelEmote
		-- ends it. /stand after, for /sit, /kneel and /laydown.)
		-- (Half a second apart: in the same moment, /stand didn't take after
		-- /kneel, and the next eight emotes played from one knee.)
		C_Timer.After(stand - SCAN_CANCEL, function()
			if not (scan and scan.at == i) or Fighting() then return end
			if CancelEmote then pcall(CancelEmote) end
		end)
		C_Timer.After(stand, function()
			if not (scan and scan.at == i) or Fighting() then return end
			pcall(DoEmote, "STAND", "none")
		end)
	end
	scan.timer = C_Timer.NewTimer(SCAN_READY, function()
		Step()
		if scan then scan.timer = C_Timer.NewTicker(step, Step) end
	end)
end

-- /cine debug emotevision: what it would do now, and why.
function ns.EmoteVisionDebug()
	local ok, here = pcall(ns.RowOnNow, ROW_KEY, nil, true)
	local db = DB()
	ns.Print(("emotevision: page %s; Show in %s; fighting %s; moving %s (still only %s); queued %d; card %s"):format(
		tostring(ns.Setting("emoteVision")), ok and tostring(here) or ("error: " .. tostring(here)),
		tostring(Fighting()), tostring(ns.playerMoving), tostring(db.emoteVisionStill), #queue,
		card and card:IsShown() and tostring(showing and showing.name) or "hidden"))
	ns.Print(("  repeats ignored %s (%s min); dead %s; res offer %s; summon offer %s; trade with %s; group levels %d"):format(
		tostring(db.emoteVisionRepeats), tostring(db.emoteVisionRepeatMins), tostring(dead),
		resFrom and resFrom.name or "none", summonFrom and summonFrom.name or "none",
		tradeWith and tradeWith.name or "none", (function() local n = 0 for _ in pairs(levels) do n = n + 1 end return n end)()))
	local moments = {}
	for _, each in ipairs(MOMENTS) do
		local list = EmotesFor(each.id, each.same and "WAVE" or nil)
		moments[#moments + 1] = each.id .. (db[each.on] and "" or " (off)") .. ": " .. table.concat(list, ",")
	end
	ns.Print("  " .. table.concat(moments, "; "))
	local known = 0
	for _ in pairs(ends) do known = known + 1 end
	ns.Print(("  aura events %d, last: %s; buffs' end times known %d"):format(auraSeen.events,
		auraSeen.last or "none", known))
	ns.Print("  last buff: " .. (lastBuff or "none yet") ..
		(" (refreshes tracked: %s)"):format(C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID and "yes" or "no, old client"))
	local target = Plain(UnitGUID("target"))
	if target then
		local ally = "no API"
		if C_RecentAllies and C_RecentAllies.IsRecentAllyByGUID then
			local okAlly, value = pcall(C_RecentAllies.IsRecentAllyByGUID, target)
			ally = okAlly and tostring(Plain(value)) or ("error: " .. tostring(value))
		end
		ns.Print(("  target %s: unit %s; guild %s; recent ally %s; known as %s; met %s"):format(
			tostring(Plain(UnitName("target"))), tostring(UnitFor(target)),
			UnitIsInMyGuild and tostring(Plain(UnitIsInMyGuild("target"))) or "no API", ally,
			tostring(select(2, Known("target"))), met[target] and ("%d s ago"):format(GetTime() - met[target]) or "never"))
	end
end

---------------------------------------------------------------------------
-- The pages (Visions, World): Vision (when it shows) and Style (how it
-- looks), two folder tabs.

local function Tabs(content, title, picked)
	local panel = ns.PageTabs(content, {
		{ L["Vision"], "Emote Vision", L["Turning it on, the moments a card shows for and each one's emotes."] },
		{ L["Settings"], "Emote Vision Settings", L["When the cards show, and for how long."] },
		{ L["Look"], "Emote Vision Style", L["Its style, words, frame and face, and where it sits."] },
	}, picked)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
end

-- Its Test button (not a page control: it works with the page off too).
local function TestButton(parent)
	local test = ns.PanelButton(parent)
	test:SetSize(100, 22)
	test:SetText(L["Test"])
	test:SetScript("OnClick", function() ns.TestEmoteVision() end)
	return test
end
local TEST_TIP = "Shows a pretend card for each moment in turn (close the settings to see it). With someone " ..
	"targeted it's theirs, and its buttons really emote at them; with no one, they only say in chat what they'd do."

local function On() return ns.GetDB() and ns.GetDB().emoteVision end
local function Changed() ns.RefreshEmoteVision() end

-- The moments and their emotes, as the Sounds tabs' rules and sounds: a band
-- for each moment (its tick and name), its emotes under it (^ to move one up,
-- x to take it off), Add an emote under them (the picker below: search,
-- filters, every emote of the game's, and Same back for an emote at you).
local GRID_W, HEAD_H, ROW_H = 520, 24, 22
local function SmallButton(parent, text, width)
	local button = ns.PanelButton(parent)
	button:SetSize(width or 22, 20)
	button:SetText(text)
	return button
end

-- The emote picker (Add an emote): a window beside the button, a search box
-- (name or command), filter buttons (by what the emote does, the tags'
-- groups), and every emote of the game's in a scrolling list, its tags on
-- the right. A click adds it to the card, and the window stays open for more
-- (up to MAX_EMOTES); ones already on it are greyed.
local PICK_W, PICK_ROWS, PICK_ROW_H, PICK_TOP = 420, 14, 22, 112
local FILTERS = {
	{ "all", "All" }, { "common", "Common" }, { "body", "Full body" }, { "gesture", "Gesture" },
	{ "voice", "Voice" }, { "sound", "Sound" }, { "loops", "Loops or holds" }, { "chat", "Chat only" },
}
local FILTER_TIPS = {
	all = "Every emote.", common = "The ones most used to answer someone: thank, bow, wave, cheer...",
	body = "Your whole character changes pose: kneels, sits, lies down, bows, dances, cowers, flexes...",
	gesture = "Hands, arms and head while you stand: a wave, a point, a salute, a laugh...",
	voice = "Says something out loud (the game's voice emotes).", sound = "Makes a sound, not a voice line: a laugh, a roar, a whistle...",
	loops = "Keeps going (a dance) or holds a pose (kneeling, sitting) till you move.",
	chat = "Only a line in chat: nothing on your character.",
}
local function FilterPasses(filter, token)
	if token == SAME then return filter == "all" or filter == "common" end
	if filter == "common" then return EMOTE_NAMES[token] ~= nil end
	if filter == "body" then return EMOTE_BODY[token] == true end
	if filter == "gesture" then return EMOTE_MOVES[token] == true and not EMOTE_BODY[token] end
	if filter == "voice" then return GameEmotes().isVoice[token] == true end
	if filter == "sound" then return EMOTE_SOUND[token] == true and not GameEmotes().isVoice[token] end
	if filter == "loops" then return EMOTE_LOOPS[token] ~= nil end
	if filter == "chat" then
		return not (EMOTE_MOVES[token] or EMOTE_SOUND[token] or GameEmotes().isVoice[token])
	end
	return true
end

local picker
local function Picker()
	if picker then return picker end
	local f = CreateFrame("Frame", "CinematicEmotePicker", UIParent, "BackdropTemplate")
	picker = f
	f:SetSize(PICK_W, PICK_TOP + PICK_ROWS * PICK_ROW_H + 30)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	f:SetBackdropColor(0.05, 0.05, 0.06, 0.97)
	f:SetBackdropBorderColor(BORDER_GOLD[1], BORDER_GOLD[2], BORDER_GOLD[3], 1)
	f:Hide()
	f.filter, f.offset, f.items = "all", 0, {}

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.title:SetPoint("RIGHT", -30, 0)
	f.title:SetJustifyH("LEFT")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	-- Search: what's typed, in an emote's name or command.
	f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.search:SetSize(220, 20)
	f.search:SetPoint("TOPLEFT", 20, -36)
	f.search:SetAutoFocus(false)
	f.hint = f.search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	f.hint:SetPoint("LEFT", 2, 0)
	f.hint:SetText(L["Search"])
	f.search:SetScript("OnTextChanged", function(self)
		f.hint:SetShown(self:GetText() == "")
		f.offset = 0
		f.Refresh()
	end)
	f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.count:SetPoint("LEFT", f.search, "RIGHT", 12, 0)

	-- The filters, four to a row.
	f.chips = {}
	for i, each in ipairs(FILTERS) do
		local chip = SmallButton(f, L[each[2]], (PICK_W - 40) / 4 - 4)
		chip:SetPoint("TOPLEFT", 16 + ((i - 1) % 4) * ((PICK_W - 40) / 4), -62 - math.floor((i - 1) / 4) * 23)
		chip.key = each[1]
		chip:SetScript("OnClick", function(self)
			f.filter, f.offset = self.key, 0
			f.Refresh()
		end)
		chip:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L[each[2]], 1, 1, 1)
			GameTooltip:AddLine(L[FILTER_TIPS[each[1]]], nil, nil, nil, true)
			GameTooltip:Show()
		end)
		chip:SetScript("OnLeave", GameTooltip_Hide)
		f.chips[i] = chip
	end

	-- The list: PICK_ROWS rows, the mouse wheel or the bar beside them scrolls.
	f.rows = {}
	for i = 1, PICK_ROWS do
		local row = CreateFrame("Button", nil, f)
		row:SetSize(PICK_W - 44, PICK_ROW_H)
		row:SetPoint("TOPLEFT", 16, -PICK_TOP - (i - 1) * PICK_ROW_H)
		local light = row:CreateTexture(nil, "HIGHLIGHT")
		light:SetAllPoints()
		light:SetColorTexture(1, 0.82, 0, 0.12)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("LEFT", 6, 0)
		row.name:SetJustifyH("LEFT")
		row.tags = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		-- (> at its right end plays it, as a right-click on the row does.)
		row.play = SmallButton(row, ">")
		row.play:SetSize(20, 18)
		row.play:SetPoint("RIGHT", -2, 0)
		row.play:SetScript("OnClick", function() TryEmote(row.token) end)
		row.play:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["Play it, to see it (at no one)."], 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		row.play:SetScript("OnLeave", GameTooltip_Hide)
		row.tags:SetPoint("RIGHT", row.play, "LEFT", -6, 0)
		row.tags:SetJustifyH("RIGHT")
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				TryEmote(self.token)
			elseif self.token and not self.taken and f.add then
				f.add(self.token)
				f.Refresh()
			end
		end)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(EmoteName(self.token), 1, 1, 1)
			GameTooltip:AddLine(self.taken and L["Already on this card (or the card is full). Right-click: play it."]
				or L["Click: add it to the card. Right-click: play it."], nil, nil, nil, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		f.rows[i] = row
	end
	f.bar = CreateFrame("Slider", nil, f)
	f.bar:SetOrientation("VERTICAL")
	f.bar:SetPoint("TOPRIGHT", -12, -PICK_TOP)
	f.bar:SetSize(14, PICK_ROWS * PICK_ROW_H)
	local track = f.bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(1, 1, 1, 0.06)
	f.bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	f.bar:SetValueStep(1)
	if f.bar.SetObeyStepOnDrag then f.bar:SetObeyStepOnDrag(true) end
	f.bar:SetScript("OnValueChanged", function(_, value)
		value = math.floor(value + 0.5)
		if value ~= f.offset then
			f.offset = value
			f.Draw()
		end
	end)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		local most = math.max(0, #f.items - PICK_ROWS)
		f.offset = math.max(0, math.min(most, f.offset - delta * 3))
		f.bar:SetValue(f.offset)
		f.Draw()
	end)
	f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	f.empty:SetPoint("TOP", 0, -PICK_TOP - 20)
	f.empty:SetText(L["No emotes match."])

	-- The rows from offset on, each its name, command and tags; one on the card greyed.
	function f.Draw()
		local list = f.getList and f.getList() or {}
		local have = {}
		for _, token in ipairs(list) do have[token] = true end
		local full = #list >= MAX_EMOTES
		for i, row in ipairs(f.rows) do
			local token = f.items[f.offset + i]
			row:SetShown(token ~= nil)
			if token then
				row.token = token
				row.taken = have[token] or full
				local name = EmoteName(token)
				if token == SAME then
					name = name .. "  |cff808080" .. L["(the emote they did at you)"] .. "|r"
				else
					name = name .. "  |cff808080" .. Command(token) .. "|r"
				end
				row.name:SetText(name)
				row.tags:SetText(token ~= SAME and EmoteTags(token) or "")
				row.play:SetShown(token ~= SAME)
				row.name:SetAlpha(row.taken and 0.4 or 1)
				row.tags:SetAlpha(row.taken and 0.4 or 1)
			end
		end
		f.empty:SetShown(#f.items == 0)
		f.count:SetText(full and ("|cffff6060" .. L["%d of %d: the card is full"]:format(#list, MAX_EMOTES) .. "|r")
			or L["%d of %d on this card"]:format(#list, MAX_EMOTES))
	end

	-- The emotes the search and filter leave, sorted by command (Same back first).
	function f.Refresh()
		local find = f.search:GetText():lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("^/", "")
		local game, all, seen = GameEmotes(), {}, {}
		for _, group in ipairs({ game.text, game.voice }) do
			for _, token in ipairs(group) do
				if not seen[token] then
					seen[token] = true
					all[#all + 1] = token
				end
			end
		end
		for _, each in ipairs(EMOTES) do
			if not seen[each[1]] then
				seen[each[1]] = true
				all[#all + 1] = each[1]
			end
		end
		table.sort(all, function(a, b) return Command(a) < Command(b) end)
		if f.moment and f.moment.same then table.insert(all, 1, SAME) end
		wipe(f.items)
		for _, token in ipairs(all) do
			local text = (EmoteName(token) .. " " .. (token ~= SAME and Command(token) or "")):lower()
			if FilterPasses(f.filter, token) and (find == "" or text:find(find, 1, true)) then
				f.items[#f.items + 1] = token
			end
		end
		local most = math.max(0, #f.items - PICK_ROWS)
		f.offset = math.min(f.offset, most)
		f.bar:SetMinMaxValues(0, most)
		f.bar:SetShown(most > 0)
		f.bar:SetValue(f.offset)
		for _, chip in ipairs(f.chips) do
			local on = chip.key == f.filter
			if on then chip:LockHighlight() else chip:UnlockHighlight() end
			local text = chip:GetFontString()
			if text then
				if on then text:SetTextColor(1, 0.82, 0) else text:SetTextColor(1, 1, 1) end
			end
		end
		f.Draw()
	end

	if ns.CloseWithSettings then ns.CloseWithSettings(f) end
	return f
end

-- Opens the picker beside owner for moment: getList() gives its emotes now,
-- add(token) adds one.
function ns.OpenEmotePicker(owner, moment, getList, add)
	local f = Picker()
	f.moment, f.getList, f.add, f.offset = moment, getList, add, 0
	f.title:SetText(L["Add an emote: %s"]:format(L[moment.name]))
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 80)
	f:Show()
	f.Refresh()
end
local function MomentsGrid(kit, content, stack)
	local box = CreateFrame("Frame", nil, content)
	box:SetSize(GRID_W, 40)
	stack:Add(box, "label")

	local Rebuild
	local function List(moment) return ParseEmotes(DB()[moment.key]) end
	local function Save(moment, list)
		ns.GetDB()[moment.key] = table.concat(list, ",")
		Changed()
		Rebuild()
	end

	-- Add an emote: the picker window, for moment (token added at the end,
	-- none twice).
	local function AddMenu(owner, moment)
		ns.OpenEmotePicker(owner, moment, function() return List(moment) end, function(token)
			local list = List(moment)
			for _, each in ipairs(list) do if each == token then return end end
			if #list >= MAX_EMOTES then return end
			list[#list + 1] = token
			Save(moment, list)
		end)
	end

	local heads, rows = {}, {}
	-- (Each moment closed to start, its emotes summed up on its band; open:
	-- its rows and Add an emote under it. Kept while the settings stay open.)
	local opened = {}
	local function Head(i)
		if heads[i] then return heads[i] end
		local head = CreateFrame("Frame", nil, box)
		head:SetSize(GRID_W, HEAD_H)
		local band = head:CreateTexture(nil, "BACKGROUND")
		band:SetAllPoints()
		band:SetColorTexture(1, 1, 1, 0.05)
		head.toggle = SmallButton(head, "+")
		head.toggle:SetPoint("LEFT", 2, 0)
		kit.Tooltip(head.toggle, L["Open or close this moment's emotes."])
		head.check = CreateFrame("CheckButton", nil, head, "UICheckButtonTemplate")
		if ns.SkinCheck then ns.SkinCheck(head.check) end
		head.check:SetSize(24, 24)
		head.check:SetPoint("LEFT", head.toggle, "RIGHT", 2, 0)
		head.name = kit.Label(head, "GameFontNormal", "")
		head.name:SetPoint("LEFT", head.check, "RIGHT", 2, 0)
		head.count = kit.Label(head, "GameFontDisableSmall", "")
		head.count:SetPoint("RIGHT", -8, 0)
		head.summary = kit.Label(head, "GameFontDisableSmall", "")
		head.summary:SetPoint("LEFT", head.name, "RIGHT", 10, 0)
		head.summary:SetPoint("RIGHT", head.count, "LEFT", -8, 0)
		head.summary:SetJustifyH("LEFT")
		head.summary:SetWordWrap(false)
		-- (A click on the band itself opens or closes it too.)
		head:EnableMouse(true)
		head:SetScript("OnMouseUp", function(self) if self.toggle:IsEnabled() then self.toggle:Click() end end)
		head.add = SmallButton(box, L["Add an emote"], 120)
		kit.Tooltip(head.add, L["Pick an emote to add as a button on this card: a common one, any of the " ..
			"game's, or a voice emote (said out loud). Up to six."])
		heads[i] = head
		return head
	end
	local function Row(n)
		if rows[n] then return rows[n] end
		local row = CreateFrame("Frame", nil, box)
		row:SetSize(GRID_W - 26, ROW_H)
		row.name = kit.Label(row, "GameFontHighlightSmall", "")
		row.name:SetPoint("LEFT", 0, 0)
		row.name:SetWidth(300)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.play = SmallButton(row, ">")
		row.play:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
		row.up = SmallButton(row, "^")
		row.up:SetPoint("LEFT", row.play, "RIGHT", 4, 0)
		row.remove = SmallButton(row, "x")
		row.remove:SetPoint("LEFT", row.up, "RIGHT", 4, 0)
		kit.Tooltip(row.play, L["Play it, to see it (at no one)."])
		kit.Tooltip(row.up, L["Move this emote up: its button comes first."])
		kit.Tooltip(row.remove, L["Take it off this card."])
		rows[n] = row
		return row
	end

	local defaults = SmallButton(box, L["Back to the defaults"], 160)
	kit.Tooltip(defaults, L["Every moment's emotes as they come."])
	defaults:SetScript("OnClick", function()
		local db = ns.GetDB()
		for _, moment in ipairs(MOMENTS) do db[moment.key] = DEFAULTS[moment.key] end
		Changed()
		Rebuild()
	end)

	function Rebuild()
		local db = DB()
		local pageOn = On() and true or false
		for _, head in ipairs(heads) do head:Hide() head.add:Hide() end
		for _, row in ipairs(rows) do row:Hide() end
		local y, n = 0, 0
		for i, moment in ipairs(MOMENTS) do
			local head = Head(i)
			head:ClearAllPoints()
			head:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
			head:Show()
			y = y + HEAD_H + 2
			local momentOn = db[moment.on] and true or false
			-- (Its font before its text: the other way, Russian letters show as boxes.)
			head.name:SetFontObject(pageOn and momentOn and "GameFontNormal" or "GameFontDisable")
			head.name:SetText(L[moment.name])
			head.check:SetChecked(momentOn)
			head.check:SetEnabled(pageOn)
			head.check:SetScript("OnClick", function(self)
				ns.GetDB()[moment.on] = self:GetChecked() and true or false
				Changed()
				Rebuild()
			end)
			kit.Tooltip(head.check, L[moment.tip])
			local list = List(moment)
			head.count:SetText(("%d/%d"):format(#list, MAX_EMOTES))
			local open = pageOn and momentOn
			local expanded = opened[moment.id] and true or false
			head.toggle:SetText(expanded and "-" or "+")
			head.toggle:SetScript("OnClick", function()
				opened[moment.id] = not opened[moment.id]
				Rebuild()
			end)
			local names = {}
			for _, token in ipairs(list) do names[#names + 1] = EmoteName(token) end
			head.summary:SetText(not expanded and table.concat(names, ", ") or "")
			for k, token in ipairs(expanded and list or {}) do
				n = n + 1
				local row = Row(n)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", box, "TOPLEFT", 26, -y)
				row:Show()
				y = y + ROW_H
				local text = EmoteName(token)
				if token ~= SAME then text = text .. "  |cff808080" .. Command(token) .. "|r  " .. EmoteTags(token) end
				if token == SAME then
					text = text .. "  |cff808080" .. L["(the emote they did at you)"] .. "|r"
				end
				row.name:SetText(text)
				row.name:SetAlpha(open and 1 or 0.5)
				row.play:SetShown(token ~= SAME)
				row.play:SetScript("OnClick", function() TryEmote(token) end)
				row.up:SetEnabled(open and k > 1)
				row.remove:SetEnabled(open)
				row.up:SetScript("OnClick", function()
					local now = List(moment)
					now[k], now[k - 1] = now[k - 1], now[k]
					Save(moment, now)
				end)
				row.remove:SetScript("OnClick", function()
					local now = List(moment)
					table.remove(now, k)
					Save(moment, now)
				end)
			end
			if not expanded then
				y = y + 2
			elseif #list == 0 then
				n = n + 1
				local row = Row(n)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", box, "TOPLEFT", 26, -y)
				row:Show()
				row.name:SetText("|cff808080" .. L["No emotes: no card"] .. "|r")
				row.play:Hide()
				row.up:Hide()
				row.remove:Hide()
				y = y + ROW_H
			else
				for k = n - #list + 1, n do rows[k].up:Show() rows[k].remove:Show() end
			end
			if expanded then
				head.add:ClearAllPoints()
				head.add:SetPoint("TOPLEFT", box, "TOPLEFT", 26, -y)
				head.add:Show()
				head.add:SetEnabled(open and #list < MAX_EMOTES)
				head.add:SetScript("OnClick", function(self) AddMenu(self, moment) end)
				y = y + 28
			end
		end
		defaults:ClearAllPoints()
		defaults:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y - 4)
		defaults:SetEnabled(pageOn)
		box:SetHeight(y + 30)
		if kit.FitContentHeight then kit.FitContentHeight(content) end
	end

	-- (Rebuilt as the page shows and as settings change: a profile, Reset.)
	box.Refresh = function()
		if content:IsVisible() then Rebuild() end
	end
	box.pageSwitch = false
	kit.AddControl(box)
	Rebuild()
end

local LookTiles -- (below, with its pictures)

-- Vision: turning it on, where (Show in), and the moments and their emotes.
function ns.CreateEmoteVisionPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Emote Vision"])
	Tabs(content, title, 1)
	local intro = kit.PageIntro(content, title,
		L["When someone does something for you or at you, a small card shows who it was, with a few " ..
		"emotes to answer in one click. It waits out fights and fades away by itself. Pick the moments and " ..
		"their emotes below. When it shows: the Settings tab. Its style and look: the Look tab."])
	local switch = kit.PageSwitch(content, "emoteVision", L["Enable Page"],
		L["On: the cards show as ticked below. Off: none do, and it keeps its settings for when " ..
		"you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")

	local header = stack:Header(content, L["Show in"])
	local lastRow = ns.ShowTable(content, header, {
		underHeader = true,
		{ key = ROW_KEY, label = L["Emote Vision"], alwaysKey = "emoteVisionAlways",
			alwaysOn = function() return ns.GetDB().emoteVisionAlways end,
			setAlways = function(value) ns.GetDB().emoteVisionAlways = value Changed() end,
			alwaysTip = L["Shows wherever you are. (Never in a fight: a card from one waits for it to end.)"],
			apply = Changed },
	}, L["Emote Vision"])
	stack:Continue(lastRow, "label")

	local moments = stack:Header(content, L["Moments"])
	local test = TestButton(content)
	-- (After the "?" its help puts beside it, 6 + 18 wide: PageIntro's.)
	test:SetPoint("LEFT", moments, "RIGHT", 36, 0)
	kit.Tooltip(test, L[TEST_TIP])
	stack:Help(content, L["Each moment's card has a button for each emote under it, in that order. Untick a " ..
		"moment for no card at all. + opens a moment."])
	MomentsGrid(kit, content, stack)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Emote Vision")
end

-- Settings: when the cards show, and for how long.
function ns.CreateEmoteVisionSettingsPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Emote Vision"])
	Tabs(content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["When the cards show and for how long. The moments and their emotes: the Vision tab. Its look: " ..
		"the Look tab."])
	local stack = kit.Stack(intro, "label")
	local b = ns.VisionRows(kit, content, stack, Changed)

	stack:Header(content, L["When"])
	b.Toggles(L["Only:"], {
		{ "emoteVisionStill", L["Only while you stand still"], L["While you're moving the card waits, and " ..
			"shows once you stop (if that's within 20 seconds)."] },
	}, On)
	b.Toggles(L["Repeats:"], {
		{ "emoteVisionRepeats", L["Ignore repeats from the same person"], L["The same person doing the same " ..
			"again (buffing you again, another wave) brings up no card for the minutes below. Their other " ..
			"moments still do."] },
	}, On)
	b.Toggles(L["Buffs:"], {
		{ "emoteVisionGroupBuffs", L["Ignore buffs from your group"], L["Buffs from people in your party or " ..
			"raid bring up no card: only strangers' do."] },
	}, On)
	b.Number(L["Ignored for:"], "emoteVisionRepeatMins", 1, 60, 1, 1, L["min"], L["How long a repeat is ignored for."],
		function(db) return db.emoteVision and db.emoteVisionRepeats end)
	b.Number(L["Stays for:"], "emoteVisionHold", 3, 20, 1, 1, L["sec"],
		L["How long a card stays before it fades. The mouse over it holds it."], On)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Emote Vision Settings")
end

-- The six styles as picture tiles (as Damage Vision's types): a little card
-- in each one's look, a click picks it. Draw: its textures on the tile's
-- picture area, 100 x 40.
local function Rect(area, layer, r, g, b, a, w, h, point, x, y)
	local tex = area:CreateTexture(nil, layer)
	tex:SetColorTexture(r, g, b, a)
	tex:SetSize(w, h)
	tex:SetPoint(point or "CENTER", area, point or "CENTER", x or 0, y or 0)
	return tex
end
local function Dot(area, layer, r, g, b, size, point, x, y)
	local tex = area:CreateTexture(nil, layer)
	tex:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	tex:SetVertexColor(r, g, b)
	tex:SetSize(size, size)
	tex:SetPoint(point or "CENTER", area, point or "CENTER", x or 0, y or 0)
	return tex
end
local LOOK_DRAW = {
	classic = function(area)
		Rect(area, "BACKGROUND", 0.55, 0.42, 0.16, 1, 92, 40)
		Rect(area, "BORDER", 0.04, 0.04, 0.05, 1, 90, 38)
		Dot(area, "ARTWORK", 0.85, 0.85, 0.85, 12, "TOPLEFT", 8, -5)
		Rect(area, "ARTWORK", 1, 1, 1, 0.9, 40, 3, "TOPLEFT", 24, -7)
		Rect(area, "ARTWORK", 1, 0.82, 0, 0.9, 54, 3, "TOPLEFT", 24, -13)
		for i = 0, 2 do Rect(area, "ARTWORK", 0.4, 0.08, 0.08, 1, 22, 8, "TOPLEFT", 12 + i * 25, -24) end
	end,
	parchment = function(area)
		Rect(area, "BACKGROUND", 0.42, 0.29, 0.13, 1, 92, 40)
		Rect(area, "BORDER", 0.9, 0.83, 0.64, 1, 88, 36)
		Dot(area, "ARTWORK", 0.6, 0.16, 0.13, 13, "TOPLEFT", 8, -5)
		Rect(area, "ARTWORK", 0.23, 0.15, 0.06, 1, 40, 3, "TOPLEFT", 25, -7)
		Rect(area, "ARTWORK", 0.42, 0.29, 0.14, 1, 52, 2, "TOPLEFT", 25, -13)
		Rect(area, "ARTWORK", 0.62, 0.5, 0.31, 1, 74, 1, "TOPLEFT", 9, -21)
		for i = 0, 2 do Rect(area, "ARTWORK", 0.42, 0.27, 0.1, 0.4, 20, 7, "TOPLEFT", 13 + i * 24, -26) end
	end,
	bubble = function(area)
		Dot(area, "ARTWORK", 0.85, 0.85, 0.85, 14, "LEFT", 0, 0)
		Rect(area, "BACKGROUND", 0.85, 0.85, 0.85, 0.9, 78, 38, "RIGHT", 0, 0)
		Rect(area, "BORDER", 0.12, 0.12, 0.13, 0.95, 76, 36, "RIGHT", -1, 0)
		Rect(area, "BORDER", 0.85, 0.85, 0.85, 0.9, 6, 6, "LEFT", 16, 0) -- (its tail, at the face)
		Rect(area, "ARTWORK", 1, 1, 1, 0.9, 50, 3, "TOPLEFT", 30, -8)
		for i = 0, 2 do Rect(area, "ARTWORK", 0, 0, 0, 0.6, 18, 7, "TOPLEFT", 30 + i * 21, -24) end
	end,
	subtitle = function(area)
		Rect(area, "BACKGROUND", 0, 0, 0, 0.45, 84, 36)
		Rect(area, "ARTWORK", 1, 1, 1, 0.95, 60, 3, "CENTER", 0, 8)
		Rect(area, "ARTWORK", 1, 0.82, 0, 0.9, 44, 2, "CENTER", 0, 2)
		for i = -1, 1 do Rect(area, "ARTWORK", 1, 0.82, 0, 1, 14, 2, "CENTER", i * 22, -8) end
		Rect(area, "ARTWORK", 1, 0.82, 0, 0.6, 36, 1, "CENTER", 0, -15)
	end,
	banner = function(area)
		Rect(area, "BACKGROUND", 0.04, 0.04, 0.05, 1, 100, 38)
		Rect(area, "BORDER", 0.79, 0.64, 0.29, 1, 100, 2, "TOP")
		Rect(area, "BORDER", 0.79, 0.64, 0.29, 1, 100, 2, "BOTTOM", 0, 1)
		Rect(area, "ARTWORK", 0.79, 0.64, 0.29, 1, 26, 2, "TOP", 0, -6)
		Rect(area, "ARTWORK", 1, 1, 1, 1, 40, 4, "TOP", 0, -12)
		for i = -1, 1 do
			Rect(area, "ARTWORK", 0.79, 0.64, 0.29, 1, 18, 8, "TOP", i * 22, -24)
			Rect(area, "OVERLAY", 0.04, 0.04, 0.05, 1, 16, 6, "TOP", i * 22, -25)
		end
	end,
	wheel = function(area)
		Dot(area, "BACKGROUND", 0.79, 0.64, 0.29, 38)
		Dot(area, "BORDER", 0.1, 0.1, 0.11, 36)
		Dot(area, "ARTWORK", 0.85, 0.85, 0.85, 15)
		for i = 0, 5 do
			local angle = math.pi / 2 - i * math.pi / 3
			Rect(area, "OVERLAY", 0.45, 0.08, 0.06, 1, 10, 5, "CENTER", math.cos(angle) * 16, math.sin(angle) * 16)
			Rect(area, "OVERLAY", 1, 0.82, 0, 1, 6, 1, "CENTER", math.cos(angle) * 16, math.sin(angle) * 16)
		end
	end,
}
function LookTiles(kit, content, stack)
	local grid = CreateFrame("Frame", nil, content)
	grid:SetSize(400, 2 * 80 + 10)
	stack:Add(grid, "label", 2)
	for i, key in ipairs(LOOK_ORDER) do
		local tile = CreateFrame("Button", nil, grid)
		tile:SetSize(124, 80)
		tile:SetPoint("TOPLEFT", ((i - 1) % 3) * 134, -math.floor((i - 1) / 3) * 90)
		local back = tile:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0, 0, 0, 0.45)
		local lit = tile:CreateTexture(nil, "BORDER")
		lit:SetAllPoints()
		lit:SetColorTexture(1, 0.82, 0, 0.08)
		local area = CreateFrame("Frame", nil, tile)
		area:SetSize(100, 40)
		area:SetPoint("TOP", 0, -10)
		LOOK_DRAW[key](area)
		local name = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("BOTTOM", 0, 8)
		name:SetText(L[LOOK_NAMES[key]])
		local edges = ns.MakeStyleEdges(tile)
		kit.Tooltip(tile, L[LOOK_TIPS[key]])
		tile:SetScript("OnClick", function()
			ns.GetDB().emoteVisionLook = key
			Changed()
			kit.Refresh()
		end)
		tile.Refresh = function()
			local picked = (ns.GetDB() or DEFAULTS).emoteVisionLook == key
			ns.DressStyleEdges(edges, picked and 2 or 1, picked and 1 or 0.4, picked and 0.82 or 0.4,
				picked and 0 or 0.4, 1)
			lit:SetShown(picked)
			name:SetTextColor(picked and 1 or 0.8, picked and 0.82 or 0.8, picked and 0 or 0.8)
		end
		tile.pageSwitch = false
		kit.AddControl(tile)
	end
end

-- Look: its style as picture tiles (as Damage Vision's types) and the Test,
-- its words, frame and face, and where it sits.
function ns.CreateEmoteVisionStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Emote Vision"])
	Tabs(content, title, 3)
	local intro = kit.PageIntro(content, title,
		L["Pick its style, then how its words and frame look and where it sits. The font, outline, shadow " ..
		"and border start on Visions Style's. Press Test and close the settings to see it."])
	local stack = kit.Stack(intro, "label")
	local rows = ns.StyleRows(kit, content, stack, Changed, "emoteVision")
	local b = ns.VisionRows(kit, content, stack, Changed)

	stack:Header(content, L["Style"])
	LookTiles(kit, content, stack)
	local tests = b.Row("")
	local test = TestButton(tests)
	test:SetPoint("LEFT")
	kit.Tooltip(test, L[TEST_TIP])

	stack:Header(content, L["Words"])
	rows.Font("emoteFont")
	b.Number(L["Size:"], "emoteTextSize", 70, 150, 5, 100, "%", L["The words' size, next to their own."], On)
	rows.Outline("emoteOutline", L["Outline"], 2, { [0] = L["None"], L["Thin"], L["Thick"] })
	b.Choices(L["Shadow:"], "emoteShadow", {
		{ "general", ns.SharedStyleSource("emoteShadow") }, { "game", L["The game's"] }, { "on", L["Shadow"] },
		{ "none", L["None"] },
	}, On)

	stack:Header(content, L["Frame"])
	rows.Border(L["Border:"], "emoteBorder", { game = L["The game's"] })
	b.Toggles(L["Show:"], {
		{ "emoteVisionPortrait", L["Their face"], L["Their portrait on the card (their class's icon when " ..
			"they're out of sight)."] },
	}, On)

	stack:Header(content, L["Position"])
	b.Number(L["Scale:"], "emoteVisionScale", 50, 150, 5, 100, "%", L["The whole card at once."], On)
	-- Its X and Y (yours, once typed or dragged), Move to drag it, Reset to put
	-- it back above speech from behind you.
	local XY_TIP = L["How far right (X) of the middle of the screen, and up (Y) from its bottom, the card sits. " ..
		"Typing here or dragging it with Move puts it there; Reset puts it back above speech from behind you."]
	local row, name = b.Row(L["Emote Vision:"])
	local line = kit.BoxLine(content) -- (the page's: its Reset puts them back)
	line:SetPoint("LEFT", name, "RIGHT", 4, 0)
	local function Own()
		ns.GetDB().emoteVisionSpot = "own"
		Changed()
	end
	line:Box("X", "emoteVisionX", -2000, 2000, 1, "%d", 1, XY_TIP, Own, 52)
	local yBox = line:Box("Y", "emoteVisionY", 0, 1600, 1, "%d", 1, XY_TIP, Own, 52)
	local move = b.Button(row, L["Move"], 90, L["Holds the card up so you can drag it where you want it; Done " ..
		"lets it go. Close the settings to see it."], function()
		ns.MoveEmoteVision()
	end)
	move:SetPoint("LEFT", yBox, "RIGHT", 16, 0)
	move:SetScript("OnUpdate", function(self) self:SetText(ns.EmoteVisionMoving() and L["Done"] or L["Move"]) end)
	local reset = b.Button(row, L["Reset"], 90, L["Puts the card back where it starts: just above where speech " ..
		"from behind you shows (the Chat Bubbles page's Move), beside the chat window."], function()
		local db = ns.GetDB()
		db.emoteVisionX, db.emoteVisionY = DEFAULTS.emoteVisionX, DEFAULTS.emoteVisionY
		db.emoteVisionSpot = DEFAULTS.emoteVisionSpot
		Changed()
		kit.Refresh()
	end)
	reset:SetPoint("LEFT", move, "RIGHT", 8, 0)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Emote Vision Style")
end
