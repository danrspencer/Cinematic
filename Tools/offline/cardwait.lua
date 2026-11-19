-- Card wait test (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/cardwait.lua < /dev/null
-- The Rested card waiting while DaylightUI's zone title is on screen
-- (ns.AddCardWait in Cards.lua, used by Support/DaylightUI.lua: the user's
-- pick 2026-11-19, two place names at once at an inn). On the stand-in game
-- with a clock of its own: the card waits while the title shows, shows once
-- it's gone, gives up after 8 s, shows at once with no title, and other
-- cards don't wait. Says PASS or FAIL per check.
-- (Optional first argument: another .toc to load, to run it on older code.)
local now = 100
local timers = {}

-- luacheck: push ignore 111 112 113 121 122 212
local ns, wow = dofile("Tools/offline/load.lua")("forever", arg and arg[1], function()
	GetTime = function() return now end
	C_Timer.After = function(seconds, fn) timers[#timers + 1] = { at = now + (seconds or 0), fn = fn } end
end)
-- luacheck: pop

-- The clock moved on in tenths, running each timer as it comes due.
local function Advance(seconds)
	local stop = now + seconds
	while now < stop - 1e-9 do
		now = math.min(stop, now + 0.1)
		local due = {}
		for i = #timers, 1, -1 do
			if timers[i].at <= now + 1e-9 then
				due[#due + 1] = timers[i]
				table.remove(timers, i)
			end
		end
		table.sort(due, function(a, b) return a.at < b.at end)
		for _, timer in ipairs(due) do pcall(timer.fn) end
		-- (The card frame's own fades and holds run on its OnUpdate.)
		local screen = _G.CinematicCard
		local update = screen and screen._scripts and screen._scripts.OnUpdate
		if update then pcall(update, screen, 0.1) end
	end
end

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

-- What the card code says, for the checks.
local logged = {}
local log = ns.Log
ns.Log = function(kind, text, ...)
	if kind == "card" then logged[#logged + 1] = tostring(text) end
	return log(kind, text, ...)
end
local function Said(pattern)
	for _, line in ipairs(logged) do
		if line:find(pattern) then return line end
	end
	return nil
end

-- DaylightUI: its Quality of Life part loading (our support's setup runs),
-- its zone title a frame we show and hide.
_G.DaylightUI = { Get = function() return true end }
local title = CreateFrame("Frame", "DaylightUIZoneTitle", UIParent)
title:Hide()
local yieldsBefore = ns.FeatureYieldedTo and ns.FeatureYieldedTo("card:zone")
wow.Fire("ADDON_LOADED", "DaylightUI")
wow.Fire("ADDON_LOADED", "DaylightUI_QoL")
-- (Its Zone card row there now, and DaylightUI's own on: the setup ran.)
local yields = ns.FeatureYieldedTo and ns.FeatureYieldedTo("card:zone")
Check("our DaylightUI setup ran", yields == "DaylightUI" and not yieldsBefore, tostring(yields))

ns.db.cards = true
ns.db.cardRestedOn = true
local function Card(name) return { name = name, sub = "Rested" } end
local function Playing() local card = ns.Cards.Current() return card and card.id or nil end
local function Clear()
	pcall(ns.Cards.Cut, "rested")
	pcall(ns.Cards.Cut, "arrival")
	Advance(3)
	logged = {}
end

local allowed, why = ns.CardAllowed("rested")
Check("Rested card allowed on the stand-in", allowed, why)

-- 1. The title up: it waits, then shows once the title's gone.
Clear()
title:Show()
local ok, fired1 = pcall(ns.Cards.Fire, "rested", Card("Lion's Pride Inn"))
Check("title up: Fire takes it (waits)", ok and fired1 == true, tostring(fired1))
Check("title up: not on screen yet", Playing() ~= "rested", Playing())
Check("title up: logged why it waits", Said("^rested waits: DaylightUI"), logged[1])
Advance(2)
Check("title up 2 s on: still waiting", Playing() ~= "rested", Playing())
title:Hide()
Advance(1)
Check("title gone: Rested card on screen", Playing() == "rested", Playing())
Check("title gone: logged it shows now", Said("^rested: waited [%d.]+ s, shows now"), Said("^rested: waited"))

-- 2. The title never goes: shown anyway after 8 s.
Clear()
title:Show()
pcall(ns.Cards.Fire, "rested", Card("Old Town"))
Advance(7)
Check("title stuck 7 s: still waiting", Playing() ~= "rested", Playing())
Advance(2)
Check("title stuck 9 s: shown anyway", Playing() == "rested", Playing())
Check("title stuck: logged it gave up", Said("gave up waiting"), Said("^rested: waited"))
title:Hide()

-- 3. No title: at once.
Clear()
pcall(ns.Cards.Fire, "rested", Card("Stormwind City"))
Check("no title: shown at once", Playing() == "rested", Playing())
Check("no title: nothing about waiting", not Said("waits"), Said("waits"))

-- 4. Another card with the title up: doesn't wait.
Clear()
ns.db.cardArrivalOn = true
title:Show()
local arrival = ns.CardAllowed("arrival")
if arrival then
	pcall(ns.Cards.Fire, "arrival", { name = "Booty Bay", sub = "Arrived" })
	Check("another card, title up: shown at once", Playing() == "arrival", Playing())
else
	print("note: the Arrival card isn't allowed on the stand-in, check 4 skipped")
end
title:Hide()

print(fails == 0 and "all checks passed" or (fails .. " check(s) failed"))
os.exit(fails == 0 and 0 or 1)
