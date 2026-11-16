-- Cinematic: ElvUI, a whole-UI replacement. It swaps the game's unit frames,
-- action bars, buffs, data bars and chat panels for its own, which fade with
-- the frames they stand in for and follow the same rows on the Standard
-- Frames page. Its parts with no game frame to follow get rows of their own
-- on the Advanced Frames page.
--
-- It sets its frames' alpha all the time (its bars' opacity and mouseover
-- fading, its unit frames' range and fader fading): they're its own frames,
-- so they're hooked.
local _, ns = ...
local L = ns.L

-- Its detached power bar: a row of its own on the Health & Resources page
-- (PersonalResources.lua), its ticks by addon name, on to start with.
ns.ADDON_POWER_ROWS = ns.ADDON_POWER_ROWS or {}
table.insert(ns.ADDON_POWER_ROWS, { addon = "ElvUI",
	tip = L["ElvUI's player power bar, while it's detached from its player frame."] })
-- (Its Keep up columns, as the other power rows': PersonalResources.lua,
-- loaded after this, sets them for every row here.)

-- Advanced Frames rows: one frame each. (from: the row that held it with
-- others till 2026-11-12, whose settings it starts with: ns.SplitAddonRows.)
local rows = {}
for i, bar in ipairs({ 2, 7, 8, 9, 10 }) do
	rows[#rows + 1] = {
		key = "elvBar" .. bar, from = "elvBars",
		label = "ElvUI action bar " .. bar, short = "ElvUI bar " .. bar,
		about = L["its action bar %d"]:format(bar),
		note = i == 1 and L["Its other bars, pet, stance, totem, micro, bag and data bars are rows on the Standard " ..
			"Frames page, with its unit frames, buffs and chat panels."] or nil,
		names = { "ElvUI_Bar" .. bar },
	}
end
rows[#rows + 1] = {
	key = "elvTopPanel", from = "elvPanels",
	label = "ElvUI top panel", short = "ElvUI top panel",
	about = L["its panel along the top of the screen"],
	names = { "ElvUI_TopPanel" },
}
rows[#rows + 1] = {
	key = "elvBottomPanel", from = "elvPanels",
	label = "ElvUI bottom panel", short = "ElvUI bottom panel",
	about = L["its panel along the bottom of the screen"],
	names = { "ElvUI_BottomPanel" },
}
rows[#rows + 1] = {
	key = "elvThreat",
	label = "ElvUI threat bar", short = "ElvUI threat",
	about = L["its threat bar"],
	names = { "ElvUI_ThreatBarHolder" },
}
for _, known in ipairs(rows) do
	known.addon, known.suite, known.hookAlpha = "ElvUI", "ElvUI", true
	table.insert(ns.ADDON_FRAMES, known)
end

-- Its frames standing in for the game's, by Standard Frames row: the row,
-- the fade group, and the frames. (Its bars 1 and 3-6 show the game's action
-- pages 1 and 3-6, so the bars that page sits on; 13-15 are retail's bars 6-8.
-- Its target and focus cast bars are on its unit frames and fade with them,
-- as the game's do.)
-- (A unit frame's power bar, <frame>_PowerBar, listed with the frame. Not
-- detached it's inside the frame: nested, left to the frame's fade. Detached
-- with its Parent at UIParent it's moved onto ElvUI's UIParent; with its
-- Parent at FRAME (the default) it stays inside the faded frame, so it's set
-- to ignore the frame's alpha (DetachedBars, below) and fades on its own.)
local ROWS = {
	{ "player", "player", "ElvUF_Player", "ElvUF_Player_PowerBar" },
	{ "petframe", "player", "ElvUF_Pet", "ElvUF_PetTarget", "ElvUF_Pet_PowerBar" },
	{ "target", "target", "ElvUF_Target", "ElvUF_Target_PowerBar" },
	{ "tot", "target", "ElvUF_TargetTarget", "ElvUF_TargetTargetTarget" },
	{ "focus", "target", "ElvUF_Focus", "ElvUF_Focus_PowerBar" },
	{ "focustot", "target", "ElvUF_FocusTarget" },
	{ "party", "party", "ElvUF_Party" },
	{ "buffs", "buffs", "ElvUIPlayerBuffs", "ElvUIPlayerDebuffs" },
	{ "mainbar", "bars", "ElvUI_Bar1", "VehicleLeaveButtonHolder" },
	{ "right1", "sidebars", "ElvUI_Bar3" },
	{ "right2", "sidebars", "ElvUI_Bar4" },
	{ "bottomright", "bars", "ElvUI_Bar5" },
	{ "bottomleft", "bars", "ElvUI_Bar6" },
	{ "bar6", "bars", "ElvUI_Bar13" },
	{ "bar7", "bars", "ElvUI_Bar14" },
	{ "bar8", "bars", "ElvUI_Bar15" },
	{ "pet", "bars", "ElvUI_BarPet" },
	{ "stance", "bars", "ElvUI_StanceBar" },
	{ "totems", "totems", "ElvUI_TotemBar", "ElvUI_TotemTracker" },
	{ "micro", "bars", "ElvUI_MicroBar" },
	-- (Classic clients have no Bags row: their bags go with the micro menu.)
	{ _G.BagsBar and "bags" or "micro", "bars", "ElvUIBagBar" },
	-- Its bar for an encounter's or quest's own power, in place of the game's.
	{ "encounter", "encounter", "ElvUI_AltPowerBar" },
	-- (Honor and Azerite: retail only.)
	{ "xp", "bars","ElvUI_ExperienceBarHolder", "ElvUI_ReputationBarHolder", "ElvUI_PetExperienceBarHolder",
		"ElvUI_HonorBarHolder", "ElvUI_AzeriteBarHolder" },
	-- Its arena enemy frames, in place of the game's (the Flag carriers row).
	{ "flags", "flags", "ElvUF_Arena1", "ElvUF_Arena2", "ElvUF_Arena3", "ElvUF_Arena4", "ElvUF_Arena5" },
	-- Your cast bars sit inside its player and pet frames: they follow the
	-- Cast bar row, as the game's do (the castbar group ignores the parent's
	-- fade), not the frame they're on.
	{ "castbar", "castbar", "ElvUF_Player_CastBar", "ElvUF_Pet_CastBar" },
	-- Its player nameplate (on with its Static Position) stands in for the
	-- personal resource display: your health and power under you.
	{ "prd", "prd", "ElvNP_Player" },
	-- Its chat panels hold the game's chat frames, with its data texts and
	-- toggle buttons (no row: the Chat page's), and its voice chat panel over
	-- the left one.
	{ "chat", "chat", "LeftChatPanel", "RightChatPanel", "LeftChatToggleButton", "RightChatToggleButton",
		"ElvUIChatVoicePanel" },
}

-- Its nameplates are its own frames on the game's plates (plate.unitFrame),
-- standing in for the game's (hidden), and it sets their alpha for its
-- target and range fading: hooked, as Plater's are (ns.SetPlateFrameAlpha).
local function SetPlateAlpha(plate, alpha)
	local frame = plate.unitFrame
	if type(frame) == "table" and frame.isNameplate and frame.SetAlpha then
		ns.SetPlateFrameAlpha(frame, alpha, "ElvUI plate SetAlpha hook")
	end
end

-- Its raid frames fade with the game's on the Standard Frames page (Players
-- and Pets): those groups are found by scans, not names.
local RAID = {
	raidplayers = { "ElvUF_Raid1", "ElvUF_Raid2", "ElvUF_Raid3", "ElvUF_Tank", "ElvUF_Assist" },
	raidpets = { "ElvUF_Raidpet" },
}

-- Its frames standing in for the game's, linked as those parts (Addon Frame
-- Links: FrameLinks.lua), so the pages' Addon Frame Links sections and the
-- Support files tab show them as found. Part -> its frame's name; looked up
-- with each scan till found (most are made after loading, and only with
-- that module of it on).
local LINKS = {
	unitplayer = "ElvUF_Player", unitpet = "ElvUF_Pet", unittarget = "ElvUF_Target",
	unittot = "ElvUF_TargetTarget", unitfocus = "ElvUF_Focus", unitfocustot = "ElvUF_FocusTarget",
	aurabuffs = "ElvUIPlayerBuffs", auradebuffs = "ElvUIPlayerDebuffs",
	prdbars = "ElvNP_Player",
}

local function IsUsable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not (frame.IsForbidden and frame:IsForbidden())
end

-- Its detached power bars still inside their faded unit frame (Parent:
-- FRAME): they ignore the frame's alpha while detached, so their own fade
-- shows them (low mana and "until full" bring them up without the frame).
-- Put back when attached again. (Each scan; nesting is worked out after.)
local DETACHABLE = { "ElvUF_Player", "ElvUF_Pet", "ElvUF_Target", "ElvUF_Focus" }
local function DetachedBars()
	for _, name in ipairs(DETACHABLE) do
		local frame, bar = _G[name], _G[name .. "_PowerBar"]
		if IsUsable(frame) and IsUsable(bar) and bar.SetIgnoreParentAlpha then
			local own = frame.POWERBAR_DETACHED == true and bar:GetParent() == frame
			if bar.cinematicOwnAlpha ~= own then
				bar.cinematicOwnAlpha = own
				bar:SetIgnoreParentAlpha(own)
			end
		end
	end
end

-- Its chat panels: the panel a chat window's lines show on (its left and
-- right chat windows, as its Chat module says), the panel's backdrop (the
-- Chat page's Background), its tab strip and its data panels and toggle
-- buttons.
local function ClaimChat()
	local E = _G.ElvUI and _G.ElvUI[1]
	local ok, chat = false, nil
	if E and type(E.GetModule) == "function" then
		ok, chat = pcall(E.GetModule, E, "Chat", true)
	end
	chat = ok and type(chat) == "table" and chat or nil
	for _, side in ipairs({ "Left", "Right" }) do
		local panel = _G[side .. "ChatPanel"]
		local window = chat and chat[side .. "ChatWindow"]
		if IsUsable(panel) and IsUsable(window) then
			local backdrop = IsUsable(panel.backdrop) and { panel.backdrop } or nil
			ns.ClaimLinkPart("ElvUI", "chatwindow", panel, { window = window, backdrop = backdrop })
		end
		local tab = _G[side .. "ChatTab"]
		if IsUsable(tab) then ns.ClaimLinkPart("ElvUI", "chattabs", tab) end
		for _, name in ipairs({ side .. "ChatDataPanel", side .. "ChatToggleButton" }) do
			local frame = _G[name]
			if IsUsable(frame) then ns.ClaimLinkPart("ElvUI", "chatbuttons", frame) end
		end
	end
end

-- Its smooth fades (its unit frames' range fade): restarted every 0.2 s from
-- the alpha it reads back, ours in it, so each restart knocked ours down and
-- its target of target flickered. While one runs the frame is marked with
-- where it ends, which our hook takes as its alpha (Frames.lua).
local function FollowFades()
	local E = _G.ElvUI and _G.ElvUI[1]
	if type(E) ~= "table" or type(E.UIFrameFade) ~= "function"
		or type(E.UIFrameFadeRemoveFrame) ~= "function" then
		return
	end
	hooksecurefunc(E, "UIFrameFade", function(_, frame, info)
		if type(frame) ~= "table" or type(frame.SetAlpha) ~= "function"
			or (frame.IsForbidden and frame:IsForbidden())
			or type(info) ~= "table" or type(info.endAlpha) ~= "number"
			or (issecretvalue and issecretvalue(info.endAlpha)) then
			return
		end
		frame.cinematicFadeEnd = info.endAlpha
		-- (It set the start alpha before this: taken again, as its end.)
		if type(info.startAlpha) == "number" and not (issecretvalue and issecretvalue(info.startAlpha)) then
			frame:SetAlpha(info.startAlpha)
		end
	end)
	hooksecurefunc(E, "UIFrameFadeRemoveFrame", function(_, frame)
		if type(frame) == "table" then frame.cinematicFadeEnd = nil end
	end)
end

ns.WhenAddonLoads("ElvUI", function()
	FollowFades()
	ns.FadeWithRows(ROWS)
	-- Its player frame, player nameplate and pet frame stay up while you or
	-- your pet recover, as the game's player frame, personal resource display
	-- and pet frame do (Health & Resources page).
	ns.AddPortraitFrame("ElvUF_Player")
	ns.AddPowerBarFrame("ElvUF_Player_PowerBar", "ElvUI")
	-- (Its player frame's SetAlpha hook does math on the alpha, its 3D
	-- portrait's fix: no secret alpha there. Its detached power bar has none.)
	ns.NO_SECRET_ALPHA.ElvUF_Player = true
	ns.AddPortraitFrame("ElvNP_Player", true)
	ns.AddPetFrame("ElvUF_Pet")
	ns.AddPetFrame("ElvUF_Pet_PowerBar")
	ns.AddScanner(function()
		for part, name in pairs(LINKS) do
			local frame = _G[name]
			if IsUsable(frame) then ns.ClaimLinkPart("ElvUI", part, frame) end
		end
		ClaimChat()
		DetachedBars()
		-- The dark bar behind its minimap's zone name and clock (with its
		-- minimap cluster on): the Minimap header row, as the game's bar there.
		local back = _G.ElvUI_MinimapClusterBackdrop
		if IsUsable(back) and not ns.IsFaded(back) then
			ns.AddFoundFrame(back, "minimapheader", false, false)
		end
	end)
	for group, names in pairs(RAID) do
		ns.FadeFoundByName(group, names)
	end
	ns.AddPlateAlpha(SetPlateAlpha)
end)

-- Its own versions of some of Cinematic's features (Addon Conflicts: whose
-- plays, AddonSupport.lua and Conflicts.lua; theirs while unpicked).
local function Elv()
	local E = _G.ElvUI and _G.ElvUI[1]
	return type(E) == "table" and E or nil
end
local function Private(path, key)
	local E = Elv()
	local t = E and E.private and E.private[path]
	return type(t) == "table" and t[key] or nil
end
-- Its backdrop (SetTemplate: the backdrop pieces it adds, and its inner and
-- outer edges) on each of these frames.
local BACKDROP = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge",
	"BottomEdge", "LeftEdge", "RightEdge", "Center", "iborder", "oborder" }
local function Backdrops(frames)
	local out = {}
	for _, frame in ipairs(frames) do
		for _, key in ipairs(BACKDROP) do
			local piece = frame[key]
			if type(piece) == "table" and piece.SetAlpha then out[#out + 1] = piece end
		end
	end
	return out
end
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }

ns.WhenAddonLoads("ElvUI", function()
	-- Its AFK mode: its own AFK screen, the UI hidden and the camera spun.
	-- Ours: the AFK scene's camera plays, its screen is held hidden, its
	-- spin doesn't start and the UI is left for CineMode.
	local afkRow
	local function OursPlays()
		return afkRow and ns.ConflictPick(afkRow) == "ours" and ns.TriggerRowNow("AFK") ~= nil
	end
	local function AfkOn()
		local E = Elv()
		return E and E.db and E.db.general and E.db.general.afk == true and "ElvUI" or nil
	end
	afkRow = { key = "scene:AFK", addon = "ElvUI", label = "AFK scene", group = "scenes",
		ours = function() return ns.TriggerRowNow("AFK") ~= nil end, hide = { "ElvUIAFKFrame" },
		about = "What plays while you're away: Cinematic's AFK camera, or ElvUI's AFK mode (its own screen, " ..
			"the UI hidden and the camera spinning)" }
	ns.AddFeatureYield("scene:AFK", AfkOn, afkRow)
	local E = Elv()
	local AFK = E and E.GetModule and select(2, pcall(E.GetModule, E, "AFK"))
	if type(AFK) == "table" and type(AFK.CameraSpin) == "function" and type(AFK.SetAFK) == "function" then
		-- (Its spin, wrapped so it never starts while ours plays: a stop
		-- after it would stop our own camera's turn too, and its start
		-- counts as you turning the camera.)
		local spin = AFK.CameraSpin
		AFK.CameraSpin = function(self, status, ...)
			if status and OursPlays() then return end
			return spin(self, status, ...)
		end
		hooksecurefunc(AFK, "SetAFK", function(_, status)
			if status and OursPlays() and not InCombatLockdown() and not UIParent:IsShown() then
				UIParent:Show()
			end
		end)
	end

	ns.AddConflict({ key = "style:tooltip", addon = "ElvUI", label = "Tooltip look", group = "style", noBoth = true,
		styleSwitch = "tooltipStyle",
		about = "How tooltips look: the Interface hub's Tooltip Style page, or ElvUI's tooltips",
		theirs = function() return Private("tooltip", "enable") == true end,
		ours = function() return ns.StyleOn("tooltipStyle") end,
		hide = function()
			local list = {}
			for _, name in ipairs(TOOLTIPS) do
				if type(_G[name]) == "table" then list[#list + 1] = _G[name] end
			end
			return Backdrops(list)
		end,
		onPick = function() if ns.RefreshTooltipStyle then ns.RefreshTooltipStyle() end end })

	ns.AddConflict({ key = "style:bubbles", addon = "ElvUI", label = "Chat bubble look", group = "style",
		noBoth = true, styleSwitch = "bubblesStyle",
		about = "How chat bubbles look: the Interface hub's Chat Bubble Style page, or ElvUI's bubbles",
		theirs = function()
			local option = Private("general", "chatBubbles")
			return option ~= nil and option ~= "disabled"
		end,
		ours = function() return ns.StyleOn("bubblesStyle") end,
		hide = function()
			local list = {}
			local all = C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles and C_ChatBubbles.GetAllChatBubbles()
			for _, bubble in pairs(type(all) == "table" and all or {}) do
				if type(bubble) == "table" and not (bubble.IsForbidden and bubble:IsForbidden()) then
					local holder = bubble:GetChildren()
					if type(holder) == "table" and not (holder.IsForbidden and holder:IsForbidden()) then
						list[#list + 1] = holder
					end
				end
			end
			return Backdrops(list)
		end,
		onPick = function() if ns.RefreshBubbleStyle then ns.RefreshBubbleStyle() end end })

	-- Its Loot Roll (bars of its own for group loot rolls) against Roll
	-- Vision's window (RollWindow.lua). Ours: its bars held hidden.
	ns.AddConflict({ key = "rolls", addon = "ElvUI", label = "Loot roll window", group = "windows",
		about = "Group loot rolls: Roll Vision's window, or ElvUI's Loot Roll bars",
		theirs = function() return Private("general", "lootRoll") == true end,
		ours = function() return ns.Setting("rollWindow") end,
		hide = function()
			local list = {}
			for i = 1, 10 do
				local bar = _G["ElvUI_LootRollFrame" .. i]
				if type(bar) == "table" then list[#list + 1] = bar end
			end
			return list
		end,
		onPick = function() if ns.RefreshRollWindow then ns.RefreshRollWindow() end end })
end)
