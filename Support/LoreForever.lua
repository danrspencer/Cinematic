-- Cinematic: Lore Forever (WoW Forever), which reads the story of places,
-- people, items and quests aloud with recorded narrators, with subtitles and
-- a small floating player while a story plays.
--
-- Its subtitles, floating player, new-page note and pin card are named
-- frames on UIParent, a row each. The subtitles fade themselves in and out
-- as lines start and end, so they're hooked: faded, it's ours times theirs.
-- Its talk mark (a small label saying your target can answer you out loud)
-- sits beside the target frame, so it fades with the Target frame row.
--
-- Willo's sky, rings of stars over the minimap, is left alone: the Lore
-- Forever companion app on the PC reads it off the screen, so faded, it
-- would stop knowing what's going on. Its minimap button and map pins are on
-- the minimap and fade with it. Its windows (the panel, options, the
-- journey, the companion's answers) are left be like any window.
--
-- Quest talk (Custom dialogue frames) parks the game's quest window off the
-- screen, and Lore Forever pins its Play narration button to that window, so
-- the button went with it. Ours sits in the bubble's top right corner while
-- Lore Forever has a recording for the page, and presses Lore Forever's own
-- button: it plays what the quest giver says, or stops it.
local _, ns = ...
local L = ns.L

for _, known in ipairs({
	{
		key = "loreSubtitles", label = "Lore Forever subtitles", short = "Lore subtitles",
		about = L["its subtitles"], names = { "LoreForeverSubtitles" }, hookAlpha = true,
	},
	{
		key = "lorePlayer", label = "Lore Forever player", short = "Lore player",
		about = L["its floating player"], names = { "LoreForeverMiniPlayer" },
	},
	{
		key = "loreSlip", label = "Lore Forever new page note", short = "Lore new page",
		about = L["its new page note"], names = { "LoreForeverPageSlip" },
	},
	{
		key = "lorePin", label = "Lore Forever pin card", short = "Lore pin card",
		about = L["its pin card"], names = { "LoreForeverPinArrive" },
	},
}) do
	known.addon, known.suite = "LoreForever", "Lore Forever"
	table.insert(ns.ADDON_FRAMES, known)
end

local CORNER = 26 -- (the button's size)

ns.WhenAddonLoads("LoreForever", function()
	-- Beside the target frame: with the target frame.
	ns.FadeWithRows({ { "target", "target", "LoreForeverTalkMark" } })
	-- Read off the screen by its companion app: never faded.
	ns.LeaveAlone({ "LoreForeverLiveSky" })

	-- Lore Forever's Play narration button on the quest window: the pill it
	-- makes there (no name), found among the window's children by its play
	-- and add halves.
	-- (It sets its pill up as the quest window opens, maybe after ours:
	-- followed as it shows and hides, from the time it's found.)
	local pill, Refresh
	local function FindPill()
		if pill or not _G.QuestFrame then return pill end
		for _, child in ipairs({ _G.QuestFrame:GetChildren() }) do
			if type(child.play) == "table" and type(child.add) == "table" and child.play.Click then
				pill = child
				break
			end
		end
		if pill then
			for _, frame in ipairs({ pill, pill.play }) do
				for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
					hooksecurefunc(frame, method, function() Refresh() end)
				end
			end
		end
		return pill
	end
	-- Shown while its pill offers a recording for this page.
	local function Recorded()
		local p = FindPill()
		return p and p:IsShown() and p.play:IsShown() or false
	end
	-- (Its pill keeps whether its line plays: p.playing.)
	local function Playing()
		local p = FindPill()
		return p and p.playing and true or false
	end

	local button
	function Refresh()
		if button then button:SetShown(Recorded()) end
	end

	ns.AddQuestTalkPart({
		make = function(bubble)
			button = CreateFrame("Button", nil, bubble)
			button:SetSize(CORNER, CORNER)
			-- (Spoken's Play button has the corner itself: ours goes beside it.)
			local spoken = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Spoken_Quests")
			button:SetPoint("CENTER", bubble, "TOPRIGHT", spoken and -(8 + CORNER) or -4, -4)
			button:SetFrameLevel(bubble:GetFrameLevel() + 6)
			button:RegisterForClicks("LeftButtonUp")
			local disc = button:CreateTexture(nil, "BACKGROUND")
			disc:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
			disc:SetPoint("TOPLEFT", 3, -3)
			disc:SetPoint("BOTTOMRIGHT", -3, 3)
			local icon = button:CreateTexture(nil, "ARTWORK")
			icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			icon:SetPoint("TOPLEFT", 5, -5)
			icon:SetPoint("BOTTOMRIGHT", -5, 5)
			local mask = button:CreateMaskTexture()
			mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(icon)
			icon:AddMaskTexture(mask)
			button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
			button:SetScript("OnClick", function()
				local p = FindPill()
				if p then p.play:Click() end
				Refresh()
			end)
			button:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(Playing() and L["Stop the narration (Lore Forever)"]
					or L["Play the narration (Lore Forever)"])
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", function() GameTooltip:Hide() end)
			button:Hide()
		end,
		shown = function() Refresh() end,
	})
end)
