-- Cinematic: DynamicCam, a camera addon. It has no frames on screen to fade
-- (only its settings windows), but it drives the same camera ours do:
--
--  - Its zoom ("reactive zoom", on to start with) swaps the game's zoom
--    functions for its own, which add steps to a zoom and stop its own
--    glide. Our cameras' zooms go to the game's own instead (ns.zoomBypass,
--    Camera.lua), so they go the distance they ask for. It swaps them again
--    with each of its situation changes, which drops our hook that sees your
--    own scroll-wheel zooms: hooked again each time.
--  - Its situations (off to start with) can zoom, turn the camera or go to a
--    saved view as you take a flight, hearth, go AFK, fish or talk to an NPC:
--    the same moments as our scenes. Each one that's on with a camera move
--    gets an Addon Conflicts row (AddonSupport.lua): Theirs (the default)
--    and our scene stands aside; Ours and its situation counts as off while
--    it picks one, so it never starts it. Not Both: two cameras on one view
--    fight.
--  - It writes its camera settings (zoom, turn speeds, field of view...) on
--    each situation change. One we hold for a move of ours (a slow turn's
--    speed, a set's value) keeps ours: its value becomes the one put back
--    when ours lets go.
--  - It owns the shoulder offset (it writes it on every situation change):
--    Shoulder Cam stands aside while it's loaded (ShoulderCam.lua).
--
-- Its UI fade (a situation's Hide UI) fades the whole UI and holds it there;
-- we never set the whole UI's alpha, so nothing fights. Its hooks on the
-- tooltip and quest windows don't touch ours.
local _, ns = ...
local L = ns.L

local LABEL = "DynamicCam"

-- Advanced Frames page (no columns: nothing of its fades).
table.insert(ns.ADDON_NOTES, {
	addon = LABEL, label = LABEL,
	works = L["Shares the camera with Cinematic's"],
	about = L["Cinematic's cameras work alongside DynamicCam, which has no frames to fade."],
})

-- Its situations that play at the same moments as our scenes: its situation
-- ID (its own, fixed), our scenes (each a ns.EVENTS key), and the row.
local SCENES = {
	{ id = "160", scenes = { "Flight" }, label = "Flight scene",
		about = "What plays on a flight path: Cinematic's flight camera, or DynamicCam's Taxi situation" },
	{ id = "200", scenes = { "Hearth", "Teleport" }, label = "Hearth and teleport scenes",
		about = "What plays as you cast your Hearthstone or a teleport: Cinematic's camera, or DynamicCam's " ..
			"Hearth/Teleport situation" },
	{ id = "303", scenes = { "AFK" }, label = "AFK scene",
		about = "What plays while you're away: Cinematic's AFK camera, or DynamicCam's AFK situation" },
	{ id = "302", scenes = { "Fishing" }, label = "Fishing scene",
		about = "What plays as you fish: Cinematic's fishing camera, or DynamicCam's Fishing situation" },
	{ id = "300", scenes = { "Quest", "QuestGossip" }, label = "Quest giver scenes",
		about = "What plays as you talk to a quest giver: Cinematic's quest camera, or DynamicCam's NPC " ..
			"Interaction situation. Picking ours turns DynamicCam's NPC Interaction off for every NPC, " ..
			"vendors and banks too" },
}

ns.WhenAddonLoads(LABEL, function()
	local libStub = _G.LibStub
	local ace = libStub and libStub("AceAddon-3.0", true)
	local dc = ace and ace:GetAddon(LABEL, true)
	if type(dc) ~= "table" then
		ns.Log("support", "DynamicCam loaded, but its addon object wasn't found: nothing done")
		return
	end

	-- Our zooms past its zoom (Camera.lua).
	ns.zoomBypass = true

	-- Your scroll-wheel zooms: its zoom functions hooked each time it swaps
	-- them in. (Hooked, the function's no longer its own, so it swaps them in
	-- again with its next situation change: hooked again then.)
	local hooked = {}
	local function HookZoom()
		for _, name in ipairs({ "CameraZoomIn", "CameraZoomOut" }) do
			if type(_G[name]) == "function" and _G[name] ~= hooked[name] then
				hooksecurefunc(name, ns.OnPlayerZoom)
				hooked[name] = _G[name]
			end
		end
	end
	for _, method in ipairs({ "ReactiveZoomOn", "ReactiveZoomOff" }) do
		if type(dc[method]) == "function" then
			hooksecurefunc(dc, method, HookZoom)
		end
	end

	-- Its camera settings: one we hold keeps ours, its value saved as the one
	-- to put back.
	if type(dc.DC_SetCVar) == "function" then
		local setCVar = dc.DC_SetCVar
		dc.DC_SetCVar = function(self, cvar, setting, ...)
			local db = ns.db
			if db and type(cvar) == "string" and setting ~= nil then
				if ns.SpeedHeld and ns.SpeedHeld(cvar) and db.heldSpeeds and db.heldSpeeds[cvar] then
					db.heldSpeeds[cvar] = tostring(setting)
					ns.LogDetail("cvar", ("%s: DynamicCam's %s kept for after ours"):format(cvar, tostring(setting)))
					return
				end
				if db.savedCVars and db.savedCVars[cvar] ~= nil then
					db.savedCVars[cvar] = tostring(setting)
					ns.LogDetail("cvar", ("%s: DynamicCam's %s kept for after ours"):format(cvar, tostring(setting)))
					return
				end
			end
			return setCVar(self, cvar, setting, ...)
		end
	end

	-- Shoulder Cam stands aside (no row: the dev copy's).
	ns.AddFeatureYield("shoulderCam", function() return LABEL end)
	if ns.ApplyShoulderCam then ns.Guard(ns.ApplyShoulderCam) end

	-- Its situations, as it has them now.
	local function Situation(id)
		local profile = dc.db and dc.db.profile
		local situations = profile and profile.situations
		local situation = type(situations) == "table" and situations[id]
		return type(situation) == "table" and situation or nil
	end
	-- On, and moving the camera (a zoom, a view or a turn): only then is it
	-- the same moment's camera as ours.
	local function MovesCamera(id)
		local situation = Situation(id)
		if not (situation and situation.enabled and not situation.errorEncountered) then
			return false
		end
		local view, turn = situation.viewZoom, situation.rotation
		return (type(view) == "table" and view.enabled) or (type(turn) == "table" and turn.enabled) or false
	end

	local function Reevaluate()
		if type(dc.EvaluateSituations) == "function" then
			pcall(dc.EvaluateSituations, dc)
		end
	end
	for _, each in ipairs(SCENES) do
		local id, scenes = each.id, each.scenes
		each.row = { key = "scene:" .. scenes[1], addon = LABEL, label = each.label, group = "scenes",
			noBoth = true, about = each.about, onPick = Reevaluate,
			ours = function()
				for _, key in ipairs(scenes) do
					if ns.TriggerRowNow(key) ~= nil then return true end
				end
				return false
			end }
		local function Theirs()
			return MovesCamera(id) and LABEL or nil
		end
		-- (Both scenes share the one row: its first scene's key.)
		for _, key in ipairs(scenes) do
			ns.AddFeatureYield("scene:" .. key, Theirs, each.row)
		end
	end

	-- "Ours": while it works out which situation you're in, the ones picked
	-- Ours count as off, so it never starts them. (Put back at once: its
	-- saved settings never change.)
	if type(dc.EvaluateSituations) == "function" then
		local evaluate = dc.EvaluateSituations
		dc.EvaluateSituations = function(self, ...)
			local off = {}
			for _, each in ipairs(SCENES) do
				local situation = Situation(each.id)
				if situation and situation.enabled and each.row.id and ns.ConflictPick(each.row) == "ours" then
					situation.enabled = false
					off[#off + 1] = situation
				end
			end
			local results = ns.Pack(pcall(evaluate, self, ...))
			for _, situation in ipairs(off) do
				situation.enabled = true
			end
			if not results[1] then
				error(results[2], 0)
			end
			return unpack(results, 2, results.n)
		end
	end
end)

-- /cine debug dynamiccam: what it's doing to the camera now, and what of
-- ours stands aside for it.
function ns.DynamicCamDebug(print)
	local libStub = _G.LibStub
	local ace = libStub and libStub("AceAddon-3.0", true)
	local dc = ace and ace:GetAddon(LABEL, true)
	if type(dc) ~= "table" then
		print("DynamicCam: not loaded")
		return
	end
	print(("DynamicCam: loaded, support %s, our zooms %s"):format(
		ns.AddonSupportOn(LABEL) and "on" or "switched off (Addons page)",
		ns.zoomBypass and "go past its zoom" or "go through its zoom"))
	local reactive = type(dc.ReactiveZoomIsOn) == "function" and dc:ReactiveZoomIsOn()
	print(("  its zoom handling: %s; the zoom functions are %s"):format(reactive and "on" or "off",
		ns.GAME_ZOOM and _G.CameraZoomIn == ns.GAME_ZOOM.CameraZoomIn and "the game's" or "swapped"))
	local last = ns.lastPlayerZoomAt
	print(("  your last zoom seen: %s"):format(last and ("%.1f s ago"):format(GetTime() - last) or "none yet"))
	print(("  its situation now: %s"):format(tostring(dc.currentSituationID or "none")))
	print(("  Shoulder Cam: %s"):format(ns.FeatureYieldedTo("shoulderCam") and "stands aside" or "not affected"))
	for _, each in ipairs(SCENES) do
		local row = each.row
		if row and row.id then
			local on = ns.ConflictTheirsOn(row)
			print(("  %s (situation %s): %s"):format(each.label, each.id,
				on and ("its moves the camera, pick " .. ns.ConflictPick(row)) or "its is off or doesn't move the camera"))
		end
	end
end
