-- Camera simulator's world (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
-- the addon's real camera code loaded on a stand-in for the game, with a
-- made-up player, camera and clock that scenarios drive (sim.lua).
--
--   local W = dofile("Tools/camera-sim/world.lua")("forever")
--
-- W.Tick() runs one frame: timers, every camera file's OnUpdate, then the
-- stand-in camera moves by the commands it was sent. What our cameras did is
-- kept in W.cam (sends, by whom, while you held the camera...), W.log (the
-- addon's own log lines) and W.errors.
-- luacheck: ignore 111 112 113 121 122 (it stands in for the game's functions on purpose)
return function(client, opts)
	opts = opts or {}
	package.path = "Tools/offline/?.lua;" .. package.path
	local wow = dofile("Tools/offline/wow.lua")
	wow.Install(client)
	-- (A stub's parent is nothing: walking up a stub's parents never ended.)
	rawset(wow.Stub, "GetParent", function() return nil end)
	rawset(wow.Stub, "GetNumPoints", function() return 0 end)

	local W = { client = client, now = 1000, TICK = opts.tick or 0.02, frame = 0, log = {}, errors = {}, errorCount = 0 }
	local me = { moving = false, combat = false, taxi = false, afk = false, dead = false, ghost = false,
		mouselook = false, left = false, right = false, indoors = false, mounted = false, flying = false,
		swimming = false, facing = 0, x = 0, y = 0, cast = nil, sitting = false, padOn = false, pad = {},
		gliding = false, speed = 0, target = nil }
	W.me = me
	local YOURS = { cameraYawMoveSpeed = "180", cameraPitchMoveSpeed = "90", cameraZoomSpeed = "20",
		cameraSmoothStyle = "0", cameraDistanceMaxZoomFactor = "2.6", GamePadEnable = "0",
		GamePadTurnWithCamera = "0", cameraSmoothTrackingStyle = "0" }
	W.YOURS = YOURS
	local cvars = {}
	for k, v in pairs(YOURS) do cvars[k] = v end
	W.cvars = cvars

	GetTime = function() return W.now end
	local timers = {}
	local function NewTimer(secs, fn, times)
		local t = { at = W.now + secs, fn = fn, every = times and secs or nil, left = times }
		function t.Cancel(self) (self or t).cancelled = true end
		function t.IsCancelled(self) return (self or t).cancelled == true end
		timers[#timers + 1] = t
		return t
	end
	C_Timer.After = function(secs, fn) NewTimer(secs, fn) end
	C_Timer.NewTimer = function(secs, fn) return NewTimer(secs, fn) end
	C_Timer.NewTicker = function(secs, fn, times) return NewTimer(secs, fn, times or math.huge) end
	GetCVar = function(name) return cvars[name] or "0" end
	GetCVarBool = function(name) local v = cvars[name] return v ~= nil and v ~= "0" end
	GetCVarDefault = function(name) return YOURS[name] or "0" end
	W.cvarWrites = {}
	SetCVar = function(name, value)
		cvars[name] = tostring(value)
		W.cvarWrites[name] = (W.cvarWrites[name] or 0) + 1
	end
	C_CVar = { GetCVar = GetCVar, SetCVar = SetCVar, GetCVarBool = GetCVarBool, GetCVarDefault = GetCVarDefault }
	InCombatLockdown = function() return me.combat end
	UnitAffectingCombat = function(unit) return unit == "player" and me.combat end
	UnitOnTaxi = function() return me.taxi end
	UnitIsAFK = function() return me.afk end
	UnitIsDeadOrGhost = function() return me.dead or me.ghost end
	UnitIsDead = function() return me.dead end
	UnitIsGhost = function() return me.ghost end
	UnitHealth = function() return (me.dead or me.ghost) and 0 or 100 end
	UnitHealthMax = function() return 100 end
	UnitPower = function() return 100 end
	UnitPowerMax = function() return 100 end
	UnitExists = function(unit) return unit == "player" or (unit == "target" and me.target ~= nil) or (unit == "npc" and me.npc == true) end
	UnitIsPlayer = function(unit) return unit == "player" end
	UnitGUID = function(unit) if unit == "npc" and me.npc then return "Creature-0-1-2-3-4-5" end return nil end
	UnitName = function(unit) if unit == "target" then return me.target end return "Player", nil end
	IsMouselooking = function() return me.mouselook end
	IsMouseButtonDown = function(button)
		if button == "LeftButton" then return me.left end
		if button == "RightButton" then return me.right end
		return me.left or me.right
	end
	IsIndoors = function() return me.indoors end
	IsOutdoors = function() return not me.indoors end
	IsMounted = function() return me.mounted end
	IsFlying = function() return me.flying end
	IsSwimming = function() return me.swimming end
	IsSubmerged = function() return false end
	IsFalling = function() return false end
	IsStealthed = function() return false end
	IsResting = function() return false end
	IsInInstance = function() return false, "none" end
	GetUnitSpeed = function() return me.moving and (me.walkMode and 2.5 or 7) or 0 end
	UnitPosition = function() return me.y, me.x, 0, 0 end
	GetPlayerFacing = function() return math.rad(me.facing % 360) end
	UnitCastingInfo = function() if me.cast and not me.cast.channel then return me.cast.name, nil, nil, me.cast.startMs, me.cast.endMs, nil, nil, nil, me.cast.id end end
	UnitChannelInfo = function() if me.cast and me.cast.channel then return me.cast.name, nil, nil, me.cast.startMs, me.cast.endMs, nil, nil, me.cast.id end end
	GetSpellInfo = function(id) return "Spell " .. tostring(id) end
	C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. tostring(id), spellID = id } end,
		GetSpellName = function(id) return "Spell " .. tostring(id) end }
	C_PlayerInfo = { GetGlidingInfo = function() return me.gliding, true, me.speed end }
	GetNumGroupMembers = function() return 0 end
	C_Minimap = {}
	IsEncounterInProgress = function() return false end
	C_DeathInfo = { GetSelfResurrectOptions = function() return {} end }
	HasSoulstone = function() return nil end
	UnitBuff = function() return nil end
	UnitDebuff = function() return nil end
	UnitAura = function() return nil end
	C_UnitAuras = { GetAuraDataByIndex = function() return nil end, GetBuffDataByIndex = function() return nil end,
		GetDebuffDataByIndex = function() return nil end, GetPlayerAuraBySpellID = function() return nil end,
		GetAuraDataBySpellName = function() return nil end }
	AuraUtil = { FindAuraByName = function() return nil end, ForEachAura = function() end }
	GetScreenWidth = function() return 1920 end
	GetScreenHeight = function() return 1080 end
	GetCursorPosition = function() return 960, 540 end
	GetFramerate = function() return 1 / W.TICK end
	debugstack = function() return "" end
	debugprofilestop = function() return W.now * 1000 end
	-- Gamepad (C_GamePad): buttons by index, their binding names.
	local PAD_NAMES = { "PAD1", "PAD2", "PAD3", "PAD4", "PADRSTICKUP", "PADRSTICKDOWN", "PADRSTICKLEFT",
		"PADRSTICKRIGHT", "PADLSTICKUP", "PADLSTICKDOWN", "PADLSTICKLEFT", "PADLSTICKRIGHT", "PADLSTICK", "PADRSTICK" }
	W.PAD_NAMES = PAD_NAMES
	C_GamePad = {
		GetActiveDeviceID = function() return me.padOn and 1 or nil end,
		GetDeviceMappedState = function()
			if not me.padOn then return nil end
			local buttons = {}
			for i, name in ipairs(PAD_NAMES) do buttons[i] = me.pad[name] == true end
			return { buttons = buttons, axes = {}, sticks = {} }
		end,
		ButtonIndexToBinding = function(i) return PAD_NAMES[i] end,
		IsEnabled = function() return me.padOn end,
	}

	-- CAMERA: moved only by the commands sent (as Tools/skyride-sim's), and by
	-- you: W.Drag turns it at a rate while a mouse button's down.
	local cam = { yaw = 0, pitch = 0, zoom = 15, goal = 15, yawRate = 0, pitchRate = 0, sends = 0, stops = 0,
		startedAt = {}, byWho = {}, whileYours = 0, whileYoursList = {}, lastStartAt = -math.huge,
		yourYawRate = 0, yourPitchRate = 0, starts = {} }
	W.cam = cam
	W.sender = nil -- who's sending (set by the ns.CameraCall wrap below), nil = not through the lock
	W.playerCalling = false
	local function Axis(axis, sign, start, name)
		local other = axis == "yaw" and "pitch" or "yaw"
		return function(share)
			if W.playerCalling then return end -- (your own key: the hooks see it, the camera's turned by W.Drag)
			cam.sends = cam.sends + 1
			local who = W.sender or "direct"
			cam.byWho[who] = (cam.byWho[who] or 0) + 1
			if start then
				cam[axis .. "Rate"] = sign * (type(share) == "number" and share or 1)
				cam.startedAt[axis] = W.frame
				if cam.startedAt[other] ~= W.frame then cam[other .. "Rate"] = 0 end
				cam.lastStartAt = W.now
				cam.starts[#cam.starts + 1] = { t = W.now, who = who, name = name }
				if W.Holding() then
					cam.whileYours = cam.whileYours + 1
					if #cam.whileYoursList < 20 then
						cam.whileYoursList[#cam.whileYoursList + 1] = ("%.2f %s %s"):format(W.now - 1000, who, name)
					end
				end
			else
				cam[axis .. "Rate"] = 0
				cam.stops = cam.stops + 1
			end
		end
	end
	MoveViewLeftStart, MoveViewLeftStop = Axis("yaw", 1, true, "MoveViewLeftStart"), Axis("yaw", 1, false)
	MoveViewRightStart, MoveViewRightStop = Axis("yaw", -1, true, "MoveViewRightStart"), Axis("yaw", -1, false)
	MoveViewDownStart, MoveViewDownStop = Axis("pitch", 1, true, "MoveViewDownStart"), Axis("pitch", 1, false)
	MoveViewUpStart, MoveViewUpStop = Axis("pitch", -1, true, "MoveViewUpStart"), Axis("pitch", -1, false)
	cam.zoomSends, cam.zoomWhileYours = 0, 0
	local function ZoomBy(sign, name)
		return function(yards)
			yards = type(yards) == "number" and yards or 1
			if not W.playerCalling then
				cam.zoomSends = cam.zoomSends + 1
				local who = W.sender or "direct"
				cam.byWho[who] = (cam.byWho[who] or 0) + 1
				cam.starts[#cam.starts + 1] = { t = W.now, who = who, name = name, zoom = true }
				if W.Holding() then cam.zoomWhileYours = cam.zoomWhileYours + 1 end
			end
			cam.goal = cam.goal + sign * yards
		end
	end
	CameraZoomIn, CameraZoomOut = ZoomBy(-1, "CameraZoomIn"), ZoomBy(1, "CameraZoomOut")
	GetCameraZoom = function() return cam.zoom end
	SetView = function() end
	ResetView = function() end
	SaveView = function() end
	local MAXZOOM = 39
	function W.MoveCamera(dt)
		cam.yaw = cam.yaw + cam.yawRate * (tonumber(cvars.cameraYawMoveSpeed) or 0) * dt + cam.yourYawRate * dt
		cam.pitch = cam.pitch + cam.pitchRate * (tonumber(cvars.cameraPitchMoveSpeed) or 0) * dt + cam.yourPitchRate * dt
		cam.pitch = math.max(-88, math.min(88, cam.pitch))
		cam.goal = math.max(1, math.min(MAXZOOM, cam.goal))
		local step = (tonumber(cvars.cameraZoomSpeed) or 0) * dt
		local d = cam.goal - cam.zoom
		cam.zoom = math.abs(d) <= step and cam.goal or cam.zoom + (d > 0 and step or -step)
	end
	-- You have the camera: a mouse button down on the world, or the right stick pushed.
	function W.Holding()
		return me.left or me.right or me.pad.PADRSTICKLEFT or me.pad.PADRSTICKRIGHT or me.pad.PADRSTICKUP
			or me.pad.PADRSTICKDOWN or false
	end

	-- hooksecurefunc as the game's: the function runs, then the hook.
	hooksecurefunc = function(a, b, c)
		local tbl, name, fn = _G, a, b
		if type(a) == "table" then tbl, name, fn = a, b, c end
		local orig = rawget(tbl, name)
		if type(orig) ~= "function" then return end
		tbl[name] = function(...)
			local results = { orig(...) }
			local ok, err = pcall(fn, ...)
			if not ok then W.Error("hook " .. tostring(name), err) end
			return unpack(results, 1, table.maxn(results))
		end
	end
	-- The functions your keys and mouse call (bindings).
	for _, name in ipairs({ "CameraOrSelectOrMoveStart", "CameraOrSelectOrMoveStop", "TurnOrActionStart",
		"TurnOrActionStop", "TurnLeftStart", "TurnLeftStop", "TurnRightStart", "TurnRightStop", "MoveForwardStart",
		"MoveForwardStop", "MoveBackwardStart", "MoveBackwardStop", "StrafeLeftStart", "StrafeLeftStop",
		"StrafeRightStart", "StrafeRightStop", "ToggleAutoRun", "StartAutoRun", "StopAutoRun", "JumpOrAscendStart",
		"AscendStop", "SitStandOrDescendStart", "DescendStop", "ToggleRun", "ToggleSheath", "PitchUpStart",
		"PitchUpStop", "PitchDownStart", "PitchDownStop", "MouselookStart", "MouselookStop", "DoEmote",
		"MoveAndSteerStart", "MoveAndSteerStop", "AcceptQuest", "CompleteQuest", "GetQuestReward", "SelectAvailableQuest",
		"SelectActiveQuest", "CloseQuest", "DeclineQuest" }) do
		_G[name] = function() end
	end

	function W.Error(where, err)
		W.errorCount = W.errorCount + 1
		local key = where .. ": " .. tostring(err):match("^[^\n]*")
		if not W.errors[key] then
			W.errors[key] = { n = 0, first = W.now - 1000 }
			W.errors[#W.errors + 1] = key
		end
		W.errors[key].n = W.errors[key].n + 1
	end

	-- Only the camera files' frames update (the rest of the addon idles).
	local FILES = { "Camera", "Core", "Director", "QuestCam", "ChatCam", "CustomTriggers", "Triggers",
		"Campfire", "MouseTurn", "ZoomGuard", "SkyrideCam", "ShowMe", "Shots", "CameraTests", "Shoulder", "Diagnostics",
		"LowHealth", "Focus" }
	local mine = {}
	W.mine = mine
	local realCreate = CreateFrame
	CreateFrame = function(...)
		local f = realCreate(...)
		local src, level, info
		level = 2
		repeat
			info = debug.getinfo(level, "S")
			src = info and info.source or ""
			level = level + 1
		until not info or not src:find("camera%-sim")
		for _, name in ipairs(FILES) do
			if src:find("[/\\@]" .. name .. "[%w]*%.lua") then
				mine[#mine + 1] = f
				f._src = src
				break
			end
		end
		return f
	end
	if opts.saved then rawset(_G, "CinematicDB", opts.saved) end
	local toc = opts.toc or "CinematicDev.toc"
	local addon = toc:match("([^/]+)%.toc$")
	local ns = {}
	W.ns = ns
	for line in io.lines(toc) do
		line = line:gsub(string.char(13), "")
		if line ~= "" and not line:find("^#") then
			local chunk, err = loadfile((line:gsub("\\", "/")))
			if chunk then
				local ok, runErr = pcall(chunk, addon, ns)
				if not ok then W.Error("load " .. line, runErr) end
			elseif err and not err:find("cannot open") then
				W.Error("load " .. line, err)
			end
		end
	end
	function W.Fire(event, ...)
		for _, frame in ipairs(wow.frames) do
			local handler = frame._events[event] and frame._scripts.OnEvent
			if handler then
				local ok, err = pcall(handler, frame, event, ...)
				if not ok and frame._src then W.Error(event, err) end
			end
		end
	end
	W.Fire("ADDON_LOADED", addon)
	W.Fire("PLAYER_LOGIN")
	W.Fire("PLAYER_ENTERING_WORLD", true, false)
	W.Fire("LOADING_SCREEN_DISABLED")

	-- Who sends each camera command (the lock's name for it).
	local call = ns.CameraCall
	ns.CameraCall = function(who, name, ...)
		local before = W.sender
		W.sender = who
		local a, b, c = call(who, name, ...)
		W.sender = before
		return a, b, c
	end
	-- The addon's own log lines.
	local realLog = ns.Log
	ns.Log = function(kind, text, ...)
		W.log[#W.log + 1] = { t = W.now - 1000, kind = kind, text = tostring(text) }
		if realLog then return realLog(kind, text, ...) end
	end
	local realPrint = ns.Print
	ns.Print = function(text, ...)
		W.log[#W.log + 1] = { t = W.now - 1000, kind = "print", text = tostring(text) }
		if realPrint then return pcall(realPrint, text, ...) end
	end

	function W.Tick()
		W.now = W.now + W.TICK
		W.frame = W.frame + 1
		for i = #timers, 1, -1 do
			local timer = timers[i]
			if timer.cancelled then
				table.remove(timers, i)
			elseif timer.at <= W.now then
				if timer.every and (timer.left or 0) > 1 then
					timer.left = timer.left - 1
					timer.at = W.now + timer.every
				else
					table.remove(timers, i)
				end
				local ok, err = pcall(timer.fn, timer)
				if not ok then W.Error("timer", err) end
			end
		end
		for _, f in ipairs(mine) do
			local fn = f._scripts.OnUpdate
			if fn and f._shown then
				local ok, err = pcall(fn, f, W.TICK)
				if not ok then W.Error("OnUpdate " .. tostring(f._src), err) end
			end
		end
		if me.moving then -- (you walk on: the quest camera goes by how far you've gone)
			local step = (me.walkMode and 2.5 or 7) * W.TICK
			me.x, me.y = me.x + step * math.sin(math.rad(me.facing)), me.y + step * math.cos(math.rad(me.facing))
		end
		W.MoveCamera(W.TICK)
		if W.AfterTick then W.AfterTick() end
	end
	function W.Run(secs)
		for _ = 1, math.floor(secs / W.TICK + 0.5) do W.Tick() end
	end

	-- What you do. (Your keys call the binding functions the addon hooks.)
	local function Key(name, ...)
		W.playerCalling = true
		_G[name](...)
		W.playerCalling = false
	end
	W.Key = Key
	function W.Move(on) -- walking by hand
		if on == me.moving then return end
		me.moving = on
		Key(on and "MoveForwardStart" or "MoveForwardStop")
		W.Fire(on and "PLAYER_STARTED_MOVING" or "PLAYER_STOPPED_MOVING")
	end
	function W.AutoRun(on)
		Key("ToggleAutoRun")
		if on ~= me.moving then
			me.moving = on
			W.Fire(on and "PLAYER_STARTED_MOVING" or "PLAYER_STOPPED_MOVING")
		end
	end
	-- A mouse button down on the world: "left" turns the camera only, "right" mouselooks.
	function W.Press(button, rate)
		if button == "left" then
			me.left = true
			Key("CameraOrSelectOrMoveStart")
		else
			me.right, me.mouselook = true, true
			Key("TurnOrActionStart")
		end
		cam.yourYawRate = rate or 0
	end
	-- lost: the game never calls the Stop (alt-tab, a loading screen).
	function W.Let(button, lost)
		if button == "left" then
			me.left = false
			if not lost then Key("CameraOrSelectOrMoveStop") end
		else
			me.right, me.mouselook = false, false
			if not lost then Key("TurnOrActionStop") end
		end
		cam.yourYawRate = 0
	end
	function W.Scroll(yards) -- your wheel: the binding calls the zoom
		Key(yards < 0 and "CameraZoomIn" or "CameraZoomOut", math.abs(yards))
	end
	function W.Stick(dir, on) -- the gamepad's right stick ("LEFT"...)
		me.pad["PADRSTICK" .. dir] = on or nil
		cam.yourYawRate = on and (dir == "LEFT" and 60 or dir == "RIGHT" and -60 or 0) or 0
	end
	function W.Pad(on) -- a gamepad in use
		me.padOn = on
		cvars.GamePadEnable = on and "1" or "0"
	end
	-- A cast: its events as the game sends them. channel: a channel's.
	function W.Cast(id, secs, channel)
		me.cast = { id = id, name = "Spell " .. id, startMs = W.now * 1000, endMs = (W.now + secs) * 1000, channel = channel }
		W.Fire(channel and "UNIT_SPELLCAST_CHANNEL_START" or "UNIT_SPELLCAST_START", "player", "cast-" .. id, id)
		-- (ConsolePort: GamePadTurnWithCamera 2 on every cast start: the game reports mouselook for the cast.)
		if me.padOn and opts.consolePort then
			cvars.GamePadTurnWithCamera = "2"
			me.mouselook = true
		end
	end
	function W.CastEnd(how) -- "done", "stop" (moved, Escape)
		local c = me.cast
		if not c then return end
		me.cast = nil
		if me.padOn and opts.consolePort then me.mouselook = me.right end
		if how == "done" then
			W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-" .. c.id, c.id)
		else
			W.Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-" .. c.id, c.id)
		end
		W.Fire(c.channel and "UNIT_SPELLCAST_CHANNEL_STOP" or "UNIT_SPELLCAST_STOP", "player", "cast-" .. c.id, c.id)
	end
	function W.Fight(on)
		me.combat = on
		W.Fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
	end
	function W.AFK(on)
		me.afk = on
		W.Fire("PLAYER_FLAGS_CHANGED", "player")
	end
	function W.Taxi(on)
		me.taxi = on
		W.Fire(on and "PLAYER_CONTROL_LOST" or "PLAYER_CONTROL_GAINED")
	end
	function W.Loading() -- a loading screen
		W.Fire("LOADING_SCREEN_ENABLED")
		W.Fire("PLAYER_LEAVING_WORLD")
		W.Fire("PLAYER_ENTERING_WORLD", false, false)
		W.Fire("LOADING_SCREEN_DISABLED")
	end
	-- A quest giver's window: opens (event: QUEST_DETAIL...), or closes ("accept": you took the
	-- quest, the next window may follow; "leave": Escape or Goodbye).
	function W.Quest(what)
		if what == "accept" or what == "leave" then
			if what == "accept" then Key("AcceptQuest") end
			me.npc = false
			W.Fire("QUEST_FINISHED")
		else
			me.npc = true
			W.Fire(what or "QUEST_DETAIL")
		end
	end
	function W.Emote(token) -- /sit, /dance...: the game's DoEmote
		Key("DoEmote", token)
	end
	return W
end
