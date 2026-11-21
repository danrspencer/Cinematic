-- Loops off with their page off (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/loopsoff.lua < /dev/null
-- A feature loop (ns.FeatureLoop) whose page is switched off runs no update
-- loop at all, even with that page's rows ticked; on again with the page.
-- Heal Vision's (2026-11-20): its rows ticked kept it going every frame
-- with the page off. Says PASS or FAIL per check.
-- (Optional first argument: another .toc to load, to run it on older code.)
-- (No group frames: the stand-in's stubs counted as members, which keep the
-- loop going to let them go.)
-- (The settings pages' builder: its once-a-second ticker kept, and nothing
-- casting or on a flight path, so it's quiet enough to build.)
local tickers = {}
-- luacheck: push ignore 122
local ns, wow = dofile("Tools/offline/load.lua")("forever", arg and arg[1], function()
	for _, name in ipairs({ "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer", "PartyMemberFrame1",
		"PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }) do
		rawset(_G, name, false)
	end
	for _, name in ipairs({ "UnitCastingInfo", "UnitChannelInfo", "UnitOnTaxi" }) do
		rawset(_G, name, function() return nil end)
	end
	rawset(_G, "GetUnitSpeed", function() return 0 end)
	C_Timer.NewTicker = function(_, fn)
		local info = debug.getinfo(2, "S")
		tickers[#tickers + 1] = { fn = fn, from = info and info.short_src or "?" }
		return { Cancel = function() end, IsCancelled = function() return false end }
	end
end)
-- luacheck: pop

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

-- A frame by the events only it listens to.
local function FrameWith(...)
	local want = { ... }
	for _, frame in ipairs(wow.frames) do
		local all = true
		for _, event in ipairs(want) do
			if not frame._events[event] then all = false break end
		end
		if all then return frame end
	end
end

-- Heal Vision's member-frame loop.
local heal = FrameWith("PLAYER_ROLES_ASSIGNED", "UNIT_IN_RANGE_UPDATE", "UNIT_CONNECTION")
Check("Heal Vision's watcher found", heal ~= nil)
if heal then
	local db = ns.db
	local function Running()
		ns.SyncFeatureLoops()
		return heal._scripts.OnUpdate ~= nil
	end
	db.healVisionInWorld = true
	db.handleHealVision = true
	Check("Heal Vision: row ticked, page on: loop runs", Running())
	db.handleHealVision = false
	Check("Heal Vision: row ticked, page off: no loop", not Running())
	ns.ApplyHealVisionFrames() -- (as the page's switch does)
	Check("Heal Vision: page off, after its apply: no loop", heal._scripts.OnUpdate == nil)
	db.handleHealVision = true
	ns.ApplyHealVisionFrames()
	Check("Heal Vision: page on again: loop at once", heal._scripts.OnUpdate ~= nil)
	-- (With its rule, the rows don't decide: no rule and no row, nothing.)
	local rules, rule = db.frameRules, db.frameRules and db.frameRules.healVision
	db.healVisionInWorld = false
	if rules then rules.healVision = nil end
	Check("Heal Vision: page on, no row or rule: no loop", not Running())
	if rules then rules.healVision = rule end
end

-- The settings pages aren't made ahead any more (Options.lua: lazyPages.StartAhead
-- isn't started; made in the background after each login it was 30% of the
-- addon's time for a minute, 2026-11-21). Each slow page is made when it's
-- first opened or searched. (Its waiting while /cine debug loops measures,
-- 2026-11-20, was checked here; it only applied to the made-ahead build.)
local madeAhead, madeOpened = 0, 0
local log = ns.Log
ns.Log = function(kind, text, ...)
	if kind == "load" and type(text) == "string" then
		if text:find("made when first needed %(ahead") then madeAhead = madeAhead + 1 end
		if text:find("made when first needed %(opened") then madeOpened = madeOpened + 1 end
	end
	return log(kind, text, ...)
end
local function AheadTicker()
	for _, ticker in ipairs(tickers) do
		if ticker.from:find("Options%.lua") then return ticker.fn end
	end
end
Check("settings pages: no made-ahead ticker at login", AheadTicker() == nil)
if ns.MakeLazyPages then
	ns.MakeLazyPages("opened")
	Check("settings pages: opening makes them there and then", madeOpened > 0 and madeAhead == 0,
		("opened %d, ahead %d"):format(madeOpened, madeAhead))
	Check("settings pages: still no made-ahead ticker after", AheadTicker() == nil)
end

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
