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

local function Trim(stack)
	if type(stack) ~= "string" then return nil end
	stack = stack:gsub("Interface[/\\]AddOns[/\\]", "")
	local lines = {}
	for line in stack:gmatch("[^\n]+") do
		lines[#lines + 1] = "      " .. line
		if #lines >= STACK_LINES then break end
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
		for i, other in ipairs(entries) do -- (to the top)
			if other == entry then table.remove(entries, i) break end
		end
	else
		entry = { kind = kind, message = message, count = 1, time = time(),
			stack = Trim(stack), source = Source(message, stack) }
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
function ns.DevTap(kind, message, stack)
	if busy then return end
	busy = true
	if kind == "error" then lastHandler.message, lastHandler.at = message, GetTime() end
	pcall(Add, kind, message, stack)
	busy = false
end

ns.DevErrorWindow = {} -- (BugGrabber's callback owner)

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
		ns.DevTap(event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked",
			("%s: %s %s"):format(Plain(a), Plain(b), InCombatLockdown() and "(in combat)" or "(out of combat)"),
			debugstack and debugstack(2, 8, 0))
	end
end)

-- /cine debug errors: open it by hand.
function ns.DevErrorWindowShow()
	window = window or CreateWindow()
	window:Show()
	Render()
end
