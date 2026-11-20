-- Cast bar "other kind's game look" test (dev tool, offline, Lua 5.1 via
-- Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/castlook.lua <forever|retail> < /dev/null
-- These bars' pick of the other kind's game look (PlateCastStyle.lua's
-- GameAs and DressAs), on the style lab's real-layout stand-in
-- (Tools/style-lab/frames.lua), through the same sample the pages' previews
-- use (ns.MakeCastLookSample; the game's templates aren't here, so it's the
-- drawn stand-in, which has the same part names). The look draws its own
-- copy of the name and icon where it wants them and fades the game's out,
-- never moving them (since 2026-11-20: moving them failed where their place
-- is secret, Forever's target bar):
--   your bar and the target's in the nameplates' look: the border hidden,
--     our name shown on the left beside our 12 wide icon, the game's name
--     faded and still where the game put it; off: ours hidden, the game's
--     back, nothing of it moved;
--   a nameplate bar in the unit frames' look: their border on it, our name
--     centered under it, our icon 20 wide; off: all as it was;
--   the copies follow the game's words as it changes them;
--   in a fight, secret alpha and sizes: no error;
--   your bar's preview asks Interface Recolor for its tint;
--   each cast tab's switch reaches only its own bars.
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
local function UnitBorderOn(bar)
	for _, region in ipairs({ bar:GetRegions() }) do
		local atlas = region.GetAtlas and region:GetAtlas()
		if atlas == "UI-CastingBar-Frame" and region ~= bar.Border and region:IsShown() then return true end
	end
	return false
end
local function CopyShown(bar)
	local copy = bar.cinematicAsText
	return copy ~= nil and copy:IsShown()
end

Check("sample maker there", ns.MakeCastLookSample ~= nil)
if not ns.MakeCastLookSample then os.exit(1) end

-- Your bar and the target's in the nameplates' game look, then back.
for _, id in ipairs({ "PLAYER", "TARGET" }) do
	local who = id == "PLAYER" and "your bar" or "target"
	db["plateCastOn_" .. id], db["plateCastFrame_" .. id], db["plateCastGameAs_" .. id] = true, false, false
	local bar = ns.MakeCastLookSample(UIParent, "unit", 2, id)
	bar:Refresh()
	local gameText, gameIcon = Points(bar.Text), Points(bar.Icon)
	local gameJustify = bar.Text:GetJustifyH()
	db["plateCastGameAs_" .. id] = true
	bar:Refresh()
	local copy, copyIcon = bar.cinematicAsText, bar.cinematicAsIcon
	Check(who .. ": border hidden", bar.Border and bar.Border:GetAlpha() < 0.01, bar.Border and bar.Border:GetAlpha())
	Check(who .. ": our name shown, the game's faded", CopyShown(bar) and bar.Text:GetAlpha() < 0.01,
		tostring(CopyShown(bar)) .. " " .. bar.Text:GetAlpha())
	Check(who .. ": our name on the left", copy and copy:GetJustifyH() == "LEFT", copy and copy:GetJustifyH())
	Check(who .. ": our name says the spell", copy and copy:GetText() == bar.Text:GetText(), copy and copy:GetText())
	Check(who .. ": our icon 12 wide", copyIcon and math.abs(copyIcon:GetWidth() - 12) < 0.01,
		copyIcon and copyIcon:GetWidth())
	Check(who .. ": our name beside our icon", copy and Points(copy):find("LEFT>", 1, true) == 1, copy and Points(copy))
	Check(who .. ": the game's name not moved", Points(bar.Text) == gameText and Points(bar.Icon) == gameIcon
		and bar.Text:GetJustifyH() == gameJustify, Points(bar.Text))
	bar.Text:SetText("Frostbolt")
	Check(who .. ": our name follows the game's words", copy and copy:GetText() == "Frostbolt", copy and copy:GetText())
	db["plateCastGameAs_" .. id] = false
	bar:Refresh()
	Check(who .. " back: our name and icon hidden", not CopyShown(bar) and not (copyIcon and copyIcon:IsShown()))
	Check(who .. " back: the game's name shown", bar.Text:GetAlpha() > 0.5, bar.Text:GetAlpha())
	Check(who .. " back: border shown", bar.Border and bar.Border:GetAlpha() > 0.5, bar.Border and bar.Border:GetAlpha())
	Check(who .. " back: nothing of the game's moved", Points(bar.Text) == gameText and Points(bar.Icon) == gameIcon)
	db["plateCastOn_" .. id] = false
end

-- A nameplate bar in the unit frames' game look, then back.
db.plateCastOwn_PLATE, db.plateCastGameAs_PLATE = false, false
local plate = ns.MakeCastLookSample(UIParent, "plate", 1, "PLATE")
plate:Refresh()
local plateText = Points(plate.Text)
Check("plate: no unit border to start", not UnitBorderOn(plate))
db.plateCastGameAs_PLATE = true
plate:Refresh()
Check("plate: unit frames' border on", UnitBorderOn(plate))
Check("plate: our name centered", plate.cinematicAsText and plate.cinematicAsText:GetJustifyH() == "CENTER",
	plate.cinematicAsText and plate.cinematicAsText:GetJustifyH())
Check("plate: our name under the bar", plate.cinematicAsText and Points(plate.cinematicAsText):find("TOPLEFT>", 1, true) == 1,
	plate.cinematicAsText and Points(plate.cinematicAsText))
Check("plate: our icon 20 wide", plate.cinematicAsIcon and math.abs(plate.cinematicAsIcon:GetWidth() - 20) < 0.01,
	plate.cinematicAsIcon and plate.cinematicAsIcon:GetWidth())
db.plateCastGameAs_PLATE = false
plate:Refresh()
Check("plate back: border gone", not UnitBorderOn(plate))
Check("plate back: our name hidden, the game's shown", not CopyShown(plate) and plate.Text:GetAlpha() > 0.5)
Check("plate back: the game's name not moved", Points(plate.Text) == plateText, Points(plate.Text))

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
Check("Cast Bars tab off: your bar keeps its look", CopyShown(mine), tostring(CopyShown(mine)))
db.unitCastStyle, db.playerCastStyle = true, false
mine:Refresh()
Check("Your Cast Bar tab off: your bar the game's", not CopyShown(mine), tostring(CopyShown(mine)))
db.playerCastStyle, db.plateCastGameAs_PLAYER = true, false
mine:Refresh()

print(("castlook %s: %d FAIL"):format(client, fails))
if fails > 0 then os.exit(1) end
