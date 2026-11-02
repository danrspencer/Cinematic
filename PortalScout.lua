-- Dev copy only (CinematicDev.toc; .pkgmeta leaves it out): /cine debug portal
-- shows the game's own portal and swirl models over the screen, one at a time,
-- to see which load on each client, how they sit in a model frame and what
-- they cost, before any is a Vitals Vision layer. Each: its file number (from
-- the game's file list) and what it is. Not every client has every one: the
-- low numbers are old enough for Classic.

local _, ns = ...

local MODELS = {
	{ 197007, "Dungeon portal (the old one)" },
	{ 197011, "Dungeon portal, red" },
	{ 197008, "Dungeon portal, green" },
	{ 240937, "Dungeon portal, purple (Wrath's)" }, -- (at -10: looks like 197007, blue; retail)
	{ 240933, "Dungeon portal, blue" }, -- (the same)
	{ 240935, "Dungeon portal, green (Wrath's)" }, -- (at -10: the whole screen green, too near)
	{ 240939, "Dungeon portal, red (Wrath's)" }, -- (looks like 197007)
	{ 165829, "Spell portal, purple" }, -- (at -10: a bright pink ring round you, in the middle)
	{ 165834, "Large spell portal, purple" }, -- (at -10: streaks off to the bottom left)
	{ 166523, "Mage portal" }, -- (at -10: like 165829, blue)
	{ 1713776, "Fel portal" },
	{ 1624366, "Void portal (Argus)" },
	{ 5855151, "Dark swirl" },
	{ 5855152, "Dark swirl (2)" },
	{ 5855149, "Frost swirl" },
	{ 5855150, "Green swirl" },
	{ 7135867, "Void swirl" },
	{ 5873233, "Void swirly" },
	{ 6727368, "Portal (War Within)" },
	{ 6839404, "Dark portal (War Within)" },
	{ 5870480, "Arcane portal" },
	{ 5906259, "Portal plane" },
}

local model
local at = 0
-- Where it sits (the model frame's own units): how far from the camera, how
-- high, which way it faces and tilts, how big, how strong.
-- (Facing 90 and 270: the old dungeon portal is edge on, a beam down the middle (tested);
-- at 0 it faces the camera; at distance -10 its swirling rim frames the screen's edges, the
-- middle clear (tested, retail).)
local place = { distance = -10, up = 0, facing = 0, tilt = 0, scale = 1, alpha = 1 }
local shownFile

local function Apply()
	model:SetPosition(place.distance, 0, place.up)
	model:SetFacing(math.rad(place.facing))
	if model.SetPitch then pcall(model.SetPitch, model, math.rad(place.tilt)) end
	model:SetModelScale(place.scale)
	model:SetAlpha(place.alpha)
end

local function Show(file, name)
	model:ClearModel()
	model:SetModel(file)
	shownFile = file
	Apply()
	model:Show()
	-- (Loaded or not shows a frame later: the file number comes back once it has.)
	C_Timer.After(0.2, function()
		if shownFile ~= file then return end
		local ok, loaded = pcall(model.GetModelFileID, model)
		ns.Print(("portal %s: %s (%d), %s"):format(at > 0 and (at .. " of " .. #MODELS) or "file", name or "?", file,
			ok and loaded == file and "loaded" or "|cffff6060not on this client|r"))
		ns.Log("portal", ("%d %s: loaded %s"):format(file, name or "?", tostring(ok and loaded)))
	end)
end

local function Where()
	ns.Print(("  distance %.1f, up %.1f, facing %d, tilt %d, scale %.2f, alpha %.2f"):format(place.distance,
		place.up, place.facing, place.tilt, place.scale, place.alpha))
end

function ns.ScoutPortal(arg)
	arg = arg or ""
	if arg == "off" then
		if model then model:Hide() end
		ns.Print("portal: off")
		return
	end
	if not model then
		model = CreateFrame("PlayerModel", nil, UIParent)
		model:SetAllPoints(UIParent)
		model:SetFrameStrata("BACKGROUND")
		model:EnableMouse(false)
	end
	local word, value = arg:match("^(%a+)%s*(%-?[%d%.]*)$")
	local number = tonumber(arg)
	local step = tonumber(value)
	if word == "near" or word == "far" then
		place.distance = place.distance + (step or 1) * (word == "near" and 1 or -1)
	elseif word == "up" or word == "down" then
		place.up = place.up + (step or 0.5) * (word == "up" and 1 or -1)
	elseif word == "turn" then
		place.facing = (place.facing + (step or 45)) % 360
	elseif word == "tilt" then
		place.tilt = (place.tilt + (step or 45)) % 360
	elseif word == "scale" and step then
		place.scale = step
	elseif word == "alpha" and step then
		place.alpha = math.max(0, math.min(1, step))
	elseif word == "reset" then
		place = { distance = -10, up = 0, facing = 0, tilt = 0, scale = 1, alpha = 1 }
	elseif word == "back" then
		at = (at - 2) % #MODELS + 1
		Show(MODELS[at][1], MODELS[at][2])
	elseif number and number > #MODELS then -- (a file number of its own)
		at = 0
		Show(number, nil)
	else
		at = number or at % #MODELS + 1
		at = (at - 1) % #MODELS + 1
		Show(MODELS[at][1], MODELS[at][2])
	end
	if word and word ~= "back" then
		if shownFile then Apply() else at = 1 Show(MODELS[1][1], MODELS[1][2]) end
		Where()
	end
	ns.Print("  next: /cine debug portal; also back, a number or file, near/far, up/down, turn, tilt, scale N, " ..
		"alpha N, reset, off")
end
