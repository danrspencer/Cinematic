-- Music volume never kept near 0 (offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/musicvolume.lua < /dev/null
-- A player's game Music slider sat at 0% though they never set it: the
-- remembered volume (musicVolume) and the game's were both 1.85625e-05, no
-- slider's value (5% steps) and none Cinematic writes (3 decimals). Written
-- by something else, it was taken as theirs while the music code stood
-- aside, put back at every login and faded in to at every camera's music
-- (Effects.lua, ns.musicKeep). On a stand-in CVar store with the game's
-- SetCVar hooks: the one-time repair at login (a real 0 left alone), a
-- near-0 or Cinematic's own write never kept as yours, your real changes
-- still kept, and camera music fading in to your volume, not the near-0
-- one, with an outside near-0 write mid-fade put right.
-- Says PASS or FAIL per check.

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end

local NEAR_ZERO = "1.85625e-05" -- (the player's, as GetCVar gave it)
local cvars = { Sound_MusicVolume = "0.55", Sound_EnableMusic = "0" }
local clock = 100
local outside = false -- a write from outside Cinematic (the game, another addon)
local savedDB

-- The game's CVars: SetCVar goes through C_CVar.SetCVar, which the addon
-- hooks (hooksecurefunc), and debugstack says who called.
local function Install()
	-- luacheck: push ignore 111 112 113 121 122
	C_CVar = {
		SetCVar = function(name, value) cvars[name] = tostring(value) end,
		GetCVar = function(name) return cvars[name] end,
		GetCVarDefault = function(name) return name == "Sound_MusicVolume" and "0.4" or "0" end,
	}
	SetCVar = function(name, value) return C_CVar.SetCVar(name, value) end
	GetCVar = function(name) return cvars[name] or "0" end
	GetCVarDefault = C_CVar.GetCVarDefault
	GetTime = function() return clock end
	hooksecurefunc = function(a, b, c)
		local tbl, name, fn = a, b, c
		if type(a) == "string" then tbl, name, fn = _G, a, b end
		local orig = tbl[name]
		tbl[name] = function(...)
			local r = { orig(...) }
			fn(...)
			return unpack(r)
		end
	end
	debugstack = function()
		return outside and "[C]: in function 'SetCVar'\n[C]: ?"
			or "Interface/AddOns/CinematicDev/Effects.lua:1: in function 'SetMusicVolume'"
	end
	CinematicDB = savedDB
	-- luacheck: pop
end

local function Login()
	local ns = dofile("Tools/offline/load.lua")("forever", "CinematicDev.toc", Install)
	savedDB = ns.db
	return ns
end

local function OutsideSet(name, value)
	outside = true
	SetCVar(name, value)
	outside = false
end

local function Volume() return tonumber(cvars.Sound_MusicVolume) end
local function Near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.0005 end

local function Logged(text)
	for _, line in ipairs(savedDB.log or {}) do
		if line:find(text, 1, true) then return true end
	end
	return false
end

-- 1: a fresh install (no profile yet: the Audio page off): nothing touched.
Login()
Check("1 fresh install: volume left alone", Near(Volume(), 0.55), cvars.Sound_MusicVolume)
Check("1 Audio page off: the repair waits", savedDB.musicVolumeNearZeroV1 == nil)
-- (A profile picked, with CineMode music: the Atmosphere hub and Audio page on.)
savedDB.profileChosen, savedDB.visualEffects, savedDB.musicInCinematic = true, true, true
local ns = Login()
Check("1 Audio page on", ns.PageSetting("musicInCinematic") == true)
Check("1 normal volume left alone", Near(Volume(), 0.55), cvars.Sound_MusicVolume)
Check("1 the repair is used up", savedDB.musicVolumeNearZeroV1 == true)

-- 2: the player's saved state: both stuck near 0, the repair not run yet.
savedDB.musicVolume, savedDB.musicVolumeNearZeroV1 = tonumber(NEAR_ZERO), nil
cvars.Sound_MusicVolume = NEAR_ZERO
Login()
Check("2 near-0 volume repaired at login", Near(Volume(), 0.4), cvars.Sound_MusicVolume)
Check("2 remembered volume repaired", Near(savedDB.musicVolume, 0.4), tostring(savedDB.musicVolume))
Check("2 repair logged", Logged("no slider's value): put back to"))

-- 3: a real 0 the player chose is never "repaired".
savedDB.musicVolume, savedDB.musicVolumeNearZeroV1 = 0, nil
cvars.Sound_MusicVolume = "0"
ns = Login()
Check("3 a real 0 stays 0", Volume() == 0, cvars.Sound_MusicVolume)
Check("3 remembered 0 stays", savedDB.musicVolume == 0, tostring(savedDB.musicVolume))

-- 4: music left alone (no camera, not CineMode): what's kept as yours.
local Tick = function(cinematic)
	clock = clock + 0.2
	ns.musicPace.run(cinematic, 0.2)
end
OutsideSet("Sound_MusicVolume", "0.55")
Tick(false)
Check("4 your change to 55% kept", Near(savedDB.musicVolume, 0.55), tostring(savedDB.musicVolume))
OutsideSet("Sound_MusicVolume", NEAR_ZERO)
Tick(false)
Check("4 an outside near-0 write not kept", Near(savedDB.musicVolume, 0.55), tostring(savedDB.musicVolume))
Check("4 the outside near-0 write logged with who", Logged("from outside Cinematic"))
SetCVar("Sound_MusicVolume", "0.012") -- (Cinematic's own, a demo's fade step left over, say)
Tick(false)
Check("4 Cinematic's own write not kept", Near(savedDB.musicVolume, 0.55), tostring(savedDB.musicVolume))
OutsideSet("Sound_MusicVolume", "0.3")
Tick(false)
Check("4 your change to 30% kept", Near(savedDB.musicVolume, 0.3), tostring(savedDB.musicVolume))
OutsideSet("Sound_MusicVolume", "0")
Tick(false)
Check("4 your change to 0 kept", savedDB.musicVolume == 0, tostring(savedDB.musicVolume))
OutsideSet("Sound_MusicVolume", "0.55")
Tick(false)

-- 5: a camera's music starting with the game's volume near 0 (music off).
OutsideSet("Sound_MusicVolume", NEAR_ZERO)
cvars.Sound_EnableMusic = "0"
ns.CameraMode = function() return "flight" end
ns.TriggerSetting = function() return true end
ns.db.musicFatigue = 0
for _ = 1, 3 do Tick(true) end
Check("5 camera music started", ns.music.managing == true, tostring(ns.music.managing))
Check("5 fades in to your volume, not the near-0 one", Near(ns.music.volume, 0.55), tostring(ns.music.volume))
Check("5 yours is the copy put back afterwards", Near(tonumber(ns.db.savedCVars.Sound_MusicVolume), 0.55),
	tostring(ns.db.savedCVars.Sound_MusicVolume))
local midFade = Volume()
Check("5 fading in", midFade and midFade > 0 and midFade < 0.55, tostring(midFade))
-- (Something writes near 0 mid-fade, as at 12:08:56 in the player's log.)
OutsideSet("Sound_MusicVolume", NEAR_ZERO)
Tick(true)
Check("5 near-0 mid-fade not taken as yours", Near(ns.music.volume, 0.55) and Near(savedDB.musicVolume, 0.55),
	("music %s, remembered %s"):format(tostring(ns.music.volume), tostring(savedDB.musicVolume)))
Check("5 the fade carries on over it", Volume() > 0.001, cvars.Sound_MusicVolume)
for _ = 1, 30 do Tick(true) end
Check("5 faded right in to 55%", Near(Volume(), 0.55), cvars.Sound_MusicVolume)
-- (Your real change mid-music still wins.)
OutsideSet("Sound_MusicVolume", "0.35")
Tick(true)
Check("5 your change during music kept", Near(ns.music.volume, 0.35) and Near(savedDB.musicVolume, 0.35),
	("music %s, remembered %s"):format(tostring(ns.music.volume), tostring(savedDB.musicVolume)))
ns.StopMusicNow()
Check("5 music ended: your volume back", Near(Volume(), 0.35), cvars.Sound_MusicVolume)

print(fails == 0 and "all passed" or (fails .. " FAILED"))
