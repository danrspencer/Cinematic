-- Cinematic: repeat talking heads (Quest Vision page, talkingHeadRepeats).
-- The game's talking head (the portrait box at the top with an NPC's line and
-- voice) closes at once, voice and all, when it plays a line this character
-- has seen before: the dailies' and world quests' lines come back day after
-- day, the story's play once. The game says nothing of which quest a line is
-- from, so seen before is the only sign there is.
--
-- Every line played is remembered (its speaker and words, in
-- CinematicCharDB.talkingHeadSeen), setting on or off. By character, so an
-- alt still hears the story. Only where the game has talking heads (not
-- Classic Era).
local _, ns = ...

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

-- The line playing now, as remembered: its speaker and words. Nil when
-- there's none to read.
local function LineKey()
	if not (C_TalkingHead and C_TalkingHead.GetCurrentLineInfo) then return nil end
	local ok, _, _, _, _, _, _, name, text = pcall(C_TalkingHead.GetCurrentLineInfo)
	if not ok or Secret(name) or Secret(text) or type(text) ~= "string" or text == "" then return nil end
	return (type(name) == "string" and name or "") .. "\n" .. text
end

-- (Lines last heard longer ago than this are forgotten, once a session, so
-- the list doesn't grow for ever: a daily's line is heard again well within it.)
local FORGET_AFTER = 90 * 24 * 3600
local pruned = false
local function Prune(seen)
	if pruned then return end
	pruned = true
	local before = time() - FORGET_AFTER
	for key, at in pairs(seen) do
		if type(at) ~= "number" or at < before then seen[key] = nil end
	end
end

local function Played(frame)
	local key = LineKey()
	local char = ns.chardb
	if not (key and char) then return end
	char.talkingHeadSeen = char.talkingHeadSeen or {}
	Prune(char.talkingHeadSeen)
	local seen = char.talkingHeadSeen[key]
	char.talkingHeadSeen[key] = time()
	if not (seen and ns.QuestVisionSetting("talkingHeadRepeats")) then return end
	ns.Log("talkinghead", "seen before, closed: " .. key:gsub("\n", ": "))
	if frame.CloseImmediately then
		frame:CloseImmediately()
	else
		if C_TalkingHead.IgnoreCurrentTalkingHead then C_TalkingHead.IgnoreCurrentTalkingHead() end
		frame:Hide()
	end
end

-- (The frame comes with Blizzard_TalkingHeadUI: loaded already, or later.)
local hooked = false
local function Hook()
	local frame = _G.TalkingHeadFrame
	if hooked or not (frame and frame.PlayCurrent) then return end
	hooked = true
	hooksecurefunc(frame, "PlayCurrent", Played)
end

if C_TalkingHead then
	Hook()
	if not hooked then
		local loader = CreateFrame("Frame")
		loader:RegisterEvent("ADDON_LOADED")
		loader:SetScript("OnEvent", function(self)
			Hook()
			if hooked then self:UnregisterAllEvents() end
		end)
	end
end
