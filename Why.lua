-- Inspect (/cine why, or the minimap button's menu): point at any frame
-- Cinematic fades, even one faded out, and click it to see why it's showing
-- or hidden right now, and which settings say so. UpdateFrames notes what
-- decided the frame being looked at (ns.WhyNote); the Standard Frames row's
-- columns behind it are worked out here again, as GetCombatShownFrames has them.

local ADDON_NAME, ns = ...
local L = ns.L

local NONE = {}
local ICON = {
	on = "Interface\\RaidFrame\\ReadyCheck-Ready",
	off = "Interface\\RaidFrame\\ReadyCheck-Waiting",
	block = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}
local GREEN, GREY, GOLD = "|cff8fe39a", "|cff9d9585", "|cffffd100"

local function Plain(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

local function Fighting()
	return InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
end

-- What UpdateFrames worked out on its last tick for the frames being looked
-- at (ns.whyLook: the one picked and the one under the cursor), by entry.
local notes = setmetatable({}, { __mode = "k" })
function ns.WhyNote(entry, target, row, cinematic, hovered, triggered, tracking, listShown, fightingShown,
		chatShowing, typingShown, deathFade, deathKept, immersive, follows, events, keepIndoors,
		questTimerUp, durabilityUp, petUnhappyUp, hoverGroups, offWhen, combatShown)
	local note = notes[entry]
	if not note then
		note = { triggers = {} }
		notes[entry] = note
	end
	note.at, note.target, note.row, note.cinematic = GetTime(), target, row, cinematic
	note.hovered, note.triggered, note.tracking = hovered[row], triggered[row], tracking
	note.listShown, note.fightingShown, note.chatShowing, note.typingShown = listShown, fightingShown,
		chatShowing, typingShown
	note.deathFade, note.deathKept, note.immersive = deathFade, deathKept, immersive
	note.keepIndoors, note.questTimerUp, note.durabilityUp, note.petUnhappyUp = keepIndoors, questTimerUp,
		durabilityUp, petUnhappyUp
	note.follows = follows
	note.followsUp = follows and (hovered[follows] or triggered[follows]
		or (combatShown and combatShown["group:" .. follows])) or false
	-- (The Mouseover groups' events that brought it up: group, trigger key.)
	local triggers = wipe(note.triggers)
	if triggered[row] then
		for _, group in ipairs(hoverGroups) do
			if not group.off and group.when ~= offWhen and group.triggers then
				local member = false
				for _, key in ipairs(group.members or NONE) do
					if key == row then member = true break end
				end
				for key, on in pairs(member and group.triggers or NONE) do
					if on and events[key] then
						triggers[#triggers + 1] = { group = group, key = key }
					end
				end
			end
		end
	end
end

-- The Standard Frames (or Advanced Frames) row a frame goes with, and its key.
local function RowItem(entry)
	for _, item in ipairs(ns.COMBAT_SHOW) do
		for _, name in ipairs(item.frames or NONE) do
			if name == entry.name then return item end
		end
	end
	for _, item in ipairs(ns.COMBAT_SHOW) do
		for _, group in ipairs(item.groups or NONE) do
			if group == entry.group then return item end
		end
	end
end

local function RowLabel(key)
	for _, item in ipairs(ns.COMBAT_SHOW) do
		if item.key == key then return item.label end
	end
	return (type(key) == "string" and key:match("^extra:(.+)")) or key
end

local function FramePage(key)
	if type(key) ~= "string" then return "Standard Frames" end
	if key:find("^page:") then return key:sub(6) end
	if key:find("^tooltip:") then return "Tooltips" end
	return (key:find("^extra:") or key:find("^addon:")) and "Advanced Frames" or "Standard Frames"
end

local function TriggerLabel(key)
	for _, trigger in ipairs(ns.HOVER_TRIGGERS) do
		if trigger.key == key then return trigger.label end
	end
	return key
end

-- A rule with each situation word green (true now) or grey (false).
local function ColorRule(text, facts)
	-- (| starts the game's text codes: doubled, it shows as itself.)
	return (text:gsub("|", "||"):gsub("[%w_]+", function(word)
		local field = ns.RULE_WORDS[word:lower()]
		if not field then return word end
		return (facts[field] and GREEN or GREY) .. word .. "|r"
	end))
end

local function Add(out, state, text, page)
	out[#out + 1] = { state = state, text = text, page = page }
end

-- A row's columns: on (doing it now), off (ticked, would show it elsewhere
-- or later) and block (keeping it hidden).
local function Columns(key, out)
	local page = FramePage(key)
	local fighting = Fighting()
	local calm = ns.InCalm()
	local facts = ns.RuleFacts(fighting or (calm and ns.db.combatShowCalm))
	if ns.RoleHides(facts)[key] then
		Add(out, "block", L["Hidden while you play your current role (the row's roles button)"], page)
		return
	end
	local text = ns.db.frameRules and ns.db.frameRules[key]
	if ns.RuleTest(key) then
		local on = ns.RuleShows(key, facts)
		Add(out, on and "on" or "block", L["Rule: %s (the rule decides, not the ticks)"]:format(ColorRule(text, facts)), page)
		return
	end
	local stays = ns.db.stayInCombat
	local found = false
	if ns.IsCineShowOn(key) then
		Add(out, "on", L["Always is ticked"], page)
		found = true
	end
	local place = ns.GetPlaceType()
	local here = (place == "pvp" and "bgShow") or ((place == "dungeon" or place == "raid") and "instanceShow")
		or (place == "city" and "cityShow") or "worldShow"
	local grouped = ns.InGroup()
	for _, column in ipairs(ns.PLACE_SHOW) do
		if ns.IsPlaceShowOn(column.list, key) then
			local now = column.list == here or (column.list == "groupShow" and grouped)
			Add(out, now and "on" or "off", (now and L["%s is ticked, and you're there"]
				or L["%s is ticked (not where you are now)"]):format(column.label), page)
			found = true
		end
	end
	local hasTarget = ns.HasTarget()
	local enemy = hasTarget and ns.IsEnemyUnit("target") and not ns.Flag(UnitIsDeadOrGhost("target"))
	if ns.IsCombatShowOn(key) then
		local now = fighting and stays
		Add(out, now and "on" or "off", now and L["In combat is ticked, and you're fighting"]
			or (fighting and L["In combat is ticked, but CineMode doesn't stay on in fights"])
			or L["In combat is ticked: it shows when a fight starts"], page)
		found = true
	end
	if ns.IsCalmShowOn(key) and (calm or not ns.IsCombatShowOn(key)) then
		local now = calm and stays
		Add(out, now and "on" or "off", now and L["Calm Timer is ticked, and a fight just ended"]
			or L["Calm Timer is ticked: it stays a while after a fight"], page)
		found = true
	end
	if ns.IsEnemyShowOn(key) then
		local now = not fighting and enemy
		Add(out, now and "on" or "off", now and L["Tar enemy is ticked, and you target an enemy"]
			or L["Tar enemy is ticked: it shows when you target an enemy"], page)
		found = true
	end
	if ns.IsFriendlyShowOn(key) then
		local now = not fighting and hasTarget and not enemy
		Add(out, now and "on" or "off", now and L["Tar friendly is ticked, and you target a friend"]
			or L["Tar friendly is ticked: it shows when you target a friend"], page)
		found = true
	end
	if fighting and ns.FightHold(key) and not ns.IsCineShowOn(key) then
		Add(out, "block", L["Held back at the fight's start while you're at rest (Personal Resources page)"],
			"Personal Resources")
	end
	if not found then
		Add(out, "off", L["Nothing is ticked on its row: tick Always to keep it up"], page)
	end
end

-- The last tooltip (Effects.lua notes each decision in ns.lastTooltipWhy):
-- a hidden tooltip can't be pointed at, so Inspect's bar has a button for it.
local TOOLTIP_KEY = "tooltip:All"
local tooltipStandIn = { tooltip = true, name = "GameTooltip" }
local KIND_LABEL = { tipquest = "Quest objective", tipgather = "Gatherable", tipenemy = "Enemy",
	tipfriendly = "Friendly", tipother = "Anything else" }

local function ExplainTooltip()
	local out, last = {}, ns.lastTooltipWhy
	local title = L["Tooltip"]
	if not last then
		Add(out, "off", L["No tooltip yet this session: point at something, then look again"], "Tooltips")
		return title, "unknown", out, TOOLTIP_KEY
	end
	if type(last.name) == "string" and not (issecretvalue and issecretvalue(last.name)) then
		title = L["Tooltip: %s"]:format(last.name)
	end
	local status = last.hide and "hidden" or "shown"
	if not last.handled then
		Add(out, "on", L["The Tooltips page is off, so Cinematic leaves tooltips alone"], "Tooltips")
	elseif not last.cinematic then
		Add(out, "on", L["CineMode was off, so tooltips show as usual"], "CineMode")
	elseif last.keyDown then
		Add(out, "on", L["You were holding the key that shows tooltips"], "Tooltips")
	elseif last.why == "until still" then
		Add(out, "block", L["Hide until the mouse is still: the mouse hadn't been still long enough"], "Tooltips")
	else
		local kinds = {}
		for word in pairs(last.kinds or NONE) do kinds[#kinds + 1] = L[KIND_LABEL[word] or word] end
		table.sort(kinds)
		local kindText = table.concat(kinds, ", ")
		if kindText == "" then
			-- (Not looked at by kind: a minimap blip's tooltip always shows.)
			Add(out, "on", L["A minimap blip's tooltip, which always shows"], "Tooltips")
		else
			Add(out, last.hide and "block" or "on", (last.hide and L["The Tooltips row was off then for: %s"]
				or L["The Tooltips row was on then for: %s"]):format(kindText), "Tooltips")
		end
		local text = ns.db.frameRules and ns.db.frameRules[TOOLTIP_KEY]
		if ns.RuleTest(TOOLTIP_KEY) then
			-- (Read now, with that tooltip's kinds: the rest may have changed since.)
			ns.tooltipKinds = last.kinds
			local facts = ns.RuleFactsNow()
			ns.tooltipKinds = nil
			Add(out, "off", L["Its rule, as things are now: %s"]:format(ColorRule(text, facts)), "Tooltips")
		elseif ns.db.tooltipAlways then
			Add(out, "off", L["Always is ticked on the Tooltips row"], "Tooltips")
		end
	end
	return title, status, out, TOOLTIP_KEY
end

-- Cinematic's own frames (the quest talk bubble, speech from behind you,
-- Chat Cam's subtitles...): their code shows them, not UpdateFrames, so each
-- tells Inspect what it is with ns.WhyRegister(frame, title, page, reasons).
-- reasons: the lines for the card (shown: why it's up), each a string.
local own = setmetatable({}, { __mode = "k" })
function ns.WhyRegister(frame, title, page, reasons)
	if frame then
		own[frame] = { frame = frame, own = true, name = title, page = page, reasons = reasons }
	end
end

-- Its size, when it's on screen under the cursor (a frame or a text).
local function OwnArea(frame)
	if not (ns.Flag(frame:IsVisible()) and ns.Flag(frame:IsMouseOver())) then return end
	local parent = frame:GetParent()
	local alpha = frame.GetEffectiveAlpha and frame:GetEffectiveAlpha()
		or frame:GetAlpha() * (parent and parent:GetEffectiveAlpha() or 1)
	local width, height = frame:GetSize()
	if Plain(alpha) and alpha > 0.05 and Plain(width) and Plain(height) and width * height > 0 then
		return width * height
	end
end

-- The smallest of them under the cursor and on screen, or nil.
local function OwnFrameUnderCursor()
	local best, bestArea
	for frame, info in pairs(own) do
		local ok, area = pcall(OwnArea, frame)
		if ok and area and (not bestArea or area < bestArea) then
			best, bestArea = info, area
		end
	end
	return best
end

local function ExplainOwn(entry)
	local out = {}
	for _, text in ipairs(entry.reasons or NONE) do
		Add(out, "on", text, entry.page)
	end
	return entry.name, "shown", out, "page:" .. entry.page
end

-- Title, status ("shown", "hidden", "partly", "unmanaged" or "unknown"),
-- what decides it.
local function Explain(entry)
	if entry.tooltip then
		return ExplainTooltip()
	elseif entry.own then
		return ExplainOwn(entry)
	end
	-- (Another addon's frame Cinematic doesn't fade: see AddonFrameUnderCursor.)
	if entry.unmanaged then
		local out, name = {}, entry.name
		if ns.db.ignoredFrames[name] then
			Add(out, "on", L["You set it to always show (Custom frames, Advanced Frames page)"], "Advanced Frames")
		else
			Add(out, "on", L["%s isn't a supported addon, so Cinematic leaves its frames as they are"]
				:format(entry.unmanaged), "Advanced Frames")
			Add(out, "off", L["/cine add %s fades it in CineMode, or add it on the Advanced Frames page"]:format(name),
				"Advanced Frames")
		end
		return name, "unmanaged", out, "extra:" .. name
	end
	local item = RowItem(entry)
	local key = item and item.key or entry.group
	local title = item and item.label or RowLabel(key) or entry.name or "?"
	local out = {}
	local n = notes[entry]
	n = n and GetTime() - n.at < 1 and n
	if not n then
		Add(out, "off", L["Cinematic isn't fading frames right now (it's off or paused)"], "CineMode")
		return title, "unknown", out, key
	end
	local status = n.target >= 1 and "shown" or n.target > 0 and "partly" or "hidden"
	if not n.cinematic then
		Add(out, "on", L["CineMode is off, so nothing fades"], "CineMode")
		return title, status, out, key
	end
	-- What's keeping it hidden, over anything else.
	if ns.layoutFadeUntil then
		Add(out, "block", L["Fading out for a layout change"])
	elseif ns.previewRows then
		Add(out, ns.previewRows[n.row] and "on" or "block", L["A profile preview shows just its own frames"])
	end
	if n.immersive and not n.typingShown then
		Add(out, "block", L["Chat Cam's Ultra immersive hides the whole UI in a conversation"], "Cameras")
	end
	if n.deathFade and not n.deathKept and not n.hovered then
		Add(out, "block", L["The death camera fades everything while you're dead"])
	elseif n.deathFade and n.deathKept then
		Add(out, "on", L["Its group is kept up through the death camera"])
	end
	if n.follows and not n.followsUp then
		Add(out, "block", L["It goes with the %s row, which is hidden"]:format(RowLabel(n.follows)), FramePage(n.follows))
	end
	if entry.group == "swing" and ns.IsSwingBarUnused and ns.IsSwingBarUnused(entry.name) then
		Add(out, "block", L["This swing bar isn't in use"], "Swing timer")
	end
	-- What's bringing it up.
	if n.hovered then
		Add(out, "on", L["The mouse is on it, or on a frame in its Mouseover group"], "Mouseover groups")
	end
	if n.typingShown then
		Add(out, "on", L["You're typing in chat"], "Chat")
	elseif n.chatShowing then
		Add(out, "on", L["A chat message is peeking"], "Chat")
	end
	if n.tracking then
		if entry.group == "minimap" then
			if ns.db.alwaysShowMinimap then
				Add(out, "on", L["Keep open: always"], "Minimap")
			end
			if n.keepIndoors then
				if ns.db.minimapIndoors and IsIndoors and ns.Flag(IsIndoors()) then
					Add(out, "on", L["Keep open: indoors, and you're inside"], "Minimap")
				end
				if ns.db.minimapKeepQuest and ns.HasTrackedQuest() then
					Add(out, "on", L["Keep open: a tracked quest"], "Minimap")
				end
				if ns.IsMinimapKeptInZone() then
					Add(out, "on", L["Keep open: in this zone"], "Minimap")
				end
			end
		elseif entry.group == "waypoint" and ns.db.alwaysShowWaypoint then
			Add(out, "on", L["Always show the waypoint is on"])
		elseif entry.group == "questtimer" and n.questTimerUp then
			Add(out, "on", L["A quest timer is running"], "Quest tracker")
		elseif entry.group == "misc" and n.durabilityUp then
			Add(out, "on", L["Your gear is damaged (durability alert)"], "Quest tracker")
		elseif entry.name == "PetFrame" and n.petUnhappyUp then
			Add(out, "on", L["Your pet is unhappy"], "Hunter")
		end
		for _, trigger in ipairs(n.triggers) do
			Add(out, "on", L["Mouseover group \"%s\": %s"]:format(trigger.group.name or "?", TriggerLabel(trigger.key)),
				"Mouseover groups")
		end
	end
	if n.fightingShown and not n.listShown then
		Add(out, "on", L["Your frame stays up while you recover"], "Personal Resources")
	end
	if status == "partly" and not n.listShown and not n.tracking and not n.hovered then
		Add(out, "on", L["Vitals Vision shows it as far as your health says"], "Vitals Vision")
	end
	-- The row's columns: the ones doing it now, then the ones that would.
	local columns = {}
	Columns(key, columns)
	for _, reason in ipairs(columns) do
		if reason.state ~= "off" then out[#out + 1] = reason end
	end
	if status == "hidden" and ns.db.mouseover then
		Add(out, "off", L["Put the mouse on it"], "Mouseover groups")
	end
	for _, reason in ipairs(columns) do
		if reason.state == "off" then out[#out + 1] = reason end
	end
	return title, status, out, key
end

-- Inspect mode: a see-through layer over the screen that takes the clicks,
-- a gold box on the frame under the cursor, and the card for the one picked.
local overlay, box, card
local picked
-- (Looked up each time: the language is picked after this file loads.)
local function StatusText(status)
	return status == "shown" and GREEN .. L["SHOWING"] .. "|r" or status == "hidden" and "|cfff2a3a3" .. L["HIDDEN"] .. "|r"
		or status == "partly" and GOLD .. L["PARTLY SHOWN"] .. "|r"
		or status == "unmanaged" and GREY .. L["NOT FADED"] .. "|r" or GREY .. "?|r"
end

-- Where an entry is on the screen, in screen pixels (left, bottom, width,
-- height), or nil. Faded ones too: a shrunk or parked one by its spot.
local function EntryRect(entry)
	if entry.shrunk or entry.parkedFullSize then
		local rect, scale = entry.savedRect, entry.savedEffectiveScale or 1
		if rect and Plain(rect[1]) then
			return rect[1] * scale, rect[2] * scale, rect[3] * scale, rect[4] * scale
		end
		return
	end
	local frame = entry.frame
	if not frame or (frame.IsForbidden and frame:IsForbidden()) or not ns.Flag(frame:IsVisible()) then
		return
	end
	local left, bottom, width, height = frame:GetRect()
	local scale = frame:GetEffectiveScale()
	if Plain(left) and Plain(bottom) and Plain(width) and Plain(height) and Plain(scale) then
		return left * scale, bottom * scale, width * scale, height * scale
	end
end

-- The smallest frame under the cursor: the most particular one.
local function EntryUnderCursor()
	local x, y = GetCursorPosition()
	local best, bestArea
	for _, entry in ipairs(ns.managed or NONE) do
		local ok, left, bottom, width, height = pcall(EntryRect, entry)
		if ok and left and width * height > 4 and x >= left and x <= left + width and y >= bottom
			and y <= bottom + height and (not bestArea or width * height < bestArea) then
			best, bestArea = entry, width * height
		end
	end
	return best
end

-- Another addon's named frame under the cursor that Cinematic doesn't fade
-- (the smallest: a top-level one, or one just inside a big holder), as a
-- stand-in entry kept per frame, or nil. Not the game's, not this addon's.
local standIns = setmetatable({}, { __mode = "k" })
local function AddonFrameUnderCursor()
	local managed = {}
	for _, entry in ipairs(ns.managed or NONE) do managed[entry.frame] = true end
	local uiScale = UIParent:GetEffectiveScale()
	local screen = UIParent:GetWidth() * UIParent:GetHeight()
	local best, bestArea, bestSource
	local function Consider(frame, depth)
		if (frame.IsForbidden and frame:IsForbidden()) or managed[frame] or not ns.Flag(frame:IsVisible())
			or not ns.Flag(frame:IsMouseOver()) then
			return
		end
		local width, height = frame:GetSize()
		local scale = frame:GetEffectiveScale() / uiScale
		if not (Plain(width) and Plain(height) and Plain(scale)) then return end
		local area = width * height * scale * scale
		local name = frame:GetName()
		-- (A holder as big as half the screen, or unnamed: what's just inside it.)
		if not name or area > screen / 2 then
			if depth == 0 then
				for _, child in ipairs({ frame:GetChildren() }) do Consider(child, 1) end
			end
			return
		end
		local alpha = frame:GetEffectiveAlpha()
		if area <= 0 or not Plain(alpha) or alpha < 0.05 or (bestArea and area >= bestArea) then return end
		local ok, secure, source = pcall(issecurevariable, name)
		if ok and not secure and source ~= ADDON_NAME then
			best, bestArea, bestSource = frame, area, source
		end
	end
	for _, frame in ipairs({ UIParent:GetChildren() }) do Consider(frame, 0) end
	if not best then return end
	local standIn = standIns[best]
	if not standIn then
		standIn = { frame = best, name = best:GetName() }
		standIns[best] = standIn
	end
	standIn.unmanaged = type(bestSource) == "string" and bestSource or L["An addon"]
	return standIn
end

local function PlaceOver(frame, entry)
	local ok, left, bottom, width, height = pcall(EntryRect, entry)
	if not (ok and left) then
		frame:Hide()
		return false
	end
	local scale = UIParent:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left / scale, bottom / scale)
	frame:SetSize(math.max(1, width / scale), math.max(1, height / scale))
	frame:Show()
	return true
end

local function Edge(frame, r, g, b, a)
	local texture = frame:CreateTexture(nil, "OVERLAY")
	texture:SetColorTexture(r, g, b, a)
	return texture
end

local function MakeBox()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetFrameLevel(50)
	local fill = frame:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(1, 0.82, 0, 0.12)
	local top, bottom, left, right = Edge(frame, 1, 0.82, 0, 0.9), Edge(frame, 1, 0.82, 0, 0.9),
		Edge(frame, 1, 0.82, 0, 0.9), Edge(frame, 1, 0.82, 0, 0.9)
	top:SetPoint("TOPLEFT") top:SetPoint("TOPRIGHT") top:SetHeight(2)
	bottom:SetPoint("BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT") bottom:SetHeight(2)
	left:SetPoint("TOPLEFT") left:SetPoint("BOTTOMLEFT") left:SetWidth(2)
	right:SetPoint("TOPRIGHT") right:SetPoint("BOTTOMRIGHT") right:SetWidth(2)
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 4)
	local back = frame:CreateTexture(nil, "BORDER")
	back:SetColorTexture(0, 0, 0, 0.7)
	back:SetPoint("TOPLEFT", label, -4, 3)
	back:SetPoint("BOTTOMRIGHT", label, 4, -3)
	frame.label, frame.back = label, back
	return frame
end

local LINE_WIDTH = 300
local Stop, Refresh -- (below)

local function OpenPage(page)
	Stop()
	ns.OpenOptions(page)
end

local function ReasonLine(index)
	local line = card.lines[index]
	if line then return line end
	line = CreateFrame("Button", nil, card)
	line.icon = line:CreateTexture(nil, "ARTWORK")
	line.icon:SetSize(14, 14)
	line.icon:SetPoint("TOPLEFT", 0, -1)
	line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	line.text:SetPoint("TOPLEFT", line.icon, "TOPRIGHT", 6, 1)
	line.text:SetWidth(LINE_WIDTH)
	line.text:SetJustifyH("LEFT")
	line.where = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	line.where:SetPoint("TOPLEFT", line.text, "BOTTOMLEFT", 0, -2)
	line.where:SetJustifyH("LEFT")
	local glow = line:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 0.82, 0, 0.08)
	line:SetScript("OnClick", function(self)
		if self.page then OpenPage(self.page) end
	end)
	card.lines[index] = line
	return line
end

local function Heading(text, anchor, gap)
	card.headingsUsed = card.headingsUsed + 1
	local heading = card.headings[card.headingsUsed]
	if not heading then
		heading = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		heading:SetJustifyH("LEFT")
		card.headings[card.headingsUsed] = heading
	end
	heading:ClearAllPoints()
	heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
	heading:SetText(text)
	heading:Show()
	return heading
end

local function CardButton(text, onClick)
	local button = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
	button:SetSize(108, 24)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	if ns.SkinButton then ns.SkinButton(button) end
	return button
end

local function PrintCard()
	if not picked then return end
	local title, status, reasons = Explain(picked)
	ns.Print(("%s: %s"):format(title, StatusText(status)))
	for _, reason in ipairs(reasons) do
		local mark = reason.state == "on" and GREEN .. "+" or reason.state == "block" and "|cfff2a3a3x" or GREY .. "-"
		print(("  %s|r %s"):format(mark, reason.text))
	end
end

local function MakeCard()
	card = CreateFrame("Frame", "CinematicInspectCard", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	card:SetFrameStrata("TOOLTIP")
	card:SetWidth(LINE_WIDTH + 52)
	card:SetClampedToScreen(true)
	card:EnableMouse(true)
	if card.SetBackdrop then
		card:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
	end
	if ns.SkinWindow then ns.SkinWindow(card) end
	card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	card.title:SetPoint("TOPLEFT", 16, -14)
	card.title:SetPoint("RIGHT", card, "RIGHT", -110, 0)
	card.title:SetJustifyH("LEFT")
	card.status = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	card.status:SetPoint("TOPRIGHT", -34, -16)
	local close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	if ns.SkinClose then ns.SkinClose(close) end
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() Stop() end)
	card.row = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.row:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
	card.lines, card.headings, card.headingsUsed = {}, {}, 0
	card.open = CardButton(L["Open settings"], function() OpenPage(card.page) end)
	card.print = CardButton(L["Print to chat"], PrintCard)
	card.open:SetPoint("BOTTOMLEFT", 16, 14)
	card.print:SetPoint("LEFT", card.open, "RIGHT", 8, 0)
	card.hint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.hint:SetPoint("BOTTOMLEFT", card.open, "TOPLEFT", 0, 8)
	card.hint:SetText(L["Click a line to open its setting. Click another frame to look at it."])
	card.hint:SetWidth(LINE_WIDTH + 20)
	card.hint:SetJustifyH("LEFT")
	card.elapsed = 0
	card:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = self.elapsed + elapsed
		if self.elapsed > 0.25 then
			self.elapsed = 0
			Refresh()
		end
	end)
end

-- Fills the card from what's true now (four times a second while it's up).
function Refresh()
	if not (card and picked) then return end
	local title, status, reasons, key = Explain(picked)
	card.title:SetText(title)
	card.status:SetText(StatusText(status))
	local last = ns.lastTooltipWhy
	if picked.tooltip then
		card.row:SetText(last and L["The last tooltip, %d sec ago"]:format(GetTime() - last.at) or "")
	elseif picked.unmanaged then
		card.row:SetText(L["Made by %s"]:format(picked.unmanaged))
	elseif picked.own then
		card.row:SetText(L["Cinematic's own, %s page"]:format(L[picked.page]))
	else
		card.row:SetText(L["%s row, %s page"]:format(RowLabel(key) or title, L[FramePage(key)]))
	end
	card.page = FramePage(key)
	card.headingsUsed = 0
	for _, heading in ipairs(card.headings) do heading:Hide() end
	local anchor, height = card.row, 44
	local lastState
	local index = 0
	for _, reason in ipairs(reasons) do
		-- (A heading over each kind of line.)
		local kind = reason.state == "off" and "off" or "now"
		if kind ~= lastState then
			local text
			if status == "unmanaged" then
				text = kind == "now" and L["NOT CINEMATIC'S"] or L["TO FADE IT"]
			elseif kind == "now" then
				text = status == "hidden" and L["KEEPING IT HIDDEN"] or L["SHOWN BECAUSE"]
			else
				text = status == "hidden" and L["ANY OF THESE WOULD SHOW IT"] or L["NOT SHOWING IT NOW"]
			end
			anchor = Heading(text, anchor, 12)
			height = height + 12 + anchor:GetStringHeight()
			lastState = kind
		end
		index = index + 1
		local line = ReasonLine(index)
		line.icon:SetTexture(ICON[reason.state])
		line.icon:SetDesaturated(reason.state == "off")
		line.text:SetText(reason.text)
		line.text:SetTextColor(reason.state == "off" and 0.62 or 1, reason.state == "off" and 0.58 or 1,
			reason.state == "off" and 0.52 or 1)
		line.page = reason.page
		line.where:SetText(reason.page and L["Settings: %s"]:format(L[reason.page]) or "")
		local lineHeight = line.text:GetStringHeight() + (reason.page and line.where:GetStringHeight() + 2 or 0) + 2
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
		line:SetSize(LINE_WIDTH + 20, lineHeight)
		line:Show()
		anchor = line
		height = height + 6 + lineHeight
	end
	for i = index + 1, #card.lines do card.lines[i]:Hide() end
	height = height + 16 + card.hint:GetStringHeight() + 8 + 24 + 14
	card:SetHeight(height)
end

local function PlaceCard()
	local ok, left, bottom, width, height = false, nil, nil, nil, nil
	if picked.frame then ok, left, bottom, width, height = pcall(EntryRect, picked) end
	local scale = UIParent:GetEffectiveScale()
	card:ClearAllPoints()
	if not (ok and left) then
		card:SetPoint("CENTER")
		return
	end
	local midX, midY = (left + width / 2) / scale, (bottom + height / 2) / scale
	-- (Beside it, on the side with more room.)
	if midX > UIParent:GetWidth() / 2 then
		card:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", left / scale - 16, midY)
	else
		card:SetPoint("LEFT", UIParent, "BOTTOMLEFT", (left + width) / scale + 16, midY)
	end
end

local function Pick(entry)
	picked = entry
	ns.whyLook[entry] = true
	if not card then MakeCard() end
	if not box.picked then
		box.picked = MakeBox()
		box.picked.back:Hide()
	end
	if entry.tooltip then box.picked:Hide() else PlaceOver(box.picked, entry) end
	card.elapsed = 1 -- (filled on its next frame, once UpdateFrames has noted it)
	Refresh()
	PlaceCard()
	card:Show()
end

local function MakeOverlay()
	overlay = CreateFrame("Frame", "CinematicInspect", UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata("FULLSCREEN_DIALOG")
	overlay:EnableMouse(true)
	tinsert(UISpecialFrames, "CinematicInspect") -- Escape stops it
	local bar = overlay:CreateTexture(nil, "BACKGROUND")
	bar:SetColorTexture(0, 0, 0, 0.75)
	local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("TOP", 0, -24)
	text:SetText(L["Inspect: click any frame to see why it's showing or hidden. Right-click or Escape to stop."])
	-- (A hidden tooltip can't be pointed at: the last one's card.)
	local tip = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
	tip:SetSize(110, 22)
	tip:SetText(L["Last tooltip"])
	tip:SetPoint("LEFT", text, "RIGHT", 12, 0)
	tip:SetScript("OnClick", function() Pick(tooltipStandIn) end)
	if ns.SkinButton then ns.SkinButton(tip) end
	bar:SetPoint("TOPLEFT", text, -12, 8)
	bar:SetPoint("BOTTOMRIGHT", tip, 12, -8)
	box = MakeBox()
	box.elapsed = 0
	overlay:SetScript("OnUpdate", function(_, elapsed)
		box.elapsed = box.elapsed + elapsed
		if box.elapsed < 0.05 then return end
		box.elapsed = 0
		-- (Ours first: they sit over the faded frames under them.)
		local ok, entry = pcall(OwnFrameUnderCursor)
		entry = ok and entry or EntryUnderCursor()
		if not entry then
			local found
			ok, found = pcall(AddonFrameUnderCursor)
			entry = ok and found or nil
		end
		box.entry = entry
		-- (Looked at for its label too.)
		local look = wipe(ns.whyLook)
		if picked then look[picked] = true end
		if entry then look[entry] = true end
		if entry and entry ~= picked and PlaceOver(box, entry) then
			local title, status = Explain(entry)
			box.label:SetText(("%s  %s"):format(title, StatusText(status)))
		else
			box:Hide()
		end
		if picked and box.picked and picked.frame then PlaceOver(box.picked, picked) end
	end)
	overlay:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			Stop()
		elseif box.entry then
			Pick(box.entry)
		end
	end)
	overlay:SetScript("OnHide", function() Stop() end)
end

function Stop()
	if not ns.whyPicking then return end
	ns.whyPicking, ns.whyLook, picked = nil, nil, nil
	if overlay then overlay:Hide() end
	if box then
		box:Hide()
		if box.picked then box.picked:Hide() end
	end
	if card then card:Hide() end
end

-- /cine debug why: what Inspect finds under the cursor, and why not.
function ns.DebugInspect()
	local x, y = GetCursorPosition()
	local focus = GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus()
	ns.Print(("inspect %s, cursor %.0f,%.0f, mouse on %s, CineMode %s, %d managed"):format(
		ns.whyPicking and "on" or "off", x, y, tostring(focus and focus.GetName and focus:GetName() or focus),
		tostring(ns.lastCinematic), #(ns.managed or NONE)))
	local found = 0
	for _, entry in ipairs(ns.managed or NONE) do
		local ok, left, bottom, width, height = pcall(EntryRect, entry)
		local over = ok and left and x >= left and x <= left + width and y >= bottom and y <= bottom + height
		if over or entry.group == "chat" then
			found = found + 1
			local frame = entry.frame
			print(("  %s %s [%s]: %s, alpha %.2f%s%s"):format(over and "UNDER" or "-", tostring(entry.name),
				tostring(entry.group), ok and left and ("%.0f,%.0f %.0fx%.0f"):format(left, bottom, width, height)
					or ("no rect" .. (ok and "" or " (error)")),
				tonumber(entry.alpha) or -1, entry.shrunk and " shrunk" or "",
				frame and frame.IsVisible and not ns.Flag(frame:IsVisible()) and " not visible" or ""))
		end
	end
	if found == 0 then print("  no managed frame under the cursor") end
	local okOwn, mine = pcall(OwnFrameUnderCursor)
	print(("  Cinematic's own frame: %s (%d known)"):format(okOwn and mine and mine.name or (okOwn and "none" or "error"),
		(function() local n = 0 for _ in pairs(own) do n = n + 1 end return n end)()))
	local under = EntryUnderCursor()
	local ok, other = pcall(AddonFrameUnderCursor)
	print(("  picks: %s; addon frame: %s"):format(under and tostring(under.name or under.group) or "none",
		ok and other and other.name .. " (" .. other.unmanaged .. ")" or (ok and "none" or "error " .. tostring(other))))
	local last = ns.lastTooltipWhy
	if last then
		print(("  last tooltip %s: hide %s (%s), %.0f sec ago, page on %s, CineMode %s"):format(tostring(last.name),
			tostring(last.hide), tostring(last.why), GetTime() - last.at, tostring(last.handled), tostring(last.cinematic)))
	end
end

function ns.ToggleInspect()
	if ns.whyPicking then
		Stop()
		return
	end
	if not overlay then MakeOverlay() end
	ns.whyPicking, ns.whyLook = true, {}
	overlay:Show()
end
