-- Once-only settings updates: each one changes saved settings made by an
-- older version (a setting renamed, split, moved to a new page) and sets its
-- done-flag (ns.db.<name>V1 = true), so it runs once per account. They run at
-- ADDON_LOADED (Core.lua calls ns.RunMigrations), in this order, after the
-- saved settings arrive and before the defaults fill in what's missing.
--
-- They're in steps (moved out of Core.lua's load handler as they were,
-- 2026-11-15) so that no function nears Lua's local and upvalue caps, and so
-- that one that errors stops only its own step: the rest still run, and its
-- update, its flag unset, tries again at the next login. A new update goes at
-- the end of the last step, or in a new step after it.
--
-- Checked outside the game by Tools/offline/migrate-test.lua: a real saved
-- settings file with every done-flag off, compared before and after a change.

local _, ns = ...
-- (Core.lua's, which loads first: the same tables.)
local DEFAULTS = ns.DEFAULTS
local ORBIT_PROFILE_KEYS, ZOOM_PROFILE_KEYS = ns.ORBIT_PROFILE_KEYS, ns.ZOOM_PROFILE_KEYS

local STEPS = {}
-- (Step 1.)
STEPS[#STEPS + 1] = function()
	-- Vitals Vision's reaches: one for all four edges, now the top and
	-- bottom's, with the sides' apart; the sides as they were. (Saved
	-- profiles too; a reach a theme set stays the theme's.)
	local function MigrateReaches(saved)
		local fromTheme = type(saved.lowHealthFromTheme) == "table" and saved.lowHealthFromTheme.values
		for _, key in ipairs({ "lowHealthReach", "lowHealthBloodReach", "lowHealthGameReach" }) do
			if saved[key] ~= nil and saved[key .. "Sides"] == nil then
				saved[key .. "Sides"] = saved[key]
				if fromTheme and fromTheme[key] ~= nil then fromTheme[key .. "Sides"] = fromTheme[key] end
			end
		end
	end
	MigrateReaches(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then MigrateReaches(saved) end
	end
	-- Heal Vision's row has a default rule now ("(dungeon or raid) and not
	-- dead"), and a rule decides instead of its ticks. Ticks of your own
	-- become your rule first, so they still act; just Dungeons and Raids
	-- (the old Heal Vision everywhere module's) take the new default.
	local function MigrateHealVisionTicks(saved)
		local rules = saved.frameRules
		if type(rules) == "table" and rules.healVision ~= nil then return end
		if saved.healVision == true then
			saved.frameRules = type(rules) == "table" and rules or {}
			saved.frameRules.healVision = "always"
			return
		end
		local words, seen, count = {}, {}, 0
		for _, pair in ipairs({ { "healVisionInCombat", "combat" }, { "healVisionCalm", "calm" },
			{ "healVisionTargetEnemy", "enemy" }, { "healVisionTargetFriendly", "friendly" },
			{ "healVisionInWorld", "world" }, { "healVisionInCities", "city" }, { "healVisionInBGs", "bg or arena" },
			{ "healVisionInDungeons", "dungeon" }, { "healVisionInRaids", "raid" }, { "healVisionInParty", "group" },
			{ "healVisionInRaid", "group" } }) do
			if saved[pair[1]] == true then
				count = count + 1
				if not seen[pair[2]] then
					seen[pair[2]] = true
					words[#words + 1] = pair[2]
				end
			end
		end
		if count == 0 or (count == 2 and saved.healVisionInDungeons == true and saved.healVisionInRaids == true) then
			return
		end
		saved.frameRules = type(rules) == "table" and rules or {}
		saved.frameRules.healVision = table.concat(words, " or ")
	end
	MigrateHealVisionTicks(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then
			MigrateHealVisionTicks(saved)
			if type(saved.settings) == "table" then MigrateHealVisionTicks(saved.settings) end
		end
	end
	-- Minimap nodes' old Ping where it is box, untick: now Mark where it
	-- is's Off (ticked takes the new default, our silent mark). Once: the
	-- box is back (the cursor sweep's ping), and unticking it now must not
	-- turn the mark off too.
	local markOnce = not ns.db.minimapNodeMarkV1
	ns.db.minimapNodeMarkV1 = true
	local function MigrateNodeMark(saved)
		if markOnce and saved.minimapNodePing == false and saved.minimapNodeMark == nil then saved.minimapNodeMark = "off" end
		-- (Ping, no sound went: it didn't mute the ping, tested.)
		if saved.minimapNodeMark == "quietping" then saved.minimapNodeMark = "mark" end
	end
	MigrateNodeMark(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then MigrateNodeMark(saved) end
	end
	-- Roll Vision's rules: once one "this quality and up" dropdown, Only items
	-- you can use, Only show the best pick and a party and a raid box; then
	-- (dev copy, never released) one grid of them per quality; now a grid
	-- per group. An old tick left on takes the grids' defaults (epics: every
	-- one, every pick).
	local function MigrateRollQuality(saved)
		local min = tonumber(saved.rollMinQuality)
		for i, row in ipairs({ "Uncommon", "Rare", "Epic", "Legendary" }) do
			for _, group in ipairs({ "Party", "Raid" }) do
				local function Put(rule, value)
					if value ~= nil and saved["roll" .. rule .. group .. row] == nil then
						saved["roll" .. rule .. group .. row] = value
					end
				end
				local show = saved["rollShow" .. row]
				if show == nil and min then show = i + 1 >= min end
				-- (a tick before Show's dropdown: ticked, every pick)
				local now = saved["rollShow" .. group .. row]
				if type(now) == "boolean" then saved["rollShow" .. group .. row] = now and "all" or "off" end
				if show ~= nil then Put("Show", show and "all" or "off") end
				local usable = saved["rollUsable" .. row]
				if usable == nil and saved.rollUsableOnly == false then usable = false end
				Put("Usable", usable)
				local best = saved["rollBest" .. row]
				if best == nil and saved.rollTopPick == false then best = false end
				Put("Best", best)
				Put("Max", tonumber(saved["roll" .. group .. row]) or tonumber(saved["roll" .. group .. "Rows"]))
			end
		end
		-- (Show the counts under each item, once one tick: on, in both.)
		if saved.rollFooter == true and saved.rollFooterParty == nil then
			saved.rollFooterParty, saved.rollFooterRaid = true, true
		end
		-- (Where's two ticks: now the Popup location dropdown.)
		if saved.rollPlace == nil and (saved.rollSeparate or saved.rollBeside) then
			saved.rollPlace = saved.rollSeparate and "separate" or "right"
		end
	end
	MigrateRollQuality(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then
			MigrateRollQuality(saved)
			if type(saved.settings) == "table" then MigrateRollQuality(saved.settings) end
		end
	end
	-- Older settings: one vertical range for up and down, and a separate
	-- narrow behind mode (now behind mode with a 45 degree swing).
	local function MigrateProfile(prefix)
		local pitch = ns.db[prefix .. "Pitch"]
		if pitch ~= nil and ns.db[prefix .. "PitchUp"] == nil then
			ns.db[prefix .. "PitchUp"], ns.db[prefix .. "PitchDown"] = pitch, pitch
		end
		if ns.db[prefix .. "Mode"] == "backnarrow" then
			ns.db[prefix .. "Mode"], ns.db[prefix .. "BackArc"] = "back", 45
		end
	end
	MigrateProfile("taxiOrbit")
	-- Rotation settings used to be shared; start the standing-still profile
	-- from the player's existing (flight) values.
	for _, key in ipairs(ORBIT_PROFILE_KEYS) do
		if ns.db["idleOrbit" .. key] == nil then
			ns.db["idleOrbit" .. key] = ns.db["taxiOrbit" .. key]
		end
	end
	MigrateProfile("idleOrbit")
	-- Zoom settings used to be shared; start the flight ones from the player's values.
	for _, key in ipairs(ZOOM_PROFILE_KEYS) do
		if ns.db["taxiZoom" .. key] == nil then
			ns.db["taxiZoom" .. key] = ns.db["idleZoom" .. key]
		end
	end
	-- The death banner was a tick box before it had styles.
	if ns.db.deathBanner ~= nil then
		if ns.db.deathBanner == false and ns.db.deathBannerStyle == nil then
			ns.db.deathBannerStyle = "none"
		end
		ns.db.deathBanner = nil
	end
	-- An early build had one "keep the other faction's names" option.
	if ns.db.plateEnemyNamesCinematic then
		ns.db.nameKeepOther = true
	end
	ns.db.plateEnemyNamesCinematic = nil
	ns.db.markOther = nil
	-- The main page's Enable Cinematic box is gone (off is the AddOns
	-- list): an off saved before, or left by a demo cut short by a
	-- reload, would have no box to undo it. Loaded means on.
	if ns.db.enabled == false then ns.db.enabled = true end
	-- The AFK camera's "Turn rotation off in" and "Turn zoom off in" (and
	-- before them "Turn camera effects off in") are now its row of the
	-- "Turn off in" grid: off there if either was.
	for _, suffix in ipairs({ "Cities", "Inns", "Dungeons", "Raids", "PvP" }) do
		if ns.db["idleOffIn" .. suffix] == nil then
			local old = ns.db["camOffIn" .. suffix] or ns.db["rotOffIn" .. suffix]
				or ns.db["zoomOffIn" .. suffix]
			if old ~= nil then ns.db["idleOffIn" .. suffix] = old and true or false end
		end
	end
	-- An early walk camera saved other values for these; start from the
	-- current defaults once.
	if not ns.db.walkSettingsV2 then
		for k in pairs(DEFAULTS) do
			if k:find("^walkOrbit.") or k:find("^walkZoom.") or k == "walkInstant" then
				ns.db[k] = nil
			end
		end
		ns.db.walkSettingsV2 = true
	end
	-- Dragging gear out of the bags opening the character window was on for
	-- everyone; where unit values are secret it's off by default now, so turn
	-- it off once there.
	if not ns.db.dragEquipV2 then
		if issecretvalue and ns.db.dragEquipCharacter then ns.db.dragEquipCharacter = nil end
		ns.db.dragEquipV2 = true
	end
	-- The auto-run camera first swung wider; narrow it once, unless changed.
	if not ns.db.runSettingsV2 then
		if ns.db.runOrbitBackArc == 35 then ns.db.runOrbitBackArc = nil end
		if ns.db.runOrbitMinChange == 15 then ns.db.runOrbitMinChange = nil end
		if ns.db.runOrbitPitchUp == 8 then ns.db.runOrbitPitchUp = nil end
		if ns.db.runOrbitPitchDown == 8 then ns.db.runOrbitPitchDown = nil end
		ns.db.runSettingsV2 = true
	end
	-- Standing still first waited 30 sec before the camera started; 60 now, unless changed.
	if not ns.db.stillDelayV2 then
		if ns.db.idleOrbitDelay == 30 then ns.db.idleOrbitDelay = nil end
		ns.db.stillDelayV2 = true
	end
	-- ...and 120 now (the slider up to 300), unless changed.
	if not ns.db.stillDelayV3 then
		if ns.db.idleOrbitDelay == 60 then ns.db.idleOrbitDelay = nil end
		ns.db.stillDelayV3 = true
	end
	-- (Profiles on the game's own look keep the game's names when a main
	-- theme comes: NameThemes.lua. Not a fresh install's, marked done: the
	-- flag below isn't set yet then.)
	if ns.MigrateNameTheme then ns.MigrateNameTheme(not ns.db.plateNameFriendsV2) end
	-- Friendly players' names on faded plates were first in class colours by
	-- default; blue now, as the game's names over heads, so switch them once.
	if not ns.db.plateNameFriendsV2 then
		if ns.db.plateNameFriends == "class" then ns.db.plateNameFriends = nil end
		ns.db.plateNameFriendsV2 = true
	end
	-- Name Style's settings still at their old defaults to "inherit" (the
	-- same look, from the game's), every profile. Once. NameRowLook.lua.
	if ns.MigrateNameInherit then ns.MigrateNameInherit() end
	-- Enemy nameplates were first hidden in fights by default; show them once.
	if not ns.db.plateCombatV2 then
		ns.db.plateCombatMobs = true
		ns.db.plateCombatOther = true
		ns.db.plateCombatV2 = true
	end
	-- "Turn music off on logout" (since removed) was first on by default,
	-- leaving game music switched off outside cinematic mode (and after
	-- removing the addon). Switch game music back on once at login if it did.
	if not ns.db.musicLogoutV1 then
		if ns.db.musicOffOnLogout then
			ns.musicBackOn = true
		end
		ns.db.musicLogoutV1 = true
	end
	ns.db.musicOffOnLogout = nil
	-- "No music while AFK" (Audio page) is now Go AFK's Music column on the
	-- Cameras page, the other way round.
	if ns.db.noMusicWhenAFK == false and ns.db.eventAFKMusic == nil then
		ns.db.eventAFKMusic = true
	end
	-- Stand still with the AFK camera first took Go AFK's music; it has its
	-- own now, so it starts out as Go AFK's was.
	if not ns.db.stillMusicV2 then
		if ns.db.eventStillCamera == "afk" and ns.db.eventAFKMusic == true and ns.db.eventStillMusic == nil then
			ns.db.eventStillMusic = true
		end
		ns.db.stillMusicV2 = true
	end
	-- (The migrations below up to the rows' renaming use the old rows.)
	local OLD_PLATE_KINDS = { "Mobs", "NPCs", "Own", "Other", "Pets", "Totems" }
	local OLD_NAME_KEYS = { "Mobs", "NPCs", "Own", "Other", "Pets", "Minions", "Totems", "Self" }
	-- An unticked Show (now "Out of combat") used to hide a kind in fights
	-- too; its In combat tick, greyed out then, would now show it in them.
	if not ns.db.plateOutOfCombatV1 then
		for _, kind in ipairs(OLD_PLATE_KINDS) do
			if ns.db["plateShow" .. kind] == false then
				ns.db["plateCombat" .. kind] = false
			end
		end
		ns.db.plateOutOfCombatV1 = true
	end
	-- The Nameplates page had an Out of combat column (plateShow<kind>) that
	-- also set the game's own nameplate options. It now only steers plates
	-- in cinematic mode, with a column per place: a kind kept up in
	-- cinematic mode stays kept everywhere, unless Out of combat was off.
	if ns.db.plateShowMobs ~= nil then
		for _, kind in ipairs(OLD_PLATE_KINDS) do
			local kept = (ns.db["plateCinematic" .. kind] and ns.db["plateShow" .. kind] ~= false) and true or false
			ns.db["plateCinematic" .. kind] = kept
			for _, suffix in ipairs({ "Cities", "Inns", "Dungeons", "Raids", "PvP" }) do
				ns.db["plateIn" .. suffix .. kind] = kept
			end
		end
	end
	-- "Hide nameplates in cinematic mode" was a switch of its own; with it
	-- off, every kind now stays up everywhere instead.
	if ns.db.hidePlates == false then
		for _, kind in ipairs(OLD_PLATE_KINDS) do
			ns.db["plateCombat" .. kind], ns.db["plateCinematic" .. kind] = true, true
			for _, suffix in ipairs({ "Cities", "Inns", "Dungeons", "Raids", "PvP" }) do
				ns.db["plateIn" .. suffix .. kind] = true
			end
		end
	end
	ns.db.hidePlates = nil
	-- "Hide names in cinematic mode" likewise: off, every name stays up.
	if ns.db.hideNames == false then
		for _, key in ipairs(OLD_NAME_KEYS) do
			ns.db["nameKeep" .. key] = true
		end
	end
	ns.db.hideNames = nil
	-- Names had one Keep column; a kept name stays kept in fights and everywhere.
	if not ns.db.nameGridV1 then
		for _, key in ipairs(OLD_NAME_KEYS) do
			if ns.db["nameKeep" .. key] then
				ns.db["nameCombat" .. key] = true
				for _, suffix in ipairs({ "Cities", "Inns", "Dungeons", "Raids", "PvP" }) do
					ns.db["nameIn" .. suffix .. key] = true
				end
			end
		end
		ns.db.nameGridV1 = true
	end
	-- The Nameplates page's rows now follow the game's own options. Each
	-- new row is ticked in a column wherever an old row it covers was.
	if not ns.db.plateRowsV1 then
		local function Regroup(prefixes, map, oldKeys)
			for _, prefix in ipairs(prefixes) do
				local new = {}
				for newKey, olds in pairs(map) do
					for _, old in ipairs(olds) do
						new[newKey] = new[newKey] or ns.db[prefix .. old] or nil
					end
				end
				for _, old in ipairs(oldKeys) do
					ns.db[prefix .. old] = nil
				end
				for newKey, value in pairs(new) do
					ns.db[prefix .. newKey] = value
				end
			end
		end
		local function Columns(head, open)
			local list = { head .. "Combat", open }
			for _, suffix in ipairs({ "Cities", "Inns", "Dungeons", "Raids", "PvP" }) do
				list[#list + 1] = head .. "In" .. suffix
			end
			return list
		end
		Regroup(Columns("plate", "plateCinematic"), {
			Enemies = { "Mobs", "Other" }, EnemyMinions = { "Pets", "Totems" }, EnemyMinor = { "Mobs" },
			Friends = { "Own" }, FriendlyMinions = { "Pets", "Totems" }, FriendlyNPCs = { "NPCs" },
		}, OLD_PLATE_KINDS)
		Regroup(Columns("name", "nameKeep"), {
			Self = { "Self" }, NPCs = { "Mobs", "NPCs" }, Critters = { "Mobs" }, Friends = { "Own" },
			FriendlyMinions = { "Pets", "Minions", "Totems" }, Enemies = { "Other" },
			EnemyMinions = { "Pets", "Minions", "Totems" },
		}, OLD_NAME_KEYS)
		ns.db.plateRowsV1 = true
	end
end

-- (Step 2.)
STEPS[#STEPS + 1] = function()
	-- Enemy Units split into Enemy players (still "Enemies") and Enemy NPCs:
	-- the new row starts out ticked wherever the old one was.
	if not ns.db.plateEnemyNPCsV1 then
		for _, prefix in ipairs({ "plateCombat", "plateCinematic", "plateInCities", "plateInInns",
			"plateInDungeons", "plateInRaids", "plateInPvP" }) do
			if ns.db[prefix .. "Enemies"] ~= nil then
				ns.db[prefix .. "EnemyNPCs"] = ns.db[prefix .. "Enemies"]
			end
		end
		ns.db.plateEnemyNPCsV1 = true
	end
	-- The grids' Inns column joined Open world: ticked there wherever either was.
	for _, kind in ipairs(ns.PLATE_KINDS) do
		if ns.db["plateInInns" .. kind] then ns.db["plateCinematic" .. kind] = true end
		ns.db["plateInInns" .. kind] = nil
	end
	for _, group in ipairs(ns.NAME_GROUPS) do
		if ns.db["nameInInns" .. group.key] then ns.db["nameKeep" .. group.key] = true end
		ns.db["nameInInns" .. group.key] = nil
	end
	ns.db.namePlateLinkV1 = nil
	-- The cozy, vista and fish cameras' "Play music" switches became a Music
	-- column per event: each starts from the switch for the camera it's set to.
	if ns.db.musicCamCozy ~= nil or ns.db.musicCamVista ~= nil or ns.db.musicCamFish ~= nil then
		local old = { cozy = ns.db.musicCamCozy, tele = ns.db.musicCamCozy, vista = ns.db.musicCamVista,
			fish = ns.db.musicCamFish }
		for _, event in ipairs(ns.EVENTS) do
			local camera = ns.db["event" .. event.key .. "Camera"] or event.camera
			if ns.EVENT_MUSIC_DEFAULT[event.camera] ~= nil and old[camera] ~= nil
				and ns.db["event" .. event.key .. "Music"] == nil then
				ns.db["event" .. event.key .. "Music"] = old[camera]
			end
		end
		ns.db.musicCamCozy, ns.db.musicCamVista, ns.db.musicCamFish = nil, nil, nil
	end
	-- The Calm Timer replaced the nameplates' linger and the letterbox's and
	-- tint's own waits after a fight; it starts from the linger.
	if ns.db.calmTime == nil then
		ns.db.calmTime = ns.db.plateCombatLinger or ns.db.letterboxCombatWait
	end
	ns.db.plateCombatLinger, ns.db.letterboxCombatWait, ns.db.tintCombatWait = nil, nil, nil
	-- And the buffs' window after a fight and each camera's own wait.
	ns.db.buffPeekCombatWindow, ns.db.musicCombatResume = nil, nil
	ns.db.fadeChat = nil -- (chat always fades in CineMode now; mouseover shows it)
	-- The Chat page's "Always show in" (Cities, Dungeons, Raids, PvP) became
	-- the Standard Frames page's Chat window row: its place columns.
	-- (Saved profiles too.)
	local function ChatPlaces(t)
		for old, list in pairs({ chatInCities = "cityShow", chatInDungeons = "instanceShow",
			chatInRaids = "instanceShow", chatInPvP = "bgShow" }) do
			if t[old] then
				t[list] = type(t[list]) == "table" and t[list] or {}
				if t[list].chat == nil then t[list].chat = true end
			end
			t[old] = nil
		end
	end
	ChatPlaces(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then ChatPlaces(saved) end
	end
	for _, mode in ipairs({ "taxi", "idle", "walk", "run", "cozy", "vista", "fish", "tele" }) do
		ns.db[mode .. "CombatWait"] = nil
	end
	-- The tele camera's tooltips followed the cozy camera's until it had its own row.
	if ns.db.tooltipOffTele == nil and ns.db.tooltipOffCozy ~= nil then
		ns.db.tooltipOffTele = ns.db.tooltipOffCozy
	end
	-- The tooltips' Never column (no showing again after hovering in a camera mode) is gone.
	for _, mode in ipairs({ "Flight", "Idle", "Cozy", "Tele", "Vista", "Fish", "Walk", "Run", "Death", "Quest" }) do
		ns.db["tooltipNever" .. mode] = nil
	end
	-- Inns had their own place in every "Turn off in" and "Keep ... in" list;
	-- they count as the open world now.
	ns.db.offInInns, ns.db.chatInInns, ns.db.musicOffInInns, ns.db.trackingOffInInns = nil, nil, nil, nil
	for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
		ns.db[cam[1] .. "OffInInns"] = nil
	end
	-- The "Turn off in" grid had Dungeons, Raids and PvP columns, and Party,
	-- Raid group and In group (gone): now In instance (battlegrounds and
	-- arenas too) and Open world. In instance is ticked if Dungeons or Raids
	-- was (not PvP: that would turn a camera off in dungeons and raids too).
	for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
		local prefix = cam[1] .. "OffIn"
		local function Merge(new, olds)
			local any, seen = false, false
			for _, old in ipairs(olds) do
				if ns.db[prefix .. old] ~= nil then
					seen = true
					any = any or ns.db[prefix .. old] == true
				end
				ns.db[prefix .. old] = nil
			end
			if seen and ns.db[prefix .. new] == nil then
				ns.db[prefix .. new] = any
			end
		end
		Merge("Instances", { "Dungeons", "Raids" })
		ns.db[prefix .. "PvP"], ns.db[prefix .. "Party"], ns.db[prefix .. "RaidGroup"] = nil, nil, nil
		ns.db[prefix .. "Group"] = nil
		-- It had an Always column too (off everywhere): every place now.
		if ns.db[cam[1] .. "OffAlways"] then
			for _, where in ipairs({ "Cities", "Instances", "World" }) do
				if not (ns.CAMERA_OFF_NEVER[cam[1]] or {})[where] then
					ns.db[prefix .. where] = true
				end
			end
		end
		ns.db[cam[1] .. "OffAlways"] = nil
	end
	-- The cozy zoom first pulled back further and came in less; update it
	-- once, unless changed.
	if not ns.db.cozySettingsV2 then
		if ns.db.cozyZoomDistance == 1 then ns.db.cozyZoomDistance = nil end
		if ns.db.cozyZoomIn == 2 then ns.db.cozyZoomIn = nil end
		ns.db.cozySettingsV2 = true
	end
	-- ...and its sway was wider and quicker, and its zoom worked from your
	-- own distance rather than a close-up.
	if ns.db.cozyLevel == 20 then ns.db.cozyLevel = nil end -- was tilting the wrong way
	-- The close-up was too tight (and a little too low); once, unless changed.
	if not ns.db.cozySettingsV4 then
		if ns.db.cozyZoomClose == 6 then ns.db.cozyZoomClose = nil end
		if ns.db.cozyLevel == 50 then ns.db.cozyLevel = nil end
		ns.db.cozySettingsV4 = true
	end
	-- The settle used to start this long before landing (default 8); now
	-- it's when the camera is locked behind you (default 5). Once, unless changed.
	if not ns.db.taxiSettleV2 then
		if ns.db.taxiSettleLead == 8 then ns.db.taxiSettleLead = nil end
		ns.db.taxiSettleV2 = true
	end
	-- Fly-bys turned to 150 degrees at first, now 160. Once, unless changed.
	if not ns.db.flyByAngleV2 then
		if ns.db.flyByAngle == 150 then ns.db.flyByAngle = nil end
		ns.db.flyByAngleV2 = true
	end
	-- The fly-by /look was on by default at first; now off by default (it may
	-- be what snaps the camera as a fly-by starts). Saved "on" goes once.
	if not ns.db.flyByLookOffV1 then
		if ns.db.flyByLook == true then ns.db.flyByLook = nil end
		ns.db.flyByLookOffV1 = true
	end
	-- Vitals' screen edges closed in evenly at first (Ramp up 0%); 50% now,
	-- saved profiles too. Once, unless changed.
	if not ns.db.lowHealthRampV2 then
		if ns.db.lowHealthRamp == 0 then ns.db.lowHealthRamp = nil end
		for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
			if type(saved) == "table" and saved.lowHealthRamp == 0 then saved.lowHealthRamp = nil end
		end
		ns.db.lowHealthRampV2 = true
	end
	-- Service NPCs' titles first kept their < > by default; off now, for
	-- everyone and every saved profile. Once.
	if not ns.db.serviceBracketsOffV1 then
		ns.db.nameServiceBrackets = nil
		for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
			if type(saved) == "table" then saved.nameServiceBrackets = nil end
		end
		ns.db.serviceBracketsOffV1 = true
	end
	-- Still too low (the ground pulled the camera in); once, unless changed.
	if not ns.db.cozySettingsV5 then
		if ns.db.cozyLevel == 40 then ns.db.cozyLevel = nil end
		ns.db.cozySettingsV5 = true
	end
	-- The cozy sway now reaches either side of your front (arriving at one
	-- side); its old narrow swing is updated once, unless changed.
	if not ns.db.cozySettingsV7 then
		if ns.db.cozyOrbitBackArc == 15 then ns.db.cozyOrbitBackArc = nil end
		ns.db.cozySettingsV7 = true
	end
	-- RP walking is deliberate: its camera now runs in cities and instances
	-- too. Once, unless changed.
	if not ns.db.walkSettingsV1 then
		if ns.db.walkOffInCities == true then ns.db.walkOffInCities = nil end
		if ns.db.walkOffInInstances == true then ns.db.walkOffInInstances = nil end
		ns.db.walkSettingsV1 = true
	end
	if not ns.db.runSettingsV6 then -- auto-run rises less (looks ahead more)
		if ns.db.runOrbitPitchUp == 10 then ns.db.runOrbitPitchUp = nil end
		ns.db.runSettingsV6 = true
	end
	if not ns.db.runSettingsV5 then -- auto-run zooms out further
		if ns.db.runZoomDistance == 5 or ns.db.runZoomDistance == 4 then ns.db.runZoomDistance = nil end
		ns.db.runSettingsV5 = true
	end
	if not ns.db.runSettingsV4 then -- livelier auto-run zoom and height changes
		for key, old in pairs({ runZoomPause = 4, runZoomTime = 10, runZoomDistance = 4, runZoomIn = 3,
			runOrbitPitchUp = 6, runOrbitPitchDown = 6, runOrbitMoveTime = 8, runOrbitPause = 4 }) do
			if ns.db[key] == old then ns.db[key] = nil end
		end
		ns.db.runSettingsV4 = true
	end
	if not ns.db.runSettingsV3 then -- auto-run's glide after a turn starts sooner
		if ns.db.runGlideDelay == 1.5 then ns.db.runGlideDelay = nil end
		ns.db.runSettingsV3 = true
	end
	if ns.db.deathSongFile then -- one song became a list to pick from
		if ns.db.deathSongFile ~= 53519 then ns.db.deathSongFiles = tostring(ns.db.deathSongFile) end
		ns.db.deathSongFile = nil
	end
	-- "Show buffs when you gain or refresh one" covered debuffs too; now they
	-- have their own switch, on if it was.
	if ns.db.debuffPeek == nil and ns.db.buffPeek ~= nil then
		ns.db.debuffPeek = ns.db.buffPeek
	end
	-- "Show buffs for" covered debuffs too; now they have their own time.
	if ns.db.debuffPeekTime == nil and ns.db.buffPeekTime ~= nil then
		ns.db.debuffPeekTime = ns.db.buffPeekTime
	end
	if not ns.db.buffPeekIgnoreV2 then -- Ghost joins the list, unless it was changed
		if ns.db.buffPeekIgnore == "2479, Plainsrunning" then ns.db.buffPeekIgnore = nil end
		ns.db.buffPeekIgnoreV2 = true
	end
	if not ns.db.deathSettingsV4 then -- starts as you fall
		if ns.db.deathOrbitDelay == 2 then ns.db.deathOrbitDelay = nil end
		ns.db.deathSettingsV4 = true
	end
	if not ns.db.deathSettingsV3 then -- a gentler rise
		if ns.db.deathLevel == 70 or ns.db.deathLevel == 60 then ns.db.deathLevel = nil end
		ns.db.deathSettingsV3 = true
	end
	if not ns.db.questCamSettingsV7 then -- the zooms in and back out go by speed, not time
		ns.db.questCamZoomTime, ns.db.questCamZoomOutTime = nil, nil
		ns.db.questCamSettingsV7 = true
	end
	if not ns.db.questCamSettingsV6 then -- a slower zoom back out (walking off, it's still quick)
		if ns.db.questCamZoomOutTime == 1.5 then ns.db.questCamZoomOutTime = nil end
		ns.db.questCamSettingsV6 = true
	end
	if not ns.db.questCamSettingsV5 then -- the side you clicked them on
		if ns.db.questCamSide == "random" then ns.db.questCamSide = nil end
		ns.db.questCamSettingsV5 = true
	end
	if not ns.db.questCamSettingsV4 then -- comes down less (lower, it met the scenery)
		if ns.db.questCamLower == 20 then ns.db.questCamLower = nil end
		ns.db.questCamSettingsV4 = true
	end
	if not ns.db.questCamSettingsV3 then -- a gentler swing
		if ns.db.questCamTime == 1.5 then ns.db.questCamTime = nil end
		ns.db.questCamSettingsV3 = true
	end
	if not ns.db.questCamSettingsV2 then -- a slower zoom
		if ns.db.questCamZoomTime == 4 then ns.db.questCamZoomTime = nil end
		ns.db.questCamSettingsV2 = true
	end
	if not ns.db.vistaSettingsV2 then -- doesn't drop down as much
		if ns.db.vistaLevel == 10 then ns.db.vistaLevel = nil end
		if ns.db.vistaOrbitPitchDown == 5 then ns.db.vistaOrbitPitchDown = nil end
		ns.db.vistaSettingsV2 = true
	end
end

-- (Step 3.)
STEPS[#STEPS + 1] = function()
	-- Auto-run's "Play music" was on by default; it's off now, unless changed.
	if not ns.db.runMusicV2 then
		if ns.db.musicCamRun == true then ns.db.musicCamRun = nil end
		ns.db.runMusicV2 = true
	end
	-- "Start a fresh song when" and "Start music anyway" became one "Play
	-- music" choice per camera: one switched off in both stays off.
	for new, old in pairs({ Flight = { "musicNewSongOnFlights", "fatigueIgnoreOnFlights" },
		Idle = { "musicNewSongWhenIdle", "fatigueIgnoreWhenIdle" },
		Cozy = { "musicNewSongWhenCozy", "fatigueIgnoreWhenCozy" },
		Walk = { "musicNewSongWhenWalking", "fatigueIgnoreWhenWalking" },
		Run = { "musicNewSongWhenAutoRun", "fatigueIgnoreWhenAutoRun" } }) do
		if ns.db[old[1]] == false and ns.db[old[2]] == false and ns.db["musicCam" .. new] == nil then
			ns.db["musicCam" .. new] = false
		end
		ns.db[old[1]], ns.db[old[2]] = nil, nil
	end
	-- Gone: "Start music anyway in a new zone" and "Ambience follows music".
	-- (A lowered ambience volume left over is put back with the other settings.)
	ns.db.fatigueIgnoreNewZone, ns.db.lastMusicZone = nil, nil
	ns.db.ambienceFollowsMusic, ns.db.ambienceScale = nil, nil
	if not ns.db.fishMissPauseV2 then -- 5 sec became 30 (moving to a new spot still ends it)
		if ns.db.fishMissPause == 5 then ns.db.fishMissPause = nil end
		ns.db.fishMissPauseV2 = true
	end
	-- The fishing event used the vista camera by default before the fish
	-- camera existed: that saved default moves over to it.
	if not ns.db.fishCamV1 then
		if ns.db.eventFishingCamera == "vista" then ns.db.eventFishingCamera = nil end
		ns.db.fishCamV1 = true
	end
	-- The Hearthstone and teleport events used the cozy camera before the tele
	-- camera existed: that saved choice moves over to it.
	if not ns.db.teleCamV1 then
		for _, key in ipairs({ "eventHearthCamera", "eventTeleportCamera" }) do
			if ns.db[key] == "cozy" then ns.db[key] = nil end
		end
		ns.db.teleCamV1 = true
	end
	if not ns.db.cozySettingsV8 then -- a slower sway
		if ns.db.cozyOrbitMoveTime == 12 then ns.db.cozyOrbitMoveTime = nil end
		ns.db.cozySettingsV8 = true
	end
	if not ns.db.cozySettingsV6 then -- a little higher again
		if ns.db.cozyLevel == 20 then ns.db.cozyLevel = nil end
		ns.db.cozySettingsV6 = true
	end
	if not ns.db.cozySettingsV3 then
		for key, old in pairs({ BackArc = 30, MinChange = 10, PitchUp = 8, PitchDown = 4,
			MoveTime = 9, DriftSpeed = 1 }) do
			if ns.db["cozyOrbit" .. key] == old then ns.db["cozyOrbit" .. key] = nil end
		end
		if ns.db.cozyZoomIn == 2 or ns.db.cozyZoomIn == 4 then ns.db.cozyZoomIn = nil end
		ns.db.cozySettingsV3 = true
	end
	-- The buff list used to start the standing-still camera; it's the cozy
	-- camera's now.
	if ns.db.idleBuffs ~= nil then
		ns.db.cozyBuffs = ns.db.idleBuffs
		if ns.db.idleAtCampfire ~= nil then ns.db.cozyBuffsOn = ns.db.idleAtCampfire end
		ns.db.idleBuffs, ns.db.idleAtCampfire = nil, nil
	end
	-- World tooltips used to be one switch for every camera mode.
	if ns.db.tooltipOffInCameraModes ~= nil then
		for _, key in ipairs({ "tooltipOffFlight", "tooltipOffIdle", "tooltipOffCozy",
			"tooltipOffWalk", "tooltipOffRun" }) do
			ns.db[key] = ns.db.tooltipOffInCameraModes
		end
		ns.db.tooltipOffInCameraModes = nil
	end
	-- They could also hide the whole time in CineMode (fadeTooltip); now
	-- it's only ever per camera mode.
	ns.db.fadeTooltip = nil
	-- Then tooltips were always hidden, with exceptions: each camera mode's
	-- Hide (tooltipOff*) became its Show anyway (tooltipShowIn*), and
	-- hiding in combat (tooltipCombat and its kinds) went.
	for _, mode in ipairs({ "Flight", "Idle", "Cozy", "Tele", "Vista", "Fish", "Walk", "Run", "Death", "Quest" }) do
		local old = ns.db["tooltipOff" .. mode]
		if old ~= nil and ns.db["tooltipShowIn" .. mode] == nil then
			ns.db["tooltipShowIn" .. mode] = not old
		end
		ns.db["tooltipOff" .. mode] = nil
	end
	ns.db.tooltipCombat, ns.db.tooltipCombatWorld = nil, nil
	ns.db.tooltipCombatUnits, ns.db.tooltipCombatUI = nil, nil
	-- Then Always hide tooltips, with each exception its own line: the
	-- kinds that showed at once after hovering show at once by themselves,
	-- and the camera modes went under one Except in these camera modes.
	ns.db.tooltipHideWorld, ns.db.tooltipHideUnits, ns.db.tooltipHideUI = nil, nil, nil
	for old, new in pairs({ tooltipQuestAtOnce = "tooltipShowQuest", tooltipGatherAtOnce = "tooltipShowGather",
		tooltipEnemyAtOnce = "tooltipShowEnemy", tooltipFriendlyAtOnce = "tooltipShowFriendly" }) do
		if ns.db[old] ~= nil and ns.db[new] == nil then
			ns.db[new] = ns.db[old]
		end
		ns.db[old] = nil
	end
	if ns.db.tooltipShowInModes == nil then
		for _, mode in ipairs({ "Flight", "Idle", "Cozy", "Tele", "Vista", "Fish", "Walk", "Run", "Death", "Quest" }) do
			if ns.db["tooltipShowIn" .. mode] then
				ns.db.tooltipShowInModes = true
			end
		end
	end
	-- Then the other way round: Hide tooltips in CineMode, in these camera
	-- modes or outside CineMode, but still show the kinds ticked. Always hide
	-- with Except outside CineMode is In CineMode; Except in these camera
	-- modes is In these camera modes with the others ticked (so plain
	-- CineMode, in no camera mode, no longer hides). Saved profiles too. Once,
	-- and only with the page's switch on: with it off, the page's never been
	-- used (or was left), so it starts over from the new defaults.
	local tooltipModes = { "Flight", "Idle", "Cozy", "Tele", "Vista", "Fish", "Walk", "Run", "Death", "Quest" }
	local function TooltipsTheOtherWay(t)
		if t.tooltipHide == nil and t.tooltipShowOutsideCine == nil and t.tooltipShowInModes == nil then
			return
		end
		local hide = t.tooltipHide ~= false
		local inModes = false
		if t.tooltipShowInModes then
			for _, mode in ipairs(tooltipModes) do
				if not t["tooltipShowIn" .. mode] then inModes = true end
			end
		end
		if t.tooltipHideInCine == nil then
			t.tooltipHideInCine = hide and not inModes
			t.tooltipHideInModes = hide and inModes
			t.tooltipHideOutsideCine = hide and t.tooltipShowOutsideCine == false
			for _, mode in ipairs(tooltipModes) do
				t["tooltipHideIn" .. mode] = inModes and not t["tooltipShowIn" .. mode]
			end
		end
		t.tooltipHide, t.tooltipShowOutsideCine, t.tooltipShowInModes = nil, nil, nil
		for _, mode in ipairs(tooltipModes) do
			t["tooltipShowIn" .. mode] = nil
		end
	end
	if not ns.db.tooltipsTheOtherWayV1 then
		if ns.db.handleTooltips then
			TooltipsTheOtherWay(ns.db)
		else
			for _, key in ipairs({ "tooltipHideInCine", "tooltipHideInModes", "tooltipHideOutsideCine",
				"tooltipShowEnemy", "tooltipShowFriendly", "tooltipShowGather", "tooltipShowQuest",
				"tooltipShowInCombat", "tooltipCombatShowEnemy", "tooltipCombatShowFriendly",
				"tooltipCombatShowElse", "tooltipReveal", "tooltipRevealDelay", "tooltipWarmTime",
				"tooltipFadeTime", "tooltipHide", "tooltipShowOutsideCine", "tooltipShowInModes" }) do
				ns.db[key] = nil
			end
			for _, mode in ipairs(tooltipModes) do
				ns.db["tooltipHideIn" .. mode], ns.db["tooltipShowIn" .. mode] = nil, nil
			end
		end
		for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
			if type(saved) == "table" then TooltipsTheOtherWay(saved) end
		end
		ns.db.tooltipsTheOtherWayV1 = true
	end
	-- The Tooltips page was Hide tooltips (in CineMode, in the camera modes
	-- ticked, outside CineMode), then But still show (kinds, a combat list,
	-- After hovering). Now it only hides in CineMode: the kinds ticked under
	-- Hide out of combat / Hide in combat, and everything in the camera modes
	-- ticked. Hiding in all of CineMode is every mode ticked and the kinds
	-- that didn't show anyway; with just the modes, plain CineMode hid
	-- nothing. Saved profiles too (missing settings were the old defaults).
	local OLD_TOOLTIP_DEFAULTS = {
		tooltipHideInCine = false, tooltipHideInModes = true, tooltipHideOutsideCine = false,
		tooltipShowEnemy = true, tooltipShowFriendly = false, tooltipShowGather = true,
		tooltipShowQuest = true, tooltipShowInCombat = true, tooltipCombatShowEnemy = true,
		tooltipCombatShowFriendly = false, tooltipCombatShowElse = false, tooltipReveal = true,
		tooltipRevealDelay = 1, tooltipWarmTime = 5, tooltipFadeTime = 0.5,
	}
	local function TooltipKindsToHide(t)
		local any = false
		for key in pairs(OLD_TOOLTIP_DEFAULTS) do
			any = any or t[key] ~= nil
		end
		if not any then
			return
		end
		local function old(key)
			if t[key] == nil then return OLD_TOOLTIP_DEFAULTS[key] end
			return t[key]
		end
		-- (With the page's switch off, it starts over from the new defaults.)
		if t.handleTooltips then
			local all = old("tooltipHideInCine")
			if all or not old("tooltipHideInModes") then
				for _, mode in ipairs(tooltipModes) do
					t["tooltipHideIn" .. mode] = all
				end
			end
			local combatList = old("tooltipShowInCombat")
			t.tooltipHideEnemy = all and not old("tooltipShowEnemy")
			t.tooltipHideFriendly = all and not old("tooltipShowFriendly")
			t.tooltipHideGather = all and not old("tooltipShowGather")
			t.tooltipHideQuest = all and not old("tooltipShowQuest")
			t.tooltipHideCombatEnemy = all and not old(combatList and "tooltipCombatShowEnemy" or "tooltipShowEnemy")
			t.tooltipHideCombatElse = all and combatList and not old("tooltipCombatShowElse")
		else
			for _, mode in ipairs(tooltipModes) do
				t["tooltipHideIn" .. mode] = nil
			end
		end
		for key in pairs(OLD_TOOLTIP_DEFAULTS) do
			t[key] = nil
		end
	end
	TooltipKindsToHide(ns.db)
	for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
		if type(saved) == "table" then TooltipKindsToHide(saved) end
	end
	-- Friendlies in combat were part of Everything else; they're a line of
	-- their own now, starting as Everything else was. Saved profiles too.
	local function CombatFriendlyFromElse(t)
		if t.tooltipHideCombatFriendly == nil and t.tooltipHideCombatElse ~= nil then
			t.tooltipHideCombatFriendly = t.tooltipHideCombatElse
		end
	end
	-- Gatherables and quest objectives in combat were part of Everything
	-- else too, the same way.
	local function CombatKindsFromElse(t)
		for _, kind in ipairs({ "Gather", "Quest" }) do
			if t["tooltipHideCombat" .. kind] == nil and t.tooltipHideCombatElse ~= nil then
				t["tooltipHideCombat" .. kind] = t.tooltipHideCombatElse
			end
		end
	end
	-- At the mouse cursor was two ticks (always, in fights) before it was a choice.
	local function CursorModeFromTicks(t)
		if t.tooltipCursorMode == nil and (t.tooltipAtCursor or t.tooltipAtCursorCombat) then
			t.tooltipCursorMode = t.tooltipAtCursor and "cursor" or "combat"
		end
		t.tooltipAtCursor, t.tooltipAtCursorCombat = nil, nil
	end
	CursorModeFromTicks(ns.db)
	for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
		if type(saved) == "table" then CursorModeFromTicks(saved) end
	end
	CombatKindsFromElse(ns.db)
	for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
		if type(saved) == "table" then CombatKindsFromElse(saved) end
	end
	CombatFriendlyFromElse(ns.db)
	for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
		if type(saved) == "table" then CombatFriendlyFromElse(saved) end
	end
	-- The cozy and vista triggers used to be switches on those cameras' pages;
	-- they're events now, each picking its camera. A switched-off trigger
	-- becomes "no camera".
	local oldTriggers = { Campfire = "cozyBuffsOn", Sit = "cozySit", Sleep = "cozySleep",
		Dance = "cozyDance", Kneel = "cozyKneel", Chair = "cozyChair", Weapon = "cozyWeapon",
		Stare = "vistaStare" }
	for event, old in pairs(oldTriggers) do
		if ns.db[old] == false and ns.db["event" .. event .. "Camera"] == nil then
			ns.db["event" .. event .. "Camera"] = "none"
		end
	end
end

-- (Step 4.)
STEPS[#STEPS + 1] = function()
	-- Events had "Start right away", then a delay ("Wait") and a "Stop on
	-- move" switch each; they now start right away and always stop on moving.
	for _, event in ipairs(ns.EVENTS) do
		local key = "event" .. event.key
		ns.db[key .. "Instant"], ns.db[key .. "Delay"], ns.db[key .. "StopOnMove"] = nil, nil, nil
	end
	-- One camera input pause used to cover the flight and AFK cameras; each
	-- has its own now. Only a changed one carries over.
	if ns.db.cameraInputPause and ns.db.cameraInputPause ~= 15 then
		ns.db.taxiInputPause = ns.db.taxiInputPause or ns.db.cameraInputPause
		ns.db.idleInputPause = ns.db.idleInputPause or ns.db.cameraInputPause
	end
	-- The quest cam's side used to be two switches (random, else left).
	if ns.db.questCamRandomSide == false and ns.db.questCamSide == nil then
		ns.db.questCamSide = ns.db.questCamLeft and "left" or "right"
	end
	-- When the tint shows used to be one choice: always, only on flights or
	-- only standing still (the last two never in combat).
	if ns.db.tintWhen == "flight" or ns.db.tintWhen == "idle" then
		ns.db.tintMoving, ns.db.tintInCombat = false, false
		ns.db.tintFlight = ns.db.tintWhen == "flight"
		ns.db.tintStill = ns.db.tintWhen == "idle"
	end
	-- The letterbox and tint first showed by situation (moving around,
	-- standing still, on flights, in combat): now by place, with fights
	-- their own column. In combat off is Combat ticked; the rest go.
	-- Battlegrounds and arenas were part of Instances on the Camera Modes
	-- grid: their own column now, starting as Instances was. (The live
	-- settings and each saved profile alike.)
	local function CarryOver(settings)
		for _, effect in ipairs(ns.EFFECT_GRID) do
			local inCombat = settings[effect .. "InCombat"]
			if inCombat ~= nil and settings[effect .. "OffInCombat"] == nil then
				settings[effect .. "OffInCombat"] = not inCombat
			end
			for _, old in ipairs({ "Moving", "Still", "Flight", "InCombat" }) do
				settings[effect .. old] = nil
			end
		end
		settings.visualEffectsAlways = nil -- (Fade the UI off shows them over the normal UI now)
		for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
			local instances = settings[cam[1] .. "OffInInstances"]
			if instances ~= nil and settings[cam[1] .. "OffInBGs"] == nil then
				settings[cam[1] .. "OffInBGs"] = instances
			end
		end
	end
	CarryOver(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then CarryOver(saved) end
	end
	-- The raid frames' threat highlight got a row: into saved Mouseover
	-- groups with the role icons, as the default groups have it. Once.
	if not ns.db.raidThreatHoverV1 then
		local function AddThreatRow(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.raidroles and not has.raidthreat then
					table.insert(group.members, "raidthreat")
				end
			end
		end
		AddThreatRow(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then AddThreatRow(saved.hoverGroups) end
		end
		ns.db.raidThreatHoverV1 = true
	end
	-- The raid frames' target highlight, an on/off switch (showRaidTargetOutline),
	-- got a full row: switched off, its Always tick starts off; and into saved
	-- Mouseover groups with the threat highlight, as the default groups have it.
	if not ns.db.raidTargetRowV1 then
		local function MoveTargetRow(saved)
			if saved.showRaidTargetOutline == false and type(saved.cineShow) == "table"
				and saved.cineShow.raidtarget == nil then
				saved.cineShow.raidtarget = false
			end
			saved.showRaidTargetOutline = nil
			for _, group in ipairs(saved.hoverGroups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.raidthreat and not has.raidtarget then
					table.insert(group.members, "raidtarget")
				end
			end
		end
		MoveTargetRow(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then MoveTargetRow(saved) end
		end
		ns.db.raidTargetRowV1 = true
	end
	-- The raid frames' ready check icon got a row: into saved Mouseover
	-- groups with the target highlight, as the default groups have it.
	if not ns.db.raidReadyRowV1 then
		local function AddReadyRow(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.raidtarget and not has.raidready then
					table.insert(group.members, "raidready")
				end
			end
		end
		AddReadyRow(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then AddReadyRow(saved.hoverGroups) end
		end
		ns.db.raidReadyRowV1 = true
	end
	-- The pet portrait got a row apart from yours: into saved Mouseover
	-- groups with your portrait, as the default groups have it. Once.
	if not ns.db.petFrameHoverV1 then
		local function AddPetRow(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.player and not has.petframe then
					table.insert(group.members, "petframe")
				end
			end
		end
		AddPetRow(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then AddPetRow(saved.hoverGroups) end
		end
		ns.db.petFrameHoverV1 = true
	end
	-- The bags got a row apart from the micro menu's: each mouseover group
	-- with the micro menu gets them too, and its role hides and rule (its
	-- ticks they follow until set). The live settings and each saved
	-- profile's alike. Once.
	if not ns.db.bagsHoverV1 then
		local function AddBagsRow(groups)
			for _, group in ipairs(groups or {}) do
				local has, at = {}, nil
				for i, key in ipairs(group.members or {}) do
					has[key] = true
					if key == "micro" then at = i end
				end
				if at and not has.bags then
					table.insert(group.members, at + 1, "bags")
				end
			end
		end
		local function CarryMicro(settings)
			AddBagsRow(settings.hoverGroups)
			for _, list in ipairs({ "tankHide", "healerHide", "damageHide", "frameRules" }) do
				local t = settings[list]
				if type(t) == "table" and t.micro ~= nil and t.bags == nil then t.bags = t.micro end
			end
		end
		CarryMicro(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then CarryMicro(saved) end
		end
		ns.db.bagsHoverV1 = true
	end
	-- Your own frame's parts got settings apart from the target grid's You
	-- row (unitPartSelf<part>, which covered both): each starts as that row
	-- had it. The live settings and each saved profile alike. Once.
	if not ns.db.unitPartPlayerV1 then
		local function CarryPlayerParts(settings)
			for _, part in ipairs(ns.UNIT_PARTS) do
				if settings["unitPartPlayer" .. part] == nil and settings["unitPartSelf" .. part] ~= nil then
					settings["unitPartPlayer" .. part] = settings["unitPartSelf" .. part]
				end
			end
		end
		CarryPlayerParts(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then CarryPlayerParts(saved) end
		end
		ns.db.unitPartPlayerV1 = true
	end
	-- The target, focus and target of target frames' parts went from a row
	-- per kind of unit (unitPart<prefix><kind><part>) to one setting each
	-- (unitPart<frame><part>): hidden where every kind had it hidden; on
	-- the target frame, shown for just some kinds, a rule naming those
	-- (the rules' words for your target); elsewhere, shown. The live
	-- settings and each saved profile alike. Once.
	if not ns.db.unitPartFramesV1 then
		local KIND_WORDS = { Self = "targetself", EnemyPlayer = "enemyplayer", EnemyNPC = "hostilenpc",
			NeutralPlayer = "neutralplayer", NeutralNPC = "neutralnpc", FriendlyPlayer = "friendlyplayer",
			FriendlyNPC = "friendlynpc" }
		local KINDS = { "Self", "EnemyPlayer", "EnemyNPC", "NeutralPlayer", "NeutralNPC", "FriendlyPlayer", "FriendlyNPC" }
		local function CarryFrameParts(settings)
			for _, frame in ipairs({ { "Target", "" }, { "ToT", "ToT" }, { "Focus", "Focus" }, { "FocusToT", "FocusToT" } }) do
				for _, part in ipairs(ns.UNIT_PARTS) do
					local key = "unitPart" .. frame[1] .. part
					if DEFAULTS[key] ~= nil and settings[key] == nil then
						-- (Threat was only ever on NPCs you can fight.)
						local kinds = part == "Threat" and { "EnemyNPC", "NeutralNPC" } or KINDS
						local shown = {}
						for _, kind in ipairs(kinds) do
							if settings["unitPart" .. frame[2] .. kind .. part] ~= false then
								shown[#shown + 1] = KIND_WORDS[kind]
							end
						end
						if #shown == 0 then
							settings[key] = false
						elseif #shown < #kinds and frame[1] == "Target" then
							settings.frameRules = settings.frameRules or {}
							if not settings.frameRules[key] then
								settings[key] = false
								settings.frameRules[key] = table.concat(shown, " or ")
							end
						end
					end
				end
			end
		end
		CarryFrameParts(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then CarryFrameParts(saved) end
		end
		ns.db.unitPartFramesV1 = true
	end
	-- Friendly plates in dungeons and raids got a setting of their own
	-- (plateInstance<kind>): each starts as the grids left it there, grouped
	-- and out of fights (what kept that kind on before), else hidden. The
	-- live settings and each saved profile alike. Once.
	if not ns.db.plateInstanceModesV1 then
		local ROWS = {
			Friends = { "Friends", "GroupMembers" },
			FriendlyMinions = { "FriendlyMinions", "MyPet", "GroupMinions" },
			FriendlyNPCs = { "FriendlyNPCs" },
		}
		local function CarryInstanceModes(settings)
			local function On(key)
				local value = settings[key]
				if value == nil then value = DEFAULTS[key] end
				return value and true or false
			end
			for kind, rows in pairs(ROWS) do
				if settings["plateInstance" .. kind] == nil then
					local shown = false
					for _, row in ipairs(rows) do
						for _, prefix in ipairs({ "plateInInstances", "plateAlways", "plateGroup", "plateCombat" }) do
							shown = shown or On(prefix .. row)
						end
					end
					settings["plateInstance" .. kind] = shown and "show" or "hide"
				end
			end
		end
		if not ns.newInstall then
			CarryInstanceModes(ns.db)
		end
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then CarryInstanceModes(saved) end
		end
		ns.db.plateInstanceModesV1 = true
	end
end

-- (Step 5.)
STEPS[#STEPS + 1] = function()
	-- The personal resource bars' power half got a row apart from the
	-- health bar: into saved Mouseover groups with it. Once.
	if not ns.db.prdPowerHoverV1 then
		local function AddPowerRow(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.prd and not has.prdpower then
					table.insert(group.members, "prdpower")
				end
			end
		end
		AddPowerRow(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then AddPowerRow(saved.hoverGroups) end
		end
		ns.db.prdPowerHoverV1 = true
	end
	-- And the mana bar's row (PersonalMana.lua), with the power half. Once.
	if not ns.db.prdManaHoverV1 then
		local function AddManaRow(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.prdpower and not has.prdmana then
					table.insert(group.members, "prdmana")
				end
			end
		end
		AddManaRow(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then AddManaRow(saved.hoverGroups) end
		end
		ns.db.prdManaHoverV1 = true
	end
	-- The mana bar's row followed the resource bar (the Cinema profile's):
	-- its own Always now, the bar's few seconds after you use mana. Once.
	if not ns.db.prdManaFollowV1 then
		local function Unfollow(follow)
			if type(follow) == "table" and follow.prdmana == "prdpower" then follow.prdmana = nil end
		end
		Unfollow(ns.db.rowFollow)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then Unfollow(saved.rowFollow) end
		end
		ns.db.prdManaFollowV1 = true
	end
	-- The minimap header got a row apart from the minimap: into saved
	-- Mouseover groups with the minimap, as the default groups have it. Once.
	if not ns.db.minimapHeaderHoverV1 then
		local function AddHeaderRow(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.minimap and not has.minimapheader then
					table.insert(group.members, "minimapheader")
				end
			end
		end
		AddHeaderRow(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then AddHeaderRow(saved.hoverGroups) end
		end
		ns.db.minimapHeaderHoverV1 = true
	end
	-- What's on the header (its name, buttons and clock) got rows apart from
	-- the minimap too.
	if not ns.db.minimapHeaderPartsHoverV1 then
		local function AddButtonRows(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				for _, key in ipairs({ "minimapzone", "minimaptracking", "minimapcalendar", "minimapclock" }) do
					if has.minimap and not has[key] then
						table.insert(group.members, key)
					end
				end
			end
		end
		AddButtonRows(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then AddButtonRows(saved.hoverGroups) end
		end
		ns.db.minimapHeaderPartsHoverV1 = true
	end
	-- And the day and night dial, later still.
	if not ns.db.minimapDialHoverV1 then
		local function AddDialRow(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.minimap and not has.minimapdial then
					table.insert(group.members, "minimapdial")
				end
			end
		end
		AddDialRow(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then AddDialRow(saved.hoverGroups) end
		end
		ns.db.minimapDialHoverV1 = true
	end
	-- And the addon buttons (ours was in the minimap's own row) and the coordinates.
	if not ns.db.minimapAddonsHoverV1 then
		local function AddEdgeRows(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				for _, key in ipairs({ "minimapaddons", "minimapcoords" }) do
					if has.minimap and not has[key] then
						table.insert(group.members, key)
					end
				end
			end
		end
		AddEdgeRows(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then AddEdgeRows(saved.hoverGroups) end
		end
		ns.db.minimapAddonsHoverV1 = true
	end
	-- And the game's addon compartment: into saved groups with the minimap,
	-- and into Reveal shows lists that have the addon buttons. Once.
	if not ns.db.minimapCompartmentV1 then
		local function AddCompartmentRow(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.minimap and not has.minimapcompartment then
					table.insert(group.members, "minimapcompartment")
				end
			end
		end
		local function AddCompartmentPart(db)
			local parts = db.minimapRevealParts
			if type(parts) == "string" and (parts .. ","):find("minimapaddons,", 1, true)
				and not (parts .. ","):find("minimapcompartment,", 1, true) then
				db.minimapRevealParts = parts .. ",minimapcompartment"
			end
		end
		AddCompartmentRow(ns.db.hoverGroups)
		AddCompartmentPart(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				AddCompartmentRow(saved.hoverGroups)
				AddCompartmentPart(saved)
			end
		end
		ns.db.minimapCompartmentV1 = true
	end
	-- The unread mail icon got a row of its own (it faded with the map):
	-- into saved groups with the minimap, and into Reveal shows lists that
	-- name any part, so it still comes up with the map. Once.
	if not ns.db.minimapMailV1 then
		local function AddMailRow(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.minimap and not has.minimapmail then
					table.insert(group.members, "minimapmail")
				end
			end
		end
		local function AddMailPart(db)
			local parts = db.minimapRevealParts
			if type(parts) == "string" and parts ~= ""
				and not (parts .. ","):find("minimapmail,", 1, true) then
				db.minimapRevealParts = parts .. ",minimapmail"
			end
		end
		AddMailRow(ns.db.hoverGroups)
		AddMailPart(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				AddMailRow(saved.hoverGroups)
				AddMailPart(saved)
			end
		end
		ns.db.minimapMailV1 = true
	end
	-- The objective boxes under the minimap went with the quest tracker
	-- (always up); now with the minimap: into saved groups with it. Once.
	if not ns.db.belowMinimapHoverV1 then
		local function AddBelowRow(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.minimap and not has.belowminimap then
					table.insert(group.members, "belowminimap")
				end
			end
		end
		AddBelowRow(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then AddBelowRow(saved.hoverGroups) end
		end
		ns.db.belowMinimapHoverV1 = true
	end
	-- The chat menu button got a Mouseover row of its own (it was the chat
	-- window's): into saved groups with chat, so nothing changes till it's
	-- taken out. Once.
	if not ns.db.chatMenuHoverV1 then
		local function AddChatMenuRow(groups)
			for _, group in ipairs(type(groups) == "table" and groups or {}) do
				local has = {}
				for _, key in ipairs(group.members or {}) do has[key] = true end
				if has.chat and not has.chatmenu then
					table.insert(group.members, "chatmenu")
				end
			end
		end
		AddChatMenuRow(ns.db.hoverGroups)
		for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
			if type(saved) == "table" then AddChatMenuRow(saved.hoverGroups) end
		end
		ns.db.chatMenuHoverV1 = true
	end
	-- Roll Vision was first off by default; on once. Saved profiles too.
	if not ns.db.rollWindowV1 then
		ns.db.rollWindow = true
		for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
			if type(saved) == "table" then saved.rollWindow = true end
		end
		ns.db.rollWindowV1 = true
	end
	-- Roll Vision on again for Subtle, which turned it off (it stays away by
	-- itself now while another roll addon is in use). Live and saved; any
	-- other profile's off is yours and stays. Once.
	if not ns.db.rollWindowV2 then
		if (ns.db.liveProfile or ns.db.profile) == "Subtle" then ns.db.rollWindow = true end
		local subtle = type(ns.db.profiles) == "table" and ns.db.profiles.Subtle
		if type(subtle) == "table" then subtle.rollWindow = true end
		ns.db.rollWindowV2 = true
	end
	-- The vignette and weather went with the tint's row of the Visual
	-- Effects grid: rows of their own now, starting as the tint's was. Once.
	if not ns.db.effectGridV2 then
		local function SplitTintRow(settings)
			for _, effect in ipairs({ "vignette", "weather" }) do
				for _, column in ipairs({ "OffInCities", "OffInInstances", "OffInBGs", "OffInWorld",
					"OffInCombat", "OnlyInCameras" }) do
					if settings["tint" .. column] ~= nil and settings[effect .. column] == nil then
						settings[effect .. column] = settings["tint" .. column]
					end
				end
			end
		end
		SplitTintRow(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then SplitTintRow(saved) end
		end
		ns.db.effectGridV2 = true
	end
end

-- (Step 6.)
STEPS[#STEPS + 1] = function()
	-- The auto-run camera now waits 5 seconds by default: into every profile
	-- too, whatever it had. Once.
	if not ns.db.runCameraDelayV1 then
		ns.db.runCameraDelay = 5
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then saved.runCameraDelay = 5 end
		end
		ns.db.runCameraDelayV1 = true
	end
	-- ...and now 10 seconds: into every profile too, whatever it had. Once.
	if not ns.db.runCameraDelayV2 then
		ns.db.runCameraDelay = 10
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then saved.runCameraDelay = 10 end
		end
		ns.db.runCameraDelayV2 = true
	end
	-- Every camera mode is off in battlegrounds and arenas now: ticked in
	-- every profile too, whatever it had. Once.
	if not ns.db.camsOffInBGsV1 then
		local function OffInBGs(t)
			for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
				if not (ns.CAMERA_OFF_NEVER[cam[1]] or {}).BGs then
					t[cam[1] .. "OffInBGs"] = true
				end
			end
		end
		OffInBGs(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then OffInBGs(saved) end
		end
		ns.db.camsOffInBGsV1 = true
	end
	-- The game's damage meter no longer comes up in fights by default: its
	-- In combat box unticked in every profile too, whatever it had. Once.
	if not ns.db.metersCombatV1 then
		local function MetersOff(t)
			if type(t.combatShow) ~= "table" then t.combatShow = {} end
			t.combatShow.meters = false
		end
		MetersOff(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then MetersOff(saved) end
		end
		ns.db.metersCombatV1 = true
	end
	-- The party frames and raid frames' players show while you're grouped
	-- by default: their Grouped boxes ticked in every profile too. Once.
	if not ns.db.groupFramesV1 then
		local function GroupedOn(t)
			if type(t.groupShow) ~= "table" then t.groupShow = {} end
			t.groupShow.party = true
			t.groupShow.raidplayers = true
		end
		GroupedOn(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then GroupedOn(saved) end
		end
		ns.db.groupFramesV1 = true
	end
	-- No death camera in instances by default (but in Pure Cinema): its
	-- Instances box ticked in every profile too, whatever it had. Once.
	-- (Saved profiles drop theirs, to follow their base.)
	if not ns.db.deathInstancesV1 then
		if (ns.db.liveProfile or ns.db.profile) ~= "Pure Cinema" then
			ns.db.deathOffInInstances = true
		end
		for name, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" and name ~= "Pure Cinema" then saved.deathOffInInstances = nil end
		end
		ns.db.deathInstancesV1 = true
	end
	-- The weather tint now shows at full strength by default: into every
	-- profile too, whatever it had. Once.
	if not ns.db.weatherStrengthV1 then
		ns.db.weatherTintStrength = 1
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then saved.weatherTintStrength = 1 end
		end
		ns.db.weatherStrengthV1 = true
	end
	-- The weather tint off to start with (2026-11-12): 0 here and in
	-- every saved profile, whatever it had. Once.
	if not ns.db.weatherStrengthV2 then
		ns.db.weatherTintStrength = 0
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then saved.weatherTintStrength = 0 end
		end
		ns.db.weatherStrengthV2 = true
	end
	-- Cinema's Story cards now take in achievements' progress (Explore
	-- progress, Almost there, Achievement step: ProfileModules.lua): on for
	-- a player on Cinema and in their saved Cinema. Once.
	if not ns.db.cinemaProgressCardsV1 then
		local function On(t)
			if type(t) ~= "table" then return end
			t.cardExploreOn, t.cardAlmostOn, t.cardStepOn = true, true, true
		end
		if (ns.db.liveProfile or ns.db.profile) == "Cinema" then On(ns.db) end
		On(ns.db.profiles and ns.db.profiles.Cinema)
		ns.db.cinemaProgressCardsV1 = true
	end
	-- Pure Cinema shows the new target arrow on plates in CineMode (it has
	-- no target frame): into the live settings while it's the profile in
	-- use, once. (Saved copies follow their base.)
	if not ns.db.targetArrowV1 then
		if (ns.db.liveProfile or ns.db.profile) == "Pure Cinema" then
			for _, prefix in ipairs({ "plateCinematic", "plateCombat", "plateInPvP", "plateInBGs", "plateInInstances" }) do
				ns.db[prefix .. "PartTargetArrow"] = true
			end
		end
		ns.db.targetArrowV1 = true
	end
	-- Your target's Also color went to its aggro row too, while it was
	-- after you: that row has its own now, as your target's to start. Once.
	if not ns.db.aggroColorV1 then
		for _, part in ipairs({ "Name", "Bar", "Border" }) do
			if ns.db["targetColor" .. part] ~= nil then
				ns.db["aggroColor" .. part] = ns.db["targetColor" .. part]
			end
		end
		ns.db.aggroColorV1 = true
	end
	-- The unit under the mouse takes just the marks over its plate now (see
	-- PlateParts): one round or under it goes back to the default.
	local over = { arrow = true, chevron = true, diamond = true, none = true }
	if ns.db.mouseoverMarkStyle ~= nil and not over[ns.db.mouseoverMarkStyle] then
		ns.db.mouseoverMarkStyle = nil
	end
	-- The Buffs/debuffs page's peeks as their defaults in every profile
	-- (debuffs now held until gone, long auras skipped). Once. (Not the
	-- ignore list: that's the player's own. Saved profiles drop theirs, to
	-- follow their base.)
	if not ns.db.buffPeekDefaultsV1 then
		for _, key in ipairs({ "buffPeek", "buffPeekAfterCombat", "buffPeekIgnoreSelf", "debuffPeek",
			"debuffPeekAfterCombat", "debuffPeekUntilGone", "buffPeekIgnoreLong", "buffPeekLongMinutes",
			"buffPeekTime", "debuffPeekTime" }) do
			ns.db[key] = DEFAULTS[key]
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then saved[key] = nil end
			end
		end
		ns.db.buffPeekDefaultsV1 = true
	end
	-- Buffs you cast on yourself peek now, showing just the new one
	-- (Buffs/debuffs page): those two as their defaults in every profile.
	-- Once.
	if not ns.db.buffPeekDefaultsV2 then
		for _, key in ipairs({ "buffPeekIgnoreSelf", "buffPeekOnlyNew" }) do
			ns.db[key] = DEFAULTS[key]
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then saved[key] = nil end
			end
		end
		ns.db.buffPeekDefaultsV2 = true
	end
	-- The debuffs Heroism, Bloodlust and the like leave (Sated, Exhaustion,
	-- Temporal Displacement, Insanity, Fatigued, the Evoker's Exhaustion)
	-- added to the ignore list, where it's set, unless there already (by
	-- ID or name). Once.
	if not ns.db.buffPeekLustV1 then
		local list = ns.db.buffPeekIgnore
		if type(list) == "string" then
			local have = {}
			for entry in list:gmatch("[^,]+") do
				have[entry:match("^%s*(.-)%s*$"):lower()] = true
			end
			for _, id in ipairs(ns.LUST_DEBUFFS) do
				local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
					or GetSpellInfo and GetSpellInfo(id)
				if not have[tostring(id)] and not (name and have[name:lower()]) then
					list = (list:match("^%s*$") and "" or list .. ", ") .. id
				end
			end
			ns.db.buffPeekIgnore = list
		end
		ns.db.buffPeekLustV1 = true
	end
	-- Campfire Nearby (the smoke of a fire somewhere close) added to the
	-- ignore list, where it's set, unless there already. Once.
	if not ns.db.buffPeekCampfireV1 then
		local list = ns.db.buffPeekIgnore
		if type(list) == "string" and not (", " .. list:lower() .. ","):find(",%s*campfire nearby%s*,") then
			ns.db.buffPeekIgnore = (list:match("^%s*$") and "" or list .. ", ") .. "Campfire Nearby"
		end
		ns.db.buffPeekCampfireV1 = true
	end
	-- Heal Vision (Vision page) as its defaults in every profile: its grid
	-- unticked, the options as the defaults say. Once. (Saved profiles drop
	-- theirs, to follow their base.)
	-- Speech from behind you as big and solid as the bubbles overhead now:
	-- its size and opacity still at their old defaults (smaller, fainter)
	-- take the new ones, here and in saved profiles. Ones you'd changed
	-- stay. Once.
	if not ns.db.speechBehindLookV2 then
		local was = { speechBehindScale = 0.9, speechBehindAlpha = 0.8 }
		for key, old in pairs(was) do
			if ns.db[key] == old then ns.db[key] = DEFAULTS[key] end
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" and saved[key] == old then saved[key] = DEFAULTS[key] end
			end
		end
		ns.db.speechBehindLookV2 = true
	end
	-- The Zone card (the lower third) without an outline now: its outline
	-- still following the Default style takes the new default, here and
	-- in saved profiles. Ones you'd set stay. Once.
	if not ns.db.cardZoneOutlineV1 then
		if ns.db.cardOutline_zone == "default" then ns.db.cardOutline_zone = DEFAULTS.cardOutline_zone end
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" and saved.cardOutline_zone == "default" then
				saved.cardOutline_zone = DEFAULTS.cardOutline_zone
			end
		end
		ns.db.cardZoneOutlineV1 = true
	end
	if not ns.db.healVisionDefaultsV1 then
		for key, value in pairs(DEFAULTS) do
			if key:find("^healVision") then
				ns.db[key] = value
				for _, saved in pairs(ns.db.profiles or {}) do
					if type(saved) == "table" then saved[key] = nil end
				end
			end
		end
		ns.db.healVisionDefaultsV1 = true
	end
	-- The Skyriding Cam, out of the dev copy, on to start with: every saved
	-- setting of its back to its default, in every profile. Once. (Nobody
	-- could have picked them: the release had no page, only old defaults
	-- saved, off among them.)
	-- The cursor sweep (Nearby ore, herbs and treasure on WoW Forever) off
	-- again and Keep open's gathering tracking on again, in every profile,
	-- once: v2.0.71 turned the sweep on for everyone, and on Forever it let a
	-- quest area's outline show over the screen.
	if not ns.db.minimapNodesOffV1 then
		for _, key in ipairs({ "minimapNodesByCursor", "minimapKeepOre", "minimapKeepHerbs", "minimapKeepTreasure" }) do
			ns.db[key] = DEFAULTS[key]
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then
					saved[key] = nil
					if type(saved.settings) == "table" then saved.settings[key] = nil end
				end
			end
		end
		ns.db.minimapNodesOffV1 = true
	end
	-- Nearby Dots' In combat too and Except in boxes became its Show in row
	-- (2026-11-13): what you'd changed there moved onto the row's ticks,
	-- once. (Open world is ticked to start with; Instances covers both
	-- Dungeons and Raids.)
	if not ns.db.nodesShowInV1 then
		local key, db = "minimap:dots", ns.db
		local function Tick(list, on)
			if on and type(db[list]) == "table" and db[list][key] == nil then db[list][key] = true end
		end
		Tick("combatShow", db.minimapNodesInCombat == true)
		Tick("cityShow", db.nodesOffInCities == false)
		Tick("instanceShow", db.nodesOffInDungeons == false or db.nodesOffInRaids == false)
		Tick("bgShow", db.nodesOffInPvP == false)
		-- (Keep open's Tracking, its Except in likewise.)
		key = "minimap:tracking"
		Tick("cityShow", db.trackingOffInCities == false)
		Tick("instanceShow", db.trackingOffInDungeons == false or db.trackingOffInRaids == false)
		Tick("bgShow", db.trackingOffInPvP == false)
		db.nodesShowInV1 = true
	end
end

-- (Step 7.)
STEPS[#STEPS + 1] = function()
	if not ns.db.skyrideDefaultsV1 then
		for key, value in pairs(DEFAULTS) do
			if key:find("^skyride") then
				ns.db[key] = value
				for _, saved in pairs(ns.db.profiles or {}) do
					if type(saved) == "table" then
						saved[key] = nil
						if type(saved.settings) == "table" then saved.settings[key] = nil end
					end
				end
			end
		end
		ns.db.skyrideDefaultsV1 = true
	end
	-- Glow on quest objects off to start with now: it turned on the game's
	-- interact key, with an icon and plate over NPCs you face, and players
	-- couldn't find what did it. Off in every profile. Once: tick it again
	-- and it stays.
	if not ns.db.questGlowOffV1 then
		ns.db.questObjectGlow = false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.questObjectGlow = nil
				if type(saved.settings) == "table" then saved.settings.questObjectGlow = nil end
			end
		end
		ns.db.questGlowOffV1 = true
	end
	-- Force reload on Settings exit (Gamepad Frames page) off to start with
	-- now (2026-11-11): the game's freeze closing Settings in gamepad mode
	-- looks fixed (user). Off in every profile. Once: tick it again and it
	-- stays.
	if not ns.db.forceReloadOffV1 then
		ns.db.forceReloadOnSettingsExit = false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.forceReloadOnSettingsExit = nil
				if type(saved.settings) == "table" then saved.settings.forceReloadOnSettingsExit = nil end
			end
		end
		ns.db.forceReloadOffV1 = true
	end
	-- Hide the minimap button in gamepad mode, the same page's other guard
	-- against that freeze: off to start with too (2026-11-11). Once.
	if not ns.db.hideMinimapButtonGamepadOffV1 then
		ns.db.hideMinimapButtonGamepad = false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.hideMinimapButtonGamepad = nil
				if type(saved.settings) == "table" then saved.settings.hideMinimapButtonGamepad = nil end
			end
		end
		ns.db.hideMinimapButtonGamepadOffV1 = true
	end
	-- Nameplates: Friendly players' and Friendly minions' Grouped (in the
	-- Location dropdown) off to start with now (2026-11-12): it showed every
	-- friendly player's plate in a party, and Ctrl+V couldn't hide them
	-- (CurseForge report). Off in every profile. Once: tick it again and it
	-- stays.
	if not ns.db.plateGroupFriendsOffV1 then
		for _, key in ipairs({ "plateGroupFriends", "plateGroupFriendlyMinions" }) do
			ns.db[key] = false
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then
					saved[key] = nil
					if type(saved.settings) == "table" then saved.settings[key] = nil end
				end
			end
		end
		ns.db.plateGroupFriendsOffV1 = true
	end
	-- Interface Recolor's raid Health bars on to start with now (2026-11-10):
	-- it began off, which saved off without anyone choosing it. Once: untick
	-- it again and it stays.
	if not ns.db.irRaidHealthOnV1 then
		ns.db.irRaidHealth = true
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.irRaidHealth = nil
				if type(saved.settings) == "table" then saved.settings.irRaidHealth = nil end
			end
		end
		ns.db.irRaidHealthOnV1 = true
	end
	-- Interface Recolor's XP bar color off to start with now (2026-11-10): it
	-- began on, which saved on without anyone choosing it. Once: tick it again
	-- and it stays.
	if not ns.db.xpBarsOffV1 then
		ns.db.xpBars = false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.xpBars = nil
				if type(saved.settings) == "table" then saved.settings.xpBars = nil end
			end
		end
		ns.db.xpBarsOffV1 = true
	end
	-- Quest item button off to start with now (2026-11-09). Off in every
	-- profile. Once: tick it again and it stays.
	if not ns.db.questItemButtonOffV1 then
		ns.db.questItemButton = false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.questItemButton = nil
				if type(saved.settings) == "table" then saved.settings.questItemButton = nil end
			end
		end
		ns.db.questItemButtonOffV1 = true
	end
	-- (campfireStandUpOffV1, 2026-11-09, turned the campfire stand-up off
	-- once for everyone after it stood a player up as they sat to eat. It's
	-- on to start with again since 2026-11-12, with eating, casting and
	-- crafting left alone; the old turn-off no longer runs, so new players
	-- keep it on.)
	-- Back on once for everyone it was turned off for (2026-11-12): eating,
	-- casting and crafting no longer get cut short. Once: untick it and it
	-- stays off.
	if not ns.db.campfireStandUpOnV2 then
		ns.db.campfireStandUp = true
		for _, saved in pairs(type(ns.db.profiles) == "table" and ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.campfireStandUp = nil
				if type(saved.settings) == "table" then saved.settings.campfireStandUp = nil end
			end
		end
		ns.db.campfireStandUpOnV2 = true
	end
	-- Boss defeated's card waits till after the fight now (it showed in the
	-- middle of it, with adds still up). Once: pick Show again and it stays.
	if not ns.db.bossDownWaitV1 then
		if ns.db.cardFight_bossDown == "show" then ns.db.cardFight_bossDown = "wait" end
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.cardFight_bossDown = nil
				if type(saved.settings) == "table" then saved.settings.cardFight_bossDown = nil end
			end
		end
		ns.db.bossDownWaitV1 = true
	end
	-- Your target's name (Nameplates page, Target: Names) up always in the
	-- Cinema profile now: it goes as your profile has it, and saved profiles
	-- drop theirs, to follow their base. Once.
	if not ns.db.targetNameCinemaV1 then
		local base = ns.ProfileBase and ns.ProfileBase() or DEFAULTS
		ns.db.nameAlwaysYourTarget = base.nameAlwaysYourTarget and true or false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then saved.nameAlwaysYourTarget = nil end
		end
		ns.db.targetNameCinemaV1 = true
	end
	-- The copy chat button off to start with now: other chat addons have
	-- their own. Off in every profile. Once: tick it again and it stays.
	if not ns.db.chatCopyOffV1 then
		ns.db.chatCopyButton = false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.chatCopyButton = nil
				if type(saved.settings) == "table" then saved.settings.chatCopyButton = nil end
			end
		end
		ns.db.chatCopyOffV1 = true
	end
	-- Keep open while tracking herbs, minerals or treasure on to start with
	-- now: WoW Forever's November update stopped Reveal finding ore and herbs
	-- (NodeSweep.lua). On in every profile. Once: untick it and it stays.
	if not ns.db.keepGatheringOnV1 then
		ns.db.minimapKeepGathering = true
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.minimapKeepGathering = nil
				if type(saved.settings) == "table" then saved.settings.minimapKeepGathering = nil end
			end
		end
		ns.db.keepGatheringOnV1 = true
	end
	-- Keep open's two tracking boxes became one Tracking dropdown, a tick per
	-- kind: gathering's tick goes to ore, herbs and treasure, creatures or
	-- fish's to each creature kind and fish, here and in saved profiles. Once.
	if not ns.db.trackingKindsV1 then
		local GATHERING = { "Ore", "Herbs", "Treasure" }
		local CREATURES = { "Humanoids", "Fish", "Beasts", "Demons", "Undead", "Dragonkin", "Elementals",
			"Giants", "Hidden" }
		local function Split(t)
			if type(t) ~= "table" then return end
			for old, kinds in pairs({ minimapKeepGathering = GATHERING, minimapKeepCreatures = CREATURES }) do
				if t[old] ~= nil then
					for _, kind in ipairs(kinds) do t["minimapKeep" .. kind] = t[old] and true or false end
					t[old] = nil
				end
			end
		end
		Split(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				Split(saved)
				Split(saved.settings)
			end
		end
		ns.db.trackingKindsV1 = true
	end
	-- The Tooltips page's Level row split in two, for friends and enemies:
	-- the enemies' row starts as the Level row was set, here and in saved
	-- profiles. Once.
	if not ns.db.tooltipLevelEnemyV1 then
		local function Copy(t)
			for _, column in ipairs({ "First", "Later" }) do
				if t["tooltipShowLevel" .. column] ~= nil then
					t["tooltipShowLevelEnemy" .. column] = t["tooltipShowLevel" .. column]
				end
			end
		end
		Copy(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				Copy(saved)
				if type(saved.settings) == "table" then Copy(saved.settings) end
			end
		end
		ns.db.tooltipLevelEnemyV1 = true
	end
	-- The dev copy starts with it on, now its tick shows there too. Once: untick
	-- it and it stays.
	if ns.isDev and not ns.db.chatCopyDevOnV1 then
		ns.db.chatCopyButton = true
		ns.db.chatCopyDevOnV1 = true
	end
	-- Open windows in the middle of the screen off to start with now: players
	-- want the game's own window spots, and couldn't find what moved them.
	-- Off in every profile. Once: tick it again and it stays.
	if not ns.db.centerPanelsOffV1 then
		ns.db.centerPanels = false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.centerPanels = nil
				if type(saved.settings) == "table" then saved.settings.centerPanels = nil end
			end
		end
		ns.db.centerPanelsOffV1 = true
	end
	-- Bubble position's Opposite clicked was the default until v2.0.27, and
	-- it stayed saved: the game's quest window jumped across the screen, over
	-- the quest tracker, and players couldn't find what did it. Back to
	-- Default in every profile (Over the head is left alone). Once: pick it
	-- again and it stays.
	if not ns.db.questTalkPlaceFixedV1 then
		if ns.db.questTalkPlace == "opposite" then ns.db.questTalkPlace = "fixed" end
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				if saved.questTalkPlace == "opposite" then saved.questTalkPlace = nil end
				if type(saved.settings) == "table" and saved.settings.questTalkPlace == "opposite" then
					saved.settings.questTalkPlace = nil
				end
			end
		end
		ns.db.questTalkPlaceFixedV1 = true
	end
end

-- (Step 8.)
STEPS[#STEPS + 1] = function()
	-- Health & Resources' grid (2026-11-13): Not full by frame, health and
	-- power apart (nfHealth... and nfPower...), from the player frame's one
	-- tick (portraitWhenNotFull) and the personal resource display's
	-- (prdWhenNotFull; for a day, one per bar: prd...NotFull). ElvUI's power
	-- bar went by the player frame's; our mana bar's Wait at pull by the
	-- power bar's. Not full now counts any time: players from before keep
	-- "only after a fight". Every profile. Once.
	if not ns.db.notFullGridV2 then
		local existing = ns.db.notFullGridV1 or ns.db.petWhenNotFullOffV1 ~= nil or ns.db.profileChosen == true
		local CARRY = {
			{ "prdHealthNotFull", { "nfHealthPrd" } },
			{ "prdPowerNotFull", { "nfPowerPrdPower" } },
			{ "prdManaNotFull", { "nfPowerPrdMana" } },
			{ "powerNotFullElvUI", { "nfPowerElvUI" } },
			{ "prdWhenNotFull", { "nfHealthPrd", "nfPowerPrdPower", "nfPowerPrdMana" } },
			{ "portraitWhenNotFull", { "nfHealthPlayer", "nfPowerPlayer", "nfPowerElvUI" } },
		}
		local function Carry(t)
			if type(t) ~= "table" then return end
			for _, carry in ipairs(CARRY) do
				local value = t[carry[1]]
				if value ~= nil then
					for _, key in ipairs(carry[2]) do
						if t[key] == nil then t[key] = value end
					end
					t[carry[1]] = nil
				end
			end
			if t.fightWaitPower ~= nil and t.fightWaitMana == nil then t.fightWaitMana = t.fightWaitPower end
			if existing and t.notFullAfterFight == nil then t.notFullAfterFight = true end
		end
		Carry(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				Carry(type(saved.settings) == "table" and saved.settings or saved)
			end
		end
		ns.db.notFullGridV2 = true
	end
	-- The pet frame kept up until its health is full (Personal Resources)
	-- off to start with now: off in every profile. Once.
	if not ns.db.petWhenNotFullOffV1 then
		ns.db.petWhenNotFull = false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then saved.petWhenNotFull = nil end
		end
		ns.db.petWhenNotFullOffV1 = true
	end
	-- Health & Resources as shares (2026-11-13): each row's Show below
	-- (pr...) from its Not full tick (on: the default, 95%) or, off, its Low mana tick
	-- (the Low mana share, 25% to start with; off: 0%). The pet frame's
	-- Not full: 99% or 0%. Every profile. Once.
	if not ns.db.prThresholdsV1 then
		local CARRY = {
			{ "prHealthPlayer", "nfHealthPlayer" },
			{ "prPowerPlayer", "nfPowerPlayer", "lowManaPortrait" },
			{ "prHealthPrd", "nfHealthPrd" },
			{ "prPowerPrd", "nfPowerPrdPower", "lowManaPower" },
			{ "prPowerMana", "nfPowerPrdMana", "lowManaMana" },
			{ "prPowerElvUI", "nfPowerElvUI", "lowManaElvUI" },
		}
		local function Carry(t)
			if type(t) ~= "table" then return end
			local share = t.lowManaShare
			if share == nil then share = 0.25 end
			for _, carry in ipairs(CARRY) do
				local notFull, low = t[carry[2]], carry[3] and t[carry[3]]
				-- (Only where something was changed: else the new default.)
				if t[carry[1]] == nil and (notFull ~= nil or low ~= nil or carry[3] and t.lowManaShare ~= nil) then
					if notFull ~= false then
						t[carry[1]] = DEFAULTS[carry[1]] or 0.95 -- (on, as most were: the start)
					else
						t[carry[1]] = carry[3] and low ~= false and share > 0 and share or 0
					end
				end
				t[carry[2]] = nil
				if carry[3] then t[carry[3]] = nil end
			end
			if t.petWhenNotFull ~= nil then
				if t.prPetHealth == nil then t.prPetHealth = t.petWhenNotFull and 0.99 or 0 end
				t.petWhenNotFull = nil
			end
			t.lowManaShare = nil
		end
		Carry(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				Carry(type(saved.settings) == "table" and saved.settings or saved)
			end
		end
		ns.db.prThresholdsV1 = true
	end
	-- Show below's 95% (saved by the carry above in v2.0.97, the default
	-- then) to Not full (99%), the default since: every share of exactly
	-- 95% in every profile. Once.
	if not ns.db.prNotFullV1 then
		local function Lift(t)
			if type(t) ~= "table" then return end
			for key, value in pairs(t) do
				if type(key) == "string" and (key:find("^prHealth") or key:find("^prPower"))
					and type(value) == "number" and math.abs(value - 0.95) < 1e-6 then
					t[key] = 0.99
				end
			end
		end
		Lift(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				Lift(type(saved.settings) == "table" and saved.settings or saved)
			end
		end
		ns.db.prNotFullV1 = true
	end
	-- Health & Resources' Keep up grid (2026-11-15): Not full: only during
	-- Calm Timer per row (Show below < 100% Calm, saved 0.995) instead of
	-- one tick for the page: ticked, every row at < 100% (99%, or the
	-- default) becomes < 100% Calm. Wait at pull one tick for every row
	-- (fightWaitPull): on if any row's was (a row left alone: its default,
	-- on for the power and mana bars). Mana text one tick for both bars
	-- (manaAfterCast): on if either was. Every profile. Once.
	-- (A Keep up row's own share, its In combat column's key: not one of its
	-- columns' or links' named after it, prHealthPlayerCalm... The two
	-- updates below would take those for rows of their own.)
	function ns.IsPrRowKey(key)
		return type(key) == "string" and (key:find("^prHealth") or key:find("^prPower") or key:find("^prPet"))
			and not (key:find("Calm$") or key:find("Always$") or key:find("Link")) and true or false
	end
	if not ns.db.prCalmRowsV1 then
		local WAITS = { fightWaitPower = true, fightWaitMana = true, fightWaitHealth = false, fightWaitPortrait = false }
		local function Shares(t, Each)
			local seen = {}
			for key, value in pairs(t) do
				if ns.IsPrRowKey(key) then
					seen[key] = true
					Each(key, value)
				end
			end
			for key in pairs(DEFAULTS) do
				if not seen[key] and ns.IsPrRowKey(key) then
					Each(key, nil)
				end
			end
		end
		local function Carry(t)
			if type(t) ~= "table" then return end
			if t.notFullAfterFight == true then
				Shares(t, function(key, value)
					local share = value
					if share == nil then share = DEFAULTS[key] end
					if type(share) == "number" and math.abs(share - 0.99) < 1e-6 then t[key] = 0.995 end
				end)
			end
			t.notFullAfterFight = nil
			local saved, on = false, false
			for key, default in pairs(WAITS) do
				if t[key] ~= nil then saved = true end
				local value = t[key]
				if value == nil then value = default end
				if value then on = true end
			end
			if saved then
				if t.fightWaitPull == nil then t.fightWaitPull = on end
				for key in pairs(WAITS) do t[key] = nil end
			end
			if t.manaAfterDisplay ~= nil or t.manaAfterPortrait ~= nil then
				if t.manaAfterCast == nil then t.manaAfterCast = t.manaAfterDisplay == true or t.manaAfterPortrait == true end
				t.manaAfterDisplay, t.manaAfterPortrait = nil, nil
			end
		end
		Carry(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				Carry(type(saved.settings) == "table" and saved.settings or saved)
			end
		end
		ns.db.prCalmRowsV1 = true
	end
	-- Health & Resources' Keep up columns (2026-11-15): In combat, After
	-- combat and Always in place of one Show below. A saved share fills
	-- all three, linked (as it worked: any time); < 100% Calm (0.995)
	-- becomes After combat < 100%, the others Off, unlinked. Opacity while
	-- hidden (prAlpha...) and Fade range gone. Every profile. Once.
	if not ns.db.prColumnsV1 then
		local function Carry(t)
			if type(t) ~= "table" then return end
			local shares, gone = {}, {}
			for key, value in pairs(t) do
				if type(key) == "string" then
					if ns.IsPrRowKey(key) and type(value) == "number" and t[key .. "Calm"] == nil then
						shares[key] = value
					elseif key:find("^prAlpha") or key == "prFadeRange" then
						gone[#gone + 1] = key
					end
				end
			end
			for key, value in pairs(shares) do
				if math.abs(value - 0.995) < 1e-6 then
					t[key], t[key .. "Calm"], t[key .. "Always"] = 0, 0.99, 0
					t[key .. "LinkCalm"], t[key .. "LinkAlways"] = false, false
				else
					t[key .. "Calm"], t[key .. "Always"] = value, value
					t[key .. "LinkCalm"], t[key .. "LinkAlways"] = true, true
				end
			end
			for _, key in ipairs(gone) do t[key] = nil end
		end
		Carry(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				Carry(type(saved.settings) == "table" and saved.settings or saved)
			end
		end
		ns.db.prColumnsV1 = true
	end
	-- Treat Player Frame and PRD the same gone (2026-11-15): each frame
	-- its own Keep up rows, profiles pick which is kept up. Where it was
	-- on (or never set: on), the PRD's rows take the player frame's, so
	-- nothing changes. Every profile. Once.
	if not ns.db.prUnlinkedV1 then
		local PAIRS = { { "prHealthPrd", "prHealthPlayer" }, { "prPowerPrd", "prPowerPlayer" } }
		local SUFFIXES = { "", "Calm", "Always", "LinkCalm", "LinkAlways" }
		local function Carry(t)
			if type(t) ~= "table" then return end
			if t.prLinked ~= false then
				for _, pair in ipairs(PAIRS) do
					for _, suffix in ipairs(SUFFIXES) do
						t[pair[1] .. suffix] = t[pair[2] .. suffix]
					end
				end
			end
			t.prLinked = nil
		end
		Carry(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				Carry(type(saved.settings) == "table" and saved.settings or saved)
			end
		end
		ns.db.prUnlinkedV1 = true
	end
	-- Heal Vision's Show below health at 99% ("any damage") to 99.9%: its
	-- box shows that step as < 100% now, so 99.5% health counts too. Every
	-- role's and every profile's. Once.
	if not ns.db.healVisionNotFullV1 then
		local function Lift(t)
			if type(t) ~= "table" then return end
			for key, value in pairs(t) do
				if type(key) == "string" and key:find("^healVision%a*Below") and type(value) == "number"
					and math.abs(value - 0.99) < 1e-6 then
					t[key] = 0.999
				end
			end
		end
		Lift(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				Lift(type(saved.settings) == "table" and saved.settings or saved)
			end
		end
		ns.db.healVisionNotFullV1 = true
	end
end

-- (Step 9.)
STEPS[#STEPS + 1] = function()
	-- Off-screen plates in CineMode off to start with now (the game's head
	-- names flashed at the screen's edge): off in every profile. Once.
	if not ns.db.plateOffscreenOffV1 then
		ns.db.plateShowOffscreen = false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.plateShowOffscreen = nil
				if type(saved.settings) == "table" then saved.settings.plateShowOffscreen = nil end
			end
		end
		ns.db.plateOffscreenOffV1 = true
	end
	-- The letterbox's height and opacity moved to the Style hub's Letterbox
	-- page: a height or opacity of your own turns it on, to keep them. Once.
	if not ns.db.letterboxStyleV1 then
		if (ns.db.letterboxSize or DEFAULTS.letterboxSize) ~= DEFAULTS.letterboxSize
			or (ns.db.letterboxAlpha or 1) ~= DEFAULTS.letterboxAlpha then
			ns.db.letterboxStyle = true
		end
		ns.db.letterboxStyleV1 = true
	end
	-- The chat bubbles' look moved to the Style hub's Chat bubbles page:
	-- Text only or a text size of your own (with the UI Manager's page on,
	-- as they needed) carry over. Once.
	if not ns.db.bubblesStyleV1 then
		local db = ns.db
		if db.handleBubbles and (db.bubblesTextOnly or (db.bubblesTextScale or 1) ~= 1) then
			db.bubblesStyle = true
			if db.bubblesTextOnly then
				db.bubblesBack = "none"
				if db.bubblesTextOutline ~= false then db.bubblesOutline = db.bubblesTextOutlineSize or 2 end
			end
		end
		db.bubblesStyleV1 = true
	end
	-- Quest talk (Quest Vision's Custom dialogue frames) is off to start with
	-- now, on in the Cinema profile: it goes as your profile has it, and
	-- saved profiles drop theirs, to follow their base. Once.
	if not ns.db.questTalkProfileV1 then
		local base = ns.ProfileBase and ns.ProfileBase() or DEFAULTS
		ns.db.questTalk = base.questTalk and true or false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then saved.questTalk = nil end
		end
		ns.db.questTalkProfileV1 = true
	end
	-- Quest talk is off in every profile for now (being fixed): turn it
	-- off once, saved profiles too.
	if not ns.db.questTalkOffV1 then
		ns.db.questTalk = false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then saved.questTalk = nil end
		end
		ns.db.questTalkOffV1 = true
	end
	-- Custom dialogue frames off in every profile, Cinema too (it no longer
	-- turns them on): off once, saved profiles too. Tick it again and it stays.
	if not ns.db.questTalkOffV2 then
		ns.db.questTalk = false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.questTalk = false
				if type(saved.settings) == "table" then saved.settings.questTalk = false end
			end
		end
		for _, point in pairs(ns.db.profileResetPoints or {}) do
			if type(point) == "table" then point.questTalk = false end
		end
		ns.db.questTalkOffV2 = true
	end
	-- Combat Vision is off to start with, on in the Cinema profile: it goes
	-- as your profile has it, and saved profiles drop theirs. Once.
	if not ns.db.combatVisionProfileV1 then
		local base = ns.ProfileBase and ns.ProfileBase() or DEFAULTS
		ns.db.combatVision = base.combatVision and true or false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then saved.combatVision = nil end
		end
		ns.db.combatVisionProfileV1 = true
	end
	-- Story Vision gathers the time of day, attack and death banner text. Its
	-- switch goes as your profile has it (off in Subtle), saved profiles drop
	-- theirs; the time of day's changes, ticked with its login title until
	-- now, get a tick of their own as that one is. Once.
	if not ns.db.storyVisionV1 then
		local base = ns.ProfileBase and ns.ProfileBase() or DEFAULTS
		ns.db.storyVision = base.storyVision ~= false
		ns.db.timeOfDayChange = ns.db.timeOfDayMessage ~= false
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.storyVision = nil
				if saved.timeOfDayMessage ~= nil then saved.timeOfDayChange = saved.timeOfDayMessage end
			end
		end
		ns.db.storyVisionV1 = true
	end
	-- Story Vision's rows are all on in Balanced and Cinema now (Cinema's look
	-- no longer turns the time of day off), the death banner only in Cinema
	-- (YOU DIED): each row goes as your profile has it. Once.
	if not ns.db.storyVisionRowsV1 then
		local base = ns.ProfileBase and ns.ProfileBase() or DEFAULTS
		for _, key in ipairs({ "storyRecap", "timeOfDayMessage", "timeOfDayChange", "chatAttackAlert",
				"deathBannerStyle" }) do
			if base[key] ~= nil then ns.db[key] = base[key] end
		end
		ns.db.storyVisionRowsV1 = true
	end
	-- The Zone name card is a chapter line now (the zone under its line):
	-- the Title it started on goes over, saved profiles too. Once.
	if not ns.db.storyZoneStyleV1 then
		if ns.db.storyZoneStyle == "title" then ns.db.storyZoneStyle = "chapter" end
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" and saved.storyZoneStyle == "title" then saved.storyZoneStyle = "chapter" end
		end
		ns.db.storyZoneStyleV1 = true
	end
	-- The Style pages' shared settings (bar texture, font, outline) follow
	-- the Style hub's General page now: everyone's start on General, saved
	-- profiles dropping theirs. Once.
	if not ns.db.styleGeneralV1 then
		for key in pairs(ns.SHARED_STYLE or {}) do
			ns.db[key] = DEFAULTS[key]
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then saved[key] = nil end
			end
		end
		ns.db.styleGeneralV1 = true
	end
	-- The Style hub's pages are on to start with now (their defaults look
	-- as the page off did: the switch is there to compare). Once.
	if not ns.db.stylePagesOnV1 then
		for _, key in ipairs({ "letterboxStyle", "questItemStyle", "rollStyle", "plateCastStyle", "bubblesStyle" }) do
			ns.db[key] = true
		end
		ns.db.stylePagesOnV1 = true
	end
	-- Subtle's bars come with CineMode now: ns.SubtleCineBars. Once, live and saved.
	if not ns.db.subtleCineBarsV1 then
		if (ns.db.liveProfile or ns.db.profile) == "Subtle" then ns.SubtleCineBars(ns.db) end
		ns.SubtleCineBars(ns.db.profiles and ns.db.profiles.Subtle)
		ns.db.subtleCineBarsV1 = true
	end
	-- Subtle's tint comes with CineMode too, and the tint's strength is full. Once.
	if not ns.db.fullTintV1 then
		if (ns.db.liveProfile or ns.db.profile) == "Subtle" then ns.SubtleCineEffect(ns.db, "tint") end
		ns.SubtleCineEffect(ns.db.profiles and ns.db.profiles.Subtle, "tint")
		ns.FullTint(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do ns.FullTint(saved) end
		ns.db.fullTintV1 = true
	end
	-- And its vignette and weather. Once.
	if not ns.db.subtleCineEffectsV1 then
		for _, effect in ipairs({ "vignette", "weather" }) do
			if (ns.db.liveProfile or ns.db.profile) == "Subtle" then ns.SubtleCineEffect(ns.db, effect) end
			ns.SubtleCineEffect(ns.db.profiles and ns.db.profiles.Subtle, effect)
		end
		ns.db.subtleCineEffectsV1 = true
	end
	-- Subtle's flights, teleports and AFK come with CineMode: ns.SubtleCineTravel. Once.
	if not ns.db.subtleCineTravelV1 then
		if (ns.db.liveProfile or ns.db.profile) == "Subtle" then ns.SubtleCineTravel(ns.db) end
		ns.SubtleCineTravel(ns.db.profiles and ns.db.profiles.Subtle)
		ns.db.subtleCineTravelV1 = true
	end
	-- Scenes a profile had off keep their cameras, ticked off: ns.ScenesOffKeepCameras. Once.
	if not ns.db.scenesOffKeepCamerasV1 then
		if not ns.newInstall then
			ns.ScenesOffKeepCameras(ns.db)
			for _, saved in pairs(ns.db.profiles or {}) do ns.ScenesOffKeepCameras(saved) end
			for _, saved in pairs(ns.db.profileResetPoints or {}) do ns.ScenesOffKeepCameras(saved) end
		end
		ns.db.scenesOffKeepCamerasV1 = true
	end
	-- Balanced's resting, logout and death cameras: ns.BalancedMoreScenes. Once.
	if not ns.db.balancedMoreScenesV1 then
		if (ns.db.liveProfile or ns.db.profile) == "Balanced" then ns.BalancedMoreScenes(ns.db) end
		ns.BalancedMoreScenes(ns.db.profiles and ns.db.profiles.Balanced)
		ns.db.balancedMoreScenesV1 = true
	end
	-- Always show tanks (healVisionTanks) is now the tank slider at 100%:
	-- unticked, tanks went by the members' health, so they still do. Once,
	-- in every profile.
	if not ns.db.healVisionTankBelowV1 then
		local function TanksSlider(t)
			if type(t) ~= "table" then return end
			if t.healVisionTanks == false then
				t.healVisionTankBelow = t.healVisionShowBelow or DEFAULTS.healVisionShowBelow
			end
			t.healVisionTanks = nil
		end
		TanksSlider(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do TanksSlider(saved) end
		ns.db.healVisionTankBelowV1 = true
	end
	-- Always show your target (healVisionTarget) is now the target opacity
	-- slider: unticked, your target faded as their kind does, which 0% does.
	-- Once, in every profile.
	if not ns.db.healVisionTargetAlphaV1 then
		local function TargetSlider(t)
			if type(t) ~= "table" then return end
			if t.healVisionTarget == false then t.healVisionTargetAlpha = 0 end
			t.healVisionTarget = nil
			t.healVisionTargetBelow = nil -- (an earlier try, never released)
		end
		TargetSlider(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do TargetSlider(saved) end
		ns.db.healVisionTargetBelowV1 = nil
		ns.db.healVisionTargetAlphaV1 = true
	end
	-- No CineMode column on the grids that only act in CineMode: its ticks
	-- go onto Always (ns.CineTicksToAlways). Once, in every profile.
	if not ns.db.cineTicksToAlwaysV1 then
		ns.CineTicksToAlways(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do ns.CineTicksToAlways(saved) end
		for _, saved in pairs(ns.db.profileResetPoints or {}) do ns.CineTicksToAlways(saved) end
		ns.db.cineTicksToAlwaysV1 = true
	end
	-- The effects' rows too (ns.EffectCineTicksToAlways). Once, in every profile.
	if not ns.db.effectCineTicksToAlwaysV1 then
		ns.EffectCineTicksToAlways(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do ns.EffectCineTicksToAlways(saved) end
		for _, saved in pairs(ns.db.profileResetPoints or {}) do ns.EffectCineTicksToAlways(saved) end
		ns.db.effectCineTicksToAlwaysV1 = true
	end
	-- Tanks and pets have an opacity of their own now: each starts as the
	-- one opacity was. Once, in every profile.
	if not ns.db.healVisionKindAlphaV1 then
		local function KindAlpha(t)
			if type(t) ~= "table" or t.healVisionMinAlpha == nil then return end
			t.healVisionTankAlpha = t.healVisionTankAlpha or t.healVisionMinAlpha
			t.healVisionPetAlpha = t.healVisionPetAlpha or t.healVisionMinAlpha
		end
		KindAlpha(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do KindAlpha(saved) end
		ns.db.healVisionKindAlphaV1 = true
	end
	-- Healers have settings of their own now, apart from damage: they
	-- start as those were. Once, in every profile.
	if not ns.db.healVisionHealersV1 then
		local function Healers(t)
			if type(t) ~= "table" then return end
			t.healVisionHealerBelow = t.healVisionHealerBelow or t.healVisionShowBelow
			t.healVisionHealerAlpha = t.healVisionHealerAlpha or t.healVisionMinAlpha
		end
		Healers(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do Healers(saved) end
		ns.db.healVisionHealersV1 = true
	end
	-- The Plate parts' Buffs/debuffs row (Part Auras) was split into Buffs
	-- and Debuffs rows: each takes its boxes, in every profile.
	local function SplitAuras(t)
		local keys = {}
		for key in pairs(t) do
			if type(key) == "string" and key:match("^plate.+PartAuras$") then
				keys[#keys + 1] = key
			end
		end
		for _, key in ipairs(keys) do
			local base = key:sub(1, -6)
			for _, part in ipairs({ "Buffs", "Debuffs" }) do
				if t[base .. part] == nil then
					t[base .. part] = t[key]
				end
			end
			t[key] = nil
		end
	end
	SplitAuras(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then SplitAuras(saved) end
	end
end

-- (Step 10.)
STEPS[#STEPS + 1] = function()
	-- "Always show your target's nameplate" (plateTarget) was split into a
	-- switch each for enemy and friendly targets, then into Enemy Target and
	-- Friendly Target rows in the Nameplates grid: one switch again, on if
	-- any of those was.
	local targetSeen, targetOn = false, false
	local oldTargetKeys = { "plateAlwaysTarget", "plateAlwaysTargetEnemy", "plateAlwaysTargetFriendly" }
	for _, row in ipairs({ "EnemyTarget", "FriendlyTarget" }) do
		for _, prefix in ipairs({ "plateCombat", "plateCombatPvP", "plateCinematic", "plateGroup", "plateAlways",
			"plateInCities", "plateInDungeons", "plateInRaids", "plateInPvP", "plateInBGs", "plateInInstances" }) do
			oldTargetKeys[#oldTargetKeys + 1] = prefix .. row
		end
	end
	for _, key in ipairs(oldTargetKeys) do
		if ns.db[key] ~= nil then
			targetSeen = true
			targetOn = targetOn or ns.db[key] and true
			ns.db[key] = nil
		end
	end
	if targetSeen and ns.db.plateTarget == nil then
		ns.db.plateTarget = targetOn
	end
	-- ...and that switch, "Always show group members' nameplates" (with
	-- "Their minions") and "Always show your pet's nameplate" became rows of
	-- the grid again: their Always boxes, as the switches were. In every
	-- profile too.
	local function UnitRowsFromSwitches(t)
		if t.plateTarget ~= nil then t.plateAlwaysMyTarget = t.plateTarget end
		if t.plateOwnPet ~= nil then t.plateAlwaysMyPet = t.plateOwnPet end
		if t.plateGroupMembers ~= nil then t.plateAlwaysGroupMembers = t.plateGroupMembers end
		if t.plateGroupMembers == false then
			t.plateAlwaysGroupMinions = false
		elseif t.plateGroupMemberMinions ~= nil then
			t.plateAlwaysGroupMinions = t.plateGroupMemberMinions
		end
		t.plateTarget, t.plateOwnPet, t.plateGroupMembers, t.plateGroupMemberMinions = nil, nil, nil, nil
	end
	UnitRowsFromSwitches(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then UnitRowsFromSwitches(saved) end
	end
	-- The Nameplates page's Cities column joined Open world (ticked there
	-- wherever either was), and Dungeons and Raids became one column
	-- (ticked wherever either was). Its BGs column came back from PvP:
	-- ticked where PvP is, to start with. (Its Always column, gone for a
	-- while, is back as its own setting.)
	local plateRows = {}
	for _, kind in ipairs(ns.PLATE_KINDS) do
		plateRows[#plateRows + 1] = { "plate", "plateCinematic", kind }
	end
	for _, group in ipairs(ns.NAME_GROUPS) do
		plateRows[#plateRows + 1] = { "name", "nameKeep", group.key }
	end
	for _, row in ipairs(plateRows) do
		local prefix, open, key = row[1], row[2], row[3]
		local head = prefix .. "In"
		if ns.db[head .. "Cities" .. key] then ns.db[open .. key] = true end
		ns.db[head .. "Cities" .. key] = nil
		if ns.db[head .. "BGs" .. key] == nil and ns.db[head .. "PvP" .. key] ~= nil then
			ns.db[head .. "BGs" .. key] = ns.db[head .. "PvP" .. key]
		end
		local dungeons, raids = ns.db[head .. "Dungeons" .. key], ns.db[head .. "Raids" .. key]
		if dungeons ~= nil or raids ~= nil then
			ns.db[head .. "Instances" .. key] = (dungeons or raids) and true or false
		end
		ns.db[head .. "Dungeons" .. key], ns.db[head .. "Raids" .. key] = nil, nil
	end
	-- Enemy NPCs (with Minor) split into Hostile NPCs (still "EnemyNPCs"
	-- and "EnemyMinor") and Neutral NPCs (with a Minor of their own): the
	-- new rows start out ticked wherever the old ones were. In every
	-- profile too.
	local function NeutralFromHostile(t)
		t.plateNeutralNPCsV1 = nil
		if t.plateNeutralRowsV1 then
			return
		end
		for _, prefix in ipairs({ "plateAlways", "plateCombat", "plateCombatPvP", "plateCinematic", "plateGroup",
			"plateInPvP", "plateInBGs", "plateInInstances" }) do
			for old, new in pairs({ EnemyNPCs = "NeutralNPCs", EnemyMinor = "NeutralMinor" }) do
				if t[prefix .. old] ~= nil and t[prefix .. new] == nil then
					t[prefix .. new] = t[prefix .. old]
				end
			end
		end
		t.plateNeutralRowsV1 = true
	end
	-- ...and Your Target into the Target Nameplate grid's rows (enemy,
	-- neutral and friendly, players and NPCs apart): each starts out ticked
	-- wherever it was, and with Always ticked whatever it was.
	local OLD_TARGET_ROWS = {
		MyTarget = ns.PLATE_TARGET_ROWS,
		MyEnemyTarget = { "MyEnemyPlayerTarget", "MyEnemyNPCTarget" },
		MyNeutralTarget = { "MyNeutralPlayerTarget", "MyNeutralNPCTarget" },
		MyFriendlyTarget = { "MyFriendlyPlayerTarget", "MyFriendlyNPCTarget" },
	}
	local function TargetRowsFromMyTarget(t)
		for _, prefix in ipairs({ "plateAlways", "plateCombat", "plateCombatPvP", "plateCinematic", "plateGroup",
			"plateInPvP", "plateInBGs", "plateInInstances" }) do
			for old, rows in pairs(OLD_TARGET_ROWS) do
				if t[prefix .. old] ~= nil then
					for _, row in ipairs(rows) do
						if t[prefix .. row] == nil then t[prefix .. row] = t[prefix .. old] end
					end
					t[prefix .. old] = nil
				end
			end
		end
		if not t.plateTargetRowsV1 then
			for _, row in ipairs(ns.PLATE_TARGET_ROWS) do
				t["plateAlways" .. row] = true
			end
			t.plateTargetRowsV1 = true
		end
	end
	-- The Names grid's NPC Names row split into Hostile NPCs and Friendly
	-- NPCs, then Neutral NPCs apart from hostile ones: each starts out ticked
	-- wherever the row it came from was. In every profile too.
	local NAME_ROW_PREFIXES = { "nameAlways", "nameGroup", "nameCombat", "nameCombatPvP", "nameKeep",
		"nameInInstances", "nameInPvP", "nameInBGs" }
	local function NPCNamesSplit(t)
		if not t.nameNPCsSplitV1 then
			for _, prefix in ipairs(NAME_ROW_PREFIXES) do
				if t[prefix .. "NPCs"] ~= nil then
					for _, row in ipairs({ "HostileNPCs", "NeutralNPCs", "FriendlyNPCs" }) do
						if t[prefix .. row] == nil then t[prefix .. row] = t[prefix .. "NPCs"] end
					end
					t[prefix .. "NPCs"] = nil
				end
			end
			t.nameNPCsSplitV1, t.nameNeutralNPCsV1 = true, true
		end
		if not t.nameNeutralNPCsV1 then
			for _, prefix in ipairs(NAME_ROW_PREFIXES) do
				if t[prefix .. "HostileNPCs"] ~= nil and t[prefix .. "NeutralNPCs"] == nil then
					t[prefix .. "NeutralNPCs"] = t[prefix .. "HostileNPCs"]
				end
			end
			t.nameNeutralNPCsV1 = true
		end
		-- Its Target row became the Target Names grid (the Target Nameplate
		-- grid's kinds): each row starts out ticked wherever it was.
		for _, prefix in ipairs(NAME_ROW_PREFIXES) do
			if t[prefix .. "Target"] ~= nil then
				for _, row in ipairs(ns.NAME_TARGET_ROWS) do
					if t[prefix .. row] == nil then t[prefix .. row] = t[prefix .. "Target"] end
				end
				t[prefix .. "Target"] = nil
			end
		end
	end
	-- ...then those rows became one again, Your Target (YourTarget), for
	-- plates and names alike (the Target section's two rows now), whose rule can
	-- name the kinds (the rules' words for your target). Rows all alike:
	-- its ticks, rule and roles are theirs. Otherwise a rule saying what
	-- each kind's row did, its ticks as rule words. Once each.
	local TARGET_KIND_WORDS = { "enemyplayer", "hostilenpc", "neutralplayer", "neutralnpc", "friendlyplayer",
		"friendlynpc" }
	local TARGET_MERGES = {
		{ flag = "plateTargetMergedV1", prefix = "plate", world = "Cinematic", rows = ns.PLATE_TARGET_ROWS,
			always = true }, -- (the plate rows started with Always ticked)
		{ flag = "nameTargetMergedV1", prefix = "name", world = "Keep", rows = { "TargetEnemyPlayer", "TargetEnemyNPC",
			"TargetNeutralPlayer", "TargetNeutralNPC", "TargetFriendlyPlayer", "TargetFriendlyNPC" } },
	}
	local TARGET_ROLES = { { "tankHide", "tank" }, { "healerHide", "healer" }, { "damageHide", "damage" } }
	local function MergeTargetRows(t, merge)
		if t[merge.flag] then
			return
		end
		local prefix = merge.prefix
		local ticks = {
			{ prefix .. "Combat", "(combat or calm)" }, { prefix .. "CombatPvP", "((combat or calm) and flagged)" },
			{ prefix .. "Group", "group" }, { prefix .. merge.world, "(not combat and world)" },
			{ prefix .. "InCities", "(not combat and city)" }, { prefix .. "InPvP", "(not combat and flagged and not bg)" },
			{ prefix .. "InBGs", "(not combat and bg)" }, { prefix .. "InInstances", "(not combat and instance)" },
			{ prefix .. "TargetEnemy", "(not combat and enemy)" }, { prefix .. "TargetFriendly", "(not combat and friendly)" },
		}
		local always = prefix .. "Always"
		local rules = type(t.frameRules) == "table" and t.frameRules or nil
		local function Value(key, row)
			local value = t[key .. row]
			if value == nil then
				return key == always and merge.always or false -- (as the rows started)
			end
			return value and true or false
		end
		local function RoleHidden(list, row)
			return type(t[list]) == "table" and t[list][prefix .. ":" .. row] and true or false
		end
		-- (Nothing of the rows saved: the new row's defaults, or what an
		-- older upgrade gave it, stand.)
		local any = false
		for _, row in ipairs(merge.rows) do
			any = any or t[always .. row] ~= nil or (rules and rules[prefix .. ":" .. row]) ~= nil
			for _, tick in ipairs(ticks) do any = any or t[tick[1] .. row] ~= nil end
			for _, role in ipairs(TARGET_ROLES) do any = any or RoleHidden(role[1], row) end
		end
		if any then
			-- Each row as a rule (its own, or its ticks'), with its roles: what it shows.
			local texts, alike = {}, true
			for i, row in ipairs(merge.rows) do
				local rule = rules and rules[prefix .. ":" .. row]
				local text
				if type(rule) == "string" and rule:find("%S") then
					text = "(" .. rule .. ")"
				elseif Value(always, row) then
					text = "always"
				else
					local words = {}
					for _, tick in ipairs(ticks) do
						if Value(tick[1], row) then words[#words + 1] = tick[2] end
					end
					text = #words > 0 and "(" .. table.concat(words, " or ") .. ")" or "never"
				end
				if text ~= "never" then
					for _, role in ipairs(TARGET_ROLES) do
						if RoleHidden(role[1], row) then text = text .. " and not " .. role[2] end
					end
				end
				texts[i] = text
				alike = alike and text == texts[1]
			end
			local first = merge.rows[1]
			local ruleKey = prefix .. ":YourTarget"
			if alike then
				t[always .. "YourTarget"] = Value(always, first)
				for _, tick in ipairs(ticks) do
					t[tick[1] .. "YourTarget"] = Value(tick[1], first)
				end
				if rules and rules[prefix .. ":" .. first] then rules[ruleKey] = rules[prefix .. ":" .. first] end
				for _, role in ipairs(TARGET_ROLES) do
					if RoleHidden(role[1], first) then t[role[1]][ruleKey] = true end
				end
			else
				-- (Kinds whose rows said the same share a piece.)
				local pieces, kindsOf = {}, {}
				for i, text in ipairs(texts) do
					if text ~= "never" then
						if not kindsOf[text] then
							kindsOf[text] = {}
							pieces[#pieces + 1] = text
						end
						table.insert(kindsOf[text], TARGET_KIND_WORDS[i])
					end
				end
				for i, text in ipairs(pieces) do
					local kinds = kindsOf[text]
					local who = #kinds > 1 and "(" .. table.concat(kinds, " or ") .. ")" or kinds[1]
					pieces[i] = text:find("^always") and who .. text:sub(7) or who .. " and " .. text
				end
				t[always .. "YourTarget"] = false
				for _, tick in ipairs(ticks) do
					t[tick[1] .. "YourTarget"] = false
				end
				if #pieces > 0 then
					t.frameRules = rules or {}
					t.frameRules[ruleKey] = table.concat(pieces, " or ")
				end
			end
			for _, row in ipairs(merge.rows) do
				t[always .. row] = nil
				for _, tick in ipairs(ticks) do
					t[tick[1] .. row] = nil
				end
				if type(t.frameRules) == "table" then t.frameRules[prefix .. ":" .. row] = nil end
				for _, role in ipairs(TARGET_ROLES) do
					if type(t[role[1]]) == "table" then t[role[1]][prefix .. ":" .. row] = nil end
				end
			end
		end
		t[merge.flag] = true
	end
	-- (Each grid's after the upgrades that made its rows: the old names
	-- Target row comes straight to the new one.)
	local function TargetUpgrades(t)
		NeutralFromHostile(t)
		TargetRowsFromMyTarget(t)
		MergeTargetRows(t, TARGET_MERGES[1])
		NPCNamesSplit(t)
		MergeTargetRows(t, TARGET_MERGES[2])
	end
	TargetUpgrades(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then TargetUpgrades(saved) end
	end
end

-- (Step 11.)
STEPS[#STEPS + 1] = function()
	-- LocalDefense attacks now show as a title on the screen (Show attacks
	-- on the screen), so the channel no longer brings up chat. Once, in
	-- every profile. (A profile without its own channel list uses the
	-- defaults, which have it off now.)
	if not ns.db.chatAttackAlertV1 then
		local function LocalDefenseOff(t)
			if type(t.chatPeekChannelList) == "table" then
				t.chatPeekChannelList.LocalDefense = false
			end
		end
		ns.db.chatAttackAlert = true
		LocalDefenseOff(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				saved.chatAttackAlert = nil -- (on by default)
				LocalDefenseOff(saved)
			end
		end
		ns.db.chatAttackAlertV1 = true
	end
	-- Say no longer brings up chat (it's off by default now). Once, in
	-- every profile.
	if not ns.db.chatSayOffV1 then
		local function SayOff(t)
			if type(t.chatPeekTypes) == "table" then
				t.chatPeekTypes.say = nil -- (off by default)
			end
		end
		SayOff(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then SayOff(saved) end
		end
		ns.db.chatSayOffV1 = true
	end
	-- ...and back on, now that says you can see as a bubble on screen don't
	-- bring up chat (Hide speech you can see as a bubble, on too). Once, in
	-- every profile.
	if not ns.db.chatSayOnV1 then
		local function SayOn(t)
			if type(t.chatPeekTypes) == "table" then
				t.chatPeekTypes.say = nil -- (on by default)
			end
			t.chatHideBubbled = nil -- (on by default)
		end
		SayOn(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then SayOn(saved) end
		end
		ns.db.chatSayOnV1 = true
	end
	-- Loot rolls no longer bring up chat (off by default now). Once, in every
	-- profile.
	if not ns.db.chatRollsOffV1 then
		local function RollsOff(t)
			if type(t.chatPeekTypes) == "table" then
				t.chatPeekTypes.rolls = nil -- (off by default)
			end
		end
		RollsOff(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then RollsOff(saved) end
		end
		ns.db.chatRollsOffV1 = true
	end
	-- Skill ups no longer bring up chat (off by default now). Once, in every
	-- profile.
	if not ns.db.chatSkillOffV1 then
		local function SkillOff(t)
			if type(t.chatPeekTypes) == "table" then
				t.chatPeekTypes.skill = nil -- (off by default)
			end
		end
		SkillOff(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then SkillOff(saved) end
		end
		ns.db.chatSkillOffV1 = true
	end
	-- NPC speech brings up chat again: Balanced and Cinema had it off, so
	-- speech from behind you never showed NPCs (says and yells you can see
	-- as a bubble still don't bring up chat). Once, in every profile.
	if not ns.db.chatNpcOnV1 then
		local function NpcOn(t)
			if type(t.chatPeekTypes) == "table" then
				t.chatPeekTypes.npc = nil -- (on by default)
			end
		end
		NpcOn(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then NpcOn(saved) end
		end
		ns.db.chatNpcOnV1 = true
	end
	-- The grids' Open world no longer covers capital cities (they're Cities,
	-- their own list): every row ticked Open world gets Cities ticked, and
	-- rules' world (the same, now) is world or city. Once, in every profile.
	-- Nameplates page rows' Also color went with the mark's color; now the
	-- plate has its own (PlateColor). A row with any part ticked keeps its
	-- look on its mark's ("same"). Once, in every profile.
	if not ns.db.plateColorV1 then
		local function PlateColor(t)
			local ids = {}
			for kind in pairs(ns.MARK_ROW_KINDS) do ids[#ids + 1] = kind end
			for id in tostring(t.markOrder or ""):gmatch("[^,]+") do ids[#ids + 1] = id end
			for _, id in ipairs(ids) do
				local key = id == "target" and "targetArrowPlateColor" or id .. "MarkPlateColor"
				if t[key] == nil and (t[id .. "ColorName"] or t[id .. "ColorBar"] or t[id .. "ColorBorder"]) then
					t[key] = "same"
				end
			end
		end
		PlateColor(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then PlateColor(saved) end
		end
		ns.db.plateColorV1 = true
	end
	if not ns.db.citiesApartV1 then
		local function CitiesApart(t)
			if type(t.worldShow) == "table" then
				t.cityShow = type(t.cityShow) == "table" and t.cityShow or {}
				for key, value in pairs(t.worldShow) do
					if t.cityShow[key] == nil then t.cityShow[key] = value end
				end
			end
			if type(t.frameRules) == "table" then
				for key, text in pairs(t.frameRules) do
					if type(text) == "string" then
						t.frameRules[key] = (text:gsub("%f[%w_][Ww][Oo][Rr][Ll][Dd]%f[^%w_]", "(world or city)"))
					end
				end
			end
		end
		CitiesApart(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then CitiesApart(saved) end
		end
		ns.db.citiesApartV1 = true
	end
	-- And the Nameplates page's and Heal Vision's: their own Cities as their
	-- open world was (set: copied; not: the default, the open world's too).
	-- Once, in every profile.
	if not ns.db.citiesApartPlatesV1 then
		local function CitiesApart(t)
			local copies = {}
			for key, value in pairs(t) do
				local plate, name = key:match("^plateCinematic(.+)"), key:match("^nameKeep(.+)")
				if plate then copies["plateInCities" .. plate] = value end
				if name then copies["nameInCities" .. name] = value end
			end
			if t.healVisionInWorld ~= nil then copies.healVisionInCities = t.healVisionInWorld end
			for key, value in pairs(copies) do
				if t[key] == nil then t[key] = value end
			end
		end
		CitiesApart(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then CitiesApart(saved) end
		end
		ns.db.citiesApartPlatesV1 = true
	end
	-- The grids that turned things off are Show in rows now (see
	-- ns.ConvertOffGrids): the live settings' old ones go over whenever
	-- they're there; and once, every saved profile's, from its built-in's,
	-- each list it keeps whole given the new rows as its built-in has them.
	-- (Converted before the Calm Timer was a time of its own, when Out of
	-- combat waited for it with it ticked: the effects' and music's had both,
	-- now just Out of combat; the tooltips' just Out of combat, now with the
	-- Calm Timer, back as a fight ends as they were. Once, every profile.)
	if ns.db.offGridsV1 and not ns.db.offGridsCalmV2 then
		local function CalmApart(t)
			if type(t.quietShow) ~= "table" then return end
			t.calmShow = type(t.calmShow) == "table" and t.calmShow or {}
			for key, quiet in pairs(t.quietShow) do
				if quiet and (key:find("^effect:") or key == "music") then
					t.calmShow[key] = false
				elseif quiet and key:find("^tooltip:") then
					t.calmShow[key] = true
				end
			end
		end
		CalmApart(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then CalmApart(saved) end
		end
	end
	ns.db.offGridsCalmV2 = true
	ns.ConvertOffGrids(ns.db, ns.OldGridDefault)
	if not ns.db.offGridsV1 then
		for name, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				local raw = ns.RawProfileBase(name)
				local base = ns.ProfileBase(name)
				ns.ConvertOffGrids(saved, function(key)
					if raw[key] ~= nil then return raw[key] end
					return ns.OldGridDefault(key)
				end, { listBase = base, compare = base, switches = true })
				for _, list in ipairs({ "worldShow", "cityShow", "instanceShow", "bgShow", "quietShow", "camShow",
					"calmShow" }) do
					if type(saved[list]) == "table" and type(base[list]) == "table" then
						for _, row in ipairs(ns.OFF_GRID_ROWS) do
							if saved[list][row.key] == nil then saved[list][row.key] = base[list][row.key] end
						end
					end
				end
			end
		end
		ns.db.offGridsV1 = true
	end
	-- The Tooltips page's five rows (tooltip:<kind>) became one, tooltip:All,
	-- whose rule can name the kinds (tipenemy and the rest). Rows all alike:
	-- its ticks, rule and roles are theirs. Otherwise a rule saying what each
	-- kind's row did, its ticks Everything else's. Once, in every profile.
	if not ns.db.tooltipOneRowV1 then
		local KINDS = { { "Enemy", "tipenemy" }, { "Friendly", "tipfriendly" }, { "Gather", "tipgather" },
			{ "Quest", "tipquest" }, { "Else", "tipother" } }
		local LISTS = { { "combatShow", "combat" }, { "calmShow", "calm" }, { "quietShow", "nocombat" },
			{ "camShow", "camera" }, { "worldShow", "world" }, { "cityShow", "city" }, { "bgShow", "bg" },
			{ "instanceShow", "instance" }, { "groupShow", "group" }, { "enemyShow", "enemy" },
			{ "friendlyShow", "friendly" } }
		local ROLES = { { "tankHide", "tank" }, { "healerHide", "healer" }, { "damageHide", "damage" } }
		-- (What the rows started as: Enemies always, Friendlies never, the rest out of combat.)
		local function Started(kind, list)
			if kind == "Enemy" or kind == "Friendly" then return false end
			return list == "quietShow" or list == "calmShow"
		end
		local function MergeTooltipRows(t)
			local rules = type(t.frameRules) == "table" and t.frameRules or nil
			local function Listed(list, kind)
				local value = type(t[list]) == "table" and t[list]["tooltip:" .. kind]
				if value == nil then return Started(kind, list) end
				return value and true or false
			end
			local any = false
			for _, kind in ipairs(KINDS) do
				local key = "tooltip:" .. kind[1]
				any = any or t["tooltipAlways" .. kind[1]] ~= nil or (rules and rules[key]) ~= nil
				for _, list in ipairs(LISTS) do any = any or (type(t[list[1]]) == "table" and t[list[1]][key]) ~= nil end
				for _, role in ipairs(ROLES) do any = any or (type(t[role[1]]) == "table" and t[role[1]][key]) ~= nil end
			end
			if any then
				-- Each row as a rule (its own, or its ticks'), with its roles.
				local texts, alike = {}, true
				for i, kind in ipairs(KINDS) do
					local key = "tooltip:" .. kind[1]
					local rule = rules and rules[key]
					local always = t["tooltipAlways" .. kind[1]]
					if always == nil then always = kind[1] == "Enemy" end
					local text
					if type(rule) == "string" and rule:find("%S") then
						text = "(" .. rule .. ")"
					elseif always then
						text = "always"
					else
						local words = {}
						for _, list in ipairs(LISTS) do
							if Listed(list[1], kind[1]) then words[#words + 1] = list[2] end
						end
						text = #words > 0 and "(" .. table.concat(words, " or ") .. ")" or "never"
					end
					if text ~= "never" then
						for _, role in ipairs(ROLES) do
							if type(t[role[1]]) == "table" and t[role[1]][key] then text = text .. " and not " .. role[2] end
						end
					end
					texts[i] = text
					alike = alike and text == texts[1]
				end
				-- (The ticks: the first row's when alike, else Everything else's, for Reset to grid.)
				local from = alike and KINDS[1][1] or "Else"
				local fromAlways = t["tooltipAlways" .. from]
				if fromAlways == nil then fromAlways = from == "Enemy" end
				t.tooltipAlways = alike and fromAlways or false
				-- (A list a profile hasn't of its own stays its built-in's.)
				for _, list in ipairs(LISTS) do
					if type(t[list[1]]) == "table" then t[list[1]]["tooltip:All"] = Listed(list[1], from) end
				end
				if alike then
					local rule = rules and rules["tooltip:" .. from]
					if rule then rules["tooltip:All"] = rule end
					for _, role in ipairs(ROLES) do
						if type(t[role[1]]) == "table" and t[role[1]]["tooltip:" .. from] then
							t[role[1]]["tooltip:All"] = true
						end
					end
				else
					-- (Kinds whose rows said the same share a piece.)
					local pieces, kindsOf = {}, {}
					for i, text in ipairs(texts) do
						if text ~= "never" then
							if not kindsOf[text] then
								kindsOf[text] = {}
								pieces[#pieces + 1] = text
							end
							table.insert(kindsOf[text], KINDS[i][2])
						end
					end
					for i, text in ipairs(pieces) do
						local kinds = kindsOf[text]
						local which = #kinds > 1 and "(" .. table.concat(kinds, " or ") .. ")" or kinds[1]
						pieces[i] = text:find("^always") and which .. text:sub(7) or which .. " and " .. text
					end
					t.frameRules = rules or {}
					t.frameRules["tooltip:All"] = #pieces > 0 and table.concat(pieces, " or ") or "never"
				end
			end
			-- (The old rows' settings out, and the old kinds' hide settings.)
			for _, kind in ipairs(KINDS) do
				local key = "tooltip:" .. kind[1]
				t["tooltipAlways" .. kind[1]] = nil
				if type(t.frameRules) == "table" then t.frameRules[key] = nil end
				for _, list in ipairs(LISTS) do
					if type(t[list[1]]) == "table" then t[list[1]][key] = nil end
				end
				for _, role in ipairs(ROLES) do
					if type(t[role[1]]) == "table" then t[role[1]][key] = nil end
				end
				if kind[1] ~= "Else" then
					t["tooltipHide" .. kind[1]], t["tooltipHideCombat" .. kind[1]] = nil, nil
				end
			end
			-- (Hide in camera modes went too: the row's In a camera mode, or its rule's camera, says.)
			for _, mode in ipairs({ "Flight", "Idle", "Cozy", "Vista", "Fish", "Walk", "Run", "Tele", "Death", "Quest" }) do
				t["tooltipHideIn" .. mode] = nil
			end
		end
		MergeTooltipRows(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then MergeTooltipRows(saved) end
		end
		ns.db.tooltipOneRowV1 = true
	end
end

-- (Step 12.)
STEPS[#STEPS + 1] = function()
	-- The Chat bubbles page's Say & yell row became three, Say, Yell and NPCs:
	-- the new rows start as the Say row was (its Always, ticks, rule and
	-- roles). Once, in every profile.
	if not ns.db.bubbleRowsSplitV1 then
		local function Split(t)
			for _, kind in ipairs({ "Yell", "NPC" }) do
				local always = "bubbles" .. kind .. "Always"
				if t.bubblesSayAlways ~= nil and t[always] == nil then
					t[always] = t.bubblesSayAlways
				end
				for _, value in pairs(t) do
					if type(value) == "table" and value["bubble:Say"] ~= nil and value["bubble:" .. kind] == nil then
						value["bubble:" .. kind] = value["bubble:Say"]
					end
				end
			end
		end
		Split(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then Split(saved) end
		end
		ns.db.bubbleRowsSplitV1 = true
	end
	-- Rules' "arena" is arenas only now (bg: battlegrounds and arenas both;
	-- battleground: battlegrounds only), so a rule written before says bg,
	-- meaning both as it did. Once, in every profile.
	if not ns.db.ruleArenaV1 then
		local function ArenaToBG(t)
			if type(t.frameRules) ~= "table" then return end
			for key, text in pairs(t.frameRules) do
				if type(text) == "string" then
					t.frameRules[key] = (text:gsub("%f[%w_][Aa][Rr][Ee][Nn][Aa]%f[^%w_]", "bg"))
				end
			end
		end
		ArenaToBG(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then ArenaToBG(saved) end
		end
		ns.db.ruleArenaV1 = true
	end
	-- The quest timer box shows while one is running in every profile (Pure
	-- Cinema had it off). Once, in every profile.
	if not ns.db.questTimerOnV1 then
		ns.db.questTimerShow = nil -- (on by default)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then saved.questTimerShow = nil end
		end
		ns.db.questTimerOnV1 = true
	end
	-- Tooltips fade in and out over 0.2 seconds by default, not 0. Once, in
	-- every profile still at the old default.
	if not ns.db.tooltipFadeV1 then
		local function FadeOn(t)
			if t.tooltipFadeTime == 0 then t.tooltipFadeTime = nil end -- (0.2 by default)
		end
		FadeOn(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then FadeOn(saved) end
		end
		ns.db.tooltipFadeV1 = true
	end
	-- The time-of-day tint now shows at full strength by default, not half.
	-- Once, in every profile still at the old default.
	if not ns.db.timeTintFullV1 then
		local function TimeTintFull(t)
			if t.timeTintStrength == 0.5 then t.timeTintStrength = nil end -- (1 by default)
		end
		TimeTintFull(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then TimeTintFull(saved) end
		end
		ns.db.timeTintFullV1 = true
	end
	-- The quest cam now leaves you be while you're mounted by default. Once,
	-- in every profile.
	if not ns.db.questCamNotMountedV1 then
		ns.db.questCamNotMounted = nil -- (on by default)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then saved.questCamNotMounted = nil end
		end
		ns.db.questCamNotMountedV1 = true
	end
	-- The cozy camera by a tent: 8 yards, not 7. Once, in every profile still
	-- at the old default (there's no slider for it).
	if not ns.db.cozyTentCloseV1 then
		local function TentEight(t)
			if t.cozyTentClose == 7 then t.cozyTentClose = nil end -- (8 by default)
		end
		TentEight(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then TentEight(saved) end
		end
		ns.db.cozyTentCloseV1 = true
	end
	-- Enemy class icons and tank and healer role icons on nameplates are now
	-- on (Always) by default: into every profile too. Once.
	if not ns.db.plateIconsAlwaysV1 then
		for _, part in ipairs(ns.PLATE_ICONS_ALWAYS) do
			ns.db["plateAlwaysPart" .. part] = true
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" then saved["plateAlwaysPart" .. part] = true end
			end
		end
		ns.db.plateIconsAlwaysV1 = true
	end
	-- The class and role icons and the target marks left the Nameplates
	-- page's grid for a When of their own (PlateIcons.lua). Once, after
	-- the updates above that set their old ticks.
	if ns.MigratePlateIconWhen then ns.MigratePlateIconWhen(ns.db) end
	-- Immersive (CDM) now shows the Cooldown Manager in place of action
	-- bars 1 to 3 with an enemy targeted too. Once, in that profile (and the
	-- live settings when they're its), where its Tar enemy column is still as it was.
	if not ns.db.cdmEnemyV1 then
		local function CooldownsOn(t)
			local list = type(t) == "table" and t.enemyShow
			if type(list) == "table" and list.cooldowns == false and list.mainbar == false then
				list.cooldowns = true
			end
		end
		CooldownsOn((ns.db.profiles or {})["Immersive (CDM)"])
		if (ns.db.liveProfile or ns.db.profile) == "Immersive (CDM)" then CooldownsOn(ns.db) end
		ns.db.cdmEnemyV1 = true
	end
	-- ...and keeps the micro menu and bags and the XP bar hidden then. Once,
	-- in each of those columns still as it was.
	if not ns.db.cdmBarsV1 then
		local function BarsOff(t)
			for _, key in ipairs({ "combatShow", "enemyShow" }) do
				local list = type(t) == "table" and t[key]
				if type(list) == "table" and list.mainbar == false and list.micro == true and list.xp == true then
					list.micro, list.xp = false, false
				end
			end
		end
		BarsOff((ns.db.profiles or {})["Immersive (CDM)"])
		if (ns.db.liveProfile or ns.db.profile) == "Immersive (CDM)" then BarsOff(ns.db) end
		ns.db.cdmBarsV1 = true
	end
	-- Stay up while recharging is each bar's now: the Utility bar's starts
	-- as the one setting was (live and in every profile). Once.
	if not ns.db.cooldownUtilityRechargeV1 then
		local function Copy(t)
			if type(t) ~= "table" then return end
			if t.cooldownWhileRecharging ~= nil then t.cooldownUtilityWhileRecharging = t.cooldownWhileRecharging end
			if t.cooldownAfterCombat ~= nil then t.cooldownUtilityAfterCombat = t.cooldownAfterCombat end
		end
		Copy(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do Copy(saved) end
		ns.db.cooldownUtilityRechargeV1 = true
	end
	-- The Raid Frame Manager's default Mouseover group held the raid and
	-- party frames too, so hovering them brought it up: just the manager now. Once.
	if not ns.db.raidManagerAloneV1 then
		local OUT = { raidplayers = true, raidpets = true, party = true, rspartyplayers = true, rspartypets = true }
		local function ManagerAlone(groups)
			for _, group in ipairs(groups or {}) do
				local preset = ns.HoverGroupPreset(group)
				if preset and preset.preset == "raidmanager" and group.members then
					for i = #group.members, 1, -1 do
						if OUT[group.members[i]] then table.remove(group.members, i) end
					end
				end
			end
		end
		ManagerAlone(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then ManagerAlone(saved.hoverGroups) end
		end
		ns.db.raidManagerAloneV1 = true
	end
	-- The extra action and zone ability buttons were in the default Action
	-- bars Mouseover group, so hovering them brought the bars up: alone now. Once.
	if not ns.db.extraAloneV1 then
		local function ExtraAlone(groups)
			for _, group in ipairs(groups or {}) do
				local preset = ns.HoverGroupPreset(group)
				if preset and preset.preset == "bars" and group.members then
					for i = #group.members, 1, -1 do
						if group.members[i] == "extra" then table.remove(group.members, i) end
					end
				end
			end
		end
		ExtraAlone(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then ExtraAlone(saved.hoverGroups) end
		end
		ns.db.extraAloneV1 = true
	end
	-- Retail's collapse buffs button has a row now, hidden but for hovering
	-- the buffs: put it in the saved Buffs Mouseover groups. Once.
	if not ns.db.buffCollapseV1 then
		local function CollapseToo(groups)
			for _, group in ipairs(groups or {}) do
				local preset = ns.HoverGroupPreset(group)
				if preset and preset.preset == "buffs" and group.members then
					local has = false
					for _, member in ipairs(group.members) do
						if member == "buffcollapse" then has = true end
					end
					if not has then group.members[#group.members + 1] = "buffcollapse" end
				end
			end
		end
		CollapseToo(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then CollapseToo(saved.hoverGroups) end
		end
		ns.db.buffCollapseV1 = true
	end
	-- The Cooldown Manager's row is now its Essential bar's, with a row of its
	-- own for the Utility bar: put that in every saved group the old row was in. Once.
	if not ns.db.cooldownsUtilityV1 then
		local function UtilityToo(groups)
			for _, group in ipairs(groups or {}) do
				for i, member in ipairs(group.members or {}) do
					if member == "cooldowns" then
						table.insert(group.members, i + 1, "cooldownsutility")
						break
					end
				end
			end
		end
		UtilityToo(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then UtilityToo(saved.hoverGroups) end
		end
		ns.db.cooldownsUtilityV1 = true
	end
	-- The tracked buffs and bars are rows of their own now (they went with
	-- the Essential row), and Enhanced Cooldown Manager's buff bars too:
	-- put them in every saved group their old row was in. Once.
	if not ns.db.cooldownsBuffsV1 then
		local AFTER = { cooldowns = { "cooldownsbuffs", "cooldownsbars" }, ["addon:fecm"] = { "addon:fecmAuras" } }
		local function BuffsToo(groups)
			for _, group in ipairs(groups or {}) do
				local has = {}
				for _, member in ipairs(group.members or {}) do has[member] = true end
				for old, new in pairs(AFTER) do
					for i, member in ipairs(group.members or {}) do
						if member == old then
							for _, row in ipairs(new) do
								if not has[row] then
									i = i + 1
									table.insert(group.members, i, row)
								end
							end
							break
						end
					end
				end
			end
		end
		BuffsToo(ns.db.hoverGroups)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then BuffsToo(saved.hoverGroups) end
		end
		ns.db.cooldownsBuffsV1 = true
	end
end

-- (Step 13.)
STEPS[#STEPS + 1] = function()
	-- "Hide the circle under your target out of combat" (hideTargetCircle)
	-- is now the Standard Frames page's Target circle row: ticked, it
	-- was up in fights and for the Calm Timer after them.
	local function CircleRow(t)
		if type(t) ~= "table" then
			return
		end
		if t.hideTargetCircle then
			for _, list in ipairs({ "cineShow", "combatShow", "calmShow" }) do
				if type(t[list]) ~= "table" then t[list] = {} end
				t[list].targetcircle = list ~= "cineShow"
			end
		end
		t.hideTargetCircle = nil
	end
	CircleRow(ns.db)
	for _, profile in pairs(ns.db.profiles or {}) do
		CircleRow(profile)
	end
	-- "Keep raid markers up as nameplates fade" (keepRaidMarkers) is now the
	-- Raid Markers grid: unticked, neither side's markers are kept.
	local function MarkersOff(t)
		if type(t) == "table" and t.keepRaidMarkers == false then
			for _, part in ipairs(ns.PLATE_MARKER_PARTS) do
				t["plateAlwaysPart" .. part] = false
			end
		end
	end
	MarkersOff(ns.db)
	for _, profile in pairs(ns.db.profiles or {}) do
		MarkersOff(profile)
		if type(profile) == "table" then
			profile.keepRaidMarkers = nil
		end
	end
	-- The Raid Markers grid's Friendly and Enemy rows are now the Names
	-- grid's one Raid marker row: ticked in each column where either was.
	local function MarkersJoined(t)
		if type(t) ~= "table" then
			return
		end
		local prefixes = { "plateAlways", "plateCombat", "plateCombatPvP", "plateCinematic", "plateGroup" }
		for _, suffix in ipairs(ns.PLATE_PLACES) do
			prefixes[#prefixes + 1] = "plateIn" .. suffix
		end
		for _, prefix in ipairs(prefixes) do
			local friendly, enemy = t[prefix .. "PartMarkerFriendly"], t[prefix .. "PartMarkerEnemy"]
			if friendly ~= nil or enemy ~= nil then
				local default = prefix == "plateAlways"
				local value = (friendly == nil and default or friendly) or (enemy == nil and default or enemy)
				t[prefix .. "PartMarker"] = value
			end
			t[prefix .. "PartMarkerFriendly"], t[prefix .. "PartMarkerEnemy"] = nil, nil
		end
	end
	MarkersJoined(ns.db)
	for _, profile in pairs(ns.db.profiles or {}) do
		MarkersJoined(profile)
	end
	-- Quest Vision's "Always show their nameplates" tick became a choice of
	-- Nameplate, Name, Quest mark or No action (questMobsShow), now ticks of
	-- their own (questMobsPlate, Name, Mark): unticked or No action is none.
	local function QuestMobsChoice(settings)
		local show = settings.questMobsShow
		if settings.plateQuestMobs == false and show == nil then
			show = "none"
		end
		if type(show) == "string" then
			settings.questMobsPlate = show == "plate"
			settings.questMobsName = show == "name"
			settings.questMobsMark = show == "mark"
		end
		settings.plateQuestMobs, settings.questMobsShow = nil, nil
	end
	QuestMobsChoice(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then QuestMobsChoice(saved) end
	end
	-- A row's plate Size (Scale, the whole plate) is now its health bar's
	-- Width and Height, both from it.
	local function PlateSizeSplit(saved)
		local sizes = {}
		for key, value in pairs(saved) do
			local prefix = type(key) == "string" and (key:match("^(.-Mark)Scale$") or key:match("^(targetArrow)Scale$"))
			if prefix then sizes[prefix] = value end
		end
		for prefix, value in pairs(sizes) do
			if type(value) == "number" then
				saved[prefix .. "PlateWidth"], saved[prefix .. "PlateHeight"] = value, value
			end
			saved[prefix .. "Scale"] = nil
		end
	end
	PlateSizeSplit(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then PlateSizeSplit(saved) end
	end
	-- Combat Vision's pulse (a tick and a strength) is a strength going in
	-- and one coming out, 0 for none; its icon's tick a tick for each.
	local function PulseSplit(saved)
		if saved.combatPulseIn == nil then
			local strength = saved.combatPulse == false and 0 or tonumber(saved.combatPulseStrength)
			if strength then saved.combatPulseIn, saved.combatPulseOut = strength, strength end
		end
		if saved.combatIconShowIn == nil and saved.combatIcon ~= nil then
			saved.combatIconShowIn, saved.combatIconShowOut = saved.combatIcon, saved.combatIcon
		end
		-- How long it stays: one for each (the old 0.5 default: the new).
		if saved.combatHoldIn == nil and tonumber(saved.combatHold) and saved.combatHold ~= 0.5 then
			saved.combatHoldIn, saved.combatHoldOut = saved.combatHold, saved.combatHold
		end
	end
	PulseSplit(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then PulseSplit(saved) end
	end
	-- Its words' "" (Combat and Respite) are those words now, "" none.
	-- Once. (Saved profiles drop theirs, to follow their base.)
	if not ns.db.combatWordsV1 then
		for _, key in ipairs({ "combatTextIn", "combatTextOut" }) do
			if (ns.db[key] or "") == "" then ns.db[key] = DEFAULTS[key] end
			for _, saved in pairs(ns.db.profiles or {}) do
				if type(saved) == "table" and saved[key] == "" then saved[key] = nil end
			end
		end
		ns.db.combatWordsV1 = true
	end
	-- Its pulse has colors of its own now, as the text's to start with.
	-- Once.
	if not ns.db.combatPulseColorV1 then
		local function PulseColor(saved)
			for _, side in ipairs({ "In", "Out" }) do
				for _, c in ipairs({ "R", "G", "B" }) do
					local key = "combatPulse" .. side .. c
					if saved[key] == nil then saved[key] = saved["combat" .. side .. c] end
				end
			end
		end
		PulseColor(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then PulseColor(saved) end
		end
		ns.db.combatPulseColorV1 = true
	end
	-- Its No text style is gone: no words going in or out in its place.
	local function NoText(saved)
		if saved.combatStyle ~= "none" then return end
		saved.combatStyle, saved.combatTextIn, saved.combatTextOut = DEFAULTS.combatStyle, "", ""
	end
	NoText(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then NoText(saved) end
	end
	-- Cinematic's Edit Mode layouts got new names (Layouts.lua): the
	-- profiles on one under its old name, on the new.
	local function LayoutRenamed(saved)
		saved.editModeLayout = ns.LAYOUT_RENAMED[saved.editModeLayout or ""] or saved.editModeLayout
	end
	LayoutRenamed(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then LayoutRenamed(saved) end
	end
	-- Last time's Page-turn sound tick is its sound rules now (the Cards
	-- page's Sounds tab): unticked, a rule with no sounds.
	local function PageTurnOff(saved)
		if rawget(saved, "storyRecapSound") == false and rawget(saved, "cardSounds_login") == nil then
			saved.cardSounds_login = "show##"
		end
	end
	PageTurnOff(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then PageTurnOff(saved) end
	end
	-- The Fade if another addon competes tick is the Questie's icons
	-- dropdown now: unticked (both showed) stays both; ticked takes the
	-- new default, Cinematic's mark winning.
	local function QuestieIconsFrom(saved)
		if rawget(saved, "questMarkFade") == false and rawget(saved, "questieIcons") == nil then
			saved.questieIcons = "both"
		end
	end
	QuestieIconsFrom(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then QuestieIconsFrom(saved) end
	end
	-- The Unit Frame Parts page's switch is gone (2026-11-11: the parts
	-- follow the HUD page's). Switched off, every part showed as
	-- the game has it: the parts' Always ticked, so they still do.
	local function PartsSwitchOff(saved)
		if rawget(saved, "handleUnitFrames") ~= false then return end
		local hidden = {}
		for key, value in pairs(saved) do
			if value == false and type(key) == "string" and key:find("^unitPart") and not key:find("Same$") then
				hidden[#hidden + 1] = key
			end
		end
		for _, key in ipairs(hidden) do saved[key] = true end
	end
	PartsSwitchOff(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then PartsSwitchOff(saved) end
	end
	-- The Shoulder Cam's "Not during Cinematic's cameras" unticked: every
	-- camera's tick on its Cameras tab instead (2026-11-13).
	local function MigrateShoulderPause(saved)
		if saved.shoulderCamPause ~= false then return end
		for _, cam in ipairs({ "Vista", "Fish", "Cozy", "AFK", "Tele", "Flight", "Death", "Yours", "Walk", "Run",
			"Quest", "Chat" }) do
			saved["shoulderCamAllow" .. cam] = true
		end
	end
	-- Turn to enemy's Always: on to start with till 2026-11-15, off since
	-- (its rule "not combat" instead). Left on, it kept turning in fights:
	-- off once for those who had the old default.
	local function MigrateTurnAlways(saved)
		if rawget(saved, "shoulderTurnAlwaysMoved") then return end
		saved.shoulderTurnAlwaysMoved = true
		if rawget(saved, "shoulderCamTargetTurnAlways") == true then saved.shoulderCamTargetTurnAlways = false end
	end
	MigrateShoulderPause(ns.db)
	MigrateTurnAlways(ns.db)
	for _, saved in pairs(ns.db.profiles or {}) do
		if type(saved) == "table" then
			MigrateShoulderPause(saved)
			MigrateTurnAlways(saved)
			if type(saved.settings) == "table" then
				MigrateShoulderPause(saved.settings)
				MigrateTurnAlways(saved.settings)
			end
		end
	end
	-- Settings from removed or renamed features, now that the migrations
	-- above have read what they need.
	for _, key in ipairs({
		"keepRaidMarkers", -- (now the Raid Markers grid)
		"shoulderCamPause", -- (now shoulderCamAllow<Cam>)
		"shoulderCamTester", -- (the Shoulder Cam's soft release, /cine testshoulder: everyone's since 2026-11-15)
		"movingKeepVFX", "damageVisionOnlyCine", -- (now Allow outside CineMode's ticks)
		"handleUnitFrames", -- (the parts follow the HUD page's switch)
		"rollMinQuality", "rollUsableOnly", "rollTopPick", -- (now roll<Rule><Group><Q>)
		"rollBeside", "rollSeparate", -- (now rollPlace)
		"rollFooter", -- (now rollFooterParty, rollFooterRaid)
		"rollPartyRows", "rollRaidRows", -- (now rollMax<Group><Q>)
		"rollShowUncommon", "rollShowRare", "rollShowEpic", "rollShowLegendary", "rollUsableUncommon", "rollUsableRare",
		"rollUsableEpic", "rollUsableLegendary", "rollBestUncommon", "rollBestRare", "rollBestEpic", "rollBestLegendary",
		"rollPartyUncommon", "rollPartyRare", "rollPartyEpic", "rollPartyLegendary", "rollRaidUncommon", "rollRaidRare", "rollRaidEpic", "rollRaidLegendary", -- (dev copy's one grid)
		"storyRecapSound", -- (now Last time's sound rules)
		"questMarkFade", -- (now questieIcons)
		"cozyInstant", "cozyBuffsOn", "cozySit", "cozySleep", "cozyDance", "cozyKneel", "cozyChair",
		"cozyWeapon", "vistaInstant", "vistaStare", "eventsV2", "eventDelay",
		"taxiShotHold", "taxiShotBlendTime",
		"taxiShots", "taxiShotInterval", "taxiShotLength", "taxiShotBlend", "taxiShotCuts",
		"questCam", -- (now the quest giver event's camera)
		"thirdsFraming", "thirdsStrength", "thirdsInterval", "thirdsHold",
		"taxiThirdsInterval", "taxiThirdsStrength", "taxiThirds", "walkThirds", "runThirds",
		"idleThirds", "cozyThirds", "vistaThirds", "deathThirds",
		"delay", "startCinematic", "startCinematicOnReload", "startDelay", "timeOfDayChange", "timeOfDaySound",
		"revealOnTarget", "ignoreDeadTarget", "unitBarTexture",
		"plateHurtMobs", "plateHurtNPCs", "plateHurtOwn", "plateHurtOther", "plateHurtPets",
		"plateHurtTotems",
		"camOffInCities", "camOffInInns", "camOffInDungeons", "camOffInRaids", "camOffInPvP",
		"rotOffInCities", "rotOffInInns", "rotOffInDungeons", "rotOffInRaids", "rotOffInPvP",
		"zoomOffInCities", "zoomOffInInns", "zoomOffInDungeons", "zoomOffInRaids", "zoomOffInPvP",
		"hideCursor", "hideCursorDelay", "innZoom", "innZoomDistance",
		"viewShift", "viewShiftAmount", "viewShiftRight", "zoneTitle", "zoneTitleSubzones",
		"taxiOrbitPitch", "idleOrbitPitch", "turnLog", "cozyPray", "cozyAngle", "deathInputPause",
		"cozyCrackle", "cursorTuck", "cursorTuckFlight", "cursorTuckIdle", "cursorTuckCozy",
		"cursorTuckVista", "cursorTuckWalk", "cursorTuckRun", "cursorTuckOther", "cursorTuckDelay",
		"flyByDistance", "flyByMinDistance", "flyByMaxDistance", "flyByTrace", "flyByLower",
		"cameraInputPause", "questCamRandomSide", "questCamLeft", "lastMusicStartedAt",
		"musicCamIdle", "musicWhenAFK", "noMusicWhenAFK", -- (now eventAFKMusic)
		"musicPauseOnLanding", "musicPauseFadeTime", -- (leaving the flight camera; the music fade time)
		"musicOffOnFlights", -- (the flight camera's Music switch, Cameras page)
		"trackingHideWhenIdle", -- (Hide in camera modes, Minimap page; removed)
		"tintWhen", -- (now tintMoving, tintStill, tintFlight)
		"combatPulse", "combatPulseStrength", -- (now combatPulseIn, combatPulseOut)
		"combatIcon", -- (now combatIconShowIn, combatIconShowOut)
		"combatHold", -- (now combatHoldIn, combatHoldOut)
		"combatWordsIn", "combatWordsOut", -- (empty words now)
		"combatWiden", -- (now combatBarScale)
		"plateTargetEnemyFadeIn", "plateTargetEnemyFadeOut", "plateTargetFriendlyFadeIn",
		"plateTargetFriendlyFadeOut", -- (the target's plate fades at the UI's fade times now)
		"enemyFadeInTime", "enemyFadeOutTime",
		"friendlyFadeInTime", "friendlyFadeOutTime", -- (combat frames likewise)
		-- (combatFadeInTime was too: it's back, for fights.)
		"combatFadeOutTime", -- (fades after fights: the Calm Timer, then the Fade out time)
		"plateShowMobs", "plateShowNPCs", "plateShowOwn", "plateShowOther", "plateShowPets",
		"plateShowTotems", -- (nameplates outside cinematic mode are the game's own now)
		"nameIconMobs", "nameIconNPCs", "nameIconOwn", "nameIconOther", "nameIconPets", "nameIconTotems",
		"nameIconPvPMobs", "nameIconPvPNPCs", "nameIconPvPOwn", "nameIconPvPOther", "nameIconPvPPets",
		"nameIconPvPTotems", -- (custom icons in place of names, removed)
		"nameShowMobs", "nameShowNPCs", "nameShowOwn", "nameShowOther", "nameShowPets",
		"nameShowMinions", "nameShowTotems", "nameShowSelf", -- (names outside cinematic mode are the game's own)
		"cameraPauseAtNPCs", "cameraPauseCasting", "cameraPauseInMenus", -- (always on now)
		"cozyTentZoom", -- (now cozyTentClose)
	}) do
		ns.db[key] = nil
	end
end

-- (Step 14.)
STEPS[#STEPS + 1] = function()
	-- The Minimap page's Hide in camera modes (<cam>HideMinimap) went: the
	-- minimap's row (In a camera mode, or a rule's camera) says.
	for key in pairs(ns.db) do
		if type(key) == "string" and key:find("HideMinimap$") then ns.db[key] = nil end
	end
	-- Vision > General's switch turned off its page (the Vision Helper, and
	-- Duel Vision before it had a page); it's Enable Visions now, over every
	-- vision. Off, it's on again with those two off, as they were. Once.
	if not ns.db.visionsMasterV1 then
		local function Keep(saved)
			if saved.handleVision == false then
				saved.handleVision, saved.minimapVisions, saved.duelPlates = true, false, false
			end
		end
		Keep(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then Keep(saved) end
		end
		ns.db.visionsMasterV1 = true
	end
	-- Enable Visions (Vision > General) went with its page: each vision has
	-- only its own switch. Off, every vision is turned off instead. Once.
	if not ns.db.visionsMasterV2 then
		local function Spread(saved)
			if saved.handleVision == false then
				for _, key in ipairs({ "handleHealVision", "questVision", "rollWindow", "duelPlates",
					"lowHealth", "combatVision", "storyVision" }) do
					saved[key] = false
				end
			end
			saved.handleVision = nil
		end
		Spread(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then Spread(saved) end
		end
		ns.db.visionsMasterV2 = true
	end
	-- Battle Vision and Story Vision are one Cards page now: their switches
	-- into its rows' ticks, their Show in rows onto its rows', each look
	-- setting you'd changed onto its event (Cards.lua), saved profiles
	-- too (only what they have). Once.
	if not ns.db.cardsV1 then
		ns.MigrateCards(ns.db, true)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then ns.MigrateCards(saved, false) end
		end
		ns.db.cardsV1 = true
	end
	-- Entering and Leaving combat, one Combat card in 1.9.12 (cardsV2), are
	-- two again (Cards.lua), saved profiles too. Once.
	if ns.db.cardsV2 and not ns.db.cardsV3 then
		ns.SplitCombatCard(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then ns.SplitCombatCard(saved) end
		end
	end
	ns.db.cardsV2, ns.db.cardsV3 = nil, true
	-- The Default style went from the Cards page: what you'd changed on it
	-- onto each card that showed it (Cards.lua), saved profiles too. Once.
	if not ns.db.cardsV5 then
		ns.SpreadCardBase(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then ns.SpreadCardBase(saved) end
		end
		ns.db.cardsV5 = true
	end
	-- The story cards' (CardMoments.lua) starting places and style changed
	-- after they first saved: theirs still as they first came, onto the
	-- new ones. Once.
	if not ns.db.cardsV6 then
		for key, old in pairs({ cardAlign_profession = "default", cardAlign_reputation = "default",
			cardAlign_collect = "default", cardAlign_rested = "default", cardBase_discover = "follow" }) do
			if ns.db[key] == old then ns.db[key] = DEFAULTS[key] end
		end
		ns.db.cardsV6 = true
	end
	-- The cards went into four families (Cards.lua's Milestone, Place,
	-- Ticker and Danger): each card still starting from the style it
	-- came with, onto its family's; the story cards' own alignments as
	-- they came, back to following it. Saved profiles too. Once.
	if not ns.db.cardsV7 then
		local function Families(t)
			for id, old in pairs(ns.CARD_OLD_BASES) do
				if t["cardBase_" .. id] == old then t["cardBase_" .. id] = DEFAULTS["cardBase_" .. id] end
			end
			for _, id in ipairs({ "profession", "reputation", "collect" }) do
				if t["cardAlign_" .. id] == "left" then t["cardAlign_" .. id] = "default" end
			end
		end
		Families(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then Families(saved) end
		end
		ns.db.cardsV7 = true
	end
	-- Rare spotted got a card of its own (Cards.lua's Rare style): onto
	-- it from the ones it had. Saved profiles too. Once.
	if not ns.db.cardsV8 then
		local OLD = { ticker = true, alert = true, film = true }
		local function Rare(t)
			if OLD[t.cardBase_rare] then t.cardBase_rare = "rare" end
		end
		Rare(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then Rare(saved) end
		end
		ns.db.cardsV8 = true
	end
	-- Kill streak went to the top bar's middle (Cards.lua): yours still
	-- following its style, onto it. Saved profiles too. Once.
	if not ns.db.cardsV9 then
		local function Middle(t)
			if t.cardAlign_streak == "default" then t.cardAlign_streak = "center" end
		end
		Middle(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then Middle(saved) end
		end
		ns.db.cardsV9 = true
	end
	-- Time of day went back to the middle of the screen (Cards.lua's
	-- Milestone): yours still in the Ticker, onto it. Saved profiles too.
	-- Once.
	if not ns.db.cardsV10 then
		local function Middle(t)
			if t.cardBase_time == "ticker" then t.cardBase_time = "milestone" end
		end
		Middle(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then Middle(saved) end
		end
		ns.db.cardsV10 = true
	end
	-- Battleground went to the lower third (Cards.lua's Place): yours
	-- still a Milestone, onto it. Saved profiles too. Once.
	if not ns.db.cardsV11 then
		local function Third(t)
			if t.cardBase_battleground == "milestone" then t.cardBase_battleground = "place" end
		end
		Third(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then Third(saved) end
		end
		ns.db.cardsV11 = true
	end
	-- No letterbox (a card in a bar with none up) went from a tick to a
	-- choice: ticked the lower third, unticked a bar of its own; Entering
	-- and Leaving combat still following their style, onto the middle of
	-- the screen (Cards.lua). Saved profiles too. Once.
	if not ns.db.cardsV12 then
		local function Choice(t)
			for key, value in pairs(t) do
				if type(key) == "string" and type(value) == "boolean"
					and (key:find("^cardBarFallback") or key:find("^cardLookBarFallback")) then
					t[key] = value and "third" or "bar"
				end
			end
			for _, id in ipairs({ "combatIn", "combatOut" }) do
				local key = "cardBarFallback_" .. id
				if t[key] == "default" then t[key] = DEFAULTS[key] end
			end
		end
		Choice(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then Choice(saved) end
		end
		ns.db.cardsV12 = true
	end
	-- Entering and Leaving combat: no edge pulse (Cards.lua), in every profile.
	-- Once: set it again and it stays.
	if not ns.db.cardsV13 then
		local function NoPulse(t)
			t.cardPulse_combatIn, t.cardPulse_combatOut = 0, 0
		end
		NoPulse(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then NoPulse(saved) end
		end
		for _, point in pairs(ns.db.profileResetPoints or {}) do
			if type(point) == "table" then NoPulse(point) end
		end
		ns.db.cardsV13 = true
	end
	-- Boss defeated went to the top bar (Cards.lua's Triumph: its banner
	-- was in the way mid-dungeon), and Dungeon cleared became the big
	-- banner in the middle: yours still as they came, onto them. Saved
	-- profiles too. Once: pick the old ones again and they stay.
	if not ns.db.cardsV14 then
		local function Wins(t)
			if t.cardBase_bossDown == "victory" then t.cardBase_bossDown = "triumph" end
			if t.cardSouls_cleared == "usual" then t.cardSouls_cleared = "souls" end
		end
		Wins(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				Wins(saved)
				if type(saved.settings) == "table" then Wins(saved.settings) end
			end
		end
		for _, point in pairs(ns.db.profileResetPoints or {}) do
			if type(point) == "table" then Wins(point) end
		end
		ns.db.cardsV14 = true
	end
	-- Exit CineMode's In PvP box covered battlegrounds and arenas too; they
	-- have a box of their own now (2026-11-12), ticked wherever In PvP was.
	if not ns.db.offInBGsV1 then
		local function SplitBGs(t)
			if t.offInBGs == nil and t.offInPvP ~= nil then t.offInBGs = t.offInPvP end
		end
		SplitBGs(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				SplitBGs(saved)
				if type(saved.settings) == "table" then SplitBGs(saved.settings) end
			end
		end
		for _, point in pairs(ns.db.profileResetPoints or {}) do
			if type(point) == "table" then SplitBGs(point) end
		end
		ns.db.offInBGsV1 = true
	end
	-- Off while moving's one Back after timed both standing still and a long
	-- move; standing still has its own slider now (2026-11-13), starting at
	-- the old one's time.
	if not ns.db.movingStillV1 then
		local function SplitStill(t)
			if t.movingStillAfter == nil and t.movingBackAfter ~= nil then t.movingStillAfter = t.movingBackAfter end
		end
		SplitStill(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				SplitStill(saved)
				if type(saved.settings) == "table" then SplitStill(saved.settings) end
			end
		end
		for _, point in pairs(ns.db.profileResetPoints or {}) do
			if type(point) == "table" then SplitStill(point) end
		end
		ns.db.movingStillV1 = true
	end
	-- Allow outside CineMode (CineMode page, 2026-11-13) is the one place a
	-- vision is held to CineMode: Damage Vision's In CineMode tick, and the
	-- CineMode column on Damage Vision's and Vitals Vision's Show in rows,
	-- went. Either ticked: its row's Always ticked, and not outside CineMode.
	if not ns.db.outsideCineV1 then
		local function Move(t)
			local ticks = type(t.cineModeShow) == "table" and t.cineModeShow or nil
			-- (Already Always: the CineMode tick added nothing, it stays everywhere.)
			if ticks and ticks["damage:vision"] == true and t.damageVisionAlways ~= true then
				t.damageVisionAlways = true
				t.outsideCineDamage = false
			end
			if t.damageVisionOnlyCine == true then t.outsideCineDamage = false end
			if ticks and ticks["vision:lowHealth"] == true and t.lowHealthAlways == false then -- (nil: Always, its default)
				t.lowHealthAlways = true
				t.outsideCineVitals = false
			end
			t.damageVisionOnlyCine = nil
			if ticks then
				ticks["damage:vision"] = nil
				ticks["vision:lowHealth"] = nil
			end
		end
		Move(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				Move(saved)
				if type(saved.settings) == "table" then Move(saved.settings) end
			end
		end
		for _, point in pairs(ns.db.profileResetPoints or {}) do
			if type(point) == "table" then Move(point) end
		end
		ns.db.outsideCineV1 = true
	end
end

-- (Step 15.)
STEPS[#STEPS + 1] = function()
	-- No CineMode column or CQL word now (ns.DropCineModeWord): last, after
	-- the updates above that read the column's ticks. Once, everywhere.
	if not ns.db.cineModeWordGoneV1 then
		ns.DropCineModeWord(ns.db)
		for _, saved in pairs(ns.db.profiles or {}) do
			if type(saved) == "table" then
				ns.DropCineModeWord(saved)
				ns.DropCineModeWord(saved.settings)
			end
		end
		for _, point in pairs(ns.db.profileResetPoints or {}) do ns.DropCineModeWord(point) end
		ns.db.cineModeWordGoneV1 = true
	end
end

-- Runs them all, each on its own: an error is logged and reported (the
-- addon's error net, Diagnostics.lua), and the steps after it still run.
function ns.RunMigrations()
	for index, step in ipairs(STEPS) do
		local ok, err = xpcall(step, function(message)
			return tostring(message) .. "\n" .. (debugstack and debugstack(2) or "")
		end)
		if not ok then
			ns.migrationErrors = ns.migrationErrors or {}
			ns.migrationErrors[#ns.migrationErrors + 1] = ("step %d: %s"):format(index, tostring(err):match("^[^\n]*"))
			if ns.ReportError then pcall(ns.ReportError, err) end
		end
	end
end
