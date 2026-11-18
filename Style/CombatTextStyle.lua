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
DEFAULTS.combatTextEdge = "game"      -- "game" (a drop shadow, as the game's), "both" (an edge too), "edge", "none"
DEFAULTS.combatTextSize = 1           -- times the game's size
DEFAULTS.combatTextHeight = 0         -- extra pixels above the plate
DEFAULTS.combatTextSchoolColors = false -- spell damage in its school's color (else the game's yellow)
DEFAULTS.combatTextHeals = true       -- heals on friendly plates, in green
DEFAULTS.combatTextMisses = true      -- Miss, Dodge, Parry, Immune...
DEFAULTS.combatTextKeepLast = true    -- a dying mob's last numbers finish above the screen's middle (LetGo)
DEFAULTS.combatTextKill = false       -- "Kill" there when the game sent no number for the killing blow (off by default since 2026-11-18)
DEFAULTS.combatTextSpells = true      -- spell hits (yellow)
DEFAULTS.combatTextSwings = true      -- swings and physical hits (white)
DEFAULTS.combatTextCrits = true       -- crits drawn as crits (off: as a plain hit)
DEFAULTS.combatTextCritSpot = "plate" -- "plate": over the plate's bar, as the game's; "above": where hits start, climbing as they do

-- The game's floating text font, read as this file loads: before Core's
-- ADDON_LOADED blanks it (hideWorldText).
local GAME_FONT = type(DAMAGE_TEXT_FONT) == "string" and not (issecretvalue and issecretvalue(DAMAGE_TEXT_FONT))
	and DAMAGE_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
ns.gameDamageTextFont = GAME_FONT

-- Whether the game is drawing its floating text blank right now: the font it
-- took at the game's start, kept through /reloads (CinematicDB.worldTextLive,
-- set on the first login of a game start only). The page's Hide all row says
-- "restart to apply" while its tick differs from this.
local liveWatch = CreateFrame("Frame")
liveWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
liveWatch:SetScript("OnEvent", function(self, _, isInitialLogin, isReloadingUi)
	self:UnregisterAllEvents()
	if ns.db and (isInitialLogin and not isReloadingUi or ns.db.worldTextLive == nil) then
		ns.db.worldTextLive = ns.blankWorldFont ~= nil
	end
end)

-- Matched side by side with the game's on Forever (2026-11-10 video, a mob
-- at mid range): its numbers ~1.4 times our first 24, starting level with
-- the plate's name (not above the plate), climbing ~60 pixels nearly
-- steadily, ~1.2 seconds in all, full until about 60% of that, then fading.
-- Crits, from a 30 fps look (same day): from a hit's size it grows to about
-- 2.5 times in ~0.13 s, shrinks back by ~0.25 s to ~1.3 times a hit, sits
-- over the plate's bar (lower than a hit) and barely climbs, still full a
-- second on. Hits landing together sit side by side, not stacked.
local BASE_SIZE = 36        -- the game's number at WorldTextScale_v2 1 (two shots: theirs ~1.1 times our first 33)
local CRIT_SIZE = 1.3       -- a crit once settled, times a hit
local START_Y = -36         -- from the plate's top down to its name (a hit's bottom)
local RISE = 40             -- pixels a number drifts up over its life, after its jump
local JUMP, JUMP_TIME = 40, 0.2 -- and the quick jump up it starts with (the game's, at mid range: it leaps, then drifts)
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
-- heal green, a miss yellow (seen in a recording, 2026-11-10). School colors (optional): its own.
local WHITE = { 1, 1, 1 }
local SPELL = { 1, 0.867, 0 } -- (the game's, read off a screenshot: 255, 221, 0)
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
-- A style theme's own colors for its numbers (its combatText list: hit, spell,
-- heal, crit, miss), else these, the game's. School colors, picked on the page,
-- win over a theme's spell color.
local function Color(kind, game)
	local theme = ns.ActiveStyleTheme and ns.ActiveStyleTheme()
	local own = theme and theme.combatText and theme.combatText[kind]
	return own or game
end

-- Each text of its own (the page's tabs): whether it shows, and its size,
-- height, side, climb, time on screen and a color of its own, as
-- combatText<Name><Setting>. A crit (shown as one) takes the Crit ones.
local KILL_COLOR = { 1, 0.3, 0.25 }
ns.COMBAT_TEXTS = {
	{ kind = "spell", name = "Spell", show = "combatTextSpells", color = SPELL, y = 10 },
	{ kind = "swing", name = "Swing", show = "combatTextSwings", color = WHITE, y = 10 },
	{ kind = "crit", name = "Crit", show = "combatTextCrits", color = SPELL, y = 50 },
	{ kind = "heal", name = "Heal", show = "combatTextHeals", color = HEAL, y = 10 },
	{ kind = "miss", name = "Miss", show = "combatTextMisses", color = SPELL, y = 0 },
	{ kind = "kill", name = "Kill", show = "combatTextKill", color = KILL_COLOR, y = 10 },
}
local TEXT_OF = {}
for _, text in ipairs(ns.COMBAT_TEXTS) do
	TEXT_OF[text.kind] = text
	local key = "combatText" .. text.name
	DEFAULTS[key .. "Size"] = 1    -- times the page's size
	DEFAULTS[key .. "Y"] = text.y or 0 -- pixels up (the player's picks, 2026-11-18: crits 50 up, misses level)
	DEFAULTS[key .. "X"] = 0       -- pixels right
	DEFAULTS[key .. "Rise"] = 1    -- times its usual climb
	DEFAULTS[key .. "Life"] = 1    -- times its usual time on screen
	DEFAULTS[key .. "Own"] = false -- its own color (below), not the game's (or the theme's)
	DEFAULTS[key .. "R"], DEFAULTS[key .. "G"], DEFAULTS[key .. "B"] = text.color[1], text.color[2], text.color[3]
end

-- A setting as it applies: its usual while a switch over it is off (its
-- tab's, right-clicked off).
local function Value(key)
	local db = ns.db
	if not db or (ns.MasterOff and ns.MasterOff(key, db)) then return DEFAULTS[key] end
	local value = db[key]
	if value == nil then return DEFAULTS[key] end
	return value
end
-- Whether a text shows. sample: the page's preview, which plays with the
-- page off too: its own tick and its tab (right-clicked off) still count.
local function Shows(text, sample)
	local db = ns.db
	if not db then return false end
	if not sample then return ns.Setting(text.show) and true or false end
	if db[text.show] == false then return false end
	local over = ns.PageSwitchOf and ns.PageSwitchOf(text.show)
	for _ = 1, 10 do
		if not over then break end
		if over:find("^tabOn:") and db[over] == false then return false end
		over = ns.PageSwitchOf(over)
	end
	return true
end

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
-- (sparePreview: the page preview's own: a number that's held a fight's
-- secret amount, put in the options page, made its scroll range secret, and
-- the mouse wheel there errored, 2026-11-18. The two never swap.)
local live, spare, sparePreview = {}, {}, {}

local function NewNumber(layer)
	local number = table.remove(layer and sparePreview or spare)
	if not number then
		number = CreateFrame("Frame", nil, layer or holder)
		number:SetSize(1, 1)
		-- (The words sit in a frame of their own: its alpha is the amount, so a
		-- hit of 0 draws nothing. See Spawn.)
		number.body = CreateFrame("Frame", nil, number)
		number.body:SetAllPoints()
		number.text = number.body:CreateFontString(nil, "OVERLAY")
		number.text:SetPoint("CENTER")
		-- (Behind it: its edge, the words again eight times nudged each way in
		-- black; and its drop shadow, once more up and to the right. Each in a
		-- layer of its own, shadow under edge under words: in one layer their
		-- order was anyone's, the black over the yellow, seen 2026-11-10.)
		number.copies = {}
		for i = 1, 9 do
			local copy = number.body:CreateFontString(nil, i == 9 and "BORDER" or "ARTWORK")
			copy.angle = i <= 8 and (i - 1) * math.pi / 4 or nil
			number.copies[i] = copy
		end
	end
	return number
end

local function Retire(index)
	local number = table.remove(live, index)
	number:Hide()
	number:ClearAllPoints()
	number.plate, number.unit, number.anchor, number.popping, number.kill = nil, nil, nil, nil, nil
	local pool = number.onLayer and sparePreview or spare -- (a preview's stays the preview's)
	pool[#pool + 1] = number
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

-- The game's look, read off a screenshot (2026-11-10): a dark edge all round
-- (~2 px on a 49 px digit) and a drop shadow ~4-5 px down and to the right.
-- The font's own OUTLINE drew nothing on ours there, so both are drawn as
-- copies of the words: the edge's nudge and the shadow's drop by the size.
-- (Second look, same day: ours came out 4-5 times darker round the digits
-- than the game's in one screenshot: its edge is about a pixel and see-
-- through, its shadow longer but faint.)
-- (Third look: the game's edge is a band about a pixel wide, ~75% dark,
-- hardly spreading; ours stacked to near black and several pixels wide, as
-- eight overlapping copies add up. So each copy is faint (about three
-- overlap at an edge: 1 - 0.65^3, ~0.75) and the shadow sits close.)
-- (Fourth look, a recording: the edges now match all round, but down and to
-- the right ours were still darker; the game's is about as dark there as
-- elsewhere. So its shadow is barely one.)
-- (Fifth look, two crops the player sent: theirs has a strong drop shadow,
-- and it falls up and to the right, ~3 px each way on 64 px digits; an earlier
-- look had mixed up which numbers were whose and thinned ours wrongly.)
local EDGE, EDGE_ALPHA, DROP, SHADOW_ALPHA = 1 / 40, 0.35, 1 / 28, 0.8
local function SetSize(number, size)
	local db = ns.db
	local font = db and Value("combatTextFont")
	local file = font and font ~= "game" and ns.StyleFontFile(font) or GAME_FONT
	local text = number.text
	if not text:SetFont(file, size, "") then
		file = "Fonts\\FRIZQT__.TTF"
		text:SetFont(file, size, "")
	end
	text:SetShadowOffset(0, 0)
	local look = db and Value("combatTextEdge") or "game"
	-- (The game's: the shadow alone, no edge, the player saw side by side;
	-- "shadow", an older name for it.)
	local edge = look == "both" or look == "edge"
	local shadow = look == "game" or look == "both" or look == "shadow"
	local nudge, drop = math.max(1, size * EDGE), math.max(1, size * DROP)
	for _, copy in ipairs(number.copies) do
		copy:SetFont(file, size, "")
		copy:SetShadowOffset(0, 0)
		copy:ClearAllPoints()
		if copy.angle then
			copy:SetPoint("CENTER", math.cos(copy.angle) * nudge, math.sin(copy.angle) * nudge)
			copy:SetTextColor(0, 0, 0, EDGE_ALPHA)
			copy:SetShown(edge)
		else
			copy:SetPoint("CENTER", drop, drop)
			copy:SetTextColor(0, 0, 0, SHADOW_ALPHA)
			copy:SetShown(shadow)
		end
	end
end

-- The words on the number and its copies.
local function SetWords(number, amount)
	number.text:SetText(amount) -- (a secret amount goes on as it is)
	for _, copy in ipairs(number.copies) do copy:SetText(amount) end
end

-- All of it scaled for a moment (a crit's pop), without laying it out again.
local function SetHeight(number, height)
	pcall(number.text.SetTextHeight, number.text, height)
	for _, copy in ipairs(number.copies) do
		if copy:IsShown() then pcall(copy.SetTextHeight, copy, height) end
	end
end

-- Hits landing together spread sideways, as the game's do (its "Resist
-- Resist", "10 12" side by side): a number landing while others on its plate
-- are still young goes past the outermost of them, right then left in turn,
-- by their widths (an amount that can't be measured, being secret: about two
-- digits).
local GAP = 4
local function Width(number, size)
	return number.width or size * SPREAD
end
local function SlotX(plate, now, width)
	local right, left, count = nil, nil, 0
	for _, other in ipairs(live) do
		if other.plate == plate and now - other.start < TOGETHER then
			count = count + 1
			local half = Width(other, other.size) / 2
			local r, l = other.baseX + half, other.baseX - half
			right = right and math.max(right, r) or r
			left = left and math.min(left, l) or l
		end
	end
	if count == 0 then return 0 end
	if count % 2 == 1 then return right + GAP + width / 2 end
	return left - GAP - width / 2
end

-- /cine debug combattext running: a number as it's made, and how it stands a
-- moment later (drawn? where? how see-through?).
local function Seen(value)
	if issecretvalue and issecretvalue(value) then return "<secret>" end
	return type(value) == "number" and ("%.1f"):format(value) or tostring(value)
end
local function RecordSpawn(number, plate, unit, amount, color, crit, size)
	local record = ns.combatTextRecord
	if not record then return end
	local function Stand(tag)
		local okC, cx, cy = pcall(number.GetCenter, number)
		local okP, px, py = pcall(plate.GetCenter, plate)
		local okW, width = pcall(number.text.GetStringWidth, number.text)
		local okA, alpha = pcall(number.GetEffectiveAlpha, number)
		local okS, scale = pcall(number.GetEffectiveScale, number)
		local okPA, plateAlpha = pcall(plate.GetEffectiveAlpha, plate)
		record(("%s unit=%s words=%s color=%.2f,%.2f,%.2f crit=%s size=%s visible=%s shown=%s alpha=%s scale=%s"
			.. " center=%s,%s width=%s strata=%s level=%s | plate visible=%s alpha=%s center=%s,%s strata=%s"
			.. " level=%s | holder visible=%s live=%d | alpha from amount took=%s, words alpha=%s"):format(
			tag, tostring(unit), Seen(amount), color[1], color[2], color[3], tostring(crit), Seen(size),
			tostring(number:IsVisible()), tostring(number:IsShown()), okA and Seen(alpha) or "error",
			okS and Seen(scale) or "error", okC and Seen(cx) or "error", okC and Seen(cy) or "error",
			okW and Seen(width) or "error", tostring(number:GetFrameStrata()), tostring(number:GetFrameLevel()),
			tostring(plate:IsVisible()), okPA and Seen(plateAlpha) or "error", okP and Seen(px) or "error",
			okP and Seen(py) or "error", tostring(plate:GetFrameStrata()), tostring(plate:GetFrameLevel()),
			tostring(holder:IsVisible()), #live, tostring(number.zeroHide),
			Seen(select(2, pcall(number.body.GetAlpha, number.body)))))
	end
	local ok, err = pcall(Stand, "DRAWN")
	if not ok then record("DRAWN: could not read it: " .. tostring(err)) end
	local start = number.start
	C_Timer.After(0.3, function()
		if number.start ~= start then return record("0.3 s on: number already gone") end
		if number.plate == false then return record("0.3 s on: its plate went, moved above the screen's middle") end
		if number.plate ~= plate then return record("0.3 s on: number already gone") end
		local okLater, errLater = pcall(Stand, "0.3 s on")
		if not okLater then record("0.3 s on: could not read it: " .. tostring(errLater)) end
	end)
end

local lastHit = setmetatable({}, { __mode = "k" }) -- [plate] = { at, guid }: our last number on it
local KillWord -- (below)

-- One number over a plate. color: an {r, g, b}; crit: pops big and settles
-- bigger, lower (over the plate's bar), barely climbing, staying longer.
-- layer: a frame to draw it in instead of the world's (a preview's: the
-- options window is over the world's frames), at the world's size.
-- kind: which text it is (ns.COMBAT_TEXTS: "spell", "swing", "heal", "miss",
-- "kill"): one turned off shows nothing, and its own settings (a crit's,
-- the Crit ones) place it. Gives the number, or nil.
local function Spawn(plate, unit, amount, color, crit, layer, kind)
	local base = TEXT_OF[kind or "spell"] or TEXT_OF.spell
	if not Shows(base, layer) then return end
	local critText = TEXT_OF.crit
	crit = crit and Shows(critText, layer) or false
	local key = "combatText" .. (crit and critText or base).name
	-- (Its color: its own; a crit's own over a hit's (a heal's crit keeps the heal's).)
	local baseKey = "combatText" .. base.name
	if crit and base.kind ~= "heal" and Value("combatTextCritOwn") then
		color = { Value("combatTextCritR"), Value("combatTextCritG"), Value("combatTextCritB") }
	elseif Value(baseKey .. "Own") then
		color = { Value(baseKey .. "R"), Value(baseKey .. "G"), Value(baseKey .. "B") }
	end
	if #live >= MAX_LIVE then Retire(1) end
	local now = GetTime()
	local number = NewNumber(layer)
	local size = BASE_SIZE * CVarNumber("WorldTextScale_v2", 1) * (Value("combatTextSize") or 1)
		* (Value(key .. "Size") or 1)
	-- (its middle where a hit's bottom starts, half a hit above; a crit's lower,
	-- over the plate's bar, unless it's put where hits start)
	local onBar = crit and Value("combatTextCritSpot") ~= "above"
	local y = START_Y + (Value("combatTextHeight") or 0) + (Value(key .. "Y") or 0) + size / 2
		+ (onBar and CRIT_DROP or 0)
	if crit then size = size * CRIT_SIZE end
	local text = number.text
	SetSize(number, size)
	text:SetTextColor(color[1], color[2], color[3])
	SetWords(number, amount)
	-- A hit of 0 (Maul comes as two hits in one instant: the swing it took the
	-- place of, for 0, and its own) showed as a white "0". The amount is secret
	-- in a fight, so it can't be checked; but it can be the words' alpha: 0
	-- draws nothing, 1 and up draws in full.
	number.body:SetAlpha(1)
	number.zeroHide = nil
	if not Plain(amount) then number.zeroHide = pcall(number.body.SetAlpha, number.body, amount) end
	local ok, width = pcall(text.GetStringWidth, text)
	number.width = ok and type(width) == "number" and Plain(width) and width > 0 and width or nil
	local x = SlotX(plate, now, Width(number, size)) + (Value(key .. "X") or 0)
	if layer then
		number.onLayer = true
		number:SetParent(layer)
		number:SetScale(holder:GetEffectiveScale() / layer:GetEffectiveScale())
		number:SetFrameStrata(layer:GetFrameStrata())
		number:SetFrameLevel(math.min(layer:GetFrameLevel() + 1, 9000))
	else
		number:SetFrameStrata(plate:GetFrameStrata())
		number:SetFrameLevel(math.min(plate:GetFrameLevel() + 20, 9000))
	end
	number.plate, number.unit, number.crit, number.size = plate, unit, crit, size
	number.popping = crit and Value("combatTextCritPop") and text.SetTextHeight and true or nil
	number.riseBy = (onBar and CRIT_RISE or 1) * (Value(key .. "Rise") or 1)
	number.start = now
	number.life = LIFE * math.max(0.3, CVarNumber("WorldTextRampDuration_v2", 1)) * (crit and CRIT_LIFE or 1)
		* math.max(0.1, Value(key .. "Life") or 1)
	number.lift = y
	number.anchor, number.anchorPoint, number.baseX, number.baseY = plate, "TOP", x, y
	number:ClearAllPoints()
	number:SetPoint("CENTER", plate, "TOP", x, y)
	number:SetAlpha(1)
	number:Show()
	live[#live + 1] = number
	ns.WakeFeatureLoop(holder)
	-- (A real hit's time and mob on its plate: a kill with no number, KillWord.)
	if unit then
		local okGuid, guid = pcall(UnitGUID, unit)
		lastHit[plate] = { at = now, guid = okGuid and Plain(guid) and guid or nil }
	end
	RecordSpawn(number, plate, unit, amount, color, crit, size)
	return number
end

-- A plate gone (its unit died or went out of range): its numbers stay where
-- it last was. Where that can't be read (WoW Forever: neither a plate's place
-- nor its anchor can, recorded 2026-11-18; left on the gone plate they didn't
-- show, it's hidden at alpha 0), they move a little above the screen's middle,
-- where a mob you fight in melee mostly stands, and finish rising there: a
-- kill's last hit, its plate gone 0.26-0.3 s after it, stays readable.
local GONE_Y = 60 -- (pixels above the screen's middle)
-- (Our Last hit stays on screen off: they go, as they used to. The Kill word
-- always moves: it's for that spot.)
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
			elseif not (ns.db.combatTextKeepLast or number.kill) then
				Retire(index)
			else
				number.anchor, number.anchorPoint = holder, "CENTER"
				number.baseY = GONE_Y
				number:ClearAllPoints()
				number:SetPoint("CENTER", holder, "CENTER", number.baseX, number.baseY)
				number.plate = false
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
			-- (A quick jump, easing out over JUMP_TIME, then the drift: the game's
			-- leap up from behind the plate, seen at 5 fps on 2026-11-10.)
			local leap = math.min(1, (now - number.start) / JUMP_TIME)
			local eased = 1 - (1 - t) ^ EASE
			local rise = (JUMP * (1 - (1 - leap) ^ 2) + RISE * eased) * (number.riseBy or 1)
			-- (anchor and start height set at Spawn, or LetGo; the rise on top)
			number:SetPoint("CENTER", number.anchor, number.anchorPoint, number.baseX, number.baseY + rise)
			-- A crit's pop: up to POP_PEAK times its size by POP_UP seconds, back
			-- by POP_DOWN (the text scaled, not re-laid: no wobble), then its own
			-- font size again, sharp.
			if number.popping then
				local age = now - number.start
				if age >= POP_DOWN then
					number.popping = nil
					SetSize(number, number.size)
				else
					local k = age < POP_UP and age / POP_UP or 1 - (age - POP_UP) / (POP_DOWN - POP_UP)
					SetHeight(number, number.size * (1 + (POP_PEAK - 1) * k))
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
-- waits up to HOLD for one; a line waits as long for its hit). Lines come
-- only while the log's filtered events are on, which Blizzard turns on and
-- off with its combat log tab: while our numbers are on we keep them on, and
-- turn them back off if we did. No log (a client without it): every hit
-- counts, and in a group only your target's.
--
-- From a recording of two fights (/cine debug combattext, Forever, a druid
-- as caster then bear, 2026-11-11):
-- - A spell's hit and its line come in the same instant, either first.
-- - A swing's line (a hit, a miss, a parry) comes 0.3 to 0.75 s BEFORE its
--   hit on the plate (the plate's hit waits for the swing to land on
--   screen). With HOLD alone every swing was left out: no numbers in bear
--   form. So a line is kept MELEE_HOLD, and a swing takes the oldest kept;
--   anything else only one HOLD fresh.
-- - A hit on you (or a miss) comes with no line at all; held one back for it
--   before, which took the line of a hit of yours landing just after. Your
--   heals on yourself do come with one, so those alone still take theirs.
-- - Maul comes as two hits in one instant with one line: one number, as the
--   game shows.
local HOLD = 0.15
local MELEE_HOLD = 1
local lines, owed, pending = {}, {}, {} -- times of lines; of hits on you; hits waiting
local logListening, logTurnedOn
ns.combatTextWhose = { mine = 0, others = 0 }

local function LogRunning()
	if not logListening or not (C_CombatLog and C_CombatLog.AreFilteredEventsEnabled) then return false end
	local ok, on = pcall(C_CombatLog.AreFilteredEventsEnabled)
	return ok and Plain(on) and on == true
end

-- A hit left out as someone else's: what came around it (hits, lines, hits
-- on you, with their times) goes to /cine log a second later, a few times a
-- session, to see why a hit of yours found no line.
local trace, traceDue, traceDumps = {}, nil, 0
local function Trace(what)
	if ns.combatTextRecord then ns.combatTextRecord(what) end -- (/cine debug combattext: all of it)
	if traceDumps >= 12 then return end
	trace[#trace + 1] = ("%.3f %s"):format(GetTime(), what)
	if #trace > 40 then table.remove(trace, 1) end
end
local function TraceFlush()
	if not traceDue or GetTime() < traceDue then return end
	traceDue, traceDumps = nil, traceDumps + 1
	ns.Log("combattext", ("left out a hit (group %s, log %s): %s"):format(
		tostring(IsInGroup and IsInGroup() or false), tostring(logListening), table.concat(trace, "; ")))
	wipe(trace)
end

-- (Which plate, whether it's your target, a swing (white) or not, a crit.)
local function TraceUnit(unit, color, crit)
	local ok, same = pcall(UnitIsUnit, unit, "target")
	return ("%s%s%s%s"):format(tostring(unit), (ok and Plain(same) and same) and "(target)" or "",
		color[1] == 1 and color[2] == 1 and color[3] == 1 and " white" or "", crit and " crit" or "")
end

local function Fresh(list, now, keep)
	while list[1] and now - list[1] > (keep or HOLD) do table.remove(list, 1) end
end

-- A line waiting for this hit, taken: a swing's is the oldest kept, any
-- other's the newest if it came within HOLD.
local function TakeLine(now, melee)
	Fresh(lines, now, MELEE_HOLD)
	if melee then
		if lines[1] then table.remove(lines, 1) return true end
	elseif lines[1] and now - lines[#lines] <= HOLD then
		table.remove(lines)
		return true
	end
	return false
end

-- Two swings on one plate in one instant are one swing of yours (Maul: the
-- swing for 0 and its own hit, with one line between them): the second goes
-- with the first.
local swingAt, swingPlate
local function Mine(hit)
	if hit.melee then swingAt, swingPlate = hit.at or GetTime(), hit[1] end
	ns.combatTextWhose.mine = ns.combatTextWhose.mine + 1
	Spawn(hit[1], hit[2], hit[3], hit[4], hit[5], nil, hit.kind)
end

-- A hit on a plate: shown now if a line came for it, else held for one.
-- melee: a swing (a physical hit, or a miss, dodge, parry...).
-- kind: which text (Spawn).
local function Claim(plate, unit, amount, color, crit, melee, kind)
	local hit = { plate, unit, amount, color, crit, melee = melee, kind = kind }
	if not LogRunning() then return Spawn(plate, unit, amount, color, crit, nil, kind) end
	local now = GetTime()
	if melee and swingAt == now and swingPlate == plate then
		Trace(("hit %s (swing) goes with the swing before it"):format(TraceUnit(unit, color, crit)))
		return Mine(hit)
	end
	if TakeLine(now, melee) then
		Trace(("hit %s%s took a waiting line"):format(TraceUnit(unit, color, crit), melee and " (swing)" or ""))
		return Mine(hit)
	end
	Trace(("hit %s%s waits"):format(TraceUnit(unit, color, crit), melee and " (swing)" or ""))
	hit.at = now
	pending[#pending + 1] = hit
	ns.WakeFeatureLoop(holder)
end

local function OnLine()
	local now = GetTime()
	Fresh(owed, now)
	if owed[1] then Trace("line for a heal on you") table.remove(owed, 1) return end -- (a heal on you, already here)
	while pending[1] and now - pending[1].at > HOLD do table.remove(pending, 1) end
	if pending[1] then
		Trace("line for a waiting hit")
		local first = table.remove(pending, 1)
		Mine(first)
		while first.melee and pending[1] and pending[1].melee and pending[1].at == first.at
			and pending[1][1] == first[1] do
			Trace("and the swing with it")
			Mine(table.remove(pending, 1))
		end
		return
	end
	Trace("line waits")
	lines[#lines + 1] = now
end

-- A heal on you or your pet: its line isn't for a plate's hit. Heals alone:
-- hits and misses on you come with no line (above).
local ownSeen = {}
local function OnOwnHit(action)
	if not Plain(action) then return end
	if not ownSeen[action] then
		ownSeen[action] = true
		ns.Log("combattext", "first on you: " .. tostring(action))
	end
	if action ~= "HEAL" then return end
	local now = GetTime()
	local took = TakeLine(now, false)
	Trace("heal on you" .. (took and " took a waiting line" or " waits"))
	if not took then owed[#owed + 1] = now end
end

-- Hits held past HOLD with no line: someone else's.
local function DropUnclaimed(now)
	while pending[1] and now - pending[1].at > HOLD do
		table.remove(pending, 1)
		ns.combatTextWhose.others = ns.combatTextWhose.others + 1
		Trace("LEFT OUT")
		traceDue = traceDue or now + 1
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

ns.COMBAT_TEXT_GAME_NUMBERS = GAME_NUMBERS -- (Core.lua lets go at logout)

-- After a setting changes (the page), and every two seconds.
function ns.RefreshCombatTextStyle()
	ns.ApplyCVarSet(GAME_NUMBERS, (PageOn() and ns.db.combatTextHideGame) and true or false)
	KeepLog()
	TraceFlush()
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

-- Only your own hits, always (the player's call, 2026-11-11: no choice of
-- whose). Picked by the combat log (Whose hit, above). A client with no log:
-- solo, every hit is yours; in a group, only your target's.
local function Wanted(unit, enemy)
	if enemy and InGroup() and not LogRunning() then
		local ok, same = pcall(UnitIsUnit, unit, "target")
		return ok and Plain(same) and same
	end
	return true
end

local flagsSeen = {}
local function OnHit(unit, action, flag, amount, school)
	local record = ns.combatTextRecord
	if not On() or not Plain(unit) or not Plain(action) then
		if record then record("plate hit skipped: numbers off, or a secret unit or kind") end
		return
	end
	local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
	local ok, plate = pcall(get or error, unit)
	if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then
		if record then record(("plate hit %s %s skipped: no plate, or locked"):format(unit, action)) end
		return
	end
	local okEnemy, enemy = pcall(UnitCanAttack, "player", unit)
	enemy = okEnemy and Plain(enemy) and enemy
	if not Wanted(unit, enemy) then
		if record then record(("plate hit %s %s skipped: no combat log, in a group, not your target"):format(unit, action)) end
		return
	end
	if record then
		record(("plate hit %s %s enemy=%s: goes on (a WOUND on a friend, a heal on an enemy, or a kind turned"
			.. " off still stops here)"):format(unit, action, tostring(enemy)))
	end
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
			Claim(plate, unit, _G.ABSORB or "Absorb", Color("miss", SPELL), false, nil, "miss")
			return
		end
		local color = Color("spell", SPELL)
		school = Plain(school) and tonumber(school) or 1
		if school == 1 then
			color = Color("hit", WHITE)
		elseif db.combatTextSchoolColors then
			color = SCHOOL[school] or color
		end
		-- (A theme's crit color over the hit's: the game's crits keep theirs.)
		if crit then color = Color("crit", color) end
		Claim(plate, unit, amount, color, crit, school == 1, school == 1 and "swing" or "spell")
	elseif action == "HEAL" then
		if enemy then return end
		Claim(plate, unit, amount, Color("heal", HEAL), crit, nil, "heal")
	elseif MISSES[action] and enemy then
		local word = _G[action]
		if not (type(word) == "string" and Plain(word)) then word = action:sub(1, 1) .. action:sub(2):lower() end
		Claim(plate, unit, word, Color("miss", SPELL), false, true, "miss")
	end
end

-- A kill the game sent no number for (WoW Forever mostly sends only its log
-- lines, recorded 2026-11-18): the word "Kill", in the crit color, as its mob's plate
-- goes. A dead enemy you'd hit in the last few seconds, not someone else's,
-- with no number of ours on it in the last moment (that one moves instead).
local FIGHTING, JUST = 8, 0.6 -- seconds: since our last number on it; a number that was the killing blow
KillWord = function(plate, unit)
	local hit = lastHit[plate]
	lastHit[plate] = nil
	if not (hit and On() and Shows(TEXT_OF.kill)) then return end
	local now = GetTime()
	if now - hit.at > FIGHTING or now - hit.at < JUST then return end
	local okGuid, guid = pcall(UnitGUID, unit)
	if not (okGuid and Plain(guid) and guid == hit.guid) then return end
	local okDead, dead = pcall(UnitIsDead, unit)
	if not (okDead and Plain(dead) and dead) then return end
	local okTap, tapped = pcall(UnitIsTapDenied, unit)
	if okTap and Plain(tapped) and tapped then return end
	-- (A hit's size, no pop: as a crit it read far too big, 2026-11-18.)
	local number = Spawn(plate, nil, ns.L["Kill"], Color("crit", KILL_COLOR), false, nil, "kill")
	if not number then return end
	number.kill = true
	if ns.combatTextRecord then ns.combatTextRecord("KILL with no number: the word shown") end
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
		own:SetScript("OnEvent", ns.Profiled("Combat text own", function(_, _, _, action)
			if On() then OnOwnHit(action) end
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
		if ok and plate then
			KillWord(plate, unit)
			LetGo(plate)
		end
	end
end))

-- /cine debug combattext: how the page stands, in one line.
function ns.CombatTextStateLine()
	local db = ns.db
	local parts = {}
	for _, key in ipairs({ "styleGeneral", "combatTextStyle", "combatTextNumbers", "combatTextHeals",
		"combatTextMisses", "combatTextCritPop", "combatTextSchoolColors", "combatTextFont", "combatTextEdge",
		"combatTextSize", "combatTextHeight", "combatTextHideGame", "hideWorldText" }) do
		parts[#parts + 1] = key .. "=" .. tostring(db[key])
	end
	return ("numbers on=%s page on=%s blocked=%s | log listening=%s running=%s turned on by us=%s | shown as yours"
		.. " %d, left out %d, showing now %d, waiting %d | game numbers off=%s | scale=%s ramp=%s | font=%s | %s")
		:format(tostring(On()), tostring(PageOn()), tostring(ns.combatTextBlocked), tostring(logListening),
		tostring(LogRunning()), tostring(logTurnedOn), ns.combatTextWhose.mine, ns.combatTextWhose.others, #live,
		#pending, tostring(GAME_NUMBERS.active), tostring(CVarNumber("WorldTextScale_v2", 1)),
		tostring(CVarNumber("WorldTextRampDuration_v2", 1)), tostring(GAME_FONT), table.concat(parts, " "))
end

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
-- (a swing's), "crit", "heal", "healcrit" or "miss". layer: the frame to
-- draw it in (Spawn).
function ns.CombatTextSample(frame, kind, layer)
	local db = ns.db
	if kind == "miss" then return Spawn(frame, nil, _G.MISS or "Miss", Color("miss", SPELL), false, layer, "miss") end
	if kind == "heal" then return Spawn(frame, nil, "18", Color("heal", HEAL), false, layer, "heal") end
	if kind == "healcrit" then return Spawn(frame, nil, "37", Color("heal", HEAL), true, layer, "heal") end
	if kind == "kill" then return Spawn(frame, nil, ns.L["Kill"], Color("crit", KILL_COLOR), false, layer, "kill") end
	local color = kind == "white" and Color("hit", WHITE) or (db.combatTextSchoolColors and SCHOOL[8] or Color("spell", SPELL))
	if kind == "crit" then color = Color("crit", color) end
	Spawn(frame, nil, kind == "crit" and "46" or kind == "white" and "11" or "23", color, kind == "crit", layer,
		kind == "white" and "swing" or "spell")
end

-- The page ------------------------------------------------------------------
local L = ns.L

function ns.CreateCombatTextStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Combat Text Style"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["Shows damage and healing numbers of our own in place of the game's."])

	-- An Experimental notice (not a gate: it doesn't stop the page working):
	-- a skull (the raid marker's: on every client) and a red Experimental.
	local skull = content:CreateTexture(nil, "ARTWORK")
	skull:SetSize(20, 20)
	skull:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
	skull:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
	local warnTitle = kit.Label(content, "GameFontNormalLarge", L["Experimental"])
	warnTitle:SetPoint("LEFT", skull, "RIGHT", 6, 0)
	warnTitle:SetTextColor(1, 0.25, 0.2)
	local warnText = kit.Label(content, "GameFontHighlightSmall", L["This page is experimental: our numbers may " ..
		"not show for every hit or heal, may not look quite like the game's everywhere, and may change in " ..
		"later versions. If something looks wrong, turn the page off to get the game's own numbers back."])
	warnText:SetPoint("TOPLEFT", skull, "BOTTOMLEFT", 0, -6)
	warnText:SetWidth(520)
	warnText:SetJustifyH("LEFT")

	local function Changed() ns.RefreshCombatTextStyle() end
	local switch = kit.PageSwitch(content, "combatTextStyle", L["Enable Page"],
		L["Turns this page's combat text on or off."], warnText, Changed)
	local stack = kit.Stack(switch, "check")
	local rows = ns.StyleRows(kit, content, stack, Changed, "combatTextStyle")
	local function Ours(db) return rows.On(db) and db.combatTextNumbers end

	-- The preview: a nameplate as yours look (the Nameplate Style page's own
	-- preview: your bar, border, name font and cast bar, over the lake or
	-- dark, a unit to pick under it), and Test, which plays a hit, a swing, a
	-- crit, two landing together and a miss on it with this page's look; heals
	-- on a friendly or your own plate.
	local preview, plate
	if ns.MakePlateRowLookPreview then
		preview = ns.MakePlateRowLookPreview(content, 480, "others")
		preview:SetHeight(170) -- (room over the plate for the numbers' climb)
		plate = preview.plate
		plate:ClearAllPoints()
		plate:SetPoint("BOTTOM", preview, "BOTTOM", 0, 44 / 1.6) -- (its scale: over the picks and its cast bar)
	else
		preview = CreateFrame("Frame", nil, content)
		preview:SetSize(480, 150)
		local back = preview:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0.05, 0.06, 0.08, 0.9)
		plate = CreateFrame("Frame", nil, preview)
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
		preview.Refresh = function() end
	end
	stack:Add(preview, "label")
	kit.AddControl(preview)
	-- (The numbers drawn in the page, over the preview (and past its top:
	-- not in it, which clips), not in the world's frames under the window.)
	local layer = CreateFrame("Frame", nil, content)
	layer:SetAllPoints(preview)
	layer:SetFrameLevel(preview:GetFrameLevel() + 30)
	layer.layoutSkip = true -- (the sweep's layout check: its numbers fly over the page, not laid out)
	-- (round: a stopped round's steps still waiting don't play. focus: the
	-- text whose tab is picked, played alone: its sample's name.)
	local round, focus = 0, nil
	local SAMPLE_OF = { spell = "hit", swing = "white", crit = "crit", heal = "heal", miss = "miss", kill = "kill" }
	local function Play()
		local kind = preview.SampleKind and preview.SampleKind()
		local steps = { { 0, "hit" }, { 0.5, "white" }, { 1.0, "crit" }, { 1.8, "hit" }, { 1.85, "white" },
			{ 2.6, "miss" }, { 3.2, "kill" } }
		if focus then
			steps = { { 0, focus }, { 0.8, focus }, { 1.6, focus }, { 1.65, focus } }
		elseif kind == "Friendly" or kind == "Player" then
			steps = { { 0, "heal" }, { 0.6, "heal" }, { 1.2, "healcrit" }, { 2.0, "heal" }, { 2.05, "heal" } }
		end
		local this = round
		for _, step in ipairs(steps) do
			C_Timer.After(step[1], function()
				if this == round and preview:IsVisible() then ns.CombatTextSample(plate, step[2], layer) end
			end)
		end
	end
	-- They play again and again while the page shows (a round every few
	-- seconds), so a change to the look shows at once; Test turns into Stop
	-- while they do. Opening the page starts them again.
	local looping, ticker, test
	local function SetLooping(on)
		looping = on
		round = round + 1
		if ticker then ticker:Cancel() ticker = nil end
		if test then test:SetText(on and L["Stop"] or L["Test"]) end
		if on and preview:IsVisible() then
			Play()
			ticker = C_Timer.NewTicker(4, function()
				if looping and preview:IsVisible() then Play() end
			end)
		end
	end
	test = ns.StylePreviewTest(preview, kit, L["Plays sample hits on the nameplate over and over."],
		function() SetLooping(not looping) end)
	preview:HookScript("OnShow", function() SetLooping(true) end)
	preview:HookScript("OnHide", function()
		if ticker then ticker:Cancel() ticker = nil end
		round = round + 1
	end)

	-- Tabs (Options.lua's ns.PageTabsBelow), each a container (right-click
	-- off: all on it off): General, Look, then a tab per text (ns.COMBAT_TEXTS)
	-- with whether it shows, its color, size, place, climb and time. Picking
	-- a text's tab plays that text alone on the preview.
	local tabList = {
		{ L["General"], L["Whose numbers show, and the game's own floating text."] },
		{ L["Look"], L["The numbers' font, size, edge and Y offset."] },
		{ L["Spells"], L["Your spells' hits."] },
		{ L["Swings"], L["Your melee and other physical hits."] },
		{ L["Crits"], L["Your crits: how big, and where."] },
		{ L["Heals"], L["Your heals on friendly nameplates."] },
		{ L["Misses"], L["Miss, Dodge, Parry and the like."] },
		{ L["Kill"], L["The Kill word on a mob you killed."] },
	}
	local hosts, _, TabsShown = ns.PageTabsBelow(content, preview, tabList, "Combat Text Style/page", nil, nil, nil,
		function(i)
			local text = ns.COMBAT_TEXTS[i - 2]
			local was = focus
			focus = text and SAMPLE_OF[text.kind] or nil
			if focus ~= was and looping then SetLooping(true) end
		end)
	-- (What's made on the page from here on goes onto a tab, its heading at the tab's top.)
	local made = {}
	local function Mark()
		for _, object in ipairs({ content:GetChildren() }) do made[object] = true end
		for _, object in ipairs({ content:GetRegions() }) do made[object] = true end
	end
	local function Into(i, header)
		for _, set in ipairs({ { content:GetChildren() }, { content:GetRegions() } }) do
			for _, object in ipairs(set) do
				if not made[object] then
					made[object] = true
					object:SetParent(hosts[i])
				end
			end
		end
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", hosts[i], "TOPLEFT", 0, 0)
	end
	Mark()

	-- General: our numbers on or off, whose, and the game's own text.
	local general = stack:Header(content, L["Our numbers"])
	rows.Check("combatTextNumbers", L["Show your damage and healing over nameplates"],
		L["Shows your own damage and healing numbers over nameplates."])
	rows.Check("combatTextKeepLast", L["Last hit stays on screen"],
		L["A dying mob's last number finishes above the middle of the screen."], Ours)
	rows.Check("combatTextSchoolColors", L["Spells in their school's color"],
		L["Colors spell numbers by their school, like fire orange."],
		Ours)

	stack:Header(content, L["The game's floating text"])
	rows.Check("combatTextHideGame", L["Turn off the game's damage and healing numbers"],
		L["Turns off the game's damage and healing numbers while this page is on."])
	local allLabel = L["Hide all the game's floating text, XP too"]
	local all = rows.Check("hideWorldText", allLabel,
		L["Hides all the game's floating text, XP too; needs a full game restart."])
	-- (Its label adds a reminder while the tick isn't what the game draws yet.)
	local function RestartPending()
		local db = ns.db or {}
		local wanted = db.hideWorldText and db.combatTextStyle and db.styleGeneral ~= false and true or false
		local live = db.worldTextLive
		if live == nil then live = ns.blankWorldFont ~= nil end
		return wanted ~= live
	end
	local allRefresh = all.Refresh
	all.Refresh = function(self, ...)
		if allRefresh then allRefresh(self, ...) end
		local text = self.Text or self.text
		if text then
			text:SetText(RestartPending()
				and allLabel .. " |cffff8040" .. L["(restart the game to apply)"] .. "|r" or allLabel)
		end
	end
	-- (The restart warning only when it takes one: back to what the game
	-- draws already, it closes any warning still up instead.)
	all:HookScript("OnClick", function(self)
		self:Refresh()
		if RestartPending() then
			StaticPopup_Show("CINEMATIC_WORLD_TEXT_RESTART")
		else
			StaticPopup_Hide("CINEMATIC_WORLD_TEXT_RESTART")
		end
	end)

	Into(1, general)

	-- The numbers' look, on the page itself (the Style pages' template,
	-- StylePages.lua's rows.Look, inline): their font, size, edge and height.
	local lookHeader = stack:Header(content, L["Look"])
	rows.Look("", L["Our numbers"], {
		inline = true,
		tabs = { default = function(key) return ns.DEFAULTS[key] end, source = ns.PageLookSource,
			copyKind = "combatTextLook", copyName = L["Our numbers"] },
		font = { "combatTextFont", L["The font for the numbers."],
			test = Ours }, -- (its list starts with The game's: "game")
		textSize = function(look)
			look.Slider("combatTextSize", L["Size"], 50, 200, 5, "%d%%", 100,
				L["How big the numbers are, next to the game's."], Ours)
			look.Slider("combatTextHeight", L["Y offset"], -40, 80, 2, "%d px", nil,
				L["Moves the numbers up or down."], Ours)
		end,
		shadow = function(look)
			look.Choices(L["Edge:"], "combatTextEdge", {
				{ "game", L["The game's"], L["A dark shadow up and to the right, no edge."] },
				{ "both", L["Edge and shadow"], L["A dark edge and the drop shadow."] },
				{ "edge", L["Dark edge"] },
				{ "none", L["None"] },
			}, Ours)
		end,
		textColor = false, outline = false, outlineColor = false, -- (their colors: by school; the edge, above)
	})

	Into(2, lookHeader)

	-- A text's tab: whether it shows (extra: rows of its own under it), a
	-- color of its own, and its size, place, climb and time on screen.
	local function TextTab(i, text, label, tip, extra)
		local key = "combatText" .. text.name
		local header = stack:Header(content, tabList[i][1])
		rows.Check(text.show, label, tip, Ours)
		local function Shown(db) return Ours(db) and db[text.show] ~= false end
		if extra then extra(Shown) end
		local own = rows.Check(key .. "Own", L["Color of its own"], L["Draws it in the color beside it."], Shown)
		rows.Swatch(own, nil, { key .. "R", key .. "G", key .. "B" }, L["Its color."],
			function(db) return Shown(db) and db[key .. "Own"] end)
		rows.Slider(key .. "Size", L["Size"], 50, 300, 5, "%d%%", 100, L["How big it is, next to the Look tab's size."],
			Shown)
		rows.Slider(key .. "Y", L["Y offset"], -80, 120, 2, "%d px", nil, L["Moves it up or down."], Shown)
		rows.Slider(key .. "X", L["X offset"], -150, 150, 2, "%d px", nil, L["Moves it left or right."], Shown)
		rows.Slider(key .. "Rise", L["Climb"], 0, 300, 10, "%d%%", 100, L["How far it rises, next to its usual."], Shown)
		rows.Slider(key .. "Life", L["Time on screen"], 30, 300, 10, "%d%%", 100,
			L["How long it stays, next to its usual."], Shown)
		Into(i, header)
	end
	local TEXT = {}
	for _, text in ipairs(ns.COMBAT_TEXTS) do TEXT[text.kind] = text end
	TextTab(3, TEXT.spell, L["Spell hits"], L["Your spells' damage, in yellow."])
	TextTab(4, TEXT.swing, L["Swings"], L["Your melee and other physical hits, in white."])
	TextTab(5, TEXT.crit, L["Show crits as crits"], L["Off: a crit looks like a plain hit."], function(Shown)
		rows.Check("combatTextCritPop", L["Crits pop"],
			L["A crit grows big for a moment, then settles."], Shown)
		rows.Choices(L["Where:"], "combatTextCritSpot", {
			{ "plate", L["Over the bar"], L["Low over the health bar, as the game's."] },
			{ "above", L["Above, like hits"], L["Where hits start, rising as they do."] },
		}, Shown)
	end)
	TextTab(6, TEXT.heal, L["Your heals on friends"], L["Heals on friendly nameplates, in green."])
	TextTab(7, TEXT.miss, L["Misses"], L["Miss, Dodge, Parry, Immune and the like, in the game's words."])
	TextTab(8, TEXT.kill, L["Kill"], L["Shows Kill when the game sends no number for the killing blow."])

	canvas:SetScript("OnShow", kit.PageShown(function()
		kit.Refresh()
		TabsShown()
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Combat Text Style", L["Combat Text Style"])
end
