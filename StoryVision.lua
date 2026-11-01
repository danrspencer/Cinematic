-- Story Vision: words that fade in on the screen at moments in your session
-- that aren't your own fights (those are Battle Vision's): what you did last
-- time, the time of day, a place under attack, your death. Each moment's code stays where it was
-- (Tint.lua draws the titles and the death banner, Chat.lua hears the
-- attacks, Recap.lua keeps the last session's counts); this page gathers their switches, so you can find what shows on
-- your screen and turn it off in one place. Its rows are under storyVision
-- (Core.lua's PAGE_SWITCH), itself under Enable Visions.

local _, ns = ...
local L = ns.L
local DEFAULTS = ns.DEFAULTS

DEFAULTS.storyVision = true      -- the page's switch (off in Subtle: the no-visions module)
DEFAULTS.timeOfDayChange = true  -- the time of day's name and sound as it changes during play
DEFAULTS.storyFont = "general"   -- its words' font (ns.QUEST_ITEM_FONTS' names; general: Style General's)
DEFAULTS.storyOutline = -1       -- ...outline: 0 none, 1 thin, 2 thick (-1: General's, else the game's)
DEFAULTS.storyOutlineR, DEFAULTS.storyOutlineG, DEFAULTS.storyOutlineB = 0, 0, 0 -- ...its color (black: the game's)
DEFAULTS.storyShadow = "general" -- ...shadow: "game", "on" or "none" (ns.SetTextShadow; general: General's)
-- Each moment's color and how long it stays (seconds between fading in and
-- out), the Style tab's (Tint.lua reads them, through ns.StyleLook).
DEFAULTS.storyTimeR, DEFAULTS.storyTimeG, DEFAULTS.storyTimeB = 1, 0.86, 0.6 -- the time of day as it changes
DEFAULTS.storyTimeHold = 4
DEFAULTS.storyAttackR, DEFAULTS.storyAttackG, DEFAULTS.storyAttackB = 1, 0.3, 0.2 -- a place under attack
DEFAULTS.storyAttackHold = 4
DEFAULTS.storyBannerR, DEFAULTS.storyBannerG, DEFAULTS.storyBannerB = 0.72, 0.11, 0.14 -- YOU DIED ("wasted": a picture)
DEFAULTS.storyBannerHold = 4 -- ("wasted" a second longer)
-- (Its other rows' settings are older than the page: timeOfDayMessage in
-- Core.lua, chatAttackAlert in Core.lua, deathBannerStyle in Core.lua.)

-- For the pages these settings used to be on: a line saying where they are
-- now, and a button there. A frame holding both, to anchor or stack.
function ns.StoryVisionLink(content, text)
	local kit = ns.lowHealthKit
	local holder = CreateFrame("Frame", nil, content)
	holder:SetSize(420, 22)
	local label = kit.Label(holder, "GameFontHighlightSmall", text)
	label:SetPoint("LEFT", 2, 0)
	local button = ns.PanelButton(holder)
	button:SetSize(110, 22)
	button:SetText(L["Story Vision"])
	kit.Tooltip(button, L["Opens the Story Vision page."])
	button:SetScript("OnClick", function() ns.OpenOptions("Story Vision") end)
	button:SetPoint("LEFT", label, "RIGHT", 10, 0)
	return holder
end

-- A Test button at a row's right, at the same height.
local function TestButton(kit, content, row, onClick)
	local button = ns.PanelButton(content)
	button:SetSize(70, 22)
	button:SetText(L["Test"])
	kit.Tooltip(button, L["Shows it now, to see how it looks."])
	button:SetScript("OnClick", onClick)
	button:SetPoint("TOPLEFT", row, "TOPLEFT", 360, 0)
	return button
end

local NOTE_W = 440 -- (each moment's words under it, wrapped)

-- Both pages' folder tabs (Battle Vision's look: ns.VisionFolderTabs), a
-- moment each, the one picked kept for both; the time of day's two rows share
-- one. (Its names as the pages are made: the language is applied after this
-- file loads.)
local TABS = { now = "recap" }
local function TabList()
	TABS[1] = { "recap", L["Last time"], L["What you did last time you played, as you log in."] }
	TABS[2] = { "time", L["Time of day"], L["The time of day's name, at login and as it changes."] }
	TABS[3] = { "attack", L["Under attack"], L["A place under attack, from the LocalDefense channel."] }
	TABS[4] = { "death", L["Death banner"], L["Words across the screen as you die."] }
	return TABS
end

-- Each tab's Test: its moment on your screen now.
local TESTS = {
	recap = function()
		local line, sample = ns.RecapDemo()
		ns.Print(sample and L["Last time: nothing to say yet this session (no quests, level or bosses), " ..
			"so this is a sample."] or line)
	end,
	time = function() ns.TestTimeChangeTitle() end,
	attack = function()
		local place = GetMinimapZoneText and GetMinimapZoneText() or ""
		ns.ShowAlertTitle(L["%s is under attack!"]:format(place ~= "" and place or GetRealZoneText()))
	end,
	death = function() ns.TestDeathBanner() end,
}

-- The preview: the screen's shape, the scene behind, the picked tab's moment
-- played on it as the game shows it, to scale (no words under 8 pixels, to
-- read). Its parts as Tint.lua draws them: the zone name's place and fonts,
-- the death banner's band (ns.DEATH_BANNER_LOOK), Story Vision's look.
local ZONE_GOLD = { 1, 0.82, 0 } -- (the zone name's: the game's own is read only as it shows)
local RECAP_GREY = { 0.7, 0.67, 0.61 } -- (the Last time line's, as Tint.lua's)
local FADE_IN, FADE_OUT = 0.6, 0.8
local function MakePreview(parent, width)
	local preview = CreateFrame("Frame", nil, parent)
	preview:SetSize(width, 270)
	if preview.SetClipsChildren then preview:SetClipsChildren(true) end
	local stage = CreateFrame("Frame", nil, preview)
	stage:SetAllPoints()
	stage:SetFrameLevel(preview:GetFrameLevel() + 2)
	local caption = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetText(L["Preview"])
	caption:SetPoint("TOPLEFT", 6, -5)
	caption.searchSkip = true
	-- The death banner: a band with soft edges (YOU DIED), or flat with the
	-- "wasted" picture on it.
	local function Band()
		local band = stage:CreateTexture(nil, "BACKGROUND")
		band:SetColorTexture(1, 1, 1, 1)
		band:SetPoint("LEFT")
		band:SetPoint("RIGHT")
		return band
	end
	local middle, above, below, flat = Band(), Band(), Band(), Band()
	middle:SetPoint("CENTER")
	above:SetPoint("BOTTOM", middle, "TOP")
	below:SetPoint("TOP", middle, "BOTTOM")
	flat:SetPoint("CENTER")
	local picture = stage:CreateTexture(nil, "ARTWORK")
	picture:SetPoint("CENTER")
	local bandParts = { middle, above, below, flat, picture }
	-- Up to three lines, each under the one before: the zone name, a title,
	-- the Last time line.
	local lines = {}
	for i = 1, 3 do
		local line = stage:CreateFontString(nil, "OVERLAY")
		line:SetFontObject("GameFontNormal") -- (a font before any text)
		lines[i] = line
	end
	local function Words(line, object, size, value, color, alpha)
		local _, _, flags = object:GetFont()
		size = math.max(8, math.floor(size + 0.5))
		if not (ns.StoryFont and ns.StoryFont(line, object, size, flags)) then
			local file = object:GetFont()
			if file and ns.SetPlateNameFont then ns.SetPlateNameFont(line, object, file, size, 1, flags or "") end
			line:SetShadowOffset(1, -1)
			line:SetShadowColor(0, 0, 0, 1)
		end
		line:SetTextColor(color[1], color[2], color[3], alpha or 1)
		line:SetVertexColor(color[1], color[2], color[3], alpha or 1) -- (one on Forever)
		line:SetText(value)
		line:Show()
	end
	-- The zone name's middle, down from the top: where the game has it (it
	-- keeps its place while hidden), else 200 down.
	local function ZoneDown(height)
		local screenH = math.max(UIParent:GetHeight(), 1)
		local ok, down = pcall(function()
			local _, y = ZoneTextString:GetCenter()
			return UIParent:GetTop() - y * ZoneTextString:GetEffectiveScale() / UIParent:GetEffectiveScale()
		end)
		if not (ok and type(down) == "number" and down > 0 and down < screenH) then down = 200 end
		return down / screenH * height
	end
	-- Plays steps, one after another: each { draw = function(), hold = seconds }.
	local steps, step, t
	stage:SetScript("OnUpdate", function(self, elapsed)
		if not steps then return end
		t = t + elapsed
		local hold = tonumber(steps[step].hold) or 3
		if t >= FADE_IN + hold + FADE_OUT then
			step, t = step + 1, 0
			if not steps[step] then
				steps = nil
				self:SetAlpha(0)
				return
			end
			steps[step].draw()
			hold = tonumber(steps[step].hold) or 3
		end
		self:SetAlpha(math.max(0, math.min(1, t / FADE_IN, (FADE_IN + hold + FADE_OUT - t) / FADE_OUT)))
	end)
	local function Play(list)
		steps, step, t = list, 1, 0
		stage:SetAlpha(0)
		list[1].draw()
	end
	-- Last time's card, over the scene (ns.PlayVisionCard draws it); cards:
	-- one waiting for its delay is dropped if the preview plays again.
	local cardHost = CreateFrame("Frame", nil, preview)
	cardHost:SetAllPoints()
	cardHost:SetFrameLevel(stage:GetFrameLevel() + 1)
	cardHost:Hide()
	local cards = 0

	function preview:Refresh()
		if not self:IsVisible() then
			return -- (the kit refreshes every page's controls)
		end
		if ns.FitStylePreview(self) then return end -- (resized: it played from there)
		local screenH = math.max(UIParent:GetHeight(), 1)
		local height = math.floor(width * screenH / math.max(UIParent:GetWidth(), 1) + 0.5)
		self:SetHeight(height)
		ns.StyleScene(self)
		local scale = height / screenH
		local look = ns.StyleLook("storyVision")
		local zoneFont = _G.ZoneTextFont or GameFontNormalHuge
		local subFont = _G.SubZoneTextFont or GameFontNormalLarge
		local _, zoneSize = zoneFont:GetFont()
		local _, subSize = subFont:GetFont()
		zoneSize, subSize = (zoneSize or 32) * scale, (subSize or 26) * scale
		local zone = GetRealZoneText and GetRealZoneText() or ""
		if zone == "" then zone = "Darkshore" end
		local gap = math.max(2, 6 * scale)
		-- (Each step starts clear: no lines, no band.)
		local function Clear()
			for _, line in ipairs(lines) do line:Hide() end
			for _, part in ipairs(bandParts) do part:Hide() end
			lines[1]:ClearAllPoints()
			lines[1]:SetPoint("CENTER", stage, "TOP", 0, -ZoneDown(height))
			for i = 2, #lines do
				lines[i]:ClearAllPoints()
				lines[i]:SetPoint("TOP", lines[i - 1], "BOTTOM", 0, -gap)
			end
		end
		local function TimeTitle()
			return ns.TimeTitleNow and ns.TimeTitleNow() or L["Dusk"]
		end
		local function Color(prefix) return { look[prefix .. "R"], look[prefix .. "G"], look[prefix .. "B"] } end
		local kind = TABS.now
		cardHost:Hide()
		cards = cards + 1
		if kind == "recap" then
			local parts = ns.RecapPartsNow()
			local card = look.storyRecapPlace ~= "zone" and ns.RecapCardText(parts, look)
			local line = not card and (ns.RecapLineFor(parts) or L["Last time: %s"]:format(zone))
			Play({ { hold = 3, draw = function()
				Clear()
				Words(lines[1], zoneFont, zoneSize, zone, ZONE_GOLD)
				local under = lines[2]
				if ns.Setting("timeOfDayMessage") then
					Words(lines[2], subFont, subSize * 0.75, TimeTitle(), ZONE_GOLD)
					under = lines[3]
				end
				if line then Words(under, subFont, subSize * 0.5, line, RECAP_GREY) end
			end } })
			-- On a card of its own: a moment after the zone name, as Battle
			-- Vision's boss card draws it (Recap.lua's look for it).
			if card then
				local this = cards
				C_Timer.After(tonumber(look.storyRecapDelay) or 0, function()
					if this ~= cards or not self:IsVisible() then return end
					cardHost:Show()
					ns.PlayVisionCard(cardHost, ns.RecapCardLook(), self:GetWidth(), height, scale, card)
				end)
			end
		elseif kind == "time" then
			-- (At login under the zone name, then as it changes on its own.)
			Play({
				{ hold = 2, draw = function()
					Clear()
					Words(lines[1], zoneFont, zoneSize, zone, ZONE_GOLD)
					Words(lines[2], subFont, subSize * 0.75, TimeTitle(), ZONE_GOLD)
				end },
				{ hold = look.storyTimeHold, draw = function()
					Clear()
					Words(lines[1], zoneFont, zoneSize, TimeTitle(), Color("storyTime"))
				end },
			})
		elseif kind == "attack" then
			Play({ { hold = look.storyAttackHold, draw = function()
				Clear()
				Words(lines[1], zoneFont, zoneSize, L["%s is under attack!"]:format(zone), Color("storyAttack"))
			end } })
		else
			local shape = ns.DEATH_BANNER_LOOK
			local wasted = ns.GetDB().deathBannerStyle == "wasted"
			Play({ { hold = (tonumber(look.storyBannerHold) or 4) + (wasted and 1 or 0), draw = function()
				Clear()
				if not shape then return end
				if wasted then
					flat:SetColorTexture(0, 0, 0, shape.wastedAlpha)
					flat:SetHeight(height * shape.wastedHeight)
					picture:SetTexture(shape.wastedTexture)
					picture:SetSize(height * shape.wastedSize * 4, height * shape.wastedSize)
					flat:Show()
					picture:Show()
					return
				end
				local black, clear = { 0, 0, 0, shape.alpha }, { 0, 0, 0, 0 }
				middle:SetHeight(height * shape.height)
				above:SetHeight(height * shape.edge)
				below:SetHeight(height * shape.edge)
				shape.gradient(middle, "VERTICAL", black, black)
				shape.gradient(above, "VERTICAL", black, clear)
				shape.gradient(below, "VERTICAL", clear, black)
				middle:Show()
				above:Show()
				below:Show()
				local _, size = GameFontNormalHuge:GetFont()
				lines[1]:ClearAllPoints()
				lines[1]:SetPoint("CENTER", middle)
				Words(lines[1], GameFontNormalHuge, (size or 20) * shape.scale * scale, L["YOU DIED"],
					Color("storyBanner"), shape.textAlpha)
			end } })
		end
	end
	return preview
end

-- The pages' tabs: Vision (turning each moment on) and Style (how the words
-- look), both in the Visions hub under one icon.
local function StoryTabs(content, title, picked)
	ns.VisionTabs(content, title, "Story Vision", "Story Style", picked,
		L["Turning each moment on, and testing it."], L["How the words look, with a preview."])
end

-- The Vision tab: each moment's switch.
function ns.CreateStoryVisionPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Story Vision"])
	StoryTabs(content, title, 1)
	local intro = kit.PageIntro(content, title,
		L["Words that fade in on the screen at moments in your session that aren't your own fights: what " ..
		"you did last time, the time of day, a place under attack, your death. (Fights and bosses: Battle " ..
		"Vision.)"])
	local switch = kit.PageSwitch(content, "storyVision", L["Enable Page"],
		L["On: each moment below shows as ticked. Off: none of them do, and each keeps its tick for when you " ..
		"turn this back on."], intro)
	local stack = kit.Stack(switch, "check", true) -- (inline: the death banner's name beside its dropdown)
	local parts = ns.VisionFolderTabs(kit, content, stack, TabList())
	-- A moment's row with its words under it (its tooltip too).
	local function Moment(key, name, text)
		local row = stack:Add(kit.Check(content, key, name, text), "check")
		stack:Note(content, text, NOTE_W)
		return row
	end

	parts.Part("recap", function()
		local recap = Moment("storyRecap", L["Last time"],
			L["On a real login (not a reload), a line under the zone name saying what you did last time you " ..
			"played: where you spent the most time, quests done, a level reached and bosses killed, such as " ..
			"\"Last time: Darkshore · 3 quests done · reached level 24\". Only what happened, and nothing if " ..
			"nothing did; never in a fight, nor after more than two weeks away."])
		local recapTest = TestButton(kit, content, recap, TESTS.recap)
		kit.Tooltip(recapTest, L["Plays your login now: the zone name fades in with the Last time line under " ..
			"it, from this session so far (a sample if nothing counted yet). Close the settings to see it."])
	end)

	parts.Part("time", function()
		Moment("timeOfDayMessage", L["Time of day at login"],
			L["Dawn, Morning, Midday, Afternoon, Evening, Dusk or Night, under the zone name when you log in or " ..
			"reload. Follows the clock picked on the Tint page."])
		local change = Moment("timeOfDayChange", L["Time of day changes"],
			L["When the time of day changes during play (not in combat), its name fades in where the zone name " ..
			"shows, with a fitting sound: a rooster at dawn, a horse in the morning, your faction's bell at " ..
			"midday, frogs in the evening, an owl at dusk and a wolf at night."])
		TestButton(kit, content, change, TESTS.time)
	end)

	parts.Part("attack", function()
		local attack = Moment("chatAttackAlert", L["Under attack"],
			L["When the LocalDefense channel says a place is under attack (\"Dun Algaz is under attack!\"), it " ..
			"shows in red where the zone name appears, with your faction's city bell. The same place shows at " ..
			"most once every 90 seconds."])
		TestButton(kit, content, attack, TESTS.attack)
	end)

	-- Shown only with the death camera (the Die row on the Cameras page).
	parts.Part("death", function()
		local banner = kit.Dropdown(content, "deathBannerStyle", {
			{ value = "none", text = L["None"] },
			{ value = "youdied", text = L["YOU DIED"] },
			{ value = "wasted", text = L["wasted"] },
		}, 180)
		if not banner then return end
		banner.inlineName = L["Death banner"]
		stack:Add(banner, "dropdown")
		local text = L["Shortly after the death camera starts, words fade in across the middle of the " ..
			"screen on a band, then fade away after a few seconds. \"YOU DIED\": dull red on a dark band with " ..
			"soft edges. \"wasted\": red with a dark outline on a flat black band."]
		local only = L["Only with the death camera on (the Die row on the Scenes page)."]
		kit.Tooltip(banner, text .. " " .. only)
		kit.GreyUnless(banner, function() return ns.TriggerAnyRow("Death") end)
		local test = TestButton(kit, content, banner, TESTS.death)
		test:ClearAllPoints()
		test:SetPoint("LEFT", banner, "RIGHT", 10, 0)
		stack:Note(content, text, NOTE_W)
		stack:Note(content, only, NOTE_W)
	end)
	parts.Finish()

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Story Vision")
end

-- The look's settings a preset sets (the rest as the defaults).
local PRESET_KEYS = { "storyFont", "storyOutline", "storyOutlineR", "storyOutlineG", "storyOutlineB", "storyShadow",
	"storyTimeR", "storyTimeG", "storyTimeB", "storyTimeHold", "storyAttackR", "storyAttackG", "storyAttackB",
	"storyAttackHold", "storyBannerR", "storyBannerG", "storyBannerB", "storyBannerHold" }

-- The Style tab: how the words look, a preview at the top.
function ns.CreateStoryStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Story Vision"])
	StoryTabs(content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["How the words look at each moment. Which moments show: the Vision tab. Changes play at once in " ..
		"the preview."])
	local preview
	local function Changed()
		if preview then preview:Refresh() end
	end
	local switch = kit.PageSwitch(content, "storyVision", L["Enable Page"],
		L["On: each moment shows as the Vision tab says, looking as this page says. Off: none of them do. " ..
		"Each setting keeps its value for when you turn this back on."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "storyVision")
	local On = rows.On

	preview = MakePreview(content, 480)
	preview.pageSwitch = false
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)

	-- The tabs under the preview: what it plays, and the rows that follow.
	local parts = ns.VisionFolderTabs(kit, content, stack, TabList(), Changed)

	ns.StylePreviewTest(preview, kit, L["Plays the picked tab's moment in the preview and on your screen, as " ..
		"it will look (close the settings to see it there)."], function()
			preview:Refresh()
			TESTS[TABS.now]()
		end)

	-- Every moment's: a preset (the words' font, outline and shadow, and the
	-- colors and times of the moments but Last time).
	rows.PresetMenu({
		{ L["Usual"], L["General's font, the game's outline and shadow, the usual colors."], {} },
		{ L["Storybook"], L["A fairy-tale serif in warm parchment colors, a soft shadow and no outline."],
			{ storyFont = "morpheus", storyOutline = 0, storyShadow = "on", storyTimeR = 0.96, storyTimeG = 0.88,
			storyTimeB = 0.7, storyAttackR = 0.86, storyAttackG = 0.36, storyAttackB = 0.24 } },
		{ L["Film"], L["Clean lettering with a thin outline, staying a little longer."],
			{ storyFont = "friz", storyOutline = 1, storyShadow = "none", storyTimeR = 0.92, storyTimeG = 0.92,
			storyTimeB = 0.9, storyTimeHold = 5, storyAttackHold = 5, storyBannerHold = 5 } },
		{ L["Bold"], L["Rough, heavy letters with a thick outline, in strong colors."],
			{ storyFont = "skurri", storyOutline = 2, storyTimeR = 1, storyTimeG = 0.78, storyTimeB = 0.3,
			storyAttackR = 1, storyAttackG = 0.2, storyAttackB = 0.1, storyBannerR = 0.85, storyBannerG = 0.08,
			storyBannerB = 0.1 } },
	}, PRESET_KEYS)
	-- Each tab's Look box: the words' font, outline and shadow (one for every
	-- moment: changing them on one tab changes them on all), and its own color
	-- (and size: Last time's card).
	local function Look(color, size)
		rows.Look(L["Look:"], L["Words"], {
			font = { "storyFont", L["The font of every line on this page. General: the one picked on the Style hub's " ..
				"General page, so changing it there changes it here. Russian, Korean or Chinese text keeps the " ..
				"game's, so its letters show. Only with Enable Style on (Style hub, General page)."] },
			outline = { "storyOutline", L["A black border round the letters."],
				names = { [-1] = L["The game's"], [0] = L["None"], L["Thin"], L["Thick"] }, own = L["The game's"] },
			outlineColor = function(look)
				look.Color(L["Outline color"], { "storyOutlineR", "storyOutlineG", "storyOutlineB" },
					L["Pick the outline's color."], function(db)
						local value = look.Get("storyOutline")
						if value == -1 then value = ns.GeneralStyleValue("storyOutline") end
						return look.On(db) and (tonumber(value) or 0) > 0
					end)
			end,
			shadow = { "storyShadow" },
			textColor = color and function(look)
				look.Color(L["Color"], { color[1] .. "R", color[1] .. "G", color[1] .. "B" }, color[2], color[3])
			end or false,
			textSize = size or false,
		})
	end
	local function Stays(key, tip, test)
		rows.Slider(key, L["Stays"], 1, 10, 0.5, "%.1f s", 1, tip, test)
	end
	-- (Dropdowns: one choice to read at a glance.)
	local function List(choices)
		return function()
			local list = {}
			for i, choice in ipairs(choices) do list[i] = { value = choice[1], text = choice[2], tip = choice[3] } end
			return list
		end
	end
	-- Two ticks on one line: the second lined up past the first's name.
	local function Pair(first, second)
		local check = rows.Check(first[1], first[2], first[3])
		if not second then return check end
		local other = kit.Check(content, second[1], second[2], second[3], function(value)
			rows.Put(second[1], value)
			Changed()
			kit.Refresh()
		end)
		other:SetPoint("LEFT", check, "LEFT", 220, 0)
		kit.GreyUnless(other, On)
		return check
	end

	-- Last time: under the zone name, or a card of its own (Battle Vision's
	-- boss card: Recap.lua plays it).
	parts.Part("recap", function()
		local function Card(db) return On(db) and rows.Get("storyRecapPlace") ~= "zone" end
		local function InBar(db)
			local place = rows.Get("storyRecapPlace")
			return On(db) and (place == "top" or place == "bottom")
		end
		Look({ "storyRecap", L["The card's color: its zone name, the rest in a lighter shade. (Under the zone " ..
			"name it's a soft gray.)"], Card }, function(look)
				look.Boxes():Box(L["Size"], "storyRecapSize", 14, 64, 1, "%d", 1,
					L["How tall the card's zone name is on the screen (its other lines go by it). In a letterbox " ..
					"bar: the bar's height."], Card)
			end)
		stack:Header(content, L["Where"])
		rows.Dropdown(L["Place:"], "storyRecapPlace", List({
			{ "zone", L["Under the zone name"], L["One line under the game's zone name, as it comes in at login."] },
			{ "screen", L["On the screen"], L["A card in the middle of the screen."] },
			{ "top", L["Top letterbox bar"] },
			{ "bottom", L["Bottom letterbox bar"] },
			{ "third", L["Lower third"], L["Low on the left of the screen, as a film names a place, its line " ..
				"fading out to the right."] },
		}), L["Where it shows: under the zone name, or a card of its own, as Battle Vision's boss card."])
		rows.Dropdown(L["In the bar:"], "storyRecapAlign", List({
			{ "left", L["Left"] },
			{ "center", L["Center"] },
			{ "right", L["Right"] },
		}), L["Where in the letterbox bar the card sits. (With no letterbox up, the lower third.)"], InBar)
		rows.Slider("storyRecapDelay", L["After"], 0, 8, 0.5, "%.1f s", 1,
			L["How long after the zone name comes in the card does, so the two don't land at once."], Card)

		stack:Header(content, L["Card"])
		rows.Dropdown(L["Style:"], "storyRecapStyle", List({
			{ "title", L["Title card"], L["The zone name big in the middle, the rest under it."] },
			{ "subtitle", L["Subtitle"], L["A small line low on the screen, where a film's subtitles go."] },
			{ "chapter", L["Chapter line"], L["The zone name over a line that draws out, as a new chapter starts."] },
		}), L["How the card is set: a title card, a subtitle or a chapter line."], Card)
		rows.Dropdown(L["Animation:"], "storyRecapAnim", List({
			{ "fade", L["Fade"], L["The card fades in and out."] },
			{ "reveal", L["Reveal"], L["The zone name opens out from its middle (or side), the rest rising in after."] },
			{ "track", L["Tracking in"], L["The zone name's letters close up, as a film's title comes in."] },
			{ "type", L["Typewriter"], L["The zone name comes in a letter at a time, as if typed into a journal, " ..
				"the rest rising in after."] },
		}), L["How the card comes in."], Card)
		Stays("storyRecapHold", L["How long the card stays between fading in and out (Typewriter: once typed)."], Card)
		rows.Check("storyRecapBook", L["Book icon"], L["A book before the zone name, as a journal's page."], Card)

		stack:Header(content, L["Details"])
		rows.Dropdown(L["Heading:"], "storyRecapHeading", List({
			{ "lasttime", L["Last time"] },
			{ "previously", L["Previously"] },
			{ "previouslyon", L["Previously, on %s"]:format(UnitName("player") or "...") },
			{ "sofar", L["Your story so far"] },
			{ "none", L["None"] },
		}), L["The words before it all (on a card, over the zone name)."])
		Pair({ "storyRecapZone", L["Zone"], L["The zone you spent the most time in (on a card, its big name)."] },
			{ "storyRecapPlayed", L["Time played"], L["How long the session was."] })
		Pair({ "storyRecapQuests", L["Quests done"], L["How many quests you turned in."] },
			{ "storyRecapLevel", L["Level reached"], L["The level you reached, if you went up."] })
		Pair({ "storyRecapBosses", L["Bosses down"], L["How many dungeon or raid bosses you killed."] },
			{ "storyRecapDeaths", L["Deaths"], L["How many times you died."] })
		Pair({ "storyRecapGold", L["Gold earned"], L["How much richer you came out, if you did."] },
			{ "storyRecapIcons", L["Icons"], L["A little icon before each detail: a map, a watch, a quest mark, a " ..
				"skull, coins..."] })
		Pair({ "storyRecapSound", L["Page-turn sound"], L["A page turning as it shows, as a journal opens."] })
		stack:Note(content, L["It shows only if something happened that's ticked here: quests, a level, bosses, " ..
			"deaths or gold. The zone and time played come with it."], NOTE_W)
	end, "rows")
	parts.Part("time", function()
		Look({ "storyTime", L["Pick the color of the time of day's name as it changes. (At login it sits under " ..
			"the zone name, in its color.)"] })
		Stays("storyTimeHold", L["How long the time of day's name stays between fading in and out."])
	end, "rows")
	parts.Part("attack", function()
		Look({ "storyAttack", L["Pick the color of a place under attack."] })
		Stays("storyAttackHold", L["How long a place under attack stays between fading in and out."])
	end, "rows")
	parts.Part("death", function()
		Look({ "storyBanner", L["Pick the color of \"YOU DIED\". (\"wasted\" is a picture: its own red.)"],
			function(db) return On(db) and db.deathBannerStyle ~= "wasted" end })
		Stays("storyBannerHold", L["How long the banner stays between fading in and out (\"wasted\" a second longer)."])
	end, "rows")
	parts.Finish()

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content)) -- (its refresh plays the preview)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Story Style", L["Story Vision"])
end
