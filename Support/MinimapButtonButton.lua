-- Cinematic: MinimapButtonButton, which gathers the minimap's addon buttons
-- into one button of its own (MinimapButtonButtonButton, on UIParent) and the
-- bar it opens (that button's child, the gathered buttons in it). It fades
-- with the Minimap page's Addon buttons row: with the map, back up when you
-- hover the minimap (the Minimap mouseover group has that row), and not for
-- an ore, herb or ping reveal unless Reveal shows lists Addon buttons. The
-- buttons it gathered fade with it (Frames.lua lets them go from the map's
-- fade once they've left the map). It never sets its button's alpha itself.
local _, ns = ...
local L = ns.L

-- Advanced Frames page (no columns: it follows the Addon buttons row).
table.insert(ns.ADDON_NOTES, {
	addon = "MinimapButtonButton", label = "MinimapButtonButton",
	works = L["Follows the Addon buttons row"],
	about = L["Its button and addon bar fade with the minimap and come back on hover."],
})

ns.WhenAddonLoads("MinimapButtonButton", function()
	ns.FadeWithRow("minimapaddons", "minimapaddons", { "MinimapButtonButtonButton" })
end)
