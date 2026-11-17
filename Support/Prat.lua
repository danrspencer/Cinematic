-- Cinematic: Prat 3.0, a chat addon. It keeps the game's chat windows, tabs,
-- input boxes and buttons, so the Chat page fades them as without it. Two of
-- its modules (both off until the player turns them on) set alpha the Chat
-- page sets too:
--  - Chat Tabs sets each tab's alpha (active and inactive) and fades the tabs
--    itself on mouseover: with it on, the tabs are left to it, as with Glass.
--  - Original Buttons sets the chat menu button's alpha from its slider: with
--    it on, the button's alpha is followed.
-- Its modules are switched on at login, so a change to either takes a /reload
-- to be seen here.
local _, ns = ...
local L = ns.L

-- Advanced Frames page (no columns: it follows the Chat page).
table.insert(ns.ADDON_NOTES, {
	addon = "Prat-3.0", label = "Prat 3.0",
	works = L["Follows the Chat page"],
	about = L["Prat's chat windows fade with the Chat page."],
})

local function ModuleOn(prat, name)
	local addon = type(prat) == "table" and prat.Addon
	if type(addon) ~= "table" or type(addon.GetModule) ~= "function" then return false end
	local module = addon:GetModule(name, true)
	return type(module) == "table" and type(module.IsEnabled) == "function" and module:IsEnabled() or false
end

ns.WhenAddonLoads("Prat-3.0", function()
	-- (Its modules are switched on after login: looked at once the world's up.)
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		local prat = _G.Prat
		if ModuleOn(prat, "ChatTabs") then
			local names = {}
			for i = 1, (NUM_CHAT_WINDOWS or 10) do
				names[#names + 1] = "ChatFrame" .. i .. "Tab"
			end
			ns.LeaveAlone(names)
			ns.Log("support", "Prat Chat Tabs on: chat tabs left to it")
		end
		if ModuleOn(prat, "OriginalButtons") then
			ns.FollowOwnAlpha({ "ChatFrameMenuButton" })
			ns.Log("support", "Prat Original Buttons on: chat menu button's alpha followed")
		end
	end)
end)
