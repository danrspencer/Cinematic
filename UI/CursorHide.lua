-- Cursor Hide (Interface hub, What Shows): in CineMode, the cursor gets out of
-- the way, where its Show in row says:
--   Replace cursor icon: always (CineMode or not, whatever the Show in row
--     says), a cursor of your pick (the game's tiniest, just a
--     corner, to start with) all the time till it's gone (SetCursor).
--     SetCursor's hardware cursor takes only the game's own Interface\Cursor
--     files (tested: our files, other textures and missing files all draw a
--     black square; none of its 389 cursors is blank).
--   gone once the mouse has been still a while.
--     With the game's hardware cursor off (HardwareCursor 0, "draws a
--     software cursor"), a picture it can't use as a cursor draws nothing at
--     all (tested: our red test picture showed nothing in the world; it
--     switches without a /reload). So while it's gone that's held off, and
--     put back as it comes back. The camera's left alone. (Mouse steering
--     did this before: it turned you as a camera circled, tested.) Over a
--     unit frame the game puts its own cursor back; with the game's window
--     in the background, Windows draws a black square over it.
--   With both, moving the mouse brings the pick back. (Tiny, Hide
--     completely and Tiny, then gone were three ways till 2026-11-19.)
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
DEFAULTS.cursorHideDelay = 3       -- seconds the mouse is still before it goes (3 at least: DELAY_MIN)
DEFAULTS.cursorReplaceIcon = false -- Replace cursor icon: the pick below shows till it's gone
DEFAULTS.cursorReplaceGameCursors = false -- ...but the game's own over a mailbox, an NPC (looks under the mouse: flashes)
DEFAULTS.cursorHideIcon = "Interface\\Cursor\\UnableItem" -- ...its cursor (the picker: CURSOR_ICONS)

local ROW_KEY = "cursor:hide"
-- Its Show in row's rule to start with, in every profile, and after any reset.
ns.RULE_DEFAULTS[ROW_KEY] = "cam_flight or cam_vista or cam_idle"
local TINY = "Interface\\Cursor\\UnableItem"
local CURSOR_FOLDER = "Interface\\Cursor\\"
-- The cursors Replace cursor icon can show (its picker, above the Show in
-- row): the game's own Interface\Cursor files only, as the hardware cursor
-- draws anything else as a black square (tested). Every single-cursor file
-- name the community file list (wow-listfile) has there, 2026-11-19; its
-- ui...2x sprite sheets left out. One this client lacks is left out.
local CURSOR_ICONS = {
	"unableitem", "item", "architect", "unablearchitect", "argusteleporter", "unableargusteleporter", "attack",
	"unableattack", "axe", "unableaxe", "bastionteleporter", "unablebastionteleporter", "broom", "unablebroom",
	"buy", "unablebuy", "cast", "unablecast", "crosshairs", "unablecrosshairs", "directions", "unabledirections",
	"disarmtrap", "unabledisarmtrap", "driver", "unabledriver", "engineerskin", "unableengineerskin", "ferry",
	"unableferry", "fishing", "unablefishing", "fishingcursor", "gatherherbs", "unablegatherherbs", "gunner",
	"unablegunner", "innkeeper", "unableinnkeeper", "inspect", "unableinspect", "interact", "unableinteract",
	"lootall", "unablelootall", "mail", "unablemail", "mappincursor", "unablemappincursor", "mine", "unablemine",
	"missions", "unablemissions", "openhand", "unableopenhand", "openhandglow", "unableopenhandglow", "palette",
	"unablepalette", "petting", "unablepetting", "picklock", "unablepicklock", "pickup", "unablepickup", "point",
	"unablepoint", "progenitorflightmaster", "unableprogenitorflightmaster", "pvp", "unablepvp", "quest",
	"unablequest", "questinteract", "unablequestinteract", "questrepeatable", "unablequestrepeatable",
	"questturnin", "unablequestturnin", "reforge", "unablereforge", "repair", "unablerepair", "repairnpc",
	"unablerepairnpc", "sawblade", "unablesawblade", "skin", "unableskin", "skinalliance", "unableskinalliance",
	"skinhorde", "unableskinhorde", "speak", "unablespeak", "stablemaster", "unablestablemaster", "taxi",
	"unabletaxi", "teleport", "unableteleport", "unablethumbdown", "unablethumbsdown", "thumbsup",
	"unablethumbsup", "unablethumbup", "trainer", "unabletrainer", "transmogrify", "unabletransmogrify",
	"ui-cursor-move", "unableui-cursor-move", "ui-cursor-size", "unableui-cursor-size", "ui-cursor-sizeleft",
	"unableui-cursor-sizeleft", "ui-cursor-sizeright", "unableui-cursor-sizeright", "vehichlecursor",
	"unablevehichlecursor", "voidstorage", "unablevoidstorage", "wildpet", "unablewildpet", "wildpetcapturable",
	"unablewildpetcapturable", "wildpetcrate", "unablewildpetcrate", "workorders", "unableworkorders"
}
-- Retail's newer cursors, in Interface\Cursor\Crosshair (from the same list).
local CROSSHAIR_FOLDER = CURSOR_FOLDER .. "Crosshair\\"
local CROSSHAIR_ICONS = {
	"architect", "unablearchitect", "argusteleporter", "unableargusteleporter", "attack", "unableattack", "axe",
	"unableaxe", "bastionteleporter", "unablebastionteleporter", "broom", "unablebroom", "buy", "unablebuy",
	"cast", "unablecast", "crosshairs", "unablecrosshairs", "directions", "unabledirections", "disarmtrap",
	"unabledisarmtrap", "driver", "unabledriver", "engineerskin", "unableengineerskin", "ferry", "unableferry",
	"fishing", "unablefishing", "fishingcursor", "gatherherbs", "unablegatherherbs", "gunner", "unablegunner",
	"innkeeper", "unableinnkeeper", "inspect", "unableinspect", "interact", "unableinteract",
	"item", "unableitem", -- (found by /cine debug cursorsize names on Forever, 2026-11-19)
	"lootall",
	"unablelootall", "mail", "unablemail", "mappincursor", "unablemappincursor", "mine", "unablemine", "missions",
	"unablemissions", "openhand", "unableopenhand", "openhandglow", "unableopenhandglow", "palette",
	"unablepalette", "picklock", "unablepicklock", "pickup", "unablepickup", "point", "unablepoint",
	"progenitorflightmaster", "unableprogenitorflightmaster", "pvp", "unablepvp", "quest", "unablequest",
	"questinteract", "unablequestinteract", "questrepeatable", "unablequestrepeatable", "questturnin",
	"unablequestturnin", "reforge", "unablereforge", "repair", "unablerepair", "repairnpc", "unablerepairnpc",
	"sawblade", "unablesawblade", "skin", "unableskin", "skinalliance", "unableskinalliance", "skinhorde",
	"unableskinhorde", "speak", "unablespeak", "stablemaster", "unablestablemaster", "taxi", "unabletaxi",
	"unablethumbdown", "unablethumbsdown", "thumbsup", "unablethumbsup", "unablethumbup", "trainer",
	"unabletrainer", "transmogrify", "unabletransmogrify", "ui-cursor-move", "unableui-cursor-move",
	"ui-cursor-size", "unableui-cursor-size", "ui-cursor-sizeleft", "unableui-cursor-sizeleft",
	"ui-cursor-sizeright", "vehichlecursor", "unablevehichlecursor", "voidstorage", "unablevoidstorage",
	"wildpet", "unablewildpet", "wildpetcapturable", "unablewildpetcapturable", "workorders", "unableworkorders"
}
local cursorHas = {} -- [path] = whether this client has it
local cursorProbe
local function CursorUsable(path)
	if type(path) ~= "string" then return false end
	-- (only the game's own cursor files, straight in Interface\Cursor or its
	-- Crosshair folder: anything else is a black square)
	local lower = path:lower()
	local inCrosshair = lower:sub(1, #CROSSHAIR_FOLDER) == CROSSHAIR_FOLDER:lower()
	local name = inCrosshair and lower:sub(#CROSSHAIR_FOLDER + 1)
		or lower:sub(1, #CURSOR_FOLDER) == CURSOR_FOLDER:lower() and lower:sub(#CURSOR_FOLDER + 1)
	if not name or name == "" or name:find("[\\/]") then return false end
	if cursorHas[path] == nil then
		if GetFileIDFromPath then
			local ok, id = pcall(GetFileIDFromPath, path)
			cursorHas[path] = ok and id ~= nil
		else
			-- (no GetFileIDFromPath: a texture says whether it found the file)
			cursorProbe = cursorProbe or CreateFrame("Frame"):CreateTexture()
			cursorProbe:SetTexture(nil)
			local ok, found = pcall(cursorProbe.SetTexture, cursorProbe, path)
			cursorHas[path] = ok and found ~= false and type(cursorProbe:GetTexture()) == "number"
		end
	end
	return cursorHas[path]
end
-- The cursor Replace cursor icon shows: the pick, or the tiny corner where it can't be used.
local function TinyIcon()
	local icon = ns.db and ns.db.cursorHideIcon
	return CursorUsable(icon) and icon or TINY
end
local cursorSource -- (IconBrowser's source: the cursors this client has)
local function CursorSource()
	if cursorSource then return cursorSource end
	local available
	cursorSource = {
		list = function()
			if not available then
				available = {}
				for _, name in ipairs(CURSOR_ICONS) do
					if CursorUsable(CURSOR_FOLDER .. name) then available[#available + 1] = CURSOR_FOLDER .. name end
				end
				for _, name in ipairs(CROSSHAIR_ICONS) do
					if CursorUsable(CROSSHAIR_FOLDER .. name) then available[#available + 1] = CROSSHAIR_FOLDER .. name end
				end
			end
			return available
		end,
		atlas = function() return false end,
		usable = CursorUsable,
		name = function(icon) return (icon:match("[^\\]*$")) end,
	}
	return cursorSource
end
local BLANK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\CursorBlank" -- (not a cursor: draws nothing)
local LAND = 0.3 -- seconds after it comes back that the cursor landing a pixel off isn't a move
local ROW_EVERY = 0.25 -- seconds between reads of the Show in row (rules aren't cheap)
local DELAY_MIN, DELAY_MAX = 3, 10 -- (the slider; a saved one under 3, from before, counts as 3)

-- The game's hardware cursor off while it's gone (yours back after, as the
-- addon's other held settings: ns.ApplyCVarSet).
local SOFTWARE = ns.CVarSet("Cursor Hide: software cursor", "the cursor gone: a software cursor draws " ..
	"Cursor Hide's blank picture as nothing", { values = { HardwareCursor = "0" } })

-- The picked cursor all the time till it's gone, as you move and click too
-- (only something on the cursor or the row turning off brings yours):
-- Replace cursor icon.
local function TinyAlways()
	return ns.db.cursorReplaceIcon == true
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

-- Replace cursor icon replaces only the game's default cursor: over a
-- mailbox, an NPC or an enemy the game's own shows. The game can't be asked
-- which cursor it shows over an object, so: over the world, a cover under
-- every UI frame (BACKGROUND) takes the mouse's movement, so the game
-- doesn't put its own back each frame. It steps aside for PROBE_TIME to
-- see what's under the mouse (a unit, or a world object's
-- tooltip) only after something moved (the mouse, you, your facing), once
-- it has settled SETTLE, or every PROBE_MOVING while it keeps moving: each
-- step aside shows the game's pointer for a moment (stepping aside every
-- 0.2 s flashed the cursor all the time, tested on Forever 2026-11-19).
-- Something there: the game's cursor till it's gone. Over a UI frame the
-- game doesn't put its own back, so ours just stays.
local PROBE_EVERY = 0.2 -- (at most this often)
local PROBE_TIME = 0.1 -- (its first frames show what was there before: the last tooltip, no mouseover yet, tested)
local LEAVE = 0.2 -- (nothing under the mouse this long before ours is back: not on one empty frame, tested)
local MOVE_PX = 2 -- (a still mouse reads half a pixel off now and then, Forever: not a move, tested)
local SETTLE = 0.08
local PROBE_MOVING = 1
local pickCover
local function PickCover()
	if pickCover then return pickCover end
	pickCover = CreateFrame("Frame", nil, WorldFrame)
	pickCover:SetAllPoints(WorldFrame)
	pickCover:SetFrameStrata("BACKGROUND")
	pickCover:SetFrameLevel(0)
	if pickCover.EnableMouseMotion then
		pickCover:EnableMouseMotion(true)
		if pickCover.EnableMouseClicks then pickCover:EnableMouseClicks(false) end
		if pickCover.SetPropagateMouseClicks then pickCover:SetPropagateMouseClicks(true) end
		pickCover.motionOnly = true
	end
	pickCover:Hide()
	return pickCover
end
local function MouseFocus()
	if GetMouseFoci then
		local foci = GetMouseFoci()
		return foci and foci[1]
	end
	return GetMouseFocus and GetMouseFocus()
end
-- Whether the game's cursor over this unit is its plain pointer (retail can
-- say; elsewhere a player you can't attack gets it).
local unitProbe
local pointerFiles
local function UnitPointer(unit)
	if SetUnitCursorTexture then
		unitProbe = unitProbe or CreateFrame("Frame"):CreateTexture()
		if not pointerFiles then
			pointerFiles = {}
			for _, path in ipairs({ "Interface\\Cursor\\Point", "Interface\\Cursor\\Crosshair\\Point" }) do
				unitProbe:SetTexture(nil)
				pcall(unitProbe.SetTexture, unitProbe, path)
				local file = unitProbe:GetTexture()
				if file then pointerFiles[file] = true end
			end
		end
		unitProbe:SetTexture(nil)
		if pcall(SetUnitCursorTexture, unitProbe, unit, nil, true) then
			local file = unitProbe:GetTexture()
			if file == nil then return true end
			if type(file) == "string" then return file:lower():find("point", 1, true) ~= nil end
			return pointerFiles[file] or false
		end
	end
	return UnitIsPlayer(unit) and not UnitCanAttack("player", unit)
end
-- What's under the mouse in the world that has a cursor of its own (or nil).
local function SomethingUnder()
	if UnitExists("mouseover") then
		local ok, plain = pcall(UnitPointer, "mouseover")
		if not (ok and plain) then return "unit" end
	end
	local tip = GameTooltip
	if tip and tip:IsShown() and tip:GetOwner() == UIParent and not (tip.GetUnit and tip:GetUnit()) then
		return "object" -- (a world object's tooltip: a mailbox, a herb, a chair)
	end
	return nil -- (a value, nil: tostring((SomethingUnder())) errored on none, tested)
end
local gameCursor -- (what's under the mouse that has the game's cursor, or nil)
local nextProbe, probeUntil, nothingSince = 0, nil, nil
local dirty, changedAt, probedAt = true, 0, 0 -- (something moved since the last look: when)
local lastX, lastY, lastFacing
local changeWhy, probeWhy -- (what counted as a move, and set off the last look: for the test's log)
-- Whether what's under the mouse may have changed since the last look.
local function NoteChanges(now)
	local x, y = GetCursorPosition()
	local ok, facing = pcall(GetPlayerFacing)
	if not ok or (issecretvalue and issecretvalue(facing)) then facing = nil end
	local far = not lastX or math.abs(x - lastX) > MOVE_PX or math.abs(y - lastY) > MOVE_PX
	if far or facing ~= lastFacing or ns.playerMoving then
		changeWhy = ("mouse %.2f,%.2f facing %s moving %s"):format((x or 0) - (lastX or 0), (y or 0) - (lastY or 0),
			facing ~= lastFacing and (facing and lastFacing and ("%.4f"):format(facing - lastFacing) or "nil change")
			or "same", tostring(ns.playerMoving or false))
		lastX, lastY, lastFacing = x, y, facing
		dirty, changedAt = true, now
	end
end
-- (/cine debug cursortest, Dev/CursorReplaceTest.lua: where Replace cursor
-- icon stands now. where: "ui", "world" or "game's"; under: unit/object/nil.)
function ns.CursorReplaceState()
	local focus = MouseFocus()
	local where = gameCursor and "game's" or (pickCover and focus == pickCover or focus == WorldFrame or focus == nil)
		and "world" or "ui"
	return where, gameCursor, (SomethingUnder()), pickCover and pickCover:IsShown() or false,
		focus and focus.GetName and focus:GetName() or (focus and "a frame") or "none", probeWhy
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
	if not ns.db.cursorHide or ns.MasterOff("cursorHide") then return "off" end
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
	if pickCover then pickCover:Hide() end
	gameCursor, probeUntil, nothingSince = nil, nil, nil
	pcall(ResetCursor)
	ns.LogDetail("cursor", "back: " .. why)
end

local function Set(picture, now, isGone)
	if isGone then
		if pickCover then pickCover:Hide() end
		if Cover().motionOnly then cover:Show() end
	elseif PickCover().motionOnly then
		pickCover:Show()
		nextProbe = now + PROBE_EVERY
	end
	if isGone then ns.ApplyCVarSet(SOFTWARE, true) end
	if pcall(SetCursor, picture) then
		ns.cursorHidden, gone = true, isGone
		ns.LogDetail("cursor", isGone and "gone" or "tiny")
	else
		if isGone then ns.ApplyCVarSet(SOFTWARE, false) end
		if cover then cover:Hide() end
		if pickCover then pickCover:Hide() end
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

-- Replace cursor icon, each frame while it's on (not gone): ours over the
-- world and UI, the game's over something with its own (see PickCover).
local function PickUpdate(now)
	local pc = PickCover()
	if not pc.motionOnly then -- (a client without movement-only frames: ours everywhere)
		pcall(SetCursor, TinyIcon())
		return
	end
	-- (Dev test only, /cine debug cursortest methods: other ways to keep ours,
	-- to find one that doesn't flash. "cover": ours always, never looking;
	-- "nocover": no cover, ours set each frame; "propagate": the cover passes
	-- the mouse's movement on to the world, so it may see what's under it.)
	-- (Always ours, never looking, unless Game's cursor over things is on:
	-- looking means the world sees the mouse, and the game then puts its
	-- pointer back each frame, a flash, tested on Forever 2026-11-19.)
	local method = ns.cursorPickMethod or (not ns.db.cursorReplaceGameCursors and "cover") or nil
	local propagate = method == "propagate"
	if pc.SetPropagateMouseMotion and pc.propagating ~= propagate then
		pc.propagating = propagate
		pcall(pc.SetPropagateMouseMotion, pc, propagate)
	end
	if method then
		pc:SetShown(method ~= "nocover")
		local under = method ~= "cover" and SomethingUnder() or nil
		if under ~= gameCursor and under then pcall(ResetCursor) end
		gameCursor = under
		if not under then pcall(SetCursor, TinyIcon()) end
		return
	end
	NoteChanges(now)
	local focus = MouseFocus()
	if pc:IsShown() then
		if focus == pc and dirty and now >= nextProbe
			and (now - changedAt >= SETTLE or now - probedAt >= PROBE_MOVING) then
			pc:Hide() -- (stepping aside: what's under the mouse, next frames)
			probeUntil, dirty, probedAt = now + PROBE_TIME, false, now
			probeWhy = changeWhy
		end
		pcall(SetCursor, TinyIcon())
		return
	end
	if focus ~= nil and focus ~= WorldFrame then -- (a UI frame: the game leaves ours there)
		gameCursor, probeUntil, nothingSince = nil, nil, nil
		pc:Show()
		nextProbe = now + PROBE_EVERY
		pcall(SetCursor, TinyIcon())
		return
	end
	if probeUntil and now < probeUntil then -- (still looking: its first frames are stale)
		if not gameCursor then pcall(SetCursor, TinyIcon()) end
		return
	end
	probeUntil = nil
	local under = SomethingUnder()
	if under then
		if gameCursor ~= under then
			pcall(ResetCursor)
			ns.LogDetail("cursor", "game's cursor: " .. under .. " under the mouse")
		end
		gameCursor, nothingSince = under, nil
		return
	end
	if gameCursor then
		nothingSince = nothingSince or now
		if now - nothingSince < LEAVE then return end
		ns.LogDetail("cursor", "game's cursor: nothing under the mouse now")
	end
	gameCursor, nothingSince = nil, nil
	pc:Show()
	nextProbe = now + PROBE_EVERY
	pcall(SetCursor, TinyIcon())
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
	-- (Replace cursor icon: always, CineMode or not, whatever the Show in
	-- row says; only something on the cursor brings yours. Hiding: where
	-- Blocked allows.)
	local replace = TinyAlways() and GetCursorInfo() == nil
	local blocked = Blocked(now)
	local busy = blocked or Busy()
	lastBlock = busy
	if ns.cursorHidden then
		if gone then
			if moved or busy then
				Show(moved and "mouse moved" or busy) -- (Replace cursor icon: the pick's back next frame)
			else
				pcall(SetCursor, BLANK) -- (each frame: the game sets its own when something comes under it)
			end
		elseif not replace then
			-- (Replaced, but Replace cursor icon's now off or something's on
			-- the cursor: yours back. Left, it stayed replaced, tested.)
			Show(GetCursorInfo() ~= nil and "cursor holding something" or "replace turned off")
		elseif not busy and GoneDue(now) then
			gameCursor, probeUntil, nothingSince = nil, nil, nil
			Set(BLANK, now, true) -- (still long enough: from the pick to gone)
		else
			PickUpdate(now)
		end
		return
	end
	if replace then
		Set(TinyIcon(), now, false)
	elseif blocked then
		return
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
	elseif ns.db and ns.db.cursorHide and not ns.MasterOff("cursorHide") and ns.CursorHideAccepted() then
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
	p(("Cursor Hide: %s, replace icon %s, delay %.1f s, Always %s, row on here %s; cursor %s (picked %s)"):format(
		db.cursorHide and "on" or "off", tostring(db.cursorReplaceIcon), Delay(),
		tostring(db.cursorHideAlways), tostring(RowShows(now)), TinyIcon(), tostring(db.cursorHideIcon)))
	local focus = MouseFocus()
	p(("  replace: game's cursor for %s; world cover %s; under the mouse %s; focus %s"):format(tostring(gameCursor),
		pickCover and (pickCover:IsShown() and "up" or "down") or "not made", tostring((SomethingUnder())),
		focus == pickCover and "our cover" or focus and (focus.GetName and focus:GetName() or "a frame") or "none"))
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
			"row=" .. tostring(RowShows(now)), "replace=" .. tostring(db.cursorReplaceIcon),
			"gameCursor=" .. tostring(gameCursor),
			"pickCover=" .. tostring(pickCover and pickCover:IsShown() or false),
			"under=" .. tostring((SomethingUnder())), "mouseover=" .. tostring(UnitExists("mouseover")),
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
	elseif arg == "names" then
		-- Cursor files this client has that the picker doesn't list: every
		-- name it knows, and likely others, tried in both folders with and
		-- without Unable and with size endings. Found ones go in the log.
		local known = {}
		for _, path in ipairs(CursorSource().list()) do known[path:lower()] = true end
		local bases, seen = {}, {}
		local function AddBase(name)
			name = name:lower():gsub("^unable", "")
			if not seen[name] then seen[name] = true bases[#bases + 1] = name end
		end
		for _, name in ipairs(CURSOR_ICONS) do AddBase(name) end
		for _, name in ipairs(CROSSHAIR_ICONS) do AddBase(name) end
		for _, name in ipairs({ "track", "lock", "important", "importantturnin", "campaignquest",
			"campaignquestturnin", "legendaryquest", "legendaryquestturnin", "recurring", "recurringturnin", "wrapper",
			"wrapperturnin", "holdinghand", "grabbinghand", "enchant", "gearenchant", "ping", "flightmaster", "loot",
			"talk", "chat", "bank", "vendor", "auction", "barber", "mailbox", "door", "chair", "herb", "ore", "treasure",
			"vehicle", "petbattle", "flag", "seat", "hand", "glove", "arrow", "hammer", "sword", "magnify" }) do
			AddBase(name)
		end
		local probe = CreateFrame("Frame"):CreateTexture()
		local function Exists(path)
			if GetFileIDFromPath then
				local ok, id = pcall(GetFileIDFromPath, path)
				return ok and id ~= nil
			end
			probe:SetTexture(nil)
			local ok, found = pcall(probe.SetTexture, probe, path)
			return ok and found ~= false and type(probe:GetTexture()) == "number"
		end
		local found, tried = {}, 0
		for _, folder in ipairs({ CURSOR_FOLDER, CROSSHAIR_FOLDER }) do
			for _, base in ipairs(bases) do
				for _, name in ipairs({ base, "unable" .. base }) do
					for _, ending in ipairs({ "", "_32", "_48", "_64", "_128", "2x", "_2x", "cursor" }) do
						local path = folder .. name .. ending
						tried = tried + 1
						if not known[path:lower()] and Exists(path) then found[#found + 1] = path end
					end
				end
			end
		end
		for _, path in ipairs(found) do ns.Log("cursor", "cursor file not in the picker: " .. path) end
		ns.Print(("Cursor names: tried %d, %d in the picker, %d more found%s (all in the log; GetFileIDFromPath %s)."):format(
			tried, #CursorSource().list(), #found,
			#found > 0 and (": " .. table.concat(found, ", "):sub(1, 150)) or "",
			GetFileIDFromPath and "yes" or "no"))
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
		ns.Print("/cine debug cursorsize [value | cycle | back | names]")
	end
end

-- The page ------------------------------------------------------------------

function ns.CreateCursorHidePage(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Cursor Hide"])
	-- (The Mouse icon's Cursor Hide tab, 2026-11-16: its tabs over the title.)
	local mouseTabs = ns.PageTabs(content, ns.ShowInTabs("mouse"), ns.ShowInIndex("mouse", "Cursor Hide"), true)
	title:SetPoint("TOPLEFT", mouseTabs, "BOTTOMLEFT", 8, -14)
	local intro = kit.PageIntro(content, title, L["In CineMode, the cursor shrinks or hides until you move the mouse."])
	local switch = kit.PageSwitch(content, "cursorHide", L["Enable Page"],
		L["On: the cursor gets out of the way where its Show in row says."], intro, Apply)
	local stack = kit.Stack(switch, "check")

	-- Replace cursor icon: its tick, and beside it a button showing the
	-- cursor picked, on a click the icon browser with the game's cursors.
	local replace = stack:Add(kit.Check(content, "cursorReplaceIcon", L["Replace cursor icon"],
		L["Your cursor is always the one picked here, until it hides."], function(value)
			ns.GetDB().cursorReplaceIcon = value
			kit.Refresh()
		end), "check")
	local browser = ns.IconBrowser(canvas, function(key, icon)
		ns.GetDB()[key] = icon
		kit.Refresh()
	end, CursorSource())
	local iconButton = CreateFrame("Button", nil, content)
	iconButton:SetSize(30, 30)
	iconButton:SetPoint("LEFT", replace, "LEFT", 220, 0)
	local edge = iconButton:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0.45, 0.38, 0.2, 1)
	local back = iconButton:CreateTexture(nil, "BORDER")
	back:SetPoint("TOPLEFT", 2, -2)
	back:SetPoint("BOTTOMRIGHT", -2, 2)
	back:SetColorTexture(0.05, 0.05, 0.05, 1)
	iconButton.icon = iconButton:CreateTexture(nil, "ARTWORK")
	iconButton.icon:SetAllPoints(back)
	local hl = iconButton:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(back)
	hl:SetColorTexture(1, 1, 1, 0.2)
	iconButton:SetScript("OnClick", function(self)
		browser:Open(self, "cursorHideIcon", TinyIcon())
	end)
	kit.Tooltip(iconButton, L["The cursor shown in place of yours; click to pick another."])
	iconButton.Refresh = function(self)
		self.icon:SetTexture(TinyIcon())
		self.icon:SetTexCoord(0, 1, 0, 1)
		self.icon:SetDesaturated(not self:IsEnabled())
	end
	kit.GreyUnless(iconButton, function(d) return d.cursorReplaceIcon == true end)
	kit.AddControl(iconButton)
	kit.RecordKey(content, "cursorHideIcon")
	-- (Its sub-option: the game's own cursor over things with one, by looking
	-- under the mouse after it moves, which flashes the game's pointer.)
	local gameCursors = stack:Add(kit.Check(content, "cursorReplaceGameCursors", L["Game's cursor over things"],
		L["Mailboxes, NPCs and enemies keep the game's own cursor; it can flash as you move."]), "check", 16)
	kit.GreyUnless(gameCursors, function(d) return d.cursorReplaceIcon == true end)

	local header = stack:Header(content, L["Show in"])
	local lastRow = ns.ShowTable(content, header, {
		opts = { anyFight = true }, underHeader = true,
		{ key = ROW_KEY, label = L["Cursor Hide"], alwaysKey = "cursorHideAlways",
			alwaysOn = function() return ns.GetDB().cursorHideAlways end,
			setAlways = function(value) ns.GetDB().cursorHideAlways = value end,
			alwaysTip = L["All through CineMode. (The other columns then have nothing to add.)"],
			apply = function() rowReadAt = -1 end },
	}, L["Cursor Hide"])
	stack:Continue(lastRow, "label")

	stack:Header(content, L["Cursor Hide"])
	stack:Add(kit.Slider(content, "cursorHideDelay", L["Gone after the mouse is still for"],
		DELAY_MIN, DELAY_MAX, 0.5, "%.1f s"), "slider")

	-- Its key, the same binding as the Keybinds page's row (set in either, both show it).
	local keyLabel = stack:Add(kit.Label(content, "GameFontHighlight", L["Hide Cursor till moves"]), "label")
	keyLabel:SetSize(200, 24)
	local first = kit.CreateKeybindButton(content, "CINEMATIC_HIDECURSOR", 1)
	first:SetPoint("LEFT", keyLabel, "RIGHT", 4, 0)
	local second = kit.CreateKeybindButton(content, "CINEMATIC_HIDECURSOR", 2)
	second:SetPoint("LEFT", first, "RIGHT", 8, 0)
	kit.PageIntro(content, second, L["Hides the cursor right away until you move the mouse."], keyLabel)

	-- The warning, over everything below the title till it's accepted (the
	-- account's): it's experimental, and /cine reset undoes it all.
	local gate = CreateFrame("Frame", nil, content)
	gate:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -8, -6)
	gate:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
	gate:SetFrameLevel(content:GetFrameLevel() + 50)
	gate:EnableMouse(true) -- (nothing under it can be clicked meanwhile)
	gate.layoutCover = true -- (/cine debug sweep: what's under it isn't seen, not an overlap)
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
		kit.RefreshKeybinds()
	end, content))
	canvas:RegisterEvent("UPDATE_BINDINGS")
	canvas:SetScript("OnEvent", kit.RefreshKeybinds)
	canvas:SetScript("OnHide", kit.StopListening)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Cursor Hide")
end
