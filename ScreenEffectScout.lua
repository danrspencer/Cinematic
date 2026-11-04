-- Dev copy only (CinematicDev.toc; .pkgmeta leaves it out): /cine debug
-- screenfx plays the game's own full-screen effects (ScreenEffectsData.lua,
-- every one in the game's data) over the screen, animated, one at a time, to
-- pick looks for Vitals Vision and the like. A rebuild by eye, not the game's
-- shader: layer 1 is the shape (a mask, stretched once over the screen, never
-- tiled: tiled it drew a grid), layers 2 and 3 scroll inside it in the
-- effect's multiply colour, the overlay over them. The game's scroll and
-- scale units aren't known, so speed and tile are knobs to match it by eye
-- (2026-11-04: effect 248, Dimensius's Cosmic Void, was the first one seen).
-- Space: next, Backspace: back, while it shows (not in a fight).
-- /cine debug screenfx shots: a screenshot of each, to review them all.

local _, ns = ...

-- Hand fixes by effect id, from reviewing the shots: skip (broken or empty),
-- tile / speed (multiplies the knobs), alpha (the scrolling layers), tint
-- (the colour wash), noMask (the shape layer hides everything), swap (use
-- layer 2 as the shape). Not made by the generator: kept across rebuilds.
local FIXES = {
	[133] = { skip = "its overlay is lettering" },
	[263] = { skip = "a plain rectangle (a UI mask)" },
	[264] = { skip = "a plain rectangle (a UI mask)" },
	-- (Second shots review: these flooded the whole screen in their colour.)
	[181] = { alpha = 0.25, tint = 0.05 },
	[212] = { alpha = 0.25, tint = 0.05 },
}
ns.SCREEN_EFFECT_FIXES = FIXES

local scout, shooter
local at = 0
local speed, tile = 0.1, 1
local SHOT_WAIT = 2.5 -- (seconds on each before its screenshot: past the fade-in, moving)

-- (ns.SetOnUpdate where the protected one is loaded, else a plain OnUpdate.)
local function SetOnUpdate(frame, fn)
	if ns.SetOnUpdate then ns.SetOnUpdate(frame, fn) else frame:SetScript("OnUpdate", fn) end
end

local function Probe(file)
	scout.probe = scout.probe or scout:CreateTexture()
	return scout.probe:SetTexture(file) ~= false
end

-- How many times a layer repeats across the screen: scales from 0.1 up are
-- screens; the tiny ones (0.008, 0.01) look like per-pixel, about 100 px a tile.
local function Repeats(scale, fix)
	scale = math.abs(scale or 1)
	if scale == 0 then scale = 1 end
	if scale < 0.1 then scale = scale * 100 end
	return scale * tile * (fix.tile or 1)
end

local function Create()
	scout = CreateFrame("Frame", nil, UIParent)
	scout:SetAllPoints(UIParent)
	scout:SetFrameStrata("BACKGROUND")
	scout:SetFrameLevel(1)
	scout:EnableMouse(false)
	-- (Stays up when the UI fades or hides: the first shots run, 2026-11-04,
	-- faded out with the UI and caught nothing.)
	ns.AddOverlay(scout)
	scout.tint = scout:CreateTexture(nil, "BACKGROUND")
	scout.tint:SetAllPoints()
	scout.tint:SetColorTexture(1, 1, 1, 1)
	-- (The multiply's darkening: black over the masked part.)
	scout.darken = scout:CreateTexture(nil, "BACKGROUND", nil, 1)
	scout.darken:SetAllPoints()
	scout.darken:SetColorTexture(0, 0, 0, 1)
	scout.layers = {}
	for i = 1, 2 do
		local tex = scout:CreateTexture(nil, "BORDER", nil, i)
		tex:SetAllPoints()
		tex:SetBlendMode("ADD")
		scout.layers[i] = tex
	end
	scout.overlay = scout:CreateTexture(nil, "ARTWORK")
	scout.overlay:SetAllPoints()
	scout.overlay:SetBlendMode("ADD")
	if scout.CreateMaskTexture then
		scout.mask = scout:CreateMaskTexture()
	end
	-- (The text on its own frame, over everything, not cut by the mask.)
	local box = CreateFrame("Frame", nil, scout)
	box:SetFrameStrata("FULLSCREEN_DIALOG")
	box:SetPoint("TOPLEFT")
	box:SetPoint("TOPRIGHT")
	box:SetHeight(92)
	local back = box:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.7)
	scout.lines = {}
	for i, font in ipairs({ "GameFontNormalLarge", "GameFontHighlight", "GameFontHighlight", "GameFontHighlightSmall" }) do
		local line = box:CreateFontString(nil, "OVERLAY", font)
		line:SetPoint("TOP", 0, -8 - (i - 1) * 20)
		line:SetWidth(1400)
		line:SetWordWrap(false)
		scout.lines[i] = line
	end
	SetOnUpdate(scout, function(self, elapsed)
		local fx = self.fx
		if not fx then return end
		self.time = self.time + elapsed
		local fix = FIXES[fx.id] or {}
		local t = self.time * speed * (fix.speed or 1)
		for i, tex in ipairs(self.layers) do
			local layer = self.moving[i]
			if layer then
				local u, v = t * layer[4], t * layer[5]
				tex:SetTexCoord(u, u + Repeats(layer[2], fix), v, v + Repeats(layer[3], fix))
			end
		end
		-- (Fades in over the effect's own fade-in time.)
		local fadeIn = math.max((fx.fade[1] or 0) / 1000, 0.05)
		self:SetAlpha(math.min(self.time / fadeIn, 1))
	end)
	scout:EnableKeyboard(true)
	scout:SetPropagateKeyboardInput(true)
	scout:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() or (shooter and shooter:IsShown()) then return end
		local step = (key == "SPACE" and 1) or (key == "BACKSPACE" and -1) or nil
		self:SetPropagateKeyboardInput(not step)
		if step then ns.ScoutScreenEffects(step > 0 and "" or "back") end
	end)
	scout:Hide()
end

local function SetMasked(on)
	if not scout.mask then return end
	for _, tex in ipairs({ scout.tint, scout.darken, scout.layers[1], scout.layers[2], scout.overlay }) do
		if on and not tex.masked then tex:AddMaskTexture(scout.mask) end
		if not on and tex.masked then tex:RemoveMaskTexture(scout.mask) end
		tex.masked = on or nil
	end
end

-- An effect's colours as the UI can draw them (the game multiplies the scene
-- by one and adds the other; a UI texture can only add light or lay paint).
-- Returns the glow colour r, g, b (the more colourful of multiply and add),
-- the glow's strength (pale colours drawn as light wash out to white: dimmer),
-- the darkening (a multiply that takes most light away: a black wash) and
-- whether both are near white (the effect is blur or depth of field only).
-- From the first full shots review, 2026-11-04: as light, pale multiplies
-- turned the screen white.
function ns.ScreenEffectLook(fx)
	local function Scaled(c)
		local s = c[4] or 1
		return math.min(c[1] * s, 1), math.min(c[2] * s, 1), math.min(c[3] * s, 1)
	end
	local function Chroma(r, g, b) return math.max(r, g, b) - math.min(r, g, b) end
	local function Light(r, g, b) return 0.3 * r + 0.59 * g + 0.11 * b end
	local mr, mg, mb = Scaled(fx.multiply)
	local ar, ag, ab = Scaled(fx.add)
	local mc, ac = Chroma(mr, mg, mb), Chroma(ar, ag, ab)
	-- (Near white both: the colour is the overlay's own, if it has one; with
	-- none, or named for blur or depth of field, nothing the UI can draw.)
	local white = mc < 0.12 and ac < 0.12 and Light(mr, mg, mb) > 0.85 and Light(ar, ag, ab) > 0.85
	local name = fx.name:lower()
	local blurOnly = white and (fx.overlay == 0 or name:find("blur", 1, true) or name:find("dof", 1, true)) and true
	local r, g, b = ar, ag, ab
	if mc > ac then r, g, b = mr, mg, mb end
	local glow = math.min(r, g, b) > 0.6 and 0.35 or 1
	-- (At most a quarter: at 0.45 the whole screen went dim, second review.)
	local darkness = math.max(mr, mg, mb) < 0.5 and (1 - Light(mr, mg, mb)) * 0.25 or 0
	return r, g, b, glow, darkness, blurOnly, white
end

local function Show(index)
	local list = ns.SCREEN_EFFECTS
	at = (index - 1) % #list + 1
	local fx = list[at]
	local fix = FIXES[fx.id] or {}
	scout.fx, scout.time = fx, 0
	local mul = fx.multiply
	local strength = mul[4] or 1
	local r, g, b, glow, darkness, blurOnly, white = ns.ScreenEffectLook(fx)
	if blurOnly and not fix.skip then fix = setmetatable({ skip = "blur or depth of field only: no UI can do that" },
		{ __index = fix }) end
	-- (The tint: the glow colour, light, over the masked part; the darkening:
	-- what the multiply takes away.)
	scout.tint:SetVertexColor(r, g, b, fix.tint or 0.15 * glow)
	scout.darken:SetAlpha(darkness)
	local missing = {}
	-- (The shape: layer 1, or 2 with swap; the others move inside it.)
	local shape, moving = fx.layers[1], { fx.layers[2], fx.layers[3] }
	if fix.swap then shape, moving = fx.layers[2], { fx.layers[1], fx.layers[3] } end
	scout.moving = moving
	local masked = scout.mask and shape and not fix.noMask and Probe(shape[1])
	if shape and not masked and not fix.noMask then missing[#missing + 1] = shape[1] end
	if masked then
		scout.mask:SetTexture(shape[1], "CLAMP", "CLAMP")
		local height = UIParent:GetHeight()
		scout.mask:ClearAllPoints()
		scout.mask:SetPoint("TOPLEFT", 0, (fx.mask[1] or 0) * height)
		scout.mask:SetPoint("BOTTOMRIGHT", 0, (fx.mask[1] or 0) * height)
	end
	SetMasked(masked)
	for i, tex in ipairs(scout.layers) do
		local layer = moving[i]
		if layer and Probe(layer[1]) then
			tex:SetTexture(layer[1], "REPEAT", "REPEAT")
			tex:SetVertexColor(r, g, b, fix.alpha or 0.6 * glow)
			tex:Show()
		else
			if layer then missing[#missing + 1] = layer[1] end
			tex:Hide()
		end
	end
	if fx.overlay ~= 0 and Probe(fx.overlay) then
		scout.overlay:SetTexture(fx.overlay)
		-- (White effects: the overlay in its own colours; at full strength the
		-- white ones still glared, second review.)
		scout.overlay:SetVertexColor(r, g, b, white and 0.6 or glow)
		scout.overlay:Show()
	else
		if fx.overlay ~= 0 then missing[#missing + 1] = fx.overlay end
		scout.overlay:Hide()
	end
	local files = {}
	for i, layer in ipairs(fx.layers) do
		files[#files + 1] = ("%d: %d (x%s y%s, scroll %s %s)"):format(i, layer[1], layer[2], layer[3], layer[4], layer[5])
	end
	-- (Skipped: nothing drawn, the header says why.)
	if fix.skip then
		scout.tint:SetAlpha(0)
		scout.darken:SetAlpha(0)
		scout.overlay:Hide()
		for _, tex in ipairs(scout.layers) do tex:Hide() end
	end
	local fixed = {}
	for key, value in pairs(FIXES[fx.id] or {}) do fixed[#fixed + 1] = key .. "=" .. tostring(value) end
	if fix.skip and not (FIXES[fx.id] or {}).skip then fixed[#fixed + 1] = "skip=" .. fix.skip end
	table.sort(fixed)
	scout.lines[1]:SetText(("%d of %d   |   effect %d   |   %s"):format(at, #list, fx.id, fx.name))
	scout.lines[2]:SetText(("overlay %s   |   layers %s"):format(fx.overlay ~= 0 and fx.overlay or "none",
		#files > 0 and table.concat(files, "   ") or "none"))
	scout.lines[3]:SetText(("multiply %s %s %s x%s   |   add %s %s %s x%s   |   mask offset %s, size %s   |   saturation %s, blur %s")
		:format(mul[1], mul[2], mul[3], strength, fx.add[1], fx.add[2], fx.add[3], fx.add[4], fx.mask[1], fx.mask[2],
			fx.saturation, fx.blur))
	scout.lines[4]:SetText((#missing > 0 and ("|cffff6060not on this client: %s|r   |   "):format(table.concat(missing, ", "))
		or "") .. (#fixed > 0 and ("|cff60ff60fixed: %s|r   |   "):format(table.concat(fixed, " ")) or "")
		.. ("speed %s, tile %s   |   Space: next, Backspace: back"):format(speed, tile))
	scout:Show()
end

-- A screenshot of each from a list number on, SHOT_WAIT seconds apart (the
-- game's "Screen captured" hidden so it isn't in the next one).
local function Shoot(from)
	if not shooter then
		shooter = CreateFrame("Frame")
		shooter:Hide()
		-- (The screenshot is taken at the end of the frame it's asked in, so
		-- the next effect is shown a frame later: asked and moved on in one
		-- go, every shot caught the next effect at the start of its fade-in,
		-- all but invisible, 2026-11-04.)
		SetOnUpdate(shooter, function(self, elapsed)
			self.left = self.left - elapsed
			if self.left > 0 then return end
			if not self.snapped then
				self.snapped = true
				Screenshot()
				return
			end
			self.snapped = nil
			if at >= #ns.SCREEN_EFFECTS then
				self:Hide()
				if ActionStatus then ActionStatus:SetAlpha(1) end
				ns.Print("screen effects: shots done (Screenshots folder)")
				return
			end
			Show(at + 1)
			self.left = SHOT_WAIT
		end)
	end
	if ActionStatus then ActionStatus:SetAlpha(0) end
	Show(from)
	shooter.left, shooter.snapped = SHOT_WAIT, nil
	shooter:Show()
	local total = (#ns.SCREEN_EFFECTS - at + 1) * SHOT_WAIT
	ns.Print(("screen effects: a screenshot of each from %d, %d:%02d in all (off: /cine debug screenfx off)")
		:format(at, math.floor(total / 60), total % 60))
end

-- /cine debug screenfx [number | id N | find words | speed N | tile N | shots [from] | back | off]
function ns.ScoutScreenEffects(arg)
	local list = ns.SCREEN_EFFECTS
	if not list then ns.Print("/cine debug screenfx is in the dev copy only.") return end
	arg = arg or ""
	if arg == "off" then
		if scout then scout:Hide() end
		if shooter and shooter:IsShown() then
			shooter:Hide()
			if ActionStatus then ActionStatus:SetAlpha(1) end
		end
		ns.Print("screen effects: off")
		return
	end
	if not scout then Create() end
	local word, rest = arg:match("^(%S+)%s*(.-)$")
	if word == "shots" then
		Shoot(math.max(math.floor(tonumber(rest) or 1), 1))
		return
	elseif word == "speed" and tonumber(rest) then
		speed = tonumber(rest)
	elseif word == "tile" and tonumber(rest) then
		tile = tonumber(rest)
	elseif word == "id" and tonumber(rest) then
		for i, fx in ipairs(list) do
			if fx.id == tonumber(rest) then at = i end
		end
	elseif word == "find" and rest ~= "" then
		local found
		for step = 1, #list do
			local i = (at + step - 1) % #list + 1
			if list[i].name:lower():find(rest:lower(), 1, true) then found = i break end
		end
		if not found then ns.Print("screen effects: no name has " .. rest) return end
		at = found
	elseif word == "back" then
		at = at - 1
	elseif tonumber(arg) then
		at = tonumber(arg)
	elseif arg == "" then
		at = at + 1
	else
		ns.Print("/cine debug screenfx [number | id N | find words | speed N | tile N | shots [from] | back | off]")
		return
	end
	if at < 1 then at = #list end
	Show(at)
end
