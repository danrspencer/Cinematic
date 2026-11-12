-- The Why window (/cine why): every row of frames Cinematic fades in one
-- window you can keep up while you play, each saying in a line whether it's
-- showing and why, by section as the Game Frames page has them. At its top,
-- whether CineMode is on (and when it isn't, what's keeping it off) and what
-- you're doing right now. A row opens to all its reasons, a button to its
-- settings and one that points it out on the screen, and to its parts, each
-- a row of its own under it: a unit frame's (portrait, name, bars...: the
-- Game Frames page's part rows, ns.UnitPartsWhy), the raid and party frames'
-- and the minimap's (rows of their own, listed under their frame here). The
-- search box and the filters find parts too. Pick a frame on screen
-- starts Inspect (Why.lua), which comes back here when stopped; Copy report
-- gives the whole list as text to send us.
-- The reasons are Inspect's (ns.why.Explain); the list is filled twice a
-- second while the window is up, and nothing runs while it's closed.

local _, ns = ...
local L = ns.L
local why = ns.why

local GREEN, GREY, RED = "|cff8fe39a", "|cff9d9585", "|cffff4040"
local WIDTH, HEIGHT = 480, 620
local TOGGLE_WIDTH = 140 -- (the big CineMode button in the top box)
local LIST_WIDTH = WIDTH - 16 - 34 -- (the list's rows: the window less its edges and scroll bar)
local ROW_HEIGHT, HEADER_HEIGHT = 38, 24
local STATUS_COLOR = {
	shown = { 0.56, 0.89, 0.60 }, partly = { 1, 0.82, 0 }, hidden = { 0.95, 0.64, 0.64 },
	idle = { 0.5, 0.5, 0.5 }, unknown = { 0.5, 0.5, 0.5 },
}
-- The Game Frames page's sections, in its order, then the rest.
local SECTIONS = {
	{ "units", "Unit frames" }, { "prd", "Personal Resource Display" }, { "bars", "Action bars" },
	{ "combat", "Trackers" },
	{ "interface", "Info and menus" }, { "minimap", "Minimap" }, { "party", "Party frames (not raid-style)" },
	{ "raid", "Raid frames" }, { "rsparty", "Party frames (raid-style)" }, { "gamepad", "Gamepad" },
	{ "overhead", "Nameplates and chat bubbles" },
	{ "addons", "Other addons' frames" }, { "other", "Everything else" },
}
local SECTION_ORDER, SECTION_LABEL = {}, {}
for i, section in ipairs(SECTIONS) do
	SECTION_ORDER[section[1]], SECTION_LABEL[section[1]] = i, section[2]
end
-- (Addons: the rows of other addons' frames, whatever they're doing.)
local FILTERS = { { "all", "All" }, { "shown", "Showing" }, { "hidden", "Hidden" }, { "addons", "Addons" } }
local INDENT = 18 -- (a part's row, under its frame's)
-- The Game Frames rows that are unit frames, whose parts open under them there.
local UNIT_FRAME = { player = "PlayerFrame", petframe = "PetFrame", target = "TargetFrame", tot = "TargetFrameToT",
	focus = "FocusFrame", focustot = "FocusFrameToT" }
-- The rows that are parts of another row's frames, listed under it: by section, and the minimap's.
local PART_PARENT = { raid = "raidplayers", party = "party", rsparty = "rspartyplayers" }

local window, list, detail, flash
local filter, search, openKey, openParent = "all", "", nil, nil
local revealAll = false -- (every part listed, opened or not: Copy report's)
local items = {} -- (the rows as last filled, parts after their frames)
local Fill -- (below)

-- A row's place in the list: its section, and where it comes on the Game
-- Frames page; then the row it's a part of, if it's one.
local rowPlace
local function RowPlace(key)
	if not rowPlace then
		rowPlace = {}
		for i, item in ipairs(ns.COMBAT_SHOW) do
			local parent = (item.part and PART_PARENT[item.page])
				or (type(item.key) == "string" and item.key:find("^minimap.") and "minimap") or nil
			rowPlace[item.key] = { section = SECTION_ORDER[item.page] and item.page or nil, at = i, parent = parent }
		end
	end
	local place = rowPlace[key]
	local section = place and place.section
	if not section then
		section = type(key) == "string" and (key:find("^addon:") or key:find("^extra:")) and "addons" or "other"
	end
	return section, place and place.at or 1000, place and place.parent or nil
end

local function StatusText(status)
	if status == "idle" then return GREY .. L["NOT ON SCREEN"] .. "|r" end
	return why.StatusText(status)
end

-- Text as it reads, without the game's color codes (for the report and the search).
local function Bare(text)
	return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "|"))
end

-- What you're doing right now, in words: what the ticks and rules go by.
local function NowWords()
	local words = {}
	local fighting = InCombatLockdown() or ns.Flag(UnitAffectingCombat("player"))
	words[#words + 1] = fighting and L["in combat"] or (ns.InCalm() and L["just out of combat (Calm Timer)"])
		or L["out of combat"]
	if ns.HasTarget() then
		local enemy = ns.IsEnemyUnit("target") and not ns.Flag(UnitIsDeadOrGhost("target"))
		words[#words + 1] = enemy and L["targeting an enemy"] or L["targeting a friend"]
	else
		words[#words + 1] = L["no target"]
	end
	local place = ns.GetPlaceType()
	words[#words + 1] = (place == "city" and L["in a city"]) or (place == "dungeon" and L["in a dungeon"])
		or (place == "raid" and L["in a raid"]) or (place == "pvp" and L["in a battleground or arena"])
		or (place == "inn" and L["at an inn"]) or L["in the open world"]
	if ns.InGroup() then
		words[#words + 1] = ns.InRaid() and L["in a raid group"] or L["in a party"]
	end
	if IsMounted and ns.Flag(IsMounted()) then words[#words + 1] = L["mounted"] end
	return table.concat(words, ", ")
end

-- The line under a row's name: the first reason doing it now, else the first.
local function MainReason(reasons)
	for _, reason in ipairs(reasons) do
		if reason.state ~= "off" then return reason end
	end
	return reasons[1]
end

local function Kind(status)
	return ((status == "shown" or status == "partly") and "shown") or (status == "hidden" and "hidden") or nil
end

-- A unit frame's part as a row under its frame's: what the Game Frames
-- page's row for it says now (info: one of ns.UnitPartsWhy's).
local partLabels
local function UnitPartItem(parent, info, at)
	if not partLabels then
		partLabels = {}
		for _, each in ipairs(ns.UnitPartLabels and ns.UnitPartLabels() or {}) do partLabels[each[1]] = each[2] end
	end
	local page = "Standard Frames"
	local reasons, status = {}, "shown"
	local function Add(state, text, where)
		reasons[#reasons + 1] = { state = state, text = text, page = where }
	end
	if info.over == "hide" then
		status = "hidden"
		Add("block", L["The Style hub's Overrides tab hides it, whatever its row says"], "Style Overrides")
	elseif info.over then
		Add("on", L["The Style hub's Overrides tab keeps it shown, whatever its row says"], "Style Overrides")
	elseif info.pageOff then
		Add("on", L["The Game Frames page is switched off, so every part shows as the game has it"], page)
	else
		status = (info.hidden or info.held) and "hidden" or "shown"
		if info.held then
			Add("block", L["Its frame is up only for the mouse or a Hover group, and this part is left out of that"],
				"Mouseover groups")
		end
		-- (Its row's ticks or rule: Always is the part's own setting, and In combat counts in any fight.)
		local columns = {}
		why.Columns(info.key, columns, ns.db[info.key] ~= false, true, page)
		for _, reason in ipairs(columns) do
			if reason.state ~= "off" then reasons[#reasons + 1] = reason end
		end
		if status == "hidden" and #reasons == 0 then
			Add("block", L["Always is unticked on its row, and nothing else ticked there applies right now"], page)
		end
		for _, reason in ipairs(columns) do
			if reason.state == "off" then reasons[#reasons + 1] = reason end
		end
		if info.same then
			Add("off", L["It goes by the Target's rows (Same as target is ticked)"], page)
		end
	end
	-- (With its frame hidden or away, so is it, whatever its own row says.)
	if parent.status == "hidden" then
		status = "hidden"
		table.insert(reasons, 1, { state = "block", text = L["Its frame is hidden, so all of it is"] })
	elseif parent.status == "idle" then
		status = "idle"
		table.insert(reasons, 1, { state = "on", text = L["Its frame isn't on screen right now"] })
	end
	return { key = "part:" .. tostring(parent.key) .. ":" .. info.part, parent = parent, entry = parent.entry,
		title = partLabels[info.part] or info.part, status = status, kind = Kind(status), reasons = reasons,
		main = MainReason(reasons), section = parent.section, sectionLabel = parent.sectionLabel, at = at,
		settingsPage = page }
end

-- Whether a row is in the list as filtered and searched (a part: by its own name).
local function Matches(item, words)
	if not (filter == "all" or (filter == "addons" and item.section == "addons") or filter == item.kind) then
		return false
	end
	return words == "" or item.title:lower():find(words, 1, true) ~= nil
		or (not item.parent and item.sectionLabel:lower():find(words, 1, true) ~= nil)
end

-- The rows, each with its status and reasons, in the list's order, a frame's
-- parts after it (those to list: all of them while it's open, else the ones
-- the filter or the search asks for); and how many rows, parts too, are
-- showing, hidden, addons' and in all (before the filter and the search).
local function Gather()
	local order, first = why.RowEntries()
	why.LookAtRows(order, first)
	local counts = { all = 0, shown = 0, hidden = 0, addons = 0 }
	local byKey, tops = {}, {}
	for _, key in ipairs(order) do
		local info = first[key]
		local ok, title, status, reasons = pcall(why.Explain, info.entry)
		if ok then
			-- (Not hidden by Cinematic, and not drawn by the game either: no
			-- target, no group, a bar switched off.)
			if (status == "shown" or status == "partly") and not info.onScreen then
				status = "idle"
				table.insert(reasons, 1, { state = "on",
					text = L["Cinematic isn't hiding it: the game has nothing to show there right now"] })
				table.insert(reasons, 2, { state = "on", text = L["For example: no target, no group, or it's switched " ..
					"off in the game's own options or by another addon"] })
			end
			local section, at, parent = RowPlace(key)
			byKey[key] = { key = key, entry = info.entry, title = tostring(title), status = status, kind = Kind(status),
				reasons = reasons, main = MainReason(reasons), section = section, sectionLabel = L[SECTION_LABEL[section]],
				at = at, parentKey = parent }
		end
	end
	-- The rows that are parts go under their frame's row, when it's listed.
	for _, key in ipairs(order) do
		local item = byKey[key]
		local parent = item and item.parentKey and item.parentKey ~= key and byKey[item.parentKey]
		if parent then
			item.parent = parent
			parent.parts = parent.parts or {}
			parent.parts[#parent.parts + 1] = item
		elseif item then
			tops[#tops + 1] = item
		end
	end
	for _, item in ipairs(tops) do
		local name = UNIT_FRAME[item.key]
		local ok, parts = pcall(ns.UnitPartsWhy or tostring, name)
		if name and ok and type(parts) == "table" then
			item.parts = item.parts or {}
			for i, info in ipairs(parts) do
				local okPart, part = pcall(UnitPartItem, item, info, i)
				if okPart then item.parts[#item.parts + 1] = part end
			end
		end
		if item.parts then
			table.sort(item.parts, function(a, b) return a.at < b.at end)
		end
	end
	-- Nameplates and chat bubbles: a row each for its whole page (one per unit
	-- would be a row for everyone nearby), with no frame to point at.
	for i, overhead in ipairs({ { "overhead:plates", "Nameplates", ns.PlatesWhy },
		{ "overhead:bubbles", "Chat Bubbles", why.BubblesWhy } }) do
		local ok, status, reasons = pcall(overhead[3] or error)
		if ok and type(reasons) == "table" then
			local item = { key = overhead[1], title = L[overhead[2]], status = status, kind = Kind(status),
				reasons = reasons, main = MainReason(reasons), section = "overhead",
				sectionLabel = L[SECTION_LABEL.overhead], at = i, wholePage = true, settingsPage = overhead[2] == "Nameplates"
					and "Nameplates" or "Chat bubbles" }
			tops[#tops + 1] = item
			-- The nameplates showing now, each a row under it with what holds
			-- it up (ns.PlateItemsWhy, Effects): listed while it's open.
			local okPlates, plates = pcall(overhead[2] == "Nameplates" and ns.PlateItemsWhy or tostring)
			if okPlates and type(plates) == "table" and #plates > 0 then
				item.parts, item.partsLabel = {}, L["%d plates"]
				for at, plate in ipairs(plates) do
					item.parts[at] = { key = "plate:" .. plate.key, parent = item, title = plate.title, status = plate.status,
						kind = Kind(plate.status), reasons = plate.reasons, main = MainReason(plate.reasons),
						section = item.section, sectionLabel = item.sectionLabel, at = at, wholePage = true,
						settingsPage = "Nameplates" }
				end
			end
		end
	end
	table.sort(tops, function(a, b)
		if a.section ~= b.section then return SECTION_ORDER[a.section] < SECTION_ORDER[b.section] end
		if a.at ~= b.at then return a.at < b.at end
		if a.title ~= b.title then return a.title < b.title end
		return tostring(a.key) < tostring(b.key)
	end)
	local found = wipe(items)
	local words = search:lower()
	local narrowed = filter ~= "all" or words ~= ""
	local function Count(item)
		counts.all = counts.all + 1
		if item.kind then counts[item.kind] = counts[item.kind] + 1 end
		if item.section == "addons" then counts.addons = counts.addons + 1 end
	end
	for _, item in ipairs(tops) do
		Count(item)
		local open = revealAll or openKey == item.key or openParent == item.key
		local own = Matches(item, words)
		local listed, any = {}, false
		for _, part in ipairs(item.parts or {}) do
			Count(part)
			local match = Matches(part, words)
			any = any or match
			if (open and (own or not narrowed)) or (narrowed and match) or revealAll then
				listed[#listed + 1] = part
			end
		end
		if own or any or revealAll then
			found[#found + 1] = item
			for _, part in ipairs(listed) do found[#found + 1] = part end
		end
	end
	return found, counts
end

-- The heading over a row's reasons: those doing it now, then those that would.
local function HeadingText(status, kind)
	if kind == "off" then
		return status == "hidden" and L["ANY OF THESE WOULD SHOW IT"] or L["NOT SHOWING IT NOW"]
	end
	return (status == "hidden" and L["KEEPING IT HIDDEN"]) or (status == "idle" and L["RIGHT NOW"])
		or L["SHOWN BECAUSE"]
end

-- Points a row's frame out on the screen for a few seconds: a gold box
-- where it is (or where it would be, faded out).
local function PointOut(item)
	if not flash then flash = why.MakeBox() end
	if not why.PlaceOver(flash, item.entry) then
		ns.Print(L["%s isn't on the screen right now, so there's nothing to point at."]:format(item.title))
		return
	end
	flash.label:SetText(("%s  %s"):format(item.title, StatusText(item.status)))
	flash.endsAt = GetTime() + 4
	ns.SetOnUpdate(flash, function(self)
		local left = self.endsAt - GetTime()
		if left <= 0 then
			self:Hide()
			ns.SetOnUpdate(self, nil)
		else
			-- (Blinking, so it's found at a glance.)
			self:SetAlpha(0.55 + 0.45 * math.abs(math.sin(left * 4)))
		end
	end)
end

local function CopyReport()
	-- (Every row, whatever the list is showing; the next fill puts the list back.)
	local keptFilter, keptSearch = filter, search
	filter, search, revealAll = "all", "", true
	local found = Gather()
	filter, search, revealAll = keptFilter, keptSearch, false
	local out = {}
	out[#out + 1] = ("Cinematic %s, %s"):format(ns.Version and ns.Version() or "?",
		ns.isRetail and "retail" or ("game " .. tostring(select(4, GetBuildInfo()))))
	if ns.lastCinematic then
		out[#out + 1] = "CineMode: ON"
	else
		out[#out + 1] = "CineMode: OFF - " .. Bare(ns.CineOffReason())
	end
	out[#out + 1] = "Right now: " .. NowWords()
	local calmLeft, calmTotal = ns.CalmLeft()
	if calmLeft then
		local full = ns.CalmFullLeft and ns.CalmFullLeft()
		out[#out + 1] = ("Calm Timer: %.0f of %.0f sec left%s"):format(calmLeft, calmTotal,
			full and (", health and power full: ends in %.0f"):format(full) or "")
	end
	local section
	for _, item in ipairs(found) do
		if item.section ~= section then
			section = item.section
			out[#out + 1] = ""
			out[#out + 1] = "== " .. item.sectionLabel .. " =="
		end
		local pad = item.parent and "    " or ""
		out[#out + 1] = ("%s[%s] %s"):format(pad, Bare(StatusText(item.status)), item.title)
		for _, reason in ipairs(item.reasons) do
			out[#out + 1] = ("%s    %s %s%s"):format(pad, reason.state == "on" and "+" or (reason.state == "block" and "x") or "-",
				Bare(reason.text), reason.page and (" (" .. ns.PageLabel(reason.page) .. ")") or "")
		end
	end
	ns.ShowReportText(L["Why is it showing? report"], L["Press Ctrl+C to copy this, then paste it to us on Discord " ..
		"or in a bug report. It lists each row of frames and its parts, whether it's showing, and why."], table.concat(out, "\n"))
end

-- A settings link: its page opened at the setting behind it (setting: its
-- id, ns.OpenSettingByKey), glowing; else, on the row's own page (Game
-- Frames, Game Frames...), at its row there by its name; else the page alone.
-- (By name only there: another page can have a label like the row's, the
-- Personal Resource Display page's "Player frame" heading.)
local function OpenAtRow(page, setting)
	local item = detail and detail.item
	local ownPage = item and (item.settingsPage or why.FramePage(item.key))
	local title = item and not item.wholePage and page == ownPage and item.title
	if ns.OpenOptionsAt and (setting or type(title) == "string") then
		ns.OpenOptionsAt(page, title or nil, setting)
	else
		ns.OpenOptions(page)
	end
end

-- A row's reasons, under it while it's open: one frame, moved to the open row.
local function DetailLine(index)
	local line = detail.lines[index]
	if line then return line end
	line = CreateFrame("Button", nil, detail)
	line.icon = line:CreateTexture(nil, "ARTWORK")
	line.icon:SetSize(14, 14)
	line.icon:SetPoint("TOPLEFT", 0, -1)
	line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	line.text:SetPoint("TOPLEFT", line.icon, "TOPRIGHT", 6, 0)
	line.text:SetWidth(LIST_WIDTH - 46)
	line.text:SetJustifyH("LEFT")
	line.where = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	line.where:SetPoint("TOPLEFT", line.text, "BOTTOMLEFT", 0, -2)
	line.where:SetJustifyH("LEFT")
	local glow = line:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 0.82, 0, 0.08)
	line:SetScript("OnClick", function(self)
		if self.page then OpenAtRow(self.page, self.setting) end
	end)
	detail.lines[index] = line
	return line
end

local function DetailHeading(index)
	local heading = detail.headings[index]
	if not heading then
		heading = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		heading:SetJustifyH("LEFT")
		detail.headings[index] = heading
	end
	return heading
end

-- Fills it for a row; gives its height.
local function FillDetail(item)
	detail.item = item
	local width = LIST_WIDTH - 14 - (item.parent and INDENT or 0)
	local y, lines, headings, lastKind = 2, 0, 0, nil
	for _, reason in ipairs(item.reasons) do
		local kind = reason.state == "off" and "off" or "now"
		if kind ~= lastKind then
			headings = headings + 1
			local heading = DetailHeading(headings)
			heading:ClearAllPoints()
			heading:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, -(y + 4))
			heading:SetText(HeadingText(item.status, kind))
			heading:Show()
			y = y + 4 + heading:GetStringHeight() + 4
			lastKind = kind
		end
		lines = lines + 1
		local line = DetailLine(lines)
		local off = reason.state == "off"
		line.icon:SetTexture(why.ICON[reason.state])
		line.icon:SetDesaturated(off)
		line.text:SetText(reason.text)
		line.text:SetTextColor(off and 0.62 or 1, off and 0.58 or 1, off and 0.52 or 1)
		line.page, line.setting = reason.page, reason.setting
		line.where:SetText(reason.page and L["Settings: %s"]:format(ns.PageLabel(reason.page)) or "")
		line.text:SetWidth(width - 32)
		local height = line.text:GetStringHeight() + (reason.page and line.where:GetStringHeight() + 2 or 0) + 2
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, -y)
		line:SetSize(width - 10, height)
		line:Show()
		y = y + height + 5
	end
	for i = lines + 1, #detail.lines do detail.lines[i]:Hide() end
	for i = headings + 1, #detail.headings do detail.headings[i]:Hide() end
	detail.open:ClearAllPoints()
	detail.open:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, -(y + 4))
	-- (The page of what's doing it now, else the row's own.)
	detail.open.page = (item.main and item.main.page) or item.settingsPage or why.FramePage(item.key)
	detail.open.setting = item.main and item.main.page == detail.open.page and item.main.setting or nil
	detail:SetWidth(width)
	y = y + 4 + 22 + 10
	detail:SetHeight(y)
	return y
end

local function MakeDetail()
	detail = CreateFrame("Frame", nil, list)
	detail.lines, detail.headings = {}, {}
	detail.open = ns.PanelButton(detail)
	detail.open:SetSize(120, 22)
	detail.open:SetText(L["Open settings"])
	detail.open:SetScript("OnClick", function(self)
		if self.page then OpenAtRow(self.page, self.setting) end
	end)
	detail.point = ns.PanelButton(detail)
	detail.point:SetSize(150, 22)
	detail.point:SetText(L["Show me where it is"])
	detail.point:SetPoint("LEFT", detail.open, "RIGHT", 8, 0)
	detail.point:SetScript("OnClick", function()
		if detail.item then PointOut(detail.item) end
	end)
end

local function Row(index)
	local row = list.rows[index]
	if row then return row end
	row = CreateFrame("Button", nil, list)
	row:SetSize(LIST_WIDTH, ROW_HEIGHT)
	local glow = row:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 0.82, 0, 0.08)
	-- (Its status as a stripe down its left edge, to read the list at a glance.)
	row.stripe = row:CreateTexture(nil, "ARTWORK")
	row.stripe:SetPoint("TOPLEFT", 0, -3)
	row.stripe:SetSize(3, ROW_HEIGHT - 6)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", 12, -4)
	row.name:SetWidth(LIST_WIDTH - 12 - 120)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.status:SetPoint("TOPRIGHT", -6, -6)
	row.status:SetJustifyH("RIGHT")
	row.reason = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.reason:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.reason:SetWidth(LIST_WIDTH - 12 - 8)
	row.reason:SetJustifyH("LEFT")
	row.reason:SetWordWrap(false)
	row.reason:SetTextColor(0.78, 0.76, 0.7)
	-- (A frame with parts: how many, listed under it while it's open.)
	row.parts = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.parts:SetPoint("BOTTOMRIGHT", -6, 7)
	row.parts:SetJustifyH("RIGHT")
	row:SetScript("OnClick", function(self)
		if openKey ~= self.key then
			openKey, openParent = self.key, self.parentKey
		else
			-- (A part closed: back to its frame, its parts still listed.)
			openKey, openParent = self.parentKey, nil
		end
		Fill()
	end)
	list.rows[index] = row
	return row
end

local function Header(index)
	local header = list.headers[index]
	if header then return header end
	header = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetJustifyH("LEFT")
	header:SetTextColor(0.62, 0.58, 0.52)
	header.line = list:CreateTexture(nil, "ARTWORK")
	header.line:SetColorTexture(1, 1, 1, 0.12)
	header.line:SetHeight(1)
	header.line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, -3)
	header.line:SetWidth(LIST_WIDTH)
	list.headers[index] = header
	return header
end

function Fill()
	if not (window and list and detail and ns.Flag(window:IsShown())) then return end
	-- The top: CineMode on or off, and what's keeping it off.
	local banner = window.banner
	if ns.lastCinematic then
		banner.stripe:SetColorTexture(0.56, 0.89, 0.60)
		banner.back:SetColorTexture(1, 1, 1, 0.05)
		banner.title:SetText(L["CineMode is %s"]:format(GREEN .. L["ON"] .. "|r"))
		banner.text:SetText(L["Cinematic is hiding parts of your interface. Each row below says whether it's " ..
			"showing right now, and why."])
		banner.page = "CineMode"
	else
		local text, page = ns.CineOffReason()
		-- (Off: red, so it can't be missed.)
		banner.stripe:SetColorTexture(1, 0.25, 0.25)
		banner.back:SetColorTexture(1, 0.15, 0.15, 0.18)
		banner.title:SetText(L["CineMode is %s"]:format(RED .. L["OFF"] .. "|r"))
		banner.text:SetText(L["So Cinematic isn't hiding anything right now."] .. " " .. text)
		banner.page = page
	end
	banner.now:SetText(L["Right now you are: %s"]:format(NowWords()))
	banner.toggle:SetText(ns.IsCineModeOn() and L["Turn CineMode Off"] or L["Turn CineMode On"])
	banner:SetHeight(math.max(34 + 20, 10 + banner.title:GetStringHeight() + 4 + banner.text:GetStringHeight() + 6
		+ banner.now:GetStringHeight() + 10))

	local found, counts = Gather()
	for _, button in ipairs(window.filters) do
		local chosen = button.key == filter
		button:SetText(("%s (%d)"):format(L[button.label], counts[button.key]))
		if chosen then button:LockHighlight() else button:UnlockHighlight() end
		local text = button:GetFontString()
		if text then
			if chosen then text:SetTextColor(1, 0.82, 0) else text:SetTextColor(1, 1, 1) end
		end
	end

	local y, rows, headers, section, opened = 0, 0, 0, nil, false
	-- The Calm Timer, while it runs: a bar of the time left, over the first section.
	local calmBar = window.calmBar
	local calmLeft = ns.CalmLeft()
	calmBar:SetShown(calmLeft ~= nil)
	if calmLeft then
		calmBar:ClearAllPoints()
		calmBar:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -6)
		y = y + 6 + calmBar:GetHeight() + 2
	end
	for _, item in ipairs(found) do
		if item.section ~= section then
			section = item.section
			headers = headers + 1
			local header = Header(headers)
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -(y + 8))
			header:SetText(item.sectionLabel:upper())
			header:Show()
			header.line:Show()
			y = y + HEADER_HEIGHT
		end
		rows = rows + 1
		local row = Row(rows)
		local indent = item.parent and INDENT or 0
		local count = item.parts and #item.parts or 0
		row.key, row.parentKey = item.key, item.parent and item.parent.key or nil
		local color = STATUS_COLOR[item.status] or STATUS_COLOR.unknown
		row.stripe:SetColorTexture(color[1], color[2], color[3])
		row.stripe:SetPoint("TOPLEFT", indent, -3)
		row.name:SetPoint("TOPLEFT", 12 + indent, -4)
		row.name:SetWidth(LIST_WIDTH - 12 - 120 - indent)
		row.name:SetText(item.title)
		if item.parent then row.name:SetTextColor(0.9, 0.86, 0.74) else row.name:SetTextColor(1, 0.82, 0) end
		row.status:SetText(StatusText(item.status))
		row.reason:SetWidth(LIST_WIDTH - 12 - 8 - indent - (count > 0 and 70 or 0))
		row.reason:SetText(item.main and item.main.text or "")
		row.parts:SetText(count > 0 and (item.partsLabel or L["%d parts"]):format(count) or "")
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
		row:Show()
		y = y + ROW_HEIGHT
		if item.key == openKey then
			opened = true
			local height = FillDetail(item)
			detail:ClearAllPoints()
			detail:SetPoint("TOPLEFT", list, "TOPLEFT", 14 + indent, -y)
			detail.point:SetShown(item.entry ~= nil)
			detail:Show()
			y = y + height
		end
	end
	for i = rows + 1, #list.rows do list.rows[i]:Hide() end
	for i = headers + 1, #list.headers do
		list.headers[i]:Hide()
		list.headers[i].line:Hide()
	end
	if not opened then detail:Hide() end
	window.empty:SetShown(rows == 0)
	if rows == 0 then
		window.empty:SetText((counts.all == 0 and L["Cinematic isn't fading any frames right now: its frame pages " ..
			"are off, or it has only just started. Give it a moment."])
			or (search ~= "" and L["Nothing here is called \"%s\"."]:format(search))
			or (filter == "addons" and L["No other addon's frames are being faded. Cinematic fades the addons it " ..
				"knows and the frames you add on the Addon Frames page. For any other frame, use Pick a frame on screen."])
			or L["Nothing in this list right now."])
	end
	-- (Addons: only those Cinematic fades have a row.)
	local note = window.note
	note:SetShown(filter == "addons" and rows > 0)
	if filter == "addons" and rows > 0 then
		note:ClearAllPoints()
		note:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -(y + 12))
		y = y + 12 + note:GetStringHeight()
	end
	list:SetHeight(math.max(1, y + 8))
end

local function MakeWindow()
	window = CreateFrame("Frame", "CinematicWhyWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate")
	window:SetSize(WIDTH, HEIGHT)
	window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	-- (Dragged by any empty part of it, out of the way of what you're looking at.)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	if window.SetBackdrop then
		window:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
	end
	if ns.SkinWindow then ns.SkinWindow(window) end
	tinsert(UISpecialFrames, "CinematicWhyWindow") -- Escape closes it

	local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText(L["Why Is It Showing/Hiding?"])
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	if ns.SkinClose then ns.SkinClose(close) end
	close:SetPoint("TOPRIGHT", -2, -2)

	-- CineMode on or off, why, and what you're doing: click it for the setting.
	local banner = CreateFrame("Button", nil, window)
	banner:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	banner:SetSize(WIDTH - 32, 70)
	banner.back = banner:CreateTexture(nil, "BACKGROUND")
	banner.back:SetAllPoints()
	banner.back:SetColorTexture(1, 1, 1, 0.05)
	local glow = banner:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 0.82, 0, 0.06)
	banner.stripe = banner:CreateTexture(nil, "ARTWORK")
	banner.stripe:SetPoint("TOPLEFT")
	banner.stripe:SetPoint("BOTTOMLEFT")
	banner.stripe:SetWidth(3)
	banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	banner.title:SetPoint("TOPLEFT", 12, -10)
	banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	banner.text:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -4)
	-- (The text leaves room on the right for the CineMode button.)
	banner.text:SetWidth(WIDTH - 32 - 24 - TOGGLE_WIDTH - 10)
	banner.text:SetJustifyH("LEFT")
	banner.now = banner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	banner.now:SetPoint("TOPLEFT", banner.text, "BOTTOMLEFT", 0, -6)
	banner.now:SetWidth(WIDTH - 32 - 24 - TOGGLE_WIDTH - 10)
	banner.now:SetJustifyH("LEFT")
	banner:SetScript("OnClick", function(self) ns.OpenOptions(self.page) end)
	-- A big button that turns CineMode on or off (the Toggle CineMode key).
	local toggle = ns.PanelButton(banner)
	toggle:SetSize(TOGGLE_WIDTH, 34)
	toggle:SetPoint("RIGHT", banner, "RIGHT", -10, 0)
	toggle:SetScript("OnClick", function()
		Cinematic_ToggleCineMode()
		Fill()
	end)
	banner.toggle = toggle
	window.banner = banner

	-- Find a row by name, and the filters with their counts.
	local okBox, box = pcall(CreateFrame, "EditBox", nil, window, "SearchBoxTemplate")
	if not okBox then box = CreateFrame("EditBox", nil, window, "InputBoxTemplate") end
	-- (Across the top of the list, the filters under it.)
	box:SetSize(WIDTH - 32 - 8, 20)
	box:SetAutoFocus(false)
	box:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 6, -10)
	box:HookScript("OnTextChanged", function(self)
		local text = self:GetText()
		search = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
		Fill()
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	window.filters = {}
	for i, info in ipairs(FILTERS) do
		local button = ns.PanelButton(window)
		button:SetSize(106, 22)
		button.key, button.label = info[1], info[2]
		if i == 1 then
			button:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -8)
		else
			button:SetPoint("LEFT", window.filters[i - 1], "RIGHT", 4, 0)
		end
		button:SetScript("OnClick", function(self)
			filter = self.key
			Fill()
		end)
		window.filters[i] = button
	end

	-- At the bottom: Inspect, the report, and how to read the list.
	local pick = ns.PanelButton(window)
	pick:SetSize(180, 24)
	pick:SetText(L["Pick a frame on screen"])
	pick:SetPoint("BOTTOMLEFT", 16, 14)
	pick:SetScript("OnClick", function()
		window:Hide()
		if not ns.whyPicking then ns.ToggleInspect() end
		ns.whyBackToWindow = true -- (stopped by hand, it comes back here: Why.lua)
	end)
	local report = ns.PanelButton(window)
	report:SetSize(120, 24)
	report:SetText(L["Copy report"])
	report:SetPoint("LEFT", pick, "RIGHT", 8, 0)
	report:SetScript("OnClick", CopyReport)
	local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", pick, "TOPLEFT", 0, 8)
	hint:SetWidth(WIDTH - 32)
	hint:SetHeight(36) -- (three lines' room, so the list's bottom edge stays put)
	hint:SetJustifyH("LEFT")
	hint:SetJustifyV("BOTTOM")
	hint:SetText(L["Click a row for all its reasons and its settings. It keeps itself up to date: start a fight " ..
		"or target something and watch it change. A frame with parts lists them under it. Not in the list? Pick it on screen."])

	local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
	if ns.SkinScroll then ns.SkinScroll(scroll) end
	scroll:SetPoint("TOPLEFT", window.filters[1], "BOTTOMLEFT", 0, -8)
	scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -34, 14 + 24 + 8 + 36 + 8) -- (over the hint and buttons)
	list = CreateFrame("Frame", nil, scroll)
	list:SetSize(LIST_WIDTH, 1)
	list.rows, list.headers = {}, {}
	scroll:SetScrollChild(list)
	window.empty = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	window.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -16)
	window.empty:SetWidth(LIST_WIDTH - 8)
	window.empty:SetJustifyH("LEFT")
	window.note = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	window.note:SetWidth(LIST_WIDTH - 8)
	window.note:SetJustifyH("LEFT")
	window.note:SetText(L["Only frames Cinematic fades are listed: the addons it knows, and the frames you add on the " ..
		"Addon Frames page. For any other addon's frame, use Pick a frame on screen."])
	MakeDetail()

	-- The Calm Timer bar (placed by Fill, at the list's top while it runs):
	-- its time left, draining every frame; click it for its setting.
	local calmBar = CreateFrame("Button", nil, list)
	calmBar:SetSize(LIST_WIDTH, 34)
	calmBar.back = calmBar:CreateTexture(nil, "BACKGROUND")
	calmBar.back:SetAllPoints()
	calmBar.back:SetColorTexture(1, 1, 1, 0.05)
	local calmGlow = calmBar:CreateTexture(nil, "HIGHLIGHT")
	calmGlow:SetAllPoints()
	calmGlow:SetColorTexture(1, 0.82, 0, 0.08)
	calmBar.label = calmBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	calmBar.label:SetPoint("TOPLEFT", 10, -4)
	calmBar.label:SetText(L["Calm Timer"])
	calmBar.left = calmBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	calmBar.left:SetPoint("TOPRIGHT", -8, -4)
	calmBar.left:SetJustifyH("RIGHT")
	calmBar.track = calmBar:CreateTexture(nil, "ARTWORK")
	calmBar.track:SetPoint("BOTTOMLEFT", 10, 6)
	calmBar.track:SetSize(LIST_WIDTH - 18, 6)
	calmBar.track:SetColorTexture(0, 0, 0, 0.5)
	calmBar.fill = calmBar:CreateTexture(nil, "OVERLAY")
	calmBar.fill:SetPoint("LEFT", calmBar.track, "LEFT")
	calmBar.fill:SetHeight(6)
	calmBar.fill:SetColorTexture(1, 0.82, 0, 0.85)
	calmBar:SetScript("OnClick", function()
		if not (ns.OpenSettingByKey and ns.OpenSettingByKey("calmTime")) then ns.OpenOptions("CineMode") end
	end)
	calmBar:Hide()
	window.calmBar = calmBar
	local function DrawCalm()
		local left, total = ns.CalmLeft()
		if not left then return end
		local full = ns.CalmFullLeft and ns.CalmFullLeft()
		if full and full < left then
			calmBar.left:SetText(L["%.0f sec (health and power full: ends in %.0f)"]:format(left, full))
		else
			calmBar.left:SetText(L["%.0f sec left"]:format(left))
		end
		local width = (LIST_WIDTH - 18) * (total > 0 and math.min(1, left / total) or 0)
		calmBar.fill:SetWidth(math.max(0.01, width))
		calmBar.fill:SetShown(width > 0.5)
	end

	local elapsedSince = 0
	ns.SetOnUpdate(window, function(_, elapsed)
		if ns.Flag(calmBar:IsShown()) then DrawCalm() end
		elapsedSince = elapsedSince + elapsed
		if elapsedSince > 0.5 then
			elapsedSince = 0
			Fill()
		end
	end)
	window:SetScript("OnShow", function()
		-- (Filled at once, and again as soon as UpdateFrames has noted the rows.)
		elapsedSince = 0.3
		Fill()
	end)
	window:SetScript("OnHide", function()
		window:StopMovingOrSizing()
		if flash then flash:Hide() end
		why.LookAway()
	end)
end

function ns.ShowWhyWindow()
	if not window then
		MakeWindow()
		window:Hide()
	end
	window:Show()
end

-- /cine why: the window, or away with it (and with Inspect, started from it).
function ns.ToggleWhyWindow()
	if ns.whyPicking then
		ns.ToggleInspect()
	elseif window and ns.Flag(window:IsShown()) then
		window:Hide()
	else
		ns.ShowWhyWindow()
	end
end

-- What the window lists now (its rows and counts), for checks outside the game.
function ns.WhyWindowRows()
	return Gather()
end
