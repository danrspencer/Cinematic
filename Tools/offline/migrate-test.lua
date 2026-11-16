-- The once-only settings updates (Migrations.lua, Core.lua's load), run on a
-- real saved settings file with every update's done-flag taken off, so each
-- one runs again; the settings they leave are written out, sorted, to compare
-- one version of the code with another (Tools/offline/migrate-compare.py).
--
--   lua5.1 Tools/offline/migrate-test.lua <client> <toc> <SavedVariables file> <out file>
--
-- (client: forever or retail. The file's CinematicDB is read as the game
-- would; the clock is held still, so two runs give the same file.)
local client, toc, savedPath, outPath = ...
assert(client and toc and savedPath and outPath, "usage: migrate-test.lua <client> <toc> <saved file> <out file>")

local saved = {}
local chunk = assert(loadfile(savedPath))
setfenv(chunk, saved)
chunk()
local db = assert(saved.CinematicDB, "no CinematicDB in " .. savedPath)

-- Every done-flag off: a key ending in V and a number, set to true.
local stripped = 0
for key, value in pairs(db) do
	if type(key) == "string" and key:find("V%d+$") and value == true then
		db[key] = nil
		stripped = stripped + 1
	end
end

math.randomseed(1)
local ns = dofile("Tools/offline/load.lua")(client, toc, function()
	local now = 1700000000
	_G.time = function(t) return t and os.time(t) or now end
	_G.GetServerTime = function() return now end
	_G.date = function(format, at) return os.date(format, at or now) end
	_G.CinematicDB = db
end)
assert(ns.db, "the addon didn't load its settings")
if ns.migrationErrors then
	for _, problem in ipairs(ns.migrationErrors) do print("update failed: " .. problem) end
	os.exit(1)
end

-- Sorted, so equal settings give equal files.
local out = {}
local function Key(k)
	return type(k) == "string" and ("%q"):format(k) or tostring(k)
end
local function Value(v)
	if type(v) == "number" then return ("%.14g"):format(v) end
	if type(v) == "string" then return ("%q"):format(v) end
	return tostring(v)
end
local seen = {}
local function Dump(t, path)
	if seen[t] then out[#out + 1] = path .. " = (seen above)" return end
	seen[t] = true
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) and (type(a) == "string" or type(a) == "number") then return a < b end
		return type(a) < type(b)
	end)
	for _, k in ipairs(keys) do
		local v, here = t[k], path .. "[" .. Key(k) .. "]"
		if type(v) == "table" then
			if next(v) == nil then out[#out + 1] = here .. " = {}" else Dump(v, here) end
		elseif type(v) ~= "function" and type(v) ~= "userdata" then
			out[#out + 1] = here .. " = " .. Value(v)
		end
	end
	seen[t] = nil
end
Dump(_G.CinematicDB, "db")
local file = assert(io.open(outPath, "w"))
file:write(table.concat(out, "\n"), "\n")
file:close()
print(("%s: %d done-flags taken off, %d lines written to %s"):format(client, stripped, #out, outPath))
