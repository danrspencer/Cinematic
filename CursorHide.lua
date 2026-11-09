-- Cursor Hide (UI Visibility hub, CineMode Autohide; on Forever a tab after Gamepad): in CineMode, the cursor gets out of
-- the way, where its Show in row says. Three ways:
--   tiny: the game's tiniest cursor all the time (SetCursor; just a corner).
--     SetCursor's hardware cursor takes only the game's own Interface\Cursor
--     files (tested: our files, other textures and missing files all draw a
--     black square; none of its 389 cursors is blank).
--   steer ("Hide completely"): gone once the mouse has been still a while.
--     With the game's hardware cursor off (HardwareCursor 0, "draws a
--     software cursor"), a picture it can't use as a cursor draws nothing at
--     all (tested: our red test picture showed nothing in the world; it
--     switches without a /reload). So while it's gone that's held off, and
--     put back as it comes back. The camera's left alone. (Mouse steering
--     did this before: it turned you as a camera circled, tested.) Over a
--     unit frame the game puts its own cursor back; with the game's window
--     in the background, Windows draws a black square over it.
--   both (Tiny, then gone): tiny all the time, and gone once the mouse has
--     been still for the delay; moving brings back the tiny one.
-- The game puts its own world cursor back nearly every frame, but not over a
-- frame: a screen-wide one that takes mouse movement only (clicks go
-- through) is up while ours is set, and ours is set again each frame.
-- Back from gone as the mouse moves, a button's pressed, you type or steer;
-- yours back as the cursor picks something up or the row stops showing.
-- The Hide Cursor till moves keybind: gone now, anywhere (CineMode or not, the page
-- on or not), till the mouse moves, a button's pressed, you type or the key's
-- pressed again. (The same software-cursor trick as above; only once the
-- page's warning has been accepted.)
-- /cine debug cursor: its state. The Cinema profile has it on in cameras
-- (ProfileModules.lua's cursor-hide).
local ADDON_NAME, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.cursorHide = false        -- at all (its page's switch)
DEFAULTS.cursorHideAlways = false  -- ...all through CineMode: its Show in row's Always (the rest: ROW_KEY's)
DEFAULTS.cursorHideMethod = "steer" -- "steer": gone once still (Hide completely); "tiny": the tiniest cursor; "both": tiny, then gone
DEFAULTS.cursorHideDelay = 3       -- seconds the mouse is still before it goes (3 at least: DELAY_MIN)

local ROW_KEY = "cursor:hide"
-- Its Show in row's rule to start with, in every profile, and after any reset.
ns.RULE_DEFAULTS[ROW_KEY] = "cam_flight or cam_vista or cam_idle"
local TINY = "Interface\\Cursor\\UnableItem"
local BLANK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\CursorBlank" -- (not a cursor: draws nothing)
local LAND = 0.3 -- seconds after it comes back that the cursor landing a pixel off isn't a move
local ROW_EVERY = 0.25 -- seconds between reads of the Show in row (rules aren't cheap)
local DELAY_MIN, DELAY_MAX = 3, 10 -- (the slider; a saved one under 3, from before, counts as 3)

-- The game's hardware cursor off while it's gone (yours back after, as the
-- addon's other held settings: ns.ApplyCVarSet).
local SOFTWARE = ns.CVarSet("Cursor Hide: software cursor", "the cursor gone: a software cursor draws " ..
	"Cursor Hide's blank picture as nothing", { values = { HardwareCursor = "0" } })

-- The tiny cursor all the time, as you move and click too (only something on
-- the cursor or the row turning off brings yours): Tiny, and Tiny, then gone.
local function TinyAlways()
	return ns.db.cursorHideMethod ~= "steer"
end
local function Delay()
	return math.max(DELAY_MIN, tonumber(ns.db.cursorHideDelay) or DELAY_MIN)
end

ns.cursorHidden = false -- (tiny or gone)
local gone = false
local cursorX, cursorY, stillSince = nil, nil, 0
local shownAt
local needMove -- (after it came back for something else: not gone again till the mouse has moved)
local lastBlock, lastShowWhy
local rowShows, rowReadAt = false, -1
local manualAt -- (the keybind hid it: when)

local cover
local function Cover()
	if cover then return cover end
	cover = CreateFrame("Frame", nil, WorldFrame)
	cover:SetAllPoints(WorldFrame)
	cover:SetFrameStrata("FULLSCREEN_DIALOG")
	if cover.EnableMouseMotion then
		cover:EnableMouseMotion(true)
		if cover.EnableMouseClicks then cover:EnableMouseClicks(false) end
		if cover.SetPropagateMouseClicks then cover:SetPropagateMouseClicks(true) end
		cover.motionOnly = true
	end
	cover:Hide()
	return cover
end

-- Whether its Show in row has it on here and now: Always, else its rule or
-- its ticks (as Vitals Vision's row reads). (Rule first, tested: a row the
-- rule editor had been through keeps a blank rule, "never", and Always then
-- did nothing.)
local function RowShows(now)
	if ns.db.cursorHideAlways then return true end
	if now - rowReadAt >= ROW_EVERY then
		rowReadAt = now
		local ok, shows = pcall(ns.RowOnNow, ROW_KEY, false, true)
		rowShows = ok and shows and true or false
	end
	return rowShows
end

-- Why it can't hide at all now (or nil): yours is wanted.
local function Blocked(now)
	if not ns.db.cursorHide then return "off" end
	if not ns.lastCinematic then return "CineMode off" end
	if not RowShows(now) then return "its Show in row is off here" end
	if GetCursorInfo() ~= nil then return "cursor holding something" end
end
-- Why the cursor's wanted for a moment (or nil): typing, a click, steering.
-- Not for the tiny cursor all the time (it clicks fine).
local function Busy()
	if ns.IsChatActive and ns.IsChatActive() then return "typing in chat" end
	if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then return "mouse button down" end
	if IsMouselooking() then return "you're steering" end
end

local function Show(why)
	if not ns.cursorHidden then return end
	-- (Not gone again till the mouse moves: only when something else brought
	-- it back. Back for the mouse moving, it has: a move inside LAND didn't
	-- count, and it then waited on, still, tested.)
	ns.cursorHidden, needMove, shownAt, lastShowWhy = false, why ~= "mouse moved", GetTime(), why
	if gone then
		gone = false
		ns.ApplyCVarSet(SOFTWARE, false)
	end
	if cover then cover:Hide() end
	pcall(ResetCursor)
	ns.LogDetail("cursor", "back: " .. why)
end

local function Set(picture, now, isGone)
	if Cover().motionOnly then cover:Show() end
	if isGone then ns.ApplyCVarSet(SOFTWARE, true) end
	if pcall(SetCursor, picture) then
		ns.cursorHidden, gone = true, isGone
		ns.LogDetail("cursor", isGone and "gone" or "tiny")
	else
		if isGone then ns.ApplyCVarSet(SOFTWARE, false) end
		cover:Hide()
		lastBlock, stillSince = "SetCursor failed", now
	end
end

-- Whether the mouse has been still long enough to go (sets lastBlock when
-- it's waiting for a move first).
local function GoneDue(now)
	if needMove then
		lastBlock = "waiting for the mouse to move first"
		return false
	end
	return now - stillSince >= Delay()
end

local driver = CreateFrame("Frame")
local function Update()
	local now = GetTime()
	local x, y = GetCursorPosition()
	local moved = x ~= cursorX or y ~= cursorY
	if moved then
		cursorX, cursorY, stillSince = x, y, now
		if now - (shownAt or 0) > LAND then needMove = nil end
	end
	if manualAt then
		-- (the keybind's: only a move, a button, typing or something picked up
		-- brings it back; a move inside LAND is the cursor landing)
		local back = (moved and now - manualAt > LAND and "mouse moved") or Busy()
			or (GetCursorInfo() ~= nil and "cursor holding something") or (not gone and "not gone")
		if back then
			manualAt = nil
			Show(back)
			ns.ApplyCursorHide()
		else
			pcall(SetCursor, BLANK)
		end
		return
	end
	local method, always = ns.db.cursorHideMethod, TinyAlways()
	local blocked = Blocked(now)
	local busy = blocked or Busy()
	lastBlock = always and blocked or busy
	if ns.cursorHidden then
		if blocked then
			Show(blocked)
		elseif gone then
			if moved or busy then
				Show(moved and "mouse moved" or busy) -- (Tiny, then gone: the tiny one's back next frame)
			else
				pcall(SetCursor, BLANK) -- (each frame: the game sets its own when something comes under it)
			end
		elseif not always then
			-- (Tiny, but the method's now Hide completely: yours back. Left,
			-- it stayed tiny, tested.)
			Show("method changed")
		elseif method == "both" and not busy and GoneDue(now) then
			Set(BLANK, now, true) -- (still long enough: from tiny to gone)
		else
			pcall(SetCursor, TINY)
		end
		return
	end
	if blocked then return end
	if always then
		Set(TINY, now, false)
	elseif not busy and GoneDue(now) then
		Set(BLANK, now, true) -- (Hide completely)
	end
end

-- Runs while it's on (its page's switch), stops when off.
-- It's experimental: nothing runs till its page's warning's been accepted
-- (the account's: CinematicDB.cursorHideAccepted), whatever a profile says.
function ns.CursorHideAccepted()
	return CinematicDB ~= nil and CinematicDB.cursorHideAccepted == true
end

local function Apply()
	if manualAt then
		ns.SetOnUpdate(driver, Update) -- (the keybind's till it's back)
	elseif ns.db and ns.db.cursorHide and ns.CursorHideAccepted() then
		ns.SetOnUpdate(driver, Update)
	else
		Show("turned off")
		ns.SetOnUpdate(driver, nil)
	end
end
ns.ApplyCursorHide = Apply

-- The Hide Cursor till moves keybind (Bindings.xml): gone now; pressed again, back.
function Cinematic_HideCursor()
	if not ns.db then return end
	if manualAt then
		manualAt = nil
		Show("key pressed again")
		Apply()
		return
	end
	-- (Experimental, as the page: nothing till its warning's been accepted.)
	if not ns.CursorHideAccepted() then
		ns.Print(L["Hide Cursor till moves: accept the warning on the Cursor Hide page first."])
		-- (its page, out of fights; in one, just the line)
		if not InCombatLockdown() and ns.OpenOptions then ns.OpenOptions("Cursor Hide") end
		return
	end
	if GetCursorInfo() ~= nil then return end -- (holding something: yours stays)
	local now = GetTime()
	Show("key") -- (from tiny, say)
	cursorX, cursorY = GetCursorPosition()
	Set(BLANK, now, true)
	if not gone then return end -- (SetCursor failed)
	manualAt = now
	ns.SetOnUpdate(driver, Update)
end

-- Everything the cursor features change, put back (/cine reset; for anyone
-- stuck with a hidden or odd cursor): Cursor Hide stopped and its warning
-- to accept again, the hardware cursor back on, the test commands' Cursor
-- Size and pictures undone, the game's own cursor back.
local picTester
function ns.CursorHideReset()
	if CinematicDB then CinematicDB.cursorHideAccepted = nil end
	manualAt = nil
	Show("reset")
	if driver then ns.SetOnUpdate(driver, nil) end
	if picTester then ns.SetOnUpdate(picTester, nil) end
	ns.ApplyCVarSet(SOFTWARE, false)
	local db = CinematicDB or {}
	if db.debugHardwareCursorWas ~= nil then
		pcall(SetCVar, "HardwareCursor", tostring(db.debugHardwareCursorWas or "1"))
		db.debugHardwareCursorWas = nil
	elseif GetCVar("HardwareCursor") == "0" then
		pcall(SetCVar, "HardwareCursor", "1") -- (still off with nothing of ours holding it: on, the game's default)
	end
	if db.debugCursorSizeWas ~= nil then
		pcall(SetCVar, "cursorSizePreferred", tostring(db.debugCursorSizeWas or "-1"))
		db.debugCursorSizeWas = nil
	end
	if cover then cover:Hide() end
	if IsMouselooking() then pcall(MouselookStop) end
	pcall(ResetCursor)
end

-- (a profile loaded or a page reset: Options' Refresh calls each page's apply)
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_LOGOUT")
loader:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		-- (the test page's old settings, before it had its own)
		if CinematicDB then CinematicDB.debugCursorHide = nil end
		if ns.db then ns.db.debugCursorHideOn = nil end
		Apply()
	else
		Show("logout")
	end
end)

-- /cine debug cursor: what it's doing and why, with what's around it.
function ns.CursorHideDebug()
	local db, now = ns.db, GetTime()
	local p = ns.Print
	p(("Cursor Hide: %s, method %s, delay %.1f s, Always %s, row on here %s"):format(
		db.cursorHide and "on" or "off", tostring(db.cursorHideMethod), Delay(),
		tostring(db.cursorHideAlways), tostring(RowShows(now))))
	p(("  now: %s; held back by: %s; still %.1f s; last back: %s"):format(
		gone and "gone" or ns.cursorHidden and "tiny" or "shown",
		needMove and "waiting for the mouse to move" or lastBlock or "nothing", now - stillSince,
		tostring(lastShowWhy)))
	p(("  CineMode %s, fight %s, steering %s; HardwareCursor %s (held off by us %s); cover %s; client %s"):format(
		ns.lastCinematic and "on" or "off", InCombatLockdown() and "yes" or "no",
		IsMouselooking() and "yes" or "no", tostring(GetCVar("HardwareCursor")), tostring(SOFTWARE.active or false),
		Cover().motionOnly and (cover:IsShown() and "up" or "down") or "not on this client",
		ns.isRetail and "retail" or "classic"))
	-- (The row's rule and the camera facts it reads.)
	local rules = db.frameRules
	local rule = type(rules) == "table" and rules[ROW_KEY]
	local facts = ns.RuleFactsNow and ns.RuleFactsNow() or {}
	local script = ns.PlayingCameraScript and ns.PlayingCameraScript()
	p(("  rule %s -> %s; camera running %s (as a script: %s), script %s; on a flight %s; facts camera %s cam_flight %s cam_script %s"):format(
		type(rule) == "string" and ('"' .. rule .. '"') or "none", tostring((ns.RuleShows(ROW_KEY, facts))),
		tostring(ns.activeCam), tostring(ns.PlayingCameraKey and ns.PlayingCameraKey()), type(script) == "table" and tostring(script.name or script.key or "?") or tostring(script),
		tostring(ns.OnTaxi and ns.OnTaxi()), tostring(facts.camera), tostring(facts.cam_flight),
		tostring(facts.cam_script)))
end

-- /cine debug cursor log [seconds]: a record of all the above for that long
-- (30 by default), into CinematicDB.debugCursorLog (kept apart from the log:
-- too many lines for it), to read after a /reload. A line each time
-- something changes, and one a second regardless.
local recorder
function ns.CursorHideRecord(seconds)
	seconds = tonumber(seconds) or 30
	CinematicDB.debugCursorLog = {}
	local lines = CinematicDB.debugCursorLog
	local started, lastKey, lastAt = GetTime(), nil, -1
	local lastX, lastY
	recorder = recorder or CreateFrame("Frame")
	local function Snapshot(now)
		local x, y = GetCursorPosition()
		local mouseMoved = x ~= lastX or y ~= lastY
		lastX, lastY = x, y
		local script = ns.PlayingCameraScript and ns.PlayingCameraScript()
		local db = ns.db
		-- (What decides it, without the times: a line when any of it changes.)
		local key = table.concat({
			"state=" .. (gone and "gone" or ns.cursorHidden and "tiny" or "shown"),
			"block=" .. tostring(needMove and "needMove" or lastBlock), "back=" .. tostring(lastShowWhy),
			"row=" .. tostring(RowShows(now)), "method=" .. tostring(db.cursorHideMethod),
			"cine=" .. tostring(ns.lastCinematic and true or false),
			"fight=" .. tostring(InCombatLockdown()), "taxi=" .. tostring(ns.OnTaxi and ns.OnTaxi() or false),
			"cam=" .. tostring(ns.activeCam),
			"scriptcam=" .. tostring(ns.PlayingCameraKey and ns.PlayingCameraKey()),
			"rule=" .. tostring((ns.RuleShows(ROW_KEY, ns.RuleFactsNow()))),
			"script=" .. (type(script) == "table" and tostring(script.name or script.key or "?") or tostring(script)),
			"steering=" .. tostring(IsMouselooking()), "mouse=" .. (mouseMoved and "moving" or "still"),
			"moving=" .. tostring(ns.playerMoving or false), "hardware=" .. tostring(GetCVar("HardwareCursor")),
			"cover=" .. tostring(cover and cover:IsShown() or false),
			"item=" .. tostring(GetCursorInfo() ~= nil), "chat=" .. tostring(ns.IsChatActive and ns.IsChatActive() or false),
		}, " ")
		return key
	end
	ns.Print(("Cursor Hide: recording for %d s. /reload after so it's saved."):format(seconds))
	ns.SetOnUpdate(recorder, function()
		local now = GetTime()
		local t = now - started
		if t > seconds then
			ns.SetOnUpdate(recorder, nil)
			lines[#lines + 1] = ("%.2f done"):format(t)
			ns.Print(("Cursor Hide: recorded %d lines. /reload to save them."):format(#lines))
			return
		end
		local key = Snapshot(now)
		if key ~= lastKey or now - lastAt >= 1 then
			lines[#lines + 1] = ("%.2f still=%.1f %s"):format(t, now - stillSince, key)
			lastKey, lastAt = key, now
		end
	end)
end

-- /cine debug cursorsize [value | cycle | back]: the game's Cursor Size
-- setting (Settings, Mouse; cursorSizePreferred), to see what it can do.
-- Bare: what it is now, its default and range. value: set to that. cycle:
-- -1 to 4, 3 seconds each, saying which. back: yours again. Yours is kept
-- in CinematicDB.debugCursorSizeWas until back (a /reload doesn't lose it).
local SIZE_CVAR = "cursorSizePreferred"
local sizeCycler
local function SizeInfo()
	local now = GetCVar(SIZE_CVAR)
	local default = (C_CVar and C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(SIZE_CVAR))
		or (GetCVarDefault and GetCVarDefault(SIZE_CVAR))
	local extra = ""
	if C_CVar and C_CVar.GetCVarInfo then
		local ok, value, defaultValue, server, character, locked, secure, readOnly = pcall(C_CVar.GetCVarInfo, SIZE_CVAR)
		if ok then
			extra = (" (info: value %s, default %s, account %s, character %s, locked %s, secure %s, read-only %s)"):format(
				tostring(value), tostring(defaultValue), tostring(server), tostring(character), tostring(locked),
				tostring(secure), tostring(readOnly))
		end
	end
	return ("%s = %s, default %s%s"):format(SIZE_CVAR, tostring(now), tostring(default), extra)
end
local function SetSize(value)
	if CinematicDB.debugCursorSizeWas == nil then CinematicDB.debugCursorSizeWas = GetCVar(SIZE_CVAR) or false end
	local ok, err = pcall(SetCVar, SIZE_CVAR, tostring(value))
	ns.Print(("Cursor size: set %s (%s); now %s; fight %s"):format(tostring(value), ok and "ok" or tostring(err),
		SizeInfo(), InCombatLockdown() and "yes" or "no"))
end
function ns.CursorSizeTest(arg)
	arg = arg or ""
	if GetCVar(SIZE_CVAR) == nil then
		ns.Print("Cursor size: this client has no " .. SIZE_CVAR .. " setting.")
		return
	end
	if sizeCycler then ns.SetOnUpdate(sizeCycler, nil) end
	if arg == "" then
		ns.Print("Cursor size: " .. SizeInfo() .. "; yours saved: " .. tostring(CinematicDB.debugCursorSizeWas))
	elseif arg:match("^hardware") then
		-- hardware 0 | 1 | back: the game's HardwareCursor ("if disabled,
		-- draws a software cursor"), to see if a software cursor takes our
		-- own pictures (the hardware one drew them as a black square).
		local value = arg:match("^hardware%s+(%S+)")
		if value == "back" then
			local was = CinematicDB.debugHardwareCursorWas
			if was == nil then ns.Print("Hardware cursor: nothing to put back.") return end
			pcall(SetCVar, "HardwareCursor", tostring(was))
			CinematicDB.debugHardwareCursorWas = nil
		elseif value == "0" or value == "1" then
			if CinematicDB.debugHardwareCursorWas == nil then
				CinematicDB.debugHardwareCursorWas = GetCVar("HardwareCursor")
			end
			pcall(SetCVar, "HardwareCursor", value)
		elseif value then
			ns.Print("/cine debug cursorsize hardware 0 | 1 | back")
			return
		end
		ns.Print(("Hardware cursor: HardwareCursor = %s; yours saved: %s"):format(tostring(GetCVar("HardwareCursor")),
			tostring(CinematicDB.debugHardwareCursorWas)))
	elseif arg:match("^pic") then
		-- pic blank | small | red | tiny | off: a test picture as the cursor,
		-- set every frame with the movement-only cover up (as Tiny), till off.
		local which = arg:match("^pic%s+(%S+)") or ""
		local TEST_PICS = { blank = "CursorBlank", small = "CursorTestSmall", red = "CursorTestRed" }
		local path = TEST_PICS[which] and ("Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\" .. TEST_PICS[which])
			or (which == "tiny" and TINY) or nil
		picTester = picTester or CreateFrame("Frame")
		if which == "off" or not path then
			ns.SetOnUpdate(picTester, nil)
			if cover and not ns.cursorHidden then cover:Hide() end
			pcall(ResetCursor)
			if which ~= "off" then ns.Print("/cine debug cursorsize pic blank | small | red | tiny | off") end
			return
		end
		if Cover().motionOnly then cover:Show() end
		ns.SetOnUpdate(picTester, function() pcall(SetCursor, path) end)
		ns.Print(("Cursor picture: %s (%s), HardwareCursor = %s. Move the mouse over the world; off to stop."):format(
			which, path, tostring(GetCVar("HardwareCursor"))))
	elseif arg == "focus" then
		-- Does the game tell addons when its window loses or gets focus? The
		-- functions named for it, then every event for 20 s while you switch
		-- away and back (what fires then, and the frame rate each second).
		local names = {}
		for name, value in pairs(_G) do
			if type(value) == "function" and type(name) == "string" then
				local lower = name:lower()
				if lower:find("focus", 1, true) or lower:find("window", 1, true) or lower:find("foreground", 1, true)
					or lower:find("active", 1, true) then
					names[#names + 1] = name
				end
			end
		end
		table.sort(names)
		ns.Print(("Focus: %d functions named focus/window/foreground/active (all in the log)."):format(#names))
		ns.Log("cursor", "focus functions: " .. table.concat(names, ", "))
		local NOISY = { COMBAT_LOG_EVENT_UNFILTERED = true, UNIT_AURA = true, UPDATE_MOUSEOVER_UNIT = true,
			CURSOR_CHANGED = false, UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true, NAME_PLATE_UNIT_ADDED = true,
			NAME_PLATE_UNIT_REMOVED = true, UNIT_HEALTH = true, ACTIONBAR_UPDATE_COOLDOWN = true,
			SPELL_UPDATE_COOLDOWN = true, BAG_UPDATE_COOLDOWN = true, CHAT_MSG_ADDON = true, UNIT_FLAGS = true }
		local listener = CreateFrame("Frame")
		local started, lastSecond = GetTime(), -1
		listener:RegisterAllEvents()
		listener:SetScript("OnEvent", function(_, event, ...)
			if NOISY[event] then return end
			ns.Log("cursor", ("focus event %.2f %s %s"):format(GetTime() - started, event,
				table.concat({ tostringall(...) }, " "):sub(1, 120)))
		end)
		ns.SetOnUpdate(listener, function()
			local t = GetTime() - started
			if math.floor(t) ~= lastSecond then
				lastSecond = math.floor(t)
				local x, y = GetCursorPosition()
				ns.Log("cursor", ("focus tick %d: fps %.0f, cursor %.0f,%.0f, over the world %s"):format(lastSecond,
					GetFramerate(), x, y, tostring(GetMouseFoci and #GetMouseFoci() or "?")))
			end
			if t > 20 then
				listener:UnregisterAllEvents()
				ns.SetOnUpdate(listener, nil)
				ns.Print("Focus: done. /reload so the log's saved.")
			end
		end)
		ns.Print("Focus: listening 20 s. Switch to another window, move the mouse over the game, switch back.")
	elseif arg == "cvars" or arg:match("^cvars ") then
		-- Every console setting with the word in its name (cursor by default),
		-- hidden ones too, with its value and help: C_Console (retail).
		local word = (arg:match("^cvars%s+(%S+)") or "cursor"):lower()
		local lister = (C_Console and C_Console.GetAllCommands) or _G.ConsoleGetAllCommands
		if not lister then
			-- (What it has instead, to look for another way.)
			local names = {}
			if type(C_Console) == "table" then
				for k in pairs(C_Console) do names[#names + 1] = tostring(k) end
			end
			table.sort(names)
			ns.Print(("Cursor size: no C_Console.GetAllCommands or ConsoleGetAllCommands. C_Console is %s%s; client %s"):format(
				type(C_Console), #names > 0 and (": " .. table.concat(names, ", ")) or "",
				tostring((select(4, GetBuildInfo())))))
			return
		end
		local ok, all = pcall(lister)
		if not ok or type(all) ~= "table" then
			ns.Print("Cursor size: listing failed: " .. tostring(all))
			return
		end
		local found = 0
		for _, info in ipairs(all) do
			local name = type(info) == "table" and info.command
			if type(name) == "string" and name:lower():find(word, 1, true) then
				found = found + 1
				local help = type(info.help) == "string" and info.help ~= "" and (" - " .. info.help) or ""
				ns.Print(("  %s = %s (type %s)%s"):format(name, tostring(GetCVar(name)), tostring(info.commandType), help))
				ns.Log("cursor", ("cvar %s = %s (type %s)%s"):format(name, tostring(GetCVar(name)),
					tostring(info.commandType), help))
			end
		end
		ns.Print(("Cursor size: %d of %d settings name \"%s\"."):format(found, #all, word))
	elseif arg == "back" then
		local was = CinematicDB.debugCursorSizeWas
		if was == nil then ns.Print("Cursor size: nothing to put back.") return end
		pcall(SetCVar, SIZE_CVAR, tostring(was or GetCVarDefault(SIZE_CVAR)))
		CinematicDB.debugCursorSizeWas = nil
		ns.Print("Cursor size: yours back. " .. SizeInfo())
	elseif arg == "cycle" then
		local values, i, left = { -1, 0, 1, 2, 3, 4 }, 0, 0
		sizeCycler = sizeCycler or CreateFrame("Frame")
		ns.SetOnUpdate(sizeCycler, function(_, elapsed)
			left = left - elapsed
			if left > 0 then return end
			i, left = i + 1, 3
			if not values[i] then
				ns.SetOnUpdate(sizeCycler, nil)
				ns.Print("Cursor size: cycle done. /cine debug cursorsize back puts yours back.")
				return
			end
			SetSize(values[i])
		end)
	elseif tonumber(arg) then
		SetSize(tonumber(arg))
	else
		ns.Print("/cine debug cursorsize [value | cycle | back]")
	end
end

-- The page ------------------------------------------------------------------

function ns.CreateCursorHidePage(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Cursor Hide"])
	title:SetPoint("TOPLEFT", 16, -16)
	ns.GroupTabs(content, title, "Cursor Hide")
	local intro = kit.PageIntro(content, title, L["In CineMode, the cursor gets out of the way: tiny, gone once " ..
		"the mouse has been still a while, or tiny and then gone. Moving the mouse brings it back from gone."])
	local switch = kit.PageSwitch(content, "cursorHide", L["Enable Page"],
		L["On: the cursor gets out of the way where its Show in row says."], intro, Apply)
	local stack = kit.Stack(switch, "check")
	local header = stack:Header(content, L["Show in"])
	local lastRow = ns.ShowTable(content, header, {
		opts = { anyFight = true }, underHeader = true, noCine = true, -- (CineMode only: Always says it all)
		{ key = ROW_KEY, label = L["Cursor Hide"], alwaysKey = "cursorHideAlways",
			alwaysOn = function() return ns.GetDB().cursorHideAlways end,
			setAlways = function(value) ns.GetDB().cursorHideAlways = value end,
			alwaysTip = L["All through CineMode. (The other columns then have nothing to add.)"],
			apply = function() rowReadAt = -1 end },
	}, L["Cursor Hide"])
	stack:Continue(lastRow, "label")

	stack:Header(content, L["Cursor"])
	stack:Add(kit.Choice(content, "cursorHideMethod", "tiny", L["Tiny"],
		L["The cursor stays a tiny corner, as you move and click too."]), "check")
	stack:Add(kit.Choice(content, "cursorHideMethod", "steer", L["Hide completely"],
		L["Once the mouse has been still a while, the cursor's gone, and moving the mouse brings it back. " ..
		"Meanwhile the game draws its cursor itself (its Hardware cursor off), which can feel a little behind " ..
		"at a low frame rate; yours is back with the cursor."]),
		"check")
	stack:Add(kit.Choice(content, "cursorHideMethod", "both", L["Tiny, then gone"],
		L["The tiny cursor all the time, as you move and click too, and gone once the mouse has been still a " ..
		"while (as Hide completely). Moving the mouse brings the tiny one back, not yours."]), "check")
	kit.GreyUnless(stack:Add(kit.Slider(content, "cursorHideDelay", L["Gone after the mouse is still for"],
		DELAY_MIN, DELAY_MAX, 0.5, "%.1f s"), "slider"), function(d) return d.cursorHideMethod ~= "tiny" end)

	-- The warning, over everything below the title till it's accepted (the
	-- account's): it's experimental, and /cine reset undoes it all.
	local gate = CreateFrame("Frame", nil, content)
	gate:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -8, -6)
	gate:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
	gate:SetFrameLevel(content:GetFrameLevel() + 50)
	gate:EnableMouse(true) -- (nothing under it can be clicked meanwhile)
	local shade = gate:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0.06, 0.05, 0.05, 0.97)
	-- A skull (the raid marker's: on every client) and a big red Experimental.
	local skull = gate:CreateTexture(nil, "ARTWORK")
	skull:SetSize(40, 40)
	skull:SetPoint("TOPLEFT", 16, -14)
	skull:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
	local warnTitle = kit.Label(gate, "GameFontNormalHuge", L["Experimental"])
	warnTitle:SetPoint("LEFT", skull, "RIGHT", 10, 0)
	warnTitle:SetTextColor(1, 0.25, 0.2)
	local warnText = kit.Label(gate, "GameFontHighlight", L["Cursor Hide changes how the game draws your cursor: " ..
		"it swaps in one of the game's own cursor pictures, and to hide it completely it turns the game's " ..
		"hardware cursor off for a while. It's experimental: the cursor may vanish where you need it, look " ..
		"wrong in places, or feel a little behind. While the cursor's hidden and the game isn't the window " ..
		"you're using, a black square can show over the game where the cursor is."])
	warnText:SetPoint("TOPLEFT", skull, "BOTTOMLEFT", 0, -12)
	warnText:SetWidth(520)
	warnText:SetJustifyH("LEFT")
	local resetText = kit.Label(gate, "GameFontHighlight", L["If your cursor ever gets stuck, type " ..
		"|cffffd100/cine reset cursor|r to put just your cursor back to normal, or |cffffd100/cine reset|r to put " ..
		"your profile back too. Either turns Cursor Hide off until you accept this again."])
	resetText:SetPoint("TOPLEFT", warnText, "BOTTOMLEFT", 0, -10)
	resetText:SetWidth(520)
	resetText:SetJustifyH("LEFT")

	-- Accept: only after the mouse has stayed on it HOLD seconds, counting
	-- down on it (off it, the count starts over).
	local HOLD = 5
	local accept = ns.PanelButton(gate)
	accept:SetSize(260, 26)
	accept:SetPoint("TOPLEFT", resetText, "BOTTOMLEFT", 0, -16)
	local overSince, ready
	local function AcceptText()
		if ready then
			accept:SetText(L["I understand, let me use it"])
		else
			local left = overSince and math.max(0, HOLD - (GetTime() - overSince)) or HOLD
			accept:SetText(L["Keep the mouse here: %d"]:format(math.ceil(left)))
		end
	end
	accept:HookScript("OnEnter", function() overSince = overSince or GetTime() end) -- (hooked: the skin's hover look stays)
	accept:HookScript("OnLeave", function()
		if not ready then overSince = nil AcceptText() end
	end)
	ns.SetOnUpdate(accept, function()
		if ready or not overSince then return end
		if GetTime() - overSince >= HOLD then ready = true end
		AcceptText()
	end)
	accept:SetScript("OnClick", function()
		if not ready then return end
		CinematicDB.cursorHideAccepted = true
		gate:Hide()
		Apply()
		kit.Refresh()
	end)
	local function GateShown()
		local shown = not ns.CursorHideAccepted()
		if shown and not gate:IsShown() then ready, overSince = false, nil end -- (a fresh hold each time it's back)
		gate:SetShown(shown)
		AcceptText()
	end
	GateShown()

	canvas:SetScript("OnShow", kit.PageShown(function()
		GateShown()
		kit.Refresh()
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Cursor Hide")
end
