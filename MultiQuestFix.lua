-- Multi Quest fix (shoulderCamMultiQuestFix, on to start with; user,
-- 2026-11-15). Players get the held Accept (One quest, below) at every quest
-- giver; the two-quest test (this first part) is the dev copy's only.
--
-- In the game's own quest window, at a quest
-- giver with 2 or more quests: accepting one ends the talk on the game's side,
-- the camera snaps back, and in again as the next window opens. The test:
-- Accept clears your target first, then you talk to them again.
--
-- Clearing a target is protected, so it's a secure button laid over the
-- game's Accept button (out of fights only): its macro /cleartarget, then
-- /click on the game's own Accept, which runs as ever (nothing of it is
-- replaced: that's what tainted, till 2026-11-14). Talking to them again
-- needs a press of yours too (addons can't): the game's Interact key, which
-- with no target talks to whoever's in front of you. If the game doesn't
-- open their next window by itself, a chat line says which key.
-- Every step goes in the log ("multiquest"), with the Shoulder Cam's own
-- "shoulder" lines for the camera's turn.
--
-- One quest (test 3, user 2026-11-15: "accepting a quest from a quest giver
-- with just 1 causes the snap back"): the game's Accept ends the talk at once,
-- so the game's turn snaps back. With the cover over it, Accept is held while
-- the camera glides back (ns.ShoulderTalkClose, quick, as the quest bubble's
-- Accept is) and the window fades, then the game's AcceptQuest is called:
-- only called, never replaced. A PvP quest (the game asks first) isn't covered.
local _, ns = ...

local REOPEN_WAIT = 0.8 -- seconds after Accept before saying "press Interact"

-- The quest giver's quests, read as their gossip or greeting opens: how many,
-- and whose (their GUID, when it's readable).
local giver = { count = 0, guid = nil, at = nil }
local GIVER_FRESH = 60 -- seconds a gossip's or greeting's count holds for the quest text after it
-- The last Accept through ours: when, and whether a window opened since.
local accepted = { at = nil, reopened = false }

local function On()
	return ns.db and ns.db.shoulderCamMultiQuestFix and true or false
end

local function NpcGuid()
	local ok, guid = pcall(UnitGUID, "npc")
	if ok and type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then return guid end
end

local function AvailableQuests(event)
	local ok, count = pcall(function()
		if event == "QUEST_GREETING" then return GetNumAvailableQuests() end
		if C_GossipInfo and C_GossipInfo.GetNumAvailableQuests then return C_GossipInfo.GetNumAvailableQuests() end
		if C_GossipInfo and C_GossipInfo.GetAvailableQuests then return #(C_GossipInfo.GetAvailableQuests() or {}) end
		return GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() or 0
	end)
	return ok and type(count) == "number" and count or 0
end

local button = CreateFrame("Button", "CinematicMultiQuestAccept", UIParent, "SecureActionButtonTemplate")
button:SetAttribute("type", "macro")
-- (Set as it's laid over: MACRO_MULTI at a giver with more quests; the
-- held Accept, nothing in the macro, at one with one.)
local MACRO_MULTI = "/cleartarget\n/click QuestFrameAcceptButton"
button:SetAttribute("macrotext", MACRO_MULTI)
button.mode = "multi"
button:Hide()

-- Soft target (test 2, user 2026-11-15): does the game's turn keep to the
-- NPC through the gap if they're your soft interact target? SoftTargetInteract
-- (0 off, 1 gamepad, 2 mouse and keyboard, 3 both) is put at 3 while the
-- cover's up and given back SOFT_BACK seconds after Accept, or as the cover
-- goes without one. (A game setting changed for a test: put back each time.)
local SOFT_CVAR, SOFT_BACK = "SoftTargetInteract", 3
local soft = { yours = nil }

local function SoftOn()
	if soft.yours ~= nil then return end
	local value = GetCVar(SOFT_CVAR)
	if value == nil then
		ns.Log("multiquest", "soft target: this client has no " .. SOFT_CVAR)
		return
	end
	soft.yours = value
	if value ~= "3" then SetCVar(SOFT_CVAR, "3") end
	ns.Log("multiquest", ("soft target: %s %s -> 3"):format(SOFT_CVAR, value))
end

local function SoftBack(why)
	if soft.yours == nil then return end
	if GetCVar(SOFT_CVAR) ~= soft.yours then SetCVar(SOFT_CVAR, soft.yours) end
	ns.Log("multiquest", ("soft target: %s back to %s (%s)"):format(SOFT_CVAR, soft.yours, why))
	soft.yours = nil
end

-- What the game has as the soft interact target now, and is it them.
local function SoftState()
	local ok, text = pcall(function()
		local exists = ns.Flag(UnitExists("softinteract"))
		if not exists then return "none" end
		local npc = ns.Flag(UnitExists("npc")) and ns.Flag(UnitIsUnit("softinteract", "npc"))
		return ("%s%s"):format(tostring(UnitName("softinteract")), npc and " (the npc)" or "")
	end)
	return ok and text or "unreadable"
end

local function Cover(mode)
	local accept = _G.QuestFrameAcceptButton
	if not accept or InCombatLockdown() then return false end
	button.mode = mode
	button:SetAttribute("macrotext", mode == "multi" and MACRO_MULTI or "")
	if mode == "multi" then SoftOn() end
	button:ClearAllPoints()
	button:SetAllPoints(accept)
	button:SetFrameStrata("DIALOG")
	button:SetFrameLevel((accept:GetFrameLevel() or 1) + 10)
	button:Show()
	return true
end

local function Uncover(why)
	if not button:IsShown() or InCombatLockdown() then return end
	button:Hide()
	ns.Log("multiquest", ("cover off the game's Accept (%s); soft target %s"):format(why, SoftState()))
	-- (The window closes before Accept's PostClick runs: the soft target's
	-- given back here only if no Accept came with it.)
	C_Timer.After(0.5, function()
		if not (accepted.at and GetTime() - accepted.at < 1) then SoftBack("no Accept") end
	end)
end

-- The one-quest Accept: held for the glide back, the window faded meanwhile.
local function HeldAccept()
	ns.Log("multiquest", "Accept (one quest): held for the camera's glide back")
	if ns.ShoulderTalkClose then
		ns.ShoulderTalkClose("AcceptQuest", AcceptQuest, true)
	else
		AcceptQuest()
	end
	if ns.ShoulderTalkHeld and ns.ShoulderTalkHeld() then
		if ns.ShoulderFadeGameWindow and _G.QuestFrame then ns.ShoulderFadeGameWindow(_G.QuestFrame) end
	else
		ns.Log("multiquest", "Accept (one quest): not held (no talk turn on), accepted at once")
	end
end

button:SetScript("PostClick", function(self)
	if self.mode == "one" then
		HeldAccept()
		return
	end
	accepted.at, accepted.reopened = GetTime(), false
	local ok, target = pcall(UnitExists, "target")
	ns.Log("multiquest", ("Accept: target cleared (target now %s), the game's Accept clicked; %d quest(s) were on offer")
		:format(ok and tostring(ns.Flag(target)) or "?", giver.count))
	local at = accepted.at
	-- The soft target through the gap, every 0.05 s till the next window opens (or 1 s).
	ns.Log("multiquest", "soft target at Accept: " .. SoftState())
	local ticker
	ticker = C_Timer.NewTicker(0.05, function()
		if accepted.at ~= at or accepted.reopened or GetTime() - at > 1 then
			ticker:Cancel()
			return
		end
		ns.Log("multiquest", ("+%.2f s soft target: %s"):format(GetTime() - at, SoftState()))
	end)
	C_Timer.After(SOFT_BACK, function()
		if accepted.at == at then SoftBack(("%d s after Accept"):format(SOFT_BACK)) end
	end)
	C_Timer.After(REOPEN_WAIT, function()
		if accepted.at ~= at or accepted.reopened then return end
		local key = GetBindingKey("INTERACTTARGET")
		ns.Log("multiquest", ("no window reopened in %.1f s: waiting for your Interact key (%s)")
			:format(REOPEN_WAIT, tostring(key)))
		ns.Print(key and ("Multi Quest fix: press %s to talk to them again."):format(GetBindingText(key))
			or "Multi Quest fix: bind the game's Interact with Target key to talk to them again.")
	end)
end)

local events = CreateFrame("Frame")
for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_FINISHED", "PLAYER_REGEN_DISABLED",
	"PLAYER_LOGIN", "PLAYER_LOGOUT" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		-- (On key down or up as the game's action buttons are, not both: it'd go twice.)
		button:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "LeftButtonDown" or "LeftButtonUp")
		return
	end
	if event == "PLAYER_LOGOUT" then
		SoftBack("logout")
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		Uncover("a fight")
		SoftBack("a fight")
		return
	end
	if event == "QUEST_FINISHED" then
		Uncover("window closed")
		return
	end
	-- A window opened: after one of ours, the game (or your Interact) reopened it.
	if accepted.at and not accepted.reopened and GetTime() - accepted.at < 10 then
		accepted.reopened = true
		ns.Log("multiquest", ("%s %.2f s after Accept; soft target %s"):format(event, GetTime() - accepted.at,
			SoftState()))
	end
	if not On() then return end
	if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
		giver.count, giver.guid, giver.at = AvailableQuests(event), NpcGuid(), GetTime()
		ns.Log("multiquest", ("%s: %d quest(s) on offer"):format(event, giver.count))
		return
	end
	-- QUEST_DETAIL: a quest's text, Accept on it. A giver with 2 or more (the
	-- same one, where their GUID's readable, just now): the multi test; else
	-- the held Accept.
	local guid = NpcGuid()
	local same = giver.at and GetTime() - giver.at < GIVER_FRESH and (not (guid and giver.guid) or guid == giver.guid)
	local mode = (ns.isDev and same and giver.count >= 2) and "multi" or "one"
	local okPvp, pvp = pcall(function() return QuestFlagsPVP and QuestFlagsPVP() end)
	if mode == "one" and (not okPvp or ns.Flag(pvp)) then
		ns.Log("multiquest", "no cover: a PvP quest (the game asks first), or unreadable")
		return
	end
	if Cover(mode) then
		ns.Log("multiquest", mode == "multi" and "cover over the game's Accept (a giver with more quests)"
			or "cover over the game's Accept (one quest: held for the glide back)")
	else
		ns.Log("multiquest", "no cover: in a fight, or no game Accept button")
	end
end)
