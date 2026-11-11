-- The menu look (main page's Menu look, ns.MenuSkin): Cinematic's settings
-- pages and windows in HD, flat (dark, a thin edge), or SD, the game's own
-- buttons and windows. Each thing made by these has both looks and shows the
-- one now; ns.ApplyMenuSkin() puts them all in the look again when it
-- changes (the setting, or Forever's Character Models under Auto: checked as
-- a page or window opens). Buttons, windows, checkboxes, sliders, dropdowns
-- and text boxes; HD's accent (a tick, a slider's filled part) is gold.

local _, ns = ...

local skinned = setmetatable({}, { __mode = "k" }) -- (thing -> its function putting it in a look)
local applied -- (the look they're in)

-- HD's colors, by what each is for. A style theme gives its own
-- (ns.MenuPalette, StyleThemes.lua); these are the ones with none.
local ROLES = { accent = { 1, 0.82, 0 }, edge = { 0.5, 0.5, 0.5 }, field = { 0.06, 0.06, 0.08 },
	window = { 0.04, 0.04, 0.05 }, well = { 0, 0, 0 }, knob = { 0.85, 0.85, 0.85 }, thumb = { 0.7, 0.7, 0.7 } }
local function Role(role)
	local palette = ns.MenuPalette and ns.MenuPalette()
	return palette and palette[role] or ROLES[role]
end
local ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local function PaintTexture(texture, round, r, g, b, a)
	if round then
		texture:SetTexture(ROUND)
		texture:SetVertexColor(r, g, b, a)
	else
		texture:SetColorTexture(r, g, b, a)
	end
end
-- Things in a role's color, painted again as the theme changes.
local toned = setmetatable({}, { __mode = "k" }) -- (texture -> { role, alpha, round })
local tonedText = setmetatable({}, { __mode = "k" }) -- (gold text -> true)
local function PaintTone(texture, how)
	local color = Role(how[1])
	PaintTexture(texture, how[3], color[1], color[2], color[3], how[2])
end
local function Tone(texture, role, alpha, round)
	local how = { role, alpha, round }
	toned[texture] = how
	PaintTone(texture, how)
end
-- (Text, both ways: on Forever text and vertex color are one.)
local function PaintText(text)
	local color = Role("accent")
	text:SetTextColor(color[1], color[2], color[3])
	if text.SetVertexColor then text:SetVertexColor(color[1], color[2], color[3]) end
end
local paletteKey = "game" -- (the theme the colors are in)
-- A heading in the game's gold: the theme's accent while there is one.
function ns.ToneText(text)
	tonedText[text] = true
	if paletteKey ~= "game" then PaintText(text) end
	return text
end
local function Repaint()
	local key = ns.MenuPaletteKey and ns.MenuPaletteKey() or "game"
	if key == paletteKey then return false end
	paletteKey = key
	for texture, how in pairs(toned) do PaintTone(texture, how) end
	for text in pairs(tonedText) do PaintText(text) end
	return true
end

-- The look things are in now (or will be, made now). Worked out once, not
-- for each thing made; ns.ApplyMenuSkin looks again.
function ns.CurrentMenuSkin()
	applied = applied or ns.MenuSkin()
	return applied
end

-- Puts thing in skin. A look that goes wrong (a client without some method)
-- mustn't stop a page being made: the first error's reported, once.
local reported
local function Apply(thing, apply, skin)
	local ok, err = pcall(apply, thing, skin)
	if not ok and not reported then
		reported = true
		geterrorhandler()(err)
	end
end

-- Every skinned thing in the look, when it's changed (force: all the same).
-- Only what shows now: the rest waits (pending) for its page to open, which calls
-- this again. (Every control on every page at once took 50 ms a theme pick.)
local pending = setmetatable({}, { __mode = "k" })
local function Visible(thing)
	if type(thing) ~= "table" or type(thing.IsVisible) ~= "function" then return true end
	local ok, shown = pcall(thing.IsVisible, thing)
	return not ok or shown ~= false
end
-- A thing left for later put in the look as soon as it shows: a page's other
-- tab or a closed section opened, which doesn't open a page (left as it was,
-- one tab showed HD and the next SD). Hooked once per thing.
local hooked = setmetatable({}, { __mode = "k" })
local function WhenShown(thing)
	if hooked[thing] or type(thing) ~= "table" or type(thing.HookScript) ~= "function" then return end
	hooked[thing] = true
	pcall(thing.HookScript, thing, "OnShow", function(self)
		if pending[self] and skinned[self] then
			pending[self] = nil
			Apply(self, skinned[self], applied)
		end
	end)
end
function ns.ApplyMenuSkin(force)
	local skin = ns.MenuSkin()
	local repainted = Repaint()
	if skin == applied and not force and not repainted then
		-- (Nothing new: just what was left for later and shows now.)
		for thing in pairs(pending) do
			if Visible(thing) then
				pending[thing] = nil
				if skinned[thing] then Apply(thing, skinned[thing], skin) end
			end
		end
		return
	end
	applied = skin
	for thing, apply in pairs(skinned) do
		if Visible(thing) then
			pending[thing] = nil
			Apply(thing, apply, skin)
		else
			pending[thing] = true
			WhenShown(thing)
		end
	end
end

local function Register(thing, apply)
	skinned[thing] = apply
	Apply(thing, apply, ns.CurrentMenuSkin())
end

-- Something a page draws its own way in both looks: apply(thing, skin) now,
-- and again each time the look changes.
function ns.OnMenuSkin(thing, apply)
	Register(thing, apply)
end

-- Whether a control's usable (some clients' sliders can't say: then it is).
local function Enabled(control)
	return not control.IsEnabled or control:IsEnabled()
end

-- A flat edge and background on frame, under everything it has: the edge a
-- pixel out all round. Gives edge, bg.
--
-- The edge is one screen pixel, whatever the scale: a fixed 1 is less than
-- a pixel in the settings (their scale is under 1), and rounds away on some
-- rows. Worked out from frame's own scale each time it shows (once its
-- parents, the settings window among them, are set), only moved if it's changed.
-- Off the pixel grid: snapped, a sliver this thin can round to nothing on
-- some rows; off it, it always draws.
local function NoSnap(texture)
	if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
	if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end
local function SnapEdge(frame, edge, left)
	NoSnap(edge)
	local function Snap()
		local scale = frame:GetEffectiveScale()
		local px = 1
		if PixelUtil and PixelUtil.GetPixelToUIUnitFactor and scale and scale > 0 then
			px = PixelUtil.GetPixelToUIUnitFactor() / scale
		end
		if edge.px ~= px then
			edge.px = px
			edge:ClearAllPoints()
			edge:SetPoint("TOPLEFT", -(left or 0) - px, px)
			edge:SetPoint("BOTTOMRIGHT", px, -px)
		end
	end
	Snap()
	frame:HookScript("OnShow", Snap)
end
local function Flat(frame, role, a, edgeAlpha)
	local edge = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	SnapEdge(frame, edge)
	Tone(edge, "edge", edgeAlpha)
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	bg:SetAllPoints()
	Tone(bg, role, a)
	NoSnap(bg)
	return edge, bg
end

-- frame's textures (made by its template: call before adding ours), but keep's.
local function TexturesOf(frame, keep)
	local art = {}
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not (keep and keep[region]) then art[#art + 1] = region end
	end
	return art
end
local function ShowArt(art, shown)
	for _, piece in ipairs(art) do piece:SetAlpha(shown and 1 or 0) end
end
-- Calls fn after the control's greyed or brought back.
local function OnEnabledChange(control, fn)
	for _, method in ipairs({ "SetEnabled", "Enable", "Disable" }) do
		if control[method] then hooksecurefunc(control, method, fn) end
	end
end

-- The game's art on a button: three pieces on some clients, one texture on
-- others, and its pushed, disabled and highlight ones.
local function ButtonArt(button)
	local art = {}
	for _, piece in ipairs({ button.Left or false, button.Middle or false, button.Right or false,
		button:GetNormalTexture() or false, button:GetPushedTexture() or false,
		button:GetDisabledTexture() or false, button:GetHighlightTexture() or false }) do
		if piece and not art[piece] then
			art[piece] = true
			art[#art + 1] = piece
		end
	end
	return art
end

-- A UIPanelButtonTemplate button in both looks. HD: dark, a thin edge, a
-- lighter hover, dimmed while disabled. SD: as the game draws it. Its own:
-- button:SetSkinEdge(r, g, b, a), the HD edge's colour (a group's, say);
-- button:SetSkinTint(r, g, b), a colour on both looks (nil: none), as for
-- one that's on or wrong.
function ns.SkinButton(button)
	local art = ButtonArt(button)
	local edge, bg = Flat(button, "field", 0.9, 0.5)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.08)
	local edgeColor, tint = nil, nil -- (edgeColor: its own, else the theme's)
	local function Paint(self, skin)
		local hd = skin == "HD"
		edge:SetShown(hd)
		bg:SetShown(hd)
		hover:SetShown(hd)
		bg:SetAlpha(Enabled(self) and 1 or 0.5)
		if tint then
			edge:SetColorTexture(tint[1], tint[2], tint[3], 0.8)
		elseif edgeColor then
			edge:SetColorTexture(edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4])
		else
			PaintTone(edge, toned[edge])
		end
		-- (Alpha, not Hide: the game's button shows its own art again as it's pressed.)
		for _, piece in ipairs(art) do
			piece:SetAlpha(hd and 0 or 1)
			if piece.SetVertexColor then
				piece:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1)
			end
		end
	end
	function button:SetSkinEdge(r, g, b, a)
		edgeColor = { r, g, b, a or 0.5 }
		Paint(self, ns.CurrentMenuSkin())
	end
	function button:SetSkinTint(r, g, b)
		tint = r and { r, g, b } or nil
		Paint(self, ns.CurrentMenuSkin())
	end
	-- (Its words: the game's gold, the theme's accent while there is one. The
	-- game puts its gold back each time it's enabled.)
	local label = button.GetFontString and button:GetFontString()
	if label then ns.ToneText(label) end
	-- (Hooked: the game's button has its own, for its art.)
	button:HookScript("OnDisable", function() bg:SetAlpha(0.5) end)
	button:HookScript("OnEnable", function()
		bg:SetAlpha(1)
		if label then ns.ToneText(label) end
	end)
	Register(button, Paint)
	return button
end

-- A new UIPanelButtonTemplate button on parent, in both looks.
function ns.PanelButton(parent)
	return ns.SkinButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
end

-- Every window opened from the settings (DockBeside's, and the others that
-- ask with this) closes as the settings do. (A frame of ours inside the
-- settings window hears it, by its own OnHide: nothing of the game's hooked.)
local closeWithSettings, settingsWatch = {}, nil
function ns.CloseWithSettings(frame)
	closeWithSettings[frame] = true
	local settings = _G.SettingsPanel or _G.InterfaceOptionsFrame
	if settingsWatch or not settings then return end
	settingsWatch = CreateFrame("Frame", nil, settings)
	settingsWatch:SetScript("OnHide", function()
		for each in pairs(closeWithSettings) do each:Hide() end
	end)
end

-- A window opened from the settings sits docked beside them (to their right)
-- as it opens, like the Look panels; its Pop out button lets you drag it
-- anywhere (kept for next time: dockSpots[key]), Dock puts it back. With the
-- settings closed, it opens where it was put to start with. Returns the
-- button (at the top right, left of the X: move it if that's taken).
local function DockSpot(key)
	local spots = ns.db and ns.db.dockSpots
	local spot = type(spots) == "table" and spots[key]
	return type(spot) == "table" and spot.x and spot.y and spot or nil
end
function ns.DockBeside(frame, key)
	local home = { frame:GetPoint(1) }
	local dock = ns.PanelButton(frame)
	dock:SetSize(70, 20)
	dock:SetPoint("TOPRIGHT", -30, -6)
	local function Place()
		local spot = DockSpot(key)
		local settings = _G.SettingsPanel or _G.InterfaceOptionsFrame
		frame:ClearAllPoints()
		if spot then
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", spot.x, spot.y)
		elseif settings and settings:IsShown() then
			frame:SetPoint("TOPLEFT", settings, "TOPRIGHT", 4, 0)
		elseif home[1] then
			frame:SetPoint(unpack(home))
		end
		dock:SetText(ns.L[spot and "Dock" or "Pop out"])
	end
	local function Save(spot)
		if not ns.db then return end
		if type(ns.db.dockSpots) ~= "table" then ns.db.dockSpots = {} end
		ns.db.dockSpots[key] = spot
	end
	dock:SetScript("OnClick", function()
		Save(not DockSpot(key) and { x = frame:GetLeft() + 30, y = frame:GetTop() - 30 } or nil)
		Place()
	end)
	if ns.lowHealthKit then
		ns.lowHealthKit.Tooltip(dock, ns.L["Pop out: drag the window anywhere (by its edge). Dock: back beside the settings."])
	end
	-- (Docked, it stays beside the settings: Pop out first to drag it.)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if DockSpot(key) then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if DockSpot(key) then Save({ x = self:GetLeft(), y = self:GetTop() }) end
		Place()
	end)
	frame:HookScript("OnShow", Place)
	ns.CloseWithSettings(frame)
	return dock
end

-- A UIPanelCloseButton in both looks. HD: a small flat square with an X,
-- in the middle of the game's room for it.
function ns.SkinClose(button)
	local art = ButtonArt(button)
	local square = CreateFrame("Frame", nil, button)
	square:SetSize(18, 18)
	square:SetPoint("CENTER")
	square:SetFrameLevel(button:GetFrameLevel())
	local edge, bg = Flat(square, "field", 0.9, 0.5)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(square)
	hover:SetColorTexture(1, 1, 1, 0.12)
	local x = square:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	x:SetPoint("CENTER", 0, 0)
	x:SetText("X")
	Register(button, function(_, skin)
		local hd = skin == "HD"
		square:SetShown(hd)
		hover:SetShown(hd)
		edge:SetShown(hd)
		bg:SetShown(hd)
		for _, piece in ipairs(art) do piece:SetAlpha(hd and 0 or 1) end
	end)
	return button
end

-- A window (or, inset, a box inside one) made with BackdropTemplate, in
-- both looks: SD the backdrop it has (set it, and its colours, first), HD
-- flat, dark with a thin edge. Checks the look as it opens.
function ns.SkinWindow(frame, inset)
	local info = frame.backdropInfo
	local bgColor = info and { frame:GetBackdropColor() }
	local borderColor = info and { frame:GetBackdropBorderColor() }
	local edge, bg
	if inset then
		edge, bg = Flat(frame, "well", 0.8, 0.5)
	else
		edge, bg = Flat(frame, "window", 0.95, 0.6)
	end
	Register(frame, function(self, skin)
		local hd = skin == "HD" or not info
		edge:SetShown(hd)
		bg:SetShown(hd)
		if not (info and self.SetBackdrop) then return end
		if hd then
			self:SetBackdrop(nil)
		elseif not self.backdropInfo then
			self:SetBackdrop(info)
			if bgColor[1] then self:SetBackdropColor(unpack(bgColor)) end
			if borderColor[1] then self:SetBackdropBorderColor(unpack(borderColor)) end
		end
	end)
	if not inset then frame:HookScript("OnShow", function() ns.ApplyMenuSkin() end) end
	return frame
end

-- A UICheckButtonTemplate checkbox in both looks. HD: a small flat square
-- in the middle of the game's room for it, a gold square in it while ticked,
-- dimmed while greyed. Its label stays as it is. round: a radio button's,
-- a circle with a gold dot.
function ns.SkinCheck(check, round)
	local art = TexturesOf(check)
	local box = CreateFrame("Frame", nil, check)
	box:SetSize(14, 14)
	box:SetPoint("CENTER")
	box:SetFrameLevel(check:GetFrameLevel())
	-- (Its left on a whole screen pixel: a column that lands between two lost
	-- its 1-pixel side edges, the top and bottom still drawn. Across only:
	-- scrolling moves it down and up.)
	box:HookScript("OnShow", function()
		local left = check:GetLeft()
		local scale = box:GetEffectiveScale()
		if not (left and scale and scale > 0 and PixelUtil and PixelUtil.GetPixelToUIUnitFactor) then return end
		local px = PixelUtil.GetPixelToUIUnitFactor() / scale
		local at = (left + (check:GetWidth() - box:GetWidth()) / 2) / px
		box:SetPoint("CENTER", (math.floor(at + 0.5) - at) * px, 0)
	end)
	local edge, bg = Flat(box, "field", 0.9, 0.6)
	if round then
		Tone(edge, "edge", 0.6, true)
		Tone(bg, "field", 0.9, true)
	end
	local tick = box:CreateTexture(nil, "ARTWORK")
	tick:SetSize(8, 8)
	tick:SetPoint("CENTER")
	Tone(tick, "accent", 1, round)
	local hover = check:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(box)
	PaintTexture(hover, round, 1, 1, 1, 0.12)
	local hd = false
	local function Show()
		tick:SetShown(hd and check:GetChecked() and true or false)
		box:SetAlpha(Enabled(check) and 1 or 0.45)
	end
	hooksecurefunc(check, "SetChecked", Show)
	-- (PostClick, not OnClick: the checkbox makers set OnClick after this,
	-- which would take a hook on it away, leaving the tick as it was.)
	check:HookScript("PostClick", Show)
	OnEnabledChange(check, Show)
	Register(check, function(_, skin)
		hd = skin == "HD"
		box:SetShown(hd)
		hover:SetShown(hd)
		ShowArt(art, not hd)
		Show()
	end)
	return check
end

-- A slider (OptionsSliderTemplate, or the plain one where there's none) in
-- both looks. HD: a thin flat track, gold up to the thumb, and a light
-- flat thumb; dimmed while greyed. The thumb's still the game's, unseen, so
-- dragging is as it was.
function ns.SkinSlider(slider)
	local thumb = slider:GetThumbTexture()
	local art = TexturesOf(slider)
	for _, child in ipairs({ slider:GetChildren() }) do
		for _, piece in ipairs(TexturesOf(child)) do art[#art + 1] = piece end
	end
	local track = CreateFrame("Frame", nil, slider)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetFrameLevel(slider:GetFrameLevel())
	Flat(track, "field", 0.9, 0.6)
	local fill, knob
	if thumb then
		fill = track:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("LEFT", track, "LEFT")
		fill:SetPoint("RIGHT", thumb, "CENTER")
		fill:SetHeight(4)
		Tone(fill, "accent", 0.75)
		knob = slider:CreateTexture(nil, "OVERLAY")
		knob:SetSize(8, 14)
		knob:SetPoint("CENTER", thumb, "CENTER")
		Tone(knob, "knob", 1)
	end
	local function Dim()
		local alpha = Enabled(slider) and 1 or 0.45
		track:SetAlpha(alpha)
		if knob then knob:SetAlpha(alpha) end
	end
	OnEnabledChange(slider, Dim)
	Register(slider, function(_, skin)
		local hd = skin == "HD"
		track:SetShown(hd)
		if knob then knob:SetShown(hd) end
		ShowArt(art, not hd)
		Dim()
	end)
	return slider
end

-- A WowStyle1DropdownTemplate dropdown in both looks. HD: flat, dark, a thin
-- edge, a lighter hover; its arrow and text stay.
function ns.SkinDropdown(dropdown)
	local art = TexturesOf(dropdown, dropdown.Arrow and { [dropdown.Arrow] = true })
	local edge, bg = Flat(dropdown, "field", 0.9, 0.5)
	local hover = dropdown:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.08)
	Register(dropdown, function(_, skin)
		local hd = skin == "HD"
		edge:SetShown(hd)
		bg:SetShown(hd)
		hover:SetShown(hd)
		ShowArt(art, not hd)
	end)
	return dropdown
end

-- A menu's list (and each submenu's) longer than MENU_ROWS entries scrolls,
-- that many tall: else a long one runs off the screen and its last entries
-- can't be reached. (After the menu's made: its entries counted.)
local MENU_ROWS, MENU_ROW_H = 15, 20
function ns.ScrollMenu(description)
	if not description then return end
	local list = description.elementDescriptions
	if type(list) ~= "table" and description.EnumerateElementDescriptions then
		list = {}
		for _, child in description:EnumerateElementDescriptions() do list[#list + 1] = child end
	end
	if type(list) ~= "table" then return end
	if #list > MENU_ROWS and description.SetScrollMode then description:SetScrollMode(MENU_ROWS * MENU_ROW_H) end
	for _, child in ipairs(list) do ns.ScrollMenu(child) end
end

-- A right-click menu (MenuUtil.CreateContextMenu's), its long lists
-- scrolling.
function ns.ContextMenu(owner, generator)
	return MenuUtil.CreateContextMenu(owner, function(menuOwner, root, ...)
		generator(menuOwner, root, ...)
		ns.ScrollMenu(root)
	end)
end

-- A new dropdown on parent in both looks, given as pcall(CreateFrame, ...)
-- gives it: ok and the dropdown (ok false where the client has no
-- DropdownButton or the template). Its long lists scroll (ns.ScrollMenu).
function ns.MenuDropdown(parent)
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then
		ns.SkinDropdown(dropdown)
		local setup = dropdown.SetupMenu
		dropdown.SetupMenu = function(self, generator)
			return setup(self, function(owner, root, ...)
				generator(owner, root, ...)
				ns.ScrollMenu(root)
			end)
		end
		-- Rebuilding a scrolling menu while it's open (a pick that refreshes
		-- the page) re-lays its list at the old scroll offset: entries jump
		-- and overlap. So while it's open the rebuild waits until it closes.
		local generate = dropdown.GenerateMenu
		if generate and dropdown.IsMenuOpen then
			local waiting
			local function Later(self)
				if self:IsMenuOpen() then
					C_Timer.After(0.05, function() Later(self) end)
				else
					waiting = nil
					generate(self)
				end
			end
			dropdown.GenerateMenu = function(self, ...)
				if not self:IsMenuOpen() then return generate(self, ...) end
				if waiting then return end
				waiting = true
				C_Timer.After(0, function() Later(self) end)
			end
		end
	end
	return ok, dropdown
end

-- An InputBoxTemplate text box in both looks. HD: a flat dark well with a
-- thin edge where the game's art was (it starts 5 left of the box, where
-- the text begins).
function ns.SkinEditBox(box)
	local art = {}
	for _, piece in ipairs({ box.Left or false, box.Middle or false, box.Right or false }) do
		if piece then art[#art + 1] = piece end
	end
	if #art == 0 then art = TexturesOf(box) end
	local edge = box:CreateTexture(nil, "BACKGROUND", nil, -8)
	SnapEdge(box, edge, 5)
	Tone(edge, "edge", 0.5)
	local bg = box:CreateTexture(nil, "BACKGROUND", nil, -7)
	bg:SetPoint("TOPLEFT", -5, 0)
	bg:SetPoint("BOTTOMRIGHT")
	Tone(bg, "well", 0.8)
	NoSnap(bg)
	Register(box, function(_, skin)
		local hd = skin == "HD"
		edge:SetShown(hd)
		bg:SetShown(hd)
		ShowArt(art, not hd)
	end)
	return box
end

-- A UIPanelScrollFrameTemplate scroll frame's bar in both looks. HD: a thin
-- flat track and a light flat thumb; its up and down buttons still there to
-- click, unseen. Where the bar isn't as expected, it's left as it is.
function ns.SkinScroll(scroll)
	local name = scroll:GetName()
	local bar = scroll.ScrollBar or (name and _G[name .. "ScrollBar"])
	local thumb = bar and bar.GetThumbTexture and bar:GetThumbTexture()
	if not thumb then return scroll end
	local art = TexturesOf(bar)
	for _, child in ipairs({ bar:GetChildren() }) do
		if child.GetNormalTexture then
			for _, piece in ipairs(ButtonArt(child)) do art[#art + 1] = piece end
		else
			for _, piece in ipairs(TexturesOf(child)) do art[#art + 1] = piece end
		end
	end
	local track = CreateFrame("Frame", nil, bar)
	track:SetPoint("TOP", 0, 14)
	track:SetPoint("BOTTOM", 0, -14)
	track:SetWidth(6)
	track:SetFrameLevel(bar:GetFrameLevel())
	Flat(track, "field", 0.6, 0.35)
	local knob = bar:CreateTexture(nil, "OVERLAY")
	knob:SetWidth(6)
	knob:SetPoint("TOP", thumb, "TOP", 0, -2)
	knob:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 2)
	Tone(knob, "thumb", 0.9)
	Register(bar, function(_, skin)
		local hd = skin == "HD"
		track:SetShown(hd)
		knob:SetShown(hd)
		ShowArt(art, not hd)
	end)
	return scroll
end

-- Each of these on a control the page goes on to use: one that goes wrong
-- leaves the control in the game's look (the first error reported, once),
-- never stops the page being made.
for _, name in ipairs({ "SkinButton", "SkinClose", "SkinWindow", "SkinCheck", "SkinSlider", "SkinDropdown",
	"SkinEditBox", "SkinScroll" }) do
	local skin = ns[name]
	ns[name] = function(control, ...)
		local ok, err = pcall(skin, control, ...)
		if not ok and not reported then
			reported = true
			geterrorhandler()(err)
		end
		-- (What's asked of a skinned button, there even when it didn't take.)
		if name == "SkinButton" and control then
			control.SetSkinEdge = control.SetSkinEdge or function() end
			control.SetSkinTint = control.SetSkinTint or function() end
		end
		return control
	end
end
