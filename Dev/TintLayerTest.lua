-- /cine debug tintlayer (dev copy only): where can a screen wash sit so that
-- nameplates draw over it? The tint is a UIParent frame, and the nameplates
-- are in WorldFrame, under all of UIParent: so the tint colours their names.
-- This lays a strong red wash in each place a frame of ours could go, one at a
-- time, and takes a screenshot of each. A name that stays its own colour in a
-- shot is over the wash there. Each shot says which place it is and where the
-- nameplates are (strata and level), in a strip along its top; the same goes
-- in the log.

local _, ns = ...

local SETTLE, AFTER = 0.8, 0.6 -- (seconds: the wash is drawn; the shot's written)

-- parent: nil = none. strata nil = left as the parent gives it.
local PLACES = {
	{ name = "no wash (reference)" },
	{ name = "UIParent, BACKGROUND 0 (today)", parent = "UIParent", strata = "BACKGROUND", level = 0 },
	{ name = "WorldFrame child, strata as given, level 0", parent = "WorldFrame", level = 0 },
	{ name = "WorldFrame child, WORLD 0", parent = "WorldFrame", strata = "WORLD", level = 0 },
	{ name = "WorldFrame child, BACKGROUND 0", parent = "WorldFrame", strata = "BACKGROUND", level = 0 },
	{ name = "no parent, WORLD 0", strata = "WORLD", level = 0 },
	{ name = "no parent, BACKGROUND 0", strata = "BACKGROUND", level = 0 },
	{ name = "a texture of WorldFrame's own (BACKGROUND layer)", texture = true },
}

local strip, label, run
local washes = {}

local function Where(frame)
	local okStrata, strata = pcall(frame.GetFrameStrata, frame)
	local okLevel, level = pcall(frame.GetFrameLevel, frame)
	return ("%s %s"):format(okStrata and tostring(strata) or "?", okLevel and tostring(level) or "?")
end

-- The nameplates up: how many, and each different strata+level seen on the
-- plates themselves and on their unit frames (where the name is).
local function Plates()
	local list = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
	local seen, order = {}, {}
	local function Note(text)
		if not seen[text] then
			seen[text] = true
			order[#order + 1] = text
		end
	end
	for _, plate in ipairs(list) do
		Note("plate " .. Where(plate))
		local unitFrame = plate.UnitFrame
		if type(unitFrame) == "table" and unitFrame.GetFrameStrata then
			Note("its UnitFrame " .. Where(unitFrame))
			local name = unitFrame.name
			local holder = type(name) == "table" and name.GetParent and name:GetParent()
			if holder and holder ~= unitFrame and holder.GetFrameStrata then
				Note("name's parent " .. Where(holder))
			end
		end
	end
	return ("%d plates: %s"):format(#list, #order > 0 and table.concat(order, ", ") or "none")
end

local function Wash(place)
	local wash = washes[place]
	if wash then return wash end
	if place.texture then
		wash = WorldFrame:CreateTexture(nil, "BACKGROUND")
	else
		local frame = CreateFrame("Frame", nil, place.parent and _G[place.parent] or nil)
		if place.strata then pcall(frame.SetFrameStrata, frame, place.strata) end
		pcall(frame.SetFrameLevel, frame, place.level)
		frame:EnableMouse(false)
		wash = frame:CreateTexture(nil, "BACKGROUND")
		wash.frame = frame
		frame:SetAllPoints(WorldFrame)
	end
	wash:SetAllPoints(wash.frame or WorldFrame)
	wash:SetColorTexture(1, 0.1, 0.1, 1)
	wash:SetBlendMode("MOD")
	washes[place] = wash
	return wash
end

local function HideAll()
	for _, wash in pairs(washes) do
		wash:Hide()
		if wash.frame then wash.frame:Hide() end
	end
end

local function Finish(text)
	run = nil
	HideAll()
	if strip then strip:Hide() end
	ns.Print(text)
end

local function Play(index, token)
	if run ~= token then return end
	local place = PLACES[index]
	if not place then
		Finish(("tintlayer: %d shots done, in the Screenshots folder."):format(#PLACES))
		return
	end
	HideAll()
	local got = "-"
	if place.parent or place.strata or place.texture then
		local ok, wash = pcall(Wash, place)
		if ok then
			if wash.frame then
				wash.frame:Show()
				got = Where(wash.frame)
			end
			wash:Show()
		else
			got = "failed: " .. tostring(wash)
		end
	end
	local text = ("tintlayer %d/%d: %s | got %s | %s | WorldFrame %s, UIParent %s | %s"):format(index, #PLACES, place.name,
		got, Plates(), Where(WorldFrame), Where(UIParent), ns.isRetail and "retail" or "classic")
	label:SetText(text)
	ns.Log("tintlayer", text)
	C_Timer.After(SETTLE, function()
		if run ~= token then return end
		Screenshot()
		C_Timer.After(AFTER, function() Play(index + 1, token) end)
	end)
end

function ns.TintLayerTest(text)
	if (text or ""):match("off") then
		if run then Finish("tintlayer: stopped.") else ns.Print("tintlayer: not running.") end
		return
	end
	if run then
		ns.Print("tintlayer: already running. /cine debug tintlayer off stops it.")
		return
	end
	if not strip then
		strip = CreateFrame("Frame", nil, UIParent)
		strip:SetFrameStrata("TOOLTIP")
		strip:SetPoint("TOPLEFT")
		strip:SetPoint("TOPRIGHT")
		strip:SetHeight(44)
		local back = strip:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0, 0, 0, 0.9)
		label = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", 10, -4)
		label:SetPoint("BOTTOMRIGHT", -10, 4)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(true)
	end
	strip:Show()
	ns.Print(("tintlayer: %d shots, about %d seconds. The screen turns red in most: hands off till it says done."):format(
		#PLACES, math.ceil(#PLACES * (SETTLE + AFTER))))
	run = {}
	Play(1, run)
end
