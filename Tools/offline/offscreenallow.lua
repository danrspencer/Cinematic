-- Settings > General's Allow offscreen nameplates in CineMode (offline, Lua
-- 5.1 via run.py):
--   python -I Tools/offline/run.py Tools/offline/offscreenallow.lua <forever|retail>
-- plateOffscreen (Auto / Always / Never, Never to start with): the update
-- turns the old Nameplates tick (plateShowOffscreen) on into Always, here and
-- in saved profiles; Effects' ns.plates.OffscreenWhy turns the game's Show
-- Offscreen on only for Always, or Auto where a Vision needs it; the plates
-- pass never holds it off (yours stays); and the General tab has the
-- dropdown. Says PASS or FAIL per check.
local client = arg and arg[1] or "forever"
local ns = dofile("Tools/offline/load.lua")(client, nil, function()
	_G.CinematicDB = {
		plateOffscreenOffV1 = true, -- (the 2026-11-05 update: long done for real players)
		plateShowOffscreen = true,
		profiles = {
			Ticked = { settings = { plateShowOffscreen = true } },
			Unticked = { settings = { plateShowOffscreen = false } },
		},
	}
end)
local failed = 0
local function Check(ok, text)
	print((ok and "PASS " or "FAIL ") .. text)
	if not ok then failed = failed + 1 end
end
if ns.migrationErrors then
	for _, problem in ipairs(ns.migrationErrors) do print("update failed: " .. problem) end
end

-- The update.
local db = _G.CinematicDB
local ticked, unticked = db.profiles.Ticked.settings, db.profiles.Unticked.settings
Check(ns.db.plateOffscreen == "always", "the tick on becomes Always (" .. tostring(ns.db.plateOffscreen) .. ")")
Check(ns.db.plateShowOffscreen == nil, "the old key is gone (" .. tostring(ns.db.plateShowOffscreen) .. ")")
Check(ticked.plateOffscreen == "always" and ticked.plateShowOffscreen == nil,
	"a saved profile with it ticked: Always (" .. tostring(ticked.plateOffscreen) .. ")")
Check(unticked.plateOffscreen == nil and unticked.plateShowOffscreen == nil,
	"a saved profile with it unticked: the default (" .. tostring(unticked.plateOffscreen) .. ")")
Check(ns.DEFAULTS.plateOffscreen == "never", "Never to start with (" .. tostring(ns.DEFAULTS.plateOffscreen) .. ")")

-- Why CineMode turns it on, by choice. (Stand-ins for the Visions' wants,
-- CineMode holding plates here, and no target.)
local realForced, realHeal = ns.PlatesForcedHere, ns.HealVisionPlatesOn
ns.PlatesForcedHere = function(cinematic) return cinematic and true or false end
local healWants = false
ns.HealVisionPlatesOn = function() return healWants end
ns.plates.friendWants = ns.plates.friendWants or {}
ns.plates.friendWants.plateCards = false
local function Why(choice, cinematic)
	ns.db.plateOffscreen = choice
	return ns.plates.OffscreenWhy(cinematic)
end
Check(Why("never", true) == nil, "Never: not turned on")
healWants = true
Check(Why("never", true) == nil, "Never: not even for Heal Vision")
ns.plates.friendWants.plateCards = true
Check(Why("never", true) == nil, "Never: not even for Emote Vision's cards")
Check(Why("auto", true) ~= nil, "Auto: on for a Vision (" .. tostring(Why("auto", true)) .. ")")
healWants, ns.plates.friendWants.plateCards = false, false
Check(Why("auto", true) == nil, "Auto: off with no Vision wanting it")
Check(Why("always", true) ~= nil, "Always: on (" .. tostring(Why("always", true)) .. ")")
Check(Why("always", false) == nil, "Always: not outside CineMode")
ns.PlatesForcedHere = function() return false end
healWants = true
Check(Why("auto", true) == nil, "Auto: not where CineMode doesn't hold plates (dungeons)")
Check(Why("always", true) ~= nil, "Always: in dungeons too")
ns.PlatesForcedHere, ns.HealVisionPlatesOn = realForced, realHeal

-- Never held off by us: the off set is never taken up by a plates pass.
local applied = {}
local realApply = ns.ApplyCVarSet
ns.ApplyCVarSet = function(set, on)
	if set == ns.NO_OFFSCREEN_PLATE_CVARS and on then applied.off = true end
	if set == ns.OFFSCREEN_PLATE_CVARS and on then applied.on = true end
	return realApply(set, on)
end
ns.db.handlePlates = true
local passes = 0
for _, choice in ipairs({ "never", "auto", "always" }) do
	ns.db.plateOffscreen = choice
	ns.plates.seen = {} -- (no skip: a full pass each time)
	local ok, err = pcall(ns.UpdatePlates, true, 0.1)
	if ok then passes = passes + 1 else print("note: plates pass: " .. tostring(err)) end
end
ns.ApplyCVarSet = realApply
Check(passes == 3, "the plates pass ran for each choice (" .. passes .. " of 3)")
Check(not applied.off, "no choice holds Show Offscreen off")
Check(applied.on == true, "Always took the on set up in a pass")

-- The General tab's dropdown, and the old Nameplates tick gone.
local pages = ns.PageSettings()
local general = pages.Cinematic and pages.Cinematic.keys or {}
Check(general.plateOffscreen ~= nil, "Settings > General has the plateOffscreen setting (Reset, profiles)")
local elsewhere = {}
for name, page in pairs(pages) do
	if name ~= "Cinematic" and page.keys.plateOffscreen then elsewhere[#elsewhere + 1] = name end
	if page.keys.plateShowOffscreen then elsewhere[#elsewhere + 1] = name .. " (old tick)" end
end
Check(#elsewhere == 0, "on no other page, the old tick gone (" .. table.concat(elsewhere, ", ") .. ")")

print(failed == 0 and "ALL PASS" or (failed .. " FAILED"))
if failed > 0 then os.exit(1) end
