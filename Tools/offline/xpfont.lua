-- XP text font at login (offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/xpfont.lua < /dev/null
-- The game reads its floating text font (DAMAGE_TEXT_FONT: the "XP: 32"
-- over you, and its numbers) at each login (/cine debug xprelog, Forever
-- 2026-11-20). A player saw XP text come back "sometimes after a relog".
-- The font was picked from the settings as they were saved, before a
-- character's own profile was loaded over them at login, so a character
-- with its own profile got the last character's XP choice. Logs in four
-- times on one saved file, two characters, and checks each time that the
-- font is blank exactly when the settings logged in with hide the XP text.
-- Says PASS or FAIL per check.

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

local GAME_FONT = "Fonts\\FRIZQT__.TTF"
local savedDB -- CinematicDB, carried from one login to the next
local chars = { A = {}, B = {} } -- each character's CinematicCharDB

-- One login as who, on the saved settings so far. Returns ns.
local function Login(who)
	-- luacheck: push ignore 111 112 113 121 122
	local ns = dofile("Tools/offline/load.lua")("forever", "CinematicDev.toc", function()
		DAMAGE_TEXT_FONT = GAME_FONT
		CinematicDB = savedDB
		CinematicCharDB = chars[who]
	end)
	-- luacheck: pop
	savedDB = ns.db
	chars[who] = ns.chardb
	return ns
end

-- Whether the font matches the settings this login runs with.
local function CheckFont(name, ns)
	local db = ns.db
	local want = db.hideWorldText and db.combatTextStyle and db.styleGeneral ~= false and true or false
	local blank = type(DAMAGE_TEXT_FONT) == "string" and DAMAGE_TEXT_FONT:find("Blank%.ttf$") ~= nil
	Check(name, blank == want, ("profile %s, XP hidden in the settings %s, font %s"):format(tostring(ns.ActiveProfile()),
		tostring(want), blank and "blank" or tostring(DAMAGE_TEXT_FONT)))
	return want
end

-- 1: character A, a fresh install: XP hidden in a profile of its own; the
-- account's profile left with XP shown.
local ns = Login("A")
local accountProfile = ns.db.profile
ns.db.profileChosen = true
ns.NewProfile("XP Hidden")
ns.db.styleGeneral, ns.db.combatTextStyle, ns.db.hideWorldText = true, true, true
ns.SetCharacterProfile(true)
ns.db.profile = accountProfile -- (the account's stays the one it was)
ns.SaveProfile() -- (as at logout)
Check("1 A has its own profile", chars.A.profile == "XP Hidden", tostring(chars.A.profile))

-- 2: character B, on the account's profile: logs in after A.
ns = Login("B")
local shownForB = not CheckFont("2 B after A: font as B's settings", ns)
ns.SaveProfile()

-- 3: A again, after B: its own profile loads over B's settings at login.
ns = Login("A")
local hiddenForA = CheckFont("3 A after B: font as A's settings", ns)
ns.SaveProfile()

-- 4: A again, after A: nothing to load over.
ns = Login("A")
CheckFont("4 A after A: font as A's settings", ns)

-- (Logins 2 and 3 must differ, or the test proves nothing.)
Check("the two characters' XP choices differ", shownForB and hiddenForA,
	("B shown %s, A hidden %s"):format(tostring(shownForB), tostring(hiddenForA)))
print(fails == 0 and "all passed" or (fails .. " FAILED"))
