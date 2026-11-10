-- The Style hub's Interface Recolor page: the rest of the game's interface in the
-- theme's color, by the same simple means as the minimap's ring: the game's own
-- art turned grey and tinted with the theme's ring color. Only a frame's chrome
-- (its borders, edges, corners, tabs and headers) is tinted; icons, backgrounds,
-- bar fills, highlights and glows keep the game's colors. Groups: chat, buffs,
-- XP and reputation bars, the menu and bag buttons, your cast bar, small windows
-- (popups, loot, ready check, the game menu) and big windows (bags, character,
-- spellbook, quest log, map, merchant...). Only with a theme picked on General.
--
-- A frame's chrome is told by its art's name (an atlas, a file, or the texture's
-- own name or parentKey): there's no list of every texture. Windows that load
-- later (the big ones are their own Blizzard addons) are dressed as they show.
-- Only colors change: nothing is moved, and secure frames stay untouched in what
-- they do. Everything goes back to the game's own when the page says so.

local _, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.irStyle = true -- the page's switch
DEFAULTS.irChat = true
DEFAULTS.irBuffs = true
DEFAULTS.irStatus = true
DEFAULTS.irMicro = true
DEFAULTS.irCast = true
DEFAULTS.irSmall = true
DEFAULTS.irBig = true
DEFAULTS.irBarArt = true

local DEPTH = 5 -- (how deep into a frame its art is looked for)

-- Each group: its setting, and its frames by name (whichever this client has).
-- all: every texture in it counts, not just its chrome (none now: the menu
-- buttons' pictures, tinted whole, came out one flat color).
local function Numbered(prefix, from, to, suffix)
	local list = {}
	for i = from, to do list[#list + 1] = prefix .. i .. (suffix or "") end
	return list
end
local function Join(...)
	local list = {}
	for i = 1, select("#", ...) do
		local part = select(i, ...)
		if type(part) == "table" then
			for _, name in ipairs(part) do list[#list + 1] = name end
		else
			list[#list + 1] = part
		end
	end
	return list
end
-- Action bar 1's art: its end caps (the gryphons or wyverns) and the band its
-- buttons sit on, by name on older clients and by parentKey on newer ones (as
-- Frames.lua's bar art row has them). Pictures through and through: tinted whole.
local function BarArt()
	local list = {}
	for _, name in ipairs({ "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarArtFrameBackground",
		"MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3" }) do
		if type(_G[name]) == "table" then list[#list + 1] = _G[name] end
	end
	for bar, keys in pairs({ MainMenuBarArtFrame = { "LeftEndCap", "RightEndCap" },
		MainMenuBar = { "EndCaps", "BorderArt" }, MainActionBar = { "EndCaps", "BorderArt" } }) do
		local frame = _G[bar]
		if type(frame) == "table" then
			for _, key in ipairs(keys) do
				if type(frame[key]) == "table" then list[#list + 1] = frame[key] end
			end
		end
	end
	return list
end
ns.ActionBarArt = BarArt

local GROUPS = {
	{ key = "irBarArt", all = true, metal = true, get = BarArt },
	{ key = "irChat", names = Join(Numbered("ChatFrame", 1, 10, "Tab"), Numbered("ChatFrame", 1, 10, "EditBox"),
		Numbered("ChatFrame", 1, 10, "ButtonFrame"), "GeneralDockManager", "ChatFrameMenuButton",
		"ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton") },
	{ key = "irBuffs", names = { "BuffFrame", "TemporaryEnchantFrame" } },
	{ key = "irStatus", names = { "StatusTrackingBarManager", "MainStatusTrackingBarContainer",
		"SecondaryStatusTrackingBarContainer", "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar" } },
	{ key = "irMicro", names = Join({ "MicroMenu", "MicroMenuContainer", "MicroButtonAndBagsBar", "BagsBar",
		"MainMenuBarBackpackButton", "CharacterReagentBag0Slot", "MainMenuBarPerformanceBar" },
		Numbered("CharacterBag", 0, 3, "Slot")) },
	{ key = "irCast", names = { "PlayerCastingBarFrame", "CastingBarFrame" } },
	-- (The damage meter's windows; its bars and words: DamageMeterStyle.lua.)
	{ key = "dmFrame", get = function() return ns.DamageMeterWindows and ns.DamageMeterWindows() or {} end },
	-- (The swing timer's frames; its fill and words: SwingTimerStyle.lua.)
	{ key = "swFrame", names = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" } },
	{ key = "irSmall", names = Join(Numbered("StaticPopup", 1, 4), { "LootFrame", "ReadyCheckFrame", "GameMenuFrame",
		"QueueStatusButton", "QueueStatusFrame", "LFGDungeonReadyDialog", "RolePollPopup", "GroupLootContainer" }) },
	{ key = "irBig", names = Join(Numbered("ContainerFrame", 1, 13), { "ContainerFrameCombinedBags", "BankFrame",
		"CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "PlayerTalentFrame", "TalentFrame", "QuestLogFrame",
		"QuestMapFrame", "WorldMapFrame", "MerchantFrame", "FriendsFrame", "GossipFrame", "QuestFrame", "MailFrame",
		"TradeFrame", "AuctionHouseFrame", "AuctionFrame", "CollectionsJournal", "EncounterJournal", "PVEFrame",
		"AchievementFrame", "ProfessionsFrame", "TradeSkillFrame", "ClassTrainerFrame", "InspectFrame",
		"CommunitiesFrame", "GuildFrame", "DressUpFrame", "TabardFrame", "TaxiFrame", "LFGParentFrame",
		"HonorFrame", "WorldStateScoreFrame", "PVPFrame", "MacroFrame", "KeyBindingFrame", "TimeManagerFrame",
		"CalendarFrame", "ItemSocketingFrame", "ItemUpgradeFrame", "ScrappingMachineFrame" }) },
}

-- The words that make a texture chrome, and the ones that make it something else
-- (looked for in its atlas, file or own name, lowercase).
-- (A button's frame drawn as one picture: the action and bag buttons' IconFrame,
-- which says icon but is the frame round one.)
local FRAME_ART = { "iconframe" }
local CHROME = { "border", "edge", "corner", "nineslice", "tab", "divider", "bevel", "header", "title", "trim",
	"ring", "metal", "frame", "rim", "bracket", "filigree", "button-up", "button-down", "closebutton" }
local NOT_CHROME = { "icon", "portrait", "model", "highlight", "glow", "flash", "bg", "background", "inset",
	"fill", "spark", "shadow", "mask", "swipe", "cooldown", "check", "parchment", "texture", "debuff" }
-- (The three pieces of a tab or a box you type in, by their own names alone.)
local PIECES = { left = true, right = true, mid = true, middle = true, selectedleft = true, selectedright = true,
	selectedmiddle = true, activeleft = true, activeright = true, activemiddle = true }

local function Plain(value)
	return not (issecretvalue and issecretvalue(value)) and value or nil
end

-- The theme's color a little brighter for the game's art (as MinimapStyle.lua's).
local function Brighter(color)
	local top = math.max(color[1], color[2], color[3], 0.01)
	local lift = math.min(1.25, 1 / top)
	return color[1] * lift, color[2] * lift, color[3] * lift
end

local function Has(name, words)
	for _, word in ipairs(words) do
		if name:find(word, 1, true) then return true end
	end
	return false
end

-- A texture's own name: its last part (a parentKey, or a global name with its
-- frame's name taken off its front: ChatFrame1TabLeft -> left).
local function OwnName(region)
	local okName, name = pcall(function() return region.GetDebugName and region:GetDebugName() end)
	name = okName and Plain(name)
	if type(name) ~= "string" then return "", "" end
	local last = name:match("([^%.]+)$") or name
	local okParent, parent = pcall(function() return region:GetParent():GetName() end)
	parent = okParent and Plain(parent)
	if type(parent) == "string" and last:sub(1, #parent) == parent then last = last:sub(#parent + 1) end
	return last:lower(), name:lower()
end

local function IsChrome(region, all)
	local okFile, file = pcall(region.GetTexture, region)
	file = okFile and Plain(file)
	if type(file) == "string" and file:lower():find("\\icons\\", 1, true) then return false end
	-- (A status bar's fill keeps its color: it says something.)
	local parent = region:GetParent()
	if parent and parent.GetStatusBarTexture and parent:GetStatusBarTexture() == region then return false end
	if all then return true end
	local okAtlas, atlas = pcall(function() return region.GetAtlas and region:GetAtlas() end)
	atlas = okAtlas and Plain(atlas)
	local own, full = OwnName(region)
	-- (A debuff's border says what kind it is.)
	if full:find("debuff", 1, true) then return false end
	if full:find("nineslice", 1, true) then return not Has(own, NOT_CHROME) end
	-- (Only a tab's or an edit box's: a button's three pieces are its face, which the
	-- game shades in parts, and tinted they come out patchy.)
	if PIECES[own] then
		local okKind, kind = pcall(function() return parent:GetObjectType() end)
		local okParent, parentName = pcall(function() return parent:GetDebugName() end)
		parentName = okParent and type(Plain(parentName)) == "string" and parentName:lower() or ""
		return (okKind and kind == "EditBox") or parentName:find("tab", 1, true) ~= nil
	end
	for _, name in ipairs({ type(atlas) == "string" and atlas:lower() or "", type(file) == "string" and file:lower() or "",
		own }) do
		if name ~= "" and Has(name, FRAME_ART) and not name:find("highlight", 1, true) then return true end
		if name ~= "" and Has(name, CHROME) and not Has(name, NOT_CHROME) then return true end
	end
	return false
end

-- What we've tinted, and the game setting its color again over ours.
local tinted, hooked = {}, {}
local busy = false
local function Apply(texture)
	local color = tinted[texture]
	if not color then return end
	busy = true
	texture:SetDesaturated(true)
	texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	busy = false
end
local function Again(texture)
	if busy or not tinted[texture] then return end
	-- (Keeps the alpha the game gave it: a tab fades, a button greys.)
	local okColor, _, _, _, a = pcall(texture.GetVertexColor, texture)
	if okColor and type(Plain(a)) == "number" then tinted[texture][4] = a end
	Apply(texture)
end
local function Tint(texture, color, groupKey)
	if color then
		local okColor, _, _, _, a = pcall(texture.GetVertexColor, texture)
		tinted[texture] = { color[1], color[2], color[3], okColor and Plain(a) or 1, group = groupKey }
		if not hooked[texture] then
			hooked[texture] = true
			hooksecurefunc(texture, "SetVertexColor", Again)
			hooksecurefunc(texture, "SetDesaturated", Again)
		end
		Apply(texture)
	elseif tinted[texture] then
		local alpha = tinted[texture][4] or 1
		tinted[texture] = nil
		busy = true
		texture:SetDesaturated(false)
		texture:SetVertexColor(1, 1, 1, alpha)
		busy = false
	end
end

-- (A forbidden frame (the trade window's money boxes...) can't even be asked what
-- it is: that's checked first, and every question after it asked safely.)
local function Kind(object)
	local okForbidden, forbidden = pcall(function() return object.IsForbidden and object:IsForbidden() end)
	if not okForbidden or forbidden then return nil end
	local ok, kind = pcall(object.GetObjectType, object)
	return ok and kind or nil
end
local function Each(frame, depth, visit, seen)
	if type(frame) ~= "table" or seen[frame] or not frame.GetObjectType then return end
	seen[frame] = true
	local kind = Kind(frame)
	if not kind then return end
	if kind == "Texture" then return visit(frame) end
	local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
	for _, region in ipairs(okRegions and regions or {}) do
		if Kind(region) == "Texture" then visit(region) end
	end
	if depth >= DEPTH or not frame.GetChildren then return end
	local okKids, kids = pcall(function() return { frame:GetChildren() } end)
	for _, kid in ipairs(okKids and kids or {}) do Each(kid, depth + 1, visit, seen) end
end

-- A group's color now, or nil: the game's.
local function ColorOf(group)
	local ring = ns.StyleOn("irStyle") and ns.ThemeRing()
	if not ring or ns.StyleLook("irStyle")[group.key] == false then return nil end
	return { Brighter(ring) }
end

-- The bar's end caps as a statue's metal, not painted in the theme's color (which
-- read as plastic: one hue from shadow to highlight). Each theme's metal, and over
-- it a copy of the art added on (ADD) in a pale glint of the theme's color, which
-- lifts the highlights far more than the shadows: dark recesses, bright edges.
local BAR_METALS = {
	reel = { 0.74, 0.75, 0.78 }, codex = { 0.82, 0.64, 0.34 },
	-- (Blackened iron, its edges glowing as if fresh from the fire.)
	forge = { 0.34, 0.3, 0.28, glint = 0.85, shine = 0.7 },
	glade = { 0.6, 0.66, 0.63 }, rime = { 0.6, 0.67, 0.76 }, vanguard = { 0.46, 0.45, 0.47, glint = 0.15 },
	hearth = { 0.7, 0.53, 0.33 }, cathedral = { 0.8, 0.66, 0.38 }, rune = { 0.52, 0.57, 0.55 },
	fel = { 0.36, 0.38, 0.34 }, void = { 0.4, 0.38, 0.47 },
}
local GLINT = 0.45 -- (the added copy's strength)
local GLINT_TINT = 0.45 -- (how much of the theme's color is in it; a metal can say less: a strong red read pink)
local function MetalOf()
	local theme = ns.ActiveStyleTheme and ns.ActiveStyleTheme()
	local metal = theme and BAR_METALS[theme.key]
	if metal then return metal end
	-- (A theme without one: a grey with a little of its color.)
	local ring = ns.ThemeRing() or { 0.6, 0.6, 0.6 }
	return { 0.45 + ring[1] * 0.2, 0.45 + ring[2] * 0.2, 0.45 + ring[3] * 0.2 }
end
local glints, isGlint = {}, {}
local function Glint(texture, color)
	local glint = glints[texture]
	if not color then
		if glint then glint:Hide() end
		return
	end
	if not glint then
		local layer, sub = texture:GetDrawLayer()
		glint = texture:GetParent():CreateTexture(nil, layer or "ARTWORK", nil, math.min(7, (sub or 0) + 1))
		glint:SetAllPoints(texture)
		glint:SetBlendMode("ADD")
		glints[texture] = glint
		isGlint[glint] = true -- (ours: never taken for the game's art)
		-- (Gone with it: faded, hidden, or taken off by the Overrides tab.)
		hooksecurefunc(texture, "SetAlpha", function(_, alpha)
			if type(Plain(alpha)) == "number" then glint:SetAlpha(alpha) end
		end)
		hooksecurefunc(texture, "Hide", function() glint:Hide() end)
		hooksecurefunc(texture, "Show", function() if glints[texture] and glint.on then glint:Show() end end)
	end
	local okAtlas, atlas = pcall(function() return texture:GetAtlas() end)
	atlas = okAtlas and Plain(atlas)
	if type(atlas) == "string" then
		glint:SetAtlas(atlas)
	else
		local okFile, file = pcall(texture.GetTexture, texture)
		if not (okFile and Plain(file)) then return glint:Hide() end
		glint:SetTexture(file)
		glint:SetTexCoord(texture:GetTexCoord())
	end
	glint:SetDesaturated(true)
	glint:SetVertexColor(color[1], color[2], color[3], color.shine or GLINT)
	glint.on = true
	local okAlpha, alpha = pcall(texture.GetAlpha, texture)
	glint:SetAlpha(okAlpha and Plain(alpha) or 1)
	glint:SetShown(texture:IsShown())
end

local counts = {} -- (for /cine debug recolor: textures tinted per group)
-- What a frame's walk found to be chrome, kept: a theme switch only changes the
-- color, so it repaints these without walking again (a walk through every window
-- cost a quarter of a second). walk: look through it again (it's just opened:
-- the game may have built new parts in it).
local found = setmetatable({}, { __mode = "k" })
local function DressFrame(frame, group, color, walk)
	local count = 0
	-- (The bar's end caps: metal with a glint, not the color.)
	local metal, glint
	if color and group.metal then
		metal = MetalOf()
		local ring = ns.ThemeRing() or metal
		local share = metal.glint or GLINT_TINT
		glint = { 1 - share + ring[1] * share, 1 - share + ring[2] * share, 1 - share + ring[3] * share,
			shine = metal.shine }
	end
	local list = found[frame]
	if walk or not list then
		list = {}
		Each(frame, 0, function(texture)
			if not isGlint[texture] and IsChrome(texture, group.all) then list[#list + 1] = texture end
		end, {})
		found[frame] = list
	end
	for _, texture in ipairs(list) do
		if color then
			Tint(texture, metal or color, group.key)
			if group.metal then Glint(texture, glint) end
			count = count + 1
		else
			Tint(texture, nil)
			if group.metal then Glint(texture, nil) end
		end
	end
	return count
end

-- Each frame dressed again as it shows: windows the game rebuilds, bags it fills.
local watched = {}
local function Watch(frame, group)
	if watched[frame] or not frame.HookScript then return end
	watched[frame] = group
	frame:HookScript("OnShow", function(self)
		local color = ColorOf(group)
		if color then DressFrame(self, group, color, true) end
	end)
end

-- (Cheap enough for a profile switch, which calls it more than once: a group that's
-- off only undoes what it tinted, and a window that's closed isn't looked through,
-- as it's dressed when it opens (Watch).)
-- (Visible, not just shown: a window's parts say shown inside a closed window.)
local function Shown(frame)
	local ok, shown = pcall(frame.IsVisible, frame)
	return not ok or Plain(shown) ~= false
end
-- The menu buttons' edges (the irMicro row). Newer clients draw each button as
-- one picture, its gold edge and its icon together (UI-HUD-MicroMenu-*), so the
-- picture isn't tinted: a copy of it, grey and in the theme's color, goes over
-- it, cut to its edge by the square frame mask (as MinimapStyle.lua's calendar).
-- The edge is mostly the button's background (ButtonBG, behind the icon); the
-- icon art's copy follows the button's state (up, pressed, disabled); one in its
-- HIGHLIGHT layer covers the mouseover art, which the game shows on hover; the
-- character button's own edge is its portrait's shadow.
local MICRO_HOLDERS = { "MicroMenu", "MicroMenuContainer", "MicroButtonAndBagsBar" }
local micro = {} -- [button] = { state, hover, extra = { [texture] = copy } }
local microColor
local function MicroButtons()
	local list, seen = {}, {}
	for _, holder in ipairs(MICRO_HOLDERS) do
		local frame = _G[holder]
		if type(frame) == "table" and frame.GetChildren then
			for _, kid in ipairs({ frame:GetChildren() }) do
				local okName, name = pcall(kid.GetName, kid)
				if okName and type(name) == "string" and name:find("MicroButton$") and not seen[kid] then
					seen[kid] = true
					list[#list + 1] = kid
				end
			end
		end
	end
	return list
end
local function AtlasOf(texture)
	if not texture then return nil end
	local ok, atlas = pcall(function() return texture:GetAtlas() end)
	atlas = ok and Plain(atlas)
	if type(atlas) == "string" and atlas:find("^UI%-HUD%-MicroMenu%-") then return atlas end
end
local function MicroCopy(button, layer, sub)
	local copy = button:CreateTexture(nil, layer, nil, sub)
	copy.mask = button:CreateMaskTexture()
	copy.mask:SetTexture(ns.THEME_SQUARE_FRAME_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	copy:AddMaskTexture(copy.mask)
	isGlint[copy] = true -- (ours: never taken for the game's art)
	copy:Hide()
	return copy
end
local function Lay(copy, art, atlas)
	if not (microColor and art and atlas) then return copy:Hide() end
	copy:ClearAllPoints()
	copy:SetAllPoints(art)
	copy.mask:ClearAllPoints()
	copy.mask:SetAllPoints(art)
	copy:SetAtlas(atlas)
	copy:SetDesaturated(true)
	copy:SetVertexColor(microColor[1], microColor[2], microColor[3], 1)
	copy:Show()
end
-- The art the button shows now: disabled, pressed or up.
local function SyncMicro(button)
	local parts = micro[button]
	if not parts then return end
	local art
	local okEnabled, enabled = pcall(button.IsEnabled, button)
	local okState, state = pcall(button.GetButtonState, button)
	if okEnabled and Plain(enabled) == false then
		art = button.GetDisabledTexture and button:GetDisabledTexture()
	elseif okState and Plain(state) == "PUSHED" then
		art = button.GetPushedTexture and button:GetPushedTexture()
	end
	art = art or (button.GetNormalTexture and button:GetNormalTexture())
	Lay(parts.state, art, AtlasOf(art))
	local hover = button.GetHighlightTexture and button:GetHighlightTexture()
	Lay(parts.hover, hover, AtlasOf(hover))
	for texture, copy in pairs(parts.extra) do
		local okShown, shown = pcall(texture.IsShown, texture)
		Lay(copy, (not okShown or Plain(shown) ~= false) and texture or nil, AtlasOf(texture))
	end
end
local function DressMicro(color)
	microColor = color -- (ColorOf's: brightened already)
	for _, button in ipairs(MicroButtons()) do
		local parts = micro[button]
		if not parts and color then
			parts = { state = MicroCopy(button, "ARTWORK", 7), hover = MicroCopy(button, "HIGHLIGHT", 7), extra = {} }
			micro[button] = parts
			-- (The gold edge is the button's background, behind its icon (tested on
			-- Forever: a copy of the icon art changed nothing); the character
			-- button's portrait shadow too.)
			for _, key in ipairs({ "Background", "PushedBackground", "Shadow" }) do
				local texture = button[key]
				if AtlasOf(texture) then
					local layer, sub = texture:GetDrawLayer()
					parts.extra[texture] = MicroCopy(button, layer or "BORDER", math.min(7, (sub or 0) + 1))
				end
			end
			local function Sync() SyncMicro(button) end
			button:HookScript("OnMouseDown", Sync)
			button:HookScript("OnMouseUp", Sync)
			button:HookScript("OnShow", Sync)
			for _, method in ipairs({ "Enable", "Disable", "SetEnabled", "SetButtonState", "SetNormalAtlas",
				"SetPushedAtlas", "SetDisabledAtlas", "SetHighlightAtlas" }) do
				if button[method] then hooksecurefunc(button, method, Sync) end
			end
		end
		if parts then SyncMicro(button) end
	end
end

local function Refresh()
	for _, group in ipairs(GROUPS) do
		local color = ColorOf(group)
		if not color then
			for texture, info in pairs(tinted) do
				if info.group == group.key then
					Tint(texture, nil)
					if group.metal then Glint(texture, nil) end
				end
			end
		end
		local count = 0
		local frames = {}
		if group.get then
			frames = group.get()
		else
			for _, name in ipairs(group.names) do
				if type(_G[name]) == "table" then frames[#frames + 1] = _G[name] end
			end
		end
		for _, frame in ipairs(frames) do
			local kind = frame.GetObjectType and Kind(frame)
			if kind then
				if kind ~= "Texture" then Watch(frame, group) end
				if color and Shown(frame) then count = count + DressFrame(frame, group, color) end
			end
		end
		counts[group.key] = count
		if group.key == "irMicro" then DressMicro(color) end
	end
end
-- (Many calls in one frame (a profile switch, a theme pick) make one pass.)
local pending = false
function ns.RefreshInterfaceRecolor()
	if pending then return end
	pending = true
	C_Timer.After(0, function()
		pending = false
		local started = debugprofilestop()
		Refresh()
		if ns.RefreshSwingTimerStyle then ns.RefreshSwingTimerStyle() end
		if ns.RefreshDamageMeterStyle then ns.RefreshDamageMeterStyle() end
		local took = debugprofilestop() - started
		if took > 10 then ns.Log("style", ("recolor pass: %.0f ms"):format(took)) end
	end)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ADDON_LOADED") -- (the big windows, each its own Blizzard addon)
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		ns.ApplyBarArtOverride()
		ns.RefreshInterfaceRecolor()
		C_Timer.After(1, ns.RefreshInterfaceRecolor)
		return
	end
	-- (Out of the way of the loading addon: next frame.)
	if ns.db then C_Timer.After(0, ns.RefreshInterfaceRecolor) end
end)

-- The Overrides tab's Action bar art row (styleOver_barArt): Hide takes the bar's
-- art away whatever the Standard Frames page's row says; the game (and that row's
-- fade) setting its alpha again is put back to none.
local artHidden, artHooked = {}, {}
local function KeepArtHidden(art)
	if busy or not artHidden[art] then return end
	busy = true
	art:SetAlpha(0)
	busy = false
end
function ns.ApplyBarArtOverride()
	local hide = ns.StyleOverride and ns.StyleOverride("barArt") == "hide"
	for _, art in ipairs(BarArt()) do
		if hide then
			if not artHooked[art] then
				artHooked[art] = true
				hooksecurefunc(art, "SetAlpha", KeepArtHidden)
			end
			artHidden[art] = true
			KeepArtHidden(art)
		elseif artHidden[art] then
			artHidden[art] = nil
			art:SetAlpha(1)
		end
	end
end

-- For /cine debug recolor: how much each group tinted, and what this client has.
function ns.ReportInterfaceRecolor()
	Refresh()
	print(("Cinematic: Interface Recolor: page %s, theme ring %s, game %s"):format(tostring(ns.StyleOn("irStyle")),
		tostring(ns.ThemeRing() ~= nil), tostring(select(4, GetBuildInfo()))))
	for _, group in ipairs(GROUPS) do
		local present = {}
		for _, name in ipairs(group.names or {}) do
			if type(_G[name]) == "table" then present[#present + 1] = name end
		end
		print(("  %s: %d tinted; frames %s"):format(group.key, counts[group.key] or 0,
			#present > 0 and table.concat(present, ", ", 1, math.min(#present, 6)) .. (#present > 6 and ", ..." or "")
			or "none"))
	end
	if ns.ReportSwingTimerStyle then ns.ReportSwingTimerStyle() end
end

-- For debug reports: every texture in a frame (DEPTH deep), to the log: what it is (own name,
-- atlas or file, layer, size, color), whether it counts as chrome, and whether
-- we tinted it.
function ns.LogTextures(tag, frame)
	Each(frame, 0, function(texture)
		local okAtlas, atlas = pcall(function() return texture:GetAtlas() end)
		local okFile, file = pcall(texture.GetTexture, texture)
		local _, full = OwnName(texture)
		local layer, sub = texture:GetDrawLayer()
		local r, g, b, alpha = texture:GetVertexColor()
		ns.Log("recolor", ("%s:   %s [%s %s] atlas=%s file=%s %.0fx%.0f shown=%s desat=%s " ..
			"color=%.2f,%.2f,%.2f,%.2f chrome=%s tinted=%s"):format(tag, full ~= "" and full or "?", tostring(layer),
			tostring(sub), tostring(okAtlas and Plain(atlas)), tostring(okFile and Plain(file)), texture:GetWidth(),
			texture:GetHeight(), tostring(texture:IsShown()), tostring(texture:IsDesaturated()), Plain(r) or -1,
			Plain(g) or -1, Plain(b) or -1, Plain(alpha) or -1, tostring(IsChrome(texture)),
			tostring(tinted[texture] ~= nil)))
	end, {})
end

-- For /cine debug micro: each menu button's textures, to the log: what they are
-- (own name, atlas or file, layer, size), whether they count as chrome, and
-- whether we tinted them.
function ns.ReportMicroButtons()
	Refresh()
	local function Say(text) ns.Log("recolor", text) end
	Say(("micro: client %s, combat %s, page %s, irMicro %s, theme ring %s"):format(tostring(select(4, GetBuildInfo())),
		tostring(InCombatLockdown()), tostring(ns.StyleOn("irStyle")), tostring(ns.StyleLook("irStyle").irMicro),
		tostring(ns.ThemeRing() ~= nil)))
	local seen, buttons = {}, {}
	for _, holder in ipairs({ "MicroMenu", "MicroMenuContainer", "MicroButtonAndBagsBar" }) do
		local frame = _G[holder]
		if type(frame) == "table" and frame.GetChildren then
			for _, kid in ipairs({ frame:GetChildren() }) do
				local name = kid.GetName and kid:GetName()
				if name and name:find("MicroButton$") and not seen[kid] then
					seen[kid] = true
					buttons[#buttons + 1] = kid
				end
			end
		end
	end
	Say(("micro: %d buttons"):format(#buttons))
	for _, button in ipairs(buttons) do
		Say(("micro: %s %.0fx%.0f shown %s"):format(button:GetName(), button:GetWidth(), button:GetHeight(),
			tostring(button:IsShown())))
		Each(button, 0, function(texture)
			local okAtlas, atlas = pcall(function() return texture:GetAtlas() end)
			local okFile, file = pcall(texture.GetTexture, texture)
			local own = OwnName(texture)
			local layer, sub = texture:GetDrawLayer()
			local r, g, b, alpha = texture:GetVertexColor()
			Say(("micro:   %s [%s %s] atlas=%s file=%s %.0fx%.0f shown=%s desat=%s color=%.2f,%.2f,%.2f,%.2f chrome=%s tinted=%s")
				:format(own ~= "" and own or "?", tostring(layer), tostring(sub), tostring(okAtlas and Plain(atlas)),
				tostring(okFile and Plain(file)), texture:GetWidth(), texture:GetHeight(), tostring(texture:IsShown()),
				tostring(texture:IsDesaturated()), Plain(r) or -1, Plain(g) or -1, Plain(b) or -1, Plain(alpha) or -1,
				tostring(IsChrome(texture)), tostring(tinted[texture] ~= nil)))
		end, {})
	end
	for button, parts in pairs(micro) do
		Say(("micro: %s copy %s %s, hover copy %s"):format(button:GetName() or "?", tostring(parts.state:IsShown()),
			tostring(parts.state:GetAtlas()), tostring(parts.hover:GetAtlas())))
	end
	ns.Print("Menu buttons' textures written to the log.")
end

-- The page itself.
function ns.CreateInterfaceRecolorPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Interface Recolor"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["The game's interface in your theme's color: the minimap, the quest tracker, the damage meter, the " ..
		"swing timer, and the game's own borders, edges and tabs, tinted. Icons, backgrounds and bars keep their colors. Only with a theme " ..
		"picked on General."])

	local function Changed()
		ns.RefreshInterfaceRecolor()
		if ns.RefreshMinimapStyle then ns.RefreshMinimapStyle() end
		if ns.RefreshQuestTrackerStyle then ns.RefreshQuestTrackerStyle() end
	end

	local switch = kit.PageSwitch(content, "irStyle", L["Enable Page"],
		L["On: the ticked parts take the theme's color. Off: the game's own."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "irStyle")
	-- (MinimapStyle.lua's: its ring always follows the page.)
	stack:Header(content, L["Minimap"])
	rows.Check("mmShade", L["Shade inside the edge"], L["A little dark just inside the ring, so the map sits " ..
		"back in it."])
	rows.Check("mmButtons", L["Color the buttons' rings"], L["The rings round the buttons on the minimap " ..
		"(tracking, calendar, the day/night dial, addon buttons...) in the theme's color too."])
	rows.Check("mmZoneBar", L["Zone bar"], L["The bar with the zone's name above the minimap in the theme's panel " ..
		"look: its shape, color and line."])
	-- (QuestTrackerStyle.lua's.)
	stack:Header(content, L["Quest tracker"])
	rows.Check("qtHeaders", L["Header bars"], L["The bars behind All Objectives, Quests, Campaign and the rest " ..
		"in the theme's panel look: its shape, color and line."])
	rows.Check("qtFont", L["Text font"], L["The headers (All Objectives, Quests...) in General's text font. Quest " ..
		"names and objectives keep the game's, which reads best that small."])
	rows.Check("qtTitles", L["Quest name color"], L["Quest names in the theme's color, with a dot in front in " ..
		"their difficulty's color. Objectives keep the game's colors."])
	rows.Check("qtBars", L["Bars and buttons"], L["Progress bars in General's bar texture, and the fold buttons in " ..
		"the theme's color."])
	-- (DamageMeterStyle.lua's.)
	stack:Header(content, L["Damage meter"])
	rows.Check("dmFrame", L["Frame color"], L["The game's damage meter's borders, header and buttons in the " ..
		"theme's color. Its bars keep their colors."])
	rows.Check("dmBars", L["Bar texture"], L["Its bars in General's bar texture, each in its own color."])
	rows.Check("dmFont", L["Text font"], L["Its names and numbers in General's text font."])
	-- (SwingTimerStyle.lua's; Classic clients' own swing timer, none on retail.)
	if not ns.isRetail then
		stack:Header(content, L["Swing timer"])
		rows.Check("swFrame", L["Frame color"], L["The swing timer bars' frames in the theme's color. What fills " ..
			"them keeps its color."])
		rows.Check("swBars", L["Bar texture"], L["The bars' fill in General's bar texture, each weapon's in its " ..
			"own color."])
		rows.Check("swFont", L["Text font"], L["The bars' words in General's text font."])
	end
	stack:Header(content, L["Recolor"])
	rows.Check("irBarArt", L["Action bar art"], L["The gryphons (or wyverns) at the ends of action bar 1, and " ..
		"the band its buttons sit on."])
	rows.Check("irChat", L["Chat"], L["The chat windows' tabs, the box you type in and their buttons."])
	rows.Check("irBuffs", L["Buffs"], L["The buffs' borders by the minimap. Debuffs keep the game's colors: they " ..
		"say what kind each is."])
	rows.Check("irStatus", L["XP and reputation bars"], L["The bars' frames. What fills them keeps its color."])
	rows.Check("irMicro", L["Menu and bag buttons"], L["The frames round the small buttons at the bottom right and your bags. " ..
		"Their pictures keep their colors."])
	rows.Check("irCast", L["Your cast bar"], L["Its frame. What fills it keeps its color."])
	rows.Check("irSmall", L["Small windows"], L["Popups, the loot window, the ready check, the game menu and the " ..
		"queue's eye."])
	rows.Check("irBig", L["Big windows"], L["Bags, character, spellbook, talents, quest log, map, merchant, friends " ..
		"and the rest of the game's windows."])

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Interface Recolor", L["Interface Recolor"])
end
