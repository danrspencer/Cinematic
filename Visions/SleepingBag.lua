-- The Sleeping bag card (the Cards page's Sleeping bag row: cardSleepBagOn).
-- Lying in a Cozy Sleeping Bag gives Well-Rested a stack about every minute,
-- up to 3 (more experience with each). While you're in it (its Resting aura
-- on you), a line in the middle of the top letterbox bar shows how many you
-- have, "Well-Rested 1/3", and one bar for the timer: a third of it for
-- each stack, the next one's third filling up as its minute goes (at 1/3, a
-- third full). A new stack makes it flash. At 3/3 it says Fully rested for a
-- moment and fades; getting up (Resting gone) fades it too. With no
-- letterbox up: just inside the top of the screen. Its font and color are
-- its row's look (the Style tab), its Show in row says where it may show.
-- Every change of the two auras goes in the log ("sleepbag"), to see what
-- the game says of each stack's time; /cine debug sleepbag says all of it now.

local _, ns = ...
local L = ns.L

ns.DEFAULTS.cardSleepBagOn = true

local WELL_RESTED = 429959  -- Well-Rested's spell ID (tested: the saved log's buff lists)
local MAX = 3               -- stacks Well-Rested goes up to
local STACK_TIME = 60       -- seconds in the bag a stack takes (the Resting aura's time, if it doesn't say)
local FADE = 0.6            -- seconds a fade in or out takes
local CHECK = 0.5           -- seconds between asks of whether it may show (and its place)
local FULL_HOLD = 5         -- seconds Fully rested stays before it fades
local PULSE = 0.9           -- seconds a new stack's flash takes to fade
local LOW = 0.025           -- with no bar: its middle this far under the top, a share of the screen's height
local TEST_STEP = 4         -- the Test's seconds a stack
local OUTLINES = { [0] = "", [1] = "OUTLINE", [2] = "THICKOUTLINE" }

local function Number(value)
	if type(value) == "number" and not (issecretvalue and issecretvalue(value)) then
		return value
	end
end
local function Text(value)
	if type(value) == "string" and not (issecretvalue and issecretvalue(value)) then
		return value
	end
end

-- The bag's use is Unroll Bag (429961, tested: the item's spell), a cast; the
-- Resting aura comes after it, an ID of its own nothing tells. So it's
-- learned: the buff new on you within LEARN_TIME seconds of Unroll Bag (in
-- the saved settings: sleepBagRestingID), else by its name in English.
local UNROLL = 429961
local LEARN_TIME = 5
local RESTING_EN = "Resting"

-- Your buffs now, each { id, name, count, duration, ends } (what the game
-- will say: nil where it won't).
local function Buffs()
	local list = {}
	for i = 1, 40 do
		local ok, id, name, count, duration, ends = pcall(function()
			if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
				local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
				if not aura then return end
				return aura.spellId, aura.name, aura.applications, aura.duration, aura.expirationTime
			end
			local name, _, count, _, duration, ends, _, _, _, id = UnitBuff("player", i)
			return id, name, count, duration, ends
		end)
		if not ok then return list, true end -- (can't be read now: a fight)
		if id == nil and name == nil then break end
		list[#list + 1] = { id = Number(id), name = Text(name), count = Number(count),
			duration = Number(duration), ends = Number(ends) }
	end
	return list
end

-- The Resting aura's ID: the learned one, else the buff named Resting (in
-- English), learned then too. Nil till then.
local function RestingID()
	local saved = ns.db and Number(ns.db.sleepBagRestingID)
	if saved then return saved end
	if not GetLocale():match("^en") then return nil end
	for _, buff in ipairs((Buffs())) do
		if buff.name == RESTING_EN and buff.id then
			if ns.db then ns.db.sleepBagRestingID = buff.id end
			ns.Log("sleepbag", ("Resting aura learned by its name: %d"):format(buff.id))
			return buff.id
		end
	end
end

-- After Unroll Bag: the buffs you had, to tell the new one (Resting) from them.
local learn -- { at = GetTime(), had = { [id] = true } }
local function Learn()
	if not learn then return end
	if GetTime() - learn.at > LEARN_TIME then
		ns.Log("sleepbag", "Unroll Bag: no new buff within " .. LEARN_TIME .. " s")
		learn = nil
		return
	end
	local now = GetTime()
	for _, buff in ipairs((Buffs())) do
		-- (New since the cast, or put on as it went off: on you already as the
		-- cast's event came, its time started since.)
		local fresh = buff.duration and buff.duration > 0 and buff.ends
			and buff.duration - (buff.ends - now) <= now - learn.at + 1.5
		if buff.id and (not learn.had[buff.id] or fresh) and buff.id ~= WELL_RESTED then
			if ns.db then ns.db.sleepBagRestingID = buff.id end
			ns.Log("sleepbag", ("Resting aura learned after Unroll Bag: %d %s, %s s"):format(buff.id,
				tostring(buff.name), tostring(buff.duration)))
			learn = nil
			return
		end
	end
end
local function Unrolled()
	learn = { at = GetTime(), had = {} }
	for _, buff in ipairs((Buffs())) do
		if buff.id then learn.had[buff.id] = true end
	end
	ns.Log("sleepbag", "Unroll Bag cast: watching for the Resting aura")
	C_Timer.After(LEARN_TIME + 0.1, Learn)
end

-- Well-Rested's name in the game's language.
local wellRestedName
local function WellRestedName()
	if not wellRestedName then
		local ok, name = pcall(function()
			if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(WELL_RESTED) end
			return (GetSpellInfo(WELL_RESTED))
		end)
		wellRestedName = ok and Text(name) or nil
	end
	return wellRestedName or L["Well-Rested"]
end

-- An aura of yours: whether you have it, its stacks, its length and when it
-- ends (nil where the game won't say). By ID where the game can look one up,
-- else by name.
local function Aura(id, name)
	if id and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if not ok then return nil end -- (can't be read now: a fight)
		if type(aura) ~= "table" then return false end
		local okRead, count, duration, ends = pcall(function()
			return aura.applications, aura.duration, aura.expirationTime
		end)
		if not okRead then return true end
		return true, Number(count), Number(duration), Number(ends)
	end
	if id then
		local list, unread = Buffs()
		if unread then return nil end
		for _, buff in ipairs(list) do
			if buff.id == id then return true, buff.count, buff.duration, buff.ends end
		end
		if not name then return false end
	end
	if name and AuraUtil and AuraUtil.FindAuraByName then
		local ok, found, _, count, _, duration, ends = pcall(AuraUtil.FindAuraByName, name, "player", "HELPFUL")
		if not ok then return nil end
		if found == nil then return false end
		return true, Number(count), Number(duration), Number(ends)
	end
	return false
end

-- What the game says now: in the bag (Resting), and Well-Rested's stacks
-- and end.
local state = { inBag = false, stacks = 0 }
local lastRise -- when the stacks last went up (the next one's due STACK_TIME on, if Resting doesn't say)
local fullAt   -- when 3/3 was first seen in this stay in the bag
local pulseAt     -- when a new stack last made the bar flash
local logged      -- the last line logged (only changes logged)

local Start -- (below)

local function Read()
	Learn()
	local id = RestingID()
	local inBag, _, restDuration, restEnds = false, nil, nil, nil
	if id then inBag, _, restDuration, restEnds = Aura(id) end
	local has, count, duration, ends = Aura(WELL_RESTED, WellRestedName())
	if inBag == nil or has == nil then return end -- (couldn't be read: kept as it was)
	local now = GetTime()
	local stacks = has and math.max(1, count or 1) or 0
	if inBag and not state.inBag then
		fullAt = nil -- (a new stay in the bag)
		lastRise = now
	end
	if stacks > state.stacks and state.inBag ~= nil then
		lastRise = now
		if inBag then pulseAt = now end
	end
	if inBag and stacks >= MAX and not fullAt then fullAt = now end
	state.inBag, state.stacks, state.duration, state.ends = inBag and true or false, stacks, duration, ends
	state.restDuration, state.restEnds = restDuration, restEnds
	local line = ("in bag %s (Resting %s: %s s of %s); Well-Rested %d/%d, %s s of %s"):format(tostring(inBag),
		tostring(id), restEnds and ("%.1f"):format(restEnds - now) or "?", tostring(restDuration),
		stacks, MAX, ends and ("%.0f"):format(ends - now) or "?", tostring(duration))
	-- (Only what changed: the time left moving on doesn't count.)
	local key = ("%s|%d|%s|%s"):format(tostring(inBag), stacks, ends and math.floor(ends + 0.5) or "?",
		restEnds and math.floor(restEnds + 0.5) or "?")
	if key ~= logged then
		logged = key
		ns.Log("sleepbag", line)
	end
	if inBag then Start() end
end

-- Camp Benefits (Emote Vision's card of it, its Show a timer while you rest:
-- ns.CampTimerOn): resting by a Welcoming Campfire for a minute gives it
-- (Campfire.lua). The same line, "Camp Benefits" and the bar filling over
-- that minute from when you sat, kneeled or lay down by the fire (the cursor
-- on it, CAMPFIRE_REST, then resting); full and flashing as it arrives
-- (CAMP_BENEFITS). Up before it: gone, from empty next time.
local CAMP_TIME = 60 -- seconds by the fire Camp Benefits takes
local CAMP_TEST = 8  -- the Test's
local camp = { byFire = false } -- since: when you sat by it; gotAt: when Camp Benefits came
local function CampWanted() return ns.CampTimerOn ~= nil and ns.CampTimerOn() end

-- The card's Test (the Cards page's Test button: Cards.lua's ns.CardTest):
-- a made-up stay in the bag, a stack each TEST_STEP seconds, shown wherever
-- (kind "camp": a made-up rest by the fire).
local test -- { start = GetTime(), kind = "bag" or "camp" }
local function TestLength()
	return (test.kind == "camp" and CAMP_TEST or MAX * TEST_STEP) + FULL_HOLD
end
local function TestState()
	local gone = GetTime() - test.start
	local stacks = math.min(MAX, math.floor(gone / TEST_STEP))
	return stacks, test.start + 7200, test.start + (stacks + 1) * TEST_STEP
end

-- The stacks, Well-Rested's end and the next stack's time (nil at 3/3).
local function Now()
	if test then
		local stacks, ends, nextAt = TestState()
		return stacks, ends, stacks < MAX and nextAt or nil
	end
	local nextAt
	if state.stacks < MAX then
		local rest = state.restDuration
		if state.restEnds and rest and rest > 10 and rest <= 2 * STACK_TIME then
			nextAt = state.restEnds
		elseif lastRise then
			nextAt = lastRise + STACK_TIME
			while nextAt < GetTime() do nextAt = nextAt + STACK_TIME end
		end
	end
	return state.stacks, state.ends, nextAt
end

local frame = CreateFrame("Frame", nil, UIParent)
frame:SetFrameStrata("BACKGROUND")
frame:SetFrameLevel(3) -- (over the letterbox: Effects.lua's, level 2)
frame:EnableMouse(false)
frame:SetSize(10, 10)
frame:Hide()
if ns.AddOverlay then ns.AddOverlay(frame) end -- (stays up with Hide the UI, as the letterbox)

local function NewText()
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetJustifyH("LEFT")
	return text
end
local label = NewText()
-- The timer: one bar, a third of it for each stack (thin marks between).
local bar = CreateFrame("Frame", nil, frame)
bar.track = bar:CreateTexture(nil, "ARTWORK")
bar.track:SetAllPoints()
bar.fill = bar:CreateTexture(nil, "OVERLAY")
bar.fill:SetPoint("TOPLEFT")
bar.fill:SetPoint("BOTTOMLEFT")
bar.ticks = {}
for i = 1, MAX - 1 do
	local tick = bar:CreateTexture(nil, "OVERLAY", nil, 2)
	tick:SetColorTexture(0, 0, 0, 0.8)
	bar.ticks[i] = tick
end
bar.flash = bar:CreateTexture(nil, "OVERLAY", nil, 7)
bar.flash:SetAllPoints()
bar.flash:SetColorTexture(1, 1, 1, 1)
bar.flash:SetBlendMode("ADD")
bar.flash:SetAlpha(0)

-- (Told to Inspect, Why.lua, as it first shows: Why.lua loads after this,
-- and the words are in your language by then.)
local registered = false
local function Register()
	if registered or not ns.WhyRegister then return end
	registered = true
	ns.WhyRegister(frame, L["Sleeping bag"], "Card Vision", {
		L["The Sleeping bag card is on: you're in a sleeping bag, its Well-Rested stacks and their time"] })
end

-- Well-Rested's time left as the buff shows it ("2 h", "58 m").
local function Left(seconds)
	seconds = math.max(0, seconds)
	if SecondsToTimeAbbrev then
		local ok, text = pcall(function()
			local format, value = SecondsToTimeAbbrev(seconds)
			return format:format(value)
		end)
		if ok and type(text) == "string" then return text end
	end
	if seconds >= 3600 then return ("%d h"):format(math.ceil(seconds / 3600)) end
	if seconds >= 60 then return ("%d m"):format(math.ceil(seconds / 60)) end
	return ("%d s"):format(math.ceil(seconds))
end
-- The next stack's time: "0:42".
local function Clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- The look (its row's: font, outline, shadow, color) and size, set again only
-- when they change. (SetFont after SetText shows Cyrillic as boxes: the
-- words are set again after.)
local fontKey, size = nil, 14
local function Style(barHeight)
	local look = ns.CardLook("sleepBag")
	local scale = tonumber(look.combatBarScale) or 0.5
	size = barHeight and barHeight >= 8 and barHeight * scale or 14
	size = math.floor(math.max(10, math.min(24, size)) + 0.5)
	local file = ns.StyleFontFile(look.combatFont) or (GameFontHighlight:GetFont())
	local outline = OUTLINES[tonumber(look.combatOutline) or 0] or ""
	local r, g, b = look.combatInR or 1, look.combatInG or 0.82, look.combatInB or 0
	local key = table.concat({ file, size, outline, look.combatShadow or "", r, g, b }, "|")
	if key == fontKey then return end
	fontKey = key
	local was = label:GetText()
	label:SetFont(file, size, outline)
	if ns.SetTextShadow then ns.SetTextShadow(label, look.combatShadow) end
	label:SetText(was or "")
	label:SetTextColor(r, g, b)
	bar.track:SetColorTexture(r, g, b, 0.2)
	bar.fill:SetColorTexture(r, g, b, 0.9)
end

-- Its place: the middle of the top bar while the letterbox is up, else just
-- inside the top of the screen.
local function Place()
	local side = ns.letterbox and ns.letterbox:IsShown() and ns.letterbox.top
	local bar = side and side:GetHeight()
	bar = bar and bar >= 8 and bar or nil
	Style(bar)
	local y = bar and bar / 2 or UIParent:GetHeight() * LOW
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "TOP", 0, -y)
end

-- What the line says now: its words, how full its bar is and in how many
-- parts (the bag's three stacks; the fire's one).
local function Line()
	local now = GetTime()
	local kind = test and test.kind or (state.inBag and "bag") or (camp.since and "camp") or nil
	if kind == "camp" then
		local share
		if test then
			share = math.min(1, (now - test.start) / CAMP_TEST)
		else
			-- (Full only as it really arrives: a slow minute waits at the end.)
			share = camp.gotAt and 1 or math.min(0.98, (now - camp.since) / CAMP_TIME)
		end
		return L["Camp Benefits"], share, 1
	end
	local stacks, _, nextAt = Now()
	local full = stacks >= MAX
	-- (A third for each stack, the one coming filling its third up.)
	local coming = 0
	if not full and nextAt then
		coming = math.max(0, math.min(1, 1 - (nextAt - now) / (test and TEST_STEP or STACK_TIME)))
	end
	return full and L["Fully rested"] or ("%s %d/%d"):format(WellRestedName(), stacks, MAX),
		math.min(1, (stacks + coming) / MAX), MAX
end

-- The words and the bar now, side by side around the middle.
local GAP = 0.6   -- the room between the words and the bar, times the words' size
local BAR_W = 7   -- the bar's length, times the words' size
local function Draw()
	local words, share, parts = Line()
	local now = GetTime()
	label:SetText(words)
	local barW, barH = math.floor(size * BAR_W + 0.5), math.max(3, math.floor(size * 0.3 + 0.5))
	bar:SetSize(barW, barH)
	bar.fill:SetShown(share > 0)
	bar.fill:SetWidth(math.max(0.01, barW * share))
	for i, tick in ipairs(bar.ticks) do
		tick:SetShown(i < parts)
		tick:ClearAllPoints()
		tick:SetPoint("TOP", bar, "TOPLEFT", barW * i / parts, 0)
		tick:SetSize(1, barH)
	end
	local flash = pulseAt and math.max(0, 1 - (now - pulseAt) / PULSE) or 0
	bar.flash:SetAlpha(flash * 0.8)
	if pulseAt and flash <= 0 then pulseAt = nil end
	local gap = size * GAP
	local width = label:GetStringWidth() + gap + barW
	frame:SetSize(width, size)
	label:ClearAllPoints()
	label:SetPoint("LEFT", frame, "CENTER", -width / 2, 0)
	bar:ClearAllPoints()
	bar:SetPoint("LEFT", frame, "CENTER", -width / 2 + label:GetStringWidth() + gap, 0)
end

-- Whether it may show now (asked every CHECK seconds, not every frame).
local function Wanted()
	local now = GetTime()
	if test then return now - test.start < TestLength() end
	if state.inBag then
		if fullAt and now - fullAt > FULL_HOLD then return false end
		return ns.CardAllowed("sleepBag") and true or false
	end
	if camp.since then
		if camp.gotAt and now - camp.gotAt > FULL_HOLD then return false end
		return ns.CampTimerOn ~= nil and ns.CampTimerOn()
	end
	return false
end

local alpha, wanted, sinceCheck = 0, false, CHECK
local function Update(_, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck >= CHECK then
		sinceCheck = 0
		local ok, yes = pcall(Wanted)
		wanted = ok and yes or false
		if wanted then Place() end
	end
	alpha = ns.Approach(alpha, wanted and 1 or 0, elapsed, FADE)
	if alpha <= 0 and not wanted then
		frame:SetAlpha(0)
		if test and GetTime() - test.start > TestLength() then test = nil end
		if not (test or state.inBag or camp.since) then frame:Hide() end
		return
	end
	frame:SetAlpha(alpha)
	Draw()
end
ns.SetOnUpdate(frame, Update)

-- The frame shows (and so updates) only in the bag, resting by a fire for
-- Camp Benefits, or on a Test.
Start = function()
	if frame:IsShown() then return end
	if not (test or (state.inBag and ns.CardOn("sleepBag"))
		or (camp.since and ns.CampTimerOn and ns.CampTimerOn())) then return end
	Register()
	alpha, wanted, sinceCheck = 0, false, CHECK
	frame:SetAlpha(0)
	frame:Show()
end

function ns.SleepBagTest(kind)
	if test then
		test = nil -- (its Test again: stopped)
		return
	end
	kind = kind == "camp" and "camp" or "bag"
	local run = { start = GetTime(), kind = kind }
	test = run
	pulseAt = nil
	local times = kind == "camp" and { CAMP_TEST } or { TEST_STEP, 2 * TEST_STEP, 3 * TEST_STEP }
	for _, at in ipairs(times) do
		C_Timer.After(at + 0.05, function()
			if test == run then pulseAt = GetTime() end
		end)
	end
	Start()
end
function ns.SleepBagTestRunning() return test ~= nil end

-- /cine debug sleepbag: what it reads now, and why it shows or not.
function ns.SleepBagReport()
	local id = RestingID()
	local lines = {}
	local function Add(text) lines[#lines + 1] = text end
	Add(("Sleeping bag: client %s, in combat %s, CineMode %s"):format(ns.isRetail and "retail" or "classic",
		tostring(InCombatLockdown()), tostring(ns.lastCinematic and true or false)))
	Add(("Resting aura ID: %s (%s)%s"):format(tostring(id),
		ns.db and ns.db.sleepBagRestingID and "learned" or "not learned yet: lie in the bag",
		learn and ", watching after Unroll Bag" or ""))
	local now = GetTime()
	local function Say(what, has, count, duration, ends)
		Add(("%s: %s, stacks %s, %s s of %s"):format(what, tostring(has), tostring(count),
			ends and ("%.1f"):format(ends - now) or "?", tostring(duration)))
	end
	if id then Say("Resting", Aura(id)) end
	Say("Well-Rested (" .. WELL_RESTED .. ")", Aura(WELL_RESTED, WellRestedName()))
	-- (Every buff on you, to find Resting's ID by eye if it wasn't learned.)
	local list, unread = Buffs()
	local buffs = {}
	for _, buff in ipairs(list) do
		buffs[#buffs + 1] = ("%s (%s, %s s)"):format(tostring(buff.name), tostring(buff.id),
			buff.ends and buff.ends > 0 and ("%.0f"):format(buff.ends - now) or "-")
	end
	Add("Buffs: " .. (unread and "can't be read now" or table.concat(buffs, ", ")))
	local stacks, ends, nextAt = Now()
	Add(("Shown: %d/%d, ends in %s, next in %s"):format(stacks, MAX, ends and Left(ends - now) or "?",
		nextAt and Clock(nextAt - now) or "-"))
	local allowed, why = ns.CardAllowed("sleepBag")
	Add(("Campfire: timer on %s, by the fire %s, resting %s, since %s, Camp Benefits came %s"):format(
		tostring(CampWanted()), tostring(camp.byFire), tostring(ns.IsResting and ns.IsResting() or false),
		camp.since and ("%.0f s ago"):format(now - camp.since) or "-",
		camp.gotAt and ("%.0f s ago"):format(now - camp.gotAt) or "-"))
	Add(("Row on %s, may show here %s%s; frame shown %s, alpha %.2f, letterbox up %s"):format(
		tostring(ns.CardOn("sleepBag")), tostring(allowed), why and (" (" .. why .. ")") or "",
		tostring(frame:IsShown()), frame:GetAlpha(), tostring(ns.letterbox and ns.letterbox:IsShown() or false)))
	-- (Printed lines go in the log too: Diagnostics.lua catches them.)
	for _, text in ipairs(lines) do ns.Print(text) end
end

-- Camp Benefits' minute by the fire: watched every half second from the
-- cursor resting on a fire till you move away. After it came (or ended),
-- you stand up first before another minute counts.
local campTicker
local function CampWatch()
	if not camp.byFire then return end
	local resting = ns.IsResting and ns.IsResting() and true or false
	if camp.waitUp then
		if not resting then camp.waitUp = nil end
		return
	end
	if resting and not camp.since then
		camp.since, camp.gotAt = GetTime(), nil
		ns.Log("sleepbag", "resting by the fire: Camp Benefits timer started")
		Start()
	elseif not resting and camp.since and not camp.gotAt then
		ns.Log("sleepbag", ("up after %.0f s by the fire, before Camp Benefits"):format(GetTime() - camp.since))
		camp.since = nil
	end
end
local function CampStop()
	camp.byFire, camp.since, camp.gotAt, camp.waitUp = false, nil, nil, nil
	if campTicker then
		campTicker:Cancel()
		campTicker = nil
	end
end
ns.Listen("CAMPFIRE_REST", function()
	camp.byFire = true
	if not campTicker then campTicker = C_Timer.NewTicker(0.5, CampWatch) end
	CampWatch()
end, CampWanted)
ns.Listen("CAMPFIRE_LEFT", CampStop, CampWanted)
ns.Listen("CAMP_BENEFITS", function()
	if not camp.since then return end
	camp.gotAt = GetTime()
	pulseAt = camp.gotAt
	ns.Log("sleepbag", ("Camp Benefits came %.1f s after resting by the fire"):format(camp.gotAt - camp.since))
end, CampWanted)
ns.Listen("CAMP_BENEFITS_DONE", function()
	camp.since, camp.gotAt, camp.waitUp = nil, nil, true
end, CampWanted)

local watcher = CreateFrame("Frame")
watcher:RegisterUnitEvent("UNIT_AURA", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED") -- (read again after a fight)
watcher:SetScript("OnEvent", ns.Profiled("UNIT_AURA (sleeping bag)", function(_, event, _, castGUID, spellID)
	if ns.isRetail then return end
	-- (In a fight Forever says Well-Rested is gone, tested 2026-11-18: 0/3
	-- each fight. Not read till after it, as it was; no bag in a fight anyway.)
	if InCombatLockdown() or ns.Flag(UnitAffectingCombat("player")) then return end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		-- (The ID, or else read off the cast's GUID: Cast-3-...-429961-...)
		local id = Number(spellID)
		if not id and Text(castGUID) then id = tonumber(castGUID:match("^Cast%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) end
		if id == UNROLL then Unrolled() end
		return
	end
	Read()
end))
