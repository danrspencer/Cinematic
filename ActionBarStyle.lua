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
-- Retail's Square: its square's corners cut as the game's are (Media/make_action_bevel.py).
local BEVEL_MASK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\ActionBevelMask"
local BEVEL_RING = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\ActionBevelRing" -- (1 to 10)
local ROUND_MASK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\ActionRoundMask" -- (make_action_rings.py)
local ROUND_GLOW = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\ActionRoundGlow" -- (make_action_rings.py)
local ROUND_PROC = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\ActionRoundProc" -- (make_action_rings.py)
local ROUND_SPARKS = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\ActionRoundSparks" -- (make_action_rings.py)
local PROC_SCALE = (20.5 + 9) / 20.5 -- (its art's half-size over its edge's radius: EDGE_R + SPREAD, over EDGE_R)
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
-- (/cine debug buttonframe: the hidden art shown faintly over ours, to line
-- ours up with the game's.)
local ghost = false
local function HideAgain(texture)
	if hiding or not hidden[texture] then return end
	hiding = true
	texture:SetAlpha(ghost and 0.5 or 0)
	hiding = false
end
function ns.ToggleButtonFrameGhost()
	ghost = not ghost
	for texture in pairs(hidden) do HideAgain(texture) end
	ns.Print(ghost and "The game's button art shows faintly over ours (again to hide it)." or
		"The game's button art hidden again.")
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
	texture:SetAlpha(hide and (ghost and 0.5 or 0) or 1)
end

-- A button's parts, found once. (A table of ours, not fields on the button:
-- the game's buttons are secure, and writing on them taints.)
local parts = setmetatable({}, { __mode = "k" })
-- Retail's button art (UI-HUD-ActionBar-IconFrame, 46x45 over a 45 button) draws
-- its square a little inside the button, with see-through room round it: our
-- square, filling the whole button, showed past the game's (retail 12.0). Ours
-- is cut to the game's square there: the mask, the dark ground and the outline
-- in by this much each side. (Classic art fills its button: none there.)
local RETAIL_INSET = 2
local FOREVER_INSET = 1
local function Inset(region, button, inset)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
	region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
end
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
	-- (Retail's art only: its square sits in from the button. Set per look in Dress.)
	part.retail = ns.isRetail and part.gameMask ~= nil
	part.inset = 0
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
		-- (The slot's own frame art, behind the icon: uncut, its square showed dark in
		-- a round button's corners on bar 1.)
		button.SlotArt or false, part.floating or false,
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
-- (A proc's glow too: retail's SpellActivationAlert, the older clients' overlay.)
local CAST_FX = { "SpellCastAnimFrame", "TargetReticleAnimFrame", "InterruptDisplay", "CooldownFlash",
	"SpellActivationAlert", "overlay" }
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

-- A round button's own glows, in place of the game's square ones: a gold glow
-- round its inside edge while you cast from it (the game's cast effect, hidden
-- above, or its checked frame, the gold square it shows while the spell's
-- current) and a faint white one on mouseover. The game's checked and mouseover
-- frames are squares along the edge: cut round, only the middle of each side
-- showed, so they're hidden on round buttons.
-- A proc (the game's square proc glow, hidden above, or its spell highlight, a
-- square cut round): one pulsing gold glow of ours, brighter than the cast's.
local function Shown(region)
	if not region then return false end
	local ok, shown = pcall(region.IsShown, region)
	return ok and shown == true
end
-- (A cancelled cast leaves the game's cast effect up, fading: the glow stayed. So
-- it needs a cast or channel of yours under way too, looked at again as one ends.)
local function Casting()
	for _, info in ipairs({ UnitCastingInfo, UnitChannelInfo }) do
		local ok, name = pcall(info, "player")
		if ok and name ~= nil then return true end
	end
	return false
end
-- The cast's progress (0 to 1) for a round button's fill: a cast fills up, a
-- channel runs down. nil: none, or its times can't be read.
local function Progress()
	for i, info in ipairs({ UnitCastingInfo, UnitChannelInfo }) do
		local ok, name, _, _, start, finish = pcall(info, "player")
		if ok and name ~= nil then
			if not (type(start) == "number" and type(finish) == "number")
				or (issecretvalue and (issecretvalue(start) or issecretvalue(finish))) or finish <= start then
				return nil
			end
			local done = math.min(1, math.max(0, (GetTime() * 1000 - start) / (finish - start)))
			return i == 1 and done or 1 - done
		end
	end
	return nil
end
-- A round button's cast fill, as the game's square buttons have: gold over the
-- icon from the left as the cast goes on, a bright line at its edge, cut round
-- by the button's mask (the game's, part of its cast effect, is hidden here).
local function FillTick(button, part)
	local progress = Progress()
	if not progress then
		part.fill:Hide()
		part.fillEdge:Hide()
		return
	end
	local wide = button:GetWidth() - part.inset * 2
	part.fill:SetWidth(math.max(0.01, wide * progress))
	part.fill:Show()
	part.fillEdge:SetShown(progress > 0 and progress < 1)
end
local function SyncFill(button, part, on)
	if on and part.mask and not part.fillMasked then
		part.fillMasked = true
		part.fill:AddMaskTexture(part.mask)
		part.fillEdge:AddMaskTexture(part.mask)
	end
	if on and not part.filling then
		part.filling = true
		part.fill:ClearAllPoints()
		part.fill:SetPoint("TOPLEFT", button, "TOPLEFT", part.inset, -part.inset)
		part.fill:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", part.inset, part.inset)
		ns.SetOnUpdate(part.fillTicker, function() FillTick(button, part) end)
		FillTick(button, part)
	elseif not on and part.filling then
		part.filling = nil
		ns.SetOnUpdate(part.fillTicker, nil)
		part.fill:Hide()
		part.fillEdge:Hide()
	end
end
local function SyncGlow(button, part)
	local okChecked, checked = pcall(button.GetChecked, button)
	local castFx = Shown(button.SpellCastAnimFrame) and Casting()
	SyncFill(button, part, part.glowOn and castFx and true or false)
	local casting = castFx or (okChecked and checked == true)
	local proc = Shown(button.SpellActivationAlert) or Shown(button.overlay) or Shown(button.SpellHighlightTexture)
	part.glow:SetShown(part.glowOn and casting and not proc and true or false)
	part.proc:SetShown(part.glowOn and proc and true or false)
	-- (Held down, by key or mouse: the game's pressed frame, a square, is hidden on
	-- round buttons; a dark round edge of ours instead.)
	local okState, state = pcall(button.GetButtonState, button)
	part.press:SetShown(part.glowOn and okState and state == "PUSHED" and true or false)
	part.sparks:SetShown(part.proc:IsShown())
	if part.proc:IsShown() then
		if not part.pulse:IsPlaying() then part.pulse:Play() end
		if not part.spin:IsPlaying() then part.spin:Play() end
	else
		part.pulse:Stop()
		part.spin:Stop()
	end
end
local castWatch = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START" }) do
	pcall(castWatch.RegisterUnitEvent, castWatch, event, "player")
end
local function SyncAllGlows()
	for button, part in pairs(parts) do
		if part.glow then SyncGlow(button, part) end
	end
end
castWatch:SetScript("OnEvent", function()
	SyncAllGlows()
	C_Timer.After(0, SyncAllGlows) -- (the cast's info can still be there as it ends)
end)

-- The game shows and hides a proc's glow by these (retail's, then the older clients').
local procHooked = false
local function HookProcs()
	if procHooked then return end
	procHooked = true
	local function Again(button)
		local part = button and parts[button]
		if not part then return end
		-- (Over our outline, as over the game's frame: under it, a square button's
		-- glow had our line through it and its inner half covered.)
		local alert = button.SpellActivationAlert or button.overlay
		if alert and alert.SetFrameLevel and part.edges and part.edges:IsShown() then
			alert:SetFrameLevel(part.edges:GetFrameLevel() + 1)
		end
		if not part.glow then return end
		SetCastFx(button, part.glowOn) -- (the alert's made the first time it shows)
		if alert and alert.HookScript and not part.alertHooked then
			part.alertHooked = true
			alert:HookScript("OnShow", function() SyncGlow(button, part) end)
			alert:HookScript("OnHide", function() SyncGlow(button, part) end)
		end
		SyncGlow(button, part)
	end
	local manager = _G.ActionButtonSpellAlertManager
	if manager and manager.ShowAlert then
		hooksecurefunc(manager, "ShowAlert", function(_, button) Again(button) end)
		hooksecurefunc(manager, "HideAlert", function(_, button) Again(button) end)
	end
	for _, name in ipairs({ "ActionButton_ShowOverlayGlow", "ActionButton_HideOverlayGlow" }) do
		if type(_G[name]) == "function" then hooksecurefunc(name, Again) end
	end
end
local function RoundGlow(button, part, round)
	if round and not part.glow then
		part.glow = button:CreateTexture(nil, "OVERLAY", nil, 6)
		part.glow:SetTexture(ROUND_GLOW)
		part.glow:SetBlendMode("ADD")
		part.glow:SetVertexColor(1, 0.78, 0.3, 0.9)
		part.glow:Hide()
		part.hover = button:CreateTexture(nil, "HIGHLIGHT", nil, 7)
		part.hover:SetTexture(ROUND_GLOW)
		part.hover:SetBlendMode("ADD")
		part.hover:SetVertexColor(1, 1, 1, 0.45)
		-- (A proc's band on the edge, over our ring: a frame of its own above the outline's.)
		part.procFrame = CreateFrame("Frame", nil, button)
		part.procFrame:SetAllPoints()
		part.procFrame:SetFrameLevel(button:GetFrameLevel() + 4)
		part.proc = part.procFrame:CreateTexture(nil, "OVERLAY", nil, 6)
		part.proc:SetTexture(ROUND_PROC)
		part.proc:SetBlendMode("ADD")
		part.proc:SetVertexColor(1, 0.66, 0.08, 1) -- (deeper gold: added up, a paler one read cream)
		part.proc:Hide()
		-- (And sparks running round it, as round the game's square one.)
		part.sparks = part.procFrame:CreateTexture(nil, "OVERLAY", nil, 7)
		part.sparks:SetTexture(ROUND_SPARKS)
		part.sparks:SetBlendMode("ADD")
		part.sparks:SetVertexColor(1, 0.9, 0.55, 1)
		part.sparks:SetAllPoints(part.proc)
		part.sparks:Hide()
		part.spin = part.sparks:CreateAnimationGroup()
		part.spin:SetLooping("REPEAT")
		local turn = part.spin:CreateAnimation("Rotation")
		turn:SetDegrees(-360)
		turn:SetDuration(2.4)
		part.press = button:CreateTexture(nil, "OVERLAY", nil, 5)
		part.press:SetTexture(ROUND_GLOW)
		part.press:SetVertexColor(0, 0, 0, 0.8)
		part.press:Hide()
		part.fill = button:CreateTexture(nil, "OVERLAY", nil, 3)
		part.fill:SetColorTexture(1, 0.72, 0.25, 0.5)
		part.fill:SetBlendMode("ADD")
		part.fill:Hide()
		part.fillEdge = button:CreateTexture(nil, "OVERLAY", nil, 4)
		part.fillEdge:SetColorTexture(1, 0.95, 0.75, 0.95)
		part.fillEdge:SetBlendMode("ADD")
		part.fillEdge:SetWidth(2)
		part.fillEdge:SetPoint("TOPRIGHT", part.fill, "TOPRIGHT")
		part.fillEdge:SetPoint("BOTTOMRIGHT", part.fill, "BOTTOMRIGHT")
		part.fillEdge:Hide()
		part.fillTicker = CreateFrame("Frame", nil, button)
		part.pulse = part.proc:CreateAnimationGroup()
		part.pulse:SetLooping("BOUNCE")
		local fade = part.pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.55)
		fade:SetDuration(0.5)
		local function Sync() SyncGlow(button, part) end
		local highlight = button.SpellHighlightTexture
		if highlight then
			for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
				if highlight[method] then hooksecurefunc(highlight, method, Sync) end
			end
		end
		HookProcs()
		local cast = button.SpellCastAnimFrame
		if cast and cast.HookScript then
			cast:HookScript("OnShow", Sync)
			cast:HookScript("OnHide", Sync)
		end
		if button.SetChecked then hooksecurefunc(button, "SetChecked", Sync) end
		if button.SetButtonState then hooksecurefunc(button, "SetButtonState", Sync) end
		button:HookScript("OnMouseDown", Sync)
		button:HookScript("OnMouseUp", Sync)
	end
	if not part.glow then return end
	part.glowOn = round
	Inset(part.glow, button, part.inset)
	Inset(part.hover, button, part.inset)
	-- (Its art reaches PROC_SPREAD past the round edge, outside the button: sized so
	-- its edge sits on the button's, Media/make_action_rings.py's EDGE_R and SPREAD.)
	local wide = button:GetWidth()
	local edge = ((type(wide) == "number" and wide > 0 and wide or 45) / 2 - part.inset)
	part.proc:ClearAllPoints()
	part.proc:SetPoint("CENTER", button, "CENTER")
	part.proc:SetSize(edge * PROC_SCALE * 2, edge * PROC_SCALE * 2)
	Inset(part.press, button, part.inset)
	SetHidden(button.GetPushedTexture and button:GetPushedTexture(), round)
	part.hover:SetShown(round)
	SetHidden(button.SpellHighlightTexture, round)
	SetHidden(button.GetCheckedTexture and button:GetCheckedTexture(), round)
	SetHidden(button.GetHighlightTexture and button:GetHighlightTexture(), round)
	SyncGlow(button, part)
end

local function SetRound(button, part, round, own)
	SetCastFx(button, round and true or false)
	RoundGlow(button, part, round and true or false)
	if own and not part.mask and button.CreateMaskTexture then
		part.mask = button:CreateMaskTexture()
	end
	if part.mask and part.maskInset ~= part.inset then
		part.maskInset = part.inset
		Inset(part.mask, button, part.inset)
	end
	if part.mask then
		-- (A cut-corner square (part.bevel): BEVEL_MASK. Round: ours, just
		-- inside the ring; the game's circle let the icon's pale edge show past it.)
		local art = round and ROUND_MASK or part.bevel and BEVEL_MASK or SQUARE_SWIPE
		if own and part.maskArt ~= art then
			part.maskArt = art
			part.mask:SetTexture(art, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
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

local SHADE = 0.55 -- (the dark line inside the outline: how dark)
local function SetOutline(button, part, plan)
	if not part.edges and plan.line then
		part.edges = ns.MakeStyleEdges(button)
		part.ring = part.edges:CreateTexture(nil, "OVERLAY")
		part.ring:SetAllPoints()
		-- The game's frame has a faint dark line just inside it, between it and the
		-- icon: ours too, inside our outline, on retail's cut-corner square.
		part.shade = part.edges:CreateTexture(nil, "OVERLAY", nil, -1)
	end
	if not part.edges then return end
	if part.edgesInset ~= part.inset then
		part.edgesInset = part.inset
		Inset(part.edges, button, part.inset)
	end
	-- (Round, or the cut-corner square: a ring of art. A plain square: lines.)
	local bevel = plan.line and part.bevel
	local round = plan.line and (plan.round or bevel)
	local square = plan.line and not round
	if square then ns.DressStyleEdges(part.edges, plan.size, plan.r, plan.g, plan.b) end
	for _, line in ipairs(part.edges.lines) do line:SetShown(square) end
	if round then
		part.ring:SetTexture((bevel and BEVEL_RING or RING) .. math.min(MAX_RING, plan.size))
		part.ring:SetVertexColor(plan.r, plan.g, plan.b, 1)
	end
	part.ring:SetShown(round)
	local inner = plan.line and plan.size or 0
	-- (Only on the cut-corner square, retail's own look copied (Forever's square
	-- takes it too): round buttons and Classic Era's squares go without.)
	Inset(part.shade, button, part.inset + inner)
	if bevel then
		part.shade:SetTexture(BEVEL_RING .. 1)
		part.shade:SetVertexColor(0, 0, 0, SHADE)
	end
	part.shade:SetShown(bevel)
end

local function Dress(button, plan)
	local part = Parts(button)
	if not part then return end
	-- (Nothing's touched on a button until the page asks for something.)
	if not part.dressed and not plan.own and plan.slots then return end
	part.dressed = true
	-- (Retail's square sits in from the button, as the game's does, and round
	-- the same: filling the button, its icons came out bigger than square's.)
	-- (Square with cut corners, as retail's own: there and on WoW Forever. Classic
	-- Era keeps plain corners.)
	part.bevel = plan.own and not plan.round and (part.retail or not ns.isClassicEra) or false
	-- (Forever's cut-corner square: set in a little too, inside where the game's
	-- border sits; filling its button, the icon came out bigger than the game's.)
	part.inset = part.retail and plan.own and RETAIL_INSET or part.bevel and FOREVER_INSET or 0
	HookProcs() -- (a square button's proc glow is lifted over our outline too)

	SetHidden(button.GetNormalTexture and button:GetNormalTexture(), plan.own)
	-- (A dark ground for empty slots: on the classic clients the game's slot art is
	-- the normal texture just hidden, which leaves them see-through.)
	if plan.own and not part.ground then
		part.ground = button:CreateTexture(nil, "BACKGROUND", nil, -8)
		part.ground:SetColorTexture(0, 0, 0, 0.5)
	end
	if part.ground and part.groundInset ~= part.inset then
		part.groundInset = part.inset
		Inset(part.ground, button, part.inset)
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
		-- (Trims the icon's own edge. Where the mask is in from the button's edge
		-- it cuts that much off already: about the same trim, the whole icon given.)
		local trim = (part.inset > 0 or part.bevel) and 0 or 0.07
		part.icon:SetTexCoord(trim, 1 - trim, trim, 1 - trim)
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
-- (Round buttons: bar 1's dividers and gryphons go too, made for square ones,
-- unless the Overrides tab says Show. InterfaceRecolor.lua's bar art reads it.)
local roundNow = false
function ns.ActionBarsRound() return roundNow end
-- Bar 1's page arrows (the up/down and its number): gone with round buttons too,
-- by alpha (the game sets it again: kept so), and not clickable while gone (out
-- of fights only: the bar may be protected).
local arrowsHidden, arrowsHooked = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local function KeepArrowsHidden(frame)
	if hiding or not arrowsHidden[frame] then return end
	hiding = true
	frame:SetAlpha(0)
	hiding = false
end
local function SetPageArrows()
	for _, name in ipairs(DIVIDER_BARS) do
		local bar = _G[name]
		local arrows = type(bar) == "table" and bar.ActionBarPageNumber
		if arrows and arrows.SetAlpha and not (arrows.IsForbidden and arrows:IsForbidden()) then
			if roundNow and not arrowsHooked[arrows] then
				arrowsHooked[arrows] = true
				hooksecurefunc(arrows, "SetAlpha", KeepArrowsHidden)
			end
			if roundNow ~= (arrowsHidden[arrows] or false) then
				arrowsHidden[arrows] = roundNow or nil
				arrows:SetAlpha(roundNow and 0 or 1)
			end
			if not InCombatLockdown() then
				for _, key in ipairs({ "UpButton", "DownButton" }) do
					local button = arrows[key]
					if button and button.EnableMouse then button:EnableMouse(not roundNow) end
				end
			end
		end
	end
end
local function SetDividers()
	local over = ns.StyleOverride and ns.StyleOverride("barDividers")
	local hide = over == "hide" or (over ~= "show" and roundNow)
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
	roundNow = plan.round and true or false
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
	SetPageArrows()
	if ns.ApplyBarArtOverride then ns.ApplyBarArtOverride() end
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
	-- Where each piece sits against the button (to line our square up with the
	-- game's): its size, its offsets from the button's edges, its atlas and
	-- that atlas's own size. To the log too.
	local function Where(label, region)
		if not region then return end
		local okAtlas, atlas = pcall(function() return region.GetAtlas and region:GetAtlas() end)
		atlas = okAtlas and atlas or nil
		local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
		local left, right, top, bottom = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
		local bl, br, bt, bb = button:GetLeft(), button:GetRight(), button:GetTop(), button:GetBottom()
		local line = ("  %s: %.1fx%.1f, in by left %.1f right %.1f top %.1f bottom %.1f, atlas %s (%s), coords %s"):format(
			label, region:GetWidth(), region:GetHeight(), (left or 0) - (bl or 0), (br or 0) - (right or 0),
			(bt or 0) - (top or 0), (bottom or 0) - (bb or 0), tostring(atlas),
			info and ("%dx%d"):format(info.width or 0, info.height or 0) or "-",
			region.GetTexCoord and table.concat({ region:GetTexCoord() }, ",", 1, 8) or "-")
		print(line)
		ns.Log("style", "buttons:" .. line)
	end
	Where("button", button)
	Where("icon", button.icon)
	Where("IconMask", button.IconMask)
	Where("normal", button:GetNormalTexture())
	Where("SlotBackground", button.SlotBackground)
	Where("SlotArt", button.SlotArt)
	Where("pushed", button.GetPushedTexture and button:GetPushedTexture())
	Where("highlight", button.GetHighlightTexture and button:GetHighlightTexture())
	local part = parts[button]
	Where("cooldown", button.cooldown)
	if part and part.mask then Where("our mask", part.mask) end
	ns.Log("style", ("buttons: client %s, scale %.3f, own %s round %s"):format(tostring(select(4, GetBuildInfo())),
		button:GetEffectiveScale(), tostring(plan.own), tostring(plan.round)))
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
