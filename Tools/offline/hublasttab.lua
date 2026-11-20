-- The tab last open under each settings icon (offline, Lua 5.1 via run.py):
--   python -I Tools/offline/run.py Tools/offline/hublasttab.lua <forever|retail>
-- db.hubLastTab (Options.lua's Select) is kept through a /reload and
-- forgotten by a real login (Core.lua's PLAYER_ENTERING_WORLD), so Card
-- Vision and the rest open on their own page after a logout. Says PASS or
-- FAIL per check.
local client = arg and arg[1] or "forever"
local ns, wow = dofile("Tools/offline/load.lua")(client)
local failed = 0
local function Check(ok, text)
	print((ok and "PASS " or "FAIL ") .. text)
	if not ok then failed = failed + 1 end
end

local function Saved() return ns.db.hubLastTab and ns.db.hubLastTab["Card Vision"] end

ns.db.hubLastTab = { ["Card Vision"] = "Card Settings" }
wow.Fire("PLAYER_ENTERING_WORLD", false, true) -- (a /reload)
Check(Saved() == "Card Settings", "a /reload keeps the tab last open (" .. tostring(Saved()) .. ")")

wow.Fire("PLAYER_ENTERING_WORLD", false, false) -- (a loading screen)
Check(Saved() == "Card Settings", "a loading screen keeps it (" .. tostring(Saved()) .. ")")

local warned = #wow.warnings
wow.Fire("PLAYER_ENTERING_WORLD", true, false) -- (a real login)
for i = warned + 1, #wow.warnings do print("WARN " .. wow.warnings[i]) end
Check(Saved() == nil, "a real login forgets it (" .. tostring(Saved()) .. ")")

-- One item's page (forget in HUBS: Card Settings, Card Style, Card Sounds,
-- Trigger Settings) isn't saved: its icon opens its list page next time.
-- A plain tab still is.
local function Open(name)
	if ns.MakeLazyPages then ns.MakeLazyPages("hublasttab test") end
	ns.OpenOptions(name)
	if ns.ShowHubPage then ns.ShowHubPage(name) end
end
local function Last(icon) return ns.db.hubLastTab and ns.db.hubLastTab[icon] end
Check(ns.ShowHubPage ~= nil, "ns.ShowHubPage is there to open pages with")
Open("Card General")
Check(Last("Card Vision") == "Card General", "Card Vision's Settings tab is saved (" .. tostring(Last("Card Vision")) .. ")")
for _, name in ipairs({ "Card Settings", "Card Style", "Card Sounds" }) do
	Open("Card General")
	Open(name)
	Check(Last("Card Vision") == nil, name .. " isn't saved: Events next time (" .. tostring(Last("Card Vision")) .. ")")
end
Open("Trigger Priority")
Check(Last("Triggers") == "Trigger Priority", "Triggers' Priority tab is saved (" .. tostring(Last("Triggers")) .. ")")
Open("Trigger Settings")
Check(Last("Triggers") == nil, "Trigger Settings isn't saved: the list next time (" .. tostring(Last("Triggers")) .. ")")

print(failed == 0 and "ALL PASS" or (failed .. " FAILED"))
if failed > 0 then os.exit(1) end
