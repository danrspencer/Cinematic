-- The game's mirror timer bars (Breath, Fatigue, Feign Death), as the
-- Standard Frames page's Trackers tab says: hidden, their words hidden, their
-- fill's texture, and their words' font and size. (When they show in CineMode
-- is the tab's Breath bars row: Frames.lua.) Classic Era's are MirrorTimer1-3;
-- retail's are made inside MirrorTimerContainer as they're first needed;
-- Forever's are found either way. A timer's parts are found by type (its bar,
-- its words), not by name, so a client that names them otherwise still works.

local _, ns = ...

-- [timer] = { bar, fill, texture, atlas, grey, texts = { { text, fontObject, file, size, flags } } }:
-- the game's own look, read once, to put back.
local timers = {}

-- Fonts in a language with letters of its own (Russian, Korean, Chinese) stay
-- the game's: a font of ours has only Latin letters.
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]

local function Each(fn)
	local seen = {}
	local function Do(timer)
		if timer and not seen[timer] then
			seen[timer] = true
			fn(timer)
		end
	end
	for i = 1, 3 do Do(_G["MirrorTimer" .. i]) end
	local container = _G.MirrorTimerContainer
	if container and container.GetChildren then
		for _, child in ipairs({ container:GetChildren() }) do Do(child) end
	end
end

local function Plain(value, kind)
	return type(value) == kind and value or nil
end

local function Parts(timer)
	local parts = timers[timer]
	if parts then return parts end
	parts = { texts = {} }
	local function Texts(frame)
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:GetObjectType() == "FontString" then
				local file, size, flags = region:GetFont()
				parts.texts[#parts.texts + 1] = { region, region:GetFontObject(), Plain(file, "string"),
					Plain(size, "number"), Plain(flags, "string") }
			end
		end
	end
	Texts(timer)
	if timer:GetObjectType() == "StatusBar" then parts.bar = timer end
	for _, child in ipairs({ timer:GetChildren() }) do
		if child:GetObjectType() == "StatusBar" then
			parts.bar = parts.bar or child
			Texts(child)
		end
	end
	local fill = parts.bar and parts.bar:GetStatusBarTexture()
	if fill then
		parts.fill = fill
		parts.atlas = fill.GetAtlas and Plain(fill:GetAtlas(), "string")
		parts.texture = parts.atlas or fill:GetTexture()
		parts.grey = fill.IsDesaturated and fill:IsDesaturated() == true or false
	end
	timers[timer] = parts
	return parts
end

-- The words' font: the game's, or one picked; scale on top (1: as is).
local function StyleText(entry, font, scale)
	local text, object, file, size, flags = entry[1], entry[2], entry[3], entry[4], entry[5]
	local words = text:GetText()
	local picked = ROMAN and font and font ~= "game" and ns.StyleFontFile and ns.StyleFontFile(font)
	if picked and size then
		text:SetFont(picked, size * scale, flags or "")
	else
		-- (The game's own: its font object back, which keeps its other alphabets.)
		if object then
			text:SetFontObject(object)
		elseif file and size then
			text:SetFont(file, size, flags or "")
		end
		if text.SetTextScale then
			text:SetTextScale(scale)
		elseif scale ~= 1 and file and size then
			text:SetFont(file, size * scale, flags or "")
		end
	end
	if picked and text.SetTextScale then text:SetTextScale(1) end
	-- (Set again after the swap, so the game picks the right alphabet.)
	if type(words) == "string" then text:SetText(words) end
end

-- The settings, as the Standard Frames page's switch leaves them: off, the
-- game's own look (no texture, font or size of ours, nothing hidden).
local GAME_LOOK = {}
local function Settings()
	local db = ns.GetDB()
	if not db then return nil end
	if not (db.enabled and ns.PageOn("handleFrames")) then return GAME_LOOK end
	return db
end

local function Style(timer)
	local db = Settings()
	if not db then return end
	local parts = Parts(timer)
	if parts.bar then
		local value = db.mirrorTexture
		if not (value and value ~= "game" and ns.SetBarTexture and ns.SetBarTexture(parts.bar, value)) then
			if parts.texture and parts.styled then
				parts.bar:SetStatusBarTexture(parts.texture)
				local fill = parts.bar:GetStatusBarTexture()
				if fill and fill.SetDesaturated then fill:SetDesaturated(parts.grey) end
			end
			parts.styled = nil
		else
			parts.styled = true
		end
	end
	local scale = tonumber(db.mirrorTextScale) or 1
	for _, entry in ipairs(parts.texts) do
		StyleText(entry, db.mirrorFont, scale)
		entry[1]:SetAlpha(db.mirrorHideText and 0 or 1)
	end
end

-- (Hidden as each comes up: the bar's row fades the same frames in CineMode,
-- so hiding is Hide, not an alpha of ours.)
local hooked = {}
local function Hook(timer)
	if hooked[timer] then return end
	hooked[timer] = true
	timer:HookScript("OnShow", function(self)
		ns.Guard(function()
			local db = Settings()
			if db and db.mirrorHide then
				self:Hide()
			else
				Style(self)
			end
		end)
	end)
end

-- Every timer made so far, as the settings say now. (One turned back on
-- shows with the next breath, fatigue or Feign Death.)
function ns.ApplyMirrorTimers()
	local db = Settings()
	if not db then return end
	Each(function(timer)
		Hook(timer)
		Style(timer)
		if db.mirrorHide then timer:Hide() end
	end)
end

-- /cine debug mirror: each timer, its parts and the settings.
function ns.ReportMirrorTimers()
	local db = ns.GetDB() or {}
	ns.Print(("Mirror timers: hide %s, hide text %s, texture %s, font %s, size %s; %s, %s"):format(
		tostring(db.mirrorHide), tostring(db.mirrorHideText), tostring(db.mirrorTexture), tostring(db.mirrorFont),
		tostring(db.mirrorTextScale), ns.isRetail and "retail" or "not retail",
		InCombatLockdown() and "in combat" or "calm"))
	local count = 0
	Each(function(timer)
		count = count + 1
		local parts = Parts(timer)
		ns.Print(("  %s (%s): bar %s, fill %s, %d text(s)%s"):format(tostring(timer:GetName() or "unnamed"),
			timer:GetObjectType(), parts.bar and tostring(parts.bar:GetName() or "unnamed") or "none",
			tostring(parts.texture), #parts.texts, parts.texts[1] and (" \"" ..
			tostring(parts.texts[1][1]:GetText()) .. "\" " .. tostring(parts.texts[1][3])) or ""))
	end)
	if count == 0 then
		ns.Print("  none made yet (retail makes them the first time one is needed: hold your breath underwater)")
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MIRROR_TIMER_START")
events:SetScript("OnEvent", function()
	-- (A moment later: retail makes the timer as it handles the same event.)
	C_Timer.After(0, function() ns.Guard(ns.ApplyMirrorTimers) end)
end)
