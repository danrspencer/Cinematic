-- The frames tables' rows as dropdowns (Options.lua's ShowTable: Standard
-- Frames, Gamepad, Chat): an Always box, a dropdown of the fights and one
-- of the places (each ticked item shows the row: all joined by OR, as the
-- columns were) and an Edit button. The ticks are the lists the
-- columns always were (combatShow, worldShow...), so saved settings and
-- profiles are as they were. Edit shows the row as a rule (db.frameRules,
-- ns.CompileRule) in the rule editor here: one still just the dropdowns'
-- words joined by OR goes back into them as it closes; one with more (AND,
-- NOT, other words) is the row's rule, shown in its place, its words in
-- their groups' colours.

local _, ns = ...
local L = ns.L

-- A tip on hover (the widget's own OnEnter and OnLeave).
local function Tip(widget, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(type(text) == "function" and text() or text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function Colored(color, text)
	return ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, text)
end

-- Each camera a rule can name (Frames.lua's ns.RULE_CAMERAS), by its name:
-- { word, name }.
function ns.RuleCameraList()
	local names = { chatcam = L["Chat Cam"] }
	for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do names[cam[1]] = cam[2] end
	local list = {}
	for _, cam in ipairs(ns.RULE_CAMERAS) do
		list[#list + 1] = { cam[1], cam[2] and names[cam[2]] or L["A camera script"] }
	end
	return list
end
-- The Camera line: any camera, then a pick of one (a menu where the client
-- has them; else a button each). A piece with pick: a menu of { word, label }.
function ns.RuleCameraPieces()
	local pieces = { { "camera", L["In a camera mode"] } }
	if ns.GRID_MENUS then
		pieces[2] = { "", L["Specific camera..."], pick = ns.RuleCameraList() }
	else
		for _, cam in ipairs(ns.RuleCameraList()) do pieces[#pieces + 1] = cam end
	end
	return pieces
end

-- The pieces of a rule, a line of buttons each in the rule editor:
-- { name, colour, { { word, label }... } }. Made when asked,
-- once the language is known.
function ns.RulePieces()
	local location = { { "world", L["Open world"] }, { "city", L["Cities"] }, { "inn", L["Inns"] },
		{ "bg", L["BGs & arenas"] } }
	if ns.isRetail then -- (apart where there are arenas)
		location[#location + 1] = { "battleground", L["Battlegrounds"] }
		location[#location + 1] = { "arena", L["Arenas"] }
	end
	for _, piece in ipairs({ { "instance", L["Instances"] }, { "dungeon", L["Dungeons"] }, { "raid", L["Raids"] } }) do
		location[#location + 1] = piece
	end
	-- (Spell range's bands, Frames.lua: * as the yards go by your class.
	-- Within: each is your target in reach, closer too, not a ring.)
	local ranges = {}
	for _, band in ipairs(ns.RANGE_BANDS) do
		ranges[#ranges + 1] = { band.field, (L["Within %s*"]):format(band.label) }
	end
	-- (The classes this client has, by the game's names for them.)
	local classes = {}
	for id = 1, (GetNumClasses and GetNumClasses() or 0) do
		local name, file = GetClassInfo(id)
		if name and file and ns.RULE_WORDS[file:lower()] then
			classes[#classes + 1] = { file:lower(), name }
		end
	end
	return {
		{ L["Logic"], { 1, 1, 1 }, { { "and", "AND" }, { "or", "OR" }, { "not", "NOT" }, { "(", "(" }, { ")", ")" } } },
		{ L["Combat"], { 1, 0.45, 0.4 }, { { "combat", L["In combat"] }, { "calm", L["Calm Timer"] },
			{ "nocombat", L["Out of combat"] },
			{ "entering", L["Entering combat"] }, { "leaving", L["Leaving combat"] }, { "boss", L["Boss fight"] } } },
		{ L["Camera"], { 0.95, 0.75, 0.45 }, ns.RuleCameraPieces() },
		{ L["Target"], { 1, 0.65, 0.25 }, { { "enemy", L["Enemy targeted"] }, { "friendly", L["Friend targeted"] },
			{ "target", L["Anything targeted"] }, { "targetself", L["You"] }, { "enemyplayer", L["Enemy players"] },
			{ "hostilenpc", L["Hostile NPCs"] }, { "neutralplayer", L["Neutral players"] },
			{ "neutralnpc", L["Neutral NPCs"] }, { "friendlyplayer", L["Friendly players"] },
			{ "friendlynpc", L["Friendly NPCs"] }, { "noplate", L["Plate off screen"] }, { "near", L["Near (11 yards)"] }, { "near28", L["Near (28 yards)"] } } },
		{ L["Spell range"], { 0.45, 0.9, 0.9 }, ranges },
		{ L["Nearby"], { 1, 0.5, 0.8 }, { { "elite11", L["Elite near (11 yards)"] },
			{ "elite28", L["Elite near (28 yards)"] }, { "elite40", L["Elite near (40 yards)"] } } },
		{ L["Location"], { 0.45, 0.75, 1 }, location },
		{ L["You"], { 0.8, 0.6, 1 }, { { "mounted", L["Mounted"] }, { "flagged", L["PvP flagged"] },
			{ "group", L["Grouped"] }, { "cinemode", L["In CineMode"] } } },
		{ L["Role"], { 0.4, 0.85, 0.5 }, { { "tank", L["Tank"] }, { "healer", L["Healer"] }, { "damage", L["Damage"] } } },
		{ L["Class"], { 0.85, 0.75, 0.6 }, classes },
		-- (Last: the editor shows it only for the Tooltips row, tooltip:All.)
		{ L["Tooltip"], { 0.95, 0.95, 0.6 }, { { "tipenemy", L["Enemy"] }, { "tipfriendly", L["Friendly"] },
			{ "tipgather", L["Gatherable"] }, { "tipquest", L["Quest objective"] }, { "tipother", L["Anything else"] } },
			tooltipOnly = true },
	}
end

-- Each situation's colour (a field of the rules' facts: aliases share it).
local fieldColor
local function FieldColor(field)
	if not fieldColor then
		fieldColor = { always = { 1, 0.82, 0 }, never = { 1, 0.82, 0 } }
		for _, group in ipairs(ns.RulePieces()) do
			for _, piece in ipairs(group[3]) do
				local field = ns.RULE_WORDS[piece[1]]
				if field then fieldColor[field] = group[2] end
				for _, picked in ipairs(piece.pick or {}) do -- (a menu's words: its line's colour too)
					fieldColor[ns.RULE_WORDS[picked[1]] or picked[1]] = group[2]
				end
			end
		end
	end
	return fieldColor[field]
end
local LOGIC_COLOR, UNKNOWN_COLOR = { 0.7, 0.7, 0.7 }, { 1, 0.38, 0.38 }

-- A rule's text with each word in its group's colour (one the rules don't
-- know red), the logic grey, for showing.
function ns.ColoredRule(text)
	-- (A word, then what's up to the next: spaces, brackets and signs, a | doubled to show as one.)
	return (text:gsub("([%w_]*)([^%w_]*)", function(word, between)
		local lower = word:lower()
		local color = (lower == "and" or lower == "or" or lower == "not") and LOGIC_COLOR
			or FieldColor(ns.RULE_WORDS[lower]) or UNKNOWN_COLOR
		word = word ~= "" and Colored(color, word) or ""
		between = between:find("%S") and Colored(LOGIC_COLOR, (between:gsub("|", "||"))) or between
		return word .. between
	end))
end

-- A row's ticks as a rule: the ticked words joined by OR, always first
-- with Always on (the rest kept, for when it's off again); never with none.
function ns.GridRule(always, words)
	local text = table.concat(words, " or ")
	if always then return text ~= "" and "always or " .. text or "always" end
	return text ~= "" and text or "never"
end

-- A rule read back into a row: words joined by OR, each one of the grid's
-- (grid: field -> true; target is enemy and friendly both), brackets
-- allowed. Gives always, and the fields ticked (field -> true); or nil and why not.
function ns.ReadGridRule(text, grid)
	local always, ticked, n = false, {}, 0
	local i = 1
	while i <= #text do
		local c = text:sub(i, i)
		if c:find("[%s()]") then
			i = i + 1
		else
			local token = text:match("^[%w_]+", i) or text:match("^[&|!]+", i)
			if not token then return nil, (L["can't read \"%s\""]):format(c) end
			i = i + #token
			local lower = token:lower()
			if lower == "and" or lower == "not" or token:find("^[&!]") then
				return nil, L["the dropdowns only join with OR"]
			end
			-- (Words and ORs take turns, a word first and last.)
			n = n + 1
			local isOr = lower == "or" or lower:find("^|+$") ~= nil
			if (n % 2 == 1) == isOr then return nil, L["it isn't finished"] end
			if not isOr then
				local field = ns.RULE_WORDS[lower]
				if not field then
					return nil, (L["\"%s\" isn't a word it knows"]):format(token)
				elseif field == "always" then
					always = true
				elseif field == "target" and grid.enemy and grid.friendly then
					ticked.enemy, ticked.friendly = true, true
				elseif field ~= "never" then
					if not grid[field] then return nil, (L["\"%s\" isn't in the dropdowns"]):format(token) end
					ticked[field] = true
				end
			end
		end
	end
	if n == 0 then return false, ticked end -- (blank: nothing ticked, so never)
	if n % 2 == 0 then return nil, L["it isn't finished"] end
	-- (Brackets matched, or the rules can't read it either.)
	local _, err = ns.CompileRule(text)
	if err then return nil, err end
	return always, ticked
end

-- A button with a down arrow at its right (in both menu looks), small text
-- at the left: what a dropdown has ticked. The arrow greys while disabled.
function ns.GridMenuButton(parent, width)
	local button = ns.PanelButton(parent)
	button:SetSize(width, 20)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetWordWrap(false)
	button:SetFontString(text)
	button:SetNormalFontObject("GameFontHighlightSmall")
	button:SetDisabledFontObject("GameFontDisableSmall")
	text:ClearAllPoints()
	text:SetPoint("LEFT", 6, 0)
	text:SetPoint("RIGHT", -16, 0)
	text:SetJustifyH("LEFT")
	local arrow = button:CreateTexture(nil, "OVERLAY")
	arrow:SetSize(14, 14)
	arrow:SetPoint("RIGHT", -2, -2)
	arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	button:HookScript("OnDisable", function() arrow:SetDesaturated(true) arrow:SetAlpha(0.4) end)
	button:HookScript("OnEnable", function() arrow:SetDesaturated(false) arrow:SetAlpha(1) end)
	return button
end

-- A menu of entries ({ text, isOn(), toggle(), enabled() or nil, tip or nil })
-- under owner, with All (or Clear, once all are ticked) at the top, unless
-- plain; kept open for ticking more. changed(): after any tick. Nil where
-- the client has no menus (MenuUtil): ns.GRID_MENUS says so.
ns.GRID_MENUS = MenuUtil and MenuUtil.CreateContextMenu and true or false
function ns.TickMenu(owner, entries, changed, plain)
	if not ns.GRID_MENUS then return end
	local keep = MenuResponse and MenuResponse.Refresh
	local function Usable(entry) return not entry[4] or entry[4]() end
	local function AllOn()
		for _, entry in ipairs(entries) do
			if Usable(entry) and not entry[2]() then return false end
		end
		return true
	end
	ns.ContextMenu(owner, function(_, root)
		if not plain then
			local top = root:CreateButton(AllOn() and L["Clear"] or L["All"], function()
				local on = not AllOn()
				for _, entry in ipairs(entries) do
					if Usable(entry) and entry[2]() ~= on then entry[3]() end
				end
				changed()
				return keep
			end)
			-- (Its text again each time the menu refreshes, as ticks change it.)
			if top and top.AddInitializer then
				top:AddInitializer(function(button)
					local text = button.fontString or (button.GetFontString and button:GetFontString())
					if text then text:SetText(AllOn() and L["Clear"] or L["All"]) end
				end)
			end
			root:CreateDivider()
		end
		for _, entry in ipairs(entries) do
			local box = root:CreateCheckbox(entry[1], entry[2], function()
				entry[3]()
				changed()
				return keep
			end)
			if box and entry[4] and box.SetEnabled then box:SetEnabled(entry[4]()) end
			if box and entry[5] and box.SetTooltip then
				box:SetTooltip(function(tooltip) tooltip:AddLine(entry[5], 1, 1, 1, true) end)
			end
		end
	end)
end

-- The rule editor: one window, for one row at a time. target: { label, the
-- row's name; Text(), its rule now (the ticks' while it has none);
-- SetText(text), as it's typed; Close(text), as it closes (back into the
-- dropdowns if it reads, else kept as the row's rule); ResetToGrid(), drop
-- the rule for the ticks it had; grid, the words its dropdowns hold: nil for
-- a row without (a nameplate row, a unit frame part), whose rule just stays;
-- follow (nil: none): { key, the row's; choices() the rows it may follow, as
-- { key, label }; leader(), the one it follows; set(key), nil for none } }.
-- Built the first time.
local editor, target
local EDIT_W = 560

local function BuildEditor()
	local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
	editor = CreateFrame("Frame", "CinematicRuleEditor", UIParent, BACKDROP)
	editor:SetWidth(EDIT_W)
	if editor.SetBackdrop then
		editor:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
	end
	ns.SkinWindow(editor)
	editor:SetPoint("CENTER")
	editor:SetFrameStrata("DIALOG")
	editor:SetToplevel(true)
	editor:SetClampedToScreen(true)
	editor:EnableMouse(true)
	ns.DockBeside(editor, "ruleEditor")
	tinsert(UISpecialFrames, "CinematicRuleEditor") -- (Escape closes it)
	local close = ns.SkinClose(CreateFrame("Button", nil, editor, "UIPanelCloseButton"))
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() editor:Hide() end)
	local heading = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOP", 0, -10)
	heading:SetWidth(EDIT_W - 220) -- (clear of Pop out)

	-- The rule, a few lines' room; a click anywhere on it types there.
	local well = CreateFrame("Frame", nil, editor, BACKDROP)
	well:SetPoint("TOPLEFT", 14, -34)
	well:SetSize(EDIT_W - 28, 64)
	if well.SetBackdrop then
		well:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		well:SetBackdropColor(0, 0, 0, 0.8)
	end
	ns.SkinWindow(well, true)
	local box = CreateFrame("EditBox", nil, well)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	-- (It fills the well, so a click anywhere on it lands on the box itself.)
	box:SetPoint("TOPLEFT", 6, -6)
	box:SetPoint("BOTTOMRIGHT", -6, 6)
	box:EnableMouse(true)
	box:SetMaxLetters(255)
	-- (The words in their colours: a coloured copy in the same font and width
	-- drawn over the box's own text, a frame level up. The box's text stays
	-- seen, grey: on Forever its cursor takes the text's colour, and a clear
	-- text left the cursor unseen.)
	local over = CreateFrame("Frame", nil, well)
	over:SetAllPoints(well)
	over:SetFrameLevel(box:GetFrameLevel() + 2)
	local colored = over:CreateFontString(nil, "OVERLAY")
	colored:SetFontObject(ChatFontNormal)
	colored:SetPoint("TOPLEFT", box, "TOPLEFT")
	colored:SetWidth(EDIT_W - 40)
	colored:SetJustifyH("LEFT")
	colored:SetJustifyV("TOP")
	colored:SetWordWrap(true)
	box:SetTextColor(0.8, 0.8, 0.8, 1)
	box:SetShadowColor(0, 0, 0, 0)
	local function Recolor() colored:SetText(ns.ColoredRule(box:GetText())) end
	-- (It has the keys from the start: Escape here closes the editor, as Done does.)
	box:SetScript("OnEscapePressed", function() editor:Hide() end)
	well:EnableMouse(true)
	well:SetScript("OnMouseDown", function() box:SetFocus() end)
	-- (A faint gold wash while it takes your typing.)
	local typing = well:CreateTexture(nil, "BACKGROUND", nil, 7)
	typing:SetPoint("TOPLEFT", 3, -3)
	typing:SetPoint("BOTTOMRIGHT", -3, 3)
	typing:SetColorTexture(1, 0.82, 0, 0.12)
	typing:Hide()
	box:SetScript("OnEditFocusGained", function() typing:Show() end)
	box:SetScript("OnEditFocusLost", function() typing:Hide() end)
	local reads = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	reads:SetPoint("TOPLEFT", well, "BOTTOMLEFT", 2, -6)
	reads:SetWidth(EDIT_W - 32)
	reads:SetJustifyH("LEFT")
	local now = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	now:SetPoint("TOPLEFT", reads, "BOTTOMLEFT", 0, -4)
	now:SetWidth(EDIT_W - 32)
	now:SetJustifyH("LEFT")

	local Refresh
	local function Changed()
		if target then target.SetText(box:GetText()) end
		Refresh()
	end
	box:SetScript("OnTextChanged", function(_, userInput)
		Recolor()
		if userInput then Changed() end
	end)
	-- A piece in at the cursor, spaced from what's either side.
	local function Insert(word)
		local text, pos = box:GetText(), box:GetCursorPosition()
		local before, after = text:sub(1, pos), text:sub(pos + 1)
		local lead = (before == "" or before:find("[%s(]$") or word == ")") and "" or " "
		local trail = (word ~= "(" and after:find("^[%w_(]")) and " " or ""
		box:SetText(before .. lead .. word .. trail .. after)
		box:SetCursorPosition(#before + #lead + #word)
		box:SetFocus()
		Changed()
	end
	-- Undo: the piece before the cursor (a word, or a bracket or sign).
	local function Undo()
		local text, pos = box:GetText(), box:GetCursorPosition()
		local before, after = text:sub(1, pos):gsub("%s+$", ""), text:sub(pos + 1)
		local shorter = before:gsub("[%w_]+$", "")
		if shorter == before then shorter = before:sub(1, -2) end
		shorter = shorter:gsub("%s+$", "")
		box:SetText(shorter .. after)
		box:SetCursorPosition(#shorter)
		box:SetFocus()
		Changed()
	end

	-- The pieces, a line each in its colour; a green dot: true where you are now.
	local palette = CreateFrame("Frame", nil, editor)
	palette:SetPoint("TOPLEFT", now, "BOTTOMLEFT", -2, -12)
	palette:SetWidth(EDIT_W - 28)
	local LINE_X, DOT_ROOM = 70, 12
	local px, py = LINE_X, 0
	local wordButtons = {}
	local function Piece(text, onClick, color, dotted)
		local button = ns.PanelButton(palette)
		button:SetHeight(20)
		local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button:SetFontString(label)
		button:SetText(Colored(color, text))
		button:SetWidth(label:GetStringWidth() + 16 + (dotted and DOT_ROOM or 0))
		label:ClearAllPoints()
		label:SetPoint("CENTER", dotted and -DOT_ROOM / 2 or 0, 0)
		button:SetSkinEdge(color[1], color[2], color[3], 0.45)
		if dotted then
			button.dot = button:CreateTexture(nil, "OVERLAY")
			button.dot:SetSize(10, 10)
			button.dot:SetPoint("RIGHT", -5, 0)
			button.dot:SetTexture("Interface\\COMMON\\Indicator-Green")
			button.dot:Hide()
		end
		if px > LINE_X and px + button:GetWidth() > EDIT_W - 28 then
			px, py = LINE_X, py - 24
		end
		button:SetPoint("TOPLEFT", palette, "TOPLEFT", px, py)
		px = px + button:GetWidth() + 4
		button:SetScript("OnClick", onClick)
		return button
	end
	local GOLD = { 1, 0.82, 0 }
	-- (The Tooltip line's name and buttons, and the palette's height without it.)
	local tipLine, heightWithout = {}, nil
	for g, group in ipairs(ns.RulePieces()) do
		if group.tooltipOnly then heightWithout = -py + 22 end
		if g > 1 then px, py = LINE_X, py - 26 end
		local name = palette:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		if group.tooltipOnly then tipLine[#tipLine + 1] = name end
		name:SetText(group[1])
		name:SetTextColor(group[2][1], group[2][2], group[2][3])
		name:SetPoint("TOPLEFT", palette, "TOPLEFT", 0, py - 6)
		for _, piece in ipairs(group[3]) do
			local word = piece[1]
			local field = ns.RULE_WORDS[word]
			local button
			if piece.pick then
				-- (A menu of words: the one picked goes in.)
				button = Piece(piece[2], function(self)
					ns.ContextMenu(self, function(_, root)
						for _, picked in ipairs(piece.pick) do
							root:CreateButton(picked[2], function() Insert(picked[1]) end)
						end
					end)
				end, group[2], false)
				Tip(button, L["Picks one camera: true while that one's running."])
			else
				button = Piece(piece[2], function() Insert(word) end, group[2], field ~= nil)
			end
			if group.tooltipOnly then tipLine[#tipLine + 1] = button end
			if field and group.tooltipOnly then
				wordButtons[word] = button
				Tip(button, (L["Adds \"%s\": true for a tooltip of this kind (one can be more than one: a quest mob " ..
					"is an enemy too). Anything else: none of the others, and every tooltip of the UI."]):format(word))
			elseif field then
				wordButtons[word] = button
				local tip = (L["Adds \"%s\". A green dot: true where you are now."]):format(word)
				if field:find("^range") then
					-- (What it measures with here, as you look.)
					Tip(button, function()
						return L["True while your target is in reach of this spell, however close."] .. "\n\n"
							.. ns.RangeBandInfo(field)
					end)
				elseif field == "near" or field == "near28" then
					Tip(button, tip .. "\n\n" .. L["In fights the game won't say how far anyone is: it stays as it " ..
						"was for the same target, and is false for a new one. Spell range is measured in fights too."])
				elseif field == "elite11" or field == "elite28" then
					Tip(button, tip .. "\n\n" .. L["In fights the game won't say how far anyone is: it stays as it was " ..
						"as the fight began, while an elite enemy still has a nameplate."])
				elseif field == "enemy" or field == "friendly" or field == "target" then
					Tip(button, tip .. "\n\n" .. L["Out of fights only, as the dropdowns' target ticks: in a fight, In " ..
						"combat decides. For your target in a fight, use the kinds (Hostile NPCs, Enemy players...)."])
				else
					Tip(button, tip)
				end
			end
		end
		if g == 1 then
			-- (Undo and Clear at the end of the Logic line, a little apart.)
			px = px + 16
			Tip(Piece(L["Undo"], Undo, GOLD), L["Takes off the piece before the cursor."])
			Tip(Piece(L["Clear"], function()
				box:SetText("")
				box:SetFocus()
				Changed()
			end, GOLD), L["Empties the rule."])
		end
	end
	local heightWith = -py + 22
	heightWithout = heightWithout or heightWith
	-- Shows the Tooltip line or not, the editor's height to match.
	local function ShowTipLine(shown)
		for _, widget in ipairs(tipLine) do widget:SetShown(shown) end
		palette:SetHeight(shown and heightWith or heightWithout)
		editor:SetHeight(34 + 64 + 6 + 32 + 12 + palette:GetHeight() + 50)
	end
	palette:SetHeight(heightWith)

	-- Along the bottom: Reset to grid (when it can't go back by itself), Done.
	local done = ns.PanelButton(editor)
	done:SetSize(90, 22)
	done:SetPoint("BOTTOMRIGHT", -14, 12)
	done:SetText(L["Done"])
	done:SetScript("OnClick", function() editor:Hide() end)
	if done.SetMotionScriptsWhileDisabled then done:SetMotionScriptsWhileDisabled(true) end -- (its tip says why)
	Tip(done, function()
		if not done:IsEnabled() then
			return L["The rule isn't finished. Finish it, or close with X or Escape to put back the rule it had."]
		end
		return target and not target.grid and L["Closes the editor, keeping the rule."]
			or L["Closes the editor. A rule that's just the dropdowns' words joined by OR goes back into them; " ..
			"one that isn't stays the row's rule."]
	end)
	local resetGrid = ns.PanelButton(editor)
	resetGrid:SetSize(130, 22)
	resetGrid:SetPoint("BOTTOMLEFT", 14, 12)
	resetGrid:SetText(L["Reset to grid"])
	resetGrid:SetScript("OnClick", function()
		if target then target.ResetToGrid() end
		target = nil -- (nothing to put back as it closes)
		editor:Hide()
	end)
	Tip(resetGrid, L["Drops the rule: the row's dropdowns decide again, ticked as they were before."])
	-- Follow a row: a menu of the row's table's others (those that follow it
	-- greyed: no loops). Picking one closes the editor, the rule as it was.
	local followButton = ns.PanelButton(editor)
	followButton:SetSize(120, 22)
	followButton:SetPoint("RIGHT", done, "LEFT", -8, 0)
	followButton:SetText(L["Follow a row"])
	followButton:SetScript("OnClick", function(self)
		local follow = target and target.follow
		if not follow then return end
		ns.ContextMenu(self, function(_, root)
			root:CreateTitle(L["Follow another row"])
			root:CreateRadio(L["None: its own settings"], function() return not follow.leader() end, function()
				follow.set(nil)
			end)
			root:CreateDivider()
			for _, choice in ipairs(follow.choices()) do
				local key = choice[1]
				if key ~= follow.key then
					local loops = ns.FollowKey(key) == follow.key
					local radio = root:CreateRadio(choice[2] .. (loops and " " .. L["(follows this one)"] or ""),
						function() return follow.leader() == key end, function()
							follow.set(key)
							target = nil -- (its rule left as it was)
							editor:Hide()
						end)
					if loops and radio and radio.SetEnabled then radio:SetEnabled(false) end
				end
			end
		end)
	end)
	Tip(followButton, L["Instead of a rule, this row shows whenever another row of its table does, however that " ..
		"one is set now or later. All or nothing: none of this row's own settings count while it follows, and " ..
		"they're kept for when it stops (Grid on the row)."])
	editor:SetHeight(34 + 64 + 6 + 32 + 12 + palette:GetHeight() + 50)

	function Refresh()
		if not target then return end
		local text = box:GetText()
		local grid = target.grid
		local isAlways, why
		if grid then isAlways, why = ns.ReadGridRule(text, grid) end
		resetGrid:SetShown(grid ~= nil and isAlways == nil)
		followButton:SetShown(target.follow ~= nil)
		-- (Only a rule that reads, or none, can be kept.)
		done:SetEnabled(not text:find("%S") or ns.CompileRule(text) ~= nil)
		reads:SetShown(grid ~= nil)
		reads:SetText(not grid and "" or isAlways ~= nil and "|cff60ff60" .. L["Goes back into the dropdowns as you close it."] .. "|r"
			or "|cffffd100" .. (L["Stays the row's rule (it can't go in the dropdowns: %s)."]):format(why) .. "|r")
		local facts = ns.db and ns.RuleFactsFor and ns.RuleFactsFor(target.key)
		for word, button in pairs(wordButtons) do
			button.dot:SetShown(facts and facts[ns.RULE_WORDS[word]] and true or false)
		end
		if not facts then
			now:SetText("")
			return
		end
		local test, err = ns.CompileRule(text)
		if not text:find("%S") then
			now:SetText(grid and "|cffffd100" .. L["Blank: never shown."] .. "|r"
				or "|cff999999" .. L["Empty: its ticks decide."] .. "|r")
		elseif not test then
			now:SetText("|cffff6060" .. (L["Not finished: %s. Closing now puts back the rule it had."]):format(err) .. "|r")
		else
			now:SetText(test(facts) and "|cff60ff60" .. L["Right now: shown"] .. "|r"
				or "|cffffd100" .. L["Right now: hidden"] .. "|r")
		end
	end
	local since = 0
	ns.SetOnUpdate(editor, function(_, elapsed)
		since = since + elapsed
		if since > 0.5 then
			since = 0
			Refresh()
		end
	end)
	-- (Closed any way: Done, X, Escape or the settings going.)
	editor:SetScript("OnHide", function()
		box:ClearFocus()
		local closing = target
		target = nil
		if closing then closing.Close(box:GetText()) end
	end)
	editor.Open = function(newTarget)
		target = newTarget
		ShowTipLine(newTarget.key ~= nil and newTarget.key:find("^tooltip:") ~= nil)
		heading:SetText((L["Rule: %s"]):format(newTarget.label))
		local text = newTarget.Text()
		box:SetText(text)
		editor:Show()
		box:SetFocus()
		box:SetCursorPosition(#text)
		Refresh()
	end
end

-- Opens the editor for a row (see target above); another row's, open,
-- closes first (its rule kept or back in its dropdowns).
function ns.OpenRuleEditor(newTarget)
	if not editor then BuildEditor() end
	if editor:IsShown() then editor:Hide() end
	editor.Open(newTarget)
end
-- Closes it (the settings going).
function ns.CloseRuleEditor()
	if editor then editor:Hide() end
end

-- Whether key's a raid-style party frames' row, which follows the raid
-- frames' on purpose. (Frames.lua loads after this: looked up when asked.)
local function RaidStyleFollower(key)
	for _, partyKey in pairs(ns.RAID_STYLE_PARTY or {}) do
		if partyKey == key then return true end
	end
	return false
end

-- The rule word for each column's list (FRAME_COLUMNS' third field).
local LIST_WORD = { combatShow = "combat", enemyShow = "enemy", friendlyShow = "friendly", bgShow = "bg",
	worldShow = "world", cityShow = "city", groupShow = "group", instanceShow = "instance" }
-- The words a list row's dropdowns hold, for ns.ReadGridRule.
local GRID = { calm = true } -- (calm: the Combat dropdown's Calm Timer, calmShow)
for _, word in pairs(LIST_WORD) do GRID[word] = true end

-- The dropdowns, by number (a grid has some of them: ns.GRID_COMBAT...),
-- each in its colour (as the editor has them), and what its tip says.
local MENU_GROUPS = {
	{ heading = "Combat", color = { 1, 0.45, 0.4 }, help = "Shown while you're in a fight." },
	{ heading = "Target", color = { 1, 0.65, 0.25 }, help = "Shown while you have one of these targeted." },
	{ heading = "Location", color = { 0.45, 0.75, 1 },
		help = "Shown the whole time while you're in any of these (Grouped: in a party or raid)." },
}
ns.GRID_COMBAT, ns.GRID_TARGET, ns.GRID_LOCATION = 1, 2, 3
-- Which dropdown each list's in (the rest: Location).
local LIST_GROUP = { combatShow = 1, enemyShow = 2, friendlyShow = 2 }
local FOLLOW_COLOR = { 0.79, 0.73, 1 }
-- The targets' names in a menu (the rest are their columns').
local MENU_NAMES = { combatShow = "In combat", enemyShow = "Enemy targeted", friendlyShow = "Friend targeted" }

-- Across a row, from the label's end: Always, the dropdowns, Edit.
local ALWAYS_W, MENU_W, RULE_W, GAP = 46, 96, 40, 2
-- The dot at the end of a row's name (room kept for it in the label).
ns.GRID_DOT_ROOM = 18

-- What a dropdown says: -, the one ticked, All or how many.
local function Summary(names, total, color)
	if #names == 0 then return "|cff808080-|r" end
	if #names == 1 then return Colored(color, names[1]) end
	if #names == total then return Colored(color, L["All"]) end
	return Colored(color, (L["%d of %d"]):format(#names, total))
end

-- Where a grid's columns go across a row, labelWidth in. layout: { groups,
-- the dropdowns it has ({ 1, 2, 3 } when nil); always = false: no Always
-- column; edit: that column }.
local function Columns(layout)
	local x, cols = 0, { menus = {} }
	if layout.always ~= false then
		cols.always = x
		x = x + ALWAYS_W + GAP
	end
	for _, g in ipairs(layout.groups or { 1, 2, 3 }) do
		cols.menus[g] = x
		x = x + MENU_W + GAP
	end
	cols.menusEnd = x
	if layout.edit then
		cols.edit = x
		x = x + RULE_W
	end
	cols.width = x
	return cols
end
-- How wide a grid's columns are (the label's not counted).
function ns.GridWidth(layout) return Columns(layout).width end

-- The headings over a grid's columns: at top's top left, labelWidth in
-- (kit.FrameHeading's height, kit.headingHeight). Gives them, to show and hide.
function ns.GridHeadings(kit, parent, top, labelWidth, layout)
	local cols, made = Columns(layout), {}
	local function Heading(text, x, width, color)
		local heading = kit.FrameHeading(parent, text)
		heading:SetWidth(width)
		heading:SetPoint("TOPLEFT", top, "TOPLEFT", labelWidth + x, 0)
		if color then heading:SetTextColor(color[1], color[2], color[3]) end
		made[#made + 1] = heading
	end
	if cols.always then Heading(layout.alwaysHeading or L["Always"], cols.always, ALWAYS_W) end
	for g, group in ipairs(MENU_GROUPS) do
		if cols.menus[g] then Heading(L[group.heading], cols.menus[g], MENU_W, group.color) end
	end
	if cols.edit then Heading(L["Edit"], cols.edit, RULE_W) end
	return made
end

-- A text button the width of the dropdowns, for the row's rule in their place.
local function RuleButton(row, width)
	local button = ns.PanelButton(row)
	button:SetSize(width, 20)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetWordWrap(false)
	button:SetFontString(text)
	text:ClearAllPoints()
	text:SetPoint("LEFT", 6, 0)
	text:SetPoint("RIGHT", -6, 0)
	text:SetJustifyH("LEFT")
	return button
end

-- One row of a grid, in a frame the caller places with its label (drawn by
-- the caller, labelWidth wide, to the row's left). kit: the page helpers
-- (Options.lua's Tooltip, Refresh, controls, RecordKey...). spec:
--   always = { isOn(), set(value), tip } (nil: an empty cell);
--   menus = { [dropdown] = { { name, isOn(), toggle(), usable() or nil, tip }... } };
--   follow = { key(), choices() giving { { key, label }... }: the rows it
--     may follow, picked in the rule editor } (nil: none): following one, it
--     shows "Follows <row>" where its rule would be, and shows as that row does;
--   rule = { key(), label(), grid (the dropdowns' words, for ns.ReadGridRule;
--     nil: a rule just stays), words(), apply(always, ticked), changed(key) } (nil: no Edit);
--   enabled() (nil: usable): whether its client has it and the like;
--   cells() (nil: "full"): "full", "always" (just Always) or "none" (a row reused);
--   changed(): after any change; band: its number (every other one lighter,
--     the band across the label too);
--   dot = true: a dot at the label's end, green while it'd show now (from its
--     rule, else liveRule(): its ticks as a rule, for a row whose ticks aren't
--     the rules' words, else its rule.grid words).
-- The row's Refresh and SetEnabled are the page's (it goes in kit.controls).
function ns.GridRow(kit, parent, labelWidth, layout, spec)
	local cols = Columns(layout)
	local Tooltip, Refresh = kit.Tooltip, kit.Refresh
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(cols.width, 24)
	local function Changed()
		if spec.changed then spec.changed() end
		Refresh()
	end
	local rule = spec.rule
	local function RuleKey() return rule and rule.key() end
	local function RuleOf(key)
		local rules = key and ns.GetDB().frameRules
		local text = rules and rules[key]
		return type(text) == "string" and text:find("%S") and text or nil
	end
	local function Rule() return RuleOf(RuleKey()) end
	local function SetRule(text)
		local db = ns.GetDB()
		db.frameRules = db.frameRules or {}
		-- (A row with a default rule: cleared is "", else the default comes
		-- back as the settings are next set up: Core's EnsureTables.)
		if text == nil and ns.RULE_DEFAULTS[RuleKey()] then text = "" end
		db.frameRules[RuleKey()] = text
		if rule.changed then rule.changed(RuleKey()) end
	end
	local function AlwaysOn() return spec.always and spec.always.isOn() and true or false end

	-- (row:SetBand(n): its number again, for a row laid out afresh.)
	if spec.band then
		local band = row:CreateTexture(nil, "BACKGROUND", nil, -8)
		band:SetPoint("TOPLEFT", row, "TOPLEFT", -labelWidth, 1)
		band:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -1)
		function row:SetBand(n) band:SetColorTexture(1, 1, 1, n % 2 == 1 and 0.05 or 0.02) end
		row:SetBand(spec.band)
	end
	local live
	if spec.dot then
		live = row:CreateTexture(nil, "OVERLAY")
		live:SetSize(10, 10)
		live:SetPoint("RIGHT", row, "LEFT", -6, 0)
		local hover = CreateFrame("Frame", nil, row)
		hover:SetSize(16, 16)
		hover:SetPoint("CENTER", live, "CENTER")
		hover:EnableMouse(true)
		Tooltip(hover, L["Green: it'd show in CineMode right now. Grey: it'd be hidden. None: its rule isn't finished."])
	end

	local always
	if spec.always and cols.always then
		always = ns.SkinCheck(CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate"))
		always:SetSize(26, 26)
		always:SetPoint("LEFT", cols.always + (ALWAYS_W - 26) / 2, 0)
		always:SetScript("OnClick", function(self)
			spec.always.set(self:GetChecked() and true or false)
			Changed()
		end)
		Tooltip(always, spec.always.tip)
	end

	-- The dropdowns, each its items' ticks.
	local menus = {}
	for g, group in ipairs(MENU_GROUPS) do
		local entries = spec.menus and spec.menus[g]
		if cols.menus[g] and entries and #entries > 0 then
			local color, heading, help = group.color, L[group.heading], spec.help and spec.help[g] or L[group.help]
			local button = ns.GridMenuButton(row, MENU_W)
			button:SetPoint("LEFT", cols.menus[g], 0)
			button:SetSkinEdge(color[1], color[2], color[3], 0.45)
			button:SetScript("OnClick", function(self) ns.TickMenu(self, entries, Changed) end)
			button.Refresh = function(self)
				local on = {}
				for _, entry in ipairs(entries) do
					if entry[2]() then on[#on + 1] = entry[1] end
				end
				self:SetText(Summary(on, #entries, color))
				self.tip = #on > 0 and table.concat(on, ", ") or L["Nothing ticked"]
			end
			button:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(heading, 1, 1, 1)
				GameTooltip:AddLine(self.tip, color[1], color[2], color[3], true)
				GameTooltip:AddLine(help, 0.8, 0.8, 0.8, true)
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			menus[#menus + 1] = button
		end
	end

	-- The row it follows (db.rowFollow), picked in the rule editor: all of
	-- that row's settings, none of its own (kept for when it stops).
	local function Leader() return spec.follow and ns.GetDB().rowFollow[spec.follow.key()] end
	local function LeaderLabel(key)
		for _, choice in ipairs(spec.follow.choices()) do
			if choice[1] == key then return choice[2] end
		end
		return key
	end
	local function SetLeader(key)
		ns.GetDB().rowFollow[spec.follow.key()] = key
		Changed()
	end

	-- The rule: in text mode, shown where Always and the dropdowns were (a
	-- click opens the editor), its edge red while it doesn't read (the
	-- ticks decide then); Edit opens the editor, Grid puts it back.
	local ruleText, edit
	if rule and cols.edit then
		ruleText = RuleButton(row, cols.menusEnd - GAP)
		ruleText:SetPoint("LEFT", 0, 0)
		local function Target()
			local before = Rule()
			-- (No rule yet: its dropdowns' or ticks' words to start from; none ticked, blank.)
			local ticksRule = not rule.grid and spec.liveRule and spec.liveRule()
			local start = before or (rule.grid and (AlwaysOn() or #rule.words() > 0)
				and ns.GridRule(AlwaysOn(), rule.words())) or (rule.grid and "")
				or (ticksRule ~= "never" and ticksRule) or ""
			return { label = rule.label(), grid = rule.grid, key = RuleKey(),
				Text = function() return start end,
				SetText = function(typed) SetRule(typed) Refresh() end,
				Close = function(typed)
					-- (A rule that doesn't read never stays: back to the one it had, or its grid.)
					if typed:find("%S") and not ns.CompileRule(typed) then
						SetRule(before and ns.CompileRule(before) and before or nil)
						Changed()
						return
					end
					local isAlways, ticked
					if rule.grid then isAlways, ticked = ns.ReadGridRule(typed, rule.grid) end
					if isAlways ~= nil then
						-- (Unchanged and never a rule: nothing to write.)
						if before or typed ~= start then rule.apply(isAlways, ticked) end
						SetRule(nil)
					elseif not before and typed == start then
						SetRule(nil) -- (its ticks' words, untouched: the ticks keep deciding)
					else
						SetRule(typed:find("%S") and typed or nil)
					end
					Changed()
				end,
				ResetToGrid = function() SetRule(nil) Changed() end,
				follow = spec.follow and ns.GRID_MENUS and { key = spec.follow.key(), choices = spec.follow.choices,
					leader = Leader, set = SetLeader } or nil,
			}
		end
		ruleText:SetScript("OnClick", function() ns.OpenRuleEditor(Target()) end)
		ruleText:SetScript("OnEnter", function(self)
			if Leader() then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(L["Follow"], FOLLOW_COLOR[1], FOLLOW_COLOR[2], FOLLOW_COLOR[3])
				GameTooltip:AddLine((L["Follows %s: shows when it does. Its own settings are kept for when it stops."])
					:format(LeaderLabel(Leader())), 1, 1, 1, true)
				GameTooltip:AddLine(L["Click to open the editor."], 0.8, 0.8, 0.8, true)
				GameTooltip:Show()
				return
			end
			local text = Rule() or ""
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L["Rule"], 1, 1, 1)
			GameTooltip:AddLine(ns.ColoredRule(text), 1, 1, 1, true)
			local _, err = ns.CompileRule(text)
			if err then
				GameTooltip:AddLine((rule.grid and L["Not finished: %s. The dropdowns decide until it is."]
					or L["Not finished: %s. Its ticks decide until it is."]):format(err), 1, 0.38, 0.38, true)
			end
			GameTooltip:AddLine(L["Click to open the editor."], 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)
		ruleText:SetScript("OnLeave", GameTooltip_Hide)

		edit = ns.PanelButton(row)
		edit:SetSize(RULE_W, 20)
		edit:SetPoint("LEFT", cols.edit, 0)
		edit:SetNormalFontObject("GameFontHighlightSmall")
		edit:SetDisabledFontObject("GameFontDisableSmall")
		if edit.SetMotionScriptsWhileDisabled then edit:SetMotionScriptsWhileDisabled(true) end -- (its tip says why)
		edit:SetScript("OnClick", function()
			local text = Rule()
			if Leader() then
				SetLeader(nil) -- (its own settings again)
			elseif not text then
				ns.OpenRuleEditor(Target())
			elseif rule.grid then
				Target().Close(text) -- (back into the dropdowns, as the editor would)
			else
				SetRule(nil) -- (its ticks again)
				Changed()
			end
		end)
		edit:SetScript("OnEnter", function(self)
			local text = Rule()
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if Leader() then
				GameTooltip:SetText(L["Back to its own settings"], 1, 1, 1)
				GameTooltip:AddLine(L["Stops following: its own ticks or rule, as they were, decide again."],
					0.8, 0.8, 0.8, true)
			elseif not text then
				GameTooltip:SetText(L["Edit as a rule"], 1, 1, 1)
				if rule.grid then
					GameTooltip:AddLine(ns.ColoredRule(ns.GridRule(AlwaysOn(), rule.words())), 1, 1, 1, true)
				elseif spec.liveRule then
					GameTooltip:AddLine(ns.ColoredRule(spec.liveRule()), 1, 1, 1, true)
				end
				GameTooltip:AddLine(L["Opens the rule editor, for AND, NOT and more places and situations " ..
					"than the dropdowns have."], 0.8, 0.8, 0.8, true)
			elseif rule.grid then
				local _, why = ns.ReadGridRule(text, rule.grid)
				GameTooltip:SetText(L["Back to the dropdowns"], 1, 1, 1)
				GameTooltip:AddLine(why and (L["Can't: %s. Open the rule to change it, or Reset to grid there."])
					:format(why) or L["Puts the rule's words back in the dropdowns."], 0.8, 0.8, 0.8, true)
			else
				GameTooltip:SetText(L["Back to the ticks"], 1, 1, 1)
				GameTooltip:AddLine(L["Drops the rule: its ticks, as they were, decide again."], 0.8, 0.8, 0.8, true)
			end
			GameTooltip:Show()
		end)
		edit:SetScript("OnLeave", GameTooltip_Hide)
	end

	-- The dot: what its rule (or its ticks, as one) gives where you are now.
	local function Live()
		if not live then return end
		local key = RuleKey()
		local facts = ns.db and ns.RuleFactsFor and ns.RuleFactsFor(key)
		local text = RuleOf(key and ns.FollowKey(key)) or (spec.liveRule and spec.liveRule())
			or (rule and rule.grid and ns.GridRule(AlwaysOn(), rule.words()))
		local test = facts and text and ns.CompileRule(text)
		if not test then
			live:Hide()
			return
		end
		local shows = test(facts)
		live:SetTexture(shows and "Interface\\COMMON\\Indicator-Green" or "Interface\\COMMON\\Indicator-Gray")
		live:Show()
	end
	row.Live = Live

	-- Shows the row as its settings are. (Refresh and SetEnabled both call
	-- this, never each other: a section's wrapper of Refresh may end in
	-- SetEnabled(false), so that would loop.)
	local function Paint()
		if not ns.GetDB() then return end
		local cells = spec.cells and spec.cells() or "full"
		local full = cells == "full"
		local enabled = row.enabled ~= false and (not spec.enabled or spec.enabled())
		local text = full and Rule()
		-- (Following a row: "Follows <row>" in the rule's place.)
		local leader = full and Leader()
		local on = AlwaysOn()
		if always then
			always:SetShown(cells ~= "none" and not text and not leader)
			always:SetChecked(on)
			always:SetEnabled(enabled)
		end
		for _, menu in ipairs(menus) do
			menu:SetShown(full and not text and not leader)
			menu:Refresh()
			menu:SetEnabled(enabled and not on)
			-- (Greyed, faded whole, edge and all: plainly out of play while Always is ticked.)
			menu:SetAlpha((enabled and not on) and 1 or 0.35)
		end
		if ruleText then
			ruleText:SetShown((text or leader) and true or false)
			ruleText:SetEnabled(enabled)
			if leader then
				ruleText:SetText(Colored(FOLLOW_COLOR, (L["Follows %s"]):format(LeaderLabel(leader))))
				ruleText:SetSkinTint(nil)
			elseif text then
				ruleText:SetText(ns.ColoredRule(text))
				ruleText:SetSkinTint(not ns.CompileRule(text) and 1 or nil, 0.45, 0.45)
			end
			edit:SetShown(full)
			edit:SetText((text or leader) and L["Grid"] or L["Edit"])
			edit:SetEnabled(enabled and (leader or not text or not rule.grid or ns.ReadGridRule(text, rule.grid) ~= nil)
				and true or false)
		end
		if live then
			if full then Live() else live:Hide() end
		end
	end
	-- (spec.override: words for a row something else decides, the Style hub's
	-- Overrides tab: they stand in for its ticks, a click away from the tab.)
	local note
	local function PaintRow()
		Paint()
		local text = spec.override and spec.override()
		if not (text or note) then return end
		if not note then
			note = CreateFrame("Button", nil, row)
			note:SetPoint("TOPLEFT")
			note:SetPoint("BOTTOMRIGHT")
			note.label = note:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			note.label:SetPoint("LEFT", 6, 0)
			note:SetScript("OnClick", function() ns.OpenOptions("Style Overrides") end)
			Tooltip(note, L["Set on the Style hub's Overrides tab. Click to open it."])
		end
		for _, child in ipairs({ row:GetChildren() }) do
			if child ~= note then child:SetShown(not text) end
		end
		note:SetShown(text and true or false)
		note.label:SetText(text or "")
	end
	function row:Refresh() PaintRow() end
	function row:SetEnabled(enabled)
		self.enabled = enabled and true or false
		PaintRow()
	end
	kit.controls[#kit.controls + 1] = row
	return row
end

-- The rows' dots kept up while parent shows (every half second).
function ns.GridDots(parent, rows)
	local ticker = CreateFrame("Frame", nil, parent)
	local since = 0
	ns.SetOnUpdate(ticker, function(_, elapsed)
		since = since + elapsed
		if since < 0.5 then return end
		since = 0
		for _, row in ipairs(rows) do
			if row:IsVisible() then row.Live() end
		end
	end)
end

-- The spec parts for a row kept in the shared lists (the Standard Frames
-- page's columns: the frames tables', the supported addons', custom
-- frames', and the Show in rows that were Turn off in grids): Key() its key
-- (a function, for rows reused), columns (from the second: FRAME_COLUMNS),
-- columnTips (nil: the columns' own), setAlways. Gives menus, words, apply
-- for ns.GridRow. A tick here gives the rows that follow this one
-- (ns.ROW_FALLBACK: the pet frame the player frame's) its old tick of their
-- own first, so only this row changes. Combat holds three times, each a
-- tick of its own: In combat, Calm Timer (calmShow: after a fight, till it's
-- run out) and Out of combat (quietShow: the rest). opts (nil: none):
--   quiet, cam: Out of combat (quietShow) and In a camera mode (camShow) in Combat too;
--   anyFight: its In combat in any fight (not greyed while CineMode doesn't stay on in them);
--   omit: lists left out (list -> true: In combat, the targets, a place);
--   calmItem: in place of the Calm Timer, a menu entry of its own (cameras' wait).
function ns.ListRowParts(Key, columns, columnTips, setAlways, opts)
	opts = opts or {}
	local omit = opts.omit or {}
	local function KeepFollowers(list, isOn)
		local db, key = ns.GetDB(), Key()
		for follower, leader in pairs(ns.ROW_FALLBACK or {}) do
			if leader == key and db[list][follower] == nil and not RaidStyleFollower(follower) then
				db[list][follower] = isOn(follower) and true or false
			end
		end
	end
	local function Ticked(c) return columns[c][2](Key()) and true or false end
	local function SetTick(c, value)
		KeepFollowers(columns[c][3], columns[c][2])
		ns.GetDB()[columns[c][3]][Key()] = value
	end
	-- (The lists that aren't columns: Calm Timer, Out of combat, In a camera mode.)
	local EXTRA_ON = { calmShow = ns.IsCalmShowOn, quietShow = ns.IsQuietShowOn, camShow = ns.IsCamShowOn }
	local function ExtraOn(list) return EXTRA_ON[list](Key()) and true or false end
	local function SetExtra(list, value)
		KeepFollowers(list, EXTRA_ON[list])
		ns.GetDB()[list][Key()] = value
	end
	local combatColumn
	for c = 2, #columns do
		if columns[c][3] == "combatShow" and not omit.combatShow then combatColumn = c end
	end
	local stays = function() return ns.GetDB().stayInCombat and true or false end

	local menus = { {}, {}, {} }
	for c = 2, #columns do
		local column = columns[c]
		local list = column[3]
		if not omit[list] then
			local name = MENU_NAMES[list] and L[MENU_NAMES[list]] or column[1]
			local tip = columnTips and columnTips[c] or column[5]
			-- (In combat only counts while CineMode stays on in fights, for the UI's rows.)
			local needsStay = column[4] and not opts.anyFight
			if needsStay then
				tip = (tip and tip .. " " or "") .. L["(Only while Combat is unticked under Turn off in, " ..
					"on the main page: CineMode stays on in fights.)"]
			end
			local group = menus[LIST_GROUP[list] or 3]
			group[#group + 1] = { name, function() return Ticked(c) end, function() SetTick(c, not Ticked(c)) end,
				needsStay and stays or nil, tip }
			-- (Combat's Calm Timer: the time after a fight, till it's run out.)
			if c == combatColumn then
				if opts.calmItem then
					group[#group + 1] = opts.calmItem
				else
					group[#group + 1] = { L["Calm Timer"], function() return ExtraOn("calmShow") end,
						function() SetExtra("calmShow", not ExtraOn("calmShow")) end, nil,
						L["On after a fight, until the Calm Timer (CineMode page) has run out. With In combat too: " ..
						"the fight, then that."] }
				end
				if opts.quiet then
					group[#group + 1] = { L["Out of combat"], function() return ExtraOn("quietShow") end,
						function() SetExtra("quietShow", not ExtraOn("quietShow")) end, nil,
						L["On out of fights, once the Calm Timer after one has run out. With Calm Timer too: as soon " ..
						"as a fight ends."] }
				end
				if opts.cam then
					group[#group + 1] = { L["In a camera mode"], function() return ExtraOn("camShow") end,
						function() SetExtra("camShow", not ExtraOn("camShow")) end, nil,
						L["On while a camera mode runs (flights, AFK, cozy and the rest)."] }
				end
			end
		end
	end
	-- (A Combat dropdown with no In combat: Calm Timer's item, and the others.)
	if not combatColumn then
		local group = menus[1]
		if opts.calmItem then group[#group + 1] = opts.calmItem end
		if opts.quiet then
			group[#group + 1] = { L["Out of combat"], function() return ExtraOn("quietShow") end,
				function() SetExtra("quietShow", not ExtraOn("quietShow")) end, nil,
				L["On out of fights, once the Calm Timer after one has run out. With Calm Timer too: as soon " ..
				"as a fight ends."] }
		end
		if opts.cam then
			group[#group + 1] = { L["In a camera mode"], function() return ExtraOn("camShow") end,
				function() SetExtra("camShow", not ExtraOn("camShow")) end, nil,
				L["On while a camera mode runs (flights, AFK, cozy and the rest)."] }
		end
	end
	-- (A row's own items at the Combat dropdown's end: opts.combatItems, each
	-- { name, isOn(), toggle(), usable() or nil, tip }. Not words of the
	-- row's rule: the row reads them itself.)
	for _, item in ipairs(opts.combatItems or {}) do
		menus[1][#menus[1] + 1] = item
	end
	local function Words()
		local words = {}
		for c = 2, #columns do
			if not omit[columns[c][3]] and Ticked(c) then words[#words + 1] = LIST_WORD[columns[c][3]] end
			if c == combatColumn and not opts.calmItem and ExtraOn("calmShow") then words[#words + 1] = "calm" end
		end
		if opts.quiet and ExtraOn("quietShow") then words[#words + 1] = "nocombat" end
		if opts.cam and ExtraOn("camShow") then words[#words + 1] = "camera" end
		return words
	end
	local function Apply(isAlways, ticked)
		if setAlways then setAlways(isAlways) end
		for c = 2, #columns do
			if not omit[columns[c][3]] then SetTick(c, ticked[LIST_WORD[columns[c][3]]] and true or false) end
		end
		if combatColumn and not opts.calmItem then SetExtra("calmShow", ticked.calm and true or false) end
		if opts.quiet then SetExtra("quietShow", ticked.nocombat and true or false) end
		if opts.cam then SetExtra("camShow", ticked.camera and true or false) end
	end
	-- (The words this row's dropdowns hold, for reading a rule back into them.)
	local grid = {}
	for word in pairs(GRID) do grid[word] = true end
	if omit.combatShow or opts.calmItem then grid.calm = nil end
	for list in pairs(omit) do
		if LIST_WORD[list] then grid[LIST_WORD[list]] = nil end
	end
	grid.nocombat = opts.quiet or nil
	grid.camera = opts.cam or nil
	return { menus = menus, words = Words, apply = Apply, grid = grid, keepFollowers = KeepFollowers }
end

-- The Standard Frames table, a row per item, as dropdowns (ShowTable does
-- the rest: its kit is the page helpers it shares). Returns the last row's
-- label, to place what comes below.
function ns.GridTable(content, columnTop, rows, kit)
	local LABEL_WIDTH, ROW_HEIGHT, COLUMNS = kit.labelWidth, kit.rowHeight, kit.columns
	local LAYOUT = { edit = true }
	-- (The rows a row may follow: the table's others.)
	local choices = {}
	for _, item in ipairs(rows) do
		if not item.alwaysOnly then choices[#choices + 1] = { item.key, item.label } end
	end
	local function Choices() return choices end
	if not rows.noHeadings then
		ns.GridHeadings(kit, content, columnTop, LABEL_WIDTH, LAYOUT)
	end

	local made = {}
	local lastLabel = columnTop
	for r, item in ipairs(rows) do
		local y = -kit.headingHeight - 4 - (r - 1) * ROW_HEIGHT
		local rowLabel = kit.Label(content, "GameFontHighlight", item.label)
		rowLabel:SetPoint("TOPLEFT", columnTop, "TOPLEFT", 0, y - 5)
		rowLabel:SetWidth(LABEL_WIDTH - 4 - ns.GRID_DOT_ROOM)
		rowLabel:SetJustifyH("LEFT")
		rowLabel:SetWordWrap(false)
		kit.ShowBox(content, item, rowLabel) -- (its frame on at all: item.showKey)
		-- A » to its page on rows that have a page of their own.
		if item.morePage then ns.MoreLink(content, rowLabel, item.morePage) end
		ns.LabelHover(content, rowLabel, item.tip)
		if ns.CINE_SHOW_SETTING[item.key] then
			kit.RecordKey(content, ns.CINE_SHOW_SETTING[item.key]) -- (for the page's Reset)
		end
		for c, column in ipairs(item.alwaysOnly and { COLUMNS[1] } or COLUMNS) do
			if c > 1 or not item.setAlways then
				kit.RecordKey(content, column[3])
				kit.RecordRow(content, column[3], item.key)
			end
		end
		if item.alwaysKey then kit.RecordKey(content, item.alwaysKey) end
		for _, key in ipairs(item.recordKeys or {}) do kit.RecordKey(content, key) end
		local opts = {}
		for k, v in pairs(rows.opts or {}) do opts[k] = v end
		for k, v in pairs(item.opts or {}) do opts[k] = v end
		if not item.alwaysOnly then
			-- (frameRules too: its rule. Left out, Reset page kept a row's rule.)
			for _, list in ipairs({ "calmShow", "quietShow", "camShow", "rowFollow", "frameRules" }) do
				kit.RecordKey(content, list)
				kit.RecordRow(content, list, item.key)
			end
		end

		local function Key() return item.key end
		local alwaysOn = item.alwaysOn or ns.IsCineShowOn
		local parts
		local function SetAlways(value)
			local setting = ns.CINE_SHOW_SETTING[item.key]
			if item.setAlways then
				item.setAlways(value)
			elseif setting then
				ns.GetDB()[setting] = value
			else
				parts.keepFollowers("cineShow", ns.IsCineShowOn)
				ns.GetDB().cineShow[item.key] = value
			end
		end
		parts = ns.ListRowParts(Key, COLUMNS, rows.columnTips, SetAlways, opts)
		local spec = {
			band = r, dot = not item.alwaysOnly,
			always = { isOn = function() return alwaysOn(item.key) end, set = SetAlways,
				tip = item.alwaysTip or item.part
				and L["Show it whenever its frame shows. This overrides its Hover groups: untick it to " ..
				"hide it in CineMode except when hovered or brought up by the other columns."]
				or L["Show it all through CineMode, instead of hiding it. (The other columns then have nothing to add.)"] },
			changed = item.apply,
			enabled = item.showKey and function() return kit.RowShown(item) end or nil,
		}
		if not item.alwaysOnly then
			spec.menus = parts.menus
			spec.follow = { key = Key, choices = Choices }
			spec.rule = { key = Key, label = function() return item.label end, grid = parts.grid,
				words = parts.words, apply = parts.apply }
		end
		local row = ns.GridRow(kit, content, LABEL_WIDTH, LAYOUT, spec)
		row.debugName = item.label -- (for the dev copy's page timing)
		row:SetPoint("TOPLEFT", columnTop, "TOPLEFT", LABEL_WIDTH, y)
		made[#made + 1] = row
		lastLabel = rowLabel
	end
	ns.GridDots(content, made)
	return lastLabel
end

-- A list of rows that open into drawers, as the Scenes page's: each row its
-- tick, its name and chips (what's set apart from the usual, as many as fit;
-- the row's tooltip lists them all), and a + to open its drawer under it, a
-- line each (its name at the left, its controls after, At places them). kit:
-- the page's (ns.lowHealthKit), parent: its content. items, in order: { id,
-- label, tip, on = the tick's setting, onTip, chips = function() giving
-- { { text, color }... }, dim = function() true: the row greyed (its name and
-- chips), lines = { { name, build = function(drawer, At) } ... } }; At(control,
-- x, dy) puts control on that line, x past the line's name (LABEL_W in).
-- Gives the list, as tall as its rows and open drawers (anchor what's below to
-- its bottom), and list:Open(id).
ns.ROW_CHIP = {
	plain = { 0.18, 0.18, 0.18, 0.8, 0.8, 0.8 },     -- (back r, g, b, then text r, g, b)
	when = { 0.08, 0.2, 0.35, 0.55, 0.8, 1 },
	never = { 0.35, 0.25, 0.05, 1, 0.8, 0.35 },
	gold = { 0.29, 0.24, 0.03, 1, 0.88, 0.4 },
	mine = { 0.18, 0.29, 0.11, 0.73, 0.89, 0.54 },
}
local LIST_ROW_W, LIST_ROW_H, LIST_ON_X, LIST_NAME_X, LIST_NAME_W, LIST_CHIPS_X, LIST_CHIPS_W =
	590, 28, 16, 46, 206, 256, 300
local LIST_DRAWER_X, LIST_LINE_H, LIST_LABEL_W = 20, 34, 62
ns.ROW_LIST_LABEL_W = LIST_LABEL_W
function ns.RowList(kit, parent, items)
	local list = CreateFrame("Frame", nil, parent)
	list:SetSize(LIST_ROW_W, LIST_ROW_H)
	local rows, drawers, opened, titles = {}, {}, {}, {}
	local function Layout()
		local y, lastGroup, g, band = 0, nil, 0, 0
		for i, item in ipairs(items) do
			local row, drawer = rows[i], drawers[i]
			-- (A title over each group's rows, as the emote page's moments: item.group.)
			if item.group and item.group ~= lastGroup then
				lastGroup, g, band = item.group, g + 1, 0
				if g > 1 then y = y + 10 end
				local title = titles[g] or kit.Label(list, "GameFontNormal", "")
				titles[g] = title
				title:SetText(item.group)
				title:ClearAllPoints()
				title:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -y)
				title.searchSkip = true
				title:Show()
				y = y + 20
			end
			band = band + 1
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
			row.band:SetColorTexture(1, 1, 1, band % 2 == 1 and 0.04 or 0)
			y = y + LIST_ROW_H
			row.toggle:SetNormalTexture(opened[item.id] and "Interface\\Buttons\\UI-MinusButton-Up"
				or "Interface\\Buttons\\UI-PlusButton-Up")
			-- (A closed drawer's settings still count for page search, which opens it.)
			drawer.searchAlways = true
			if opened[item.id] then
				drawer:ClearAllPoints()
				drawer:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_DRAWER_X, -y)
				drawer:Show()
				y = y + drawer:GetHeight() + 4
			else
				drawer:Hide()
			end
		end
		list:SetHeight(math.max(y, 1))
	end
	local function Toggle(id)
		opened[id] = not opened[id]
		Layout()
	end
	for i, item in ipairs(items) do
		local row = CreateFrame("Button", nil, list)
		row:SetSize(LIST_ROW_W, LIST_ROW_H)
		rows[i] = row
		row.band = row:CreateTexture(nil, "BACKGROUND", nil, -8)
		row.band:SetAllPoints()
		local hover = row:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.05)
		local edge = row:CreateTexture(nil, "BACKGROUND")
		edge:SetPoint("BOTTOMLEFT")
		edge:SetPoint("BOTTOMRIGHT")
		edge:SetHeight(1)
		edge:SetColorTexture(1, 1, 1, 0.08)
		row:SetScript("OnClick", function() Toggle(item.id) end)
		local function Place(control, x)
			control:SetPoint("LEFT", row, "LEFT", x, 0)
			return control
		end

		-- Its tick.
		local on = Place(kit.Check(row, item.on, "", item.onTip, function(value)
			ns.GetDB()[item.on] = value
			kit.Refresh()
		end), LIST_ON_X)
		on.searchLabel = item.label
		kit.RecordKey(parent, item.on)

		-- Its name, and its chips (dimmed while it's greyed).
		local name = Place(kit.Label(row, "GameFontHighlight", item.label), LIST_NAME_X)
		name:SetWidth(LIST_NAME_W)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		name.searchSkip = true
		local chips = Place(CreateFrame("Frame", nil, row), LIST_CHIPS_X)
		chips:SetSize(LIST_CHIPS_W, 16)
		chips.searchSkip = true
		chips.pageSwitch = false
		chips.pool = {}
		chips.Refresh = function()
			local made = item.chips and item.chips() or {}
			row.chipList = made
			local x, shown = 0, 0
			for c, each in ipairs(made) do
				local chip = chips.pool[c]
				if not chip then
					chip = CreateFrame("Frame", nil, chips)
					chip:SetHeight(16)
					chip.back = chip:CreateTexture(nil, "BACKGROUND")
					chip.back:SetAllPoints()
					chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					chip.text:SetPoint("CENTER")
					chips.pool[c] = chip
				end
				chip.text:SetText(each[1])
				local width = math.ceil(chip.text:GetStringWidth()) + 10
				if x + width > LIST_CHIPS_W then break end
				local color = each[2] or ns.ROW_CHIP.plain
				chip.back:SetColorTexture(color[1], color[2], color[3], 0.9)
				chip.text:SetTextColor(color[4], color[5], color[6])
				chip:SetWidth(width)
				chip:ClearAllPoints()
				chip:SetPoint("LEFT", chips, "LEFT", x, 0)
				chip:Show()
				x, shown = x + width + 4, c
			end
			for c = shown + 1, #chips.pool do chips.pool[c]:Hide() end
			local dim = item.dim and item.dim() and 0.5 or 1
			name:SetAlpha(dim)
			chips:SetAlpha(dim)
		end
		kit.AddControl(chips)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(item.label, 1, 1, 1)
			if item.tip then GameTooltip:AddLine(item.tip, 0.8, 0.8, 0.8, true) end
			for _, chip in ipairs(self.chipList or {}) do
				GameTooltip:AddLine("- " .. chip[1], 1, 0.82, 0)
			end
			GameTooltip:AddLine(ns.L["Click to show or hide its settings."], 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row.toggle = Place(CreateFrame("Button", nil, row), LIST_ROW_W - 22)
		row.toggle:SetSize(14, 14)
		row.toggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		row.toggle:SetScript("OnClick", function() Toggle(item.id) end)
		kit.Tooltip(row.toggle, ns.L["Show or hide this row's settings."])

		-- Its drawer: a line each, its name at the left.
		local lines = item.lines or {}
		local drawer = CreateFrame("Frame", nil, list)
		drawer:SetSize(LIST_ROW_W - LIST_DRAWER_X, #lines * LIST_LINE_H + 8)
		drawer:Hide()
		drawer.openSection = function()
			opened[item.id] = true
			Layout()
		end
		drawers[i] = drawer
		local back = drawer:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0, 0, 0, 0.3)
		for l, line in ipairs(lines) do
			local middle = -4 - (l - 0.5) * LIST_LINE_H
			local label = kit.Label(drawer, "GameFontNormalSmall", line.name)
			label:SetPoint("LEFT", drawer, "TOPLEFT", 6, middle)
			label.searchSkip = true
			line.build(drawer, function(control, x, dy)
				control:SetPoint("LEFT", drawer, "TOPLEFT", x or LIST_LABEL_W, middle + (dy or 0))
				return control
			end)
		end
	end
	list.pageSwitch = false
	list.Refresh = function() Layout() end
	kit.AddControl(list)
	function list:Open(id)
		opened[id] = true
		Layout()
	end
	Layout()
	return list
end
