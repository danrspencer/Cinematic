-- Cinematic: Glass Forever, a chat addon. It keeps the game's chat tabs
-- (ChatFrame1Tab...) and input boxes (ChatFrame1EditBox...) and fades them
-- itself, holding their alpha with SetAlpha hooks of its own. The Chat page
-- setting them too fought over that alpha, and they stayed invisible (issue
-- #8): with Glass loaded they're left to it. The tab bar they sit in
-- (GeneralDockManager) still fades with the chat, as without Glass: Glass
-- fades it by showing and hiding it, never by its alpha, so the tabs go
-- with the chat.
--
-- It draws each chat window's lines on a frame of its own (an unnamed scroll
-- frame inside GlassFrame, .chatFrame its window), not in the window, so
-- fading the window left them up: those fade with the Chat window row, and
-- are linked as each window's panel (FrameLinks.lua) so a message the Chat
-- page lets through still brings them up. A window dragged out of Glass's
-- dock is the game's again (its Glass frame hidden) and fades as usual.
local _, ns = ...
local L = ns.L

-- Advanced Frames page (no columns: it follows the Chat page).
table.insert(ns.ADDON_NOTES, {
	addon = "Glass", label = "Glass Forever",
	works = L["Follows the Chat page"],
	about = L["Glass's chat lines and tab bar fade with the Chat page, and a message brings them up where " ..
		"the Chat page says. Glass fades each chat tab and the input box itself, so the Chat page leaves " ..
		"those alone while it's on."],
})

-- Glass shows and hides the tab bar with alpha animations (0 to 1 to show it
-- for a party or guild line, 1 to 0 to hide it), and an animation's alpha
-- wins over the frame's own while it plays: the bar flashed up through our
-- fade for a second. While the Chat page has it faded, its show animation
-- stops at once (the bar stays at our alpha), and its hide hides it at once.
-- (Glass's own animations, made once its chat is set up: hooked when found.)
local function OurDockAlpha(dock)
	for _, entry in ipairs(ns.managed) do
		if entry.frame == dock then return entry.alpha or 1 end
	end
	return 1
end

local dockHooked = false
local function HookDockFades()
	local dock = _G.GeneralDockManager
	if dockHooked or type(dock) ~= "table" or type(dock.showAg) ~= "table" or type(dock.hideAg) ~= "table"
		or type(dock.QuickHide) ~= "function" then
		return
	end
	dockHooked = true
	hooksecurefunc(dock.showAg, "Play", function(group)
		if OurDockAlpha(dock) < 0.99 then group:Stop() end
	end)
	hooksecurefunc(dock.hideAg, "Play", function(group)
		if OurDockAlpha(dock) < 0.99 then
			group:Stop()
			pcall(dock.QuickHide, dock)
		end
	end)
end

local function FindLines()
	HookDockFades()
	local container = _G.GlassFrame
	if type(container) ~= "table" or not container.GetChildren then return end
	for _, frame in ipairs({ container:GetChildren() }) do
		local window = frame.chatFrame
		if type(window) == "table" and not (frame.IsForbidden and frame:IsForbidden())
			and type(window.GetName) == "function" and (window:GetName() or ""):match("^ChatFrame%d+$") then
			if not ns.IsFaded(frame) then
				ns.AddFoundFrame(frame, "chat", true, true)
			end
			ns.ClaimLinkPart("Glass", "chatwindow", frame, { window = window })
		end
	end
end

ns.WhenAddonLoads("Glass", function()
	local names = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		names[#names + 1] = "ChatFrame" .. i .. "Tab"
		names[#names + 1] = "ChatFrame" .. i .. "EditBox"
	end
	ns.LeaveAlone(names)
	ns.AddScanner(FindLines)
end)
