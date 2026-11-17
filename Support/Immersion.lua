-- Cinematic: Immersion, which swaps the game's gossip and quest windows for
-- its own (ImmersionFrame), with gamepad controls through ConsolePort. It
-- tucks the game's windows away under a hidden frame of its own, where the
-- game still shows its gossip window (CustomGossipFrameManager): Quest talk
-- (Custom dialogue frames) doesn't count a window tucked away like that
-- (QuestTalk.lua, TuckedAway), so only Immersion's comes up. It has no camera
-- of its own: the quest camera plays with it as usual.
local _, ns = ...
local L = ns.L

-- Advanced Frames page (no columns: nothing of its fades).
table.insert(ns.ADDON_NOTES, {
	addon = "Immersion", label = "Immersion",
	works = L["Takes over talking to NPCs"],
	about = L["Immersion replaces the game's NPC windows, so Cinematic's dialogue frames don't show."],
})
