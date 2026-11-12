-- Cinematic: Naowh Forever, a WoW Forever suite (one addon per module). Its
-- Quality of Life module's top bar, along the top of the screen, gets a row
-- on the Advanced Frames page, and so do its other pieces on screen (below);
-- its own RestedXP guide window, standing in for RestedXP's, fades with the
-- Quest tracker row as RestedXP's does.
--
-- The top bar and its FPS / MS readout set their own alpha (its Show On
-- Mouseover fading): they're its own frames, so they're hooked.
local _, ns = ...
local L = ns.L

-- Advanced Frames row. (The readout is an unnamed frame on UIParent, kept
-- as the bar's sys.)
table.insert(ns.ADDON_FRAMES, {
	key = "naowhTopBar", addon = "NaowhForever_QoL", suite = "Naowh Forever",
	label = "Naowh Forever top bar", short = "Naowh top bar",
	about = L["its top bar along the top of the screen, with its FPS and MS readout"],
	names = { "NaowhForeverTopBar" },
	match = function(frame)
		local bar = _G.NaowhForeverTopBar
		return type(bar) == "table" and frame == bar.sys
	end,
	hookAlpha = true,
})

-- Its other pieces on screen, one frame a row: named frames on UIParent that
-- leave their own alpha alone. (The swing timer's name has "SwingTimer" in
-- it: without its row here it was taken for the game's, and followed the
-- Swing timer row.)
-- Left out: the ones that set their own alpha all the time, some from secret
-- values (Low Health, Pet Tracker, Focus Cast Bar, Combat Alert, the mouse
-- ring and Cooldown at Cursor), and its windows (the trainer popup, quiz,
-- Daily Word and Bag Space cards): a faded window still takes clicks.
local function Rows(addon, rows)
	for _, row in ipairs(rows) do
		table.insert(ns.ADDON_FRAMES, {
			key = row[1], addon = addon, suite = "Naowh Forever",
			label = "Naowh Forever " .. row[3], short = "Naowh " .. row[3],
			about = row[4], names = { row[2] },
		})
	end
end

Rows("NaowhForever_Combat", {
	{ "naowhSwing", "NaowhForeverSwingTimer", "swing timer", L["its swing timer bars"] },
	{ "naowhThreat", "NaowhForeverThreatMeter", "threat meter", L["its threat meter"] },
	{ "naowhBuffReminders", "NaowhForeverBuffReminders", "buff reminders", L["its Buffs & Consumables icons"] },
	{ "naowhCampfire", "NaowhForeverCampfire", "campfire", L["its campfire reminder"] },
	{ "naowhCampNearby", "NaowhForeverCampNearby", "camp nearby", L["its Camp Nearby alert"] },
	{ "naowhBlessings", "NaowhForeverBlessingBar", "blessing bar", L["its blessing bar"] },
	{ "naowhGearBar", "NaowhForeverGearBar", "gear set bar", L["its gear set bar"] },
	{ "naowhTrinkets", "NaowhForeverTrinkets", "trinket bar", L["its trinket bar"] },
	{ "naowhPvPFlag", "NaowhForeverPvPFlag", "PvP flag", L["its PvP flag button"] },
})

Rows("NaowhForever_QoL", {
	{ "naowhCombatTimer", "NaowhForeverCombatTimer", "combat timer", L["its combat timer"] },
	{ "naowhCoTank", "NaowhForeverCoTank", "co-tank frame", L["its co-tank frame"] },
	{ "naowhHealerMana", "NaowhForeverHealerMana", "healer mana", L["its healer mana list"] },
	{ "naowhGcd", "NaowhForeverGcdTracker", "GCD tracker", L["its GCD tracker"] },
	{ "naowhCrosshair", "NaowhForeverCrosshair", "crosshair", L["its crosshair in the middle of the screen"] },
	{ "naowhXPBar", "NaowhForeverXPBar", "XP bar", L["its XP bar"] },
	{ "naowhXPTicker", "NaowhForeverXPTicker", "XP ticker", L["its XP per hour ticker"] },
	{ "naowhGroupXP", "NaowhForeverGroupXP", "group XP", L["its group XP bars"] },
	{ "naowhLootFeed", "NaowhForeverLootFeed", "loot feed", L["its loot feed"] },
	{ "naowhFlightTimer", "NaowhForeverFlightTimer", "flight timer", L["its flight timer"] },
	{ "naowhGroupButtons", "NaowhForeverGroupButtons", "group buttons", L["its Invite and Disband buttons"] },
	{ "naowhLayer", "NaowhForeverLayerTracker", "layer tracker", L["its layer tracker"] },
	{ "naowhDurability", "NaowhForeverDurability", "durability warning", L["its low durability warning"] },
	{ "naowhGearReminders", "NaowhForeverGearReminders", "gear reminders", L["its gear reminder icons"] },
	{ "naowhRestock", "NaowhForeverRestock", "restock reminder", L["its restock reminder"] },
	{ "naowhTalentPoints", "NaowhForeverTalentPoints", "talent points", L["its unspent talent points reminder"] },
	{ "naowhLegacyPoints", "NaowhForeverLegacyPoints", "Legacy points", L["its unspent Legacy points alert"] },
	{ "naowhFlightPoint", "NaowhForeverFlightPoint", "flight point reminder", L["its flight point reminders"] },
})

ns.WhenAddonLoads("NaowhForever", function()
	ns.FadeWithRow("quests", "quests", { "NaowhRXPWindow" })
end)
