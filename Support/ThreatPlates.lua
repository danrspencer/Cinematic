-- Cinematic: Threat Plates (TidyPlates_ThreatPlates), nameplates of its own.
--
-- Fade. It puts a frame of its own on each game plate (plate.TPFrame, named
-- ThreatPlatesFrame...) and hides the game's unit frame under it, for the
-- units it draws. Its frame ignores the plate's alpha (it does its own range
-- and target fading), so a faded game plate left it at full: the fade goes on
-- its frame, hooked as it sets its own alpha all the time (ours times its
-- own: ns.SetPlateFrameAlpha). A unit it leaves to the game keeps the game's
-- unit frame, faded as usual.
--
-- Settings. With its friendly plates set to show out of fights only, it
-- switches the game's friendly plate settings around each fight, the ones
-- the Nameplates page's rows decide: those writes count as its own passes
-- and the rows are switched on again after them (ns.FollowOthersPlateWrites).
-- Its occlusion option writes the game's plate alpha settings; those are
-- left to it.
local _, ns = ...
local L = ns.L

-- Advanced Frames page (no columns: its plates follow the Nameplates page).
table.insert(ns.ADDON_NOTES, {
	addon = "TidyPlates_ThreatPlates", label = "Threat Plates",
	works = L["Follows the Nameplates page"],
	about = L["Threat Plates' nameplates fade in CineMode and follow the Nameplates page."],
})

local LABEL = "Threat Plates plate alpha"

local function Usable(frame)
	return type(frame) == "table" and not (frame.IsForbidden and frame:IsForbidden())
end

local function SetPlateAlpha(plate, alpha)
	local ours = plate.TPFrame
	if Usable(ours) and ours.SetAlpha then
		ns.SetPlateFrameAlpha(ours, alpha, LABEL)
	end
end

ns.WhenAddonLoads("TidyPlates_ThreatPlates", function()
	ns.AddPlateAlpha(SetPlateAlpha)
	-- (The game's unit frame hidden under its own: moved off the plate, or
	-- hidden where it can't be moved.)
	ns.AddPlateHidden(function(plate)
		local unitFrame = plate.UnitFrame
		return Usable(plate.TPFrame) and Usable(unitFrame)
			and (unitFrame:GetParent() ~= plate or not unitFrame:IsShown())
	end)
	-- Its frame gets its new unit in its own handler, which runs after ours:
	-- the plate's fade goes on again after it.
	ns.AfterPlateAdded(function(plate)
		if ns.db and ns.db.enabled then
			ns.RefreshPlateAlpha(plate)
		end
	end)
	ns.FollowOthersPlateWrites("TidyPlates_ThreatPlates", "Threat Plates")
end)
