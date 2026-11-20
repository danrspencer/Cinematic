-- Addon Conflicts: features another addon has its own version of (the rows,
-- picks and gates: AddonSupport.lua's ns.AddConflict and ns.AddFeatureYield;
-- the addons' rows: Support/). Here: holding the other addon's version at
-- alpha 0 while a row's pick is Ours and Cinematic's is on (its settings left
-- be), the Addons > Conflicts page, and the window that comes
-- up at login over everything (the welcome window too) while a conflict with
-- both versions on has no pick yet.

local _, ns = ...
local L = ns.L

local NONE = {}
-- The page's groups, in order.
local GROUPS = {
	{ key = "scenes", label = "Cards and scenes" },
	{ key = "quest", label = "Quest Vision" },
	{ key = "windows", label = "Windows" },
	{ key = "style", label = "Style" },
}
local PICK_LABELS = { theirs = "Theirs", ours = "Ours", both = "Both" }
local PICK_TIPS = {
	theirs = "%s's version plays, and Cinematic's stands aside while it's on.",
	ours = "Cinematic's version plays, and %s's is hidden while Cinematic's is on. Its settings stay as they are.",
	both = "Both play, Cinematic's and %s's.",
}
local PAGE = "Addon Conflicts"
-- Addons with rows (Support/): the page is listed with one of them loaded.
local ADDONS = { "DaylightUI", "DynamicCam", "ElvUI", "Leatrix_Plus", "NaowhForever_QoL", "RareScanner" }

-- Holding their frames hidden ------------------------------------------------

-- A held frame stays at alpha 0 whatever it sets (its tweens set alpha), and
-- lets mouse and keys through (an AFK screen takes both). Let go, it gets
-- back the alpha it last set itself.
local held = setmetatable({}, { __mode = "k" }) -- frame -> { mouse =, keyboard = } it had
local hooked = setmetatable({}, { __mode = "k" })
local own = setmetatable({}, { __mode = "k" }) -- frame -> the alpha it last set itself
local applying = false

local function Known(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

local function Zero(frame)
	applying = true
	frame:SetAlpha(0)
	applying = false
end

local function Hook(frame)
	if hooked[frame] then return end
	hooked[frame] = true
	local alpha = frame:GetAlpha()
	own[frame] = Known(alpha) and alpha or nil
	hooksecurefunc(frame, "SetAlpha", ns.Profiled("Addon Conflicts hide", function(self, value)
		if applying then return end
		own[self] = Known(value) and value or nil
		if held[self] then Zero(self) end
	end))
	if frame.HookScript then -- (a texture has none: an addon's backdrop pieces)
		frame:HookScript("OnShow", function(self)
			if held[self] then Zero(self) end
		end)
	end
end

local function Hold(frame)
	if held[frame] then return end
	Hook(frame)
	local had = {}
	if frame.IsMouseEnabled and frame:IsMouseEnabled() then
		had.mouse = true
		frame:EnableMouse(false)
	end
	if frame.IsKeyboardEnabled and frame:IsKeyboardEnabled() then
		had.keyboard = true
		frame:EnableKeyboard(false)
	end
	held[frame] = had
	Zero(frame)
end

local function Release(frame)
	local had = held[frame]
	if not had then return end
	held[frame] = nil
	if had.mouse then frame:EnableMouse(true) end
	if had.keyboard then frame:EnableKeyboard(true) end
	applying = true
	frame:SetAlpha(own[frame] or 1)
	applying = false
end

local function FramesOf(row)
	local hide = row.hide
	if type(hide) == "function" then
		local ok, list = pcall(hide)
		return ok and type(list) == "table" and list or NONE
	end
	local out = {}
	for _, name in ipairs(hide or NONE) do
		local frame = _G[name]
		if type(frame) == "table" and frame.SetAlpha then out[#out + 1] = frame end
	end
	return out
end

-- Whether a row's other version is held hidden now: its pick Ours, theirs on,
-- and Cinematic's on.
local function Holding(row)
	if not row.hide or ns.ConflictPick(row) ~= "ours" or not ns.ConflictTheirsOn(row) then return false end
	return ns.ConflictOursOn(row)
end

-- Every row's frames held or let go, as their picks and states say.
local want = {}
function ns.UpdateConflictHolds()
	wipe(want)
	for _, row in ipairs(ns.CONFLICTS) do
		if Holding(row) then
			for _, frame in ipairs(FramesOf(row)) do want[frame] = true end
		end
	end
	for frame in pairs(held) do
		if not want[frame] then Release(frame) end
	end
	for frame in pairs(want) do Hold(frame) end
end

-- Looked at twice a second once there's a row (their frames are made as
-- they're first needed, and their versions switch on and off in their own
-- options), and just after a line that can bring a chat bubble.
local ticker
local BUBBLE_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL",
	"CHAT_MSG_PARTY" }
local function Tick()
	ns.UpdateConflictHolds()
end
function ns.OnConflictAdded()
	if ticker then return end
	ticker = C_Timer.NewTicker(0.5, ns.Profiled("Addon Conflicts", Tick))
	local watcher = CreateFrame("Frame")
	for _, event in ipairs(BUBBLE_EVENTS) do watcher:RegisterEvent(event) end
	watcher:SetScript("OnEvent", function()
		C_Timer.After(0.05, Tick)
	end)
end

-- A row's pick, saved; its effects at once.
function ns.SetConflictPick(row, pick)
	ns.GetDB().conflictPicks[row.id] = pick
	if row.onPick then pcall(row.onPick, pick) end
	ns.UpdateConflictHolds()
	if ns.ConflictsChanged then ns.ConflictsChanged() end
end

-- Rows, in the page's order (by group, then as added).
local function Ordered(only)
	local list = {}
	for _, group in ipairs(GROUPS) do
		for _, row in ipairs(ns.CONFLICTS) do
			if row.group == group.key and (not only or only(row)) then list[#list + 1] = row end
		end
	end
	for _, row in ipairs(ns.CONFLICTS) do
		local known = false
		for _, group in ipairs(GROUPS) do known = known or row.group == group.key end
		if not known and (not only or only(row)) then list[#list + 1] = row end
	end
	return list
end

-- The ones the window asks about: no pick yet, and both versions on (with
-- Cinematic's off there's nothing to pick between).
function ns.ConflictUndecided(row)
	local _, picked = ns.ConflictPick(row)
	return not picked and ns.ConflictTheirsOn(row) and ns.ConflictOursOn(row)
end
local Undecided = ns.ConflictUndecided

-- The row's line for the page and window: what it is, and what Ours does.
local function About(row)
	return L[row.about or row.label] .. "."
end

-- /cine why: what an addon's frame under the cursor is to a row, or nil.
function ns.ConflictOfFrame(frame)
	for _, row in ipairs(ns.CONFLICTS) do
		for _, each in ipairs(FramesOf(row)) do
			if each == frame then return row end
		end
	end
	return nil
end
function ns.ConflictPickLabel(pick)
	return L[PICK_LABELS[pick] or pick]
end

-- A tip on hover, beside a flat button's own lighting up.
local function HoverTip(button, text)
	button:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(text, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	button:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- The pick buttons -------------------------------------------------------------

-- Theirs / Ours / Both side by side (Both left out for a row with one look),
-- the pick filled in gold; an unpicked row's Theirs only edged in it.
local GOLD_FILL, GOLD_EDGE = { 0.5, 0.38, 0.05 }, { 0.62, 0.48, 0.08 }
local function PickButtons(parent, onPick)
	local F = ns.FlatStyle
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(3 * 58 + 2 * 2, 22)
	holder.buttons = {}
	for i, pick in ipairs({ "theirs", "ours", "both" }) do
		local b = F.Button(holder, L[PICK_LABELS[pick]], "box", function() onPick(holder.row, pick) end)
		b:SetSize(58, 22)
		b:SetPoint("LEFT", (i - 1) * 60, 0)
		b.pick = pick
		b:HookScript("OnEnter", function(self)
			if not holder.row then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L[PICK_LABELS[pick]], 1, 1, 1)
			GameTooltip:AddLine(L[PICK_TIPS[pick]]:format(holder.row.addon), nil, nil, nil, true)
			GameTooltip:Show()
		end)
		b:HookScript("OnLeave", function() GameTooltip:Hide() end)
		holder.buttons[i] = b
	end
	function holder:SetRow(row)
		holder.row = row
		local pick, picked = ns.ConflictPick(row)
		for _, b in ipairs(holder.buttons) do
			b:SetShown(not (b.pick == "both" and row.noBoth))
			local on = b.pick == pick
			F.Flat(b, (on and picked) and GOLD_FILL or F.RAISED, on and GOLD_EDGE or F.EDGE)
			F.Color(b.text, on and F.WHITE or F.SOFT)
		end
	end
	return holder
end

-- The settings page ------------------------------------------------------------

function ns.CreateConflictsPanel(kit)
	local any = false
	for _, addon in ipairs(ADDONS) do any = any or ns.AddOnWillLoad(addon) end
	if not any then return end
	local F = ns.FlatStyle
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Addon Conflicts"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title, L["Pick whose version plays for features your other addons also have."])

	local rows, headers = {}, {}
	local Build
	local function Pick(row, pick)
		ns.SetConflictPick(row, pick)
		Build()
	end
	local function All(pick)
		for _, row in ipairs(ns.CONFLICTS) do
			local _, picked = ns.ConflictPick(row)
			if pick == "ours" or picked then ns.SetConflictPick(row, pick) end
		end
		Build()
	end
	local allTheirs = F.Button(content, L["All theirs"], "box", function() All("theirs") end)
	allTheirs:SetSize(110, 24)
	allTheirs:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
	HoverTip(allTheirs, L["Every row to Theirs: the other addons' versions play."])
	local allOurs = F.Button(content, L["All ours"], "box", function() All("ours") end)
	allOurs:SetSize(110, 24)
	allOurs:SetPoint("LEFT", allTheirs, "RIGHT", 8, 0)
	HoverTip(allOurs, L["Every row to Ours: Cinematic's versions play, the other addons' hidden while they do."])

	-- Column heads: Feature, Addon, Theirs (its version on now), Plays.
	local COLUMNS = { 0, 230, 340, 420 }
	local heads = CreateFrame("Frame", nil, content)
	heads:SetSize(600, 16)
	heads:SetPoint("TOPLEFT", allTheirs, "BOTTOMLEFT", 0, -14)
	for i, text in ipairs({ "Feature", "Addon", "Theirs now", "Plays" }) do
		local head = kit.Label(heads, "GameFontDisableSmall", L[text])
		head:SetPoint("LEFT", COLUMNS[i], 0)
	end
	local empty = kit.Label(content, "GameFontDisable", L["None of your loaded addons has its own version " ..
		"of a Cinematic feature switched on right now."])
	empty:SetPoint("TOPLEFT", heads, "BOTTOMLEFT", 0, -10)
	local note = kit.Label(content, "GameFontDisableSmall", L["Style rows have no Both option, since only one look can win. A row you haven't picked uses " ..
		"theirs, like Theirs does."])
	note:SetWidth(600)

	local function Row(i)
		local row = rows[i]
		if row then return row end
		row = CreateFrame("Frame", nil, content)
		row:SetSize(600, 26)
		row:EnableMouse(true)
		row.name = kit.Label(row, "GameFontHighlight")
		row.name:SetPoint("LEFT", COLUMNS[1], 0)
		row.name:SetWidth(COLUMNS[2] - 8)
		row.name:SetWordWrap(false)
		row.addon = kit.Label(row, "GameFontHighlightSmall")
		row.addon:SetPoint("LEFT", COLUMNS[2], 0)
		row.dot = row:CreateTexture(nil, "ARTWORK")
		row.dot:SetTexture("Interface\\Buttons\\WHITE8x8")
		row.dot:SetSize(7, 7)
		row.dot:SetPoint("LEFT", COLUMNS[3], 0)
		row.state = kit.Label(row, "GameFontHighlightSmall")
		row.state:SetPoint("LEFT", row.dot, "RIGHT", 5, 0)
		row.picks = PickButtons(row, Pick)
		row.picks:SetPoint("LEFT", COLUMNS[4], 0)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:SetText(L[self.conflict.label], 1, 1, 1)
			GameTooltip:AddLine(About(self.conflict), nil, nil, nil, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = row
		return row
	end
	local function Header(i, text)
		local header = headers[i]
		if not header then
			header = kit.Label(content, "GameFontNormal")
			headers[i] = header
		end
		header:SetText(text)
		header:Show()
		return header
	end

	function Build()
		local anchor, used, groupsUsed = heads, 0, 0
		local list = Ordered()
		local lastGroup
		for _, conflict in ipairs(list) do
			if conflict.group ~= lastGroup then
				lastGroup = conflict.group
				local label = conflict.group
				for _, group in ipairs(GROUPS) do
					if group.key == conflict.group then label = group.label end
				end
				groupsUsed = groupsUsed + 1
				local header = Header(groupsUsed, L[label])
				header:ClearAllPoints()
				header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
				anchor = header
			end
			used = used + 1
			local row = Row(used)
			row.conflict = conflict
			row.name:SetText(L[conflict.label])
			row.addon:SetText(conflict.addon)
			local on = ns.ConflictTheirsOn(conflict)
			row.dot:SetVertexColor(on and 0.3 or 0.4, on and 0.7 or 0.4, on and 0.3 or 0.4)
			row.state:SetText(on and L["On"] or L["Off"])
			row.picks:SetRow(conflict)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
			row:Show()
			anchor = row
		end
		for i = used + 1, #rows do rows[i]:Hide() end
		for i = groupsUsed + 1, #headers do headers[i]:Hide() end
		empty:SetShown(used == 0)
		heads:SetShown(used > 0)
		note:ClearAllPoints()
		note:SetPoint("TOPLEFT", used > 0 and anchor or empty, "BOTTOMLEFT", 0, -14)
	end

	-- (Built afresh as it shows: rows come as their addons load, after the
	-- pages are made, and their versions switch on and off.)
	canvas:SetScript("OnShow", kit.PageShown(function()
		kit.Refresh()
		Build()
	end, content))
	ns.ConflictsChanged = function()
		if canvas:IsVisible() then Build() end
	end
	canvas:Hide()
	kit.RegisterSubpage(canvas, PAGE)
end

-- The window -----------------------------------------------------------------

-- Drawn flat as the welcome window is (ns.FlatStyle), a strata higher (at
-- login it waits for that to close, not over it). A card a row: what it is and its pick buttons, three a page; Next
-- through them, Done on the last. Theirs for the rest picks Theirs for every
-- unpicked one; Decide later, the X or Escape leave them unpicked (theirs plays)
-- and it comes back at the next login.
local WIDTH, PAD, GAP, PER_PAGE = 560, 22, 8, 4
local CARD_W = WIDTH - 2 * PAD
local PICKS_W = 3 * 58 + 2 * 2 -- (PickButtons' width)
-- A card's words: left of its pick buttons, never under them.
local TEXT_W = CARD_W - 12 - PICKS_W - 20
local window, cards, list, page
local ShowCards

local function Unpicked()
	local n = 0
	for _, row in ipairs(list or NONE) do
		local _, picked = ns.ConflictPick(row)
		if not picked then n = n + 1 end
	end
	return n
end

local function Card(i)
	local F = ns.FlatStyle
	local card = cards[i]
	if card then return card end
	card = CreateFrame("Frame", nil, window, BackdropTemplateMixin and "BackdropTemplate")
	card:SetWidth(CARD_W)
	F.Flat(card, F.RAISED, F.EDGE)
	card.name = F.Text(card, "GameFontHighlight", "", F.WHITE, TEXT_W)
	card.name:SetPoint("TOPLEFT", 12, -10)
	card.picks = PickButtons(card, function(row, pick)
		ns.SetConflictPick(row, pick)
		ShowCards()
	end)
	card.picks:SetPoint("TOPRIGHT", -10, -9)
	card.about = F.Text(card, "GameFontHighlightSmall", "", F.DIM, TEXT_W)
	card.about:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -5)
	card.about:SetSpacing(2)
	cards[i] = card
	return card
end

-- A card as tall as its words (at least its buttons' row).
local function Fit(card)
	local text = 10 + card.name:GetStringHeight() + 5 + card.about:GetStringHeight() + 11
	card:SetHeight(math.max(40, math.ceil(text)))
end

function ShowCards()
	local F = ns.FlatStyle
	local first = (page - 1) * PER_PAGE
	local pages = math.max(1, math.ceil(#list / PER_PAGE))
	local anchor, height = window.sub, 0
	for i = 1, PER_PAGE do
		local row = list[first + i]
		local card = Card(i)
		if row then
			card.name:SetText(L[row.label])
			card.about:SetText(About(row))
			card.picks:SetRow(row)
			local _, picked = ns.ConflictPick(row)
			card:SetBackdropBorderColor(unpack(picked and GOLD_EDGE or F.EDGE))
			Fit(card)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, anchor == window.sub and -16 or -GAP)
			card:Show()
			height = height + card:GetHeight() + (anchor == window.sub and 16 or GAP)
			anchor = card
		else
			card:Hide()
		end
	end
	window.count:ClearAllPoints()
	window.count:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, -12)
	-- (Title, intro, the cards, the count line, the buttons.)
	window:SetHeight(math.ceil(PAD + window.title:GetStringHeight() + 6 + window.sub:GetStringHeight()
		+ height + 12 + 14 + 18 + 30 + PAD))
	window.count:SetText(L["%d of %d picked"]:format(#list - Unpicked(), #list)
		.. (pages > 1 and ("   " .. L["page %d of %d"]:format(page, pages)) or ""))
	window.next:SetLabel(page < pages and L["Next"] or L["Done"])
	window.rest:SetShown(Unpicked() > 0)
end

local function CreateWindow()
	local F = ns.FlatStyle
	window = CreateFrame("Frame", "CinematicConflicts", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	window:SetWidth(WIDTH)
	window:SetPoint("CENTER", 0, 80)
	window:SetFrameStrata("FULLSCREEN_DIALOG") -- (over the welcome window: DIALOG)
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	F.Flat(window, F.BG)
	tinsert(UISpecialFrames, "CinematicConflicts")
	cards = {}

	local close = F.Button(window, "x", nil, function() window:Hide() end)
	close.text:SetFontObject("GameFontHighlightLarge")
	close:SetSize(28, 28)
	close:SetPoint("TOPRIGHT", -6, -6)
	window.title = F.Text(window, "GameFontNormalHuge", L["Two versions of the same thing"], F.GOLD)
	window.title:SetPoint("TOPLEFT", PAD, -PAD)
	window.sub = F.Text(window, "GameFontHighlight", "", F.SOFT, WIDTH - 2 * PAD)
	window.sub:SetPoint("TOPLEFT", window.title, "BOTTOMLEFT", 0, -6)

	window.count = F.Text(window, "GameFontHighlightSmall", "", F.DIM)
	window.count:SetPoint("BOTTOMLEFT", PAD, PAD + 40)
	window.later = F.Button(window, L["Decide later"], nil, function() window:Hide() end)
	window.later:SetPoint("BOTTOMLEFT", PAD - 3, PAD + 5)
	window.next = F.Button(window, L["Next"], "main", function()
		if page < math.ceil(#list / PER_PAGE) then
			page = page + 1
			ShowCards()
		else
			window:Hide()
		end
	end)
	window.next:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	window.rest = F.Button(window, L["Theirs for the rest"], "box", function()
		for _, row in ipairs(list) do
			local _, picked = ns.ConflictPick(row)
			if not picked then ns.SetConflictPick(row, "theirs") end
		end
		window:Hide()
	end)
	window.rest:SetSize(150, 30)
	window.rest:SetPoint("RIGHT", window.next, "LEFT", -8, 0)
	window:SetScript("OnHide", function()
		if Unpicked() > 0 then
			ns.Print(L["Addon Conflicts: any you haven't picked use the other addon's version. This shows again next " ..
				"login unless you pick on Addons > Conflicts."])
		end
	end)
end

-- all: every row (/cine conflicts), not just the unpicked ones with both versions on.
function ns.ShowConflicts(all)
	local rows = Ordered(not all and Undecided or nil)
	if #rows == 0 then
		if all then ns.Print(L["No addon conflicts: none of your loaded addons has its own version of a " ..
			"Cinematic feature."]) end
		return false
	end
	if not window then CreateWindow() end
	list, page = rows, 1
	local addons, seen = {}, {}
	for _, row in ipairs(rows) do
		if not seen[row.addon] then
			seen[row.addon] = true
			addons[#addons + 1] = row.addon
		end
	end
	window.sub:SetText(L["%s has its own version of %d things Cinematic does. Pick whose plays. You can " ..
		"change it any time on Addons > Conflicts."]:format(table.concat(addons, ", "), #rows))
	window:Show()
	ShowCards()
	return true
end

-- At login (and /reload): after the welcome window's (1 s). With that open,
-- not over it: once it's closed (its Customize page done too).
local function LoginShow()
	if InCombatLockdown() or not (ns.db and ns.db.enabled) then return end
	ns.ShowConflicts()
end
local loginWatcher = CreateFrame("Frame")
loginWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
loginWatcher:SetScript("OnEvent", function(_, _, isLogin, isReload)
	if (isLogin or isReload) and ns.db and ns.db.enabled then
		C_Timer.After(2, function()
			if not (ns.AfterWelcome and ns.AfterWelcome(LoginShow)) then LoginShow() end
		end)
	end
end)
