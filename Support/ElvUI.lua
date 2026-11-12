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
local ROWS = {
	{ "player", "player", "ElvUF_Player" },
	{ "petframe", "player", "ElvUF_Pet", "ElvUF_PetTarget" },
	{ "target", "target", "ElvUF_Target" },
	{ "tot", "target", "ElvUF_TargetTarget", "ElvUF_TargetTargetTarget" },
	{ "focus", "target", "ElvUF_Focus" },
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
	-- and pet frame do (Personal Resource Display page).
	ns.AddPortraitFrame("ElvUF_Player")
	ns.AddPortraitFrame("ElvNP_Player", true)
	ns.AddPetFrame("ElvUF_Pet")
	ns.AddScanner(function()
		for part, name in pairs(LINKS) do
			local frame = _G[name]
			if IsUsable(frame) then ns.ClaimLinkPart("ElvUI", part, frame) end
		end
		ClaimChat()
	end)
	for group, names in pairs(RAID) do
		ns.FadeFoundByName(group, names)
	end
	ns.AddPlateAlpha(SetPlateAlpha)
end)
