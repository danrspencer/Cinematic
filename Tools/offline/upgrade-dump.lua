-- One side of the upgrade check (Tools/upgrade-check.py): the addon loaded
-- on the stand-in game with a player's saved settings, as an update would
-- (done-flags kept: only updates the player hasn't had run), and what it
-- leaves written out, sorted, to compare with another version's.
--
--   lua5.1 Tools/offline/upgrade-dump.lua <client> <toc> <saved file|fresh> <out> [saved out]
--
-- fresh: no saved settings, a new install. <out> gets the settings as
-- "db[...] = value" lines, then the defaults as "default[...] = value"
-- lines; [saved out], when given, gets CinematicDB as a SavedVariables file
-- (what the game would write at logout), for the next version to load.
-- (Done-flags named in CINE_DROP_FLAGS, comma-separated, are taken off the
-- loaded file first: updates newer than the version that wrote it. With
-- CINE_FLIP=1 every top-level on/off setting is turned the other way first:
-- a player who changed everything.)
local client, toc, savedPath, outPath, savedOut = ...
assert(client and toc and savedPath and outPath,
	"usage: upgrade-dump.lua <client> <toc> <saved file|fresh> <out> [saved out]")

local db
if savedPath ~= "fresh" then
	local saved = {}
	local chunk = assert(loadfile(savedPath))
	setfenv(chunk, saved)
	chunk()
	db = assert(saved.CinematicDB, "no CinematicDB in " .. savedPath)
	for flag in (os.getenv("CINE_DROP_FLAGS") or ""):gmatch("[^,]+") do db[flag] = nil end
	if os.getenv("CINE_FLIP") == "1" then
		for key, value in pairs(db) do
			if type(value) == "boolean" and not key:find("V%d+$") then db[key] = not value end
		end
	end
end

math.randomseed(1)
local ns, wow = dofile("Tools/offline/load.lua")(client, toc, function()
	local now = 1700000000
	_G.time = function(t) return t and os.time(t) or now end
	_G.GetServerTime = function() return now end
	_G.date = function(format, at) return os.date(format, at or now) end
	_G.CinematicDB = db
end)
assert(ns.db, "the addon didn't load its settings")
local failed = false
for _, problem in ipairs(ns.migrationErrors or {}) do
	print("update failed: " .. problem)
	failed = true
end
for _, warning in ipairs(wow.warnings or {}) do print("warning: " .. warning) end

local function Key(k)
	return type(k) == "string" and ("%q"):format(k) or tostring(k)
end
local function Value(v)
	if type(v) == "number" then return ("%.14g"):format(v) end
	if type(v) == "string" then return ("%q"):format(v) end
	return tostring(v)
end
local function Sorted(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) and (type(a) == "string" or type(a) == "number") then return a < b end
		return type(a) < type(b)
	end)
	return keys
end
local out, seen = {}, {}
local function Dump(t, path)
	if seen[t] then return end
	seen[t] = true
	for _, k in ipairs(Sorted(t)) do
		local v, here = t[k], path .. "[" .. Key(k) .. "]"
		if type(v) == "table" then
			if next(v) == nil then out[#out + 1] = here .. " = {}" else Dump(v, here) end
		elseif type(v) ~= "function" and type(v) ~= "userdata" then
			out[#out + 1] = here .. " = " .. Value(v)
		end
	end
	seen[t] = nil
end
Dump(ns.db, "db")
Dump(ns.DEFAULTS or {}, "default")
local file = assert(io.open(outPath, "w"))
file:write(table.concat(out, "\n"), "\n")
file:close()

-- As the game writes SavedVariables: plain values, nested tables.
if savedOut then
	local parts = { "CinematicDB = " }
	local function Write(v, indent)
		if type(v) ~= "table" then
			parts[#parts + 1] = Value(v)
			return
		end
		if seen[v] then parts[#parts + 1] = "{}" return end
		seen[v] = true
		parts[#parts + 1] = "{\n"
		for _, k in ipairs(Sorted(v)) do
			local item = v[k]
			if type(item) ~= "function" and type(item) ~= "userdata" then
				parts[#parts + 1] = indent .. "\t[" .. Key(k) .. "] = "
				Write(item, indent .. "\t")
				parts[#parts + 1] = ",\n"
			end
		end
		parts[#parts + 1] = indent .. "}"
		seen[v] = nil
	end
	Write(ns.db, "")
	parts[#parts + 1] = "\n"
	local saved = assert(io.open(savedOut, "w"))
	saved:write(table.concat(parts))
	saved:close()
end
print(("%s: %d lines written to %s"):format(client, #out, outPath))
if failed then os.exit(1) end
