-- /cine debug cursortest: one run checking Cursor Hide's Replace cursor icon
-- (2026-11-19): ours over open ground and the UI, the game's own over things
-- with one (a mailbox, an NPC, an enemy). It sets itself up (the page on,
-- its warning accepted, Replace on with the fishing hook, CineMode off),
-- runs the cursor name probe (/cine debug cursorsize names), then shows each
-- step in a lasting box, waits as long as it takes for the mouse to be over
-- the right thing, and asks Yes / No on screen. Every change of state is
-- logged ("cursortest"), with each step's flips between ours and the game's.
-- Yours all back at the end, and a DONE box. Run again to stop early.
local _, ns = ...

local PICK = { "Interface\\Cursor\\Crosshair\\Fishing", "Interface\\Cursor\\Fishing", "Interface\\Cursor\\Attack" }
local HOLD = 0.6 -- seconds the mouse must stay over the right thing before the question

-- name, what to do, the state wanted, the question
local STEPS = {
	{ "open ground", "Move the mouse over open ground: nothing with a name under it.",
		function(where) return where == "world" end, "Is your cursor the fishing hook (your pick)?" },
	{ "still", "Keep the mouse STILL over open ground and watch the cursor for a few seconds.",
		function(where) return where == "world" end,
		"Did it stay the fishing hook the whole time, with NO flashing?", 4 },
	{ "object", "Move the mouse over a mailbox, or any object that shows a name (a chair, a herb, a door).",
		function(where, game) return where == "game's" and game == "object" end,
		"Is your cursor the game's own for it now (NOT the fishing hook)?" },
	{ "npc", "Move the mouse over an NPC or an enemy.",
		function(where, game) return where == "game's" and game == "unit" end,
		"Is your cursor the game's own for it now (NOT the fishing hook)?" },
	{ "ui", "Move the mouse over an action bar button.",
		function(where) return where == "ui" end, "Is your cursor the fishing hook (your pick)?" },
}

local runner, box
local saved, cineWasOn
local function Log(text) ns.Log("cursortest", text) end

local function PutBack()
	if not saved then return end
	local db = ns.GetDB()
	db.cursorHide, db.cursorReplaceIcon, db.cursorHideIcon = saved.hide, saved.replace, saved.icon
	db.cursorReplaceGameCursors = saved.gameCursors
	CinematicDB.cursorHideAccepted = saved.accepted
	saved = nil
	ns.cursorPickMethod = nil
	if ns.ApplyCursorHide then ns.ApplyCursorHide() end
	if cineWasOn and ns.IsCineModeOn and not ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		Cinematic_ToggleCineMode()
	end
	cineWasOn = nil
end

local function Stop(why)
	if runner then ns.SetOnUpdate(runner, nil) end
	if box then box:Hide() end
	Log("stopped: " .. why)
	PutBack()
end

-- Yes / No (and Skip) under the prompt.
local function Buttons(onAnswer)
	if not box then
		box = CreateFrame("Frame", nil, UIParent)
		box:SetSize(420, 50)
		box:SetPoint("CENTER", 0, -40)
		box:SetFrameStrata("FULLSCREEN_DIALOG")
		box.buttons = {}
		for i, label in ipairs({ "Yes", "No", "Skip" }) do
			local b = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
			b:SetSize(120, 40)
			b:SetPoint("LEFT", (i - 1) * 140, 0)
			b:SetText(label)
			b:SetScript("OnClick", function() if box.onAnswer then box.onAnswer(label) end end)
			box.buttons[i] = b
		end
	end
	box.onAnswer = onAnswer
	box:Show()
end

local function Finish(results)
	Stop("done")
	local lines = {}
	for _, r in ipairs(results) do lines[#lines + 1] = r end
	Log("RESULTS: " .. table.concat(lines, "; "))
	ns.TestPrompt("CURSOR TEST DONE. Your settings are back.\n\nNow /reload, then tell Claude 'check log'.", 3600)
end

-- (Setup both tests share: the page on, Replace on with the fishing hook,
-- CineMode off. Yours kept for PutBack.)
local function Setup()
	local db = ns.GetDB()
	saved = { hide = db.cursorHide, replace = db.cursorReplaceIcon, icon = db.cursorHideIcon,
		gameCursors = db.cursorReplaceGameCursors,
		accepted = CinematicDB.cursorHideAccepted }
	if ns.IsCineModeOn and ns.IsCineModeOn() and Cinematic_ToggleCineMode then
		cineWasOn = true
		Cinematic_ToggleCineMode()
	end
	local pick
	for _, path in ipairs(PICK) do
		if GetFileIDFromPath == nil or GetFileIDFromPath(path) then pick = path break end
	end
	db.cursorHide, db.cursorReplaceIcon, db.cursorHideIcon = true, true, pick or PICK[3]
	db.cursorReplaceGameCursors = true -- (the test checks the game's cursor over things)
	CinematicDB.cursorHideAccepted = true
	if ns.ApplyCursorHide then ns.ApplyCursorHide() end
end

-- /cine debug cursortest methods: what the flashing is, in one run. Our
-- way of seeing what's under the mouse steps our cover aside, and the game
-- shows its pointer while it's aside (the logs: every flash is a look). This
-- tries the other ways, each for two questions: does it flash as you move
-- over open ground, and does the game's own cursor show over an NPC.
--   cover: ours always, never looking (no flash expected, no NPC cursor)
--   nocover: no cover, ours set every frame (the game may put its own back)
--   propagate: the cover passes the mouse's movement on to the world
local METHOD_STEPS = {
	{ "cover", "flash" }, { "nocover", "flash" }, { "nocover", "npc" }, { "propagate", "flash" }, { "propagate", "npc" },
}
local MOVE_FOR = 4 -- seconds of moving the mouse over open ground before the question
function ns.CursorMethodTest()
	if saved then
		Stop("run again")
		ns.TestPrompt("Cursor test stopped. Your settings are back.", 5)
		return
	end
	Setup()
	local pc = CreateFrame("Frame")
	Log(("methods start: client %s, SetPropagateMouseMotion %s, pick %s"):format(ns.isRetail and "retail" or "forever",
		type(pc.SetPropagateMouseMotion), tostring(ns.GetDB().cursorHideIcon)))
	runner = runner or CreateFrame("Frame")
	local step, results = 1, {}
	local moved, asking, lastKey, lastX, lastY, lastMoveAt = 0, false, nil, nil, nil, 0
	local lastT
	local function Begin()
		local method, kind = METHOD_STEPS[step][1], METHOD_STEPS[step][2]
		ns.cursorPickMethod = method
		moved, asking, lastT = 0, false, nil
		if box then box:Hide() end
		Log(("method step %d: %s %s"):format(step, method, kind))
		if kind == "flash" then
			ns.TestPrompt(("CURSOR TEST, part %d of %d:\n\nMove the mouse around over open ground and watch the "
				.. "fishing hook. (It asks in a few seconds.)"):format(step, #METHOD_STEPS), 3600)
		else
			asking = true -- (its Yes / No: Answer puts them up)
			ns.TestPrompt(("CURSOR TEST, part %d of %d:\n\nPut the mouse on an NPC and leave it there.\n\nIs the "
				.. "cursor the game's own (speech bubble or sword) while on it? Then click Yes or No."):format(step,
				#METHOD_STEPS), 3600)
		end
	end
	local function Answer(label)
		local method, kind = METHOD_STEPS[step][1], METHOD_STEPS[step][2]
		local text = kind == "flash" and ("flashes " .. (label == "Yes" and "YES" or label == "No" and "no" or "skip"))
			or ("game's cursor on NPC " .. (label == "Yes" and "YES" or label == "No" and "no" or "skip"))
		results[#results + 1] = method .. ": " .. text
		Log(("method step %d (%s %s): %s"):format(step, method, kind, text))
		step = step + 1
		if step > #METHOD_STEPS then Finish(results) return end
		Begin()
		if asking then Buttons(Answer) end
	end
	ns.SetOnUpdate(runner, function()
		local now = GetTime()
		local ok, where, game, under, cover, focus = pcall(ns.CursorReplaceState)
		if not ok then Stop("state error: " .. tostring(where)) return end
		local key = ("where=%s game=%s under=%s mouseover=%s cover=%s focus=%s"):format(where, tostring(game),
			tostring(under), tostring(UnitExists("mouseover")), tostring(cover), tostring(focus))
		if key ~= lastKey then
			Log(("method step %d (%s): %s"):format(step, tostring(ns.cursorPickMethod), key))
			lastKey = key
		end
		if asking then return end
		local x, y = GetCursorPosition()
		if lastX and (math.abs(x - lastX) > 2 or math.abs(y - lastY) > 2) then lastMoveAt = now end
		lastX, lastY = x, y
		if lastT and where ~= "ui" and now - lastMoveAt < 0.3 then moved = moved + (now - lastT) end
		lastT = now
		if moved >= MOVE_FOR then
			asking = true
			ns.TestPrompt(("CURSOR TEST, part %d of %d:\n\nDid the fishing hook flash (the normal pointer for a "
				.. "moment) while you moved? Then click Yes or No."):format(step, #METHOD_STEPS), 3600)
			Buttons(Answer)
		end
	end)
	Begin()
end

function ns.CursorReplaceTest()
	if saved then
		Stop("run again")
		ns.TestPrompt("Cursor test stopped. Your settings are back.", 5)
		return
	end
	Setup() -- (the fishing hook: easy to tell from the game's own)
	local db = ns.GetDB()
	Log(("start: client %s, pick %s, GetFileIDFromPath %s, GetMouseFoci %s"):format(ns.isRetail and "retail" or "forever",
		tostring(db.cursorHideIcon), type(GetFileIDFromPath), type(GetMouseFoci)))
	-- (the cursor names this client has that the picker doesn't list: in the log)
	if ns.CursorSizeTest then pcall(ns.CursorSizeTest, "names") end

	runner = runner or CreateFrame("Frame")
	local step, results = 1, {}
	local heldSince, asking, flips, lastGame, lastKey
	local function Begin()
		local s = STEPS[step]
		heldSince, asking, flips, lastGame = nil, false, 0, nil
		if box then box:Hide() end
		Log(("step %d (%s): waiting"):format(step, s[1]))
		ns.TestPrompt(("CURSOR TEST, step %d of %d:\n\n%s\n\n(It waits as long as you need.)"):format(step, #STEPS, s[2]),
			3600)
	end
	local function Answer(label)
		local s = STEPS[step]
		local verdict = label == "Skip" and "SKIP" or ((label == "Yes") and "PASS" or "FAIL")
		results[#results + 1] = ("%s %s (flips %d)"):format(s[1], verdict, flips)
		Log(("step %d (%s): answer %s -> %s, flips between ours and the game's: %d"):format(step, s[1], label,
			verdict, flips))
		step = step + 1
		if step > #STEPS then Finish(results) return end
		Begin()
	end
	ns.SetOnUpdate(runner, function()
		local now = GetTime()
		local ok, where, game, under, cover, focus, probeWhy = pcall(ns.CursorReplaceState)
		if not ok then Stop("state error: " .. tostring(where)) return end
		if game ~= lastGame then
			if not asking then flips = flips + 1 end -- (moving to the buttons doesn't count)
			lastGame = game
		end
		local key = ("where=%s game=%s under=%s cover=%s focus=%s"):format(where, tostring(game), tostring(under),
			tostring(cover), tostring(focus))
			.. (cover == false and (" lookedBecause=" .. tostring(probeWhy)) or "")
		if key ~= lastKey then
			Log(("step %d: %s"):format(step, key))
			lastKey = key
		end
		if asking then return end
		local s = STEPS[step]
		if s[3](where, game) then
			heldSince = heldSince or now
			if now - heldSince >= (s[5] or HOLD) then
				asking = true
				Log(("step %d (%s): reached, asking"):format(step, s[1]))
				ns.TestPrompt(("CURSOR TEST, step %d of %d:\n\n%s\n\nKeep the mouse there, look, then click Yes or No.")
					:format(step, #STEPS, s[4]), 3600)
				Buttons(Answer)
			end
		elseif not asking then
			heldSince = nil
		end
	end)
	Begin()
end
