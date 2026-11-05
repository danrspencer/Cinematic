-- Cinematic: DialogueUI (Dialogue UI), which swaps the game's gossip and
-- quest windows for its own (DUIQuestFrame), with its own gamepad controls.
-- It stops the game's windows opening at all (it unregisters their events),
-- so Quest talk (Custom dialogue frames) never comes up beside it: that only
-- opens over a game window. Where DialogueUI steps aside (in instances, with
-- its option), the game's windows come back, and with them ours.
--
-- Its camera (Camera Movement: zoom in on the NPC, or pan; on to start with)
-- moves the view as a talk starts and puts it back as it ends. While its
-- window's up with that on, it holds the camera lock (ns.RegisterCamera), so
-- the quest camera and our others wait; with Camera Movement off in its
-- settings, ours play as usual. Shoulder Cam leaves the shoulder offset alone
-- meanwhile (DialogueUI sets that same setting for its shot).
local _, ns = ...
local L = ns.L

-- Advanced Frames page (no columns: nothing of its fades).
table.insert(ns.ADDON_NOTES, {
	addon = "DialogueUI", label = "Dialogue UI",
	works = L["Takes over talking to NPCs"],
	about = L["Dialogue UI's window stands in for the game's gossip and quest windows, so Cinematic's " ..
		"Custom dialogue frames don't show while it's on. While its camera moves (Camera Movement in its " ..
		"settings), Cinematic's quest camera and other cameras wait; turn that off there to have ours."],
})

-- Whether DialogueUI's window is up with its camera on (its saved settings:
-- CameraMovement 0 is off, nil its default, on).
function ns.DialogueUICameraOn()
	local frame = _G.DUIQuestFrame
	if not (frame and ns.Flag(frame:IsShown())) then
		return false
	end
	local db = _G.DialogueUI_DB
	if type(db) ~= "table" then
		return true
	end
	if db.CameraMovement == 0 then
		return false
	end
	if db.CameraMovementDisableInstance and ns.Flag(IsInInstance()) then
		return false
	end
	return true
end

ns.WhenAddonLoads("DialogueUI", function()
	-- (No letGo: its camera isn't ours to stop.)
	ns.RegisterCamera("DialogueUI", ns.DialogueUICameraOn)
end)
