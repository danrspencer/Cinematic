-- Cinematic: Platynator, nameplates of its own.
--
-- Fade. It moves each game plate's unit frame into a hidden frame of its own
-- and draws its own plate on top: made per game plate (NamePlate1 has the
-- first, and so on) and parented to it, never moved to another. So the
-- fade leaves the game's unit frame be (ns.addonPlateHidden) and goes on its
-- plate instead. It sets that plate's alpha itself all the time (target,
-- mouseover, range), so it's hooked: ours times its own
-- (ns.SetPlateFrameAlpha).
--
-- Settings. At login, on each loading screen and after a fight it writes the
-- game's "which plates show" settings from its own options, the ones the
-- Nameplates page's rows decide: those writes count as its own passes and
-- the rows are switched on again after them (ns.FollowOthersPlateWrites).
local _, ns = ...
local L = ns.L

-- Advanced Frames page (no columns: its plates follow the Nameplates page).
table.insert(ns.ADDON_NOTES, {
	addon = "Platynator", label = "Platynator",
	works = L["Follows the Nameplates page"],
	about = L["Platynator's nameplates fade in CineMode and follow the Nameplates page."],
})

local LABEL = "Platynator plate alpha"

local function Usable(frame)
	return type(frame) == "table" and not (frame.IsForbidden and frame:IsForbidden())
end

-- Its plates on a game plate: the children made from its plate template (its
-- widgets, its design index and its unit setter). It makes one per design
-- (enemy, friendly, simplified...) on each game plate and shows the one the
-- unit gets, so all of them take the fade.
local function SetPlateAlpha(plate, alpha)
	for _, child in ipairs({ plate:GetChildren() }) do
		if Usable(child) and type(child.widgets) == "table" and child.kind ~= nil
			and type(child.SetUnit) == "function" then
			ns.SetPlateFrameAlpha(child, alpha, LABEL)
		end
	end
end

ns.WhenAddonLoads("Platynator", function()
	ns.AddPlateAlpha(SetPlateAlpha)
	ns.AddPlateHidden(function(plate)
		local unitFrame = plate.UnitFrame
		return Usable(unitFrame) and unitFrame:GetParent() ~= plate
	end)
	-- Its plate takes its new unit in its own handler, which runs after
	-- ours: the plate's fade goes on again after it.
	ns.AfterPlateAdded(function(plate)
		if ns.db and ns.db.enabled then
			ns.RefreshPlateAlpha(plate)
		end
	end)
	ns.FollowOthersPlateWrites("Platynator", "Platynator")
end)
