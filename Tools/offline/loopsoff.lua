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

-- The settings pages made ahead (Options.lua's lazyPages) wait while
-- /cine debug loops measures (ns.loopAudit): their time swamped the loops
-- measured, 2026-11-20. Neither a new page started nor one under way stepped.
local made = 0
local log = ns.Log
ns.Log = function(kind, text, ...)
	if kind == "load" and type(text) == "string" and text:find("made when first needed %(ahead") then made = made + 1 end
	return log(kind, text, ...)
end
local stepper -- (the builder's frame, as its loop is set)
local setOnUpdate = ns.SetOnUpdate
ns.SetOnUpdate = function(frame, fn, ...)
	local info = debug.getinfo(2, "S")
	if fn and info and info.short_src:find("Options%.lua") then stepper = frame end
	return setOnUpdate(frame, fn, ...)
end
local ahead
for _, ticker in ipairs(tickers) do
	if ticker.from:find("Options%.lua") then ahead = ticker.fn end
end
-- (The HUD's page starts it as it's made: as on opening the settings.)
if not ahead and ns.MakeLazyPages then
	ns.MakeLazyPages("opened")
	for _, ticker in ipairs(tickers) do
		if ticker.from:find("Options%.lua") then ahead = ticker.fn end
	end
end
Check("settings pages: the made-ahead ticker found", ahead ~= nil)
if ahead then
	local function Tick(n) for _ = 1, n do pcall(ahead) end end
	ns.loopAudit = {}
	Tick(12)
	Check("settings pages: none started while loops measure", stepper == nil and made == 0,
		("stepper %s, made %d"):format(tostring(stepper ~= nil), made))
	ns.loopAudit = nil
	Tick(6)
	Check("settings pages: one starts once the measuring's over", stepper ~= nil)
	if stepper then
		local madeBefore = made
		ns.loopAudit = {}
		for _ = 1, 20 do
			local step = stepper._scripts.OnUpdate
			if step then pcall(step, stepper, 0.016) end
		end
		Check("settings pages: one under way waits while loops measure", made == madeBefore)
		ns.loopAudit = nil
		for _ = 1, 200 do
			local step = stepper._scripts.OnUpdate
			if not step then break end
			pcall(step, stepper, 0.016)
		end
		Check("settings pages: it carries on after", made > madeBefore, ("made %d"):format(made))
	end
end

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
