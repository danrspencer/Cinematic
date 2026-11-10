-- The Interface Recolor page's Damage meter rows: the game's own damage meter
-- (its windows are UIParent's children named DamageMeter...) in the theme's
-- look. Its chrome takes the theme's color (InterfaceRecolor.lua's dmFrame
-- group); here, its bars in General's bar texture (each bar's own color kept:
-- class colors say who) and its words in General's text font. Its rows come
-- from a pool and are made as the list grows, so they're looked for again as
-- they show (a light look each second while a window is up, only new ones done).
-- Everything goes back to the game's own when the page or a row says so.

local _, ns = ...

local DEFAULTS = ns.DEFAULTS
DEFAULTS.dmFrame = true -- the meter's chrome in the theme's color (InterfaceRecolor.lua)
DEFAULTS.dmBars = true  -- its bars in General's bar texture
DEFAULTS.dmFont = true  -- its words in General's text font

local DEPTH = 10 -- (how deep into a window its parts are looked for: rows sit in a scroll box)

-- Fonts in a language with letters of its own (Russian, Korean, Chinese) stay
-- the game's: a font of ours has only Latin letters.
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]

local function Plain(value, kind)
	if issecretvalue and issecretvalue(value) then return nil end
	return type(value) == kind and value or nil
end

-- The meter's windows: UIParent's children whose names start DamageMeter.
local windows = {}
function ns.DamageMeterWindows()
	local list = {}
	for _, frame in pairs(windows) do list[#list + 1] = frame end
	local okKids, kids = pcall(function() return { UIParent:GetChildren() } end)
	for _, kid in ipairs(okKids and kids or {}) do
		local okName, name = pcall(kid.GetName, kid)
		name = okName and Plain(name, "string")
		if name and name:find("^DamageMeter") and not windows[name] then
			local okForbidden, forbidden = pcall(function() return kid.IsForbidden and kid:IsForbidden() end)
			if okForbidden and not forbidden then
				windows[name] = kid
				list[#list + 1] = kid
			end
		end
	end
	return list
end

-- What we changed, with the game's own to put back.
local bars = {}  -- [bar] = { atlas, file }
local texts = {} -- [text] = { fontObject, file, size, flags }
local plan = {}  -- (what the page says now: path, atlas, font)
local busy = false

local function BarOwn(bar)
	local fill = bar:GetStatusBarTexture()
	local okAtlas, atlas = pcall(function() return fill and fill.GetAtlas and fill:GetAtlas() end)
	local okFile, file = pcall(function() return fill and fill:GetTexture() end)
	return { atlas = okAtlas and Plain(atlas, "string") or nil,
		file = okFile and (Plain(file, "string") or Plain(file, "number")) or nil }
end

local function DressBar(bar)
	local own = bars[bar]
	if not plan.path then
		if own then
			busy = true
			if own.atlas and bar.SetStatusBarAtlas then
				pcall(bar.SetStatusBarAtlas, bar, own.atlas)
			elseif own.file then
				pcall(bar.SetStatusBarTexture, bar, own.file)
			end
			busy = false
		end
		return
	end
	if not own then
		own = BarOwn(bar)
		bars[bar] = own
		-- (The game setting its texture again, as a pooled row's made ready: ours again.)
		local function Again(self)
			if busy then return end
			bars[self] = BarOwn(self)
			if plan.path then DressBar(self) end
		end
		hooksecurefunc(bar, "SetStatusBarTexture", Again)
		if bar.SetStatusBarAtlas then hooksecurefunc(bar, "SetStatusBarAtlas", Again) end
	end
	if own.on == plan.path then return end -- (done already: the look each second)
	own.on = plan.path
	-- (Its color is the game's own: only its texture changes.)
	local fill = bar:GetStatusBarTexture()
	local r, g, b, a = 1, 1, 1, 1
	if fill and fill.GetVertexColor then r, g, b, a = fill:GetVertexColor() end
	busy = true
	if plan.atlas and bar.SetStatusBarAtlas then
		pcall(bar.SetStatusBarAtlas, bar, plan.path)
	else
		pcall(bar.SetStatusBarTexture, bar, plan.path)
	end
	busy = false
	fill = bar:GetStatusBarTexture()
	if fill and Plain(r, "number") then fill:SetVertexColor(r, g, b, a) end
end

local function DressText(text)
	local own = texts[text]
	if not plan.font then
		if own then
			if own[1] then
				text:SetFontObject(own[1])
			elseif own[2] and own[3] then
				text:SetFont(own[2], own[3], own[4] or "")
			end
			texts[text] = nil
		end
		return
	end
	local file, size, flags = text:GetFont()
	size = Plain(size, "number")
	if not size then return end
	if not own then
		texts[text] = { text:GetFontObject(), Plain(file, "string"), size, Plain(flags, "string") }
	end
	if Plain(file, "string") ~= plan.font then text:SetFont(plan.font, size, Plain(flags, "string") or "") end
end

local counts = { bars = 0, texts = 0, windows = 0 }
local function Walk(frame, depth, seen)
	if type(frame) ~= "table" or seen[frame] or not frame.GetObjectType then return end
	seen[frame] = true
	local okForbidden, forbidden = pcall(function() return frame.IsForbidden and frame:IsForbidden() end)
	if not okForbidden or forbidden then return end
	if frame:GetObjectType() == "StatusBar" then
		DressBar(frame)
		counts.bars = counts.bars + 1
	end
	local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
	for _, region in ipairs(okRegions and regions or {}) do
		if region:GetObjectType() == "FontString" then
			DressText(region)
			counts.texts = counts.texts + 1
		end
	end
	if depth >= DEPTH or not frame.GetChildren then return end
	local okKids, kids = pcall(function() return { frame:GetChildren() } end)
	for _, kid in ipairs(okKids and kids or {}) do Walk(kid, depth + 1, seen) end
end

local function Refresh()
	if not ns.db then return end
	local look = ns.StyleLook("irStyle")
	local on = ns.StyleOn("irStyle") and ns.ThemeRing() ~= nil
	plan.path, plan.atlas = nil, nil
	if on and look.dmBars ~= false then plan.path, plan.atlas = ns.StyleTexturePath(ns.db.styleTexture) end
	plan.font = on and ROMAN and look.dmFont ~= false and ns.StyleFontFile and ns.StyleFontFile(ns.db.styleFont) or nil
	counts.bars, counts.texts = 0, 0
	local list = ns.DamageMeterWindows()
	counts.windows = #list
	local seen = {}
	for _, frame in ipairs(list) do Walk(frame, 0, seen) end
	-- (A row that's not been seen this time (back in the pool) is put back too
	-- when the page says the game's: it's done as it shows again otherwise.)
	if not plan.path then
		for bar in pairs(bars) do DressBar(bar) end
		wipe(bars)
	end
	if not plan.font then
		for text in pairs(texts) do DressText(text) end
	end
	return list
end

-- (Many calls in one frame make one pass; InterfaceRecolor.lua's refresh calls it.)
local pending = false
function ns.RefreshDamageMeterStyle()
	if pending then return end
	pending = true
	C_Timer.After(0, function()
		pending = false
		Refresh()
	end)
end

-- New rows as the list grows: a look each second while a window's up and the
-- page has something to do.
local ticker
local function Tick()
	if not (plan.path or plan.font) then return end
	for _, frame in pairs(windows) do
		local okVisible, visible = pcall(frame.IsVisible, frame)
		if okVisible and visible then
			Refresh()
			return
		end
	end
end

-- For /cine debug meterstyle.
function ns.ReportDamageMeterStyle()
	local list = Refresh()
	local names = {}
	for _, frame in ipairs(list or {}) do names[#names + 1] = frame:GetName() or "?" end
	ns.Log("recolor", ("meter: client %s, combat %s, page %s, theme ring %s, dmFrame %s dmBars %s dmFont %s, " ..
		"texture %s, font %s"):format(tostring(select(4, GetBuildInfo())), tostring(InCombatLockdown()),
		tostring(ns.StyleOn("irStyle")), tostring(ns.ThemeRing() ~= nil), tostring(ns.StyleLook("irStyle").dmFrame),
		tostring(ns.StyleLook("irStyle").dmBars), tostring(ns.StyleLook("irStyle").dmFont), tostring(plan.path),
		tostring(plan.font)))
	ns.Log("recolor", ("meter: %d windows (%s), %d bars, %d texts"):format(counts.windows, table.concat(names, ", "),
		counts.bars, counts.texts))
	if ns.LogTextures then
		for _, frame in ipairs(list or {}) do ns.LogTextures("meter", frame) end
	end
	ns.Print("Damage meter's parts written to the log.")
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" and not ticker then
		ticker = C_Timer.NewTicker(1, Tick)
	end
	if ns.db then ns.RefreshDamageMeterStyle() end
end)
