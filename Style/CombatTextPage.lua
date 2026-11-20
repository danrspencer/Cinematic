-- The Style hub's Combat Text Style page (CombatTextStyle.lua draws the
-- numbers, CombatTextTexts.lua holds every text's settings): a preview of a
-- nameplate as yours look with sample numbers playing on it, then three
-- tabs. General: whose numbers, the last hit, quick looks. Look: every kind
-- of text the game sends in one list (an on/off switch and a color each),
-- and the picked one's settings under it, each part its group's until
-- changed. The game's text: its own numbers and XP text off.

local _, ns = ...
local L = ns.L
local CT = ns.CombatTexts

-- What the preview plays: a mix of hits (none picked, or a group), or the
-- picked text again and again (a hit with its crit). { time, text, its hit }:
-- spells of every school in the mix, so Spells by school shows (2026-11-18).
-- A fourth: its cast in seconds (a Fireball's 2.5, an instant's 0), so a
-- long cast's growing shows (CastSize, CastTime).
local MIX = { { 0, "spellFire", nil, 2.5 }, { 0.35, "swing" }, { 0.7, "spellFrost", nil, 0 },
	{ 1.0, "spellCrit", "spellFire", 2.5 }, { 1.02, "swing" }, { 1.05, "spellShadow" },
	{ 1.35, "spellShadow" }, { 1.7, "swingCrit" }, { 2.0, "spellArcane" }, { 2.3, "ability" }, { 2.6, "spellNature" },
	{ 2.45, "pet" }, { 2.85, "missDodge" }, { 3.1, "spellHoly" }, { 3.4, "spellMissResist" } }
local HEALS = { { 0, "heal", nil, 2.5 }, { 0.6, "heal", nil, 0 }, { 1.2, "healCrit", nil, 1.5 }, { 2.0, "heal" },
	{ 2.05, "heal" } }
local CRIT_WITH = { swing = "swingCrit", ability = "spellCrit", spell = "spellCrit", heal = "healCrit" }
local function StepsFor(id)
	local node = id and CT.NODE[id]
	if not node or id == "all" or id == "damage" then return nil end
	-- (Spells: each school, then a crit of one.)
	if id == "spell" then
		local steps, at = {}, 0
		for _, child in ipairs(node.children) do
			if CT.NODE[child].school then
				-- (In turn an instant and a long cast: a long one's growing shows.)
				steps[#steps + 1] = { at, child, nil, #steps % 2 == 1 and 2.5 or 0 }
				at = at + 0.45
			end
		end
		steps[#steps + 1] = { at, "spellCrit", "spellFrost", 2.5 }
		return steps
	end
	if node.children and not node.sample then
		local steps, at = {}, 0
		for _, child in ipairs(node.children) do
			steps[#steps + 1] = { at, child }
			at = at + 0.4
		end
		return steps
	end
	return { { 0, id, nil, 0 }, { 0.8, CRIT_WITH[id] or id, nil, 2.5 }, { 1.6, id, nil, 2.5 }, { 1.65, id } }
end

-- Whether a text's hits can come from a cast (spells and heals: their
-- CastSize, CastTime; a swing, an ability or a miss never has one).
local function Casts(id)
	local node = CT.NODE[id]
	if node and (node.word or node.misses) then return false end
	return id == "all" or id == "damage" or id:find("^spell") ~= nil or id:find("^heal") ~= nil
end

-- Choices, by setting.
local function MoveChoices()
	return {
		{ "up", L["Up"], L["Rises, as the game's."] },
		{ "down", L["Down"], L["Falls."] },
		{ "arcleft", L["Arc left"], L["Rises, curving left."] },
		{ "arcright", L["Arc right"], L["Rises, curving right."] },
		{ "fan", L["Fan out"], L["Curves left and right in turn."] },
		{ "stay", L["Stays"], L["Stays where it starts, then fades."] },
	}
end

function ns.CreateCombatTextStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Combat Text Style"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["Shows damage and healing numbers of our own in place of the game's."])

	-- An Experimental notice (not a gate: the page works as ever), back at
	-- the user's ask (2026-11-20): the game never says whose a hit is, so
	-- ours are told apart by guesswork (the log's lines, casts, totems).
	-- A skull (the raid marker's: on every client) and a red Experimental.
	local skull = content:CreateTexture(nil, "ARTWORK")
	skull:SetSize(20, 20)
	skull:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
	skull:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
	local warnTitle = kit.Label(content, "GameFontNormalLarge", L["Experimental"])
	warnTitle:SetPoint("LEFT", skull, "RIGHT", 6, 0)
	warnTitle:SetTextColor(1, 0.25, 0.2)
	local warnText = kit.Label(content, "GameFontHighlightSmall",
		L["You may see other people's damage as your own."])
	warnText:SetPoint("TOPLEFT", skull, "BOTTOMLEFT", 0, -6)
	warnText:SetWidth(520)
	warnText:SetJustifyH("LEFT")

	local function Changed() ns.RefreshCombatTextStyle() end
	local switch = kit.PageSwitch(content, "combatTextStyle", L["Enable Page"],
		L["Turns this page's combat text on or off."], warnText, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "combatTextStyle")
	local function Ours(db) return rows.On(db) and db.combatTextNumbers end

	-- The preview: a nameplate as yours look (the Nameplate Style page's own
	-- preview: your bar, border, name font and cast bar, over the lake or
	-- dark, a unit to pick under it), sample numbers playing on it.
	local preview, plate
	if ns.MakePlateRowLookPreview then
		preview = ns.MakePlateRowLookPreview(content, 480, "others")
		preview:SetHeight(170) -- (room over the plate for the numbers' climb)
		plate = preview.plate
		plate:ClearAllPoints()
		plate:SetPoint("BOTTOM", preview, "BOTTOM", 0, 44 / 1.6) -- (its scale: over the picks and its cast bar)
	else
		preview = CreateFrame("Frame", nil, content)
		preview:SetSize(480, 150)
		local back = preview:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0.05, 0.06, 0.08, 0.9)
		plate = CreateFrame("Frame", nil, preview)
		plate:SetSize(140, 30)
		plate:SetPoint("BOTTOM", 0, 26)
		local bar = plate:CreateTexture(nil, "ARTWORK")
		bar:SetPoint("BOTTOMLEFT")
		bar:SetSize(140, 10)
		bar:SetColorTexture(0.75, 0.1, 0.1, 1)
		preview.Refresh = function() end
	end
	stack:Add(preview, "label")
	kit.AddControl(preview)
	-- (Pop out and held at the page's top as you scroll, as every Style
	-- page's preview (2026-11-18). Its own Scene button stays: the pop-out's
	-- backdrop one draws only the Style scene, which this preview hasn't.)
	if ns.StylePopout then
		ns.StylePopout(preview, kit.Tooltip) -- (StylePages.lua)
		if preview.backButton then preview.backButton:Hide() end
		preview.backButton = nil
	end
	-- (The numbers drawn beside the preview, over it (and past its top: not
	-- in it, which clips), not in the world's frames under the window.)
	local layer = CreateFrame("Frame", nil, content)
	layer:SetAllPoints(preview)
	layer:SetFrameLevel(preview:GetFrameLevel() + 30)
	layer.layoutSkip = true -- (the sweep's layout check: its numbers fly over the page, not laid out)
	-- (Wherever the preview goes, popped out into its window or held at the
	-- top as you scroll: the layer with it, over it, its numbers its size.)
	local function Follow()
		local home = preview:GetParent()
		if home and layer:GetParent() ~= home then layer:SetParent(home) end
		layer:SetFrameStrata(preview:GetFrameStrata())
		layer:SetFrameLevel(math.min(preview:GetFrameLevel() + 30, 9000))
		layer.zoom = preview:GetEffectiveScale() / math.max(content:GetEffectiveScale(), 0.01)
	end
	hooksecurefunc(preview, "SetParent", Follow)
	hooksecurefunc(preview, "SetFrameLevel", Follow)
	-- (round: a stopped round's steps still waiting don't play. focus: the
	-- text picked on the Look tab, played alone.)
	local round, focus = 0, nil
	local function Play()
		Follow()
		local kind = preview.SampleKind and preview.SampleKind()
		local steps = StepsFor(focus)
		if not steps then
			steps = (kind == "Friendly" or kind == "Player") and HEALS or MIX
		end
		local this = round
		for _, step in ipairs(steps) do
			C_Timer.After(step[1], function()
				if this == round and preview:IsVisible() then ns.CombatTextSample(plate, step[2], layer, step[3], step[4]) end
			end)
		end
	end
	-- They play again and again while the page shows (a round every few
	-- seconds), so a change shows at once; Test turns into Stop while they
	-- do. Opening the page starts them again.
	local looping, ticker, test
	local function SetLooping(on)
		looping = on
		round = round + 1
		if ticker then ticker:Cancel() ticker = nil end
		if test then test:SetText(on and L["Stop"] or L["Test"]) end
		if on and preview:IsVisible() then
			Play()
			ticker = C_Timer.NewTicker(4, function()
				if looping and preview:IsVisible() then Play() end
			end)
		end
	end
	test = ns.StylePreviewTest(preview, kit, L["Plays sample hits on the nameplate over and over."],
		function() SetLooping(not looping) end)
	preview:HookScript("OnShow", function() SetLooping(true) end)
	preview:HookScript("OnHide", function()
		if ticker then ticker:Cancel() ticker = nil end
		round = round + 1
	end)

	-- Tabs (Options.lua's ns.PageTabsBelow), each a container (right-click
	-- off: all on it off; Texts' off: every text off, CombatTextTexts.lua).
	local hosts, _, TabsShown = ns.PageTabsBelow(content, preview, {
		{ L["General"], L["Turn our numbers on, and hide the game's."] },
		{ L["Look"], L["Each text starts out looking like the one it's under. Changing one only changes that one."] },
	}, "Combat Text Style/page", nil, nil, nil, function()
		local was = focus
		focus = nil -- (the mix again; a text's Look panel opened plays that text)
		if focus ~= was and looping then SetLooping(true) end
	end)
	-- (What's made on the page from here on goes onto a tab, its heading at the tab's top.)
	local made = {}
	for _, object in ipairs({ content:GetChildren() }) do made[object] = true end
	for _, object in ipairs({ content:GetRegions() }) do made[object] = true end
	local function Into(i, header)
		for _, set in ipairs({ { content:GetChildren() }, { content:GetRegions() } }) do
			for _, object in ipairs(set) do
				if not made[object] then
					made[object] = true
					object:SetParent(hosts[i])
				end
			end
		end
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", hosts[i], "TOPLEFT", 0, 0)
	end

	-- General ------------------------------------------------------------------
	-- Who draws the numbers (2026-11-19, the player's design): a row for each
	-- kind, your damage, your heals, your pet's, and the game's XP, each ours,
	-- the game's own or none. Your pet's has a note: in a group ours show only
	-- its spells (its swings look the same as your group's). XP none blanks
	-- the game's font, so its numbers go too: The game's leaves the other rows
	-- while it's set, and picking it with a row on The game's asks first.
	-- How ours look: the Look tab.
	local general = stack:Header(content, L["Who draws the numbers"])
	stack:Note(content, L["Ours follow the Look tab. The game's look the way the game normally draws them."], 560)
	-- (group: your pet's fourth cell, Game's in groups, 110 wide; the row
	-- ends at 620, inside the page's 600-plus width.)
	local COL = { ours = 210, game = 310, none = 410, group = 510 }
	local head = CreateFrame("Frame", nil, content)
	head:SetSize(600, 16)
	stack:Add(head, "label")
	for column, words in pairs({ ours = L["Ours"], game = L["The game's"], none = L["None"] }) do
		local label = kit.Label(head, "GameFontDisableSmall", words)
		label:SetPoint("CENTER", head, "LEFT", COL[column] + 48, 0) -- (over its column's buttons, 96 wide)
		label.searchSkip = true
	end
	local function GetDB() return ns.GetDB() or {} end
	local function XpHidden() return GetDB().hideWorldText and true or false end
	-- (The XP row's relog: the tick isn't what the game draws yet.)
	local function RestartPending()
		local db = ns.db or {}
		local wanted = db.hideWorldText and db.combatTextStyle and db.styleGeneral ~= false and true or false
		local live = db.worldTextLive
		if live == nil then live = ns.blankWorldFont ~= nil end
		return wanted ~= live
	end
	local function Applied()
		Changed()
		if ns.RefreshCombatTextStyle then ns.RefreshCombatTextStyle() end
		kit.Refresh()
	end
	-- A choice in a row: a segment, as the Quick settings' (picked: warmer,
	-- gold words, a gold line under), at its column; usable() false: greyed,
	-- offTip saying why (the user's ask, 2026-11-19: The game's greyed while
	-- XP is None, not gone).
	local function Cell(line, words, column, tip, click, lit, usable, offTip, width)
		local button = CreateFrame("Button", nil, line)
		local back = button:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		local under = button:CreateTexture(nil, "ARTWORK")
		under:SetPoint("BOTTOMLEFT")
		under:SetPoint("BOTTOMRIGHT")
		under:SetHeight(2)
		under:SetColorTexture(1, 0.82, 0, 1)
		local glow = button:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 1, 1, 0.07)
		local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("CENTER", 0, 1)
		text:SetText(words)
		button:SetSize(width or 96, 22)
		-- (Words wider than the cell: the small font, the words set again after
		-- it: a font changed under set words shows boxes for Russian.)
		if text:GetStringWidth() > (width or 96) - 8 then
			text:SetFontObject("GameFontHighlightSmall")
			text:SetText(words)
		end
		button:SetPoint("LEFT", line, "LEFT", COL[column], 0)
		button.searchLabel = words
		kit.Tooltip(button, tip)
		button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
		button:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
		button:SetScript("OnClick", click)
		button.Refresh = function(self)
			local can = not usable or usable()
			self.liveTip = not can and offTip or nil
			local on = lit()
			back:SetColorTexture(on and 0.2 or 0.1, on and 0.17 or 0.1, on and 0.08 or 0.12, 0.95)
			under:SetShown(on)
			if on then text:SetTextColor(1, 0.82, 0) else text:SetTextColor(0.85, 0.85, 0.85) end
			self:SetEnabled(can and rows.On(GetDB()) and true or false)
		end
		kit.AddControl(button)
		return button
	end
	-- A note under a row, from the Ours column, in its color.
	local function RowNote(r, g, b)
		local holder = CreateFrame("Frame", nil, content)
		holder:SetSize(600, 30)
		stack:Add(holder, "label")
		local note = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		note:SetPoint("TOPLEFT", holder, "TOPLEFT", COL.ours, 0)
		note:SetWidth(330)
		note:SetJustifyH("LEFT")
		note:SetTextColor(r, g, b)
		note.searchSkip = true
		return holder, note
	end
	local WHO = {
		{ "combatTextDamageBy", L["Your damage"], L["Your hits on enemies."] },
		{ "combatTextHealBy", L["Your heals"], L["Your heals on friendly nameplates."] },
		{ "combatTextPetBy", L["Your pet's damage"], L["Your pet's hits on enemies."], pet = true },
	}
	-- (The setting as saved: your pet's "group" stays "group" here.)
	local function By(key)
		local value = GetDB()[key]
		if value == "group" and key == "combatTextPetBy" then return value end
		return (value == "game" or value == "none") and value or "ours"
	end
	-- (A row on The game's, or Game's in groups: hiding XP would blank them.)
	local function UsesGame(key) local by = By(key) return by == "game" or by == "group" end
	for _, row in ipairs(WHO) do
		local key = row[1]
		local line = CreateFrame("Frame", nil, content)
		line:SetSize(620, 26)
		line.settingKey = key -- (/cine find)
		stack:Add(line, "label")
		local name = kit.Label(line, "GameFontHighlight", row[2])
		name:SetPoint("LEFT", line, "LEFT", 0, 0)
		kit.Tooltip(line, row[3])
		if row.pet then
			-- (Its own tooltip: what the warning is, 2026-11-19.)
			local warn = CreateFrame("Frame", nil, line)
			warn:SetSize(16, 16)
			warn:SetPoint("LEFT", name, "RIGHT", 6, 0)
			warn:EnableMouse(true)
			local icon = warn:CreateTexture(nil, "OVERLAY")
			icon:SetAllPoints()
			icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
			kit.Tooltip(warn, L["In a group, ours show only your pet's spells, not its swings."])
		end
		local function Pick(value) return function() GetDB()[key] = value Applied() end end
		Cell(line, L["Ours"], "ours", L["Ours, in the Look tab's look."], Pick("ours"),
			function() return By(key) == "ours" end)
		Cell(line, L["The game's"], "game", L["The game's own numbers, the way it normally draws them."], Pick("game"),
			function() return By(key) == "game" end, function() return not XpHidden() end,
			L["Set XP and other floating text to The game's first. While it's on None, the game draws none of its numbers."])
		Cell(line, L["None"], "none", L["No numbers for these."], Pick("none"),
			function() return By(key) == "none" end)
		if row.pet then
			Cell(line, L["Game's in groups"], "group",
				L["Ours when you're solo. In a group or raid, the game's own, which show every pet hit."], Pick("group"),
				function() return By(key) == "group" end, function() return not XpHidden() end,
				L["Set XP and other floating text to The game's first. While it's on None, the game draws none of its numbers."], 110)
			local holder, note = RowNote(1, 0.83, 0.62)
			holder.Refresh = function()
				local grouped = (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid())
				note:SetText(grouped and L["You're in a group: only your pet's spells show now. Its swings look the same as your group's."]
					or L["In a group, ours only show your pet's spells, since its swings look the same as everyone else's. The game's shows every pet hit in its own look."])
				note:SetShown(By(key) == "ours")
			end
			kit.AddControl(holder)
		end
	end
	-- The XP row: the game's floating text (XP gained, and all its numbers
	-- with it: one font), shown or none. None asks first while a row is on
	-- The game's: those would draw nothing.
	local function SetXpHidden(hidden)
		GetDB().hideWorldText = hidden
		Applied()
		if RestartPending() then StaticPopup_Show("CINEMATIC_WORLD_TEXT_RESTART") else StaticPopup_Hide("CINEMATIC_WORLD_TEXT_RESTART") end
	end
	StaticPopupDialogs.CINEMATIC_CT_XP_CONFLICT = {
		text = L["Hiding XP hides all the game's floating text, so these would show nothing: %s."],
		button1 = L["Switch them to ours"], button2 = CANCEL or L["Cancel"],
		OnAccept = function()
			for _, row in ipairs(WHO) do
				if UsesGame(row[1]) then GetDB()[row[1]] = "ours" end
			end
			SetXpHidden(true)
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	local xp = CreateFrame("Frame", nil, content)
	xp:SetSize(600, 26)
	xp.settingKey = "hideWorldText" -- (/cine find)
	stack:Add(xp, "label")
	local xpName = kit.Label(xp, "GameFontHighlight", L["XP and other floating text"])
	xpName:SetPoint("LEFT", xp, "LEFT", 0, 0)
	Cell(xp, L["The game's"], "game", L["The game's floating text: XP gained and the rest."],
		function() SetXpHidden(false) end, function() return not XpHidden() end)
	Cell(xp, L["None"], "none", L["Hides all the game's floating text, damage numbers included. Log out and back in to apply."],
		function()
			if XpHidden() then return end
			local using = {}
			for _, row in ipairs(WHO) do
				if UsesGame(row[1]) then using[#using + 1] = row[2] end
			end
			if using[1] then
				StaticPopup_Show("CINEMATIC_CT_XP_CONFLICT", table.concat(using, ", "))
			else
				SetXpHidden(true)
			end
		end, function() return XpHidden() end)
	local xpHolder, xpNote = RowNote(0.62, 0.62, 0.62)
	xpHolder.Refresh = function()
		if RestartPending() then
			xpNote:SetTextColor(1, 0.55, 0.25)
			xpNote:SetText(XpHidden()
				and L["Log out and back in to apply. With it hidden the game draws none of its numbers, so The game's is grayed out in the rows above."]
				or L["Log out and back in to apply: until then the game's floating text stays hidden."])
		else
			xpNote:SetTextColor(0.62, 0.62, 0.62)
			xpNote:SetText(XpHidden() and L["With it hidden the game draws none of its numbers, so The game's is grayed out in the rows above."]
				or L["None hides all of the game's floating text, damage numbers included. It takes a log out and back in."])
		end
	end
	kit.AddControl(xpHolder)
	Into(1, general)

	-- Texts ----------------------------------------------------------------------
	-- A row per text, as the Names rows (Name Style): its switch and name,
	-- indented under its group, and a button saying where its look comes
	-- from (its group's name, grey) or what's its own ("Own: Color", gold);
	-- the button opens its Look panel, a tab per part (Color, Text, Place,
	-- Motion), each setting its group's until set there. A miss word's and
	-- own word beside it.
	-- (Looks to start from, over the table: many texts set at once.)
	local lookTop = stack:Header(content, L["Quick settings"])
	stack:Help(content, L["Each row sets many texts at once. You can change any of them afterward in the table below."])
	local function Set(id, setting, value) ns.GetDB()[CT.Key(id, setting)] = value end
	-- Three rows, each one choice of its own (2026-11-18: one line of looks
	-- read as one choice, two of them lit at once): spell colors, which texts
	-- show, how big. Each choice lit while the settings are as it leaves them;
	-- none lit and "Your own" once they're set otherwise in the table. Reset
	-- all, beside the heading, puts every text back.
	local db = function() return ns.GetDB() or {} end
	local function ShowsOff(id) return db()[CT.Key(id, "Show")] == false end
	local HITS = { "swing", "swingGlance", "ability", "spell", "heal" }
	local CRITS = { "swingCrit", "spellCrit", "healCrit" }
	local SWINGS = { swing = true, swingCrit = true, miss = true } -- (No swings: what it turns off)
	-- (Your pet's rows aren't in Shows: their own row, Pet hits.)
	local function AllShow()
		for _, node in ipairs(CT.NODES) do
			if not node.pet then Set(node.id, "Show", nil) end
		end
	end
	local function Schools(color)
		for _, node in ipairs(CT.NODES) do
			if node.school then
				Set(node.id, "R", color and node.color[1] or nil)
				Set(node.id, "G", color and node.color[2] or nil)
				Set(node.id, "B", color and node.color[3] or nil)
			end
		end
	end
	local function SchoolsAre(color)
		for _, node in ipairs(CT.NODES) do
			if node.school and db()[CT.Key(node.id, "R")] ~= (color and node.color[1] or nil) then return false end
		end
		return true
	end
	-- (All texts' Size or Time on screen: 0.75, or back to the game's.)
	local function Scale(setting, on)
		CT.Field("all", setting).set(on and 0.75 or ns.DEFAULTS[CT.Key("all", setting)])
	end
	local function ScaleIs(setting, value) return CT.Get("all", setting) == value end
	-- (Pet hits: how big ours are. Who draws them, the game or none: the
	-- General tab's Your pet's damage.)
	local function PetOurs() return (ns.CombatTextBy and ns.CombatTextBy("pet") or "ours") == "ours" end
	local function PetAs(size)
		CT.Field("pet", "Size").set(size or (CT.Usual("pet", "Size")))
	end
	local function PlaceAs(value) ns.GetDB()[CT.Key("all", "Together")] = value end
	local function PlaceIs(value) return (CT.Value(CT.Key("all", "Together")) or "side") == value end
	-- By hit kind (2026-11-18): swings smaller (or shorter), spells and heals
	-- growing with their casts; off, each back to its usual.
	local KIND = { Size = { "Size", "CastSize" }, Time = { "Time", "CastTime" } }
	local function Kind(setting, on)
		local plain, grow = KIND[setting][1], KIND[setting][2]
		CT.Field("swing", plain).set(on and 0.8 or (CT.Usual("swing", plain)))
		for _, id in ipairs({ "spell", "heal" }) do CT.Field(id, grow).set(on and 0.15 or (CT.Usual(id, grow))) end
	end
	local function KindIs(setting)
		local plain, grow = KIND[setting][1], KIND[setting][2]
		return CT.Get("swing", plain) == 0.8 and CT.Get("spell", grow) == 0.15 and CT.Get("heal", grow) == 0.15
	end
	local function KindOff(setting)
		local plain, grow = KIND[setting][1], KIND[setting][2]
		return CT.Get("swing", plain) == CT.Get("all", plain) and (CT.Get("spell", grow) or 0) == 0
			and (CT.Get("heal", grow) or 0) == 0
	end
	-- { its name, { { choice's name, what it does, set, is it, what's said, rows it opens, preview }... } }
	local GROUPS = {
		{ L["Spell colors"], {
			{ L["All yellow"], L["Every spell in the game's yellow."], function() Schools(false) end,
				function() return SchoolsAre(false) end, L["Every spell is the game's yellow again."], {} },
			{ L["By school"], L["Each spell school in its own color: fire orange, frost blue."], function() Schools(true) end,
				function() return SchoolsAre(true) end, L["Each spell school has its own color: see Spells in the table."],
				{ "damage", "spell" }, "spell" },
		} },
		{ L["Shows"], {
			{ L["Everything"], L["Every text on."], AllShow, function()
				for _, node in ipairs(CT.NODES) do if not node.pet and ShowsOff(node.id) then return false end end
				return true
			end, L["Every text is on."], {} },
			{ L["Crits and misses"], L["Shows only your crits and misses, with plain hits and heals turned off."], function()
				AllShow()
				for _, id in ipairs(HITS) do Set(id, "Show", false) end
			end, function()
				for _, id in ipairs(HITS) do if not ShowsOff(id) then return false end end
				for _, id in ipairs(CRITS) do if ShowsOff(id) then return false end end
				return true
			end, L["Plain hits and heals are off and crits and misses are on. Switch any of them back in the table."],
				{ "damage", "swing", "ability", "spell", "heal" } },
			{ L["No swings"], L["Turns off your auto attacks, along with their crits and misses."], function()
				AllShow()
				for id in pairs(SWINGS) do Set(id, "Show", false) end
			end, function()
				for _, node in ipairs(CT.NODES) do
					if not node.pet and ShowsOff(node.id) ~= (SWINGS[node.id] or false) then return false end
				end
				return true
			end, L["Swings and swing crits are off: switch them back in the table."], { "damage", "swing" } },
		} },
		-- (Placement, 2026-11-19: how hits landing together sit, All texts'.)
		{ L["Placement"], {
			{ L["Side by side"], L["Side by side, as the game's."], function() PlaceAs(nil) end,
				function() return PlaceIs("side") end, "", {} },
			{ L["Stacked"], L["Each one a little higher than the last."], function() PlaceAs("stack") end,
				function() return PlaceIs("stack") end, "", {} },
			{ L["On top"], L["All in one spot."], function() PlaceAs("top") end,
				function() return PlaceIs("top") end, "", {} },
			{ L["Make room"], L["Crits and your casts show in the middle, and the rest move aside."], function() PlaceAs("room") end,
				function() return PlaceIs("room") end, "", {} },
		} },
		-- (Pet hits, 2026-11-19: small to start, or as big as yours.)
		{ L["Pet hits"], {
			{ L["Small"], L["Your pet's hits show smaller than yours."], function() PetAs(nil) end,
				function() return PetOurs() and CT.Get("pet", "Size") == 0.7 end, "", { "damage", "pet" } },
			{ L["Same as yours"], L["Your pet's hits show as big as yours."], function() PetAs(1) end,
				function() return PetOurs() and CT.Get("pet", "Size") == 1 end, "", { "damage", "pet" } },
		} },
		{ L["Size"], {
			{ L["The game's"], L["As big as the game's numbers."], function() Scale("Size", false) Kind("Size", false) end,
				function() return ScaleIs("Size", 1) and KindOff("Size") end, "", {} },
			{ L["Smaller"], L["Every number is three quarters of the game's size."],
				function() Kind("Size", false) Scale("Size", true) end,
				function() return ScaleIs("Size", 0.75) and KindOff("Size") end, "", {} },
			{ L["By hit kind"], L["Swings are smaller, and spells and heals get bigger the longer their cast."],
				function() Scale("Size", false) Kind("Size", true) end,
				function() return ScaleIs("Size", 1) and KindIs("Size") end, "", { "damage", "swing", "spell", "heal" } },
		} },
		-- (Its own row since 2026-11-18: how long isn't how big.)
		{ L["Duration"], {
			{ L["The game's"], L["On screen as long as the game's numbers."],
				function() Scale("Time", false) Kind("Time", false) end,
				function() return ScaleIs("Time", 1) and KindOff("Time") end, "", {} },
			{ L["Shorter"], L["Every number stays three quarters as long as the game's."],
				function() Kind("Time", false) Scale("Time", true) end,
				function() return ScaleIs("Time", 0.75) and KindOff("Time") end, "", {} },
			{ L["By hit kind"], L["Swings stay up for less time, and spells and heals stay longer the longer their cast."],
				function() Scale("Time", false) Kind("Time", true) end,
				function() return ScaleIs("Time", 1) and KindIs("Time") end, "", { "damage", "swing", "spell", "heal" } },
		} },
	}
	local Unfold -- (the table's: below)
	-- (Reset all, at the heading's right.)
	local resetAll = ns.PanelButton(content)
	-- (Reset, 2026-11-19: everything on this tab back to how it starts, the
	-- texts' looks, which show, and All texts' own few: placement, tags, the
	-- last hit. Was "Reset all to the game's", which left placement as it was.)
	resetAll:SetText(L["Reset"])
	local resetWords = resetAll:GetFontString()
	resetAll:SetSize(math.max(90, (resetWords and resetWords:GetStringWidth() or 60) + 24), 22)
	resetAll:SetPoint("LEFT", lookTop, "LEFT", 400, 0)
	kit.Tooltip(resetAll, L["Puts everything on this tab back to its defaults."])
	local OWN_FEW = { CT.Key("all", "Together"), CT.Key("all", "Tags"), CT.Key("all", "Numbers"), "combatTextKeepLast" }
	resetAll:SetScript("OnClick", function()
		for _, node in ipairs(CT.NODES) do
			CT.Reset(node.id)
			Set(node.id, "Show", nil)
		end
		for _, key in ipairs(OWN_FEW) do ns.GetDB()[key] = ns.DEFAULTS[key] end
		Changed()
		kit.Refresh()
	end)
	resetAll.Refresh = function(self)
		local any = false
		for _, node in ipairs(CT.NODES) do
			if CT.Changed(node.id) or ShowsOff(node.id) then any = true end
		end
		for _, key in ipairs(OWN_FEW) do
			local value = db()[key]
			if value ~= nil and value ~= ns.DEFAULTS[key] then any = true end
		end
		self:SetEnabled(Ours(db()) and any)
	end
	kit.AddControl(resetAll)
	for _, group in ipairs(GROUPS) do
		local line = CreateFrame("Frame", nil, content)
		line:SetSize(560, 26)
		stack:Add(line, "label")
		local name = kit.Label(line, "GameFontHighlight", group[1])
		name:SetPoint("LEFT", line, "LEFT", 0, 0)
		name:SetWidth(110)
		name:SetJustifyH("LEFT")
		local own = kit.Label(line, "GameFontDisableSmall", L["Your own"])
		own.searchSkip = true
		local last
		local buttons = {}
		for _, choice in ipairs(group[2]) do
			-- (A segment, as the Look panels' choices (StylePages.lua's Segments):
			-- joined, dark; the picked one warmer, gold words, a gold line under.
			-- Dark words on a gold band smeared the font's shadow, 2026-11-18.)
			local button = CreateFrame("Button", nil, line)
			local back = button:CreateTexture(nil, "BACKGROUND")
			back:SetAllPoints()
			local under = button:CreateTexture(nil, "ARTWORK")
			under:SetPoint("BOTTOMLEFT")
			under:SetPoint("BOTTOMRIGHT")
			under:SetHeight(2)
			under:SetColorTexture(1, 0.82, 0, 1)
			local glow = button:CreateTexture(nil, "HIGHLIGHT")
			glow:SetAllPoints()
			glow:SetColorTexture(1, 1, 1, 0.07)
			local words = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			words:SetPoint("CENTER", 0, 1)
			words:SetText(choice[1])
			button:SetSize(math.max(64, words:GetStringWidth() + 24), 22)
			if last then button:SetPoint("LEFT", last, "RIGHT", 1, 0) else button:SetPoint("LEFT", line, "LEFT", 114, 0) end
			button.searchLabel = choice[1]
			kit.Tooltip(button, choice[2])
			button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
			button:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
			button:SetScript("OnClick", function()
				choice[3]()
				if Unfold then Unfold(choice[6]) end
				focus = choice[7] -- (the preview plays what it changed: the schools for By school)
				if looping then SetLooping(true) end
				Changed()
				kit.Refresh()
			end)
			button.Refresh = function(self)
				local on = choice[4]()
				back:SetColorTexture(on and 0.2 or 0.1, on and 0.17 or 0.1, on and 0.08 or 0.12, 0.95)
				under:SetShown(on)
				if on then words:SetTextColor(1, 0.82, 0) else words:SetTextColor(0.85, 0.85, 0.85) end
				self:SetEnabled(Ours(db()) and true or false)
			end
			kit.AddControl(button)
			buttons[#buttons + 1] = choice
			last = button
		end
		own:SetPoint("LEFT", last, "RIGHT", 10, 0)
		-- ("Your own" while none of the row's choices is how things are.)
		local mark = CreateFrame("Frame", nil, line)
		mark.Refresh = function()
			local any = false
			for _, choice in ipairs(buttons) do any = any or choice[4]() end
			own:SetShown(not any)
		end
		kit.AddControl(mark)
	end

	local rowButtons = {}
	local hidden = { Add = function(_, control)
		control:Hide()
		return control
	end }
	-- (A value as words, for the panel's "As Spells: 100%".)
	local MOVE_WORDS = {}
	for _, choice in ipairs(MoveChoices()) do MOVE_WORDS[choice[1]] = choice[2] end
	local EDGE_WORDS = { game = L["The game's"], both = L["Edge and shadow"], edge = L["Dark edge"], none = L["None"] }
	local function Words(setting, value)
		if setting == "Font" then return value == "game" and L["The game's"] or ns.StyleFontName(value) end
		if setting == "Edge" then return EDGE_WORDS[value] or tostring(value) end
		if setting == "Move" then return MOVE_WORDS[value] or tostring(value) end
		if setting == "Start" then return value == "bar" and L["Over the bar"] or L["Over the name"] end
		if setting == "Pop" then return value and L["On"] or L["Off"] end
		if setting == "Y" or setting == "X" then return ("%d px"):format(tonumber(value) or 0) end
		if type(value) == "number" then return ("%d%%"):format(math.floor(value * 100 + 0.5)) end
		return tostring(value)
	end
	local function OpenRow(id)
		local row = rowButtons[id]
		if row.pop then
			row.pop:SetShown(not row.pop:IsShown())
			return
		end
		local label = CT.Label(id)
		local function Usual(setting) return (CT.Usual(id, setting)) end
		-- (A full key, a setting of the page's own on one text's panel (Tags on
		-- Damage's, Together and Last hit on All texts'), goes through as it is.)
		local styleRows = ns.StyleRows(kit, content, hidden, Changed, "combatTextStyle", function(setting)
			if setting:find("^ct_") or setting:find("^combatText") then return setting end
			return CT.Field(id, setting)
		end)
		local button, pop = styleRows.Look("", label, {
			tabs = {
				default = function(setting) return CT.PART_OF[setting] and Usual(setting) or nil end,
				usual = function(setting) return Words(setting, Usual(setting)), Usual(setting) end,
				-- (Where it's from: this text, else the text it's under that sets it.)
				source = function(setting)
					if not CT.PART_OF[setting] then return nil end
					local from = CT.From(id, setting)
					local key = CT.Key(id, setting)
					local saved = (ns.GetDB() or {})[key]
					-- (All texts': its own only where it's not the game's; the rest
					-- set here, else built in, else the text above's.)
					local own = from == id and saved ~= nil and (id ~= "all" or saved ~= ns.DEFAULTS[key])
					local fromName = from == "all" and L["The game's"] or (L["%s's"]):format(CT.Label(from))
					if from == id and id ~= "all" and not own then fromName = L["Built in"] end
					return { text = own and (id == "all" and L["Set here"] or L["This text"]) or fromName, own = own,
						parent = fromName, short = from == "all" and L["The game's"] or CT.Label(from) }
				end,
				resolved = function(setting) return Usual(setting) end,
				color = function()
					local color = CT.Color(id)
					return color[1], color[2], color[3]
				end,
				copyKind = "combatText", copyName = label,
				resetLabel = function() return id == "all" and L["Reset all"] or L["Clear this text"] end,
			},
			groups = {
				{ "Color", { { "textColor", "Color" } } },
				{ "Text", { { "font", "Font" }, { "textSize", "Size" }, { "shadow", "Edge" }, { "numbers", "Number style" },
					{ "tags", "Tags" } } },
				{ "Place", { { "place", "Place" }, { "together", "Together" } } },
				{ "Motion", { { "motion", "Motion" }, { "lastHit", "Last hit" } } },
			},
			-- (No color of All texts' or Damage's own: each text under them has one.)
			textColor = id ~= "all" and id ~= "damage" and function(look)
				look.Section(L["Color"])
				look.Chips(L["Its color"], { "R", "G", "B" })
			end,
			font = function(look)
				look.Section(L["Text"])
				look.Font("Font", L["The font for it."], nil, { "game", L["The game's"] })
			end,
			textSize = function(look)
				look.Slider("Size", L["Size"], 50, 300, 5, "%d%%", 100, L["How big it is compared to the game's."])
				look.Slider("CritScale", L["Crit size"], 100, 300, 5, "%d%%", 100, L["How big its crits are compared to its hits."])
				if Casts(id) then
					look.Slider("CastSize", L["Bigger per second of cast"], 0, 50, 5, "+%d%%", 100,
						L["Longer casts show bigger numbers, up to 150%; instants and unknown casts stay 100%."])
				end
			end,
			shadow = function(look)
				look.Segments(L["Edge"], "Edge", {
					{ "game", L["The game's"], L["A dark shadow up and to the right, no edge."] },
					{ "both", L["Edge and shadow"], L["A dark edge and the drop shadow."] },
					{ "edge", L["Dark edge"] },
					{ "none", L["None"] },
				})
			end,
			-- (All texts': how amounts are written, every number's. Retail only
			-- for now, the user's call 2026-11-19: hidden on Forever.)
			numbers = id == "all" and ns.isRetail and function(look)
				look.Dropdown(L["Number style"], CT.Key("all", "Numbers"), function()
					local tips = {
						full = L["Every digit, as the game's."],
						short = L["Thousands as K, one decimal."],
						whole = L["Thousands as K, no decimal."],
						bare = L["Thousands with no letter."],
						d10 = L["Every number divided by 10."],
						d100 = L["Every number divided by 100; smaller hits show 0."],
						d1000 = L["Every number divided by 1,000; smaller hits show 0."],
					}
					local list = {}
					for _, each in ipairs(CT.NUMBER_STYLES) do
						list[#list + 1] = { value = each[1], text = each[2], tip = tips[each[1]] }
					end
					return list
				end, L["How numbers are written: 22,245 as 22.2K, 22K, 22, or divided down."])
			end,
			-- (Damage's: a tag on hits that partly landed, every damage text's.)
			tags = id == "damage" and function(look)
				look.Section(L["Partly landed"])
				look.Check(CT.Key("all", "Tags"), L["Tag hits that partly landed"],
					L["Adds (Glancing), (Blocked) or (Resisted) after the number. In a fight, the amount is hidden."])
			end,
			-- (All texts': how hits landing together sit, and the last hit.)
			together = id == "all" and function(look)
				look.Segments(L["Hits landing together"], CT.Key("all", "Together"), {
					{ "side", L["Side by side"], L["Side by side, as the game's."] },
					{ "stack", L["Stacked"], L["Each one a little higher than the last."] },
					{ "top", L["On top"], L["All in one spot."] },
					{ "room", L["Make room"], L["Crits and your casts show in the middle, and the rest move aside."] },
				})
			end,
			lastHit = id == "all" and function(look)
				look.Section(L["When a mob dies"])
				look.Check("combatTextKeepLast", L["Last hit stays on screen"],
					L["A dying mob's last number finishes above the middle of the screen."])
			end,
			place = function(look)
				look.Section(L["Place"])
				look.Pair(true)
				look.Slider("Y", L["Y offset"], -80, 150, 2, "%d px", nil, L["Moves it up or down."])
				look.Slider("X", L["X offset"], -150, 150, 2, "%d px", nil, L["Moves it left or right."])
				look.Pair(false)
				look.Segments(L["Starts"], "Start", {
					{ "name", L["Over the name"], L["Where the game's hits start."] },
					{ "bar", L["Over the bar"], L["Low over the health bar, where the game's crits sit."] },
				})
			end,
			motion = function(look)
				look.Section(L["Motion"])
				look.Segments(L["Moves"], "Move", MoveChoices())
				look.Pair(true)
				look.Slider("Climb", L["Climb"], 0, 300, 10, "%d%%", 100, L["How far it moves compared to the game's."])
				look.Slider("Time", L["Time on screen"], 30, 300, 10, "%d%%", 100, L["How long it stays compared to the game's."])
				look.Pair(false)
				if Casts(id) then
					look.Slider("CastTime", L["Longer per second of cast"], 0, 50, 5, "+%d%%", 100,
						L["Longer casts stay longer, up to 150%; instants and unknown casts stay 100%."])
				end
				look.Slider("Fade", L["Fades from"], 10, 95, 5, "%d%%", 100, L["How far into its time on screen it starts to fade."])
				look.Segments(L["Pops in"], "Pop", { { true, L["On"], L["Grows big for a moment, then settles, like the game's crits."] },
					{ false, L["Off"] } })
			end,
		})
		if button then button:Hide() end
		row.pop = pop
		pop:HookScript("OnShow", function()
			local was = focus
			focus = id
			if focus ~= was and looping then SetLooping(true) end
		end)
		pop:Show()
	end
	-- The rows, in a box of their own so a group can fold up (its rows
	-- hidden, the ones under moving up). Each: a + or - on a group, a small
	-- switch (a pill, not a tick: green on), its color, its name in that
	-- color, its look's button and (a miss word's) its own word.
	-- Right-click a row to turn it on or off too.
	local ROW_X, ROW_H = 250, 26 -- (the buttons' column, past the deepest name; a row's height)
	-- (To start: every group folded but All texts and Damage, 2026-11-19.)
	local folded = {}
	for _, node in ipairs(CT.NODES) do
		if node.children and node.id ~= "all" and node.id ~= "damage" then folded[node.id] = true end
	end
	local box = CreateFrame("Frame", nil, content)
	box:SetSize(560, ROW_H)
	stack:Add(box, "label")
	local lines = {}
	local function Hidden(node)
		local step = node.parent and CT.NODE[node.parent]
		while step do
			if folded[step.id] then return true end
			step = step.parent and CT.NODE[step.parent]
		end
		return false
	end
	local function Layout()
		local y = 0
		for _, line in ipairs(lines) do
			local show = not Hidden(line.node)
			line.frame:SetShown(show)
			if show then
				line.frame:ClearAllPoints()
				line.frame:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
				y = y + ROW_H
			end
			if line.fold then
				line.fold:SetNormalTexture(folded[line.node.id] and "Interface\\Buttons\\UI-PlusButton-Up"
					or "Interface\\Buttons\\UI-MinusButton-Up")
			end
		end
		box:SetHeight(math.max(ROW_H, y))
		if kit.FitContentHeight then
			kit.FitContentHeight(content)
			C_Timer.After(0, function() kit.FitContentHeight(content) end)
		end
	end
	-- (A look clicked opens the rows it changed: these groups, each unfolded.)
	Unfold = function(ids)
		for _, id in ipairs(ids or {}) do folded[id] = nil end
		Layout()
	end
	local function ShowOn(id)
		local key = CT.Key(id, "Show")
		local value = (ns.GetDB() or {})[key]
		if value == nil then value = ns.DEFAULTS[key] end
		return value ~= false
	end
	local function Flip(id)
		ns.GetDB()[CT.Key(id, "Show")] = not ShowOn(id)
		Changed()
		kit.Refresh()
	end
	local function RowColor(node) return CT.Color(node.id) end -- (a school's crit: its school's, critOf)
	for _, node in ipairs(CT.NODES) do
		local id = node.id
		local line = { node = node }
		local row = CreateFrame("Button", nil, box)
		row:SetSize(560, ROW_H)
		row:RegisterForClicks("RightButtonUp")
		row:SetScript("OnClick", function() Flip(id) end)
		row.searchLabel = L[node.label]
		line.frame = row
		-- (Search finding it inside a folded group: its groups unfolded.)
		row.openSection = function()
			local ids, step = {}, node.parent
			while step do
				ids[#ids + 1] = step
				step = CT.NODE[step] and CT.NODE[step].parent
			end
			if Unfold then Unfold(ids) end
		end
		local x = node.depth * 18
		-- (A group's + or -.)
		if node.children then
			local fold = CreateFrame("Button", nil, row)
			fold:SetSize(14, 14)
			fold:SetPoint("LEFT", row, "LEFT", x, 0)
			fold:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
			fold:SetScript("OnClick", function()
				folded[id] = not folded[id] or nil
				Layout()
			end)
			kit.Tooltip(fold, L["Shows or hides the texts under it."])
			line.fold = fold
		end
		-- (The switch: a track and a knob, left off, right on.)
		local switch = CreateFrame("Button", nil, row)
		switch:SetSize(26, 13)
		switch:SetPoint("LEFT", row, "LEFT", x + 18, 0)
		switch.settingKey = CT.Key(id, "Show") -- (its id for /cine find)
		switch.searchLabel = L[node.label]
		local track = switch:CreateTexture(nil, "ARTWORK")
		track:SetAllPoints()
		local knob = switch:CreateTexture(nil, "OVERLAY")
		knob:SetSize(9, 9)
		knob:SetColorTexture(0.95, 0.95, 0.95, 1)
		switch:SetScript("OnClick", function() Flip(id) end)
		kit.Tooltip(switch, node.crit and L["Shows these crits or not."]
			or L["Shows or hides it. Turning it off hides the texts under it too, except crits, which have their own."])
		local chip = row:CreateTexture(nil, "ARTWORK")
		chip:SetSize(12, 12)
		chip:SetPoint("LEFT", switch, "RIGHT", 8, 0)
		local chipEdge = row:CreateTexture(nil, "BORDER")
		chipEdge:SetPoint("TOPLEFT", chip, -1, 1)
		chipEdge:SetPoint("BOTTOMRIGHT", chip, 1, -1)
		chipEdge:SetColorTexture(0, 0, 0, 1)
		local name = row:CreateFontString(nil, "OVERLAY", node.children and "GameFontNormal" or "GameFontHighlight")
		name:SetPoint("LEFT", chip, "RIGHT", 8, 0)
		name:SetText(L[node.label])
		if node.tip then kit.Tooltip(row, L[node.tip]) end
		-- (Drawn again with every change: the switch, its color, greyed while a
		-- group over it is off.)
		row.Refresh = function()
			local on = ShowOn(id)
			track:SetColorTexture(on and 0.2 or 0.22, on and 0.55 or 0.22, on and 0.22 or 0.24, 1)
			knob:ClearAllPoints()
			knob:SetPoint(on and "RIGHT" or "LEFT", switch, on and "RIGHT" or "LEFT", on and -2 or 2, 0)
			local color = RowColor(node)
			chip:SetColorTexture(color[1], color[2], color[3], 1)
			local shows = CT.Shows(id, nil, true)
			if node.children and id ~= "heal" and id ~= "swing" and id ~= "ability" and id ~= "spell" then
				name:SetTextColor(shows and 1 or 0.5, shows and 0.82 or 0.5, shows and 0 or 0.5) -- (a group: gold)
			else
				local k = shows and 1 or 0.45
				name:SetTextColor(color[1] * k + (1 - k) * 0.5, color[2] * k + (1 - k) * 0.5, color[3] * k + (1 - k) * 0.5)
			end
			row:SetAlpha(Ours(ns.GetDB() or {}) and 1 or 0.5)
		end
		kit.AddControl(row)

		local button = ns.PanelButton(row)
		button:SetHeight(22)
		button:SetPoint("LEFT", row, "LEFT", ROW_X, 0)
		button.searchLabel = L[node.label]
		kit.Tooltip(button, id == "all" and L["Every text's look; each row below starts from it."]
			or L["This text's own look, on top of the one above it."])
		button:SetScript("OnClick", function() OpenRow(id) end)
		button.opensLook = true -- (opens a Look panel: /cine debug lookdock clicks one a page)
		function button.Refresh(self)
			local own = CT.OwnParts(id)
			local inherits = false
			if #own > 0 then
				local names = {}
				for i, part in ipairs(own) do names[i] = L[part] end
				self:SetText(L["Own:"] .. " " .. table.concat(names, " · "))
			elseif id == "all" then
				self:SetText(L["The game's"])
			else
				self:SetText(CT.Label(node.parent))
				inherits = true
			end
			local words = self:GetFontString()
			if words then
				if inherits then words:SetTextColor(0.6, 0.6, 0.6) else words:SetTextColor(1, 0.82, 0) end
			end
			self:SetWidth(math.max(140, (words and words:GetStringWidth() or 100) + 30))
			self:SetEnabled(Ours(ns.GetDB() or {}) and true or false)
		end
		kit.AddControl(button)
		rowButtons[id] = button
		-- (A thin line under All texts: the rows below start from it.)
		if id == "all" then
			local rule = row:CreateTexture(nil, "ARTWORK")
			rule:SetColorTexture(0.45, 0.38, 0.2, 0.8)
			rule:SetHeight(1)
			rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
			rule:SetPoint("RIGHT", button, "LEFT", 300, 0)
		end
		-- (A word of its own, beside its button: a miss word's.)
		if node.word then
			local edit = ns.SkinEditBox(CreateFrame("EditBox", nil, row, "InputBoxTemplate"))
			edit:SetSize(90, 20)
			edit:SetPoint("LEFT", button, "RIGHT", 10, 0)
			edit:SetAutoFocus(false)
			edit:SetMaxLetters(24)
			edit.searchLabel = L[node.label]
			edit.settingKey = CT.Key(id, "Word") -- (its id for /cine find)
			local function Save(self)
				local text = self:GetText() or ""
				ns.GetDB()[CT.Key(id, "Word")] = text:match("%S") and text or nil
				self:ClearFocus()
				Changed()
				kit.Refresh()
			end
			edit:SetScript("OnEnterPressed", Save)
			edit:SetScript("OnEditFocusLost", Save)
			edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
			kit.Tooltip(edit, (L["Your own word in place of the game's (%s). Leave it empty to use the game's."]):format(CT.Word(id, true)))
			edit.Refresh = function(self)
				if not self:HasFocus() then self:SetText((ns.GetDB() or {})[CT.Key(id, "Word")] or "") end
				self:SetEnabled(Ours(ns.GetDB() or {}) and true or false)
			end
			kit.AddControl(edit)
		end
		lines[#lines + 1] = line
	end
	Layout()
	box:HookScript("OnShow", Layout)
	Into(2, lookTop) -- (Start from a look at the tab's top, the table under it)

	-- Reset page: every text's settings too (fields aren't the page's keys).
	if kit.OnReset then
		kit.OnReset(content, function()
			for _, node in ipairs(CT.NODES) do
				CT.Reset(node.id)
				ns.GetDB()[CT.Key(node.id, "Show")] = nil
			end
			Changed()
		end)
	end

	canvas:SetScript("OnShow", kit.PageShown(function()
		kit.Refresh()
		TabsShown()
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Combat Text Style", L["Combat Text Style"])
end

-- The welcome window's Combat Text demo (ShowMe.lua): this page's preview, a
-- nameplate as yours look, on the screen near its top (over the faded
-- window), the page's mix of hits played on it twice. Your numbers' look,
-- whether the page is on or not: it's what they'd look like.
local DEMO_PASSES, DEMO_EVERY = 2, 4 -- (rounds of the mix, seconds apart)
local demo
function ns.ShowCombatTextDemo(on)
	if not on then
		if demo then
			demo.round = demo.round + 1
			demo:Hide()
		end
		return true
	end
	if not ns.MakePlateRowLookPreview then return false end
	if not demo then
		demo = CreateFrame("Frame", nil, UIParent)
		demo:SetSize(480, 170)
		demo:SetPoint("TOP", UIParent, "TOP", 0, -130)
		demo:SetFrameStrata("FULLSCREEN")
		demo:EnableMouse(false)
		local preview = ns.MakePlateRowLookPreview(demo, 480, "others")
		preview:SetPoint("TOPLEFT")
		preview:SetHeight(170) -- (room over the plate for the numbers' climb, as on the page)
		preview.plate:ClearAllPoints()
		preview.plate:SetPoint("BOTTOM", preview, "BOTTOM", 0, 44 / 1.6)
		-- (the numbers over it, past its top: not in it, which clips)
		local layer = CreateFrame("Frame", nil, demo)
		layer:SetAllPoints(preview)
		layer:SetFrameLevel(math.min(preview:GetFrameLevel() + 30, 9000))
		layer.zoom = 1
		demo.preview, demo.layer, demo.round = preview, layer, 0
		-- (Not the page's picker, Scene button or "not saved" tag: they're the
		-- page's, and showed on the screen, 2026-11-20. Hiding them didn't
		-- hold (something shows them again after), so in this copy of the
		-- preview they go onto a frame that's never shown.)
		local away = CreateFrame("Frame", nil, demo)
		away:Hide()
		for _, piece in ipairs(preview.pagePieces or {}) do piece:SetParent(away) end
	end
	demo:Show()
	demo.round = demo.round + 1
	local this = demo.round
	for pass = 0, DEMO_PASSES - 1 do
		for _, step in ipairs(MIX) do
			C_Timer.After(pass * DEMO_EVERY + step[1], function()
				if this == demo.round and demo:IsShown() then
					demo.played = (demo.played or 0) + 1
					ns.CombatTextSample(demo.preview.plate, step[2], demo.layer, step[3], step[4])
				end
			end)
		end
	end
	return true
end
-- (For the shelf's test: shown, and how many hits it's played.)
function ns.CombatTextDemoState()
	local pieces = 0
	for _, piece in ipairs(demo and demo.preview.pagePieces or {}) do
		if piece:IsVisible() then pieces = pieces + 1 end
	end
	return demo ~= nil and demo:IsShown(), demo and demo.played or 0, pieces
end
