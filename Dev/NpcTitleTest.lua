-- /cine debug npctitle: one run on NPC titles going away up close (a player's
-- report, 2026-11-20: walking up to a profession trainer or vendor, the title
-- under its name goes). The guess: up close the game swaps the name over the
-- head for a nameplate, and a friendly NPC's plate carries the name only.
-- Out of a fight, standing 10 to 15 yards from a trainer or vendor in plain
-- view (outdoors), no target. The game's NPC names over heads held on the
-- whole run (as a fresh install has them), so there's a title to lose; your
-- moving closer done by the plate range instead of walking (5 yards: no
-- plate on it yet, 60: a plate). Steps on screen, a screenshot each:
--   1 far        friendly NPC plates on, range 5: name and title over the head
--   2 near       the same, range 60: its plate comes (the player's moment)
--   3 near, off  friendly NPC plates off, range 60: the title should stay
--   4 cine far   CineMode on, as 1 (Cinematic's own names rows decide now)
--   5 cine near  CineMode on, as 2 (Cinematic's title line under plates)
--   6 page far   CineMode on, the Nameplates and Names pages on (as a fresh
--                install has them: CineMode's own name-only plates), far
--   7 page near  the same, near: Service NPCs' titles on Cinematic's plates
-- (Steps 6 and 7 with your own Names and Nameplates rows: their Service NPCs
-- and Friendly NPCs ones and rules logged at the start. The pages' switches
-- put back as they were at the end.)
-- Every step's game settings held by sets of ours (ns.CVarSet: put back as
-- they let go, and after a /reload by the leftover pass); CineMode off at the
-- start and put back as it was. At the start: the game's plate and name
-- settings, which of our sets hold them, your values from before Cinematic
-- wrote them and its own (cvarsBefore / cvarsOurs), and your Names and
-- Nameplates rows for friendly and service NPCs. Each step, settled and at its
-- end: every NPC plate (pets and guardians left out): name, title as read,
-- plate and name drawn, Cinematic's title line. The title the game draws over
-- a head can't be read by addons: the screenshots settle that part. Into
-- CinematicDB.npcTitleLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETUP, STEP, SETTLE, CINE_SETTLE = 10, 8, 2, 3 -- seconds
local CVARS = { "nameplateShowFriendlyNPCs", "nameplateShowAll", "nameplateMaxDistance",
	"SoftTargetNameplateInteract", "UnitNameNPC", "UnitNameFriendlySpecialNPCName", "UnitNameInteractiveNPC",
	"UnitNameHostleNPC" }

-- The whole run: NPC names over heads on, soft targeting's plates off.
local BASE = ns.CVarSet("NPC title test: names", "/cine debug npctitle: NPC names over heads on for the run",
	{ secure = true, values = { UnitNameNPC = "1", UnitNameFriendlySpecialNPCName = "1",
		UnitNameInteractiveNPC = "1", SoftTargetNameplateInteract = "0" } })
local FAR = ns.CVarSet("NPC title test: far", "/cine debug npctitle: friendly NPC plates on, 5 yards",
	{ secure = true, values = { nameplateShowAll = "1", nameplateShowFriendlyNPCs = "1", nameplateMaxDistance = "5" } })
local NEAR = ns.CVarSet("NPC title test: near", "/cine debug npctitle: friendly NPC plates on, 60 yards",
	{ secure = true, values = { nameplateShowAll = "1", nameplateShowFriendlyNPCs = "1", nameplateMaxDistance = "60" } })
local OFF = ns.CVarSet("NPC title test: plates off", "/cine debug npctitle: friendly NPC plates off, 60 yards",
	{ secure = true, values = { nameplateShowFriendlyNPCs = "0", nameplateMaxDistance = "60" } })
local SETS = { BASE, FAR, NEAR, OFF }

-- plates: NPC plates expected drawn (true/false), nil to just report.
local STEPS = {
	{ key = "far", set = FAR, plates = false, say = "FAR: plates on, but only within 5 yards. Stand still." },
	{ key = "near", set = NEAR, plates = true, say = "NEAR: plates on, within 60 yards. Stand still." },
	{ key = "near, off", set = OFF, plates = false, say = "NEAR, plates OFF. Stand still." },
	{ key = "cine far", set = FAR, cine = true, say = "CineMode ON, far (5 yards). Stand still." },
	{ key = "cine near", set = NEAR, cine = true, say = "CineMode ON, near (60 yards). Stand still." },
	{ key = "page far", set = FAR, cine = true, page = true,
		say = "CineMode ON, Nameplates page ON, far (5 yards). Stand still." },
	{ key = "page near", set = NEAR, cine = true, page = true,
		say = "CineMode ON, Nameplates page ON, near (60 yards). Stand still." },
}

local run -- { at, index, step, pass, fail, cineWas, pageWas, pageOn, ticker }

-- (Cut short by a /reload while the pages were on for steps 6 and 7: put back.)
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_ENTERING_WORLD")
restorer:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	local was = CinematicDB and CinematicDB.npcTitlePageWas
	if was and ns.db then
		ns.db.handlePlates, ns.db.handleNames = was.plates, was.names
		CinematicDB.npcTitlePageWas = nil
	end
end)

local function Say(text)
	local log = CinematicDB and CinematicDB.npcTitleLog
	if log then log[#log + 1] = ("%.2f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end
local function Ask(fn, ...)
	if not fn then return nil end
	local ok, value = pcall(fn, ...)
	return ok and Plain(value) or nil
end
local function Alpha(region)
	if not region then return "-" end
	local ok, alpha = pcall(region.GetEffectiveAlpha or region.GetAlpha, region)
	alpha = ok and Plain(alpha) or nil
	return type(alpha) == "number" and ("%.2f"):format(alpha) or tostring(alpha)
end

local function CVarLine()
	local parts = {}
	for _, cvar in ipairs(CVARS) do parts[#parts + 1] = cvar .. "=" .. tostring(GetCVar(cvar)) end
	return table.concat(parts, " ")
end

local function CineOn()
	return ns.IsCineModeOn and ns.IsCineModeOn() and true or false
end
local function SetCine(on)
	if CineOn() ~= on and _G.Cinematic_ToggleCineMode then
		_G.Cinematic_ToggleCineMode()
		Say("  CineMode turned " .. (on and "ON" or "OFF") .. " by the test")
	end
end

-- Who has the game's plate and name settings, and Cinematic's own rows for
-- friendly and service NPCs (the Names grid writes the NPC names settings
-- as yours: an unticked Friendly NPCs row turns them off).
local function SetupLines()
	local keep = ns.chardb or ns.db
	local before, ours = keep.cvarsBefore or {}, keep.cvarsOurs or {}
	for _, cvar in ipairs(CVARS) do
		local holder = ns.CVarHolder and ns.CVarHolder(cvar)
		Say(("  %s now %s; held by %s; yours before Cinematic %s, Cinematic's %s; saved %s"):format(cvar,
			tostring(GetCVar(cvar)), holder and tostring(holder.label) or "none", tostring(before[cvar]),
			tostring(ours[cvar]), tostring(ns.db.savedCVars and ns.db.savedCVars[cvar])))
	end
	local rows = {}
	for key, value in pairs(ns.db) do
		if type(key) == "string" and (key:find("FriendlyNPCs$") or key:find("ServiceNPCs$"))
			and (key:find("^name") or key:find("^plate")) and value and value ~= "" then
			rows[#rows + 1] = key .. "=" .. tostring(value)
		end
	end
	table.sort(rows)
	Say("  rows ticked: " .. (#rows > 0 and table.concat(rows, ", ") or "none"))
	Say(("  handlePlates %s, handleNames %s, nameServiceShow %s, nameServiceClassOnly %s, questObjectGlow %s,"
		.. " CineMode %s"):format(tostring(ns.db.handlePlates), tostring(ns.db.handleNames),
		tostring(ns.db.nameServiceShow), tostring(ns.db.nameServiceClassOnly), tostring(ns.db.questObjectGlow),
		tostring(CineOn())))
	local kinds = {}
	for _, kind in ipairs(ns.SERVICE_KINDS or {}) do
		kinds[#kinds + 1] = kind.key .. (ns.db["nameService" .. kind.key] and "+" or "-")
	end
	Say("  Service NPCs kinds: " .. table.concat(kinds, " "))
	local rules = ns.db.frameRules or {}
	Say(("  rules: name:ServiceNPCs '%s', name:FriendlyNPCs '%s', plate:FriendlyNPCs '%s'"):format(
		tostring(rules["name:ServiceNPCs"]), tostring(rules["name:FriendlyNPCs"]), tostring(rules["plate:FriendlyNPCs"])))
end

-- Every NPC plate now (players, pets and guardians left out), one line each;
-- returns how many are drawn, how many with a title, and how many of those
-- show Cinematic's title line.
local function Dump(label)
	local drawn, titled, lined = 0, 0, 0
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local frame = plate.UnitFrame
		local unit = plate.namePlateUnitToken or (frame and frame.unit)
		local guid = unit and Ask(UnitGUID, unit)
		local skip = not unit or (type(guid) == "string" and guid:find("^Player%-"))
			or Ask(UnitPlayerControlled, unit)
		if not skip then
			local visible = Ask(plate.IsVisible, plate)
			local name = frame and frame.name
			local ours = ns.PlateNameText and ns.PlateNameText(plate)
			local line2 = ns.PlateLine2Text and ns.PlateLine2Text(plate)
			local line2Shown = line2 and Ask(line2.IsVisible, line2) or false
			local okTitle, title = pcall(ns.DescribePlateTitle, plate, unit)
			title = okTitle and tostring(title) or "title unreadable"
			local hasTitle = title:find("^title=<") ~= nil
			if visible then
				drawn = drawn + 1
				if hasTitle then
					titled = titled + 1
					if line2Shown then lined = lined + 1 end
				end
			end
			Say(("  %s %s: plate visible %s alpha %s; game name visible %s alpha %s; our name %s; title line %s; %s"
				.. "; target %s"):format(label, tostring(Ask(UnitName, unit)), tostring(visible), Alpha(plate),
				tostring(name and Ask(name.IsVisible, name)), Alpha(name), ours and ("alpha " .. Alpha(ours)) or "none",
				line2 and ("'" .. tostring(Plain(line2:GetText())) .. "' visible " .. tostring(line2Shown) .. " alpha "
				.. Alpha(line2)) or "none", title, tostring(Ask(UnitIsUnit, unit, "target"))))
		end
	end
	Say(("  %s: %d NPC plates drawn, %d of them with a title, %d showing Cinematic's title line"):format(label, drawn,
		titled, lined))
	return drawn, titled, lined
end

local function Shot(what)
	if ns.PadTestBoxHide then ns.PadTestBoxHide() end
	local ok = pcall(function() Screenshot() end)
	Say(ok and ("  screenshot (%s) at %s"):format(what, date("%m%d%y_%H%M%S")) or "  screenshot failed")
end

local function Prompt(text, sub, waiting)
	ns.PadTestBox(text, sub, waiting and 1 or 0.3, waiting and 0.82 or 1, waiting and 0 or 0.3)
end

local function Verdict(ok, text)
	run[ok and "pass" or "fail"] = run[ok and "pass" or "fail"] + 1
	Say(("  %s %s"):format(ok and "PASS" or "FAIL", text))
end

local function EndStep()
	local step = run.step
	if not step then return end
	local spec = step.spec
	local drawn, titled, lined = Dump("at end")
	local range = GetCVar("nameplateMaxDistance")
	if spec.plates == false then
		Verdict(drawn == 0, ("%s: %d NPC plates drawn, expected none (range %s); its screenshot shows the names and"
			.. " titles over heads"):format(spec.key, drawn, tostring(range)))
	elseif spec.plates then
		Verdict(titled > 0, ("%s: %d NPC plates drawn, %d with a title (needed: one with a title to show the"
			.. " moment); compare its screenshot with step 1's"):format(spec.key, drawn, titled))
	else
		Say(("  RESULT %s: %d NPC plates drawn, %d with a title, %d of those with Cinematic's title line; see its"
			.. " screenshot"):format(spec.key, drawn, titled, lined))
	end
	ns.ApplyCVarSet(spec.set, false)
	run.step = nil
end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	if run.step then EndStep() end
	SetCine(false)
	if run.pageOn then
		ns.db.handlePlates, ns.db.handleNames = run.pageWas[1], run.pageWas[2]
		CinematicDB.npcTitlePageWas = nil
		Say(("  Nameplates and Names pages put back (%s, %s)"):format(tostring(run.pageWas[1]),
			tostring(run.pageWas[2])))
	end
	for i = #SETS, 1, -1 do ns.ApplyCVarSet(SETS[i], false) end
	if run.cineWas then SetCine(true) end
	Say("settings after: " .. CVarLine())
	Say(("done: %d PASS, %d FAIL%s"):format(run.pass, run.fail, done and "" or " (stopped early)"))
	run = nil
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped.", "", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	local now = GetTime() - run.at
	if InCombatLockdown() then
		Say("stopped: a fight started")
		Finish(false)
		return
	end
	if now < SETUP then
		Prompt("Stand OUTDOORS 10 to 15 yards from a TRAINER or VENDOR (a title under its name), in plain view,"
			.. " NO target. Then stand still: the test changes the settings itself.",
			("Starts in %d"):format(math.ceil(SETUP - now)), true)
		return
	end
	local step = run.step
	if not step or GetTime() - step.at >= STEP + (step.spec.cine and CINE_SETTLE - SETTLE or 0) then
		EndStep()
		run.index = run.index + 1
		local spec = STEPS[run.index]
		if not spec then
			Finish(true)
			return
		end
		if spec.page and not run.pageOn then
			-- (CineMode off and on round it, so it's applied afresh with the pages on.)
			SetCine(false)
			run.pageOn = true
			CinematicDB.npcTitlePageWas = { plates = run.pageWas[1], names = run.pageWas[2] }
			ns.db.handlePlates, ns.db.handleNames = true, true
			if ns.EnsurePlateRows then ns.EnsurePlateRows() end
			Say(("  Nameplates and Names pages turned ON by the test (were %s, %s)"):format(tostring(run.pageWas[1]),
				tostring(run.pageWas[2])))
		end
		SetCine(spec.cine and true or false)
		ns.ApplyCVarSet(spec.set, true)
		run.step = { spec = spec, at = GetTime() }
		Say(("--- step %d: %s (CineMode %s, target %s) ---"):format(run.index, spec.key, tostring(CineOn()),
			tostring(Ask(UnitExists, "target") or false)))
		Say("  settings: " .. CVarLine())
		step = run.step
	end
	local into = GetTime() - step.at
	local settle = step.spec.cine and CINE_SETTLE or SETTLE
	if into >= settle and not step.settled then
		step.settled = true
		Say("  settings settled: " .. CVarLine())
		Dump("settled")
		Shot(step.spec.key)
		return
	end
	if into >= settle and into < settle + 1 then return end -- (the screenshot's moment: no box)
	local total = STEP + (step.spec.cine and CINE_SETTLE - SETTLE or 0)
	Prompt(("%d/%d: %s"):format(run.index, #STEPS, step.spec.say), ("RECORDING: %d sec left"):format(
		math.ceil(total - into)), false)
end

function ns.NpcTitleTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("npc title test: not in a fight")
		return
	end
	CinematicDB.npcTitleLog = {}
	run = { at = GetTime(), index = 0, pass = 0, fail = 0, pageWas = { ns.db.handlePlates, ns.db.handleNames } }
	Say(("start: %s (game %s), version %s, target %s, plates up %d"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), tostring(Ask(C_AddOns and C_AddOns.GetAddOnMetadata, "CinematicDev",
		"Version")), tostring(Ask(UnitExists, "target") or false), #(C_NamePlate.GetNamePlates() or {})))
	Say("settings at the start:")
	SetupLines()
	run.cineWas = CineOn()
	SetCine(false)
	ns.ApplyCVarSet(BASE, true)
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.TestPrompt("NPC title test: follow the box (type it again to stop)")
end
