-- Cinematic: Questie's quest tracker, which stands in for the game's, in two
-- of the game tracker's ways:
--
-- 1. The Interface Recolor page's Quest tracker rows (QuestTrackerStyle.lua's
--    looks, through ns.QuestTrackerKit), no settings of its own: Header bars
--    puts the theme's panel behind its "Questie Tracker: 3/40" header; Text
--    font puts that header and its zone names in General's font; Quest name
--    color takes the difficulty color out of each quest's name (kept as a dot
--    in front) and gives the name the theme's color; Bars and buttons tints
--    the quests' fold buttons. Its words get the firm shadow. Its own focus
--    buttons keep their colors (they say which quest is focused).
-- 2. The Quest Tracker page's "Show just that quest" and "Close the gaps"
--    (ns.AddQuestFocusTracker): the quests a reveal shows stay, the rest of
--    its lines, zone names, header and backdrop fade; closing the gaps moves
--    those quests' lines up to the top, quest under quest, and puts them back
--    after.
--
-- What's read (Questie 12.6.4, read 2026-11-10): its lines are pooled Buttons
-- linePool1..250 in its scroll child, each anchored under the one before
-- (linePool1 at the top), with .label (a FontString), .mode ("zone",
-- "quest", "achieve", "objective"), .Quest.Id (a quest's lines),
-- .expandQuest.texture (the fold button). Its header is Questie_HeaderFrame
-- with .trackedQuests.label. Its quest item buttons (secure) are parented to
-- their quest's line: a line with one can't be moved in a fight, so it's
-- moved (or put back) when the fight's over. Every read is guarded: an
-- unknown shape counts as nothing.
local _, ns = ...

local LINES = 250 -- (its pool)
local QUEST_GAP = 6 -- between quests moved up (its units)

local function Kit()
	return ns.QuestTrackerKit
end

local function Line(i)
	local line = _G["linePool" .. i]
	if type(line) == "table" and line.GetObjectType and type(line.label) == "table" then return line end
end

local function Shown(frame)
	return frame and ns.Flag(frame:IsShown())
end

-- 1. Its look --------------------------------------------------------------

local plan -- (the Interface Recolor page's now; nil: the game's look)
local busy = false
local styled = {} -- [label] = { text = what Questie wrote, r, g, b, a } for a quest name we rewrote
local hookedLines, modes = {}, {}
local tinted, shadowed = {}, {}

-- A quest's name: its words with the dot, in the theme's color.
local function StyleTitle(line)
	local label = line.label
	local okText, raw = pcall(label.GetText, label)
	if not okText or type(raw) ~= "string" or (issecretvalue and issecretvalue(raw)) then return end
	local own = styled[label]
	if not own then
		local r, g, b, a = label:GetTextColor()
		own = { r, g, b, a }
		styled[label] = own
	end
	if not raw:find("|T", 1, true) then
		own.text = raw
		local _, size = label:GetFont()
		local plain = Kit().DotName(raw, size)
		if plain ~= raw then
			busy = true
			label:SetText(plain)
			busy = false
		end
	end
	local accent = plan.accent
	label:SetTextColor(accent[1], accent[2], accent[3], 1)
end

-- A line we rewrote, back to Questie's: its words (keep: when it's still the
-- same line) and its color.
local function UnstyleTitle(label, keepText)
	local own = styled[label]
	if not own then return end
	styled[label] = nil
	busy = true
	if keepText and own.text then label:SetText(own.text) end
	label:SetTextColor(own[1] or 1, own[2] or 0.82, own[3] or 0, own[4] or 1)
	busy = false
end

local function StyleLine(line)
	local label = line.label
	local mode = line.mode
	-- (Questie set its own font as the line changed kind: ours is forgotten.)
	if modes[line] ~= mode then
		modes[line] = mode
		Kit().ForgetFont(label)
	end
	Kit().SetFont(label, plan and plan.font and mode == "zone" and plan.font or nil)
	if plan and Shown(line) then
		shadowed[label] = true
		Kit().SetShadow(label, true)
	elseif shadowed[label] then
		shadowed[label] = nil
		Kit().SetShadow(label, false)
	end
	if plan and plan.accent and mode == "quest" then
		StyleTitle(line)
	elseif styled[label] then
		UnstyleTitle(label, false) -- (another kind of line now: its words are Questie's)
	end
	local fold = type(line.expandQuest) == "table" and line.expandQuest.texture
	if type(fold) == "table" and fold.SetDesaturated then
		local tint = plan and plan.buttons and plan.ring or nil
		if tint or tinted[fold] then
			tinted[fold] = tint and true or nil
			Kit().Tint(fold, tint)
		end
	end
end

-- Its line changing words or kind between our passes: styled at once.
local function HookLine(line)
	if hookedLines[line] then return end
	hookedLines[line] = true
	hooksecurefunc(line.label, "SetText", function()
		if busy then return end
		if plan and plan.accent and line.mode == "quest" then
			StyleTitle(line)
		elseif styled[line.label] then
			UnstyleTitle(line.label, false)
		end
	end)
	if type(line.SetMode) == "function" then
		hooksecurefunc(line, "SetMode", function()
			if not busy and (plan or modes[line]) then StyleLine(line) end
		end)
	end
end

-- Its header: the panel behind it, the width of the tracker.
local headerHooked = false
local function PlacePanel(panel)
	local header, base = _G.Questie_HeaderFrame, _G.Questie_BaseFrame
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", header, "TOPLEFT", 2, 3)
	panel:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 2, -2)
	local left = header:GetLeft()
	local baseRight = base and base:GetRight()
	if type(left) == "number" and type(baseRight) == "number" then
		panel:SetWidth(math.max(header:GetWidth(), baseRight - left - 6))
	else
		panel:SetWidth(header:GetWidth() + 8)
	end
end

local function StyleHeader()
	local header = _G.Questie_HeaderFrame
	if type(header) ~= "table" or not header.GetObjectType then return end
	Kit().DressHeader(header, nil, plan and plan.headers or false, PlacePanel)
	local tracked = header.trackedQuests
	local label = type(tracked) == "table" and tracked.label
	if type(label) ~= "table" or not label.SetFont then return end
	Kit().SetFont(label, plan and plan.font or nil)
	Kit().SetShadow(label, plan ~= nil)
	-- (It sets its own font again as it updates: ours straight after.)
	if not headerHooked then
		headerHooked = true
		hooksecurefunc(label, "SetFont", function()
			if busy or not (plan and plan.font) then return end
			busy = true
			Kit().SetFont(label, plan.font)
			busy = false
		end)
	end
end

-- A pass: QuestTrackerStyle.lua's Restyle, with the page's plan (nil: off).
local function Restyle(newPlan)
	if not (Kit() and _G.Questie_BaseFrame) then return end
	local wasOn = plan ~= nil
	plan = newPlan
	if not plan and not wasOn and not next(styled) and not next(tinted) then return end
	StyleHeader()
	for i = 1, LINES do
		local line = Line(i)
		if not line then break end
		if plan then HookLine(line) end
		if plan or hookedLines[line] then StyleLine(line) end
	end
	-- (Off: the quests' names back as Questie wrote them.)
	if not (plan and plan.accent) then
		for label in pairs(styled) do UnstyleTitle(label, true) end
	end
end

ns.WhenAddonLoads("Questie", function()
	ns.RestyleQuestieTracker = Restyle
	-- After it lays the tracker out: once, a frame later (as the game tracker's).
	local loader = _G.QuestieLoader
	local ok, tracker = pcall(function() return loader:ImportModule("QuestieTracker") end)
	if ok and type(tracker) == "table" and type(tracker.Update) == "function" then
		hooksecurefunc(tracker, "Update", function()
			if plan or next(styled) then ns.RefreshQuestTrackerStyle() end
		end)
	end
end)

-- 2. Show just that quest ----------------------------------------------------

local moved = {} -- [line] = { its own anchor's points } while not in its own place
local placedAt = {} -- [line] = the line it's under now (or false: the top)
local backdrop -- { own back color, own edge color, set back, set edge } while faded
local anyMoved = false

local function CanMove(line)
	return not InCombatLockdown() or not line:IsProtected()
end

local function Under(line, above, gap)
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
end

local function PutBack(line)
	local own = moved[line]
	line:ClearAllPoints()
	line:SetPoint(own[1], own[2], own[3], own[4], own[5])
	moved[line], placedAt[line] = nil, nil
end

-- Its backdrop (on the tracker itself, so not a part to fade): its colors'
-- alpha times alpha; Questie setting its own since counts as its own.
local function FadeBackdrop(base, alpha)
	if not (base.GetBackdropColor and base.SetBackdropColor) then return end
	local function Same(a, b)
		return a and b and math.abs((a[4] or 0) - (b[4] or 0)) < 0.01
	end
	if alpha >= 1 then
		if backdrop then
			local back, edge = backdrop[1], backdrop[2]
			base:SetBackdropColor(back[1], back[2], back[3], back[4])
			base:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
			backdrop = nil
		end
		return
	end
	local back, edge = { base:GetBackdropColor() }, { base:GetBackdropBorderColor() }
	if not backdrop or not (Same(back, backdrop[3]) and Same(edge, backdrop[4])) then
		backdrop = { back, edge }
	end
	local ownBack, ownEdge = backdrop[1], backdrop[2]
	backdrop[3] = { ownBack[1], ownBack[2], ownBack[3], (ownBack[4] or 0) * alpha }
	backdrop[4] = { ownEdge[1], ownEdge[2], ownEdge[3], (ownEdge[4] or 0) * alpha }
	base:SetBackdropColor(unpack(backdrop[3]))
	base:SetBackdropBorderColor(unpack(backdrop[4]))
end

local wanted, runs, firstOf = {}, {}, {}
local function Apply(othersAlpha, quests, timers, active)
	local base = _G.Questie_BaseFrame
	if type(base) ~= "table" or not base.GetChildren then return false end
	local questFrame = _G.TrackedQuests
	-- (Its header, its icon, the sizer: everything but the quests.)
	for _, part in ipairs({ base:GetChildren() }) do
		if part ~= questFrame then ns.FadeRelative(part, othersAlpha) end
	end
	FadeBackdrop(base, othersAlpha)
	local scrollBar = _G.TrackedQuestsScrollFrame and _G.TrackedQuestsScrollFrame.ScrollBar
	if type(scrollBar) == "table" and scrollBar.SetAlpha then ns.FadeRelative(scrollBar, othersAlpha) end

	-- Its lines: a quest's (title, objectives, timer) stay with its quest.
	wipe(wanted)
	wipe(runs)
	wipe(firstOf)
	local found, previous = false, nil
	for i = 1, LINES do
		local line = Line(i)
		if not line or not Shown(line) then break end
		local quest = line.mode ~= "zone" and type(line.Quest) == "table" and line.Quest.Id
		local want = quest and (quests[quest] or (timers and timers[quest])) and true or false
		ns.FadeRelative(line, want and 1 or othersAlpha)
		if want then
			found = true
			wanted[line] = true
			-- (A new run: the first line of a quest, or after lines that fade.)
			if not (previous and wanted[previous]) or (type(previous.Quest) == "table" and previous.Quest.Id ~= quest) then
				runs[#runs + 1] = line
				firstOf[line] = i
			end
		end
		previous = line
	end

	-- Close the gaps: only while just those quests are wanted. Each run's first
	-- line goes under the last wanted line before it (the first run to the
	-- top); the lines after it follow it, as they're anchored under it.
	local collapse = active and ns.db.questRevealOnlyThat and ns.db.questRevealCollapse and #runs > 0
	local want = {} -- [line] = the line to go under (false: the top)
	if collapse then
		local lastWanted
		for i = 1, LINES do
			local line = Line(i)
			if not line or not Shown(line) then break end
			if firstOf[line] then
				local above = lastWanted or false
				-- (Already in its own place under it: no move.)
				local own = i == 1 and not lastWanted or (lastWanted and Line(i - 1) == lastWanted)
				if not own then want[line] = above end
			end
			if wanted[line] then lastWanted = line end
		end
	end
	local top = Line(1)
	for line in pairs(moved) do
		if want[line] == nil and CanMove(line) then PutBack(line) end
	end
	for line, above in pairs(want) do
		if placedAt[line] ~= above and CanMove(line) then
			if not moved[line] then
				moved[line] = { line:GetPoint(1) }
			end
			if above then
				Under(line, above, QUEST_GAP)
			else
				local own = moved[top] or { top:GetPoint(1) }
				line:ClearAllPoints()
				line:SetPoint(own[1], own[2], own[3], own[4], own[5])
			end
			placedAt[line] = above
		end
	end
	-- (All back: Questie's tracker height was worked out with them moved.)
	local restored = anyMoved and not next(moved)
	anyMoved = next(moved) ~= nil
	if restored and not InCombatLockdown() then
		local ok, tracker = pcall(function() return _G.QuestieLoader:ImportModule("QuestieTracker") end)
		if ok and type(tracker) == "table" and type(tracker.Update) == "function" then
			pcall(tracker.Update, tracker)
		end
	end
	ns.questFocusOthersUp = othersAlpha < 1 or next(moved) ~= nil
	return found
end

ns.WhenAddonLoads("Questie", function()
	ns.AddQuestFocusTracker(Apply)
end)
