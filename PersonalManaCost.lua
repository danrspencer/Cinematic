-- Mana cost: while you cast a spell that costs mana, the mana it will take
-- shows as a pale stretch at the end of your mana, from the fill's right
-- edge leftwards: what's left after the cast is the fill to its left.
-- On your mana under your character (the personal resource display's power
-- bar while mana is your power, else our own mana bar under it while that's
-- in use: PersonalMana.lua), and on your player frame's (its mana bar, else
-- the game's mana bar under it). Each on to start with: the UI Manager's
-- Personal Resources page turns them off (manaCostDisplay, manaCostPortrait).
-- The game's own cost on the player frame (retail's) is faded while ours
-- is on there.
-- Mana and its max can be secret in fights: the stretch is a status bar of
-- its own, drawn reversed from the fill's right edge and given them as they
-- are, clipped to the bar (a cost over what you have runs out at its left).
-- Some casts take their mana as they start (seen on Forever: an arcane
-- mage's casts): once your mana has dropped by the cost since the cast
-- began, it's paid and the stretch goes (else it took the cost twice).
-- The drop can reach us a little before the cast's start (a Discipline
-- priest's Smite, 2026-11-09), and your mana can't always be read: a spell
-- seen paying at its start is remembered (by character and by name, so
-- every rank of it: chardb.manaAtStart) and its casts show no stretch from
-- then on. (A cost a buff takes away: the game's cost for it reads 0 if the
-- game counts it, and no stretch; a spell paying at its start shows none
-- either way.)

local _, ns = ...

local DEFAULTS = ns.DEFAULTS
DEFAULTS.manaCostDisplay = true     -- a cast's mana cost on your mana under your character
DEFAULTS.manaCostPortrait = true    -- ...and on your player frame's

local display = _G.PersonalResourceDisplayFrame
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local SHADE = { 1, 1, 1, 0.5 } -- the stretch: white over the fill, half seen
local KEYS = { display = "manaCostDisplay", portrait = "manaCostPortrait" }

local overlays = setmetatable({}, { __mode = "k" }) -- bar -> its overlay
local gameCost = setmetatable({}, { __mode = "k" }) -- the game's own cost pieces -> true, while faded for ours
local casting -- the cast going on, while it costs mana (its guid, or true)
local cost -- ...its mana cost
local paid -- ...true once its mana was taken (some take it as they start)
local startMana -- your mana as the cast began (nil: secret)
local lastMana -- your mana at its last change
local changes = {} -- your mana's changes this last second: { at, before }
local castSpell -- the cast's spell, by name: all its ranks (nil: unreadable)
local stoppedAt -- when a cast of ours that pays at its end last ended (its mana comes then)
local lastStart -- for /cine debug: how the last cast's start was read
local EARLY = 0.5 -- seconds: a drop this soon before a cast's start can be its cost

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- Trace (while the log takes detail: always in the dev copy, else /cine
-- debug record): every cast event and mana change around a cast, in the
-- order they reach us, with what each read, to see why a cast's paid or not.
local traceUntil = 0 -- power changes are traced until then (a little past a cast)
local function Shown(value)
	if value == nil then return "nil" end
	return Readable(value) and tostring(value) or "secret"
end
local function Trace(text)
	if ns.LogDetailOn and ns.LogDetailOn() and ns.Log then
		ns.Log("manacost", ("%.3f %s"):format(GetTime(), text))
	end
end

-- The bars your mana is on now, by where: display (under your character)
-- and portrait (your player frame). Either can be nil. (Power type
-- secret: maybe mana.)
local function ManaBars()
	local powerType = UnitPowerType("player")
	local isMana = not Readable(powerType) or powerType == MANA
	local under
	if display then
		if ns.PersonalManaShown and ns.PersonalManaShown() then
			under = ns.PersonalManaBar()
		elseif isMana then
			under = display.PowerBar
		end
	end
	local portrait
	local frame = _G.PlayerFrame
	if frame then
		if isMana then
			portrait = frame.manabar or frame.ManaBar or _G.PlayerFrameManaBar
		else
			local alternate = _G.AlternatePowerBar or _G.PlayerFrameAlternateManaBar
			if alternate and ns.Flag(alternate:IsShown()) then portrait = alternate end
		end
	end
	return { display = under, portrait = portrait }
end
ns.PlayerManaBars = ManaBars

-- A spell's mana cost (nil: none, or it can't be read). The game's list
-- has an entry per power it costs; some only with an aura you have.
local function ManaCost(spellID)
	local getCost = C_Spell and C_Spell.GetSpellPowerCost or _G.GetSpellPowerCost
	if not (getCost and spellID) then return end
	local ok, found = pcall(function()
		for _, each in ipairs(getCost(spellID) or {}) do
			local aura = each.requiredAuraID
			if each.type == MANA and (not aura or aura == 0 or each.hasRequiredAura) then
				return each.cost
			end
		end
	end)
	if ok and found ~= nil and (not Readable(found) or found > 0) then return found end
end

local function Overlay(bar)
	local overlay = overlays[bar]
	if overlay then return overlay end
	-- (A clipping frame the bar's size, and in it the stretch: as wide as the
	-- bar, its right edge on the fill's.)
	overlay = CreateFrame("Frame", nil, bar)
	overlay:SetAllPoints()
	overlay:SetClipsChildren(true)
	overlay:SetFrameLevel(bar:GetFrameLevel() + 1)
	local stretch = CreateFrame("StatusBar", nil, overlay)
	stretch:SetReverseFill(true)
	stretch:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	stretch:SetStatusBarColor(SHADE[1], SHADE[2], SHADE[3], SHADE[4])
	overlay.stretch = stretch
	overlay:Hide()
	overlays[bar] = overlay
	return overlay
end

-- The game's own cost on a bar (retail's player frame): its pieces.
local function GameCost(bar)
	local frame = _G.PlayerFrame
	local pieces = {}
	for _, piece in ipairs({ bar.ManaCostPredictionBar or false,
		frame and bar == (frame.manabar or frame.ManaBar) and frame.myManaCostPredictionBar or false }) do
		if type(piece) == "table" and piece.SetAlpha then pieces[#pieces + 1] = piece end
	end
	return pieces
end

-- The stretch on one bar, for the cast going on (false: it can't be).
local function Draw(bar)
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not fill then return false end
	local overlay = Overlay(bar)
	local stretch = overlay.stretch
	local ok = pcall(function()
		stretch:SetWidth(bar:GetWidth())
		stretch:ClearAllPoints()
		stretch:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
		stretch:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
		stretch:SetMinMaxValues(0, UnitPowerMax("player", MANA))
		stretch:SetValue(cost)
	end)
	overlay:SetShown(ok)
	return ok
end

-- Drawn again: the cast starting or ending, your mana or its bars changing,
-- the page's settings.
local function Update()
	local db = ns.GetDB()
	local bars = ManaBars()
	local drawn, mute = {}, {}
	for where, key in pairs(KEYS) do
		local bar = bars[where]
		if bar and db and db[key] and ns.PersonalResourcesOn(db) then
			if casting and not paid and Draw(bar) then drawn[bar] = true end
			for _, piece in ipairs(GameCost(bar)) do mute[piece] = true end
		end
	end
	for bar, overlay in pairs(overlays) do
		if not drawn[bar] then overlay:Hide() end
	end
	-- (The game's own faded where ours is on, back elsewhere.)
	for piece in pairs(mute) do
		gameCost[piece] = true
		piece:SetAlpha(0)
	end
	for piece in pairs(gameCost) do
		if not mute[piece] then
			gameCost[piece] = nil
			piece:SetAlpha(1)
		end
	end
	-- (And the mana after the cast, by the same cast: PersonalManaText.lua.)
	if ns.UpdateManaAfter then ns.UpdateManaAfter(casting and not paid and cost or nil, bars) end
end
ns.UpdateManaCost = Update

-- Your mana now (nil: secret), and on a change, whether this cast's cost
-- was taken: down by at least half of it since the cast began (half:
-- regen ticks in between).
local function ReadMana()
	local mana = UnitPower("player", MANA)
	if Readable(mana) then return mana end
end

-- The spells seen paying at their start (name -> true).
local function AtStart()
	local char = ns.chardb
	if not char then return {} end
	char.manaAtStart = char.manaAtStart or {}
	return char.manaAtStart
end

local function SetPaid()
	paid = true
	if castSpell then AtStart()[castSpell] = true end
	Trace("PAID (seen paying at its start): " .. Shown(castSpell))
end

local function CheckPaid()
	if paid or not casting or not startMana or not Readable(cost) then return end
	local mana = ReadMana()
	if mana and startMana - mana >= cost * 0.5 then SetPaid() end
end

local function Start(castGUID, spellID)
	cost = ManaCost(spellID)
	casting = type(cost) == "number" and (castGUID or true) or nil
	if not casting then cost = nil end
	paid = nil
	local name = Readable(spellID) and (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
		or _G.GetSpellInfo and (_G.GetSpellInfo(spellID))) or nil
	castSpell = Readable(name) and name ~= "" and name or nil
	-- (Taken just before the cast's start reached us: the most mana you had
	-- this last half second, even with a regen tick after the drop (heals,
	-- 2026-11-10). Not a drop with the end of a cast that paid at its end.)
	local now = GetTime()
	startMana = ReadMana()
	local early, ago = false, nil
	if startMana then
		for _, change in ipairs(changes) do
			if now - change.at <= EARLY and change.before > startMana
				and not (stoppedAt and math.abs(change.at - stoppedAt) <= 0.2) then
				startMana, early, ago = change.before, true, now - change.at
			end
		end
	end
	lastStart = { cost = Readable(cost) and cost or nil, readable = startMana ~= nil,
		ago = ago or (changes[#changes] and now - changes[#changes].at) or nil, early = early }
	local learned = casting and castSpell and AtStart()[castSpell] and true or false
	if learned then paid = true end
	CheckPaid()
	traceUntil = now + 2
	local seen = {}
	for _, change in ipairs(changes) do
		seen[#seen + 1] = ("%.3fs ago from %s"):format(now - change.at, Shown(change.before))
	end
	Trace(("START %s guid %s: cost %s, mana now %s, last event mana %s, changes [%s], start mana %s%s, learned %s, stopped %s, paid %s")
		:format(Shown(castSpell), Shown(castGUID), Shown(cost), Shown(UnitPower("player", MANA)), Shown(lastMana),
			table.concat(seen, "; "), Shown(startMana), early and " (taken before)" or "", tostring(learned),
			stoppedAt and ("%.3fs ago"):format(now - stoppedAt) or "never", tostring(paid)))
	Update()
	-- (What's drawn on each mana bar: ours, and anything else on it, an
	-- addon's or the game's, by name.)
	if ns.LogDetailOn and ns.LogDetailOn() then
		for where, bar in pairs(ManaBars()) do
			local others = {}
			for _, child in ipairs({ bar:GetChildren() }) do
				if child ~= overlays[bar] and ns.Flag(child:IsShown()) then
					local ok, name = pcall(child.GetDebugName or child.GetName, child)
					others[#others + 1] = ok and Readable(name) and name or "unnamed"
				end
			end
			Trace(("%s bar %s: ours %s, others shown [%s]"):format(where, ns.DescribeManaBar(bar),
				overlays[bar] and ns.Flag(overlays[bar]:IsShown()) and "shown" or "hidden", table.concat(others, ", ")))
		end
	end
end

-- (Only for the cast that's on: some spells go off on their own mid-cast.
-- A cast whose guid can't be read: taken as it.)
local function Stop(castGUID)
	if not casting then return end
	if Readable(castGUID) and Readable(casting) and castGUID ~= casting then return end
	-- (Only a cast of ours yet to pay: a failed key press or another spell's
	-- end hid the drop of the next cast's cost.)
	if not paid then stoppedAt = GetTime() end
	casting, cost, paid, startMana, castSpell = nil, nil, nil, nil, nil
	Update()
end

-- For /cine debug plates: which bar each is on.
function ns.DescribeManaBar(bar)
	if bar == nil then return "none" end
	if display and bar == display.PowerBar then return "the power bar" end
	if ns.PersonalManaBar and bar == ns.PersonalManaBar() then return "our mana bar" end
	local ok, name = pcall(bar.GetName, bar)
	return ok and Readable(name) and name or "the player frame's"
end

function ns.DescribeManaCost()
	local db = ns.GetDB() or {}
	local bars = ManaBars()
	local learned = 0
	for _ in pairs(AtStart()) do learned = learned + 1 end
	local last = lastStart and ("; last cast: cost %s, mana %s, mana changed %s before, %s"):format(
		tostring(lastStart.cost or "unread"), lastStart.readable and "read" or "secret",
		lastStart.ago and ("%.2fs"):format(lastStart.ago) or "never",
		lastStart.early and "taken just before" or "not taken before") or ""
	return ("mana cost: resource bar %s (%s), player frame %s (%s), casting %s, cost %s, %d spells pay at start%s"):format(
		db.manaCostDisplay and "on" or "off", ns.DescribeManaBar(bars.display),
		db.manaCostPortrait and "on" or "off", ns.DescribeManaBar(bars.portrait),
		casting and (paid and "a spell (paid at its start)" or "a spell") or "nothing", Readable(cost) and tostring(cost) or cost and "secret" or "none",
		learned, last)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
watcher:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
watcher:RegisterUnitEvent("UNIT_MAXPOWER", "player")
watcher:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
watcher:SetScript("OnEvent", function(_, event, _, arg2, spellID)
	if event:find("^UNIT_SPELLCAST_") and event ~= "UNIT_SPELLCAST_START" then
		traceUntil = GetTime() + 2
		Trace(("%s guid %s (ours %s): mana %s, casting info %s, paid %s"):format(event:sub(16), Shown(arg2),
			Shown(casting), Shown(UnitPower("player", MANA)), Shown((UnitCastingInfo("player"))), tostring(paid)))
	elseif event == "UNIT_POWER_FREQUENT" and GetTime() < traceUntil then
		Trace(("power %s: mana %s, last %s, casting %s, start mana %s, paid %s"):format(Shown(arg2),
			Shown(UnitPower("player", MANA)), Shown(lastMana), casting and "yes" or "no", Shown(startMana), tostring(paid)))
	end
	if event == "UNIT_SPELLCAST_START" then
		Start(arg2, spellID)
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		-- (A second cast failing, queued while one is on: that one goes on.)
		-- (Parentheses: Classic Era returns nothing at all when not casting.)
		if type((UnitCastingInfo("player"))) == "nil" then Stop(arg2) end
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_SUCCEEDED" then
		Stop(arg2)
	elseif event == "PLAYER_ENTERING_WORLD" or event == "UNIT_DISPLAYPOWER" then
		-- (A frame on: our mana bar comes or goes on these too, PersonalMana.lua.)
		C_Timer.After(0, Update)
	else
		-- (Your mana changing: drawn again. arg2: the power's token; a secret
		-- one maybe mana.)
		if event == "UNIT_POWER_FREQUENT" and (not Readable(arg2) or arg2 == "MANA") then
			local mana, now = ReadMana(), GetTime()
			if mana ~= lastMana then
				if mana and lastMana then changes[#changes + 1] = { at = now, before = lastMana } end
				lastMana = mana
				while changes[1] and now - changes[1].at > 1 do table.remove(changes, 1) end
			end
		end
		if casting and (event ~= "UNIT_POWER_FREQUENT" or not Readable(arg2) or arg2 == "MANA") then
			CheckPaid()
			Update()
		end
	end
end)
