-- Battle Vision's moments, as cards (Cards.lua): going into a fight and
-- coming out of it, and a boss's name as its fight starts or before it. This
-- file hears them (ns.Cards.Fire does the rest) and draws every card, of every
-- page's moment: a word on the screen, in a letterbox bar or across it on a
-- band (a title card, a subtitle, a chapter line or a banner), a pulse round
-- the screen's edges, an icon. (Sounds: CombatSoundRules.lua.)

local _, ns = ...
local L = ns.L
local DEFAULTS = ns.DEFAULTS

-- (Each a row on the Cards page: their look is its, Cards.lua's.)
DEFAULTS.combatOnEnter = true          -- the Combat card going into a fight (its row: cardCombatOn)
DEFAULTS.combatOnLeave = true          -- ...and coming out of it
DEFAULTS.combatMinFight = 3            -- no leaving card after a fight shorter than this (seconds)
DEFAULTS.combatTextIn = "Combat"       -- the words ("": none, just the icon, pulse, bar; these
DEFAULTS.combatTextOut = "Respite"     -- two shown in the game's language: ns.CardWords)
-- Boss fights: the boss's name for its words, once a run for each boss: as
-- it's pulled, or before that as you first target it or come near it.
DEFAULTS.cardBossOn = false            -- the Boss row
DEFAULTS.combatBossPull = true         -- as a boss fight starts (ENCOUNTER_START)
DEFAULTS.combatBossTarget = false      -- as you first target a boss, before the pull
DEFAULTS.combatBossNear = false        -- as you first come within about 28 yards of one
DEFAULTS.combatBossSub = true          -- the dungeon and difficulty under the name
DEFAULTS.combatBossCount = true        -- "Boss 2 of 3" over it, where the Journal knows (on the pull)

local FADE_IN, FADE_OUT = 0.35, 0.5
local REVEAL = 1.1                 -- Reveal: seconds the words take to open
local REVEAL_OUT = 0.9             -- ...and to fade out, slower
local LATE_FROM, LATE_FOR = 0.6, 0.6 -- ...a boss card's other lines coming in after the name
local TRACK = 1.4                  -- Tracking in: seconds the letters take to close up
local TRACK_FROM = 0.32            -- ...from this much apart (of the text's height)
local TYPE_EACH = 0.07             -- Typewriter: seconds for each letter
local PULSE_PEAK, PULSE_GONE = 0.12, 0.9
local CUT_OUT = 0.25               -- a cue cut short (the fight's other edge came first) fades this fast
local OUTLINES = { [0] = "", "OUTLINE", "THICKOUTLINE" }
-- Banner: the words across the middle of the screen on a dark band with soft
-- edges (the death banner's), coming in and going slowly, or a picture on a
-- flat one (card.picture), in quicker. The words look worn: faint copies
-- behind them, nudged each way, bleed their edges. (A grain texture over them
-- wore the band round the letters too, and looked dirty: tested.)
local BANNER_IN, BANNER_OUT = 3, 1.5
local PICTURE_IN, PICTURE_OUT = 0.4, 1
local BANNER_BAND, BANNER_EDGE = 1.7, 1.2 -- the band's height and each soft edge's, of the words' height
local BANNER_ALPHA = 0.7
local BANNER_BLEED = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -0.6, 0.6 }, { 0.6, -0.6 } }
local BLEED_NUDGE = 0.035                 -- ...how far, of the words' size
local BLEED_ALPHA, BANNER_TEXT_ALPHA = 0.16, 0.9
local FLAT_BAND, FLAT_ALPHA = 1.6, 0.5    -- a picture's band, of its height

-- A gradient on texture, from alpha 0 at one end to peak (or 1) at the other
-- ("VERTICAL": opaque at the top if high; "HORIZONTAL": opaque at the left if
-- high). (The peak goes in its colors: SetAlpha on it after didn't dim it.)
local function Gradient(texture, orientation, high, r, g, b, peak)
	peak = peak or 1
	local from, to = high and 0 or peak, high and peak or 0
	if orientation == "HORIZONTAL" then from, to = to, from end
	texture:SetColorTexture(1, 1, 1, 1)
	if texture.SetGradient and CreateColor then
		texture:SetGradient(orientation, CreateColor(r, g, b, from), CreateColor(r, g, b, to))
	elseif texture.SetGradientAlpha then
		texture:SetGradientAlpha(orientation, r, g, b, from, r, g, b, to)
	else
		texture:SetColorTexture(r, g, b, 0.4 * peak)
	end
end

-- The chapter line's color: flat, or fading out to the right (the lower third).
local function LineColor(line, r, g, b, fade)
	if fade then
		Gradient(line, "HORIZONTAL", true, r, g, b)
	elseif line.SetGradient and CreateColor then
		line:SetColorTexture(1, 1, 1, 1)
		line:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.8), CreateColor(r, g, b, 0.8))
	elseif line.SetGradientAlpha then
		line:SetColorTexture(1, 1, 1, 1)
		line:SetGradientAlpha("HORIZONTAL", r, g, b, 0.8, r, g, b, 0.8)
	else
		line:SetColorTexture(r, g, b, 0.8)
	end
end

-- A cue's parts on frame (the real one over the screen, or the preview's):
-- letterbox bars of its own, a pulse round the edges, and over them the
-- text, its line and the icon.
local function MakeCue(frame)
	local bars = CreateFrame("Frame", nil, frame)
	bars:SetAllPoints()
	ns.MakeLetterboxBars(bars)
	local pulse = CreateFrame("Frame", nil, frame)
	pulse:SetAllPoints()
	pulse:SetFrameLevel(bars:GetFrameLevel() + 1)
	pulse.edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = pulse:CreateTexture(nil, "ARTWORK")
		if side == "TOP" or side == "BOTTOM" then
			edge:SetPoint(side .. "LEFT")
			edge:SetPoint(side .. "RIGHT")
		else
			edge:SetPoint("TOP" .. side)
			edge:SetPoint("BOTTOM" .. side)
		end
		pulse.edges[side] = edge
	end
	local over = CreateFrame("Frame", nil, frame)
	over:SetAllPoints()
	over:SetFrameLevel(pulse:GetFrameLevel() + 1)
	-- The words in a window that opens from their middle or side (Reveal).
	local clip = CreateFrame("Frame", nil, over)
	if clip.SetClipsChildren then clip:SetClipsChildren(true) end
	local text = clip:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.8)
	-- An outline in a color: the text again behind it, nudged each way (the
	-- game's own outline is always black).
	text.rim = {}
	for i = 1, 8 do
		text.rim[i] = clip:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		text.rim[i]:SetDrawLayer("OVERLAY", -1)
	end
	-- (A banner's worn edges: its faint copies, behind the outline.)
	text.bleed = {}
	for i = 1, #BANNER_BLEED do
		text.bleed[i] = clip:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		text.bleed[i]:SetDrawLayer("OVERLAY", -2)
	end
	local line = over:CreateTexture(nil, "OVERLAY")
	local icon = over:CreateTexture(nil, "OVERLAY")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- A boss card's lines: the dungeon under the name, the boss's number over it.
	local sub = over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	local meta = over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	for _, each in ipairs({ sub, meta }) do
		each:SetShadowOffset(1, -1)
		each:SetShadowColor(0, 0, 0, 0.8)
	end
	-- A banner's band, under the words (the words' frame is over it): its
	-- middle and soft edges, or flat for a picture.
	local band = {}
	for _, part in ipairs({ "middle", "top", "bottom", "flat" }) do
		band[part] = over:CreateTexture(nil, "BACKGROUND")
		band[part]:Hide()
	end
	for _, part in ipairs({ "middle", "flat" }) do
		band[part]:SetPoint("LEFT", over, "LEFT")
		band[part]:SetPoint("RIGHT", over, "RIGHT")
	end
	band.top:SetPoint("BOTTOMLEFT", band.middle, "TOPLEFT")
	band.top:SetPoint("BOTTOMRIGHT", band.middle, "TOPRIGHT")
	band.bottom:SetPoint("TOPLEFT", band.middle, "BOTTOMLEFT")
	band.bottom:SetPoint("TOPRIGHT", band.middle, "BOTTOMRIGHT")
	local picture = over:CreateTexture(nil, "ARTWORK")
	picture:SetPoint("CENTER")
	picture:Hide()
	frame.cue = { bars = bars, pulse = pulse, over = over, clip = clip, text = text, line = line, icon = icon,
		sub = sub, meta = meta, band = band, picture = picture }
	bars:Hide()
	pulse:Hide()
	over:Hide()
	return frame.cue
end

local function FontFile(look)
	return ns.StyleFontFile(look.combatFont) or (GameFontNormalHuge:GetFont())
end

-- The words at key (combatTextIn, combatTextOut) as shown: the defaults in
-- the game's language.
function ns.CardWords(key)
	local word = ns.db and ns.db[key] or DEFAULTS[key]
	return word == DEFAULTS[key] and L[word] or word
end

-- Tracking in: the words' letters each a text of their own, each where it
-- sits in the whole words (cue.letterAt) plus spacing for each character
-- before it (cue.letterIndex), about cue.text's origin. At no spacing they
-- sit just as the whole words do, so the swap back to them can't be seen.
local function LayLetters(cue, spacing)
	local total = cue.wordsWidth + spacing * (cue.charCount - 1)
	local origin = cue.trackOrigin
	local x = origin == "LEFT" and 0 or origin == "RIGHT" and -total or -total / 2
	for i = 1, cue.letterCount do
		cue.letters[i]:SetPoint("LEFT", cue.text, origin, x + cue.letterAt[i] + spacing * (cue.letterIndex[i] - 1), 0)
	end
end

-- Sets up cue for a going in (enter) or coming out, on a screen width x
-- height; scale: that next to the real screen (the preview's smaller).
-- boss: a boss card's { name, sub, meta } (the name can be secret: shown,
-- never read).
local function Setup(cue, look, enter, width, height, scale, boss)
	local r, g, b, pr, pg, pb
	if enter then
		r, g, b = look.combatInR, look.combatInG, look.combatInB
		pr, pg, pb = look.combatPulseInR, look.combatPulseInG, look.combatPulseInB
	else
		r, g, b = look.combatOutR, look.combatOutG, look.combatOutB
		pr, pg, pb = look.combatPulseOutR, look.combatPulseOutG, look.combatPulseOutB
	end
	local word = boss and boss.name or ns.CardWords(enter and "combatTextIn" or "combatTextOut")
	local secret = issecretvalue ~= nil and issecretvalue(word)
	local style, place = look.combatStyle, look.combatPlace
	-- (A banner: across the middle; a picture always on one, in place of the
	-- words.)
	local picture = boss and boss.picture
	local banner = style == "banner" or picture and true or false
	if banner then place = "screen" end
	if picture or (not secret and word == "") then style = "none" end
	-- (In a bar with no letterbox up, if it says so: the lower third.)
	if (place == "top" or place == "bottom") and look.combatBarFallback
		and not (ns.db.letterbox and (scale ~= 1 or ns.lastCinematic)
		and ns.LetterboxHeight(ns.LetterboxLook(), width, height) >= 1) then
		place = "third"
	end
	local size = look.combatSize * scale
	if style == "subtitle" then
		size = math.max(size * 0.5, 11 * scale)
		if not secret then word = "- " .. word .. " -" end
	elseif style == "chapter" then
		size = size * 0.65
	end
	local text, line, icon = cue.text, cue.line, cue.icon
	text:ClearAllPoints()
	line:ClearAllPoints()
	icon:ClearAllPoints()
	cue.barSide, cue.lineWidth, cue.third = nil, nil, place == "third"
	local x, y, point, relative = 0, 0, "CENTER", "CENTER"
	if place == "top" or place == "bottom" then
		-- With the letterbox up (in CineMode; the preview as if it were): in
		-- its bar. Else in a bar of our own, as tall as the letterbox's. The
		-- text scales with the bar (combatBarScale).
		local barLook = ns.LetterboxLook()
		local full = ns.LetterboxHeight(barLook, width, height)
		local active = ns.db.letterbox and (scale ~= 1 or ns.lastCinematic) and full >= 1
		local want = full >= 1 and full or size * 1.5
		size = math.max(want * look.combatBarScale, 6 * scale)
		cue.ownBar = not (active and scale == 1)
		local side = place == "top" and "TOP" or "BOTTOM"
		local align = look.combatAlign == "left" and "LEFT" or look.combatAlign == "right" and "RIGHT" or ""
		point, relative = align ~= "" and align or "CENTER", side .. align
		x = (align == "LEFT" and 1 or align == "RIGHT" and -1 or 0) * math.max(16 * scale, want * 0.6)
		y = (side == "TOP" and -1 or 1) * want / 2
		cue.barSide, cue.barShare = side, want / height
		if style == "chapter" then
			line:SetPoint("CENTER", cue.over, side, 0, (side == "TOP" and -1 or 1) * (want - 1))
		end
	elseif place == "third" then
		-- The lower third: low on the left, the line under it fading out.
		point, relative, x, y = "BOTTOMLEFT", "BOTTOMLEFT", width * 0.07, height * 0.22
		if style == "chapter" then line:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6 * scale) end
	elseif style == "title" then
		y = height * 0.12
	elseif style == "subtitle" then
		point, relative, y = "BOTTOM", "BOTTOM", height * 0.16
	elseif style == "chapter" then
		y = height * 0.14
		line:SetPoint("TOP", text, "BOTTOM", 0, -6 * scale)
	end
	text:SetPoint(point, cue.over, relative, x, y)
	text:SetText(word)
	local outline = OUTLINES[look.combatOutline] or ""
	local or_, og, ob = look.combatOutlineR or 0, look.combatOutlineG or 0, look.combatOutlineB or 0
	local rimmed = outline ~= "" and or_ + og + ob > 0
	local fontSize = math.floor(size + 0.5)
	ns.SetPlateNameFont(text, GameFontNormalHuge, FontFile(look), fontSize, 1, rimmed and "" or outline)
	ns.SetTextShadow(text, look.combatShadow)
	-- (A banner's words a touch see-through, its copies faint: as SetAlpha,
	-- below. A color's alpha is the same thing on text, and SetAlpha after
	-- undid it: tested.)
	cue.textAlpha = style == "banner" and BANNER_TEXT_ALPHA or 1
	text:SetTextColor(r, g, b, 1)
	text:SetVertexColor(r, g, b, 1) -- (one and the same on Forever)
	text:SetShown(style ~= "none")
	for i, bleed in ipairs(text.bleed) do
		bleed:SetShown(style == "banner")
		if style == "banner" then
			local nudge = BANNER_BLEED[i]
			bleed:ClearAllPoints()
			bleed:SetPoint("CENTER", text, "CENTER", nudge[1] * size * BLEED_NUDGE, nudge[2] * size * BLEED_NUDGE)
			bleed:SetText(word)
			ns.SetPlateNameFont(bleed, GameFontNormalHuge, FontFile(look), fontSize, 1, "")
			bleed:SetTextColor(r, g, b, 1)
			bleed:SetVertexColor(r, g, b, 1)
			bleed:SetShadowOffset(0, 0)
		end
	end
	local nudge = (outline == "THICKOUTLINE" and 2 or 1) * math.max(scale, 0.5)
	for i, rim in ipairs(text.rim) do
		rim:SetShown(rimmed and style ~= "none")
		if rimmed then
			local angle = (i - 1) * math.pi / 4
			rim:ClearAllPoints()
			rim:SetPoint("CENTER", text, "CENTER", math.cos(angle) * nudge, math.sin(angle) * nudge)
			rim:SetText(word)
			ns.SetPlateNameFont(rim, GameFontNormalHuge, FontFile(look), fontSize, 1, "")
			rim:SetTextColor(or_, og, ob, 1)
			rim:SetVertexColor(or_, og, ob, 1)
			rim:SetShadowOffset(0, 0)
		end
	end
	if style == "chapter" then
		LineColor(line, r, g, b, cue.third)
		line:SetHeight(math.max(1, scale))
		-- (A secret name's width is secret too: then a fixed share of the screen.)
		local textWidth = text:GetStringWidth()
		if issecretvalue and issecretvalue(textWidth) then textWidth = width * 0.2 end
		cue.lineWidth = cue.barSide and width * 0.6 or cue.third and width * 0.26
			or math.max(textWidth * 1.6, width * 0.3)
	end
	line:SetShown(style == "chapter")
	-- A boss card's lines: in a bar, the dungeon beside the name (before it
	-- when on the right); on the screen, the dungeon under it (under its line)
	-- and the boss's number over it.
	local sub, meta = cue.sub, cue.meta
	sub:ClearAllPoints()
	meta:ClearAllPoints()
	local subText = boss and style ~= "none" and boss.sub or ""
	local metaText = boss and style ~= "none" and not cue.barSide and boss.meta or ""
	local subR, subG, subB = (r + 1) / 2, (g + 1) / 2, (b + 1) / 2
	local plain = outline ~= "" and "OUTLINE" or ""
	local before = cue.barSide and look.combatAlign == "right"
	if subText ~= "" then
		local subSize = cue.barSide and size * 0.7 or math.max(size * 0.42, 10 * scale)
		ns.SetPlateNameFont(sub, GameFontNormalHuge, FontFile(look), math.floor(subSize + 0.5), 1, plain)
		ns.SetTextShadow(sub, look.combatShadow)
		sub:SetText(subText)
		sub:SetTextColor(subR, subG, subB, 1)
		sub:SetVertexColor(subR, subG, subB, 1)
		local under = style == "chapter" and line or text
		if before then
			cue.subAt = { "RIGHT", text, "LEFT", -size * 0.8, 0 }
		elseif cue.barSide then
			cue.subAt = { "LEFT", text, "RIGHT", size * 0.8, 0 }
		elseif cue.third then
			cue.subAt = { "TOPLEFT", under, "BOTTOMLEFT", 0, -size * 0.25 }
		else
			cue.subAt = { "TOP", under, "BOTTOM", 0, -size * 0.25 }
		end
		sub:SetPoint(unpack(cue.subAt))
	end
	sub:SetShown(subText ~= "")
	if metaText ~= "" then
		local metaSize = math.max(size * 0.3, 8 * scale)
		ns.SetPlateNameFont(meta, GameFontNormalHuge, FontFile(look), math.floor(metaSize + 0.5), 1, plain)
		ns.SetTextShadow(meta, look.combatShadow)
		meta:SetText(metaText)
		meta:SetTextColor(0.8, 0.78, 0.72, 1)
		meta:SetVertexColor(0.8, 0.78, 0.72, 1)
		cue.metaAt = cue.third and { "BOTTOMLEFT", text, "TOPLEFT", 0, size * 0.2 }
			or { "BOTTOM", text, "TOP", 0, size * 0.2 }
		meta:SetPoint(unpack(cue.metaAt))
	end
	meta:SetShown(metaText ~= "")
	-- Reveal: the words' window opens from where they're anchored (Draw), a
	-- boss card's other lines rising in after them.
	local clip = cue.clip
	clip:ClearAllPoints()
	local origin = point:find("LEFT") and "LEFT" or point:find("RIGHT") and "RIGHT" or "CENTER"
	local pad = size * 0.5
	clip:SetPoint(origin, text, origin, origin == "LEFT" and -pad or origin == "RIGHT" and pad or 0, 0)
	clip:SetHeight(size * 2.5)
	-- (Tracking in and Typewriter need the words' letters: a secret name opens
	-- as Reveal.)
	local anim = look.combatAnim
	if (anim == "track" or anim == "type") and (secret or style == "none") then anim = "reveal" end
	cue.reveal, cue.track, cue.type = anim == "reveal", anim == "track", anim == "type"
	cue.clipWidth = width
	clip:SetWidth((cue.reveal or cue.type) and 1 or width)
	cue.late, cue.rise = (cue.reveal or cue.track or cue.type) and (subText ~= "" or metaText ~= ""), size * 0.15
	cue.lateFrom, cue.typeTime = LATE_FROM, 0
	-- The words' width up to a letter, measured in their own font, so pairs
	-- keep their kerning.
	local flags = rimmed and "" or outline
	local function Width(part)
		local measure = cue.measure
		if not measure then
			measure = cue.over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
			measure:Hide()
			cue.measure = measure
		end
		measure:SetText(part)
		ns.SetPlateNameFont(measure, GameFontNormalHuge, FontFile(look), fontSize, 1, flags)
		return measure:GetStringWidth()
	end
	-- Typewriter: the window opens from the words' left a letter at a time
	-- (cue.typeEnds: where each ends), the other lines rising in after.
	if cue.type then
		clip:ClearAllPoints()
		clip:SetPoint("LEFT", text, "LEFT", -size * 0.1, 0)
		cue.typeEnds = {}
		local typed = ""
		for char in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			typed = typed .. char
			cue.typeEnds[#cue.typeEnds + 1] = Width(typed) + size * 0.2
		end
		cue.typeTime = #cue.typeEnds * TYPE_EACH
		cue.lateFrom = cue.typeTime
	end
	-- Tracking in: a text for each letter, the same font and color, laid out
	-- apart (Draw closes them up, then the words show whole again).
	cue.letters = cue.letters or {}
	local count = 0
	if cue.track then
		-- (Each letter's place: the words up to and with it, less the letter
		-- itself.)
		cue.letterAt, cue.letterIndex = cue.letterAt or {}, cue.letterIndex or {}
		cue.trackOrigin, cue.trackFrom = origin, size * TRACK_FROM
		cue.wordsWidth = Width(word)
		local before, index = "", 0
		for char in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			index = index + 1
			if char ~= " " then
				count = count + 1
				local letter = cue.letters[count]
				if not letter then
					letter = cue.over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
					letter:SetShadowOffset(1, -1)
					letter:SetShadowColor(0, 0, 0, 0.8)
					cue.letters[count] = letter
				end
				letter:ClearAllPoints()
				letter:SetText(char)
				ns.SetPlateNameFont(letter, GameFontNormalHuge, FontFile(look), fontSize, 1, flags)
				ns.SetTextShadow(letter, look.combatShadow)
				letter:SetTextColor(r, g, b, 1)
				letter:SetVertexColor(r, g, b, 1)
				letter:Show()
				cue.letterAt[count] = Width(before .. char) - Width(char)
				cue.letterIndex[count] = index
			end
			before = before .. char
		end
		cue.letterCount, cue.charCount = count, index
		if count > 0 then LayLetters(cue, cue.trackFrom) end
	end
	for i = count + 1, #cue.letters do cue.letters[i]:Hide() end
	cue.tracking = cue.track and count > 0
	text:SetAlpha(cue.tracking and 0 or cue.textAlpha)
	for _, rim in ipairs(text.rim) do rim:SetAlpha(cue.tracking and 0 or 1) end
	for _, bleed in ipairs(text.bleed) do bleed:SetAlpha(cue.tracking and 0 or BLEED_ALPHA) end
	sub:SetAlpha(1)
	meta:SetAlpha(1)
	local showIcon = look[enter and "combatIconShowIn" or "combatIconShowOut"] and true or false
	icon:SetShown(showIcon)
	if showIcon then
		icon:SetTexture(enter and look.combatIconIn or look.combatIconOut)
		icon:SetSize(size * 1.1, size * 1.1)
		if style == "none" then
			icon:SetPoint(point, cue.over, relative, x, y)
		else
			icon:SetPoint("RIGHT", before and subText ~= "" and sub or text, "LEFT", -size * 0.35, 0)
		end
	end
	for side, edge in pairs(cue.pulse.edges) do
		local thick = (side == "TOP" or side == "BOTTOM") and height * 0.2 or width * 0.12
		if side == "TOP" or side == "BOTTOM" then edge:SetHeight(thick) else edge:SetWidth(thick) end
		Gradient(edge, (side == "TOP" or side == "BOTTOM") and "VERTICAL" or "HORIZONTAL",
			side == "TOP" or side == "LEFT", pr, pg, pb)
	end
	-- A banner's band: soft edged under the words, or flat under a picture
	-- (picture: a card's file, pictureSize its height of the screen's,
	-- pictureAspect its width of its height).
	local band = cue.band
	for _, part in pairs(band) do part:Hide() end
	cue.banner, cue.holdExtra = banner, boss and tonumber(boss.holdExtra) or 0
	cue.pictured = picture and true or false
	if picture then
		local tall = height * (boss.pictureSize or 0.1)
		cue.picture:SetTexture(picture)
		cue.picture:SetSize(tall * (boss.pictureAspect or 4), tall)
		band.flat:SetColorTexture(0, 0, 0, FLAT_ALPHA)
		band.flat:SetHeight(tall * FLAT_BAND)
		band.flat:Show()
	elseif banner then
		band.middle:SetColorTexture(0, 0, 0, BANNER_ALPHA)
		band.middle:SetHeight(size * BANNER_BAND)
		band.middle:Show()
		for side, high in pairs({ top = false, bottom = true }) do
			Gradient(band[side], "VERTICAL", high, 0, 0, 0, BANNER_ALPHA)
			band[side]:SetHeight(size * BANNER_EDGE)
			band[side]:Show()
		end
	end
	cue.picture:SetShown(picture and true or false)
	cue.look, cue.enter, cue.width, cue.height, cue.scale = look, enter, width, height, scale
	cue.barLook = cue.barSide and setmetatable({ letterboxSizeBy = "height", letterboxSize = cue.barShare,
		letterboxMotion = "slide" }, { __index = ns.LetterboxLook() })
end

-- How far cue is faded in age seconds in (0 to 1, before easing), and its
-- length.
local function Shown(cue, age)
	local look = cue.look
	local hold = (cue.enter and look.combatHoldIn or look.combatHoldOut) + (cue.typeTime or 0) + (cue.holdExtra or 0)
	local fadeIn = cue.pictured and PICTURE_IN or cue.banner and BANNER_IN or FADE_IN
	local fadeOut = cue.pictured and PICTURE_OUT or cue.banner and BANNER_OUT
		or (cue.reveal or cue.track or cue.type) and REVEAL_OUT or FADE_OUT
	local a
	if age < fadeIn then
		a = age / fadeIn
	elseif age > fadeIn + hold then
		a = 1 - (age - fadeIn - hold) / fadeOut
	else
		a = 1
	end
	return math.max(a, 0), fadeIn + hold + fadeOut
end

-- Draws cue age seconds in. Gives false once it's over (and hidden). Cut
-- short (cue.cutAt, cue.cutFrom: when, and how shown then), it fades out
-- from there in CUT_OUT.
local function Draw(cue, age)
	local look = cue.look
	local a, length = Shown(cue, age)
	local cut = 1
	if cue.cutAt then
		cut = 1 - (age - cue.cutAt) / CUT_OUT
		a = math.min(a, cue.cutFrom * cut)
	end
	if age >= length or cut <= 0 then
		cue.bars:Hide()
		cue.pulse:Hide()
		cue.over:Hide()
		return false
	end
	a = a * a * (3 - 2 * a)
	cue.over:Show()
	cue.over:SetAlpha(a)
	-- (Reveal: the window opening, eased out; the line drawing out with it.)
	local open = a
	if cue.reveal then
		open = 1 - (1 - math.min(age / REVEAL, 1)) ^ 4
		cue.clip:SetWidth(math.max(cue.clipWidth * open, 1))
	elseif cue.type then
		local ends = cue.typeEnds
		local n = math.min(#ends, math.floor(age / TYPE_EACH) + 1)
		cue.clip:SetWidth(math.max(ends[n] or 1, 1))
		open = n / math.max(#ends, 1)
	elseif cue.track then
		-- (Tracking in: the letters closing up, eased out; once together, the
		-- words whole, with their kerning and outline.)
		local t = math.min(age / TRACK, 1)
		open = 1 - (1 - t) ^ 3
		if cue.tracking then
			if t < 1 then
				LayLetters(cue, cue.trackFrom * (1 - open))
			else
				cue.tracking = false
				for i = 1, cue.letterCount do cue.letters[i]:Hide() end
				cue.text:SetAlpha(cue.textAlpha)
				for _, rim in ipairs(cue.text.rim) do rim:SetAlpha(1) end
				for _, bleed in ipairs(cue.text.bleed) do bleed:SetAlpha(BLEED_ALPHA) end
			end
		end
	end
	if cue.lineWidth then cue.line:SetWidth(math.max(cue.lineWidth * open, 0.01)) end
	if cue.late then
		local t = math.max(0, math.min((age - cue.lateFrom) / LATE_FOR, 1))
		t = t * t * (3 - 2 * t)
		for _, each in ipairs({ { cue.sub, cue.subAt }, { cue.meta, cue.metaAt } }) do
			local at = each[2]
			if at and each[1]:IsShown() then
				each[1]:SetAlpha(t)
				each[1]:SetPoint(at[1], at[2], at[3], at[4], at[5] - cue.rise * (1 - t))
			end
		end
	end
	local pulse = 0
	local strength = cue.enter and look.combatPulseIn or look.combatPulseOut
	if strength > 0 then
		pulse = age < PULSE_PEAK and age / PULSE_PEAK or math.max(0, 1 - (age - PULSE_PEAK) / (PULSE_GONE - PULSE_PEAK))
	end
	pulse = pulse * cut
	cue.pulse:SetShown(pulse > 0)
	cue.pulse:SetAlpha(pulse * strength)
	cue.bars:SetShown(cue.barSide ~= nil and cue.ownBar)
	if cue.barSide and cue.ownBar then
		local bars = cue.bars
		ns.DrawLetterbox(bars, cue.barLook, cue.width, cue.height, a, cue.scale)
		local other = cue.barSide == "TOP" and "bottom" or "top"
		bars[other]:Hide()
		bars[other .. "Feather"]:Hide()
		bars[other .. "Line"]:Hide()
		bars[cue.barSide == "TOP" and "top" or "bottom"]:Show()
	end
	return true
end

-- Plays cue on frame: its OnUpdate runs it to the end. look: a card's
-- (ns.CardLook). after: called once it's done (not if another card on
-- frame cuts it short).
local function Play(frame, look, enter, width, height, scale, boss, after)
	local cue = frame.cue or MakeCue(frame)
	Setup(cue, look, enter, width, height, scale, boss)
	local age = 0
	cue.cutAt = nil
	-- Cut short: a quick fade out from as shown as it is now.
	cue.cut = function()
		if cue.cutAt then return end
		cue.cutAt, cue.cutFrom = age, (Shown(cue, age))
	end
	Draw(cue, 0)
	frame:SetScript("OnUpdate", function(self, elapsed)
		age = age + elapsed
		if not Draw(cue, age) then
			self:SetScript("OnUpdate", nil)
			if after then after() end
		end
	end)
end

-- A card { name, sub, meta } (or a banner's picture: Setup's) in look (a
-- card's, Cards.lua's ns.CardLook), on frame (the screen's, or a preview's),
-- width x height, scale next to the real screen.
function ns.PlayCard(frame, look, width, height, scale, card, after)
	Play(frame, look, true, width, height, scale, card, after)
end

-- The card playing on frame cut short: a quick fade out from as shown now.
function ns.CutCard(frame)
	local cue = frame and frame.cue
	if cue and cue.cut and frame:GetScript("OnUpdate") then cue.cut() end
end

-- Going into a fight and coming out of it: the Combat card (its Show in row
-- read with the rules' entering or leaving true, and CineMode as the fight
-- began: cine), each as its tick says, and the fight's sound with it.
local fightStart, cineAtStart = 0, false
local function FightCard(enter, cine)
	if not ns.Setting(enter and "combatOnEnter" or "combatOnLeave") then return end
	local edge = enter and "enter" or "leave"
	ns.Cards.Fire("combat", {
		name = ns.CardWords(enter and "combatTextIn" or "combatTextOut"), edge = edge, cine = cine,
		sound = function() ns.PlayCombatCueSound(edge, cine) end, -- (CombatSoundRules.lua)
	})
end

-- Boss cards. A boss is told by the pull (ENCOUNTER_START: its name, plain)
-- or, before it, as an enemy elite in a dungeon or raid at a skull's level,
-- or on retail two or more levels over yours (the trash at yours, tested:
-- names and GUIDs there are secret even out of a fight, so no Journal match).
-- Each encounter's card shows once a run (a wipe doesn't bring it back). One
-- shown before a pull (target, near) holds the next until a boss dies, as
-- which boss it was can't be told; that boss's pull then has the usual card.
local PULL_GAP = 2      -- seconds the pull and the fight's start can be apart
local PRE_HOLD = 300    -- a card before a pull holds the next this long at most (no kill: not a boss)
local NEAR_EVERY = 0.5  -- seconds between looks at the plates for one near
local OUTSIDE_RESET = 600 -- back in after this long outside: a new run
local bossRun = { shown = {}, cardAt = -math.huge, preAt = -math.huge }

local function Plain(fn, ...)
	local ok, value = pcall(fn, ...)
	if ok and not (issecretvalue and issecretvalue(value)) then return value end
end

local function InsideInstance()
	local _, kind = GetInstanceInfo()
	return kind == "party" or kind == "raid"
end

-- Why a card showed or not, while /cine debug boss watch runs (it sets ns.BossCardLog).
local function BossLog(text)
	if ns.BossCardLog then ns.BossCardLog(text) end
end

-- The line under the name: the dungeon and its difficulty ("" for none).
local function InstanceLine()
	if not ns.db.combatBossSub then return "" end
	local name, kind, _, difficulty = GetInstanceInfo()
	if kind == "none" or type(name) ~= "string" or (issecretvalue and issecretvalue(name)) or name == "" then
		return ""
	end
	if type(difficulty) == "string" and not (issecretvalue and issecretvalue(difficulty)) and difficulty ~= "" then
		return name .. " · " .. difficulty
	end
	return name
end

-- "Boss 2 of 3" for an encounter, from the Journal where it knows ("" else).
local function BossNumber(encounterID)
	if not (ns.db.combatBossCount and EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex) then return "" end
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local ok, journal = pcall(EJ_GetInstanceForMap, mapID or 0)
	if not ok or not journal or journal == 0 then return "" end
	-- (The Journal's own choice put back after, in case its window is open.)
	local before = EJ_GetCurrentInstance and EJ_GetCurrentInstance()
	if EJ_SelectInstance then pcall(EJ_SelectInstance, journal) end
	local count, index = 0, nil
	while count < 40 do
		local okInfo, name, _, _, _, _, _, dungeonEncounter = pcall(EJ_GetEncounterInfoByIndex, count + 1, journal)
		if not okInfo or not name then break end
		count = count + 1
		if dungeonEncounter == encounterID then index = count end
	end
	if before and before ~= 0 and before ~= journal and EJ_SelectInstance then pcall(EJ_SelectInstance, before) end
	if index and index == count and count > 1 then return L["Final boss"] end
	return index and L["Boss %d of %d"]:format(index, count) or ""
end

-- A made-up boss card for the preview and the Test button (in an instance:
-- its own line under the name).
function ns.BossSampleCard()
	local sub = InstanceLine()
	if sub == "" and ns.db.combatBossSub then sub = L["The Deadmines"] .. " · " .. L["Normal"] end
	return { name = L["Edwin VanCleef"], sub = sub,
		meta = ns.db.combatBossCount and L["Boss %d of %d"]:format(5, 5) or "" }
end

-- Whether unit looks like a boss before its pull (plain answers only), and why.
local function LooksLikeBoss(unit)
	if not InsideInstance() then return false, "not in a dungeon or raid" end
	local rank = ns.EnemyNPCRank(unit)
	if rank ~= "elite" then return false, "rank " .. (Plain(tostring, rank) or "secret") end
	local level = Plain(UnitLevel, unit)
	if level == -1 or Plain(UnitClassification, unit) == "worldboss" then return true, "skull level or world boss" end
	local mine = UnitLevel("player")
	if ns.isRetail and type(level) == "number" and type(mine) == "number" and level >= mine + 2 then
		return true, ("level %d, yours %d"):format(level, mine)
	end
	return false, ("elite at level %s, yours %s: not a skull%s"):format(tostring(level), tostring(mine),
		ns.isRetail and " or 2 over" or "")
end

-- Whether a boss card may show now, by tick (combatBossPull...), the Boss
-- row and its Show in row (Cards.lua), and why not.
local function BossAllowed(db, tick)
	if not db[tick] then return false, tick .. " off" end
	return ns.CardAllowed("boss", "enter", ns.lastCinematic and true or false)
end

-- A boss's card on the screen (already allowed: BossAllowed), the pull's
-- sound with it unless quiet (a card before the pull: no fight yet).
local function BossCard(card, cine, quiet)
	card.edge, card.cine = "enter", cine
	if not quiet then
		card.sound = function() ns.PlayCombatCueSound("enter", cine) end
	end
	ns.Cards.Fire("boss", card, true)
end

-- A card before the pull, for unit (target, a plate): once until a boss dies.
local function CardBeforePull(unit, tick)
	local db = ns.db
	if not db then return end
	local who = (Plain(UnitName, unit) or "a secret name") .. " (" .. tick .. ")"
	local why
	if InCombatLockdown() then
		why = "in combat"
	elseif bossRun.encounterOn then
		why = "an encounter is on"
	elseif GetTime() - bossRun.preAt < PRE_HOLD then
		why = ("held %.0fs more: a card already showed before a pull, no boss killed since"):format(
			PRE_HOLD - (GetTime() - bossRun.preAt))
	end
	local looks, how
	if not why then
		looks, how = LooksLikeBoss(unit)
		if not looks then why = "not boss-like: " .. how end
	end
	if not why then
		local allowed, no = BossAllowed(db, tick)
		if not allowed then why = no end
	end
	if why then
		BossLog(("no card for %s: %s"):format(who, why))
		return
	end
	BossLog(("card before the pull for %s: %s"):format(who, how))
	bossRun.preAt = GetTime()
	BossCard({ name = (UnitName(unit)), sub = InstanceLine(), meta = "" }, ns.lastCinematic and true or false, true)
end

-- Near: the plates looked at twice a second, only out of a fight in an instance.
local nearLook = CreateFrame("Frame")
nearLook:Hide()
local nearWait = 0
nearLook:SetScript("OnUpdate", function(_, elapsed)
	nearWait = nearWait - elapsed
	if nearWait > 0 then return end
	nearWait = NEAR_EVERY
	local db = ns.db
	if not (db and db.combatBossNear and ns.CardOn("boss")) or InCombatLockdown() or bossRun.encounterOn
		or GetTime() - bossRun.preAt < PRE_HOLD then
		return
	end
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and Plain(CheckInteractDistance, unit, 4) == true and LooksLikeBoss(unit) then
			CardBeforePull(unit, "combatBossNear")
			return
		end
	end
end)

-- A new run: another instance, or back in after long outside.
local function EnteredWorld()
	local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	local inside = InsideInstance()
	nearLook:SetShown(inside)
	if not inside then
		bossRun.leftAt = bossRun.leftAt or GetTime()
		return
	end
	if instanceID ~= bossRun.instance or GetTime() - (bossRun.leftAt or GetTime()) > OUTSIDE_RESET then
		bossRun.shown, bossRun.preAt, bossRun.encounterOn = {}, -math.huge, nil
		BossLog(("new run in instance %s: every boss's card can show again"):format(tostring(instanceID)))
	end
	bossRun.instance, bossRun.leftAt = instanceID, nil
end

-- The pull: its card in place of Entering combat's, the first time this run.
local function EncounterStart(db, encounterID, name)
	bossRun.encounterOn = true
	local key = (issecretvalue and issecretvalue(encounterID)) and "?" or encounterID
	local who = ("%s (encounter %s)"):format(Plain(tostring, name) or "a secret name", tostring(key))
	if bossRun.shown[key] then
		BossLog(("no card at the pull of %s: its card showed already this run"):format(who))
		return
	end
	bossRun.shown[key] = true
	-- (Its card already showed before the pull: the usual card.)
	if GetTime() - bossRun.preAt < PRE_HOLD then
		BossLog(("no card at the pull of %s: a card showed before it (%.0fs ago), so the usual card"):format(who,
			GetTime() - bossRun.preAt))
		return
	end
	local allowed, no = BossAllowed(db, "combatBossPull")
	if not allowed then
		BossLog(("no card at the pull of %s: %s"):format(who, no))
		return
	end
	local card = { name = name ~= nil and name or "", sub = InstanceLine(),
		meta = key ~= "?" and BossNumber(encounterID) or "", at = GetTime() }
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then
		-- (Already fighting, a pull from range: over the card playing.)
		BossLog(("card at the pull of %s, already in combat: plays now (%s)"):format(who, card.meta))
		bossRun.cardAt = GetTime()
		BossCard(card, ns.lastCinematic and true or false)
	else
		BossLog(("card at the pull of %s: waits for combat to start (%s)"):format(who, card.meta))
		bossRun.pending = card
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
for _, event in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END" }) do
	pcall(watcher.RegisterEvent, watcher, event) -- (each client that has them)
end
watcher:SetScript("OnEvent", function(_, event, ...)
	local db = ns.db
	if not db then
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		ns.Cards.Cut("combat") -- (a respite still showing)
		fightStart, cineAtStart = GetTime(), ns.lastCinematic and true or false
		local card = bossRun.pending
		bossRun.pending = nil
		if card then
			BossLog(("combat started %.2fs after the pull: %s"):format(GetTime() - card.at,
				GetTime() - card.at < PULL_GAP and "its card plays" or "too late for its card, the usual card"))
		end
		if card and GetTime() - card.at < PULL_GAP then
			bossRun.cardAt = GetTime()
			BossCard(card, cineAtStart)
		elseif GetTime() - bossRun.cardAt >= PULL_GAP then
			FightCard(true, cineAtStart)
		else
			BossLog("combat started: no Entering combat card, a boss card just played")
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- (The Combat card going in or a boss's still showing: cut short.)
		ns.Cards.Cut("combat")
		ns.Cards.Cut("boss")
		if GetTime() - fightStart >= db.combatMinFight then
			FightCard(false, cineAtStart)
		end
	elseif event == "ENCOUNTER_START" then
		EncounterStart(db, ...)
	elseif event == "ENCOUNTER_END" then
		local _, _, _, _, success = ...
		bossRun.encounterOn = nil
		if Plain(tostring, success) == "1" then bossRun.preAt = -math.huge end -- (a boss down: the next may show before its pull)
		BossLog(("encounter ended, success %s: %s"):format(Plain(tostring, success) or "secret",
			Plain(tostring, success) == "1" and "the next boss's card may show before its pull" or "a card before a pull stays held"))
		-- (The Boss event's sounds for a kill or a wipe.)
		local result = Plain(tostring, success)
		if ns.CardOn("boss") and result then
			ns.PlayCombatCueSound(result == "1" and "kill" or "wipe", ns.lastCinematic and true or false)
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		if db.combatBossTarget and ns.CardOn("boss") and UnitExists("target") then
			CardBeforePull("target", "combatBossTarget")
		end
	else
		EnteredWorld()
	end
end)
