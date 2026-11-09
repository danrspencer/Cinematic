-- The Style hub's Minimap page: the minimap's own ring in the theme's color (the
-- game's art, turned grey and tinted, so its light, shadow and north point stay
-- just as the game draws them), with a little dark just inside it. The buttons
-- on it take the color too: their rings (the game's tracking border art, which
-- addon buttons use as well, and WoW Forever's dial and square buttons). Only
-- with a theme picked on General: with the game's look the minimap keeps the
-- game's. The zone's bar above it is the theme's panel: its shape, color and line.
--
-- Everything goes back to the game's own as soon as the page says so. A minimap
-- another addon made square or skins itself is left be.

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.mmStyle = true -- the page's switch
DEFAULTS.mmShade = true -- the dark just inside the ring
DEFAULTS.mmButtons = true -- the round buttons' rings in the theme's color
DEFAULTS.mmZoneBar = true -- the zone's bar as the theme's panel

-- The game's ring round the minimap, by client (WoW Forever's and retail's compass,
-- classic clients' border): whichever there are.
local GAME_RINGS = { "MinimapCompassTexture", "MinimapBorder" }
-- Addons that dress the minimap themselves, round or not.
local OTHER_SKINS = { "SexyMap", "EllesmereUIMinimap", "BasicMinimap" }
-- The round buttons' ring art: the game's tracking border, by file id or path.
local BUTTON_RING_ID = 136430
local BUTTON_RING_PATH = "minimap%-trackingborder"
-- Frames whose buttons sit on the minimap's edge.
local BUTTON_HOLDERS = { "Minimap", "MinimapCluster", "MinimapBackdrop", "GameTimeFrame" }
local SHADE_INNER = 114 / 128 -- (the shade's circle, of its size: Media/make_shape_art.py's MINIMAP_INNER)

local function Look()
	return ns.StyleLook("mmStyle")
end

local function OthersSkinIt()
	local shape = type(_G.GetMinimapShape) == "function" and _G.GetMinimapShape()
	if shape and shape ~= "ROUND" then return true end
	local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if not IsLoaded then return false end
	for _, name in ipairs(OTHER_SKINS) do
		if IsLoaded(name) then return true end
	end
	return false
end

-- The game's art we've hidden stays hidden: the game sets its alpha again. What
-- stands in for it (follows) takes the alpha it was given: the zone's bar fades
-- in CineMode by its art's alpha (Frames.lua's minimap header).
local hidden, hooked, follows = {}, {}, {}
local hiding = false
local function HideAgain(texture, alpha)
	if hiding or not hidden[texture] then return end
	local follower = follows[texture]
	if follower and type(alpha) == "number" and not (issecretvalue and issecretvalue(alpha)) then
		follower:SetAlpha(alpha)
	end
	hiding = true
	texture:SetAlpha(0)
	hiding = false
end
local function SetHidden(texture, hide)
	if type(texture) ~= "table" or type(texture.SetAlpha) ~= "function" then return end
	if hide then
		if not hidden[texture] then
			local alpha = texture:GetAlpha()
			hidden[texture] = (issecretvalue and issecretvalue(alpha)) and 1 or alpha
			if follows[texture] then follows[texture]:SetAlpha(hidden[texture]) end
		end
		if not hooked[texture] then
			hooked[texture] = true
			hooksecurefunc(texture, "SetAlpha", HideAgain)
		end
		HideAgain(texture)
	elseif hidden[texture] then
		local alpha = hidden[texture]
		hidden[texture] = nil
		texture:SetAlpha(type(alpha) == "number" and alpha or 1)
	end
end

-- The buttons' rings we've tinted, so they go back to the game's.
local tinted = {}
-- (The day/night dial's ring on WoW Forever, MinimapCluster.DielFrame: art of its own,
-- told by its atlas's name.)
local DIAL_RING_WORDS = { "border", "ring", "frame-cycle" }
-- (WoW Forever's square buttons by the minimap: the tracking button's back. The
-- calendar's and the tracking button's gold frames are one picture with what's in
-- them (the calendar, the magnifying glass), drawn in several layers: one tinted copy
-- cut to the frame goes over them all, so what's in them keeps its colors.)
local SQUARE_BUTTON_ATLASES = { "ui-hud-minimap-button" }
local FRAME_ONLY_ATLASES = { "ui-hud-minimap-calendar-button", "ui-hud-minimap-tracking-button" }
local function Plain(value)
	return not (issecretvalue and issecretvalue(value)) and value or nil
end
local function IsButtonRing(region, inDial)
	if type(region) ~= "table" or not region.GetObjectType then return false end
	local okType, kind = pcall(region.GetObjectType, region)
	if not (okType and kind == "Texture") then return false end
	local ok, file = pcall(region.GetTexture, region)
	file = ok and Plain(file)
	if file == BUTTON_RING_ID then return true end
	if type(file) == "string" and file:lower():find(BUTTON_RING_PATH) then return true end
	local okAtlas, atlas = pcall(function() return region.GetAtlas and region:GetAtlas() end)
	atlas = okAtlas and type(Plain(atlas)) == "string" and atlas:lower() or nil
	if atlas then
		for _, name in ipairs(SQUARE_BUTTON_ATLASES) do
			if atlas == name then return true end
		end
		for _, name in ipairs(FRAME_ONLY_ATLASES) do
			if atlas == name then return "frame" end
		end
	end
	if not inDial then return false end
	local name = atlas or (type(file) == "string" and file:lower()) or ""
	for _, word in ipairs(DIAL_RING_WORDS) do
		if name:find(word, 1, true) then return true end
	end
	return false
end
local function EachButtonRing(visit)
	local seen = {}
	local cluster = _G.MinimapCluster
	local dial = type(cluster) == "table" and cluster.DielFrame or nil
	-- (The addon compartment's button, "1": all its art is its frame.)
	local box = _G.AddonCompartmentFrame
	local function Look(frame, depth, inDial, inBox)
		if type(frame) ~= "table" or seen[frame] or not frame.GetRegions then return end
		seen[frame] = true
		inDial = inDial or frame == dial
		inBox = inBox or (box ~= nil and frame == box)
		local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
		for _, region in ipairs(okRegions and regions or {}) do
			local okType, kind = pcall(function() return region:GetObjectType() end)
			local found = inBox and okType and kind == "Texture" or IsButtonRing(region, inDial)
			if found then visit(region, found) end
		end
		if depth < 2 and frame.GetChildren then
			local okKids, kids = pcall(function() return { frame:GetChildren() } end)
			for _, kid in ipairs(okKids and kids or {}) do Look(kid, depth + 1, inDial, inBox) end
		end
	end
	Look(dial, 0)
	Look(box, 0)
	for _, name in ipairs(BUTTON_HOLDERS) do Look(_G[name], 0) end
end
-- A tinted copy of a button's art over it, cut to its frame (kind "frame").
-- (One per button, on top of all its layers, placed by the first of them showing.)
local copies = {}
local function FrameCopy(art)
	local owner = art:GetParent()
	local copy = copies[owner]
	if not copy then
		copy = owner:CreateTexture(nil, "OVERLAY", nil, 7)
		copy.mask = owner:CreateMaskTexture()
		copy.mask:SetTexture(ns.THEME_SQUARE_FRAME_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		copy:AddMaskTexture(copy.mask)
		copies[owner] = copy
	end
	copy:ClearAllPoints()
	copy:SetAllPoints(art)
	copy.mask:ClearAllPoints()
	copy.mask:SetAllPoints(art)
	return copy
end
local function TintButtons(color)
	for _, copy in pairs(copies) do copy:Hide() end
	if color then
		local r, g, b = math.min(1, color[1] * 1.25), math.min(1, color[2] * 1.25), math.min(1, color[3] * 1.25)
		local placed = {}
		EachButtonRing(function(ring, kind)
			if kind == "frame" then
				local owner = ring:GetParent()
				if placed[owner] then return end
				-- (Only by one showing: a button's pressed art waits hidden.)
				local okAtlas, atlas = pcall(function() return ring:GetAtlas() end)
				if not (okAtlas and type(Plain(atlas)) == "string") then return end
				local okShown, shown = pcall(function() return ring:IsShown() end)
				if okShown and Plain(shown) == false then return end
				placed[owner] = true
				local copy = FrameCopy(ring)
				copy:SetAtlas(atlas)
				copy:SetDesaturated(true)
				copy:SetVertexColor(r, g, b, 1)
				copy:Show()
				return
			end
			tinted[ring] = true
			ring:SetDesaturated(true)
			ring:SetVertexColor(r, g, b, 1)
		end)
		return
	end
	for ring in pairs(tinted) do
		ring:SetDesaturated(false)
		ring:SetVertexColor(1, 1, 1, 1)
	end
	tinted = {}
end

-- The zone's bar: WoW Forever's zone button's art, retail's BorderTop, classic
-- clients' MinimapBorderTop.
local function ZoneBarArt()
	local cluster = _G.MinimapCluster
	local button = type(cluster) == "table" and cluster.ZoneTextButton or _G.MinimapZoneTextButton
	if type(button) == "table" and button.StateTexture then return button.StateTexture, button end
	if type(cluster) == "table" and cluster.BorderTop then return cluster.BorderTop, button end
	return _G.MinimapBorderTop, button
end
local zoneBar
local ZONE_CORNER = 8 -- (the panel shape's corners: the bar's short)
local ZONE_GAP = 2 -- (between the bar and the buttons at its ends)
-- (The game's bar runs on under the buttons at its ends, the calendar and the
-- tracking button, hidden by them; ours, with its line and shaped corners, would show
-- past them: it stops short of them.)
local function Edge(frame, side)
	if type(frame) ~= "table" or not frame.GetLeft then return nil end
	local ok, value = pcall(side == "left" and frame.GetLeft or frame.GetRight, frame)
	return ok and type(value) == "number" and not (issecretvalue and issecretvalue(value)) and value or nil
end
local function FitZoneBar(art)
	local cluster = _G.MinimapCluster
	local left, right = Edge(art, "left"), Edge(art, "right")
	local inLeft, inRight = 0, 0
	if left and right then
		local tracking = type(cluster) == "table" and cluster.Tracking
		local trackRight = Edge(tracking, "right")
		if trackRight and trackRight > left and trackRight < right then inLeft = trackRight + ZONE_GAP - left end
		local calendarLeft = Edge(_G.GameTimeFrame, "left")
		if calendarLeft and calendarLeft < right and calendarLeft > left then inRight = right - calendarLeft + ZONE_GAP end
	end
	zoneBar:ClearAllPoints()
	zoneBar:SetPoint("TOPLEFT", art, "TOPLEFT", inLeft, 0)
	zoneBar:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -inRight, 0)
end
local function DressZoneBar(on)
	local art, button = ZoneBarArt()
	if type(art) ~= "table" or not art.GetParent then return end
	if on and not zoneBar then
		-- (Under the zone's button, so its words show over it.)
		local holder = _G.MinimapCluster or art:GetParent()
		zoneBar = CreateFrame("Frame", nil, holder)
		zoneBar:SetAllPoints(art)
		zoneBar:EnableMouse(false)
		local below = type(button) == "table" and button.GetFrameLevel and button:GetFrameLevel() or holder:GetFrameLevel() + 1
		zoneBar:SetFrameLevel(math.max(0, below - 1))
		zoneBar.themeSliceCorner = ZONE_CORNER
		zoneBar.back = zoneBar:CreateTexture(nil, "BACKGROUND", nil, -7)
		zoneBar.back:SetAllPoints()
		zoneBar.edges = ns.MakeStyleEdges(zoneBar, "BORDER")
		follows[art] = zoneBar
	end
	SetHidden(art, on)
	if not zoneBar then return end
	zoneBar:SetShown(on)
	if not on then return end
	FitZoneBar(art)
	local back, edge = ns.ThemePanel()
	back = back or { 0.05, 0.05, 0.06, 0.85 }
	edge = edge or ns.ThemeRing() or { 0.5, 0.5, 0.5, 1 }
	local shaped = ns.DressThemeSlice(zoneBar, back[1], back[2], back[3], back[4] or 1, edge[1], edge[2], edge[3], 1)
	zoneBar.back:SetShown(not shaped)
	zoneBar.edges:SetShown(not shaped)
	if not shaped then
		ns.DressThemeGrain(zoneBar.back)
		zoneBar.back:SetVertexColor(back[1], back[2], back[3], back[4] or 1)
		ns.DressStyleEdges(zoneBar.edges, 1, edge[1], edge[2], edge[3], 1, false)
	end
end

-- The game's ring, grey and tinted (as the buttons' are, a little brighter than the
-- theme's color, which the grey darkens), or back as it was.
-- Grey, the game's frame is darker than our portraits' rings: a copy of it added
-- over it (ADD) brings it up to theirs, turning with it as the map does.
local ringsTinted, lifts = {}, {}
local RING_LIFT = 0.28
local function Lift(ring)
	local lift = lifts[ring]
	if lift then return lift end
	local okAtlas, atlas = pcall(function() return ring.GetAtlas and ring:GetAtlas() end)
	if not (okAtlas and type(Plain(atlas)) == "string") then return nil end
	local layer, sub = ring:GetDrawLayer()
	lift = ring:GetParent():CreateTexture(nil, layer or "ARTWORK", nil, math.min(7, (sub or 0) + 1))
	lift:SetAllPoints(ring)
	lift:SetAtlas(atlas)
	lift:SetDesaturated(true)
	lift:SetBlendMode("ADD")
	if ring.GetRotation and lift.SetRotation then
		local okTurn, turn = pcall(ring.GetRotation, ring)
		if okTurn and type(Plain(turn)) == "number" then lift:SetRotation(turn) end
		hooksecurefunc(ring, "SetRotation", function(_, angle)
			if type(Plain(angle)) == "number" then lift:SetRotation(angle) end
		end)
	end
	lifts[ring] = lift
	return lift
end
local function TintRings(color)
	for _, name in ipairs(GAME_RINGS) do
		local ring = _G[name]
		if type(ring) == "table" and ring.SetDesaturated then
			if color then
				ringsTinted[ring] = true
				local r, g, b = math.min(1, color[1] * 1.25), math.min(1, color[2] * 1.25), math.min(1, color[3] * 1.25)
				ring:SetDesaturated(true)
				ring:SetVertexColor(r, g, b, 1)
				local lift = Lift(ring)
				if lift then
					lift:SetVertexColor(r, g, b, RING_LIFT)
					lift:Show()
				end
			elseif ringsTinted[ring] then
				ringsTinted[ring] = nil
				ring:SetDesaturated(false)
				ring:SetVertexColor(1, 1, 1, 1)
				if lifts[ring] then lifts[ring]:Hide() end
			end
		end
	end
end

-- The dark just inside the ring, its circle on the map's edge.
local shade
local function SizeShade()
	local map = _G.Minimap
	if not (shade and map) then return end
	local wide = map:GetWidth()
	if type(wide) ~= "number" or (issecretvalue and issecretvalue(wide)) or wide <= 0 then return end
	shade:SetSize(wide / SHADE_INNER, wide / SHADE_INNER)
end

function ns.RefreshMinimapStyle()
	local map = _G.Minimap
	if type(map) ~= "table" or not map.GetWidth then return end
	local color = ns.StyleOn("mmStyle") and ns.ThemeRing()
	local on = color and not OthersSkinIt() and true or false
	TintRings(on and color or nil)
	TintButtons(on and Look().mmButtons ~= false and color or nil)
	DressZoneBar(on and Look().mmZoneBar ~= false)
	local shaded = on and Look().mmShade ~= false
	if shaded and not shade then
		local holder = CreateFrame("Frame", nil, map)
		holder:SetAllPoints()
		holder:SetFrameLevel(map:GetFrameLevel() + 1)
		holder:EnableMouse(false)
		shade = holder:CreateTexture(nil, "ARTWORK")
		shade:SetPoint("CENTER")
		shade:SetTexture(ns.THEME_MINIMAP_SHADE)
		ns.ThemeNoSnap(shade)
		map:HookScript("OnSizeChanged", SizeShade)
	end
	if shade then
		shade:SetShown(shaded)
		SizeShade()
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function()
	ns.RefreshMinimapStyle()
	-- (Other addons' minimap shape and buttons, made a moment later.)
	C_Timer.After(1, function() ns.RefreshMinimapStyle() end)
	C_Timer.After(5, function() ns.RefreshMinimapStyle() end)
end)

-- For /cine debug minimapstyle: what this client's minimap has, and our state.
function ns.ReportMinimapStyle()
	local map = _G.Minimap
	print(("Cinematic: Minimap Style: page %s, theme ring %s, others skin it %s, shape %s, game %s"):format(
		tostring(ns.StyleOn("mmStyle")), tostring(ns.ThemeRing() ~= nil), tostring(OthersSkinIt()),
		tostring(type(_G.GetMinimapShape) == "function" and _G.GetMinimapShape() or "none"),
		tostring(select(4, GetBuildInfo()))))
	if map then
		print(("map %s x %s, level %s, strata %s"):format(tostring(map:GetWidth()), tostring(map:GetHeight()),
			tostring(map:GetFrameLevel()), tostring(map:GetFrameStrata())))
	end
	for _, name in ipairs(GAME_RINGS) do
		local art = _G[name]
		local okAtlas, atlas = pcall(function() return art and art.GetAtlas and art:GetAtlas() end)
		print(("  %s: %s%s"):format(name, art and "yes" or "no", art and (", alpha " .. tostring(art:GetAlpha())
			.. ", atlas " .. tostring(okAtlas and atlas) .. (ringsTinted[art] and ", tinted by us" or "")) or ""))
	end
	if shade then
		print(("shade shown %s, size %s"):format(tostring(shade:IsShown()), tostring(shade:GetWidth())))
	end
	local rings = 0
	EachButtonRing(function() rings = rings + 1 end)
	print(("button rings found %d, tinted %d"):format(rings, (function()
		local count = 0
		for _ in pairs(tinted) do count = count + 1 end
		return count
	end)()))
	-- (The day/night dial's parts, WoW Forever's MinimapCluster.DielFrame, to find its ring.)
	local cluster = _G.MinimapCluster
	local dial = type(cluster) == "table" and cluster.DielFrame or nil
	if not (dial and dial.GetRegions) then return print("  no DielFrame") end
	local function Dump(frame, label, depth)
		for i, region in ipairs({ frame:GetRegions() }) do
			local okFile, file = pcall(function() return region.GetTexture and region:GetTexture() end)
			local okAtlas, atlas = pcall(function() return region.GetAtlas and region:GetAtlas() end)
			print(("  %s #%d %s: %s %s%s"):format(label, i, tostring(region:GetObjectType()),
				tostring(okFile and file), tostring(okAtlas and atlas), tinted[region] and " (tinted)" or ""))
		end
		if depth < 2 then
			for i, kid in ipairs({ frame:GetChildren() }) do Dump(kid, label .. "." .. i, depth + 1) end
		end
	end
	Dump(dial, "DielFrame", 0)
	-- (The square buttons: every texture, tinted or copied or not.)
	for label, frame in pairs({ Tracking = cluster and cluster.Tracking, Calendar = _G.GameTimeFrame,
		AddOns = _G.AddonCompartmentFrame }) do
		if type(frame) == "table" and frame.GetRegions then
			local function Square(f, name, depth)
				for i, region in ipairs({ f:GetRegions() }) do
					if region:GetObjectType() == "Texture" then
						local okFile, file = pcall(function() return region:GetTexture() end)
						local okAtlas, atlas = pcall(function() return region:GetAtlas() end)
						print(("  %s #%d: %s %s, shown %s%s%s"):format(name, i, tostring(okFile and file),
							tostring(okAtlas and atlas), tostring(region:IsShown()), tinted[region] and " (tinted)" or "",
							copies[f] and copies[f]:IsShown() and " (frame copied)" or ""))
					end
				end
				if depth < 2 then
					for i, kid in ipairs({ f:GetChildren() }) do Square(kid, name .. "." .. (kid:GetName() or i), depth + 1) end
				end
			end
			Square(frame, label, 0)
		else
			print("  no " .. label)
		end
	end
	-- (And the art round the minimap left as it is: a frame to color that isn't found yet.)
	local function Others(frame, label, depth)
		local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
		for i, region in ipairs(okRegions and regions or {}) do
			local okAtlas, atlas = pcall(function() return region.GetAtlas and region:GetAtlas() end)
			if okAtlas and type(atlas) == "string" and not tinted[region] then
				print(("  %s #%d: %s"):format(label, i, atlas))
			end
		end
		if depth < 2 then
			local okKids, kids = pcall(function() return { frame:GetChildren() } end)
			for i, kid in ipairs(okKids and kids or {}) do
				Others(kid, label .. "." .. (kid.GetName and kid:GetName() or i), depth + 1)
			end
		end
	end
	if cluster then Others(cluster, "Cluster", 0) end
end

-- The page itself.
function ns.CreateMinimapStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Minimap Style"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["The minimap's ring, its buttons and the zone's bar in your theme's colors. Only with a theme picked " ..
		"on General. A minimap another addon makes square or dresses itself keeps its own look."])

	local function Changed() ns.RefreshMinimapStyle() end

	local switch = kit.PageSwitch(content, "mmStyle", L["Enable Page"],
		L["On: the minimap's ring and buttons take the theme's color. Off: the game's own."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "mmStyle")
	stack:Header(content, L["Look"])
	rows.Check("mmShade", L["Shade inside the edge"], L["A little dark just inside the ring, so the map sits " ..
		"back in it."])
	rows.Check("mmButtons", L["Color the buttons' rings"], L["The rings round the round buttons on the minimap " ..
		"(tracking, mail, addon buttons...) in the theme's color too."])
	rows.Check("mmZoneBar", L["Zone bar"], L["The bar with the zone's name above the minimap in the theme's panel " ..
		"look: its shape, color and line."])

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Minimap Style", L["Minimap Style"])
end
