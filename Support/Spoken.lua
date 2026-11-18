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
	-- (What it says is there to be read while it's up: CineMode leaves it
	-- alone till you switch its row, 2026-11-17.)
	known.shownByDefault = true
	ns.ADDON_SHOWN_BY_DEFAULT[known.key] = true
	table.insert(ns.ADDON_FRAMES, known)
end

-- The narrators' portraits are 3D models, and a model doesn't fade with its
-- window: Spoken fades it by hand to the window's alpha, so a window we faded
-- left the speaker's head on screen alone (a player, 2026-11-17). So each
-- model follows its window's alpha (ours times Spoken's) whenever either is
-- set. The models are made with the first line that shows one (Spoken's
-- Portrait:Configure), so they're looked for then too.
local MODEL_OF = { -- window -> its model, once made
	SpokenPlayerFrame = function(window)
		return window.portrait and window.portrait.model
	end,
	SpokenMinimalPlayerFrame = function(window)
		local viewport = window.portrait and window.portrait.viewport
		return viewport and viewport.model
	end,
	-- (The subtitles' face, beside the speaker's name: on Spoken's Subtitle.)
	SpokenSubtitleFrame = function(_, env)
		local subtitle = rawget(env, "Subtitle")
		local viewport = type(subtitle) == "table" and subtitle.viewport
		return viewport and viewport.model
	end,
}
ns.WhenAddonLoads("Spoken", function()
	local env = rawget(_G, "SpokenEnv")
	local Portrait = type(env) == "table" and rawget(env, "Portrait")
	if not (type(Portrait) == "table" and type(Portrait.Configure) == "function") then return end
	local windowOf = setmetatable({}, { __mode = "k" }) -- model -> its window
	local hookedWindow = {}
	local syncing = false
	local function Follow(window, model)
		if syncing then return end
		local alpha = window:GetEffectiveAlpha()
		if issecretvalue and issecretvalue(alpha) then return end
		syncing = true
		model:SetAlpha(alpha)
		syncing = false
	end
	local function OnModelAlpha(model)
		local window = windowOf[model]
		if window then Follow(window, model) end
	end
	local function Sync(window)
		local find = MODEL_OF[window:GetName() or ""]
		local model = find and find(window, env)
		if not (model and model.SetAlpha) then return end
		if not windowOf[model] then
			windowOf[model] = window
			hooksecurefunc(model, "SetAlpha", OnModelAlpha)
		end
		Follow(window, model)
	end
	local function SyncAll()
		for name in pairs(MODEL_OF) do
			local window = _G[name]
			if window and window.SetAlpha then
				if not hookedWindow[window] then
					hookedWindow[window] = true
					hooksecurefunc(window, "SetAlpha", Sync)
				end
				Sync(window)
			end
		end
	end
	hooksecurefunc(Portrait, "Configure", SyncAll)
	SyncAll()
end)

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
