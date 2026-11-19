-- /cine debug hvplates: one run checking Heal Vision's Nameplates tick in
-- CineMode (2026-11-19: CineMode kept strangers' plates off, so it showed
-- nothing on them; now the tick keeps friendly plates on and up, the Don't
-- fade parts follow CineMode's Names rows, and it's off in capital cities).
-- Steps in the big test box (Frames.lua's ns.PadTestBox), each waiting for
-- what it asks, with no time limit (type it again to end there):
--   1 healthy     open world near friendly players, CineMode on: their
--                 plates on and held up whole, health bars faded, names at
--                 CineMode's level (nothing over healthy strangers)
--   2 everyone    the test sets Damage's line to 100% for a moment: every
--                 friendly player counts as hurt, their bars show in full
--   3 city        in a capital city: the tick lets go, plates back to
--                 CineMode's rows
-- The test turns the tick on itself, sets Don't fade to the name only, and
-- puts those and the line back after (a /reload too). Each check logs PASS or FAIL with what it read, and a
-- screenshot per step. Into CinematicDB.healPlatesLog. Dev copy only
-- (CinematicDev.toc).
local _, ns = ...

local SETUP = 6 -- seconds before the first step
local SETTLE = 3 -- seconds for plates and settings to follow
local MAX_PLATES = 8 -- friendly plates logged per step

local run -- { at, index, phase, phaseAt, pass, fail, said }

local function Say(text)
	local log = CinematicDB and CinematicDB.healPlatesLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Check(what, ok, detail)
	if ok then run.pass = run.pass + 1 else run.fail = run.fail + 1 end
	Say(("  %s %s: %s"):format(ok and "PASS" or "FAIL", what, detail))
end

-- The tick and Damage's line as they were: put back at the end, or after a
-- /reload cut the run short.
-- Damage's line and opacity as Heal Vision reads them: the role's own when
-- your role has its own settings (ns.HealVisionSetting), first run's lesson.
local function RoleKey(key)
	local saved = CinematicDB and CinematicDB.healPlatesRestore
	if saved and saved.keys and saved.keys[key] then return saved.keys[key] end
	local role = ns.PlayerRole and ns.PlayerRole()
	if role and ns.db["healVisionOwn_" .. role] then return key .. "_" .. role end
	return key
end
local function BelowKey() return RoleKey("healVisionShowBelow") end
local function AlphaKey() return RoleKey("healVisionMinAlpha") end

local function PutBack()
	local saved = CinematicDB and CinematicDB.healPlatesRestore
	if not (saved and ns.db) then return end
	ns.db.healVisionPlates = saved.plates
	-- (Keys as saved at the start; a run from before they were saved wrote
	-- the shared ones.)
	local keys = saved.keys or { healVisionShowBelow = "healVisionShowBelow", healVisionMinAlpha = "healVisionMinAlpha" }
	ns.db[keys.healVisionShowBelow] = saved.below
	if saved.minAlpha ~= nil then ns.db[keys.healVisionMinAlpha] = saved.minAlpha end
	for key, value in pairs(saved.keep or {}) do ns.db[key] = value end
	CinematicDB.healPlatesRestore = nil
	if ns.ApplyHealVisionPlates then ns.ApplyHealVisionPlates() end
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	C_Timer.After(1, PutBack)
end)

local function Plates()
	return C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
end
local function Plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end
local function Ask(fn, ...)
	local ok, value = pcall(fn, ...)
	return ok and Plain(value) or nil
end
local function UnitOf(plate)
	return plate and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
end
local function FriendlyPlayer(unit)
	return type(unit) == "string" and Ask(UnitIsPlayer, unit) and Ask(UnitIsFriend, "player", unit)
		and not Ask(UnitIsUnit, unit, "player") and true or false
end
local function Grouped(unit)
	return (UnitInParty and Ask(UnitInParty, unit)) or (UnitInRaid and Ask(UnitInRaid, unit) ~= nil) or false
end
-- Friendly players' plates up now: { unit, plate } each.
local function FriendPlates()
	local out = {}
	for _, plate in ipairs(Plates()) do
		local unit = UnitOf(plate)
		if FriendlyPlayer(unit) then out[#out + 1] = { unit = unit, plate = plate } end
	end
	return out
end

local function SetsLine()
	local p = ns.plates or {}
	local wants = p.friendWants or {}
	return ("place %s; held on: players %s, bars %s, minions %s; nameplateShowFriendlyPlayers %s, "
		.. "nameplateShowOnlyNameForFriendlyPlayerUnits %s; rows want players %s, bars %s, group %s; Heal Vision on here %s")
		:format(tostring(ns.PlateSuffix and ns.PlateSuffix() or "open world"),
		tostring(p.FRIEND_PLAYER_CVARS and p.FRIEND_PLAYER_CVARS.active),
		tostring(p.FRIEND_BODY_CVARS and p.FRIEND_BODY_CVARS.active),
		tostring(p.FRIEND_MINION_CVARS and p.FRIEND_MINION_CVARS.active),
		tostring(GetCVar("nameplateShowFriendlyPlayers")), tostring(GetCVar("nameplateShowOnlyNameForFriendlyPlayerUnits")),
		tostring(wants.players), tostring(wants.body), tostring(wants.groupRows),
		tostring(ns.HealVisionPlatesOn and ns.HealVisionPlatesOn()))
end

-- One plate's line: Effects' alphas (whole/body/name...) and what Heal
-- Vision holds on it, per part.
local function PlateLine(unit, plate)
	local alphas = "?"
	if ns.DescribePlateNameKept then
		local ok, text = pcall(ns.DescribePlateNameKept, unit, plate)
		alphas = ok and type(text) == "string" and text:match("alphas=(%S+)") or "unreadable"
	end
	local info = ns.HealVisionPlateInfo and ns.HealVisionPlateInfo(unit) or { parts = {} }
	local parts = {}
	for part, entry in pairs(info.parts) do
		parts[#parts + 1] = ("%s(%s)=%s"):format(part, entry.kept and "kept" or "faded", table.concat(entry.alphas, ","))
	end
	table.sort(parts)
	return ("%s%s: kind %s, health %s, curve %s, plate alphas %s, held %s, kept level %s, %s"):format(
		tostring(Ask(UnitName, unit)), Grouped(unit) and " (group)" or "", tostring(info.kind), tostring(info.health),
		tostring(info.curve), alphas, tostring(info.unit), tostring(info.keptLevel),
		#parts > 0 and table.concat(parts, " ") or "no layers held"), info, tonumber(alphas:match("^([%d%.]+)"))
end

-- Every value of a part's layers: all at most / at least a level (secret: unknown).
local function PartAlphas(info, part)
	local entry = info.parts[part]
	if not entry then return nil end
	local low, high, secret = math.huge, -math.huge, false
	for _, text in ipairs(entry.alphas) do
		local value = tonumber(text:match("^([%d%.%-]+)"))
		if value then
			low, high = math.min(low, value), math.max(high, value)
		else
			secret = true
		end
	end
	return low, high, secret
end

local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end

local function OpenWorld()
	local suffix = ns.PlateSuffix and ns.PlateSuffix()
	return suffix ~= "Cities" and suffix ~= "Instances" and suffix ~= "BGs"
end

-- The plates' checks for a step: held up whole, health bars by want ("faded"
-- or "shown"), kept parts at the kept level.
local function PlateChecks(health)
	Say("  " .. SetsLine())
	local list = FriendPlates()
	Check("friendly player plates up", #list > 0, ("%d of %d plates"):format(#list, #Plates()))
	local floor = tonumber(ns.db[AlphaKey()]) or 0
	for i, each in ipairs(list) do
		if i > MAX_PLATES then
			Say(("  (%d more not logged)"):format(#list - MAX_PLATES))
			break
		end
		local line, info, whole = PlateLine(each.unit, each.plate)
		Say("  " .. line)
		local who = tostring(Ask(UnitName, each.unit))
		Check(who .. ": Heal Vision holds the plate", info.unit == true, tostring(info.unit))
		Check(who .. ": plate up whole", whole and whole >= 0.99 or false, tostring(whole))
		-- (The Plate parts grid's level on the Health part's frames: plain, ours.
		-- At 0 the hurt's bars can't show, whatever Heal Vision sets inside.)
		local frames = {}
		local unitFrame = each.plate.UnitFrame
		for _, frame in ipairs(unitFrame and ns.PlatePartFrames and ns.PlatePartFrames(unitFrame, "Health") or {}) do
			local ok, alpha = pcall(frame.GetAlpha, frame)
			frames[#frames + 1] = ok and tonumber(Plain(alpha)) or -1
		end
		local lowest = math.huge
		for _, alpha in ipairs(frames) do lowest = math.min(lowest, alpha) end
		Check(who .. ": Health part frames at full (parts grid)", #frames > 0 and lowest >= 0.99,
			#frames > 0 and table.concat(frames, ",") or "none found")
		local low, high, secret = PartAlphas(info, "Health")
		if low == nil then
			Check(who .. ": health bar layers held", false, "none")
		elseif info.parts.Health.kept then
			Check(who .. ": health bar faded by health (not in Don't fade)", false, "kept")
		elseif health == "faded" then
			Check(who .. ": health bar faded (healthy)", secret or high <= floor + 0.05,
				("%s to %s (Damage opacity %.2f)%s"):format(low, high, floor, secret and ", some secret" or ""))
		else
			Check(who .. ": health bar shown (hurt)", secret or low >= 0.95,
				("%s to %s%s"):format(low, high, secret and ", some secret" or ""))
		end
		local level = info.keptLevel or 1
		local nameLow, nameHigh = PartAlphas(info, "Name")
		if nameLow ~= nil then
			Check(who .. ": name at CineMode's level", nameHigh <= level + 0.05,
				("%s to %s, kept level %.2f"):format(nameLow, nameHigh, level))
		else
			Say(("  %s: name not held (kept level %s: CineMode shows it in full, or Name isn't in Don't fade)")
				:format(who, tostring(info.keptLevel)))
		end
	end
end

-- Who sets the alpha of a held plate's Health and Level layers: each layer
-- hooked once (hooks stay; they count only while watching), callers by file
-- and line from the stack.
local hooked = setmetatable({}, { __mode = "k" })
local watch -- { [caller] = count } while watching
local function Caller()
	local stack = debugstack and debugstack(3, 4, 0) or ""
	for line in stack:gmatch("[^\n]+") do
		local where = line:match("([%w_]+%.lua:%d+)")
		if where then return where end
	end
	return (stack:match("^[^\n]*") or "?"):sub(1, 80)
end
local function WatchPlate(unit)
	local info = ns.HealVisionPlateInfo(unit)
	local count = 0
	for _, part in ipairs({ "Health", "Level" }) do
		local entry = info.parts[part]
		for _, layer in ipairs(entry and entry.layers or {}) do
			count = count + 1
			if not hooked[layer] then
				hooked[layer] = true
				hooksecurefunc(layer, "SetAlpha", function()
					if watch then
						local key = part .. " " .. Caller()
						watch[key] = (watch[key] or 0) + 1
					end
				end)
			end
		end
	end
	return count
end

local STEPS = {
	{ key = "healthy", ask = "Go to the OPEN WORLD (not a city or instance) near friendly PLAYERS, CineMode ON. "
		.. "Then stay still.",
		ready = function() return ns.lastCinematic and OpenWorld() and #FriendPlates() > 0 end,
		checks = function() PlateChecks("faded") end },
	{ key = "who-sets", ask = "Stay still: watching who sets one plate's health bar and level alpha.",
		start = function()
			watch = nil
			for _, each in ipairs(FriendPlates()) do
				local info = ns.HealVisionPlateInfo(each.unit)
				if info.parts.Health then
					run.watched = each.unit
					Say(("  watching %s: %d layers (Health, Level)"):format(tostring(Ask(UnitName, each.unit)),
						WatchPlate(each.unit)))
					watch = {}
					break
				end
			end
			if not watch then Say("  no held plate with a health bar to watch") end
		end,
		ready = function() return true end,
		checks = function()
			local lines = {}
			for key, count in pairs(watch or {}) do lines[#lines + 1] = ("%s x%d"):format(key, count) end
			table.sort(lines)
			Say("  SetAlpha callers in 3 s: " .. (#lines > 0 and table.concat(lines, "; ") or "none"))
			local others = 0
			for key, count in pairs(watch or {}) do
				if not key:find("HealVisionFrames", 1, true) then others = others + count end
			end
			Check("only Heal Vision sets those layers", watch ~= nil and others == 0,
				("%d calls from elsewhere"):format(others))
			watch = nil
		end },
	{ key = "everyone-hurt", ask = "Stay still: every friendly player now counts as hurt (Damage's line at 100%).",
		start = function()
			ns.db[BelowKey()] = 1
			ns.ApplyHealVisionPlates()
			Say("  Damage's line set to 100% for this step")
		end,
		ready = function() return ns.lastCinematic and #FriendPlates() > 0 end,
		checks = function()
			PlateChecks("shown")
			local saved = CinematicDB.healPlatesRestore
			ns.db[BelowKey()] = saved and saved.below
			ns.ApplyHealVisionPlates()
			Say("  Damage's line put back: " .. tostring(ns.db[BelowKey()]))
		end },
	{ key = "city", ask = "Now go into a CAPITAL CITY (hearth or walk), CineMode ON. Type the command again to end "
		.. "here if you can't.",
		ready = function() return ns.lastCinematic and ns.PlateSuffix and ns.PlateSuffix() == "Cities" end,
		checks = function()
			Say("  " .. SetsLine())
			Check("Heal Vision off in the city", not ns.HealVisionPlatesOn(), tostring(ns.HealVisionPlatesOn()))
			local held = 0
			for _, each in ipairs(FriendPlates()) do
				local info = ns.HealVisionPlateInfo(each.unit)
				if next(info.parts) then
					held = held + 1
					if held <= MAX_PLATES then Say("  still held: " .. (PlateLine(each.unit, each.plate))) end
				end
			end
			Check("no plate held in the city", held == 0, ("%d held of %d friendly plates"):format(held, #FriendPlates()))
			local p, wants = ns.plates, ns.plates.friendWants
			Check("friendly players' plates only as rows want", not p.FRIEND_PLAYER_CVARS.active
				or wants.players or wants.groupRows or wants.plateCards or false, SetsLine())
			Check("their bars only as rows want", not p.FRIEND_BODY_CVARS.active or wants.body or false, SetsLine())
		end },
}

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	PutBack()
	Say(("done: %d PASS, %d FAIL%s; tick %s and Damage's line %s put back"):format(run.pass, run.fail,
		done and "" or " (stopped early)", tostring(ns.db.healVisionPlates), tostring(ns.db[BelowKey()])))
	run = nil
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped. /reload, then say \"check log\".",
		"", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Box(text, sub, waiting)
	ns.PadTestBox(text, sub, waiting and 1 or 0.3, waiting and 0.82 or 1, waiting and 0 or 0.3)
end

local function Tick()
	local now = GetTime() - run.at
	if now < SETUP then
		Box("Heal Vision plates test. Out of a fight, CineMode ON. Follow the box: it waits for you at each step.",
			("Starts in %d"):format(math.ceil(SETUP - now)), true)
		return
	end
	if run.index == 0 then run.index, run.phase, run.phaseAt = 1, "wait", GetTime() end
	local step = STEPS[run.index]
	if not step then
		Finish(true)
		return
	end
	if run.phase == "wait" then
		if not run.said then
			run.said = true
			Say(("--- step %d: %s (CineMode %s, plates up %d) ---"):format(run.index, step.key,
				tostring(ns.lastCinematic), #Plates()))
			if step.start then step.start() end
		end
		if InCombatLockdown() then
			Box(("%d/%d: leave the fight first"):format(run.index, #STEPS), "WAITING FOR YOU", true)
		elseif step.ready() then
			run.phase, run.phaseAt = "settle", GetTime()
		else
			Box(("%d/%d: %s"):format(run.index, #STEPS, step.ask), "WAITING FOR YOU", true)
		end
		return
	end
	if run.phase == "settle" then
		if not step.ready() or InCombatLockdown() then
			Say("  undone before it settled: waiting again")
			run.phase = "wait"
			return
		end
		if GetTime() - run.phaseAt >= SETTLE then
			local ok, err = pcall(step.checks)
			if not ok then Say("  error in checks: " .. tostring(err)) end
			Say("  " .. Shot(("step %d %s"):format(run.index, step.key)))
			run.index, run.phase, run.phaseAt, run.said = run.index + 1, "wait", GetTime(), nil
		else
			Box(("%d/%d: %s"):format(run.index, #STEPS, step.ask), "HANDS OFF: checking", false)
		end
	end
end

function ns.HealPlatesTest()
	if run then
		Finish(false)
		return
	end
	if not (ns.HealVisionPlateInfo and ns.HealVisionPlatesOn) then
		ns.Print("heal plates test: Heal Vision's plate code isn't loaded")
		return
	end
	CinematicDB.healPlatesLog = {}
	CinematicDB.healPlatesRestore = { plates = ns.db.healVisionPlates }
	local keys = { healVisionShowBelow = BelowKey(), healVisionMinAlpha = AlphaKey() }
	CinematicDB.healPlatesRestore.keys = keys
	CinematicDB.healPlatesRestore.below = ns.db[keys.healVisionShowBelow]
	run = { at = GetTime(), index = 0, pass = 0, fail = 0 }
	ns.db.healVisionPlates = true
	-- (Don't fade as it comes, the name only, for the run: with Health ticked
	-- nothing fades by health, 2026-11-19's first run.)
	local kept, keep = {}, {}
	for _, part in ipairs(ns.HEAL_PLATE_PARTS or {}) do
		local key = "healVisionPlatesKeep" .. part
		if ns.db[key] then kept[#kept + 1] = part end
		keep[key] = ns.db[key]
		ns.db[key] = ns.DEFAULTS[key]
	end
	CinematicDB.healPlatesRestore.keep = keep
	-- (Damage's opacity at 0 for the run: healthy bars gone outright, plain
	-- to see on the screenshots, where the game hides the alphas.)
	CinematicDB.healPlatesRestore.minAlpha = ns.db[AlphaKey()]
	ns.db[AlphaKey()] = 0
	ns.ApplyHealVisionPlates()
	Say(("start: %s (game %s), Cinematic %s, CineMode %s, in group %s, plates up %d; Heal Vision page %s, tick was %s, "
		.. "Damage keys %s, line %s opacity %s, fade range %s, your don't fade: %s (Name only for the run)"):format(ns.isRetail and "retail" or "classic",
		tostring((select(4, GetBuildInfo()))), ns.Version and ns.Version() or "?", tostring(ns.lastCinematic),
		tostring(IsInGroup()), #Plates(), tostring(ns.Setting("handleHealVision")),
		tostring(CinematicDB.healPlatesRestore.plates), BelowKey() .. "/" .. AlphaKey(), tostring(ns.db[BelowKey()]),
		tostring(CinematicDB.healPlatesRestore.minAlpha) .. " (0 for the run)", tostring(ns.db.healVisionFadeRange),
		#kept > 0 and table.concat(kept, ", ") or "nothing"))
	Say("  " .. SetsLine())
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print("heal plates test: follow the box (type it again to stop)")
end
