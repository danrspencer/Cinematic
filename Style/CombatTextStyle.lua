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
DEFAULTS.combatTextDamageBy = "ours"  -- who draws your damage: "ours", "game" (the game's own) or "none"
DEFAULTS.combatTextHealBy = "ours"    -- who draws your heals
DEFAULTS.combatTextPetBy = "ours"     -- who draws your pet's damage
DEFAULTS.combatTextFont = "game"      -- "game": the game's floating text font; else a Style font
DEFAULTS.combatTextEdge = "game"      -- "game" (a drop shadow, as the game's), "both" (an edge too), "edge", "none"
DEFAULTS.combatTextSize = 1           -- times the game's size (All texts' Size)
DEFAULTS.combatTextKeepLast = true    -- a dying mob's last numbers finish above the screen's middle (LetGo)
-- (Every text's own settings: CombatTextTexts.lua, ns.CombatTexts.)

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
local CRIT_SIZE = 1.3       -- a crit once settled, times a hit (the texts' Crit size; a crit's climb and time: the tree's)
local START_Y = -36         -- from the plate's top down to its name (a hit's bottom)
local RISE = 40             -- pixels a number drifts up over its life, after its jump
local JUMP, JUMP_TIME = 40, 0.2 -- and the quick jump up it starts with (the game's, at mid range: it leaps, then drifts)
local CRIT_DROP = -36       -- a crit's middle, below a hit's
local POP_PEAK, POP_UP, POP_DOWN = 2.5, 0.13, 0.25 -- the pop: times its size, seconds to grow, seconds till back
local TOGETHER = 0.25       -- seconds: hits this close in time spread sideways
local SPREAD = 1.3          -- a slot's width, times the text size (about two digits)
local EASE = 1.3            -- the climb's slowing: 1 = steady (the game's is close to it)
local LIFE = 1.2            -- seconds, at the game's WorldTextRampDuration_v2 1
local FADE_FROM = 0.6       -- of its life, when it starts fading
local MAX_LIVE = 40         -- numbers showing at once; the oldest goes first
local ARC = 60              -- pixels an arcing number drifts sideways over its life

local CT = ns.CombatTexts
local Value = CT.Value
local NODE = CT.NODE

-- A hit that partly landed: its flag's tag (All texts' Tag).
local TAGS = { GLANCING = "Glancing", CRUSHING = "Crushing", BLOCK_REDUCED = "Blocked",
	RESIST_REDUCED = "Resisted", ABSORB_REDUCED = "Absorbed" }

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
		-- (A partly landed hit's tag, "(Glancing)", after the words: anchored
		-- to their right edge, never measured (an amount is secret).)
		number.tag = number.body:CreateFontString(nil, "OVERLAY")
		number.tag:SetPoint("LEFT", number.text, "RIGHT", 4, 0)
		number.tag:SetShadowOffset(1, -1)
		number.tag:SetShadowColor(0, 0, 0, 1)
	end
	return number
end

local function Retire(index)
	local number = table.remove(live, index)
	number:Hide()
	number:ClearAllPoints()
	number.plate, number.unit, number.anchor, number.popping = nil, nil, nil, nil
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
	local font = CT.Get(number.id or "all", "Font", number.via)
	local file = font and font ~= "game" and ns.StyleFontFile(font) or GAME_FONT
	local text = number.text
	if not text:SetFont(file, size, "") then
		file = "Fonts\\FRIZQT__.TTF"
		text:SetFont(file, size, "")
	end
	text:SetShadowOffset(0, 0)
	local look = CT.Get(number.id or "all", "Edge", number.via) or "game"
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
	if number.tag then number.tag:SetFont(file, math.max(8, size * 0.5), "") end
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

-- Make room (2026-11-19, the player's design): the biggest hits in the
-- middle, the rest moved aside out of their way. Each number has a rank:
-- 1 a crit, 2 a hit of something you cast or pressed (a spell or heal with
-- a cast of yours, an ability), 3 the rest (swings, DoT ticks, procs,
-- Thorns: no cast waiting for them), 4 a miss. A new one takes the free spot
-- nearest its middle among the numbers ranked over it (and, ranked 3 or 4,
-- its own rank's: those sit side by side); then any in its way ranked under
-- it (and, a crit or a cast's, its own rank's older ones) slide aside, over
-- SLIDE, each one moved pushing on any in its own way. Overlap is where each
-- is now: one that's climbed above a new one isn't in its way. Widths are
-- guessed (an amount in a fight is secret): about three digits.
local SLIDE = 0.15
local ROOM_SPREAD = 1.7
local function Rank(node, cast)
	if node.pet then return 3 end -- (your pet's, crits too: never in the way of yours)
	if node.crit then return 1 end
	if node.word then return 4 end
	if cast ~= nil or node.id == "ability" then return 2 end
	return 3
end
local function BoxW(number) return number.boxW or number.width or (number.size or BASE_SIZE) * ROOM_SPREAD end
local function RankOf(number) return number.rank or 3 end
local function Overlap(a, ax, ay, b)
	return math.abs(ax - b.baseX) < (BoxW(a) + BoxW(b)) / 2 + GAP
		and math.abs(ay - (b.curY or b.baseY)) < ((a.size or BASE_SIZE) + (b.size or BASE_SIZE)) * 0.45
end
local function SlideTo(number, x, now)
	number.slideFrom = number.shownX or number.baseX
	number.slideAt = now
	number.baseX = x
end
local roomSide = 1
local function RoomX(plate, number, y, home, now)
	local rank = number.rank
	local others = {}
	for _, other in ipairs(live) do
		if other.plate == plate and other ~= number then others[#others + 1] = other end
	end
	local function Blocks(other) return RankOf(other) < rank or (rank >= 3 and RankOf(other) == rank) end
	local function Free(x)
		for _, other in ipairs(others) do
			if Blocks(other) and Overlap(number, x, y, other) then return false end
		end
		return true
	end
	-- (Its middle first, then just past each one in its way, either side.)
	local spots = { home }
	for _, other in ipairs(others) do
		if Blocks(other) then
			local apart = (BoxW(number) + BoxW(other)) / 2 + GAP + 0.5
			spots[#spots + 1] = other.baseX + apart
			spots[#spots + 1] = other.baseX - apart
		end
	end
	roomSide = -roomSide
	local best
	for _, x in ipairs(spots) do
		if Free(x) then
			local off, was = math.abs(x - home), best and math.abs(best - home)
			if not best or off < was - 0.5 or (math.abs(off - was) <= 0.5 and (x - home) * roomSide > 0) then best = x end
		end
	end
	best = best or home
	-- (Then the rest out of its way, and on from each one moved.)
	local queue, moved, steps = { { number, best, y } }, {}, 0
	while queue[1] and steps < 16 do
		steps = steps + 1
		local mover, mx, my = unpack(table.remove(queue, 1))
		local mRank = RankOf(mover)
		for _, other in ipairs(others) do
			local oRank = RankOf(other)
			local pushed = oRank > mRank or (oRank == mRank and (mover ~= number or mRank <= 2))
			if other ~= mover and not moved[other] and pushed and Overlap(mover, mx, my, other) then
				local side = other.baseX > mx and 1 or other.baseX < mx and -1 or roomSide
				local x = mx + side * ((BoxW(mover) + BoxW(other)) / 2 + GAP + 0.5)
				SlideTo(other, x, now)
				moved[other] = true
				queue[#queue + 1] = { other, x, other.curY or other.baseY }
			end
		end
	end
	return best
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


-- One number over a plate. id: which text it is (CombatTextTexts.lua: "swing",
-- "spellFire", "spellCrit", "missDodge"...), its settings its own or its
-- group's; via: the hit a crit crits or a miss missed with ("spellFire",
-- "swing"), whose look a crit takes where its own isn't set, and whose color
-- a miss takes. A text turned off shows nothing. layer: a frame to draw it
-- in instead of the world's (a preview's: the options window is over the
-- world's frames), at the world's size. tag: a partly landed hit's flag
-- ("GLANCING"). color: in place of the text's. Gives the number, or nil.
local fanSide = 1
local function Spawn(plate, unit, amount, id, via, layer, tag, color, cast)
	local node = NODE[id]
	if not node or not CT.Shows(id, via, layer) then return end
	local crit = node.crit and true or false
	color = color or CT.Color(id, via)
	if #live >= MAX_LIVE then Retire(1) end
	local now = GetTime()
	local number = NewNumber(layer)
	number.id, number.via = id, via
	local function Get(setting) return CT.Get(id, setting, via) end
	-- (cast: how long its spell's cast took, in seconds, if known. Each second
	-- of it makes the number CastSize bigger and CastTime longer, up to
	-- CAST_MAX. Not known, or instant: as it is, 100%.)
	local function Grown(setting)
		local per = tonumber((Get(setting))) or 0
		if not (type(cast) == "number" and cast > 0 and per > 0) then return 1 end
		return math.min(CT.CAST_MAX or 1.5, 1 + per * cast)
	end
	local size = BASE_SIZE * CVarNumber("WorldTextScale_v2", 1) * (Get("Size") or 1) * Grown("CastSize")
	-- (its middle where a hit's bottom starts, half a hit above; one set to
	-- start over the bar (a crit, as the game's) lower)
	local onBar = Get("Start") == "bar"
	local y = START_Y + (Get("Y") or 0) + size / 2 + (onBar and CRIT_DROP or 0)
	if crit then size = size * (Get("CritScale") or CRIT_SIZE) end
	local text = number.text
	SetSize(number, size)
	text:SetTextColor(color[1], color[2], color[3])
	SetWords(number, amount)
	-- (Its tag, All texts' Tag on: the flag's word, in its color.)
	local tagWord = tag and TAGS[tag] and Value(CT.Key("all", "Tags")) and ns.L[TAGS[tag]]
	number.tag:SetText(tagWord and ("(" .. tagWord .. ")") or "")
	number.tag:SetTextColor(color[1], color[2], color[3])
	number.tag:SetShown(tagWord and true or false)
	-- A hit of 0 (Maul comes as two hits in one instant: the swing it took the
	-- place of, for 0, and its own) showed as a white "0". The amount is secret
	-- in a fight, so it can't be checked; but it can be the words' alpha: 0
	-- draws nothing, 1 and up draws in full.
	number.body:SetAlpha(1)
	number.zeroHide = nil
	if not Plain(amount) then number.zeroHide = pcall(number.body.SetAlpha, number.body, amount) end
	local ok, width = pcall(text.GetStringWidth, text)
	number.width = ok and type(width) == "number" and Plain(width) and width > 0 and width or nil
	-- (Its rank and room, for Make room: kept whichever way, so a change of
	-- it while numbers show still finds them.)
	number.size, number.rank = size, Rank(node, cast)
	number.boxW = number.width or size * ROOM_SPREAD
	number.curY, number.slideAt, number.shownX = y, nil, nil
	-- (Hits landing together: side by side (the game's), stacked up, on top,
	-- or making room, the biggest in the middle.)
	local together = Value(CT.Key("all", "Together"))
	local x = 0
	if together == "room" then
		x = RoomX(plate, number, y, Get("X") or 0, now) - (Get("X") or 0)
	elseif together == "stack" then
		local count = 0
		for _, other in ipairs(live) do
			if other.plate == plate and now - other.start < TOGETHER then count = count + 1 end
		end
		y = y + count * size * 0.8
	elseif together ~= "top" then
		x = SlotX(plate, now, Width(number, size))
	end
	x = x + (Get("X") or 0)
	if layer then
		number.onLayer = true
		number:SetParent(layer)
		number:SetScale(holder:GetEffectiveScale() / layer:GetEffectiveScale() * (layer.zoom or 1)) -- (zoom: a popped preview's)
		number:SetFrameStrata(layer:GetFrameStrata())
		number:SetFrameLevel(math.min(layer:GetFrameLevel() + 1, 9000))
	else
		number:SetFrameStrata(plate:GetFrameStrata())
		number:SetFrameLevel(math.min(plate:GetFrameLevel() + 20, 9000))
	end
	number.plate, number.unit, number.crit, number.size = plate, unit, crit, size
	number.popping = Get("Pop") and text.SetTextHeight and true or nil
	-- (How it moves: up (the game's), down, an arc either way, fanned out (each
	-- one the other way from the last), or staying put.)
	local move = Get("Move") or "up"
	number.move = move
	if move == "fan" then
		fanSide = -fanSide
		number.side = fanSide
	else
		number.side = move == "arcleft" and -1 or 1
	end
	number.riseBy = math.max(0, Get("Climb") or 1)
	number.fadeFrom = math.min(0.95, math.max(0.05, Get("Fade") or FADE_FROM))
	number.start = now
	number.life = LIFE * math.max(0.3, CVarNumber("WorldTextRampDuration_v2", 1)) * math.max(0.1, Get("Time") or 1)
		* Grown("CastTime")
	number.lift = y
	number.anchor, number.anchorPoint, number.baseX, number.baseY = plate, "TOP", x, y
	number:ClearAllPoints()
	number:SetPoint("CENTER", plate, "TOP", x, y)
	number:SetAlpha(1)
	number:Show()
	live[#live + 1] = number
	ns.WakeFeatureLoop(holder)
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
-- (Our Last hit stays on screen off: they go, as they used to. The Kill
-- text, which went there too, is gone since 2026-11-18: the player's call.)
local GONE_WAIT = 0.06 -- (seconds a gone plate's numbers wait for it back: a fight's start, the same instant)
local goneWait = {}  -- [plate] = { guid, at }: gone, its numbers waiting
local function LetGo(plate)
	local x, y
	for index = #live, 1, -1 do
		local number = live[index]
		if number.plate == plate then
			if x == nil then x, y = PlateSpot(plate) end
			number.slideAt, number.shownX = nil, nil -- (a slide aside stops where it's headed)
			if x then
				number.anchor, number.anchorPoint = holder, "BOTTOMLEFT"
				number.baseX, number.baseY = x + number.baseX, y + number.lift
				number:ClearAllPoints()
				number:SetPoint("CENTER", holder, "BOTTOMLEFT", number.baseX, number.baseY)
				number.plate = false
			elseif not ns.db.combatTextKeepLast then
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
			-- (Down: the same, falling; an arc or a fan: drifting sideways as it
			-- climbs, more as it goes; staying: no move at all.)
			local move, dx = number.move, 0
			if move == "down" then
				rise = -rise
			elseif move == "stay" then
				rise = 0
			elseif move == "arcleft" or move == "arcright" or move == "fan" then
				dx = (number.side or 1) * ARC * eased * eased * (number.riseBy or 1)
			end
			-- (Sliding aside, Make room: from where it was to its new spot, easing.)
			local x = number.baseX
			if number.slideAt then
				local k = (now - number.slideAt) / SLIDE
				if k >= 1 then
					number.slideAt = nil
				else
					x = number.slideFrom + (number.baseX - number.slideFrom) * (1 - (1 - k) ^ 2)
				end
			end
			number.shownX, number.curY = x, number.baseY + rise
			-- (anchor and start height set at Spawn, or LetGo; the move on top)
			number:SetPoint("CENTER", number.anchor, number.anchorPoint, x + dx, number.baseY + rise)
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
			local fade = number.fadeFrom or FADE_FROM
			number:SetAlpha(t > fade and (1 - t) / (1 - fade) or 1)
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
-- (Whether a line has come at all this session. On retail (12.0.5, 2026-11-19)
-- none ever came though the log said it was on: every hit waited for one and
-- was left out, no numbers at all. Till one comes, it's as with no log.)
local logLines = false
ns.combatTextWhose = { mine = 0, others = 0 }

-- (Retail says its log is restricted (C_CombatLog.IsCombatLogRestricted, true
-- in and out of fights, 2026-11-19), and a stray line still comes now and
-- then: one did, and from then on every hit waited for lines that didn't
-- come, no numbers again. So on retail a restricted log is no log. Retail
-- only till Forever's answer is known: lines do come there.)
local function Restricted()
	if not ns.isRetail then return false end
	local IsRestricted = ns.Check.Api("C_CombatLog.IsCombatLogRestricted")
	return IsRestricted ~= nil and ns.Check.True(IsRestricted())
end

local function LogRunning()
	if not logListening or not logLines or Restricted() then return false end
	if not (C_CombatLog and C_CombatLog.AreFilteredEventsEnabled) then return false end
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
local TakeCast, PeekCast -- (below: the cast a spell's hit came from; whether one waits)

-- In a group or raid (2026-11-19): others' hits in your own schools (five
-- frost mages on one boss) land in the instants of yours, and the first
-- took your line: their number shown, yours left out. So there a spell hit
-- or heal waits HOLD with the others, and each line goes to the likeliest
-- near it: a cast of yours waiting for it (CAST), on the mob you cast at
-- (TARGET), a mob your hits in its school landed on lately (MARK: your DoT,
-- Ignite, a seal, a poison), else any (a line nobody likelier wanted).
-- Still can't tell: someone's tick in your school, on a mob you're ticking,
-- in the instant of yours. Swings there: only your target's.
local group = {
	CAST = 4, MARK = 2, TARGET = 1,
	MARK_KEEP = 20, -- seconds a mob stays marked by your hits in a school
	SAME = 0.05,    -- seconds that count as one instant
	CAP = 30,       -- hits waiting at most (a raid's pull: the oldest go)
	pending = {}, marks = {}, markCount = 0,
	swung = {}, -- [plate] = when your last swing on it landed (Off-class: weapon procs)
}
function group.On()
	return ((IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid())) and true or false
end
function group.Key(hit)
	return hit.guid and hit.school and (hit.guid .. ":" .. hit.school) or nil
end
function group.Mark(hit, now)
	local key = group.Key(hit)
	if not key then return end
	if not group.marks[key] then group.markCount = group.markCount + 1 end
	group.marks[key] = now
	if group.markCount > 200 then
		for each, at in pairs(group.marks) do
			if now - at > group.MARK_KEEP then group.marks[each], group.markCount = nil, group.markCount - 1 end
		end
	end
end

-- Whether a waiting hit's plate is still its mob's: the game hands a dead
-- mob's plate to another, and a number held for its line (In a group:
-- 0.3 s) went on the new one. Gone (no mob on it now): as before.
local function StillThere(hit)
	if not hit.guid or not hit[2] then return true end
	local ok, now = pcall(UnitGUID, hit[2])
	if not ok or not Plain(now) or now == nil then return true end
	return now == hit.guid
end

local function Mine(hit)
	if hit.melee then swingAt, swingPlate = hit.at or GetTime(), hit[1] end
	ns.combatTextWhose.mine = ns.combatTextWhose.mine + 1
	-- (Your swing on this plate: an off-class weapon proc on it is yours.)
	if hit.melee and (hit.via == "swing" or hit.via == "swingGlance") and hit[1] then
		group.swung[hit[1]] = hit.at or GetTime()
	end
	if not StillThere(hit) then
		if ns.combatTextRecord then Trace("yours, but its plate went to another mob while it waited: left out") end
		return
	end
	if hit.school then group.Mark(hit, hit.at or GetTime()) end
	local cast = hit.school and TakeCast(hit.school, hit.at or GetTime())
	Spawn(hit[1], hit[2], hit[3], hit.id, hit.via, nil, hit.tag, nil, cast)
end

-- A hit on a plate: shown now if a line came for it, else held for one.
-- melee: a swing (a physical hit, or a miss, dodge, parry...). id, via,
-- tag: which text (Spawn). school: a spell's or heal's, to find its cast by
-- (TakeCast); nil for one that never has one (a swing, a miss).
-- (A hit drawn late, its plate back a moment on (TargetHit): matched to the
-- log as of when it landed, so the wait doesn't leave it out.)
local claimAt

-- Damage shields (2026-11-19): a frost mage's Blizzard in a dungeon showed a
-- steady "19" in Nature or Holy, a groupmate's Thorns or Retribution Aura on
-- the tank, landing in the instant of a Blizzard tick and taking its line.
-- The game never says which spell hit, only its school, so: a spell hit in a
-- school your class can't deal ("off-class") counts only when (1) a hit on
-- you landed with it (a damage shield answers a swing at its wearer, a
-- cleave's too, and the log credits the wearer), and (2) a line came for it
-- that none of your own schools' hits took: it waits HOLD, so they go first.
-- Several at once: no more than the hits on you, mobs targeting you first.
-- Your wand's shots (Shoot) are yours in any school; so is a weapon proc (a
-- hit on the mob your swing just landed on, with its own line in its
-- instant: Fiery Weapon on a warrior). No log: (1) alone.
local off = {
	-- Schools each class deals (bits: 2 Holy, 4 Fire, 8 Nature, 16 Frost, 32
	-- Shadow, 64 Arcane; Physical isn't checked). A class not here: all.
	CLASS = {
		WARRIOR = 0, ROGUE = 8, HUNTER = 4 + 8 + 64, PALADIN = 2, PRIEST = 2 + 32, SHAMAN = 4 + 8 + 16,
		MAGE = 4 + 16 + 64, WARLOCK = 4 + 32, DRUID = 8 + 64, DEATHKNIGHT = 16 + 32, MONK = 8,
		DEMONHUNTER = 4 + 32 + 64 + 2 + 8 + 16, EVOKER = 4 + 8 + 16 + 64,
	},
	WINDOW = 0.8,  -- seconds between a hit on you and its shield's hit, either way (untested: the recorder logs the gap)
	pending = {},  -- off-class hits waiting HOLD
	youHit = {},   -- times of hits on you, each good for one shield hit
	wand = {},     -- times of your wand's shots, each good for one hit
}
-- Whether your class can deal this school (a mixed school: any part of it).
function off.Fits(school)
	if not school or school == 1 then return true end
	if off.mask == nil then
		local ok, _, class = pcall(UnitClass, "player")
		off.mask = ok and Plain(class) and off.CLASS[class] or false
	end
	if not off.mask then return true end
	-- (Retail, no log to say whose: all of a mixed school must be your class's.
	-- A druid's Astral (Arcane + Nature) shared Nature with a shaman and showed
	-- as his, 2026-11-19. Forever, with lines: any part, as before.)
	if ns.isRetail then return bit.band(school, bit.bnot(off.mask)) == 0 end
	return bit.band(school, off.mask) ~= 0
end

-- Retail, no log (2026-11-19, /cine debug whosehit): the game's damage meter
-- updates as you deal damage or heal (your casts, your DoT ticks) and never
-- for strangers' hits (none in 25 s of them, standing still), but not once
-- per hit. So it says whether you're fighting at all: with no update in the
-- last FOR seconds, a hit isn't yours. (A hit and its update can come in the
-- same frame either way round: a hit that finds none looks again next frame.)
local meter = { FOR = 2, at = nil, frame = CreateFrame("Frame") }
if ns.isRetail and ns.Check.RegisterEvent(meter.frame, "DAMAGE_METER_COMBAT_SESSION_UPDATED") then
	meter.listening = true
	meter.frame:SetScript("OnEvent", function() meter.at = GetTime() end)
end
function meter.Fighting(now)
	if not meter.listening then return true end
	return meter.at ~= nil and now - meter.at <= meter.FOR
end

local function Claim(plate, unit, amount, id, via, melee, tag, school)
	local hit = { plate, unit, amount, melee = melee, id = id, via = via, tag = tag, school = school }
	-- (Your target as it landed: a pet's hit is checked a moment on, and a
	-- target switched just after it (seen 2026-11-19) left an imp's out.)
	local okTarget, onTarget = pcall(UnitIsUnit, unit, "target")
	hit.onTarget = okTarget and Plain(onTarget) and onTarget and true or nil
	-- (Its mob, for StillThere and In a group's marks.)
	local okGuid, guid = pcall(UnitGUID, unit)
	hit.guid = okGuid and Plain(guid) and guid or nil
	-- (Off-class, a damage's: waits for the hits on you and your own lines.)
	if school and not melee and CT.Kind(id) ~= "heal" and not off.Fits(school) then
		local now = claimAt or GetTime()
		local okYou, onYou = pcall(UnitIsUnit, unit .. "target", "player")
		hit.at, hit.onYou = now, okYou and Plain(onYou) and onYou and true or nil
		if ns.combatTextRecord then
			Trace(("hit %s school %d off-class (on you: %s) waits"):format(tostring(unit), school, tostring(hit.onYou)))
		end
		if #off.pending >= group.CAP then
			table.remove(off.pending, 1)
			ns.combatTextWhose.others = ns.combatTextWhose.others + 1
		end
		off.pending[#off.pending + 1] = hit
		ns.WakeFeatureLoop(holder)
		return
	end
	local crit = NODE[id] and NODE[id].crit
	local color = { 1, 1, 1 } -- (for the trace's "white" only)
	if id ~= "swing" and id ~= "swingCrit" and id ~= "swingGlance" then color = CT.SPELL end
	if not LogRunning() then
		local function Show()
			local cast = school and TakeCast(school, GetTime())
			return Spawn(plate, unit, amount, id, via, nil, tag, nil, cast)
		end
		local now = claimAt or GetTime()
		if meter.Fighting(now) then return Show() end
		-- (Its update may come later this frame.)
		return C_Timer.After(0, function()
			if meter.Fighting(now) then return Show() end
			ns.combatTextWhose.others = ns.combatTextWhose.others + 1
			if ns.combatTextRecord then Trace(("hit %s: you weren't dealing damage (no meter update): left out"):format(tostring(unit))) end
		end)
	end
	local now = claimAt or GetTime()
	if group.On() then
		-- (A swing in a group: your target's only. Its line came 0.3-0.75 s
		-- before it, too loose to tell whose; abilities' hits (Cleave) still
		-- go on any mob.)
		if melee and (via == "swing" or via == "swingGlance") and not hit.onTarget then
			ns.combatTextWhose.others = ns.combatTextWhose.others + 1
			if ns.combatTextRecord then Trace(("hit %s (swing) in a group, not your target: left out"):format(tostring(unit))) end
			return
		end
		-- (A spell hit or heal: waits with the others for the lines, scored.)
		if school and not melee then
			hit.at = now
			local score, why = 0, {}
			if PeekCast(school, now) then score, why[#why + 1] = score + group.CAST, "cast" end
			local key = group.Key(hit)
			if key and group.marks[key] and now - group.marks[key] <= group.MARK_KEEP then
				score, why[#why + 1] = score + group.MARK, "mark"
			end
			if hit.onTarget then score, why[#why + 1] = score + group.TARGET, "target" end
			hit.score = score
			if ns.combatTextRecord then
				Trace(("hit %s school %d in a group waits, score %d (%s)"):format(tostring(unit), school, score,
					#why > 0 and table.concat(why, "+") or "nothing"))
			end
			if #group.pending >= group.CAP then
				table.remove(group.pending, 1)
				ns.combatTextWhose.others = ns.combatTextWhose.others + 1
			end
			group.pending[#group.pending + 1] = hit
			ns.WakeFeatureLoop(holder)
			return
		end
	end
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

local Unclaimed -- (below: a hit no line came for, your pet's or someone else's)
local function OnLine()
	local now = GetTime()
	Fresh(owed, now)
	if owed[1] then Trace("line for a heal on you") table.remove(owed, 1) return end -- (a heal on you, already here)
	while pending[1] and now - pending[1].at > HOLD do Unclaimed(table.remove(pending, 1), now) end
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
local function OnOwnHit(unit, action, school)
	if not Plain(action) then return end
	if not ownSeen[action] then
		ownSeen[action] = true
		ns.Log("combattext", "first on you: " .. tostring(action))
	end
	-- (A physical hit on you: a damage shield of yours may answer it,
	-- Off-class above. Only physical: shields answer swings, and in a raid
	-- the boss's spells on you would vouch for everyone's shields.)
	if action == "WOUND" and unit == "player" and Plain(school) and tonumber(school) == 1 then
		local now = GetTime()
		while off.youHit[1] and now - off.youHit[1] > off.WINDOW do table.remove(off.youHit, 1) end
		if #off.youHit < 8 then off.youHit[#off.youHit + 1] = now end
		if ns.combatTextRecord then Trace("physical hit on you") end
	end
	if action ~= "HEAL" then return end
	local now = GetTime()
	local took = TakeLine(now, false)
	Trace("heal on you" .. (took and " took a waiting line" or " waits"))
	if not took then owed[#owed + 1] = now end
end

-- Your pet's hits (2026-11-19): no log line comes with them (a warlock's imp,
-- recorded), so a hit held past HOLD with none is your pet's when you have
-- one, it's on your target (as it landed) or your pet's, and it was physical
-- (its swing) or came with one of your pet's casts just finished before it
-- (a Firebolt, after its flight); its misses aren't shown. The rest: someone
-- else's.
local PET_WAIT = 2.5 -- (seconds a pet's finished cast waits for its hit)
local petCasts = {}
local petWatch = CreateFrame("Frame")
pcall(petWatch.RegisterUnitEvent, petWatch, "UNIT_SPELLCAST_SUCCEEDED", "pet")
petWatch:SetScript("OnEvent", function()
	local now = GetTime()
	while petCasts[1] and now - petCasts[1] > PET_WAIT do table.remove(petCasts, 1) end
	if #petCasts < 6 then petCasts[#petCasts + 1] = now end
end)
local function PetHit(hit, now)
	local node = NODE[hit.id]
	if not node or node.word then return false end
	-- (A heal is never your pet's: a groupmate's on a friend you target.)
	if CT.Kind(hit.id) == "heal" then return false end
	if ns.CombatTextBy and ns.CombatTextBy("pet") ~= "ours" then return false end -- (the game's draws them, or none show)
	local function Is(a, b)
		local ok, same = pcall(UnitIsUnit, a, b)
		if not ok then return "error" end
		if not Plain(same) then return "secret" end
		return same and true or false
	end
	local okPet, has = pcall(UnitExists, "pet")
	local pet = okPet and Plain(has) and has and true or false
	-- (On your pet's target, or yours: the game may not say whom an imp is
	-- casting at, and it casts at yours. A recording, 2026-11-19: every
	-- Firebolt left out with the pet's target check alone.)
	local petTarget, yourTarget = Is(hit[2], "pettarget"), hit.onTarget or Is(hit[2], "target")
	while petCasts[1] and now - petCasts[1] > PET_WAIT do table.remove(petCasts, 1) end
	local cast = petCasts[1] and true or false
	local record = ns.combatTextRecord
	if record then
		record(("pet check: pet=%s on pet's target=%s on your target=%s physical=%s pet cast waiting=%s"):format(
			tostring(pet), tostring(petTarget), tostring(yourTarget), tostring(hit.melee and true or false), tostring(cast)))
	end
	if not pet or not (petTarget == true or yourTarget == true) then return false end
	-- (In a group, a groupmate's spell on your target looks the same: only
	-- the pet's own target counts there.)
	local grouped = (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid())
	if grouped and petTarget ~= true then return false end
	-- (A mob someone else pulled: their hits, never your pet's.)
	local okTap, tapped = pcall(UnitIsTapDenied, hit[2])
	if okTap and Plain(tapped) and tapped then return false end
	-- (A swing: no cast comes before it, so it's your pet's only when it can't
	-- be anyone else's: solo, on your target. In a group a groupmate's swing
	-- looks the same, so none count there. The player's call, 2026-11-19: only
	-- your own and your pet's numbers, ever.)
	if hit.melee then return not grouped end
	if cast then
		table.remove(petCasts, 1)
		return true
	end
	return false
end
-- A hit no line came for: your pet's, else someone else's (left out).
Unclaimed = function(hit, now)
	if hit[1] and hit[2] and PetHit(hit, now) and StillThere(hit) then
		Trace("PET'S: no line, on your pet's target")
		local crit = NODE[hit.id] and NODE[hit.id].crit
		return Spawn(hit[1], hit[2], hit[3], crit and "petCrit" or "pet", hit.via, nil, hit.tag)
	end
	ns.combatTextWhose.others = ns.combatTextWhose.others + 1
	Trace("LEFT OUT")
	traceDue = traceDue or now + 1
end
-- Off-class hits held past HOLD (your own schools' hits have had their
-- lines): each takes a wand shot of yours, or a hit on you and a line left
-- over; mobs targeting you first. The rest: someone else's.
local function TakeTime(list, at, window)
	for i, t in ipairs(list) do
		if math.abs(t - at) <= window then
			table.remove(list, i)
			return t
		end
	end
end
local function ResolveOff(now, cutoff)
	local ripe
	for i = #off.pending, 1, -1 do
		local hit = off.pending[i]
		-- (A hit on you may come after its shield's: wait for it, a little.)
		local swung = hit[1] and group.swung[hit[1]]
		if now - hit.at > HOLD and hit.at < cutoff
			and (now - hit.at > off.WINDOW or #off.youHit > 0 or #off.wand > 0
				or (swung and math.abs(swung - hit.at) <= off.WINDOW)) then
			ripe = ripe or {}
			ripe[#ripe + 1] = table.remove(off.pending, i)
		end
	end
	if not ripe then return end
	table.sort(ripe, function(a, b)
		if (a.onYou and 1 or 0) ~= (b.onYou and 1 or 0) then return a.onYou and true or false end
		return a.at < b.at
	end)
	local running = LogRunning()
	for _, hit in ipairs(ripe) do
		local mine
		local swung = hit[1] and group.swung[hit[1]]
		if TakeTime(off.wand, hit.at, PET_WAIT) then
			mine = "your wand"
		elseif swung and math.abs(swung - hit.at) <= off.WINDOW and running then
			-- (A weapon proc, 2026-11-19: Fiery Weapon on a warrior, on the mob
			-- your swing just landed on (its number 0.3-0.75 s after its line, so
			-- either side), with its own line in its instant.)
			Fresh(lines, now, MELEE_HOLD)
			if TakeTime(lines, hit.at, group.SAME) then
				mine = ("your swing on it %+.2f s and a spare line (a weapon proc)"):format(swung - hit.at)
			end
		end
		if not mine then
			local you = TakeTime(off.youHit, hit.at, off.WINDOW)
			if you and running then
				Fresh(lines, now, MELEE_HOLD)
				-- (Its line in its own instant: in a raid lines are left over
				-- all the time, your hits on mobs with no plate.)
				if TakeTime(lines, hit.at, group.SAME) then
					mine = ("a hit on you %+.2f s and a spare line"):format(you - hit.at)
				else
					table.insert(off.youHit, 1, you) -- (not this one's: another may have it)
					table.sort(off.youHit)
				end
			elseif you then
				mine = ("a hit on you %+.2f s (no log)"):format(you - hit.at)
			end
		end
		if mine then
			Trace("OFF-CLASS, YOURS: " .. mine)
			-- (A shield's hit came from no cast: it mustn't take one of yours.)
			if mine ~= "your wand" then hit.school = nil end
			Mine(hit)
		else
			ns.combatTextWhose.others = ns.combatTextWhose.others + 1
			Trace(("OFF-CLASS LEFT OUT (on you: %s, hits on you waiting: %d)"):format(tostring(hit.onYou), #off.youHit))
		end
	end
end
-- A group's spell hits and heals (In a group, above), once the oldest has
-- waited two HOLDs (the hits around it in, their lines too): all that
-- waited HOLD, likeliest first, each takes the line nearest it within HOLD.
-- No line: your pet's, or someone else's.
local function ResolveGroup(now)
	local oldest
	for _, hit in ipairs(group.pending) do
		if not oldest or hit.at < oldest then oldest = hit.at end
	end
	if not oldest or now - oldest <= 2 * HOLD then return end
	local ripe = {}
	for i = #group.pending, 1, -1 do
		if now - group.pending[i].at > HOLD then ripe[#ripe + 1] = table.remove(group.pending, i) end
	end
	table.sort(ripe, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.at < b.at
	end)
	Fresh(lines, now, MELEE_HOLD)
	local record = ns.combatTextRecord
	for _, hit in ipairs(ripe) do
		local best, gap
		for i, t in ipairs(lines) do
			local d = math.abs(t - hit.at)
			if d <= HOLD and (not gap or d < gap) then best, gap = i, d end
		end
		if best then
			table.remove(lines, best)
			if record then Trace(("GROUP, YOURS: score %d, its line %.2f s off"):format(hit.score, gap)) end
			Mine(hit)
		else
			if record then Trace(("GROUP: score %d found no line"):format(hit.score)) end
			Unclaimed(hit, now)
		end
	end
end
-- Hits held past HOLD with no line: your pet's, or someone else's.
local function DropUnclaimed(now)
	while pending[1] and now - pending[1].at > HOLD do
		Unclaimed(table.remove(pending, 1), now)
	end
	-- (Your own schools' hits first, then the off-class ones: leftovers.)
	if group.pending[1] then ResolveGroup(now) end
	if off.pending[1] then
		-- (Not one landing with a group hit still waiting: that one's line first.)
		local cutoff = math.huge
		for _, hit in ipairs(group.pending) do cutoff = math.min(cutoff, hit.at - HOLD) end
		ResolveOff(now, cutoff)
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

-- Who draws each kind of number (the General tab's table, 2026-11-19): ours,
-- the game's or none, for your damage, your heals and your pet's. The game's
-- own numbers are its CVars: off while a row is ours or none, on while it's
-- the game's (on even if yours had them off), yours put back as the page goes
-- off and at logout. (Not its XP: no CVar has it; that's the XP row, the
-- blank font, which hides all the game's numbers with it.)
local GAME_CVARS = {
	damage = { "floatingCombatTextCombatDamage", "floatingCombatTextCombatDamage_v2" },
	heal = { "floatingCombatTextCombatHealing", "floatingCombatTextCombatHealing_v2" },
	pet = { "floatingCombatTextPetMeleeDamage", "floatingCombatTextPetSpellDamage",
		"floatingCombatTextPetMeleeDamage_v2", "floatingCombatTextPetSpellDamage_v2" },
}
local BY_KEY = { damage = "combatTextDamageBy", heal = "combatTextHealBy", pet = "combatTextPetBy" }
local GAME_SETS = {}
for kind, cvars in pairs(GAME_CVARS) do
	local function Values(value)
		local values = {}
		for _, cvar in ipairs(cvars) do values[cvar] = value end
		return values
	end
	GAME_SETS[kind] = {
		off = ns.CVarSet("Game's " .. kind .. " numbers off", "Combat Text Style (" .. BY_KEY[kind] .. ")",
			{ playerWins = true, values = Values("0") }),
		on = ns.CVarSet("Game's " .. kind .. " numbers on", "Combat Text Style (" .. BY_KEY[kind] .. ": the game's)",
			{ playerWins = true, values = Values("1") }),
	}
end
local GAME_NUMBERS = GAME_SETS.damage.off
ns.COMBAT_TEXT_GAME_NUMBERS = GAME_NUMBERS -- (Core.lua lets go at logout; the rest, below)
local letGo = CreateFrame("Frame")
letGo:RegisterEvent("PLAYER_LOGOUT")
letGo:SetScript("OnEvent", function()
	for _, sets in pairs(GAME_SETS) do
		pcall(ns.ApplyCVarSet, sets.off, false)
		pcall(ns.ApplyCVarSet, sets.on, false)
	end
end)
-- Who draws a kind: "ours", "game" or "none". Your pet's can be "group"
-- (the user's ask, 2026-11-19): ours alone, the game's in a group or raid.
local function By(kind)
	local value = Value(BY_KEY[kind])
	if value == "group" and kind == "pet" then
		return ((IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid())) and "game" or "ours"
	end
	return (value == "game" or value == "none") and value or "ours"
end
ns.CombatTextBy = By

-- After a setting changes (the page), and every two seconds.
function ns.RefreshCombatTextStyle()
	local on = PageOn()
	for kind, sets in pairs(GAME_SETS) do
		local by = By(kind)
		ns.ApplyCVarSet(sets.off, on and by ~= "game")
		ns.ApplyCVarSet(sets.on, on and by == "game")
	end
	KeepLog()
	TraceFlush()
	if not On() then
		for index = #live, 1, -1 do Retire(index) end
		wipe(pending)
		wipe(off.pending)
		wipe(group.pending)
	end
end

-- (Your pet's "group": joining or leaving one switches the game's pet
-- numbers at once, not at the next two-second refresh.)
local groupWatch = CreateFrame("Frame")
groupWatch:RegisterEvent("GROUP_ROSTER_UPDATE")
groupWatch:SetScript("OnEvent", function()
	if Value(BY_KEY.pet) == "group" then ns.RefreshCombatTextStyle() end
end)

ns.FeatureLoop(holder, function(...)
	DropUnclaimed(GetTime())
	Step(...)
end, function() return #live > 0 or #pending > 0 or #off.pending > 0 or #group.pending > 0 end)

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

-- A physical hit is a swing's (white) or an ability's (Claw, Ferocious Bite:
-- yellow, as the game's); UNIT_COMBAT doesn't say which. An instant
-- ability's hit lands in the very frame of its cast, either side of it (a
-- recording, a cat druid, 2026-11-18), a swing's on its own. So a physical
-- hit waits that frame out, and is an ability's when a cast of yours (not
-- the auto attack) came in it.
local AUTO_ATTACK = 6603
local WAND_SHOOT = 5019
local castAt
-- A spell's cast, for its number's size (CastSize, CastTime: 2026-11-18).
-- UNIT_COMBAT doesn't say which spell hit, so each cast of yours as it
-- finishes is kept a moment, with how long it took (its start to its end,
-- haste and all; 0 for an instant), and the next spell hit or heal of yours
-- takes the oldest still waiting: a Fireball's after its flight. A channel's
-- is its length, for every tick while it lasts. Which school each spell's
-- hits come in is learned as they're taken, so a DoT's tick doesn't take a
-- cast of another school. Nothing waiting: not known, its number as it is.
local CAST_WAIT = 2.5 -- (seconds a finished cast waits for its hit: a long flight)
local castStarts = {} -- [spell] = when its cast began
local casts = {}      -- { at, secs, spell } each, oldest first
local channel         -- { secs, spell, ends }
local schoolsOf = {}  -- [spell] = { [school] = hits taken }
local TakeCastLast    -- { at, school, secs, spell }: the cast the last spell hit took
local castWatch = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP" }) do
	pcall(castWatch.RegisterUnitEvent, castWatch, event, "player")
end
castWatch:SetScript("OnEvent", function(_, event, _, _, spell)
	if not (Plain(spell) and spell) then return end
	local now = GetTime()
	if event == "UNIT_SPELLCAST_START" then
		castStarts[spell] = now
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		local ok, _, _, _, startMs, endMs = pcall(UnitChannelInfo, "player")
		local secs = ok and Plain(startMs) and Plain(endMs) and tonumber(startMs) and tonumber(endMs)
			and (endMs - startMs) / 1000 or nil
		channel = secs and secs > 0 and { secs = secs, spell = spell, ends = now + secs + 0.3 } or nil
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if channel then channel.ends = math.min(channel.ends, now + 0.3) end
	elseif spell ~= AUTO_ATTACK then
		-- (A wand's shot: its hit is yours in any school, Off-class.)
		if spell == WAND_SHOOT then
			while off.wand[1] and now - off.wand[1] > CAST_WAIT do table.remove(off.wand, 1) end
			if #off.wand < 4 then off.wand[#off.wand + 1] = now end
		end
		castAt = now
		local began = castStarts[spell]
		castStarts[spell] = nil
		-- (A channel's own start comes as a finished cast too: its ticks take the channel.)
		if channel and channel.spell == spell and now < channel.ends then return end
		local secs = began and now - began < 15 and now - began or 0
		while casts[1] and now - casts[1].at > CAST_WAIT do table.remove(casts, 1) end
		if #casts < 8 then casts[#casts + 1] = { at = now, secs = secs, spell = spell } end
	end
end)
-- Whether a school's hit could be this spell's: none of its hits learned
-- yet, or this school its most.
local function SchoolFits(spell, school)
	local seen = schoolsOf[spell]
	if not seen then return true end
	local best, most = nil, 0
	for each, count in pairs(seen) do
		if count > most then best, most = each, count end
	end
	return best == school
end
local function Learn(spell, school)
	local seen = schoolsOf[spell] or {}
	schoolsOf[spell] = seen
	seen[school] = (seen[school] or 0) + 1
end
-- Seconds of the cast this hit came from, or nil (not known: 100%).
TakeCast = function(school, now)
	school = tonumber(school)
	if not school then return nil end
	local record = ns.combatTextRecord
	if channel and now <= channel.ends and SchoolFits(channel.spell, school) then
		Learn(channel.spell, school)
		if record then record(("cast: a tick of channel %s, %.1f s"):format(tostring(channel.spell), channel.secs)) end
		return channel.secs
	end
	-- (An area spell's other hits, in the instant of the one that took its
	-- cast: the same cast, 2026-11-19. Before, the first alone grew.)
	local last = TakeCastLast
	if last and last.school == school and math.abs(now - last.at) <= group.SAME then
		if record then record(("cast: spell %s again (an area spell's hits in one instant)"):format(tostring(last.spell))) end
		return last.secs
	end
	while casts[1] and now - casts[1].at > CAST_WAIT do table.remove(casts, 1) end
	for i, cast in ipairs(casts) do
		if SchoolFits(cast.spell, school) then
			table.remove(casts, i)
			Learn(cast.spell, school)
			TakeCastLast = { at = now, school = school, secs = cast.secs, spell = cast.spell }
			if record then record(("cast: spell %s, %.2f s, school %d"):format(tostring(cast.spell), cast.secs, school)) end
			return cast.secs
		end
	end
	if record then record(("cast: none waiting for school %d (100%%)"):format(school)) end
	return nil
end
-- Whether a cast of yours waits for a hit of this school (TakeCast's, not
-- taking it): In a group's score.
PeekCast = function(school, now)
	school = tonumber(school)
	if not school then return false end
	if channel and now <= channel.ends and SchoolFits(channel.spell, school) then return true end
	local last = TakeCastLast
	if last and last.school == school and math.abs(now - last.at) <= group.SAME then return true end
	for _, cast in ipairs(casts) do
		if now - cast.at <= CAST_WAIT and SchoolFits(cast.spell, school) then return true end
	end
	return false
end
-- A miss with no school of its own (the game sends misses as physical) while
-- a long cast of yours waits for its hit: that spell's, the cast used up.
local function TakeLongCast(now)
	while casts[1] and now - casts[1].at > CAST_WAIT do table.remove(casts, 1) end
	for i, cast in ipairs(casts) do
		if cast.secs > 0 then
			table.remove(casts, i)
			return true
		end
	end
	return false
end
local function Physical(then_)
	local held = claimAt
	local at = held or GetTime()
	C_Timer.After(0, function()
		local was = claimAt
		claimAt = held
		then_(castAt == at)
		claimAt = was
	end)
end

-- A hit's text: a swing's (glancing or not), an ability's, or a spell's by
-- its school; a crit's, its hit's crits (via: the hit).
local CRIT_OF = { swing = "swingCrit", swingGlance = "swingCrit", ability = "spellCrit", heal = "healCrit" }
local function HitText(school, ability, glancing)
	if school == 1 then
		if ability then return "ability" end
		return glancing and "swingGlance" or "swing"
	end
	return CT.SCHOOL_NODE[school] or "spell"
end
-- (A spell's or ability's: its school's crit row, Fire's crits; a mixed
-- school, none of them: Crits itself.)
local SCHOOL_CRIT = { ability = "spellCritAbility" }
for _, node in ipairs(CT.NODES) do
	if node.critOf then SCHOOL_CRIT[node.critOf] = node.id end
end
local function CritText(hit)
	return SCHOOL_CRIT[hit] or CRIT_OF[hit] or "spellCrit"
end

local flagsSeen = {}
-- A hit's kind, school and flag as one key (the plate's and your target's
-- copy of one hit share it: TargetHit).
local function HitKey(action, flag, school)
	return tostring(action) .. "/" .. (Plain(school) and tostring(school) or "?") .. "/" .. (Plain(flag) and tostring(flag) or "?")
end
local targetHits = {} -- [hit key] = when your target's plate had it
-- spot: a hit on your target with no plate at all (a critter, which the
-- game gives none: seen 2026-11-19, a Rabbit), { plate = where it's drawn,
-- enemy = whether it was one as it was hit }.
local function OnHit(unit, action, flag, amount, school, spot)
	local record = ns.combatTextRecord
	if not On() or not Plain(unit) or not Plain(action) then
		if record then record("plate hit skipped: numbers off, or a secret unit or kind") end
		return
	end
	local plate = spot and spot.plate
	if not plate then
		local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
		local ok
		ok, plate = pcall(get or error, unit)
		if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then
			if record then record(("plate hit %s %s skipped: no plate, or locked"):format(unit, action)) end
			return
		end
	end
	local okTarget, isTarget = pcall(UnitIsUnit, unit, "target")
	if okTarget and Plain(isTarget) and isTarget then targetHits[HitKey(action, flag, school)] = GetTime() end
	local okEnemy, enemy = pcall(UnitCanAttack, "player", unit)
	enemy = okEnemy and Plain(enemy) and enemy
	if spot then enemy = spot.enemy end
	if not Wanted(unit, enemy) then
		if record then record(("plate hit %s %s skipped: no combat log, in a group, not your target"):format(unit, action)) end
		return
	end
	if record then
		record(("plate hit %s %s enemy=%s school=%s flag=%s: goes on (a WOUND on a friend, a heal on an enemy, or a"
			.. " text turned off still stops here)"):format(unit, action, tostring(enemy), Seen(school), Seen(flag)))
	end
	flag = Plain(flag) and flag or nil
	local crit = flag == "CRITICAL"
	-- (Each kind of hit and flag once in /cine log: is a crit "CRITICAL" here?)
	if flag then
		local seen = action .. "/" .. tostring(flag)
		if not flagsSeen[seen] then
			flagsSeen[seen] = true
			ns.Log("combattext", "first " .. seen .. (crit and " (a crit)" or ""))
		end
	end
	school = Plain(school) and tonumber(school) or 1
	if action == "WOUND" then
		if not enemy then return end
		-- (A plain 0: all of it absorbed, as the game's word.)
		if Plain(amount) and (amount == 0 or amount == "0") then
			if school ~= 1 then
				return Claim(plate, unit, CT.Word("spellMissAbsorb"), "spellMissAbsorb", HitText(school), nil)
			end
			return Physical(function(ability)
				local id = ability and "spellMissAbsorb" or "missAbsorb"
				Claim(plate, unit, CT.Word(id), id, HitText(1, ability), nil)
			end)
		end
		if school == 1 then
			return Physical(function(ability)
				local hit = HitText(1, ability, flag == "GLANCING")
				if record then record(ability and "physical hit: an ability's (a cast in its frame)" or "physical hit: a swing's") end
				-- (Matched to the log as a swing either way: Maul, an ability on the
				-- next swing, comes as two hits in one instant with one line, the
				-- second its own number, which went with the first only as swings
				-- do: left out as an ability's, 2026-11-18.)
				Claim(plate, unit, amount, crit and CritText(hit) or hit, hit, true, flag)
			end)
		end
		local hit = HitText(school)
		Claim(plate, unit, amount, crit and CritText(hit) or hit, hit, false, flag, school)
	elseif action == "HEAL" then
		if enemy then return end
		Claim(plate, unit, amount, crit and "healCrit" or "heal", "heal", nil, flag, school)
	elseif (CT.WORD_NODE[action] or CT.SPELL_WORD_NODE[action]) and enemy then
		-- Whose miss: a swing's (Swings' Misses) or a spell's or ability's
		-- (Spells and abilities' Misses). A miss comes as physical (school 1)
		-- even when a spell was resisted (seen 2026-11-18, a white Resist), so:
		-- a resist or reflect is a spell's; one with a school of its own is; one
		-- in the frame of a cast of yours is an ability's (or an instant's); one
		-- while a long cast waits for its hit (a Fireball in flight) is that
		-- spell's; the rest are swings'.
		local swingId, spellId = CT.WORD_NODE[action], CT.SPELL_WORD_NODE[action]
		local function Show(id, via)
			if record then record(("miss %s: %s"):format(action, id == spellId and "a spell's or ability's" or "a swing's")) end
			Claim(plate, unit, CT.Word(id), id, via, true)
		end
		if not swingId then return Show(spellId, "spell") end
		if not spellId then return Show(swingId, "swing") end
		if school ~= 1 then return Show(spellId, HitText(school)) end
		return Physical(function(ability)
			if ability then return Show(spellId, "ability") end
			if TakeLongCast(GetTime()) then return Show(spellId, "spell") end
			Show(swingId, "swing")
		end)
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
		-- Your target's hits too, for one that came with no plate hit: as a
		-- fight starts the game takes every plate away and brings it back in
		-- the same instant, and a hit landing then (a pull's Immolate, seen
		-- 2026-11-19) came for your target alone. A frame on, its plate back:
		-- drawn there, unless the plate had it after all.
		local onTarget = CreateFrame("Frame")
		if pcall(onTarget.RegisterUnitEvent, onTarget, "UNIT_COMBAT", "target") then
			-- (No plate at all, a critter's: drawn where a dying mob's last hit
			-- goes, above the screen's middle; the game says nowhere else.)
			local noPlate = CreateFrame("Frame", nil, holder)
			noPlate:SetSize(1, 1)
			noPlate:SetPoint("CENTER", holder, "CENTER", 0, GONE_Y)
			onTarget:SetScript("OnEvent", ns.Profiled("Combat text", function(_, _, _, action, flag, amount, school)
				if not On() or not Plain(action) then return end
				-- (You as your target: your own hits' listener has those.)
				local okSelf, isSelf = pcall(UnitIsUnit, "target", "player")
				if okSelf and Plain(isSelf) and isSelf then return end
				local at, key = GetTime(), HitKey(action, flag, school)
				-- (Whether it's an enemy as it's hit, and which mob: a critter killed
				-- by it is gone a frame on, and you may switch target meanwhile.)
				local okEnemy, enemy = pcall(UnitCanAttack, "player", "target")
				enemy = okEnemy and Plain(enemy) and enemy and true or false
				local okGuid, guid = pcall(UnitGUID, "target")
				guid = okGuid and Plain(guid) and guid or nil
				-- (Its own plate, looked for again and again: at a pull it can take
				-- more than a frame to come back, and the first hit went above the
				-- screen's middle, 2026-11-19. Only after 0.4 s with none, there.)
				local tries = 0
				local function Late(hitUnit, spot)
					claimAt = at
					local ok, why = pcall(OnHit, hitUnit, action, flag, amount, school, spot)
					claimAt = nil
					if not ok then geterrorhandler()(why) end
				end
				local function Try()
					if targetHits[key] == at then return end
					local record = ns.combatTextRecord
					for i = 1, 40 do
						local plateUnit = "nameplate" .. i
						local same
						if guid then
							local okSame, its = pcall(UnitGUID, plateUnit)
							same = okSame and Plain(its) and its == guid
						else
							local okSame, isIt = pcall(UnitIsUnit, plateUnit, "target")
							same = okSame and Plain(isIt) and isIt
						end
						if same then
							if record then
								record(("hit on your target came with no plate hit: drawn on %s, its plate back after %.2f s")
									:format(plateUnit, GetTime() - at))
							end
							return Late(plateUnit)
						end
					end
					tries = tries + 1
					if tries < 8 then return C_Timer.After(0.05, Try) end
					-- (Only an enemy's, a critter's: a friend you target has no plate
					-- with friendly plates off, and its heals aren't drawn mid-screen.)
					if not enemy then
						if record then record("hit on your target came with no plate hit, none came in 0.4 s, not an enemy: left out") end
						return
					end
					if record then record("hit on your target came with no plate hit, and none came in 0.4 s: drawn above the screen's middle") end
					Late("target", { plate = noPlate, enemy = enemy })
				end
				C_Timer.After(0, Try)
			end))
		end
		-- Whose hit: the log's lines, and the hits on you and your pet that own theirs.
		local log = CreateFrame("Frame")
		logListening = pcall(log.RegisterEvent, log, "COMBAT_LOG_MESSAGE")
		log:SetScript("OnEvent", ns.Profiled("Combat text log", function()
			if not logLines then
				logLines = true
				ns.Log("combattext", "first combat log line: hits are matched to lines from now on")
			end
			if On() then OnLine() end
		end))
		local own = CreateFrame("Frame")
		pcall(own.RegisterUnitEvent, own, "UNIT_COMBAT", "player", "pet")
		own:SetScript("OnEvent", ns.Profiled("Combat text own", function(_, _, who, action, _, _, school)
			if On() then OnOwnHit(who, action, school) end
		end))
		if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2, function() ns.Guard(ns.RefreshCombatTextStyle) end) end
		ns.RefreshCombatTextStyle()
		return
	end
	if not Plain(unit) then return end
	-- A plate going isn't always its mob gone: as a fight starts the game takes
	-- every plate away and brings it back in the same instant, and a pull's
	-- Immolate crit, drawn on its plate, was moved above the screen's middle
	-- (2026-11-19). So its numbers wait GONE_WAIT for the same mob's plate:
	-- back, they go on it; not, they're let go (a kill).
	local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
	local okGuid, guid = pcall(UnitGUID, unit)
	guid = okGuid and Plain(guid) and guid or nil
	if event == "NAME_PLATE_UNIT_ADDED" then
		Listen(unit)
		local ok, plate = pcall(get or error, unit)
		-- (The game reuses plates: this one, gone a moment ago for another mob,
		-- lets that mob's numbers go now, before this one's hits come.)
		local before = ok and plate and goneWait[plate]
		if before and before.guid ~= guid then
			goneWait[plate] = nil
			LetGo(plate)
		end
		if not guid then return end
		for old, went in pairs(goneWait) do
			if went.guid == guid then
				goneWait[old] = nil
				if ok and plate then
					local moved = 0
					for _, number in ipairs(live) do
						if number.plate == old then
							number.plate, number.unit, number.anchor = plate, unit, plate
							moved = moved + 1
						end
					end
					local record = ns.combatTextRecord
					if record and moved > 0 then record(("its plate came back: %d number(s) stay on it"):format(moved)) end
				else
					LetGo(old)
				end
			end
		end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local ok, plate = pcall(get or error, unit)
		if not (ok and plate) then return end
		if not guid then return LetGo(plate) end
		local at = GetTime()
		goneWait[plate] = { guid = guid, at = at }
		C_Timer.After(GONE_WAIT, function()
			local went = goneWait[plate]
			if went and went.at == at then
				goneWait[plate] = nil
				LetGo(plate)
			end
		end)
	end
end))

-- /cine debug combattext: how the page stands, in one line.
function ns.CombatTextStateLine()
	local db = ns.db
	local parts = {}
	for _, key in ipairs({ "styleGeneral", "combatTextStyle", "combatTextNumbers", "combatTextFont", "combatTextEdge",
		"combatTextSize", "combatTextDamageBy", "combatTextHealBy", "combatTextPetBy", "hideWorldText" }) do
		parts[#parts + 1] = key .. "=" .. tostring(db[key])
	end
	-- (And every text turned off, and those with anything of their own.)
	local off, own = {}, {}
	for _, node in ipairs(CT.NODES) do
		if db[CT.Key(node.id, "Show")] == false then off[#off + 1] = node.id end
		if CT.Changed(node.id) then own[#own + 1] = node.id end
	end
	parts[#parts + 1] = "off=" .. (off[1] and table.concat(off, ",") or "none")
	parts[#parts + 1] = "own=" .. (own[1] and table.concat(own, ",") or "none")
	return ("numbers on=%s page on=%s blocked=%s | log listening=%s lines came=%s restricted=%s meter=%s running=%s turned on by us=%s | shown as yours"
		.. " %d, left out %d, showing now %d, waiting %d | game numbers off=%s | scale=%s ramp=%s | font=%s | %s")
		:format(tostring(On()), tostring(PageOn()), tostring(ns.combatTextBlocked), tostring(logListening),
		tostring(logLines), tostring(Restricted()),
		meter.listening and (meter.at and ("%.1f s ago"):format(GetTime() - meter.at) or "never") or "off",
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
		LogRunning() and "combat log lines" or (logListening and (logLines and "log off: all hits count"
			or "no log lines have come: all hits count") or "no log on this client"),
		whose.mine, whose.others)
	ns.Print(text)
	ns.Log("combattext", text)
end

-- A sample of a text over a frame, for the page's preview (CombatTextPage.lua):
-- the text itself if it's one the game sends (a crit through its group's
-- first hit, a miss with a swing).
-- layer: the frame to draw it in (Spawn).
local SAMPLE_VIA = { swingCrit = "swing", spellCrit = "spellNature", healCrit = "heal", pet = "swing", petCrit = "spellFire" }
-- cast: its spell's cast in seconds (a long cast's bigger, CastSize).
function ns.CombatTextSample(frame, id, layer, via, cast)
	local node = NODE[id]
	if not node then return end
	if node.word then
		return Spawn(frame, nil, CT.Word(id), id, via or (node.parent == "spellMiss" and "spell" or "swing"), layer)
	end
	if node.sample then
		return Spawn(frame, nil, node.sample, id, via or SAMPLE_VIA[id] or node.critOf or id, layer,
			id == "swingGlance" and "GLANCING" or nil,
			nil, cast)
	end
end
