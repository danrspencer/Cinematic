-- The real nameplates' health bars, as the Style hub's General page says: its
-- bar texture and border, so a style theme reaches them (and they match the
-- General page's preview). Their colors stay the game's: our fills are grey, so
-- they take its colors, and nothing here reads a value the game keeps secret.
-- With General on the game's look nothing's touched. Each bar is hooked once,
-- as the cast bars are (PlateCastStyle.lua): the game sets its fill again as
-- plates are reused. Plates the game keeps from addons are skipped.

local _, ns = ...

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

-- General's texture (nil: the game's) and its border's kind, size and color.
local function Look()
	local db = ns.db
	if not (db and db.styleGeneral) then return nil, "game" end
	local texture = db.styleTexture
	if texture == "game" then texture = nil end
	return texture, ns.StyleBorder(db, "styleBorder")
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
	local texture, kind, size, r, g, b = Look()
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
	if kind == "line" then
		state.edges = state.edges or ns.MakeStyleEdges(bar)
		ns.DressStyleEdges(state.edges, size, r, g, b, 1, true)
		state.edges:Show()
	elseif state.edges then
		state.edges:Hide()
	end
end

local function GameSet(bar)
	if busy then return end
	local state = states[bar]
	if not (state and state.on) then return end
	-- (The game's own again, on a plate come back: ours over it, its noted.)
	state.on = false
	pcall(Dress, bar)
end

local function StylePlate(plate)
	if not plate then return end
	local personal = C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
	if plate == personal then return end
	local bar = BarOf(plate)
	if not bar then return end
	local texture, kind = Look()
	-- (Left quite alone until there's something to do.)
	if not (texture or kind ~= "game" or states[bar]) then return end
	if not hooked[bar] then
		hooked[bar] = true
		hooksecurefunc(bar, "SetStatusBarTexture", GameSet)
	end
	Dress(bar)
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

function ns.RefreshPlateHealthStyle()
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
	local line = ("plate health style: texture %s, border %s, theme %s; %d plates, %d styled, %d kept from addons, in instance %s"):format(
		tostring(texture or "game"), tostring(kind), ns.ActiveStyleTheme().key, total, styled, kept,
		tostring((IsInInstance())))
	ns.Log("plates", line)
	if not quiet then ns.Print(line) end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watcher:SetScript("OnEvent", function(_, _, unit)
	if not (ns.db and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
	TryPlate(C_NamePlate.GetNamePlateForUnit(unit))
end)
