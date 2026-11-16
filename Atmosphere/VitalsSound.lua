-- Vitals Vision's sound: played as your health reaches Full (LowHealth.lua),
-- so also at the top of a test and of the quick look picking Cinema shows.
-- The sounds are files of the game's, listed on the theme menu
-- (ns.LOW_HEALTH_MENU in LowHealthThemes.lua). Auto is your class and spec's
-- by the theme Auto picks you, so it follows talent trees where there are no
-- specs. Picked by file name: /cine soundtest vitals plays yours, /cine
-- soundtest vitals all walks through the lot.

local _, ns = ...
local L = ns.L

local SECONDS = 6 -- (some of these go on: faded out by then)
local TEST_EVERY = 4

local walk -- (the test's walk through the list, while it runs)

-- True if the game took it (false: no such file on this client). At the
-- page's Ambient volume, played as the combat cues are (CombatSoundRules.lua).
local function Play(id)
	return ns.PlayAmbienceFile(id, ns.GetDB().lowHealthSoundVolume, SECONDS)
end

-- Auto's: your class's menu entry, and your spec's (nil if it has no sound of
-- its own: the class's, then).
local function Yours()
	local _, token = UnitClass("player")
	local theme = ns.LowHealthAutoTheme()
	local noTree = ns.LowHealthAutoNoTree()
	for _, class in ipairs(ns.LOW_HEALTH_MENU) do
		if class[1] == token then
			for _, spec in ipairs(class[3]) do
				if spec[2] == theme and spec.sound and not noTree then return class, spec end
			end
			return class
		end
	end
end

-- value: the setting ("auto", "off" or a file number). The ID played, or nil.
function ns.PlayVitalsSound(value)
	if value == "off" then return nil end
	if value ~= "auto" then return Play(value) and value or nil end
	local class, spec = Yours()
	if spec and Play(spec.sound) then return spec.sound end
	return class and Play(class.sound) and class.sound or nil
end

function ns.StopVitalsSound()
	walk = nil
	ns.StopAmbienceFile()
end

-- The setting's choices: Auto with what it picks, Off, then each sound.
function ns.VitalsSoundChoices()
	local class, spec = Yours()
	local name = spec and spec.soundName or class and class.soundName
	local list = { { value = "auto", text = L["Auto"] .. (name and ": " .. L[name] or "") },
		{ value = "off", text = L["Off"] } }
	for _, entry in ipairs(ns.LOW_HEALTH_MENU) do
		list[#list + 1] = { value = entry.sound, text = L[entry[2]] .. ": " .. L[entry.soundName] }
		for _, each in ipairs(entry[3]) do
			if each.sound then
				list[#list + 1] = { value = each.sound,
					text = L[each[1]] .. " " .. L[entry[2]] .. ": " .. L[each.soundName] }
			end
		end
	end
	return list
end

-- /cine soundtest vitals [all]: yours, or each in turn. Again stops the walk.
function ns.TestVitalsSound(all)
	local stopped = walk
	ns.StopVitalsSound()
	if stopped then
		ns.Print("vitals sounds stopped")
		return
	end
	if not all then
		local db = ns.GetDB()
		local _, token = UnitClass("player")
		local id = ns.PlayVitalsSound(db.lowHealthSound)
		ns.Print(("vitals sound: setting %s at %s, class %s, auto theme %s, combat %s, ambience on %s at %s: %s"):format(
			tostring(db.lowHealthSound), tostring(db.lowHealthSoundVolume), tostring(token),
			tostring(ns.LowHealthAutoTheme()), tostring(InCombatLockdown()), tostring(GetCVar("Sound_EnableAmbience")),
			tostring(db.combatHeldAmbience or GetCVar("Sound_AmbienceVolume")),
			id and ("playing " .. id) or "none played"))
		return
	end
	local steps = {}
	for _, class in ipairs(ns.LOW_HEALTH_MENU) do
		steps[#steps + 1] = { class[2], class.soundName, class.sound }
		for _, spec in ipairs(class[3]) do
			if spec.sound then steps[#steps + 1] = { spec[1] .. " " .. class[2], spec.soundName, spec.sound } end
		end
	end
	local mine = {}
	walk = mine
	local function Step(i)
		if walk ~= mine then return end
		local step = steps[i]
		if not step then
			walk = nil
			ns.Print("vitals sounds: done")
			return
		end
		ns.Print(("%d/%d %s: %s, %d%s"):format(i, #steps, step[1], step[2], step[3],
			Play(step[3]) and "" or " (not on this client)"))
		C_Timer.After(TEST_EVERY, function() Step(i + 1) end)
	end
	Step(1)
end

-- /cine debug spec: every way this client might tell your spec, each with
-- what it says, for Auto (LowHealth.lua's AutoTheme). In chat and the log.
function ns.SpecDebug()
	local function Say(line)
		ns.Print(line)
		ns.Log("vitals", "spec: " .. line)
	end
	local function Pack(...) return select("#", ...), { ... } end
	-- (a function by its path: "missing", or what it gives, nils and all)
	local function Ask(path, ...)
		local fn = _G
		for part in path:gmatch("[^%.]+") do
			fn = type(fn) == "table" and fn[part] or nil
		end
		if type(fn) ~= "function" then return path .. ": missing" end
		local count, results = Pack(pcall(fn, ...))
		local worked = results[1]
		for i = 1, count do
			local ok, text = pcall(tostring, results[i])
			results[i] = ok and text or "secret"
		end
		local said = count > 1 and table.concat(results, " ", 2, count) or "(gave nothing)"
		return path .. ": " .. said .. (worked and "" or " (error)")
	end
	local _, token, classID = UnitClass("player")
	local _, _, _, build = GetBuildInfo()
	Say(("class %s, level %s, game %s, combat %s, auto theme %s, sound setting %s"):format(tostring(token),
		tostring(UnitLevel("player")), tostring(build), tostring(InCombatLockdown()),
		tostring(ns.LowHealthAutoTheme()), tostring(ns.GetDB().lowHealthSound)))
	for _, path in ipairs({ "GetSpecialization", "C_SpecializationInfo.GetSpecialization", "GetNumSpecializations",
		"GetPrimaryTalentTree", "GetActiveTalentGroup", "GetActiveSpecGroup",
		"C_SpecializationInfo.GetActiveSpecGroup", "PlayerUtil.GetCurrentSpecID",
		"C_ClassTalents.GetActiveConfigID", "C_ClassTalents.GetLastSelectedSavedConfigID",
		"GetNumTalentTabs" }) do
		Say(Ask(path))
	end
	local counts, labels = ns.TalentTreePoints()
	if counts then
		local trees = {}
		for i, count in ipairs(counts) do trees[i] = tostring(labels[i]) .. " " .. count end
		Say("talent trees: " .. table.concat(trees, ", "))
	else
		Say("talent trees: none on this client")
	end
	Say(Ask("C_SpecializationInfo.GetNumSpecializationsForClassID", classID))
	Say(Ask("C_SpecializationInfo.GetSpecIDs", classID))
	Say(Ask("C_SpecializationInfo.CanPlayerUseTalentSpecUI"))
	Say(Ask("C_SpecializationInfo.IsSpecSelectionEnabled"))
	for i = 1, 4 do
		Say(Ask("GetSpecializationInfo", i))
		Say(Ask("C_SpecializationInfo.GetSpecializationInfo", i))
		Say(Ask("GetTalentTabInfo", i))
	end
	local names = {}
	for name, value in pairs(C_SpecializationInfo or {}) do
		if type(value) == "function" then names[#names + 1] = name end
	end
	table.sort(names)
	for first = 1, #names, 6 do
		Say("C_SpecializationInfo has: " .. table.concat(names, ", ", first, math.min(first + 5, #names)))
	end
end
