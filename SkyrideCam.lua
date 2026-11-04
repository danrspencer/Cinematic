-- Skyriding Cam (skyrideCam, dev copy, retail): skyriding through the air,
-- the camera zooms all the way out so you can see where you're going, and
-- back to your own distance a moment after you land. It plays the built-in
-- Skyriding zoom camera script (CameraScripts.lua, made from this page's
-- settings; its runner's travel rules: steering doesn't stop it, scrolling
-- the zoom yourself does). "In the air" is the game's gliding info, on once
-- you've been up skyrideCamStart seconds and off once you've been down
-- skyrideCamLand (ns.SkyridingNow, CameraScripts.lua).
-- Where: its Show in row (Always ticked to start with: everywhere).
-- /cine debug skyride logs what the game says while you fly.
local _, ns = ...
local L = ns.L

-- (Only where there's skyriding: retail's gliding info.)
if not (ns.isRetail and C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then return end
ns.SKYRIDE_CAM = true -- (it's here: /cine debug skyride says so)

local ROW_KEY = "skyride:cam"
ns.CINE_SHOW_SETTING[ROW_KEY] = "skyrideCamAlways"

-- Whether the camera may play now: the page on, and its Show in row here.
function ns.SkyrideCamOn()
	local db = ns.db
	if not (db and ns.Setting("skyrideCam")) then return false end
	if db.skyrideCamAlways then return true end
	local ok, here = pcall(ns.RowOnNow, ROW_KEY, false, true)
	return ok and here and true or false
end

function ns.CreateSkyrideCamPanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Skyriding Cam"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["While you skyride through the air, the camera zooms all the way out so you can see where you're going."])
	local switch = kit.PageSwitch(content, "skyrideCam", L["Enable Page"],
		L["On: taking to the air on a skyriding mount zooms the camera out, and landing brings it back to your " ..
		"own distance. Steering with the mouse doesn't stop it; scrolling the zoom yourself does. It plays the " ..
		"Skyriding zoom camera script, made from the settings below."], intro)
	local function IfOn() return ns.Setting("skyrideCam") end
	local stack = kit.Stack(switch, "check")

	local header = stack:Header(content, L["Show in"])
	local lastRow = ns.ShowTable(content, header, {
		opts = { quiet = true, cam = true, anyFight = true }, underHeader = true,
		{ key = ROW_KEY, label = L["Skyriding Cam"], alwaysKey = "skyrideCamAlways",
			alwaysOn = function() return ns.GetDB().skyrideCamAlways end,
			setAlways = function(value) ns.GetDB().skyrideCamAlways = value end,
			alwaysTip = L["Wherever you skyride. (The other columns then have nothing to add.)"] },
	}, L["Skyriding Cam"])
	stack:Continue(lastRow, "label")

	stack:Header(content, L["Zoom"])
	local distance = stack:Add(kit.Slider(content, "skyrideCamDistance", L["Zoom out to"], 10, 39, 1,
		L["%d yards"]), "slider")
	kit.Tooltip(distance, L["How far out the camera goes. 39 is as far as the game allows, past your own " ..
		"max camera distance for the flight."])
	kit.GreyUnless(distance, IfOn)
	local zoomTime = stack:Add(kit.Slider(content, "skyrideCamZoomTime", L["Zoom out over"], 1, 10, 0.5,
		L["%.1f sec"]), "slider")
	kit.GreyUnless(zoomTime, IfOn)
	local backTime = stack:Add(kit.Slider(content, "skyrideCamBackTime", L["Back in over"], 0.5, 10, 0.5,
		L["%.1f sec"]), "slider")
	kit.Tooltip(backTime, L["How long the camera takes to come back to your own distance after you land."])
	kit.GreyUnless(backTime, IfOn)

	stack:Header(content, L["Timing"])
	local start = stack:Add(kit.Slider(content, "skyrideCamStart", L["Start after"], 0, 3, 0.25,
		L["%.2f sec"]), "slider")
	kit.Tooltip(start, L["How long you're in the air before the camera zooms out, so a hop doesn't start it."])
	kit.GreyUnless(start, IfOn)
	local land = stack:Add(kit.Slider(content, "skyrideCamLand", L["End after landing"], 0, 10, 0.5,
		L["%.1f sec"]), "slider")
	kit.Tooltip(land, L["How long you're on the ground before the camera comes back in, so touching down " ..
		"between flaps doesn't bounce it."])
	kit.GreyUnless(land, IfOn)

	stack:Header(content, L["CineMode"])
	kit.GreyUnless(stack:Add(kit.Check(content, "skyrideCine", L["CineMode while skyriding"],
		L["With \"Start in CineMode\" off (Cinematic's main page), skyriding brings CineMode on (the UI " ..
		"fades as your Show in rows say) until you land."]), "check"), IfOn)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Skyriding Cam")
end

-- ---------------------------------------------------------------------------
-- /cine debug skyride: finding out what we can read and control while you
-- skyride (Tools/skyride-test-plan.md says what to fly for each).
--   skyride          what the game says now; again to start or stop the
--                    flight log: a line every LOG_EVERY seconds in the air,
--                    and the game's events as they come (gliding, casts,
--                    charges, settings the game changes itself, bars, fights)
--   skyride frames   the frames up now that look like skyriding's (vigor,
--                    widgets, the skyriding bar): shown, alpha, protected
--   skyride probe <zoom|turn|tilt|fov|follow>
--                    one of our camera moves or settings, tried now, before
--                    and after logged (for a macro, mid-flight)
-- All of it goes to the saved log (/reload to save it).
-- ---------------------------------------------------------------------------
do
	local LOG_EVERY, LOG_FOR = 0.25, 300
	local function V(value, fmt)
		if value == nil then return "nil" end
		if issecretvalue and issecretvalue(value) then return "secret" end
		if fmt and type(value) == "number" then return fmt:format(value) end
		return tostring(value)
	end
	local function Plain(value) return type(value) == "number" and not (issecretvalue and issecretvalue(value)) end
	local function Zoom() return GetCameraZoom and GetCameraZoom() end
	local function Glide()
		local ok, gliding, can, speed = pcall(C_PlayerInfo.GetGlidingInfo)
		if not ok then return "gliding info error", nil, nil, nil end
		return ("gliding %s, can %s, speed %s"):format(V(gliding), V(can), V(speed, "%.1f")), gliding, can, speed
	end
	local function Call(name, ...)
		local fn = _G[name]
		if not fn then return "nil" end
		local ok, a = pcall(fn, ...)
		return ok and V(a) or "error"
	end
	local function Facing()
		local ok, facing = pcall(GetPlayerFacing)
		return ok and Plain(facing) and math.deg(facing) or nil
	end
	-- The skyriding bar (the bonus bar while you skyride): each spell, and its
	-- charges. compact: only the spells with charges (vigor: Surge Forward's), by ID.
	local function Bar(compact)
		local index = _G.GetBonusBarIndex and _G.GetBonusBarIndex()
		if not Plain(index) or index == 0 then return ("bonus bar %s"):format(V(index)) end
		local first = ((_G.NUM_ACTIONBAR_PAGES or 6) + index - 1) * 12
		local parts = {}
		for slot = first + 1, first + 12 do
			local ok, kind, id = pcall(GetActionInfo, slot)
			if ok and kind == "spell" and Plain(id) then
				local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or tostring(id)
				local charges = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(id)
				local have = type(charges) == "table" and ("%s/%s"):format(V(charges.currentCharges), V(charges.maxCharges))
					or "-"
				if not compact then
					parts[#parts + 1] = ("%s %s %s"):format(V(name), V(id), have)
				elseif have ~= "-" then
					parts[#parts + 1] = ("%s %s"):format(V(id), have)
				end
			end
		end
		if compact then return ("charges %s"):format(#parts > 0 and table.concat(parts, ", ") or "none") end
		return ("bonus bar %d: %s"):format(index, #parts > 0 and table.concat(parts, ", ") or "no spells")
	end
	local function Where()
		local ok, y, x, z, instance = pcall(UnitPosition, "player")
		if not ok then return nil end
		return y, x, z, instance
	end
	local function Ours()
		local state = ns.CameraScriptState and ns.CameraScriptState()
		return ("Skyriding Cam page %s, may play here %s, cine %s; skyriding now %s; script %s; zoom %s, zoom speed %s, max factor %s, fov %s, follow %s"):format(
			ns.Setting("skyrideCam") and "on" or "off", tostring(ns.SkyrideCamOn()), tostring(ns.db.skyrideCine),
			tostring(ns.SkyridingNow and ns.SkyridingNow()),
			state and ("%s (%s)"):format(state.script and state.script.name or "?", tostring(state.phase)) or "none",
			V(Zoom(), "%.1f"), tostring(GetCVar("cameraZoomSpeed")), tostring(GetCVar("cameraDistanceMaxZoomFactor")),
			tostring(GetCVar("cameraFov")), tostring(GetCVar("cameraSmoothStyle")))
	end
	local function Log(text) ns.Log("skyride", text) end

	-- The flight log: a line LOG_EVERY seconds while you're in the air (and at
	-- once as gliding or can-glide changes), the events as they come.
	local logger = CreateFrame("Frame")
	local log = { on = false, widgets = {} }
	logger:Hide()
	-- (pcall: an event this client hasn't got would error.)
	local EVENTS = { "PLAYER_IS_GLIDING_CHANGED", "PLAYER_CAN_GLIDE_CHANGED", "UNIT_SPELLCAST_SUCCEEDED",
		"SPELL_UPDATE_CHARGES", "CVAR_UPDATE", "UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
		"ACTIONBAR_PAGE_CHANGED", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"ZONE_CHANGED_NEW_AREA", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE", "UPDATE_UI_WIDGET" }
	local lastCharges -- (SPELL_UPDATE_CHARGES comes often: logged only as the charges change)
	logger:SetScript("OnEvent", function(_, event, ...)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			local unit, _, spellID = ...
			if unit ~= "player" then return end
			local name = Plain(spellID) and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
			Log(("event cast %s %s | %s"):format(V(name), V(spellID), (Glide())))
		elseif event == "SPELL_UPDATE_CHARGES" then
			local charges = Bar(true)
			if charges ~= lastCharges then
				lastCharges = charges
				Log("event " .. charges)
			end
		elseif event == "UPDATE_UI_WIDGET" then
			local info = ...
			local id = type(info) == "table" and info.widgetID
			if id and not log.widgets[id] then
				log.widgets[id] = true -- (once each: they update every frame or so)
				Log(("event widget %s (type %s, set %s)"):format(V(id), V(info.widgetType), V(info.widgetSetID)))
			end
		else
			local a, b = ...
			Log(("event %s %s %s | %s, mouselook %s"):format(event, V(a), V(b), (Glide()),
				Call("IsMouselooking")))
		end
	end)
	ns.SetOnUpdate(logger, function(_, elapsed)
		local now = GetTime()
		if now - log.started >= LOG_FOR then
			log.on = false
			logger:Hide()
			logger:UnregisterAllEvents()
			Log("log over (time up)")
			ns.Print("skyride log over (5 minutes): /reload to save it")
			return
		end
		local text, gliding, can, speed = Glide()
		local changed = gliding ~= log.gliding or can ~= log.can
		log.gliding, log.can = gliding, can
		log.since = log.since + elapsed
		local flying = IsFlying and IsFlying()
		if not changed and (log.since < LOG_EVERY or not (gliding or flying)) then return end
		-- (Your height and pitch can't be read, and the unit speed is 0 while
		-- gliding: tested. The flat speed from your position against the
		-- glide's speed gives how steep you go, not which way; the glide speed
		-- falling says climbing, rising without a surge diving.)
		local y, x = Where()
		local shape = ""
		if Plain(y) and Plain(x) and log.y and log.since > 0 then
			local flat = math.sqrt((x - log.x) ^ 2 + (y - log.y) ^ 2) / log.since
			local steep = Plain(speed) and speed > 5 and math.deg(math.acos(math.min(1, flat / speed)))
			local trend = Plain(speed) and Plain(log.speed) and (speed - log.speed) / log.since
			shape = (" | flat %.1f, steep %s, speed %s/s"):format(flat, steep and ("%.0f deg"):format(steep) or "-",
				trend and ("%+.1f"):format(trend) or "-")
		end
		if Plain(y) and Plain(x) then log.y, log.x = y, x else log.y = nil end
		log.speed = Plain(speed) and speed or nil
		-- (Your facing, and how fast it turns: steering.)
		local facing = Facing()
		local turn = facing and log.facing and ((facing - log.facing + 540) % 360 - 180) / log.since
		log.facing = facing
		Log(("%s%s%s | %s | falling %s, mouselook %s, facing %s, turning %s/s | combat %s | zoom %s, fov %s | ours: sky %s"):format(
			changed and "CHANGED " or "", text, shape, Bar(true), Call("IsFalling"), Call("IsMouselooking"),
			V(facing, "%.0f"), V(turn, "%+.0f"), V(InCombatLockdown()), V(Zoom(), "%.1f"), tostring(GetCVar("cameraFov")),
			tostring(ns.SkyridingNow and ns.SkyridingNow())))
		-- (The bar in full as you take off: its spells by name.)
		if changed and gliding == true then Log(Bar()) end
		log.since = 0
	end)

	local function Snapshot()
		local build, _, _, toc = GetBuildInfo()
		ns.Print(("skyride: %s | flying %s, falling %s, mounted %s, taxi %s, skyriding zone %s, flyable %s, indoors %s, combat %s (%s, %s)"):format(
			(Glide()), Call("IsFlying"), Call("IsFalling"), Call("IsMounted"), Call("UnitOnTaxi", "player"),
			Call("IsAdvancedFlyableArea"), Call("IsFlyableArea"), Call("IsIndoors"), V(InCombatLockdown()),
			tostring(build), tostring(toc)))
		local _, speed, run, flight, swim = pcall(GetUnitSpeed, "player")
		local y, x, z, instance = Where()
		ns.Print(("  unit speed %s (run %s, flight %s, swim %s); position %s, %s, height %s (instance %s); facing %s"):format(
			V(speed, "%.1f"), V(run, "%.1f"), V(flight, "%.1f"), V(swim, "%.1f"), V(x, "%.1f"), V(y, "%.1f"),
			V(z, "%.1f"), V(instance), V(Facing(), "%.0f")))
		ns.Print("  " .. Bar())
		ns.Print("  " .. Ours())
	end

	local function ToggleLog()
		log.on = not log.on
		if log.on then
			log.started, log.since, log.gliding, log.can, log.y, log.speed, log.facing = GetTime(), 0, nil, nil, nil, nil, nil
			log.widgets, lastCharges = {}, nil
			for _, event in ipairs(EVENTS) do pcall(logger.RegisterEvent, logger, event) end
			Log("log started: " .. Ours())
			ns.Print("  logging while you're in the air (5 minutes, or /cine debug skyride again): /reload after to save it")
		else
			logger:UnregisterAllEvents()
			Log("log stopped")
			ns.Print("  log stopped: /reload to save it")
		end
		logger:SetShown(log.on)
	end

	-- The frames up now that look like skyriding's: by name (vigor, widgets,
	-- the bars it swaps in), with whether we could fade them (protected ones
	-- can't be touched in a fight).
	local FRAME_WORDS = { "vigor", "glid", "dragon", "skyrid", "powerbar", "uiwidget", "override", "bonusaction",
		"encounterbar", "vehicle", "mainactionbar", "mainmenubar" }
	local function IsFrame(value)
		local ok, isFrame = pcall(function() return value.IsObjectType and value:IsObjectType("Frame") end)
		return ok and isFrame == true
	end
	local function Frames()
		local found = {}
		for name, value in pairs(_G) do
			if type(name) == "string" and type(value) == "table" and not name:find("^Cinematic") then
				local lower = name:lower()
				for _, word in ipairs(FRAME_WORDS) do
					if lower:find(word, 1, true) then
						if IsFrame(value) then found[#found + 1] = name end
						break
					end
				end
			end
		end
		table.sort(found)
		local shown = 0
		for _, name in ipairs(found) do
			local frame = _G[name]
			local okShown, visible = pcall(frame.IsVisible, frame)
			if okShown and visible == true then
				shown = shown + 1
				local _, alpha = pcall(frame.GetEffectiveAlpha, frame)
				local _, protected = pcall(frame.IsProtected, frame)
				local _, forbidden = pcall(frame.IsForbidden, frame)
				local okParent, parent = pcall(frame.GetParent, frame)
				local parentName = okParent and parent and parent.GetName and parent:GetName()
				Log(("frame %s: visible, alpha %s, protected %s, forbidden %s, parent %s"):format(name,
					V(alpha, "%.2f"), V(protected), V(forbidden), V(parentName)))
			end
		end
		Log(("frames: %d named like skyriding's, %d visible | %s, combat %s"):format(#found, shown, (Glide()),
			V(InCombatLockdown())))
		ns.Print(("skyride frames: %d visible of %d named like skyriding's (in /cine log)"):format(shown, #found))
	end

	-- Probes: one of our camera moves or settings, tried now. Settings tried
	-- are put back after, and at the next login if you /reload meanwhile
	-- (db.skyrideProbeRestore).
	local function Hold(cvar, value)
		local db = ns.db
		db.skyrideProbeRestore = db.skyrideProbeRestore or {}
		if db.skyrideProbeRestore[cvar] == nil then db.skyrideProbeRestore[cvar] = GetCVar(cvar) end
		SetCVar(cvar, value)
	end
	local function Restore(cvar)
		local saved = ns.db.skyrideProbeRestore
		if saved and saved[cvar] ~= nil then
			SetCVar(cvar, saved[cvar])
			saved[cvar] = nil
			if not next(saved) then ns.db.skyrideProbeRestore = nil end
		end
	end
	local function State()
		local script = ns.PlayingCameraScript and ns.PlayingCameraScript()
		return ("%s, mouselook %s, facing %s, zoom %s, script %s"):format((Glide()), Call("IsMouselooking"),
			V(Facing(), "%.0f"), V(Zoom(), "%.1f"), tostring(script and script.name))
	end
	local function Move(name) if _G[name] then ns.CallCameraFunction(name, 1) end end
	local function Stop(name) if _G[name] then ns.CallCameraFunction(name) end end
	local PROBES = {
		-- Our zoom commands: does the game take them in the air?
		zoom = function()
			local z0 = Zoom()
			ns.CallCameraFunction("CameraZoomOut", 10)
			C_Timer.After(1.5, function()
				local z1 = Zoom()
				ns.CallCameraFunction("CameraZoomIn", 10)
				C_Timer.After(1.5, function()
					Log(("probe zoom: %s out 10 -> %s, in 10 -> %s | %s"):format(V(z0, "%.1f"), V(z1, "%.1f"),
						V(Zoom(), "%.1f"), State()))
				end)
			end)
		end,
		-- A turn of the view: does it turn the view, you (your facing), or neither?
		turn = function()
			local f0 = Facing()
			Move("MoveViewLeftStart")
			C_Timer.After(1, function()
				Stop("MoveViewLeftStop")
				local f1 = Facing()
				C_Timer.After(1, function()
					Log(("probe turn: facing %s, after 1 s turning the view %s, 1 s later %s | %s"):format(V(f0, "%.0f"),
						V(f1, "%.0f"), V(Facing(), "%.0f"), State()))
				end)
			end)
		end,
		-- A tilt of the view up (watch: does the view tilt, or your flight?).
		tilt = function()
			local before = State()
			Move("MoveViewUpStart")
			C_Timer.After(1, function()
				Stop("MoveViewUpStop")
				Log(("probe tilt: tilted the view up 1 s | before %s | after %s"):format(before, State()))
			end)
		end,
		-- The field of view, 20 narrower for 4 s: does it take, or does the game's own flight FOV win?
		fov = function()
			local f0 = tonumber(GetCVar("cameraFov"))
			if not f0 then
				Log("probe fov: no cameraFov here")
				return
			end
			local want = math.max(30, f0 - 20)
			Hold("cameraFov", want)
			local f1 = GetCVar("cameraFov")
			C_Timer.After(4, function()
				local f2 = GetCVar("cameraFov")
				Restore("cameraFov")
				Log(("probe fov: %s -> set %s, read %s, 4 s later %s, back to %s | %s"):format(tostring(f0), tostring(want),
					tostring(f1), tostring(f2), tostring(GetCVar("cameraFov")), State()))
			end)
		end,
		-- Camera follow off (cameraSmoothStyle 0) for 6 s: does the camera still swing behind you in the air?
		follow = function()
			local s0 = GetCVar("cameraSmoothStyle")
			Hold("cameraSmoothStyle", "0")
			C_Timer.After(6, function()
				local s1 = GetCVar("cameraSmoothStyle")
				Restore("cameraSmoothStyle")
				Log(("probe follow: cameraSmoothStyle %s -> 0 for 6 s (read %s at the end), back to %s | %s"):format(
					tostring(s0), tostring(s1), tostring(GetCVar("cameraSmoothStyle")), State()))
			end)
		end,
	}
	-- (A probe's setting left over from a /reload mid-probe: put back now.)
	local restorer = CreateFrame("Frame")
	restorer:RegisterEvent("PLAYER_LOGIN")
	restorer:SetScript("OnEvent", function()
		local saved = ns.db and ns.db.skyrideProbeRestore
		if type(saved) ~= "table" then return end
		for _, cvar in ipairs({ "cameraFov", "cameraSmoothStyle" }) do
			if saved[cvar] ~= nil then
				Log(("probe: %s put back to %s (left over)"):format(cvar, tostring(saved[cvar])))
				Restore(cvar)
			end
		end
	end)

	function ns.SkyrideDebug(arg)
		arg = arg or ""
		if arg == "frames" then
			Frames()
			return
		end
		local probe = arg:match("^probe%s+(%a+)")
		if probe or arg == "probe" then
			if not PROBES[probe or ""] then
				ns.Print("skyride probe: zoom, turn, tilt, fov or follow")
				return
			end
			Log(("probe %s starting | %s"):format(probe, State()))
			PROBES[probe]()
			ns.Print(("skyride probe %s: logged in a few seconds (/reload after to save it)"):format(probe))
			return
		end
		Snapshot()
		ToggleLog()
	end
end
