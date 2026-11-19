-- Cinematic: DaylightUI, a whole-UI suite: a core (DaylightUI) and one addon
-- per part. It swaps the game's unit frames, action bars, buffs, chat and the
-- like for its own, which fade with the frames they stand in for and follow
-- the same rows on the Standard Frames page. Its parts with no game frame to
-- follow get rows of their own on the Advanced Frames page.
--
-- Its core has one fade engine for all its parts: each part registers its
-- areas (DaylightUI.Fade.Register: a key and a function handing out the
-- area's frames, many of them unnamed), and from then on that engine sets
-- their alpha. Those areas are what's faded here, found through that same
-- list. Its own frames are hooked; the game's frames it sets (the chat
-- frames, the quest tracker, the micro menu) are followed.
local ADDON_NAME, ns = ...
local L = ns.L

-- Advanced Frames rows: one frame each. (from: the row that held it with
-- others till 2026-11-12, whose settings it starts with: ns.SplitAddonRows.)
for _, known in ipairs({
	{
		key = "dlMeter1", from = "dlMeters", addon = "DaylightUI_InfoPanel",
		label = "DaylightUI damage meter 1", short = "DaylightUI meter 1",
		about = L["its first damage meter window"],
		names = { "DaylightUIDamageMeter" },
	},
	-- (Its second meter became the first of the windows you add, 1.9: any
	-- number, meters, threat and summaries, each DaylightUIMeterWindow_<id>.
	-- One row for all of them, as for Details' windows; key kept, so the
	-- second meter's settings carry over.)
	{
		key = "dlMeter2", from = "dlMeters", addon = "DaylightUI_InfoPanel",
		label = "DaylightUI meter windows", short = "DaylightUI windows",
		about = L["the meter windows you add to it"],
		patterns = { "^DaylightUIMeterWindow_" },
	},
	{
		key = "dlThreat", addon = "DaylightUI_InfoPanel",
		label = "DaylightUI threat meter", short = "DaylightUI threat",
		about = L["its threat meter window"],
		names = { "DaylightUIThreatMeterFrame" },
	},
	{
		key = "dlFlightTimer", from = "dlQoL", addon = "DaylightUI_QoL",
		label = "DaylightUI flight timer", short = "DaylightUI flight timer",
		about = L["its flight timer"],
		names = { "DaylightUIFlightTimer" },
	},
	{
		key = "dlLootFeed", from = "dlQoL", addon = "DaylightUI_QoL",
		label = "DaylightUI loot feed", short = "DaylightUI loot feed",
		about = L["its loot feed"],
		names = { "DaylightUILootFeed" },
	},
	{
		key = "dlReminder", addon = "DaylightUI_Buffs",
		label = "DaylightUI buff reminder", short = "DaylightUI reminder",
		about = L["its missing-buff reminder"],
		names = { "DaylightUIBuffReminderHolder" },
	},
	{
		key = "dlPull", addon = "DaylightUI_UnitFrames",
		label = "DaylightUI pull timer", short = "DaylightUI pull",
		about = L["its pull timer"],
		note = L["Its cast bar isn't faded, like the game's."],
		names = { "DaylightUIPullTimer" },
	},
	{
		key = "dlQuestArrow", from = "dlQuestNav", addon = "DaylightUI_Quests",
		label = "DaylightUI quest arrow", short = "DaylightUI arrow",
		about = L["its quest arrow"],
		names = { "DaylightUIQuestArrow" },
	},
	{
		key = "dlQuestMarker", from = "dlQuestNav", addon = "DaylightUI_Quests",
		label = "DaylightUI quest marker", short = "DaylightUI marker",
		about = L["its quest marker"],
		names = { "DaylightUIQuestMarker" },
	},
	{
		key = "dlQuestProgress", addon = "DaylightUI_Quests",
		label = "DaylightUI quest progress", short = "DaylightUI progress",
		about = L["its quest progress lines over the world"],
		names = { "DaylightUIQuestProgress" },
	},
	{
		key = "dlDataBar", addon = "DaylightUI_InfoPanel",
		label = "DaylightUI data bar", short = "DaylightUI data bar",
		about = L["its data bar along the bottom of the screen"],
		names = { "DaylightUIDataBar" },
	},
	{
		key = "dlCursorRing", addon = "DaylightUI_QoL",
		label = "DaylightUI cursor ring", short = "DaylightUI cursor ring",
		about = L["its ring around the mouse cursor"],
		names = { "DaylightUICursorRing" },
	},
	{
		key = "dlLeaderTab", addon = "DaylightUI_UnitFrames",
		label = "DaylightUI leader tab", short = "DaylightUI leader",
		about = L["its group leader tab on the left edge of the screen"],
		names = { "DaylightUILeaderTab" },
	},
}) do
	known.suite, known.hookAlpha = "DaylightUI", true
	table.insert(ns.ADDON_FRAMES, known)
end

-- (Frames those rows fade, by name or pattern: left out of the areas below.)
local OWN_ROWS, OWN_PATTERNS = {}, {}
for _, known in ipairs(ns.ADDON_FRAMES) do
	if known.suite == "DaylightUI" then
		for _, name in ipairs(known.names or {}) do
			OWN_ROWS[name] = true
		end
		for _, pattern in ipairs(known.patterns or {}) do
			OWN_PATTERNS[#OWN_PATTERNS + 1] = pattern
		end
	end
end
local function OwnRow(name)
	if OWN_ROWS[name] then return true end
	for _, pattern in ipairs(OWN_PATTERNS) do
		if name:find(pattern) then return true end
	end
	return false
end

-- Its fade areas by Standard Frames row: the row and the fade group. Bars
-- 1-8 aren't here: their holders have no name (so no row of their own), so
-- their buttons, named, fade instead (below).
local AREAS = {
	["UnitFrames.player"] = { "player", "player" },
	["UnitFrames.pet"] = { "petframe", "player" },
	["UnitFrames.target"] = { "target", "target" },
	["UnitFrames.targettarget"] = { "tot", "target" },
	["UnitFrames.focus"] = { "focus", "target" },
	["UnitFrames.focustarget"] = { "focustot", "target" },
	["UnitFrames.party"] = { "party", "party" },
	["UnitFrames.raid"] = { "raidplayers", "raidplayers" },
	-- (Its bars at your feet, and the battleground's enemy flag carriers.)
	["UnitFrames.personal"] = { "prd", "prd" },
	["UnitFrames.arena"] = { "flags", "flags" },
	-- (Its Cooldown Manager layout.)
	["ActionBars.cdm"] = { "cooldowns", "cooldowns" },
	["Chat.side"] = { "chat", "chat" },
	["InfoPanel.xp"] = { "xp", "bars" },
	["Buffs.buffs"] = { "buffs", "buffs" },
	["Buffs.debuffs"] = { "buffs", "buffs" },
	["ActionBars.stance"] = { "stance", "bars" },
	["ActionBars.pet"] = { "pet", "bars" },
	["ActionBars.possess"] = { "mainbar", "bars" },
	["ActionBars.totem"] = { "totems", "totems" },
	["ActionBars.totemTimers"] = { "totems", "totems" },
	["ActionBars.bagBar"] = { _G.BagsBar and "bags" or "micro", "bars" },
	["ActionBars.microMenu"] = { "micro", "bars" },
	["Chat.chat"] = { "chat", "chat" },
	-- (The info panel holds the minimap, its XP bar and the meters.)
	["InfoPanel.panel"] = { "minimap", "minimap" },
	["InfoPanel.tracker"] = { "quests", "quests" },
	["Quests.tracker"] = { "quests", "quests" },
}

-- Its bars 1-8, by the game's bar each stands in for (Standard Frames row,
-- fade group).
local BARS = {
	{ "mainbar", "bars" }, { "bottomleft", "bars" }, { "bottomright", "bars" }, { "right1", "sidebars" },
	{ "right2", "sidebars" }, { "bar6", "bars" }, { "bar7", "bars" }, { "bar8", "bars" },
}

local areas = {} -- key -> its frames function, as each part registers it
local named = {} -- frame name -> true once given its row

local function Own(name)
	return name:find("^DaylightUI") ~= nil
end

-- An area's frame: its own by name with the row (hooked), unnamed ones as
-- found, and the game's (already faded with their own rows) followed.
local function AddAreaFrame(frame, row, group)
	if type(frame) ~= "table" or type(frame.GetName) ~= "function" or (frame.IsForbidden and frame:IsForbidden()) then
		return
	end
	local name = frame:GetName()
	if name and OwnRow(name) then
		return
	elseif name then
		if not named[name] then
			named[name] = true
			if Own(name) then
				ns.FadeWithRow(row, group, { name }, true, true)
			else
				ns.FollowOwnAlpha({ name })
			end
		end
	elseif not ns.IsFaded(frame) then
		ns.AddFoundFrame(frame, group, true, true)
	end
end

local function ScanAreas()
	for key, frames in pairs(areas) do
		local spot = AREAS[key]
		local ok, list = pcall(frames)
		if spot and ok and type(list) == "table" then
			for _, frame in ipairs(list) do
				AddAreaFrame(frame, spot[1], spot[2])
			end
		end
	end
end

ns.WhenAddonLoads("DaylightUI", function()
	local fade = _G.DaylightUI and _G.DaylightUI.Fade
	if type(fade) ~= "table" or type(fade.Register) ~= "function" then
		return
	end
	-- (Its parts register as they're enabled, at login: after this.)
	hooksecurefunc(fade, "Register", function(def)
		if type(def) == "table" and type(def.key) == "string" and type(def.frames) == "function" then
			areas[def.key] = def.frames
		end
	end)
	ns.AddScanner(ScanAreas)
	-- Its quest tracker sets its item buttons' holder (screen-sized) to the
	-- tracker's alpha by hand.
	ns.FadeWithRow("quests", "quests", { "DaylightUIQuestItems" }, true, true)
end)

ns.WhenAddonLoads("DaylightUI_ActionBars", function()
	local rows = {}
	for num, bar in ipairs(BARS) do
		local row = { bar[1], bar[2] }
		for i = 1, 12 do
			row[i + 2] = "DaylightUIBar" .. num .. "Button" .. i
		end
		rows[num] = row
	end
	ns.FadeWithRows(rows)
end)

-- Its own Edit Mode layout: once a character's set up with it (or is on
-- one of its layouts), it puts that layout back on every login, asking for a
-- reload. A profile's layout of ours switching it away each login too made
-- the two take turns, so its layout is left to it (Layouts.lua). A
-- character that said "not now" to its setup, on another layout, isn't
-- kept: profiles' layouts work there as without it.
ns.WhenAddonLoads("DaylightUI", function()
	ns.layoutKeeper = function()
		local DUI = _G.DaylightUI
		local editMode, installer = DUI and DUI.EditMode, DUI and DUI.Installer
		if not editMode then
			return nil
		end
		local okSet, state = pcall(function() return installer and installer.State() end)
		local okOn, on = pcall(editMode.AnyActive)
		if (okSet and state == "installed") or (okOn and on) then
			return "DaylightUI"
		end
		return nil
	end
end)

ns.WhenAddonLoads("DaylightUI_UnitFrames", function()
	ns.FadeWithRow("swing", "swing", { "DaylightUISwingTimer" }, true, true)
	ns.AddPortraitFrame("DaylightUIFrame_player")
	-- Its cast bars standing apart from their unit frames (named only then):
	-- yours with the Cast bar row, the others with their unit's.
	ns.FadeWithRow("castbar", "castbar", { "DaylightUICastBar_player" }, true, true)
	ns.FadeWithRow("target", "target", { "DaylightUICastBar_target" }, true, true)
	ns.FadeWithRow("focus", "target", { "DaylightUICastBar_focus" }, true, true)
end)

-- Its Quality of Life part has its own version of some of Cinematic's
-- features: its AFK screen and campfire scene (those scenes' cameras), its
-- zone title, level-up and reputation banners (those cards), and its object
-- glow (soft targeting settings of its own: Quest Vision's object glow and
-- Hide object icons). Whose plays is the Addon Conflicts pick (AddonSupport,
-- Conflicts.lua): its own while unpicked (the player's pick, 2026-11-12).
-- "Ours" holds its banner or screen at alpha 0 while Cinematic's is on. Its
-- error text and quest progress lines need nothing: they draw instead of the
-- game's, which is all Cinematic hides.
local LABEL = "DaylightUI"
local function DUI() return _G.DaylightUI end
local function QoLOn(key)
	return function()
		local dui = DUI()
		if dui and dui.Get and dui:Get("QoL", key) == true then
			return LABEL
		end
		return nil
	end
end
ns.WhenAddonLoads("DaylightUI_QoL", function()
	-- Its zone title showing a place's name as you walk into an inn: our
	-- Rested card (the inn's name too) waits till it's gone, rather than
	-- both names at once (the user's pick, 2026-11-19).
	if ns.AddCardWait then
		ns.AddCardWait(function(id)
			local title = _G.DaylightUIZoneTitle
			if id == "rested" and type(title) == "table" and ns.Flag(title:IsVisible()) then
				return L["DaylightUI's zone title is showing"]
			end
			return nil
		end)
	end
	local function Scene(key)
		return function() return ns.TriggerRowNow(key) ~= nil end
	end
	local function Card(id)
		return function() return ns.CardOn(id) end
	end
	local function Glow()
		return ns.QuestVisionSetting("questObjectGlow") or ns.QuestVisionSetting("hideObjectIcons")
	end
	for _, each in ipairs({
		{ "scene:AFK", "afkScreen", "AFK scene", "scenes", Scene("AFK"), { "DaylightUIAfkScreen" },
			"What plays while you're away: Cinematic's AFK camera, or DaylightUI's AFK screen" },
		{ "scene:Campfire", "campfire", "Campfire scene", "scenes", Scene("Campfire"), { "DaylightUICampfire" },
			"What plays as you sit by a campfire: Cinematic's Campfire camera, or DaylightUI's campfire scene" },
		{ "card:zone", "zoneTitle", "Zone card", "scenes", Card("zone"), { "DaylightUIZoneTitle" },
			"The banner as you enter a new zone" },
		{ "card:levelUp", "levelUp", "Level-up card", "scenes", Card("levelUp"), { "DaylightUILevelUp" },
			"The banner as you gain a level" },
		{ "card:reputation", "repBanner", "Reputation card", "scenes", Card("reputation"), { "DaylightUIRepBanner" },
			"The banner as you reach a new standing with a faction" },
		{ "questObjectGlow", "objectGlow", "Object glow and icons", "quest", Glow, nil,
			"Herbs, ore and quest objects lighting up near you: Quest Vision's object glow and Hide object " ..
			"icons, or DaylightUI's object glow. Both set the game's soft targeting, so only one can", true },
	}) do
		local row = { key = each[1], addon = LABEL, label = each[3], group = each[4], ours = each[5],
			hide = each[6], about = each[7], noBoth = each[8] }
		ns.AddFeatureYield(each[1], QoLOn(each[2]), row)
		-- (Hide object icons goes with the glow: one row.)
		if each[1] == "questObjectGlow" then ns.AddFeatureYield("hideObjectIcons", QoLOn(each[2]), row) end
	end
end)

-- Its looks against the Style hub's (Addon Conflicts' Style rows: one look
-- wins, no Both). Theirs: Cinematic's page stands aside while its own is on
-- (ns.StyleOn). Ours: Cinematic's look, and its own held at alpha 0 where it
-- can be (its tooltip and bubble backgrounds); its settings left be.
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }
local function Shells(list)
	local dui = DUI()
	local get = dui and dui.Style and dui.Style.GetShell
	local out = {}
	if type(get) ~= "function" then return out end
	for _, frame in ipairs(list) do
		local ok, shell = pcall(get, frame)
		if ok and type(shell) == "table" then out[#out + 1] = shell end
	end
	return out
end
local function ModuleOn(name)
	local dui = DUI()
	local mod = dui and dui.GetModule and dui:GetModule(name)
	return type(mod) == "table" and mod.enabled and true or false
end

ns.WhenAddonLoads("DaylightUI_Tooltip", function()
	ns.AddConflict({ key = "style:tooltip", addon = LABEL, label = "Tooltip look", group = "style", noBoth = true,
		styleSwitch = "tooltipStyle",
		about = "How tooltips look: the Interface hub's Tooltip Style page, or DaylightUI's tooltips",
		theirs = function()
			local dui = DUI()
			local aside = dui and dui.PrettyAside and dui.PrettyAside.Draws and dui.PrettyAside.Draws()
			return ModuleOn("Tooltip") and not aside
		end,
		ours = function() return ns.StyleOn("tooltipStyle") end,
		hide = function()
			local list = {}
			for _, name in ipairs(TOOLTIPS) do
				if type(_G[name]) == "table" then list[#list + 1] = _G[name] end
			end
			return Shells(list)
		end,
		onPick = function() if ns.RefreshTooltipStyle then ns.RefreshTooltipStyle() end end })
end)

ns.WhenAddonLoads("DaylightUI_Chat", function()
	ns.AddConflict({ key = "style:bubbles", addon = LABEL, label = "Chat bubble look", group = "style", noBoth = true,
		styleSwitch = "bubblesStyle",
		about = "How chat bubbles look: the Interface hub's Chat Bubble Style page, or DaylightUI's bubbles",
		theirs = function()
			local dui = DUI()
			return dui and dui.Get and dui:Get("Chat", "bubbles") == true or false
		end,
		ours = function() return ns.StyleOn("bubblesStyle") end,
		hide = function()
			local list = {}
			local all = C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles and C_ChatBubbles.GetAllChatBubbles()
			for _, bubble in pairs(type(all) == "table" and all or {}) do
				if type(bubble) == "table" and not (bubble.IsForbidden and bubble:IsForbidden()) then
					local frame = bubble:GetChildren()
					if type(frame) == "table" and not (frame.IsForbidden and frame:IsForbidden()) then
						list[#list + 1] = frame
					end
				end
			end
			return Shells(list)
		end,
		onPick = function() if ns.RefreshBubbleStyle then ns.RefreshBubbleStyle() end end })
end)

ns.WhenAddonLoads("DaylightUI_InfoPanel", function()
	ns.AddConflict({ key = "style:minimap", addon = LABEL, label = "Minimap look", group = "style", noBoth = true,
		about = "Its square minimap: left as DaylightUI draws it, or dressed by the Style hub's Interface Recolor " ..
			"page as well (its ring and buttons in the theme's color)",
		theirs = function()
			local dui = DUI()
			return dui and dui.Get and dui:Get("InfoPanel", "map.enabled") == true or false
		end,
		ours = function() return ns.StyleOn("irStyle") end,
		onPick = function() if ns.RefreshMinimapStyle then ns.RefreshMinimapStyle() end end })
end)

-- Its damage number font (DAMAGE_TEXT_FONT, set as it loads, after
-- Cinematic's) against the Combat Text Style page's Hide all the game's
-- floating text (a blank font: Core.lua). Theirs: its font. Ours: the blank
-- one again after each time it sets its own. The game reads it at login, so
-- either shows from the next game start.
do
	local BLANK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\Blank.ttf"
	local function OursOn()
		local db = ns.db
		return db and db.hideWorldText and db.combatTextStyle and db.styleGeneral ~= false and true or false
	end
	local row
	local function Apply()
		if row and OursOn() and ns.ConflictPick(row) == "ours" then DAMAGE_TEXT_FONT = BLANK end
	end
	ns.WhenAddonLoads("DaylightUI", function()
		local dui = DUI()
		local fonts = dui and dui.GameFonts
		if type(fonts) ~= "table" then return end
		row = ns.AddConflict({ key = "style:damageFont", addon = LABEL, label = "Damage number font", group = "style",
			noBoth = true, restart = true,
			about = "The game's floating numbers: blanked by the Combat Text Style page's Hide all the game's " ..
				"floating text, or in DaylightUI's damage font. Shows from the next game start",
			theirs = function()
				return type(fonts.DamageWanted) == "function" and fonts.DamageWanted() ~= nil or false
			end,
			ours = OursOn, onPick = Apply })
		if type(fonts.Apply) == "function" then hooksecurefunc(fonts, "Apply", Apply) end
	end)
end

-- Its nameplates are its own frames, one put on each game plate that shows a
-- unit (parented to it), with the game's unit frame kept at alpha 0 under
-- it. So the fade leaves that unit frame be (ns.addonPlateHidden: setting
-- its alpha would show the game's plate under its own) and goes on its plate
-- instead. It sets that plate's alpha itself too (back to full as a plate
-- appears, and its Fade other plates), so it's hooked: ours times its own
-- (ns.SetPlateFrameAlpha). Its plates are pooled and move from plate to
-- plate: one moved takes the alpha of the plate it lands on.
do
	local plateAlpha = setmetatable({}, { __mode = "k" }) -- [game plate] = its fade, below 1
	local hooked = setmetatable({}, { __mode = "k" })
	local LABEL = "DaylightUI plate alpha"

	local function Usable(frame)
		return type(frame) == "table" and not (frame.IsForbidden and frame:IsForbidden())
	end

	-- Its plate on a game plate: the child that has that plate's unit frame
	-- as the frame it hid.
	local function Ours(plate)
		local unitFrame = plate.UnitFrame
		if not unitFrame then
			return nil
		end
		for _, child in ipairs({ plate:GetChildren() }) do
			if Usable(child) and child.nameplate == plate and child.gameFrame == unitFrame then
				return child
			end
		end
		return nil
	end

	local function Hook(ours)
		if hooked[ours] then
			return
		end
		hooked[ours] = true
		hooksecurefunc(ours, "SetParent", function(self, parent)
			ns.SetPlateFrameAlpha(self, Usable(parent) and plateAlpha[parent] or nil, LABEL)
		end)
	end

	local function SetPlateAlpha(plate, alpha)
		alpha = alpha and alpha < 1 and alpha or nil
		plateAlpha[plate] = alpha
		local ours = Ours(plate)
		if ours then
			Hook(ours)
			ns.SetPlateFrameAlpha(ours, alpha, LABEL)
		end
	end

	ns.WhenAddonLoads("DaylightUI_Nameplates", function()
		ns.AddPlateAlpha(SetPlateAlpha)
		ns.AddPlateHidden(function(plate)
			return Ours(plate) ~= nil
		end)
		-- A new plate gets its plate in its own handler, which runs after
		-- ours (Effects: NAME_PLATE_UNIT_ADDED). Its own "last" handler runs
		-- after that one: the new unit's alpha goes on then, before it's drawn
		-- (the game plate's last alpha was its last unit's: a hidden enemy's
		-- plate flashed up for a frame).
		local DUI = _G.DaylightUI
		if DUI and DUI.RegisterEvent then
			DUI.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit)
				local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
				if ns.db and ns.db.enabled and type(plate) == "table"
					and not (plate.IsForbidden and plate:IsForbidden()) then
					ns.RefreshPlateAlpha(plate)
				end
			end, true)
		else
			ns.AfterPlateAdded(function(plate)
				SetPlateAlpha(plate, plateAlpha[plate])
			end)
		end
	end)
end
