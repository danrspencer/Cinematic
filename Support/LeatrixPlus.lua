-- Cinematic: Leatrix Plus, a large set of game tweaks. Most of them sit beside
-- Cinematic without clashing (its zone text hiding, combat plates and max
-- camera zoom set the same game parts Cinematic's zone card, plate fade and
-- Graphics page do, and both work). What's handled here:
--
-- - Its square minimap (Enhance minimap > Square minimap) rebuilds the
--   minimap's header as a bar of its own, a dark backdrop at its Header
--   opacity, unnamed, on the map. It fades with the Minimap page's Minimap
--   header row, as the game's bar does: hiding that row left it on screen
--   (a player's report, 2026-11-12). Its black border is the map's child, so
--   it goes with the map. The game's header strip it holds at its own
--   opacity is left to it.
-- - Its minimap button bag (right-click the minimap) fades with the Addon
--   buttons row, as MinimapButtonButton's does.
-- - Its flight bar (Show flight times) gets a row of its own on the Addon
--   Frames page.
-- - Its Set edit mode layout puts a layout back on every login, like
--   DaylightUI's: profiles' layouts are left to it then (Layouts.lua).
-- - Its tooltip backgrounds tinted by faction (Enhance tooltip) against the
--   Style hub's Tooltip Style page: an Addon Conflicts row.
--
-- Its settings are read from its saved variables (LeaPlusDB: "On" for a
-- ticked box), loaded before its code runs; most take a reload to change.
local _, ns = ...
local L = ns.L
local LABEL = "Leatrix Plus"

local function On(key)
	local db = _G.LeaPlusDB
	return type(db) == "table" and db[key] == "On"
end

local function Usable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not (frame.IsForbidden and frame:IsForbidden())
end

-- Addon Frames row: its flight bar, unnamed on UIParent (made on your first
-- flight), told by its parts.
table.insert(ns.ADDON_FRAMES, {
	key = "leatrixFlightBar", addon = "Leatrix_Plus",
	label = "Leatrix Plus flight bar", short = "Leatrix flight bar",
	about = L["its flight progress bar (Show flight times)"],
	note = L["Its square minimap's header bar follows the Minimap header row on the HUD page, " ..
		"and its minimap button bag the Addon buttons row."],
	match = function(frame)
		return type(frame.track) == "table" and type(frame.dest) == "table" and type(frame.time) == "table"
			and type(frame.edges) == "table" and frame.spark ~= nil
	end,
})

-- Its square minimap's header bar: the map's unnamed child with its backdrop
-- (a plain background in its border's art).
local HEADER_BACK = "chatframebackground$"
local HEADER_EDGE = "ui%-dialogbox%-background%-dark$"
local function IsHeaderBar(frame)
	if not Usable(frame) or frame:GetName() or type(frame.GetBackdrop) ~= "function" then return false end
	local ok, back = pcall(frame.GetBackdrop, frame)
	return ok and type(back) == "table" and type(back.bgFile) == "string" and type(back.edgeFile) == "string"
		and back.bgFile:lower():find(HEADER_BACK) ~= nil and back.edgeFile:lower():find(HEADER_EDGE) ~= nil
end

ns.WhenAddonLoads("Leatrix_Plus", function()
	-- The game's header strip: Enhance minimap holds it at its Header opacity
	-- (0 on its square map, under its own bar), so the header fade leaves it
	-- (Frames.lua), or it came back at full over Leatrix Plus's.
	local zone = type(_G.MinimapCluster) == "table" and _G.MinimapCluster.ZoneTextButton
	if On("MinimapModder") and type(zone) == "table" and type(zone.StateTexture) == "table" then
		ns.headerArtLeftAlone = ns.headerArtLeftAlone or {}
		ns.headerArtLeftAlone[zone.StateTexture] = true
	end
	local headerBar
	ns.AddScanner(function()
		if not On("MinimapModder") then return end
		if On("SquareMinimap") and not headerBar and type(Minimap) == "table" and Minimap.GetChildren then
			for _, child in ipairs({ Minimap:GetChildren() }) do
				if IsHeaderBar(child) then headerBar = child break end
			end
		end
		if headerBar and not ns.IsFaded(headerBar) then
			ns.AddFoundFrame(headerBar, "minimapheader", false, false)
		end
		local bag = _G.LeaPlusGlobalMinimapCombinedButtonFrame
		if On("MinimapButtonBag") and Usable(bag) and not ns.IsFaded(bag) then
			ns.AddFoundFrame(bag, "minimapaddons", false, false)
		end
	end)

	-- (Another support file's keeper, DaylightUI's, asked first.)
	local before = ns.layoutKeeper
	ns.layoutKeeper = function()
		local other = before and before()
		if other then return other end
		local db = _G.LeaPlusDB
		local name = type(db) == "table" and db.EditModeLayoutName
		if On("SetEditModeLayout") and type(name) == "string" and name:match("%S") then
			return LABEL
		end
		return nil
	end

	ns.AddConflict({ key = "style:tooltip", addon = LABEL, label = "Tooltip look", group = "style", noBoth = true,
		styleSwitch = "tooltipStyle",
		about = "How tooltips look: the Interface hub's Tooltip Style page, or Leatrix Plus's tooltip backgrounds " ..
			"tinted blue or red by faction (Enhance tooltip)",
		theirs = function() return On("TipModEnable") and On("TipBackSimple") end,
		ours = function() return ns.StyleOn("tooltipStyle") end,
		onPick = function() if ns.RefreshTooltipStyle then ns.RefreshTooltipStyle() end end })
end)
