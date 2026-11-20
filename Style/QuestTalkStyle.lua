-- Quest Vision's Quest talk tab: quest talk itself (its switch, questTalk:
-- off, the game's own gossip and quest windows) and how it looks (QuestTalk.lua
-- draws it): the panels behind the NPC's words, your replies and the quest's card
-- (parchment, the game's chat bubble, dark or none), their opacity, and the
-- words' font, size and outline. A preview at the top: a bubble and its
-- replies, dressed by quest talk's own code. Then its controls (the "Show
-- the game's window" link, the number keys). Where it sits (and where the
-- game's windows do, with it off): the Vision tab (Options.lua).

local _, ns = ...
local L = ns.L


function ns.CreateQuestTalkStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Dialogue"])
	ns.QuestTabs(content, title, 2)
	local intro = kit.PageIntro(content, title,
		L["How NPC dialogue looks."])

	local preview -- (below: drawn again as each setting changes)
	local function Changed()
		if ns.RefreshQuestTalkStyle then ns.RefreshQuestTalkStyle() end
		if preview then preview:Refresh() end
	end

	local switch = kit.PageSwitch(content, "questTalkStyled", L["Enable Page"],
		L["When on, the dialogue looks the way this page sets it. When off, it uses the game's parchment."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "questTalk")

	preview = ns.MakeQuestTalkPreview(content, 480)
	stack:Add(preview, "label")
	ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
	kit.AddControl(preview)


	stack:Header(content, L["Panels"])
	rows.Look(L["Look:"], L["Panels"], {
		backColor = function(look)
			look.Choices(L["Panels:"], "questTalkStyle", {
				{ "parchment", L["Parchment"], L["Like the quest window's page."] },
				{ "bubble", L["Chat bubble"], L["The game's own chat bubble."] },
				{ "dark", L["Dark"] },
				{ "none", L["None"], L["Just the words, with no bubble. An outline makes them easier to read."] },
			})
		end,
		backAlpha = function(look)
			look.Slider("questTalkAlpha", L["Opacity"], 20, 100, 5, "%d%%", 100, L["How see-through the panels are."],
				function(db) return db.questTalk and db.questTalkStyle ~= "none" end)
		end,
	})
	rows.Check("questTalkCardSame", L["Quest card on the bubble's background"],
		L["Gives the quest card and reply list the bubble's look."])
	rows.Check("questTalkPortrait", L["The NPC's portrait"],
		L["Shows the NPC's round portrait on the bubble's top left corner."])

	stack:Header(content, L["Size"])
	rows.Slider("questTalkScale", L["Scale"], 70, 150, 5, "%d%%", 100,
		L["The size of the bubble and the reply list. Their text grows with them."])
	rows.Slider("questTalkLines", L["Bubble height"], 3, 15, 1, L["%d lines"], 1,
		L["How many lines of words the bubble holds."])

	-- Where the quest card and the list sit (where the bubble does: the Quest
	-- Vision page's Where they go).
	stack:Header(content, L["Layout"])
	local SIDE_TIP = L["Where the quest card goes next to the bubble."] .. " " ..
		""
	local function SideOn(db) return db.questTalk end
	local side = kit.Dropdown(content, "questTalkCardSide", {
		{ value = "below", text = L["Below"] },
		{ value = "side", text = L["Side"] },
		{ value = "right", text = L["Right"] },
		{ value = "left", text = L["Left"] },
		{ value = "separate", text = L["Separate"] },
	}, 160, Changed)
	if side then
		local sideName = stack:Add(kit.Label(content, "GameFontHighlight", L["Quest card beside the bubble"]), "label")
		side:SetPoint("LEFT", sideName, "RIGHT", 10, 0)
		kit.GreyUnless(side, SideOn)
		kit.Tooltip(side, SIDE_TIP)
	else
		rows.Choices(L["Quest card beside the bubble"], "questTalkCardSide", {
			{ "below", L["Below"], SIDE_TIP }, { "side", L["Side"], SIDE_TIP },
			{ "right", L["Right"], SIDE_TIP }, { "left", L["Left"], SIDE_TIP },
			{ "separate", L["Separate"], SIDE_TIP },
		}, SideOn)
	end
	local listLine = stack:Add(kit.BoxLine(content), "label")
	local listY = listLine:Box(L["List height on the screen"], "questTalkListY", 20, 80, 1, "%d", 100,
		L["How far up the screen the list of replies starts."], function()
			ns.GetDB().questTalkSpot = nil -- (the box decides again)
			Changed()
		end, nil, "%")
	-- (Only Separate's: else the card goes with the bubble.)
	kit.GreyUnless(listY, function(db) return rows.On(db) and db.questTalkCardSide == "separate" end)

	stack:Header(content, L["Words"])
	rows.Look(L["Look:"], L["Words"], {
		font = { "questTalkFont", L["The font for the words."] },
		textSize = function(look)
			look.Slider("questTalkTextSize", L["Text size"], 70, 150, 5, "%d%%", 100,
				L["How big the words are, next to their usual size."])
			look.Slider("questTalkNumberAlpha", L["Numbers opacity"], 10, 100, 5, "%d%%", 100,
				L["How faded the page count (2 / 3) and the numbers by the replies and buttons are."])
		end,
		outline = { "questTalkOutline", L["A black border around the letters, for light text with no panel behind it."], names = { [0] = L["None"], L["Thin"], L["Thick"] } },
		outlineColor = false, -- (a page of words: too many copies)
		shadow = { "questTalkShadow" },
		textColor = { "questTalkTextColor", L["The bubble's text in a color of your own. The quest card keeps its own color."], keys = { "questTalkTextR", "questTalkTextG", "questTalkTextB" } },
	})

	-- Using it.
	stack:Header(content, L["Controls"])
	local function Control(key, label, tip)
		stack:Add(kit.Check(content, key, label, tip, function(value)
			ns.GetDB()[key] = value
			if ns.RefreshQuestTalk then ns.RefreshQuestTalk() end
			Changed()
		end), "check")
	end
	Control("questTalkGameButton", L["\"Show the game's window\" link"],
		L["Adds a link on the quest card that brings back the game's quest window."])
	Control("questTalkKeys", L["Number keys and Space"],
		L["Number keys pick a reply and Space moves on, outside fights."])

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Quest Talk Style", L["Dialogue"])
end
