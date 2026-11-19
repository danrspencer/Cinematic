-- Mac camera notch test (offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/notchgap.lua <forever|retail> < /dev/null
-- With the game's notch option on a Mac, UIParent sits lower than the world's
-- top. Full-screen effects (ns.CoverWorld: letterbox, tint and its edges,
-- death screen, Focus, low health, teleport) must reach up over that strip:
--   no notch: anchored flush to UIParent (gap 0);
--   a 32 high strip at UI scale 1, and the same strip at UI scale 0.8 (40 in
--     UIParent's units): the top point lifted by it, the bottom on UIParent's;
--   the gap shrinking back (option turned off): the frames come down again;
--   every effect's frame is one of these covers once built.
-- Says PASS or FAIL per check; exits 1 on any FAIL.
local client = ... or "forever"

-- luacheck: push ignore 111 112 113 121 122 212
local ns = dofile("Tools/offline/load.lua")(client, "CinematicDev.toc")
-- luacheck: pop

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print(("%s %s: %s%s"):format(ok and "PASS" or "FAIL", client, name, detail and (" (" .. tostring(detail) .. ")") or ""))
end

local UI, World = _G.UIParent, _G.WorldFrame
local function Screen(worldTop, uiTop, uiScale)
	World.GetTop = function() return worldTop end
	World.GetEffectiveScale = function() return 1 end
	UI.GetTop = function() return uiTop end
	UI.GetEffectiveScale = function() return uiScale end
end

-- Records a frame's points (the stand-in's SetPoint does nothing).
local function Track(frame)
	frame._points = {}
	frame.ClearAllPoints = function(self) self._points = {} end
	frame.SetPoint = function(self, point, rel, relPoint, x, y)
		self._points[point] = { rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
	end
	return frame
end

local function Flush(frame, gap, label)
	local top, bottom = frame._points.TOPLEFT, frame._points.BOTTOMRIGHT
	Check(label .. " top", top and top.rel == UI and top.relPoint == "TOPLEFT" and math.abs(top.y - gap) < 0.01,
		top and top.y)
	Check(label .. " bottom", bottom and bottom.rel == UI and bottom.relPoint == "BOTTOMRIGHT" and bottom.y == 0)
end

-- No notch.
Screen(768, 768, 1)
Check("no notch gap 0", ns.NotchGap() == 0, ns.NotchGap())
local cover = Track(_G.CreateFrame("Frame", nil, UI))
ns.CoverWorld(cover)
Flush(cover, 0, "no notch")

-- A 32 high strip at scale 1.
Screen(800, 768, 1)
ns.RefitWorldCovers()
Flush(cover, 32, "notch scale 1")

-- The same strip at UI scale 0.8: 40 in UIParent's units.
Screen(800, 960, 0.8) -- (the world's top is 1000 in UIParent's units)
Check("notch scale 0.8 gap", math.abs(ns.NotchGap() - 40) < 0.01, ns.NotchGap())
ns.RefitWorldCovers()
Flush(cover, 40, "notch scale 0.8")

-- Shown again after the option went off: fitted on show.
Screen(768, 768, 1)
cover._scripts.OnShow(cover)
Flush(cover, 0, "option off, on show")

-- Unreadable sizes (loading screen): no gap, no error.
Screen(nil, 768, 1)
Check("unreadable gap 0", ns.NotchGap() == 0)

-- The letterbox keeps the gap it lays the bars out with.
if ns.letterbox then
	Track(ns.letterbox)
	ns.letterbox.notchGap = nil
	Screen(800, 768, 1)
	ns.letterbox:Fit()
	Flush(ns.letterbox, 32, "letterbox")
	Check("letterbox gap", ns.letterbox.gap == 32, ns.letterbox.gap)
end

-- Every full-screen effect uses it (they build late, so read the source).
for _, file in ipairs({ "Atmosphere/Tint.lua", "Atmosphere/Focus.lua", "Atmosphere/LowHealth.lua",
	"Atmosphere/TeleportVision.lua", "Effects.lua" }) do
	local f = io.open(file, "rb")
	local text = f:read("*a")
	f:close()
	local covers = select(2, text:gsub("ns%.CoverWorld%(", ""))
	local want = file == "Atmosphere/Tint.lua" and 2 or 1
	Check(file .. " covers the notch", covers >= want, covers)
end

if fails > 0 then
	os.exit(1)
end
