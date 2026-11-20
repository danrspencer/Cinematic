-- /cine debug offscreen: whether a plate pinned to the screen's edge (the
-- game's Show Offscreen Nameplates, held on where Emote Vision's cards or Heal
-- Vision need it, 2026-11-19) can be told from one in view. Combat Text
-- Style draws numbers on plates, so a hit on someone behind you shows at the
-- edge. Plates can't be measured (GetCenter: restricted).
-- Run 1 (Forever, 2026-11-20): GetPoint on the plate, its UnitFrame and
-- health bar errored too; only frame level differed (102 -> 101); and only one
-- unit matched, the others' GUIDs secret. So this one keys plates by the plate
-- frame itself (and its unit token), keeps the whole error text, and walks
-- every piece of each plate (children and regions, a few levels down), reading
-- each piece's points, size, shown, alpha and art: the health bar's
-- background texture's points were readable before (PlateRowLook.lua).
-- One run, out of a fight, CineMode off (it waits for that, then turns Show
-- Offscreen on for the run and puts yours back, a /reload too):
--   1 in front   plates up in front of you, still: every readable value of
--                each plate
--   2 behind     turn your character around (it waits, no time limit, for
--                you to face the other way): the same values again for the
--                same plates, now pinned to the edge
-- Then per plate, which values differ between the two, and each error text
-- once. Into CinematicDB.offscreenProbeLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETTLE = 2
local SAMPLES = 4
local TURNED = 2.4 -- radians your facing must change for step 2 (about 140 degrees)
local DEPTH = 3 -- levels of children walked under each plate
local MAX_PIECES = 80 -- pieces read per plate, at most

local run
local function Say(text)
	local log = CinematicDB and CinematicDB.offscreenProbeLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Secret(value) return issecretvalue and issecretvalue(value) end
local function Show(value)
	if Secret(value) then return "secret" end
	if type(value) == "number" then return ("%.1f"):format(value) end
	if type(value) == "table" then
		local ok, name = pcall(function() return value.GetDebugName and value:GetDebugName() or value:GetName() end)
		return ok and name and not Secret(name) and tostring(name) or "frame"
	end
	return tostring(value)
end
-- Every return of a method, or "error #n" (the text kept once in run.errors).
local function ErrorId(err)
	local text = tostring(err):gsub("^Interface[^:]*:%d+: ", ""):sub(1, 160)
	local id = run.errorIds[text]
	if not id then
		run.errors[#run.errors + 1] = text
		id = #run.errors
		run.errorIds[text] = id
	end
	return "error #" .. id
end
local function Read(frame, method, ...)
	if not (frame and frame[method]) then return nil end
	-- (Counted with select: a nil among the returns, GetPoint's relativeTo,
	-- would cut # short and lose the offsets after it.)
	local function Pack(...) return select("#", ...), { ... } end
	local count, out = Pack(pcall(frame[method], frame, ...))
	if not out[1] then return ErrorId(out[2]) end
	local parts = {}
	for i = 2, count do parts[#parts + 1] = Show(out[i]) end
	return #parts > 0 and table.concat(parts, " ") or "nil"
end

-- PutBack: your Show Offscreen as it was.
local function PutBack()
	local saved = CinematicDB and CinematicDB.offscreenProbeWas
	if saved == nil or InCombatLockdown() then return end
	pcall(SetCVar, "nameplateShowOffscreen", saved)
	CinematicDB.offscreenProbeWas = nil
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
local function Facing()
	local ok, facing = pcall(GetPlayerFacing)
	return ok and not Secret(facing) and facing or nil
end

-- One piece's readings into r, each field "<path>.<what>".
local PIECE_READS = { "GetNumPoints", "GetWidth", "GetHeight", "GetLeft", "GetTop", "GetAlpha",
	"GetEffectiveAlpha", "IsShown", "IsVisible", "GetScale", "GetFrameLevel", "IsRectValid", "IsClampedToScreen" }
local function ReadPiece(r, path, piece)
	for _, method in ipairs(PIECE_READS) do
		local value = Read(piece, method)
		if value then r[path .. "." .. method] = value end
	end
	local points = 0
	local ok, count = pcall(piece.GetNumPoints, piece)
	if ok and type(count) == "number" and not Secret(count) then points = count end
	for i = 1, math.max(points, 1) do r[path .. ".point" .. i] = Read(piece, "GetPoint", i) end
	local art = Read(piece, "GetAtlas") or Read(piece, "GetTexture")
	if art then r[path .. ".art"] = art end
end

-- Walks a plate: the plate, then its children and regions, by parent key
-- where they have one, else by place in the list.
local function Walk(r, path, frame, depth, seen)
	if seen.count >= MAX_PIECES or seen[frame] then return end
	seen[frame], seen.count = true, seen.count + 1
	ReadPiece(r, path, frame)
	if depth >= DEPTH then return end
	local function Each(method, kind)
		if not frame[method] then return end
		local list = { pcall(frame[method], frame) }
		if not table.remove(list, 1) then
			r[path .. "." .. method] = ErrorId(list[1])
			return
		end
		for i, child in ipairs(list) do
			local okKey, key = pcall(function() return child.GetParentKey and child:GetParentKey() end)
			local name = okKey and type(key) == "string" and not Secret(key) and key or (kind .. i)
			Walk(r, path .. "/" .. name, child, depth + 1, seen)
		end
	end
	Each("GetChildren", "c")
	Each("GetRegions", "r")
end

-- One plate's readings: [field] = text.
local function Readings(plate)
	local r = {}
	Walk(r, "plate", plate, 0, { count = 0 })
	-- (The pieces the first run read by name, in case the walk misses them.)
	local frame = plate.UnitFrame
	local bar = frame and frame.healthBar
	if bar and bar.bgTexture then ReadPiece(r, "named.healthBar.bgTexture", bar.bgTexture) end
	local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
	for _, check in ipairs({ "UnitIsVisible", "UnitInRange", "CheckInteractDistance" }) do
		local fn = _G[check]
		if fn then
			local ok, value = pcall(fn, unit or "none", check == "CheckInteractDistance" and 4 or nil)
			r["unit." .. check] = ok and Show(value) or ErrorId(value)
		end
	end
	return r
end

-- [plate frame] = { token, readings }: the plate frame itself is the key (a
-- plate stays with its unit while that unit has one; GUIDs can be secret).
local function Snapshot()
	local out = {}
	for _, plate in ipairs(Plates()) do
		out[plate] = { token = tostring(plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)), r = Readings(plate) }
	end
	return out
end
local function Count(snap)
	local n = 0
	for _ in pairs(snap) do n = n + 1 end
	return n
end
local function Box(text, sub) ns.PadTestBox(text, sub or "", 1, 0.82, 0) end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	PutBack()
	if done then
		Say("--- compare: values that differ for the same plate, in front vs behind ---")
		local both, gone = 0, 0
		local sameEverywhere = {}
		for plate, front in pairs(run.front) do
			local back = run.back[plate]
			if back and back.token == front.token then
				both = both + 1
				local diffs = {}
				for field, value in pairs(front.r) do
					local after = back.r[field]
					if after ~= value then
						diffs[#diffs + 1] = ("%s: %s -> %s"):format(field, value, tostring(after))
						sameEverywhere[field] = (sameEverywhere[field] or 0) + 1
					end
				end
				for field, value in pairs(back.r) do
					if front.r[field] == nil then diffs[#diffs + 1] = ("%s: nil -> %s"):format(field, value) end
				end
				table.sort(diffs)
				Say(("  %s: %d fields, %s"):format(front.token, Count(front.r),
					#diffs > 0 and table.concat(diffs, "; ") or "nothing differs"))
			else
				gone = gone + 1
			end
		end
		-- (A field that changed on every plate is the likeliest tell.)
		local always = {}
		for field, n in pairs(sameEverywhere) do
			if n == both then always[#always + 1] = field end
		end
		table.sort(always)
		Say(("changed on every plate (%d): %s"):format(both, #always > 0 and table.concat(always, ", ") or "none"))
		Say(("%d plates in both, %d in front had no plate behind you (or a new unit)"):format(both, gone))
	end
	for i, text in ipairs(run.errors) do Say(("error #%d: %s"):format(i, text)) end
	Say(done and "done" or "stopped early")
	run = nil
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped.", "", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

-- (Every field for the first 2 plates only: the compare covers the rest.)
local function LogSnapshot(label, snap)
	local logged = 0
	for _, entry in pairs(snap) do
		local fields = {}
		for field, value in pairs(entry.r) do fields[#fields + 1] = field .. "=" .. value end
		table.sort(fields)
		logged = logged + 1
		Say(("  %s %s (%d fields)%s"):format(label, entry.token, #fields,
			logged <= 2 and (": " .. table.concat(fields, ", ")) or ""))
	end
end

local function Tick()
	if InCombatLockdown() then
		Box("Leave the fight first.", "WAITING FOR YOU")
		return
	end
	local into = GetTime() - run.phaseAt
	if run.phase == "cine" then
		-- (CineMode holds Show Offscreen itself: off first, then ours for the run.)
		if ns.lastCinematic then
			Box("Turn CineMode OFF for this test.", "WAITING FOR YOU")
			return
		end
		CinematicDB.offscreenProbeWas = GetCVar("nameplateShowOffscreen")
		pcall(SetCVar, "nameplateShowOffscreen", "1")
		Say(("Show Offscreen was %s, now %s"):format(tostring(CinematicDB.offscreenProbeWas),
			tostring(GetCVar("nameplateShowOffscreen"))))
		run.phase, run.phaseAt = "front", GetTime()
		return
	end
	if run.phase == "front" then
		local count = #Plates()
		if count < 3 then
			Box("1/2: Stand where 3 or more mobs or players with plates are IN FRONT of you, close by. Stay still.",
				"WAITING FOR YOU")
			run.phaseAt = GetTime()
			return
		end
		if into < SETTLE then
			Box("1/2: In front of you. HANDS OFF: reading plates.")
			return
		end
		run.samples = run.samples + 1
		run.front = Snapshot()
		if run.samples >= SAMPLES then
			Say(("--- in front: %d plates, facing %s ---"):format(count, Show(Facing())))
			LogSnapshot("front", run.front)
			pcall(Screenshot)
			run.facing = Facing()
			run.phase, run.phaseAt, run.samples = "turn", GetTime(), 0
			if not run.facing then Say("note: facing unreadable: step 2 waits for 8 s instead") end
		end
		return
	end
	if run.phase == "turn" then
		local now = Facing()
		local turned
		if run.facing and now then
			local diff = math.abs(now - run.facing) % (2 * math.pi)
			if diff > math.pi then diff = 2 * math.pi - diff end
			turned = diff >= TURNED
		else
			turned = into >= 8
		end
		if not turned then
			Box("2/2: TURN AROUND so those plates are BEHIND you. Then stay still.", "WAITING FOR YOU")
			return
		end
		run.phase, run.phaseAt = "back", GetTime()
		return
	end
	if run.phase == "back" then
		if into < SETTLE then
			Box("2/2: Behind you. HANDS OFF: reading plates.")
			return
		end
		run.back = Snapshot()
		Say(("--- behind: %d plates, facing %s ---"):format(#Plates(), Show(Facing())))
		LogSnapshot("back", run.back)
		pcall(Screenshot)
		Finish(true)
	end
end

function ns.OffscreenProbe()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("offscreen probe: not in a fight")
		return
	end
	CinematicDB.offscreenProbeLog = {}
	run = { at = GetTime(), phase = "cine", phaseAt = GetTime(), samples = 0, front = {}, back = {},
		errors = {}, errorIds = {} }
	Say(("start: %s (game %s), Cinematic %s, CineMode %s"):format(ns.isRetail and "retail" or "classic",
		tostring((select(4, GetBuildInfo()))), ns.Version and ns.Version() or "?", tostring(ns.lastCinematic)))
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print("offscreen probe: follow the box (type it again to stop)")
end
