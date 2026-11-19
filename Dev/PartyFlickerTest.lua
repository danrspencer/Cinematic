-- /cine debug partyflicker [steps]: one run looking for party frames that
-- flicker (a player's report 2026-11-17, with DaylightUI among their addons).
-- Changes no settings. Watches every party frame it can find (the game's,
-- the raid-style ones and other addons' such as DaylightUI's) at every frame
-- drawn: its own alpha, its alpha on screen, shown or not, and our fade. Each
-- change goes to the log ("partyflicker"), and so does every SetAlpha an
-- addon makes on a frame we fade (with the line of code that made it) and
-- every one of ours, the raid aura settings (raidFramesDisplayBuffs...)
-- changing, a screenshot every 5 seconds and a verdict per step: flickers
-- (gone then back within a second) and how often its alpha was set back and
-- forth. "partyflicker 3": only that step. Typed again while running: stops.
-- (2026-11-19, after a run where DaylightUI dimmed with plain SetAlpha only:
-- its repaints are counted by kind, plain or SetAlphaFromBoolean (secret),
-- an addon's or ours logged only when the value changes, each party unit's
-- dead / ghost / in range logged as it changes, and a step 5 for a member
-- who's dead and far off, the player's clip. "partyflicker 35": those two.)
-- Dev copy only (CinematicDev.toc).
local _, ns = ...

local READ = 5          -- seconds to read the step
local SHOT_EVERY = 5    -- seconds between screenshots
local FLICKER_GAP = 1   -- gone and back within this many seconds = a flicker
local MAX_LINES = 400   -- change lines logged per step (counted past that)
local GROUPS = { party = true, raidplayers = true, raidpets = true }
local CVARS = { raidframesdisplaybuffs = true, raidframesdisplaydebuffs = true, usecompactpartyframes = true,
	raidoptiondisplaypets = true }
local ADDONS = { "DaylightUI", "DaylightUI_UnitFrames", "ElvUI", "EllesmereUI", "EllesmereUIUnitFrames", "FlareUI",
	"Grid2", "VuhDo", "Cell", "ShadowedUnitFrames", "PitBull4", "Aptechka" }

local STEPS = {
	{ key = "still", length = 30, cine = false, say = "1/5 CINEMODE OFF: in a party, stand still, mouse away " ..
		"from your frames. Watch the party frames: do they blink?" },
	{ key = "cine", length = 30, cine = true, say = "2/5 CINEMODE ON: stand still, mouse away from your " ..
		"frames. Watch the party frames: do they blink?" },
	{ key = "range", length = 40, cine = true, say = "3/5 OUT OF RANGE: CineMode on, walk far from a party " ..
		"member (or have them walk off), then back. Watch their frame" },
	{ key = "fight", length = 40, cine = true, say = "4/5 FIGHT: CineMode on, start a fight with your party " ..
		"close by, keep it going. Watch the party frames" },
	{ key = "ghost", length = 60, cine = true, say = "5/5 DEAD: CineMode on, a party member dies far from you " ..
		"(or you die and release). Watch their frames: do they blink?" },
}

local run
local watcher = CreateFrame("Frame")
local function Log(text) ns.Log("partyflicker", text) end
local function Secret(value) return issecretvalue and issecretvalue(value) or false end
local function Num(value)
	if value == nil then return "nil" end
	if Secret(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
-- (Wrapped: C_Timer refused the game's Screenshot itself on WoW Forever.)
local function Shot() Screenshot() end
local function Loaded(name)
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
	local ok, yes = pcall(isLoaded, name)
	return ok and ns.Flag(yes) and true or false
end
local function Version(name)
	local meta = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
	local ok, version = pcall(meta, name, "Version")
	return ok and version or "?"
end

-- The first line of code outside Cinematic (and the game's hook glue) that
-- led here: who set the alpha.
local function Caller()
	local stack = debugstack(3, 12, 0) or ""
	for line in stack:gmatch("[^\n]+") do
		if not line:find("Cinematic", 1, true) and not line:find("%[C%]") and not line:find("hooksecurefunc") then
			return (line:gsub("^%s+", ""):gsub("Interface/AddOns/", ""):sub(1, 140))
		end
	end
	return "?"
end

-- A frame's unit: its key, or the secure attribute (oUF and the like).
local function UnitOf(frame)
	local unit = rawget(frame, "unit") or rawget(frame, "displayedUnit")
	if type(unit) ~= "string" and frame.GetAttribute then
		local ok, value = pcall(frame.GetAttribute, frame, "unit")
		unit = ok and value or nil
	end
	return (type(unit) == "string" and not Secret(unit)) and unit or nil
end

local function Label(frame)
	local ok, name = pcall(frame.GetDebugName, frame)
	return (ok and type(name) == "string") and name or tostring(frame)
end

-- Every party frame: the ones we fade as party or raid members, the game's
-- by name, and any other named frame showing a party unit (an addon's we may
-- not know).
local function AddWatch(frame, entry)
	if type(frame) ~= "table" or type(frame.GetAlpha) ~= "function" or run.watched[frame] then return end
	if frame.IsForbidden and frame:IsForbidden() then return end
	run.watched[frame] = { frame = frame, entry = entry, label = Label(frame) }
	run.count = run.count + 1
	if entry then run.entries[entry] = run.watched[frame] end
end

local function FindFrames()
	for _, entry in ipairs(ns.managed or {}) do
		if GROUPS[entry.group] then AddWatch(entry.frame, entry) end
	end
	for i = 1, 4 do AddWatch(_G["PartyMemberFrame" .. i]) end
	for i = 1, 5 do AddWatch(_G["CompactPartyFrameMember" .. i]) end
	local holder = _G.PartyFrame
	if holder and not (holder.IsForbidden and holder:IsForbidden()) then
		for _, child in ipairs({ holder:GetChildren() }) do
			if child ~= _G.CompactPartyFrame and UnitOf(child) then AddWatch(child) end
		end
	end
	if run.scanned then return end
	run.scanned = true
	-- (Once: other addons' party frames, by a party unit on a named frame.)
	for name, value in pairs(_G) do
		if type(name) == "string" and type(value) == "table" and not name:find("^Cinematic")
			and name:lower():find("party", 1, true) and type(value.GetObjectType) == "function" then
			local ok, kind = pcall(value.GetObjectType, value)
			if ok and (kind == "Button" or kind == "Frame") then
				local unit = UnitOf(value)
				if unit and unit:find("^party%d") then AddWatch(value) end
			end
		end
	end
end

-- (Every SetAlpha an addon makes on a frame we fade, and every one of ours:
-- through the alpha trace's hook, which stays as it was.)
local function Trace(entry, what, value)
	local step = run and run.step
	local watch = step and step.started and not step.skip and run.entries[entry]
	local now = GetTime()
	if not watch or now - step.at < READ then return end
	if what == "ours" then
		step.ours = (step.ours or 0) + 1
	else
		step.theirs = (step.theirs or 0) + 1
		local kind = what == "SetAlphaFromBoolean" and "secret" or "plain"
		step[kind] = (step[kind] or 0) + 1
		watch[kind] = (watch[kind] or 0) + 1
		-- (Ours straight after theirs, again and again: a tug of war.)
		if watch.lastOurs and now - watch.lastOurs < 0.05 then step.tugs = (step.tugs or 0) + 1 end
	end
	if what == "ours" then watch.lastOurs = now end
	-- (Logged when it changes: the same value 5 times a second filled the log.)
	local said = what .. " " .. Num(value)
	if watch["last" .. (what == "ours" and "Ours" or "Theirs")] == said then return end
	watch["last" .. (what == "ours" and "Ours" or "Theirs")] = said
	step.lines = (step.lines or 0) + 1
	if step.lines <= MAX_LINES then
		Log(("%s %.2fs %s %s %s (fade %s, base %s)%s"):format(step.key, now - step.at - READ, watch.label, what,
			Num(value), Num(entry.alpha), Num(entry.baseAlpha), what == "ours" and "" or (" by " .. Caller())))
	end
end

-- Each party unit's state (dead, ghost, connected, in range), logged as it
-- changes; a secret answer says so.
local function Ask(fn, ...)
	if type(fn) ~= "function" then return "?" end
	local ok, a, b = pcall(fn, ...)
	if not ok then return "error" end
	if Secret(a) then return "secret" end
	if b ~= nil and not Secret(b) and b ~= true then return "unchecked" end
	return tostring(a)
end
local function SampleUnits(step, now)
	run.unitState = run.unitState or {}
	for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
		if UnitExists(unit) then
			local state = ("dead %s, ghost %s, connected %s, in range %s"):format(Ask(UnitIsDead, unit),
				Ask(UnitIsGhost, unit), Ask(UnitIsConnected, unit),
				unit == "player" and "-" or Ask(UnitInRange, unit))
			if state ~= run.unitState[unit] then
				run.unitState[unit] = state
				Log(("%s %.2fs unit %s: %s"):format(step.key, now - step.at - READ, unit, state))
			end
		end
	end
end

-- One look at each frame, every frame drawn.
local function Sample(step, now)
	for frame, watch in pairs(run.watched) do
		local okA, alpha = pcall(frame.GetAlpha, frame)
		local okE, drawn = pcall(frame.GetEffectiveAlpha, frame)
		local visible = frame:IsVisible() and true or false
		local entry = watch.entry
		local state = ("%s, alpha %s, drawn %s, unit %s%s"):format(visible and "shown" or "hidden",
			okA and Num(alpha) or "?", okE and Num(drawn) or "?", tostring(UnitOf(frame)),
			entry and (", fade %s, applied %s"):format(Num(entry.alpha), Num(entry.applied)) or ", not faded by us")
		if state ~= watch.last then
			if watch.last then step.changes = (step.changes or 0) + 1 end
			watch.last = state
			step.lines = (step.lines or 0) + 1
			if step.lines <= MAX_LINES then
				Log(("%s %.2fs %s %s"):format(step.key, now - step.at - READ, watch.label, state))
			end
		end
		-- (Up: shown and drawn over a fifth; secret counts as up, and so does
		-- none at all: a frame under a secret alpha gets no effective alpha,
		-- the game's raid-style party frames on Forever. A flicker: gone then
		-- back within FLICKER_GAP.)
		local up = visible and (not okE or type(drawn) ~= "number" or Secret(drawn) or drawn > 0.2)
		if watch.up ~= nil and up ~= watch.up then
			if up and watch.downAt and now - watch.downAt <= FLICKER_GAP then
				step.flickers = (step.flickers or 0) + 1
				watch.flickers = (watch.flickers or 0) + 1
				Log(("%s FLICKER %d: %s back after %.2fs"):format(step.key, step.flickers, watch.label,
					now - watch.downAt))
			elseif not up then
				watch.downAt = now
			end
		end
		watch.up = up
	end
end

local function Verdict(step)
	if step.skip then return ("%s: SKIPPED, %s"):format(step.key, step.skip) end
	if run.count == 0 then return ("%s: FAILED, no party frames found (in a party?)"):format(step.key) end
	local fight = step.spec.key ~= "fight" and step.fighting and ", a fight came in" or ""
	local churn = ("addon SetAlpha %d (plain %d, secret %d), ours %d, back to back %d, state changes %d"):format(
		step.theirs or 0, step.plain or 0, step.secret or 0, step.ours or 0, step.tugs or 0, step.changes or 0)
	if (step.flickers or 0) > 0 then
		return ("%s: FLICKERED %d times (%s%s)"):format(step.key, step.flickers, churn, fight)
	end
	if (step.tugs or 0) > 20 then
		return ("%s: NO FLICKER SEEN, but alpha set back and forth (%s%s)"):format(step.key, churn, fight)
	end
	return ("%s: PASS, steady (%s%s), %d screenshots"):format(step.key, churn, fight, step.shots or 0)
end

local function Finish(stopped)
	if not run then return end
	run.watcher:SetScript("OnUpdate", nil)
	run.watcher:UnregisterAllEvents()
	ns.AlphaTrace = run.oldTrace
	ns.Print(("Party flicker test %s"):format(stopped and "stopped" or "done"))
	for _, step in ipairs(run.done) do
		local verdict = Verdict(step)
		Log("verdict " .. verdict)
		ns.Print("  " .. verdict)
	end
	for _, watch in pairs(run.watched) do
		if watch.flickers then Log(("frame %s flickered %d times"):format(watch.label, watch.flickers)) end
		if watch.plain or watch.secret then
			Log(("frame %s repainted by its addon: plain %d, secret %d"):format(watch.label, watch.plain or 0,
				watch.secret or 0))
		end
	end
	ns.PadTestBox(stopped and "Test stopped." or "Test done.", "/reload, then say: check log", 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
	run = nil
end

local function OnUpdate()
	local now = GetTime()
	if not run.step then
		run.index = run.index + 1
		local spec = run.steps[run.index]
		if not spec then return Finish(false) end
		local step = { key = spec.key, at = now, spec = spec }
		if not IsInGroup() then
			step.skip = "not in a party"
			Log(("%s skipped: %s"):format(step.key, step.skip))
		end
		run.step, run.done[#run.done + 1] = step, step
	end
	local step = run.step
	local spec = step.spec
	if step.skip then
		ns.PadTestBox(spec.say, "SKIPPED: " .. step.skip, 1, 0.3, 0.3)
		if now - step.at >= 4 then run.step = nil end
		return
	end
	-- (Waiting on CineMode as the step wants it: the clock starts after.)
	local cine = ns.lastCinematic and true or false
	if not step.started then
		if cine ~= spec.cine then
			step.at = now
			ns.PadTestBox(spec.say, spec.cine and "waiting: turn CineMode ON" or "waiting: turn CineMode OFF",
				1, 0.82, 0)
			return
		end
		step.started = true
		step.at = now
		FindFrames()
		-- (Each step logs its first values again.)
		for _, watch in pairs(run.watched) do watch.lastTheirs, watch.lastOurs = nil, nil end
		run.unitState = nil
		Log(("%s start: %d frames watched, CineMode %s, party frames %s"):format(step.key, run.count,
			tostring(cine), ns.RaidStyleParty and (ns.RaidStyleParty() and "raid style" or "normal") or "?"))
	end
	local left = READ + spec.length - (now - step.at)
	if now - step.at < READ then
		ns.PadTestBox(spec.say, ("GET READY: starts in %d"):format(math.ceil(READ - (now - step.at))), 1, 0.82, 0)
		return
	end
	ns.PadTestBox(spec.say, ("RECORDING: %d sec left%s"):format(math.ceil(left),
		step.flickers and (", FLICKERS: %d"):format(step.flickers) or ""), 0.2, 1, 0.2)
	step.fighting = step.fighting or InCombatLockdown()
	-- (New frames as the group changes: a cheap look each second.)
	if now - (run.foundAt or 0) >= 1 then
		run.foundAt = now
		FindFrames()
	end
	Sample(step, now)
	if now - (step.unitsAt or 0) >= 0.25 then
		step.unitsAt = now
		SampleUnits(step, now)
	end
	if now - (step.shotAt or 0) >= SHOT_EVERY then
		step.shotAt = now
		step.shots = (step.shots or 0) + 1
		Log(("%s screenshot %d at %s"):format(step.key, step.shots, date("%H:%M:%S")))
		pcall(Shot)
	end
	if left <= 0 then run.step = nil end
end

local function OnEvent(_, event, name, value)
	if event == "CVAR_UPDATE" and type(name) == "string" and CVARS[name:lower()] then
		Log(("setting %s = %s%s"):format(name, tostring(value), run.step and (" (step " .. run.step.key .. ")") or ""))
	elseif event == "GROUP_ROSTER_UPDATE" then
		Log(("group changed: %d members%s"):format(GetNumGroupMembers(), run.step and (" (step " .. run.step.key .. ")") or ""))
	end
end

function ns.PartyFlickerTest(only)
	if run then return Finish(true) end
	local steps = {}
	if type(only) == "string" then
		for number in only:gmatch("%d") do
			if STEPS[tonumber(number)] then steps[#steps + 1] = STEPS[tonumber(number)] end
		end
	end
	if #steps == 0 then steps = STEPS end
	run = { steps = steps, index = 0, done = {}, watched = {}, entries = {}, count = 0 }
	Log(("start: %d steps, client %s, in group %s (%d)"):format(#steps,
		ns.isRetail and "retail" or "Forever/Classic", tostring(IsInGroup()), GetNumGroupMembers()))
	local addons = {}
	for _, name in ipairs(ADDONS) do
		if Loaded(name) then addons[#addons + 1] = name .. " " .. Version(name) end
	end
	Log("frame addons: " .. (#addons > 0 and table.concat(addons, ", ") or "none"))
	for cvar in pairs(CVARS) do
		local value = GetCVar(cvar)
		if value ~= nil then Log(("setting %s = %s at start"):format(cvar, value)) end
	end
	run.oldTrace = ns.AlphaTrace
	local old = run.oldTrace
	ns.AlphaTrace = function(entry, what, value)
		if old then old(entry, what, value) end
		pcall(Trace, entry, what, value)
	end
	run.watcher = watcher
	run.watcher:RegisterEvent("CVAR_UPDATE")
	run.watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	run.watcher:SetScript("OnEvent", OnEvent)
	run.watcher:SetScript("OnUpdate", function()
		local ok, err = pcall(OnUpdate)
		if not ok then
			Log("error: " .. tostring(err))
			ns.Print("Party flicker test error: " .. tostring(err))
			Finish(true)
		end
	end)
	ns.Print(("Party flicker test: %d steps, follow the box (type it again to stop)"):format(#steps))
end
