-- Cinematic: Cooldown Manager Centered.
local _, ns = ...
local L = ns.L

-- One frame (or one kind of numbered frame) a row. (from: the row that held
-- them all till 2026-11-12, whose settings each starts with: ns.SplitAddonRows.)
for _, known in ipairs({
	-- Its icons sit in unnamed copies of these two frames, which follow their
	-- alpha, so fading these fades them too.
	{
		key = "cmcUtility", label = "Cooldown Manager Centered utility cooldowns", short = "CMC utility",
		about = L["its utility cooldowns"],
		note = L["The game's Cooldown Manager itself is a row on the Game Frames page."],
		names = { "CMCUtilityLayoutHost" },
	},
	{
		key = "cmcEssential", label = "Cooldown Manager Centered essential trackers", short = "CMC essential",
		about = L["its essential cooldown trackers"],
		names = { "CMCEssentialCustomTrackerHost" },
	},
	{
		key = "cmcBuffs", label = "Cooldown Manager Centered buff containers", short = "CMC buffs",
		about = L["its buff containers"],
		patterns = { "^CMCBuffContainer%d+$" },
	},
	{
		key = "cmcTrackers", label = "Cooldown Manager Centered trackers", short = "CMC trackers",
		about = L["its trackers"],
		patterns = { "^CMCTracker%d+$" },
	},
	{
		-- Its aura overlays: unnamed screen-sized AuraContainers.
		key = "cmcOverlays", label = "Cooldown Manager Centered aura overlays", short = "CMC overlays",
		about = L["its aura overlays"],
		match = function(frame)
			return frame:GetObjectType() == "AuraContainer"
		end,
	},
}) do
	known.addon, known.suite, known.from = "CooldownManagerCentered", "Cooldown Manager Centered", "cmc"
	table.insert(ns.ADDON_FRAMES, known)
end
