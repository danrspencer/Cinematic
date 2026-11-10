-- The Style hub's Combat Text Style (Tools/combat-text-plan.md): our own
-- damage and healing numbers over nameplates, drawn to look like the game's
-- floating world text. The game can't hide its "XP: 35" alone (one font
-- draws all its world text), so with its text blanked (hideWorldText) these
-- stand in for the damage numbers, without the XP.
--
-- Where they come from: UNIT_COMBAT, one listener per nameplate unit (a
-- listener for all units gets each hit 3-4 times: the plate, target,
-- softenemy). The amount is secret on Forever (in fights): never compared,
-- only put on a text with SetText, which takes it. The kind of hit, crit
-- flag and school are plain.
--
-- Where they show: on the plate itself (the base plate, not the UnitFrame
-- CineMode fades), in the plate's strata just above it, so they're over
-- every plate's art. A plate that goes (the mob died, the kill shot's
-- number still rising) leaves its numbers where it last was. A locked
-- (forbidden) plate gets none. How they move: matched by eye to the game's
-- (the constants below); its size and duration CVars still scale them.
--
-- The page (below): its Enable Page; ours on or off; whose hits; heals,
-- misses, school colors, the crit pop; font, outline, size, height; and the
-- game's own text: its damage and healing numbers off (CVars, at once), and
-- all of it, XP too (the blank font, Core.lua, from the next game start).

local _, ns = ...

local DEFAULTS = ns.DEFAULTS
DEFAULTS.combatTextStyle = false      -- the page's Enable Page
DEFAULTS.combatTextNumbers = true     -- our numbers over nameplates
DEFAULTS.combatTextHideGame = true    -- the game's damage and healing numbers off (its CVars) while the page is on
DEFAULTS.combatTextCritPop = true     -- a crit pops big and settles, as the game's
DEFAULTS.combatTextFont = "game"      -- "game": the game's floating text font; else a Style font
DEFAULTS.combatTextOutline = 1        -- 0 none, 1 thin (the game's), 2 thick
DEFAULTS.combatTextSize = 1           -- times the game's size
DEFAULTS.combatTextHeight = 0         -- extra pixels above the plate
DEFAULTS.combatTextSchoolColors = false -- spell damage in its school's color (else the game's yellow)
DEFAULTS.combatTextHeals = true       -- heals on friendly plates, in green
DEFAULTS.combatTextMisses = true      -- Miss, Dodge, Parry, Immune...
DEFAULTS.combatTextScope = "auto"     -- "auto" (yours, by the combat log; no log: your target's in a group), "all", "target"

-- The game's floating text font, read as this file loads: before Core's
-- ADDON_LOADED blanks it (hideWorldText).
local GAME_FONT = type(DAMAGE_TEXT_FONT) == "string" and not (issecretvalue and issecretvalue(DAMAGE_TEXT_FONT))
	and DAMAGE_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
ns.gameDamageTextFont = GAME_FONT

-- Matched side by side with the game's on Forever (2026-11-10 video, a mob
-- at mid range): its numbers ~1.4 times our first 24, starting level with
-- the plate's name (not above the plate), climbing ~60 pixels nearly
-- steadily, ~1.2 seconds in all, full until about 60% of that, then fading.
-- Crits, from a 30 fps look (same day): from a hit's size it grows to about
-- 2.5 times in ~0.13 s, shrinks back by ~0.25 s to ~1.3 times a hit, sits
-- over the plate's bar (lower than a hit) and barely climbs, still full a
-- second on. Hits landing together sit side by side, not stacked.
local BASE_SIZE = 33        -- the game's number at WorldTextScale_v2 1
local CRIT_SIZE = 1.3       -- a crit once settled, times a hit
local START_Y = -36         -- from the plate's top down to its name (a hit's bottom)
local RISE = 64             -- pixels a number climbs over its life
local CRIT_RISE = 0.2       -- a crit barely climbs
local CRIT_DROP = -36       -- a crit's middle, below a hit's
local CRIT_LIFE = 1.5       -- a crit stays longer, times a hit's life
local POP_PEAK, POP_UP, POP_DOWN = 2.5, 0.13, 0.25 -- the pop: times its size, seconds to grow, seconds till back
local TOGETHER = 0.25       -- seconds: hits this close in time spread sideways
local SPREAD = 1.3          -- a slot's width, times the text size (about two digits)
local EASE = 1.3            -- the climb's slowing: 1 = steady (the game's is close to it)
local LIFE = 1.2            -- seconds, at the game's WorldTextRampDuration_v2 1
local FADE_FROM = 0.6       -- of its life, when it starts fading
local MAX_LIVE = 40         -- numbers showing at once; the oldest goes first

-- Colors as the game's: a melee or physical hit white, a spell's yellow, a
-- heal green, a miss white. School colors (optional): its own.
local WHITE = { 1, 1, 1 }
local SPELL = { 1, 0.95, 0.2 }
local HEAL = { 0.1, 1, 0.1 }
local SCHOOL = {
	[1] = { 1, 1, 1 },          -- physical
	[2] = { 1, 0.9, 0.5 },      -- holy
	[4] = { 1, 0.5, 0.1 },      -- fire
	[8] = { 0.3, 1, 0.3 },      -- nature
	[16] = { 0.45, 0.85, 1 },   -- frost
	[32] = { 0.65, 0.4, 1 },    -- shadow
	[64] = { 1, 0.5, 0.95 },    -- arcane
}
-- The game's words for the hits with no number (its own strings: translated).
local MISSES = { MISS = true, DODGE = true, PARRY = true, BLOCK = true, RESIST = true, IMMUNE = true,
	ABSORB = true, EVADE = true, DEFLECT = true, REFLECT = true }

local function Plain(value)
	return not (issecretvalue and issecretvalue(value))
end

local function PageOn()
	return ns.StyleOn("combatTextStyle")
end

local function On()
	return PageOn() and ns.db.combatTextNumbers and not ns.combatTextBlocked and true or false
end

-- The game's world text CVars, read as a number starts (a CVar changed: at
-- once). Missing on a client: the default.
local function CVarNumber(name, default)
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	local ok, value = pcall(get, name)
	value = ok and Plain(value) and tonumber(value)
	return value or default
end

-- Numbers ---------------------------------------------------------------------
local holder = CreateFrame("Frame", nil, WorldFrame) -- (shows with the UI hidden, as the game's)
holder:SetAllPoints()
local live, spare = {}, {}

local function NewNumber()
	local number = table.remove(spare)
	if not number then
		number = CreateFrame("Frame", nil, holder)
		number:SetSize(1, 1)
		number.text = number:CreateFontString(nil, "OVERLAY")
		number.text:SetPoint("CENTER")
	end
	return number
end

local function Retire(index)
	local number = table.remove(live, index)
	number:Hide()
	number:ClearAllPoints()
	number.plate, number.unit, number.anchor, number.popping = nil, nil, nil, nil
	spare[#spare + 1] = number
end

-- Where a plate is on screen, or nil (a client where plates can't be measured).
local function PlateSpot(plate)
	local ok, x, y = pcall(plate.GetCenter, plate)
	if ok and x and y and Plain(x) and Plain(y) then
		local top = select(2, pcall(plate.GetTop, plate))
		if type(top) == "number" and Plain(top) then y = top end
		local scale = plate:GetEffectiveScale() / holder:GetEffectiveScale()
		return x * scale, y * scale
	end
end

local OUTLINES = { [0] = "", "OUTLINE", "THICKOUTLINE" }
local function SetSize(text, size)
	local db = ns.db
	local file = db and db.combatTextFont ~= "game" and ns.StyleFontFile(db.combatTextFont) or GAME_FONT
	local outline = OUTLINES[db and tonumber(db.combatTextOutline) or 1] or "OUTLINE"
	if not text:SetFont(file, size, outline) then
		text:SetFont("Fonts\\FRIZQT__.TTF", size, outline)
	end
end

-- Hits landing together spread sideways, as the game's do (its "Resist
-- Resist", "10 12" side by side): the nth number on a plate while others
-- there are still young goes in slot n: middle, right, left, further right...
local SLOTS = { 0, 1, -1, 2, -2, 3, -3 }
local function Slot(plate, now)
	local young = 0
	for _, other in ipairs(live) do
		if other.plate == plate and now - other.start < TOGETHER then young = young + 1 end
	end
	return SLOTS[young % #SLOTS + 1]
end

-- One number over a plate. color: an {r, g, b}; crit: pops big and settles
-- bigger, lower (over the plate's bar), barely climbing, staying longer.
local function Spawn(plate, unit, amount, color, crit)
	if #live >= MAX_LIVE then Retire(1) end
	local db = ns.db
	local now = GetTime()
	local number = NewNumber()
	local size = BASE_SIZE * CVarNumber("WorldTextScale_v2", 1) * (db.combatTextSize or 1)
	local x = Slot(plate, now) * size * SPREAD
	-- (its middle where a hit's bottom starts, half a hit above; a crit's lower)
	local y = START_Y + (db.combatTextHeight or 0) + size / 2 + (crit and CRIT_DROP or 0)
	if crit then size = size * CRIT_SIZE end
	local text = number.text
	SetSize(text, size)
	text:SetTextColor(color[1], color[2], color[3])
	text:SetText(amount) -- (a secret amount goes on as it is)
	number:SetFrameStrata(plate:GetFrameStrata())
	number:SetFrameLevel(math.min(plate:GetFrameLevel() + 20, 9000))
	number.plate, number.unit, number.crit, number.size = plate, unit, crit, size
	number.popping = crit and db.combatTextCritPop and text.SetTextHeight and true or nil
	number.start = now
	number.life = LIFE * math.max(0.3, CVarNumber("WorldTextRampDuration_v2", 1)) * (crit and CRIT_LIFE or 1)
	number.lift = y
	number.anchor, number.anchorPoint, number.baseX, number.baseY = plate, "TOP", x, y
	number:ClearAllPoints()
	number:SetPoint("CENTER", plate, "TOP", x, y)
	number:SetAlpha(1)
	number:Show()
	live[#live + 1] = number
	ns.WakeFeatureLoop(holder)
end

-- A plate gone (its unit died or went out of range): its numbers stay where
-- it last was, or go if that can't be read.
local function LetGo(plate)
	local x, y
	for index = #live, 1, -1 do
		local number = live[index]
		if number.plate == plate then
			if x == nil then x, y = PlateSpot(plate) end
			if x then
				number.anchor, number.anchorPoint = holder, "BOTTOMLEFT"
				number.baseX, number.baseY = x + number.baseX, y + number.lift
				number:ClearAllPoints()
				number:SetPoint("CENTER", holder, "BOTTOMLEFT", number.baseX, number.baseY)
				number.plate = false
			else
				Retire(index)
			end
		end
	end
end

-- How far through its life a number is: it climbs almost steadily, slowing
-- a little (1 - (1 - t) ^ EASE), and fades out from FADE_FROM to its end.
local function Step()
	local now = GetTime()
	for index = #live, 1, -1 do
		local number = live[index]
		local t = (now - number.start) / number.life
		if t >= 1 then
			Retire(index)
		else
			local eased = 1 - (1 - t) ^ EASE
			local rise = RISE * (number.crit and CRIT_RISE or 1) * eased
			-- (anchor and start height set at Spawn, or LetGo; the rise on top)
			number:SetPoint("CENTER", number.anchor, number.anchorPoint, number.baseX, number.baseY + rise)
			-- A crit's pop: up to POP_PEAK times its size by POP_UP seconds, back
			-- by POP_DOWN (the text scaled, not re-laid: no wobble), then its own
			-- font size again, sharp.
			if number.popping then
				local age = now - number.start
				local text = number.text
				if age >= POP_DOWN then
					number.popping = nil
					SetSize(text, number.size)
				else
					local k = age < POP_UP and age / POP_UP or 1 - (age - POP_UP) / (POP_DOWN - POP_UP)
					pcall(text.SetTextHeight, text, number.size * (1 + (POP_PEAK - 1) * k))
				end
			end
			number:SetAlpha(t > FADE_FROM and (1 - t) / (1 - FADE_FROM) or 1)
		end
	end
end

-- Whose hit -------------------------------------------------------------------
-- UNIT_COMBAT never says who hit, so a party member's swing on your mob
-- showed as yours (seen 2026-11-10). The game's combat log does, but its
-- lines come as protected text (COMBAT_LOG_MESSAGE: "|Ky16|k"): unreadable,
-- yet they come, and with Blizzard's filter as it stands (yours: you and your
-- pet) a line comes with each hit of yours and none with a teammate's. So a
-- hit is yours when a line comes within HOLD of it, one line per hit (a hit
-- waits up to HOLD for one; a line waits as long for its hit). Hits on you
-- and your pet take their own lines, so a mob's swing at you can't lend its
-- line to a teammate's hit. Lines come only while the log's filtered events
-- are on, which Blizzard turns on and off with its combat log tab: while our
-- numbers are on we keep them on, and turn them back off if we did. No log
-- (a client without it): every hit counts, and in a group only your target's.
local HOLD = 0.15
local lines, owed, pending = {}, {}, {} -- times of lines; of hits on you; hits waiting
local logListening, logTurnedOn
ns.combatTextWhose = { mine = 0, others = 0 }

local function LogRunning()
	if not logListening or not (C_CombatLog and C_CombatLog.AreFilteredEventsEnabled) then return false end
	local ok, on = pcall(C_CombatLog.AreFilteredEventsEnabled)
	return ok and Plain(on) and on == true
end

local function Fresh(list, now)
	while list[1] and now - list[1] > HOLD do table.remove(list, 1) end
end

local function Mine(hit)
	ns.combatTextWhose.mine = ns.combatTextWhose.mine + 1
	Spawn(hit[1], hit[2], hit[3], hit[4], hit[5])
end

-- A hit on a plate: shown now if a line came for it, else held for one.
local function Claim(plate, unit, amount, color, crit)
	local hit = { plate, unit, amount, color, crit }
	if not LogRunning() then return Spawn(plate, unit, amount, color, crit) end
	local now = GetTime()
	Fresh(lines, now)
	if lines[1] then
		table.remove(lines, 1)
		return Mine(hit)
	end
	hit.at = now
	pending[#pending + 1] = hit
	ns.WakeFeatureLoop(holder)
end

local function OnLine()
	local now = GetTime()
	Fresh(owed, now)
	if owed[1] then table.remove(owed, 1) return end -- (a hit on you, already here)
	while pending[1] and now - pending[1].at > HOLD do table.remove(pending, 1) end
	if pending[1] then return Mine(table.remove(pending, 1)) end
	lines[#lines + 1] = now
end

-- A hit on you or your pet: its line isn't for a plate's hit.
local function OnOwnHit()
	local now = GetTime()
	Fresh(lines, now)
	if lines[1] then table.remove(lines, 1) else owed[#owed + 1] = now end
end

-- Hits held past HOLD with no line: someone else's.
local function DropUnclaimed(now)
	while pending[1] and now - pending[1].at > HOLD do
		table.remove(pending, 1)
		ns.combatTextWhose.others = ns.combatTextWhose.others + 1
	end
end

-- The log's lines kept coming while our numbers are on (Blizzard turns them
-- off as its combat log tab hides); put back as they were when ours go off.
local function KeepLog()
	if not (C_CombatLog and C_CombatLog.SetFilteredEventsEnabled and C_CombatLog.AreFilteredEventsEnabled) then return end
	local ok, on = pcall(C_CombatLog.AreFilteredEventsEnabled)
	if not ok or not Plain(on) then return end
	if On() then
		if not on then
			pcall(C_CombatLog.SetFilteredEventsEnabled, true)
			logTurnedOn = true
		end
	elseif logTurnedOn then
		logTurnedOn = nil
		local window = _G.COMBATLOG
		local shown = type(window) == "table" and window.IsShown and window:IsShown()
		if on and not (Plain(shown) and shown) then pcall(C_CombatLog.SetFilteredEventsEnabled, false) end
	end
end

-- The game's own damage and healing numbers off while the page is on (its
-- Turn off tick): their CVars, at once, yours put back as the page goes off.
-- (Not its XP: no CVar has it; that's Hide all, the blank font.)
local GAME_NUMBERS = ns.CVarSet("Game's damage numbers off", "Combat Text Style (combatTextHideGame)", {
	playerWins = true,
	values = {
		floatingCombatTextCombatDamage = "0",
		floatingCombatTextCombatHealing = "0",
		floatingCombatTextPetMeleeDamage = "0",
		floatingCombatTextPetSpellDamage = "0",
		floatingCombatTextCombatDamage_v2 = "0",
		floatingCombatTextCombatHealing_v2 = "0",
		floatingCombatTextPetMeleeDamage_v2 = "0",
		floatingCombatTextPetSpellDamage_v2 = "0",
	},
})

-- After a setting changes (the page), and every two seconds.
function ns.RefreshCombatTextStyle()
	ns.ApplyCVarSet(GAME_NUMBERS, (PageOn() and ns.db.combatTextHideGame) and true or false)
	KeepLog()
	if not On() then
		for index = #live, 1, -1 do Retire(index) end
		wipe(pending)
	end
end

ns.FeatureLoop(holder, function(...)
	DropUnclaimed(GetTime())
	Step(...)
end, function() return #live > 0 or #pending > 0 end)

-- Hits -------------------------------------------------------------------------
local function InGroup()
	return (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid())
end

local function Wanted(unit, enemy)
	local scope = ns.db.combatTextScope or "auto"
	if scope == "auto" then scope = (InGroup() and not LogRunning()) and "target" or "all" end
	if scope == "target" and enemy then
		local ok, same = pcall(UnitIsUnit, unit, "target")
		return ok and Plain(same) and same
	end
	return true
end

local flagsSeen = {}
local function OnHit(unit, action, flag, amount, school)
	if not On() or not Plain(unit) or not Plain(action) then return end
	local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
	local ok, plate = pcall(get or error, unit)
	if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
	local okEnemy, enemy = pcall(UnitCanAttack, "player", unit)
	enemy = okEnemy and Plain(enemy) and enemy
	if not Wanted(unit, enemy) then return end
	local db = ns.db
	local crit = Plain(flag) and flag == "CRITICAL"
	-- (Each kind of hit and flag once in /cine log: is a crit "CRITICAL" here?)
	if Plain(flag) then
		local seen = action .. "/" .. tostring(flag)
		if not flagsSeen[seen] then
			flagsSeen[seen] = true
			ns.Log("combattext", "first " .. seen .. (crit and " (a crit)" or ""))
		end
	end
	if action == "WOUND" then
		if not enemy then return end
		-- (A plain 0: all of it absorbed, as the game's word.)
		if Plain(amount) and (amount == 0 or amount == "0") then
			if db.combatTextMisses then Claim(plate, unit, _G.ABSORB or "Absorb", WHITE, false) end
			return
		end
		local color = SPELL
		school = Plain(school) and tonumber(school) or 1
		if school == 1 then
			color = WHITE
		elseif db.combatTextSchoolColors then
			color = SCHOOL[school] or SPELL
		end
		Claim(plate, unit, amount, color, crit)
	elseif action == "HEAL" then
		if enemy or not db.combatTextHeals then return end
		Claim(plate, unit, amount, HEAL, crit)
	elseif MISSES[action] and enemy and db.combatTextMisses then
		local word = _G[action]
		if not (type(word) == "string" and Plain(word)) then word = action:sub(1, 1) .. action:sub(2):lower() end
		Claim(plate, unit, word, WHITE, false)
	end
end

-- One listener per plate unit, made as its plate comes.
local listeners = {}
local function Listen(unit)
	if listeners[unit] then return end
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", ns.Profiled("Combat text", function(_, _, ...) OnHit(...) end))
	if pcall(frame.RegisterUnitEvent, frame, "UNIT_COMBAT", unit) then
		listeners[unit] = frame
	end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", ns.Profiled("Combat text plates", function(_, event, unit)
	if event == "PLAYER_LOGIN" then
		-- Forever Combat Text draws the same numbers: ours step aside.
		local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
		ns.combatTextBlocked = loaded and loaded("ForeverCombatText") and "ForeverCombatText" or nil
		for i = 1, 40 do Listen("nameplate" .. i) end
		-- Whose hit: the log's lines, and the hits on you and your pet that own theirs.
		local log = CreateFrame("Frame")
		logListening = pcall(log.RegisterEvent, log, "COMBAT_LOG_MESSAGE")
		log:SetScript("OnEvent", ns.Profiled("Combat text log", function()
			if On() then OnLine() end
		end))
		local own = CreateFrame("Frame")
		pcall(own.RegisterUnitEvent, own, "UNIT_COMBAT", "player", "pet")
		own:SetScript("OnEvent", ns.Profiled("Combat text own", function()
			if On() then OnOwnHit() end
		end))
		if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2, function() ns.Guard(ns.RefreshCombatTextStyle) end) end
		ns.RefreshCombatTextStyle()
		return
	end
	if not Plain(unit) then return end
	if event == "NAME_PLATE_UNIT_ADDED" then
		Listen(unit)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
		local ok, plate = pcall(get or error, unit)
		if ok and plate then LetGo(plate) end
	end
end))

-- /cine debug combatnumbers: the page on or off, with what it needs and how
-- many hits it took as yours and left out as others'.
function ns.CombatNumbersToggle()
	local db = ns.db
	db.combatTextStyle = not db.combatTextStyle
	ns.RefreshCombatTextStyle()
	local whose = ns.combatTextWhose
	local text = ("Combat Text Style %s (Style hub %s, our numbers %s)%s. Game's damage numbers %s; all its"
		.. " floating text %s (font %s). Whose hit: %s; so far %d shown as yours, %d left out as others'"):format(
		db.combatTextStyle and "on" or "off", db.styleGeneral and "on" or "off",
		db.combatTextNumbers and "on" or "off",
		ns.combatTextBlocked and (", but held back: " .. ns.combatTextBlocked .. " is loaded") or "",
		GAME_NUMBERS.active and "off" or "showing", db.hideWorldText and "hidden after a restart" or "showing",
		tostring(GAME_FONT),
		LogRunning() and "combat log lines" or (logListening and "log off: all hits count" or "no log on this client"),
		whose.mine, whose.others)
	ns.Print(text)
	ns.Log("combattext", text)
end

-- A sample over a frame, for the page's preview: "hit" (a spell's), "white"
-- (a swing's), "crit", "heal" or "miss".
function ns.CombatTextSample(frame, kind)
	local db = ns.db
	if kind == "miss" then return Spawn(frame, nil, _G.MISS or "Miss", WHITE, false) end
	if kind == "heal" then return Spawn(frame, nil, "18", HEAL, false) end
	local color = kind == "white" and WHITE or (db.combatTextSchoolColors and SCHOOL[8] or SPELL)
	Spawn(frame, nil, kind == "crit" and "46" or kind == "white" and "11" or "23", color, kind == "crit")
end

-- The page ------------------------------------------------------------------
local L = ns.L

function ns.CreateCombatTextStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Combat Text Style"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["Damage and healing numbers of our own over nameplates, drawn to look like the game's, and the game's " ..
		"own floating text turned off. The game draws its XP gains (\"XP: 35\") in the same font as its damage " ..
		"numbers, so the only way to hide the XP is to hide all of its text and show ours instead."])

	local function Changed() ns.RefreshCombatTextStyle() end
	local switch = kit.PageSwitch(content, "combatTextStyle", L["Enable Page"],
		L["On: this page's settings take hold. Off: the game's own floating text, as it was."], intro, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "combatTextStyle")
	local function Ours(db) return rows.On(db) and db.combatTextNumbers end

	-- The preview: a nameplate of a mob, and Test, which plays a hit, a swing, a
	-- crit, two landing together and a miss on it with this page's look.
	local preview = CreateFrame("Frame", nil, content)
	preview:SetSize(480, 150)
	local back = preview:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.05, 0.06, 0.08, 0.9)
	local plate = CreateFrame("Frame", nil, preview)
	plate:SetSize(140, 30)
	plate:SetPoint("BOTTOM", 0, 26)
	local bar = plate:CreateTexture(nil, "ARTWORK")
	bar:SetPoint("BOTTOMLEFT")
	bar:SetSize(140, 10)
	bar:SetColorTexture(0.75, 0.1, 0.1, 1)
	local name = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	name:SetPoint("BOTTOM", bar, "TOP", 0, 3)
	name:SetText(L["Gnarlpine Ambusher"])
	name:SetTextColor(1, 0.3, 0.2)
	stack:Add(preview, "label")
	kit.AddControl(preview)
	preview.Refresh = function() end
	local function Play()
		local steps = { { 0, "hit" }, { 0.5, "white" }, { 1.0, "crit" }, { 1.8, "hit" }, { 1.85, "white" }, { 2.6, "miss" } }
		for _, step in ipairs(steps) do
			C_Timer.After(step[1], function()
				if preview:IsVisible() then ns.CombatTextSample(plate, step[2]) end
			end)
		end
	end
	ns.StylePreviewTest(preview, kit, L["Plays a few hits on the nameplate: a spell's, a swing's, a crit, " ..
		"two landing together and a miss, with this page's look."], Play)

	stack:Header(content, L["Our numbers"])
	rows.Check("combatTextNumbers", L["Show your damage and healing over nameplates"],
		L["Our own numbers: your hits on the nameplate of what you hit, your heals on a friend's. They take " ..
		"the game's place when its text is off below."])
	rows.Choices(L["Whose hits:"], "combatTextScope", {
		{ "auto", L["Yours"], L["Only your own hits and your pet's, as the game shows. The game doesn't say who " ..
			"hit, so this goes by its combat log: leave its filter as it comes (your actions). With no log, " ..
			"in a group only your target's."] },
		{ "target", L["Your target's"], L["Every hit on your target only, anyone's."] },
		{ "all", L["Everyone's"], L["Every hit on every nameplate, yours or not."] },
	}, Ours)
	rows.Check("combatTextHeals", L["Your heals on friends"], L["Heals on friendly nameplates, in green."], Ours)
	rows.Check("combatTextMisses", L["Misses"], L["Miss, Dodge, Parry, Immune and the like, in the game's words."],
		Ours)
	rows.Check("combatTextCritPop", L["Crits pop"],
		L["A crit grows big for a moment and settles a little bigger than a hit, as the game's do."], Ours)
	rows.Check("combatTextSchoolColors", L["Spells in their school's color"],
		L["Fire orange, frost blue, nature green and so on. Off: spells in the game's yellow, swings in white."],
		Ours)

	stack:Header(content, L["Look"])
	rows.Font("combatTextFont", L["The numbers' font. The game's: the one it draws its own floating text in."],
		Ours, { "game", L["The game's"] })
	rows.Outline("combatTextOutline", L["Outline"], 2, { [0] = L["None"], L["Thin"], L["Thick"] },
		L["A black border around the numbers. Thin: as the game's."], Ours)
	rows.Slider("combatTextSize", L["Size"], 50, 200, 5, "%d%%", 100,
		L["How big the numbers are, next to the game's."], Ours)
	rows.Slider("combatTextHeight", L["Height"], -40, 80, 2, "%d px", nil,
		L["Moves the numbers up (or down) from where the game's start: level with the nameplate's name."], Ours)

	stack:Header(content, L["The game's floating text"])
	rows.Check("combatTextHideGame", L["Turn off the game's damage and healing numbers"],
		L["The game's own numbers over what you hit and heal, off at once while this page is on, and back as " ..
		"they were when it's off. Its XP gains stay: for those, the next one."])
	local all = rows.Check("hideWorldText", L["Hide all the game's floating text, XP too (restart required)"],
		L["The game has no way to hide just the XP you gain: it draws that, its damage and healing numbers, " ..
		"misses and the like all in one font. This blanks that font, so they all go, always. Takes effect " ..
		"after you fully restart the game; /reload isn't enough."])
	all:HookScript("OnClick", function() StaticPopup_Show("CINEMATIC_WORLD_TEXT_RESTART") end)

	canvas:SetScript("OnShow", kit.PageShown(kit.Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Combat Text Style", L["Combat Text Style"])
end
