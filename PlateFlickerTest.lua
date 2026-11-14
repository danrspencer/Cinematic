-- /cine debug plateflicker: one run recording a white flicker on the
-- nameplates (reported 2026-11-14, after the style revamp). For 8 seconds,
-- every frame, each plate's health bar fill (its texture or atlas, color,
-- alpha), the bar's and the plate's alpha, the game's name and our own name
-- text (shown, alpha, color, its glow and band, its outline copies): a line
-- in the log only when something changed, with the frame number, so a
-- one-frame flash shows. It counts how often the bar's fill is set again
-- (the game's or ours) and its color. Six screenshots in the first 2.5
-- seconds (the box hidden while recording). Settings that decide the plates'
-- look go at the top. Into CinematicDB.plateFlickerLog. Dev copy only.
local _, ns = ...

local READY, RECORD = 5, 8 -- seconds
local run -- { at, frame, last = { [plate] = signature }, counts = { [bar] = { tex, color } }, shots }

local function Say(text)
	local log = CinematicDB and CinematicDB.plateFlickerLog
	if log then log[#log + 1] = ("%.2f f%d %s"):format(run and GetTime() - run.at or 0, run and run.frame or 0, text) end
end
local function Plain(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Get(region, method)
	if not (region and region[method]) then return "-" end
	local results = { pcall(region[method], region) }
	if not results[1] then return "err" end
	local out = {}
	for i = 2, #results do out[#out + 1] = Plain(results[i]) end
	return table.concat(out, ",")
end

-- (Counts while running: the fill set again, its color set. And who set
-- them: the caller's file and line, with the color, each different one
-- logged once a bar - ours or the game's.)
local hooked = setmetatable({}, { __mode = "k" })
local function Caller()
	local stack = debugstack and debugstack(3, 3, 0) or ""
	-- (The first line that isn't this file: who called.)
	for line in stack:gmatch("[^\n]+") do
		if not line:find("PlateFlickerTest") then return (line:gsub("^%s+", ""):sub(1, 140)) end
	end
	return "?"
end
local function Count(bar, what, ...)
	if not run then return end
	local count = run.counts[bar] or { tex = 0, color = 0, vertex = 0, seen = {} }
	run.counts[bar] = count
	count[what] = count[what] + 1
	local args = {}
	for i = 1, select("#", ...) do args[#args + 1] = Plain((select(i, ...))) end
	local who = what .. " " .. table.concat(args, ",") .. " from " .. Caller()
	if not count.seen[who] and run.callers < 400 then
		count.seen[who] = true
		run.callers = run.callers + 1
		Say(("  bar %s: %s"):format(tostring(bar):sub(-6), who))
	end
end
local function Hook(bar)
	if hooked[bar] then return end
	hooked[bar] = true
	pcall(hooksecurefunc, bar, "SetStatusBarTexture", function(self, ...) Count(self, "tex", ...) end)
	pcall(hooksecurefunc, bar, "SetStatusBarColor", function(self, ...) Count(self, "color", ...) end)
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if fill and not hooked[fill] then
		hooked[fill] = true
		pcall(hooksecurefunc, fill, "SetVertexColor", function(_, ...) Count(bar, "vertex", ...) end)
	end
end

local function Signature(plate)
	local unitFrame = plate.UnitFrame
	if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then return "forbidden" end
	local container = unitFrame.HealthBarsContainer
	local bar = (container and container.healthBar) or unitFrame.healthBar
	if bar then Hook(bar) end
	local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	local text = ns.PlateNameText and ns.PlateNameText(plate)
	local dress = text and text.cineDress
	local rim = text and text.cineRim
	local look = ns.PlateLookNow and ns.PlateLookNow(plate)
	return ("plate a %s | container a %s eff %s | bar a %s shown %s color %s | fill %s atlas %s color %s a %s desat %s | name a %s color %s font %s | " ..
		"ours %s a %s color %s | glow %s band %s rim %s | row look %s"):format(Get(plate, "GetAlpha"),
		Get(container, "GetAlpha"), Get(bar, "GetEffectiveAlpha"), Get(bar, "GetAlpha"), Get(bar, "IsShown"),
		Get(bar, "GetStatusBarColor"), Get(fill, "GetTexture"), Get(fill, "GetAtlas"),
		Get(fill, "GetVertexColor"), Get(fill, "GetAlpha"), Get(fill, "IsDesaturated"), Get(unitFrame.name, "GetAlpha"),
		Get(unitFrame.name, "GetTextColor"), Get(unitFrame.name, "GetFont"), text and "shown" or "no",
		Get(text, "GetAlpha"), Get(text, "GetTextColor"), tostring(dress and dress.glow:IsShown()),
		tostring(dress and dress.back:IsShown()), tostring(rim and rim.on), look and ("outline " ..
		tostring(look.outline) .. " shadow " .. tostring(look.shadow) .. " texture " .. tostring(look.texture)) or "none")
end

local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Say(("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end

local watcher = CreateFrame("Frame")
watcher:Hide()
watcher:SetScript("OnUpdate", function()
	if not run then return end
	local now = GetTime() - run.at
	if now < READY then
		ns.PadTestBox("Stand where the WHITE BARS flash (CineMode on, a busy street, as in your video). Then just " ..
			"watch: the box goes away while it records.", ("Recording starts in %d"):format(math.ceil(READY - now)), 1, 0.82, 0)
		return
	end
	if not run.started then
		run.started = true
		ns.PadTestBoxHide()
		Say("--- recording ---")
	end
	run.frame = run.frame + 1
	local into = now - READY
	if run.shots < 6 and into >= run.shots * 0.45 then
		run.shots = run.shots + 1
		Shot(tostring(run.shots))
	end
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates() or {}) do
		local ok, sig = pcall(Signature, plate)
		sig = ok and sig or ("error " .. tostring(sig))
		if run.last[plate] ~= sig then
			run.last[plate] = sig
			local unit = plate.namePlateUnitToken
			local okName, name = pcall(UnitName, unit or "")
			Say(("%s (%s): %s"):format(tostring(unit), okName and Plain(name) or "?", sig))
		end
	end
	if into >= RECORD then
		watcher:Hide()
		for bar, count in pairs(run.counts) do
			Say(("bar %s: fill set %d times, color set %d, fill color set %d in %d frames"):format(
				tostring(bar):sub(-6), count.tex, count.color, count.vertex, run.frame))
		end
		Say(("done: %d frames, %.0f fps"):format(run.frame, run.frame / RECORD))
		run = nil
		ns.PadTestBox("Done. /reload, then say \"check log\".", "", 0.3, 1, 0.3)
		C_Timer.After(10, function() if not run then ns.PadTestBoxHide() end end)
	end
end)

function ns.PlateFlickerTest()
	if run then return end
	CinematicDB.plateFlickerLog = {}
	run = { at = GetTime(), frame = 0, last = setmetatable({}, { __mode = "k" }), counts = {}, shots = 0, callers = 0 }
	local db = ns.GetDB()
	local texture, kind, size
	if ns.PlateThemeBar then texture, kind, size = ns.PlateThemeBar() end
	local nameTheme = ns.NameThemeNow and ns.NameThemeNow()
	Say(("start: %s (game %s), CineMode %s, in combat %s, style on %s, theme %s, General texture %s border %s, " ..
		"plate theme %s -> bar %s %s %s, name theme %s (%s), Nameplate Style %s, Name Style %s, looks on %s, " ..
		"rows own %s, plates %d"):format(ns.isRetail and "retail" or "Forever", tostring((select(4, GetBuildInfo()))),
		tostring(ns.lastCinematic), tostring(InCombatLockdown()), tostring(db.styleGeneral), tostring(db.styleTheme),
		tostring(db.styleTexture), tostring(db.styleBorder), tostring(db.plateTheme), tostring(texture), tostring(kind),
		tostring(size), tostring(db.nameTheme), nameTheme and nameTheme.key or "none", tostring(db.handlePlateStyle),
		tostring(db.plateNameStyle), tostring(ns.PlateLooksOn and ns.PlateLooksOn()),
		tostring(ns.NameRowsOwn and ns.NameRowsOwn()), C_NamePlate and #C_NamePlate.GetNamePlates() or 0))
	local values = {}
	for _, setting in ipairs({ "Outline", "OutlineColor", "Shadow", "Glow", "Back", "Colour", "Font" }) do
		local value, from = ns.NameLookValue("all", setting)
		values[#values + 1] = ("%s=%s(%s)"):format(setting, tostring(value), tostring(from))
	end
	Say("All names: " .. table.concat(values, " "))
	watcher:Show()
	ns.Print(("plate flicker recorder: %d sec, follow the box"):format(READY + RECORD))
end
