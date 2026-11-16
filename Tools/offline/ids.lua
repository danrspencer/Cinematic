-- Every /cine find id, as the settings build them, outside the game (the
-- /support skill's find_ids.py reads it). From the repo root:
--
--   lua5.1 Tools/offline/ids.lua <client> [toc]
--   python -I Tools/offline/run.py Tools/offline/ids.lua forever Cinematic.toc    (no lua5.1)
--
-- Prints one tab-separated line per id: "id", the id, its page, its label
-- (ns.SettingIds, as /cine debug ids lists them), then "hidden" lines for
-- each ns.DEFAULTS key no control has (only /run CinematicDB.key=value
-- reaches it), with its default.

local client, toc = arg[1] or "forever", arg[2] or "Cinematic.toc"
local ns = dofile("Tools/offline/load.lua")(client, toc)
local with = ns.SettingIds()
local seen = {}
for _, line in ipairs(with) do
	local id, page, label = line:match("^(.-) | (.-) | (.*)$")
	if id then
		seen[id] = true
		-- (A Show in row has no label of its own: its row's name, from the
		-- HUD rows or the other addons' frames.)
		local rowKey = label == "" and id:match("^row:(.+)$")
		if rowKey then
			label = ns.RowLabel(rowKey) or ""
			local addonKey = rowKey:match("^addon:(.+)$")
			for _, item in ipairs(addonKey and ns.ADDON_FRAMES or {}) do
				if item.key == addonKey then label = (item.addon or "") .. " " .. (item.label or "") end
			end
		end
		print(("id\t%s\t%s\t%s"):format(id, page, label))
	end
end
local keys = {}
for key in pairs(ns.DEFAULTS) do
	if not seen[key] then keys[#keys + 1] = key end
end
table.sort(keys)
for _, key in ipairs(keys) do
	local value = ns.DEFAULTS[key]
	if type(value) ~= "table" and type(value) ~= "function" then
		print(("hidden\t%s\t%s\t%s"):format(key, type(value), tostring(value)))
	end
end
