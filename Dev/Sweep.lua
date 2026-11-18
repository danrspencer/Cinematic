-- /cine debug sweep: one run through every settings page and setting,
-- checking each works, then putting everything back. Dev copy only.
--   /cine debug sweep [pages] [shots] [page words]
--       full: every page opened (a Lua error or a page that won't show is
--       logged), and on each, every folder tab clicked through (tabs in tabs
--       too, as /cine debug pageshots does), each look measured as
--       PageShots.lua measures it: words cut off, text over text, text under
--       a bar (a preview over the rows), parts past the page's right edge.
--       With "shots", a screenshot of each look (its top: pageshots scrolls).
--       With "pages", only that: no settings changed. Then every setting on them (checkbox, radio pick, slider,
--       number box, dropdown) changed as a click would, one step a frame:
--       a tick flipped, a slider at its min, max and middle, a box a step up
--       and down, up to 6 of a dropdown's choices, each other radio pick.
--       After each step: Lua errors and blocked actions from it, a popup it
--       opened (logged and hidden, never accepted), and whether the control
--       shows what was set. Then the setting is put back the same way, and
--       checked it came back, and that no other setting changed with it.
--   /cine debug sweep visual [N] [seed S] [page words]
--       N settings picked at random (20 if no N; the seed is logged, so
--       "seed S" runs the same ones again): each changed far from what it
--       is, a screenshot before and after (the settings window and the box
--       hidden for them), then put back.
-- Page words: only pages whose name has them (nameplate, style...).
-- At the end the whole profile is put back as it was (and applied as a
-- profile switch does), and the game settings (CVars), the Edit Mode
-- layout and CineMode are compared with the start: anything changed is
-- logged and the CVars are put back. A /reload in the middle: put back
-- at the next login. Stops itself in a fight. Typed again: stops.
-- Into CinematicDB.sweepLog: FAIL and WARN lines, then a summary.
local ADDON, ns = ...

local DROPDOWN_CHOICES = 6 -- most choices of one dropdown tried in a full run
local VISUAL_DEFAULT = 20
local BOX_STEPS = 5 -- wheel steps a number box moves in a visual run
-- Saved settings that change by themselves or are the run's own: not
-- counted as a setting's side effect. (profiles: the active one is saved
-- as settings change; put back with the rest at the end.)
local QUIET = { log = true, sweepLog = true, sweepPending = true, pageTimes = true, pageTimesOn = true,
	sectionsOpen = true, selfTest = true, profiles = true, hubLastTab = true, hubKept = true,
	-- (Counters and debug lists that grow as you play: 2026-11-17's first run.)
	slashUsage = true, chatCamDebug = true, smartFindLooks = true,
	-- (The game settings Cinematic holds now and what they were: its own
	-- record as it holds and lets go (a fight lets go of some), never a
	-- setting. Put back, it said one still held that wasn't. 2026-11-17.)
	savedCVars = true }
-- Settings that change others on purpose: setting -> a pattern of the
-- others' names it may change (a theme writes its values, a unit
-- converts its width, a dragged spot becomes your own spot).
local SETS_OTHERS = { lowHealthTheme = "^lowHealth", prdHealthWidthUnit = "^prdHealthWidthPx$",
	prdPowerWidthUnit = "^prdPowerWidthPx$", emoteVisionX = "^emoteVisionSpot$", emoteVisionY = "^emoteVisionSpot$" }
-- CVars Cinematic itself drives as you play, whatever page is open (the
-- friendly plates where a row shows them or your target is one, the Shoulder
-- Cam's offset): not counted, not put back, and their held copies
-- (savedCVars) left as they are, the feature still holding them. 2026-11-17.
local LIVE_CVARS = { nameplateshowfriendlyplayers = true, test_cameraovershoulder = true }
-- CVars the game changes as you play: not counted, not put back.
local function QuietCVar(name)
	local lower = name:lower()
	return LIVE_CVARS[lower] or lower:find("^last") or lower:find("saved") or lower:find("camera") and lower:find("distance")
end

local run

local function Say(text)
	local log = CinematicDB and CinematicDB.sweepLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end

local function Copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for k, v in pairs(value) do result[k] = Copy(v) end
	return result
end
local function Same(a, b)
	if a == b then return true end
	-- (A slider's value read back through its step: 0.6 and 0.6000000001.)
	if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-6 end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do
		if not Same(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end
local function Show(value)
	if type(value) == "table" then return "{table}" end
	if type(value) == "number" then return ("%.4g"):format(value) end
	if type(value) == "string" then return ("%q"):format(#value > 30 and value:sub(1, 30) .. "..." or value) end
	return tostring(value)
end
-- Same in meaning: inside a table setting (a Show in list), an entry not
-- written (its default) and one written true or false count as the same,
-- as ticking one on and off again writes it out. (The control's own reading
-- back is checked apart: Verify.)
local function Alike(a, b, depth)
	if a == b then return true end
	if (depth or 0) > 0 and ((a == nil and type(b) == "boolean") or (b == nil and type(a) == "boolean")) then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do
		if not Alike(v, b[k], (depth or 0) + 1) then return false end
	end
	for k, v in pairs(b) do
		if a[k] == nil and not Alike(nil, v, (depth or 0) + 1) then return false end
	end
	return true
end
-- Where two values first differ: "key.sub: was -> now" (for a table setting).
local function Diff(was, now, path)
	if type(was) == "table" and type(now) == "table" then
		for k, v in pairs(was) do
			if not Alike(v, now[k], 1) then return Diff(v, now[k], path .. "." .. tostring(k)) end
		end
		for k, v in pairs(now) do
			if was[k] == nil and not Alike(nil, v, 1) then return Diff(nil, v, path .. "." .. tostring(k)) end
		end
	end
	return ("%s: %s -> %s"):format(path, Show(was), Show(now))
end
local function Plain(text)
	if type(text) ~= "string" then return "" end
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " "))
end
local function FirstLine(text)
	return (tostring(text):match("^[^\n]*") or "")
end

-- (Seeded, so a visual run can be repeated: Park-Miller, exact in doubles.)
local function Random(seed)
	local state = seed % 2147483646 + 1
	return function(n)
		state = state * 16807 % 2147483647
		return math.floor(state / 2147483647 * n) + 1
	end
end

-- The settings now, without the quiet ones.
local function Snapshot()
	local db, copy = ns.GetDB(), {}
	for k, v in pairs(db) do
		if not QUIET[k] then copy[k] = Copy(v) end
	end
	return copy
end
local function CVars()
	local list = {}
	local all = C_Console and C_Console.GetAllCommands and C_Console.GetAllCommands()
		or ConsoleGetAllCommands and ConsoleGetAllCommands()
	if type(all) ~= "table" then return nil end
	local cvarType = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar or 0
	for _, each in ipairs(all) do
		local name = each.command
		if each.commandType == cvarType and type(name) == "string" and not QuietCVar(name) then
			local ok, value = pcall(GetCVar, name)
			if ok and value ~= nil then list[name] = value end
		end
	end
	return list
end

local function Layout()
	local ok, name = pcall(function() return ns.ActiveLayoutName and ns.ActiveLayoutName() end)
	return ok and name or nil
end

-- Each kind of control: its value now (read after its Refresh), the values
-- a run tries, setting one as a click would, and whether it shows it.
local function Fire(frame, script, ...)
	local fn = frame:GetScript(script)
	if fn then fn(frame, ...) end
end
local function Choices(control)
	local list = control.frame.sweepChoices
	if type(list) == "function" then list = list() end
	local values = {}
	for _, choice in ipairs(type(list) == "table" and list or {}) do values[#values + 1] = choice.value end
	return values
end
local KINDS = {}
KINDS.check = {
	Read = function(c) return c.frame:GetChecked() and true or false end,
	Values = function(c, visual) return visual and { not c.orig } or { not c.orig } end,
	Set = function(c, value)
		c.frame:SetChecked(value)
		Fire(c.frame, "OnClick", "LeftButton")
	end,
	Shows = function(c, value) return (c.frame:GetChecked() and true or false) == value end,
}
KINDS.radio = {
	Read = function(c)
		for i, frame in ipairs(c.frames) do
			if frame:GetChecked() then return i end
		end
		return 0
	end,
	Values = function(c, visual, rnd)
		local others = {}
		for i = 1, #c.frames do
			if i ~= c.orig then others[#others + 1] = i end
		end
		if visual and #others > 0 then return { others[rnd(#others)] } end
		while #others > DROPDOWN_CHOICES do table.remove(others, rnd(#others)) end
		return others
	end,
	Set = function(c, index)
		local frame = c.frames[index]
		if frame then Fire(frame, "OnClick", "LeftButton") end
	end,
	Shows = function(c, index) return c.frames[index] and c.frames[index]:GetChecked() and true or false end,
	Refresh = function(c)
		for _, frame in ipairs(c.frames) do frame:Refresh() end
	end,
}
KINDS.slider = {
	Read = function(c) return c.frame:GetValue() end,
	Values = function(c, visual)
		local low, high = c.frame:GetMinMaxValues()
		if visual then return { math.abs(c.orig - low) > math.abs(c.orig - high) and low or high } end
		local step = tonumber(c.frame:GetValueStep()) or 0
		local mid = low + (high - low) / 2
		if step > 0 then mid = low + math.floor((mid - low) / step + 0.5) * step end
		return { low, high, mid }
	end,
	Set = function(c, value) c.frame:SetValue(value) end,
	Shows = function(c, value)
		local step = tonumber(c.frame:GetValueStep()) or 0
		return math.abs(c.frame:GetValue() - value) <= math.max(step, 1e-6) + 1e-6
	end,
}
-- (A number box: its value is the wheel steps it moved that took, as the
-- wheel can stop at its ends; put back by the same steps the other way.)
KINDS.box = {
	Read = function() return 0 end,
	Values = function(_, visual, rnd)
		if visual then return { rnd(2) == 1 and BOX_STEPS or -BOX_STEPS } end
		return { 1, -1, -1, 1 }
	end,
	Set = function(c, steps)
		local delta = steps > 0 and 1 or -1
		for _ = 1, math.abs(steps) do
			local before = c.frame:GetText()
			Fire(c.frame, "OnMouseWheel", delta)
			if c.frame:GetText() ~= before then c.moved = (c.moved or 0) + delta end
		end
	end,
	PutBack = function(c)
		local moved = c.moved or 0
		c.moved = 0
		local delta = moved > 0 and -1 or 1
		for _ = 1, math.abs(moved) do Fire(c.frame, "OnMouseWheel", delta) end
	end,
}
KINDS.dropdown = {
	Read = function(c) return Copy(c.frame.sweepGet()) end,
	Values = function(c, visual, rnd)
		local all, others = Choices(c), {}
		for _, value in ipairs(all) do
			if not Same(value, c.orig) then others[#others + 1] = value end
		end
		if visual then return #others > 0 and { others[rnd(#others)] } or {} end
		if #others <= DROPDOWN_CHOICES then return others end
		local picked, used = { others[1], others[#others] }, { [1] = true, [#others] = true }
		while #picked < DROPDOWN_CHOICES do
			local i = rnd(#others)
			if not used[i] then
				used[i] = true
				picked[#picked + 1] = others[i]
			end
		end
		return picked
	end,
	Set = function(c, value) c.frame.sweepPick(value) end,
	Shows = function(c, value) return Same(c.frame.sweepGet(), value) end,
	Refresh = function() end, -- (its Refresh rebuilds its menu: nothing to read)
}

-- (A Show in row's tick menu, UI/GridRows.lua: entries { name, isOn(),
-- toggle(), usable() }; a value is one entry flipped, as ticking it does.)
KINDS.ticks = {
	Read = function(c)
		local on = {}
		for i, entry in ipairs(c.frame.sweepTicks) do on[i] = entry[2]() and true or false end
		return on
	end,
	Values = function(c, _, rnd)
		local usable = {}
		for i, entry in ipairs(c.frame.sweepTicks) do
			if not entry[4] or entry[4]() then usable[#usable + 1] = i end
		end
		-- (One a run, at random: the Show in tables hold ~1500 of these menus.)
		return #usable > 0 and { usable[rnd(#usable)] } or {}
	end,
	Set = function(c, index)
		c.frame.sweepTicks[index][3]()
		c.frame.sweepChanged()
	end,
	Shows = function(c, index)
		local now = c.frame.sweepTicks[index][2]() and true or false
		c.flipped = c.flipped or {}
		c.flipped[index] = not c.flipped[index]
		return now == (c.orig[index] ~= c.flipped[index])
	end,
	PutBack = function(c)
		for i, entry in ipairs(c.frame.sweepTicks) do
			if (entry[2]() and true or false) ~= c.orig[i] then entry[3]() end
		end
		c.frame.sweepChanged()
	end,
}

local function KindOf(frame)
	if type(frame.Refresh) ~= "function" or not frame.GetObjectType then return nil end
	if frame.sweepPick then return "dropdown" end
	if frame.sweepTicks and frame.sweepChanged then return "ticks" end
	local objectType = frame:GetObjectType()
	if objectType == "CheckButton" then return frame:GetScript("OnClick") and "check" or nil end
	if objectType == "Slider" then return "slider" end
	if objectType == "EditBox" and frame:GetScript("OnMouseWheel") then return "box" end
end
local function LabelOf(frame)
	local label = frame.searchLabel or frame.inlineName
		or (frame.rowName and frame.rowName.GetText and frame.rowName:GetText())
	if frame.hiddenSwitch then label = "Enable Page" end
	if not label and frame.GetObjectType and frame:GetObjectType() == "CheckButton" and frame:GetParent()
		and frame:GetParent().RowId then
		label = "Always"
	end
	if frame.sweepTicks and not label then
		local first = frame.sweepTicks[1]
		label = "ticks: " .. tostring(first and first[1] or "?") .. ", ..."
	end
	return Plain(label)
end

-- Every setting control on the pages (those whose name has filter), radio
-- picks of one setting on one line made one entry.
local function Collect(filter)
	ns.MakeLazyPages("the sweep")
	if ns.MapTabContainers then ns.MapTabContainers() end -- (tabs' settings under them, the pages just made too)
	if ns.RefreshOptions then ns.RefreshOptions() end
	local pages, list, seen, radios = {}, {}, {}, {}
	for _, page in ipairs(ns.SettingsPages()) do
		local name = Plain(page.name or "Cinematic")
		if not filter or name:lower():find(filter, 1, true) then
			pages[#pages + 1] = page
			local function Walk(frame, depth)
				if depth > 40 or seen[frame] then return end
				seen[frame] = true
				local kind = KindOf(frame)
				local id = kind and ns.SettingIdOf(frame)
				if id then
					local entry = { frame = frame, kind = kind, id = id, page = name, label = LabelOf(frame) }
					local parent = frame:GetParent()
					if kind == "check" and parent and frame.sweepValue ~= nil then
						radios[parent] = radios[parent] or {}
						local group = radios[parent][id]
						if group then
							group[#group + 1] = entry
						else
							radios[parent][id] = { entry }
							list[#list + 1] = entry
						end
					else
						list[#list + 1] = entry
					end
				end
				for _, child in ipairs({ frame:GetChildren() }) do Walk(child, depth + 1) end
			end
			Walk(page.canvas, 0)
		end
	end
	-- (Two or more checkboxes of one setting on one line: radio picks.)
	for _, byId in pairs(radios) do
		for _, group in pairs(byId) do
			if #group > 1 then
				local first = group[1]
				first.kind = "radio"
				first.frames = {}
				local labels = {}
				for i, entry in ipairs(group) do
					first.frames[i] = entry.frame
					labels[#labels + 1] = entry.label ~= "" and entry.label or tostring(i)
				end
				first.label = table.concat(labels, "/")
			end
		end
	end
	return pages, list
end

-- What a run noted for the step it's on: errors, blocked actions, popups.
local function Note(kind, text)
	if not run then return end
	local control = run.current
	local line = ("%s %s | %s | %s: %s"):format(kind, control and control.id or "-", control and control.page or "-",
		control and control.label or "-", text)
	if control then
		if kind == "FAIL" then control.failed = true else control.warned = true end
		-- (Opening a page: counted on its page's line straight away.)
		local page = control.id == "page" and run.pages[control.page]
		if page and kind == "FAIL" then page.fails = page.fails + 1 elseif page then page.warns = page.warns + 1 end
	end
	if kind == "FAIL" then run.fails = run.fails + 1 else run.warns = run.warns + 1 end
	Say(line)
end

local events = CreateFrame("Frame")
local reportError -- (Diagnostics.lua's, wrapped while a run is on)
local function Watch(on)
	if on and not reportError then
		events:RegisterEvent("ADDON_ACTION_BLOCKED")
		events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
		reportError = ns.ReportError
		ns.ReportError = function(message, stack, caught)
			if run then Note("FAIL", ("Lua error%s: %s"):format(run.step and (" after " .. run.step) or "",
				FirstLine(message))) end
			return reportError(message, stack, caught)
		end
	elseif not on and reportError then
		events:UnregisterEvent("ADDON_ACTION_BLOCKED")
		events:UnregisterEvent("ADDON_ACTION_FORBIDDEN")
		ns.ReportError = reportError
		reportError = nil
	end
end
events:SetScript("OnEvent", function(_, event, addon, action)
	if event == "PLAYER_LOGIN" then
		local pending = CinematicDB and CinematicDB.sweepPending
		if type(pending) == "table" then
			local db = ns.GetDB()
			for k in pairs(db) do
				if not QUIET[k] and pending[k] == nil then db[k] = nil end
			end
			for k, v in pairs(pending) do db[k] = v end
			CinematicDB.sweepPending = nil
			if ns.SettingsChanged then ns.Guard(ns.SettingsChanged) end
			ns.Print("the settings sweep was cut short: your settings are back")
		end
		return
	end
	if run and (addon == ADDON or addon == "Cinematic" or addon == "CinematicDev") then
		Note("FAIL", ("%s: %s"):format(event, tostring(action)))
	end
end)
events:RegisterEvent("PLAYER_LOGIN")

local function HidePopups()
	for i = 1, 4 do
		local popup = _G["StaticPopup" .. i]
		if popup and popup:IsShown() then
			local text = popup.text or popup.Text
			Note("WARN", "opened a popup (hidden, not accepted): " .. Plain(text and text.GetText and text:GetText() or "?"))
			popup:Hide()
		end
	end
end

local function Settings() return _G.SettingsPanel or _G.InterfaceOptionsFrame end
local function Shot(what)
	ns.PadTestBoxHide()
	local ok = pcall(Screenshot)
	return ("screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)")
end

-- The steps, run one a frame (or after a wait: visual runs). Each is
-- { name, fn, wait }.
local function Add(name, fn, wait)
	run.queue[#run.queue + 1] = { name = name, fn = fn, wait = wait }
end

-- A control's value now, its own Refresh first (the settings as saved).
local function Read(c)
	local kind = KINDS[c.kind]
	if kind.Refresh then kind.Refresh(c) else c.frame:Refresh() end
	return kind.Read(c)
end

-- The setting's saved value, when its id is a plain key.
local function Saved(c)
	local db = ns.GetDB()
	if c.id:find("^row:") then return nil, false end
	return Copy(db[c.id]), true
end

-- The settings that changed against the start, other than the control's
-- own: put back, and noted.
local function OthersChanged(c)
	local db = ns.GetDB()
	local allowed = SETS_OTHERS[c.id]
	for k, v in pairs(run.before) do
		if k ~= c.id and not Same(db[k], v) then
			if not Alike(db[k], v) and not (allowed and k:find(allowed)) then
				Note("WARN", ("changed and not back: %s (put back)"):format(Diff(v, db[k], k)))
			end
			db[k] = Copy(v)
		end
	end
	for k, v in pairs(db) do
		if k ~= c.id and not QUIET[k] and run.before[k] == nil and v ~= nil then
			-- (Not counted: a store made the first time it's needed (a table),
			-- an off written where nothing was, or its default written out.)
			if type(v) == "table" then
				Say(("  note: %s made by %s (a table, taken off)"):format(k, c.id))
			elseif v ~= false and not Same(v, ns.DEFAULTS[k]) then
				Note("WARN", ("%s added and not taken off: %s (taken off)"):format(k, Show(v)))
			end
			db[k] = nil
		end
	end
end

local function Check(c, value)
	local kind = KINDS[c.kind]
	HidePopups()
	if kind.Shows then
		Read(c)
		if not kind.Shows(c, value) then
			Note("WARN", ("set to %s, the control shows %s"):format(Show(value), Show(kind.Read(c))))
		end
	end
end

local function Act(c, value, label)
	run.current = c
	run.step = label
	local kind = KINDS[c.kind]
	local ok, err = xpcall(function() kind.Set(c, value) end, function(e)
		local got, stack = pcall(debugstack, 2, 2, 0)
		return FirstLine(e) .. (got and type(stack) == "string" and (" @ " .. stack:gsub("\n", " | ")) or "")
	end)
	if not ok then Note("FAIL", ("Lua error setting %s: %s"):format(Show(value), tostring(err))) end
end

local function PutBack(c)
	run.current = c
	run.step = "put back"
	local kind = KINDS[c.kind]
	local ok, err = pcall(function()
		if kind.PutBack then
			kind.PutBack(c)
		elseif c.kind == "radio" then
			if c.orig > 0 then kind.Set(c, c.orig) end
		else
			kind.Set(c, c.orig)
		end
	end)
	if not ok then Note("FAIL", "Lua error putting it back: " .. FirstLine(err)) end
end

local function Verify(c)
	run.current = c
	HidePopups()
	local now, plain = Saved(c)
	-- (Not counted: nothing saved before and its control reads as it did
	-- (its default written out), or a slider's "follows another" (false)
	-- that a slider can't put back.)
	local quiet = plain and ((c.saved == nil and Same(Read(c), c.orig))
		or (c.kind == "slider" and type(c.saved) == "boolean"))
	if plain and not Same(now, c.saved) then
		if not Alike(now, c.saved) and not quiet then
			Note("WARN", ("didn't come back: %s (put back)"):format(Diff(c.saved, now, c.id)))
		end
		ns.GetDB()[c.id] = Copy(c.saved)
	elseif c.kind ~= "box" then
		-- (Its own reading, as its page shows it: a Show in row's ticks.)
		local back = Read(c)
		if not Same(back, c.orig) then
			Note("WARN", ("shows %s after putting back, was %s"):format(Show(back), Show(c.orig)))
		end
	end
	OthersChanged(c)
	run.done = run.done + 1
	local page = run.pages[c.page]
	if page then
		page.tested = page.tested + 1
		if c.failed then page.fails = page.fails + 1 elseif c.warned then page.warns = page.warns + 1 end
	end
	run.current, run.step = nil, nil
end

-- Full run: each control's values one a frame, then back, then checked.
-- (A step giving true runs again next frame.)
local function QueueControl(c)
	Add(c.id, function()
		run.current = c
		if not c.phase then
			c.orig = Read(c)
			c.saved = Saved(c)
			c.values = KINDS[c.kind].Values(c, false, run.rnd)
			c.phase = 1
		end
		local i = c.phase
		if i > 1 then Check(c, c.values[i - 1]) end
		if c.values[i] ~= nil then
			Act(c, c.values[i], ("setting %s"):format(Show(c.values[i])))
			c.phase = i + 1
			return true
		end
		PutBack(c)
		Verify(c)
	end)
end

-- Visual run: a screenshot before and after one change, then back.
local function QueueVisual(c, index, total)
	local panel, alpha
	Add(c.id, function()
		run.current = c
		c.orig = Read(c)
		c.saved = Saved(c)
		c.values = KINDS[c.kind].Values(c, true, run.rnd)
		ns.PadTestBox(("%d/%d: %s > %s"):format(index, total, c.page, c.label ~= "" and c.label or c.id),
			"Just watch. Screenshots before and after.", 1, 0.82, 0)
	end, 2)
	Add(c.id, function()
		panel = Settings()
		alpha = panel and panel:GetAlpha()
		if panel then
			run.panel, run.alpha = panel, alpha
			panel:SetAlpha(0)
		end
		ns.PadTestBoxHide()
	end, 0.5)
	Add(c.id, function()
		local value = c.values[1]
		Say(("visual %d/%d %s | %s | %s: %s, CineMode %s"):format(index, total, c.id, c.page, c.label,
			Shot("before"), tostring(ns.lastCinematic)))
		if value == nil then
			Say("  nothing else to set it to")
			return
		end
		Act(c, value, ("setting %s"):format(Show(value)))
		Say(("  %s -> %s"):format(Show(c.orig), Show(value)))
	end, 2)
	Add(c.id, function()
		Say("  " .. Shot("after"))
		if c.values[1] ~= nil then Check(c, c.values[1]) end
	end, 0.5)
	Add(c.id, function()
		if panel and alpha then panel:SetAlpha(alpha) end
		run.panel = nil
		if c.values[1] ~= nil then PutBack(c) end
	end, 1)
	Add(c.id, function() Verify(c) end)
end

-- Every page opened, and its tabs clicked through: each look measured.
local OPEN_WAIT, TAB_WAIT, MAX_LOOKS = 0.5, 0.3, 30 -- (seconds; looks a page at most)
local LAYOUT_KINDS = { "words cut off", "text over text", "past the page's right edge", "text under a bar",
	"text under the style preview" }

local function TabName(tab)
	local text = tab.label and tab.label.GetText and tab.label:GetText() or (tab.GetText and tab:GetText())
	text = Plain(text)
	return text ~= "" and text or ("tab " .. tostring(tab.shotIndex))
end

-- One look at the page as it shows now (path: the tabs picked).
local function LookAt(page, entry, path)
	entry.looks = entry.looks + 1
	entry.label = path ~= "" and path or "(page)"
	run.looks = run.looks + 1
	-- (Measured at the top, and scrolled to the middle and the bottom: a
	-- sticky preview covers the rows only as they scroll under it, 2026-11-17.)
	local scroll = page.canvas.scroll
	local range = scroll and scroll.GetVerticalScrollRange and (tonumber(scroll:GetVerticalScrollRange()) or 0) or 0
	local spots = range > 40 and { 0, range / 2, range } or { 0 }
	local seen = {}
	for n, at in ipairs(spots) do
		if n > 1 then
			scroll:SetVerticalScroll(at)
			coroutine.yield(TAB_WAIT)
			-- (A sticky preview still easing into its corner (slow frames in
			-- the settings): measured once it's there, 2 seconds at most.)
			for _ = 1, 20 do
				if not (ns.StickyPreviewMoving and ns.StickyPreviewMoving()) then break end
				coroutine.yield(0.1)
			end
		end
		local where = n == 1 and "" or (n == 2 and " (scrolled halfway)" or " (scrolled to the bottom)")
		local found = ns.PageLayoutFindings and { ns.PageLayoutFindings(page.canvas) } or {}
		for i, list in ipairs(found) do
			-- (Only what's new scrolled: the same words again aren't.)
			local fresh = {}
			for _, words in ipairs(list) do
				if not seen[i .. words] then
					seen[i .. words] = true
					fresh[#fresh + 1] = words
				end
			end
			if #fresh > 0 then
				Note("WARN", ("%s%s: %s"):format(LAYOUT_KINDS[i] or "?", where, table.concat(fresh, "; ")))
			end
		end
		if run.shots then
			run.boxAt = GetTime() + 2 -- (the box kept off till the shot's taken)
			Say(("  %s | %s%s: %s"):format(entry.page, entry.label, where, Shot("look")))
			-- (The game names shots by the second: two in one, the second's lost.)
			coroutine.yield(1.1)
		end
	end
	if #spots > 1 then
		scroll:SetVerticalScroll(0)
		coroutine.yield(TAB_WAIT)
	end
end

-- (Run in a coroutine: yields the seconds to wait, a tab's click to settle.)
local function Explore(page, entry, visited, path)
	local canvas = page.canvas
	local set
	for _, each in ipairs(ns.PageTabSets and ns.PageTabSets(canvas.content or canvas) or {}) do
		if not visited[each] then set = each break end
	end
	if not set or entry.looks >= MAX_LOOKS then
		LookAt(page, entry, path)
		return
	end
	local inner = {}
	for k in pairs(visited) do inner[k] = true end
	inner[set] = true
	-- (Every tab must turn its feature on and off by right-click: the user's
	-- rule, 2026-11-17. Noted once a tab.)
	run.tabsSeen = run.tabsSeen or {}
	for _, tab in ipairs(set) do
		if tab:IsShown() and not run.tabsSeen[tab] then
			run.tabsSeen[tab] = true
			local why = not tab.canFlip and "a right-click does nothing"
				or tab.switchPage and ns.HasPageSwitch and not ns.HasPageSwitch(tab.switchPage)
				and ("its page, %s, has no switch"):format(tab.switchPage)
			if why then
				local label = entry.label
				entry.label = (path ~= "" and (path .. " > ") or "") .. TabName(tab)
				Note("WARN", "no right-click on/off: " .. why)
				entry.label = label
			end
			-- (A tab is a container: off, every setting on it reads off. Set off
			-- a moment, each checked, put back.)
			if not why and tab.flipKey and tab.containerHost then
				local db = ns.GetDB()
				local was = db[tab.flipKey]
				db[tab.flipKey] = false
				local still = {}
				local function Walk(frame, depth)
					if depth > 30 then return end
					local key = frame.settingKey
					if type(key) == "string" and key ~= tab.flipKey and db[key] and ns.Setting(key) and not still[key] then
						still[key] = true
						still[#still + 1] = key
					end
					for _, child in ipairs({ frame:GetChildren() }) do Walk(child, depth + 1) end
				end
				Walk(tab.containerHost, 0)
				db[tab.flipKey] = was
				if #still > 0 then
					local label = entry.label
					entry.label = (path ~= "" and (path .. " > ") or "") .. TabName(tab)
					Note("WARN", ("tab off, but %d settings on it still read on: %s"):format(#still,
						table.concat(still, ", ", 1, math.min(#still, 8))))
					entry.label = label
				end
				run.containersChecked = (run.containersChecked or 0) + 1
			end
		end
	end
	local was, left = set.picked or 1, false
	for _, tab in ipairs(set) do
		if entry.looks >= MAX_LOOKS then break end
		if tab:IsShown() then
			local here = path ~= "" and (path .. " > " .. TabName(tab)) or TabName(tab)
			entry.label = here
			local ok, err = pcall(tab.Click, tab)
			if not ok then Note("FAIL", "Lua error clicking the tab: " .. FirstLine(err)) end
			coroutine.yield(TAB_WAIT)
			HidePopups()
			if not canvas:IsVisible() then
				-- (A tab that opens another page: noted, its page opened again.)
				Say(("  note: %s | %s opens another page"):format(entry.page, here))
				left = true
				pcall(ns.OpenOptions, page.key)
				coroutine.yield(OPEN_WAIT)
				break
			end
			Explore(page, entry, inner, here)
		end
	end
	if set[was] and not left and canvas:IsVisible() then
		pcall(set[was].Click, set[was])
		coroutine.yield(TAB_WAIT)
	end
end

-- Every icon's tree, read off the layout (the user's rule, 2026-11-17): an
-- icon's tabs in one hub, the first its root (an icon whose first tabs are
-- Show sections, "HUD:...": each of those a root, siblings), every other
-- tab under a root. Each such tab: a switch of its own (not its root's or
-- another icon's), hung under its root (Frames.lua's ns.SHOW_IN_CHILDREN),
-- and with its roots set off it reads off and greyed (put back straight
-- after). No exceptions.
local function TreeCheck()
	if not (ns.ShowInTabNames and ns.PageSwitchKey and ns.PageHub) then return end
	local db = ns.GetDB()
	local checked, owner = 0, {}
	for _, name in ipairs(ns.ShowInTabNames()) do
		local list = ns.ShowInTabs(name)
		local hubs, order = {}, {}
		for _, tab in ipairs(list) do
			local hub = ns.PageHub(tab[2]) or "?"
			if not hubs[hub] then
				hubs[hub] = {}
				order[#order + 1] = hub
			end
			table.insert(hubs[hub], tab)
		end
		for _, hub in ipairs(order) do
			local tabs, roots = hubs[hub], {}
			local function KeyOf(page)
				local section = page:match("^HUD:(.+)$")
				return section and ns.SHOW_IN_SWITCH and ns.SHOW_IN_SWITCH[section] or ns.PageSwitchKey(page)
			end
			local i = 1
			repeat
				roots[#roots + 1] = KeyOf(tabs[i][2])
				i = i + 1
			until not (tabs[i] and tabs[i][2]:find("^HUD:") and tabs[1][2]:find("^HUD:"))
			local isRoot = {}
			for _, key in ipairs(roots) do isRoot[key] = true end
			for j = i, #tabs do
				local page = tabs[j][2]
				run.current = { id = "tree", page = ("%s (%s hub)"):format(Plain(list[1][1] and name or name), hub),
					label = Plain(tabs[j][1]) }
				local key = KeyOf(page)
				if not key then
					Note("WARN", ("tree: no switch of its own (page %s)"):format(page))
				elseif isRoot[key] then
					Note("WARN", ("tree: shares its icon's switch %s"):format(key))
				elseif owner[key] and owner[key] ~= name then
					Note("WARN", ("tree: shares switch %s with the %s icon"):format(key, owner[key]))
				else
					owner[key] = name
					checked = checked + 1
					local master, under = key, false
					for _ = 1, 10 do
						master = ns.PageSwitchOf(master)
						if not master then break end
						if isRoot[master] then under = true break end
					end
					if not under then
						Note("WARN", ("tree: its switch %s isn't under its icon's (%s)"):format(key, table.concat(roots, "/")))
					else
						local was = {}
						for _, root in ipairs(roots) do was[root] = db[root]; db[root] = false end
						local stillOn, greyed = ns.PageOn(key), ns.PageSwitchOff(page)
						for _, root in ipairs(roots) do db[root] = was[root] end
						if stillOn or not greyed then
							Note("WARN", ("tree: its icon off, but it's %s"):format(stillOn and "still on" or "not greyed"))
						end
					end
				end
			end
		end
	end
	run.current = nil
	Say(("  tree: %d icon tabs checked under their icon's switch"):format(checked))
end

local function QueuePage(page)
	local name = Plain(page.name or "Cinematic")
	local entry = { id = "page", page = name, label = "(opening the page)", looks = 0 }
	Add(name, function()
		run.current = entry
		run.step = "opening"
		local ok, err = pcall(ns.OpenOptions, page.key)
		if not ok then Note("FAIL", "Lua error opening: " .. FirstLine(err)) end
	end, OPEN_WAIT)
	local co
	Add(name, function()
		run.current = entry
		if not co then
			-- (Once a run: every hub icon a right-click can't turn on and off.)
			if not run.iconsChecked and ns.HubTilesWithoutSwitch then
				run.iconsChecked = true
				ns.Guard(TreeCheck)
				run.current = { id = "icon", page = "-", label = "-" }
				for _, each in ipairs(ns.HubTilesWithoutSwitch()) do
					Note("WARN", ("icon %s > %s: no right-click on/off (no switch)"):format(each.hub, each.label))
				end
				run.current = entry -- (the tree check left it unset: this page's own tab notes named nothing)
			end
			HidePopups()
			if not page.canvas:IsVisible() then
				Note("WARN", "page didn't show")
				run.opened = run.opened + 1
				return
			end
			co = coroutine.create(function()
				Explore(page, entry, {}, "")
				-- (The page's other parts, each an icon of its own sharing its
				-- canvas (canvas.hubTabs): Nameplate Style's Smart, the HUD's
				-- sections. Its tab row's skipped as pages of their own, so
				-- these were never seen: 2026-11-17, the preview over Smart.)
				for _, part in ipairs(page.canvas.hubTabs or {}) do
					if part.name and part.name ~= page.key and ns.ShowHubPage then
						local ok, err = pcall(ns.ShowHubPage, part.name)
						if not ok then Note("FAIL", ("Lua error opening part %s: %s"):format(part.name, FirstLine(err))) end
						coroutine.yield(OPEN_WAIT)
						HidePopups()
						if page.canvas:IsVisible() then
							Explore(page, entry, {}, Plain(part.label or part.name))
						else
							Say(("  note: %s | part %s didn't show"):format(entry.page, part.name))
						end
					end
				end
			end)
		end
		local ok, wait = coroutine.resume(co)
		if not ok then Note("FAIL", "sweep's own error looking at the page: " .. FirstLine(wait)) end
		if ok and coroutine.status(co) ~= "dead" then return true, wait end
		run.opened = run.opened + 1
		run.current, run.step = nil, nil
	end)
end

local Finish

local function Box()
	if run.visual then return end
	ns.PadTestBox(("Settings sweep: %d of %d settings%s. Don't touch anything, stay out of fights."):format(
		run.done, run.total, run.current and (", " .. run.current.page) or ""),
		("%d fail, %d warn (type /cine debug sweep to stop)"):format(run.fails, run.warns), 1, 0.82, 0)
end

local driver = CreateFrame("Frame")
local function Tick()
	if not run then return end
	if InCombatLockdown() then
		Say("in a fight: stopped")
		Finish(false)
		return
	end
	if ns.IsSuspended and ns.IsSuspended() then
		Note("FAIL", "Cinematic suspended itself (an error kept repeating): stopped")
		Finish(false)
		return
	end
	local now = GetTime()
	if now < run.nextAt then return end
	local step = run.queue[run.index]
	if not step then
		Finish(true)
		return
	end
	local ok, again, wait = pcall(step.fn)
	if not ok then Note("FAIL", ("sweep's own error at %s: %s"):format(step.name, FirstLine(again))) end
	local repeating = ok and again == true
	if not repeating then run.index = run.index + 1 end
	run.nextAt = now + (repeating and (wait or 0) or step.wait or 0)
	if now - (run.boxAt or 0) > 0.5 then
		run.boxAt = now
		Box()
	end
end

-- Everything as it was at the start, and what wasn't noted.
local function PutAllBack()
	if run.panel and run.alpha then run.panel:SetAlpha(run.alpha) end
	local db = ns.GetDB()
	local leaks = {}
	for k, v in pairs(run.before) do
		if not Same(db[k], v) then
			if not Alike(db[k], v) then leaks[#leaks + 1] = Diff(v, db[k], k) end
			db[k] = Copy(v)
		end
	end
	for k in pairs(db) do
		if not QUIET[k] and run.before[k] == nil then
			-- (A list made the first time its page opened: not a leak.)
			if type(db[k]) ~= "table" and db[k] ~= false and not Same(db[k], ns.DEFAULTS[k]) then
				leaks[#leaks + 1] = k
			end
			db[k] = nil
		end
	end
	if #leaks > 0 then
		run.warns = run.warns + 1
		Say("WARN settings not back at the end (put back): " .. table.concat(leaks, "; "))
	end
	CinematicDB.sweepPending = nil
	if ns.SettingsChanged then ns.Guard(ns.SettingsChanged) end
	if run.cvars then
		local after, changed = CVars() or {}, {}
		for name, value in pairs(run.cvars) do
			if after[name] ~= nil and after[name] ~= value then
				changed[#changed + 1] = ("%s %s -> %s"):format(name, value, after[name])
				pcall(SetCVar, name, value)
			end
		end
		table.sort(changed)
		if #changed > 0 then
			run.warns = run.warns + 1
			Say("WARN game settings (CVars) changed and not back (put back): " .. table.concat(changed, "; "))
		end
	else
		Say("game settings (CVars) not compared: no CVar list on this client")
	end
	local layout = Layout()
	if layout ~= run.layout then
		run.warns = run.warns + 1
		Say(("WARN Edit Mode layout was %s, now %s"):format(tostring(run.layout), tostring(layout)))
	end
	if (ns.lastCinematic and true or false) ~= run.cine then
		Say(("CineMode was %s, now %s: switched back"):format(tostring(run.cine), tostring(ns.lastCinematic)))
		if Cinematic_ToggleCineMode then pcall(Cinematic_ToggleCineMode) end
	end
end

function Finish(done)
	if not run then return end
	ns.SetOnUpdate(driver, nil)
	local this = run
	local function Close()
		run = this
		PutAllBack()
		local names = {}
		for name in pairs(this.pages) do names[#names + 1] = name end
		table.sort(names)
		Say("--- summary ---")
		for _, name in ipairs(names) do
			local page = this.pages[name]
			if page.tested > 0 or page.fails > 0 or page.warns > 0 then
				Say(("page %s: %d settings, %d fail, %d warn"):format(name, page.tested, page.fails, page.warns))
			end
		end
		Say(("  tab containers checked: %d"):format(this.containersChecked or 0))
		Say(("%s: %d pages opened (%d looks, tabs clicked through), %d of %d settings tested, %d fail, %d warn, "
			.. "%.0f sec, seed %d"):format(done and "done" or "stopped", this.opened, this.looks, this.done, this.total,
			this.fails, this.warns, GetTime() - this.at, this.seed))
		Watch(false)
		run = nil
		ns.PadTestBox(("Sweep %s: %d fail, %d warn. /reload, then say \"check log\"."):format(
			done and "done" or "stopped", this.fails, this.warns), "", 1, 0.82, 0)
		ns.Print(("settings sweep %s: %d fail, %d warn"):format(done and "done" or "stopped", this.fails, this.warns))
		C_Timer.After(15, function() if not run then ns.PadTestBoxHide() end end)
	end
	run = nil -- (no more steps or notes while it waits)
	if InCombatLockdown() then
		ns.PadTestBox("Sweep stopped for the fight: your settings go back when it ends.", "", 1, 0.3, 0.3)
		local wait = CreateFrame("Frame")
		wait:RegisterEvent("PLAYER_REGEN_ENABLED")
		wait:SetScript("OnEvent", function(self)
			self:UnregisterAllEvents()
			ns.Guard(Close)
		end)
	else
		ns.Guard(Close)
	end
end

function ns.SettingsSweep(args)
	if run then
		Finish(false)
		return
	end
	if InCombatLockdown() then return ns.Print("not in a fight") end
	local words, visual, count, seed, pagesOnly, shots = {}, false, nil, nil, false, false
	local tokens = {}
	for word in (args or ""):lower():gmatch("%S+") do tokens[#tokens + 1] = word end
	local i = 1
	while i <= #tokens do
		local word = tokens[i]
		if word == "visual" then
			visual = true
		elseif word == "pages" then
			pagesOnly = true
		elseif word == "shots" then
			shots = true
		elseif word == "seed" and tonumber(tokens[i + 1]) then
			seed = tonumber(tokens[i + 1])
			i = i + 1
		elseif visual and not count and tonumber(word) then
			count = tonumber(word)
		else
			words[#words + 1] = word
		end
		i = i + 1
	end
	local filter = #words > 0 and table.concat(words, " ") or nil
	seed = math.floor(seed or (time() % 100000))
	CinematicDB.sweepLog = {}
	run = { at = GetTime(), queue = {}, index = 1, nextAt = 0, fails = 0, warns = 0, done = 0, opened = 0,
		pages = {}, visual = visual, seed = seed, rnd = Random(seed), looks = 0, shots = shots }
	Watch(true)
	local pages, controls
	local ok, err = pcall(function() pages, controls = Collect(filter) end)
	if not ok then
		Say("couldn't list the settings: " .. FirstLine(err))
		Watch(false)
		run = nil
		return ns.Print("sweep: couldn't list the settings (check log)")
	end
	if #controls == 0 then
		Watch(false)
		run = nil
		return ns.Print(("sweep: no settings on pages named %q"):format(filter or ""))
	end
	for _, page in ipairs(pages) do
		run.pages[Plain(page.name or "Cinematic")] = { tested = 0, fails = 0, warns = 0 }
	end
	run.before = Snapshot()
	run.cvars = CVars()
	run.layout = Layout()
	run.cine = ns.lastCinematic and true or false
	CinematicDB.sweepPending = Copy(run.before)
	local kinds = {}
	for _, c in ipairs(controls) do kinds[c.kind] = (kinds[c.kind] or 0) + 1 end
	local kindList = {}
	for kind, n in pairs(kinds) do kindList[#kindList + 1] = kind .. " " .. n end
	table.sort(kindList)
	Say(("start %s: %s run, %s (game %s), pages %d, settings %d (%s), filter %s, seed %d, CineMode %s, layout %s")
		:format(date("%Y-%m-%d %H:%M:%S"), visual and "visual" or pagesOnly and "pages (layout only)" or "full", ns.isRetail and "retail" or tostring(ns.CLIENT),
		tostring((select(4, GetBuildInfo()))), #pages, #controls, table.concat(kindList, ", "), tostring(filter), seed,
		tostring(run.cine), tostring(run.layout)))
	if visual then
		count = math.max(1, math.min(count or VISUAL_DEFAULT, #controls))
		local picked, used = {}, {}
		while #picked < count do
			local n = run.rnd(#controls)
			if not used[n] then
				used[n] = true
				picked[#picked + 1] = controls[n]
			end
		end
		run.total = count
		for n, c in ipairs(picked) do QueueVisual(c, n, count) end
		ns.Print(("settings sweep (visual): %d settings, about %d sec, seed %d; type it again to stop"):format(count,
			count * 6, seed))
	else
		run.total = pagesOnly and 0 or #controls
		for _, page in ipairs(pages) do QueuePage(page) end
		if not pagesOnly then
			for _, c in ipairs(controls) do QueueControl(c) end
		end
		local secs = #pages * (OPEN_WAIT + 4 * TAB_WAIT)
			+ (pagesOnly and 0 or #controls * 3 / math.max(tonumber(GetFramerate()) or 60, 20))
		ns.Print(("settings sweep: %d pages%s, about %d sec; don't touch anything; type it again to stop")
			:format(#pages, pagesOnly and " (layout only)" or (", " .. #controls .. " settings"), math.ceil(secs)))
	end
	ns.SetOnUpdate(driver, Tick)
end
