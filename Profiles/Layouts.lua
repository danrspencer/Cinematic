-- Edit Mode layouts: Cinematic's own (EDIT_MODE_LAYOUTS), each made only
-- once a profile that uses it is picked (never just for installing: a
-- player's report 2026-11-17 found three new layouts they never asked for),
-- and switching to a profile's (ns.ApplyProfileLayout). A built-in profile whose
-- layout module names one (db.editModeLayout) switches Edit Mode to it when
-- it's picked, making it first if it isn't there; a profile without one
-- puts back the layout the player was on before. The dev build's Dev page
-- has a button per layout to make it or bring it up to date.
--
-- Each is the game's own: an account layout listed in Edit Mode beside the
-- player's, which they can change there like any other. Making one never
-- touches their layouts, and one with a design is made on a copy of theirs
-- (OwnBase), so only our frames move. Edit Mode only takes one made or brought up to date
-- this session after a reload (and saving there before then would put its
-- old copy back), so switching to one offers a reload (madeNow).

local _, ns = ...
local L = ns.L

ns.LAYOUT_NAME = "Retail Inspired"

-- Cinematic's own layouts' old names, and what they're called now: one
-- still under its old name counts as the new one, and is renamed in Edit
-- Mode on logging in (RenameOld; Edit Mode shows the old name till the
-- next reload) and in saved profiles (Core.lua).
ns.LAYOUT_RENAMED = {
	CINE_FOREVER_RETAIL_LAYOUT = "Retail Inspired",
	CINE_PURE_CINEMA_LAYOUT = "Personal Resource Centered",
}

-- A saved layout's name, an old one of ours as it's called now.
local function Named(layout)
	return ns.LAYOUT_RENAMED[layout.layoutName] or layout.layoutName
end

local function AccountType()
	return Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account or 1
end

local function Presets()
	local manager = _G.EditModePresetLayoutManager
	return manager and manager:GetCopyOfPresetLayouts() or {}
end

-- The saved layouts (not the presets), and a layout's place among them (nil: none).
local function FindLayout(name)
	local info = C_EditMode.GetLayouts()
	for i, layout in ipairs(info.layouts) do
		if Named(layout) == name then return info, i end
	end
	return info, nil
end

-- A whole-UI addon keeping Edit Mode on a layout of its own (ns.layoutKeeper,
-- set by its support file: fn() -> its name while it does). Profiles' layouts
-- are left to it then: it puts its own back on every login, so the two
-- would take turns, each asking for a reload.
local function KeptBy()
	local keeper = ns.layoutKeeper
	return keeper and keeper() or nil
end
local keptSaid = false
local function LeftToKeeper()
	local keeper = KeptBy()
	if keeper and not keptSaid then
		keptSaid = true
		ns.Log("state", "edit mode layout left to " .. keeper)
	end
	return keeper ~= nil
end

-- A layout's number for SetActiveLayout by name (a preset's too); nil if gone.
local function IndexOf(info, name)
	local presets = Presets()
	for i, preset in ipairs(presets) do
		if preset.layoutName == name then return i end
	end
	for i, layout in ipairs(info.layouts) do
		if Named(layout) == name then return #presets + i end
	end
end

-- A layout's name by its SetActiveLayout number (a preset's too).
local function NameAt(info, index)
	if not index then return nil end
	local presets = Presets()
	if index <= #presets then return presets[index].layoutName end
	local layout = info.layouts[index - #presets]
	return layout and Named(layout)
end

-- The active layout's name.
local function ActiveName(info)
	return NameAt(info, info.activeLayout)
end

-- The active layout's name (nil: no Edit Mode here).
function ns.ActiveLayoutName()
	if not (C_EditMode and C_EditMode.GetLayouts) then return nil end
	return ActiveName(C_EditMode.GetLayouts())
end

-- A profile's layout (db.editModeLayout) as the name to go to. A preset
-- (ns.LAYOUT_PRESET): the one the player is on now, or was on before a
-- profile switched it, else the first (Modern); nil: the game has none.
local function Target(info, name)
	if name ~= ns.LAYOUT_PRESET then return ns.LAYOUT_RENAMED[name] or name end
	local presets = Presets()
	local active = info.activeLayout
	if active and presets[active] then return presets[active].layoutName end
	for _, preset in ipairs(presets) do
		if preset.layoutName == ns.chardb.layoutOwn then return preset.layoutName end
	end
	return presets[1] and presets[1].layoutName
end

-- Shows or hides the extra action bars to match the game's toggles (bar 2 =
-- toggles[1]) without a reload. Not MultiActionBar_Update: called from here it
-- taints the bars' buttons, and their cooldowns then error on secret values.
-- A visibility state driver set and cleared at once instead: the game's
-- SecureStateDriverManager shows or hides the bar from its own secure code.
-- False when it can't (in a fight, a vehicle or override bar up, a bar
-- missing): the game shows them as toggled on the next reload.
local TOGGLE_BARS = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
	"MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }
local function ShowToggledBars(toggles)
	if InCombatLockdown() or not (RegisterStateDriver and UnregisterStateDriver) then return false end
	local main = _G.MainActionBar or _G.MainMenuBar
	if not (main and main:IsShown()) then return false end
	local ok = true
	for i, name in ipairs(TOGGLE_BARS) do
		local bar = _G[name]
		local want = toggles[i] and true or false
		if toggles[i] ~= nil and not bar then
			ok = false
		elseif bar and bar:IsShown() ~= want then
			RegisterStateDriver(bar, "visibility", want and "show" or "hide")
			UnregisterStateDriver(bar, "visibility")
			if bar:IsShown() ~= want then ok = false end
		end
	end
	return ok
end

-- The action bars one of ours lays out (def.bars: 2 = MultiBarBottomLeft, 3 =
-- MultiBarBottomRight...), switched on when it's switched to: they're the
-- game's Action Bars options, not part of a layout. The ones Cinematic
-- switched on (chardb.layoutBarsOn) go back off on any other layout.
local function SyncBars(name)
	if not (GetActionBarToggles and SetActionBarToggles) or not ns.chardb then return end
	local def = name and ns.EDIT_MODE_LAYOUTS[name]
	local bars = def and def.bars
	if type(bars) == "function" then bars = bars() end
	local toggles = { GetActionBarToggles() }
	local on = ns.chardb.layoutBarsOn or {}
	local changed = false
	if bars then
		for _, bar in ipairs(bars) do
			if toggles[bar - 1] == false then
				toggles[bar - 1], on[bar] = true, true
				changed = true
			end
		end
	else
		for bar in pairs(on) do
			if toggles[bar - 1] then
				toggles[bar - 1] = false
				changed = true
			end
		end
		on = {}
	end
	ns.chardb.layoutBarsOn = next(on) and on or nil
	if not changed then return end
	SetActionBarToggles(unpack(toggles))
	local shown = ShowToggledBars(toggles)
	if not shown then StaticPopup_Show("CINEMATIC_BARS_RELOAD") end
	ns.Log("state", "edit mode layout action bars: " .. (def and "on" or "back off")
		.. (shown and " (shown now)" or " (after a reload)"))
end

-- Switches Edit Mode's layout, with the faded frames at full size for it
-- (Frames.lua: shrunk, they'd keep their old size and place).
local function SetActive(index)
	if ns.UnshrinkForLayout then ns.UnshrinkForLayout() end
	C_EditMode.SetActiveLayout(index)
	SyncBars(NameAt(C_EditMode.GetLayouts(), index))
end

-- Without an export string: the Modern preset with the dev's changes to it
-- (the layout as it was at 17:30 on 2026-10-20, read from the game's own
-- Edit Mode save). Each: Enum.EditModeSystem, its index (nil: none), where
-- it's anchored (none: where Modern has it), and the settings that differ
-- from Modern (setting = value).
local UNIT_FRAME = Enum.EditModeSystem and Enum.EditModeSystem.UnitFrame or 3
local PARTY = Enum.EditModeUnitFrameSystemIndices and Enum.EditModeUnitFrameSystemIndices.Party or 4
local RAID_STYLE_PARTY = Enum.EditModeUnitFrameSetting and Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames or 4
local DESIGN = {
	-- (Bar 3's two rows beside bars 1 and 2: its bottom row on bar 1's, and bar 2
	-- level with its top row, so the gap between 1 and 2 is its own rows' gap.)
	-- (Bars 2 and 3 2 apart, the gap between buttons in a bar (measured on
	-- Forever, 2026-11-10), so the three look like one block.)
	-- (Bar 1 left of centre by half of bar 3 and the gap, so bars 1-3 together are centred.)
	{ 0, 1, "BOTTOM", "UIParent", "BOTTOM", -141, 42, { [6] = 1 } },        -- action bar 1 (no bar art)
	{ 0, 2, "TOPRIGHT", "MultiBarBottomRight", "TOPLEFT", -2, 0 },          -- 2
	{ 0, 3, "BOTTOMLEFT", "MainActionBar", "BOTTOMRIGHT", 2, 0, { [1] = 2 } }, -- 3 (2 rows)
	-- (Stance and pet bars in the same spot above bar 2: a class has one or the other.)
	{ 0, 11, "BOTTOMLEFT", "MultiBarBottomLeft", "TOPLEFT", 0, 4 },         -- stance bar
	{ 0, 12, "BOTTOMLEFT", "MultiBarBottomLeft", "TOPLEFT", 0, 4 },         -- pet bar
	{ 0, 13, "BOTTOMLEFT", "MultiBarBottomLeft", "TOPLEFT", 0, 4 },         -- possess bar
	-- (Above bar 3, clear of the swing timers in the middle.)
	{ 4, nil, "BOTTOMLEFT", "MultiBarBottomRight", "TOPLEFT", 0, 4 },       -- encounter bar
	{ 9, nil, "BOTTOMLEFT", "MultiBarBottomLeft", "TOPLEFT", 0, 4 },        -- vehicle leave button
	{ 13, nil, "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -2, 2 },           -- micro menu
	{ 14, nil, "BOTTOMRIGHT", "MicroMenuContainer", "TOPRIGHT", 0, 4 },     -- bags
	-- (status bars' setting 3: width, 0 = 50%, 10 = 100%)
	{ 15, 1, "BOTTOM", "UIParent", "BOTTOM", 0, 0, { [3] = 0 } },           -- status bar 1
	{ 15, 2, "BOTTOM", "MainStatusTrackingBarContainer", "TOP", 0, 0, { [3] = 0 } }, -- status bar 2
	{ 25, nil, "BOTTOMLEFT", "MultiBarBottomLeft", "TOPLEFT", 0, 4 },
	{ 26, 1, "RIGHT", "MultiBarBottomLeft", "LEFT", 30, 13, { [0] = 1 } },  -- action bar end caps
	{ 26, 2, "LEFT", "MultiBarBottomRight", "RIGHT", -30, 38.2, { [0] = 1 } },
	-- The centre stack, bottom up, each on top of the one below (so nothing
	-- overlaps whatever the screen's height or UI scale: none of it is
	-- placed from the screen's middle): the swing timers on bar 2 (in line
	-- with the screen's middle: bar 1's -141 back), ranged, off hand, main
	-- hand; the Cooldown Manager's utility and essential rows; then (below,
	-- with the system's number) the personal resource display, the cast bar
	-- and the Cooldown Manager's buff icons on top. (Swing timers' setting 3:
	-- width, 0 the narrowest, as the dev set it in Edit Mode on 2026-11-05.)
	{ 29, 3, "BOTTOM", "MultiBarBottomLeft", "TOP", 141, 6, { [3] = 0 } },   -- swing timers: ranged
	{ 29, 2, "BOTTOM", "SwingTimerRangedFrame", "TOP", 0, 4, { [3] = 0 } },  -- off hand
	{ 29, 1, "BOTTOM", "SwingTimerOffHandFrame", "TOP", 0, 4, { [3] = 0 } }, -- main hand
	{ 20, 2, "BOTTOM", "SwingTimerMainHandFrame", "TOP", 0, 6 },            -- cooldown viewers: utility
	{ 20, 1, "BOTTOM", "UtilityCooldownViewer", "TOP", 0, 4 },              -- essential
	-- (No anchor: where the base layout has it. presetOnly: only when made on
	-- a game preset; on the player's own layout their party frames stay as
	-- they set them.)
	{ UNIT_FRAME, PARTY, nil, nil, nil, nil, nil, { [RAID_STYLE_PARTY] = 1 }, presetOnly = true }, -- party frames: raid-style
}

-- Pure Cinema's retail layout: the dev's PURE_CINEMA, as the game's Edit Mode
-- save had it (WTF edit-mode-cache-account, 2026-10-29): one line per system
-- (system, index, in its default spot, point, relative point, relative to,
-- x, y, -1, settings), in the game's own export format, so it's put together
-- into an export string (ExportFromSystems). The personal resource display
-- moved to the middle (its health bar shown: its first setting, HideHealth,
-- 0), the Cooldown Manager above it. The cast bar out of its default spot
-- (in it, the game stacks it above whatever pet or stance bar is up). The
-- pet and stance bars and the vehicle leave button stay in theirs: pinned
-- to bar 2, they went to the screen's top left on characters without it.
-- The party frames raid-style (their line's first setting, '$: setting 4,
-- UseRaidStylePartyFrames, 1).
local PURE_CINEMA_SYSTEMS = {
	"0 0 1 7 7 UIParent 0.0 45.0 -1 ##$$%/&('%)#+#,$",
	"0 1 1 7 7 UIParent 0.0 45.0 -1 ##$$%/&('%(#,$",
	"0 2 1 7 7 UIParent 0.0 45.0 -1 ##$$%/&('%(#,$",
	"0 3 1 5 5 UIParent -5.0 -77.0 -1 #$$$%/&('%(#,$",
	"0 4 1 5 5 UIParent -5.0 -77.0 -1 #$$$%/&('%(#,$",
	"0 5 0 1 1 UIParent 0.0 -2.0 -1 ##$$%/&('%(#,$",    -- bars 6-8: top middle (as TOP_BARS)
	"0 6 0 1 1 UIParent 0.0 -52.0 -1 ##$$%/&('%(#,$",
	"0 7 0 1 1 UIParent 0.0 -102.0 -1 ##$$%/&('%(#,$",
	"0 10 1 7 7 UIParent 0.0 45.0 -1 ##$$&('%",
	"0 11 1 7 7 UIParent 0.0 45.0 -1 ##$$&('%,#",
	"0 12 1 7 7 UIParent 0.0 45.0 -1 ##$$&('%",
	"1 -1 0 4 4 UIParent 0.0 -240.7 -1 ##$#%#",
	"2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%(&(",
	"3 0 1 8 7 UIParent -300.0 250.0 -1 $#3#",
	"3 1 1 6 7 UIParent 300.0 250.0 -1 %#3#",
	"3 2 1 6 7 UIParent 520.0 265.0 -1 %#&#3#",
	"3 3 1 0 2 CompactRaidFrameManager 0.0 -7.0 -1 '$(#)#-=.+/#1$3#5#6(7-7$8(9(",
	"3 4 1 0 2 CompactRaidFrameManager 0.0 -5.0 -1 ,#-=.+/#0#1#2(3#5#6(7-7$8(9(",
	"3 5 1 5 5 UIParent 0.0 0.0 -1 &#*$3#",
	"3 6 1 5 5 UIParent 0.0 0.0 -1 -=.+/#4$5#6(7-7$8(9(",
	"3 7 1 4 4 UIParent 0.0 0.0 -1 3#",
	"4 -1 0 2 2 UIParent -414.5 -277.8 -1 #",
	"5 -1 0 4 4 UIParent 0.0 -80.4 -1 #",
	"6 0 1 2 2 UIParent -255.0 -10.0 -1 ##$#%#&.(()(",
	"6 1 1 2 2 UIParent -270.0 -155.0 -1 ##$#%#'+(()(-$",
	"6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$",
	"7 -1 0 4 4 UIParent 0.0 60.0 -1 #",                -- talking head: in the middle, a little above centre
	"8 -1 1 6 6 UIParent 35.0 50.0 -1 #'$A%$&i",
	"9 -1 1 7 7 UIParent 0.0 45.0 -1 #",
	"10 -1 1 0 0 UIParent 16.0 -116.0 -1 #",
	"11 -1 1 8 8 UIParent -9.0 85.0 -1 #",
	"12 -1 1 2 2 UIParent -110.0 -275.0 -1 #K$#%#",
	"13 -1 1 8 8 MicroButtonAndBagsBar 0.0 0.0 -1 ##$#%)&-",
	"14 -1 1 2 2 MicroButtonAndBagsBar 0.0 10.0 -1 ##$#%(",
	"15 0 1 7 7 StatusTrackingBarManager 0.0 0.0 -1 &-",
	"15 1 1 7 7 StatusTrackingBarManager 0.0 17.0 -1 &-",
	"16 -1 1 5 5 UIParent 0.0 0.0 -1 #(",
	"17 -1 0 4 4 UIParent 0.0 355.3 -1 ##",
	"18 -1 1 5 5 UIParent 0.0 0.0 -1 #-",
	"19 -1 0 5 5 UIParent -438.3 251.7 -1 ##",
	"20 0 0 4 4 UIParent 0.0 -350.0 -1 ##$/%$&('%(-($)#+$,$-$",
	"20 1 0 4 4 UIParent 0.0 -403.3 -1 ##$7%$&('%(-($)#+$,$-$",
	"20 2 0 4 4 UIParent 0.0 -293.3 -1 ##$$%$&('((-($)#+$,$-$",
	"20 3 1 7 7 UIParent 420.0 430.0 -1 #$$$%#&('((-($)#*#+$,$-$.-.$",
	"21 -1 0 4 4 UIParent 0.0 -204.7 -1 ##%#&#'((()#*-*$+#,&-#.#/(0#1#",
	"22 0 1 8 7 UIParent -457.0 336.0 -1 #$$$%#&('((#)U*$+%,$-#.#/U0%",
	"22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+%",
	"22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+%",
	"22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+%",
	"23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&7&%'7(%)U+$,$-$.(/U",
	"24 -1 0 4 4 UIParent -22.5 241.3 -1 #",
	"26 -1 1 4 4 UIParent 0.0 0.0 -1 #(",
}

-- Forever's Personal Resource Centered: the Modern preset with the personal
-- resource display moved to the middle, where retail's has it (no export of
-- Forever's yet; its system number by name, none on a client without it).
local PRD_SYSTEM = Enum.EditModeSystem and Enum.EditModeSystem.PersonalResourceDisplay
if not PRD_SYSTEM and Enum.EditModeSystem then
	-- (another name on this client: any with "Personal" in it)
	for key, value in pairs(Enum.EditModeSystem) do
		if type(key) == "string" and key:find("Personal") then PRD_SYSTEM = value end
	end
end
local FOREVER_PURE = PRD_SYSTEM and { { PRD_SYSTEM, nil, "CENTER", "UIParent", "CENTER", 0, -205 } } or {}
-- Retail Inspired's in the middle too, as retail has it, not in Modern's
-- spot at the left: in the centre stack (DESIGN) on the essential row, the
-- cast bar on it and the buff icons on that. (No such system: the cast bar
-- on the essential row.)
do
	local below = "EssentialCooldownViewer"
	if PRD_SYSTEM then
		DESIGN[#DESIGN + 1] = { PRD_SYSTEM, nil, "BOTTOM", below, "TOP", 0, 4 }
		below = "PersonalResourceDisplayFrame"
	end
	-- (16 up: Forever's cast bar writes the spell's name under itself, which
	-- sat on the personal resource display's health bar at 4, 2026-11-13.)
	DESIGN[#DESIGN + 1] = { 1, nil, "BOTTOM", below, "TOP", 0, PRD_SYSTEM and 16 or 4 } -- cast bar
	DESIGN[#DESIGN + 1] = { 20, 3, "BOTTOM", "PlayerCastingBarFrame", "TOP", 0, 4 }    -- buff icons
end

-- The Follow HUD (dev only, Forever): a centred HUD that moves as one, for the
-- Shoulder Cam's Frames follow you (ShoulderCam.lua), in pieces, each its own
-- set of Edit Mode changes (FOLLOW_HUD_PIECES), so a player can take some and
-- keep the rest of their own layout. Put together with ns.FollowHudDesign.
--   stack: one root, the personal resource display, on the screen's bottom
--     (the only frame placed on the screen): the cast bar on it, the
--     Cooldown Manager's rows and buff icons above that (so the PRD, cast bar
--     and portraits sit at the same height whether the rows are full or
--     empty: 1 unit tall), the swing timers hanging down under it (main
--     hand, off hand, ranged). Frames follow you moves the PRD and the rest
--     ride along. No PRD system: the cast bar is the root.
--   sizes: the PRD, cast bar and swing timers one width (without it, the
--     player's own sizes stay).
--   portraits: the player and target frames each side of it, 300 from the
--     middle (as Retail Inspired's, clear of a 12-icon essential row), pinned
--     to the screen, not hung on the PRD: they're protected, and the game
--     locks whatever a protected frame hangs on in a fight, so hung on it
--     they held the whole HUD still in fights (2026-11-13).
-- Mockup: https://claude.ai/artifact/PPvLu5DMCUPEgBpNG2zEy6 (2026-11-07).
-- Two of each, by what sits at the root (picks.root): "prd", the personal
-- resource display (as above), or "player", the player frame: then the cast
-- bar's the root, and the player frame is pinned to the screen under the
-- stack, centred, as the PRD would be. It can't slide with you: the game locks
-- it in fights (and anything it hangs on), so it stays put while the rest
-- glide over to you. Its portraits piece moves the target frame alone.
local FOLLOW_HUD_PIECES = {}
ns.FOLLOW_HUD_PIECE_ORDER = { "stack", "sizes", "portraits" }
ns.FOLLOW_HUD_ROOTS = { "prd", "player" }
do
	local indices = Enum.EditModeUnitFrameSystemIndices or {}
	-- One width for the three (2026-11-13; the sizes run and screenshots
	-- measured at 1.22 px a unit): the cast bar's Bar Size (setting 0, 100-150,
	-- kept in steps of 10: 1 = 110) makes it 229 wide with its art. The PRD's
	-- Bar Width (setting 12, 50-150, steps of 10) can't reach that alone (110:
	-- 220), so 140 (9) at a Size (setting 9, 70-150, steps of 10) of 80 (1):
	-- about 224 to the eye, its bars 19 tall (settings 4 and 5, 10-30, steps
	-- of 1: 9) so 15 after the size, as before. The swing timers' Width
	-- (setting 3, 213-852) is kept in single units, not steps (1 made it
	-- 214): 19 = 232, the same to the eye; their Height (setting 4, 15-60,
	-- 5 = 20) thinner than the game's 30.
	local SWING_SIZE = { [3] = 19, [4] = 5 }
	local PRD_SIZE, CAST_SIZE = { [12] = 9, [9] = 1, [4] = 9, [5] = 9 }, { [0] = 1 }
	local PLAYER, TARGET = indices.Player or 1, indices.Target or 2
	for _, kind in ipairs(ns.FOLLOW_HUD_ROOTS) do
		local stack, sizes = {}, {}
		local root, rootName = 1, "PlayerCastingBarFrame"
		local withPRD = kind == "prd" and PRD_SYSTEM
		if withPRD then
			root, rootName = PRD_SYSTEM, "PersonalResourceDisplayFrame"
			stack[#stack + 1] = { 1, nil, "BOTTOM", rootName, "TOP", 0, 26 }               -- cast bar (its name under it)
			sizes[#sizes + 1] = { 1, nil, nil, nil, nil, nil, nil, CAST_SIZE }
		end
		-- (330: just under your feet at a normal zoom; 210 put it down by the
		-- action bars, "too low", 2026-11-13.)
		stack[#stack + 1] = { root, nil, "BOTTOM", "UIParent", "BOTTOM", 0, 330 }          -- the root
		sizes[#sizes + 1] = { root, nil, nil, nil, nil, nil, nil, withPRD and PRD_SIZE or CAST_SIZE }
		stack[#stack + 1] = { 20, 1, "BOTTOM", "PlayerCastingBarFrame", "TOP", 0, 6 }       -- cooldowns: essential
		stack[#stack + 1] = { 20, 2, "BOTTOM", "EssentialCooldownViewer", "TOP", 0, 4 }     -- utility
		stack[#stack + 1] = { 20, 3, "BOTTOM", "UtilityCooldownViewer", "TOP", 0, 4 }       -- buff icons
		stack[#stack + 1] = { 29, 1, "TOP", rootName, "BOTTOM", 0, -12 }                    -- swing timers: main hand (a gap under the root)
		stack[#stack + 1] = { 29, 2, "TOP", "SwingTimerMainHandFrame", "BOTTOM", 0, -4 }    -- off hand
		stack[#stack + 1] = { 29, 3, "TOP", "SwingTimerOffHandFrame", "BOTTOM", 0, -4 }     -- ranged
		for index = 1, 3 do sizes[#sizes + 1] = { 29, index, nil, nil, nil, nil, nil, SWING_SIZE } end
		local portraits
		if kind == "player" then
			-- (Under the swing timers (12 + 3 x 24 under the cast bar's bottom),
			-- on the screen, not hung on them: a first guess, untested in game.)
			stack[#stack + 1] = { UNIT_FRAME, PLAYER, "TOP", "UIParent", "BOTTOM", 0, 240 } -- player frame
			portraits = {
				{ UNIT_FRAME, TARGET, "LEFT", "UIParent", "BOTTOM", 300, 345 },              -- target frame
			}
		else
			-- (On the screen, level with the PRD's middle: 330 up, about 15 more.)
			portraits = {
				{ UNIT_FRAME, PLAYER, "RIGHT", "UIParent", "BOTTOM", -300, 345 },            -- player frame
				{ UNIT_FRAME, TARGET, "LEFT", "UIParent", "BOTTOM", 300, 345 },              -- target frame
			}
		end
		FOLLOW_HUD_PIECES[kind] = { stack = stack, sizes = sizes, portraits = portraits }
	end
end

-- A design from the pieces picked (picks: piece -> true; nil: stack and
-- sizes), one row per frame: a later piece's place and settings go over an
-- earlier's for the same frame (sizes adds its settings to stack's place).
-- base: rows to start from (copied).
function ns.FollowHudDesign(picks, base)
	picks = picks or { stack = true, sizes = true }
	local pieces = FOLLOW_HUD_PIECES[picks.root or "prd"] or FOLLOW_HUD_PIECES.prd
	local design, at = {}, {}
	local function Add(row)
		local key = tostring(row[1]) .. ":" .. tostring(row[2])
		local have = at[key]
		-- (Ids that aren't plain numbers, as the offline stand-in's Enum gives,
		-- can look alike for two frames: a second place there is a row of its own.)
		if have and have[3] and row[3] and type(row[1]) ~= "number" then have = nil end
		if not have then
			have = { row[1], row[2], presetOnly = row.presetOnly }
			at[key] = have
			design[#design + 1] = have
		end
		if row[3] then
			for i = 3, 7 do have[i] = row[i] end
		end
		if row[8] then
			local settings = {}
			for setting, value in pairs(have[8] or {}) do settings[setting] = value end
			for setting, value in pairs(row[8]) do settings[setting] = value end
			have[8] = settings
		end
	end
	for _, row in ipairs(base or {}) do Add(row) end
	for _, piece in ipairs(ns.FOLLOW_HUD_PIECE_ORDER) do
		if picks[piece] then
			for _, row in ipairs(pieces[piece]) do Add(row) end
		end
	end
	return design
end

-- Shoulder Cam (the Shoulder Cam profile's layout): Retail Inspired's action
-- bars and the rest, with all of the Follow HUD's pieces in place of its
-- centre stack.
local SHOULDER_HUD
do
	local STACK = { [29] = true, [20] = true, [1] = true }
	if PRD_SYSTEM then STACK[PRD_SYSTEM] = true end
	local rest = {}
	for _, row in ipairs(DESIGN) do
		if not STACK[row[1]] then rest[#rest + 1] = row end
	end
	SHOULDER_HUD = ns.FollowHudDesign({ stack = true, sizes = true, portraits = true }, rest)
end

-- Retail laid out like WoW Forever's default: its party frames raid-style.

-- Action bars 6-8 at the top middle in all of ours, not in the middle of the
-- screen where Modern has them. Each from the screen's top, not chained to the
-- one above: these bars are often off, and a bar pinned to one that's off goes
-- to the screen's top left. 50 apart, Modern's own spacing.
local TOP_BARS = {
	{ 0, 6, "TOP", "UIParent", "TOP", 0, -2 },
	{ 0, 7, "TOP", "UIParent", "TOP", 0, -52 },
	{ 0, 8, "TOP", "UIParent", "TOP", 0, -102 },
}
for _, design in ipairs({ DESIGN, FOREVER_PURE, SHOULDER_HUD }) do
	for _, bar in ipairs(TOP_BARS) do design[#design + 1] = bar end
end

-- Cinematic's own layouts, by the name Edit Mode lists them under. export:
-- an Edit Mode export string (Share > Copy to Clipboard); without one, design:
-- changes to the player's own layout (OwnBase; Modern if none), as DESIGN:
-- only the frames it lists move, the rest stay where the player had them
-- (party and raid frames, unit frames, minimap, chat...). bars: the action bars it lays
-- out, switched on with it (SyncBars).
ns.EDIT_MODE_LAYOUTS = {
	[ns.LAYOUT_NAME] = { export = nil, design = DESIGN, bars = { 2, 3 },
		client = "forever" },
	-- Retail laid out like WoW Forever's default (the retail profile "Forever").
	-- Not designed yet: a copy of Modern until its export string's in (its
	-- party frames raid-style, as Forever's).
	-- (the Cinema profile's: retail's from the dev's own, Forever's designed)
	["Personal Resource Centered"] = ns.isRetail and { systems = PURE_CINEMA_SYSTEMS, client = "retail" }
		or { design = FOREVER_PURE, client = "forever" },
}
-- (Made when its profile is picked, like the others, from the layout the
-- player is on then; a reload offered as it's made.)
ns.EDIT_MODE_LAYOUTS["Shoulder Cam"] = { design = SHOULDER_HUD, bars = { 2, 3 }, client = "forever" }
-- The Follow HUD (dev only for now, FollowHud.lua): the layout the player was
-- on as it was set up (chardb.followHudBase: theirs, or one of ours like
-- Retail Inspired), with just the Follow HUD's pieces picked (the profile's
-- followHud.picks; none: stack and sizes) on it, the rest as they had it
-- (their bars, raid frames, chat...). Made only when it's set up, never on
-- logging in. Its action bars: the ones its base switches on. (Functions,
-- read as it's made or switched to.)
local function FollowHudBase() return ns.chardb and ns.chardb.followHudBase end
ns.EDIT_MODE_LAYOUTS["Follow HUD"] = { client = "forever", onDemand = true,
	base = FollowHudBase,
	design = function()
		local saved = ns.db and ns.db.followHud
		return ns.FollowHudDesign(saved and saved.picks)
	end,
	bars = function()
		local base = ns.EDIT_MODE_LAYOUTS[FollowHudBase() or ""]
		local bars = base and base.bars
		return type(bars) == "table" and bars or nil
	end }

-- A layout's design rows (def.design, or what its function gives now).
local function DesignOf(def)
	if type(def.design) == "function" then return def.design() end
	return def.design
end

-- A layout from systems lines (as PURE_CINEMA_SYSTEMS): the export string is
-- a format version, the number of systems, then the lines. (The Edit Mode
-- save is version 2; 1 tried too.) Nil if the game reads neither.
local function ExportFromSystems(systems)
	local body = #systems .. " " .. table.concat(systems, " ")
	for _, version in ipairs({ 2, 1 }) do
		local layout = C_EditMode.ConvertStringToLayoutInfo(version .. " " .. body)
		if layout then
			ns.Log("state", ("edit mode layout read from systems (version %d)"):format(version))
			return layout
		end
	end
	ns.Log("state", "edit mode layout: the game couldn't read the systems")
end

local function Copy(source)
	if type(source) ~= "table" then return source end
	local result = {}
	for k, v in pairs(source) do result[k] = Copy(v) end
	return result
end

-- The layout ours with a design are made on (a copy, safe to change): the
-- player's own, the one named (ns.ResetLayouts: the one they go back to),
-- else the one on now, or, on one of ours, the one before a profile
-- switched to it (chardb.layoutOwn). Never one of ours: Modern then.
-- Second: whether it's a game preset (presetOnly rows apply). building: the
-- one of ours being made, when it may be made on another of ours (the Follow
-- HUD, on whatever layout the player's on: Retail Inspired too), never itself.
local function OwnBase(name, building)
	local info = C_EditMode.GetLayouts()
	local function Usable(layoutName)
		return layoutName and (not ns.EDIT_MODE_LAYOUTS[layoutName] or (building and layoutName ~= building))
	end
	local want = name or ActiveName(info)
	if not Usable(want) then want = ns.chardb and ns.chardb.layoutOwn end
	if Usable(want) then
		for _, layout in ipairs(info.layouts) do
			if Named(layout) == want then return Copy(layout), false, want end
		end
		for _, preset in ipairs(Presets()) do
			if preset.layoutName == want then return preset, true, want end
		end
	end
	local modern = Presets()[1]
	return modern, true, modern and modern.layoutName
end

-- A design's changes made on a layout (OwnBase's). A system it moves that the
-- layout hasn't got (one saved before the game added it) taken from Modern.
local function ApplyDesign(layout, design, onPreset)
	layout.systems = layout.systems or {}
	local modern
	for _, saved in ipairs(design) do
		local there = false
		for _, system in ipairs(layout.systems) do
			if system.system == saved[1] and system.systemIndex == saved[2] then there = true break end
		end
		if not there then
			modern = modern or Presets()[1] or {}
			for _, system in ipairs(modern.systems or {}) do
				if system.system == saved[1] and system.systemIndex == saved[2] then
					layout.systems[#layout.systems + 1] = Copy(system)
					break
				end
			end
		end
	end
	local found = {}
	for _, system in ipairs(layout.systems) do
		for i, saved in ipairs(design) do
			if (onPreset or not saved.presetOnly)
				and system.system == saved[1] and system.systemIndex == saved[2] then
				found[i] = true
				if saved[3] then
					system.isInDefaultPosition = false
					system.anchorInfo = { point = saved[3], relativeTo = saved[4], relativePoint = saved[5],
						offsetX = saved[6], offsetY = saved[7] }
				end
				for _, setting in ipairs(system.settings or {}) do
					local value = saved[8] and saved[8][setting.setting]
					if value then setting.value = value end
				end
			end
		end
	end
	for i, saved in ipairs(design) do
		if not found[i] and (onPreset or not saved.presetOnly) then
			ns.Log("state", ("edit mode layout: system %s index %s not in the preset"):format(
				tostring(saved[1]), tostring(saved[2])))
		end
	end
end

-- /cine debug layout: what the game says about Edit Mode and the personal
-- resource display, for Personal Resource Centered (Forever's designed).
function ns.DescribeLayouts()
	if not (C_EditMode and C_EditMode.GetLayouts) then ns.Print("no Edit Mode here") return end
	local info = C_EditMode.GetLayouts()
	local names = {}
	for _, layout in ipairs(info.layouts) do names[#names + 1] = Named(layout) end
	ns.Print(("client %s, on %s, saved: %s; in combat %s, Edit Mode open %s"):format(ns.CLIENT,
		tostring(ActiveName(info)), table.concat(names, ", "), tostring(InCombatLockdown()),
		tostring(_G.EditModeManagerFrame and _G.EditModeManagerFrame:IsShown())))
	local keys = {}
	for key, value in pairs(Enum.EditModeSystem or {}) do
		if type(key) == "string" and key:find("Personal") then keys[#keys + 1] = key .. "=" .. tostring(value) end
	end
	ns.Print(("PRD system: %s (enum: %s); profile layout: %s"):format(tostring(PRD_SYSTEM),
		#keys > 0 and table.concat(keys, ", ") or "none", tostring(ns.db and ns.db.editModeLayout)))
	local function Describe(label, layout)
		if not layout then ns.Print("  " .. label .. ": not there") return end
		local systems = {}
		for _, system in ipairs(layout.systems or {}) do
			systems[#systems + 1] = tostring(system.system)
			if system.system == PRD_SYSTEM then
				local a = system.anchorInfo or {}
				ns.Print(("  %s: PRD index %s, default spot %s, %s %s %s %s %s"):format(label,
					tostring(system.systemIndex), tostring(system.isInDefaultPosition), tostring(a.point),
					tostring(a.relativeTo), tostring(a.relativePoint), tostring(a.offsetX), tostring(a.offsetY)))
				return
			end
		end
		ns.Print(("  %s: no PRD system; has %s"):format(label, table.concat(systems, " ")))
	end
	Describe("Modern preset", Presets()[1])
	local _, index = FindLayout("Personal Resource Centered")
	Describe("Personal Resource Centered", index and info.layouts[index])
	local frame = _G.PersonalResourceDisplayFrame
	if frame then
		local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
		local relName = ok and relativeTo and relativeTo.GetName and relativeTo:GetName()
		ns.Print(("  PersonalResourceDisplayFrame: shown %s, %s"):format(tostring(frame:IsShown()),
			ok and ("%s %s %s %s %s"):format(tostring(point), tostring(relName or relativeTo),
				tostring(relativePoint), tostring(x), tostring(y)) or "point unreadable"))
		ns.Print(("  system %s, nameplateShowSelf %s, scale %s"):format(tostring(frame.system),
			tostring(GetCVar("nameplateShowSelf")), tostring(frame:GetScale())))
		-- (Edit Mode's own copy of its place: whether the game applied the layout to it)
		local sys = frame.systemInfo
		local a = sys and sys.anchorInfo or {}
		ns.Print(("  its systemInfo: %s, default spot %s, %s %s %s %s %s; isInDefaultPosition %s"):format(
			sys and "yes" or "none", tostring(sys and sys.isInDefaultPosition), tostring(a.point),
			tostring(a.relativeTo), tostring(a.relativePoint), tostring(a.offsetX), tostring(a.offsetY),
			tostring(frame.isInDefaultPosition)))
		local manager = _G.EditModeManagerFrame
		local cached = manager and manager.layoutInfo
		ns.Print(("  Edit Mode's cached layout: %s"):format(cached and tostring(ActiveName(cached)) or "none"))
		for _, entry in ipairs(ns.managed or {}) do
			if entry.frame == frame then
				ns.Print(("  faded entry %s: alpha %s, shrunk %s, saved points %s, parked %s"):format(
					tostring(entry.name or entry.group), tostring(entry.alpha), tostring(entry.shrunk),
					entry.savedPoints and #entry.savedPoints or "none", tostring(ns.IsParked and ns.IsParked(entry))))
			end
		end
	else
		ns.Print("  no PersonalResourceDisplayFrame")
	end
end

-- One of ours as a layout to save. base: the player's layout to make it on
-- (OwnBase; nil: the one on now).
local function BuildLayout(name, base)
	local def = ns.EDIT_MODE_LAYOUTS[name]
	if not def then return nil end
	local layout
	if def.export then
		layout = C_EditMode.ConvertStringToLayoutInfo(def.export)
	elseif def.systems then
		layout = ExportFromSystems(def.systems)
	else
		local onPreset, baseName
		-- (def.base: the layout it's made on, when it says, as the Follow HUD's.)
		layout, onPreset, baseName = OwnBase(base or (def.base and def.base()), def.base and name or nil)
		if layout then
			ApplyDesign(layout, DesignOf(def) or {}, onPreset)
			ns.Log("state", ("edit mode layout %s made on %s"):format(name, tostring(baseName)))
		end
	end
	if not layout then return nil end
	layout.layoutName, layout.layoutType = name, AccountType()
	return layout
end

-- /cine debug layoutbase: checks ours made on the player's layouts, saving
-- nothing. For each of ours with a design (this client) on each layout the
-- player has (saved and presets): every frame the design doesn't list kept
-- exactly as in that layout, every one it lists moved, the party frames'
-- raid-style as theirs (on a preset: on), and the game reading the result
-- back. Then ours in Edit Mode now against one made on the layout they'd be
-- made on now (OwnBase). Lines in db.layoutBaseLog (/reload to write it), a
-- verdict per check in chat.
function ns.LayoutBaseTest()
	if not (C_EditMode and C_EditMode.GetLayouts) then ns.Print("layoutbase: no Edit Mode here") return end
	local out, fails = {}, 0
	local function Line(text) out[#out + 1] = text end
	local function Verdict(ok, text)
		if not ok then fails = fails + 1 end
		Line((ok and "PASS " or "FAIL ") .. text)
	end
	local function Key(system) return tostring(system.system) .. ":" .. tostring(system.systemIndex) end
	local function Systems(layout)
		local map = {}
		for _, system in ipairs(layout and layout.systems or {}) do map[Key(system)] = system end
		return map
	end
	local function Anchor(a)
		a = a or {}
		return ("%s %s %s %s %s"):format(tostring(a.point), tostring(a.relativeTo), tostring(a.relativePoint),
			tostring(a.offsetX), tostring(a.offsetY))
	end
	local function Describe(system)
		if not system then return "missing" end
		local settings = {}
		for _, s in ipairs(system.settings or {}) do settings[#settings + 1] = s.setting .. "=" .. tostring(s.value) end
		table.sort(settings)
		return ("default %s, %s / %s, settings %s"):format(tostring(system.isInDefaultPosition),
			Anchor(system.anchorInfo), Anchor(system.anchorInfo2), table.concat(settings, " "))
	end
	local function Setting(system, which)
		for _, s in ipairs(system and system.settings or {}) do
			if s.setting == which then return s.value end
		end
	end
	local info = C_EditMode.GetLayouts()
	local presets = Presets()
	local accounts = 0
	for _, layout in ipairs(info.layouts) do
		if layout.layoutType == AccountType() then accounts = accounts + 1 end
	end
	Line(("client %s, in combat %s, Edit Mode open %s, on %s, layoutOwn %s, profile layout %s, account layouts %d"):format(
		ns.CLIENT, tostring(InCombatLockdown()), tostring(_G.EditModeManagerFrame and _G.EditModeManagerFrame:IsShown()),
		tostring(ActiveName(info)), tostring(ns.chardb and ns.chardb.layoutOwn),
		tostring(ns.db and ns.db.editModeLayout), accounts))
	-- (every layout the player has, not ours: the saved ones first, then the presets)
	local bases = {}
	for _, layout in ipairs(info.layouts) do
		if not ns.EDIT_MODE_LAYOUTS[Named(layout)] then
			bases[#bases + 1] = { name = Named(layout), preset = false, kind = layout.layoutType }
		end
	end
	for _, preset in ipairs(presets) do bases[#bases + 1] = { name = preset.layoutName, preset = true } end
	local ours = {}
	for name, def in pairs(ns.EDIT_MODE_LAYOUTS) do
		-- (On-demand ones too: built here, not saved.)
		if def.design and (not def.client or def.client == ns.CLIENT) then ours[#ours + 1] = name end
	end
	table.sort(ours)
	if #ours == 0 then Line("none of ours is made on the player's layout on this client") end
	for _, name in ipairs(ours) do
		local design = DesignOf(ns.EDIT_MODE_LAYOUTS[name])
		local listed = {}
		for _, row in ipairs(design) do listed[tostring(row[1]) .. ":" .. tostring(row[2])] = row end
		for _, base in ipairs(bases) do
			Line(("-- %s on %s (%s)"):format(name, base.name, base.preset and "preset"
				or ("saved, type " .. tostring(base.kind))))
			local baseLayout, onPreset, baseName = OwnBase(base.name)
			local built = BuildLayout(name, base.name)
			Verdict(baseName == base.name and onPreset == base.preset,
				("base picked: %s (preset %s)"):format(tostring(baseName), tostring(onPreset)))
			if built then
				local before, after = Systems(baseLayout), Systems(built)
				local kept, moved, missing = 0, 0, {}
				for key, system in pairs(before) do
					local row = listed[key]
					local partyOnly = row and row.presetOnly and not onPreset and not row[3]
					if not row or partyOnly then
						if Describe(system) == Describe(after[key]) then
							kept = kept + 1
						else
							Verdict(false, ("%s changed but the design doesn't list it: was %s, now %s"):format(key,
								Describe(system), Describe(after[key])))
						end
					end
				end
				for key, row in pairs(listed) do
					local system = after[key]
					if not system then
						missing[#missing + 1] = key
					elseif row[3] then
						local a = system.anchorInfo or {}
						local ok = a.point == row[3] and a.relativeTo == row[4] and a.relativePoint == row[5]
							and a.offsetX == row[6] and a.offsetY == row[7] and system.isInDefaultPosition == false
						if ok then moved = moved + 1 else
							Verdict(false, ("%s not moved: %s"):format(key, Describe(system)))
						end
					end
				end
				Verdict(true, ("%d of the player's frames kept as they were, %d of ours moved"):format(kept, moved))
				if #missing > 0 then
					table.sort(missing)
					Line("note: on neither this layout nor Modern (no such frame on this client): " .. table.concat(missing, ", "))
				end
				local partyKey = tostring(UNIT_FRAME) .. ":" .. tostring(PARTY)
				local had, has = Setting(before[partyKey], RAID_STYLE_PARTY), Setting(after[partyKey], RAID_STYLE_PARTY)
				-- (on a preset, 1 only where the design turns it on: Retail Inspired, not Personal Resource Centered)
				local want = had
				if onPreset and listed[partyKey] and listed[partyKey].presetOnly then want = 1 end
				Verdict(has == want, ("party frames raid-style: theirs %s, ours %s (want %s)"):format(
					tostring(had), tostring(has), tostring(want)))
				local ok, text = pcall(C_EditMode.ConvertLayoutInfoToString, built)
				local back = ok and text and C_EditMode.ConvertStringToLayoutInfo(text)
				Verdict(back ~= nil and #(back.systems or {}) == #(built.systems or {}),
					("the game reads it back: %s, %s systems (built %d)"):format(tostring(back ~= nil),
						tostring(back and #(back.systems or {})), #(built.systems or {})))
			else
				Verdict(false, "not built")
			end
		end
		-- (ours in Edit Mode now, against one made on the layout it'd be made on now)
		local _, index = FindLayout(name)
		local _, onPreset, nowBase = OwnBase(nil)
		if not index then
			Line(("%s: not in Edit Mode (would be made on %s)"):format(name, tostring(nowBase)))
		else
			local saved, fresh = Systems(info.layouts[index]), Systems(BuildLayout(name))
			local differ = {}
			for key, system in pairs(fresh) do
				if Describe(system) ~= Describe(saved[key]) then differ[#differ + 1] = key end
			end
			table.sort(differ)
			Line(("%s in Edit Mode: %s one made on %s (preset %s)%s"):format(name,
				#differ == 0 and "same as" or ("%d frames differ from"):format(#differ), tostring(nowBase),
				tostring(onPreset), #differ > 0 and (": " .. table.concat(differ, ", ")
				.. " (made before, or changed in Edit Mode; Regenerate makes it on " .. tostring(nowBase) .. ")") or ""))
		end
	end
	Line(fails == 0 and "ALL PASS" or (fails .. " FAIL"))
	if ns.db then ns.db.layoutBaseLog = out end
	for _, text in ipairs(out) do
		if text:find("^FAIL") or text:find("^ALL PASS") or text:find("FAIL$") or text:find("in Edit Mode") then
			ns.Print("layoutbase: " .. text)
		end
	end
	ns.Print(("layoutbase: %d lines saved, /reload to write them"):format(#out))
end

-- Ours made or remade this session (by name). Edit Mode keeps the list it
-- read at login, so switching to one of these moves nothing until a reload
-- (tested on Forever: the PRD stayed in Modern's spot, centred after the
-- reload). Switching to one offers that reload (OfferReload), after which
-- it's switched to again (layoutPending).
local madeNow = {}

local function OfferReload(name)
	ns.chardb.layoutPending = name
	StaticPopup_Show("CINEMATIC_LAYOUT_RELOAD")
end

-- Why layouts can't be changed now (nil: they can).
local function Blocked()
	if not (C_EditMode and C_EditMode.GetLayouts) then return L["this game has no Edit Mode"] end
	if InCombatLockdown() then return L["not in combat"] end
	local manager = _G.EditModeManagerFrame
	if manager and manager:IsShown() then return L["close Edit Mode first"] end
end

-- One of ours made, or brought up to date, and switched to. true: done (a
-- reload applies it everywhere); false, reason: not.
function ns.MakeLayout(name)
	local blocked = Blocked()
	if blocked then return false, blocked end
	local info, index = FindLayout(name)
	local layout = BuildLayout(name)
	if not layout then return false, L["couldn't read the layout"] end
	if index then
		info.layouts[index] = layout
	else
		local count = 0
		for _, other in ipairs(info.layouts) do
			if other.layoutType == AccountType() then count = count + 1 end
		end
		local max = Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType or 5
		if count >= max then
			return false, L["you already have %d account layouts in Edit Mode; delete one there first"]:format(max)
		end
		info.layouts[#info.layouts + 1] = layout
	end
	C_EditMode.SaveLayouts(info)
	local active = IndexOf(C_EditMode.GetLayouts(), name)
	-- (whether the game took it: it can refuse a layout without saying)
	ns.Log("state", ("edit mode layout %s %s: %s"):format(name, index and "updated" or "made",
		active and "there" or "NOT there"))
	if not active then return false, L["the game didn't keep the layout"] end
	madeNow[name] = true
	SetActive(active)
	return true
end

-- Whether a layout's in Edit Mode: "active" (on now), "made", or nil (not there).
function ns.LayoutState(name)
	if not (C_EditMode and C_EditMode.GetLayouts) then return nil end
	local info, index = FindLayout(name)
	if not index then return nil end
	return ActiveName(info) == name and "active" or "made"
end

-- One of ours made again from the code (the Customize panel's Regenerate, the
-- Dev page's buttons), undoing changes made to it in Edit Mode, and switched
-- to. Offers a reload (Edit Mode shows its old copy, or none, until then),
-- after which it's switched to again.
function ns.RegenerateLayout(name)
	local ok, reason = ns.MakeLayout(name)
	if not ok then
		ns.Print(reason)
	else
		OfferReload(name)
	end
	return ok
end

-- Ours still under an old name (ns.LAYOUT_RENAMED) renamed in Edit Mode,
-- unless one's under the new name already. In place, so the numbers
-- SetActiveLayout goes by stay. (Not in combat or with Edit Mode open:
-- the next login then.)
local function RenameOld()
	if Blocked() then return end
	local info = C_EditMode.GetLayouts()
	local taken, renamed = {}, false
	for _, layout in ipairs(info.layouts) do taken[layout.layoutName] = true end
	for _, layout in ipairs(info.layouts) do
		local new = ns.LAYOUT_RENAMED[layout.layoutName]
		if new and not taken[new] then
			ns.Log("state", ("edit mode layout renamed: %s to %s"):format(layout.layoutName, new))
			layout.layoutName, taken[new], renamed = new, true, true
		end
	end
	if renamed then C_EditMode.SaveLayouts(info) end
end

-- On logging in (or a reload), once Edit Mode has its layouts: ours under
-- old names renamed (none made here), then the layout just remade, switched to again;
-- otherwise the profile's, as on switching to it. Edit Mode keeps a layout per character,
-- so one logged into from a character on another profile can be on the
-- wrong one (Retail's on a character whose profile isn't Retail).
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_ENTERING_WORLD")
login:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	if not (C_EditMode and C_EditMode.GetLayouts) or not ns.chardb then return end
	local name = ns.chardb.layoutPending
	name = name and ns.LAYOUT_RENAMED[name] or name
	ns.chardb.layoutPending = nil
	C_Timer.After(1, function()
		RenameOld()
		if not name then
			if ns.ProfileChosen() then ns.ApplyProfileLayout() end
			return
		end
		if InCombatLockdown() or LeftToKeeper() then return end
		local info = C_EditMode.GetLayouts()
		local index = IndexOf(info, name)
		if index and info.activeLayout ~= index then
			SetActive(index)
		end
	end)
end)

-- The profile's Edit Mode layout (db.editModeLayout, from its layout module,
-- or picked on the Profiles page): on switching profile (Profiles.lua) and
-- logging in, Edit Mode goes to it, after the fight if in one; one of ours
-- is made if it isn't there. "": the player's own, the one they were on
-- before a profile switched it (chardb.layoutOwn), back; on one of ours with
-- none saved, the first preset (Modern).
local afterCombat = CreateFrame("Frame")
afterCombat:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	ns.ApplyProfileLayout()
end)
local missingSaid = {}

function ns.ApplyProfileLayout()
	if not (C_EditMode and C_EditMode.GetLayouts) or not ns.db or not ns.chardb then return end
	if InCombatLockdown() then
		afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local manager = _G.EditModeManagerFrame
	if manager and manager:IsShown() then return end -- (the player's choosing there)
	if LeftToKeeper() then return end
	local name = ns.db.editModeLayout or ""
	local info = C_EditMode.GetLayouts()
	if name == "" then
		local own = ns.chardb.layoutOwn
		ns.chardb.layoutOwn = nil -- (back on it: or, gone, nothing to go back to)
		local index = own and IndexOf(info, own)
		if not index and ns.EDIT_MODE_LAYOUTS[ActiveName(info) or ""] then
			own = Presets()[1] and Presets()[1].layoutName
			index = own and IndexOf(info, own)
		end
		if index and info.activeLayout ~= index then
			SetActive(index)
			ns.Log("state", "edit mode layout back to: " .. own)
		end
		return
	end
	name = Target(info, name)
	if not name then return end
	-- (the one to go back to: what's on now, unless a profile's switched it already)
	local current = ActiveName(info)
	if not ns.chardb.layoutOwn and current ~= name then ns.chardb.layoutOwn = current end
	local index = IndexOf(info, name)
	if not index then
		if ns.EDIT_MODE_LAYOUTS[name] then
			local ok, reason = ns.MakeLayout(name)
			if ok then
				OfferReload(name)
			else
				ns.Print(L["couldn't add this profile's Edit Mode layout: %s"]:format(reason))
			end
		elseif not missingSaid[name] then
			missingSaid[name] = true
			ns.Print(L["this profile's Edit Mode layout, %s, isn't there; your layout stays as it is"]:format(name))
		end
		return
	end
	if info.activeLayout ~= index then
		SetActive(index)
		ns.Log("state", "edit mode layout: " .. name)
		if madeNow[name] then OfferReload(name) end
	else
		SyncBars(name) -- (on it already: its bars may still be off)
	end
end

-- Resetting Cinematic (ns.ResetAddon): back on the player's own layout (the
-- one before a profile switched it; on one of ours with none saved, the
-- first preset), and every one of Cinematic's own layouts deleted, as the
-- reset's popup says: a profile that uses one makes it again when it's
-- picked. (Till 2026-11-17 they were remade, so a reset before removing
-- the addon still left them all.) Not in combat: false then (and done
-- nothing).
function ns.ResetLayouts()
	if not (C_EditMode and C_EditMode.GetLayouts) or not ns.chardb then return true end
	if InCombatLockdown() then return false end
	local info = C_EditMode.GetLayouts()
	local own = ns.chardb.layoutOwn
	local active = ActiveName(info)
	if KeptBy() then
		own = nil -- (its addon's layout stays on)
	end
	if own and IndexOf(info, own) then
		active = own
	elseif active and ns.EDIT_MODE_LAYOUTS[active] then
		active = Presets()[1] and Presets()[1].layoutName
	end
	ns.chardb.layoutOwn = nil
	local kept, removed = {}, 0
	for _, layout in ipairs(info.layouts) do
		if ns.EDIT_MODE_LAYOUTS[Named(layout)] then
			removed = removed + 1
		else
			kept[#kept + 1] = layout
		end
	end
	if removed > 0 then
		info.layouts = kept
		info.activeLayout = (active and IndexOf(info, active)) or 1
		if ns.UnshrinkForLayout then ns.UnshrinkForLayout() end
		C_EditMode.SaveLayouts(info)
		ns.Log("state", ("reset: %d edit mode layout(s) deleted, on %s"):format(removed, tostring(active)))
	end
	local index = active and IndexOf(C_EditMode.GetLayouts(), active)
	if index and C_EditMode.GetLayouts().activeLayout ~= index then SetActive(index) end
	SyncBars(active)
	return true
end

-- Whether ns.ApplyProfileLayout would switch Edit Mode's layout now (one of
-- ours not made yet counts: it's made and switched to).
function ns.LayoutWouldChange()
	if not (C_EditMode and C_EditMode.GetLayouts) or not ns.db or not ns.chardb or InCombatLockdown() then
		return false
	end
	local manager = _G.EditModeManagerFrame
	if manager and manager:IsShown() or KeptBy() then return false end
	local name = ns.db.editModeLayout or ""
	local info = C_EditMode.GetLayouts()
	if name == "" then
		name = ns.chardb.layoutOwn
		if not (name and IndexOf(info, name)) and ns.EDIT_MODE_LAYOUTS[ActiveName(info) or ""] then
			name = Presets()[1] and Presets()[1].layoutName
		end
	else
		name = Target(info, name)
	end
	if not name then return false end
	local index = IndexOf(info, name)
	if not index then return ns.EDIT_MODE_LAYOUTS[name] ~= nil end
	return info.activeLayout ~= index
end

-- On switching profile: a layout change waits for the UI to fade out first
-- (Core.lua: up to LAYOUT_FADE_MAX), so the frames aren't seen moving; then
-- the profile's preview, if it has one (ns.PreviewProfile). Mid-fight, or
-- no change: as it is.
local LAYOUT_FADE_MAX = 2.5
function ns.SwitchProfileLayout()
	if ns.LayoutWouldChange() then
		ns.layoutFadeUntil = GetTime() + LAYOUT_FADE_MAX
	else
		ns.ApplyProfileLayout()
	end
end

-- (Core.lua, each tick while fading for it: once everything's faded, out of
-- time, or a fight starts.)
function ns.FinishLayoutFade()
	ns.layoutFadeUntil = nil
	ns.ApplyProfileLayout()
	local pending = ns.pendingPreview
	ns.pendingPreview = nil
	if pending then ns.PreviewProfile(pending) end
end

-- Leaving Edit Mode on another layout than the profile's: the profile takes
-- it (a profile that leaves the layout alone stays so; one on the game's
-- own stays so while it's a preset), so logging in, or switching back to the
-- profile, puts the player's own pick back.
-- On "Your own" (""): a layout of the player's stays theirs, nothing to save;
-- one of ours picked there is the profile's from then on. (Not taken, the
-- next login saw one of ours with nothing to go back to and switched to
-- Modern: "Edit Mode keeps resetting to Modern", a player's report 2026-11-14.)
local function AdoptLayout()
	if not ns.db or not ns.chardb or not ns.ProfileChosen() or KeptBy() then return end
	local want = ns.db.editModeLayout or ""
	local info = C_EditMode.GetLayouts()
	local active = ActiveName(info)
	if not active then return end
	if want == "" then
		if not ns.EDIT_MODE_LAYOUTS[active] then return end
	elseif active == Target(info, want) then
		return
	end
	if want == ns.LAYOUT_PRESET and info.activeLayout <= #Presets() then return end
	ns.db.editModeLayout = active
	ns.chardb.layoutOwn = nil -- (the player's pick now: nothing to go back to)
	SyncBars(active)
	ns.Print(L["the %s profile now uses the Edit Mode layout %s"]:format(
		ns.ProfileLabel(ns.ActiveProfile()), active))
	ns.Log("state", "edit mode layout picked in edit mode: " .. active)
	if ns.RefreshOptions then ns.RefreshOptions() end
end
if _G.EditModeManagerFrame and C_EditMode and C_EditMode.GetLayouts then
	_G.EditModeManagerFrame:HookScript("OnHide", AdoptLayout)
end

-- Bar 1's page arrows (up/down): Classic Era (1.15.9) puts them on its right,
-- WoW Forever on its left. Moved to the left whenever the game puts them on
-- the right. (Not in combat if the bar's protected; pcall: an anchor can be
-- secret on Forever.)
do
	local bar = not ns.isRetail and _G.MainActionBar
	local arrows = bar and bar.ActionBarPageNumber
	if arrows then
		local moving
		local function OnRight()
			local _, relativeTo, relativePoint = arrows:GetPoint()
			return relativeTo == bar and relativePoint == "BOTTOMRIGHT"
		end
		local function ToLeft()
			if moving or (InCombatLockdown() and arrows:IsProtected()) then return end
			local ok, right = pcall(OnRight)
			if not (ok and right) then return end
			local _, _, _, x, y = arrows:GetPoint()
			moving = true
			arrows:ClearAllPoints()
			arrows:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -(x or 0), y or 0)
			moving = false
		end
		hooksecurefunc(arrows, "SetPoint", ToLeft)
		ToLeft()
	end
end

ns.OnLanguage(function()
	StaticPopupDialogs.CINEMATIC_LAYOUT_RELOAD = {
		text = L["Edit Mode keeps its old list of layouts until you reload, and saving there before then " ..
			"would undo this. Reload now?"],
		button1 = RELOADUI or L["Reload"], button2 = L["Later"],
		OnAccept = ReloadUI,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	StaticPopupDialogs.CINEMATIC_BARS_RELOAD = {
		text = L["This Edit Mode layout's action bars come on or off after a reload. Reload now?"],
		button1 = RELOADUI or L["Reload"], button2 = L["Later"],
		OnAccept = ReloadUI,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
end)
