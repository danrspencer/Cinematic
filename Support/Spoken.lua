-- Cinematic: Spoken, which reads the game aloud (quests and gossip with
-- Spoken Quests, places, books, bosses with its other parts), with a narrator
-- window and subtitles on screen while a line plays.
--
-- Its narrator windows (the full one and the minimal one) and its subtitles
-- are named frames on UIParent, a row each. All three fade themselves in and
-- out as lines start and end, so they're hooked: faded, it's ours times
-- theirs. Its narrator over Dialogue UI moves onto Dialogue UI's window and
-- goes with it, so it has no row. Its minimap button is a LibDBIcon one,
-- handled with the rest.
--
-- Quest talk (Custom dialogue frames) parks the game's quest window off the
-- screen, and Spoken Quests pins its Listen button to that window, so the
-- button went with it. Ours gets Spoken's own round Play button instead, in
-- the bubble's top right corner: it reads the open quest (Spoken Quests'
-- /spqread) or, while a line plays, skips it.
local _, ns = ...
local L = ns.L

for _, known in ipairs({
	{
		key = "spokenNarrator", label = "Spoken narrator", short = "Spoken narrator",
		about = L["its narrator window"], names = { "SpokenPlayerFrame" },
	},
	{
		key = "spokenMinimal", label = "Spoken minimal narrator", short = "Spoken minimal",
		about = L["its minimal narrator window"], names = { "SpokenMinimalPlayerFrame" },
	},
	{
		key = "spokenSubtitles", label = "Spoken subtitles", short = "Spoken subtitles",
		about = L["its subtitles"], names = { "SpokenSubtitleFrame" },
	},
}) do
	known.addon, known.suite, known.hookAlpha = "Spoken", "Spoken", true
	table.insert(ns.ADDON_FRAMES, known)
end

-- The Play button on Quest talk's bubble, with Spoken Quests loaded.
local CORNER = 26 -- (its size; the button's own art fills it)
ns.WhenAddonLoads("Spoken_Quests", function()
	local Spoken = _G.Spoken
	if not (Spoken and Spoken.IsCompatible and Spoken:IsCompatible(1) and Spoken.CreateRoundButton) then
		return
	end
	local button
	local function Playing()
		return Spoken:GetNowPlaying() ~= nil
	end
	local function Tip()
		GameTooltip:SetOwner(button, "ANCHOR_TOP")
		GameTooltip:SetText(Playing() and L["Stop this line (Spoken)"] or L["Read this aloud (Spoken)"])
		GameTooltip:Show()
	end
	local function SetGlyph()
		if button and button.SetPlaying then button:SetPlaying(Playing()) end
		-- (Its tooltip up: brought up to date, so it doesn't say Read while it's reading.)
		if button and GameTooltip:IsOwned(button) then Tip() end
	end
	-- (A frame later: Spoken says a line started before it counts it as
	-- playing, so read at once it still looked silent and kept Play.)
	local function Relabel()
		SetGlyph()
		C_Timer.After(0, function() SetGlyph() end)
	end
	ns.AddQuestTalkPart({
		make = function(bubble)
			button = Spoken:CreateRoundButton(bubble, "play")
			if not button then return end
			button:SetSize(CORNER, CORNER)
			button:SetPoint("CENTER", bubble, "TOPRIGHT", -4, -4)
			button:SetFrameLevel(bubble:GetFrameLevel() + 6)
			button:RegisterForClicks("LeftButtonUp")
			button:SetScript("OnClick", function()
				if Playing() then
					Spoken:Skip()
				elseif SlashCmdList and SlashCmdList.SPOKENQUESTSREAD then
					SlashCmdList.SPOKENQUESTSREAD("")
				end
				Relabel()
			end)
			button:SetScript("OnEnter", Tip)
			button:SetScript("OnLeave", function() GameTooltip:Hide() end)
			if Spoken.RegisterCallback then
				for _, event in ipairs({ "CLIP_QUEUED", "CLIP_STARTED", "CLIP_STOPPED", "CLIP_DROPPED" }) do
					Spoken:RegisterCallback(event, Relabel)
				end
			end
		end,
		-- (Only with its quests or gossip part on in Spoken's settings.)
		shown = function()
			if not button then return end
			local on = not Spoken.IsPartOn or Spoken:IsPartOn("quests") or Spoken:IsPartOn("gossip")
			button:SetShown(on and true or false)
			Relabel()
		end,
	})
end)
