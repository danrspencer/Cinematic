-- Lines-only chat peeks only with the game's own chat (offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/chatdefault.lua < /dev/null
-- With EllesmereUI's chat, "Show just those messages" put our copy of a new
-- line under the window's own line, which EllesmereUI keeps showing: two
-- lines (2026-11-20). Now the copies are made only while chat is the game's
-- own: no addon claims the chat window (EllesmereUI, ElvUI, Glass) and
-- Chattynator isn't loaded. Else a message brings up the window as without
-- the setting. Says PASS or FAIL per check.

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

local ns = dofile("Tools/offline/load.lua")("forever", "CinematicDev.toc")
ns.db.chatPeekLinesOnly = true
local switch = "handleChat" -- (and every switch above it: off on a fresh install)
while switch do
	ns.db[switch] = true
	switch = ns.PageSwitchOf(switch)
end
local IsLoaded = C_AddOns.IsAddOnLoaded

Check("1 game's own chat: default", ns.ChatIsDefault() == true)
Check("1 game's own chat: lines only", ns.ChatPeekLinesOnly() == true)
ns.db.chatPeekLinesOnly = false
Check("1 setting off: no lines only", ns.ChatPeekLinesOnly() == false)
ns.db.chatPeekLinesOnly = true

C_AddOns.IsAddOnLoaded = function(name) return name == "Chattynator" end -- luacheck: ignore 122
Check("2 Chattynator: not default", ns.ChatIsDefault() == false)
Check("2 Chattynator: no lines only (window peeks)", ns.ChatPeekLinesOnly() == false)
C_AddOns.IsAddOnLoaded = IsLoaded -- luacheck: ignore 122
Check("2 back to default", ns.ChatPeekLinesOnly() == true)

-- EllesmereUI's chat (Support/EllesmereUI.lua): its panel claims the window.
ns.ClaimLinkPart("EllesmereUI", "chatwindow", {}, { window = {} })
Check("3 EllesmereUI chat: not default", ns.ChatIsDefault() == false)
Check("3 EllesmereUI chat: no lines only (window peeks)", ns.ChatPeekLinesOnly() == false)
Check("3 setting kept for later", ns.db.chatPeekLinesOnly == true)

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
