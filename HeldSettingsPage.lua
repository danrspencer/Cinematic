-- The dev copy's Held Game Settings page (the Dev hub): every game setting
-- the addon holds (ns.ApplyCVarSet; its sets named with ns.CVarSet where
-- they're made), live, as a grid of one row per setting of each set. Its
-- columns sort with a click on their heading (again: the other way). Saved
-- own values no set holds (db.savedCVars: camera speeds, music, view
-- distance, or left over) get rows too. A row's mouseover: what its set is
-- for. Only in CinematicDev.toc.
local _, ns = ...

local REFRESH = 0.5 -- seconds between updates while shown
local ROW_H = 16
local HELD_COLOR, FREE_COLOR, OWN_COLOR, BAD_COLOR = "|cff40ff40", "|cff777777", "|cff66ccff", "|cffff4040"

-- The columns: heading, share of the width, the row's field shown and how
-- it sorts (numbers by size; nil last either way).
local COLUMNS = {
	{ "Set", 0.19, "set" },
	{ "Setting", 0.23, "cvar" },
	{ "State", 0.07, "stateRank", numeric = true, tip = "Held: ours is written now. Free: the set has let go." },
	{ "Ours", 0.07, "ours", tip = "What the set writes while it holds the setting." },
	{ "Now", 0.07, "now", tip = "The setting's value right now (- : not on this client)." },
	{ "Yours", 0.07, "yours", tip = "The player's own value, saved: what goes back when it lets go." },
	{ "Sets", 0.05, "shared", numeric = true,
		tip = "How many sets hold this setting. Over 1: the first to let go puts yours back from under the rest." },
	{ "Holds", 0.06, "holds", numeric = true, tip = "How often the set took hold this session." },
	{ "Held", 0.095, "heldAt", numeric = true, tip = "When the set last took hold." },
	{ "Let go", 0.095, "letGoAt", numeric = true, tip = "When the set last let go." },
}

local function Ago(at)
	if not at then
		return "never"
	end
	local secs = GetTime() - at
	if secs < 60 then
		return ("%d s ago"):format(secs)
	elseif secs < 3600 then
		return ("%d min ago"):format(secs / 60)
	end
	return ("%.1f h ago"):format(secs / 3600)
end

-- The rows as they are now: { set, cvar, state, ours, now, yours, shared,
-- holds, heldAt, letGoAt, held (bool), why, flags }.
local function Gather()
	local saved = ns.db and ns.db.savedCVars or {}
	local count, heldBy = {}, {}
	for _, set in ipairs(ns.cvarSets) do
		for cvar in pairs(set.values) do
			count[cvar] = (count[cvar] or 0) + 1
			if set.active then heldBy[cvar] = true end
		end
	end
	local rows = {}
	for _, set in ipairs(ns.cvarSets) do
		local flags = {}
		if set.playerWins then flags[#flags + 1] = "your change wins" end
		if set.secure then flags[#flags + 1] = "not in fights" end
		for cvar, ours in pairs(set.values) do
			local now = GetCVar(cvar)
			rows[#rows + 1] = { set = set.label or "(no label)", cvar = cvar, held = set.active or false,
				state = set.active and "held" or "free", stateRank = set.active and 0 or 2,
				ours = tostring(ours), now = now ~= nil and tostring(now) or "-",
				yours = saved[cvar] ~= nil and tostring(saved[cvar]) or nil, shared = count[cvar],
				holds = set.holds or 0, heldAt = set.heldAt, letGoAt = set.letGoAt, why = set.why,
				flags = table.concat(flags, ", "), missing = now == nil }
		end
	end
	for cvar, value in pairs(saved) do
		if not count[cvar] then
			rows[#rows + 1] = { set = "(not a set)", cvar = cvar, held = false, state = "saved", stateRank = 1,
				now = tostring(GetCVar(cvar)),
				yours = tostring(value), shared = 0, holds = 0,
				why = "Saved outside the sets: a camera's speed, music, view distance... (or left over)" }
		elseif not heldBy[cvar] then
			-- (A set's setting saved while none of them holds it: nothing will put it back.)
			for _, row in ipairs(rows) do
				if row.cvar == cvar then row.leftOver = true end
			end
		end
	end
	return rows
end

local sortBy, sortDown = 3, false -- (held first to start)

local function Sort(rows)
	local field, numeric = COLUMNS[sortBy][3], COLUMNS[sortBy].numeric
	table.sort(rows, function(a, b)
		local x, y = a[field], b[field]
		if x ~= y then
			if x == nil or y == nil then
				return y == nil -- (nil last, either way)
			end
			if numeric then x, y = tonumber(x) or 0, tonumber(y) or 0 else x, y = tostring(x):lower(), tostring(y):lower() end
			if x ~= y then
				if sortDown then return x > y end
				return x < y
			end
		end
		if a.set ~= b.set then return a.set < b.set end
		return a.cvar < b.cvar
	end)
end

function ns.CreateHeldSettingsPage(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", "Held Game Settings")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title, "Every game setting the addon changes for a while and puts " ..
		"back after (ns.ApplyCVarSet), one row per setting of each set. Click a heading to sort by it. Name a new " ..
		"set with ns.CVarSet where it's made, or it shows as (no label).")
	local summary = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	summary:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
	summary:SetJustifyH("LEFT")

	local grid = CreateFrame("Frame", nil, content)
	grid:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -8)
	grid:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	grid:SetHeight(ROW_H)

	local Refresh
	-- Places a row's cells (or the headings) across the grid's width.
	local function Lay(cells)
		local width = grid:GetWidth() or 0
		local x = 0
		for i, column in ipairs(COLUMNS) do
			local cell = cells[i]
			cell:ClearAllPoints()
			cell:SetPoint("LEFT", cells.parent, "LEFT", x + 2, 0)
			cell:SetWidth(math.max(1, width * column[2] - 4))
			x = x + width * column[2]
		end
	end

	local headings = { parent = CreateFrame("Frame", nil, grid) }
	headings.parent:SetPoint("TOPLEFT")
	headings.parent:SetPoint("TOPRIGHT")
	headings.parent:SetHeight(ROW_H + 4)
	local line = headings.parent:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetColorTexture(0.45, 0.38, 0.2, 0.8)
	for i, column in ipairs(COLUMNS) do
		local button = CreateFrame("Button", nil, headings.parent)
		button:SetHeight(ROW_H)
		local text = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		text:SetAllPoints()
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		button.text = text
		button:SetScript("OnClick", function()
			if sortBy == i then sortDown = not sortDown else sortBy, sortDown = i, false end
			Refresh()
		end)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(column[1], 1, 0.82, 0)
			if column.tip then GameTooltip:AddLine(column.tip, 1, 1, 1, true) end
			GameTooltip:AddLine("Click to sort by it; again for the other way.", 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		headings[i] = button
	end

	local rowFrames = {}
	local function RowFrame(index)
		local row = rowFrames[index]
		if row then return row end
		row = CreateFrame("Button", nil, grid)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", 0, -(ROW_H + 6) - (index - 1) * ROW_H)
		row:SetPoint("RIGHT")
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.04 or 0)
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 0.82, 0, 0.08)
		local cells = { parent = row }
		for i in ipairs(COLUMNS) do
			local cell = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			cell:SetJustifyH("LEFT")
			cell:SetWordWrap(false)
			cells[i] = cell
		end
		row.cells = cells
		row:SetScript("OnEnter", function(self)
			local data = self.data
			if not data then return end
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
			GameTooltip:SetText(data.set .. ": " .. data.cvar, 1, 0.82, 0)
			if data.why then GameTooltip:AddLine(data.why, 1, 1, 1, true) end
			if data.flags and data.flags ~= "" then GameTooltip:AddLine(data.flags, 0.6, 0.6, 0.6, true) end
			if data.leftOver then
				GameTooltip:AddLine("Saved, but no set holds it now: nothing will put it back.", 1, 0.25, 0.25, true)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rowFrames[index] = row
		return row
	end

	function Refresh()
		local rows = Gather()
		Sort(rows)
		local sets, held = #ns.cvarSets, 0
		for _, set in ipairs(ns.cvarSets) do
			if set.active then held = held + 1 end
		end
		summary:SetText(("%d sets, %s%d held now|r. CineMode %s, in a fight %s."):format(sets, HELD_COLOR, held,
			ns.lastCinematic and HELD_COLOR .. "on|r" or "off", InCombatLockdown() and BAD_COLOR .. "yes|r" or "no"))
		Lay(headings)
		for i, column in ipairs(COLUMNS) do
			local arrow = sortBy == i and (sortDown and " |TInterface\\Buttons\\Arrow-Down-Up:10|t"
				or " |TInterface\\Buttons\\Arrow-Up-Up:10|t") or ""
			headings[i].text:SetText(column[1] .. arrow)
		end
		for index, data in ipairs(rows) do
			local row = RowFrame(index)
			row.data = data
			Lay(row.cells)
			local c = row.cells
			local dim = data.missing and FREE_COLOR or ""
			c[1]:SetText(dim .. data.set)
			c[2]:SetText(dim .. data.cvar)
			c[3]:SetText((data.held and HELD_COLOR or FREE_COLOR) .. data.state)
			c[4]:SetText(data.ours or "")
			c[5]:SetText(dim .. data.now)
			c[6]:SetText(data.yours and (data.leftOver and BAD_COLOR or OWN_COLOR) .. data.yours or "")
			c[7]:SetText((data.shared or 0) > 1 and BAD_COLOR .. data.shared or tostring(data.shared or ""))
			c[8]:SetText(data.holds > 0 and tostring(data.holds) or "")
			c[9]:SetText(data.heldAt and Ago(data.heldAt) or "")
			c[10]:SetText(data.letGoAt and Ago(data.letGoAt) or "")
			row:Show()
		end
		for index = #rows + 1, #rowFrames do
			rowFrames[index]:Hide()
			rowFrames[index].data = nil
		end
		grid:SetHeight(ROW_H + 6 + #rows * ROW_H)
	end

	local since = 0
	canvas:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < REFRESH then return end
		since = 0
		Refresh()
		kit.FitContentHeight(content)
	end)
	grid:SetScript("OnSizeChanged", function() if canvas:IsShown() then Refresh() end end)
	canvas:SetScript("OnShow", kit.PageShown(Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Held Game Settings", "Held Game Settings")
end
