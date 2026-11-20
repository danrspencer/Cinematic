-- /cine debug hvicons: one run for a player's report (2026-11-20) on Heal
-- Vision's nameplates: (1) class icons stay on plates Heal Vision has
-- faded; (2) an "Interrupted" cast bar shows over healthy players in fights.
-- It runs itself, out of a fight near other players (a city is fine: Heal
-- Vision's rule is "not dead" for the run); the
-- only thing it asks is that you stand near some. CineMode ON for the run
-- (2026-11-20: outside it Forever built no friendly player plates even with
-- every plate setting on; CineMode holds them for Heal Vision, proven).
-- For the run (all put back after, a /reload too): Heal Vision's plates on
-- Nameplates, Other players never shown by health (every stranger's plate
-- should be gone), friendly class icons Always, friendly players' plates on
-- with their bars (cast bars live on full plates only).
--   1 icons     every held stranger plate: its class and role icon frames,
--               shown or not, their frame and picture alphas. Any icon up
--               on a plate that should be gone: FAIL. Screenshot.
--   2 everything every picture and text on those plates: any still showing,
--               by name (the catch-all, after the icons slipped through).
--   3 cast      one held stranger plate: which frames are its cast bar part
--               (the container or the bar), then the game's own interrupt
--               played on its cast bar (CastingBarMixin's), Heal Vision told
--               as the game would. Every frame for 3 s: the bar's shown,
--               its alpha, its container's, its fade animation, its text.
--               Up past Heal Vision's 1 s re-fade: FAIL. Screenshots.
-- Into CinematicDB.hvIconsLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local SETTLE = 2
local WATCH = 3 -- seconds the cast bar is watched
local MAX_PLATES = 6

local run
local function Say(text)
	local log = CinematicDB and CinematicDB.hvIconsLog
	if log then log[#log + 1] = ("%.2f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Check(what, ok, detail)
	if ok then run.pass = run.pass + 1 else run.fail = run.fail + 1 end
	Say(("  %s %s: %s"):format(ok and "PASS" or "FAIL", what, detail))
end
local function Secret(value) return issecretvalue and issecretvalue(value) end
local function Plain(value) if Secret(value) then return nil end return value end
local function Show(value)
	if Secret(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Read(frame, method, ...)
	if not (frame and frame[method]) then return nil end
	local ok, value = pcall(frame[method], frame, ...)
	return ok and value or nil
end
local function Name(frame)
	local ok, name = pcall(function() return frame:GetDebugName() end)
	return ok and name and tostring(name):match("[^%.]+%.?[^%.]*$") or tostring(frame)
end
local function Cine() return ns.lastCinematic and true or false end
local function SetCine(want)
	if Cine() ~= want and _G.Cinematic_ToggleCineMode then pcall(_G.Cinematic_ToggleCineMode) end
end
local function Screenshot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() _G.Screenshot() end)
	Say(("  screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end

-- The run's settings: [key] = value, and the game settings: [cvar] = value.
local SETTINGS = { healVisionPlates = true, healVisionPlatesShow = "plates", healVisionPlateOthersBelow = 0,
	plateIconAlwaysClassFriendly = true }
-- (No game settings of its own: CineMode holds the plates. Outside it, every
-- friendly plate setting on still gave none on Forever, 2026-11-20.)

local function PutBack()
	local saved = CinematicDB and CinematicDB.hvIconsRestore
	if not (saved and ns.db) or InCombatLockdown() then return end
	for key, value in pairs(saved.settings or {}) do ns.db[key] = value end
	if saved.hasRule and type(ns.db.frameRules) == "table" then ns.db.frameRules.healVision = saved.rule end
	for cvar, value in pairs(saved.cvars or {}) do pcall(SetCVar, cvar, value) end
	CinematicDB.hvIconsRestore = nil
	if ns.ApplyHealVisionPlates then ns.ApplyHealVisionPlates() end
	-- (CineMode as it was before the run.)
	C_Timer.After(0.5, function() SetCine(saved.cine and true or false) end)
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	C_Timer.After(2, PutBack)
end)

local function Plates()
	return C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
end
local function Grouped(unit)
	return Plain(UnitInParty and UnitInParty(unit)) == true or type(Plain(UnitInRaid and UnitInRaid(unit))) == "number"
end
-- Friendly strangers' plates Heal Vision holds now.
local function HeldStrangers()
	local out = {}
	for _, plate in ipairs(Plates()) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit) -- (Forever: the latter)
		-- (By Effects.lua's PlateKind, as Heal Vision itself: on Forever
		-- UnitIsPlayer and UnitIsFriend can say no for players; it falls back
		-- on their GUID. Seen 2026-11-20: 0 found with players all around.)
		if type(unit) == "string" and not Secret(unit) and ns.PlateKind and ns.PlateKind(unit) == "Friends"
			and not Plain(UnitIsUnit(unit, "player")) and not Grouped(unit)
			and ns.HealVisionPlateUnit and ns.HealVisionPlateUnit(unit) then
			out[#out + 1] = { unit = unit, plate = plate }
		end
	end
	return out
end

local function IconLine(label, icon)
	if not icon then return label .. " none made", false end
	local shown = Read(icon, "IsVisible")
	local frameAlpha = Read(icon, "GetAlpha")
	local pictureAlpha = icon.texture and Read(icon.texture, "GetAlpha")
	local up = Plain(shown) == true and (Plain(frameAlpha) or 1) > 0.05
		and (Secret(pictureAlpha) and true or (Plain(pictureAlpha) or 1) > 0.05)
	return ("%s shown %s, frame alpha %s, picture alpha %s, effective %s"):format(label, Show(shown), Show(frameAlpha),
		Show(pictureAlpha), Show(Read(icon, "GetEffectiveAlpha"))), up and not Secret(pictureAlpha)
end

-- What a waiting step is short of, for the box (it never waits silently).
local function Missing()
	local total, kinds, held = 0, {}, #HeldStrangers()
	for _, plate in ipairs(Plates()) do
		total = total + 1
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit) -- (Forever: the latter)
		local kind = type(unit) == "string" and not Secret(unit) and ns.PlateKind and ns.PlateKind(unit) or "?"
		kinds[kind] = (kinds[kind] or 0) + 1
	end
	local list = {}
	for kind, count in pairs(kinds) do list[#list + 1] = kind .. " " .. count end
	table.sort(list)
	return ("CineMode %s; plates %d (%s); friendly players setting %s; held by Heal Vision %d (on here %s)"):format(
		Cine() and "ON" or "off", total, #list > 0 and table.concat(list, ", ") or "none",
		tostring(GetCVar("nameplateShowFriendlyPlayers")), held, tostring(ns.HealVisionPlatesOn and ns.HealVisionPlatesOn()))
end

-- The steps: each waits for ready(), settles, then checks().
local STEPS = {}
-- (Friendly players' plates on, once CineMode is fully off: its letting go
-- puts your own settings back, over ours if they came first.)
STEPS[#STEPS + 1] = { key = "setup", ask = "Setting up: turning CineMode on.",
	ready = function() return Cine() end,
	checks = function()
		-- (CineMode holds friendly plates and their bars for Heal Vision itself.)
		if ns.ApplyHealVisionPlates then ns.ApplyHealVisionPlates() end
		Say("  " .. Missing())
	end }
STEPS[#STEPS + 1] = { key = "icons", ask = "Stand near other players (not in your group), out of a fight. A city is fine.",
	ready = function() return Cine() and #HeldStrangers() > 0 end,
	checks = function()
		local list = HeldStrangers()
		Say(("  %d stranger plates held by Heal Vision"):format(#list))
		local up, seen = 0, 0
		for i, each in ipairs(list) do
			if i > MAX_PLATES then break end
			local class, role
			if ns.PlateIconFrames then class, role = ns.PlateIconFrames(each.plate) end
			local classLine, classUp = IconLine("class icon", class)
			local roleLine, roleUp = IconLine("role icon", role)
			Say(("  %s: %s; %s"):format(tostring(Plain(UnitName(each.unit))), classLine, roleLine))
			if class or role then seen = seen + 1 end
			if classUp or roleUp then up = up + 1 end
		end
		Check("an icon was made to look at", seen > 0, ("%d plates with an icon"):format(seen))
		Check("no class or role icon up on a plate Heal Vision hides", up == 0,
			("%d plates with an icon up (the screenshot shows them)"):format(up))
		Screenshot("icons")
	end }
-- The catch-all (2026-11-20, after the class icons slipped through): every
-- picture and text on a plate Heal Vision hides, any that still shows. Shown
-- (IsVisible), with a size, a text with words, and no alpha on it or up its
-- parents to the plate at (near) nothing; a secret alpha on the way counts as
-- faded (Heal Vision's curve). Each read guarded; at most WALK_MAX things a
-- plate, so a strange plate can't stall the run. [plate] -> { lines }.
local WALK_MAX = 600
local function ShortName(object)
	local ok, name = pcall(function() return object:GetDebugName() end)
	name = ok and type(name) == "string" and name or tostring(object)
	return name:gsub("^NamePlate%d+%.", ""):sub(1, 60)
end
local function Showing(region, plate)
	local okShown, shown = pcall(region.IsVisible, region)
	if not okShown or Plain(shown) ~= true then return false end
	local okW, width = pcall(region.GetWidth, region)
	local okH, height = pcall(region.GetHeight, region)
	if okW and okH and Plain(width) and Plain(height) and (width <= 0.5 or height <= 0.5) then return false end
	if region.GetText then
		local okText, text = pcall(region.GetText, region)
		if okText and not Secret(text) and (text == nil or text == "") then return false end
	end
	-- (Its alpha times its parents', up to the plate.)
	local alpha, object, steps = 1, region, 0
	while object and steps < 16 do
		local okA, a = pcall(object.GetAlpha, object)
		if not okA or Secret(a) then return false end
		alpha = alpha * (tonumber(a) or 1)
		if object == plate then break end
		local okP, parent = pcall(object.GetParent, object)
		object, steps = okP and parent or nil, steps + 1
	end
	return alpha > 0.05, alpha
end
local function StillShowing(plate)
	local found, queue, seen, count = {}, { plate }, {}, 0 -- (the plate itself down: anything hung on it)
	while #queue > 0 and count < WALK_MAX do
		local frame = table.remove(queue, 1)
		if frame and not seen[frame] then
			seen[frame] = true
			count = count + 1
			local okR, regions = pcall(function() return { frame:GetRegions() } end)
			for _, region in ipairs(okR and regions or {}) do
				count = count + 1
				local up, alpha = Showing(region, plate)
				if up then
					local okT, kind = pcall(region.GetObjectType, region)
					found[#found + 1] = ("%s (%s, alpha %.2f)"):format(ShortName(region), okT and tostring(kind) or "?", alpha)
				end
			end
			local okC, children = pcall(function() return { frame:GetChildren() } end)
			for _, child in ipairs(okC and children or {}) do queue[#queue + 1] = child end
		end
	end
	return found, count
end

ns.HealIconsStillShowing = StillShowing -- (Tools' offline smoke run of the catch-all)

STEPS[#STEPS + 1] = { key = "everything", ready = function() return Cine() and #HeldStrangers() > 0 end,
	checks = function()
		local total = 0
		for i, each in ipairs(HeldStrangers()) do
			if i > MAX_PLATES then break end
			local found, walked = StillShowing(each.plate)
			total = total + #found
			local list = {}
			for n = 1, math.min(#found, 8) do list[n] = found[n] end
			Say(("  %s: %d things looked at, %d still showing%s"):format(tostring(Plain(UnitName(each.unit))), walked,
				#found, #found > 0 and (": " .. table.concat(list, "; ") .. (#found > 8 and "; ..." or "")) or ""))
		end
		Check("nothing on a plate Heal Vision hides still shows", total == 0,
			("%d things showing (named above; the screenshot shows them)"):format(total))
		Screenshot("everything")
	end }
STEPS[#STEPS + 1] = { key = "cast", ready = function() return Cine() and #HeldStrangers() > 0 end,
	checks = function()
		local each = HeldStrangers()[1]
		local frame = each.plate.UnitFrame
		local bar = frame and (frame.castBar or frame.CastBar)
		-- (Forever: the bar sits inside CastBarsContainer, seen 2026-11-20: the
		-- container's child that's a status bar, the game's cast bar mixin's.)
		local box = frame and frame.CastBarsContainer
		if not bar and box then
			for _, child in ipairs({ box:GetChildren() }) do
				if child.HandleInterruptOrSpellFailed or (child.IsObjectType and child:IsObjectType("StatusBar")) then
					bar = child
					break
				end
			end
		end
		local parts = ns.PlatePartFrames and ns.PlatePartFrames(frame, "CastBar") or {}
		local names = {}
		for _, part in ipairs(parts) do names[#names + 1] = Name(part) end
		Say(("  %s's cast bar: %s; its part frames (Heal Vision fades inside these): %s; container %s"):format(
			tostring(Plain(UnitName(each.unit))), bar and Name(bar) or "none", table.concat(names, ", "),
			tostring(frame and frame.CastBarsContainer and Name(frame.CastBarsContainer))))
		if not bar then
			Check("a cast bar to play on", false, "none on this plate")
			return
		end
		Say(("  bar: FadeOutAnim %s, HandleInterruptOrSpellFailed %s, PlayInterruptAnims %s, holdTime %s"):format(
			tostring(bar.FadeOutAnim ~= nil), tostring(bar.HandleInterruptOrSpellFailed ~= nil),
			tostring(bar.PlayInterruptAnims ~= nil), Show(bar.holdTime)))
		-- The game's own interrupt on it, Heal Vision told as the game would.
		-- (Shown at full and its interrupt animations played, nothing more: on
		-- Forever the game's interrupt handler refuses ("secret keys"), and a
		-- bar marked casting with no progress made the game's bar error every
		-- frame, 2026-11-20. Put back after the watch: hidden, not casting.)
		local ok, err = pcall(function()
			bar:Show()
			bar:SetAlpha(1)
			if bar.PlayInterruptAnims then bar:PlayInterruptAnims() end
		end)
		Say("  interrupt played: " .. (ok and "yes" or ("error: " .. tostring(err))))
		if ns.HealVisionTestEvent then ns.HealVisionTestEvent("UNIT_SPELLCAST_INTERRUPTED", each.unit) end
		run.watch = { bar = bar, parts = parts, from = GetTime(), lastUp = nil, samples = 0, shots = {} }
	end,
	-- (Watched per frame after its checks: see the meter below.)
	watch = true }

local meter = CreateFrame("Frame")
meter:Hide()
ns.SetOnUpdate(meter, function()
	local w = run and run.watch
	if not w then return end
	local t = GetTime() - w.from
	local bar = w.bar
	local shown = Plain(Read(bar, "IsVisible")) == true
	local alpha = Read(bar, "GetAlpha")
	local fading = bar.FadeOutAnim and Read(bar.FadeOutAnim, "IsPlaying")
	local text = bar.Text and Read(bar.Text, "GetText")
	local container = w.parts[1] ~= bar and w.parts[1] or nil
	w.samples = w.samples + 1
	if shown and (Secret(alpha) or (Plain(alpha) or 0) > 0.05) then w.lastUp = t end
	if w.samples % 6 == 1 then
		Say(("    %.2f s: bar shown %s, alpha %s, effective %s, fading %s, text %s; container alpha %s"):format(t,
			tostring(shown), Show(alpha), Show(Read(bar, "GetEffectiveAlpha")), Show(fading), Show(text),
			container and Show(Read(container, "GetAlpha")) or "-"))
	end
	for _, at in ipairs({ 0.2, 0.9, 1.5 }) do
		if t >= at and not w.shots[at] then
			w.shots[at] = true
			Screenshot(("cast %.1f s"):format(at))
		end
	end
	if t >= WATCH then
		run.watch = nil
		meter:Hide()
		pcall(function() bar.casting, bar.channeling = nil, nil bar:Hide() end)
		-- (The bar's own alpha is the game's, often secret: what decides is
		-- its container, faded by Heal Vision since 2026-11-20 (its alpha
		-- then secret, the curve's), so nothing on the bar can show through.)
		local container = w.parts[1] ~= bar and w.parts[1] or nil
		local boxAlpha = container and Read(container, "GetAlpha")
		Check("the cast bar's container is faded by Heal Vision", container ~= nil
			and (Secret(boxAlpha) or (Plain(boxAlpha) or 1) <= 0.05),
			("container %s, alpha %s; the bar was forced on at full for %d s (the screenshots show it unseen)"):format(
				container and Name(container) or "none", Show(boxAlpha), WATCH))
		run.index, run.phase = run.index + 1, "start"
	end
end)

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	meter:Hide()
	Say(("done: %d PASS, %d FAIL%s"):format(run.pass, run.fail, done and "" or " (stopped early)"))
	run = nil
	PutBack()
	ns.PadTestBox(done and "Test done. /reload, then say \"check log\"." or "Test stopped. /reload, then say \"check log\".",
		"", 1, 0.82, 0)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function Tick()
	if run.watch then return end
	local step = STEPS[run.index]
	if not step then
		Finish(true)
		return
	end
	if InCombatLockdown() then
		ns.PadTestBox(("%d/%d: leave the fight first"):format(run.index, #STEPS), "WAITING FOR YOU", 1, 0.82, 0)
		return
	end
	if run.phase == "start" then
		Say(("--- step %d: %s ---"):format(run.index, step.key))
		run.phase, run.phaseAt = "wait", GetTime()
		return
	end
	if run.phase == "wait" then
		if step.ready() then
			run.phase, run.phaseAt = "settle", GetTime()
		else
			ns.PadTestBox(("%d/%d: %s"):format(run.index, #STEPS, step.ask or "HANDS OFF"), "WAITING FOR YOU: " .. Missing(),
				1, 0.82, 0)
			-- (In the log too, every 5 s: what it's waiting on.)
			if GetTime() - (run.saidWait or 0) >= 5 then
				run.saidWait = GetTime()
				Say("  waiting: " .. Missing())
			end
		end
		return
	end
	if run.phase == "settle" then
		if GetTime() - run.phaseAt < SETTLE then
			ns.PadTestBox(("%d/%d: HANDS OFF"):format(run.index, #STEPS), "checking", 0.3, 1, 0.3)
			return
		end
		local ok, err = pcall(step.checks)
		if not ok then Say("  error in checks: " .. tostring(err)) end
		if step.watch and run.watch then
			ns.PadTestBoxHide()
			meter:Show()
		else
			run.index, run.phase = run.index + 1, "start"
		end
	end
end

function ns.HealIconsCastTest()
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then
		ns.Print("heal vision icons test: not in a fight")
		return
	end
	CinematicDB.hvIconsLog = {}
	local saved = { settings = {}, cvars = {}, cine = Cine() }
	for key, value in pairs(SETTINGS) do
		saved.settings[key] = ns.db[key]
		ns.db[key] = value
	end
	-- (Heal Vision's rule "not dead" for the run, not "not city and not dead":
	-- the test runs in a city too, where crowds are.)
	if type(ns.db.frameRules) == "table" then
		saved.hasRule, saved.rule = true, ns.db.frameRules.healVision
		ns.db.frameRules.healVision = "not dead"
	end
	SetCine(true)
	CinematicDB.hvIconsRestore = saved
	if ns.ApplyHealVisionPlates then ns.ApplyHealVisionPlates() end
	run = { at = GetTime(), index = 1, phase = "start", pass = 0, fail = 0 }
	Say(("start: %s (game %s), Cinematic %s, CineMode was %s; Heal Vision page %s, here %s, place %s; Icons page %s, "
		.. "Plate Cast Style %s"):format(ns.isRetail and "retail" or "classic", tostring((select(4, GetBuildInfo()))),
		ns.Version and ns.Version() or "?", tostring(saved.cine), tostring(ns.Setting("handleHealVision")),
		tostring(ns.HealVisionPlatesOn and ns.HealVisionPlatesOn()), tostring(ns.PlateSuffix and ns.PlateSuffix() or "open world"),
		tostring(ns.Setting("handlePlateIcons")), tostring(ns.StyleOn and ns.StyleOn("plateCastStyle"))))
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
	ns.Print("heal vision icons test: follow the box (type it again to stop)")
end
