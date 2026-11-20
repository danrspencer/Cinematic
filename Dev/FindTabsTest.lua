-- /cine debug findtabs: one run on /cine find landing on the wrong tab
-- (2026-11-20: /cine find row:plate:FriendlyNPCs opened the Nameplates page
-- on its Dungeons & raids tab, the glow where the Friendly tab's row would
-- be). Hands off: it runs /cine find on ids from the Nameplates and Names
-- icons' tabs, one after another, each from the tab the last one left. For
-- each: the tab saved before and after, what /cine find said, whether the
-- id's control is on screen (its frame visible, its page shown), and a
-- screenshot. Traced as it happens: every save of a page's picked tab
-- (SectionState.Save, with who called it) and every Nameplates or Names icon
-- pick (ns.PickPlatesIcon). A verdict per id: PASS when its control is
-- visible. Out of a fight. Into CinematicDB.findTabsLog. Dev copy only.
local _, ns = ...

local WAIT, SETUP = 1.5, 4 -- seconds
local CASES = {
	-- (First right after a /reload, the page not built yet: the player's way.
	-- The Dungeons & raids tab's dropdowns have no ids: none of them here.)
	{ id = "row:plate:FriendlyNPCs", where = "Nameplates, Friendly (page not built yet)" },
	{ id = "row:plate:EnemyNPCs", where = "Nameplates, Enemy" },
	{ id = "row:name:ServiceNPCs", where = "Names, Friendly NPCs" },
	{ id = "row:plate:FriendlyNPCs", where = "Nameplates, Friendly (from Names)" },
	{ id = "row:name:ServiceNPCs", where = "Names, Friendly NPCs (from Nameplates)" },
}

local run -- { at, index, caseAt, pass, fail, ticker }

local function Say(text)
	local log = CinematicDB and CinematicDB.findTabsLog
	if log then log[#log + 1] = ("%.2f %s"):format(run and GetTime() - run.at or 0, text) end
end

local function SavedTab()
	local open = ns.db and ns.db.sectionsOpen
	return tostring(open and open["Nameplates/tab"])
end

-- Who called: the first few lines of the stack below the hook, file:line only.
local function Caller()
	local stack = debugstack(3, 6, 0) or ""
	local lines = {}
	for file, line in stack:gmatch("([%w_]+%.lua)\"?%]?:(%d+)") do
		lines[#lines + 1] = file .. ":" .. line
		if #lines >= 5 then break end
	end
	return table.concat(lines, " < ")
end

-- The traces, put in once (they log only while a run is on).
local traced
local function Trace()
	if traced then return end
	traced = true
	local kit = ns.lowHealthKit and ns.lowHealthKit.SectionState
	if kit and kit.Save then
		local save = kit.Save
		kit.Save = function(section, open, ...)
			if run and type(section) == "table" and section.id == "Nameplates/tab" then
				Say(("    tab saved: %s -> %s (%s)"):format(tostring(section.open), tostring(open), Caller()))
			end
			return save(section, open, ...)
		end
	end
end

-- (ns.PickPlatesIcon is made as the Nameplates page is built, lazily: wrapped
-- once it's there, and again if it's made anew.)
local pickWrap
local function TracePick()
	local pick = ns.PickPlatesIcon
	if pick and pick ~= pickWrap then
		pickWrap = function(names, ...)
			if run then
				Say(("    icon picked: %s, tab before %s (%s)"):format(names and "Names" or "Nameplates", SavedTab(),
					Caller()))
			end
			local results = { pick(names, ...) }
			if run then Say("      tab after the pick: " .. SavedTab()) end
			return unpack(results)
		end
		ns.PickPlatesIcon = pickWrap
	end
end

local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Say(ok and ("  screenshot (%s) at %s"):format(what, date("%m%d%y_%H%M%S")) or "  screenshot failed")
end

local function Check(case)
	local entry = ns.FindEntryOf and ns.FindEntryOf(case.id)
	local frame = entry and entry.edges and entry.edges.top
	local page = entry and entry.page and entry.page.canvas
	local visible = frame and frame:IsVisible() and true or false
	Say(("  after: tab %s; control %s (shown flag %s, visible %s), its page %s shown %s"):format(SavedTab(),
		frame and "found" or "NOT in the index", tostring(frame and frame:IsShown()), tostring(visible),
		tostring(entry and entry.page and entry.page.key), tostring(page and page:IsVisible())))
	run[visible and "pass" or "fail"] = run[visible and "pass" or "fail"] + 1
	Say(("  %s %s: its control %s on screen"):format(visible and "PASS" or "FAIL", case.id,
		visible and "is" or "is NOT"))
	Shot(case.id)
end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	Say(("done: %d PASS, %d FAIL%s"):format(run.pass, run.fail, done and "" or " (stopped early)"))
	run = nil
	ns.TestPrompt(done and "Find test done. /reload, then say \"check log\"." or "Find test stopped.", 10)
end

local function Tick()
	if InCombatLockdown() then
		Say("stopped: a fight started")
		Finish(false)
		return
	end
	TracePick()
	local now = GetTime()
	if now - run.at < SETUP then return end
	local case = CASES[run.index]
	if case and not case.checked and now - run.caseAt >= WAIT then
		case.checked = true
		Check(case)
		return
	end
	if case and now - run.caseAt < WAIT + 0.5 then return end
	run.index = run.index + 1
	case = CASES[run.index]
	if not case then
		Finish(true)
		return
	end
	case.checked = nil
	run.caseAt = now
	Say(("--- %d/%d: /cine find %s (should open %s); tab before %s ---"):format(run.index, #CASES, case.id,
		case.where, SavedTab()))
	TracePick()
	local ok, text, pageName = pcall(ns.FindSetting, case.id)
	Say(("  /cine find said: %s"):format(ok and (tostring(text) .. " on " .. tostring(pageName))
		or ("error " .. tostring(text))))
end

function ns.FindTabsTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("find tabs test: not in a fight")
		return
	end
	Trace()
	CinematicDB.findTabsLog = {}
	run = { at = GetTime(), index = 0, caseAt = 0, pass = 0, fail = 0 }
	for _, case in ipairs(CASES) do case.checked = nil end
	Say(("start: %s (game %s), tab saved %s, traces: save %s, icon pick %s"):format(ns.isRetail and "retail" or
		"Forever", tostring((select(4, GetBuildInfo()))), SavedTab(), tostring(ns.lowHealthKit
		and ns.lowHealthKit.SectionState ~= nil), tostring(ns.PickPlatesIcon ~= nil and "now" or "once built")))
	ns.TestPrompt("Find test: hands off, it opens the settings by itself (about 15 sec). Run it right after a /reload.", 4)
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
end
