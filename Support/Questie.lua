-- Cinematic: Questie, whose tracker stands in for the game's quest tracker.
-- Its tracker and its quest item buttons fade with the Quest tracker row on
-- the Standard Frames page, so they come up with it as you make progress.
--
-- The item buttons are top-level (on UIParent, beside the tracker or in it)
-- and set their own alpha (its fade-out option): they're its own frames, so
-- they're hooked. The tracker leaves its own alpha alone.
--
-- It draws objective icons of its own on nameplates and the target frame (on
-- to start with, each its own option): our quest mark steps aside for them,
-- unit by unit (ns.QuestieMarks). So does our quest item button for an item
-- it has a button for (ns.QuestieItemButton).
local _, ns = ...
local L = ns.L

-- Advanced Frames page (no columns: it follows the Quest tracker row).
table.insert(ns.ADDON_NOTES, {
	addon = "Questie", label = "Questie",
	works = L["Follows the Quest tracker row"],
	about = L["Questie's quest tracker and its quest item buttons fade with the Quest tracker row on the " ..
		"Game Frames page. Where Questie puts its own icon on a nameplate or the target frame, Quest Vision's " ..
		"quest mark stays off it, and the quest item button stays away while its tracker has a button for that item."],
})

-- Whether Questie has its objective icon on the unit: on its nameplate, or
-- with onTargetFrame on the target frame. Its own checks, as it draws: its
-- option, none in instances on Forever, and an unfinished objective it knows
-- for the NPC (quests it doesn't know keep our mark). Unreadable counts as no,
-- and so does all of it with questMarkFade unticked.
function ns.QuestieMarks(unit, onTargetFrame)
	local questie, loader = _G.Questie, _G.QuestieLoader
	local profile = questie and questie.db and questie.db.profile
	if not (profile and loader and profile[onTargetFrame and "nameplateTargetFrameEnabled" or "nameplateEnabled"]) then
		return false
	end
	if not ns.QuestVisionSetting("questMarkFade") or (questie.IsForever and IsInInstance()) then
		return false
	end
	local okGuid, guid = pcall(UnitGUID, unit)
	if not okGuid or type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then
		return false
	end
	local plates = loader:ImportModule("QuestieNameplate")
	if type(plates.GetIcon) ~= "function" then
		return false
	end
	local okIcon, icon = pcall(plates.GetIcon, guid)
	return okIcon and icon ~= nil
end

-- Its item buttons, one per quest you can hold (made up front).
local ITEM_BUTTONS = 35

-- Whether Questie's tracker has a button up for the item. Read off its buttons,
-- so a quest it doesn't track, or has collapsed, keeps ours. Never with
-- questItemFade unticked.
function ns.QuestieItemButton(itemID)
	if not (_G.Questie and ns.QuestVisionSetting("questItemFade")) then
		return false
	end
	for i = 1, ITEM_BUTTONS do
		local button = _G["Questie_ItemButton" .. i]
		if button and button.itemId == itemID and ns.Flag(button:IsVisible()) then
			return true
		end
	end
	return false
end

ns.WhenAddonLoads("Questie", function()
	ns.FadeWithRow("quests", "quests", { "Questie_BaseFrame" })
	local buttons = {}
	for i = 1, ITEM_BUTTONS do
		buttons[i] = "Questie_ItemButton" .. i
	end
	ns.FadeWithRow("quests", "quests", buttons, true, true)
end)
