-- Cooldown Manager numbered lines test (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/cooldownlines.lua < /dev/null
-- The Cooldown Manager page's numbered lines (2026-11-20, in place of
-- situations: UI/CooldownRules.lua): a line fits by its Combat and Location
-- or its CQL rule; read top to bottom, the first that fits decides, none: the
-- row's own dropdown; a spell's lines before its own, its bar's after;
-- tracked buffs and bars too; a rule typed in the editor goes back into the
-- dropdowns when they can say it; the page's block adds, moves, deletes and
-- lights the line in use; the ready pass fades by a line; and the update
-- turns old situations into lines. Says PASS or FAIL per check.
-- (Optional first argument: another .toc to load, to run it on older code.)
local now = 100

-- luacheck: push ignore 111 112 113 121 122 212
local ns = dofile("Tools/offline/load.lua")("retail", arg and arg[1], function()
	GetTime = function() return now end
	InCombatLockdown = function() return true end
end)
-- luacheck: pop

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

local db = ns.db
for _, start in ipairs({ "handleCooldowns", ns.CDM_TABS.essential, ns.CDM_TABS.utility, ns.CDM_TABS.buffs }) do
	local switch = start
	while switch do
		db[switch] = true
		switch = ns.PageSwitchOf(switch)
	end
end
Check("tables made at load", type(db.cooldownSpellRules) == "table" and type(db.cooldownBuffRules) == "table"
	and type(db.cooldownGroupRules) == "table")
Check("situations gone", db.cooldownSituations == nil and ns.BuildCooldownSituations == nil)

-- Where you are: faked facts (a dungeon, in a fight).
local facts
local function Be(place, fight, extra)
	facts = { nocombat = not fight, combat = fight, calm = false }
	if place ~= "world" then facts[place] = true end
	for k, v in pairs(extra or {}) do facts[k] = v end
	facts.nocombat = not facts.combat and not facts.calm -- (as the real facts: Frames.lua's RuleFacts)
	ns.CooldownRuleFactsStale()
end
ns.RuleFactsNow = function() return facts end
Be("dungeon", true)

local IMMOLATE, CORRUPTION = 348, 172

-- Fitting, by the dropdowns.
local function Fits(rule) return ns.CooldownRuleFits(rule, facts) end
Check("Dungeons, In combat fits in a dungeon fight", Fits({ show = "x", place = "dungeon", combat = "in" }))
Check("Dungeons, Out of combat doesn't", not Fits({ show = "x", place = "dungeon", combat = "out" }))
Check("Cities, Any doesn't", not Fits({ show = "x", place = "city", combat = "any" }))
Check("Anywhere, Any fits", Fits({ show = "x", place = "any", combat = "any" }))
Be("dungeon", false, { calm = true })
Check("Calm Timer counts as In combat", Fits({ show = "x", place = "any", combat = "in" }))
Be("dungeon", true)
Check("CQL line fits", Fits({ show = "x", cql = "dungeon and not group" }))
Check("CQL line that doesn't read never fits", not Fits({ show = "x", cql = "dungeon and (" }))

-- Top to bottom, the first that fits; none: the row's own dropdown.
db.cooldownProcOnly[IMMOLATE] = true
db.cooldownSpellRules[IMMOLATE] = {
	{ show = "recharge", combat = "in", place = "dungeon" },
	{ show = "never", combat = "any", place = "any" },
}
local mode, own = ns.CooldownSpellMode(IMMOLATE, "essential")
Check("line 1 fits: While recharging", mode == "recharge" and own == true, mode)
local _, hit = ns.CooldownRuleMode("spell", IMMOLATE)
Check("line number reported", hit == 1, hit)
Be("city", false)
Check("line 2 next: Never", (ns.CooldownSpellMode(IMMOLATE, "essential")) == "never")
db.cooldownSpellRules[IMMOLATE][2] = nil
Check("no line fits: its own dropdown (When it procs)", (ns.CooldownSpellMode(IMMOLATE, "essential")) == "proc")
Check("page view (own false) skips lines", (ns.CooldownSpellMode(IMMOLATE, "essential", false)) == "proc")
Be("dungeon", true)
db.cooldownSpellRules[IMMOLATE] = {
	{ show = "always", combat = "any", place = "any" },
	{ show = "recharge", combat = "in", place = "dungeon" },
}
Check("order decides: Anywhere first wins", (ns.CooldownSpellMode(IMMOLATE, "essential")) == "always")
db.cooldownSpellRules[IMMOLATE][1], db.cooldownSpellRules[IMMOLATE][2] =
	db.cooldownSpellRules[IMMOLATE][2], db.cooldownSpellRules[IMMOLATE][1]
ns.CooldownRuleFactsStale()
Check("moved up: Dungeons first wins", (ns.CooldownSpellMode(IMMOLATE, "essential")) == "recharge")
db.cooldownSpellRules[IMMOLATE] = nil
db.cooldownProcOnly[IMMOLATE] = nil

-- When ready on a line: its own When ready parts, else its bar's.
db.cooldownSpellRules[CORRUPTION] = { { show = "ready", combat = "any", place = "any" } }
db.cooldownGroupDefaults.essential = { power = true, early = 3, anyTime = true }
local m, o, power, earlyOn, early, anyTime = ns.CooldownSpellMode(CORRUPTION, "essential")
Check("ready line takes its bar's parts", m == "ready" and o and power == true and earlyOn == true and early == 3
	and anyTime == true, ("%s %s %s %s"):format(tostring(m), tostring(power), tostring(early), tostring(anyTime)))
db.cooldownReadyOnly[CORRUPTION], db.cooldownNeedsPower[CORRUPTION] = true, nil
db.cooldownEarlyOn[CORRUPTION], db.cooldownReadyEarly[CORRUPTION] = true, 7
db.cooldownAlwaysShow[CORRUPTION] = nil
local _, _, power2, _, early2 = ns.CooldownSpellMode(CORRUPTION, "essential")
Check("ready line takes its own parts when it has them", power2 == nil and early2 == 7, tostring(early2))
db.cooldownReadyOnly[CORRUPTION], db.cooldownEarlyOn[CORRUPTION], db.cooldownReadyEarly[CORRUPTION] = nil, nil, nil
db.cooldownSpellRules[CORRUPTION] = nil
db.cooldownGroupDefaults.essential = nil

-- Under its base spell, and a bar's lines after a spell's own.
local baseSpell = ns.BaseSpell
ns.BaseSpell = function(id) return id == 99348 and IMMOLATE or baseSpell(id) end
db.cooldownSpellRules[IMMOLATE] = { { show = "never", combat = "any", place = "dungeon" } }
Check("override reads its base's lines", (ns.CooldownSpellMode(99348, "essential")) == "never")
db.cooldownSpellRules[IMMOLATE] = nil
ns.BaseSpell = baseSpell
db.cooldownGroupRules.utility = { { show = "never", combat = "in", place = "dungeon" } }
Check("bar's line decides for a spell not set", (ns.CooldownSpellMode(CORRUPTION, "utility")) == "never")
Check("bar's line in CooldownGroupSettings", (ns.CooldownGroupSettings("utility")) == "never")
db.cooldownAlwaysShow[CORRUPTION] = true
Check("spell's own dropdown beats its bar's line", (ns.CooldownSpellMode(CORRUPTION, "utility")) == "always")
db.cooldownAlwaysShow[CORRUPTION] = nil
db.cooldownGroupRules.utility = nil

-- Tracked buffs.
db.cooldownBuffRules[1126] = { { show = "hidden", combat = "any", place = "dungeon" } }
Check("buff's line decides", (ns.CooldownBuffMode(1126, "buffs")) == "hidden")
Be("world", true)
Check("buff's line out of place: its own", (ns.CooldownBuffMode(1126, "buffs")) ~= "hidden")
db.cooldownBuffRules[1126] = nil
Be("dungeon", true)

-- Mending: a bad line dropped, an empty list gone.
db.cooldownSpellRules[IMMOLATE] = { { show = 5 }, { show = "always", combat = "nope", place = "moon" } }
local list = ns.CooldownRules("spell", IMMOLATE)
Check("bad line dropped, bad parts mended", list and #list == 1 and list[1].combat == "any" and list[1].place == "any")
db.cooldownSpellRules[IMMOLATE] = { { show = 5 } }
Check("all bad: list gone", ns.CooldownRules("spell", IMMOLATE) == nil and db.cooldownSpellRules[IMMOLATE] == nil)

-- Typed in the editor: back into the dropdowns when they can say it.
local rule = { show = "always", combat = "any", place = "any" }
Check("dropdowns as text", ns.CooldownRuleText({ place = "dungeon", combat = "in" }) == "dungeon and (combat or calm)")
ns.SetCooldownRuleText(rule, "dungeon and nocombat")
Check("'dungeon and nocombat' to dropdowns", rule.cql == nil and rule.place == "dungeon" and rule.combat == "out")
ns.SetCooldownRuleText(rule, "nocombat AND dungeon")
Check("either way round, any case", rule.cql == nil and rule.place == "dungeon" and rule.combat == "out")
ns.SetCooldownRuleText(rule, "raid")
Check("'raid' to dropdowns", rule.cql == nil and rule.place == "raid" and rule.combat == "any")
ns.SetCooldownRuleText(rule, "dungeon or raid")
Check("'dungeon or raid' kept as CQL", rule.cql == "dungeon or raid")
local ok = ns.SetCooldownRuleText(rule, "dungeon and (")
Check("unfinished rule refused, line kept", ok == false and rule.cql == "dungeon or raid")
ns.SetCooldownRuleText(rule, "  ")
Check("emptied: back to Anywhere, Any", rule.cql == nil and rule.place == "any" and rule.combat == "any")

-- The page's block.
local changed = 0
local block = ns.CooldownRuleLines(CreateFrame("Frame"), { Changed = function() changed = changed + 1 end })
local MODES = { { value = "always", text = "Always" }, { value = "never", text = "Never" } }
block.Set("spell", CORRUPTION, "Corruption", MODES)
Check("no lines: no height", block.Layout() == 0 and not block.Has())
block.Add()
block.Add()
Check("Add makes lines (Always, anywhere)", #db.cooldownSpellRules[CORRUPTION] == 2
	and db.cooldownSpellRules[CORRUPTION][1].show == "always" and changed == 2)
Check("height: two lines and Everywhere else", block.Layout() == 3 * ns.COOLDOWN_LINE_H)
db.cooldownSpellRules[CORRUPTION][1].show = "never"
db.cooldownSpellRules[CORRUPTION][1].place = "raid"
block.Layout()
-- (The lines: the block's children that have a number.)
local lines = {}
for _, child in ipairs({ block:GetChildren() }) do
	if child.n and child:IsShown() then lines[child.n] = child end
end
Check("two line frames", lines[1] ~= nil and lines[2] ~= nil)
if lines[1] and lines[2] then
	Check("line 2 lit (fits here), line 1 not", lines[2].lit:IsShown() and not lines[1].lit:IsShown())
	lines[2].up:GetScript("OnClick")(lines[2].up)
	Check("move up swaps", db.cooldownSpellRules[CORRUPTION][1].place == "any"
		and db.cooldownSpellRules[CORRUPTION][2].place == "raid")
	block.Layout()
	lines[1].delete:GetScript("OnClick")(lines[1].delete)
	Check("delete removes that line", #db.cooldownSpellRules[CORRUPTION] == 1
		and db.cooldownSpellRules[CORRUPTION][1].place == "raid")
	block.Layout()
	lines[1].delete:GetScript("OnClick")(lines[1].delete)
	Check("last line deleted: list gone", db.cooldownSpellRules[CORRUPTION] == nil and block.Layout() == 0)
end
-- Edit: the rule editor opened on the line; closing it sets the line.
db.cooldownSpellRules[CORRUPTION] = { { show = "never", combat = "any", place = "any" } }
block.Layout()
local opened
local openEditor = ns.OpenRuleEditor
ns.OpenRuleEditor = function(target) opened = target end
for _, child in ipairs({ block:GetChildren() }) do
	if child.n == 1 then child.edit:GetScript("OnClick")(child.edit) end
end
ns.OpenRuleEditor = openEditor
Check("Edit opens the editor on the line", opened ~= nil and opened.Text() == "")
if opened then
	opened.Close("raid and not group")
	Check("closing it keeps the CQL on the line", db.cooldownSpellRules[CORRUPTION][1].cql == "raid and not group")
end
db.cooldownSpellRules[CORRUPTION] = nil

-- The page (2026-11-20): two columns, Spell and Icon shows; Flash and When
-- ready's Resources, Out of fights and Show early in each row's own settings,
-- the When ready part only while its dropdown or a line of its own is When ready.
do
	local cdmSpells = ns.CooldownManagerSpells
	ns.CooldownManagerSpells = function() return { { id = IMMOLATE, group = "essential" } } end
	local okShow, err = pcall(ns.CdmShowSpells, "essential")
	Check("page lists the Essential bar", okShow, err)
	local rows, groupRows, open = ns.CdmPageRows()
	local row = rows[1]
	Check("Immolate's row made", row ~= nil and row.key == IMMOLATE, row and row.key)
	if row then
		Check("its When ready parts and Flash sit in its settings", row.power:GetParent() == row.drawer
			and row.anyTime:GetParent() == row.drawer and row.early:GetParent() == row.drawer
			and row.flash and row.flash:GetParent() == row.drawer)
		local src = io.open("Options.lua"):read("*a")
		Check("no column headings left", not src:find("powerHeading") and not src:find("flashHeading"))
		-- (The stand-in keeps no sizes or points: they're caught as set.)
		local height, modeTop
		row.drawer.SetHeight = function(_, h) height = h end
		local setPoint = row.mode.SetPoint
		row.mode.SetPoint = function(self, a, b, c, x, y)
			modeTop = y
			return setPoint(self, a, b, c, x, y)
		end
		local function Show()
			ns.CdmShowSpells("essential")
			row.mode.Refresh(row.mode)
		end
		open[IMMOLATE] = true
		db.cooldownAlwaysShow[IMMOLATE] = true
		Show()
		local short, plainTop = height, modeTop
		Check("Always: no When ready part", not row.power:IsShown() and row.flash:IsShown(), tostring(row.power:IsShown()))
		db.cooldownAlwaysShow[IMMOLATE] = nil
		db.cooldownReadyOnly[IMMOLATE] = true
		Show()
		Check("When ready: its part shows, the settings grow", row.power:IsShown() and row.anyTime:IsShown()
			and row.early:IsShown() and height and short and height > short,
			("%s -> %s"):format(tostring(short), tostring(height)))
		db.cooldownReadyOnly[IMMOLATE] = nil
		db.cooldownAlwaysShow[IMMOLATE] = true
		db.cooldownSpellRules[IMMOLATE] = { { show = "ready", combat = "in", place = "any" } }
		Show()
		Check("a When ready line shows the part too", row.power:IsShown())
		local ruleBlock = row.lines
		Check("the line drawn under it", ruleBlock and ruleBlock:IsShown() and ruleBlock.Shown() == 1)
		Check("its dropdown moved down to Everywhere else", modeTop and plainTop
			and modeTop <= plainTop - ns.COOLDOWN_LINE_H * 2, ("%s -> %s"):format(tostring(plainTop), tostring(modeTop)))
		db.cooldownSpellRules[IMMOLATE] = nil
		db.cooldownAlwaysShow[IMMOLATE] = nil
		open[IMMOLATE] = nil
	end
	Check("bar row has its settings", groupRows.essential and groupRows.essential.drawer ~= nil)
	ns.CooldownManagerSpells = cdmSpells
end

-- The ready pass on the stand-in: Corruption Never on a Dungeons line, Agony
-- next to it with none; in a dungeon Corruption fades, Agony stays.
local AGONY = 980
local function Icon(id)
	local icon = CreateFrame("Frame")
	icon.GetSpellID = function() return id end
	icon:Show()
	return icon
end
local cor, agony = Icon(CORRUPTION), Icon(AGONY)
local viewer = CreateFrame("Frame", "EssentialCooldownViewer")
viewer:Show()
viewer.itemFramePool = { EnumerateActive = function()
	local all, i = { cor, agony }, 0
	return function() i = i + 1 return all[i] end
end }
viewer.GetChildren = function() return cor, agony end
ns.managed[#ns.managed + 1] = { frame = viewer, name = "EssentialCooldownViewer", group = "cooldowns", alpha = 1,
	baseAlpha = 1 }
db.cooldownAlwaysShow[CORRUPTION], db.cooldownAlwaysShow[AGONY] = true, true
db.cooldownSpellRules[CORRUPTION] = { { show = "never", combat = "any", place = "dungeon" } }
local function Pass()
	ns.CooldownRuleFactsStale()
	ns.readyPace.due = true
	now = now + 1
	local okPass, err = pcall(ns.UpdateReadyOnly, 0.1)
	if not okPass then return nil, err end
	return ns.ReadyIconProbe(CORRUPTION), ns.ReadyIconProbe(AGONY)
end
local pc, pa = Pass()
Check("ready pass: in a dungeon, the line's Never fades it", pc and pc.target == 0, pc and tostring(pc.target) or pa)
Check("ready pass: the one with no line stays", pa and pa.target ~= 0, pa and tostring(pa.target))
Be("world", true)
pc = Pass()
Check("ready pass: out of the dungeon, its own Always", pc and pc.target ~= 0, pc and tostring(pc.target))
db.cooldownSpellRules[CORRUPTION] = nil

-- The update: situations into lines (here and in a saved profile).
local function Situations()
	return {
		{ name = "Dungeon fights", places = { dungeon = true }, combat = "in", set = {
			cooldownProcOnly = { [IMMOLATE] = true }, cooldownNeverShow = { [CORRUPTION] = true },
			cooldownBuffMode = { [1126] = "hidden" }, cooldownGroupDefaults = { utility = { mode = "ready" } } } },
		{ name = "Instances", places = { dungeon = true, raid = true }, combat = "out", set = {
			cooldownAlwaysShow = { [IMMOLATE] = true } } },
		{ name = "Unused", places = {}, combat = "any", set = { cooldownAlwaysShow = { [AGONY] = true } } },
	}
end
db.cooldownSituations = Situations()
db.profiles = db.profiles or {}
db.profiles.LinesTest = { cooldownSituations = Situations() }
db.cooldownLinesV1 = nil
ns.RunMigrations()
local im = db.cooldownSpellRules[IMMOLATE]
Check("situations dropped", db.cooldownSituations == nil and db.profiles.LinesTest.cooldownSituations == nil)
Check("Immolate: two lines in situation order", im and #im == 2 and im[1].show == "proc" and im[1].place == "dungeon"
	and im[1].combat == "in" and im[2].show == "always", im and #im)
Check("two places become CQL", im and im[2] and im[2].cql == "(dungeon or raid) and nocombat", im and im[2] and im[2].cql)
Check("Never line for Corruption", db.cooldownSpellRules[CORRUPTION] and db.cooldownSpellRules[CORRUPTION][1].show == "never")
Check("buff line", db.cooldownBuffRules[1126] and db.cooldownBuffRules[1126][1].show == "hidden")
Check("bar line", db.cooldownGroupRules.utility and db.cooldownGroupRules.utility[1].show == "ready")
Check("situation with no places adds nothing", db.cooldownSpellRules[AGONY] == nil)
local saved = db.profiles.LinesTest.cooldownSpellRules
Check("saved profile converted too", saved and saved[IMMOLATE] and #saved[IMMOLATE] == 2)
Check("done flag set", db.cooldownLinesV1 == true)

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
