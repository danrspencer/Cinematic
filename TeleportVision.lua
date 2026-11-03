-- Teleport Vision: while you cast your Hearthstone, Astral Recall or a
-- teleport (the casts the tele camera plays for: Camera.lua's ns.departCast),
-- a portal's glowing rim closes in round you over the cast, brighter and
-- turning quicker as it fills, spiral arms turning the other way inside it
-- and motes spiraling in. Gone: a flash as you're whisked away. Cancelled:
-- it opens back out and fades. It follows the tele camera's own rules: only
-- when that cast's scene plays now. In your spec's colour (its Vitals Vision
-- theme's glow), or one of your own. Its page is at the bottom.

local ADDON_NAME, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.teleportVision = false        -- at all (its page's switch)
DEFAULTS.teleportVisionColor = "spec"  -- "spec" (Auto: your spec's Vitals theme's glow), a theme's key, or "custom"
DEFAULTS.teleportVisionR = 0.55
DEFAULTS.teleportVisionG = 0.45
DEFAULTS.teleportVisionB = 1
DEFAULTS.teleportVisionAlpha = 1       -- how strong at the end of the cast
DEFAULTS.teleportVisionMotes = true    -- motes spiraling in
DEFAULTS.teleportVisionDark = 1        -- the world darkened outside the rim (0: not at all)
DEFAULTS.teleportVisionClouds = true   -- clouds swirling round outside the rim, in a deep shade of its color
DEFAULTS.teleportVisionEdges = true    -- black edges closing in with the portal
DEFAULTS.teleportVisionEdgeReach = 0.35 -- how far in (share of the screen) they come as the cast fills
DEFAULTS.teleportVisionEdgeAlpha = 1    -- how dark they get
DEFAULTS.teleportVisionEdgeClose = 0    -- seconds before the cast ends that they close over the whole screen (0: never)
DEFAULTS.teleportVisionHideCast = true  -- your cast bar faded out (over CAST_FADE seconds) while it shows: the portal is the cast's progress
DEFAULTS.teleportVisionFadeTooltip = true -- ...and the tooltip, the same way

local ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\LowHealth\\"
local RIM = 0.43           -- where the ring texture's rim is (a share of its half-width)
local RIM_OUT = 1.25       -- the rim's distance from the middle as the cast starts (shares of the way to a corner)...
local RIM_IN = 0.45        -- ...and as it ends: round you
local GONE_TIME = 1.6      -- seconds it takes to clear as you go...
local BLACK_HOLD = 0.6     -- ...the first of them all black (with Black edges): the ring shrinking into you under it
local CANCEL_TIME = 0.8    -- seconds it takes to open back out and fade
local TEST_TIME = 8        -- seconds the page's test cast takes
local MAX_MOTES = 16

local frame, ring, arms, flash, shade, clouds, edges, blackout
local motes = {}
local spin = { ring = 0, arms = 0 }
local lastAt
local test -- (the page's pretend cast: { startAt, endsAt })

local function Create()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata("BACKGROUND")
	frame:SetFrameLevel(2)
	frame:EnableMouse(false)
	ns.AddOverlay(frame) -- (shown with the UI hidden too)
	-- (Under the ring: the world darkened outside it, then clouds swirling round.)
	shade = frame:CreateTexture(nil, "BACKGROUND")
	shade:SetTexture(ART .. "RingShade", "CLAMP", "CLAMP") -- (its dark edge carries on past it)
	shade:SetAllPoints(frame)
	shade:SetBlendMode("BLEND")
	-- (Black edges over the shade, under the clouds and ring: Tint.lua's vignette.)
	edges = ns.CreateVignette(frame)
	for _, piece in pairs(edges) do piece:SetDrawLayer("BACKGROUND", 1) end
	-- (...and, at the last moment, black over the whole screen, all of it: under the flash only.)
	blackout = frame:CreateTexture(nil, "OVERLAY", nil, 2)
	blackout:SetAllPoints(frame)
	blackout:SetColorTexture(0, 0, 0, 1)
	blackout:Hide()
	clouds = frame:CreateTexture(nil, "BORDER")
	clouds:SetTexture(ART .. "Vortex")
	clouds:SetBlendMode("BLEND")
	clouds:SetPoint("CENTER")
	ring = frame:CreateTexture(nil, "ARTWORK")
	ring:SetTexture(ART .. "Ring")
	ring:SetBlendMode("ADD")
	ring:SetPoint("CENTER")
	arms = frame:CreateTexture(nil, "ARTWORK", nil, -1)
	arms:SetTexture(ART .. "Swirl")
	arms:SetBlendMode("ADD")
	arms:SetPoint("CENTER")
	flash = frame:CreateTexture(nil, "OVERLAY", nil, 1) -- (under the blackout: the black takes over, the flash with it)
	flash:SetAllPoints(frame)
	flash:SetTexture(ART .. "GlowGlow")
	flash:SetBlendMode("ADD")
	for i = 1, MAX_MOTES do
		local tex = frame:CreateTexture(nil, "OVERLAY", nil, 1)
		tex:SetTexture(ART .. "Mote")
		tex:SetBlendMode("ADD")
		tex:Hide()
		motes[i] = { tex = tex }
	end
	frame:Hide()
end

-- Its colour: your spec's Vitals Vision theme's glow (its flash's if none), or yours.
local function Color(db, cast)
	if db.teleportVisionColor == "custom" and not (cast and cast.themeKey) then
		return db.teleportVisionR, db.teleportVisionG, db.teleportVisionB
	end
	-- (The color reel's: that spec's theme, whatever yours is; else the one picked, else Auto's.)
	local picked = db.teleportVisionColor ~= "spec" and db.teleportVisionColor ~= "custom" and db.teleportVisionColor
	local key = cast and cast.themeKey or picked or ns.LowHealthAutoTheme and ns.LowHealthAutoTheme()
	local theme = key and ns.LOW_HEALTH_THEME and ns.LOW_HEALTH_THEME[key]
	local color = theme and (theme.glow or theme.flash) or { 0.55, 0.45, 1 }
	return color[1], color[2], color[3]
end

-- The cast to show: the page's test, or yours if its scene plays (the tele camera's rules).
local function Cast()
	if test then return test end
	local cast = ns.departCast
	if cast and cast.scene and ns.Setting("teleportVision") then return cast end
end

local function Mote(now, r, g, b)
	for _, mote in ipairs(motes) do
		if not mote.born then
			mote.born, mote.life = now, 2 + math.random() * 1.5
			mote.turn, mote.out = math.random() * 2 * math.pi, 0.8 + math.random() * 0.4
			mote.size = 0.012 + math.random() * 0.016
			mote.tex:SetVertexColor(r, g, b, 0)
			return
		end
	end
end

-- The tests' timer (the page's test and the color reel): the seconds left on the
-- pretend cast in the middle of the screen, and when the black takes over, so
-- its timing can be judged without casting for real.
local timer
local function Timer(text)
	if not timer then
		local holder = CreateFrame("Frame", nil, UIParent)
		holder:SetAllPoints(UIParent)
		holder:SetFrameStrata("TOOLTIP")
		holder:EnableMouse(false)
		ns.AddOverlay(holder)
		timer = holder:CreateFontString(nil, "OVERLAY", "GameFont_Gigantic")
		timer:SetPoint("CENTER", 0, -40)
		timer:SetShadowOffset(2, -2)
	end
	timer:SetText(text or "")
	timer:GetParent():SetShown(text ~= nil)
end

local function Update()
	local now = GetTime()
	lastAt = lastAt or now
	local spent = now - lastAt
	lastAt = now
	local cast = Cast()
	if test and not test.done and now >= test.endsAt then test.done, test.doneAt = "gone", now end
	local width, height = frame:GetWidth(), frame:GetHeight()
	local corner = 0.5 * math.sqrt(width * width + height * height)
	local db = ns.GetDB()
	-- How far through (0-1), and what's after: closing out as it's gone or cancelled.
	local p, alpha, rim, flashAlpha, fadeOut = 0, 0, RIM_OUT, 0, 1
	if cast then
		local span = math.max(0.5, cast.endsAt - cast.startAt)
		p = math.min(1, math.max(0, ((cast.doneAt or now) - cast.startAt) / span))
		rim = RIM_OUT + (RIM_IN - RIM_OUT) * p * p * (3 - 2 * p)
		alpha = 0.25 + 0.75 * p ^ 1.5
		if cast.done == "gone" then
			local since = now - cast.doneAt
			rim = rim * math.max(0, 1 - since / BLACK_HOLD) -- (shrinking into you as you go)
			flashAlpha = math.max(0, 1 - since / BLACK_HOLD) * 0.8
			-- (All of it held while the black holds, then clearing: not all at once at the end.)
			fadeOut = since < BLACK_HOLD and 1 or math.max(0, 1 - (since - BLACK_HOLD) / (GONE_TIME - BLACK_HOLD))
			alpha = alpha * fadeOut
			if since >= GONE_TIME then cast = nil end
		elseif cast.done == "cancelled" then
			local t = (now - cast.doneAt) / CANCEL_TIME
			rim = rim + (RIM_OUT - rim) * math.min(1, t)
			alpha = alpha * math.max(0, 1 - t)
			if t >= 1 then cast = nil end
		end
	end
	if not cast then
		if timer then Timer(nil) end
		if test and test.done then test = nil end
		frame:Hide()
		for _, mote in ipairs(motes) do mote.born = nil mote.tex:Hide() end
		lastAt = nil
		return
	end
	alpha = alpha * db.teleportVisionAlpha
	local r, g, b = Color(db, cast)
	-- The ring: quicker as the cast fills; the arms the other way, inside it.
	spin.ring = (spin.ring + spent * (4 + 20 * p) / 60 * 2 * math.pi) % (2 * math.pi)
	spin.arms = (spin.arms - spent * (6 + 30 * p) / 60 * 2 * math.pi) % (2 * math.pi)
	local half = math.max(1, corner * rim / RIM)
	-- The shade: the whole screen, its clear middle's edge on the rim (by its
	-- coordinates, as its texture's edge carries on past it).
	local dark = db.teleportVisionDark * math.min(1, alpha * 1.3) * fadeOut
	if dark > 0 then
		-- (Not below a tenth of the way: as you go the rim shrinks to nothing, and the
		-- coordinates grew past what the game takes: "TexCoord out of range".)
		local shadeHalf = corner * math.max(rim, 0.05) / 0.47
		local across, down = 0.5 * width / shadeHalf, 0.5 * height / shadeHalf
		shade:SetTexCoord(0.5 - 0.5 * across, 0.5 + 0.5 * across, 0.5 - 0.5 * down, 0.5 + 0.5 * down)
		shade:SetVertexColor(r * 0.12, g * 0.12, b * 0.12, math.min(1, dark))
		shade:Show()
	else
		shade:Hide()
	end
	-- The black edges: in from the screen's edges as the cast fills (a third of the
	-- way at the end), all the way as you go, fading with the flash.
	-- Its last moments (Closing time before the end): they close over the whole
	-- screen, black, until you're gone; then it fades with the flash.
	if db.teleportVisionEdges then
		local reach = 0.06 + (db.teleportVisionEdgeReach - 0.06) * p * p * (3 - 2 * p)
		local close = 0
		if cast.done == "gone" then
			close = 1
		elseif not cast.done and db.teleportVisionEdgeClose > 0 then
			local left = cast.endsAt - now
			close = math.max(0, math.min(1, 1 - left / db.teleportVisionEdgeClose))
			close = close * close * (3 - 2 * close)
		end
		reach = reach + (0.5 - reach) * close
		local edgeAlpha = db.teleportVisionEdgeAlpha * math.min(1, (0.35 + 0.65 * math.max(p, close))
			* math.min(1, alpha * 2 + close)) * fadeOut
		ns.SetVignette(edges, reach, math.min(1, edgeAlpha), 0, 0, 0, width, height)
		blackout:SetAlpha(math.min(1, (db.teleportVisionEdgeAlpha + (1 - db.teleportVisionEdgeAlpha) * close) * close
			* fadeOut))
		blackout:SetShown(close > 0)
	else
		ns.SetVignette(edges, 0, 0)
		blackout:Hide()
	end
	-- The clouds: wound round outside the rim, turning with it, in a deep shade of its color.
	if db.teleportVisionClouds then
		local cloudHalf = math.max(1, corner * math.max(rim, 0.3) / 0.4)
		clouds:SetSize(cloudHalf * 2, cloudHalf * 2)
		clouds:SetRotation(spin.ring * 0.6)
		clouds:SetVertexColor(r * 0.5, g * 0.5, b * 0.5, math.min(1, alpha * 0.75))
		clouds:Show()
	else
		clouds:Hide()
	end
	ring:SetSize(half * 2, half * 2)
	ring:SetRotation(spin.ring)
	ring:SetVertexColor(r, g, b, math.min(1, alpha))
	local armsHalf = math.max(1, corner * math.max(rim, 0.2) / 0.36)
	arms:SetSize(armsHalf * 2, armsHalf * 2)
	arms:SetRotation(spin.arms)
	arms:SetVertexColor(r, g, b, math.min(1, alpha * 0.45 * p))
	flash:SetVertexColor(r + (1 - r) * 0.5, g + (1 - g) * 0.5, b + (1 - b) * 0.5, flashAlpha)
	-- Motes: more as it fills, winding in from the rim.
	if db.teleportVisionMotes and not cast.done and math.random() < (2 + 6 * p) * spent then
		Mote(now, r, g, b)
	end
	for _, mote in ipairs(motes) do
		if mote.born then
			local t = (now - mote.born) / mote.life
			if t >= 1 or not db.teleportVisionMotes then
				mote.born = nil
				mote.tex:Hide()
			else
				local dist = corner * rim * mote.out * (1 - 0.7 * t * t)
				local turn = mote.turn - 2 * math.pi * 0.5 * t
				local px = mote.size * height
				mote.tex:ClearAllPoints()
				mote.tex:SetPoint("CENTER", frame, "CENTER", dist * math.cos(turn), dist * math.sin(turn))
				mote.tex:SetSize(px, px)
				mote.tex:SetVertexColor(r, g, b, math.min(1, alpha * math.sin(math.pi * t)))
				mote.tex:Show()
			end
		end
	end
	-- (The test's timer: seconds left, the blackout marked as it starts.)
	if cast == test then
		local left = cast.endsAt - now
		if cast.done == "gone" then
			Timer("|cffaaaaaa" .. L["gone"] .. "|r")
		elseif cast.done then
			Timer(nil)
		elseif db.teleportVisionEdges and db.teleportVisionEdgeClose > 0 and left <= db.teleportVisionEdgeClose then
			Timer(("%.1f  |cffff6060%s|r"):format(math.max(0, left), L["blackout"]))
		else
			Timer(("%.1f"):format(math.max(0, left)))
		end
	elseif timer then
		Timer(nil)
	end
	frame:Show()
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
	if not ns.GetDB() then return end
	-- (Nothing to do with no cast, or one over a while: not every frame's work.)
	local cast = Cast()
	if not (cast and (not cast.done or GetTime() - cast.doneAt < GONE_TIME + CANCEL_TIME))
		and not (frame and frame:IsShown()) then
		return
	end
	if not frame then Create() end
	Update()
end)

-- Your cast bar and the tooltip faded out over the cast's first CAST_FADE
-- seconds while it shows a teleport Tele Vision is showing (teleportVisionHideCast,
-- teleportVisionFadeTooltip), so you see it start, then the portal is the
-- progress. The bar sets itself back to full as a cast starts, so its own
-- events are followed too, and both are set again each frame while it lasts.
-- Cancelled: both put back at once (and CineMode's fade on the bar, Tooltips'
-- own on the tooltip as it next shows). Gone: kept hidden while the black and
-- its clearing last (GONE_TIME), or the bar's finish flash showed on the black.
local CAST_BARS = { "PlayerCastingBarFrame", "CastingBarFrame", "GamepadPlayerCastingBarFrame" }
local CAST_FADE = 3 -- seconds they take to fade out
-- The alpha wanted for the bar or the tooltip (key: its setting) now, or nil: not faded.
local function FadeWanted(key)
	local db = ns.GetDB()
	local cast = ns.departCast
	if not (db and db[key] and ns.Setting("teleportVision") and cast and cast.scene) then
		return nil
	end
	if cast.done == "gone" and GetTime() - cast.doneAt < GONE_TIME then
		return 0
	elseif cast.done then
		return nil
	end
	return math.max(0, 1 - (GetTime() - cast.startAt) / CAST_FADE)
end
local function UpdateCastBar(bar)
	local alpha = FadeWanted("teleportVisionHideCast")
	if alpha then
		bar.cinematicTeleHidden = true
		bar:SetAlpha(alpha)
	elseif bar.cinematicTeleHidden then
		bar.cinematicTeleHidden = nil
		if ns.Flag(bar:IsShown()) then
			bar:SetAlpha(1)
			-- (The game skips its finish fade for a bar at alpha 0, as it was as you
			-- went: idle, it would show full, stuck. Hidden, as that fade would have.)
			if not (bar.casting or bar.channeling or bar.reverseChanneling or bar.isInEditMode) then bar:Hide() end
		end
		if ns.ReapplyCastBar then ns.ReapplyCastBar(bar) end -- (unless CineMode has it faded: Cast bar row)
	end
end
local tooltipFaded = false
local function UpdateTooltip()
	local alpha = FadeWanted("teleportVisionFadeTooltip")
	if alpha then
		tooltipFaded = true
		GameTooltip:SetAlpha(alpha)
	elseif tooltipFaded then
		tooltipFaded = false
		GameTooltip:SetAlpha(1)
	end
end
-- (A tooltip that comes up meanwhile shows at full: faded straight away.)
GameTooltip:HookScript("OnShow", function() if tooltipFaded then UpdateTooltip() end end)
local hookedBars = {}
-- (Set each frame while it lasts: the bar's own events alone come too seldom
-- for a smooth fade. It runs on till both are back.)
local castFader = CreateFrame("Frame")
castFader:Hide()
castFader:SetScript("OnUpdate", function(self)
	for bar in pairs(hookedBars) do UpdateCastBar(bar) end
	UpdateTooltip()
	if not FadeWanted("teleportVisionHideCast") and not FadeWanted("teleportVisionFadeTooltip") then
		self:Hide()
	end
end)
local barWatcher = CreateFrame("Frame")
barWatcher:RegisterEvent("PLAYER_LOGIN")
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
	barWatcher:RegisterUnitEvent(event, "player")
end
barWatcher:SetScript("OnEvent", function()
	for _, name in ipairs(CAST_BARS) do
		local bar = _G[name]
		if bar and bar.HookScript and not hookedBars[bar] then
			hookedBars[bar] = true
			bar:HookScript("OnEvent", UpdateCastBar)
			bar:HookScript("OnShow", UpdateCastBar)
		end
	end
	-- (After Camera.lua has noted the cast, or its end: next frame. One more
	-- run puts back what was faded, on a cancel too.)
	C_Timer.After(0, function() castFader:Show() end)
end)

-- The page's test: a pretend cast of TEST_TIME seconds (again: stop).
function ns.TestTeleportVision()
	if test and not test.done then
		test.done, test.doneAt = "cancelled", GetTime()
		return
	end
	local now = GetTime()
	test = { startAt = now, endsAt = now + TEST_TIME }
end
function ns.TeleportVisionTesting() return test ~= nil and not test.done end

-- /cine teleport colors [seconds]: every class and spec's color in turn, a
-- pretend cast each (4 seconds if not given), its class, spec and theme in the
-- middle of the screen, numbered, to record; again or off: stop.
local reel, reelLabel
local function StopReel()
	if reel then reel:Cancel() reel = nil end
	if reelLabel then reelLabel:GetParent():Hide() end
end
function ns.TeleportColorReel(arg)
	if reel or arg == "off" then
		StopReel()
		if test and not test.done then test.done, test.doneAt = "cancelled", GetTime() end
		ns.Print(L["Tele Vision colors: stopped."])
		return
	end
	if not reelLabel then
		local holder = CreateFrame("Frame", nil, UIParent)
		holder:SetAllPoints(UIParent)
		holder:SetFrameStrata("HIGH")
		holder:EnableMouse(false)
		ns.AddOverlay(holder)
		reelLabel = holder:CreateFontString(nil, "OVERLAY", "GameFont_Gigantic")
		reelLabel:SetPoint("CENTER", 0, 160)
		reelLabel:SetShadowOffset(2, -2)
		reelLabel.sub = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		reelLabel.sub:SetPoint("TOP", reelLabel, "BOTTOM", 0, -8)
	end
	-- (Every spec in the theme menu's order, each once.)
	local list = {}
	for _, class in ipairs(ns.LOW_HEALTH_MENU or {}) do
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class[1]] or L[class[2]]
		local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class[1]]
		for _, spec in ipairs(class[3]) do
			if spec[1] ~= "No talents yet" then
				local line = L[spec[1]] .. " " .. name
				if color then
					line = ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, line)
				end
				list[#list + 1] = { text = line, key = spec[2] }
			end
		end
	end
	local seconds = math.max(2, tonumber(arg) or 4)
	local at = 0
	local function Next()
		at = at + 1
		local entry = list[at]
		if not entry then
			StopReel()
			ns.Print(L["Tele Vision colors: all %d shown."]:format(#list))
			return
		end
		local theme = ns.LOW_HEALTH_THEME[entry.key]
		reelLabel:SetText(entry.text)
		reelLabel.sub:SetText(("%d / %d  ·  %s (%s)"):format(at, #list, theme and L[theme.name] or entry.key, entry.key))
		reelLabel:GetParent():Show()
		local now = GetTime()
		test = { startAt = now, endsAt = now + seconds, themeKey = entry.key }
	end
	Next()
	reel = C_Timer.NewTicker(seconds + GONE_TIME + 0.3, Next)
	ns.Print(L["Tele Vision colors: %d specs, %d seconds each (/cine teleport colors again to stop)."]:format(
		#list, seconds))
end

-- (Its icon's tooltip in the Visions hub: an easter egg. An L key, looked up as it shows.)
ns.TILE_TOOLTIPS = ns.TILE_TOOLTIPS or {}
ns.TILE_TOOLTIPS["Teleport Vision"] = "Tele Vision (Rules the Nation)"

-- The page (Visions, World): its switch, the colour, the strength, the motes and a test.
function ns.CreateTeleportVisionPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Tele Vision"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["As you cast your Hearthstone, Astral Recall or a teleport, a portal's glowing rim closes in round " ..
		"you, brighter and turning quicker as the cast fills, and flashes as you're whisked away. It shows " ..
		"whenever the tele camera would play for that cast (Cameras), with or alongside it."])
	local function Changed() end
	local switch = kit.PageSwitch(content, "teleportVision", L["Enable Page"],
		L["On: it shows as you cast. Off: it doesn't, and keeps its settings for when you turn this back on."],
		intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed)
	local function On() return ns.GetDB() and ns.GetDB().teleportVision end

	stack:Header(content, L["Look"])
	-- Color: like Vitals Vision's theme menu. Auto (your class and spec's, as
	-- they change), any class and spec's, or your own (the swatch beside it).
	local function ClassName(class)
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class[1]] or L[class[2]]
		local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class[1]]
		if color then name = ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name) end
		return name
	end
	local function ThemeName(key)
		local theme = key and ns.LOW_HEALTH_THEME and ns.LOW_HEALTH_THEME[key]
		return theme and L[theme.name] or tostring(key)
	end
	local function AutoText()
		return L["Auto"] .. ": " .. ThemeName(ns.LowHealthAutoTheme and ns.LowHealthAutoTheme())
	end
	local picker = rows.Dropdown(L["Color:"], "teleportVisionColor", function()
		local list = { { value = "spec", text = AutoText() } }
		for _, class in ipairs(ns.LOW_HEALTH_MENU or {}) do
			for _, spec in ipairs(class[3]) do
				if spec[1] ~= "No talents yet" then
					list[#list + 1] = { value = spec[2], text = L[spec[1]] .. " " .. ClassName(class) .. ": " ..
						ThemeName(spec[2]) }
				end
			end
		end
		list[#list + 1] = { value = "custom", text = L["Your own color"] }
		return list
	end, L["Its color. Auto: your class and spec's (the glow of the Vitals Vision theme Auto picks for you), " ..
		"changing with your spec. Or pick any class and spec's, or your own color beside this."], On)
	if picker and picker.SetupMenu then
		picker:SetupMenu(function(_, root)
			local function Picked(value) return ns.GetDB() and ns.GetDB().teleportVisionColor == value end
			local function Pick(value)
				ns.GetDB().teleportVisionColor = value
				kit.Refresh()
			end
			root:CreateRadio(AutoText(), function() return Picked("spec") end, function() Pick("spec") end)
			root:CreateDivider()
			for _, class in ipairs(ns.LOW_HEALTH_MENU or {}) do
				local menu = root:CreateButton(ClassName(class))
				for _, spec in ipairs(class[3]) do
					local key = spec[2]
					if spec[1] ~= "No talents yet" then
						menu:CreateRadio(L[spec[1]] .. ": " .. ThemeName(key), function() return Picked(key) end,
							function() Pick(key) end)
					end
				end
			end
			root:CreateDivider()
			root:CreateRadio(L["Your own color"], function() return Picked("custom") end, function() Pick("custom") end)
		end)
	end
	if picker then
		-- (Beside the picker, not on its own text inside it: it sat over the picker's end.)
		local swatch = rows.Swatch(picker, "teleportVisionColor", { "teleportVisionR", "teleportVisionG",
			"teleportVisionB" }, L["Your own color for it."], On)
		swatch:ClearAllPoints()
		swatch:SetPoint("LEFT", picker, "RIGHT", 10, 0)
		picker.besideSwatch = swatch
	end
	local strength = stack:Add(kit.Slider(content, "teleportVisionAlpha", L["Strength"], 0, 100, 5, "%d%%", 100,
		Changed), "slider")
	kit.Tooltip(strength, L["How strong it is as the cast ends (it starts faint)."])
	kit.GreyUnless(strength, On)
	local darkness = stack:Add(kit.Slider(content, "teleportVisionDark", L["Darkness"], 0, 100, 5, "%d%%", 100,
		Changed), "slider")
	kit.Tooltip(darkness, L["How dark the world gets outside the portal's rim, in a deep shade of its color."])
	kit.GreyUnless(darkness, On)
	rows.Check("teleportVisionClouds", L["Swirling clouds"], L["Clouds in a deep shade of its color, swirling " ..
		"round outside the rim, so the portal fills the screen."], On)
	rows.Check("teleportVisionEdges", L["Black edges"], L["Black edges closing in from the screen's sides as " ..
		"the cast fills, then over the whole screen at the last moment."], On)
	local function Edges() return On() and ns.GetDB().teleportVisionEdges end
	for _, info in ipairs({
		{ "teleportVisionEdgeReach", L["Edge reach"], 5, 50, 1, "%d%%", 100,
			L["How far in the black edges come as the cast fills (a share of the screen from each side)."] },
		{ "teleportVisionEdgeAlpha", L["Edge darkness"], 0, 100, 5, "%d%%", 100, L["How dark the black edges get."] },
		{ "teleportVisionEdgeClose", L["Blackout"], 0, 3, 0.1, "%.1f sec", 1,
			L["How long before the cast ends the black takes over the whole screen. 0: it doesn't."] },
	}) do
		local slider = stack:Add(kit.Slider(content, info[1], info[2], info[3], info[4], info[5], info[6], info[7],
			Changed), "slider")
		kit.Tooltip(slider, info[8])
		kit.GreyUnless(slider, Edges)
	end
	rows.Check("teleportVisionHideCast", L["Fade out your cast bar"], L["Your cast bar fades out over the " ..
		"first 3 seconds of the cast, so you see it start, then the portal closing in is its progress. Other " ..
		"casts show it as usual."], On)
	rows.Check("teleportVisionFadeTooltip", L["Fade out the tooltip"], L["The tooltip fades out over the " ..
		"first 3 seconds of the cast too, and comes back as the cast ends or is cancelled."], On)
	rows.Check("teleportVisionMotes", L["Motes spiraling in"], L["Motes of its color winding in from the rim."],
		On)

	-- Test: a pretend cast, Stop while it runs (as the camera tests), at the
	-- right end of the Color row (else a row of its own).
	local button = ns.PanelButton(content)
	button:SetSize(100, 22)
	if picker then
		button:SetPoint("LEFT", picker.besideSwatch or picker, "RIGHT", 12, 0)
	else
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(300, 26)
		stack:Add(row, "label")
		button:SetPoint("LEFT", row, "LEFT")
	end
	local function Label() button:SetText(ns.TeleportVisionTesting() and L["Stop"] or L["Test"]) end
	button:SetScript("OnClick", function()
		ns.TestTeleportVision()
		Label()
	end)
	button:SetScript("OnUpdate", Label)
	button.Refresh = Label -- (before GreyUnless, which wraps it)
	kit.Tooltip(button,L["A pretend 8-second cast, on the screen (close the settings to see it)."])
	kit.GreyUnless(button, On)
	kit.AddControl(button)
	Label()

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Teleport Vision")
end
