-- /cine debug aggro test: measures how far mobs really attack you from, to
-- tune the Nameplates rows' Near aggro range guess (Frames' ns.AggroRadius).
-- No call says where a mob is, but your own spot is readable (UnitPosition)
-- and your attacks' ranges are known: you target a red mob standing still and
-- walk straight at it. Each time it comes into reach of one of your attacks
-- (or the 28-yard interact distance) the spot is kept; when it attacks you,
-- the pull was at that attack's yards less how far you walked since, far
-- finer than the range steps alone. Each pull is saved (CinematicDB.
-- aggroSamples, every session) and the best fit of all of them shown: yards
-- at your level and per level of difference, against the guess's. The big
-- test box says what to do and what it sees. Typed again: stops. "/cine debug
-- aggro clear": forgets the pulls. Dev copy only (CinematicDev.toc).
local _, ns = ...

local run -- { ticker, mob = { guid, name, level, me, rings = { [yards] = in reach }, flips = { [yards] = spot }, done } }

local function Log(text) ns.Log("aggro", text) end
local function Plain(fn, ...)
	if not fn then return nil end
	local ok, value = pcall(fn, ...)
	if ok and not (issecretvalue and issecretvalue(value)) then return value end
end
local function Spot()
	local ok, north, west, _, instance = pcall(UnitPosition, "player")
	if ok and type(north) == "number" and type(west) == "number"
		and not (issecretvalue and (issecretvalue(north) or issecretvalue(west))) then
		return { north, west, instance }
	end
end
local function Apart(a, b)
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
end
local function Samples()
	ns.db.aggroSamples = ns.db.aggroSamples or {}
	return ns.db.aggroSamples
end

-- (The guess as Frames has it, for a level difference: mob's less yours.)
local function Guess(diff)
	local g = ns.AGGRO_GUESS
	return math.max(g.min, math.min(g.max, g.base + diff))
end

-- Best straight line through the pulls: yards = base + step * difference.
-- One level difference only: the step taken as 1, the base from the mean.
local function Fit()
	local list = Samples()
	local n = #list
	if n == 0 then return "no pulls yet" end
	local sx, sy, sxx, sxy, err = 0, 0, 0, 0, 0
	for _, s in ipairs(list) do
		local d = s.mob - s.me
		sx, sy, sxx, sxy = sx + d, sy + s.yards, sxx + d * d, sxy + d * s.yards
		err = err + (s.yards - Guess(d))
	end
	local spread = n * sxx - sx * sx
	local base, step
	if n >= 2 and spread > 0.001 then
		step = (n * sxy - sx * sy) / spread
		base = (sy - step * sx) / n
	else
		step = 1
		base = (sy - sx) / n
	end
	return ("%d pull%s: %.1f yd at your level, %+.2f yd per level (guess %d, +1); guess off by %+.1f yd on average%s"):format(
		n, n == 1 and "" or "s", base, step, ns.AGGRO_GUESS.base, err / n,
		spread > 0.001 and "" or " (all one level difference: pull mobs of other levels for the per-level step)")
end

-- The checks to walk through: each attack's yards on your bars (one spell
-- per yards), and 28 for the interact distance out of a fight.
local function Rings(unit)
	local spells, yards = ns.AggroRangeChecks()
	local rings = {}
	for _, id in ipairs(spells) do
		local y = yards[id]
		if y and y > 0 and rings[y] == nil then
			local reaches = ns.SpellReachesUnit(id, unit)
			if reaches ~= nil then rings[y] = reaches end
		end
	end
	if rings[28] == nil then
		local near = ns.InteractDistanceOf(unit, 4)
		if near ~= nil then rings[28] = near end
	end
	return rings
end
local function Sorted(rings)
	local list = {}
	for y in pairs(rings) do list[#list + 1] = y end
	table.sort(list)
	return list
end

local function Box(text, sub, r, g, b)
	ns.PadTestBox(text, sub or "(/cine debug aggro test again stops)", r, g, b)
end

local function Tick()
	local spot = Spot()
	if not spot then
		Box("Can't read where you are here.", "Try outdoors, out of a dungeon.", 1, 0.3, 0.3)
		return
	end
	local unit = "target"
	local guid = Plain(UnitGUID, unit)
	local reaction = Plain(UnitReaction, unit, "player")
	local usable = type(guid) == "string" and type(reaction) == "number" and reaction <= 3
		and ns.EnemyNPCRank(unit) ~= nil
	if not usable then
		Box("Target a red mob standing still, further than your longest attack, then walk straight at it.",
			Fit())
		return
	end
	local mob = run.mob
	if not mob or mob.guid ~= guid then
		local name = Plain(UnitName, unit)
		mob = { guid = guid, name = type(name) == "string" and name or "?", level = Plain(UnitLevel, unit),
			me = Plain(UnitEffectiveLevel or UnitLevel, "player"), rings = Rings(unit), flips = {} }
		run.mob = mob
		local list = Sorted(mob.rings)
		Log(("target %s, level %s, you %s; checks at %s yd; in reach of %s"):format(mob.name, tostring(mob.level),
			tostring(mob.me), table.concat(list, ", "), (function()
				local inside = {}
				for _, y in ipairs(list) do if mob.rings[y] then inside[#inside + 1] = y end end
				return #inside > 0 and table.concat(inside, ", ") or "none"
			end)()))
	end
	if mob.done then
		Box("Done with this one: kill it or run, then target the next.", mob.done)
		return
	end
	local after = Plain(UnitThreatSituation, "player", unit) ~= nil or Plain(UnitIsUnit, "targettarget", "player") == true
	if type(mob.level) ~= "number" or type(mob.me) ~= "number" or mob.level <= 0 then
		Box("Can't use this one (no level, or a skull).", "Target another red mob.", 1, 0.6, 0)
		return
	end
	local diff = mob.level - mob.me
	if not after then
		-- (Each check's reach turning on: the spot kept; off again, you backed
		-- off: forgotten.)
		local now = Rings(unit)
		for y, reaches in pairs(now) do
			if reaches and mob.rings[y] == false then
				mob.flips[y] = spot
				Log(("%s in reach of %d yd"):format(mob.name, y))
			elseif not reaches and mob.rings[y] then
				mob.flips[y] = nil
			end
			mob.rings[y] = reaches
		end
		local inside, outside
		for _, y in ipairs(Sorted(mob.rings)) do
			if mob.rings[y] then inside = inside or y else outside = y end
		end
		Box(("%s (level %d, you %d): walk straight at it."):format(mob.name, mob.level, mob.me),
			("Within %s yd, past %s yd. Guess: attacks at %d yd."):format(tostring(inside or "-"),
				tostring(outside or "-"), Guess(diff)))
		return
	end
	-- It came after you: the nearest check you walked into, less the walk since.
	local ring
	for y, at in pairs(mob.flips) do
		if mob.rings[y] and (not ring or y < ring) and at[3] == spot[3] then ring = y end
	end
	local nearest -- (the next check in, never reached: the pull was further than it)
	for _, y in ipairs(Sorted(mob.rings)) do
		if not mob.rings[y] and (not ring or y < ring) then nearest = y end
	end
	local result
	if ring then
		local walked = Apart(mob.flips[ring], spot)
		local yards = math.max(ring - walked, nearest or 0)
		local samples = Samples()
		samples[#samples + 1] = { mob = mob.level, me = mob.me, yards = math.floor(yards * 10 + 0.5) / 10,
			ring = ring, name = mob.name }
		result = ("%s attacked at %.1f yd (guess %d): %.1f yd in from %d yd"):format(mob.name, yards, Guess(diff),
			walked, ring)
		Log(result .. "; " .. Fit())
		Box(result, Fit(), 0.3, 1, 0.4)
	else
		result = ("%s attacked before you walked into reach of any check (past %s yd), or you started too close: not counted"):format(
			mob.name, tostring(nearest or "-"))
		Log(result)
		Box(result, Fit(), 1, 0.6, 0)
	end
	mob.done = result
end

function ns.AggroTest(arg)
	if arg == "clear" then
		if ns.db then ns.db.aggroSamples = nil end
		ns.Print("aggro test: pulls forgotten")
		return
	end
	if run then
		run.ticker:Cancel()
		run = nil
		local fit = Fit()
		Log("stopped: " .. fit)
		ns.Print("aggro test: " .. fit)
		ns.PadTestBox("Aggro test stopped.", fit, 1, 0.82, 0)
		C_Timer.After(15, function() if not run then ns.PadTestBoxHide() end end)
		return
	end
	run = {}
	local spells = ns.AggroRangeChecks()
	Log(("start: game %s, you level %s, %d attacks on your bars, %d pulls saved"):format(
		tostring((select(4, GetBuildInfo()))), tostring(Plain(UnitLevel, "player")), #spells, #Samples()))
	run.ticker = C_Timer.NewTicker(0.1, function()
		local ok, err = pcall(Tick)
		if not ok then Log("error: " .. tostring(err)) end
	end)
	ns.Print("aggro test: follow the box")
end
