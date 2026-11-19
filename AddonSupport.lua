-- Cinematic: support for other addons. Each one's file (Support/) adds its rows
-- for the Advanced Frames page (plain data: the page lists them installed or
-- not) and any setup code, which only runs once that addon has loaded. So an
-- addon that isn't loaded costs nothing beyond its rows.
local ADDON_NAME, ns = ...
local L = ns.L

-- Other addons' frames faded out of the box, listed on the Advanced Frames page.
-- Each fades as its own group ("addon:<key>") while its addon is loaded and
-- it isn't switched off (db.addonFrames[key] = false). names: its named
-- frames. about: what they are, for the options page (note: more to say there).
-- patterns: name patterns for top-level frames numbered per window.
-- match(frame): whether an unnamed frame on UIParent is one of its
-- own, for addons that don't name their frames (those can't be added with
-- /cine add, which saves frames by name). short: a shorter label, if needed.
-- suite: listed once, under this name, among the addons not installed.
-- hookAlpha: its frames set their own alpha all the time, so follow it at once
-- (see HookOwnAlpha in Frames.lua). loaded: set once its addon has loaded.
-- shownByDefault: its Always on to start with (left alone till you switch
-- it), for frames there to be read while they're up (Spoken's subtitles).
-- follows: a HUD row key whose ticks (Always too) it takes until set
-- (ns.ROW_FALLBACK), for frames that stood in for a game frame on its row
-- before getting their own (RestedXP's guide and the Quest tracker row).
ns.ADDON_FRAMES = {}
ns.ADDON_SHOWN_BY_DEFAULT = {} -- key -> true, from shownByDefault

-- Addons supported with no frames to list: on the Advanced Frames page all
-- the same, with what's done for them (works) in place of the columns. about:
-- the same said at more length, for its tooltip.
ns.ADDON_NOTES = {}
-- (Their descriptions are made before the language is known: see Locales.lua.)
ns.OnLanguage(function()
	ns.TranslateFields(ns.ADDON_FRAMES, "about", "note")
	ns.TranslateFields(ns.ADDON_NOTES, "about", "works")
end)

-- Rows that held several frames were split into a row per frame (2026-11-12):
-- each new row names the old one (from), and starts with its settings. In
-- settings (the live ones, or a saved profile's), every row list's entry for
-- the old row ("addon:<key>"; addonFrames and addonsSeen by the bare key),
-- copied to each new row without one, the old entry dropped (unless a row
-- still has that key); in Mouseover groups the old row's place taken by the
-- new ones, and a row following it (rowFollow) follows the first. Safe to run
-- again: nothing's left to carry.
function ns.SplitAddonRows(settings)
	if type(settings) ~= "table" then return end
	local split, live = {}, {}
	for _, known in ipairs(ns.ADDON_FRAMES) do
		live[known.key] = true
		if known.from then
			split[known.from] = split[known.from] or {}
			table.insert(split[known.from], known.key)
		end
	end
	for old, keys in pairs(split) do
		local keep = live[old]
		local oldItem = "addon:" .. old
		for listName, list in pairs(settings) do
			if type(list) == "table" and listName ~= "hoverGroups" and listName ~= "profiles" then
				local bare = listName == "addonFrames" or listName == "addonsSeen"
				local from = bare and old or oldItem
				local value = list[from]
				if value ~= nil then
					for _, key in ipairs(keys) do
						local to = bare and key or "addon:" .. key
						if to ~= from and list[to] == nil then list[to] = value end
					end
					if not keep then list[from] = nil end
				end
				if listName == "rowFollow" and not keep then
					for row, followed in pairs(list) do
						if followed == oldItem then list[row] = "addon:" .. keys[1] end
					end
				end
			end
		end
		for _, group in ipairs(type(settings.hoverGroups) == "table" and settings.hoverGroups or {}) do
			local members = type(group) == "table" and group.members
			if type(members) == "table" then
				local at
				for i, member in ipairs(members) do
					if member == oldItem then at = i break end
				end
				if at then
					local has = {}
					for _, member in ipairs(members) do has[member] = true end
					if not keep then table.remove(members, at) else at = at + 1 end
					for _, key in ipairs(keys) do
						if not has["addon:" .. key] then
							table.insert(members, at, "addon:" .. key)
							at = at + 1
						end
					end
				end
			end
		end
	end
end

local setups = {} -- addon name -> setup functions still to run
local supported = {} -- addon name -> true: has a setup (loaded or not)
local started = false -- (Cinematic itself loaded: the setups can run)

function ns.WhenAddonLoads(addon, setup)
	supported[addon] = true
	setups[addon] = setups[addon] or {}
	table.insert(setups[addon], setup)
end

-- Support switched off on the Addons page (db.addonSupportOff, the
-- account's: addon -> true): its setup doesn't run. Read at load, so a
-- change counts after a /reload (a setup that ran can't be taken back).
-- (CinematicDB itself while ns.db isn't set yet: its ADDON_LOADED may come first.)
function ns.AddonSupportOn(addon)
	local db = ns.db or _G.CinematicDB
	local off = type(db) == "table" and db.addonSupportOff
	return not (type(off) == "table" and off[addon])
end

-- Whether the addon has setup code here (so its support can be switched off).
function ns.HasAddonSetup(addon)
	return supported[addon] or false
end

-- Whether Support/ has anything for the addon: rows, a note or a setup.
function ns.IsSupportedAddon(addon)
	if supported[addon] then
		return true
	end
	for _, list in ipairs({ ns.ADDON_FRAMES, ns.ADDON_NOTES }) do
		for _, known in ipairs(list) do
			if known.addon == addon then
				return true
			end
		end
	end
	return false
end

-- Loaded, or ticked on for this character and so loading this session: for
-- pages built as Cinematic loads, before addons later in the alphabet are in.
function ns.AddOnWillLoad(addon)
	if ns.AddOnLoaded(addon) then return true end
	if not ns.AddOnInstalled(addon) then return false end
	local state = C_AddOns and C_AddOns.GetAddOnEnableState or _G.GetAddOnEnableState
	if not state then return false end
	-- (Its arguments the other way round on older clients.)
	local ok, value = pcall(state, addon, UnitName("player"))
	if not ok or type(value) ~= "number" then ok, value = pcall(state, UnitName("player"), addon) end
	return ok and type(value) == "number" and value > 0
end

local function IsLoaded(addon)
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	return isLoaded and isLoaded(addon) and true or false
end

local function OnLoaded(addon)
	for _, known in ipairs(ns.ADDON_FRAMES) do
		if known.addon == addon then
			known.loaded = true
		end
	end
	local list = setups[addon]
	setups[addon] = nil
	if list and not ns.AddonSupportOn(addon) then
		ns.Log("support", ("support for %s is switched off (Addons page): its setup didn't run"):format(addon))
		return
	end
	for _, setup in ipairs(list or {}) do
		local ok, err = pcall(setup)
		if not ok then
			ns.Log("error", ("support for %s: %s"):format(addon, tostring(err)))
		end
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, _, addon)
	if addon == ADDON_NAME then
		-- Addons loaded before this one, now that all of its files are in.
		started = true
		local loaded = {}
		for _, known in ipairs(ns.ADDON_FRAMES) do
			loaded[known.addon] = true
		end
		for name in pairs(setups) do
			loaded[name] = true
		end
		for name in pairs(loaded) do
			if IsLoaded(name) then
				OnLoaded(name)
			end
		end
	elseif started then
		OnLoaded(addon)
	end
end)

-- Helpers for the setups ------------------------------------------------------

-- Quest trackers of other addons that do the Quest tracker page's "Show just
-- that quest" (and "Close the gaps") their own way: each tick the game's
-- tracker does it, fn(othersAlpha, quests, timers, active) runs too (quests:
-- quest ID -> true, the ones a reveal shows; timers: the same for a running
-- timer, or nil; active: just those wanted now). It returns whether it has
-- any of them, and sets ns.questFocusOthersUp while it has anything faded or
-- moved, so it's called again till it's all back (Frames.lua).
-- shown(), if given, says whether that addon's tracker is up now (it keeps
-- its own list of quests, so quest progress reveals for any quest then).
ns.QUEST_FOCUS_TRACKERS = {}
ns.questFocusTrackerNames = {} -- (fn -> the addon's name, for /cine debug framepass)
local trackerShown = {}
function ns.AddQuestFocusTracker(fn, name, shown)
	table.insert(ns.QUEST_FOCUS_TRACKERS, fn)
	ns.questFocusTrackerNames[fn] = name
	if shown then trackerShown[#trackerShown + 1] = shown end
end
function ns.QuestTrackerOfAddonUp()
	for _, shown in ipairs(trackerShown) do
		local ok, up = pcall(shown)
		if ok and up then return true end
	end
	return false
end

-- Parts other addons put on Quest talk's bubble (CinematicQuestTalkBubble),
-- e.g. a voice-over addon's Listen button, for buttons they'd otherwise pin
-- to the game's quest window (parked off the screen while ours is up). Each
-- part is { make = fn(bubble), shown = fn(bubble) }: make runs once, when the
-- bubble is first built; shown each time a screen of ours opens.
ns.QUEST_TALK_PARTS = {}
function ns.AddQuestTalkPart(part)
	table.insert(ns.QUEST_TALK_PARTS, part)
end

-- Features another addon has its own version of: the Addon Conflicts page and
-- window pick whose plays, per feature (Conflicts.lua). Picks, saved for the
-- account in db.conflictPicks by row id ("<addon>:<key>"): "theirs" (the
-- default, and what an unpicked row does: Cinematic's stands aside while
-- theirs is on), "ours" (Cinematic's plays and theirs is hidden at alpha 0
-- while ours is on, its settings left be) or "both".
-- ns.AddConflict(row) lists one: row.key (the feature), addon, label, group
-- ("scenes", "quest" or "style"), about (a line on what it is), theirs (fn:
-- true while the addon's own version is on), ours (fn: true while
-- Cinematic's is; theirs is hidden only then), hide (their frames' global
-- names, or fn returning frames: held at alpha 0 for "ours"), noBoth (one
-- look wins: no Both), styleSwitch (a Style page's switch that stands aside
-- for "theirs": ns.StyleOn), onPick (fn after its pick changes).
ns.CONFLICTS = {}
local conflictById = {}
local PICKS = { theirs = true, ours = true, both = true }
function ns.AddConflict(row)
	row.id = row.addon .. ":" .. row.key
	if conflictById[row.id] then return conflictById[row.id] end
	conflictById[row.id] = row
	table.insert(ns.CONFLICTS, row)
	if ns.OnConflictAdded then ns.OnConflictAdded(row) end
	return row
end

-- A row's pick, and whether the player made it (an unpicked row plays theirs,
-- or its row.default: one that had a pick of its own before, RareScanner's).
function ns.ConflictPick(row)
	local picks = ns.db and ns.db.conflictPicks
	local pick = type(picks) == "table" and picks[row.id]
	if not PICKS[pick] or (pick == "both" and row.noBoth) then
		return row.default or "theirs", false
	end
	return pick, true
end

-- Whether the addon's own version is on now.
function ns.ConflictTheirsOn(row)
	local ok, on = pcall(row.theirs)
	return ok and on and true or false
end

-- The row for a feature whose other addon's version is on now, its pick and
-- that addon, or nil.
function ns.ConflictState(key)
	for _, row in ipairs(ns.CONFLICTS) do
		if row.key == key and ns.ConflictTheirsOn(row) then
			return row, (ns.ConflictPick(row)), row.addon
		end
	end
	return nil
end

-- Whether Cinematic's version of a feature stands aside now: an addon's own
-- is on and its row's pick is theirs.
function ns.ConflictStandsAside(key)
	for _, row in ipairs(ns.CONFLICTS) do
		if row.key == key and ns.ConflictPick(row) == "theirs" and ns.ConflictTheirsOn(row) then
			return row
		end
	end
	return nil
end

-- A Style page's switch standing aside: an addon's own look is on and its
-- row's pick is theirs. (Only the rows for that switch are gone over, listed
-- by switch as rows are added: asked about 400 times a frame through
-- ns.StyleOn while plates came and went turning the camera fast, each going
-- over every conflict row, 2026-11-15. Picks and the addons' own switches
-- are still asked each time: they can change at any moment.)
local rowsBySwitch, rowsListed = {}, 0
function ns.StyleSwitchYielded(switchKey)
	local rows = ns.CONFLICTS
	if rowsListed ~= #rows then
		wipe(rowsBySwitch)
		for _, row in ipairs(rows) do
			if row.styleSwitch then
				rowsBySwitch[row.styleSwitch] = rowsBySwitch[row.styleSwitch] or {}
				table.insert(rowsBySwitch[row.styleSwitch], row)
			end
		end
		rowsListed = #rows
	end
	local list = rowsBySwitch[switchKey]
	if not list then return nil end
	for _, row in ipairs(list) do
		if ns.ConflictPick(row) == "theirs" and ns.ConflictTheirsOn(row) then
			return row
		end
	end
	return nil
end

-- Features gated by a pick (ns.FeatureYieldedTo): "card:<event id>"
-- (Cards.lua), "scene:<trigger key>" (camera scenes: CameraRows.lua),
-- "questObjectGlow" and "hideObjectIcons" (Quest Vision's soft-target
-- settings: Core.lua). fn() returns the addon's name while its version is
-- on; row (ns.AddConflict's fields, its key the feature's unless it shares a
-- row: row.key) lists it on the page.
local featureYields = {}
function ns.AddFeatureYield(feature, fn, row)
	row = row or {}
	row.key = row.key or feature
	row.theirs = row.theirs or fn
	if row.addon then row = ns.AddConflict(row) end
	featureYields[feature] = featureYields[feature] or {}
	table.insert(featureYields[feature], { fn = fn, row = row.id and row or nil })
end

-- The addon whose own version of a feature plays instead of Cinematic's now
-- (on, and its row's pick theirs), and its row; or nil.
function ns.FeatureYieldedTo(feature)
	local list = featureYields[feature]
	if not list then
		return nil
	end
	for _, each in ipairs(list) do
		local ok, who = pcall(each.fn)
		if ok and who and (not each.row or ns.ConflictPick(each.row) == "theirs") then
			return who, each.row
		end
	end
	return nil
end

-- Why a feature stands aside, in words (Cards' reasons, /cine why), or nil.
function ns.FeatureYieldReason(feature)
	local who, row = ns.FeatureYieldedTo(feature)
	if not who then return nil end
	local picked = false
	if row then picked = select(2, ns.ConflictPick(row)) end
	if picked then
		return L["%s shows its own (Addon Conflicts: Theirs)"]:format(who)
	end
	return L["%s shows its own (Addon Conflicts: not picked yet, so Theirs)"]:format(who)
end

-- Its frames standing in for the game's, by Standard Frames row: each row is
-- { row, fade group, frame names... }. They set their own alpha and are its
-- own frames, so they're hooked.
function ns.FadeWithRows(rows)
	for _, row in ipairs(rows) do
		ns.FadeWithRow(row[1], row[2], { unpack(row, 3) }, true, true)
	end
end

-- Its named frames that fade in a group found by scans, not names (the raid
-- frames' Players and Pets): picked up by each scan once they exist. Its own
-- frames, so hooked.
function ns.FadeFoundByName(group, names)
	ns.AddScanner(function()
		for _, name in ipairs(names) do
			local frame = _G[name]
			if type(frame) == "table" and not ns.IsFaded(frame) then
				ns.AddFoundFrame(frame, group, true, true)
			end
		end
	end)
end

-- Nameplate addons drawing plates of their own (see ns.SetPlateAlpha in
-- Effects.lua). Each joins the ones already there, as more than one can be
-- loaded (a whole-UI suite with its nameplates part, and Plater).
-- fn(plate, alpha): alpha nil to let go of the plate.
function ns.AddPlateAlpha(fn)
	local other = ns.addonPlateAlpha
	ns.addonPlateAlpha = other and function(plate, alpha)
		other(plate, alpha)
		fn(plate, alpha)
	end or fn
end

-- fn(plate): true if it keeps the game's unit frame at alpha 0 under its own.
function ns.AddPlateHidden(fn)
	local other = ns.addonPlateHidden
	ns.addonPlateHidden = other and function(plate)
		return other(plate) or fn(plate)
	end or fn
end

-- An addon's own frame on a plate, which sets its own alpha (range and target
-- fading): hooked, so while the plate is faded its alpha is ours times its
-- own, and at full it's left to it again. On the frame: cinematicPlateAlpha,
-- ours while faded (nil at full); cinematicOwnAlpha, the alpha it last set
-- itself (nil when it can't be known: set from a secret value).
do
	local applying = false

	local function Known(value)
		return not (issecretvalue and issecretvalue(value))
	end

	local function Apply(frame)
		applying = true
		frame:SetAlpha((frame.cinematicOwnAlpha or 1) * (frame.cinematicPlateAlpha or 1))
		applying = false
	end

	-- label: what the hook is called on the Profiler page.
	function ns.HookPlateFrame(frame, label)
		if frame.cinematicHooked then
			return
		end
		frame.cinematicHooked = true
		local alpha = frame:GetAlpha()
		frame.cinematicOwnAlpha = Known(alpha) and alpha or nil
		hooksecurefunc(frame, "SetAlpha", ns.Profiled(label, function(self, own)
			if applying then
				return
			end
			self.cinematicOwnAlpha = type(own) == "number" and Known(own) and own or nil
			if self.cinematicPlateAlpha then
				Apply(self)
			end
		end))
		if frame.SetAlphaFromBoolean then
			hooksecurefunc(frame, "SetAlphaFromBoolean", function(self)
				self.cinematicOwnAlpha = nil
				if self.cinematicPlateAlpha then
					Apply(self)
				end
			end)
		end
	end

	-- alpha: the plate's fade, nil or 1 at full (back to its own alpha; one it
	-- can't tell is put right at its next update).
	function ns.SetPlateFrameAlpha(frame, alpha, label)
		alpha = alpha and alpha < 1 and alpha or nil
		if alpha then
			ns.HookPlateFrame(frame, label)
		end
		if frame.cinematicPlateAlpha ~= alpha then
			frame.cinematicPlateAlpha = alpha
			Apply(frame)
		end
	end
end

-- fn(plate) runs on each new plate after the addon's own handler for it (it
-- puts its frames on the plate in that, which runs after ours: Effects), so
-- they get the plate's alpha before they're drawn. Called from the addon's
-- setup: a watcher made then is called after the addon's own.
function ns.AfterPlateAdded(fn)
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	watcher:SetScript("OnEvent", function(_, _, unit)
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
		if type(plate) == "table" and not (plate.IsForbidden and plate:IsForbidden()) then
			fn(plate)
		end
	end)
end

-- A nameplate addon that writes the game's "which plates show" settings
-- itself (at login, after a fight) from code that can't be wrapped like
-- Plater's passes: its writes count as its own passes (ns.OTHERS_CVAR_ADDONS,
-- Core.lua: settings held stay held), and one that changes a setting the
-- Nameplates page's rows decide switches those rows on again after it, as
-- for Plater. folder: its AddOns folder; label: its name, for the log.
do
	local ROW_CVARS = {}
	for _, cvar in ipairs({
		"nameplateShowAll", "nameplateShowEnemies", "nameplateShowEnemyMinions", "nameplateShowEnemyPets",
		"nameplateShowEnemyGuardians", "nameplateShowEnemyTotems", "nameplateShowEnemyMinus",
		"nameplateShowFriends", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNPCs",
		"nameplateShowFriendlyMinions", "nameplateShowFriendlyPets", "nameplateShowFriendlyGuardians",
		"nameplateShowFriendlyTotems", "nameplateShowFriendlyPlayerMinions", "nameplateShowFriendlyPlayerPets",
		"nameplateShowFriendlyPlayerGuardians", "nameplateShowFriendlyPlayerTotems",
	}) do
		ROW_CVARS[cvar:lower()] = true
	end
	local watched = {} -- [folder] = label
	local pending = false
	local hooked = false

	local function OnWrite(name)
		if pending or type(name) ~= "string" or not ROW_CVARS[name:lower()] then
			return
		end
		local stack = (debugstack() or ""):gsub("\\", "/")
		for folder, label in pairs(watched) do
			if stack:find("AddOns/" .. folder .. "/", 1, true) then
				pending = true
				-- (After the rest of its pass: it writes several at once.)
				C_Timer.After(0, function()
					pending = false
					if ns.db and ns.db.handlePlates then
						ns.Log("cvar", label .. " set the game's nameplate settings: Nameplates page's rows switched on again")
						ns.EnsurePlateRows()
					end
				end)
				return
			end
		end
	end

	function ns.FollowOthersPlateWrites(folder, label)
		watched[folder] = label
		ns.OTHERS_CVAR_ADDONS[folder] = true
		if hooked then
			return
		end
		hooked = true
		if C_CVar and C_CVar.SetCVar then
			hooksecurefunc(C_CVar, "SetCVar", ns.Profiled("Nameplate addon SetCVar hook", OnWrite))
		end
		hooksecurefunc("SetCVar", ns.Profiled("Nameplate addon SetCVar hook", OnWrite))
	end
end
