-- Cinematic: Addon Frame Links. Some addons draw their own frames in place
-- of the game's (EllesmereUI's chat panels, its tab strip). A support file
-- claims each such frame as a part of a game frame group ("chat": its
-- Window, Tabs and Buttons), so what the page does for the game's part
-- (a message peeking a chat window, the Chat page's Background, Tabs and
-- Buttons ticks) it does for the addon's too.
--
-- Which addon's frame a part uses (db.frameLinks):
--   parts[part]   = "blz" or an addon: the player's pick for that part;
--   groups[group] = "blz" or an addon: the player's pick for the whole group,
--                   for the parts not picked on their own.
-- Neither picked: the one supported addon that claims the part ("found by
-- Cinematic"). Two or more claiming it is a clash: the part stays the game's
-- own until the player picks (the Addons hub's Links page, or the Addons
-- page's Support files tab).
--
-- The claimed frames still fade with their row as their support file adds
-- them (ns.AddFoundFrame): a link only adds what the part does on the page.
local _, ns = ...
local L = ns.L

-- The game frame groups and their parts. (Labels are English keys, read
-- through L when shown: the language isn't known yet at load.)
ns.LINK_GROUPS = {
	{ key = "chat", label = "Chat window", page = "Chat Links", parts = {
		{ key = "chatwindow", label = "Window",
			tip = "The panel behind the chat window's lines. It comes up when a message peeks that window." },
		{ key = "chattabs", label = "Tabs",
			tip = "The chat tabs. A message brings them up where the Chat page ticks Tabs." },
		{ key = "chatbuttons", label = "Buttons",
			tip = "The buttons beside the chat. A message brings them up where the Chat page ticks Buttons." },
	} },
	-- (Its addons' trackers fade with the Quest tracker row as their support
	-- files add them, linked or not: the link says which addon's it is.)
	{ key = "quests", label = "Quest tracker", page = "Quest Tracker Links", parts = {
		{ key = "questtracker", label = "Tracker",
			tip = "The quest list. It comes up as the Quest tracker row and this page say." },
	} },
	-- (These fade as their support files set them up, linked or not: the
	-- link says which addon's frame each part is.)
	{ key = "units", label = "Unit frames", page = "Unit Frame Links", parts = {
		{ key = "unitplayer", label = "Player", tip = "Your own frame." },
		{ key = "unitpet", label = "Pet", tip = "Your pet's frame." },
		{ key = "unittarget", label = "Target", tip = "Your target's frame." },
		{ key = "unittot", label = "Target of target", tip = "Your target's target's frame." },
		{ key = "unitfocus", label = "Focus", tip = "Your focus's frame." },
		{ key = "unitfocustot", label = "Focus target", tip = "Your focus's target's frame." },
	} },
	{ key = "buffs", label = "Buffs and debuffs", page = "Buffs Links", parts = {
		{ key = "aurabuffs", label = "Buffs", tip = "Your buffs." },
		{ key = "auradebuffs", label = "Debuffs", tip = "Your debuffs." },
	} },
	{ key = "minimap", label = "Minimap", page = "Minimap Links", parts = {
		{ key = "mapzone", label = "Zone name", tip = "The bar with the zone's name." },
		{ key = "mapclock", label = "Clock", tip = "The clock by the minimap." },
		{ key = "mapcoords", label = "Coordinates", tip = "Your coordinates by the minimap." },
	} },
	{ key = "cooldowns", label = "Cooldown Manager", page = "Cooldown Links", parts = {
		{ key = "cdessential", label = "Essential", tip = "The Essential Cooldowns bar." },
		{ key = "cdutility", label = "Utility", tip = "The Utility Cooldowns bar." },
		{ key = "cdbuffs", label = "Tracked buffs", tip = "The tracked buffs' icons." },
	} },
	{ key = "prd", label = "Personal resource display", page = "Unit Frame Links", parts = {
		{ key = "prdbars", label = "Health and power bars", tip = "Your health and power bars." },
	} },
	{ key = "swing", label = "Swing timer", page = "Swing Links", parts = {
		{ key = "swingbars", label = "Swing bars", tip = "The swing timer's bars." },
	} },
}
-- Each Links page tab's switch (on to start with), by group: off, its
-- groups' links are ignored, every part the game's own (the Unit Frames
-- tab's covers the unit frames' and the resource bars'). (The timers' two
-- since 2026-11-17, their tabs on the Links page: before, on their own pages,
-- they had none.)
local LINK_SWITCH = { chat = "linksChat", quests = "linksQuests", units = "linksUnits", prd = "linksUnits",
	buffs = "linksBuffs", minimap = "linksMinimap", cooldowns = "linksCooldowns", swing = "linksSwing" }
for _, key in pairs(LINK_SWITCH) do ns.DEFAULTS[key] = true end
local function GroupOff(groupKey)
	local key = LINK_SWITCH[groupKey]
	return key ~= nil and ns.db ~= nil and not ns.PageOn(key)
end
local GROUP_OF, PART_DEF, GROUP_DEF = {}, {}, {}
for _, group in ipairs(ns.LINK_GROUPS) do
	GROUP_DEF[group.key] = group
	for _, part in ipairs(group.parts) do
		GROUP_OF[part.key] = group.key
		PART_DEF[part.key] = part
	end
end

-- What the fade pass reads (Frames.lua), rebuilt by ns.ApplyFrameLinks:
ns.chatLinkRole = {} -- [frame] = "tabs" or "buttons": up with a docked window's peek where the Chat page ticks it
ns.chatLinkBackdrop = {} -- [frame] = its backdrop's regions: faded as the Chat page's Background says
ns.chatPanelOwner = {} -- [frame] = the chat window it draws the lines of

-- part -> addon -> { [frame] = info }. info.window: the chat window it's the
-- panel of; info.backdrop: its regions that are the backdrop.
local claims = {}

local function DB()
	local db = ns.db
	if not db then return nil end
	db.frameLinks = db.frameLinks or {}
	db.frameLinks.parts = db.frameLinks.parts or {}
	db.frameLinks.groups = db.frameLinks.groups or {}
	return db.frameLinks
end

-- The addons claiming a part, sorted (nil: none).
function ns.LinkClaimants(part)
	local list
	for addon, frames in pairs(claims[part] or {}) do
		if next(frames) then
			list = list or {}
			list[#list + 1] = addon
		end
	end
	if list then table.sort(list) end
	return list
end

-- The addon whose frame the part uses (nil: the game's own), and why:
-- "picked" (its own pick), "group" (the group's pick), "found" (the one
-- addon claiming it), "clash" (two or more, none picked), "none" (the
-- group's addon has no such part) or nil (nothing claims it).
function ns.LinkResolve(part)
	if GroupOff(GROUP_OF[part]) then return nil, nil end -- (its tab switched off: none of its links)
	local links, owners = DB(), claims[part] or {}
	local function Has(addon) return owners[addon] and next(owners[addon]) ~= nil end
	local pick = links and links.parts[part]
	if pick then
		if pick ~= "blz" and (Has(pick) or ns.LinkPickedName(pick)) then return pick, "picked" end
		return nil, "picked"
	end
	local groupPick = links and links.groups[GROUP_OF[part]]
	if groupPick then
		if groupPick ~= "blz" and Has(groupPick) then return groupPick, "group" end
		return nil, groupPick == "blz" and "group" or "none"
	end
	local list = ns.LinkClaimants(part)
	if not list then return nil, nil end
	if #list == 1 then return list[1], "found" end
	return nil, "clash"
end

-- A pick of a frame by name (Find a frame, for an addon with no support
-- file): "frame:<its name>". The name, or nil for any other pick.
function ns.LinkPickedName(pick)
	return type(pick) == "string" and pick:match("^frame:(.+)$") or nil
end

-- The parts claimed by two or more addons, with no pick settling them.
function ns.LinkClashes()
	local list = {}
	for _, group in ipairs(ns.LINK_GROUPS) do
		for _, part in ipairs(group.parts) do
			local _, why = ns.LinkResolve(part.key)
			if why == "clash" then list[#list + 1] = { group = group, part = part } end
		end
	end
	return list
end

-- What each part does for its frame while it's linked.
local APPLY = {
	chatwindow = function(frame, info)
		if info.window then
			ns.chatPeekPanels[info.window] = frame
			ns.chatPanelOwner[frame] = info.window
		else
			-- (A frame picked by name: which window it draws isn't known, so
			-- it comes up with any of them.)
			for i = 1, (NUM_CHAT_WINDOWS or 10) do
				local chatFrame = _G["ChatFrame" .. i]
				if chatFrame and not ns.chatPeekPanels[chatFrame] then ns.chatPeekPanels[chatFrame] = frame end
			end
		end
		if info.backdrop then ns.chatLinkBackdrop[frame] = info.backdrop end
	end,
	chattabs = function(frame) ns.chatLinkRole[frame] = "tabs" end,
	chatbuttons = function(frame) ns.chatLinkRole[frame] = "buttons" end,
}

-- Works the links out again: after a claim, or a pick on the pages.
function ns.ApplyFrameLinks()
	if not ns.db or not ns.chatPeekPanels then return end
	-- (A backdrop no longer linked gets its own alpha back.)
	local before = {}
	for frame, regions in pairs(ns.chatLinkBackdrop) do before[frame] = regions end
	wipe(ns.chatPeekPanels)
	wipe(ns.chatLinkRole)
	wipe(ns.chatLinkBackdrop)
	wipe(ns.chatPanelOwner)
	for part, apply in pairs(APPLY) do
		local addon = ns.LinkResolve(part)
		local name = ns.LinkPickedName(addon)
		if name then
			local frame = _G[name]
			if type(frame) == "table" and type(frame.GetObjectType) == "function"
				and not (frame.IsForbidden and frame:IsForbidden()) then
				apply(frame, {})
			end
		else
			for frame, info in pairs(addon and claims[part][addon] or {}) do
				apply(frame, info)
			end
		end
	end
	ns.FadePickedFrames()
	for frame, regions in pairs(before) do
		if not ns.chatLinkBackdrop[frame] then
			for _, region in ipairs(regions) do ns.FadeRelative(region, 1) end
		end
	end
	ns.framesWake = "frame links" -- (the frames' pass at once: Core.lua)
	for _, watcher in ipairs(ns.frameLinkWatchers) do watcher() end
end

-- Each part's HUD row and fade group: a frame picked for it by name
-- fades with them, as a support file's does (ns.FadeWithRow). Once per name
-- a session (a pick taken back fades with it till /reload).
local PART_ROW = {
	chatwindow = { "chat", "chat" }, chattabs = { "chat", "chat" }, chatbuttons = { "chat", "chat" },
	questtracker = { "quests", "quests" },
	unitplayer = { "player", "player" }, unitpet = { "petframe", "player" }, unittarget = { "target", "target" },
	unittot = { "tot", "target" }, unitfocus = { "focus", "target" }, unitfocustot = { "focustot", "target" },
	aurabuffs = { "buffs", "buffs" }, auradebuffs = { "buffs", "buffs" },
	mapzone = { "minimapzone", "minimapzone" }, mapclock = { "minimapclock", "minimapclock" },
	mapcoords = { "minimapcoords", "minimapcoords" },
	cdessential = { "cooldowns", "cooldowns" }, cdutility = { "cooldownsutility", "cooldowns" },
	cdbuffs = { "cooldownsbuffs", "cooldowns" },
	prdbars = { "prd", "prd" }, swingbars = { "swing", "swing" },
}
local fadingPicked = {}
function ns.FadePickedFrames()
	local links = DB()
	if not links or not ns.FadeWithRow then return end
	for part, pick in pairs(links.parts) do
		local name, row = ns.LinkPickedName(pick), PART_ROW[part]
		-- (Not while its tab's switched off; one fading already goes on till /reload.)
		if name and row and not fadingPicked[name] and not GroupOff(GROUP_OF[part]) then
			fadingPicked[name] = true
			ns.FadeWithRow(row[1], row[2], { name }, true, true)
		end
	end
end
-- (At login: frames picked earlier, whatever the support files claim.)
local loginWatch = CreateFrame("Frame")
loginWatch:RegisterEvent("PLAYER_LOGIN")
loginWatch:SetScript("OnEvent", function()
	C_Timer.After(1, function() ns.ApplyFrameLinks() end)
end)

-- fn() runs after the links are worked out again (the pages showing them).
ns.frameLinkWatchers = {}
function ns.WatchFrameLinks(fn)
	table.insert(ns.frameLinkWatchers, fn)
end

local applyQueued = false
local function ApplySoon()
	if applyQueued then return end
	applyQueued = true
	C_Timer.After(0, function()
		applyQueued = false
		ns.ApplyFrameLinks()
	end)
end

-- A support file's claim: frame is addon's part (a key of ns.LINK_GROUPS'
-- parts). info as in claims above. Claiming again replaces the info.
function ns.ClaimLinkPart(addon, part, frame, info)
	if not PART_DEF[part] or type(frame) ~= "table" then return end
	claims[part] = claims[part] or {}
	claims[part][addon] = claims[part][addon] or {}
	local had = claims[part][addon][frame]
	info = info or {}
	claims[part][addon][frame] = info
	-- (Claimed again by the next scan, unchanged: nothing to work out.)
	if not had or had.window ~= info.window then ApplySoon() end
end

-- Sets a pick (value nil: back to following the group, or for a group, to
-- the support files deciding) and works the links out again.
function ns.SetLinkPick(kind, key, value)
	local links = DB()
	if not links then return end
	links[kind][key] = value
	ns.ApplyFrameLinks()
end

-- The addons claiming any part of a group, sorted.
function ns.LinkGroupAddons(groupKey)
	local seen, list = {}, {}
	for _, part in ipairs(GROUP_DEF[groupKey].parts) do
		for _, addon in ipairs(ns.LinkClaimants(part.key) or {}) do
			if not seen[addon] then
				seen[addon] = true
				list[#list + 1] = addon
			end
		end
	end
	table.sort(list)
	return list
end

-- Whether any part of a group uses an addon's frame now.
function ns.LinkGroupInUse(groupKey)
	for _, part in ipairs(GROUP_DEF[groupKey].parts) do
		if ns.LinkResolve(part.key) then return true end
	end
	return false
end

-- Options pages -------------------------------------------------------------

-- What a part's row says beside its choice.
local function PartStatus(part)
	local addon, why = ns.LinkResolve(part)
	if why == "clash" then
		return "|cffd9a441" .. (L["%s: pick one"]):format(table.concat(ns.LinkClaimants(part), L[" or "])) .. "|r"
	elseif why == "found" then
		return "|cff9cc0ff" .. L["found by Cinematic"] .. "|r"
	elseif why == "group" and addon then
		return "|cff808080" .. (L["from %s"]):format(addon) .. "|r"
	elseif why == "none" then
		return "|cffd9a441" .. (L["%s has none"]):format(DB().groups[GROUP_OF[part]]) .. "|r"
	elseif why == "picked" and ns.LinkPickedName(addon) then
		local frame = _G[ns.LinkPickedName(addon)]
		return "|cffffd100" .. (frame and L["picked"] or L["picked, not loaded now"]) .. "|r"
	elseif why == "picked" then
		return "|cffffd100" .. L["picked"] .. "|r"
	end
	return ""
end

local ROW_H, LABEL_W, CHOICE_W = 26, 150, 210

-- The Addon Frame Links section of a page (its body), for one group: the
-- group's row (an addon for all its parts) and a row per part (one addon's
-- frame each). onResize: after it changes height.
function ns.BuildLinkBand(body, groupKey, onResize)
	local kit = ns.GRID_KIT
	local group = GROUP_DEF[groupKey]
	local band = { rows = {} }
	local intro = kit.Label(body, "GameFontHighlightSmall", "")
	intro:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -6)
	intro:SetWidth(LABEL_W + CHOICE_W + 180)
	intro:SetJustifyH("LEFT")

	local function Changed()
		band.Refresh()
		kit.Refresh()
		if onResize then onResize() end
	end

	local function Row(label, tip, key, choices, status)
		local row = CreateFrame("Frame", nil, body)
		row:SetSize(LABEL_W + CHOICE_W + 180, ROW_H)
		row.label = kit.Label(row, "GameFontHighlight", label)
		row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.label:SetWidth(LABEL_W - 8)
		row.label:SetJustifyH("LEFT")
		row.label:SetWordWrap(false)
		local hover = CreateFrame("Frame", nil, row)
		hover:SetAllPoints(row.label)
		hover:EnableMouse(true)
		kit.Tooltip(hover, tip)
		row.choice = kit.Dropdown(row, key, choices, CHOICE_W, Changed)
		if row.choice then row.choice:SetPoint("LEFT", row, "LEFT", LABEL_W, 0) end
		row.status = kit.Label(row, "GameFontHighlightSmall", "")
		row.status:SetPoint("LEFT", row, "LEFT", LABEL_W + CHOICE_W + 10, 0)
		row.Status = status
		band.rows[#band.rows + 1] = row
		return row
	end

	-- The group's row: Automatic (the support files decide), the game's own,
	-- or one addon for every part it has.
	local groupRow = Row(L[group.label], L["Picks one addon for every part below that it has."],
		{ get = function() local links = DB() return links and links.groups[groupKey] end,
			set = function(value) ns.SetLinkPick("groups", groupKey, value) end },
		function()
			local list = { { value = nil, text = L["Automatic"] }, { value = "blz", text = L["Blizzard"] } }
			for _, addon in ipairs(ns.LinkGroupAddons(groupKey)) do list[#list + 1] = { value = addon, text = addon } end
			return list
		end,
		function() return "|cff808080" .. L["sets every part below"] .. "|r" end)
	groupRow.label:SetFontObject("GameFontNormal")

	-- Find a frame: a small panel of its own (ns.OpenFindFramePanel).
	local FIND = "find" -- (the choice that opens it: never saved)

	for _, part in ipairs(group.parts) do
		local partRow -- (the panel opens beside it)
		partRow = Row(L[part.label], L[part.tip],
			{ get = function() local links = DB() return links and links.parts[part.key] end,
				set = function(value)
					if value == FIND then
						ns.OpenFindFramePanel(part.key, partRow.choice or partRow, Changed)
					else
						ns.SetLinkPick("parts", part.key, value)
					end
				end },
			function()
				local list = { { value = nil, text = (L["Same as %s"]):format(L[group.label]) },
					{ value = "blz", text = L["Blizzard"] } }
				for _, addon in ipairs(ns.LinkClaimants(part.key) or {}) do
					list[#list + 1] = { value = addon, text = addon }
				end
				local links = DB()
				local name = links and ns.LinkPickedName(links.parts[part.key])
				if name then list[#list + 1] = { value = links.parts[part.key], text = name } end
				list[#list + 1] = { value = FIND, text = L["Find a frame..."] }
				return list
			end,
			function() return PartStatus(part.key) end)
	end

	function band.Refresh()
		local addons = ns.LinkGroupAddons(groupKey)
		local clashes = 0
		for _, part in ipairs(group.parts) do
			local _, why = ns.LinkResolve(part.key)
			if why == "clash" then clashes = clashes + 1 end
		end
		if #addons == 0 then
			intro:SetText(L["No supported addon you have loaded draws its own frames for this. To use another " ..
				"addon's frame for a part, pick Find a frame... in its list."])
		elseif clashes > 0 then
			intro:SetText("|cffd9a441" .. (L["%s all have parts of this. A part two of them have stays " ..
				"the game's own until you pick (here, or on Addons > Frames, Support files tab)."])
				:format(table.concat(addons, L[" and "])) .. "|r")
		else
			intro:SetText(L["Which frame each part is: the game's own, or another addon's that draws its own. " ..
				"Cinematic hides and shows the frame picked as it would the game's."])
		end
		local y = -6 - intro:GetStringHeight() - 6
		for i, row in ipairs(band.rows) do
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
			-- (A part's name a step in, under the group's; every choice in one column.)
			local indent = i > 1 and 16 or 0
			row.label:ClearAllPoints()
			row.label:SetPoint("LEFT", row, "LEFT", indent, 0)
			row.label:SetWidth(LABEL_W - 8 - indent)
			row:Show()
			y = y - ROW_H
			row.status:SetText(row.Status())
			if row.choice and row.choice.Refresh then row.choice:Refresh() end
		end
	end
	band.Refresh()
	return band
end

-- A page's Addon Frame Links section, last on the page, under anchor: its
-- band (opens and closes, as the Chat page's sections) and the group's rows.
-- flat: no band, always open (a page's tab of its own: the Cooldown
-- Manager's Frame Links). Returns it; section.Show() from the page's OnShow.
function ns.BuildLinkSection(content, anchor, groupKey, flat)
	local kit = ns.GRID_KIT
	local top = flat and 0 or kit.BAND_HEIGHT
	local frame = CreateFrame("Frame", nil, content)
	frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, flat and 0 or -18)
	frame:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	frame:SetHeight(math.max(top, 1))
	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", 0, -top)
	body:SetPoint("TOPRIGHT", 0, -top)
	body:SetHeight(1)
	body.searchAlways = true
	local section = { frame = frame, body = body, open = flat and true or false, id = "Links/" .. groupKey }
	local function Layout()
		if not flat then
			kit.SectionState.Restore(section)
			section.nameRow:SetOpen(section.open)
		end
		body:SetShown(section.open)
		frame:SetHeight(top + (section.open and (kit.ContentDepth(body) or 0) + 10 or 0))
		kit.FitContentHeight(content)
	end
	if not flat then
		section.nameRow = kit.SectionBand(frame, L["Addon Frame Links"], function()
			kit.SectionState.Save(section, not section.open)
			Layout()
		end)
	end
	function body.openSection()
		if not section.open then
			kit.SectionState.Save(section, true)
			Layout()
		end
	end
	local band = ns.BuildLinkBand(body, groupKey, Layout)
	ns.RegisterLinkSection(groupKey, frame, body.openSection)
	ns.WatchFrameLinks(function()
		if frame:IsVisible() then
			band.Refresh()
			Layout()
		end
	end)
	-- (Open at first only while it has something: an addon's frame in use,
	-- or a pick waiting. Opened or closed with a click, it stays so.)
	function section.Show()
		if not flat and ns.db and ns.db.sectionsOpen and ns.db.sectionsOpen[section.id] == nil then
			section.open = ns.LinkBandOpen(groupKey)
		end
		band.Refresh()
		Layout()
		C_Timer.After(0, Layout) -- (again once the rows have their places)
	end
	return section
end

-- Find a frame: a small panel beside the part's choice, with a search for
-- any other addon's frame by name (one with no support file), as the
-- Addons page's Find frames: hovering a match marks it on screen, clicking it
-- picks it for the part. One panel, made the first time it's wanted.
local findPanel
local FIND_ROWS = 10
local function MakeFindPanel()
	local kit = ns.GRID_KIT
	local panel = CreateFrame("Frame", "CinematicFindFramePanel", UIParent)
	panel:SetSize(340, 96)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:Hide()
	local edge = panel:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0.45, 0.38, 0.2, 1)
	local back = panel:CreateTexture(nil, "BORDER")
	back:SetPoint("TOPLEFT", 1, -1)
	back:SetPoint("BOTTOMRIGHT", -1, 1)
	back:SetColorTexture(0.05, 0.05, 0.05, 0.97)
	panel.title = kit.Label(panel, "GameFontNormal", "")
	panel.title:SetPoint("TOPLEFT", 10, -10)
	panel.title:SetPoint("RIGHT", -30, 0)
	panel.title:SetJustifyH("LEFT")
	panel.title:SetWordWrap(false)
	local close = ns.SkinClose(CreateFrame("Button", nil, panel, "UIPanelCloseButton"))
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() panel:Hide() end)
	local okBox, box = pcall(CreateFrame, "EditBox", nil, panel, "SearchBoxTemplate")
	if not okBox or not box then box = ns.SkinEditBox(CreateFrame("EditBox", nil, panel, "InputBoxTemplate")) end
	box:SetHeight(20)
	box:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 6, -8)
	box:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
	box:SetAutoFocus(false)
	box.searchSkip = true
	if box.Instructions then box.Instructions:SetText(L["Find frames by name or addon"]) end
	box:SetScript("OnEscapePressed", function() panel:Hide() end)
	panel.box = box
	panel.rows = {}
	local frames, matches = nil, {}
	local function FindRow(i)
		local row = panel.rows[i]
		if row then return row end
		row = CreateFrame("Button", nil, panel)
		row:SetHeight(20)
		row:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -6 - (i - 1) * 20)
		row:SetPoint("RIGHT", panel, "RIGHT", -6, 0)
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.1)
		row.text = kit.Label(row, "GameFontHighlight", "")
		row.text:SetPoint("LEFT", 6, 0)
		row.text:SetPoint("RIGHT", -6, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row:SetScript("OnEnter", function(self)
			if self.entry and not ns.MarkFrame(self.entry.name) then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(L["Not on screen right now."], 1, 1, 1, 1, true)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function()
			ns.MarkFrame(nil)
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(self)
			if not (self.entry and panel.part) then return end
			local part, done = panel.part, panel.done
			panel:Hide()
			ns.SetLinkPick("parts", part, "frame:" .. self.entry.name)
			if done then done() end
		end)
		panel.rows[i] = row
		return row
	end
	-- (Names starting with what's typed first, then the shortest.)
	function panel.Update()
		local query = (box:GetText() or ""):match("^%s*(.-)%s*$"):lower()
		wipe(matches)
		if query ~= "" then
			frames = frames or (ns.FindAddableFrames and ns.FindAddableFrames()) or {}
			for _, entry in ipairs(frames) do
				if entry.lower:find(query, 1, true) then matches[#matches + 1] = entry end
			end
			table.sort(matches, function(a, b)
				local aStarts, bStarts = a.lower:sub(1, #query) == query, b.lower:sub(1, #query) == query
				if aStarts ~= bStarts then return aStarts end
				if #a.name ~= #b.name then return #a.name < #b.name end
				return a.name < b.name
			end)
		end
		local lines = 0
		for i = 1, math.min(#matches, FIND_ROWS) do
			local row = FindRow(i)
			row.entry = matches[i]
			row.text:SetText("|cffffd100" .. matches[i].name .. "|r" ..
				(matches[i].source and ("  |cff808080" .. matches[i].source .. "|r") or ""))
			lines = i
		end
		local note
		if query == "" then
			note = L["Type part of a frame's name or its addon's. Hover a match to see it on screen; click it to use it."]
		elseif #matches == 0 then
			note = L["Nothing found. Only named frames Cinematic doesn't fade already are listed."]
		elseif #matches > FIND_ROWS then
			note = L["%d more: type more of its name"]:format(#matches - FIND_ROWS)
		end
		if note then
			lines = lines + 1
			local row = FindRow(lines)
			row.entry = nil
			row.text:SetText("|cff808080" .. note .. "|r")
		end
		for i, row in ipairs(panel.rows) do row:SetShown(i <= lines) end
		panel:SetHeight(10 + panel.title:GetStringHeight() + 8 + 20 + 6 + lines * 20 + 10)
	end
	box:HookScript("OnTextChanged", panel.Update)
	function panel.Reset() frames = nil end
	panel:SetScript("OnHide", function()
		ns.MarkFrame(nil)
		box:ClearFocus()
	end)
	return panel
end

-- Opens Find a frame for part, beside anchor (its choice); done() after a pick.
function ns.OpenFindFramePanel(part, anchor, done)
	findPanel = findPanel or MakeFindPanel()
	findPanel.part, findPanel.done = part, done
	findPanel.Reset() -- (looked for afresh: frames come and go)
	findPanel.title:SetText((L["Frame for %s"]):format(L[PART_DEF[part].label]))
	findPanel:ClearAllPoints()
	findPanel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
	-- (Gone with the settings, or their page.)
	findPanel.hooked = findPanel.hooked or {}
	if not findPanel.hooked[anchor] then
		findPanel.hooked[anchor] = true
		anchor:HookScript("OnHide", function()
			if findPanel.part == part or findPanel:IsShown() then findPanel:Hide() end
		end)
	end
	findPanel.box:SetText("")
	findPanel.Update()
	findPanel:Show()
	findPanel.box:SetFocus()
end

-- Each group's Addon Frame Links section, by group: { frame, open = opens
-- it }. ns.OpenLinkSection opens its page scrolled to it (the Addons
-- page's Support files buttons).
local linkSections = {}

-- An Addon Reveal Link tab's switch (LINK_SWITCH), made on host, its tab's
-- own frame: what's on it greys with it, and its hub tab finds it there (the
-- tab's hubTabs entry: switchFrame = host). The page's own switch stays the
-- page's other tabs'. Returns host.
function ns.LinksSwitch(host, groupKey)
	ns.GRID_KIT.PageSwitch(host, LINK_SWITCH[groupKey], L["Enable Page"],
		L["Turn this off to ignore the links on this tab and use the game's own frames."], host,
		function() ns.ApplyFrameLinks() end)
	return host
end

function ns.RegisterLinkSection(groupKey, frame, open)
	linkSections[groupKey] = { frame = frame, open = open }
end
function ns.OpenLinkSection(groupKey)
	local group = GROUP_DEF[groupKey]
	if not group then return end
	ns.OpenOptions(group.page)
	-- (Once the page has shown and laid itself out: the section open, then
	-- the page's scroll frame moved to it, as the settings search does.)
	C_Timer.After(0.15, function()
		local section = linkSections[groupKey]
		if not section then return end
		if section.open then section.open() end
		C_Timer.After(0.05, function()
			local scroll = section.frame:GetParent()
			while scroll and not (scroll.GetObjectType and scroll:GetObjectType() == "ScrollFrame") do
				scroll = scroll:GetParent()
			end
			local content = scroll and scroll:GetScrollChild()
			local top, contentTop = section.frame:GetTop(), content and content:GetTop()
			if not (top and contentTop) then return end
			scroll:SetVerticalScroll(math.max(0, math.min(contentTop - top - 20, scroll:GetVerticalScrollRange())))
		end)
	end)
end

-- Whether a page's section starts open: only while a part uses an addon's
-- frame or waits on a pick.
function ns.LinkBandOpen(groupKey)
	if ns.LinkGroupInUse(groupKey) then return true end
	for _, part in ipairs(GROUP_DEF[groupKey].parts) do
		local _, why = ns.LinkResolve(part.key)
		if why == "clash" then return true end
	end
	return false
end

-- The Addons hub's Links page (2026-11-17; before, an Addon Reveal Link tab
-- on each frame's own page): a tab per part of the screen, each its own
-- hidden hub tile under the Links icon (tabOf), with its own switch, its
-- groups' sections on it. Its old page names kept (ns.OpenOptions, /cine
-- find): Options.lua's ns.PAGE_HUB has them. has: whether this client has it.
-- A tab nothing links (no loaded addon claims its parts, nothing picked) is
-- hidden; with none linked anywhere, every tab shows (Find a frame in reach).
local LINK_TABS = {
	{ page = "Unit Frame Links", label = "Unit Frames", name = "Unit Frame Links", groups = { "units", "prd" },
		tip = "Which supported addon's frames stand in for the unit frames and your resource bars." },
	{ page = "Buffs Links", label = "Buffs & Debuffs", name = "Buff Links", groups = { "buffs" },
		tip = "Which supported addon's frames stand in for your buffs and debuffs." },
	{ page = "Minimap Links", label = "Minimap", name = "Minimap Links", groups = { "minimap" },
		tip = "Which supported addon's frames stand in for the minimap's parts." },
	{ page = "Quest Tracker Links", label = "Quest Tracker", name = "Quest Tracker Links", groups = { "quests" },
		tip = "Which supported addon's frames stand in for the quest tracker." },
	{ page = "Chat Links", label = "Chat", name = "Chat Links", groups = { "chat" },
		tip = "Which frame each part of the chat is: the game's, or an addon's that draws its own." },
	{ page = "Cooldown Links", label = "Cooldown Manager", name = "Cooldown Manager Links", groups = { "cooldowns" },
		tip = "Which supported addon's frames stand in for the Cooldown Manager's bars.",
		has = function() return ns.HasCooldownManager() end },
	{ page = "Swing Links", label = "Swing Timer", name = "Swing Timer Links", groups = { "swing" },
		tip = "Which supported addon's frames stand in for the swing timer.",
		has = function() return not ns.isRetail end },
}
-- (A heading over each group where a tab has two.)
local LINK_HEADS = { units = "Unit frames", prd = "Personal Resource Display" }

-- Whether a group has anything to link: a loaded addon claiming a part, or a pick.
local function GroupHasLinks(groupKey)
	if #ns.LinkGroupAddons(groupKey) > 0 then return true end
	local links = DB()
	if not links then return false end
	if links.groups[groupKey] ~= nil then return true end
	for _, part in ipairs(GROUP_DEF[groupKey].parts) do
		if links.parts[part.key] ~= nil then return true end
	end
	return false
end

-- kit: Options.lua's page helpers (ns.lowHealthKit).
function ns.CreateAddonLinksPage(kit)
	local canvas, content = kit.CreateScrollPage()
	local tabs, list = {}, {}
	for _, each in ipairs(LINK_TABS) do
		if not each.has or each.has() then
			tabs[#tabs + 1] = each
			list[#list + 1] = { L[each.label], each.page, L[each.tip] }
		end
	end
	local title = kit.Label(content, "GameFontNormalLarge", L["Links"])
	local panel, ShowTab = ns.PageTabs(content, list, 1)
	local tabFrames = content.pageTabs.frames
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
	local intro = kit.PageIntro(content, title, L["Some addons draw their own frames in place of the game's: " ..
		"pick which frame Cinematic treats as each part."])

	-- A frame for each tab, under the intro, its switch and its groups' sections on it.
	local hosts, sections = {}, {}
	for i, each in ipairs(tabs) do
		local host = CreateFrame("Frame", nil, content)
		host:SetSize(1, 1)
		host:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
		host.recordAs = content -- (its switch the page's: its Reset puts it back)
		host.searchAlways = true
		host:Hide()
		ns.LinksSwitch(host, each.groups[1])
		hosts[i], sections[i] = host, {}
		local below -- (the last group's section: the next heading goes under it)
		for _, groupKey in ipairs(each.groups) do
			-- (The resource bars' only where Cinematic has its own.)
			if groupKey ~= "prd" or _G.CinematicPersonalPower ~= nil then
				local anchor = host
				if #each.groups > 1 then
					anchor = kit.Label(host, "GameFontNormal", L[LINK_HEADS[groupKey]])
					if below then
						anchor:SetPoint("TOPLEFT", below.frame, "BOTTOMLEFT", -2, -18)
					else
						anchor:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
					end
				end
				local section = ns.BuildLinkSection(content, anchor, groupKey, true)
				section.frame:SetParent(host)
				section.frame:SetPoint("RIGHT", content, "RIGHT", -16, 0)
				sections[i][#sections[i] + 1] = section
				below = section
			end
		end
	end

	local current = 1
	-- The tabs shown: those with something to link (and want, the one asked
	-- for); every one when none has.
	local function FitTabs(want)
		local any = false
		local shown = {}
		for i, each in ipairs(tabs) do
			for _, groupKey in ipairs(each.groups) do
				if GroupHasLinks(groupKey) then shown[i] = true end
			end
			any = any or shown[i] or false
		end
		for i, tab in ipairs(tabFrames) do tab:SetShown(not any or shown[i] or i == want) end
	end
	local function ShowPart(i)
		FitTabs(i)
		current = i
		for n, host in ipairs(hosts) do host:SetShown(n == i) end
		ShowTab(i)
		title:SetText(L[tabs[i].label])
		for _, section in ipairs(sections[i]) do section.Show() end
		kit.FitContentHeight(content)
	end
	-- The first tab shown (the Links icon itself opens there, or where it was).
	local function FirstShown()
		FitTabs()
		if tabFrames[current] and tabFrames[current]:IsShown() then return current end
		for i, tab in ipairs(tabFrames) do
			if tab:IsShown() then return i end
		end
		return 1
	end
	ns.WatchFrameLinks(function()
		if canvas:IsVisible() then
			FitTabs(current)
			ShowTab(current)
		end
	end)

	local ICON = "Interface\\Icons\\INV_Misc_Gear_08"
	canvas.hubTabs = { { name = "Addon Links", icon = ICON, label = "Links", noSwitch = true,
		onSelect = function() ShowPart(FirstShown()) end } }
	for i, each in ipairs(tabs) do
		canvas.hubTabs[#canvas.hubTabs + 1] = { name = each.page, icon = ICON, label = "Links", own = true,
			tabOf = "Addon Links", switchLabel = each.name, switchFrame = hosts[i],
			onSelect = function() ShowPart(i) end }
	end
	canvas:SetScript("OnShow", kit.PageShown(function()
		kit.Refresh()
		ShowPart(current)
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Addon Links", L["Links"])
end

-- A line at the top right of a frame's own page while an addon's frames
-- stand in for its parts (groupKeys'): which addon's, and a click to the
-- Links page's tab. Hidden while nothing is linked.
function ns.LinkPointer(content, groupKeys)
	local button = CreateFrame("Button", nil, content)
	button:SetHeight(18)
	button:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, -(ns.FOLDER_TAB_HEIGHT + 26))
	button.searchSkip = true
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("RIGHT", button, "RIGHT", 0, 0)
	text:SetTextColor(0.61, 0.75, 1)
	button:SetScript("OnEnter", function(self)
		text:SetTextColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(L["Opens the Links page, where you pick which addon's frames these are."], 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		text:SetTextColor(0.61, 0.75, 1)
		GameTooltip:Hide()
	end)
	button:SetScript("OnClick", function()
		for _, groupKey in ipairs(groupKeys) do
			if ns.LinkGroupInUse(groupKey) then return ns.OpenOptions(GROUP_DEF[groupKey].page) end
		end
	end)
	local function Update()
		local seen, names = {}, {}
		for _, groupKey in ipairs(groupKeys) do
			for _, part in ipairs(GROUP_DEF[groupKey].parts) do
				local addon = ns.LinkResolve(part.key)
				addon = ns.LinkPickedName(addon) or addon
				if addon and not seen[addon] then
					seen[addon] = true
					names[#names + 1] = addon
				end
			end
		end
		if #names == 0 then
			button:Hide()
			return
		end
		table.sort(names)
		text:SetText((L["Using %s's frames: Addons > Links"]):format(table.concat(names, L[" and "])))
		button:SetWidth(text:GetStringWidth() + 4)
		button:Show()
	end
	content:HookScript("OnShow", Update)
	ns.WatchFrameLinks(function()
		if content:IsVisible() then Update() end
	end)
	Update()
	return button
end

-- The Addons page's Support files tab: the clashes to pick, then what
-- each supported addon loaded replaces. Returns the panel; panel.Refresh()
-- lays it out and returns its height.
function ns.BuildSupportFilesPanel(parent, width)
	local kit = ns.GRID_KIT
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(width, 1)
	local lines, clashRows = {}, {}

	local function Line(i)
		local line = lines[i]
		if not line then
			line = CreateFrame("Frame", nil, panel)
			line:SetSize(width, 20)
			line.text = kit.Label(line, "GameFontHighlight", "")
			line.text:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
			line.text:SetWidth(width - 130)
			line.text:SetJustifyH("LEFT")
			line.open = ns.PanelButton(line)
			line.open:SetSize(140, 22)
			line.open:SetPoint("RIGHT", line, "RIGHT", 0, 0)
			line.open:SetScript("OnClick", function() if line.group then ns.OpenLinkSection(line.group) end end)
			lines[i] = line
		end
		return line
	end

	local function ClashRow(i)
		local row = clashRows[i]
		if not row then
			row = CreateFrame("Frame", nil, panel)
			row:SetSize(width, ROW_H)
			row.label = kit.Label(row, "GameFontHighlight", "")
			row.label:SetPoint("LEFT", row, "LEFT", 16, 0)
			row.label:SetWidth(LABEL_W + 40)
			row.label:SetJustifyH("LEFT")
			row.choice = kit.Dropdown(row,
				{ get = function() local links = DB() return links and row.part and links.parts[row.part] end,
					set = function(value) ns.SetLinkPick("parts", row.part, value) end },
				function()
					local list = { { value = nil, text = L["Not picked (the game's own)"] },
						{ value = "blz", text = L["Blizzard"] } }
					for _, addon in ipairs(row.part and ns.LinkClaimants(row.part) or {}) do
						list[#list + 1] = { value = addon, text = addon }
					end
					return list
				end, CHOICE_W, function()
					panel.Refresh()
					if panel.onResize then panel.onResize() end
				end)
			if row.choice then row.choice:SetPoint("LEFT", row, "LEFT", LABEL_W + 64, 0) end
			clashRows[i] = row
		end
		return row
	end

	function panel.Refresh()
		for _, line in ipairs(lines) do line:Hide() end
		for _, row in ipairs(clashRows) do row:Hide() end
		local y, n = 0, 0
		-- (The page buttons all as wide as the widest label: page names run
		-- from Chat to Personal Resource Display.)
		local buttonW = 90
		for _, group in ipairs(ns.LINK_GROUPS) do
			Line(1).open:SetText((ns.PageLabel and ns.PageLabel(group.page) or L[group.page]) .. " »")
			local label = Line(1).open:GetFontString()
			buttonW = math.max(buttonW, (label and label:GetStringWidth() or 120) + 28)
		end
		local function Text(text, button, group)
			n = n + 1
			local line = Line(n)
			line.text:SetText(text)
			line.group = group
			line.open:SetShown(button ~= nil)
			if button then
				line.open:SetText(button)
				line.open:SetWidth(buttonW)
			end
			-- (The text up to the button, or the whole width.)
			line.text:SetWidth(button and width - buttonW - 12 or width)
			-- (A line with a button: tall enough for it and a gap to the next.)
			local height = math.max(button and 28 or 20, line.text:GetStringHeight() + 6)
			line:SetHeight(height)
			line.text:ClearAllPoints()
			if button then
				line.text:SetPoint("LEFT", line, "LEFT", 0, 0)
			else
				line.text:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
			end
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
			line:Show()
			y = y + height
		end
		Text("|cff808080" .. L["Addons that draw their own frames in place of the game's (chat panels, tabs...). " ..
			"Each part uses one addon's frame, and the page it belongs to works on it."] .. "|r")
		y = y + 6
		-- Clashes: a part two loaded addons both have.
		local clashes = ns.LinkClashes()
		if #clashes > 0 then
			Text("|cffd9a441" .. L["Clashes"] .. "|r  |cff808080" .. L["Parts two of your addons both have. " ..
				"Each stays the game's own until you pick which addon's to use."] .. "|r")
			for i, clash in ipairs(clashes) do
				local row = ClashRow(i)
				row.part = clash.part.key
				row.label:SetText(("%s › %s"):format(L[clash.group.label], L[clash.part.label]))
				if row.choice and row.choice.Refresh then row.choice:Refresh() end
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
				row:Show()
				y = y + ROW_H
			end
			y = y + 8
		end
		-- Each addon loaded that claims parts: the groups it has parts of.
		local byAddon, order = {}, {}
		for _, group in ipairs(ns.LINK_GROUPS) do
			for _, addon in ipairs(ns.LinkGroupAddons(group.key)) do
				if not byAddon[addon] then
					byAddon[addon] = {}
					order[#order + 1] = addon
				end
				local used, total = 0, 0
				for _, part in ipairs(group.parts) do
					local claimed = claims[part.key] and claims[part.key][addon] and next(claims[part.key][addon])
					if claimed then
						total = total + 1
						if ns.LinkResolve(part.key) == addon then used = used + 1 end
					end
				end
				byAddon[addon][#byAddon[addon] + 1] = { group = group, used = used, total = total }
			end
		end
		table.sort(order)
		if #order == 0 then
			Text("|cff808080" .. L["None of your loaded addons draws its own frames in place of the game's."] .. "|r")
		end
		for _, addon in ipairs(order) do
			Text(addon)
			for _, entry in ipairs(byAddon[addon]) do
				Text(("    %s  |cff808080%s|r"):format(L[entry.group.label],
					(L["%d of %d parts in use"]):format(entry.used, entry.total)),
					(ns.PageLabel and ns.PageLabel(entry.group.page) or L[entry.group.page]) .. " »", entry.group.key)
			end
			y = y + 4
		end
		panel:SetHeight(math.max(1, y))
		return y
	end
	return panel
end
