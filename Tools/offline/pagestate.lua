-- Page snapshot check (offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/pagestate.lua < /dev/null
-- /cine debug pagestate (Dev/PageStateDebug.lua, dev copy) on the stand-in:
-- the command reaches it; with no preview on screen it says so; with the
-- Combat Text Style page's preview shown it logs the preview, its spot, the
-- page's view and what hangs from it (the tab row's base), with no errors,
-- and a frame the game couldn't place is called out. Says PASS or FAIL.
-- luacheck: push ignore 111 112 113 121 122 212
local ns = dofile("Tools/offline/load.lua")("forever", "CinematicDev.toc")
Screenshot = function() end
local printed = ""
ns.Print = function(text) printed = tostring(text) end
-- luacheck: pop

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end
local function Has(text)
	for _, line in ipairs(CinematicDB.pageStateLog or {}) do
		if line:find(text, 1, true) then return line end
	end
end

Check("the command is on ns", type(ns.PageStateDebug) == "function")
local real, called = ns.PageStateDebug, nil
ns.PageStateDebug = function() called = true end
ns.HandleSlash("debug pagestate")
Check("/cine debug pagestate starts it", called == true)
ns.PageStateDebug = real

-- 1. No preview on screen.
for _, preview in ipairs(ns.STYLE_PREVIEWS or {}) do
	preview:Hide()
	if preview.stackSpot then preview.stackSpot:Hide() end
end
ns.PageStateDebug()
Check("header logged", Has("pagestate ") ~= nil)
Check("no preview said", Has("no Style preview on screen") ~= nil)
Check("chat line", printed:find("pagestate: 0 previews", 1, true) ~= nil, printed)

-- 2. The Combat Text Style preview on screen (its page's: the tab row hangs from it).
local target
for _, preview in ipairs(ns.STYLE_PREVIEWS or {}) do
	if preview.stackSpot and preview.stackSpot:GetParent() then
		local ok, text = pcall(function() return preview.popTitle end)
		if ok and text == nil and not target then target = preview end
	end
end
target = target or (ns.STYLE_PREVIEWS or {})[1]
Check("a preview to look at", target ~= nil)
if target then
	target:Show()
	-- (The stand-in has no anchors: one frame hung from it, as the tab row's base.)
	local base = CreateFrame("Frame", nil, target.stackSpot:GetParent())
	base.GetNumPoints = function() return 1 end
	base.GetPoint = function() return "TOPLEFT", target, "BOTTOMLEFT", 0, -36 end
	base.GetRect = function() return nil end
	ns.PageStateDebug()
	Check("preview logged", Has("preview [preview]") ~= nil)
	Check("spot logged", Has("spot [spot]") ~= nil)
	Check("sticky state logged", Has("sticky:") ~= nil)
	Check("the base hanging from it", Has("hangs from preview") ~= nil)
	Check("its chain", Has("chain: hanging1 -> preview") ~= nil)
	Check("unplaced called out", Has("place: NONE") ~= nil)
	Check("no errors", not Has("error"))
end

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
if fails > 0 then os.exit(1) end
