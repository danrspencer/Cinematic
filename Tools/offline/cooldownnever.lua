-- Cooldown Manager "Never" test (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/cooldownnever.lua < /dev/null
-- The Cooldown Manager page's Icon shows Never (2026-11-20: hide a spell's
-- icon, Corruption): the mode read back for a spell on its own, under its
-- base spell, for a whole group and on a numbered line; the page's dropdown and
-- the profile key list have it; and on the stand-in game a
-- Never icon in the Essential bar is faded by the ready pass, a flashing one
-- too, while an Always one next to it isn't. Says PASS or FAIL per check.
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
-- (The page and its bar tabs on, with every switch above them: a fresh
-- install has the page off, and its spells then follow no mode of ours.)
for _, start in ipairs({ "handleCooldowns", ns.CDM_TABS.essential, ns.CDM_TABS.utility }) do
	local switch = start
	while switch do
		db[switch] = true
		switch = ns.PageSwitchOf(switch)
	end
end
local NEVER, ALWAYS = 172, 980 -- (Corruption, Agony)
Check("db table made at load", type(db.cooldownNeverShow) == "table")

-- The mode, Default's.
db.cooldownNeverShow[NEVER] = true
local mode, own = ns.CooldownSpellMode(NEVER, "essential", false)
Check("spell set Never reads never, its own", mode == "never" and own == true, mode)
local baseSpell = ns.BaseSpell
ns.BaseSpell = function(id) return id == 99172 and NEVER or baseSpell(id) end
Check("its override reads its base's Never", (ns.CooldownSpellMode(99172, "essential", false)) == "never")
ns.BaseSpell = baseSpell
db.cooldownNeverShow[NEVER] = nil
db.cooldownGroupDefaults.utility = { mode = "never" }
Check("group set Never: its spells read never",
	(ns.CooldownSpellMode(NEVER, "utility", false)) == "never")
db.cooldownGroupDefaults.utility = nil

-- On a numbered line (situations gone, 2026-11-20: CooldownRules.lua).
db.cooldownSpellRules[NEVER] = { { show = "never", combat = "any", place = "any" } }
ns.CooldownRuleFactsStale()
Check("a line's Never used by CooldownSpellMode", (ns.CooldownSpellMode(NEVER, "essential")) == "never")
Check("the page's own dropdown left as it was", (ns.CooldownSpellMode(NEVER, "essential", false)) ~= "never")
db.cooldownSpellRules[NEVER] = nil

-- The page's dropdown: the Options.lua MODES list (by its source, the page's locals).
local src = io.open("Options.lua"):read("*a")
Check("dropdown lists Never", src:find('{ value = "never", text = L%["Never"%] }') ~= nil)
Check("OWN_MODES stores never", src:find('never = "cooldownNeverShow"') ~= nil)
local profiles = io.open("Profiles/Profiles.lua"):read("*a")
Check("profiles carry cooldownNeverShow", profiles:find('"cooldownNeverShow"') ~= nil)

-- The fade on the stand-in: two icons in the Essential bar, one Never, one
-- Always; the ready pass run; their targets read back.
local function Icon(id)
	local icon = CreateFrame("Frame")
	icon.GetSpellID = function() return id end
	icon:Show()
	return icon
end
local never, always = Icon(NEVER), Icon(ALWAYS)
local viewer = CreateFrame("Frame", "EssentialCooldownViewer")
viewer:Show()
viewer.itemFramePool = { EnumerateActive = function()
	local list, i = { never, always }, 0
	return function() i = i + 1 return list[i] end
end }
viewer.GetChildren = function() return never, always end
ns.managed[#ns.managed + 1] = { frame = viewer, name = "EssentialCooldownViewer", group = "cooldowns", alpha = 1,
	baseAlpha = 1 }
db.cooldownNeverShow[NEVER] = true
db.cooldownAlwaysShow[ALWAYS] = true
local flashing = ns.CooldownIconFlashing
ns.CooldownIconFlashing = function(icon) return icon == never end -- (its cooldown ending: Never still hides it)
ns.readyPace.due = true
local ok, err = pcall(ns.UpdateReadyOnly, 0.1)
ns.CooldownIconFlashing = flashing
Check("ready pass ran", ok, err)
local probeNever, probeAlways = ns.ReadyIconProbe(NEVER), ns.ReadyIconProbe(ALWAYS)
Check("Never icon found in the bar", probeNever ~= nil)
Check("Never icon faded (target 0)", probeNever and probeNever.target == 0,
	probeNever and tostring(probeNever.target))
Check("Always icon left shown", probeAlways and probeAlways.target ~= 0,
	probeAlways and tostring(probeAlways.target))

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
