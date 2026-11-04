-- The game's own full-screen effects (ScreenEffectsData.lua, from its data
-- tables), drawn by the UI: Vitals Vision's game effects (a theme's effect,
-- LowHealthThemes.lua) and the dev copy's /cine debug screenfx
-- (ScreenEffectScout.lua). A rebuild by eye, not the game's shader: layer 1
-- is the shape (a mask, stretched once over the area, never tiled: tiled it
-- drew a grid), layers 2 and 3 scroll inside it in the effect's colour, the
-- overlay over them. Retail's files only: Classic has none of them.
--
-- Units, measured on a recording of the real effect 248 (Dimensius's Cosmic
-- Void, a quest's buff, 2026-11-04): a small scale (under 0.05) counts pixels
-- of a 768-tall screen (repeats down the screen = 768 x scale) and the scroll
-- rate is texture lengths a second (its layers rose 0.05 next to the real
-- 0.07 screens a second). Bigger scales are a guess (screens), slowed.

local _, ns = ...

local REF_HEIGHT = 768 -- (the game's units for small scales: pixels of a 768-tall screen)
local BIG_SCALE_SPEED = 0.1 -- (the guess for layers with big scales, unmeasured)
-- Flat-colour textures some effects use as a layer: a constant in the game's
-- shader, not a picture. Drawn as light they were a flat wash over the
-- screen (effect 248's white8x8 next to the real one, 2026-11-04): left out.
local SOLID = { [1273161] = "white8x8", [188526] = "grey", [3308414] = "gray8x8" }

local byId
function ns.ScreenEffectById(id)
	if not ns.SCREEN_EFFECTS then return nil end
	if not byId then
		byId = {}
		for _, fx in ipairs(ns.SCREEN_EFFECTS) do byId[fx.id] = fx end
	end
	return byId[id]
end

-- Whether this client has a file: Classic's SetTexture can't tell (a missing
-- file still "loads", bright green), and has none of these.
local probe
local function Has(file)
	if not ns.isRetail then return false end
	if not probe then
		local holder = CreateFrame("Frame", nil, UIParent)
		holder:Hide()
		probe = holder:CreateTexture()
	end
	return probe:SetTexture(file) ~= false
end
ns.ScreenEffectFileLoads = Has

-- An effect's colours as the UI can draw them (the game multiplies the scene
-- by one and adds the other; a UI texture can only add light or lay paint).
-- Returns the glow colour r, g, b (the more colourful of multiply and add),
-- the glow's strength (pale colours drawn as light wash out to white: dimmer),
-- the darkening (a multiply that takes most light away: a black wash) and
-- whether both are near white (blurOnly: blur or depth of field only, when
-- it has no overlay or says so; white: the overlay's own colours are it).
-- From the shots reviews, 2026-11-04: as light, pale multiplies turned the
-- screen white; darkening by up to 0.45 dimmed it all.
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
	local white = mc < 0.12 and ac < 0.12 and Light(mr, mg, mb) > 0.85 and Light(ar, ag, ab) > 0.85
	local name = fx.name:lower()
	local blurOnly = white and (fx.overlay == 0 or name:find("blur", 1, true) or name:find("dof", 1, true)) and true
	local r, g, b = ar, ag, ab
	if mc > ac then r, g, b = mr, mg, mb end
	local glow = math.min(r, g, b) > 0.6 and 0.35 or 1
	local darkness = math.max(mr, mg, mb) < 0.5 and (1 - Light(mr, mg, mb)) * 0.25 or 0
	return r, g, b, glow, darkness, blurOnly, white
end

-- How many times a layer repeats over an area w x h (across: its width) and
-- its speed: small scales are the game's pixel units (measured), the rest
-- the area (a guess), slowed.
local function Small(scale) return scale ~= 0 and math.abs(scale) < 0.05 end
local function Repeats(scale, tile, across, w, h)
	scale = math.abs(scale or 1)
	if scale == 0 then scale = 1 end
	if Small(scale) then
		scale = scale * REF_HEIGHT
		if across then scale = scale * w / math.max(1, h) end
	end
	return scale * tile
end
local function LayerSpeed(layer)
	return (Small(layer[2]) or Small(layer[3])) and 1 or BIG_SCALE_SPEED
end

-- A drawer in parent: its own frame (centered; Place sizes it), so the
-- caller fades it with SetAlpha and grows it past the screen's edges.
-- :Set(fx, opts) sets it up for an effect (opts: tile, speed, alpha (the
-- moving layers), tint (the colour wash), noMask, swap (layer 2 as the shape),
-- skip), and says whether there's anything to draw, why not, and the files
-- this client hasn't; :Step(elapsed) moves its layers.
function ns.NewScreenEffect(parent)
	local e = {}
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetPoint("CENTER")
	holder:SetSize(1, 1)
	holder:EnableMouse(false)
	e.frame = holder
	local tint = holder:CreateTexture(nil, "BACKGROUND")
	tint:SetAllPoints()
	tint:SetColorTexture(1, 1, 1, 1)
	-- (The multiply's darkening: black over the shape.)
	local darken = holder:CreateTexture(nil, "BACKGROUND", nil, 1)
	darken:SetAllPoints()
	darken:SetColorTexture(0, 0, 0, 1)
	local layers = {}
	for i = 1, 2 do
		local tex = holder:CreateTexture(nil, "BORDER", nil, i)
		tex:SetAllPoints()
		tex:SetBlendMode("ADD")
		layers[i] = tex
	end
	local overlay = holder:CreateTexture(nil, "ARTWORK")
	overlay:SetAllPoints()
	overlay:SetBlendMode("ADD")
	local mask = holder.CreateMaskTexture and holder:CreateMaskTexture()
	if mask then mask:SetAllPoints(holder) end
	local all = { tint, darken, layers[1], layers[2], overlay }
	local masked = false
	local moving, time, opts = {}, 0, {}

	function e:Place(w, h)
		holder:SetSize(math.max(1, w), math.max(1, h))
	end
	function e:Show() holder:Show() end
	function e:Hide() holder:Hide() end
	function e:SetAlpha(a) holder:SetAlpha(a) end

	function e:Set(fx, options)
		opts = options or {}
		time = 0
		local missing = {}
		local r, g, b, glow, darkness, blurOnly, white = ns.ScreenEffectLook(fx)
		local skip = opts.skip or blurOnly and "blur or depth of field only: no UI can do that" or nil
		-- (The shape: layer 1, or 2 with swap; the others move inside it.)
		local shape = fx.layers[1]
		moving = { fx.layers[2], fx.layers[3] }
		if opts.swap then shape, moving = fx.layers[2], { fx.layers[1], fx.layers[3] } end
		-- (The data's mask offset isn't used: effect 248's -0.25 moved either
		-- way was wrong next to the real one. Lowered, its heavy bottom went off
		-- screen; raised, the clamped edge filled the bottom 40% with a flat
		-- block, 2026-11-04. Fitted to the area it's closest.)
		local shaped = mask and shape and not opts.noMask and Has(shape[1])
		if shape and not shaped and not opts.noMask then missing[#missing + 1] = shape[1] end
		if shaped then mask:SetTexture(shape[1], "CLAMP", "CLAMP") end
		if shaped ~= masked then
			for _, tex in ipairs(all) do
				if shaped then tex:AddMaskTexture(mask) else tex:RemoveMaskTexture(mask) end
			end
			masked = shaped and true or false
		end
		tint:SetVertexColor(r, g, b, opts.tint or 0.15 * glow)
		darken:SetAlpha(darkness)
		local drawn = false
		for i, tex in ipairs(layers) do
			local layer = moving[i]
			if layer and not SOLID[layer[1]] and Has(layer[1]) then
				tex:SetTexture(layer[1], "REPEAT", "REPEAT")
				tex:SetVertexColor(r, g, b, opts.alpha or 0.6 * glow)
				tex:Show()
				drawn = true
			else
				if layer and not SOLID[layer[1]] then missing[#missing + 1] = layer[1] end
				tex:Hide()
			end
		end
		if fx.overlay ~= 0 and Has(fx.overlay) then
			overlay:SetTexture(fx.overlay)
			-- (White effects: the overlay in its own colours; at full strength the
			-- white ones still glared.)
			overlay:SetVertexColor(r, g, b, white and 0.6 or glow)
			overlay:Show()
			drawn = true
		else
			if fx.overlay ~= 0 then missing[#missing + 1] = fx.overlay end
			overlay:Hide()
		end
		if skip or not drawn then
			tint:SetAlpha(0)
			darken:SetAlpha(0)
			overlay:Hide()
			for _, tex in ipairs(layers) do tex:Hide() end
		end
		e:Step(0)
		return not skip and drawn, skip, missing
	end

	function e:Step(elapsed)
		time = time + elapsed
		local t = time * (opts.speed or 1)
		local w, h = holder:GetSize()
		local tile = opts.tile or 1
		for i, tex in ipairs(layers) do
			local layer = moving[i]
			if layer and tex:IsShown() then
				local lt = t * LayerSpeed(layer)
				local u, v = lt * layer[4], lt * layer[5]
				tex:SetTexCoord(u, u + Repeats(layer[2], tile, true, w, h), v, v + Repeats(layer[3], tile, false, w, h))
			end
		end
	end

	return e
end
