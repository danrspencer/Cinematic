-- /cine debug offscreen: whether a plate pinned to the screen's edge (the
-- game's Show Offscreen Nameplates, held on where Emote Vision's cards or Heal
-- Vision need it, 2026-11-19) can be told from one in view. Combat Text
-- Style draws numbers on plates, so a hit on someone behind you shows at the
-- edge. Plates can't be measured (GetCenter: restricted), but anchor points
-- can be read on Forever (GetPoint): maybe an edge plate's differ. One run,
-- out of a fight, CineMode off (it waits for that, then turns Show Offscreen
-- on for the run and puts yours back, a /reload too):
--   1 in front   plates up in front of you, still: every readable value of
--                each plate
--   2 behind     turn your character around (it waits, no time limit, for
--                you to face the other way): the same values again for the
--                same units, now pinned to the edge
-- Then per unit, which values differ between the two. Into
-- CinematicDB.offscreenProbeLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETTLE = 2
local SAMPLES = 4
local TURNED = 2.4 -- radians your facing must change for step 2 (about 140 degrees)

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
		local ok, name = pcall(function() return value.GetName and value:GetName() end)
		return ok and name and tostring(name) or "frame"
	end
	return tostring(value)
end
-- Every return of a method, or its error.
local function Read(frame, method, ...)
	if not (frame and frame[method]) then return "-" end
	local out = { pcall(frame[method], frame, ...) }
	if not out[1] then return "error: " .. tostring(out[2]):match("[^:]*$"):sub(1, 50) end
	local parts = {}
	for i = 2, #out do parts[#parts + 1] = Show(out[i]) end
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

-- One plate's readings: [field] = text.
local function Readings(plate)
	local frame, bar = plate.UnitFrame, plate.UnitFrame and plate.UnitFrame.healthBar
	local r = {}
	r.points = Read(plate, "GetNumPoints")
	for i = 1, 2 do r["point" .. i] = Read(plate, "GetPoint", i) end
	r.center = Read(plate, "GetCenter")
	r.rect = Read(plate, "GetRect")
	r.scale = Read(plate, "GetScale")
	r.effScale = Read(plate, "GetEffectiveScale")
	r.alpha = Read(plate, "GetAlpha")
	r.shown = Read(plate, "IsShown")
	r.visible = Read(plate, "IsVisible")
	r.level = Read(plate, "GetFrameLevel")
	r.strata = Read(plate, "GetFrameStrata")
	r.clamped = Read(plate, "IsClampedToScreen")
	r.ufPoint = Read(frame, "GetPoint", 1)
	r.ufAlpha = Read(frame, "GetAlpha")
	r.ufScale = Read(frame, "GetScale")
	r.barPoint = Read(bar, "GetPoint", 1)
	r.barShown = Read(bar, "IsShown")
	local unit = plate.namePlateUnitToken
	local ok, visible = pcall(UnitIsVisible, unit or "none")
	r.unitVisible = ok and Show(visible) or "error"
	return r
end

local function Snapshot()
	local out = {}
	for _, plate in ipairs(Plates()) do
		local unit = plate.namePlateUnitToken
		local ok, guid = pcall(UnitGUID, unit or "none")
		if ok and guid and not Secret(guid) then
			local okName, name = pcall(UnitName, unit)
			out[guid] = { name = okName and not Secret(name) and name or "?", r = Readings(plate) }
		end
	end
	return out
end
local function Box(text, sub) ns.PadTestBox(text, sub or "", 1, 0.82, 0) end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	PutBack()
	if done then
		Say("--- compare: values that differ for the same unit, in front vs behind ---")
		local units = 0
		for guid, front in pairs(run.front) do
			local back = run.back[guid]
			if back then
				units = units + 1
				local diffs = {}
				for field, value in pairs(front.r) do
					if back.r[field] ~= value then diffs[#diffs + 1] = ("%s: %s -> %s"):format(field, value, back.r[field]) end
				end
				table.sort(diffs)
				Say(("  %s: %s"):format(front.name, #diffs > 0 and table.concat(diffs, "; ") or "nothing differs"))
			end
		end
		local gone = 0
		for guid in pairs(run.front) do if not run.back[guid] then gone = gone + 1 end end
		Say(("%d units in both, %d had no plate behind you (offscreen setting %s)"):format(units, gone,
			tostring(GetCVar("nameplateShowOffscreen"))))
	end
	Say(done and "done" or "stopped early")
	run = nil
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped.", "", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function LogSnapshot(label, snap)
	for _, entry in pairs(snap) do
		local fields = {}
		for field, value in pairs(entry.r) do fields[#fields + 1] = field .. "=" .. value end
		table.sort(fields)
		Say(("  %s %s: %s"):format(label, entry.name, table.concat(fields, ", ")))
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
		if count < 2 then
			Box("1/2: Stand where 2 or more mobs or players with plates are IN FRONT of you. Stay still.", "WAITING FOR YOU")
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
	run = { at = GetTime(), phase = "cine", phaseAt = GetTime(), samples = 0, front = {}, back = {} }
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
