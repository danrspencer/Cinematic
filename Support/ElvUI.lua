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

-- Advanced Frames rows.
for _, known in ipairs({
	{
		key = "elvBars", addon = "ElvUI",
		label = "ElvUI other bars", short = "ElvUI bars",
		about = L["its action bars 2 and 7 to 10"],
		note = L["Its other bars, pet, stance, totem, micro, bag and data bars are rows on the Standard " ..
			"Frames page, with its unit frames, buffs and chat panels."],
		names = { "ElvUI_Bar2", "ElvUI_Bar7", "ElvUI_Bar8", "ElvUI_Bar9", "ElvUI_Bar10" },
	},
	{
		key = "elvPanels", addon = "ElvUI",
		label = "ElvUI top and bottom panels", short = "ElvUI panels",
		about = L["its panels along the top and bottom of the screen"],
		names = { "ElvUI_TopPanel", "ElvUI_BottomPanel" },
	},
	{
		key = "elvThreat", addon = "ElvUI",
		label = "ElvUI threat bar", short = "ElvUI threat",
		about = L["its threat bar"],
		names = { "ElvUI_ThreatBarHolder" },
	},
}) do
	known.hookAlpha = true
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
	{ "xp", "bars", "ElvUI_ExperienceBarHolder", "ElvUI_ReputationBarHolder", "ElvUI_PetExperienceBarHolder" },
	-- Your cast bars sit inside its player and pet frames: they follow the
	-- Cast bar row, as the game's do (the castbar group ignores the parent's
	-- fade), not the frame they're on.
	{ "castbar", "castbar", "ElvUF_Player_CastBar", "ElvUF_Pet_CastBar" },
	-- Its chat panels hold the game's chat frames, with its data texts and
	-- toggle buttons (no row: the Chat page's).
	{ "chat", "chat", "LeftChatPanel", "RightChatPanel", "LeftChatToggleButton", "RightChatToggleButton" },
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

ns.WhenAddonLoads("ElvUI", function()
	ns.FadeWithRows(ROWS)
	for group, names in pairs(RAID) do
		ns.FadeFoundByName(group, names)
	end
	ns.AddPlateAlpha(SetPlateAlpha)
end)
