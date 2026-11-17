-- The real nameplates' health bars, as the Style hub's General page says: its
-- bar texture and border, so a style theme reaches them (and they match the
-- General page's preview). Their colors stay the game's: our fills are grey, so
-- they take its colors, and nothing here reads a value the game keeps secret.
-- With General on the game's look nothing's touched. Each bar is hooked once,
-- as the cast bars are (PlateCastStyle.lua): the game sets its fill again as
-- plates are reused. Plates the game keeps from addons are skipped.

local _, ns = ...

ns.DEFAULTS.stylePlate = "game" -- the game's nameplate Style: "game" (left alone) or its number, 0 up

-- The game's own Style setting, as the General page says: held like any other
-- game setting of ours (yours saved and put back, a change of yours in its
-- Options wins), so it's on the Held Game Settings page too. Only while Style's on.
local STYLE_NAMES = { "Modern", "Thin Bars", "Blocky Bars", "Clean Health", "Blocky Cast", "Legacy Red" }
local STYLE_SET = ns.CVarSet("Nameplate style", "Style hub's General page: the nameplate style picked there",
	{ secure = true, playerWins = true, values = { nameplateStyle = "0" } })

-- The styles' names, on a client whose menu has them (nil: not this one).
function ns.GamePlateStyles()
	local ok, value = pcall(GetCVar, "nameplateStyle")
	if ok and STYLE_NAMES[(tonumber(value) or -1) + 1] then return STYLE_NAMES end
end

local function HoldPlateStyle()
	local db = ns.db
	if not (db and ns.GamePlateStyles()) then return end
	local value = db.styleGeneral and db.stylePlate ~= "game" and tostring(db.stylePlate) or nil
	if STYLE_SET.active and value ~= STYLE_SET.values.nameplateStyle then ns.ApplyCVarSet(STYLE_SET, false) end
	if value then STYLE_SET.values.nameplateStyle = value end
	if not (STYLE_SET.active and not value) then ns.ApplyCVarSet(STYLE_SET, value ~= nil) end
end

local states = setmetatable({}, { __mode = "k" }) -- [bar] = { game's fill, our edges, on }
local hooked = setmetatable({}, { __mode = "k" })
local busy = false -- (while we set the fill: not the game setting its own)

local function Known(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local function Usable(region)
	if type(region) ~= "table" or not region.SetAlpha then return false end
	if not region.IsForbidden then return true end
	local forbidden = region:IsForbidden()
	return Known(forbidden) and not forbidden
end

local function BarOf(plate)
	local unitFrame = plate and plate.UnitFrame
	if not (Usable(plate) and Usable(unitFrame)) then return nil end
	local container = unitFrame.HealthBarsContainer
	local bar = (Usable(container) and container.healthBar) or unitFrame.healthBar
	return Usable(bar) and bar.SetStatusBarTexture and bar or nil
end

-- A bar's Nameplate Style row Look, over General's (PlateRowLook.lua):
-- [bar] = { texture ("game": the game's fill), border = { kind, size, r, g, b } }.
local overrides = setmetatable({}, { __mode = "k" })

-- The plate theme's texture (nil: the game's) and its border's kind, size
-- and color: General's while it follows General (PlateThemes.lua); a bar's
-- row Look over them (bar: the one asked about).
local function Look(bar)
	local texture, kind, size, r, g, b = ns.PlateThemeBar()
	local own = bar and overrides[bar]
	if own then
		if own.texture ~= nil then texture = own.texture ~= "game" and own.texture or nil end
		if own.border then kind, size, r, g, b = unpack(own.border) end
	end
	return texture, kind, size, r, g, b
end

-- The game's fill as it is now, to put back.
local function RememberFill(bar, state)
	local fill = bar:GetStatusBarTexture()
	if not fill then return end
	local atlas = fill.GetAtlas and fill:GetAtlas()
	local file = fill.GetTexture and fill:GetTexture()
	state.atlas = Known(atlas) and atlas or nil
	state.file = Known(file) and file or nil
end

local function Dress(bar)
	local state = states[bar]
	if not state then
		state = {}
		states[bar] = state
	end
	local texture, kind, size, r, g, b = Look(bar)
	busy = true
	if texture then
		if not state.on then RememberFill(bar, state) end
		state.on = ns.SetBarTexture(bar, texture) or state.on
	elseif state.on then
		local game = state.atlas or state.file
		if game then
			bar:SetStatusBarTexture(game)
			local fill = bar:GetStatusBarTexture()
			if fill and fill.SetDesaturated then fill:SetDesaturated(false) end
		end
		state.on = false
	end
	busy = false
	ns.DressThemeVeil(bar, texture and "plate" or nil)
	-- (A plate theme's ground behind the fill and its bar shape, PlateThemes.lua.
	-- The shape masks the fill and the ground: the game's own rounding off
	-- the fill first, ns.DressBarShape. Square again once it's left.)
	local shape, ground = ns.PlateThemeExtras()
	if ground then
		state.ground = state.ground or bar:CreateTexture(nil, "BACKGROUND", nil, -1)
		state.ground:SetAllPoints()
		state.ground:SetColorTexture(ground[1], ground[2], ground[3], ground[4] or 0.7)
		state.ground:Show()
	elseif state.ground then
		state.ground:Hide()
	end
	local back = state.ground or bar.bgTexture
	if back and back.GetParent and (shape or state.shaped) then
		state.shaped = ns.DressBarShape(bar, back, not shape, nil, nil, shape) or nil
	end
	if kind == "line" then
		state.edges = state.edges or ns.MakeStyleEdges(bar)
		ns.DressStyleEdges(state.edges, size, r, g, b, 1, true)
		state.edges:Show()
	elseif state.edges then
		state.edges:Hide()
	end
end

-- A row Look's gradient on a bar's fill: from the color the game (or our
-- row colors) gave it, left to right, to the gradient's. r, g, b: that
-- color, as just set (else read). A secret color is left flat.
local function Shade(bar, r, g, b)
	local state = states[bar]
	local fade = state and state.gradient
	if not fade then return end
	-- (Not given: the color the game last set, else read. WoW Forever reads
	-- a plate bar's color back as white.)
	if r == nil and state.color then r, g, b = unpack(state.color) end
	if r == nil then r, g, b = bar:GetStatusBarColor() end
	if not (Known(r) and Known(g) and Known(b) and r) then return end
	local fill = bar:GetStatusBarTexture()
	if not (fill and fill.SetGradient and CreateColor) then return end
	pcall(fill.SetGradient, fill, "HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(fade[1], fade[2], fade[3], 1))
end
local colorHooked = setmetatable({}, { __mode = "k" })
local function ColorSet(bar, r, g, b)
	if busy then return end
	-- (Kept: the bar's color as the game set it, for going flat again.)
	local state = states[bar]
	if state and Known(r) and Known(g) and Known(b) and type(r) == "number" then state.color = { r, g, b } end
	Shade(bar, r, g, b)
end

local function Gradient(bar, state)
	local own = overrides[bar]
	local fade = own and own.gradient or nil
	if fade then
		if not colorHooked[bar] then
			colorHooked[bar] = true
			hooksecurefunc(bar, "SetStatusBarColor", ColorSet)
		end
		state.gradient = fade
		Shade(bar)
	elseif state.gradient then
		-- (Flat again: its color set on the fill itself, as the bar's color set
		-- again the same doesn't clear the gradient. The color the game last
		-- set, not the one read back: WoW Forever reads a plate bar's as white,
		-- and that went on the fill, a white bar flashing until the game
		-- painted it again, 2026-11-14. None known: left for the game's next.)
		state.gradient = nil
		local color = state.color
		local fill = bar:GetStatusBarTexture()
		if color and fill then pcall(fill.SetVertexColor, fill, color[1], color[2], color[3], 1) end
	end
end

local function GameSet(bar)
	if busy then return end
	local state = states[bar]
	if not (state and state.on) then return end
	-- (The game's own again, on a plate come back: ours over it, its noted.)
	state.on = false
	pcall(Dress, bar)
	pcall(Shade, bar) -- (a new fill: its gradient again)
end

local function StylePlate(plate)
	if not plate then return end
	local personal = C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
	if plate == personal then return end
	local bar = BarOf(plate)
	if not bar then return end
	local texture, kind = Look(bar)
	-- (Left quite alone until there's something to do.)
	if not (texture or kind ~= "game" or states[bar] or (overrides[bar] and overrides[bar].gradient)) then return end
	if not hooked[bar] then
		hooked[bar] = true
		hooksecurefunc(bar, "SetStatusBarTexture", GameSet)
	end
	Dress(bar)
	Gradient(bar, states[bar])
end

-- (An error isn't swallowed: the log keeps the first of each, for /cine log.)
local logged = {}
local function TryPlate(plate)
	local ok, err = pcall(StylePlate, plate)
	if not ok and not logged[tostring(err)] then
		logged[tostring(err)] = true
		ns.Log("plates", "health style error: " .. tostring(err))
	end
end

-- A plate's row Look (nil: none), from PlateRowLook.lua: its bar dressed again.
function ns.SetPlateBarOverride(plate, look)
	local bar = BarOf(plate)
	if not bar then return end
	if not look and not overrides[bar] then return end
	overrides[bar] = look and { texture = look.texture, border = look.border, gradient = look.gradient } or nil
	TryPlate(plate)
end

function ns.RefreshPlateHealthStyle()
	HoldPlateStyle()
	if not (ns.db and C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do TryPlate(plate) end
end

-- Why a plate is as it is, for the log.
local function WhyPlate(plate)
	if not Usable(plate) then return "plate kept from addons" end
	local unitFrame = plate.UnitFrame
	if not Usable(unitFrame) then return "UnitFrame " .. (unitFrame and "kept from addons" or "missing") end
	local container = unitFrame.HealthBarsContainer
	local bar = BarOf(plate)
	if not bar then
		return ("no bar: container %s, its healthBar %s, unitFrame.healthBar %s"):format(tostring(container ~= nil),
			tostring(type(container) == "table" and container.healthBar ~= nil), tostring(unitFrame.healthBar ~= nil))
	end
	local state = states[bar]
	local fill = bar:GetStatusBarTexture()
	local file = fill and fill.GetTexture and fill:GetTexture()
	local atlas = fill and fill.GetAtlas and fill:GetAtlas()
	return ("bar: hooked %s, styled %s, edges %s, fill %s, atlas %s"):format(tostring(hooked[bar] == true),
		tostring(state and state.on or false), tostring(state and state.edges ~= nil or false),
		Known(file) and tostring(file) or "secret", Known(atlas) and tostring(atlas) or "secret")
end

-- /cine debug plates: what's styled, and what the game keeps from us; each
-- plate's reason in the log. quiet: the log alone (the screenshot run).
function ns.ReportPlateHealthStyle(quiet)
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	local texture, kind = Look()
	local total, styled, kept = 0, 0, 0
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		total = total + 1
		local okWhy, why = pcall(WhyPlate, plate)
		if total <= 12 then ns.Log("plates", ("health style %d: %s"):format(total, tostring(why) .. (okWhy and "" or " (error)"))) end
		local bar = BarOf(plate)
		if not bar then
			kept = kept + 1
		elseif states[bar] and states[bar].on then
			styled = styled + 1
		end
	end
	local line = ("plate health style: texture %s, border %s, theme %s; %d plates, %d styled, %d kept from addons, in instance %s, style %s (picked %s, held %s)"):format(
		tostring(texture or "game"), tostring(kind), ns.ActiveStyleTheme().key, total, styled, kept,
		tostring((IsInInstance())), tostring(GetCVar("nameplateStyle")), tostring(ns.db and ns.db.stylePlate),
		tostring(STYLE_SET.active or false))
	ns.Log("plates", line)
	if not quiet then ns.Print(line) end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
-- (A held setting can't change in a fight: tried again as one ends.)
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event, unit)
	if event ~= "NAME_PLATE_UNIT_ADDED" then
		HoldPlateStyle()
		return
	end
	if not (ns.db and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	-- (Showing nothing: dressed as it wakes. PlateSleep.lua.)
	if not ns.PlateAsleep(plate) then TryPlate(plate) end
end)
ns.plateSleep.OnWake(function(plate) if ns.db then TryPlate(plate) end end)
