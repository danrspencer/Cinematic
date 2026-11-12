-- Cinematic: EllesmereUI, a whole-UI suite: one addon per part, each set up
-- only once it has loaded. It swaps the game's unit frames, action bars and
-- the like for its own, which fade with the frames they stand in for and
-- follow the same rows on the Standard Frames page. Its parts with no game
-- frame to follow get rows of their own on the Advanced Frames page.
--
-- It sets its frames' alpha all the time (target changes, combat, mouseover):
-- its own frames are hooked, and game frames it sets are checked every frame.
local _, ns = ...
local L = ns.L

-- A frame by its Unlock Mode entry, which hands it out: most of its parts'
-- frames have no name.
local function UnlockFrame(key)
	local eui = _G.EllesmereUI
	local elems = type(eui) == "table" and eui._unlockRegisteredElements
	local elem = type(elems) == "table" and elems[key]
	if type(elem) ~= "table" or type(elem.getFrame) ~= "function" then
		return nil
	end
	local ok, frame = pcall(elem.getFrame)
	return ok and type(frame) == "table" and frame or nil
end

-- A row's match (it's asked about each unnamed frame): whether the frame is
-- one of these entries'. Looked up once per scan.
local function MatchUnlockFrames(keys)
	local frames, lookedAt = {}, nil
	return function(frame)
		local now = GetTime()
		if lookedAt ~= now then
			lookedAt = now
			wipe(frames)
			for _, key in ipairs(keys) do
				local found = UnlockFrame(key)
				if found then
					frames[found] = true
				end
			end
		end
		return frames[frame] or false
	end
end

-- Advanced Frames rows: one frame (or one kind of numbered frame) each.
-- (from: the row that held it with others till 2026-11-12, whose settings it
-- starts with: ns.SplitAddonRows. bar: a bar row for the built-in profiles'
-- modules.)
local rows = {}
for i, bar in ipairs({ 6, 7, 8, 9, 10 }) do
	rows[#rows + 1] = {
		key = "euiBar" .. bar, from = "euiBars", addon = "EllesmereUIActionBars", bar = true,
		label = "EllesmereUI Action Bar " .. bar, short = "EllesmereUI bar " .. bar,
		about = L["its action bar %d"]:format(bar),
		note = i == 1 and L["Its bars 1-5, pet, stance and XP bars are rows on the Game Frames page, " ..
			"with its unit frames and quest tracker."] or nil,
		names = { "EABBar_Bar" .. bar },
	}
end
-- (Its QoL displays, a row each: name, label.)
local QOL = {
	{ "EUI_SecondaryStats", "Secondary Stats", "its secondary stats display" },
	{ "EUI_FPSCounter", "FPS Counter", "its FPS counter" },
	{ "EllesmereUIBattleResIcon", "Battle Res", "its battle res display" },
	{ "EllesmereUIBloodlustIcon", "Bloodlust", "its Bloodlust display" },
	{ "EUI_MovementAlertFrame", "Movement Alert", "its movement alert" },
	{ "EUI_TimeSpiralFrame", "Time Spiral", "its Time Spiral display" },
	{ "EUI_GatewayShardFrame", "Gateway Shard", "its Gateway Shard display" },
	{ "EUI_CharacterCrosshair", "Crosshair", "its crosshair" },
}
for _, entry in ipairs(QOL) do
	rows[#rows + 1] = {
		key = "eui" .. entry[2]:gsub("%s", ""), from = "euiQoL", addon = "EllesmereUIQoL",
		label = "EllesmereUI " .. entry[2], short = "EllesmereUI " .. entry[2]:lower(),
		about = L[entry[3]],
		names = { entry[1] },
	}
end
-- (Its buff reminders' anchors, a row each: name, label.)
for _, entry in ipairs({
	{ "EABR_Anchor", "Buff Reminders" }, { "EABR_CombatAnchor", "Combat Reminders" },
	{ "EABR_TalentAnchor", "Talent Reminders" }, { "EABR_BeaconAnchor", "Beacon Reminders" },
	{ "EABR_CursorAnchor", "Cursor Reminders" },
}) do
	rows[#rows + 1] = {
		key = "eui" .. entry[2]:gsub("%s", ""), from = "euiReminders", addon = "EllesmereUIAuraBuffReminders",
		label = "EllesmereUI " .. entry[2], short = "EllesmereUI " .. entry[2]:lower(),
		about = L["its missing-buff reminders"],
		names = { entry[1] },
	}
end
for _, known in ipairs(rows) do
	known.suite, known.hookAlpha = "EllesmereUI", true
	table.insert(ns.ADDON_FRAMES, known)
end

for _, known in ipairs({
	{
		key = "euiCooldowns", addon = "EllesmereUICooldownManager", bar = true,
		label = "EllesmereUI Cooldown Manager", short = "EllesmereUI cooldowns",
		about = L["its cooldown bars"],
		patterns = { "^ECME_CDMBar_" },
	},
	{
		key = "euiResourceBars", from = "euiResource", addon = "EllesmereUIResourceBars",
		label = "EllesmereUI Resource Bars", short = "EllesmereUI resource bars",
		about = L["its health and power bars"],
		note = L["Its cast bar isn't faded, like the game's. Its swing timer is the Swing timer row on " ..
			"the Game Frames page."],
		names = { "EllesmereUIResourceBarsFrame" },
	},
	{
		key = "euiTotemBar", from = "euiResource", addon = "EllesmereUIResourceBars",
		label = "EllesmereUI Totem Bar", short = "EllesmereUI totem bar",
		about = L["its totem bar"],
		names = { "ERB_TotemBarFrame" },
	},
	{
		key = "euiCallTotemBar", from = "euiResource", addon = "EllesmereUIResourceBars",
		label = "EllesmereUI Call Totem Bar", short = "EllesmereUI call totem bar",
		about = L["its call totem bar"],
		names = { "ERB_CallTotemBarFrame" },
	},
	{
		key = "euiMeters", addon = "EllesmereUIDamageMeters",
		label = "EllesmereUI Damage Meters", short = "EllesmereUI meters",
		about = L["its meter windows"],
		patterns = { "^EllesmereUIDMFrame%d+$" },
	},
	{
		key = "euiDataBars", addon = "EllesmereUIDataBars", bar = true,
		label = "EllesmereUI Data Bars", short = "EllesmereUI data bars",
		about = L["its data bars"],
		patterns = { "^EllesmereUIDataBarsBar%d+$" },
	},
	{
		-- (Unnamed and not taking the mouse, so /cine add can't find it.)
		key = "euiDistance", addon = "EllesmereUIQoL",
		label = "EllesmereUI Target Distance", short = "EllesmereUI distance",
		about = L["its target distance (range) text"],
		match = MatchUnlockFrames({ "EUI_TargetDistance" }),
	},
	{
		key = "euiCombatText", addon = "EllesmereUIQoL",
		label = "EllesmereUI Self Combat Text", short = "EllesmereUI combat text",
		about = L["its combat text over your character"],
		match = MatchUnlockFrames({ "EUI_SelfCombatText" }),
	},
	-- Forever Essentials' parts, a row each. (bar: rows the built-in profiles'
	-- modules count as bars, as the row they come from was.)
	{
		key = "euiThreatMeter", from = "euiEssentials", addon = "EllesmereUIForeverEssentials", bar = true,
		label = "EllesmereUI Threat Meter", short = "EllesmereUI threat meter",
		about = L["its threat meter"],
		names = { "EllesmereUIThreatMeterFrame" },
	},
	{
		key = "euiJunkList", from = "euiEssentials", addon = "EllesmereUIForeverEssentials", bar = true,
		label = "EllesmereUI Junk List", short = "EllesmereUI junk list",
		about = L["its junk list"],
		names = { "EllesmereUIJunkList" },
	},
	{
		-- (Unnamed: found by its Unlock Mode entry.)
		key = "euiFlightTimer", from = "euiEssentials", addon = "EllesmereUIForeverEssentials", bar = true,
		label = "EllesmereUI Flight Timer", short = "EllesmereUI flight timer",
		about = L["its flight timer"],
		match = MatchUnlockFrames({ "EUI_FlightTimer" }),
	},
	{
		key = "euiLootFeed", from = "euiEssentials", addon = "EllesmereUIForeverEssentials", bar = true,
		label = "EllesmereUI Loot Feed", short = "EllesmereUI loot feed",
		about = L["its loot feed"],
		match = MatchUnlockFrames({ "EUI_LootFeed" }),
	},
}) do
	known.suite, known.hookAlpha = "EllesmereUI", true
	table.insert(ns.ADDON_FRAMES, known)
end

-- Its unit frames have no row here: they follow the game's on the Game Frames
-- page. A note says so, so they're not looked for on this page.
table.insert(ns.ADDON_NOTES, {
	addon = "EllesmereUIUnitFrames", label = "Unit Frames",
	works = L["Follow the Game Frames page's rows"],
	about = L["Its player, target, target of target and focus frames fade with the Player frame, Target, " ..
		"Target of target and Focus rows on the Game Frames page, its party frames with Party frames and its " ..
		"raid frames with Players. " ..
		"Set when they come back, or tick Always, there. Hover Find leaves them out and says which row."],
})

-- The core: its visibility pass sets its frames' alpha (and some of the
-- game's) a frame after target changes and the like. Fade them again
-- straight after, from its own list of visibility updates (kept last in it:
-- its parts may add theirs later), and check every frame for the rest.
ns.WhenAddonLoads("EllesmereUI", function()
	ns.syncEveryFrame = true
	ns.FollowOwnAlpha({ "MicroMenuContainer", "BagsBar", "Minimap", "ObjectiveTrackerFrame" })
	-- (Its cooldown manager sets the game's cooldown viewers' alpha, which
	-- can't be hooked, from a second list run after the first: joined once,
	-- at the first scan, after its parts have joined. It can't be left.)
	local eui = _G.EllesmereUI
	if type(eui) ~= "table" then
		return
	end
	local followingVisEdges = false
	ns.AddScanner(function()
		if type(eui.RegisterVisibilityUpdater) == "function"
			and type(eui.UnregisterVisibilityUpdater) == "function" then
			eui.UnregisterVisibilityUpdater(ns.SyncOwnAlphas)
			eui.RegisterVisibilityUpdater(ns.SyncOwnAlphas)
		end
		if not followingVisEdges and type(eui.RegisterVisEdge) == "function" then
			followingVisEdges = true
			eui.RegisterVisEdge(ns.SyncOwnAlphas)
		end
	end)
end)

ns.WhenAddonLoads("EllesmereUIUnitFrames", function()
	ns.FadeWithRows({
		{ "player", "player", "EllesmereUIUnitFrames_Player", "EllesmereUIUnitFrames_Pet" },
		{ "target", "target", "EllesmereUIUnitFrames_Target" },
		{ "tot", "target", "EllesmereUIUnitFrames_TargetTarget" },
		{ "focus", "target", "EllesmereUIUnitFrames_Focus", "EllesmereUIUnitFrames_FocusTarget" },
		{ "buffs", "buffs", "EllesmereUIPlayerAuraBars_Buffs", "EllesmereUIPlayerAuraBars_Debuffs" },
	})
	ns.AddPortraitFrame("EllesmereUIUnitFrames_Player")
end)

ns.WhenAddonLoads("EllesmereUIActionBars", function()
	ns.FadeWithRows({
		{ "mainbar", "bars", "EABBar_MainBar" },
		{ "bottomleft", "bars", "EABBar_Bar2" },
		{ "bottomright", "bars", "EABBar_Bar3" },
		{ "right1", "sidebars", "EABBar_Bar4" },
		{ "right2", "sidebars", "EABBar_Bar5" },
		{ "pet", "bars", "EABBar_PetBar" },
		{ "stance", "bars", "EABBar_StanceBar" },
		{ "xp", "bars", "EllesmereEAB_XPBar", "EllesmereEAB_RepBar", "EllesmereEAB_FavorBar" },
	})
	-- It keeps retail's main bar at alpha 0.
	ns.LeaveAlone({ "MainActionBar" })
end)

-- Its frames standing in for the game's, linked as those parts (Addon Frame
-- Links: FrameLinks.lua), by its addon -> part -> its frame's name. Looked
-- up with each scan till found: most are made after loading.
local LINKS = {
	EllesmereUIUnitFrames = {
		unitplayer = "EllesmereUIUnitFrames_Player", unitpet = "EllesmereUIUnitFrames_Pet",
		unittarget = "EllesmereUIUnitFrames_Target", unittot = "EllesmereUIUnitFrames_TargetTarget",
		unitfocus = "EllesmereUIUnitFrames_Focus", unitfocustot = "EllesmereUIUnitFrames_FocusTarget",
		aurabuffs = "EllesmereUIPlayerAuraBars_Buffs", auradebuffs = "EllesmereUIPlayerAuraBars_Debuffs",
	},
	EllesmereUIMinimap = { mapzone = "_EBS_LocationBg", mapclock = "_EBS_ClockBg", mapcoords = "_EBS_CoordFrame" },
	EllesmereUICooldownManager = {
		cdessential = "ECME_CDMBar_cooldowns", cdutility = "ECME_CDMBar_utility", cdbuffs = "ECME_CDMBar_buffs",
	},
	EllesmereUIResourceBars = { prdbars = "EllesmereUIResourceBarsFrame", swingbars = "ERB_SwingTimerFrame" },
}
for addon, parts in pairs(LINKS) do
	ns.WhenAddonLoads(addon, function()
		ns.AddScanner(function()
			for part, name in pairs(parts) do
				local frame = _G[name]
				if type(frame) == "table" and type(frame.GetObjectType) == "function"
					and not (frame.IsForbidden and frame:IsForbidden()) then
					ns.ClaimLinkPart("EllesmereUI", part, frame)
				end
			end
		end)
	end)
end

-- Its raid and party frames fade with the game's on the Standard Frames page:
-- the raid ones (with its healer mana, boss and extra frames) as Players, the
-- party ones (unnamed) as Party frames.
ns.WhenAddonLoads("EllesmereUIRaidFrames", function()
	ns.FadeFoundByName("raidplayers", {
		"EllesmereUIRaidFrameContainer", "ERF_HealerMana", "ERFExtraFramesContainer", "ERFFriendlyBossContainer",
	})
	ns.AddScanner(function()
		local party = UnlockFrame("RF_PartyFrames")
		if party and not ns.IsFaded(party) then
			ns.AddFoundFrame(party, "party", true, true)
		end
	end)
end)

-- Its nameplates are its own frames on the game's plates (its plate, or the
-- name over a friendly NPC), beside the game's unit frame, which it keeps at
-- alpha 0. The fade only reached that unit frame, so its plates popped up and
-- went at full as plates were switched on and off. Its frames on a plate fade
-- with it, as Plater's do: its alpha (target and range fading) times ours,
-- hooked (ns.SetPlateFrameAlpha). They're pooled and move from plate to plate: one moved takes the
-- alpha of the plate it lands on.
do
	local pieces = setmetatable({}, { __mode = "k" }) -- [game plate] = its frames on it (and how many children it had)
	local hooked = setmetatable({}, { __mode = "k" })
	local LABEL = "EllesmereUI plate SetAlpha hook"

	local function HookPiece(frame)
		if hooked[frame] then
			return
		end
		hooked[frame] = true
		ns.HookPlateFrame(frame, LABEL)
		hooksecurefunc(frame, "SetParent", function(self, parent)
			local unitFrame = type(parent) == "table" and not (parent.IsForbidden and parent:IsForbidden())
				and parent.UnitFrame
			ns.SetPlateFrameAlpha(self, type(unitFrame) == "table" and unitFrame.cinematicAlpha or nil, LABEL)
		end)
	end

	-- Its frames on a plate: the plate's unnamed children but the game's own
	-- (the widgets and interact prompt it moves off the unit frame). Game
	-- frames' methods aren't hooked: that breaks the game's calls to them.
	-- Looked for again when the plate's number of children changes.
	local function Pieces(plate)
		local count = plate:GetNumChildren()
		local list = pieces[plate]
		if list and list.count == count then
			return list
		end
		list = { count = count }
		local unitFrame = plate.UnitFrame
		for _, child in ipairs({ plate:GetChildren() }) do
			if child ~= unitFrame and not child:GetName() and not (unitFrame and (child == unitFrame.WidgetContainer
				or child == unitFrame.SoftTargetFrame)) and not (child.IsForbidden and child:IsForbidden()) then
				HookPiece(child)
				list[#list + 1] = child
			end
		end
		pieces[plate] = list
		return list
	end

	local function SetPlateAlpha(plate, alpha)
		for _, frame in ipairs(Pieces(plate)) do
			if frame:GetParent() == plate then
				ns.SetPlateFrameAlpha(frame, alpha, LABEL)
			end
		end
	end

	ns.WhenAddonLoads("EllesmereUINameplates", function()
		ns.AddPlateAlpha(SetPlateAlpha)
		-- A new plate's frames are put on it in its own handler, which runs
		-- after ours (Core: NAME_PLATE_UNIT_ADDED): give them the plate's
		-- alpha straight after, before they're drawn. That handler also sets
		-- the game's unit frame of a friendly plate to 1 if it's below 0.01
		-- (ours, faded): put ours back too, or the name flashed up for a
		-- frame on every plate coming into view (turning the camera round in
		-- a city).
		ns.AfterPlateAdded(function(plate)
			local unitFrame = plate.UnitFrame
			if unitFrame then
				SetPlateAlpha(plate, unitFrame.cinematicAlpha)
				if unitFrame.cinematicAlpha then
					unitFrame:SetAlpha(unitFrame.cinematicAlpha)
				end
			end
		end)
	end)
end

-- Its quest tracker: the game's skinned (with a background of its own), or
-- on WoW Forever its Custom Quest Tracker, a tracker of its own in place of
-- the game's (which it keeps at alpha 0). Its item buttons sit in a layer
-- outside it that takes its alpha, so they fade with it. Linked as the
-- Quest tracker's tracker (Quest Tracker page's Addon Frame Links).
-- The Quest Tracker page's "Show just that quest" and "Close the gaps" on its
-- custom tracker (ns.AddQuestFocusTracker). Its rows are pooled Buttons in
-- its scroll frame's child, each with its kind ("zone", "quest", "obj"), id
-- (a quest's rows: the quest ID) and the spot it put it at (lastX, lastY,
-- under the child's top). The quests a reveal shows stay; the rest of the
-- rows, the zone names, its header, background and scroll bar fade. Closing
-- the gaps moves those quests' rows up under the first row, quest under
-- quest, and puts them back at their own spots after (it sets a row's spot
-- again only when its own changes). Its item buttons (secure, in a layer of
-- their own, by screen position) aren't moved: a moved quest's button fades
-- for the while, as the game tracker's copies do; the others' with the rest.
local customItemLayer -- (found by the scan: the layer holding its item buttons)
do
	local QUEST_GAP = 6 -- between quests moved up (its units)
	local moved = {} -- [row] = true while not at its own spot
	local wanted, shifted, place = {}, {}, {} -- (kept, refilled each tick)
	local function ScrollChild(tracker)
		for _, part in ipairs({ tracker:GetChildren() }) do
			if part:GetObjectType() == "ScrollFrame" and part.GetScrollChild then
				return part, part:GetScrollChild()
			end
		end
	end
	local function ByY(a, b) return a.lastY < b.lastY end
	local function Put(row, y)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", row.lastX or 0, -y)
	end
	local function Apply(othersAlpha, quests, timers, active)
		local tracker = _G.EUI_CustomQuestTracker
		if type(tracker) ~= "table" or not tracker.GetChildren then return false end
		local scroll, child = ScrollChild(tracker)
		if not child then return false end
		for _, part in ipairs({ tracker:GetChildren() }) do
			if part ~= scroll then ns.FadeRelative(part, othersAlpha) end
		end
		wipe(wanted)
		wipe(shifted)
		local found, top = false, nil
		for _, row in ipairs({ child:GetChildren() }) do
			if type(row.lastY) == "number" and row:IsShown() then
				local want = (row.kind == "quest" or row.kind == "obj")
					and (quests[row.id] or (timers and timers[row.id])) and true or false
				ns.FadeRelative(row, want and 1 or othersAlpha)
				if want then
					found = true
					wanted[#wanted + 1] = row
				end
				if not top or row.lastY < top then top = row.lastY end
			end
		end
		-- Close the gaps: only while just those quests are wanted.
		local collapse = active and ns.db.questRevealOnlyThat and ns.db.questRevealCollapse and #wanted > 0
		wipe(place)
		if collapse then
			table.sort(wanted, ByY)
			-- (A quest's focus ring, left of its title, rises above it: its
			-- tracker starts the first quest that far down, or the clip cuts
			-- the ring off. The same here: its button is 6 over the title's
			-- font, sits 3 higher, and its art reaches half its size above.)
			local ring = wanted[1].focus
			if ring and ring:IsShown() then
				top = math.max(top, math.ceil(3 + ring:GetHeight() * 0.5))
			end
			local cursor, offset, lastID, bottom = top, 0, nil, nil
			for _, row in ipairs(wanted) do
				if row.id ~= lastID then
					if bottom then cursor = bottom + QUEST_GAP end
					offset = cursor - row.lastY
					lastID = row.id
				end
				local y = row.lastY + offset
				local height = row:GetHeight()
				bottom = math.max(bottom or 0, y + (type(height) == "number" and height or 0))
				if offset < -0.5 then
					place[row] = y
					shifted[row.id] = true
				end
			end
		end
		for row in pairs(moved) do
			if not place[row] then
				Put(row, row.lastY)
				moved[row] = nil
			end
		end
		for row, y in pairs(place) do
			Put(row, y)
			moved[row] = true
		end
		-- Its item buttons, by their quest.
		if customItemLayer then
			for _, button in ipairs({ customItemLayer:GetChildren() }) do
				if button.questID then
					local want = quests[button.questID] or (timers and timers[button.questID])
					ns.FadeRelative(button, want and (shifted[button.questID] and 0 or 1) or othersAlpha)
				end
			end
		end
		ns.questFocusOthersUp = othersAlpha < 1 or next(moved) ~= nil or next(shifted) ~= nil
		return found
	end
	ns.WhenAddonLoads("EllesmereUIQuestTracker", function()
		ns.AddQuestFocusTracker(Apply, "EllesmereUI")
	end)
end

ns.WhenAddonLoads("EllesmereUIQuestTracker", function()
	ns.FadeWithRows({ { "quests", "quests", "EllesmereUIQTBackground", "EUI_CustomQuestTracker" } })
	ns.AddScanner(function()
		local tracker = _G.EUI_CustomQuestTracker
		if type(tracker) == "table" and type(tracker.GetObjectType) == "function" then
			ns.ClaimLinkPart("EllesmereUI", "questtracker", tracker)
			-- (Its item buttons' layer: on UIParent, unnamed, holding buttons
			-- that each know their quest and have a cooldown.)
			if not customItemLayer then
				-- (Forbidden frames first: even asking one its name errors.)
				for _, layer in ipairs({ UIParent:GetChildren() }) do
					if not (layer.IsForbidden and layer:IsForbidden()) and not layer:GetName() then
						local first = select(1, layer:GetChildren())
						if type(first) == "table" and not (first.IsForbidden and first:IsForbidden())
							and first.questID ~= nil and first.cd then
							customItemLayer = layer
							break
						end
					end
				end
			end
		end
	end)
end)

ns.WhenAddonLoads("EllesmereUIResourceBars", function()
	ns.FadeWithRows({ { "swing", "swing", "ERB_SwingTimerFrame" } })
end)

-- It moves the map out of the cluster and keeps the cluster at alpha 0, and
-- the calendar too (the tracking button and day/night dial, in the cluster,
-- go with it): it draws its own.
-- Its zone name bar is sized to the name, measured only when the name
-- changes: measured while the map is shrunk away (faded), the text reads far
-- too wide (it's never drawn smaller than a few pixels), and the bar stays
-- the width of the screen. So measure it again once the map has its size
-- back, the way it does (a frame later, once the text has its size again).
local function RefitLocationBar()
	local bar = _G._EBS_LocationBg
	if type(bar) ~= "table" or type(bar.GetRegions) ~= "function" then
		return
	end
	for _, region in ipairs({ bar:GetRegions() }) do
		if region:GetObjectType() == "FontString" then
			local width = region:GetStringWidth()
			if type(width) == "number" and width > 0 then
				bar:SetSize(width + 20, 18)
			end
			return
		end
	end
end

ns.WhenAddonLoads("EllesmereUIMinimap", function()
	ns.LeaveAlone({ "MinimapCluster", "GameTimeFrame" })
	ns.OnMinimapRestored(function()
		RefitLocationBar()
		C_Timer.After(0, RefitLocationBar)
	end)
end)

-- Its chat draws its panel, sidebar, border and tab strip in its own unnamed
-- frames on UIParent, so they don't fade with the chat frames. The panel and
-- sidebar are found through its per-chat-frame data; the rest by what
-- they're anchored to (those parts, or the tab dock).
local function IsUsable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and type(frame.SetAlpha) == "function" and not (frame.IsForbidden and frame:IsForbidden())
end

local function IsAnchoredTo(frame, targets)
	for i = 1, frame:GetNumPoints() do
		local ok, _, relativeTo = pcall(frame.GetPoint, frame, i)
		if ok and relativeTo and targets[relativeTo] then
			return true
		end
	end
	return false
end

local function FindChat()
	local chatData = _G.EllesmereUI and _G.EllesmereUI._chatCFD
	if type(chatData) ~= "function" then
		return
	end
	local parts = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local chatFrame = _G["ChatFrame" .. i]
		local ok, data = false, nil
		if chatFrame then
			ok, data = pcall(chatData, chatFrame)
		end
		if ok and type(data) == "table" then
			-- (Its panel draws the window's lines, not the chat frame: linked
			-- as the window's panel, a message peeking the window brings it up,
			-- its backdrop as the Chat page's Background says: FrameLinks.lua.
			-- The backdrop: the panel's own textures, and on WoW Forever the
			-- bronze boxes it builds on it. Its message frame is a child.)
			if IsUsable(data.bg) then
				local backdrop = {}
				for _, region in ipairs({ data.bg:GetRegions() }) do
					if region.GetObjectType and region:GetObjectType() == "Texture" then
						backdrop[#backdrop + 1] = region
					end
				end
				if IsUsable(data.fvHost) then backdrop[#backdrop + 1] = data.fvHost end
				ns.ClaimLinkPart("EllesmereUI", "chatwindow", data.bg, { window = chatFrame, backdrop = backdrop })
			end
			for _, key in ipairs({ "bg", "sidebar", "scrollBtn" }) do
				if IsUsable(data[key]) then
					parts[data[key]] = true
					ns.AddFoundFrame(data[key], "chat", true, true)
					if key ~= "bg" then ns.ClaimLinkPart("EllesmereUI", "chatbuttons", data[key]) end
				end
			end
		end
	end
	if not next(parts) then
		return
	end
	local dock = _G.GeneralDockManager
	if dock then
		parts[dock] = true
	end
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if IsUsable(frame) and not frame:GetName() and IsAnchoredTo(frame, parts) then
			if not ns.IsFaded(frame) then
				ns.AddFoundFrame(frame, "chat", true, true)
			end
			-- (Its tab strip lies over the dock, anchored to it.)
			if dock and IsAnchoredTo(frame, { [dock] = true }) then
				ns.ClaimLinkPart("EllesmereUI", "chattabs", frame)
			end
		end
	end
end

ns.WhenAddonLoads("EllesmereUIChat", function()
	ns.AddScanner(FindChat)
end)
