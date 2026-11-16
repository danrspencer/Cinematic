-- Cinematic: stack numbers on the Cooldown Manager's tracked buffs
-- (db.cooldownStacks, its page's Settings tab). The game's tracked buff icons
-- on Forever show a stacking debuff as on or off only, and in fights addons
-- can't read an aura's stacks (every aura read errors), so the stacks of the
-- spells listed below are counted from your own casts, which stay readable:
-- each cast adds one, up to the most, and all of them drop a set time after
-- the first. The game's icon going off clears them (that stays readable),
-- and out of fights, when its aura can be read, the aura's own count wins.
local _, ns = ...

-- Stacking spells, by the spell ID you cast. max: the most stacks; lasts:
-- seconds from the first stack (later casts don't refresh it); icons: the
-- spell IDs the Cooldown Manager may show it under (besides the cast's).
local STACKING = {
	-- Arcane Blast (Forever): each cast adds Spell Damage and mana cost,
	-- stacks up to 4 times, lasts 18 sec from the first.
	{ casts = { 400574, 1239696 }, max = 4, lasts = 18 },
}

local byCast, byIcon = {}, {} -- spell ID -> its entry
for _, entry in ipairs(STACKING) do
	entry.stacks, entry.endsAt = 0, 0
	for _, id in ipairs(entry.casts) do
		byCast[id], byIcon[id] = entry, entry
	end
	for _, id in ipairs(entry.icons or {}) do byIcon[id] = entry end
end

local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local test -- the /cine debug stacktest run going, if one is (below)

local function Secret(value)
	return issecretvalue and issecretvalue(value) or false
end

local function PlainNumber(value)
	return type(value) == "number" and not Secret(value) and value or nil
end

-- (A short log of the last casts and looks, for /cine debug stacks.)
local log = {}
local function Log(text)
	log[#log + 1] = ("%.1f %s"):format(GetTime(), text)
	if #log > 40 then table.remove(log, 1) end
end

-- (A cast lands a moment before the game's icon picks the aura up: an icon
-- still off this soon after one doesn't clear the count.)
local CAST_GRACE = 0.6

-- The stacks up now, put right by the game's icon for the spell: whether it
-- holds an aura (its auraInstanceID there at all, which stays readable in
-- fights: Discipline's test, 2026-11-14, on and off at the right times) and,
-- out of fights where the aura can be read, its own count and end time. (Not
-- by spell ID: Arcane Blast's debuff is 400573, not the cast's ID.)
local function Stacks(entry, icon)
	local now = GetTime()
	if entry.stacks > 0 and now >= entry.endsAt then entry.stacks = 0 end
	local instance = icon and icon.auraInstanceID
	if icon and type(instance) == "nil" then
		if entry.stacks > 0 and now - (entry.castAt or 0) > CAST_GRACE then
			Log(("icon off: cleared %d"):format(entry.stacks))
			entry.stacks = 0
		end
	elseif PlainNumber(instance) and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instance)
		if ok and type(aura) == "table" and not Secret(aura) then
			local count, ends = PlainNumber(aura.applications), PlainNumber(aura.expirationTime)
			if count then
				count = math.max(count, 1)
				if count ~= entry.stacks then
					Log(("read %d (counted %d)"):format(count, entry.stacks))
				end
				entry.stacks = count
				if ends and ends > 0 then entry.endsAt = ends end
			end
		end
	end
	return entry.stacks
end

-- The spell a tracked buff's icon is for (its Cooldown Manager info), kept by
-- icon and cooldown ID: in fights some of it is secret.
local iconEntry = setmetatable({}, { __mode = "k" }) -- icon -> { cooldownID, entry or false }
local INFO_FIELDS = { "spellID", "overrideSpellID", "overrideTooltipSpellID" }
local function EntryOf(icon)
	local cooldownID = PlainNumber(icon.cooldownID)
	local kept = iconEntry[icon]
	if kept and (cooldownID == nil or kept.id == cooldownID) then return kept.entry or nil end
	local info = ns.IconCooldownInfo and ns.IconCooldownInfo(icon)
	if type(info) ~= "table" then return kept and kept.entry or nil end
	local found = false
	for _, field in ipairs(INFO_FIELDS) do
		local id = PlainNumber(info[field])
		if id and byIcon[id] then found = byIcon[id] break end
	end
	if not found and type(info.linkedSpellIDs) == "table" and not Secret(info.linkedSpellIDs) then
		for _, id in ipairs(info.linkedSpellIDs) do
			id = PlainNumber(id)
			if id and byIcon[id] then found = byIcon[id] break end
		end
	end
	if cooldownID then
		iconEntry[icon] = { id = cooldownID, entry = found }
		if found then Log(("icon found (cooldown %d)"):format(cooldownID)) end
	end
	return found or nil
end

-- Our number on an icon, over the game's art, in its bottom right corner as
-- the game's stack counts sit; and the time left (the game's icon shows
-- none for these): a swipe over the icon and the seconds in its middle.
-- (The swipe a frame of its own under the text's: a Cooldown draws over
-- its parent's font strings.)
local labels = setmetatable({}, { __mode = "k" }) -- icon -> the count's font string
local function Label(icon)
	local text = labels[icon]
	if not text then
		local art = type(icon.Icon) == "table" and type(icon.Icon.GetObjectType) == "function" and icon.Icon or icon
		local ok, holder = pcall(CreateFrame, "Frame", nil, icon)
		if not ok then return nil end
		holder:SetAllPoints(art)
		holder:SetFrameLevel(icon:GetFrameLevel() + 10)
		local made, swipe = pcall(CreateFrame, "Cooldown", nil, icon, "CooldownFrameTemplate")
		if made then
			swipe:SetAllPoints(art)
			swipe:SetFrameLevel(icon:GetFrameLevel() + 9)
			swipe:SetDrawEdge(false)
			swipe:SetHideCountdownNumbers(true)
			swipe:SetReverse(false)
		else
			swipe = nil
		end
		text = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		text:SetPoint("BOTTOMRIGHT", -1, 2)
		text:SetJustifyH("RIGHT")
		local time = holder:CreateFontString(nil, "OVERLAY")
		time:SetFont((text:GetFont()), 15, "OUTLINE")
		time:SetPoint("CENTER", 0, 0)
		time:SetTextColor(1, 1, 1)
		text.time, text.swipe = time, swipe
		labels[icon] = text
	end
	return text
end

local function HideLabel(text)
	text:Hide()
	text.time:Hide()
	if text.swipe and text.swipeEnds then
		text.swipe:Clear()
		text.swipeEnds = nil
	end
end

local function On()
	return ns.db and ns.db.cooldownStacks and ns.PageOn("handleCooldowns")
end

local function ShowIcon(icon)
	if icon.IsForbidden and icon:IsForbidden() then return end
	local entry = EntryOf(icon)
	local stacks = entry and Stacks(entry, icon) or 0
	if stacks > 0 then
		local text = Label(icon)
		if text then
			text:SetText(stacks)
			text:Show()
			local left = entry.endsAt - GetTime()
			text.time:SetText(left >= 0.5 and tostring(math.floor(left + 0.5)) or "")
			text.time:Show()
			-- (Set again only when the end moves: an aura read out of a
			-- fight can put it right.)
			if text.swipe and text.swipeEnds ~= entry.endsAt then
				text.swipeEnds = entry.endsAt
				text.swipe:SetCooldown(entry.endsAt - entry.lasts, entry.lasts)
			end
		end
	elseif labels[icon] then
		HideLabel(labels[icon])
	end
end

local function Update()
	if not On() then
		for _, text in pairs(labels) do HideLabel(text) end
		return
	end
	for _, name in ipairs(VIEWERS) do
		local viewer = _G[name]
		local pool = viewer and viewer.itemFramePool
		if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
			for icon in pool:EnumerateActive() do ShowIcon(icon) end
		end
	end
end

local watcher = CreateFrame("Frame")
local since = 0
ns.SetOnUpdate(watcher, function(_, elapsed)
	since = since + elapsed
	if since < 0.2 then return end
	since = 0
	Update()
end)
watcher:Hide()

-- Your casts: one more stack each (a fresh count once the last ran out).
watcher:SetScript("OnEvent", function(_, event, _, _, spellID)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		local id = PlainNumber(spellID)
		local entry = id and byCast[id]
		if not entry then
			if id and test then test.onCast(id) end
			return
		end
		local now = GetTime()
		if entry.stacks <= 0 or now >= entry.endsAt then
			entry.stacks, entry.endsAt = 0, now + entry.lasts
		end
		entry.stacks = math.min(entry.stacks + 1, entry.max)
		entry.castAt = now
		Log(("cast %d: counted %d, %s"):format(id, entry.stacks, InCombatLockdown() and "in fight" or "no fight"))
		if test then test.onCast(id) end
		since = 1 -- (shown on the next frame)
	elseif event == "PLAYER_DEAD" then
		for _, entry in ipairs(STACKING) do entry.stacks = 0 end
	elseif event == "PLAYER_ENTERING_WORLD" then
		ns.ApplyCooldownStacks()
		return
	end
	Update()
end)
pcall(watcher.RegisterUnitEvent, watcher, "UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(watcher.RegisterEvent, watcher, "PLAYER_DEAD")
pcall(watcher.RegisterEvent, watcher, "PLAYER_ENTERING_WORLD")

-- Starts or stops it as the page says (its tick box, the page's switch).
function ns.ApplyCooldownStacks()
	if not ns.db then return end
	Update()
	-- (Kept running while the page's switch is off: Update hides the
	-- numbers then, and they come back with it.)
	watcher:SetShown(ns.db.cooldownStacks and true or false)
end

-- /cine debug stacks: what it counted and found, the latest last.
function ns.CooldownStacksReport()
	ns.Print(("Stack counts: %s; page %s"):format(ns.db and ns.db.cooldownStacks and "on" or "off",
		ns.PageOn("handleCooldowns") and "on" or "off"))
	for _, entry in ipairs(STACKING) do
		ns.Print(("  %s: %d now (%.0f sec left)"):format(table.concat(entry.casts, "/"), Stacks(entry),
			math.max(0, entry.endsAt - GetTime())))
	end
	for _, name in ipairs(VIEWERS) do
		local viewer = _G[name]
		local pool = viewer and viewer.itemFramePool
		if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
			for icon in pool:EnumerateActive() do
				local info = ns.IconCooldownInfo and ns.IconCooldownInfo(icon)
				local spell = info and PlainNumber(info.spellID)
				ns.Print(("  %s icon: spell %s%s"):format(name, spell and tostring(spell) or "?",
					EntryOf(icon) and " (counted)" or ""))
			end
		end
	end
	for _, line in ipairs(log) do ns.Print("  " .. line) end
end

-- /cine debug stacktest: a guided test for players with a stacking spell
-- (Arcane Blast). Three timed steps in a big box (ns.PadTestBox), each
-- recording what the game's icon and our number do, then a verdict per
-- item and the lot in a copy box to paste back. Typed again: stops.
-- The game's icon counts as active while it holds an aura (its
-- auraInstanceID there at all: its value is secret in fights).
local copyBox
local function ShowCopy(text)
	if not copyBox then
		copyBox = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		copyBox:SetFrameStrata("FULLSCREEN_DIALOG")
		copyBox:SetSize(620, 380)
		copyBox:SetPoint("CENTER")
		copyBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 2 })
		copyBox:SetBackdropColor(0, 0, 0, 0.92)
		copyBox:SetBackdropBorderColor(1, 0.82, 0, 1)
		copyBox:EnableMouse(true)
		copyBox:SetMovable(true)
		copyBox:RegisterForDrag("LeftButton")
		copyBox:SetScript("OnDragStart", copyBox.StartMoving)
		copyBox:SetScript("OnDragStop", copyBox.StopMovingOrSizing)
		local title = copyBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOP", 0, -12)
		title:SetText("Stack test results: press Ctrl+C to copy, then paste them on Discord")
		local close = CreateFrame("Button", nil, copyBox, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 2, 2)
		local scroll = CreateFrame("ScrollFrame", nil, copyBox, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 14, -40)
		scroll:SetPoint("BOTTOMRIGHT", -32, 14)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(560)
		edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
		edit:SetScript("OnTextChanged", function(self, userInput)
			if userInput then self:SetText(copyBox.text) self:HighlightText() end
		end)
		scroll:SetScrollChild(edit)
		copyBox.edit = edit
	end
	copyBox.text = text
	copyBox:Show()
	copyBox.edit:SetText(text)
	copyBox.edit:SetFocus()
	copyBox.edit:HighlightText()
end

local function TestIcon()
	for _, name in ipairs(VIEWERS) do
		local viewer = _G[name]
		local pool = viewer and viewer.itemFramePool
		if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
			for icon in pool:EnumerateActive() do
				if EntryOf(icon) then return icon end
			end
		end
	end
end

local function SpellName(id)
	local ok, name = pcall(function() return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) end)
	if ok and type(name) == "string" and not Secret(name) then return name end
	return "?"
end

function ns.CooldownStacksTest()
	if test then
		test.ticker:Cancel()
		test = nil
		ns.PadTestBoxHide()
		ns.Print("stack test stopped")
		return
	end
	local out = {}
	local function Line(text) out[#out + 1] = text end
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Cinematic", "Version")
	Line(("Cinematic %s, game %s (%s)"):format(tostring(version), tostring((GetBuildInfo())),
		tostring(select(4, GetBuildInfo()))))
	local _, class = UnitClass("player")
	Line(("Class %s, level %s, setting %s, page %s"):format(tostring(class), tostring(UnitLevel("player")),
		ns.db.cooldownStacks and "on" or "off", ns.PageOn("handleCooldowns") and "on" or "off"))
	local known = {}
	for _, entry in ipairs(STACKING) do
		for _, id in ipairs(entry.casts) do
			local ok, has = pcall(IsPlayerSpell, id)
			known[#known + 1] = ("%d %s"):format(id, ok and has and "known" or "not known")
		end
	end
	Line("Spells: " .. table.concat(known, ", "))
	local ids = {}
	for _, name in ipairs(VIEWERS) do
		local viewer = _G[name]
		local pool = viewer and viewer.itemFramePool
		if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
			for icon in pool:EnumerateActive() do
				local info = ns.IconCooldownInfo and ns.IconCooldownInfo(icon)
				local id = type(info) == "table" and PlainNumber(info.spellID)
				local linked = {}
				if type(info) == "table" and type(info.linkedSpellIDs) == "table" and not Secret(info.linkedSpellIDs) then
					for _, l in ipairs(info.linkedSpellIDs) do linked[#linked + 1] = tostring(PlainNumber(l)) end
				end
				ids[#ids + 1] = tostring(id or "?") .. (#linked > 0 and ("[" .. table.concat(linked, "/") .. "]") or "")
					.. (EntryOf(icon) and "*" or "")
			end
		end
	end
	Line("Tracked buff icons (* = counted): " .. (#ids > 0 and table.concat(ids, " ") or "none"))
	local icon = TestIcon()
	if not icon then
		Line("FAIL: no Tracked Buffs icon for Arcane Blast. Put it in Tracked Buffs (Cooldown Settings, Buffs tab) and run this again.")
		ShowCopy(table.concat(out, "\n"))
		return
	end
	Line("PASS: Arcane Blast's Tracked Buffs icon found")
	for _, entry in ipairs(STACKING) do entry.stacks, entry.endsAt = 0, 0 end

	local STEPS = {
		{ say = "1/3: Target a mob that will live 20 sec or more and cast ARCANE BLAST 5 times in a row. Nothing else.", time = 24 },
		{ say = "2/3: STOP casting. Don't cast anything, just wait.", time = 26 },
		{ say = "3/3: Cast ARCANE BLAST 2 times, then cast ARCANE MISSILES once (or Arcane Explosion " ..
			"if you don't have it).", time = 22 },
	}
	local READY = 4
	test = { start = GetTime(), step = 0, events = {}, casts = {} }
	local run = test
	local function At() return GetTime() - run.start end
	local function Event(text) run.events[#run.events + 1] = ("%5.1f s  %s"):format(At(), text) end
	local lastActive, lastText, lastShown
	run.onCast = function(id)
		run.casts[#run.casts + 1] = { at = At(), id = id, step = run.step }
		local counted = byCast[id] and byCast[id].stacks
		Event(("step %d cast %d %s%s"):format(run.step, id, SpellName(id),
			counted and (" -> counted " .. counted) or ""))
	end
	local stepEnds, recordFrom = 0, 0
	local function NextStep()
		run.step = run.step + 1
		local step = STEPS[run.step]
		if not step then return false end
		recordFrom = At() + READY
		stepEnds = recordFrom + step.time
		return true
	end
	NextStep()
	run.ticker = C_Timer.NewTicker(0.1, function()
		if test ~= run then return end
		local now = At()
		if now >= stepEnds and not NextStep() then
			run.ticker:Cancel()
			test = nil
			ns.PadTestBoxHide()
			-- Verdicts.
			local ab = {}
			for _, cast in ipairs(run.casts) do
				if byCast[cast.id] then ab[#ab + 1] = cast end
			end
			local first = ab[1]
			Line(("%s: Arcane Blast casts seen (%d)"):format(#ab > 0 and "PASS" or "FAIL", #ab))
			local maxShown = 0
			for _, e in ipairs(run.events) do
				local n = tonumber(e:match("number shows (%d)"))
				if n and n > maxShown then maxShown = n end
			end
			Line(("%s: our number went up to %d (should be 4)"):format(maxShown == 4 and "PASS" or "FAIL", maxShown))
			if first then
				local gameOff, oursOff
				for _, e in ipairs(run.events) do
					local t = tonumber(e:match("^%s*([%d%.]+) s"))
					if t and t > first.at and t < first.at + 40 then
						if not gameOff and (e:find("game icon inactive", 1, true) or e:find("game icon hidden", 1, true)) then
							gameOff = t
						end
						if not oursOff and e:find("number hidden", 1, true) then oursOff = t end
					end
				end
				Line(("Game icon went inactive %s after the first cast; our number %s (should be about 18 s)"):format(
					gameOff and ("%.1f s"):format(gameOff - first.at) or "never",
					oursOff and ("%.1f s"):format(oursOff - first.at) or "never"))
				if gameOff and oursOff then
					Line(("%s: number and game icon end together"):format(math.abs(gameOff - oursOff) <= 1.5
						and "PASS" or "FAIL"))
				end
			end
			-- Step 3: did the other Arcane spell end the stacks?
			for _, cast in ipairs(run.casts) do
				if cast.step == 3 and not byCast[cast.id] then
					local cleared
					for _, e in ipairs(run.events) do
						local t = tonumber(e:match("^%s*([%d%.]+) s"))
						if t and t >= cast.at and t <= cast.at + 1.5 and (e:find("game icon inactive", 1, true)
							or e:find("game icon hidden", 1, true)) then
							cleared = true
						end
					end
					Line(("Other spell %d %s: %s the stacks"):format(cast.id, SpellName(cast.id),
						cleared and "ENDED" or "did not end"))
				end
			end
			Line("Timeline:")
			for _, e in ipairs(run.events) do Line(e) end
			ShowCopy(table.concat(out, "\n"))
			return
		end
		local step = STEPS[run.step]
		if now < recordFrom then
			ns.PadTestBox(step.say, ("GET READY: starts in %d"):format(math.ceil(recordFrom - now)), 1, 0.82, 0)
		else
			ns.PadTestBox(step.say, ("RECORDING: %d sec left"):format(math.ceil(stepEnds - now)), 0.2, 1, 0.2)
		end
		-- What the game's icon and our number show, on each change.
		local live = TestIcon() or icon
		local active = type(live.auraInstanceID) ~= "nil"
		if active ~= lastActive then
			lastActive = active
			Event(active and "game icon active" or "game icon inactive")
		end
		-- (And whether it's shown: Hide When Inactive hides it.)
		local ok, shown = pcall(live.IsShown, live)
		shown = not ok and "error" or Secret(shown) and "secret" or (shown and "shown" or "hidden")
		if shown ~= lastShown then
			lastShown = shown
			Event("game icon " .. shown)
		end
		local label = labels[live]
		local text = label and label:IsShown() and label:GetText() or nil
		if text ~= lastText then
			lastText = text
			local time = text and label.time:IsShown() and label.time:GetText()
			Event(text and ("number shows " .. text .. (time and time ~= "" and (", timer " .. time) or ", no timer"))
				or "number hidden")
		end
	end)
end
