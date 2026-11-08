-- Cinematic: RareScanner. Its alert is one button (RARESCANNER_BUTTON, the
-- rare's name, model and loot, a click to target it), at the bottom of the
-- screen as it finds a rare, treasure or event. It fades as its own row on
-- the Advanced Frames page. For a rare NPC, Rare spotted's card can stand in
-- for it (Card Settings > Rare spotted: rareScannerAlert, "ours" by default):
-- its button goes as it comes up and our card shows, with RareScanner's
-- sound and chat line as it has them. "theirs": its button as before, and
-- our card stays quiet for the rares it showed. Treasures and events keep its
-- button either way. Its button only comes up out of fights (it's a secure
-- button), so hiding it is too.
local _, ns = ...
local L = ns.L

table.insert(ns.ADDON_FRAMES, {
	key = "rarescanner", addon = "RareScanner", label = "RareScanner",
	about = L["its alert button"],
	note = L["Rare spotted's card can show in place of it for rares (Card Settings > Rare spotted)."],
	names = { "RARESCANNER_BUTTON" },
})

-- (The game's minimap icons for a rare NPC, as RareScanner tells them apart.)
local NPC_ATLAS = {
	VignetteKill = true, VignetteKillElite = true, DemonInvasion5 = true, ["nazjatar-nagaevent"] = true,
	["Warfront-NeutralHero"] = true, ["Tormentors-Boss"] = true, ["WarlockPortal-Yellow-32x32"] = true,
}

ns.WhenAddonLoads("RareScanner", function()
	local button = _G.RARESCANNER_BUTTON
	if type(button) ~= "table" or type(button.ShowButton) ~= "function" then
		ns.Log("error", "support for RareScanner: no RARESCANNER_BUTTON:ShowButton")
		return
	end
	hooksecurefunc(button, "ShowButton", function(self)
		if not (self.entityID and self.name and NPC_ATLAS[self.atlasName]) or self.preEvent then return end
		if InCombatLockdown() then return end
		local ok, ours = pcall(ns.RareScannerFound, self.name, nil, self.displayID)
		if ok and ours and self.HideButton and not InCombatLockdown() then
			self:HideButton()
		elseif not ok then
			ns.Log("error", "support for RareScanner: " .. tostring(ours))
		end
	end)
end)
