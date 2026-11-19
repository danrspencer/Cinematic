-- /cine debug chatreveal (dev copy only): the handoff from a revealed chat
-- line (Show just those messages) to the chat window coming up on hover.
-- Two rounds, each: a test line is revealed, you mouse over the chat window.
--   A: a pretend loot line comes in under it first, so the copy no longer sits
--      on the window's lines: the copy must go in a quick fade as the window
--      starts coming up (no text over text).
--   B: nothing after it: the copy crosses over the window's own line.
-- Every frame of each hover is logged (window alpha, copy alpha, quick fade,
-- lines up), with screenshots in round A, and a verdict per round. Nothing is
-- printed to chat while a round runs (a chat line would change what's tested);
-- the steps show in big text on the screen.

local _, ns = ...

local HOVER_WAIT = 25 -- seconds to mouse over chat
local FADE_WAIT = 20 -- seconds to move off chat and let it fade
local AFTER_RISE = 1.2 -- seconds recorded once the window starts coming up
local QUICK_MAX = 0.35 -- round A: the copy must be gone this soon after the rise starts
local SHOTS = { 0.05, 0.4 } -- round A screenshots, seconds after the rise starts

local driver = CreateFrame("Frame")
local prompt, run

local function Log(text) ns.Log("chatreveal", text) end

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

local function StateText(st)
	if not st then return "no copy" end
	return ("copy %s a=%s quick=%s linesUp=%s count=%s/%s window a=%s base=%s"):format(
		st.shown and "up" or "gone", Num(st.alpha), tostring(st.quick), tostring(st.linesUp),
		tostring(st.count), tostring(st.windowCount), Num(st.windowAlpha), Num(st.base))
end

-- What the hover wait sees, every WATCH_EVERY seconds: the mouse over the
-- window, the window shown and how far up, and each new line in it.
local WATCH_EVERY = 0.25
local function Watch(r, cf, now)
	if r.watchAt and now < r.watchAt then return end
	r.watchAt = now + WATCH_EVERY
	local over = ns.Flag(cf:IsMouseOver())
	local panel = ns.chatPeekPanels and ns.chatPeekPanels[cf]
	Log(("round %s wait %.2f: mouse over %s, visible %s, shown %s, eff alpha %s, seen %s, panel %s"):format(r.name,
		now - r.hoverFrom, tostring(over), tostring(cf:IsVisible()), tostring(cf:IsShown()),
		Num(cf:GetEffectiveAlpha()), tostring(ns.ChatSeen(cf)), panel and tostring(panel:GetName()) or "none"))
	local count = cf:GetNumMessages()
	if type(count) == "number" and r.lastCount and count > r.lastCount then
		for i = r.lastCount + 1, count do
			local line = cf:GetMessageInfo(i)
			local text = type(line) == "string" and not (issecretvalue and issecretvalue(line)) and line or "(unreadable)"
			Log(("round %s: new window line %d: %s"):format(r.name, i, text:gsub("|", "!"):sub(1, 120)))
			if r.name == "B" then r.otherLine = true end
		end
	end
	if type(count) == "number" then r.lastCount = count end
end

local Next

local function Finish(text)
	ns.SetOnUpdate(driver, nil)
	Prompt(nil)
	if run and run.restoreLinesOnly ~= nil then ns.db.chatPeekLinesOnly = run.restoreLinesOnly end
	if run and run.holdSet then ns.db.chatPeekTime = run.restoreHold end
	run = nil
	Log(text)
	ns.Print(text)
end

local function Verdict(round)
	local r = round
	local lines = {}
	if not r.riseAt then
		lines[#lines + 1] = "FAIL: no hover seen (the window never came up)"
	elseif r.goneBeforeRise then
		lines[#lines + 1] = "REDO: the copy went before the hover"
	elseif r.otherLine then
		lines[#lines + 1] = "REDO: another chat line came in during the round (see new window line)"
	else
		local gone = r.goneAt and (r.goneAt - r.riseAt) or nil
		local overlap = ("overlap %.2fs"):format(r.overlap)
		if r.name == "A" then
			local ok = r.quickSeen and gone and gone <= QUICK_MAX
			lines[#lines + 1] = ("%s: quick fade %s, copy gone %s after rise (want <= %.2f), %s"):format(
				ok and "PASS" or "FAIL", r.quickSeen and "yes" or "NO", gone and Num(gone) .. "s" or "never",
				QUICK_MAX, overlap)
		else
			local ok = not r.quickSeen and r.linesUpAtRise
			lines[#lines + 1] = ("%s: lines up at rise %s, quick fade %s (want no), copy gone %s after rise, %s"):format(
				ok and "PASS" or "FAIL", tostring(r.linesUpAtRise), r.quickSeen and "YES" or "no",
				gone and Num(gone) .. "s" or "never", overlap)
		end
	end
	return ("round %s: %s"):format(r.name, table.concat(lines, "; "))
end

-- Each frame while a round waits for or records the hover.
local function Step()
	local r = run and run.round
	if not r then return end
	local cf, now = run.chatFrame, GetTime()
	local st = ns.ChatCopyState(cf)
	if r.phase == "fade" then
		-- (Waiting for the window to be faded out before the round's line.)
		if not ns.ChatSeen(cf) then
			r.unseenAt = r.unseenAt or now
			if now - r.unseenAt >= (tonumber(ns.FadeOutTime()) or 0.5) + 0.8 then
				r.phase = "peek"
				Prompt("Round " .. r.name .. ": hands off the chat for a moment")
				r.peekAt = now + 0.6
			end
		else
			r.unseenAt = nil
			if now > r.started + FADE_WAIT then
				Finish("chatreveal: chat never faded out (is CineMode on?). " .. Verdict(r))
			end
		end
	elseif r.phase == "peek" then
		if now >= r.peekAt then
			local line = ("|cffffd200Cinematic test %s: this line was revealed|r"):format(r.name)
			cf:AddMessage(line)
			ns.ChatTestPeek(cf, line)
			Log(("round %s: line revealed: %s"):format(r.name, StateText(ns.ChatCopyState(cf))))
			r.phase = r.loot and "loot" or "hover"
			r.lastCount = cf:GetNumMessages()
			r.lootAt = now + 0.5
			r.hoverFrom = now
			if not r.loot then
				Prompt("Round " .. r.name .. ": mouse over the chat window now, and stay on it")
			end
		end
	elseif r.phase == "loot" then
		if now >= r.lootAt then
			local info = ChatTypeInfo and ChatTypeInfo.LOOT
			cf:AddMessage("You receive loot: [Cinematic Test Item].", info and info.r or 0, info and info.g or 0.67,
				info and info.b or 0)
			Log(("round %s: loot line in: %s"):format(r.name, StateText(ns.ChatCopyState(cf))))
			r.phase = "hover"
			Prompt("Round " .. r.name .. ": mouse over the chat window now, and stay on it")
		end
	elseif r.phase == "hover" then
		local alpha = st and st.windowAlpha or 0
		r.startAlpha = r.startAlpha or alpha
		Watch(r, cf, now)
		if not r.riseAt then
			if not (st and st.shown) then
				r.goneBeforeRise = true
				Log(("round %s: copy gone before any hover: %s"):format(r.name, StateText(st)))
				Next()
			elseif alpha > r.startAlpha + 0.03 then
				r.riseAt = now
				r.linesUpAtRise = st.linesUp
				Log(("round %s: window starts coming up: %s"):format(r.name, StateText(st)))
			elseif now > r.hoverFrom + HOVER_WAIT then
				Next()
			end
		end
		if r.riseAt then
			local t = now - r.riseAt
			Log(("round %s +%.3f: %s"):format(r.name, t, StateText(st)))
			if st and st.quick then r.quickSeen = true end
			local copyUp = st and st.shown and (st.alpha or 0) > 0.15
			local base = st and st.base or r.startAlpha
			local windowUp = (alpha - base) / math.max(0.05, 1 - base) > 0.15
			if copyUp and windowUp and r.lastAt then r.overlap = r.overlap + (now - r.lastAt) end
			if not (st and st.shown) and not r.goneAt then r.goneAt = now end
			r.lastAt = now
			if r.loot then
				for i, at in ipairs(SHOTS) do
					if not r.shot[i] and t >= at then
						r.shot[i] = true
						local before = st and st.windowCount
						Screenshot()
						Log(("round %s: screenshot %d at +%.2fs (window lines before %s)"):format(r.name, i, t, tostring(before)))
					end
				end
			end
			if t >= AFTER_RISE then Next() end
		end
	end
end

local ROUNDS = {
	{ name = "A", loot = true },
	{ name = "B", loot = false },
}

Next = function()
	local r = run.round
	if r then
		run.verdicts[#run.verdicts + 1] = Verdict(r)
		Log(run.verdicts[#run.verdicts])
	end
	run.index = run.index + 1
	local spec = ROUNDS[run.index]
	if not spec then
		Finish("chatreveal: done. " .. table.concat(run.verdicts, " | ") .. " -- check log")
		return
	end
	run.round = { name = spec.name, loot = spec.loot, phase = "fade", started = GetTime(), overlap = 0, shot = {} }
	Prompt("Round " .. spec.name .. ": move the mouse off the chat and wait")
end

function ns.ChatRevealTest(text)
	if (text or ""):match("off") then
		if run then Finish("chatreveal: stopped.") else ns.Print("chatreveal: not running.") end
		return
	end
	if run then
		ns.Print("chatreveal: already running. /cine debug chatreveal off stops it.")
		return
	end
	local cf = DEFAULT_CHAT_FRAME
	if not (ns.ChatTestPeek and ns.ChatCopyState and cf) then
		ns.Print("chatreveal: the chat code has no test hooks.")
		return
	end
	if not ns.PageOn("handleChat") then
		ns.Print("chatreveal: turn the Chat page on first.")
		return
	end
	if not ns.ChatWindowShown(cf) then
		ns.Print("chatreveal: select your main chat tab first.")
		return
	end
	run = { chatFrame = cf, index = 0, verdicts = {} }
	-- (Show just those messages on for the test, put back after.)
	if not ns.db.chatPeekLinesOnly then
		run.restoreLinesOnly = false
		ns.db.chatPeekLinesOnly = true
	end
	-- (A long reveal time for the test, put back after: time to get to the chat.)
	run.holdSet, run.restoreHold = true, ns.db.chatPeekTime
	ns.db.chatPeekTime = 30
	Log(("start: %s, CineMode %s, hold %s, fade out %s, lines-only was %s"):format(ns.isRetail and "retail" or "classic",
		tostring(ns.IsCineModeOn and ns.IsCineModeOn()), tostring(ns.HoldTime("chatPeekTime")),
		tostring(ns.FadeOutTime()), tostring(run.restoreLinesOnly == nil)))
	ns.Print("chatreveal: 2 rounds, follow the big text. Don't type in chat till it says done.")
	ns.SetOnUpdate(driver, Step)
	Next()
end
