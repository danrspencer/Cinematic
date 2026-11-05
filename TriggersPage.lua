-- Cinematic: the Triggers page (Camera hub) for TriggerLibrary.lua's
-- triggers. One icon, three folder tabs: Triggers (every trigger, ours and
-- yours, a row each), Priority (the order they win in, moved with the
-- arrows) and Log (what fired, what was held back and why). A trigger's own
-- page opens from its row (Trigger Settings, no tab of its own): what
-- starts it, Only if, what ends it, its timing, its priority and the
-- scenes using it. Our own triggers show their place and their scene; the
-- rest of them is still in their cameras' code.
local _, ns = ...
local L = ns.L

local WIDTH = 560
local ROW_H = 22
-- The trigger a Trigger Settings page shows: a library id, or "b:<key>" for one of ours.
local PAGE = { now = nil, show = "all", by = "group" }

local KIND_ICONS = { spell = "Interface\\Icons\\Spell_Nature_Lightning",
	emote = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", aura = "Interface\\Icons\\Spell_Holy_WordFortitude",
	place = "Interface\\Icons\\INV_Misc_Map_01", moment = "Interface\\Icons\\INV_Misc_PocketWatch_01",
	state = "Interface\\Icons\\Spell_Holy_MindVision", interact = "Interface\\Icons\\INV_Misc_Note_01",
	key = "Interface\\Icons\\INV_Misc_Key_03", chat = "Interface\\Icons\\INV_Scroll_03" }
local KIND_NAMES = { chat = "Chat" }
local function KindName(kind)
	for _, each in ipairs(ns.CUSTOM_TRIGGER_KINDS) do
		if each.value == kind then return each.text end
	end
	return L[KIND_NAMES[kind] or tostring(kind)]
end
-- A trigger's icon: a spell's own where it names one, else its kind's.
local function IconOf(kind, what)
	if (kind == "spell" or kind == "aura") and what and what ~= "" then
		local id = tonumber(what) or what
		local ok, texture = pcall(function()
			return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
				or (GetSpellTexture and GetSpellTexture(id))
		end)
		if ok and texture then return texture end
	end
	return KIND_ICONS[kind] or KIND_ICONS.moment
end
local function Src(id)
	local kind, what = tostring(ns.TriggerField(id, "src") or ""):match("^(%a+):(.*)$")
	return kind or "emote", what or ""
end

-- Opens a trigger's own page (from the Scenes page's Edit, a New trigger...).
function ns.OpenTriggerPage(id)
	if PAGE.now ~= id then PAGE.sub = 1 end
	PAGE.now = id
	ns.OpenOptions("Trigger Settings")
	if ns.ShowHubPage then ns.ShowHubPage("Trigger Settings") end
end

-- The page's tabs (picked 1 to 3; back: the Triggers tab opens its page
-- even while lit, from a trigger's own page). title: the page's, under them.
local function Tabs(content, title, picked, back)
	local panel = ns.PageTabs(content, {
		{ L["Triggers"], "Triggers", L["Every trigger, ours and yours: open one to change it."], back },
		{ L["Priority"], "Trigger Priority", L["The order they win in when two are on at once."] },
		{ L["Log"], "Trigger Log", L["What fired, what was held back and why, this session."] },
	}, picked)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
	return panel
end

local function Button(parent, text, width, tip, onClick)
	local button = ns.PanelButton(parent)
	button:SetSize(width, 22)
	button:SetText(text)
	button.searchSkip = true
	if tip then ns.lowHealthKit.Tooltip(button, tip) end
	button:SetScript("OnClick", onClick)
	return button
end
local function Text(parent, font, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	if width then fs:SetWidth(width) end
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs.searchSkip = true
	return fs
end
-- (Text and vertex colour are one on Forever: both set.)
local function Color(fs, r, g, b)
	fs:SetTextColor(r, g, b)
	if fs.SetVertexColor then fs:SetVertexColor(r, g, b) end
end
-- Refreshed every half second while its frame shows (the dots, the log, Fire now).
local function WhileShown(frame, fn)
	local ticker = CreateFrame("Frame", nil, frame)
	local since = 0
	ns.SetOnUpdate(ticker, function(_, elapsed)
		since = since + elapsed
		if since >= 0.5 then
			since = 0
			fn()
		end
	end)
end

-- Every trigger as the list shows it: { id (yours) or key (ours), name,
-- src (what starts it, in words), kind, what, group, pri, uses, mine, users }.
local function Entries()
	local list = {}
	for _, each in ipairs(ns.BuiltInTriggers()) do
		list[#list + 1] = { key = each.key, name = each.name, src = each.starts, icon = each.icon, kind = each.kind,
			group = L[each.group], pri = ns.OursPri(each.key), uses = 1, users = { each.key }, source = each.source }
		-- (And the other scenes using it.)
		for _, key in ipairs(ns.TriggerUsers(ns.OursTriggerId(each.key))) do
			table.insert(list[#list].users, key)
		end
	end
	for _, id in ipairs((ns.TriggerLibList())) do
		local kind, what = Src(id)
		local users = ns.TriggerUsers(id)
		list[#list + 1] = { id = id, name = ns.TriggerLabel(id), src = ns.DescribeTriggerSource(kind .. ":" .. what),
			kind = kind, what = what, group = L["Yours"], pri = ns.TriggerPri(id), uses = #users, users = users,
			mine = true }
	end
	return list
end

function ns.CreateTriggersPanels(kit)
	-- ===== Triggers: the list =====
	do
		local canvas, content = kit.CreateScrollPage(true)
		local title = kit.Label(content, "GameFontNormalLarge", L["Triggers"])
		Tabs(content, title, 1)
		local intro = kit.PageIntro(content, title, L["Everything that can start a scene, in one list. A trigger " ..
			"is what starts it, Only if (a CQL rule), what ends it, its timing and its priority. Scenes pick " ..
			"them on the Scenes page; open one here to change it for every scene using it. Ours show their " ..
			"place and their scene: the rest of them moves here in a later update."])
		local show = ns.ChoiceMenu(content, 130, {
			{ value = "all", text = L["All"] }, { value = "ours", text = L["Ours"] },
			{ value = "yours", text = L["Yours"] }, { value = "unused", text = L["Unused"] },
			{ value = "on", text = L["On now"] },
		}, function() return PAGE.show end, function(value)
			PAGE.show = value
			kit.Refresh()
		end)
		show:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
		kit.Tooltip(show, L["Which triggers to list."])
		kit.AddControl(show)
		local by = ns.ChoiceMenu(content, 110, { { value = "group", text = L["By group"] },
			{ value = "kind", text = L["By kind"] } }, function() return PAGE.by end, function(value)
			PAGE.by = value
			kit.Refresh()
		end)
		by:SetPoint("LEFT", show, "RIGHT", 8, 0)
		kit.Tooltip(by, L["How the list is grouped."])
		kit.AddControl(by)
		local new = Button(content, L["+ New trigger"], 120, L["Make a trigger of your own (/cheer to start " ..
			"with) and open its page. Pick it on a scene's Triggers on the Scenes page."], function()
			local id = ns.AddLibTrigger("emote:cheer")
			if id then ns.OpenTriggerPage(id) end
		end)
		new:SetPoint("LEFT", by, "RIGHT", 10, 0)
		new.Refresh = function(self) self:SetEnabled(#(ns.TriggerLibList()) < ns.TRIGGER_LIB_MAX) end
		kit.AddControl(new)

		-- The list: a header band with the columns' names, then each group's
		-- name and its rows, banded as the other pages' lists, across the page.
		local head = CreateFrame("Frame", nil, content)
		head:SetSize(WIDTH, 20)
		head:SetPoint("TOPLEFT", show, "BOTTOMLEFT", 0, -14)
		local headBack = head:CreateTexture(nil, "BACKGROUND")
		headBack:SetAllPoints()
		headBack:SetColorTexture(0, 0, 0, 0.35)
		local headEdge = head:CreateTexture(nil, "BORDER")
		headEdge:SetPoint("BOTTOMLEFT")
		headEdge:SetPoint("BOTTOMRIGHT")
		headEdge:SetHeight(1)
		headEdge:SetColorTexture(1, 0.82, 0, 0.25)
		local cols = {}
		for _, key in ipairs({ "name", "src", "scene", "pri" }) do
			cols[key] = Text(head, "GameFontNormalSmall")
		end
		cols.name:SetText(L["Trigger"])
		cols.src:SetText(L["Starts when"])
		cols.scene:SetText(L["Scene"])
		cols.pri:SetText(L["Priority"])
		cols.pri:SetJustifyH("RIGHT")
		local body = CreateFrame("Frame", nil, content)
		body:SetSize(WIDTH, 1)
		body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)

		-- Where the columns go across width w: { x, width } each.
		local function Columns(w)
			local nameW = math.floor(w * 0.29)
			local srcX = 34 + nameW + 10
			local srcW = math.floor(w * 0.33)
			local sceneX = srcX + srcW + 10
			return { name = { 34, nameW }, src = { srcX, srcW }, scene = { sceneX, w - sceneX - 78 },
				pri = { w - 72, 44 }, dot = w - 18 }
		end
		local function Place(fs, parent, col, y)
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", parent, "LEFT", col[1], y or 0)
			fs:SetWidth(col[2])
		end

		local rows, groups = {}, {}
		local function Row(n)
			if rows[n] then return rows[n] end
			local row = CreateFrame("Button", nil, body)
			row:SetHeight(ROW_H + 2)
			row.band = row:CreateTexture(nil, "BACKGROUND", nil, -8)
			row.band:SetAllPoints()
			local hover = row:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints()
			hover:SetColorTexture(1, 0.82, 0, 0.08)
			local edge = row:CreateTexture(nil, "BACKGROUND")
			edge:SetPoint("BOTTOMLEFT")
			edge:SetPoint("BOTTOMRIGHT")
			edge:SetHeight(1)
			edge:SetColorTexture(1, 1, 1, 0.06)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(20, 20)
			row.icon:SetPoint("LEFT", 6, 0)
			row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			row.name = Text(row, "GameFontHighlight")
			row.src = Text(row, "GameFontHighlightSmall")
			row.scene = Text(row, "GameFontHighlightSmall")
			row.pri = Text(row, "GameFontNormal")
			row.pri:SetJustifyH("RIGHT")
			row.dot = row:CreateTexture(nil, "OVERLAY")
			row.dot:SetSize(8, 8)
			row.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
			row:SetScript("OnClick", function(self) ns.OpenTriggerPage(self.entry.id or ("b:" .. self.entry.key)) end)
			row:SetScript("OnEnter", function(self)
				local entry = self.entry
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(entry.name, 1, 0.82, 0)
				GameTooltip:AddLine(entry.src, 1, 1, 1, true)
				if not entry.pri then
					GameTooltip:AddLine(L["Its camera takes turns by its own rules for now."], 0.7, 0.7, 0.7, true)
				end
				GameTooltip:AddLine(L["Click to open its page."], 0.5, 0.8, 1, true)
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
			rows[n] = row
			return row
		end
		local function Group(n)
			if groups[n] then return groups[n] end
			local fs = Text(body, "GameFontNormal", 400)
			groups[n] = fs
			return fs
		end
		local function Dot(row)
			local on = row.entry and row.entry.id and ns.LibTriggerOn(row.entry.id)
			row.dot:SetShown(row.entry and row.entry.id ~= nil)
			if on then row.dot:SetVertexColor(0.3, 0.85, 0.55) else row.dot:SetVertexColor(0.3, 0.3, 0.34) end
		end
		local function Layout()
			local w = math.max(WIDTH, math.floor((content:GetWidth() or 0) - 24))
			local col = Columns(w)
			head:SetWidth(w)
			body:SetWidth(w)
			for key, fs in pairs(cols) do Place(fs, head, col[key]) end
			local list = {}
			for _, entry in ipairs(Entries()) do
				local keep = PAGE.show == "all" or (PAGE.show == "ours" and not entry.mine)
					or (PAGE.show == "yours" and entry.mine) or (PAGE.show == "unused" and entry.uses == 0)
					or (PAGE.show == "on" and entry.id and ns.LibTriggerOn(entry.id))
				if keep then list[#list + 1] = entry end
			end
			local order, byGroup = {}, {}
			for _, entry in ipairs(list) do
				local group = PAGE.by == "kind" and KindName(entry.kind) or entry.group
				if not byGroup[group] then
					byGroup[group] = {}
					order[#order + 1] = group
				end
				table.insert(byGroup[group], entry)
			end
			local y, n, g = 4, 0, 0
			for _, group in ipairs(order) do
				g = g + 1
				local fs = Group(g)
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -(y + 8))
				fs:SetText(("%s  |cff8a8678%d|r"):format(group, #byGroup[group]))
				fs:Show()
				y = y + 28
				for i, entry in ipairs(byGroup[group]) do
					n = n + 1
					local row = Row(n)
					row.entry = entry
					row:SetWidth(w)
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
					row.band:SetColorTexture(1, 1, 1, i % 2 == 1 and 0.045 or 0.015)
					row.icon:SetTexture(entry.icon or IconOf(entry.kind, entry.what))
					Place(row.name, row, col.name)
					Place(row.src, row, col.src)
					Place(row.scene, row, col.scene)
					Place(row.pri, row, col.pri)
					row.dot:ClearAllPoints()
					row.dot:SetPoint("LEFT", row, "LEFT", col.dot, 0)
					row.name:SetText(entry.name)
					if entry.mine then Color(row.name, 1, 1, 1) else Color(row.name, 0.92, 0.89, 0.8) end
					row.src:SetText(entry.src)
					Color(row.src, 0.7, 0.68, 0.62)
					local names = {}
					for _, key in ipairs(entry.users) do names[#names + 1] = ns.SceneDisplayName(key) end
					row.scene:SetText(#names > 0 and table.concat(names, ", ") or L["Unused"])
					if #names > 0 then Color(row.scene, 0.7, 0.68, 0.62) else Color(row.scene, 0.93, 0.5, 0.31) end
					row.pri:SetText(entry.pri and ("%d"):format(entry.pri) or "|cff8a8678" .. L["own"] .. "|r")
					Dot(row)
					row:Show()
					y = y + ROW_H + 2
				end
			end
			for i = n + 1, #rows do rows[i]:Hide() end
			for i = g + 1, #groups do groups[i]:Hide() end
			if n == 0 then
				local fs = Group(1)
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -12)
				fs:SetText(L["No triggers match."])
				fs:Show()
				y = 32
			end
			body:SetHeight(math.max(1, y))
			kit.FitContentHeight(content)
		end
		local holder = CreateFrame("Frame", nil, content)
		holder:Hide()
		holder.Refresh = function() if canvas:IsVisible() then Layout() else canvas.stale = true end end
		kit.AddControl(holder)
		WhileShown(body, function()
			for _, row in ipairs(rows) do
				if row:IsShown() then Dot(row) end
			end
		end)
		canvas:SetScript("OnShow", kit.PageShown(function()
			kit.Refresh()
			Layout()
		end, content))
		canvas:Hide()
		kit.RegisterSubpage(canvas, "Triggers")
	end

	-- ===== Priority: the order =====
	do
		local canvas, content = kit.CreateScrollPage(true)
		local title = kit.Label(content, "GameFontNormalLarge", L["Priority"])
		Tabs(content, title, 2)
		local intro = kit.PageIntro(content, title, L["When two triggers are on at once, the one higher in this " ..
			"list plays its scene. Move one with its arrows (or type its number on its page). Ours are groups " ..
			"of our triggers: Emotes and seats is every emote, seat and Fishing. A card or music never competes " ..
			"with a camera: this is the cameras' order."])
		local note = kit.Label(content, "GameFontDisableSmall", L["The flight, quest, chat, RP walk, auto-run and " ..
			"death cameras take turns by their own rules for now: they join this list in a later update."])
		note:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
		note:SetWidth(WIDTH)
		note:SetJustifyH("LEFT")
		local reset = Button(content, L["Put ours back"], 130, L["Our triggers' places as we ship them. " ..
			"Yours keep theirs."], function()
			ns.ResetAllOurs()
			kit.Refresh()
		end)
		reset:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
		local body = CreateFrame("Frame", nil, content)
		body:SetSize(WIDTH, 1)
		body:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -10)

		-- The list: ours (their sources) and yours, by number; ours first in a tie, as they win it.
		-- (Ours: each of the standing-still ones, by its own number.)
		local function Items()
			local list = {}
			for _, each in ipairs(ns.BuiltInTriggers()) do
				if each.source then
					list[#list + 1] = { ours = each.key, name = each.name, pri = ns.OursPri(each.key), icon = each.icon }
				end
			end
			for _, id in ipairs((ns.TriggerLibList())) do
				local kind, what = Src(id)
				list[#list + 1] = { id = id, name = ns.TriggerLabel(id), pri = ns.TriggerPri(id), kind = kind,
					what = what, uses = #ns.TriggerUsers(id) }
			end
			table.sort(list, function(a, b)
				if a.pri ~= b.pri then return a.pri < b.pri end
				if (a.ours ~= nil) ~= (b.ours ~= nil) then return a.ours ~= nil end
				return a.name < b.name
			end)
			return list
		end
		local function SetPri(item, pri)
			if item.ours then
				local each = ns.OursTrigger(item.ours)
				local base = each and each.source and ns.BuiltInSourceOrder(each.source)
				ns.SetTriggerField(ns.OursTriggerId(item.ours), "pri", pri ~= base and pri or nil)
			else
				ns.SetTriggerField(item.id, "pri", pri ~= ns.TRIGGER_DEFAULT_PRI and pri or nil)
			end
		end
		local Layout -- (below)
		-- Moved past its neighbour: their numbers swapped (one apart, if they're the same).
		local function Move(index, step)
			local list = Items()
			local item, other = list[index], list[index + step]
			if not (item and other) then return end
			local a, b = item.pri, other.pri
			if a == b then
				SetPri(item, a + (step < 0 and -1 or 1))
			else
				SetPri(item, b)
				SetPri(other, a)
			end
			kit.Refresh()
		end
		local rows = {}
		local function Row(n)
			if rows[n] then return rows[n] end
			local row = CreateFrame("Frame", nil, body)
			row:SetSize(WIDTH, 24)
			row.band = row:CreateTexture(nil, "BACKGROUND", nil, -8)
			row.band:SetAllPoints()
			local edge = row:CreateTexture(nil, "BACKGROUND")
			edge:SetPoint("BOTTOMLEFT")
			edge:SetPoint("BOTTOMRIGHT")
			edge:SetHeight(1)
			edge:SetColorTexture(1, 1, 1, 0.06)
			row.num = Text(row, "GameFontNormal", 40)
			row.num:SetPoint("LEFT", 0, 0)
			row.num:SetJustifyH("RIGHT")
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(18, 18)
			row.icon:SetPoint("LEFT", 48, 0)
			row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			row.name = Text(row, "GameFontHighlight", 300)
			row.name:SetPoint("LEFT", 72, 0)
			row.tag = Text(row, "GameFontHighlightSmall", 110)
			row.tag:SetPoint("LEFT", 378, 0)
			local function Arrow(dir, x)
				local arrow = CreateFrame("Button", nil, row)
				arrow:SetSize(22, 22)
				arrow:SetPoint("LEFT", x, 0)
				local tex = dir < 0 and "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp" or
					"Interface\\ChatFrame\\UI-ChatIcon-ScrollDown"
				arrow:SetNormalTexture(tex .. "-Up")
				arrow:SetPushedTexture(tex .. "-Down")
				arrow:SetDisabledTexture(tex .. "-Disabled")
				arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
				arrow:SetScript("OnClick", function() Move(row.index, dir) end)
				kit.Tooltip(arrow, dir < 0 and L["Higher: wins over the one above."] or L["Lower: the one below wins over it."])
				return arrow
			end
			row.up, row.down = Arrow(-1, 496), Arrow(1, 520)
			row:EnableMouse(true)
			rows[n] = row
			return row
		end
		function Layout()
			local list = Items()
			local count = {}
			local oursCount = {}
			for _, item in ipairs(list) do
				count[item.pri] = (count[item.pri] or 0) + 1
				if item.ours then oursCount[item.pri] = (oursCount[item.pri] or 0) + 1 end
			end
			for i, item in ipairs(list) do
				local row = Row(i)
				row.index = i
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(i - 1) * 24)
				row.num:SetText(("%d"):format(item.pri))
				row.icon:SetTexture(item.icon or IconOf(item.kind, item.what))
				row.band:SetColorTexture(1, 1, 1, i % 2 == 1 and 0.045 or 0.015)
				row.name:SetText(item.name)
				if item.ours then Color(row.name, 0.85, 0.82, 0.72) else Color(row.name, 1, 1, 1) end
				local tag = item.ours and L["Ours"] or (item.uses == 0 and L["unused"] or "")
				-- (A tie among ours is as we ship it: emotes are one at a time anyway.)
				if count[item.pri] > 1 and not (item.ours and (oursCount[item.pri] or 0) == count[item.pri]) then tag = (tag ~= "" and tag .. ", " or "") .. "|cffee8350" .. L["tie"] .. "|r" end
				row.tag:SetText(tag)
				Color(row.tag, 0.62, 0.6, 0.55)
				row.up:SetEnabled(i > 1)
				row.down:SetEnabled(i < #list)
				row:Show()
			end
			for i = #list + 1, #rows do rows[i]:Hide() end
			body:SetHeight(math.max(1, #list * 24))
			kit.FitContentHeight(content)
		end
		local holder = CreateFrame("Frame", nil, content)
		holder:Hide()
		holder.Refresh = function() if canvas:IsVisible() then Layout() else canvas.stale = true end end
		kit.AddControl(holder)
		canvas:SetScript("OnShow", kit.PageShown(function()
			kit.Refresh()
			Layout()
		end, content))
		canvas:Hide()
		kit.RegisterSubpage(canvas, "Trigger Priority", L["Priority"])
	end

	-- ===== Log =====
	do
		local canvas, content = kit.CreateScrollPage(true)
		local title = kit.Label(content, "GameFontNormalLarge", L["Log"])
		Tabs(content, title, 3)
		local intro = kit.PageIntro(content, title, L["Your triggers firing, held back (Only if, cooldown, " ..
			"chance), losing to a higher one, and ending, with why; and which of ours started a camera. This " ..
			"session only, newest first."])
		local clear = Button(content, L["Clear"], 80, L["Empty the log."], function()
			ns.ClearTriggerLog()
			kit.Refresh()
		end)
		clear:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
		local body = CreateFrame("Frame", nil, content)
		body:SetSize(WIDTH, 1)
		body:SetPoint("TOPLEFT", clear, "BOTTOMLEFT", 0, -10)
		local empty = Text(body, "GameFontDisable", WIDTH)
		empty:SetPoint("TOPLEFT", 2, 0)
		empty:SetText(L["Nothing yet. Do something one of your triggers watches for, or press Fire now on its page."])
		local COLORS = { fired = "ff4fd08f", skipped = "ffee8350", lost = "ffee8350", ended = "ff9b978c" }
		local WORDS = { fired = "Fired", skipped = "Held back", lost = "Lost", ended = "Ended" }
		local lines, shownVersion = {}, -1
		local function Layout()
			local log = ns.triggerLog
			shownVersion = log.version
			local y = 0
			for n = 1, #log do
				local entry = log[#log - n + 1]
				local fs = lines[n]
				if not fs then
					fs = Text(body, "GameFontHighlightSmall", WIDTH)
					fs:SetWordWrap(true)
					lines[n] = fs
				end
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", body, "TOPLEFT", 2, -y)
				fs:SetText(("|cff9b978c%s|r  |c%s%s|r  %s  |cffbdb8aa%s|r"):format(entry.clock,
					COLORS[entry.what] or "ffffffff", L[WORDS[entry.what] or entry.what], entry.name, entry.why))
				fs:Show()
				local h = fs:GetStringHeight()
				y = y + math.max(14, type(h) == "number" and h or 14) + 4
			end
			for n = #log + 1, #lines do lines[n]:Hide() end
			empty:SetShown(#log == 0)
			body:SetHeight(math.max(20, y))
			kit.FitContentHeight(content)
		end
		local holder = CreateFrame("Frame", nil, content)
		holder:Hide()
		holder.Refresh = function() if canvas:IsVisible() then Layout() else canvas.stale = true end end
		kit.AddControl(holder)
		WhileShown(body, function()
			if ns.triggerLog.version ~= shownVersion then Layout() end
		end)
		canvas:SetScript("OnShow", kit.PageShown(function()
			kit.Refresh()
			Layout()
		end, content))
		canvas:Hide()
		kit.RegisterSubpage(canvas, "Trigger Log", L["Log"])
	end

	ns.CreateTriggerSettingsPanel(kit)
end

-- ===== A trigger's own page =====
function ns.CreateTriggerSettingsPanel(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", L["Trigger"])
	local tabs = Tabs(content, title, 1, true)
	local icon = content:CreateTexture(nil, "ARTWORK")
	icon:SetSize(24, 24)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 8, -10)
	title:ClearAllPoints()
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	title:SetWidth(300)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	local controls = {} -- (this page's, refreshed by its Layout)
	local function Add(control)
		controls[#controls + 1] = control
		return control
	end

	local function Id() return PAGE.now and not PAGE.now:find("^b:") and ns.IsLibTrigger(PAGE.now) and PAGE.now or nil end
	local function BuiltIn()
		local key = PAGE.now and PAGE.now:match("^b:(.+)$")
		if not key then return nil end
		for _, each in ipairs(ns.BuiltInTriggers()) do
			if each.key == key then return each end
		end
	end
	local function Kind() return (Src(Id())) end
	-- (What's set here: yours, or one of ours by its library id.)
	local function EditId()
		local built = BuiltIn()
		return Id() or (built and ns.OursTriggerId(built.key)) or nil
	end
	local function Editable() return EditId() ~= nil end
	local function Set(field, value)
		local id = EditId()
		if not id then return end
		ns.SetTriggerField(id, field, value)
		kit.Refresh()
	end

	-- Fire now (Stop while on), Copy, Delete.
	local fire = Add(Button(content, L["Fire now"], 90, L["Starts this trigger's scenes now, whatever its Only " ..
		"if, cooldown and chance say (click again to stop). The Log tab shows it."], function()
		local id = Id()
		if id then ns.FireLibTrigger(id) end
		kit.Refresh()
	end))
	fire:SetPoint("TOPRIGHT", content, "TOPRIGHT", -12, -(ns.FOLDER_TAB_HEIGHT + 26))
	fire.Refresh = function(self)
		local id = Id()
		self:SetShown(id ~= nil)
		self:SetText(id and ns.LibTriggerOn(id) and L["Stop"] or L["Fire now"])
	end
	local copy = Add(Button(content, L["Copy"], 70, L["A copy of this trigger, to change apart from it."], function()
		local id = Id()
		local new = id and ns.CopyLibTrigger(id)
		if new then ns.OpenTriggerPage(new) end
	end))
	copy:SetPoint("RIGHT", fire, "LEFT", -6, 0)
	copy.Refresh = function(self) self:SetShown(Id() ~= nil) end
	if not StaticPopupDialogs.CINEMATIC_DELETE_LIB_TRIGGER then
		StaticPopupDialogs.CINEMATIC_DELETE_LIB_TRIGGER = {
			text = L["Delete the trigger %s? It comes off every scene using it."],
			button1 = DELETE or L["Delete"], button2 = CANCEL or L["Cancel"],
			OnAccept = function(_, data) data() end,
			timeout = 0, whileDead = true, hideOnEscape = true,
		}
	end
	local delete = Add(Button(content, DELETE or L["Delete"], 70, L["Delete this trigger: it comes off every scene " ..
		"using it."], function()
		local id = Id()
		if not id then return end
		StaticPopup_Show("CINEMATIC_DELETE_LIB_TRIGGER", (ns.TriggerLabel(id):gsub("|", "")), nil, function()
			ns.RemoveLibTrigger(id)
			PAGE.now = nil
			ns.ShowHubPage("Triggers")
		end)
	end))
	delete:SetPoint("RIGHT", copy, "LEFT", -6, 0)
	delete.Refresh = function(self) self:SetShown(Id() ~= nil) end
	local reset = Add(Button(content, L["Reset"], 80, L["Back as we ship it: its Only if, wait, cooldown, " ..
		"chance and priority."], function()
		local built = BuiltIn()
		if built then ns.ResetOursTrigger(built.key) end
		kit.Refresh()
	end))
	reset:SetPoint("TOPRIGHT", content, "TOPRIGHT", -12, -(ns.FOLDER_TAB_HEIGHT + 26))
	reset.Refresh = function(self)
		local built = BuiltIn()
		self:SetShown(built ~= nil)
		self:SetEnabled(built ~= nil and ns.OursChanged(built.key))
	end

	local reads = Text(content, "GameFontHighlight", WIDTH)
	reads:SetWordWrap(true)
	reads:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -12)
	local readsBack = content:CreateTexture(nil, "BACKGROUND")
	readsBack:SetColorTexture(0, 0, 0, 0.35)
	readsBack:SetPoint("TOPLEFT", reads, "TOPLEFT", -6, 6)
	readsBack:SetPoint("BOTTOMRIGHT", reads, "BOTTOMRIGHT", 6, -6)
	-- Its own folder tabs, under the sentence (as a card's own pages have):
	-- Starts (its name, what starts it, Only if), Ends, Timing, Scenes (its
	-- priority and the scenes using it).
	local Layout -- (below)
	local sub, _, ShowSub, subBase, subH = ns.FolderTabs(content, {
		{ L["Starts"], L["Its name, what starts it and its Only if rule."] },
		{ L["Ends"], L["What ends it: the first of its endings to happen."] },
		{ L["Timing"], L["A wait before it starts, a least time, a cooldown and a chance."] },
		{ L["Scenes"], L["Its priority, and the scenes it starts."] },
	}, function(i)
		PAGE.sub = i
		Layout()
	end)
	subBase:SetPoint("TOPLEFT", reads, "BOTTOMLEFT", -6, -(16 + subH))
	sub:SetPoint("TOPLEFT", subBase, "TOPLEFT")
	sub:SetPoint("RIGHT", content, "RIGHT", -8, 0)
	sub:SetHeight(1) -- (just its top edge, a line under the tabs)
	local body = CreateFrame("Frame", nil, content)
	body:SetSize(WIDTH, 1)
	body:SetPoint("TOPLEFT", subBase, "TOPLEFT", 6, -10)

	-- Lines: a name on the left, controls from LABEL_X; shown(line) says whether
	-- it shows, and Layout stacks the ones that do. A section's line has a header.
	local LABEL_X, LINE_H = 170, 30
	local lines = {}
	local building = 1 -- (the folder tab the lines made now go on)
	local function Line(label, shown, header)
		local line = CreateFrame("Frame", nil, body)
		line:SetSize(WIDTH, header and 26 or LINE_H)
		line.shown = shown
		line.label = Text(line, header and "GameFontNormal" or "GameFontHighlight", header and WIDTH or LABEL_X - 10)
		line.label:SetPoint("LEFT", 0, header and -2 or 0)
		line.label:SetText(label)
		line.label.searchSkip = nil
		if header then
			local rule = line:CreateTexture(nil, "ARTWORK")
			rule:SetColorTexture(1, 0.82, 0, 0.18)
			rule:SetHeight(1)
			rule:SetPoint("BOTTOMLEFT", 0, 2)
			rule:SetPoint("BOTTOMRIGHT", 0, 2)
		end
		line.tab = building
		lines[#lines + 1] = line
		return line
	end
	local function Mine() return Id() ~= nil end
	local function Heading(text, shown) return Line(text, shown or Mine, true) end
	local function Menu(line, width, choices, get, set, x)
		local menu = Add(ns.ChoiceMenu(line, width, choices, get, function(value)
			set(value)
			kit.Refresh()
		end))
		menu:SetPoint("LEFT", x or LABEL_X, 0)
		return menu
	end
	-- An edit box: get() its text, set(text) as it's left (Enter or a click away).
	local function Box(line, width, get, set, x, numeric)
		local box = Add(ns.SkinEditBox(CreateFrame("EditBox", nil, line, "InputBoxTemplate")))
		box:SetSize(width, 20)
		box:SetAutoFocus(false)
		box:SetMaxLetters(numeric and 6 or 80)
		box:SetPoint("LEFT", (x or LABEL_X) + 6, 0)
		box.searchSkip = true
		box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		box:SetScript("OnEscapePressed", function(self)
			self:SetText(get() or "")
			self:ClearFocus()
		end)
		box:SetScript("OnEditFocusLost", function(self)
			local text = self:GetText():gsub("[%c|]", ""):match("^%s*(.-)%s*$")
			set(text)
			kit.Refresh()
		end)
		box.Refresh = function(self)
			if not self:HasFocus() then self:SetText(get() or "") end
		end
		return box
	end
	local function Number(line, field, default, low, high, x)
		return Box(line, 54, function()
			local value = ns.TriggerNumber(EditId(), field, default)
			return value == math.floor(value) and ("%d"):format(value) or tostring(value)
		end, function(text)
			local value = tonumber(text)
			if not value then value = default end
			value = math.max(low, math.min(high, value))
			Set(field, value ~= default and value or nil)
		end, x, true)
	end

	-- (Ours: what starts it and what ends it, in words, on those tabs.)
	local function Ours() return BuiltIn() ~= nil end
	local oursStarts = Text(Line(L["Starts when"], Ours), "GameFontHighlight", WIDTH - LABEL_X)
	oursStarts:SetPoint("LEFT", LABEL_X, 0)

	-- Name
	Heading(L["Name"])
	local nameLine = Line(L["Name"], Mine)
	Box(nameLine, 240, function() return ns.TriggerField(Id(), "name") or "" end, function(text)
		Set("name", text ~= "" and text or nil)
	end)

	-- Starts when
	Heading(L["Starts when"])
	local kindLine = Line(L["Kind"], Mine)
	local KIND_START = { emote = "cheer", spell = "", aura = "", place = "", moment = "levelup", state = "mounted",
		interact = "mail", key = "1" }
	Menu(kindLine, 180, ns.CUSTOM_TRIGGER_KINDS, Kind, function(value)
		local id = Id()
		if not id or value == Kind() then return end
		local rows = ns.GetDB().cameraRows
		rows[id .. ".at"], rows[id .. ".ends"] = nil, nil -- (its kind's own to start with)
		ns.SetTriggerField(id, "src", value .. ":" .. (KIND_START[value] or ""))
	end)
	local TYPED = { emote = L["Emote"], spell = L["Spell name or ID"], aura = L["Buff name or ID"],
		place = L["Zone or subzone"] }
	local whatLine = Line(L["Which"], function() return Mine() and TYPED[Kind()] ~= nil end)
	local whatBox = Box(whatLine, 220, function() return select(2, Src(Id())) end, function(text)
		local kind = Kind()
		if kind == "emote" then text = ns.EmoteToken(text) end
		Set("src", kind .. ":" .. text)
	end)
	kit.Tooltip(whatBox, L["Emotes: the command, with or without its slash. Spells and buffs: the name in your " ..
		"game language, or a spell ID (works in any language). Places: the zone or subzone name as the game shows it."])
	local here = Add(Button(whatLine, L["Here"], 54, L["Fill in the subzone you're in now (or the zone, where " ..
		"there's no subzone)."], function()
		local name = GetSubZoneText and GetSubZoneText()
		if type(name) ~= "string" or name == "" then name = GetZoneText and GetZoneText() end
		if type(name) == "string" and name ~= "" then Set("src", "place:" .. name) end
	end))
	here:SetPoint("LEFT", whatBox, "RIGHT", 8, 0)
	here.Refresh = function(self) self:SetShown(Kind() == "place") end
	local FIXED = { moment = ns.CUSTOM_TRIGGER_MOMENTS, state = ns.CUSTOM_TRIGGER_STATES,
		interact = ns.CUSTOM_TRIGGER_INTERACTIONS, key = ns.CUSTOM_TRIGGER_KEYS }
	local pickLine = Line(L["Which"], function() return Mine() and FIXED[Kind()] ~= nil end)
	local pick = Menu(pickLine, 240, function() return FIXED[Kind()] or {} end, function() return select(2, Src(Id())) end,
		function(value) Set("src", Kind() .. ":" .. value) end)
	kit.Tooltip(pick, L["Which one. Key bindings are set in the game's Key Bindings, under Cinematic."])
	local atLine = Line(L["When"], function() return Mine() and ns.TRIGGER_PHASES[Kind()] ~= nil end)
	Menu(atLine, 200, function() return ns.TRIGGER_PHASES[Kind()] or {} end, function()
		local list = ns.TRIGGER_PHASES[Kind()]
		return ns.TriggerField(Id(), "at") or (list and list[1].value)
	end, function(value)
		local list = ns.TRIGGER_PHASES[Kind()]
		Set("at", not (list and list[1].value == value) and value or nil)
	end)

	-- Only if
	Heading(L["Only if"], Editable)
	local condLine = Line(L["Rule (CQL)"], Editable)
	local rule = Add(Button(condLine, "", 300, L["A rule it needs to start, in the words the Show in rules use " ..
		"(In combat, Cities, Resting, Mounted, In CineMode..., with AND, OR and NOT). Empty: always. Click to " ..
		"write it in the rule editor."], function()
		local id = EditId()
		if not id then return end
		ns.OpenRuleEditor({
			label = ns.TriggerLabel(id),
			Text = function() return ns.TriggerField(id, "cond") or "" end,
			SetText = function() end,
			Close = function(text)
				text = tostring(text or ""):gsub("[|]", ""):match("^%s*(.-)%s*$")
				ns.SetTriggerField(id, "cond", text ~= "" and text ~= "always" and text or nil)
				kit.Refresh()
			end,
			ResetToGrid = function()
				ns.SetTriggerField(id, "cond", nil)
				kit.Refresh()
			end,
		})
	end))
	rule:SetPoint("LEFT", LABEL_X, 0)
	rule.Refresh = function(self)
		local text = ns.TriggerField(EditId(), "cond")
		self:SetText(type(text) == "string" and ns.ColoredRule(text) or L["Always"])
	end

	-- Ends when: up to three, the first to happen ends it.
	building = 2
	local oursEnds = Text(Line(L["Ends when"], Ours), "GameFontHighlight", WIDTH - LABEL_X)
	oursEnds:SetPoint("LEFT", LABEL_X, 0)
	oursEnds:SetText(L["As its camera's code says, for now (moving ends it too)"])
	Heading(L["Ends when"])
	local function EndChoices()
		local kind = Kind()
		local ENDS_TEXT = { spell = L["The cast ends"], aura = L["The buff fades"], place = L["You leave"],
			state = L["It stops"], interact = L["Its window closes"] }
		local list = {}
		if ENDS_TEXT[kind] then
			local phases = ns.TRIGGER_PHASES[kind]
			local at = ns.TriggerField(Id(), "at")
			-- (Started as it stops: it ends as it comes back.)
			local turned = at and phases and at ~= phases[1].value
			list[#list + 1] = { value = "ends", text = turned and L["It comes back"] or ENDS_TEXT[kind] }
		end
		list[#list + 1] = { value = "time", text = L["A set time"] }
		if kind == "key" then list[#list + 1] = { value = "key", text = L["Its key pressed again"] } end
		if #(ns.TriggerLibList()) > 1 then list[#list + 1] = { value = "trig", text = L["Another trigger starts"] } end
		list[#list + 1] = { value = "never", text = kind == "emote" and L["Nothing more (moving or another emote ends it)"]
			or L["Nothing more (moving ends it)"] }
		return list
	end
	local function Ends() return ns.TriggerEnds(Id()) end
	local function SetEnd(i, each)
		local list = Ends()
		list[i] = each
		ns.SetTriggerEnds(Id(), list)
		kit.Refresh()
	end
	for i = 1, ns.TRIGGER_ENDS_MAX do
		local line = Line(i == 1 and L["Ends when"] or L["or"], function() return Mine() and i <= #Ends() end)
		Menu(line, 240, EndChoices, function() local each = Ends()[i] return each and each.kind end, function(value)
			if value == "trig" then
				for _, other in ipairs((ns.TriggerLibList())) do
					if other ~= Id() then return SetEnd(i, { kind = "trig", ref = other }) end
				end
				return
			end
			SetEnd(i, { kind = value, secs = value == "time" and 5 or nil })
		end)
		local secs = Box(line, 54, function()
			local each = Ends()[i]
			return each and each.secs and ("%g"):format(each.secs) or ""
		end, function(text)
			local each = Ends()[i]
			if not each or each.kind ~= "time" then return end
			SetEnd(i, { kind = "time", secs = math.max(1, math.min(3600, tonumber(text) or 5)) })
		end, LABEL_X + 250, true)
		local secsRefresh = secs.Refresh
		secs.Refresh = function(self)
			local each = Ends()[i]
			self:SetShown(each ~= nil and each.kind == "time")
			secsRefresh(self)
		end
		local other = Menu(line, 170, function()
			local list = {}
			for _, id in ipairs((ns.TriggerLibList())) do
				if id ~= Id() then list[#list + 1] = { value = id, text = ns.TriggerLabel(id) } end
			end
			return list
		end, function() local each = Ends()[i] return each and each.ref end, function(value)
			SetEnd(i, { kind = "trig", ref = value })
		end, LABEL_X + 250)
		local otherRefresh = other.Refresh
		other.Refresh = function(self)
			local each = Ends()[i]
			local shown = each ~= nil and each.kind == "trig"
			self:SetShown(shown)
			if shown then otherRefresh(self) end
		end
		local remove = Add(CreateFrame("Button", nil, line))
		remove:SetSize(16, 16)
		remove:SetPoint("LEFT", LABEL_X + 432, 0)
		remove:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
		remove:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		remove:SetScript("OnClick", function()
			local list = Ends()
			table.remove(list, i)
			ns.SetTriggerEnds(Id(), list)
			kit.Refresh()
		end)
		remove.Refresh = function(self) self:SetShown(#Ends() > 1) end
		kit.Tooltip(remove, L["Take this ending off."])
	end
	local addEndLine = Line("", function() return Mine() and #Ends() < ns.TRIGGER_ENDS_MAX end)
	local addEnd = Add(Button(addEndLine, L["+ Add ending"], 120, L["Another way for it to end: the first one " ..
		"that happens ends it. Moving, walking, zooming or a fight are the camera's own stop rules (Scripts " ..
		"page), not the trigger's."], function()
		local list = Ends()
		list[#list + 1] = { kind = "time", secs = 10 }
		ns.SetTriggerEnds(Id(), list)
		kit.Refresh()
	end))
	addEnd:SetPoint("LEFT", LABEL_X, 0)

	-- Timing
	building = 3
	Heading(L["Timing"], Editable)
	local waitLine = Line(L["Wait before starting"], Editable)
	Number(waitLine, "delay", 0, 0, 600)
	-- (Keep going at least: yours only; ours end as their cameras' code says.)
	local holdText = Add(Text(waitLine, "GameFontHighlight", 150))
	holdText:SetPoint("LEFT", LABEL_X + 90, 0)
	holdText:SetText(L["Keep going at least"])
	holdText.searchSkip = nil
	holdText.Refresh = function(self) self:SetShown(Mine()) end
	local holdBox = Number(waitLine, "hold", 0, 0, 600, LABEL_X + 240)
	local holdRefresh = holdBox.Refresh
	holdBox.Refresh = function(self)
		self:SetShown(Mine())
		holdRefresh(self)
	end
	local cdLine = Line(L["Cooldown"], Editable)
	Number(cdLine, "cd", 0, 0, 86400)
	local chanceText = Text(cdLine, "GameFontHighlight", 150)
	chanceText:SetPoint("LEFT", LABEL_X + 90, 0)
	chanceText:SetText(L["Chance (%)"])
	chanceText.searchSkip = nil
	Number(cdLine, "chance", 100, 1, 100, LABEL_X + 240)
	local secText = Add(Text(waitLine, "GameFontDisableSmall", 40))
	secText:SetPoint("LEFT", LABEL_X + 310, 0)
	secText:SetText(L["sec"])
	secText.Refresh = function(self) self:SetShown(Mine()) end
	local rearmLine = Line("", function() return Mine() and ns.TRIGGER_HELD_KINDS[Kind()] end)
	local rearm = Add(ns.SkinCheck(CreateFrame("CheckButton", nil, rearmLine, "UICheckButtonTemplate")))
	rearm:SetSize(26, 26)
	rearm:SetPoint("LEFT", LABEL_X - 4, 0)
	local rearmText = rearm.Text or rearm.text or rearm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	rearmText:SetPoint("LEFT", rearm, "RIGHT", 2, 0)
	rearmText:SetFontObject("GameFontHighlight")
	rearmText:SetText(L["Don't start again until it has stopped being true"])
	rearm:SetScript("OnClick", function(self) Set("rearm", not self:GetChecked() and "no" or nil) end)
	rearm.Refresh = function(self) self:SetChecked(ns.TriggerField(Id(), "rearm") ~= "no") end
	kit.Tooltip(rearm, L["On: once it has played, it waits for its thing to stop (you dismount, you leave) " ..
		"before it can start again. Off: it may start again while still true, after its cooldown."])

	-- Priority
	building = 4
	Heading(L["Priority"], function() return Mine() or BuiltIn() ~= nil end)
	local priLine = Line(L["Priority"], function() return Mine() or BuiltIn() ~= nil end)
	local priBox = Box(priLine, 54, function()
		local id, built = Id(), BuiltIn()
		if id then return ("%d"):format(ns.TriggerPri(id)) end
		local pri = built and ns.OursPri(built.key)
		return pri and ("%d"):format(pri) or ""
	end, function(text)
		local value = tonumber(text)
		if not value then return end
		value = math.floor(math.max(-9999, math.min(9999, value)))
		local id, built = Id(), BuiltIn()
		if id then
			Set("pri", value ~= ns.TRIGGER_DEFAULT_PRI and value or nil)
		elseif built and built.source then
			-- (Its own number; the same as its source's is none of its own.)
			Set("pri", value ~= ns.BuiltInSourceOrder(built.source) and value or nil)
		end
	end, nil, true)
	kit.Tooltip(priBox, L["Lower wins when two triggers are on at once (ours: Hearthstone 100, logging out 200, " ..
		"AFK 300, campfire 400, emotes 500, weapon 600, campfire buff 700, standing still 800)."])
	local order = Add(Button(priLine, L["See the order"], 110, L["Opens the Priority tab."], function()
		ns.ShowHubPage("Trigger Priority")
	end))
	order:SetPoint("LEFT", priBox, "RIGHT", 10, 0)
	local ownRules = Text(priLine, "GameFontDisableSmall", WIDTH - LABEL_X)
	ownRules:SetPoint("LEFT", LABEL_X, 0)
	ownRules:SetText(L["Its camera takes turns by its own rules for now."])

	-- Used by
	Heading(L["Used by"], function() return true end)
	local usedLine = Line(L["Scenes"], function() return true end)
	local used = Text(usedLine, "GameFontHighlight", 260)
	used:SetPoint("LEFT", LABEL_X, 0)
	local useIn = Menu(usedLine, 140, function()
		local list, id = {}, EditId()
		if not id then return list end
		local taken = {}
		for _, key in ipairs(ns.TriggerUsers(id)) do taken[key] = true end
		for _, trigger in ipairs(ns.CAMERA_TRIGGERS) do
			local key = trigger.key
			if not taken[key] and ns.SceneTakesTriggers(key) and not ns.TriggerDeleted(key)
				and #ns.SceneTriggers(key) < ns.SCENE_TRIGGER_MAX and ns.SceneLead(key) == key then
				list[#list + 1] = { value = key, text = ns.SceneDisplayName(key) }
			end
		end
		return list
	end, function() return nil end, function(key)
		local list = {}
		for i, source in ipairs(ns.SceneTriggers(key)) do list[i] = source end
		list[#list + 1] = "t:" .. EditId()
		ns.SetSceneTriggers(key, list)
	end, LABEL_X + 270)
	if useIn.SetDefaultText then useIn:SetDefaultText(L["Use in..."]) end
	kit.Tooltip(useIn, L["Add this trigger to a scene (yours, or one of ours that runs while you stand still)."])
	local scenes = Add(Button(usedLine, L["Scenes page"], 110, L["Opens the Scenes page."], function()
		ns.ShowHubPage("Scenes")
	end))
	scenes:SetPoint("LEFT", LABEL_X + 270, 0)

	-- The sentence at the top: the trigger in words.
	local function Sentence()
		local id, built = Id(), BuiltIn()
		if built then
			local oid = ns.OursTriggerId(built.key)
			local extra = {}
			local cond = ns.TriggerField(oid, "cond")
			if type(cond) == "string" then extra[#extra + 1] = (L["only if |cffffd100%s|r"]):format(cond) end
			local delay = ns.TriggerNumber(oid, "delay", 0)
			if delay > 0 then extra[#extra + 1] = (L["after waiting %g sec"]):format(delay) end
			local cd = ns.TriggerNumber(oid, "cd", 0)
			if cd > 0 then extra[#extra + 1] = (L["at most once every %g sec"]):format(cd) end
			local chance = ns.TriggerNumber(oid, "chance", 100)
			if chance < 100 then extra[#extra + 1] = (L["%d%% of the time"]):format(chance) end
			local pri = ns.OursPri(built.key)
			return (L["|cffffd100Ours:|r %s%s. When it ends is still its camera's code (a later update moves it " ..
				"here). %s"]):format(built.starts, #extra > 0 and ", " .. table.concat(extra, ", ") or "",
				pri and (L["Priority %d."]):format(pri) or L["Its camera takes turns by its own rules for now."])
		end
		if not id then return L["This trigger isn't there any more: pick one on the Triggers tab."] end
		local kind, what = Src(id)
		local phases = ns.TRIGGER_PHASES[kind]
		local at = ns.TriggerField(id, "at")
		local atText
		for _, each in ipairs(phases or {}) do
			if each.value == (at or phases[1].value) then atText = each.text end
		end
		local parts = { (L["Starts when |cffffd100%s|r"]):format(ns.DescribeTriggerSource(kind .. ":" .. what)) }
		if atText then parts[1] = parts[1] .. " (" .. atText:lower() .. ")" end
		local cond = ns.TriggerField(id, "cond")
		if type(cond) == "string" then parts[#parts + 1] = (L["only if |cffffd100%s|r"]):format(cond) end
		local delay = ns.TriggerNumber(id, "delay", 0)
		if delay > 0 then parts[#parts + 1] = (L["after waiting %g sec"]):format(delay) end
		local cd = ns.TriggerNumber(id, "cd", 0)
		if cd > 0 then parts[#parts + 1] = (L["at most once every %g sec"]):format(cd) end
		local chance = ns.TriggerNumber(id, "chance", 100)
		if chance < 100 then parts[#parts + 1] = (L["%d%% of the time"]):format(chance) end
		local ends, choices = {}, {}
		for _, each in ipairs(EndChoices()) do choices[each.value] = each.text end
		for _, each in ipairs(Ends()) do
			if each.kind == "time" then
				ends[#ends + 1] = (L["after %g sec"]):format(each.secs)
			elseif each.kind == "trig" then
				ends[#ends + 1] = (L["when %s starts"]):format(ns.IsLibTrigger(each.ref) and ns.TriggerLabel(each.ref) or "?")
			else
				ends[#ends + 1] = (choices[each.kind] or each.kind):lower()
			end
		end
		return (L["%s. Ends: |cffffd100%s|r. Priority %d."]):format(table.concat(parts, ", "),
			table.concat(ends, L[" or "]), ns.TriggerPri(id))
	end

	function Layout()
		local id, built = Id(), BuiltIn()
		if not PAGE.sub then PAGE.sub = 1 end
		ShowSub(PAGE.sub)
		if id then
			local kind, what = Src(id)
			icon:SetTexture(IconOf(kind, what))
			title:SetText(ns.TriggerLabel(id))
		elseif built then
			icon:SetTexture(built.icon or IconOf(built.kind))
			oursStarts:SetText(built.starts)
			title:SetText(built.name)
		else
			icon:SetTexture(KIND_ICONS.moment)
			title:SetText(L["Trigger"])
		end
		reads:SetText(Sentence())
		local names = {}
		local users = id and ns.TriggerUsers(id) or {}
		if built then
			users = { built.key }
			for _, key in ipairs(ns.TriggerUsers(ns.OursTriggerId(built.key))) do users[#users + 1] = key end
		end
		for _, key in ipairs(users) do names[#names + 1] = ns.SceneDisplayName(key) end
		used:SetText(#names > 0 and table.concat(names, ", ") or L["No scene uses it yet."])
		-- (Ours: another scene can use it while it's one of the standing-still ones.)
		useIn:SetShown(id ~= nil or (built and built.source) ~= nil)
		scenes:SetShown(false)
		priBox:SetShown(id ~= nil or (built and built.source) ~= nil)
		order:SetShown(id ~= nil or (built and built.source) ~= nil)
		ownRules:SetShown(built ~= nil and not built.source)
		for _, control in ipairs(controls) do
			if control.Refresh then control:Refresh() end
		end
		local y = 0
		for _, line in ipairs(lines) do
			local shown = line.tab == PAGE.sub and line.shown() and true or false
			line:SetShown(shown)
			if shown then
				line:ClearAllPoints()
				line:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
				y = y + line:GetHeight()
			end
		end
		body:SetHeight(math.max(1, y))
		kit.FitContentHeight(content)
	end
	local holder = CreateFrame("Frame", nil, content)
	holder:Hide()
	holder.Refresh = function() if canvas:IsVisible() then Layout() else canvas.stale = true end end
	kit.AddControl(holder)
	WhileShown(body, function()
		local id = Id()
		if id then fire:Refresh() end
	end)
	canvas:SetScript("OnShow", kit.PageShown(function()
		kit.Refresh()
		Layout()
	end, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Trigger Settings", L["Trigger"])
end
