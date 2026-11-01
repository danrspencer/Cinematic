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

function ns.CreateStoryVisionPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Story Vision"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["Words that fade in on the screen at moments in your session that aren't your own fights: what " ..
		"you did last time, the time of day, a place under attack, your death. (Fights and bosses: Battle " ..
		"Vision.)"])
	local switch = kit.PageSwitch(content, "storyVision", L["Enable Page"],
		L["On: each moment below shows as ticked. Off: none of them do, and each keeps its tick for when you " ..
		"turn this back on."], intro)
	local stack = kit.Stack(switch, "check", true) -- (inline: the death banner's name beside its dropdown)

	local recap = stack:Add(kit.Check(content, "storyRecap", L["Last time"],
		L["On a real login (not a reload), a line under the zone name saying what you did last time you " ..
		"played: where you spent the most time, quests done, a level reached and bosses killed, such as " ..
		"\"Last time: Darkshore · 3 quests done · reached level 24\". Only what happened, and nothing if " ..
		"nothing did; never in a fight, nor after more than two weeks away."]), "check")
	local recapTest = TestButton(kit, content, recap, function()
		local line, sample = ns.RecapDemo()
		ns.Print(sample and L["Last time: nothing to say yet this session (no quests, level or bosses), " ..
			"so this is a sample."] or line)
	end)
	kit.Tooltip(recapTest, L["Plays your login now: the zone name fades in with the Last time line under " ..
		"it, from this session so far (a sample if nothing counted yet). Close the settings to see it."])

	stack:Add(kit.Check(content, "timeOfDayMessage", L["Time of day at login"],
		L["Dawn, Morning, Midday, Afternoon, Evening, Dusk or Night, under the zone name when you log in or " ..
		"reload. Follows the clock picked on the Tint page."]), "check")

	local change = stack:Add(kit.Check(content, "timeOfDayChange", L["Time of day changes"],
		L["When the time of day changes during play (not in combat), its name fades in where the zone name " ..
		"shows, with a fitting sound: a rooster at dawn, a horse in the morning, your faction's bell at " ..
		"midday, frogs in the evening, an owl at dusk and a wolf at night."]), "check")
	TestButton(kit, content, change, function() ns.TestTimeChangeTitle() end)

	local attack = stack:Add(kit.Check(content, "chatAttackAlert", L["Under attack"],
		L["When the LocalDefense channel says a place is under attack (\"Dun Algaz is under attack!\"), it " ..
		"shows in red where the zone name appears, with your faction's city bell. The same place shows at " ..
		"most once every 90 seconds."]), "check")
	TestButton(kit, content, attack, function()
		local place = GetMinimapZoneText and GetMinimapZoneText() or ""
		ns.ShowAlertTitle(L["%s is under attack!"]:format(place ~= "" and place or GetRealZoneText()))
	end)

	-- Shown only with the death camera (the Die row on the Cameras page).
	local banner = kit.Dropdown(content, "deathBannerStyle", {
		{ value = "none", text = L["None"] },
		{ value = "youdied", text = L["YOU DIED"] },
		{ value = "wasted", text = L["wasted"] },
	}, 180)
	if banner then
		banner.inlineName = L["Death banner"]
		stack:Add(banner, "dropdown")
		kit.Tooltip(banner, L["Shortly after the death camera starts, words fade in across the middle of the " ..
			"screen on a band, then fade away after a few seconds. \"YOU DIED\": dull red on a dark band with " ..
			"soft edges. \"wasted\": red with a dark outline on a flat black band."] .. " " ..
			L["Only with the death camera on (the Die row on the Scenes page)."])
		kit.GreyUnless(banner, function() return ns.TriggerAnyRow("Death") end)
		local test = TestButton(kit, content, banner, function() ns.TestDeathBanner() end)
		test:ClearAllPoints()
		test:SetPoint("LEFT", banner, "RIGHT", 10, 0)
	end

	-- The words' look (the Style pages' Look box): its font, General's first.
	local rows = ns.StyleRows(kit, content, stack, function() end, "storyVision")
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
		-- (Each line as the game's zone text it sits with: its size and color.)
		textSize = false, textColor = false,
	})

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Story Vision")
end
