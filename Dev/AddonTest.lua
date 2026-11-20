-- Testing Cinematic's support for another addon (the /addon-support skill's
-- in-game half). Dev copy only.
--
-- /cine debug solo <Addon> [more addons]: turns every other addon off and
-- reloads, so only that addon (its own parts, <Addon>* folders, and what it
-- needs to load) runs with Cinematic. /cine debug solo off puts the list back
-- as it was and reloads. While solo is on, each login says so on screen and
-- names any other addon that still loaded.
--
-- /cine debug addontest <Addon> [quick]: one run that tests itself, logged
-- into CinematicDB.addonTestLog (/reload, then "check log"). CineMode off for
-- the run, back as it was at the end.
--   1 target: you target anything (frames that only show with a target);
--   2 fight: you fight something, a dummy will do; it goes on once the
--     fight ends (quick skips 1 and 2);
--   3 rows: hands off. Each row the addon's frames fade with (its own rows on
--     the Addons page, and the game's rows its frames stand in for) is hidden
--     by its key, then shown, then handed back. Per row: did every frame go to
--     0 and stay there (an addon setting its alpha back fights our fade), did
--     each come back, and did it stop taking the mouse while hidden (hover
--     would need ns.HOVER_BY_RECT). A screenshot of each hidden row.
-- All along, every frame the addon made (named or not, told by the game's
-- taint record: whose code made it) that draws something on screen is
-- checked: faded by us (itself or a frame it sits in), left alone on
-- purpose, or NOT COVERED. Every NOT COVERED frame is a frame the support
-- missed. Verdicts at the end.
local addonName, ns = ...

local GetNum = C_AddOns and C_AddOns.GetNumAddOns or _G.GetNumAddOns
local GetInfo = C_AddOns and C_AddOns.GetAddOnInfo or _G.GetAddOnInfo
local GetDeps = C_AddOns and C_AddOns.GetAddOnDependencies or _G.GetAddOnDependencies
local GetOptDeps = C_AddOns and C_AddOns.GetAddOnOptionalDependencies or _G.GetAddOnOptionalDependencies
local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
local EnableAddOn = C_AddOns and C_AddOns.EnableAddOn or _G.EnableAddOn
local DisableAddOn = C_AddOns and C_AddOns.DisableAddOn or _G.DisableAddOn
local SaveAddOns = C_AddOns and C_AddOns.SaveAddOns or _G.SaveAddOns
local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata

local function Secret(value) return issecretvalue and issecretvalue(value) end
local function Num(value)
	if value == nil then return "nil" end
	if Secret(value) then return "secret" end
	if type(value) == "number" then return ("%.2f"):format(value) end
	return tostring(value)
end
local function Call(object, method, ...)
	if not (object and object[method]) then return nil end
	local ok, a, b, c, d = pcall(object[method], object, ...)
	if not ok then return nil end
	return a, b, c, d
end

-- Every addon in the list: { name, enabled, loaded, state (0 off, 1 some
-- characters, 2 all) }. (GetAddOnEnableState's arguments swapped places
-- between clients: both tried.)
local function EnableState(name)
	local fn = C_AddOns and C_AddOns.GetAddOnEnableState
	if fn then
		local ok, state = pcall(fn, name)
		if ok and type(state) == "number" then return state end
		ok, state = pcall(fn, name, UnitName("player"))
		if ok and type(state) == "number" then return state end
	end
	if _G.GetAddOnEnableState then
		local ok, state = pcall(_G.GetAddOnEnableState, nil, name)
		if ok and type(state) == "number" then return state end
	end
	return nil
end

local function AddOns()
	local out = {}
	for i = 1, (GetNum and GetNum() or 0) do
		local name, _, _, _, reason = GetInfo(i)
		if name then
			out[#out + 1] = {
				name = name, enabled = reason ~= "DISABLED", loaded = IsLoaded(name) and true or false,
				state = EnableState(name),
			}
		end
	end
	return out
end

-- The installed addon whose name is this (any case), or nil.
local function Resolve(typed)
	for _, each in ipairs(AddOns()) do
		if each.name:lower() == typed:lower() then return each.name end
	end
	return nil
end

-- Whether an addon name is the target's, or one of its parts (EllesmereUI's
-- EllesmereUIResourceBars, Questie's Questie_*).
local function Belongs(name, target)
	return type(name) == "string" and name:lower():sub(1, #target) == target:lower()
end

-------------------------------------------------------------------- solo
-- (Libraries it can use, kept: LibSharedMedia, Ace3... Not every "!" name:
-- !KalielsTracker is a whole tracker, kept by mistake in the first run.)
local function IsLib(name)
	return (name:find("^Lib") or name:find("^Ace")) ~= nil
end

function ns.SoloAddons(words)
	local db = CinematicDB
	if words == "" then
		local solo = db.soloAddons
		ns.Print(type(solo) == "table" and ("solo: on since %s for %s. /cine debug solo off brings the rest back."):format(
			tostring(solo.at), table.concat(solo.keep or {}, ", "))
			or "solo: off. /cine debug solo <Addon> [more] turns every other addon off and reloads.")
		return
	end
	if words == "off" then
		local solo = db.soloAddons
		if type(solo) ~= "table" then
			ns.Print("solo: not on. /cine debug solo <Addon> turns every other addon off.")
			return
		end
		local me = UnitName("player")
		for name, state in pairs(solo.turnedOff or {}) do
			-- (On for some characters only: back on for this one at least.)
			if state == 1 then pcall(EnableAddOn, name, me) else pcall(EnableAddOn, name) end
		end
		for name, state in pairs(solo.turnedOn or {}) do
			if state == 0 then pcall(DisableAddOn, name) end
		end
		db.soloAddons = nil
		SaveAddOns()
		ns.Print("solo off: your addon list is back. Reloading.")
		ns.ReloadOrAsk("Solo off: your addon list is back. Reload now?")
		return
	end
	if type(db.soloAddons) == "table" then
		ns.Print("solo: already on for " .. table.concat(db.soloAddons.keep or {}, ", ") ..
			". /cine debug solo off first.")
		return
	end
	local keep, turnedOff, turnedOn = {}, {}, {}
	keep[addonName] = true
	local wanted = {}
	for typed in words:gmatch("%S+") do
		local name = Resolve(typed)
		if not name then
			ns.Print("solo: no addon called " .. typed .. " is installed.")
			return
		end
		wanted[#wanted + 1] = name
	end
	local all = AddOns()
	-- Its parts (folders starting with its name) that were on, and what each
	-- kept one needs to load (and the libraries it can use), all the way down.
	-- An addon that was off itself brings every part of it: its parts were off
	-- with it, not picked (EllesmereUI turned off for another UI suite came back
	-- as its core alone, none of its frames made, 2026-11-20).
	for _, name in ipairs(wanted) do
		keep[name] = true
		local wasOn = false
		for _, each in ipairs(all) do
			if each.name == name then wasOn = each.enabled end
		end
		for _, each in ipairs(all) do
			if (each.enabled or not wasOn) and Belongs(each.name, name) then keep[each.name] = true end
		end
	end
	local changed = true
	while changed do
		changed = false
		for name in pairs(keep) do
			for _, dep in ipairs(GetDeps and { GetDeps(name) } or {}) do
				if dep and not keep[dep] then keep[dep], changed = true, true end
			end
			for _, dep in ipairs(GetOptDeps and { GetOptDeps(name) } or {}) do
				if dep and IsLib(dep) and not keep[dep] then keep[dep], changed = true, true end
			end
		end
	end
	for _, each in ipairs(all) do
		if keep[each.name] then
			if not each.enabled then
				turnedOn[each.name] = each.state or 0
				EnableAddOn(each.name)
			end
		elseif each.enabled then
			turnedOff[each.name] = each.state or 2
			DisableAddOn(each.name)
		end
	end
	local kept = {}
	for name in pairs(keep) do kept[#kept + 1] = name end
	table.sort(kept)
	db.soloAddons = { keep = kept, turnedOff = turnedOff, turnedOn = turnedOn, at = date("%Y-%m-%d %H:%M") }
	SaveAddOns()
	ns.Print(("solo: only %s now. Reloading; /cine debug solo off brings the rest back."):format(table.concat(kept, ", ")))
	ns.ReloadOrAsk(("Solo: only %s now. Reload now?"):format(table.concat(kept, ", ")))
end

-- Other addons loaded besides the solo ones (and the game's own): the check.
local function Others(keep)
	local kept, out = {}, {}
	for _, name in ipairs(keep or {}) do kept[name] = true end
	for _, each in ipairs(AddOns()) do
		if each.loaded and not kept[each.name] and not each.name:find("^Blizzard_") then
			out[#out + 1] = each.name
		end
	end
	return out
end

do
	local login = CreateFrame("Frame")
	login:RegisterEvent("PLAYER_LOGIN")
	login:SetScript("OnEvent", function()
		local solo = CinematicDB and CinematicDB.soloAddons
		if type(solo) ~= "table" then return end
		C_Timer.After(3, function()
			local others = Others(solo.keep)
			local msg = "SOLO: only " .. table.concat(solo.keep or {}, ", ") .. " (/cine debug solo off brings the rest back)"
			if #others > 0 then msg = msg .. "\nStill loaded too: " .. table.concat(others, ", ") end
			ns.TestPrompt(msg, 12)
		end)
	end)
end

-------------------------------------------------------------------- the test
local MAX_LINES = 6000
local SETTLE = 4 -- seconds a row gets to reach its alpha
local HOLD = 1.5 -- seconds it must stay there (an addon setting its own back)
local run

local function Log(text)
	local log = CinematicDB and CinematicDB.addonTestLog
	if not log or #log >= MAX_LINES then return end
	log[#log + 1] = ("%.2f %s %s"):format(GetTime(), run and run.stage or "-", text)
end

local function Verdict(name, ok, detail)
	Log(("VERDICT %s: %s%s"):format(name, ok == nil and "CAN'T TELL" or (ok and "PASS" or "FAIL"),
		detail and (" (" .. detail .. ")") or ""))
	if run then
		local kind = ok == nil and "unclear" or (ok and "pass" or "fail")
		run.tally[kind] = run.tally[kind] + 1
	end
end

local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Log(ok and ("screenshot %s at %s"):format(what, date("%m%d%y_%H%M%S")) or "screenshot failed")
end

local function SetCine(on)
	if not (ns.IsCineModeOn and Cinematic_ToggleCineMode) then return end
	if (ns.IsCineModeOn() and true or false) ~= on then
		Cinematic_ToggleCineMode()
		Log("CineMode turned " .. (on and "on" or "off") .. " by the test")
	end
end

local function Name(frame)
	local name = Call(frame, "GetName")
	if type(name) == "string" then return name end
	return tostring(Call(frame, "GetDebugName") or "?")
end

-- Whose code made the frame (and how that's known): a named one by its
-- global name's taint (the game's own read as secure: nil); an unnamed one
-- by a field an addon set on it, not counting ours or a hooked method (a
-- hook writes the method onto the frame: whoever hooked it, not who made
-- it). A field only says who touched it, so those are marked "field".
local owners = setmetatable({}, { __mode = "k" })
local ownedHow = setmetatable({}, { __mode = "k" })
local function Owner(frame)
	local known = owners[frame]
	if known ~= nil then return known or nil, ownedHow[frame] end
	local by, how
	local name = Call(frame, "GetName")
	if type(name) == "string" and _G[name] == frame then
		local secure, who = issecurevariable(name)
		if not secure then by, how = who, "name" end
	else
		pcall(function()
			local meta = getmetatable(frame)
			local methods = meta and type(meta.__index) == "table" and meta.__index or {}
			for key, value in pairs(frame) do
				if key ~= 0 and not (type(value) == "function" and methods[key]) then
					local secure, who = issecurevariable(frame, key)
					if not secure and who and who ~= addonName and who ~= "Cinematic" then
						by, how = who, "field"
						break
					end
				end
			end
		end)
	end
	owners[frame], ownedHow[frame] = by or false, how
	return by, how
end

local function Rect(frame)
	local left, bottom, width, height = Call(frame, "GetRect")
	if type(left) ~= "number" or Secret(left) or Secret(width) or Secret(bottom) or Secret(height) then return nil end
	local scale = (Call(frame, "GetEffectiveScale") or 1) / UIParent:GetEffectiveScale()
	return left * scale, bottom * scale, width * scale, height * scale
end

-- Whether it draws anything itself: a shown texture or text with something
-- in it, or a kind of frame that draws (a bar, a cooldown swirl, a model).
local DRAWS = { StatusBar = true, Cooldown = true, PlayerModel = true, Model = true, ModelScene = true }
local function Draws(frame)
	if DRAWS[Call(frame, "GetObjectType") or ""] then return true end
	local drawn = false
	pcall(function()
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:IsShown() then
				local kind = region:GetObjectType()
				if kind == "FontString" then
					local text = region:GetText()
					if Secret(text) or (text and text ~= "") then drawn = true break end
				elseif kind == "Texture" then
					-- (A color texture has no file: any shown one at some alpha.)
					local alpha = region:GetAlpha()
					if Secret(alpha) or alpha > 0 then drawn = true break end
				end
			end
		end
	end)
	return drawn
end

local function FirstText(frame)
	local found
	pcall(function()
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:GetObjectType() == "FontString" then
				local text = region:GetText()
				if text and not Secret(text) and text ~= "" then found = text:sub(1, 40) break end
			end
		end
	end)
	return found
end

-- How our side covers a frame: "faded in <group>" (it or a frame it sits
-- in), "left alone", or nil.
local function Coverage(frame, managedBy)
	local at = frame
	for _ = 1, 30 do
		if not at then break end
		local entry = managedBy[at]
		if entry then
			return at == frame and ("faded in " .. tostring(entry.group))
				or ("in %s, faded in %s"):format(Name(at), tostring(entry.group))
		end
		-- (A tooltip's parts show with the tooltip, on hover: not a HUD frame.)
		if Call(at, "GetObjectType") == "GameTooltip" then return "in a tooltip (shows on hover)" end
		local name = Call(at, "GetName")
		if type(name) == "string" and ns.IsLeftAlone and ns.IsLeftAlone(name) then return "left alone" end
		-- (Ignores its parent's alpha: a faded parent doesn't take it.)
		local ignores = Call(at, "IsIgnoringParentAlpha")
		if not Secret(ignores) and ignores == true then return nil end
		at = Call(at, "GetParent")
		if at == UIParent then break end
	end
	return nil
end

local function ManagedBy()
	local map = {}
	for _, entry in ipairs(ns.managed or {}) do
		if entry.frame then map[entry.frame] = entry end
	end
	return map
end

-- One pass over every frame: the target's frames drawing on screen, each
-- logged the first time seen (and again if its cover changes).
local function Inventory()
	if not run then return end
	local managedBy = ManagedBy()
	local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
	local frame = EnumerateFrames()
	while frame do
		if not Call(frame, "IsForbidden") and Belongs(Owner(frame), run.target) then
			local visible = Call(frame, "IsVisible")
			local alpha = Call(frame, "GetEffectiveAlpha")
			local onScreen = (Secret(visible) or visible) and (Secret(alpha) or (type(alpha) == "number" and alpha > 0.01))
			local left, bottom, width, height = Rect(frame)
			if onScreen and left and width > 1 and height > 1 and left < screenW and left + width > 0
				and bottom < screenH and bottom + height > 0 and Draws(frame) then
				local cover = Coverage(frame, managedBy)
				local seen = run.frames[frame]
				if not seen or seen.cover ~= cover then
					local by, how = Owner(frame)
					local line = ("%s (%s, by %s from its %s) %s: %.0fx%.0f at %.0f,%.0f, %s, alpha %s, parent %s%s"):format(
						Name(frame), tostring(Call(frame, "GetObjectType")), tostring(by), tostring(how),
						cover and ("covered: " .. cover) or "NOT COVERED", width, height, left + width / 2,
						bottom + height / 2, tostring(Call(frame, "GetFrameStrata")), Num(alpha),
						Name(Call(frame, "GetParent")), FirstText(frame) and (", text \"" .. FirstText(frame) .. "\"") or "")
					Log("frame " .. line)
					run.frames[frame] = { cover = cover, line = line, stage = run.stage }
				end
			end
		end
		frame = EnumerateFrames(frame)
	end
end

-- The rows its frames fade with: its own rows (Addons page) and the game's
-- rows naming one of its frames (FadeWithRow).
local function Rows()
	local rows = {}
	for _, item in ipairs(ns.COMBAT_SHOW or {}) do
		local mine = item.addon and Belongs(item.addon, run.target)
		if not mine then
			for _, name in ipairs(item.frames or {}) do
				local frame = _G[name]
				if type(frame) == "table" and Belongs(Owner(frame), run.target) then mine = true break end
			end
		end
		if mine then rows[#rows + 1] = item end
	end
	return rows
end

-- The target's managed frames a row covers. (Its own rows' frames are all
-- its own, unnamed ones found by match() too, whatever the taint says.)
local function RowEntries(item)
	local groups, names, out = {}, {}, {}
	for _, group in ipairs(item.groups or {}) do groups[group] = true end
	for _, name in ipairs(item.frames or {}) do names[name] = true end
	local itsRow = item.addon and Belongs(item.addon, run.target)
	for _, entry in ipairs(ns.managed or {}) do
		if entry.frame and (groups[entry.group] or (entry.name and names[entry.name]))
			and (itsRow or Belongs(Owner(entry.frame), run.target)) then
			out[#out + 1] = entry
		end
	end
	return out
end

local function Force(key, state)
	ns.db.frameForce[key] = state
	if ns.db.frameForceAt then ns.db.frameForceAt[key] = state and GetTime() or nil end
	ns.RefreshFrameForce()
end

local function Read(entry)
	local frame = entry.frame
	return {
		visible = Call(frame, "IsVisible"), alpha = Call(frame, "GetEffectiveAlpha"),
		-- (Secret on some frames: DaylightUI's buff buttons, 2026-11-19. A
		-- secret can't be compared, so it's kept as the word.)
		mouse = (function()
			-- (Hover is the mouse moving over it: our faded bars turn only
			-- their clicks off, on purpose, so IsMouseEnabled reads false.)
			local value = frame.IsMouseMotionEnabled and Call(frame, "IsMouseMotionEnabled")
			if value == nil then value = Call(frame, "IsMouseEnabled") end
			if Secret(value) then return "secret" end
			return value
		end)(), ours = entry.alpha, base = entry.baseAlpha,
	}
end

-- Waits till every entry meets want (or SETTLE runs out), then watches HOLD
-- seconds for one leaving it; done(results) with each entry's last reading
-- and whether it held.
local function Settle(entries, want, done)
	local started, heldSince = GetTime(), nil
	local broke = {}
	local ticker
	ticker = C_Timer.NewTicker(0.2, function()
		if not run then ticker:Cancel() return end
		local all = true
		for _, entry in ipairs(entries) do
			local reading = Read(entry)
			local ok = want(reading, entry)
			if heldSince and ok == false then broke[entry] = reading end
			if ok == false then all = false end
		end
		local now = GetTime()
		if all and not heldSince then heldSince = now end
		if (heldSince and now - heldSince >= HOLD) or (not heldSince and now - started >= SETTLE) then
			ticker:Cancel()
			local results = {}
			for _, entry in ipairs(entries) do
				results[#results + 1] = { entry = entry, reading = Read(entry), broke = broke[entry] }
			end
			done(results, heldSince ~= nil)
		end
	end)
end

local function Hidden(reading)
	if Secret(reading.alpha) or Secret(reading.visible) then return nil end
	-- (Its alpha unreadable, the read itself erroring: EllesmereUI's player
	-- frame on WoW Forever, 2026-11-20, hidden on screen: can't tell.)
	if reading.visible and reading.alpha == nil then return nil end
	return not reading.visible or (type(reading.alpha) == "number" and reading.alpha <= 0.05)
end
-- Back to what it showed before the row was hidden (its own fade can keep
-- it at 0: DaylightUI's mouseover bars, 2026-11-19, first read as a FAIL).
-- before: entry -> its reading then.
local before = {}
local function Up(reading, entry)
	if Secret(reading.alpha) or Secret(reading.visible) then return nil end
	if not reading.visible then return nil end -- (hidden by the addon itself: can't tell)
	if reading.alpha == nil then return nil end -- (unreadable: can't tell)
	local was = before[entry] and before[entry].alpha
	if type(was) ~= "number" or Secret(was) then
		was = type(entry.baseAlpha) == "number" and not Secret(entry.baseAlpha) and entry.baseAlpha or 1
	end
	if was < 0.05 then return nil end -- (at 0 before too: can't tell)
	return type(reading.alpha) == "number" and reading.alpha >= was * 0.85
end

local function ReadingLine(result)
	local r = result.reading
	return ("%s: visible %s, alpha %s (ours %s, its base %s), mouse %s"):format(result.entry.name or Name(result.entry.frame),
		Num(r.visible), Num(r.alpha), Num(r.ours), Num(r.base), Num(r.mouse))
end

local Finish

local function TestRow(index)
	if not run then return end
	local item = run.rows[index]
	if not item then
		Finish(true)
		return
	end
	run.stage = "row " .. item.key
	local entries = RowEntries(item)
	local label = tostring(item.label or item.key)
	if #entries == 0 then
		Verdict(label .. " has its frames", nil, "none of its frames is faded by us now: row off, page off, or not made yet")
		C_Timer.After(0.2, function() TestRow(index + 1) end)
		return
	end
	ns.TestPrompt(("Addon test: row %d/%d, %s (hands off)"):format(index, #run.rows, label), SETTLE + HOLD + 4)
	wipe(before)
	for _, entry in ipairs(entries) do before[entry] = Read(entry) end
	Force(item.key, "hide")
	Settle(entries, Hidden, function(hiddenResults)
		Shot("hidden " .. item.key)
		local fought, notHidden, mouseOff = {}, {}, {}
		for _, result in ipairs(hiddenResults) do
			Log("hidden " .. ReadingLine(result))
			local name = result.entry.name or Name(result.entry.frame)
			if result.broke then fought[#fought + 1] = name end
			if Hidden(result.reading) == false then notHidden[#notHidden + 1] = name end
			if before[result.entry].mouse == true and result.reading.mouse == false
				and not (ns.HOVER_BY_RECT and result.entry.name and ns.HOVER_BY_RECT[result.entry.name]) then
				mouseOff[#mouseOff + 1] = name
			end
		end
		Verdict(label .. " hides", #notHidden == 0, #notHidden > 0 and ("still up: " .. table.concat(notHidden, ", ")) or
			(#entries .. " frames"))
		Verdict(label .. " stays hidden", #fought == 0,
			#fought > 0 and ("set its alpha back: " .. table.concat(fought, ", ")) or nil)
		if #mouseOff > 0 then
			Verdict(label .. " keeps the mouse while hidden", false,
				"turned the mouse off, hover can't bring it back (ns.HOVER_BY_RECT?): " .. table.concat(mouseOff, ", "))
		end
		Force(item.key, "show")
		Settle(entries, Up, function(upResults)
			local down, unclear = {}, 0
			for _, result in ipairs(upResults) do
				Log("shown " .. ReadingLine(result))
				local up = Up(result.reading, result.entry)
				if up == false then down[#down + 1] = result.entry.name or Name(result.entry.frame) end
				if up == nil then unclear = unclear + 1 end
			end
			Verdict(label .. " comes back", #down == 0 and (unclear < #upResults or nil),
				#down > 0 and ("still down: " .. table.concat(down, ", ")) or
				(unclear > 0 and (unclear .. " hidden or at alpha 0 by the addon itself") or nil))
			Force(item.key, run.forceBefore[item.key])
			C_Timer.After(1, function() TestRow(index + 1) end)
		end)
	end)
end

local STEPS = {
	{ tag = "target", say = "Addon test 1/3: TARGET anything (an NPC, a player, yourself)." },
	{ tag = "fight", say = "Addon test 2/3: FIGHT something (a target dummy works). The test goes on by itself when the fight ends." },
}

local events = CreateFrame("Frame")

local function StartRows()
	if not run then return end
	events:UnregisterAllEvents()
	run.stage = "rows"
	Inventory()
	run.rows = Rows()
	run.forceBefore = {}
	for _, item in ipairs(run.rows) do run.forceBefore[item.key] = ns.db.frameForce[item.key] end
	Log(("%d rows to test: %s"):format(#run.rows, (function()
		local keys = {}
		for _, item in ipairs(run.rows) do keys[#keys + 1] = item.key end
		return table.concat(keys, ", ")
	end)()))
	TestRow(1)
end

local function Step(index)
	if not run then return end
	local step = STEPS[index]
	if not step or run.quick then
		StartRows()
		return
	end
	run.step, run.stage = index, step.tag
	events:UnregisterAllEvents()
	if step.tag == "target" then
		events:RegisterEvent("PLAYER_TARGET_CHANGED")
	else
		events:RegisterEvent("PLAYER_REGEN_DISABLED")
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
	ns.TestPrompt(step.say, 3600)
end

events:SetScript("OnEvent", function(_, event)
	if not run then return end
	if event == "PLAYER_TARGET_CHANGED" and UnitExists("target") and run.step == 1 then
		run.step = "target seen"
		Log("target: " .. tostring(UnitName("target")))
		C_Timer.After(1.5, function()
			Inventory()
			Shot("target")
			Step(2)
		end)
	elseif event == "PLAYER_REGEN_DISABLED" then
		run.fought = true
		Log("fight started")
		C_Timer.After(2, function() Shot("fight") end)
	elseif event == "PLAYER_REGEN_ENABLED" and run.fought and run.step == 2 then
		run.step = "fight over"
		Log("fight over")
		C_Timer.After(1, function() Step(3) end)
	end
end)

Finish = function(done)
	if not run then return end
	run.ticker:Cancel()
	events:UnregisterAllEvents()
	-- (Rows still forced by the test go back to what they were.)
	for _, item in ipairs(run.forceBefore and run.rows or {}) do
		if ns.db.frameForce[item.key] ~= run.forceBefore[item.key] then Force(item.key, run.forceBefore[item.key]) end
	end
	if done then
		Inventory()
		local open, covered = {}, 0
		for _, seen in pairs(run.frames) do
			if seen.cover then covered = covered + 1 else open[#open + 1] = seen.line end
		end
		table.sort(open)
		Verdict("every frame on screen covered", #open == 0,
			("%d covered, %d NOT COVERED"):format(covered, #open))
		for _, line in ipairs(open) do Log("  NOT COVERED " .. line) end
		Verdict("its parts loaded", #run.unloaded == 0, #run.unloaded > 0
			and ("not loaded, their rows untested: " .. table.concat(run.unloaded, ", ")) or nil)
		Verdict("ran alone", #run.others == 0, #run.others > 0 and ("also loaded: " .. table.concat(run.others, ", ")) or nil)
		Log(("totals: %d pass, %d fail, %d can't tell"):format(run.tally.pass, run.tally.fail, run.tally.unclear))
	end
	local cineWasOn, tally = run.cineWasOn, run.tally
	run = nil
	SetCine(cineWasOn)
	ns.TestPrompt(done and ("Addon test DONE: %d pass, %d fail, %d can't tell. Type /reload, then say \"check log\"."):format(
		tally.pass, tally.fail, tally.unclear) or "Addon test stopped.", 30)
end

function ns.AddonTest(words)
	if run then
		Finish(false)
		return
	end
	local typed, quick = words:match("^(%S+)%s*(%S*)")
	local target = typed and Resolve(typed)
	if not target then
		ns.Print("addontest: /cine debug addontest <Addon> [quick] (its folder name: " .. tostring(typed) .. " isn't installed)")
		return
	end
	if not IsLoaded(target) then
		ns.Print("addontest: " .. target .. " isn't loaded. Turn it on (or /cine debug solo " .. target .. ") first.")
		return
	end
	CinematicDB.addonTestLog = {}
	local solo = CinematicDB.soloAddons
	run = {
		target = target, quick = quick == "quick", frames = {}, tally = { pass = 0, fail = 0, unclear = 0 },
		cineWasOn = ns.IsCineModeOn and ns.IsCineModeOn() or false, stage = "start",
	}
	run.others = Others(type(solo) == "table" and solo.keep or { addonName, target })
	-- (Its own parts and what it needs count as alone without solo too.)
	for i = #run.others, 1, -1 do
		local name = run.others[i]
		if Belongs(name, target) or name == addonName then table.remove(run.others, i) end
	end
	local function Version(name)
		local ok, value = pcall(GetMeta, name, "Version")
		return ok and tostring(value) or "?"
	end
	local parts = {}
	for _, each in ipairs(AddOns()) do
		if each.loaded and Belongs(each.name, target) then parts[#parts + 1] = each.name .. " " .. Version(each.name) end
	end
	Log(("start %s: Cinematic %s, game %s, %s; support %s; solo %s; also loaded: %s; CineMode was %s"):format(
		date("%Y-%m-%d %H:%M"), Version(addonName), tostring((GetBuildInfo())), table.concat(parts, ", "),
		ns.AddonSupportOn and tostring(ns.AddonSupportOn(target)) or "?",
		type(solo) == "table" and table.concat(solo.keep or {}, "+") or "off",
		#run.others > 0 and table.concat(run.others, ", ") or "none", run.cineWasOn and "on" or "off"))
	-- (Its parts its rows are for that aren't loaded: their rows can't be
	-- tested, so the run fails rather than passing on the rest.)
	-- (Only parts this client lists: one made for another client isn't in
	-- its list at all, as EllesmereUIMythicTimer on WoW Forever.)
	run.unloaded = {}
	local unloadedSeen, listed = {}, {}
	for _, each in ipairs(AddOns()) do listed[each.name] = true end
	for _, known in ipairs(ns.ADDON_FRAMES or {}) do
		if Belongs(known.addon, target) and listed[known.addon] and not IsLoaded(known.addon)
			and not unloadedSeen[known.addon] then
			unloadedSeen[known.addon] = true
			run.unloaded[#run.unloaded + 1] = known.addon
		end
	end
	table.sort(run.unloaded)
	for _, known in ipairs(ns.ADDON_FRAMES or {}) do
		if Belongs(known.addon, target) then
			Log(("row addon:%s (%s): %s, loaded %s"):format(known.key, tostring(known.label),
				ns.IsAddonFramesOn(known.key) and "on" or "OFF", tostring(known.loaded)))
		end
	end
	SetCine(false)
	-- (Its frames as they come and go, every 2 seconds.)
	run.ticker = C_Timer.NewTicker(2, Inventory)
	Inventory()
	Shot("start")
	Step(1)
end
