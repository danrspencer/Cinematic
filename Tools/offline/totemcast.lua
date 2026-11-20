-- Totem hits matched to their casts (offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/totemcast.lua < /dev/null
-- A shaman's Searing Totem numbers were all left out with the Combat Text
-- Style on (2026-11-20): no log line comes with a totem's hit. Now a cast
-- finished by a plate the game says is yours (not your pet) marks the mob it
-- cast at, and one hit with no line on that mob within WAIT is the totem's.
-- Checked on the stand-in (ns.CombatTextTotem, CombatTextStyle.lua): a totem's
-- cast is kept, someone else's and your pet's aren't, the hit must be on its
-- target and in time, one hit per cast, nothing kept with Your pet's on the
-- game's, the page off, or a secret answer; heals and swings never taken.
-- Says PASS or FAIL per check.
-- luacheck: push ignore 111 112 113 121 122 212
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local owners, targets, pets = {}, {}, {}
local now = 100
local ns, wow = dofile("Tools/offline/load.lua")("forever", "CinematicDev.toc", function()
	issecretvalue = function(value) return value == SECRET end
	UnitIsOwnerOrControllerOfUnit = function(_, unit) return owners[unit] end
	UnitIsUnit = function(a, b) return b == "pet" and pets[a] or false end
	UnitGUID = function(unit) return targets[unit:match("^(.-)target$") or ""] end
	GetTime = function() return now end
end)
-- luacheck: pop

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

local totem = ns.CombatTextTotem
Check("the matcher is on ns", type(totem) == "table" and type(totem.Take) == "function")
local MOB, OTHER = "Creature-0-1-2-3-94-AAAA", "Creature-0-1-2-3-116-BBBB"
ns.db.styleGeneral, ns.db.combatTextStyle, ns.db.combatTextNumbers, ns.db.combatTextPetBy = true, true, true, "ours"
local function Cast(unit) wow.Fire("UNIT_SPELLCAST_SUCCEEDED", unit, "cast", 3606) end
local function Reset() wipe(totem.casts) owners, targets, pets = {}, {}, {} end

-- 1. Your totem's cast marks its target; its hit is taken once.
Reset()
owners.nameplate2, targets.nameplate2 = true, MOB
Cast("nameplate2")
Check("your totem's cast kept", #totem.casts == 1 and totem.casts[1].target == MOB, #totem.casts)
now = now + 0.15
Check("its hit on its target is the totem's", totem.Take(MOB, now, now) == true)
Check("one hit per cast", totem.Take(MOB, now, now) == false)

-- 2. On another mob, or too late: not the totem's.
Cast("nameplate2")
now = now + 0.1
Check("a hit on another mob isn't", totem.Take(OTHER, now, now) == false)
now = now + totem.WAIT + 0.1
Check("a hit after WAIT isn't", totem.Take(MOB, now, now) == false)
Check("old casts let go", #totem.casts == 0, #totem.casts)
-- (A far totem's bolt: 1.07 s on, from 20 yards in game, still counts.)
Cast("nameplate2")
now = now + 1.1
Check("a far bolt's hit 1.1 s on is the totem's", totem.Take(MOB, now, now) == true)

-- 3. Not yours, your pet, no target, secret answers, not a plate: nothing kept.
Reset()
targets.nameplate3 = MOB
Cast("nameplate3")
Check("someone else's totem not kept", #totem.casts == 0)
owners.nameplate4, pets.nameplate4, targets.nameplate4 = true, true, MOB
Cast("nameplate4")
Check("your pet's cast not kept (PetHit has those)", #totem.casts == 0)
owners.nameplate5 = true
Cast("nameplate5")
Check("a cast with no target not kept", #totem.casts == 0)
owners.nameplate6, targets.nameplate6 = SECRET, MOB
Cast("nameplate6")
Check("a secret owner answer not kept", #totem.casts == 0)
owners.target, targets.target = true, MOB
Cast("target")
Check("only plate units (no double count)", #totem.casts == 0)

-- 4. Your pet's numbers by the game, or the page off: nothing kept.
Reset()
owners.nameplate2, targets.nameplate2 = true, MOB
ns.db.combatTextPetBy = "game"
Cast("nameplate2")
Check("Your pet's on the game's: not kept", #totem.casts == 0)
ns.db.combatTextPetBy = "ours"
ns.db.combatTextStyle = false
Cast("nameplate2")
Check("page off: not kept", #totem.casts == 0)
ns.db.combatTextStyle = true

-- 5. Which hits may be a totem's: a spell's damage only.
Reset()
owners.nameplate2, targets.nameplate2 = true, MOB
Cast("nameplate2")
Check("a swing isn't a totem's", totem.Hit({ id = "swing", melee = true, guid = MOB, at = now }, now) == false)
Check("a heal isn't a totem's", totem.Hit({ id = "heal", guid = MOB, at = now }, now) == false)
Check("a spell hit is", totem.Hit({ id = "spell", guid = MOB, at = now }, now) == true)

for _, warning in ipairs(wow.warnings) do
	if warning:find("CombatText", 1, true) then Check("load: " .. warning, false) end
end
print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
if fails > 0 then os.exit(1) end
