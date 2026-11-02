-- The Cards page (Cards.lua's), in the Visions hub under one icon with two
-- folder tabs. Events: a row for each event, its tick and its Show in row
-- (GridRows.lua), as the frames pages' grids, and under each the style it
-- uses, with a link to it. Style: the Default style, the look every card
-- starts from, or an event's own (each setting following the Default style
-- until it's given its own) and what's its alone (when it fires, its lines,
-- its words, its sounds), picked from one dropdown.

local _, ns = ...
local L = ns.L

local NOTE_W = 440
-- What the Style tab shows: "default" (the Default style) or an event's id
-- (the links on other pages and under the Events tab's rows pick one).
local CARD = { now = "default" }

-- The pages' tabs, picked 1 or 2. title: the page's, put under them.
local function CardTabs(content, title, picked)
	local panel = ns.PageTabs(content, {
		{ L["Events"], "Card Vision", L["Each event's card on or off, and where it shows."] },
		{ L["Style"], "Card Style", L["How the cards look: the Default style every card starts from, and each " ..
			"event's own, with a preview."] },
	}, picked)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
end

-- For the pages its moments used to be on: a line saying where they are
-- now, and a button there (event: the Style tab with that one picked).
-- A frame holding both, to anchor or stack.
function ns.CardsLink(content, text, event)
	local kit = ns.lowHealthKit
	local holder = CreateFrame("Frame", nil, content)
	holder:SetSize(420, 22)
	local label = kit.Label(holder, "GameFontHighlightSmall", text)
	label:SetPoint("LEFT", 2, 0)
	local button = ns.PanelButton(holder)
	button:SetSize(110, 22)
	button:SetText(L["Card Vision"])
	kit.Tooltip(button, L["Opens the Card Vision page."])
	button:SetScript("OnClick", function()
		if event then CARD.now = event end
		ns.OpenOptions(event and "Card Style" or "Card Vision")
	end)
	button:SetPoint("LEFT", label, "RIGHT", 10, 0)
	return holder
end

-- A made-up card for the Default style's preview and Test: the zone you're
-- in, as the Zone event would show it.
local function DefaultSample()
	local card = ns.CardSample("zone") or {}
	if not card.name then card.name = GetRealZoneText and GetRealZoneText() or "Darkshore" end
	return card
end

-- The preview: the screen's shape (or a height given), the scene behind, a
-- card played on it, the event which() gives (nil: the Default style's, a
-- zone's card). The General page's screen too.
function ns.MakeCardPreview(parent, width, fixedH, which)
	local preview = CreateFrame("Frame", nil, parent)
	preview:SetSize(width, fixedH or 270)
	if preview.SetClipsChildren then preview:SetClipsChildren(true) end
	local stage = CreateFrame("Frame", nil, preview)
	stage:SetAllPoints()
	stage:SetFrameLevel(preview:GetFrameLevel() + 2)
	local caption = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetText(L["Preview"])
	caption:SetPoint("TOPLEFT", 6, -5)
	caption.searchSkip = true
	function preview:Refresh()
		if not self:IsVisible() then
			return -- (the kit refreshes every page's controls)
		end
		if ns.FitStylePreview(self) then return end -- (resized: it played from there)
		local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
		local previewH = fixedH or math.floor(width * screenH / math.max(screenW, 1) + 0.5)
		self:SetHeight(previewH)
		ns.StyleScene(self)
		local id = which and which()
		if id == "default" then id = nil end
		local card = id and ns.CardSample(id) or DefaultSample()
		card.sound = nil
		ns.PlayCard(stage, ns.CardLook(id), self:GetWidth(), previewH, previewH / math.max(screenH, 1), card)
	end
	return preview
end

-- (Dropdowns: { value, text, tip } each, read as it opens.)
local function List(choices)
	return function()
		local list = {}
		for i, choice in ipairs(choices) do list[i] = { value = choice[1], text = choice[2], tip = choice[3] } end
		return list
	end
end

-- The Style tab's look rows (rows: ns.StyleRows', their keys the Default
-- style's: the tab's fieldOf turns them into the picked event's). icon: a
-- button for an event's own icon, after the Icon tick.
local function LookRows(content, stack, rows, icon)
	local On, Get = rows.On, rows.Get
	local function Banner() return Get("cardStyle") == "banner" end
	local function InBar(db)
		local place = Get("cardPlace")
		return On(db) and not Banner() and (place == "top" or place == "bottom")
	end
	stack:Header(content, L["Where"])
	rows.Dropdown(L["Place:"], "cardPlace", List({
		{ "screen", L["On the screen"], L["In the middle of the screen (a subtitle: low on it)."] },
		{ "top", L["Top letterbox bar"] },
		{ "bottom", L["Bottom letterbox bar"] },
		{ "third", L["Lower third"], L["Low on the left of the screen, as a film names someone, its line fading " ..
			"out to the right."] },
	}), L["Where the card shows: in the middle of the screen, in a letterbox bar or in the lower third. (A " ..
		"banner goes across the middle.)"], function(db) return On(db) and not Banner() end)
	rows.Dropdown(L["In the bar:"], "cardAlign", List({
		{ "left", L["Left"] },
		{ "center", L["Center"] },
		{ "right", L["Right"] },
	}), L["Where in the letterbox bar the card sits."], InBar)
	rows.Slider("cardBarScale", L["Letterbox scale"], 20, 100, 1, "%d%%", 100,
		L["The words' height next to the bar's: they grow and shrink with your letterbox. (With no letterbox " ..
		"up, a bar as tall as your letterbox's comes in for the card.)"], InBar)
	rows.Check("cardBarFallback", L["Lower third with no letterbox"],
		L["Ticked: while no letterbox is up, the card shows in the lower third. Unticked: a bar of its own " ..
		"comes in for it."], InBar)

	stack:Header(content, L["Text"])
	rows.Dropdown(L["Style:"], "cardStyle", List({
		{ "title", L["Title card"], L["Big words in the middle of the screen, the rest under them."] },
		{ "subtitle", L["Subtitle"], L["A small line low on the screen, where a film's subtitles go."] },
		{ "chapter", L["Chapter line"], L["The words over a line that draws out, as a new scene starts."] },
		{ "banner", L["Banner"], L["Across the middle of the screen on a dark band with soft edges, coming in " ..
			"and going slowly, as YOU DIED does."] },
	}), L["How the card is set: a title card, a subtitle, a chapter line or a banner."])
	rows.Dropdown(L["Animation:"], "cardAnim", List({
		{ "fade", L["Fade"], L["The card fades in and out."] },
		{ "reveal", L["Reveal"], L["The words open out from their middle (or from their side, in the lower third " ..
			"or at a bar's side), the line drawing out with them; the other lines rise in after."] },
		{ "track", L["Tracking in"], L["The letters start spread apart and close up, as a film's title comes in; " ..
			"the other lines rise in after. A name the game keeps secret (a boss's before its fight, on retail) " ..
			"opens as Reveal instead."] },
		{ "type", L["Typewriter"], L["The words come in a letter at a time from the left, as if typed; the " ..
			"other lines rise in after. A secret name opens as Reveal instead."] },
	}), L["How the card comes in."])
	rows.Look(L["Look:"], L["Words"], {
		font = { "cardFont", L["Words in Russian, Korean or Chinese keep the game's font, so their letters show."] },
		textSize = function(look)
			look.Slider("cardSize", L["Size"], 14, 80, 1, "%d", 1,
				L["How tall the words are on the screen; the other lines go by them. (In a letterbox bar: " ..
				"Letterbox scale.)"], function(db) return On(db) and not InBar(db) end)
		end,
		outline = { "cardOutline", L["A border round the letters."], names = { [0] = L["None"], L["Thin"], L["Thick"] } },
		outlineColor = function(look)
			look.Color(L["Outline color"], { "cardOutlineR", "cardOutlineG", "cardOutlineB" },
				L["Pick the outline's color."], function(db)
					local value = look.Get("cardOutline")
					if value == -1 then value = ns.GeneralStyleValue("cardOutline") end
					return look.On(db) and (tonumber(value) or 0) > 0
				end)
		end,
		textColor = function(look)
			look.Color(L["Color"], { "cardR", "cardG", "cardB" },
				L["The words' color; the lines with them in a lighter shade."])
		end,
		shadow = { "cardShadow" },
	})

	stack:Header(content, L["Timing and extras"])
	rows.Slider("cardHold", L["Stays"], 0.5, 12, 0.5, "%.1f s", 1,
		L["How long the card stays between fading in and out (Typewriter: once typed)."])
	local pulse = rows.Slider("cardPulse", L["Edge pulse"], 0, 100, 1, "%d%%", 100,
		L["The edges of the screen flash for a moment as the card shows, this strongly. 0: no pulse."])
	rows.Swatch(pulse, nil, { "cardPulseR", "cardPulseG", "cardPulseB" }, L["Pick the pulse's color."],
		function(db) return On(db) and (tonumber(Get("cardPulse")) or 0) > 0 end)
	local iconCheck = rows.Check("cardIconShow", L["Icon"], L["An icon before the words: each event's own (a map " ..
		"for a zone, a skull for a boss...), unless it's given another with the button beside this."])
	if icon then icon(iconCheck) end
end

-- The settings an event can have of its own, as the Style tab lists them.
local GROUPS = {
	{ "Place", { "Place" } }, { "In the bar", { "Align" } }, { "Letterbox scale", { "BarScale" } },
	{ "Lower third with no letterbox", { "BarFallback" } }, { "Style", { "Style" } }, { "Animation", { "Anim" } },
	{ "Font", { "Font" } }, { "Size", { "Size" } }, { "Outline", { "Outline" } },
	{ "Outline color", { "OutlineR", "OutlineG", "OutlineB" } }, { "Shadow", { "Shadow" } },
	{ "Color", { "R", "G", "B" } }, { "Stays", { "Hold" } }, { "Edge pulse", { "Pulse" } },
	{ "Pulse color", { "PulseR", "PulseG", "PulseB" } }, { "Icon", { "IconShow" } }, { "Icon picture", { "Icon" } },
}
local function OwnGroup(id, group)
	for _, field in ipairs(group[2]) do
		if ns.CardIsOwn(id, field) then return true end
	end
	return false
end
local function Follow(id, group)
	local db = ns.GetDB()
	for _, field in ipairs(group[2]) do db[ns.CardKey(field, id)] = "default" end
end
-- The names of an event's own settings, in the list's order.
local function OwnNames(id)
	local names = {}
	for _, group in ipairs(GROUPS) do
		if OwnGroup(id, group) then names[#names + 1] = L[group[1]] end
	end
	return names
end

-- The style an event starts from, by name: the Default style, a ready-made
-- one (Cards.lua's CARD_STYLES), or for a subzone following the zone, the
-- zone's.
local function BaseName(id)
	local event = ns.CARD_BY_ID[id]
	local db = ns.GetDB()
	if event and event.parent and (db["cardBase_" .. id] or "follow") == "follow" then
		return L["Follows %s"]:format(L[ns.CARD_BY_ID[event.parent].name])
	end
	local base = ns.CardBase(id)
	local style = ns.CARD_STYLE_BY_ID[base]
	return style and L[style.name] or L["Default style"]
end

-- The style an event uses, in a few words: the one it starts from, and how
-- many settings it has of its own ("Combat +2").
local function StyleSummary(id)
	local names = OwnNames(id)
	return BaseName(id) .. (#names > 0 and (" +" .. #names) or "")
end

-- The styles an event can start from, for a dropdown: the Default style, the
-- ready-made ones, and for a subzone its zone's first.
local function StyleChoices(id)
	local list = {}
	local event = ns.CARD_BY_ID[id]
	if event and event.parent then
		list[#list + 1] = { value = "follow", text = L["Follows %s"]:format(L[ns.CARD_BY_ID[event.parent].name]),
			tip = L["Whatever style that event starts from."] }
	end
	list[#list + 1] = { value = "default", text = L["Default style"], tip = L["The look every card starts from."] }
	for _, style in ipairs(ns.CARD_STYLES) do list[#list + 1] = { value = style.id, text = L[style.name] } end
	return list
end
-- An event's starting style as a setting, for a dropdown.
local function BaseField(id)
	local key = "cardBase_" .. id
	return { get = function() return ns.GetDB()[key] end, set = function(value) ns.GetDB()[key] = value end }
end

-- Events: each event's tick and Show in row.
local TIPS = {
	combatIn = "As a fight starts: a word (Combat), a pulse round the screen's edges and a sound.",
	combatOut = "As a fight ends: a word (Respite) and a sound. Not after a fight shorter than its setting on " ..
		"the Style tab.",
	boss = "A boss's name as its fight starts (or before it, as you first target it or come near it), the " ..
		"dungeon under it and \"Boss 2 of 3\" over it. Once a run for each boss, in place of Entering combat's.",
	zone = "As you come into a new zone, its name as a card in place of the game's own. The time of day at " ..
		"login goes on it.",
	subzone = "As you come into a subzone (a town, a camp, a landing) too, the zone's name small under it. Only " ..
		"with Zone ticked.",
	login = "On a real login (not a reload), what you did last time you played: where you spent the most time, " ..
		"quests done, a level reached and bosses killed. Only what happened, and nothing if nothing did; never " ..
		"in a fight, nor after more than two weeks away.",
	time = "When the time of day changes during play (not in combat), its name with a fitting sound: a rooster " ..
		"at dawn, a horse in the morning, your faction's bell at midday, frogs in the evening, an owl at dusk and " ..
		"a wolf at night.",
	attack = "When the LocalDefense channel says a place is under attack (\"Dun Algaz is under attack!\"), with " ..
		"your faction's city bell. The same place at most once every 90 seconds.",
	death = "Shortly after the death camera starts: YOU DIED across the middle of the screen, \"wasted\" or " ..
		"words of your own. Only with the death camera on (the Die row on the Scenes page).",
}
local FIGHT_OPTS = { anyFight = true, omit = { combatShow = true, enemyShow = true, friendlyShow = true } }
local STORY_OPTS = { anyFight = true, quiet = true, omit = { enemyShow = true, friendlyShow = true } }

-- The lists a Show in row's ticks are kept in (its Always: cardAlways_<id>).
local ROW_LISTS = { "combatShow", "calmShow", "quietShow", "camShow", "enemyShow", "friendlyShow", "bgShow",
	"worldShow", "cityShow", "groupShow", "instanceShow", "frameRules", "tankHide", "healerHide", "damageHide" }

-- Events: a row for each event, as the Scenes page's: its tick, name and
-- chips (the style it uses, and where it shows when not everywhere), its
-- settings in a drawer under it (When: its Show in row; Style: the one it
-- starts from, Edit style and Test).
function ns.CreateCardsPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	CardTabs(content, title, 1)
	local intro = kit.PageIntro(content, title,
		L["Every moment that puts words on your screen, as a card: going into a fight and coming out of it, a " ..
		"boss, a new zone, what you did last time, the time of day, a place under attack, your death. A row for " ..
		"each: its tick, the style it uses and where it shows; click it for its settings. How they look: the " ..
		"Style tab. One card at a time: a more important one cuts in, a less important one waits for it."])
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["On: each card shows as its row says. Off: none of them do, and each row keeps its tick for when you " ..
		"turn this back on."], intro)
	local stack = kit.Stack(switch, "check")
	stack:Header(content, L["Events"])
	local grid = ns.GRID_KIT
	local columns = ns.FRAME_COLUMNS
	local items = {}
	for i, event in ipairs(ns.CARD_EVENTS) do
		local id, key, alwaysKey = event.id, "card:" .. event.id, "cardAlways_" .. event.id
		local opts = event.fight and FIGHT_OPTS or STORY_OPTS
		local function Key() return key end
		local function SetAlways(value) ns.GetDB()[alwaysKey] = value end
		local parts = ns.ListRowParts(Key, columns, nil, SetAlways, opts)
		-- (What the page's Reset puts back.)
		kit.RecordKey(content, alwaysKey)
		kit.RecordKey(content, "cardBase_" .. id)
		for _, list in ipairs(ROW_LISTS) do
			kit.RecordKey(content, list)
			grid.RecordRow(content, list, key)
		end
		items[i] = {
			id = id, label = L[event.name], tip = L[TIPS[id]], on = event.on,
			onTip = L["Ticked: this card shows where its row says. Unticked: never."],
			dim = function()
				return not (ns.GetDB()[event.on] and (not event.needs or ns.GetDB()[ns.CARD_BY_ID[event.needs].on]))
			end,
			chips = function()
				local db = ns.GetDB()
				local own = #OwnNames(id)
				local list = { { StyleSummary(id), own > 0 and ns.ROW_CHIP.gold or ns.ROW_CHIP.plain } }
				local rule = db.frameRules and db.frameRules[key]
				if type(rule) == "string" and rule:find("%S") then
					list[#list + 1] = { rule, ns.ROW_CHIP.when }
				elseif not db[alwaysKey] then
					local names = {}
					for c = 2, #columns do
						if not opts.omit[columns[c][3]] and columns[c][2](key) then names[#names + 1] = columns[c][1] end
					end
					if not opts.omit.combatShow and ns.IsCalmShowOn(key) then names[#names + 1] = L["Calm Timer"] end
					if opts.quiet and ns.IsQuietShowOn(key) then names[#names + 1] = L["Out of combat"] end
					list[#list + 1] = #names == 0 and { L["Never"], ns.ROW_CHIP.never }
						or { table.concat(names, ", "), ns.ROW_CHIP.when }
				end
				for _, roleList in ipairs({ "tankHide", "healerHide", "damageHide" }) do
					if ns.RoleHidden(db, roleList, key) then
						list[#list + 1] = { L["Some roles"], ns.ROW_CHIP.when }
						break
					end
				end
				return list
			end,
			lines = {
				{ name = L["When"], build = function(drawer, At)
					local layout = { groups = event.fight and { ns.GRID_LOCATION } or { ns.GRID_COMBAT, ns.GRID_LOCATION },
						roles = grid.rolesMenu, edit = true }
					At(ns.GridRow(grid, drawer, 0, layout, {
						band = 1,
						always = { isOn = function() return ns.GetDB()[alwaysKey] and true or false end, set = SetAlways,
							tip = L["Shows wherever you are. (The other columns then have nothing to add.)"] },
						menus = parts.menus,
						rule = { key = Key, label = function() return L[event.name] end, grid = parts.grid,
							words = parts.words, apply = parts.apply },
						roles = { key = Key, tip = L["Tick roles to show it only while you're one of them (your " ..
							"specialization's, or the one picked in the group finder), whatever the row says. None " ..
							"ticked (-): every role."] },
					}))
				end },
				{ name = L["Style"], build = function(drawer, At)
					local base = kit.Dropdown(drawer, BaseField(id), function() return StyleChoices(id) end, 170)
					if base then
						At(base)
						kit.Tooltip(base, L["The style this card starts from: the Default style or a ready-made one. " ..
							"Settings you give it on the Style tab go over it."])
					end
					local edit = ns.PanelButton(drawer)
					edit:SetSize(90, 22)
					edit:SetText(L["Edit style"])
					At(edit, ns.ROW_LIST_LABEL_W + 180)
					kit.Tooltip(edit, L["Opens the Style tab with this event picked."])
					edit:SetScript("OnClick", function()
						CARD.now = id
						ns.ShowHubPage("Card Style")
					end)
					local test = ns.PanelButton(drawer)
					test:SetSize(60, 22)
					test:SetText(L["Test"])
					At(test, ns.ROW_LIST_LABEL_W + 276)
					kit.Tooltip(test, L["Shows its card now, to see how it looks (close the settings to see it)."])
					test:SetScript("OnClick", function() ns.CardTest(id) end)
				end },
			},
		}
	end
	local list = ns.RowList(kit, content, items)
	stack:Add(list, "label")
	stack:Note(content, L["A style with +2 has two settings of its own over the one it starts from (the Style tab " ..
		"lists them)."], NOTE_W)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card Vision")
end

-- What a page builds for each event, shown only while it's the one picked
-- (Now()): Part(id, build) then Finish() once the page is built. Each part
-- starts where the first began. A control that shows and hides itself
-- (ownVisibility) is left to do so on its event.
local function Parts(kit, content, stack, Now)
	local owner, hidden, start = {}, {}, nil
	local function Each(fn)
		for _, object in ipairs({ content:GetChildren() }) do fn(object) end
		for _, object in ipairs({ content:GetRegions() }) do fn(object) end
	end
	local parts = {}
	function parts.Part(id, build)
		if start then stack:Continue(start[1], start[2]) else start = { stack.last, stack.kind } end
		local before = {}
		Each(function(object) before[object] = true end)
		build()
		Each(function(object) if not before[object] then owner[object] = id end end)
	end
	function parts.Finish()
		local apply = CreateFrame("Frame", nil, content)
		apply:SetSize(1, 1)
		apply:Hide()
		apply.pageSwitch = false
		apply.Refresh = function()
			local now = Now()
			Each(function(object)
				local id = owner[object]
				if id == now then
					if hidden[object] then
						hidden[object] = nil
						if not object.ownVisibility then object:Show() end
					end
				elseif id and object:IsShown() then
					hidden[object] = true
					object:Hide()
				end
			end)
		end
		kit.AddControl(apply)
	end
	return parts
end

-- A row with an edit box for words (key: "" for none; the defaults shown
-- and kept as such in any language).
local function WordsRow(kit, content, stack, key, label, tip)
	local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
	name:SetSize(150, 22)
	local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	if ns.SkinEditBox then ns.SkinEditBox(box) end
	box:SetSize(180, 22)
	box:SetAutoFocus(false)
	box:SetMaxLetters(40)
	box:SetPoint("LEFT", name, "LEFT", 160, 0)
	kit.Tooltip(box, tip)
	kit.RecordKey(content, key)
	local default = ns.DEFAULTS[key]
	local function Save(self)
		local words = (self:GetText() or ""):match("^%s*(.-)%s*$")
		ns.GetDB()[key] = (default ~= "" and words == L[default]) and default or words
		self:ClearFocus()
	end
	box:SetScript("OnEnterPressed", Save)
	box:SetScript("OnEditFocusLost", Save)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.CardWords(key))
		self:ClearFocus()
	end)
	box.Refresh = function(self)
		if not self:HasFocus() then self:SetText(default == "" and (ns.GetDB()[key] or "") or ns.CardWords(key)) end
	end
	kit.AddControl(box)
	return box
end

-- Style: the Default style or an event picked from one dropdown (the Default
-- style first), its look, and an event's options under it.
function ns.CreateCardStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	CardTabs(content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["How the cards look. Default style: the look every card starts from. An event: its own look, each " ..
		"setting following the Default style (a subzone's, the zone's) until you change it here, then the " ..
		"event's own until you put it back; and under it, what's the event's alone. Changes play at once in the " ..
		"preview."])
	local preview
	local function Changed()
		if preview then preview:Refresh() end
	end
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["On: each card shows as the Events tab says, looking as this tab says. Off: none of them do. Each " ..
		"setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local function IsDefault() return CARD.now == "default" end

	-- The look's rows edit the Default style's settings, or the picked event's
	-- own (showing what shows: its own, else what it follows; a change makes
	-- it its own).
	local isField = {}
	for _, field in ipairs(ns.CARD_FIELDS) do isField[field[1]] = true end
	local fields = {}
	local function FieldOf(key)
		local name = type(key) == "string" and key:match("^card(%u%w*)$")
		if not (name and isField[name]) then return key end
		fields[name] = fields[name] or {
			get = function()
				if IsDefault() then return ns.GetDB()[key] end
				return ns.CardRaw(CARD.now, name)
			end,
			set = function(value) ns.GetDB()[ns.CardKey(name, not IsDefault() and CARD.now or nil)] = value end,
		}
		return fields[name]
	end
	for _, field in ipairs(ns.CARD_FIELDS) do
		kit.RecordKey(content, ns.CardKey(field[1]))
		for _, event in ipairs(ns.CARD_EVENTS) do kit.RecordKey(content, ns.CardKey(field[1], event.id)) end
	end
	for _, event in ipairs(ns.CARD_EVENTS) do kit.RecordKey(content, "cardBase_" .. event.id) end
	local rows = ns.StyleRows(kit, content, stack, Changed, "cards", FieldOf)

	-- What it shows: one row, so it reads as what the rest of the tab is
	-- about: the event's icon, "Editing", the dropdown (the Default style,
	-- then each event) and a line saying what that is.
	local bar = CreateFrame("Frame", nil, content)
	bar:SetSize(480, 30)
	stack:Add(bar, "label")
	local barIcon = bar:CreateTexture(nil, "ARTWORK")
	barIcon:SetSize(26, 26)
	barIcon:SetPoint("LEFT", 2, 0)
	barIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local editing = kit.Label(bar, "GameFontNormalLarge", L["Editing"])
	editing:SetPoint("LEFT", barIcon, "RIGHT", 8, 0)
	local barLine = kit.Label(bar, "GameFontHighlightSmall", "")
	barLine:SetWidth(320)
	barLine:SetJustifyH("LEFT")
	barLine:SetWordWrap(false)
	local picker = kit.Dropdown(content, { get = function() return CARD.now end, set = function(id) CARD.now = id end },
		function()
			local list = { { value = "default", text = L["Default style"],
				tip = L["The look every card starts from."] } }
			for _, event in ipairs(ns.CARD_EVENTS) do list[#list + 1] = { value = event.id, text = L[event.name] } end
			return list
		end, 230, Changed)
	if picker then
		picker:SetPoint("LEFT", editing, "RIGHT", 12, 0)
		picker:SetFrameLevel(bar:GetFrameLevel() + 3)
		picker.pageSwitch = false
		kit.Tooltip(picker, L["The Default style, or the event whose card this tab shows and sets."])
		barLine:SetPoint("LEFT", picker, "RIGHT", 12, 0)
	else
		barLine:SetPoint("LEFT", editing, "RIGHT", 12, 0)
	end
	bar.pageSwitch = false
	bar.Refresh = function()
		local event = ns.CARD_BY_ID[CARD.now]
		barIcon:SetTexture(event and event.icon or "Interface\\Icons\\INV_Misc_Book_09")
		if not event then
			barLine:SetText(L["The look every card starts from."])
		else
			local names = OwnNames(CARD.now)
			barLine:SetText(L["Starts from: %s"]:format("|cffffd100" .. BaseName(CARD.now) .. "|r")
				.. (#names > 0 and ("  " .. L["Its own: %s"]:format(table.concat(names, ", "))) or ""))
		end
	end
	kit.AddControl(bar)

	preview = ns.MakeCardPreview(content, 480, nil, function() return CARD.now end)
	preview.pageSwitch = false
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)
	ns.StylePreviewTest(preview, kit, L["Plays the card in the preview and on your screen, as it will look, with " ..
		"its sound (close the settings to see it there). The Default style: the zone you're in, as the Zone " ..
		"event would show it."], function()
			preview:Refresh()
			if IsDefault() then
				local card = DefaultSample()
				card.defaultLook = true
				ns.Cards.Fire("zone", card, true)
			else
				ns.CardTest(CARD.now)
			end
		end)

	-- The style the event starts from (the Default style's: none, it's what
	-- they all start from).
	rows.Dropdown(L["Starts from:"], { get = function() return not IsDefault() and ns.GetDB()["cardBase_" .. CARD.now] or nil end,
		set = function(value) if not IsDefault() then ns.GetDB()["cardBase_" .. CARD.now] = value end end },
		function() return IsDefault() and {} or StyleChoices(CARD.now) end,
		L["The style this card starts from: the Default style or a ready-made one. The settings below that you " ..
		"change go over it, as its own."], function(db) return rows.On(db) and not IsDefault() end)

	-- Which settings it has of its own, and a dropdown to put one back.
	local own = kit.Label(content, "GameFontHighlightSmall", "")
	own:SetWidth(NOTE_W)
	own:SetJustifyH("LEFT")
	stack:Add(own, "label")
	own.Refresh = function(self)
		if IsDefault() then
			self:SetText(L["The look every card starts from: each event follows it setting by setting, until it's " ..
				"given its own (pick the event above)."])
			return
		end
		local names = OwnNames(CARD.now)
		if #names == 0 then
			self:SetText(L["None of its own: it's all %s."]:format(BaseName(CARD.now)))
		else
			self:SetText(L["Its own: %s. The rest: %s."]:format(table.concat(names, ", "), BaseName(CARD.now)))
		end
	end
	kit.AddControl(own)
	local back = rows.Dropdown(L["Back to its style:"], { get = function() return nil end, set = function(index)
		if IsDefault() then return end
		if index == "all" then
			for _, group in ipairs(GROUPS) do Follow(CARD.now, group) end
		elseif GROUPS[index] then
			Follow(CARD.now, GROUPS[index])
		end
	end }, function()
		local list = {}
		if IsDefault() then return list end
		for i, group in ipairs(GROUPS) do
			if OwnGroup(CARD.now, group) then list[#list + 1] = { value = i, text = L[group[1]] } end
		end
		if #list > 1 then list[#list + 1] = { value = "all", text = L["All of them"] } end
		return list
	end, L["Puts one of the event's own settings back, to come from the style it starts from again."], function(db)
		return not IsDefault() and #OwnNames(CARD.now) > 0 and rows.On(db)
	end)
	if back and back.SetDefaultText then back:SetDefaultText(L["Pick a setting"]) end

	-- A whole look in one pick, for the Default style: one of the ready-made
	-- styles (the events' own settings, and the styles they start from, left
	-- as they are).
	local presetKeys = {}
	for _, field in ipairs(ns.CARD_FIELDS) do presetKeys[#presetKeys + 1] = ns.CardKey(field[1]) end
	-- (The ready-made styles, the Lower third first: the Default style's own.)
	local presetList = { { L["Lower third"], L["The words over a line low on the left, the rest under it, its " ..
		"letters closing up."], {} } }
	for _, style in ipairs(ns.CARD_STYLES) do
		local values = {}
		for field, value in pairs(style.look) do values[ns.CardKey(field)] = value end
		presetList[#presetList + 1] = { L[style.name], nil, values }
	end
	local presets = rows.PresetMenu(presetList, presetKeys)
	if presets then kit.GreyUnless(presets, function(db) return rows.On(db) and IsDefault() end) end

	-- The icon's own picture: a button after the Icon tick opening every icon
	-- the game has (IconBrowser.lua). Right-click: back to the event's own.
	-- (The Default style's: each event's own icon.)
	local browser = ns.IconBrowser(canvas, function(key, icon)
		ns.GetDB()[key] = icon
		Changed()
		kit.Refresh()
	end)
	local function IconButton(after)
		local button = CreateFrame("Button", nil, content)
		button:SetSize(22, 22)
		button:SetPoint("LEFT", after.Text or after.text or after, "RIGHT", 10, 0)
		local border = button:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.45, 0.38, 0.2, 1)
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", -2, 2)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local hl = button:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(icon)
		hl:SetColorTexture(1, 1, 1, 0.2)
		kit.Tooltip(button, L["The icon. Click to pick it from all the game's. Right-click: back to the event's own."])
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", function(self, mouse)
			if IsDefault() then return end
			local key = ns.CardKey("Icon", CARD.now)
			if mouse == "RightButton" then
				ns.GetDB()[key] = "default"
				Changed()
				kit.Refresh()
				return
			end
			browser:Open(self, key, ns.CardLook(CARD.now).combatIconIn)
		end)
		button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
		button:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
		button.Refresh = function(self)
			self:SetShown(not IsDefault())
			icon:SetTexture(not IsDefault() and ns.CardLook(CARD.now).combatIconIn or nil)
		end
		kit.GreyUnless(button, function(db) return rows.On(db) and ns.CardRaw(CARD.now, "IconShow") end)
		kit.AddControl(button)
	end
	LookRows(content, stack, rows, IconButton)

	-- What's each event's alone, under its look.
	local parts = Parts(kit, content, stack, function() return CARD.now end)
	local function Check(key, label, tip, test)
		local check = stack:Add(kit.Check(content, key, label, tip), "check")
		if test then kit.GreyUnless(check, test) end
		return check
	end
	local function Header(text) stack:Header(content, text) end
	parts.Part("combatIn", function()
		Header(L["Words"])
		WordsRow(kit, content, stack, "combatTextIn", L["Words:"],
			L["The words going into a fight. Empty: none, just the rest of the card."])
		ns.CombatSoundRulesSection(kit, content, stack) -- (CombatSoundRules.lua)
	end)
	parts.Part("combatOut", function()
		Header(L["Words"])
		WordsRow(kit, content, stack, "combatTextOut", L["Words:"],
			L["The words coming out of a fight. Empty: none, just the rest of the card."])
		Header(L["When"])
		stack:Add(kit.Slider(content, "combatMinFight", L["Not after fights under"], 0, 10, 1, "%d s"), "slider")
		stack:Note(content, L["No card coming out of a fight shorter than this, so a stray hit doesn't bring it " ..
			"up. 0: after every fight. Its sounds: Entering combat's rules (one list for both)."], NOTE_W)
	end)
	parts.Part("boss", function()
		Header(L["When"])
		Check("combatBossPull", L["Boss pulled"], L["The boss's name as its fight starts, in place of Entering " ..
			"combat's card. Once a run for each boss."])
		Check("combatBossTarget", L["Boss targeted"], L["The boss's name as you first target it, before the " ..
			"fight. A dungeon or raid boss is told by its level: a skull, or on retail two over yours."])
		Check("combatBossNear", L["Boss nearby"], L["The boss's name as you first come within about 28 yards of " ..
			"it, before the fight. A dungeon or raid boss is told by its level: a skull, or on retail two over yours."])
		Header(L["Lines"])
		Check("combatBossSub", L["Dungeon line"],
			L["The dungeon or raid and its difficulty under the boss's name (beside it in a letterbox bar)."])
		if EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex then
			Check("combatBossCount", L["Boss number"],
				L["\"Boss 2 of 3\" over the name, from the Adventure Guide, as the fight starts (not in a letterbox bar)."])
		end
		ns.CombatSoundRulesSection(kit, content, stack, true) -- (its boss fights' sounds)
	end)
	parts.Part("zone", function()
		Header(L["Lines"])
		Check("storyZoneTerritory", L["Territory"], L["Under the name, what the game says of the place: " ..
			"Contested Territory, Sanctuary, Alliance or Horde Territory..."])
		Check("timeOfDayMessage", L["Time of day at login"], L["Dawn, Morning, Midday, Afternoon, Evening, Dusk or " ..
			"Night as you log in or reload: over the name on this card, or under the game's zone name with Zone " ..
			"unticked. Follows the clock picked on the Tint page."])
	end)
	parts.Part("subzone", function()
		stack:Note(content, L["Only with Zone ticked: it takes the game's zone text away. Its look follows Zone's " ..
			"until it's given its own here; its lines are Zone's."], NOTE_W)
	end)
	parts.Part("login", function()
		Header(L["Where"])
		Check("storyRecapUnder", L["Under the zone name"], L["One line under the game's zone name, as it comes in " ..
			"at login, in place of a card. (The look above is the card's.)"])
		stack:Add(kit.Slider(content, "storyRecapDelay", L["After"], 0, 8, 0.5, "%.1f s"), "slider")
		Header(L["Details"])
		local heading = kit.Dropdown(content, "storyRecapHeading", List({
			{ "lasttime", L["Last time"] },
			{ "previously", L["Previously"] },
			{ "previouslyon", L["Previously, on %s"]:format(UnitName("player") or "...") },
			{ "sofar", L["Your story so far"] },
			{ "none", L["None"] },
		}), 200)
		if heading then
			local name = stack:Add(kit.Label(content, "GameFontHighlight", L["Heading:"]), "label")
			name:SetSize(150, 30)
			name:SetJustifyV("MIDDLE")
			heading:SetPoint("LEFT", name, "RIGHT", 4, 0)
			kit.Tooltip(heading, L["The words before it all (on a card, over the zone name)."])
		end
		for _, pair in ipairs({
			{ "storyRecapZone", L["Zone"], L["The zone you spent the most time in (on a card, its big name)."] },
			{ "storyRecapPlayed", L["Time played"], L["How long the session was."] },
			{ "storyRecapQuests", L["Quests done"], L["How many quests you turned in."] },
			{ "storyRecapLevel", L["Level reached"], L["The level you reached, if you went up."] },
			{ "storyRecapBosses", L["Bosses down"], L["How many dungeon or raid bosses you killed."] },
			{ "storyRecapDeaths", L["Deaths"], L["How many times you died."] },
			{ "storyRecapGold", L["Gold earned"], L["How much richer you came out, if you did."] },
			{ "storyRecapIcons", L["Icons"], L["A little icon before each detail: a map, a watch, a quest mark, a " ..
				"skull, coins..."] },
			{ "storyRecapSound", L["Page-turn sound"], L["A page turning as it shows, as a journal opens."] },
		}) do
			Check(pair[1], pair[2], pair[3])
		end
		stack:Note(content, L["It shows only if something happened that's ticked here: quests, a level, bosses, " ..
			"deaths or gold. The zone and time played come with it."], NOTE_W)
	end)
	parts.Part("time", function()
		stack:Note(content, L["Its sound goes with the time of day: a rooster at dawn, a horse in the morning, " ..
			"your faction's bell at midday, frogs in the evening, an owl at dusk and a wolf at night."], NOTE_W)
	end)
	parts.Part("attack", function()
		stack:Note(content, L["With your faction's city bell. The same place shows at most once every 90 seconds."],
			NOTE_W)
	end)
	parts.Part("death", function()
		Header(L["Words"])
		local banner = kit.Dropdown(content, "deathBannerStyle", List({
			{ "youdied", L["YOU DIED"] },
			{ "wasted", L["wasted"], L["A picture: red with a dark outline, on a flat black band, its own colors."] },
			{ "custom", L["Custom"], L["Your own words."] },
		}), 200)
		if banner then
			local name = stack:Add(kit.Label(content, "GameFontHighlight", L["Death banner:"]), "label")
			name:SetSize(150, 30)
			name:SetJustifyV("MIDDLE")
			banner:SetPoint("LEFT", name, "RIGHT", 4, 0)
			kit.Tooltip(banner, L["YOU DIED, \"wasted\" (a picture) or words of your own."])
		end
		local box = WordsRow(kit, content, stack, "deathBannerText", L["Your words:"],
			L["The words the banner shows with Custom picked. Left blank: YOU DIED."])
		kit.GreyUnless(box, function(db) return db.deathBannerStyle == "custom" end)
		stack:Note(content, L["Only with the death camera on (the Die row on the Scenes page)."], NOTE_W)
	end)
	parts.Finish()

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content)) -- (its refresh plays the preview)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card Style", L["Card Vision"])
end
