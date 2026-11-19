-- /cine debug petplate: why your pet's nameplate isn't there out of
-- CineMode (user, Forever 2026-11-19: after the Preview Match test, its
-- plate stayed away with CineMode off). One run, hands off once your pet is
-- out: its plate read as things are now, then the test turns CineMode on,
-- then off (3 s each to settle), reading it each time, and puts CineMode back
-- as it was. Per read: the pet's plate there or not, shown, its alpha, the
-- game's unit frame on it shown or hidden, asleep in Cinematic's plate
-- sleep (PlateSleep.lua hides the game's frame of a sleeping plate), our
-- alpha on it, the fade's own account (ns.DescribePlateNameKept), and every
-- nameplate setting that decides a friendly pet's plate. Verdicts at the end.
-- Logged into CinematicDB.petPlateLog. Dev copy only.
local _, ns = ...

local SETTLE = 3
local CVARS = { "nameplateShowAll", "nameplateShowFriends", "nameplateShowFriendlyPets",
	"nameplateShowFriendlyPlayerPets", "nameplateShowFriendlyMinions", "nameplateShowFriendlyPlayerMinions",
	"nameplateShowFriendlyGuardians", "nameplateShowFriendlyPlayerGuardians", "nameplateShowFriendlyNPCs",
	"nameplateShowFriendlyPlayers", "nameplateShowOnlyNames", "nameplateShowOnlyNameForFriendlyPlayerUnits",
	"UnitNameFriendlyPetName" }

local run -- { cineWasOn, reads = {}, events }

local function Log(text)
	local log = CinematicDB and CinematicDB.petPlateLog
	if not log then return end
	log[#log + 1] = ("%s %s"):format(date("%H:%M:%S"), text)
end

local function Say(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Call(object, method, ...)
	if not (object and object[method]) then return nil end
	local ok, value = pcall(object[method], object, ...)
	return ok and value or nil
end
local function CVar(name)
	local get = C_CVar and C_CVar.GetCVar or GetCVar
	local ok, value = pcall(get, name)
	return ok and value or "?"
end
local function CineOn() return ns.IsCineModeOn and ns.IsCineModeOn() and true or false end
local function SetCine(on)
	if not (ns.IsCineModeOn and Cinematic_ToggleCineMode) then return end
	if CineOn() ~= on then Cinematic_ToggleCineMode() end
end

-- One read of the pet's plate.
local function Read(label)
	local facts = { label = label, cine = CineOn(), pet = UnitExists("pet") and true or false }
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("pet")
	facts.plate = plate ~= nil
	local parts = { ("%s: CineMode %s, pet %s, plate %s"):format(label, tostring(facts.cine), tostring(facts.pet),
		plate and (plate:GetName() or "unnamed") or "NONE") }
	if plate then
		facts.forbidden = Call(plate, "IsForbidden") and true or false
		facts.shown = Call(plate, "IsShown")
		facts.asleep = ns.PlateAsleep and ns.PlateAsleep(plate) or false
		local frame = plate.UnitFrame
		facts.frameShown = frame and Call(frame, "IsShown")
		facts.frameVisible = frame and Call(frame, "IsVisible")
		parts[#parts + 1] = ("forbidden %s, plate shown %s alpha %s, unit frame shown %s visible %s alpha %s, asleep %s, our alpha %s"):format(
			tostring(facts.forbidden), Say(facts.shown), Say(Call(plate, "GetAlpha")), Say(facts.frameShown),
			Say(facts.frameVisible), Say(frame and Call(frame, "GetAlpha")), tostring(facts.asleep),
			Say(frame and frame.cinematicAlpha))
		if ns.DescribePlateNameKept then
			local ok, text = pcall(ns.DescribePlateNameKept, "pet", plate)
			parts[#parts + 1] = "fade: " .. (ok and tostring(text) or ("error " .. tostring(text)))
		end
	end
	local cvars = {}
	for _, name in ipairs(CVARS) do cvars[#cvars + 1] = name:gsub("^nameplate", "") .. "=" .. tostring(CVar(name)) end
	parts[#parts + 1] = "cvars " .. table.concat(cvars, " ")
	if ns.plateSleep and ns.plateSleep.Describe then parts[#parts + 1] = ns.plateSleep.Describe() end
	Log(table.concat(parts, " | "))
	run.reads[label] = facts
	return facts
end

local function Verdict(ok, text)
	Log(((ok == nil) and "SKIP " or ok and "PASS " or "FAIL ") .. text)
end

local function Finish()
	local off = run.reads["CineMode off"]
	local on = run.reads["CineMode on"]
	if off then
		Verdict(off.plate, "pet's plate there with CineMode off")
		if off.plate then
			Verdict(not off.asleep, "pet's plate awake with CineMode off (asleep = the game's frame hidden by us)")
			Verdict(off.frameShown == true, "the game's unit frame on it shown with CineMode off")
		end
	end
	if on then Verdict(on.plate, "pet's plate there with CineMode on") end
	run.events:UnregisterAllEvents()
	SetCine(run.cineWasOn)
	Log("CineMode back " .. (run.cineWasOn and "on" or "off"))
	run = nil
	ns.TestPrompt("Pet plate check DONE. /reload, then tell Claude 'check log'.", 30)
end

local function Steps()
	Read("as it was")
	ns.TestPrompt("Pet plate check: hands off, turning CineMode on.", SETTLE)
	SetCine(true)
	C_Timer.After(SETTLE, function()
		if not run then return end
		Read("CineMode on")
		ns.TestPrompt("Pet plate check: hands off, turning CineMode off.", SETTLE)
		SetCine(false)
		C_Timer.After(SETTLE, function()
			if not run then return end
			Read("CineMode off")
			Finish()
		end)
	end)
end

function ns.PetPlateTest()
	if run then
		run.events:UnregisterAllEvents()
		SetCine(run.cineWasOn)
		run = nil
		ns.TestPrompt("Pet plate check stopped.", 3)
		return
	end
	CinematicDB.petPlateLog = {}
	run = { cineWasOn = CineOn(), reads = {} }
	run.events = CreateFrame("Frame")
	local client = select(4, GetBuildInfo())
	Log(("start: interface %s, CineMode %s, in a fight %s"):format(tostring(client), tostring(run.cineWasOn),
		tostring(InCombatLockdown())))
	if UnitExists("pet") then
		Steps()
		return
	end
	ns.TestPrompt("Pet plate check: CALL YOUR PET (no time limit; the command again stops it).", 600)
	run.events:RegisterEvent("UNIT_PET")
	run.events:SetScript("OnEvent", function(_, _, unit)
		if run and unit == "player" and UnitExists("pet") then
			run.events:UnregisterAllEvents()
			C_Timer.After(1, function() if run then Steps() end end)
		end
	end)
end
