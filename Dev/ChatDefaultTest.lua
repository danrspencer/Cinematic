-- /cine debug chatdefault (dev copy only): Show just those messages works
-- only with the game's own chat (ns.ChatIsDefault, UI/Chat.lua). With
-- EllesmereUI's chat our copy of a new line showed under its own line: two
-- lines (2026-11-20). Runs itself, logs everything, own verdicts:
--   0: what chat is on screen (which addon claims the window, chat addons
--      loaded) and the Chat page's checkbox: shown only with the game's chat.
--   1: your setup as it is: a test line comes in while chat is faded. Game's
--      chat: a copy of just the line, the window stays faded. Another addon's:
--      no copy, the window comes up instead.
--   2: the other way round (ns.ChatIsDefault answered the opposite for the
--      round), so both answers are proven on this client.
-- Screenshots in each round. Nothing goes to chat while a round runs (a chat
-- line would peek chat itself); the steps show in big text on the screen.

local _, ns = ...

local HOLD = 4 -- reveal time for the test (seconds), put back after
local LOOK_AT = 0.6 -- seconds after the line that the result is read
local SHOT_AT = 0.3 -- seconds after the line that the screenshot is taken
local CHAT_ADDONS = { "EllesmereUIChat", "ElvUI", "Glass", "Chattynator", "Prat-3.0", "DaylightUI_Chat" }

local driver = CreateFrame("Frame")
local prompt, run

local function Log(text) ns.Log("chatdefault", text) end

local function Prompt(text)
	if not prompt then
		prompt = CreateFrame("Frame", nil, WorldFrame)
		prompt:SetFrameStrata("TOOLTIP")
		prompt:SetAllPoints(WorldFrame)
		prompt.text = prompt:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		prompt.text:SetPoint("TOP", prompt, "TOP", 0, -WorldFrame:GetHeight() * 0.2)
		prompt.text:SetWidth(WorldFrame:GetWidth() * 0.6)
	end
	prompt.text:SetText(text or "")
	prompt:SetShown(text ~= nil)
end

local function Num(v) return type(v) == "number" and ("%.2f"):format(v) or tostring(v) end

local function CopyText(st)
	if not st then return "no copy frame" end
	return ("copy %s a=%s lines=%s, window lines %s a=%s"):format(st.shown and "UP" or "gone", Num(st.alpha),
		tostring(st.count), tostring(st.windowCount), Num(st.windowAlpha))
end

local function Loaded(name)
	local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return IsLoaded and IsLoaded(name) and true or false
end

local realIsDefault

local function Finish(text)
	ns.SetOnUpdate(driver, nil)
	if realIsDefault then ns.ChatIsDefault = realIsDefault end
	if run then
		if run.restoreLinesOnly ~= nil then ns.db.chatPeekLinesOnly = run.restoreLinesOnly end
		ns.db.chatPeekTime = run.restoreHold
	end
	run = nil
	Log(text)
	Prompt("Chat test DONE -- type: check log")
	C_Timer.After(8, function() if not run then Prompt(nil) end end)
	ns.Print(text)
end

-- 0: the setup and the checkbox.
local function CheckSetup()
	local claimants = ns.LinkClaimants and ns.LinkClaimants("chatwindow")
	local loaded = {}
	for _, name in ipairs(CHAT_ADDONS) do
		if Loaded(name) then loaded[#loaded + 1] = name end
	end
	local isDefault = realIsDefault()
	Log(("setup: %s, CineMode %s, game's own chat %s; window claimed by %s; chat addons loaded: %s; " ..
		"setting %s, lines only now %s, panel over ChatFrame1 %s"):format(ns.isRetail and "retail" or "Forever",
		tostring(ns.IsCineModeOn and ns.IsCineModeOn()), tostring(isDefault),
		claimants and table.concat(claimants, ", ") or "none", #loaded > 0 and table.concat(loaded, ", ") or "none",
		tostring(run.restoreLinesOnly == nil), tostring(ns.ChatPeekLinesOnly()),
		tostring(ns.chatPeekPanels and ns.chatPeekPanels[run.chatFrame] and true or false)))
	local entry = ns.FindEntryOf and ns.FindEntryOf("chatPeekLinesOnly")
	local box = entry and entry.edges and entry.edges.top
	if not (box and box.Refresh) then
		run.verdicts[#run.verdicts + 1] = "0 checkbox: FAIL (not found in the settings)"
	else
		box:Refresh()
		local shown = box:IsShown() and true or false
		run.verdicts[#run.verdicts + 1] = ("0 checkbox: %s (shown %s, want %s)"):format(
			shown == isDefault and "PASS" or "FAIL", tostring(shown), tostring(isDefault))
	end
	Log(run.verdicts[#run.verdicts])
end

local ROUNDS = {
	{ name = "1", label = "your chat as it is" },
	{ name = "2", label = "the other way round", flip = true },
}

local Next

local function Verdict(r)
	local st = r.state
	local copyUp = st and st.shown and true or false
	local windowUp = r.peeked
	local ok
	if r.isDefault then
		ok = copyUp and not windowUp
	else
		ok = (not copyUp) and windowUp
	end
	return ("%s %s (game's chat %s): %s, copy %s (want %s), window up %s (want %s)"):format(r.name, r.label,
		tostring(r.isDefault), ok and "PASS" or "FAIL", tostring(copyUp), tostring(r.isDefault),
		tostring(windowUp), tostring(not r.isDefault))
end

local function Step()
	local r = run and run.round
	if not r then return end
	local cf, now = run.chatFrame, GetTime()
	if r.phase == "fade" then
		-- (Waits, no time limit, for the window faded and no copy left up.)
		local st = ns.ChatCopyState(cf)
		local quiet = not ns.ChatSeen(cf) and not (st and st.shown) and (ns.chatPeekUntil[cf] or 0) <= now
		if quiet then
			r.quietAt = r.quietAt or now
			if now - r.quietAt >= (tonumber(ns.FadeOutTime()) or 0.5) + 0.8 then
				r.phase = "line"
				r.lineAt = now + 0.3
				Prompt(("Chat test round %s (%s): hands off, a test line comes in"):format(r.name, r.label))
			end
		else
			r.quietAt = nil
			if not r.told and now > r.started + 15 then
				r.told = true
				Log(("round %s: chat still up after 15 s (seen %s, copy %s); waiting"):format(r.name,
					tostring(ns.ChatSeen(cf)), CopyText(st)))
				Prompt(("Chat test round %s: waiting for chat to fade.\nMouse off chat. If it never fades, turn CineMode on."):format(r.name))
			end
		end
	elseif r.phase == "line" then
		if now >= r.lineAt then
			if r.flip then ns.ChatIsDefault = function() return not realIsDefault() end end
			r.isDefault = ns.ChatIsDefault()
			r.peekBefore = ns.chatPeekUntil[cf] or 0
			local line = ("|cffffd200Cinematic chat test %s: this line came in|r"):format(r.name)
			cf:AddMessage(line)
			ns.ChatTestPeek(cf, line)
			r.sentAt = now
			r.phase = "look"
			Log(("round %s: line in, lines only %s: %s"):format(r.name, tostring(ns.ChatPeekLinesOnly()),
				CopyText(ns.ChatCopyState(cf))))
		end
	elseif r.phase == "look" then
		local t = now - r.sentAt
		if not r.shot and t >= SHOT_AT then
			r.shot = true
			Screenshot()
			Log(("round %s: screenshot at +%.2fs: %s"):format(r.name, t, CopyText(ns.ChatCopyState(cf))))
		end
		if t >= LOOK_AT then
			r.state = ns.ChatCopyState(cf)
			r.peeked = (ns.chatPeekUntil[cf] or 0) > r.peekBefore
			Log(("round %s at +%.2fs: %s, window peek until %s (was %s), seen %s"):format(r.name, t,
				CopyText(r.state), Num(ns.chatPeekUntil[cf]), Num(r.peekBefore), tostring(ns.ChatSeen(cf))))
			ns.ChatIsDefault = realIsDefault
			Next()
		end
	end
end

Next = function()
	local r = run.round
	if r then
		run.verdicts[#run.verdicts + 1] = Verdict(r)
		Log(run.verdicts[#run.verdicts])
	end
	run.index = run.index + 1
	local spec = ROUNDS[run.index]
	if not spec then
		local fails = 0
		for _, v in ipairs(run.verdicts) do
			if v:find("FAIL", 1, true) then fails = fails + 1 end
		end
		Finish(("chatdefault: done, %s. %s -- check log"):format(fails == 0 and "ALL PASS" or (fails .. " FAILED"),
			table.concat(run.verdicts, " | ")))
		return
	end
	run.round = { name = spec.name, label = spec.label, flip = spec.flip, phase = "fade", started = GetTime() }
	Prompt(("Chat test round %s (%s): mouse off chat, waiting for it to fade"):format(spec.name, spec.label))
end

function ns.ChatDefaultTest(text)
	ns.debugNoCopyWindow = true
	if (text or ""):match("off") then
		if run then Finish("chatdefault: stopped.") else ns.Print("chatdefault: not running.") end
		return
	end
	if run then
		ns.Print("chatdefault: already running. /cine debug chatdefault off stops it.")
		return
	end
	local cf = DEFAULT_CHAT_FRAME
	if not (ns.ChatTestPeek and ns.ChatCopyState and ns.ChatIsDefault and cf) then
		ns.Print("chatdefault: the chat code has no test hooks.")
		return
	end
	if not ns.PageOn("handleChat") then
		ns.Print("chatdefault: turn the Chat page on first.")
		return
	end
	if not ns.ChatWindowShown(cf) then
		ns.Print("chatdefault: select your main chat tab first.")
		return
	end
	realIsDefault = ns.ChatIsDefault
	run = { chatFrame = cf, index = 0, verdicts = {}, restoreHold = ns.db.chatPeekTime }
	-- (Show just those messages on for the test, put back after.)
	if not ns.db.chatPeekLinesOnly then
		run.restoreLinesOnly = false
		ns.db.chatPeekLinesOnly = true
	end
	ns.db.chatPeekTime = HOLD
	ns.Print("chatdefault: runs itself, about 20 seconds; follow the big text. Don't type in chat till it says DONE.")
	CheckSetup()
	ns.SetOnUpdate(driver, Step)
	Next()
end
