-- Shoulder Cam calibration (the Calibrate tab on the Shoulder Cam page): how
-- far an offset moves YOUR model on screen, measured, for the race, sex and
-- form you are now. A model's size factor (ShoulderCam.lua, MEASURED_SCALES)
-- is built in for every race and sex and the forms measured so far; one that
-- looks wrong, or a form nobody's measured yet, is measured here.
--
-- How: it says a line in /say (the game puts your chat bubble right over
-- you), then steps the shoulder offset (both sides, at 8 and 12 yards, each
-- zoom from its own 0) and reads where the bubble moved each time, against
-- where the offset should have put a Dwarf. The middle of those readings is
-- your factor, called good if they all agree within SPREAD. While it runs
-- the Shoulder Cam keeps its hands off (ns.shoulderTestHold); after, your
-- offset, Keep Character Centered, chat bubbles, the motion sickness option
-- and your zoom are put back.
-- A bubble lasts ~5 s: when it's gone, a button says the line again (only a
-- click or a typed command lets an addon talk; a timer's line is blocked).
--
-- Saved for you at once (db.shoulderCamScales[key], over the built-in one),
-- with its details in db.shoulderCalibrations[key] (spread, readings, date):
-- the tab lists those, each with a Reset, and Share puts them on one line to
-- paste to us, so the built-in table can have them for everyone.
-- (Moved here from the dev copy's ShoulderCamTest.lua, 2026-11-14; its
-- /cine debug shoulder calibrate runs this.)
local ADDON_NAME, ns = ...
local L = ns.L

local SHOULDER, CENTERED = "test_cameraOverShoulder", "CameraKeepCharacterCentered"
local REDUCE = "CameraReduceUnexpectedMovement"
local SETTLE = 0.6     -- seconds a step waits at least (the game eases over in about 0.3)
local STILL = 0.3      -- ...and until the bubble's been still this long (a zoom takes longer)
local SETTLE_MOST = 4  -- ...but never longer than this
local SAMPLE = 0.05    -- seconds between bubble reads
local SPREAD = 0.06    -- the most the readings may differ for a good run
local STEPS = { { 0, 8 }, { 1 }, { 2 }, { 0 }, { -1 }, { -2 }, { 0, 12 }, { 1.5 }, { 2.5 }, { 0 }, { -1.5 }, { -2.5 } }

-- (Translated: said aloud, so in your language. Matched by its start.)
local function Line()
	return L["Calibrating my camera, please ignore this line for a moment: I'm measuring where my character " ..
		"sits on the screen as the camera moves over my shoulder. Thanks for your patience!"]
end

local function Log(text) if ns.Log then ns.Log("shoulder", "calibrate: " .. text) end end
local function Zoom() return GetCameraZoom and GetCameraZoom() or 0 end

-- Form names for the tab and the shared line (GetShapeshiftFormID's).
local FORM_NAMES = { [1] = "Cat Form", [2] = "Tree of Life", [3] = "Travel Form", [4] = "Aquatic Form",
	[5] = "Bear Form", [8] = "Dire Bear Form", [16] = "Ghost Wolf", [27] = "Swift Flight Form",
	[29] = "Flight Form", [31] = "Moonkin Form", [35] = "Moonkin Form" }
local SEX_NAMES = { ["2"] = "Male", ["3"] = "Female" }
-- (Race tokens that don't read as their name; the rest get a space before
-- each capital: NightElf -> Night Elf.)
local RACE_NAMES = { Scourge = "Undead" }
local function RaceName(token)
	return L[RACE_NAMES[token] or (token:gsub("(%l)(%u)", "%1 %2"))]
end

-- A key (Race-sex or Race-sex-formN) said for people: "Night Elf Female, Cat
-- Form", or in two parts (who, then the form or "On foot") for the table.
local function KeyParts(key)
	local race, sex, form = tostring(key):match("^(.-)%-(%d)%-form(%d+)$")
	if not race then race, sex = tostring(key):match("^(.-)%-(%d)$") end
	if not race then return tostring(key), "" end
	local who = ("%s %s"):format(RaceName(race), L[SEX_NAMES[sex] or "?"] or "?")
	if not form then return who, L["On foot"] end
	local name = FORM_NAMES[tonumber(form)]
	return who, name and L[name] or (L["Form %s"]):format(form)
end
function ns.ShoulderKeyName(key)
	local who, what = KeyParts(key)
	return what ~= "" and ("%s, %s"):format(who, what) or who
end

-- The bubble over you: its x and y as shares of the screen (-1 to 1 from the
-- middle), or nil and why.
local function BubbleText(bubble)
	local inside = bubble:GetChildren()
	if not inside or (inside.IsForbidden and inside:IsForbidden()) then return nil end
	if inside.String and inside.String.GetText then return inside.String:GetText() end
	for _, region in ipairs({ inside:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" then return region:GetText() end
	end
end
local function BubbleSpot()
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then return nil, "no bubbles on this client" end
	local okAll, all = pcall(C_ChatBubbles.GetAllChatBubbles, false)
	if not okAll or not all then return nil, "bubbles can't be read here" end
	local line = Line()
	for _, bubble in ipairs(all) do
		if not (bubble.IsForbidden and bubble:IsForbidden()) then
			local okText, says = pcall(BubbleText, bubble)
			local okSame, same = pcall(function()
				return type(says) == "string" and says:sub(1, 40) == line:sub(1, 40)
			end)
			if okText and okSame and same then
				local ok, x, y = pcall(bubble.GetCenter, bubble)
				if ok and type(x) == "number" and type(y) == "number" then
					local scale = bubble:GetEffectiveScale() / WorldFrame:GetEffectiveScale()
					return (x * scale / WorldFrame:GetWidth() - 0.5) * 2, (y * scale / WorldFrame:GetHeight() - 0.5) * 2
				end
				return nil, "the bubble can't be measured here"
			end
		end
	end
	return nil, "no bubble of yours up"
end
ns.ShoulderBubbleSpot = BubbleSpot

local function SendLine()
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	if send then send(Line(), "SAY") end
end

-- Where the offset puts a Dwarf at this zoom, as a share of the screen.
local function WorkedOut(yards)
	return -yards / (math.max(1.5, Zoom()) * ns.ShoulderViewWidth())
end

local run -- { key, steps, at, waited, baseline, held, readings }
local stepper = CreateFrame("Frame")
stepper:Hide()

local function Changed()
	if ns.ShoulderCalibrateChanged then ns.ShoulderCalibrateChanged() end
end

-- What a run changed, put back. (Also saved, db.shoulderCalibrateHeld, so a
-- reload or logout mid-run puts it back at the next login: chat bubbles,
-- Keep Character Centered and the motion sickness option would otherwise
-- stay as the run had them.)
local function PutBackHeld(held)
	if held.offset then SetCVar(SHOULDER, held.offset) end
	if held.centered then SetCVar(CENTERED, held.centered) end
	if held.bubbles then SetCVar("chatBubbles", held.bubbles) end
	if held.reduce then SetCVar(REDUCE, held.reduce) end
end

local function Finish(why)
	stepper:Hide()
	if not run then return end
	local held = run.held
	PutBackHeld(held)
	if ns.db then ns.db.shoulderCalibrateHeld = nil end
	if ns.shoulderCalibrateGoOn then ns.shoulderCalibrateGoOn:Hide() end
	local delta = held.zoom - Zoom()
	if math.abs(delta) > 0.1 and ns.CallCameraFunction then
		ns.CallCameraFunction(delta > 0 and "CameraZoomOut" or "CameraZoomIn", math.abs(delta))
	end
	ns.shoulderTestHold = nil
	local done = run
	run = nil
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	if why then
		Log(why)
		ns.PadTestBox(L["Calibration stopped"], why, 1, 0.3, 0.3)
		C_Timer.After(8, function() if not run then ns.PadTestBoxHide() end end)
		Changed()
		return
	end
	-- The middle reading, called good if they all agree.
	local list = {}
	for _, factor in ipairs(done.readings) do list[#list + 1] = factor end
	table.sort(list)
	if #list < 6 then
		Log(("%s: only %d readings"):format(done.key, #list))
		ns.PadTestBox(L["Calibration: not enough readings"], L["Try again somewhere open and flat."], 1, 0.3, 0.3)
		C_Timer.After(10, function() if not run then ns.PadTestBoxHide() end end)
		Changed()
		return
	end
	local middle = #list % 2 == 1 and list[(#list + 1) / 2] or (list[#list / 2] + list[#list / 2 + 1]) / 2
	local spread = list[#list] - list[1]
	local good = spread <= SPREAD
	local factor = tonumber(("%.2f"):format(middle))
	local db = ns.db
	db.shoulderCalibrations = db.shoulderCalibrations or {}
	db.shoulderCalibrations[done.key] = { factor = factor, spread = tonumber(("%.3f"):format(spread)), readings = #list,
		good = good, client = ns.CLIENT, when = date("%Y-%m-%d %H:%M"), zoom = ("%.1f"):format(done.held.zoom) }
	-- (Used only when good: a doubtful one is kept to look at, not to go by.)
	if good then
		db.shoulderCamScales = db.shoulderCamScales or {}
		db.shoulderCamScales[done.key] = factor
	end
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	local shown = {}
	for i, f in ipairs(list) do shown[i] = ("%.2f"):format(f) end
	Log(("%s = %.2f (%s: readings %s, spread %.3f)"):format(done.key, factor, good and "good" or "redo",
		table.concat(shown, " "), spread))
	ns.PadTestBox(("%s: %.2f"):format(ns.ShoulderKeyName(done.key), factor),
		good and L["Saved, and in use now. Share it from the Calibrate tab."]
			or (L["The readings disagree (%.2f apart): try again somewhere open and flat."]):format(spread),
		good and 0.3 or 1, good and 1 or 0.3, 0.3)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
	Changed()
end

local function BeginStep(step)
	run.waited, run.last, run.moved = 0, nil, 0
	SetCVar(SHOULDER, ("%.2f"):format(step[1]))
	if step[2] then
		local delta = step[2] - Zoom()
		if math.abs(delta) > 0.1 and ns.CallCameraFunction then
			ns.CallCameraFunction(delta > 0 and "CameraZoomOut" or "CameraZoomIn", math.abs(delta))
		end
	end
end

local function Box()
	ns.PadTestBox((L["Calibrating: step %d of %d"]):format(run.at, #run.steps),
		L["Stand still and leave the camera alone."], 0.7, 0.7, 0.7)
end

-- The bubble's gone mid-run: a button to say the line again and go on.
local function Wait(why)
	run.paused = true
	stepper:Hide()
	local button = ns.shoulderCalibrateGoOn
	if not button then
		button = CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
		button:SetFrameStrata("FULLSCREEN_DIALOG")
		button:SetSize(240, 32)
		button:SetScript("OnClick", function(self)
			self:Hide()
			if not (run and run.paused) then return end
			run.paused, run.hadBubble = nil, nil
			SendLine()
			Box()
			BeginStep(run.steps[run.at])
			stepper:Show()
		end)
		ns.shoulderCalibrateGoOn = button
	end
	button:SetText(L["Say it again and go on"])
	button:ClearAllPoints()
	button:SetPoint("TOP", UIParent, "TOP", 0, -260)
	button:SetScale(UIParent:GetEffectiveScale())
	button:Show()
	ns.PadTestBox((L["Calibrating: step %d of %d"]):format(run.at, #run.steps),
		L["The bubble's gone: click the button below to go on."], 0.3, 1, 0.3)
	Log(("waiting at step %d of %d (%s)"):format(run.at, #run.steps, tostring(why)))
end

ns.SetOnUpdate(stepper, function(_, elapsed)
	if not run then
		stepper:Hide()
		return
	end
	run.tick = (run.tick or 0) + elapsed
	if run.tick < SAMPLE then return end
	local dt = run.tick
	run.tick = 0
	if InCombatLockdown() then return Finish(L["A fight started."]) end
	if UnitExists("target") then return Finish(L["You picked a target: clear it (Esc) and start again."]) end
	local x, why = BubbleSpot()
	run.waited = run.waited + dt
	if not x then
		if run.hadBubble or run.waited > 1.5 then Wait(why) end
		return
	end
	run.hadBubble = true
	if run.last and math.abs(x - run.last) > 0.001 then run.moved = run.waited end
	run.last = x
	if run.waited >= SETTLE and (run.waited - run.moved >= STILL or run.waited >= SETTLE_MOST) then
		local step = run.steps[run.at]
		if step[1] == 0 then run.baseline = x end
		local shift = run.baseline and x - run.baseline
		local want = WorkedOut(step[1])
		local factor = shift and math.abs(want) > 0.001 and shift / want or nil
		if factor then run.readings[#run.readings + 1] = factor end
		Log(("step %d: offset %.2f zoom %.2f: bubble x %.3f, real/worked-out %s"):format(run.at, step[1], Zoom(), x,
			factor and ("%.2f"):format(factor) or "?"))
		run.at = run.at + 1
		if run.steps[run.at] then
			Box()
			BeginStep(run.steps[run.at])
		else
			Finish()
		end
	end
end)

-- Why it can't start now, or nil.
local function CantStart()
	if run then return L["It's already running."] end
	if InCombatLockdown() then return L["Not in a fight."] end
	if IsMounted and ns.Flag(IsMounted()) then return L["Get off your mount first."] end
	if UnitExists("target") then return L["Clear your target first (Esc)."] end
	if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then return L["This client can't read chat bubbles."] end
	-- (Chat bubbles in dungeons, raids and battlegrounds are locked to addons.)
	if IsInInstance and ns.Flag(IsInInstance()) then return L["Not in a dungeon, raid or battleground."] end
end
ns.ShoulderCalibrateCantStart = CantStart

-- Starts it (from a click: the line needs one).
local function Start()
	local why = CantStart()
	if why then
		ns.Print(why)
		return
	end
	-- (Steps past the farthest the camera goes here left out.)
	local farthest = 15 * (tonumber(GetCVar("cameraDistanceMaxZoomFactor")) or 1) + 0.5
	local steps = {}
	for _, step in ipairs(STEPS) do
		if not step[2] or step[2] <= farthest then steps[#steps + 1] = step end
	end
	local key = ns.ShoulderModelKey and ns.ShoulderModelKey() or "?"
	run = { key = key, steps = steps, at = 1, readings = {},
		held = { offset = GetCVar(SHOULDER), centered = GetCVar(CENTERED), zoom = Zoom(),
			bubbles = GetCVar("chatBubbles"), reduce = GetCVar(REDUCE) } }
	local saved = {}
	for k, v in pairs(run.held) do saved[k] = v end
	ns.db.shoulderCalibrateHeld = saved
	SetCVar("chatBubbles", "1")
	SetCVar(REDUCE, "0")
	SetCVar(CENTERED, "0")
	ns.shoulderTestHold = true
	Log(("%s starting: offset %s, zoom %.2f, cameraFov %s"):format(key, tostring(run.held.offset), Zoom(),
		tostring(GetCVar("cameraFov"))))
	SendLine()
	Box()
	BeginStep(steps[1])
	stepper:Show()
	Changed()
end

-- A run cut off by a reload or logout: what it changed back at the next
-- login, then the Shoulder Cam's own settings over it again.
local leftover = CreateFrame("Frame")
leftover:RegisterEvent("PLAYER_ENTERING_WORLD")
leftover:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	local held = ns.db and ns.db.shoulderCalibrateHeld
	if type(held) ~= "table" then return end
	ns.db.shoulderCalibrateHeld = nil
	PutBackHeld(held)
	Log("a run was cut off: chat bubbles, Keep Character Centered and the motion sickness option put back")
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
end)

function ns.ShoulderCalibrateStop()
	if run then Finish(L["Stopped."]) end
end

-- The button's click: the warning first, its Yes starts it.
function ns.ShoulderCalibrateAsk()
	local why = CantStart()
	if why then
		ns.Print(why)
		return
	end
	if not StaticPopupDialogs.CINEMATIC_SHOULDER_CALIBRATE then
		StaticPopupDialogs.CINEMATIC_SHOULDER_CALIBRATE = {
			text = L["Calibrate the Shoulder Cam for %s?\n\nIt says a line in /say a few times (everyone near you " ..
				"sees it), so somewhere quiet is best. Stand still on open, flat ground and leave the camera " ..
				"alone for about 10 seconds."],
			button1 = YES or L["Yes"], button2 = NO or L["No"],
			OnAccept = function() Start() end,
			timeout = 0, whileDead = false, hideOnEscape = true,
		}
	end
	local key = ns.ShoulderModelKey and ns.ShoulderModelKey() or "?"
	StaticPopup_Show("CINEMATIC_SHOULDER_CALIBRATE", ns.ShoulderKeyName(key))
end
-- (The dev command: typed, so it can talk without the popup's click.)
ns.ShoulderCalibrateStart = Start

-- Your measurements on one line, to paste to us:
-- CINECAL1 <client> <version> <key>=<factor>/<spread>/<readings>[/redo] ...
function ns.ShoulderCalibrationLine()
	local list = ns.db and ns.db.shoulderCalibrations or {}
	local keys = {}
	for key in pairs(list) do keys[#keys + 1] = key end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		local c = list[key]
		if type(c) == "table" and c.factor then
			parts[#parts + 1] = ("%s=%.2f/%.3f/%d%s"):format(key, c.factor, c.spread or 0, c.readings or 0,
				c.good and "" or "/redo")
		end
	end
	if #parts == 0 then return nil end
	local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	local version = getMeta and getMeta(ADDON_NAME, "Version") or "?"
	return ("CINECAL1 %s %s %s %s"):format(ns.CLIENT or "?", tostring(version), date("%Y-%m-%d"), table.concat(parts, " "))
end

-- A measurement taken off: the built-in one (or the race's) goes back in use.
function ns.ShoulderCalibrationReset(key)
	local db = ns.db
	if db.shoulderCalibrations then db.shoulderCalibrations[key] = nil end
	if db.shoulderCamScales then db.shoulderCamScales[key] = nil end
	if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
	Log(("%s reset"):format(key))
	Changed()
end

-- The Calibrate tab: built by the Shoulder Cam page (ShoulderCam.lua).
function ns.BuildShoulderCalibrateTab(host, kit)
	local top = CreateFrame("Frame", nil, host)
	top:SetSize(1, 1)
	top:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 1)
	local stack = kit.Stack(top, "check")
	stack:Header(host, L["Calibrate"])
	stack:Note(host, L["If you sit too far to the side or too close to the middle in a form (or on foot), " ..
		"calibrate it. Share sends us your numbers so everyone gets them."], 440)
	local now = stack:Add(kit.Label(host, "GameFontNormal", ""), "label")
	now:SetWidth(440)
	now:SetJustifyH("LEFT")
	local go = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
	go:SetSize(150, 24)
	go:SetText(L["Calibrate"])
	if ns.SkinButton then ns.SkinButton(go) end
	stack:Add(go, "label")
	go:SetScript("OnClick", function()
		if run then ns.ShoulderCalibrateStop() else ns.ShoulderCalibrateAsk() end
	end)
	kit.Tooltip(go, L["Measures the race, sex and form you are now. Stand still on open, flat ground, nothing " ..
		"targeted, and leave the camera alone for about 10 seconds. It says a line in /say a few times."])
	local share = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
	share:SetSize(150, 24)
	share:SetText(L["Share"])
	if ns.SkinButton then ns.SkinButton(share) end
	share:SetPoint("LEFT", go, "RIGHT", 10, 0)
	share:SetScript("OnClick", function()
		local line = ns.ShoulderCalibrationLine()
		if line and ns.ShowCameraShare then ns.ShowCameraShare(line, L["Your Shoulder Cam measurements"]) end
	end)
	kit.Tooltip(share, L["Your measurements on one line: copy it and paste it to us on Discord or GitHub."])

	stack:Header(host, L["Your measurements"])
	-- (A table: who, form, size, how sure, when, and a Reset each. Columns'
	-- x from the row's left.)
	local COLS = { who = 0, what = 150, size = 270, sure = 320, when = 390, reset = 470 }
	local head = CreateFrame("Frame", nil, host)
	head:SetSize(530, 16)
	stack:Add(head, "label")
	local function HeadText(text, x)
		local label = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("LEFT", head, "LEFT", x, 0)
		label:SetText(text)
	end
	HeadText(L["Character"], COLS.who)
	HeadText(L["Form"], COLS.what)
	HeadText(L["Size"], COLS.size)
	HeadText(L["Result"], COLS.sure)
	HeadText(L["Date"], COLS.when)
	local none = head:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	none:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
	none:SetText(L["None yet: calibrate to add one."])
	local rows = {}
	local function Cell(row, x, width, font)
		local text = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
		text:SetPoint("LEFT", row, "LEFT", x, 0)
		text:SetWidth(width)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		return text
	end
	local function Row(i)
		if rows[i] then return rows[i] end
		local row = CreateFrame("Frame", nil, host)
		row:SetSize(530, 22)
		row:SetPoint("TOPLEFT", i == 1 and head or rows[i - 1], "BOTTOMLEFT", 0, i == 1 and -4 or 0)
		-- (Every other row a faint band, for the eye along it.)
		if i % 2 == 0 then
			local band = row:CreateTexture(nil, "BACKGROUND")
			band:SetAllPoints()
			band:SetColorTexture(1, 1, 1, 0.04)
		end
		row.who = Cell(row, COLS.who + 2, COLS.what - COLS.who - 6)
		row.what = Cell(row, COLS.what, COLS.size - COLS.what - 6)
		row.size = Cell(row, COLS.size, COLS.sure - COLS.size - 6)
		row.sure = Cell(row, COLS.sure, COLS.when - COLS.sure - 6, "GameFontHighlightSmall")
		row.when = Cell(row, COLS.when, COLS.reset - COLS.when - 6, "GameFontHighlightSmall")
		row.reset = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.reset:SetSize(56, 18)
		row.reset:SetPoint("LEFT", row, "LEFT", COLS.reset, 0)
		row.reset:SetText(L["Reset"])
		if ns.SkinButton then ns.SkinButton(row.reset) end
		row.reset:SetScript("OnClick", function(self) ns.ShoulderCalibrationReset(self.key) end)
		kit.Tooltip(row.reset, L["Stops using this measurement: the built-in size comes back."])
		rows[i] = row
		return row
	end

	local function Refresh()
		local key = ns.ShoulderModelKey and ns.ShoulderModelKey() or "?"
		local scale, from = 1, "?"
		if ns.ShoulderModelScale then scale, from = ns.ShoulderModelScale() end
		now:SetText((L["You now: |cffffffff%s|r, size |cffffffff%.2f|r |cff9d9d9d(%s)|r"]):format(
			ns.ShoulderKeyName(key), scale, tostring(from)))
		go:SetText(run and L["Stop"] or L["Calibrate"])
		local list = ns.db and ns.db.shoulderCalibrations or {}
		local keys = {}
		for k in pairs(list) do keys[#keys + 1] = k end
		table.sort(keys)
		none:SetShown(#keys == 0)
		for i, k in ipairs(keys) do
			local c = list[k]
			local row = Row(i)
			row.reset.key = k
			row.who:SetText((KeyParts(k)))
			row.what:SetText(select(2, KeyParts(k)))
			row.size:SetText(("%.2f"):format(c.factor or 0))
			row.sure:SetText(c.good and ("|cff60e060%s|r"):format(L["Good"]) or ("|cffff8040%s|r"):format(L["Not used"]))
			row.when:SetText(tostring(c.when or ""):match("^%S+") or "")
			row:Show()
		end
		for i = #keys + 1, #rows do rows[i]:Hide() end
		share:SetEnabled(#keys > 0)
	end
	kit.AddControl({ debugName = "shoulder calibrate tab", owner = host, Refresh = Refresh })
	ns.ShoulderCalibrateChanged = function() if host:IsVisible() then Refresh() end end
	-- (Shifting form with the tab open: "You now" follows.)
	local watch = CreateFrame("Frame", nil, host)
	watch:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	watch:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
	watch:SetScript("OnEvent", function() if host:IsVisible() then C_Timer.After(0.3, Refresh) end end)
	host:HookScript("OnShow", Refresh)
end
