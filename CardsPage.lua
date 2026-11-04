-- The Cards page (Cards.lua's), in the Visions hub under one icon with two
-- folder tabs. Events: a row for each event, its tick and its Show in row
-- (GridRows.lua), as the frames pages' grids, and under each the style it
-- uses, with buttons to its own pages. Card Types: the styles the cards start
-- from, each changed for every card using it. An event's own pages, opened
-- from its row (no tabs on the page's: their own three, and a way back):
-- Settings, what's its alone (when it fires, its lines, its words); Style,
-- its look (the style it starts from, each setting following it until it's
-- given its own); Sounds.

local _, ns = ...
local L = ns.L

local NOTE_W = 440
-- The event an event's own pages show (the buttons under the Events tab's
-- rows and the links on other pages pick one), and the style the Card Types
-- tab shows.
local CARD = { now = "combatIn", style = "third" }

-- The page's tabs, picked 1 or 2. title: the page's, put under them.
local function CardTabs(content, title, picked)
	local panel = ns.PageTabs(content, {
		{ L["Events"], "Card Vision", L["Each event's card on or off, and where it shows."] },
		{ L["Card Types"], "Card Styles", L["The styles the cards start from: change one for every card using it."] },
	}, picked)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
end

-- An event's own pages' top: the page's two tabs, Events lit (it's under
-- it; a click goes back to it), the event's icon and name as the title, and
-- under them a row of smaller folder tabs, one for each of its three pages
-- (picked 1 to 3). Gives a frame to put the page under (kit.PageIntro's
-- under).
local PAGES = {
	{ "Settings", "Card Settings", "What's this card's alone: when it shows, its lines, its words." },
	{ "Style", "Card Style", "How this card looks, with a preview." },
	{ "Sounds", "Card Sounds", "What this card plays as it shows." },
}
local function CardTop(kit, content, title, picked)
	local panel = ns.PageTabs(content, {
		{ L["Events"], "Card Vision", L["Back to every card's row."], true },
		{ L["Card Types"], "Card Styles", L["The styles the cards start from: change one for every card using it."] },
	}, 1)
	local icon = content:CreateTexture(nil, "ARTWORK")
	icon:SetSize(24, 24)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -10)
	title:ClearAllPoints()
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	local list = {}
	for i, page in ipairs(PAGES) do list[i] = { L[page[1]], L[page[3]] } end
	local sub, _, ShowSub, subBase, subH = ns.FolderTabs(content, list, function(i)
		if i ~= picked then ns.ShowHubPage(PAGES[i][2]) end
	end)
	subBase:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -(44 + subH))
	sub:SetPoint("TOPLEFT", subBase, "TOPLEFT")
	sub:SetPoint("RIGHT", content, "RIGHT", -8, 0)
	sub:SetHeight(1) -- (just its top edge, a line under the tabs)
	ShowSub(picked)
	local under = CreateFrame("Frame", nil, content)
	under:SetSize(1, 1)
	under:SetPoint("TOPLEFT", subBase, "TOPLEFT", 8, -6)
	local holder = CreateFrame("Frame", nil, content)
	holder:SetSize(1, 1)
	holder:Hide()
	holder.pageSwitch = false
	holder.Refresh = function()
		local event = ns.CARD_BY_ID[CARD.now] or ns.CARD_EVENTS[1]
		icon:SetTexture(event.icon)
		title:SetText(L[event.name])
	end
	kit.AddControl(holder)
	return under
end

-- For the pages its moments used to be on: a line saying where they are
-- now, and a button there (event: the Settings tab with that one picked).
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
		ns.OpenOptions(event and "Card Settings" or "Card Vision")
	end)
	button:SetPoint("LEFT", label, "RIGHT", 10, 0)
	return holder
end

-- The preview: the screen's shape (or a height given), the scene behind, a
-- card played on it, the event which() gives (nil: the Zone's, the zone
-- you're in), in the look lookOf() gives (nil: the event's). The General
-- page's screen too.
function ns.MakeCardPreview(parent, width, fixedH, which, lookOf)
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
		local id = which and which() or "zone"
		local card = ns.CardSample(id)
		if id == "zone" and not card.name then card.name = GetRealZoneText and GetRealZoneText() or "Darkshore" end
		card.sound = nil
		local look = lookOf and lookOf() or ns.CardLook(id)
		ns.PlayCard(stage, look, self:GetWidth(), previewH, previewH / math.max(screenH, 1), card)
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

-- The Style tab's look rows (rows: ns.StyleRows', their keys the base
-- look's: the tab's fieldOf turns them into the picked event's). icon: a
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
	local move = rows.Slider("cardOffsetX", L["Move across"], -50, 50, 0.5, "%.1f%%", 100,
		L["Moves the card from where its place puts it: right, or left below 0, as a share of the screen's width."])
	move:Box(L["Move up"], rows.K("cardOffsetY"), -50, 50, 0.5, "%.1f", 100,
		L["Moves the card from where its place puts it: up, or down below 0, as a share of the screen's height."],
		nil, "%")
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
		outline = { "cardOutline", L["A border around the letters."], names = { [0] = L["None"], L["Thin"], L["Thick"] } },
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
			-- (The small lines over and under the words: Cards.lua's Small...)
			look.Font("cardSmallFont", L["The small lines' font, over and under the words."], nil,
				{ "same", L["Same as the words"] }, L["Small lines' font:"])
			look.Slider("cardSmallSize", L["Small lines' size"], 50, 250, 5, "%d%%", 100,
				L["The small lines over and under the words, bigger or smaller than they come (100%: as they come, " ..
				"by the words' size)."])
			local last = look.Choices(L["Small lines' color:"], "cardSmallColor", {
				{ "auto", L["Automatic"], L["Under the words: their color, lighter. Over them: a pale gray."] },
				{ "custom", L["Custom"], L["A color of your own (the swatch), for both lines."] },
			})
			look.Swatch(last, "cardSmallColor", { "cardSmallR", "cardSmallG", "cardSmallB" },
				L["Pick the small lines' color."])
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
	{ "Place", { "Place" } }, { "Position", { "OffsetX", "OffsetY" } }, { "In the bar", { "Align" } }, { "Letterbox scale", { "BarScale" } },
	{ "Lower third with no letterbox", { "BarFallback" } }, { "Style", { "Style" } }, { "Animation", { "Anim" } },
	{ "Font", { "Font" } }, { "Size", { "Size" } }, { "Outline", { "Outline" } },
	{ "Outline color", { "OutlineR", "OutlineG", "OutlineB" } }, { "Shadow", { "Shadow" } },
	{ "Color", { "R", "G", "B" } }, { "Small lines' font", { "SmallFont" } }, { "Small lines' size", { "SmallSize" } },
	{ "Small lines' color", { "SmallColor", "SmallR", "SmallG", "SmallB" } },
	{ "Stays", { "Hold" } }, { "Edge pulse", { "Pulse" } },
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

-- The style an event starts from, by name: a ready-made one (Cards.lua's
-- CARD_STYLES), or for a subzone following the zone, the zone's.
local function BaseName(id)
	local event = ns.CARD_BY_ID[id]
	local db = ns.GetDB()
	if event and event.parent and (db["cardBase_" .. id] or "follow") == "follow" then
		return L["Follows %s"]:format(L[ns.CARD_BY_ID[event.parent].name])
	end
	local base = ns.CardBase(id)
	local style = ns.CARD_STYLE_BY_ID[base]
	return style and L[style.name] or L["Lower third"]
end

-- The style an event uses, in a few words: the one it starts from, and how
-- many settings it has of its own ("Combat +2").
local function StyleSummary(id)
	local names = OwnNames(id)
	return BaseName(id) .. (#names > 0 and (" +" .. #names) or "")
end

-- The styles an event can start from, for a dropdown: the ready-made ones,
-- and for a subzone its zone's first.
local function StyleChoices(id)
	local list = {}
	local event = ns.CARD_BY_ID[id]
	if event and event.parent then
		list[#list + 1] = { value = "follow", text = L["Follows %s"]:format(L[ns.CARD_BY_ID[event.parent].name]),
			tip = L["Whatever style that event starts from."] }
	end
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
	combatIn = "As a fight starts: a word (Combat), a pulse around the screen's edges and a sound.",
	combatOut = "As a fight ends: a word (Respite) and a sound. Not after a fight shorter than its setting on " ..
		"the Settings tab.",
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
	duel = "Your own duels: as you challenge someone or they challenge you, as it starts, and who won. Which of " ..
		"those and their words: the Settings tab.",
	cleared = "As a dungeon's or raid's last boss goes down: its name, the time since you came in and how many " ..
		"times you died.",
	discover = "A place new to you: a zone the first time you're there, a subzone as the game says you " ..
		"discovered it, a dungeon or raid the first time you go in. In place of the Zone or Subzone card.",
	arrival = "As a flight lands: where it took you.",
	rested = "As you come into an inn or a city (not at login, not in a fight): the place's name. The same " ..
		"place at most once every 10 minutes.",
	levelUp = "As you reach a new level (after the fight, if you're in one): the level, the zone and how long " ..
		"it took this session. Max level at the cap.",
	achievement = "An achievement you earn: its name and points.",
	reputation = "As your standing with a faction changes (\"Honored\", with whom under it), a Renown level " ..
		"or a friendship's rank: small in the top bar, but Exalted, Hated, the last Renown level and a " ..
		"friendship's top rank big, as Level up looks.",
	collect = "A new mount in your collection, big as Level up looks; a new pet, small in the top bar.",
	profession = "A profession learned, or its cap raised (Journeyman, Expert...).",
	quest = "As you turn in a story quest (campaign, important or legendary) or a dungeon, raid or elite one: " ..
		"its title.",
	rare = "A rare's name as you first target it, point at it or (out of fights) its nameplate shows. Once " ..
		"each a session.",
	battleground = "A battleground's or arena's name as the gates open, then Victory or Defeat.",
	streak = "Other players you kill without dying, at 2, 3, 5 and every 5 after.",
	death = "Shortly after the death camera starts: YOU DIED across the middle of the screen, \"wasted\" or " ..
		"words of your own. Only with the death camera on (the Die row on the Scenes page).",
	bossDown = "As a dungeon or raid boss goes down, or a world boss you fought: VICTORY ACHIEVED across the " ..
		"middle of the screen in gold, its name under it. Its words: the Settings tab.",
	felled = "As a rare you have targeted dies (yours, not someone else's): ENEMY FELLED across the middle of " ..
		"the screen in gold, its name under it. Its words: the Settings tab.",
	revived = "As you come back to life, resurrected or back in your body: VITALITY RESTORED across the middle " ..
		"of the screen in gold, YOU DIED's other side.",
}
local FIGHT_OPTS = { anyFight = true, omit = { combatShow = true, enemyShow = true, friendlyShow = true } }
local STORY_OPTS = { anyFight = true, quiet = true, omit = { enemyShow = true, friendlyShow = true } }

-- The lists a Show in row's ticks are kept in (its Always: cardAlways_<id>).
local ROW_LISTS = { "combatShow", "calmShow", "quietShow", "camShow", "enemyShow", "friendlyShow", "bgShow",
	"worldShow", "cityShow", "groupShow", "instanceShow", "frameRules" }

-- A Test button says Stop while its card's moments play in turn (Now: its
-- event's id).
local function TestStops(button, Now)
	local wait = 0
	button:HookScript("OnUpdate", function(self, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.2
		self:SetText(ns.CardTestRunning(Now()) and L["Stop"] or L["Test"])
	end)
end

-- Events: a row for each event, as the Scenes page's: its tick, name and
-- chips (the style it uses, and where it shows when not everywhere), its
-- settings in a drawer under it (When: its Show in row; Style: the one it
-- starts from, Style, Sounds and Test).
function ns.CreateCardsPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	CardTabs(content, title, 1)
	local intro = kit.PageIntro(content, title,
		L["Every moment that puts words on your screen, as a card: going into a fight and coming out of it, a " ..
		"boss, a new zone, what you did last time, the time of day, a place under attack, a duel, your death. A " ..
		"row for " ..
		"each: its tick, the style it uses and where it shows; click it for its settings. How they look: the " ..
		"Style tab. One card at a time: a more important one cuts in, a less important one waits for it."])
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["On: each card shows as its row says. Off: none of them do, and each row keeps its tick for when you " ..
		"turn this back on."], intro)
	local stack = kit.Stack(switch, "check")
	local cardScale = stack:Add(kit.Slider(content, "cardScale", L["Card size"], 50, 200, 5, "%d%%", 100),
		"slider")
	kit.Tooltip(cardScale, L["Every card's words bigger or smaller, for a big or wide screen (a card in a " ..
		"letterbox bar goes by the bar's height instead)."])
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
				return list
			end,
			lines = {
				{ name = L["When"], build = function(drawer, At)
					local layout = { groups = event.fight and { ns.GRID_LOCATION } or { ns.GRID_COMBAT, ns.GRID_LOCATION },
						edit = true }
					At(ns.GridRow(grid, drawer, 0, layout, {
						band = 1,
						always = { isOn = function() return ns.GetDB()[alwaysKey] and true or false end, set = SetAlways,
							tip = L["Shows wherever you are. (The other columns then have nothing to add.)"] },
						menus = parts.menus,
						rule = { key = Key, label = function() return L[event.name] end, grid = parts.grid,
							words = parts.words, apply = parts.apply },
					}))
				end },
				{ name = L["Style"], build = function(drawer, At)
					local base = kit.Dropdown(drawer, BaseField(id), function() return StyleChoices(id) end, 170)
					if base then
						At(base)
						kit.Tooltip(base, L["The style this card starts from. Settings you give it on the Style tab go " ..
							"over it."])
					end
					-- (Buttons to it on the Settings, Style and Sounds tabs.)
					for n, link in ipairs({ { L["Settings"], "Card Settings",
						L["Opens the Settings tab with this event picked."] },
						{ L["Style"], "Card Style", L["Opens the Style tab with this event picked."] },
						{ L["Sounds"], "Card Sounds", L["Opens the Sounds tab with this event picked."] } }) do
						local button = ns.PanelButton(drawer)
						button:SetSize(70, 22)
						button:SetText(link[1])
						At(button, ns.ROW_LIST_LABEL_W + 180 + (n - 1) * 76)
						kit.Tooltip(button, link[3])
						button:SetScript("OnClick", function()
							CARD.now = id
							ns.ShowHubPage(link[2])
						end)
					end
					local test = ns.PanelButton(drawer)
					test:SetSize(60, 22)
					test:SetText(L["Test"])
					At(test, ns.ROW_LIST_LABEL_W + 408)
					kit.Tooltip(test, ns.CardSequences[id]
						and L["Shows each of its cards in turn, to see how they look (close the settings to see them). " ..
						"Clicking Stop ends it."]
						or L["Shows its card now, to see how it looks (close the settings to see it)."])
					test:SetScript("OnClick", function() ns.CardTest(id) end)
					TestStops(test, function() return id end)
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

-- Style: an event's look (opened from its row).
function ns.CreateCardStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	local under = CardTop(kit, content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["How this card looks. It starts from a style (a subzone's, the zone's), each setting following it until " ..
		"you change it here, then the card's own until you put it back. Change the style itself on the Card Types " ..
		"tab, for every card using it. Changes play at once in the preview."], under)
	local preview
	local function Changed()
		if preview then preview:Refresh() end
	end
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["On: each card shows as the Events tab says, looking as its Style page says. Off: none of them do. " ..
		"Each setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")

	-- The look's rows edit the picked event's own settings (showing what
	-- shows: its own, else what it follows; a change makes it its own).
	local isField = {}
	for _, field in ipairs(ns.CARD_FIELDS) do isField[field[1]] = true end
	local fields = {}
	local function FieldOf(key)
		local name = type(key) == "string" and key:match("^card(%u%w*)$")
		if not (name and isField[name]) then return key end
		fields[name] = fields[name] or {
			get = function() return ns.CardRaw(CARD.now, name) end,
			set = function(value) ns.GetDB()[ns.CardKey(name, CARD.now)] = value end,
		}
		return fields[name]
	end
	for _, field in ipairs(ns.CARD_FIELDS) do
		kit.RecordKey(content, ns.CardKey(field[1]))
		for _, event in ipairs(ns.CARD_EVENTS) do kit.RecordKey(content, ns.CardKey(field[1], event.id)) end
	end
	for _, event in ipairs(ns.CARD_EVENTS) do kit.RecordKey(content, "cardBase_" .. event.id) end
	local rows = ns.StyleRows(kit, content, stack, Changed, "cards", FieldOf)

	preview = ns.MakeCardPreview(content, 480, nil, function() return CARD.now end)
	preview.pageSwitch = false
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)
	local styleTest = ns.StylePreviewTest(preview, kit, L["Plays the card in the preview and on your screen, as it " ..
		"will look, with its sound (close the settings to see it there). A card with moments (Duel) plays each in " ..
		"turn; clicking Stop ends it."], function()
			preview:Refresh()
			ns.CardTest(CARD.now)
		end)
	TestStops(styleTest, function() return CARD.now end)

	-- The style the event starts from, and a button to change that style
	-- itself (the Card Types tab, it picked).
	local base = rows.Dropdown(L["Starts from:"], { get = function() return ns.GetDB()["cardBase_" .. CARD.now] end,
		set = function(value) ns.GetDB()["cardBase_" .. CARD.now] = value end },
		function() return StyleChoices(CARD.now) end,
		L["The style this card starts from. The settings below that you change go over it, as its own."])
	if base then
		local edit = ns.PanelButton(content)
		edit:SetSize(110, 22)
		edit:SetText(L["Edit style"])
		edit:SetPoint("LEFT", base, "RIGHT", 10, 0)
		edit.pageSwitch = false
		kit.Tooltip(edit, L["Opens this style on the Card Types tab: a change there is for every card using it."])
		edit:SetScript("OnClick", function()
			CARD.style = ns.CardBase(CARD.now)
			ns.ShowHubPage("Card Styles")
		end)
	end

	-- Which settings it has of its own, and a dropdown to put one back.
	local own = kit.Label(content, "GameFontHighlightSmall", "")
	own:SetWidth(NOTE_W)
	own:SetJustifyH("LEFT")
	stack:Add(own, "label")
	own.Refresh = function(self)
		local names = OwnNames(CARD.now)
		if #names == 0 then
			self:SetText(L["None of its own: it's all %s."]:format(BaseName(CARD.now)))
		else
			self:SetText(L["Its own: %s. The rest: %s."]:format(table.concat(names, ", "), BaseName(CARD.now)))
		end
	end
	kit.AddControl(own)
	local back = rows.Dropdown(L["Back to its style:"], { get = function() return nil end, set = function(index)
		if index == "all" then
			for _, group in ipairs(GROUPS) do Follow(CARD.now, group) end
		elseif GROUPS[index] then
			Follow(CARD.now, GROUPS[index])
		end
	end }, function()
		local list = {}
		for i, group in ipairs(GROUPS) do
			if OwnGroup(CARD.now, group) then list[#list + 1] = { value = i, text = L[group[1]] } end
		end
		if #list > 1 then list[#list + 1] = { value = "all", text = L["All of them"] } end
		return list
	end, L["Puts one of the event's own settings back, to come from the style it starts from again."], function(db)
		return #OwnNames(CARD.now) > 0 and rows.On(db)
	end)
	if back and back.SetDefaultText then back:SetDefaultText(L["Pick a setting"]) end

	-- The icon's own picture: a button after the Icon tick opening every icon
	-- the game has (IconBrowser.lua). Right-click: back to the event's own.
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
		button.Refresh = function()
			icon:SetTexture(ns.CardLook(CARD.now).combatIconIn)
		end
		kit.GreyUnless(button, function(db) return rows.On(db) and ns.CardRaw(CARD.now, "IconShow") end)
		kit.AddControl(button)
	end
	LookRows(content, stack, rows, IconButton)


	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content)) -- (its refresh plays the preview)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card Style", L["Card Vision"])
end

-- Card Types: a style picked from a dropdown and its look, for every card that
-- starts from it (each card's own settings over it).
function ns.CreateCardStylesPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	CardTabs(content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["The styles the cards start from. Change one here and every card that starts from it changes too, " ..
		"except where a card has a setting of its own (its Style page, from its row on the Events tab). Changes " ..
		"play at once in the preview."])
	local preview
	local function Changed()
		if preview then preview:Refresh() end
	end
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["On: each card shows as the Events tab says, in its style. Off: none of them do. Each setting keeps " ..
		"its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")

	-- The look's rows edit the picked style (showing what shows: your change,
	-- else how it comes; a change is yours).
	local isField = {}
	for _, field in ipairs(ns.CARD_FIELDS) do isField[field[1]] = true end
	local fields = {}
	local function FieldOf(key)
		local name = type(key) == "string" and key:match("^card(%u%w*)$")
		if not (name and isField[name]) then return key end
		fields[name] = fields[name] or {
			get = function() return ns.CardStyleRaw(CARD.style, name) end,
			set = function(value) ns.GetDB()[ns.CardStyleKey(name, CARD.style)] = value end,
		}
		return fields[name]
	end
	for _, field in ipairs(ns.CARD_FIELDS) do
		for _, style in ipairs(ns.CARD_STYLES) do kit.RecordKey(content, ns.CardStyleKey(field[1], style.id)) end
	end
	local rows = ns.StyleRows(kit, content, stack, Changed, "cards", FieldOf)

	-- The settings changed from how the style comes, by the list's names.
	local function Changes(style)
		local names = {}
		for _, group in ipairs(GROUPS) do
			for _, field in ipairs(group[2]) do
				if ns.CardStyleIsOwn(style, field) then
					names[#names + 1] = L[group[1]]
					break
				end
			end
		end
		return names
	end
	-- The card it plays: the first one using it, else the zone's.
	local function Sample()
		local users = ns.CardStyleUsers(CARD.style)
		return users[1] and users[1].id or "zone"
	end

	-- What it shows: "Editing", the dropdown and a line saying which cards
	-- use it.
	local bar = CreateFrame("Frame", nil, content)
	bar:SetSize(480, 30)
	stack:Add(bar, "label")
	local editing = kit.Label(bar, "GameFontNormalLarge", L["Editing"])
	editing:SetPoint("LEFT", 2, 0)
	local barLine = kit.Label(bar, "GameFontHighlightSmall", "")
	barLine:SetWidth(320)
	barLine:SetJustifyH("LEFT")
	barLine:SetWordWrap(false)
	local picker = kit.Dropdown(content, { get = function() return CARD.style end,
		set = function(id) CARD.style = id end }, function()
			local list = {}
			for _, style in ipairs(ns.CARD_STYLES) do list[#list + 1] = { value = style.id, text = L[style.name] } end
			return list
		end, 200, function() kit.Refresh() end)
	if picker then
		picker:SetPoint("LEFT", editing, "RIGHT", 12, 0)
		picker:SetFrameLevel(bar:GetFrameLevel() + 3)
		picker.pageSwitch = false
		kit.Tooltip(picker, L["The style this tab shows and sets."])
		barLine:SetPoint("LEFT", picker, "RIGHT", 12, 0)
	else
		barLine:SetPoint("LEFT", editing, "RIGHT", 12, 0)
	end
	bar.pageSwitch = false
	bar.Refresh = function()
		local names = {}
		for _, event in ipairs(ns.CardStyleUsers(CARD.style)) do names[#names + 1] = L[event.name] end
		barLine:SetText(#names > 0 and L["Used by: %s"]:format("|cffffd100" .. table.concat(names, ", ") .. "|r")
			or L["No card uses it yet."])
	end
	kit.AddControl(bar)

	preview = ns.MakeCardPreview(content, 480, nil, Sample, function() return ns.CardStyleLook(CARD.style, Sample()) end)
	preview.pageSwitch = false
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)
	ns.StylePreviewTest(preview, kit, L["Plays a card in this style in the preview and on your screen (close the " ..
		"settings to see it there): the first card using it, else the zone you're in."], function()
			preview:Refresh()
			local id = Sample()
			local card = ns.CardSample(id)
			if id == "zone" and not card.name then card.name = GetRealZoneText and GetRealZoneText() or "Darkshore" end
			card.look = ns.CardStyleLook(CARD.style, id)
			ns.Cards.Fire(id, card, true)
		end)

	-- What's changed from how it comes, and a dropdown to put one back.
	local own = kit.Label(content, "GameFontHighlightSmall", "")
	own:SetWidth(NOTE_W)
	own:SetJustifyH("LEFT")
	stack:Add(own, "label")
	own.Refresh = function(self)
		local names = Changes(CARD.style)
		self:SetText(#names == 0 and L["As it comes: nothing changed."]
			or L["Changed: %s."]:format(table.concat(names, ", ")))
	end
	kit.AddControl(own)
	local back = rows.Dropdown(L["Back as it comes:"], { get = function() return nil end, set = function(index)
		local db = ns.GetDB()
		for i, group in ipairs(GROUPS) do
			if index == "all" or index == i then
				for _, field in ipairs(group[2]) do db[ns.CardStyleKey(field, CARD.style)] = "default" end
			end
		end
	end }, function()
		local list = {}
		for i, group in ipairs(GROUPS) do
			for _, field in ipairs(group[2]) do
				if ns.CardStyleIsOwn(CARD.style, field) then
					list[#list + 1] = { value = i, text = L[group[1]] }
					break
				end
			end
		end
		if #list > 1 then list[#list + 1] = { value = "all", text = L["All of them"] } end
		return list
	end, L["Puts one of your changes to the style back, as it comes."], function(db)
		return #Changes(CARD.style) > 0 and rows.On(db)
	end)
	if back and back.SetDefaultText then back:SetDefaultText(L["Pick a setting"]) end

	LookRows(content, stack, rows)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content)) -- (its refresh plays the preview)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card Styles", L["Card Vision"])
end

-- Settings: what's an event's alone (opened from its row): when it fires,
-- its lines, its words.
function ns.CreateCardSettingsPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	local under = CardTop(kit, content, title, 1)
	local intro = kit.PageIntro(content, title,
		L["What's this card's alone: when it shows, the lines with its name, its words. How it looks: the Style " ..
		"tab."], under)
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["On: each card shows as the Events tab says, as this tab sets it. Off: none of them do. Each setting " ..
		"keeps its value for when you turn this back on."], intro)
	local stack = kit.Stack(switch, "check")
	local function Now() return CARD.now end

	-- What's each event's alone.
	local parts = Parts(kit, content, stack, Now)
	local function Check(key, label, tip, test)
		local check = stack:Add(kit.Check(content, key, label, tip), "check")
		if test then kit.GreyUnless(check, test) end
		return check
	end
	local function Header(text) stack:Header(content, text) end
	-- In a fight (or just out of one): shown now, held till after, or not at
	-- all. (Not for the fight's own cards.)
	local function FightRow(id)
		if not (ns.CARD_BY_ID[id] and ns.CARD_BY_ID[id].inFight) then return end
		Header(L["In a fight"])
		local choice = kit.Dropdown(content, "cardFight_" .. id, List({
			{ "show", L["Show it now"] },
			{ "wait", L["Wait till after"], L["Held till you've been out of the fight 5 seconds (back in it, longer: a " ..
				"feign death or vanish doesn't let it through), then shown. Dropped after 5 minutes."] },
			{ "skip", L["Skip it"], L["Not shown at all in a fight, or in the 5 seconds after one."] },
		}), 200)
		if choice then
			local name = stack:Add(kit.Label(content, "GameFontHighlight", L["In a fight:"]), "label")
			name:SetSize(150, 30)
			name:SetJustifyV("MIDDLE")
			choice:SetPoint("LEFT", name, "RIGHT", 4, 0)
			kit.Tooltip(choice, L["What this card does if it comes while you're in a fight, or in the 5 seconds " ..
				"after one."])
		end
	end
	parts.Part("combatIn", function()
		Header(L["Words"])
		WordsRow(kit, content, stack, "combatTextIn", L["Words:"],
			L["The words going into a fight. Empty: none, just the rest of the card."])
	end)
	parts.Part("combatOut", function()
		Header(L["Words"])
		WordsRow(kit, content, stack, "combatTextOut", L["Words:"],
			L["The words coming out of a fight. Empty: none, just the rest of the card."])
		Header(L["When"])
		local minFight = stack:Add(kit.Slider(content, "combatMinFight", L["Not after fights under"], 0, 10, 1,
			"%d s"), "slider")
		kit.Tooltip(minFight, L["No card coming out of a fight shorter than this, so a stray hit doesn't bring it " ..
			"up. 0: after every fight."])
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
	end)
	parts.Part("zone", function()
		Header(L["Lines"])
		Check("storyZoneTerritory", L["Territory"], L["Under the name, what the game says of the place: " ..
			"Contested Territory, Sanctuary, Alliance or Horde Territory..."])
		Check("timeOfDayMessage", L["Time of day at login"], L["Dawn, Morning, Midday, Afternoon, Evening, Dusk or " ..
			"Night as you log in or reload: over the name on this card, or under the game's zone name with Zone " ..
			"unticked. Follows the clock picked on the Tint page."])
		Header(L["When"])
		local gap = stack:Add(kit.Slider(content, "storyZoneGap", L["Not again within"], 0, 30, 1, "%d s"), "slider")
		kit.Tooltip(gap, L["After a Zone or Subzone card, no other comes for this long, so passing through " ..
			"places quickly doesn't bring one after another. 0: every time."])
		FightRow("zone")
	end)
	parts.Part("subzone", function()
		stack:Note(content, L["Only with Zone ticked: it takes the game's zone text away. Its look follows Zone's " ..
			"until it's given its own here; its lines are Zone's."], NOTE_W)
		FightRow("subzone")
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
		}) do
			Check(pair[1], pair[2], pair[3])
		end
		stack:Note(content, L["It shows only if something happened that's ticked here: quests, a level, bosses, " ..
			"deaths or gold. The zone and time played come with it."], NOTE_W)
		FightRow("login")
	end)
	parts.Part("attack", function()
		stack:Note(content, L["The same place shows at most once every 90 seconds."], NOTE_W)
	end)
	-- A dropdown on a row of its own, its label before it.
	local function PickRow(key, label, items, tip)
		local box = kit.Dropdown(content, key, List(items), 200)
		if not box then return end
		local name = stack:Add(kit.Label(content, "GameFontHighlight", label), "label")
		name:SetSize(150, 30)
		name:SetJustifyV("MIDDLE")
		box:SetPoint("LEFT", name, "RIGHT", 4, 0)
		kit.Tooltip(box, tip)
	end
	-- A win's (and loss's) card as it was or as a souls banner (Cards.lua's
	-- ns.SoulsCard).
	local function SoulsRow(id, tip)
		Header(L["Banner"])
		PickRow("cardSouls_" .. id, L["Shows as:"], {
			{ "usual", L["Its card"], L["As it always has, in its own look (the Style tab)."] },
			{ "souls", L["Souls banner"], L["Big words across the middle of the screen on a dark band, as YOU DIED " ..
				"shows: a win in gold, a loss in red (the Victory and Death styles' looks)."] },
		}, tip)
	end
	-- Boss defeated's, Rare felled's and Revived's words (SOULS_WORDS, or your
	-- own).
	local function SoulsWordsRows(id)
		Header(L["Words"])
		local items = {}
		for _, entry in ipairs(ns.SOULS_WORDS[id]) do
			items[#items + 1] = { entry[1], L[entry[2]]:format(L["<NAME>"]) }
		end
		items[#items + 1] = { "custom", L["Custom"], L["Your own words."] }
		PickRow(id .. "Words", L["Banner words:"], items,
			L["The big words across the screen. <NAME>: the name of the one that fell."])
		local box = WordsRow(kit, content, stack, id .. "Text", L["Your words:"],
			L["The words the banner shows with Custom picked. Left blank: the first ones in the list."])
		kit.GreyUnless(box, function(db) return db[id .. "Words"] == "custom" end)
	end
	-- (The wins that can show as a souls banner, and their Banner's tooltip.)
	local SOULS_TIPS = {
		cleared = "How the dungeon's end shows: its card, or a souls banner: its name and CONQUERED across the " ..
			"middle of the screen, the time and deaths under it.",
		battleground = "How the result shows: its card in the top bar, or a souls banner: VICTORY ACHIEVED or " ..
			"DEFEATED across the middle of the screen (where the game's scoreboard may cover it).",
		streak = "How it shows: its card, or a souls banner: PREY SLAUGHTERED across the middle of the screen, " ..
			"the count and who under it.",
	}
	parts.Part("duel", function()
		Header(L["When"])
		Check("cardDuelAsk", L["You challenge"], L["The other player's name as you challenge them to a duel."])
		Check("cardDuelAsked", L["You're challenged"], L["The other player's name as they challenge you to a duel."])
		Check("cardDuelStart", L["Duel starts"], L["Both names as the duel is accepted and its countdown starts."])
		Check("cardDuelResult", L["Result"], L["Whether you won or lost (or someone fled) as the duel ends."])
		Header(L["Words"])
		local start = WordsRow(kit, content, stack, "duelTextStart", L["Starts:"],
			L["The words under both names as the duel starts. Empty: none."])
		kit.GreyUnless(start, function(db) return db.cardDuelStart end)
		for _, row in ipairs({ { "duelTextWon", L["Won:"], L["The big words as you win a duel."] },
			{ "duelTextLost", L["Lost:"], L["The big words as you lose a duel."] } }) do
			local box = WordsRow(kit, content, stack, row[1], row[2], row[3])
			kit.GreyUnless(box, function(db) return db.cardDuelResult end)
		end
		SoulsRow("duel", L["How the result shows: its card (with the words above), or a souls banner: VICTORY " ..
			"ACHIEVED or DEFEATED across the middle of the screen, who it was against under it."])
	end)
	for _, id in ipairs({ "bossDown", "felled", "revived" }) do
		parts.Part(id, function()
			SoulsWordsRows(id)
			if ns.CARD_BY_ID[id].inFight then FightRow(id) end
			stack:Note(content, L["Its look is the Victory style's (the Style tab), its sound on the Sounds tab."],
				NOTE_W)
		end)
	end
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
	parts.Part("time", function()
		FightRow("time")
		stack:Note(content, L["Its look is on the Style tab, a sound for each time of day on the Sounds tab."], NOTE_W)
	end)
	for _, id in ipairs({ "cleared", "discover", "arrival", "rested", "levelUp", "achievement", "reputation", "collect",
		"profession", "quest", "rare", "battleground", "streak" }) do
		parts.Part(id, function()
			if SOULS_TIPS[id] then SoulsRow(id, L[SOULS_TIPS[id]]) end
			if ns.CARD_BY_ID[id] and ns.CARD_BY_ID[id].inFight then
				FightRow(id)
				stack:Note(content, L["Its look is on the Style tab, its sound on the Sounds tab."], NOTE_W)
			else
				stack:Note(content, L["Nothing of its own here: its look is on the Style tab, its sound on the Sounds " ..
					"tab."], NOTE_W)
			end
		end)
	end
	parts.Finish()

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card Settings", L["Card Vision"])
end

-- Sounds: an event's sounds (opened from its row).
function ns.CreateCardSoundsPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Card Vision"])
	local under = CardTop(kit, content, title, 3)
	local intro = kit.PageIntro(content, title, L["What this card plays as it shows."], under)
	local switch = kit.PageSwitch(content, "cards", L["Enable Page"],
		L["On: each card shows as the Events tab says, with its sounds. Off: none of them do. Each setting keeps " ..
		"its value for when you turn this back on."], intro)
	local stack = kit.Stack(switch, "check")

	-- (Each event's sound rules: CombatSoundRules.lua. Entering and Leaving
	-- combat's one list, shown on both; Boss's its own; Time of day's a rule for each time; the rest's
	-- own, read as the card shows.)
	local parts = Parts(kit, content, stack, function() return CARD.now end)
	parts.Part("combatIn", function() ns.CombatSoundRulesSection(kit, content, stack) end)
	parts.Part("combatOut", function() ns.CombatSoundRulesSection(kit, content, stack) end)
	parts.Part("boss", function() ns.CombatSoundRulesSection(kit, content, stack, true) end)
	parts.Part("time", function() ns.CombatSoundRulesSection(kit, content, stack, "time") end)
	for _, id in ipairs(ns.CARD_SOUND_LISTS) do
		parts.Part(id, function() ns.CombatSoundRulesSection(kit, content, stack, id) end)
	end
	parts.Finish()

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Card Sounds", L["Card Vision"])
end
