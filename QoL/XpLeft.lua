-- Quality of life's XP left: the experience bar's words and its tooltip say
-- how much XP is still needed for the next level ("XP: 20212/21300 (1088 left)",
-- "1,088 XP to level 23"). The game's own words, added to: any words under the
-- XP bar's frames (each client's names differ) or tooltip line showing both your
-- XP and the level's total get the rest after them. Off: the game's words alone.

local _, ns = ...
local L = ns.L

-- (Where each client keeps the XP bar's words: retail's manager and its holders,
-- the older clients' bar and the overlay its words sit on.)
local FRAMES = { "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "MainMenuExpBar",
	"MainMenuBarOverlayFrame", "MainMenuBarExpText" }

local function Plain(value, kind)
	if issecretvalue and issecretvalue(value) then return nil end
	return type(value) == kind and value or nil
end

local function Big(number)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(number) or tostring(number)
end

-- Your XP, the level's total and what's left, while there's a next level to earn.
local function Numbers()
	local okCur, cur = pcall(UnitXP, "player")
	local okMax, max = pcall(UnitXPMax, "player")
	cur, max = okCur and Plain(cur, "number"), okMax and Plain(max, "number")
	if not cur or not max or max <= 0 or cur >= max then return nil end
	if IsXPUserDisabled and IsXPUserDisabled() then return nil end
	return cur, max, max - cur
end

-- Do these words show both your XP and the level's total? (Thousands split by
-- commas, dots or spaces or not at all: each number read whole.) And were they
-- split (so ours is written the same way)?
local function Shows(text, cur, max)
	local joined, split = text, false
	for _ = 1, 3 do
		local next, count = joined:gsub("(%d)[,%. \194\160](%d%d%d)", "%1%2")
		if count == 0 then break end
		joined, split = next, true
	end
	local seenCur, seenMax = false, false
	for digits in joined:gmatch("%d+") do
		local number = tonumber(digits)
		if number == cur then seenCur = true end
		if number == max then seenMax = true end
	end
	return seenCur and seenMax, split
end

-- [fontString] = the game's own words last put there
local gameText = {}
local busy = false
local function Dress(text)
	if busy then return end
	local ok, words = pcall(text.GetText, text)
	words = ok and Plain(words, "string")
	if not words then return end
	gameText[text] = words
	if not ns.db or not ns.Setting("xpLeft") then return end
	local cur, max, left = Numbers()
	if not cur then return end
	local shows, split = Shows(words, cur, max)
	if not shows then return end
	busy = true
	pcall(text.SetText, text, words .. " " .. L["(%s left)"]:format(split and Big(left) or tostring(left)))
	busy = false
end

local hooked = {}
local function Hook(text)
	if hooked[text] then return end
	hooked[text] = true
	hooksecurefunc(text, "SetText", Dress)
	if text.SetFormattedText then hooksecurefunc(text, "SetFormattedText", Dress) end
	Dress(text)
end

local function Walk(object, depth, seen)
	if not object or seen[object] or depth > 4 then return end
	seen[object] = true
	if object.IsForbidden and object:IsForbidden() then return end
	if object:GetObjectType() == "FontString" then Hook(object) return end
	for _, region in ipairs({ object:GetRegions() }) do
		if region:GetObjectType() == "FontString" then Hook(region) end
	end
	for _, child in ipairs({ object:GetChildren() }) do Walk(child, depth + 1, seen) end
end

local function Find()
	local seen = {}
	for _, name in ipairs(FRAMES) do
		local frame = _G[name]
		if type(frame) == "table" and frame.GetObjectType then pcall(Walk, frame, 0, seen) end
	end
end

-- The switch flipped: the game's words back, or ours added again.
function ns.RefreshXpLeft()
	for text, words in pairs(gameText) do
		busy = true
		pcall(text.SetText, text, words)
		busy = false
		Dress(text)
	end
end

-- The tooltip over the bar ("20,212 / 21,300 ( 95% )"): a line under it.
local added = false
local function OnTooltip(tip)
	if added or not ns.db or not ns.Setting("xpLeft") then return end
	local cur, max, left = Numbers()
	if not cur then return end
	local okLines, lines = pcall(tip.NumLines, tip)
	lines = okLines and Plain(lines, "number") or 0
	local name = tip:GetName()
	for i = 1, math.min(lines, 3) do
		local line = name and _G[name .. "TextLeft" .. i]
		local ok, words = pcall(function() return line and line:GetText() end)
		words = ok and Plain(words, "string")
		if words and Shows(words, cur, max) then
			added = true
			local level = Plain(UnitLevel("player"), "number")
			tip:AddLine(level and L["%s XP to level %d"]:format(Big(left), level + 1) or L["(%s left)"]:format(Big(left)),
				1, 0.82, 0)
			tip:Show()
			return
		end
	end
end
if GameTooltip then
	hooksecurefunc(GameTooltip, "Show", function(tip) pcall(OnTooltip, tip) end)
	GameTooltip:HookScript("OnHide", function() added = false end)
	pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipCleared", function() added = false end)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function()
	Find()
	C_Timer.After(1, Find) -- (bars some clients build a moment later)
end)
