-- /cine debug plateflicker: one run on your target's nameplate name flickering
-- in a fight (retail, 2026-11-18 video: the name in the bar went bright and dim
-- every frame or two, and smaller, once the fight began). Two timed steps in
-- the big test box (Frames.lua's ns.PadTestBox), each with a screenshot:
--   1 calm: you target a training dummy and don't attack;
--   2 fight: you hit it.
-- All the time it logs, for your target's plate: each call that sets its name's
-- color, font, alpha, text or shown (who made it: the file and line), and each
-- change in what the name reads back (color, alpha, size, font), and each
-- change to anything on the plate, the game's or ours (ScanPlate). Into
-- CinematicDB.plateFlickerLog. It changes no settings. Dev copy only
-- (CinematicDev.toc).
local _, ns = ...

local SETUP, WAIT = 8, 4 -- seconds: before the first step, before a step records
local STEPS = {
	{ key = "calm", seconds = 14, say = "%d/%d: TARGET the training dummy. Do NOT attack it. Just watch its plate." },
	{ key = "fight", seconds = 26, say = "%d/%d: ATTACK the dummy now and KEEP HITTING it until the box says done." },
}
local MAX_LINES = 4000 -- per step, so a busy fight can't fill the saved file
local CALLS_KEPT = 4 -- calls logged in full per setter and caller; the rest only counted

local run -- { at, step, starts, lines, counts, last, shot }

local function Say(text)
	local log = CinematicDB and CinematicDB.plateFlickerLog
	if not log or not run then return end
	run.lines = run.lines + 1
	if run.lines == MAX_LINES then text = "(step's log full: the rest only counted)" end
	if run.lines > MAX_LINES then return end
	log[#log + 1] = ("%.2f %s"):format(GetTime() - run.at, text)
end
local function Plain(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	if type(value) == "table" then
		local ok, name = pcall(function() return value.GetName and value:GetName() end)
		return ok and name and tostring(name) or "table"
	end
	return tostring(value)
end

-- Who called: the first file and line on the stack that isn't this file.
local function Caller()
	local stack = debugstack(3, 6, 0) or ""
	for line in stack:gmatch("[^\n]+") do
		if not line:find("PlateFlickerTest", 1, true) and not line:find("^%[C%]") then
			local file, number = line:match("([^/\\]+%.lua)\"?%]?:(%d+)")
			if file then return file .. ":" .. number end
			return (line:gsub("^%s+", "")):sub(1, 80)
		end
	end
	return "?"
end

-- The name's hooks: every setter that can change how it looks, hooked once.
local SETTERS = { "SetTextColor", "SetVertexColor", "SetFont", "SetFontObject", "SetAlpha", "SetText", "Show",
	"Hide", "SetShown", "SetScale", "SetShadowColor", "SetShadowOffset", "SetTextHeight", "SetAlphaGradient",
	"SetDrawLayer", "SetIgnoreParentAlpha" }
local hooked = setmetatable({}, { __mode = "k" })
local function Hook(name)
	if hooked[name] then return end
	hooked[name] = true
	for _, setter in ipairs(SETTERS) do
		if name[setter] then
			pcall(hooksecurefunc, name, setter, function(self, ...)
				if not run or run.name ~= self then return end
				local caller = Caller()
				local key = setter .. " " .. caller
				local counts = run.counts
				counts[key] = (counts[key] or 0) + 1
				if counts[key] <= CALLS_KEPT then
					local args = {}
					for i = 1, math.min(select("#", ...), 4) do args[i] = Plain((select(i, ...))) end
					Say(("  call %s(%s) from %s%s"):format(setter, table.concat(args, ", "), caller,
						InCombatLockdown() and " [fight]" or ""))
				end
			end)
		end
	end
end

-- What the name reads back now, as one line (logged when it changes).
local function Reading(plate, name)
	local r, g, b, a = name:GetTextColor()
	local file, size = name:GetFont()
	local object = name.GetFontObject and name:GetFontObject()
	local unitFrame = plate.UnitFrame
	return ("color %s %s %s %s, alpha %s, shown %s, size %s, font %s (%s), scale %s | unit frame alpha %s, plate alpha %s"):format(
		Plain(r), Plain(g), Plain(b), Plain(a), Plain(name:GetAlpha()), Plain(name:IsShown()), Plain(size),
		Plain(file and tostring(file):match("[^\\/]+$")), Plain(object), Plain(name.GetScale and name:GetScale()),
		Plain(unitFrame and unitFrame:GetAlpha()), Plain(plate:GetAlpha()))
end

-- Everything on the plate (the game's and ours): each frame's alpha, shown,
-- scale and level, each texture's and text's shown, alpha, color and layer,
-- as one line each, by a name for it. Its art, once, when first seen (ours
-- has Cinematic's paths). A line logged each time it changes.
local function Label(region, path)
	local ok, debugName = pcall(region.GetDebugName, region)
	-- (Secret in a fight: the path it was found by.)
	if ok and type(debugName) == "string" and not (issecretvalue and issecretvalue(debugName)) and debugName ~= "" then
		return (debugName:gsub("^NamePlate%d+%.", ""))
	end
	return path
end
local function RegionLine(region)
	local kind = region:GetObjectType()
	local parts = { kind, "shown " .. Plain(region:IsShown()), "alpha " .. Plain(region:GetAlpha()) }
	if kind == "Texture" or kind == "FontString" then
		local layer, sub = region:GetDrawLayer()
		parts[#parts + 1] = ("layer %s %s"):format(Plain(layer), Plain(sub))
		local r, g, b, a = region:GetVertexColor()
		parts[#parts + 1] = ("vertex %s %s %s %s"):format(Plain(r), Plain(g), Plain(b), Plain(a))
		if kind == "FontString" then
			local tr, tg, tb, ta = region:GetTextColor()
			local _, size = region:GetFont()
			parts[#parts + 1] = ("text color %s %s %s %s, size %s, words %s"):format(Plain(tr), Plain(tg), Plain(tb),
				Plain(ta), Plain(size), Plain(region:GetText()))
		end
	elseif region.GetFrameLevel then
		parts[#parts + 1] = ("scale %s, level %s"):format(Plain(region:GetScale()), Plain(region:GetFrameLevel()))
	end
	return table.concat(parts, ", ")
end
local function Art(region)
	if region:GetObjectType() ~= "Texture" then return nil end
	local atlas, file = region:GetAtlas(), region:GetTexture()
	return ("art %s / %s"):format(Plain(atlas), Plain(file))
end
local function EachRegion(frame, path, depth, fn)
	fn(frame, path)
	for i, region in ipairs({ frame:GetRegions() }) do fn(region, path .. ".r" .. i) end
	if depth <= 0 then return end
	for i, child in ipairs({ frame:GetChildren() }) do
		if not (child.IsForbidden and child:IsForbidden()) then EachRegion(child, path .. ".c" .. i, depth - 1, fn) end
	end
end
local function ScanPlate(plate)
	local seen = run.seen
	local fresh = {}
	EachRegion(plate.UnitFrame, "UnitFrame", 4, function(region, path)
		local ok, line = pcall(RegionLine, region)
		line = ok and line or ("read failed: " .. tostring(line))
		fresh[region] = true
		local before = seen[region]
		if before ~= line then
			local label = run.labels[region]
			if not label then
				label = Label(region, path)
				run.labels[region] = label
				local okArt, art = pcall(Art, region)
				Say(("  new %s: %s%s"):format(label, line, okArt and art and (", " .. art) or ""))
			else
				Say(("  %s: %s%s"):format(label, line, InCombatLockdown() and " [fight]" or ""))
			end
			seen[region] = line
		end
	end)
	for region in pairs(seen) do
		if not fresh[region] then
			Say(("  gone %s"):format(run.labels[region] or "?"))
			seen[region] = nil
		end
	end
end

local watcher = CreateFrame("Frame")
watcher:Hide()

local function Finish(done)
	watcher:Hide()
	if run then
		for key, count in pairs(run.counts) do Say(("  total %s: %d"):format(key, count)) end
	end
	run = nil
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped.", "", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function NewStep(index)
	if run.step then
		for key, count in pairs(run.counts) do Say(("  total %s: %d"):format(key, count)) end
	end
	run.step, run.counts, run.lines, run.last, run.shot = index, {}, 0, nil, nil
	Say(("--- step %d: %s (in fight %s, CineMode %s, retail %s, style %s) ---"):format(index, STEPS[index].key,
		tostring(InCombatLockdown()), tostring(ns.lastCinematic and true or false), tostring(ns.isRetail),
		tostring(ns.db and ns.db.styleTheme)))
end

ns.SetOnUpdate(watcher, function()
	if not run then return end
	local now = GetTime() - run.at
	if now < SETUP then
		ns.PadTestBox("Stand near a TRAINING DUMMY, out of a fight. Follow the box.",
			("Starts in %d"):format(math.ceil(SETUP - now)), 1, 0.82, 0)
		return
	end
	local index
	for i = #run.starts, 1, -1 do
		if now >= run.starts[i] then
			index = i
			break
		end
	end
	if not index then return end
	if index > #STEPS then
		Finish(true)
		return
	end
	if index ~= run.step then NewStep(index) end
	local step = STEPS[index]
	local into = now - run.starts[index]
	if into < WAIT then
		ns.PadTestBox(step.say:format(index, #STEPS), "GET READY", 1, 0.82, 0)
		return
	end
	ns.PadTestBox(step.say:format(index, #STEPS), ("RECORDING: %d sec left"):format(math.ceil(step.seconds - into)),
		0.3, 1, 0.3)
	-- (The box moved off the plate's way? It's at the top: the plate is mid-screen.)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
	local name = plate and plate.UnitFrame and plate.UnitFrame.name
	if not name then
		if run.last ~= "none" then
			run.last = "none"
			Say("  no target plate")
		end
		return
	end
	if run.name ~= name then
		run.name = name
		run.seen, run.labels = {}, {}
		Hook(name)
		Say(("  target plate: %s (%s), name's parent %s"):format(Plain(UnitName("target")), Plain(plate:GetName()),
			Label(name:GetParent(), "?")))
	end
	local scanned, why = pcall(ScanPlate, plate)
	if not scanned and not run.scanFailed then
		run.scanFailed = true
		Say("  plate scan failed: " .. tostring(why))
	end
	local ok, line = pcall(Reading, plate, name)
	line = ok and line or ("read failed: " .. tostring(line))
	if line ~= run.last then
		run.last = line
		Say(("  reads %s%s"):format(line, InCombatLockdown() and " [fight]" or ""))
	end
	if not run.shot and into >= step.seconds * 0.6 then
		run.shot = true
		ns.PadTestBoxHide()
		local shotOk = pcall(Screenshot)
		Say(("  screenshot step %d %s at %s%s"):format(index, step.key, date("%m%d%y_%H%M%S"), shotOk and "" or " (failed)"))
	end
end)

function ns.PlateFlickerTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("plate flicker test: not in a fight")
		return
	end
	CinematicDB.plateFlickerLog = {}
	run = { at = GetTime(), starts = {}, counts = {}, lines = 0 }
	local at = SETUP
	for i, step in ipairs(STEPS) do
		run.starts[i] = at
		at = at + step.seconds
	end
	run.starts[#STEPS + 1] = at
	ns.Print("plate flicker test: follow the box (run it again to stop)")
	watcher:Show()
end
