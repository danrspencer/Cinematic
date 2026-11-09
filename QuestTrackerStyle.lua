-- The quest tracker's part of the Style hub's Interface Recolor page (InterfaceRecolor.lua): the game's quest objective tracker in the
-- theme's look. Its header bars ("All Objectives", "Quests", "Campaign"...) as
-- the theme's panel, its words in the theme's font (General's text font, sizes
-- kept), quest names in the theme's accent color, progress bars in General's
-- bar texture and the fold buttons tinted, as the minimap's buttons are. Only
-- with a theme picked on General.
--
-- WoW Forever and retail (ObjectiveTrackerFrame): the parts are found by what
-- they are, not by name, as the tracker's layout differs between clients and
-- versions. Classic Era's QuestWatchFrame has no headers or bars: its words
-- take the font and color. Everything goes back to the game's own when the
-- page says so. Only looks change: no frame of the tracker's is moved, and its
-- quest item buttons (secure) are left alone.

local ADDON_NAME, ns = ...

local DEFAULTS = ns.DEFAULTS
DEFAULTS.qtHeaders = true -- the header bars as the theme's panel
DEFAULTS.qtFont = true    -- the words in General's text font
DEFAULTS.qtTitles = true  -- quest names in the theme's accent color
DEFAULTS.qtBars = true    -- progress bars in General's texture, the fold buttons tinted

local HEADER_CORNER = 8 -- (the panel shape's corners: a header's short)
local DEPTH = 7 -- (how deep into the tracker its parts are looked for)

local function Look()
	return ns.StyleLook("irStyle")
end

local function Plain(value)
	return not (issecretvalue and issecretvalue(value)) and value or nil
end

-- The theme's color a little brighter for the game's art, which goes darker grey
-- than ours (as MinimapStyle.lua's).
local function Brighter(color)
	local top = math.max(color[1], color[2], color[3], 0.01)
	local lift = math.min(1.25, 1 / top)
	return color[1] * lift, color[2] * lift, color[3] * lift
end

local function Tracker()
	return _G.ObjectiveTrackerFrame or _G.QuestWatchFrame or _G.WatchFrame
end

-- What we've changed, so it goes back: a texture's alpha (hidden), a font
-- string's font, a bar's texture, a texture's tint.
local hidden, fonts, bars, tints = {}, {}, {}, {}
local hooked = {}
local busy = false

local function HideAgain(texture)
	if busy or not hidden[texture] then return end
	busy = true
	texture:SetAlpha(0)
	busy = false
end
local function SetHidden(texture, hide)
	if type(texture) ~= "table" or not texture.SetAlpha then return end
	if hide then
		if not hidden[texture] then
			local alpha = Plain(texture:GetAlpha())
			hidden[texture] = type(alpha) == "number" and alpha or 1
		end
		if not hooked[texture] then
			hooked[texture] = true
			hooksecurefunc(texture, "SetAlpha", HideAgain)
		end
		HideAgain(texture)
	elseif hidden[texture] then
		local alpha = hidden[texture]
		hidden[texture] = nil
		texture:SetAlpha(alpha)
	end
end

-- Quest names: the game's yellow (or its highlight, on the mouse) turned to the
-- theme's accent, as bright as the game's was. Other colors (a failed quest's
-- red...) left as they are.
local titles = {}
local accent -- (the color now, or nil: the game's)
local function Luma(r, g, b) return 0.3 * r + 0.59 * g + 0.11 * b end
local GAME_YELLOW = Luma(0.75, 0.61, 0) -- (the tracker's quest names; on the mouse 1, 0.82, 0)
local function Recolor(text, r, g, b, a)
	if busy or not accent or not titles[text] then return end
	r, g, b = Plain(r), Plain(g), Plain(b)
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
	-- (Gold to yellow, or a light grey to white: the game's own colors for a quest's
	-- name. A red or green it has for a failed or done quest is left as it is.)
	local yellow = r > 0.6 and g > 0.45 and b < 0.35 and r >= g
	local grey = math.max(r, g, b) - math.min(r, g, b) < 0.15 and Luma(r, g, b) > 0.55
	if not (yellow or grey) then return end
	local scale = math.min(1.6, Luma(r, g, b) / GAME_YELLOW)
	local top = math.max(accent[1], accent[2], accent[3], 0.01)
	scale = math.min(scale, 1 / top)
	local nr, ng, nb, na = accent[1] * scale, accent[2] * scale, accent[3] * scale, Plain(a) or 1
	busy = true
	text:SetTextColor(nr, ng, nb, na)
	-- (On WoW Forever a font string's text and vertex color are one: both, or it can stay.)
	if text.SetVertexColor then text:SetVertexColor(nr, ng, nb, na) end
	busy = false
end
-- WoW Forever writes a quest's difficulty color into its name (|cAARRGGBB...|r:
-- gray trivial, green easy, yellow your level, orange and red harder), which no
-- text color overrides. Taken out, so the name's in the theme's color, and kept as
-- a dot of that color in front of it. originals: the name as the game set it.
local DOT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Themes\\Shapes\\PortraitCircleCut"
local originals = {}
local function Accent(text)
	if not accent then return end
	local okColor, r, g, b, a = pcall(text.GetTextColor, text)
	if not okColor then return end
	-- (As bright as the game's color was: brighter on the mouse.)
	local luma = type(Plain(r)) == "number" and Luma(r, Plain(g) or 0, Plain(b) or 0) or GAME_YELLOW
	local top = math.max(accent[1], accent[2], accent[3], 0.01)
	local scale = math.min(1 / top, math.max(1, luma / GAME_YELLOW))
	busy = true
	text:SetTextColor(accent[1] * scale, accent[2] * scale, accent[3] * scale, Plain(a) or 1)
	if text.SetVertexColor then text:SetVertexColor(accent[1] * scale, accent[2] * scale, accent[3] * scale, Plain(a) or 1) end
	busy = false
end
local function Rewrite(text)
	if busy or not accent or not titles[text] then return end
	local okText, raw = pcall(text.GetText, text)
	raw = okText and Plain(raw)
	-- (Already ours: just its color, which the game may have set again.)
	if type(raw) ~= "string" or raw:find("|T", 1, true) then return Accent(text) end
	local hex = raw:match("|c%x%x(%x%x%x%x%x%x)")
	local plain = raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	if hex then
		local okFont, _, size = pcall(text.GetFont, text)
		local dot = math.floor((okFont and Plain(size) or 12) * 0.8 + 0.5)
		plain = ("|T%s:%d:%d:0:0:128:128:0:128:0:128:%d:%d:%d|t %s"):format(DOT, dot, dot,
			tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), plain)
	end
	if plain ~= raw then
		originals[text] = raw
		busy = true
		text:SetText(plain)
		busy = false
	end
	Accent(text)
end
local function MarkTitle(text)
	if titles[text] then return end
	titles[text] = true
	if not hooked[text] then
		hooked[text] = true
		hooksecurefunc(text, "SetTextColor", Recolor)
		if text.SetVertexColor then hooksecurefunc(text, "SetVertexColor", Recolor) end
		hooksecurefunc(text, "SetText", Rewrite)
	end
	Rewrite(text)
end

-- A header's panel: under it (so its words show over it), where its bar was.
local panels = {}
local function DressHeader(header, art, on)
	SetHidden(art, on)
	local panel = panels[header]
	if on and not panel then
		panel = CreateFrame("Frame", nil, header)
		panel:SetFrameLevel(math.max(0, header:GetFrameLevel() - 1))
		panel:SetAllPoints(art)
		panel:EnableMouse(false)
		panel.themeSliceCorner = HEADER_CORNER
		panel.back = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
		panel.back:SetAllPoints()
		panel.edges = ns.MakeStyleEdges(panel, "BORDER")
		panels[header] = panel
	end
	if not panel then return end
	panel:SetShown(on)
	if not on then return end
	local back, edge = ns.ThemePanel()
	back = back or { 0.05, 0.05, 0.06, 0.85 }
	edge = edge or ns.ThemeRing() or { 0.5, 0.5, 0.5, 1 }
	local shaped = ns.DressThemeSlice(panel, back[1], back[2], back[3], back[4] or 1, edge[1], edge[2], edge[3], 1)
	panel.back:SetShown(not shaped)
	panel.edges:SetShown(not shaped)
	if not shaped then
		ns.DressThemeGrain(panel.back)
		panel.back:SetVertexColor(back[1], back[2], back[3], back[4] or 1)
		ns.DressStyleEdges(panel.edges, 1, edge[1], edge[2], edge[3], 1, false)
	end
end

local function SetFontOf(text, file)
	local own = fonts[text]
	if not file then
		if own then
			fonts[text] = nil
			pcall(text.SetFont, text, own[1], own[2], own[3])
		end
		return
	end
	local okFont, nowFile, size, flags = pcall(text.GetFont, text)
	if not (okFont and nowFile and Plain(size)) then return end
	if not own then
		own = { nowFile, size, flags or "" }
		fonts[text] = own
	end
	-- (The game can set its own font again as it reuses a line: its size is then the one to keep.)
	if nowFile ~= file then
		own[1], own[2], own[3] = nowFile, size, flags or ""
		pcall(text.SetFont, text, file, size, flags or "")
	end
end

-- A firm dark shadow under the tracker's words, so they read on bright ground too
-- (snow, sand, a lit wall): the game's is faint. on false: the game's own back.
local shadows = {}
local function SetShadowOf(text, on)
	local own = shadows[text]
	if not on then
		if own then
			shadows[text] = nil
			pcall(text.SetShadowColor, text, own[1], own[2], own[3], own[4])
			pcall(text.SetShadowOffset, text, own[5], own[6])
		end
		return
	end
	if not own then
		local okColor, r, g, b, a = pcall(text.GetShadowColor, text)
		local okOffset, x, y = pcall(text.GetShadowOffset, text)
		if not (okColor and okOffset and Plain(r) and Plain(x)) then return end
		shadows[text] = { r, g, b, a, x, y }
	end
	text:SetShadowColor(0, 0, 0, 1)
	text:SetShadowOffset(1, -1)
end

-- The quest names' color: the theme's ring color, brought up to read as well as the
-- game's gold does on the dark (lighter, then toward white if it's still dim), and
-- unlike the objectives' near-white, so a name stands out from its lines.
local NAME_LUMA = 0.6
-- (A theme whose ring is near grey (Silver Screen, Emberforge, Slate, Moonlit Glade):
-- its color can't stand apart from the objectives' near-white, so its names keep
-- the game's gold, as the game's own look has them.)
local NEUTRAL_SPREAD, GAME_GOLD = 0.2, { 0.75, 0.61, 0 }
local function NameColor(ring)
	local r, g, b = ring[1], ring[2], ring[3]
	if math.max(r, g, b) - math.min(r, g, b) < NEUTRAL_SPREAD then return GAME_GOLD end
	local luma = Luma(r, g, b)
	if luma > 0.01 then
		local lift = math.min(NAME_LUMA / luma, 1 / math.max(r, g, b, 0.01))
		if lift > 1 then r, g, b = r * lift, g * lift, b * lift end
	end
	luma = Luma(r, g, b)
	if luma < NAME_LUMA - 0.1 then
		local toWhite = (NAME_LUMA - 0.1 - luma) / (1 - luma)
		r, g, b = r + (1 - r) * toWhite, g + (1 - g) * toWhite, b + (1 - b) * toWhite
	end
	return { r, g, b }
end

local function SetBarOf(bar, file)
	local own = bars[bar]
	if not file then
		if own then
			bars[bar] = nil
			if own.atlas and bar.SetStatusBarAtlas then
				pcall(bar.SetStatusBarAtlas, bar, own.atlas)
			elseif own.file then
				pcall(bar.SetStatusBarTexture, bar, own.file)
			end
		end
		return
	end
	local fill = bar:GetStatusBarTexture()
	if not own then
		local okAtlas, atlas = pcall(function() return fill and fill.GetAtlas and fill:GetAtlas() end)
		local okFile, path = pcall(function() return fill and fill:GetTexture() end)
		own = { atlas = okAtlas and Plain(atlas) or nil, file = okFile and Plain(path) or nil }
		bars[bar] = own
	end
	-- (Its color is the game's own: only its texture changes.)
	local r, g, b, a = 1, 1, 1, 1
	if fill and fill.GetVertexColor then r, g, b, a = fill:GetVertexColor() end
	bar:SetStatusBarTexture(file)
	fill = bar:GetStatusBarTexture()
	if fill and Plain(r) then fill:SetVertexColor(r, g, b, a) end
end

local function Tint(texture, color)
	if color then
		tints[texture] = true
		texture:SetDesaturated(true)
		texture:SetVertexColor(Brighter(color))
	elseif tints[texture] then
		tints[texture] = nil
		texture:SetDesaturated(false)
		texture:SetVertexColor(1, 1, 1, 1)
	end
end

-- What the page says now, worked out once a pass.
local function Plan()
	local look = Look()
	local ring = ns.StyleOn("irStyle") and ns.ThemeRing()
	if not ring then return nil end
	local db = ns.db
	local font = look.qtFont ~= false and db and ns.StyleFontFile and ns.StyleFontFile(db.styleFont) or nil
	local texture = look.qtBars ~= false and db and ns.StyleTexturePath(db.styleTexture) or nil
	return {
		ring = ring, headers = look.qtHeaders ~= false, font = font, texture = texture,
		buttons = look.qtBars ~= false, accent = look.qtTitles ~= false and NameColor(ring) or nil,
	}
end

local found -- (for /cine debug questtracker: what the last pass found)
local function Each(frame, depth, visit, seen)
	if type(frame) ~= "table" or seen[frame] or not frame.GetObjectType then return end
	seen[frame] = true
	local okForbidden, forbidden = pcall(function() return frame.IsForbidden and frame:IsForbidden() end)
	if okForbidden and forbidden then return end
	visit(frame)
	if depth >= DEPTH or not frame.GetChildren then return end
	local okKids, kids = pcall(function() return { frame:GetChildren() } end)
	for _, kid in ipairs(okKids and kids or {}) do Each(kid, depth + 1, visit, seen) end
end

-- A header: a frame with its words, a fold button and a bar behind them.
local function HeaderArt(frame)
	if not (frame.Text and frame.MinimizeButton) then return nil end
	local art = frame.Background
	if type(art) == "table" and art.GetObjectType and art:GetObjectType() == "Texture" then return art end
end

local function Restyle()
	local tracker = Tracker()
	if type(tracker) ~= "table" then return end
	local plan = Plan()
	accent = plan and plan.accent or nil
	found = { headers = 0, titles = 0, words = 0, bars = 0, buttons = 0 }
	Each(tracker, 0, function(frame)
		local kind = frame:GetObjectType()
		if kind == "StatusBar" then
			found.bars = found.bars + 1
			SetBarOf(frame, plan and plan.texture or nil)
			return
		end
		local art = HeaderArt(frame)
		if art then
			found.headers = found.headers + 1
			DressHeader(frame, art, plan and plan.headers or false)
			local button = frame.MinimizeButton
			for _, region in ipairs({ button:GetRegions() }) do
				if region:GetObjectType() == "Texture" then
					found.buttons = found.buttons + 1
					Tint(region, plan and plan.buttons and plan.ring or nil)
				end
			end
		end
		-- (A quest's name: retail's and Forever's block HeaderText.)
		local title = frame.HeaderText
		if type(title) == "table" and title.GetObjectType and title:GetObjectType() == "FontString" then
			found.titles = found.titles + 1
			if accent then MarkTitle(title) end
			Rewrite(title)
		end
		-- (A header's words: the game's gold too.)
		if art and accent and type(frame.Text) == "table" and frame.Text.GetObjectType
			and frame.Text:GetObjectType() == "FontString" then
			MarkTitle(frame.Text)
			Accent(frame.Text)
		end
		local headerText = art and frame.Text
		local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
		for _, region in ipairs(okRegions and regions or {}) do
			if region:GetObjectType() == "FontString" then
				found.words = found.words + 1
				-- (The theme's font on the headers only: at a quest name's size the narrow and
				-- bold ones crowd their letters, and the game's reads best.)
				SetFontOf(region, region == headerText and plan and plan.font or nil)
				SetShadowOf(region, plan ~= nil)
			end
		end
	end, {})
	-- (Off: the names' color back to the game's on its next update; set it now too.)
	if not accent then
		for text in pairs(titles) do
			if originals[text] then
				busy = true
				text:SetText(originals[text])
				busy = false
			end
			if text.GetText and text:GetText() then text:SetTextColor(0.75, 0.61, 0) end
		end
		titles, originals = {}, {}
	end
end

-- Coalesced: many updates in one frame (a quest log change) restyle once.
local pending = false
local function Soon()
	if pending then return end
	pending = true
	C_Timer.After(0, function()
		pending = false
		local started = debugprofilestop()
		Restyle()
		local took = debugprofilestop() - started
		if took > 10 then ns.Log("style", ("quest tracker pass: %.0f ms"):format(took)) end
	end)
end
ns.RefreshQuestTrackerStyle = Soon -- (a profile switch calls it more than once: one pass)

-- After the game redraws the tracker: whichever of its update functions this
-- client has.
local hookedUpdates = false
local function HookUpdates()
	if hookedUpdates then return end
	hookedUpdates = true
	local tracker = Tracker()
	for _, pair in ipairs({ { tracker, "Update" }, { _G.ObjectiveTrackerManager, "UpdateAll" },
		{ _G.ObjectiveTrackerManager, "UpdateModule" } }) do
		local owner, name = pair[1], pair[2]
		if type(owner) == "table" and type(owner[name]) == "function" then hooksecurefunc(owner, name, Soon) end
	end
	for _, name in ipairs({ "ObjectiveTracker_Update", "QuestWatch_Update", "WatchFrame_Update" }) do
		if type(_G[name]) == "function" then hooksecurefunc(name, Soon) end
	end
	if type(tracker) == "table" and tracker.HookScript then tracker:HookScript("OnShow", Soon) end
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED",
	"SUPER_TRACKING_CHANGED" }) do
	pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		HookUpdates()
		Restyle()
		C_Timer.After(1, Restyle) -- (sections the tracker builds a moment later)
		return
	end
	if ns.StyleOn("irStyle") or next(fonts) or next(panels) then Soon() end
end)

-- For /cine debug questtracker: what this client's tracker has, and our state.
function ns.ReportQuestTrackerStyle()
	local tracker = Tracker()
	print(("Cinematic: Quest Tracker Style: page %s, theme ring %s, accent %s, tracker %s, game %s"):format(
		tostring(ns.StyleOn("irStyle")), tostring(ns.ThemeRing() ~= nil), tostring(ns.ThemeAccent() ~= nil),
		tracker and (tracker:GetName() or "?") or "none", tostring(select(4, GetBuildInfo()))))
	local plan = Plan()
	print(("plan: font %s, texture %s"):format(tostring(plan and plan.font), tostring(plan and plan.texture)))
	Restyle()
	if found then
		print(("found: headers %d, quest names %d, words %d, bars %d, fold button textures %d"):format(
			found.headers, found.titles, found.words, found.bars, found.buttons))
	end
	-- (The first quest names: their words as stored (color codes shown), colors and font.)
	local shown = 0
	print(("accent %s"):format(accent and ("%.2f %.2f %.2f"):format(accent[1], accent[2], accent[3]) or "none"))
	for text in pairs(titles) do
		if shown >= 3 then break end
		shown = shown + 1
		local okText, words = pcall(text.GetText, text)
		local okColor, r, g, b = pcall(text.GetTextColor, text)
		local okVertex, vr, vg, vb = pcall(function() return text:GetVertexColor() end)
		local object = text.GetFontObject and text:GetFontObject()
		local objectName = object and object.GetName and object:GetName()
		local okObject, orr, og, ob = pcall(function() return object:GetTextColor() end)
		print(("  name %q: text %s, vertex %s, font %s %s"):format(
			tostring(okText and Plain(words) and words:gsub("|", "||") or "?"),
			okColor and ("%.2f %.2f %.2f"):format(Plain(r) or -1, Plain(g) or -1, Plain(b) or -1) or "?",
			okVertex and ("%.2f %.2f %.2f"):format(Plain(vr) or -1, Plain(vg) or -1, Plain(vb) or -1) or "?",
			tostring(objectName), okObject and ("%.2f %.2f %.2f"):format(Plain(orr) or -1, Plain(og) or -1, Plain(ob) or -1)
				or "-"))
	end
	-- (The headers' art, to see what each is.)
	if type(tracker) == "table" then
		Each(tracker, 0, function(frame)
			local art = HeaderArt(frame)
			if art then
				local okAtlas, atlas = pcall(function() return art:GetAtlas() end)
				local okText, text = pcall(function() return frame.Text:GetText() end)
				print(("  header %q: art %s%s"):format(tostring(okText and Plain(text)), tostring(okAtlas and atlas),
					panels[frame] and panels[frame]:IsShown() and " (panel)" or ""))
			end
		end, {})
	end
end
