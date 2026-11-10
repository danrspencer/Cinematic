-- The Interface Recolor page's Swing timer rows: the game's own swing timer
-- (Classic clients: main hand, off hand and ranged bars) in the theme's look.
-- Its frame's chrome takes the theme's color (InterfaceRecolor.lua's swFrame
-- group); here, the fill in General's bar texture (the game's color kept: each
-- weapon's bar keeps its own) and the words in General's text font. A bar's
-- parts are found by type (its bar, its words), not by name, as
-- MirrorTimerStyle.lua's. Everything goes back to the game's own when the page
-- or a row says so. (When the bars show: the Swing timer page, Frames.lua.)

local _, ns = ...

local DEFAULTS = ns.DEFAULTS
DEFAULTS.swFrame = true -- the bars' frames in the theme's color (InterfaceRecolor.lua)
DEFAULTS.swBars = true  -- the fill in General's bar texture
DEFAULTS.swFont = true  -- the words in General's text font

ns.SWING_BAR_NAMES = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }

-- Fonts in a language with letters of its own (Russian, Korean, Chinese) stay
-- the game's: a font of ours has only Latin letters.
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]

local function Plain(value, kind)
	if issecretvalue and issecretvalue(value) then return nil end
	return type(value) == kind and value or nil
end

-- [frame] = { bars = { StatusBar... }, texts = { { text, fontObject, file, size, flags } } }
local parts = {}
-- [bar] = { atlas, file }: its fill's own, read once, to put back.
local own = {}

local function Parts(frame)
	local found = parts[frame]
	if found then return found end
	found = { bars = {}, texts = {} }
	local seen = {}
	local function Walk(object, depth)
		if seen[object] or depth > 3 then return end
		seen[object] = true
		if object:GetObjectType() == "StatusBar" then found.bars[#found.bars + 1] = object end
		for _, region in ipairs({ object:GetRegions() }) do
			if region:GetObjectType() == "FontString" then
				local file, size, flags = region:GetFont()
				found.texts[#found.texts + 1] = { region, region:GetFontObject(), Plain(file, "string"),
					Plain(size, "number"), Plain(flags, "string") }
			end
		end
		for _, child in ipairs({ object:GetChildren() }) do Walk(child, depth + 1) end
	end
	local ok = pcall(Walk, frame, 0)
	if not ok then return nil end
	parts[frame] = found
	return found
end

local function SetBar(bar, path, atlas)
	local mine = own[bar]
	if not path then
		if mine then
			own[bar] = nil
			if mine.atlas and bar.SetStatusBarAtlas then
				pcall(bar.SetStatusBarAtlas, bar, mine.atlas)
			elseif mine.file then
				pcall(bar.SetStatusBarTexture, bar, mine.file)
			end
		end
		return
	end
	local fill = bar:GetStatusBarTexture()
	if not mine then
		local okAtlas, oldAtlas = pcall(function() return fill and fill.GetAtlas and fill:GetAtlas() end)
		local okFile, oldFile = pcall(function() return fill and fill:GetTexture() end)
		own[bar] = { atlas = okAtlas and Plain(oldAtlas, "string") or nil,
			file = okFile and (Plain(oldFile, "string") or Plain(oldFile, "number")) or nil }
	end
	-- (Its color is the game's own: only its texture changes.)
	local r, g, b, a = 1, 1, 1, 1
	if fill and fill.GetVertexColor then r, g, b, a = fill:GetVertexColor() end
	if atlas and bar.SetStatusBarAtlas then
		pcall(bar.SetStatusBarAtlas, bar, path)
	else
		pcall(bar.SetStatusBarTexture, bar, path)
	end
	fill = bar:GetStatusBarTexture()
	if fill and Plain(r, "number") then fill:SetVertexColor(r, g, b, a) end
end

local function SetFont(info, file)
	local text, fontObject, oldFile, size, flags = info[1], info[2], info[3], info[4], info[5]
	if file and size then
		text:SetFont(file, size, flags or "")
	elseif fontObject then
		text:SetFontObject(fontObject)
	elseif oldFile and size then
		text:SetFont(oldFile, size, flags or "")
	end
end

local counts = { bars = 0, texts = 0 }
local hooked = {}
local function Refresh()
	if ns.isRetail or not ns.db then return end
	local look = ns.StyleLook("irStyle")
	local on = ns.StyleOn("irStyle") and ns.ThemeRing() ~= nil
	local path, atlas
	if on and look.swBars ~= false then path, atlas = ns.StyleTexturePath(ns.db.styleTexture) end
	local font = on and ROMAN and look.swFont ~= false and ns.StyleFontFile and ns.StyleFontFile(ns.db.styleFont) or nil
	counts.bars, counts.texts = 0, 0
	for _, name in ipairs(ns.SWING_BAR_NAMES) do
		local frame = _G[name]
		if type(frame) == "table" and frame.GetObjectType then
			-- (The game may build or reset its parts as it shows: dressed again then.)
			if not hooked[frame] and frame.HookScript then
				hooked[frame] = true
				frame:HookScript("OnShow", function() ns.RefreshSwingTimerStyle() end)
			end
			local found = Parts(frame)
			if found then
				for _, bar in ipairs(found.bars) do
					SetBar(bar, path, atlas)
					if path then counts.bars = counts.bars + 1 end
				end
				for _, info in ipairs(found.texts) do
					SetFont(info, font)
					if font then counts.texts = counts.texts + 1 end
				end
			end
		end
	end
end

-- (Many calls in one frame make one pass; InterfaceRecolor.lua's refresh calls it.)
local pending = false
function ns.RefreshSwingTimerStyle()
	if pending or ns.isRetail then return end
	pending = true
	C_Timer.After(0, function()
		pending = false
		Refresh()
	end)
end

-- For /cine debug recolor.
function ns.ReportSwingTimerStyle()
	if ns.isRetail then return end
	Refresh()
	local present = {}
	for _, name in ipairs(ns.SWING_BAR_NAMES) do
		if type(_G[name]) == "table" then present[#present + 1] = name end
	end
	print(("  swing timer: %d bars textured, %d texts in our font; frames %s"):format(counts.bars, counts.texts,
		#present > 0 and table.concat(present, ", ") or "none"))
end

if not ns.isRetail then
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:SetScript("OnEvent", function()
		ns.RefreshSwingTimerStyle()
		C_Timer.After(1, ns.RefreshSwingTimerStyle)
	end)
end
