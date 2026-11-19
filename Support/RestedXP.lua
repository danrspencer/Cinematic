-- Cinematic: RestedXP Guides, whose guide window stands in for the game's
-- quest tracker. Its guide, quest item and target buttons, level splits and
-- waypoint arrow are a row each on the Addons page. The guide, buttons and
-- splits rode on the HUD page's Quest tracker row before (till 2026-11-19),
-- so until set they take that row's ticks (follows). The arrow starts as a
-- new row does: players keep it up to find their way while the guide fades,
-- as TomTom's arrow.
--
-- The guide (its mouseover fading), the arrow and the splits (their opacity
-- settings) set their own alpha: they're its own frames, so they're hooked.
local _, ns = ...
local L = ns.L

for _, known in ipairs({
	{ key = "rxpGuide", label = "RestedXP guide", about = L["its guide window"], names = { "RXPFrame" },
		follows = "quests" },
	{ key = "rxpItem", label = "RestedXP quest item", about = L["its quest item button"], names = { "RXPItemFrame" },
		follows = "quests" },
	{ key = "rxpTarget", label = "RestedXP targets", about = L["its target buttons"], names = { "RXPTargetFrame" },
		follows = "quests" },
	{ key = "rxpSplits", label = "RestedXP level splits", about = L["its level splits"], names = { "RXPLevelSplits" },
		follows = "quests" },
	{ key = "rxpArrow", label = "RestedXP arrow", about = L["its waypoint arrow"], names = { "RXPG_ARROW" } },
}) do
	known.addon, known.suite, known.short, known.hookAlpha = "RXPGuides", "RestedXP Guides", known.label, true
	table.insert(ns.ADDON_FRAMES, known)
end
