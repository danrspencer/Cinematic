-- Real layout for the offline stand-in (Tools/offline/wow.lua): frames keep
-- their anchors, sizes, textures, fonts and colors, and work out where they
-- are as the game would, so the addon's own preview code can be run outside
-- the game and what it drew read back (Dump). For Tools/style-lab, not the
-- addon. Install(wow) before the addon's files load.

local F = {}

local UI_W, UI_H = 1920, 1080

-- The game's font objects the addon asks for by name: file, size, color.
local FRIZ, ARIALN = "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF"
local GOLD, WHITE, GREY = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.5, 0.5, 0.5 }
local FONTS = {
	GameFontNormal = { FRIZ, 12, GOLD }, GameFontNormalSmall = { FRIZ, 10, GOLD },
	GameFontNormalLarge = { FRIZ, 16, GOLD }, GameFontNormalHuge = { FRIZ, 20, GOLD },
	GameFontNormalMed3 = { FRIZ, 14, GOLD }, GameFontNormalMed2 = { FRIZ, 14, GOLD },
	GameFontHighlight = { FRIZ, 12, WHITE }, GameFontHighlightSmall = { FRIZ, 10, WHITE },
	GameFontHighlightLarge = { FRIZ, 16, WHITE }, GameFontHighlightMedium = { FRIZ, 14, WHITE },
	GameFontHighlightHuge = { FRIZ, 20, WHITE }, GameFontHighlightOutline = { FRIZ, 12, WHITE, "OUTLINE" },
	GameFontDisable = { FRIZ, 12, GREY }, GameFontDisableSmall = { FRIZ, 10, GREY },
	GameFontDisableLarge = { FRIZ, 16, GREY }, GameFontWhite = { FRIZ, 12, WHITE },
	GameFontRed = { FRIZ, 12, { 1, 0.1, 0.1 } }, GameFontGreen = { FRIZ, 12, { 0.1, 1, 0.1 } },
	GameTooltipHeaderText = { FRIZ, 14, WHITE }, GameTooltipText = { FRIZ, 12, WHITE },
	GameTooltipTextSmall = { FRIZ, 10, WHITE }, NumberFontNormal = { ARIALN, 14, WHITE, "OUTLINE" },
	NumberFontNormalSmall = { ARIALN, 12, WHITE, "OUTLINE" }, ChatFontNormal = { ARIALN, 14, WHITE },
	SystemFont_Shadow_Med1 = { FRIZ, 12, WHITE }, QuestFont = { FRIZ, 13, { 0.1, 0.07, 0.03 } },
	SubZoneTextFont = { FRIZ, 26, GOLD }, ZoneTextFont = { FRIZ, 32, GOLD },
}

local gen = 0 -- (layout changed: every worked-out rect is stale)
local function Dirty() gen = gen + 1 end

-- How wide text is, near enough, without its font.
local function TextWidth(text, size)
	text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  ")
	local width, line = 0, 0
	for i = 1, #text do
		local c = text:sub(i, i)
		if c == "\n" then
			width = math.max(width, line)
			line = 0
		elseif c:byte() < 128 or c:byte() >= 192 then
			line = line + size * (c:find("[ilj%.,'!t]") and 0.3 or c:find("[MWmw]") and 0.8 or 0.52)
		end
	end
	return math.max(width, line)
end

local function Scale(o)
	local s = 1
	while o do
		s = s * (rawget(o, "_scale") or 1)
		o = rawget(o, "_parent")
	end
	return s
end
local function Alpha(o)
	local a = 1
	while o do
		a = a * (rawget(o, "_alpha") or 1)
		o = rawget(o, "_parent")
	end
	return a
end
local function Visible(o)
	while o do
		if rawget(o, "_shown") == false then return false end
		o = rawget(o, "_parent")
	end
	return true
end
F.Alpha, F.Visible, F.Scale = Alpha, Visible, Scale

local Rect

local function TextHeight(o)
	local text, size = o._text, o._fontSize or 12
	if not text or text == "" then return 0 end
	local lines = 1
	for _ in tostring(text):gmatch("\n") do lines = lines + 1 end
	local width = rawget(o, "_w") or rawget(o, "_anchorW")
	if width and width > 0 and rawget(o, "_wrap") ~= false then
		lines = math.max(lines, math.ceil(TextWidth(text, size) / width))
	end
	return lines * (size + (rawget(o, "_spacing") or 0) + 1)
end

-- Natural size: what it was given, or a text's own.
local function Natural(o)
	local w, h = rawget(o, "_w"), rawget(o, "_h")
	if o._kind == "FontString" then
		w = (w and w > 0) and w or TextWidth(o._text, rawget(o, "_fontSize") or 12)
		h = (h and h > 0) and h or TextHeight(o)
	end
	return w or 0, h or 0
end

local PX = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1,
	BOTTOMRIGHT = 1 }
local PY = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, BOTTOMLEFT = 0, BOTTOM = 0,
	BOTTOMRIGHT = 0 }

-- The rect, in screen units, y up: left, bottom, width, height (nil: no anchors,
-- not drawn; a loop of anchors comes out nil too).
function Rect(o)
	if rawget(o, "_rectGen") == gen then
		local r = rawget(o, "_rect")
		if r then return r[1], r[2], r[3], r[4] end
		return nil
	end
	if rawget(o, "_inRect") then return nil end
	o._inRect = true
	local left, bottom, width, height
	local scale = Scale(o)
	local fillOf = rawget(o, "_fillOf")
	if o._name == "UIParent" or o._name == "WorldFrame" then
		left, bottom, width, height = 0, 0, UI_W, UI_H
	elseif fillOf then
		-- (A status bar's fill: as long as its value.)
		local bar = fillOf
		local l, b, w, h = Rect(bar)
		if l then
			local lo, hi = rawget(bar, "_min") or 0, rawget(bar, "_max") or 1
			local value = rawget(bar, "_value") or 0
			local part = hi > lo and math.max(0, math.min(1, (value - lo) / (hi - lo))) or 0
			if rawget(bar, "_orient") == "VERTICAL" then
				left, bottom, width, height = l, b, w, h * part
			elseif rawget(bar, "_reverse") then
				left, bottom, width, height = l + w * (1 - part), b, w * part, h
			else
				left, bottom, width, height = l, b, w * part, h
			end
		end
	else
		local points = rawget(o, "_points")
		if points and #points > 0 then
			local nw, nh = Natural(o)
			nw, nh = nw * scale, nh * scale
			local xl, xr, xc, yb, yt, yc
			for _, p in ipairs(points) do
				local rel = p[2]
				if type(rel) == "string" then rel = _G[rel] end
				if type(rel) ~= "table" or not rawget(rel, "_kind") then rel = rawget(o, "_parent") end
				local l, b, w, h
				if rel then l, b, w, h = Rect(rel) end
				if l then
					local x = l + w * PX[p[3]] + (p[4] or 0) * scale
					local y = b + h * PY[p[3]] + (p[5] or 0) * scale
					local fx, fy = PX[p[1]], PY[p[1]]
					if fx == 0 then xl = x elseif fx == 1 then xr = x else xc = x end
					if fy == 0 then yb = y elseif fy == 1 then yt = y else yc = y end
				end
			end
			if xl and xr then
				left, width = xl, xr - xl
			elseif xl then
				left, width = xl, nw
			elseif xr then
				left, width = xr - nw, nw
			elseif xc then
				left, width = xc - nw / 2, nw
			end
			if yb and yt then
				bottom, height = yb, yt - yb
			elseif yb then
				bottom, height = yb, nh
			elseif yt then
				bottom, height = yt - nh, nh
			elseif yc then
				bottom, height = yc - nh / 2, nh
			end
			if left and not bottom then bottom, height = 0, nh end
			if bottom and not left then left, width = 0, nw end
			-- (A text between two anchors wraps to them: taller than one line.)
			if o._kind == "FontString" and left and xl and xr and not (yb and yt) then
				o._anchorW = width / scale
				local h2 = TextHeight(o) * scale
				if yt then bottom = yt - h2 elseif yc then bottom = yc - h2 / 2 elseif yb then bottom = yb end
				height = h2
			end
		end
	end
	o._inRect = nil
	o._rectGen = gen
	if left then
		o._rect = { left, bottom, width, height }
		return left, bottom, width, height
	end
	o._rect = nil
	return nil
end
F.Rect = Rect

function F.Install(wow)
	local M = wow.Methods
	local NewObject = wow.NewObject
	local order = 0
	local function Next()
		order = order + 1
		return order
	end

	local function Set(name, fn) M[name] = fn end

	-- Anchors and size.
	local function Point(self, point, a, b, c, d)
		local relative, relPoint, x, y
		if type(a) == "number" then
			x, y = a, b
		elseif type(b) == "number" then
			relative, x, y = a, b, c
		else
			relative, relPoint, x, y = a, b, c, d
		end
		point = tostring(point):upper()
		relPoint = relPoint and tostring(relPoint):upper() or point
		if not PX[point] or not PX[relPoint] then return end
		local points = rawget(self, "_points")
		if not points then
			points = {}
			self._points = points
		end
		for i, each in ipairs(points) do
			if each[1] == point then
				table.remove(points, i)
				break
			end
		end
		points[#points + 1] = { point, relative or rawget(self, "_parent"), relPoint, tonumber(x) or 0, tonumber(y) or 0 }
		Dirty()
	end
	Set("SetPoint", Point)
	Set("ClearAllPoints", function(self)
		self._points = nil
		Dirty()
	end)
	Set("SetAllPoints", function(self, relative)
		if relative == true or relative == nil then relative = rawget(self, "_parent") end
		self._points = { { "TOPLEFT", relative, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", relative, "BOTTOMRIGHT", 0, 0 } }
		Dirty()
	end)
	Set("GetNumPoints", function(self)
		local points = rawget(self, "_points")
		return points and #points or 0
	end)
	Set("GetPoint", function(self, i)
		local points = rawget(self, "_points")
		local p = points and points[i or 1]
		if p then return p[1], p[2], p[3], p[4], p[5] end
	end)
	local function Size(self, w, h)
		-- (A stub's "number", from a game frame that isn't here: nothing.)
		if type(w) ~= "number" then w = 0 end
		if type(h) ~= "number" then h = h == nil and w or 0 end
		self._w, self._h = w, h
		Dirty()
		local script = self._scripts and self._scripts.OnSizeChanged
		if script and not rawget(self, "_inSize") then
			self._inSize = true
			pcall(script, self, self._w, self._h)
			self._inSize = nil
		end
	end
	Set("SetSize", Size)
	Set("SetWidth", function(self, w) Size(self, w, rawget(self, "_h") or 0) end)
	Set("SetHeight", function(self, h) Size(self, rawget(self, "_w") or 0, h) end)
	Set("SetScale", function(self, s)
		self._scale = s
		Dirty()
	end)
	Set("GetScale", function(self) return rawget(self, "_scale") or 1 end)
	Set("GetEffectiveScale", function(self) return Scale(self) end)
	Set("SetParent", function(self, parent)
		local old = rawget(self, "_parent")
		if old and rawget(old, "_children") then
			for i, child in ipairs(old._children) do
				if child == self then
					table.remove(old._children, i)
					break
				end
			end
		end
		-- (A texture or text moves with its list too: hiding the new parent hides it.)
		local region = false
		if old and rawget(old, "_regions") then
			for i, each in ipairs(old._regions) do
				if each == self then
					table.remove(old._regions, i)
					region = true
					break
				end
			end
		end
		self._parent = parent
		if parent and rawget(parent, "_children") then table.insert(parent._children, self) end
		if region and parent and rawget(parent, "_regions") then table.insert(parent._regions, self) end
		Dirty()
	end)
	local function Own(self, fn)
		local l, b, w, h = Rect(self)
		if not l then return nil end
		local s = Scale(self)
		return fn(l / s, b / s, w / s, h / s)
	end
	Set("GetLeft", function(self) return Own(self, function(l) return l end) end)
	Set("GetRight", function(self) return Own(self, function(l, _, w) return l + w end) end)
	Set("GetBottom", function(self) return Own(self, function(_, b) return b end) end)
	Set("GetTop", function(self) return Own(self, function(_, b, _, h) return b + h end) end)
	Set("GetCenter", function(self)
		local l, b, w, h = Rect(self)
		if not l then return nil end
		local s = Scale(self)
		return (l + w / 2) / s, (b + h / 2) / s
	end)
	local function Width(self)
		local l, _, w = Rect(self)
		if l then return w / Scale(self) end
		return (Natural(self))
	end
	local function Height(self)
		local l, _, _, h = Rect(self)
		if l then return h / Scale(self) end
		return select(2, Natural(self))
	end
	Set("GetWidth", Width)
	Set("GetHeight", Height)
	Set("GetSize", function(self) return Width(self), Height(self) end)
	Set("GetRect", function(self)
		local l, b, w, h = Rect(self)
		if not l then return nil end
		local s = Scale(self)
		return l / s, b / s, w / s, h / s
	end)

	-- Shown, alpha, levels.
	Set("SetAlpha", function(self, a) self._alpha = a end)
	Set("GetAlpha", function(self) return rawget(self, "_alpha") or 1 end)
	Set("GetEffectiveAlpha", function(self) return Alpha(self) end)
	Set("IsVisible", function(self) return Visible(self) end)
	local function Fire(self, script)
		local fn = self._scripts and self._scripts[script]
		if fn then pcall(fn, self) end
	end
	Set("Show", function(self)
		local was = rawget(self, "_shown")
		self._shown = true
		if not was then Fire(self, "OnShow") end
	end)
	Set("Hide", function(self) self._shown = false end)
	Set("SetShown", function(self, shown)
		if shown then self:Show() else self:Hide() end
	end)
	Set("SetFrameLevel", function(self, level) self._level = level end)
	Set("GetFrameLevel", function(self)
		local level = rawget(self, "_level")
		if level then return level end
		local parent = rawget(self, "_parent")
		return parent and parent.GetFrameLevel and parent:GetFrameLevel() + 1 or 0
	end)
	Set("SetFrameStrata", function(self, strata) self._strata = strata end)
	Set("GetFrameStrata", function(self) return rawget(self, "_strata") or "MEDIUM" end)
	Set("SetClipsChildren", function(self, on) self._clips = on end)

	-- Regions.
	local function Region(self, kind, name, layer, sub)
		local r = NewObject(kind, name, self)
		table.insert(self._regions, r)
		r._layer, r._sub = layer or (kind == "FontString" and "OVERLAY" or "ARTWORK"), sub or 0
		r._order = Next()
		return r
	end
	Set("CreateTexture", function(self, name, layer, _, sub) return Region(self, "Texture", name, layer, sub) end)
	Set("CreateMaskTexture", function(self, name, layer, _, sub)
		local r = Region(self, "Texture", name, layer, sub)
		r._isMask = true
		return r
	end)
	Set("CreateLine", function(self, name, layer)
		local r = Region(self, "Texture", name, layer)
		r._isLine = true
		return r
	end)
	Set("CreateFontString", function(self, name, layer, template)
		local r = Region(self, "FontString", name, layer)
		r._wrap = true
		if template then r:SetFontObject(template) end
		return r
	end)
	Set("GetDrawLayer", function(self) return self._layer, self._sub end)
	Set("SetDrawLayer", function(self, layer, sub) self._layer, self._sub = layer, sub or 0 end)

	-- Textures.
	Set("SetTexture", function(self, file)
		self._file, self._atlas, self._color = file, nil, nil
		return true
	end)
	Set("GetTexture", function(self) return rawget(self, "_file") or rawget(self, "_atlas") end)
	Set("SetAtlas", function(self, atlas)
		self._atlas, self._file, self._color = atlas, nil, nil
		return true
	end)
	Set("GetAtlas", function(self) return rawget(self, "_atlas") end)
	Set("SetColorTexture", function(self, r, g, b, a)
		self._color, self._file, self._atlas = { r or 0, g or 0, b or 0, a or 1 }, nil, nil
	end)
	Set("SetVertexColor", function(self, r, g, b, a) self._vc = { r or 1, g or 1, b or 1, a or 1 } end)
	Set("GetVertexColor", function(self)
		local c = rawget(self, "_vc") or { 1, 1, 1, 1 }
		return c[1], c[2], c[3], c[4]
	end)
	Set("SetTexCoord", function(self, ...) self._coord = { ... } end)
	Set("GetTexCoord", function(self)
		local c = rawget(self, "_coord")
		if c then return unpack(c) end
		return 0, 1, 0, 1
	end)
	Set("SetHorizTile", function(self, on) self._tile = on end)
	Set("SetVertTile", function() end)
	Set("SetDesaturated", function(self, on) self._desat = on and true or false end)
	Set("SetBlendMode", function(self, mode) self._blend = mode end)
	Set("SetRotation", function(self, angle) self._rot = angle end)
	Set("SetGradient", function(self, orient, a, b)
		if type(a) == "table" and type(b) == "table" then
			self._grad = { orient, { a.r or a[1], a.g or a[2], a.b or a[3], a.a or a[4] or 1 },
				{ b.r or b[1], b.g or b[2], b.b or b[3], b.a or b[4] or 1 } }
		end
	end)
	Set("SetGradientAlpha", function(self, orient, r1, g1, b1, a1, r2, g2, b2, a2)
		self._grad = { orient, { r1, g1, b1, a1 }, { r2, g2, b2, a2 } }
	end)
	Set("AddMaskTexture", function(self, mask) self._mask = mask end)
	Set("RemoveMaskTexture", function(self) self._mask = nil end)

	-- Text.
	local function FontFrom(self, source)
		if type(source) == "string" then source = _G[source] end
		local info = type(source) == "table" and rawget(source, "_fontInfo")
		if not info then return end
		-- (The object's font as it is now: the Tooltips page sets the game's own.)
		self._font, self._fontSize = rawget(source, "_font"), rawget(source, "_fontSize")
		self._fontFlags = rawget(source, "_fontFlags") or ""
		self._textColor = { info[3][1], info[3][2], info[3][3], 1 }
		self._fontObject = source
	end
	Set("SetFontObject", function(self, source)
		FontFrom(self, source)
		Dirty()
	end)
	Set("GetFontObject", function(self) return rawget(self, "_fontObject") end)
	Set("SetFont", function(self, file, size, flags)
		self._font, self._fontSize, self._fontFlags = file, size, flags or ""
		Dirty()
		return true
	end)
	Set("GetFont", function(self)
		return rawget(self, "_font") or FRIZ, rawget(self, "_fontSize") or 12, rawget(self, "_fontFlags") or ""
	end)
	Set("SetText", function(self, text)
		if self._kind == "Button" then
			self:GetFontString()._text = text
		else
			self._text = text
		end
		Dirty()
	end)
	Set("GetText", function(self)
		if self._kind == "Button" then
			local label = rawget(self, "_label")
			return label and label._text
		end
		return rawget(self, "_text")
	end)
	Set("SetFormattedText", function(self, fmt, ...) self:SetText(fmt:format(...)) end)
	Set("SetTextColor", function(self, r, g, b, a) self._textColor = { r or 1, g or 1, b or 1, a or 1 } end)
	Set("GetTextColor", function(self)
		local c = rawget(self, "_textColor") or { 1, 1, 1, 1 }
		return c[1], c[2], c[3], c[4]
	end)
	Set("SetShadowColor", function(self, r, g, b, a) self._shadowColor = { r, g, b, a or 1 } end)
	Set("GetShadowColor", function(self)
		local c = rawget(self, "_shadowColor") or { 0, 0, 0, 1 }
		return c[1], c[2], c[3], c[4]
	end)
	Set("SetShadowOffset", function(self, x, y) self._shadow = { x or 0, y or 0 } end)
	Set("GetShadowOffset", function(self)
		local s = rawget(self, "_shadow") or { 0, 0 }
		return s[1], s[2]
	end)
	Set("SetJustifyH", function(self, how) self._justH = how end)
	Set("GetJustifyH", function(self) return rawget(self, "_justH") or "CENTER" end)
	Set("SetJustifyV", function(self, how) self._justV = how end)
	Set("GetJustifyV", function(self) return rawget(self, "_justV") or "MIDDLE" end)
	Set("SetWordWrap", function(self, on) self._wrap = on end)
	Set("SetSpacing", function(self, n) self._spacing = n end)
	Set("SetMaxLines", function(self, n) self._maxLines = n end)
	Set("GetStringWidth", function(self) return TextWidth(rawget(self, "_text"), rawget(self, "_fontSize") or 12) end)
	Set("GetUnboundedStringWidth", function(self)
		return TextWidth(rawget(self, "_text"), rawget(self, "_fontSize") or 12)
	end)
	Set("GetStringHeight", function(self) return TextHeight(self) end)
	Set("GetLineHeight", function(self) return (rawget(self, "_fontSize") or 12) + 1 end)
	Set("GetNumLines", function(self)
		return math.max(1, math.floor(TextHeight(self) / ((rawget(self, "_fontSize") or 12) + 1)))
	end)

	-- Status bars.
	local function Fill(self)
		local fill = rawget(self, "_fill")
		if not fill then
			fill = self:CreateTexture(nil, "ARTWORK")
			fill._fillOf = self
			self._fill = fill
		end
		return fill
	end
	Set("SetStatusBarTexture", function(self, file)
		local fill = Fill(self)
		if type(file) == "table" then
			fill._file, fill._atlas, fill._color = rawget(file, "_file"), rawget(file, "_atlas"), rawget(file, "_color")
		else
			fill._file, fill._atlas, fill._color = file, nil, nil
		end
		return true
	end)
	Set("GetStatusBarTexture", function(self) return Fill(self) end)
	Set("SetStatusBarColor", function(self, r, g, b, a) Fill(self)._vc = { r or 1, g or 1, b or 1, a or 1 } end)
	Set("GetStatusBarColor", function(self)
		local c = rawget(Fill(self), "_vc") or { 1, 1, 1, 1 }
		return c[1], c[2], c[3], c[4]
	end)
	Set("SetMinMaxValues", function(self, lo, hi)
		self._min, self._max = lo, hi
		Dirty()
	end)
	Set("GetMinMaxValues", function(self) return rawget(self, "_min") or 0, rawget(self, "_max") or 1 end)
	Set("SetValue", function(self, value)
		self._value = value
		Dirty()
	end)
	Set("GetValue", function(self) return rawget(self, "_value") or 0 end)
	Set("SetOrientation", function(self, how)
		self._orient = how
		Dirty()
	end)
	Set("SetReverseFill", function(self, on)
		self._reverse = on
		Dirty()
	end)
	Set("SetFillStyle", function(self, how)
		self._reverse = how == "REVERSE"
		Dirty()
	end)

	-- Buttons.
	local function ButtonPiece(key)
		return function(self, file)
			local piece = rawget(self, key)
			if not piece then
				piece = self:CreateTexture(nil, key == "_highlightTex" and "HIGHLIGHT" or "ARTWORK")
				piece:SetAllPoints()
				self[key] = piece
				if key == "_pushedTex" or key == "_disabledTex" then piece._shown = false end
			end
			if type(file) == "table" then
				piece._file, piece._atlas = rawget(file, "_file"), rawget(file, "_atlas")
			else
				piece._file = file
			end
		end
	end
	local function ButtonGet(key)
		return function(self) return rawget(self, key) end
	end
	for name, key in pairs({ Normal = "_normalTex", Pushed = "_pushedTex", Disabled = "_disabledTex",
		Highlight = "_highlightTex", Checked = "_checkedTex" }) do
		Set("Set" .. name .. "Texture", ButtonPiece(key))
		Set("Get" .. name .. "Texture", ButtonGet(key))
	end
	Set("GetFontString", function(self)
		local label = rawget(self, "_label")
		if not label then
			label = self:CreateFontString(nil, "OVERLAY", rawget(self, "_normalFont") or "GameFontNormal")
			label:SetPoint("CENTER")
			self._label = label
		end
		return label
	end)
	Set("SetFontString", function(self, label) self._label = label end)
	Set("SetNormalFontObject", function(self, source)
		self._normalFont = source
		self:GetFontString():SetFontObject(source)
	end)
	Set("SetEnabled", function(self, on) self._disabled = not on end)
	Set("Enable", function(self) self._disabled = false end)
	Set("Disable", function(self) self._disabled = true end)
	Set("IsEnabled", function(self) return not rawget(self, "_disabled") end)
	Set("GetThumbTexture", function(self) return rawget(self, "_thumb") end)
	Set("SetThumbTexture", function(self, file)
		local thumb = rawget(self, "_thumb") or self:CreateTexture(nil, "OVERLAY")
		thumb._file = file
		self._thumb = thumb
	end)

	-- Backdrops.
	Set("SetBackdrop", function(self, info) self.backdropInfo = info end)
	Set("SetBackdropColor", function(self, r, g, b, a) self._bdColor = { r, g, b, a or 1 } end)
	Set("GetBackdropColor", function(self)
		local c = rawget(self, "_bdColor") or { 1, 1, 1, 1 }
		return c[1], c[2], c[3], c[4]
	end)
	Set("SetBackdropBorderColor", function(self, r, g, b, a) self._bdEdge = { r, g, b, a or 1 } end)
	Set("GetBackdropBorderColor", function(self)
		local c = rawget(self, "_bdEdge") or { 1, 1, 1, 1 }
		return c[1], c[2], c[3], c[4]
	end)

	-- Font objects and the things the stand-in's stub would swallow.
	for name, info in pairs(FONTS) do
		local object = NewObject("Font", name)
		object._fontInfo = info
		object._font, object._fontSize, object._fontFlags = info[1], info[2], info[4] or ""
		_G[name] = object
	end
	_G.GetScreenWidth = function() return UI_W end
	_G.GetScreenHeight = function() return UI_H end
	-- (Hooks on a frame run; hooks on the game's functions are nothing here.)
	_G.hooksecurefunc = function(a, b, c)
		if type(a) ~= "table" or not rawget(a, "_kind") then return end
		local old = a[b]
		rawset(a, b, function(...)
			local r = { old(...) }
			c(...)
			return unpack(r)
		end)
	end
	_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
	-- (What the game's templates would have given a new frame.)
	local TEMPLATES = { UIPanelButtonTemplate = { 120, 22 }, WowStyle1DropdownTemplate = { 150, 26 },
		UICheckButtonTemplate = { 26, 26 }, OptionsSliderTemplate = { 144, 17 }, InputBoxTemplate = { 100, 20 },
		UIPanelCloseButton = { 24, 24 } }
	local create = _G.CreateFrame
	_G.CreateFrame = function(kind, name, parent, template)
		local frame = create(kind, name, parent, template)
		local size = type(template) == "string" and TEMPLATES[template]
		if size then frame._w, frame._h = size[1], size[2] end
		if template == "UICheckButtonTemplate" and frame.Text then
			frame.Text:SetFontObject("GameFontHighlight")
			frame.Text:SetPoint("LEFT", frame, "RIGHT", 2, 0)
		end
		if template == "OptionsSliderTemplate" then
			frame:SetThumbTexture("")
			frame._thumb:SetSize(16, 16)
			frame._thumb:SetPoint("CENTER", frame, "LEFT", 72, 0)
		end
		return frame
	end
	Set("SetDefaultText", function(self, text) self:SetText(text) end)
	Set("OverrideText", function(self, text) self:SetText(text) end)
	-- (The modern atlases: there, as on retail.)
	_G.C_Texture = { GetAtlasInfo = function(name) return { file = name, width = 64, height = 64 } end }
end

-- Everything drawn under root, back to front, relative to root's top left:
-- { k, x, y, w, h, ... } each, in screen units, y down.
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7,
	TOOLTIP = 8 }
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

function F.Dump(root)
	local items, seq = {}, 0
	local rl, rb, rw, rh = Rect(root)
	if not rl then return items, 0, 0 end
	local function Top(y) return rb + rh - y end
	local function Clip(frame, clip)
		if not rawget(frame, "_clips") then return clip end
		local l, b, w, h = Rect(frame)
		if not l then return clip end
		local box = { l - rl, Top(b + h), w, h }
		if clip then
			local x2 = math.min(box[1] + box[3], clip[1] + clip[3])
			local y2 = math.min(box[2] + box[4], clip[2] + clip[4])
			box[1], box[2] = math.max(box[1], clip[1]), math.max(box[2], clip[2])
			box[3], box[4] = x2 - box[1], y2 - box[2]
		end
		return box
	end
	local function Emit(region, clip, strata, level)
		if rawget(region, "_isMask") or region._layer == "HIGHLIGHT" then return end
		if rawget(region, "_shown") == false then return end
		local l, b, w, h = Rect(region)
		if not l or w <= 0 or h <= 0 then return end
		local alpha = Alpha(region)
		if alpha <= 0.002 then return end
		seq = seq + 1
		local item = { x = l - rl, y = Top(b + h), w = w, h = h, a = alpha, clip = clip,
			z = { strata, level, LAYER[region._layer] or 3, region._sub or 0, seq } }
		local get = function(key) return rawget(region, key) end
		if region._kind == "FontString" then
			local text = get("_text")
			if not text or text == "" then return end
			item.k = "text"
			item.text = tostring(text)
			item.font = get("_font") or FRIZ
			item.size = (get("_fontSize") or 12) * Scale(region)
			item.flags = get("_fontFlags") or ""
			item.color = get("_textColor") or { 1, 1, 1, 1 }
			item.shadow = get("_shadow")
			item.shadowColor = get("_shadowColor")
			item.justH = get("_justH")
			item.justV = get("_justV")
			item.wrap = get("_wrap")
			item.spacing = get("_spacing")
			-- (No height of its own: it grows from its anchor too, whatever its lines come to.)
			local top = get("_points") and get("_points")[1]
			if top and (get("_h") or 0) <= 0 and PY[top[1]] == 1 then item.justV = "TOP" end
			-- (No width of its own: it grows from its anchor, whatever the font's width.)
			local points = get("_points")
			if (get("_w") or 0) <= 0 and points and #points == 1 then
				local side = PX[points[1][1]]
				item.ax = side == 0 and "l" or side == 1 and "r" or "c"
			end
		else
			if not (get("_file") or get("_atlas") or get("_color") or get("_grad")) then return end
			item.k = "tex"
			local file = get("_file")
			item.file = type(file) == "string" and file or nil
			item.fileId = type(file) == "number" and file or nil
			item.atlas = get("_atlas")
			item.color = get("_color")
			item.vc = get("_vc")
			item.coord = get("_coord")
			item.desat = get("_desat")
			item.blend = get("_blend")
			item.tile = get("_tile") and true or nil
			item.rot = get("_rot")
			item.grad = get("_grad")
			local bar = get("_fillOf")
			if bar then
				local lo, hi = rawget(bar, "_min") or 0, rawget(bar, "_max") or 1
				local value = rawget(bar, "_value") or 0
				item.part = hi > lo and math.max(0, math.min(1, (value - lo) / (hi - lo))) or 0
			end
			local mask = get("_mask")
			if mask then
				item.mask = rawget(mask, "_file")
				local ml, mb, mw, mh = Rect(mask)
				if ml then item.maskRect = { ml - rl, Top(mb + mh), mw, mh } end
			end
		end
		items[#items + 1] = item
	end
	local SKIP = { Texture = true, FontString = true, AnimationGroup = true, Animation = true }
	local function Walk(frame, clip, strata, level)
		if rawget(frame, "_shown") == false or rawget(frame, "_alpha") == 0 then return end
		strata = STRATA[rawget(frame, "_strata") or ""] or strata
		level = rawget(frame, "_level") or level + 1
		local inner = Clip(frame, clip)
		local info = rawget(frame, "backdropInfo")
		if info then
			local l, b, w, h = Rect(frame)
			if l then
				seq = seq + 1
				items[#items + 1] = { k = "backdrop", x = l - rl, y = Top(b + h), w = w, h = h, a = Alpha(frame),
					clip = inner, bg = info.bgFile, edge = info.edgeFile, edgeSize = info.edgeSize,
					bgColor = rawget(frame, "_bdColor"), edgeColor = rawget(frame, "_bdEdge"),
					z = { strata, level, 0, 0, seq } }
			end
		end
		for _, region in ipairs(frame._regions or {}) do Emit(region, inner, strata, level) end
		for _, child in ipairs(frame._children or {}) do
			if not SKIP[child._kind] then Walk(child, inner, strata, level) end
		end
	end
	Walk(root, nil, 3, 0)
	table.sort(items, function(a, b)
		for i = 1, 5 do
			if a.z[i] ~= b.z[i] then return a.z[i] < b.z[i] end
		end
		return false
	end)
	for _, item in ipairs(items) do item.z = nil end
	return items, rw, rh
end

return F
