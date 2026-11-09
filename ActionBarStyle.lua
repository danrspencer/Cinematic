-- The Style hub's Action Bars page: how the game's action buttons look. Their
-- outline (the game's, none, a dark line, the class color or a color of your
-- own), their shape (the game's, square or round) and the background of empty
-- slots. Bars 1 to 8, pet and stance buttons, and the gamepad bar on WoW
-- Forever. Other addons' bars are left alone, and so are the game's while
-- Dominos (it reuses them) or Masque (it skins them) is on.
--
-- Only the buttons' textures change, so nothing here touches what they do, but
-- the frames we add to them are made out of a fight. The game's art is hidden
-- by alpha, not removed: it comes back as soon as the page says so.

local ADDON_NAME, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.abStyle = true    -- the page's switch (off: these defaults, whatever it's set to)
DEFAULTS.abEdge = "game"   -- the outline: "game", "none", "thin", "thick", "colored" (the class's) or "custom"
DEFAULTS.abEdgeSize = 2    -- ...Custom's thickness
DEFAULTS.abEdgeR, DEFAULTS.abEdgeG, DEFAULTS.abEdgeB = 0.1, 0.1, 0.1
DEFAULTS.abShape = "game"  -- the shape: "game", "square" or "round"
DEFAULTS.abSlots = true    -- the game's background on empty slots

local RING = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\ActionRing" -- (1 to 10: Media/make_action_rings.py)
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- (a round mask every client has)
local SQUARE_SWIPE = "Interface\\Buttons\\WHITE8X8"
local MAX_RING = 10
local GAME_GRAY = 0.4 -- (the outline with the game's color on a shape of ours)
local CLASS_THICKNESS = 2

local BARS = {
	{ "ActionButton", 12 }, { "MultiBarBottomLeftButton", 12 }, { "MultiBarBottomRightButton", 12 },
	{ "MultiBarRightButton", 12 }, { "MultiBarLeftButton", 12 }, { "MultiBar5Button", 12 },
	{ "MultiBar6Button", 12 }, { "MultiBar7Button", 12 }, { "BonusActionButton", 12 },
	{ "PetActionButton", 10 }, { "StanceButton", 10 }, { "ShapeshiftButton", 10 },
}

local function Look()
	return ns.StyleLook("abStyle")
end

-- Addons that do the game's buttons' look themselves.
local function OthersSkinThem()
	local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return IsLoaded and (IsLoaded("Dominos") or IsLoaded("Masque")) and true or false
end

-- What the page says, worked out once for all the buttons. own: our art, not
-- the game's. Any outline of ours needs a clean square under it, so the game's
-- shape only stays with the game's outline; the game's outline on a shape of
-- ours is a thin gray line, as its art doesn't fit.
local function Plan()
	local look = Look()
	local kind, size, r, g, b = ns.StyleBorder(look, "abEdge")
	if kind == "colored" then
		local _, class = UnitClass("player")
		local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		kind, size = "line", CLASS_THICKNESS
		r, g, b = color and color.r or 1, color and color.g or 1, color and color.b or 1
	end
	local own = look.abShape == "square" or look.abShape == "round" or kind ~= "game"
	if own and kind == "game" then
		kind, size, r, g, b = "line", 1, GAME_GRAY, GAME_GRAY, GAME_GRAY
	end
	return { own = own, round = own and look.abShape == "round", line = kind == "line", size = size,
		r = r, g = g, b = b, slots = look.abSlots ~= false }
end

-- The art we've hidden stays hidden: the game sets alpha on it, and on classic
-- clients the alpha in SetVertexColor too (empty slots at half).
local hidden = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local hiding = false
local function HideAgain(texture)
	if hiding or not hidden[texture] then return end
	hiding = true
	texture:SetAlpha(0)
	hiding = false
end
local function SetHidden(texture, hide)
	if not texture then return end
	if hide and not hooked[texture] then
		hooked[texture] = true
		hooksecurefunc(texture, "SetAlpha", HideAgain)
		hooksecurefunc(texture, "SetVertexColor", HideAgain)
	end
	if hide == (hidden[texture] or false) then return end
	hidden[texture] = hide or nil
	texture:SetAlpha(hide and 0 or 1)
end

-- A button's parts, found once. (A table of ours, not fields on the button:
-- the game's buttons are secure, and writing on them taints.)
local parts = setmetatable({}, { __mode = "k" })
local function Parts(button)
	local part = parts[button]
	if part then return part end
	local name = button:GetName()
	local icon = button.icon or (name and _G[name .. "Icon"])
	if not icon then return end
	part = {
		icon = icon, gameMask = button.IconMask, gameMaskOn = button.IconMask ~= nil,
		cooldown = button.cooldown or (name and _G[name .. "Cooldown"]),
		backs = {}, roundOn = {},
	}
	part.floating = name and _G[name .. "FloatingBG"] or nil
	for _, back in ipairs({ button.SlotBackground or false, button.SlotArt or false, part.floating or false }) do
		if back then part.backs[#part.backs + 1] = back end
	end
	parts[button] = part
	return part
end

-- The art that shows over a round button and needs its corners cut too.
local function RoundArt(button, part)
	local list = { part.icon, part.ground or false }
	for _, texture in ipairs({
		button.GetPushedTexture and button:GetPushedTexture() or false,
		button.GetHighlightTexture and button:GetHighlightTexture() or false,
		button.GetCheckedTexture and button:GetCheckedTexture() or false,
		button.Flash or false, button.Border or false, button.NewActionTexture or false,
		button.SpellHighlightTexture or false, button.SlotBackground or false,
	}) do
		if texture and texture.AddMaskTexture then list[#list + 1] = texture end
	end
	for i = #list, 1, -1 do
		if not list[i] then table.remove(list, i) end
	end
	return list
end

-- (own: a square of ours has a mask too, a plain one. Bar 1's icons went missing
-- behind the slot art with no mask on them at all, and only those: with one, as
-- the game's own look and round both have, they draw.)
-- The game's casting effects are square frames of their own over the button, which no
-- mask of ours reaches: on a round button they show past its edge, so they go.
local CAST_FX = { "SpellCastAnimFrame", "TargetReticleAnimFrame", "InterruptDisplay", "CooldownFlash" }
local fxHidden, fxHooked = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local function KeepFxHidden(frame)
	if fxHidden[frame] and not hiding then
		hiding = true
		frame:SetAlpha(0)
		hiding = false
	end
end
local function SetCastFx(button, hide)
	for _, key in ipairs(CAST_FX) do
		local frame = button[key]
		if frame and frame.SetAlpha then
			if hide and not fxHooked[frame] then
				fxHooked[frame] = true
				hooksecurefunc(frame, "SetAlpha", KeepFxHidden)
			end
			if hide ~= (fxHidden[frame] or false) then
				fxHidden[frame] = hide or nil
				frame:SetAlpha(hide and 0 or 1)
			end
		end
	end
end

local function SetRound(button, part, round, own)
	SetCastFx(button, round and true or false)
	if own and not part.mask and button.CreateMaskTexture then
		part.mask = button:CreateMaskTexture()
		part.mask:SetAllPoints(button)
	end
	if part.mask then
		if own and part.maskRound ~= round then
			part.maskRound = round
			part.mask:SetTexture(round and CIRCLE or SQUARE_SWIPE, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
		end
		if own then
			for _, texture in ipairs(RoundArt(button, part)) do
				if not part.roundOn[texture] then
					part.roundOn[texture] = true
					texture:AddMaskTexture(part.mask)
				end
			end
		else
			for texture in pairs(part.roundOn) do
				texture:RemoveMaskTexture(part.mask)
				part.roundOn[texture] = nil
			end
		end
	end
	if part.cooldown and part.cooldown.SetSwipeTexture and (round or part.roundSwipe) then
		part.cooldown:SetSwipeTexture(round and CIRCLE or SQUARE_SWIPE)
		part.roundSwipe = round or nil
	end
end

local function SetOutline(button, part, plan)
	if not part.edges and plan.line then
		part.edges = ns.MakeStyleEdges(button)
		part.ring = part.edges:CreateTexture(nil, "OVERLAY")
		part.ring:SetAllPoints()
	end
	if not part.edges then return end
	local round = plan.line and plan.round
	local square = plan.line and not plan.round
	if square then ns.DressStyleEdges(part.edges, plan.size, plan.r, plan.g, plan.b) end
	for _, line in ipairs(part.edges.lines) do line:SetShown(square) end
	if round then
		part.ring:SetTexture(RING .. math.min(MAX_RING, plan.size))
		part.ring:SetVertexColor(plan.r, plan.g, plan.b, 1)
	end
	part.ring:SetShown(round)
end

local function Dress(button, plan)
	local part = Parts(button)
	if not part then return end
	-- (Nothing's touched on a button until the page asks for something.)
	if not part.dressed and not plan.own and plan.slots then return end
	part.dressed = true

	SetHidden(button.GetNormalTexture and button:GetNormalTexture(), plan.own)
	-- (A dark ground for empty slots: on the classic clients the game's slot art is
	-- the normal texture just hidden, which leaves them see-through.)
	if plan.own and not part.ground then
		part.ground = button:CreateTexture(nil, "BACKGROUND", nil, -8)
		part.ground:SetAllPoints()
		part.ground:SetColorTexture(0, 0, 0, 0.5)
	end
	if part.ground then part.ground:SetShown(plan.own and plan.slots) end
	for _, back in ipairs(part.backs) do SetHidden(back, not plan.slots) end

	-- The game's mask (rounded corners on retail art) goes with its shape.
	if part.gameMask and part.gameMaskOn == plan.own then
		if plan.own then
			part.icon:RemoveMaskTexture(part.gameMask)
		else
			part.icon:AddMaskTexture(part.gameMask)
		end
		part.gameMaskOn = not plan.own
	end
	if plan.own then
		part.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- (trims the icon's own edge)
	else
		part.icon:SetTexCoord(0, 1, 0, 1)
	end
	-- (And above the slot art for certain: they can share a draw layer.)
	if not part.iconLayer then part.iconLayer, part.iconSub = part.icon:GetDrawLayer() end
	part.icon:SetDrawLayer(part.iconLayer, math.min(7, (part.iconSub or 0) + (plan.own and 1 or 0)))
	SetRound(button, part, plan.round, plan.own)
	SetOutline(button, part, plan)
end

-- Retail's bar 1 has a divider between its buttons: small frames of the bar's own
-- (from a pool, no names), each with a TopEdge and a BottomEdge. Hidden only by the
-- Overrides tab's Button dividers row (by alpha, kept so as the game sets it again).
local DIVIDER_BARS = { "MainActionBar", "MainMenuBar" }
local dividerHidden, dividerHooked = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local function KeepDividerHidden(frame)
	if hiding or not dividerHidden[frame] then return end
	hiding = true
	frame:SetAlpha(0)
	hiding = false
end
local dividerBarsHooked = false
local function SetDividers()
	local over = ns.StyleOverride and ns.StyleOverride("barDividers")
	local hide = over == "hide"
	for _, name in ipairs(DIVIDER_BARS) do
		local bar = _G[name]
		if type(bar) == "table" and bar.GetChildren then
			for _, kid in ipairs({ bar:GetChildren() }) do
				if kid.TopEdge and kid.BottomEdge and not (kid.IsForbidden and kid:IsForbidden()) then
					if hide and not dividerHooked[kid] then
						dividerHooked[kid] = true
						hooksecurefunc(kid, "SetAlpha", KeepDividerHidden)
					end
					if hide then
						dividerHidden[kid] = true
						KeepDividerHidden(kid)
					elseif dividerHidden[kid] then
						dividerHidden[kid] = nil
						kid:SetAlpha(1)
					end
				end
			end
		end
	end
	-- (The game lays them out again as the bar changes: hidden again after it.)
	if dividerBarsHooked then return end
	dividerBarsHooked = true
	for _, name in ipairs(DIVIDER_BARS) do
		local bar = _G[name]
		if type(bar) == "table" and type(bar.UpdateDividers) == "function" then
			hooksecurefunc(bar, "UpdateDividers", function() C_Timer.After(0, SetDividers) end)
		end
	end
end

local function EachButton(apply)
	for _, bar in ipairs(BARS) do
		for i = 1, bar[2] do
			local button = _G[bar[1] .. i]
			if button then apply(button) end
		end
	end
	local pad = _G.GamepadMainActionBarFrame
	if pad and type(pad.actionButtons) == "table" then
		for _, button in ipairs(pad.actionButtons) do apply(button) end
	end
end

-- The game's Cooldown Manager (retail): its icons round with round buttons, so
-- the two read as one set. Each icon's art cut by a circle, its cooldown sweep
-- round, and the outline's ring round it as the buttons have. Its icons come and
-- go (a spec, a talent): dressed again as its viewers lay them out.
local CDM_VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
local cdmParts = setmetatable({}, { __mode = "k" })
local function EachCdmIcon(visit)
	local function Look(frame, depth)
		local okKids, kids = pcall(function() return { frame:GetChildren() } end)
		for _, kid in ipairs(okKids and kids or {}) do
			local icon = kid.Icon
			if type(icon) == "table" and icon.GetObjectType and icon:GetObjectType() == "Texture" then
				visit(kid, icon)
			elseif depth < 2 then
				Look(kid, depth + 1)
			end
		end
	end
	for _, name in ipairs(CDM_VIEWERS) do
		local viewer = _G[name]
		if type(viewer) == "table" and viewer.GetChildren then Look(viewer, 0) end
	end
end
local function DressCdmIcon(item, icon, plan)
	local part = cdmParts[item]
	if not part then
		if not plan.round then return end
		part = { on = {} }
		part.mask = item:CreateMaskTexture()
		part.mask:SetAllPoints(icon)
		part.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
		cdmParts[item] = part
	end
	-- (Every texture of the icon's: its picture and any square border or overlay.)
	for _, region in ipairs({ item:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region.AddMaskTexture then
			if plan.round and not part.on[region] then
				part.on[region] = true
				region:AddMaskTexture(part.mask)
			elseif not plan.round and part.on[region] then
				part.on[region] = nil
				region:RemoveMaskTexture(part.mask)
			end
		end
	end
	local cooldown = item.Cooldown
	if cooldown and cooldown.SetSwipeTexture and (plan.round or part.swipe) then
		cooldown:SetSwipeTexture(plan.round and CIRCLE or SQUARE_SWIPE)
		part.swipe = plan.round or nil
	end
	local ring = plan.round and plan.line
	if ring and not part.ring then
		part.ring = item:CreateTexture(nil, "OVERLAY", nil, 7)
		part.ring:SetAllPoints(icon)
	end
	if part.ring then
		part.ring:SetShown(ring and true or false)
		if ring then
			part.ring:SetTexture(RING .. math.min(MAX_RING, plan.size))
			part.ring:SetVertexColor(plan.r, plan.g, plan.b, 1)
		end
	end
end
local cdmHooked = false
function ns.RefreshCooldownShape()
	local plan = Plan()
	EachCdmIcon(function(item, icon)
		local ok, err = pcall(DressCdmIcon, item, icon, plan)
		if not ok then ns.Log("style", "cooldown icon failed: " .. tostring(err)) end
	end)
	if cdmHooked then return end
	cdmHooked = true
	for _, name in ipairs(CDM_VIEWERS) do
		local viewer = _G[name]
		if type(viewer) == "table" then
			local function Again() C_Timer.After(0, ns.RefreshCooldownShape) end
			if type(viewer.RefreshLayout) == "function" then hooksecurefunc(viewer, "RefreshLayout", Again) end
			if viewer.HookScript then viewer:HookScript("OnShow", Again) end
		end
	end
end

local waiting = false -- (a change made in a fight: done as it ends)
function ns.RefreshActionBarStyle()
	if InCombatLockdown() then
		waiting = true
		return
	end
	waiting = false
	if OthersSkinThem() then return end
	local plan = Plan()
	local failed
	EachButton(function(button)
		if not (button.IsForbidden and button:IsForbidden()) then
			local ok, err = pcall(Dress, button, plan)
			if not ok then failed = err end
		end
	end)
	if failed then ns.Log("style", "action buttons failed: " .. tostring(failed)) end
	ns.RefreshCooldownShape()
	SetDividers()
	-- (The square band bar 1 sits on: round buttons on it look out of place.)
	if ns.SetBarBorderOff then ns.SetBarBorderOff(plan.round) end
end

-- For the shots' log: what the page means to do and what's come of it.
function ns.ActionBarState()
	local plan, dressed, counted = Plan(), 0, 0
	EachButton(function(button)
		counted = counted + 1
		if parts[button] and parts[button].dressed then dressed = dressed + 1 end
	end)
	local button = _G.ActionButton1
	local normal = button and button.GetNormalTexture and button:GetNormalTexture()
	return ("bars: own %s line %s round %s others %s dressed %d/%d normal alpha %s"):format(tostring(plan.own), tostring(plan.line),
		tostring(plan.round), tostring(OthersSkinThem()), dressed, counted, tostring(normal and normal:GetAlpha()))
end

-- For the theme shots' log: whether bar 1's first icon can draw.
function ns.ButtonLayers()
	local button = _G.ActionButton1
	if not (button and button.icon) then return "no ActionButton1" end
	local function Of(texture)
		if not texture then return "none" end
		local layer, sub = texture:GetDrawLayer()
		return ("%s %s shown %s alpha %s masks %s"):format(tostring(layer), tostring(sub), tostring(texture:IsShown()),
			tostring(texture:GetAlpha()), tostring(texture.GetNumMaskTextures and texture:GetNumMaskTextures()))
	end
	return ("icon %s; slot back %s; slot art %s"):format(Of(button.icon), Of(button.SlotBackground), Of(button.SlotArt))
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if waiting then ns.RefreshActionBarStyle() end
		return
	end
	ns.RefreshActionBarStyle()
	C_Timer.After(1, ns.RefreshActionBarStyle) -- (bars some clients build a moment later)
end)

-- For /cine debug buttons: what a client's buttons are made of, and our state.
function ns.ReportActionBarStyle()
	local plan = Plan()
	print(("Cinematic: Action Bars: page %s, others skin them %s, in combat %s, game %s"):format(
		tostring(ns.StyleOn("abStyle")), tostring(OthersSkinThem()), tostring(InCombatLockdown() and true or false),
		tostring(select(4, GetBuildInfo()))))
	print(("own %s, round %s, line %s, size %s, slots %s"):format(tostring(plan.own), tostring(plan.round),
		tostring(plan.line), tostring(plan.size), tostring(plan.slots)))
	local counted, dressed = 0, 0
	EachButton(function(button)
		counted = counted + 1
		if parts[button] and parts[button].dressed then dressed = dressed + 1 end
	end)
	print(("buttons %d, dressed %d"):format(counted, dressed))
	local button = _G.ActionButton1
	if not button then return print("no ActionButton1") end
	local name = button:GetName()
	for _, field in ipairs({ "icon", "IconMask", "NormalTexture", "SlotBackground", "SlotArt", "Border", "Flash",
		"cooldown", "NewActionTexture", "SpellHighlightTexture" }) do
		print(("  %s: %s"):format(field, button[field] and "yes" or "no"))
	end
	print(("  FloatingBG: %s, normal texture: %s, mask maker: %s"):format(
		_G[name .. "FloatingBG"] and "yes" or "no", button:GetNormalTexture() and "yes" or "no",
		button.CreateMaskTexture and "yes" or "no"))
end

-- The preview: three icons and an empty slot, dressed by the same code.
local ICONS = { "Interface\\Icons\\Spell_Holy_FlashHeal", "Interface\\Icons\\Ability_Warrior_Rampage",
	"Interface\\Icons\\Spell_Nature_Lightning" }
local PREVIEW_SIZE, PREVIEW_GAP = 45, 8

local function GameArt(texture, atlas, file)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas)
	else
		texture:SetTexture(file)
	end
end

local function MakePreview(content)
	local holder = CreateFrame("Frame", nil, content)
	holder:SetSize(480, 90)
	ns.StyleScene(holder)
	local buttons = {}
	local count = #ICONS + 1
	local left = -(count * PREVIEW_SIZE + (count - 1) * PREVIEW_GAP) / 2
	for i = 1, count do
		local button = CreateFrame("Button", nil, holder)
		button:SetSize(PREVIEW_SIZE, PREVIEW_SIZE)
		button:SetPoint("LEFT", holder, "CENTER", left + (i - 1) * (PREVIEW_SIZE + PREVIEW_GAP), 0)
		button:EnableMouse(false)
		button.SlotBackground = button:CreateTexture(nil, "BACKGROUND", nil, -1)
		button.SlotBackground:SetAllPoints()
		GameArt(button.SlotBackground, "UI-HUD-ActionBar-IconFrame-Slot", "Interface\\Buttons\\UI-EmptySlot-Disabled")
		button.icon = button:CreateTexture(nil, "BACKGROUND")
		button.icon:SetAllPoints()
		button.icon:SetTexture(ICONS[i] or "")
		button.icon:SetShown(ICONS[i] ~= nil)
		button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
		local normal = button:GetNormalTexture()
		if normal then
			GameArt(normal, "UI-HUD-ActionBar-IconFrame", "Interface\\Buttons\\UI-Quickslot2")
		end
		buttons[i] = button
	end
	function holder:Refresh()
		local plan = Plan()
		for _, button in ipairs(buttons) do pcall(Dress, button, plan) end
	end
	holder:SetScript("OnShow", holder.Refresh)
	return holder
end

ns.MakeActionBarPreview = MakePreview

-- The page itself.
local PRESET_KEYS = { "abEdge", "abEdgeSize", "abEdgeR", "abEdgeG", "abEdgeB", "abShape", "abSlots" }

function ns.CreateActionBarStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Action Bar Style"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How the game's action buttons look: their outline, their shape and the background of empty slots. " ..
		"Other addons' bars keep their own look, and the game's do too with Dominos or Masque on."])

	local preview -- (below: drawn again as each setting changes)
	local function Changed()
		ns.RefreshActionBarStyle()
		if preview then preview:Refresh() end
	end

	local switch = kit.PageSwitch(content, "abStyle", L["Enable Page"],
		L["On: action buttons look as this page says. Off: the game's own (the preview shows that too). Each " ..
		"setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "abStyle")

	preview = MakePreview(content)
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)

	rows.PresetMenu({
		{ L["Like the game's"], L["The game's action buttons, as it draws them (the defaults)."], {} },
		{ L["Dark"], L["Square buttons with a thick dark outline."], { abEdge = "thick", abShape = "square" } },
		{ L["Round"], L["Round buttons with a thin dark outline."], { abEdge = "thin", abShape = "round" } },
		{ L["Class color"], L["Square buttons outlined in your class color."],
			{ abEdge = "colored", abShape = "square" } },
	}, PRESET_KEYS)

	stack:Header(content, L["Look"])
	rows.Border(L["Outline:"], "abEdge", { game = true, colored = L["Class color"] },
		L["The line around each button. Thin and Thick are black. With the game's shape only the game's outline " ..
		"fits, so any other outline makes the buttons square."])
	rows.Choices(L["Shape:"], "abShape", {
		{ "game", L["The game's"] },
		{ "square", L["Square"], L["Square icons with their edges trimmed."] },
		{ "round", L["Round"], L["Round icons, with the cooldown sweep and the highlights round too."] },
	})
	rows.Check("abSlots", L["Empty slot background"], L["The game's background on empty action slots. Off: only " ..
		"empty space shows there. Classic clients draw part of it on the bar's art, which stays."])

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Action Style", L["Action Bar Style"])
end
