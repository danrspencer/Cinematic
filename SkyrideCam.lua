-- Skyriding Cam (skyrideCam, dev copy, retail): skyriding through the air,
-- the camera zooms all the way out so you can see where you're going, and
-- back to your own distance a moment after you land. It plays the built-in
-- Skyriding zoom camera script (CameraScripts.lua, made from this page's
-- settings; its runner's travel rules: steering doesn't stop it, scrolling
-- the zoom yourself does). "In the air" is the game's gliding info, on once
-- you've been up skyrideCamStart seconds and off once you've been down
-- skyrideCamLand (ns.SkyridingNow, CameraScripts.lua).
-- Where: its Show in row (Always ticked to start with: everywhere).
-- /cine debug skyride logs what the game says while you fly.
local _, ns = ...
local L = ns.L

-- (Only where there's skyriding: retail's gliding info.)
if not (ns.isRetail and C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then return end
ns.SKYRIDE_CAM = true -- (ProfileModules.lua's Cinema cameras turn it on where it's here)

local ROW_KEY = "skyride:cam"
ns.CINE_SHOW_SETTING[ROW_KEY] = "skyrideCamAlways"

-- Whether the camera may play now: the page on, and its Show in row here.
function ns.SkyrideCamOn()
	local db = ns.db
	if not (db and ns.Setting("skyrideCam")) then return false end
	if db.skyrideCamAlways then return true end
	local ok, here = pcall(ns.RowOnNow, ROW_KEY, false, true)
	return ok and here and true or false
end

function ns.CreateSkyrideCamPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Skyriding Cam"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["While you skyride through the air, the camera zooms all the way out so you can see where you're going."])
	local switch = kit.PageSwitch(content, "skyrideCam", L["Enable Page"],
		L["On: taking to the air on a skyriding mount zooms the camera out, and landing brings it back to your " ..
		"own distance. Steering with the mouse doesn't stop it; scrolling the zoom yourself does. It plays the " ..
		"Skyriding zoom camera script, made from the settings below."], intro)
	local function IfOn() return ns.Setting("skyrideCam") end
	local stack = kit.Stack(switch, "check")

	local header = stack:Header(content, L["Show in"])
	local lastRow = ns.ShowTable(content, header, {
		opts = { quiet = true, cam = true, anyFight = true }, underHeader = true,
		{ key = ROW_KEY, label = L["Skyriding Cam"], alwaysKey = "skyrideCamAlways",
			alwaysOn = function() return ns.GetDB().skyrideCamAlways end,
			setAlways = function(value) ns.GetDB().skyrideCamAlways = value end,
			alwaysTip = L["Wherever you skyride. (The other columns then have nothing to add.)"] },
	}, L["Skyriding Cam"])
	stack:Continue(lastRow, "label")

	stack:Header(content, L["Zoom"])
	local distance = stack:Add(kit.Slider(content, "skyrideCamDistance", L["Zoom out to"], 10, 39, 1,
		L["%d yards"]), "slider")
	kit.Tooltip(distance, L["How far out the camera goes. 39 is as far as the game allows, past your own " ..
		"max camera distance for the flight."])
	kit.GreyUnless(distance, IfOn)
	local zoomTime = stack:Add(kit.Slider(content, "skyrideCamZoomTime", L["Zoom out over"], 1, 10, 0.5,
		L["%.1f sec"]), "slider")
	kit.GreyUnless(zoomTime, IfOn)
	local backTime = stack:Add(kit.Slider(content, "skyrideCamBackTime", L["Back in over"], 0.5, 10, 0.5,
		L["%.1f sec"]), "slider")
	kit.Tooltip(backTime, L["How long the camera takes to come back to your own distance after you land."])
	kit.GreyUnless(backTime, IfOn)

	stack:Header(content, L["Timing"])
	local start = stack:Add(kit.Slider(content, "skyrideCamStart", L["Start after"], 0, 3, 0.25,
		L["%.2f sec"]), "slider")
	kit.Tooltip(start, L["How long you're in the air before the camera zooms out, so a hop doesn't start it."])
	kit.GreyUnless(start, IfOn)
	local land = stack:Add(kit.Slider(content, "skyrideCamLand", L["End after landing"], 0, 10, 0.5,
		L["%.1f sec"]), "slider")
	kit.Tooltip(land, L["How long you're on the ground before the camera comes back in, so touching down " ..
		"between flaps doesn't bounce it."])
	kit.GreyUnless(land, IfOn)

	stack:Header(content, L["CineMode"])
	kit.GreyUnless(stack:Add(kit.Check(content, "skyrideCine", L["CineMode while skyriding"],
		L["With \"Start in CineMode\" off (Cinematic's main page), skyriding brings CineMode on (the UI " ..
		"fades as your Show in rows say) until you land."]), "check"), IfOn)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Skyriding Cam")
end
