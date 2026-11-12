-- Cinematic: WeakAuras. Its auras sit in one screen-sized frame (and two
-- small ones for auras attached to the mouse or the personal resource
-- display), so fading those fades them all. Auras anchored to another frame
-- are that frame's children and fade with it. It leaves those frames' alpha
-- alone, so they aren't hooked.
local _, ns = ...
local L = ns.L

-- One frame a row. (from: the row that held all three till 2026-11-12, whose
-- settings each starts with: ns.SplitAddonRows.)
for _, known in ipairs({
	{
		key = "weakauras", label = "WeakAuras auras", short = "WeakAuras",
		about = L["its auras"],
		note = L["Auras anchored to another frame fade with that frame."],
		names = { "WeakAurasFrame" },
	},
	{
		key = "weakaurasMouse", from = "weakauras",
		label = "WeakAuras on the mouse", short = "WeakAuras on mouse",
		about = L["its auras attached to the mouse"],
		names = { "WeakAurasAttachToMouseFrame" },
	},
	{
		key = "weakaurasPRD", from = "weakauras",
		label = "WeakAuras on the personal resource display", short = "WeakAuras on PRD",
		about = L["its auras attached to the personal resource display"],
		names = { "WeakAurasAttachToPRD" },
	},
}) do
	known.addon, known.suite = "WeakAuras", "WeakAuras"
	table.insert(ns.ADDON_FRAMES, known)
end
