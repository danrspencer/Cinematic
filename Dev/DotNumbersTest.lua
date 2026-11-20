-- /cine debug dotnumbers: one run checking whether the Cooldown Manager
-- page's "Use the spell's cooldown, not its buff" takes the countdown
-- numbers off a DoT's icon in the Essential bar (a player's report
-- 2026-11-20: Corruption, Bane of Agony and Siphon Life showed no numbers,
-- with Numbers on Game's option (on)). A DoT has no cooldown of its own, so
-- swapping its debuff's timer for the spell's cooldown may leave nothing.
-- It sets itself up (CineMode off, the page and its switches on, the game's
-- Show Numbers for Cooldowns on, the Essential bar's Numbers on Game's
-- option), then rounds, each waiting (no time limit) for you to cast (and
-- for a DoT, its icon to show its debuff):
--   1 DoT, Use the spell's cooldown, not its buff: On
--   2 DoT, Use the spell's cooldown, not its buff: Off
-- Each logs the round's icons (aura or not, the sweep, the countdown text's
-- visibility, width, font, color, levels) with a screenshot. The text is
-- secret in fights, so the screenshots say whether a number drew (a first
-- version counted a secret text as drawn: wrong). Everything is put back
-- at the end, and at the next login if a /reload cuts it short.
-- Into CinematicDB.dotNumbersLog. Dev copy only (CinematicDev.toc).
local ADDON_NAME, ns = ...

local AFTER = 2.5 -- seconds after the DoT shows before it's read (the game sets the icon)

local run -- { at, rounds, round, phaseAt, castAt, seenAt, dots, cooldownSpell, cooldownName, casts, ticker }

local function Secret(value)
	return issecretvalue and issecretvalue(value) or false
end
local function Show(value)
	if Secret(value) then return "secret" end
	return tostring(value)
end
local function Say(text)
	local log = CinematicDB and CinematicDB.dotNumbersLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end
local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end
local function Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = Copy(v) end
	return copy
end
local function SpellName(id)
	local GetName = (C_Spell and C_Spell.GetSpellName) or function(spell) return (GetSpellInfo(spell)) end
	local ok, name = pcall(GetName, id)
	return ok and type(name) == "string" and not Secret(name) and name or ("spell " .. tostring(id))
end

-- What's kept to put back: the row settings, the old page keys, the page
-- switches the test turned on, and the game's option.
local KEYS = { "handleCooldowns", "cooldownRowSettings", "cooldownFollowNumbers", "cooldownShowNumbers", "cooldownSpellNotBuff" }
local function Keep(switches)
	local kept = { db = {}, switches = switches }
	for _, key in ipairs(KEYS) do kept.db[key] = Copy(ns.db[key]) end
	local ok, value = pcall(GetCVar, "countdownForCooldowns")
	kept.cvar = ok and value or nil
	CinematicDB.dotNumbersPending = kept
end
local function PutBack()
	local kept = CinematicDB.dotNumbersPending
	if type(kept) ~= "table" then return end
	for _, key in ipairs(KEYS) do ns.db[key] = Copy(kept.db[key]) end
	for _, key in ipairs(kept.switches or {}) do ns.db[key] = false end
	if kept.cvar ~= nil then pcall(SetCVar, "countdownForCooldowns", kept.cvar) end
	CinematicDB.dotNumbersPending = nil
	if ns.ApplyCooldownNumbers then pcall(ns.ApplyCooldownNumbers) end
	if ns.readyPace then ns.readyPace.due = true end
end
local restorer = CreateFrame("Frame")
restorer:RegisterEvent("PLAYER_LOGIN")
restorer:SetScript("OnEvent", function()
	if type(CinematicDB and CinematicDB.dotNumbersPending) == "table" then
		PutBack()
		ns.Print("DoT numbers test was cut short: your Cooldown Manager settings are back")
	end
end)

-- The page's switch and every switch above it on (each one turned on is
-- listed, to turn off again at the end).
local function SwitchesOn()
	local turned = {}
	local switch = "handleCooldowns"
	while switch do
		if ns.db[switch] == false then
			ns.db[switch] = true
			turned[#turned + 1] = switch
		end
		switch = ns.PageSwitchOf(switch)
	end
	return turned
end

-- The Essential bar's spells with no cooldown of their own (DoTs and the like).
local function FindDots()
	local dots, names, all = {}, {}, {}
	for _, spell in ipairs(ns.CooldownManagerSpells()) do
		if spell.group == "essential" then
			local name = SpellName(spell.id)
			all[#all + 1] = name
			local base = GetSpellBaseCooldown and GetSpellBaseCooldown(spell.id)
			if type(base) == "number" and not Secret(base) and base == 0 then
				dots[spell.id] = true
				names[#names + 1] = ("%s %d"):format(name, spell.id)
			end
		end
	end
	return dots, names, all
end

local function ShowsAura(icon)
	local fromAura = icon.wasSetFromAura
	if Secret(fromAura) then return type(icon.auraInstanceID) == "number" or Secret(icon.auraInstanceID) end
	return fromAura == true
end

-- A spell in the Essential or Utility bar with a cooldown of its own
-- (5 sec or more), for the round that checks numbers on a plain cooldown.
local function FindCooldownSpell()
	for _, spell in ipairs(ns.CooldownManagerSpells()) do
		if spell.group == "essential" or spell.group == "utility" then
			local base = GetSpellBaseCooldown and GetSpellBaseCooldown(spell.id)
			if type(base) == "number" and not Secret(base) and base >= 5000 then
				return spell.id, spell.group
			end
		end
	end
end

local VIEWER_GROUP = { EssentialCooldownViewer = "essential", UtilityCooldownViewer = "utility" }

-- (A method's results shown: "secret", the value, or "error"; "-" when it has none.)
local function Ask(object, method, ...)
	if type(object) ~= "table" or type(object[method]) ~= "function" then return "-" end
	local results = { pcall(object[method], object, ...) }
	if not results[1] then return "error" end
	local parts = {}
	for i = 2, #results do
		local value = results[i]
		parts[#parts + 1] = type(value) == "number" and not Secret(value) and ("%.2f"):format(value) or Show(value)
	end
	return table.concat(parts, "/")
end

-- The round's icons now (the DoTs, or the cooldown spell's): lines with
-- everything that decides whether the countdown draws, and whether any
-- shows its debuff.
local function Look(wanted)
	local lines, anyAura, count = {}, false, 0
	ns.EachCooldownIcon(function(icon, id, bar)
		local group = VIEWER_GROUP[bar]
		local base = ns.BaseSpell and ns.BaseSpell(id) or id
		if not group or not (wanted[base] or wanted[id]) then return end
		count = count + 1
		anyAura = anyAura or ShowsAura(icon)
		local cd = icon.Cooldown
		local font
		if type(cd) == "table" and cd.GetCountdownFontString then
			local ok, value = pcall(cd.GetCountdownFontString, cd)
			font = ok and value or nil
		end
		lines[#lines + 1] = ("  %s %d (%s): up %s alpha %s, from aura %s, aura id %s, picture %s"):format(
			SpellName(id), id, group, Ask(icon, "IsShown"), Ask(icon, "GetEffectiveAlpha"),
			Show(icon.wasSetFromAura), Show(icon.auraInstanceID), Ask(icon.Icon, "GetTexture"))
		-- (What makes it round: masks on its picture, and how many of its own textures have one.)
		local masked, textures = 0, 0
		for _, region in ipairs({ icon:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "Texture" then
				textures = textures + 1
				local ok, n = pcall(region.GetNumMaskTextures, region)
				if ok and type(n) == "number" and n > 0 then masked = masked + 1 end
			end
		end
		lines[#lines + 1] = ("    shape: picture masks %s, crop %s, its textures masked %d of %d, swipe round %s"):format(
			Ask(icon.Icon, "GetNumMaskTextures"), Ask(icon.Icon, "GetTexCoord"), masked, textures,
			tostring(ns.CooldownSwipeTexture and ns.CooldownSwipeTexture() ~= nil))
		lines[#lines + 1] = ("    sweep: shown %s visible %s alpha %s level %s (icon %s), times %s, draw swipe %s, " ..
			"paused %s, numbers hidden %s"):format(Ask(cd, "IsShown"), Ask(cd, "IsVisible"),
			Ask(cd, "GetEffectiveAlpha"), Ask(cd, "GetFrameLevel"), Ask(icon, "GetFrameLevel"),
			Ask(cd, "GetCooldownTimes"), Ask(cd, "GetDrawSwipe"), Ask(cd, "IsPaused"),
			Ask(cd, "GetHideCountdownNumbers"))
		lines[#lines + 1] = ("    countdown text: %s, shown %s visible %s alpha %s, width %s, font %s, color %s, " ..
			"layer %s | row numbers %s, not buff %s, swapped %s"):format(font and "found" or "none",
			Ask(font, "IsShown"), Ask(font, "IsVisible"), Ask(font, "GetEffectiveAlpha"), Ask(font, "GetStringWidth"),
			Ask(font, "GetFont"), Ask(font, "GetTextColor"), Ask(font, "GetDrawLayer"),
			tostring(ns.CooldownRowSetting("numbers", id, group)), tostring(ns.CooldownRowSetting("notBuff", id, group)),
			tostring(ns.CooldownNoBuffOn(id, group)))
		-- (The fix: a DoT has no cooldown of its own, so it's never swapped.)
		if ns.CooldownNoBuffOn(id, group) then run.swapped = true end
	end, true)
	return lines, anyAura, count
end

-- Each round: what it sets, what it asks, and when its icons are read
-- (aura: a cast of yours and a DoT's debuff on its icon; else the cast).
local ROUNDS = {
	{ key = "on", notBuff = true, aura = true, say = "Use the spell's cooldown, not its buff is ON.\n" ..
		"Put CORRUPTION (or another DoT) on a target dummy or a mob with lots of health." },
	{ key = "off", notBuff = false, aura = true, say = "Use the spell's cooldown, not its buff is OFF.\n" ..
		"Cast your DoT again (refresh it or put it on another target)." },
	-- (Found with these, 2026-11-20, kept for later: { key = "square", square
	-- = true, ... }, { key = "cooldown", spell = true, ... }, { key =
	-- "pageoff", pageOff = true, ... }. Now the fix's check: on vs off.)
}

-- The square round: the Cooldown Manager's icons dressed as with square
-- buttons, the action bars left as they are (Action Bar Style reads its look
-- through ns.StyleLook each time: this run's look over it, the page's own
-- under). Back to the page's own look after it, or at the end.
local styleLookWas
local function SquareIcons(on)
	if on and not styleLookWas then
		styleLookWas = ns.StyleLook
		ns.StyleLook = function(key, ...)
			local look = styleLookWas(key, ...)
			if key ~= "abStyle" or type(look) ~= "table" then return look end
			return setmetatable({ abShape = "square" }, { __index = look })
		end
	elseif not on and styleLookWas then
		ns.StyleLook, styleLookWas = styleLookWas, nil
	else
		return
	end
	if ns.RefreshCooldownShape then
		local ok, err = pcall(ns.RefreshCooldownShape)
		Say(("  icons dressed %s: %s"):format(on and "square" or "back", ok and "ok" or tostring(err)))
	end
end

local function Finish(done)
	if run.ticker then run.ticker:Cancel() end
	if run.casts then run.casts:UnregisterAllEvents() end
	SquareIcons(false)
	if done then
		Say(("VERDICT: %s; the countdown text is secret, so the screenshots (round on and off, the DoT icons " ..
			"that show the debuff) show whether a number drew: both should"):format(run.swapped
			and "FAIL, a DoT's icon was still swapped for its spell's cooldown"
			or "PASS, no DoT's icon swapped for its spell's cooldown, even with the setting on"))
	end
	PutBack()
	Say("settings put back")
	run = nil
	ns.PadTestBox(done and "DoT numbers test DONE. Type /reload, then say \"check log\"." or "DoT numbers test stopped.",
		"", 1, 0.82, 0)
	C_Timer.After(15, function() if not run then ns.PadTestBoxHide() end end)
end

local function RoundText(round)
	return ("%d/%d: "):format(run.round, #run.rounds) .. round.say:format(run.cooldownName or "")
end

local function StartRound(index)
	local round = run.rounds[index]
	run.round, run.phaseAt, run.castAt, run.seenAt = index, GetTime(), nil, nil
	ns.db.handleCooldowns = not round.pageOff
	SquareIcons(round.square)
	ns.SetCooldownRow("essential", "notBuff", round.notBuff)
	ns.SetCooldownRow("essential", "numbers", "game")
	ns.SetCooldownRow("utility", "numbers", "game")
	-- (The round's spells' own rows follow their bar for this.)
	for id in pairs(run.dots) do
		ns.SetCooldownRow(id, "notBuff", nil)
		ns.SetCooldownRow(id, "numbers", nil)
	end
	if run.cooldownSpell then ns.SetCooldownRow(run.cooldownSpell, "numbers", nil) end
	if ns.ApplyCooldownNumbers then pcall(ns.ApplyCooldownNumbers) end
	if ns.ApplyCooldownKeybinds then pcall(ns.ApplyCooldownKeybinds) end
	ns.readyPace.due = true
	Say(("--- round %d %s: not buff %s, page on %s (in combat %s) ---"):format(index, round.key,
		tostring(round.notBuff), tostring(ns.PageOn("handleCooldowns")), tostring(InCombatLockdown())))
	ns.TestPrompt(RoundText(round):gsub("\n", " "), 6)
end

local function Tick()
	local round = run.rounds[run.round]
	local now = GetTime()
	local wanted = round.spell and { [run.cooldownSpell] = true } or run.dots
	if not run.seenAt then
		local _, anyAura = Look(wanted)
		-- (A cast of yours since the round started, and for a DoT its debuff on its icon.)
		if run.castAt and (anyAura or not round.aura) then
			run.seenAt = now
			Say("  seen: reading in a moment")
		end
		ns.PadTestBox(RoundText(round), run.castAt and "Cast seen: waiting for its icon"
			or "WAITING for your cast (no time limit). Type the command again to stop.", 1, 0.82, 0)
		return
	end
	if now - run.seenAt < AFTER then
		ns.PadTestBox(RoundText(round), "RECORDING: keep still", 0.3, 1, 0.3)
		return
	end
	local lines, _, count = Look(wanted)
	Say(("  %d icon(s), CVar countdownForCooldowns %s, in combat %s, CineMode %s, round icons %s:"):format(count,
		tostring(GetCVar("countdownForCooldowns")), tostring(InCombatLockdown()), tostring(ns.lastCinematic),
		tostring(ns.CooldownRoundArt and ns.CooldownRoundArt() ~= nil)))
	for _, line in ipairs(lines) do Say(line) end
	Say("  " .. Shot("round " .. round.key))
	if run.round < #run.rounds then
		C_Timer.After(1, function() if run then StartRound(run.round + 1) end end)
		run.seenAt = math.huge -- (till the next round starts)
	else
		Finish(true)
	end
end

function ns.DotNumbersTest()
	if run then
		Finish(false)
		return
	end
	CinematicDB.dotNumbersLog = {}
	local switches = SwitchesOn()
	local dots, names, all = FindDots()
	if #names == 0 then
		for _, key in ipairs(switches) do ns.db[key] = false end
		ns.TestPrompt(("DoT numbers test: no spell without a cooldown in your Essential bar (in it: %s). " ..
			"Add Corruption to it in the game's Cooldown Settings, then run it again."):format(
			#all > 0 and table.concat(all, ", ") or "nothing"), 12)
		return
	end
	run = { at = GetTime(), dots = dots, rounds = {} }
	run.cooldownSpell = FindCooldownSpell()
	run.cooldownName = run.cooldownSpell and SpellName(run.cooldownSpell)
	for _, round in ipairs(ROUNDS) do
		if not round.spell or run.cooldownSpell then run.rounds[#run.rounds + 1] = round end
	end
	Keep(switches)
	if ns.lastCinematic and _G.Cinematic_ToggleCineMode then
		_G.Cinematic_ToggleCineMode()
		Say("CineMode turned OFF")
	end
	pcall(SetCVar, "countdownForCooldowns", "1")
	Say(("start: %s (game %s), version %s, DoTs in Essential: %s; switches turned on: %s; " ..
		"cooldown spell %s; handled %s, page on %s, CDM shown %s"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), tostring(select(2, pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version"))), table.concat(names, ", "),
		#switches > 0 and table.concat(switches, ", ") or "none",
		run.cooldownSpell and ("%s %d"):format(run.cooldownName, run.cooldownSpell) or "none (round skipped)",
		tostring(ns.GroupHandled("cooldowns")),
		tostring(ns.PageOn("handleCooldowns")), tostring(ns.CooldownViewersShown and ns.CooldownViewersShown())))
	-- (Your casts, secret IDs in fights or not: any one counts.)
	run.casts = CreateFrame("Frame")
	run.casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	run.casts:SetScript("OnEvent", function(_, _, _, _, spellID)
		if not run or run.seenAt then return end
		-- (The cooldown round: its spell's cast only, when the ID can be read.)
		local round = run.rounds[run.round]
		if round and round.spell and not Secret(spellID) and spellID ~= run.cooldownSpell then return end
		-- (A DoT round: one of the DoTs' own casts, when the ID can be read. A
		-- Shadow Bolt read the page-off round with the debuff gone, 2026-11-20.)
		if round and round.aura and not Secret(spellID)
			and not (run.dots[spellID] or run.dots[ns.BaseSpell and ns.BaseSpell(spellID) or spellID]) then
			return
		end
		run.castAt = GetTime()
		Say("  cast " .. Show(spellID))
	end)
	StartRound(1)
	run.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then
			Say("error: " .. tostring(err))
			if run then Finish(false) end
		end
	end)
end
