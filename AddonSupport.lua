-- Cinematic: support for other addons. Each one's file (Support/) adds its rows
-- for the Advanced Frames page (plain data: the page lists them installed or
-- not) and any setup code, which only runs once that addon has loaded. So an
-- addon that isn't loaded costs nothing beyond its rows.
local ADDON_NAME, ns = ...

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
ns.ADDON_FRAMES = {}

-- Addons supported with no frames to list: on the Advanced Frames page all
-- the same, with what's done for them (works) in place of the columns. about:
-- the same said at more length, for its tooltip.
ns.ADDON_NOTES = {}
-- (Their descriptions are made before the language is known: see Locales.lua.)
ns.OnLanguage(function()
	ns.TranslateFields(ns.ADDON_FRAMES, "about", "note")
	ns.TranslateFields(ns.ADDON_NOTES, "about", "works")
end)

local setups = {} -- addon name -> setup functions still to run
local supported = {} -- addon name -> true: has a setup (loaded or not)
local started = false -- (Cinematic itself loaded: the setups can run)

function ns.WhenAddonLoads(addon, setup)
	supported[addon] = true
	setups[addon] = setups[addon] or {}
	table.insert(setups[addon], setup)
end

-- Support switched off on the Addon Frames page (db.addonSupportOff, the
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
		ns.Log("support", ("support for %s is switched off (Addon Frames page): its setup didn't run"):format(addon))
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
ns.QUEST_FOCUS_TRACKERS = {}
ns.questFocusTrackerNames = {} -- (fn -> the addon's name, for /cine debug framepass)
function ns.AddQuestFocusTracker(fn, name)
	table.insert(ns.QUEST_FOCUS_TRACKERS, fn)
	ns.questFocusTrackerNames[fn] = name
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
