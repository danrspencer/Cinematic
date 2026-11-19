-- /cine debug ufdrift [always]: records the player and target frames while
-- you play, for "unit frames get messed up after some combat, /reload fixes
-- it" (2026-11-18), a bug that's hard to make happen on purpose.
--   /cine debug ufdrift          one run (20 minutes at most); the same
--                                command again stops it;
--   /cine debug ufdrift always   on from now on, at every login and /reload
--                                too, so it's already recording when it
--                                happens; the command again stops it (and
--                                turns always off, so the log stays).
-- It records:
--   every region and child frame of PlayerFrame / TargetFrame (and the frames
--   we hang on them): where it is on screen, its size, shown, alpha, parent
--   and anchors; in full at the start, then only what changed (a bar's fill
--   left out, a text by its top and height: both move with the numbers);
--   when: the start, a fight starting, every 2 s in a fight, a fight ending
--   (and 0.6 s / 2 s after, past our settle pass), each new target;
--   at 2 s after a fight, what's not where it was when the fight began (the
--   target frame only if it's the same target): a DRIFT line and a
--   screenshot when anything is;
--   each RefreshUnitStyle call (in a fight or not), the game's own art and
--   classification updates, blocked actions and our "style" log lines;
--   the target's kind (level, classification, power) and the page's settings.
-- Into CinematicDB.ufDriftLog (the newest 30000 lines). Changes no settings.
-- Dev copy only.
local _, ns = ...

local LIMIT = 20 * 60 -- seconds: a single run stops by itself after this
local KEEP = 30000 -- log lines
local FRAMES = { "PlayerFrame", "TargetFrame" }

local run -- { at, last = { [frameName] = { [key] = line } }, pre, preTarget, fights, ticker, always }

local function Say(text)
	local log = CinematicDB and CinematicDB.ufDriftLog
	if not log then return end
	-- (An always-on log keeps the newest lines: the old ones go in a block.)
	if #log >= KEEP then
		local kept = {}
		for i = #log - KEEP + 5001, #log do kept[#kept + 1] = log[i] end
		CinematicDB.ufDriftLog = kept
		log = kept
	end
	log[#log + 1] = ("%s %.1f %s"):format(date("%H:%M:%S"), run and GetTime() - run.at or 0, text)
end
local function Secret(value) return issecretvalue and issecretvalue(value) end
-- (Forever hides some reads in fights: shown, alpha, a layer.)
local function T(value)
	if Secret(value) then return "secret" end
	return tostring(value)
end
local function N(value)
	if value == nil then return "nil" end
	if Secret(value) then return "secret" end
	if type(value) == "number" then return ("%.1f"):format(value) end
	return tostring(value)
end
local function NameOf(object)
	if not object then return "nil" end
	local ok, name = pcall(function() return object.GetDebugName and object:GetDebugName() or object:GetName() end)
	if ok and name and not Secret(name) then
		-- (Our own frames have no name: the address is long but stays the same all run.)
		return (tostring(name):gsub("^PlayerFrame%.", "P."):gsub("^TargetFrame%.", "T."))
	end
	return tostring(object)
end
local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Say(("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end

-- One line per region: rect on screen, shown, alpha, parent, anchors (a
-- text's top and height instead of its rect: its width is its words').
local function Line(region)
	local words = {}
	local ok = pcall(function()
		if region.GetFont then
			words[#words + 1] = ("top %s %sh"):format(N(region:GetTop()), N(region:GetHeight()))
		else
			local left, bottom, width, height = region:GetRect()
			words[#words + 1] = ("at %s,%s %sx%s"):format(N(left), N(bottom), N(width), N(height))
		end
		words[#words + 1] = "shown " .. T(region:IsShown()) .. "/" .. T(region:IsVisible())
		words[#words + 1] = "alpha " .. N(region:GetAlpha())
		if region.GetScale then words[#words + 1] = "scale " .. N(region:GetScale()) end
		words[#words + 1] = "parent " .. NameOf(region:GetParent())
		if region.GetFrameLevel then words[#words + 1] = "level " .. N(region:GetFrameLevel()) end
		if region.GetDrawLayer then words[#words + 1] = "layer " .. T(region:GetDrawLayer()) end
		if region.GetFont then words[#words + 1] = "font " .. N((select(2, region:GetFont()))) end
		local count = region:GetNumPoints()
		for i = 1, (not Secret(count) and count or 0) do
			local point, to, toPoint, x, y = region:GetPoint(i)
			words[#words + 1] = ("%s>%s.%s %s,%s"):format(T(point), NameOf(to), T(toPoint), N(x), N(y))
		end
	end)
	if not ok then words[#words + 1] = "(unreadable)" end
	-- (A word built from a secret is secret too: concat refuses it.)
	for i, word in ipairs(words) do if Secret(word) then words[i] = "secret" end end
	return table.concat(words, "; ")
end

-- Every region under a frame, down through its children (a bar's fill left
-- out: it grows and shrinks with the health).
local function Walk(frame, out, depth)
	if depth > 8 then return end
	out[NameOf(frame)] = Line(frame)
	local fill
	if frame.GetObjectType and frame:GetObjectType() == "StatusBar" then
		local ok, texture = pcall(frame.GetStatusBarTexture, frame)
		fill = ok and texture
	end
	local ok, regions = pcall(function() return { frame:GetRegions() } end)
	for _, region in ipairs(ok and regions or {}) do
		if region ~= fill then out[NameOf(region)] = Line(region) end
	end
	local okKids, kids = pcall(function() return { frame:GetChildren() } end)
	for _, kid in ipairs(okKids and kids or {}) do
		if not (kid.IsForbidden and kid:IsForbidden()) then Walk(kid, out, depth + 1) end
	end
end

local function TargetId()
	local ok, guid = pcall(UnitGUID, "target")
	if ok and guid and not Secret(guid) then return guid end
	return nil
end

local function Kind()
	local db = ns.GetDB()
	local target = "none"
	if UnitExists("target") then
		local okName, name = pcall(UnitName, "target")
		local powerType = UnitPowerType and select(2, UnitPowerType("target"))
		target = ("%s lvl %s %s power %s %s"):format(okName and not Secret(name) and tostring(name) or "?",
			N(UnitLevel("target")), T(UnitClassification("target")), T(powerType),
			UnitIsPlayer("target") and "player" or "npc")
	end
	return ("combat %s, target %s; theme %s layout %s, ufStyle %s shape %s nameBack %s texture %s"):format(
		tostring(InCombatLockdown()), target, tostring(db.styleTheme), tostring(ns.ThemeLayout and ns.ThemeLayout()),
		tostring(db.ufStyle), tostring(db.ufShape), tostring(db.ufNameBack), tostring(db.ufTexture))
end

-- The differences between two snapshots of one frame, as log lines.
local function Compare(id, before, now, mark)
	local keys = {}
	for key in pairs(now) do keys[#keys + 1] = key end
	for key in pairs(before) do if now[key] == nil then keys[#keys + 1] = key end end
	table.sort(keys)
	local changed = 0
	for _, key in ipairs(keys) do
		if before[key] ~= now[key] then
			changed = changed + 1
			Say(("  %s %s %s: %s  (was %s)"):format(mark, id, key, tostring(now[key]), tostring(before[key])))
		end
	end
	return changed
end

local function SnapNow(why, full)
	Say("== " .. why .. ": " .. Kind())
	local changed = 0
	for _, id in ipairs(FRAMES) do
		local frame = _G[id]
		if frame then
			local now = {}
			Walk(frame, now, 0)
			local before = run.last[id]
			if full or not before then
				local keys = {}
				for key in pairs(now) do keys[#keys + 1] = key end
				table.sort(keys)
				for _, key in ipairs(keys) do Say(("  %s %s: %s"):format(id, key, now[key])) end
			else
				changed = changed + Compare(id, before, now, "~")
			end
			run.last[id] = now
		end
	end
	if not full then Say(("  (%d changed)"):format(changed)) end
end

-- (A read that fails costs that one snapshot, not the run.)
local function Snap(why, full)
	if not run then return end
	local ok, err = pcall(SnapNow, why, full)
	if not ok then Say("snapshot " .. why .. " failed: " .. tostring(err)) end
end

-- 2 s after a fight: what isn't where it was when the fight began.
local function Drift(fight)
	if not (run and run.pre) then return end
	Snap("fight " .. fight .. " +2s")
	local total = 0
	local ok, err = pcall(function()
		for _, id in ipairs(FRAMES) do
			local before, now = run.pre[id], run.last[id]
			local same = id ~= "TargetFrame" or (run.preTarget and run.preTarget == TargetId())
			if before and now and same then total = total + Compare(id, before, now, "DRIFT") end
		end
	end)
	if not ok then Say("drift check failed: " .. tostring(err)) end
	Say(("DRIFT fight %d: %d not as before the fight"):format(fight, total))
	if total > 0 then Shot("drift fight " .. fight) end
end

local function Later(seconds, why)
	C_Timer.After(seconds, function()
		if run then Snap(why) end
	end)
end

-- Hooks (once; quiet while no run).
local hooked = false
local function Hook()
	if hooked then return end
	hooked = true
	local refresh = ns.RefreshUnitStyle
	if refresh then
		ns.RefreshUnitStyle = function(again, ...)
			if run then Say(("RefreshUnitStyle(%s) combat %s"):format(tostring(again), tostring(InCombatLockdown()))) end
			return refresh(again, ...)
		end
	end
	local log = ns.Log
	if log then
		ns.Log = function(category, text, ...)
			if run and category == "style" then Say("log: " .. tostring(text)) end
			return log(category, text, ...)
		end
	end
	for _, name in ipairs({ "PlayerFrame_UpdateArt", "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt",
		"TargetFrame_CheckClassification", "TargetFrame_Update", "TargetFrame_CheckLevel", "UnitFrame_Update",
		"UnitFrameHealthBar_Update", "UnitFrameManaBar_UpdateType" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function(frame)
				if run then Say(("game %s(%s) combat %s"):format(name, NameOf(frame), tostring(InCombatLockdown()))) end
			end)
		end
	end
	for _, id in ipairs(FRAMES) do
		local frame = _G[id]
		for _, method in ipairs({ "Update", "CheckClassification", "CheckLevel", "UpdateArt", "UpdateLevel" }) do
			if frame and type(frame[method]) == "function" then
				hooksecurefunc(frame, method, function()
					if run then Say(("game %s:%s() combat %s"):format(id, method, tostring(InCombatLockdown()))) end
				end)
			end
		end
	end
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event, a, b)
	if not run then return end
	if event == "PLAYER_REGEN_DISABLED" then
		run.fights = run.fights + 1
		Snap("fight " .. run.fights .. " starts")
		run.pre = { PlayerFrame = run.last.PlayerFrame, TargetFrame = run.last.TargetFrame }
		run.preTarget = TargetId()
		run.ticker = C_Timer.NewTicker(2, function() if run and InCombatLockdown() then Snap("in fight " .. run.fights) end end)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if run.ticker then run.ticker:Cancel() run.ticker = nil end
		local fight = run.fights
		Snap("fight " .. fight .. " ends")
		Later(0.6, "fight " .. fight .. " +0.6s")
		C_Timer.After(2, function() Drift(fight) end)
	elseif event == "PLAYER_TARGET_CHANGED" then
		Snap("target changed")
		Later(0.6, "target changed +0.6s")
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		Say(("%s %s %s"):format(event, tostring(a), tostring(b)))
	else
		Say(("%s %s"):format(event, tostring(a)))
	end
end)

local function Stop(why)
	if not run then return end
	Snap("end (" .. why .. ")", true)
	Shot("end")
	if run.ticker then run.ticker:Cancel() end
	run = nil
	CinematicDB.ufDriftAlways = nil
	watcher:UnregisterAllEvents()
	-- (After the shot, so the prompt isn't in it.)
	C_Timer.After(0.5, function() ns.TestPrompt("Unit frame recorder done. /reload now, then say check log", 10) end)
end

local function Start(always, fresh)
	Hook()
	if fresh or type(CinematicDB.ufDriftLog) ~= "table" then CinematicDB.ufDriftLog = {} end
	run = { at = GetTime(), last = {}, fights = 0, always = always }
	Say(("start%s: %s (game %s)"):format(always and " (always)" or "", ns.isRetail and "retail" or "classic",
		tostring((select(4, GetBuildInfo())))))
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
		"ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "UNIT_DISPLAYPOWER", "UNIT_CLASSIFICATION_CHANGED",
		"UNIT_LEVEL", "EDIT_MODE_LAYOUTS_UPDATED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }) do
		pcall(watcher.RegisterEvent, watcher, event)
	end
	Snap("start", true)
	if not always then
		local started = run
		C_Timer.After(LIMIT, function() if run == started then Stop("20 minutes") end end)
	end
end

function ns.UnitDriftTest(args)
	if run then
		Stop("you stopped it")
		return
	end
	if not ns.RefreshUnitStyle then
		ns.Print("unit frame recorder: the Unit Frames page isn't loaded")
		return
	end
	local always = (args or ""):find("always") ~= nil
	CinematicDB.ufDriftAlways = always or nil
	Start(always, true)
	Shot("start")
	ns.TestPrompt(always and "Unit frame recorder on, at every login too. When the frames look wrong: /cine debug ufdrift"
		or "Unit frame recorder on. Fight until the frames look wrong, then /cine debug ufdrift again", 10)
end

-- Always on: again after each login and /reload (once the frames are dressed:
-- our own passes run up to 2 s in), the log carried on.
local starter = CreateFrame("Frame")
starter:RegisterEvent("PLAYER_ENTERING_WORLD")
starter:SetScript("OnEvent", function()
	if run or not (CinematicDB and CinematicDB.ufDriftAlways) then return end
	C_Timer.After(3, function()
		if run or not CinematicDB.ufDriftAlways or not ns.RefreshUnitStyle then return end
		Start(true, false)
		ns.Print("unit frame recorder is on (always); /cine debug ufdrift stops it")
	end)
end)
