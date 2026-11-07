-- Cinematic: suggestions while typing /cine in the chat box. A list over the
-- chat box of the commands that fit what's typed, the ones you use most first
-- (counted for the account: CinematicDB.slashUsage), then the help's own.
-- Up/Down picks one (its text goes in the box: Enter runs it), Tab or a click
-- fills it in and shows what can follow it. On/off: the main page's
-- Command Suggestions (slashComplete).
local _, ns = ...

local MAX_ROWS = 8
local MAX_KEPT = 60     -- (commands remembered; the least used go first)
local MAX_LENGTH = 48   -- (longer ones aren't remembered: pasted text)
local ROW_HEIGHT = 18
local FADE_DAYS = 30    -- (a command unused this long counts half)
-- Before you've used any: the ones worth knowing first.
local POPULAR = { "config", "why", "keys", "hideui", "find", "profile", "behind", "flyby", "selftest", "log" }

local function Usage()
	local db = CinematicDB
	if type(db) ~= "table" then return nil end
	if type(db.slashUsage) ~= "table" then db.slashUsage = {} end
	return db.slashUsage
end

-- "  Debug   Zoom " -> "debug zoom"
local function Normalize(msg)
	if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return nil end
	msg = msg:lower():gsub("%s+", " "):match("^ ?(.-) ?$")
	return msg
end

local function Score(entry, now)
	local days = math.max(0, (now - (entry.t or now)) / 86400)
	return (entry.n or 0) / (1 + days / FADE_DAYS)
end

-- Counts a command that ran (Slash.lua: known ones only, not typos).
function ns.RecordSlashUse(msg)
	local cmd = Normalize(msg)
	if not cmd or cmd == "" or #cmd > MAX_LENGTH then return end
	local usage = Usage()
	if not usage then return end
	local now = time()
	local entry = usage[cmd]
	if type(entry) ~= "table" then entry = {}; usage[cmd] = entry end
	entry.n, entry.t = (entry.n or 0) + 1, now
	-- Too many: the least used goes.
	local count, worst, worstScore = 0, nil, nil
	for key, each in pairs(usage) do
		count = count + 1
		local score = type(each) == "table" and Score(each, now) or -1
		if not worstScore or score < worstScore then worst, worstScore = key, score end
	end
	if count > MAX_KEPT and worst ~= cmd then usage[worst] = nil end
end

-- The help's commands as { fill = "find ", shown = "find <words>", text, order }:
-- fill is what goes in the box, up to the first <...> or [...].
local function HelpCommands()
	local list, seen = {}, {}
	local popular = {}
	for i, word in ipairs(POPULAR) do popular[word] = i end
	for i, each in ipairs(ns.SlashHelpList and ns.SlashHelpList() or {}) do
		local shown = each.command:gsub("^/cine ?", ""):gsub("||", "|")
		local fill = shown:match("^(.-)%s*[<%[]") or shown
		fill = fill:match("^(.-)%s*$")
		if fill ~= "" and not seen[fill] then
			seen[fill] = true
			list[#list + 1] = {
				fill = fill, shown = shown, text = each.text,
				order = popular[fill] or (#POPULAR + i),
				takesMore = shown ~= fill,
			}
		end
	end
	return list
end

-- What fits typed (what's after "/cine "), best first.
local function Suggestions(typed)
	local now, result, byFill = time(), {}, {}
	local help = HelpCommands()
	for _, each in ipairs(help) do byFill[each.fill] = each end
	local usage = Usage() or {}
	for cmd, entry in pairs(usage) do
		if type(entry) == "table" and cmd ~= typed and cmd:sub(1, #typed) == typed then
			local known = byFill[cmd]
			result[#result + 1] = {
				fill = cmd, shown = known and known.shown or cmd, text = known and known.text,
				score = Score(entry, now), order = known and known.order or 1000,
				takesMore = known and known.takesMore,
			}
			byFill[cmd] = false -- (listed: not again below)
		end
	end
	for _, each in ipairs(help) do
		if byFill[each.fill] and each.fill ~= typed and each.fill:sub(1, #typed) == typed then
			result[#result + 1] = {
				fill = each.fill, shown = each.shown, text = each.text,
				score = 0, order = each.order, takesMore = each.takesMore,
			}
		end
	end
	table.sort(result, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		if a.order ~= b.order then return a.order < b.order end
		return a.fill < b.fill
	end)
	for i = #result, MAX_ROWS + 1, -1 do result[i] = nil end
	return result
end

-- The list: over the chat box, the best match at the bottom, next to it.
local list, rows = nil, {}
local box          -- (the chat box it's showing for)
local slash        -- ("/cine" or "/cinematic", as typed)
local typed = ""   -- (what you typed after it, before picking with the arrows)
local shown = {}   -- (the suggestions in the rows: 1 = bottom)
local picked = 0   -- (the row the arrows are on, 0 = none)
local filling      -- (set while we change the box's text ourselves)

local function Hide()
	if list then list:Hide() end
	box, picked, shown = nil, 0, {}
end

local function Highlight()
	for i, row in ipairs(rows) do row.glow:SetShown(i == picked) end
end

local function Fill(editBox, text)
	filling = true
	editBox:SetText(text)
	editBox:SetCursorPosition(#text)
	filling = nil
end

local Refresh

-- Tab or a click: the command in, and what can follow it.
local function Choose(index)
	local editBox, choice = box, shown[index]
	if not editBox or not choice then return end
	typed = choice.fill .. " "
	-- (The press on the row took the chat box's focus, and the game closed
	-- it: open again first, then the text in.)
	if not editBox:IsShown() or not editBox:HasFocus() then
		local Activate = (ChatFrameUtil and ChatFrameUtil.ActivateChat) or ChatEdit_ActivateChat
		if Activate then Activate(editBox) else editBox:Show() end
		if not editBox:HasFocus() then editBox:SetFocus() end
	end
	Fill(editBox, slash .. " " .. typed)
	Refresh(editBox)
end

local function MakeList()
	list = CreateFrame("Frame", nil, UIParent)
	list:SetFrameStrata("DIALOG")
	list:SetToplevel(true)
	list:SetClampedToScreen(true)
	list:Hide()
	local bg = list:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.04, 0.04, 0.05, 1) -- (solid: no chat showing through)
	local edge = list:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("TOPRIGHT")
	edge:SetHeight(1)
	edge:SetColorTexture(1, 0.82, 0, 0.5)
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("BOTTOMLEFT", 0, 2 + (i - 1) * ROW_HEIGHT)
		row:SetPoint("BOTTOMRIGHT", 0, 2 + (i - 1) * ROW_HEIGHT)
		row.glow = row:CreateTexture(nil, "ARTWORK")
		row.glow:SetAllPoints()
		row.glow:SetColorTexture(1, 0.82, 0, 0.18)
		row.glow:Hide()
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.command = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.command:SetPoint("LEFT", 8, 0)
		row.command:SetJustifyH("LEFT")
		row.command:SetWordWrap(false)
		row.hint = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.hint:SetPoint("LEFT", row.command, "RIGHT", 10, 0)
		row.hint:SetPoint("RIGHT", -8, 0)
		row.hint:SetJustifyH("LEFT")
		row.hint:SetWordWrap(false)
		row:RegisterForClicks("LeftButtonUp")
		row:SetScript("OnClick", function(self) ns.Guard(Choose, self.index) end)
		-- (Pressed then let go off the row: no click, so the list goes if the
		-- chat box closed meanwhile.)
		row:SetScript("OnMouseUp", function(self)
			if box and not self:IsMouseOver() and not box:HasFocus() then Hide() end
		end)
		row.index = i
		rows[i] = row
	end
end

function Refresh(editBox)
	if not ns.db or ns.db.slashComplete == false then return Hide() end
	shown = Suggestions(typed)
	if #shown == 0 then return Hide() end
	if not list then MakeList() end
	box, picked = editBox, 0
	list:ClearAllPoints()
	list:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", 0, 2)
	list:SetPoint("BOTTOMRIGHT", editBox, "TOPRIGHT", 0, 2)
	list:SetHeight(4 + #shown * ROW_HEIGHT)
	-- (The commands in one column: as wide as the widest, within reason.)
	local widest = 0
	for i, row in ipairs(rows) do
		local each = shown[i]
		row:SetShown(each ~= nil)
		if each then
			-- What you typed in gold, the rest white.
			local head, rest = each.shown:sub(1, #typed), each.shown:sub(#typed + 1)
			row.command:SetWidth(0)
			row.command:SetText("|cffffd100" .. head .. "|r" .. rest)
			widest = math.max(widest, row.command:GetStringWidth())
			row.hint:SetText(each.text or "")
		end
	end
	widest = math.min(widest + 2, (editBox:GetWidth() or 300) * 0.5)
	for _, row in ipairs(rows) do row.command:SetWidth(widest) end
	Highlight()
	list:Show()
end

-- "/cine de" -> "/cine", "de"; nil if it isn't a /cine command.
local function Split(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
	local head, rest = text:match("^%s*(/[Cc][Ii][Nn][Ee][Mm][Aa][Tt][Ii][Cc])(.*)$")
	if not head then head, rest = text:match("^%s*(/[Cc][Ii][Nn][Ee])(.*)$") end
	if not head or (rest ~= "" and not rest:find("^%s")) then return nil end
	return head, rest:lower():gsub("^%s+", ""):gsub("%s+", " ")
end

local function OnTextChanged(editBox, userInput)
	if filling then return end
	if not userInput then return Hide() end -- (history, a link put in...)
	local head, rest = Split(editBox:GetText())
	if not head then return Hide() end
	slash, typed = head:lower(), rest
	Refresh(editBox)
end

local function OnArrowPressed(editBox, key)
	if box ~= editBox or not list or not list:IsShown() then return end
	if key == "UP" then
		picked = picked >= #shown and 0 or picked + 1
	elseif key == "DOWN" then
		picked = picked <= 0 and #shown or picked - 1
	else
		return
	end
	local choice = shown[picked]
	Fill(editBox, slash .. " " .. (choice and choice.fill or typed))
	Highlight()
end

local function OnTabPressed(editBox)
	if box ~= editBox or not list or not list:IsShown() then return end
	Choose(picked > 0 and picked or 1)
end

-- (The real work protected, ns.Guard: an error is reported, not a Lua
-- error at every key.)
local function Leave(editBox)
	if box ~= editBox then return end
	-- (A press on one of its rows takes the chat box's focus: the list stays
	-- for the click, Choose.)
	for _, row in ipairs(rows) do
		if row:IsShown() and row:IsMouseOver() then return end
	end
	Hide()
end

-- The keystroke hooks: a quick look first, so typing anything that isn't a
-- slash command (with no list up) costs one byte read and no garbage.
local function QuickText(editBox, userInput)
	if filling then return end
	if not box then
		if not userInput then return end
		local text = editBox:GetText()
		if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or text:byte(1) ~= 47 then return end -- ("/")
	end
	ns.Guard(OnTextChanged, editBox, userInput)
end
local function QuickArrow(editBox, key)
	if box then ns.Guard(OnArrowPressed, editBox, key) end
end
local function QuickTab(editBox)
	if box then ns.Guard(OnTabPressed, editBox) end
end
local function QuickLeave(editBox)
	if box then Leave(editBox) end
end

local hooked = {}
local function HookBox(editBox)
	if not editBox or hooked[editBox] or not editBox.HookScript then return end
	hooked[editBox] = true
	editBox:HookScript("OnTextChanged", QuickText)
	editBox:HookScript("OnArrowPressed", QuickArrow)
	editBox:HookScript("OnTabPressed", QuickTab)
	editBox:HookScript("OnEditFocusLost", QuickLeave)
	editBox:HookScript("OnHide", QuickLeave)
	editBox:HookScript("OnEnterPressed", QuickLeave)
end

-- (Up to 40: temporary chat windows, whispers popped out, are numbered after
-- the usual ones.)
local function HookAll()
	for i = 1, 40 do HookBox(_G["ChatFrame" .. i .. "EditBox"]) end
end

local watch = CreateFrame("Frame")
watch:RegisterEvent("PLAYER_LOGIN")
watch:SetScript("OnEvent", function()
	ns.Guard(HookAll)
	if FCF_OpenTemporaryWindow then
		hooksecurefunc("FCF_OpenTemporaryWindow", function() ns.Guard(HookAll) end)
	end
end)
