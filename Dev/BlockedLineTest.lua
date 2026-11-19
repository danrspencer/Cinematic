-- /cine debug blockedline: proves the dev error box catches the yellow
-- "Interface action failed because of an AddOn" line, even with no
-- ADDON_ACTION_BLOCKED event (ErrorWindow.lua's hooks). Nothing to do but watch:
--   1 direct     calls the game's DisplayInterfaceActionBlockedMessage itself:
--                one "blocked (no event)" entry, and no chat-line entry on top
--                (the same line twice) (PASS/FAIL)
--   2 chat only  puts the line in chat by hand, no game function: one
--                "blocked (chat line only)" entry (PASS/FAIL)
--   3 replay     the line put in chat as chat history restore does at login
--                (ns.chatRestoring): no entry (PASS/FAIL)
--   4 settings   opens our settings the way our code does (ns.OpenOptions), main
--                page: no blocked line, the page shown. Forever's gamepad UI
--                once blocked it (OpenToCategory moves the gamepad cursor in,
--                game code only); now picked with SelectCategory (PASS/FAIL)
--   5 page       the same at a sub-page, as /reload puts it back (PASS/FAIL)
--   6 control    the old way (Settings.OpenToCategory from us): how many it
--                blocks now, to show the trigger was live (INFO)
-- Into CinematicDB.blockedLineTestLog, a verdict a step, a screenshot a step.
-- The yellow lines in chat during it are the test's. Run again to stop it.
-- Dev copy only.
local _, ns = ...

local HOOK, CHAT = "blocked (no event)", "blocked (chat line only)"
local WAIT = 1.5 -- seconds
local LINE = type(_G.INTERFACE_ACTION_BLOCKED) == "string" and _G.INTERFACE_ACTION_BLOCKED
	or "Interface action failed because of an AddOn"

local run

local function Say(text)
	local log = CinematicDB and CinematicDB.blockedLineTestLog
	if log then log[#log + 1] = ("%s %.1f %s"):format(date("%H:%M:%S"), run and GetTime() - run.at or 0, text) end
end
local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Say(("  screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end
local function Counts()
	return (ns.DevErrorCount(HOOK)), (ns.DevErrorCount(CHAT))
end
local function ChatLine()
	local frame = DEFAULT_CHAT_FRAME or _G.ChatFrame1
	local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
	frame:AddMessage(LINE, info and info.r or 1, info and info.g or 1, info and info.b or 0)
end

local function Finish(done)
	if not run then return end
	local this = run
	run = nil
	ns.chatRestoring = nil
	local line = ("%s: %d pass, %d fail, %d info"):format(done and "done" or "stopped", this.pass, this.fail, this.info)
	Say(line)
	ns.TestPrompt(("Blocked line test %s. /reload, then say \"check log\"."):format(line), 12)
end

local function Verdict(ok, text)
	if ok then run.pass = run.pass + 1 else run.fail = run.fail + 1 end
	Say(("  verdict %s: %s"):format(ok and "PASS" or "FAIL", text))
end

local function CloseSettings()
	local window = _G.SettingsPanel
	if window and window:IsShown() and HideUIPanel then pcall(HideUIPanel, window) end
end

-- A step that opens our settings as our code does (ns.OpenOptions, page or
-- the main one): no blocked line wanted, and the page on screen (wantShown
-- given what ns.ShownOptionsPage says).
local function OpenedStep(title, page, wantShown)
	return { "settings opened by our code: " .. title, function()
		CloseSettings()
		local ok, err = pcall(ns.OpenOptions, page)
		if not ok then Say("  OpenOptions error: " .. tostring(err)) end
		return true
	end, function(hook0, chat0, hook1, chat1)
		local new = hook1 - hook0 + chat1 - chat0
		if new > 0 then
			local _, stack = ns.DevErrorCount(hook1 > hook0 and HOOK or CHAT)
			if stack then Say("  stack:\n" .. stack) end
		end
		local shown = ns.ShownOptionsPage and ns.ShownOptionsPage()
		Say(("  gamepad UI %s, GamePadEnable %s, page shown %q"):format(_G.SmartNavigation and "there" or "not there",
			tostring(GetCVar and GetCVar("GamePadEnable")), tostring(shown)))
		local pageOk = wantShown(shown) and true or false
		Verdict(new == 0 and pageOk, ("blocked lines +%d (0 wanted), page %s"):format(new,
			pageOk and "shown" or "NOT shown"))
		CloseSettings()
	end }
end

-- Each step: a title, what it does, and its check (given the counts before).
local STEPS = {
	{ "the game's blocked-line function called, 12 calls deep", function()
		if type(_G.DisplayInterfaceActionBlockedMessage) == "function" then
			-- (12 calls deep, none a tail call: the box must keep more than the
			-- 8 lines it once cut every stack at, where the cause hid.)
			local function Deep(n)
				if n == 0 then pcall(_G.DisplayInterfaceActionBlockedMessage) else Deep(n - 1) end
			end
			Deep(12)
			return true
		end
	end, function(hook0, chat0, hook1, chat1)
		local _, stack = ns.DevErrorCount(HOOK)
		local kept = 0
		for _ in (stack or ""):gmatch("[^\n]+") do kept = kept + 1 end
		Say(("  stack lines kept: %d (12 or more wanted)"):format(kept))
		Verdict(hook1 == hook0 + 1 and chat1 == chat0 and kept >= 12,
			("hook entries +%d (1 wanted), chat-line entries +%d (0 wanted), stack lines %d (12+ wanted)"):format(
				hook1 - hook0, chat1 - chat0, kept))
	end },
	{ "the line put in chat by hand", function()
		ChatLine()
		return true
	end, function(hook0, chat0, hook1, chat1)
		Verdict(chat1 == chat0 + 1 and hook1 == hook0, ("chat-line entries +%d (1 wanted), hook entries +%d (0 wanted)"):format(
			chat1 - chat0, hook1 - hook0))
	end },
	{ "the line put back as chat history does at login", function()
		ns.chatRestoring = true
		pcall(ChatLine)
		ns.chatRestoring = nil
		return true
	end, function(hook0, chat0, hook1, chat1)
		Verdict(chat1 == chat0 and hook1 == hook0, ("entries +%d (0 wanted)"):format(chat1 - chat0 + hook1 - hook0))
	end },
	-- (the main page reads "CineMode" on Forever, "" where it isn't a search page)
	OpenedStep("main page", nil, function(shown) return shown == "" or shown == "CineMode" end),
	OpenedStep("Card Vision page (as /reload puts it back)", "Card Vision",
		function(shown) return shown ~= nil and shown ~= "" end),
	{ "control: the game's own OpenToCategory called by us (the old way)", function()
		local target = ns.settingsCategory
		if not (target and Settings and Settings.OpenToCategory) then
			Say("  no Settings.OpenToCategory on this client: skipped")
			return true
		end
		CloseSettings()
		-- (our main category, as ns.OpenOptions used to open it)
		local ok, err = pcall(Settings.OpenToCategory, target:GetID())
		if not ok then Say("  OpenToCategory error: " .. tostring(err)) end
		return true
	end, function(hook0, chat0, hook1, chat1)
		local new = hook1 - hook0 + chat1 - chat0
		run.info = run.info + 1
		Say(("  verdict INFO: the old way blocked %d time(s) now (it blocks only while the gamepad cursor is in no focus group)"):format(new))
		CloseSettings()
	end },
}

local function Step(index)
	if not run then return end
	local step = STEPS[index]
	if not step then return Finish(true) end
	Say(("--- %d of %d: %s ---"):format(index, #STEPS, step[1]))
	ns.TestPrompt(("Blocked line test: %d of %d, %s. Just watch."):format(index, #STEPS, step[1]), WAIT)
	local hook0, chat0 = Counts()
	if not step[2]() then
		Verdict(false, "DisplayInterfaceActionBlockedMessage missing on this client")
		return Step(index + 1)
	end
	C_Timer.After(WAIT, function()
		if not run then return end
		local ok, err = pcall(function()
			local hook1, chat1 = Counts()
			Say(("  box: hook entries %d -> %d, chat-line entries %d -> %d"):format(hook0, hook1, chat0, chat1))
			Shot(("step %d"):format(index))
			step[3](hook0, chat0, hook1, chat1)
		end)
		if not ok then
			Say("error: " .. tostring(err))
			return Finish(false)
		end
		Step(index + 1)
	end)
end

function ns.BlockedLineTest()
	if run then
		Finish(false)
		return
	end
	if not (CinematicDB and ns.DevErrorCount) then
		ns.Print("/cine debug blockedline: the dev error box isn't loaded.")
		return
	end
	if InCombatLockdown() then
		ns.Print("/cine debug blockedline: not in a fight (the settings can't open then).")
		return
	end
	CinematicDB.blockedLineTestLog = {}
	run = { at = GetTime(), pass = 0, fail = 0, info = 0 }
	local hook, chat = Counts()
	Say(("start: %s (game %s), box has %d hook and %d chat-line entries"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), hook, chat))
	C_Timer.After(0.2, function() Step(1) end)
end
