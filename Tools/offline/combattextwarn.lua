-- Combat Text Style page's Experimental notice (offline, Lua 5.1 via
-- Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/combattextwarn.lua < /dev/null
-- Back at the top of the page (2026-11-20): our numbers can take someone
-- else's damage for yours. Checked on each client: the page builds with its
-- Experimental title and the notice. Says PASS or FAIL per check.
local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

local client = arg and arg[1] or "forever"
local _, wow = dofile("Tools/offline/load.lua")(client, "CinematicDev.toc")

-- Every font string's text, anywhere under any frame.
local function Find(text)
	local seen = {}
	local function Walk(object)
		if seen[object] then return end
		seen[object] = true
		if object._text == text then return object end
		for _, region in ipairs(object._regions or {}) do
			local found = Walk(region)
			if found then return found end
		end
	end
	for _, frame in ipairs(wow.frames) do
		local found = Walk(frame)
		if found then return found end
	end
end

local warn = Find("You may see other people's damage as your own.")
Check(client .. ": the notice is on the page", warn ~= nil)
Check(client .. ": its Experimental title too", Find("Experimental") ~= nil)
print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
if fails > 0 then os.exit(1) end
