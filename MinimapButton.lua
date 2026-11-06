-- Cinematic minimap button: left-click for a quick menu, right-click for the
-- settings, drag to move it around the minimap's edge.
--
-- It's the minimap's child, like LibDBIcon's buttons, so addons that gather
-- minimap buttons find it (they scan the minimap's children, and our name
-- passes their checks). It shrinks and parks with the minimap while faded;
-- hovering the map's empty spot still brings it back (see ShrinkEntry).
-- Gathered, it's the gatherer's: left where it's put, and no longer faded with
-- the map (ns.MinimapButtonGathered), or it'd be invisible in their popout.
local _, ns = ...
local L = ns.L

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local EDGE_OFFSET = 10 -- how far outside the minimap's rim the button sits
local button
-- EllesmereUI's minimap keeps the button on the minimap and lays it out in its
-- drawer, so it's anchored once, then left alone (and still fades with the map).
local inDrawer

local function Print(msg)
	ns.Print(msg)
end

-- The visions: while one is in use (doing something now, not just switched
-- on), the button glows in its colour, and the menu and tooltip list it with
-- a link to its page, with its icon (as the vision wheel has them). Not
-- with the main page's Minimap Glow Helper (minimapHelper) unticked.
-- active: its file's ns function saying so. trim: an icon's edge cut off.
local VISIONS = {
	{ label = "Heal Vision", page = "Heal Vision", active = "HealVisionActive", color = { 0.35, 1, 0.45 },
		icon = "Interface\\Icons\\Spell_Holy_FlashHeal", trim = true },
	{ label = "Quest Vision", page = "Quest Vision", active = "QuestVisionActive", color = { 1, 0.82, 0 },
		icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", trim = true },
	{ label = "Duel Vision", page = "Duel Vision", active = "DuelVisionActive", color = { 1, 0.35, 0.3 },
		icon = "Interface\\Icons\\Ability_DualWield", trim = true },
	{ label = "Roll Vision", page = "Roll Vision", active = "RollVisionActive", color = { 0.45, 0.7, 1 },
		icon = "Interface\\Icons\\INV_Misc_Dice_01", trim = true },
	{ label = "Vitals Vision", page = "Vitals Vision", active = "VitalsVisionActive", color = { 1, 0.25, 0.4 },
		icon = "Interface\\Icons\\Spell_Shadow_LifeDrain02", trim = true },
}
local GLOW_EVERY = 0.5 -- seconds between looks at which are in use
local inUse = {} -- the visions in use at the last look

-- A vision's line in the menu and tooltip (text: its label, or a line with
-- it): its icon, then the text in its colour.
local function VisionText(vision, text)
	local icon = vision.trim and "|T%s:16:16:0:0:64:64:5:59:5:59|t " or "|T%s:16:16|t "
	local function Byte(value) return math.floor(value * 255 + 0.5) end
	local color = vision.color
	return icon:format(vision.icon) .. ("|cff%02x%02x%02x%s|r"):format(Byte(color[1]), Byte(color[2]),
		Byte(color[3]), text)
end

-- The camera running now (one at a time), as a vision-like line for the menu
-- and tooltip, or nil: a script playing, else our camera mode by its script
-- (ns.activeCam's keys, some not their script's id). Not with the main
-- page's Minimap Glow Helper (minimapHelper) unticked.
local CAM_SCRIPT = { idle = "afk", chatcam = "chat" }
local CAMERA_COLOR = { 0.55, 0.8, 1 }
local function CameraInUse()
	if not ns.Setting("minimapHelper") then return nil end
	local script = ns.PlayingCameraScript and ns.PlayingCameraScript()
	local cam = ns.activeCam
	if not script and cam and ns.FindCameraScript then
		script = ns.FindCameraScript(CAM_SCRIPT[cam] or cam)
	end
	if not script then return nil end
	return { label = script.name, id = script.id, color = CAMERA_COLOR, trim = true,
		icon = ns.CameraIcon and ns.CameraIcon(script) or ICON }
end

local function UpdateInUse()
	wipe(inUse)
	for _, vision in ipairs(ns.Setting("minimapHelper") and VISIONS or {}) do
		local Active = ns[vision.active]
		if Active then
			local ok, active = pcall(Active)
			if ok and active then
				inUse[#inUse + 1] = vision
			end
		end
	end
	local glow = button.glow
	local first = inUse[1]
	if first then
		if glow.vision ~= first then
			glow.vision = first
			glow.texture:SetVertexColor(first.color[1], first.color[2], first.color[3])
		end
		if not glow:IsShown() then
			glow:Show()
			glow.pulse:Play()
		end
	elseif glow:IsShown() then
		glow.pulse:Stop()
		glow:Hide()
	end
end

-- Whether one quarter of the minimap (vert "TOP"/"BOTTOM", horiz "LEFT"/"RIGHT")
-- is round, from GetMinimapShape: the global that minimap addons (ElvUI and
-- the like) set for a square map. "CORNER-X" rounds only corner X, "SIDE-X"
-- the two corners on side X, "TRICORNER-X" all but the one opposite X.
local function QuarterIsRound(vert, horiz)
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		return false
	end
	local kind, which = tostring(shape):match("^(%u+)%-(%u+)$")
	if kind == "CORNER" then
		return which == vert .. horiz
	elseif kind == "SIDE" then
		return which == vert or which == horiz
	elseif kind == "TRICORNER" then
		return (which:find(vert, 1, true) or which:find(horiz, 1, true)) ~= nil
	end
	return true
end

-- The button's offset from the minimap's center at the saved angle: on the
-- circle in a round quarter, on the square's edge in a square one.
local function RimOffset(angle, halfWidth, halfHeight)
	local x, y = math.cos(angle), math.sin(angle)
	if QuarterIsRound(y > 0 and "TOP" or "BOTTOM", x < 0 and "LEFT" or "RIGHT") then
		return x * halfWidth, y * halfHeight
	end
	local stretch = 1 / math.max(math.abs(x), math.abs(y)) -- out from the circle to the square
	return x * stretch * halfWidth, y * stretch * halfHeight
end

local function Place()
	local db = ns.GetDB()
	if not button or not db then
		return
	end
	local x, y = RimOffset(math.rad(db.minimapAngle),
		Minimap:GetWidth() / 2 + EDGE_OFFSET, Minimap:GetHeight() / 2 + EDGE_OFFSET)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Whether the button is ours to place: on the minimap's rim, not in a drawer
-- or another addon's collection.
local function OnRim()
	return button ~= nil and not inDrawer and button:GetParent() == Minimap
end

-- Whether another addon took the button off the minimap (see the top).
function ns.MinimapButtonGathered()
	return button ~= nil and not inDrawer and button:GetParent() ~= Minimap
end

local function UpdateIcon()
	local db = ns.GetDB()
	local active = db.enabled and not ns.GetSnoozeLeft()
	button.icon:SetDesaturated(not active)
	-- (Not in gamepad mode with hideMinimapButtonGamepad: clicking it there
	-- tends to freeze WoW Forever.)
	local shown = db.minimapButton and not (db.hideMinimapButtonGamepad and ns.IsGamePadOn())
	if shown ~= button.wanted then
		-- Only on a change, and with Show/Hide, which addons gathering the
		-- button follow: they hide it themselves too.
		button.wanted = shown
		if shown then button:Show() else button:Hide() end
	end
end

local function FormatTime(seconds)
	if seconds == math.huge then
		return L["until reload"]
	end
	return (L["%d:%02d left"]):format(math.floor(seconds / 60), math.floor(seconds % 60))
end

local MENU_MARGIN = 12 -- pixels between the menu and the screen edges

local function KeepOffEdges(menu)
	if not menu:IsShown() then
		return
	end
	local left, bottom, width, height = menu:GetRect()
	if not left then
		return
	end
	local scale = menu:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local screenW, screenH = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
	local dx, dy = 0, 0
	if left + width > screenW - MENU_MARGIN then dx = screenW - MENU_MARGIN - (left + width) end
	if left + dx < MENU_MARGIN then dx = MENU_MARGIN - left end
	if bottom < MENU_MARGIN then dy = MENU_MARGIN - bottom end
	if bottom + height + dy > screenH - MENU_MARGIN then dy = screenH - MENU_MARGIN - (bottom + height) end
	if dx ~= 0 or dy ~= 0 then
		menu:ClearAllPoints()
		-- (Offsets are in the menu's own scale, like its rect.)
		menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + dx, bottom + dy)
	end
end

local function ShowMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		-- No menu system on this client: just toggle.
		ns.SetEnabled(not ns.GetDB().enabled)
		UpdateIcon()
		return
	end
	local menu = ns.ContextMenu(owner, function(_, root)
		local db = ns.GetDB()
		-- (The camera in use first, a link to its tab on the Cameras page.)
		local camera = CameraInUse()
		if camera then
			root:CreateTitle(L["Cameras in use"])
			root:CreateButton(VisionText(camera, camera.label), function()
				if ns.ShowCameraTab then ns.ShowCameraTab(camera.id) else ns.OpenOptions("Cameras") end
			end)
			root:CreateDivider()
		end
		-- (Then the visions in use, each a link to its page.)
		UpdateInUse()
		if inUse[1] then
			root:CreateTitle(L["Visions in use"])
			for _, vision in ipairs(inUse) do
				local page = vision.page
				root:CreateButton(VisionText(vision, L[vision.label]), function() ns.OpenOptions(page) end)
			end
			root:CreateDivider()
		end
		root:CreateTitle("Cinematic")
		root:CreateCheckbox(L["Enable Cinematic"], function() return db.enabled end, function()
			ns.SetEnabled(not db.enabled)
			UpdateIcon()
		end)
		-- (Ticked whenever the menu is open: unticking hides the button.)
		root:CreateCheckbox(L["Show minimap button"], function() return db.minimapButton end, function()
			db.minimapButton = false
			UpdateIcon()
			Print(L["minimap button hidden. Bring it back with /cine button or the " ..
				"\"Show minimap button\" option."])
		end)
		root:CreateDivider()
		-- (A frame later: the menu's own click is done with by then.)
		root:CreateButton(L["Why is it showing?"], function() C_Timer.After(0, ns.ToggleInspect) end)
		root:CreateButton(L["Settings"], ns.OpenOptions)
	end)
	-- The menu opens at the cursor and is only kept on screen; keep it a little
	-- way off the edges too. (Once it has its size, a frame later.)
	if menu and menu.GetRect then
		C_Timer.After(0, function() KeepOffEdges(menu) end)
	end
end

local function OnEnter(self)
	local canDrag = self == button and OnRim()
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Cinematic")
	local db = ns.GetDB()
	local left = ns.GetSnoozeLeft()
	-- (No profile picked yet: Cinematic does nothing, and a click opens the welcome window.)
	if not ns.ProfileChosen() then
		GameTooltip:AddLine(L["No profile yet"], 1, 0.5, 0)
		GameTooltip:AddLine(L["Click: pick a profile"], 1, 1, 1)
		if canDrag then
			GameTooltip:AddLine(L["Drag: move"], 1, 1, 1)
		end
		GameTooltip:Show()
		return
	end
	if not db.enabled then
		GameTooltip:AddLine(L["Off"], 1, 0.3, 0.3)
	elseif left then
		GameTooltip:AddLine(L["Paused, %s"]:format(FormatTime(left)), 1, 0.8, 0.2)
	else
		GameTooltip:AddLine(L["On"], 0.3, 1, 0.3)
	end
	local camera = CameraInUse()
	if camera then
		GameTooltip:AddLine(VisionText(camera, L["%s in use"]:format(camera.label)))
	end
	for _, vision in ipairs(inUse) do
		GameTooltip:AddLine(VisionText(vision, L["%s in use"]:format(L[vision.label])))
	end
	GameTooltip:AddLine(L["Left-click: options"], 1, 1, 1)
	GameTooltip:AddLine(L["Right-click: settings"], 1, 1, 1)
	if canDrag then
		GameTooltip:AddLine(L["Drag: move"], 1, 1, 1)
	end
	GameTooltip:Show()
end

local function OnClick(owner, mouseButton)
	GameTooltip:Hide()
	if not ns.ProfileChosen() then
		ns.ShowWelcome()
	elseif mouseButton == "RightButton" then
		ns.OpenOptions()
	else
		ShowMenu(owner)
	end
end

-- Dragging moves the button around the minimap's rim.
local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	if not mx then
		return
	end
	local scale = Minimap:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = x / scale, y / scale
	ns.GetDB().minimapAngle = math.deg(math.atan2(y - my, x - mx))
	Place()
end

local function Create()
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	inDrawer = isLoaded("EllesmereUIMinimap") and true or false
	button = CreateFrame("Button", "CinematicMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFixedFrameStrata(true)
	button:SetFrameLevel(8)
	button:SetFixedFrameLevel(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if not inDrawer then -- (EllesmereUI places it: dragging would pull it out of the drawer)
		button:RegisterForDrag("LeftButton")
	end
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(24, 24)
	background:SetPoint("CENTER")

	-- (Centred in the button: at 50 the border's ring centres on it too.)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetTexture(ICON)
	button.icon:SetSize(18, 18)
	button.icon:SetPoint("CENTER")
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT")

	-- The glow while a vision is in use: a pulsing light over the icon and
	-- rim, in the vision's colour. (The pulse is on a frame of its own: a
	-- texture's vertex colour alpha is its alpha.)
	local glow = CreateFrame("Frame", nil, button)
	glow:SetAllPoints()
	glow:Hide()
	glow.texture = glow:CreateTexture(nil, "OVERLAY")
	glow.texture:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	glow.texture:SetBlendMode("ADD")
	glow.texture:SetSize(38, 38)
	glow.texture:SetPoint("CENTER", button.icon, "CENTER")
	glow.pulse = glow:CreateAnimationGroup()
	glow.pulse:SetLooping("BOUNCE")
	local fade = glow.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.9)
	fade:SetSmoothing("IN_OUT")
	button.glow = glow

	button:SetScript("OnClick", OnClick)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		ns.SetOnUpdate(self, OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		ns.SetOnUpdate(self, nil)
	end)
	-- (A timer of its own: the drag has the button's OnUpdate.)
	C_Timer.NewTicker(GLOW_EVERY, function()
		if button:IsVisible() or glow:IsShown() then
			UpdateInUse()
		end
	end)

	Place()
	UpdateIcon()
end

-- Called by Core: at login, and on its regular scan so the button follows the
-- map's shape if an addon changes it (and the icon catches a pause running out).
function ns.UpdateMinimapButton()
	if not button then
		Create()
	elseif OnRim() then
		Place()
	end
	UpdateIcon()
end

function ns.ToggleMinimapButton()
	local db = ns.GetDB()
	db.minimapButton = not db.minimapButton
	ns.UpdateMinimapButton()
	Print(db.minimapButton and L["minimap button shown"] or L["minimap button hidden"])
end

-- The game's addon compartment (retail and WoW Forever; the .toc names these):
-- the same clicks and tooltip, for when the button's hidden or gathered away.
-- Not in gamepad mode with hideMinimapButtonGamepad: the button's hidden there
-- as clicking it tends to freeze WoW Forever, and this would open the same.
function Cinematic_OnCompartmentClick(_, mouseButton)
	local db = ns.GetDB()
	if db.hideMinimapButtonGamepad and ns.IsGamePadOn() then
		Print(L["not available in gamepad mode: use /cine instead."])
		return
	end
	-- (A frame later: the compartment's own menu is closing. UIParent: that
	-- menu's button goes with it.)
	C_Timer.After(0, function() OnClick(UIParent, mouseButton) end)
end

function Cinematic_OnCompartmentEnter(_, frame)
	OnEnter(frame)
end

function Cinematic_OnCompartmentLeave()
	GameTooltip:Hide()
end
