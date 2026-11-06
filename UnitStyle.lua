-- The Style hub's Unit frames page: how the game's player, target, focus,
-- pet, target of target and party frames (unless the game draws the party
-- as raid frames) look: their bars' texture, border and
-- background, the health bar's and name's colors, the name's font, outline
-- and size, and the portrait (the game's, or a player's class icon). A
-- Default tab, and a tab for each frame that follows Default until its "Use
-- default settings" is unticked (as Heal Vision's role tabs do): then the
-- frame has its own copy of each setting (<key>_<FRAME>). Which parts show:
-- the UI Manager's Unit Frames page (Frames.lua).

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.ufStyle = true

-- Whether the game draws the party as raid frames (retail's Edit Mode
-- setting, the classic clients' useCompactPartyFrames): then the Party tab
-- has nothing to dress (the Raid frames page's, those).
function ns.RaidStyleParty()
	local manager = _G.EditModeManagerFrame
	if manager and manager.UseRaidStylePartyFrames then
		local ok, raid = pcall(manager.UseRaidStylePartyFrames, manager)
		if ok and type(raid) == "boolean" then return raid end
	end
	local ok, raid = pcall(GetCVarBool, "useCompactPartyFrames")
	return ok and raid == true
end

-- The party's own frames (when they aren't raid-style): the classic
-- clients' by name, retail's in PartyFrame (the raid-style ones apart).
local function PartyFrames()
	local list = {}
	if ns.RaidStyleParty() then return list end
	for i = 1, 4 do
		local frame = _G["PartyMemberFrame" .. i]
		if frame then list[#list + 1] = frame end
	end
	local holder = _G.PartyFrame
	if holder and not (holder.IsForbidden and holder:IsForbidden()) then
		for _, child in ipairs({ holder:GetChildren() }) do
			if child ~= _G.CompactPartyFrame then list[#list + 1] = child end
		end
	end
	return list
end

-- Each frame (its id, as the settings name it) and the game's frames it
-- covers (their names, or a function giving the frames themselves).
local FRAMES = {
	{ "PLAYER", "Player", { "PlayerFrame" } },
	{ "TARGET", "Target", { "TargetFrame" } },
	{ "FOCUS", "Focus", { "FocusFrame" } },
	{ "PET", "Pet", { "PetFrame" } },
	{ "TOT", "Target of target", { "TargetFrameToT", "FocusFrameToT" } },
	{ "PARTY", "Party", PartyFrames },
}

-- The game's frames an entry covers, now.
local function GameFrames(info)
	if type(info[3]) == "function" then return info[3]() end
	local list = {}
	for _, name in ipairs(info[3]) do
		if _G[name] then list[#list + 1] = _G[name] end
	end
	return list
end

-- The settings, Default's (and each frame's own, <key>_<FRAME>, starting as
-- Default's). Texture, border, font and outline start on the General page.
local KEYS = {
	ufTexture = "general",       -- the bars' fill (ns.StyleTexturePath)
	ufBorder = "general",        -- their border: "game", "none", "thin", "thick", "custom" (ns.StyleBorder)
	ufBorderSize = 1, ufBorderR = 0, ufBorderG = 0, ufBorderB = 0,
	ufBack = 0.5,                -- the dark behind them, with a border of ours
	ufHealthColor = "game",      -- the health bar: "game", "class" (class or reaction) or "custom"
	ufHealthR = 0.2, ufHealthG = 0.8, ufHealthB = 0.4,
	ufNameColor = "game",        -- the name: "game", "class" (class or reaction), "white" or "theme" (its accent)
	ufFont = "general",          -- the name's font (ns.QUEST_ITEM_FONTS' names)
	ufOutline = -1,              -- ...outline: 0 none, 1 thin, 2 thick (-1: General's)
	ufNameSize = 1,              -- ...times its usual size
	ufShadow = "general",        -- ...shadow: "game", "on" or "none" (ns.SetTextShadow; general: General's)
	ufNameCut = "game",          -- ...too long for its box: "game" (ends in "...") or "first" (FitName)
	ufPortrait = "game",         -- "game" (their face) or "class" (a player's class icon)
	ufShape = "game",            -- its shape: "game", "circle", "square", one of StyleThemes.lua's shapes or "none" (not "game": the frame art goes)
}
local SHARED = { ufTexture = { "texture", "game" }, ufFont = { "font", "game" }, ufOutline = { "outline", 0 },
	ufShadow = { "shadow", "game" }, ufBorder = { "border", "game" } }

local function Share(key, suffix)
	local entry = SHARED[key]
	if not entry then return end
	local shared = ns.SHARED_STYLE
	shared[key .. suffix] = { kind = entry[1], own = entry[2] }
	if entry[1] == "border" then
		shared[key .. "Size" .. suffix] = { kind = "borderSize", follows = key .. suffix }
		for _, channel in ipairs({ "R", "G", "B" }) do
			shared[key .. channel .. suffix] = { kind = "border" .. channel, follows = key .. suffix }
		end
	end
end

for key, value in pairs(KEYS) do DEFAULTS[key] = value end
for key in pairs(SHARED) do Share(key, "") end
for _, frame in ipairs(FRAMES) do
	local id = frame[1]
	DEFAULTS["ufOwn_" .. id] = false
	for key, value in pairs(KEYS) do DEFAULTS[key .. "_" .. id] = value end
	for key in pairs(SHARED) do Share(key, "_" .. id) end
end
-- (A border's own size and color, per frame: the shared list's border entry
-- reads <key>Size, <key>R... under the frame's suffix.)
for _, frame in ipairs(FRAMES) do
	for _, part in ipairs({ "Size", "R", "G", "B" }) do
		ns.SHARED_STYLE["ufBorder_" .. frame[1] .. part] = ns.SHARED_STYLE["ufBorder" .. part .. "_" .. frame[1]]
		DEFAULTS["ufBorder_" .. frame[1] .. part] = DEFAULTS["ufBorder" .. part .. "_" .. frame[1]]
	end
end

-- A frame's look: its own settings while its "Same as the Default tab" is
-- unticked, else Default's; each through the Style pages' look (General's,
-- and the game's with the page or General off).
local views = {}
local function View(id)
	local view = views[id]
	if not view then
		view = setmetatable({}, { __index = function(_, key)
			local look = ns.StyleLook("ufStyle")
			local db = ns.db
			if db and ns.StyleOn("ufStyle") and db["ufOwn_" .. id] then
				-- (ufBorderSize_PLAYER and the like: the border's parts by its key.)
				local own = key:match("^ufBorder(%u%l*)$")
				if own and own ~= "" then return look["ufBorder_" .. id .. own] end
				return look[key .. "_" .. id]
			end
			return look[key]
		end })
		views[id] = view
	end
	return view
end
ns.UnitStyleView = View

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- A unit's color: a player's class, else its reaction to you (nil: unknown,
-- or secret in a fight).
local function UnitColor(unit)
	if not Readable(unit) then return end
	local ok, r, g, b = pcall(function()
		if UnitIsPlayer(unit) then
			local _, class = UnitClass(unit)
			local color = Readable(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
			if color then return color.r, color.g, color.b end
		end
		local reaction = UnitReaction(unit, "player")
		local color = Readable(reaction) and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
		if color then return color.r, color.g, color.b end
	end)
	if ok and Readable(r) then return r, g, b end
end

local function HealthColor(view, unit)
	if view.ufHealthColor == "class" then
		return UnitColor(unit)
	elseif view.ufHealthColor == "custom" then
		return view.ufHealthR, view.ufHealthG, view.ufHealthB
	end
end

-- A unit's power color, for a fill of ours where the game's power bar is white
-- (retail and Forever: mana's blue, rage's red... are in the art, per power).
-- Mana's the blue of that art, not the table's darker one; unknown or secret
-- in a fight, mana's too, as anything beats a white bar.
local MANA_BLUE = { 0, 0.55, 1 }
local function PowerTint(unit)
	if not Readable(unit) then return MANA_BLUE end
	local ok, tint = pcall(function()
		local _, token, r, g, b = UnitPowerType(unit)
		if not Readable(token) or token == "MANA" then return end
		local colors = _G.PowerBarColor
		local info = colors and colors[token]
		if info and Readable(info.r) then return { info.r, info.g, info.b } end
		if Readable(r) then return { r, g, b } end
	end)
	return ok and tint or MANA_BLUE
end

-- What we've changed, to put back: bar -> its own fill and color; skins.
local own = setmetatable({}, { __mode = "k" })
local skins = setmetatable({}, { __mode = "k" })
local dressing = false -- (our own setters: not the game's, for the hooks)

local function OwnOf(object)
	local saved = own[object]
	if not saved then
		saved = {}
		if object.GetStatusBarTexture then
			local fill = object:GetStatusBarTexture()
			saved.atlas = fill and fill.GetAtlas and fill:GetAtlas()
			saved.file = fill and fill:GetTexture()
			local ok, r, g, b = pcall(object.GetStatusBarColor, object)
			if ok and Readable(r) then saved.color = { r, g, b } end
		elseif object.GetFontObject then
			saved.object = object:GetFontObject()
			local r, g, b = object:GetTextColor()
			if Readable(r) then saved.color = { r, g, b } end
		end
		own[object] = saved
	end
	return saved
end

-- Dirt on a texture: its own patch of the art, kept for good, the art's own size
-- (not stretched), turned or not. The same patch on every bar read as a pattern.
local gritSpots = setmetatable({}, { __mode = "k" })
local GRIT_W, GRIT_H = 340, 85
local function ScatterGrit(texture, wide, tall)
	if not (Readable(wide) and Readable(tall) and wide > 0 and tall > 0) then return end
	local spot = gritSpots[texture]
	if not spot then
		spot = { math.random(), math.random(), math.random() < 0.5, math.random() < 0.5 }
		gritSpots[texture] = spot
	end
	local across, down = math.min(1, wide / GRIT_W), math.min(1, tall / GRIT_H)
	local left, top = spot[1] * (1 - across), spot[2] * (1 - down)
	local right, bottom = left + across, top + down
	if spot[3] then left, right = right, left end
	if spot[4] then top, bottom = bottom, top end
	texture:SetTexCoord(left, right, top, bottom)
end

-- Our border and background behind a bar (for any border but the game's).
local function Skin(bar)
	local skin = skins[bar]
	if not skin then
		skin = CreateFrame("Frame", nil, bar)
		skin:SetAllPoints()
		skin:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
		skin.back = skin:CreateTexture(nil, "BACKGROUND", nil, -8)
		skin.back:SetAllPoints()
		skin.back:SetColorTexture(0, 0, 0, 1)
		skin.border = ns.MakeStyleEdges(skin)
		-- (The fine work the game's own bars have: light along the top, shade along the
		-- bottom, so a flat fill reads as set into its frame.)
		skin.shine = bar:CreateTexture(nil, "OVERLAY")
		skin.shine:SetPoint("TOPLEFT", 0, -1)
		skin.shine:SetPoint("TOPRIGHT", 0, -1)
		skin.shine:SetHeight(1)
		skin.shine:SetColorTexture(1, 1, 1, 0.1)
		skin.dark = bar:CreateTexture(nil, "OVERLAY", nil, 1)
		skin.dark:SetPoint("TOPLEFT")
		skin.dark:SetPoint("TOPRIGHT")
		skin.dark:SetHeight(1)
		skin.dark:SetColorTexture(0, 0, 0, 0.5)
		skin.shade = bar:CreateTexture(nil, "OVERLAY")
		skin.shade:SetPoint("BOTTOMLEFT")
		skin.shade:SetPoint("BOTTOMRIGHT")
		skin.shade:SetHeight(2)
		skin.shade:SetColorTexture(0, 0, 0, 0.38)
		skin.grit = bar:CreateTexture(nil, "OVERLAY", nil, -1)
		skin.grit:SetAllPoints()
		skin.grit:SetTexture(ns.THEME_GRIT)
		skin.grit:SetAlpha(0.3)
		skin.sheen = bar:CreateTexture(nil, "OVERLAY", nil, -2)
		skin.sheen:SetAllPoints()
		skin.sheen:SetTexture(ns.THEME_SHEEN)
		skin.depth = bar:CreateTexture(nil, "OVERLAY", nil, -3)
		skins[bar] = skin
	end
	return skin
end

local BAR_GAP = 1 -- (between a bar and the one above it, their lines shared: FitBars)
local function DressSkin(skin, view, under)
	local kind, size, r, g, b = ns.StyleBorder(view, "ufBorder")
	skin:SetShown(kind ~= "game")
	skin.back:SetAlpha(tonumber(view.ufBack) or 0.5)
	-- (A bar under another as wide as it: the frame under the target's mana is wider
	-- than what shows of it, hidden by the game's art when that's up.)
	if under and skin.under ~= under then
		skin.under = under
		skin:ClearAllPoints()
		skin:SetPoint("TOP", skin:GetParent(), "TOP")
		skin:SetPoint("BOTTOM", skin:GetParent(), "BOTTOM")
		skin:SetPoint("LEFT", under, "LEFT")
		skin:SetPoint("RIGHT", under, "RIGHT")
	end
	-- (A cell of a shaped frame: square, in a line of its own, with the fine work. The
	-- style theme's bar shape is for bars that stand alone: a straight border can't follow it.)
	local cell = not view.isTile and view.ufShape and view.ufShape ~= "game" and ns.ThemeLayout() ~= "slab"
	skin.shine:SetShown(cell and true or false)
	skin.shade:SetShown(cell and true or false)
	-- (A slab: no line or dirt to carry it, so it's light that stops it being one flat
	-- block of color, and a touch of grain.)
	local slab = not view.isTile and ns.ThemeLayout() == "slab"
	-- (Not on a thin bar: the shading would be all there is of it, and dim it to nothing.)
	local barTall = skin:GetParent():GetHeight()
	local thin = Readable(barTall) and barTall < 8
	skin.sheen:SetShown((slab or cell) and not thin and true or false)
	skin.sheen:SetAlpha(slab and 1 or 0.7)
	-- (What's empty in the theme's own dark, not black: an empty bar's still part of it.)
	local ring = (slab or cell) and ns.ThemeRing()
	if ring then
		skin.back:SetColorTexture(ring[1] * 0.2, ring[2] * 0.2, ring[3] * 0.2, 1)
	else
		skin.back:SetColorTexture(0, 0, 0, 1)
	end
	-- (Fading in toward the bar's leading edge: the fill's own width, so it moves with it.)
	local fill = skin:GetParent():GetStatusBarTexture()
	local depth = (slab or cell) and fill and not thin and ns.ThemeBarDepth()
	skin.depth:SetShown(depth and true or false)
	if depth then
		skin.depth:ClearAllPoints()
		skin.depth:SetAllPoints(fill)
		ns.ThemeGradient(skin.depth, depth[1], depth[2], depth[3], depth[4], 0)
	end
	skin.shine:SetShown((cell or slab) and true or false)
	skin.grit:SetShown((cell or slab) and not thin and true or false)
	skin.grit:SetAlpha(slab and 0.14 or 0.18)
	skin.dark:SetShown(cell and true or false)
	if thin then
		skin.shade:SetHeight(1)
		skin.dark:Hide()
	else
		skin.shade:SetHeight(2)
	end
	ScatterGrit(skin.grit, skin:GetParent():GetWidth(), skin:GetParent():GetHeight())
	local shaped = ns.DressBarShape(skin:GetParent(), skin.back, view.isTile or cell, skin)
	skin.border:SetShown(kind == "line" and not shaped)
	if kind == "line" and not shaped then
		ns.DressStyleEdges(skin.border, size, r, g, b, 1, true)
		-- (A bar right under another: the one above's bottom line is its top, two would pile up.)
		skin.border.lines[1]:SetShown(not under)
	end
end

-- A bar's fill as view says (view nil: the game's); color: its color, or
-- nil for the game's. tint: a color for our fill where the game's is white
-- (retail's health bar: its green is in the art, which ours doesn't have).
local function DressBar(bar, view, r, g, b, tint, under)
	if not (bar and bar.SetStatusBarTexture) or (bar.IsForbidden and bar:IsForbidden()) then return end
	local saved = OwnOf(bar)
	dressing = true
	if view and ns.SetBarTexture(bar, view.ufTexture) then
		saved.ours = true
		local c = saved.color
		if not r and tint and (not c or (c[1] > 0.95 and c[2] > 0.95 and c[3] > 0.95)) then
			r, g, b = tint[1], tint[2], tint[3]
		end
	elseif saved.ours then
		saved.ours = nil
		local fill = saved.atlas or saved.file
		if fill then bar:SetStatusBarTexture(fill) end
		local now = bar:GetStatusBarTexture()
		if now and now.SetDesaturated then now:SetDesaturated(false) end
	end
	if r then
		local fill = bar:GetStatusBarTexture()
		if fill and fill.SetDesaturated then fill:SetDesaturated(true) end -- (a colored fill of the game's tints clean)
		bar:SetStatusBarColor(r, g, b)
		saved.colored = true
	elseif saved.colored then
		saved.colored = nil
		if saved.color then bar:SetStatusBarColor(unpack(saved.color)) end
		if not saved.ours then
			local fill = bar:GetStatusBarTexture()
			if fill and fill.SetDesaturated then fill:SetDesaturated(false) end
		end
	end
	if view and view.ufBorder ~= "game" or skins[bar] then
		local skin = Skin(bar)
		if view then
			DressSkin(skin, view, under)
		else
			ns.DressBarShape(bar, skin.back, true)
			skin:Hide()
		end
	end
	dressing = false
end

-- The name as view says: its color, font, outline and size.
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]
local function DressName(text, view, unit)
	if not (text and text.SetTextColor) or (text.IsForbidden and text:IsForbidden()) then return end
	local saved = OwnOf(text)
	local color = view and view.ufNameColor
	local r, g, b
	if color == "class" then
		r, g, b = UnitColor(unit)
	elseif color == "white" then
		r, g, b = 1, 1, 1
	elseif color == "theme" then
		local accent = ns.ThemeAccent()
		if accent then r, g, b = accent[1], accent[2], accent[3] end
	end
	if r then
		text:SetTextColor(r, g, b)
		saved.colored = true
	elseif saved.colored and saved.color then
		text:SetTextColor(unpack(saved.color))
		saved.colored = nil
	end
	local font = view and view.ufFont or "game"
	local outline = view and tonumber(view.ufOutline) or 0
	local size = view and tonumber(view.ufNameSize) or 1
	if font == "game" and outline <= 0 and size == 1 then
		if saved.fonted and saved.object then
			text:SetFontObject(saved.object)
			pcall(function() text:SetText(text:GetText()) end)
			saved.fonted = nil
		end
		ns.SetTextShadow(text, view and view.ufShadow)
		return
	end
	local object = saved.object
	if not object then return end
	local file, height, flags = object:GetFont()
	if not (file and height) then return end
	if ROMAN then
		file = ns.StyleFontFile(font) or file
	end
	if outline >= 0 and ns.OutlinedFlags then flags = ns.OutlinedFlags(flags, outline) end
	if ns.SetPlateNameFont then
		ns.SetPlateNameFont(text, object, file, height, size, flags or "")
	else
		pcall(text.SetFont, text, file, height * size, flags or "")
	end
	saved.fonted = true
	ns.SetTextShadow(text, view and view.ufShadow)
end

-- A name too long for its box, on "First name": the game ends it in "...", so it
-- loses its last words instead (Benediction Cumberbatch: Benediction), and a
-- single word too long loses letters. The game writes the name again as the unit
-- changes: ours after it. A secret name can't be read or measured: the game's.
local fitting = false
local function TooWide(text, room)
	local wide = text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth()
	return Readable(wide) and wide > room + 0.5
end

local function Fit(text, saved, again)
	local full = saved.full
	if not full or (not saved.cut and not saved.shown) then return end
	if not saved.cut then
		text:SetText(full)
		saved.shown, saved.fitFull = nil, nil
		return
	end
	local room = text:GetWidth()
	if not Readable(room) or room < 1 then return end
	local file, height = text:GetFont()
	if not again and saved.fitFull == full and saved.fitRoom == room and saved.fitFile == file
		and saved.fitHeight == height then return end
	saved.fitFull, saved.fitRoom, saved.fitFile, saved.fitHeight = full, room, file, height
	text:SetText(full)
	saved.shown = nil
	if not TooWide(text, room) then return end
	local shown = full
	repeat
		local shorter = shown:match("^(.*%S)%s+%S+$")
		if not shorter then break end
		shown = shorter
		text:SetText(shown)
	until not TooWide(text, room)
	while TooWide(text, room) and #shown > 1 do
		-- (One letter off the end, all its bytes.)
		local shorter = shown:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
		if shorter == "" then break end
		shown = shorter
		text:SetText(shown)
	end
	saved.shown = shown
end

local function Refit(text, saved, again)
	fitting = true
	pcall(Fit, text, saved, again)
	fitting = false
end

local function FitName(text, view)
	if not (text and text.SetText) or (text.IsForbidden and text:IsForbidden()) then return end
	local saved = OwnOf(text)
	saved.cut = view and view.ufNameCut == "first" or false
	if saved.cut and not saved.fitHooked then
		saved.fitHooked = true
		local ok, name = pcall(text.GetText, text)
		saved.full = ok and Readable(name) and type(name) == "string" and name or nil
		hooksecurefunc(text, "SetText", function(_, written)
			if fitting then return end
			if not (Readable(written) and type(written) == "string") then
				saved.full, saved.shown = nil, nil
				return
			end
			-- (Our own cut, set again as the font changes, isn't a new name.)
			if written ~= saved.shown then saved.full, saved.shown = written, nil end
			Refit(text, saved, true)
		end)
	end
	Refit(text, saved)
end

-- The numbers on a bar: the frames' font, and never taller than the bar (the
-- game's fit its own art, which ours doesn't have round them). Left alone in
-- languages our fonts don't cover.
local BAR_WORDS = { "LeftText", "RightText", "TextString", "HealthBarText", "ManaBarText" }
local function DressBarText(bar, view)
	if not (bar and ROMAN) or (bar.IsForbidden and bar:IsForbidden()) then return end
	local height = bar:GetHeight()
	for _, key in ipairs(BAR_WORDS) do
		local text = bar[key]
		if text and text.SetFont and not (text.IsForbidden and text:IsForbidden()) then
			local saved = OwnOf(text)
			local object = saved.object
			local file, size, flags
			if object then file, size, flags = object:GetFont() end
			if view and file and size and Readable(height) and height > 4 then
				local font = ns.StyleFontFile(view.ufFont) or file
				pcall(text.SetFont, text, font, math.min(size, math.max(7, height - 1)), flags or "")
				saved.fitted = true
			elseif saved.fitted and object then
				saved.fitted = nil
				text:SetFontObject(object)
				pcall(function() text:SetText(text:GetText()) end)
			end
		end
	end
end

-- (For the Raid frames page, RaidStyle.lua: its own look read as these keys.)
ns.UnitStyleDressBar, ns.UnitStyleDressName, ns.UnitStyleColor = DressBar, DressName, UnitColor

-- The portrait: a player's class icon, or their face (the game's).
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local function DressPortrait(portrait, view, unit)
	if not (portrait and portrait.SetTexture) or (portrait.IsForbidden and portrait:IsForbidden()) then return end
	local want = view and view.ufPortrait == "class"
	local class
	if want and Readable(unit) then
		local ok, isPlayer = pcall(UnitIsPlayer, unit)
		if ok and Readable(isPlayer) and isPlayer then
			local _, file = UnitClass(unit)
			class = Readable(file) and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[file] and file
		end
	end
	local saved = OwnOf(portrait)
	if class then
		portrait:SetTexture(CLASS_ICONS)
		portrait:SetTexCoord(unpack(_G.CLASS_ICON_TCOORDS[class]))
		saved.iconed = true
	elseif saved.iconed then
		saved.iconed = nil
		portrait:SetTexCoord(0, 1, 0, 1)
		if Readable(unit) and SetPortraitTexture then pcall(SetPortraitTexture, portrait, unit) end
	end
end

-- The parts of one of the game's frames.
local function Parts(frame)
	return frame.healthbar or frame.HealthBar, frame.manabar or frame.ManaBar, frame.name or frame.Name,
		frame.portrait or frame.Portrait
end

-- The game's frame art, in the style theme's ornament color: one texture draws
-- the portrait ring and the name box (the names as Frames.lua's Art lists them).
-- Nothing's touched with no theme, and what was tinted goes back.
local tinted = setmetatable({}, { __mode = "k" })
local function FrameArt(frame)
	local list = {}
	local name = frame.GetName and frame:GetName()
	local holder = frame.PlayerFrameContainer or frame.TargetFrameContainer
	for _, art in ipairs({ holder and holder.FrameTexture or false, holder and holder.AlternatePowerFrameTexture or false,
		holder and holder.VehicleFrameTexture or false, holder and holder.BossPortraitFrameTexture or false,
		frame.FrameTexture or false, name and _G[name .. "Texture"] or false,
		name and _G[name .. "TextureFrameTexture"] or false }) do
		if art and art.SetVertexColor and art.SetDesaturated then list[#list + 1] = art end
	end
	return list
end

local function DressFrameArt(frame, active)
	local color = active and ns.ThemeRing()
	for _, art in ipairs(FrameArt(frame)) do
		if not (art.IsForbidden and art:IsForbidden()) and (color or tinted[art]) then
			-- (Its alpha as it is: left out, it'd be set to 1, undoing a frame's fade.)
			local _, _, _, alpha = art:GetVertexColor()
			if not Readable(alpha) then alpha = nil end
			art:SetDesaturated(color and true or false)
			art:SetVertexColor(color and color[1] or 1, color and color[2] or 1, color and color[3] or 1, alpha)
			tinted[art] = color and true or nil
		end
	end
end

-- The portrait's shape. The game's ring is in the frame art, so any other shape
-- hides that art and draws its own: a thin ring, or a square with the round
-- mask off. None hides the portrait too, leaving just the bars. Everything
-- goes back on the game's shape; nothing's touched until one's picked.
local RING = "Interface\\AddOns\\" .. (...) .. "\\Textures\\ActionRing2"
local shapes = setmetatable({}, { __mode = "k" }) -- frame -> what's ours on it
local kept = setmetatable({}, { __mode = "k" }) -- texture -> true, while we hold it clear
local keeping = false
local function KeepClear(texture)
	if keeping or not kept[texture] then return end
	keeping = true
	texture:SetAlpha(0)
	keeping = false
end
local keepHooked = setmetatable({}, { __mode = "k" })
local function SetClear(texture, clear)
	if not texture or not texture.SetAlpha then return end
	if clear and not keepHooked[texture] then
		keepHooked[texture] = true
		hooksecurefunc(texture, "SetAlpha", KeepClear)
		-- (A texture's color carries its alpha: the aggro glow and the fight's red flash
		-- came back through these, as streaks of red, with the rest of the art gone.)
		if texture.SetVertexColor then hooksecurefunc(texture, "SetVertexColor", KeepClear) end
		if texture.SetAlphaFromBoolean then hooksecurefunc(texture, "SetAlphaFromBoolean", KeepClear) end
		if texture.Show then hooksecurefunc(texture, "Show", KeepClear) end
		if texture.SetShown then hooksecurefunc(texture, "SetShown", KeepClear) end
	end
	if clear == (kept[texture] or false) then return end
	kept[texture] = clear or nil
	texture:SetAlpha(clear and 0 or 1)
end

local function PortraitMask(frame)
	local holder = frame.PlayerFrameContainer or frame.TargetFrameContainer
	return holder and (holder.PlayerPortraitMask or holder.PortraitMask) or frame.PortraitMask
end

-- (Art that goes with the frame art: the rest glow and the combat flash follow its ring.)
local function ArtExtras(frame)
	local list = {}
	local holder = frame.PlayerFrameContainer or frame.TargetFrameContainer
	if holder and holder.FrameFlash then list[#list + 1] = holder.FrameFlash end
	if holder and holder.Flash then list[#list + 1] = holder.Flash end
	local content = frame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	if main and main.StatusTexture then list[#list + 1] = main.StatusTexture end
	-- (The gold corner the game's frame art has by the portrait.)
	local contextual = content and content.PlayerFrameContentContextual
	if contextual and contextual.PlayerPortraitCornerIcon then list[#list + 1] = contextual.PlayerPortraitCornerIcon end
	-- (Classic's dark block behind the bars, which the frame art covers.)
	local name = frame.GetName and frame:GetName()
	local back = name and _G[name .. "Background"]
	if back then list[#list + 1] = back end
	-- (And everything the Unit Frames page knows as frame art: the threat glow among it.)
	for _, art in ipairs(ns.UnitPartRegions and ns.UnitPartRegions(frame, "Art") or {}) do list[#list + 1] = art end
	return list
end

-- The level over a shape's ring: on the classic clients it's a badge on the
-- portrait's corner, and the ring would cut through it. Out of fights, as the
-- ring is made. (Its regions change parent, not place.)
local function LiftLevel(frame, state, lift)
	if InCombatLockdown() then return end
	if lift and not state.lifted then
		if not state.badge then
			state.badge = CreateFrame("Frame", nil, frame)
			state.badge:SetAllPoints(frame)
			state.badge:SetFrameLevel(frame:GetFrameLevel() + 7)
		end
		state.lifted = {}
		for _, region in ipairs(ns.UnitPartRegions and ns.UnitPartRegions(frame, "Level") or {}) do
			if region.SetParent then
				state.lifted[region] = region:GetParent()
				pcall(region.SetParent, region, state.badge)
			end
		end
	elseif state.lifted and not lift then
		for region, parent in pairs(state.lifted) do pcall(region.SetParent, region, parent) end
		state.lifted = nil
	end
end

-- The name's own strip, over the bars, as the game's frame has: with the bars each in
-- their own thin line right under it, nothing of a background shows round them.
-- on: a theme with a panel, and a shape of ours.
local function DressPlateLook(plate, on)
	local back, edge = ns.ThemePanel()
	plate:SetShown(on and back ~= nil)
	if not (on and back) then return end
	plate.back:SetColorTexture(back[1], back[2], back[3], 1)
	ScatterGrit(plate.grit, plate:GetWidth(), plate:GetHeight())
	-- (Light from the middle out, so the strip isn't one flat tone.)
	local glow = ns.ThemeRing() or edge
	ns.ThemeGradient(plate.left, glow[1], glow[2], glow[3], 0, 0.14)
	ns.ThemeGradient(plate.right, glow[1], glow[2], glow[3], 0.14, 0)
	plate.edges:Show()
	ns.DressStyleEdges(plate.edges, 1, edge[1], edge[2], edge[3], 1, false)
end

local function MakePlate(parent)
	local plate = CreateFrame("Frame", nil, parent)
	plate.themeSliceCorner = 10
	plate.back = plate:CreateTexture(nil, "BACKGROUND", nil, -7)
	plate.back:SetAllPoints()
	plate.grit = plate:CreateTexture(nil, "BACKGROUND", nil, -6)
	plate.grit:SetAllPoints()
	plate.grit:SetTexture(ns.THEME_GRIT)
	plate.grit:SetAlpha(0.45)
	plate.left = plate:CreateTexture(nil, "BACKGROUND", nil, -5)
	plate.left:SetPoint("TOPLEFT")
	plate.left:SetPoint("BOTTOMRIGHT", plate, "BOTTOM")
	plate.right = plate:CreateTexture(nil, "BACKGROUND", nil, -5)
	plate.right:SetPoint("TOPRIGHT")
	plate.right:SetPoint("BOTTOMLEFT", plate, "BOTTOM")
	plate.edges = ns.MakeStyleEdges(plate)
	return plate
end

-- Its place: on top of the health bar, as wide as its line.
local NAME_ROW, NAME_ROW_SMALL = 16, 13
local function PlacePlate(plate, health)
	local tall = health:GetHeight()
	plate:ClearAllPoints()
	plate:SetPoint("BOTTOMLEFT", health, "TOPLEFT", -1, 1)
	plate:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 1, 1)
	plate:SetHeight(Readable(tall) and tall < 9 and NAME_ROW_SMALL or NAME_ROW)
end

-- A slab (ns.ThemeLayout): the name on the health bar and the value at its right.
-- Only on a bar tall enough to hold a name: the small frames keep theirs above.
local SLAB_HEIGHT = 12
local function SlabOn(health)
	if not (health and ns.StyleOn("ufStyle") and ns.ThemeLayout() == "slab") then return false end
	local tall = health:GetHeight()
	return Readable(tall) and tall >= SLAB_HEIGHT
end

-- The bridge from the portrait to the rows, as the game's frame has: a short, narrow
-- piece of the ring's own metal off the health bar's end, running in under the ring.
-- All textures of its own frame, so the picture covers it: lines on a frame above
-- crossed the face.
local function PlaceBridge(bridge, plate, health, bottom, flip, shape)
	local near, far = flip and "RIGHT" or "LEFT", flip and "LEFT" or "RIGHT"
	local tall = health:GetHeight()
	local inset = Readable(tall) and tall < 9 and 2 or 6
	-- (Short of the rows at both ends, and of the lines between them, so it doesn't read
	-- as more of them. Its art has a margin for its shadow, so it's a little bigger.)
	bridge:ClearAllPoints()
	bridge:SetPoint("TOP" .. far, plate, "TOP" .. near, flip and -1 or 1, -inset + 2)
	bridge:SetPoint("BOTTOM" .. far, bottom or health, "BOTTOM" .. near, flip and -1 or 1, inset - 2)
	bridge:SetWidth(ns.ThemeBridgeReach(shape))
	bridge.art:SetTexCoord(flip and 1 or 0, flip and 0 or 1, 0, 1) -- (its worked edge to the rows)
end

local function DressBridge(bridge, on)
	local color = ns.ThemeRing()
	bridge:SetShown(on and color ~= nil)
	if not (on and color) then return end
	bridge.art:SetVertexColor(color[1], color[2], color[3], 1)
end

local function MakeBridge(parent)
	local bridge = CreateFrame("Frame", nil, parent)
	bridge.art = bridge:CreateTexture(nil, "BACKGROUND", nil, -7)
	bridge.art:SetAllPoints()
	bridge.art:SetTexture(ns.THEME_COLLAR)
	ns.ThemeNoSnap(bridge.art)
	return bridge
end

-- A soft dark edge behind all the rows, which lifts them off the world.
local function MakeRowShadow(parent)
	local shadow = CreateFrame("Frame", nil, parent)
	shadow.art = shadow:CreateTexture(nil, "BACKGROUND", nil, -8)
	shadow.art:SetAllPoints()
	shadow.art:SetTexture(ns.THEME_ROW_SHADOW)
	return shadow
end
local function PlaceRowShadow(shadow, plate, bottom)
	shadow:ClearAllPoints()
	shadow:SetPoint("TOPLEFT", plate, "TOPLEFT", -9, 9)
	shadow:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 9, -9)
end

local function FramePlate(frame, state, portrait, on, over, shape)
	-- (A slab theme's whole point is nothing round its bars.)
	if not (on and not over) or ns.ThemeLayout() == "slab" then
		if state.plate then state.plate:Hide() end
		if state.bridge then state.bridge:Hide() end
		if state.shadow then state.shadow:Hide() end
		return
	end
	local health, power = Parts(frame)
	if not health then return end
	if not InCombatLockdown() then
		if not state.plate then
			state.plate = MakePlate(frame)
			state.plate:SetFrameLevel(frame:GetFrameLevel()) -- (under the name)
		end
		local portraitX, healthX = portrait:GetCenter(), health:GetCenter()
		state.flip = Readable(portraitX) and Readable(healthX) and portraitX > healthX
		PlacePlate(state.plate, health)
		if not state.bridge then
			state.bridge = MakeBridge(frame)
			state.bridge:SetFrameLevel(frame:GetFrameLevel())
		end
		local shown = power and ns.Flag(power:IsShown()) and power or health
		-- (Your second power, drawn under the first: the rows end there.)
		local extra = frame == _G.PlayerFrame and _G.AlternatePowerBar
		if extra and ns.Flag(extra:IsShown()) then shown = extra end
		PlaceBridge(state.bridge, state.plate, health, shown, state.flip, shape)
		if not state.shadow then
			state.shadow = MakeRowShadow(frame)
			state.shadow:SetFrameLevel(frame:GetFrameLevel())
		end
		PlaceRowShadow(state.shadow, state.plate, shown)
		state.shadow:Show()
	end
	if state.plate then DressPlateLook(state.plate, true) end
	if state.bridge then DressBridge(state.bridge, true) end
end

-- What a game region was before any of ours moved it, kept from the first touch.
-- Every look that moves it goes back to these, not to what it found: so it doesn't
-- matter which theme follows which, or what the last one left behind.
local firstSpots, firstSizes, firstFonts = {}, {}, {}
setmetatable(firstSpots, { __mode = "k" })
setmetatable(firstSizes, { __mode = "k" })
setmetatable(firstFonts, { __mode = "k" })
local function SpotsOf(region)
	if firstSpots[region] then return firstSpots[region] end
	local spots = {}
	for i = 1, tonumber(region:GetNumPoints()) or 0 do spots[i] = { region:GetPoint(i) } end
	firstSpots[region] = spots
	return spots
end
local function FirstSize(region)
	if not firstSizes[region] then firstSizes[region] = { region:GetSize() } end
	return firstSizes[region][1], firstSizes[region][2]
end
local function FirstFont(region)
	if not firstFonts[region] then firstFonts[region] = { region:GetFont() } end
	local font = firstFonts[region]
	return font[1], font[2], font[3]
end
local function PutBack(region, spots)
	region:ClearAllPoints()
	-- (By number: a point on no frame has nil in the middle, which unpack stops at. Each
	-- on its own, and said if it's refused: one bad spot took the whole frame's look with it.)
	for _, spot in ipairs(spots) do
		local ok, err = pcall(region.SetPoint, region, spot[1], spot[2], spot[3], spot[4], spot[5])
		if not ok then
			ns.Log("style", ("put back refused: %s; %s %s %s %s %s; %s"):format(tostring(region.GetDebugName and region:GetDebugName()),
				tostring(spot[1]), tostring(spot[2]), tostring(spot[3]), tostring(spot[4]), tostring(spot[5]), tostring(err)))
			pcall(region.SetPoint, region, spot[1] or "CENTER", spot[2] or region:GetParent(), spot[3] or spot[1] or "CENTER", 0, 0)
		end
	end
end

-- With no portrait the level's badge has nothing to sit on: it goes on the plate's
-- end. Only where there's a badge (retail's level is text, already by the name).
local function PlaceBadge(frame, state, on)
	if InCombatLockdown() then return end
	if on and not state.badgeSpots and state.plate and ns.UnitPartRegions
		and #ns.UnitPartRegions(frame, "LevelBack") > 0 then
		state.badgeSpots = {}
		for _, region in ipairs(ns.UnitPartRegions(frame, "Level")) do
			state.badgeSpots[region] = SpotsOf(region)
			region:ClearAllPoints()
			region:SetPoint("CENTER", state.plate, state.flip and "RIGHT" or "LEFT", state.flip and 8 or -8, 0)
		end
	elseif not on and state.badgeSpots then
		for region, spots in pairs(state.badgeSpots) do PutBack(region, spots) end
		state.badgeSpots = nil
	end
end

-- A slab's bars at a slab's size: one tall bar, across where the portrait was with
-- none showing, and thin power under it. The game's own bars, so out of fights only,
-- on their frame's own spot, and put back as they were when the theme changes.
local SLAB_TALL, SLAB_POWER = 26, 5
local function SlabSpot(frame, health, portrait, bare)
	local frameLeft, frameTop = frame:GetLeft(), frame:GetTop()
	local left, right, top = health:GetLeft(), health:GetRight(), health:GetTop()
	if not (Readable(frameLeft) and Readable(frameTop) and Readable(left) and Readable(right) and Readable(top)) then
		return nil
	end
	local portraitLeft, portraitRight = portrait and portrait:GetLeft(), portrait and portrait:GetRight()
	if bare and Readable(portraitLeft) and Readable(portraitRight) then
		left, right = math.min(left, portraitLeft), math.max(right, portraitRight)
	end
	return { x = left - frameLeft, y = top - frameTop, wide = right - left }
end

-- (The game's masks on a bar's fill stay the size they were: left on a bigger bar,
-- they cut the fill back to its old size.)
local function StripMasks(state, bar)
	local fill = bar:GetStatusBarTexture()
	if not (fill and fill.GetNumMaskTextures) then return end
	state.masks = state.masks or {}
	if state.masks[fill] then return end
	local list = {}
	local count = fill:GetNumMaskTextures()
	for i = (Readable(count) and count or 0), 1, -1 do
		local mask = fill:GetMaskTexture(i)
		if mask then
			list[#list + 1] = mask
			fill:RemoveMaskTexture(mask)
		end
	end
	state.masks[fill] = list
end

local function SizeSlab(frame, state, bars, portrait, bare)
	local health = bars[1]
	for _, bar in ipairs(bars) do StripMasks(state, bar) end
	if not state.spot then
		state.spot = SlabSpot(frame, health, portrait, bare)
		if not state.spot then return end
		state.bars = {}
		for _, bar in ipairs(bars) do
			local wide, tall = FirstSize(bar)
			state.bars[bar] = { spots = SpotsOf(bar), wide = wide, tall = tall }
		end
	end
	local spot = state.spot
	health:ClearAllPoints()
	health:SetPoint("TOPLEFT", frame, "TOPLEFT", spot.x, spot.y)
	health:SetSize(spot.wide, SLAB_TALL)
	local above = health
	for i = 2, #bars do
		local bar = bars[i]
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)
		bar:SetSize(spot.wide, SLAB_POWER)
		above = bar
		-- (Numbers don't fit on a line this thin.)
		SetClear(bar.LeftText, true)
		SetClear(bar.RightText, true)
		SetClear(bar.TextString, true)
	end
end

local function UnsizeSlab(state)
	for fill, list in pairs(state.masks or {}) do
		for _, mask in ipairs(list) do fill:AddMaskTexture(mask) end
	end
	for bar, was in pairs(state.bars or {}) do
		PutBack(bar, was.spots)
		if Readable(was.wide) and Readable(was.tall) then bar:SetSize(was.wide, was.tall) end
		SetClear(bar.LeftText, false)
		SetClear(bar.RightText, false)
		SetClear(bar.TextString, false)
	end
end

-- With a shape of ours the bars reach to the portrait: the game's stop short of where
-- its frame art used to be. Same heights and gaps, just wider. As a slab's, out of
-- fights and put back after. on nil: only take it off.
local fits = setmetatable({}, { __mode = "k" })
local BRIDGE = 1.5 -- (between the ring and the rows: what shows of the bridge)
local RING_IN = 2 -- (the ring's inside the portrait's place by this: RING_INSET)
local function FitBars(frame, bars, portrait, shape, on, name)
	if InCombatLockdown() then return end
	local state = fits[frame]
	if not on then
		if state then
			fits[frame] = nil
			for bar, was in pairs(state.bars) do
				PutBack(bar, was.spots)
				if Readable(was.wide) then bar:SetWidth(was.wide) end
			end
			for fill, list in pairs(state.masks or {}) do
				for _, mask in ipairs(list) do fill:AddMaskTexture(mask) end
			end
			if state.name then
				PutBack(state.name, SpotsOf(state.name))
				state.name:SetJustifyH(state.justify or "LEFT")
			end
			for level in pairs(state.levels or {}) do PutBack(level, SpotsOf(level)) end
		end
		return
	end
	local health = bars[1]
	if not state then
		local frameLeft, frameTop = frame:GetLeft(), frame:GetTop()
		local left, right, top = health:GetLeft(), health:GetRight(), health:GetTop()
		local portraitLeft, portraitRight = portrait:GetLeft(), portrait:GetRight()
		for _, value in ipairs({ frameLeft or false, frameTop or false, left or false, right or false, top or false,
			portraitLeft or false, portraitRight or false }) do
			if not Readable(value) then return end
		end
		local grow = (portraitRight - portraitLeft) * (ns.ThemePortraitFit(shape) - 1) / 2
		-- (A shape narrower than its square stands that much further from the rows.)
		local side = (portraitRight - portraitLeft + grow * 2) * ns.ThemePortraitSide(shape)
		if portraitLeft > right then
			right = math.max(right, portraitLeft - grow + RING_IN - BRIDGE + side)
		else
			left = math.min(left, portraitRight + grow - RING_IN + BRIDGE - side)
		end
		-- (The rows' middle on the portrait's: the name's strip sits on top of where the
		-- game's rows began, so they'd hang high.)
		local _, middle = portrait:GetCenter()
		local tall = health:GetHeight()
		local row = (Readable(tall) and tall < 9 and NAME_ROW_SMALL or NAME_ROW) + 1
		local rows = row + (Readable(tall) and tall or 0)
		for i = 2, #bars do
			local height = bars[i]:GetHeight()
			if ns.Flag(bars[i]:IsShown()) and Readable(height) then rows = rows + BAR_GAP + height end
		end
		if Readable(middle) then top = middle + rows / 2 - row end
		state = { x = left - frameLeft, y = top - frameTop, wide = right - left, bars = {} }
		for _, bar in ipairs(bars) do
			state.bars[bar] = { spots = SpotsOf(bar), wide = (FirstSize(bar)) }
		end
		fits[frame] = state
	end
	for _, bar in ipairs(bars) do StripMasks(state, bar) end
	health:ClearAllPoints()
	health:SetPoint("TOPLEFT", frame, "TOPLEFT", state.x, state.y)
	health:SetWidth(state.wide)
	-- (The name in the middle of its strip.)
	local dressed = shapes[frame]
	if name and dressed and dressed.plate and ns.Flag(dressed.plate:IsShown()) then
		SpotsOf(name)
		if not state.name then state.justify = name:GetJustifyH() end
		state.name = name
		name:ClearAllPoints()
		name:SetPoint("CENTER", dressed.plate, "CENTER")
		name:SetJustifyH("CENTER") -- (retail's box is wider than its words)
		-- (Retail's level has no badge: it goes in the strip, not on the line under it.)
		if ns.UnitPartRegions and #ns.UnitPartRegions(frame, "LevelBack") == 0 then
			-- (Its name to the left, as the game has it, across from the level.)
			name:ClearAllPoints()
			name:SetPoint("LEFT", dressed.plate, "LEFT", 6, 0)
			name:SetJustifyH("LEFT")
			state.levels = state.levels or {}
			for _, level in ipairs(ns.UnitPartRegions(frame, "Level")) do
				if level.GetObjectType and level:GetObjectType() == "FontString" then
					SpotsOf(level)
					state.levels[level] = true
					level:ClearAllPoints()
					level:SetPoint("RIGHT", dressed.plate, "RIGHT", -5, 0)
				end
			end
		end
	end
	for i = 2, #bars do
		bars[i]:ClearAllPoints()
		-- (The game's overlap, its art covering the join: with none, a clean gap.)
		bars[i]:SetPoint("TOPLEFT", bars[i - 1], "BOTTOMLEFT", 0, -BAR_GAP)
		bars[i]:SetWidth(state.wide)
	end
end

-- What else a frame can show, which sits where the art or portrait was: on a bare bar
-- each needs a place of its own, or it lands on the name or floats. Dead and the like
-- at the value's end, the raid marker on the bar's top edge, the leader's crown above
-- its corner, a quest or boss mark off its end, a skull for the level with the level.
local moved = setmetatable({}, { __mode = "k" })
local function Extras(frame, health)
	local list = {}
	local function Add(region, point, to, x, y)
		if region and region.SetPoint then list[#list + 1] = { region, point, to, x, y } end
	end
	local name = frame.GetName and frame:GetName() or ""
	local parent = health:GetParent()
	local content = frame.TargetFrameContent or frame.PlayerFrameContent
	local context = content and (content.TargetFrameContentContextual or content.PlayerFrameContentContextual)
	local main = content and (content.TargetFrameContentMain or content.PlayerFrameContentMain)
	for _, text in ipairs({ frame.deadText or false, frame.unconsciousText or false, parent and parent.DeadText or false,
		parent and parent.UnconsciousText or false, _G[name .. "TextureFrameDeadText"] or false,
		_G[name .. "TextureFrameUnconsciousText"] or false }) do
		Add(text, "RIGHT", "RIGHT", -7, 0)
	end
	Add(context and context.RaidTargetIcon or _G[name .. "TextureFrameRaidTargetIcon"], "CENTER", "TOP", 0, 3)
	Add(context and context.LeaderIcon or _G[name .. "TextureFrameLeaderIcon"], "BOTTOMLEFT", "TOPLEFT", 0, 0)
	Add(context and context.GuideIcon, "BOTTOMLEFT", "TOPLEFT", 0, 0)
	Add(context and context.QuestIcon or _G[name .. "TextureFrameQuestIcon"], "LEFT", "RIGHT", 2, 0)
	Add(context and context.BossIcon, "LEFT", "RIGHT", 2, 0)
	Add(context and context.HighLevelTexture or main and main.HighLevelTexture or _G[name .. "TextureFrameHighLevelTexture"],
		"LEFT", "LEFT", 6, 0)
	return list
end
local function SlabExtras(frame, health, on)
	if on then
		local list = moved[frame] or {}
		moved[frame] = list
		for _, item in ipairs(Extras(frame, health)) do
			local region = item[1]
			list[region] = SpotsOf(region)
			region:ClearAllPoints()
			region:SetPoint(item[2], health, item[3], item[4], item[5])
		end
	elseif moved[frame] then
		for region, spots in pairs(moved[frame]) do PutBack(region, spots) end
		moved[frame] = nil
	end
end

-- The name moves onto the bar, on a frame over it (it's drawn under the bar where
-- it was), and the bar's middle number to its right, as the left one goes. Done
-- again each time: the game places them again as the unit changes.
local slabs = setmetatable({}, { __mode = "k" })
local function DressSlab(frame, health, name, power, portrait, bare)
	if InCombatLockdown() or not (health and name) then return end
	local state = slabs[frame]
	local on = state ~= nil and ns.StyleOn("ufStyle") and ns.ThemeLayout() == "slab" or SlabOn(health)
	local middle = health.TextString
	if on then
		if not state then
			state = { name = SpotsOf(name), parent = name:GetParent(), width = name:GetWidth(), justify = name:GetJustifyH(),
				middle = middle and SpotsOf(middle), right = health.RightText and SpotsOf(health.RightText) }
			state.top = CreateFrame("Frame", nil, frame)
			state.top:SetAllPoints(health)
			slabs[frame] = state
		end
		local bars = { health, power }
		local second = frame == _G.PlayerFrame and _G.AlternatePowerBar
		if second then bars[#bars + 1] = second end
		local ok, err = pcall(SizeSlab, frame, state, bars, portrait, bare)
		if not ok then ns.Log("style", "slab size failed: " .. tostring(err)) end
		state.top:SetFrameLevel(health:GetFrameLevel() + 3)
		name:SetParent(state.top)
		name:ClearAllPoints()
		-- (After the level, which goes on the bar too: no badge, just the number.)
		local shape = shapes[frame]
		if shape and shape.badge then
			shape.badge:SetFrameLevel(math.max(frame:GetFrameLevel() + 7, health:GetFrameLevel() + 4))
		end
		local level
		for _, region in ipairs(ns.UnitPartRegions and ns.UnitPartRegions(frame, "Level") or {}) do
			if region.GetObjectType and region:GetObjectType() == "FontString" then
				if not state.level then state.level = {} end
				if not state.level[region] then
					local file, size, flags = FirstFont(region)
					state.level[region] = { spots = SpotsOf(region), file = file, size = size, flags = flags }
					if file then region:SetFont(file, 11, flags or "") end
				end
				-- (Your own says nothing a sleek frame needs: only a target's stays.)
				local own = frame == _G.PlayerFrame
				SetClear(region, own)
				region:ClearAllPoints()
				region:SetPoint("LEFT", health, "LEFT", 7, 0)
				level = not own or level
			end
		end
		for _, region in ipairs(ns.UnitPartRegions and ns.UnitPartRegions(frame, "LevelBack") or {}) do SetClear(region, true) end
		name:SetPoint("LEFT", health, "LEFT", level and 28 or 7, 0)
		name:SetJustifyH("LEFT")
		local wide = health:GetWidth()
		if Readable(wide) then name:SetWidth(wide * 0.62) end
		if middle then
			middle:ClearAllPoints()
			middle:SetPoint("RIGHT", health, "RIGHT", -7, 0)
		end
		if health.RightText then
			health.RightText:ClearAllPoints()
			health.RightText:SetPoint("RIGHT", health, "RIGHT", -7, 0)
		end
	elseif state then
		slabs[frame] = nil
		for region, was in pairs(state.level or {}) do
			PutBack(region, was.spots)
			SetClear(region, false)
			if was.file then region:SetFont(was.file, was.size, was.flags or "") end
		end
		for _, region in ipairs(ns.UnitPartRegions and ns.UnitPartRegions(frame, "LevelBack") or {}) do SetClear(region, false) end
		local ok, err = pcall(UnsizeSlab, state)
		if not ok then ns.Log("style", "slab size back failed: " .. tostring(err)) end
		if health.RightText and state.right then PutBack(health.RightText, state.right) end
		name:SetParent(state.parent)
		PutBack(name, state.name)
		name:SetJustifyH(state.justify)
		if Readable(state.width) then name:SetWidth(state.width) end
		if middle and state.middle then PutBack(middle, state.middle) end
	end
	SetClear(health.LeftText, on)
	SlabExtras(frame, health, on)
	-- (Resting's Zzz: over a portrait it's a detail, over a lone bar a stray.)
	local content = frame.PlayerFrameContent
	local contextual = content and content.PlayerFrameContentContextual
	SetClear(contextual and contextual.PlayerRestLoop, on)
end

-- The game's level badge is drawn for its big round portrait: a size down with a
-- shape of ours, the number with it. Out of fights, and put back after.
local BADGE_SIZE = 0.58
local function ShrinkBadge(frame, state, on, portrait, shape)
	if InCombatLockdown() or not ns.UnitPartRegions then return end
	if on and state.small and state.badgeShape ~= shape and #ns.UnitPartRegions(frame, "LevelBack") > 0 then
		state.badgeShape = nil
	end
	if on and not state.small and #ns.UnitPartRegions(frame, "LevelBack") > 0 then
		state.small = {}
		for _, region in ipairs(ns.UnitPartRegions(frame, "Level")) do
			if region.GetObjectType and region:GetObjectType() == "FontString" then
				local file, size, flags = FirstFont(region)
				if file and size then
					state.small[region] = { file = file, size = size, flags = flags, spots = SpotsOf(region) }
					region:SetFont(file, size * BADGE_SIZE, flags or "")
				end
			elseif region.SetSize then
				local wide, tall = FirstSize(region)
				if Readable(wide) and Readable(tall) then
					state.small[region] = { wide = wide, tall = tall, spots = SpotsOf(region) }
					region:SetSize(wide * BADGE_SIZE, tall * BADGE_SIZE)
				end
			end
		end
	elseif not on and state.small then
		for region, was in pairs(state.small) do
			if was.file then region:SetFont(was.file, was.size, was.flags or "") else region:SetSize(was.wide, was.tall) end
			PutBack(region, was.spots)
		end
		state.small, state.badgeShape = nil, nil
	end
	-- (On the shape's own spot: the portrait's far bottom corner, mirrored with it.)
	if on and state.small and state.badgeShape ~= shape then
		local wide = portrait:GetWidth()
		if Readable(wide) then
			state.badgeShape = shape
			local spot = ns.ThemeBadgeSpot(shape)
			local x, y = spot[1] * wide, spot[2] * wide
			for region in pairs(state.small) do
				region:ClearAllPoints()
				region:SetPoint("CENTER", portrait, state.flip and "BOTTOMRIGHT" or "BOTTOMLEFT", state.flip and -x or x, y)
			end
		end
	end
end

-- The level's badge in the theme's color, as its other rings are.
local function TintBadge(frame, on)
	local color = on and ns.ThemeRing()
	for _, art in ipairs(ns.UnitPartRegions and ns.UnitPartRegions(frame, "LevelBack") or {}) do
		if art.SetDesaturated and (color or tinted[art]) then
			local _, _, _, alpha = art:GetVertexColor()
			if not Readable(alpha) then alpha = nil end
			art:SetDesaturated(color and true or false)
			art:SetVertexColor(color and color[1] or 1, color and color[2] or 1, color and color[3] or 1, alpha)
			tinted[art] = color and true or nil
		end
	end
end

-- (Inside the portrait's place: the bars start right at its edge, and a shaped
-- bar's point needs air between them to read.)
local RING_INSET = 2

local function DressShape(frame, portrait, view, artOver)
	local shape = view and view.ufShape or "game"
	local state = shapes[frame]
	if shape == "game" and not state then return end
	if not portrait then return end
	if not state then
		state = {}
		shapes[frame] = state
	end
	local own = shape ~= "game"
	for _, art in ipairs(FrameArt(frame)) do SetClear(art, own) end
	for _, art in ipairs(ArtExtras(frame)) do SetClear(art, own) end
	SetClear(portrait, shape == "none")
	LiftLevel(frame, state, own)
	FramePlate(frame, state, portrait, own, artOver, shape)
	local slab = ns.ThemeLayout() == "slab"
	PlaceBadge(frame, state, shape == "none" and not slab)
	ShrinkBadge(frame, state, own and not slab and shape ~= "none", portrait, shape)
	TintBadge(frame, own)
	-- (A shape that'd cut the picture grows round it: ns.ThemePortraitFit.)
	local wide = portrait:GetWidth()
	local grow = Readable(wide) and wide * (ns.ThemePortraitFit(shape) - 1) / 2 or 0
	-- (The arch's point is narrow and the game's picture sits to the left of its square:
	-- a touch closer in, moved right and down, puts the face under the point.)
	local arched = shape == "arch" and not OwnOf(portrait).iconed
	if arched then
		portrait:SetTexCoord(0, 0.9, 0, 0.92)
	elseif state.arched then
		portrait:SetTexCoord(0, 1, 0, 1)
	end
	state.arched = arched
	-- (The game's mask isn't a true circle: it leaves corners of the picture for
	-- the frame art to cover. A circle of ours has a mask of its own, just inside
	-- the ring. Made out of fights only, as the ring is.)
	local mask = PortraitMask(frame)
	if mask and portrait.RemoveMaskTexture then
		local maskFile = ns.ThemePortraitCut(shape)
		if maskFile and not state.round and not InCombatLockdown() then
			local owner = portrait:GetParent()
			state.round = owner:CreateMaskTexture()
			ns.ThemeNoSnap(state.round)
		end
		if maskFile and state.round then
			state.round:SetTexture(maskFile, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
			state.round:ClearAllPoints()
			state.round:SetPoint("TOPLEFT", portrait, "TOPLEFT", -grow, grow)
			state.round:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", grow, -grow)
		end
		local round = maskFile ~= nil and state.round ~= nil
		local bare = shape == "square" or round
		if bare and not state.bare then
			portrait:RemoveMaskTexture(mask)
		elseif state.bare and not bare then
			portrait:AddMaskTexture(mask)
		end
		state.bare = bare
		if round and not state.rounded then
			portrait:AddMaskTexture(state.round)
		elseif state.rounded and not round then
			portrait:RemoveMaskTexture(state.round)
		end
		state.rounded = round
	end
	-- (Ours round it. The game's frames are secure: made out of fights only.)
	if own and shape ~= "none" and not state.holder and not InCombatLockdown() then
		state.holder = CreateFrame("Frame", nil, frame)
		state.holder:SetAllPoints(portrait)
		state.holder:SetFrameLevel(frame:GetFrameLevel() + 5)
		state.ring = state.holder:CreateTexture(nil, "OVERLAY")
		state.ring:SetPoint("TOPLEFT", RING_INSET, -RING_INSET)
		state.ring:SetPoint("BOTTOMRIGHT", -RING_INSET, RING_INSET)
		state.ring:SetTexture(RING)
		ns.ThemeNoSnap(state.ring)
		-- (A thin dark line outside it: a pale ring goes on snow and sky without.)
		state.ringBack = state.holder:CreateTexture(nil, "OVERLAY", nil, -1)
		state.ringBack:SetPoint("TOPLEFT", RING_INSET - 1.5, -RING_INSET + 1.5)
		state.ringBack:SetPoint("BOTTOMRIGHT", -RING_INSET + 1.5, RING_INSET - 1.5)
		ns.ThemeNoSnap(state.ringBack)
		state.inner = state.holder:CreateTexture(nil, "ARTWORK")
		ns.ThemeNoSnap(state.inner)
		state.inner:SetAlpha(0.75)
		state.edges = ns.MakeStyleEdges(state.holder)
	end
	if state.holder then
		local color = ns.ThemeRing() or { 0.8, 0.65, 0.25 }
		state.holder:SetShown(own and shape ~= "none")
		local ringFile = ns.ThemePortraitRing(shape)
		local shadeFile = ns.ThemePortraitShade(shape)
		state.inner:SetShown(shadeFile and true or false)
		if shadeFile then
			state.inner:SetTexture(shadeFile)
			state.inner:ClearAllPoints()
			state.inner:SetPoint("TOPLEFT", -grow, grow)
			state.inner:SetPoint("BOTTOMRIGHT", grow, -grow)
		end
		state.ring:SetShown(ringFile and true or false)
		state.ringBack:SetShown(ringFile and true or false)
		if ringFile then
			state.ring:SetTexture(ringFile)
			state.ringBack:SetTexture(ringFile)
		end
		state.ring:SetVertexColor(color[1], color[2], color[3], 1)
		state.ringBack:SetVertexColor(0, 0, 0, 0.75)
		local inset = RING_INSET - grow
		state.ring:ClearAllPoints()
		state.ring:SetPoint("TOPLEFT", inset, -inset)
		state.ring:SetPoint("BOTTOMRIGHT", -inset, inset)
		state.ringBack:ClearAllPoints()
		state.ringBack:SetPoint("TOPLEFT", inset - 1.5, -inset + 1.5)
		state.ringBack:SetPoint("BOTTOMRIGHT", -inset + 1.5, inset - 1.5)
		state.edges:SetShown(shape == "square")
		if shape == "square" then ns.DressStyleEdges(state.edges, 2, color[1], color[2], color[3], 1, true) end
	end
end

local hooked = setmetatable({}, { __mode = "k" })
local Dress
local HEALTH_GREEN = { 0, 0.8, 0 }

-- Game frame -> its entry, as last dressed (the portrait hook's lookup, so
-- it doesn't rebuild every list on each portrait update; refilled by
-- ns.RefreshUnitStyle on the roster and Edit Mode events).
local frameInfo = setmetatable({}, { __mode = "k" })

-- One frame (id) as the page says, every game frame it covers.
local function DressFrame(info)
	local active = ns.StyleOn("ufStyle")
	local view = active and View(info[1]) or nil
	for _, frame in ipairs(GameFrames(info)) do
		frameInfo[frame] = info
		if not (frame.IsForbidden and frame:IsForbidden()) then
			local unit = frame.unit
			local health, power, text, portrait = Parts(frame)
			local r, g, b
			if view then r, g, b = HealthColor(view, unit) end
			-- (A theme's color, fuller for a bar this big. Class colors stand as they are.)
			if r and view.ufHealthColor == "custom" and ns.ThemeLayout() ~= "slab" and ns.ThemeRing() then
				local vivid = ns.ThemeVivid({ r, g, b })
				r, g, b = vivid[1], vivid[2], vivid[3]
			end
			DressBar(health, view, r, g, b, HEALTH_GREEN)
			-- (Mana in the theme's color: rage, energy and the rest mean something by theirs.)
			local mana = view and ns.ThemeMana() or nil
			local tint = PowerTint(unit)
			if mana and tint == MANA_BLUE then
				DressBar(power, view, mana[1], mana[2], mana[3], tint, health)
			else
				DressBar(power, view, nil, nil, nil, tint, health)
			end
			-- (The player's second power, Elemental's mana say: drawn under the first.)
			local second = frame == _G.PlayerFrame and _G.AlternatePowerBar or nil
			DressBar(second, view, mana and mana[1], mana and mana[2], mana and mana[3], MANA_BLUE, health)
			DressBarText(health, view)
			DressBarText(power, view)
			DressBarText(second, view)
			DressName(text, view, unit)
			FitName(text, view)
			DressPortrait(portrait, view, unit)
			DressFrameArt(frame, active)
			-- (A slab's taken off first: the badge measures the level's place next, and
			-- would keep the bar as the spot to put it back to.)
			local slabTheme = view and ns.ThemeLayout() == "slab"
			local bare = view and view.ufShape == "none"
			if not slabTheme then DressSlab(frame, health, text, power, portrait, bare) end
			DressShape(frame, portrait, view, ns.StyleOverride("unitPart" .. info[2] .. "Art") == "hide")
			-- (One's taken off before the other's measured from the game's own sizes.)
			local fit = health and power and portrait and view and view.ufShape ~= "game" and view.ufShape ~= "none"
				and ns.ThemeLayout() ~= "slab"
			local bars = { health, power }
			local extra = frame == _G.PlayerFrame and _G.AlternatePowerBar
			if extra and health and power then bars[3] = extra end
			local ok, err = true, nil
			if not fit then ok, err = pcall(FitBars, frame, bars, portrait, nil, false) end
			if slabTheme then DressSlab(frame, health, text, power, portrait, bare) end
			if fit then ok, err = pcall(FitBars, frame, bars, portrait, view.ufShape, true, text) end
			if not ok then ns.Log("style", "bar fit failed: " .. tostring(err)) end
			-- (The game sets these again as the unit changes: ours after it.)
			if not hooked[frame] then
				hooked[frame] = true
				local second = frame == _G.PlayerFrame and _G.AlternatePowerBar
				for _, bar in ipairs({ health or false, power or false, second or false }) do
					if bar and bar.SetStatusBarTexture then
						hooksecurefunc(bar, "SetStatusBarTexture", function() if not dressing then Dress(info) end end)
					end
				end
				if health and health.SetStatusBarColor then
					hooksecurefunc(health, "SetStatusBarColor", function() if not dressing then Dress(info) end end)
				end
				-- (A power bar's fill and color change with the unit's power: the
				-- game's newest is what's ours to tint and to put back. It sets
				-- the color after the fill, so that's ours to follow too.)
				if power and power.SetStatusBarColor then
					hooksecurefunc(power, "SetStatusBarTexture", function(_, fill)
						local saved = own[power]
						if dressing or not saved then return end
						if type(fill) == "string" or type(fill) == "number" then saved.atlas, saved.file = fill, nil end
					end)
					hooksecurefunc(power, "SetStatusBarColor", function(_, r, g, b)
						if dressing then return end
						local saved = own[power]
						if saved and Readable(r) then saved.color = { r, g, b } end
						Dress(info)
					end)
				end
			end
		end
	end
end

function Dress(info)
	if dressing then return end
	DressFrame(info)
end

-- Every frame again (the page's settings changing, a new target...).
-- For /cine debug themecheck: where the parts we move are, as text to compare.
function ns.UnitStyleSpots()
	local out = {}
	for _, id in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame" }) do
		local frame = _G[id]
		if frame then
			local health, power, name = Parts(frame)
			local list = { health = health or false, power = power or false, name = name or false,
				second = frame == _G.PlayerFrame and _G.AlternatePowerBar or false }
			for i, region in ipairs(ns.UnitPartRegions and ns.UnitPartRegions(frame, "Level") or {}) do list["level" .. i] = region end
			for key, region in pairs(list) do
				if region then
					-- (To a tenth: the game's own sums wander in the last digits.)
					local function Near(value) return type(value) == "number" and ("%.1f"):format(value) or tostring(value) end
					-- (A text's width is its words': it isn't ours to size.)
					local text = region.GetFont ~= nil
					local words = { tostring(region:GetParent()), text and "" or Near(region:GetWidth()),
						text and "" or Near(region:GetHeight()) }
					for i = 1, tonumber(region:GetNumPoints()) or 0 do
						local point, to, toPoint, x, y = region:GetPoint(i)
						words[#words + 1] = table.concat({ tostring(point), tostring(to), tostring(toPoint), Near(x), Near(y) }, " ")
					end
					if region.GetFont then words[#words + 1] = tostring(select(2, region:GetFont())) end
					out[id .. " " .. key] = table.concat(words, "; ")
				end
			end
		end
	end
	return out
end

-- For the shots' log: what the player frame's meant to be and what it is.
function ns.UnitStyleState()
	local frame = _G.PlayerFrame
	if not frame then return "unit: no PlayerFrame" end
	local view = View("PLAYER")
	local health = Parts(frame)
	local fill = health and health.GetStatusBarTexture and health:GetStatusBarTexture()
	local r, g, b = 0, 0, 0
	if health and health.GetStatusBarColor then r, g, b = health:GetStatusBarColor() end
	return ("unit: health %s fill %s color %.2f %.2f %.2f; wants texture %s path %s health %s shape %s"):format(tostring(health ~= nil),
		tostring(fill and fill:GetTexture()), r or 0, g or 0, b or 0, tostring(view.ufTexture),
		tostring(ns.StyleTexturePath(view.ufTexture)), tostring(view.ufHealthColor), tostring(view.ufShape))
end

function ns.RefreshUnitStyle()
	if not ns.db then return end
	wipe(frameInfo)
	-- (Each on its own, so one's trouble leaves the others dressed, with where it was.)
	for _, info in ipairs(FRAMES) do
		local ok, err = xpcall(function() DressFrame(info) end, function(text)
			return tostring(text) .. " at " .. tostring(debugstack and debugstack(2, 3, 0))
		end)
		if not ok then ns.Log("style", "unit frame " .. tostring(info[1]) .. " failed: " .. err) end
	end
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET",
	"UNIT_DISPLAYPOWER", "UNIT_FACTION", "GROUP_ROSTER_UPDATE", "EDIT_MODE_LAYOUTS_UPDATED", "CVAR_UPDATE" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event, name)
	-- (Of the game's settings, only the classic clients' raid-style party one.)
	if event == "CVAR_UPDATE" and name ~= "useCompactPartyFrames" then return end
	ns.RefreshUnitStyle()
end)
if hooksecurefunc and type(_G.UnitFramePortrait_Update) == "function" then
	hooksecurefunc("UnitFramePortrait_Update", function(frame)
		local info = frame and frameInfo[frame]
		if info then
			local _, _, _, portrait = Parts(frame)
			DressPortrait(portrait, ns.StyleOn("ufStyle") and View(info[1]) or nil, frame.unit)
		end
	end)
end

-- The preview: the five frames as small mock-ups, each dressed by its own
-- look (a frame clicked opens its tab: onPick(id)).
-- (Faces: the first icon this client has; the last of each list is in every client.)
local THRALL = { "Interface\\Icons\\Achievement_Leader_Thrall", "Interface\\Icons\\INV_Misc_Head_Orc_01" }
local SAMPLES = {
	PLAYER = { name = "Thrall", x = 14, y = -30, w = 150, class = "SHAMAN", health = 0.86, power = { 0, 0.55, 1 },
		amount = 0.4, faces = THRALL },
	TARGET = { name = "The Lich King", x = 270, y = -30, w = 150, reaction = 2, health = 0.62,
		power = { 0, 0.55, 1 }, amount = 1, flip = true,
		faces = { "Interface\\Icons\\Achievement_Boss_LichKing", "Interface\\Icons\\INV_Misc_Head_Undead_01" } },
	FOCUS = { name = "Jaina", x = 300, y = -112, w = 110, class = "MAGE", health = 0.95, power = { 0, 0.55, 1 },
		amount = 0.7, flip = true,
		faces = { "Interface\\Icons\\Achievement_Character_Jaina_Proudmoore", "Interface\\Icons\\Achievement_Leader_Jaina_Proudmoore",
			"Interface\\Icons\\INV_Misc_Head_Human_02" } },
	PET = { name = "Wolf", x = 30, y = -118, w = 80, reaction = 5, health = 1, power = { 1, 1, 0 }, amount = 0.5,
		small = true, faces = { "Interface\\Icons\\Ability_Hunter_Pet_Wolf" } },
	PARTY = { name = "Varian", x = 150, y = -146, w = 90, class = "WARRIOR", health = 0.7, power = { 1, 0, 0 },
		amount = 0.8, small = true,
		faces = { "Interface\\Icons\\Achievement_Leader_King_Varian_Wrynn", "Interface\\Icons\\INV_Misc_Head_Human_01" } },
	TOT = { name = "Thrall", x = 372, y = -80, w = 70, class = "SHAMAN", health = 0.86, power = { 0, 0.55, 1 },
		amount = 0.4, small = true, faces = THRALL },
}
local function SampleFace(sample)
	if not sample.face then
		local faces = sample.faces
		sample.face = faces[#faces]
		local FileID = _G.GetFileIDFromPath
		if FileID then
			for _, path in ipairs(faces) do
				if FileID(path) then sample.face = path break end
			end
		end
	end
	return sample.face
end
local GAME_FILL = "Interface\\TargetingFrame\\UI-StatusBar"

local function SampleColor(sample)
	if sample.class then
		local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[sample.class]
		if color then return color.r, color.g, color.b end
	end
	local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[sample.reaction or 4]
	if color then return color.r, color.g, color.b end
	return 1, 0.2, 0.2
end

function ns.MakeUnitStylePreview(parent, width, onPick)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 190)
	if holder.SetClipsChildren then holder:SetClipsChildren(true) end
	local caption = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetPoint("TOPLEFT", 6, -5)
	caption:SetText(L["Preview"])
	caption.searchSkip = true
	-- (The frames on a stage their layout's size, its margins even, kept in
	-- the middle however wide the preview is.)
	local right, bottom = 0, 0
	for _, sample in pairs(SAMPLES) do
		local size = sample.small and 22 or 34
		right = math.max(right, sample.x + sample.w + size + 6)
		bottom = math.max(bottom, -sample.y + size + 6)
	end
	local stage = CreateFrame("Frame", nil, holder)
	stage:SetSize(right + 14, bottom + 30) -- (the layout's left and top margins, on the other sides too)
	stage:SetPoint("CENTER")
	local samples = {}
	for _, info in ipairs(FRAMES) do
		local id, sample = info[1], SAMPLES[info[1]]
		local unit = CreateFrame("Button", nil, stage)
		local size = sample.small and 22 or 34
		unit:SetSize(sample.w + size + 6, size + 6)
		unit:SetPoint("TOPLEFT", stage, "TOPLEFT", sample.x, sample.y)
		unit.portrait = unit:CreateTexture(nil, "ARTWORK")
		unit.portrait:SetSize(size, size)
		unit.portrait:SetPoint(sample.flip and "RIGHT" or "LEFT", unit, sample.flip and "RIGHT" or "LEFT", 0, 0)
		-- (The face: an icon cut round like the game's portraits.)
		unit.face = unit:CreateTexture(nil, "ARTWORK")
		unit.face:SetAllPoints(unit.portrait)
		unit.face:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		if unit.CreateMaskTexture then
			local mask = unit:CreateMaskTexture()
			mask:SetAllPoints(unit.portrait)
			mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIONAL",
				"CLAMPTOBLACKADDITIONAL")
			unit.face:AddMaskTexture(mask)
			unit.faceMask, unit.faceMasked = mask, true
		end
		-- (Its ring: a disc a little bigger behind it, as the class icons have.)
		unit.ring = unit:CreateTexture(nil, "BORDER")
		unit.ring:SetPoint("TOPLEFT", unit.portrait, -2, 2)
		unit.ring:SetPoint("BOTTOMRIGHT", unit.portrait, 2, -2)
		unit.ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		unit.ring:SetVertexColor(0.8, 0.65, 0.25)
		unit.name = unit:CreateFontString(nil, "OVERLAY", sample.small and "GameFontNormalSmall" or "GameFontNormal")
		unit.health = CreateFrame("StatusBar", nil, unit)
		unit.health:SetSize(sample.w, sample.small and 6 or 10)
		unit.power = CreateFrame("StatusBar", nil, unit)
		unit.power:SetSize(sample.w, sample.small and 3 or 5)
		local side = sample.flip and "RIGHT" or "LEFT"
		unit.health:SetPoint("TOP" .. side, unit.portrait, "TOP" .. (sample.flip and "LEFT" or "RIGHT"),
			sample.flip and -6 or 6, -(sample.small and 9 or 13))
		unit.power:SetPoint("TOP", unit.health, "BOTTOM", 0, -2)
		unit.name:SetPoint("BOTTOM" .. side, unit.health, "TOP" .. side, 0, 2)
		-- (Over the bars, for a slab's name.)
		unit.nameTop = CreateFrame("Frame", nil, unit)
		unit.nameTop:SetAllPoints()
		unit.name:SetParent(unit.nameTop)
		unit.value = unit.nameTop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		unit.value:SetPoint(sample.flip and "LEFT" or "RIGHT", unit.health, sample.flip and "LEFT" or "RIGHT",
			sample.flip and 7 or -7, 0)
		-- (On the stage, so it's under the portrait, as it is on the game's frames.)
		unit.plate = MakePlate(stage)
		unit.plate:SetFrameLevel(stage:GetFrameLevel())
		unit.bridge = MakeBridge(stage)
		unit.bridge:SetFrameLevel(stage:GetFrameLevel())
		unit.rowShadow = MakeRowShadow(stage)
		unit.rowShadow:SetFrameLevel(stage:GetFrameLevel())
		PlacePlate(unit.plate, unit.health)
		for _, bar in ipairs({ unit.health, unit.power }) do
			bar:SetMinMaxValues(0, 1)
			local ground = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
			ground:SetAllPoints()
			ground:SetColorTexture(0, 0, 0, 0.5)
			bar.game = ground
		end
		unit.health:SetValue(sample.health)
		unit.power:SetValue(sample.amount)
		unit.mark = unit:CreateTexture(nil, "OVERLAY")
		unit.mark:SetPoint("TOPLEFT", -3, 3)
		unit.mark:SetPoint("BOTTOMRIGHT", 3, -3)
		unit.mark:SetColorTexture(1, 0.82, 0, 0.12)
		unit:SetScript("OnClick", function() if onPick then onPick(id) end end)
		unit.id, unit.sample = id, sample
		samples[#samples + 1] = unit
	end
	function holder:Refresh(editing)
		ns.StyleScene(self, 0.55, 0.85)
		for _, unit in ipairs(samples) do
			local view, sample = View(unit.id), unit.sample
			unit.mark:SetShown(editing == unit.id)
			-- (The bars: the look's fill, else the game's look.)
			for i, bar in ipairs({ unit.health, unit.power }) do
				if not ns.SetBarTexture(bar, view.ufTexture) then
					bar:SetStatusBarTexture(GAME_FILL)
					bar:GetStatusBarTexture():SetDesaturated(false)
				end
				if i == 1 then
					local r, g, b
					if view.ufHealthColor == "class" then
						r, g, b = SampleColor(sample)
					elseif view.ufHealthColor == "custom" then
						r, g, b = view.ufHealthR, view.ufHealthG, view.ufHealthB
					end
					bar:SetStatusBarColor(r or 0, g or 0.8, b or 0)
				else
					local mana = ns.ThemeMana()
					if mana and sample.power[1] == 0 and sample.power[3] == 1 then
						bar:SetStatusBarColor(mana[1], mana[2], mana[3])
					else
						bar:SetStatusBarColor(unpack(sample.power))
					end
				end
				local kind = ns.StyleBorder(view, "ufBorder")
				bar.game:SetShown(kind == "game")
				DressSkin(Skin(bar), view, i == 2 and unit.health or nil)
			end
			DressPlateLook(unit.plate, view.ufShape ~= "game" and ns.ThemeLayout() ~= "slab")
			-- (A slab: as the game's frames get it, with a taller bar, as they have.)
			local slab = ns.ThemeLayout() == "slab" and not sample.small
			local across = sample.small and 22 or 34
			local bare = slab and view.ufShape == "none"
			local side = sample.flip and "RIGHT" or "LEFT"
			unit.health:ClearAllPoints()
			if bare then
				unit.health:SetPoint("TOP" .. side, unit.portrait, "TOP" .. side, 0, -6)
			else
				-- (A shape's rows in the portrait's middle, as FitBars puts them.)
				local down = sample.small and 9 or 13
				if view.ufShape ~= "game" and not slab then
					local row = (sample.small and NAME_ROW_SMALL or NAME_ROW) + 1
					local rows = row + (sample.small and 9 or 15) + BAR_GAP
					down = (across - rows) / 2 + row
				end
				local gap = 6
				if view.ufShape ~= "game" and not slab then
					local fit = ns.ThemePortraitFit(view.ufShape)
					gap = 4 + across * (fit - 1) / 2 - across * fit * ns.ThemePortraitSide(view.ufShape)
				end
				unit.health:SetPoint("TOP" .. side, unit.portrait, "TOP" .. (sample.flip and "LEFT" or "RIGHT"),
					sample.flip and -gap or gap, -down)
			end
			unit.health:SetSize(sample.w + (bare and across + 6 or 0), slab and 22 or sample.small and 6 or 10)
			unit.power:SetSize(sample.w + (bare and across + 6 or 0), slab and 4 or sample.small and 3 or 5)
			unit.name:ClearAllPoints()
			if slab then
				unit.name:SetPoint(sample.flip and "RIGHT" or "LEFT", unit.health, sample.flip and "RIGHT" or "LEFT",
					sample.flip and -7 or 7, 0)
			else
				local side = sample.flip and "RIGHT" or "LEFT"
				if view.ufShape ~= "game" then
					unit.name:SetPoint("CENTER", unit.plate, "CENTER")
				else
					unit.name:SetPoint("BOTTOM" .. side, unit.health, "TOP" .. side, 0, 2)
				end
			end
			unit.nameTop:SetFrameLevel(unit.health:GetFrameLevel() + 3)
			unit.value:SetShown(slab)
			if slab then
				unit.value:SetFontObject(_G.GameFontHighlightSmall)
				unit.value:SetText(("%d%%"):format(sample.health * 100))
			end
			PlacePlate(unit.plate, unit.health)
			PlaceBridge(unit.bridge, unit.plate, unit.health, unit.power, sample.flip, view.ufShape)
			PlaceRowShadow(unit.rowShadow, unit.plate, unit.power)
			unit.rowShadow:SetShown(view.ufShape ~= "game" and view.ufShape ~= "none" and ns.ThemeLayout() ~= "slab")
			DressBridge(unit.bridge, view.ufShape ~= "game" and view.ufShape ~= "none" and ns.ThemeLayout() ~= "slab")
			-- (The name.)
			local object = sample.small and _G.GameFontNormalSmall or _G.GameFontNormal
			unit.name:SetFontObject(object)
			local file, height, flags = object:GetFont()
			local font, outline = view.ufFont, tonumber(view.ufOutline) or 0
			if ROMAN then
				file = ns.StyleFontFile(font) or file
			end
			if outline >= 0 and ns.OutlinedFlags then flags = ns.OutlinedFlags(flags, outline) end
			if file and height then unit.name:SetFont(file, height * (tonumber(view.ufNameSize) or 1), flags or "") end
			ns.SetTextShadow(unit.name, view.ufShadow)
			unit.name:SetText(L[sample.name])
			local nr, ng, nb = 1, 0.82, 0
			if view.ufNameColor == "class" then
				nr, ng, nb = SampleColor(sample)
			elseif view.ufNameColor == "white" then
				nr, ng, nb = 1, 1, 1
			elseif view.ufNameColor == "theme" and ns.ThemeAccent() then
				nr, ng, nb = unpack(ns.ThemeAccent())
			end
			unit.name:SetTextColor(nr, ng, nb)
			-- (The portrait: a class icon for a player with Class icon picked.)
			local coords = view.ufPortrait == "class" and sample.class and _G.CLASS_ICON_TCOORDS
				and _G.CLASS_ICON_TCOORDS[sample.class]
			unit.portrait:SetShown(coords and true or false)
			unit.face:SetShown(not coords)
			unit.ring:SetShown(not coords)
			-- (Its shape: a square's ring a plain block behind it, no ring at all with None.)
			local shape, ring = view.ufShape, ns.ThemeRing() or { 0.8, 0.65, 0.25 }
			local square = shape == "square"
			if unit.faceMask and square == unit.faceMasked then
				if square then unit.face:RemoveMaskTexture(unit.faceMask) else unit.face:AddMaskTexture(unit.faceMask) end
				unit.faceMasked = not square
			end
			local shapeFile = ns.ThemePortraitMask(shape) or "Interface\\CharacterFrame\\TempPortraitAlphaMask"
			local grow = (sample.small and 22 or 34) * (ns.ThemePortraitFit(shape) - 1) / 2
			unit.ring:ClearAllPoints()
			unit.ring:SetPoint("TOPLEFT", unit.portrait, -2 - grow, 2 + grow)
			unit.ring:SetPoint("BOTTOMRIGHT", unit.portrait, 2 + grow, -2 - grow)
			if unit.faceMask then
				unit.faceMask:ClearAllPoints()
				unit.faceMask:SetPoint("TOPLEFT", unit.portrait, -grow, grow)
				unit.faceMask:SetPoint("BOTTOMRIGHT", unit.portrait, grow, -grow)
				unit.faceMask:SetTexture(shapeFile, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
			end
			if square then
				unit.ring:SetColorTexture(ring[1], ring[2], ring[3], 1)
			else
				unit.ring:SetTexture(shapeFile)
				unit.ring:SetVertexColor(ring[1], ring[2], ring[3])
			end
			if shape == "none" then
				unit.face:Hide()
				unit.ring:Hide()
				unit.portrait:Hide()
			end
			if coords then
				unit.portrait:SetTexture(CLASS_ICONS)
				unit.portrait:SetTexCoord(unpack(coords))
			else
				unit.face:SetTexture(SampleFace(sample))
			end
		end
	end
	return holder
end

-- The page itself.
local PRESET_KEYS = { "ufTexture", "ufBorder", "ufBorderSize", "ufBorderR", "ufBorderG", "ufBorderB", "ufBack",
	"ufHealthColor", "ufNameColor", "ufFont", "ufOutline", "ufNameSize", "ufShadow", "ufPortrait", "ufShape" }
local TAB_NAMES = {}
for _, info in ipairs(FRAMES) do TAB_NAMES[info[1]] = info[2] end

function ns.CreateUnitStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Unit Frames"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["How your player, target, focus, pet, target of target and party frames look. The Default tab's " ..
		"settings are every frame's until its own tab has Same as the Default tab unticked. Which parts show: " ..
		"the Interface hub's Unit Frames page."])

	-- The tab being edited (nil: Default), and each setting as the field it edits:
	-- the frame's own copy while it has one, else Default's (shown greyed).
	local editing
	local function UsesDefault(db) return editing and not db["ufOwn_" .. editing] end
	local function FieldOf(key)
		return {
			get = function()
				local db = ns.GetDB()
				if not db then return nil end
				local own = editing and db["ufOwn_" .. editing]
				local border = key:match("^ufBorder(%u%l*)$")
				if own and border and border ~= "" then return db["ufBorder_" .. editing .. border] end
				return db[own and key .. "_" .. editing or key]
			end,
			set = function(value)
				local db = ns.GetDB()
				local border = key:match("^ufBorder(%u%l*)$")
				if editing and border and border ~= "" then
					db["ufBorder_" .. editing .. border] = value
				else
					db[editing and key .. "_" .. editing or key] = value
				end
			end,
		}
	end
	local fields = {}
	local function Field(key)
		fields[key] = fields[key] or FieldOf(key)
		return fields[key]
	end

	local preview -- (below: drawn again as each setting changes)
	local tabs, ownCheck, partyNote
	local function Changed()
		ns.RefreshUnitStyle()
		if preview then preview:Refresh(editing) end
	end

	local switch = kit.PageSwitch(content, "ufStyle", L["Enable Page"],
		L["On: the unit frames look as this page says. Off: the game's own (the preview shows that too). " ..
		"Each setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "ufStyle", Field)
	local function Editable(db) return rows.On(db) and not UsesDefault(db) end

	local function Pick(id)
		editing = id
		kit.Refresh()
		Changed()
	end

	preview = ns.MakeUnitStylePreview(content, 480, Pick)
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)
	local refreshPreview = preview.Refresh
	preview.Refresh = function(self) refreshPreview(self, editing) end

	rows.PresetMenu({
		{ L["Like the game's"], L["The game's frames, as it draws them (the defaults)."], {} },
		{ L["Flat"], L["Flat bars with a thin black edge, health and names in class and reaction colors, " ..
			"Arial Narrow."], { ufTexture = "flat", ufBorder = "thin", ufBack = 0.65, ufHealthColor = "class",
			ufNameColor = "class", ufFont = "arial", ufOutline = 1 } },
		{ L["Slim"], L["Borderless flat bars in class colors, small white names."],
			{ ufTexture = "flat", ufBorder = "none", ufBack = 0.4, ufHealthColor = "class", ufNameColor = "white",
				ufNameSize = 0.9, ufOutline = 1 } },
		{ L["Cinematic"], L["Soft bars with a fine edge, class icons for players."],
			{ ufTexture = "soft", ufBorder = "thin", ufBack = 0.45, ufHealthColor = "class", ufPortrait = "class",
				ufOutline = 1 } },
		{ L["Square"], L["Square portraits with no frame art, flat bars with a thin edge."],
			{ ufShape = "square", ufTexture = "flat", ufBorder = "thin", ufBack = 0.65, ufHealthColor = "class" } },
		{ L["Bars only"], L["No portrait and no frame art: just the name and bars, in class colors."],
			{ ufShape = "none", ufTexture = "soft", ufBorder = "thin", ufBack = 0.6, ufHealthColor = "class",
				ufNameColor = "class" } },
	}, PRESET_KEYS)

	-- The tabs, in the folder look (ns.FolderTabs): Default, then each frame,
	-- the settings on the panel under them. On a frame's, Same as the Default
	-- tab; on Default's, a note in its place.
	local TAB_H = ns.FOLDER_TAB_HEIGHT
	local ids, list = { false }, {}
	for _, info in ipairs(FRAMES) do ids[#ids + 1] = info[1] end
	for i, id in ipairs(ids) do
		list[i] = { id and L[TAB_NAMES[id]] or L["Default"],
			id and L["This frame's settings: Default's until you untick Same as the Default tab."]
			or L["The settings every frame has while its tab uses the default settings."] }
	end
	local tabsRoom = CreateFrame("Frame", nil, content)
	tabsRoom:SetSize(480, TAB_H + 4)
	stack:Add(tabsRoom, "label")
	local panel, ShowTab, base
	panel, tabs, ShowTab, base = ns.FolderTabs(content, list, function(i) Pick(ids[i] or nil) end)
	panel:SetPoint("TOPLEFT", tabsRoom, "BOTTOMLEFT", -10, 0)
	base:SetPoint("TOPLEFT", tabsRoom, "BOTTOMLEFT", -10, 0)
	local defaultNote
	local function TabsLook()
		local db = ns.GetDB()
		for i, tab in ipairs(tabs) do
			local id = ids[i] or nil
			local own = id and db and db["ufOwn_" .. id]
			tab:SetText((id and L[TAB_NAMES[id]] or L["Default"]) .. (own and " |cffffd100*|r" or ""))
			tab:SetWidth(math.max(56, math.ceil(tab.label:GetStringWidth()) + 16))
			if id == editing then ShowTab(i) end
		end
		ownCheck:SetShown(editing ~= nil)
		defaultNote:SetShown(editing == nil)
		partyNote:SetShown(editing == "PARTY" and ns.RaidStyleParty())
	end
	-- (Every setting the page has, Default's and each frame's, for its Reset.)
	for key in pairs(KEYS) do kit.RecordKey(content, key) end
	for _, info in ipairs(FRAMES) do
		kit.RecordKey(content, "ufOwn_" .. info[1])
		for key in pairs(KEYS) do kit.RecordKey(content, key .. "_" .. info[1]) end
		for _, part in ipairs({ "Size", "R", "G", "B" }) do kit.RecordKey(content, "ufBorder_" .. info[1] .. part) end
	end
	ownCheck = kit.Check(content, false, L["Same as the Default tab"],
		L["Ticked: this frame looks as the Default tab says. Unticked: as the settings below say (they start " ..
		"as Default's, and are kept while it's ticked)."], function(value)
			local db = ns.GetDB()
			-- (A first untick: the frame starts from Default's settings.)
			if not value and not db["ufStarted_" .. editing] then
				for key in pairs(KEYS) do db[key .. "_" .. editing] = db[key] end
				for _, part in ipairs({ "Size", "R", "G", "B" }) do
					db["ufBorder_" .. editing .. part] = db["ufBorder" .. part]
				end
				db["ufStarted_" .. editing] = true
			end
			db["ufOwn_" .. editing] = not value
			Changed()
			kit.Refresh()
		end)
	ownCheck.Refresh = function(self)
		local db = ns.GetDB()
		self:SetChecked(editing and db and not db["ufOwn_" .. editing] or false)
		TabsLook()
	end
	ownCheck.pageSwitch = false
	stack:Add(ownCheck, "check")
	-- (Party, while the game draws it as raid frames: nothing here to dress.)
	partyNote = kit.Label(content, "GameFontHighlightSmall", L["Your party uses raid-style frames (Edit Mode's " ..
		"party frames setting): they follow the Raid Frames page, not this tab."])
	partyNote:SetPoint("LEFT", ownCheck.Text or ownCheck.text or ownCheck, "RIGHT", 16, 0)
	partyNote:SetWidth(300)
	partyNote:SetJustifyH("LEFT")
	partyNote:SetTextColor(1, 0.82, 0)
	kit.GreyUnless(ownCheck, rows.On)
	kit.AddControl(ownCheck)
	defaultNote = kit.Label(content, "GameFontHighlightSmall",
		L["Every frame looks as this tab says while its own tab has Same as the Default tab ticked."])
	defaultNote:SetPoint("LEFT", ownCheck, "LEFT", 4, 0)
	defaultNote.searchSkip = true

	stack:Header(content, L["Look"])
	rows.Look(L["Bars:"], L["Bars"], {
		texture = { "ufTexture", L["The bars' fill. Below the game's own few: any other addon shares (through " ..
			"LibSharedMedia)."], test = Editable, tint = { 0.25, 0.75, 0.3 } },
		barColor = function(look)
			local last = look.Choices(L["Health:"], "ufHealthColor", {
				{ "game", L["The game's"] },
				{ "class", L["Class or reaction"], L["Players in their class color, everyone else red, yellow or " ..
					"green by how they see you."] },
				{ "custom", L["Custom"], L["A color of your own (the swatch)."] },
			}, Editable)
			look.Swatch(last, "ufHealthColor", { "ufHealthR", "ufHealthG", "ufHealthB" },
				L["The health bar's color, for Custom."], Editable)
		end,
		border = { "ufBorder", L["Round each bar: the game's frame alone, or a border of ours (Custom: its " ..
			"thickness and color under it)."], opts = { game = true }, test = Editable },
		ground = function(look)
			look.Slider("ufBack", L["Background"], 0, 100, 5, "%d%%", 100,
				L["How dark it is behind the bars, with a border of ours."], Editable)
		end,
	})
	rows.Look(L["Name:"], L["Name"], {
		font = { "ufFont", L["The name's font. Russian, Korean or Chinese names keep the game's, so their " ..
			"letters show."], test = Editable },
		textSize = function(look)
			look.Slider("ufNameSize", L["Size"], 50, 150, 5, "%d%%", 100, L["The name's size, next to the game's."],
				Editable)
		end,
		textColor = function(look)
			look.Choices(L["Color:"], "ufNameColor", {
				{ "game", L["The game's"] },
				{ "class", L["Class or reaction"] },
				{ "white", L["White"] },
				{ "theme", L["The theme's"] },
			}, Editable)
		end,
		outline = { "ufOutline", nil, names = { [0] = L["None"], L["Thin"], L["Thick"] }, test = Editable },
		outlineColor = false, -- (the game's text: its outline is always black)
		shadow = { "ufShadow", test = Editable },
	})

	rows.Choices(L["Long names:"], "ufNameCut", {
		{ "game", L["The game's"], L["A name too long for its frame ends in \"...\"."] },
		{ "first", L["First name"], L["A name too long for its frame loses its last words, with no \"...\": " ..
			"Benediction Cumberbatch shows as Benediction. A single long word loses its last letters."] },
	}, Editable)
	local portrait = rows.Choices(L["Portrait:"], "ufPortrait", {
		{ "game", L["The game's"], L["Their face."] },
		{ "class", L["Class icon"], L["A player's class icon in place of their face (NPCs keep theirs)."] },
	}, Editable)
	local shape = rows.Choices(L["Shape:"], "ufShape", {
		{ "game", L["The game's"], L["The game's round frame."] },
		{ "circle", L["Circle"], L["A thin ring in place of the game's frame art."] },
		{ "square", L["Square"], L["A square portrait with a thin edge, in place of the game's frame art."] },
		{ "hex", L["Hexagon"], L["A six-sided portrait, in place of the game's frame art."] },
		{ "diamond", L["Diamond"], L["A diamond portrait, in place of the game's frame art."] },
		{ "arch", L["Arch"], L["A portrait in a pointed window, in place of the game's frame art."] },
		{ "cut", L["Cut square"], L["A square portrait with small cut corners, in place of the game's frame art."] },
		{ "eye", L["Eye"], L["A tall, narrow portrait with a point at each end, in place of the game's frame art."] },
		{ "octagon", L["Octagon"], L["An eight-sided portrait, in place of the game's frame art."] },
		{ "shield", L["Shield"], L["A portrait on a shield, in place of the game's frame art."] },
		{ "petal", L["Leaf"], L["A rounded portrait with two sharp corners, in place of the game's frame art."] },
		{ "crystal", L["Crystal"], L["A wide cut crystal, in place of the game's frame art."] },
		{ "none", L["None"], L["No portrait and no frame art: just the name and bars."] },
	}, Editable)
	-- (The panel's bottom under the last row, its right at the page's.)
	panel:SetPoint("BOTTOM", shape or portrait, "BOTTOM", 0, -12)
	panel:SetPoint("RIGHT", content, "RIGHT", -16, 0)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Unit Style", L["Unit Frames"])
end
