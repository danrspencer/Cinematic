-- Combat Text Style's texts (CombatTextStyle.lua draws them, CombatTextPage.lua
-- is their page): every kind of text the game sends, in a tree. Each one
-- starts out the same as its group, its group the same as All texts; a
-- setting changed on one is its own from then on, the rest still its
-- group's (as the Names rows'). Clear puts it back to its group's. (2026-11-18: in place of a tab per text,
-- the player's call: anything about any text, changed on its own.)
--
-- Settings: ct_<text>_<setting> (ns.CombatTexts.Key), except All texts'
-- font, edge and size, which keep their older names (combatTextFont...,
-- a theme's settings name them). Nothing saved for a text: its built-in
-- look (a swing's white), else its group's, setting by setting.
--
-- A crit's group is the hit it crits: a fire spell's crit, not set on its
-- own, looks as Fire does; one of its own looks as Spell crits says.
--
-- Spells and abilities are one group (2026-11-18, the player's call: both
-- are something you cast or press), and each of the two (Swings, Spells and
-- abilities) has its own Misses, with only the words it can get: a spell
-- can't be dodged, a swing can't be resisted. A miss looks as its Misses
-- group: white under Swings, yellow under Spells and abilities.

local _, ns = ...
local DEFAULTS = ns.DEFAULTS
local L = ns.L

local CT = {}
ns.CombatTexts = CT

local WHITE = { 1, 1, 1 }
local SPELL = { 1, 0.867, 0 } -- (the game's, read off a screenshot: 255, 221, 0)
local HEAL = { 0.1, 1, 0.1 }
CT.SPELL = SPELL

-- The parts of a text's look, and their settings.
local PARTS = {
	Color = { "R", "G", "B" },
	-- (CritScale: a crit's size, times a hit's. CastSize, CastTime: how much
	-- bigger and longer a spell's number is for each second of its cast,
	-- 2026-11-18; 0, or a cast not known, leaves it as it is.)
	Text = { "Font", "Size", "CritScale", "CastSize", "Edge" },
	Place = { "Y", "X", "Start" },
	Motion = { "Move", "Climb", "Time", "CastTime", "Fade", "Pop" },
}
CT.PARTS = PARTS
local PART_OF = {}
for part, list in pairs(PARTS) do
	for _, setting in ipairs(list) do PART_OF[setting] = part end
end

-- All texts' (the start of every text): the game's look, as matched by eye
-- (CombatTextStyle.lua's notes), and the player's picks of 2026-11-18 (10 px
-- up, crits 50).
local ROOT = { R = 1, G = 0.867, B = 0, Font = "game", Size = 1, CritScale = 1.3, CastSize = 0, Edge = "game", Y = 10, X = 0,
	Start = "name", Move = "up", Climb = 1, Time = 1, CastTime = 0, Fade = 0.6, Pop = false }
-- (A cast's growth goes no further than this: a long cast's number at most
-- half again as big, and as long.)
CT.CAST_MAX = 1.5
-- A crit's place and motion, as the game's: over the plate's bar, barely
-- climbing, staying longer, popping in.
local CRIT_PLACE = { Y = 50, X = 0, Start = "bar" }
-- (Not which way it moves: the hit it crits', 2026-11-18, the player's call.)
local CRIT_MOTION = { Climb = 0.2, Time = 1.5, Fade = 0.6, Pop = true }
local function Color(c) return { R = c[1], G = c[2], B = c[3] } end

-- The tree, in the page's order. own: its parts that are its own from the
-- start, with their values. theme: the theme color it takes (a style theme's
-- combatText list) while its color isn't one the player picked. sample: what
-- the preview shows for it. word: a miss word's (the game's own string).
local NODES = {
	{ id = "all", label = "All texts", tip = "What every text starts from." },
	{ id = "damage", parent = "all", label = "Damage", tip = "Your hits on enemies." },
	{ id = "swing", parent = "damage", label = "Swings", tip = "Your melee auto attacks.",
		own = { Color = Color(WHITE) }, theme = "hit", sample = "11", damage = true },
	{ id = "swingGlance", parent = "swing", label = "Glancing", tip = "A weaker swing against a higher-level mob.",
		sample = "7", damage = true },
	{ id = "swingCrit", parent = "swing", label = "Swing crits", tip = "Your swings' crits.", crit = true,
		sample = "29", damage = true },
	{ id = "miss", parent = "swing", label = "Misses", tip = "Swings that didn't land, in the game's words.",
		misses = true },
	{ id = "spell", parent = "damage", label = "Spells and abilities", tip = "Everything you cast or press.",
		own = { Color = Color(SPELL) }, theme = "spell", sample = "23", damage = true },
	{ id = "ability", parent = "spell", label = "Abilities", tip = "Your physical abilities, like Claw.",
		sample = "27", damage = true },
	{ id = "spellHoly", parent = "spell", label = "Holy", school = 2, color = { 1, 0.9, 0.5 }, sample = "21", damage = true },
	{ id = "spellFire", parent = "spell", label = "Fire", school = 4, color = { 1, 0.5, 0.1 }, sample = "24", damage = true },
	{ id = "spellNature", parent = "spell", label = "Nature", school = 8, color = { 0.3, 1, 0.3 }, sample = "19", damage = true },
	{ id = "spellFrost", parent = "spell", label = "Frost", school = 16, color = { 0.45, 0.85, 1 }, sample = "22", damage = true },
	{ id = "spellShadow", parent = "spell", label = "Shadow", school = 32, color = { 0.65, 0.4, 1 }, sample = "25", damage = true },
	{ id = "spellArcane", parent = "spell", label = "Arcane", school = 64, color = { 1, 0.5, 0.95 }, sample = "26", damage = true },
	{ id = "spellCrit", parent = "spell", label = "Crits", tip = "Your spells' and abilities' crits.", crit = true,
		sample = "46", damage = true },
	{ id = "spellMiss", parent = "spell", label = "Misses", tip = "Spells and abilities that didn't land, in the game's words.",
		misses = true },
	{ id = "heal", parent = "all", label = "Heals", tip = "Your heals on friendly nameplates.",
		own = { Color = Color(HEAL) }, theme = "heal", sample = "18" },
	{ id = "healCrit", parent = "heal", label = "Heal crits", tip = "Your heals' crits.", crit = true, sample = "37" },
}
-- Each Misses group's words, in the game's order, after its group: a
-- swing's (missDodge...), a spell's or ability's (spellMissDodge...).
-- spellOnly: never a swing's.
local WORDS = {
	{ "Miss", "MISS" }, { "Dodge", "DODGE" }, { "Parry", "PARRY" }, { "Block", "BLOCK" },
	{ "Resist", "RESIST", spellOnly = true }, { "Immune", "IMMUNE" }, { "Evade", "EVADE" }, { "Absorb", "ABSORB" },
	{ "Deflect", "DEFLECT" }, { "Reflect", "REFLECT", spellOnly = true },
}
for _, group in ipairs({ "miss", "spellMiss" }) do
	local at
	for index, node in ipairs(NODES) do
		if node.id == group then at = index end
	end
	for _, word in ipairs(WORDS) do
		if group == "spellMiss" or not word.spellOnly then
			at = at + 1
			table.insert(NODES, at, { id = group .. word[1], parent = group, word = word[2], label = word[1],
				spellOnly = word.spellOnly })
		end
	end
end
CT.NODES = NODES
local NODE = {}
for index, node in ipairs(NODES) do
	node.index = index
	NODE[node.id] = node
	if node.crit then node.own = { Place = CRIT_PLACE, Motion = CRIT_MOTION } end
	if node.misses then node.own = { Place = { Y = 0, X = 0, Start = "name" } } end
end
CT.NODE = NODE
-- (Each one's depth in the tree and its children, for the page's list.)
for _, node in ipairs(NODES) do
	local parent = node.parent and NODE[node.parent]
	node.depth = parent and parent.depth + 1 or 0
	if parent then
		parent.children = parent.children or {}
		parent.children[#parent.children + 1] = node.id
	end
end
-- A miss word's node, by the game's word ("DODGE"): a swing's, and a
-- spell's (SPELL_WORD_NODE); a school's.
CT.WORD_NODE, CT.SPELL_WORD_NODE, CT.SCHOOL_NODE = {}, {}, {}
for _, node in ipairs(NODES) do
	if node.word and node.parent == "miss" then CT.WORD_NODE[node.word] = node.id end
	if node.word and node.parent == "spellMiss" then CT.SPELL_WORD_NODE[node.word] = node.id end
	if node.school then CT.SCHOOL_NODE[node.school] = node.id end
end

-- A setting's key.
local LEGACY = { all = { Font = "combatTextFont", Edge = "combatTextEdge", Size = "combatTextSize" } }
function CT.Key(id, setting)
	local legacy = LEGACY[id] and LEGACY[id][setting]
	return legacy or ("ct_" .. id .. "_" .. setting)
end
local Key = CT.Key

-- The defaults: All texts' settings, whether each text shows, and the few
-- that only one text has. A text's own look isn't in DEFAULTS: nothing saved
-- is its group's, as the Names rows (2026-11-18, the player's call), and a
-- text's built-in look (a swing's white, a crit's place) its own until set.
for _, setting in ipairs({ "R", "G", "B", "Font", "Size", "CritScale", "CastSize", "Edge", "Y", "X", "Start", "Move",
	"Climb", "Time", "CastTime", "Fade", "Pop" }) do
	DEFAULTS[Key("all", setting)] = ROOT[setting]
end
for _, node in ipairs(NODES) do
	DEFAULTS[Key(node.id, "Show")] = true
end
DEFAULTS[Key("all", "Together")] = "side"  -- hits landing together: "side" (side by side), "stack", "top" (on top of each other)
DEFAULTS[Key("all", "Tags")] = false       -- a hit that partly landed tagged: "(Glancing)", "(Blocked)"

-- Each text's built-in look: its own parts, setting by setting.
local BUILTIN = {}
for _, node in ipairs(NODES) do
	if node.own then
		local flat = {}
		for _, values in pairs(node.own) do
			for setting, value in pairs(values) do flat[setting] = value end
		end
		BUILTIN[node.id] = flat
	end
end
CT.BUILTIN = BUILTIN

-- A setting as it applies: its usual while a switch over it is off.
local function Value(key)
	local db = ns.db
	if not db or (ns.MasterOff and ns.MasterOff(key, db)) then return DEFAULTS[key] end
	local value = db[key]
	if value == nil then return DEFAULTS[key] end
	return value
end
CT.Value = Value
-- A text's own saved value (nil: none; nil too while a switch over it is off).
local function Saved(id, setting)
	local key = Key(id, setting)
	local db = ns.db
	if not db or (ns.MasterOff and ns.MasterOff(key, db)) then return nil end
	return db[key]
end

-- The text a setting comes from, up to All texts: the first set there, or
-- built in. via: the hit a crit crits (its group in place of its own parent).
local function Parent(id, via)
	local node = NODE[id]
	if node.crit and via and NODE[via] then return via end
	return node.parent
end
CT.Parent = Parent
-- Gives the value and the text it's from ("all" for All texts').
function CT.Get(id, setting, via)
	local step = id
	for _ = 1, 12 do
		if not step or step == "all" then break end
		local value = Saved(step, setting)
		if value ~= nil then return value, step end
		local built = BUILTIN[step] and BUILTIN[step][setting]
		if built ~= nil then return built, step end
		step = Parent(step, via)
		via = nil -- (only a crit's own step goes through its hit)
	end
	return Value(Key("all", setting)), "all"
end
function CT.From(id, setting, via)
	return select(2, CT.Get(id, setting, via))
end
-- What a text would have with nothing of its own: its built-in, else its
-- group's.
function CT.Usual(id, setting)
	local built = BUILTIN[id] and BUILTIN[id][setting]
	if built ~= nil then return built, id end
	if id == "all" then return DEFAULTS[Key("all", setting)], "all" end
	return CT.Get(Parent(id), setting)
end

-- A text's color ({ r, g, b }). via: the hit a crit crits. A built-in
-- color: the style theme's, if it has one for it.
function CT.Color(id, via)
	local step = id
	for _ = 1, 12 do
		local node = step and NODE[step]
		if not node then break end
		local r = Saved(step, "R")
		if r ~= nil then return { r, Saved(step, "G") or r, Saved(step, "B") or r } end
		local built = BUILTIN[step]
		if built and built.R ~= nil then
			local theme = node.theme and ns.ActiveStyleTheme and ns.ActiveStyleTheme()
			local own = theme and theme.combatText and theme.combatText[node.theme]
			return own or { built.R, built.G, built.B }
		end
		if step == "all" then return { Value(Key("all", "R")), Value(Key("all", "G")), Value(Key("all", "B")) } end
		step = Parent(step, via)
		if NODE[id].crit then via = nil end
	end
	return SPELL
end

-- Whether a text shows: its own switch, and every group over it (a crit's
-- or a Misses group's: not its hit's, they have their own, for crits and
-- misses only).
-- sample: the page's preview, which plays with the page off (a text's own
-- switch and its tab, right-clicked off, still count).
local TEXTS_TAB = "tabOn:Combat Text Style/page:2"
local function SwitchOn(key, sample)
	local db = ns.db
	if not db then return false end
	if sample then return db[key] ~= false end
	if ns.MasterOff and ns.MasterOff(key, db) then return false end
	local value = db[key]
	if value == nil then value = DEFAULTS[key] end
	return value ~= false
end
function CT.Shows(id, _, sample) -- (_: the hit, unused: a crit has its own switch)
	local db = ns.db
	if not db or db[TEXTS_TAB] == false then return false end
	if not SwitchOn(Key(id, "Show"), sample) then return false end
	local child, step = NODE[id], NODE[id].parent
	for _ = 1, 10 do
		if not step then break end
		if not (child.crit or child.misses) and not SwitchOn(Key(step, "Show"), sample) then return false end
		child, step = NODE[step], NODE[step].parent
	end
	return true
end

-- A miss word: the player's own word, else the game's (gameOnly: the game's).
function CT.Word(id, gameOnly)
	local own = not gameOnly and Saved(id, "Word")
	if type(own) == "string" and own:match("%S") then return own end
	local node = NODE[id]
	if node.word then
		local word = _G[node.word]
		if type(word) == "string" and not (issecretvalue and issecretvalue(word)) then return word end
		return node.word:sub(1, 1) .. node.word:sub(2):lower()
	end
	return ""
end

-- A text's name, for the page ("Misses").
function CT.Label(id)
	local node = NODE[id]
	return node and L[node.label] or id
end

-- Every look setting, by part (the Look panel's tabs).
CT.LOOK_SETTINGS = {}
for _, list in pairs(PARTS) do
	for _, setting in ipairs(list) do CT.LOOK_SETTINGS[#CT.LOOK_SETTINGS + 1] = setting end
end
CT.PART_OF = PART_OF

-- Its parts that have something of its own (the row's button: "Own: Color").
function CT.OwnParts(id)
	local db = ns.db
	local own, seen = {}, {}
	if not db then return own end
	for _, setting in ipairs(CT.LOOK_SETTINGS) do
		local key = Key(id, setting)
		local value = db[key]
		local set = value ~= nil and (id ~= "all" or value ~= DEFAULTS[key])
		local part = PART_OF[setting]
		if set and not seen[part] then
			seen[part] = true
			own[#own + 1] = part
		end
	end
	local word = db[Key(id, "Word")]
	if type(word) == "string" and word:match("%S") and not seen.Text then own[#own + 1] = "Text" end
	table.sort(own)
	return own
end
function CT.Changed(id) return #CT.OwnParts(id) > 0 end

-- Back to its group's (All texts: to the game's). Whether it shows stays.
function CT.Reset(id)
	local db = ns.db
	if not db then return end
	for _, setting in ipairs(CT.LOOK_SETTINGS) do db[Key(id, setting)] = nil end
	db[Key(id, "Word")] = nil
end

-- A field for the page's controls: what applies, its own once set (the
-- same as it'd have anyway saved as none, as the Names rows' are).
function CT.Field(id, setting)
	if not PART_OF[setting] then return Key(id, setting) end
	local key = Key(id, setting)
	return {
		key = key,
		get = function() return (CT.Get(id, setting)) end,
		set = function(value)
			local db = ns.GetDB()
			if id ~= "all" then
				-- (What it'd have anyway, its built-in or its group's: none of its own.)
				if value == (CT.Usual(id, setting)) then value = nil end
				-- (A color: all three its own together.)
				if PART_OF[setting] == "Color" and value ~= nil then
					local now = CT.Color(id)
					for i, each in ipairs(PARTS.Color) do
						if db[Key(id, each)] == nil then db[Key(id, each)] = now[i] end
					end
				end
			end
			db[key] = value
		end,
	}
end
