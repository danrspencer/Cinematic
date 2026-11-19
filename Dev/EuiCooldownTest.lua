-- /cine debug euicd: one run finding why a spell's icon goes missing from
-- EllesmereUI's cooldown bar (its cooldown manager places the game's
-- Essential and Utility icons on its own ECME_CDMBar_* bars) with Cinematic
-- on (player report 2026-11-16: "makes my 3rd cooldown disappear"). Three
-- timed steps in the test box:
--   1 now:    out of a fight, as it is (our per-spell fades on);
--   2 paused: the same, the Cooldown Manager page's per-spell fades paused
--             (ns.cooldownFadePaused: every icon back to full);
--   3 fight:  fades on again, attacking a dummy or an enemy and casting.
-- Recorded the whole time, into CinematicDB.euiCdTestLog:
--   twice a second when anything changes, each icon in the game's spell bars
--   (spell, shown, alpha, effective alpha, our fade target and alpha, its
--   mode and where that comes from, its parent and anchor) and the children
--   of EllesmereUI's bars;
--   every SetAlpha under 0.05 on those icons, counted by who did it (us,
--   EllesmereUI, other) with the first caller's stack;
--   our settings and EllesmereUI's for its bars; a screenshot each step.
-- Verdicts at the end, one per spell. Dev copy only (CinematicDev.toc).
local addonName, ns = ...

local WAIT = 4 -- seconds to read the box
local ICON_STEPS = {
	{ secs = 12, say = "1/3: Stand STILL, OUT OF A FIGHT. Don't cast. Look at EllesmereUI's cooldown bar.", tag = "now" },
	{ secs = 12, say = "2/3: Still STILL, no casting. (Cinematic's per-spell fades are paused now.)", tag = "paused" },
	{ secs = 20, say = "3/3: ATTACK a target dummy or an enemy and CAST your spells, the 3rd one too.", tag = "fight" },
}
local STEPS = ICON_STEPS -- (the run's steps: these, or the bars run's, below)
local SPELL_BARS = { EssentialCooldownViewer = "essential", UtilityCooldownViewer = "utility" }
local EUI_BARS = { "ECME_CDMBar_cooldowns", "ECME_CDMBar_utility" }
local MAX_LINES = 5000

local run -- { step, at, ticker, last, seen = { [tag] = { [icon] = facts } }, darks = { [key] = n }, firsts }
local hookedIcons = setmetatable({}, { __mode = "k" })

local function Log(text)
	local log = CinematicDB and CinematicDB.euiCdTestLog
	if not log or #log >= MAX_LINES then return end
	log[#log + 1] = ("%.2f %s %s"):format(GetTime(), run and STEPS[run.step] and STEPS[run.step].tag or "-", text)
end

local function Secret(value) return issecretvalue and issecretvalue(value) end
local function Num(value)
	if value == nil then return "nil" end
	if Secret(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Plain(value)
	return type(value) == "number" and not Secret(value) and value or nil
end
local function Call(frame, method, ...)
	if not (frame and frame[method]) then return nil end
	local ok, value = pcall(frame[method], frame, ...)
	if not ok then return nil end
	return value
end
local function NameOf(frame)
	if type(frame) ~= "table" then return tostring(frame) end
	if Secret(frame) then return "secret" end
	local name = Call(frame, "GetName")
	if type(name) == "string" and not Secret(name) then return name end
	local debugName = Call(frame, "GetDebugName")
	return type(debugName) == "string" and not Secret(debugName) and debugName or "(no name)"
end

local function SpellLabel(id)
	if not id then return "spell ?" end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	return ("%s (%s)"):format(Secret(name) and "secret" or tostring(name), tostring(id))
end

-- Who called SetAlpha, by the first lines of the stack past this hook.
local function Caller()
	local stack = debugstack and debugstack(3, 4, 0) or ""
	stack = stack:gsub("Interface[/\\]AddOns[/\\]", ""):gsub("%[string \"@?", ""):gsub("\"%]", "")
	return (stack:gsub("\n", " | ")):sub(1, 300)
end
local function Who(stack)
	-- (The first line not the game's own: "[C]: in function 'SetAlpha'" comes first.)
	local first = stack
	for line in stack:gmatch("[^|]+") do
		if not line:find("%[C%]") then first = line break end
	end
	if first:find("Cinematic") then return "US" end
	if first:find("Ellesmere") then return "EUI" end
	return "OTHER"
end

-- Every SetAlpha under 0.05 on an icon, counted by who (the first stack kept).
local function HookIcon(icon)
	if hookedIcons[icon] or type(icon.SetAlpha) ~= "function" then return end
	hookedIcons[icon] = true
	hooksecurefunc(icon, "SetAlpha", function(self, alpha)
		if not run then return end
		local n = Plain(alpha)
		if not n or n >= 0.05 then return end
		local stack = Caller()
		local key = ("%s by %s"):format(SpellLabel(ns.CooldownIconSpellOf(self)), Who(stack))
		run.darks[key] = (run.darks[key] or 0) + 1
		if not run.firsts[key] then
			run.firsts[key] = true
			Log(("dark SetAlpha %s on %s from %s"):format(Num(alpha), key, stack))
		end
	end)
end

-- One icon's facts as one line.
local function IconFacts(icon, id, bar)
	local group = SPELL_BARS[bar]
	local target, fade = ns.CooldownReadyState(icon)
	local mode, own = ns.CooldownSpellMode(id, group)
	local from = own and "its own" or "its group's"
	if not own and ns.db.cooldownSmartDefaults and ns.COOLDOWN_SMART_GROUPS[group] then
		local set = ns.db.cooldownGroupDefaults[group]
		if not (set and set.mode) and ns.SmartCooldownMode(ns.BaseSpell(id)) then from = "Smart set" end
	end
	local okP, point, relativeTo, relativePoint, x, y = pcall(icon.GetPoint, icon, 1)
	return {
		spell = SpellLabel(id), bar = group, place = icon.layoutIndex,
		shown = Call(icon, "IsShown"), visible = Call(icon, "IsVisible"),
		alpha = Call(icon, "GetAlpha"), effective = Call(icon, "GetEffectiveAlpha"),
		target = target, fade = fade, mode = mode or "always", from = from,
		parent = NameOf(Call(icon, "GetParent")),
		anchor = okP and ("%s %s %s %s,%s"):format(tostring(point), NameOf(relativeTo), tostring(relativePoint),
			Num(x), Num(y)) or "?",
	}
end
local function IconLine(f)
	return ("%s [%s #%s] shown %s visible %s alpha %s eff %s | ours: target %s fade %s mode %s (%s) | parent %s at %s")
		:format(f.spell, tostring(f.bar), Num(f.place), Num(f.shown), Num(f.visible), Num(f.alpha), Num(f.effective),
			Num(f.target), Num(f.fade), tostring(f.mode), f.from, f.parent, f.anchor)
end

-- The game's spell bar icons, and EllesmereUI's bars' children, as lines.
local function Snapshot()
	local icons, lines = {}, {}
	ns.EachCooldownIcon(function(icon, id, bar)
		if not SPELL_BARS[bar] then return end
		HookIcon(icon)
		local facts = IconFacts(icon, id, bar)
		icons[icon] = facts
		lines[#lines + 1] = "icon " .. IconLine(facts)
	end, true)
	table.sort(lines)
	for _, name in ipairs(EUI_BARS) do
		local bar = _G[name]
		if type(bar) ~= "table" then
			lines[#lines + 1] = name .. ": not made"
		else
			local kids = {}
			for _, child in ipairs({ bar:GetChildren() }) do
				local id = ns.CooldownIconSpellOf(child)
				kids[#kids + 1] = ("%s %s/%s/%s"):format(id and SpellLabel(id) or NameOf(child),
					ns.Flag(Call(child, "IsShown")) and "shown" or "hidden", Num(Call(child, "GetAlpha")),
					Num(Call(child, "GetEffectiveAlpha")))
			end
			lines[#lines + 1] = ("%s: shown %s alpha %s eff %s, %d children: %s"):format(name, Num(Call(bar, "IsShown")),
				Num(Call(bar, "GetAlpha")), Num(Call(bar, "GetEffectiveAlpha")), #kids, table.concat(kids, "; "))
		end
	end
	return icons, lines
end

local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(function() Screenshot() end)
	Log(ok and ("screenshot %s at %s"):format(what, date("%m%d%y_%H%M%S")) or "screenshot failed")
end

-- Our Cooldown Manager settings that fade single icons.
local function LogOurSettings()
	local db = ns.db
	local function Keys(map)
		local out = {}
		for id, value in pairs(map or {}) do out[#out + 1] = ("%s=%s"):format(tostring(id), tostring(value)) end
		table.sort(out)
		return #out > 0 and table.concat(out, ",") or "none"
	end
	Log(("ours: page on %s (own switch %s, Timers %s), cooldowns row on %s, EUI CDM support %s, close the gaps left to %s, smart %s, situation %s")
		:format(tostring(ns.PageOn("handleCooldowns") and true or false), tostring(db.handleCooldowns),
			tostring(db.handleTimers), tostring(ns.IsCombatShowOn("cooldowns")),
			tostring(ns.AddonSupportOn("EllesmereUICooldownManager")),
			tostring(ns.FeatureYieldedTo("cooldownCenter") or "nobody"), tostring(db.cooldownSmartDefaults),
			tostring(ns.cooldownSitNow or "Default")))
	for group in pairs({ essential = true, utility = true }) do
		local mode, power, early, anyTime = ns.CooldownGroupSettings(group)
		Log(("ours: %s group mode %s (power %s, early %s, out of fights %s)"):format(group, tostring(mode),
			tostring(power), tostring(early), tostring(anyTime)))
	end
	Log(("ours: ready %s; recharge %s; proc %s; always %s"):format(Keys(db.cooldownReadyOnly),
		Keys(db.cooldownRechargeOnly), Keys(db.cooldownProcOnly), Keys(db.cooldownAlwaysShow)))
	Log(("ours: spell not buff %s, keybinds %s, numbers follow %s"):format(tostring(db.cooldownSpellNotBuff),
		tostring(db.cooldownKeybinds), tostring(db.cooldownFollowNumbers)))
end

-- EllesmereUI's stored settings for its cooldown addon, scalars two deep.
local function LogEuiSettings()
	local db, eui = _G.EllesmereUIDB, _G.EllesmereUI
	local active = eui and eui.GetActiveProfileName and eui.GetActiveProfileName() or "?"
	local profile = type(db) == "table" and type(db.profiles) == "table" and db.profiles[active]
	local addons = type(profile) == "table" and profile.addons
	local cdm = type(addons) == "table" and addons.EllesmereUICooldownManager
	if type(cdm) ~= "table" then
		Log(("EUI profile %s: no cooldown manager settings stored"):format(tostring(active)))
		return
	end
	local lines = 0
	local function Dump(path, tbl, depth)
		local parts = {}
		for key, value in pairs(tbl) do
			if type(value) == "table" then
				if depth < 3 then Dump(path .. "." .. tostring(key), value, depth + 1) end
			else
				parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
			end
		end
		if #parts > 0 and lines < 60 then
			lines = lines + 1
			table.sort(parts)
			Log(("EUI %s: %s"):format(path, table.concat(parts, " "):sub(1, 900)))
		end
	end
	Dump("profile " .. tostring(active), cdm, 1)
end

local function Verdict(name, ok, detail)
	Log(("VERDICT %s: %s%s"):format(name, ok == nil and "CAN'T TELL" or (ok and "PASS" or "FAIL"),
		detail and (" (" .. detail .. ")") or ""))
end

-- Seen: shown, and its effective alpha over 0.5 (nil when unreadable).
local function Seen(f)
	if not f then return nil end
	if not ns.Flag(f.shown) then return false end
	local eff = Plain(f.effective)
	if not eff then return nil end
	return eff > 0.5
end

local function Finish()
	ns.cooldownFadePaused = nil
	ns.readyPace.due = true
	local now, paused, fight = run.seen.now or {}, run.seen.paused or {}, run.seen.fight or {}
	local bySpell = {}
	for _, step in ipairs({ now, paused, fight }) do
		for _, f in pairs(step) do bySpell[f.spell] = bySpell[f.spell] or f end
	end
	local function Find(step, spell)
		for _, f in pairs(step) do if f.spell == spell then return f end end
	end
	local spells = {}
	for spell in pairs(bySpell) do spells[#spells + 1] = spell end
	table.sort(spells)
	for _, spell in ipairs(spells) do
		local a, b, c = Find(now, spell), Find(paused, spell), Find(fight, spell)
		local seenA, seenB, seenC = Seen(a), Seen(b), Seen(c)
		local f = a or b or c
		local detail = ("still %s, paused %s, fight %s; our mode %s (%s)"):format(tostring(seenA), tostring(seenB),
			tostring(seenC), f.mode, f.from)
		if seenA == false and seenB == true then
			Verdict(spell .. ": hidden by OUR per-spell fade", false, detail)
		elseif seenA == false and seenB == false then
			Verdict(spell .. ": hidden with our fade paused too (not that)", false, detail)
		elseif seenC == false then
			Verdict(spell .. ": hidden in the fight", false, detail)
		else
			Verdict(spell .. ": seen", seenA ~= nil and seenB ~= nil, detail)
		end
	end
	local darks = {}
	for key, count in pairs(run.darks) do darks[#darks + 1] = ("%s x%d"):format(key, count) end
	table.sort(darks)
	Log("dark SetAlpha counts: " .. (#darks > 0 and table.concat(darks, ", ") or "none"))
	run.ticker:Cancel()
	run = nil
	ns.PadTestBox("Test done. Type /reload to save it, then say 'check log'.", "", 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
end

-- /cine debug euicd bars: the whole bars, not single icons (Reddit report
-- 2026-11-19: "my cooldown manager refused to show on the screen when it was
-- supposed to", with EllesmereUI). Three timed steps: CineMode off, then on,
-- out of a fight; then on, in a fight. Each half second when anything
-- changes: each of EllesmereUI's bars and the game's viewers (shown, alpha,
-- effective alpha, how many icons), our fade entry for it (group, the alpha
-- we want and set), and its row's In combat tick. At each step's end, /cine
-- why's reasons for each bar. Verdicts: a bar hidden where its row says it
-- shows. Into CinematicDB.euiCdTestLog too.
local BAR_STEPS = {
	{ secs = 10, say = "1/3: Stand STILL, OUT OF A FIGHT. CineMode is OFF now.", tag = "off", cine = false },
	{ secs = 10, say = "2/3: Still OUT OF A FIGHT. CineMode is ON now.", tag = "cine", cine = true },
	{ secs = 20, say = "3/3: ATTACK a target dummy or an enemy and CAST. CineMode stays ON.", tag = "fight", cine = true },
}
-- Each bar and the row that should show it.
local WHOLE_BARS = {
	{ "ECME_CDMBar_cooldowns", "addon:euiCooldowns" }, { "ECME_CDMBar_utility", "addon:euiCooldowns" },
	{ "ECME_CDMBar_buffs", "addon:euiCooldowns" },
	{ "EssentialCooldownViewer", "cooldowns" }, { "UtilityCooldownViewer", "cooldownsutility" },
	{ "BuffIconCooldownViewer", "cooldownsbuffs" }, { "BuffBarCooldownViewer", "cooldownsbars" },
}

local function EntryOf(frame)
	for _, entry in ipairs(ns.managed) do
		if entry.frame == frame then return entry end
	end
end

local function BarFacts(name, rowKey)
	local frame = _G[name]
	if type(frame) ~= "table" then return { name = name, row = rowKey, made = false } end
	local entry = EntryOf(frame)
	local icons = 0
	for _, child in ipairs({ frame:GetChildren() }) do
		if ns.Flag(Call(child, "IsShown")) then icons = icons + 1 end
	end
	return {
		name = name, row = rowKey, made = true, frame = frame, entry = entry,
		shown = Call(frame, "IsShown"), visible = Call(frame, "IsVisible"),
		alpha = Call(frame, "GetAlpha"), effective = Call(frame, "GetEffectiveAlpha"), icons = icons,
		rowOn = ns.IsCombatShowOn(rowKey),
	}
end
local function BarLine(f)
	if not f.made then return ("%s (row %s): not made"):format(f.name, f.row) end
	local e = f.entry
	return ("%s (row %s, In combat %s): shown %s visible %s alpha %s eff %s, %d icons shown | ours: %s")
		:format(f.name, f.row, tostring(f.rowOn), Num(f.shown), Num(f.visible), Num(f.alpha), Num(f.effective),
			f.icons, e and ("group %s want %s set %s"):format(tostring(e.group), Num(e.alpha), Num(e.applied))
				or "not faded by us")
end

local function BarsFinish()
	for _, spec in ipairs(WHOLE_BARS) do
		local name = spec[1]
		local off, cine, fight = run.seen.off[name], run.seen.cine[name], run.seen.fight[name]
		local any = (off and off.icons or 0) + (cine and cine.icons or 0) + (fight and fight.icons or 0)
		if not (off and off.made) then
			Verdict(name, nil, "not made: its bar is off or empty")
		elseif any == 0 then
			-- (An empty bar is kept at alpha 0: nothing to see either way.)
			Verdict(name .. ": no icons the whole run", nil, "empty, nothing to tell")
		else
			local detail = ("CineMode off %s, on %s, fight %s; row In combat %s"):format(tostring(Seen(off)),
				tostring(Seen(cine)), tostring(Seen(fight)), tostring(fight and fight.rowOn))
			if Seen(off) == false then
				Verdict(name .. ": hidden with CineMode OFF", false, detail)
			elseif fight and fight.rowOn and Seen(fight) == false then
				Verdict(name .. ": hidden in the FIGHT though its row's In combat is ticked", false, detail)
			else
				Verdict(name .. ": as its row says", Seen(off) ~= nil, detail)
			end
		end
	end
	run.ticker:Cancel()
	run = nil
	ns.PadTestBox("Test done. Type /reload to save it, then say 'check log'.", "", 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
end

local function WhyAll(tag)
	for _, spec in ipairs(WHOLE_BARS) do
		local frame = _G[spec[1]]
		local entry = type(frame) == "table" and EntryOf(frame)
		if entry then
			ns.WhyLater(entry, function(ok, status, out)
				Log(("why %s at %s: %s"):format(spec[1], tag, ok and tostring(status) or ("error " .. tostring(status))))
				for _, reason in ipairs(ok and out or {}) do
					Log(("  [%s] %s%s"):format(tostring(reason.state), tostring(reason.text),
						reason.page and (" (" .. reason.page .. ")") or ""))
				end
			end)
		end
	end
end

local function SetCine(want)
	if (ns.lastCinematic and true or false) ~= want and _G.Cinematic_ToggleCineMode then
		_G.Cinematic_ToggleCineMode()
		Log("CineMode turned " .. (want and "ON" or "OFF"))
	end
end

local function BarsTest()
	CinematicDB.euiCdTestLog = {}
	STEPS = BAR_STEPS
	run = { step = 1, at = GetTime(), seen = {}, darks = {}, firsts = {}, bars = true }
	local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	local function Version(addon)
		local ok, value = pcall(meta, addon, "Version")
		return ok and tostring(value) or "?"
	end
	local _, class = UnitClass("player")
	Log(("start bars %s: Cinematic %s, game %s, EllesmereUI CDM %s, profile %s, class %s"):format(
		date("%Y-%m-%d %H:%M"), Version(addonName), tostring((GetBuildInfo())),
		Version("EllesmereUICooldownManager"), tostring(ns.ActiveProfile and ns.ActiveProfile()), tostring(class)))
	LogOurSettings()
	LogEuiSettings()
	SetCine(false)
	run.ticker = C_Timer.NewTicker(0.5, function()
		if not run then return end
		local step = STEPS[run.step]
		local into = GetTime() - run.at
		if into < WAIT then
			ns.PadTestBox(step.say, ("GET READY: starts in %d"):format(math.ceil(WAIT - into)), 1, 0.82, 0)
		else
			ns.PadTestBox(step.say, ("RECORDING: %d sec left"):format(math.ceil(step.secs - into)), 0.2, 1, 0.2)
		end
		local facts, lines = {}, {}
		for _, spec in ipairs(WHOLE_BARS) do
			local f = BarFacts(spec[1], spec[2])
			facts[spec[1]] = f
			lines[#lines + 1] = BarLine(f)
		end
		local text = table.concat(lines, "\n")
		if text ~= run.last then
			run.last = text
			Log(("snapshot (combat %s, CineMode %s):"):format(InCombatLockdown() and "yes" or "no",
				ns.lastCinematic and "on" or "off"))
			for _, line in ipairs(lines) do Log("  " .. line) end
		end
		if into >= step.secs then
			run.seen[step.tag] = facts
			WhyAll(step.tag)
			Shot(step.tag)
			if run.step >= #STEPS then
				run.ticker:Cancel()
				C_Timer.After(0.8, function() if run then BarsFinish() end end)
				return
			end
			run.step, run.at = run.step + 1, GetTime()
			SetCine(STEPS[run.step].cine)
		end
	end)
end

function ns.EuiCooldownTest(bars)
	if run then
		run.ticker:Cancel()
		run = nil
		ns.cooldownFadePaused = nil
		ns.readyPace.due = true
		ns.PadTestBoxHide()
		ns.Print("euicd test stopped")
		return
	end
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	if not isLoaded("EllesmereUICooldownManager") then
		ns.Print("euicd test: EllesmereUI Cooldown Manager isn't loaded")
		return
	end
	if bars then
		BarsTest()
		return
	end
	STEPS = ICON_STEPS
	CinematicDB.euiCdTestLog = {}
	run = { step = 1, at = GetTime(), seen = {}, darks = {}, firsts = {} }
	local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	local function Version(addon)
		local ok, value = pcall(meta, addon, "Version")
		return ok and tostring(value) or "?"
	end
	local _, class = UnitClass("player")
	local spec = GetSpecialization and GetSpecialization()
	Log(("start %s: Cinematic %s, game %s, EllesmereUI CDM %s, profile %s, class %s spec %s, CineMode %s"):format(
		date("%Y-%m-%d %H:%M"), Version(addonName), tostring((GetBuildInfo())),
		Version("EllesmereUICooldownManager"), tostring(ns.ActiveProfile and ns.ActiveProfile()), tostring(class),
		tostring(spec), ns.lastCinematic and "on" or "off"))
	LogOurSettings()
	LogEuiSettings()
	run.ticker = C_Timer.NewTicker(0.5, function()
		if not run then return end
		local step = STEPS[run.step]
		local into = GetTime() - run.at
		if into < WAIT then
			ns.PadTestBox(step.say, ("GET READY: starts in %d"):format(math.ceil(WAIT - into)), 1, 0.82, 0)
		else
			ns.PadTestBox(step.say, ("RECORDING: %d sec left"):format(math.ceil(step.secs - into)), 0.2, 1, 0.2)
		end
		local icons, lines = Snapshot()
		local text = table.concat(lines, "\n")
		if text ~= run.last then
			run.last = text
			Log(("snapshot (combat %s):"):format(InCombatLockdown() and "yes" or "no"))
			for _, line in ipairs(lines) do Log("  " .. line) end
		end
		if into >= step.secs then
			run.seen[step.tag] = icons
			Shot(step.tag)
			if run.step >= #STEPS then
				run.ticker:Cancel()
				C_Timer.After(0.6, function() if run then Finish() end end)
				return
			end
			run.step, run.at = run.step + 1, GetTime()
			-- (Step 2 pauses our per-spell fades; step 3 puts them back.)
			ns.cooldownFadePaused = STEPS[run.step].tag == "paused" or nil
			ns.readyPace.due = true
			Log("our per-spell fades " .. (ns.cooldownFadePaused and "PAUSED" or "on"))
		end
	end)
end
