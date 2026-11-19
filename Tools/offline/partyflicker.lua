-- Party flicker test (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/partyflicker.lua < /dev/null
-- A stand-in for DaylightUI's party tile on Forever (a player's clip,
-- 2026-11-18): its range fade dims an out-of-range member 5 times a second
-- with SetAlphaFromBoolean, so its alpha reads back secret. Cinematic fades
-- the tile as its own (hooked, like Support/DaylightUI.lua does), and the
-- frame passes must leave that dim alone while not fading, and put our fade
-- back the moment it repaints while fading. Says PASS or FAIL per check.
-- (Optional first argument: another .toc to load, to run it on older code.)
local NAME = "DaylightUIPartyHeaderUnitButton1"
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local DIM = 0.4

-- luacheck: push ignore 111 112 113 121 122 212
local ns = dofile("Tools/offline/load.lua")("forever", arg and arg[1], function()
	issecretvalue = function(value) return value == SECRET end
	-- (Real hooks only on the test tile: the rest of the stand-in as before.)
	hooksecurefunc = function(target, method, fn)
		if type(target) == "table" and rawget(target, "_partyTest") then
			local old = target[method]
			target[method] = function(...)
				old(...)
				fn(...)
			end
		end
	end
end)
-- luacheck: pop

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

-- The tile: its alpha as set (secret after a boolean paint) and as drawn.
local tile = CreateFrame("Button", NAME, UIParent)
rawset(tile, "_partyTest", true)
tile._alpha, tile._drawn = 1, 1
tile.SetAlpha = function(self, alpha) self._alpha, self._drawn = alpha, alpha end
tile.GetAlpha = function(self) return self._alpha end
tile.SetAlphaFromBoolean = function(self, on, yes, no)
	self._alpha, self._drawn = SECRET, on and yes or no
end
-- Its range tick: an out-of-range member (the answer itself secret).
local function RangeTick() tile:SetAlphaFromBoolean(false, 1, DIM) end

ns.db.handleFrames = true
-- (The stand-in's chat frames are stubs whose parents never end: that walk is
-- skipped, it has nothing to do with this.)
ns.MarkChatHolders = function() end
ns.FadeWithRow("party", "party", { NAME }, true, true)
local ok, err = pcall(ns.BuildManagedList)
if not ok then print("note: the frame scan errored on the stand-in: " .. tostring(err)) end
-- A frame pass: the whole one, and its own-alpha step on its own (the one
-- that wrote full alpha over the dim) in case the stand-in cuts the pass short.
local function Pass()
	pcall(ns.UpdateFrames, false, 0.2)
	ns.SyncOwnAlphas()
end
local entry
for _, each in ipairs(ns.managed) do
	if each.frame == tile then entry = each end
end
Check("tile is faded as its own, hooked", entry and entry.ownAlpha)
if not entry then
	print("1 check(s) failed")
	os.exit(1)
end

-- 1. Not fading: its dim stays through our passes.
RangeTick()
local worst = tile._drawn
for _ = 1, 10 do
	Pass()
	if tile._drawn ~= DIM then worst = tile._drawn end
	RangeTick()
end
Check("out of range, not faded: dim kept through 10 passes", worst == DIM, "drawn " .. tostring(worst))

-- 2. Fading (CineMode hides it): its repaint never shows.
ns.SetEntryAlpha(entry, 0)
Check("faded: drawn at 0", tile._drawn == 0, "drawn " .. tostring(tile._drawn))
RangeTick()
Check("faded: its range repaint put straight back to 0", tile._drawn == 0, "drawn " .. tostring(tile._drawn))

-- 3. Fade over: back up, then its dim stays again.
ns.SetEntryAlpha(entry, 1)
Check("fade over: drawn at full", tile._drawn == 1, "drawn " .. tostring(tile._drawn))
RangeTick()
Pass()
Check("fade over: its dim kept after a pass", tile._drawn == DIM, "drawn " .. tostring(tile._drawn))

-- 4. Back in range (a plain number): taken as its alpha, as before.
tile:SetAlpha(1)
Pass()
Check("back in range: full", tile._drawn == 1, "drawn " .. tostring(tile._drawn))
ns.SetEntryAlpha(entry, 0.5)
Check("back in range, half faded: 0.5", math.abs(tile._drawn - 0.5) < 0.01, "drawn " .. tostring(tile._drawn))

print(fails == 0 and "all checks passed" or (fails .. " check(s) failed"))
os.exit(fails == 0 and 0 or 1)
