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
--   7 fight      the settings key in a fight (taken down the fight path with
--                ns.testFakeFight): the window opens, gamepad UI or not, and
--                with it the fight is marked so the left list's blocked
--                gamepad calls stay out of the dev box (PASS/FAIL)
--   8 quiet      a blocked line from the gamepad UI's file (faked chunk name):
--                out of the box while marked, in it after (PASS/FAIL)
--   9 taint scan which game fields an addon wrote (issecurevariable) in the
--                settings window, game menu, panel list and gamepad UI, also
--                once before step 1: Escape > Options in a fight blocked every
--                settings line, so something read there is tainted (INFO)
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

-- Which game values an addon wrote (issecurevariable: who tainted each field),
-- through the settings window, the game menu, the panel manager's list and the
-- gamepad UI: a tainted one read as the game menu's Options button opens the
-- settings in a fight blocks every settings line (Escape > Options, 2026-11-20).
-- Walks fields and child frames, each table once; lines into the log.
local SCAN_ROOTS = { "SettingsPanel", "GameMenuFrame", "UIPanelWindows", "SmartNavigation", "Settings",
	"SettingsInbound", "SettingsCallbackRegistry" }
local SCAN_MAX, SCAN_DEPTH, SCAN_SHOW = 40000, 10, 60
local function TaintScan(label, showMax, sayTo)
	local Say = sayTo or Say
	if type(issecurevariable) ~= "function" then
		Say("  " .. label .. ": no issecurevariable on this client")
		return
	end
	local seen, found, byAddon, visited, allPaths = {}, {}, {}, 0, {}
	local function Note(path, who)
		who = tostring(who or "?")
		byAddon[who] = (byAddon[who] or 0) + 1
		allPaths[#allPaths + 1] = path
		if #found < SCAN_SHOW then found[#found + 1] = ("    %s  (by %s)"):format(path, who) end
	end
	local function Walk(t, path, depth)
		if visited >= SCAN_MAX or depth > SCAN_DEPTH or seen[t] then return end
		seen[t] = true
		local ok = pcall(function()
			for key, value in pairs(t) do
				visited = visited + 1
				if visited >= SCAN_MAX then return end
				if type(key) == "string" then
					local fine, secure, who = pcall(issecurevariable, t, key)
					if fine and not secure then Note(path .. "." .. key, who) end
					if type(value) == "table" and not (issecretvalue and issecretvalue(value)) then
						Walk(value, path .. "." .. key, depth + 1)
					end
				end
			end
		end)
		if not ok then return end
		if type(t.GetChildren) == "function" then
			local kids = { pcall(t.GetChildren, t) }
			for i = 2, #kids do
				local kid = kids[i]
				if type(kid) == "table" then
					local name = (kid.GetDebugName and select(2, pcall(kid.GetDebugName, kid))) or ("child" .. (i - 1))
					Walk(kid, path .. ":" .. tostring(name), depth + 1)
				end
			end
		end
	end
	for _, root in ipairs(SCAN_ROOTS) do
		local fine, secure, who = pcall(issecurevariable, root)
		if fine and not secure then Note("_G." .. root, who) end
		local value = _G[root]
		if type(value) == "table" then Walk(value, root, 1) end
	end
	local total, parts = 0, {}
	for who, n in pairs(byAddon) do
		total = total + n
		parts[#parts + 1] = ("%s %d"):format(who, n)
	end
	table.sort(parts)
	Say(("  %s: %d tainted field(s) in %d looked at%s%s"):format(label, total, visited,
		total > 0 and ", by " .. table.concat(parts, ", ") or "", visited >= SCAN_MAX and " (cut at the limit)" or ""))
	-- (where: counts by the window's part, then the first few paths)
	local groups, order = {}, {}
	for _, path in ipairs(allPaths) do
		local part = path:match("^([^.:]+[.:][^.:]+)") or path
		if not groups[part] then groups[part] = 0; order[#order + 1] = part end
		groups[part] = groups[part] + 1
	end
	for _, part in ipairs(order) do Say(("    in %s: %d"):format(part, groups[part])) end
	for i = 1, math.min(#found, showMax or SCAN_SHOW) do Say(found[i]) end
	if total > math.min(#found, showMax or SCAN_SHOW) then
		Say(("    ... and %d more"):format(total - math.min(#found, showMax or SCAN_SHOW)))
	end
	return total, groups
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
	{ "the settings key in a fight (fight path, faked)", function()
		CloseSettings()
		if ns.OptionsOpenAfterFight then ns.OptionsOpenAfterFight(true) end
		ns.testFakeFight = true
		local ok, err = pcall(Cinematic_ToggleSettings)
		ns.testFakeFight = nil
		if not ok then Say("  toggle error: " .. tostring(err)) end
		return true
	end, function(hook0, chat0, hook1, chat1)
		local new = hook1 - hook0 + chat1 - chat0
		local waits = ns.OptionsOpenAfterFight and ns.OptionsOpenAfterFight(true)
		local shown = ns.OurSettingsShown and ns.OurSettingsShown()
		local pad = _G.SmartNavigation ~= nil
		Say(("  gamepad UI %s, page shown %s, waits for the fight's end %s, quiet mark %s"):format(
			pad and "there" or "not there", tostring(shown), tostring(waits), tostring(ns.settingsOpenedInFight)))
		-- (opened in the fight, gamepad UI or not: players want them there;
		-- with the gamepad UI marked so its blocked lines stay out of the box)
		Verdict(new == 0 and shown and not waits and (not pad or ns.settingsOpenedInFight),
			("blocked lines in the box +%d (0 wanted), window %s (open wanted), %s, quiet mark %s"):format(new,
				shown and "open" or "closed", waits and "waits for the fight's end" or "no wait",
				pad and (ns.settingsOpenedInFight and "set" or "NOT set") or "not needed"))
		if ns.SettingsOpenedInFight then ns.SettingsOpenedInFight(false) end
		CloseSettings()
	end },
	-- (A blocked call from the gamepad UI's own file, faked with a chunk of
	-- that name: kept out of the box only while the settings were opened in
	-- a fight, and in the box again after.)
	{ "the gamepad UI's blocked line, settings opened in a fight, then not", function()
		if not (ns.SettingsOpenedInFight and type(_G.DisplayInterfaceActionBlockedMessage) == "function") then return end
		local chunk = loadstring("local f = ... f()", "@Interface/AddOns/Blizzard_GamepadSmartNavigation/SmartNavigation.lua")
		run.muted0 = ns.quietSettingsBlocks
		ns.SettingsOpenedInFight(true)
		pcall(chunk, _G.DisplayInterfaceActionBlockedMessage)
		-- (the box adds the hook's entry a frame later: mark off after it)
		C_Timer.After(0.5, function()
			ns.SettingsOpenedInFight(false)
			run.hookMid = (ns.DevErrorCount(HOOK))
			pcall(chunk, _G.DisplayInterfaceActionBlockedMessage)
		end)
		return true
	end, function(hook0, _, hook1)
		local quiet = (run.hookMid or -1) - hook0
		local after = hook1 - (run.hookMid or hook1)
		local muted = ns.quietSettingsBlocks - (run.muted0 or 0)
		Verdict(quiet == 0 and after == 1 and muted >= 1,
			("marked: box +%d (0 wanted), skipped %d (1+ wanted); unmarked: box +%d (1 wanted)"):format(quiet, muted, after))
	end },
	{ "taint scan after the steps (settings, game menu, panel list, gamepad UI)", function()
		CloseSettings()
		return true
	end, function()
		run.info = run.info + 1
		TaintScan("verdict INFO: after the steps")
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
	-- (before any step opens the settings: what was already tainted this session)
	run.info = run.info + 1
	local ok, err = pcall(TaintScan, "verdict INFO: before the steps")
	if not ok then Say("  taint scan error: " .. tostring(err)) end
	C_Timer.After(0.2, function() Step(1) end)
end

-- /cine debug taintopen [ways]: which way of opening the settings leaves the
-- window's lists written by us (the taint that blocks every settings line when
-- Escape > Options opens it later in a fight). Each way gets a fresh /reload
-- (click the test's Reload button), a scan before (clean wanted), the open, a
-- scan after. "list" = fields in the left list (CategoryList), 0 wanted:
--   1 game      you open it: Escape, then Options (the control)
--   2 ours      ns.OpenOptions on two hub pages (Card Vision, then Chat: the
--               left-list fold runs), as the key, /cine and the minimap do
--   3 show      ShowUIPanel(SettingsPanel) from us, no page picked
--   4 category  Settings.OpenToCategory from us (the old way)
--   5 game+ours you open and close it first (the lists built by the game), then
--               ours as in 2: does our open taint lists the game built
--   6 fight     ours as in 2 and closed, then you start a fight and open
--               Escape > Options in it: blocked lines counted, 0 wanted (PASS/FAIL)
--               (7 opento+fight passed 2026-11-20 and became ns.PickSettingsCategory:
--               our picks go through Settings.OpenToCategory, so 6 tests that now)
-- No ways given: all six. "/cine debug taintopen 2 6": those only.
-- Into CinematicDB.taintOpenTestLog, a screenshot a way, a summary at the end.
-- Run again to stop it. Dev copy only.
local TAINT_WAYS = { "game", "ours", "show", "category", "game+ours", "fight" }
local taintWait, taintReloadButton, WatchSummary

local function TSay(text)
	local log = CinematicDB and CinematicDB.taintOpenTestLog
	if log then log[#log + 1] = ("%s %s"):format(date("%H:%M:%S"), text) end
end
local function TShot(what)
	local ok = pcall(function() Screenshot() end)
	TSay(("  screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end
local function PanelShown()
	local panel = _G.SettingsPanel
	return panel and panel:IsShown() and true or false
end
local function BlockedCount()
	return (ns.DevErrorCount(HOOK)) + (ns.DevErrorCount(CHAT))
end
-- (polls until check() is true, no time limit: you take as long as you like)
local function WaitFor(check, after)
	local token = {}
	taintWait = token
	local function Poll()
		if taintWait ~= token then return end
		if check() then return after() end
		C_Timer.After(0.25, Poll)
	end
	Poll()
end

local function TaintState() return CinematicDB and CinematicDB.taintOpenTest end

-- A scan: its total, and the left list's share of it.
local function Scan(label, show)
	local total, groups = TaintScan(label, show, TSay)
	return total or -1, groups and groups["SettingsPanel.CategoryList"] or 0
end

local function TaintStop(text)
	local state = TaintState()
	taintWait = nil
	if not state then return end
	CinematicDB.taintOpenTest = nil
	TSay("summary (tainted fields: all / in the left list; before: clean wanted):")
	for _, n in ipairs(state.picks) do
		local r = state.results[n]
		local line = r and ("before %d, after %d / list %d"):format(r.before or -1, r.after or -1, r.list or -1) or "not run"
		if r and r.game then line = line .. (", after your open %d / list %d"):format(r.game, r.gameList or -1) end
		if r and r.blocked then line = line .. (", blocked in the fight %d (0 wanted)"):format(r.blocked) end
		TSay(("  %d %s: %s"):format(n, TAINT_WAYS[n], line))
	end
	TSay(("%s: %d pass, %d fail"):format(text, state.pass or 0, state.fail or 0))
	ns.TestPrompt(("Taint open test %s. Say \"check log\"."):format(text), 12)
end

local function TaintClose()
	if PanelShown() and HideUIPanel and not InCombatLockdown() then pcall(HideUIPanel, _G.SettingsPanel) end
end

local function TaintNext(state)
	state.pos = state.pos + 1
	if state.pos > #state.picks then return TaintStop("done") end
	-- (ReloadUI from our code is blocked on Forever, a timer's or a click's
	-- (2026-11-20, both in the log): a secure button running /reload as a macro.)
	TSay("  waiting for the Reload button click")
	ns.TestPrompt(("Taint open test: click Reload for way %d."):format(state.picks[state.pos]), 3600)
	TaintClose()
	if not taintReloadButton then
		taintReloadButton = CreateFrame("Button", "CinematicTaintTestReload", UIParent,
			"SecureActionButtonTemplate, UIPanelButtonTemplate")
		taintReloadButton:SetFrameStrata("FULLSCREEN_DIALOG")
		taintReloadButton:SetSize(220, 44)
		taintReloadButton:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		taintReloadButton:SetText("Reload")
		taintReloadButton:SetAttribute("type", "macro")
		taintReloadButton:SetAttribute("macrotext", "/reload")
		-- (down or up as the game's own buttons, not both: two reloads)
		taintReloadButton:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
		taintReloadButton:SetScript("PreClick", function()
			TSay("  Reload clicked")
			TaintClose()
		end)
	end
	taintReloadButton:Show()
end

local function TaintAfterOpen(state, n, way)
	C_Timer.After(1.5, function()
		if TaintState() ~= state then return end
		TShot(way)
		local r = state.results[n]
		WatchSummary()
		r.after, r.list = Scan(("way %d %s, after the open"):format(n, way), 15)
		TaintClose()
		TaintNext(state)
	end)
end

-- (ours: two hub pages, so the left list's fold has a group to open and one
-- to fold, as it does when you go about the settings)
local function OurOpen(label, after)
	local ok, err = pcall(label == "show" and function() ShowUIPanel(_G.SettingsPanel) end
		or label == "category" and function() Settings.OpenToCategory(ns.settingsCategory:GetID()) end
		or function() ns.OpenOptions("Card Vision") end)
	if not ok then TSay("  open error: " .. tostring(err)) end
	if label == "show" or label == "category" then return after() end
	C_Timer.After(1, function()
		local fine, why = pcall(ns.OpenOptions, "Chat")
		if not fine then TSay("  open error: " .. tostring(why)) end
		after()
	end)
end

-- Who makes the left list again, and who picks pages: each call into the log
-- with its stack (the first 6 of each; the rest counted), and whether our
-- quiet pick ran and what it found. (2026-11-20: the list stayed tainted
-- with the quiet pick in; this says from where, instead of a guess.)
local watchCounts = {}
local function Watch(name, line)
	watchCounts[name] = (watchCounts[name] or 0) + 1
	local n = watchCounts[name]
	if n > 6 then return end
	local stack = debugstack and debugstack(3, 10, 0) or ""
	stack = stack:gsub("Interface[/\\]AddOns[/\\]", ""):gsub("\n$", ""):gsub("\n", "\n      ")
	TSay(("  call %s #%d (%s, in a fight %s)%s:\n      %s"):format(name, n, (_G.issecure and _G.issecure()) and "secure" or "ours",
		tostring(InCombatLockdown()), line and (" " .. line) or "", stack))
end
local function CatText(category)
	if type(category) ~= "table" then return tostring(category) end
	local name = category.GetName and category:GetName() or "?"
	local parent = category.GetParentCategory and category:GetParentCategory()
	return ("%s (open %s, parent %s open %s)"):format(tostring(name), tostring(category.IsExpanded and category:IsExpanded()),
		parent and tostring(parent.GetName and parent:GetName()) or "none",
		parent and tostring(parent.IsExpanded and parent:IsExpanded()) or "-")
end
local watching
local function WatchRebuilds()
	watchCounts = {}
	if watching then return end
	local panel = _G.SettingsPanel
	local list = panel and panel.GetCategoryList and panel:GetCategoryList()
	if not list then TSay("  watch: no category list") return end
	watching = true
	hooksecurefunc(list, "CreateCategories", function() Watch("CreateCategories") end)
	if list.SetCurrentCategory then
		hooksecurefunc(list, "SetCurrentCategory", function(_, c) Watch("list:SetCurrentCategory", CatText(c)) end)
	end
	if panel.SelectCategory then
		hooksecurefunc(panel, "SelectCategory", function(_, c) Watch("SelectCategory", CatText(c)) end)
	end
	if ns.PickSettingsCategory then
		hooksecurefunc(ns, "PickSettingsCategory", function(_, c) Watch("PickSettingsCategory (after)", CatText(c)) end)
	end
	TSay("  watch: hooked CreateCategories, SetCurrentCategory, SelectCategory, PickSettingsCategory")
end
function WatchSummary()
	local parts = {}
	for name, n in pairs(watchCounts) do parts[#parts + 1] = ("%s %d"):format(name, n) end
	table.sort(parts)
	TSay("  calls this way: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
end

local function TaintRunWay()
	local state = TaintState()
	if not state then return end
	local n = state.picks[state.pos]
	local way = n and TAINT_WAYS[n]
	if not way then return TaintStop("done") end
	if InCombatLockdown() then
		TSay("  in a fight: waiting for its end")
		return WaitFor(function() return not InCombatLockdown() end, TaintRunWay)
	end
	TSay(("--- way %d %s (%d of %d this run; game %s, gamepad UI %s, GamePadEnable %s) ---"):format(n, way, state.pos,
		#state.picks, tostring((select(4, GetBuildInfo()))), _G.SmartNavigation and "there" or "not there",
		tostring(GetCVar and GetCVar("GamePadEnable"))))
	TaintClose()
	local r = {}
	state.results[n] = r
	r.before = Scan(("way %d %s, before"):format(n, way), 5)
	WatchRebuilds()
	if way == "game" or way == "game+ours" then
		ns.TestPrompt(("Taint open test, way %d: press Escape, then click Options."):format(n), 3600)
		WaitFor(PanelShown, function()
			ns.TestPrompt("Taint open test: got it, just watch.", 2)
			if way == "game" then return TaintAfterOpen(state, n, way) end
			C_Timer.After(1.5, function()
				if TaintState() ~= state then return end
				r.game, r.gameList = Scan(("way %d, after your open (game built it)"):format(n), 5)
				ns.TestPrompt("Taint open test: now press Escape to close the settings.", 3600)
				WaitFor(function() return not PanelShown() end, function()
					ns.TestPrompt("Taint open test: got it, just watch.", 2)
					C_Timer.After(1, function()
						if TaintState() ~= state then return end
						OurOpen("ours", function() TaintAfterOpen(state, n, way) end)
					end)
				end)
			end)
		end)
	elseif way == "fight" then
		ns.TestPrompt(("Taint open test, way %d: opening our settings. Just watch."):format(n), 3)
		OurOpen("ours", function()
			C_Timer.After(1.5, function()
				if TaintState() ~= state then return end
				WatchSummary()
				r.after, r.list = Scan(("way %d, after our open"):format(n), 15)
				TaintClose()
				ns.TestPrompt("Taint open test: start a fight (attack a training dummy or any enemy). The test waits.", 3600)
				WaitFor(InCombatLockdown, function()
					local blocked0 = BlockedCount()
					TSay(("  fight started, box has %d blocked entries"):format(blocked0))
					watchCounts = {}
					ns.TestPrompt("Taint open test: in the fight now press Escape, then click Options.", 3600)
					WaitFor(PanelShown, function()
						local fight = InCombatLockdown()
						ns.TestPrompt("Taint open test: got it, keep fighting a moment.", 3)
						C_Timer.After(3, function()
							if TaintState() ~= state then return end
							TShot("fight")
							WatchSummary()
							r.blocked = BlockedCount() - blocked0
							if r.blocked > 0 then
								local _, stack = ns.DevErrorCount(HOOK)
								if stack then TSay("  newest blocked stack:\n" .. stack) end
							end
							local ok = r.blocked == 0 and fight
							if ok then state.pass = (state.pass or 0) + 1 else state.fail = (state.fail or 0) + 1 end
							TSay(("  verdict %s: Escape > Options in a fight: blocked lines +%d (0 wanted), opened %s"):format(
								ok and "PASS" or "FAIL", r.blocked, fight and "in the fight" or "NOT in a fight"))
							ns.TestPrompt("Taint open test: close the settings and end the fight. The test waits.", 3600)
							WaitFor(function() return not InCombatLockdown() and not PanelShown() end, function()
								TaintNext(state)
							end)
						end)
					end)
				end)
			end)
		end)
	else
		ns.TestPrompt(("Taint open test, way %d: %s. Just watch."):format(n, way), 3)
		OurOpen(way, function() TaintAfterOpen(state, n, way) end)
	end
end

function ns.TaintOpenTest(words)
	if TaintState() then return TaintStop("stopped") end
	if not (CinematicDB and ns.DevErrorCount) then return end
	if InCombatLockdown() then
		ns.Print("/cine debug taintopen: not in a fight.")
		return
	end
	local picks = {}
	for word in tostring(words or ""):gmatch("%d+") do
		local n = tonumber(word)
		if TAINT_WAYS[n] then picks[#picks + 1] = n end
	end
	if #picks == 0 then for n = 1, #TAINT_WAYS do picks[n] = n end end
	CinematicDB.taintOpenTestLog = {}
	-- (pos 0: the first way runs after the first reload, on a clean window)
	CinematicDB.taintOpenTest = { pos = 0, picks = picks, results = {}, pass = 0, fail = 0 }
	TSay("start: ways " .. table.concat(picks, " ") .. ", each after its own /reload")
	TaintNext(CinematicDB.taintOpenTest)
end

-- After each reload the test made: the next way, once the game has settled.
local taintEvents = CreateFrame("Frame")
taintEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
taintEvents:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	local state = TaintState()
	if not state or type(state.picks) ~= "table" then
		if state then CinematicDB.taintOpenTest = nil end -- (an older run's)
		return
	end
	if state.pos < 1 then state.pos = 1 end
	C_Timer.After(4, TaintRunWay)
end)

-- /cine debug fightopen: our settings opened in a REAL fight with the gamepad
-- UI (2026-11-20: players want them in fights, so they open there again and
-- the left list's blocked gamepad calls are kept out of the dev box). One run,
-- the test says each step on screen and waits for it (no time limit):
--   1 open     you start a fight; the test opens the Card Vision page (an
--              AddOns page: the left list moves sets, the case that once
--              tainted it). Window open, dev box +0 (PASS/FAIL); yellow chat
--              lines and how many the box skipped (INFO: what players see)
--   2 after    you close it and end the fight: the quiet mark is off (PASS/FAIL);
--              left list taint scan (INFO)
--   3 next     you start a new fight and open Escape > Options yourself: 0
--              blocked lines, in the box or in chat (PASS/FAIL; 1756 once)
-- Into CinematicDB.fightOpenTestLog, a screenshot a step. Run again to stop.
-- Dev copy only.
local fight, fightWait
local function FSay(text)
	local log = CinematicDB and CinematicDB.fightOpenTestLog
	if log then log[#log + 1] = ("%s %.1f %s"):format(date("%H:%M:%S"), fight and GetTime() - fight.at or 0, text) end
end
local function FShot(what)
	local ok = pcall(function() Screenshot() end)
	FSay(("  screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end
local function FVerdict(ok, text)
	if ok then fight.pass = fight.pass + 1 else fight.fail = fight.fail + 1 end
	FSay(("  verdict %s: %s"):format(ok and "PASS" or "FAIL", text))
end
-- (yellow lines that reach chat while the test runs: what a player sees)
local yellow, yellowHooked = 0, false
local function CountYellow(_, text)
	if fight and type(text) == "string" and not (issecretvalue and issecretvalue(text)) and text:find(LINE, 1, true) then
		yellow = yellow + 1
	end
end
local function FWait(check, after)
	local token = {}
	fightWait = token
	local function Poll()
		if fightWait ~= token or not fight then return end
		if check() then return after() end
		C_Timer.After(0.25, Poll)
	end
	Poll()
end
local function FDone(text)
	if not fight then return end
	local this = fight
	fight, fightWait = nil, nil
	local line = ("%s: %d pass, %d fail"):format(text, this.pass, this.fail)
	FSay(line)
	ns.TestPrompt(("Fight open test %s. Say \"check log\"."):format(line), 12)
end
local function Counts3()
	return BlockedCount(), yellow, ns.quietSettingsBlocks or 0
end

local function FightNext()
	FSay("--- 3 of 3: a new fight, Escape > Options opened by you ---")
	ns.TestPrompt("Fight open test: start ANOTHER fight. The test waits.", 3600)
	FWait(InCombatLockdown, function()
		local box0, yellow0 = Counts3()
		ns.TestPrompt("Fight open test: in the fight press Escape, then click Options.", 3600)
		FWait(PanelShown, function()
			local inFight = InCombatLockdown()
			ns.TestPrompt("Fight open test: got it, keep fighting a moment.", 3)
			C_Timer.After(3, function()
				if not fight then return end
				FShot("step 3")
				local box1, yellow1 = Counts3()
				FSay(("  in a fight %s, quiet mark %s"):format(tostring(inFight), tostring(ns.settingsOpenedInFight)))
				if box1 > box0 then
					local _, stack = ns.DevErrorCount(HOOK)
					if stack then FSay("  newest blocked stack:\n" .. stack) end
				end
				FVerdict(inFight and box1 == box0 and yellow1 == yellow0,
					("Escape > Options in a new fight: dev box +%d, yellow chat lines +%d (0 and 0 wanted)"):format(
						box1 - box0, yellow1 - yellow0))
				ns.TestPrompt("Fight open test: close the settings and end the fight. The test waits.", 3600)
				FWait(function() return not InCombatLockdown() and not PanelShown() end, function() FDone("done") end)
			end)
		end)
	end)
end

local function FightAfter()
	FSay("--- 2 of 3: settings closed, fight over ---")
	ns.TestPrompt("Fight open test: press Escape to close the settings, then end the fight. The test waits.", 3600)
	FWait(function() return not InCombatLockdown() and not PanelShown() end, function()
		C_Timer.After(0.5, function()
			if not fight then return end
			FVerdict(not ns.settingsOpenedInFight, ("quiet mark after the fight: %s (off wanted)"):format(
				ns.settingsOpenedInFight and "STILL ON" or "off"))
			local ok, err = pcall(TaintScan, "verdict INFO: after the fight", 10, FSay)
			if not ok then FSay("  taint scan error: " .. tostring(err)) end
			FightNext()
		end)
	end)
end

function ns.FightOpenTest()
	if fight then return FDone("stopped") end
	if not (CinematicDB and ns.DevErrorCount and ns.QuietSettingsBlock) then
		ns.Print("/cine debug fightopen: the dev error box isn't loaded.")
		return
	end
	if InCombatLockdown() then
		ns.Print("/cine debug fightopen: start it out of a fight.")
		return
	end
	if not yellowHooked then
		yellowHooked = true
		for i = 1, (NUM_CHAT_WINDOWS or 10) do
			local frame = _G["ChatFrame" .. i]
			if frame and frame.AddMessage then hooksecurefunc(frame, "AddMessage", CountYellow) end
		end
	end
	CinematicDB.fightOpenTestLog = {}
	fight = { at = GetTime(), pass = 0, fail = 0 }
	if PanelShown() and HideUIPanel then pcall(HideUIPanel, _G.SettingsPanel) end
	FSay(("start: %s (game %s), gamepad UI %s, GamePadEnable %s"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), _G.SmartNavigation and "there" or "not there",
		tostring(GetCVar and GetCVar("GamePadEnable"))))
	pcall(TaintScan, "verdict INFO: before the fight", 5, FSay)
	FSay("--- 1 of 3: our settings opened in a real fight ---")
	ns.TestPrompt("Fight open test: start a fight (attack a training dummy or any enemy). The test waits.", 3600)
	FWait(InCombatLockdown, function()
		local box0, yellow0, quiet0 = Counts3()
		ns.TestPrompt("Fight open test: in a fight, opening the settings. Just watch.", 3)
		local ok, err = pcall(ns.OpenOptions, "Card Vision")
		if not ok then FSay("  OpenOptions error: " .. tostring(err)) end
		C_Timer.After(2, function()
			if not fight then return end
			FShot("step 1")
			local box1, yellow1, quiet1 = Counts3()
			local shown = ns.ShownOptionsPage and ns.ShownOptionsPage()
			FSay(("  in a fight %s, page shown %q, quiet mark %s, waits for the fight's end %s"):format(
				tostring(InCombatLockdown()), tostring(shown), tostring(ns.settingsOpenedInFight),
				tostring(ns.OptionsOpenAfterFight and ns.OptionsOpenAfterFight())))
			fight.info = true
			FSay(("  verdict INFO: yellow chat lines +%d (what players see), skipped by the box %d"):format(
				yellow1 - yellow0, quiet1 - quiet0))
			if box1 > box0 then
				local _, stack = ns.DevErrorCount(HOOK)
				if stack then FSay("  newest blocked stack:\n" .. stack) end
			end
			FVerdict(shown == "Card Vision" and box1 == box0, ("page %s (Card Vision wanted), dev box +%d (0 wanted)"):format(
				tostring(shown), box1 - box0))
			FightAfter()
		end)
	end)
end
