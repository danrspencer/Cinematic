-- Cinematic: the Camera Scripts page, where camera scripts are
-- written (CameraScripts.lua runs them), and the preview window beside it.
--
-- The page: the camera picked, by its name at the top: a click drops the
-- list of every camera down over the page (the Camera hub's groups, then
-- yours, New camera and Import), gone again as you pick one. Then Copy,
-- Delete and Share, what starts it (the Scenes page rows set to it), Run
-- now and Stop. Then its steps, a row each (Together and Repeat with theirs indented
-- under them): a click picks one and opens its settings under it; the
-- buttons below add a step after the one picked (inside it, for Together and
-- Repeat). Then the stop rules, and When it ends, another list of steps.
-- The built-in ones show their steps but don't change: Copy one first.
--
-- The preview window plays the script on a drawing (from above, and from
-- the side), no camera moving, over and over, with a bar of its steps in
-- time: a click on the drawing pauses it, on the bar jumps there. It sits
-- beside the settings (docked) or anywhere you drag it (Pop out), and stays
-- up when they close; its corner grip sizes it (the drawing grows with it).
local _, ns = ...
local L = ns.L

-- (The page: the camera picked, full width. The list of every camera drops
-- down over it from the camera's name, LIST_W a column, two columns.)
local LEFT, WIDTH, LIST_W = 16, 568, 206
local COL = LEFT
local ROW_H, INDENT = 22, 16
local EDITOR_H = 66
local SHARE_PREFIX, SHARE_FORMAT = "CINES", 1
local COLORS = {
	move = { 0.4, 0.62, 1 }, wait = { 0.6, 0.62, 0.68 }, flow = { 0.68, 0.52, 0.95 }, misc = { 0.92, 0.62, 0.3 },
}
local KIND_COLOR = { rotate = "move", tilt = "move", zoom = "move",
	wait = "wait", together = "flow", ["repeat"] = "flow", emote = "misc", putback = "misc",
	sway = "move", spin = "move", aim = "move", ending = "flow",
	play = "flow", endMusic = "misc", follow = "move", behind = "move" }
local KIND_NAMES = { rotate = "Rotate", tilt = "Tilt", zoom = "Zoom",
	wait = "Wait", together = "Together", ["repeat"] = "Repeat", emote = "Emote",
	putback = "Undo its turns", sway = "Sway", spin = "Spin",
	aim = "Aim at", play = "Play script", endMusic = "End music",
	follow = "Follow your turns", behind = "Swing behind you" }
-- The add buttons' groups (CameraScripts.lua's ns.CAMERA_SCRIPT_ADD_GROUPS).
local ADD_GROUP_NAMES = { move = "Move the camera", wait = "Wait", group = "Group steps", other = "Other" }
-- (A field's name: by its kind first, where the same key means something else there.)
local FIELD_NAMES = { deg = "Degrees", secs = "Seconds", way = "Way", ease = "Ease", to = "Yards", min = "Nearest",
	max = "Furthest", token = "Emote", times = "Times", of = "From", arc = "Arc", drift = "Drift",
	pause = "Pause", favor = "Middle", down = "Down", up = "Up", accel = "Speed-up",
	["sway.min"] = "At least", ["spin.max"] = "Top speed", ["spin.start"] = "Start speed", blend = "Speed match", speedUp = "Speed up", slowDown = "Slow down", what = "Until", after = "After", rand = "Random",
	["tilt.up"] = "Higher by", ["tilt.down"] = "Lower by", ["zoom.max"] = "Up to", ["wait.max"] = "Up to",
	fit = "Time", at = "At", miss = "Not found",
	speed = "Top speed", past = "Past max", ["putback.zoom"] = "Zoom too", script = "Camera",
	["follow.after"] = "Glide after", lazy = "Laziness", top = "Top speed", corners = "Corners", steer = "Steering",
	["follow.most"] = "Fall behind at most", ["behind.speed"] = "Turn speed" }
local CHOICE_NAMES = { left = "Left", right = "Right", random = "Either way", once = "Picked once",
	smooth = "Smooth", gentle = "Gentle", steady = "Steady", none = "None", short = "Short", medium = "Medium", long = "Long", yards = "You", yours = "Your zoom",
	yes = "Favor", no = "Anywhere", cast = "The cast", landing = "Landing", alive = "Back to life",
	time = "Seconds go by", secs = "Its seconds", talk = "Someone new talks", click = "Where you clicked",
	speaker = "Who's talking", stay = "Stay", look = "Look round", ["past.no"] = "No", ["past.yes"] = "Yes",
	["zoom.no"] = "No", ["zoom.yes"] = "Yes", ["corners.no"] = "No", ["corners.yes"] = "Quicker",
	["steer.no"] = "No", ["steer.yes"] = "Quicker", ["rand.no"] = "No", ["rand.between"] = "Between two",
	["rand.give"] = "Give or take" }
local RULE_NAMES = { camera = "You move the camera", fight = "A fight starts", walk = "You walk", zoom = "You zoom",
	ends = "Its trigger ends", cast = "Your cast ends", window = "A window opens",
	closed = "Its quest window closes", done = "Its steps run out" }
-- (The rules a few words don't say enough for: the dropdown's tooltip.)
local RULE_TIPS = {
	window = "A quest giver's, a vendor's, the game menu, your bags...: any window that pauses the cameras (Pause cameras in windows on the Scenes page). Pause: it waits where it is, however long the window's open, and carries on as it closes. Scenes a window starts (a quest giver, an Interaction) aren't held by their own window.",
	closed = "Played for a quest giver: you accepted, handed in or picked the next quest, and their window closed. Pause: it stops where it is (a zoom in under way too) and holds that many seconds before going on; its trigger ending meanwhile (the conversation's over 3 seconds after the last window) waits for it, so the zoom back out comes after the pause. The next quest's window opening carries on at once. Leaving (Escape, Goodbye) isn't this: that ends the trigger.",
	done = "Every step played, for a trigger. Hold: it stays where it got to until its trigger's over, then runs When it ends. (Played by hand, with Run, there's no trigger: When it ends runs.)",
}
local ACTION_NAMES = { stop = "Stop, leave it there", putback = "Run When it ends", pause = "Pause, then carry on",
	restart = "Start again", ignore = "Carry on", hold = "Hold till its trigger ends" }
local HINTS = {
	rotate = "Turns the view. Picked once: one way for every such turn in the script. Slow down None ends at full speed, for a turn the same way next to carry straight on; Speed match: seconds to go from that speed to its own.",
	tilt = "Positive tilts down, negative up; beside a turn (Together) both go at once. Random Give or take: to Height from where the scene started, give or take Higher by and Lower by, picked each time. Slow down None ends at full speed, for a tilt the same way next to carry straight on; Speed match: seconds to go from that speed to its own.",
	zoom = "Zooms to this many yards from you, or (From: your zoom) this many further out than you were as it started. Random Between two: somewhere from Nearest to Up to, picked each time. Top speed (yards a second): quicker if it gets there sooner; 0 goes by Seconds. Past max: beyond the game's own limit.",
	wait = "Until: seconds, or a Hearthstone or teleport cast that many seconds from done, that many seconds before landing, back to life, or someone new talks. Waiting on something, steps added while it's picked go inside it and run meanwhile, easing to a stop when it's time.",
	together = "Runs the steps inside it at once; it's done when the longest is. Pick it and add steps to put them inside.",
	["repeat"] = "Runs the steps inside it again. 0 times: until the camera ends (the preview shows three).",
	emote = "Your character does this emote (a word, like wave or cheer).",
	putback = "Undoes every turn, tilt and zoom this scene made, all at once, by adding up its own turns (the game never says which way the camera points). If you move the camera yourself, it starts counting again from where you leave it. Zoom too off: the zoom stays, for a Zoom beside it in a Together to bring back at its own speed.",
	behind = "Swings the view round behind you over this many seconds, turning at Turn speed (degrees a second) at most; the height stays. Only while you're moving (a flight, walking or running): standing still, the game doesn't turn the camera. Where it ends counts as where the scene started, for Undo its turns and Sway.",
	sway = "A random spot within Arc of where the camera was as this sway first ran, At least that far on; then it creeps on at Drift degrees a second through Pause, easing off before the edge. Middle: favor spots near the middle.",
	spin = "Round and round from Start speed, speeding up by Speed-up each second to Top speed (degrees a second); 0 seconds: until the camera ends. Speed match: seconds to go from the turn before's speed to its own.",
	aim = "Where you clicked: turns Degrees toward the side of the screen you clicked who you're talking to, as the quest cam does. Who's talking: swings toward the NPC talking now by their chat bubble, leaving them Degrees off the middle, as Chat Cam does. Not found (opened with a key, no bubble on screen): a turn either way, stay, or look round (a full turn at most) for their bubble. Top speed (degrees a second): slower than Seconds if the turn would go faster; 0 goes by Seconds.",
	play = "Plays another camera's steps here, as they are now (a built-in one with your settings), then goes on. Not its stop rules or When it ends.",
	endMusic = "Fades out the music a camera started, over this many seconds, and ends it (your own game music is left alone). The next steps go on meanwhile. Put it in When it ends to stop the music as the scene ends.",
	follow = "Runs until the camera ends: put it in a Together beside the rest. While you turn, the view holds its direction instead of swinging round with you. Glide after seconds of not turning, it glides round after you, to where it was before you turned: Laziness (seconds) says how lazily (the further off, the quicker), Top speed (degrees a second) the fastest, Speed-up how quickly it gets going and slows down. Corners: bigger turns glide back quicker, small ones gentler. Steering: several turns in a row glide sooner and quicker. Fall behind at most (degrees, 0: no limit): the furthest it lets you turn away from the view; past it, the view turns with you. The script's other turns wait while it glides, then carry on.",
}
local function Translate(map)
	for key, text in pairs(map) do map[key] = L[text] end
end
ns.OnLanguage(function()
	for _, map in ipairs({ KIND_NAMES, FIELD_NAMES, CHOICE_NAMES, RULE_NAMES, RULE_TIPS, ACTION_NAMES, HINTS }) do
		Translate(map)
	end
end)

local function Num(n)
	return (("%.1f"):format(n):gsub("%.0$", ""))
end

-- (+2, -1.5: from your distance.)
local function Signed(n)
	return (n >= 0 and "+" or "-") .. Num(math.abs(n))
end

-- A step's line on the page.
local function StepText(step)
	if step.k == "ending" then
		return #step.steps > 0 and L["When it ends"] or L["When it ends: nothing, it stays where it is"]
	end
	local k = step.k
	if k == "zoom" and step.rand == "between" then
		local low, high = math.min(step.to, step.max), math.max(step.to, step.max)
		return (step.of == "yours" and L["Zoom somewhere from your distance %s to %s yd over %s s"]:format(Signed(low),
			Signed(high), Num(step.secs)) or L["Zoom somewhere from %s to %s yd over %s s"]:format(Num(low), Num(high),
			Num(step.secs)))
	elseif k == "tilt" and step.rand == "give" then
		return L["Tilt to %s° give or take %s/%s over %s s"]:format(Signed(step.deg), Num(step.up), Num(step.down),
			Num(step.secs))
	elseif k == "zoom" and step.fit == "cast" then
		return (step.of == "yours" and L["Zoom to your distance %s yd over the cast"]:format(Signed(step.to))
			or L["Zoom to %s yd over the cast"]:format(Num(step.to)))
	elseif k == "rotate" then
		local way = step.way == "random" and L["either way"] or step.way == "once" and L["either way, the same each time"]
			or step.way == "left" and L["left"] or L["right"]
		return L["Rotate %s° %s over %s s"]:format(Num(step.deg), way, Num(step.secs))
	elseif k == "tilt" then
		if step.deg == 0 then return L["Tilt 0° (no tilt)"] end
		return (step.deg > 0 and L["Tilt %s° down over %s s"] or L["Tilt %s° up over %s s"]):format(Num(math.abs(step.deg)),
			Num(step.secs))
	elseif k == "zoom" and step.of == "yours" then
		return L["Zoom to your distance %s yd over %s s"]:format(Signed(step.to), Num(step.secs))
	elseif k == "zoom" then
		return L["Zoom to %s yd over %s s"]:format(Num(step.to), Num(step.secs))
	elseif k == "wait" and step.what == "time" and #(step.steps or {}) == 0 then
		if step.rand == "between" then
			return L["Wait %s to %s s"]:format(Num(math.min(step.secs, step.max)), Num(math.max(step.secs, step.max)))
		end
		return L["Wait %s s"]:format(Num(step.secs))
	elseif k == "wait" then
		local text = step.what == "cast" and (step.secs > 0 and L["Until the cast is %s s from done"]:format(Num(step.secs))
			or L["Until the cast ends"])
			or step.what == "landing" and L["Until %s s before landing"]:format(Num(step.secs))
			or step.what == "alive" and L["Until you're back to life"]
			or step.what == "talk" and L["Until someone new talks"]
			or step.rand == "between" and L["Until %s to %s s go by"]:format(Num(math.min(step.secs, step.max)),
				Num(math.max(step.secs, step.max)))
			or L["Until %s s go by"]:format(Num(step.secs))
		return #step.steps > 0 and text .. L[", doing these"] or text
	elseif k == "aim" then
		return (step.at == "click" and L["Turn %s° toward where you clicked them over %s s"]
			or L["Swing to who's talking, %s° off the middle, over %s s"]):format(Num(step.deg), Num(step.secs))
	elseif k == "sway" then
		local text = L["Sway within %s° of where the sway began over %s s"]:format(Num(step.arc), Num(step.secs))
		if step.pause > 0 then
			text = text .. ", " .. (step.drift > 0 and L["drift %s°/s for %s s"]:format(Num(step.drift), Num(step.pause))
				or L["hold %s s"]:format(Num(step.pause)))
		end
		return text
	elseif k == "spin" and step.start > 0 then
		return (step.secs > 0 and L["Spin from %s to %s°/s, for %s s"]:format(Num(step.start), Num(step.max), Num(step.secs))
			or L["Spin from %s to %s°/s, until it ends"]:format(Num(step.start), Num(step.max)))
	elseif k == "spin" then
		return (step.secs > 0 and L["Spin, speeding up to %s°/s, for %s s"]:format(Num(step.max), Num(step.secs))
			or L["Spin, speeding up to %s°/s, until it ends"]:format(Num(step.max)))
	elseif k == "play" then
		local played = ns.FindCameraScript(step.script)
		return L["Play %s"]:format(played and played.name or step.script)
	elseif k == "emote" then
		return L["Do /%s"]:format(step.token)
	elseif k == "endMusic" then
		return L["End the music over %s s"]:format(Num(step.secs))
	elseif k == "follow" then
		return L["Follow your turns, catching up %s s after"]:format(Num(step.after))
	elseif k == "behind" then
		return L["Swing behind you over %s s"]:format(Num(step.secs))
	elseif k == "putback" then
		return (step.zoom == "no" and L["Undo its turns and tilts over %s s"] or L["Undo its turns, tilts and zoom over %s s"]):format(
			Num(step.secs))
	elseif k == "together" then
		return #step.steps == 0 and L["Together (empty: pick it and add steps)"] or L["Together: these at once"]
	elseif k == "repeat" then
		local text = step.times == 0 and L["Repeat until it ends"] or L["Repeat %s times"]:format(Num(step.times))
		return #step.steps == 0 and text .. " " .. L["(empty: pick it and add steps)"] or text
	end
	return k
end

local function CountSteps(list)
	local n = 0
	for _, step in ipairs(list) do
		n = n + 1 + (step.steps and CountSteps(step.steps) or 0)
	end
	return n
end

-- Where a step is: its list and place (searched through both lists).
local function FindStep(list, step)
	for i, each in ipairs(list) do
		if each == step then return list, i end
		if each.steps then
			local found, at = FindStep(each.steps, step)
			if found then return found, at end
		end
	end
end

local page = {} -- the page's state and widgets
local preview -- the preview window, once made

-- A choice: a dropdown (or, on a client without the modern one, a button
-- that steps through them). choices() and value() are asked each time.
local function Choice(parent, width, choices, value, set, nameOf)
	local ok, pick = ns.MenuDropdown(parent)
	if ok and pick and pick.SetupMenu then
		pick:SetWidth(width)
		pick:SetupMenu(function(_, root)
			for _, choice in ipairs(choices()) do
				root:CreateRadio(nameOf(choice), function() return value() == choice end, function() set(choice) end)
			end
		end)
		pick.Refresh = function(self) self:GenerateMenu() end
	else
		pick = ns.PanelButton(parent)
		pick:SetSize(width, 22)
		pick:SetScript("OnClick", function()
			local list, now = choices(), value()
			for i, choice in ipairs(list) do
				if choice == now then
					set(list[i % #list + 1])
					return
				end
			end
			if list[1] then set(list[1]) end
		end)
		pick.Refresh = function(self) self:SetText(nameOf(value()) or "") end
	end
	pick.searchSkip = true
	return pick
end

local function Button(parent, text, width)
	local button = ns.PanelButton(parent)
	button:SetSize(width, 22)
	button:SetText(text)
	return button
end

local function Box(parent, width)
	local box = ns.SkinEditBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return box
end

-- A number box the mouse wheel turns up and down: by stepOf()'s step (nil:
-- not a number now, the wheel does nothing), ten times that with Shift, a
-- tenth with Ctrl; then saved as typing it would be (its OnEditFocusLost,
-- which keeps it in range).
local function WheelNumber(box, stepOf)
	box:EnableMouseWheel(true)
	box:SetScript("OnMouseWheel", function(self, delta)
		local by = stepOf()
		if not by or (self.IsEnabled and not self:IsEnabled()) then return end
		by = by * (IsShiftKeyDown() and 10 or IsControlKeyDown() and 0.1 or 1)
		local value = (tonumber(self:GetText()) or 0) + delta * by
		value = math.floor(value / by + 0.5) * by
		self:SetText((("%.2f"):format(value):gsub("%.?0+$", "")))
		local save = self:GetScript("OnEditFocusLost")
		if save then save(self) end
	end)
end

local function IconButton(parent, art, tip)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(16, 16)
	button:SetNormalTexture(art)
	button:SetHighlightTexture(art)
	button:GetHighlightTexture():SetAlpha(0.4)
	if tip then
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(tip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	return button
end

-- ---------------------------------------------------------------------------
-- The preview window
-- ---------------------------------------------------------------------------

local VIEW, SIDE = 200, 84
local RINGS, SEGMENTS = { 3, 6, 9, 12 }, 32
local YARD = (VIEW / 2 - 8) / 13 -- pixels a yard, from above
local SIDE_YARD = 9
local START_HEIGHT = 25 -- degrees: the camera's height above you the drawing starts at

local function NewLine(parent, r, g, b, a, thick)
	if not parent.CreateLine then return nil end
	local line = parent:CreateLine(nil, "ARTWORK")
	line:SetThickness(thick or 1)
	line:SetColorTexture(r, g, b, a)
	return line
end
local function SetLine(line, parent, x1, y1, x2, y2)
	if not line then return end
	line:SetStartPoint("CENTER", parent, x1, y1)
	line:SetEndPoint("CENTER", parent, x2, y2)
end
local function Dot(parent, size, r, g, b)
	local dot = parent:CreateTexture(nil, "OVERLAY")
	dot:SetSize(size, size)
	dot:SetColorTexture(r, g, b, 1)
	return dot
end

local function Store()
	local db = ns.GetDB()
	if type(db.cameraScripts) ~= "table" then db.cameraScripts = {} end
	return db.cameraScripts
end

-- The settings window the page is in (to dock beside).
local function SettingsWindow()
	local frame = page.canvas
	while frame and frame:GetParent() and frame:GetParent() ~= UIParent do frame = frame:GetParent() end
	return frame
end

local function PlacePreview()
	local w = preview
	local saved = Store().preview
	w:ClearAllPoints()
	if type(saved) == "table" and saved.x and saved.y then
		w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
		w.dock:SetText(L["Dock"])
	else
		local settings = SettingsWindow()
		if settings and settings:IsShown() then
			w:SetPoint("TOPLEFT", settings, "TOPRIGHT", 4, 0)
		else
			w:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
		end
		w.dock:SetText(L["Pop out"])
	end
end

-- Draws the camera where the plan has it at t.
local function DrawPreview()
	local w = preview
	if not w.plan then return end
	local yaw, pitch, zoom = ns.SampleCameraPlan(w.plan, w.t, w.start)
	local height = math.max(-10, math.min(85, START_HEIGHT - pitch))
	local flat = math.min(13, zoom * math.cos(math.rad(height)))
	-- From above: you in the middle facing up; the view turned left puts the
	-- camera round to your right.
	local cx, cy = math.sin(math.rad(yaw)) * flat * YARD, -math.cos(math.rad(yaw)) * flat * YARD
	w.camDot:ClearAllPoints()
	w.camDot:SetPoint("CENTER", w.view, "CENTER", cx, cy)
	SetLine(w.sight, w.view, cx, cy, 0, 0)
	local toward = math.atan2(-cy, -cx)
	for i, side in ipairs({ -0.45, 0.45 }) do
		SetLine(w.cone[i], w.view, cx, cy, cx + math.cos(toward + side) * 46, cy + math.sin(toward + side) * 46)
	end
	-- From the side: you standing on the ground, the camera up on its arc.
	local hx, hy = -SIDE / 2 + 14, -40
	local sx = hx + math.cos(math.rad(height)) * math.min(zoom, 9) * SIDE_YARD * 0.7
	local sy = hy + math.sin(math.rad(height)) * math.min(zoom, 9) * SIDE_YARD
	w.sideDot:ClearAllPoints()
	w.sideDot:SetPoint("CENTER", w.side, "CENTER", math.min(sx, SIDE / 2 - 6), math.max(-90, math.min(90, sy)))
	SetLine(w.sideSight, w.side, math.min(sx, SIDE / 2 - 6), math.max(-90, math.min(90, sy)), hx, hy)
	w.readout:SetText(L["Turn %d°   Tilt %d°   Zoom %s yd   %s / %s s"]:format(math.floor(yaw + 0.5),
		math.floor(pitch + 0.5), Num(zoom), Num(w.t), Num(w.plan.total)))
	w.head:ClearAllPoints()
	w.head:SetPoint("LEFT", w.bar, "LEFT", (w.bar:GetWidth() - 2) * math.min(1, w.t / w.plan.total), 0)
	-- (Following Run: once it's over, how to play it again.)
	w.status:SetText(w.following and "" or L["Stopped. Run plays it again."])
end

-- Lays the script out again (after a change) and draws its steps' bar.
function ns.RefreshCameraScriptPreview()
	local w = preview
	if not w or not w:IsShown() or not page.script then return end
	w.title:SetText(page.script.name)
	w.start = { yaw = 0, pitch = 0, zoom = math.max(2, GetCameraZoom and GetCameraZoom() or 8) }
	w.plan = ns.PlanCameraScript(page.script, w.start)
	w.t = math.min(w.t or 0, w.plan.total)
	for _, seg in ipairs(w.segments) do seg:Hide() end
	local width = w.bar:GetWidth()
	for i, span in ipairs(w.plan.spans) do
		local seg = w.segments[i]
		if not seg then
			seg = w.bar:CreateTexture(nil, "ARTWORK")
			w.segments[i] = seg
		end
		local c = COLORS[KIND_COLOR[span.step.k]] or COLORS.wait
		seg:SetColorTexture(c[1], c[2], c[3], i % 2 == 0 and 0.75 or 0.95)
		seg:ClearAllPoints()
		seg:SetPoint("TOPLEFT", w.bar, "TOPLEFT", width * span.t0 / w.plan.total, -1)
		seg:SetSize(math.max(1, width * (span.t1 - span.t0) / w.plan.total), w.bar:GetHeight() - 2)
		seg:Show()
	end
	DrawPreview()
end

-- The window's size: the drawing (ART_W by VIEW at scale 1) scaled to fill
-- what's left of it after the title (TOP) and the readout, bar and paused
-- line under it (UNDER); never smaller than at scale 1.
local ART_W, TOP, UNDER, SIDES = VIEW + 8 + SIDE, 34, 58, 24
local MIN_W, MIN_H = ART_W + SIDES, TOP + VIEW + UNDER
local function FitPreview()
	local w = preview
	local width, height = w:GetSize()
	local scale = math.max(0.5, math.min((width - SIDES) / ART_W, (height - TOP - UNDER) / VIEW))
	w.art:SetScale(scale)
	w.art:ClearAllPoints()
	w.art:SetPoint("TOP", w, "TOP", 0, -TOP / scale)
	w.readout:ClearAllPoints()
	w.readout:SetPoint("TOPLEFT", w, "TOPLEFT", 12, -(TOP + VIEW * scale + 8))
	w.bar:ClearAllPoints()
	w.bar:SetPoint("TOPLEFT", w.readout, "BOTTOMLEFT", 0, -6)
	w.bar:SetPoint("RIGHT", w, "RIGHT", -12, 0)
	w.status:SetWidth(width - SIDES)
end

local function MakePreview()
	local w = CreateFrame("Frame", "CinematicScriptPreview", UIParent, "BackdropTemplate")
	preview = w
	local size = Store().previewSize
	w:SetSize(type(size) == "table" and tonumber(size.w) or MIN_W, type(size) == "table" and tonumber(size.h) or MIN_H)
	w:SetResizable(true)
	local most = { UIParent:GetWidth() * 0.9, UIParent:GetHeight() * 0.9 }
	if w.SetResizeBounds then
		w:SetResizeBounds(MIN_W, MIN_H, most[1], most[2])
	elseif w.SetMinResize then
		w:SetMinResize(MIN_W, MIN_H)
		w:SetMaxResize(most[1], most[2])
	end
	w:SetFrameStrata("DIALOG")
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	if w.SetBackdrop then
		w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	end
	ns.SkinWindow(w)
	tinsert(UISpecialFrames, "CinematicScriptPreview")
	ns.CloseWithSettings(w)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", function(self)
		local saved = Store().preview
		if type(saved) == "table" and saved.x then self:StartMoving() end
	end)
	w:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Store().preview = { x = self:GetLeft(), y = self:GetTop() }
	end)

	w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	w.title:SetPoint("TOPLEFT", 12, -10)
	w.title:SetPoint("RIGHT", -92, 0)
	w.title:SetJustifyH("LEFT")
	w.title:SetWordWrap(false)
	local close = ns.SkinClose(CreateFrame("Button", nil, w, "UIPanelCloseButton"))
	close:SetPoint("TOPRIGHT", 0, 0)
	w.dock = Button(w, L["Pop out"], 70)
	w.dock:SetPoint("TOPRIGHT", -28, -6)
	w.dock:SetScript("OnClick", function()
		local store = Store()
		if type(store.preview) == "table" and store.preview.x then
			store.preview = nil
		else
			store.preview = { x = w:GetLeft() + 30, y = w:GetTop() - 30 }
		end
		PlacePreview()
	end)
	ns.lowHealthKit.Tooltip(w.dock, L["Pop out: drag the window anywhere (by its edge). Dock: back beside the settings."])

	-- The drawing: where the camera is, from above and from the side.
	w.art = CreateFrame("Frame", nil, w)
	w.art:SetSize(ART_W, VIEW)
	local view = CreateFrame("Frame", nil, w.art)
	view:SetSize(VIEW, VIEW)
	view:SetPoint("TOPLEFT")
	local viewBg = view:CreateTexture(nil, "BACKGROUND")
	viewBg:SetAllPoints()
	viewBg:SetColorTexture(0, 0, 0, 0.45)
	w.view = view
	for _, yards in ipairs(RINGS) do
		local r = yards * YARD
		for i = 1, SEGMENTS do
			local a1, a2 = (i - 1) / SEGMENTS * 2 * math.pi, i / SEGMENTS * 2 * math.pi
			SetLine(NewLine(view, 0.5, 0.5, 0.55, 0.35), view, math.cos(a1) * r, math.sin(a1) * r, math.cos(a2) * r,
				math.sin(a2) * r)
		end
		local label = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		label:SetPoint("BOTTOM", view, "CENTER", 0, r + 1)
		label:SetText(L["%d yd"]:format(yards))
	end
	local you = Dot(view, 7, 1, 1, 1)
	you:SetPoint("CENTER")
	SetLine(NewLine(view, 1, 1, 1, 0.9, 2), view, 0, 0, 0, 14) -- (facing up)
	w.sight = NewLine(view, 1, 0.82, 0, 0.8, 1)
	w.cone = { NewLine(view, 1, 0.82, 0, 0.35), NewLine(view, 1, 0.82, 0, 0.35) }
	w.camDot = Dot(view, 9, 1, 0.82, 0)

	local side = CreateFrame("Frame", nil, w.art)
	side:SetSize(SIDE, VIEW)
	side:SetPoint("TOPLEFT", view, "TOPRIGHT", 8, 0)
	local sideBg = side:CreateTexture(nil, "BACKGROUND")
	sideBg:SetAllPoints()
	sideBg:SetColorTexture(0, 0, 0, 0.45)
	w.side = side
	SetLine(NewLine(side, 0.5, 0.5, 0.55, 0.6, 2), side, -SIDE / 2 + 2, -62, SIDE / 2 - 2, -62)
	local body = side:CreateTexture(nil, "ARTWORK")
	body:SetColorTexture(1, 1, 1, 0.9)
	body:SetSize(6, 22)
	body:SetPoint("BOTTOM", side, "CENTER", -SIDE / 2 + 14, -62)
	w.sideSight = NewLine(side, 1, 0.82, 0, 0.8)
	w.sideDot = Dot(side, 8, 1, 0.82, 0)
	local sideLabel = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sideLabel:SetPoint("BOTTOM", 0, 6)
	sideLabel:SetText(L["side"])

	w.readout = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	-- The bar: the script's steps, and how far in it is.
	w.bar = CreateFrame("Frame", nil, w)
	w.bar:SetHeight(12)
	local barBg = w.bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	barBg:SetColorTexture(0, 0, 0, 0.5)
	w.head = w.bar:CreateTexture(nil, "OVERLAY")
	w.head:SetColorTexture(1, 1, 1, 1)
	w.head:SetSize(2, 14)
	w.segments = {}

	w.status = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	w.status:SetPoint("TOPLEFT", w.bar, "BOTTOMLEFT", 0, -6)
	w.status:SetJustifyH("LEFT")

	-- The corner grip (the chat frames' own) sizes it.
	local grip = CreateFrame("Button", nil, w)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel(w:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnMouseDown", function()
		w.sizing = true
		w:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		w:StopMovingOrSizing()
		w.sizing = nil
		Store().previewSize = { w = math.floor(w:GetWidth() + 0.5), h = math.floor(w:GetHeight() + 0.5) }
		PlacePreview() -- (sizing moved its anchor: back where it goes, docked or not)
	end)
	w:SetScript("OnSizeChanged", function()
		FitPreview()
		ns.RefreshCameraScriptPreview()
	end)
	FitPreview()

	-- It follows Run: the real camera's time into this script, while it's
	-- the one running. (Its plan's moves, so a random one may differ a little
	-- from the camera's.)
	ns.SetOnUpdate(w, function()
		if not w.plan then return end
		local state = ns.CameraScriptState()
		local following = state and page.script and state.script.id == page.script.id and true or nil
		if following then w.t = math.min(w.plan.total, state.t) end
		if following or following ~= w.following then
			w.following = following
			DrawPreview()
		end
	end)
	w:SetScript("OnHide", function()
		if w.sizing then
			w:StopMovingOrSizing()
			w.sizing = nil
		end
	end)
	w:Hide()
end

function ns.ShowCameraScriptPreview()
	if not preview then MakePreview() end
	preview:Show()
	PlacePreview()
	preview.t, preview.following = 0, nil
	ns.RefreshCameraScriptPreview()
end

-- ---------------------------------------------------------------------------
-- The share window
-- ---------------------------------------------------------------------------

local share
local function ShareWindow()
	if share then return share end
	share = CreateFrame("Frame", "CinematicScriptShare", UIParent, "BackdropTemplate")
	share:SetSize(460, 260)
	share:SetPoint("CENTER")
	share:SetFrameStrata("DIALOG")
	share:EnableMouse(true)
	if share.SetBackdrop then
		share:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	end
	ns.SkinWindow(share)
	tinsert(UISpecialFrames, "CinematicScriptShare")
	share.title = share:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	share.title:SetPoint("TOPLEFT", 14, -12)
	local close = ns.SkinClose(CreateFrame("Button", nil, share, "UIPanelCloseButton"))
	close:SetPoint("TOPRIGHT", 0, 0)
	ns.DockBeside(share, "scriptShare"):SetPoint("TOPRIGHT", -28, -6)
	share.hint = share:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	share.hint:SetPoint("TOPLEFT", 14, -32)
	share.hint:SetWidth(430)
	share.hint:SetJustifyH("LEFT")
	local scroll = ns.SkinScroll(CreateFrame("ScrollFrame", nil, share, "UIPanelScrollFrameTemplate"))
	scroll:SetPoint("TOPLEFT", 14, -64)
	scroll:SetPoint("BOTTOMRIGHT", -34, 44)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(400)
	scroll:SetScrollChild(box)
	box:SetScript("OnEscapePressed", function() share:Hide() end)
	share.box = box
	share.status = share:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	share.status:SetPoint("BOTTOMLEFT", 14, 18)
	share.status:SetWidth(300)
	share.status:SetJustifyH("LEFT")
	share.accept = Button(share, L["Add script"], 110)
	share.accept:SetPoint("BOTTOMRIGHT", -14, 12)
	local WHY = { empty = "", newer = "This script is from a newer Cinematic: update it to add this one.",
		other = "That isn't a camera script (they start CINES1:).", broken = "That isn't a whole script: copy it again, all of it." }
	box:SetScript("OnTextChanged", function(self, userInput)
		if share.mode == "export" then
			if userInput then
				self:SetText(share.text)
				self:HighlightText()
			end
			return
		end
		local data, why = ns.UnpackShared(SHARE_PREFIX, SHARE_FORMAT, self:GetText())
		share.data = data and ns.CleanCameraScript(data, "import")
		share.accept:SetEnabled(share.data ~= nil)
		share.status:SetText(share.data and L["%s: %d steps. Add script adds it to yours."]:format(share.data.name,
			CountSteps(share.data.steps) + CountSteps(share.data.ending)) or L[WHY[why] or ""])
	end)
	share.accept:SetScript("OnClick", function()
		if not share.data then return end
		local script = ns.AddCameraScript(share.data, share.data.name)
		if not script then
			ns.Print(L["You have 30 camera scripts already: delete one to add another."])
			return
		end
		share:Hide()
		page.Pick(script.id)
	end)
	return share
end

local function ShowShare(export)
	local window = ShareWindow()
	window.mode = export and "export" or "import"
	if export then
		local script = page.script
		window.text = ns.PackShared(SHARE_PREFIX, SHARE_FORMAT, { name = script.name, steps = script.steps,
			ending = script.ending, rules = script.rules,
			icon = script.icon, desc = script.desc })
		window.title:SetText(L["Share %s"]:format(script.name))
		window.hint:SetText(L["Press Ctrl+C to copy this, then paste it wherever your friends will see it. They " ..
			"add it with Import on their Scripts page."])
		window.accept:Hide()
		window.status:SetText("")
	else
		window.text = ""
		window.title:SetText(L["Import a camera script"])
		window.hint:SetText(L["Paste in a script someone shared (Ctrl+V), then Add script. It's added as a new " ..
			"script of yours."])
		window.accept:Show()
		window.accept:SetEnabled(false)
	end
	window:Show()
	window.box:SetText(window.text)
	window.box:SetFocus()
	if export then window.box:HighlightText() end
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

-- Every camera, in the Camera hub's groups, then yours. A string: a built-in
-- script's id. own: a camera that isn't a script yet (its value in
-- ns.CAMERA_NAMES, and the steps it waits for).
local CAMERA_LIST = {
	{ section = "At rest", color = { 0.3, 0.7, 0.5 }, items = { "cozy", "vista", "fish", "afk", "tele" } },
	{ section = "Travel", color = { 0.35, 0.6, 0.9 }, items = { "flight", "flyby", "walk", "run" } },
	{ section = "Moments", color = { 0.65, 0.45, 0.9 }, items = { "quest", "chat", "death" } },
	{ section = "Yours", color = { 0.92, 0.62, 0.3 }, mine = true },
}
ns.OnLanguage(function()
	for _, group in ipairs(CAMERA_LIST) do group.section = L[group.section] end
end)
local LIST_ROW = 18
local DOT = { script = { 0.3, 0.8, 0.5 }, own = { 0.6, 0.6, 0.65 }, mine = { 1, 0.62, 0.25 } }

-- A step row (pooled): its line, colour strip, and up, down and delete.
local function StepRow(content)
	local row = CreateFrame("Button", nil, content)
	row:SetSize(WIDTH, ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.strip = row:CreateTexture(nil, "ARTWORK")
	row.strip:SetSize(3, ROW_H - 4)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.text:SetPoint("RIGHT", -64, 0)
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.06)
	row.del = IconButton(row, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", L["Remove this step"])
	row.del:SetPoint("RIGHT", -4, 0)
	-- (The scroll bar's arrows: the plain Arrow-Up/Down art sits off-center in
	-- its square, the up one low and the down one high, so a pair looked uneven.)
	-- (Bigger than the remove button: the art has a wide empty edge.)
	row.down = IconButton(row, "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up", L["Move down"])
	row.down:SetSize(24, 24)
	row.down:SetPoint("RIGHT", row.del, "LEFT", 0, 0)
	row.up = IconButton(row, "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up", L["Move up"])
	row.up:SetSize(24, 24)
	row.up:SetPoint("RIGHT", row.down, "LEFT", 2, 0)
	row:SetScript("OnClick", function(self)
		page.selected = page.selected ~= self.step and self.step or nil
		page.Layout()
	end)
	row.up:SetScript("OnClick", function(self) page.MoveStep(self:GetParent().step, -1) end)
	row.down:SetScript("OnClick", function(self) page.MoveStep(self:GetParent().step, 1) end)
	row.del:SetScript("OnClick", function(self) page.DeleteStep(self:GetParent().step) end)
	return row
end

-- A step's speed over its time, under its settings (rotate, tilt, zoom,
-- spin, aim): its own speed in blue; with Speed match and a turn before it
-- handing straight over, the part it takes over shaded, starting from that
-- turn's speed (the dot), its own speed without it dashed grey.
local GRAPH_H, GRAPH_POINTS, GRAPH_LEFT, GRAPH_BOTTOM = 70, 48, 44, 14
local function MakeGraph(parent)
	local g = CreateFrame("Frame", nil, parent)
	g:SetSize(WIDTH - 28, GRAPH_H)
	local bg = g:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.25)
	local plotW, plotH = WIDTH - 28 - GRAPH_LEFT - 8, GRAPH_H - GRAPH_BOTTOM - 8
	g.plotW, g.plotH = plotW, plotH
	g.band = g:CreateTexture(nil, "BORDER")
	g.band:SetColorTexture(1, 0.82, 0, 0.13)
	local function Line(r, gg, b, a, thick)
		if not g.CreateLine then return nil end
		local line = g:CreateLine(nil, "ARTWORK")
		line:SetThickness(thick)
		line:SetColorTexture(r, gg, b, a)
		return line
	end
	g.Line = Line
	g.axisX, g.axisY = Line(0.35, 0.35, 0.4, 1, 1), Line(0.35, 0.35, 0.4, 1, 1)
	g.edge = Line(1, 0.82, 0, 0.6, 1)
	g.own, g.real = {}, {}
	for i = 1, GRAPH_POINTS do
		g.own[i] = Line(0.55, 0.55, 0.6, 0.7, 1)
		g.real[i] = Line(0.36, 0.55, 0.94, 1, 2)
	end
	g.dot = g:CreateTexture(nil, "OVERLAY")
	g.dot:SetSize(6, 6)
	g.dot:SetColorTexture(1, 0.82, 0, 1)
	-- (The dot's speed beside it: what the turn before ends at, to match.)
	g.dotText = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	g.dotText:SetTextColor(1, 0.82, 0)
	local function Text(justify)
		local text = g:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		text:SetJustifyH(justify)
		return text
	end
	g.top, g.zero, g.secs, g.match = Text("RIGHT"), Text("LEFT"), Text("RIGHT"), Text("CENTER")
	g.top:SetPoint("TOPRIGHT", g, "TOPLEFT", GRAPH_LEFT - 4, -4)
	g.zero:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", GRAPH_LEFT, 2)
	g.zero:SetText(L["0 s"])
	g.secs:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -8, 2)
	g.match:SetTextColor(1, 0.82, 0)
	g.match:SetText(L["Speed match"])
	return g
end
local function PlaceLine(g, line, x1, y1, x2, y2)
	if not line then return end
	line:SetStartPoint("BOTTOMLEFT", g, GRAPH_LEFT + x1, GRAPH_BOTTOM + y1)
	line:SetEndPoint("BOTTOMLEFT", g, GRAPH_LEFT + x2, GRAPH_BOTTOM + y2)
	line:Show()
end
-- Draws speeds (ns.CameraStepSpeeds) with blend seconds of Speed match.
local function DrawGraph(g, speeds, blend)
	local T = speeds.T
	local from = speeds.from
	local match = from and blend > 0 and math.min(T, blend) or 0
	local function Own(t) return speeds.Speed(t) end
	local function Real(t)
		if match > 0 and t < match then
			local u = (1 - math.cos(math.pi * t / match)) / 2
			return from + (Own(t) - from) * u
		end
		return Own(t)
	end
	local most = from or 0
	for i = 0, GRAPH_POINTS do most = math.max(most, Own(T * i / GRAPH_POINTS)) end
	most = math.max(most, 0.1)
	local W, H = g.plotW, g.plotH
	local function X(t) return W * t / T end
	local function Y(v) return H * math.min(1, v / most) end
	PlaceLine(g, g.axisX, 0, 0, W, 0)
	PlaceLine(g, g.axisY, 0, 0, 0, H)
	for i = 1, GRAPH_POINTS do
		local t0, t1 = T * (i - 1) / GRAPH_POINTS, T * i / GRAPH_POINTS
		PlaceLine(g, g.real[i], X(t0), Y(Real(t0)), X(t1), Y(Real(t1)))
		-- (Its own speed, dashed: every other piece, only where Speed match changes it.)
		if match > 0 and t0 < match and i % 2 == 0 then
			PlaceLine(g, g.own[i], X(t0), Y(Own(t0)), X(t1), Y(Own(t1)))
		elseif g.own[i] then
			g.own[i]:Hide()
		end
	end
	g.band:SetShown(match > 0)
	g.match:SetShown(match > 0)
	if g.edge then g.edge:SetShown(match > 0) end
	if match > 0 then
		g.band:ClearAllPoints()
		g.band:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", GRAPH_LEFT, GRAPH_BOTTOM)
		g.band:SetSize(math.max(1, X(match)), H)
		PlaceLine(g, g.edge, X(match), 0, X(match), H)
		g.match:ClearAllPoints()
		g.match:SetPoint("TOP", g, "BOTTOMLEFT", GRAPH_LEFT + X(match) / 2, GRAPH_BOTTOM + H - 2)
	end
	local unit = speeds.axis == "zoom" and L["%s yd/s"] or L["%s°/s"]
	g.dot:SetShown(from ~= nil)
	g.dotText:SetShown(from ~= nil)
	if from then
		g.dot:ClearAllPoints()
		g.dot:SetPoint("CENTER", g, "BOTTOMLEFT", GRAPH_LEFT, GRAPH_BOTTOM + Y(from))
		g.dotText:ClearAllPoints()
		-- (Under it near the top, so it stays inside the graph.)
		if Y(from) > H * 0.6 then
			g.dotText:SetPoint("TOPLEFT", g.dot, "BOTTOMRIGHT", 3, -1)
		else
			g.dotText:SetPoint("BOTTOMLEFT", g.dot, "TOPRIGHT", 3, 1)
		end
		g.dotText:SetText(unit:format(Num(from)))
	end
	g.top:SetText(unit:format(Num(most)))
	g.secs:SetText(L["%s s"]:format(Num(T)))
	g:Show()
end
-- The plan the graph reads from: the page's script, from the preview's start.
local function GraphPlan()
	if not page.script then return nil end
	return ns.PlanCameraScript(page.script,
		{ yaw = 0, pitch = 0, zoom = math.max(2, GetCameraZoom and GetCameraZoom() or 8) })
end
local GRAPH_KINDS = { rotate = true, tilt = true, zoom = true, spin = true, aim = true }

-- Settings that can't do anything as the step is set: hidden, their place
-- left empty. (speeds: ns.CameraStepSpeeds's, for Speed match.)
local function FieldHidden(step, key, speeds)
	if key == "blend" then return not (speeds and speeds.from) end
	local k = step.k
	if k == "zoom" and key == "max" then return step.rand ~= "between" end
	if k == "tilt" and (key == "up" or key == "down") then return step.rand ~= "give" end
	if k == "wait" then
		if key == "rand" then return step.what ~= "time" end
		if key == "max" then return step.what ~= "time" or step.rand ~= "between" end
		if key == "secs" then return step.what == "alive" or step.what == "talk" end
	end
	return false
end
-- A setting's name, where Random changes what it is.
local function FieldLabel(step, key)
	if step.k == "zoom" and key == "to" and step.rand == "between" then return L["Nearest"] end
	if step.k == "tilt" and key == "deg" and step.rand == "give" then return L["Height"] end
	if step.k == "wait" and key == "secs" and step.what == "time" and step.rand == "between" then return L["Shortest"] end
	return nil
end

-- The settings of the step picked, under its row: up to eight fields, two
-- to a row, the speed graph, and a hint. (Speed match: hidden, its place
-- left empty, where no turn hands over to the step: it would do nothing.)
local SLOTS, PER_ROW, SLOT_ROW, SLOT_W = 10, 2, 26, 186
local function MakeEditor(content)
	local editor = CreateFrame("Frame", nil, content)
	editor:SetSize(WIDTH, EDITOR_H)
	local bg = editor:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 0.82, 0, 0.06)
	editor.slots = {}
	for i = 1, SLOTS do
		local slot = {}
		slot.label = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		slot.label:SetPoint("TOPLEFT", 14 + ((i - 1) % PER_ROW) * SLOT_W, -8 - math.floor((i - 1) / PER_ROW) * SLOT_ROW)
		slot.label:SetWidth(70)
		slot.label:SetJustifyH("LEFT")
		slot.box = Box(editor, 54)
		slot.box:SetPoint("LEFT", slot.label, "RIGHT", 6, 0)
		local function Commit(box)
			local step, field = editor.step, slot.field
			if not step or not field then return end
			step[field[1]] = ns.CleanCameraScriptField(field, box:GetText())
			box:SetText(field[2] == "num" and Num(step[field[1]]) or step[field[1]])
			page.Changed()
		end
		slot.box:SetScript("OnEnterPressed", function(self) Commit(self) self:ClearFocus() end)
		slot.box:SetScript("OnEditFocusLost", Commit)
		-- (Seconds and Speed match by half a second, the rest by one.)
		WheelNumber(slot.box, function()
			local field = slot.field
			if not field or field[2] ~= "num" then return nil end
			return (field[1] == "secs" or field[1] == "blend" or field[1] == "max" and editor.step
				and editor.step.k == "wait") and 0.5 or 1
		end)
		-- (A camera to play: every one but this, by name.)
		local function Choices()
			if not slot.field then return {} end
			if slot.field[2] ~= "script" then return slot.field[3] end
			local ids = {}
			for _, script in ipairs(ns.CameraScripts()) do
				if script.id ~= (page.script and page.script.id) then ids[#ids + 1] = script.id end
			end
			return ids
		end
		slot.pick = Choice(editor, 98, Choices,
			function() return editor.step and slot.field and editor.step[slot.field[1]] end,
			function(choice)
				editor.step[slot.field[1]] = choice
				slot.pick:Refresh()
				page.Changed()
			end, function(choice)
				if slot.field and slot.field[2] == "script" then
					local script = ns.FindCameraScript(choice)
					return script and script.name or choice
				end
				return slot.field and CHOICE_NAMES[slot.field[1] .. "." .. choice] or CHOICE_NAMES[choice] or choice
			end)
		slot.pick:SetPoint("LEFT", slot.label, "RIGHT", 6, 0)
		editor.slots[i] = slot
	end
	editor.hint = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	editor.hint:SetPoint("BOTTOMLEFT", 14, 7)
	editor.hint:SetWidth(WIDTH - 24)
	editor.hint:SetJustifyH("LEFT")
	editor.hint:SetWordWrap(true)
	if editor.hint.SetMaxLines then editor.hint:SetMaxLines(3) end
	editor.graph = MakeGraph(editor)

	function editor:Edit(step, locked)
		self.step = step
		if ns.UpgradeCameraScriptStep then ns.UpgradeCameraScriptStep(step) end
		-- (When it ends: no settings of its own, just what it is.)
		local kind = ns.CAMERA_SCRIPT_KINDS[step.k]
		local fields = kind and kind.fields or {}
		local speeds = GRAPH_KINDS[step.k] and not step.off and ns.CameraStepSpeeds
			and ns.CameraStepSpeeds(GraphPlan(), step) or nil
		for i, slot in ipairs(self.slots) do
			local field = not locked and fields[i]
			-- (Speed match with nothing handing over to it: an empty place.)
			local shown = field and not FieldHidden(step, field[1], speeds)
			slot.field = field or nil
			slot.label:SetShown(shown and true or false)
			local picked = field and (field[2] == "pick" or field[2] == "script") or false
			slot.box:SetShown(shown and not picked or false)
			slot.pick:SetShown(shown and picked or false)
			if field and step[field[1]] == nil then step[field[1]] = field[#field] end
			if field then
				slot.label:SetText(FieldLabel(step, field[1]) or FIELD_NAMES[step.k .. "." .. field[1]]
					or FIELD_NAMES[field[1]] or field[1])
				if picked then
					slot.pick:Refresh()
				else
					slot.box:SetText(field[2] == "num" and Num(step[field[1]]) or step[field[1]])
					slot.box:SetCursorPosition(0)
				end
			end
		end
		-- (A built-in camera's step: the settings it's made from, see
		-- page.StepSettings.)
		local settings = page.StepSettings and page.StepSettings(self, locked and step.set or nil) or 0
		self.hint:SetText(settings > 0 and L["Made from these settings. Copy the camera to change the step itself."]
			or step.k == "ending" and L["Runs when the camera ends, whatever ends it (its stop rules say which do). Every camera has it: it can't be removed. Pick it and add steps to put them inside."]
			or locked and L["A built-in camera: Copy it to change it."] or HINTS[step.k] or "")
		local rows = locked and 0 or math.ceil(#fields / PER_ROW)
		local graphH = 0
		if speeds and speeds.T > 0 then
			self.graph:ClearAllPoints()
			self.graph:SetPoint("TOPLEFT", self, "TOPLEFT", 14, -(rows * SLOT_ROW + settings + 6))
			DrawGraph(self.graph, speeds, tonumber(step.blend) or 0)
			graphH = GRAPH_H + 8
		else
			self.graph:Hide()
		end
		self:SetHeight(rows * SLOT_ROW + settings + graphH + math.max(26, self.hint:GetStringHeight() + 14))
	end
	return editor
end

-- A row of the camera list (pooled): a dot for what it is, and its name.
local function ListRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(LIST_W, LIST_ROW)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.07)
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.dot:SetSize(7, 7)
	row.dot:SetPoint("LEFT", 6, 0)
	row.ring = row:CreateTexture(nil, "ARTWORK", nil, 1) -- (a hollow dot: a darker middle over the dot)
	row.ring:SetSize(4, 4)
	row.ring:SetPoint("CENTER", row.dot)
	row.ring:SetColorTexture(0.05, 0.05, 0.07, 1)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 18, 0)
	row.text:SetPoint("RIGHT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row:SetScript("OnClick", function(self)
		page.OpenList(false)
		page.Pick(self.entry)
	end)
	return row
end

-- The camera's name at the top of the page: a dot, its name, its group, and
-- an arrow; a click drops the list down.
local function CameraButton(content)
	local button = ns.PanelButton(content)
	button:SetSize(240, 26) -- (room beside it for Copy, Delete, Share and Run)
	button.dot = button:CreateTexture(nil, "OVERLAY")
	button.dot:SetSize(8, 8)
	button.dot:SetPoint("LEFT", 10, 0)
	button.ring = button:CreateTexture(nil, "OVERLAY", nil, 1)
	button.ring:SetSize(4, 4)
	button.ring:SetPoint("CENTER", button.dot)
	button.ring:SetColorTexture(0.05, 0.05, 0.07, 1)
	button.arrow = button:CreateTexture(nil, "OVERLAY")
	button.arrow:SetSize(14, 14)
	button.arrow:SetPoint("RIGHT", -8, 0)
	button.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	button.group = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	button.group:SetPoint("RIGHT", button.arrow, "LEFT", -6, 0)
	button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.name:SetPoint("LEFT", button.dot, "RIGHT", 8, 0)
	button.name:SetPoint("RIGHT", button.group, "LEFT", -6, 0)
	button.name:SetJustifyH("LEFT")
	button.name:SetWordWrap(false)
	if button.GetFontString and button:GetFontString() then button:GetFontString():SetText("") end
	button:SetScript("OnClick", function() page.OpenList(not page.list:IsShown()) end)
	return button
end

function ns.CreateCameraScriptsPanel(kit)
	local canvas, content = kit.CreateScrollPage(true)
	page.canvas, page.content = canvas, content
	local title = kit.Label(content, "GameFontNormalLarge", L["Scripts"])
	title:SetPoint("TOPLEFT", LEFT, -16)
	kit.PageIntro(content, title, L["Every camera, made of small steps: rotate, tilt, zoom, sway, wait, and Together " ..
		"and Repeat for steps at once or again. Stop rules say what happens when you move the camera, walk, zoom, a " ..
		"fight starts or its trigger ends. The built-in ones are our own cameras' steps, with your settings: set a " ..
		"row on the Scenes page to one to run it instead of the camera, or Copy it to make it yours. " ..
		"A hollow dot: that camera isn't a script yet."])

	-- The camera's name, and the list it drops down: over the page (a dim
	-- layer under it takes a click outside to close it), every camera in two
	-- columns, a box to find one, then yours, New camera and Import.
	page.camButton = CameraButton(content)
	page.camButton:SetPoint("TOPLEFT", LEFT, -46)
	-- (Its tip: what this camera is and what starts it, then how to pick another.)
	page.camButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.name:GetText() or "", 1, 0.82, 0)
		if page.tipStatus then GameTooltip:AddLine(page.tipStatus, 1, 1, 1, true) end
		if page.tipStarts then GameTooltip:AddLine(page.tipStarts, 0.8, 0.8, 0.8, true) end
		GameTooltip:AddLine(L["Every camera, built in and yours: click to pick another."], 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	page.camButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	page.dim = CreateFrame("Button", nil, content)
	page.dim:SetAllPoints(content)
	page.dim:SetFrameLevel(content:GetFrameLevel() + 40)
	local dimArt = page.dim:CreateTexture(nil, "BACKGROUND")
	dimArt:SetAllPoints()
	dimArt:SetColorTexture(0, 0, 0, 0.35)
	page.dim:SetScript("OnClick", function() page.OpenList(false) end)
	page.dim:Hide()
	local list = CreateFrame("Frame", nil, content)
	page.list = list
	list:SetFrameLevel(content:GetFrameLevel() + 45)
	list:SetPoint("TOPLEFT", page.camButton, "BOTTOMLEFT", 0, -4)
	list:SetWidth(10 + LIST_W + 12 + LIST_W + 10)
	list:EnableMouse(true) -- (a click on it isn't a click outside)
	local listBg = list:CreateTexture(nil, "BACKGROUND")
	listBg:SetAllPoints()
	listBg:SetColorTexture(0.06, 0.06, 0.08, 0.97)
	for i, sides in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
		{ "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local edge = list:CreateTexture(nil, "BORDER")
		edge:SetPoint(sides[1])
		edge:SetPoint(sides[2])
		if i <= 2 then edge:SetHeight(1) else edge:SetWidth(1) end
		edge:SetColorTexture(1, 0.82, 0, 0.6)
	end
	page.find = Box(list, 200)
	page.find:SetPoint("TOPLEFT", 15, -10)
	page.find:SetScript("OnTextChanged", function() page.PlaceList() end)
	page.find:SetScript("OnEscapePressed", function() page.OpenList(false) end)
	page.findHint = kit.Label(list, "GameFontDisableSmall", L["Find a camera"])
	page.findHint:SetPoint("LEFT", page.find, "LEFT", 2, 0)
	local close = Button(list, L["Close"], 64)
	close:SetPoint("TOPRIGHT", -10, -8)
	close:SetScript("OnClick", function() page.OpenList(false) end)
	list:Hide()
	page.listRows, page.listHeads = {}, {}
	page.newButton = Button(list, L["+ New camera"], LIST_W)
	page.newButton:SetScript("OnClick", function()
		page.OpenList(false)
		local script = ns.AddCameraScript(nil, L["My camera %d"]:format(#(Store().list or {}) + 1))
		if script then page.Pick(script.id) else ns.Print(L["You have 30 camera scripts already: delete one to add another."]) end
	end)
	kit.Tooltip(page.newButton, L["A new script of yours, with a few steps to start from."])
	page.importButton = Button(list, L["Import"], LIST_W)
	page.importButton:SetScript("OnClick", function()
		page.OpenList(false)
		ShowShare(false)
	end)
	kit.Tooltip(page.importButton, L["Add a script someone shared with you."])

	-- The camera picked: its name, Copy, Delete, Share.
	page.nameLabel = kit.Label(content, "GameFontNormalSmall", L["Name"])
	page.nameLabel:SetPoint("TOPLEFT", COL, -84)
	page.name = Box(content, 200)
	page.name:SetPoint("LEFT", page.nameLabel, "RIGHT", 10, 0)
	page.name:SetMaxLetters(40)
	page.name:SetScript("OnEditFocusLost", function(self)
		local mine = page.script and ns.MyCameraScript(page.script.id)
		local text = self:GetText():gsub("|", ""):match("^%s*(.-)%s*$")
		if mine and text ~= "" then
			mine.name = text
			ns.CameraScriptChanged()
			page.Layout()
			ns.RefreshCameraScriptPreview()
		end
		self:SetText(page.script and page.script.name or "")
	end)
	page.copy = Button(content, L["Copy"], 56)
	page.copy:SetPoint("LEFT", page.camButton, "RIGHT", 8, 0)
	page.copy:SetScript("OnClick", function()
		local script = ns.AddCameraScript(page.script)
		if script then page.Pick(script.id) else ns.Print(L["You have 30 camera scripts already: delete one to add another."]) end
	end)
	kit.Tooltip(page.copy, L["A copy of this script, yours to change."])
	page.delete = Button(content, L["Delete"], 60)
	page.delete:SetPoint("LEFT", page.copy, "RIGHT", 4, 0)
	page.delete:SetScript("OnClick", function()
		if page.confirmDelete == page.id then
			ns.DeleteCameraScript(page.id)
			page.confirmDelete = nil
			page.Pick("cozy")
		else
			page.confirmDelete = page.id
			page.delete:SetText(L["Sure?"])
		end
	end)
	kit.Tooltip(page.delete, L["Deletes this script (click twice). Rows set to it go back to no camera."])
	-- One of ours you changed: back to ours (in Delete's place).
	page.reset = Button(content, L["Reset"], 60)
	page.reset:SetPoint("LEFT", page.copy, "RIGHT", 4, 0)
	page.reset:SetScript("OnClick", function()
		if page.confirmDelete == page.id then
			ns.ResetBuiltinCameraScript(page.id)
			page.confirmDelete = nil
			page.Pick(page.id)
		else
			page.confirmDelete = page.id
			page.reset:SetText(L["Sure?"])
		end
	end)
	kit.Tooltip(page.reset, L["Puts our script back, made from its camera's settings again, in place of your changes (click twice)."])
	-- (After Delete; after Copy for a built-in one, which has no Delete: see Layout.)
	page.share = Button(content, L["Share"], 56)
	page.share:SetScript("OnClick", function() ShowShare(true) end)
	kit.Tooltip(page.share, L["A string of this script to give to friends."])

	-- (What it is and what starts it: the camera button's tip.)
	-- Run, beside Share: moves the real camera through it; Stop while it's
	-- the one running.
	page.runNow = Button(content, L["Run"], 54)
	page.runNow:SetPoint("LEFT", page.share, "RIGHT", 4, 0)
	function page.RunNow()
		local played, why = ns.PlayCameraScript(page.script)
		if not played then ns.Print(why) end
	end
	local function Running()
		local state = ns.CameraScriptState()
		return state and page.script and state.script.id == page.script.id
	end
	-- (Its drawing opens beside the settings, following it.)
	page.runNow:SetScript("OnClick", function()
		if Running() then ns.StopCameraScript() return end
		page.RunNow()
		if Running() then ns.ShowCameraScriptPreview() end
	end)
	local runningWas
	ns.SetOnUpdate(page.runNow, function(self)
		local running = Running() and true or false
		if running ~= runningWas then
			runningWas = running
			self:SetText(running and L["Stop"] or L["Run"])
		end
		-- (The steps it's on lit up.)
		local lit = running and ns.CameraScriptActivePaths() or nil
		local changed = false
		for i = 1, page.used do
			local row = page.rows[i]
			local on = lit and lit[row.path] or nil
			if on ~= row.lit then row.lit, changed = on, true end
		end
		if changed then page.Paint() end
	end)
	kit.Tooltip(page.runNow, L["Moves the real camera through this script now, with a drawing of it beside the settings and its steps lit up as it goes (click again to stop it). Its stop rules count, as for a trigger."])

	-- The lists and rules, laid out by Layout.
	page.rows, page.used = {}, 0
	page.editor = MakeEditor(content)
	page.addBars = {}
	-- (A header over each group, then its buttons four to a row.)
	local ADD_PER_ROW, ADD_W, ADD_ROW, ADD_HEADER = 4, 136, 26, 18
	for _, list in ipairs({ "steps" }) do
		local bar = CreateFrame("Frame", nil, content)
		local y = 0
		for _, group in ipairs(ns.CAMERA_SCRIPT_ADD_GROUPS) do
			local header = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			header:SetPoint("TOPLEFT", 2, y - 3)
			header:SetText(L[ADD_GROUP_NAMES[group.key]])
			y = y - ADD_HEADER
			for i, kind in ipairs(group.kinds) do
				local add = Button(bar, "+ " .. KIND_NAMES[kind], ADD_W - 4)
				add:SetPoint("TOPLEFT", ((i - 1) % ADD_PER_ROW) * ADD_W, y - math.floor((i - 1) / ADD_PER_ROW) * ADD_ROW)
				add:SetScript("OnClick", function() page.AddStep(kind) end)
			end
			y = y - math.ceil(#group.kinds / ADD_PER_ROW) * ADD_ROW - 4
		end
		page.addHeight = -y
		bar:SetSize(WIDTH, page.addHeight)
		page.addBars[list] = bar
	end
	page.ruleRows = {}
	local RULE_X = 30 -- (the rows' names, after the rules' ticks)
	for i, rule in ipairs(ns.CAMERA_SCRIPT_RULES) do
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(WIDTH, 26)
		-- Its tick first: off, the event leaves the camera running.
		row.on = ns.SkinCheck(CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate"))
		row.on:SetSize(24, 24)
		row.on:SetPoint("LEFT", 2, 0)
		row.on:SetScript("OnClick", function(self)
			if page.script then page.SetRule(rule.key .. "On", self:GetChecked() and true or false) end
		end)
		kit.Tooltip(row.on, L["Untick to leave the camera running when this happens. Moving the camera yourself still takes over: it carries on a second after you let go."])
		row.label = kit.Label(row, "GameFontHighlightSmall", RULE_NAMES[rule.key])
		row.label:SetPoint("LEFT", RULE_X, 0)
		row.label:SetWidth(126)
		row.pick = Choice(row, 150, function() return rule.actions end,
			function() return page.script and page.script.rules[rule.key] end,
			function(action)
				page.SetRule(rule.key, action)
			end, function(action) return ACTION_NAMES[action] end)
		row.pick:SetPoint("LEFT", RULE_X + 128, 0)
		if RULE_TIPS[rule.key] then kit.Tooltip(row.pick, RULE_TIPS[rule.key]) end
		row.secsLabel = kit.Label(row, "GameFontHighlightSmall", L["for"])
		row.secsLabel:SetPoint("LEFT", row.pick, "RIGHT", 8, 0)
		row.secs = Box(row, 34)
		row.secs:SetPoint("LEFT", row.secsLabel, "RIGHT", 8, 0)
		row.secsUnit = kit.Label(row, "GameFontHighlightSmall", L["s"])
		row.secsUnit:SetPoint("LEFT", row.secs, "RIGHT", 4, 0)
		local function Commit(box)
			local secs = tonumber(box:GetText())
			if secs and page.script then page.SetRule(rule.key .. "Secs", math.max(1, math.min(60, secs))) end
			box:SetText(page.script and Num(page.script.rules[rule.key .. "Secs"]) or "")
		end
		row.secs:SetScript("OnEditFocusLost", Commit)
		WheelNumber(row.secs, function() return 1 end)
		row.rule = rule
		page.ruleRows[i] = row
	end
	-- Below them, while it runs: its Edge haze (a percent) and a Stop button
	-- (script.haze, script.button).
	page.optHeader = kit.Label(content, "GameFontNormal", L["While it runs"])
	page.optRows = {}
	for i, key in ipairs({ "haze", "button" }) do
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(WIDTH, 26)
		row.key = key
		row.label = kit.Label(row, "GameFontHighlightSmall", key == "haze" and L["Edge haze"] or L["Stop button"])
		row.label:SetPoint("LEFT", RULE_X, 0)
		row.label:SetWidth(126)
		if key == "haze" then
			row.box = Box(row, 40)
			row.box:SetPoint("LEFT", RULE_X + 128, 0)
			row.unit = kit.Label(row, "GameFontHighlightSmall", "%")
			row.unit:SetPoint("LEFT", row.box, "RIGHT", 4, 0)
			local function Commit(box)
				local value = tonumber(box:GetText())
				if value and page.script and not page.locked then
					page.script.haze = math.max(0, math.min(100, value)) / 100
					page.Changed()
				end
				box:SetText(page.script and Num(page.script.haze * 100) or "")
			end
			row.box:SetScript("OnEnterPressed", function(self) Commit(self) self:ClearFocus() end)
			row.box:SetScript("OnEditFocusLost", Commit)
			WheelNumber(row.box, function() return 5 end)
			kit.Tooltip(row.box, L["A soft haze around the edges of the screen while this camera runs, as if it had focused on you. 0 leaves it off. Needs Camera haze on the Visual Effects page, which also turns it up or down."])
		else
			row.pick = Choice(row, 150, function() return { "no", "yes" } end,
				function() return page.script and (page.script.button and "yes" or "no") end,
				function(choice)
					page.script.button = choice == "yes" or nil
					page.Changed()
				end, function(choice) return choice == "yes" and L["Show it"] or L["No button"] end)
			row.pick:SetPoint("LEFT", RULE_X + 128, 0)
			kit.Tooltip(row.pick, L["A Stop camera button on screen while its steps run (under the release popup when you're dead): click it for your own view back, until what started it is over."])
		end
		page.optRows[i] = row
	end

	-- Picks a camera for the page: a script's id, or a list entry (a camera
	-- that isn't a script yet).
	-- Leaving a script Run's playing (another picked, or the page left): it
	-- stops, and its drawing closes. (A trigger's run of it carries on.)
	local function LeaveRun(id)
		local state = ns.CameraScriptState()
		if id and state and not state.trigger and state.script.id == id then ns.StopCameraScript() end
		if preview then preview:Hide() end
	end
	function page.Pick(entry)
		local was = page.script and page.script.id
		page.selected, page.confirmDelete = nil, nil
		page.delete:SetText(L["Delete"])
		page.reset:SetText(L["Reset"])
		if type(entry) == "table" and entry.own then
			page.own, page.id, page.script = entry, nil, nil
		else
			local id = type(entry) == "table" and entry.id or entry
			local script = ns.MyCameraScript(id) or ns.FindCameraScript(id) or ns.FindCameraScript("cozy")
			page.own, page.id, page.script = nil, script.id, script
			-- (Ours change too: the first change keeps yours of it, page.Changed.
			-- Unchanged, its steps show the settings they're made from.)
			page.builtin = script.builtin and true or false
			page.locked = false
			page.hasSettings = script.builtin and not script.edited and ns.CameraScriptSettingKeys(script.id) ~= nil
		end
		if (page.script and page.script.id) ~= was then LeaveRun(was) end
		page.Layout()
		if page.script then ns.RefreshCameraScriptPreview() elseif preview then preview:Hide() end
	end

	-- A stop rule (or its seconds), saved in the script (one of ours: kept as
	-- yours of it, page.Changed).
	function page.SetRule(key, value)
		page.script.rules[key] = value
		page.Changed()
	end

	-- After a change: the page and the preview follow. One of our scripts
	-- changed for the first time: yours of it kept from now on (plain numbers,
	-- not its settings), the step picked still picked in it.
	local function PathTo(list, step, path)
		for i, each in ipairs(list or {}) do
			path[#path + 1] = i
			if each == step or (each.steps and PathTo(each.steps, step, path)) then return path end
			path[#path] = nil
		end
	end
	-- (fromSettings: remade from its settings, not changed: not kept.)
	function page.Changed(fromSettings)
		local script = page.script
		if script and script.builtin and not script.edited and not fromSettings then
			local key = page.selected and (PathTo(script.steps, page.selected, {}) and "steps"
				or PathTo(script.ending, page.selected, {}) and "ending")
			local path = key and PathTo(script[key], page.selected, {})
			page.script = ns.EditBuiltinCameraScript(script)
			page.hasSettings = false
			if path then
				local step = { steps = page.script[key] }
				for _, i in ipairs(path) do step = step and step.steps and step.steps[i] end
				page.selected = step
			end
		end
		page.Layout()
		ns.RefreshCameraScriptPreview()
	end

	-- A built-in camera's settings (its steps' step.set, CameraScripts.lua):
	-- the same switches, sliders and dropdowns as its own page, two to a row.
	-- A change remakes its steps from them (once a frame at most: a slider
	-- drag sends many).
	local VAR_COL, CHECK_ROW, SLIDER_ROW = 284, 28, 44
	-- Where a step is in a script ({ list key, index, index... }), and the
	-- step there in another (remade) one: nil if it isn't made from any of
	-- the same settings as was.
	local function StepPath(script, step)
		local function Find(list, path)
			for i, each in ipairs(list) do
				path[#path + 1] = i
				if each == step or (each.steps and Find(each.steps, path)) then return true end
				path[#path] = nil
			end
		end
		for _, key in ipairs({ "steps", "ending" }) do
			local path = { key }
			if Find(script[key], path) then return path end
		end
	end
	local function StepAt(script, path, was)
		local step = { steps = script[path[1]] }
		for i = 2, #path do
			step = step.steps and step.steps[path[i]]
			if not step then return nil end
		end
		for _, key in ipairs(step.set or {}) do
			for _, old in ipairs(was.set or {}) do
				if key == old then return step end
			end
		end
	end
	local remake, PlaceRuleSettings, HideTabs
	local function SettingChanged()
		if remake then return end
		remake = true
		C_Timer.After(0, function()
			remake = false
			if not (page.id and page.builtin and not page.script.edited and content:IsVisible()) then return end
			local path = page.selected and StepPath(page.script, page.selected)
			page.script = ns.FindCameraScript(page.id)
			page.selected = path and StepAt(page.script, path, page.selected) or nil
			kit.Refresh() -- (greyed settings, and the camera's own page)
			page.Changed(true)
		end)
	end
	-- A setting's control on parent, as its own page has it (Options.lua's
	-- ns.SettingControl), made once for each place (made: a cache of them by
	-- key), placed at x, y. Gives it and its row's height; nil for a setting
	-- with no control.
	local DROP_ROW = 30
	local function SettingAt(made, parent, key, x, y)
		local control = made[key]
		if control == nil then
			control = ns.SettingControl and ns.SettingControl(key, parent, function() SettingChanged() end) or false
			if control and control.settingType == "DropdownButton" then
				-- (Its name before it, as on its own page.)
				control.nameLabel = control:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				control.nameLabel:SetPoint("RIGHT", control, "LEFT", -8, 0)
				control.nameLabel:SetText(control.settingName or "")
			end
			made[key] = control
		end
		if not control then return nil end
		local kind = control.settingType
		control:ClearAllPoints()
		if kind == "CheckButton" then
			control:SetPoint("TOPLEFT", x - 4, y)
		elseif kind == "DropdownButton" then
			control:SetPoint("TOPLEFT", x + (control.nameLabel:GetStringWidth() or 0) + 8, y - 2)
		else
			control:SetPoint("TOPLEFT", x, y - 18)
		end
		if control.Refresh then control:Refresh() end
		control:Show()
		return control, kind == "CheckButton" and CHECK_ROW or kind == "DropdownButton" and DROP_ROW or SLIDER_ROW
	end
	-- The step editor's settings for a built-in step (keys: its step.set, nil
	-- for none): two to a row at its top. Gives their height.
	local stepControls = {}
	function page.StepSettings(editor, keys)
		for _, control in pairs(stepControls) do
			if control then control:Hide() end
		end
		if not keys then return 0 end
		local y, col, rowH = -10, 0, 0
		for _, key in ipairs(keys) do
			local control, height = SettingAt(stepControls, editor, key, 14 + col * VAR_COL, y)
			if control then
				rowH = math.max(rowH, height)
				col = col + 1
				if col == 2 then y, col, rowH = y - rowH, 0, 0 end
			end
		end
		if col > 0 then y = y - rowH end
		return y == -10 and 0 or -y - 4
	end

	-- A built-in camera's stop rule made from settings (keys): them, under
	-- its row at y (nil: all hidden). Gives the y under them.
	local ruleControls = {}
	function PlaceRuleSettings(rule, keys, y)
		if not rule then
			for _, control in pairs(ruleControls) do
				if control then control:Hide() end
			end
			return y
		end
		for _, key in ipairs(keys) do
			local control, height = SettingAt(ruleControls, content, key, COL + 14, y)
			if control then y = y - height end
		end
		return y
	end

	-- The folder tabs: Script (1) and Stop rules (2). page.tab: the one picked.
	local tabsPanel, tabs, ShowTab, tabsBase
	tabsPanel, tabs, ShowTab, tabsBase = ns.FolderTabs(content, {
		{ L["Script"], L["The camera's steps, in order, and what it does when it ends."] },
		{ L["Stop rules"], L["What happens when you move the camera, a fight starts, you walk, you zoom, its trigger ends, a window opens or closes, or its steps run out; and its edge haze and Stop button while it runs."] },
	}, function(i)
		page.tab, page.selected = i, nil
		ShowTab(i)
		page.Layout()
	end)
	tabsBase:SetPoint("TOPLEFT", tabsPanel, "TOPLEFT")
	page.tab = 1
	function HideTabs()
		tabsPanel:Hide()
		for _, tab in ipairs(tabs) do tab:Hide() end
	end
	HideTabs()

	-- After the step picked (inside it, for Together, Repeat and When it
	-- ends), or at the end of the steps.
	function page.AddStep(kind)
		local script = page.script
		if page.locked or not script then return end
		if CountSteps(script.steps) + CountSteps(script.ending) >= 80 then
			ns.Print(L["A script holds 80 steps at most."])
			return
		end
		local step = ns.NewCameraScriptStep(kind)
		local sel = page.selected
		local list, at
		if sel then list, at = FindStep(script.steps, sel) end
		if sel and not list then list, at = FindStep(script.ending, sel) end
		local into = sel and sel.steps
			and not (sel.k == "wait" and sel.what == "time" and #sel.steps == 0)
		if into and (list or sel.k == "ending") then
			table.insert(sel.steps, step)
		elseif list then
			table.insert(list, at + 1, step)
		else
			table.insert(script.steps, step)
		end
		page.selected = step
		page.Changed()
	end

	function page.MoveStep(step, by)
		local script = page.script
		local list, at = FindStep(script.steps, step)
		if not list then list, at = FindStep(script.ending, step) end
		if not list or not list[at + by] then return end
		list[at], list[at + by] = list[at + by], list[at]
		page.Changed()
	end

	function page.DeleteStep(step)
		local script = page.script
		local list, at = FindStep(script.steps, step)
		if not list then list, at = FindStep(script.ending, step) end
		if not list then return end
		table.remove(list, at)
		if page.selected == step then page.selected = nil end
		page.Changed()
	end

	-- Colours the rows: the steps Run's on (row.lit), and the one picked.
	function page.Paint()
		for i = 1, page.used do
			local row = page.rows[i]
			if row.lit then
				row.bg:SetColorTexture(1, 0.82, 0, 0.16)
			elseif row.step == page.selected then
				row.bg:SetColorTexture(1, 0.82, 0, 0.1)
			else
				row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.0)
			end
		end
	end

	-- The list, in its panel: At rest and Travel, then Moments and Yours (New
	-- camera and Import under them); what's typed in the box narrows it.
	function page.PlaceList()
		local find = page.find:GetText():lower():match("^%s*(.-)%s*$")
		page.findHint:SetShown(find == "")
		local used, heads = 0, 0
		local x, y, lowest = 10, -40, -40
		local function Row(entry, name, kind)
			if find ~= "" and not name:lower():find(find, 1, true) then return end
			used = used + 1
			local row = page.listRows[used]
			if not row then
				row = ListRow(list)
				page.listRows[used] = row
			end
			row:SetWidth(LIST_W)
			row.entry = entry
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", x, y)
			row.text:SetText(name)
			local c = DOT[kind]
			row.dot:SetColorTexture(c[1], c[2], c[3], 1)
			row.ring:SetShown(kind == "own")
			local picked = (page.own and entry == page.own) or (not page.own and type(entry) ~= "table" and entry == page.id)
				or (not page.own and type(entry) == "table" and entry.id == page.id)
			row.bg:SetColorTexture(1, 0.82, 0, picked and 0.16 or 0)
			row:Show()
			y = y - LIST_ROW
		end
		for index, group in ipairs(CAMERA_LIST) do
			if index == 3 then
				lowest = math.min(lowest, y)
				x, y = 10 + LIST_W + 12, -40
			end
			heads = heads + 1
			local head = page.listHeads[heads]
			if not head then
				head = kit.Label(list, "GameFontNormalSmall", "")
				page.listHeads[heads] = head
			end
			head:ClearAllPoints()
			head:SetPoint("TOPLEFT", x + 4, y - 4)
			head:SetText(group.section)
			head:SetTextColor(group.color[1], group.color[2], group.color[3])
			y = y - 20
			if group.mine then
				for _, script in ipairs(Store().list or {}) do
					if type(script) == "table" and script.id then Row(script.id, script.name, "mine") end
				end
			else
				for _, item in ipairs(group.items) do
					if type(item) == "table" and item.own then
						local name = item.name and L[item.name] or ns.CAMERA_NAMES[item.own] or tostring(item.own)
						Row(item, name, "own")
					else
						local script = ns.FindCameraScript(type(item) == "table" and item.id or item)
						if script then Row(item, script.name, "script") end
					end
				end
			end
		end
		for i = used + 1, #page.listRows do page.listRows[i]:Hide() end
		page.newButton:ClearAllPoints()
		page.newButton:SetPoint("TOPLEFT", x, y - 6)
		page.importButton:ClearAllPoints()
		page.importButton:SetPoint("TOPLEFT", x, y - 32)
		lowest = math.min(lowest, y - 56)
		list:SetHeight(-lowest + 10)
	end

	-- Opens or closes the list (opening, the page scrolls to its top, where
	-- the camera's name is).
	function page.OpenList(open)
		if open then
			if canvas.scroll then canvas.scroll:SetVerticalScroll(0) end
			page.find:SetText("")
			page.PlaceList()
			page.dim:Show()
			list:Show()
		else
			page.find:ClearFocus()
			page.dim:Hide()
			list:Hide()
		end
		page.camButton.arrow:SetTexture(open and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up")
	end

	-- A list of steps, placed down the script's column.
	-- (off: inside a step switched off, greyed too.)
	-- (prefix: the list's place, for its rows' paths, "2.1": the steps a
	-- running script is on light up by them.)
	local function PlaceRows(list, depth, y, off, prefix)
		for i, step in ipairs(list) do
			local at = prefix == "" and tostring(i) or (prefix .. "." .. i)
			page.used = page.used + 1
			local row = page.rows[page.used]
			if not row then
				row = StepRow(content)
				page.rows[page.used] = row
			end
			row.step, row.path = step, at
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", COL, y)
			local c = COLORS[KIND_COLOR[step.k]] or COLORS.wait
			row.strip:ClearAllPoints()
			row.strip:SetPoint("LEFT", 4 + depth * INDENT, 0)
			row.strip:SetColorTexture(c[1], c[2], c[3], 1)
			row.text:ClearAllPoints()
			row.text:SetPoint("LEFT", 12 + depth * INDENT, 0)
			row.text:SetPoint("RIGHT", (page.locked or step.k == "ending") and -4 or -72, 0)
			-- (A built-in part switched off: greyed, "Off:" before it; its own
			-- switch is in its settings, a click away.)
			local greyed = off or step.off
			row.text:SetText(step.off and L["Off: %s"]:format(StepText(step)) or StepText(step))
			local shade = greyed and 0.5 or 1
			row.text:SetTextColor(shade, shade, shade)
			row.text:SetVertexColor(shade, shade, shade) -- (one on Forever)
			-- (No arrow the way it can't go: up for the first in its list, down for the last.)
			-- (When it ends: always last, and always there.)
			local fixed = page.locked or step.k == "ending"
			row.up:SetShown(not fixed and i > 1)
			row.down:SetShown(not fixed and i < #list)
			row.del:SetShown(not fixed)
			row:Show()
			y = y - ROW_H
			if step == page.selected then
				page.editor:ClearAllPoints()
				page.editor:SetPoint("TOPLEFT", COL, y)
				page.editor:Edit(step, page.locked)
				page.editor:Show()
				page.editorShown = true
				y = y - page.editor:GetHeight() - 2
			end
			if step.steps then y = PlaceRows(step.steps, depth + 1, y, greyed, at) end
		end
		return y
	end

	-- The camera button: its name, dot, and the group it's in.
	function page.SetCameraButton(name, kind)
		local button = page.camButton
		button.name:SetText(name)
		local c = DOT[kind]
		button.dot:SetColorTexture(c[1], c[2], c[3], 1)
		button.ring:SetShown(kind == "own")
		local group = ""
		for _, each in ipairs(CAMERA_LIST) do
			if each.mine and kind == "mine" then group = each.section end
			for _, item in ipairs(each.items or {}) do
				if item == page.own or item == page.id or (type(item) == "table" and item.id and item.id == page.id) then
					group = each.section
				end
			end
		end
		button.group:SetText(group)
	end

	function page.Layout()
		local script = page.script
		local scriptShown = script ~= nil
		for _, widget in ipairs({ page.copy, page.share, page.runNow }) do
			if widget then widget:SetShown(scriptShown) end
		end
		page.used, page.editorShown = 0, false
		local y
		if not script then
			-- A camera that isn't a script yet: its name and what it waits for.
			page.name:Hide()
			page.nameLabel:Hide()
			page.delete:Hide()
			page.reset:Hide()
			page.SetCameraButton(page.own.name and L[page.own.name] or ns.CAMERA_NAMES[page.own.own] or "", "own")
			page.tipStatus = L["Not a script yet: it runs on its own code. Laying it out as steps needs %s, steps the runner doesn't have yet."]:format(
				L[page.own.needs])
			page.tipStarts = nil
			for _, bar in pairs(page.addBars) do bar:Hide() end
			for _, row in ipairs(page.ruleRows) do row:Hide() end
			for _, row in ipairs(page.optRows) do row:Hide() end
			page.optHeader:Hide()
			PlaceRuleSettings(nil)
			HideTabs()
			y = -84
		else
			-- (Ours: its name stays ours, Reset in Delete's place once changed.)
			page.name:SetShown(not page.builtin)
			page.nameLabel:SetShown(not page.builtin)
			if not page.name:HasFocus() then page.name:SetText(script.name) end
			page.SetCameraButton(script.name, not page.builtin and "mine" or "script")
			local top = page.builtin and -84 or -112
			page.delete:SetShown(not page.builtin)
			page.reset:SetShown(page.builtin and script.edited or false)
			page.share:ClearAllPoints()
			page.share:SetPoint("LEFT", not page.builtin and page.delete or script.edited and page.reset or page.copy,
				"RIGHT", 4, 0)
			page.tipStatus = not page.builtin and L["Yours: change anything."]
				or script.edited and L["Built in, changed by you: change anything, and the camera plays your version. Reset puts ours back."]
				or L["Built in, from your settings: this is what the camera plays. Change anything, and it's kept as yours of it (Reset puts ours back)."]
			y = top + 4
			local keys = ns.CameraScriptTriggers(script.id)
			local names = {}
			for _, key in ipairs(keys) do names[#names + 1] = ns.CameraTriggerName(key) end
			page.tipStarts = #names > 0 and L["Starts when: %s"]:format(table.concat(names, ", "))
				or L["Starts when: no trigger yet. Set a row on the Scenes page to it."]
			-- The tabs: Script (its steps, When it ends last) and Stop rules.
			for _, tab in ipairs(tabs) do tab:Show() end
			tabsPanel:Show()
			y = y - ns.FOLDER_TAB_HEIGHT - 4
			tabsPanel:ClearAllPoints()
			tabsPanel:SetPoint("TOPLEFT", COL - 8, y)
			tabsPanel:SetWidth(WIDTH + 16)
			ShowTab(page.tab)
			local panelTop = y
			y = y - 12
			local onScript = page.tab == 1
			PlaceRuleSettings(nil)
			if onScript then
				-- (One When it ends row for the script, kept while it's the same
				-- script, so it stays picked.)
				if page.endFor ~= script.ending then
					local was = page.endStep
					page.endFor, page.endStep = script.ending, { k = "ending", steps = script.ending }
					if page.selected == was and was then page.selected = page.endStep end
				end
				y = PlaceRows(script.steps, 0, y, nil, "")
				y = PlaceRows({ page.endStep }, 0, y, nil, "e")
				local bar = page.addBars.steps
				bar:SetShown(not page.locked)
				if not page.locked then
					bar:SetPoint("TOPLEFT", COL, y - 6)
					y = y - 6 - page.addHeight
				end
				for _, row in ipairs(page.ruleRows) do row:Hide() end
				for _, row in ipairs(page.optRows) do row:Hide() end
				page.optHeader:Hide()
			else
				page.addBars.steps:Hide()
				-- A dropdown each (a built-in camera's too: kept beside it, for
				-- when its script runs). A rule made from a setting: its slider
				-- under the row while it pauses.
				for _, row in ipairs(page.ruleRows) do
					local key = row.rule.key
					row:Show()
					row:SetPoint("TOPLEFT", COL, y)
					local on = script.rules[key .. "On"] ~= false
					row.on:SetChecked(on)
					row.pick:Refresh()
					if row.pick.SetEnabled then row.pick:SetEnabled(on) end
					row.pick:SetAlpha(on and 1 or 0.6) -- (greyed whatever the dropdown's look)
					local pause = on and script.rules[key] == "pause"
					local set = pause and page.hasSettings and script.ruleSet and script.ruleSet[key]
					local showSecs = pause and not set and not row.rule.noSecs
					row.secsLabel:SetShown(showSecs)
					row.secs:SetShown(showSecs)
					row.secsUnit:SetShown(showSecs)
					if showSecs then
						row.secs:SetEnabled(true)
						if not row.secs:HasFocus() then row.secs:SetText(Num(script.rules[key .. "Secs"])) end
					end
					y = y - 26
					if set then y = PlaceRuleSettings(key, set, y) end
				end
				-- While it runs: the haze and the Stop button (a built-in
				-- camera's made from settings: those instead).
				page.optHeader:Show()
				page.optHeader:SetPoint("TOPLEFT", COL + 8, y - 12)
				y = y - 34
				for _, row in ipairs(page.optRows) do
					local set = page.hasSettings and script.ruleSet and script.ruleSet[row.key]
					row:Show()
					row:SetPoint("TOPLEFT", COL, y)
					local control = row.box or row.pick
					control:SetShown(not set)
					if row.unit then row.unit:SetShown(not set) end
					if not set then
						if row.box then
							row.box:SetEnabled(not page.locked)
							if not row.box:HasFocus() then row.box:SetText(Num(script.haze * 100)) end
						else
							row.pick:Refresh()
							if row.pick.SetEnabled then row.pick:SetEnabled(not page.locked) end
							row.pick:SetAlpha(page.locked and 0.6 or 1)
						end
					end
					y = y - 26
					if set then y = PlaceRuleSettings(row.key, set, y) end
				end
			end
			tabsPanel:SetHeight(panelTop - y + 8)
			y = y - 14
		end
		for i = page.used + 1, #page.rows do page.rows[i]:Hide() end
		if not page.editorShown then page.editor:Hide() end
		page.Paint()
		content:SetHeight(-y + 30)
	end

	-- (Leaving the page, its section or the settings: Run stops too.)
	canvas:HookScript("OnHide", function()
		page.OpenList(false)
		LeaveRun(page.script and page.script.id)
	end)
	canvas:SetScript("OnShow", kit.PageShown(function()
		if not page.script and not page.own then page.Pick("cozy") elseif page.own then page.Pick(page.own)
		else page.Pick(page.id) end
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Camera Scripts", L["Scripts"])
end

-- For the General page's camera tabs (CameraManager.lua): this page shown
-- with a script picked, and a script's steps in a line (its top-level ones;
-- a Repeat's or Together's in brackets).
function ns.ShowCameraScript(id)
	ns.ShowHubPage("Camera Scripts")
	if page.Pick then page.Pick(id) end
end
function ns.CameraScriptSummary(script)
	local function Names(list)
		local names = {}
		for _, step in ipairs(list or {}) do
			local name = KIND_NAMES[step.k] or step.k
			if step.steps and #step.steps > 0 and (step.k == "repeat" or step.k == "together") then
				name = name .. " (" .. Names(step.steps) .. ")"
			end
			names[#names + 1] = name
		end
		return table.concat(names, ", ")
	end
	return Names(script.steps)
end
