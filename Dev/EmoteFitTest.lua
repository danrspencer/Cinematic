-- /cine debug emotefit: one run checking that Emote Vision's buttons fit their
-- names in every card style (a "You're welcome" ran past its button's edges,
-- 2026-11-19). Nothing to do but watch: each style (Classic, Parchment letter,
-- Speech bubble, Subtitle, Banner, Wheel) at text size 100% and 150%, with
-- three short emotes and with six long ones, a card each; for every card it
-- logs, per button, its name's width against the button's, whether the game
-- cut the name short, whether the button is out past the card's edge (the
-- wheel's may be, round its disc) and whether it covers another button (or
-- the wheel's face), with its own verdict, and takes a screenshot (named in the
-- log). Nothing saved is changed: the style and size are only pretended while
-- it runs. Into CinematicDB.emoteFitLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local LOOKS = { "classic", "parchment", "bubble", "subtitle", "banner", "wheel" }
local SIZES = { 1, 1.5 }
-- (The thank card's own three, and six of the longest names.)
local SETS = {
	{ "YW", "BOW", "SMILE" },
	{ "YW", "CONGRATULATE", "HIGHFIVE", "APPLAUD", "CURTSEY", "WELCOME" },
}
local SHOW_AT, NEXT_AT = 1.2, 2.2 -- seconds into each card: its screenshot (faded in by then), the next card
local SLACK = 1 -- pixels a measure may be off by

local run -- { at, cases, index, problems, oldOpt, oldLook }

local function Say(text)
	local log = CinematicDB and CinematicDB.emoteFitLog
	if log then log[#log + 1] = ("%.1f %s"):format(run and GetTime() - run.at or 0, text) end
end

local function Rect(region)
	local left, right, top, bottom = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
	if not (left and right and top and bottom) then return nil end
	return { left = left, right = right, top = top, bottom = bottom }
end
local function Overlap(a, b)
	return a and b and math.min(a.right, b.right) - math.max(a.left, b.left) > SLACK
		and math.min(a.top, b.top) - math.max(a.bottom, b.bottom) > SLACK
end

-- The card's shown buttons: each with its name's text, the font string.
local function Buttons(card)
	local list = {}
	for _, group in ipairs({ card.buttons or {}, card.words or {} }) do
		for _, button in ipairs(group) do
			if button:IsShown() then
				local text = button.text or (button.GetFontString and button:GetFontString())
				if text then list[#list + 1] = { button = button, text = text } end
			end
		end
	end
	return list
end

-- One card measured: a line per button, and its problems counted.
local function Measure(case, card)
	local problems = 0
	local look = case.look
	-- (Where the buttons should stay: the panel the card draws, the bubble's
	-- starting past the face that sits outside it.)
	local area = Rect(look == "bubble" and card.bubble or card)
	local list = Buttons(card)
	local face = look == "wheel" and card.portrait and card.portrait:IsShown() and Rect(card.portrait)
	if #list ~= #case.emotes then
		Say(("  %d buttons shown for %d emotes (one this client hasn't?)"):format(#list, #case.emotes))
	end
	for i, each in ipairs(list) do
		local box, text = each.button, each.text
		local wide, need = box:GetWidth(), text:GetStringWidth()
		local cut = text.IsTruncated and text:IsTruncated() or false
		local word = text:GetText() or "?"
		-- (Room each side: a panel's or tab's edge; a bare word needs none.)
		local pad = (box.edges or box.back) and 4 or 0
		if box.GetFontString and box:GetFontString() == text then pad = 6 end
		local bad = {}
		if need > wide - pad * 2 + SLACK then bad[#bad + 1] = ("name %.0f wider than its room %.0f"):format(need, wide - pad * 2) end
		if cut then bad[#bad + 1] = "name cut short" end
		local rect = Rect(box)
		if look ~= "wheel" and rect and area and (rect.left < area.left - SLACK or rect.right > area.right + SLACK
			or rect.bottom < area.bottom - SLACK) then
			bad[#bad + 1] = ("out past the card (%.0f..%.0f, card %.0f..%.0f)"):format(rect.left, rect.right,
				area.left, area.right)
		end
		for j = i + 1, #list do
			if Overlap(rect, Rect(list[j].button)) then
				bad[#bad + 1] = "covers " .. (list[j].text:GetText() or "?")
			end
		end
		-- (The face is round, in its ring: the button's nearest point to its
		-- middle inside the ring's circle.)
		if face and rect then
			local cx, cy = (face.left + face.right) / 2, (face.top + face.bottom) / 2
			local radius = (face.right - face.left) / 2 + 2
			local nx = math.max(rect.left - cx, 0, cx - rect.right)
			local ny = math.max(rect.bottom - cy, 0, cy - rect.top)
			if nx * nx + ny * ny < (radius - SLACK) ^ 2 then bad[#bad + 1] = "covers the face" end
		end
		problems = problems + #bad
		Say(("  %s: %s (button %.0f, name %.0f)%s"):format(#bad > 0 and "BAD" or "ok", word, wide, need,
			#bad > 0 and (" - " .. table.concat(bad, "; ")) or ""))
	end
	-- (The name over the buttons: cut short with "..." when long; a note, not
	-- counted.)
	if card.name and card.name.IsTruncated and card.name:IsTruncated() then
		Say(("  note: the name \"%s\" is cut short (%.0f wide, %.0f room)"):format(card.name:GetText() or "?",
			card.name.GetUnboundedStringWidth and card.name:GetUnboundedStringWidth() or 0, card.name:GetWidth()))
	end
	return problems
end

local function PutBack()
	if not run then return end
	ns.EmoteOpt, ns.StyleLook = run.oldOpt, run.oldLook
	if ns.HideEmoteCard then ns.HideEmoteCard() end
end

local function Finish(stopped)
	local problems, count = run.problems, #run.cases
	Say(("%s: %d cards, %d problems"):format(stopped and "STOPPED" or "DONE", run.index, problems))
	PutBack()
	if run.ticker then run.ticker:Cancel() end
	run = nil
	ns.PadTestBox(("Emote button test %s: %d cards, %d problems."):format(stopped and "stopped" or "done",
		count, problems), "/reload, then say \"check log\".", problems > 0 and 1 or 0.3, problems > 0 and 0.3 or 1, 0.3)
	C_Timer.After(12, function() if not run then ns.PadTestBoxHide() end end)
end

local function ShowCase(case)
	-- (The style and size pretended: what Show reads, nothing saved.)
	ns.EmoteOpt = function(key)
		if key == "emoteVisionLook" then return case.look end
		if key == "emoteVisionPortrait" then return true end
		if key == "emoteVisionScale" then return 1 end
		return run.oldOpt(key)
	end
	ns.StyleLook = function(prefix, ...)
		local look = run.oldLook(prefix, ...)
		if prefix ~= "emoteVision" or type(look) ~= "table" then return look end
		local copy = {}
		for k, v in pairs(look) do copy[k] = v end
		copy.emoteTextSize = case.size
		return copy
	end
	local ok, shown, card = pcall(ns.EmoteFitShow, { kind = "Emote", name = "Someone Longername", class = "PALADIN",
		icon = "Interface\\Icons\\INV_Misc_QuestionMark", line = "thanks you.", emotes = case.emotes, test = true })
	if not ok then
		Say("  ERROR " .. tostring(shown))
		run.problems = run.problems + 1
		return nil
	end
	if not shown then Say("  no card (no emotes this client has)") end
	return shown and card or nil
end

function ns.EmoteFitTest(args)
	if args == "stop" then
		if run then Finish(true) else ns.Print("emote button test isn't running") end
		return
	end
	if run then ns.Print("emote button test is running: /cine debug emotefit stop") return end
	if not (ns.EmoteFitShow and ns.EmoteOpt and ns.StyleLook) then
		ns.Print("emote button test: Emote Vision isn't loaded")
		return
	end
	if InCombatLockdown() then ns.Print("emote button test: not in a fight") return end
	CinematicDB.emoteFitLog = {}
	run = { at = GetTime(), cases = {}, index = 0, problems = 0, oldOpt = ns.EmoteOpt, oldLook = ns.StyleLook }
	for _, look in ipairs(LOOKS) do
		for _, size in ipairs(SIZES) do
			for _, emotes in ipairs(SETS) do
				run.cases[#run.cases + 1] = { look = look, size = size, emotes = emotes }
			end
		end
	end
	Say(("emote button test: %d cards, client %s, locale %s, text scale %s, pad %s"):format(#run.cases,
		tostring((select(4, GetBuildInfo()))), tostring(GetLocale()), tostring(ns.VisionTextScale and ns.VisionTextScale()),
		tostring(GetCVarBool and GetCVarBool("GamePadEnable"))))
	ns.PadTestBox(("Emote button test: %d cards, about %d sec. Just watch."):format(#run.cases,
		math.ceil(#run.cases * NEXT_AT)), "", 1, 0.82, 0)
	local started, card, shot
	run.ticker = C_Timer.NewTicker(0.1, function()
		if not run then return end
		if InCombatLockdown() then Finish(true) return end
		local now = GetTime()
		if not started or now - started >= NEXT_AT then
			run.index = run.index + 1
			local case = run.cases[run.index]
			if not case then Finish() return end
			started, shot = now, false
			ns.PadTestBoxHide()
			-- (The menu look the panel buttons wear, as Skin.lua holds it and as
			-- it'd be read now: they went from the game's to flat mid-run once.)
			Say(("card %d: %s, size %d%%, %d emotes, menu look %s (now %s)"):format(run.index, case.look,
				case.size * 100, #case.emotes, tostring(ns.CurrentMenuSkin and ns.CurrentMenuSkin()),
				tostring(ns.MenuSkin and ns.MenuSkin())))
			card = ShowCase(case)
		elseif not shot and now - started >= SHOW_AT then
			shot = true
			if card and card:IsShown() then
				local case = run.cases[run.index]
				run.problems = run.problems + Measure(case, card)
				local ok = pcall(function() Screenshot() end)
				Say(("  screenshot at %s%s"):format(date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
			elseif card then
				Say("  card gone before it could be measured")
			end
		end
	end)
end
