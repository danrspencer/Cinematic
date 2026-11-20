-- Dev copy only: a window that pops up every time any error or warning shows,
-- from any addon or the game, even ones Cinematic otherwise drops (the
-- harmless secret-bar errors), catches in its own loops, or that BugGrabber
-- keeps quiet. Loaded first in CinematicDev.toc so it hears from the start.
-- It hangs on no frame of the game's (not UIParent), so hiding the interface
-- (CineMode, Alt+Z) doesn't hide it. /cine debug errors opens it by hand.
local _, ns = ...

local MAX_ENTRIES = 200
local STACK_LINES = 8

local entries, byKey = {}, {}
local window, busy, dirty = nil, false, false
local lastHandler = { message = nil, at = nil } -- (BugGrabber's copy of one just heard)

local function Plain(value)
	if issecretvalue and issecretvalue(value) then return "<secret>" end
	local ok, text = pcall(tostring, value)
	return ok and text or "?"
end

-- (Blocked lines keep more: who started it sits under the game's own calls,
-- 9th line or lower for Settings opening, 2026-11-19; and the stack's bottom
-- 10 lines too, where the first caller is: a list redraw in a fight was
-- 20+ game calls deep, 2026-11-20.)
local BLOCKED_STACK_LINES = 30
local function Trim(stack, kind)
	if type(stack) ~= "string" then return nil end
	stack = stack:gsub("Interface[/\\]AddOns[/\\]", "")
	local max = type(kind) == "string" and kind:find("^blocked") and BLOCKED_STACK_LINES or STACK_LINES
	local lines = {}
	for line in stack:gmatch("[^\n]+") do
		lines[#lines + 1] = "      " .. line
		if #lines >= max then break end
	end
	return #lines > 0 and table.concat(lines, "\n") or nil
end

-- Whose: the first addon folder in the message or the stack, and who tainted it.
local function Source(message, stack)
	local where = message:match("AddOns[/\\]([^/\\]+)[/\\]") or message:match("^([%w_!%-]+)[/\\][^:]+%.lua:")
		or (type(stack) == "string" and (stack:match("AddOns[/\\]([^/\\]+)[/\\]") or stack:match("([%w_!%-]+)[/\\][^:]+%.lua:")))
	local tainted = message:match("tainted by '([^']+)'")
	if tainted and tainted ~= where then
		return (where or "?") .. ", tainted by " .. tainted
	end
	return where or "?"
end

local Render

local function CreateWindow()
	-- (No parent: shows while UIParent is hidden; scaled like it by hand.)
	local frame = CreateFrame("Frame", "CinematicDevErrorWindow", nil, BackdropTemplateMixin and "BackdropTemplate")
	frame:SetSize(760, 360)
	frame:SetPoint("TOP", 0, -60)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame:SetBackdropColor(0.08, 0, 0, 0.92)
		frame:SetBackdropBorderColor(1, 0.25, 0.25, 1)
	end

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -9)
	title:SetTextColor(1, 0.35, 0.35)
	frame.title = title

	local function Button(label, width, onClick)
		local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		button:SetSize(width, 20)
		button:SetText(label)
		button:SetScript("OnClick", onClick)
		return button
	end
	local close = Button("Close", 60, function() frame:Hide() end)
	close:SetPoint("TOPRIGHT", -6, -5)
	local clear = Button("Clear", 60, function()
		wipe(entries)
		wipe(byKey)
		Render()
	end)
	clear:SetPoint("RIGHT", close, "LEFT", -4, 0)
	local select = Button("Select all", 80, function()
		frame.box:SetFocus()
		frame.box:HighlightText()
	end)
	select:SetPoint("RIGHT", clear, "LEFT", -4, 0)

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -30)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(715)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	-- (Read-only: typing puts the text back.)
	box:SetScript("OnTextChanged", function(self, user)
		if user and frame.text then self:SetText(frame.text) end
	end)
	scroll:SetScrollChild(box)
	frame.box, frame.scroll = box, scroll

	frame:SetScript("OnShow", function(self)
		local scale = UIParent and UIParent:GetEffectiveScale() or 1
		self:SetScale(scale > 0 and scale or 1)
	end)
	frame:Hide()
	return frame
end

function Render()
	dirty = false
	if not window then return end
	local lines = {}
	for i = #entries, 1, -1 do -- newest first
		local entry = entries[i]
		lines[#lines + 1] = ("|cffff6060%s|r x%d  |cffffd060%s|r  (%s)\n  %s"):format(
			date("%H:%M:%S", entry.time), entry.count, entry.kind, entry.source, entry.message)
		if entry.stack then lines[#lines + 1] = "|cff909090" .. entry.stack .. "|r" end
	end
	window.text = table.concat(lines, "\n")
	window.box:SetText(window.text)
	window.box:SetCursorPosition(0)
	window.scroll:SetVerticalScroll(0)
	window.title:SetText(("Cinematic dev: errors and warnings (%d)"):format(#entries))
end

local function Add(kind, message, stack)
	message = Plain(message)
	local key = kind .. "\0" .. message
	local entry = byKey[key]
	if entry then
		entry.count, entry.time = entry.count + 1, time()
		entry.stack = Trim(stack, kind) or entry.stack -- (the newest one's: the same line can come from new places)
		for i, other in ipairs(entries) do -- (to the top)
			if other == entry then table.remove(entries, i) break end
		end
	else
		entry = { kind = kind, message = message, count = 1, time = time(),
			stack = Trim(stack, kind), source = Source(message, stack) }
		byKey[key] = entry
		if #entries >= MAX_ENTRIES then
			local old = table.remove(entries, 1)
			for k, v in pairs(byKey) do
				if v == old then byKey[k] = nil break end
			end
		end
	end
	entries[#entries + 1] = entry
	window = window or CreateWindow()
	window:Show()
	-- (Drawn once a frame at most: errors come dozens a second in a fight.)
	if not dirty then
		dirty = true
		C_Timer.After(0, Render)
	end
end

-- Diagnostics.lua calls this from the error handler (before anything is
-- dropped), from its loops' catches and from ns.Log warnings.
-- (And each new one into the saved log once a session, stack and all, so
-- "check log" finds it after a /reload: this window keeps them in memory
-- only, 2026-11-20 (a blocked call in a fight seen here, nowhere in the log).
-- Cinematic's own errors are in the log already as ERROR lines too.)
local logged = {}
local function SaveToLog(kind, message, stack)
	local key = tostring(kind) .. "|" .. Plain(message)
	if logged[key] or not ns.Log then return end
	logged[key] = true
	local lines = Trim(stack, kind)
	ns.Log("deverror", ("%s: %s%s"):format(tostring(kind), Plain(message), lines and ("\n" .. lines) or ""))
end

function ns.DevTap(kind, message, stack)
	if busy then return end
	busy = true
	if kind == "error" then lastHandler.message, lastHandler.at = message, GetTime() end
	pcall(Add, kind, message, stack)
	pcall(SaveToLog, kind, message, stack)
	busy = false
end

ns.DevErrorWindow = {} -- (BugGrabber's callback owner)

-- How many times a kind of entry came so far, and the newest one's stack
-- (/cine debug blockedline, BlockedLineTest.lua).
function ns.DevErrorCount(kind)
	local count, stack = 0, nil
	for _, entry in ipairs(entries) do
		if entry.kind == kind then count, stack = count + entry.count, entry.stack end
	end
	return count, stack
end

-- BugGrabber (when it owns the error handler, ours may never be called).
local grabbed = false
local function UseBugGrabber()
	local grabber = _G.BugGrabber
	if grabbed or not (grabber and grabber.RegisterCallback) then return end
	grabbed = true
	grabber.RegisterCallback(ns.DevErrorWindow, "BugGrabber_BugGrabbed", function(_, err)
		if not err then return end
		-- (Already heard through the handler this very moment.)
		if lastHandler.at == GetTime() and lastHandler.message == err.message then return end
		ns.DevTap("error (BugGrabber)", err.message, err.stack)
	end)
	-- This session's earlier ones, grabbed before we were listening.
	local ok, db = pcall(grabber.GetDB, grabber)
	local session = grabber.GetSessionId and select(2, pcall(grabber.GetSessionId, grabber))
	if ok and type(db) == "table" then
		for _, err in ipairs(db) do
			if err.session == session then ns.DevTap("error (BugGrabber, earlier)", err.message, err.stack) end
		end
	end
end
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "MACRO_ACTION_BLOCKED",
	"MACRO_ACTION_FORBIDDEN", "LUA_WARNING", "ADDON_LOADED", "PLAYER_LOGIN" }) do
	pcall(watcher.RegisterEvent, watcher, event) -- (not every client has every one)
end
watcher:SetScript("OnEvent", function(_, event, a, b)
	if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
		UseBugGrabber()
	elseif event == "LUA_WARNING" then
		ns.DevTap("warning", b or a)
	else
		watcher.blockedAt = GetTime()
		ns.DevTap(event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked",
			("%s: %s %s"):format(Plain(a), Plain(b), InCombatLockdown() and "(in combat)" or "(out of combat)"),
			debugstack and debugstack(2, 8, 0))
	end
end)

-- The yellow "Interface action failed because of an AddOn" line can come with
-- no ADDON_ACTION_BLOCKED event at all (Forever: the gamepad SmartNavigation
-- focus call blocked when Settings is opened from addon code), so the events
-- above miss it. The game always goes through DisplayInterfaceActionBlockedMessage
-- for that line, even when it prints it only once a session: hook it and keep
-- the stack. Skipped when a blocked event already came this frame (that one
-- calls it too, and is already in the box).
local displayAt
if type(_G.DisplayInterfaceActionBlockedMessage) == "function" then
	hooksecurefunc("DisplayInterfaceActionBlockedMessage", function()
		local at = GetTime()
		displayAt = at
		local stack = debugstack and debugstack(2, 18, 10)
		local fight = InCombatLockdown() and "(in combat)" or "(out of combat)"
		C_Timer.After(0, function()
			if watcher.blockedAt == at then return end
			ns.DevTap("blocked (no event)", "Interface action failed line, " .. fight, stack)
		end)
	end)
end

-- And the line itself, straight from the chat windows: in case it reaches chat
-- some other way than the function above (nothing else in the box then). The
-- game prints it before that function's hook runs, so this waits a frame and
-- skips lines the hook or a blocked event already put in the box. Old copies
-- chat history restore puts back at login (UI/ChatCopy.lua, ns.chatRestoring)
-- are skipped.
local BLOCKED_TEXT = type(_G.INTERFACE_ACTION_BLOCKED) == "string" and _G.INTERFACE_ACTION_BLOCKED
	or "Interface action failed because of an AddOn"
local chatAt
local function OnChatLine(_, text)
	if ns.chatRestoring or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
	if not text:find(BLOCKED_TEXT, 1, true) then return end
	local at = GetTime()
	if chatAt == at then return end -- (the same line in another chat window)
	chatAt = at
	local stack = debugstack and debugstack(2, 18, 10)
	local fight = InCombatLockdown() and "(in combat)" or "(out of combat)"
	C_Timer.After(0, function()
		if displayAt == at or watcher.blockedAt == at then return end
		ns.DevTap("blocked (chat line only)", "Interface action failed line in chat, " .. fight, stack)
	end)
end
for i = 1, (NUM_CHAT_WINDOWS or 10) do
	local frame = _G["ChatFrame" .. i]
	if frame and frame.AddMessage then hooksecurefunc(frame, "AddMessage", OnChatLine) end
end
-- /cine debug errors: open it by hand.
function ns.DevErrorWindowShow()
	window = window or CreateWindow()
	window:Show()
	Render()
end
