-- The Follow HUD (dev only for now, Forever): the frames that follow you over
-- your shoulder, put on top of whatever profile you're on, piece by piece,
-- changing nothing else: not your styles, nor the rest of your Edit Mode
-- layout (your raid frames, bars, chat... stay as you had them). The
-- Shoulder Cam works without it; it's what makes the HUD slide with you.
--
-- Pieces (picks, by key):
--   layout pieces (Layouts.lua, FOLLOW_HUD_PIECES): stack, sizes, portraits.
--     Any of them: a layout called "Follow HUD", made on a copy of the one
--     you're on (chardb.followHudBase), and the profile switched to it.
--   setting pieces (ProfileModules.lua, follow-*): SETTING_PIECES below.
--
-- ns.FollowHudSetUp(picks): what each picked piece changes written over the
-- live settings, what was there kept first (the profile's followHud.undo),
-- so ns.FollowHudUndo puts it back: each setting still as the Follow HUD left
-- it, that is (one you've changed since stays yours). Setting up again takes
-- the last one off first, so undo always goes back to before the first.
-- ns.FollowHudUpdate: the layout made again on its base (picking up changes
-- you've made to your own layout since). Edit Mode only takes a layout made
-- this session after a reload, so both offer one (Layouts.lua).

local _, ns = ...
local L = ns.L

local LAYOUT_NAME = "Follow HUD"

-- The setting pieces, in the order they're offered. module: its module, or
-- one by what's at the root (picks.root: "prd", the personal resource
-- display, or "player", the player frame; a root not listed: none, and the
-- piece isn't offered). on: picked to start with.
local SETTING_PIECES = {
	{ key = "prdOn", module = { prd = "follow-prd-on" }, on = true },
	{ key = "fights", module = { prd = "follow-fights", player = "follow-fights-player" }, on = true },
	{ key = "enemy", module = { prd = "follow-enemy", player = "follow-enemy-player" }, on = true },
	{ key = "noPortrait", module = { prd = "follow-no-portrait" }, on = false },
	{ key = "frames", module = "follow-frames", on = true },
}
ns.FOLLOW_HUD_SETTING_PIECES = SETTING_PIECES
-- The layout pieces picked to start with (the rest off).
local LAYOUT_ON = { stack = true, sizes = true, portraits = false }

local function RootOf(picks) return picks and picks.root == "player" and "player" or "prd" end

-- A setting piece's module key with this root (nil: not with it).
local function PieceModule(piece, root)
	if type(piece.module) == "table" then return piece.module[root] end
	return piece.module
end

-- The picks to start with: every piece, on or off, and the PRD at the root.
function ns.FollowHudDefaultPicks()
	local picks = { root = "prd" }
	for _, piece in ipairs(ns.FOLLOW_HUD_PIECE_ORDER) do picks[piece] = LAYOUT_ON[piece] or false end
	for _, piece in ipairs(SETTING_PIECES) do picks[piece.key] = piece.on end
	return picks
end

local function Copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = Copy(v) end
	return out
end

local function Same(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	return ns.SerialValue(a) == ns.SerialValue(b)
end

-- A setting, or a list's row, as it is now.
local function Read(key, row)
	local value = ns.db[key]
	if row == nil then return value end
	if type(value) ~= "table" then return nil end
	return value[row] -- (not "and value[row] or nil": a row that's false must stay false)
end

local function Write(key, row, value)
	if row == nil then
		ns.db[key] = Copy(value)
	else
		if type(ns.db[key]) ~= "table" then ns.db[key] = {} end
		ns.db[key][row] = Copy(value)
	end
end

local function AnyLayoutPiece(picks)
	for _, piece in ipairs(ns.FOLLOW_HUD_PIECE_ORDER) do
		if picks[piece] then return true end
	end
	return false
end

-- Puts back what an undo list kept, latest first, where the setting's still
-- as the Follow HUD left it. Returns how many went back, and how many were
-- left as you've changed them since.
local function Restore(undo)
	local back, kept = 0, 0
	for i = #undo, 1, -1 do
		local entry = undo[i]
		if Same(Read(entry.key, entry.row), entry.new) then
			Write(entry.key, entry.row, entry.old)
			back = back + 1
		else
			kept = kept + 1
		end
	end
	return back, kept
end

-- Why it can't be set up or taken off now (nil: it can).
local function Blocked()
	if not ns.db then return L["not loaded yet"] end
	if InCombatLockdown() then return L["not in combat"] end
	local manager = _G.EditModeManagerFrame
	if manager and manager:IsShown() then return L["close Edit Mode first"] end
end

-- Whether it's set up on this profile: its picks, or nil.
function ns.FollowHudPicks()
	local saved = ns.db and ns.db.followHud
	return saved and saved.picks or nil
end

-- picks (nil: the ones to start with). true, or false and why not.
function ns.FollowHudSetUp(picks)
	local blocked = Blocked()
	if blocked then return false, blocked end
	picks = Copy(picks or ns.FollowHudDefaultPicks())
	local saved = ns.db.followHud
	if saved and saved.undo then Restore(saved.undo) end
	local undo, seen = {}, {}
	local function Set(key, row, value)
		local where = key .. "\0" .. tostring(row)
		-- (Written twice: what was there first kept, the last one as what it set.)
		if seen[where] then
			undo[seen[where]].new = Copy(value)
		else
			undo[#undo + 1] = { key = key, row = row, old = Copy(Read(key, row)), new = Copy(value) }
			seen[where] = #undo
		end
		Write(key, row, value)
	end
	local root = RootOf(picks)
	picks.root = root
	local applied = { root }
	for _, piece in ipairs(SETTING_PIECES) do
		local key = picks[piece.key] and PieceModule(piece, root)
		local module = key and ns.GetModule(key)
		if module and not (module.client and module.client ~= ns.CLIENT) then
			module.apply(function(key, value)
				if type(value) == "table" and key ~= "hoverGroups" then
					for row, rowValue in pairs(value) do Set(key, row, rowValue) end
				else
					Set(key, nil, value)
				end
			end, ns.CLIENT)
			applied[#applied + 1] = piece.key
		end
	end
	local withLayout = AnyLayoutPiece(picks) and ns.EDIT_MODE_LAYOUTS[LAYOUT_NAME] ~= nil
	if withLayout then
		Set("editModeLayout", nil, LAYOUT_NAME)
		-- (Made on the layout you're on now; on the Follow HUD already, on the one it was made on.)
		local active = ns.ActiveLayoutName()
		if active and active ~= LAYOUT_NAME then
			ns.chardb.followHudBase = active
			-- (The one to go back to, as a profile's switch keeps it: yours, not one of ours.)
			if not ns.chardb.layoutOwn and not ns.EDIT_MODE_LAYOUTS[active] then ns.chardb.layoutOwn = active end
		end
		applied[#applied + 1] = "layout"
	end
	ns.db.followHud = { picks = picks, undo = undo }
	ns.SaveProfile()
	local made, reason = true, nil
	if withLayout then
		made = ns.RegenerateLayout(LAYOUT_NAME)
		if not made then reason = L["couldn't make the Follow HUD layout"] end
	end
	ns.SettingsChanged()
	ns.Log("state", ("follow hud: set up on %s (%s), %d settings kept to undo, layout on %s"):format(
		ns.ActiveProfile(), table.concat(applied, ", "), #undo,
		withLayout and tostring(ns.chardb.followHudBase) or "none"))
	return made, reason
end

-- Takes it off this profile. true, or false and why not.
function ns.FollowHudUndo()
	local blocked = Blocked()
	if blocked then return false, blocked end
	local saved = ns.db.followHud
	if not (saved and saved.undo) then return false, L["the Follow HUD isn't set up on this profile"] end
	local back, kept = Restore(saved.undo)
	ns.db.followHud = nil
	ns.SaveProfile()
	-- (The layout's setting back as it was: Edit Mode goes back with it.)
	ns.SettingsChanged()
	ns.Log("state", ("follow hud: taken off %s, %d settings back, %d left as changed since"):format(
		ns.ActiveProfile(), back, kept))
	return true, nil, kept
end

-- Its layout made again on the one it was made on. true, or false and why not.
function ns.FollowHudUpdate()
	local blocked = Blocked()
	if blocked then return false, blocked end
	local picks = ns.FollowHudPicks()
	if not (picks and AnyLayoutPiece(picks)) then return false, L["the Follow HUD has no layout on this profile"] end
	local made = ns.RegenerateLayout(LAYOUT_NAME)
	ns.Log("state", ("follow hud: layout made again on %s: %s"):format(tostring(ns.chardb.followHudBase),
		tostring(made)))
	return made, not made and L["couldn't make the Follow HUD layout"] or nil
end

-- The set-up section at the top of the Shoulder Cam page's Follow HUD tab (dev
-- only for now): where it stands beside its header, a row of buttons (Set Up,
-- Undo, Update Layout, Change pieces, each only while it can be used), and the
-- pieces under them: what's at the root as a dropdown, the rest as ticks in two
-- columns. Set up, the pieces fold away (Change pieces opens them), so the tab
-- fits without scrolling. The ticks start as the profile's set-up has them, or
-- the ones to start with; ticking only changes what Set Up puts on.
-- (No ticks for the PRD's own switch and Frames follow you: Set Up always puts
-- those on where they apply, AUTO_PIECES.)
local AUTO_PIECES = { prdOn = true, frames = true }
local PIECE_TEXT = {
	stack = { "Center stack", "Your health and power (picked above) at the bottom middle, with the cast bar, " ..
		"Cooldown Manager and swing timers, so they slide with you as one. Makes an Edit Mode layout called " ..
		"Follow HUD from the one you're on: everything else in it stays as you had it." },
	sizes = { "Same width", "The Personal Resource Display, cast bar and swing timers made one width. Off: your " ..
		"own sizes stay." },
	portraits = { "Portraits each side", "Your player and target frames each side of the stack (with the player " ..
		"frame picked above, the target frame alone). They don't slide with you: the game locks them in fights." },
	prdOn = { "Personal Resource Display on", "Turns on the game's Personal Resource Display, the stack's root." },
	fights = { "Up in fights", "Your health and power (picked above) come up in fights, and stay up while your " ..
		"health or power isn't full with the player frame picked." },
	enemy = { "Up with an enemy targeted", "Your health and power (picked above) come up with an enemy targeted." },
	noPortrait = { "Hide portrait while it's up", "Your portrait stays down in fights and with an enemy targeted, " ..
		"and the Personal Resource Display stays up while your health or power isn't full." },
}

function ns.BuildFollowHudSetup(parent, stack, kit)
	if not ns.isDev then return end
	local wanted, wantedFor
	local editing -- (Change pieces: the pieces open while it's set up)
	local function Wanted()
		local profile = ns.ActiveProfile()
		if wantedFor ~= profile then
			wanted, wantedFor, editing = Copy(ns.FollowHudPicks() or ns.FollowHudDefaultPicks()), profile, false
		end
		return wanted
	end
	-- (Its header with a "?" holding what it does, and where it stands beside them.)
	local header = stack:Header(parent, L["Set Up"])
	stack:Help(parent, L["Puts the frames that follow you on this profile; Undo takes them off again."])
	local status = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetJustifyH("LEFT")
	status:SetPoint("LEFT", header, "RIGHT", 32, 0)

	-- (The buttons on one row.)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(1, 24)
	stack:Add(row, "label")
	local pieces -- (the box the pieces sit in, below)
	local function Button(label, tip, onClick)
		local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		button:SetSize(122, 22)
		button:SetText(label)
		if ns.SkinButton then ns.SkinButton(button) end
		kit.Tooltip(button, tip)
		button:SetScript("OnClick", function()
			local ok, reason, kept = onClick()
			if not ok then
				ns.Print(L["Follow HUD: %s"]:format(tostring(reason)))
			elseif kept and kept > 0 then
				ns.Print(L["Follow HUD taken off; %d settings you've changed since are left as you have them."]:format(kept))
			end
			wantedFor = nil -- (the ticks as it's set up now, folded away again)
			kit.Refresh()
		end)
		return button
	end
	local setUp = Button(L["Set Up"], L["Puts the ticked pieces on this profile; layout pieces need a reload."],
		function()
			local picks = Wanted()
			for key in pairs(AUTO_PIECES) do picks[key] = true end
			return ns.FollowHudSetUp(picks)
		end)
	setUp:SetPoint("LEFT", row, "LEFT", 0, 0)
	local undo = Button(L["Undo"], L["Takes the Follow HUD off this profile and puts your settings back."], ns.FollowHudUndo)
	undo:SetPoint("LEFT", setUp, "RIGHT", 6, 0)
	local update = Button(L["Update Layout"], L["Rebuilds the Follow HUD layout, losing any Edit Mode changes made to it."], ns.FollowHudUpdate)
	update:SetPoint("LEFT", undo, "RIGHT", 6, 0)
	local change = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	change:SetSize(122, 22)
	if ns.SkinButton then ns.SkinButton(change) end
	kit.Tooltip(change, L["Shows the pieces you can pick from."])
	change:SetScript("OnClick", function()
		Wanted()
		editing = not editing
		kit.Refresh()
	end)

	-- The pieces: what's at the root (a dropdown), then the rest in two columns
	-- (what goes in the layout on the left, when it comes up on the right).
	pieces = CreateFrame("Frame", nil, parent)
	pieces:SetSize(1, 1)
	stack:Add(pieces, "label")
	local rootLabel = kit.Label(pieces, "GameFontHighlight", L["Your health and power"])
	rootLabel:SetPoint("TOPLEFT", pieces, "TOPLEFT", 0, -5)
	local ROOT_TEXT = {
		prd = { "Personal Resource Display", "Your Personal Resource Display at the bottom middle, under you, " ..
			"sliding with you as the rest do." },
		player = { "Player frame", "Your player frame at the bottom middle, under the rest. It stays put while " ..
			"they slide over to you: the game locks it in fights, so it can't follow you." },
	}
	local choices = {}
	for _, root in ipairs(ns.FOLLOW_HUD_ROOTS) do
		choices[#choices + 1] = { value = root, text = L[ROOT_TEXT[root][1]], tip = L[ROOT_TEXT[root][2]] }
	end
	local dropdown = kit.Dropdown(pieces, {
		get = function() return RootOf(Wanted()) end,
		set = function(value) Wanted().root = value end, -- (Dropdown refreshes: the root's own pieces hide or come back)
	}, choices, 220)
	if dropdown then dropdown:SetPoint("LEFT", rootLabel, "LEFT", 170, 0) end
	local pieceOf = {}
	for _, piece in ipairs(SETTING_PIECES) do pieceOf[piece.key] = piece end
	local columns = { {}, {} }
	for _, piece in ipairs(ns.FOLLOW_HUD_PIECE_ORDER) do table.insert(columns[1], piece) end
	for _, piece in ipairs(SETTING_PIECES) do
		if not AUTO_PIECES[piece.key] then table.insert(columns[2], piece.key) end
	end
	local ROW_H, COLUMN_X, TOP = 28, 280, -32
	local rows = 0
	for c, column in ipairs(columns) do
		for r, piece in ipairs(column) do
			local text = PIECE_TEXT[piece]
			local check = kit.Check(pieces, {
				noSettingId = true, -- (a pick for Set Up, not saved: no setting for /cine find)
				get = function() return Wanted()[piece] and true or false end,
				set = function(value) Wanted()[piece] = value end,
			}, L[text[1]], L[text[2]])
			check:SetPoint("TOPLEFT", pieces, "TOPLEFT", -2 + (c - 1) * COLUMN_X, TOP - (r - 1) * ROW_H)
			-- (A piece with nothing to do with this root hidden, an empty cell: the PRD's own with the player frame.)
			if pieceOf[piece] then
				local refresh = check.Refresh
				check.Refresh = function(self)
					refresh(self)
					self:SetShown(PieceModule(pieceOf[piece], RootOf(Wanted())) ~= nil)
				end
			end
			rows = math.max(rows, r)
		end
	end
	local OPEN_H = -TOP + rows * ROW_H - 4

	row.Refresh = function()
		local picks = ns.FollowHudPicks()
		Wanted() -- (a new profile: folded, its own ticks)
		local withLayout = picks and AnyLayoutPiece(picks)
		setUp:SetText(picks and L["Set Up Again"] or L["Set Up"])
		-- (Hidden while it can't be used: nothing to take off, remake or open.)
		undo:SetShown(picks ~= nil)
		update:SetShown(withLayout and true or false)
		change:SetShown(picks ~= nil)
		change:SetText(editing and L["Hide Pieces"] or L["Change Pieces"])
		change:ClearAllPoints()
		change:SetPoint("LEFT", withLayout and update or undo, "RIGHT", 6, 0)
		-- (Not set up: the pieces always open, there's nothing else to do here.)
		local open = picks == nil or editing
		if pieces:IsShown() ~= open then
			pieces:SetShown(open)
			pieces:SetHeight(open and OPEN_H or 1)
			if kit.FitContentHeight then kit.FitContentHeight(parent:GetParent()) end
		end
		if not picks then
			status:SetText(L["Not set up on this profile."])
		elseif withLayout then
			status:SetText(L["Set up, with the layout made on %s."]:format(
				tostring(ns.chardb and ns.chardb.followHudBase or "?")))
		else
			status:SetText(L["Set up, without a layout of its own."])
		end
	end
	kit.AddControl(row)
	pieces:SetHeight(OPEN_H)
	row:Refresh()
	-- (The frames' own settings carry on under a header of their own.)
	stack:Header(parent, L["Frames"])
end

-- /cine debug followhud [setup|undo|update]: its state, with what's around
-- it (the layout, the PRD and the settings it changed), or one of those done.
local function Say(text) ns.Print("follow hud: " .. text) end
function ns.FollowHudDebug(what)
	if what == "setup" or what == "undo" or what == "update" then
		local fn = (what == "setup" and ns.FollowHudSetUp) or (what == "undo" and ns.FollowHudUndo) or ns.FollowHudUpdate
		local ok, reason, kept = fn()
		Say(what .. ": " .. (ok and "done" or ("not done, " .. tostring(reason)))
			.. (kept and kept > 0 and (", %d left as you changed them"):format(kept) or ""))
	end
	local picks = ns.FollowHudPicks()
	local on = {}
	for key, value in pairs(picks or {}) do if value == true then on[#on + 1] = key end end
	table.sort(on)
	Say(("profile %s, set up %s%s; in combat %s"):format(tostring(ns.ActiveProfile()), tostring(picks ~= nil),
		picks and (" (root %s: %s)"):format(RootOf(picks), table.concat(on, ", ")) or "", tostring(InCombatLockdown())))
	Say(("layout: on %s, Follow HUD %s, made on %s, profile's %s, yours to go back to %s"):format(
		tostring(ns.ActiveLayoutName()), tostring(ns.LayoutState and ns.LayoutState(LAYOUT_NAME)),
		tostring(ns.chardb and ns.chardb.followHudBase), tostring(ns.db.editModeLayout),
		tostring(ns.chardb and ns.chardb.layoutOwn)))
	local prd = _G.PersonalResourceDisplayFrame
	local width = prd and select(2, pcall(prd.GetWidth, prd))
	local cast = _G.PlayerCastingBarFrame
	local castWidth = cast and select(2, pcall(cast.GetWidth, cast))
	Say(("PRD: prdOn %s, nameplateShowSelf %s, shown %s, width %s; cast bar width %s; Shoulder Cam %s, Frames follow you %s"):format(
		tostring(ns.db.prdOn), tostring(GetCVar("nameplateShowSelf")), tostring(prd and prd:IsShown()),
		tostring(width), tostring(castWidth), tostring(ns.db.shoulderCam), tostring(ns.db.shoulderCamFrames)))
	local saved = ns.db.followHud
	for _, entry in ipairs(saved and saved.undo or {}) do
		local now = Read(entry.key, entry.row)
		Say(("  %s%s: was %s, set %s, now %s"):format(entry.key, entry.row ~= nil and ("." .. tostring(entry.row)) or "",
			ns.SerialValue(entry.old), ns.SerialValue(entry.new),
			Same(now, entry.new) and "the same" or ns.SerialValue(now)))
	end
end
