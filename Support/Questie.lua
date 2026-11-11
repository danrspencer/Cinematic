-- Cinematic: Questie, whose tracker stands in for the game's quest tracker.
-- Its tracker and its quest item buttons fade with the Quest tracker row on
-- the Standard Frames page, so they come up with it as you make progress.
--
-- The item buttons are top-level (on UIParent, beside the tracker or in it)
-- and set their own alpha (its fade-out option): they're its own frames, so
-- they're hooked. The tracker leaves its own alpha alone.
--
-- It draws objective icons of its own on nameplates and the target frame (on
-- to start with, each its own option). Quest Vision's Questie's icons
-- dropdown picks which shows where both would: ours (Questie's hidden there:
-- PlateParts' RefreshQuestIcon and ns.QuestieTargetIcon below), Questie's
-- (ours steps aside, unit by unit: ns.QuestieMarks) or both. Where ours is
-- off, Questie's nameplate icon still goes where ours would (PlateParts). Our
-- quest item button steps aside for an item it has a button for
-- (ns.QuestieItemButton).
local _, ns = ...
local L = ns.L

-- Advanced Frames page (no columns: it follows the Quest tracker row).
table.insert(ns.ADDON_NOTES, {
	addon = "Questie", label = "Questie",
	works = L["Follows the Quest tracker row"],
	about = L["Questie's quest tracker and its quest item buttons fade with the Quest tracker row on the " ..
		"Game Frames page, and does the Quest Tracker page's Show just that quest and Close the gaps. With a theme " ..
		"picked, the Interface Recolor page's Quest tracker rows style it too. Its quest icons on nameplates sit where Quest Vision's quest mark would, and where " ..
		"both would show, Quest Vision's Questie's icons setting picks which. The quest item button stays away " ..
		"while its tracker has a button for that item."],
})

-- Quest Vision's Questie's icons choice: "ours", "questie" or "both".
function ns.QuestieIconsMode()
	local mode = ns.Setting("questieIcons")
	return (mode == "questie" or mode == "both") and mode or "ours"
end

-- Whether our quest mark steps aside for Questie's objective icon on the
-- unit: on its nameplate, or with onTargetFrame on the target frame. Only
-- with Questie's icons winning. Its own checks, as it draws: its option, none
-- in instances on Forever, and an unfinished objective it knows for the NPC
-- (quests it doesn't know keep our mark). Unreadable counts as no.
function ns.QuestieMarks(unit, onTargetFrame)
	local questie, loader = _G.Questie, _G.QuestieLoader
	local profile = questie and questie.db and questie.db.profile
	if not (profile and loader and profile[onTargetFrame and "nameplateTargetFrameEnabled" or "nameplateEnabled"]) then
		return false
	end
	if not ns.Setting("questVision") or ns.QuestieIconsMode() ~= "questie" or (questie.IsForever and IsInInstance()) then
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

-- Questie's icon on the target frame: a plain unnamed frame with an .Icon it
-- puts on the target frame (a new one each time it draws one). With ours
-- showing there and ours winning (yield), it's made see-through; otherwise
-- what we made see-through is put back.
local hiddenTargetIcons = {}
function ns.QuestieTargetIcon(yield)
	if not yield then
		for frame in pairs(hiddenTargetIcons) do
			frame:SetAlpha(1)
			hiddenTargetIcons[frame] = nil
		end
		return
	end
	local parent = _G.TargetFrame
	if not (_G.QuestieLoader and parent and ns.QuestieIconsMode() == "ours") then
		return
	end
	for _, child in ipairs({ parent:GetChildren() }) do
		if not (child.IsForbidden and child:IsForbidden()) and rawget(child, "Icon") and not child:GetName()
			and child:GetObjectType() == "Frame" then
			child:SetAlpha(0)
			hiddenTargetIcons[child] = true
		end
	end
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
	-- Its tracker is made seconds after the loading screen, past the login
	-- window, hidden, and shown about a second later: snapped to hidden as
	-- soon as it's made, while it's still hidden, so it never shows (waiting
	-- for it to show let it flash for a moment). Its first show snaps again,
	-- in case CineMode wasn't on yet as it was made.
	local checks = 0
	local watch
	watch = C_Timer.NewTicker(0.1, function()
		checks = checks + 1
		local base = _G.Questie_BaseFrame
		local made = type(base) == "table" and base.HookScript ~= nil
		if made or checks >= 600 then
			watch:Cancel()
			if made and ns.SnapLateFrames then
				ns.SnapLateFrames()
				local shown = false
				base:HookScript("OnShow", function()
					if shown then return end
					shown = true
					ns.SnapLateFrames()
				end)
			end
		end
	end)
end)
