-- Cinematic tracking detection: keeps the minimap up while gathering or
-- creature tracking is active (Keep open, Minimap page: minimapKeepGathering,
-- minimapKeepCreatures), or a prey hunt (minimapKeepPrey).
local _, ns = ...

-- Gathering and creature tracking. There's no API for what appears on the
-- minimap, but the active tracking spell can be found, so the minimap can stay
-- up while it's on. Matched by spell ID (language-independent), through the
-- player's auras and the client's tracking list, plus the active tracking icon
-- on clients that only expose that.
local TRACKING = {
	{ option = "minimapKeepGathering", spells = { 2383 }, -- Find Herbs
		icons = { 136065, "interface\\icons\\inv_misc_flower_02" } },
	{ option = "minimapKeepGathering", spells = { 2580 }, -- Find Minerals
		icons = { 136025, "interface\\icons\\spell_nature_earthquake" } },
	{ option = "minimapKeepGathering", spells = { 2481 }, -- Find Treasure
		icons = { 135725, "interface\\icons\\racial_dwarf_findtreasure" } },
	{ option = "minimapKeepCreatures", spells = { 43308 }, icons = {} }, -- Find Fish
	{ option = "minimapKeepCreatures", icons = {}, spells = {
		1494, 19878, 19879, 19880, 19882, 19883, 19884, 19885, -- hunter tracking
		5225,                                                -- druid: Track Humanoids
		5500, 5502,                                          -- Sense Demons, Sense Undead
	} },
}
local TRACKING_CHECK_INTERVAL = 0.5
local trackingCheckedAt, keepForGathering, keepForCreatures = 0, false, false

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

-- Spell IDs of tracking that's active right now, as a set (into active).
local function FillActiveTrackingSpells(active)
	-- Auras (tracking spells show as buffs)
	for i = 1, 40 do
		local name, spellID
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			-- Errors (rather than returning nil) while auras are secret.
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
			if not ok or IsSecret(aura) or not aura then break end
			name, spellID = aura.name, aura.spellId
		elseif UnitBuff then
			local _
			name, _, _, _, _, _, _, _, _, spellID = UnitBuff("player", i)
		end
		if IsSecret(name) or not name then break end
		if not IsSecret(spellID) and spellID then active[spellID] = true end
	end
	-- The client's tracking list
	if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
		for i = 1, C_Minimap.GetNumTrackingTypes() do
			local info = C_Minimap.GetTrackingInfo(i)
			if type(info) == "table" and info.active and info.spellID then
				active[info.spellID] = true
			end
		end
	end
	return active
end

local function GetActiveTrackingSpells()
	return FillActiveTrackingSpells({})
end

local function GetActiveTrackingIcon()
	local icon = GetTrackingTexture and GetTrackingTexture()
	if type(icon) == "string" then
		return icon:lower()
	end
	return icon
end

-- The active tracking, read afresh only once the player's auras or tracking
-- have changed: reading every aura (a table each) twice a second was most of
-- the addon's garbage in cities.
local activeSpells, activeIcon, trackingChanged = {}, nil, true
local changeWatcher = CreateFrame("Frame")
if not pcall(changeWatcher.RegisterUnitEvent, changeWatcher, "UNIT_AURA", "player") then
	changeWatcher:RegisterEvent("UNIT_AURA")
end
for _, event in ipairs({ "MINIMAP_UPDATE_TRACKING", "PLAYER_ENTERING_WORLD" }) do
	pcall(changeWatcher.RegisterEvent, changeWatcher, event)
end
changeWatcher:SetScript("OnEvent", function(_, event, unit)
	if event ~= "UNIT_AURA" or unit == "player" then
		trackingChanged = true
	end
end)

-- Whether tracking that's ticked under Keep open is on: gathering (herbs,
-- minerals, treasure), and creatures or fish.
local function IsTrackingSomethingWanted()
	local db = ns.GetDB()
	if trackingChanged then
		trackingChanged = false
		FillActiveTrackingSpells(wipe(activeSpells))
		activeIcon = GetActiveTrackingIcon()
	end
	local active, icon = activeSpells, activeIcon
	local gathering, creatures = false, false
	for _, kind in ipairs(TRACKING) do
		if db[kind.option] then
			local on = false
			for _, spellID in ipairs(kind.spells) do
				if active[spellID] then on = true end
			end
			for _, trackingIcon in ipairs(kind.icons) do
				if icon and icon == trackingIcon then on = true end
			end
			if on and kind.option == "minimapKeepGathering" then
				gathering = true
			elseif on then
				creatures = true
			end
		end
	end
	return gathering, creatures
end

-- Called from Frames.lua's frame update: whether to keep the minimap up for
-- gathering tracking, and for creature or fish tracking. Auras are secret in
-- combat, so the last answer is kept until it's over.
function ns.IsKeepingMinimapForTracking(now)
	if now - trackingCheckedAt >= TRACKING_CHECK_INTERVAL and not InCombatLockdown()
		and not ns.Flag(UnitAffectingCombat("player")) then
		trackingCheckedAt = now
		keepForGathering, keepForCreatures = IsTrackingSomethingWanted()
	end
	return keepForGathering, keepForCreatures
end

-- Prey hunts (retail): while you're hunting your prey, its hunt widget shows
-- (the crystal in a ring: "Your prey's location is hidden"), and the minimap
-- stays up (Keep open, Minimap page: minimapKeepPrey). Found through the
-- game's widget sets, by the widget type whose name says Prey (the enum's
-- exact name isn't known for sure), or the quest log's active prey quest
-- where the client has that call. Untested in game: /cine debug prey.
local WIDGET_SETS = { "GetTopCenterWidgetSetID", "GetPowerBarWidgetSetID", "GetBelowMinimapWidgetSetID",
	"GetObjectiveTrackerWidgetSetID" }
local PREY_CHECK_INTERVAL = 1
local function NoSet() return nil end
local preyCheckedAt, huntingPrey = -10, false

-- The widget types whose names say Prey: { [value] = name }.
local preyTypes
local function PreyWidgetTypes()
	if not preyTypes then
		preyTypes = {}
		local kinds = Enum and Enum.UIWidgetVisualizationType
		if type(kinds) == "table" then
			for name, value in pairs(kinds) do
				if type(name) == "string" and name:lower():find("prey") then preyTypes[value] = name end
			end
		end
	end
	return preyTypes
end

-- The active prey quest's ID, where the client has a call for it.
local function ActivePreyQuest()
	local call = C_QuestLog and C_QuestLog.GetActivePreyQuest
	if not call then return nil end
	local ok, questID = pcall(call)
	return ok and not IsSecret(questID) and type(questID) == "number" and questID > 0 and questID or nil
end

-- Whether the game shows a widget: its type's own info call (named after the
-- type, GetPreyHuntProgressWidgetVisualizationInfo) says shownState. A set
-- lists its widgets whether they're up or not. Unknown (no call, no answer,
-- secret): nil.
local function WidgetShown(widgetID, typeName)
	local manager = C_UIWidgetManager
	local call = manager and typeName and manager["Get" .. typeName .. "WidgetVisualizationInfo"]
	if not call then return nil end
	local ok, info = pcall(call, widgetID)
	if not ok then return nil end
	if type(info) ~= "table" then return false end
	local state = info.shownState
	if IsSecret(state) or state == nil then return nil end
	local hidden = Enum and Enum.WidgetShownState and Enum.WidgetShownState.Hidden or 0
	return state ~= hidden
end

-- The prey widget showing in one of the game's widget sets: its ID and set.
local function ShownPreyWidget()
	local manager = C_UIWidgetManager
	if not (manager and manager.GetAllWidgetsBySetID) then return nil end
	local kinds = PreyWidgetTypes()
	if not next(kinds) then return nil end
	for _, setCall in ipairs(WIDGET_SETS) do
		local okSet, setID = pcall(manager[setCall] or NoSet)
		if okSet and type(setID) == "number" and not IsSecret(setID) then
			local ok, widgets = pcall(manager.GetAllWidgetsBySetID, setID)
			if ok and type(widgets) == "table" then
				for _, widget in ipairs(widgets) do
					local kind = widget.widgetType
					-- (Shown, or can't tell: counts.)
					if not IsSecret(kind) and kinds[kind] and WidgetShown(widget.widgetID, kinds[kind]) ~= false then
						return widget.widgetID, setCall
					end
				end
			end
		end
	end
	return nil
end

-- Whether this client has prey hunts at all (the Minimap page's row is hidden
-- where it doesn't).
-- (Retail only: WoW Forever has some of the same functions but no prey hunts.)
function ns.HasPreyHunts()
	return ns.isRetail and ((C_QuestLog and C_QuestLog.GetActivePreyQuest) ~= nil or next(PreyWidgetTypes()) ~= nil)
end

-- Called from Frames.lua's frame update: hunting prey right now.
function ns.IsHuntingPrey(now)
	if now - preyCheckedAt >= PREY_CHECK_INTERVAL then
		preyCheckedAt = now
		huntingPrey = ActivePreyQuest() ~= nil or ShownPreyWidget() ~= nil
	end
	return huntingPrey
end

-- /cine debug prey: each way of telling, and what it says.
function ns.ReportPrey()
	local names = {}
	for value, name in pairs(PreyWidgetTypes()) do names[#names + 1] = ("%s=%s"):format(name, tostring(value)) end
	ns.Print(("prey widget types: %s; GetActivePreyQuest %s -> %s"):format(
		#names > 0 and table.concat(names, ", ") or "none",
		C_QuestLog and C_QuestLog.GetActivePreyQuest and "exists" or "missing", tostring(ActivePreyQuest())))
	local manager = C_UIWidgetManager
	for _, setCall in ipairs(WIDGET_SETS) do
		local okSet, setID = pcall(manager and manager[setCall] or NoSet)
		local list = {}
		if okSet and type(setID) == "number" and not IsSecret(setID) then
			local ok, widgets = pcall(manager.GetAllWidgetsBySetID, setID)
			for _, widget in ipairs(ok and type(widgets) == "table" and widgets or {}) do
				local kind = widget.widgetType
				local name = not IsSecret(kind) and PreyWidgetTypes()[kind]
				list[#list + 1] = name and ("%s(type %s, shown %s)"):format(tostring(widget.widgetID), tostring(kind),
					tostring(WidgetShown(widget.widgetID, name))) or ("%s(type %s)"):format(tostring(widget.widgetID),
					tostring(kind))
			end
		end
		ns.Print(("  %s %s: %s"):format(setCall, tostring(setID), #list > 0 and table.concat(list, ", ") or "none"))
	end
	local widgetID, setCall = ShownPreyWidget()
	ns.Print(("hunting prey: %s (widget %s in %s); Keep open while hunting: %s, in combat %s"):format(
		tostring(ActivePreyQuest() ~= nil or widgetID ~= nil), tostring(widgetID), tostring(setCall),
		tostring(ns.db.minimapKeepPrey), tostring(ns.Flag(UnitAffectingCombat("player")))))
end

ns.GetActiveTrackingSpells = GetActiveTrackingSpells
ns.GetActiveTrackingIcon = GetActiveTrackingIcon
ns.IsTrackingSomethingWanted = IsTrackingSomethingWanted
