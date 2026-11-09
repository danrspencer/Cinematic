-- Cinematic: Heal Vision on the game's own party and raid frames (the
-- Vision page). Members (pets too) show only while below full health, or as
-- the page's options say tanks and those with a debuff (you can dispel, or
-- any), and the group titles ("Group 1", "Party") hide. The mouse over the
-- frames fades everyone back in while it's there, out of combat.
--
-- As in HealerFrame.lua, the addon never knows anyone's health: their health
-- percent goes through a curve (1 below full, 0 at full) straight into
-- SetAlpha. (The mouse fading them in: a curve whose value at full health
-- goes up in steps, as the fade goes.) The game's frames can't be moved by addons in a fight, so a
-- hidden member leaves a gap rather than the others closing up.
--
-- Raid-style frames (raid, and raid-style party): the fade goes on the member
-- frame itself, so the aura icons inside it go too (on WoW Forever they're
-- forbidden frames, out of reach on their own). The game dims members out of
-- range with that same alpha, so the dimming moves to its parts instead, and
-- the game's own setting is followed straight away by ours (script hooks, as
-- Frames.lua does for the party frames). The plain party frames keep their
-- own alpha: the fade goes on their parts. Either way, parts that ignore the
-- frame's alpha (your target's outline) are skipped, and so is anything
-- CineMode is fading right now (a row unticked), so nothing fights.
local _, ns = ...

local RESCAN_EVERY = 5   -- seconds between finding each member's parts again
local UPDATE_EVERY = 0.5 -- and between going over every member (health changes come by event)
local RANGE_DIM = 0.55   -- the game's own for members out of range
local STEPS = 20         -- the mouse's fade, in this many steps

local members = {}  -- member frame -> { unit, parts, whole, alpha }, the ones faded now
local byUnit = {}   -- unit -> { member frames showing it }
local managed = {}  -- frame -> its CineMode entry (Frames.lua's ns.managed)
local titles = {}   -- group titles hidden now
local touched = {}  -- frame or part -> true: its alpha was set here (put back to 1 once let go)
local hooked = {}   -- member frames whose scripts are followed
local curves = {}   -- kind (TANKS...) -> { below, floor, [step] = its curve (false: none on this client) }
local hovered = false
local reveal, revealStep = 0, 0 -- the mouse's fade: how far in (0-1), and as a step
local hoverFrame = nil -- the member frame the mouse is over now (in fights too)
local hoverIn = {}     -- member frame -> how far its own mouseover fade is in (0-1), while it's above 0
local sinceScan, sinceUpdate = RESCAN_EVERY, 0

local function Secret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

local function Forbidden(frame)
	return frame.IsForbidden and frame:IsForbidden()
end

-- Each kind of member's health and opacity settings (Vision section).
-- (Damage, and anyone without a role: the group titles go by their opacity too.)
local TANKS = { below = "healVisionTankBelow", alpha = "healVisionTankAlpha" }
local HEALERS = { below = "healVisionHealerBelow", alpha = "healVisionHealerAlpha" }
local OTHERS = { below = "healVisionShowBelow", alpha = "healVisionMinAlpha" }
local PETS = { below = "healVisionPetBelow", alpha = "healVisionPetAlpha" }
local DEAD = { alpha = "healVisionDeadAlpha" } -- (no health setting for these two)
local OFFLINE = { alpha = "healVisionOfflineAlpha" }
local FAR = { alpha = "healVisionFarAlpha" } -- (100%: off)

-- Your target: their kind's settings, but hidden no fainter than the target
-- opacity (raise).
-- (A setting as your role has it: see ns.HealVisionSetting.)
local function Setting(key)
	return ns.HealVisionSetting(key)
end

local targetKinds = {}
local function TargetOf(kind)
	local made = targetKinds[kind]
	if not made then
		made = { below = kind.below, alpha = kind.alpha, raise = "healVisionTargetAlpha" }
		targetKinds[kind] = made
	end
	return made
end

-- A kind's opacity setting (your target's: see TargetOf).
local function Floor(kind)
	local floor = tonumber(Setting(kind.alpha)) or 0
	if kind.raise then floor = math.max(floor, tonumber(Setting(kind.raise)) or 1) end
	-- (The plate under the mouse: Mouseover, at least. See the plates' HoverOf.)
	if kind.raiseHover then floor = math.max(floor, tonumber(Setting(kind.raiseHover)) or 0) end
	return floor
end

-- The alpha a hidden member of this kind has at this step of the mouse's
-- fade: its opacity setting at 0, full at STEPS.
local function Shown(step, kind)
	local floor = Floor(kind)
	floor = math.max(0, math.min(floor, 1))
	return floor + (1 - floor) * step / STEPS
end

-- Health percent to alpha: 1 below the kind's health setting; at or above
-- it, Shown(step). 100% there means always (full health too), on every
-- line, as tanks' always did; 99% is any damage. 0% never.
local function Curve(step, kind)
	local floor = Floor(kind)
	local below = Setting(kind.below)
	local made = curves[kind]
	if not made or made.floor ~= floor or made.below ~= below then
		made = { floor = floor, below = below }
		curves[kind] = made
	end
	if made[step] ~= nil then return made[step] end
	made[step] = false
	if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum.LuaCurveType and UnitHealthPercent) then
		return false
	end
	local ok, curve = pcall(C_CurveUtil.CreateCurve)
	if ok and curve then
		curve:SetType(Enum.LuaCurveType.Step)
		below = tonumber(below) or 0.95
		if below >= 1 then
			curve:AddPoint(0, 1) -- (100%: always shown, at full health too, on every line)
		elseif below > 0 then
			curve:AddPoint(0, 1)
			curve:AddPoint(below, Shown(step, kind))
		else
			curve:AddPoint(0, Shown(step, kind)) -- (0%: never by health)
		end
		made[step] = curve
	end
	return made[step]
end

local function Plain(value)
	if Secret(value) then return nil end
	return value
end

-- The group's tanks (by role, or main tank in a raid): their own health setting.
local function Tank(unit)
	if Plain(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) == "TANK" then return true end
	return IsInRaid() and GetPartyAssignment and Plain(GetPartyAssignment("MAINTANK", unit)) == true
end

-- The settings a member goes by: pets', tanks', healers' or everyone else's.
local function KindOf(unit)
	if unit:find("pet") then return PETS end
	if Tank(unit) then return TANKS end
	if Plain(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) == "HEALER" then return HEALERS end
	return OTHERS
end

-- A debuff on them that the game's filters find: ones you can dispel
-- (newer filter first, the older one if this client doesn't know it), or any.
-- Long ones (over LONG_DEBUFF, or for good: seasonal and other hour-long
-- ones) don't count, nothing on the frame needs a heal or a dispel. A secret
-- answer is yes: only a debuff comes back secret (nothing is nil). No answer,
-- or an error (WoW Forever won't let addons see members' auras while they're
-- secret: in fights, battlegrounds): no, they go by their health.
local LONG_DEBUFF = 120 -- seconds
local DISPEL_FILTERS = { "HARMFUL|RAID_PLAYER_DISPELLABLE", "HARMFUL|RAID" }
local ANY_FILTERS = { "HARMFUL" }
local function Counts(duration)
	if Secret(duration) then return true end
	return type(duration) == "number" and duration > 0 and duration <= LONG_DEBUFF
end
local function Debuffed(unit, filters, oldFilter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for _, filter in ipairs(filters) do
			local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, filter)
			if ok then
				for i = 1, 40 do
					if i > 1 then
						ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
						if not ok then return false end
					end
					if Secret(data) then return true end
					if type(data) ~= "table" then return false end
					local okDuration, duration = pcall(function() return data.duration end)
					if okDuration and Counts(duration) then return true end
				end
				return false
			end
		end
		return false
	end
	if UnitDebuff then
		for i = 1, 40 do
			local ok, name, _, _, _, duration = pcall(UnitDebuff, unit, i, oldFilter)
			if not ok then return false end
			if Secret(name) then return true end
			if type(name) ~= "string" then return false end
			if Counts(duration) then return true end
		end
	end
	return false
end

-- What the debuff options would make of a member (for /cine debug auras),
-- on WoW Forever too, where they're hidden for now.
function ns.HealVisionDebuffs(unit)
	return ("dispellable %s, any %s"):format(tostring(Debuffed(unit, DISPEL_FILTERS, "RAID")),
		tostring(Debuffed(unit, ANY_FILTERS, nil)))
end

-- Shown whatever their health, as the Vision page's options say: tanks at
-- 100%, and those with a debuff. (Your target goes before everything, in Rule.)
-- The debuff ones are off for now, their options hidden (the choices kept):
-- neither client lets addons see members' auras in fights in instances or
-- battlegrounds (C_Secrets.ShouldAurasBeSecret says so then, see /cine debug
-- auras), only out of combat.
ns.HEAL_VISION_DEBUFFS = false
local function ShownAnyway(unit)
	local debuffs = ns.HEAL_VISION_DEBUFFS
	return ((tonumber(Setting("healVisionTankBelow")) or 1) >= 1 and Tank(unit)) -- (100%: always)
		or (debuffs and Setting("healVisionAnyDebuff") and Debuffed(unit, ANY_FILTERS, nil))
		or (debuffs and Setting("healVisionDispel") and Debuffed(unit, DISPEL_FILTERS, "RAID"))
end

-- (kind: its setting, as the Vision grid's row has it: on here, see ns.HealVisionHere.)
local function Wanted(kind)
	local db = ns.db
	return db and kind == "healVision" and ns.HealVisionHere(db) and not ns.IsSuspended()
end

-- Not while CineMode is fading it (it fades it its own way, back to full once shown).
local function Free(frame)
	local entry = managed[frame]
	return not (entry and entry.alpha < 1)
end

-- The game set a raid-style member's alpha (out of range dimming): ours back.
local function Reassert(frame)
	local member = members[frame]
	if member and member.whole and type(member.alpha) ~= "nil" and Free(frame) then
		pcall(frame.SetAlpha, frame, member.alpha)
	end
end
if ns.Profiled then Reassert = ns.Profiled("Heal Vision frame alpha hook", Reassert) end

local function Hook(frame)
	if hooked[frame] or not frame.HookScript then return end
	hooked[frame] = true
	frame:HookScript("OnEvent", Reassert)
	frame:HookScript("OnShow", Reassert)
	ns.HookOnUpdate(frame, Reassert)
end

-- The mouse onto a member: it fades in (Mouseover, at least), and out from
-- the moment the mouse is off it. (Off: asked each frame while it's there,
-- so a buff icon on it, taking the mouse, still counts as on.)
local entering = {}
local function Entered(frame)
	if members[frame] then hoverFrame = frame end
end
local function HookEnter(frame)
	if entering[frame] or not frame.HookScript then return end
	entering[frame] = true
	frame:HookScript("OnEnter", Entered)
end

-- (A main tank's target beside them is refreshed every frame from another
-- frame's OnUpdate (the game's onUpdateFrame), which the script hooks above
-- miss: the game's alpha won there between our updates, a flicker. Followed
-- where the game sets it instead: its range, and on WoW Forever its centre
-- status icon too, after the range (seen with /cine debug healwatch).)
for _, name in ipairs({ "CompactUnitFrame_UpdateInRange", "CompactUnitFrame_UpdateCenterStatusIcon",
	"CompactUnitFrame_UpdateAll" }) do
	if type(_G[name]) == "function" then hooksecurefunc(name, Reassert) end
end

-- The plain party frames' parts: the game setting one's alpha (a texture's
-- colour carries it: the portrait, recoloured as health changes, flashed on
-- its own) gets ours back straight away.
local partOf = {}   -- part -> its member frame, for the parts faded now
local hookedParts = {}
local settingPart = false
local function ReassertPart(part)
	if settingPart then return end
	local member = members[partOf[part]]
	if member and not member.whole and type(member.alpha) ~= "nil" and Free(part) then
		settingPart = true
		pcall(part.SetAlpha, part, member.alpha)
		settingPart = false
	end
end
if ns.Profiled then ReassertPart = ns.Profiled("Heal Vision part alpha hook", ReassertPart) end

local function HookPart(part)
	if hookedParts[part] then return end
	hookedParts[part] = true
	for _, method in ipairs({ "SetAlpha", "SetAlphaFromBoolean", "SetVertexColor" }) do
		if type(part[method]) == "function" then hooksecurefunc(part, method, ReassertPart) end
	end
end

-- A member's parts: its regions and child frames, less the ones that ignore its alpha.
local function Parts(frame)
	local parts = {}
	local function Add(part)
		if Forbidden(part) or not part.SetAlpha then return end
		local ignoring = part.IsIgnoringParentAlpha and part:IsIgnoringParentAlpha()
		if not Secret(ignoring) and ignoring then return end
		parts[#parts + 1] = part
	end
	for _, region in ipairs({ frame:GetRegions() }) do Add(region) end
	for _, child in ipairs({ frame:GetChildren() }) do Add(child) end
	return parts
end

-- (A main tank's target, as the raid frames show beside them ("raid3target"):
-- goes by its tank, else it would go by the mob's health. The second value:
-- true for these.)
local function Unit(frame)
	local unit = frame.displayedUnit or frame.unit
	if Secret(unit) or type(unit) ~= "string" then return nil end
	-- (Its target's target too, beside that: "raid3targettarget".)
	local tank = unit:match("^(.-)target")
	if tank and tank ~= "" then return tank, true end
	return unit, false
end

-- (whole: a raid-style frame, faded itself.)
local function AddMember(frame, kind, found, whole)
	if not frame or Forbidden(frame) or not Wanted(kind) then return end
	local unit, beside = Unit(frame)
	if not unit then return end
	-- (Found afresh each time: the game adds parts as it needs them.)
	found[frame] = { unit = unit, parts = Parts(frame), whole = whole, beside = beside }
	if whole then Hook(frame) end
	HookEnter(frame)
end

-- A group's title ("Group 1", "Party"): hidden while its kind is on, as the
-- members under it come and go.
local function GroupTitle(group)
	local name = group:GetName()
	return group.title or (name and _G[name .. "Title"])
end

local function AddTitle(group, kind, list)
	if not Wanted(kind) then return end
	local title = GroupTitle(group)
	if title and not Forbidden(title) and title.SetAlpha then list[#list + 1] = title end
end

-- The frames the members are in: the mouse over any brings everyone back,
-- out of combat only (in a fight, the hurt stay the only ones shown).
local HOLDERS = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer",
	"PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }

local function Hovered()
	if InCombatLockdown() then return false end
	for _, name in ipairs(HOLDERS) do
		local holder = _G[name]
		if holder and not Forbidden(holder) then
			local okVisible, visible = pcall(holder.IsVisible, holder)
			local okOver, over = pcall(holder.IsMouseOver, holder)
			if okVisible and okOver and not Secret(visible) and not Secret(over) and visible and over then
				return true
			end
		end
	end
	return false
end

-- Every party and raid member's frame now up (pets too), with its parts.
local function Scan()
	local found, foundTitles = {}, {}
	-- Party frames: Classic's, retail's (in PartyFrame) and the raid-style ones.
	for i = 1, 4 do AddMember(_G["PartyMemberFrame" .. i], "healVision", found) end
	local holder = _G.PartyFrame
	if holder and not Forbidden(holder) then
		for _, child in ipairs({ holder:GetChildren() }) do
			if child ~= _G.CompactPartyFrame then AddMember(child, "healVision", found) end
		end
	end
	holder = _G.CompactPartyFrame
	if holder and not Forbidden(holder) then
		AddTitle(holder, "healVision", foundTitles)
		for _, child in ipairs({ holder:GetChildren() }) do
			if child ~= GroupTitle(holder) then AddMember(child, "healVision", found, true) end
		end
	end
	-- Raid frames: members on their own, or in their groups' frames.
	holder = _G.CompactRaidFrameContainer
	if holder and not Forbidden(holder) then
		for _, child in ipairs({ holder:GetChildren() }) do
			local name = not Forbidden(child) and child:GetName()
			if name and name:find("^CompactRaidGroup%d+$") then
				AddTitle(child, "healVision", foundTitles)
				for _, member in ipairs({ child:GetChildren() }) do
					if member ~= GroupTitle(child) then AddMember(member, "healVision", found, true) end
				end
			else
				AddMember(child, "healVision", found, true)
			end
		end
	end
	wipe(managed)
	for _, entry in ipairs(ns.managed or {}) do
		if not entry.removed then managed[entry.frame] = entry end
	end
	-- What's no longer faded here: back to full.
	local still = {}
	for frame, member in pairs(found) do
		if member.whole then still[frame] = true end
		for _, part in ipairs(member.parts) do still[part] = true end
	end
	for _, title in ipairs(foundTitles) do still[title] = true end
	settingPart = true -- (not put back by ReassertPart)
	for frame in pairs(touched) do
		if not still[frame] then
			if Free(frame) then pcall(frame.SetAlpha, frame, 1) end
			touched[frame] = nil
		end
	end
	settingPart = false
	members, titles = found, foundTitles
	wipe(partOf)
	for frame, member in pairs(members) do
		if not member.whole then
			for _, part in ipairs(member.parts) do
				partOf[part] = frame
				HookPart(part)
			end
		end
	end
	wipe(byUnit)
	for frame, member in pairs(members) do
		byUnit[member.unit] = byUnit[member.unit] or {}
		table.insert(byUnit[member.unit], frame)
	end
end

-- Whether a member is in range, for the parts' dimming: a boolean (maybe
-- secret, straight to the game), or nil when there's nothing to dim.
local function InRange(unit)
	if not UnitInRange or unit == "player" then return nil end
	local isYou = UnitIsUnit(unit, "player")
	if not Secret(isYou) and isYou then return nil end
	local inRange, checked = UnitInRange(unit)
	if not Secret(checked) and not checked then return nil end
	return inRange
end

-- How far a member is from you in yards (math.huge: another instance), or
-- nil when the game won't say (secret, or hidden in dungeons and raids).
function ns.HealVisionDistance(unit)
	if UnitDistanceSquared then
		local ok, squared, checked = pcall(UnitDistanceSquared, unit)
		if ok and Plain(checked) == true and type(Plain(squared)) == "number" then
			return math.sqrt(squared)
		end
	end
	local okYou, y, x, _, instance = pcall(UnitPosition, "player")
	local okThem, theirY, theirX, _, theirInstance = pcall(UnitPosition, unit)
	if not (okYou and okThem) then return nil end
	y, x, theirY, theirX = Plain(y), Plain(x), Plain(theirY), Plain(theirX)
	instance, theirInstance = Plain(instance), Plain(theirInstance)
	if type(instance) == "number" and type(theirInstance) == "number" and instance ~= theirInstance then
		return math.huge
	end
	if type(y) ~= "number" or type(x) ~= "number" or type(theirY) ~= "number" or type(theirX) ~= "number" then
		return nil
	end
	return math.sqrt((y - theirY) ^ 2 + (x - theirX) ^ 2)
end

-- Where you are: "pvp" and "arena" (battlegrounds), "party", "raid" and
-- "scenario" (instances), or "none" (the open world).
local function PlaceType()
	local ok, inside, kind = pcall(IsInInstance)
	if not ok or Plain(inside) ~= true then return "none" end
	return Plain(kind) or "none"
end

-- A map as a zone: up through the small maps inside it (caves, city
-- districts) to the zone or dungeon map they're in. (Kept by map: maps don't
-- move, and GetMapInfo makes a table each time, every frame for each member.)
local zoneMaps = {} -- [map] = its zone map
local function ZoneMap(map)
	local kept = zoneMaps[map]
	if kept then return kept end
	local start = map
	for _ = 1, 5 do
		local ok, info = pcall(C_Map.GetMapInfo, map)
		-- (Unreadable: not kept, asked again next time.)
		if not ok or type(Plain(info)) ~= "table" then return map end
		local mapType, parent = Plain(info.mapType), Plain(info.parentMapID)
		if type(mapType) ~= "number" or mapType <= Enum.UIMapType.Dungeon
			or type(parent) ~= "number" or parent == 0 then
			break
		end
		map = parent
	end
	zoneMaps[start] = map
	return map
end

local function UnitMap(unit)
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo and Enum and Enum.UIMapType) then return nil end
	local ok, map = pcall(C_Map.GetBestMapForUnit, unit)
	map = ok and Plain(map)
	if type(map) ~= "number" then return nil end
	return ZoneMap(map)
end

-- A raid member's zone by the raid list (pets: their owner's), or nil.
local function RosterZone(unit)
	local index = unit:match("^raid(%d+)$") or unit:match("^raidpet(%d+)$")
	if not index or not GetRaidRosterInfo then return nil end
	local ok, _, _, _, _, _, _, zone = pcall(GetRaidRosterInfo, tonumber(index))
	zone = ok and Plain(zone)
	if type(zone) ~= "string" or zone == "" then return nil end
	return zone
end

-- Whether a member's in another zone than you: true, false, or nil (the game
-- won't say). The raid list's zone names first, then the maps (the floors
-- of one dungeon are one zone: the same map group).
function ns.HealVisionOtherZone(unit)
	local theirs = RosterZone(unit)
	local ok, yours = pcall(GetRealZoneText)
	yours = ok and Plain(yours)
	if theirs and type(yours) == "string" and yours ~= "" then return theirs ~= yours end
	local myMap, theirMap = UnitMap("player"), UnitMap(unit)
	if not (myMap and theirMap) then return nil end
	if myMap == theirMap then return false end
	if C_Map.GetMapGroupID then
		local okMine, myGroup = pcall(C_Map.GetMapGroupID, myMap)
		local okTheirs, theirGroup = pcall(C_Map.GetMapGroupID, theirMap)
		myGroup, theirGroup = okMine and Plain(myGroup), okTheirs and Plain(theirGroup)
		if type(myGroup) == "number" and myGroup ~= 0 and myGroup == theirGroup then return false end
	end
	return true
end

-- Far away: in battlegrounds by distance only (more than 100 yards); in
-- dungeons and raids, out of your zone (the instance), else by distance; in
-- the open world by distance, else by zone. Unknown: not far.
local FAR_YARDS = 100
local function Far(unit)
	local place = PlaceType()
	if place == "pvp" or place == "arena" then
		local yards = ns.HealVisionDistance(unit)
		return yards ~= nil and yards > FAR_YARDS
	end
	if place ~= "none" and ns.HealVisionOtherZone(unit) == true then return true end
	local yards = ns.HealVisionDistance(unit)
	if yards ~= nil then return yards > FAR_YARDS end
	return place == "none" and ns.HealVisionOtherZone(unit) == true
end

-- Which rule a member goes by, first that fits (unknown, secret: it doesn't):
-- your target (shown, its opacity at 100%), offline, dead (or a ghost), far
-- away (its slider below 100%), shown anyway (tanks at 100%, debuffs), else
-- their health (your target's hidden no fainter than its opacity: see
-- TargetOf). The second value: the opacity setting the hidden ones go by (DEAD...).
local function IsTarget(unit)
	return Plain(UnitIsUnit(unit, "target")) == true
end
-- (beside: a tank's target beside them, not kept up with the tank: their
-- health, as everyone else's.)
local function Rule(unit, beside)
	if (tonumber(Setting("healVisionTargetAlpha")) or 1) >= 1 and IsTarget(unit) then return "target" end
	if UnitIsConnected and Plain(UnitIsConnected(unit)) == false then return "offline", OFFLINE end
	if UnitIsDeadOrGhost and Plain(UnitIsDeadOrGhost(unit)) == true then return "dead", DEAD end
	if (tonumber(Setting("healVisionFarAlpha")) or 1) < 1 and Far(unit) then return "far", FAR end
	if not beside and ShownAnyway(unit) then return "shown" end
	return "health"
end

-- In battlegrounds where the game won't say how far anyone is (WoW Forever),
-- out of range of your heals stands in for far away: the game's own range
-- dimming goes to the Far away opacity instead (raid-style frames). The
-- addon never knows who's out of range (secret), so it's on top of the
-- rules that show members (health, tanks, debuffs), not one of them.
local function RangeFar(unit, rule)
	if rule ~= "health" and rule ~= "shown" then return false end
	if (tonumber(Setting("healVisionFarAlpha")) or 1) >= 1 then return false end
	local place = PlaceType()
	return (place == "pvp" or place == "arena") and ns.HealVisionDistance(unit) == nil
end

-- What Heal Vision makes of a member, for /cine debug health.
function ns.HealVisionDebug(unit)
	local db = ns.db
	if not db then return "no settings" end
	local frames = byUnit[unit] or {}
	local alpha = frames[1] and members[frames[1]] and members[frames[1]].alpha
	local otherZone = ns.HealVisionOtherZone(unit)
	-- (Off: why, as ns.HealVisionHere goes.)
	local on = Wanted("healVision") and "true"
	if not on then
		on = ns.IsSuspended() and "false (stopped for this session)"
			or (db.handleHealVision == false and "false (Heal Vision page switched off)")
			or "false (Show in grid: not ticked here)"
	end
	local rule = Rule(unit)
	if RangeFar(unit, rule) then rule = rule .. " (out of range: far away opacity)" end
	-- Each frame: its name, shown or not, faded whole (raid-style) or by
	-- parts, held by CineMode (not free), and the opacity it really has.
	local function Show(value)
		if Secret(value) then return "secret" end
		if type(value) == "number" then return ("%.2f"):format(value) end
		return tostring(value)
	end
	local list = {}
	for _, frame in ipairs(frames) do
		local okShown, shown = pcall(frame.IsShown, frame)
		local okAlpha, frameAlpha = pcall(frame.GetAlpha, frame)
		local okEffective, effective = pcall(frame.GetEffectiveAlpha, frame)
		list[#list + 1] = ("%s shown %s %s free %s alpha %s effective %s"):format(
			tostring(frame:GetName()), okShown and Show(shown) or "?", members[frame].whole and "whole" or "parts",
			tostring(Free(frame)), okAlpha and Show(frameAlpha) or "?", okEffective and Show(effective) or "?")
	end
	return ("on %s, %d frame(s), rule %s, place %s, other zone %s, far slider %s, hover step %d/%d, alpha %s [%s]"):format(
		on, #frames, rule, PlaceType(),
		tostring(otherZone), tostring(Setting("healVisionFarAlpha")), revealStep, STEPS,
		Secret(alpha) and "secret" or tostring(alpha), table.concat(list, "; "))
end

-- A member's step of the fade: the mouse over all the frames' (out of
-- combat), or its own mouseover's, as far in as that goes (its opacity:
-- the step where Shown reaches it), whichever is further.
local function HoverStep(frame, kind)
	local hover = hoverIn[frame]
	if not hover then return revealStep end
	local floor = math.max(0, math.min(Floor(kind), 1))
	local most = tonumber(Setting("healVisionMouseoverAlpha")) or 0
	if most <= floor or floor >= 1 then return revealStep end
	local top = math.min(STEPS, math.ceil((most - floor) / (1 - floor) * STEPS - 0.001))
	return math.max(revealStep, math.floor(hover * top + 0.5))
end

local function Update(frame)
	local member = members[frame]
	if not member then return end
	local unit = member.unit
	-- (A tank's target: everyone else's settings, by the tank's health.)
	local kind = member.beside and OTHERS or KindOf(unit)
	local fade = Curve(revealStep, kind)
	if not fade then return end
	local alpha, gone, rule = 1, nil, nil
	if revealStep < STEPS and UnitExists(unit) then
		rule, gone = Rule(unit, member.beside)
		if rule == "health" and IsTarget(unit) then kind = TargetOf(kind) end
		local step = HoverStep(frame, gone or kind)
		fade = Curve(step, kind) or fade
		if gone then
			alpha = Shown(step, gone)
		elseif rule == "health" then
			-- (Health as it is, not with heals being cast. Secret: straight to the game.)
			local ok, value = pcall(UnitHealthPercent, unit, false, fade)
			if ok and type(value) ~= "nil" then alpha = value end
		end
	end
	member.alpha = alpha
	if member.whole then
		if Free(frame) then
			if not pcall(frame.SetAlpha, frame, alpha) then frame:SetAlpha(1) end
			touched[frame] = true
		end
		-- (The dead, offline and far count as out of range: no dimming on top
		-- of their slider's opacity, it's theirs as set.)
		-- (Battlegrounds: out of range dims to Far away, see RangeFar.)
		local inRange = nil
		if not gone then inRange = InRange(unit) end
		local dim = RangeFar(unit, rule) and Shown(revealStep, FAR) or RANGE_DIM
		for _, part in ipairs(member.parts) do
			if Free(part) then
				if type(inRange) == "nil" or not part.SetAlphaFromBoolean
					or not pcall(part.SetAlphaFromBoolean, part, inRange, 1, dim) then
					part:SetAlpha(1)
				end
				touched[part] = true
			end
		end
	else
		settingPart = true
		for _, part in ipairs(member.parts) do
			if Free(part) then
				if not pcall(part.SetAlpha, part, alpha) then pcall(part.SetAlpha, part, 1) end
				touched[part] = true
			end
		end
		settingPart = false
	end
end

local function UpdateAll()
	for frame in pairs(members) do Update(frame) end
	for _, title in ipairs(titles) do
		if Free(title) then
			title:SetAlpha(Shown(revealStep, OTHERS))
			touched[title] = true
		end
	end
end

-- After a setting changes (Options.lua's Heal Vision page).
function ns.ApplyHealVisionFrames()
	sinceScan = RESCAN_EVERY
	Scan()
	UpdateAll()
	if ns.ApplyHealVisionPlates then ns.ApplyHealVisionPlates() end -- (the plates go by the same settings: below)
end

-- Whether it's handling any frames now (the minimap button's glow).
function ns.HealVisionActive()
	return next(members) ~= nil
end

local applyPending = false
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_IN_RANGE_UPDATE",
	"UNIT_AURA", "PLAYER_SPECIALIZATION_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
	"PLAYER_TARGET_CHANGED" }) do
	pcall(watcher.RegisterEvent, watcher, event) -- (not every client has every event)
end
watcher:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_CONNECTION"
		or event == "UNIT_IN_RANGE_UPDATE" or event == "UNIT_AURA" then
		if Secret(unit) or not byUnit[unit] then return end
		for _, frame in ipairs(byUnit[unit]) do Update(frame) end
	elseif event == "PLAYER_TARGET_CHANGED" then
		UpdateAll()
	else
		-- (After the game has set its frames up for the new group, or place:
		-- the Vision grid may say otherwise there. Once for a burst: joining
		-- a raid sends dozens.)
		if not applyPending then
			applyPending = true
			C_Timer.After(0.5, function()
				applyPending = false
				ns.ApplyHealVisionFrames()
			end)
		end
	end
end)
-- (Runs only while a Heal Vision is on or still has frames: no loop at all
-- otherwise.)
ns.FeatureLoop(watcher, function(_, elapsed)
	if not next(members) and not next(touched) and not ns.HealVisionAny() then
		return
	end
	-- The mouse over the frames: everyone fades in (as fast as CineMode's
	-- frames), and out again once it's gone.
	if next(members) then
		hovered = Hovered()
		local target = hovered and 1 or 0
		if reveal ~= target then
			reveal = ns.Approach(reveal, target, elapsed, hovered and ns.FadeInTime() or ns.FadeOutTime())
			local step = math.floor(reveal * STEPS + 0.5)
			if step ~= revealStep then
				revealStep = step
				UpdateAll()
			end
		end
	end
	-- One member's mouseover: in while the mouse is on it, out the moment it's off.
	if hoverFrame then
		local ok, over = pcall(hoverFrame.IsMouseOver, hoverFrame)
		if not members[hoverFrame] or not ok or Secret(over) or not over then hoverFrame = nil end
	end
	if hoverFrame and not hoverIn[hoverFrame] then hoverIn[hoverFrame] = 0 end
	for frame, value in pairs(hoverIn) do
		local on = frame == hoverFrame
		local now = ns.Approach(value, on and 1 or 0, elapsed, on and ns.FadeInTime() or ns.FadeOutTime())
		if now <= 0 and not on then now = nil end
		hoverIn[frame] = now
		-- (Again only as it moves a step: STEPS of the way at most.)
		if math.floor((now or 0) * STEPS + 0.5) ~= math.floor(value * STEPS + 0.5) and members[frame] then
			Update(frame)
		end
	end
	sinceScan, sinceUpdate = sinceScan + elapsed, sinceUpdate + elapsed
	if sinceUpdate < UPDATE_EVERY then return end
	sinceUpdate = 0
	if sinceScan >= RESCAN_EVERY then
		sinceScan = 0
		Scan()
	end
	UpdateAll()
end, function()
	return next(members) ~= nil or next(touched) ~= nil or ns.HealVisionAny()
end)

-- /cine debug healwatch [seconds]: logs every frame, for a while, each raid
-- and party member frame's alpha when it changes (and its health bar's),
-- with who set it (a SetAlpha hook on each, so /reload afterwards: that also
-- writes the log). To find a member frame flickering.
local watching
function ns.HealWatchDebug(seconds)
	if watching then
		ns.Print("healwatch: already running")
		return
	end
	seconds = tonumber(seconds) or 5
	local start = GetTime()
	local last, hookedSet, lastSet = {}, {}, {}
	local function Show(value)
		if Secret(value) then return "secret" end
		if type(value) == "number" then return ("%.2f"):format(value) end
		return tostring(value)
	end
	local function Describe(frame)
		local unit = frame.displayedUnit or frame.unit
		return ("%s (%s)"):format(tostring(frame:GetName()), Secret(unit) and "secret unit" or tostring(unit))
	end
	local function Log(text)
		ns.Log("healwatch", ("%.3f %s"):format(GetTime() - start, text))
	end
	local function Frames()
		local list = {}
		for frame in pairs(members) do list[frame] = true end
		local container = _G.CompactRaidFrameContainer
		if container and not Forbidden(container) then
			for _, child in ipairs({ container:GetChildren() }) do
				if not Forbidden(child) then
					local name = child:GetName()
					if name and name:find("^CompactRaidGroup%d+$") then
						for _, member in ipairs({ child:GetChildren() }) do
							if not Forbidden(member) then list[member] = true end
						end
					else
						list[child] = true
					end
				end
			end
		end
		return list
	end
	local function Watch(frame)
		if hookedSet[frame] then return end
		hookedSet[frame] = true
		hooksecurefunc(frame, "SetAlpha", function(self, alpha)
			if not watching then return end
			-- (The stack can come back secret, from code the game ran with secrets.)
			local stack = debugstack(3, 2, 0)
			if Secret(stack) or type(stack) ~= "string" then
				stack = "a secret stack"
			else
				stack = stack:gsub("Interface[/\\]AddOns[/\\]", ""):gsub("\n", " < ")
			end
			-- (Only when the value or the caller changes: the log keeps 500 lines.)
			local call = Show(alpha) .. " from " .. stack
			local seen = lastSet[self]
			if seen and seen.call == call then
				seen.count = seen.count + 1
				return
			end
			Log(("SetAlpha %s on %s%s"):format(call, Describe(self),
				seen and (" (the one before %d times)"):format(seen.count) or ""))
			lastSet[self] = { call = call, count = 1 }
		end)
	end
	watching = CreateFrame("Frame")
	Log(("start, %d seconds, %d heal vision members, hover step %d"):format(seconds, (function()
		local n = 0
		for _ in pairs(members) do n = n + 1 end
		return n
	end)(), revealStep))
	ns.SetOnUpdate(watching, function(self)
		if GetTime() - start > seconds then
			ns.SetOnUpdate(self, nil)
			watching = nil
			Log("stop")
			ns.Print("healwatch: done, /reload to write the log")
			return
		end
		for frame in pairs(Frames()) do
			Watch(frame)
			local member = members[frame]
			local okShown, shown = pcall(frame.IsVisible, frame)
			local okAlpha, alpha = pcall(frame.GetAlpha, frame)
			local bar = frame.healthBar or frame.HealthBar
			local okBar, barAlpha = false, nil
			if bar and bar.GetAlpha then okBar, barAlpha = pcall(bar.GetAlpha, bar) end
			local state = ("shown %s alpha %s bar %s ours %s%s"):format(okShown and Show(shown) or "?",
				okAlpha and Show(alpha) or "?", okBar and Show(barAlpha) or "-",
				member and Show(member.alpha) or "not a member",
				member and (" unit " .. member.unit .. " free " .. tostring(Free(frame))) or "")
			if last[frame] ~= state then
				last[frame] = state
				Log(Describe(frame) .. ": " .. state)
			end
		end
	end)
	ns.Print(("healwatch: logging the raid frames' alpha for %d seconds"):format(seconds))
end

-- Heal Vision on nameplates (the page's Nameplates tick): a friendly
-- player's or minion's plate (yours too: your pet) shows only while they need
-- healing, by the same health and opacity settings as the frames (their
-- role's: tanks, healers, damage, pets), your target's raise and the dead's
-- opacity. Its parts fade but those ticked in Don't fade (the name, to start
-- with). As on the frames, the addon never knows anyone's health: it goes
-- through the kind's curve straight into each layer's alpha.
-- The Plate parts grid sets its own alpha on each part's frame (PlateParts.lua
-- PART_FRAMES), and a secret alpha can't be multiplied with it here, so the
-- fade goes one layer down: the textures, texts and frames inside each part's
-- frame (a part that is a texture or text itself: that). Each layer's own
-- alpha is noted the first time and the curve scaled by it, so a faint one
-- (a highlight) never comes back brighter, and given back when let go.
-- Plates the game locks (friendly ones in dungeons and raids) aren't reachable.
-- In CineMode or not: it's for healing.
ns.DEFAULTS.healVisionPlates = false
-- The parts it can fade (as the Plate parts grid names them), each with a
-- Don't fade tick: healVisionPlatesKeep<part>. Only the name kept to start with.
ns.HEAL_PLATE_PARTS = { "Health", "Name", "CastBar", "Buffs", "Debuffs", "RaidMarker", "Level", "Highlight",
	"Widgets" }
for _, part in ipairs(ns.HEAL_PLATE_PARTS) do
	ns.DEFAULTS["healVisionPlatesKeep" .. part] = part == "Name"
end
local plateLayers = {} -- [nameplate unit] = { [layer] = its own alpha }, the layers faded on its plate
local plateParts = {} -- [nameplate unit] = { [part] = layers faded } (for /cine debug healplates)

local function Reachable(region)
	if type(region) ~= "table" or not region.SetAlpha then return false end
	local forbidden = Forbidden(region)
	return not (Secret(forbidden) or forbidden)
end

-- A plate's unit frame, if the game lets addons at it.
local function PlateFrame(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	local unitFrame = plate and plate.UnitFrame
	return Reachable(unitFrame) and unitFrame or nil
end

-- The layers to fade on a plate, by part: [layer] = its part; and how many
-- each part has.
local function PlateLayersOf(unitFrame)
	if not ns.PlatePartFrames then return nil end
	local found, byPart = {}, {}
	local function Add(layer, part)
		if Reachable(layer) and not found[layer] then
			found[layer] = part
			byPart[part] = (byPart[part] or 0) + 1
		end
	end
	for _, part in ipairs(ns.HEAL_PLATE_PARTS) do
		if not ns.Setting("healVisionPlatesKeep" .. part) then
			for _, frame in ipairs(ns.PlatePartFrames(unitFrame, part)) do
				if frame.IsObjectType and frame:IsObjectType("Frame") then
					for _, region in ipairs({ frame:GetRegions() }) do Add(region, part) end
					for _, child in ipairs({ frame:GetChildren() }) do Add(child, part) end
				else
					Add(frame, part)
				end
			end
		end
	end
	return found, byPart
end

-- The settings a plate's unit goes by (nil: not one it fades): pets', or a
-- player's by role (anyone not in your group has none: Damage's).
local function PlateKindOf(unit)
	if Plain(UnitIsUnit(unit, "player")) ~= false then return nil end
	local kind = ns.PlateKind and ns.PlateKind(unit)
	if kind == "FriendlyMinions" then return PETS end
	-- (A friendly NPC only in your group: follower dungeon and delve
	-- companions, healed like players. Guards, vendors and the rest: not.)
	if kind == "FriendlyNPCs" then
		local grouped = (UnitInParty and Plain(UnitInParty(unit)) == true)
			or (UnitInRaid and type(Plain(UnitInRaid(unit))) == "number")
		if not grouped then return nil end
	elseif kind ~= "Friends" then
		return nil
	end
	if Tank(unit) then return TANKS end
	if Plain(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) == "HEALER" then return HEALERS end
	return OTHERS
end

-- A kind's curve as Curve makes it (step 0), its values times a layer's own
-- alpha. [kind] = { below, floor, [own] = curve (false: none) }.
local scaledCurves = {}
local function ScaledCurve(kind, own)
	local below, floor = Setting(kind.below), Shown(0, kind)
	local made = scaledCurves[kind]
	if not made or made.below ~= below or made.floor ~= floor then
		made = { below = below, floor = floor }
		scaledCurves[kind] = made
	end
	own = math.floor(own * 100 + 0.5) / 100
	if made[own] ~= nil then return made[own] end
	made[own] = false
	if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum.LuaCurveType and UnitHealthPercent) then return false end
	local ok, curve = pcall(C_CurveUtil.CreateCurve)
	if ok and curve then
		curve:SetType(Enum.LuaCurveType.Step)
		below = tonumber(below) or 0.95
		if below >= 1 then
			curve:AddPoint(0, own) -- (100%: always shown)
		elseif below > 0 then
			curve:AddPoint(0, own)
			curve:AddPoint(below, floor * own)
		else
			curve:AddPoint(0, floor * own)
		end
		made[own] = curve
	end
	return made[own]
end

-- The plate under the mouse shows no fainter than Mouseover, at least (the
-- frames' setting too; 0%: off; not the dead): [kind] = that kind with it.
-- hoverUnit: that plate's unit (nil: none), found on UPDATE_MOUSEOVER_UNIT
-- and let go once the mouse is off it (polled: the game says nothing then).
local hoverKinds = {}
local hoverUnit
local function HoverOf(kind)
	local made = hoverKinds[kind]
	if not made then
		made = { below = kind.below, alpha = kind.alpha, raise = kind.raise, raiseHover = "healVisionMouseoverAlpha" }
		hoverKinds[kind] = made
	end
	return made
end

-- Gives a plate's faded layers back their own alpha: all, or those not in keep.
local function ReleasePlate(unit, keep)
	local layers = plateLayers[unit]
	if not layers then return end
	for layer, own in pairs(layers) do
		if not (keep and keep[layer]) then
			pcall(layer.SetAlpha, layer, own)
			layers[layer] = nil
		end
	end
	if not next(layers) then plateLayers[unit] = nil end
end

local function UpdatePlate(unit)
	local unitFrame = PlateFrame(unit)
	local kind = unitFrame and ns.Setting("healVisionPlates") and PlateKindOf(unit)
	local wanted, byPart
	if kind then wanted, byPart = PlateLayersOf(unitFrame) end
	ReleasePlate(unit, wanted)
	plateParts[unit] = byPart
	if not (wanted and next(wanted)) then return end
	local dead = UnitIsDeadOrGhost and Plain(UnitIsDeadOrGhost(unit)) == true
	if not dead and IsTarget(unit) then kind = TargetOf(kind) end
	if unit == hoverUnit then kind = HoverOf(kind) end
	local layers = plateLayers[unit] or {}
	plateLayers[unit] = layers
	for layer in pairs(wanted) do
		local own = layers[layer]
		if not own then
			-- (Its own alpha, the first time: a secret one counts as full. The
			-- cast bar's always full: the game fades it out after each cast, and
			-- read then, it would stay that faint.)
			local ok, alpha = pcall(layer.GetAlpha, layer)
			own = wanted[layer] ~= "CastBar" and ok and type(alpha) == "number" and not Secret(alpha) and alpha or 1
			layers[layer] = own
		end
		local alpha = own
		if dead then
			alpha = Shown(0, DEAD) * own
		else
			local fade = ScaledCurve(kind, own)
			if fade then
				local ok, value = pcall(UnitHealthPercent, unit, false, fade)
				if ok and type(value) ~= "nil" then alpha = value end
			end
		end
		if not pcall(layer.SetAlpha, layer, alpha) then pcall(layer.SetAlpha, layer, own) end
	end
end

local plateWatch = CreateFrame("Frame")
local PLATE_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "UNIT_MAXHEALTH",
	"PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "UNIT_FLAGS", "UPDATE_MOUSEOVER_UNIT",
	-- (Each cast shows the cast bar afresh at full: faded again at once, and
	-- the next frame, after the game has set it up. Seen blinking per cast
	-- with only the half-second pass.)
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP" }
local CAST_EVENTS = {}
for _, event in ipairs(PLATE_EVENTS) do
	if event:find("^UNIT_SPELLCAST_") then CAST_EVENTS[event] = true end
end
-- A cast ending: the game flashes its cast bar and fades it out itself,
-- setting its alpha every frame for a moment (it lit up at the end of each
-- cast, seen on video), so that plate is faded again every frame meanwhile.
-- Polled, not a hook on the game's cast bar. [unit] = until when.
local CAST_ENDS = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_EMPOWER_STOP = true }
local CAST_END_HOLD = 1 -- seconds
local castEnding = {}
local castHolder = CreateFrame("Frame")
castHolder:Hide()

local function UpdateAllPlates()
	for unit in pairs(plateLayers) do UpdatePlate(unit) end
	if not ns.Setting("healVisionPlates") then return end
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if type(unit) == "string" and not Secret(unit) then UpdatePlate(unit) end
	end
end

-- Parts come and go on a plate (auras, a cast) and the game sets some
-- layers' alpha itself: every plate again twice a second while it's on.
local plateTicker

-- After the tick or a Heal Vision setting changes: listened to only while
-- it's on (UNIT_HEALTH comes for every unit), every plate faded let go when off.
function ns.ApplyHealVisionPlates()
	local on = ns.Setting("healVisionPlates") and true or false
	for _, event in ipairs(PLATE_EVENTS) do
		if on then
			pcall(plateWatch.RegisterEvent, plateWatch, event)
		else
			pcall(plateWatch.UnregisterEvent, plateWatch, event)
		end
	end
	if on and not plateTicker then
		plateTicker = C_Timer.NewTicker(0.5, function() UpdateAllPlates() end)
	elseif not on and plateTicker then
		plateTicker:Cancel()
		plateTicker = nil
	end
	UpdateAllPlates()
end

plateWatch:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_REMOVED" then
		ReleasePlate(unit) -- (the plate goes back to the game for another unit)
		plateParts[unit] = nil
		if hoverUnit == unit then hoverUnit = nil end
	elseif event == "PLAYER_TARGET_CHANGED" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
		UpdateAllPlates()
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		-- (Which plate's unit the mouse is on: none of them, nothing to do.)
		local was = hoverUnit
		hoverUnit = nil
		for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
			local each = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			if type(each) == "string" and not Secret(each) and Plain(UnitIsUnit(each, "mouseover")) == true then
				hoverUnit = each
				break
			end
		end
		if was and was ~= hoverUnit then UpdatePlate(was) end
		if hoverUnit then
			UpdatePlate(hoverUnit)
			castHolder:Show() -- (watches for the mouse leaving it)
		end
	elseif type(unit) == "string" and not Secret(unit) and unit:find("^nameplate") then
		UpdatePlate(unit)
		if CAST_EVENTS[event] then
			C_Timer.After(0, function() UpdatePlate(unit) end)
		end
		if CAST_ENDS[event] and plateLayers[unit] then
			castEnding[unit] = GetTime() + CAST_END_HOLD
			castHolder:Show()
		end
	end
end)

ns.SetOnUpdate(castHolder, function(self)
	-- (The mouse off the plate it was on: that plate goes back to its fade.)
	if hoverUnit and Plain(UnitIsUnit(hoverUnit, "mouseover")) ~= true then
		local was = hoverUnit
		hoverUnit = nil
		UpdatePlate(was)
	end
	local now = GetTime()
	for unit, untilWhen in pairs(castEnding) do
		if now > untilWhen or not plateLayers[unit] then
			castEnding[unit] = nil
		else
			UpdatePlate(unit)
		end
	end
	if not next(castEnding) and not hoverUnit then self:Hide() end
end)

-- Set up at login with the saved tick (the frames' Apply comes later too).
plateWatch:RegisterEvent("PLAYER_LOGIN")
plateWatch:HookScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		ns.ApplyHealVisionPlates()
	end
end)

-- /cine debug healplates: each plate it fades, its parts and how many layers
-- each, and what each kind's curve gives at full health (a plain number: 1.0
-- in, so it can be read).
function ns.HealVisionPlatesDebug()
	for _, pair in ipairs({ { "tanks", TANKS }, { "healers", HEALERS }, { "damage", OTHERS }, { "pets", PETS } }) do
		local curve = Curve(0, pair[2])
		local ok, value = false, nil
		if curve and curve.Evaluate then ok, value = pcall(curve.Evaluate, curve, 1) end
		ns.Print(("  curve %s: below %s, opacity %s, at full health gives %s"):format(pair[1],
			tostring(Setting(pair[2].below)), tostring(Setting(pair[2].alpha)),
			curve and (ok and tostring(value) or "error") or "no curve"))
	end
	local kept = {}
	for _, part in ipairs(ns.HEAL_PLATE_PARTS) do
		if ns.Setting("healVisionPlatesKeep" .. part) then kept[#kept + 1] = part end
	end
	ns.Print(("heal vision plates: tick %s, page %s, don't fade: %s"):format(tostring(ns.db and ns.db.healVisionPlates),
		tostring(ns.Setting("handleHealVision")), #kept > 0 and table.concat(kept, ", ") or "nothing"))
	-- (Plates the game locks from addons, friendly ones in dungeons and raids:
	-- listed only when asked for, and then only counted.)
	local okAll, all = pcall(C_NamePlate.GetNamePlates, true)
	local okOpen, open = pcall(C_NamePlate.GetNamePlates)
	local locked = 0
	if okAll and type(all) == "table" then
		for _, plate in ipairs(all) do
			local forbidden = Forbidden(plate)
			if Secret(forbidden) or forbidden then locked = locked + 1 end
		end
	end
	local inInstance, instanceType = IsInInstance()
	ns.Print(("  plates: %s open to addons, %s locked (in instance %s, %s)"):format(
		okOpen and type(open) == "table" and tostring(#open) or "?", okAll and tostring(locked) or "?",
		tostring(inInstance), tostring(instanceType)))
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if type(unit) == "string" then
			local okName, who = pcall(UnitName, unit)
			local kind = PlateKindOf(unit)
			local parts = {}
			for _, part in ipairs(ns.HEAL_PLATE_PARTS) do
				local count = plateParts[unit] and plateParts[unit][part]
				if count then parts[#parts + 1] = ("%s %d"):format(part, count) end
			end
			ns.Print(("  %s (%s): plate kind %s, settings %s, reachable %s, layers faded: %s"):format(
				okName and not Secret(who) and tostring(who) or "?", unit, tostring(ns.PlateKind and ns.PlateKind(unit)),
				kind == TANKS and "tanks" or kind == HEALERS and "healers" or kind == PETS and "pets"
					or kind == OTHERS and "damage" or "none",
				tostring(PlateFrame(unit) ~= nil), #parts > 0 and table.concat(parts, ", ") or "none"))
		end
	end
end
