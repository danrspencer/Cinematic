-- /cine debug lowmana: one run recording why low mana (Health & Resources'
-- "Show below this much mana") doesn't bring up your resource bar or player
-- frame. For 40 seconds the big test box (ns.PadTestBox) says what to do and
-- what it sees, and the log ("lowmana") gets each link of the chain whenever
-- it changes: CineMode, the page, the slider and tick, the game's display
-- setting, your mana and whether it reads as low, and per frame whether the
-- rule keeps it up, its fade alpha and whether it's drawn. A verdict at the
-- end names the first link that broke. Dev copy only (CinematicDev.toc).
local _, ns = ...

local LENGTH = 40 -- seconds
local WATCH = {
	PlayerFrame = "portraitWhenNotFull", ElvUF_Player = "portraitWhenNotFull",
	ElvUF_Player_PowerBar = "portraitWhenNotFull",
	PersonalResourceDisplayFrame = "prdWhenNotFull", CinematicPersonalResource = "prdWhenNotFull",
	CinematicPersonalPower = "prdWhenNotFull", CinematicPersonalMana = "prdWhenNotFull",
}

local run -- { at, ticker, last, facts }

local function Log(text) ns.Log("lowmana", text) end
local function Num(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Readable(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end
local function Bool(value)
	if issecretvalue and issecretvalue(value) then return "secret" end
	return value and "yes" or "no"
end

-- Your mana now: share (nil: secret), and the line for the log.
local function Mana()
	local powerType = UnitPowerType("player")
	local mana, maxMana = UnitPower("player", 0), UnitPowerMax("player", 0)
	local share = Readable(mana) and Readable(maxMana) and maxMana > 0 and mana / maxMana or nil
	return share, ("power type %s, mana %s/%s"):format(Num(powerType), Num(mana), Num(maxMana))
end

-- A frame's parents up to UIParent: name(alpha, ignores parent alpha).
local function Chain(frame)
	local out = {}
	for _ = 1, 4 do
		if not frame or frame == UIParent then break end
		local okName, name = pcall(frame.GetName, frame)
		local okAlpha, alpha = pcall(frame.GetAlpha, frame)
		local ignoring = frame.IsIgnoringParentAlpha and frame:IsIgnoringParentAlpha()
		out[#out + 1] = ("%s(%s%s)"):format(okName and tostring(name) or "?", okAlpha and Num(alpha) or "?",
			ignoring and ", ignores parent" or "")
		local okParent, parent = pcall(frame.GetParent, frame)
		frame = okParent and parent or nil
	end
	return table.concat(out, " < ")
end

-- The game's own answer to "is mana under the share?", shown: a sign whose
-- alpha it sets from your mana through the same curve the frames get.
local sign
local function Sign(show)
	if not sign then
		sign = CreateFrame("Frame", nil, UIParent)
		sign:SetFrameStrata("TOOLTIP")
		sign:SetSize(420, 40)
		sign:SetPoint("TOP", 0, -170)
		local back = sign:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0.5, 0, 0, 0.85)
		local text = sign:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		text:SetPoint("CENTER")
		text:SetText("LOW MANA (the game says so)")
		text:SetTextColor(1, 1, 1)
	end
	sign:SetShown(show)
	if show then ns.SetLowManaSecretAlpha(sign) end
end

local function Tick()
	local db = ns.db
	local facts = run.facts
	local cine = ns.lastCinematic and true or false
	local pageOn = ns.PersonalResourcesOn()
	local wanted = db.prPowerPlayer or 0
	local share, manaLine = Mana()
	local low = ns.LowManaNow and ns.LowManaNow() or false
	local displayOn = ns.PersonalDisplayOn and ns.PersonalDisplayOn()
	local manaBar = ns.PersonalManaShown and ns.PersonalManaShown()
	facts.cine = facts.cine or cine
	facts.page = facts.page or pageOn
	facts.read = facts.read or share ~= nil
	facts.low = facts.low or (cine and low)
	if share then facts.lowest = math.min(facts.lowest or 1, share) end
	local head = ("CineMode %s | page %s | slider %d%% | your player frame too %s | game display %s | our mana bar %s | " ..
		"in combat %s"):format(Bool(cine), Bool(pageOn), math.floor(wanted * 100 + 0.5), Bool(wanted > 0),
		Bool(displayOn), Bool(manaBar), Bool(InCombatLockdown()))
	local frames, shown = {}, {}
	for _, entry in ipairs(ns.managed or {}) do
		local setting = entry.name and WATCH[entry.name]
		if setting then
			local ok, keep = pcall(ns.KeepYourFrameUp, setting, entry, false, false)
			keep = ok and keep or false
			local frame = entry.frame
			local okVis, visible = pcall(frame.IsVisible, frame)
			local okEff, effective = pcall(frame.GetEffectiveAlpha, frame)
			local f = facts[entry.name] or { kept = 0, alpha = 0, drawn = false }
			facts[entry.name] = f
			if keep and cine then f.kept = f.kept + 1 end
			if Readable(entry.alpha) then f.alpha = math.max(f.alpha, entry.alpha) end
			local drawn = okVis and visible == true and okEff and Readable(effective) and effective > 0.5
			f.drawn = f.drawn or (drawn and Readable(entry.alpha) and entry.alpha > 0.5)
			f.group = entry.group
			if entry.manaSecret then f.secret = (f.secret or 0) + 1 end
			frames[#frames + 1] = ("%s [%s] rule %s, secret mana alpha %s, fade %s, visible %s, drawn alpha %s"):format(
				entry.name, tostring(entry.group), Bool(keep), Bool(entry.manaSecret), Num(entry.alpha),
				okVis and Bool(visible) or "?", okEff and Num(effective) or "?")
			if entry.manaSecret then run.secretUsed = entry.name end
			if entry.name == "ElvUF_Player_PowerBar" then run.barNested = entry.nested or false end
			if drawn then shown[#shown + 1] = entry.name end
		end
	end
	Sign(share == nil)
	local bar = _G.ElvUF_Player_PowerBar
	local barLine = type(bar) == "table" and bar.GetParent and (" | ElvUI bar: %s, detached %s, set by us %s, nested %s"):format(
		Chain(bar), tostring(_G.ElvUF_Player and _G.ElvUF_Player.POWERBAR_DETACHED), tostring(bar.cinematicOwnAlpha),
		tostring(run.barNested)) or ""
	local line = ("%s | %s, low %s | curve API %s, curve error %s | %s%s"):format(head, manaLine, Bool(low),
		Bool(ns.ManaCurveReady and ns.ManaCurveReady()), tostring(ns.lowManaSecretError), table.concat(frames, "; "),
		barLine)
	if line ~= run.last then
		run.last = line
		Log(("%.1fs %s"):format(GetTime() - run.at, line))
	end
	-- The box: what to do, and what it sees.
	local left = math.max(0, math.ceil(LENGTH - (GetTime() - run.at)))
	local say
	if not cine then
		say = "Turn CineMode ON"
	elseif not share and Readable(UnitPowerMax("player", 0)) and UnitPowerMax("player", 0) == 0 then
		say = "This character has no mana (max mana 0): log one that has"
	elseif not share then
		say = ("Spend mana under %d%%. When the red LOW MANA sign shows, does your %s show too?"):format(
			math.floor(wanted * 100 + 0.5), run.secretUsed or "player frame")
	elseif share >= wanted then
		say = ("Spend mana: cast heals till you're under %d%% (now %d%%)"):format(math.floor(wanted * 100 + 0.5),
			math.floor(share * 100))
	else
		say = ("Mana %d%%: low. Up now: %s"):format(math.floor(share * 100),
			#shown > 0 and table.concat(shown, ", ") or "NOTHING")
	end
	ns.PadTestBox(say, ("%d sec left  (type it again to stop)"):format(left))
	if left <= 0 then ns.LowManaTest(true) end
end

local function Verdict()
	local f, db = run.facts, ns.db
	local wanted = math.floor((db.prPowerPlayer or 0) * 100 + 0.5)
	if not f.cine then return "CineMode was never on: low mana only brings frames up in CineMode" end
	if not f.page then return "The Health & Resources page was off" end
	if wanted == 0 then return "Player Frame's power row is at Show below 0%" end
	if not f.read then
		local used = {}
		for name in pairs(WATCH) do
			if f[name] and f[name].secret then used[#used + 1] = name end
		end
		if #used == 0 then
			return ("Mana secret all run, and no frame got the game's alpha (curve API %s)"):format(
				Bool(ns.ManaCurveReady and ns.ManaCurveReady()))
		end
		return ("Mana secret: the game set the alpha of %s%s. Did it come up under the share? Tell me"):format(
			table.concat(used, ", "), ns.lowManaSecretError and (" (error: " .. ns.lowManaSecretError .. ")") or "")
	end
	if not f.low then
		return ("Your mana never read as low: lowest %d%%, needs under %d%%"):format(math.floor((f.lowest or 1) * 100),
			wanted)
	end
	local kept, faded, notDrawn, worked = {}, {}, {}, {}
	for name in pairs(WATCH) do
		local frame = f[name]
		if frame and frame.kept > 0 then
			kept[#kept + 1] = name
			if frame.drawn then
				worked[#worked + 1] = name
			elseif frame.alpha < 0.5 then
				faded[#faded + 1] = ("%s (fade reached %.2f)"):format(name, frame.alpha)
			else
				notDrawn[#notDrawn + 1] = name
			end
		end
	end
	if #kept == 0 then
		return ("Low mana read, but no frame took it (game display on %s, Your player frame too %s)"):format(
			Bool(ns.PersonalDisplayOn and ns.PersonalDisplayOn()), Bool((db.prPowerPlayer or 0) > 0))
	end
	if #worked > 0 then return "WORKED: came up: " .. table.concat(worked, ", ") end
	if #faded > 0 then return "The rule said show, but the fade never rose: " .. table.concat(faded, ", ") end
	return "Faded in, but drawn hidden (a parent or the plate): " .. table.concat(notDrawn, ", ")
end

-- Typed again while running: stops. done: the time ran out.
function ns.LowManaTest(done)
	if run then
		run.ticker:Cancel()
		local verdict = Verdict()
		Log("verdict " .. verdict)
		ns.Print("low mana test: " .. verdict)
		run = nil
		Sign(false)
		ns.PadTestBox(done and "Test done." or "Test stopped.", verdict, 1, 0.82, 0)
		C_Timer.After(15, function() if not run then ns.PadTestBoxHide() end end)
		return
	end
	if done then return end
	local addons = {}
	for _, name in ipairs({ "ElvUI", "EllesmereUI", "ShadowedUnitFrames", "UnhaltedUnitFrames" }) do
		if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) then addons[#addons + 1] = name end
	end
	run = { at = GetTime(), facts = {} }
	Log(("start: unit frame addons loaded: %s"):format(#addons > 0 and table.concat(addons, ", ") or "none"))
	run.ticker = C_Timer.NewTicker(0.5, function()
		local ok, err = pcall(Tick)
		if not ok then Log("error: " .. tostring(err)) end
	end)
	ns.Print(("low mana test: %d sec, follow the box"):format(LENGTH))
end
