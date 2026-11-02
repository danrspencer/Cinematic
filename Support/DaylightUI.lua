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
local _, ns = ...
local L = ns.L

-- Advanced Frames rows.
for _, known in ipairs({
	{
		key = "dlMeters", addon = "DaylightUI_InfoPanel",
		label = "DaylightUI damage meters", short = "DaylightUI meters",
		about = L["its damage meter windows"],
		note = L["Its info panel (XP bar and minimap) follows the Minimap row on the Standard Frames page; " ..
			"its unit frames, bars, buffs, chat and quest tracker follow the rows of the frames they replace."],
		names = { "DaylightUIDamageMeter", "DaylightUIDamageMeter2" },
	},
	{
		key = "dlThreat", addon = "DaylightUI_InfoPanel",
		label = "DaylightUI threat meter", short = "DaylightUI threat",
		about = L["its threat meter window"],
		names = { "DaylightUIThreatMeterFrame" },
	},
	{
		key = "dlQoL", addon = "DaylightUI_QoL",
		label = "DaylightUI QoL displays", short = "DaylightUI QoL",
		about = L["its flight timer and loot feed"],
		names = { "DaylightUIFlightTimer", "DaylightUILootFeed" },
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
		key = "dlQuestNav", addon = "DaylightUI_Quests",
		label = "DaylightUI quest arrow", short = "DaylightUI arrow",
		about = L["its quest arrow and marker"],
		names = { "DaylightUIQuestArrow", "DaylightUIQuestMarker" },
	},
}) do
	known.suite, known.hookAlpha = "DaylightUI", true
	table.insert(ns.ADDON_FRAMES, known)
end

-- (Frames those rows fade: left out of the areas below.)
local OWN_ROWS = {}
for _, known in ipairs(ns.ADDON_FRAMES) do
	if known.suite == "DaylightUI" then
		for _, name in ipairs(known.names or {}) do
			OWN_ROWS[name] = true
		end
	end
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
	if name and OWN_ROWS[name] then
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
	for num, row in ipairs(BARS) do
		local names = {}
		for i = 1, 12 do
			names[i] = "DaylightUIBar" .. num .. "Button" .. i
		end
		ns.FadeWithRow(row[1], row[2], names, true, true)
	end
end)

ns.WhenAddonLoads("DaylightUI_UnitFrames", function()
	ns.FadeWithRow("swing", "swing", { "DaylightUISwingTimer" }, true, true)
	ns.AddPortraitFrame("DaylightUIFrame_player")
end)

-- Its nameplates are its own frames, one put on each game plate that shows a
-- unit (parented to it), with the game's unit frame kept at alpha 0 under
-- it. So the fade leaves that unit frame be (ns.addonPlateHidden: setting
-- its alpha would show the game's plate under its own) and sets its plate's
-- alpha instead, which it never sets itself. Its plates are pooled and move
-- from plate to plate: one moved takes the alpha of the plate it lands on.
do
	local plateAlpha = setmetatable({}, { __mode = "k" }) -- [game plate] = its fade, below 1
	local hooked = setmetatable({}, { __mode = "k" })

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
			self:SetAlpha(Usable(parent) and plateAlpha[parent] or 1)
		end)
	end

	local function SetPlateAlpha(plate, alpha)
		alpha = alpha and alpha < 1 and alpha or nil
		plateAlpha[plate] = alpha
		local ours = Ours(plate)
		if ours then
			Hook(ours)
			ours:SetAlpha(alpha or 1)
		end
	end

	ns.WhenAddonLoads("DaylightUI_Nameplates", function()
		local other, otherHidden = ns.addonPlateAlpha, ns.addonPlateHidden
		ns.addonPlateAlpha = function(plate, alpha)
			if other then
				other(plate, alpha)
			end
			SetPlateAlpha(plate, alpha)
		end
		ns.addonPlateHidden = function(plate)
			return (otherHidden and otherHidden(plate)) or Ours(plate) ~= nil
		end
		-- A new plate gets its plate in its own handler, which runs after
		-- ours (Effects: NAME_PLATE_UNIT_ADDED): give it the plate's alpha
		-- straight after, before it's drawn.
		local watcher = CreateFrame("Frame")
		watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
		watcher:SetScript("OnEvent", function(_, _, unit)
			local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
			if Usable(plate) then
				SetPlateAlpha(plate, plateAlpha[plate])
			end
		end)
	end)
end
