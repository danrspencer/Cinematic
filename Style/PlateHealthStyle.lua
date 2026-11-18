-- The real nameplates' health bars, as the Style hub's General page says: its
-- bar texture and border, so a style theme reaches them (and they match the
-- General page's preview). Their colors stay the game's: our fills are grey, so
-- they take its colors, and nothing here reads a value the game keeps secret.
-- A full-color fill (Neon Coast's Sunset) is the one exception: its fill's kept
-- white and the game's color goes on a thin strip under it (ns.DressPlateFullColor).
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

-- A full-color fill (Sunset's, ns.StyleTextureFull) in its own colors: the fill
-- kept white whatever color the bar's given, and that color on a thin strip along
-- the bar's bottom, so hostile, neutral and friendly still read at a glance. on:
-- false takes it off. r, g, b: the bar's color (nil: the strip's kept); it may be
-- secret, and is only passed on. Shared with the previews (General, Plate themes).
-- The strip shows only once a color's reached it: with none it would be white, a
-- bar that means nothing (seen on a Young Wolf, Forever, 2026-11-18). Gives
-- whether a color went on.
local strips = setmetatable({}, { __mode = "k" })
local stripColored = setmetatable({}, { __mode = "k" })
local STRIP = 2

-- The style theme's own color for a reaction ("hostile", "neutral",
-- "friendly", "friends": friendly players), from its reaction list: nil
-- without one. Neon Coast's sunset coral, gold, mint and cyan.
function ns.ThemeReactionColor(kind)
	local theme = ns.ActiveStyleTheme and ns.ActiveStyleTheme()
	local color = theme and theme.reaction and theme.reaction[kind]
	if color then return color[1], color[2], color[3] end
end

-- A unit's reaction in the theme's colors (nil: no theme list, or the game
-- keeps it secret).
local function ThemeReaction(unit)
	if not unit then return nil end
	local theme = ns.ActiveStyleTheme and ns.ActiveStyleTheme()
	if not (theme and theme.reaction) then return nil end
	local okPlayer, player = pcall(UnitIsPlayer, unit)
	if okPlayer and Known(player) and player then
		local okAttack, attack = pcall(UnitCanAttack, "player", unit)
		if not (okAttack and Known(attack)) then return nil end
		return ns.ThemeReactionColor(attack and "hostile" or "friends")
	end
	local ok, reaction = pcall(UnitReaction, unit, "player")
	if not (ok and Known(reaction) and type(reaction) == "number") then return nil end
	return ns.ThemeReactionColor(reaction <= 3 and "hostile" or reaction == 4 and "neutral" or "friendly")
end
function ns.DressPlateFullColor(bar, on, r, g, b)
	local strip = strips[bar]
	if not on then
		if strip then strip:Hide() end
		return
	end
	if not strip then
		strip = bar:CreateTexture(nil, "OVERLAY", nil, 6)
		strip:SetTexture("Interface\\Buttons\\WHITE8X8")
		strip:SetPoint("BOTTOMLEFT")
		strip:SetPoint("BOTTOMRIGHT")
		strip:SetHeight(STRIP)
		strips[bar] = strip
	end
	local fill = bar:GetStatusBarTexture()
	if fill then pcall(fill.SetVertexColor, fill, 1, 1, 1, 1) end
	local colored = false
	if r ~= nil then colored = pcall(strip.SetVertexColor, strip, r, g, b, 1) end
	if colored then stripColored[strip] = true end
	strip:SetShown(stripColored[strip] == true)
	return colored
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
		state.on = ns.SetBarTexture(bar, texture, true) or state.on
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
	state.full = texture and state.on and ns.StyleTextureFull(texture) or false
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
	if state and state.full and not state.gradient then
		local tr, tg, tb = ThemeReaction(state.unit)
		if tr then
			ns.DressPlateFullColor(bar, true, tr, tg, tb)
			state.stripFrom = "theme's set"
		else
			local ok = ns.DressPlateFullColor(bar, true, r, g, b)
			state.stripFrom = ("game%s %s"):format(Known(r) and "" or " (secret)", ok and "set" or "refused")
		end
	end
end

-- A full-color fill on or off (state.full, from Dress), with the strip in the
-- bar's color: the game's last, else read (WoW Forever reads white: none), else
-- the unit's own reaction color. unit: the plate's, if known.
local function Full(bar, state, unit)
	if not (state.full and not state.gradient) then
		if strips[bar] and strips[bar]:IsShown() then
			ns.DressPlateFullColor(bar, false)
			local color, fill = state.color, bar:GetStatusBarTexture()
			if color and fill and not state.gradient then pcall(fill.SetVertexColor, fill, color[1], color[2], color[3], 1) end
		end
		return
	end
	if not colorHooked[bar] then
		colorHooked[bar] = true
		hooksecurefunc(bar, "SetStatusBarColor", ColorSet)
	end
	-- (Worked out again for each unit: a plate's reused, and its last unit's
	-- color mustn't stay on the strip.)
	if strips[bar] then stripColored[strips[bar]] = nil end
	-- (The bar's color read, else the unit's own, else the game's last on this
	-- bar: last, as that can be the plate's unit before this one.)
	local r, g, b, from = ThemeReaction(unit)
	if r then from = "theme's" end
	if r == nil then
		local ok, rr, gg, bb = pcall(bar.GetStatusBarColor, bar)
		if ok and Known(rr) and Known(gg) and Known(bb) and rr and not (rr > 0.99 and gg > 0.99 and bb > 0.99) then
			r, g, b, from = rr, gg, bb, "read"
		else
			from = ok and (Known(rr) and "read white" or "read secret") or "read error"
		end
	end
	if r == nil and unit and UnitSelectionColor then
		local ok, rr, gg, bb = pcall(UnitSelectionColor, unit)
		if ok then r, g, b = rr, gg, bb end
		from = from .. (ok and (Known(rr) and ", unit's" or ", unit's (secret)") or ", unit's error")
	elseif r == nil then
		from = from .. (unit and ", no UnitSelectionColor" or ", no unit")
	end
	if r == nil and state.color then -- (a secret color's still passed on: the game may take it)
		r, g, b = state.color[1], state.color[2], state.color[3]
		from = from .. ", kept"
	end
	local done = ns.DressPlateFullColor(bar, true, r, g, b)
	state.stripFrom = from .. (done and " set" or r == nil and " none" or " refused")
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
	pcall(Full, bar, state, state.unit)
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
	local unitFrame = plate.UnitFrame
	local unit = unitFrame and unitFrame.unit
	states[bar].unit = Known(unit) and unit or nil
	Full(bar, states[bar], states[bar].unit)
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
	-- (A full-color fill's strip: where its color came from, and whether it shows.)
	local strip = strips[bar]
	return ("bar: hooked %s, styled %s, edges %s, fill %s, atlas %s, full %s, strip %s (%s)"):format(
		tostring(hooked[bar] == true), tostring(state and state.on or false), tostring(state and state.edges ~= nil or false),
		Known(file) and tostring(file) or "secret", Known(atlas) and tostring(atlas) or "secret",
		tostring(state and state.full or false), strip and (strip:IsShown() and "shown" or "hidden") or "none",
		tostring(state and state.stripFrom or "-"))
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
