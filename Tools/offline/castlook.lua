-- Cast bar "other kind's game look" test (dev tool, offline, Lua 5.1 via
-- Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/castlook.lua <forever|retail> < /dev/null
-- These bars' pick of the other kind's game look (PlateCastStyle.lua's
-- GameAs and DressAs, 2026-11-19), on the style lab's real-layout stand-in
-- (Tools/style-lab/frames.lua), through the same sample the pages' previews
-- use (ns.MakeCastLookSample; the game's templates aren't here, so it's the
-- drawn stand-in, which has the same part names):
--   a target bar in the nameplates' look: its border hidden, the name left
--     beside a 12 wide icon; then off: the name, its anchors and the icon as
--     they were;
--   a nameplate bar in the unit frames' look: their border on it, the name
--     centered, a 20 wide icon; then off: the border gone, all as it was.
-- Says PASS or FAIL per check; exits 1 on any FAIL.
local F = dofile("Tools/style-lab/frames.lua")
local client = ... or "forever"

-- luacheck: push ignore 111 112 113 121 122 212
local ns = dofile("Tools/offline/load.lua")(client, "CinematicDev.toc", function(w)
	F.Install(w)
	rawset(_G, "CreateFontFamily", false)
end)
-- luacheck: pop

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print(("%s %s: %s%s"):format(ok and "PASS" or "FAIL", client, name, detail and (" (" .. tostring(detail) .. ")") or ""))
end

local db = ns.GetDB()
-- (Each cast page on, and every switch it's under: Unit Frames' and the
-- nameplates' style pages, the Style hub's. Off on a fresh install.)
for _, key in ipairs({ "unitCastStyle", "playerCastStyle", "plateCastStyle" }) do
	local switch = key
	while switch do
		db[switch] = true
		switch = ns.PageSwitchOf(switch)
	end
end
local function Points(region)
	local list = {}
	for i = 1, region:GetNumPoints() do
		local point, relative, relativePoint, x, y = region:GetPoint(i)
		list[#list + 1] = ("%s>%s.%s %s,%s"):format(tostring(point), tostring(relative), tostring(relativePoint),
			tostring(x), tostring(y))
	end
	return table.concat(list, " ")
end
local function Snapshot(bar)
	return { justify = bar.Text:GetJustifyH(), text = Points(bar.Text), icon = Points(bar.Icon),
		iconW = bar.Icon:GetWidth() }
end
local function UnitBorderOn(bar)
	for _, region in ipairs({ bar:GetRegions() }) do
		local atlas = region.GetAtlas and region:GetAtlas()
		if atlas == "UI-CastingBar-Frame" and region ~= bar.Border and region:IsShown() then return true end
	end
	return false
end

Check("sample maker there", ns.MakeCastLookSample ~= nil)
if not ns.MakeCastLookSample then os.exit(1) end

-- Your bar in the nameplates' game look, then back (only You has the pick for
-- now: the target's and bosses' anchors are secret on Forever, AsHeld).
db.unitCastStyle = true
db.plateCastOn_PLAYER, db.plateCastFrame_PLAYER, db.plateCastGameAs_PLAYER = true, false, false
local target = ns.MakeCastLookSample(UIParent, "unit", 2, "PLAYER")
target:Refresh()
local before = Snapshot(target)
db.plateCastGameAs_PLAYER = true
target:Refresh()
local border = target.Border
Check("your bar: border hidden", border and border:GetAlpha() < 0.01, border and border:GetAlpha())
Check("your bar: name on the left", target.Text:GetJustifyH() == "LEFT", target.Text:GetJustifyH())
Check("your bar: icon 12 wide", math.abs(target.Icon:GetWidth() - 12) < 0.01, target.Icon:GetWidth())
Check("your bar: name beside the icon", Points(target.Text):find("LEFT>", 1, true) == 1, Points(target.Text))
db.plateCastGameAs_PLAYER = false
target:Refresh()
local after = Snapshot(target)
Check("your bar back: name justify", after.justify == before.justify, after.justify .. " was " .. before.justify)
Check("your bar back: name anchors", after.text == before.text, after.text .. " | was " .. before.text)
Check("your bar back: icon anchors", after.icon == before.icon, after.icon .. " | was " .. before.icon)
Check("your bar back: icon size", math.abs(after.iconW - before.iconW) < 0.01, after.iconW .. " was " .. before.iconW)
Check("your bar back: border shown", border and border:GetAlpha() > 0.5, border and border:GetAlpha())

-- A saved Nameplates' pick on the target's row is held back: the game's look.
db.plateCastOn_TARGET, db.plateCastFrame_TARGET, db.plateCastGameAs_TARGET = true, false, false
local held = ns.MakeCastLookSample(UIParent, "unit", 1, "TARGET")
held:Refresh()
local heldBefore = Snapshot(held)
db.plateCastGameAs_TARGET = true
held:Refresh()
local heldNow = Snapshot(held)
Check("target: Nameplates' pick held back (name)", heldNow.justify == heldBefore.justify and heldNow.text == heldBefore.text,
	heldNow.justify .. " " .. heldNow.text)
Check("target: Nameplates' pick held back (border shown)", held.Border and held.Border:GetAlpha() > 0.5,
	held.Border and held.Border:GetAlpha())
db.plateCastGameAs_TARGET = false

-- A nameplate bar in the unit frames' game look, then back.
db.plateCastStyle = true
db.plateCastOwn_PLATE, db.plateCastGameAs_PLATE = false, false
local plate = ns.MakeCastLookSample(UIParent, "plate", 1, "PLATE")
plate:Refresh()
local plateBefore = Snapshot(plate)
Check("plate: no unit border to start", not UnitBorderOn(plate))
db.plateCastGameAs_PLATE = true
plate:Refresh()
Check("plate: unit frames' border on", UnitBorderOn(plate))
Check("plate: name centered", plate.Text:GetJustifyH() == "CENTER", plate.Text:GetJustifyH())
Check("plate: icon 20 wide", math.abs(plate.Icon:GetWidth() - 20) < 0.01, plate.Icon:GetWidth())
db.plateCastGameAs_PLATE = false
plate:Refresh()
local plateAfter = Snapshot(plate)
Check("plate back: border gone", not UnitBorderOn(plate))
Check("plate back: name justify", plateAfter.justify == plateBefore.justify, plateAfter.justify)
Check("plate back: name anchors", plateAfter.text == plateBefore.text, plateAfter.text .. " | was " .. plateBefore.text)
Check("plate back: icon size", math.abs(plateAfter.iconW - plateBefore.iconW) < 0.01, plateAfter.iconW)

-- The theme's Interface Recolor on your cast bar's art (irCast): the
-- preview's "You" bar asks for that row's tint, as your real bar has it
-- (2026-11-19: yours purple, the preview gold); the target's doesn't (the
-- game's target bar isn't in the row). The tint itself needs the game's
-- template parts: the in-game match test compares the colors.
do
	local asked = {}
	local recolor = ns.RecolorLike
	ns.RecolorLike = function(frame, key) asked[frame] = key end
	local you = ns.MakeCastLookSample(UIParent, "player", 1, "PLAYER")
	you:Refresh()
	Check("recolor: your bar's preview tinted as the irCast row", asked[you] == "irCast", asked[you])
	local them = ns.MakeCastLookSample(UIParent, "unit", 1, "TARGET")
	them:Refresh()
	Check("recolor: the target's preview left as the game's", asked[them] == nil, asked[them])
	ns.RecolorLike = recolor
	Check("recolor: Interface Recolor has RecolorLike", type(recolor) == "function")
end

-- In a fight: a plate's name alpha and sizes are secret (Forever,
-- 2026-11-19: "attempt to compare a secret number value", 22 times). A
-- stand-in secret: a table, which errors when compared as a number, as the
-- game's do.
local SECRET = { secret = true }
local secretCheck = _G.issecretvalue
_G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
db.plateCastGameAs_PLATE = false
local fight = ns.MakeCastLookSample(UIParent, "plate", 1, "PLATE")
fight:Refresh()
fight.Text.GetAlpha = function() return SECRET end
for _, region in ipairs({ fight.Text, fight.Icon, fight.Spark }) do
	region.GetSize = function() return SECRET, SECRET end
	region.GetWidth = function() return SECRET end
	region.GetHeight = function() return SECRET end
end
db.plateCastGameAs_PLATE = true
local okOn, errOn = pcall(fight.Refresh, fight)
Check("fight: unit frames' look on with secret alpha and sizes", okOn, errOn)
Check("fight: their border on", UnitBorderOn(fight))
db.plateCastGameAs_PLATE = false
local okOff, errOff = pcall(fight.Refresh, fight)
Check("fight: taken off with secret sizes", okOff, errOff)
_G.issecretvalue = secretCheck

-- Your cast bar its own tab (2026-11-20): its switch is Your Cast Bar's
-- (playerCastStyle), not the Cast Bars tab's (unitCastStyle), each under the
-- Unit Frames style icon.
Check("your bar's tab switch under Unit Frames' style", ns.PageSwitchOf("playerCastStyle") == "ufStyle",
	ns.PageSwitchOf("playerCastStyle"))
db.plateCastOn_PLAYER, db.plateCastFrame_PLAYER, db.plateCastGameAs_PLAYER = true, false, true
local mine = ns.MakeCastLookSample(UIParent, "unit", 1, "PLAYER")
db.unitCastStyle = false
mine:Refresh()
Check("Cast Bars tab off: your bar keeps its look", mine.Text:GetJustifyH() == "LEFT", mine.Text:GetJustifyH())
db.unitCastStyle, db.playerCastStyle = true, false
mine:Refresh()
Check("Your Cast Bar tab off: your bar the game's", mine.Text:GetJustifyH() ~= "LEFT", mine.Text:GetJustifyH())
db.playerCastStyle, db.plateCastGameAs_PLAYER = true, false
mine:Refresh()

print(("castlook %s: %d FAIL"):format(client, fails))
if fails > 0 then os.exit(1) end
