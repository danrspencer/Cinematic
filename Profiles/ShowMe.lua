-- Cinematic: Show me, the welcome window's Customize choices tried for a few
-- seconds (and the Profiles page's, the same panel: Welcome.lua). A choice
-- with something to see has a demo: the letterbox and tint, a camera, a
-- Vision's test. One runs at a time; its button says Stop while it does.
--
-- ns.ShowMeFor(slot, choice): the demo key for a choice, or nil.
-- ns.ShowMe(key, hideFrame, force): start it (again: stop). A camera demo
--   fades hideFrame to FADED_ALPHA while the camera moves, and lets clicks
--   and camera drags through it to the world; as it was after. force: a
--   Vision's test with its switch off (the levels page's See it first row).
-- ns.ShowMeRunning(key), ns.ShowMeBlocked(key) (why it can't run now, or
-- nil), ns.StopShowMe(), ns.ShowMeListen(fn) (fn runs when one starts or
-- stops), ns.ShowMeInProfile(key, profile) (whether a profile has that look),
-- ns.ShowMeWhen(key, profile) (when it shows there: the row's tags).
--
-- The effects demos set ns.effectsDemo, which Core.lua's effects step reads
-- in place of the effects' own Show in rows (Effects.lua's letterbox shows
-- for it with its setting off, too). The camera demos are a slow orbit of
-- their own (below), not one of Cinematic's cameras: those need their own
-- moment (standing still a while, a campfire), and Cinematic switched on.
local _, ns = ...
local L = ns.L

local ALL_EFFECTS = { letterbox = true, tint = true, vignette = true, weather = true }

-- Fading UI: the UI fades out as CineMode fades it, holds, and comes back.
-- With a level picked, its own CineMode's fade: the frames pass told it's
-- CineMode (ns.fadeDemo, Core.lua), so each frame goes as that level's Show
-- in rows and fade times have it (not mouseover: the mouse is on the window,
-- over the bars, Frames.lua). Before one's picked
-- nothing's looked after (Profiles.lua's OFF_UNTIL_PICKED), and on a level
-- that fades nothing (Blank Slate) there's nothing to see: then the whole UI
-- fades, UIParent's alpha, the welcome window kept out of it. Not in a fight
-- (and stopped as one starts, before the lock: UIParent's alpha put back).
local FADE_HOLD = 5   -- seconds from the start until the UI comes back
local WHOLE_FADE = 0.8 -- seconds the whole UI takes to fade, each way
local fadeFrame = CreateFrame("Frame")
local fade -- { startAt, whole, window, ignored, alpha, back }

local function StopFade()
	local was = fade
	if not was then return end
	fade = nil
	ns.SetOnUpdate(fadeFrame, nil)
	fadeFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
	if ns.fadeDemo then
		ns.fadeDemo = nil
		ns.framesWake = "fade demo" -- (the frames' pass at once: Core.lua)
	end
	if was.whole then
		UIParent:SetAlpha(was.alpha)
		if was.window then was.window:SetIgnoreParentAlpha(was.ignored) end
		for frame, ignored in pairs(was.kept or {}) do frame:SetIgnoreParentAlpha(ignored) end
	end
end

local function FadeStep()
	local t = GetTime() - fade.startAt
	if not fade.whole then
		if t >= fade.hold then
			-- (back as CineMode would bring it: the demo goes on a moment, the window faded)
			ns.fadeDemo = nil
			ns.framesWake = "fade demo"
			ns.SetOnUpdate(fadeFrame, nil)
		end
		return
	end
	local hold = fade.hold
	local p = t >= hold and math.min(1, (t - hold) / WHOLE_FADE) or math.max(0, 1 - t / WHOLE_FADE)
	UIParent:SetAlpha(fade.alpha * p * p * (3 - 2 * p))
	if t >= hold + WHOLE_FADE then ns.SetOnUpdate(fadeFrame, nil) end
end

-- hold: seconds until the UI comes back (FADE_HOLD). keep: frames of ours on
-- UIParent kept out of the whole UI's fade, as the window is (Death Vision's
-- screen, which the fade took with the rest).
local function StartFade(window, hold, keep)
	StopFade()
	local whole = not ns.ProfileChosen() or not (ns.AnyFramePageOn and ns.AnyFramePageOn())
	-- (the window kept out of the whole UI's fade: a client without the call, none)
	if whole and not (window and window.SetIgnoreParentAlpha) then error("can't fade the UI here") end
	fade = { startAt = GetTime(), whole = whole, alpha = UIParent:GetAlpha(), hold = hold or FADE_HOLD }
	if whole then
		fade.window, fade.ignored = window, window:IsIgnoringParentAlpha()
		window:SetIgnoreParentAlpha(true)
		fade.kept = {}
		for _, frame in ipairs(keep or {}) do
			if frame.SetIgnoreParentAlpha then
				fade.kept[frame] = frame:IsIgnoringParentAlpha()
				frame:SetIgnoreParentAlpha(true)
			end
		end
	else
		ns.fadeDemo = true
		ns.framesWake = "fade demo"
	end
	fadeFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	ns.SetOnUpdate(fadeFrame, FadeStep)
end
fadeFrame:SetScript("OnEvent", function() ns.StopShowMe() end)

-- Mouseover: the UI faded as CineMode fades it, then one mouseover group
-- back as if you'd pointed at where it lives (a pointer drawn there), then
-- faded again. The frames pass's profile preview does the showing (Core.lua,
-- Frames.lua: ns.previewRows, just those rows up, the rest faded), so it's
-- your level's own frames and fade times. The Action bars group, else the
-- first with members. Only where your frames are looked after: a level that
-- fades nothing (Blank Slate) has nothing to bring back.
local HOVER_FADE, HOVER_SHOW, HOVER_AFTER = 2.5, 3.5, 2 -- seconds: faded, the group up, faded again
local hoverFrame = CreateFrame("Frame")
local hoverDemo -- { startAt, rows, pointer, phase }
local function HoverGroupRows()
	local groups = ns.GetHoverGroups and ns.GetHoverGroups() or {}
	local pick, first
	for _, group in ipairs(groups) do
		if not group.off and group.members and #group.members > 0 then
			first = first or group
			for _, key in ipairs(group.members) do
				if key == "mainbar" then pick = pick or group end
			end
		end
	end
	pick = pick or first
	if not pick then return nil end
	local rows = {}
	for _, key in ipairs(pick.members) do rows[key] = true end
	return rows, pick
end
-- Where to point: the main action bar's middle if it's in the group, else
-- the group's first shown frame (in UIParent's units), and its name.
-- (2026-11-20: the first shown frame could be the XP bar or the bags; no
-- pointer was seen on the bar.)
local function HoverSpot(rows)
	local best
	for _, entry in ipairs(ns.managed or {}) do
		local frame = entry.frame
		if rows[entry.row] and frame and frame.GetCenter and not (frame.IsForbidden and frame:IsForbidden())
			and ns.Flag(frame:IsVisible()) then
			local x, y = frame:GetCenter()
			if type(x) == "number" and type(y) == "number" and not (issecretvalue and issecretvalue(x)) then
				local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
				local spot = { x * scale, y * scale, entry.name or tostring(entry.row) }
				if entry.row == "mainbar" then return spot[1], spot[2], spot[3] end
				best = best or spot
			end
		end
	end
	if best then return best[1], best[2], best[3] end
end
local function StopHoverDemo()
	local was = hoverDemo
	if not was then return end
	hoverDemo = nil
	ns.SetOnUpdate(hoverFrame, nil)
	if was.pointer then was.pointer:Hide() end
	ns.previewRows = nil
	ns.framesWake = "mouseover demo"
end
local NO_ROWS = {}
local function HoverStep()
	local d = hoverDemo
	local t = GetTime() - d.startAt
	local phase = t < HOVER_FADE and 1 or t < HOVER_FADE + HOVER_SHOW and 2 or 3
	-- (kept on: the frames pass drops a preview at its time, Core.lua)
	ns.previewUntil = GetTime() + 1
	if phase ~= d.phase then
		d.phase = phase
		ns.previewRows = phase == 2 and d.rows or NO_ROWS
		ns.framesWake = "mouseover demo"
		if d.pointer then
			local x, y, name = HoverSpot(d.rows)
			d.spot = x and ("%s at %.0f, %.0f"):format(tostring(name), x, y) or "none found"
			if phase == 2 and x then
				d.pointer:ClearAllPoints()
				d.pointer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
				d.pointer:Show()
			else
				d.pointer:Hide()
			end
		end
	end
	if t >= HOVER_FADE + HOVER_SHOW + HOVER_AFTER then
		ns.previewRows = nil
		ns.framesWake = "mouseover demo"
		ns.SetOnUpdate(hoverFrame, nil)
	end
end
local hoverPointer
-- (For the shelf's test: its phase (1 faded, 2 the group up, 3 faded again) and the pointer up.)
function ns.MouseoverDemoState()
	local art = hoverPointer and hoverPointer.art
	return hoverDemo and hoverDemo.phase, hoverPointer ~= nil and hoverPointer:IsShown(),
		hoverDemo and hoverDemo.spot, art and tostring(art:GetTexture()),
		hoverPointer and hoverPointer:GetLeft() and ("%.0f, %.0f, strata %s, alpha %.2f"):format(hoverPointer:GetLeft(),
			hoverPointer:GetTop(), hoverPointer:GetFrameStrata(), hoverPointer:GetEffectiveAlpha()) or nil
end
local function StartHoverDemo()
	StopHoverDemo()
	local rows = HoverGroupRows()
	if not rows then error("no mouseover group") end
	if not hoverPointer then
		-- (A pointer of its own, not the mouse: drawn over the faded frames,
		-- out of UIParent's way.)
		hoverPointer = CreateFrame("Frame", nil, UIParent)
		hoverPointer:SetFrameStrata("TOOLTIP")
		hoverPointer:SetSize(32, 32)
		local art = hoverPointer:CreateTexture(nil, "OVERLAY")
		art:SetAllPoints()
		art:SetTexture("Interface\\Cursor\\Point")
		hoverPointer.art = art
		hoverPointer:Hide()
	end
	hoverDemo = { startAt = GetTime(), rows = rows, pointer = hoverPointer }
	ns.SetOnUpdate(hoverFrame, HoverStep)
	HoverStep()
end

-- Heal Vision: it works on the game's party and raid frames, which aren't
-- there with no group, so a party of five of its own, drawn where the game's
-- party frames go: all at full health, then Heal Vision fading them away
-- (full: nothing to heal), one taking hits and coming back as her health
-- drops, healed, and fading again. A picture of what it does, not the
-- feature itself (Visions/HealVisionFrames.lua).
local HEAL_PARTY = { { "Vedeth", "WARRIOR" }, { "Lumen", "PRIEST" }, { "Ashka", "HUNTER" }, { "Sly", "ROGUE" },
	{ "Maketh", "MAGE" } }
local HEAL_HURT = 2 -- the one who takes the hits
-- (seconds: faded from, hits from, hits to, healed from, healed to, end)
local HEAL_FADE, HEAL_HIT, HEAL_LOW, HEAL_UP, HEAL_FULL, HEAL_END = 1.5, 3.2, 4.4, 6.6, 7.8, 10
local HEAL_GONE = 0.06 -- a faded frame's alpha (Heal Vision's hidden)
local healFrame
local healDemo -- { startAt, tiles }
local function HealTiles()
	if healFrame then return healFrame.tiles end
	healFrame = CreateFrame("Frame", nil, UIParent)
	healFrame:SetSize(120, #HEAL_PARTY * 44)
	healFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -220)
	healFrame:SetFrameStrata("MEDIUM")
	healFrame.tiles = {}
	for i, member in ipairs(HEAL_PARTY) do
		local tile = CreateFrame("Frame", nil, healFrame)
		tile:SetSize(120, 40)
		tile:SetPoint("TOPLEFT", 0, -(i - 1) * 44)
		local ground = tile:CreateTexture(nil, "BACKGROUND")
		ground:SetAllPoints()
		ground:SetColorTexture(0, 0, 0, 0.8)
		tile.health = CreateFrame("StatusBar", nil, tile)
		tile.health:SetPoint("TOPLEFT", 1, -1)
		tile.health:SetPoint("BOTTOMRIGHT", -1, 1)
		tile.health:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
		tile.health:SetMinMaxValues(0, 1)
		local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member[2]]
		tile.health:SetStatusBarColor(color and color.r or 0, color and color.g or 0.8, color and color.b or 0)
		tile.name = tile.health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tile.name:SetPoint("TOPLEFT", 5, -4)
		tile.name:SetText(L[member[1]])
		healFrame.tiles[i] = tile
	end
	healFrame:Hide()
	return healFrame.tiles
end
local function Ease(from, to, t0, t1, t)
	local p = math.max(0, math.min(1, (t - t0) / (t1 - t0)))
	p = p * p * (3 - 2 * p)
	return from + (to - from) * p
end
local healStepFrame = CreateFrame("Frame")
local function HealStep(_, elapsed)
	local d = healDemo
	local t = GetTime() - d.startAt
	for i, tile in ipairs(d.tiles) do
		local health = 1
		if i == HEAL_HURT then
			-- (three hits down to under half, then healed back up)
			health = t < HEAL_UP and Ease(1, 0.42, HEAL_HIT, HEAL_LOW, t) or Ease(0.42, 1, HEAL_UP, HEAL_FULL, t)
			health = math.floor(health * 20 + 0.5) / 20
		end
		tile.health:SetValue(health)
		-- (Heal Vision on from HEAL_FADE: below full shows, full fades)
		local want = (t < HEAL_FADE or health < 0.99) and 1 or HEAL_GONE
		local alpha = tile:GetAlpha()
		local speed = math.min(1, (elapsed or 0) * 3)
		tile:SetAlpha(alpha + (want - alpha) * speed)
	end
end
local function StopHealDemo()
	if not healDemo then return end
	healDemo = nil
	ns.SetOnUpdate(healStepFrame, nil)
	if healFrame then healFrame:Hide() end
end
local function StartHealDemo()
	StopHealDemo()
	local tiles = HealTiles()
	for _, tile in ipairs(tiles) do
		tile:SetAlpha(1)
		tile.health:SetValue(1)
	end
	healFrame:Show()
	healDemo = { startAt = GetTime(), tiles = tiles }
	ns.SetOnUpdate(healStepFrame, HealStep)
end
-- (For the shelf's test: each member's alpha and health now.)
function ns.HealDemoState()
	if not healDemo then return nil end
	local out = {}
	for i, tile in ipairs(healDemo.tiles) do out[i] = { tile:GetAlpha(), tile.health:GetValue() } end
	return out, HEAL_HURT
end

-- Audio: CineMode's music (the Audio page, Effects.lua's ns.UpdateMusic), as
-- a camera starts it: the game's music switched on at no volume, faded up to
-- your own, held, faded out, and your settings back (saved as Cinematic saves
-- them, so a /reload mid-demo puts them back too). Your own music already on
-- is left alone, as CineMode leaves it. (Before, this played the Vitals
-- heartbeat, not the Audio page's at all: the user's ask, 2026-11-20.)
local MUSIC_HOLD = 6
local musicFrame = CreateFrame("Frame")
local musicDemo -- { startAt, fade, volume, ours }
local function StopMusicDemo()
	local was = musicDemo
	if not was then return end
	musicDemo = nil
	ns.SetOnUpdate(musicFrame, nil)
	if was.ours then
		ns.RestoreCVar("Sound_EnableMusic")
		ns.RestoreCVar("Sound_MusicVolume")
	end
end
local function MusicStep()
	local d = musicDemo
	local t = GetTime() - d.startAt
	local up = math.min(1, t / d.fade)
	local down = math.min(1, math.max(0, (t - d.fade - MUSIC_HOLD) / d.fade))
	SetCVar("Sound_MusicVolume", ("%.3f"):format(d.volume * up * (1 - down)))
	if down >= 1 then ns.SetOnUpdate(musicFrame, nil) end
end
local function StartMusicDemo()
	StopMusicDemo()
	if ns.music and ns.music.managing then error("CineMode's music is playing already") end
	local volume = tonumber(GetCVar("Sound_MusicVolume")) or 1
	local on = GetCVar("Sound_EnableMusic") == "1"
	musicDemo = { startAt = GetTime(), fade = math.max(0.5, ns.db.musicFadeTime or 3), volume = volume, ours = not on }
	if on then return end
	if volume < 0.05 then -- (near silent too: 0.0000186 seen, 2026-11-20)
		ns.Print(L["your game music volume is 0, so cinematic music can't be heard. " ..
			"Turn Music up in the game's Sound settings."])
	end
	ns.SaveCVar("Sound_EnableMusic")
	ns.SaveCVar("Sound_MusicVolume")
	SetCVar("Sound_MusicVolume", "0")
	SetCVar("Sound_EnableMusic", 1)
	ns.SetOnUpdate(musicFrame, MusicStep)
end
-- (For the shelf's test: playing, your own music or ours, and the volume now.)
function ns.MusicDemoState()
	return musicDemo ~= nil, musicDemo and not musicDemo.ours, GetCVar("Sound_EnableMusic"), GetCVar("Sound_MusicVolume")
end

-- Where the Roll window goes in its demo (RollWindow.lua's Place: its top
-- centre, in its own units): left of the welcome window, by its top, kept on
-- the screen.
local ROLL_GAP = 12
local TINT_STOP = 2 -- seconds on each time of day in the Tint demo (the 4 with a color)
local function RollBeside(roll, window)
	if not (window:IsShown() and roll) then return nil end
	local left, top = window:GetLeft(), window:GetTop()
	local width = roll:GetWidth()
	if type(left) ~= "number" or type(top) ~= "number" or type(width) ~= "number" then return nil end
	local mine, its = window:GetEffectiveScale(), roll:GetEffectiveScale()
	local x = left * mine / its - ROLL_GAP - width / 2
	return math.max(width / 2 + 8, x), top * mine / its
end

-- seconds: how long it runs; effects: which effects show; camera: the
-- orbit runs (stopped by your input too); start, stop, running: a
-- Vision's own test; once: a test that shows and is done (no Stop);
-- setting: the Vision's switch, which has to be on.
local DEMOS = {
	-- (start: given the window the demo fades, as the camera demos fade it)
	fadeUI = { seconds = 7, fade = true, start = StartFade, stop = StopFade },
	bars = { seconds = 6, effects = { letterbox = true } },
	letterbox = { seconds = 6, effects = ALL_EFFECTS },
	-- (The day's colors in turn, quietly: the tint as it is now, at night,
	-- only darkened the scene, no color seen, 2026-11-20. The user's pick.)
	tint = { seconds = 4 * TINT_STOP + 1, effects = { tint = true, vignette = true, weather = true },
		start = function() if ns.DaySweep then ns.DaySweep(TINT_STOP, nil, true) end end,
		stop = function() if ns.DaySweep then ns.DaySweep() end end },
	cameraLook = { seconds = 5, camera = true, effects = ALL_EFFECTS },
	camera = { seconds = 5, camera = true },
	-- (switches: its feature's switches, on while a forced demo plays, below)
	vitals = { seconds = 5, setting = "lowHealth", switches = { "lowHealth" },
		start = function() ns.FlashVitals(3) end,
		stop = function() if ns.StopVitalsFlash then ns.StopVitalsFlash() end end },
	tele = { seconds = 30, setting = "teleportVision",
		-- (3 seconds into its pretend cast: the portal's already opening; no
		-- timer in the middle, the settings page's)
		start = function() ns.TestTeleportVision(3, true) end,
		running = function() return ns.TeleportVisionTesting() end,
		-- (its test again: it stops)
		stop = function() if ns.TeleportVisionTesting() then ns.TestTeleportVision() end end },
	-- (Emote and Roll: up until they go as they would, or Stop)
	emote = { seconds = 60, setting = "emoteVision", start = function() ns.TestEmoteVision() end,
		running = function() return ns.EmoteCardShown() end,
		stop = function() ns.HideEmoteCard() end },
	-- (Its window opened behind the welcome window, where the game's roll
	-- frames go: beside it on the left meanwhile, the user's pick 2026-11-20.)
	roll = { seconds = 60, setting = "rollWindow", switches = { "rollWindow" },
		start = function(window)
			ns.rollDemoSpot = window and function(roll) return RollBeside(roll, window) end or nil
			ns.TestRollWindow(true)
		end,
		running = function() return ns.RollVisionActive() end,
		stop = function()
			ns.rollDemoSpot = nil
			ns.CloseRollWindow()
		end },
	damage = { seconds = 30, setting = "damageVision", start = function() ns.TestDamageVision(true) end,
		running = function() return ns.DamageVisionTesting() end,
		stop = function() ns.StopDamageVisionTest() end },
	-- (The Shoulder Cam: ShoulderCam.lua's test, in and out by itself, your
	-- settings untouched; starting it is the one-time question's yes. fade:
	-- the window faded while it runs, as for a camera demo. blocked: why it
	-- can't run now.)
	shoulder = { seconds = 10, fade = true,
		start = function() if not ns.ShoulderCamDemo() then error("can't start now") end end,
		running = function() return ns.ShoulderCamDemoRunning() end,
		stop = function() ns.StopShoulderCamDemo() end,
		blocked = function() return ns.ShoulderCamDemoBlocked() end },
	-- The welcome window's See all shelf (Welcome.lua): each feature's own Test.
	-- (Weather: the Tint demo's weather alone. once: a card, a flash or a
	-- sound, shown and done.)
	weather = { seconds = 6, effects = { weather = true } },
	-- (A card held up for its seconds, not once: its switches stay on till it's gone.)
	timeTitle = { seconds = 6, switches = { "cards", "timeOfDayChange" },
		start = function() ns.TestTimeChangeTitle() end },
	cards = { once = true, start = function() ns.CardTest("zone") end },
	recap = { once = true, start = function() ns.TestDamageRecap() end },
	-- (Flashes the game's Cooldown Manager's icons: only once a level that
	-- shows it is picked, and its Cooldowns page is on.)
	cdflash = { once = true, start = function() ns.TestCooldownFlash() end,
		blocked = function()
			if not (ns.PageOn and ns.PageOn("handleCooldowns") and ns.CooldownViewersShown
				and ns.CooldownViewersShown()) then
				return L["It flashes the game's Cooldown Manager icons: pick a level that shows them."]
			end
		end },
	speech = { once = true, start = function() ns.TestSpeechBehind() end },
	-- (Nameplates: the plate code told it's CineMode (Core.lua's
	-- ns.PlatesCinematic), so the plates that don't matter fade and your
	-- target's stays, as your level has them; its switch on meanwhile.)
	plates = { seconds = 7, fade = true, switches = { "handlePlates" },
		start = function() ns.plateDemo = true end,
		stop = function() ns.plateDemo = nil end },
	-- (Combat Text: the Combat Text Style page's preview, its hits playing, CombatTextPage.lua.)
	combatText = { seconds = 9, fade = true,
		start = function() if not ns.ShowCombatTextDemo(true) then error("no preview") end end,
		stop = function() ns.ShowCombatTextDemo(false) end },
	-- (Chat Bubbles: two in your bubble look over the world, Bubbles.lua.)
	bubbles = { seconds = 7, fade = true, start = function() ns.ShowBubbleDemo(true) end,
		stop = function() ns.ShowBubbleDemo(false) end },
	-- (Heal Vision: its own party, above; the window faded.)
	heal = { seconds = HEAL_END, fade = true, start = StartHealDemo, stop = StopHealDemo,
		running = function() return healDemo ~= nil end },
	-- (Mouseover: above. Only with your frames looked after.)
	mouseover = { seconds = HOVER_FADE + HOVER_SHOW + HOVER_AFTER + 1.5, fade = true,
		start = StartHoverDemo, stop = StopHoverDemo,
		blocked = function()
			if not (ns.ProfileChosen() and ns.AnyFramePageOn and ns.AnyFramePageOn() and ns.db.mouseover) then
				return L["It brings back a faded frame: pick a level that fades your UI and has Mouseover on."]
			end
		end },
	-- (CineMode's music: in, held, out; above. Its fades and hold, and a moment.)
	audio = { seconds = 14, start = StartMusicDemo, stop = StopMusicDemo,
		running = function() return musicDemo ~= nil end },
	-- (The UI fades with it, as it does while you're dead (CineMode's death
	-- fade), the window too, the user's ask 2026-11-20; the death screen kept
	-- out of the whole UI's fade.)
	deathVision = { seconds = 15, switches = { "deathScreen" }, fade = true,
		start = function(window)
			StartFade(window, 13, { ns.DeathScreenFrame and ns.DeathScreenFrame() })
			if not ns.DeathVisionTesting() then ns.TestDeathVision() end
		end,
		running = function() return ns.DeathVisionTesting() end,
		stop = function()
			StopFade()
			if ns.DeathVisionTesting() then ns.TestDeathVision() end
		end },
	-- (No Duel Vision: it brings back duelists' nameplates in CineMode, which
	-- the welcome window keeps off; out of it every plate shows. Nothing to
	-- see here, 2026-11-20: a page link in the shelf's "Also in" line.)
}
-- The cameras' Tests (CameraTests.lua), as the Camera Settings page's Test
-- buttons run them, for CAM_TEST seconds (its 30 at most), the window faded.
-- They're Cinematic's own cameras: not before a level's picked.
local CAM_TEST = 15
local CAM_DEMOS = { afk = "AFK Cam", questCam = "Quest Cam", flight = "Flight Cam", cozy = "Cozy Cam",
	vista = "Vista Cam", fish = "Fish Cam", deathCam = "Death Cam", walk = "RP Walk Cam", run = "Auto-run Cam" }
for key, section in pairs(CAM_DEMOS) do
	DEMOS[key] = { seconds = CAM_TEST, fade = true, profile = true,
		-- (Refused: why, in the log; the quest camera's own checks with it, the
		-- one that refused on Blank Slate with the cameras on, 2026-11-20.)
		start = function()
			if not ns.CameraTestStart(section) then
				error(("refused: %s off here %s%s"):format(section,
					tostring(ns.CameraOffWhy and ns.CameraOffWhy(section == "Quest Cam" and "quest" or "") or "no"),
					section == "Quest Cam" and (", Quest scene camera %s, calm wait over %s, moving %s"):format(
						tostring(ns.TriggerHasCamera and ns.TriggerHasCamera("Quest")),
						tostring(ns.CombatWaitOver and ns.CombatWaitOver("quest", GetTime())),
						tostring(ns.playerMoving)) or ""), 0)
			end
		end,
		running = function() return ns.CameraTestLeft(section) ~= nil end,
		stop = function() if ns.CameraTestLeft(section) then ns.CameraTestStop() end end }
end
-- Each test's function, which a client without that Vision lacks.
local NEEDS = { vitals = "FlashVitals", tele = "TestTeleportVision", emote = "TestEmoteVision",
	roll = "TestRollWindow", damage = "TestDamageVision", shoulder = "ShoulderCamDemo",
	timeTitle = "TestTimeChangeTitle", cards = "CardTest", recap = "TestDamageRecap", cdflash = "TestCooldownFlash",
	speech = "TestSpeechBehind", audio = "SaveCVar", bubbles = "ShowBubbleDemo", combatText = "ShowCombatTextDemo", deathVision = "TestDeathVision" }
for key in pairs(CAM_DEMOS) do NEEDS[key] = "CameraTestStart" end
function ns.ShowMeAvailable(key)
	return DEMOS[key] ~= nil and not (NEEDS[key] and not ns[NEEDS[key]])
end

-- Which choices have one: a slot's parts, and the Visions by key.
local BY_PART = {
	vfx = { standard = "letterbox", pure = "letterbox", noletterbox = "tint", cameras = "cameraLook" },
	camera = { pure = "camera", immersive = "camera", lite = "camera" },
}

function ns.ShowMeFor(slot, choice)
	local key
	if choice.vision then
		key = DEMOS[choice.vision.key] and choice.vision.key
	elseif slot and BY_PART[slot] then
		key = BY_PART[slot][choice.part]
	end
	if key and NEEDS[key] and not ns[NEEDS[key]] then return nil end
	return key
end

local current -- { key, def, untilAt, hidden, alpha, mice }
local FADED_ALPHA = 0.3 -- the window's while a camera demo runs
-- The tour (below): its steps one after another. advancing: the tour itself
-- moving on (a demo's natural end, its next start), which doesn't end it.
local tour -- { steps, i, hideFrame, hidden, alpha, mice, timer, holdKey }
local advancing = false
local TourNext, TourEnd

-- A frame and every frame in it no longer taking the mouse (each one's
-- setting kept in mice, to put back): a faded window still takes the clicks
-- and camera drags over it, its buttons too. And the backgrounds inside it
-- (not its own) cleared while it's faded: each a layer over the window's,
-- the boxes showed darker than the window round them, uneven.
local function MouseOff(frame, mice, inside)
	if inside and frame.GetBackdropColor and frame:GetBackdrop() then
		local r, g, b, a = frame:GetBackdropColor()
		if a and a > 0 then
			mice[#mice + 1] = { frame = frame, backdrop = { r, g, b, a } }
			frame:SetBackdropColor(r, g, b, 0)
		end
	end
	if frame.IsMouseEnabled then
		local click, wheel = frame:IsMouseEnabled(), frame.IsMouseWheelEnabled and frame:IsMouseWheelEnabled()
		if click or wheel then
			mice[#mice + 1] = { frame = frame, click = click, wheel = wheel }
			if click then frame:EnableMouse(false) end
			if wheel then frame:EnableMouseWheel(false) end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do MouseOff(child, mice, true) end
end
local ticker
local listeners = {}

local function Notify()
	for _, fn in ipairs(listeners) do pcall(fn) end
end

function ns.ShowMeListen(fn)
	listeners[#listeners + 1] = fn
end

function ns.ShowMeRunning(key)
	return current ~= nil and current.key == key
end

-- (force: a Vision's test with its switch off too, the welcome window's
-- See it first row: its tests show without it)
-- (None in a fight, the shelf's plan: every demo greys together, one line
-- saying why, rather than a tooltip each. profile: Cinematic's own cameras,
-- which need a level picked.)
function ns.ShowMeBlocked(key, force)
	local def = DEMOS[key]
	if not def then return L["Nothing to show here."] end
	if InCombatLockdown() then return L["Not in a fight: try it once the fight ends."] end
	if def.blocked then
		local why = def.blocked()
		if why then return why end
	end
	if def.profile and not ns.ProfileChosen() then return L["Pick a profile first."] end
	-- (Turned off, the welcome window's Turn off: the cameras won't start, and said so in chat each click)
	if def.profile and not ns.db.enabled then return L["Cinematic is off: turn it on first"] end
	if def.setting and not force and not ns.Setting(def.setting) then
		return L["Click the row to turn it on first."]
	end
end

-- Whether a profile has a demo's look (the See it first row's In and Not in):
-- its settings, under their pages' switches. Camera: the Cameras page's
-- Enable switch (off on Blank Slate, which leaves the camera as the game has it).
local IN_PROFILE = { fadeUI = { "handleFrames" }, bars = { "letterboxPage", "letterbox" }, tint = { "tintPage" },
	camera = { "cameraModes" }, vitals = { "lowHealth" }, tele = { "teleportVision" }, shoulder = { "shoulderCam" },
	weather = { "tintPage", "weatherTint" }, timeTitle = { "cards", "timeOfDayChange" }, cards = { "cards" },
	recap = { "damageVision" }, damage = { "damageVision" }, emote = { "emoteVision" }, roll = { "rollWindow" },
	deathVision = { "deathScreen" }, duel = { "duelPlates" }, audio = { "musicInCinematic" },
	mouseover = { "handleFrames", "mouseover" }, heal = { "handleHealVision" }, plates = { "handlePlates" },
	bubbles = { "handleBubbles" }, combatText = { "combatTextStyle" } }
-- A camera's Test by its scene (CameraRows.lua's triggers): on with the Cameras
-- page's switch, the scene ticked and a camera picked (camera: the one to pick
-- for Turn on).
local CAM_SCENE = { afk = { "AFK", "afk" }, questCam = { "Quest", "quest" }, flight = { "Flight", "flight" },
	cozy = { "Campfire", "cozy" }, vista = { "Stare", "vista" }, fish = { "Fishing", "fish" },
	deathCam = { "Death", true }, walk = { "Walk", "walk" }, run = { "Run", "run" } }
for key in pairs(CAM_SCENE) do IN_PROFILE[key] = { "cameraModes" } end
-- (Their demos: Cinematic's cameras on while they play, the scene ticked with
-- a camera picked, and cameras outside CineMode (the welcome window keeps it
-- off). Blank Slate has them all off: every camera's Test ran and nothing
-- moved, 2026-11-20. Back after, as a Vision's switches.)
for key, scene in pairs(CAM_SCENE) do
	DEMOS[key].switches = { "cameraModes" }
	DEMOS[key].sets = function()
		local trigger = ns.CAMERA_TRIGGER and ns.CAMERA_TRIGGER[scene[1]]
		local values = { outsideCineCameras = true }
		if trigger then
			values[trigger.sceneOff] = false
			if ns.db[trigger.camera] == trigger.off then values[trigger.camera] = scene[2] end
		end
		return values
	end
end
local function SceneOn(base, key)
	local trigger = CAM_SCENE[key] and ns.CAMERA_TRIGGER and ns.CAMERA_TRIGGER[CAM_SCENE[key][1]]
	if not trigger then return true end
	return not base[trigger.sceneOff] and base[trigger.camera] ~= trigger.off
end
-- Turn on (the shelf's): the switches written into the profile being tried,
-- the live settings, with every switch over them (a page off holds its
-- settings off). Not the looks set by Show in rows (the letterbox, the tint),
-- the camera orbit (a profile's scenes), the Shoulder Cam (its own question)
-- or Fading UI (the HUD's every section): those have no Turn on.
local NO_TURN_ON = { bars = true, tint = true, camera = true, shoulder = true, fadeUI = true }
function ns.ShowMeCanTurnOn(key)
	return IN_PROFILE[key] ~= nil and not NO_TURN_ON[key]
end
function ns.ShowMeTurnOn(key)
	if not ns.ShowMeCanTurnOn(key) or InCombatLockdown() then return false end
	local db = ns.db
	for _, each in ipairs(IN_PROFILE[key]) do
		db[each] = true
		local page = ns.PageSwitchOf(each)
		while page do
			db[page] = true
			page = ns.PageSwitchOf(page)
		end
	end
	local trigger = CAM_SCENE[key] and ns.CAMERA_TRIGGER and ns.CAMERA_TRIGGER[CAM_SCENE[key][1]]
	if trigger then
		db[trigger.sceneOff] = false
		if db[trigger.camera] == trigger.off then db[trigger.camera] = CAM_SCENE[key][2] end
		if ns.CameraRowsChanged then ns.CameraRowsChanged() end
	end
	if ns.RefreshOutsideCine then ns.RefreshOutsideCine(true) end
	ns.letterboxDirty = true
	if ns.RefreshTint then ns.RefreshTint() end
	Notify()
	return true
end
local function On(base, key)
	local page = ns.PageSwitchOf(key)
	while page do
		if base[page] == false then return false end
		page = ns.PageSwitchOf(page)
	end
	return base[key] and true or false
end
function ns.ShowMeInProfile(key, name)
	local keys = IN_PROFILE[key]
	local base = keys and name and ns.ProfileBase and ns.ProfileBase(name)
	if not base then return nil end
	if base.visualEffects == false and (key == "bars" or key == "tint") then return false end
	if key == "tint" and base.tintPreset == "none" then return false end
	for _, each in ipairs(keys) do
		if not On(base, each) then return false end
	end
	return SceneOn(base, key)
end

-- When a profile's look shows (the See it first row's tags): ns.ShowMeWhen(key,
-- profile) gives the tag ("In CineMode", "4 scenes", "Off"...), whether the
-- profile has it, and a sentence for the description box (nil for none).
-- The letterbox and tint by their Show in rows: Always, the CineMode tick
-- alone, Out of fights alone, else Sometimes. The camera by its scenes ticked
-- on (a built-in's own rows: copies and triggers of your own aren't in a profile).
local SHOW_LISTS = { "combatShow", "calmShow", "quietShow", "camShow", "worldShow", "cityShow", "bgShow",
	"instanceShow", "groupShow", "enemyShow", "friendlyShow" }
local EFFECT_OF = { bars = "letterbox", tint = "tint" }
local function Ticked(base, list, key)
	local on = type(base[list]) == "table" and base[list][key]
	if on == nil then on = ns.LIST_DEFAULTS[list] and ns.LIST_DEFAULTS[list][key] end
	return on and true or false
end
-- The names in a list, "A, B and C" (past max: "A, B and 3 more").
local function Names(list, max)
	if #list > max then
		local shown = {}
		for i = 1, max - 1 do shown[i] = list[i] end
		return (L["%s and %d more"]):format(table.concat(shown, ", "), #list - max + 1)
	end
	if #list == 1 then return list[1] end
	return (L["%s and %s"]):format(table.concat(list, ", ", 1, #list - 1), list[#list])
end
-- A profile's scenes ticked on, by name; cine: those that bring CineMode on;
-- picks: up to three of these to name for many (the scenes' own names don't
-- all read in a sentence: "resting with a listed buff (campfire)").
local PICKS = { { "Campfire", "sit by a campfire" }, { "Flight", "take a flight" }, { "Dance", "dance" },
	{ "Fishing", "fish" }, { "Sit", "sit down" } }
local function Scenes(base)
	local all, cine, on = {}, {}, {}
	for _, trigger in ipairs(ns.CAMERA_TRIGGERS or {}) do
		if trigger.sceneOff and not base[trigger.sceneOff] and base[trigger.camera] ~= trigger.off then
			-- (its name, "Take a flight", mid-sentence: "take a flight")
			local name = ns.CameraTriggerName and ns.CameraTriggerName(trigger.key) or trigger.key
			name = tostring(name):gsub("^%u%l", string.lower)
			all[#all + 1] = name
			on[trigger.key] = true
			if trigger.cine and base[trigger.cine] then cine[#cine + 1] = name end
		end
	end
	local picks = {}
	for _, pick in ipairs(PICKS) do
		if on[pick[1]] and #picks < 3 then picks[#picks + 1] = L[pick[2]] end
	end
	return all, cine, picks
end
function ns.ShowMeWhen(key, name)
	local has = ns.ShowMeInProfile(key, name)
	if has == nil then return nil end
	if not has then return L["Off"], false, L["Not in this profile."] end
	local base = ns.ProfileBase(name)
	local effect = EFFECT_OF[key]
	if effect then
		local row = "effect:" .. effect
		local rule = type(base.frameRules) == "table" and base.frameRules[row]
		if base[effect .. "Always"] then return L["Always"], true, L["All the time."] end
		local others = type(rule) == "string" and rule:find("%S") and true or false
		local quiet = false
		for _, list in ipairs(SHOW_LISTS) do
			if Ticked(base, list, row) then
				if list == "quietShow" then quiet = true else others = true end
			end
		end
		if quiet and not others then
			return L["Out of fights"], true, L["Whenever you're out of a fight."]
		end
		if not (others or quiet) then return L["Off"], false, L["Not in this profile."] end
		return L["Sometimes"], true, L["At the moments its Show in row ticks."]
	end
	if key == "camera" then
		local scenes, _, picks = Scenes(base)
		if #scenes == 0 then return L["Off"], false, L["Not in this profile."] end
		local tag = #scenes == 1 and L["1 scene"] or (L["%d scenes"]):format(#scenes)
		if #scenes > 5 and #picks > 0 then
			return tag, true, (L["Plays at %d moments, like when you %s."]):format(#scenes, Names(picks, 3))
		end
		return tag, true, (L["Plays when you %s."]):format(Names(scenes, 5))
	end
	-- (Start in CineMode, the row's tick: as saved, which the tick changes for the level picked)
	if key == "fadeUI" then
		if ns.ProfileSettings(name).fadeUI ~= false then
			return L["Out of fights"], true, L["Whenever you're out of a fight."]
		end
		return L["With cameras"], true, L["Only while a camera brings CineMode on: Start in CineMode is off."]
	end
	if key == "vitals" then return L["Low health"], true, L["As your health drops."] end
	if key == "tele" then return L["On hearth"], true, L["As you hearth or teleport."] end
	if key == "shoulder" then
		return L["On"], true, L["Over your shoulder outdoors, off your mount and out of dungeons and raids."]
	end
	return L["On"], true, nil
end

-- The orbit: the camera turns round you, easing in and out. It claims the
-- view as Cinematic's cameras do (Core.lua's camera lock), and turns by
-- stepping your turn speed setting, held while it does and put back after,
-- as Chat Cam does (ChatCam.lua, which has the why of each step): from rest
-- the lowest setting goes in with a creep too slow to see, the move sent
-- over it a moment later (a move started at speed jumps a frame); the
-- setting's sent only once it's changed enough, and never under 1 (lower,
-- the game turns at full speed); your setting's back a moment after the
-- move stops (else its last frame can run at yours). Your own camera input
-- stops it at once.
local WHO, YAW = "showme", "cameraYawMoveSpeed"
local ORBIT_TURN = 180    -- degrees, over the demo's seconds
local ORBIT_EASE = 1      -- seconds to full speed, and from it at the end
local MIN_SETTING = 1     -- the lowest speed setting sent
local PRIME_SHARE = 0.001 -- the creep's share of the setting
local PRIME_TIME = 0.2    -- seconds the creep runs before the move
local SETTING_CHANGE = 0.02 -- setting changes smaller than this share aren't sent
local RESTORE_DELAY = 0.3 -- seconds after the move stops before your setting's back
local orbitFrame = CreateFrame("Frame")
local orbit -- { startAt, endAt, speed, moving, sent }
local restoring = 0 -- (stops whose setting isn't back yet: the lock counts them)

local function StopOrbit()
	if not orbit then return end
	orbit = nil
	ns.SetOnUpdate(orbitFrame, nil)
	ns.CallCameraFunction("MoveViewRightStop")
	restoring = restoring + 1
	C_Timer.After(RESTORE_DELAY, function()
		restoring = restoring - 1
		-- (not if another orbit's begun: it holds the setting now)
		if not orbit then ns.ReleaseSpeed(WHO, YAW) end
	end)
end

local function OrbitStep()
	local now = GetTime()
	if now >= orbit.endAt then
		StopOrbit()
		return
	end
	if not orbit.moving then
		-- (the creep's run long enough: the move over it, at full share)
		if now < orbit.startAt then return end
		if not ns.CameraCall(WHO, "MoveViewRightStart", 1) then
			StopOrbit()
			return
		end
		orbit.moving = true
	end
	local p = math.max(0, math.min(1, (now - orbit.startAt) / ORBIT_EASE, (orbit.endAt - now) / ORBIT_EASE))
	p = p * p * (3 - 2 * p)
	local setting = math.max(MIN_SETTING, orbit.speed * p)
	if math.abs(setting - orbit.sent) > orbit.sent * SETTING_CHANGE then
		ns.SetHeldSpeed(WHO, YAW, setting)
		orbit.sent = setting
	end
end

local function StartOrbit(seconds)
	if not ns.ClaimCamera(WHO) then return false end
	ns.SetHeldSpeed(WHO, YAW, MIN_SETTING)
	if not ns.CameraCall(WHO, "MoveViewRightStart", PRIME_SHARE) then
		ns.ReleaseSpeed(WHO, YAW)
		return false
	end
	local now = GetTime()
	-- (Full speed for ORBIT_TURN in all: each ease covers half its time's
	-- worth, so the two together one ease's.)
	local turning = seconds - PRIME_TIME
	orbit = { startAt = now + PRIME_TIME, endAt = now + seconds, sent = MIN_SETTING,
		speed = ORBIT_TURN / math.max(1, turning - ORBIT_EASE) }
	ns.SetOnUpdate(orbitFrame, OrbitStep)
	return true
end

if ns.RegisterCamera then
	ns.RegisterCamera(WHO, function() return orbit ~= nil or restoring > 0 end, StopOrbit)
end

-- A forced demo's switches (def.switches): a Vision's test reads its own
-- settings through its switch, so with the switch off (before a level's
-- picked every one is: Profiles.lua's OFF_UNTIL_PICKED) it drew nothing,
-- 2026-11-20 (Vitals, Roll, Death Vision, the time of day title). On while
-- it plays, with every switch over them, and back after; kept in
-- db.showMeRestore meanwhile, so a /reload mid-demo puts them back at login.
local function SwitchesOn(def)
	local db, saved = ns.db, {}
	for _, key in ipairs(def.switches) do
		local each = key
		while each do
			if db[each] ~= true and saved[each] == nil then
				saved[each] = db[each] == nil and "nil" or db[each]
				db[each] = true
			end
			each = ns.PageSwitchOf(each)
		end
	end
	-- (and other values it needs, def.sets: a camera's scene and camera)
	for key, value in pairs(def.sets and def.sets() or {}) do
		if db[key] ~= value and saved[key] == nil then
			saved[key] = db[key] == nil and "nil" or db[key]
			db[key] = value
		end
	end
	db.showMeRestore = next(saved) and saved or nil
	if ns.RefreshOutsideCine then ns.RefreshOutsideCine(true) end
	if def.sets and ns.CameraRowsChanged then ns.CameraRowsChanged() end
end
local function SwitchesBack()
	local db = ns.db
	local saved = db and db.showMeRestore
	if type(saved) ~= "table" then return end
	db.showMeRestore = nil
	for key, value in pairs(saved) do
		if value == "nil" then db[key] = nil else db[key] = value end
	end
	if ns.RefreshOutsideCine then ns.RefreshOutsideCine(true) end
	if ns.RefreshRollWindow then ns.RefreshRollWindow() end
	if ns.CameraRowsChanged then ns.CameraRowsChanged() end
end
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function() SwitchesBack() end)
-- (A profile switched mid-demo, a level picked: the demo stops first, its
-- switches back on the profile it was on. After, they'd go onto the new
-- one's settings, a Vision it has turned off. Profiles.lua loads first.)
if ns.SetProfile then
	local SetProfile = ns.SetProfile
	ns.SetProfile = function(...)
		if ns.StopShowMe then ns.StopShowMe() end
		return SetProfile(...)
	end
end

-- A frame faded and its mouse let through (MouseOff), and back.
local function Unfade(frame, alpha, mice)
	frame:SetAlpha(alpha)
	for _, each in ipairs(mice) do
		if each.click then each.frame:EnableMouse(true) end
		if each.wheel then each.frame:EnableMouseWheel(true) end
		if each.backdrop then each.frame:SetBackdropColor(unpack(each.backdrop)) end
	end
end

-- (Anything but the tour moving on also ends the tour: a Stop, the window
-- closing, a profile switched, a fight.)
function ns.StopShowMe()
	local run = current
	if run then
		current = nil
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
		if run.def.effects then
			ns.effectsDemo = nil
			ns.letterboxDirty = true
			if ns.RefreshTint then ns.RefreshTint() end
		end
		if run.def.camera then StopOrbit() end
		if run.def.stop then pcall(run.def.stop) end
		if run.switched then SwitchesBack() end
		if run.hidden then Unfade(run.hidden, run.alpha, run.mice) end
	end
	if not advancing and tour then TourEnd() end
	if run then Notify() end
end

-- A demo running for at least seconds more (the welcome window's tint
-- strength slider, dragged while the Tint demo plays).
function ns.ShowMeKeep(key, seconds)
	local run = current
	if run and run.key == key then run.untilAt = math.max(run.untilAt, GetTime() + seconds) end
end

local function Tick()
	local run = current
	if not run then return end
	if GetTime() >= run.untilAt or (run.def.camera and not orbit)
		or (run.def.running and not run.def.running()) then
		-- (Ended by itself, its time up or you moved: a tour goes on to its next.)
		advancing = true
		ns.StopShowMe()
		advancing = false
		if tour then TourNext() end
	end
end

-- seconds: how long, in place of the demo's own (the tour's Emote Vision).
-- True if it started (a once demo: shown).
function ns.ShowMe(key, hideFrame, force, seconds)
	if ns.ShowMeRunning(key) then
		ns.StopShowMe()
		return false
	end
	ns.StopShowMe()
	local def = DEMOS[key]
	if not def or ns.ShowMeBlocked(key, force) then return false end
	-- (Another camera of ours moving the view, or you: none.)
	if def.camera and not StartOrbit(seconds or def.seconds) then return false end
	-- (Not for a once demo: nothing's left running to put them back after.)
	local switched = force and def.switches and not def.once and not InCombatLockdown()
	if switched then SwitchesOn(def) end
	local started, err = true, nil
	if def.start then started, err = pcall(def.start, hideFrame) end
	if not started then
		ns.Log("showme", ("%s didn't start: %s"):format(key, tostring(err)))
		if switched then SwitchesBack() end
		return false
	end
	if def.once then return true end
	if def.effects then
		ns.effectsDemo = def.effects
		ns.letterboxDirty = true
		if ns.RefreshTint then ns.RefreshTint() end
	end
	current = { key = key, def = def, untilAt = GetTime() + (seconds or def.seconds), switched = switched }
	if (def.camera or def.fade) and hideFrame then
		-- (Faded, the world showing through, and the mouse passing through
		-- it to the world: Escape still closes it.)
		current.hidden, current.alpha, current.mice = hideFrame, hideFrame:GetAlpha(), {}
		hideFrame:SetAlpha(FADED_ALPHA)
		MouseOff(hideFrame, current.mice)
		GameTooltip:Hide()
	end
	ticker = C_Timer.NewTicker(0.2, Tick)
	Notify()
	return true
end

-- The tour (the welcome window's Watch the tour, and the shelf's Play all):
-- steps, each { key, seconds (nil: its own), skip (true: left out) }, played
-- one after another, the window faded the whole way (the plan's open
-- question, leaned yes). Each goes on as the last ends by itself, its time
-- up or you moved (the AFK Cam stops on input): a step that can't play is
-- passed over. A once demo (a card) is held TOUR_ONCE seconds. Stop, the
-- window closing, a profile switched or a fight ends it.
local TOUR_ONCE = 6
function TourEnd()
	local was = tour
	if not was then return end
	tour = nil
	if was.timer then was.timer:Cancel() end
	if was.hidden then Unfade(was.hidden, was.alpha, was.mice) end
	Notify()
end
function TourNext()
	local t = tour
	if not t then return end
	t.holdKey = nil
	t.i = t.i + 1
	local step = t.steps[t.i]
	if not step then return TourEnd() end
	advancing = true
	local started = ns.ShowMe(step.key, t.hideFrame, true, step.seconds)
	advancing = false
	if tour ~= t or current then return end
	if started then
		-- (shown and done: held a moment, then on)
		t.holdKey = step.key
		t.timer = C_Timer.NewTimer(TOUR_ONCE, function()
			t.timer = nil
			if tour == t then TourNext() end
		end)
		Notify()
	else
		ns.Log("showme", "tour: passed over " .. step.key)
		return TourNext()
	end
end
-- Starts it (again: stops). False with nothing it can play now.
function ns.ShowMeTour(steps, hideFrame)
	if tour then
		ns.StopShowMe()
		return false
	end
	ns.StopShowMe()
	if InCombatLockdown() then return false end
	local list = {}
	for _, step in ipairs(steps) do
		if not step.skip and ns.ShowMeAvailable(step.key) and not ns.ShowMeBlocked(step.key, true) then
			list[#list + 1] = step
		end
	end
	if #list == 0 then return false end
	tour = { steps = list, i = 0, hideFrame = hideFrame }
	if hideFrame then
		tour.hidden, tour.alpha, tour.mice = hideFrame, hideFrame:GetAlpha(), {}
		hideFrame:SetAlpha(FADED_ALPHA)
		MouseOff(hideFrame, tour.mice)
		GameTooltip:Hide()
	end
	TourNext()
	return true
end
function ns.ShowMeTouring() return tour ~= nil end
-- What's playing now, for the notice: its key (a tour's held card too), and
-- during a tour its place: n of N.
function ns.ShowMeNow()
	local key = current and current.key or (tour and tour.holdKey)
	if not key then return nil end
	return key, tour and tour.i, tour and #tour.steps
end
-- (A fight begins: the tour ends, before the lock.)
local tourFrame = CreateFrame("Frame")
tourFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
tourFrame:SetScript("OnEvent", function() if tour then ns.StopShowMe() end end)
