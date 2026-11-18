-- The settings sweep (Dev/Sweep.lua, /cine debug sweep) run outside the game,
-- on the stand-in (wow.lua): every page opened, every setting changed and
-- put back. The stand-in's stubs make some FAIL lines of their own (a slider
-- that reads 0-1, a size that's always 0), so the FAIL lines are compared
-- with the last saved ones (sweep-baseline-<client>.txt) and only new ones
-- count. Exit 1 on a new one, or when the sweep doesn't finish.
--
--   lua5.1 Tools/offline/sweep.lua <client> [--update]
--   python -I Tools/offline/run.py Tools/offline/sweep.lua forever
--
-- --update saves this run's FAIL lines as the baseline (after a change
-- that's meant, or to take a fixed one off the list).
local client, flag = ...
assert(client == "forever" or client == "retail", "usage: sweep.lua <forever|retail> [--update]")
local update = flag == "--update"
local BASELINE = ("Tools/offline/sweep-baseline-%s.txt"):format(client)
local MAX_TICKS = 400000

local now = 0
-- (A clock that moves, in place before the files keep their own copy of
-- GetTime: the sweep waits between its steps.)
local ns = dofile("Tools/offline/load.lua")(client, "CinematicDev.toc", function()
	rawset(_G, "GetTime", function() return now end)
	rawset(_G, "GetFramerate", function() return 60 end)
	-- (Numbers the stand-in's stubs don't give: the tint's clock.)
	rawset(_G, "GetClockTime", function() return 12, 0 end)
	rawset(_G, "GetGameTime", function() return 12, 0 end)
end)

-- The sweep's driver runs from ns.SetOnUpdate: catch it and call it ourselves.
-- (Only its own frame, the last one set as it starts: the pages it opens set
-- and clear OnUpdates of their own.)
local driver, driverFrame, starting
local setOnUpdate = ns.SetOnUpdate
ns.SetOnUpdate = function(frame, fn)
	if starting and fn then driverFrame = frame end
	if frame == driverFrame then driver = fn end
	return setOnUpdate(frame, fn)
end

if not ns.SettingsSweep then
	print("sweep: no ns.SettingsSweep (Dev/Sweep.lua not in CinematicDev.toc?)")
	os.exit(1)
end
starting = true
ns.SettingsSweep("seed 1") -- (the same dropdown choices every run)
starting = false
if not driver then
	print("sweep: didn't start: " .. table.concat(CinematicDB.sweepLog or {}, " | "))
	os.exit(1)
end
local ticks = 0
while driver and ticks < MAX_TICKS do
	now = now + 1 / 60
	ticks = ticks + 1
	local fn = driver
	local ok, err = pcall(fn, nil, 1 / 60)
	if not ok then
		print("sweep: its driver errored: " .. tostring(err))
		os.exit(1)
	end
	-- (Finish takes the driver off: ns.SetOnUpdate(driver, nil).)
end

local log = CinematicDB.sweepLog or {}
if (os.getenv("SWEEP_DEBUG") or "") ~= "" then
	local shown = {}
	for _, line in ipairs(log) do
		local at = line:match("FAIL .-: Lua error[^:]*: ([%w/]+%.lua:%d+)")
		if at and not shown[at] then shown[at] = true print(line) end
	end
end
local summary
local fails, seen = {}, {}
for _, line in ipairs(log) do
	local text = line:gsub("^[%d%.]+ ", "")
	if text:find("^done: ") or text:find("^stopped: ") then summary = text end
	if text:find("^FAIL ") then
		-- (Numbers and the value tried out: the same fail on another run reads the same.)
		local key = text:gsub('setting ".-":', "setting:"):gsub("%-?%d+%.?%d*", "#")
		if not seen[key] then
			seen[key] = true
			fails[#fails + 1] = key
		end
	end
end
table.sort(fails)
print(("sweep %s: %s"):format(client, summary or "no summary (didn't finish)"))

if update then
	local out = assert(io.open(BASELINE, "w"))
	for _, key in ipairs(fails) do out:write(key, "\n") end
	out:close()
	print(("sweep %s: %d FAIL lines saved as the baseline (%s)"):format(client, #fails, BASELINE))
	os.exit(summary and summary:find("^done") and 0 or 1)
end

local known = {}
local file = io.open(BASELINE, "r")
if file then
	for line in file:lines() do known[(line:gsub("\r", ""))] = true end
	file:close()
end
local new, gone = {}, 0
for _, key in ipairs(fails) do
	if not known[key] then new[#new + 1] = key end
	known[key] = nil
end
for _ in pairs(known) do gone = gone + 1 end
for _, key in ipairs(new) do print("  NEW " .. key) end
if gone > 0 then
	print(("  %d baseline FAIL lines didn't come up this time (fixed? --update takes them off)"):format(gone))
end
print(("sweep %s: %d new FAIL lines (%d known)"):format(client, #new, #fails - #new))
local finished = summary and summary:find("^done")
os.exit((finished and #new == 0) and 0 or 1)
