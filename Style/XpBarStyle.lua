-- The Interface Recolor page's XP and reputation bars rows: the game's own
-- experience, reputation and honor bars in the theme's look. Their frames'
-- chrome takes the theme's color (InterfaceRecolor.lua's irStatus group);
-- here, the XP bar's fill in the theme's mana color (the game's own art, tinted)
-- and the words in General's text font. A bar's parts are
-- found by type (its bars, its words), not by name, as SwingTimerStyle.lua's.
-- Everything goes back to the game's own when the page or a row says so.

local _, ns = ...

local DEFAULTS = ns.DEFAULTS
DEFAULTS.xpBars = true -- the XP bar's fill in the theme's mana color
DEFAULTS.xpFont = true -- the words in General's text font

-- (Each client's: retail's manager and its two holders, the older clients' bars.)
local FRAMES = { "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
	"MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar", "HonorWatchBar", "ArtifactWatchBar" }

-- Fonts in a language with letters of its own (Russian, Korean, Chinese) stay
-- the game's: a font of ours has only Latin letters.
local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]

local function Plain(value, kind)
	if issecretvalue and issecretvalue(value) then return nil end
	return type(value) == kind and value or nil
end

-- [frame] = { bars = { StatusBar... }, texts = { { text, fontObject, file, size, flags } } }
local parts = {}
-- [bar] = { fill = its fill we tinted }: the XP bars we've colored
local own = {}
-- (Shared between holders: a bar or words found under two is dressed once.)
local seenAll = {}

local function Parts(frame)
	local found = parts[frame]
	if found then return found end
	found = { bars = {}, texts = {} }
	local seen = {}
	local function Walk(object, depth)
		if seen[object] or depth > 4 then return end
		seen[object] = true
		if object.IsForbidden and object:IsForbidden() then return end
		if object:GetObjectType() == "StatusBar" and not seenAll[object] then
			seenAll[object] = true
			found.bars[#found.bars + 1] = object
		end
		for _, region in ipairs({ object:GetRegions() }) do
			if region:GetObjectType() == "FontString" and not seenAll[region] then
				seenAll[region] = true
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

-- The game's colors, ours to give: they're painted into its own fill art (WoW
-- Forever's XP bar: its fill white, the bar's color never set), so a plain
-- texture of ours came out white, or the bar's unset green. Told by the bar's
-- name: experience (rested blue, else purple), reputation (its standing's), honor.
-- A color's hue turned by degrees (its lightness and strength kept).
local XP_TURN = 40
local function Turned(color, degrees)
	local r, g, b = color[1], color[2], color[3]
	local top, low = math.max(r, g, b), math.min(r, g, b)
	local chroma = top - low
	if chroma < 0.01 then return { r, g, b } end
	local hue
	if top == r then hue = ((g - b) / chroma) % 6 elseif top == g then hue = (b - r) / chroma + 2 else hue = (r - g) / chroma + 4 end
	hue = (hue * 60 + degrees) % 360 / 60
	local x = chroma * (1 - math.abs(hue % 2 - 1))
	local parts = ({ { chroma, x, 0 }, { x, chroma, 0 }, { 0, chroma, x }, { 0, x, chroma }, { x, 0, chroma },
		{ chroma, 0, x } })[math.floor(hue) + 1]
	return { parts[1] + low, parts[2] + low, parts[3] + low }
end
local XP_RESTED, XP_NORMAL, HONOR = { 0, 0.39, 0.88 }, { 0.58, 0, 0.55 }, { 1, 0.24, 0 }
-- (Its kind by its name or its holders' (three up), or for XP by its rested
-- marker, which only the XP bar has: names differ from client to client.)
local function KindOf(bar)
	local object, names = bar, {}
	for _ = 1, 4 do
		if not object then break end
		local ok, name = pcall(function() return object:GetDebugName() end)
		names[#names + 1] = ok and Plain(name, "string") and name:lower() or ""
		if object.ExhaustionTick or object.ExhaustionLevelFillBar then return "xp" end
		local okParent, parent = pcall(object.GetParent, object)
		object = okParent and parent or nil
	end
	local all = table.concat(names, " ")
	if all:find("exp", 1, true) or all:find("xp", 1, true) then return "xp" end
	if all:find("reput", 1, true) then return "rep" end
	if all:find("honor", 1, true) then return "honor" end
	return nil, all
end
local function GameColor(bar)
	local kind = KindOf(bar)
	if kind == "xp" then
		-- (The theme's mana color turned toward violet, as the game's XP is purple by
		-- its blue mana: of the theme, but not the mana bar's own. The game's without one.)
		local theme = ns.ActiveStyleTheme and ns.ActiveStyleTheme()
		-- (A theme's own xp color, where turning its mana didn't suit it: as given.)
		if theme and theme.xp then return { theme.xp[1], theme.xp[2], theme.xp[3], exact = true } end
		if theme and theme.mana then return Turned(theme.mana, XP_TURN) end
		local okRest, rest = pcall(GetRestState)
		return okRest and rest == 1 and XP_RESTED or XP_NORMAL
	elseif kind == "rep" then
		local standing
		if C_Reputation and C_Reputation.GetWatchedFactionData then
			local okData, data = pcall(C_Reputation.GetWatchedFactionData)
			standing = okData and type(data) == "table" and data.reaction
		elseif GetWatchedFactionInfo then
			local okInfo, _, reaction = pcall(GetWatchedFactionInfo)
			standing = okInfo and reaction
		end
		local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing or 4]
		return color and { color.r, color.g, color.b }
	elseif kind == "honor" then
		return HONOR
	end
end
-- The game's own fill kept (its lighter top and all), only turned grey and
-- tinted the theme's mana color. (A flat texture of ours lost that light; one put
-- in its place couldn't always be put back: its atlas unreadable, the whole sheet
-- came back squashed into the bar.) Only the XP bar: the rest (reputation,
-- honor...) can't be told apart well enough, and keep the game's colors.
local busy = false
local barHooked, restedHooked = {}, {}
-- The color as bright as it goes (its strongest part at full), and a dark one
-- for rested XP, the part past your XP the game shades apart.
-- (Rich, not pale: most themes' mana is a soft grey-blue, and pushed to full
-- brightness it read light and washed out, the game's art greyed under it. So a
-- strength of at least VIVID and a brightness of BRIGHT, its hue kept.)
local VIVID, BRIGHT = 0.78, 1
local function Bright(color)
	local r, g, b = color[1], color[2], color[3]
	local top, low = math.max(r, g, b, 0.01), math.min(r, g, b)
	local strength = math.max((top - low) / top, VIVID)
	-- (Each channel's place between the lowest and the highest, kept.)
	local function Channel(c)
		local place = top > low and (c - low) / (top - low) or 1
		return BRIGHT * (1 - strength + strength * place)
	end
	return { Channel(r), Channel(g), Channel(b) }
end
local RESTED_SHADE, LIFT = 0.45, 0.9
-- The rested part: the XP bar's ExhaustionLevelFillBar, on it or a holder.
local function RestedOf(bar)
	local object = bar
	for _ = 1, 3 do
		if not object then return nil end
		local rested = object.ExhaustionLevelFillBar
		if type(rested) == "table" and rested.SetVertexColor then return rested end
		local ok, parent = pcall(object.GetParent, object)
		object = ok and parent or nil
	end
end
-- (A copy of the fill added on top, lighting it: grey and tinted, the game's
-- art came out dark. It follows the fill's cut as the bar fills.)
local function SyncLift(mine)
	if mine.fill and mine.lift then mine.lift:SetTexCoord(mine.fill:GetTexCoord()) end
	if mine.rested and mine.restedLift then mine.restedLift:SetTexCoord(mine.rested:GetTexCoord()) end
end
-- A light copy of src (the same art, grey, added on top in color): made once.
local function Lift(src, lift, color, alpha)
	if not lift then
		local layer, sub = src:GetDrawLayer()
		lift = src:GetParent():CreateTexture(nil, layer or "ARTWORK", nil, math.min(7, (sub or 0) + 1))
		lift:SetBlendMode("ADD")
	end
	local okAtlas, atlas = pcall(function() return src.GetAtlas and src:GetAtlas() end)
	atlas = okAtlas and Plain(atlas, "string")
	if atlas then
		lift:SetAtlas(atlas)
	else
		local okFile, file = pcall(src.GetTexture, src)
		file = okFile and (Plain(file, "string") or Plain(file, "number"))
		if file then lift:SetTexture(file) end
	end
	lift:ClearAllPoints()
	lift:SetAllPoints(src)
	lift:SetDesaturated(true)
	lift:SetVertexColor(color[1], color[2], color[3], alpha)
	lift:SetShown(src:IsShown())
	return lift
end
local function ColorBar(bar)
	local mine = own[bar]
	if not mine or busy then return end
	local fill = bar:GetStatusBarTexture()
	if not fill then return end
	local base = GameColor(bar) or { 1, 1, 1 }
	local color = base.exact and base or Bright(base)
	busy = true
	fill:SetDesaturated(true)
	fill:SetVertexColor(color[1], color[2], color[3], 1)
	mine.lift = Lift(fill, mine.lift, color, LIFT)
	mine.lift:Show()
	mine.fill = fill
	-- (Rested XP the same, darker: its own light too, as its lighter top went.)
	local rested = RestedOf(bar)
	if rested then
		local dark = { color[1] * RESTED_SHADE, color[2] * RESTED_SHADE, color[3] * RESTED_SHADE }
		rested:SetDesaturated(true)
		rested:SetVertexColor(dark[1], dark[2], dark[3], 1)
		mine.rested = rested
		mine.restedLift = Lift(rested, mine.restedLift, dark, LIFT)
		-- (Shown and hidden with it, as you rest and level.)
		if not restedHooked[rested] then
			restedHooked[rested] = true
			for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
				if rested[method] then
					hooksecurefunc(rested, method, function(self)
						local now = own[bar]
						if now and now.restedLift then now.restedLift:SetShown(self:IsShown()) end
					end)
				end
			end
		end
	end
	SyncLift(mine)
	busy = false
end
local function SetBar(bar, on)
	local mine = own[bar]
	if not on or KindOf(bar) ~= "xp" then
		if mine then
			own[bar] = nil
			busy = true
			local fill = bar:GetStatusBarTexture()
			if fill then
				fill:SetDesaturated(false)
				fill:SetVertexColor(1, 1, 1, 1)
			end
			if mine.lift then mine.lift:Hide() end
			if mine.rested then
				mine.rested:SetDesaturated(false)
				mine.rested:SetVertexColor(1, 1, 1, 1)
			end
			if mine.restedLift then mine.restedLift:Hide() end
			busy = false
		end
		return
	end
	if not mine then own[bar] = {} end
	-- (The game colors or swaps its fill as you level or rest: ours again after;
	-- and the light's cut follows the fill's as the bar fills.)
	if not barHooked[bar] then
		barHooked[bar] = true
		for _, method in ipairs({ "SetStatusBarColor", "SetStatusBarTexture", "SetStatusBarAtlas" }) do
			if bar[method] then hooksecurefunc(bar, method, function() ColorBar(bar) end) end
		end
		local function FollowNow()
			local now = own[bar]
			if now then SyncLift(now) end
		end
		-- (The fill's cut can change only as it's next drawn: again a frame later.)
		local function Follow()
			FollowNow()
			C_Timer.After(0, FollowNow)
		end
		if bar.SetValue then hooksecurefunc(bar, "SetValue", Follow) end
		if bar.SetMinMaxValues then hooksecurefunc(bar, "SetMinMaxValues", Follow) end
		if bar.HookScript then bar:HookScript("OnSizeChanged", Follow) end
	end
	ColorBar(bar)
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

local hooked = {}
local function Refresh()
	if not ns.db then return end
	local look = ns.StyleLook("irStyle")
	local on = ns.StyleOn("irStyle") and ns.ThemeRing() ~= nil
	local tint = on and look.xpBars ~= false
	local font = on and ROMAN and look.xpFont ~= false and ns.StyleFontFile and ns.StyleFontFile(ns.db.styleFont) or nil
	for _, name in ipairs(FRAMES) do
		local frame = _G[name]
		if type(frame) == "table" and frame.GetObjectType then
			-- (The game may build or reset its parts as it shows: dressed again then.)
			if not hooked[frame] and frame.HookScript then
				hooked[frame] = true
				frame:HookScript("OnShow", function() ns.RefreshXpBarStyle() end)
			end
			local found = Parts(frame)
			if found then
				for _, bar in ipairs(found.bars) do SetBar(bar, tint) end
				for _, info in ipairs(found.texts) do SetFont(info, font) end
			end
		end
	end
end

-- (Many calls in one frame make one pass; InterfaceRecolor.lua's refresh calls it.)
local pending = false
function ns.RefreshXpBarStyle()
	if pending then return end
	pending = true
	C_Timer.After(0, function()
		pending = false
		Refresh()
	end)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
-- (Rested or not, a reputation's standing: its color again.)
for _, event in ipairs({ "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING", "PLAYER_XP_UPDATE", "UPDATE_FACTION",
	"PLAYER_LEVEL_UP" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event)
	if event ~= "PLAYER_ENTERING_WORLD" then
		for bar in pairs(own) do ColorBar(bar) end
		return
	end
	ns.RefreshXpBarStyle()
	C_Timer.After(1, ns.RefreshXpBarStyle) -- (bars some clients build a moment later)
end)

-- For /cine debug xpbar: each bar found, its kind and colors, to the log.
function ns.ReportXpBarStyle()
	Refresh()
	for frame, found in pairs(parts) do
		local okName, frameName = pcall(function() return frame:GetDebugName() end)
		for _, bar in ipairs(found.bars) do
			local okBar, barName = pcall(function() return bar:GetDebugName() end)
			local kind, names = KindOf(bar)
			local r, g, b = bar:GetStatusBarColor()
			local fill = bar:GetStatusBarTexture()
			local fr, fg, fb = 1, 1, 1
			if fill then fr, fg, fb = fill:GetVertexColor() end
			ns.Log("style", ("xpbar: under %s: %s, kind %s (%s), ours %s, bar color %s %s %s, fill %s %s %s, rest %s"):format(
				tostring(okName and frameName), tostring(okBar and barName), tostring(kind), tostring(names),
				tostring(own[bar] ~= nil), tostring(r), tostring(g), tostring(b), tostring(fr), tostring(fg), tostring(fb),
				tostring(GetRestState and GetRestState())))
		end
	end
	ns.Print("XP bars written to the log.")
end
