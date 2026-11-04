-- Dev copy only (CinematicDev.toc; .pkgmeta leaves it out): /cine debug
-- screenfx plays the game's own full-screen effects (ScreenEffectsData.lua,
-- every one in the game's data) over the screen, animated, one at a time, to
-- pick looks for Vitals Vision and the like. Drawn by ScreenEffects.lua's
-- drawer (how, and the measured units, there); speed and tile multiply its
-- own, to adjust by eye.
-- Space: next, Backspace: back, while it shows (not in a fight).
-- /cine debug screenfx shots: a screenshot of each, to review them all.

local _, ns = ...

-- Hand fixes by effect id, from reviewing the shots: skip (broken or empty),
-- tile / speed (multiplies the knobs), alpha (the scrolling layers), tint
-- (the colour wash), noMask (the shape layer hides everything), swap (use
-- layer 2 as the shape). Not made by the generator: kept across rebuilds.
local FIXES = {
	[133] = { skip = "its overlay is lettering" },
	[263] = { skip = "a plain rectangle (a UI mask)" },
	[264] = { skip = "a plain rectangle (a UI mask)" },
	-- (Second shots review: these flooded the whole screen in their colour.)
	[181] = { alpha = 0.25, tint = 0.05 },
	[212] = { alpha = 0.25, tint = 0.05 },
}
ns.SCREEN_EFFECT_FIXES = FIXES

local scout, shooter, effect
local at = 0
local speed, tile = 1, 1
local SHOT_WAIT = 2.5 -- (seconds on each before its screenshot: past the fade-in, moving)

-- (ns.SetOnUpdate where the protected one is loaded, else a plain OnUpdate.)
local function SetOnUpdate(frame, fn)
	if ns.SetOnUpdate then ns.SetOnUpdate(frame, fn) else frame:SetScript("OnUpdate", fn) end
end

local function Create()
	scout = CreateFrame("Frame", nil, UIParent)
	scout:SetAllPoints(UIParent)
	scout:SetFrameStrata("BACKGROUND")
	scout:SetFrameLevel(1)
	scout:EnableMouse(false)
	-- (Stays up when the UI fades or hides: the first shots run, 2026-11-04,
	-- faded out with the UI and caught nothing.)
	ns.AddOverlay(scout)
	effect = ns.NewScreenEffect(scout)
	-- (The text on its own frame, over everything, not cut by the mask.)
	local box = CreateFrame("Frame", nil, scout)
	box:SetFrameStrata("FULLSCREEN_DIALOG")
	box:SetPoint("TOPLEFT")
	box:SetPoint("TOPRIGHT")
	box:SetHeight(92)
	local back = box:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.7)
	scout.lines = {}
	for i, font in ipairs({ "GameFontNormalLarge", "GameFontHighlight", "GameFontHighlight", "GameFontHighlightSmall" }) do
		local line = box:CreateFontString(nil, "OVERLAY", font)
		line:SetPoint("TOP", 0, -8 - (i - 1) * 20)
		line:SetWidth(1400)
		line:SetWordWrap(false)
		scout.lines[i] = line
	end
	SetOnUpdate(scout, function(self, elapsed)
		local fx = self.fx
		if not fx then return end
		self.time = self.time + elapsed
		effect:Place(self:GetSize())
		effect:Step(elapsed)
		-- (Fades in over the effect's own fade-in time.)
		local fadeIn = math.max((fx.fade[1] or 0) / 1000, 0.05)
		effect:SetAlpha(math.min(self.time / fadeIn, 1))
	end)
	scout:EnableKeyboard(true)
	scout:SetPropagateKeyboardInput(true)
	scout:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() or (shooter and shooter:IsShown()) then return end
		local step = (key == "SPACE" and 1) or (key == "BACKSPACE" and -1) or nil
		self:SetPropagateKeyboardInput(not step)
		if step then ns.ScoutScreenEffects(step > 0 and "" or "back") end
	end)
	scout:Hide()
end

local function Show(index)
	local list = ns.SCREEN_EFFECTS
	at = (index - 1) % #list + 1
	local fx = list[at]
	local fix = FIXES[fx.id] or {}
	scout.fx, scout.time = fx, 0
	effect:Place(scout:GetSize())
	local _, skip, missing = effect:Set(fx, { tile = tile * (fix.tile or 1), speed = speed * (fix.speed or 1),
		alpha = fix.alpha, tint = fix.tint, noMask = fix.noMask, swap = fix.swap, skip = fix.skip })
	effect:SetAlpha(0)
	local mul = fx.multiply
	local files = {}
	for i, layer in ipairs(fx.layers) do
		files[#files + 1] = ("%d: %d (x%s y%s, scroll %s %s)"):format(i, layer[1], layer[2], layer[3], layer[4], layer[5])
	end
	local fixed = {}
	for key, value in pairs(fix) do fixed[#fixed + 1] = key .. "=" .. tostring(value) end
	if skip and not fix.skip then fixed[#fixed + 1] = "skip=" .. skip end
	table.sort(fixed)
	scout.lines[1]:SetText(("%d of %d   |   effect %d   |   %s"):format(at, #list, fx.id, fx.name))
	scout.lines[2]:SetText(("overlay %s   |   layers %s"):format(fx.overlay ~= 0 and fx.overlay or "none",
		#files > 0 and table.concat(files, "   ") or "none"))
	scout.lines[3]:SetText(("multiply %s %s %s x%s   |   add %s %s %s x%s   |   mask offset %s, size %s   |   saturation %s, blur %s")
		:format(mul[1], mul[2], mul[3], mul[4] or 1, fx.add[1], fx.add[2], fx.add[3], fx.add[4], fx.mask[1], fx.mask[2],
			fx.saturation, fx.blur))
	scout.lines[4]:SetText((#missing > 0 and ("|cffff6060not on this client: %s|r   |   "):format(table.concat(missing, ", "))
		or "") .. (#fixed > 0 and ("|cff60ff60fixed: %s|r   |   "):format(table.concat(fixed, " ")) or "")
		.. ("speed %s, tile %s   |   Space: next, Backspace: back"):format(speed, tile))
	scout:Show()
end

-- A screenshot of each from a list number on, SHOT_WAIT seconds apart (the
-- game's "Screen captured" hidden so it isn't in the next one).
local function Shoot(from)
	if not shooter then
		shooter = CreateFrame("Frame")
		shooter:Hide()
		-- (The screenshot is taken at the end of the frame it's asked in, so
		-- the next effect is shown a frame later: asked and moved on in one
		-- go, every shot caught the next effect at the start of its fade-in,
		-- all but invisible, 2026-11-04.)
		SetOnUpdate(shooter, function(self, elapsed)
			self.left = self.left - elapsed
			if self.left > 0 then return end
			if not self.snapped then
				self.snapped = true
				Screenshot()
				return
			end
			self.snapped = nil
			if at >= #ns.SCREEN_EFFECTS then
				self:Hide()
				if ActionStatus then ActionStatus:SetAlpha(1) end
				ns.Print("screen effects: shots done (Screenshots folder)")
				return
			end
			Show(at + 1)
			self.left = SHOT_WAIT
		end)
	end
	if ActionStatus then ActionStatus:SetAlpha(0) end
	Show(from)
	shooter.left, shooter.snapped = SHOT_WAIT, nil
	shooter:Show()
	local total = (#ns.SCREEN_EFFECTS - at + 1) * SHOT_WAIT
	ns.Print(("screen effects: a screenshot of each from %d, %d:%02d in all (off: /cine debug screenfx off)")
		:format(at, math.floor(total / 60), total % 60))
end

-- /cine debug screenfx [number | id N | find words | speed N | tile N | shots [from] | back | off]
function ns.ScoutScreenEffects(arg)
	local list = ns.SCREEN_EFFECTS
	if not list then ns.Print("/cine debug screenfx is in the dev copy only.") return end
	arg = arg or ""
	if arg == "off" then
		if scout then scout:Hide() end
		if shooter and shooter:IsShown() then
			shooter:Hide()
			if ActionStatus then ActionStatus:SetAlpha(1) end
		end
		ns.Print("screen effects: off")
		return
	end
	if not scout then Create() end
	local word, rest = arg:match("^(%S+)%s*(.-)$")
	if word == "shots" then
		Shoot(math.max(math.floor(tonumber(rest) or 1), 1))
		return
	elseif word == "speed" and tonumber(rest) then
		speed = tonumber(rest)
	elseif word == "tile" and tonumber(rest) then
		tile = tonumber(rest)
	elseif word == "id" and tonumber(rest) then
		for i, fx in ipairs(list) do
			if fx.id == tonumber(rest) then at = i end
		end
	elseif word == "find" and rest ~= "" then
		local found
		for step = 1, #list do
			local i = (at + step - 1) % #list + 1
			if list[i].name:lower():find(rest:lower(), 1, true) then found = i break end
		end
		if not found then ns.Print("screen effects: no name has " .. rest) return end
		at = found
	elseif word == "back" then
		at = at - 1
	elseif tonumber(arg) then
		at = tonumber(arg)
	elseif arg == "" then
		at = at + 1
	else
		ns.Print("/cine debug screenfx [number | id N | find words | speed N | tile N | shots [from] | back | off]")
		return
	end
	if at < 1 then at = #list end
	Show(at)
end
