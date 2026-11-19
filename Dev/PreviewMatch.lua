-- /cine debug previewmatch [skip|stop]: the Preview Match test
-- (Tools/preview-match-plan.md). Do the cast bar previews look like the
-- game's bars, and does These bars' pick of the other kind's game look
-- (PlateCastStyle.lua's GameAs) dress the real bars and put them back? One
-- run, steps on screen, no time limit, CineMode off for the run. It never
-- opens Settings (on Forever that sets off the gamepad's "Interface action
-- failed" line): it makes the preview bars itself, by the pages' own code
-- (ns.MakeCastLookSample), in a strip at the screen's right. Dev copy only.
--   1 you target yourself and cast (Hearthstone is best): your bar, the
--     target's and our samples read and shot, as your settings are;
--   2 a nameplate shows a cast (a caster mob, players in a city; or
--     "/cine debug previewmatch skip"): its bar and our plate sample;
--   3 the test picks the other kind's game look for You, Target & focus and
--     Nameplates itself; you cast again: the same read, and checked;
--   4 a nameplate casts again (or skip): checked the same;
--   5 hands off: your picks put back, the bars checked back as in step 1.
-- Your settings come back at the end, on stop, and at the next login if a
-- reload cuts the run short (CinematicDB.previewMatchKept).
-- Read: each frame's named parts both share (Icon, Text, Spark, Border,
-- TextBorder...), every one that shows: art, color, size and place as parts
-- of the bar's size, fonts; the bar's fill and shape; its place on screen
-- for the offline report (Tools/preview-match/build.py). Each pair compared
-- part by part, one line per difference, scored. Verdicts PASS/FAIL at the
-- end. Saved into CinematicDB.previewMatch[client]; /reload, "check log".
local _, ns = ...

local INTO, AFTER_SHOT = 0.5, 1.2 -- (seconds)
local MAX_LINES = 1500

-- Each pair: its name, the game's bar's key, our sample's (each phase's
-- reads are kept as <phase>:<key>).
local PAIRS = {
	{ name = "Your cast bar", real = "player", ours = "ours:player" },
	{ name = "Target cast bar", real = "target", ours = "ours:unit" },
	{ name = "Nameplate cast bar", real = "plate", ours = "ours:plate" },
}
-- The settings the test changes (and puts back).
-- (Each cast page and every switch it's under: added at the start, ns.PageSwitchOf.)
local KEPT_KEYS = { "unitCastStyle", "plateCastStyle" }
local CAST_PAGES = { "unitCastStyle", "plateCastStyle" }
for _, id in ipairs({ "PLAYER", "TARGET", "PLATE" }) do
	for _, key in ipairs({ "plateCastOn_", "plateCastGameAs_", "plateCastFrame_", "plateCastOwn_" }) do
		KEPT_KEYS[#KEPT_KEYS + 1] = key .. id
	end
end

-- How far apart is "different" (as parts of the bar's own size).
local SIZE_OFF, PLACE_X_OFF, PLACE_Y_OFF, FONT_OFF, SHAPE_OFF = 0.15, 0.08, 0.6, 0.25, 0.25

local run -- { step, reads = { [key] = read }, shots = {}, cineWasOn, events }

local function Client()
	local interface = tonumber((select(4, GetBuildInfo()))) or 0
	return interface >= 100000 and "retail" or (interface >= 16000 and interface < 20000) and "forever"
		or (interface >= 10000 and interface < 16000) and "era" or ("game" .. interface)
end

local function Store()
	CinematicDB.previewMatch = CinematicDB.previewMatch or {}
	local store = CinematicDB.previewMatch[Client()]
	if not store then
		store = {}
		CinematicDB.previewMatch[Client()] = store
	end
	return store
end

local function Log(text)
	local store = Store()
	store.lines = store.lines or {}
	if #store.lines >= MAX_LINES then return end
	store.lines[#store.lines + 1] = ("%s %s %s"):format(date("%H:%M:%S"), run and run.tag or "-", text)
end

local function Secret(value) return issecretvalue and issecretvalue(value) end
local function Plain(value)
	if Secret(value) then return nil end
	return value
end
local function Num(value)
	value = Plain(value)
	return type(value) == "number" and value or nil
end
local function Call(object, method, ...)
	if not (object and object[method]) then return nil end
	local results = { pcall(object[method], object, ...) }
	if not results[1] then return nil end
	return unpack(results, 2)
end
local function Round(value, places)
	if type(value) ~= "number" then return nil end
	local mult = 10 ^ (places or 3)
	return math.floor(value * mult + 0.5) / mult
end

-- Drawn on screen: shown all the way up and not see-through.
local function Showing(region)
	if not Plain(Call(region, "IsVisible")) then return false end
	local alpha = Num(Call(region, "GetEffectiveAlpha")) or Num(Call(region, "GetAlpha"))
	return alpha == nil or alpha > 0.02
end

-- The screen in pixels (the screenshot's size).
local function ScreenSize()
	local get = _G.GetPhysicalScreenSize
	local w, h
	if get then w, h = get() end
	if not (tonumber(w) and tonumber(h)) then
		w, h = (GetCVar("gxWindowedResolution") or ""):match("(%d+)x(%d+)")
	end
	return tonumber(w) or 1920, tonumber(h) or 1080
end

-- Where a region sits on screen, in the screenshot's pixels (left, top,
-- right, bottom; top-down).
local function Pixels(region)
	local left, bottom, width, height = Call(region, "GetRect")
	left, bottom, width, height = Num(left), Num(bottom), Num(width), Num(height)
	local scale = Num(Call(region, "GetEffectiveScale"))
	if not (left and bottom and width and height and scale) then return nil end
	local _, physH = ScreenSize()
	local k = scale * physH / 768
	return { left * k, physH - (bottom + height) * k, (left + width) * k, physH - bottom * k }
end

local function Grow(box, add)
	if not add then return box end
	if not box then return { add[1], add[2], add[3], add[4] } end
	box[1], box[2] = math.min(box[1], add[1]), math.min(box[2], add[2])
	box[3], box[4] = math.max(box[3], add[3]), math.max(box[4], add[4])
	return box
end

-- A texture's art: its atlas, else its file.
local function Art(texture)
	local atlas = Plain(Call(texture, "GetAtlas"))
	if atlas and atlas ~= "" then return "atlas:" .. tostring(atlas) end
	local file = Plain(Call(texture, "GetTexture"))
	return file and tostring(file) or nil
end

-- One region, as parts of the bar's size (cx, cy: its middle from the bar's
-- middle; w, h: its size).
local function ReadRegion(region, bar)
	local kind = Call(region, "GetObjectType")
	local bl, bb, bw, bh = Call(bar, "GetRect")
	local l, b, w, h = Call(region, "GetRect")
	bl, bb, bw, bh, l, b, w, h = Num(bl), Num(bb), Num(bw), Num(bh), Num(l), Num(b), Num(w), Num(h)
	local entry = { kind = kind }
	-- (Its anchors, readable on Forever's plates where sizes aren't.)
	local count = Num(Call(region, "GetNumPoints"))
	if count and count > 0 then
		local list = {}
		for i = 1, count do
			local ok, point, relative, relativePoint, x, y = pcall(region.GetPoint, region, i)
			if ok and Plain(point) then
				local rel = relative == bar and "bar" or (relative and Plain(Call(relative, "GetName"))) or
					(relative and relative == bar.Icon and "Icon") or tostring(relative and "other")
				list[#list + 1] = ("%s>%s.%s %s,%s"):format(tostring(point), tostring(rel), tostring(Plain(relativePoint)),
					tostring(Round(Num(x), 1)), tostring(Round(Num(y), 1)))
			end
		end
		entry.points = table.concat(list, " ")
	end
	if bl and bw and bw > 0 and bh and bh > 0 and l and w and h then
		-- (Both in the same units: the region's rect scaled into the bar's.)
		local ratio = (Num(Call(region, "GetEffectiveScale")) or 1) / (Num(Call(bar, "GetEffectiveScale")) or 1)
		l, b, w, h = l * ratio, b * ratio, w * ratio, h * ratio
		entry.w, entry.h = Round(w / bw), Round(h / bh)
		entry.cx = Round(((l + w / 2) - (bl + bw / 2)) / bw)
		entry.cy = Round(((b + h / 2) - (bb + bh / 2)) / bh)
	end
	if kind == "Texture" or kind == "MaskTexture" then
		entry.art = Art(region)
		local r, g, bl2, a = Call(region, "GetVertexColor")
		r, g, bl2, a = Num(r), Num(g), Num(bl2), Num(a)
		if r then entry.color = ("%.2f,%.2f,%.2f,%.2f"):format(r, g or 0, bl2 or 0, a or 1) end
		entry.layer = Plain(Call(region, "GetDrawLayer"))
		entry.blend = Plain(Call(region, "GetBlendMode"))
	elseif kind == "FontString" then
		local font, size, flags = Call(region, "GetFont")
		font, size = Plain(font), Num(size)
		entry.font = font and (tostring(font):match("[^\\/]+$") or tostring(font)) or nil
		entry.flags = Plain(flags)
		if size and bh and bh > 0 then entry.fontSize, entry.fontH = Round(size, 1), Round(size / bh) end
		entry.justify = Plain(Call(region, "GetJustifyH"))
		local text = Plain(Call(region, "GetText"))
		entry.text = type(text) == "string" and text or nil
		local r, g, bl2 = Call(region, "GetTextColor")
		r, g, bl2 = Num(r), Num(g), Num(bl2)
		if r then entry.color = ("%.2f,%.2f,%.2f"):format(r, g or 0, bl2 or 0) end
	end
	return entry
end

-- Whether a region is the bar's own (in it, a few levels down at most): not
-- a frame it only points at (the player bar's layoutParent, snappedToFrame).
local function Inside(region, bar)
	local up = Call(region, "GetParent")
	for _ = 1, 4 do
		if not up then return false end
		if up == bar then return true end
		up = Call(up, "GetParent")
	end
	return false
end

-- A bar the game's template makes, to read its sizes where the live bar's are
-- secret (Forever's target cast bar, 2026-11-19). Made once, never shown.
local references = {}
local function Reference(template)
	if references[template] ~= nil then return references[template] or nil end
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(400, 100)
	holder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
	holder:SetAlpha(0)
	local ok, bar = pcall(CreateFrame, "StatusBar", nil, holder, template)
	if not (ok and bar) then
		references[template] = false
		return nil
	end
	pcall(bar.UnregisterAllEvents, bar)
	for _, script in ipairs({ "OnEvent", "OnUpdate", "OnShow", "OnHide" }) do pcall(bar.SetScript, bar, script, nil) end
	bar:ClearAllPoints()
	bar:SetPoint("CENTER")
	bar:Show()
	references[template] = bar
	return bar
end

-- A bar: its shape, fill, every named part that shows, and its place on
-- screen (with the parts that hang off it, as the name plate under it).
local function ReadBar(bar, label, template)
	if not bar then return nil end
	if Plain(Call(bar, "IsForbidden")) then return { label = label, forbidden = true } end
	local read = { label = label, parts = {} }
	local w, h = Call(bar, "GetSize")
	w, h = Num(w), Num(h)
	read.w, read.h = Round(w, 1), Round(h, 1)
	read.shape = (w and h and h > 0) and Round(w / h, 2) or nil
	read.scale = Round(Num(Call(bar, "GetEffectiveScale")), 3)
	local fill = Call(bar, "GetStatusBarTexture")
	if fill then
		read.fill = Art(fill)
		local r, g, b = Call(bar, "GetStatusBarColor")
		r, g, b = Num(r), Num(g), Num(b)
		if r then read.fillColor = ("%.2f,%.2f,%.2f"):format(r, g or 0, b or 0) end
	end
	local box = Pixels(bar)
	local parent = Call(bar, "GetParent")
	local seen = {} -- (one part under two keys, our sample's glow: once, by the game's name)
	local keys = {}
	for key in pairs(bar) do if type(key) == "string" then keys[#keys + 1] = key end end
	table.sort(keys) -- (capitals first: the game's part names before ours)
	for _, key in ipairs(keys) do
		local value = bar[key]
		-- (Not the frame it's in: our samples keep their plate as frameBars.)
		if type(key) == "string" and type(value) == "table" and value ~= fill and value ~= parent then
			local okIs, isRegion = pcall(function() return value.GetObjectType ~= nil and value.GetRect ~= nil end)
			local kind = okIs and isRegion and Call(value, "GetObjectType")
			if kind and kind ~= "AnimationGroup" and kind ~= "MaskTexture" and not seen[value] and Inside(value, bar)
				and Showing(value) then
				seen[value] = true
				read.parts[key] = ReadRegion(value, bar)
				-- (Only what's near the bar counts for the cut: a glow 3000 px wide doesn't.)
				local px = Pixels(value)
				local entry = read.parts[key]
				if px and entry.w and entry.w < 2 and entry.h and entry.h < 6 then box = Grow(box, px) end
			end
		end
	end
	read.box = box and { Round(box[1], 0), Round(box[2], 0), Round(box[3], 0), Round(box[4], 0) } or nil
	local own = Pixels(bar)
	read.barBox = own and { Round(own[1], 0), Round(own[2], 0), Round(own[3], 0), Round(own[4], 0) } or nil
	-- (Sizes secret: the parts that show, sized and placed as the game's own
	-- template makes them; on screen, the first frame around it we can read.)
	local unread = not read.w
	for _, entry in pairs(read.parts) do if not entry.w then unread = true end end
	local reference = unread and template and Reference(template)
	if reference then
		read.geometryFrom = template
		-- (As big as the live bar where that's readable: the plate's template is 0x0.)
		if read.w and read.h and read.w > 0 and read.h > 0 then reference:SetSize(read.w, read.h) end
		local rw, rh = Num(Call(reference, "GetWidth")), Num(Call(reference, "GetHeight"))
		read.w, read.h = read.w or Round(rw, 1), read.h or Round(rh, 1)
		read.shape = read.shape or ((rw and rh and rh > 0) and Round(rw / rh, 2) or nil)
		for key, entry in pairs(read.parts) do
			local twin = reference[key]
			if not entry.w and type(twin) == "table" and twin.GetRect then
				local copy = ReadRegion(twin, reference)
				-- (Only a part the template itself lays out: the plate's icon and
				-- text are placed by the game's code as a cast starts, 1x1 till
				-- then. Forever 2026-11-19.)
				local pxW = copy.w and read.w and copy.w * read.w
				local pxH = copy.h and read.h and copy.h * read.h
				if pxW and pxH and pxW > 1.5 and pxH > 1.5 then
					entry.w, entry.h, entry.cx, entry.cy = copy.w, copy.h, copy.cx, copy.cy
				else
					entry.unplaced = true
				end
				entry.fontH = entry.fontH or copy.fontH
				entry.fontSize = entry.fontSize or copy.fontSize
			end
		end
	end
	if not read.box then
		local up = Call(bar, "GetParent")
		for _ = 1, 6 do
			if not up then break end
			local px = Pixels(up)
			-- (Not the whole screen: a plate's frames around it are as big as
			-- the world. No cut then.)
			local _, physH = ScreenSize()
			if px and (px[4] - px[2]) < physH / 3 then
				read.box = { Round(px[1], 0), Round(px[2], 0), Round(px[3], 0), Round(px[4], 0) }
				read.areaOf = Call(up, "GetName") or "a frame around it"
				local scale = Num(Call(bar, "GetEffectiveScale")) or Num(Call(up, "GetEffectiveScale"))
				local _, physH = ScreenSize()
				if scale and read.w then read.barPxW = Round(read.w * scale * physH / 768, 0) end
				break
			end
			up = Call(up, "GetParent")
		end
	end
	return read
end

local function Shot(name)
	-- (The step's words off the screen first: they sit over the top of it,
	-- where the target frame is.)
	pcall(ns.TestPrompt, " ", 0.05)
	local stamp = date("%m%d%y_%H%M%S")
	Screenshot()
	run.shots[#run.shots + 1] = { name = name, stamp = stamp, time = time() }
	Log(("SHOT %s %s"):format(name, stamp))
	return stamp
end

local function Keep(key, read, stamp)
	if not read then
		Log(key .. ": not found")
		return
	end
	read.shot = stamp
	run.reads[key] = read
	local names = {}
	for name in pairs(read.parts or {}) do names[#names + 1] = name end
	table.sort(names)
	Log(("%s: %s %sx%s fill %s, shows %s"):format(key, read.forbidden and "FORBIDDEN" or "read",
		tostring(read.w), tostring(read.h), tostring(read.fill), table.concat(names, ", ")))
end

-- The game's bars.
local function PlayerBar()
	return _G.PlayerCastingBarFrame or _G.CastingBarFrame
end
local function PlateBar(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or Plain(Call(plate, "IsForbidden")) then return nil, plate and "forbidden" end
	local uf = plate.UnitFrame
	if not uf then return nil, "no UnitFrame" end
	return uf.castBar or uf.CastBar or (uf.CastBarsContainer and uf.CastBarsContainer.castBar), nil
end

-- Compare: one line per difference, game first.
local function Differ(a, b, off)
	-- (Unknown on either side, a size the game keeps secret: no finding.)
	if type(a) ~= "number" or type(b) ~= "number" then return false end
	return math.abs(a - b) > off
end
-- Two "r,g,b[,a]" colors more than a tenth apart on any part.
local function ColorOff(a, b)
	if not (a and b) then return false end
	local x, y = {}, {}
	for v in a:gmatch("[%d%.]+") do x[#x + 1] = tonumber(v) end
	for v in b:gmatch("[%d%.]+") do y[#y + 1] = tonumber(v) end
	for i = 1, 3 do
		if x[i] and y[i] and math.abs(x[i] - y[i]) > 0.1 then return true end
	end
	return false
end
local function Compare(real, ours)
	local findings = { checks = 0 }
	local function Say(text) findings[#findings + 1] = text end
	if real.forbidden or ours.forbidden then
		Say("can't read (forbidden)")
		return findings
	end
	findings.checks = 2 -- (shape, fill)
	if real.shape and ours.shape and math.abs(real.shape - ours.shape) / real.shape > SHAPE_OFF then
		Say(("SHAPE bar is %sx%s (%.1f:1) in game, %sx%s (%.1f:1) ours"):format(tostring(real.w), tostring(real.h),
			real.shape, tostring(ours.w), tostring(ours.h), ours.shape))
	end
	if real.fill ~= ours.fill then
		Say(("FILL %s in game, %s ours"):format(tostring(real.fill), tostring(ours.fill)))
	end
	local names, seen = {}, {}
	for name in pairs(real.parts) do if not seen[name] then seen[name] = true names[#names + 1] = name end end
	for name in pairs(ours.parts) do if not seen[name] then seen[name] = true names[#names + 1] = name end end
	table.sort(names)
	for _, name in ipairs(names) do
		local g, o = real.parts[name], ours.parts[name]
		findings.checks = findings.checks + 1 -- (shows in both)
		if g and o then findings.checks = findings.checks + (g.kind == "FontString" and 6 or 4) end
		if g and not o then
			Say(("MISSING %s (%s %s) shows in game, not ours"):format(name, tostring(g.kind), tostring(g.art or g.font or "")))
		elseif o and not g then
			Say(("EXTRA %s (%s %s) shows ours, not in game"):format(name, tostring(o.kind), tostring(o.art or o.font or "")))
		else
			-- (The icon's art is the spell's: never the same spell.)
			-- (Nor art the game won't tell: nil on its side is unknown, not none.)
			if name ~= "Icon" and g.art and g.art ~= o.art then
				Say(("ART %s: %s in game, %s ours"):format(name, tostring(g.art), tostring(o.art)))
			end
			-- (Its color: a theme's tint on the game's art shows here, 2026-11-19:
			-- your bar was purple, the preview gold, and nothing said so.)
			if g.kind ~= "FontString" and name ~= "Icon" and ColorOff(g.color, o.color) then
				Say(("COLOR %s: %s in game, %s ours"):format(name, tostring(g.color), tostring(o.color)))
			end
			-- (A font string's width follows its words, which differ: height only.)
			local wide = g.kind ~= "FontString" and Differ(g.w, o.w, SIZE_OFF)
			if wide or Differ(g.h, o.h, SIZE_OFF * 4) then
				Say(("SIZE %s: %sx%s of the bar in game, %sx%s ours"):format(name, tostring(g.w), tostring(g.h),
					tostring(o.w), tostring(o.h)))
			end
			-- (The spark runs along the bar as the cast goes: up and down only.)
			-- (The spark, and its glow with it, run along the bar as the cast
			-- goes: their place along it isn't the look.)
			local moves = name == "Spark" or name == "StandardGlow"
			if (not moves and Differ(g.cx, o.cx, PLACE_X_OFF)) or Differ(g.cy, o.cy, PLACE_Y_OFF) then
				Say(("PLACE %s: middle at %s,%s of the bar in game, %s,%s ours"):format(name, tostring(g.cx),
					tostring(g.cy), tostring(o.cx), tostring(o.cy)))
			end
			if g.kind == "FontString" then
				if g.font ~= o.font then Say(("FONT %s: %s in game, %s ours"):format(name, tostring(g.font), tostring(o.font))) end
				if Differ(g.fontH, o.fontH, FONT_OFF) then
					Say(("FONT SIZE %s: %s (%s of the bar's height) in game, %s (%s) ours"):format(name,
						tostring(g.fontSize), tostring(g.fontH), tostring(o.fontSize), tostring(o.fontH)))
				end
				if g.justify ~= o.justify then
					Say(("JUSTIFY %s: %s in game, %s ours"):format(name, tostring(g.justify), tostring(o.justify)))
				end
			end
		end
	end
	return findings
end

local function SetCine(on)
	if not (ns.IsCineModeOn and Cinematic_ToggleCineMode) then return end
	if (ns.IsCineModeOn() and true or false) ~= on then
		Cinematic_ToggleCineMode()
		Log("CineMode turned " .. (on and "on" or "off") .. " by the test")
	end
end

-- Your settings: kept before the test changes them, put back after (and at
-- the next login if a reload cut the run short).
local function DB() return ns.GetDB and ns.GetDB() or ns.db end
local function KeepSettings()
	local db = DB()
	for _, key in ipairs(CAST_PAGES) do
		local switch = ns.PageSwitchOf and ns.PageSwitchOf(key)
		while switch do
			local known = false
			for _, kept in ipairs(KEPT_KEYS) do if kept == switch then known = true end end
			if not known then KEPT_KEYS[#KEPT_KEYS + 1] = switch end
			switch = ns.PageSwitchOf(switch)
		end
	end
	local kept = {}
	for _, key in ipairs(KEPT_KEYS) do kept[key] = { value = db[key] } end
	CinematicDB.previewMatchKept = kept
end
local function PutBack()
	local kept = CinematicDB and CinematicDB.previewMatchKept
	local db = DB()
	if not (kept and db) then return false end
	for key, entry in pairs(kept) do db[key] = entry.value end
	CinematicDB.previewMatchKept = nil
	if ns.RefreshPlateCastStyle then pcall(ns.RefreshPlateCastStyle) end
	return true
end
local restore = CreateFrame("Frame")
restore:RegisterEvent("PLAYER_LOGIN")
restore:SetScript("OnEvent", function()
	C_Timer.After(1, function()
		if PutBack() then ns.Print("preview match: your cast bar settings put back (a reload cut the test short).") end
	end)
end)

-- The test's own samples, as the pages' previews make them, in a strip at
-- the screen's right, clear of the unit frames and your cast bar.
local strip
local samples = {} -- [kind] = bar
-- (All three casting, as your Hearthstone is: a channel's fill differs.)
local SAMPLE_ROWS = { { "player", "PLAYER", 1 }, { "unit", "TARGET", 1 }, { "plate", "PLATE", 1 } }
local function MakeSamples()
	if strip then return end
	strip = CreateFrame("Frame", nil, UIParent)
	strip:SetSize(300, 190)
	strip:SetPoint("LEFT", UIParent, "LEFT", 60, 60) -- (the right has the quest tracker)
	local back = strip:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.05, 0.05, 0.07, 0.85)
	for i, row in ipairs(SAMPLE_ROWS) do
		local bar = ns.MakeCastLookSample(strip, row[1], row[3], row[2], 0.4)
		if bar then
			bar:ClearAllPoints()
			bar:SetPoint("TOP", strip, "TOP", 0, -24 - (i - 1) * 56)
			samples[row[1]] = bar
		end
	end
end
local function RefreshSamples()
	for _, bar in pairs(samples) do pcall(bar.Refresh, bar) end
end

-- What a phase's verdicts read straight off a bar (no sizes needed: Forever
-- keeps the target bar's secret).
local function Facts(bar)
	if not bar then return nil end
	local facts = {}
	local text = bar.Text
	facts.justify = text and Plain(Call(text, "GetJustifyH"))
	for _, part in ipairs({ "Border", "TextBorder" }) do
		local region = bar[part]
		facts[part] = region and Num(Call(region, "GetAlpha")) or nil
	end
	-- (The unit frames' border we put on: a shown texture of that atlas, not
	-- the bar's own Border.)
	facts.unitBorder = false
	for _, region in ipairs({ bar:GetRegions() }) do
		local atlas = Plain(Call(region, "GetAtlas"))
		if type(atlas) == "string" and atlas:lower() == "ui-castingbar-frame" and region ~= bar.Border
			and Plain(Call(region, "IsShown")) then
			facts.unitBorder = true
		end
	end
	local icon = bar.Icon
	local w = icon and Num(Call(icon, "GetWidth"))
	facts.iconW = w and Round(w, 1) or nil
	return facts
end

local verdicts = {}
local function Verdict(ok, text)
	local line = (ok == nil and "SKIP " or ok and "PASS " or "FAIL ") .. text
	verdicts[#verdicts + 1] = line
	Log("VERDICT " .. line)
end

local function Finish()
	local store = Store()
	store.reads, store.shots, store.verdicts = run.reads, run.shots, verdicts
	store.pairs = {}
	local summary = {}
	for _, phase in ipairs({ "game", "other" }) do
		for _, pair in ipairs(PAIRS) do
			local real, ours = run.reads[phase .. ":" .. pair.real], run.reads[phase .. ":" .. pair.ours]
			local name = pair.name .. (phase == "other" and " (other kind's look)" or "")
			local entry = { name = name, real = phase .. ":" .. pair.real, ours = phase .. ":" .. pair.ours }
			if real and ours then
				entry.findings = Compare(real, ours)
				local checks = math.max(entry.findings.checks, #entry.findings, 1)
				entry.findings.checks = nil
				entry.score = math.floor(100 * (checks - #entry.findings) / checks + 0.5)
				Log(("PAIR %s: score %d, %d differences"):format(name, entry.score, #entry.findings))
				for _, line in ipairs(entry.findings) do Log("  " .. line) end
				summary[#summary + 1] = ("%s %d"):format(name, entry.score)
			else
				entry.missing = not real and "game's not read" or "ours not read"
				Log(("PAIR %s: %s"):format(name, entry.missing))
			end
			store.pairs[#store.pairs + 1] = entry
		end
	end
	run.events:UnregisterAllEvents()
	SetCine(run.cineWasOn)
	if strip then strip:Hide() end
	local fails = 0
	for _, line in ipairs(verdicts) do if line:find("^FAIL") then fails = fails + 1 end end
	run = nil
	ns.TestPrompt(("Preview match DONE: %d verdicts, %d FAIL. /reload, then tell Claude 'check log'."):format(#verdicts, fails), 30)
	ns.Print("preview match: " .. table.concat(summary, ", "))
end

local function ReadSamples(phase, stamp)
	for kind, bar in pairs(samples) do
		Keep(phase .. ":ours:" .. kind, ReadBar(bar, "ours:" .. kind), stamp)
	end
end

-- Step 5: your picks back, the bars checked back as in step 1.
local function BackStep()
	run.step, run.tag = 5, "back"
	ns.TestPrompt("Preview match 5/5: hands off, putting your settings back.", 3)
	PutBack()
	RefreshSamples()
	C_Timer.After(1, function()
		if not run then return end
		for _, which in ipairs({ "player", "target" }) do
			local before = run.facts["game:" .. which]
			local now = Facts(which == "player" and PlayerBar() or _G.TargetFrameSpellBar)
			if before and now then
				Verdict(before.justify == now.justify and before.unitBorder == now.unitBorder,
					("%s bar back as before: name justify %s (was %s), our unit border %s (was %s)"):format(which,
						tostring(now.justify), tostring(before.justify), tostring(now.unitBorder), tostring(before.unitBorder)))
			else
				Verdict(nil, which .. " bar back as before: not read in step 1")
			end
		end
		Finish()
	end)
end

-- The other kind's game look, picked by the test.
local function SetOther()
	local db = DB()
	for _, key in ipairs(CAST_PAGES) do
		local switch = key
		while switch do
			db[switch] = true
			switch = ns.PageSwitchOf and ns.PageSwitchOf(switch)
		end
	end
	for _, id in ipairs({ "PLAYER", "TARGET" }) do
		db["plateCastOn_" .. id] = true
		db["plateCastFrame_" .. id] = false
		db["plateCastGameAs_" .. id] = true -- (held back on the target's: AsHeld, PlateCastStyle.lua)
	end
	db.plateCastGameAs_PLATE = true
	if ns.RefreshPlateCastStyle then pcall(ns.RefreshPlateCastStyle) end
	RefreshSamples()
end

local function CheckOther(which, facts, label)
	if not facts then
		Verdict(nil, label .. ": not read")
		return
	end
	if which == "plate" then
		Verdict(facts.unitBorder and facts.justify == "CENTER",
			("%s in the unit frames' game look: their border on %s, name %s"):format(
			label, tostring(facts.unitBorder), tostring(facts.justify)))
	else
		local hidden = (facts.Border or 0) < 0.01 and (facts.TextBorder or 0) < 0.01
		Verdict(hidden and facts.justify == "LEFT",
			("%s in the nameplates' game look: border and box hidden %s, name %s, icon %s wide"):format(
			label, tostring(hidden), tostring(facts.justify), tostring(facts.iconW)))
	end
end

local function PlateStep(step)
	run.step, run.tag = step, step == 2 and "game" or "other"
	ns.TestPrompt(("Preview match %d/5: a NAMEPLATE must show a CAST: pull a caster mob, or stand in a city with "
		.. "friendly plates on. Or type /cine debug previewmatch skip"):format(step), 600)
end
local function CastStep(step)
	run.step, run.tag = step, step == 1 and "game" or "other"
	ns.TestPrompt(("Preview match %d/5: TARGET YOURSELF, then cast a spell with a CAST TIME (Hearthstone is best)%s.")
		:format(step, step == 3 and ". Your bars are in the other kind's game look now" or ""), 600)
end
local function AfterPlate()
	if run.step < 3 then
		SetOther()
		CastStep(3)
	else
		BackStep()
	end
end

local function OnEvent(_, event, unit)
	if not run then return end
	if not (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START") then return end
	if (run.step == 1 or run.step == 3) and unit == "player" then
		local phase, step = run.tag, run.step
		run.step = step + 0.5
		C_Timer.After(INTO, function()
			if not run then return end
			RefreshSamples()
			local stamp = Shot(phase .. " cast")
			Keep(phase .. ":player", ReadBar(PlayerBar(), "player"), stamp)
			run.facts[phase .. ":player"] = Facts(PlayerBar())
			if UnitIsUnit("target", "player") then
				Keep(phase .. ":target", ReadBar(_G.TargetFrameSpellBar, "target", "TargetSpellBarTemplate"), stamp)
				run.facts[phase .. ":target"] = Facts(_G.TargetFrameSpellBar)
			else
				Log("target: not you, target bar not read")
			end
			ReadSamples(phase, stamp)
			-- (Your bar's art in the theme's color, Interface Recolor's irCast: the
			-- preview's in the same color, 2026-11-19.)
			local real, ours = run.reads[phase .. ":player"], run.reads[phase .. ":ours:player"]
			for _, part in ipairs({ "Border", "TextBorder" }) do
				local g = real and real.parts and real.parts[part]
				local o = ours and ours.parts and ours.parts[part]
				if g and o then
					Verdict(not ColorOff(g.color, o.color), ("%s: your bar's %s %s, the preview's %s"):format(phase, part,
						tostring(g.color), tostring(o.color)))
				end
			end
			if phase == "other" then
				CheckOther("unit", run.facts["other:player"], "your bar")
				-- (The target's pick is held back for now: its bar keeps the game's
				-- look, its name centered under it, its box shown.)
				local target = run.facts["other:target"]
				if target then
					Verdict(target.justify == "CENTER" and (target.TextBorder or 1) > 0.01,
						("target bar's Nameplates' pick held back: name %s, box alpha %s"):format(tostring(target.justify),
							tostring(target.TextBorder)))
				else
					Verdict(nil, "target bar held back: not read")
				end
				CheckOther("plate", Facts(samples.plate), "plate sample")
			end
			C_Timer.After(AFTER_SHOT, function() if run then PlateStep(step + 1) end end)
		end)
	elseif (run.step == 2 or run.step == 4) and type(unit) == "string" and unit:find("^nameplate") then
		local phase, step = run.tag, run.step
		run.step = step + 0.5
		C_Timer.After(INTO, function()
			if not run then return end
			local bar, why = PlateBar(unit)
			if not bar then
				Log(("plate %s: %s, waiting for another"):format(unit, tostring(why or "no cast bar")))
				run.step = step
				return
			end
			RefreshSamples()
			local stamp = Shot(phase .. " plate")
			-- (No template sizes for a plate: its icon and name are placed by the
			-- game's code as a cast starts, the template's are meaningless.)
			local read = ReadBar(bar, "plate")
			Keep(phase .. ":plate", read, stamp)
			if read and read.parts then
				for _, name in ipairs({ "Text", "Icon" }) do
					local part = read.parts[name]
					if part then Log(("plate %s: points %s, justify %s"):format(name, tostring(part.points), tostring(part.justify))) end
				end
			end
			if phase == "other" then CheckOther("plate", Facts(bar), "nameplate bar") end
			C_Timer.After(AFTER_SHOT, function() if run then AfterPlate() end end)
		end)
	end
end

local function Stop()
	if not run then return end
	run.events:UnregisterAllEvents()
	SetCine(run.cineWasOn)
	if strip then strip:Hide() end
	PutBack()
	run = nil
	ns.TestPrompt("Preview match stopped. Your settings are back.", 5)
end

function ns.PreviewMatch(arg)
	arg = arg or ""
	if arg == "stop" then
		Stop()
		return
	end
	if arg == "skip" then
		if run and (run.step == 2 or run.step == 4) then
			Log("plate step " .. run.step .. " skipped")
			AfterPlate()
		end
		return
	end
	if run then
		ns.Print("preview match: already running (/cine debug previewmatch stop to stop it)")
		return
	end
	if InCombatLockdown() then
		ns.Print("preview match: not in a fight. Try again after it.")
		return
	end
	if not ns.MakeCastLookSample then
		ns.Print("preview match: the cast bar page's sample maker is missing.")
		return
	end
	local store = Store()
	wipe(store)
	wipe(verdicts)
	local version, build = GetBuildInfo()
	local physW, physH = ScreenSize()
	store.client, store.build, store.started = Client(), ("%s %s"):format(tostring(version), tostring(build)), date()
	store.screen = { physW, physH }
	store.uiScale = Round(UIParent:GetEffectiveScale(), 4)
	run = { step = 1, tag = "game", reads = {}, shots = {}, facts = {},
		cineWasOn = ns.IsCineModeOn and ns.IsCineModeOn() and true or false }
	run.events = CreateFrame("Frame")
	run.events:RegisterEvent("UNIT_SPELLCAST_START")
	run.events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	run.events:SetScript("OnEvent", OnEvent)
	SetCine(false)
	KeepSettings()
	local db = DB()
	local settings = {}
	for _, key in ipairs(KEPT_KEYS) do settings[#settings + 1] = ("%s=%s"):format(key, tostring(db[key])) end
	Log(("start: %s %s, screen %dx%d, UI scale %s; %s"):format(store.client, store.build, physW, physH,
		tostring(store.uiScale), table.concat(settings, " ")))
	MakeSamples()
	strip:Show()
	RefreshSamples()
	-- (The samples: made from the game's templates, the icon in its place.)
	for kind, bar in pairs(samples) do
		local icon = bar.Icon
		local points = icon and Num(Call(icon, "GetNumPoints")) or 0
		Verdict(bar.fromTemplate ~= nil and points > 0, ("%s sample from the game's %s, icon anchored at %d points"):format(
			kind, tostring(bar.fromTemplate or "drawn stand-in"), points))
	end
	CastStep(1)
end
