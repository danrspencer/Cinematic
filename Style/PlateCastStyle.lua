-- The Style hub's Cast bars page: how the cast bars look, on nameplates,
-- yours (and your pet's), your target's and focus's, and the bosses' and
-- arena enemies'. The game's own bars are restyled where they are (each
-- change put back on as the game sets its own again, on each cast): their
-- fill and its colors by what's cast (a cast, a channel, one that can't be
-- interrupted, one that was), a dark ground behind, a border, the spell's
-- icon, shield and spark, and the spell's name in a font of your own, with
-- the seconds left at the end. A Default row, and a row for each kind of bar
-- whose "These bars" dropdown picks its look: the game's (plateCastOn_<BAR>
-- off; not the nameplates'), the Default row's, or its own copy of each
-- setting (plateCastOwn_<BAR>, <key>_<BAR>). The bars past the nameplates'
-- start with the game's look, and keep
-- the game's size (yours is sized in Edit Mode). Whether the nameplates'
-- show (in CineMode): the Nameplates page's Plate parts grid. A preview at
-- the top, drawn by the same code as the real ones.

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.plateCastStyle = true
DEFAULTS.plateCastWidth = 1        -- times the game's, about its middle
DEFAULTS.plateCastHeight = 1       -- times the game's, its top kept
DEFAULTS.plateCastPlayerWidth = 1  -- your cast bar's width, times the game's (the You tab, with its own look)
DEFAULTS.plateCastPlayerWidthUnit = "pct" -- ...or "px": plateCastPlayerWidthPx pixels on screen
DEFAULTS.plateCastPlayerWidthPx = 0
DEFAULTS.plateCastFill = "general" -- the fill: "game" (its own, and its colors) or a texture (general: General's)
DEFAULTS.plateCastR, DEFAULTS.plateCastG, DEFAULTS.plateCastB = 1, 0.7, 0                       -- a cast
DEFAULTS.plateCastChannelR, DEFAULTS.plateCastChannelG, DEFAULTS.plateCastChannelB = 0.25, 0.75, 0.35 -- a channel
DEFAULTS.plateCastLockedR, DEFAULTS.plateCastLockedG, DEFAULTS.plateCastLockedB = 0.6, 0.6, 0.65  -- can't be interrupted
DEFAULTS.plateCastStopR, DEFAULTS.plateCastStopG, DEFAULTS.plateCastStopB = 0.85, 0.15, 0.1     -- interrupted
DEFAULTS.plateCastBack = 0.6        -- the dark ground behind our fill, 0 to 1
DEFAULTS.plateCastBorder = "general" -- "game", "none", "thin", "thick", "custom" (general: General's)
DEFAULTS.plateCastSpark = true
DEFAULTS.plateCastIcon = true
DEFAULTS.plateCastIconSize = 1      -- the icon under the bar, times the game's
DEFAULTS.plateCastShield = true     -- the game's shield on casts that can't be interrupted
DEFAULTS.plateCastImportant = true  -- the game's mark on important casts
DEFAULTS.plateCastTarget = true     -- the game's who it's cast at (its mark and name)
DEFAULTS.plateCastText = true       -- the spell's name
DEFAULTS.plateCastFont = "general" -- QUEST_ITEM_FONTS (QuestItemButton.lua; general: General's)
DEFAULTS.plateCastTextSize = 1      -- times the game's size
DEFAULTS.plateCastOutline = "general" -- "game", "none", "thin" or "thick" (general: General's)
DEFAULTS.plateCastTextColor = "game" -- its text's color: "game" or "custom" (ns.SetTextColorOf)
DEFAULTS.plateCastTextR, DEFAULTS.plateCastTextG, DEFAULTS.plateCastTextB = 1, 1, 1
DEFAULTS.plateCastShadow = "general" -- "game", "on" or "none" (ns.SetTextShadow; general: General's)
DEFAULTS.plateCastTimer = false     -- the seconds left at the bar's right end

-- The look's own settings (each kind of bar has its copy: BAR_KEYS).
local PRESET_KEYS = { "plateCastWidth", "plateCastHeight", "plateCastFill", "plateCastBack", "plateCastBorder", "plateCastSpark", "plateCastIcon", "plateCastIconSize",
	"plateCastShield", "plateCastImportant", "plateCastTarget", "plateCastText", "plateCastFont", "plateCastTextSize", "plateCastOutline", "plateCastShadow", "plateCastTextColor", "plateCastTextR", "plateCastTextG", "plateCastTextB",
	"plateCastTimer" }

local FILLS = {
	flat = "Interface\\Buttons\\WHITE8X8",
	smooth = "Interface\\TargetingFrame\\UI-StatusBar",
	raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
-- (Any other of the Style pages' textures that's a file: ns.StyleTexturePath.
-- An atlas isn't: the game's fill shows for it.)
setmetatable(FILLS, { __index = function(_, value)
	if not ns.StyleTexturePath then return end
	local path, atlas = ns.StyleTexturePath(value)
	if path and not atlas then return path end
end })
local OUTLINE_LEVEL = { none = 0, thin = 1, thick = 2 }
-- The game's art on the bar our border and ground stand in for (not every
-- client has each), and the parts with a tickbox of their own.
local BORDER_ART = { "Border", "TextBorder" }

local function Known(value)
	return not (issecretvalue and issecretvalue(value))
end

local function Usable(region)
	return type(region) == "table" and region.SetAlpha and not (region.IsForbidden and region:IsForbidden())
end

-- [bar] = what's ours on it: its ground, border, overlay and timer, the
-- game's alphas for what's hidden, its fill and color as the game last set
-- them, the font it had, and what was last put on.
local states = setmetatable({}, { __mode = "k" })
local busy = false -- (while we set the bar: not the game setting its own)

local function State(bar)
	local state = states[bar]
	if not state then
		state = { hidden = {} }
		states[bar] = state
	end
	return state
end

-- A part of the game's shown (its own alpha back) or hidden (alpha 0).
local function ShowPart(state, region, shown)
	if not Usable(region) then
		return
	end
	local hidden = state.hidden
	if not shown then
		if hidden[region] == nil then
			local alpha = region:GetAlpha()
			hidden[region] = type(alpha) == "number" and Known(alpha) and alpha or 1
		end
		region:SetAlpha(0)
	elseif hidden[region] ~= nil then
		region:SetAlpha(hidden[region])
		hidden[region] = nil
	end
end

-- What the bar shows now: "cast", "channel", "locked" (can't be
-- interrupted) or "stop" (interrupted), and the can't-be-interrupted answer
-- when the game keeps it secret (then "cast" or "channel", the overlay
-- showing by it).
local function UnitLocked(bar)
	local unit = bar.unit
	if type(unit) ~= "string" then
		return nil
	end
	local ok, name, _, _, _, _, _, _, locked = pcall(UnitCastingInfo, unit)
	if ok and type(name) ~= "nil" then
		return locked
	end
	local okChannel, channel, _, _, _, _, _, channelLocked = pcall(UnitChannelInfo, unit)
	if okChannel and type(channel) ~= "nil" then
		return channelLocked
	end
	return nil
end

local function CastKind(bar)
	local kind = bar.barType
	if not (type(kind) == "string" and Known(kind)) then
		kind = nil
	elseif kind == "interrupted" then
		return "stop"
	elseif kind == "uninterruptable" or kind == "uninterruptible" then
		return "locked"
	end
	local base = (ns.Flag(bar.channeling) or ns.Flag(bar.reverseChanneling) or kind == "channel") and "channel"
		or "cast"
	local locked = bar.notInterruptible
	if locked == nil then
		locked = UnitLocked(bar)
	end
	if not Known(locked) then
		return base, locked
	end
	return locked and "locked" or base
end

local COLOR_KEYS = {
	cast = { "plateCastR", "plateCastG", "plateCastB" },
	channel = { "plateCastChannelR", "plateCastChannelG", "plateCastChannelB" },
	locked = { "plateCastLockedR", "plateCastLockedG", "plateCastLockedB" },
	stop = { "plateCastStopR", "plateCastStopG", "plateCastStopB" },
}
local function Rgb(look, kind)
	local keys = COLOR_KEYS[kind]
	return look[keys[1]], look[keys[2]], look[keys[3]]
end

-- Each kind of bar (its id, as the settings name it, and its tab's name).
local BARS = {
	{ "PLATE", "Nameplates" },
	{ "PLAYER", "You" },
	{ "TARGET", "Target & focus" },
	{ "BOSS", "Boss & arena" },
}
-- The settings each has a copy of (Default's are the plain keys), starting
-- as Default's; the shared ones (General's) shared under each's name too.
local BAR_KEYS = { "plateCastBorderSize", "plateCastBorderR", "plateCastBorderG", "plateCastBorderB" }
for _, key in ipairs(PRESET_KEYS) do BAR_KEYS[#BAR_KEYS + 1] = key end
for _, keys in pairs(COLOR_KEYS) do
	for _, key in ipairs(keys) do BAR_KEYS[#BAR_KEYS + 1] = key end
end
local OWN_KEY = {}
for _, key in ipairs(BAR_KEYS) do OWN_KEY[key] = true end
for _, info in ipairs(BARS) do
	local id = info[1]
	DEFAULTS["plateCastOwn_" .. id] = false
	if id ~= "PLATE" then DEFAULTS["plateCastOn_" .. id] = false end
	if id == "PLAYER" or id == "TARGET" then DEFAULTS["plateCastFrame_" .. id] = false end -- (the unit frame's look: FrameLooked)
	for _, key in ipairs(BAR_KEYS) do
		DEFAULTS[key .. "_" .. id] = DEFAULTS[key]
		local entry = ns.SHARED_STYLE[key]
		if entry then
			ns.SHARED_STYLE[key .. "_" .. id] = entry.follows
				and { kind = entry.kind, follows = entry.follows .. "_" .. id } or entry
		end
	end
end

-- Whether a kind of bar is restyled: the page on, and for any but the
-- nameplates', its tab's Restyle these bars ticked. (db: the settings to
-- ask, for the options' tests.)
local function Active(id, db)
	db = db or ns.db
	return ns.StyleOn("plateCastStyle", db) and (id == "PLATE" or (db and db["plateCastOn_" .. id])) and true
		or false
end

-- A kind of bar's look (id nil: the Default tab's): its own settings while
-- its "Use default settings" is unticked, else Default's; each through the
-- Style pages' look (General's, and the game's with the page or General off).
local views = {}
-- (Yours and your target's can take their unit frame's look instead, its
-- fill, font and border: FRAME_LOOK, the rest Default's. Their border and
-- background are then the frame's own, drawn by UnitStyle.lua: ours off.)
local OUTLINE_NAMES = { [0] = "none", [1] = "thin", [2] = "thick" }
local FRAME_LOOK = {
	plateCastFill = function(frame) return frame.ufTexture end,
	plateCastBorder = function(frame) return frame.ufBorder == "game" and "game" or "none" end,
	plateCastBack = function() return 0 end,
	plateCastFont = function(frame) return frame.ufFont end,
	plateCastOutline = function(frame) return OUTLINE_NAMES[tonumber(frame.ufOutline)] or "game" end,
	plateCastShadow = function(frame) return frame.ufShadow end,
}
local FRAME_IDS = { PLAYER = true, TARGET = true }
local function FrameLooked(id, db)
	db = db or ns.db
	return FRAME_IDS[id] and db and db["plateCastFrame_" .. id] and Active(id, db) and ns.UnitFrameLook and true
		or false
end
local function View(id)
	local view = views[id or "DEFAULT"]
	if not view then
		view = setmetatable({}, { __index = function(_, key)
			local look = ns.StyleLook("plateCastStyle")
			local db = ns.db
			if FRAME_LOOK[key] and FrameLooked(id, db) then
				local value = FRAME_LOOK[key](ns.UnitFrameLook(id))
				if value ~= nil then return value end
			end
			if id and OWN_KEY[key] and db and ns.StyleOn("plateCastStyle") and db["plateCastOwn_" .. id] then
				return look[key .. "_" .. id]
			end
			return look[key]
		end })
		views[id or "DEFAULT"] = view
	end
	return view
end

-- The look a kind of bar gets now: the game's while it isn't restyled.
local function Look(id)
	if id and not Active(id) then
		return ns.StyleLook("plateCastStyle", true)
	end
	return View(id)
end

function ns.PlateCastLook()
	return Look("PLATE")
end

-- A part of the game's bar: by its key, or (the classic clients' older
-- bars) by its name, <bar's name><part>.
local function Part(bar, field)
	local part = bar[field]
	if part == nil and bar.GetName then
		local name = bar:GetName()
		part = type(name) == "string" and _G[name .. field] or nil
	end
	return part
end

-- Our pieces on a bar, made the first time it needs them.
local function Ground(bar, state)
	if not state.ground then
		state.ground = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
		state.ground:SetAllPoints()
		state.ground:SetColorTexture(0, 0, 0, 1)
	end
	return state.ground
end

-- A frame of 1-wide lines just outside around (r, g, b, a).
local LINES = {
	{ "TOPLEFT", -1, 1, "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", -1, -1, "BOTTOMRIGHT", 1, -1 },
	{ "TOPLEFT", -1, 1, "BOTTOMLEFT", -1, -1 }, { "TOPRIGHT", 1, 1, "BOTTOMRIGHT", 1, -1 },
}
local function Lines(around, r, g, b, a)
	local frame = CreateFrame("Frame", nil, around)
	frame:SetAllPoints()
	frame:SetFrameLevel(around:GetFrameLevel() + 2)
	for i, line in ipairs(LINES) do
		local texture = frame:CreateTexture(nil, "OVERLAY")
		texture:SetColorTexture(r, g, b, a)
		texture:SetPoint(line[1], around, line[1], line[2], line[3])
		texture:SetPoint(line[4], around, line[4], line[5], line[6])
		if i <= 2 then texture:SetHeight(1) else texture:SetWidth(1) end
	end
	return frame
end

local function Edge(bar, state)
	if not state.edge then
		state.edge = ns.MakeStyleEdges(bar)
	end
	return state.edge
end

-- The fill again in the can't-be-interrupted color, over the game's, showing
-- by an answer the game keeps secret (SetAlphaFromBoolean takes those).
local function Overlay(bar, state, fill)
	if not state.overlay then
		state.overlay = bar:CreateTexture(nil, "ARTWORK", nil, 7)
	end
	local overlay = state.overlay
	overlay:ClearAllPoints()
	overlay:SetAllPoints(fill)
	return overlay
end

local function Timer(bar, state)
	if not state.timer then
		local timer = bar:CreateFontString(nil, "OVERLAY")
		local text = Part(bar, "Text")
		-- (the game's font, not ours if the name has it already)
		local own = state.fonts and state.fonts.text
		local object = own and own.object or (Usable(text) and text.GetFontObject and text:GetFontObject())
		timer:SetFontObject(object or "GameFontHighlightSmall")
		timer:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
		timer:SetJustifyH("RIGHT")
		state.timer = timer
	end
	return state.timer
end

-- The spell name's (and the timer's) font: the game's, or ours over it (a
-- family, so every alphabet's letters show: ns.SetPlateNameFont).
local function FontFile(look)
	return ns.StyleFontFile(look.plateCastFont)
end

-- (Its size: the page's Text size, the timer's times the bar's height too,
-- as it's on the bar.)
local function SetFontOnly(state, text, look, which)
	local scale = (look.plateCastTextSize or 1) * (which == "timer" and look.plateCastHeight or 1)
	local wanted = look.plateCastFont ~= "game" or look.plateCastOutline ~= "game"
		or math.abs(scale - 1) > 0.001
	local fonts = state.fonts or {}
	state.fonts = fonts
	local own = fonts[which]
	if not wanted then
		if own and own.ours then
			if own.object then
				text:SetFontObject(own.object)
			elseif own.file then
				pcall(text.SetFont, text, own.file, own.size, own.flags)
			end
			pcall(function() text:SetText(text:GetText()) end)
			own.ours, own.key = false, nil
		end
		return
	end
	if not own then
		local file, size, flags = text:GetFont()
		own = { object = text:GetFontObject(), file = file, size = size, flags = flags }
		fonts[which] = own
	end
	if not (own.file and own.size) then
		return
	end
	local flags = own.flags or ""
	if look.plateCastOutline ~= "game" then
		flags = ns.OutlinedFlags(flags, OUTLINE_LEVEL[look.plateCastOutline] or 1)
	end
	local file = FontFile(look) or own.file
	local key = file .. "|" .. flags .. "|" .. scale
	if own.key ~= key then
		ns.SetPlateNameFont(text, own.object, file, own.size, scale, flags)
		own.ours, own.key = true, key
	end
end
-- (Then its shadow, over what the font brought.)
local function SetFont(state, text, look, which)
	SetFontOnly(state, text, look, which)
	ns.SetTextShadow(text, look.plateCastShadow)
	ns.SetTextColorOf(text, look.plateCastTextColor, look.plateCastTextR, look.plateCastTextG, look.plateCastTextB)
end

-- The fill's color by what's cast, and the overlay for a secret answer.
local function Paint(bar, state, look)
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not fill then
		return
	end
	local kind, secret = CastKind(bar)
	state.kind = kind
	busy = true
	pcall(bar.SetStatusBarColor, bar, Rgb(look, kind))
	busy = false
	local overlay = state.overlay
	if secret ~= nil or overlay then
		overlay = Overlay(bar, state, fill)
		overlay:SetTexture(FILLS[look.plateCastFill])
		overlay:SetVertexColor(Rgb(look, "locked"))
		if secret ~= nil and overlay.SetAlphaFromBoolean then
			if not pcall(overlay.SetAlphaFromBoolean, overlay, secret, 1, 0) then
				overlay:SetAlpha(0)
			end
		else
			overlay:SetAlpha(0)
		end
	end
end

-- The seconds left, when the game will say (its numbers can be secret in
-- fights): hidden otherwise.
local function UpdateTimer(bar, state)
	local timer = state.timer
	if not timer then
		return
	end
	local value, most = bar.value, bar.maxValue
	if not (type(value) == "number" and type(most) == "number" and Known(value) and Known(most)) then
		local ok, v = pcall(bar.GetValue, bar)
		local okRange, _, m = pcall(bar.GetMinMaxValues, bar)
		value, most = ok and v, okRange and m
	end
	if type(value) == "number" and type(most) == "number" and Known(value) and Known(most) and most > 0 then
		local left = (ns.Flag(bar.channeling) and value) or (most - value)
		if left >= 0 and state.kind ~= "stop" then
			timer:SetFormattedText("%.1f", left)
			timer:Show()
			return
		end
	end
	-- (Retail's are secret in fights, the bar's and its fill's too: the
	-- cast's own duration then, secret, which the text can still take.)
	local unit = bar.unit
	if type(unit) == "string" and state.kind ~= "stop" then
		local ok = pcall(function()
			local duration = _G.UnitCastingDuration and _G.UnitCastingDuration(unit)
			if not duration and _G.UnitChannelDuration then
				duration = _G.UnitChannelDuration(unit)
			end
			timer:SetFormattedText("%.1f", duration:GetRemainingDuration())
		end)
		if ok then
			timer:Show()
			return
		end
	end
	timer:Hide()
end

-- The bar's size: its width and height times the page's, about its middle
-- (its top kept: the spell's name under it moves down with it). Retail
-- won't say where a plate's parts are, but the bar's anchors can be read:
-- each put back with its left or right side moved in or out and its bottom
-- down, and a side it isn't held by sized instead. Its own (as the game last
-- set it) kept, and put back at 100%. Not sized while its anchors can't be
-- read (state.sizeWhy says why, for /cine debug plates).
local function Number(ok, value)
	return ok and type(value) == "number" and Known(value) and value or nil
end

local function ReadPoints(bar)
	local count = Number(pcall(bar.GetNumPoints, bar))
	if not count then
		return nil, "its anchors are secret"
	end
	local points = {}
	for i = 1, count do
		local ok, point, relative, relativePoint, x, y = pcall(bar.GetPoint, bar, i)
		if not (ok and Known(point) and Known(relative) and Known(relativePoint) and Known(x) and Known(y)) then
			return nil, "its anchors are secret"
		end
		points[i] = { point, relative, relativePoint, x or 0, y or 0 }
	end
	return points
end

local function SamePoints(a, b)
	if not (a and b) or #a ~= #b then
		return false
	end
	for i, p in ipairs(a) do
		local q = b[i]
		if p[1] ~= q[1] or p[2] ~= q[2] or p[3] ~= q[3] or math.abs(p[4] - q[4]) > 0.01
			or math.abs(p[5] - q[5]) > 0.01 then
			return false
		end
	end
	return true
end

local function SetPoints(bar, points)
	pcall(bar.ClearAllPoints, bar)
	for _, p in ipairs(points) do
		pcall(bar.SetPoint, bar, p[1], p[2], p[3], p[4], p[5])
	end
end

-- Whether a size read back (now) is the game's own again rather than ours:
-- the game snaps sizes to whole pixels, so ours reads back a little off
-- (taking that for the game's own grew the bar on every cast, without end).
local function Reset(now, ours)
	return not ours or math.abs(now - ours) > math.max(1, ours * 0.05)
end

-- Retail's: the bar's own anchors and size are secret. The game holds it
-- at a height of its own on its container's bottom, the health bar on top
-- (a taller container only pushed the health bar up; scaling it moved it
-- off, its anchors' offsets scaled too: both tested). So its height's set,
-- growing up from its bottom, and its container grows by the same, the
-- health bar and name riding up on it. Its own height is read off its
-- ground, which fills it (the bar's own is secret); ours reads back there
-- too, so that's the game's own again only when clearly not ours. Its
-- width there is the health bar's: the Nameplate Style page's. All put
-- back at 100%.
local function OwnHeight(bar)
	local ground = bar.Background
	if Usable(ground) and ground.GetHeight then
		local height = Number(pcall(ground.GetHeight, ground))
		if height and height > 0 then
			return height
		end
	end
end

local function Room(bar, state, grow)
	local container = bar:GetParent()
	if not (Usable(container) and container.SetHeight) then
		return
	end
	local now = Number(pcall(container.GetHeight, container))
	if now and Reset(now, state.containerHeight) then
		state.containerOwn = now
	end
	local own = state.containerOwn
	if not grow then
		if state.containerHeight and own then
			pcall(container.SetHeight, container, own)
		end
		state.containerHeight = nil
		return
	end
	if own and own > 0 then
		state.containerHeight = own + grow
		pcall(container.SetHeight, container, state.containerHeight)
	end
end

local function HeightOnly(bar, state, height)
	local now = OwnHeight(bar)
	if now and Reset(now, state.barHeight) then
		state.ownHeight = now
	end
	local own = state.ownHeight
	if math.abs(height - 1) < 0.001 then
		if state.barHeight and own then
			pcall(bar.SetHeight, bar, own)
			Room(bar, state, nil)
		end
		state.barHeight, state.sizeWhy = nil, nil
		return
	end
	if not own then
		state.sizeWhy = "its anchors and height are secret"
		return
	end
	state.barHeight = own * height
	pcall(bar.SetHeight, bar, state.barHeight)
	-- (The bar sits on the icon's row, so a taller icon lifts it too, tested.)
	Room(bar, state, state.barHeight - own + (state.iconGain or 0))
	state.sizeWhy = nil
end

-- The bar's wide effects (the interrupt glow, its flashes and sparkles: a
-- texture or frame of the game's on it at least half its width, with a width
-- of its own, not pinned at both sides) widened as the bar is (ratio: its
-- width now over its own, own); the small ones (icon, spark, shield) and
-- text left. Each one's own width kept as the game last set it (it may set
-- one again as it plays: we follow on the bar's next event), put back at 1.
local function WidenEffects(bar, state, ratio, own)
	if not (own and own > 0) then
		return
	end
	state.effects = state.effects or setmetatable({}, { __mode = "k" })
	local ours = {}
	for _, value in pairs(state) do
		if type(value) == "table" then ours[value] = true end
	end
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	local pieces = {}
	pcall(function()
		for _, region in ipairs({ bar:GetRegions() }) do pieces[#pieces + 1] = region end
		for _, child in ipairs({ bar:GetChildren() }) do pieces[#pieces + 1] = child end
	end)
	for _, piece in ipairs(pieces) do
		local kind = piece.GetObjectType and piece:GetObjectType()
		if piece ~= fill and not ours[piece] and kind ~= "FontString" and Usable(piece) and piece.SetWidth then
			local points = ReadPoints(piece)
			local left, right = false, false
			for _, p in ipairs(points or {}) do
				if p[1]:find("LEFT") then left = true end
				if p[1]:find("RIGHT") then right = true end
			end
			local saved = state.effects[piece]
			local now = Number(pcall(piece.GetWidth, piece))
			if points and not (left and right) and now and now > 0 then
				if not saved or Reset(now, saved.ours) then
					saved = { own = now }
					state.effects[piece] = saved
				end
				if saved.own >= own * 0.5 then
					if math.abs(ratio - 1) < 0.001 then
						if saved.ours then pcall(piece.SetWidth, piece, saved.own) end
						saved.ours = nil
					else
						saved.ours = saved.own * ratio
						pcall(piece.SetWidth, piece, saved.ours)
					end
				end
			end
		end
	end
end

local function SizeBar(bar, state, look)
	local width, height = look.plateCastWidth or 1, look.plateCastHeight or 1
	local wanted = math.abs(width - 1) > 0.001 or math.abs(height - 1) > 0.001
	local points, why = ReadPoints(bar)
	if not points and not state.sized then
		HeightOnly(bar, state, height)
		return
	end
	-- (The game's own again whenever what's on it isn't what we put on.)
	if points and not SamePoints(points, state.sizedPoints) then
		state.own = state.own or {}
		state.own.points = points
	end
	local own = state.own
	if own then
		local nowWidth = Number(pcall(bar.GetWidth, bar))
		local nowHeight = Number(pcall(bar.GetHeight, bar))
		if nowWidth and Reset(nowWidth, state.sizedWidth) then
			own.width = nowWidth
		end
		if nowHeight and Reset(nowHeight, state.sizedHeight) then
			own.height = nowHeight
		end
	end
	if not wanted then
		if state.sized and own and own.points then
			SetPoints(bar, own.points)
			if own.width and own.height then
				pcall(bar.SetSize, bar, own.width, own.height)
			end
		end
		if state.effects then WidenEffects(bar, state, 1, own and own.width) end
		state.sized, state.sizedPoints, state.sizedWidth, state.sizedHeight, state.sizeWhy = false, nil, nil, nil, nil
		return
	end
	if not (own and own.points and own.width and own.height and own.width > 0 and own.height > 0) then
		state.sizeWhy = why or "no size yet"
		return
	end
	local sides = {}
	for _, p in ipairs(own.points) do
		for _, side in ipairs({ "LEFT", "RIGHT", "TOP", "BOTTOM" }) do
			if p[1]:find(side) then sides[side] = true end
		end
	end
	local dx = own.width * (1 - width) / 2
	local grow = own.height * (height - 1)
	local mine = {}
	for i, p in ipairs(own.points) do
		local x, y = p[4], p[5]
		if p[1]:find("LEFT") then
			x = x + dx
		elseif p[1]:find("RIGHT") then
			x = x - dx
		end
		if p[1]:find("BOTTOM") then
			y = y - grow
		end
		mine[i] = { p[1], p[2], p[3], x, y }
	end
	SetPoints(bar, mine)
	state.sizedWidth, state.sizedHeight = nil, nil
	if not (sides.LEFT and sides.RIGHT) then
		state.sizedWidth = own.width * width
		pcall(bar.SetWidth, bar, state.sizedWidth)
	end
	if not (sides.TOP and sides.BOTTOM) then
		state.sizedHeight = own.height * height
		pcall(bar.SetHeight, bar, state.sizedHeight)
	end
	WidenEffects(bar, state, width, own.width)
	state.sized, state.sizedPoints, state.sizeWhy = true, mine, nil
end

-- The spell's icon at the page's size (its place the game's, its
-- size taken from its anchor). Its own size is the game's again whenever it
-- clearly isn't ours (read-backs snap to pixels).
local function SizeIcon(bar, state, height)
	local icon = Part(bar, "Icon")
	if not (Usable(icon) and icon.SetSize) then
		return
	end
	local width = Number(pcall(icon.GetWidth, icon))
	local tall = Number(pcall(icon.GetHeight, icon))
	if width and tall and width > 0 and tall > 0 then
		local ours = state.iconSize
		if not ours or Reset(width, ours[1]) or Reset(tall, ours[2]) then
			state.iconOwn = { width, tall }
		end
	end
	local own = state.iconOwn
	if math.abs(height - 1) < 0.001 then
		if state.iconSize and own then
			pcall(icon.SetSize, icon, own[1], own[2])
		end
		state.iconSize, state.iconGain = nil, nil
		return
	end
	if own then
		state.iconSize = { own[1] * height, own[2] * height }
		state.iconGain = own[2] * (height - 1)
		pcall(icon.SetSize, icon, state.iconSize[1], state.iconSize[2])
	end
end

-- Yours: its width alone (the You tab's own Width), set about the point it
-- hangs from, its anchors left be (Edit Mode's; PersonalMana.lua moves it
-- down under our mana bar). Pinned at both sides: left at the game's. Its
-- own width kept as the game last set it, put back at 100%.
-- (width: { scale = times the game's } or { px = pixels on screen }.)
local function WidthOnly(bar, state, width)
	local now = Number(pcall(bar.GetWidth, bar))
	if now and now > 0 and Reset(now, state.widthOnly) then
		state.widthOwn = now
	end
	local own = state.widthOwn
	local target = own and (width.px and ns.PixelsToUnits and ns.PixelsToUnits(bar, width.px)
		or own * (width.scale or 1))
	local points = ReadPoints(bar)
	local left, right = false, false
	for _, p in ipairs(points or {}) do
		if p[1]:find("LEFT") then left = true end
		if p[1]:find("RIGHT") then right = true end
	end
	if not target or math.abs(target - own) < 0.01 or (left and right) then
		if state.widthOnly and own then
			pcall(bar.SetWidth, bar, own)
		end
		if state.effects then WidenEffects(bar, state, 1, own) end
		state.widthOnly = nil
		return
	end
	state.widthOnly = target
	pcall(bar.SetWidth, bar, target)
	WidenEffects(bar, state, target / own, own)
end

local GAME_WIDTH = { scale = 1 }

-- (sized: the bar's own size too, the nameplates' alone; a table: its
-- width alone, as WidthOnly's (yours with a look of its own); the rest
-- keep the game's, yours set in Edit Mode.)
local UNSIZED = { plateCastWidth = 1, plateCastHeight = 1 }
local function Size(bar, state, look, sized)
	SizeIcon(bar, state, look.plateCastIconSize or 1)
	-- (Each way's own size back before the other reads it: a preview's
	-- sample, its tab changed.)
	if type(sized) ~= "table" and state.widthOnly then
		WidthOnly(bar, state, GAME_WIDTH)
	end
	if sized == true then
		SizeBar(bar, state, look)
	elseif state.sized or state.barHeight then
		SizeBar(bar, state, UNSIZED)
	end
	if type(sized) == "table" then
		WidthOnly(bar, state, sized)
	end
end

-- How a kind of bar is sized: the nameplates' wholly, yours by the You
-- tab's Width while it's restyled with a look of its own.
local function SizedAs(id, db)
	if id == "PLATE" then return true end
	db = db or ns.db
	if id == "PLAYER" and db and db.plateCastOwn_PLAYER and Active(id, db) then
		local px = db.plateCastPlayerWidthUnit == "px" and tonumber(db.plateCastPlayerWidthPx)
		if px and px > 0 then return { px = px } end
		return { scale = tonumber(db.plateCastPlayerWidth) or 1 }
	end
	return false
end

-- Your cast bar's width on screen now, in whole pixels (the page fills its
-- px box with it when picked).
local function PlayerBarPixels()
	local bar = _G.PlayerCastingBarFrame or _G.CastingBarFrame
	local width = bar and Number(pcall(bar.GetWidth, bar))
	local px = width and width > 0 and ns.UnitsToPixels and ns.UnitsToPixels(bar, width)
	return px and math.floor(px + 0.5)
end

-- Puts the look on a bar (the game's where a setting says the game's). The
-- preview's bars too (sample: no game fill to put back). sized: a
-- nameplate's (or a sample of one), sized by the page.
local function Apply(bar, look, sample, sized)
	local state = State(bar)
	local ours = FILLS[look.plateCastFill]
	if ours then
		busy = true
		pcall(bar.SetStatusBarTexture, bar, ours)
		busy = false
		Paint(bar, state, look)
		state.filled = true
	elseif state.filled then
		state.filled = false
		if not sample and state.ownFill then
			busy = true
			pcall(bar.SetStatusBarTexture, bar, state.ownFill)
			if state.ownColor then
				pcall(bar.SetStatusBarColor, bar, unpack(state.ownColor))
			end
			busy = false
		end
		if state.overlay then state.overlay:SetAlpha(0) end
	end
	local ground = (ours and look.plateCastBack > 0) and Ground(bar, state) or state.ground
	if ground then
		ground:SetAlpha(look.plateCastBack)
		ground:SetShown(ours ~= nil and look.plateCastBack > 0)
	end
	ShowPart(state, Part(bar, "Background"), not ours)
	local border, size, br, bg, bb = ns.StyleBorder(look, "plateCastBorder")
	-- (The box the spell's name sits in goes with the name.)
	for _, field in ipairs(BORDER_ART) do
		ShowPart(state, Part(bar, field), border == "game" and (field ~= "TextBorder" or look.plateCastText))
	end
	if border == "line" then
		local edge = Edge(bar, state)
		ns.DressStyleEdges(edge, size, br, bg, bb, 1, true)
		edge:Show()
	elseif state.edge then
		state.edge:Hide()
	end
	ShowPart(state, Part(bar, "Spark"), look.plateCastSpark)
	ShowPart(state, Part(bar, "Icon"), look.plateCastIcon)
	ShowPart(state, Part(bar, "BorderShield"), look.plateCastShield)
	ShowPart(state, bar.ImportantCastIndicator, look.plateCastImportant)
	ShowPart(state, bar.CastTargetIndicator, look.plateCastTarget)
	ShowPart(state, bar.CastTargetNameText, look.plateCastTarget)
	local text = Part(bar, "Text")
	ShowPart(state, text, look.plateCastText)
	if Usable(text) and text.GetFont then
		SetFont(state, text, look, "text")
	end
	if look.plateCastTimer then
		local timer = Timer(bar, state)
		SetFont(state, timer, look, "timer")
		UpdateTimer(bar, state)
	elseif state.timer then
		state.timer:Hide()
	end
	Size(bar, state, look, sized)
	state.on = true
end
ns.StylePlateCastBar = Apply

-- The real bars: each hooked once, so whatever the game sets on it as a
-- cast starts, changes or ends, the look goes back on. A bar no longer
-- restyled gets the game's look back once, then is left be.
local hooked = setmetatable({}, { __mode = "k" })
local barIds = setmetatable({}, { __mode = "k" }) -- [bar] = its kind's id

-- With the unit frame's look, the bar is part of the frame: pinned just under
-- its lowest bar, as wide as it, the spell's icon in the frame's left edge,
-- and the frame's buffs that hang under it moved down to under the cast bar.
-- Yours only while Edit Mode has it locked to the player frame (else it's
-- where you put it). The game places these bars again as buffs come and go:
-- each time, ours goes back on a frame later. Not in fights where the game
-- locks the bar. Its own anchors (and the buffs') put back when turned off.
local PIN_GAP = 3 -- (under the frame's bar: past both borders)
local placing = false
local pinned = setmetatable({}, { __mode = "k" }) -- [bar or buff] = { own = its points, ours = ours }
local pinReport = {} -- [bar] = what the last try did (/cine debug unitframes)
local pinHooked = setmetatable({}, { __mode = "k" }) -- [region] = its SetPoint heard
local PlaceOnFrame -- (below)

-- (The game places it again: ours back on a frame later, once.)
local pinSoon = setmetatable({}, { __mode = "k" })
local function OnGamePoint(bar)
	if placing or not pinned[bar] or pinSoon[bar] then return end
	pinSoon[bar] = true
	C_Timer.After(0, function()
		pinSoon[bar] = nil
		if pinned[bar] and FrameLooked(barIds[bar]) then PlaceOnFrame(bar, true) end
	end)
end

local function OwnerOf(bar)
	if bar == _G.PlayerCastingBarFrame then
		return bar.attachedToPlayerFrame and _G.PlayerFrame or nil, "PLAYER"
	end
	for _, name in ipairs({ "TargetFrame", "FocusFrame" }) do
		local frame = _G[name]
		if frame and (frame.spellbar == bar or _G[name .. "SpellBar"] == bar) then
			return frame, name == "TargetFrame" and "TARGET" or "FOCUS"
		end
	end
end

local function Locked(region)
	return InCombatLockdown() and region.IsProtected and select(2, region:IsProtected())
end

-- (A region's points, ours on it, or the game's again: then kept as its own.)
local function Pin(region, points)
	local saved = pinned[region]
	local now = ReadPoints(region)
	if now and not (saved and SamePoints(now, saved.ours)) then
		saved = { own = now }
		pinned[region] = saved
	end
	if not saved or Locked(region) then return false end
	placing = true
	SetPoints(region, points)
	placing = false
	saved.ours = ReadPoints(region)
	return true
end

local function Unpin(region)
	local saved = pinned[region]
	if not saved then return end
	pinned[region] = nil
	local now = ReadPoints(region)
	if saved.own and now and SamePoints(now, saved.ours) and not Locked(region) then
		placing = true
		SetPoints(region, saved.own)
		placing = false
	end
end

local function Bottom(region)
	local ok, bottom = pcall(region.GetBottom, region)
	local okScale, scale = pcall(region.GetEffectiveScale, region)
	if ok and okScale and type(bottom) == "number" and Known(bottom) and Known(scale) then return bottom * scale end
end
local function Top(region)
	local ok, top = pcall(region.GetTop, region)
	local okScale, scale = pcall(region.GetEffectiveScale, region)
	if ok and okScale and type(top) == "number" and Known(top) and Known(scale) then return top * scale, scale end
end

-- The frame's buffs and debuffs that start a row under it: its small square
-- children held by the frame itself or by their holder (the rest of a row
-- hangs off those). Retail's and Forever's target and focus: in
-- TargetFrameContent.TargetFrameContentContextual.Auras (/cine debug
-- unitframes, 2026-11-17).
local function AuraHolder(frame)
	local content = frame.TargetFrameContent
	local contextual = content and content.TargetFrameContentContextual
	return contextual and contextual.Auras
end
local function BuffStarts(frame, bar)
	local list = {}
	local holder = AuraHolder(frame)
	for _, parent in ipairs({ frame, holder or false }) do
		local ok, children = pcall(function() return parent and { parent:GetChildren() } or {} end)
		for _, child in ipairs(ok and children or {}) do
			if child ~= bar and Usable(child) then
				local width = Number(pcall(child.GetWidth, child))
				local height = Number(pcall(child.GetHeight, child))
				local points = ReadPoints(child)
				local first = points and points[1]
				if width and height and width > 8 and width <= 40 and math.abs(width - height) < 3 and first
					and (first[2] == frame or (holder and first[2] == holder)) and first[1]:find("TOP") then
					list[#list + 1] = child
				end
			end
		end
	end
	return list
end

local buffsMoved = setmetatable({}, { __mode = "k" }) -- [frame] = { its buffs we moved }
local function PlaceBuffs(frame, bar, on)
	local moved = buffsMoved[frame] or {}
	buffsMoved[frame] = moved
	if not on then
		for buff in pairs(moved) do Unpin(buff) end
		wipe(moved)
		return 0
	end
	local floor = Bottom(bar)
	local count = 0
	for _, buff in ipairs(BuffStarts(frame, bar)) do
		local saved = pinned[buff]
		local own = saved and saved.own
		local now = ReadPoints(buff)
		if now and not (saved and SamePoints(now, saved.ours)) then own = now end
		local top, scale = Top(buff)
		if own and top and floor then
			-- (From where the game holds it: a frame's own place, not ours.)
			local shift = 0
			if saved and saved.ours and SamePoints(now, saved.ours) then
				shift = own[1][5] - now[1][5]
			end
			local ownTop = top + shift * scale
			local want = floor - PIN_GAP * scale
			if ownTop > want then
				local points = {}
				for i, p in ipairs(own) do
					points[i] = { p[1], p[2], p[3], p[4], p[5] - (ownTop - want) / scale }
				end
				if Pin(buff, points) then
					if not pinHooked[buff] then
						pinHooked[buff] = true
						hooksecurefunc(buff, "SetPoint", function() OnGamePoint(bar) end)
					end
					moved[buff] = true
					count = count + 1
				end
			elseif moved[buff] then
				Unpin(buff)
				moved[buff] = nil
			end
		end
	end
	return count
end

function PlaceOnFrame(bar, on)
	local frame, frameId = OwnerOf(bar)
	if not pinHooked[bar] then
		pinHooked[bar] = true
		hooksecurefunc(bar, "SetPoint", function(self) OnGamePoint(self) end)
	end
	local report = { frame = frameId or "none" }
	pinReport[bar] = report
	if not (on and frame) then
		Unpin(bar)
		if frame then PlaceBuffs(frame, bar, false) end
		report.why = not frame and "not on a unit frame (yours: not locked to the player frame)" or "off"
		return
	end
	local health, power = ns.UnitFrameBars(frame)
	local lowest = Usable(power) and power:IsShown() and power or health
	if not Usable(lowest) then
		report.why = "no health bar found"
		return
	end
	-- (The icon's at the bar's left, outside it: the bar starts that far in.)
	local icon = Part(bar, "Icon")
	local room = 0
	local iconWidth = Usable(icon) and Number(pcall(icon.GetWidth, icon))
	local iconAlpha = Usable(icon) and Number(pcall(icon.GetAlpha, icon))
	if iconWidth and iconAlpha and iconAlpha > 0 then room = iconWidth + 3 end
	local placed = Pin(bar, {
		{ "TOPLEFT", lowest, "BOTTOMLEFT", room, -PIN_GAP },
		{ "TOPRIGHT", lowest, "BOTTOMRIGHT", 0, -PIN_GAP },
	})
	report.placed = placed
	report.why = not placed and (Locked(bar) and "locked in a fight" or "its anchors can't be read") or nil
	report.buffs = placed and PlaceBuffs(frame, bar, true) or 0
end

function ns.UnitCastPinReport()
	local lines = {}
	for bar, report in pairs(pinReport) do
		local name = bar.GetName and bar:GetName() or "?"
		local anchors = {}
		for _, p in ipairs(ReadPoints(bar) or {}) do
			local okName, relative = pcall(function() return p[2] and p[2]:GetDebugName() end)
			anchors[#anchors + 1] = ("%s>%s %s %.1f,%.1f"):format(p[1], okName and Known(relative)
				and tostring(relative):match("[^.]*$") or "?", p[3], p[4], p[5])
		end
		local frame = OwnerOf(bar)
		local starts = {}
		for _, buff in ipairs(frame and BuffStarts(frame, bar) or {}) do
			local okName, buffName = pcall(buff.GetDebugName, buff)
			starts[#starts + 1] = okName and Known(buffName) and tostring(buffName):match("[^.]*$") or "?"
		end
		lines[#lines + 1] = ("cast pin %s: frame %s, placed %s, buffs moved %s%s; width %s; anchors %s; buff rows %s")
			:format(tostring(name), report.frame, tostring(report.placed or false), tostring(report.buffs or 0),
				report.why and (" (" .. report.why .. ")") or "", tostring(Number(pcall(bar.GetWidth, bar))),
				#anchors > 0 and table.concat(anchors, " + ") or "secret", #starts > 0 and table.concat(starts, ", ")
				or "none found")
	end
	return lines
end

local function Restyle(bar)
	local id = barIds[bar] or "PLATE"
	local state = states[bar]
	local active = Active(id)
	if not active and not (state and state.on) then
		return
	end
	Apply(bar, Look(id), nil, SizedAs(id))
	if FRAME_IDS[id] then
		local framed = FrameLooked(id)
		if framed or (state and state.framed) then
			local _, frameId = OwnerOf(bar)
			ns.DressCastSkin(bar, framed and (frameId or id) or nil)
			PlaceOnFrame(bar, framed)
			states[bar].framed = framed
		end
	end
	if not active then
		states[bar].on = false
	end
end

local onEvent = ns.Profiled("Plate cast bar style", Restyle)
local onUpdate = ns.Profiled("Plate cast bar style update", function(bar)
	local state = states[bar]
	if not (state and state.on) then
		return
	end
	local look = Look(barIds[bar] or "PLATE")
	-- (What's cast can change mid-cast: an interrupt, a shield coming up.)
	if state.filled then
		local kind = CastKind(bar)
		if kind ~= state.kind then
			Paint(bar, state, look)
		end
	end
	if look.plateCastTimer then
		UpdateTimer(bar, state)
	end
end)

local function Hook(bar, id)
	if hooked[bar] then
		return
	end
	hooked[bar] = true
	barIds[bar] = id
	bar:HookScript("OnEvent", onEvent)
	bar:HookScript("OnShow", onEvent)
	ns.HookOnUpdate(bar, onUpdate)
	-- (The game's own fill and color kept, for turning ours off again.)
	pcall(hooksecurefunc, bar, "SetStatusBarTexture", function(self, texture)
		if busy then
			return
		end
		local state = State(self)
		local fill = self:GetStatusBarTexture()
		local atlas = fill and fill.GetAtlas and fill:GetAtlas()
		state.ownFill = (Known(atlas) and atlas) or (Known(texture) and texture) or state.ownFill
		if state.on then
			Restyle(self)
		end
	end)
	pcall(hooksecurefunc, bar, "SetStatusBarColor", function(self, r, g, b, a)
		if busy then
			return
		end
		local state = State(self)
		if Known(r) and Known(g) and Known(b) and Known(a) then
			state.ownColor = { r, g, b, a or 1 }
		end
		if state.on and state.filled then
			Paint(self, state, Look(barIds[self] or "PLATE"))
		end
	end)
end

-- A plate's cast bar (WoW Forever's in CastBarsContainer), or nil.
local function BarOf(unitFrame)
	if not Usable(unitFrame) then
		return nil
	end
	local container = unitFrame.CastBarsContainer
	local bar = unitFrame.castBar or (type(container) == "table" and container.castBar) or unitFrame.CastBar
	return Usable(bar) and bar.SetStatusBarTexture and bar or nil
end

local function PersonalPlate()
	return C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("player")
end

local function StylePlate(plate)
	if not plate or plate == PersonalPlate() then
		return
	end
	local bar = BarOf(plate.UnitFrame)
	if not bar then
		return
	end
	if Active("PLATE") then
		Hook(bar, "PLATE")
	end
	if hooked[bar] then
		Restyle(bar)
	end
end

-- The game's other cast bars, by kind: yours (retail's, Classic's, the
-- pet's for vehicles and mind control, WoW Forever's gamepad one), the
-- target's and focus's (spellbar on every client; by its name too), and the
-- bosses' and arena enemies' (retail's arena frames, the classic clients'
-- by name). Untested: the arena ones.
local GAME_BARS = {
	PLAYER = function(add)
		for _, name in ipairs({ "PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame", "CastingBarFrame",
			"PetCastingBarFrame", "GamepadPlayerCastingBarFrame" }) do
			add(_G[name])
		end
	end,
	TARGET = function(add)
		for _, name in ipairs({ "TargetFrame", "FocusFrame" }) do
			add(_G[name] and _G[name].spellbar)
			add(_G[name .. "SpellBar"])
		end
	end,
	BOSS = function(add)
		for i = 1, 8 do
			local boss = _G["Boss" .. i .. "TargetFrame"]
			add(boss and boss.spellbar)
			add(_G["Boss" .. i .. "TargetFrameSpellBar"])
			add(_G["ArenaEnemyFrame" .. i .. "CastingBar"])
			add(_G["ArenaEnemyMatchFrame" .. i .. "CastingBar"])
		end
		local arena = _G.CompactArenaFrame
		if type(arena) == "table" and type(arena.memberUnitFrames) == "table" then
			for _, member in ipairs(arena.memberUnitFrames) do
				add(type(member) == "table" and member.CastingBarFrame)
			end
		end
	end,
}

-- One kind's bars: hooked once it's restyled, each dressed again.
local function StyleGame(id)
	local seen = {}
	pcall(GAME_BARS[id], function(bar)
		if not (Usable(bar) and bar.SetStatusBarTexture and bar.HookScript) or seen[bar] then
			return
		end
		seen[bar] = true
		if Active(id) then
			Hook(bar, id)
		end
		if hooked[bar] then
			Restyle(bar)
		end
	end)
end

-- Every bar again (a change on the page).
function ns.RefreshPlateCastStyle()
	if not ns.db then
		return
	end
	for id in pairs(GAME_BARS) do
		StyleGame(id)
	end
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		StylePlate(plate)
	end
end

ns.plateSleep.OnWake(function(plate) if ns.db then StylePlate(plate) end end)

-- (The bosses' and arena's frames come as they're needed: looked for again
-- then.)
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_ENTERING_WORLD", "ADDON_LOADED",
	"INSTANCE_ENCOUNTER_ENGAGE_UNIT", "ARENA_OPPONENT_UPDATE" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event, unit)
	if not ns.db then
		return
	end
	if event == "NAME_PLATE_UNIT_ADDED" then
		if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
			local plate = C_NamePlate.GetNamePlateForUnit(unit)
			-- (Showing nothing: styled as it wakes. PlateSleep.lua.)
			if not ns.PlateAsleep(plate) then StylePlate(plate) end
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		for id in pairs(GAME_BARS) do
			StyleGame(id)
		end
	elseif event == "ADDON_LOADED" then
		if unit == "Blizzard_ArenaUI" or unit == "Blizzard_CompactRaidFrames" then
			StyleGame("BOSS")
		end
	else
		StyleGame("BOSS")
	end
end)

-- The bar's size and anchors now, its container's size, ours on it, or why not.
local function SizeReport(bar, state)
	local function Num(value)
		return value and ("%.1f"):format(value) or "?"
	end
	local function Pair(size)
		return size and size[1] and size[2] and ("%sx%s"):format(Num(size[1]), Num(size[2])) or "?"
	end
	local points, why = ReadPoints(bar)
	local anchors = {}
	for _, p in ipairs(points or {}) do
		local okName, name = pcall(function() return p[2] and p[2]:GetDebugName() end)
		anchors[#anchors + 1] = ("%s>%s %s %s,%s"):format(p[1],
			okName and Known(name) and tostring(name):match("[^.]*$") or "?", p[3], Num(p[4]), Num(p[5]))
	end
	local container = bar:GetParent()
	local own = state and state.own
	return ("bar %sx%s, anchors %s; container %sx%s (own height %s, ours %s); bar height by its ground %s (own %s, ours %s); icon %s (own %s); own %sx%s; ours %s%s"):format(
		Num(Number(pcall(bar.GetWidth, bar))), Num(Number(pcall(bar.GetHeight, bar))),
		points and (#anchors > 0 and table.concat(anchors, " + ") or "none") or why,
		Num(container and Number(pcall(container.GetWidth, container))),
		Num(container and Number(pcall(container.GetHeight, container))),
		Num(state and state.containerOwn), Num(state and state.containerHeight),
		Num(OwnHeight(bar)), Num(state and state.ownHeight), Num(state and state.barHeight),
		Pair(bar.Icon and Usable(bar.Icon) and { Number(pcall(bar.Icon.GetWidth, bar.Icon)),
			Number(pcall(bar.Icon.GetHeight, bar.Icon)) }), Pair(state and state.iconOwn),
		Num(own and own.width), Num(own and own.height),
		tostring(state and state.sized or false), state and state.sizeWhy and (" (" .. state.sizeWhy .. ")") or "")
end

-- For /cine debug plates: where the target plate's cast bar is, its fields,
-- what it's casting as we read it, and what's ours on it.
function ns.DescribePlateCastBar(unitFrame)
	local bar = BarOf(unitFrame)
	if not bar then
		local container = unitFrame and unitFrame.CastBarsContainer
		return "none found (castBar " .. tostring(unitFrame and unitFrame.castBar ~= nil) .. ", container "
			.. tostring(container ~= nil) .. ")"
	end
	local function Say(value)
		if not Known(value) then
			return "secret"
		end
		return type(value) == "number" and ("%.2f"):format(value) or tostring(value)
	end
	local fields = {}
	for field, value in pairs(bar) do
		if type(field) == "string" and type(value) == "table"
			and select(2, pcall(function() return value.GetObjectType ~= nil end)) == true then
			local okType, kind = pcall(value.GetObjectType, value)
			local okShown, shown = pcall(value.IsShown, value)
			local okAlpha, alpha = pcall(value.GetAlpha, value)
			fields[#fields + 1] = ("%s:%s%s a=%s"):format(field, okType and tostring(kind) or "?",
				(okShown and Known(shown) and not shown) and "(hidden)" or "", okAlpha and Say(alpha) or "?")
		end
	end
	table.sort(fields)
	local fill = bar:GetStatusBarTexture()
	local okAtlas, atlas = pcall(function() return fill and fill:GetAtlas() end)
	local okTexture, texture = pcall(function() return fill and fill:GetTexture() end)
	local kind, secret = CastKind(bar)
	local state = states[bar]
	return ("%s; barType=%s casting=%s channeling=%s notInterruptible=%s unit=%s value=%s/%s; we read %s%s; "
		.. "fill atlas=%s texture=%s; page %s, hooked %s, styled %s, game fill %s; size: %s; fields: %s"):format(
		bar == unitFrame.castBar and "castBar" or (bar == unitFrame.CastBar and "CastBar" or "CastBarsContainer.castBar"),
		Say(bar.barType), Say(bar.casting), Say(bar.channeling), Say(bar.notInterruptible), Say(bar.unit),
		Say(bar.value), Say(bar.maxValue), kind, secret ~= nil and " (can't-interrupt secret)" or "",
		okAtlas and Say(atlas) or "?", okTexture and Say(texture) or "?",
		tostring(Active("PLATE")), tostring(hooked[bar] == true), tostring(state and state.on),
		tostring(state and state.ownFill), SizeReport(bar, state), table.concat(fields, ", "))
end

-- The page.
-- (Each: its label, icon and spell, the spell's name in the game's own words.)
local SAMPLES = {
	{ "Casting", "Interface\\Icons\\Spell_Fire_FlameBolt", 133, "Fireball" },
	{ "Channeling", "Interface\\Icons\\Spell_Shadow_SiphonMana", 689, "Drain Life", channel = true },
	{ "Can't be interrupted", "Interface\\Icons\\Spell_Shadow_ShadowBolt", 686, "Shadow Bolt", locked = true },
}
local function SpellName(id, fallback)
	local ok, name = pcall(function()
		return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or (GetSpellInfo and GetSpellInfo(id))
	end)
	return ok and type(name) == "string" and name or fallback
end
local SAMPLE_TIME = 2.5 -- seconds a sample cast takes, over and over
local SAMPLE_W = 140 -- a sample plate's width (the game's are about 258 wide)
-- The game's own fills, retail's atlases (the classic smooth one where
-- there's none).
local GAME_ATLAS = { cast = "UI-CastingBar-Full-Standard", channel = "UI-CastingBar-Full-Channel",
	locked = "UI-CastingBar-Full-Uninterruptable" }
local GAME_COLORS = { cast = { 1, 0.7, 0 }, channel = { 0, 1, 0 }, locked = { 0.7, 0.7, 0.7 } }

-- A stand-in for the game's bar: a status bar with its parts by the same names.
local function MakeSample(parent, info)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(SAMPLE_W, 7)
	bar:SetMinMaxValues(0, 1)
	local background = bar:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.5)
	bar.Background = background
	bar.Border = Lines(bar, 0.75, 0.75, 0.75, 0.8)
	local icon = bar:CreateTexture(nil, "OVERLAY")
	-- (Laid out as the game's: retail's icon and spell name under the bar,
	-- at its left; elsewhere the icon at the bar's left, the name on it.)
	icon:SetSize(13, 13)
	if ns.isRetail then
		icon:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
	else
		icon:SetPoint("RIGHT", bar, "LEFT", -3, 0)
	end
	-- (The spell's own icon, the game's current art. Not filtered smooth: SetTexture with a
	-- filter mode crashed the game on retail as the page was made.)
	local art = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(info[3]) or info[2]
	icon:SetTexture(art)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	bar.Icon = icon
	local shield = bar:CreateTexture(nil, "OVERLAY", nil, 1)
	shield:SetSize(20, 24)
	shield:SetPoint("CENTER", icon, "CENTER", 0, -1)
	if not (shield.SetAtlas and pcall(shield.SetAtlas, shield, "nameplates-InterruptShield")) then
		shield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
	end
	shield:SetShown(info.locked == true)
	bar.BorderShield = shield
	local spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
	spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	spark:SetBlendMode("ADD")
	spark:SetSize(12, 16)
	bar.Spark = spark
	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	if ns.isRetail then
		text:SetPoint("LEFT", icon, "RIGHT", 2, 0)
	else
		text:SetPoint("CENTER", bar, "CENTER", 0, 0)
	end
	text:SetText(SpellName(info[3], info[4]))
	bar.Text = text
	bar.channeling = info.channel or nil
	bar.casting = not info.channel or nil
	bar.notInterruptible = info.locked or false
	bar.barType = info.locked and "uninterruptable" or (info.channel and "channel" or "standard")
	return bar
end

local TAB_NAMES = {}
for _, info in ipairs(BARS) do TAB_NAMES[info[1]] = info[2] end

-- A cast bar page: a preview, then a row per kind of bar spec.ids has
-- (Default first, spec.default), each with its These bars pick and a Look
-- panel (the Style pages' template, StylePages.lua's rows.Look): Bar, Icon,
-- Text and Border. A kind's settings are its own copy (<key>_<ID>) while
-- These bars says Their own look, else the Default row's (its panel greyed)
-- or the game's. Two pages (2026-11-16): the unit frames' (Default, yours,
-- target & focus, boss & arena: the Unit Frames icon's Cast Style tab) and
-- the nameplates' (Cast Bar Style, the Nameplates hub's), its Default the
-- unit frames' page's. spec: page, title, intro, ids, default, tabs (the
-- page's icon's tabs: ns.ShowInTabs' key), defaultName (Default's, where
-- it isn't on this page).
local function BuildCastPage(kit, spec)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L[spec.title])
	if spec.tabs then
		local tabs = ns.PageTabs(content, ns.ShowInTabs(spec.tabs), ns.ShowInIndex(spec.tabs, spec.page))
		title:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 8, -14)
	else
		title:SetPoint("TOPLEFT", 16, -16)
	end
	local intro = kit.PageIntro(content, title, spec.intro)

	-- The row shown in the preview (nil: Default): the last one whose panel
	-- was opened (to start with: the page's own row, without a Default).
	local editing = (spec.tabs == "units" and "PLAYER") or (not spec.default and spec.ids[1]) or nil
	local preview -- (below: drawn again as each setting changes)
	local panels = {} -- [id or "DEFAULT"] = its panel's sample, once made
	local function Changed()
		ns.RefreshPlateCastStyle()
		if preview then preview:Refresh() end
		for _, sample in pairs(panels) do
			if sample:IsVisible() then sample:Refresh() end
		end
	end

	local switch = kit.PageSwitch(content, "plateCastStyle", L["Enable Page"],
		L["On: the cast bars look as this page says; off: the game's own look."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "plateCastStyle")

	-- The preview: a cast, a channel and one that can't be interrupted, filling
	-- again and again, over the Style pages' scene.
	local PREVIEW_W, PREVIEW_H = 480, 150
	preview = CreateFrame("Frame", nil, content)
	preview:SetSize(PREVIEW_W, PREVIEW_H)
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	ns.StyleScene(preview, 0.6, 0.8) -- (StylePages.lua)
	local caption = kit.Label(preview, "GameFontDisableSmall", L["Preview"])
	caption:SetPoint("TOPLEFT", 6, -5)
	caption.searchSkip = true
	local samples = {}
	-- Three small plates side by side, as the game lays one out: the health
	-- bar with the unit's name in it (here what the sample shows), the cast
	-- bar under it.
	-- (Spread over the scene as plates over units, each scaled with however
	-- big the page makes the preview: in one row at one size they sat close
	-- together at its top, the rest of it empty.)
	local SPOTS = { { 0.24, 0.3 }, { 0.5, 0.58 }, { 0.76, 0.3 } }
	-- (The unit frames' page: taller samples, a mana bar too, so the middle one
	-- goes lower, clear of the other two. 2026-11-17.)
	if spec.tabs == "units" then
		SPOTS = { { 0.25, 0.27 }, { 0.5, 0.74 }, { 0.75, 0.27 } }
		PREVIEW_H = 180
		preview:SetHeight(PREVIEW_H)
	end
	local plates = {}
	local function PlaceSamples(_, width, height)
		width, height = width or PREVIEW_W, height or PREVIEW_H
		local scale = math.max(1, math.min(1.6, width / 340))
		for i, plate in ipairs(plates) do
			plate:SetScale(scale)
			plate:ClearAllPoints()
			plate:SetPoint("CENTER", preview, "TOPLEFT", width * SPOTS[i][1] / scale, -height * SPOTS[i][2] / scale)
		end
	end
	for i, info in ipairs(SAMPLES) do
		local plate = CreateFrame("Frame", nil, preview)
		plate:SetSize(SAMPLE_W, 26)
		plates[i] = plate
		local health = CreateFrame("StatusBar", nil, plate)
		health:SetSize(SAMPLE_W, 13)
		health:SetPoint("TOP", plate, "TOP", 0, 0)
		health:SetStatusBarTexture(FILLS.flat)
		health:SetStatusBarColor(0.8, 0.1, 0.1)
		health:SetMinMaxValues(0, 1)
		health:SetValue(0.85 - (i - 1) * 0.2)
		local ground = health:CreateTexture(nil, "BACKGROUND")
		ground:SetAllPoints()
		ground:SetColorTexture(0, 0, 0, 0.6)
		Lines(health, 0, 0, 0, 1)
		local name = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetPoint("LEFT", 3, 0)
		name:SetPoint("RIGHT", -3, 0)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		name:SetText(L[info[1]])
		name.searchSkip = true
		local bar = MakeSample(plate, info)
		bar:SetPoint("TOP", health, "BOTTOM", 0, -2)
		bar.offset = (i - 1) * 0.3
		samples[i] = bar
		-- (The unit frames' page: a unit frame's bars, health and mana, dressed as
		-- the Unit Frames page says, the cast bar under them: preview:Refresh.)
		if spec.tabs == "units" then
			local power = CreateFrame("StatusBar", nil, plate)
			power:SetSize(SAMPLE_W, 5)
			power:SetPoint("TOP", health, "BOTTOM", 0, -2)
			power:SetMinMaxValues(0, 1)
			power:SetValue(0.6 + (i - 1) * 0.1)
			local powerGround = power:CreateTexture(nil, "BACKGROUND")
			powerGround:SetAllPoints()
			powerGround:SetColorTexture(0, 0, 0, 0.6)
			plate:SetHeight(42)
			plate.health, plate.power, plate.ground = health, power, ground
			bar.frameBars = plate
		end
	end
	PlaceSamples(nil, PREVIEW_W, PREVIEW_H)
	preview:HookScript("OnSizeChanged", PlaceSamples)
	-- (A look with some settings in place of its own: a choice pointed at in a
	-- Look panel, never saved. General's picked: as the row's own resolves it.)
	local function LookOver(id, over)
		local look = Look(id)
		if not over then return look end
		return setmetatable({}, { __index = function(_, key)
			local value = over[key]
			if value == nil or ns.IsGeneralStyle(value) then return look[key] end
			return value
		end })
	end
	-- (A sample bar as a look says: the game's fill and colors where it has none.)
	local function Dress(bar, info, look, sized)
		if not FILLS[look.plateCastFill] then
			local kind = info.locked and "locked" or (info.channel and "channel" or "cast")
			local atlas = ns.isRetail and C_Texture and C_Texture.GetAtlasInfo
				and C_Texture.GetAtlasInfo(GAME_ATLAS[kind]) and GAME_ATLAS[kind]
			if atlas and bar.SetStatusBarTexture then
				bar:SetStatusBarTexture(atlas)
				bar:SetStatusBarColor(1, 1, 1)
			else
				bar:SetStatusBarTexture(FILLS.smooth)
				bar:SetStatusBarColor(unpack(GAME_COLORS[kind]))
			end
		end
		Apply(bar, look, true, sized)
	end
	-- (The row being looked at: the game's look for a kind not restyled.)
	-- (A sample's unit frame bars as that frame looks, and its cast bar under
	-- them: right under, in the frame's border, with the Unit frame's look.)
	local function DressFrameBars(bar, framed)
		local plate = bar.frameBars
		if not (plate and ns.UnitFrameLook) then return end
		local frameId = editing == "TARGET" and "TARGET" or "PLAYER"
		local view = ns.UnitFrameLook(frameId)
		for _, part in ipairs({ plate.health, plate.power }) do
			if not ns.SetBarTexture(part, view.ufTexture) then part:SetStatusBarTexture(FILLS.smooth) end
			ns.DressCastSkin(part, frameId)
		end
		plate.health:SetStatusBarColor(0.1, 0.8, 0.1)
		plate.power:SetStatusBarColor(0, 0.45, 1)
		plate.ground:SetShown(view.ufBorder == "game" or not ns.StyleOn("ufStyle"))
		bar:ClearAllPoints()
		if framed then
			local room = bar.Icon:IsShown() and bar.Icon:GetAlpha() > 0 and bar.Icon:GetWidth() + 3 or 0
			bar:SetPoint("TOPLEFT", plate.power, "BOTTOMLEFT", room, -PIN_GAP)
			bar:SetPoint("TOPRIGHT", plate.power, "BOTTOMRIGHT", 0, -PIN_GAP)
		else
			bar:SetWidth(SAMPLE_W)
			bar:SetPoint("TOP", plate.power, "BOTTOM", 0, -6)
		end
		ns.DressCastSkin(bar, framed and frameId or nil)
	end
	function preview:Refresh()
		local look = Look(editing)
		local framed = FrameLooked(editing, ns.GetDB())
		for i, bar in ipairs(samples) do
			Dress(bar, SAMPLES[i], look, not editing or SizedAs(editing, ns.GetDB()))
			DressFrameBars(bar, framed)
		end
	end
	local started = GetTime()
	local function Fill(bars, look)
		for _, bar in ipairs(bars) do
			local done = ((GetTime() - started) / SAMPLE_TIME + (bar.offset or 0)) % 1
			local value = bar.channeling and (1 - done) or done
			bar:SetValue(value)
			bar.value, bar.maxValue = value * SAMPLE_TIME, SAMPLE_TIME
			bar.Spark:SetPoint("CENTER", bar, "LEFT", bar:GetWidth() * value, 0)
			if look.plateCastTimer and states[bar] then UpdateTimer(bar, states[bar]) end
		end
	end
	ns.SetOnUpdate(preview, function() Fill(samples, Look(editing)) end)
	kit.AddControl(preview)

	-- (Every setting the page has, Default's and each of its kinds', for its Reset.)
	if spec.default then
		for _, key in ipairs(BAR_KEYS) do kit.RecordKey(content, key) end
	end
	for _, id in ipairs(spec.ids) do
		kit.RecordKey(content, "plateCastOwn_" .. id)
		if id ~= "PLATE" then kit.RecordKey(content, "plateCastOn_" .. id) end
		if FRAME_IDS[id] then kit.RecordKey(content, "plateCastFrame_" .. id) end
		for _, key in ipairs(BAR_KEYS) do kit.RecordKey(content, key .. "_" .. id) end
	end

	-- A row's These bars: the game's look (all but the nameplates'), the
	-- Default row's, or its own; one choice over plateCastOn_ and plateCastOwn_.
	local function LookPick(id)
		local db = ns.GetDB()
		if not (db and id) then return nil end
		if id ~= "PLATE" and not db["plateCastOn_" .. id] then return "game" end
		if FRAME_IDS[id] and db["plateCastFrame_" .. id] then return "frame" end
		return db["plateCastOwn_" .. id] and "own" or "default"
	end
	local function PickLook(id, value)
		local db = ns.GetDB()
		if id ~= "PLATE" then db["plateCastOn_" .. id] = value ~= "game" end
		if FRAME_IDS[id] then db["plateCastFrame_" .. id] = value == "frame" end
		if value == "game" then return end
		if value == "frame" then
			db["plateCastOwn_" .. id] = false
			return
		end
		-- (Their own the first time: they start from Default's settings.)
		if value == "own" and not db["plateCastStarted_" .. id] then
			for _, key in ipairs(BAR_KEYS) do db[key .. "_" .. id] = db[key] end
			db["plateCastStarted_" .. id] = true
		end
		db["plateCastOwn_" .. id] = value == "own"
	end

	-- A row's settings: Default's plain keys, a kind's own copy (<key>_<ID>).
	local fieldsOf = {}
	local function FieldOf(id)
		if not fieldsOf[id or "DEFAULT"] then
			local fields = {}
			fieldsOf[id or "DEFAULT"] = function(key)
				if type(key) ~= "string" or not OWN_KEY[key] then return key end
				if not fields[key] then
					local dbKey = id and key .. "_" .. id or key
					fields[key] = {
						get = function()
							local db = ns.GetDB()
							return db and db[dbKey]
						end,
						set = function(value) ns.GetDB()[dbKey] = value end,
					}
				end
				return fields[key]
			end
		end
		return fieldsOf[id or "DEFAULT"]
	end
	-- (A row's settings can change: Default's always, a kind's while it has its
	-- own look and is restyled.)
	local function EditableFor(id)
		return function(db)
			return ns.StyleOn("plateCastStyle", db) and (not id or (Active(id, db) and db["plateCastOwn_" .. id]))
				and true or false
		end
	end

	-- Where a row's setting comes from (the Look panel's tags).
	local function SourceOf(id)
		return function(key)
			if type(key) ~= "string" then return nil end -- (the Look from tab's own field)
			local db = ns.GetDB() or {}
			local pick = LookPick(id)
			if pick == "game" then return { text = L["The game's"] } end
			if pick == "frame" then
				return { text = FRAME_LOOK[key] and L["Unit frame's"] or L["Default row's"] }
			end
			if pick == "default" then return { text = L["Default row's"] } end
			local value = db[id and key .. "_" .. id or key]
			if ns.IsGeneralStyle and ns.IsGeneralStyle(value) then return { text = L["General's"] } end
			-- (What the main theme wrote, still as it wrote it: StyleThemes.lua's Casts().)
			if not id and ns.ThemeSetting then
				local themed = ns.ThemeSetting(key)
				local theme = ns.ActiveStyleTheme and ns.ActiveStyleTheme()
				if themed ~= nil and themed == value and theme then
					return { text = L["Set by theme: %s"]:format(L[theme.name]) }
				end
			end
			if value ~= nil and value ~= ns.DEFAULTS[key] then return { text = L["This row"], own = true } end
			return nil
		end
	end

	-- A row's Look panel, made the first time it's opened.
	local function MakePanel(id, label)
		local Editable = EditableFor(id)
		local Field = FieldOf(id)
		local function Filled(db)
			local fill = ns.StyleKeyGet(Field("plateCastFill"))
			if ns.IsGeneralStyle(fill) then fill = ns.GeneralStyleValue("plateCastFill") end
			return Editable(db) and FILLS[fill] ~= nil
		end
		local hidden = { Add = function(_, control)
			control:Hide()
			return control
		end }
		local looks = ns.StyleRows(kit, content, hidden, Changed, "plateCastStyle", Field)
		local button, pop = looks.Look("", L["Cast bars"] .. ": " .. label, {
			tabs = {
				default = function(key) return OWN_KEY[key] and ns.DEFAULTS[key] or nil end,
				source = SourceOf(id),
				copyKind = "castRow", copyName = label,
			},
			-- (Its sample: a cast as this row draws it.)
			preview = function(parent, width)
				local holder = CreateFrame("Frame", nil, parent)
				holder:SetSize(width, 70)
				ns.StyleScene(holder, 0.6, 0.85)
				local bar = MakeSample(holder, SAMPLES[1])
				bar:SetScale(1.6)
				bar:SetPoint("CENTER", holder, "CENTER", 0, 4)
				local tag = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				tag:SetPoint("TOPRIGHT", -8, -6)
				tag.searchSkip = true
				local lookNow = Look(id)
				function holder.Refresh(_, over, note)
					tag:SetShown(over ~= nil)
					tag:SetText(note or L["Preview: not saved"])
					lookNow = LookOver(id, over)
					Dress(bar, SAMPLES[1], lookNow, not id or SizedAs(id, ns.GetDB()))
				end
				ns.SetOnUpdate(holder, function() Fill({ bar }, lookNow) end)
				holder:HookScript("OnShow", function(self) self:Refresh() end)
				panels[id or "DEFAULT"] = holder
				return holder
			end,
			-- (A row's first tab: what it goes by, 2026-11-16. Not on Default's.)
			uses = id and function(look)
				local list = {}
				if id ~= "PLATE" then
					list[#list + 1] = { "game", L["The game's"], L["Cinematic leaves these cast bars alone."] }
				end
				list[#list + 1] = { "default", L["Default's"], L["They look as the Default row says."] }
				if FRAME_IDS[id] then
					list[#list + 1] = { "frame", L["Unit frame's"],
						L["Part of the unit frame: its fill, border and font, right under its bars."] }
				end
				list[#list + 1] = { "own", L["Their own"], L["These bars use their own look from the tabs here."] }
				look.Segments(L["These bars"], { get = function() return LookPick(id) end, set = function(value)
					PickLook(id, value)
					editing = id
				end }, list, FRAME_IDS[id]
					and L["How these cast bars look: the game's own, the Default row's, the unit frame's, or their own."]
					or L["How these cast bars look: the game's own, the Default row's, or their own."])
			end or nil,
			texture = { "plateCastFill", L["The bar's fill, including textures other addons share."], label = L["Fill:"], test = Editable,
				tint = { 1, 0.7, 0 } },
			barColor = function(look)
				look.Colors(L["Colors:"], {
					{ L["Casting"], COLOR_KEYS.cast, L["Pick the color of a cast."] },
					{ L["Channeling"], COLOR_KEYS.channel, L["Pick the color of a channel."] },
					{ L["Can't be interrupted"], COLOR_KEYS.locked,
						L["Pick the color of a cast or channel that can't be interrupted."] },
					{ L["Interrupted"], COLOR_KEYS.stop,
						L["Pick the color of a cast that was interrupted (when the game says: not in every fight)."] },
				}, Filled)
			end,
			ground = function(look)
				look.Slider("plateCastBack", L["Dark ground"], 0, 100, 5, "%d%%", 100,
					L["How dark it is behind the fill (with a fill of your own; the game's keeps its own)."], Filled)
				-- (Its size: the nameplates' (and Default's, for them), and yours its width.)
				if not id or id == "PLATE" then
					if not ns.isRetail then
						look.Slider("plateCastWidth", L["Width"], 50, 150, 5, "%d%%", 100,
							L["Its width, next to the game's, about its middle (nameplates only)."], Editable)
					end
					look.Slider("plateCastHeight", L["Height"], 50, 300, 10, "%d%%", 100,
						L["The cast bar's height, next to the game's."],
						Editable)
				elseif id == "PLAYER" then
					local playerSizes = look.Boxes()
					local widthTip = L["Your cast bar's width, about the point it hangs from (its height and place: " ..
						"Edit Mode's)."]
					playerSizes:Pick(L["Width"], "plateCastPlayerWidthUnit", "pct", L["Its width as a percent of the game's."],
						Editable)
					playerSizes:Box("", "plateCastPlayerWidth", 20, 200, 5, "%d", 100, widthTip,
						function(db) return Editable(db) and db.plateCastPlayerWidthUnit ~= "px" end, "%")
					playerSizes:Pick("", "plateCastPlayerWidthUnit", "px",
						L["Its width in pixels on screen: the same number on two bars, the same width."], Editable, function()
							local db = ns.GetDB()
							if (tonumber(db.plateCastPlayerWidthPx) or 0) <= 0 then
								db.plateCastPlayerWidthPx = PlayerBarPixels() or 200
							end
						end)
					playerSizes:Box("", "plateCastPlayerWidthPx", 10, 2000, 5, "%d", 1, widthTip,
						function(db) return Editable(db) and db.plateCastPlayerWidthUnit == "px" end, "px")
				end
				look.Check("plateCastSpark", L["The spark at the fill's end"], nil, Editable)
			end,
			icon = function(look)
				look.Check("plateCastIcon", L["The spell's icon"], nil, Editable)
				look.Slider("plateCastIconSize", L["Size"], 50, 300, 10, "%d%%", 100,
					L["The icon's size, next to the game's."],
					function(db) return Editable(db) and ns.StyleKeyGet(Field("plateCastIcon")) end)
				look.Check("plateCastShield", L["The shield on casts that can't be interrupted"],
					L["The game's shield over the icon while the cast can't be interrupted."], Editable)
				-- (Seen on retail's plates and game 11509's alike.)
				look.Check("plateCastImportant", L["The mark on important casts"],
					L["The game's mark on casts it counts as important, ones worth interrupting or getting out of."],
					Editable)
				look.Check("plateCastTarget", L["Who it's cast at"],
					L["The game's mark and name for who the spell is cast at."], Editable)
			end,
			font = function(look)
				look.Check("plateCastText", L["The spell's name"], nil, Editable)
				look.Font("plateCastFont", nil, Editable)
			end,
			textSize = function(look)
				look.Slider("plateCastTextSize", L["Size"], 50, 300, 10, "%d%%", 100, L["Its size, next to the game's."],
					Editable)
			end,
			outline = function(look)
				look.Choices(L["Outline:"], "plateCastOutline", {
					{ "general", L["General"], L["As the Style hub's General page says."] },
					{ "game", L["The game's"] },
					{ "none", L["None"] },
					{ "thin", L["Thin"] },
					{ "thick", L["Thick"] },
				}, Editable)
			end,
			outlineColor = false, -- (the game's text: its outline is always black)
			shadow = function(look)
				look.Choices(L["Shadow:"], "plateCastShadow", {
					{ "general", ns.SharedStyleSource("plateCastShadow"), L["As the Style hub's General page says."] },
					{ "game", L["The game's"] },
					{ "on", L["Shadow"], L["A dark copy of the letters just behind them, down and to the right."] },
					{ "none", L["None"] },
				}, Editable)
				look.Check("plateCastTimer", L["Seconds left at its right end"],
					L["Shows the seconds left at the cast bar's right end."], Editable)
			end,
			textColor = { "plateCastTextColor", L["The spell's name and seconds left in a color of your own."],
				keys = { "plateCastTextR", "plateCastTextG", "plateCastTextB" }, test = Editable },
			border = { "plateCastBorder", L["The cast bar's border: the game's or one of ours."], opts = { game = true }, test = Editable },
		})
		if button then button:Hide() end
		return pop
	end

	-- The rows: Default first (where it's this page's), then each kind of bar.
	stack:Header(content, L["Cast bars"])
	local ids = spec.default and { false } or {}
	for _, id in ipairs(spec.ids) do ids[#ids + 1] = id end
	local pops = {}
	for _, id in ipairs(ids) do
		id = id or nil
		local label = id and L[TAB_NAMES[id]] or L["Default"]
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(130, 26)
		name:SetJustifyV("MIDDLE")
		-- One button a row, as Name Style's (2026-11-16): Default's opens its
		-- look; a row's says what it goes by, The game's or Default (grey) or
		-- Own (gold), and gives a menu to pick that and to edit its own look.
		local button = ns.PanelButton(content)
		button:SetHeight(22)
		button:SetPoint("LEFT", name, "RIGHT", 4, 0)
		button.searchLabel = label
		button.pageSwitch = false
		local function OpenLook(shown)
			editing = shown
			if preview then preview:Refresh() end
			local key = shown or "DEFAULT"
			if not pops[key] then pops[key] = MakePanel(shown, shown and label or L["Default"]) end
			pops[key]:SetShown(not pops[key]:IsShown())
		end
		if id then
			kit.Tooltip(button, L["Click to pick how these cast bars look."])
			-- (Straight to its panel, 2026-11-16: its Look from tab picks the
			-- game's, Default's or its own.)
			button:SetScript("OnClick", function() OpenLook(id) end)
		else
			kit.Tooltip(button, L["Every kind of cast bar's look while its row says Default."])
			button:SetScript("OnClick", function() OpenLook(nil) end)
			-- (A line under it, as Name Style's: the rows below go by it.)
			local line = content:CreateTexture(nil, "ARTWORK")
			line:SetHeight(1)
			line:SetColorTexture(0.6, 0.5, 0.25, 0.6)
			line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
			line:SetPoint("RIGHT", button, "RIGHT", 190, 0)
		end
		function button.Refresh(self)
			local db = ns.GetDB()
			local pickNow = id and LookPick(id)
			self:SetText(not id and L["Look"] or pickNow == "game" and L["The game's"] or pickNow == "default"
				and L["Default"] or pickNow == "frame" and L["Unit frame's"] or L["Own"])
			self:SetWidth(170)
			local words = self:GetFontString()
			if words then
				if id and pickNow ~= "own" then words:SetTextColor(0.6, 0.6, 0.6) else words:SetTextColor(1, 0.82, 0) end
			end
			self:SetEnabled(rows.On(db) and true or false)
		end
		kit.AddControl(button)
	end

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, spec.page, L[spec.title])
end

-- The unit frames' cast bars (yours, your target's and focus's, the bosses'
-- and arena enemies'), with the Default row every cast bar can follow: the
-- Unit Frames icon's Cast Style tab.
function ns.CreateUnitCastStylePanel(kit)
	BuildCastPage(kit, { page = "Unit Cast Style", title = "Cast Style", tabs = "units",
		ids = { "PLAYER", "TARGET", "BOSS" }, default = true,
		intro = L["How the unit frames' cast bars look: yours, your target's and focus's, and the bosses' and arena " ..
		"enemies'. Each row's These bars picks its look: the game's (they start so), the Default row's, or its own, " ..
		"set in its Look panel. The Default row is every cast bar's base look, the nameplates' too while theirs " ..
		"says so. Changes show at once, here and on bars casting now."] })
end

-- The nameplates' cast bars: the Nameplates hub's Cast Bar Style. Their
-- Default: the unit frames' page's (above).
function ns.CreatePlateCastStylePanel(kit)
	BuildCastPage(kit, { page = "Cast Bar Style", title = "Cast Bar Style", tabs = "plates", ids = { "PLATE" },
		defaultName = L["Default's (Unit Frames)"],
		intro = L["How the nameplates' cast bars look: the Default row's (on the Unit Frames icon's Cast Style tab), " ..
		"or their own, set in their Look panel. Whether they show in CineMode: the Nameplates page's Plate parts " ..
		"grid. Changes show at once, here and on bars casting now."] })
end

-- One sample cast bar, for the General page's nameplate preview: dressed as
-- the page says (:Refresh), and filling again and again.
function ns.MakePlateCastSample(parent)
	local info = SAMPLES[1]
	local bar = MakeSample(parent, info)
	function bar:Refresh()
		local look = ns.PlateCastLook()
		if not FILLS[look.plateCastFill] then
			local atlas = ns.isRetail and C_Texture and C_Texture.GetAtlasInfo
				and C_Texture.GetAtlasInfo(GAME_ATLAS.cast) and GAME_ATLAS.cast
			if atlas and self.SetStatusBarTexture then
				self:SetStatusBarTexture(atlas)
				self:SetStatusBarColor(1, 1, 1)
			else
				self:SetStatusBarTexture(FILLS.smooth)
				self:SetStatusBarColor(unpack(GAME_COLORS.cast))
			end
		end
		Apply(self, look, true, true)
	end
	local started = GetTime()
	ns.HookOnUpdate(bar, function(self)
		local value = ((GetTime() - started) / SAMPLE_TIME) % 1
		self:SetValue(value)
		self.value, self.maxValue = value * SAMPLE_TIME, SAMPLE_TIME
		self.Spark:SetPoint("CENTER", self, "LEFT", self:GetWidth() * value, 0)
		if ns.PlateCastLook().plateCastTimer and states[self] then UpdateTimer(self, states[self]) end
	end)
	return bar
end
