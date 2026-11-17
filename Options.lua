-- Cinematic settings: a panel under Options > AddOns, also opened with /cine config
local _, ns = ...
local L = ns.L
-- (The disc behind the pages' "?" help icons, soft-edged at its size: Media/make_help_disc.py.
-- On ns, not a local: this file is near Lua's 200-local cap.)
ns.HELP_DISC = "Interface\\AddOns\\" .. (...) .. "\\Textures\\HelpDisc"

-- Each page is a canvas (registered with the Settings panel) holding a scroll
-- frame; the panel/extrasPanel variables are the scrolling content
-- that the widgets are built on.
local panel, category, extrasPanel, chatPanel
local mainCanvas
local controls = {}   -- widgets that mirror a db key, refreshed on show
-- The settings each page's controls show (page content frame -> key -> true),
-- for its "Reset page" button.
local pageKeys = {}
-- The section of its page each setting (and list row) is in: the header or
-- section band last put on the page before it (content frame -> its title,
-- as shown), for the profile modules (ProfileModules.lua).
-- (fixed: a section whose own headers don't start new ones, a camera's on
-- the Camera Settings page.)
local sectionNow, sectionFixed = {}, {}
local sectionsMet = {} -- (each { frame, title }, in the order they're put on their pages)
local function SetSection(parent, title, fixed)
	if parent and type(title) == "string" and title ~= "" and not sectionFixed[parent] then
		sectionNow[parent] = title
		sectionFixed[parent] = fixed
		sectionsMet[#sectionsMet + 1] = { parent, title }
	end
end
local function SectionOf(parent)
	local frame = parent
	while frame and not sectionNow[frame] do frame = frame:GetParent() end
	return frame and sectionNow[frame] or false
end
-- (section: its section when it's moved from elsewhere, else the one it's in.)
-- A control's setting: a db key, or a field ({ get = fn, set = fn(value) }:
-- a setting that's one key or another, as Heal Vision's and the Unit frames
-- Style page's tabs have it).
local function KeyGet(key)
	if type(key) == "table" then return key.get() end
	local db = ns.GetDB()
	return db and db[key]
end
local function KeyPut(key, value)
	if type(key) == "table" then key.set(value) else ns.GetDB()[key] = value end
end
ns.StyleKeyGet, ns.StyleKeyPut = KeyGet, KeyPut

local function RecordKey(parent, key, section)
	-- (A Look popout's controls count as its page's: StylePages.lua.)
	parent = parent and parent.recordAs or parent
	if type(key) == "string" then
		pageKeys[parent] = pageKeys[parent] or {}
		if not pageKeys[parent][key] then pageKeys[parent][key] = section or SectionOf(parent) end
	end
end
-- Pages sharing a list (the Standard Frames columns: Standard Frames, Gamepad,
-- Advanced Frames) reset only their own rows of it (page -> list -> row ->
-- its section, or false).
local pageRows = {}
local function RecordRow(parent, key, row, section)
	pageRows[parent] = pageRows[parent] or {}
	pageRows[parent][key] = pageRows[parent][key] or {}
	if not pageRows[parent][key][row] then pageRows[parent][key][row] = section or SectionOf(parent) end
end
-- Every page's settings by the page's name (as registered): { keys = key ->
-- section, rows = list -> row -> section, sections = { section... } }, a
-- page's panels counted in it (section: the title of the part of the page
-- it's under, as shown, or false above the first; sections: in the order
-- they're on the page). For the profile modules. Unnamed: under "?".
function ns.PageSettings()
	if ns.MakeLazyPages then ns.MakeLazyPages("the page list") end
	local pages = {}
	local function Page(content)
		local frame = content
		while frame and not frame.pageName do frame = frame:GetParent() end
		local name = frame and frame.pageName or "?"
		pages[name] = pages[name] or { keys = {}, rows = {}, sections = {} }
		return pages[name]
	end
	for _, met in ipairs(sectionsMet) do
		local sections = Page(met[1]).sections
		local seen = false
		for _, title in ipairs(sections) do seen = seen or title == met[2] end
		if not seen then sections[#sections + 1] = met[2] end
	end
	for content, keys in pairs(pageKeys) do
		local page = Page(content)
		for key, section in pairs(keys) do page.keys[key] = page.keys[key] or section end
	end
	for content, lists in pairs(pageRows) do
		local page = Page(content)
		for key, rows in pairs(lists) do
			page.rows[key] = page.rows[key] or {}
			for row, section in pairs(rows) do page.rows[key][row] = page.rows[key][row] or section end
		end
	end
	return pages
end
local extraRows = {}
local sliderCount = 0

-- Changes a label's font. The game picks the font's alphabet (Cyrillic, say,
-- on an English client) when text is set, so text already there is set again:
-- otherwise it falls back to the Latin font and shows boxes.
local function SetLabelFont(label, font)
	label:SetFontObject(font)
	local text = label:GetText()
	if text and text ~= "" then
		label:SetText("")
		label:SetText(text)
	end
end

-- A control's id for /cine find: its setting's key, or its Show in grid
-- row's (row:<key>) for the controls on one. Nil: none.
function ns.SettingIdOf(widget)
	if type(widget.settingKey) == "string" then return widget.settingKey end
	local parent = widget.GetParent and widget:GetParent()
	local rowId = parent and parent.RowId
	if rowId then
		local ok, id = pcall(rowId)
		if ok and type(id) == "string" then return "row:" .. id end
	end
end
-- (Shift pressed or let go over a setting: its tooltip again, with or
-- without its id.)
do
	local watch = CreateFrame("Frame")
	watch:RegisterEvent("MODIFIER_STATE_CHANGED")
	watch:SetScript("OnEvent", function(_, _, key)
		if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
		local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
		local onEnter = owner and owner.searchTip and owner:GetScript("OnEnter")
		if onEnter and ns.SettingIdOf(owner) then onEnter(owner) end
	end)
end

local function Tooltip(widget, tip)
	widget.searchTip = tip
	widget:SetScript("OnEnter", function(self)
		-- (liveTip: a tip set since, the HUD page's "?" moving from section to section)
		local text = self.liveTip or tip
		-- A slider's label can run past its bar: the tip goes beyond whichever
		-- ends further right, so it never covers the value.
		local label = self.tooltipLabel
		if label and label:GetRight() and self:GetRight() and label:GetRight() > self:GetRight() then
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMLEFT", label, "TOPRIGHT", 8, 0)
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		end
		-- A row label cut short (ns.LabelHover): its full name over the tip.
		local full = self.fullLabel
		if full and full:IsTruncated() then
			GameTooltip:SetText(full:GetText(), 1, 0.82, 0)
			GameTooltip:AddLine(text, 1, 1, 1, true)
		else
			GameTooltip:SetText(text, 1, 1, 1, 1, true)
		end
		-- (Shift held: its id, as the command that opens it, to give players.)
		local id = ns.SettingIdOf(self)
		if id and IsShiftKeyDown() then
			GameTooltip:AddLine("/cine find " .. id, 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Hovering a grid row's label (one line, cut short when too long) shows its
-- tip, if any, and its full name while cut short. A name alone goes after a
-- few seconds.
function ns.LabelHover(parent, label, tip)
	local hover = CreateFrame("Frame", nil, parent)
	hover:SetAllPoints(label)
	hover:EnableMouse(true)
	hover.fullLabel = label
	if tip then
		Tooltip(hover, tip)
		return hover
	end
	local shown = 0
	hover:SetScript("OnEnter", function(self)
		if not label:IsTruncated() then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(label:GetText(), 1, 1, 1)
		GameTooltip:Show()
		shown = shown + 1
		local this = shown
		C_Timer.After(3, function()
			if this == shown and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
		end)
	end)
	hover:SetScript("OnLeave", function(self)
		shown = shown + 1
		if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)
	return hover
end

-- The way back from a frame's own page: a button right of its title (or after, a
-- button there already) to the HUD page at its rows' tab (section:
-- its key there, as Frames.lua's ROW_SECTIONS).
function ns.FramesLink(content, title, section, after)
	local button = ns.StyleLink(content, title, "Standard Frames", L["When it shows in CineMode (always, in " ..
		"fights, in places): its rows on the HUD page."], Tooltip, L["HUD"] .. " »", after)
	button:SetScript("OnClick", function() ns.OpenFramesSection(section) end)
	return button
end

-- What the PvP column or box covers, wherever it appears.
local PVP_TIP = L["While you're flagged for PvP, and in battlegrounds and arenas."]

local function Label(parent, font, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	fs:SetText(text or "")
	-- (Titles and headings: in the style theme's accent.)
	if font and font:find("^GameFontNormal") and ns.ToneText then ns.ToneText(fs) end
	return fs
end

-- A page's intro, kept out of the way: a "?" beside its title shows it on
-- hover (and search still finds its words). Returns a flat anchor under the
-- title (or under, if given) for what goes below; hiding it hides the "?" too.
-- (warn: a warning triangle in place of the "?", for an intro that's a caution.)
local function PageIntro(parent, title, text, under, warn)
	-- (A page's first: its intro, behind the "?" on its card on the CineMode page.)
	if parent.introText == nil then parent.introText = text end
	local first = not parent.pageHelp -- (the page's title's "?": its on/off switch goes past it)
	local anchor = CreateFrame("Frame", nil, parent)
	anchor:SetSize(1, 1)
	anchor:SetPoint("TOPLEFT", under or title, "BOTTOMLEFT", 0, -2)

	local help = CreateFrame("Button", nil, anchor)
	help:SetSize(18, 18)
	help:SetPoint("LEFT", title, "RIGHT", 6, 0)
	-- (Above the title's own frame: a camera section's title is on its header.)
	help:SetFrameLevel(math.max(anchor:GetFrameLevel(), title:GetParent():GetFrameLevel()) + 2)
	if warn then
		local icon = help:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
		icon:SetVertexColor(0.9, 0.9, 0.9)
		help:HookScript("OnEnter", function() icon:SetVertexColor(1, 1, 1) end)
		help:HookScript("OnLeave", function() icon:SetVertexColor(0.9, 0.9, 0.9) end)
	else
		local ring = help:CreateTexture(nil, "BACKGROUND")
		ring:SetAllPoints()
		ring:SetTexture(ns.HELP_DISC)
		ring:SetVertexColor(0.3, 0.3, 0.3, 0.9)
		local mark = help:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		mark:SetPoint("CENTER", 1, 0)
		mark:SetText("?")
		mark.searchSkip = true
		help:HookScript("OnEnter", function() mark:SetTextColor(1, 1, 1) end)
		help:HookScript("OnLeave", function() mark:SetTextColor(1, 0.82, 0) end)
	end
	Tooltip(help, text)
	help.searchNote = text
	help.searchEdges = { top = title, bottom = title, left = title, right = help }
	if first then parent.pageHelp, parent.pageTitle = help, title
	elseif title == parent.pageHelp then parent.pageHelpLast = help end -- (a triangle past the "?": the switch goes past it)
	return anchor
end

local function Header(parent, text, anchor, yOffset)
	SetSection(parent, text)
	local fs = Label(parent, "GameFontNormal", text)
	fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset or -18)
	return fs
end

-- Lays out a column of controls, each below the last, the same way on every
-- page: headers and notes at the column edge, checkboxes 2 left of it (so the
-- box lines up), sliders 2 right and edit boxes 6 right (their borders).
-- ("inline": a slider or dropdown on one line with its name, in an inline stack.)
local STACK_X = { header = 0, label = 0, dropdown = 0, check = -2, slider = 2, box = 6, inline = 0 }
local STACK_GAP = { -- [kind being added][kind above it]
	header = { header = 6, label = 18, dropdown = 18, check = 18, slider = 24, box = 18, inline = 18 },
	label = { header = 6, label = 6, dropdown = 6, check = 8, slider = 14, box = 4, inline = 8 },
	dropdown = { header = 8, label = 6, dropdown = 8, check = 6, slider = 14, box = 8, inline = 8 },
	check = { header = 6, label = 8, dropdown = 8, check = 2, slider = 14, box = 8, inline = 2 },
	slider = { header = 26, label = 26, dropdown = 30, check = 26, slider = 34, box = 30, inline = 26 },
	box = { header = 6, label = 4, dropdown = 8, check = 4, slider = 14, box = 8, inline = 6 },
	inline = { header = 6, label = 8, dropdown = 8, check = 4, slider = 12, box = 6, inline = 4 },
}

-- inline: each slider (and each dropdown given an inlineName) goes on one
-- line with its name, as on Graphics+: the bars lined up past the stack's
-- longest name, each value to its bar's right.
-- Every setting's control, by its key (the first made): how to make it
-- again elsewhere (a camera's Camera Scripts page shows a step's settings
-- under it, ns.SettingControl). And the settings a camera's section leaves
-- out, its script page having them (movedFrom: a section's content -> set of
-- keys; a moved control is made on a hidden frame, out of the layout and of
-- search, so what's done with it after still works).
local settingMakers, movedFrom, movedSink = {}, {}, nil
local function Remember(control, key, make)
	-- (A { get, set } field naming its setting, key = "...": that's its id
	-- for /cine find, as a combined Off-or-amount slider's amount.)
	if type(key) == "table" and type(key.key) == "string" then
		control.settingKey = key.key
		return
	end
	-- (Or noSettingId = true: a theme's, a row's or a wheel's value, no one
	-- setting to find; the offline check leaves it out, ns.SettingIds.)
	if type(key) == "table" and key.noSettingId then control.noSettingId = true end
	if type(key) ~= "string" then return end
	control.settingKey = key
	if not settingMakers[key] then settingMakers[key] = { make = make, control = control } end
end

local function Stack(anchor, kind, inline)
	-- (Inline on every page since 2026-11-15, user: "all sliders same line like
	-- in Graphics+". false keeps a stack's sliders with their names above.)
	local stack = { last = anchor, kind = kind or "header", indent = 0, inline = inline ~= false, rows = {} }
	stack.moved = anchor and anchor.GetParent and movedFrom[anchor:GetParent()] or nil
	local parent = anchor and anchor.GetParent and anchor:GetParent()
	if stack.moved and not stack.moved.noted then
		stack.moved.noted = true
		local note = Label(parent, "GameFontHighlightSmall", L["The rest of its settings are on the Scripts page, under the steps they make: pick this camera there."])
		note:SetWidth(520)
		note:SetJustifyH("LEFT")
		note:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
		stack.last, stack.kind = note, "label"
	end
	-- (A header waits for the first control under it that isn't moved: none,
	-- and it's left out too.)
	local function Moved(control)
		if not (stack.moved and control.settingKey and stack.moved[control.settingKey]) then return false end
		if not movedSink then
			movedSink = CreateFrame("Frame", nil, UIParent)
			movedSink:Hide()
		end
		control:SetParent(movedSink)
		control:ClearAllPoints()
		control.searchLabel = nil
		return true
	end
	-- Puts control below the last one. indent: how far right of the usual
	-- place it sits (children of a checkbox); the next control is placed from it.
	function stack:Add(control, controlKind, indent)
		if Moved(control) then return control end
		if self.moved then self.moved.left = true end -- (its section still has settings: a tab of its own)
		if self.waiting then
			local header = self.waiting
			self.waiting = nil
			header:Show()
			self:Add(header, "header")
		end
		-- (subIndent: a Look panel's sub-settings, set by its rows.Sub.)
		indent = indent or self.subIndent or 0
		local placed = control
		if self.inline and (controlKind == "slider" or control.inlineName) then
			placed = self:InlineRow(control, controlKind)
			controlKind = "inline"
		end
		-- (Under a page's hidden Enable switch, already 14 below the title: no
		-- more gap than a tick's, bar a slider's room for its name.)
		local gap = STACK_GAP[controlKind][self.kind]
		if self.last.hiddenSwitch and controlKind ~= "slider" then gap = math.min(gap, 2) end
		-- (A centered preview's spot: where it'd have been, the column's edge.)
		placed:SetPoint("TOPLEFT", self.last.stackSpot or self.last, "BOTTOMLEFT",
			STACK_X[controlKind] + indent - STACK_X[self.kind] - self.indent, -gap)
		self.last, self.kind, self.indent = placed, controlKind, indent
		return control
	end
	-- The line an inline control sits on, its name at the left.
	function stack:InlineRow(control, controlKind)
		local row = CreateFrame("Frame", nil, control:GetParent())
		row:SetSize(1, 22)
		local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetJustifyH("LEFT")
		name:SetPoint("LEFT")
		name:SetText(control.inlineName or control.searchLabel or "")
		name.searchSkip = true
		control.rowName = name
		if controlKind == "slider" then
			control.valueOnly = true
			control:SetWidth(180)
			control.title:ClearAllPoints()
			control.title:SetPoint("LEFT", control, "RIGHT", 10, 0)
			control.searchEdges = { top = control, bottom = control, left = name, right = control.title }
		end
		control.rowX = STACK_X[controlKind] -- (a slider's bar sits 2 right of where it's put)
		self.rows[#self.rows + 1] = { row = row, control = control }
		self.nameWidth = math.max(self.nameWidth or 0, name:GetStringWidth())
		for _, each in ipairs(self.rows) do
			each.control:ClearAllPoints()
			each.control:SetPoint("LEFT", each.row, "LEFT", self.nameWidth + 20 + each.control.rowX, 0)
		end
		return row
	end
	function stack:Header(parent, text)
		SetSection(parent, text)
		local header = Label(parent, "GameFontNormal", text)
		if self.moved then
			if self.waiting then self.waiting:Hide() end
			self.waiting = header
			header:Hide()
			return header
		end
		return self:Add(header, "header")
	end
	-- A note in small text, wrapped to width.
	function stack:Note(parent, text, width)
		local note = Label(parent, "GameFontHighlightSmall", text)
		note:SetWidth(width or 270)
		note:SetJustifyV("TOP")
		return self:Add(note, "label")
	end
	-- A note kept behind a "?" beside the header just added (see PageIntro).
	function stack:Help(parent, text)
		self.last, self.kind = PageIntro(parent, self.last.stackSpot or self.last, text), "label"
		return self.last
	end
	-- Carries on from a control placed some other way.
	function stack:Continue(control, controlKind)
		self.last, self.kind, self.indent = control, controlKind, 0
	end
	return stack
end

local function Check(parent, key, label, tip, onChange)
	local cb = ns.SkinCheck(CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate"))
	cb:SetSize(26, 26)
	local text = cb.Text or cb.text
	if not text then
		text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	end
	text:SetFontObject("GameFontHighlight")
	text:SetText(label)
	if tip then Tooltip(cb, tip) end
	cb.searchLabel = label
	cb.searchEdges = { top = cb, bottom = cb, left = cb, right = text }

	cb:SetScript("OnClick", function(self)
		local value = self:GetChecked() and true or false
		if onChange then onChange(value) else KeyPut(key, value) end
	end)
	cb.Refresh = function(self) self:SetChecked(KeyGet(key)) end
	controls[#controls + 1] = cb
	RecordKey(parent, key)
	Remember(cb, key, function(where, changed)
		return Check(where, key, label, tip, function(value)
			if onChange then onChange(value) else KeyPut(key, value) end
			changed(value)
		end)
	end)
	return cb
end

-- A labelled slider. `scale` converts between stored and shown values
-- (letterbox size is stored as a fraction but shown as a percent).
local function Slider(parent, key, label, minV, maxV, step, fmt, scale, onChange)
	scale = scale or 1
	RecordKey(parent, key)
	sliderCount = sliderCount + 1
	local name = "CinematicOptionsSlider" .. sliderCount
	local ok, slider = pcall(CreateFrame, "Slider", name, parent, "OptionsSliderTemplate")
	if not ok then
		-- Fallback for clients without the template.
		slider = CreateFrame("Slider", name, parent)
		slider:SetOrientation("HORIZONTAL")
		slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
		local bg = slider:CreateTexture(nil, "BACKGROUND")
		bg:SetColorTexture(0, 0, 0, 0.5)
		bg:SetPoint("LEFT", 0, 0)
		bg:SetPoint("RIGHT", 0, 0)
		bg:SetHeight(6)
	end
	slider:SetSize(200, 16)
	-- (A range below 0 runs from 0 on the slider itself, moved back as it's
	-- read: dragging the game's slider from -40 to 40 skipped 0.)
	local offset = minV < 0 and -minV or 0
	slider:SetMinMaxValues(minV + offset, maxV + offset)
	slider:SetValueStep(step)
	if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

	-- Hide the template's own min/max/title text; we draw a single label.
	for _, suffix in ipairs({ "Low", "High", "Text" }) do
		local fs = slider[suffix] or _G[name .. suffix]
		if fs then fs:Hide() end
	end
	ns.SkinSlider(slider) -- (the menu look: Skin.lua)

	local title = Label(slider, "GameFontHighlight")
	title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)
	slider.tooltipLabel = title
	if label ~= "" then
		slider.searchLabel = label
		slider.searchEdges = { top = title, bottom = slider, left = slider, right = slider }
	else
		title.searchSkip = true -- (just the value; its label is drawn beside it)
	end

	local function UpdateTitle(value)
		local shown = "|cffffd100" .. (type(fmt) == "function" and fmt(value) or fmt:format(value)) .. "|r"
		title:SetText((label == "" or slider.valueOnly) and shown or label .. ": " .. shown)
	end
	slider.title = title

	slider:SetScript("OnValueChanged", function(self, value)
		value = math.floor((value - offset) / step + 0.5) * step
		UpdateTitle(value)
		if self.refreshing then return end
		if type(key) == "table" then
			key.set(value / scale)
		else
			ns.GetDB()[key] = value / scale
		end
		if onChange then onChange(value) end
	end)
	slider.Refresh = function(self)
		local value = (type(key) == "table" and key.get() or ns.GetDB()[key]) * scale
		self.refreshing = true
		self:SetValue(value + offset)
		self.refreshing = false
		UpdateTitle(value)
	end
	controls[#controls + 1] = slider
	Remember(slider, key, function(where, changed)
		return Slider(where, key, label, minV, maxV, step, fmt, scale, function(value)
			if onChange then onChange(value) end
			changed(value)
		end)
	end)
	return slider
end

-- A line of small number boxes, each with its name before it, in place of
-- a slider each (the Nameplate Style page's W and H boxes): the mouse wheel
-- steps a box, or a number's typed and Enter pressed. `scale` and `fmt` as
-- Slider's; a name may be blank (the box beside the one before); unit: a
-- word after the box (sec), the number alone in it. Without one, a
-- slider's fmt ("%d%%", "%.2fs") is split so: the number in the box, the
-- rest after it. key: a setting's name, or { get, set } as Slider's.
local function BoxLine(parent)
	local line = CreateFrame("Frame", nil, parent)
	line:SetSize(10, 22)
	local right = 0
	function line.Box(_, label, key, minV, maxV, step, fmt, scale, tip, onChange, width, unit)
		scale = scale or 1
		RecordKey(parent, key)
		if type(fmt) == "string" and not unit then
			local number, after = fmt:match("^(%%[%d%.]*[df])%s*(.*)$")
			if number and after ~= "" then
				fmt, unit = number, (after:gsub("%%%%", "%%"))
			end
		end
		local name = Label(line, "GameFontHighlight", label)
		name:SetPoint("LEFT", line, "LEFT", right, 0)
		name.searchSkip = true
		local box = ns.SkinEditBox(CreateFrame("EditBox", nil, line, "InputBoxTemplate"))
		box:SetSize(width or 36, 20)
		box:SetPoint("LEFT", name, "RIGHT", label ~= "" and 8 or 0, 0)
		box:SetAutoFocus(false)
		box:SetJustifyH("RIGHT")
		box:SetMaxLetters(6)
		box:EnableMouseWheel(true)
		box.searchLabel = label
		-- (its id, as Remember gives a checkbox: the Why window's links, /cine find <key>; a { get, set }
		-- field's key = "...")
		box.settingKey = type(key) == "table" and key.key or key
		box.noSettingId = type(key) == "table" and key.noSettingId or nil
		right = right + (label ~= "" and name:GetStringWidth() + 8 or 0) + (width or 36) + 18
		if unit then
			local after = Label(line, "GameFontHighlight", unit)
			after:SetPoint("LEFT", box, "RIGHT", 4, 0)
			after.searchSkip = true
			box.unitLabel = after
			right = right + after:GetStringWidth() + 4
		end
		-- (Found by search: its page scrolls to it and it glows.)
		box.searchEdges = { top = box, bottom = box, left = name, right = box.unitLabel or box }
		line:SetWidth(right)
		-- (Greyed, the box and its words dim: a disabled box alone looks the same.)
		local setEnabled = box.SetEnabled
		function box.SetEnabled(self, enabled)
			if setEnabled then setEnabled(self, enabled) end
			local alpha = enabled and 1 or 0.5
			self:SetAlpha(alpha)
			name:SetAlpha(alpha)
			if self.unitLabel then self.unitLabel:SetAlpha(alpha) end
		end
		local function Now()
			local value = type(key) == "table" and key.get() or ns.GetDB()[key]
			return (value or 0) * scale
		end
		local percent = scale == 100 or (unit and unit:match("^%%"))
		-- (A % box shows a typed 3.25 as 3.25%, whole numbers as before.)
		local function Shown(value)
			if type(fmt) == "function" then return fmt(value) end
			if percent and math.abs(value - math.floor(value + 0.5)) > 1e-6 then
				local text = ("%.2f"):format(value):gsub("0+$", ""):gsub("%.$", "")
				return (fmt:gsub("%%[%d%.]*[df]", "%%s", 1)):format(text)
			end
			return fmt:format(value)
		end
		-- (A typed number is kept as typed, to the decimals the box shows,
		-- not snapped to step; a % box keeps two decimals (3.2%), whichever
		-- it shows; a % box's wheel moves 1% a time.)
		local exact = step
		if type(fmt) == "string" then
			local decimals = fmt:match("%%[%d]*%.(%d)f")
			exact = fmt:match("%%[%d]*d") and 1 or decimals and 10 ^ -tonumber(decimals) or step
			exact = math.min(exact, step)
		end
		if percent then exact = math.min(exact, 0.01) end
		local wheelStep = percent and math.min(1, step) or step
		local function Set(value)
			value = math.max(minV, math.min(maxV, math.floor(value / exact + 0.5) * exact))
			if type(key) == "table" then
				key.set(value / scale)
			else
				ns.GetDB()[key] = value / scale
			end
			box:SetText(box:HasFocus() and tostring(value) or Shown(value))
			box.edited = nil
			if onChange then onChange(value) end
		end
		box:SetScript("OnMouseWheel", function(self, delta)
			if not self:IsEnabled() then return end
			-- (From a typed 3.2%, the wheel goes to 4% or 3%, back on the steps.)
			local steps = Now() / wheelStep
			local near = math.floor(steps + 0.5)
			if math.abs(steps - near) > 1e-6 then
				Set((delta > 0 and math.ceil(steps) or math.floor(steps)) * wheelStep)
			else
				Set(Now() + delta * wheelStep)
			end
		end)
		box:SetScript("OnEditFocusGained", function(self)
			self:SetText(tostring(math.floor(Now() / exact + 0.5) * exact))
			self:HighlightText()
			self.edited = nil
		end)
		-- (Only a number typed in it is saved on leaving it.)
		box:SetScript("OnTextChanged", function(self, typed)
			if typed then self.edited = true end
		end)
		box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		box:SetScript("OnEscapePressed", function(self)
			self.cancelled = true
			self:ClearFocus()
		end)
		box:SetScript("OnEditFocusLost", function(self)
			local typed = tonumber((self:GetText():match("%-?[%d%.]+")))
			if typed and self.edited and not self.cancelled then
				Set(typed)
			end
			self.cancelled, self.edited = nil, nil
			self:SetText(Shown(Now()))
		end)
		box.Refresh = function(self)
			if not self:HasFocus() then self:SetText(Shown(Now())) end
		end
		controls[#controls + 1] = box
		Tooltip(box, tip or L["Scroll the mouse wheel over it, or type a number and press Enter."])
		return box, name
	end
	-- A "show below" box (Health & Resources, Heal Vision): each share as "up
	-- while under it" (< 50%), not full as < 100%, 0 Off and the top step
	-- Always. Its steps (wheel): 0 Off, 1-98 a share, 99 not full (saved as
	-- notFull: 0.99 or 0.999, as its page reads it), 100 Always (saved 1).
	-- Typed: 100 (or 99) not full, "a..." Always, "o..." or 0 Off. field: a
	-- setting's name or { get, set } as Box's; onChange(step). calm (Health &
	-- Resources): the saved share for "not full, only during Calm Timer", a
	-- step of its own after not full (< 100% Calm; Always moves to 101).
	local NOT_FULL_STEP = 99
	local function Trim(step)
		return (("%.2f"):format(step):gsub("0+$", ""):gsub("%.$", ""))
	end
	function line.ShareBox(_, field, tip, onChange, notFull, width, calm)
		local get = type(field) == "table" and field.get or function() return ns.GetDB()[field] end
		local set = type(field) == "table" and field.set or function(value) ns.GetDB()[field] = value end
		local CALM_STEP = calm and NOT_FULL_STEP + 1 or nil
		local ALWAYS_STEP = calm and NOT_FULL_STEP + 2 or NOT_FULL_STEP + 1
		local function StepOf(share)
			share = tonumber(share) or 0
			if share >= 1 then return ALWAYS_STEP end
			if calm and math.abs(share - calm) < 1e-6 then return CALM_STEP end
			if share >= 0.99 - 1e-6 then return NOT_FULL_STEP end
			return share * 100
		end
		local function ShareOf(step)
			if step >= ALWAYS_STEP then return 1 end
			if calm and step >= CALM_STEP then return calm end
			if step >= NOT_FULL_STEP then return notFull end
			return math.max(0, step) / 100
		end
		local function Text(step)
			if step <= 0 then return L["Off"] end
			if step >= ALWAYS_STEP then return L["Always"] end
			if calm and step >= CALM_STEP then return L["< 100% Calm"] end
			if step >= NOT_FULL_STEP then return "< 100%" end
			return ("< %s%%"):format(Trim(step))
		end
		local box = line:Box("", {
			get = function() return StepOf(get()) / 100 end,
			set = function(value) set(ShareOf(value * 100)) end,
		}, 0, ALWAYS_STEP, 1, Text, 100, tip, onChange, width or 56)
		box:SetMaxLetters(12) -- (< 3.25%, and the words in other languages)
		if type(field) == "string" then
			RecordKey(parent, field)
			box.settingKey = field
		elseif type(field.key) == "string" then
			box.settingKey = field.key
		end
		-- (Typing starts from the number or word the box shows; typed words too.)
		box:SetScript("OnEditFocusGained", function(self)
			local step = StepOf(get())
			self:SetText(step <= 0 and "0" or step >= ALWAYS_STEP and L["Always"]
				or calm and step >= CALM_STEP and L["< 100% Calm"] or step >= NOT_FULL_STEP and "100" or Trim(step))
			self:HighlightText()
			self.edited = nil
		end)
		box:SetScript("OnEditFocusLost", function(self)
			local step
			if self.edited and not self.cancelled then
				local text = self:GetText():lower()
				local always, off = L["Always"]:lower():sub(1, 2), L["Off"]:lower():sub(1, 2)
				local calmWord = L["Calm"]:lower():sub(1, 2)
				local number = tonumber((text:match("[%d%.]+")))
				if text:find("^%s*a") or text:find("^%s*" .. always, 1) then
					step = ALWAYS_STEP
				elseif text:find("^%s*o") or text:find("^%s*" .. off, 1) then
					step = 0
				elseif calm and (text:find("^%s*c") or text:find(calmWord, 1, true)) then
					step = CALM_STEP
				elseif number then
					step = number >= NOT_FULL_STEP and NOT_FULL_STEP or math.max(0, math.min(98, number))
				end
			end
			if step then
				set(ShareOf(step))
				if onChange then onChange(step) end
			end
			self.cancelled, self.edited = nil, nil
			self:SetText(Text(StepOf(get())))
		end)
		-- An arrow on its right: Always, < 100% (and < 100% Calm) and Off one
		-- click away (the wheel and typing hid them). No menus on the client:
		-- each click moves to the next.
		local arrow = CreateFrame("Button", nil, line)
		arrow:SetSize(18, 18)
		arrow:SetPoint("LEFT", box, "RIGHT", 2, 0)
		arrow:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
		arrow:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
		arrow:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
		arrow:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight", "ADD")
		line:SetWidth(line:GetWidth() + 20)
		local function Pick(step)
			set(ShareOf(step))
			box:Refresh()
			if onChange then onChange(step) end
		end
		local PICKS = { { ALWAYS_STEP, L["Always"] }, { NOT_FULL_STEP, L["< 100% (not full)"] } }
		if calm then PICKS[#PICKS + 1] = { CALM_STEP, L["< 100% Calm (not full, only during Calm Timer)"] } end
		PICKS[#PICKS + 1] = { 0, L["Off"] }
		arrow:SetScript("OnClick", function(self)
			if box:HasFocus() then box:ClearFocus() end
			if MenuUtil and MenuUtil.CreateContextMenu then
				ns.ContextMenu(self, function(_, root)
					for _, pick in ipairs(PICKS) do
						root:CreateRadio(pick[2], function() return StepOf(get()) == pick[1] end,
							function() Pick(pick[1]) end)
					end
				end)
				return
			end
			local now, next = StepOf(get()), 1
			for i, pick in ipairs(PICKS) do
				if pick[1] == now then next = i % #PICKS + 1 end
			end
			Pick(PICKS[next][1])
		end)
		Tooltip(arrow, calm and L["Pick Always, < 100%, < 100% Calm or Off, or scroll over the box for other shares."]
			or L["Pick Always, < 100% or Off, or scroll over the box for other shares."])
		-- (Greyed with its box.)
		local setEnabled = box.SetEnabled
		function box.SetEnabled(self, enabled)
			setEnabled(self, enabled)
			arrow:SetEnabled(enabled and true or false)
			arrow:SetAlpha(enabled and 1 or 0.5)
		end
		box.arrow = arrow
		return box
	end
	-- A round pick before the next box (its name first, if any): ticked
	-- while setting key is value, a click sets it (onPick(value) after: the
	-- box's number filled in, say). Two on a line: one or the other.
	function line.Pick(_, label, key, value, tip, onChange, onPick)
		RecordKey(parent, key)
		local name = Label(line, "GameFontHighlight", label or "")
		name:SetPoint("LEFT", line, "LEFT", right, 0)
		name.searchSkip = true
		local hasName = label and label ~= ""
		local ok, pick = pcall(CreateFrame, "CheckButton", nil, line, "UIRadioButtonTemplate")
		if ok and pick then
			ns.SkinCheck(pick, true)
		else
			pick = ns.SkinCheck(CreateFrame("CheckButton", nil, line, "UICheckButtonTemplate"))
		end
		pick:SetSize(18, 18)
		-- (line.nameWidth: names at least so wide, lines of picks lined up.)
		local nameWidth = hasName and math.max(name:GetStringWidth(), line.nameWidth or 0) + 8 or 0
		pick:SetPoint("LEFT", line, "LEFT", right + nameWidth, 0)
		-- (The box after it clear of it: an input box's art reaches out left.)
		right = right + nameWidth + 18 + 12
		line:SetWidth(right)
		pick.searchLabel = hasName and label or nil
		pick.settingKey = key
		pick:SetScript("OnClick", function()
			ns.GetDB()[key] = value
			if onPick then onPick(value) end
			if onChange then onChange(value) end
		end)
		local setEnabled = pick.SetEnabled
		function pick.SetEnabled(self, enabled)
			if setEnabled then setEnabled(self, enabled) end
			self:SetAlpha(enabled and 1 or 0.5)
			name:SetAlpha(enabled and 1 or 0.5)
		end
		pick.Refresh = function(self)
			self:SetChecked(ns.GetDB()[key] == value)
		end
		controls[#controls + 1] = pick
		if tip then Tooltip(pick, tip) end
		return pick, name
	end
	return line
end

-- Greys a control out unless test(db) holds (checkbox labels dim too).
local function GreyUnless(control, test)
	control.greyTest = test -- (for ns.SettingControl)
	local refresh = control.Refresh
	control.Refresh = function(self)
		refresh(self)
		local enabled = test(ns.GetDB())
		if self.SetEnabled then self:SetEnabled(enabled) end
		local label = self.Text or self.text
		if label and self.GetObjectType and self:GetObjectType() == "CheckButton" then
			SetLabelFont(label, enabled and "GameFontHighlight" or "GameFontDisable")
		elseif self.title and self.GetObjectType and self:GetObjectType() == "Slider" then
			SetLabelFont(self.title, enabled and "GameFontHighlight" or "GameFontDisable")
		end
		if self.rowName then -- (an inline stack's row name)
			SetLabelFont(self.rowName, enabled and "GameFontHighlight" or "GameFontDisable")
		end
	end
end

-- The pages' master switches (handle<...>; see PageSwitch): page content ->
-- { key, check }. While one is off, every other control on its page greys
-- out, keeping its value; switched on, each is back as its own settings say.
local pageSwitches = {}
local function SwitchOf(control)
	if control.pageSwitch == nil then
		local frame = control:GetParent()
		while frame and not pageSwitches[frame] do
			frame = frame:GetParent()
		end
		control.pageSwitch = frame and pageSwitches[frame] or false
	end
	return control.pageSwitch
end

-- (Dev copy: how long each control's refresh took, the slowest kept for
-- PageShown's timing line. ns.pageTiming: { count, slowest = { {ms, name} } }.)
local function ControlName(control)
	return control.debugName or control.searchLabel
		or (control.GetObjectType and control:GetObjectType()) or "?"
end
-- One control as its setting is now (timing: the dev copy's, as Refresh's).
local function RefreshControl(control, timing)
	local started = timing and debugprofilestop()
	local switch = control.SetEnabled and SwitchOf(control)
	if switch and switch.check ~= control then
		-- (Enabled first, so its own greying decides; then off with the switch.)
		local label = control.GetObjectType and control:GetObjectType() == "CheckButton"
			and (control.Text or control.text)
		if label then
			control.baseFont = control.baseFont or label:GetFontObject() or "GameFontHighlight"
			SetLabelFont(label, control.baseFont)
		end
		control:SetEnabled(true)
		control:Refresh()
		local master = ns.PageSwitchOf(switch.key)
		if not ns.GetDB()[switch.key] or (master and ns.GetDB()[master] == false) then
			control:SetEnabled(false)
			if label then SetLabelFont(label, "GameFontDisable") end
		end
	else
		-- (A page's switch greys with the one it's under: a vision's with Enable Visions.)
		local master = switch and ns.PageSwitchOf(switch.key)
		local label = master and (control.Text or control.text)
		if label then
			control.baseFont = control.baseFont or label:GetFontObject() or "GameFontHighlight"
			SetLabelFont(label, control.baseFont)
			control:SetEnabled(true)
		end
		control:Refresh()
		if master and ns.GetDB()[master] == false then
			control:SetEnabled(false)
			if label then SetLabelFont(label, "GameFontDisable") end
		end
	end
	if timing then
		local ms = debugprofilestop() - started
		if ms > 1 then
			local slowest = timing.slowest
			slowest[#slowest + 1] = { ms, ControlName(control) }
			table.sort(slowest, function(a, b) return a[1] > b[1] end)
			slowest[6] = nil
		end
	end
end

-- The settings page a control is on (RegisterSubpage marks them), or nil:
-- not on one (the welcome window's, a popup's).
local function PageOf(control)
	if control.onSettingsPage then return control.onSettingsPage end
	-- (A plain table's owner: the frame it lays out, so it's skipped with it.)
	local frame = control.GetParent and control:GetParent() or control.owner
	while frame and not frame.pageWatch do
		frame = frame:GetParent()
	end
	control.onSettingsPage = frame -- (not kept when nil: its page may not be registered yet)
	return frame
end

-- A control on no settings page, its parent hidden: refreshed as that shows
-- (once, however many Refreshes passed it by).
local function StaleTillShown(control, parent)
	control.staleTillShown = true
	if parent.staleControls then
		parent.staleControls[control] = true
		return
	end
	parent.staleControls = { [control] = true }
	parent:HookScript("OnShow", function(self)
		for each in pairs(self.staleControls) do
			self.staleControls[each] = nil
			if each.staleTillShown then
				each.staleTillShown = nil
				RefreshControl(each)
			end
		end
	end)
end

-- Every control as its setting is now. Only the pages on screen: a page out
-- of sight is marked stale and refreshed as it comes into view (its
-- pageWatch), as a switch of profile refreshing them all took ~130 ms.
local function Refresh()
	if not ns.GetDB() then return end
	local timing = (ns.isDev or ns.pageRun) and { count = #controls, refreshed = 0, slowest = {} }
	ns.pageTiming = timing
	for _, control in ipairs(controls) do
		local page = PageOf(control)
		local parent = not page and (control.GetParent and control:GetParent() or control.owner)
		-- (On a page shown, but in a part of it that's hidden: the HUD's other
		-- sections, a tab not picked. Refreshed as that part shows, 2026-11-16:
		-- each HUD icon refreshed all 147 rows, ~20 ms.)
		local hiddenPart
		if page and page:IsVisible() and control.GetParent then
			local at = control:GetParent()
			while at and at ~= page and not hiddenPart do
				if at.IsShown and not at:IsShown() then hiddenPart = at end
				at = at.GetParent and at:GetParent() or nil
			end
		end
		if page and not page:IsVisible() then
			page.stale = true
		elseif hiddenPart then
			StaleTillShown(control, hiddenPart)
		elseif parent and not parent:IsVisible() then
			-- (On no settings page and out of sight (the Customize window's, a
			-- popup's): refreshed as its parent shows. ~400 of these refreshed on
			-- every page opened took 20-35 ms.)
			StaleTillShown(control, parent)
		else
			if page then page.stale = nil end -- (refreshed now: its pageWatch needn't again)
			control.staleTillShown = nil
			RefreshControl(control, timing)
			if timing then timing.refreshed = timing.refreshed + 1 end
		end
	end
	if ns.PaintPageSwitches then ns.PaintPageSwitches() end -- (the hub icons' Off marks)
	if ns.PaintHeaderSwitches then ns.PaintHeaderSwitches() end -- (the switches by page titles)
end

-- A page's master switch at the top (below anchor): "CineMode <page>". Not
-- shown: a right-click on the page's icon (or folder tab) flips it, and the
-- icon says whether it's on. (Kept, 1 high, for the page's layout and greying.)
-- Shown instead: an On/Off switch right of the page's title, past its "?"
-- (and before a Style link there, moved along), the same as that right-click.
-- Made as the page first shows, its title's parts all there by then.
local function PaintHeaderSwitch(toggle)
	if not ns.GetDB() then return end
	local master = ns.PageSwitchOf(toggle.key)
	local held = master and ns.GetDB()[master] == false
	local on = not held and KeyGet(toggle.key) and true or false
	toggle.fill:SetColorTexture(on and 0.16 or 0.22, on and 0.52 or 0.07, on and 0.2 or 0.05, 1)
	toggle.knob:ClearAllPoints()
	toggle.knob:SetPoint(on and "RIGHT" or "LEFT", on and -2 or 2, 0)
	toggle.text:ClearAllPoints()
	toggle.text:SetPoint("CENTER", on and -7 or 7, 0)
	toggle.text:SetText(on and L["On"] or L["Off"])
	toggle.text:SetTextColor(1, 1, 1, held and 0.4 or 1)
	toggle:SetEnabled(not held)
end
local function MakeHeaderSwitch(content, switch)
	if switch.header or not (switch.check and content.pageHelp) then return end
	local toggle = CreateFrame("Button", nil, content.pageHelp:GetParent())
	toggle:SetSize(46, 18)
	toggle:SetPoint("LEFT", content.pageHelpLast or content.pageHelp, "RIGHT", 8, 0)
	toggle:SetFrameLevel(content.pageHelp:GetFrameLevel())
	toggle.key, toggle.check = switch.key, switch.check
	local edge = toggle:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0.45, 0.38, 0.2, 1)
	toggle.fill = toggle:CreateTexture(nil, "BORDER")
	toggle.fill:SetPoint("TOPLEFT", 1, -1)
	toggle.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	toggle.knob = toggle:CreateTexture(nil, "ARTWORK")
	toggle.knob:SetSize(14, 14)
	toggle.knob:SetColorTexture(0.85, 0.8, 0.65, 1)
	toggle.text = toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	toggle.text.searchSkip = true
	local hl = toggle:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 1, -1)
	hl:SetPoint("BOTTOMRIGHT", -1, 1)
	hl:SetColorTexture(1, 1, 1, 0.12)
	Tooltip(toggle, L["Turns this page on or off (as a right-click on its icon)."])
	toggle:SetScript("OnClick", function(self)
		local on = KeyGet(self.key) and true or false
		self.check:SetChecked(not on)
		self.check:GetScript("OnClick")(self.check, "LeftButton")
		if PlaySound and SOUNDKIT then
			PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
		PaintHeaderSwitch(self)
		if ns.PaintPageSwitches then ns.PaintPageSwitches() end
	end)
	toggle:SetScript("OnShow", PaintHeaderSwitch)
	-- (A Style link right of the title: now right of the switch.)
	local link = content.titleLink
	if link and link.linkTitle == content.pageTitle then
		link:ClearAllPoints()
		link:SetPoint("LEFT", toggle, "RIGHT", 8, 0)
	end
	switch.header = toggle
	content.pageHeaderSwitch = toggle -- (for pages in other files: shown or not as their part says)
	-- (content.headerSwitchOff: a part of the page with no switch of its own
	-- picked, a HUD section's banner icon: hidden till its HUD icon is.)
	toggle:SetShown(not content.headerSwitchOff)
	if content.tabbedPage then ns.DropPageHeader(content) end -- (a page under tabs: none, StylePages.lua)
	PaintHeaderSwitch(toggle)
end
ns.PaintHeaderSwitches = function()
	for _, switch in pairs(pageSwitches) do
		if switch.header and switch.header:IsVisible() then PaintHeaderSwitch(switch.header) end
	end
end
local function RegisterPageSwitch(content, key, check)
	local switch = { key = key, check = check }
	pageSwitches[content] = switch
	if check then
		check:Hide()
		check:SetHeight(1)
		check.searchLabel = nil
		check.hiddenSwitch = true -- (the stack under it starts close: Stack's Add)
		content:HookScript("OnShow", function() MakeHeaderSwitch(content, switch) end)
		if content:IsVisible() then MakeHeaderSwitch(content, switch) end
	end
end
local function PageSwitch(content, key, label, tip, anchor, onChange)
	local check = Check(content, key, label, tip, function(value)
		ns.GetDB()[key] = value
		if onChange then onChange(value) end
		Refresh()
	end)
	check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -2, -14)
	RegisterPageSwitch(content, key, check)
	return check
end
-- A checkbox that acts as one choice in a group sharing a db key.
local function Choice(parent, key, value, label, tip)
	local cb = Check(parent, key, label, tip, function()
		KeyPut(key, value)
		Refresh()
	end)
	cb.Refresh = function(self) self:SetChecked(KeyGet(key) == value) end
	return cb
end

-- A box of our own beside a dropdown, showing a font file (a font list's
-- hovered entry): its name and a line of letters in it, sized to them, just
-- right of the hovered line (line: the menu's; else the dropdown).
-- FontSample(nil) hides it; it hides itself too once the dropdown's menu closes.
local sample
local function FontSample(dropdown, file, name, line)
	if not dropdown then
		if sample then sample:Hide() end
		return
	end
	if not sample then
		sample = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
		sample:SetFrameStrata("TOOLTIP")
		if sample.SetBackdrop then
			sample:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
				edgeSize = 1 })
			sample:SetBackdropColor(0, 0, 0, 0.9)
			sample:SetBackdropBorderColor(1, 0.82, 0, 1)
		end
		sample.name = sample:CreateFontString(nil, "OVERLAY")
		sample.name:SetPoint("TOPLEFT", 10, -8)
		sample.name:SetWordWrap(false)
		sample.line = sample:CreateFontString(nil, "OVERLAY")
		sample.line:SetPoint("TOPLEFT", sample.name, "BOTTOMLEFT", 0, -6)
		sample.line:SetWordWrap(false)
		ns.SetOnUpdate(sample, function(self)
			if not (self.dropdown and self.dropdown.IsMenuOpen and self.dropdown:IsMenuOpen()) then self:Hide() end
		end)
	end
	-- (A file the game won't set yet, not loaded: the game's, until it is.)
	local fallback = (GameFontHighlight:GetFont())
	for text, size in pairs({ [sample.name] = 18, [sample.line] = 14 }) do
		local ok, set = pcall(text.SetFont, text, file, size, "")
		if not ok or set == false then text:SetFont(fallback, size, "") end
	end
	sample.name:SetText(name)
	sample.name:SetTextColor(1, 0.82, 0)
	sample.line:SetText("The quick brown fox 0123")
	sample.line:SetTextColor(1, 1, 1)
	sample:SetSize(math.max(sample.name:GetStringWidth(), sample.line:GetStringWidth()) + 20,
		sample.name:GetStringHeight() + sample.line:GetStringHeight() + 22)
	sample.dropdown = dropdown
	sample:ClearAllPoints()
	if line and line.GetRight then
		sample:SetPoint("LEFT", line, "RIGHT", 16, 0) -- (past the menu's edge)
	else
		sample:SetPoint("LEFT", dropdown, "RIGHT", 12, 0)
	end
	sample:Show()
end

-- A dropdown for a db key with a fixed set of choices ({ value, text,
-- enabled = optional test(db): greyed in the menu unless it holds }), or
-- a function giving them each time the menu opens.
-- Returns nil on clients without the modern dropdown template.
local function Dropdown(parent, key, choices, width, onChange)
	local ok, dropdown = ns.MenuDropdown(parent)
	if not ok or not dropdown or not dropdown.SetupMenu then
		return nil
	end
	dropdown:SetWidth(width or 200)
	dropdown.searchSkip = true -- (it shows the current choice, not a label)
	dropdown:SetupMenu(function(_, rootDescription)
		-- (A long list scrolls: ns.MenuDropdown's.)
		local list = type(choices) == "function" and choices() or choices
		for _, choice in ipairs(list) do
			local radio = rootDescription:CreateRadio(choice.text,
				-- SetupMenu builds the menu right away, before saved settings load.
				function()
					return ns.GetDB() ~= nil and KeyGet(key) == choice.value
				end,
				function()
					KeyPut(key, choice.value)
					if onChange then onChange(choice.value) end
					Refresh()
				end)
			-- (choice.texture: a strip of it at the entry's right, as the Style
			-- pages' texture lists show each; tinted choice.tint.)
			if choice.texture and radio and radio.AddInitializer then
				radio:AddInitializer(function(button)
					if not button.AttachTexture then return end
					local strip = button:AttachTexture()
					if choice.atlas then strip:SetAtlas(choice.texture) else strip:SetTexture(choice.texture) end
					strip:SetSize(90, 12)
					strip:SetPoint("RIGHT", button, "RIGHT", -6, 0)
					local tint = choice.tint or { 0.3, 0.75, 0.35 }
					strip:SetVertexColor(tint[1], tint[2], tint[3], 1)
					-- (Grey last, both ways: the menu's pooled textures came back
					-- in their own colors with only SetDesaturated, before the rest.)
					local grey = choice.atlas and true or false
					strip:SetDesaturated(grey)
					if strip.SetDesaturation then strip:SetDesaturation(grey and 1 or 0) end
				end)
			end
			-- (choice.font: hovered, a sample of it beside the dropdown. The menu's
			-- own lines can't take a font: the game won't let addons SetFont them.)
			if choice.font and radio and radio.SetOnEnter then
				radio:SetOnEnter(function(line) FontSample(dropdown, choice.font, choice.text, line) end)
				if radio.SetOnLeave then radio:SetOnLeave(function() FontSample(nil) end) end
			end
			-- (choice.tip: its tooltip in the open menu.)
			if choice.tip and radio and radio.SetTooltip then
				radio:SetTooltip(function(tooltip)
					tooltip:SetText(choice.text, 1, 1, 1)
					tooltip:AddLine(choice.tip, nil, nil, nil, true)
				end)
			end
			local db = ns.GetDB()
			if choice.enabled and db and radio and radio.SetEnabled then
				radio:SetEnabled(choice.enabled(db) and true or false)
			end
		end
	end)
	dropdown.Refresh = function(self) self:GenerateMenu() end
	controls[#controls + 1] = dropdown
	RecordKey(parent, key)
	Remember(dropdown, key, function(where, changed)
		return Dropdown(where, key, choices, width, function(value)
			if onChange then onChange(value) end
			changed(value)
		end)
	end)
	return dropdown
end

-- A setting's control made again on parent, as its own page has it (its
-- tip, its greying): changed(value) after each change. Nil for a setting
-- with no control remembered.
function ns.SettingControl(key, parent, changed)
	local made = settingMakers[key]
	if not made then return nil end
	local control = made.make(parent, changed)
	if not control then return nil end
	if made.control.searchTip then Tooltip(control, made.control.searchTip) end
	if made.control.greyTest then GreyUnless(control, made.control.greyTest) end
	control.settingType = made.control.GetObjectType and made.control:GetObjectType() or nil
	control.settingName = made.control.inlineName -- (a dropdown's name, drawn beside it on its own page)
	return control
end

local SCROLLBAR_WIDTH = 26

-- Puts a page's settings back to their defaults: each setting its controls
-- show (a list kept as a table, like the Standard Frames columns, is emptied,
-- which means its defaults).
-- Lists whose defaults are in code and that are nil until changed (emptied,
-- they'd be an empty list rather than the defaults).
local RESET_TO_NIL = { hoverGroups = true }

-- The unit frames' parts and their names, in the order the pages list them.
function ns.UnitPartLabels()
	return {
		{ "Portrait", L["Portrait"] }, { "Name", L["Name"] }, { "NameBack", L["Name background"] },
		{ "Level", L["Level"] }, { "LevelBack", L["Level background"] },
		{ "Health", L["Health bar"] }, { "DeadText", L["Dead text"] }, { "Power", L["Power bar"] }, { "Numbers", L["Bar numbers"] },
		{ "Art", L["Frame art"] },
		{ "PvP", L["PvP icon"] }, { "Icons", L["Icons"] }, { "Auras", L["Auras"] },
		{ "CombatText", L["Hit text"] }, { "Threat", L["Threat"] }, { "CastBar", L["Cast bar"] },
	}
end
-- Lists holding what you made beside settings: a page's Reset leaves those
-- entries as they are, as Reset Settings does (Profiles.lua's
-- RESET_PROFILE_KEEPS). [key] = fn(entry): true for one of yours.
local CAMERA_ROWS_MINE = { order = true, custom = true, extras = true, sort = true }
local CAMERA_ROW_FIELDS_MINE = { name = true, triggers = true } -- (your names and added triggers, on any row)
local RESET_KEEPS_MINE = {
	-- (The Nameplates rows' names you gave them.)
	markNames = function() return true end,
	-- (Your own triggers and the copies of rows you added: all of theirs. The
	-- rows' order, as it says which copies there are. A built-in trigger's own
	-- row goes back: its ticks, When, and Add back for one you deleted.)
	cameraRows = function(entry)
		if CAMERA_ROWS_MINE[entry] then return true end
		local id, field = tostring(entry):match("^([^.]+)%.(.+)$")
		if not id then return false end
		if CAMERA_ROW_FIELDS_MINE[field] then return true end
		local trigger, copy = ns.CameraRowTrigger(id)
		return copy ~= nil or (trigger ~= nil and trigger.custom == true)
	end,
}
-- More for a page's reset to do: [page content] = fn, after its settings are back.
local resetHooks = {}
local function DeepCopy(source)
	if type(source) ~= "table" then return source end
	local result = {}
	for k, v in pairs(source) do result[k] = DeepCopy(v) end
	return result
end
-- only: just these settings of the page (a part's own Reset), key -> true.
local function ResetPage(content, only)
	local db = ns.GetDB()
	-- (The active profile's values, not just the defaults; its reset point's
	-- if the player saved one.)
	local base = ns.ResetBase()
	local point = db.profileResetPoints and db.profileResetPoints[ns.ActiveProfile()]
	for key in pairs(pageKeys[content] or {}) do
		local default = base[key]
		local rows = pageRows[content] and pageRows[content][key]
		local mine = RESET_KEEPS_MINE[key]
		if only and not only[key] then -- luacheck: ignore 542 (not this part's)
		elseif mine and type(db[key]) == "table" then
			-- Back to the profile's own entries, but for yours.
			local from = type(default) == "table" and default or {}
			for k in pairs(db[key]) do
				if not mine(k) and from[k] == nil then db[key][k] = nil end
			end
			for k, v in pairs(from) do
				if not mine(k) then db[key][k] = DeepCopy(v) end
			end
		elseif RESET_TO_NIL[key] and not (point and point[key]) then
			db[key] = nil
		elseif type(default) == "table" then
			-- A built-in profile's own list or the reset point's (copied: those
			-- stay as they are), just this page's rows of it when pages share it.
			if rows and type(db[key]) == "table" then
				for k in pairs(rows) do db[key][k] = DeepCopy(default[k]) end
			else
				db[key] = DeepCopy(default)
			end
		elseif type(db[key]) == "table" and default == nil then
			for k in pairs(db[key]) do
				if not rows or rows[k] then
					db[key][k] = nil
				end
			end
		else
			db[key] = default
		end
	end
	ns.letterboxDirty = true
	if ns.ResyncVitalsLook then ns.ResyncVitalsLook() end -- (the theme's own look back on its settings)
	if resetHooks[content] then resetHooks[content]() end
	if ns.InvalidateSceneGroups then ns.InvalidateSceneGroups() end -- (the Scenes page's rows, changed in place)
	if ns.RefreshTint then ns.RefreshTint() end
	if ns.ApplyBubbles then ns.ApplyBubbles() end
	if ns.ApplyUnitFrameParts then ns.ApplyUnitFrameParts() end
	if ns.RefreshActionBarStyle then ns.RefreshActionBarStyle() end
	if ns.RefreshMinimapStyle then ns.RefreshMinimapStyle() end
	if ns.RefreshQuestTrackerStyle then ns.RefreshQuestTrackerStyle() end
	if ns.RefreshInterfaceRecolor then ns.RefreshInterfaceRecolor() end
	if ns.ApplyGraphicsPlus then ns.ApplyGraphicsPlus() end
	Refresh()
end

StaticPopupDialogs.CINEMATIC_RESET_PAGE = {
	text = L["Put this page's settings back to the profile's own?"],
	button1 = YES, button2 = NO,
	OnAccept = function(_, content) ResetPage(content) end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
-- A part of a page's own Reset: data = { content, keys = key -> true, after = fn }.
StaticPopupDialogs.CINEMATIC_RESET_PART = {
	text = L["Put these settings back to the profile's own?"],
	button1 = YES, button2 = NO,
	OnAccept = function(_, data)
		ResetPage(data.content, data.keys)
		if data.after then data.after() end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

-- noReset: no "Reset page" button (the main page has its own reset for everything).
local function CreateScrollPage(noReset)
	local canvas = CreateFrame("Frame")
	local scroll = ns.SkinScroll(CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate"))
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_WIDTH, 4)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(600, 1)
	scroll:SetScrollChild(content)
	canvas.scroll, canvas.content = scroll, content
	scroll:SetScript("OnSizeChanged", function(_, width)
		content:SetWidth(width)
	end)
	-- Every page gets a "Reset page" button, top right; it scrolls away with
	-- the top of the page (left in place, the settings scrolled under it), and
	-- goes on a page with no settings of its own.
	local reset = ns.PanelButton(content)
	reset:SetSize(100, 22)
	reset:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, -8)
	reset:SetText(L["Reset page"])
	reset.searchSkip = true
	Tooltip(reset, L["Puts this page's settings back to your profile's values."])
	reset:SetScript("OnClick", function()
		StaticPopup_Show("CINEMATIC_RESET_PAGE", nil, nil, content)
	end)
	reset:SetScript("OnShow", function(self)
		if noReset or not pageKeys[content] then
			self:Hide()
		end
	end)
	canvas.resetButton = reset
	return canvas, content
end

-- How far below its top a frame's widgets reach (nil before it's laid out).
local function ContentDepth(content)
	local top = content:GetTop()
	if not top then
		return nil
	end
	local lowest = top
	local function consider(object)
		if object:IsShown() then
			local bottom = object:GetBottom()
			if bottom and bottom < lowest then
				lowest = bottom
			end
		end
	end
	for _, child in ipairs({ content:GetChildren() }) do
		consider(child)
		if child:IsShown() then
			for _, grandchild in ipairs({ child:GetChildren() }) do consider(grandchild) end
			for _, region in ipairs({ child:GetRegions() }) do consider(region) end
		end
	end
	for _, region in ipairs({ content:GetRegions() }) do consider(region) end
	return top - lowest
end

-- Size the scrolling content to reach just past its lowest widget, so the
-- scroll range always fits however many settings a page has.
local function FitContentHeight(content)
	local depth = ContentDepth(content)
	if depth then
		content:SetHeight(depth + 16)
	end
end

-- OnShow for a page: refresh, then fit the scroll height (again next frame,
-- once text and anchors have settled).
local function PageShown(refresh, content)
	return function()
		-- (/cine debug pages: a page opened from the list, not its icon, timed on its own)
		local own = not ns.pageRun and CinematicDB and CinematicDB.pageTimesOn
			and ns.StartPageRun(((PageOf(content) or {}).pageName or "?") .. " (from the list)")
		local started = debugprofilestop()
		ns.ApplyMenuSkin() -- (the Menu look, as it is now: Forever's Character Models may have changed)
		local looked = debugprofilestop()
		ns.pageTiming = nil
		refresh()
		local refreshed = debugprofilestop()
		FitContentHeight(content)
		local fitted = debugprofilestop()
		-- (Dev copy: a line in chat when a page is slow to open, to find why.
		-- Off for now; set ns.pageTimingLog = true to bring it back.)
		if ns.isDev and ns.pageTimingLog and fitted - started > 30 then
			local timing, slow = ns.pageTiming, {}
			for _, each in ipairs(timing and timing.slowest or {}) do
				slow[#slow + 1] = ("%s %.0f"):format(each[2], each[1])
			end
			ns.Print(("page open %.0f ms: look %.0f, refresh %.0f (%s controls; slowest: %s), fit %.0f"):format(
				fitted - started, looked - started, refreshed - looked, timing and timing.count or "?",
				#slow > 0 and table.concat(slow, ", ") or "-", fitted - refreshed))
		end
		local run = ns.pageRun
		if run then
			local timing = ns.pageTiming
			run.look, run.refresh, run.fit = looked - started, refreshed - looked, fitted - refreshed
			run.controls = timing and ("%d of %d"):format(timing.refreshed or 0, timing.count or 0)
			local slow = {}
			for _, each in ipairs(timing and timing.slowest or {}) do
				slow[#slow + 1] = ("%s %.1f"):format(each[2], each[1])
			end
			run.slowest = table.concat(slow, ", ")
		end
		if own then
			own.show = fitted - started
			ns.EndPageRun(own)
		end
		C_Timer.After(0, function()
			local fitStart = run and debugprofilestop()
			FitContentHeight(content)
			if run then run.laterFit = (run.laterFit or 0) + debugprofilestop() - fitStart end
		end)
	end
end

-- (/cine debug pages: each page switch timed into CinematicDB.pageTimes, the
-- last 30, for finding why switching pages lags. Its steps' ms, then the whole
-- frame's: from the click to the next frame, the game's layout and drawing too.)
function ns.StartPageRun(name)
	if not (CinematicDB and CinematicDB.pageTimesOn) then
		ns.pageRun = nil
		return
	end
	ns.pageVisits = ns.pageVisits or {}
	ns.pageVisits[name] = (ns.pageVisits[name] or 0) + 1
	local run = { name = name, started = debugprofilestop(), fps = GetFramerate(), visit = ns.pageVisits[name] }
	ns.pageRun = run
	return run
end
-- (ns.pageRunWatch: the first OnUpdate after a switch: when the game's own drawing of it is done)
function ns.EndPageRun(run)
	if not run or ns.pageRun ~= run then return end
	run.lua = debugprofilestop() - run.started
	ns.pageRun = nil
	ns.pageRunWatch = ns.pageRunWatch or CreateFrame("Frame")
	ns.pageRunWatch:SetScript("OnUpdate", function(self)
		self:SetScript("OnUpdate", nil)
		run.update = debugprofilestop() - run.started
	end)
	C_Timer.After(0, function()
		local frame = debugprofilestop() - run.started
		local list = CinematicDB.pageTimes or {}
		CinematicDB.pageTimes = list
		table.insert(list, 1, ("%s (visit %d): lua %.1f ms (select %.1f, show %.1f [look %.1f, refresh %.1f, fit %.1f], "
			.. "switches %.1f), first OnUpdate at %.1f, later fit %.1f, to next frame %.1f ms (a frame is %.1f); "
			.. "controls %s; slowest: %s"):format(
			tostring(run.name), run.visit, run.lua, run.select or 0, run.show or 0, run.look or 0, run.refresh or 0,
			run.fit or 0, run.switches or 0, run.update or -1, run.laterFit or -1, frame,
			1000 / math.max(run.fps, 1), run.controls or "-",
			run.slowest ~= "" and run.slowest or "-"))
		list[61] = nil -- (60 kept: a whole settings tour)
	end)
end

-- The pages' sections that open and close with a click remember it across
-- reloads (ns.db.sectionsOpen: section.id -> true or false); one never
-- clicked opens as its page says. Pages are built before the settings load,
-- so Restore takes what was saved at the first layout after they have.
local SectionState = {}
-- What was saved for id, or default.
function SectionState.Saved(id, default)
	local saved = ns.db and ns.db.sectionsOpen and ns.db.sectionsOpen[id]
	if saved == nil then
		return default
	end
	return saved
end
-- section: { id, open }. (open nil: back to what its page says.)
function SectionState.Save(section, open)
	section.open = open
	if ns.db and ns.db.sectionsOpen then
		ns.db.sectionsOpen[section.id] = open
	end
end
function SectionState.Restore(section)
	if not section.restored and ns.db and ns.db.sectionsOpen then
		section.restored = true
		section.open = SectionState.Saved(section.id, section.open)
	end
	return section.open
end

-- Search (on the main page): finds a setting on any page by its label,
-- tooltip or note, and opens its page with it highlighted. (The game's own
-- search box can't see inside pages drawn like these.)
local searchPages = {} -- { name = page name (nil: the main page), canvas = its canvas }, as listed
-- Every settings page as listed (PageShots.lua walks them): read only.
function ns.SettingsPages() return searchPages end
-- Our settings pages on the screen now, kept as they show and hide (a hidden
-- settings window hides them too), for ns.OurSettingsShown: asking every
-- page each time cost 0.1 ms a call, a profile showed, 2026-11-11.
ns.shownSettingsCanvases = {}
function ns.WatchSettingsCanvas(canvas)
	local shown = ns.shownSettingsCanvases
	canvas:HookScript("OnShow", function(self) shown[self] = true end)
	canvas:HookScript("OnHide", function(self) shown[self] = nil end)
	if canvas:IsVisible() then shown[canvas] = true end
end

-- Text as shown, without colour codes; nil if it has no words.
local function SearchText(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " ")
	if not text:find("%a") then return nil end
	return text
end

-- Every page's settings, headings and notes as they are now (pages show and
-- hide rows as settings change). rank: 0 a page, 1 a label or heading, 3 a note.
-- pages: just those pages' (a sub-page's or hub's own search box).
-- Also the controls by their setting's key (frame.settingKey, set by
-- Remember): keyed[key] = the first such entry found.
ns.searchPrepare = {} -- pages that fill their rows only when shown: called to fill them before a search
-- Pages whose body is made the first time they're needed, not at login: the
-- two that cost the most to make (HUD ~300 ms and Hover Groups ~190 ms of the
-- ~1.35 s every page took on Forever, 2026-11-16). Opening the page makes it,
-- and so does anything that reads every page: the search (and /cine find),
-- ns.PageSettings (the profiles), ns.SettingIds. The log says when each is made.
local lazyPages = { list = {}, waiting = {} }
function lazyPages.Add(canvas, name, build)
	local made = false
	local entry = {}
	local function Make(why)
		if made then return end
		made = true
		entry.made = true
		local started = type(debugprofilestop) == "function" and debugprofilestop()
		ns.Guard(build)
		local ended = type(started) == "number" and debugprofilestop()
		if type(ended) == "number" and ns.Log then
			ns.Log("load", ("settings page %s made when first needed (%s) in %d ms"):format(name, why or "?",
				ended - started))
		end
	end
	-- (The page's own OnShow, set as it's made, runs straight after.)
	local function FirstShow(self, ...)
		Make("opened")
		local onShow = self:GetScript("OnShow")
		if onShow and onShow ~= FirstShow then onShow(self, ...) end
	end
	canvas:SetScript("OnShow", FirstShow)
	lazyPages.list[#lazyPages.list + 1] = Make
	entry.Make, entry.name = Make, name
	lazyPages.waiting[#lazyPages.waiting + 1] = entry
	return Make
end
-- Made ahead, one at a quiet moment each (2026-11-16: the HUD's alone till
-- then; Nameplates, Nameplate Style and Hover Groups took 100-200 ms on
-- their first opening). Checked each second: out of combat, the settings
-- closed, not casting, on no flight path, standing still these last 5
-- seconds; then the next page not made yet is, and 3 more quiet seconds
-- before the one after. All made: the checks stop. (One opened before its
-- turn: made then, as before.)
function lazyPages.StartAhead()
	if lazyPages.ticker then return end
	local still = 0
	lazyPages.ticker = C_Timer.NewTicker(1, function()
		local settings = _G.SettingsPanel or _G.InterfaceOptionsFrame
		local casting = (UnitCastingInfo and UnitCastingInfo("player")) or (UnitChannelInfo and UnitChannelInfo("player"))
		local busy = InCombatLockdown() or (settings and settings:IsShown()) or casting
			or (UnitOnTaxi and UnitOnTaxi("player")) or (GetUnitSpeed and GetUnitSpeed("player") or 0) > 0
		still = busy and 0 or still + 1
		if still < 5 then return end
		for _, entry in ipairs(lazyPages.waiting) do
			if not entry.made then
				entry.Make("ahead, standing still")
				still = 2
				return
			end
		end
		lazyPages.ticker:Cancel()
	end)
end
-- (For pages made in other files: ns.LazyPageBody(canvas, name, build).)
ns.LazyPageBody = lazyPages.Add
function ns.MakeLazyPages(why)
	for _, Make in ipairs(lazyPages.list) do Make(why) end
end
ns.searchPrepare[#ns.searchPrepare + 1] = function() ns.MakeLazyPages("search") end
local function BuildSearchIndex(pages)
	Refresh() -- (slider titles and some rows are only filled in on refresh)
	for _, prepare in ipairs(ns.searchPrepare) do prepare() end
	local entries, keyed = {}, {}
	local named = not pages or #pages > 1 -- (pages to pick among: their names count too)
	for _, page in ipairs(pages or searchPages) do
		local seen = {}
		local function add(text, tip, rank, edges)
			text = SearchText(text)
			if not text or seen[text] then return end
			seen[text] = true
			tip = SearchText(tip)
			entries[#entries + 1] = { page = page, text = text, lower = text:lower(),
				tip = tip and tip:lower(), rank = rank, edges = edges, order = #entries }
		end
		if named then add(page.name or "Cinematic", nil, 0) end
		local function walk(frame)
			-- (IsShown: the frame's own flag, so hidden rows are left out even on
			-- pages that aren't open)
			-- (A closed section's settings count: finding one opens it.)
			if frame.searchSkip or not (frame:IsShown() or frame.searchAlways) then return end
			-- (A Show in grid row: row:<its rule's key>, GridRows.lua.)
			if frame.RowId then
				local ok, id = pcall(frame.RowId)
				if ok and type(id) == "string" and not keyed["row:" .. id] then
					keyed["row:" .. id] = { page = page, text = id,
						edges = { top = frame, bottom = frame, left = frame, right = frame } }
				end
			end
			local settingKey = frame.settingKey
			if type(settingKey) == "string" and not keyed[settingKey] then
				keyed[settingKey] = { page = page, text = SearchText(frame.searchLabel) or settingKey,
					edges = frame.searchEdges or { top = frame, bottom = frame, left = frame, right = frame } }
			end
			if frame.searchNote then -- (a page intro behind its "?")
				add(frame.searchNote, nil, 3, frame.searchEdges)
				return
			end
			if frame.searchLabel then
				add(frame.searchLabel, frame.searchTip, 1, frame.searchEdges)
				return
			end
			local tip = frame.searchTip -- (a button's or box's tooltip goes with its text)
			for _, region in ipairs({ frame:GetRegions() }) do
				if region:GetObjectType() == "FontString" and not region.searchSkip and region:IsShown() then
					local text = region:GetText()
					local rank = (type(text) == "string" and #text <= 40) and 1 or 3
					add(text, tip, rank, { top = region, bottom = region, left = region, right = region })
					tip = nil
				end
			end
			for _, child in ipairs({ frame:GetChildren() }) do
				walk(child)
			end
		end
		walk(page.canvas.content)
		-- (The page's Enable switch: its checkbox is hidden, the switch drawn
		-- in the page's header (RegisterPageSwitch), so the walk above never
		-- reaches it and /cine find handleSwing found nothing, 2026-11-16.)
		local switch = pageSwitches[page.canvas.content]
		if switch and not keyed[switch.key] then
			keyed[switch.key] = { page = page, text = L["Enable Page"], pageSwitch = switch }
		end
	end
	return entries, keyed
end

-- The best matches for what's typed (every word in the label, or in the
-- label and tooltip together).
local function SearchMatches(index, query)
	local words = {}
	for word in query:lower():gmatch("%S+") do words[#words + 1] = word end
	local function has(text)
		for _, word in ipairs(words) do
			if not text:find(word, 1, true) then return false end
		end
		return true
	end
	local matches = {}
	for _, entry in ipairs(index) do
		if has(entry.lower) then
			entry.score = entry.rank
			matches[#matches + 1] = entry
		elseif entry.tip and has(entry.lower .. " " .. entry.tip) then
			entry.score = math.max(entry.rank, 2)
			matches[#matches + 1] = entry
		end
	end
	table.sort(matches, function(a, b)
		if a.score ~= b.score then return a.score < b.score end
		return a.order < b.order
	end)
	return matches
end

-- A brief glow over a found setting.
local function Highlight(canvas, edges)
	local glow = canvas.searchGlow
	if not glow then
		glow = CreateFrame("Frame", nil, canvas.content)
		glow.searchSkip = true
		glow:SetFrameLevel(canvas.content:GetFrameLevel() + 10)
		local texture = glow:CreateTexture(nil, "OVERLAY")
		texture:SetAllPoints()
		texture:SetColorTexture(1, 0.82, 0, 0.25)
		ns.SetOnUpdate(glow, function(self, elapsed)
			self.time = self.time + elapsed
			if self.time >= 2.5 then
				self:Hide()
			else
				self:SetAlpha(math.min(1, 2.5 - self.time))
			end
		end)
		canvas.searchGlow = glow
	end
	glow:ClearAllPoints()
	glow:SetPoint("TOP", edges.top, "TOP", 0, 3)
	glow:SetPoint("BOTTOM", edges.bottom, "BOTTOM", 0, -3)
	glow:SetPoint("LEFT", edges.left, "LEFT", -4, 0)
	glow:SetPoint("RIGHT", edges.right, "RIGHT", 6, 0)
	glow.time = 0
	glow:SetAlpha(1)
	glow:Show()
end

-- Hubs (below): HubTab(name) shows a page in its hub.
local HubAdd, HubTab

-- Opens a match's page, scrolled to it and highlighted. onPage: it's
-- already open (found by its own search box, or its hub's).
local function ShowMatch(entry, onPage)
	HubTab(entry.page.key) -- (a hub's page: its tab picked)
	-- In a closed section of the Camera Settings page: opened first.
	local object = entry.edges and entry.edges.top
	while object do
		if object.openSection then
			object.openSection()
			break
		end
		object = object:GetParent()
	end
	if not onPage then ns.OpenOptions(entry.page.key) end
	local canvas = entry.page.canvas
	-- (A page's Enable switch, in its header: made as the page shows, so
	-- looked up once it has.)
	if entry.pageSwitch then
		C_Timer.After(0.1, function()
			local header = entry.pageSwitch.header
			canvas.scroll:SetVerticalScroll(0)
			if header then Highlight(canvas, { top = header, bottom = header, left = header, right = header }) end
		end)
		return
	end
	if not entry.edges then return end
	-- (once the page has shown and sized itself)
	C_Timer.After(0.1, function()
		local content, scroll = canvas.content, canvas.scroll
		local top, contentTop = entry.edges.top:GetTop(), content:GetTop()
		if not top or not contentTop then return end
		local offset = contentTop - top - 40
		scroll:SetVerticalScroll(math.max(0, math.min(offset, scroll:GetVerticalScrollRange())))
		Highlight(canvas, entry.edges)
	end)
end

-- /cine find <words>: the settings search's best match for them, opened as
-- clicking it would (its page, scrolled to it, glowing). Returns its text and
-- its page's name, or nil with nothing found. Page|Page|words looks only on
-- pages with all those names (ns.PageOnPath), as the same words are on many
-- pages: Style|Names|fade time. After a pipe, the first word can be a page
-- too: Style|Names fade time (tried first, then as all words). (Pipes come
-- from the chat box doubled: any run of them splits.)
function ns.FindSetting(query)
	-- A setting's id (/cine find nfHealthPlayer), or a Show in row's
	-- (/cine find row:player): straight to its control.
	local id = type(query) == "string" and (query:match("^%s*([%w_]+)%s*$") or query:match("^%s*(row:%S+)%s*$"))
	-- (A Nameplates row's setting too, as customMark1Size: ns.MarkRowDefault.)
	if id and (ns.DEFAULTS[id] ~= nil or id:find("^row:") or (ns.MarkRowDefault and ns.MarkRowDefault(id) ~= nil))
		and ns.OpenSettingByKey then
		local text, pageName = ns.OpenSettingByKey(id)
		if text then return text, pageName end
	end
	local parts = {}
	for part in (type(query) == "string" and query or ""):gmatch("[^|]+") do
		part = part:match("^%s*(.-)%s*$"):lower()
		if part ~= "" then parts[#parts + 1] = part end
	end
	local words = table.remove(parts)
	if not words then return nil end
	-- Only page names (ui visibility minimap): that page opened, at its top.
	-- The words name the page's path in menu order, top down, and the page
	-- with the most of them in its own name wins (the first listed on a tie).
	if #parts == 0 then
		local list = {}
		for word in words:gmatch("%S+") do list[#list + 1] = word end
		local bestPage, bestScore = nil, 0
		for _, page in ipairs(searchPages) do
			if ns.PageOnPathInOrder(page.key, list) then
				local own = ((page.key or "Cinematic") .. " " .. (page.name or "") .. " "
					.. (ns.PageLabel(page.key or "Cinematic") or "")):lower()
				local score = 0
				for _, word in ipairs(list) do
					if own:find(word, 1, true) then score = score + 1 end
				end
				if score > bestScore then bestPage, bestScore = page, score end
			end
		end
		if bestPage then
			ShowMatch({ page = bestPage })
			return bestPage.name or "Cinematic", L["page"]
		end
	end
	local function Best(text)
		local pages
		if #parts > 0 then
			pages = {}
			for _, page in ipairs(searchPages) do
				if ns.PageOnPath(page.key, parts) then pages[#pages + 1] = page end
			end
			if #pages == 0 then return nil end
		end
		return SearchMatches(BuildSearchIndex(pages), text)[1]
	end
	local best
	local first, rest = words:match("^(%S+)%s+(.+)$")
	if first and #parts > 0 then
		parts[#parts + 1] = first
		best = Best(rest)
		parts[#parts] = nil
	end
	best = best or Best(words)
	if not best then return nil end
	ShowMatch(best)
	return best.text, best.page.name or "Cinematic"
end

local SEARCH_ROWS = 12

-- The search box, with its matches listed in a box below it (over the page).
-- pages: searches just those (a sub-page's or hub's box, top right beside Reset page).
local function CreateSearch(canvas, parent, pages)
	local page = pages and true -- (a box for some pages, not the main one)
	local named = not pages or #pages ~= 1 -- (matches show their page's name; a hub's list grows)
	local ok, box = pcall(CreateFrame, "EditBox", nil, parent, "SearchBoxTemplate")
	if not ok or not box then
		box = ns.SkinEditBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
	end
	box:SetSize(page and 180 or 260, 20)
	box:SetAutoFocus(false)
	box.searchSkip = true
	if box.Instructions then
		box.Instructions:SetText(page and L["Search this page"] or L["Search Cinematic's settings"])
	end

	local list = CreateFrame("Frame", nil, parent)
	list.searchSkip = true
	if page then
		list:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 2, -2)
		list:SetWidth(420)
	else
		list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -2)
		list:SetWidth(580)
	end
	list:SetFrameLevel(parent:GetFrameLevel() + 20)
	list:EnableMouse(true) -- (clicks don't reach the settings underneath)
	list:Hide()
	local border = list:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0.45, 0.38, 0.2, 1)
	local bg = list:CreateTexture(nil, "BORDER")
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(0.05, 0.05, 0.05, 0.97)

	local rows, matches, index = {}, {}, nil
	local function Row(i)
		if rows[i] then return rows[i] end
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(20)
		row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
		row:SetPoint("RIGHT", -4, 0)
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.1)
		row.text = Label(row, "GameFontHighlight")
		row.text:SetPoint("LEFT", 6, 0)
		row.text:SetPoint("RIGHT", -6, 0)
		row.text:SetWordWrap(false)
		row:SetScript("OnClick", function(self)
			if not self.entry then return end
			list:Hide()
			box:ClearFocus()
			ShowMatch(self.entry, page)
		end)
		rows[i] = row
		return row
	end

	-- The matches from offset on; the mouse wheel scrolls through the rest.
	local offset = 0
	local function Draw()
		local shown = math.min(#matches - offset, SEARCH_ROWS)
		for i = 1, shown do
			local entry, row = matches[offset + i], Row(i)
			local text = entry.text
			if #text > 70 then text = text:sub(1, 67) .. "..." end
			row.entry = entry
			row.text:SetText(not named and text or
				("|cffffd100" .. (entry.page.name or "Cinematic") .. ":|r  " .. text))
			row:Show()
		end
		local lines = shown
		local below = #matches - offset - shown
		if #matches == 0 or below > 0 then
			lines = lines + 1
			local row = Row(lines)
			row.entry = nil
			row.text:SetText(#matches == 0 and L["|cff808080Nothing found|r"] or
				("|cff808080" .. L["Scroll for %d more"]:format(below) .. "|r"))
			row:Show()
		end
		for i = lines + 1, #rows do rows[i]:Hide() end
		list:SetHeight(lines * 20 + 8)
	end
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(offset - delta, #matches - SEARCH_ROWS))
		Draw()
	end)

	local function Update()
		local query = (box:GetText() or ""):match("^%s*(.-)%s*$")
		if query == "" then
			list:Hide()
			return
		end
		index = index or BuildSearchIndex(pages)
		matches = SearchMatches(index, query)
		offset = 0
		Draw()
		list:Show()
	end

	box:HookScript("OnTextChanged", Update)
	-- A fresh look at the pages each time you start searching, and the
	-- matches back for what's still typed there.
	box:HookScript("OnEditFocusGained", function()
		index = nil
		Update()
	end)
	box:HookScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if matches[1] and list:IsShown() then
			list:Hide()
			ShowMatch(matches[1], page)
		end
	end)
	box:HookScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	canvas:HookScript("OnHide", function() list:Hide() end)
	return box
end

local function CreatePanel()
	mainCanvas, panel = CreateScrollPage(true)
	mainCanvas.name = "Cinematic"
	mainCanvas.pageName = "Cinematic" -- (ns.PageSettings)

	local title = Label(panel, "GameFontNormalLarge", "Cinematic")
	title:SetPoint("TOPLEFT", 16, -16)
	-- The version beside it ("dev" for the development copy, or run from the
	-- source, where the packager hasn't filled it in).
	local version = ns.Version()
	if version:find("project%-version") then version = "dev" end
	local versionLabel = Label(panel, "GameFontDisableSmall", version)

	local subtitle = PageIntro(panel, title,
		L["Fades the UI and adds letterbox bars between fights for a cinematic view."])
	-- (Past the title's "?", which sits where it used to be and hid it.)
	versionLabel:SetPoint("LEFT", panel.pageHelp, "RIGHT", 6, 0)

	local searchBox = CreateSearch(mainCanvas, panel)
	searchBox:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 6, -14)

	-- Left column: general
	local general = Header(panel, L["General"], subtitle, -54)

	-- (No Enable Cinematic box: off is the game's AddOns list, or /cine,
	-- which asks and reloads with it off there. ns.TurnOffCompletely.)
	local minimapButton = Check(panel, "minimapButton", L["Show minimap button"],
		L["Click it for quick options and a link to these settings, drag to move it."], function(value)
			ns.GetDB().minimapButton = value
			if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		end)
	minimapButton:SetPoint("TOPLEFT", general, "BOTTOMLEFT", -2, -6)

	-- (Only where the game has a compartment.)
	local aboveGlow = minimapButton
	if AddonCompartmentFrame then
		aboveGlow = Check(panel, "addonCompartment", L["Show in addon compartment"],
			L["Lists Cinematic in the game's addon list by the minimap."],
			function(value)
				ns.GetDB().addonCompartment = value
				if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
			end)
		aboveGlow:SetPoint("TOPLEFT", minimapButton, "BOTTOMLEFT", 0, -2)
	end

	local glowHelper = Check(panel, "minimapHelper", L["Minimap Glow Helper"],
		L["The minimap button glows while a vision is doing something."])
	glowHelper:SetPoint("TOPLEFT", aboveGlow, "BOTTOMLEFT", 0, -2)

	local slashComplete = Check(panel, "slashComplete", L["Suggest /cine commands while typing"],
		L["Typing /cine in chat lists the commands that fit."])
	slashComplete:SetPoint("TOPLEFT", glowHelper, "BOTTOMLEFT", 0, -2)

	-- The language Cinematic's text is in: for the account, not a profile, and
	-- set as the addon loads (Locales.lua), so a change asks to reload. Each
	-- language is named in itself.
	local languageLabel = Label(panel, "GameFontHighlight", L["Language"])
	languageLabel:SetPoint("TOPLEFT", slashComplete, "BOTTOMLEFT", 4, -14)
	local LANGUAGES = {
		{ value = "auto", text = L["Game language"] },
		{ value = "enUS", text = "English" },
		{ value = "deDE", text = "Deutsch" },
		{ value = "esES", text = "Español" },
		{ value = "frFR", text = "Français" },
		{ value = "itIT", text = "Italiano" },
		{ value = "koKR", text = "한국어" },
		{ value = "ptBR", text = "Português (Brasil)" },
		{ value = "ruRU", text = "Русский" },
		{ value = "zhCN", text = "简体中文" },
		{ value = "zhTW", text = "繁體中文" },
	}
	local function CurrentLanguage()
		return (CinematicDB and CinematicDB.language) or "auto"
	end
	local function ChooseLanguage(value)
		if not CinematicDB or value == CurrentLanguage() then
			return
		end
		CinematicDB.language = value ~= "auto" and value or nil
		StaticPopup_Show("CINEMATIC_LANGUAGE_RELOAD")
	end
	local language
	local ok, dropdown = ns.MenuDropdown(panel)
	if ok and dropdown and dropdown.SetupMenu then
		language = dropdown
		language:SetWidth(180)
		language:SetupMenu(function(_, root)
			for _, choice in ipairs(LANGUAGES) do
				root:CreateRadio(choice.text, function() return CurrentLanguage() == choice.value end,
					function() ChooseLanguage(choice.value) end)
			end
		end)
		language.Refresh = function(self) self:GenerateMenu() end
	else
		-- (No modern dropdown on this client: a button that steps through them.)
		language = ns.PanelButton(panel)
		language:SetSize(180, 22)
		language:SetScript("OnClick", function()
			for i, choice in ipairs(LANGUAGES) do
				if choice.value == CurrentLanguage() then
					ChooseLanguage(LANGUAGES[i % #LANGUAGES + 1].value)
					break
				end
			end
			language:Refresh()
		end)
		language.Refresh = function(self)
			for _, choice in ipairs(LANGUAGES) do
				if choice.value == CurrentLanguage() then self:SetText(choice.text) end
			end
		end
	end
	language.searchSkip = true -- (it shows the current choice, not a label)
	language:SetPoint("TOPLEFT", languageLabel, "BOTTOMLEFT", -4, -6)
	Tooltip(language, L["The language Cinematic's text is in; a change needs a reload."])
	controls[#controls + 1] = language

	-- The settings pages' and windows' look, for the account like the
	-- language (ns.MenuSkin, Skin.lua).
	do
		local skinLabel = Label(panel, "GameFontHighlight", L["Menu look"])
		skinLabel:SetPoint("TOPLEFT", language, "BOTTOMLEFT", 4, -14)
		local SKINS = { { value = "auto" }, { value = "HD", text = L["HD (flat)"] },
			{ value = "SD", text = L["SD (the game's look)"] } }
		local function CurrentSkin()
			return (CinematicDB and CinematicDB.menuSkin) or "auto"
		end
		-- (Auto says which it comes to here.)
		local function SkinText(choice)
			return choice.text or (L["Auto (%s)"]):format(ns.AutoMenuSkin())
		end
		local function ChooseSkin(value)
			if CinematicDB then CinematicDB.menuSkin = value ~= "auto" and value or nil end
			ns.ApplyMenuSkin()
		end
		local skinMenu
		local made, skinDropdown = ns.MenuDropdown(panel)
		if made and skinDropdown and skinDropdown.SetupMenu then
			skinMenu = skinDropdown
			skinMenu:SetWidth(180)
			skinMenu:SetupMenu(function(_, root)
				for _, choice in ipairs(SKINS) do
					root:CreateRadio(SkinText(choice), function() return CurrentSkin() == choice.value end,
						function() ChooseSkin(choice.value) end)
				end
			end)
			skinMenu.Refresh = function(self) self:GenerateMenu() end
		else
			-- (No modern dropdown on this client: a button that steps through them.)
			skinMenu = ns.PanelButton(panel)
			skinMenu:SetSize(180, 22)
			skinMenu.Refresh = function(self)
				for _, choice in ipairs(SKINS) do
					if choice.value == CurrentSkin() then self:SetText(SkinText(choice)) end
				end
			end
			skinMenu:SetScript("OnClick", function(self)
				for i, choice in ipairs(SKINS) do
					if choice.value == CurrentSkin() then
						ChooseSkin(SKINS[i % #SKINS + 1].value)
						break
					end
				end
				self:Refresh()
			end)
		end
		skinMenu.searchSkip = true -- (it shows the current choice, not a label)
		skinMenu:SetPoint("TOPLEFT", skinLabel, "BOTTOMLEFT", -4, -6)
		Tooltip(skinMenu, L["The look of Cinematic's settings windows: HD is flat and dark, and SD looks like the game's own."])
		controls[#controls + 1] = skinMenu
	end

	-- Right column: CineMode, coming in and going out together.
	local cineHeader = Label(panel, "GameFontNormal", L["CineMode"])
	cineHeader:SetPoint("TOPLEFT", general, "TOPLEFT", 320, 0)

	local fadeUI = Check(panel, "fadeUI", L["Start in CineMode"],
		L["CineMode comes in by itself between fights, fading the UI."])
	fadeUI:SetPoint("TOPLEFT", cineHeader, "BOTTOMLEFT", -2, -6)

	-- (What takes you out of it, Exit CineMode: on the CineMode page.)

	local defaults = ns.PanelButton(panel)
	defaults:SetSize(140, 22)
	defaults:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -12)
	defaults:SetText(L["Reset addon"])
	defaults.searchSkip = true
	Tooltip(defaults, L["Reset Settings keeps what you made, Reset EVERYTHING deletes it all, and both reload the UI."])
	defaults:SetScript("OnClick", function()
		ns.ShowResetPopup()
	end)
	-- The active profile, under the button (picked on the Profiles page).
	local profileLabel = Label(panel, "GameFontHighlightSmall")
	profileLabel:SetPoint("RIGHT", defaults, "LEFT", -10, 0)
	profileLabel:SetJustifyH("RIGHT")
	controls[#controls + 1] = { debugName = "active profile label", owner = panel, Refresh = function()
		if not ns.ProfileChosen() then
			profileLabel:SetText(L["Profile: |cffff8000none yet|r (pick one on the Profiles page)"])
			return
		end
		profileLabel:SetText(L["Profile: %s"]:format("|cffffd100" .. ns.ProfileLabel(ns.ActiveProfile()) .. "|r") ..
			(ns.IsCharacterProfile() and L[" (this character)"] or ""))
	end }

	mainCanvas:SetScript("OnShow", PageShown(Refresh, panel))
	mainCanvas:Hide() -- so OnShow fires on the first visit too
	searchPages[1] = { canvas = mainCanvas }
	ns.WatchSettingsCanvas(mainCanvas)
	-- (Back on the main page: the key opens there next. Cinematic_ToggleSettings)
	CreateFrame("Frame", nil, mainCanvas):SetScript("OnShow", function() ns.lastOptionsPage = nil end)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(mainCanvas, "Cinematic")
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(mainCanvas)
	end
end

-- Each sub-page by name, for ns.OpenOptions: its category, or its frame on
-- clients with the old options window.
local subpages = {}

-- The left list, top down, by English name: hubs and plain pages. Entries are
-- queued as they're made and handed to the game in this order when setup ends
-- (menu.Flush), so the order of the Create calls doesn't matter. One not named
-- here goes last; a hub under another (hub.under) right under that one.
local menu = { order = { "Profiles", "CineMode", "UI Manager", "Addons", "Visions", "Style", "Atmosphere", "Camera",
	"Keybinds", "Quality of life", "Help", "Community", "Dev" }, queue = {} }
do
	local function Register(entry)
		if category and Settings and Settings.RegisterCanvasLayoutSubcategory then
			local parentSub = entry.parent and subpages[entry.parent] or category
			local sub = Settings.RegisterCanvasLayoutSubcategory(parentSub, entry.frame, entry.shown)
			Settings.RegisterAddOnCategory(sub)
			subpages[entry.key] = sub
		elseif InterfaceOptions_AddCategory then
			InterfaceOptions_AddCategory(entry.frame)
		end
	end
	-- key: its subpages name; parent: the hub it's under, or nil (Cinematic).
	-- After setup (menu.flushed), straight in at the bottom.
	function menu.Add(key, frame, shown, parent)
		subpages[key] = frame
		menu.parentOf[key] = parent -- (AutoFold: the lines it's under)
		local entry = { key = key, frame = frame, shown = shown, parent = parent }
		if menu.flushed then Register(entry) else menu.queue[#menu.queue + 1] = entry end
	end
	function menu.Flush()
		local done = {}
		local function Put(entry)
			if done[entry] then return end
			done[entry] = true
			Register(entry)
			for _, child in ipairs(menu.queue) do
				if child.parent == entry.key then Put(child) end
			end
		end
		for _, key in ipairs(menu.order) do
			for _, entry in ipairs(menu.queue) do
				if entry.key == key and not entry.parent then Put(entry) end
			end
		end
		for _, entry in ipairs(menu.queue) do
			if not entry.parent then Put(entry) end
		end
		menu.flushed, menu.queue = true, {}
	end
	-- Interface, Visions and Quality of Life open in the left list as one of
	-- their pages shows, and fold again as you go elsewhere (2026-11-16); so
	-- do their group lines (Heads-up...) and Wheels under them: a line open
	-- while the page shown is it or one under it. The game's list: a
	-- category's SetExpanded, the list made again. (Its names unchecked on
	-- each client: /cine log says what it found, once.)
	menu.parentOf, menu.fold = {}, { ["UI Manager"] = true, Visions = true, ["Quality of life"] = true, Wheels = true }
	local logged
	local function Fold(current)
		local list = SettingsPanel and SettingsPanel.GetCategoryList and SettingsPanel:GetCategoryList()
		-- (The page shown's line and every line it's under, by key.)
		local open = {}
		for key, category in pairs(subpages) do
			if category == current then
				while key do
					open[key] = true
					key = menu.parentOf[key]
				end
				break
			end
		end
		local changed = false
		for key in pairs(menu.fold) do
			local category = subpages[key]
			if type(category) == "table" and category.SetExpanded then
				local inside = open[key] or false
				local now = category.IsExpanded and category:IsExpanded() or category.expanded or false
				if (now and true or false) ~= inside then
					category:SetExpanded(inside)
					changed = true
				end
			end
		end
		if changed and list and list.CreateCategories then list:CreateCategories() end
		if not logged and ns.Log then
			logged = true
			local probe = subpages["UI Manager"]
			ns.Log("ui", ("left list fold: SetExpanded %s, IsExpanded %s, list %s, CreateCategories %s, " ..
				"SetCurrentCategory %s, found %s"):format(tostring(type(probe) == "table" and probe.SetExpanded ~= nil),
				tostring(type(probe) == "table" and probe.IsExpanded ~= nil), tostring(list ~= nil),
				tostring(list ~= nil and list.CreateCategories ~= nil),
				tostring(list ~= nil and list.SetCurrentCategory ~= nil), tostring(next(open) ~= nil)))
		end
	end
	-- An icon picked in its hub (2026-11-16): its line in the left list lit
	-- (the list's own highlight; the page the settings show stays the hub's),
	-- the lines it's under opened. menu.lineOf: AddBandShortcuts' lines; an
	-- icon with none (a hub's first), the hub's own line.
	menu.lineOf = {}
	function menu.MarkLine(hubName, english, tabOf)
		-- (A tab (Name Style): its icon's line, Nameplate Names'. 2026-11-16.)
		local key = menu.lineOf[hubName .. "|" .. english] or (tabOf and menu.lineOf[hubName .. "|" .. tabOf])
			or hubName
		local category = subpages[key]
		if type(category) ~= "table" then return end
		-- (Its groups opened only, 2026-11-16: the list's SetCurrentCategory lit
		-- the line but left the settings showing the page they had, so a line's
		-- borrowed hub frame was never handed back: two hubs drawn at once.)
		local ok, err = pcall(Fold, category)
		if not ok and ns.Log then ns.Log("error", "left list line: " .. tostring(err)) end
		-- The line itself picked too (2026-11-16): the settings' own
		-- SelectCategory, so the old line hides (handing the hub frame back)
		-- and this one shows (taking it, its icon already the current one).
		-- Without it the old line stayed lit, or none did when its group
		-- just folded away. menu.lineNow: each hub's, for ns.OpenOptions.
		menu.lineNow[hubName] = category
		local panel = SettingsPanel
		if menu.selecting or not (panel and panel.SelectCategory and panel:IsShown()) then return end
		if InCombatLockdown() and panel:IsProtected() then return end
		if panel.GetCurrentCategory and panel:GetCurrentCategory() == category then return end
		menu.selecting = true
		ok, err = pcall(panel.SelectCategory, panel, category)
		menu.selecting = nil
		if not ok and ns.Log then ns.Log("error", "left list pick: " .. tostring(err)) end
	end
	menu.lineNow = {}
	-- Cinematic's lines in the left list fold with gold arrows, not the game's
	-- +/- (2026-11-16): each line's own toggle kept, just see-through (still
	-- what's clicked), our arrow over it, right while folded, down while
	-- open. Only on our lines: the list's buttons are shared with every
	-- addon's, so a reused one gets its +/- back. Looked over a few times a
	-- second while the settings are open (their list made again often).
	-- (The list's parts unchecked on each client: /cine log says what it
	-- found, once.)
	local ARROW = ns.HELP_DISC:gsub("HelpDisc$", "ListArrow")
	local arrowLogged
	-- (A line's category: on it, or in its element data however deep the list
	-- keeps it. ours: the categories to find.)
	local function CategoryOf(button, ours)
		local tried = { button.category, button.GetCategory and button:GetCategory() or nil }
		local data = button.GetElementData and button:GetElementData()
		local function Add(each)
			if type(each) ~= "table" then return end
			tried[#tried + 1] = each
			tried[#tried + 1] = each.category
			tried[#tried + 1] = each.data
			if type(each.data) == "table" then tried[#tried + 1] = each.data.category end
			if each.GetData then
				local ok, inner = pcall(each.GetData, each)
				if ok and type(inner) == "table" then
					tried[#tried + 1] = inner
					tried[#tried + 1] = inner.category
				end
			end
		end
		Add(data)
		for _, each in pairs(tried) do
			if type(each) == "table" and ours[each] then return each end
		end
		return nil, data
	end
	local function ToggleOf(button)
		if button.Toggle then return button.Toggle end
		-- (Else the small button on the line: the +/-.)
		for _, child in ipairs({ button:GetChildren() }) do
			if child.IsObjectType and child:IsObjectType("Button") and (child:GetWidth() or 99) <= 24 then return child end
		end
	end
	function menu.PaintArrows()
		local list = SettingsPanel and SettingsPanel.GetCategoryList and SettingsPanel:GetCategoryList()
		local box = list and list.ScrollBox
		if not (box and box.ForEachFrame) then
			if not arrowLogged and ns.Log and SettingsPanel and SettingsPanel:IsVisible() then
				arrowLogged = true
				local keys = {}
				for k in pairs(list or {}) do if type(k) == "string" and #keys < 30 then keys[#keys + 1] = k end end
				ns.Log("ui", ("left list arrows: no ScrollBox.ForEachFrame (list %s; its keys: %s)")
					:format(tostring(list ~= nil), table.concat(keys, ",")))
			end
			return
		end
		local ours = {}
		for _, category in pairs(subpages) do
			if type(category) == "table" then ours[category] = true end
		end
		local seen, mine, toggles = 0, 0, 0
		-- (While one of ours is open, the folded ones' arrows at half, 2026-11-16.)
		local anyOpen = false
		for category in pairs(ours) do
			if category.IsExpanded and category:IsExpanded() or category.expanded then
				-- (Only one with lines under it counts: a page's own line can say open.)
				for key, each in pairs(subpages) do
					if each == category and menu.fold[key] then anyOpen = true end
				end
			end
		end
		box:ForEachFrame(function(button)
			seen = seen + 1
			local category = CategoryOf(button, ours)
			local toggle = ToggleOf(button)
			local isOurs = category ~= nil
			if toggle then toggles = toggles + 1 end
			if isOurs and toggle and toggle:IsShown() then
				mine = mine + 1
				if not button.cineArrow then
					button.cineArrow = button:CreateTexture(nil, "OVERLAY")
					button.cineArrow:SetSize(16, 16)
					button.cineArrow:SetTexture(ARROW)
				end
				button.cineArrow:ClearAllPoints()
				button.cineArrow:SetPoint("CENTER", toggle, "CENTER", 0, 0)
				local open = category.IsExpanded and category:IsExpanded() or category.expanded
				button.cineArrow:SetRotation(open and -math.pi / 2 or 0)
				button.cineArrow:SetAlpha((anyOpen and not open) and 0.5 or 1)
				button.cineArrow:Show()
				toggle:SetAlpha(0)
				button.cineToggle = toggle
				-- (Painted again the moment it's clicked: the list made again
				-- under it, the game's +/- would show till the next look.)
				if not toggle.cineHooked then
					toggle.cineHooked = true
					toggle:HookScript("OnClick", function() menu.PaintSoon() end)
				end
			else
				if button.cineArrow then button.cineArrow:Hide() end
				if button.cineToggle then
					button.cineToggle:SetAlpha(1)
					button.cineToggle = nil
				end
			end
		end)
		-- (Logged once it's found ours, or what a line holds if it can't.)
		if (not arrowLogged or (mine > 0 and not menu.arrowFound)) and ns.Log and seen > 0 then
			arrowLogged = true
			menu.arrowFound = mine > 0
			-- (And the parts of the first line with children of its own, to see
			-- where its +/- is if none was found: each child and region.)
			local parts = {}
			box:ForEachFrame(function(button)
				if #parts > 0 then return end
				local category, data = CategoryOf(button, ours)
				-- (Its element data's keys, a level down: where the category is.)
				if type(data) == "table" then
					local keys = {}
					for k, v in pairs(data) do
						keys[#keys + 1] = tostring(k) .. ":" .. type(v)
						if type(v) == "table" then
							for k2, v2 in pairs(v) do
								if #keys < 40 then keys[#keys + 1] = tostring(k) .. "." .. tostring(k2) .. ":" .. type(v2) end
							end
						end
					end
					parts[#parts + 1] = "data {" .. table.concat(keys, ",") .. "}"
				else
					parts[#parts + 1] = "data " .. type(data)
				end
				for k, v in pairs(button) do
					if type(k) == "string" and type(v) == "table" and v.GetObjectType then
						local ok, kind = pcall(v.GetObjectType, v)
						local w = v.GetWidth and v:GetWidth() or 0
						local tex = v.GetTexture and v:GetTexture()
						local atlas = v.GetAtlas and v:GetAtlas()
						parts[#parts + 1] = ("%s=%s %dpx %s"):format(k, ok and kind or "?", w, tostring(atlas or tex))
					end
				end
				parts[#parts + 1] = "category " .. tostring(category and (category.GetName and category:GetName() or category.name))
			end)
			ns.Log("ui", ("left list arrows: %d lines, %d with a toggle, %d of ours with one; a line's parts: %s")
				:format(seen, toggles, mine, table.concat(parts, "; ")))
		end
	end
	-- Painted now and again as the list settles (it lays out its lines as the
	-- frame ends), so the game's +/- never shows on ours.
	function menu.PaintSoon()
		pcall(menu.PaintArrows)
		C_Timer.After(0, function() pcall(menu.PaintArrows) end)
	end
	function menu.AutoFold()
		-- (The list made again: painted at once, not at the next look.)
		local list = SettingsPanel and SettingsPanel.GetCategoryList and SettingsPanel:GetCategoryList()
		if list and list.CreateCategories and not menu.listHooked then
			menu.listHooked = true
			hooksecurefunc(list, "CreateCategories", function() menu.PaintSoon() end)
		end
		-- (The arrows: painted while the settings show.)
		if SettingsPanel and not menu.arrowWatch then
			local watch = CreateFrame("Frame", nil, SettingsPanel)
			local wait = 0
			ns.SetOnUpdate(watch, function(_, elapsed)
				wait = wait - elapsed
				if wait > 0 then return end
				wait = 0.15
				local ok, err = pcall(menu.PaintArrows)
				if not ok and not menu.arrowError then
					menu.arrowError = true
					if ns.Log then ns.Log("error", "left list arrows: " .. tostring(err)) end
				end
			end)
			menu.arrowWatch = watch
		end
		local EventRegistry = _G.EventRegistry
		if not (EventRegistry and EventRegistry.RegisterCallback) then return end
		EventRegistry:RegisterCallback("Settings.CategoryChanged", function(_, category)
			local ok, err = pcall(Fold, category)
			if not ok and ns.Log then ns.Log("error", "left list fold: " .. tostring(err)) end
		end, menu)
	end
end

-- Hubs: a sub-page holding several pages, picked from a row of icons at its
-- top (the page shows under them, its name on the icon's mouseover). Above
-- the icons, a search box for all its pages and Reset page for the one shown.
-- HubAdd(canvas, name, searchPage) takes a page into its hub (false: in none);
-- HubTab(name) shows a page in its hub and gives the hub's name (false: in none).
do
	-- Each hub (by English name) and its pages in order, with their icons
	-- (or a function that gives one).
	local HUBS = {
		-- (One home per kind of game frame, 2026-11-16: a band per kind of frame
		-- holding all its pages: when it shows (its section of the HUD page, an
		-- icon each: CreateCombatPanel's HUD_ICONS, placed by their before),
		-- its rules, then its looks. What Shows: what's for all of them. label:
		-- the hub's name as shown, its pages' ids staying "UI Manager"'s and the
		-- Style pages' theirs.)
		-- (plain: its icons in one row, no bands or their names: about one icon
		-- a kind of frame now, its pages its tabs, 2026-11-16.)
		-- (groups: its icons in three groups in the row, each on its colored band, the
		-- General (HUD) icon first on its own,
		-- 2026-11-16: Heads-up (you and the fight), Overhead (over units), Info
		-- (the screen's edges: any icon not listed). Each a line in the left list.)
		{ name = "UI Manager", label = "Interface", plain = true, note = { "Addon frames moved to the Addons hub >",
			"Advanced Frames" }, groups = { order = { "Heads-up", "Overhead", "Info" }, other = "Info",
				["HUD:hud"] = false, ["HUD:units"] = "Heads-up", ["HUD:party"] = "Heads-up", ["HUD:bars"] = "Heads-up",
				["HUD:buffs"] = "Heads-up", ["HUD:combat"] = "Heads-up",
				Nameplates = "Overhead", ["Nameplate Names"] = "Overhead", ["Combat Text Style"] = "Overhead" },
			colors = {
			["Heads-up"] = { 0.35, 0.6, 0.9 }, Overhead = { 0.85, 0.55, 0.25 }, Info = { 0.45, 0.75, 0.45 },
			["What Shows"] = { 0.75, 0.65, 0.45 }, Mouseover = { 0.35, 0.6, 0.9 }, ["Unit Frames"] = { 0.35, 0.6, 0.9 },
			["Party & Raid"] = { 0.35, 0.6, 0.9 }, ["Action Bars"] = { 0.35, 0.6, 0.9 }, Chat = { 0.35, 0.6, 0.9 },
			Tooltips = { 0.35, 0.6, 0.9 }, ["Map & Quests"] = { 0.35, 0.6, 0.9 },
			["Buffs & Debuffs"] = { 0.35, 0.6, 0.9 }, Timers = { 0.35, 0.6, 0.9 }, ["Menus & Info"] = { 0.35, 0.6, 0.9 },
			["Combat Text"] = { 0.35, 0.6, 0.9 },
		}, pages = {
			-- (A standard: your faction's battle banner.)
			{ "Standard Frames", function()
				return UnitFactionGroup("player") == "Horde" and "Interface\\Icons\\INV_BannerPVP_01"
					or "Interface\\Icons\\INV_BannerPVP_02"
			end, label = "HUD", section = "What Shows" },
			{ "Gamepad", "Interface\\Icons\\INV_Gizmo_01", label = "Gamepad Frames", section = "What Shows",
				tabOf = "HUD:bars" }, -- (the Action Bars icon's Gamepad tab, 2026-11-16)
			-- (Mouse: what the pointer brings up, the pointer itself and what it shows, 2026-11-16.)
			-- (The frames, the HUD's top down; combat text last, over heads.)
			-- (Keep up and Frame Links: tabs of the Unit Frames icon, the HUD's
			-- Show in first, 2026-11-16: PersonalResources.lua.)
			{ "Personal Resources", "Interface\\Icons\\Ability_Racial_BloodRage", -- (Bloodrage: health into power)
				label = "Unit Frames", section = "Unit Frames", tabOf = "HUD:units" },
			{ "Unit Style", "Interface\\Icons\\INV_Misc_Head_Human_01", label = "Unit Frame Style", section = "Unit Frames",
				tabOf = "HUD:units" }, -- (the Unit Frames icon's Style tab)
			{ "Personal Style", "Interface\\Icons\\Spell_Holy_SealOfVengeance", label = "Personal Resource Style",
				section = "Unit Frames", tabOf = "HUD:units" }, -- (the Unit Frames icon's Resource Style tab)
			-- (The unit frames' cast bars, PlateCastStyle.lua: the Unit Frames icon's Cast Style tab, 2026-11-16.)
			{ "Unit Cast Style", "Interface\\Icons\\Spell_Nature_Lightning", label = "Cast Style", section = "Unit Frames",
				tabOf = "HUD:units" },
			{ "Raid Style", "Interface\\Icons\\INV_Misc_GroupNeedMore", label = "Raid Frame Style", section = "Party & Raid",
				tabOf = "HUD:party" }, -- (the Party & Raid icon's Raid Style tab)
			-- (Nameplates and Names, 2026-11-16: two icons, both the Nameplates page's
			-- tiles (CreatePlatesPanel), the rest their tabs. Their own hub till then.)
			{ "Nameplates", "Interface\\Icons\\Ability_Hunter_SniperShot", label = "Nameplates", section = "Nameplates" },
			{ "Plate Icons", "Interface\\Icons\\INV_Misc_GroupNeedMore", label = "Icons", section = "Nameplates",
				tabOf = "Nameplates" }, -- (PlateIcons.lua)
			{ "Nameplate Style", "Interface\\Icons\\Ability_Marksmanship", label = "Nameplate Style", section = "Nameplates",
				tabOf = "Nameplates" },
			{ "Cast Bar Style", "Interface\\Icons\\Spell_Nature_Lightning", label = "Cast Bar Style", section = "Nameplates",
				tabOf = "Nameplates" },
			{ "Name Style", "Interface\\Icons\\INV_Misc_Note_02", label = "Name Style", section = "Nameplates",
				tabOf = "Nameplate Names" },
			{ "Action Style", "Interface\\Icons\\Ability_DualWield", label = "Action Bar Style", section = "Action Bars",
				tabOf = "HUD:bars" }, -- (the Action Bars icon's Bar Style tab)
			{ "Chat", "Interface\\Icons\\INV_Scroll_03", section = "Chat" },
			-- (The Chat icon's Bubbles and Bubble Style tabs, 2026-11-16.)
			{ "Chat bubbles", "Interface\\Icons\\Ability_Warrior_BattleShout", label = "Chat Bubbles", section = "Chat",
				tabOf = "HUD:chat" },
			{ "Bubble Style", "Interface\\Icons\\Ability_Warrior_RallyingCry", label = "Chat Bubble Style", section = "Chat",
				tabOf = "HUD:chat" },
			-- (Reveal and Frame Links: tabs of their icons, the HUD's Show in first, 2026-11-16.)
			{ "Minimap", "Interface\\Icons\\INV_Misc_Map_01", section = "Map & Quests", tabOf = "HUD:minimap" },
			-- (One Mouse icon, after the Minimap's, 2026-11-16: Hover Groups, its tabs Tooltips, Tooltip Style and Cursor.)
			-- (Its picture the game's own mouse pointer.)
			{ "Mouseover groups", "Interface\\Cursor\\Point", label = "Mouseover", section = "Mouseover" },
			{ "Tooltips", "Interface\\Icons\\INV_Misc_Book_09", section = "Mouseover", tabOf = "Mouseover groups" },
			{ "Tooltip Style", "Interface\\Icons\\INV_Misc_Note_05", label = "Tooltip Style", section = "Mouseover",
				tabOf = "Mouseover groups" },
			{ "Cursor Hide", "Interface\\Icons\\INV_Misc_Eye_01", section = "Mouseover", tabOf = "Mouseover groups" }, -- (CursorHide.lua)
			{ "Quest tracker", "Interface\\Icons\\INV_Misc_Note_01", label = "Quest Tracker", section = "Map & Quests",
				tabOf = "HUD:quests" },
			-- (Buffs & Debuffs: one icon, its Show in the HUD's, Reveal and links this page's, 2026-11-16.)
			{ "Buffs/debuffs", "Interface\\Icons\\Spell_Holy_WordFortitude", label = "Buffs/Debuffs", section = "Buffs & Debuffs",
				tabOf = "HUD:buffs" },
			-- (The Timers icon's tabs, after its Show in, 2026-11-16.)
			{ "Cooldown Manager", "Interface\\Icons\\INV_Misc_PocketWatch_01", section = "Timers", tabOf = "HUD:combat" },
			{ "Swing timer", "Interface\\Icons\\INV_Sword_04", label = "Swing Timer", section = "Timers",
				tabOf = "HUD:combat" },
			{ "Breath Bar", "Interface\\Icons\\Spell_Shadow_DemonBreath", section = "Timers", tabOf = "HUD:combat" },
			{ "Combat Text Style", "Interface\\Icons\\Ability_Warrior_Riposte", label = "Combat Text Style",
				section = "Combat Text" },
		} },
		-- (Cameras: what everyone has; Dev: the dev copy's own, to the right)
		-- (master: Enable Cameras; its pages with no switch of their own show Off with it)
		{ name = "Camera", master = "cameraModes", colors = { Cameras = { 0.35, 0.6, 0.9 }, ["Special Cams"] = { 0.55, 0.45, 0.9 },
			Dev = { 0.85, 0.3, 0.25 } },
			pages = {
			{ "Cameras", "Interface\\Icons\\INV_Misc_Spyglass_03", label = "General", section = "Cameras" },
			{ "Scenes", "Interface\\Icons\\Spell_Holy_MindVision", section = "Cameras" }, -- (built with Cameras: CreateCamerasPanel)
			-- (TriggersPage.lua: the list; its other pages tabs on it, or opened from a row)
			{ "Triggers", "Interface\\Icons\\INV_Misc_PocketWatch_02", section = "Cameras" },
			{ "Trigger Priority", "Interface\\Icons\\INV_Misc_PocketWatch_02", tabOf = "Triggers" },
			{ "Trigger Log", "Interface\\Icons\\INV_Misc_PocketWatch_02", tabOf = "Triggers" },
			{ "Trigger Settings", "Interface\\Icons\\INV_Misc_PocketWatch_02", tabOf = "Triggers" },
			{ "Camera Scripts", "Interface\\Icons\\INV_Scroll_05", label = "Scripts", section = "Cameras" }, -- (CameraScriptsPage.lua)
			{ "My Shots", "Interface\\Icons\\INV_Misc_Spyglass_02", section = "Cameras" }, -- (ShotsPage.lua)
			-- (Surge Forward's own icon, from the game: SkyrideCam.lua, retail.)
			{ "Skyriding Cam", function()
				local get = C_Spell and C_Spell.GetSpellTexture
				local ok, icon = pcall(get or error, 372608)
				return ok and icon or "Interface\\Icons\\INV_Misc_Spyglass_02"
			end, section = "Special Cams" },
			-- (Special Cams, 2026-11-15: the two that change how the camera follows you as you play.)
			{ "Shoulder Cam", "Interface\\Icons\\INV_Shoulder_02", section = "Special Cams" }, -- (ShoulderCam.lua)
			{ "Camera Settings", "Interface\\Icons\\Trade_Engineering", dev = true, section = "Dev" }, -- (settings no script step uses)
		} },
		-- (label: the name on its icon, when the page is registered under another)
		-- (the look and the sound: the visual effects' pages, then Audio)
		{ name = "Atmosphere", colors = { Visuals = { 0.65, 0.45, 0.9 }, Audio = { 0.3, 0.7, 0.5 } }, pages = {
			{ "Effects", "Interface\\Icons\\Spell_Holy_Restoration", label = "General" }, -- (in no section: a band of its own)
			{ "Tint", "Interface\\Icons\\INV_Misc_Gem_Variety_02", section = "Visuals" },
			-- (tabOf: no icon of its own, a folder tab on that page's (ns.PageTabs))
			{ "Tint Style", "Interface\\Icons\\INV_Misc_Gem_Variety_02", tabOf = "Tint" },
			{ "Letterbox", "Interface\\Icons\\Spell_Shadow_ShadesOfDarkness", section = "Visuals" },
			{ "Letterbox Style", "Interface\\Icons\\Spell_Shadow_ShadesOfDarkness", tabOf = "Letterbox" },
			{ "Graphics+", "Interface\\Icons\\INV_Misc_Gem_Pearl_04", label = "Graphics Boost", section = "Visuals" },
			{ "Audio", "Interface\\Icons\\INV_Misc_Drum_01", section = "Audio" },
		} },
		-- (The look of the whole interface: Enable Style and the theme, and the
		-- recolor. Each frame's own look is on its page in the Interface hub,
		-- nameplates' in theirs, a Vision's on its own: 2026-11-16.)
		{ name = "Style", pages = {
			{ "Style General", "Interface\\Icons\\INV_Misc_Gear_08", label = "General" },
			{ "Style Pages", "Interface\\Icons\\INV_Misc_Gear_08", tabOf = "Style General" }, -- (GeneralStyle.lua)
			{ "Style Overrides", "Interface\\Icons\\INV_Misc_Gear_08", tabOf = "Style General" }, -- (StyleOverrides.lua)
			{ "Interface Recolor", "Interface\\Icons\\INV_Misc_Gem_01", tabOf = "Style General" }, -- (InterfaceRecolor.lua: General's last tab)
		} },
		-- (Everything about nameplates, listed after Interface: which show
		-- (General: the Nameplates page, its id kept), the icons on them, then
		-- their looks (Look: still Style > General's Enable Style and theme;
		-- ids kept). name: not "Nameplates", the General page's id.)
		-- (General and the dev copy's Wind Guide in no section: plain icons)
		{ name = "Visions", colors = { Combat = { 0.85, 0.3, 0.25 }, World = { 0.35, 0.6, 0.9 } }, pages = {
			-- (General: every Vision as a card, 2026-11-16. VisionsStyle.lua: the
			-- look they share. Each in no section, a band of its own.)
			{ "Visions General", "Interface\\Icons\\INV_Misc_Book_11", label = "General" },
			{ "Visions Style", "Interface\\Icons\\INV_Misc_Gear_08" },
			{ "Heal Vision", "Interface\\Icons\\Spell_Holy_FlashHeal", section = "Combat" },
			-- (tabOf: no icon of its own, a folder tab on that page's (ns.PageTabs))
			{ "Damage Vision", "Interface\\Icons\\Ability_Warrior_Rampage", section = "Combat" }, -- (DamageVision.lua)
			{ "Damage Vision Look", "Interface\\Icons\\Ability_Warrior_Rampage", tabOf = "Damage Vision" },
			{ "Vitals Vision", "Interface\\Icons\\Spell_Shadow_LifeDrain02", section = "Combat" },
			{ "Vitals Style", "Interface\\Icons\\Spell_Shadow_LifeDrain02", tabOf = "Vitals Vision" },
			{ "Quest Vision", "Interface\\Icons\\INV_Misc_Head_Dragon_01", section = "World" },
			{ "Quest Talk Style", "Interface\\Icons\\INV_Scroll_02", tabOf = "Quest Vision" },
			{ "Quest Item Style", "Interface\\Icons\\INV_Misc_Key_03", tabOf = "Quest Vision" },
			{ "Roll Vision", "Interface\\Icons\\INV_Misc_Dice_01", section = "World" },
			{ "Roll Style", "Interface\\Icons\\INV_Misc_Dice_02", tabOf = "Roll Vision" },
			{ "Teleport Vision", "Interface\\Icons\\Spell_Arcane_TeleportStormWind",
				section = "World" }, -- (TeleportVision.lua; its tooltip: ns.TILE_TOOLTIPS)
			{ "Duel Vision", "Interface\\Icons\\Ability_DualWield", section = "World" },
			{ "Emote Vision", "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", section = "World" }, -- (EmoteVision.lua)
			{ "Emote Vision Settings", "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", tabOf = "Emote Vision" },
			{ "Emote Vision Style", "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", tabOf = "Emote Vision" },
			-- (CardsPage.lua's: Battle Vision's and Story Vision's moments, one page)
			{ "Card Vision", "Interface\\Icons\\INV_Misc_Book_09", section = "World" },
			{ "Card Styles", "Interface\\Icons\\INV_Misc_Book_09", label = "Card Types", tabOf = "Card Vision" },
			-- (an event's own pages: not tabs on the page's, opened from its row)
			{ "Card Settings", "Interface\\Icons\\INV_Misc_Book_09", tabOf = "Card Vision" },
			{ "Card Style", "Interface\\Icons\\INV_Misc_Book_09", tabOf = "Card Vision" },
			{ "Card Sounds", "Interface\\Icons\\INV_Misc_Book_09", tabOf = "Card Vision" },
			{ "Wind Guide", "Interface\\Icons\\Spell_Nature_Cyclone", dev = true },
		} },
		{ name = "Quality of life", label = "Quality of Life", colors = { Helpers = { 0.3, 0.7, 0.5 } }, pages = {
			{ "General", "Interface\\Icons\\INV_Misc_Bag_07" },
			{ "Fishing", "Interface\\Icons\\Trade_Fishing", section = "Helpers" },
			{ "Hunter", "Interface\\Icons\\INV_Weapon_Bow_07", section = "Helpers" },
			{ "Keyboard Map", "Interface\\Icons\\INV_Misc_Note_06", section = "Helpers" }, -- (KeyboardMap.lua)
		} },
		-- (Everything about other addons, listed after Interface. General:
		-- CreateQualityPanel's end, only with one of its addons loaded;
		-- Conflicts: Conflicts.lua, only with an addon that has rows loaded;
		-- Frames: the Advanced Frames page, always, its ids kept.)
		{ name = "Addons", pages = {
			-- (Custom Support: Addon Frames' second tab since 2026-11-16.)
			{ "Advanced Frames", "Interface\\Icons\\INV_Misc_Gear_01", label = "Frames" },
			{ "Addon Support", "Interface\\Icons\\INV_Misc_Gear_02", tabOf = "Advanced Frames" },
			{ "Addon Conflicts", "Interface\\Icons\\Ability_Warrior_Disarm", label = "Conflicts" },
		} },
		-- (WheelsPage.lua's pages; listed under Quality of life. The master wheel first, plain; the wheels it opens on a band.)
		{ name = "Wheels", under = "Quality of life", colors = { Wheels = { 0.65, 0.45, 0.9 } }, pages = {
			{ "Master wheel", "Interface\\Icons\\Spell_Nature_WispSplode", label = "Master Wheel" },
			{ "Your wheels", "Interface\\Icons\\INV_Misc_Note_01", label = "Your Wheels" },
			{ "Camera wheel", "Interface\\Icons\\INV_Misc_Spyglass_03", label = "Camera Wheel", section = "Wheels" },
			{ "Menu wheel", "Interface\\Icons\\INV_Misc_Gear_01", label = "Menu Wheel", section = "Wheels" },
			{ "Marker wheel", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", label = "Marker Wheel", section = "Wheels" },
			{ "Ground marker wheel", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", label = "Ground Marker Wheel",
				section = "Wheels" },
			{ "Vision wheel", "Interface\\Icons\\Ability_EyeOfTheOwl", label = "Vision Wheel", section = "Wheels" },
		} },
		-- Help, above Community: where to read up and report a problem, and the
		-- tools for when something looks wrong. (The hub has its first page's
		-- name: OpenOptions("Help") opens the hub, at that page.)
		{ name = "Help", pages = {
			{ "Help", "Interface\\Icons\\INV_Misc_QuestionMark" }, -- (WhatsNew.lua)
			{ "Why showing", "Interface\\Icons\\Ability_Hunter_EagleEye", label = "Why Is It Showing?" }, -- (Why.lua)
			{ "Profiler", "Interface\\Icons\\INV_Misc_PocketWatch_02" }, -- (ProfilerPage.lua)
			{ "Game settings", "Interface\\Icons\\INV_Gizmo_02", label = "Game Settings" }, -- (GameSettingsPage.lua)
		} },
		-- (WhatsNew.lua's pages, after Help. Dev: the dev copy's own tools)
		{ name = "Community", colors = { Updates = { 0.35, 0.6, 0.9 }, People = { 0.3, 0.7, 0.5 },
			Dev = { 0.85, 0.3, 0.25 } }, pages = {
			{ "New features", "Interface\\Icons\\INV_Misc_Gift_01", label = "New Features", section = "Updates" },
			{ "All changes", "Interface\\Icons\\INV_Misc_Book_11", label = "All Changes", section = "Updates" },
			{ "Socials", "Interface\\Icons\\INV_Letter_15", section = "People" },
			{ "Thanks", "Interface\\Icons\\INV_ValentinesCard02", section = "People" },
			{ "Module Editor", "Interface\\Icons\\INV_Misc_Wrench_01", section = "Dev", dev = true }, -- (ModuleEditor.lua)
		} },
		-- (The dev copy's own hub: none of its pages are in the release, so neither is it.)
		{ name = "Dev", pages = {
			{ "Held Game Settings", "Interface\\Icons\\INV_Gizmo_02", dev = true }, -- (HeldSettingsPage.lua)
			{ "Demo Commands", "Interface\\Icons\\INV_Misc_Film_01", dev = true }, -- (DemoHub.lua)
			{ "Minimap Copy", "Interface\\Icons\\INV_Misc_Map_01", dev = true }, -- (MinimapCopy.lua)
		} },
	}
	-- Pages sharing one icon, a folder tab each, where this client has more
	-- than one of them: the first it has gets the icon, named label; the rest
	-- are its tabs (tabOf). Each page: { English name, tab name, tab tip }.
	-- (None now, 2026-11-16: the HUD page's sections are icons in their bands,
	-- HUD_ICONS, and a frame's own pages tabs of its icon, ns.ShowInTabs. Kept
	-- for a group to come: { label, master, switches, pages = { { page, tab, tip } } }.)
	local PAGE_GROUPS = {}
	-- (Whether this client makes the page: as the calls at the end of this file decide.)
	local GROUP_HAS = {}
	local groupsDone
	-- (Once, as the first page comes into its hub: each group's pages this
	-- client has, and their icon and tabs set on HUBS' entries.)
	local function PageGroups()
		if groupsDone then return end
		groupsDone = true
		for _, group in ipairs(PAGE_GROUPS) do
			local have = {}
			for _, each in ipairs(group.pages) do
				if GROUP_HAS[each[1]]() then have[#have + 1] = each end
			end
			group.have = have
			-- (One page here: no icon of the group's, so no switch over that page.)
			if group.master then ns.SetPageMaster(group.switches, #have > 1 and group.master or nil) end
			if #have > 1 then
				for _, hub in ipairs(HUBS) do
					for _, page in ipairs(hub.pages) do
						for i, each in ipairs(have) do
							if page[1] == each[1] then
								if i == 1 then page.label = group.label else page.tabOf = have[1][1] end
							end
						end
					end
				end
			end
		end
	end
	-- A grouped page's folder tabs, its title moved under them (none when
	-- this client has just the one page of its group).
	function ns.GroupTabs(content, title, english)
		PageGroups()
		for _, group in ipairs(PAGE_GROUPS) do
			if #group.have > 1 then
				local list, picked = {}, nil
				for i, each in ipairs(group.have) do
					list[i] = { L[each[2]], each[1], L[each[3]] }
					if each[1] == english then picked = i end
				end
				if picked then
					local panel = ns.PageTabs(content, list, picked)
					title:ClearAllPoints()
					title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
					return panel
				end
			end
		end
	end
	-- Pages still being worked on: "(WIP)" after the name on their icon's mouseover.
	-- (dev = true on a page above: it's only in the dev copy (CinematicDev.toc), and
	-- its icon has a red X over it and "(dev only)" on mouseover. Every dev-only
	-- page gets it.)
	local WIP_PAGES = { ["Wind Guide"] = true }
	local TILE, TILE_GAP, EDGE = 36, 6, 12
	local BAR = 30 -- (the search box and Reset page, above the icons)
	local byName = {} -- tile by the name its page was registered under (English or shown)
	-- (the icon lit for a tile: its own, or for a page's other tab the page's)
	local function Lit(tile)
		return tile and tile.tabOf and byName[tile.tabOf] or tile
	end

	local LABEL_H, BAND_PAD, SECTION_GAP = 14, 4, 10 -- (a section's name above its band; bands apart)
	local BELOW = 10 -- (room under the icons, above the line to the page)
	local GOLD = { 1, 0.82, 0 }

	local PLAIN = { 0.6, 0.55, 0.45 } -- (a band of pages in no section)

	-- A section's band: a fill and an edge in its color (gold while one of its
	-- pages is shown, faded otherwise), its name above in the same color.
	local function PaintBands(hub)
		if not hub.bands then return end
		for _, band in pairs(hub.bands) do
			local lit = hub.current and band.tiles[Lit(hub.current)]
			local c = lit and GOLD or hub.colors and hub.colors[band.section] or PLAIN
			band:SetColorTexture(c[1], c[2], c[3], lit and 0.14 or 0.08)
			for _, line in ipairs(band.edges) do line:SetColorTexture(c[1], c[2], c[3], lit and 0.45 or 0.25) end
			if lit then band.label:SetTextColor(c[1], c[2], c[3])
			else band.label:SetTextColor(c[1] * 0.6 + 0.15, c[2] * 0.6 + 0.15, c[3] * 0.6 + 0.15) end
		end
	end

	-- (key: the section, or the place of a run of pages in none, its band unnamed)
	local function Band(hub, key, section)
		hub.bands = hub.bands or {}
		local band = hub.bands[key]
		if band then return band end
		band = hub.frame:CreateTexture(nil, "BACKGROUND")
		band.section = section
		band.edges = {}
		for i, sides in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
			{ "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
			local line = hub.frame:CreateTexture(nil, "BORDER")
			line:SetPoint(sides[1], band)
			line:SetPoint(sides[2], band)
			if i <= 2 then line:SetHeight(1) else line:SetWidth(1) end
			band.edges[i] = line
		end
		band.label = hub.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		band.label:SetPoint("BOTTOMLEFT", band, "TOPLEFT", 2, 2)
		band.label:SetText(section and L[section] or "")
		band.label.searchSkip = true
		hub.bands[key] = band
		return band
	end

	local MIN_TILE = 28 -- (icons shrink this far to keep the bands on one row)

	-- A hub with sections: each section's pages on its band, the bands in one
	-- row, the icons a little smaller if that keeps them there (a band that
	-- still won't fit starts another).
	local function SectionLayout(hub, width)
		local runs = {}
		for _, tile in ipairs(hub.tiles) do
			local run = runs[#runs]
			if not run or run.section ~= tile.section then
				run = { section = tile.section }
				runs[#runs + 1] = run
			end
			run[#run + 1] = tile
		end
		-- (all but the icons themselves: gaps, band padding, the page's edges)
		local fixed = EDGE * 2 + (#runs - 1) * SECTION_GAP
		for _, run in ipairs(runs) do fixed = fixed + (#run - 1) * TILE_GAP + BAND_PAD * 2 end
		local size = math.max(MIN_TILE, math.min(TILE, math.floor((width - fixed) / math.max(1, #hub.tiles))))
		local high = size + BAND_PAD * 2
		local x, y = EDGE, -BAR - EDGE
		local used = {}
		-- (pages in no section: a band of their own too, with no name)
		for index, run in ipairs(runs) do
			local wide = #run * (size + TILE_GAP) - TILE_GAP + BAND_PAD * 2
			local band = Band(hub, run.section or index, run.section)
			-- (A name wider than its few icons: the next band starts past the
			-- name, so the two names never run together.)
			local room = math.max(wide, band.label:GetStringWidth() + 4)
			if x > EDGE and x + room > width - EDGE then
				x, y = EDGE, y - LABEL_H - high - TILE_GAP
			end
			band:ClearAllPoints()
			band:SetPoint("TOPLEFT", hub.frame, "TOPLEFT", x, y - LABEL_H)
			band:SetSize(wide, high)
			band.tiles, used[band] = {}, true
			for i, tile in ipairs(run) do
				band.tiles[tile] = true
				tile:ClearAllPoints()
				tile:SetSize(size, size)
				tile:SetPoint("TOPLEFT", band, "TOPLEFT", BAND_PAD + (i - 1) * (size + TILE_GAP), -BAND_PAD)
				tile:Show()
			end
			x = x + room + SECTION_GAP
		end
		-- (a band left over from an earlier layout, pages since added: put away)
		for _, band in pairs(hub.bands or {}) do
			local shown = used[band] or false
			band:SetShown(shown)
			band.label:SetShown(shown)
			for _, line in ipairs(band.edges) do line:SetShown(shown) end
		end
		PaintBands(hub)
		hub.host:ClearAllPoints()
		hub.host:SetPoint("TOPLEFT", hub.frame, "TOPLEFT", 0, y - LABEL_H - high - BELOW)
		hub.host:SetPoint("BOTTOMRIGHT")
	end

	-- Icons in rows across the page's width, the picked page filling the rest.
	local function Layout(hub)
		local width = hub.frame:GetWidth()
		if not width or width <= 0 then return end
		for _, tile in ipairs(hub.tiles) do
			if tile.section then return SectionLayout(hub, width) end
		end
		-- (One icon only, Addons without Conflicts: no row at all, 2026-11-16;
		-- the page right under the search bar.)
		if #hub.tiles <= 1 then
			for _, tile in ipairs(hub.tiles) do tile:Hide() end
			hub.host:ClearAllPoints()
			hub.host:SetPoint("TOPLEFT", hub.frame, "TOPLEFT", 0, -BAR - BELOW)
			hub.host:SetPoint("BOTTOMRIGHT")
			return
		end
		local left = EDGE
		local perRow = math.max(1, math.floor((width - left - EDGE + TILE_GAP) / (TILE + TILE_GAP)))
		local column, row = 0, 0
		-- (hub.groups: a gap between groups, a thin line in it; x past the gaps so far.)
		local GROUP_GAP = 16
		local x, lastGroup, lines = 0, nil, 0
		hub.groupLines = hub.groupLines or {}
		local function Place(tile)
			if column >= perRow or (column > 0 and left + x + TILE > width - EDGE) then
				column, row, x = 0, row + 1, 0
			end
			local y = -BAR - EDGE - row * (TILE + TILE_GAP)
			if tile.group and lastGroup and tile.group ~= lastGroup and column > 0 then
				lines = lines + 1
				local line = hub.groupLines[lines]
				if not line then
					line = hub.frame:CreateTexture(nil, "ARTWORK")
					line:SetColorTexture(0.6, 0.5, 0.3, 0.5)
					line:SetWidth(1)
					hub.groupLines[lines] = line
				end
				line:ClearAllPoints()
				line:SetPoint("TOPLEFT", hub.frame, "TOPLEFT", left + x + (GROUP_GAP - TILE_GAP) / 2, y - 4)
				line:SetHeight(TILE - 8)
				line:Show()
				x = x + GROUP_GAP
			end
			lastGroup = tile.group
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", hub.frame, "TOPLEFT", left + x, y)
			tile:Show()
			column = column + 1
			x = x + TILE + TILE_GAP
		end
		for _, tile in ipairs(hub.tiles) do Place(tile) end
		for i = lines + 1, #hub.groupLines do hub.groupLines[i]:Hide() end
		local rows = #hub.tiles > 0 and row + 1 or 0
		hub.host:ClearAllPoints()
		hub.host:SetPoint("TOPLEFT", hub.frame, "TOPLEFT", 0,
			-BAR - EDGE - rows * (TILE + TILE_GAP) + TILE_GAP - BELOW)
		hub.host:SetPoint("BOTTOMRIGHT")
	end

	local function Light(tile, lit)
		if lit then tile.border:SetColorTexture(1, 0.82, 0, 1)
		else tile.border:SetColorTexture(0.45, 0.38, 0.2, 1) end
		tile.icon:SetDesaturated(not lit)
	end

	local function Select(tile)
		local hub = tile.hub
		if hub.current == tile then return end
		local run = ns.StartPageRun(tile.english)
		local previous = hub.current
		if previous then
			if previous.canvas ~= tile.canvas then previous.canvas:Hide() end
			Light(Lit(previous), false)
		end
		hub.current = tile
		Light(Lit(tile), true)
		PaintBands(hub)
		if tile.onSelect then tile.onSelect() end
		local shown = run and debugprofilestop()
		if run then run.select = shown - run.started end
		tile.canvas:Show()
		local painted = run and debugprofilestop()
		if run then run.show = painted - shown end
		-- (Reset page: for a page with settings of its own)
		hub.reset:SetShown(pageKeys[tile.resetContent or tile.canvas.content] ~= nil)
		if ns.PaintPageSwitches then ns.PaintPageSwitches() end -- (its off card)
		if run then run.switches = debugprofilestop() - painted end
		ns.EndPageRun(run)
		-- (Its line in the left list lit, its groups open: menu.MarkLine.)
		if menu.MarkLine then menu.MarkLine(hub.name, tile.english, tile.tabOf) end
	end

	-- (made when its first page comes, so it's listed where that page would be)
	local function CreateHub(hub)
		-- (hub.under: listed under that hub, made first, not under Cinematic.
		-- Its place in the list: menu.order.)
		local parentHub
		for _, each in ipairs(HUBS) do
			if each.name == hub.under then parentHub = each end
		end
		if parentHub and not parentHub.frame then CreateHub(parentHub) end
		local frame = CreateFrame("Frame")
		frame.name = L[hub.label or hub.name]
		frame.parent = parentHub and L[parentHub.label or parentHub.name] or "Cinematic"
		hub.frame, hub.tiles = frame, {}
		hub.host = CreateFrame("Frame", nil, frame)
		hub.host:SetPoint("TOPLEFT", 0, -EDGE)
		hub.host:SetPoint("BOTTOMRIGHT")
		-- A line between the icons and the page, for its content to scroll under.
		local divider = frame:CreateTexture(nil, "ARTWORK")
		divider:SetHeight(1)
		divider:SetPoint("BOTTOMLEFT", hub.host, "TOPLEFT", EDGE, 0)
		divider:SetPoint("BOTTOMRIGHT", hub.host, "TOPRIGHT", -EDGE, 0)
		divider:SetColorTexture(0.45, 0.38, 0.2, 0.8)
		-- Reset page (the page shown), and left of it a search box for all its pages.
		local reset = ns.PanelButton(frame)
		reset:SetSize(100, 22)
		reset:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
		reset:SetText(L["Reset page"])
		Tooltip(reset, L["Puts this page's settings back to your profile's values."])
		reset:SetScript("OnClick", function()
			if hub.current then
				StaticPopup_Show("CINEMATIC_RESET_PAGE", nil, nil,
					hub.current.resetContent or hub.current.canvas.content)
			end
		end)
		hub.reset = reset
		-- (hub.note: { a line, the page it opens }: in the bar at the top left,
		-- where a page used to be. Colored on hover, not refonted: Cyrillic.)
		if hub.note then
			local note = CreateFrame("Button", nil, frame)
			note.text = note:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			note.text:SetPoint("LEFT")
			note.text:SetText(L[hub.note[1]])
			note:SetSize(note.text:GetStringWidth() + 4, 18)
			note:SetPoint("LEFT", frame, "TOPLEFT", EDGE + 4, -19)
			note:SetScript("OnClick", function() ns.OpenOptions(hub.note[2]) end)
			note:SetScript("OnEnter", function() note.text:SetTextColor(1, 0.82, 0) end)
			note:SetScript("OnLeave", function() note.text:SetTextColor(0.5, 0.5, 0.5) end)
		end
		hub.searchPages = {}
		local box = CreateSearch(frame, frame, hub.searchPages)
		box:SetPoint("RIGHT", reset, "LEFT", -12, 0)
		frame:SetScript("OnSizeChanged", function() Layout(hub) end)
		frame:SetScript("OnShow", function()
			Layout(hub)
			if not hub.current and hub.tiles[1] then Select(hub.tiles[1]) end
			ns.PaintPageSwitches()
		end)
		frame:Hide()
		-- (the hub it's under starts collapsed in the list: Wheels hidden till it's opened)
		menu.Add(hub.name, frame, L[hub.label or hub.name], parentHub and parentHub.name)
	end

	-- A tile's page switch (its hidden Enable Page: RegisterPageSwitch), or nil.
	-- A page with none in a hub with a master (hub.master: Enable Cameras)
	-- follows that: Off on its icon with it, nothing to flip.
	-- A group's icon (Timers) flips the group's master instead (asIcon: the
	-- icon itself, its dot, tooltip and right-click); on its tabs' pages the
	-- master stands in while it's off, so the off card turns it back on.
	local groupSwitches = {}
	local function GroupSwitch(tile)
		local english = tile.tabOf or tile.english
		for _, group in ipairs(PAGE_GROUPS) do
			if group.master and group.have and #group.have > 1 and group.have[1][1] == english then
				local switch = groupSwitches[group.master]
				if not switch then
					local check = CreateFrame("CheckButton", nil, tile.hub.frame)
					check:Hide()
					check:SetScript("OnClick", function(self)
						KeyPut(group.master, self:GetChecked() and true or false)
						Refresh()
					end)
					switch = { key = group.master, check = check, name = group.label }
					groupSwitches[group.master] = switch
				end
				return switch
			end
		end
	end
	local function TileSwitch(tile, asIcon)
		if tile.noSwitch or (asIcon and tile.noDot) then return nil end
		local group = GroupSwitch(tile)
		if group and (asIcon or ns.GetDB()[group.key] == false) then return group end
		local switch = pageSwitches[tile.resetContent or tile.canvas.content or false]
		if switch and switch.check then return switch end
		if tile.hub.master then
			tile.follows = tile.follows or { key = tile.hub.master, follows = true }
			return tile.follows
		end
	end
	-- Whether a page's switch is on, and true second if it's off with the one
	-- it's under (a vision's with Enable Visions): then it can't be flipped.
	local function SwitchState(switch)
		if switch.follows then
			local on = ns.GetDB()[switch.key] ~= false
			return on, not on
		end
		local master = ns.PageSwitchOf(switch.key)
		if master and ns.GetDB()[master] == false then return false, true end
		return KeyGet(switch.key) and true or false
	end
	-- Flips a page's switch as a click on its box would.
	local function FlipSwitch(switch)
		local on, held = SwitchState(switch)
		if held or switch.follows then return end
		switch.check:SetChecked(not on)
		switch.check:GetScript("OnClick")(switch.check, "LeftButton")
		if PlaySound and SOUNDKIT then
			PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
	end
	-- Its line on a tooltip: on or off, and what a right-click does.
	local function SwitchLine(switch)
		local on, held = SwitchState(switch)
		if held then
			GameTooltip:AddLine(L["Off with the General page's switch."], 1, 0.25, 0.25, true)
		elseif switch.follows then
			return
		elseif on then
			GameTooltip:AddLine(L["On. Right-click to turn this page off."], 0.25, 1, 0.25, true)
		else
			GameTooltip:AddLine(L["Off. Right-click to turn this page on."], 1, 0.25, 0.25, true)
		end
	end
	-- A page's on/off dot in its icon's corner (green on, red off; none for a
	-- page without a switch), and the icon darkened while it's off.
	local function PaintSwitch(tile)
		local switch = TileSwitch(tile, true)
		if not switch and not tile.switchDot then return end
		if not tile.switchDot then
			tile.offMark = tile:CreateTexture(nil, "OVERLAY")
			tile.offMark:SetAllPoints(tile.icon)
			tile.offMark:SetColorTexture(0, 0, 0, 0.55)
			tile.switchDot = tile:CreateTexture(nil, "OVERLAY", nil, 7)
			tile.switchDot:SetSize(12, 12)
			tile.switchDot:SetPoint("BOTTOMRIGHT", tile.icon, "BOTTOMRIGHT", 1, -1)
		end
		local off = switch and not SwitchState(switch) or false
		tile.offMark:SetShown(off)
		tile.switchDot:SetShown(switch ~= nil)
		tile.switchDot:SetTexture(off and "Interface\\COMMON\\Indicator-Red" or "Interface\\COMMON\\Indicator-Green")
	end
	-- The switch with a box behind one (a page following its hub's master:
	-- the master's own, Enable Cameras on the Scenes page), or nil.
	local function BoxSwitch(switch)
		if switch.check then return switch end
		for _, each in pairs(pageSwitches) do
			if each.key == switch.key and each.check then return each end
		end
	end
	-- A card over a page that's off, its settings out of sight: its icon, "<page>
	-- is off" and a Turn on button (none while it's off with the General
	-- page's switch, just why).
	local function CreateOffCard(hub)
		local card = CreateFrame("Frame", nil, hub.host)
		card:SetAllPoints(hub.host)
		card:SetFrameLevel(hub.host:GetFrameLevel() + 500)
		card:EnableMouse(true) -- (the faded settings under it not clickable or scrolled)
		card:EnableMouseWheel(true)
		card:SetScript("OnMouseWheel", function() end)
		local box = CreateFrame("Frame", nil, card)
		-- (one slim row: icon, what's off, the button on the right; a dim red tint)
		box:SetPoint("TOPLEFT", 16, -16)
		box:SetPoint("TOPRIGHT", -16, -16)
		local edge = box:CreateTexture(nil, "BACKGROUND")
		edge:SetAllPoints()
		edge:SetColorTexture(0.55, 0.16, 0.12, 0.7)
		local bg = box:CreateTexture(nil, "BORDER")
		bg:SetPoint("TOPLEFT", 1, -1)
		bg:SetPoint("BOTTOMRIGHT", -1, 1)
		bg:SetColorTexture(0.16, 0.04, 0.03, 0.85)
		card.icon = box:CreateTexture(nil, "ARTWORK")
		card.icon:SetSize(32, 32)
		card.icon:SetPoint("LEFT", 12, 0)
		card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		card.icon:SetDesaturated(true)
		card.button = ns.PanelButton(box)
		card.button:SetSize(150, 24)
		card.button:SetPoint("RIGHT", -12, 0)
		card.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -1)
		card.title:SetPoint("RIGHT", card.button, "LEFT", -12, 0)
		card.title:SetJustifyH("LEFT")
		card.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
		card.text:SetPoint("RIGHT", card.button, "LEFT", -12, 0)
		card.text:SetJustifyH("LEFT")
		card.button:SetScript("OnClick", function(self)
			if self.switch then FlipSwitch(self.switch) end
			ns.PaintPageSwitches()
		end)
		card.box = box
		hub.offCard = card
		return card
	end
	local function PaintOffCard(hub)
		local card, tile = hub.offCard, hub.current
		-- (the page it faded last time back, whichever shows now, its tabs too)
		local function KeepTabs(tabs, keep)
			if not (tabs and tabs.panel.SetIgnoreParentAlpha) then return end
			tabs.panel:SetIgnoreParentAlpha(keep)
			for _, tab in ipairs(tabs.frames) do tab:SetIgnoreParentAlpha(keep) end
		end
		if card and card.faded then
			card.faded:SetAlpha(1)
			KeepTabs(card.faded.content and card.faded.content.pageTabs, false)
			card.faded = nil
		end
		local switch = tile and TileSwitch(tile)
		if not switch or SwitchState(switch) then
			if card then card:Hide() end
			return
		end
		card = card or CreateOffCard(hub)
		local box = BoxSwitch(switch)
		local stuck = not box or select(2, SwitchState(box))
		local name = L[tile.switchLabel or switch.name or tile.label or tile.english]
		card.icon:SetTexture(tile.icon:GetTexture())
		card.title:SetText("|cffff5a40" .. L["%s is off"]:format(name) .. "|r")
		card.text:SetText(stuck and L["Off with the General page's switch."]
			or L["Turn it on to see and change its settings."])
		card.button:SetText(L["Turn on %s"]:format(name))
		-- (as wide as its words: Turn on Combat Text Style ran past its edges)
		local words = card.button:GetFontString()
		local textW = words and words:GetStringWidth()
		card.button:SetWidth(math.max(150, (type(textW) == "number" and textW or 0) + 24))
		card.button.switch = box
		card.button:SetShown(not stuck)
		card.box:SetHeight(math.max(32, card.title:GetStringHeight() + 3 + card.text:GetStringHeight()) + 20)
		-- A page split into tabs (HUD, Gamepad, Cursor) keeps them over the
		-- card, still clickable, so the other tabs' pages are a click away.
		local tabs = tile.canvas.content and tile.canvas.content.pageTabs
		card:ClearAllPoints()
		card:SetPoint("BOTTOMRIGHT", hub.host)
		if tabs and tabs.panel.SetIgnoreParentAlpha then
			if tile.canvas.scroll then tile.canvas.scroll:SetVerticalScroll(0) end
			card:SetPoint("TOPLEFT", hub.host, "TOPLEFT", 0, -(ns.FOLDER_TAB_HEIGHT + 22))
			KeepTabs(tabs, true)
		else
			card:SetPoint("TOPLEFT", hub.host)
		end
		tile.canvas:SetAlpha(0)
		card.faded = tile.canvas
		card:Show()
	end
	function ns.PaintPageSwitches()
		if not ns.GetDB() then return end
		for _, hub in ipairs(HUBS) do
			for _, tile in ipairs(hub.tiles or {}) do PaintSwitch(tile) end
			if hub.host then PaintOffCard(hub) end
		end
	end

	local function CreateTile(hub, canvas, english, iconFile, label)
		local tile = CreateFrame("Button", nil, hub.frame)
		tile.hub, tile.canvas = hub, canvas
		tile.english, tile.label = english, label -- (its name on the off card)
		tile:SetSize(TILE, TILE)
		tile.border = tile:CreateTexture(nil, "BACKGROUND")
		tile.border:SetAllPoints()
		tile.border:SetColorTexture(0.45, 0.38, 0.2, 1)
		local bg = tile:CreateTexture(nil, "BORDER")
		bg:SetPoint("TOPLEFT", 1, -1)
		bg:SetPoint("BOTTOMRIGHT", -1, 1)
		bg:SetColorTexture(0.06, 0.05, 0.04, 0.95)
		local icon = tile:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", -2, 2)
		-- (iconFile can be a function: picked again each time it shows)
		local function Paint()
			icon:SetTexture(type(iconFile) == "function" and iconFile() or iconFile)
		end
		Paint()
		tile:SetScript("OnShow", Paint)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		icon:SetDesaturated(true) -- (in colour once picked)
		tile.icon = icon
		local hl = tile:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(icon)
		hl:SetColorTexture(1, 1, 1, 0.15)
		-- Its page's name on mouseover.
		tile:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			local own = ns.TILE_TOOLTIPS and ns.TILE_TOOLTIPS[english] -- (a page's own: Tele Vision's)
			local shown = L[own or label or english]
			GameTooltip:SetText(WIP_PAGES[english] and shown .. " " .. L["(WIP)"] or shown, 1, 0.82, 0)
			if self.dev then
				GameTooltip:AddLine("(dev only)", 1, 0.25, 0.25)
			end
			local switch = TileSwitch(self, true)
			if switch then SwitchLine(switch) end
			GameTooltip:Show()
		end)
		tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
		-- (Right-click: its page's switch flipped, the page left as it is.)
		tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		tile:SetScript("OnClick", function(self, button)
			if button ~= "RightButton" then return Select(self) end
			local switch = TileSwitch(self, true)
			if not switch then return end
			FlipSwitch(switch)
			if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
		end)
		return tile
	end

	function HubAdd(canvas, name, searchPage)
		PageGroups()
		for _, hub in ipairs(HUBS) do
			for order, page in ipairs(hub.pages) do
				local english = page[1]
				if name == english or name == L[english] then
					-- (Where it is, for a Look box's title: Interface > Style > HUD > Unit Frames.)
					local under
					for _, each in ipairs(HUBS) do
						if each.name == hub.under then under = each.label or each.name end
					end
					local path = {}
					for _, step in ipairs({ under or false, hub.label or hub.name, page.section or false, page.label or english }) do
						if step then path[#path + 1] = L[step] end
					end
					canvas.hubPath = path
					if not hub.frame then CreateHub(hub) end
					canvas:SetParent(hub.host)
					canvas:ClearAllPoints()
					canvas:SetAllPoints(hub.host)
					canvas:Hide()
					-- An icon for the page, or one for each of its tabs (canvas.hubTabs:
					-- { name, icon, onSelect, resetContent, setSelect, section }, sharing the page).
					local icon = type(page[2]) == "function" and page[2]() or page[2]
					local tabs = canvas.hubTabs or { { name = english, icon = icon, label = page.label } }
					for i, tab in ipairs(tabs) do
						local tile = CreateTile(hub, canvas, tab.name, tab.icon, tab.label)
						tile.order = order + i / 100
						-- (tab.before: listed right before that page of the hub, in its band:
						-- the HUD page's sections, each with its frame's pages.)
						for at, each in ipairs(tab.before and hub.pages or {}) do
							if each[1] == tab.before then tile.order = at - 0.5 + i / 1000 end
						end
						-- (hub.plain: one row, no bands; the band kept for the left list's lines and the tour)
						tile.band = tab.section or page.section
						tile.section = not hub.plain and tile.band or nil
						tile.onSelect, tile.resetContent = tab.onSelect, tab.resetContent
						-- (noDot: no switch on its icon, its page's under another's;
						-- switchLabel: the name its off card gives that switch.)
						tile.noDot, tile.switchLabel = tab.noDot, tab.switchLabel
						tile.noSwitch = tab.noSwitch -- (none at all, not its page's: no off card)
						tile.showIn = tab.showIn -- (its Show in list's key: ns.HubOverview's tabs)
						if page.dev and tile.CreateLine then
							-- (A red X over the icon: dev copy only.)
							tile.dev = true
							for _, corners in ipairs({ { "TOPLEFT", "BOTTOMRIGHT" }, { "TOPRIGHT", "BOTTOMLEFT" } }) do
								local line = tile:CreateLine(nil, "OVERLAY")
								line:SetThickness(3)
								line:SetColorTexture(1, 0.15, 0.15, 0.9)
								line:SetStartPoint(corners[1], tile.icon, 0, 0)
								line:SetEndPoint(corners[2], tile.icon, 0, 0)
							end
						end
						if tab.setSelect then
							tab.setSelect(function() Select(tile) end)
						end
						if tab.tabOf or page.tabOf then -- (tab.tabOf: one of a page's icons only)
							tile.tabOf = tab.tabOf or page.tabOf
							tile:Hide()
						else
							hub.tiles[#hub.tiles + 1] = tile
						end
						if i == 1 then
							byName[name], byName[english] = tile, tile
						end
						-- (tab.own: opened by its own name too, ns.OpenOptions("HUD:raid").)
						if tab.own then byName[tab.name] = tile end
					end
					-- (hub.groups: each icon in its group, the groups in their order.)
					local groups = hub.groups
					if groups then
						for _, each in ipairs(hub.tiles) do
							-- (false: in no group, first, a band of its own: the General icon)
						each.group = groups[each.english]
						if each.group == nil then each.group = groups.other end
						each.group = each.group or nil
							each.band = each.group
						each.section = each.group -- (its colored band, as other hubs' sections: SectionLayout)
							for rank, name in ipairs(groups.order) do
								if name == each.group then each.groupRank = rank end
							end
						end
					end
					table.sort(hub.tiles, function(a, b)
						if (a.groupRank or 0) ~= (b.groupRank or 0) then return (a.groupRank or 0) < (b.groupRank or 0) end
						return a.order < b.order
					end)
					-- (its search: the hub's box; its Reset page: the hub's)
					searchPage.order = order
					hub.searchPages[#hub.searchPages + 1] = searchPage
					table.sort(hub.searchPages, function(a, b) return a.order < b.order end)
					if canvas.resetButton then
						canvas.resetButton:HookScript("OnShow", canvas.resetButton.Hide)
						canvas.resetButton:Hide()
					end
					return true
				end
			end
		end
		return false
	end

	-- Whether a hub has a page by that name (the dev build's Demo Hub tours).
	function ns.IsHubPage(name)
		return byName[name] ~= nil
	end

	-- Lines in the left list under a hub (2026-11-16): one for each of its
	-- bands (Heads-up..., Combat...), each icon's line under its band's, and
	-- an icon in no band past the first (the hub's own line opens that) on
	-- a line of its own. Each folded to start with, opening as you go in
	-- (menu.AutoFold). Each a page that, as it shows, takes the hub's own
	-- frame in (the settings put it back on the hub's line as that's picked)
	-- at its icon (a band's: its first), so its own line stays lit. Before
	-- menu.Flush, every page in.
	function ns.AddBandShortcuts(hubName)
		for _, hub in ipairs(HUBS) do
			if hub.name == hubName and hub.frame then
				local function Line(key, label, parentKey, target)
					local frame = CreateFrame("Frame")
					frame.name, frame.parent = label, L[hub.label or hub.name]
					-- (Put back as it was as this one hides, before the next shows:
					-- where the settings had it, for the hub's own line.)
					local kept
					frame:SetScript("OnShow", function(self)
						local hubFrame = hub.frame
						-- (Held by another line still: that one hands it back first.)
						if hub.heldBy and hub.heldBy ~= self then
							local onHide = hub.heldBy:GetScript("OnHide")
							if onHide then onHide(hub.heldBy) end
						end
						hub.heldBy = self
						kept = { parent = hubFrame:GetParent(), points = {} }
						for i = 1, hubFrame:GetNumPoints() do kept.points[i] = { hubFrame:GetPoint(i) } end
						hubFrame:SetParent(self)
						hubFrame:ClearAllPoints()
						hubFrame:SetAllPoints(self)
						hubFrame:Show()
						-- (This line picked already: its icon's line not picked over
						-- it, a band's line staying lit.)
						local was = menu.selecting
						menu.selecting = true
						HubTab(target)
						menu.selecting = was
					end)
					frame:SetScript("OnHide", function(self)
						local hubFrame = hub.frame
						if hub.heldBy == self then hub.heldBy = nil end
						if not kept or hubFrame:GetParent() ~= self then return end
						hubFrame:SetParent(kept.parent)
						hubFrame:ClearAllPoints()
						for _, point in ipairs(kept.points) do hubFrame:SetPoint(unpack(point)) end
						if not kept.parent then hubFrame:Hide() end -- (never shown on its own line yet)
						kept = nil
					end)
					frame:Hide() -- (made shown, its OnShow would never come as the list shows it)
					menu.Add(key, frame, label, parentKey)
				end
				local bands = {}
				for i, tile in ipairs(hub.tiles) do
					local band = tile.band or tile.section
					local label = L[tile.label or tile.english]
					if band then
						local bandKey = hub.name .. "/" .. band
						if not bands[band] then
							bands[band] = true
							Line(bandKey, L[band], hub.name, tile.english)
							menu.fold[bandKey] = true
						end
						Line(bandKey .. "/" .. tile.english, label, bandKey, tile.english)
					menu.lineOf[hub.name .. "|" .. tile.english] = bandKey .. "/" .. tile.english
					elseif i > 1 then
						Line(hub.name .. "/" .. tile.english, label, hub.name, tile.english)
					menu.lineOf[hub.name .. "|" .. tile.english] = hub.name .. "/" .. tile.english
					end
				end
			end
		end
	end

	-- A hub page's own tabs (tabOf it in HUBS), as { label, page } each, in
	-- order (the Visions hub's General page's chips).
	function ns.HubTabsOf(hubName, page)
		local list = {}
		for _, hub in ipairs(HUBS) do
			if hub.name == hubName then
				for _, each in ipairs(hub.pages) do
					if each.tabOf == page and not each.dev then
						list[#list + 1] = { L[each.label or each[1]], each[1] }
					end
				end
			end
		end
		return list
	end

	-- A hub's icons in their order, left to right: each one's name (as
	-- ns.OpenOptions takes it), its label as shown and its band (the Demo
	-- Hub's screenshot tour).
	function ns.HubIcons(hubName)
		local list = {}
		for _, hub in ipairs(HUBS) do
			if hub.name == hubName then
				for _, tile in ipairs(hub.tiles or {}) do
					-- (on: its page's switch, on or off (held off: off); nil without
					-- one. A HUD section's is the HUD page's, its icon having no dot.)
					local switch, on = TileSwitch(tile, true) or TileSwitch(tile), nil
					if switch then
						local isOn, held = SwitchState(switch)
						on = isOn and not held
					end
					list[#list + 1] = { name = tile.english, label = L[tile.label or tile.english],
						band = tile.band and L[tile.band] or "", texture = tile.icon and tile.icon:GetTexture(), on = on }
				end
			end
		end
		return list
	end

	function HubTab(name)
		local tile = byName[name]
		if not tile then return false end
		-- (already on that page, at another of its tabs: left there, unless
		-- that tab is the one asked for by its own name)
		local current = tile.hub.current
		if not (current and current.canvas == tile.canvas and tile.english ~= name) then
			Select(tile)
		end
		return tile.hub.name
	end

	-- A hub page shown, from inside the settings (its folder tab: ns.PageTabs).
	function ns.ShowHubPage(name)
		return HubTab(name)
	end

	-- A hub page's switch by its English name, flipped (its folder tab's
	-- right-click), or its line added to owner's tooltip.
	function ns.FlipPageSwitch(name)
		local switch = byName[name] and TileSwitch(byName[name], true)
		if switch then FlipSwitch(switch) end
	end
	function ns.PageSwitchTip(owner, name)
		local switch = byName[name] and TileSwitch(byName[name])
		if not (switch and GameTooltip:IsOwned(owner)) then return end
		SwitchLine(switch)
		GameTooltip:Show()
	end

	-- A page's name as its icon shows it, by its English name.
	function ns.PageLabel(name)
		for _, hub in ipairs(HUBS) do
			for _, page in ipairs(hub.pages) do
				if page[1] == name then return L[page.label or name] end
			end
		end
		return L[name]
	end

	-- Whether a page (its English name; nil: the main page) goes by every
	-- one of parts (lower case): each found in its name, its label, the page
	-- it's a tab of, its hub's or the hub that's under, in English or the
	-- language shown. (/cine find Style|Names|fade time.)
	function ns.PageOnPath(name, parts)
		local known = {}
		local function add(text)
			if type(text) == "string" then
				known[#known + 1] = text:lower()
				known[#known + 1] = L[text]:lower()
			end
		end
		local function addHub(hub)
			add(hub.name)
			add(hub.label)
		end
		add(name or "Cinematic")
		for _, hub in ipairs(HUBS) do
			for _, page in ipairs(hub.pages) do
				if page[1] == name then
					add(page.label)
					add(page.tabOf)
					addHub(hub)
					for _, each in ipairs(HUBS) do
						if each.name == hub.under then addHub(each) end
					end
				end
			end
		end
		for _, part in ipairs(parts) do
			local found = false
			for _, text in ipairs(known) do
				if text:find(part, 1, true) then found = true break end
			end
			if not found then return false end
		end
		return true
	end

	-- Whether words (lower case) name a page (its English name; nil: the main
	-- page) in menu order, top down: the left list's page, the icon group, the
	-- page it's a tab of, the page itself (in English or the language shown).
	-- A name of many words takes them all (/cine find ui visibility minimap).
	function ns.PageOnPathInOrder(name, words)
		local levels = {}
		local function level(...)
			local known = {}
			for i = 1, select("#", ...) do
				local text = select(i, ...)
				if type(text) == "string" then
					known[#known + 1] = text:lower()
					known[#known + 1] = L[text]:lower()
				end
			end
			if #known > 0 then levels[#levels + 1] = known end
		end
		local found
		for _, hub in ipairs(HUBS) do
			for _, page in ipairs(hub.pages) do
				if not found and page[1] == name then
					found = true
					for _, each in ipairs(HUBS) do
						if each.name == hub.under then level(each.name, each.label) end
					end
					level(hub.name, hub.label)
					level(page.section)
					level(page.tabOf)
				end
			end
		end
		local page
		for _, hub in ipairs(HUBS) do
			for _, each in ipairs(hub.pages) do
				if each[1] == name then page = each end
			end
		end
		level(name or "Cinematic", page and page.label)
		local at = 1
		for _, word in ipairs(words) do
			local hit
			for i = at, #levels do
				for _, text in ipairs(levels[i]) do
					if text:find(word, 1, true) then hit = i break end
				end
				if hit then break end
			end
			if not hit then return false end
			at = hit
		end
		return true
	end

	-- A hub page's icon by its English name (nil for a page with none).
	function ns.PageIcon(name)
		for _, hub in ipairs(HUBS) do
			for _, page in ipairs(hub.pages) do
				if page[1] == name then
					return type(page[2]) == "function" and page[2]() or page[2]
				end
			end
		end
	end

	-- A hub's pages as the CineMode page's tabs list them (a page's tabs
	-- left out, and pages this client hasn't): each one's name, label, icon and
	-- intro, and its switch (on; held: off with the hub's; fixed: can't be
	-- flipped from there). Second, the hub's name as shown.
	function ns.HubPageStates(hubName)
		for _, hub in ipairs(HUBS) do
			if hub.name == hubName then
				local list = {}
				for _, page in ipairs(hub.pages) do
					local tile = not page.tabOf and byName[page[1]]
					if tile then
						local switch = TileSwitch(tile, true)
						local on, held = false, false
						if switch then on, held = SwitchState(switch) end
						local content = tile.resetContent or (tile.canvas and tile.canvas.content)
						list[#list + 1] = { name = page[1], label = L[page.label or page[1]],
							icon = type(page[2]) == "function" and page[2]() or page[2],
							intro = content and content.introText, hasSwitch = switch ~= nil, dev = page.dev,
							section = page.section,
							on = on, held = held, fixed = (switch and switch.follows or held) and true or false }
					end
				end
				return list, L[hub.label or hub.name]
			end
		end
	end

	-- A hub's icons, left to right, each with its tabs (2026-11-16: the
	-- CineMode Overview, every page and tab with a switch): as HubPageStates
	-- gives a page, plus band, and tabs: { name, label, hasSwitch, on, held,
	-- fixed, shared } each. shared: the icon's own switch (or the HUD's for
	-- its sections), turned on and off there. An icon's tabs: its Show in
	-- list's (ns.ShowInTabs, Show in itself being the icon), else its pages
	-- with tabOf it.
	local ICON_SHOW_IN = { ["Mouseover groups"] = "mouse", ["Nameplates"] = "plates", ["Nameplate Names"] = "names" }
	local function StateOf(switch)
		if not switch then return { hasSwitch = false, on = false, held = false, fixed = false } end
		local on, held = SwitchState(switch)
		-- (key, follows: whose switch it goes by, for the CineMode page's "with HUD".)
		return { hasSwitch = true, on = on, held = held, fixed = (switch.follows or held) and true or false,
			key = switch.key, follows = switch.follows and true or false }
	end
	function ns.HubOverview(hubName)
		for _, hub in ipairs(HUBS) do
			if hub.name == hubName then
				local list = {}
				for _, tile in ipairs(hub.tiles or {}) do
					local own = TileSwitch(tile, true)
					local switch = own or TileSwitch(tile)
					local entry = StateOf(switch)
					-- (No switch of its own, a HUD section: shows the HUD's, flipped there.)
					if switch and not own then entry.fixed, entry.shared = true, true end
					local content = tile.resetContent or (tile.canvas and tile.canvas.content)
					entry.name, entry.label = tile.english, L[tile.label or tile.english]
					entry.icon = tile.icon and tile.icon:GetTexture()
					entry.intro, entry.dev, entry.band = content and content.introText, tile.dev, tile.band
					entry.tabs = {}
					local key = tile.showIn or ICON_SHOW_IN[tile.english]
					local tabs = key and ns.ShowInTabs and ns.ShowInTabs(key) or ns.HubTabsOf(hubName, tile.english)
					for _, tab in ipairs(tabs) do
						local page = tab[2]
						if page ~= tile.english and byName[page] then
							local tabSwitch = TileSwitch(byName[page])
							local state = StateOf(tabSwitch)
							state.name, state.label = page, tab[1]
							if tabSwitch and switch and tabSwitch.key == switch.key then state.shared = true end
							entry.tabs[#entry.tabs + 1] = state
						end
					end
					list[#list + 1] = entry
				end
				return list, L[hub.label or hub.name]
			end
		end
	end
	-- A hub's General switch (2026-11-16: Interface's, Visions'): off, every
	-- other page switch of the hub goes off too, the ones that were on kept
	-- (db.hubKept); on, those come back on. Each through its own box, so its
	-- page puts itself right. (Lazy pages made first: their switches with them.)
	function ns.CascadeHub(hubName, generalKey, on)
		local db = ns.GetDB()
		if not db then return end
		if ns.MakeLazyPages then ns.MakeLazyPages("a hub's General switch") end
		db.hubKept = db.hubKept or {}
		for _, hub in ipairs(HUBS) do
			if hub.name == hubName then
				local kept = on and db.hubKept[hubName] or {}
				local done = { [generalKey] = true }
				for _, page in ipairs(hub.pages) do
					local tile = byName[page[1]]
					local switch = tile and TileSwitch(tile)
					if switch and switch.check and not switch.follows and not done[switch.key] then
						done[switch.key] = true
						local now = KeyGet(switch.key) and true or false
						local want = on and kept[switch.key] or false
						if not on and now then kept[switch.key] = true end
						if want ~= now then
							switch.check:SetChecked(want)
							switch.check:GetScript("OnClick")(switch.check, "LeftButton")
						end
					end
				end
				db.hubKept[hubName] = not on and kept or nil
			end
		end
		if ns.PaintPageSwitches then ns.PaintPageSwitches() end
	end

	-- A tab's page switch flipped, as a right-click on its tab does.
	function ns.FlipTabSwitch(name)
		local switch = byName[name] and TileSwitch(byName[name])
		if switch then FlipSwitch(switch) end
	end
end

-- (name in English, as ns.OpenOptions takes it; shown in the game's language,
-- or as shown if given.)
local function RegisterSubpage(subpanel, name, shown)
	subpanel.name = shown or L[name]
	subpanel.pageName = name -- (ns.PageSettings)
	subpanel.parent = "Cinematic"
	-- (Its controls refreshed as it comes into view if a Refresh passed it by
	-- while hidden. A child of its own, so the page's OnShow stays the page's.)
	local watch = CreateFrame("Frame", nil, subpanel)
	watch:SetScript("OnShow", function()
		ns.lastOptionsPage = name -- (Cinematic_ToggleSettings)
		if subpanel.stale then
			subpanel.stale = nil
			Refresh()
		end
	end)
	subpanel.pageWatch = watch
	subpages[name] = subpanel
	-- (Kept by name for good, hub pages too: ns.SettingsPageCanvas.)
	ns.settingsCanvases = ns.settingsCanvases or {}
	ns.settingsCanvases[name] = subpanel
	local page = { name = shown or L[name], key = name, canvas = subpanel }
	searchPages[#searchPages + 1] = page
	ns.WatchSettingsCanvas(subpanel)
	-- (a hub's page: shown in its place there, not listed on its own; the hub
	-- has the search box and Reset page)
	if HubAdd(subpanel, name, page) then
		-- (unless the hub has the page's name, and is listed under it)
		if subpages[name] == subpanel then subpages[name] = nil end
		return
	end
	-- Its own search box, for just its settings, left of Reset page.
	if subpanel.content and subpanel.resetButton then
		local box = CreateSearch(subpanel, subpanel.content, { page })
		box:SetPoint("RIGHT", subpanel.resetButton, "LEFT", -12, 0)
		subpanel.searchBox = box -- (the CineMode page narrows it: its tabs run under it)
	end
	menu.Add(name, subpanel, L[name])
end

-- Sub-page: what brings faded things back, and what stays up.
local function CreateRevealPanel()
	local canvas, content = CreateScrollPage()

	-- Folder tabs at the top (2026-11-17): a tab for each hub CineMode works
	-- through, a row for each of its pages and their tabs (a click on one
	-- opens it), each with when it works: Off or On, or, for one with an Allow
	-- outside CineMode tick, Off, CineMode (only while it's on) or Always
	-- (while it's off too). Then Settings, this page's own (everything made on
	-- it below the rows, moved onto host).
	local SECTIONS = {
		{ "UI Manager", L["Interface"], L["What fades in CineMode, and what brings it back."] },
		{ "Visions", L["Visions"], L["Effects that play over the world when something happens."] },
		{ "Style", L["Style"], L["How the whole interface looks."] },
		{ "Atmosphere", L["Atmosphere"], L["How the world looks and sounds in CineMode."] },
		{ "Camera", L["Camera"], L["The camera coming alive."] },
	}
	local SETTINGS_TAB = #SECTIONS + 1
	local overview, host, PickTab, FillOverview
	local picked = 1 -- (the tab shown, kept while the game runs)
	local tabList = {}
	for i, section in ipairs(SECTIONS) do tabList[i] = { section[2], section[3] } end
	tabList[SETTINGS_TAB] = { L["Settings"], L["How fast the UI fades, the Calm Timer, and what takes you out of CineMode."] }
	local tabsPanel, tabButtons, ShowTabs, tabsBase = ns.FolderTabs(content, tabList, function(i) PickTab(i) end)
	-- (Settings, this page's own, set a little apart from the hubs' tabs.)
	local function ShowTab(i)
		ShowTabs(i)
		local last = tabButtons[SETTINGS_TAB]
		last:ClearAllPoints()
		last:SetPoint("BOTTOMLEFT", tabButtons[SETTINGS_TAB - 1], "BOTTOMRIGHT", 18, 0)
	end
	tabsBase:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -(ns.FOLDER_TAB_HEIGHT + 16))
	tabsPanel:SetPoint("TOPLEFT", tabsBase)
	tabsPanel:SetPoint("RIGHT", content, "RIGHT", -8, 0)
	tabsPanel:SetHeight(1) -- (just its top edge, a line under the tabs)

	local title = Label(content, "GameFontNormalLarge", "CineMode")
	title:SetPoint("TOPLEFT", tabsPanel, "BOTTOMLEFT", 8, -14)
	-- (The tab's hub, what it's for, beside the title: hidden on Settings.)
	local sectionNote = Label(content, "GameFontDisableSmall", "")
	sectionNote:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 1)

	overview = CreateFrame("Frame", nil, content)
	overview:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
	overview:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	overview:SetHeight(1)
	overview.searchSkip = true -- (the settings' own pages are what search finds)
	local summary = Label(overview, "GameFontHighlightSmall")
	summary:SetPoint("BOTTOMRIGHT", overview, "TOPRIGHT", 0, 16)
	local whenHead = Label(overview, "GameFontDisableSmall", L["When"])
	whenHead:SetPoint("TOPRIGHT", overview, "TOPRIGHT", -8, 0)
	local HEAD_H, PAGE_H, TAB_H, TAB_INDENT, SEG_H = 16, 28, 22, 34, 18

	-- A page's Allow outside CineMode ticks (Core.lua's OUTSIDE_CINE and
	-- OUTSIDE_EFFECT), by its English name: with them its row's choices are
	-- Off, CineMode and Always. (Effects: the vignette's and weather's together.)
	local OUTSIDE = {
		Nameplates = { "outsideCinePlates" },
		Effects = { "outsideCineVignette", "outsideCineWeather" },
		Tint = { "outsideCineTint" }, Letterbox = { "outsideCineLetterbox" },
		Audio = { "outsideCineMusic" },
		Cameras = { "outsideCineCameras" },
		["Shoulder Cam"] = { "outsideCineShoulder" }, ["Skyriding Cam"] = { "outsideCineSkyride" },
		["Heal Vision"] = { "outsideCineHeal" }, ["Damage Vision"] = { "outsideCineDamage" },
		["Vitals Vision"] = { "outsideCineVitals" }, ["Quest Vision"] = { "outsideCineQuest" },
		["Roll Vision"] = { "outsideCineRoll" }, ["Teleport Vision"] = { "outsideCineTeleport" },
		["Duel Vision"] = { "outsideCineDuel" }, ["Emote Vision"] = { "outsideCineEmote" },
		["Card Vision"] = { "outsideCineCards" },
	}
	-- (Held to CineMode while Cameras is: their Always does nothing then.)
	local CAMERA_HELD = { ["Shoulder Cam"] = true, ["Skyriding Cam"] = true }
	local function TicksOf(name)
		if name == "Shoulder Cam" and not (ns.ShoulderCamUnlocked and ns.ShoulderCamUnlocked()) then return nil end
		return OUTSIDE[name]
	end
	local function TickOn(db, tick)
		local value = db[tick]
		if value == nil then value = ns.DEFAULTS and ns.DEFAULTS[tick] end
		return value == true
	end
	local CHOICES_ON = { L["Off"], L["On"] }
	local CHOICES_CINE = { L["Off"], L["CineMode"], L["Always"] }
	-- (Which is picked: 1 Off, 2 On or CineMode, 3 Always.)
	local function Picked(entry, ticks)
		if not entry.on then return 1 end
		if not ticks then return 2 end
		local db = ns.GetDB()
		for _, tick in ipairs(ticks) do
			if not TickOn(db, tick) then return 2 end
		end
		return 3
	end
	-- A choice the row can't take now (its page off or on with another's
	-- switch; Always on a camera while Cameras is CineMode only), and why.
	local function Inert(row, i)
		local entry = row.entry
		if entry.held then return L["Off with the General page's switch."] end
		if entry.fixed and (i == 1 or not row.ticks) then return L["On and off with the General page's switch."] end
		if i == 3 and row.tickHeld then return L["Cameras (Camera tab) is set to CineMode."] end
	end
	local function Choose(row, i)
		local entry, ticks = row.entry, row.ticks
		if Inert(row, i) then return end
		if i == 1 then
			if entry.on then row.flip(entry.name) end
		else
			if not entry.on then row.flip(entry.name) end
			if ticks then
				local db = ns.GetDB()
				for _, tick in ipairs(ticks) do db[tick] = i == 3 end
				if ns.RefreshOutsideCine then ns.RefreshOutsideCine(true) end
				Refresh()
				if entry.on and PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
			end
		end
		FillOverview()
	end
	local function ChoiceTip(self)
		local row, i = self.row, self.index
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.label:GetText(), 1, 0.82, 0)
		local tip
		if i == 1 then
			tip = L["This page does nothing."]
		elseif not row.ticks then
			tip = L["This page works as its settings say."]
		elseif i == 2 then
			tip = L["Works only while CineMode is on."]
		else
			tip = L["Works while CineMode is off too."]
		end
		GameTooltip:AddLine(tip, 1, 1, 1, true)
		local why = Inert(row, i)
		if why then GameTooltip:AddLine(why, 1, 0.25, 0.25, true) end
		GameTooltip:Show()
	end
	-- (Its choices side by side, the last at the row's right.)
	local function MakeChoices(row)
		local list = {}
		for i = 1, 3 do
			local choice = CreateFrame("Button", nil, row)
			choice:SetHeight(SEG_H)
			choice.edge = choice:CreateTexture(nil, "BACKGROUND")
			choice.edge:SetAllPoints()
			choice.edge:SetColorTexture(0.35, 0.35, 0.37, 1)
			choice.bg = choice:CreateTexture(nil, "BORDER")
			choice.bg:SetPoint("TOPLEFT", 1, -1)
			choice.bg:SetPoint("BOTTOMRIGHT", -1, 1)
			local hover = choice:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints(choice.bg)
			hover:SetColorTexture(1, 1, 1, 0.08)
			choice.label = choice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			choice.label:SetPoint("CENTER", 0, 0)
			choice.row, choice.index = row, i
			choice:SetScript("OnClick", function(self)
				Choose(self.row, self.index)
				if GameTooltip:IsOwned(self) then ChoiceTip(self) end
			end)
			choice:SetScript("OnEnter", ChoiceTip)
			choice:SetScript("OnLeave", function() GameTooltip:Hide() end)
			list[i] = choice
		end
		return list
	end
	-- (The picked choice's color: Off red, On plain, CineMode blue, Always
	-- green, so what's been changed stands out among the rows.)
	local PICK_COLOR = { { 0.42, 0.13, 0.11 }, { 0.26, 0.26, 0.28 }, { 0.15, 0.3, 0.52 }, { 0.14, 0.42, 0.2 } }
	-- (fixed: the page's switch is another's, the HUD's say: no Off and On,
	-- which could never be clicked here; just CineMode and Always if it has them.)
	local function PaintChoices(row, own)
		local list = row.choices
		local entry = row.entry
		local first = entry.fixed and 2 or 1
		if not own or (entry.fixed and not (row.ticks and entry.on)) then
			for _, choice in ipairs(list) do choice:Hide() end
			return
		end
		local names = row.ticks and CHOICES_CINE or CHOICES_ON
		local pick = Picked(entry, row.ticks)
		for i = #list, 1, -1 do
			local choice = list[i]
			if i > #names or i < first then
				choice:Hide()
			else
				choice:Show()
				choice.label:SetText(names[i])
				choice:SetWidth(math.max(38, math.ceil(choice.label:GetStringWidth()) + 16))
				choice:ClearAllPoints()
				if i == #names then
					choice:SetPoint("RIGHT", row, "RIGHT", -8, 0)
				else
					choice:SetPoint("RIGHT", list[i + 1], "LEFT", 1, 0)
				end
				local on = i == pick
				if on then
					local color = PICK_COLOR[row.ticks and (i == 1 and 1 or i + 1) or i]
					choice.bg:SetColorTexture(color[1], color[2], color[3], 1)
				else
					choice.bg:SetColorTexture(0.06, 0.06, 0.07, 1)
				end
				local tone = on and 1 or 0.7
				choice.label:SetTextColor(tone, tone, tone)
				choice.label:SetVertexColor(tone, tone, tone) -- (one on Forever)
				choice:SetAlpha(Inert(row, i) and (on and 0.7 or 0.35) or 1)
			end
		end
	end
	local function RowTip(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.label:GetText(), 1, 0.82, 0)
		if not self.isTab and type(self.entry.intro) == "string" then
			GameTooltip:AddLine(self.entry.intro, 1, 1, 1, true)
		end
		GameTooltip:AddLine(L["Go to this page."], 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end
	local rows = {}
	local function MakeRow()
		local row = CreateFrame("Button", nil, overview)
		local glow = row:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 0.82, 0, 0.07)
		local line = row:CreateTexture(nil, "BORDER")
		line:SetHeight(1)
		line:SetPoint("BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT")
		line:SetColorTexture(0.22, 0.22, 0.22, 0.8)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(20, 20)
		row.icon:SetPoint("LEFT", 6, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.dev = {}
		if row.CreateLine then
			for _, corners in ipairs({ { "TOPLEFT", "BOTTOMRIGHT" }, { "TOPRIGHT", "BOTTOMLEFT" } }) do
				local cross = row:CreateLine(nil, "OVERLAY")
				cross:SetThickness(2)
				cross:SetColorTexture(1, 0.15, 0.15, 0.9)
				cross:SetStartPoint(corners[1], row.icon, 0, 0)
				cross:SetEndPoint(corners[2], row.icon, 0, 0)
				row.dev[#row.dev + 1] = cross
			end
		end
		row.label = Label(row, "GameFontHighlight", "")
		-- (Where its Off and On would be, whose switch it goes by: "with HUD".)
		row.note = Label(row, "GameFontDisableSmall", "")
		row.note:SetPoint("RIGHT", row, "RIGHT", -10, 0)
		row.choices = MakeChoices(row)
		row:SetScript("OnClick", function(self) ns.OpenOptions(self.entry.name) end)
		row:SetScript("OnEnter", RowTip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return row
	end
	-- (A group's name over its rows, a thin line under it: Heads-up...)
	local subHeads = {}
	local function MakeSubHead()
		local sub = CreateFrame("Frame", nil, overview)
		sub:SetHeight(16)
		sub.text = Label(sub, "GameFontNormalSmall", "")
		sub.text:SetPoint("LEFT", 2, 0)
		local line = sub:CreateTexture(nil, "ARTWORK")
		line:SetHeight(1)
		line:SetPoint("BOTTOMLEFT", 0, -2)
		line:SetPoint("BOTTOMRIGHT", 0, -2)
		line:SetColorTexture(0.6, 0.5, 0.25, 0.5)
		return sub
	end
	-- The tab's hub: each page a row (its group's name over the first of a
	-- group), its tabs indented under it, and how many switches are on.
	function FillOverview()
		if not ns.GetDB() then return end
		local section = SECTIONS[math.min(picked, #SECTIONS)]
		sectionNote:SetText(section[3])
		local pages = ns.HubOverview(section[1]) or {}
		local db = ns.GetDB()
		local count, onCount, used, heads = 0, 0, 0, 0
		local y = -HEAD_H
		-- (A row's name: a hub's General page by its own (Effects, Cameras),
		-- the HUD's as HUD.)
		local function NameOf(entry, isTab)
			if isTab or entry.label ~= L["General"] then return entry.label end
			if entry.name == "HUD:hud" then return L["HUD"] end
			if entry.name:find(":") then return entry.label end
			-- (Style General, Visions General: Style, Visions.)
			return L[entry.name:match("^(.+) General$") or entry.name]
		end
		-- (Each switch's page by its key, over every hub, the first listed
		-- winning (the HUD's before its sections): whose switch a row goes by.)
		local keyNames = {}
		for _, each in ipairs(SECTIONS) do
			for _, page in ipairs(ns.HubOverview(each[1]) or {}) do
				if page.key and not page.follows and not keyNames[page.key] then keyNames[page.key] = NameOf(page, false) end
				for _, tab in ipairs(page.tabs) do
					if tab.key and not tab.follows and not keyNames[tab.key] then keyNames[tab.key] = NameOf(tab, true) end
				end
			end
		end
		local function MasterOf(entry)
			local key = entry.key
			if entry.held and not entry.follows then key = ns.PageSwitchOf(key) or key end
			return keyNames[key] or L["General"]
		end
		local function Place(entry, isTab, flip)
			used = used + 1
			local row = rows[used] or MakeRow()
			rows[used] = row
			-- (A tab turned on and off with its icon's switch, or with none: no choices.)
			local own = entry.hasSwitch and not (isTab and entry.shared)
			row.entry, row.flip, row.isTab = entry, flip, isTab
			row.ticks = own and TicksOf(entry.name) or nil
			row.tickHeld = row.ticks and CAMERA_HELD[entry.name] and db.outsideCineCameras == false or false
			row:SetHeight(isTab and TAB_H or PAGE_H)
			row.icon:SetShown(not isTab)
			if not isTab then row.icon:SetTexture(entry.icon) end
			for _, cross in ipairs(row.dev) do cross:SetShown(not isTab and entry.dev or false) end
			local text = NameOf(entry, isTab)
			row.note:SetText("")
			if own and entry.fixed and not (row.ticks and entry.on) then
				row.note:SetText((entry.held and L["off with %s"] or L["with %s"]):format(MasterOf(entry)))
			end
			row.label:SetFontObject(isTab and "GameFontHighlightSmall" or "GameFontHighlight")
			row.label:SetText(text)
			row.label:ClearAllPoints()
			row.label:SetPoint("LEFT", row, "LEFT", isTab and TAB_INDENT + 12 or TAB_INDENT, 0)
			local off = own and not entry.on
			if not isTab then
				row.icon:SetDesaturated(entry.hasSwitch and not entry.on)
				row.icon:SetAlpha(entry.hasSwitch and not entry.on and 0.6 or 1)
			end
			local tone = off and 0.6 or (isTab and 0.85 or 1)
			row.label:SetTextColor(tone, tone, tone)
			row.label:SetVertexColor(tone, tone, tone) -- (one on Forever)
			PaintChoices(row, own)
			if own and not entry.shared then
				count = count + 1
				if entry.on then onCount = onCount + 1 end
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", overview, "TOPLEFT", 0, y)
			row:SetPoint("RIGHT", overview, "RIGHT", 0, 0)
			row:Show()
			y = y - row:GetHeight()
		end
		local banded, band = false, false
		for _, page in ipairs(pages) do banded = banded or page.band ~= nil end
		for _, page in ipairs(pages) do
			local pageBand = page.band or "General"
			-- (No General header over the first page: the hub's own, the HUD's, on its own at the top.)
			if banded and pageBand ~= band and not (band == false and pageBand == "General") then
				heads = heads + 1
				local sub = subHeads[heads] or MakeSubHead()
				subHeads[heads] = sub
				y = y - (band ~= false and 10 or 4)
				sub:ClearAllPoints()
				sub:SetPoint("TOPLEFT", overview, "TOPLEFT", 0, y)
				sub:SetPoint("RIGHT", overview, "RIGHT", 0, 0)
				sub.text:SetText(L[pageBand])
				sub:Show()
				y = y - 22
			end
			band = pageBand
			Place(page, false, ns.FlipPageSwitch)
			for _, tab in ipairs(page.tabs) do Place(tab, true, ns.FlipTabSwitch) end
		end
		for i = used + 1, #rows do rows[i]:Hide() end
		for i = heads + 1, #subHeads do subHeads[i]:Hide() end
		overview:SetHeight(math.max(1, -y + 8))
		summary:SetText(L["%d of %d switches on."]:format(onCount, count))
		FitContentHeight(content)
	end

	-- (What's on the page so far: the tabs, title and overview stay where they
	-- are; whatever's made after goes onto the Settings tab's host, below.)
	local before = {}
	for _, object in ipairs({ content:GetChildren() }) do before[object] = true end
	for _, object in ipairs({ content:GetRegions() }) do before[object] = true end

	local subtitle = PageIntro(content, title,
		L["How fast the UI fades and what brings it back while CineMode is on."])

	-- Folder tabs of its own (ns.PageTabsBelow): Settings and Exit. Each
	-- section's controls, made on content, go onto its tab's frame as the next
	-- section starts (TakeInto), each tab's stack starting at its top. (What
	-- works outside CineMode: each page's row on the hubs' tabs, 2026-11-17.)
	local subHosts, _, SubShown = ns.PageTabsBelow(content, subtitle, {
		{ L["Settings"], L["How fast the UI fades, the Calm Timer, and fights coming in."] },
		{ L["Exit"], L["What takes you out of CineMode: fights, places, groups, moving and windows."] },
	}, "CineMode/settings")
	-- (Search opens the nearest tab only: Settings first, then this one.)
	for _, subHost in ipairs(subHosts) do
		local open = subHost.openSection
		subHost.openSection = function()
			PickTab(SETTINGS_TAB)
			open()
		end
	end
	local taken = {}
	for _, list in ipairs({ { content:GetChildren() }, { content:GetRegions() } }) do
		for _, object in ipairs(list) do taken[object] = true end
	end
	local function TakeInto(i)
		for _, list in ipairs({ { content:GetChildren() }, { content:GetRegions() } }) do
			for _, object in ipairs(list) do
				if not taken[object] then
					taken[object] = true
					object:SetParent(subHosts[i])
				end
			end
		end
	end
	local function TabTop(i)
		local top = CreateFrame("Frame", nil, subHosts[i])
		top:SetSize(1, 1)
		top:SetPoint("TOPLEFT", subHosts[i], "TOPLEFT", 0, 0)
		return top
	end

	-- Each slider on one line with its name (an inline stack, as on Graphics+).
	local stack = Stack(TabTop(1), "label", true)

	-- Start in CineMode: the main page's box again, the same setting (its
	-- tip too), so the page has all of CineMode's coming in and going out.
	local startCine = ns.SettingControl("fadeUI", content, function() end)
	if startCine then stack:Add(startCine, "check") end

	-- Fading: how fast the UI goes and comes back
	stack:Header(content, L["Fading"])

	local fadeIn = stack:Add(Slider(content, "fadeInTime", L["Fade in time"], 0, 10, 0.1, L["%.1f sec"]), "slider")
	Tooltip(fadeIn, L["How long things take to fade in out of combat."])

	local fadeOut = stack:Add(Slider(content, "fadeOutTime", L["Fade out time"], 0, 10, 0.1, L["%.1f sec"]), "slider")
	Tooltip(fadeOut, L["How long things take to fade out."])

	local combatFadeIn = stack:Add(Slider(content, "combatFadeInTime", L["Combat fade in time"], 0, 10, 0.1,
		L["%.1f sec"]), "slider")
	Tooltip(combatFadeIn, L["How long things take to fade in during a fight."] .. " " ..
		L["Casts count too when a rule uses Casting."])

	local calmFull, calmPet -- (below; hidden while the Calm Timer is Off)
	local calm = stack:Add(Slider(content, "calmTime", L["Calm Timer"], 0, 120, 5, function(value)
		return value == 0 and L["As soon as a fight ends"]
			or L["%d sec after a fight"]:format(value)
	end, nil, function()
		if calmFull then calmFull:Refresh() end
		if calmPet then calmPet:Refresh() end
	end), "slider")
	Tooltip(calm, L["How long after a fight before CineMode comes back."])

	-- Off at the left end; past it, how long after you're back to full the
	-- Calm Timer ends (calmEndsAtFull and calmFullAfter).
	RecordKey(content, "calmEndsAtFull")
	RecordKey(content, "calmFullAfter")
	calmFull = Slider(content, {
		key = "calmFullAfter",
		get = function()
			local db = ns.GetDB()
			return db.calmEndsAtFull and (db.calmFullAfter or 0) or -1
		end,
		set = function(value)
			local db = ns.GetDB()
			db.calmEndsAtFull = value >= 0
			if value >= 0 then
				db.calmFullAfter = value
			end
		end,
	}, L["Exit Calm Timer when healthy"], -1, 15, 1, function(value)
		if value < 0 then
			return L["Off"]
		end
		return value == 0 and L["as soon as you're healthy"] or L["%d sec after you're healthy"]:format(value)
	end, nil, function()
		-- (Just the checkbox below: a full Refresh on every step of a drag lags.)
		if calmPet then calmPet:Refresh() end
	end)
	stack:Add(calmFull, "slider")
	Tooltip(calmFull, L["Ends the Calm Timer early once your health and power are back to full."])

	-- (Indented under it, as its sub-option.)
	calmPet = Check(content, "calmEndsAtFullPet", L["Include your pet"],
		L["With a pet out, its health must be full too."])
	stack:Add(calmPet, "check", 16)
	GreyUnless(calmPet, function(db) return db.calmEndsAtFull end)

	-- (Both do nothing with the Calm Timer Off: hidden, their room kept.)
	for _, control in ipairs({ calmFull, calmPet }) do
		local refresh = control.Refresh
		control.Refresh = function(self)
			refresh(self)
			local shown = (tonumber(ns.GetDB().calmTime) or 0) > 0
			self:SetShown(shown)
			if self.rowName then self.rowName:SetShown(shown) end
		end
	end

	-- Set aside for now (hidden, their settings kept as they are): the Exit
	-- CineMode section. (Mouseover has its own page.)
	local setAside = {}

	-- One column of sections, each below the last: what brings the UI back,
	-- combat text, your portrait.
	local revealHeader = Header(content, L["Exit CineMode"], calm, -24)
	revealHeader:SetPoint("TOPLEFT", calm.rowName or calm, "BOTTOMLEFT", -2, -24)

	local cast = Check(content, "revealOnCast", L["While casting"],
		L["Includes mounting and hearthstone casts."])
	cast:SetPoint("TOPLEFT", revealHeader, "BOTTOMLEFT", -2, -6)

	-- (Opening windows and Talking to NPCs show, in the stack: see below.)
	local npcs = Check(content, "revealAtNPCs", L["Talking to NPCs"],
		L["Exit CineMode while an NPC window, like a quest giver or vendor, is open."])

	-- Stored the other way round (stayWithWindows), like the rest of this
	-- section reading as what brings the UI back.
	local windows = Check(content, "stayWithWindows", L["Opening windows"],
		L["Exit CineMode while a game window, like your bags or the map, is open."], function(value)
			ns.GetDB().stayWithWindows = not value
		end)
	windows.Refresh = function(self) self:SetChecked(not ns.GetDB().stayWithWindows) end

	local drag = Check(content, "revealOnDrag", L["While dragging something"],
		L["Picking up an item or spell brings the UI back until you put it down."])
	drag:SetPoint("TOPLEFT", cast, "BOTTOMLEFT", 0, -2)

	local returnDelay = Slider(content, "returnDelay", L["Back into CineMode after"], 0, 60, 1, L["%d sec"])
	returnDelay:SetPoint("TOPLEFT", drag, "BOTTOMLEFT", 4, -26)
	Tooltip(returnDelay, L["How long things must stay calm before CineMode comes back."])

	for _, control in ipairs({ revealHeader, cast, drag, returnDelay }) do
		setAside[#setAside + 1] = control
	end
	for _, control in ipairs(setAside) do
		control:Hide()
	end

	-- (Standard Frames' In combat rows, brought up early.)
	local hostileCast = Check(content, "fadeInOnHostileCast", L["Cast fade into combat"],
		L["Casting at an enemy out of combat brings up your combat frames."])
	stack:Add(hostileCast, "check")
	GreyUnless(hostileCast, function(db) return db.stayInCombat end)

	-- What takes you out of CineMode: fights, places, groups and moving (from
	-- the main page, 2026-11-11), then windows (the rest of the section set
	-- aside above): its own tab. (Windows and NPCs, made above, go with it.)
	TakeInto(1)
	for _, control in ipairs({ windows, npcs }) do control:SetParent(subHosts[2]) end
	stack = Stack(TabTop(2), "label", true)
	SetSection(content, L["Exit CineMode"]) -- (no heading: the tab says it; for search and the modules)

	-- Stored the other way round (stayInCombat), as the Standard Frames page's lists apply while staying.
	local combat = Check(content, "stayInCombat", L["In combat"],
		L["Being in combat brings the UI back."], function(value)
			ns.GetDB().stayInCombat = not value
			Refresh()
		end)
	combat.Refresh = function(self) self:SetChecked(not ns.GetDB().stayInCombat) end
	stack:Add(combat, "check")

	-- Places in the same order as every other place list (PlaceList).
	local world = Check(content, "offInWorld", L["In the open world"],
		L["Anywhere outside cities, dungeons and raids."])
	stack:Add(world, "check")

	local cities = Check(content, "offInCities", L["In cities"],
		L["Capital cities, including Dalaran."])
	stack:Add(cities, "check")

	local dungeons = Check(content, "offInDungeons", L["In dungeons"],
		L["Keep the normal UI in dungeons and scenarios."])
	stack:Add(dungeons, "check")

	local raids = Check(content, "offInRaids", L["In raids"])
	stack:Add(raids, "check")

	local pvp = Check(content, "offInPvP", L["In PvP"],
		L["While you're flagged for PvP out in the world."])
	stack:Add(pvp, "check")

	local bgs = Check(content, "offInBGs", L["In battlegrounds"], L["Battlegrounds and arenas."])
	stack:Add(bgs, "check")

	local party = Check(content, "offInParty", L["In a party"],
		L["Keep the normal UI while you're in a party (but not a raid group)."])
	stack:Add(party, "check")

	local raidGroup = Check(content, "offInRaidGroup", L["In a raid group"],
		L["Keep the normal UI while you're in a raid group, wherever you are."])
	stack:Add(raidGroup, "check")

	local moving = Check(content, "offWhileMoving", L["When moving"],
		L["Walking or riding about brings the UI back."],
		function(value)
			ns.GetDB().offWhileMoving = value
			Refresh()
		end)
	stack:Add(moving, "check")

	-- (Indented under Moving, as its sub-options.)
	local movingStill = Slider(content, "movingStillAfter", L["Back after stopping"], 1, 60, 1, L["%d sec"])
	Tooltip(movingStill, L["CineMode comes back once you've stood still this long."])
	GreyUnless(movingStill, function(db) return db.offWhileMoving end)
	stack:Add(movingStill, "slider", 16)

	local movingBack = Slider(content, "movingBackAfter", L["Back after moving"], 1, 60, 1, L["%d sec"])
	Tooltip(movingBack, L["CineMode comes back once you've kept moving this long."])
	GreyUnless(movingBack, function(db) return db.offWhileMoving end)
	stack:Add(movingBack, "slider", 16)

	stack:Add(windows, "check")
	stack:Add(npcs, "check")

	-- Allow outside CineMode's ticks: set from each page's row on the hubs'
	-- tabs now (2026-11-17), recorded here as this page's, in their section
	-- still, for Reset page and the profile modules (ProfileModules.lua).
	TakeInto(2)
	SetSection(content, L["Allow outside CineMode"])
	for _, tick in pairs(ns.OUTSIDE_EFFECT or {}) do RecordKey(content, tick) end
	for _, tick in pairs(ns.OUTSIDE_CINE or {}) do RecordKey(content, tick) end
	RecordKey(content, "outsideCinePlates")
	RecordKey(content, "outsideCineCameras")

	-- The Settings tab: everything made since the overview, on a frame of its
	-- own to show and hide (1 by 1: one with no height draws none of it).
	-- Search still finds its settings with a hub's tab shown, and a match
	-- opens this tab (ShowMatch's openSection).
	host = CreateFrame("Frame", nil, content)
	host:SetSize(1, 1)
	host:SetPoint("TOPLEFT")
	host.searchAlways = true
	host.openSection = function() PickTab(SETTINGS_TAB) end
	for _, list in ipairs({ { content:GetChildren() }, { content:GetRegions() } }) do
		for _, object in ipairs(list) do
			if not before[object] and object ~= host then object:SetParent(host) end
		end
	end
	function PickTab(i)
		picked = i
		ShowTab(i)
		overview:SetShown(i ~= SETTINGS_TAB)
		host:SetShown(i == SETTINGS_TAB)
		sectionNote:SetShown(i ~= SETTINGS_TAB)
		if i ~= SETTINGS_TAB and ns.Flag(canvas:IsVisible()) then FillOverview() end
		if i == SETTINGS_TAB then SubShown() end
		FitContentHeight(content)
		C_Timer.After(0, function() FitContentHeight(content) end)
	end
	PickTab(picked)

	canvas:SetScript("OnShow", PageShown(function()
		Refresh()
		if picked ~= SETTINGS_TAB then FillOverview() end
	end, content))
	canvas:Hide()
	RegisterSubpage(canvas, "CineMode")
	-- (Narrower than other pages': the hubs' tabs run along under its left end.)
	if canvas.searchBox then canvas.searchBox:SetWidth(130) end
	-- (The welcome window's See Profile: the CineMode page on its first tab.)
	function ns.OpenCineModeOverview()
		PickTab(1)
		ns.OpenOptions("CineMode")
	end
end

-- Sub-page: your buffs and debuffs, shown when you gain one and on hover.
local function CreateBuffsPanel()
	local canvas, content = CreateScrollPage()

	-- (The Buffs & Debuffs icon's Reveal and links tabs, its Show in the HUD
	-- page's: ns.ShowInTabs("buffs"), 2026-11-16.)
	local title = Label(content, "GameFontNormalLarge", L["Show Advanced"])
	local outer, ShowOuter = ns.PageTabs(content, ns.ShowInTabs("buffs"), 2)
	title:SetPoint("TOPLEFT", outer, "BOTTOMLEFT", 8, -14)

	local note = PageIntro(content, title,
		L["CineMode hides your buffs and debuffs: pick what brings them back."])

	local buffPeek = Check(content, "buffPeek", L["Show buffs when you gain or refresh one"],
		L["Gaining or refreshing a buff briefly shows your buffs and debuffs."])
	buffPeek:SetPoint("TOPLEFT", note, "BOTTOMLEFT", -2, -17) -- (as under the other pages' hidden switch)
	local switch = PageSwitch(content, "handleBuffs", L["Enable Page"],
		L["Lets this page bring your hidden buffs and debuffs back in CineMode."], note)

	-- Two parts (ns.PageTabsBelow, its tabs not drawn: the icon's pick them):
	-- Reveal, and Addon Frame Links.
	local tabHosts, PickPart, TabsShown, AdoptTab = ns.PageTabsBelow(content, switch, {
		{ L["Show Advanced"], L["What brings your hidden buffs and debuffs up for a while."] },
		{ L["Addon Reveal Link"], L["Which supported addon's frames stand in for your buffs and debuffs."] },
	}, "Buffs/page", 2, "buffs", 1, nil, true)
	ns.ShowInParts(canvas, content, title, "buffs", PickPart, ShowOuter, { label = "Buffs & Debuffs",
		icon = "Interface\\Icons\\Spell_Holy_WordFortitude", titles = { L["Show Advanced"], L["Addon Reveal Link"] },
		switchLabel = "Show Advanced" })
	-- (Made before the switch, under the page's intro: onto the tab, at its top.)
	buffPeek:SetParent(tabHosts[1])
	buffPeek:ClearAllPoints()
	buffPeek:SetPoint("TOPLEFT", tabHosts[1], "TOPLEFT", -2, 0)
	buffPeek:HookScript("OnClick", Refresh) -- grey out / enable the options below

	local BUFF_INDENT = 16
	local function IfBuffPeek(db) return db.buffPeek end
	local function IfDebuffPeek(db) return db.debuffPeek end
	local function IfAnyPeek(db) return db.buffPeek or db.debuffPeek end

	local buffAfterCombat = Check(content, "buffPeekAfterCombat", L["Only after combat"],
		L["Only within the Calm Timer after a fight, so buffing up in town doesn't count."])
	buffAfterCombat:SetPoint("TOPLEFT", buffPeek, "BOTTOMLEFT", BUFF_INDENT, -2)
	GreyUnless(buffAfterCombat, IfBuffPeek)

	local buffIgnoreSelf = Check(content, "buffPeekIgnoreSelf", L["Not ones you cast on yourself"],
		L["Buffs you or your pet cast on yourself don't bring them up."])
	buffIgnoreSelf:SetPoint("TOPLEFT", buffAfterCombat, "BOTTOMLEFT", 0, -2)
	GreyUnless(buffIgnoreSelf, IfBuffPeek)

	-- (Only where there's skyriding: as SkyrideCam.lua decides that.)
	local aboveOnlyNew = buffIgnoreSelf
	if ns.isRetail and C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
		local buffNotSkyriding = Check(content, "buffPeekNotSkyriding", L["Not while skyriding"],
			L["No buff brings them up while you're on a skyriding mount."])
		buffNotSkyriding:SetPoint("TOPLEFT", buffIgnoreSelf, "BOTTOMLEFT", 0, -2)
		GreyUnless(buffNotSkyriding, IfBuffPeek)
		aboveOnlyNew = buffNotSkyriding
	end

	local buffOnlyNew = Check(content, "buffPeekOnlyNew", L["Just the new one"],
		L["Only the buff you gained or refreshed shows."])
	buffOnlyNew:SetPoint("TOPLEFT", aboveOnlyNew, "BOTTOMLEFT", 0, -2)
	GreyUnless(buffOnlyNew, IfBuffPeek)
	buffOnlyNew:HookScript("OnClick", Refresh)

	local buffCollapse = Check(content, "buffPeekCollapse", L["Close the gaps"],
		L["The new buff shows at the start of the row, not in its own place among empty spaces."])
	buffCollapse:SetPoint("TOPLEFT", buffOnlyNew, "BOTTOMLEFT", BUFF_INDENT, -2)
	GreyUnless(buffCollapse, function(db) return db.buffPeek and db.buffPeekOnlyNew end)

	-- (Buffs only: the debuffs' own hold is "Keep them up until the debuff is gone".)
	local shortFull = Check(content, "buffPeekShortFull", L["Keep ones lasting less than up until they run out"],
		L["A short buff stays up for as long as it lasts."], function(value)
			ns.GetDB().buffPeekShortFull = value
			Refresh()
		end)
	shortFull:SetPoint("TOPLEFT", buffCollapse, "BOTTOMLEFT", -BUFF_INDENT, -2)
	GreyUnless(shortFull, IfBuffPeek)
	local shortSeconds = Slider(content, "buffPeekShortSeconds", "", 5, 60, 1, L["%d sec"])
	shortSeconds:SetPoint("TOPLEFT", shortFull, "BOTTOMLEFT", 24, -10)
	GreyUnless(shortSeconds, function(db) return IfBuffPeek(db) and db.buffPeekShortFull end)

	local debuffPeek = Check(content, "debuffPeek", L["Show debuffs when you gain or refresh one"],
		L["Gaining or refreshing a debuff briefly shows your debuffs."])
	debuffPeek:SetPoint("TOPLEFT", shortSeconds, "BOTTOMLEFT", -24 - BUFF_INDENT, -16)
	debuffPeek:HookScript("OnClick", Refresh)

	local debuffAfterCombat = Check(content, "debuffPeekAfterCombat", L["Only after combat"],
		L["Only within the Calm Timer after a fight."])
	debuffAfterCombat:SetPoint("TOPLEFT", debuffPeek, "BOTTOMLEFT", BUFF_INDENT, -2)
	GreyUnless(debuffAfterCombat, IfDebuffPeek)

	local debuffUntilGone = Check(content, "debuffPeekUntilGone", L["Keep them up until the debuff is gone"],
		L["Keeps them up while you have any debuff."])
	debuffUntilGone:SetPoint("TOPLEFT", debuffAfterCombat, "BOTTOMLEFT", 0, -2)
	GreyUnless(debuffUntilGone, IfDebuffPeek)

	-- (Debuffs only: a long debuff doesn't keep them up either.)
	local ignoreLong = Check(content, "buffPeekIgnoreLong", L["Not ones lasting longer than"],
		L["Debuffs that last longer than this don't bring them up."], function(value)
			ns.GetDB().buffPeekIgnoreLong = value
			Refresh()
		end)
	ignoreLong:SetPoint("TOPLEFT", debuffUntilGone, "BOTTOMLEFT", 0, -2)
	GreyUnless(ignoreLong, IfDebuffPeek)
	local longMinutes = Slider(content, "buffPeekLongMinutes", "", 1, 60, 1, L["%d min"])
	longMinutes:SetPoint("TOPLEFT", ignoreLong, "BOTTOMLEFT", 24, -10)
	GreyUnless(longMinutes, function(db) return IfDebuffPeek(db) and db.buffPeekIgnoreLong end)

	-- (All the way left: Off, the mouseover time.)
	local function PeekSeconds(value) return value <= 0 and L["Off"] or L["%.1f sec"]:format(value) end
	local buffPeekTime = Slider(content, "buffPeekTime", L["Override Default Buff Reveal Time"], 0, 30, 0.5, PeekSeconds)
	buffPeekTime:SetPoint("TOPLEFT", longMinutes, "BOTTOMLEFT", 4 - BUFF_INDENT - 24, -30)
	Tooltip(buffPeekTime, L["How long a new buff keeps the buffs up."])
	GreyUnless(buffPeekTime, IfBuffPeek)

	local debuffPeekTime = Slider(content, "debuffPeekTime", L["Override Default Debuff Reveal Time"], 0, 30, 0.5,
		PeekSeconds)
	Tooltip(debuffPeekTime, L["How long a new debuff keeps the buffs up."])
	debuffPeekTime:SetPoint("TOPLEFT", buffPeekTime, "BOTTOMLEFT", 0, -34)
	GreyUnless(debuffPeekTime, IfDebuffPeek)

	-- Buffs and debuffs that never bring the buffs up: a row each (icon, name,
	-- Remove), then a box to add one. Still saved as one comma-separated list
	-- (buffPeekIgnore), which is what Frames.lua reads.
	local ignoreLabel = Label(content, "GameFontHighlightSmall", L["Except for these buffs and debuffs:"])
	ignoreLabel:SetPoint("TOPLEFT", debuffPeekTime, "BOTTOMLEFT", -2, -22)

	local function IgnoreEntries()
		local entries = {}
		for entry in (ns.GetDB().buffPeekIgnore or ""):gmatch("[^,]+") do
			entry = entry:match("^%s*(.-)%s*$")
			if entry ~= "" then
				entries[#entries + 1] = entry
			end
		end
		return entries
	end
	local function SaveEntries(entries)
		ns.GetDB().buffPeekIgnore = table.concat(entries, ", ")
		Refresh()
		FitContentHeight(content)
	end
	-- A spell ID shows as its name (and icon) in your game language.
	local function Describe(entry)
		local id = tonumber(entry)
		if not id then
			return entry, nil
		end
		local name, icon
		if C_Spell and C_Spell.GetSpellInfo then
			local info = C_Spell.GetSpellInfo(id)
			name, icon = info and info.name, info and info.iconID
		elseif GetSpellInfo then
			local _
			name, _, icon = GetSpellInfo(id)
		end
		return name and ("%s |cff808080(%d)|r"):format(name, id) or entry, icon
	end

	local ignoreRows = {}
	local function IgnoreRow(i)
		local row = ignoreRows[i]
		if not row then
			row = CreateFrame("Frame", nil, content)
			row:SetSize(300, 22)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(18, 18)
			row.icon:SetPoint("LEFT", 0, 0)
			row.text = Label(row, "GameFontHighlight")
			row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
			row.remove = ns.PanelButton(row)
			row.remove:SetSize(70, 20)
			row.remove:SetPoint("RIGHT", 0, 0)
			row.remove:SetText(L["Remove"])
			row.remove:SetScript("OnClick", function(self)
				local entries = IgnoreEntries()
				table.remove(entries, self:GetParent().index)
				SaveEntries(entries)
			end)
			ignoreRows[i] = row
		end
		return row
	end

	local addBox = ns.SkinEditBox(CreateFrame("EditBox", nil, content, "InputBoxTemplate"))
	addBox:SetSize(200, 20)
	addBox:SetAutoFocus(false)
	local addButton = ns.PanelButton(content)
	addButton:SetSize(70, 20)
	addButton:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
	addButton:SetText(L["Add"])
	local function AddEntry()
		local entry = addBox:GetText():gsub(",", ""):match("^%s*(.-)%s*$")
		addBox:SetText("")
		addBox:ClearFocus()
		if entry ~= "" then
			local entries = IgnoreEntries()
			for _, existing in ipairs(entries) do
				if existing:lower() == entry:lower() then
					return
				end
			end
			entries[#entries + 1] = entry
			SaveEntries(entries)
		end
	end
	addBox:SetScript("OnEnterPressed", AddEntry)
	addBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	addButton:SetScript("OnClick", AddEntry)
	local ADD_TIP = L["Gaining this doesn't bring your buffs up; type a spell ID or name."]
	Tooltip(addBox, ADD_TIP)
	Tooltip(addButton, ADD_TIP)

	-- Rebuilt as the page shows and after each change.
	local ignoreList = { debugName = "buff ignore list", owner = content, Refresh = function()
		local enabled = IfAnyPeek(ns.GetDB()) and true or false
		local previous = ignoreLabel
		local entries = IgnoreEntries()
		for i, entry in ipairs(entries) do
			local row = IgnoreRow(i)
			local text, icon = Describe(entry)
			row.index = i
			row.text:SetText(text)
			row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.remove:SetEnabled(enabled)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and 6 or 0, i == 1 and -6 or -2)
			row:Show()
			previous = row
		end
		for i = #entries + 1, #ignoreRows do ignoreRows[i]:Hide() end
		addBox:ClearAllPoints()
		addBox:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", #entries == 0 and 12 or 6, -8)
		addBox:SetEnabled(enabled)
		addButton:SetEnabled(enabled)
	end }
	controls[#controls + 1] = ignoreList
	RecordKey(content, "buffPeekIgnore") -- (for Reset page)
	AdoptTab() -- (everything above onto the Settings tab)

	canvas:SetScript("OnShow", PageShown(function()
		Refresh()
		TabsShown()
	end, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Buffs/debuffs", L["Buffs/Debuffs"])
end

-- Slow zoom controls for one profile (idleZoom* or taxiZoom*), stacked under
-- `anchor` (a checkbox). Returns the last control, for anchoring below it.
local function BuildZoomControls(parent, stack, prefix)
	local function key(name) return prefix .. name end

	stack:Add(Check(parent, key("Random"), L["Random zoom in and out"],
		L["Keeps drifting to new random distances after the first pull-back."]), "check")

	local zoomDistance = stack:Add(Slider(parent, key("Distance"), L["Zoom out up to"], 1, 40, 1, L["%d yards"]), "slider")
	Tooltip(zoomDistance, L["How far past your own zoom the camera pulls back (the first move always " ..
		"goes this far)."])

	local zoomIn = stack:Add(Slider(parent, key("In"), L["Zoom in up to"], 0, 10, 1, L["%d yards"]), "slider")
	Tooltip(zoomIn, L["How much closer than your own zoom the random zoom may come."])

	stack:Add(Slider(parent, key("Time"), L["Each zoom takes"], 5, 60, 1, L["%d sec"]), "slider")

	local zoomEase = stack:Add(Slider(parent, key("Ease"), L["Zoom ease in/out"], 10, 50, 5, "%d%%", 100), "slider")
	Tooltip(zoomEase, L["How much of each zoom is spent speeding up and slowing down."])

	local zoomPause = stack:Add(Slider(parent, key("Pause"), L["Pause between zooms"], 0, 60, 1, L["%d sec"]), "slider")
	Tooltip(zoomPause, L["Random zoom only."])

	local zoomPauseVary = stack:Add(Slider(parent, key("PauseVary"), L["Pause varies by up to"], 0, 30, 0.5,
		L["%.1f sec"]), "slider")
	Tooltip(zoomPauseVary, L["Each pause varies at random by up to this much."])

	stack:Add(Check(parent, key("PastMax"), L["Allow zooming past your maximum"],
		L["Raises the game's max camera distance while pulled back."]), "check")
end

-- The camera modes' switch, on the Cameras page: off, no camera mode
-- starts, Shoulder Cam lets go, and it and the Camera Settings page grey out.
local function CameraModesSwitch(content, anchor)
	return PageSwitch(content, "cameraModes", L["Enable Cameras"],
		L["Lets the cameras start as the rows below say."], anchor, function()
			if ns.ApplyShoulderCam then ns.ApplyShoulderCam() end
		end)
end

-- Camera rotation settings, built once per profile (taxiOrbit* for flights,
-- idleOrbit* for standing still), each on its own sub-page.
-- Rotation controls for a camera's fixed style: "sweep" (steady sweeps: the
-- AFK camera) or "back" (sways from side to side: flights, RP walk).
local function BuildRotationControls(container, stack, prefix, style)
	local function key(name) return prefix .. name end

	if style == "sweep" then
		local orbitRight = stack:Add(Check(container, key("Right"), L["Turn clockwise"],
			L["Sweeps turn the other way round."]), "check")

		if prefix == "idleOrbit" then
			stack:Add(Check(container, key("RandomDir"), L["Random direction"],
				L["Each time, the camera picks clockwise or anticlockwise at random."], function(value)
					ns.GetDB()[key("RandomDir")] = value
					Refresh()
				end), "check")
			GreyUnless(orbitRight, function(db) return not db[key("RandomDir")] end)
		end

		local orbitStep = stack:Add(Slider(container, key("Step"), L["Turn per sweep"], 10, 90, 5, "%d°"), "slider")
		Tooltip(orbitStep, L["How far each sweep turns, always the same way, staying level."])

		local orbitSpeed = stack:Add(Slider(container, key("Speed"), L["Turn speed"], 1, 45, 1, "%d°/sec"), "slider")
		Tooltip(orbitSpeed, L["Top speed in the middle of a sweep."])
	else
		local minChange = stack:Add(Slider(container, key("MinChange"), L["Minimum change"], 10, 120, 5, "%d°"), "slider")
		Tooltip(minChange, L["Each new angle is at least this many degrees from the last."])

		local backArc = stack:Add(Slider(container, key("BackArc"), L["Sway either side"], 0, 90, 5, "%d°"), "slider")
		Tooltip(backArc, L["How far the camera may sway to either side."])

		local pitchUp = stack:Add(Slider(container, key("PitchUp"), L["Tilt up as far as"], 0, 45, 5, "%d°"), "slider")
		Tooltip(pitchUp, L["Each move also tilts the camera to a random angle between these limits."])

		local pitchDown = stack:Add(Slider(container, key("PitchDown"), L["Tilt down as far as"], 0, 45, 5, "%d°"), "slider")
		Tooltip(pitchDown, L["How far below level a move may tilt."])

		if prefix == "runOrbit" then
			local pitchFloor = stack:Add(Slider(container, key("PitchFloor"), L["Lowest tilt"], 0, 45, 1, "%d°"), "slider")
			Tooltip(pitchFloor, L["The camera never tilts more than this far below where it started."])
		end

		local moveTime = stack:Add(Slider(container, key("MoveTime"), L["Each move takes"], 1, 20, 0.5, L["%.1f sec"]), "slider")
		Tooltip(moveTime, L["How long each move takes, however far it goes."])
	end

	local ease = stack:Add(Slider(container, key("Ease"), L["Ease in/out"], 10, 50, 5, "%d%%", 100), "slider")
	Tooltip(ease, L["How much of each move is spent speeding up and slowing down."])

	local orbitPause = stack:Add(Slider(container, key("Pause"), L["Pause between moves"], 0, 60, 0.5, L["%.1f sec"]), "slider")
	if style == "sweep" then
		Tooltip(orbitPause, L["How long the camera rests between sweeps."])
	else
		Tooltip(orbitPause, L["How long the camera rests between moves."])
	end

	stack:Add(Check(container, key("Drift"), L["Keep drifting during pauses"],
		style == "sweep"
			and L["Instead of stopping between sweeps, the camera keeps creeping slowly the same way."]
			or L["Instead of stopping between moves, the camera keeps creeping slowly back toward " ..
				"the middle."]), "check")

	stack:Add(Slider(container, key("DriftSpeed"), L["Drift speed"], 0.5, 5, 0.5, "%.1f°/sec"), "slider")
end


-- The places a "Turn ... off in" list covers, in the same order and with the
-- same names everywhere: Open world (where a list has it), Cities, Dungeons,
-- Raids, PvP, then the groups (Party, Raid group).
local PLACES = {
	{ "Cities", L["Cities"] }, { "Dungeons", L["Dungeons"] },
	{ "Raids", L["Raids"] }, { "PvP", L["PvP"] },
}

-- The Camera Settings page: the camera settings no Scripts page step uses
-- yet, a folder tab for each camera that still has some (cameras whose
-- settings have all moved get none). Each camera is laid out on its
-- section's body as it once was on a page of its own; CameraSection gives
-- the body and the title to build under. The tab last picked is kept across
-- reloads (SectionState, its id "Camera Settings/tab", open the camera's key).
local SECTION_HEADER = 30 -- height of a section's name row
local SECTION_GAP = 6
-- In order: { frame, body, icon, reset, name, key, open }. cameraSections.focus: the
-- one camera shown (its icon picked in the Camera hub), open, the rest hidden.
-- cameraSections.tabs: the folder tabs (panel, tab buttons, Show), once made.
local cameraSections = {}
local cameraSettingsContent, cameraSettingsTop -- the page's content, and what the first section goes under
local cameraTabPicked = { id = "Camera Settings/tab", open = false }

-- Whether a section still has settings of its own (not all on the Scripts page).
local function SectionHasSettings(section)
	local moved = movedFrom[section.body]
	return not moved or moved.left == true
end

local function LayoutCameraSections()
	local focus, tabs = cameraSections.focus, cameraSections.tabs
	-- (one camera on its own: its name row is the page's title)
	cameraSettingsTop:SetShown(not focus)
	cameraSettingsTop.title:SetShown(not focus)
	-- In tabs: the one picked (the first with settings, if none is yet).
	local picked
	if tabs and not focus then
		SectionState.Restore(cameraTabPicked)
		local first, saved
		for i, section in ipairs(cameraSections) do
			local has = SectionHasSettings(section)
			tabs.buttons[i]:SetShown(has)
			if has then
				first = first or section
				if section.key == cameraTabPicked.open then saved = section end
			end
		end
		picked = saved or first
		tabs.panel:SetShown(picked ~= nil)
		tabs.empty:SetShown(picked == nil)
		for i, section in ipairs(cameraSections) do
			if section == picked then tabs.Show(i) end
		end
	else
		if tabs then
			tabs.panel:Hide()
			tabs.empty:Hide()
			for _, button in ipairs(tabs.buttons) do button:Hide() end
		end
	end
	local above
	for _, section in ipairs(cameraSections) do
		SectionState.Restore(section)
		local shown, open
		if tabs and not focus then
			shown, open = section == picked, section == picked
		else
			shown, open = not focus or focus == section, section.open or focus == section
		end
		section.frame:SetShown(shown)
		if shown then
			section.frame:ClearAllPoints()
			if tabs and not focus then
				section.frame:SetPoint("TOPLEFT", tabs.panel, "TOPLEFT", 30, -12)
				section.frame:SetPoint("RIGHT", tabs.panel, "RIGHT", -12, 0)
			else
				if above then
					section.frame:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SECTION_GAP)
				elseif focus then
					section.frame:SetPoint("TOPLEFT", cameraSettingsContent, "TOPLEFT", 16, -12)
				else
					section.frame:SetPoint("TOPLEFT", cameraSettingsTop, "BOTTOMLEFT", 0, -16)
				end
				section.frame:SetPoint("RIGHT", cameraSettingsContent, "RIGHT", -16, 0)
			end
			above = section.frame
		end
		section.body:SetShown(open)
		local height = SECTION_HEADER
		if open then
			height = math.max(height, (ContentDepth(section.body) or 0) + 12)
		end
		section.frame:SetHeight(height)
		if tabs and not focus and section == picked then
			tabs.panel:SetHeight(height + 24)
		end
		section.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up"
			or "Interface\\Buttons\\UI-PlusButton-Up")
		-- (on its own or in a tab: it can't close; on its own the hub's Reset
		-- page resets it)
		section.icon:SetShown(not focus and not tabs)
		section.reset:SetShown(not focus)
		if section.test then
			section.test:ClearAllPoints()
			if focus then
				section.test:SetPoint("RIGHT", section.reset:GetParent(), "RIGHT", -6, 0)
			else
				section.test:SetPoint("RIGHT", section.reset, "LEFT", -6, 0)
			end
		end
	end
	if cameraSettingsContent then
		FitContentHeight(cameraSettingsContent)
	end
end

-- (Laid out again next frame too, once the opened settings have settled.)
local function RelayoutCameraSections()
	LayoutCameraSections()
	C_Timer.After(0, LayoutCameraSections)
end

StaticPopupDialogs.CINEMATIC_RESET_SECTION = {
	text = L["Put this camera's settings back to the profile's own?"],
	button1 = YES, button2 = NO,
	OnAccept = function(_, content) ResetPage(content) end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

-- A new section at the bottom of the Camera Settings page: its body (where
-- the camera's settings go) and an anchor where its title used to be (the
-- title itself is in the name row). key: its name in English, for what's
-- remembered of it.
local function CameraSection(name, key)
	local section = { open = false, id = "Camera Settings/" .. key, key = key }
	local frame = CreateFrame("Frame", nil, cameraSettingsContent)
	local previous = cameraSections[#cameraSections]
	if previous then
		frame:SetPoint("TOPLEFT", previous.frame, "BOTTOMLEFT", 0, -SECTION_GAP)
	else
		frame:SetPoint("TOPLEFT", cameraSettingsTop, "BOTTOMLEFT", 0, -16)
	end
	frame:SetPoint("RIGHT", cameraSettingsContent, "RIGHT", -16, 0)
	frame:SetHeight(SECTION_HEADER)

	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT")
	body:SetPoint("TOPRIGHT")
	body:SetHeight(1)
	body:Hide()
	body.searchAlways = true
	SetSection(body, name, true)

	-- The name row: click to open or close (the +/- sits in the page margin).
	local header = CreateFrame("Button", nil, frame)
	header:SetPoint("TOPLEFT", -18, 0)
	header:SetPoint("TOPRIGHT")
	header:SetHeight(SECTION_HEADER)
	header:SetFrameLevel(body:GetFrameLevel() + 5)
	local band = header:CreateTexture(nil, "BACKGROUND")
	band:SetAllPoints()
	band:SetColorTexture(1, 1, 1, 0.05)
	local hover = header:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 0.82, 0, 0.08)
	local icon = header:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("LEFT", header, "LEFT", 1, 0)
	local title = Label(header, "GameFontNormalLarge", name)
	title:SetPoint("LEFT", header, "LEFT", 18, 0)
	header:SetScript("OnClick", function()
		if cameraSections.focus or cameraSections.tabs then return end
		SectionState.Save(section, not section.open)
		RelayoutCameraSections()
	end)

	local reset = ns.PanelButton(header)
	reset:SetSize(90, 20)
	reset:SetPoint("RIGHT", header, "RIGHT", -6, 0)
	reset:SetText(L["Reset"])
	reset.searchSkip = true
	Tooltip(reset, L["Puts this camera's settings back to your profile's values."])
	reset:SetScript("OnClick", function()
		StaticPopup_Show("CINEMATIC_RESET_SECTION", nil, nil, body)
	end)

	-- Test: runs the camera for a while (CameraTests.lua), Stop with the
	-- seconds left meanwhile. (Placed by LayoutCameraSections: left of Reset, or
	-- at the row's end in the Camera hub, where Reset is the hub's own.)
	local testKey
	for k in pairs(ns.CAMERA_TESTS or {}) do
		if k == key or L[k] == key then testKey = k end
	end
	if testKey then
		local test = ns.PanelButton(header)
		test:SetSize(90, 20)
		test:SetPoint("RIGHT", reset, "LEFT", -6, 0)
		test:SetText(L["Test"])
		test.searchSkip = true
		Tooltip(test, ns.CAMERA_TESTS[testKey].tip and L[ns.CAMERA_TESTS[testKey].tip]
			or L["Runs this camera for 30 seconds where you stand."])
		test:SetScript("OnClick", function()
			if ns.CameraTestLeft(testKey) then
				ns.CameraTestStop()
			else
				ns.CameraTestStart(testKey)
			end
		end)
		local wait = 0
		ns.SetOnUpdate(test, function(self, elapsed)
			wait = wait - elapsed
			if wait > 0 then return end
			wait = 0.2
			local left = ns.CameraTestLeft(testKey)
			self:SetText(left and L["Stop (%d)"]:format(math.ceil(left)) or L["Test"])
		end)
		section.test = test
	end

	-- (Search: a setting found in here opens the section first, or in the
	-- Camera hub picks its icon.)
	function body.openSection()
		if section.selectTab then
			section.selectTab()
		elseif cameraSections.tabs then
			SectionState.Save(cameraTabPicked, section.key)
			RelayoutCameraSections()
		elseif not section.open then
			SectionState.Save(section, true)
			RelayoutCameraSections()
		end
	end
	section.frame, section.body, section.icon, section.reset, section.name = frame, body, icon, reset, name
	cameraSections[#cameraSections + 1] = section
	local anchor = body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	anchor:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -SECTION_HEADER + 2)
	anchor:SetSize(1, 1)
	-- (The settings its cameras' script pages have are left out
	-- here, see Stack. Its cameras' script ids: CameraScripts.lua.)
	movedFrom[body] = ns.CameraSectionMoved and ns.CameraSectionMoved(key) or nil
	return body, anchor, title
end

-- Every camera mode's page is laid out the same way:
--   Starting (full width): opts.top's own section first if any, then
--     starting cinematic mode straight away, the
--     mode's own starting options (opts.start), the wait after combat and the
--     pause after you move the camera.
--   Then, in one column, each slider on one line with its name: Rotation
--     (and opts.rotationExtras), Zoom (and opts.zoomExtras), the mode's own
--     sections (opts.extras: Height, Turning, Fly-bys, Landing), Depth of field.
-- The opts functions take (content, stack) and add their controls to it.
-- The Death, Quest, Tele and Chat Cam sections follow the same layout by hand.
local ZOOM_TIP = L["The camera slowly pulls back, then drifts in and out."]
local INPUT_PAUSE_TIP = L["After you move the camera yourself, it waits this long before carrying on."]

local function CreateCameraModePanel(opts)
	local content, top, title = CameraSection(L[opts.name], opts.name)

	local subtitle = PageIntro(content, title, opts.description, top)

	local stack = Stack(subtitle, "label", true)
	if opts.top then
		opts.top(content, stack)
	end

	stack:Header(content, L["Starting"])
	if opts.start then
		opts.start(content, stack)
	end
	local inputPause = stack:Add(Slider(content, opts.inputPauseKey, L["Pause after you move the camera"],
		0, 60, 0.5, L["%.1f sec"]), "slider")
	Tooltip(inputPause, INPUT_PAUSE_TIP .. (opts.inputPauseTip and (" " .. opts.inputPauseTip) or ""))

	stack:Header(content, L["Rotation"])
	stack:Add(Check(content, opts.orbitPrefix, opts.rotateLabel, opts.rotateTip), "check")
	BuildRotationControls(content, stack, opts.orbitPrefix, opts.style)
	if opts.rotationExtras then
		opts.rotationExtras(content, stack)
	end

	stack:Header(content, L["Zoom"])
	stack:Add(Check(content, opts.zoomPrefix, L["Slowly zoom"], opts.zoomTip or ZOOM_TIP), "check")
	BuildZoomControls(content, stack, opts.zoomPrefix)
	if opts.zoomExtras then
		opts.zoomExtras(content, stack)
	end

	if opts.extras then
		opts.extras(content, stack)
	end

	stack:Header(content, L["Depth of field"])
	local dof = stack:Add(Slider(content, opts.dofKey, L["Edge haze"], 0, 100, 2.5, "%.1f%%", 100, function(value)
		if ns.FocusPreview then ns.FocusPreview(value / 100) end
	end), "slider")
	Tooltip(dof, L["A soft haze around the screen edges in this camera mode."])
	GreyUnless(dof, function(db) return db.visualEffects and db.depthOfField end)
end

-- The "Height" section of a camera mode's page: how far it lowers the camera.
local function HeightExtras(key, minV, maxV, tip)
	return function(content, stack)
		stack:Header(content, L["Height"])
		local level = stack:Add(Slider(content, key, L["Lower the camera"], minV, maxV, 5, "%d°"), "slider")
		Tooltip(level, tip)
	end
end

-- The "Turning" section of a travel mode's page (RP walk, auto-run).
-- A comma-separated list setting in an edit box (saved as you leave it).
local function ListBox(parent, key, width, tip, onSave)
	RecordKey(parent, key)
	local box = ns.SkinEditBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	local function Save(self)
		ns.GetDB()[key] = self:GetText()
		if onSave then onSave() end
	end
	box:SetScript("OnEnterPressed", function(self) Save(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusLost", Save)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.GetDB()[key] or "")
		self:ClearFocus()
	end)
	box.Refresh = function(self)
		if not self:HasFocus() then self:SetText(ns.GetDB()[key] or "") end
	end
	controls[#controls + 1] = box
	Tooltip(box, tip)
	return box
end

-- Each event's tip (the Cameras page's rows).
local EVENT_TIPS = {
	Campfire = L["Standing or sitting still with any of the buffs listed below (like Welcoming Campfire)."],
	Sit = L["Doing the emote or pressing the sit key."],
	SitButton = L["Clicking the Campfire button on the Quality of Life page."],
	Sleep = L["Doing the emote, until you move or jump."],
	Dance = L["Doing the emote, until you move or jump."],
	Kneel = L["Doing the emote, until you move or jump."],
	Chair = L["Right-clicking a seat to sit on it."],
	Weapon = L["Unsheathing your weapon with your Sheathe key out of combat."],
	Hearth = L["Casting your Hearthstone."],
	Teleport = L["Casting a teleport spell."],
	Logout = L["Logging out where the game counts down first."],
	Stare = L["Doing the emote while standing still."],
	Fishing = L["Casting Fishing, until you move or jump."],
	AFK = L["Being flagged AFK."],
	Still = L["Standing still for the time below with nothing else going on."],
	Flight = L["Taking off on a flight path."],
	Quest = L["Talking to a quest giver."],
	QuestGossip = L["Talking to an NPC about a quest step."],
}
local function CreateFlightPanel()
	CreateCameraModePanel({
		name = L["Flight Cam"],
		description = L["On flight paths, the camera sways side to side with an occasional fly-by."],
		start = function(content, stack)
			stack:Add(Check(content, "dropTargetOnFlights", L["Drop your target at takeoff"],
				L["Your target's frames fade until you pick a new target or land."]), "check")
		end,
		inputPauseKey = "taxiInputPause",
		orbitPrefix = "taxiOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["The camera sways from side to side around where it started."],
		extras = function(content, stack)
			stack:Header(content, L["Fly-bys"])
			stack:Add(Check(content, "taxiFlyBy", L["Random fly-bys"],
				L["Now and then the camera turns round to look back past you."]), "check")
			stack:Add(Check(content, "flyByLook", L["Do /look as a fly-by starts"],
				L["Your character does /look as a fly-by starts, which players nearby see."]), "check")
			local every = stack:Add(Slider(content, "taxiFlyByEvery", L["About one every"], 30, 300, 10, L["%d sec"]), "slider")
			Tooltip(every, L["About one fly-by per this many seconds of flight."])
			local from = stack:Add(Slider(content, "taxiFlyByFrom", L["Not before"], 0, 100, 5, L["%d%% of the way"]), "slider")
			Tooltip(from, L["Keeps random fly-bys away from takeoff."])
			local to = stack:Add(Slider(content, "taxiFlyByTo", L["Not after"], 0, 100, 5, L["%d%% of the way"]), "slider")
			Tooltip(to, L["Keeps random fly-bys away from landing (and the settle before it)."])
			local angle = stack:Add(Slider(content, "flyByAngle", L["Turn round"], 90, 180, 5, "%d°"), "slider")
			Tooltip(angle, L["How far the camera turns round, where 180 looks straight back at you."])
			local turnTime = stack:Add(Slider(content, "flyByTurnTime", L["Turn round takes"], 3, 20, 1, L["%d sec"]), "slider")
			Tooltip(turnTime, L["How long the turn round takes, easing in and out."])
			stack:Add(Slider(content, "flyByHold", L["Look back for"], 0, 20, 1, L["%d sec"]), "slider")
			stack:Add(Slider(content, "flyByBackTime", L["Turn back takes"], 3, 20, 1, L["%d sec"]), "slider")

			stack:Header(content, L["Landing"])
			stack:Add(Check(content, "taxiSettle", L["Turn back before landing"],
				L["Before you land, the camera turns back to where it was at takeoff."]), "check")
			stack:Add(Check(content, "taxiLandZoom", L["Put the zoom back when you land"],
				L["As you land, the camera glides back to your takeoff zoom."]), "check")
			local settleLead = stack:Add(Slider(content, "taxiSettleLead", L["Turned back by"], 2, 20, 1,
				L["%d sec before landing"]), "slider")
			Tooltip(settleLead, L["How long before landing the camera has settled."])
		end,
		zoomPrefix = "taxiZoom", dofKey = "dofFlight",
	})
end

local function CreateStandingPanel()
	CreateCameraModePanel({
		name = L["AFK Cam"],
		description = L["When you stand still a while or go AFK, the camera slowly circles your character."],
		inputPauseKey = "idleInputPause",
		orbitPrefix = "idleOrbit", style = "sweep",
		rotateLabel = L["Sweep around you"],
		rotateTip = L["The camera sweeps around your character, pausing between sweeps."],
		zoomPrefix = "idleZoom",
		dofKey = "dofIdle",
	})
end

local function CreateAutoRunPanel()
	CreateCameraModePanel({
		name = L["Auto-run Cam"],
		description = L["While you auto-run, the camera follows along until you stop or steer."],
		inputPauseKey = "runInputPause",
		orbitPrefix = "runOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["The camera sways gently from side to side around where it started, pausing " ..
			"between moves."],
		zoomPrefix = "runZoom",
		zoomTip = L["The camera eases out a little, then drifts in and out."],
		dofKey = "dofRun",
	})
end

local function CreateCozyPanel()
	CreateCameraModePanel({
		name = L["Cozy Cam"],
		description = L["When you rest, sit or dance, the camera slowly turns to face you and eases in."],
		inputPauseKey = "cozyInputPause",
		orbitPrefix = "cozyOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["Once turned half round, the camera sways gently from side to side."],
		extras = HeightExtras("cozyLevel", -30, 80, L["How far the camera comes down toward the ground as it turns."]),
		zoomPrefix = "cozyZoom",
		zoomTip = L["The camera eases in close, then drifts a little in and out."],
		zoomExtras = function(content, stack)
			local close = stack:Add(Slider(content, "cozyZoomClose", L["Zoom in to about"], 2, 20, 0.5,
				L["%.1f yards"]), "slider")
			Tooltip(close, L["The close-up distance the cozy camera zooms in to."])
		end,
		dofKey = "dofCozy",
	})
end

local function CreateVistaPanel()
	CreateCameraModePanel({
		name = L["Vista Cam"],
		description = L["When you /stare at the view, the camera sways very gently from where it is."],
		inputPauseKey = "vistaInputPause",
		orbitPrefix = "vistaOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["The camera sways very gently from side to side."],
		extras = HeightExtras("vistaLevel", -30, 45, L["How much lower the camera sways, to look out across the view."]),
		zoomPrefix = "vistaZoom",
		zoomTip = L["The camera eases out a little, then drifts slowly in and out."],
		dofKey = "dofVista",
	})
end

local function CreateFishPanel()
	CreateCameraModePanel({
		name = L["Fish Cam"],
		description = L["While you fish, the camera sways gently and keeps your bobber in view."],
		inputPauseKey = "fishInputPause",
		orbitPrefix = "fishOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["The camera sways a little from side to side."],
		extras = HeightExtras("fishLevel", -30, 45, L["How much lower the camera sways, to look out across the water."]),
		zoomPrefix = "fishZoom",
		zoomTip = L["The camera eases out a little, then drifts slowly in and out."],
		dofKey = "dofFish",
	})
end

local function CreateWalkPanel()
	CreateCameraModePanel({
		name = L["RP Walk Cam"],
		description = L["While you auto-walk, the camera drifts gently along with you."],
		inputPauseKey = "walkInputPause",
		inputPauseTip = L["Keep it short, so it's back in time if you need to steer."],
		orbitPrefix = "walkOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["The camera sways gently from side to side around where it started, pausing " ..
			"between moves."],
		zoomPrefix = "walkZoom",
		zoomTip = L["The camera eases out a little, then drifts in and out."],
		dofKey = "dofWalk",
	})
end

-- Not a CreateCameraModePanel page (no sway, zoom profile or music switch of
-- its own), but laid out the same way.
local function CreateDeathPanel()
	local content, top, title = CameraSection(L["Death Cam"], "Death Cam")
	local subtitle = PageIntro(content, title, L["When you die, the camera slowly circles your body until you release or are revived."], top)
	-- (On or off, and its song, are the Die row's camera and Music on the Cameras page.)
	local function IfOn() return ns.TriggerAnyRow("Death") end

	local stack = Stack(subtitle, "label", true)
	-- (The death banner, "YOU DIED" across the screen: the Cards page's Death now.)
	stack:Add(ns.CardsLink(content, L["The death banner:"], "death"), "label")

	stack:Header(content, L["Starting"])
	local delay = stack:Add(Slider(content, "deathOrbitDelay", L["Start after"], 0, 10, 0.5, L["%.1f sec"]), "slider")
	Tooltip(delay, L["How long after you die before the camera starts turning."])
	GreyUnless(delay, IfOn)
	local afterBoss = stack:Add(Check(content, "deathAfterBoss", L["Wait for boss fights to end"],
		L["If you die in a boss fight, the death camera waits for it to end."]), "check")
	GreyUnless(afterBoss, IfOn)
	local selfRes = stack:Add(Check(content, "deathOffWithSelfRes", L["Not with a soulstone or Reincarnation"],
		L["No death camera when you can come back yourself, like with a soulstone."]), "check")
	GreyUnless(selfRes, IfOn)
	local exitButton = stack:Add(Check(content, "deathExitButton", L["Exit camera button"],
		L["Adds a button under the release popup to get your own view back."]), "check")
	GreyUnless(exitButton, IfOn)

	stack:Header(content, L["Rotation"])
	local right = stack:Add(Check(content, "deathOrbitRight", L["Turn clockwise"]), "check")
	GreyUnless(right, function(db) return IfOn(db) and not db.deathOrbitRandomDir end)
	local randomDir = stack:Add(Check(content, "deathOrbitRandomDir", L["Random direction"],
		L["Each death, the camera picks clockwise or anticlockwise at random."]), "check")
	randomDir:HookScript("OnClick", Refresh)
	GreyUnless(randomDir, IfOn)
	local speed = stack:Add(Slider(content, "deathOrbitSpeed", L["Turn speed"], 1, 20, 1, "%d°/sec"), "slider")
	GreyUnless(speed, IfOn)

	stack:Header(content, L["Zoom"])
	local zoom = stack:Add(Slider(content, "deathZoom", L["Zoom out by"], 0, 15, 0.5, L["%.1f yards"]), "slider")
	Tooltip(zoom, L["How far the camera pulls back while you're dead."])
	GreyUnless(zoom, IfOn)

	stack:Header(content, L["Height"])
	local level = stack:Add(Slider(content, "deathLevel", L["Raise the camera"], 0, 90, 5, "%d°"), "slider")
	Tooltip(level, L["How far the camera rises to look down on your body."])
	GreyUnless(level, IfOn)

	stack:Header(content, L["Screen"])
	-- Hide all except: the Mouseover page's groups, ticked (deathKeepGroups:
	-- ns.HoverGroupId -> true). (The release and resurrect popups always show.)
	local KEEP_TIP = L["The groups ticked here stay up while the death camera hides your frames."]
	-- (None until the settings load: the pages are built first.)
	local function KeepGroups()
		return ns.db and ns.GetHoverGroups() or {}
	end
	local function KeepTicked(group)
		local kept = ns.GetDB().deathKeepGroups
		return kept ~= nil and kept[ns.HoverGroupId(group)] and true or false
	end
	local function ToggleKeep(group)
		local db = ns.GetDB()
		db.deathKeepGroups = db.deathKeepGroups or {}
		local id = ns.HoverGroupId(group)
		db.deathKeepGroups[id] = not db.deathKeepGroups[id] or nil
	end
	RecordKey(content, "deathKeepGroups")
	local okKeep, keep = ns.MenuDropdown(content)
	if okKeep and keep and keep.SetupMenu then
		stack:Add(Label(content, "GameFontHighlight", L["Hide all except"]), "label")
		keep:SetWidth(260)
		keep.searchSkip = true -- (it shows the current ticks, not a label)
		keep:SetupMenu(function(_, root)
			for _, group in ipairs(KeepGroups()) do
				root:CreateCheckbox(group.name, function() return KeepTicked(group) end, function()
					ToggleKeep(group)
					return MenuResponse and MenuResponse.Refresh
				end)
			end
		end)
		if keep.SetSelectionText then
			keep:SetSelectionText(function()
				local ticked = {}
				for _, group in ipairs(KeepGroups()) do
					if KeepTicked(group) then ticked[#ticked + 1] = group.name end
				end
				return #ticked > 0 and table.concat(ticked, ", ") or L["None"]
			end)
		end
		keep.Refresh = function(self) self:GenerateMenu() end
		controls[#controls + 1] = keep
		stack:Add(keep, "dropdown")
		Tooltip(keep, KEEP_TIP)
		GreyUnless(keep, IfOn)
	end
	local screen = stack:Add(Check(content, "deathScreen", L["Darken the screen"],
		L["The world dims and goes cold until you release or come back."]), "check")
	screen:HookScript("OnClick", Refresh) -- grey out / enable the strength below
	GreyUnless(screen, IfOn)
	local screenStrength = stack:Add(Slider(content, "deathScreenStrength", L["Strength"], 10, 100, 5,
		"%d%%", 100), "slider")
	GreyUnless(screenStrength, function(db) return IfOn(db) and db.deathScreen end)
	local creep = stack:Add(Slider(content, "deathVignetteTime", L["Edges creep in over"], 1, 30, 1,
		L["%d sec"]), "slider")
	Tooltip(creep, L["How long the dark edges take to close in after you die."])
	GreyUnless(creep, function(db) return IfOn(db) and db.deathScreen end)
	local reach = stack:Add(Slider(content, "deathVignetteSize", L["Edges reach in"], 15, 50, 5,
		"%d%%", 100), "slider")
	Tooltip(reach, L["How far the dark edges reach in from each side of the screen."])
	GreyUnless(reach, function(db) return IfOn(db) and db.deathScreen end)
	local corpseRun = stack:Add(Check(content, "deathCorpseRun", L["Edges lift as you near your body"],
		L["The dark edges lift as you walk back to your body."]), "check")
	GreyUnless(corpseRun, function(db) return IfOn(db) and db.deathScreen end)

	stack:Header(content, L["Music"])
	local songBox = ns.SkinEditBox(CreateFrame("EditBox", nil, content, "InputBoxTemplate"))
	songBox:SetSize(260, 20)
	songBox:SetAutoFocus(false)
	stack:Add(songBox, "box")
	RecordKey(content, "deathSongFiles")
	local function SaveSong(self) ns.GetDB().deathSongFiles = self:GetText() end
	songBox:SetScript("OnEnterPressed", function(self) SaveSong(self) self:ClearFocus() end)
	songBox:SetScript("OnEditFocusLost", SaveSong)
	songBox:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.GetDB().deathSongFiles or "")
		self:ClearFocus()
	end)
	songBox.Refresh = function(self)
		local db = ns.GetDB()
		if not self:HasFocus() then self:SetText(db.deathSongFiles or "") end
		self:SetEnabled(IfOn() and ns.TriggerAnyRow("Death", "music"))
	end
	controls[#controls + 1] = songBox
	Tooltip(songBox, L["Music file IDs, separated by commas; one plays at random when you die."])
	stack:Note(content, L["Music file IDs, separated by commas. One is picked at random while the " ..
		"Die row's Music is ticked on the Scenes page."], 280)
end

-- Chat Cam (ChatCam.lua), started by NPCs talking; laid
-- out as the Quest Cam's below.
local function CreateChatCamPanel()
	local content, top, title = CameraSection(L["Chat Cam"], "Chat Cam")
	local subtitle = PageIntro(content, title, L["The camera turns toward NPCs as they talk near you."], top)
	-- (On or off: its two rows' cameras, on the Cameras page.)
	local function IfOn() return ns.TriggerAnyRow("Chat") or ns.TriggerAnyRow("ChatNearby") end

	local stack = Stack(subtitle, "label", true)
	stack:Header(content, L["Rotation"])
	local speed = stack:Add(Slider(content, "chatCamSwingSpeed", L["Swing speed"], 5, 40, 1, L["%d°/sec"]), "slider")
	Tooltip(speed, L["The fastest the camera swings toward a new speaker."])
	GreyUnless(speed, IfOn)
	local frame = stack:Add(Slider(content, "chatCamFrame", L["Leave the speaker off center"], 0, 20, 1, "%d°"), "slider")
	Tooltip(frame, L["How far from the screen's center the speaker ends up."])
	GreyUnless(frame, IfOn)
	local drift = stack:Add(Slider(content, "chatCamDrift", L["Drift"], 0, 10, 1, "%d°"), "slider")
	Tooltip(drift, L["How far the camera drifts side to side once settled."])
	GreyUnless(drift, IfOn)
	local search = stack:Add(Check(content, "chatCamSearch", L["Look around for speakers off screen"],
		L["The camera turns around to find speakers you can't see."]), "check")
	GreyUnless(search, IfOn)
	local immersive = stack:Add(Check(content, "chatCamImmersive", L["Ultra immersive"],
		L["Snaps to speakers, adds a tall letterbox with subtitles and fades the whole UI."]), "check")
	GreyUnless(immersive, IfOn)

	stack:Header(content, L["Zoom"])
	local distance = stack:Add(Slider(content, "chatCamDistance", L["Zoom in to about"], 1.5, 10, 0.5, L["%.1f yards"]), "slider")
	Tooltip(distance, L["The camera zooms in to this distance if you're further out."])
	GreyUnless(distance, IfOn)
	local zoomSpeed = stack:Add(Slider(content, "chatCamZoomSpeed", L["Zoom in speed"], 0.25, 10, 0.25, L["%.2f yards/sec"]), "slider")
	Tooltip(zoomSpeed, L["The first swing waits for the zoom in to finish."])
	GreyUnless(zoomSpeed, IfOn)
	local zoomOutSpeed = stack:Add(Slider(content, "chatCamZoomOutSpeed", L["Zoom back out speed"], 0, 10, 0.25, L["%.2f yards/sec"]), "slider")
	Tooltip(zoomOutSpeed, L["How fast the camera zooms back out once the talking is over."])
	GreyUnless(zoomOutSpeed, IfOn)
	local zoomMax = stack:Add(Slider(content, "chatCamZoomMaxTime", L["Zoom takes at most"], 2, 30, 1, L["%d sec"]), "slider")
	Tooltip(zoomMax, L["The longest a zoom in or out can take."])
	GreyUnless(zoomMax, IfOn)

	stack:Header(content, L["Ending"])
	local quiet = stack:Add(Slider(content, "chatCamQuiet", L["Over after no one talks for"], 3, 30, 1, L["%d sec"]), "slider")
	Tooltip(quiet, L["How long no one must talk before the camera turns back."])
	GreyUnless(quiet, IfOn)
end

-- Not a CreateCameraModePanel page either (QuestCam.lua, started by the quest
-- giver event), but laid out the same way.
local QUEST_SIDES = {
	{ value = "click", text = L["Where you clicked them"] },
	{ value = "random", text = L["Either side, at random"] },
	{ value = "right", text = L["Your right"] },
	{ value = "left", text = L["Your left"] },
}
local function CreateQuestPanel()
	local content, top, title = CameraSection(L["Quest Cam"], "Quest Cam")
	local subtitle = PageIntro(content, title, L["When you talk to a quest giver, the camera zooms in and looks past you at them."], top)
	-- (On or off, and the wait before starting: its two rows', on the Cameras page.)
	local function IfOn() return ns.TriggerAnyRow("Quest") or ns.TriggerAnyRow("QuestGossip") end

	local stack = Stack(subtitle, "label", true)
	stack:Header(content, L["Starting"])
	local gossip = stack:Add(Check(content, "questCamAllGossip", L["Every NPC you talk to"],
		L["Also zooms in for NPCs with nothing to say about quests."]), "check")
	GreyUnless(gossip, function() return ns.TriggerAnyRow("Quest") end)
	local mounted = stack:Add(Check(content, "questCamNotMounted", L["Not while mounted"],
		L["Talking to a quest giver from your mount, the camera stays as it is."]), "check")
	GreyUnless(mounted, IfOn)
	local daily = stack:Add(Check(content, "questCamNotDaily", L["Not for dailies"],
		L["The camera stays put when a quest giver only has dailies or weeklies."]), "check")
	GreyUnless(daily, IfOn)

	stack:Header(content, L["Rotation"])
	local angle = stack:Add(Slider(content, "questCamAngle", L["Come round to the side"], 0, 90, 5, "%d°"), "slider")
	Tooltip(angle, L["How far the camera turns to one side to look past you."])
	GreyUnless(angle, IfOn)
	local turnTime = stack:Add(Slider(content, "questCamTurnTime", L["Turn to the side takes"], 1, 8, 0.5, L["%.1f sec"]), "slider")
	Tooltip(turnTime, L["How long the turn to the side takes."])
	GreyUnless(turnTime, IfOn)
	local SIDE_TIP = L["Which side of you the camera comes round to."]
	local side = Dropdown(content, "questCamSide", QUEST_SIDES, 180)
	if side then
		side.inlineName = L["Side"]
		stack:Add(side, "dropdown")
		Tooltip(side, SIDE_TIP)
		GreyUnless(side, IfOn)
	else
		stack:Add(Label(content, "GameFontHighlight", L["Side"]), "label")
		for _, choice in ipairs(QUEST_SIDES) do
			local check = stack:Add(Choice(content, "questCamSide", choice.value, choice.text, SIDE_TIP), "check")
			GreyUnless(check, IfOn)
		end
	end
	local drift = stack:Add(Slider(content, "questCamDrift", L["Drift"], 0, 10, 1, "%d°"), "slider")
	Tooltip(drift, L["How far the camera drifts side to side once settled."])
	GreyUnless(drift, IfOn)

	stack:Header(content, L["Zoom"])
	local distance = stack:Add(Slider(content, "questCamDistance", L["Zoom in to about"], 1.5, 10, 0.5, L["%.1f yards"]), "slider")
	Tooltip(distance, L["The camera zooms in to this distance if you're further out."])
	GreyUnless(distance, IfOn)
	local zoomSpeed = stack:Add(Slider(content, "questCamZoomSpeed", L["Zoom in speed"], 0.25, 10, 0.25, L["%.2f yards/sec"]), "slider")
	Tooltip(zoomSpeed, L["The turn to the side happens along the way, then the tilt down."])
	GreyUnless(zoomSpeed, IfOn)
	local zoomOutSpeed = stack:Add(Slider(content, "questCamZoomOutSpeed", L["Zoom back out speed"], 0, 10, 0.25, L["%.2f yards/sec"]), "slider")
	Tooltip(zoomOutSpeed, L["How fast the camera zooms back out once you walk away."])
	GreyUnless(zoomOutSpeed, IfOn)
	local zoomMax = stack:Add(Slider(content, "questCamZoomMaxTime", L["Zoom takes at most"], 2, 30, 1, L["%d sec"]), "slider")
	Tooltip(zoomMax, L["The longest a zoom in or out can take."])
	GreyUnless(zoomMax, IfOn)

	stack:Header(content, L["Height"])
	local lower = stack:Add(Slider(content, "questCamLower", L["Lower the camera"], 0, 45, 5, "%d°"), "slider")
	Tooltip(lower, L["How far the camera comes down toward eye level."])
	GreyUnless(lower, IfOn)
end

local function CreateTelePanel()
	local content, sectionTop, title = CameraSection(L["Tele Cam"], "Tele Cam")
	local subtitle = PageIntro(content, title, L["When you cast your Hearthstone or a teleport, the camera spins around you as it zooms in."], sectionTop)
	-- (On or off: the Hearthstone and teleport rows' cameras, on the Cameras page.)
	local function IfOn() return ns.TriggerAnyRow("Hearth") or ns.TriggerAnyRow("Teleport") end

	local stack = Stack(subtitle, "label", true)

	stack:Header(content, L["Rotation"])
	local accel = stack:Add(Slider(content, "teleSpinAccel", L["Then speeds up by"], 0, 30, 1,
		L["%d° per sec, each sec"]), "slider")
	Tooltip(accel, L["How fast the spin speeds up once half round."])
	GreyUnless(accel, IfOn)
	local top = stack:Add(Slider(content, "teleSpinMax", L["Top speed"], 30, 360, 10, L["%d° per sec"]), "slider")
	Tooltip(top, L["The spin never goes faster than this."])
	GreyUnless(top, IfOn)
	local level = stack:Add(Slider(content, "teleLevel", L["Bring the camera down"], -30, 80, 5, "%d°"), "slider")
	Tooltip(level, L["As it turns round, the camera also comes down toward the ground (negative: up)."])
	GreyUnless(level, IfOn)

	stack:Header(content, L["Zoom"])
	local zoom = stack:Add(Check(content, "teleZoom", L["Zoom in over the cast"],
		L["The camera starts zooming in as the cast starts, and is still coming in as you go."]), "check")
	zoom:HookScript("OnClick", Refresh)
	GreyUnless(zoom, IfOn)
	local function IfZoom(db) return IfOn(db) and db.teleZoom end
	local close = stack:Add(Slider(content, "teleZoomClose", L["Zoom in to about"], 1.5, 20, 0.5, L["%.1f yards"]), "slider")
	Tooltip(close, L["The distance the zoom ends at as the cast finishes."])
	GreyUnless(close, IfZoom)
	local zoomBack = stack:Add(Slider(content, "teleZoomBackTime", L["If you cancel, zoom back out in"],
		0.5, 3, 0.25, L["%.2f sec"]), "slider")
	Tooltip(zoomBack, L["Canceling the cast, the camera zooms back out to your own distance this quickly."])
	GreyUnless(zoomBack, IfZoom)

	stack:Header(content, L["Canceling"])
	local back = stack:Add(Check(content, "teleReturn", L["Turn back if you cancel"],
		L["If you cancel the cast, the camera turns back to where it was."]), "check")
	GreyUnless(back, IfOn)
end

-- The Camera Settings page, with a section for each camera.
local function CreateCameraSettingsPanel()
	local canvas, content = CreateScrollPage(true) -- (each section has its own Reset)
	cameraSettingsContent = content
	local title = Label(content, "GameFontNormalLarge", L["Camera Settings"])
	title:SetPoint("TOPLEFT", 16, -16)
	local subtitle = PageIntro(content, title, L["Extra settings for cameras that aren't on the Scripts page yet."])
	cameraSettingsTop = subtitle
	subtitle.title = title
	-- (Greyed with the camera modes' switch, which is on the Cameras page.)
	RegisterPageSwitch(content, "cameraModes")

	CreateFlightPanel()
	CreateStandingPanel()
	CreateCozyPanel()
	CreateTelePanel()
	CreateVistaPanel()
	CreateFishPanel()
	CreateWalkPanel()
	CreateAutoRunPanel()
	CreateDeathPanel()
	CreateQuestPanel()
	if ns.ChatCamCommand then -- (ChatCam.lua)
		CreateChatCamPanel()
	end
	-- Mouse Turn (MouseTurn.lua: dev copy only): a cap on right-click turning.
	if ns.mouseTurnState then
		local content, top, title = CameraSection(L["Mouse Turn"], "Mouse Turn")
		local subtitle = PageIntro(content, title, L["Keeps right-mouse turning smooth by capping and easing its speed."], top)
		local function IfOn(db) return db.mouseTurnCap end

		local stack = Stack(subtitle, "label", true)
		stack:Header(content, L["Cap"])
		local on = stack:Add(Check(content, "mouseTurnCap", L["Cap right-click turn speed"],
			L["Right-click turning never goes faster than the speed below."]),
			"check")
		on:HookScript("OnClick", Refresh)
		local speed = stack:Add(Slider(content, "mouseTurnCapSpeed", L["Top turn speed"], 30, 720, 10,
			L["%d° per sec"]), "slider")
		Tooltip(speed, L["The fastest you can turn."])
		GreyUnless(speed, IfOn)
		local ease = stack:Add(Slider(content, "mouseTurnCapEase", L["Ease back over"], 0.05, 1.5, 0.05,
			L["%.2f sec"]), "slider")
		Tooltip(ease, L["How long your own Mouse Look Speed takes to come back after you slow down."])
		GreyUnless(ease, IfOn)

		stack:Header(content, L["Ramp up"])
		local ramp = stack:Add(Check(content, "mouseTurnRamp", L["Ramp up right-click turn speed"],
			L["Each right-click turn starts slow and builds up to your own speed."]), "check")
		ramp:HookScript("OnClick", Refresh)
		local function IfRamp(db) return db.mouseTurnRamp end
		local rampStart = stack:Add(Slider(content, "mouseTurnRampStart", L["Start at"], 5, 100, 5,
			L["%d%% of your speed"]), "slider")
		Tooltip(rampStart, L["How fast a turn starts, as a share of your own Mouse Look Speed."])
		GreyUnless(rampStart, IfRamp)
		local rampTime = stack:Add(Slider(content, "mouseTurnRampTime", L["Up to full speed over"], 0.1, 2, 0.05,
			L["%.2f sec"]), "slider")
		Tooltip(rampTime, L["How long a turn takes to build up to full speed."])
		GreyUnless(rampTime, IfRamp)

		stack:Header(content, L["Both"])
		local pitch = stack:Add(Check(content, "mouseTurnCapPitch", L["Slow looking up and down too"],
			L["Looking up and down slows by the same share as turning."]), "check")
		GreyUnless(pitch, function(db) return db.mouseTurnCap or db.mouseTurnRamp end)
	end

	-- A folder tab for each camera (those with settings left: see
	-- LayoutCameraSections), the picked one's section on the panel under them.
	local tabList = {}
	for i, section in ipairs(cameraSections) do tabList[i] = { section.name } end
	local panel, buttons, Show, base, height = ns.FolderTabs(content, tabList, function(i)
		SectionState.Save(cameraTabPicked, cameraSections[i].key)
		RelayoutCameraSections()
	end) -- (one row: only the cameras with settings left show)
	panel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -8, -(height + 16))
	panel:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	base:SetPoint("TOPLEFT", panel, "TOPLEFT")
	local empty = Label(content, "GameFontHighlight", L["Every camera's settings are on the Scripts page now."])
	empty:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
	cameraSections.tabs = { panel = panel, buttons = buttons, Show = Show, empty = empty }

	canvas:SetScript("OnShow", function()
		Refresh()
		RelayoutCameraSections()
	end)
	canvas:Hide()
	-- In the Camera hub, an icon per camera, each showing just that camera.
	local ICONS = {
		-- (a gryphon for the Alliance, a bat otherwise)
		["Flight Cam"] = function()
			return UnitFactionGroup("player") == "Alliance" and "Interface\\Icons\\Ability_Mount_Gryphon_01"
				or "Interface\\Icons\\Ability_Hunter_Pet_Bat"
		end,
		["AFK Cam"] = "Interface\\Icons\\Spell_Nature_Sleep",
		["Cozy Cam"] = "Interface\\Icons\\Spell_Fire_Fire",
		["Tele Cam"] = "Interface\\Icons\\Spell_Arcane_TeleportStormWind",
		["Vista Cam"] = "Interface\\Icons\\Ability_Hunter_EagleEye",
		["Fish Cam"] = "Interface\\Icons\\Trade_Fishing",
		["RP Walk Cam"] = "Interface\\Icons\\INV_Boots_01",
		["Auto-run Cam"] = "Interface\\Icons\\Ability_Rogue_Sprint",
		["Death Cam"] = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
		["Quest Cam"] = "Interface\\Icons\\INV_Misc_Book_08",
		["Chat Cam"] = "Interface\\Icons\\Ability_Warrior_BattleShout",
	}
	-- (and its group in the hub's row: at rest, travel, then moments)
	local GROUPS = {
		["AFK Cam"] = "At rest", ["Cozy Cam"] = "At rest", ["Vista Cam"] = "At rest", ["Fish Cam"] = "At rest",
		["Flight Cam"] = "Travel", ["Tele Cam"] = "Travel", ["Auto-run Cam"] = "Travel", ["RP Walk Cam"] = "Travel",
		["Quest Cam"] = "Moments", ["Chat Cam"] = "Moments",["Death Cam"] = "Moments",
	}
	local GROUP_ORDER = { ["At rest"] = 1, Travel = 2, Moments = 3 }
	-- (No icon per camera where there are scripts: each camera's settings
	-- are on its Scripts page; what's left here, settings no step uses, is
	-- on this page's one icon (dev copy only), a section for each camera.)
	if not ns.CameraSectionMoved then canvas.hubTabs = {} end
	for index, section in ipairs(canvas.hubTabs and cameraSections or {}) do
		local english = section.name
		for key in pairs(ICONS) do
			if section.name == L[key] then english = key end
		end
		canvas.hubTabs[#canvas.hubTabs + 1] = {
			name = english, icon = ICONS[english], resetContent = section.body,
			section = GROUPS[english], index = index,
			onSelect = function()
				cameraSections.focus = section
				canvas.scroll:SetVerticalScroll(0)
				RelayoutCameraSections()
			end,
			setSelect = function(select) section.selectTab = select end,
		}
	end
	table.sort(canvas.hubTabs or {}, function(a, b)
		local groupA, groupB = GROUP_ORDER[a.section] or 4, GROUP_ORDER[b.section] or 4
		if groupA ~= groupB then return groupA < groupB end
		return a.index < b.index
	end)
	-- (Dev copy only: every camera's settings are on its Scripts page, which
	-- makes its controls again from the ones here, so the page is still
	-- built for players, just not shown or searched.)
	if ns.isDev then RegisterSubpage(canvas, "Camera Settings") end
end

-- Blizzard's colour picker; the setup API changed in newer clients.
-- Also used by the minimap button's menu (ns.OpenColorPicker).
local function OpenColorPicker(r, g, b, onChange)
	local function apply()
		onChange(ColorPickerFrame:GetColorRGB())
	end
	local function cancel(previous)
		onChange(previous.r or previous[1], previous.g or previous[2], previous.b or previous[3])
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, hasOpacity = false, swatchFunc = apply, cancelFunc = cancel,
		})
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.previousValues = { r, g, b }
		ColorPickerFrame.func = apply
		ColorPickerFrame.cancelFunc = cancel
		ColorPickerFrame:SetColorRGB(r, g, b)
		ColorPickerFrame:Show()
	end
end
ns.OpenColorPicker = OpenColorPicker

-- Sub-page: the visual effects' General tab (the Atmosphere hub's first):
-- the master switch, the Turn off in grid, the letterbox, vignette, inns,
-- weather and depth of field.
-- The master switch, on both tabs: off, none of the effects show (each keeps
-- its own setting), and the tab's other controls grey out.
local function VisualEffectsSwitch(content, anchor)
	local master = Check(content, "visualEffects", L["Enable Visual Effects"],
		L["Turns the whole Atmosphere hub on or off at once."], function(value)
			ns.GetDB().visualEffects = value
			ns.letterboxDirty = true
			if ns.RefreshTint then ns.RefreshTint() end
			if ns.ApplyGraphicsPlus then ns.ApplyGraphicsPlus() end
			Refresh()
		end)
	master:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -2, -14)
	RegisterPageSwitch(content, "visualEffects", master)
	return master
end

local function CreateEffectsPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Visual Effects"])
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title,
		L["How the game world looks in CineMode: vignette, inn glow, weather and depth of field."])

	local master = VisualEffectsSwitch(content, subtitle)

	-- Show in: a row each for the vignette and weather, as the Standard
	-- Frames page's (GridRows.lua): where and when each shows. A row off
	-- everywhere switches its effect off (its own switch follows). (The
	-- letterbox's and tint's rows: their own pages, LetterboxStyle.lua.)
	local gridHeader = Header(content, L["Show in"], master, -18)
	gridHeader:SetPoint("TOPLEFT", master, "BOTTOMLEFT", 2, -18)
	PageIntro(content, gridHeader,
		L["Pick where and when each effect shows in CineMode."])
	local EFFECT_LABELS = { vignette = L["Vignette"], weather = L["Weather"] }
	-- (No CineMode column: the effects only show in CineMode, so Always says it all.)
	local effectRows = { opts = { quiet = true, cam = true, anyFight = true }, underHeader = true }
	for _, effect in ipairs(ns.EFFECT_GRID) do
		if EFFECT_LABELS[effect] then
			local key, alwaysKey = "effect:" .. effect, effect .. "Always"
			effectRows[#effectRows + 1] = { key = key, label = EFFECT_LABELS[effect], alwaysKey = alwaysKey,
				alwaysOn = function() return ns.GetDB()[alwaysKey] end,
				setAlways = function(value) ns.GetDB()[alwaysKey] = value end,
				alwaysTip = L["Shows all the time in CineMode, fights included."],
				apply = function()
					local switch = ns.EFFECT_SWITCHES[effect]
					if switch then ns.GetDB()[switch] = ns.RowOnAnywhere(key, ns.GetDB()[alwaysKey]) end
					if ns.RefreshTint then ns.RefreshTint() end
				end }
		end
	end
	local lastGridRow = ns.ShowTable(content, gridHeader, effectRows, L["Visual Effects"])

	-- The vignette, inn glow and weather: each slider on one line with its
	-- name, as on Graphics+, the sliders lined up past the longest name and
	-- each one's value to its right. All the way left is Off. (The vignette
	-- and weather are switched on and off in the grid's Always column.)
	local inlineRows = {}
	local function InlineSlider(anchor, gap, key, label, maxV, step, onChange)
		local name = Label(content, "GameFontHighlight", label)
		name:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
		name.searchSkip = true
		local slider = Slider(content, key, "", 0, maxV, step, function(value)
			return value == 0 and L["Off"] or ("%d%%"):format(value)
		end, 100, onChange)
		slider:SetWidth(130)
		slider.title:ClearAllPoints()
		slider.title:SetPoint("LEFT", slider, "RIGHT", 10, 0)
		slider.searchLabel = label
		slider.searchEdges = { top = slider, bottom = slider, left = name, right = slider.title }
		slider.rowName = name
		inlineRows[#inlineRows + 1] = slider
		return slider
	end
	-- (Greyed with its name.)
	local function GreyRow(slider, test)
		GreyUnless(slider, test)
		local refresh = slider.Refresh
		slider.Refresh = function(self)
			refresh(self)
			SetLabelFont(self.rowName, test(ns.GetDB()) and "GameFontHighlight" or "GameFontDisable")
		end
	end

	-- Vignette
	local vignetteStrength = InlineSlider(lastGridRow, 24, "vignetteStrength", L["Vignette strength"], 100, 5,
		ns.RefreshTint)
	Tooltip(vignetteStrength, L["Soft dark edges that draw the eye to the middle."])
	GreyRow(vignetteStrength, function(db) return db.vignette end)

	-- Inns: Off is the inn glow switched off (its amount kept for next time).
	local innGlowStrength = InlineSlider(vignetteStrength.rowName, 18, {
		key = "innGlowAmount",
		get = function()
			local db = ns.GetDB()
			return db.innGlow and db.innGlowAmount or 0
		end,
		set = function(value)
			local db = ns.GetDB()
			db.innGlow = value > 0
			if value > 0 then db.innGlowAmount = value end
		end,
	}, L["Inn glow amount"], 100, 1, ns.RefreshTint)
	RecordKey(content, "innGlow") -- (for Reset page)
	RecordKey(content, "innGlowAmount")
	Tooltip(innGlowStrength, L["Indoors in an inn, a soft firelit glow replaces the outdoor tint."] .. " " ..
		L["How much light the glow adds at its brightest, low on the screen."])

	-- Weather
	local weatherTintStrength = InlineSlider(innGlowStrength.rowName, 18, "weatherTintStrength", L["Weather strength"], 100, 5,
		ns.RefreshTint)
	Tooltip(weatherTintStrength, L["Rain, snow and sandstorms tint the scene, more strongly in heavier weather."])
	GreyRow(weatherTintStrength, function(db) return db.weatherTint end)

	-- View distance in bad weather (Graphics.lua): only where the game says the
	-- weather and has the view distance setting.
	local lastRow = weatherTintStrength
	if C_Weather and C_Weather.GetCurrentWeather and GetCVar("horizonStart") ~= nil then
		lastRow = InlineSlider(weatherTintStrength.rowName, 18, "rainViewScale", L["Reduce view distance in bad weather"], 100, 5)
		Tooltip(lastRow, L["Brings the view distance in during rain, snow or sandstorms, more the heavier it gets."])
	end

	-- Camera haze (depth of field): each camera mode's page sets its own
	-- strength, this scales them all. Off is the haze switched off (the
	-- scale kept for next time).
	local cameraHaze = InlineSlider(lastRow.rowName, 18, {
		key = "dofScale",
		get = function()
			local db = ns.GetDB()
			return db.depthOfField and (db.dofScale or 1) or 0
		end,
		set = function(value)
			local db = ns.GetDB()
			db.depthOfField = value > 0
			if value > 0 then db.dofScale = value end
		end,
	}, L["Camera haze"], 200, 5)
	RecordKey(content, "depthOfField") -- (for Reset page)
	RecordKey(content, "dofScale")
	Tooltip(cameraHaze, L["A soft haze around the screen edges in the camera modes."])

	local nameWidth = 0
	for _, slider in ipairs(inlineRows) do
		nameWidth = math.max(nameWidth, slider.rowName:GetStringWidth())
	end
	for _, slider in ipairs(inlineRows) do
		slider:SetPoint("LEFT", slider.rowName, "LEFT", nameWidth + 20, 0)
	end

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	-- (Its own name, not "General": Quality of life has a General page. Shown as
	-- Visual Effects in search, and General on its icon.)
	RegisterSubpage(canvas, "Effects", L["Visual Effects"])
end

-- (The Tint tab's Style page: TintStyle.lua.)

-- Sub-page: Graphics+, the game's graphics settings past its menu's most
-- (Graphics.lua). Each slider only on clients that have its setting.
local function CreateGraphicsPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Graphics Boost"])
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title,
		L["The game's graphics settings one by one, shared by every profile on this computer."] .. "\n\n" ..
		L["A slider changes nothing until you move it. Higher (in gold) costs frame rate, lower " ..
		"(in blue) saves it. Tick and untick a setting to compare it with the game's own; Reset page leaves them " ..
		"all alone again."] .. "\n\n" ..
		L["Ground clutter changes show as the ground around you loads again: move on a " ..
		"little, or /reload. Changing the game's Graphics menu doesn't undo these: they're written again " ..
		"over its new settings."])

	local function Changed() ns.ApplyGraphicsPlus() end
	local switch = PageSwitch(content, "graphicsPlus", L["Enable Page"],
		L["Uses the settings below, or the game's own when turned off."],
		subtitle, Changed)
	local stack = Stack(switch, "check")

	local LABELS = {
		graphicsPlusClutter = { L["Ground clutter density"], L["How thickly grass, flowers and stones grow " ..
			"on the ground."] },
		graphicsPlusClutterDistance = { L["Ground clutter distance"], L["How far away grass and flowers still " ..
			"show."] },
		graphicsPlusClutterFade = { L["Ground clutter fade"], L["How far away grass and flowers start thinning out."] },
		graphicsPlusView = { L["View distance"], L["How far the land is drawn in full; very demanding on frame rate."] },
		graphicsPlusTerrain = { L["Terrain detail distance"], L["How far away the land keeps its full shape " ..
			"before it turns low detail."] },
		graphicsPlusBuildings = { L["Building detail distance"], L["How far away buildings keep their full " ..
			"detail."] },
		graphicsPlusObjects = { L["Object detail distance"], L["How far away trees, rocks and other objects keep their full detail."] },
		graphicsPlusObjectFade = { L["Object fade distance"], L["How far away small objects stay before they fade out."] },
		graphicsPlusCreatures = { L["Creature detail distance"], L["How far away creatures and characters keep their full detail."] },
		graphicsPlusPlateDistance = { L["Nameplate distance"], L["How far away nameplates show, in yards."] },
		graphicsPlusZoomMax = { L["Max zoom distance"], L["How far out you can zoom the camera."] },
		graphicsPlusShadows = { L["Shadow sharpness"], L["Higher gives sharper shadow edges, lower saves frame rate."] },
	}
	-- (The groups' names, for the translations: see setting.group in Graphics.lua.)
	local GROUPS = {
		["Camera and nameplates"] = L["Camera and nameplates"],
		["Ground clutter"] = L["Ground clutter"],
		["Land and buildings"] = L["Land and buildings"],
		["Objects and creatures"] = L["Objects and creatures"],
		["Shadows"] = L["Shadows"],
	}
	local any = false
	local group
	-- Each setting's tick and slider share a row: the sliders lined up past
	-- the longest label on the page, each one's value to its right. A header
	-- over each group (none for a group this game version has none of).
	local rows = {}
	for _, setting in ipairs(ns.GRAPHICS_PLUS) do
		if ns.GraphicsPlusExists(setting.cvar) then
			any = true
			if setting.group ~= group then
				group = setting.group
				stack:Header(content, GROUPS[group])
			end
			local text = LABELS[setting.key]
			local tip = text[2]
			-- (The game's name for the setting beside it, in grey, as typed after /console.)
			local names = setting.cvar
			for _, cvar in ipairs(setting.also or {}) do
				names = names .. ", " .. cvar
			end
			local check = stack:Add(Check(content, setting.key .. "On", text[1] .. " |cff9d9d9d(" .. names .. ")|r",
				tip, function(value)
				ns.GetDB()[setting.key .. "On"] = value
				Changed()
				Refresh() -- grey out / enable its slider
			end), "check")
			-- Unmoved (nil), the slider shows the game's own value and changes
			-- nothing. A setting with a few values (shadows) slides over their
			-- places in the list.
			local values = setting.values
			local function Own()
				return tonumber(ns.GraphicsPlusOwn(setting)) or setting.menu
			end
			local function Place(value)
				local best = 1
				for i, v in ipairs(values) do
					if math.abs(v - value) < math.abs(values[best] - value) then best = i end
				end
				return best
			end
			local access = {
				get = function()
					local value = ns.GetDB()[setting.key] or Own()
					return values and Place(value) or value
				end,
				set = function(value) ns.GetDB()[setting.key] = values and values[value] or value end,
			}
			local slider
			slider = Slider(content, access, "", values and 1 or setting.min,
				values and #values or setting.max, values and 1 or setting.step,
				function(position)
					local value = values and values[position] or position
					local own = Own()
					local num = setting.decimals and ("%." .. setting.decimals .. "f") or "%d"
					if not setting.decimals then own = own + 0.5 end -- (%d rounds down)
					if ns.GetDB()[setting.key] == nil then
						return ("|cffffffff" .. num .. "|r  |cff9d9d9d"):format(value) .. L["(game's own)"]
					end
					-- (Lower than the game's own in blue: it saves frame rate.)
					return ((value < Own() and "|cff4fb3ff" or "") .. num .. "|r"):format(value) .. "  |cff9d9d9d" ..
						L["(game: %s)"]:format(num:format(own)) -- (short: longer ran off the page)
				end, nil, function()
					Changed()
					slider:Refresh() -- (its label: moved now, and against the game's own)
				end)
			slider:SetWidth(130)
			slider.title:ClearAllPoints()
			slider.title:SetPoint("LEFT", slider, "RIGHT", 10, 0)
			rows[#rows + 1] = { check = check, slider = slider }
			RecordKey(content, setting.key) -- (for Reset page: back to unmoved)
			Tooltip(slider, tip)
			GreyUnless(slider, function(db) return db[setting.key .. "On"] end)
		end
	end
	local labelWidth = 0
	for _, row in ipairs(rows) do
		local label = row.check.Text or row.check.text
		labelWidth = math.max(labelWidth, label and label:GetStringWidth() or 0)
	end
	for _, row in ipairs(rows) do
		row.slider:SetPoint("LEFT", row.check, "LEFT", 26 + labelWidth + 20, 0)
	end
	if not any then
		stack:Note(content, L["This game version has none of these settings."], 420)
	end
	-- (Reset page: those marked so go back to the game's default, before the rest are put back.)
	resetHooks[content] = ns.GraphicsPlusResetDefaults

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Graphics+", L["Graphics Boost"])
end

-- Sub-page for audio: music during cinematic mode.
local function CreateAudioPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Audio"])
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title,
		L["Sound and music during CineMode; your own sound settings come back afterward."])

	-- The page's switch: off, CineMode leaves music alone (nothing below applies).
	local music = PageSwitch(content, "musicInCinematic", L["Enable Page"],
		L["Plays music when a camera starts in CineMode and fades it out when the UI returns."], subtitle)

	-- One column, each slider on one line with its name (an inline stack, as on Graphics+).
	local stack = Stack(music, "check", true)

	-- First: where and when music plays, a row as the Standard Frames
	-- page's (GridRows.lua). Off: it fades out (your own game music too), back after.
	local playsHeader = stack:Header(content, L["Music plays in"])
	stack:Help(content,
		L["Pick where and when music can play in CineMode."])
	-- (underHeader: the column names level with the header, as on the Letterbox page.)
	local lastRow = ns.ShowTable(content, playsHeader, {
		opts = { quiet = true, cam = true, anyFight = true }, underHeader = true, {
		key = "music", label = L["Music"], alwaysKey = "musicAlways",
		alwaysOn = function() return ns.GetDB().musicAlways end,
		setAlways = function(value) ns.GetDB().musicAlways = value end,
		alwaysTip = L["Music can play all through CineMode. (The other columns then have nothing to add.)"],
	} }, L["Audio"])
	stack:Continue(lastRow, "label")

	stack:Header(content, L["Music"])
	local musicFade = stack:Add(Slider(content, "musicFadeTime", L["Music fade time"], 0.5, 10, 0.5,
		L["%.1f sec"]), "slider")
	Tooltip(musicFade, L["How long music takes to fade in or out with CineMode."])

	-- (Minutes, in half-minute steps.)
	local fatigue = stack:Add(Slider(content, "musicFatigue", L["Music fatigue"], 0, 30, 0.5, function(value)
		local minutes, seconds = math.floor(value), math.floor((value % 1) * 60 + 0.5)
		if minutes == 0 then
			return L["%d sec"]:format(seconds)
		elseif seconds == 0 then
			return L["%d min"]:format(minutes)
		end
		return L["%d min %d sec"]:format(minutes, seconds)
	end), "slider")
	Tooltip(fatigue, L["After a camera starts music, no camera starts it again for this long."])

	-- Stopping as you leave the camera modes.
	stack:Add(Check(content, "musicPauseWhenMoving", L["Stop music leaving a camera mode"],
		L["Fades music out once you leave the camera modes and move on."]), "check")

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Audio")
end

-- The frames tables (Standard Frames, Gamepad, Advanced Frames): the
-- name, then a column per situation ({ heading, isOn, list, needs "stay
-- cinematic in combat", tip }): Always, the fights and targets, then the
-- places (ns.PLACE_SHOW). Narrow columns, so all eight fit beside the
-- scrollbar: a heading of two words or more takes two lines, the last lines level.
-- With the dropdowns (ns.GRID_MENUS) the name has the old Roles column's room
-- too: longer names in full, and the section tabs in one row.
local FRAME_LABEL_WIDTH, FRAME_COLUMN_WIDTH, FRAME_HEADING_HEIGHT = ns.GRID_MENUS and 212 or 160, 52, 24
local FRAME_COLUMNS = {
	{ L["Always"], ns.IsCineShowOn, "cineShow", false },
	{ L["In combat"], ns.IsCombatShowOn, "combatShow", true },
	{ L["Tar enemy"], ns.IsEnemyShowOn, "enemyShow", false },
	{ L["Tar friendly"], ns.IsFriendlyShowOn, "friendlyShow", false },
}
for _, place in ipairs(ns.PLACE_SHOW) do
	FRAME_COLUMNS[#FRAME_COLUMNS + 1] = {
		place.label, function(key) return ns.IsPlaceShowOn(place.list, key) end, place.list, false, place.tip,
	}
end

ns.FRAME_COLUMNS = FRAME_COLUMNS -- (a Show in row's columns, for the pages outside this file)

local function FrameHeading(parent, text)
	local heading = Label(parent, "GameFontNormalSmall", (text:gsub("^(.*) ", "%1\n")))
	heading:SetSize(FRAME_COLUMN_WIDTH, FRAME_HEADING_HEIGHT)
	heading:SetJustifyH("CENTER")
	heading:SetJustifyV("BOTTOM")
	return heading
end

-- A row whose frame can be turned off altogether (item.showKey, a setting
-- on unless false): a box before its name, the name moved over for it.
-- Unticked, the row's other controls grey (RowShown).
local SHOW_BOX_ROOM = 20
local function RowShown(item)
	return not item.showKey or ns.GetDB()[item.showKey] ~= false
end
local function ShowBox(content, item, rowLabel)
	if not item.showKey then return end
	local box = Check(content, item.showKey, "", item.showTip, function(value)
		ns.GetDB()[item.showKey] = value
		if item.showChanged then item.showChanged() end
		Refresh()
	end)
	box:SetSize(22, 22)
	box.Refresh = function(self) self:SetChecked(RowShown(item)) end
	local point, relativeTo, relativePoint, x, y = rowLabel:GetPoint(1)
	rowLabel:SetPoint(point, relativeTo, relativePoint, x + SHOW_BOX_ROOM, y)
	rowLabel:SetWidth(rowLabel:GetWidth() - SHOW_BOX_ROOM)
	box:SetPoint("RIGHT", rowLabel, "LEFT", 0, 0)
end

-- The page helpers the dropdown grids share (GridRows.lua's ns.GridRow).
ns.GRID_KIT = { controls = controls, Label = Label, Tooltip = Tooltip,
	FrameHeading = FrameHeading, RecordKey = RecordKey, RecordRow = RecordRow,
	Refresh = Refresh, headingHeight = FRAME_HEADING_HEIGHT, ShowBox = ShowBox, RowShown = RowShown,
	Dropdown = Dropdown } -- (Dropdown: FrameLinks.lua's Addon Frame Links)

-- Sub-page: the cameras (CameraRows.lua). A row per trigger (an emote, a
-- campfire, going AFK, a flight, dying...) and the camera it starts, as the
-- Nameplates page's Marks grid: a line with chips for what's set apart from
-- the usual, its settings in a drawer under it (its name, its camera with
-- Music and CineMode, When it may start, and what its trigger needs: buffs,
-- seat words, a wait). A copy gives a trigger a second camera somewhere
-- else: a trigger's rows are tried top to bottom, the first whose When fits
-- picks the camera.
local function CreateCamerasPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["General"]) -- (the Camera hub's first page)
	title:SetPoint("TOPLEFT", 16, -16)
	local subtitle = PageIntro(content, title,
		L["In CineMode, the camera comes alive when things happen, like emotes, flights or going AFK."] .. "\n\n" ..
		L["In the camera modes, the minimap and quest tracker hover holds and the buff and chat " ..
		"peeks use their short default times, so they clear the view quickly."])
	local switch = CameraModesSwitch(content, subtitle)
	-- (Every camera as an icon, each opening a tab of its own: CameraManager.lua.)
	ns.CameraManager(ns.lowHealthKit, canvas, content, title, subtitle, switch)
	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Cameras")

	-- The Scenes page: the rows, a page of their own (the Camera hub's second).
	canvas, content = CreateScrollPage()
	local header = Label(content, "GameFontNormalLarge", L["Scenes"])
	header:SetPoint("TOPLEFT", 16, -16)
	local help = PageIntro(content, header,
		L["Each row is a scene that plays its camera when one of its triggers happens."])

	-- Each trigger's name and tip (the events' from ns.EVENTS and EVENT_TIPS).
	local LABELS = { Walk = L["Auto-walk (RP walk)"], Run = L["Auto-run"], Death = L["Die"],
		Chat = L["NPCs you talk to"], ChatNearby = L["NPCs chatting nearby"] }
	for _, event in ipairs(ns.EVENTS) do LABELS[event.key] = event.label end
	local TIPS = {
		Walk = L["Auto-running in walk mode."],
		Run = L["Auto-running."],
		Death = L["Dying, until you release or are resurrected."],
		Chat = L["An NPC talking to you or your party; the camera swings toward whoever's talking."],
		ChatNearby = L["Other NPCs talking near you, once you've stood still a while."],
	}
	local MUSIC_TIP = L["Starts music as this camera starts; needs the Audio page on."]
	local MUSIC_TIPS = {
		AFK = MUSIC_TIP,
		Still = MUSIC_TIP .. L[" Off also keeps music from coming back after a pause while you stand still."],
		Death = L["Plays a song of its own while the death camera runs."],
	}
	local CINE_TIP = L["Brings CineMode on while this camera runs, when Start in CineMode is off."]
	-- What each trigger needs besides (its own row's drawer only: the copies share it).
	local EXTRAS = {
		Campfire = { L["Buffs"], list = "cozyBuffs", tip = L["Buff names or spell IDs, separated by commas."] },
		Chair = { L["Seats"], list = "cozyChairWords", tip = L["Words in an object's name that mark it as a seat, separated by commas."] },
		Still = { L["Wait"], slider = { "idleOrbitDelay", L["After standing still for"], 5, 300, 5, L["%d sec"] },
			tip = L["How long you stand still before this row's camera starts."] },
		Quest = { L["Wait"], slider = { "questCamDelay", L["Wait before starting"], 0, 10, 0.5, L["%.1f sec"] },
			tip = L["How long the camera waits on a quest window before it starts."] },
		QuestGossip = { L["Wait"], slider = { "questCamGossipDelay", L["Wait before starting"], 0, 10, 0.5,
			L["%.1f sec"] }, tip = L["How long the camera waits on the window before it starts."] },
		Walk = { L["Wait"], slider = { "walkCameraDelay", L["After auto-walking for"], 0, 60, 1, L["%d sec"] } },
		Run = { L["Wait"], slider = { "runCameraDelay", L["After auto-running for"], 0, 60, 1, L["%d sec"] } },
		ChatNearby = { L["Wait"], slider = { "chatNearbyDelay", L["After standing still for"], 0, 60, 1,
			L["%d sec"] }, tip = L["How long you stand still before NPCs chatting nearby start this camera."] },
	}
	-- (Fade at once, beside CineMode on these rows: the trigger's own row's.)
	local INSTANT = { Flight = "taxiInstant", Walk = "walkInstant", Run = "runInstant" }
	local GO_TIP = L["How long you keep going before this row's camera starts."]
	-- (Short camera names, for the chips; their colors: back, then text.)
	local SHORT = { cozy = L["Cozy"], vista = L["Vista"], fish = L["Fish"], afk = L["AFK"], tele = L["Tele"],
		flight = L["Flight"], quest = L["Quest"], walk = L["RP Walk"], run = L["Auto-run"], [true] = L["Death"],
		chat = L["Chat"], death = L["Death"] }
	local CAM_CHIP = {
		cozy = { 0.29, 0.19, 0.03, 1, 0.77, 0.42 }, tele = { 0.18, 0.12, 0.29, 0.78, 0.66, 1 },
		afk = { 0.13, 0.19, 0.29, 0.66, 0.77, 1 }, vista = { 0.05, 0.23, 0.21, 0.5, 0.88, 0.83 },
		fish = { 0.05, 0.16, 0.27, 0.5, 0.75, 1 }, flight = { 0.09, 0.23, 0.29, 0.62, 0.88, 1 },
		quest = { 0.29, 0.24, 0.03, 1, 0.88, 0.4 }, walk = { 0.09, 0.23, 0.09, 0.62, 0.89, 0.62 },
		run = { 0.09, 0.23, 0.09, 0.62, 0.89, 0.62 }, [true] = { 0, 0, 0, 0.85, 0.85, 0.85 },
		death = { 0, 0, 0, 0.85, 0.85, 0.85 },
		chat = { 0.27, 0.09, 0.2, 1, 0.66, 0.85 } }
	local WHEN_CHIP = { 0.08, 0.2, 0.35, 0.55, 0.8, 1 }
	local NEVER_CHIP = { 0.35, 0.25, 0.05, 1, 0.8, 0.35 }
	local PLAIN_CHIP = { 0.18, 0.18, 0.18, 0.8, 0.8, 0.8 }
	local MINE_CHIP = { 0.18, 0.29, 0.11, 0.73, 0.89, 0.54 }
	local PLACE_NAMES = { world = L["Open world"], city = L["Cities"], instance = L["Instances"],
		bg = L["BGs & arenas"], group = L["Grouped"] }
	local PLACE_WORDS = { "world", "city", "instance", "bg" }
	local WHEN_LAYOUT = { groups = { ns.GRID_COMBAT, ns.GRID_LOCATION }, edit = true }
	local WHEN_HELP = { [ns.GRID_COMBAT] = L["Whether this row's camera may start in or after a fight."],
		[ns.GRID_LOCATION] = L["Where this row's camera may start."] }

	-- A row's line: its arrows, on/off tick, name and chips, then copy, open and remove;
	-- its drawer under it, a line each (Name, Camera, When, and what its
	-- trigger needs).
	local ROW_W, ROW_H, ON_X, NAME_X, NAME_W, CHIPS_X, CHIPS_W = 590, 28, 16, 46, 206, 256, 252
	local DRAWER_X, LINE_H, LABEL_W = 20, 34, 62
	-- Copies of a row (its copy button; false hides it again). Copies made
	-- show either way, with their arrows and remove button.
	local SHOW_COPY = true

	-- (The line above the rows: New trigger, Import and Sort by. The New
	-- trigger panel opens under it, the rows below that.)
	local bar = CreateFrame("Frame", nil, content)
	bar:SetSize(ROW_W, 26)
	do
		local windows = Check(content, "pauseCamsInWindows", L["Pause cameras while a window is open"],
			L["Scenes pause while a window like the map or spellbook is open."])
		windows:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -4)
		bar:SetPoint("TOPLEFT", windows, "BOTTOMLEFT", 0, -2)
	end
	local grid = CreateFrame("Frame", nil, content)
	grid:SetSize(ROW_W, ROW_H)
	grid:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
	local rows, drawers, opened = {}, {}, {}
	local MakeRow -- (below)
	local function Changed()
		ns.SyncAllSceneGroups() -- (a group's members follow its row)
		ns.CameraRowsChanged()
		Refresh()
	end
	local function WhenChanged()
		ns.SyncAllSceneGroups()
		ns.CameraRowsChanged()
	end
	local function Toggle(id)
		opened[id] = not opened[id]
		grid:Refresh()
	end
	-- (A trigger of your own: what starts it, "/cheer"; its name is the row's.)
	local function TriggerName(trigger)
		return trigger.custom and ns.DescribeTriggerSource(ns.SceneTriggers(trigger.key)[1]) or trigger.key
	end
	-- (A group's lead: the scene's name, CameraRows.lua's SCENE_GROUPS.)
	local function SceneName(trigger)
		local group = ns.SceneGroupOf(trigger.key)
		return group and group.name or LABELS[trigger.key] or TriggerName(trigger)
	end
	local function RowLabel(id)
		local trigger, copy = ns.CameraRowTrigger(id)
		return SceneName(trigger) .. (copy and " (" .. copy .. ")" or "")
	end
	-- (A built-in scene's own triggers' names: a group's members'.)
	-- A built-in scene's own triggers: a list of { key, name } (a line each on
	-- its page), or their names joined (less those taken off it).
	local function BuiltInList(key)
		local list = {}
		for _, member in ipairs(ns.SceneGroupMembers(key)) do
			list[#list + 1] = { key = member, name = LABELS[member] or member }
		end
		return list
	end
	local function BuiltInNames(key)
		local names = {}
		for _, each in ipairs(BuiltInList(key)) do
			if not ns.TriggerDropped(each.key) then names[#names + 1] = each.name end
		end
		return table.concat(names, ", ")
	end
	local function OwnName(id)
		local db = ns.GetDB()
		local own = db and db.cameraRows and db.cameraRows[id .. ".name"]
		return type(own) == "string" and own or ""
	end
	local function HasCamera(id)
		local trigger = ns.CameraRowTrigger(id)
		return ns.CameraRowValue(id, "camera") ~= trigger.off
	end
	-- (The rows a row's When may follow, by their keys: every row shown, your
	-- name for it first.)
	local function FollowChoices()
		local list = {}
		for _, id in ipairs(ns.CameraRowOrder()) do
			list[#list + 1] = { ns.CameraRowKey(id), OwnName(id) ~= "" and OwnName(id) or RowLabel(id) }
		end
		return list
	end
	local function FollowLabel(key)
		local id = tostring(key):match("^trig:(.+)$")
		if id and ns.CameraRowTrigger(id) then return OwnName(id) ~= "" and OwnName(id) or RowLabel(id) end
		return tostring(key)
	end

	-- What's set apart from the usual on a row, for its chips: { text, color }.
	local function RowChips(id, parts)
		local trigger, copy = ns.CameraRowTrigger(id)
		local db, key = ns.GetDB(), ns.CameraRowKey(id)
		local camera = ns.CameraRowValue(id, "camera")
		if camera == trigger.off then return { { L["No camera"], PLAIN_CHIP } } end
		-- (A shot: its name, in its camera's colors; a trigger of your own: Mine first.)
		local base = ns.ShotBase(camera)
		local list = { { base ~= camera and ns.CameraName(camera) or SHORT[camera] or ns.CameraName(camera) or tostring(camera),
			CAM_CHIP[base] or PLAIN_CHIP } }
		if trigger.custom then table.insert(list, 1, { L["Mine"], MINE_CHIP }) end
		-- (More than one trigger: how many, its own one counted for a built-in scene.)
		if not copy and ns.SceneTakesTriggers(trigger.key) then
			local count = #ns.SceneTriggers(trigger.key) + (trigger.custom and 0 or 1)
			if count > 1 then list[#list + 1] = { (L["%d triggers"]):format(count), PLAIN_CHIP } end
		end
		if trigger.music and ns.CameraRowValue(id, "music") then list[#list + 1] = { L["Music"], PLAIN_CHIP } end
		if trigger.cine and ns.CameraRowValue(id, "cine") then list[#list + 1] = { "CineMode", PLAIN_CHIP } end
		for _, member in ipairs(copy and { trigger.key } or ns.SceneGroupMembers(trigger.key)) do
			local extra = EXTRAS[member]
			local delay = extra and extra.slider and db[extra.slider[1]]
			if delay and delay > 0 and member ~= "Still" then
				list[#list + 1] = { (L["Wait %s sec"]):format(delay), PLAIN_CHIP }
			end
			if not copy and member == "Still" then
				list[#list + 1] = { (L["%d sec"]):format(db.idleOrbitDelay or 0), PLAIN_CHIP }
			end
		end
		-- (Following a row: just that, its When being that row's.)
		local leader = db.rowFollow and db.rowFollow[key]
		if leader then
			list[#list + 1] = { (L["Follows %s"]):format(FollowLabel(leader)), WHEN_CHIP }
			return list
		end
		if trigger.key ~= "Death" and not ns.CameraRowAlways(id) and ns.IsCombatShowOn(key) then
			list[#list + 1] = { L["In combat"], WHEN_CHIP }
		end
		if ns.CameraRowCalm(id) then list[#list + 1] = { L["Calm Timer"], WHEN_CHIP } end
		local rule = db.frameRules and db.frameRules[key]
		if type(rule) == "string" and rule:find("%S") then
			list[#list + 1] = { rule, WHEN_CHIP }
		elseif not ns.CameraRowAlways(id) and parts then
			local ticked, missing, all = {}, {}, 0
			for _, word in ipairs(parts.words()) do ticked[word] = true end
			for _, word in ipairs(PLACE_WORDS) do
				if parts.grid[word] then
					all = all + 1
					if not ticked[word] then missing[#missing + 1] = PLACE_NAMES[word] end
				end
			end
			if #missing == 0 then
				-- (Everywhere: nothing set apart.)
			elseif #missing == 1 and #missing < all then
				list[#list + 1] = { (L["Not in %s"]):format(missing[1]), WHEN_CHIP }
			else
				local names = {}
				for _, word in ipairs({ "world", "city", "instance", "bg", "group" }) do
					if ticked[word] then names[#names + 1] = PLACE_NAMES[word] end
				end
				list[#list + 1] = #names == 0 and { L["Never"], NEVER_CHIP } or { table.concat(names, ", "), WHEN_CHIP }
			end
		end
		return list
	end

	-- A camera choice for a row: a dropdown, or on a client without the
	-- modern one a button that steps through them.
	local function CameraPick(parent, id)
		local trigger = ns.CameraRowTrigger(id)
		local function Set(value)
			ns.SetCameraRowValue(id, "camera", value)
			Changed()
		end
		-- Its cameras, and My Shots' shots where it has the cozy camera (the
		-- standing-still ones a shot is made from), No camera last
		-- (CameraTriggerEditor.lua).
		local function Cameras() return ns.CameraChoiceValues(trigger.cameras) end
		local takesShots = false
		for _, value in ipairs(trigger.cameras) do takesShots = takesShots or value == "cozy" end
		local ok, pick = ns.MenuDropdown(parent)
		if ok and pick and pick.SetupMenu then
			pick:SetWidth(150)
			pick:SetupMenu(function(_, root)
				for _, value in ipairs(Cameras()) do
					root:CreateRadio(ns.CameraName(value) or tostring(value), function()
						return ns.GetDB() ~= nil and ns.CameraRowValue(id, "camera") == value
					end, function() Set(value) end)
				end
				-- (New shot...: made, picked, and My Shots opened on it.)
				if takesShots and not ns.SHOTS_RETIRED and #(ns.ShotList()) < ns.SHOT_MAX then
					root:CreateButton(L["New shot..."], function() ns.NewShotFor(Set) end)
				end
			end)
			pick.Refresh = function(self) self:GenerateMenu() end
		else
			pick = ns.PanelButton(parent)
			pick:SetSize(150, 22)
			pick:SetScript("OnClick", function()
				local now, list = ns.CameraRowValue(id, "camera"), Cameras()
				for i, value in ipairs(list) do
					if value == now then
						Set(list[i % #list + 1])
						return
					end
				end
				Set(list[1])
			end)
			pick.Refresh = function(self) self:SetText(ns.CameraName(ns.CameraRowValue(id, "camera")) or "") end
		end
		pick.searchSkip = true
		controls[#controls + 1] = pick
		return pick
	end

	local function MoveButton(row, id, by)
		local button = CreateFrame("Button", nil, row)
		button:SetSize(14, 14)
		button:SetPoint("LEFT", row, "LEFT", 2, by < 0 and 7 or -7)
		local art = by < 0 and "Interface\\Buttons\\Arrow-Up-" or "Interface\\Buttons\\Arrow-Down-"
		button:SetNormalTexture(art .. "Up")
		button:SetPushedTexture(art .. "Down")
		button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		Tooltip(button, by < 0 and L["Move this row up: its trigger tries it sooner."]
			or L["Move this row down: its trigger tries it later."])
		button:SetScript("OnClick", function()
			ns.MoveCameraRow(id, by)
			Changed()
		end)
		return button
	end

	-- The rows as shown, grouped by their first row's camera's name (Sort
	-- by: Camera, the default; an older saved "camera" too) then by scene
	-- name, or by scene name alone (Scene); no camera last. Each scene's
	-- rows together in their order.
	local HUB_NAMES = { cozy = "Cozy Cam", vista = "Vista Cam", fish = "Fish Cam", afk = "AFK Cam",
		tele = "Tele Cam", flight = "Flight Cam", quest = "Quest Cam", walk = "RP Walk Cam", run = "Auto-run Cam",
		[true] = "Death Cam", chat = "Chat Cam", death = "Death Cam" }
	local SORTS = { { nil, "Camera" }, { "trigger", "Scene" } }
	local function SortOf()
		return ns.GetDB().cameraRows.sort == "trigger" and "trigger" or nil
	end
	local function ShownRows()
		local sort = SortOf()
		local groups, byTrigger = {}, {}
		for _, id in ipairs(ns.CameraRowOrder()) do
			local trigger = ns.CameraRowTrigger(id)
			local group = byTrigger[trigger]
			if not group then
				-- (Its name without a leading slash: /dance among the d's.)
				local name = SceneName(trigger):gsub("^%p+", ""):lower()
				local camera, cam = ns.ShotBase(ns.CameraRowValue(id, "camera")), ""
				if sort == nil then
					cam = HUB_NAMES[camera] and (ns.CAMERA_NAMES[camera] or ""):lower() or "\255"
				end
				group = { name = name, cam = cam }
				byTrigger[trigger], groups[#groups + 1] = group, group
			end
			group[#group + 1] = id
		end
		table.sort(groups, function(a, b)
			if a.cam ~= b.cam then return a.cam < b.cam end
			return a.name < b.name
		end)
		local sorted = {}
		for _, group in ipairs(groups) do
			for _, id in ipairs(group) do sorted[#sorted + 1] = id end
		end
		return sorted
	end
	local function SetSort(value)
		ns.GetDB().cameraRows.sort = value
		Refresh()
	end
	-- (a dropdown, or on a client without the modern one a button that steps)
	local ok, sort = ns.MenuDropdown(content)
	if ok and sort and sort.SetupMenu then
		sort:SetWidth(110)
		sort:SetupMenu(function(_, root)
			for _, entry in ipairs(SORTS) do
				root:CreateRadio(L[entry[2]], function() return ns.GetDB() ~= nil and SortOf() == entry[1] end,
					function() SetSort(entry[1]) end)
			end
		end)
		sort.Refresh = function(self) self:GenerateMenu() end
	else
		sort = ns.PanelButton(content)
		sort:SetSize(110, 22)
		sort:SetScript("OnClick", function()
			local now = SortOf()
			for i, entry in ipairs(SORTS) do
				if entry[1] == now then SetSort(SORTS[i % #SORTS + 1][1]) return end
			end
		end)
		sort.Refresh = function(self)
			local now = SortOf()
			for _, entry in ipairs(SORTS) do
				if entry[1] == now then self:SetText(L[entry[2]]) end
			end
		end
	end
	sort:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	sort.searchSkip = true
	Tooltip(sort, L["Lists the rows by camera name or by scene name."])
	controls[#controls + 1] = sort
	local sortLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	sortLabel:SetPoint("RIGHT", sort, "LEFT", -6, 0)
	sortLabel:SetText(L["Sort by"])
	-- A trigger of your own (CustomTriggers.lua): a new one, made in the New
	-- trigger panel (CameraTriggerEditor.lua) and added to the rows on Save,
	-- or one a friend shared.
	do
		local draft
		draft = ns.BuildTriggerDraft(content, { width = ROW_W, Tooltip = Tooltip,
			onSaved = function() Changed() end,
			onShown = function(shown)
				grid:ClearAllPoints()
				if shown then
					grid:SetPoint("TOPLEFT", draft, "BOTTOMLEFT", 0, -8)
				else
					grid:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
				end
				FitContentHeight(content)
			end })
		draft:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
		local newTrigger = ns.PanelButton(content)
		newTrigger:SetSize(110, 22)
		newTrigger:SetPoint("LEFT", bar, "LEFT", 0, 0)
		newTrigger:SetText(L["+ New scene"])
		newTrigger.searchLabel = L["+ New scene"]
		Tooltip(newTrigger, L["Make a scene of your own with its triggers, camera and end."])
		newTrigger:SetScript("OnClick", function() draft:Open() end)
		newTrigger.Refresh = function(self)
			local count = 0
			for _ in tostring(ns.GetDB().cameraRows.custom or ""):gmatch("[^,]+") do count = count + 1 end
			self:SetEnabled(count < ns.CUSTOM_TRIGGER_MAX)
		end
		controls[#controls + 1] = newTrigger
		local import = ns.PanelButton(content)
		import:SetSize(70, 22)
		import:SetPoint("LEFT", newTrigger, "RIGHT", 6, 0)
		import:SetText(L["Import"])
		import.searchSkip = true
		Tooltip(import, L["Add a scene or shot a friend shared (the text from their Share button)."])
		import:SetScript("OnClick", function()
			ns.ShowCameraImport(function(new, kind)
				if kind == "trigger" then opened[new] = true end
				Changed()
			end)
		end)
		-- (Built-in triggers you've deleted: Add back, shown while there are any.)
		local addBack = ns.BuildAddBackMenu(content, function(trigger) return SceneName(ns.CAMERA_TRIGGER[trigger]) end,
			Changed)
		addBack:SetPoint("LEFT", import, "RIGHT", 6, 0)
		Tooltip(addBack, L["Bring back a built-in scene you deleted, with its settings as they were."])
		controls[#controls + 1] = addBack
	end

	-- (Who's in a row's group, as its drawer was made for: made again when it changes.)
	local function GroupSig(id)
		local trigger, copy = ns.CameraRowTrigger(id)
		return copy and "" or table.concat(ns.SceneGroupMembers(trigger.key), ",")
	end
	function grid:Refresh()
		local list = ShownRows()
		local at = {}
		for i, id in ipairs(list) do
			at[id] = i
			ns.CameraRowFollow(id) -- (its unset ticks its camera's, before its controls refresh)
			if rows[id] and rows[id].groupSig ~= GroupSig(id) then
				rows[id]:Hide()
				drawers[id]:Hide()
				rows[id], drawers[id] = nil, nil
			end
			if not rows[id] then
				MakeRow(id)
				rows[id].groupSig = GroupSig(id)
			end
		end
		for id, row in pairs(rows) do
			if not at[id] then
				row:Hide()
				drawers[id]:Hide()
				drawers[id].searchAlways = false
			end
		end
		local y, band, last = 0, 0, nil
		for i, id in ipairs(list) do
			local row, drawer = rows[id], drawers[id]
			local trigger = ns.CameraRowTrigger(id)
			if trigger ~= last then band, last = band + 1, trigger end
			row.band:SetColorTexture(1, 1, 1, band % 2 == 1 and 0.04 or 0)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
			row:Show()
			y = y + ROW_H
			row.up:SetShown(i > 1 and ns.CameraRowTrigger(list[i - 1]) == trigger)
			row.down:SetShown(i < #list and ns.CameraRowTrigger(list[i + 1]) == trigger)
			-- (Its drawer: a closed one's settings still count for page search, which opens it.)
			drawer.searchAlways = true
			row.toggle:SetNormalTexture(opened[id] and "Interface\\Buttons\\UI-MinusButton-Up"
				or "Interface\\Buttons\\UI-PlusButton-Up")
			if opened[id] then
				drawer:ClearAllPoints()
				drawer:SetPoint("TOPLEFT", grid, "TOPLEFT", DRAWER_X, -y)
				drawer:Show()
				y = y + drawer:GetHeight() + 4
			else
				drawer:Hide()
			end
		end
		grid:SetHeight(math.max(y, 1))
	end
	controls[#controls + 1] = grid
	-- For the General page's camera tabs (CameraManager.lua): a row's name and
	-- triggers, and the row shown here, its settings open, scrolled to and lit.
	ns.SceneRowLabel = RowLabel
	function ns.SceneRowTriggers(id)
		local trigger, copy = ns.CameraRowTrigger(id)
		if copy or trigger.custom then return TriggerName(trigger) end
		return BuiltInNames(trigger.key)
	end
	function ns.ShowSceneRow(id)
		opened[id] = true
		ns.ShowHubPage("Scenes")
		grid:Refresh()
		local row = rows[id]
		if not row then return end
		if not row.flash then
			row.flash = row:CreateTexture(nil, "BACKGROUND", nil, -7)
			row.flash:SetAllPoints()
			row.flash:SetColorTexture(1, 0.82, 0, 0.3)
			local fade = row.flash:CreateAnimationGroup()
			local alpha = fade:CreateAnimation("Alpha")
			alpha:SetFromAlpha(1)
			alpha:SetToAlpha(0)
			alpha:SetStartDelay(0.4)
			alpha:SetDuration(1.4)
			fade:SetScript("OnFinished", function() row.flash:Hide() end)
			row.flash.fade = fade
		end
		C_Timer.After(0.05, function() -- (once the page has fit its height)
			local scroll = grid:GetParent():GetParent()
			local top, rowTop = grid:GetParent():GetTop(), row:GetTop()
			if scroll.SetVerticalScroll and top and rowTop then
				local range = scroll:GetVerticalScrollRange() or 0
				scroll:SetVerticalScroll(math.max(0, math.min(range, top - rowTop - 40)))
			end
			row.flash:Show()
			row.flash.fade:Stop()
			row.flash.fade:Play()
		end)
	end
	-- What the page's Reset puts back (and the profile modules find here):
	-- every row it can have, made or not, and the cameras' old rows their
	-- triggers' own rows follow until set.
	RecordKey(content, "cameraRows")
	for _, list in ipairs(ns.CAMERA_ROW_LISTS) do RecordKey(content, list) end
	for _, trigger in ipairs(ns.CAMERA_TRIGGERS) do
		for _, field in ipairs({ "camera", "music", "cine", "sceneOff" }) do
			if type(trigger[field]) == "string" then RecordKey(content, trigger[field]) end
		end
		if INSTANT[trigger.key] then RecordKey(content, INSTANT[trigger.key]) end
		local extra = EXTRAS[trigger.key]
		if extra then RecordKey(content, extra.list or extra.slider[1]) end
		for copy = 1, ns.CAMERA_ROW_COPIES do
			local rowKey = ns.CameraRowKey(trigger.key .. (copy > 1 and copy or ""))
			for _, list in ipairs(ns.CAMERA_ROW_LISTS) do RecordRow(content, list, rowKey) end
		end
	end
	for _, cam in ipairs(ns.CAMERA_OFF_CAMS) do
		RecordKey(content, "camAlways" .. cam[1])
		if not ns.CALM_WAIT_NEVER[cam[1]] then RecordKey(content, cam[1] .. "CalmWait") end
		for _, list in ipairs(ns.CAMERA_ROW_LISTS) do RecordRow(content, list, "cam:" .. cam[1]) end
	end

	function MakeRow(id)
		local trigger, copy = ns.CameraRowTrigger(id)
		local key, rowKey = trigger.key, ns.CameraRowKey(id)
		local row = CreateFrame("Button", nil, grid)
		row:SetSize(ROW_W, ROW_H)
		row:Hide()
		rows[id] = row
		row.band = row:CreateTexture(nil, "BACKGROUND", nil, -8)
		row.band:SetAllPoints()
		local hover = row:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.05)
		local line = row:CreateTexture(nil, "BACKGROUND")
		line:SetPoint("BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT")
		line:SetHeight(1)
		line:SetColorTexture(1, 1, 1, 0.08)
		row:SetScript("OnClick", function() Toggle(id) end)
		local function Place(control, x)
			control:SetPoint("LEFT", row, "LEFT", x, 0)
			return control
		end
		row.up, row.down = MoveButton(row, id, -1), MoveButton(row, id, 1)

		-- Its tick: off, its trigger passes it over (the next of its rows is
		-- tried; with none, no camera).
		local on = Place(Check(row, nil, "", L["Use this row; unticked, its trigger skips it."],
			function(value)
				ns.SetCameraRowOn(id, value)
				Changed()
			end), ON_X)
		on.Refresh = function(self) self:SetChecked(ns.CameraRowOn(id)) end
		on.searchLabel = RowLabel(id)

		-- Its name: your own (its trigger's dimmed after it), else its trigger's
		-- and number; dimmed with no camera.
		local name = Place(Label(row, "GameFontHighlight", ""), NAME_X)
		name:SetWidth(NAME_W)
		name:SetWordWrap(false)
		name.searchSkip = true
		function row:SetName()
			local own = OwnName(id)
			if own ~= "" then
				name:SetText(own .. " |cff999999" .. RowLabel(id) .. "|r")
			else
				name:SetText(SceneName(trigger) .. (copy and " |cff999999(" .. copy .. ")|r" or ""))
			end
			name:SetAlpha((ns.CameraRowOn(id) and HasCamera(id)) and 1 or 0.5)
			self.chips:SetAlpha(ns.CameraRowOn(id) and 1 or 0.5)
		end

		-- The chips, as many as fit (hovering the row lists them all).
		local chips = Place(CreateFrame("Frame", nil, row), CHIPS_X)
		chips:SetSize(CHIPS_W, 16)
		chips.searchSkip = true
		chips.pool = {}
		row.chips = chips
		local parts -- (its When's, below)
		chips.Refresh = function()
			local list = RowChips(id, parts)
			row.chipList = list
			local x, shownChips = 0, 0
			for i, each in ipairs(list) do
				local chip = chips.pool[i]
				if not chip then
					chip = CreateFrame("Frame", nil, chips)
					chip:SetHeight(16)
					chip.back = chip:CreateTexture(nil, "BACKGROUND")
					chip.back:SetAllPoints()
					chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					chip.text:SetPoint("CENTER")
					chips.pool[i] = chip
				end
				chip.text:SetText(each[1])
				local width = math.ceil(chip.text:GetStringWidth()) + 10
				if x + width > CHIPS_W then break end
				local c = each[2]
				chip.back:SetColorTexture(c[1], c[2], c[3], 0.9)
				chip.text:SetTextColor(c[4], c[5], c[6])
				chip:SetWidth(width)
				chip:ClearAllPoints()
				chip:SetPoint("LEFT", chips, "LEFT", x, 0)
				chip:Show()
				x, shownChips = x + width + 4, i
			end
			for i = shownChips + 1, #chips.pool do chips.pool[i]:Hide() end
			row:SetName()
		end
		controls[#controls + 1] = chips

		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(OwnName(id) ~= "" and OwnName(id) or RowLabel(id), 1, 1, 1)
			local tip = EVENT_TIPS[key] or TIPS[key] or (trigger.custom and L["A scene of your own; open it to set its triggers and when it ends."])
			if not copy and ns.SceneGroupOf(key) then
				local names = {}
				for _, member in ipairs(ns.SceneGroupMembers(key)) do names[#names + 1] = LABELS[member] or member end
				tip = (L["Starts on any of these: %s."]):format(table.concat(names, ", "))
			end
			if tip then GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true) end
			for _, chip in ipairs(self.chipList or {}) do
				GameTooltip:AddLine("- " .. chip[1], 1, 0.82, 0)
			end
			GameTooltip:AddLine(L["Click to show or hide its settings."], 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)

		-- Open, copy, and (a copy) remove.
		row.toggle = Place(CreateFrame("Button", nil, row), ROW_W - 44)
		row.toggle:SetSize(14, 14)
		row.toggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		row.toggle:SetScript("OnClick", function() Toggle(id) end)
		Tooltip(row.toggle, L["Show or hide this row's settings."])
		-- (Copy: two squares, one over the other, drawn here, the back one first.)
		local copyButton = SHOW_COPY and Place(CreateFrame("Button", nil, row), ROW_W - 66)
		if copyButton then
			copyButton:SetSize(16, 16)
			for i, square in ipairs({ { 0, 5 }, { 5, 0 } }) do
				local x, y = square[1], square[2]
				local edge = copyButton:CreateTexture(nil, "ARTWORK", nil, i * 2 - 2)
				edge:SetSize(11, 11)
				edge:SetPoint("TOPLEFT", x, -y)
				edge:SetColorTexture(1, 0.82, 0, 1)
				local inside = copyButton:CreateTexture(nil, "ARTWORK", nil, i * 2 - 1)
				inside:SetSize(7, 7)
				inside:SetPoint("TOPLEFT", x + 2, -y - 2)
				inside:SetColorTexture(0.1, 0.1, 0.1, 1)
			end
			copyButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			Tooltip(copyButton, L["Copies this row just below, so you can give it another camera."])
			copyButton:SetScript("OnClick", function()
				local new = ns.CopyCameraRow(id)
				if new then
					opened[new] = true
					Changed()
				end
			end)
			copyButton.Refresh = function(self)
				local free = ns.FreeCameraRow(key) ~= nil
				self:SetEnabled(free)
				self:SetAlpha(free and 1 or 0.35)
			end
			controls[#controls + 1] = copyButton
		end
		-- (Every row: a copy, one of yours with its copies, or a built-in
		-- trigger's own row, which Add back brings back.)
		do
			local remove = Place(CreateFrame("Button", nil, row), ROW_W - 22)
			remove:SetSize(16, 16)
			remove:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
			remove:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			Tooltip(remove, copy and L["Remove this copy."]
				or trigger.custom and L["Delete this scene of your own, with its copies."]
				or L["Deletes this scene so it starts no camera."])
			remove:SetScript("OnClick", function()
				local function Gone()
					opened[id] = nil
					Changed()
				end
				if copy then
					ns.RemoveCameraRow(id)
					Gone()
				elseif trigger.custom then
					ns.ConfirmRemoveCustomTrigger(id, Gone)
				else
					ns.ConfirmDeleteBuiltInTrigger(key, RowLabel(id), Gone) -- (a group's members with it)
				end
			end)
		end

		-- The drawer.
		-- (What its triggers need: a group's members' too, a line each.)
		local extras = {}
		if not copy then
			for _, member in ipairs(ns.SceneGroupMembers(key)) do
				if EXTRAS[member] then extras[#extras + 1] = member end
			end
		end
		local function LineHeight(name)
			local member = name:match("^Extra:(.+)$")
			return (member and EXTRAS[member].slider) and 46 or LINE_H
		end
		local LINES = { "Name", "Camera", "When" }
		-- (Its Triggers, a line each, under the rest, for a scene of yours or a
		-- built-in one that takes them: CameraTriggerEditor.lua. When each
		-- ends is the trigger's own: the Triggers page.)
		local custom = trigger.custom and not copy
		local takesTriggers = not copy and ns.SceneTakesTriggers(key)
		local LINE_NAMES = { Name = L["Name"], Camera = L["Camera"], When = L["When"] }
		for _, member in ipairs(extras) do
			LINES[#LINES + 1] = "Extra:" .. member
			LINE_NAMES["Extra:" .. member] = EXTRAS[member][1]
		end
		local lineTop, height = {}, 4
		for _, each in ipairs(LINES) do
			lineTop[each] = height
			height = height + LineHeight(each)
		end
		local drawer = CreateFrame("Frame", nil, grid)
		drawer:SetSize(ROW_W - DRAWER_X, height + 4)
		local blockLines = 0 -- (the Triggers lines shown now)
		drawer:Hide()
		drawers[id] = drawer
		drawer.openSection = function()
			opened[id] = true
			grid:Refresh()
		end
		local drawerBack = drawer:CreateTexture(nil, "BACKGROUND")
		drawerBack:SetAllPoints()
		drawerBack:SetColorTexture(0, 0, 0, 0.3)
		local function At(lineName, control, x, dy)
			local h = LineHeight(lineName)
			control:SetPoint("LEFT", drawer, "TOPLEFT", x, -lineTop[lineName] - h / 2 + (dy or 0))
			return control
		end
		for _, each in ipairs(LINES) do
			local label = At(each, Label(drawer, "GameFontNormalSmall", LINE_NAMES[each]), 6)
			label.searchSkip = true
		end

		-- Name: your own for the row (empty: its trigger's, greyed in the box).
		local nameBox = At("Name", ns.SkinEditBox(CreateFrame("EditBox", nil, drawer, "InputBoxTemplate")),
			LABEL_W + 6)
		nameBox:SetSize(220, 20)
		nameBox:SetAutoFocus(false)
		nameBox:SetMaxLetters(40)
		nameBox.searchSkip = true
		local nameHint = nameBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		nameHint:SetPoint("LEFT", 2, 0)
		nameHint:SetPoint("RIGHT", -2, 0)
		nameHint:SetJustifyH("LEFT")
		nameHint:SetWordWrap(false)
		nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		nameBox:SetScript("OnEditFocusLost", function(self)
			local text = self:GetText():match("^%s*(.-)%s*$")
			ns.GetDB().cameraRows[id .. ".name"] = text ~= "" and text or nil
			row:SetName()
			nameHint:SetShown(text == "")
		end)
		nameBox:SetScript("OnEditFocusGained", function() nameHint:Hide() end)
		nameBox:SetScript("OnEscapePressed", function(self)
			self:SetText(OwnName(id))
			self:ClearFocus()
		end)
		nameBox.Refresh = function(self)
			if self:HasFocus() then return end
			self:SetText(OwnName(id))
			nameHint:SetText(RowLabel(id))
			nameHint:SetShown(OwnName(id) == "")
		end
		controls[#controls + 1] = nameBox
		Tooltip(nameBox, L["Your own name for this row, shown on the grid."])

		-- Camera: its camera, its Music and CineMode.
		local pick = At("Camera", CameraPick(drawer, id), LABEL_W)
		Tooltip(pick, trigger.custom and L[ns.CUSTOM_CAMERA_TIP]
			or L["The camera this row starts."])
		local x = LABEL_W + 166
		if trigger.music then
			local music = Check(drawer, nil, L["Music"], MUSIC_TIPS[key] or MUSIC_TIP, function(value)
				ns.SetCameraRowValue(id, "music", value)
				Changed()
			end)
			music.Refresh = function(self) self:SetChecked(ns.CameraRowValue(id, "music") and true or false) end
			-- (The trigger's own row: its id for /cine find, as musicCamRun.)
			if not copy and type(trigger.music) == "string" then music.settingKey = trigger.music end
			GreyUnless(music, function()
				return (key == "Death" or ns.PageSetting("musicInCinematic")) and (key == "AFK" or HasCamera(id))
			end)
			At("Camera", music, x)
			x = x + 90
		end
		if trigger.cine then
			local cine = Check(drawer, nil, "CineMode", CINE_TIP, function(value)
				ns.SetCameraRowValue(id, "cine", value)
				Changed()
			end)
			cine.Refresh = function(self) self:SetChecked(ns.CameraRowValue(id, "cine") and true or false) end
			-- (The trigger's own row: its id for /cine find, as runCine.)
			if not copy and type(trigger.cine) == "string" then cine.settingKey = trigger.cine end
			GreyUnless(cine, function() return HasCamera(id) end)
			At("Camera", cine, x)
			x = x + 100
		end
		if INSTANT[key] and not copy then
			local instant = Check(drawer, INSTANT[key], L["Fade at once"],
				L["Skips the wait before fading, so the UI fades and the camera starts moving straight away."])
			GreyUnless(instant, function() return HasCamera(id) end)
			At("Camera", instant, x)
		end

		-- When: as the Standard Frames page's rows, In combat, the places and
		-- the Calm Timer wait (a trigger's own row: its camera's until set).
		-- Flights never start in instances; the death camera can't wait or be
		-- kept out of fights (you die in one).
		local omit = { enemyShow = true, friendlyShow = true, combatShow = key == "Death" or nil }
		for where in pairs(ns.CAMERA_OFF_NEVER[ns.CameraValueMode(trigger.cameras[1])] or {}) do
			omit[where == "BGs" and "bgShow" or "instanceShow"] = true
		end
		local calmItem = key ~= "Death" and { L["Wait for the Calm Timer"],
			function() return ns.CameraRowCalm(id) end,
			function() ns.GetDB().cameraRows[id .. ".calm"] = not ns.CameraRowCalm(id) end, nil,
			L["This row's camera waits until the Calm Timer (CineMode page) has run out after a fight."] } or nil
		local function Key() return rowKey end
		local function SetAlways(value) ns.GetDB().cameraRows[id .. ".always"] = value end
		parts = ns.ListRowParts(Key, FRAME_COLUMNS, nil, SetAlways, { anyFight = true, omit = omit, calmItem = calmItem })
		local when = ns.GridRow(ns.GRID_KIT, drawer, 0, WHEN_LAYOUT, {
			band = 1,
			always = { isOn = function() return ns.CameraRowAlways(id) end, set = SetAlways,
				tip = L["This row's camera may start anywhere."] },
			menus = parts.menus,
			help = WHEN_HELP,
			follow = { key = Key, choices = FollowChoices },
			rule = { key = Key, label = function() return RowLabel(id) end, grid = parts.grid, words = parts.words,
				apply = parts.apply, changed = WhenChanged },
			changed = WhenChanged,
		})
		At("When", when, LABEL_W)

		if takesTriggers then
			local function BlockAt(line, control, x)
				control:SetPoint("LEFT", drawer, "TOPLEFT", x, -height - (line - 0.5) * LINE_H)
				return control
			end
			BlockAt(1, Label(drawer, "GameFontNormalSmall", L["Triggers"]), 6).searchSkip = true
			ns.BuildCustomTriggerLines(drawer, id, { At = At, BlockAt = BlockAt, Changed = Changed, Tooltip = Tooltip,
				x = LABEL_W, shareX = LABEL_W + 236, builtinLabel = not custom and BuiltInList(key) or nil,
				AddControl = function(control) controls[#controls + 1] = control end,
				-- (The drawer grows and shrinks with them; the rows below move.)
				resize = function(lines)
					if lines == blockLines then return end
					blockLines = lines
					drawer:SetHeight(height + lines * LINE_H + 4)
					if drawer:IsShown() then grid:Refresh() end
				end })
		end

		-- What its triggers need (its own row only; a group's members' each,
		-- named for the member where there's more than one).
		for _, member in ipairs(extras) do
			local extra, line = EXTRAS[member], "Extra:" .. member
			if extra.list then
				At(line, ListBox(drawer, extra.list, 420, extra.tip,
					extra.list == "cozyBuffs" and function() if ns.CheckIdleBuffs then ns.CheckIdleBuffs() end end or nil),
					LABEL_W + 6)
			else
				local s = extra.slider
				local label = #ns.SceneGroupMembers(key) > 1 and (LABELS[member] or member) .. ": " .. s[2] or s[2]
				local slider = At(line, Slider(drawer, s[1], label, s[3], s[4], s[5], s[6]), LABEL_W + 4, -6)
				Tooltip(slider, extra.tip or GO_TIP)
				if member ~= "Still" then GreyUnless(slider, function() return HasCamera(id) end) end
			end
		end
	end

	-- Indoors: hidden for now (true brings it back); the settings keep working
	-- at their values.
	local SHOW_INDOOR_SETTINGS = false
	if SHOW_INDOOR_SETTINGS then
		local indoorHeader = Header(content, L["Indoors"], grid, -24)
		local indoorLimits = Check(content, "indoorLimits", L["Limit the camera indoors"],
			L["Indoors, the camera modes zoom out and swing less so they don't hit walls."])
		indoorLimits:SetPoint("TOPLEFT", indoorHeader, "BOTTOMLEFT", -2, -6)
		indoorLimits:HookScript("OnClick", Refresh) -- grey out / enable the options below
		local function IfIndoorLimits(db) return db.indoorLimits end

		local indoorZoom = Slider(content, "indoorZoomOut", L["Zoom out indoors up to"], 0, 10, 0.5, L["%.1f yards"])
		indoorZoom:SetPoint("TOPLEFT", indoorLimits, "BOTTOMLEFT", 4, -26)
		Tooltip(indoorZoom, L["How far past your own distance the slow zoom may pull back indoors."])
		GreyUnless(indoorZoom, IfIndoorLimits)

		local indoorSwing = Slider(content, "indoorSwing", L["Swing indoors up to"], 0, 90, 5, "%d°")
		indoorSwing:SetPoint("TOPLEFT", indoorZoom, "BOTTOMLEFT", 0, -34)
		Tooltip(indoorSwing, L["How far either side of behind the flight, RP walk and auto-run cameras " ..
			"may swing indoors."])
		GreyUnless(indoorSwing, IfIndoorLimits)

		local indoorSweep = Check(content, "indoorNoSweep", L["No AFK camera sweep indoors"],
			L["Stops the AFK camera sweeping around you indoors, where it can hit walls."])
		indoorSweep:SetPoint("TOPLEFT", indoorSwing, "BOTTOMLEFT", -4, -14)
		GreyUnless(indoorSweep, IfIndoorLimits)
	end

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Scenes")
end

-- The Standard Frames table under anchor: a row per frame (COMBAT_SHOW
-- items), a column per situation. Used by the Gamepad and Chat pages too.
-- ...: where the rows are (page, then section). The Chat page's rows
-- aren't frames: rows.labelWidth widens the names, rows.columnTips[c] is a
-- column's tip, rows.noHeadings leaves the headings out (a row added later
-- under a table's), rows.underHeader sits it close under a header or a
-- page switch (the one-line headings' empty top taken up), and a row's
-- alwaysOn() / setAlways(value) are its Always box's own setting.
local function ShowTable(content, anchor, rows, ...)
	-- One table: a row per frame, a column per situation.
	local LABEL_WIDTH, COLUMN_WIDTH, ROW_HEIGHT = rows.labelWidth or FRAME_LABEL_WIDTH, FRAME_COLUMN_WIDTH, 24
	local COLUMNS = FRAME_COLUMNS
	SetSection(content, (select(2, ...))) -- (its heading: the rows' section)
	local columnTop = CreateFrame("Frame", nil, content)
	columnTop:SetSize(1, 1)
	columnTop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, rows.underHeader and ns.GRID_MENUS and 6 or -12)
	-- (The rows as dropdowns where the client has menus: GridRows.lua.)
	if ns.GRID_MENUS then
		return ns.GridTable(content, columnTop, rows, setmetatable(
			{ labelWidth = LABEL_WIDTH, rowHeight = ROW_HEIGHT, columns = COLUMNS }, { __index = ns.GRID_KIT }))
	end
	for c, column in ipairs(rows.noHeadings and {} or COLUMNS) do
		FrameHeading(content, column[1]):SetPoint("TOPLEFT", columnTop, "TOPLEFT",
			LABEL_WIDTH + (c - 1) * COLUMN_WIDTH, 0)
	end

	local lastLabel = columnTop
	-- (rows.kindHeadings: as GridRows.lua's ns.GridTable has them.)
	local gap, lastKind = 0, nil
	for r, item in ipairs(rows) do
		local kind = item.part and 2 or 1
		if rows.kindHeadings and kind ~= lastKind then
			local head = Label(content, "GameFontNormalSmall", rows.kindHeadings[kind])
			head:SetPoint("TOPLEFT", columnTop, "TOPLEFT", 0,
				lastKind and -FRAME_HEADING_HEIGHT - 4 - (r - 1) * ROW_HEIGHT - gap - 6 or -2)
			head.searchSkip = true
			if lastKind then gap = gap + ROW_HEIGHT end
			lastKind = kind
		end
		local y = -FRAME_HEADING_HEIGHT - 4 - (r - 1) * ROW_HEIGHT - gap
		local rowLabel = Label(content, "GameFontHighlight", item.label)
		rowLabel:SetPoint("TOPLEFT", columnTop, "TOPLEFT", 0, y - 5)
		rowLabel:SetWidth(LABEL_WIDTH - 4)
		rowLabel:SetJustifyH("LEFT")
		rowLabel:SetWordWrap(false)
		ShowBox(content, item, rowLabel)
		-- (No » to a row's own page, 2026-11-16: its frame's pages are tabs of one icon.)
		ns.LabelHover(content, rowLabel, item.tip)
		if ns.CINE_SHOW_SETTING[item.key] then
			RecordKey(content, ns.CINE_SHOW_SETTING[item.key]) -- (for the page's Reset)
		end
		local alwaysOn = item.alwaysOn or ns.IsCineShowOn
		for c, column in ipairs(item.alwaysOnly and { COLUMNS[1] } or COLUMNS) do
			local isOn, tableKey, needsStay = column[2], column[3], column[4]
			if c == 1 then isOn = alwaysOn end
			local alwaysTip = item.alwaysTip or item.part
				and L["Shows it whenever its frame shows, hovered or not."]
				or L["Shows it all through CineMode instead of hiding it."]
			local columnTip = rows.columnTips and rows.columnTips[c] or column[5]
			local check = Check(content, tableKey, "", c == 1 and alwaysTip or columnTip, function(value)
				local setting = c == 1 and ns.CINE_SHOW_SETTING[item.key]
				if c == 1 and item.setAlways then
					item.setAlways(value)
				elseif setting then
					ns.GetDB()[setting] = value
				else
					ns.GetDB()[tableKey][item.key] = value
				end
				if item.apply then item.apply() end
				if c == 1 then Refresh() end -- (greys the other columns)
			end)
			RecordRow(content, tableKey, item.key)
			check:SetPoint("TOPLEFT", columnTop, "TOPLEFT",
				LABEL_WIDTH + (c - 1) * COLUMN_WIDTH + (COLUMN_WIDTH - 26) / 2, y)
			check.Refresh = function(self)
				local db = ns.GetDB()
				self:SetChecked(isOn(item.key))
				-- (A row with a rule that reads: the rule decides, its ticks greyed.)
				self:SetEnabled(RowShown(item) and not ns.RuleTest(item.key) and (c == 1
					or (not alwaysOn(item.key) and (not needsStay or db.stayInCombat))))
			end
		end
		lastLabel = rowLabel
	end
	return lastLabel -- (the last row's label, to place what comes below)
end
-- (For the pages made before it in this file: built once it's all loaded.)
ns.ShowTable = ShowTable

-- Whether a Show in row (GridRows.lua) is on anywhere at all: Always, any
-- tick of the Standard Frames page's columns, Out of combat, In a camera mode,
-- or a rule (a Visual Effects row's effect switch follows it).
function ns.RowOnAnywhere(key, always)
	if always then return true end
	for c = 2, #FRAME_COLUMNS do
		if FRAME_COLUMNS[c][2](key) then return true end
	end
	if ns.IsQuietShowOn(key) or ns.IsCamShowOn(key) then return true end
	local rules = ns.GetDB().frameRules
	return type(rules) == "table" and type(rules[key]) == "string" and rules[key]:find("%S") ~= nil
end

-- A section's name row on the Unit Frames and Standard Frames pages: a band
-- across the top of frame (BAND_HEIGHT high), clicked to open or close the
-- section (the +/- sits in the page margin). check: a tick to sit at its
-- right end ("Same as target"). nameRow:SetOpen(open) shows which it is;
-- nameRow.title is its name.
local BAND_HEIGHT = 26
local function SectionBand(frame, title, onClick, check)
	SetSection(frame:GetParent(), title)
	local nameRow = CreateFrame("Button", nil, frame)
	nameRow:SetPoint("TOPLEFT", -18, 0)
	nameRow:SetPoint("TOPRIGHT")
	nameRow:SetHeight(BAND_HEIGHT)
	local band = nameRow:CreateTexture(nil, "BACKGROUND")
	band:SetAllPoints()
	band:SetColorTexture(1, 1, 1, 0.05)
	local hover = nameRow:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 0.82, 0, 0.08)
	local icon = nameRow:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("LEFT", nameRow, "LEFT", 1, 0)
	nameRow.title = Label(nameRow, "GameFontNormal", title)
	nameRow.title:SetPoint("LEFT", nameRow, "LEFT", 18, 0)
	nameRow:SetScript("OnClick", onClick)
	function nameRow:SetOpen(open)
		icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
	end
	if check then
		-- The label hangs off the row's right edge and the box sits left of it,
		-- so the text never runs past the edge whatever its width (measuring it
		-- here came up short and cut it off).
		local text = check.Text or check.text
		text:ClearAllPoints()
		text:SetPoint("RIGHT", nameRow, "RIGHT", -6, 0)
		check:SetPoint("RIGHT", text, "LEFT", -2, 0)
		check:SetFrameLevel(nameRow:GetFrameLevel() + 2)
	end
	return nameRow
end
-- (For the pages' Addon Frame Links sections: FrameLinks.lua.)
ns.GRID_KIT.SectionBand, ns.GRID_KIT.SectionState, ns.GRID_KIT.BAND_HEIGHT = SectionBand, SectionState, BAND_HEIGHT
ns.GRID_KIT.ContentDepth, ns.GRID_KIT.FitContentHeight = ContentDepth, FitContentHeight

-- The unit frame parts' rows (under the HUD page's Unit frames rows): the lists a part's row
-- keeps its dropdowns' ticks in.
function ns.UnitPartLists()
	local lists = { "calmShow", "quietShow", "camShow" }
	for c = 2, #FRAME_COLUMNS do
		lists[#lists + 1] = FRAME_COLUMNS[c][3]
	end
	return lists
end
-- One part's row: Always (its unitPart<unit><part> setting, ticked to start
-- with), the Combat, Target and Location dropdowns and Edit, its label
-- (part[2]) indent in from the row's labelWidth to its left. title: its
-- frame's name, for the rule editor; same: its "Same as target" setting
-- (greyed while that's ticked); band: its number. The caller places the row
-- (the label goes with it). Gives the row and the label's widgets.
function ns.UnitPartRow(content, labelWidth, layout, unit, title, part, same, band, indent)
	local key = "unitPart" .. unit .. part[1]
	RecordKey(content, key)
	for _, list in ipairs(ns.UnitPartLists()) do
		RecordKey(content, list)
		RecordRow(content, list, key)
	end
	local function Key() return key end
	local function SetAlways(value) ns.GetDB()[key] = value end
	local parts = ns.ListRowParts(Key, FRAME_COLUMNS, nil, SetAlways, { quiet = true, cam = true, anyFight = true })
	local row = ns.GridRow(ns.GRID_KIT, content, labelWidth, layout, {
		band = band, dot = true,
		always = { isOn = function() return ns.GetDB()[key] ~= false end, set = SetAlways,
			tip = L["Shows it the whole time, CineMode or not."] },
		menus = parts.menus,
		rule = { key = Key, label = function() return title .. ": " .. part[2] end,
			grid = parts.grid, words = parts.words, apply = parts.apply, changed = ns.ApplyUnitFrameParts },
		changed = ns.ApplyUnitFrameParts,
		-- (Greyed while it goes by the target's.)
		enabled = same and function() return ns.GetDB()[same] == false end or nil,
		override = function() return ns.StyleOverrideText(key) end,
	})
	row.debugName = title .. ": " .. part[2] -- (for the dev copy's page timing)
	local label = Label(content, "GameFontHighlight", part[2])
	label:SetPoint("TOPLEFT", row, "TOPLEFT", indent - labelWidth, -5)
	label:SetWidth(labelWidth - 4 - ns.GRID_DOT_ROOM - indent)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	return row, label, ns.LabelHover(content, label) -- (full name while cut short)
end
-- A frame set apart from the target (its Same as target unticked): its parts'
-- rows start as the target's (keys: its parts), unless it has choices of its
-- own from before (Always unticked, a dropdown or role ticked, a rule).
function ns.CopyTargetParts(unit, keys)
	local db, lists = ns.GetDB(), ns.UnitPartLists()
	for _, key in ipairs(keys) do
		local own = "unitPart" .. unit .. key
		if db[own] == false or (db.frameRules and db.frameRules[own]) then
			return
		end
		for _, list in ipairs(lists) do
			if db[list] and db[list][own] ~= nil then return end
		end
	end
	for _, key in ipairs(keys) do
		local own, target = "unitPart" .. unit .. key, "unitPartTarget" .. key
		db[own] = db[target]
		for _, list in ipairs(lists) do
			if db[list] then db[list][own] = db[list][target] end
		end
		if db.frameRules then db.frameRules[own] = db.frameRules[target] end
	end
end
-- Whether a unit frame has a part: its frame has it (parts: its UNIT_PARTS
-- list), and it's not one only some frames have (UNIT_PART_ONLY: hit text).
function ns.UnitHasPart(unit, parts, part)
	local only = ns.UNIT_PART_ONLY[part]
	return parts[part] ~= nil and (not only or only[unit] == true)
end

-- Sub-page for combat: staying cinematic in fights, and what to show then.
local function CreateCombatPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["HUD"])
	title:SetPoint("TOPLEFT", 16, -16)

	-- The page's sections, an icon each in their frame's band on the Interface
	-- hub (canvas.hubTabs, 2026-11-16), not folder tabs: keys, the sections
	-- on it (sharing one, as the party frames' two); before, the page in HUBS
	-- it's listed right before; section, its band. Each the HUD's banner: a
	-- band's banner is when its frames show. (The first is the page's own,
	-- ns.OpenOptions("Standard Frames"): HUD, its switch for all of them and
	-- no rows; hud = true. The others have no switch of their own: no dot on
	-- their icon, and the HUD's off card while it's off.)
	local HUD_ICONS = {
		-- (General since 2026-11-16: the hub's first icon, on its own before the groups; its switch still all the HUD's.)
		{ keys = { "hud" }, label = "General", section = "What Shows", before = "Gamepad", hud = true },
		-- (tabs: one page with the frame's own page's parts, its tabs: ns.ShowInTabs.)
		{ keys = { "units", "prd", "playercast", "highlight" }, label = "Unit Frames", section = "Unit Frames", before = "Personal Resources",
			icon = "Interface\\Icons\\INV_Misc_Head_Human_01",
			tabs = "units" },
		-- (Party & Raid: one icon, its tabs Party, Raid and Raid Style; Raid's
		-- icon hidden under it, tabOf, picked by its tab: tabIndex.)
		{ keys = { "party", "rsparty" }, label = "Party & Raid", section = "Party & Raid", before = "Raid Style",
			icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
			tabs = "party" },
		{ keys = { "raid" }, label = "Party & Raid", section = "Party & Raid", before = "Raid Style",
			tabs = "party", tabIndex = 2, tabOf = "HUD:party" },
		{ keys = { "bars" }, label = "Action Bars", section = "Action Bars", before = "Action Style", tabs = "bars",
			icon = "Interface\\Icons\\Ability_DualWield" },
		{ keys = { "chat" }, label = "Chat", section = "Chat", before = "Chat", tabs = "chat",
			icon = "Interface\\Icons\\INV_Scroll_03" },
		{ keys = { "minimap" }, label = "Minimap", section = "Map & Quests", before = "Minimap", tabs = "minimap",
			icon = "Interface\\Icons\\INV_Misc_Map_01" },
		{ keys = { "quests" }, label = "Quest Tracker", section = "Map & Quests", before = "Quest tracker", tabs = "quests",
			-- (A quest giver's "!", drawn sharp at 128 px: Media/make_quest_icon.py, 2026-11-16.)
			icon = ns.HELP_DISC:gsub("HelpDisc$", "QuestTracker") },
		{ keys = { "buffs" }, label = "Buffs & Debuffs", section = "Buffs & Debuffs", before = "Buffs/debuffs", tabs = "buffs",
			icon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
		{ keys = { "combat" }, label = "Timers", section = "Timers", before = "Cooldown Manager", tabs = "timers",
			icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
		{ keys = { "interface" }, label = "Menus & Info", section = "Menus & Info", before = "Combat Text Style",
			icon = "Interface\\Icons\\INV_Misc_Bag_07" },
		{ keys = { "other" }, label = "Other Frames in CineMode", section = "What Shows", before = "Gamepad" },
	}
	-- (A section's icon's name: "HUD:" and its first key.)
	local function IconOf(key)
		for _, icon in ipairs(HUD_ICONS) do
			for _, each in ipairs(icon.keys) do
				if each == key then return icon end
			end
		end
	end
	local function IconName(icon) return "HUD:" .. icon.keys[1] end

	-- (The rows are dropdowns where the client has menus, else a column each: GridRows.lua.)
	local subtitle = PageIntro(content, title, ns.GRID_MENUS
		and L["CineMode hides everything: pick which frames show, and when."]
		or L["CineMode hides everything: tick which frames show, and when."])

	-- The game's frames this client has, in sections (their page: see
	-- ROW_SECTIONS), each a table of its own; the gamepad's are on the
	-- Gamepad page, other addons' frames on the Advanced Frames page.
	local switch = PageSwitch(content, "handleFrames", L["Enable Page"],
		L["CineMode hides these frames, and shows them only when their rows say."], subtitle, function(value)
		-- (The Interface hub's General: every page of the hub with it, 2026-11-16.)
		ns.CascadeHub("UI Manager", "handleFrames", value and true or false)
		if ns.ApplyUnitFrameParts then ns.ApplyUnitFrameParts() end
		if ns.ApplyMirrorTimers then ns.ApplyMirrorTimers() end
	end)
	-- (In combat rows stay for the Calm Timer after a fight: it's the fight still.)

	-- (Your player frame kept up while you recover: the Personal Resources page.)
	-- (Pet happiness: the Quality of life > Hunter page.)
	-- The lowest option so far, and how far in from the column edge it sits.
	local lastCheck, lastIndent = switch, 0
	-- (Everything below is made the first time the page is needed, not at
	-- login: lazyPages. Opened from elsewhere before then, a section's tab
	-- makes it first.)
	local MakeHud
	local function OpenSectionFirst(key)
		MakeHud("a section opened")
		if ns.OpenFramesSection ~= OpenSectionFirst then return ns.OpenFramesSection(key) end
	end
	ns.OpenFramesSection = OpenSectionFirst
	local function MakeBody()

		-- Each section a tab of its own, in Heal Vision's folder look
		-- (ns.FolderTabs, made once every section is): the picked one's table
		-- shows on the panel under them, its full name at its top. (The party
		-- frames' two sections share the Party tab, raid-style second.) The raid-style
		-- party frames' (page = "rsparty") rows are greyed while its "Same as raid
		-- frames" is ticked, when the raid frames' rows decide for them; unticked,
		-- they're rows of their own, starting from the raid frames' choices.
		-- (section.body: what its table made, hidden on other tabs: search still
		-- finds it, and picks its tab; section.last: its last row's label, the
		-- panel's bottom under it.) The tab last picked is kept across reloads
		-- (SectionState, its id "Standard Frames/tab", open the section's key).
		local sections = {}
		local picked = { id = "Standard Frames/tab", open = "units" }
		-- (The panel's top left, under the tabs (placed once they're made, as high
		-- as their rows); the sections' frames hang on it.)
		local panelTop = CreateFrame("Frame", nil, content)
		panelTop:SetSize(1, 1)
		local panel, ShowTab, PlaceTop
		-- (The tabs' frames: shown as sub-tabs where the picked icon has more than
		-- one tab, Unit Frames' Unit frames, Resources, Cast bar and Highlight;
		-- hidden otherwise, its icon picking its one. 2026-11-16.)
		local subTabs, subTabsShown
		-- (Sections sharing a tab name share its tab, stacked: the party frames,
		-- raid-style and not. tabs[i] = { label, sections }.)
		local tabs = {}
		local function OwnPartyRows()
			-- (The page is built before the settings load: the default then.)
			local db = ns.GetDB()
			return db ~= nil and db.raidStylePartySame == false
		end
		-- Shows the picked section's tab (its sections one under another, the one
		-- the game uses now tagged In use), the panel down to its last row.
		local hudNote -- (the HUD icon's page: what the banners are, under its switch)
		local hudList, MakeHudList -- (and under it, every icon of the hub and its tabs, as links)
		local function Layout()
			SectionState.Restore(picked)
			-- (The HUD icon: its switch and note, no section.)
			local hud = picked.open == "hud"
			if hudNote then hudNote:SetShown(hud) end
			-- (Made again each time, its on/off dots as the switches are now.)
			if hud and MakeHudList then
				if hudList then hudList:Hide() end
				MakeHudList()
			end
			if hudList then hudList:SetShown(hud) end
			panel:SetShown(not hud)
			if hud then
				for _, section in ipairs(sections) do
					section.frame:Hide()
					section.body:Hide()
				end
				-- (No sub-tabs here: the last icon's were left showing over the title.)
				subTabsShown = false
				for _, tab in ipairs(subTabs or {}) do tab:Hide() end
				local help = content.pageHelp -- (back by the title, shown here)
				if help then
					help.liveTip = nil -- (the page's own tip again)
					help:ClearAllPoints()
					help:SetPoint("LEFT", title, "RIGHT", 6, 0)
				end
				FitContentHeight(content)
				return
			end
			local shown
			for i, tab in ipairs(tabs) do
				for _, section in ipairs(tab.sections) do
					if section.key == picked.open then shown = i end
				end
			end
			shown = shown or 1
			for _, section in ipairs(sections) do
				section.frame:Hide()
				section.body:Hide()
			end
			local order = {}
			for _, section in ipairs(tabs[shown].sections) do
				if section.relayout then section.relayout() end -- (the Unit frames' blocks, open as saved)
				local inUse = #tabs[shown].sections > 1 and section.inUse and section.inUse()
				if section.inUseTag then section.inUseTag:SetShown(inUse == true) end
				order[#order + 1] = section
			end
			-- (The raid-style party frames' grid folded away while Same as raid
			-- frames is ticked: just their heading, the raid frames' rows decide.)
			local above, bottom
			for _, section in ipairs(order) do
				section.frame:ClearAllPoints()
				if bottom then
					section.frame:SetPoint("TOPLEFT", bottom, "BOTTOMLEFT", 0, -28)
				else
					section.frame:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12, -10)
				end
				local folded = section.key == "rsparty" and not OwnPartyRows()
				section.frame:Show()
				section.body:SetShown(not folded)
				above, bottom = section, folded and section.frame or section.last
			end
			-- (The unit frames' Addon Frame Links: the Unit Frames icon's Frame Links tab now.)
			local inset = 0
			-- (The page's "?" by the first section's heading: its title isn't shown here.)
			local help = content.pageHelp
			if help and order[1] then
				help.liveTip = order[1].helpTip -- (that section's own tip: Tooltip)
				help:ClearAllPoints()
				help:SetPoint("CENTER", order[1].helpSpot)
				help:SetFrameLevel(order[1].frame:GetFrameLevel() + 5)
			end
			-- (Its icon's tabs as sub-tabs, where it has more than one.)
			if subTabs then
				local icon, count = IconOf(tabs[shown].sections[1].key), 0
				for _, tab in ipairs(tabs) do
					if IconOf(tab.sections[1].key) == icon then count = count + 1 end
				end
				subTabsShown = count > 1
				for i, tab in ipairs(tabs) do
					subTabs[i]:SetShown(subTabsShown and IconOf(tab.sections[1].key) == icon)
				end
			end
			ShowTab(shown)
			if PlaceTop then PlaceTop() end -- (the tabs' rows, measured again as they're shown)
			panel:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMLEFT", above.width + 6 - inset, -12)
			FitContentHeight(content)
		end
		-- (A section picked from the page (search, the Raid » button): its icon lit too.)
		local function Pick(section)
			SectionState.Save(picked, section.key)
			Layout()
			local icon = IconOf(section.key)
			if icon then ns.ShowHubPage(IconName(icon)) end
		end
		-- (Its icon picked: its first section, unless one of its others shows.
		-- The Unit Frames icon: its Show in, Keep up and Frame Links tabs over
		-- the title, made the first time; no tabs on the others.)
		-- (icon.tabs: its key in ns.ShowInTabs, a set of tabs each, made the
		-- first time; only the picked icon's shown.)
		local tabsOf = {}
		function ns.PickFramesIcon(icon)
			SectionState.Restore(picked)
			if IconOf(picked.open) ~= icon then SectionState.Save(picked, icon.keys[1]) end
			title:SetText(L[icon.label])
			title:SetShown(icon.hud == true) -- (a section's: its table's heading names it)
			if icon.tabs and not tabsOf[icon.tabs] then
				local _, Show = ns.PageTabs(content, ns.ShowInTabs(icon.tabs), icon.tabIndex or 1)
				tabsOf[icon.tabs] = content.pageTabs
				content.pageTabs.Show = Show
				content.tabbedPage = nil -- (its own HUD icon keeps its title and On/Off: its sections show none)
			end
			for key, tabs in pairs(tabsOf) do
				local mine = key == icon.tabs
				tabs.panel:SetShown(mine)
				for _, tab in ipairs(tabs.frames) do tab:SetShown(mine) end
			end
			local mine = icon.tabs and tabsOf[icon.tabs]
			-- (icon.tabIndex: its tab in the set, more than one of the HUD's own: Party & Raid's)
			if mine then mine.Show(icon.tabIndex or 1) end
			content.pageTabs = mine or nil -- (over the HUD's off card)
			title:ClearAllPoints()
			if mine then
				title:SetPoint("TOPLEFT", mine.panel, "BOTTOMLEFT", 8, -14)
			else
				title:SetPoint("TOPLEFT", 16, -16)
			end
			-- (The HUD's On/Off by the title on its own icon only: MakeHeaderSwitch.)
			content.headerSwitchOff = icon.hud ~= true
			local header = pageSwitches[content] and pageSwitches[content].header
			if header then header:SetShown(icon.hud == true) end
			Layout()
		end
		-- (ns.FramesLink's: the page opened at a section, its icon lit.)
		function ns.OpenFramesSection(key)
			SectionState.Restore(picked)
			SectionState.Save(picked, key)
			Layout()
			local icon = IconOf(key)
			ns.OpenOptions(icon and IconName(icon) or "Standard Frames")
		end
		resetHooks[content] = function()
			Layout()
			ns.ApplyHideKeybinds()
			if ns.ApplyMirrorTimers then ns.ApplyMirrorTimers() end
		end
		-- Set apart: its rows start as the raid frames' (ticks and rules),
		-- unless they have choices of their own from before.
		local function CopyRaidRows()
			local db = ns.GetDB()
			for _, key in pairs(ns.RAID_STYLE_PARTY) do
				for _, column in ipairs(FRAME_COLUMNS) do
					if db[column[3]][key] ~= nil then
						return
					end
				end
			end
			for raidKey, key in pairs(ns.RAID_STYLE_PARTY) do
				for _, column in ipairs(FRAME_COLUMNS) do
					db[column[3]][key] = column[2](raidKey)
				end
				if type(db.frameRules) == "table" then
					db.frameRules[key] = db.frameRules[raidKey]
				end
			end
		end
		-- What's on the page, to tell what a table adds.
		local function Widgets()
			local set = {}
			for _, object in ipairs({ content:GetChildren() }) do set[object] = true end
			for _, object in ipairs({ content:GetRegions() }) do set[object] = true end
			return set
		end

		local SECTION_WIDTH = ns.GRID_MENUS and ns.GridTableWidth(FRAME_LABEL_WIDTH)
			or FRAME_LABEL_WIDTH + #FRAME_COLUMNS * FRAME_COLUMN_WIDTH
		-- The Unit frames section where the client has the parts (and menus): a
		-- block per frame, its row as the other sections' and under it, opened and
		-- closed with a click on its name (the +/- in the margin), a row per part
		-- it has (its unitPart<frame><part> settings). The
		-- focus and target of target ones start with Same as target, their parts
		-- greyed while it's ticked. Which are open is kept across reloads
		-- (SectionState, "Standard Frames/unit/<row key>"). Gives the mark under
		-- the last block, to place what comes below; section.relayout opens and
		-- closes the blocks as saved, for Layout.
		local function UnitBlocks(frame, sectionRows, heading, section)
			local UNITS = {
				player = { unit = "Player", parts = ns.UNIT_PARTS_PLAYER },
				petframe = { unit = "Pet", parts = ns.UNIT_PARTS_PET },
				target = { unit = "Target", parts = ns.UNIT_PARTS_TARGET },
				tot = _G.TargetFrameToT and { unit = "ToT", same = "unitPartsToTSame", parts = ns.UNIT_PARTS_TOT } or nil,
				focus = _G.FocusFrame and { unit = "Focus", same = "unitPartsFocusSame", parts = ns.UNIT_PARTS_TARGET }
					or nil,
				focustot = _G.FocusFrame and _G.FocusFrameToT
					and { unit = "FocusToT", same = "unitPartsFocusToTSame", parts = ns.UNIT_PARTS_TOT } or nil,
			}
			local PARTS = ns.UnitPartLabels()
			-- (Every frame's name moved in TOGGLE_W for the +/-, its parts' INDENT.)
			local ROW_H, TOGGLE_W, INDENT = 24, 18, 30
			local kit = setmetatable({ labelWidth = FRAME_LABEL_WIDTH, rowHeight = ROW_H, columns = FRAME_COLUMNS },
				{ __index = ns.GRID_KIT })
			local labelWidth = FRAME_LABEL_WIDTH - ns.GRID_TABLE_LABEL_TRIM
			-- (Where ns.GridTable puts a table's row, under its column top.)
			local rowTop = -FRAME_HEADING_HEIGHT - 4
			SetSection(content, heading)
			local blocks, partRows, after = {}, {}, nil
			local function Relayout()
				for _, block in ipairs(blocks) do
					local open = block.height and SectionState.Restore(block.state) and true or false
					block.box:SetShown(open)
					block.box:SetHeight(open and block.height or 0.001)
					if block.icon then
						block.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up"
							or "Interface\\Buttons\\UI-PlusButton-Up")
					end
				end
			end
			section.relayout = Relayout
			for i, item in ipairs(sectionRows) do
				local unit = UNITS[item.key]
				local block = { state = { id = "Standard Frames/unit/" .. item.key, open = false } }
				blocks[i] = block
				local columnTop = CreateFrame("Frame", nil, content)
				columnTop:SetSize(1, 1)
				if after then
					columnTop:SetPoint("TOPLEFT", after, "BOTTOMLEFT", 0, -rowTop)
				else
					columnTop:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 6) -- (as ShowTable's, under a header)
				end
				local label = ns.GridTable(content, columnTop, { item, noHeadings = after ~= nil,
					followRows = sectionRows, bandFrom = i - 1 }, kit)
				local point, relativeTo, relativePoint, x, y = label:GetPoint(1)
				label:SetPoint(point, relativeTo, relativePoint, x + TOGGLE_W, y)
				label:SetWidth(label:GetWidth() - TOGGLE_W)
				local box = CreateFrame("Frame", nil, content)
				box:SetPoint("TOPLEFT", columnTop, "TOPLEFT", 0, rowTop - ROW_H)
				box:SetSize(section.width, 0.001)
				box:Hide()
				block.box, after = box, box
				if unit then
					local function Toggle()
						SectionState.Save(block.state, not block.state.open)
						Relayout()
						Layout()
					end
					-- (Search finding a part opens its frame's block, and the tab.
					-- searchAlways: closed, its rows still count, or /cine find
					-- row:unitPartPlayerName found nothing, 2026-11-17.)
					box.searchAlways = true
					box.openSection = function()
						SectionState.Save(block.state, true)
						section.body.openSection()
					end
					local plus = CreateFrame("Button", nil, content)
					plus:SetSize(16, 16)
					plus:SetPoint("LEFT", columnTop, "TOPLEFT", 0, rowTop - ROW_H / 2)
					block.icon = plus:CreateTexture(nil, "ARTWORK")
					block.icon:SetAllPoints()
					plus:SetScript("OnClick", Toggle)
					Tooltip(plus, L["Shows or hides its parts."])
					local name = CreateFrame("Button", nil, content)
					name:SetPoint("TOPLEFT", label, "TOPLEFT", 0, 4)
					name:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 0, -4)
					name:SetScript("OnClick", Toggle)
					Tooltip(name, (item.tip and item.tip .. "\n\n" or "") .. L["Click to show or hide its parts."])
					local before = Widgets()
					local y, same = 0, unit.same
					unit.keys = {}
					if same then
						local check = Check(content, same, L["Same as target"],
							L["Shows the same parts as the Target rows."], function(value)
							ns.GetDB()[same] = value
							if not value then
								ns.CopyTargetParts(unit.unit, unit.keys)
							end
							ns.ApplyUnitFrameParts()
							Refresh()
						end)
						check:SetPoint("TOPLEFT", box, "TOPLEFT", INDENT - 4, 0)
						y = -ROW_H
					end
					local k = 0
					for _, part in ipairs(PARTS) do
						if ns.UnitHasPart(unit.unit, unit.parts, part[1]) then
							k = k + 1
							unit.keys[k] = part[1]
							local row = ns.UnitPartRow(content, labelWidth, ns.GRID_TABLE_LAYOUT, unit.unit, item.label,
								part, same, k + 1, INDENT)
							row:SetPoint("TOPLEFT", box, "TOPLEFT", labelWidth, y - (k - 1) * ROW_H)
							partRows[#partRows + 1] = row
						end
					end
					block.height = -y + k * ROW_H
					for object in pairs(Widgets()) do
						if not before[object] then object:SetParent(box) end
					end
				end
			end
			ns.GridDots(content, partRows)
			Relayout()
			return after
		end

		-- (tab: its tab's name, nil: heading. link: { page, tip, label }, a button
		-- to the page with the rest of its settings, right of its heading, named
		-- label or the page.)
		local function Section(page, heading, tab, link)
			local sectionRows = {}
			for _, item in ipairs(ns.COMBAT_SHOW) do
				if item.page == page and ns.OptionAvailable(item) and not item.key:find("^addon:")
					and not (item.auraFrames and not _G.CompactUnitFrame_UtilSetBuff) then
					sectionRows[#sectionRows + 1] = item
				end
			end
			if #sectionRows == 0 then
				return
			end
			-- (Whole frames first, then the parts drawn inside them, each kind under
			-- a heading of its own: the raid tab's Raid Frame Manager up with Players.)
			local whole, inside = {}, {}
			for _, item in ipairs(sectionRows) do table.insert(item.part and inside or whole, item) end
			if #whole > 0 and #inside > 0 then
				sectionRows = whole
				for _, item in ipairs(inside) do sectionRows[#sectionRows + 1] = item end
				sectionRows.kindHeadings = { L["Frames"], L["Parts"] }
			end
			local section = { key = page or "other", tab = tab or heading, width = SECTION_WIDTH }
			local frame = CreateFrame("Frame", nil, content)
			frame:SetSize(SECTION_WIDTH, 20)
			frame:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12, -10)
			frame.searchAlways = true
			section.frame = frame
			local title = Label(frame, "GameFontNormal", heading)
			title:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -3)
			-- (Room for the page's "?" right of the heading: on the first shown
			-- section's, the page's own title hidden on a banner icon's page: Layout.)
			section.helpSpot = CreateFrame("Frame", nil, frame)
			section.helpSpot:SetSize(18, 18)
			section.helpSpot:SetPoint("LEFT", title, "RIGHT", 6, 0)
			local after = section.helpSpot -- (what the next button goes right of)
			-- (No Raid » button or In use tag on the party frames' headings,
			-- 2026-11-16: Raid is a tab of the Party & Raid icon.)
			-- (link: one such, or a list of them, side by side.)
			for _, each in ipairs(link and (type(link[1]) == "table" and link or { link }) or {}) do
				local style = ns.StyleLink(frame, title, each[1], each[2], Tooltip, (each[3] or ns.PageLabel(each[1])) .. " »")
				style:SetPoint("LEFT", after, "RIGHT", 6, 0)
				after = style
			end
			section.body = CreateFrame("Frame", nil, content)
			section.body:SetPoint("TOPLEFT", frame, "TOPLEFT")
			section.body:SetSize(1, 1)
			section.body.searchAlways = true
			section.body.openSection = function() Pick(section) end
			frame.openSection = section.body.openSection
			local same
			if page == "rsparty" then
				same = Check(content, "raidStylePartySame", L["Same as raid frames"],
					L["Raid-style party frames follow the Raid tab's rows."], function(value)
					ns.GetDB().raidStylePartySame = value
					if not value then
						CopyRaidRows()
					end
					Refresh()
					Layout() -- (its grid folds away while ticked)
				end)
				-- (Right after its heading (past the "?"'s room), its words right
				-- of the box. Hidden with its tab.)
				same:SetParent(frame)
				local text = same.Text or same.text
				same:SetPoint("LEFT", after, "RIGHT", 8, 0)
				text:ClearAllPoints()
				text:SetPoint("LEFT", same, "RIGHT", 2, 1)
			end
			local before = Widgets()
			sectionRows.underHeader = true
			if page == "units" and ns.GRID_MENUS and ns.HasUnitFrameParts and ns.HasUnitFrameParts() then
				section.last = UnitBlocks(frame, sectionRows, heading, section)
			else
				section.last = ShowTable(content, frame, sectionRows, "Standard Frames", heading)
			end
			for object in pairs(Widgets()) do
				if not before[object] then
					object:SetParent(section.body)
					-- (Greyed while the raid frames' rows decide for them.)
					if same and object.Refresh and object.SetEnabled then
						local refresh = object.Refresh
						object.Refresh = function(self)
							refresh(self)
							if not OwnPartyRows() then
								self:SetEnabled(false)
							end
						end
					end
				end
			end
			-- (Under the action bars' rows: their key names hidden.)
			if page == "bars" then
				local keys = Check(content, "hideKeybinds", L["Hide keybinds"],
					L["Hides the key names on the action bar buttons (1, a-Q, s-2...), CineMode or not."],
					function(value)
						ns.GetDB().hideKeybinds = value
						ns.ApplyHideKeybinds()
					end)
				keys:SetParent(section.body)
				keys:SetPoint("TOPLEFT", section.last, "BOTTOMLEFT", -4, -8)
				local macros = Check(content, "hideMacroText", L["Hide macro names"],
					L["Hides the macro names on the action bar buttons, CineMode or not."],
					function(value)
						ns.GetDB().hideMacroText = value
						ns.ApplyHideKeybinds()
					end)
				macros:SetParent(section.body)
				macros:SetPoint("TOPLEFT", keys, "BOTTOMLEFT", 0, 0)
				local book = Check(content, "barsWithSpellbook", L["Show while the spellbook is open"],
					L["Keeps your action bars up while the spellbook or macros window is open."])
				book:SetParent(section.body)
				book:SetPoint("TOPLEFT", macros, "BOTTOMLEFT", 0, 0)
				section.last = book
			end
			-- (The breath bar's look and hiding it: the Timers icon's Breath Bar tab, 2026-11-16.)
			sections[#sections + 1] = section
		end
		local SECTIONS = {
			-- (Their look: the Unit Frames icon's Style tab.)
			{ "units", L["Unit frames"], L["UF"] }, -- (its sub-tab: UF)
			-- (Your health and resource bars under your character: on the Unit frames tab too.
			-- Kept up while you recover: the Unit Frames icon's Keep up tab.)
			{ "prd", L["Personal Resource Display"], L["PRD"] },
			-- (Your cast bar: a sub-tab of Unit Frames' Show in too, its look the Cast Style tab's, 2026-11-16.)
			{ "playercast", L["Your cast bar"], L["Cast bar"] },
			{ "bars", L["Action bars"] }, { "buffs", L["Buffs and debuffs"] }, { "combat", L["Trackers"] },
			-- (The chat window's row: the Chat icon's Show in tab.)
			{ "chat", L["Chat window"] },
			{ "interface", L["Info and menus"] }, { "minimap", L["Minimap"] }, { "quests", L["Quest tracker"] },
			{ "party", L["Party frames (not raid-style)"], L["Party"] },
			-- (Their look: the Party & Raid icon's Raid Style tab, RaidStyle.lua.)
			{ "raid", L["Raid frames"], L["Raid"] },
			-- (On the Party tab too, under the not raid-style ones.)
			{ "rsparty", L["Party frames (raid-style)"], L["Party"] },
			-- (Game settings that mark your character: Self Highlight, Effects.lua. On the Unit frames tab too.)
			{ "highlight", L["Highlight"] },
			{ false, L["Other"] }, -- (any row not given a section)
		}
		-- (The page's "?" by a section's heading says what that section is for: Layout.)
		local SECTION_TIPS = {
			units = L["CineMode hides the unit frames: pick which show, and when."],
			prd = L["CineMode hides your personal resource display: pick which parts show, and when."],
			playercast = L["CineMode hides your cast bar: pick when it shows."],
			bars = L["CineMode hides the action bars: pick which show, and when."],
			buffs = L["CineMode hides your buffs and debuffs: pick when they show."],
			combat = L["CineMode hides timers, meters and cooldowns: pick which show, and when."],
			chat = L["CineMode hides the chat window: pick when it shows."],
			interface = L["CineMode hides info frames and menus: pick which show, and when."],
			minimap = L["CineMode hides the minimap: pick which parts show, and when."],
			quests = L["CineMode hides the quest tracker: pick when it shows."],
			party = L["CineMode hides the party frames: pick when they show."],
			raid = L["CineMode hides the raid frames: pick when they show."],
			rsparty = L["CineMode hides the raid-style party frames: pick when they show."],
			highlight = L["CineMode hides your character's highlight: pick when it shows."],
			other = L["CineMode hides these frames: pick which show, and when."],
		}
		for _, section in ipairs(SECTIONS) do
			Section(section[1] or nil, section[2], section[3], section[4])
			local made = sections[#sections]
			if made and made.key == (section[1] or "other") then made.helpTip = SECTION_TIPS[made.key] end
		end
		local list, tabFrames, base = {}
		for _, section in ipairs(sections) do
			local tab
			for _, each in ipairs(tabs) do
				if each.label == section.tab then tab = each end
			end
			if not tab then
				tab = { label = section.tab, sections = {} }
				tabs[#tabs + 1] = tab
				list[#list + 1] = { section.tab }
			end
			tab.sections[#tab.sections + 1] = section
		end
		panel, tabFrames, ShowTab, base = ns.FolderTabs(content, list, function(i) Pick(tabs[i].sections[1]) end, nil,
			SECTION_WIDTH + 8)
		-- (Each section is picked by its icon in the hub, HUD_ICONS: the tabs
		-- shown only as an icon's sub-tabs, Layout.)
		for _, tab in ipairs(tabFrames) do tab:Hide() end
		subTabs = tabFrames
		-- (A section's page has no title shown, nor switch: its table at the
		-- top, under its icon's tabs if it has them.)
		function PlaceTop()
			panelTop:ClearAllPoints()
			local tabsNow = content.pageTabs
			-- (Room above for the sub-tabs, where they show.)
			local below = -12 - (subTabsShown and (tabFrames.height or 0) + 4 or 0)
			if tabsNow then
				panelTop:SetPoint("TOPLEFT", tabsNow.panel, "BOTTOMLEFT", 8, below)
			else
				panelTop:SetPoint("TOPLEFT", content, "TOPLEFT", 16, below)
			end
		end
		hudNote = Label(content, "GameFontHighlight", L["Each kind of frame has an icon above, and its Show in tab " ..
			"says when those frames show in CineMode, a row each. This switch turns all of them on or off at once."])
		hudNote:SetPoint("TOPLEFT", lastCheck, "BOTTOMLEFT", 6 - lastIndent, -16)
		hudNote:SetWidth(SECTION_WIDTH - 12)
		hudNote:SetWordWrap(true)
		hudNote:Hide()
		-- Every page of the hub, under the note (2026-11-16): each icon (its
		-- picture and name, a link to it), its other tabs beside it as links,
		-- wrapping. Made the first time the HUD icon shows, the hub's icons all in.
		local LIST_TABS = { ["HUD:units"] = "units", ["HUD:party"] = "party", ["HUD:bars"] = "bars",
			["HUD:chat"] = "chat", ["HUD:minimap"] = "minimap", ["HUD:quests"] = "quests", ["HUD:buffs"] = "buffs",
			["HUD:combat"] = "timers", ["Mouseover groups"] = "mouse", ["Nameplates"] = "plates",
			["Nameplate Names"] = "names" }
		-- (What each icon is for, under its name: its Show in tab's tip, else these.)
		local LIST_NOTES = { ["HUD:interface"] = L["The XP bar, bags, micro menu and the like: when they show."],
			["Combat Text Style"] = L["The damage and healing numbers over heads: how they look."] }
		-- (The cards: StylePages.lua's ns.MakeHubCards, the Visions hub's General page's too.)
		function MakeHudList()
			-- (In the hub's groups, each under its name: Heads-up, Overhead, Info.)
			local groups, entries = {}
			for _, icon in ipairs(ns.HubIcons("UI Manager")) do
				if not (groups[#groups] and groups[#groups][1] == icon.band) then
					entries = {}
					groups[#groups + 1] = { icon.band, entries }
				end
				if icon.name ~= "HUD:hud" then
					local key = LIST_TABS[icon.name]
					local tabs, chips = key and ns.ShowInTabs(key) or {}, {}
					for i, tab in ipairs(tabs) do
						if i > 1 then chips[#chips + 1] = { tab[1], tab[2] } end
					end
					entries[#entries + 1] = { label = icon.label, texture = icon.texture, open = icon.name, tabs = chips,
						note = LIST_NOTES[icon.name] or (tabs[1] and tabs[1][3]) or "", state = icon.on }
				end
			end
			hudList = ns.MakeHubCardGroups(content, groups, SECTION_WIDTH - 12)
			hudList:SetPoint("TOPLEFT", hudNote, "BOTTOMLEFT", 0, -18)
			FitContentHeight(content)
		end
		PlaceTop()
		panel:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
		-- (On panelTop, not the panel: the panel's bottom hangs on the rows under them.)
		base:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
		-- (Addon Frame Links for the unit frames: the Unit Frames icon's Frame
		-- Links tab, PersonalResources.lua, 2026-11-16.)
		Layout()

		canvas:SetScript("OnShow", PageShown(function()
			Refresh()
			Layout() -- (as last left, once the settings have loaded)
		end, content))
	end
	MakeHud = lazyPages.Add(canvas, "HUD", MakeBody)
	-- (Made ahead at a quiet moment, with the other slow pages: lazyPages.StartAhead.)
	lazyPages.StartAhead()
	-- (An icon for each section with rows on this client, as Section finds them.)
	local function HasRows(key)
		for _, item in ipairs(ns.COMBAT_SHOW) do
			if (item.page or "other") == key and ns.OptionAvailable(item) and not item.key:find("^addon:")
				and not (item.auraFrames and not _G.CompactUnitFrame_UtilSetBuff) then
				return true
			end
		end
	end
	canvas.hubTabs = {}
	for _, icon in ipairs(HUD_ICONS) do
		local has = icon.hud == true
		for _, key in ipairs(icon.keys) do has = has or HasRows(key) or false end
		if has then
			canvas.hubTabs[#canvas.hubTabs + 1] = {
				name = IconName(icon), label = icon.label, section = icon.section, before = icon.before, own = true,
				showIn = icon.tabs,
				noDot = not icon.hud, switchLabel = "HUD", tabOf = icon.tabOf,
				-- (its own picture, 2026-11-16; the HUD's and Other's your faction's banner)
				icon = icon.icon or function()
					return UnitFactionGroup("player") == "Horde" and "Interface\\Icons\\INV_BannerPVP_01"
						or "Interface\\Icons\\INV_BannerPVP_02"
				end,
				onSelect = function()
					MakeHud("its icon picked")
					if ns.PickFramesIcon then ns.PickFramesIcon(icon) end
				end,
			}
		end
	end
	canvas:Hide()
	RegisterSubpage(canvas, L["Standard Frames"], L["HUD"])
end

-- Sub-page: chat bubbles (where they show; how they look: BubbleStyle.lua).
local function CreateBubblesPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Chat Bubbles"])
	-- (The Chat icon's Bubbles tab, 2026-11-16: its tabs over the title; their
	-- look the Bubble Style tab beside it.)
	local tabs = ns.PageTabs(content, ns.ShowInTabs("chat"), ns.ShowInIndex("chat", "Chat bubbles"))
	title:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 8, -14)

	local subtitle = PageIntro(content, title,
		L["Pick where chat bubbles show."])

	local function Changed() if ns.ApplyBubbles then ns.ApplyBubbles() end end

	local switch = PageSwitch(content, "handleBubbles", L["Enable Page"],
		L["Shows chat bubbles where this page says; off uses the game's own settings."], subtitle, Changed)
	-- Show in: a row per kind of bubble, as the Standard Frames page's
	-- (GridRows.lua): where and when each shows.
	local stack = Stack(switch, "check")
	local bubbleHeader = stack:Header(content, L["Show in"])
	stack:Help(content, L["Pick where and when each kind of bubble shows."])
	local bubbleRows = { opts = { quiet = true, cam = true, anyFight = true }, underHeader = true }
	for _, bubble in ipairs({ { "Say", L["Say"] }, { "Yell", L["Yell"] }, { "Party", L["Party"] }, { "NPC", L["NPCs"] } }) do
		local alwaysKey = "bubbles" .. bubble[1] .. "Always"
		bubbleRows[#bubbleRows + 1] = { key = "bubble:" .. bubble[1], label = bubble[2], alwaysKey = alwaysKey,
			alwaysOn = function() return ns.GetDB()[alwaysKey] end,
			setAlways = function(value) ns.GetDB()[alwaysKey] = value end,
			alwaysTip = L["These bubbles show everywhere, in fights and out."],
			apply = Changed }
	end
	stack:Continue(ShowTable(content, bubbleHeader, bubbleRows, L["Chat bubbles"]), "label")

	-- Custom bubbles: ones Cinematic draws itself, looking like the game's.
	-- Speech from behind you (Speech.lua): says and yells with no bubble on
	-- screen, shown low on the screen. Keep bubbles on screen (Bubbles.lua):
	-- retail's drawn again below the bar, classic's moved.
	stack:Header(content, L["Custom bubbles"])
	stack:Help(content, L["Cinematic draws its own bubbles for speech whose game bubble you can't see."])
	local offScreen = stack:Add(Check(content, "chatSpeechBehind", L["Show off-screen bubbles"],
		L["Shows speech from someone off screen in a bubble low on the screen."]), "check")
	GreyUnless(offScreen, function(db) return db.chatPeek and db.chatHideBubbled end)
	offScreen:HookScript("OnClick", Refresh) -- (greys out / enables Show emotes too)
	-- (How they look: a button right of it, to the Style hub's Chat bubbles page.)
	local offScreenStyle = ns.PanelButton(content)
	offScreenStyle:SetSize(70, 20)
	offScreenStyle:SetText(L["Style"])
	offScreenStyle:SetPoint("LEFT", offScreen.Text or offScreen.text, "RIGHT", 16, 0)
	Tooltip(offScreenStyle, L["Opens the Chat Bubble Style page: how off-screen bubbles look and where they show."])
	offScreenStyle:SetScript("OnClick", function() ns.OpenOptions("Bubble Style") end)
	local emotes = stack:Add(Check(content, "chatSpeechEmotes", L["Show emotes too"],
		L["Shows emotes in the off-screen bubbles too, instead of in chat."]), "check")
	GreyUnless(emotes, function(db) return db.chatPeek and db.chatHideBubbled and db.chatSpeechBehind end)
	stack:Add(Check(content, "bubblesOffTop", L["Keep bubbles on screen"],
		L["Moves bubbles at the very top of the screen down where you can read them."]), "check")

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Chat bubbles", L["Chat Bubbles"])
end

-- Sub-page: quality of life, small helpers grouped by section (General, ...).
-- Sections and options only for one client show only there.
local function CreateQualityPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["General"])
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title, L["Small helpers for getting around the world."])
	local switch = PageSwitch(content, "handleQuality", L["Enable Page"],
		L["Turns all the Quality of Life helpers on or off."], subtitle, function()
		if ns.RefreshTalentLink then ns.RefreshTalentLink() end
		if ns.RefreshTalentCalc then ns.RefreshTalentCalc() end
	end)

	local stack = Stack(switch, "check")
	-- (Campfire.lua.)
	do
		local sit = stack:Add(Check(content, "campfireSitButton", L["Campfire button"],
			L["Hover a campfire to show a button that sits you down by it."]), "check")
		sit:HookScript("OnClick", Refresh) -- grey out / enable the options below
		local EMOTE_TIP = L["What the Campfire button does; with several ticked, one is picked at random."]
		-- (on one row, each right of the one before)
		local previous
		for _, emote in ipairs({ { "campfireSit", L["Sit"] }, { "campfireKneel", L["Kneel"] },
			{ "campfireLie", L["Lie down"] } }) do
			local check = Check(content, emote[1], emote[2], EMOTE_TIP)
			if previous then
				check:SetPoint("LEFT", previous.Text or previous.text, "RIGHT", 16, 0)
			else
				stack:Add(check, "check", 24)
			end
			GreyUnless(check, function(db) return db.campfireSitButton end)
			previous = check
		end
		local reach = stack:Add(Slider(content, "campfireReach", L["Cursor reach from the middle"], 5, 50, 1,
			L["%d%%"], 100), "slider", 24)
		Tooltip(reach, L["How close to the middle of the screen the cursor must be on a campfire."])
		GreyUnless(reach, function(db) return db.campfireSitButton end)
		local grow = stack:Add(Check(content, "campfireReachGrow", L["Reach widens the longer you hover"],
			L["The longer you hover a campfire, the further from the middle it may be."]), "check", 24)
		GreyUnless(grow, function(db) return db.campfireSitButton end)
		local NAMES_TIP = L["Words in a name that mark it as a campfire, separated by commas."]
		local namesLabel = Label(content, "GameFontHighlightSmall", L["Campfire names:"])
		stack:Add(namesLabel, "label", 24)
		local names = stack:Add(ListBox(content, "campfireNames", 300, NAMES_TIP), "box", 24)
		GreyUnless(names, function(db) return db.campfireSitButton end)
		-- (Only where the game has Camp Benefits: WoW Forever.)
		if ns.HasCampBenefits and ns.HasCampBenefits() then
			local stand = stack:Add(Check(content, "campfireStandUp", L["Stand up once you get Camp Benefits"],
				L["Stands you up once you get Camp Benefits."]), "check", 24)
			GreyUnless(stand, function(db) return db.campfireSitButton end)
		end
	end
	-- (DragEquip.lua.)
	stack:Add(Check(content, "dragEquipCharacter", L["Open the character window when dragging gear out of your bags"],
		L["Opens the character window when you drag gear out of your bags."]
		.. (issecretvalue and "\n\n" .. L["Off by default here: it can cause harmless errors in error catchers."] or "")), "check")
	-- (TalentLink.lua; WoW Forever only.)
	if not ns.isRetail then
		stack:Add(Check(content, "talentLink", L["Talents button when inspecting someone"],
			L["Adds a button to view the talents of someone you inspect."],
			function(value)
				ns.GetDB().talentLink = value
				if ns.RefreshTalentLink then
					ns.RefreshTalentLink()
				end
			end), "check")
		-- (TalentCalc.lua.)
		stack:Add(Check(content, "talentCalc", L["Talent calculator button on the talents window"],
			L["Adds a talent calculator button to your talents window to plan a build."],
			function(value)
				ns.GetDB().talentCalc = value
				if ns.RefreshTalentCalc then
					ns.RefreshTalentCalc()
				end
			end), "check")
	end
	-- (CenterPanels.lua.)
	stack:Add(Check(content, "centerPanels", L["Open windows in the middle of the screen"],
		L["Moves game windows away from the left edge so your character stays in view."]), "check")
	stack:Add(Check(content, "dragPanels", L["Drag windows to move them"],
		L["Lets you drag the game's windows to move them."]), "check")
	local putBack = ns.PanelButton(content)
	putBack:SetSize(160, 22)
	putBack:SetText(L["Put windows back"])
	Tooltip(putBack, L["Forget where you've dragged the windows to: each opens in its usual place again."]
		.. " " .. L["Quest Vision's list of replies and its bubble too."])
	putBack:SetScript("OnClick", function()
		if ns.ForgetPanelSpots then
			ns.ForgetPanelSpots()
		end
	end)
	stack:Add(putBack, "label", 24)
	-- (ChatCopy.lua.)
	stack:Add(Check(content, "chatCopyButton", L["Copy chat button"],
		L["Adds an icon to chat windows to copy their text."]), "check")
	local keepChat = stack:Add(Check(content, "chatHistory", L["Keep chat history"],
		L["Chat windows bring back their last lines after a reload or login."]), "check")
	keepChat:HookScript("OnClick", Refresh) -- grey out / enable the option below
	local chatTime = stack:Add(Check(content, "chatHistoryTime", L["Show the time on those lines"],
		L["Puts the time at the start of brought-back lines."]), "check", 24)
	GreyUnless(chatTime, function(db) return db.chatHistory end)
	-- (XpLeft.lua.)
	stack:Add(Check(content, "xpLeft", L["Show XP left to level"],
		L["Shows how much XP you still need for the next level."],
		function(value)
			KeyPut("xpLeft", value)
			if ns.RefreshXpLeft then ns.RefreshXpLeft() end
		end), "check")
	-- (Camera.lua.)
	local loginZoom = stack:Add(Check(content, "loginZoom", L["Reset the zoom on login and /reload"],
		L["The camera zooms to the distance below when you log in or reload."]), "check")
	loginZoom:HookScript("OnClick", Refresh) -- grey out / enable the slider below
	local loginDistance = stack:Add(Slider(content, "loginZoomDistance", L["Zoom to"], 2, 39, 0.5,
		L["%.1f yards"]), "slider", 24)
	Tooltip(loginDistance, L["The camera distance to start at."])
	GreyUnless(loginDistance, function(db) return db.loginZoom end)
	-- (Reload.lua.)
	stack:Add(Check(content, "reloadButton", L["Reload button on the screen"],
		L["A button at the top of the screen that reloads the UI in one click."]), "check")
	stack:Add(Check(content, "reloadKeepWindows", L["Keep windows open across a reload"],
		L["Reopens the windows you had open after a reload."]), "check")
	-- (On the CineMode page until 2026-11-13.)
	stack:Header(content, L["Combat text"])

	local combatText = Check(content, "hideCombatText", L["Hide combat text out of combat"],
		L["Hides floating damage and healing numbers in CineMode out of combat."])
	stack:Add(combatText, "check")

	-- (Hide all floating text, XP too: on the Style hub's Combat Text Style
	-- page since 2026-11-10, CombatTextStyle.lua.)

	-- The red error text at the top of the screen, in and out of fights
	-- (CineMode or not).
	stack:Header(content, L["Hide error messages"])

	local errorsInCombat = Check(content, "hideErrorsInCombat", L["In combat"],
		L["Hides the red error text while you're fighting."])
	stack:Add(errorsInCombat, "check")

	local errorsOutOfCombat = Check(content, "hideErrorsOutOfCombat", L["Out of combat"],
		L["Hides the red error text while you're out of combat."])
	stack:Add(errorsOutOfCombat, "check")
	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	-- (Quality of life's first page: "General" there.)
	RegisterSubpage(canvas, "General")

	-- (Not on retail, which has no ammo. Shown on every class; HunterAmmo.lua
	-- only runs on hunters.)
	if not ns.isRetail then
		canvas, content = CreateScrollPage()
		title = Label(content, "GameFontNormalLarge", L["Hunter"])
		title:SetPoint("TOPLEFT", 16, -16)
		switch = PageSwitch(content, "handleHunter", L["Enable Page"],
			L["Turns the Hunter helpers on or off."], title)
		stack = Stack(switch, "check")
		-- (Hunter.lua: Classic Era only. WoW Forever has the game's own setting.)
		if ns.isClassicEra then
			stack:Add(Check(content, "hunterRightClickShot", L["Right click attack also uses Auto-shot"],
				L["Right-clicking an enemy uses Auto Shot when it's far enough away."]), "check")
		end
		-- (HunterAmmo.lua.)
		stack:Add(Check(content, "hunterAmmoSort", L["Smallest ammo stack first after Clean Up Bags"],
			L["Moves the smallest ammo stack first after Clean Up Bags, so it's shot first."]), "check")
		stack:Add(Check(content, "hunterQuiverFill", L["Fill quiver button at vendors"],
			L["Adds a Fill button at vendors that fills your quiver with ammo."]), "check")
		-- (Pet happiness, Frames.lua. Off to start with.)
		local pet = Check(content, "petUnhappyShow", L["Show the pet frame when your pet isn't happy"],
			L["Keeps your pet frame up while your pet isn't happy."])
		stack:Add(pet, "check")
		pet:HookScript("OnClick", Refresh) -- grey out / enable the option below
		local petCam = Check(content, "petUnhappyHideInCam", L["Hide in camera modes"],
			L["The pet frame fades with the UI while a camera mode runs."])
		stack:Add(petCam, "check", 16)
		GreyUnless(petCam, function(db) return db.petUnhappyShow end)
		canvas:SetScript("OnShow", PageShown(Refresh, content))
		canvas:Hide()
		RegisterSubpage(canvas, "Hunter")
	end

	-- Addon Support: a section for each addon Cinematic has a rule of its own
	-- for, shown only with that addon loaded; the page only with one of them.
	-- (Here, not a function of its own: this file's near the 200 locals cap.)
	do
		local function RefreshPlates()
			if ns.RefreshClassIcon and C_NamePlate and C_NamePlate.GetNamePlates then
				for _, plate in ipairs(C_NamePlate.GetNamePlates()) do ns.RefreshClassIcon(plate) end
			end
		end
		local SUPPORT = {
			-- (Support/Questie.lua; the icons' pin in PlateParts' RefreshQuestIcon.)
			{ addon = "Questie", label = "Questie", build = function(page, list)
				list:Add(Check(page, "questieMoveIcons", L["Move Questie's nameplate icons"],
					L["Moves Questie's quest icons beside the name, where Cinematic's quest mark goes."], function(value)
						KeyPut("questieMoveIcons", value)
						RefreshPlates()
					end), "check")
			end },
			-- (Its Nameplates' Show quest icons; the mark's pin in PlateParts' ns.EQoLMark.)
			{ addon = "EnhanceQoL", label = "EnhanceQoL", build = function(page, list)
				list:Add(Check(page, "eqolMoveIcons", L["Move EnhanceQoL's nameplate quest marks"],
					L["Keeps EnhanceQoL's quest marks up, beside the name where Cinematic's would go."],
					function(value)
						KeyPut("eqolMoveIcons", value)
						RefreshPlates()
					end), "check")
			end },
		}
		local have = {}
		for _, each in ipairs(SUPPORT) do
			-- (Will load: built as Cinematic loads, before addons later in the alphabet are in.)
			if ns.AddOnWillLoad(each.addon) then have[#have + 1] = each end
		end
		if #have > 0 then
			canvas, content = CreateScrollPage()
			title = Label(content, "GameFontNormalLarge", L["Addon Support"])
			title:SetPoint("TOPLEFT", 16, -16)
			local intro = PageIntro(content, title, L["Settings for how Cinematic works with your other addons."])
			switch = PageSwitch(content, "handleAddonSupport", L["Enable Page"],
				L["Turns Cinematic's support for your other addons on or off."], intro, RefreshPlates)
			stack = Stack(switch, "check")
			-- (Addon Frames' tab row, Custom Support its last tab, picked here,
			-- 2026-11-16: one row for the two pages. The others open Addon Frames
			-- at theirs. Addon Frames made by now: its Custom Support tab shown.)
			if extrasPanel and extrasPanel.PickAddonTab then
				extrasPanel.supportTab:Show()
				local width = extrasPanel.tabsWidth
				local row = CreateFrame("Frame", nil, content)
				local tabsPanel, ShowTab, tabsBase, tabsHeight, _
				tabsPanel, _, ShowTab, tabsBase, tabsHeight = ns.FolderTabs(content, {
					{ L["Loaded"], L["The addons loaded now: their frames, and the ones you added."] },
					{ L["Find frames"], L["Find other addons' frames to fade: search, hover, or Smart Find."] },
					{ L["Not running"], L["Addons installed but not loaded, and the ones supported but not installed."] },
					{ L["Support files"], L["Addons that replace the game's frames, and which to use where two do."] },
					{ L["Custom Support"], L["Settings for each supported addon you have installed."] },
				}, function(i)
					ShowTab(5)
					if i ~= 5 then extrasPanel.PickAddonTab(i) end
				end)
				row:SetSize(width, tabsHeight + 6)
				stack:Add(row, "label")
				tabsBase:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -tabsHeight)
				tabsPanel:SetPoint("TOPLEFT", tabsBase, "TOPLEFT")
				tabsPanel:SetSize(width, 1)
				ShowTab(5)
			end
			for _, each in ipairs(have) do
				stack:Header(content, each.label)
				each.build(content, stack)
			end
			canvas:SetScript("OnShow", PageShown(Refresh, content))
			canvas:Hide()
			RegisterSubpage(canvas, "Addon Support")
		end
	end
end

-- Sub-page: fishing (casting with right-click or a gamepad button, the cast bar).
local function CreateFishingPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Fishing"])
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title,
		L["Casting and catching, with the mouse or a gamepad, CineMode or not."])

	local switch = PageSwitch(content, "handleFishing", L["Enable Page"],
		L["Right-click casts Fishing again and the Fishing cast bar hides, as this page says."], subtitle)
	local stack = Stack(switch, "check")
	stack:Header(content, L["Casting"])
	stack:Add(Check(content, "hideFishingCastBar", L["Hide the Fishing cast bar"],
		L["Hides your cast bar while you're fishing."]),
		"check")
	local recast = stack:Add(Check(content, "fishRightClickCast", L["Right-click to cast"],
		L["With a fishing pole equipped, right-click in the world casts Fishing."]), "check")
	recast:HookScript("OnClick", Refresh) -- grey out / enable the options below
	-- (They apply to the gamepad button too.)
	local function IfRecast(db) return db.fishRightClickCast or (C_GamePad ~= nil and db.fishGamepadCast) end
	local delay = stack:Add(Slider(content, "fishRecastDelay", L["Wait after a cast ends"], 0, 3, 0.1,
		L["%.1f sec"]), "slider")
	Tooltip(delay, L["How long after a cast ends before right-click casts again."])
	GreyUnless(delay, IfRecast)
	local missPause = stack:Add(Slider(content, "fishMissPause", L["Pause after a missed cast"], 0, 30, 1,
		function(value) return value == 0 and L["Off"] or (L["%d sec"]):format(value) end), "slider")
	Tooltip(missPause, L["After a failed cast, right-click goes back to normal for this long."])
	GreyUnless(missPause, IfRecast)
	stack:Add(Check(content, "fishRightClickReel", L["Reel in with same key/click"],
		L["Reels in with the same click or key you cast with."]), "check")

	-- Gamepad mode: a gamepad button does what right-click does.
	if C_GamePad then
		local padCast = stack:Add(Check(content, "fishGamepadCast", L["Gamepad: a button casts too"],
			L["In gamepad mode, the button below casts Fishing like right-click does."]), "check")
		padCast:HookScript("OnClick", Refresh) -- grey out / enable the button choice (and the options above)
		local function IfPadCast(db) return db.fishGamepadCast end
		local PAD_BUTTONS = {
			-- (By where the button sits: pads print different letters there.)
			{ value = "PAD3", text = L["Left face button (Xbox X)"] },
			{ value = "PAD4", text = L["Top face button (Xbox Y)"] },
			{ value = "PAD1", text = L["Bottom face button (Xbox A)"] },
			{ value = "PAD2", text = L["Right face button (Xbox B)"] },
		}
		local BUTTON_TIP = L["The gamepad button that casts Fishing."]
		local button = Dropdown(content, "fishGamepadKey", PAD_BUTTONS, 200)
		if button then
			stack:Add(button, "dropdown", 24)
			Tooltip(button, BUTTON_TIP)
			GreyUnless(button, IfPadCast)
		else
			for _, choice in ipairs(PAD_BUTTONS) do
				GreyUnless(stack:Add(Choice(content, "fishGamepadKey", choice.value, choice.text, BUTTON_TIP),
					"check", 24), IfPadCast)
			end
		end
	end

	-- (Camera.lua: the volumes go up as a Fishing cast starts, back after.)
	stack:Header(content, L["Sound"])
	local volume = stack:Add(Check(content, "fishVolume", L["Louder while fishing"],
		L["Turns the game's volume up while your bobber is out, so you hear a bite."]), "check")
	volume:HookScript("OnClick", function()
		if not ns.db.fishVolume and ns.FishVolumeRestore then ns.FishVolumeRestore() end
		Refresh()
	end)
	local function IfVolume(db) return db.fishVolume end
	local master = stack:Add(Slider(content, "fishMasterVolume", L["Master volume"], 0, 100, 5, "%d%%", 100),
		"slider")
	Tooltip(master, L["The game's master volume while you fish."])
	GreyUnless(master, IfVolume)
	local effects = stack:Add(Slider(content, "fishSfxVolume", L["Sound effects volume"], 0, 100, 5, "%d%%", 100),
		"slider")
	Tooltip(effects, L["The game's sound effects volume while you fish: the splash of a bite is a sound effect."])
	GreyUnless(effects, IfVolume)
	local background = stack:Add(Check(content, "fishVolumeBackground", L["Sound in the background too"],
		L["Keeps the game's sound playing in the background while you fish."]), "check", 16)
	GreyUnless(background, IfVolume)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Fishing")
end

-- Sub-page for WoW Forever's gamepad mode: its action bars and button hints,
-- with the Standard Frames page's columns.
local function CreateGamepadPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Gamepad Frames"])
	-- (The Action Bars icon's Gamepad tab, 2026-11-16: its tabs over the title.)
	local tabs = ns.PageTabs(content, ns.ShowInTabs("bars"), ns.ShowInIndex("bars", "Gamepad"))
	title:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 8, -14)

	local subtitle = PageIntro(content, title,
		L["CineMode hides the gamepad's bars, button hints and reticle: pick when they show."])

	local rows = {}
	for _, item in ipairs(ns.COMBAT_SHOW) do
		if item.page == "gamepad" then
			rows[#rows + 1] = item
		end
	end
	local switch = PageSwitch(content, "handleGamepad", L["Enable Page"],
		L["CineMode hides the gamepad's frames, and shows them only when their rows say."], subtitle, function()
		if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
	end)
	rows.underHeader = true
	-- (Everything below on a panel, as the HUD page's sections are, its
	-- heading at the top: 2026-11-16. The panel itself: at the page's end.)
	local panelHeading = Label(content, "GameFontNormal", L["Gamepad frames"])
	panelHeading:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 14, -14)
	local lastRow = ShowTable(content, panelHeading, rows, "Gamepad")

	-- The prompt sits on a nameplate, not a frame of its own: a setting for
	-- the plates' fade rather than a row.
	local prompt = Check(content, "showInteractPrompt", L["Show the interact prompt (X)"],
		L["Keeps the gamepad's interact prompt up in CineMode as nameplates fade."])
	prompt:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", -2, -16)
	local press = Check(content, "gamepadPressReveal", L["Show the action bars when you press a button"],
		L["Pressing a gamepad button brings the action bars up."])
	press:SetPoint("TOPLEFT", prompt, "BOTTOMLEFT", 0, -2)
	press:HookScript("OnClick", Refresh) -- grey out / enable the options below

	-- Which buttons count: a list that opens and closes (+ / -), closed at first.
	local IfPress = function(db) return db.gamepadPressReveal end
	local listToggle = CreateFrame("Button", nil, content)
	listToggle:SetSize(260, 20)
	listToggle:SetPoint("TOPLEFT", press, "BOTTOMLEFT", 28, -4)
	listToggle.icon = listToggle:CreateTexture(nil, "ARTWORK")
	listToggle.icon:SetSize(14, 14)
	listToggle.icon:SetPoint("LEFT", 0, 0)
	listToggle.text = listToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	listToggle.text:SetPoint("LEFT", listToggle.icon, "RIGHT", 4, 0)
	listToggle.text:SetText(L["Buttons that show them"])
	listToggle:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
	listToggle:GetHighlightTexture():SetAllPoints(listToggle.icon)
	Tooltip(listToggle, L["Show or hide the list of buttons that bring the action bars up."])
	-- The list sits in a box that's empty and flat while closed, so what
	-- comes below moves up.
	local BUTTON_COLUMN, BUTTON_ROW = 200, 24
	local list = CreateFrame("Frame", nil, content)
	list:SetPoint("TOPLEFT", listToggle, "BOTTOMLEFT", 0, -2)
	list:SetSize(BUTTON_COLUMN * 2, 1)
	local rowsPerColumn = math.ceil(#ns.GAMEPAD_BUTTONS / 2)
	for i, item in ipairs(ns.GAMEPAD_BUTTONS) do
		-- (With the game's own name for it alongside, as your pad labels it.)
		local gameText = ns.PadButtonText(item.key)
		local label = gameText ~= "" and ("%s  |cff808080%s|r"):format(item.label, gameText) or item.label
		local check = Check(list, "gamepadPressButtons", label, nil, function(value)
			ns.GetDB().gamepadPressButtons[item.key] = value
		end)
		local column, row = math.floor((i - 1) / rowsPerColumn), (i - 1) % rowsPerColumn
		check:SetPoint("TOPLEFT", list, "TOPLEFT", column * BUTTON_COLUMN, -row * BUTTON_ROW)
		check.Refresh = function(self) self:SetChecked(ns.IsPadButtonOn(item.key)) end
		GreyUnless(check, IfPress)
	end
	RecordKey(content, "gamepadPressButtons") -- (for the page's Reset)
	local listOpen = false
	local function ShowList()
		listToggle.icon:SetTexture(listOpen and "Interface\\Buttons\\UI-MinusButton-Up"
			or "Interface\\Buttons\\UI-PlusButton-Up")
		list:SetShown(listOpen)
		list:SetHeight(listOpen and rowsPerColumn * BUTTON_ROW or 1)
	end
	ShowList()
	listToggle:SetScript("OnClick", function()
		listOpen = not listOpen
		ShowList()
		FitContentHeight(content)
	end)

	-- The action bars' own fade times (every time they show, not just for presses).
	-- (From the list, which sits 26 right of the column edge: the press
	-- check's 2 left and the toggle's 28.)
	local stack = Stack(list, "label")
	stack.indent = 26
	stack:Header(content, L["Action bar fading"])
	local stay = stack:Add(Slider(content, "gamepadPressHold", L["Stay after a press"], 0, 10, 0.5, L["%.1f sec"]),
		"slider")
	Tooltip(stay, L["How long the action bars stay after your last button press."])
	GreyUnless(stay, function(db) return db.gamepadPressReveal end)
	local fadeIn = stack:Add(Slider(content, "gamepadBarsFadeIn", L["Fade in time"], 0, 3, 0.1, L["%.1f sec"]),
		"slider")
	Tooltip(fadeIn, L["How long the gamepad action bars take to fade in."])
	local fadeOut = stack:Add(Slider(content, "gamepadBarsFadeOut", L["Fade out time"], 0, 3, 0.1, L["%.1f sec"]),
		"slider")
	Tooltip(fadeOut, L["How long the gamepad action bars take to fade out."])

	stack:Header(content, L["Settings window"])
	stack:Add(Check(content, "forceReloadOnSettingsExit", L["Force reload on Settings exit"],
		L["Reloads the UI when you close Settings, to avoid a gamepad-mode freeze."]), "check")
	local lastSetting = stack:Add(Check(content, "hideMinimapButtonGamepad", L["Hide the minimap button in gamepad mode"],
		L["Hides the minimap button in gamepad mode, where it can freeze the game."],
		function(value)
			ns.GetDB().hideMinimapButtonGamepad = value
			if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		end), "check")

	-- The panel behind it all (the HUD page's sections' look: a dark fill, a
	-- thin grey edge), from its heading to the last setting, under them.
	local panel = CreateFrame("Frame", nil, content)
	panel:SetFrameLevel(content:GetFrameLevel())
	panel:SetPoint("TOPLEFT", panelHeading, "TOPLEFT", -12, 12)
	panel:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	panel:SetPoint("BOTTOM", lastSetting, "BOTTOM", 0, -12)
	local fill = panel:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(0.12, 0.12, 0.13, 0.9)
	for _, sides in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
		{ "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local line = panel:CreateTexture(nil, "BORDER")
		line:SetColorTexture(0.42, 0.42, 0.42, 1)
		line:SetPoint(sides[1])
		line:SetPoint(sides[2])
		if sides[1] == "TOPLEFT" and sides[2] == "TOPRIGHT" or sides[1] == "BOTTOMLEFT" then
			line:SetHeight(1)
		else
			line:SetWidth(1)
		end
	end

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Gamepad", L["Gamepad Frames"])
end

-- Folder tabs (Heal Vision's and the Standard Frames, Unit Frames and
-- Nameplate & Names pages'): the picked one taller, lit, a gold top, in the
-- panel's colour with no line between, so they look one piece; the rest dark
-- behind. The panel's top edge runs either side of the picked tab. list:
-- { text, tip } each; onClick(i); width: each tab's (nil: to fit its text);
-- maxWidth: past it they wrap onto rows, the picked one's row next to the
-- panel (nil: one row). Gives the panel (the caller places and sizes it), the
-- tabs (hidden ones are left out), Show(i) to light tab i and lay out those
-- shown, the base (the caller puts it at the panel's
-- top left: the bottom row's bottom left) and how high the tabs reach above it.
ns.FOLDER_TAB_HEIGHT = 20
function ns.FolderTabs(parent, list, onClick, width, maxWidth, onRightClick)
	local TAB_H, TAB_GAP = ns.FOLDER_TAB_HEIGHT, 3
	local PANEL_BG, TAB_BG = { 0.12, 0.12, 0.13, 0.9 }, { 0.04, 0.04, 0.05, 0.9 }
	local EDGE, DIM_EDGE = { 0.42, 0.42, 0.42, 1 }, { 0.22, 0.22, 0.22, 1 }
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetFrameLevel(parent:GetFrameLevel()) -- (under the settings on it)
	local function Line(frame, color)
		local line = frame:CreateTexture(nil, "BORDER")
		line:SetColorTexture(unpack(color))
		-- (Off the pixel grid: snapped, a line this thin can round to nothing
		-- on some rows, like the panel's bottom under the Keybinds rows.)
		if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(false) end
		if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
		return line
	end
	local panelBg = panel:CreateTexture(nil, "BACKGROUND")
	panelBg:SetAllPoints()
	panelBg:SetColorTexture(unpack(PANEL_BG))
	local leftEdge, rightEdge, bottomEdge = Line(panel, EDGE), Line(panel, EDGE), Line(panel, EDGE)
	leftEdge:SetPoint("TOPLEFT")
	leftEdge:SetPoint("BOTTOMLEFT")
	leftEdge:SetWidth(1)
	rightEdge:SetPoint("TOPRIGHT")
	rightEdge:SetPoint("BOTTOMRIGHT")
	rightEdge:SetWidth(1)
	bottomEdge:SetPoint("BOTTOMLEFT")
	bottomEdge:SetPoint("BOTTOMRIGHT")
	bottomEdge:SetHeight(1)
	local topLeft, topRight = Line(panel, EDGE), Line(panel, EDGE)
	topLeft:SetHeight(1)
	topRight:SetHeight(1)
	-- The panel's edges one screen pixel thick, whatever the scale (a fixed 1
	-- is less than a pixel in the settings), worked out each time it shows.
	local function EdgeThickness()
		local scale = panel:GetEffectiveScale()
		if not (PixelUtil and PixelUtil.GetPixelToUIUnitFactor and scale and scale > 0) then return end
		local px = math.max(1, PixelUtil.GetPixelToUIUnitFactor() / scale)
		leftEdge:SetWidth(px)
		rightEdge:SetWidth(px)
		bottomEdge:SetHeight(px)
		topLeft:SetHeight(px)
		topRight:SetHeight(px)
	end
	EdgeThickness()
	panel:HookScript("OnShow", EdgeThickness)
	local function PaintTab(tab, on)
		tab:SetHeight(on and TAB_H + 4 or TAB_H)
		tab.bg:SetColorTexture(unpack(on and PANEL_BG or TAB_BG))
		for _, side in ipairs({ tab.left, tab.right, tab.top }) do
			side:SetColorTexture(unpack(on and EDGE or DIM_EDGE))
		end
		if on then tab.top:SetColorTexture(1, 0.82, 0, 1) end
		tab.top:SetHeight(on and 2 or 1)
		local r, g, b = 1, 0.82, 0
		if on then r, g, b = 1, 1, 1 end
		tab.label:SetTextColor(r, g, b)
		tab.label:SetVertexColor(r, g, b) -- (one on Forever)
	end
	local tabs = {}
	for i, each in ipairs(list) do
		local tab = CreateFrame("Button", nil, parent)
		tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		tab.label:SetPoint("CENTER", 0, 1)
		tab:SetFontString(tab.label)
		tab:SetText(each[1])
		tab:SetSize(width or math.max(40, math.ceil(tab.label:GetStringWidth()) + 12), TAB_H)
		tab.bg = tab:CreateTexture(nil, "BACKGROUND")
		tab.bg:SetAllPoints()
		tab.left, tab.right, tab.top = Line(tab, EDGE), Line(tab, EDGE), Line(tab, EDGE)
		tab.left:SetPoint("TOPLEFT")
		tab.left:SetPoint("BOTTOMLEFT")
		tab.left:SetWidth(1)
		tab.right:SetPoint("TOPRIGHT")
		tab.right:SetPoint("BOTTOMRIGHT")
		tab.right:SetWidth(1)
		tab.top:SetPoint("TOPLEFT")
		tab.top:SetPoint("TOPRIGHT")
		local hover = tab:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.06)
		if each[2] then Tooltip(tab, each[2]) end
		-- (onRightClick(i): a right-click on a tab, its tip shown again after)
		if onRightClick then tab:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
		tab:SetScript("OnClick", function(self, button)
			if button ~= "RightButton" then return onClick(i) end
			onRightClick(i)
			if GameTooltip:IsOwned(self) and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
		end)
		tabs[i] = tab
		tab.shotSet, tab.shotIndex = tabs, i -- (PageShots.lua clicks through them)
	end
	-- The rows of the tabs shown (a caller can hide some), as many on each as
	-- fit (tab.row: its row's number).
	local rows
	local function Rows()
		-- (Fitted to their text: measured again each time, and when they'd
		-- run past maxWidth their padding shrinks first, so they keep to one
		-- row while the words fit.)
		if not width then
			local shown, textWidth = 0, 0
			for _, tab in ipairs(tabs) do
				if tab:IsShown() then
					tab.textWidth = math.ceil(tab.label:GetStringWidth())
					shown, textWidth = shown + 1, textWidth + tab.textWidth
				end
			end
			local pad = 12
			if maxWidth and shown > 0 then
				local room = maxWidth - 8 - (shown - 1) * TAB_GAP - textWidth
				pad = math.max(4, math.min(12, math.floor(room / shown)))
			end
			for _, tab in ipairs(tabs) do
				if tab:IsShown() then
					tab:SetWidth(pad < 12 and tab.textWidth + pad or math.max(40, tab.textWidth + pad))
				end
			end
		end
		local x = 0
		rows = { {} }
		for _, tab in ipairs(tabs) do
			if tab:IsShown() then
				local w = tab:GetWidth()
				if maxWidth and x > 0 and x + w > maxWidth then
					rows[#rows + 1] = {}
					x = 0
				end
				local row = rows[#rows]
				row[#row + 1] = tab
				tab.row = #rows
				x = x + w + TAB_GAP
			end
		end
	end
	local base = CreateFrame("Frame", nil, parent)
	base:SetSize(1, 1)
	local function Show(picked)
		tabs.picked = picked
		Rows()
		tabs.height = #rows * (TAB_H + 4) -- (how high they reach now: their rows can change as they're measured again)
		-- (The picked one's row at the bottom, the rest above it in order.
		-- Each row up clears the picked tab's extra height.)
		-- (The picked tab's row as measured now: one hidden keeps an old row
		-- that may not be there any more, the HUD page's at Party after Raid Style.)
		local pickedRow = tabs[picked].row
		if not rows[pickedRow] then pickedRow = 1 end
		local order = { pickedRow }
		for r = 1, #rows do
			if r ~= pickedRow then order[#order + 1] = r end
		end
		for up, r in ipairs(order) do
			for n, tab in ipairs(rows[r]) do
				tab:ClearAllPoints()
				if n == 1 then
					tab:SetPoint("BOTTOMLEFT", base, "TOPLEFT", 8, (up - 1) * (TAB_H + 4))
				else
					tab:SetPoint("BOTTOMLEFT", rows[r][n - 1], "BOTTOMRIGHT", TAB_GAP, 0)
				end
			end
		end
		for i, tab in ipairs(tabs) do
			PaintTab(tab, i == picked)
			if i == picked then
				topLeft:ClearAllPoints()
				topLeft:SetPoint("TOPLEFT", panel, "TOPLEFT")
				topLeft:SetPoint("TOPRIGHT", tab, "BOTTOMLEFT", 1, 0)
				topRight:ClearAllPoints()
				topRight:SetPoint("TOPLEFT", tab, "BOTTOMRIGHT", -1, 0)
				topRight:SetPoint("TOPRIGHT", panel, "TOPRIGHT")
			end
		end
		-- (The picked tab hidden, its page picked some other way (the HUD's
		-- sections, by their hub icons): the top edge whole, no gap for it.)
		local open = tabs[picked]:IsShown()
		if not open then
			topLeft:ClearAllPoints()
			topLeft:SetPoint("TOPLEFT", panel, "TOPLEFT")
			topLeft:SetPoint("TOPRIGHT", panel, "TOPRIGHT")
		end
		topRight:SetShown(open)
	end
	Show(1)
	return panel, tabs, Show, base, #rows * (TAB_H + 4)
end

-- Sub-page: which nameplates show (mobs, your faction, the other faction),
-- which stay up in cinematic mode, and how far away they show.
local function CreatePlatesPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Nameplates"])
	-- Two icons' tabs over the title (2026-11-16): the Nameplates icon's (this
	-- page's grids but Names, then Icons and the looks) and the Names icon's
	-- (this page's Names grid, then Name Style); only the picked icon's shown.
	local plateTabs, ShowPlateTab = ns.PageTabs(content, ns.ShowInTabs("plates"), 1)
	local plateSet = content.pageTabs
	local nameTabs, ShowNameTab = ns.PageTabs(content, ns.ShowInTabs("names"), 1)
	local nameSet = content.pageTabs
	title:SetPoint("TOPLEFT", plateTabs, "BOTTOMLEFT", 8, -14)
	local function ShowSet(names)
		for _, set in ipairs({ plateSet, nameSet }) do
			local mine = (set == nameSet) == names
			set.panel:SetShown(mine)
			for _, tab in ipairs(set.frames) do tab:SetShown(mine) end
		end
		content.pageTabs = names and nameSet or plateSet
		if names then ShowNameTab(1) else ShowPlateTab(1) end
	end
	ShowSet(false)
	local _ = nameTabs -- (its panel: nameSet.panel)

	local subtitle = PageIntro(content, title,
		L["CineMode hides nameplates and names: pick which show, and when."])

	-- The page's master switch: off, CineMode leaves nameplates and names to
	-- the game's own options (everything below greys out).
	local handleCheck = Check(content, "handlePlates", L["Enable Page"],
		L["Lets CineMode fade nameplates and names as this page says."],
		function(value)
			ns.GetDB().handlePlates = value
			if value and ns.EnsurePlateRows then
				ns.EnsurePlateRows()
			end
			ns.WarnPlatesInCombat()
			Refresh()
		end)
	handleCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -12)
	RegisterPageSwitch(content, "handlePlates", handleCheck)
	-- (Everything below is made the first time the page is needed: lazyPages.)
	local function MakeBody()

		-- Nameplates and names each get a table: a row per kind of unit, as the
		-- Standard Frames page's (GridRows.lua): Always, the Combat, Target and
		-- Location dropdowns, the roles and Edit.
		local ROW_HEIGHT = 24
		local GRID_LABEL = 170 -- (wide enough for every tab on one row over the grid)
		local PLATE_LAYOUT = { edit = true }
		local NAME_LAYOUT = PLATE_LAYOUT
		local function TableTop(anchor, layout)
			local top = CreateFrame("Frame", nil, content)
			top:SetSize(1, 1)
			top:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
			top.layout = layout
			ns.GridHeadings(ns.GRID_KIT, content, top, GRID_LABEL, layout)
			return top
		end
		-- A row's label and its grid row (spec: ns.GridRow's). indent: a row that
		-- sits under the one before (Minions), as in the game's options.
		local function PlaceRow(top, r, label, indent, spec)
			local y = -FRAME_HEADING_HEIGHT - 4 - (r - 1) * ROW_HEIGHT
			local rowLabel = Label(content, indent and "GameFontHighlightSmall" or "GameFontHighlight", label)
			-- (What goes below lines up with the grid, not the indent. labelShift:
			-- room for a +/- (kind rows) or a part row's indent under its kind.)
			rowLabel.indentX = (indent and 18 or 0) + (top.labelShift or 0)
			rowLabel:SetPoint("TOPLEFT", top, "TOPLEFT", rowLabel.indentX, y - 5)
			rowLabel:SetWidth(GRID_LABEL - 4 - ns.GRID_DOT_ROOM - rowLabel.indentX)
			rowLabel:SetJustifyH("LEFT")
			rowLabel:SetWordWrap(false)
			ns.LabelHover(content, rowLabel)
			spec.band = top.band or r
			local row = ns.GridRow(ns.GRID_KIT, content, GRID_LABEL, top.layout, spec)
			row.debugName = label -- (for the dev copy's page timing)
			row:SetPoint("TOPLEFT", top, "TOPLEFT", GRID_LABEL, y)
			top.rows = top.rows or {}
			top.rows[#top.rows + 1] = row
			return rowLabel
		end
		-- A row's ticks (db keys: Always, the combat ones, the places) as a rule,
		-- for its dot. (Close to what they do, not the same: names and plates
		-- have rules of their own on fights.)
		local PLACE_WORDS = { PvP = "(flagged and not bg)", BGs = "bg", [""] = "world", Cities = "city", Instances = "instance" }
		local function TicksRule(always, keys)
			local db, words = ns.GetDB(), {}
			if db[always] then return "always" end
			for _, each in ipairs(keys) do
				if db[each[1]] then words[#words + 1] = each[2] end
			end
			return #words > 0 and table.concat(words, " or ") or "never"
		end
		-- Both grids' column tooltips (each box adds its row's note). Always keeps
		-- its row up everywhere, and Grouped in a party or raid, in fights and out,
		-- whatever the rest says. (The rest grey while Always is ticked, keeping
		-- their ticks.)
		local ALWAYS_TIP = L["Shows everywhere, in fights and out."]
		local COMBAT_TIP = L["Show in fights, and for the Calm Timer after."]
		local PVP_COMBAT_TIP = L["Show in fights while you're PvP flagged, and for the Calm Timer after."]
		local GROUP_TIP = L["Always show while you're in a party or raid."]
		local TARGET_ENEMY_TIP = L["Show out of fights while you have a living enemy targeted."]
		local TARGET_FRIEND_TIP = L["Show out of fights while you have anything else targeted: friends, NPCs, dead enemies."]

		-- Each grid a tab of its own, in Heal Vision's folder look (ns.FolderTabs,
		-- made once every section is): the picked one's section shows on the
		-- panel under them, its full name at its top. What a section adds between
		-- BeginSection and EndSection goes in its body, hidden on other tabs
		-- (search still finds it, and picks its tab). section.last: its last
		-- row's label, the panel's bottom under it. The tab last picked is kept
		-- across reloads (SectionState, its id "Nameplates/tab", open the key).
		local sections = {}
		local picked = { id = "Nameplates/tab", open = "Instances" }
		local SECTION_WIDTH = GRID_LABEL + ns.GridWidth(PLATE_LAYOUT)
		-- (The panel's top left, under the tabs (placed once they're made, as high
		-- as their rows); the sections' frames hang on it.)
		local panelTop = CreateFrame("Frame", nil, content)
		panelTop:SetSize(1, 1)
		-- (Under the picked section's last row, at its left: the panel's bottom.)
		local foot = CreateFrame("Frame", nil, content)
		foot:SetSize(1, 1)
		local panel, ShowTab, folderTabs, folderHeight
		local playersTop, npcTop, serviceTop, extrasTop -- (the Names icon's four grids)
		-- (The Names icon's sections, 2026-11-16: Players, NPCs ("Names", its old
		-- id), Service NPCs and Extras.)
		local function IsNames(key) return type(key) == "string" and key:find("^Names") ~= nil end
		local function LayoutSections()
			SectionState.Restore(picked)
			local shown
			for i, section in ipairs(sections) do
				if section.key == picked.open then shown = i end
			end
			shown = shown or 1
			for i, section in ipairs(sections) do
				section.frame:SetShown(i == shown)
				section.body:SetShown(i == shown)
			end
			if IsNames(sections[shown].key) then content.lastNamesSection = sections[shown].key
			else content.lastPlatesSection = sections[shown].key end
			ShowTab(shown)
			local last = sections[shown].last
			foot:ClearAllPoints()
			foot:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -(last.indentX or 0), 0)
			FitContentHeight(content)
		end
		local function Pick(section)
			SectionState.Save(picked, section.key)
			LayoutSections()
			-- (Its icon lit: Names', or the Nameplates one for the rest.)
			ns.ShowHubPage(IsNames(section.key) and "Nameplate Names" or "Nameplates")
		end
		-- An icon picked (its tile's onSelect): the Names grid alone, or the rest
		-- with their folder tabs (Names' left out), the last of them shown.
		function ns.PickPlatesIcon(names)
			SectionState.Restore(picked)
			if names and not IsNames(picked.open) then
				SectionState.Save(picked, content.lastNamesSection or "NamesPlayers")
			elseif not names and IsNames(picked.open) then
				SectionState.Save(picked, content.lastPlatesSection or "Instances")
			end
			-- (Each icon's own sections as its sub-tabs.)
			for i, section in ipairs(sections) do
				if folderTabs then folderTabs[i]:SetShown(IsNames(section.key) == names) end
			end
			if folderTabs then
				panelTop:ClearAllPoints()
				panelTop:SetPoint("TOPLEFT", handleCheck, "BOTTOMLEFT", 2, -14 - folderHeight)
			end
			LayoutSections()
		end
		-- What's on the page, to tell what a section adds.
		local function Widgets()
			local set = {}
			for _, object in ipairs({ content:GetChildren() }) do set[object] = true end
			for _, object in ipairs({ content:GetRegions() }) do set[object] = true end
			return set
		end
		-- (tab: its tab's name, nil: heading.)
		local function Section(heading, key, tab)
			SetSection(content, heading)
			local section = { key = key, tab = tab or heading }
			section.frame = CreateFrame("Frame", nil, content)
			section.frame:SetSize(SECTION_WIDTH, 20)
			section.frame:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12, -10)
			section.frame.searchAlways = true
			section.title = Label(section.frame, "GameFontNormal", heading)
			section.title:SetPoint("TOPLEFT", section.frame, "TOPLEFT", 0, -3)
			section.body = CreateFrame("Frame", nil, content)
			section.body:SetPoint("TOPLEFT", section.frame, "BOTTOMLEFT")
			section.body:SetSize(1, 1)
			section.body.searchAlways = true
			section.body.openSection = function() Pick(section) end
			section.frame.openSection = section.body.openSection
			sections[#sections + 1] = section
			return section
		end
		local function BeginSection(section)
			section.before = Widgets()
		end
		local function EndSection(section, last)
			section.last = last
			for object in pairs(Widgets()) do
				if not section.before[object] then
					object:SetParent(section.body)
				end
			end
			section.before = nil
		end

		local friendlySection = Section(L["Friendly nameplates"], "Friendly", L["Friendly"])
		-- The grid can't keep plates up out of fights while the game's own
		-- "Always Show Nameplates" is off: say so beside the page's switch, seen
		-- on every tab (checked as the page shows).
		local showAllWarning = Label(content, "GameFontRedSmall",
			L["Blizzard's Always Show Nameplates is off, so nameplates only show in combat."])
		showAllWarning:SetPoint("LEFT", handleCheck, "LEFT", 2, 0) -- (the switch itself is hidden)
		showAllWarning.Refresh = function(self)
			self:SetShown(GetCVar("nameplateShowAll") == "0")
		end
		controls[#controls + 1] = showAllWarning
		-- The columns: Always (set apart: it stands for the rest of its row), In
		-- Combat, In PvP combat, PvP and BGs & arenas, the other places, and
		-- Grouped (not a place) beside Instances.
		local PLACE_COLUMNS = {
			{ always = true },
			{ combat = true },
			{ pvpCombat = true },
			{ "PvP", L["PvP"], L["Show while PvP flagged, outside battlegrounds and arenas."] },
			{ "BGs", L["BGs & arenas"], L["Show in battlegrounds and arenas."] },
			{ "", L["Open world"], L["Show out in the world, inns included (capital cities are Cities)."] },
			{ "Cities", L["Cities"], L["Show in capital cities."] },
			{ group = true },
			{ "Instances", L["Instances"], L["Show in dungeons, scenarios and raids."] },
		}
		BeginSection(friendlySection)
		local columnTop = TableTop(friendlySection.frame, PLATE_LAYOUT)

		-- Two grids: friendly units, then enemy and neutral ones (below Friendly
		-- Plates in Dungeons and Raids). Rows for particular units (your pet first,
		-- your group last) only add to the game's own nameplate options' rows:
		-- ns.PLATE_UNIT_ROWS; group members have no use for Grouped.
		local FRIENDLY_KINDS = {
			{ "MyPet", L["Your pet"] },
			{ "Friends", L["Friendly players"] },
			{ "FriendlyMinions", L["Minions"], true },
			{ "FriendlyNPCs", L["Friendly NPCs"] },
			{ "GroupMembers", L["Group members"], nil, true },
			{ "GroupMinions", L["Minions"], true, true },
		}
		local ENEMY_KINDS = {
			{ "Enemies", L["Enemy players"] },
			{ "EnemyMinions", L["Minions"], true },
			{ "EnemyNPCs", L["Hostile NPCs"] },
			{ "EnemyMinor", L["Minor"], true },
			{ "NeutralNPCs", L["Neutral NPCs"] },
			{ "NeutralMinor", L["Minor"], true },
		}
		local tip = L[" Also turns these nameplates on in the game's options."]
		local UNIT_ROW_TIPS = {
			YourTarget = L[" Your target's nameplate, whatever the Nameplates grid says."],
			MyPet = L[" Your pet's nameplate, whatever the Minions rows say, grouped or not."],
			GroupMembers = L[" Your party or raid members' nameplates, whatever Friendly players says."],
			GroupMinions = L[" Your party or raid members' pets, whatever the Minions rows say."],
		}
		-- Friendly rows: in dungeons and raids, Friendly Plates in Dungeons and
		-- Raids decides (below the Nameplates grid), so they have no Instances box.
		local INSTANCE_LOCKED = {
			Friends = true, FriendlyMinions = true, FriendlyNPCs = true, MyPet = true, GroupMembers = true,
			GroupMinions = true,
		}
		local lastLabel
		local function AddPlateRow(top, r, kind)
			-- A setting changed: ticked, its nameplates on in the game's options.
			local function Set(key, value)
				ns.GetDB()[key] = value
				if value then
					ns.EnablePlateRow(kind[1])
				end
				ns.WarnPlatesInCombat()
			end
			local function Item(name, key, itemTip)
				RecordKey(content, key) -- (for the page's Reset)
				return { name, function() return ns.GetDB()[key] and true or false end,
					function() Set(key, not ns.GetDB()[key]) end, nil, itemTip }
			end
			local alwaysKey = "plateAlways" .. kind[1]
			local rowTip = UNIT_ROW_TIPS[kind[1]]
			local part = kind[1]:find("^Part") -- (Plate parts rows: no game settings of their own)
			local tip = rowTip and (part or kind[1]:find("Target$")) and rowTip or (rowTip or "") .. tip
			RecordKey(content, alwaysKey)
			local combat = { Item(L["In combat"], "plateCombat" .. kind[1], COMBAT_TIP .. tip),
				Item(L["In PvP combat"], "plateCombatPvP" .. kind[1], PVP_COMBAT_TIP .. tip) }
			local targets = { Item(L["Enemy targeted"], "plateTargetEnemy" .. kind[1], TARGET_ENEMY_TIP .. tip),
				Item(L["Friend targeted"], "plateTargetFriendly" .. kind[1], TARGET_FRIEND_TIP .. tip) }
			local places, ticks = {}, { { "plateCombat" .. kind[1], "combat" },
				{ "plateCombatPvP" .. kind[1], "(combat and flagged)" },
				{ "plateTargetEnemy" .. kind[1], "(enemy and not combat)" },
				{ "plateTargetFriendly" .. kind[1], "(friendly and not combat)" } }
			for _, place in ipairs(PLACE_COLUMNS) do
				if place.group then
					-- (Group members' rows only apply grouped: no Grouped.)
					if not kind[4] then
						local groupKey = "plateGroup" .. kind[1]
						places[#places + 1] = Item(L["Grouped"], groupKey, GROUP_TIP .. tip)
						ticks[#ticks + 1] = { groupKey, "group" }
					end
				elseif place[1] then
					-- The open world keeps the original "keep up in CineMode" key; the
					-- friendly rows have no Instances (Friendly plates in dungeons and raids).
					local key = place[1] == "" and ("plateCinematic" .. kind[1]) or ("plateIn" .. place[1] .. kind[1])
					if not (place[1] == "Instances" and INSTANCE_LOCKED[kind[1]]) then
						places[#places + 1] = Item(place[2], key, place[3] .. tip)
						ticks[#ticks + 1] = { key, PLACE_WORDS[place[1]] }
					end
				end
			end
			-- Greyed out where this client has no such setting.
			local function Available()
				return part or ns.HasPlateSettings(kind[1])
			end
			-- (Its rule, in place of its ticks: edited on the row.)
			local ruleKey = "plate:" .. kind[1]
			local layout = top.layout
			local function RuleKey() return ruleKey end
			if layout.edit then RecordRow(content, "frameRules", ruleKey) end -- (for the page's Reset and the modules)
			lastLabel = PlaceRow(top, r, kind[2], kind[3], {
				dot = true,
				always = { isOn = function() return ns.GetDB()[alwaysKey] end,
					set = function(value) Set(alwaysKey, value) end, tip = ALWAYS_TIP .. tip },
				menus = { [ns.GRID_COMBAT] = combat, [ns.GRID_TARGET] = targets, [ns.GRID_LOCATION] = places },
				help = { [ns.GRID_COMBAT] = L["Shown in fights: any of them, or only while you're PvP flagged."] },
				enabled = Available,
				override = part and function() return ns.StyleOverrideText("plate" .. kind[1]) end or nil,
				rule = layout.edit and { key = RuleKey, label = function() return kind.title or kind[2] end,
					changed = function()
						local text = ns.GetDB().frameRules[ruleKey]
						if text and text:find("%S") then ns.EnablePlateRow(kind[1]) end
					end } or nil,
				liveRule = function() return TicksRule(alwaysKey, ticks) end,
			})
		end

		-- The Friendly and Enemy grids' rows, each kind's (ns.PLATE_OWN_PART_KINDS)
		-- with a +/- that opens its parts under it, as the HUD page's unit frames
		-- do: Use custom parts unticked, a line saying it goes by the Default
		-- parts tab (a link there); ticked, a row for each part of its own (keys
		-- plate<column>Part<kind><part>, copied from the default rows as it's
		-- ticked). Each row's top hangs under the block above, so opening one
		-- moves the rest down. Gives the end of the last block, for the panel's foot.
		local TOGGLE_W = 18
		local OWN_KIND = {}
		for _, kind in ipairs(ns.PLATE_OWN_PART_KINDS) do OWN_KIND[kind] = true end
		local defaultPartsSection -- (the Default parts tab: made below)
		-- The parts of the plates (see PlateParts): key, label, tip. Retail's plates have no level.
		local PLATE_PART_LABELS
		-- (Raid markers beyond plate range are the game's, and so is yours.)
		PLATE_PART_LABELS = {
			{ "Health", L["Health bar"], L[" The health bar."] },
			{ "Name", L["Name"], L[" The name on the plate (the Names grid below is for names without a plate)."] },
			{ "CastBar", L["Cast bar"], L[" The cast bar."] },
			{ "Buffs", L["Buffs"], L[" The buffs shown on the plate."] },
			{ "Debuffs", L["Debuffs"], L[" The debuffs (and crowd control) shown on the plate."] },
			{ "RaidMarker", L["Raid marker"], L[" The raid target marker (skull, star...)."] },
			{ "Classification", L["Elite/rare icon"], L[" The elite, rare or boss icon."] },
			{ "Level", L["Level"], L[" The level."] },
			{ "Threat", L["Threat glow"], L[" The glow while a mob has you (or is about to) as its target."] },
			{ "Highlight", L["Target highlight"], L[" The border round your target's or mouseover's plate."] },
			{ "Widgets", L["Quest/widget icons"], L[" Quest objective icons and other widgets over the plate."] },
		}
		local function AddKindRows(top, kinds)
			top.rows = top.rows or {}
			local blocks, after = {}, nil
			local function Relayout()
				local db = ns.GetDB() or {} -- (none yet while the page is first built)
				for _, block in ipairs(blocks) do
					local open = block.parts and SectionState.Restore(block.state) and true or false
					local custom = db["plateOwnParts" .. block.kind] and true or false
					block.box:SetShown(open)
					block.box:SetHeight(open and (ROW_HEIGHT + (custom and block.parts * ROW_HEIGHT or 0) + 4) or 0.001)
					if block.parts then
						block.rowsBox:SetShown(custom)
						block.usingDefault:SetShown(not custom)
						block.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up"
							or "Interface\\Buttons\\UI-PlusButton-Up")
					end
				end
				FitContentHeight(content)
			end
			for i, kind in ipairs(kinds) do
				local rowTop = top
				if i > 1 then
					rowTop = CreateFrame("Frame", nil, content)
					rowTop:SetSize(1, 1)
					rowTop:SetPoint("TOPLEFT", after, "BOTTOMLEFT", 0, FRAME_HEADING_HEIGHT + 4)
					rowTop.layout, rowTop.rows = top.layout, top.rows
				end
				rowTop.labelShift, rowTop.band = TOGGLE_W, i
				AddPlateRow(rowTop, 1, kind)
				local box = CreateFrame("Frame", nil, content)
				box:SetPoint("TOPLEFT", rowTop, "TOPLEFT", 0, -FRAME_HEADING_HEIGHT - 4 - ROW_HEIGHT)
				box:SetSize(SECTION_WIDTH, 0.001)
				box:Hide()
				local block = { kind = kind[1], box = box, state = { id = "Nameplates/kind/" .. kind[1], open = false } }
				blocks[i], after = block, box
				if OWN_KIND[kind[1]] then
					local function Toggle()
						SectionState.Save(block.state, not block.state.open)
						Relayout()
					end
					-- (Search finding a part opens its kind's block.)
					box.openSection = function()
						SectionState.Save(block.state, true)
						Relayout()
					end
					local plus = CreateFrame("Button", nil, content)
					plus:SetSize(16, 16)
					plus:SetPoint("LEFT", rowTop, "TOPLEFT", (kind[3] and 18 or 0),
						-FRAME_HEADING_HEIGHT - 4 - ROW_HEIGHT / 2)
					block.icon = plus:CreateTexture(nil, "ARTWORK")
					block.icon:SetAllPoints()
					plus:SetScript("OnClick", Toggle)
					Tooltip(plus, L["Shows or hides its parts."])
					local before = Widgets() -- (all from here in its box, hidden while closed: not the +/-)
					local inset = TOGGLE_W + (kind[3] and 18 or 0) + 10
					local custom = Check(content, "plateOwnParts" .. kind[1], L["Use custom parts"],
						L["Gives these nameplates their own parts instead of the Default parts tab's."], function(value)
						ns.GetDB()["plateOwnParts" .. kind[1]] = value
						if value then ns.CopyDefaultPlateParts(kind[1]) end
						Relayout()
						Refresh()
					end)
					custom:SetPoint("TOPLEFT", box, "TOPLEFT", inset - 4, 0)
					-- (Unticked: the tab it goes by, a click away.)
					local usingDefault = CreateFrame("Button", nil, content)
					usingDefault.text = usingDefault:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
					usingDefault.text:SetPoint("LEFT")
					usingDefault.text:SetText(L["Using Default parts >"])
					usingDefault:SetSize(usingDefault.text:GetStringWidth() + 4, 18)
					usingDefault:SetPoint("LEFT", custom.Text or custom.text or custom, "RIGHT", 16, 0)
					usingDefault:SetScript("OnClick", function()
						if defaultPartsSection then defaultPartsSection.body.openSection() end
					end)
					usingDefault:SetScript("OnEnter", function() usingDefault.text:SetTextColor(1, 0.82, 0) end)
					usingDefault:SetScript("OnLeave", function() usingDefault.text:SetTextColor(0.5, 0.5, 0.5) end)
					block.usingDefault = usingDefault
					-- Its parts' rows.
					local rowsBox = CreateFrame("Frame", nil, content)
					rowsBox:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -ROW_HEIGHT)
					rowsBox:SetSize(SECTION_WIDTH, 1)
					block.rowsBox = rowsBox
					local partTop = CreateFrame("Frame", nil, content)
					partTop:SetSize(1, 1)
					partTop:SetPoint("TOPLEFT", rowsBox, "TOPLEFT", 0, FRAME_HEADING_HEIGHT + 4)
					partTop.layout, partTop.rows, partTop.labelShift = top.layout, top.rows, inset
					local rowsBefore = Widgets()
					local k = 0
					for _, part in ipairs(PLATE_PART_LABELS) do
						if not (part[1] == "Level" and ns.isRetail) then
							k = k + 1
							local key = "Part" .. kind[1] .. part[1]
							UNIT_ROW_TIPS[key] = part[3] .. L[" In CineMode, on these nameplates while they're up."]
							if INSTANCE_LOCKED[kind[1]] then INSTANCE_LOCKED[key] = true end
							AddPlateRow(partTop, k, { key, part[2], title = kind[2] .. ": " .. part[2] })
						end
					end
					for object in pairs(Widgets()) do
						if not rowsBefore[object] then object:SetParent(rowsBox) end
					end
					block.parts = k
					for object in pairs(Widgets()) do
						if not before[object] and object ~= rowsBox then object:SetParent(box) end
					end
					rowsBox:SetParent(box)
				end
			end
			Relayout()
			content:HookScript("OnShow", Relayout) -- (settings loaded, or another profile since)
			local foot = CreateFrame("Frame", nil, content)
			foot:SetSize(1, 1)
			foot:SetPoint("TOPLEFT", after, "BOTTOMLEFT")
			return foot, Relayout
		end
		local friendlyFoot = AddKindRows(columnTop, FRIENDLY_KINDS)
		EndSection(friendlySection, friendlyFoot)

		-- Friendly plates in dungeons and raids: the game won't let addons fade
		-- them there, so each kind is just on or off (see Effects). The grids
		-- have no Instances boxes for them (INSTANCE_LOCKED, AddPlateRow).
		local instanceSection = Section(L["Friendly plates in dungeons and raids"], "Instances", L["Dungeons & raids"])
		local instanceAnchor = PageIntro(instanceSection.frame, instanceSection.title,
			L["In dungeons and raids, each kind of friendly nameplate is either all on or all off."], nil, true)
		local INSTANCE_CHOICES = {
			{ "Friends", L["Friendly players"], target = true },
			{ "FriendlyMinions", L["Pets and minions"] },
			{ "FriendlyNPCs", L["Friendly NPCs"], target = true },
		}
		BeginSection(instanceSection)
		local lastInstanceRow = instanceAnchor
		for i, row in ipairs(INSTANCE_CHOICES) do
			local key = "plateInstance" .. row[1]
			local choices = { { value = "hide", text = L["Hidden"] }, { value = "show", text = L["Shown"] } }
			if row.target then
				choices[3] = { value = "target", text = L["With a friendly target"] }
			end
			local rowLabel = Label(content, "GameFontHighlight", row[2])
			rowLabel:SetPoint("TOPLEFT", lastInstanceRow, "BOTTOMLEFT", 0, i == 1 and -18 or -20) -- (room between the dropdowns: flat ones fill their frames)
			local dropdown = Dropdown(content, key, choices, 200, function(value)
				if value ~= "hide" then
					ns.EnablePlateRow(row[1])
				end
				ns.WarnPlatesInCombat()
			end)
			if dropdown then
				dropdown:SetPoint("LEFT", rowLabel, "LEFT", GRID_LABEL + 30, 0)
			end
			lastInstanceRow = rowLabel
		end
		EndSection(instanceSection, lastInstanceRow)

		-- Enemy and neutral units, laid out the same way.
		local enemySection = Section(L["Enemy nameplates"], "Enemy", L["Enemy"])
		table.insert(sections, 1, table.remove(sections)) -- (its tab before Friendly's)
		BeginSection(enemySection)
		local enemyTop = TableTop(enemySection.frame, PLATE_LAYOUT)
		local enemyFoot = AddKindRows(enemyTop, ENEMY_KINDS)
		EndSection(enemySection, enemyFoot)

		-- The parts of the plates that are up (see PlateParts), laid out the same
		-- way. Retail's plates have no level.
		local partTip = L[" In CineMode, on the nameplates that are up."]
		local PARTS = PLATE_PART_LABELS
		-- (The class and role icons and the target marks, the addon's own, have a
		-- When each on the Nameplates hub's Icons and Nameplate Style pages: PlateIcons.lua.)
		local r
		local function PartsSection(heading, key, tab)
			local section = Section(heading, key, tab)
			BeginSection(section)
			local top = TableTop(section.frame, PLATE_LAYOUT)
			r = 0
			for _, part in ipairs(PARTS) do
				if not (part[1] == "Level" and ns.isRetail) then
					r = r + 1
					UNIT_ROW_TIPS["Part" .. part[1]] = part[3] .. partTip
					AddPlateRow(top, r, { "Part" .. part[1], part[2] })
				end
			end
			EndSection(section, lastLabel)
			return top
		end
		-- (The Default parts tab: every kind's, but for kinds set to Use custom parts.)
		local partsTop = PartsSection(L["Default plate parts"], "Parts", L["Default parts"])
		defaultPartsSection = sections[#sections]

		-- Names, laid out the same way. Outside cinematic mode the game's own
		-- name options decide.
		-- Names: four sections, the Names icon's sub-tabs (2026-11-16): players,
		-- Enemy NPCs, Friendly NPCs (with Service NPCs, its row and its settings
		-- together) and extras.
		local playersSection = Section(L["Player names"], "NamesPlayers", L["Players"])
		local namesHeader = playersSection.title
		-- (A warning beside it: on faded plates the names are ours. See PlateParts.)
		local namesNote = CreateFrame("Button", nil, playersSection.frame)
		namesNote:SetSize(16, 16)
		namesNote:SetPoint("LEFT", namesHeader, "RIGHT", 6, 0)
		local namesNoteIcon = namesNote:CreateTexture(nil, "ARTWORK")
		namesNoteIcon:SetAllPoints()
		namesNoteIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
		local namesNoteText = L["In CineMode, Cinematic draws names on faded nameplates to look like the game's."] ..
			L[" Their look: the Name Style page."]
		Tooltip(namesNote, namesNoteText)
		namesNote.searchNote = namesNoteText
		namesNote.searchEdges = { top = namesHeader, bottom = namesHeader, left = namesHeader, right = namesNote }
		BeginSection(playersSection)
		playersTop = TableTop(playersSection.frame, NAME_LAYOUT)
		local nameTip = L[" Ticking any box turns these names on in the game's options."]
		-- (Units with plates show a kept name on theirs in CineMode: see Effects.)
		-- A row of boxes (keys name<column><key>) for a names group: the Target
		-- group's is the Target section's Names row, below.
		local function AddNameRow(top, r, group, key, label, indent, tip)
			local function Set(setting, value)
				ns.GetDB()[setting] = value
				ns.SyncNameRow(group)
				ns.WarnPlatesInCombat()
			end
			local function Item(name, setting, itemTip)
				RecordKey(content, setting) -- (for the page's Reset)
				return { name, function() return ns.GetDB()[setting] and true or false end,
					function() Set(setting, not ns.GetDB()[setting]) end, nil, itemTip }
			end
			local alwaysKey = "nameAlways" .. key
			RecordKey(content, alwaysKey)
			-- (Names can't change mid-fight: In PvP combat goes by how the fight started.)
			local combat = { Item(L["In combat"], "nameCombat" .. key, COMBAT_TIP .. tip),
				Item(L["In PvP combat"], "nameCombatPvP" .. key,
					PVP_COMBAT_TIP .. L[" The game only allows this to be set as the fight starts."] .. tip) }
			local targets = { Item(L["Enemy targeted"], "nameTargetEnemy" .. key, TARGET_ENEMY_TIP .. tip),
				Item(L["Friend targeted"], "nameTargetFriendly" .. key, TARGET_FRIEND_TIP .. tip) }
			local places, ticks = {}, { { "nameCombat" .. key, "combat" }, { "nameCombatPvP" .. key, "(combat and flagged)" },
				{ "nameTargetEnemy" .. key, "(enemy and not combat)" },
				{ "nameTargetFriendly" .. key, "(friendly and not combat)" } }
			for _, place in ipairs(PLACE_COLUMNS) do
				if place.group then
					places[#places + 1] = Item(L["Grouped"], "nameGroup" .. key, GROUP_TIP .. tip)
					ticks[#ticks + 1] = { "nameGroup" .. key, "group" }
				elseif place[1] then
					-- The open world keeps the original Keep column's key.
					local placeKey = place[1] == "" and ("nameKeep" .. key) or ("nameIn" .. place[1] .. key)
					places[#places + 1] = Item(place[2], placeKey, place[3] .. tip)
					ticks[#ticks + 1] = { placeKey, PLACE_WORDS[place[1]] }
				end
			end
			-- Its rule (name:<row>), on the row.
			local ruleKey = ns.NameRuleKey(key)
			local function RuleKey() return ruleKey end
			RecordRow(content, "frameRules", ruleKey) -- (for the page's Reset and the modules)
			lastLabel = PlaceRow(top, r, label, indent, {
				dot = true,
				always = { isOn = function() return ns.GetDB()[alwaysKey] end,
					set = function(value) Set(alwaysKey, value) end, tip = ALWAYS_TIP .. tip },
				menus = { [ns.GRID_COMBAT] = combat, [ns.GRID_TARGET] = targets, [ns.GRID_LOCATION] = places },
				rule = { key = RuleKey, label = function() return label end, changed = function() ns.SyncNameRow(group) end },
				help = { [ns.GRID_COMBAT] = L["Shown in fights: any of them, or only while you're PvP flagged."] },
				-- Greyed out where this client has no such setting.
				enabled = function() return ns.HasNameSettings(group) end,
				liveRule = function() return TicksRule(alwaysKey, ticks) end,
			})
		end
		-- Each group's rows in its section (which: players, npcs, service, extras).
		local GROUP_SECTION = { Self = "players", Friends = "players", FriendlyMinions = "players",
			GroupMembers = "players", GroupMinions = "players", Enemies = "players", EnemyMinions = "players",
			HostileNPCs = "npcs", NeutralNPCs = "npcs", Critters = "npcs",
			-- (Friendly NPCs with Service NPCs on the Friendly NPCs tab, 2026-11-16.)
			FriendlyNPCs = "service", ServiceNPCs = "service", Guild = "extras" }
		local targetGroup
		local function AddRows(top, which)
			local count = 0
			for _, group in ipairs(ns.NAME_GROUPS) do
				if group.rows then
					targetGroup = group
				elseif (GROUP_SECTION[group.key] or "extras") == which then
					count = count + 1
					local tip = group.plateOnly and group.tip
						or (group.tip or "") .. nameTip
					-- (Service NPCs under Friendly NPCs, on their tab: indented as before.)
					AddNameRow(top, count, group, group.key, group.label, group.indent, tip)
				end
			end
			return count
		end
		AddRows(playersTop, "players")
		EndSection(playersSection, lastLabel)

		-- (Enemy NPCs since 2026-11-16: hostile, neutral and critters; ids kept.)
		local npcSection = Section(L["Enemy NPCs"], "Names", L["Enemy NPCs"])
		BeginSection(npcSection)
		npcTop = TableTop(npcSection.frame, NAME_LAYOUT)
		AddRows(npcTop, "npcs")
		EndSection(npcSection, lastLabel)

		local extrasSection = Section(L["More over heads"], "NamesExtras", L["Extras"])
		BeginSection(extrasSection)
		extrasTop = TableTop(extrasSection.frame, NAME_LAYOUT)
		local extraRows = AddRows(extrasTop, "extras")
		-- Raid markers (skull, moon...) kept up over their units as the rest of
		-- their plates fades or shows their names alone (see KeepRaidMarker).
		UNIT_ROW_TIPS.PartMarker = L[" Keeps raid markers over their units in CineMode as their nameplates fade."]
		AddPlateRow(extrasTop, extraRows + 1, { "PartMarker", L["Raid marker"] })
		EndSection(extrasSection, lastLabel)

		-- Service NPCs: its row, then its own settings right under it: whether it
		-- shows names or titles alone, and which titles it keeps (Effects, PlateGuild).
		-- (Friendly NPCs since 2026-11-16: their row first, Service NPCs under it; ids kept.)
		local serviceSection = Section(L["Friendly NPCs"], "NamesService", L["Friendly NPCs"])
		BeginSection(serviceSection)
		serviceTop = TableTop(serviceSection.frame, NAME_LAYOUT)
		AddRows(serviceTop, "service")
		local serviceShowLabel = Label(content, "GameFontHighlight", L["Show"])
		serviceShowLabel:SetPoint("TOPLEFT", lastLabel, "BOTTOMLEFT", 0, -20)
		local serviceShowTip = L["Show a service NPC's name with its title, or just its title."]
		local serviceShow = Dropdown(content, "nameServiceShow", {
			{ value = "name", text = L["Names and titles"] },
			{ value = "title", text = L["Titles only"] },
		}, 200, function()
			if ns.RefreshAllPlates then ns.RefreshAllPlates() end
		end)
		if serviceShow then
			serviceShow:SetPoint("LEFT", serviceShowLabel, "LEFT", GRID_LABEL + 30, 0)
			Tooltip(serviceShow, serviceShowTip)
		end
		-- How their titles look (brackets, icons in place of titles): Name
		-- Style's Service NPCs row, Second line tab. Its link here.
		local serviceLookLabel = Label(content, "GameFontHighlight", L["Their look"])
		serviceLookLabel:SetPoint("TOPLEFT", serviceShowLabel, "BOTTOMLEFT", 0, -22)
		local serviceLook = ns.StyleLink(content, serviceLookLabel, "Name Style",
			L["Set brackets and icons for titles on the Name Style page."],
			Tooltip, L["Name Style"], serviceLookLabel)
		serviceLook:ClearAllPoints()
		serviceLook:SetPoint("LEFT", serviceLookLabel, "LEFT", GRID_LABEL + 30, 0)
		local serviceIconsLabel = serviceLookLabel -- (the next row goes under it)
		local serviceKindsLabel = Label(content, "GameFontHighlight", L["Kinds"])
		serviceKindsLabel:SetPoint("TOPLEFT", serviceIconsLabel, "BOTTOMLEFT", 0, -22)
		-- (Quest givers: by the game's quest cursor, or Questie's icons. Hidden on
		-- a client with neither.)
		local questiePossible = ns.QuestieMinimapPossible and ns.QuestieMinimapPossible()
		local questPossible = (ns.QuestGiversPossible and ns.QuestGiversPossible()) or questiePossible
		local cell, subRow, lastServiceKind = 0, nil, serviceKindsLabel
		for _, kind in ipairs(ns.SERVICE_KINDS) do
			if kind.key ~= "Quest" or questPossible then
				local key = "nameService" .. kind.key
				local tip
				if kind.key == "Other" then
					tip = L["Any other title, lore titles too (<Ranger-General of Silvermoon>)."]
				elseif kind.key == "Quest" then
					tip = L["NPCs with a quest for you to pick up or hand in."]
				else
					tip = L["NPCs whose title has one of these words in it: %s."]:format(((kind.words .. (kind.moreWords and "," .. kind.moreWords or "")):gsub(",", ", ")))
				end
				local check = Check(content, key, kind.label, tip, function(value)
					ns.GetDB()[key] = value
					if ns.ServiceKindsChanged then ns.ServiceKindsChanged() end
					if ns.RefreshAllPlates then ns.RefreshAllPlates() end
					-- (Trainers greys out its Your class only.)
					if kind.key == "Trainer" then Refresh() end
				end)
				-- (The row under Trainers is its Your class only's own.)
				if math.floor(cell / 2) == subRow then cell = cell + 2 end
				local column, row = cell % 2, math.floor(cell / 2)
				cell = cell + 1
				check:SetPoint("TOPLEFT", serviceKindsLabel, "TOPLEFT", GRID_LABEL + 26 + column * 200, 6 - row * 26)
				if column == 0 then lastServiceKind = check end
				-- Trainers' sub-option, indented under it: your class's trainers
				-- only (PlateGuild's OtherClassTitle). Greyed out while Trainers is
				-- unticked.
				if kind.key == "Trainer" then
					local classOnly = Check(content, "nameServiceClassOnly", L["Your class only"],
						L["Leaves out other classes' trainers."], function(value)
						ns.GetDB().nameServiceClassOnly = value
						if ns.ServiceKindsChanged then ns.ServiceKindsChanged() end
						if ns.RefreshAllPlates then ns.RefreshAllPlates() end
					end)
					classOnly:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 20, 0)
					GreyUnless(classOnly, function(db) return db.nameServiceTrainer end)
					subRow = row + 1
					if column == 0 then lastServiceKind = classOnly end
				end
			end
		end
		if subRow and math.ceil(cell / 2) <= subRow then cell = (subRow + 1) * 2 end
		-- Use Questie DB (Support/QuestieMinimap.lua's ns.QuestieGiverNames): Quest
		-- givers by Questie's icons. Greyed out while Questie isn't loaded;
		-- hidden on retail, which Questie never runs on.
		if questiePossible then
			local questieLabel = Label(content, "GameFontHighlight", L["Questie"])
			questieLabel:SetPoint("TOPLEFT", serviceKindsLabel, "TOPLEFT", 0, -math.ceil(cell / 2) * 26 - 6)
			local questie = Check(content, "nameServiceQuestie", L["Quest NPCs (Use Questie DB)"],
				L["Uses Questie's quest marks to find quest givers instead of the game's quest cursor."] .. (ns.QuestieLoaded() and "" or ("\n\n" .. L["Needs Questie: it isn't loaded."])),
				function(value)
					ns.GetDB().nameServiceQuestie = value
					if ns.RefreshAllPlates then ns.RefreshAllPlates() end
				end)
			questie:SetPoint("TOPLEFT", questieLabel, "TOPLEFT", GRID_LABEL + 26, 6)
			GreyUnless(questie, function() return ns.QuestieLoaded() end)
			lastServiceKind = questie
		end
		EndSection(serviceSection, lastServiceKind)
		-- (Extras after Service NPCs in the tabs: made before it, its raid marker row's code first.)
		for i, each in ipairs(sections) do
			if each == extrasSection then
				table.remove(sections, i)
				break
			end
		end
		sections[#sections + 1] = extrasSection

		-- Your target: its plate and its name, whatever its kind's rows say, a
		-- row each (their rules naming kinds of target where they differ). Made
		-- here, after the Names grid's rows, and laid out at the top.
		local targetSection = Section(L["Target"], "Target")
		table.insert(sections, 1, table.remove(sections))
		-- (Dungeons & raids' tab first of all, before Target's.)
		for i, section in ipairs(sections) do
			if section == instanceSection then
				table.insert(sections, 1, table.remove(sections, i))
				break
			end
		end
		BeginSection(targetSection)
		local targetTop = TableTop(targetSection.frame, PLATE_LAYOUT)
		AddPlateRow(targetTop, 1, { "YourTarget", L["Nameplates"] })
		local targetNameTip = L[" Your target's name, even with its kind's names off."] .. nameTip
		AddNameRow(targetTop, 2, targetGroup, "YourTarget", L["Names"], nil, targetNameTip)
		EndSection(targetSection, lastLabel)

		for _, top in ipairs({ targetTop, columnTop, enemyTop, partsTop, playersTop, npcTop, serviceTop, extrasTop }) do
			ns.GridDots(content, top.rows or {})
		end

		-- The tabs, in order: your target's plate and name, enemy nameplates,
		-- friendly nameplates, friendly plates in dungeons and raids, their parts,
		-- then names and raid markers.
		local list, base, height = {}
		for i, section in ipairs(sections) do list[i] = { section.tab } end
		panel, folderTabs, ShowTab, base, height = ns.FolderTabs(content, list, function(i) Pick(sections[i]) end, nil,
			SECTION_WIDTH + 8)
		folderHeight = height
		panelTop:SetPoint("TOPLEFT", handleCheck, "BOTTOMLEFT", 2, -14 - height)
		panel:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
		panel:SetPoint("BOTTOMRIGHT", foot, "TOPLEFT", SECTION_WIDTH + 12, -12)
		-- (On panelTop, not the panel: the panel's bottom hangs on the rows under them.)
		base:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
		LayoutSections()

		canvas:SetScript("OnShow", PageShown(function()
			Refresh()
			LayoutSections() -- (as last left, once the settings have loaded)
		end, content))
	end
	local MakePlates = lazyPages.Add(canvas, "Nameplates", MakeBody)
	-- Two hub tiles: the Nameplates icon and the Names icon, each picking its
	-- grids and showing its tabs.
	local function PickIcon(names)
		ShowSet(names)
		MakePlates("its icon picked")
		if ns.PickPlatesIcon then ns.PickPlatesIcon(names) end
	end
	canvas.hubTabs = {
		{ name = "Nameplates", icon = "Interface\\Icons\\Ability_Hunter_SniperShot", label = "Nameplates",
			onSelect = function() PickIcon(false) end },
		{ name = "Nameplate Names", icon = "Interface\\Icons\\INV_Misc_Note_02", label = "Names", own = true,
			onSelect = function() PickIcon(true) end },
	}
	canvas:Hide()
	RegisterSubpage(canvas, "Nameplates", L["Nameplates"])
end

-- The Style hub's Names page: how names look on nameplates showing just the
-- name (CineMode), with a preview of them at the top. PlateParts draws them.
local function CreateNameStylePanel()
	-- (Each row's Color tab: the colors its names can take, by NAME_ROWS' key;
	-- a row not here, every one (Default, Your target). Friends / Enemies:
	-- the players' segments; Hostile, Neutral, Friendly: the NPC reactions';
	-- class: Color by's Class. Enemy players keep Hostile, for Hostile's color.)
	local NAME_COLOR_PARTS = {
		GroupMembers = { class = true, Friends = true }, Friends = { class = true, Friends = true },
		Enemies = { class = true, Enemies = true, Hostile = true },
		ServiceNPCs = { Friendly = true }, FriendlyNPCs = { Friendly = true },
		NeutralNPCs = { Neutral = true }, HostileNPCs = { Hostile = true },
		FriendlyMinions = { Friendly = true }, GroupMinions = { Friendly = true }, EnemyMinions = { Hostile = true },
	}
	-- (Each kind of service NPC's row: as Service NPCs'.)
	for _, each in ipairs(ns.NAME_ROWS) do
		if each.service then NAME_COLOR_PARTS[each.key] = { Friendly = true } end
	end
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Name Style"])
	-- (The Names icon's Name Style tab, 2026-11-16: its tabs over the title.)
	local nameTabs = ns.PageTabs(content, ns.ShowInTabs("names"), ns.ShowInIndex("names", "Name Style"))
	title:SetPoint("TOPLEFT", nameTabs, "BOTTOMLEFT", 8, -14)
	local subtitle = PageIntro(content, title,
		L["How names look on nameplates that show just the name."])

	local scene -- (below: drawn again as each setting changes)
	local panels = {} -- [row] = its Look panel's preview, once made
	local rowButtons = {}
	local function Changed()
		if ns.NameRowsChanged then ns.NameRowsChanged() end
		if ns.RefreshPlateNameStyle then ns.RefreshPlateNameStyle() end
		-- (All names' outline and shadow reach full plates' names too: PlateRowLook.lua.)
		if ns.RefreshTargetArrows then ns.RefreshTargetArrows() end
		-- (The lines under names: titles' brackets and icons, the line's size and color.)
		if ns.ServiceKindsChanged then ns.ServiceKindsChanged() end
		if ns.RefreshAllPlates then ns.RefreshAllPlates() end
		if ns.RefreshPlateGuilds then ns.RefreshPlateGuilds() end
		if scene then scene:Refresh() end
		for _, button in pairs(rowButtons) do button:Refresh() end
	end
	local function On(db) return db.plateNameStyle end

	-- (Its switch: names as this page says, or as the plates draw them.)
	local switch = PageSwitch(content, "plateNameStyle", L["Enable Page"],
		L["Names look as this page says; off, as the nameplate draws them."], subtitle, Changed)
	local stack = Stack(switch, "check")

	-- A sample name of each kind, drawn as its row says (NameRowLook.lua):
	-- its font, size, outline (in its color), shadow, opacity, color, glow,
	-- band and the line under it. sample: { name, kind: "player"/"npc",
	-- reaction (1-8), class, title }. over: a row's choice pointed at
	-- ({ setting = value }), shown, not saved. off: as the plates draw names.
	local SAMPLES = {
		all = { name = L["Kodo Bull"], kind = "npc", reaction = 4 },
		Target = { name = L["Gnoll Brute"], kind = "npc", reaction = 2 },
		GroupMembers = { name = "Elandra", kind = "player", reaction = 5, class = "PRIEST" },
		Friends = { name = "Thandril", kind = "player", reaction = 5, class = "MAGE" },
		Enemies = { name = "Varek", kind = "player", reaction = 2, class = "ROGUE" },
		ServiceNPCs = { name = L["Innkeeper Allison"], kind = "npc", reaction = 5, title = L["Innkeeper"] },
		FriendlyNPCs = { name = L["Stormwind Guard"], kind = "npc", reaction = 5 },
		NeutralNPCs = { name = L["Kodo Bull"], kind = "npc", reaction = 4 },
		HostileNPCs = { name = L["Gnoll Brute"], kind = "npc", reaction = 2 },
		FriendlyMinions = { name = L["Wolf"], kind = "npc", reaction = 5 },
		GroupMinions = { name = L["Felhunter"], kind = "npc", reaction = 5 },
		EnemyMinions = { name = L["Water Elemental"], kind = "npc", reaction = 2 },
	}
	-- (Each kind of service NPC: a name with a title of that kind.)
	local SERVICE_SAMPLES = { Vendor = { "Thomas Miller", "Bread Merchant" }, Repair = { "Brother Kristoff", "Repair Vendor" },
		Trainer = { "Wilken Gilmore", "Mage Trainer" }, Profession = { "Lee Brown", "Fisherman" },
		Flight = { "Dungar Longdrink", "Gryphon Master" }, Inn = { "Innkeeper Allison", "Innkeeper" },
		Bank = { "Olivia Burnside", "Banker" }, Stable = { "Jenova Stoneshield", "Stable Master" },
		Other = { "Brog Hamfist", "General Supplies" }, Quest = { "Marshal Dughan", nil } }
	for kind, info in pairs(SERVICE_SAMPLES) do
		SAMPLES["Service" .. kind] = { name = info[1], kind = "npc", reaction = 5, title = info[2] and L[info[2]] or nil }
	end
	local REACTION = { { 1, 0, 0 }, { 1, 0, 0 }, { 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 }, { 0, 1, 0 }, { 0, 1, 0 },
		{ 0, 1, 0 } }
	local ROMAN = not ({ ruRU = true, koKR = true, zhCN = true, zhTW = true })[GetLocale and GetLocale() or ""]
	-- The plates' own font, as the game sets it up (or the usual one).
	local function PlateFont()
		local object = _G.SystemFont_NamePlate or _G.SystemFont_NamePlateFixed or _G.GameFontNormal
		local file, size, flags = object:GetFont()
		if not file then
			object = _G.GameFontNormal
			file, size, flags = object:GetFont()
		end
		return object, file, size, flags
	end
	-- A sample: its text, the line under it, and its glow and band behind.
	local function MakeSample(parent)
		local sample = { owner = parent }
		sample.glow = parent:CreateTexture(nil, "ARTWORK", nil, 1)
		sample.glow:SetTexture(ns.NAME_GLOW) -- (PlateParts.lua)
		sample.glow:SetBlendMode("ADD")
		sample.back = parent:CreateTexture(nil, "ARTWORK", nil, 2)
		sample.text = parent:CreateFontString(nil, "OVERLAY")
		sample.text:SetFontObject("GameFontNormal")
		sample.text.searchSkip = true
		sample.line = parent:CreateFontString(nil, "OVERLAY")
		sample.line:SetFontObject("GameFontNormalSmall")
		sample.line:SetPoint("TOP", sample.text, "BOTTOM", 0, -1)
		sample.line.searchSkip = true
		return sample
	end
	local function DrawSample(sample, row, over, scale)
		local db = ns.GetDB()
		local info = SAMPLES[row] or SAMPLES.all
		local text = sample.text
		local function S(setting) return (ns.NameLookValue(row, setting, over)) end
		local object, file, size, flags = PlateFont()
		local styled = db.plateNameStyle
		scale = scale or 1
		if not styled then
			text:SetFontObject(object)
			text:SetShadowOffset(0, 0)
			text:SetAlpha(1)
			text:SetTextColor(1, 1, 1)
			text:SetText(info.name)
			ns.SetTextRim(text, nil)
			sample.glow:Hide()
			sample.back:Hide()
			for _, edge in ipairs(sample.edges or {}) do edge:Hide() end
			sample.line:SetText(info.title and ("<" .. info.title .. ">") or "")
			return
		end
		-- Its font: the row's, All names', else the usual (General's while on).
		local font = S("Font")
		if ROMAN then
			if font == "usual" then
				file = db.styleGeneral and ns.StyleFontFile(db.styleFont) or file
			elseif font ~= "game" then
				file = ns.StyleFontFile(font) or file
			end
		end
		local outline = tonumber(S("Outline")) or 0
		local rim = outline > 0 and S("OutlineColor") == "custom"
		ns.SetPlateNameFont(text, object, file, size, (tonumber(S("Size")) or 1) * scale,
			ns.OutlinedFlags(flags, rim and 0 or outline))
		if S("Shadow") then
			text:SetShadowOffset(db.plateNameShadowX or 1, db.plateNameShadowY or -1)
			text:SetShadowColor(0, 0, 0, tonumber(S("ShadowAlpha")) or 1)
		else
			text:SetShadowOffset(0, 0)
		end
		text:SetAlpha(tonumber(S("Alpha")) or 1)
		-- Its color: as the row's Color tab says.
		local mode = S("Colour")
		local r, g, b = 1, 1, 1
		local classColor = info.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.class]
		local function Reaction()
			local setting = info.reaction <= 3 and "Hostile" or info.reaction == 4 and "Neutral" or "Friendly"
			if info.kind == "npc" and S(setting) == "custom" then return ns.NameLookColor(row, setting, over) end
			return unpack(REACTION[info.reaction])
		end
		if mode == "one" then
			r, g, b = ns.NameLookColor(row, "Colour", over)
		elseif mode == "class" and classColor then
			r, g, b = classColor.r, classColor.g, classColor.b
		elseif mode and info.kind == "player" and info.reaction >= 5 then
			local friends = S("Friends")
			if friends == "class" and classColor then
				r, g, b = classColor.r, classColor.g, classColor.b
			else
				local color = ns.PLATE_FRIEND_COLOURS[friends] or ns.PLATE_FRIEND_COLOURS.blue
				r, g, b = color[1], color[2], color[3]
			end
		elseif mode and info.kind == "player" and S("Enemies") == "class" and classColor then
			r, g, b = classColor.r, classColor.g, classColor.b
		elseif mode then
			r, g, b = Reaction()
		elseif classColor then
			r, g, b = classColor.r, classColor.g, classColor.b
		end
		text:SetTextColor(r, g, b)
		text:SetText(info.name)
		if rim then ns.SetTextRim(text, outline, ns.NameLookColor(row, "OutlineColor", over)) else ns.SetTextRim(text, nil) end
		-- Its glow and band, sized to it.
		local width, height = text:GetStringWidth(), (select(2, text:GetFont())) or 12
		-- (Glow, band and its border: NameRowLook's, as the plates draw them.)
		ns.DressNameParts(sample.owner, sample, text, width, height, S, function(setting)
			return ns.NameLookColor(row, setting, over)
		end)
		-- The line under it: a title (Service NPCs) or a guild (players).
		local under = info.title or (info.kind == "player" and info.reaction >= 5 and L["Guild"]) or nil
		if under then
			local lineSize = tonumber(S("Line2Size")) or 1
			ns.SetPlateNameFont(sample.line, object, file, size, 0.85 * lineSize * scale, flags)
			local lineColor = S("Line2Color")
			if lineColor == "grey" then
				sample.line:SetTextColor(0.72, 0.72, 0.72)
			elseif lineColor == "gold" then
				sample.line:SetTextColor(1, 0.82, 0)
			else
				sample.line:SetTextColor(r, g, b)
			end
			local brackets = not info.title or db.nameServiceBrackets
			sample.line:SetText(brackets and ("<" .. under .. ">") or under)
			sample.line:SetAlpha(tonumber(S("Alpha")) or 1)
		else
			sample.line:SetText("")
		end
	end

	-- The scene: a name of each kind, spread over the lake, each in its row's
	-- look (your target bigger, in front).
	local SCENE_W, SCENE_H = 480, 150
	local SPOTS = {
		{ "Target", 0.5, 0.5 }, { "GroupMembers", 0.16, 0.2 }, { "Friends", 0.5, 0.17 }, { "Enemies", 0.84, 0.2 },
		{ "ServiceNPCs", 0.2, 0.52 }, { "FriendlyNPCs", 0.82, 0.5 }, { "NeutralNPCs", 0.3, 0.82 },
		{ "HostileNPCs", 0.7, 0.82 },
	}
	scene = CreateFrame("Frame", nil, content)
	scene:SetSize(SCENE_W, SCENE_H)
	stack:Add(scene, "label")
	ns.StylePopout(scene, Tooltip) -- (StylePages.lua)
	ns.StyleScene(scene, 0.55, 0.8)
	local caption = Label(scene, "GameFontDisableSmall", L["Preview"])
	caption:SetPoint("TOPLEFT", 6, -5)
	caption.searchSkip = true
	local spots = {}
	for i in ipairs(SPOTS) do spots[i] = MakeSample(scene) end
	-- (The names grow with the scene, however big the page makes it: at the
	-- game's size they were specks in a screen-shaped scene.)
	local sceneScale = 1
	local function PlaceSpots(_, width, height)
		width, height = width or SCENE_W, height or SCENE_H
		sceneScale = math.max(1, math.min(1.8, width / 340))
		for i, spot in ipairs(SPOTS) do
			spots[i].text:ClearAllPoints()
			spots[i].text:SetPoint("CENTER", scene, "TOPLEFT", width * spot[2], -height * spot[3])
		end
		if scene.Refresh and ns.db then scene:Refresh() end
	end
	PlaceSpots(nil, SCENE_W, SCENE_H)
	scene:HookScript("OnSizeChanged", PlaceSpots)
	function scene:Refresh()
		for i, spot in ipairs(SPOTS) do
			-- (scene.zoom: its - and + (StylePages' AddPreviewZoom); names drawn on it, not frames.)
			DrawSample(spots[i], spot[1], nil, (spot[1] == "Target" and 1.25 or 1) * sceneScale * (scene.zoom or 1))
		end
		for _, preview in pairs(panels) do
			if preview:IsVisible() then preview:Refresh() end
		end
	end
	controls[#controls + 1] = scene

	-- Name theme (under the scene): a whole look in one pick, under All names (NameThemes.lua).
	-- Follow main theme first: the main theme's own names. The old presets are
	-- among them (Bold, Subtle; Like the game's names is The game's).
	stack:Header(content, L["Name theme"])
	RecordKey(content, "nameTheme")
	local nameStrip = stack:Add(ns.MakePartThemeStrip(ns.lowHealthKit, content, "name", function() Changed() end), "label")
	local themeNow = stack:Note(content, "", 460)
	themeNow.searchSkip = true
	themeNow.Refresh = function(self)
		local db = ns.GetDB()
		local theme = ns.NameThemeNow()
		local picked = db and db.nameTheme or "main"
		if picked == "main" then
			self:SetText(theme and (L["Following the main theme: %s's names."]):format(L[theme.name])
				or L["Following the main theme: the game's names."])
		else
			self:SetText((L["%s, picked here: it stays when the main theme changes."]):format(theme and L[theme.name] or ""))
		end
		self:SetTextColor(0.6, 0.6, 0.6)
	end
	controls[#controls + 1] = themeNow
	controls[#controls + 1] = nameStrip

	-- Where these names are right now: a warning while they aren't drawn (out
	-- of CineMode, or in it where plates aren't kept on), a calm line while
	-- they are. The game's own names over heads can't be styled by addons.
	local whereNote = stack:Note(content, "", 460)
	whereNote.searchSkip = true
	local WARN = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14:14|t "
	local OK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t "
	local whereState
	local function UpdateWhere()
		local cine = ns.lastCinematic and true or false
		local state = not cine and "out" or (ns.PlatesForcedHere(cine) and "on" or "here")
		if state == whereState then return end
		whereState = state
		if state == "on" then
			whereNote:SetText(OK .. L["In CineMode: names near you are drawn by their nameplates and look as this " ..
				"page says. Further off, the game's own names show, which addons can't resize or fade."])
			whereNote:SetTextColor(0.6, 0.9, 0.6)
		elseif state == "here" then
			whereNote:SetText(WARN .. L["In CineMode, but names here are the game's own (in dungeons and raids, " ..
				"or with the Nameplates page off): this page doesn't change them, and addons can't resize or fade them. " ..
				"The preview shows this page's look."])
			whereNote:SetTextColor(1, 0.82, 0)
		else
			whereNote:SetText(WARN .. L["Not in CineMode: names over heads are the game's own, which addons can't " ..
				"resize or fade. This page's look shows on names near you once you're in CineMode (the preview shows it now)."])
			whereNote:SetTextColor(1, 0.82, 0)
		end
	end
	local whereAt = 0
	ns.HookOnUpdate(canvas, function()
		if GetTime() < whereAt then return end
		whereAt = GetTime() + 0.25
		UpdateWhere()
	end)
	canvas:HookScript("OnShow", UpdateWhere)

	-- (The Style pages' rows, StylePages.lua: each greyed by this page's own
	-- switch, as General's doesn't reach these names.)
	local rows = ns.StyleRows(ns.lowHealthKit, content, stack, Changed, "plateNameStyle")

	-- The rows: All names (the page's own settings), then a row per kind of
	-- unit, each a Look panel (made the first time it's opened): Text, Color,
	-- Glow, Background and Second line. A row's setting left on Inherit takes
	-- All names', and All names' the game's.
	stack:Header(content, L["Names"])
	local TAB_NAMES = { Font = "Text", Size = "Text", Alpha = "Text", Outline = "Text", OutlineColor = "Text",
		Shadow = "Text", ShadowAlpha = "Text", Colour = "Color", Friends = "Color", Enemies = "Color",
		Hostile = "Color", Neutral = "Color", Friendly = "Color", Glow = "Glow", Back = "Background",
		BackAlpha = "Background", Line2Size = "Second line", Line2Color = "Second line",
		GlowAlpha = "Glow", GlowSize = "Glow", BackBorder = "Background", BackBorderSize = "Background" }
	local OUTLINE_NAMES = { [0] = L["None"], L["Thin"], L["Thick"] }
	local function Words(setting, value)
		if setting == "Font" then
			if value == "usual" then return L["General's or the game's"] end
			return value == "game" and L["The game's"] or ns.StyleFontName(value)
		elseif setting == "Outline" then
			return OUTLINE_NAMES[tonumber(value) or 0] or tostring(value)
		elseif setting == "Size" or setting == "Alpha" or setting == "ShadowAlpha" or setting == "BackAlpha"
			or setting == "Line2Size" or setting == "GlowAlpha" or setting == "GlowSize" then
			return ("%d%%"):format(math.floor((tonumber(value) or 1) * 100 + 0.5))
		elseif setting == "Shadow" then
			return value and L["Shadow"] or L["None"]
		elseif setting == "Colour" then
			return ({ [true] = L["How they see you"], [false] = L["The plate's"], class = L["Class colors"],
				one = L["One color"] })[value] or tostring(value)
		end
		local WORDS = { blue = L["Blue"], class = L["Class colors"], white = L["White"], react = L["Hostile's color"],
			game = L["The game's"], custom = L["Custom"], black = L["Black"], none = L["None"], soft = L["Soft glow"],
			band = L["Band"], name = L["Name's"], grey = L["Grey"], gold = L["Gold"] }
		return WORDS[value] or tostring(value)
	end
	local function RowSource(row, setting)
		local db = ns.GetDB() or {}
		local own = db[ns.NameLookKey(row, setting)]
		own = own ~= nil and own ~= "inherit"
		local parent, short
		-- (From the nearest row up that sets it (2026-11-16: rows inherit along
		-- NAME_ROWS' parents), else Default's, the theme's or the game's.)
		local above = row ~= "all" and (ns.NAME_ROW_PARENT[row] or "all") or nil
		local from = above and select(2, ns.NameLookValue(above, setting)) or select(2, ns.NameLookValue("all", setting))
		if from ~= "all" and from ~= "theme" and from ~= "game" and ns.NameRowLabel(from) then
			parent, short = (L["%s's"]):format(ns.NameRowLabel(from)), ns.NameRowLabel(from)
		elseif from == "all" and row == "Target" then
			-- (Your target: its own kind's row first, then Default's. 2026-11-16.)
			parent, short = L["Its kind's row, else Default's"], L["Its kind's"]
		elseif from == "all" and row ~= "all" then
			parent, short = L["Default's"], L["Default"]
		elseif from == "theme" or (from == "all" and row == "all" and ns.NameThemeLook()
			and ns.NameThemeLook()[setting] ~= nil) then
			local theme = ns.NameThemeNow()
			parent, short = (L["Name theme: %s"]):format(theme and L[theme.name] or ""), L["theme"]
		end
		if not parent then parent = L["The game's"] end
		return { text = own and (row == "all" and L["Set here"] or L["This row"]) or parent, own = own,
			parent = parent, short = short }
	end
	local function ParentValue(row, setting)
		if row == "all" then
			local themed = ns.NameThemeLook()
			if themed and themed[setting] ~= nil then return themed[setting] end
			return ns.NAME_LOOK_GAME[setting]
		end
		local above = ns.NAME_ROW_PARENT[row]
		return (ns.NameLookValue(above or "all", setting))
	end

	-- A row's Look panel: its keys through a field each (nameLook<row><setting>,
	-- All names' plateName<setting>), "inherit" saved as no value.
	local function OpenRow(row, label)
		if rowButtons[row].pop then
			rowButtons[row].pop:SetShown(not rowButtons[row].pop:IsShown())
			return
		end
		local function FieldOf(key)
			-- (The service titles' own settings, the same for every row.)
			if key:find("^nameService") then return key end
			local dbKey = ns.NameLookKey(row, key)
			RecordKey(content, dbKey)
			return { get = function()
				local value = ns.GetDB()[dbKey]
				if value == nil then
					if row == "all" then value = ns.DEFAULTS[dbKey] else value = ns.NameRowDefault(dbKey) end
				end
				return value
			end, set = function(value)
				local default = row == "all" and ns.DEFAULTS[dbKey] or ns.NameRowDefault(dbKey)
				if value == default then value = nil end
				ns.GetDB()[dbKey] = value
			end }
		end
		local function DefaultOf(key)
			if key:find("^nameService") then return nil end -- (not this row's: never reset with it)
			local dbKey = ns.NameLookKey(row, key)
			if row == "all" then return ns.DEFAULTS[dbKey] end
			return ns.NameRowDefault(dbKey)
		end
		local function Own(setting)
			local value = ns.GetDB()[ns.NameLookKey(row, setting)]
			return value ~= nil and value ~= "inherit" and value or nil
		end
		local INHERIT = { "inherit", L["Inherit"], row == "all" and L["The name theme's look, else the game's."] or
			L["Follows the Default row's look, else the game's."] }
		local hidden = { Add = function(_, control)
			control:Hide()
			return control
		end }
		local styleRows = ns.StyleRows(ns.lowHealthKit, content, hidden, Changed, "plateNameStyle", FieldOf)
		local service = row == "all" or row == "ServiceNPCs" or row:find("^Service") ~= nil
		local button, pop = styleRows.Look("", label, {
			tabs = {
				default = DefaultOf,
				usual = function(key)
					if key:find("^nameService") then return nil end
					return Words(key, ParentValue(row, key)), ParentValue(row, key)
				end,
				source = function(key)
					if key:find("^nameService") then return nil end
					return RowSource(row, key)
				end,
				resolved = function(key) return ParentValue(row, key) end,
				copyKind = "nameRow", copyName = label,
				-- (Start from a theme: a name theme's look in just this row.)
				themeList = function()
					local list = {}
					for _, theme in ipairs(ns.NameThemeList()) do list[#list + 1] = { key = theme.key, name = L[theme.name] } end
					return list
				end,
				themeLook = function(key)
					local theme = ns.NameThemeByKey(key)
					if not theme then return nil end
					local look = {}
					for setting, value in pairs(theme.look) do look[setting] = value end
					return look
				end,
				resetLabel = function() return row == "all" and L["Reset all"] or L["Clear this row"] end,
			},
			preview = function(parent, width)
				local holder = CreateFrame("Frame", nil, parent)
				holder:SetSize(width, 96)
				ns.StyleScene(holder, 0.55, 0.85)
				local sample = MakeSample(holder)
				sample.text:SetPoint("CENTER", holder, "CENTER", 0, 8)
				local tag = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				tag:SetPoint("TOPRIGHT", -8, -6)
				tag.searchSkip = true
				function holder.Refresh(_, over, note)
					tag:SetShown(over ~= nil)
					tag:SetText(note or L["Preview: not saved"])
					DrawSample(sample, row, over, 1.6 * (holder.zoom or 1))
				end
				-- (Its name drawn on it, not a frame: zoomed by its own size.)
				function holder.OnZoom() end
				holder:SetScript("OnShow", function(self) self:Refresh() end)
				panels[row] = holder
				return holder
			end,
			font = function(look)
				look.Font("Font", L["The names' font."], nil, INHERIT)
			end,
			textSize = function(look)
				-- (Up to 400%, 2026-11-16: a target's name can be made to stand out.)
				look.Pair(true) -- (Size and Opacity on one line, 2026-11-16)
				look.Slider("Size", L["Size"], 50, 400, 10, "%d%%", 100, L["How big the names are, next to the plates' own."])
				look.Slider("Alpha", L["Opacity"], 20, 100, 5, "%d%%", 100,
					L["How see-through the names are, on top of their fades."])
				look.Pair(false)
			end,
			textColor = false,
			outline = function(look)
				look.Segments(L["Outline"], "Outline", { INHERIT, { 0, L["None"] }, { 1, L["Thin"] }, { 2, L["Thick"] } },
					L["A border around the letters."], nil, "outline")
			end,
			outlineColor = function(look)
				local function Custom(db) return look.On(db) and Own("OutlineColor") == "custom" end
				local function Outlined(db)
					return look.On(db) and (tonumber((ns.NameLookValue(row, "Outline"))) or 0) > 0
				end
				-- (Under Outline, indented: its parts, 2026-11-16.)
				look.Sub(true)
				look.Segments(L["Outline color"], "OutlineColor", { INHERIT, { "black", L["Black"] },
					{ "custom", L["Custom"], L["An outline in your own color; costs more with many names up."] } }, nil, Outlined)
				look.Chips(L["Its color"], { "OutlineR", "OutlineG", "OutlineB" }, nil, Custom)
				look.Sub(false)
			end,
			shadow = function(look)
				look.Segments(L["Shadow"], "Shadow", { INHERIT, { true, L["Shadow"],
					L["A dark copy of the letters just behind them, to lift them off the world."] }, { false, L["None"] } })
				look.Sub(true) -- (under Shadow, indented; half as long, 2026-11-16)
				look.Pair(true)
				look.Slider("ShadowAlpha", L["Shadow opacity"], 0, 100, 5, "%d%%", 100, L["How dark the shadow is."],
					function(db) return look.On(db) and ns.NameLookValue(row, "Shadow") == true end)
				look.Pair(false)
				look.Sub(false)
			end,
			nameColor = function(look)
				-- (The Default row: no One color or its picker, 2026-11-16: every kind
				-- of name in one color undoes the rows' own, as the plates' did.)
				-- (Only the colors this row's names can take, 2026-11-16: an NPC row
				-- has no players' or other reactions' colors, nor Class; the
				-- Default row and Your target, every kind of unit, have them all.)
				local parts = NAME_COLOR_PARTS[row]
				-- (How they see you only where names of every reaction share the row,
				-- 2026-11-16: Default, Your target. A row of one kind of unit has its
				-- color below; Inherit gives Default's way.)
				local choices = { INHERIT }
				if not parts then
					choices[#choices + 1] = { true, L["How they see you"], L["Red for hostile, yellow for neutral and green for friendly units."] }
				end
				if not parts or parts.class then
					choices[#choices + 1] = { "class", L["Class"], L["Players in their class's color, the rest as how they see you."] }
				end
				-- (No One color on an NPC row, 2026-11-16: its reaction's Custom below
				-- is that one color already.)
				local npcRow = parts and not parts.Friends and not parts.Enemies
				if row ~= "all" and not npcRow then choices[#choices + 1] = { "one", L["One color"] } end
				choices[#choices + 1] = { false, L["The plate's"], L["The plate's own color, white or gray."] }
				look.Segments(L["Color by"], "Colour", choices)
				if row ~= "all" and not npcRow then
					look.Chips(L["Color"], { "ColourR", "ColourG", "ColourB" }, nil,
						function(db) return look.On(db) and Own("Colour") == "one" end)
				end
				-- (The Default row: Color by alone, 2026-11-16. Each kind's color is
				-- on its own row; Your target takes them from its kind's.)
				if row == "all" then return end
				local function Reacting(db)
					local mode = ns.NameLookValue(row, "Colour")
					return look.On(db) and mode ~= "one" and mode ~= false
				end
				if not parts or parts.Friends then
					look.Segments(L["Friendly players"], "Friends", { INHERIT,
						{ "blue", L["Blue"], L["Blue, as the game's names over their heads."] },
						{ "class", L["Class colors"], L["Their class's color; also turns on the game's class colors for nameplates."] },
						{ "white", L["White"] } }, nil, Reacting)
				end
				if not parts or parts.Enemies then
					look.Segments(L["Enemy players"], "Enemies", { INHERIT, { "react", L["Hostile's color"] },
						{ "class", L["Class colors"] } }, nil, Reacting)
				end
				for _, each in ipairs({ { "Hostile", L["Hostile"] }, { "Neutral", L["Neutral"] },
					{ "Friendly", L["Friendly"] } }) do
					if not parts or parts[each[1]] then
						look.Segments(each[2], each[1], { INHERIT, { "game", L["The game's"] }, { "custom", L["Custom"] } },
							L["NPCs of this reaction in a color of your own."], nil)
						look.Chips(each[2] .. " " .. L["color"], { each[1] .. "R", each[1] .. "G", each[1] .. "B" }, nil,
							function(db) return look.On(db) and Own(each[1]) == "custom" end)
					end
				end
			end,
			glow = function(look)
				look.Segments(L["Glow"], "Glow", { INHERIT, { "none", L["None"] },
					{ "soft", L["Soft glow"], L["A soft light behind the name."] } })
				-- (No picker on the Default row, 2026-11-16: one color for every
				-- name's glow, as One color was. The theme's own still comes through.)
				if row ~= "all" then
					look.Chips(L["Glow color"], { "GlowR", "GlowG", "GlowB" }, nil,
						function(db) return look.On(db) and Own("Glow") == "soft" end)
				end
				-- (Its opacity and size, 2026-11-16, under it.)
				local function Glowing(db) return look.On(db) and ns.NameLookValue(row, "Glow") ~= "none" end
				look.Sub(true)
				look.Pair(true)
				look.Slider("GlowAlpha", L["Opacity"], 10, 100, 5, "%d%%", 100, L["How strong the glow is."], Glowing)
				look.Slider("GlowSize", L["Size"], 50, 300, 10, "%d%%", 100, L["How far the glow spreads round the name."],
					Glowing)
				look.Pair(false)
				look.Sub(false)
			end,
			backColor = function(look)
				look.Segments(L["Behind the name"], "Back", { INHERIT, { "none", L["Nothing"] },
					{ "band", L["Band"], L["A band of color behind the name."] } })
				local function Banded(db) return look.On(db) and ns.NameLookValue(row, "Back") ~= "none" end
				if row ~= "all" then -- (as the glow's: none on the Default row)
					look.Chips(L["Color"], { "BackR", "BackG", "BackB" }, nil,
						function(db) return look.On(db) and Own("Back") == "band" end)
				end
				look.Sub(true)
				look.Pair(true)
				look.Slider("BackAlpha", L["Opacity"], 10, 100, 5, "%d%%", 100, L["How see-through the band is."], Banded)
				look.Pair(false)
				-- (A border round the band, 2026-11-16: its color and thickness.)
				look.Segments(L["Border"], "BackBorder", { INHERIT, { "none", L["None"] },
					{ "line", L["Line"], L["A line round the band."] } }, nil, Banded)
				local function Edged(db) return Banded(db) and ns.NameLookValue(row, "BackBorder") == "line" end
				look.Sub(false)
				look.Sub(true)
				look.Chips(L["Border color"], { "BackBorderR", "BackBorderG", "BackBorderB" }, nil, Edged)
				look.Pair(true)
				look.Slider("BackBorderSize", L["Thickness"], 1, 4, 1, "%d", 1, L["How thick the band's border is, in pixels."],
					Edged)
				look.Pair(false)
				look.Sub(false)
			end,
			backAlpha = false,
			line2 = function(look)
				look.Slider("Line2Size", L["Size"], 50, 120, 5, "%d%%", 100,
					L["The guild or title under the name, next to the name's size."])
				look.Segments(L["Color"], "Line2Color", { INHERIT, { "name", L["Name's"] }, { "grey", L["Grey"] },
					{ "gold", L["Gold"] } })
				-- (Service NPCs' titles: the same for every row that shows them.)
				if service then
					look.Toggle("nameServiceBrackets", L["Brackets round titles"],
						L["Shows NPC titles with their < > brackets."])
					look.Toggle("nameServiceBracketsWithName", L["When the name shows too"],
						L["Keeps the < > on a title shown under its NPC's name."])
					look.Toggle("nameServiceIcons", L["Icons for titles"],
						L["An icon in place of a service NPC's title (an anvil for repairs...)."])
					look.Slider("nameServiceIconScale", L["Icon size"], 50, 200, 5, "%d%%", 100,
						L["How big the title icons are."], function(db) return look.On(db) and db.nameServiceIcons end)
				end
			end,
		})
		if button then button:Hide() end
		rowButtons[row].pop = pop
		pop:Show()
	end
	for _, info in ipairs(ns.NAME_ROWS) do
		local row = info.key
		for _, key in ipairs(ns.NameRowKeys(row)) do RecordKey(content, key) end
		-- (Indented under the row it inherits from, a step a level. Default and
		-- the rows right under it flush left.)
		local shownLabel = info.label
		if (info.depth or 0) > 1 then shownLabel = ("     "):rep(info.depth - 1) .. info.label end
		local name = stack:Add(Label(content, "GameFontHighlight", shownLabel), "label")
		name.searchLabel = info.label
		name:SetSize(195, 26) -- (room for the deepest, Group members' minions, indented)
		name:SetJustifyV("MIDDLE")
		local button = ns.PanelButton(content)
		button:SetHeight(22)
		button:SetPoint("LEFT", name, "RIGHT", 4, 0)
		-- (A thin line under the Default row: the rows below start on it. 2026-11-16.)
		if row == "all" then
			local line = content:CreateTexture(nil, "ARTWORK")
			line:SetColorTexture(0.45, 0.38, 0.2, 0.8)
			line:SetHeight(1)
			line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
			line:SetPoint("RIGHT", name, "RIGHT", 4 + 300, 0)
		end
		button.searchLabel = info.label
		Tooltip(button, row == "all" and L["Every name's look; each row below starts from it."]
			or L["This kind's own look, over the row it's under."])
		button:SetScript("OnClick", function() OpenRow(row, info.label) end)
		function button.Refresh(self)
			local db = ns.GetDB()
			local tabs, seen = {}, {}
			for setting, tab in pairs(TAB_NAMES) do
				local value = db and db[ns.NameLookKey(row, setting)]
				if value ~= nil and value ~= "inherit" and not seen[tab] then
					seen[tab] = true
					tabs[#tabs + 1] = L[tab]
				end
			end
			table.sort(tabs)
			local inherits = false
			if #tabs > 0 then
				self:SetText(L["Own:"] .. " " .. table.concat(tabs, " · "))
			elseif row == "all" then
				self:SetText(ns.NameThemeNow() and L["The name theme's"] or L["The game's"])
			else
				-- (The row right above it, which it goes by (2026-11-16); Default
				-- for the rows right under Default.)
				local above = ns.NAME_ROW_PARENT[row]
				local aboveLabel = above and ns.NameRowLabel(above)
				-- (Your target: whatever its kind's row says, under its own.)
				if row == "Target" then aboveLabel = L["Its kind's row"] end
				self:SetText(aboveLabel or L["Default"])
				inherits = true
			end
			-- (Grey while it has nothing of its own: it's all the Default row's.)
			local words = self:GetFontString()
			if words then
				if inherits then words:SetTextColor(0.6, 0.6, 0.6) else words:SetTextColor(1, 0.82, 0) end
			end
			self:SetWidth(math.max(140, self:GetFontString():GetStringWidth() + 30))
			self:SetEnabled(db and db.plateNameStyle and true or false)
		end
		rowButtons[row] = button
		controls[#controls + 1] = button
	end

	-- Distance and timing. Retail's plates scale themselves: one size, and
	-- names raised as a whole. WoW Forever's don't, so names are sized and
	-- placed by the camera's zoom (PlateParts' Look): set at two points,
	-- close and far, following perspective between them and on past far. The
	-- camera's distance now shows under them, to set each with the camera
	-- there. (Each name's own size and opacity: its row's Text tab.)
	-- (Hidden for now, 2026-11-16: hard for players to read; names' size is on
	-- their rows' Text tab. The settings still work as they are.)
	local SHOW_DISTANCE = false
	if SHOW_DISTANCE then stack:Header(content, L["Distance and timing"]) end
	local function HideDelayBox(boxes)
		boxes:Box(L["Hide delay"], "plateNameHideDelay", 0, 10, 0.1, "%.1f", 1,
			L["How long a unit stays out of sight before its name hides."], On, L["sec"])
		boxes:Box(L["Fade time"], "plateNameFadeTime", 0, 5, 0.1, "%.1f", 1,
			L["How long a name takes to fade in or out."], On, L["sec"])
	end
	if not SHOW_DISTANCE then -- luacheck: ignore 542
	elseif ns.isRetail then
		local sizes = rows.Boxes()
		sizes:Box(L["Raise"], "plateNameY", -30, 30, 1, "%d", 1,
			L["Moves the names up (or down, below 0) from where the plates put them."], On)
		HideDelayBox(sizes)
		rows.Check("plateNameFixedSize", L["Same size at any distance"],
			L["Names keep one size at any distance."], On)
	else
		local fades = rows.Boxes()
		HideDelayBox(fades)
		stack:Header(content, L["Close (camera zoomed all the way in)"])
		local close = rows.Boxes()
		close:Box(L["Size"], "plateNameCloseSize", 50, 300, 5, "%d", 100,
			L["How big names are with the camera zoomed all the way in."], On, "%")
		close:Box(L["Raise"], "plateNameCloseY", -40, 60, 1, "%d", 1,
			L["Moves names up or down with the camera zoomed all the way in."], On)
		stack:Header(content, L["Far (camera about 34 yards from you)"])
		local far = rows.Boxes()
		far:Box(L["Size"], "plateNameFarSize", 20, 100, 5, "%d", 100,
			L["How big names are with the camera zoomed far out."],
			On, "%")
		far:Box(L["Raise"], "plateNameFarY", -60, 10, 1, "%d", 1,
			L["Moves names up or down with the camera zoomed far out."], On)
		-- (Every unit counts as 16 yards from you: PlateParts' UNIT_YARDS.)
		local cameraNote = stack:Note(content, "", 460)
		cameraNote.searchSkip = true
		local noteAt = 0
		ns.HookOnUpdate(canvas, function()
			if GetTime() < noteAt then
				return
			end
			noteAt = GetTime() + 0.2
			local zoom = math.floor((GetCameraZoom and GetCameraZoom() or 0) + 0.5)
			cameraNote:SetText((L["The camera is %d yards from you: every name is sized as if its unit were " ..
				"about %d yards from it."]):format(zoom, zoom + 16))
		end)
	end

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Name Style", L["Name Style"])
end

-- The Style hub's Nameplates page (Nameplate Style): how the Nameplates page's Target
-- Indicator row looks (PlateParts draws it), a grid with a row for each kind
-- of unit it marks (your target, your target while it's after you, your
-- focus, the one under the mouse): whether it shows, its mark, color, which
-- of the unit's own parts take the color, size and movement. A preview of
-- each on a plate at the top; under the grid, the height of marks over the plate.
-- (In a block: the main chunk's locals are near Lua's cap.)
local CreateTargetArrowPanel
do
	-- The grid's rows: kind, label, tip. Aggro goes by your target's size
	-- and movement (no cells of its own for them), and by its style, color
	-- and Also color where they say Your target's.
	local MARK_KINDS = {
		{ "aggro", L["Aggro on you"], L["Any enemy attacking you."] },
		{ "target", L["Target"], L["Your target."] },
		{ "focus", L["Focus"], L["Your focus."] },
		{ "mouseover", L["Mouseover"], L["The unit under your mouse."] },
		{ "others", L["Default"], L["Every plate no row above fits."] },
	}
	-- (- first: no mark.)
	local MARK_STYLES = {
		{ value = "none", text = "-" },
		{ value = "arrow", text = L["Arrow"] },
		{ value = "chevron", text = L["Chevron"] },
		{ value = "diamond", text = L["Diamond"] },
		{ value = "glow", text = L["Glow"] },
		{ value = "brackets", text = L["Brackets"] },
		{ value = "carets", text = L["Carets"] },
		{ value = "corners", text = L["Corners"] },
		{ value = "underline", text = L["Underline"] },
	}
	-- (The unit under the mouse: just the marks over its plate. Round it or
	-- under it, they hang in the air where its plate is hidden.)
	local MOUSEOVER_STYLES = {
		{ value = "none", text = "-" },
		{ value = "arrow", text = L["Arrow"] },
		{ value = "chevron", text = L["Chevron"] },
		{ value = "diamond", text = L["Diamond"] },
	}
	-- (Aggro: -, then Your target's, then the rest.)
	local AGGRO_STYLES = { MARK_STYLES[1], { value = "same", text = L["Your target's"] } }
	for i = 2, #MARK_STYLES do AGGRO_STYLES[#AGGRO_STYLES + 1] = MARK_STYLES[i] end
	-- (Default's: its - is the game's own look, no mark.)
	local OTHERS_STYLES = { { value = "none", text = L["The game's"] } }
	for i = 2, #MARK_STYLES do OTHERS_STYLES[#OTHERS_STYLES + 1] = MARK_STYLES[i] end
	local MARK_COLORS = {
		{ value = "gold", text = L["Gold"] },
		{ value = "reaction", text = L["By reaction"] },
		{ value = "class", text = L["Class colors"] },
		{ value = "custom", text = L["Custom"] },
	}
	local AGGRO_COLORS = { { value = "same", text = L["Your target's"] } }
	for _, choice in ipairs(MARK_COLORS) do AGGRO_COLORS[#AGGRO_COLORS + 1] = choice end
	-- (A plate's: - none, the next row's; the game's; the mark's; then as the mark's.)
	local PLATE_COLORS = { { value = "-", text = "-" }, { value = "game", text = L["The game's"] },
		{ value = "same", text = L["Mark's"] } }
	for _, choice in ipairs(MARK_COLORS) do PLATE_COLORS[#PLATE_COLORS + 1] = choice end
	-- The setting for a kind's cell (see Core's DEFAULTS).
	local function MarkKey(kind, key)
		return kind == "target" and "targetArrow" .. key or kind .. "Mark" .. key
	end
	-- A row's line: where its parts start, from its left, and its size; its
	-- drawer under it, in from the left, a line each (Row, Name, Mark, Color,
	-- Plate, When; Default's own no Row: it's always there).
	-- (Name first, then a column each: Mark (its preview), Plate (its
	-- chips: opacity, colors, size) and When (its chip), each a heading over
	-- the grid, in the color its drawer line's name has (COLUMN_COLORS).)
	local SHOW_X, NAME_X, PREVIEW_X, PLATE_X, WHEN_X = 16, 44, 232, 290, 414
	local ROW_W, NAME_W, PLATE_W, WHEN_W, NUMBER_W = 590, 186, 118, 128, 30 -- (When: up to the copy button)
	local COLUMN_COLORS = { Mark = { 0.85, 0.65, 1 }, Plate = { 1, 0.8, 0.35 }, When = { 0.55, 0.8, 1 } }
	local DRAWER_X, LINE_H, LABEL_W = 44, 34, 48
	-- The Also color column's parts: setting (<kind>Color<part>), name, tip,
	-- and (targetOnly) whether only your target's plate has one: the game's
	-- border, round your target's health bar alone.
	local ALSO_PARTS = {
		{ "Name", L["Name"], L["The unit's name in its mark's color, on its plate or shown alone."] },
		{ "Bar", L["Health bar"], L["The unit's health bar in its mark's color."] },
		{ "Border", L["Border"], L["The border the game puts round your target's health bar, in its mark's " ..
			"color."], targetOnly = true },
	}
	local ALSO_SHORT = { Name = L["Name"], Bar = L["Bar"], Border = L["Border"] }
	local ROW_H = 28
	function CreateTargetArrowPanel()
		local canvas, content = CreateScrollPage()

		local title = Label(content, "GameFontNormalLarge", L["Nameplate Style"])
		-- (The Nameplates icon's Plate Style tab, 2026-11-16: its tabs over the title.)
		local plateTabs, ShowPlateTab = ns.PageTabs(content, ns.ShowInTabs("plates"), ns.ShowInIndex("plates", "Nameplate Style"))
		title:SetPoint("TOPLEFT", plateTabs, "BOTTOMLEFT", 8, -14)
		-- (Two parts, each the Nameplates icon's tab (2026-11-16): Plate Style
		-- (Show in, the theme) and Marks (its rows, a page of their own in all
		-- but name); the preview shown with both. ShowPart: made with the body.)
		local ShowPart
		local subtitle = PageIntro(content, title,
			L["Makes your target, focus and mouseover stand out on the nameplates."])
		-- (A warning triangle past the "?": friendly plates are the game's in
		-- dungeons and raids, as on the Nameplates page's Dungeons & raids tab.)
		PageIntro(content, content.pageHelp or title,
			L["Friendly plates in dungeons and raids"] .. "\n\n" ..
			L["In dungeons and raids, this page can't change friendly nameplates."], nil, true)

		local preview -- (below: drawn again as each setting changes)
		local function Changed()
			if ns.RefreshTargetArrows then ns.RefreshTargetArrows() end
			if preview then preview:Refresh() end
		end
		-- (Its switch: the marks and their colors on the plates, or none at all.)
		local switch = PageSwitch(content, "handlePlateStyle", L["Enable Page"],
			L["Turns this page's marks and colors on or off."], subtitle, Changed)
		-- (Everything below is made the first time the page is needed: lazyPages.)
		local function MakeBody()
			-- (What's on the page before the body: neither part's.)
			local before = {}
			for _, object in ipairs({ content:GetChildren() }) do before[object] = true end
			for _, object in ipairs({ content:GetRegions() }) do before[object] = true end
			local stack = Stack(switch, "check")
			-- Where they show: a Show in row (PlateIcons.lua, as the Icons page's).
			local showHeader = stack:Header(content, L["Show in"])
			-- (No Cine column: whether plates work outside CineMode is the CineMode
			-- page's Outside CineMode > Nameplates; a Cine tick moved to Always,
			-- PlateIcons.lua's MigratePlateIconWhen.)
			local showRow = ShowTable(content, showHeader, { opts = { anyFight = true }, underHeader = true,
				ns.TargetMarksShowRow(Changed) }, L["Nameplate Style"])
			stack:Continue(showRow, "label")

			-- The preview, as the Unit Frame Style page's: a scene of plates, one
			-- for each row of the grid (the first few, Default at the back), each
			-- drawn as this client's own plates are (its name over the bar,
			-- Forever's level box at the bar's right end) and dressed by its row:
			-- its mark, its name and health bar in their colors or its Also
			-- color's, the game's border round your target's bar, its opacity and
			-- size. The row being edited glows; a plate clicked opens its row.
			local previewed = "others"
			preview = CreateFrame("Frame", nil, content)
			preview:SetSize(560, 190)
			stack:Add(preview, "label")
			ns.StylePopout(preview, Tooltip) -- (StylePages.lua)
			if preview.SetClipsChildren then preview:SetClipsChildren(true) end
			local caption = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			caption:SetPoint("TOPLEFT", 6, -5)
			caption:SetText(L["Preview"])
			caption.searchSkip = true
			-- (Spots on the scene, as fractions of it, and a scale: the nearer
			-- ones first and larger; Default's at the back.)
			local SPOTS = { { 0.27, 0.42, 1 }, { 0.73, 0.40, 1 }, { 0.16, 0.76, 0.9 }, { 0.5, 0.70, 0.95 },
				{ 0.84, 0.76, 0.9 } }
			local BAR_W, BAR_H = 120, 10
			local WHO_COLORS = { Enemy = { 0.75, 0.1, 0.1 }, Neutral = { 0.85, 0.75, 0 }, Friendly = { 0, 0.6, 0.1 } }
			local GAME_FILL = "Interface\\TargetingFrame\\UI-StatusBar"
			local plates = {}
			local function MakeSample(n)
				local plate = CreateFrame("Button", nil, preview)
				plate:SetSize(BAR_W + 40, 44)
				plate.bar = CreateFrame("Frame", nil, plate)
				plate.bar:SetSize(BAR_W, BAR_H)
				plate.bar:SetPoint("CENTER", plate, "CENTER", -8, -4)
				plate.bar:SetFrameLevel(plate:GetFrameLevel() + 2)
				local edge = plate.bar:CreateTexture(nil, "BORDER")
				edge:SetPoint("TOPLEFT", -1, 1)
				edge:SetPoint("BOTTOMRIGHT", 1, -1)
				edge:SetColorTexture(0, 0, 0, 1)
				plate.back = plate.bar:CreateTexture(nil, "ARTWORK", nil, -1)
				plate.back:SetAllPoints()
				plate.fill = plate.bar:CreateTexture(nil, "ARTWORK")
				plate.fill:SetPoint("TOPLEFT")
				plate.fill:SetPoint("BOTTOMLEFT")
				plate.fill:SetTexture(GAME_FILL)
				-- (The game's border round your target's bar: 2 pixels, just outside its black edge.)
				plate.border = {}
				for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
					local line = plate.bar:CreateTexture(nil, "BORDER", nil, 1)
					if side == "TOP" or side == "BOTTOM" then
						line:SetPoint(side .. "LEFT", edge, side .. "LEFT", -2, side == "TOP" and 2 or -2)
						line:SetPoint(side .. "RIGHT", edge, side .. "RIGHT", 2, side == "TOP" and 2 or -2)
						line:SetHeight(2)
					else
						line:SetPoint("TOP" .. side, edge, "TOP" .. side, side == "LEFT" and -2 or 2, 0)
						line:SetPoint("BOTTOM" .. side, edge, "BOTTOM" .. side, side == "LEFT" and -2 or 2, 0)
						line:SetWidth(2)
					end
					plate.border[#plate.border + 1] = line
				end
				-- (Forever's level, in a box of its own at the bar's right end; retail's plates have none.)
				if not ns.isRetail then
					plate.level = CreateFrame("Frame", nil, plate.bar)
					plate.level:SetSize(20, BAR_H + 4)
					plate.level:SetPoint("LEFT", plate.bar, "RIGHT", 4, 0)
					local levelEdge = plate.level:CreateTexture(nil, "BORDER")
					levelEdge:SetAllPoints()
					levelEdge:SetColorTexture(0.8, 0.65, 0.25, 1)
					local levelBack = plate.level:CreateTexture(nil, "ARTWORK")
					levelBack:SetPoint("TOPLEFT", 1, -1)
					levelBack:SetPoint("BOTTOMRIGHT", -1, 1)
					levelBack:SetColorTexture(0.05, 0.04, 0.03, 0.9)
					local levelText = plate.level:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					levelText:SetPoint("CENTER", 0, 0)
					levelText:SetText(tostring(18 + n))
					levelText.searchSkip = true
				end
				plate.name = plate.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				plate.name:SetPoint("BOTTOM", plate.bar, "TOP", 0, 3)
				plate.name.searchSkip = true
				-- (A cast under its bar, at the Cast Bar Style page's size and cast
				-- color, filling over and over: the spell's icon at its left.)
				plate.cast = CreateFrame("Frame", nil, plate.bar)
				plate.cast:SetPoint("TOP", plate.bar, "BOTTOM", 0, -3)
				local castEdge = plate.cast:CreateTexture(nil, "BACKGROUND")
				castEdge:SetPoint("TOPLEFT", -1, 1)
				castEdge:SetPoint("BOTTOMRIGHT", 1, -1)
				castEdge:SetColorTexture(0, 0, 0, 1)
				local castBack = plate.cast:CreateTexture(nil, "BORDER")
				castBack:SetAllPoints()
				castBack:SetColorTexture(0.2, 0.2, 0.2, 1)
				plate.castFill = plate.cast:CreateTexture(nil, "ARTWORK")
				plate.castFill:SetPoint("TOPLEFT")
				plate.castFill:SetPoint("BOTTOMLEFT")
				plate.castFill:SetTexture(GAME_FILL)
				local castIcon = plate.cast:CreateTexture(nil, "ARTWORK")
				castIcon:SetPoint("RIGHT", plate.cast, "LEFT", -2, 0)
				castIcon:SetTexture(({ "Interface\\Icons\\Spell_Fire_FlameBolt", "Interface\\Icons\\Spell_Frost_FrostBolt02",
					"Interface\\Icons\\Spell_Shadow_ShadowBolt", "Interface\\Icons\\Spell_Nature_Lightning",
					"Interface\\Icons\\Spell_Holy_FlashHeal", "Interface\\Icons\\Spell_Nature_Slow" })[(n - 1) % 6 + 1])
				castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				plate.castIcon = castIcon
				-- (The row being edited: a soft gold glow behind its plate.)
				plate.glow = plate:CreateTexture(nil, "BACKGROUND")
				plate.glow:SetPoint("TOPLEFT", plate.bar, "TOPLEFT", -10, 22)
				plate.glow:SetPoint("BOTTOMRIGHT", plate.bar, "BOTTOMRIGHT", plate.level and 34 or 10, -8)
				plate.glow:SetColorTexture(1, 0.82, 0, 0.12)
				-- (A row hovered in the grid: its plate lit brighter, see preview:Hover.)
				plate.lit = plate:CreateTexture(nil, "BACKGROUND", nil, 1)
				plate.lit:SetAllPoints(plate.glow)
				plate.lit:SetColorTexture(1, 1, 1, 0.14)
				plate.lit:Hide()
				plate:SetScript("OnClick", function(self)
					if self.kind and preview.OnPlateClick then preview.OnPlateClick(self.kind) end
					preview:Pick(self.kind)
				end)
				plate:SetScript("OnEnter", function(self)
					if not self.kind then return end
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(self.full or "", 1, 0.82, 0)
					GameTooltip:AddLine(L["Click to open its row."], 1, 1, 1, true)
					GameTooltip:Show()
				end)
				plate:SetScript("OnLeave", GameTooltip_Hide)
				plate.goal = { alpha = 1, width = 1, height = 1 }
				plate.now = { alpha = 1, width = 1, height = 1 }
				plate.phase = n * 1.7 -- (each plate's fight at its own point in the loop)
				plate.health = 1
				plates[n] = plate
				return plate
			end
			-- The rows shown: the first few on the grid, then Default.
			local function ShownRows()
				local list, others = {}, nil
				for _, id in ipairs(ns.TargetMarkOrder()) do
					if ns.MarkRowBase(id) == "others" then
						others = others or id
					elseif #list < #SPOTS then
						list[#list + 1] = id
					end
				end
				return list, others or "others"
			end
			-- Picks a row to preview (one taken off: back to Default).
			function preview:Pick(id)
				previewed = id or "others"
				self:Refresh()
				if self.OnPicked then self.OnPicked() end -- (the grid: its row lit)
			end
			-- A row hovered in the grid (nil: none): its plate lit, when it's on the scene.
			function preview:Hover(id)
				for _, plate in pairs(plates) do
					plate.lit:SetShown(id ~= nil and plate.kind == id and plate:IsShown())
				end
			end
			-- Dresses a plate as its row says. (Named as its row, so each is
			-- told apart at a glance.)
			-- (who: the plate's own kind of unit, its bar's color under the row's,
			-- 2026-11-16: Hostile, Neutral, Friendly or Player (your class's color),
			-- the plate named for it.)
			local WHO_PLATES = { { "Enemy", L["Hostile"] }, { "Neutral", L["Neutral"] }, { "Friendly", L["Friendly"] },
				{ "Player", L["Player"] } }
			local function Dress(plate, kind, who)
				plate.kind = kind
				local base, reaction = ns.MarkRowBase(kind)
				local info = preview.RowInfo and preview.RowInfo(kind)
				plate.full = info and info.full or L["Default"]
				plate.name:SetText(who and who[2] or info and info.label or L["Default"])
				plate.glow:Hide() -- (one plate shown now, 2026-11-16: no glow to tell the picked one apart)
				local shown = ns.TargetMarkSetting("Show", kind) and true or false
				plate.arrow = plate.arrow or ns.MakeTargetArrow(plate.bar, plate.bar)
				ns.StyleTargetArrow(plate.arrow, nil, kind)
				plate.arrow:SetShown(shown and ns.TargetMarkSetting("Style", kind) ~= "none")
				plate.arrow:SetAlpha(ns.TargetMarkSetting("Opacity", kind) or 1)
				local tintKind = ns.TargetMarkTintKind(kind)
				local r, g, b = ns.TargetPlateColour(nil, tintKind)
				if shown and ns.TargetMarkAlso("ColorName", tintKind) then
					plate.name:SetTextColor(r, g, b)
				else
					plate.name:SetTextColor(1, 1, 1) -- (the game's names over plates: white)
				end
				local colors = WHO_COLORS[(who and who[1]) or (reaction or ""):match("^%u%l+") or ""] or WHO_COLORS.Enemy
				if who and who[1] == "Player" then
					local class = select(2, UnitClass("player"))
					local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
					colors = classColor and { classColor.r, classColor.g, classColor.b } or { 0.25, 0.78, 0.92 }
				end
				local fr, fg, fb = colors[1], colors[2], colors[3]
				if shown and ns.TargetMarkAlso("ColorBar", tintKind) then fr, fg, fb = r, g, b end
				plate.fill:SetVertexColor(fr, fg, fb)
				plate.back:SetColorTexture(fr * 0.25, fg * 0.25, fb * 0.25, 1)
				-- (The border: your target's own, white unless its Also color takes it.)
				local targeted = base == "target" or base == "aggro"
				for _, line in ipairs(plate.border) do
					line:SetShown(targeted)
					if shown and ns.TargetMarkAlso("ColorBorder", tintKind) then
						line:SetColorTexture(r, g, b, 1)
					else
						line:SetColorTexture(1, 1, 1, 1)
					end
				end
				-- (Its row's Look: the bar's texture and border, the name's font,
				-- size, outline and shadow, the level box. PlateRowLook.lua.)
				local look = ns.PlateRowLookFor and ns.PlateRowLookFor(kind)
				-- (Where the row sets none: the plate theme's bar and border, as the
				-- plates have them, and the Look panel's preview; else the game's.
				-- 2026-11-16: the theme never showed here.)
				local themeTexture, themeEdge, themeSize, themeR, themeG, themeB
				if ns.PlateThemeBar then themeTexture, themeEdge, themeSize, themeR, themeG, themeB = ns.PlateThemeBar() end
				local texture = look and look.texture
				if texture == nil then texture = themeTexture end
				if texture and texture ~= "game" and ns.SetStyleTexture then
					ns.SetStyleTexture(plate.fill, texture)
				else
					plate.fill:SetTexture(GAME_FILL)
				end
				local border = look and look.border
				if not border and themeEdge then border = { themeEdge, themeSize, themeR, themeG, themeB } end
				if border and border[1] == "line" then
					plate.edges = plate.edges or ns.MakeStyleEdges(plate.bar)
					ns.DressStyleEdges(plate.edges, border[2], border[3], border[4], border[5], 1, true)
					plate.edges:Show()
				elseif plate.edges then
					plate.edges:Hide()
				end
				if plate.level then plate.level:SetShown(not (look and look.level == false)) end
				local nameFile, nameSize, nameFlags = _G.GameFontNormal:GetFont()
				if look and look.outline and look.outline >= 0 and ns.OutlinedFlags then
					nameFlags = ns.OutlinedFlags(nameFlags, look.outline)
				end
				if ns.SetPlateNameFont then
					ns.SetPlateNameFont(plate.name, _G.GameFontNormal, look and look.font or nameFile, nameSize,
						look and look.size or 1, nameFlags)
				end
				plate.name:SetShadowOffset(look and look.shadow == "none" and 0 or 1, look and look.shadow == "none" and 0 or -1)
				-- (The cast: the Cast Bar Style page's size, times the bar's, and its cast color.)
				local castLook = ns.PlateCastLook and ns.PlateCastLook()
				plate.castW = castLook and castLook.plateCastWidth or 1
				local castH = 6 * (castLook and castLook.plateCastHeight or 1)
				plate.cast:SetHeight(castH)
				plate.castIcon:SetSize(math.max(8, castH + 2), math.max(8, castH + 2))
				plate.castFill:SetVertexColor(castLook and castLook.plateCastR or 1, castLook and castLook.plateCastG or 0.7,
					castLook and castLook.plateCastB or 0)
				-- (Its opacity and health bar's size, the sizes this client takes
				-- (ns.plateSizes: Forever's the width); moved to by the OnUpdate below.)
				local goal, sizes, db = plate.goal, ns.plateSizes or {}, ns.GetDB()
				goal.alpha = shown and (ns.TargetMarkSetting("Alpha", kind) or 1) or 0.35
				goal.width = (shown and sizes.width and ns.TargetMarkSetting("PlateWidth", kind) or 1)
					* (sizes.width and db.plateStyleWidth or 1)
				goal.height = (shown and sizes.height and ns.TargetMarkSetting("PlateHeight", kind) or 1)
					* (sizes.height and db.plateStyleHeight or 1)
			end
			function preview:Refresh()
				if not (ns.MakeTargetArrow and ns.GetDB()) then return end
				ns.StyleScene(self, 0.55, 0.8) -- (the Style pages' scene: StylePages.lua)
				local list, others = ShownRows()
				local onScene = previewed == others
				for _, id in ipairs(list) do onScene = onScene or id == previewed end
				if not onScene then
					-- (A row further down the grid, picked: in the last spot.)
					local found = false
					for _, id in ipairs(ns.TargetMarkOrder()) do found = found or id == previewed end
					if found then list[math.min(#list + 1, #SPOTS)] = previewed else previewed = others end
				end
				local width, height = self:GetWidth(), self:GetHeight()
				local used = {}
				local function Place(n, spot, kind, who)
					local plate = plates[n] or MakeSample(n)
					plate:ClearAllPoints()
					plate:SetScale(spot[3])
					plate:SetPoint("CENTER", self, "TOPLEFT", width * spot[1] / spot[3], -height * spot[2] / spot[3])
					plate:Show()
					Dress(plate, kind, who)
					used[n] = true
				end
				-- (The row picked (Default to start) on four plates, one in each
				-- quarter of the scene, 2026-11-16: a hostile, a neutral, a friendly
				-- unit and a player.)
				for n, who in ipairs(WHO_PLATES) do
					local column, row = (n - 1) % 2, math.floor((n - 1) / 2)
					Place(n, { 0.25 + column * 0.5, 0.3 + row * 0.44, 0.95 }, previewed, who)
				end
				for n, plate in pairs(plates) do
					if not used[n] then plate:Hide() end
				end
			end
			-- Moving like plates in a fight: health dropping in hits and filling
			-- again, each plate at its own point, and its opacity and size going to
			-- its row's in the Change time (plateStyleFadeTime), as PlateParts'
			-- easer moves them. The marks bob on their own (StyleTargetArrow).
			local HEALTH_TIME = 9
			local started = GetTime()
			-- (The health for a time in the loop: full, five hits, a pause, filled again.)
			local function HealthAt(t)
				if t < 1.5 then return 1 end
				if t < 4.5 then return 1 - 0.13 * (math.floor((t - 1.5) / 0.6) + 1) end
				if t < 6 then return 0.35 end
				return math.min(1, 0.35 + (t - 6) / 2 * 0.65)
			end
			-- (Shown again: at their rows' look at once, as plates just come.)
			-- (Hooked: StylePopout's own OnShow fits it to the page's width.)
			preview:HookScript("OnShow", function(self)
				self.snap = true
				self:Refresh()
			end)
			preview:HookScript("OnSizeChanged", function(self)
				if self:IsShown() then self:Refresh() end
			end)
			preview.snap = true
			ns.SetOnUpdate(preview, function(self, elapsed)
				local time = ns.GetDB().plateStyleFadeTime or 1.5
				local t = GetTime() - started
				for _, plate in pairs(plates) do
					if plate:IsShown() then
						for what, goal in pairs(plate.goal) do
							plate.now[what] = self.snap and goal or ns.Approach(plate.now[what], goal, elapsed, time)
						end
						plate:SetAlpha(plate.now.alpha)
						plate.bar:SetSize(BAR_W * plate.now.width, BAR_H * plate.now.height)
						plate.health = ns.Approach(plate.health, HealthAt((t + plate.phase) % HEALTH_TIME), elapsed, 0.25)
						plate.fill:SetWidth(math.max(0.01, plate.bar:GetWidth() * plate.health))
						-- (The cast filling over 2.5 of every 3 seconds, each plate at its own point.)
						local castWidth = plate.bar:GetWidth() * (plate.castW or 1)
						plate.cast:SetWidth(castWidth)
						plate.castFill:SetWidth(math.max(0.01, castWidth * math.min(1, (t + plate.phase) % 3 / 2.5)))
					end
				end
				self.snap = nil
			end)
			controls[#controls + 1] = preview

			-- A choice from a list: a dropdown, or on a client without the modern
			-- one a button that steps through them.
			local function Pick(parent, key, choices, width)
				RecordKey(content, key) -- (for Reset page: the row's own isn't the page)
				local pick = Dropdown(parent, key, choices, width, Changed)
				if pick then
					return pick
				end
				pick = ns.PanelButton(parent)
				pick:SetSize(width, 22)
				pick:SetScript("OnClick", function()
					local db = ns.GetDB()
					local now = 0
					for i, choice in ipairs(choices) do
						if db[key] == choice.value then now = i end
					end
					db[key] = choices[now % #choices + 1].value
					Refresh()
					Changed()
				end)
				pick.Refresh = function(self)
					for _, choice in ipairs(choices) do
						if ns.GetDB()[key] == choice.value then self:SetText(choice.text) end
					end
				end
				controls[#controls + 1] = pick
				RecordKey(content, key)
				return pick
			end

			-- Plate theme (under the preview): the bars' look under the rows, in one pick (texture and
			-- border; names are Name Style's). Follow General first: as plates
			-- have always been. PlateThemes.lua.
			stack:Header(content, L["Plate theme"])
			RecordKey(content, "plateTheme")
			local plateStrip = stack:Add(ns.MakePartThemeStrip(ns.lowHealthKit, content, "plate", function()
				if ns.RefreshPlateHealthStyle then ns.RefreshPlateHealthStyle() end
				Changed()
			end), "label")
			local plateThemeNow = stack:Note(content, "", 460)
			plateThemeNow.searchSkip = true
			plateThemeNow.Refresh = function(self)
				local theme = ns.PlateThemeNow()
				self:SetText(theme and (L["%s, picked here: it stays when the main theme changes."]):format(L[theme.name])
					or L["Following General: the bar's texture and border as the Style hub's General page has them."])
				self:SetTextColor(0.6, 0.6, 0.6)
			end
			controls[#controls + 1] = plateThemeNow
			controls[#controls + 1] = plateStrip
			-- Customize (2026-11-16): the Default row's Look panel (Smart Style's
			-- last row): the plates' own look before any row of Smart Style.
			local customize = ns.PanelButton(content)
			customize:SetSize(140, 22)
			customize:SetText(L["Customize"])
			customize:SetPoint("TOPLEFT", plateThemeNow, "BOTTOMLEFT", 0, -12)
			Tooltip(customize, L["Change the plates' basic look."])
			customize:SetScript("OnClick", function()
				local grid = content.markGrid
				local default
				for _, id in ipairs(ns.TargetMarkOrder()) do
					if not default and ns.MarkRowBase(id) == "others" then default = id end
				end
				local button = grid and grid.lookButtons and grid.lookButtons[default or "others"]
				if preview and preview.Pick then preview:Pick(default) end
				if button and button:GetScript("OnClick") then button:GetScript("OnClick")(button, "LeftButton") end
			end)
			customize.Refresh = function() end
			customize.pageSwitch = false
			controls[#controls + 1] = customize

			-- The grid: a line for each row in the order a plate tries them, its
			-- mark's preview, name and what's set apart from the usual (chips);
			-- its settings in a drawer under it, opened by clicking the line.
			-- (What's made from here on: the Marks part; before it, Plate Style's.)
			local styleMade = {}
			for _, object in ipairs({ content:GetChildren() }) do styleMade[object] = true end
			for _, object in ipairs({ content:GetRegions() }) do styleMade[object] = true end
			local marksHeader = stack:Header(content, L["Smart Style"]) -- (Marks until 2026-11-16)
			stack:Help(content, L["Each plate takes its look from the first row that fits it, top to bottom."])
			-- (The columns' headings: what a row sets on the mark, on the plate, and when.)
			local headings = CreateFrame("Frame", nil, content)
			headings:SetSize(ROW_W, 16)
			stack:Add(headings, "label")
			for _, column in ipairs({ { "Mark", L["Mark"], PREVIEW_X, L["The row's mark over the plate."] },
				{ "Plate", L["Look"], PLATE_X, L["What the row changes on the plate itself."] },
				{ "When", L["When"], WHEN_X, L["When the row applies."] } }) do
				local heading = CreateFrame("Frame", nil, headings)
				heading:SetSize(60, 16)
				heading:SetPoint("LEFT", headings, "LEFT", column[3], 0)
				local text = Label(heading, "GameFontNormalSmall", column[2])
				text:SetPoint("LEFT")
				text:SetTextColor(unpack(COLUMN_COLORS[column[1]]))
				text.searchSkip = true
				Tooltip(heading, column[4])
			end
			local grid = CreateFrame("Frame", nil, content)
			grid:SetSize(ROW_W, ROW_H * #MARK_KINDS)
			stack:Add(grid, "label")
			-- The kinds of row (Core's MARK_ROW_KINDS), in the Kind dropdown's
			-- order: id, name, tip.
			local KINDS = {
				{ "target", L["Target"], L["Your target."] },
				{ "focus", L["Focus"], L["Your focus."] },
				{ "mouseover", L["Mouseover"], MARK_KINDS[4][3] },
				{ "aggro", L["Aggro on you"], MARK_KINDS[1][3] },
				{ "aggroother", L["Aggro on not you"], L["Any enemy attacking someone friendly other than you."] },
				{ "aggrononank", L["Aggro on non-tank"], L["Any enemy attacking a player who isn't a tank."] },
				{ "aggrohealer", L["Aggro on a healer"], L["Any enemy attacking a healer."] },
				{ "tapped", L["Not your kill"], L["An NPC someone outside your group hit first, so you get no credit for it."] },
				{ "npc", L["Normal NPC"], L["Living NPCs that aren't elite, rare or a boss."] },
				{ "elite", L["Elite NPC"], L["Living elite, rare elite and boss NPCs."] },
				{ "npcs", L["NPC"], L["Any living NPC, normal or elite."] },
				{ "players", L["Players"], L["Players, friendly or enemy."] },
				{ "minions", L["Minions"], L["Anything a player controls: pets, totems and guardians."] },
				{ "all", L["Any unit"], L["Every plate: NPCs, players and minions."] },
				{ "others", L["Default"], MARK_KINDS[5][3] },
			}
			local KIND_INFO = {}
			for _, kind in ipairs(KINDS) do KIND_INFO[kind[1]] = kind end
			local REACTION_NAMES = { Enemy = L["Enemy"], Neutral = L["Neutral"], Friendly = L["Friendly"] }
			local REACTION_TIPS = { Enemy = L["This row: just the enemies among them."],
				Neutral = L["This row: just the neutral ones among them."],
				Friendly = L["This row: just the friendly ones among them."] }
			-- (A Who of one or more, "EnemyNeutral": Enemy/Neutral.)
			local function WhoName(reaction)
				local names = {}
				for who in reaction:gmatch("%u%l+") do names[#names + 1] = REACTION_NAMES[who] or who end
				return table.concat(names, "/")
			end
			-- (The Units rows' units, by Core's MARK_UNIT_FLAGS letters: their
			-- names, NPC for both ranks, Any unit for all; their tips.)
			local UNIT_LETTERS = { n = "npc", e = "elite", p = "players", m = "minions" }
			local function UnitsName(flags)
				if flags == "nepm" then return KIND_INFO.all[2] end
				local names = {}
				for letter in flags:gsub("ne", "N"):gmatch(".") do
					names[#names + 1] = letter == "N" and KIND_INFO.npcs[2] or KIND_INFO[UNIT_LETTERS[letter]][2]
				end
				return table.concat(names, ", ")
			end
			-- (An Aggro mix's: Aggro: and who (You, Not you) and their roles
			-- (Tank/Healer/DPS), each left out with all of it ticked.)
			local AGGRO_NAMES = { t = L["Tank"], h = L["Healer"], d = L["DPS"] }
			local function AggroName(flags)
				local parts = {}
				if not (flags:find("y", 1, true) and flags:find("o", 1, true)) then
					parts[1] = flags:find("y", 1, true) and L["You"] or L["Not you"]
				end
				local roles = {}
				for letter in flags:gsub("[yo]", ""):gmatch(".") do roles[#roles + 1] = AGGRO_NAMES[letter] end
				if #roles < 3 then parts[#parts + 1] = table.concat(roles, "/") end
				return L["Aggro"] .. ": " .. (#parts > 0 and table.concat(parts, ", ") or L["Anyone"])
			end
			local function UnitsTip(flags)
				local tips = {}
				for letter in flags:gmatch(".") do tips[#tips + 1] = KIND_INFO[UNIT_LETTERS[letter]][3] end
				return table.concat(tips, " ")
			end
			-- (A Distance's name in the Distance dropdown, short beside a row's
			-- name, and its tip.)
			local DISTANCE_NAMES = { In11 = L["Within 11 yards"], In28 = L["Within 28 yards"],
				In40 = L["Within 40 yards"], Past28 = L["Past 28 yards"], Past40 = L["Past 40 yards"],
				OutOfRange = L["Out of range"], NearAggro = L["Near aggro range"] }
			local DISTANCE_SHORT = { In11 = L["in 11 yd"], In28 = L["in 28 yd"], In40 = L["in 40 yd"],
				Past28 = L["past 28 yd"], Past40 = L["past 40 yd"], OutOfRange = L["out of range"],
				NearAggro = L["near aggro"] }
			-- (Near aggro range, its own tip: Frames' ns.UnitNearAggro.)
			local NEAR_AGGRO_TIP = L["Just hostile NPCs about close enough to attack you."]
			local DISTANCE_TIP = L["Just units about that far from you."]
			-- A row's names and tip from its id: its kind's name (label), what's
			-- under it (sub: its Who, Distance and number), all in one line (full);
			-- a name of your own (markNames) for label and full instead, its own
			-- in auto and its tip.
			local AutoRowInfo
			local function RowInfo(id)
				local info = AutoRowInfo(id)
				local db = ns.GetDB() -- (nil while the page is first made, at load)
				local own = db and db.markNames
				own = type(own) == "table" and own[id]
				info.auto = info.full
				if type(own) == "string" and own:find("%S") then
					info.label, info.sub, info.full = own, nil, own
					info.tip = "|cffffd100" .. info.auto .. "|r\n" .. info.tip
				end
				return info
			end
			function AutoRowInfo(id)
				local base, reaction, copy, distance = ns.MarkRowBase(id)
				local kind = KIND_INFO[base] or KINDS[1]
				if not KIND_INFO[base] and ns.MARK_UNIT_FLAGS[base] then
					kind = { base, UnitsName(ns.MARK_UNIT_FLAGS[base]), UnitsTip(ns.MARK_UNIT_FLAGS[base]) }
				elseif not KIND_INFO[base] and ns.MARK_AGGRO_FLAGS[base] then
					kind = { base, AggroName(ns.MARK_AGGRO_FLAGS[base]), L["Any enemy attacking whoever its ticks say."] }
				end
				local who = reaction and WhoName(reaction)
				local far = distance and DISTANCE_SHORT[distance]
				local number = copy and "(" .. copy .. ")"
				local scope = who and far and who .. ", " .. far or who or far
				local sub = scope and number and scope .. " " .. number or scope or number
				local fullScope = (who or "") .. (who and distance and ", " or "")
					.. (distance and DISTANCE_NAMES[distance] or "")
				return { id = id, base = base, reaction = reaction, distance = distance, label = kind[2], sub = sub,
					full = kind[2] .. (fullScope ~= "" and " - " .. fullScope or "") .. (number and " " .. number or ""),
					tip = kind[3] .. (reaction and " " .. (REACTION_TIPS[reaction]
						or (L["This row: just these among them: %s."]):format(WhoName(reaction))) or "")
						.. (distance and " " .. (distance == "NearAggro" and NEAR_AGGRO_TIP or DISTANCE_TIP) or "") }
			end
			preview.RowInfo = RowInfo

			-- When each row fits, in its drawer (as the Standard Frames page's rows:
			-- Always, the dropdowns, roles, a rule: Core's MARK_WHEN_WORDS).
			local WHEN_LAYOUT = { edit = true }
			local WHEN_GROUP = { combat = 1, calm = 1, nocombat = 1, camera = 1, enemy = 2, friendly = 2, near = 2,
				near28 = 2 }
			local WHEN_NAMES = { combat = L["In combat"], calm = L["Calm Timer"], nocombat = L["Out of combat"],
				camera = L["In a camera mode"], enemy = L["Enemy targeted"], friendly = L["Friend targeted"],
				near = L["Near (11 yards)"], near28 = L["Near (28 yards)"], world = L["Open world"], city = L["Cities"],
				inn = L["Inns"], bg = L["BGs & arenas"], instance = L["Instances"], dungeon = L["Dungeons"],
				raid = L["Raids"], group = L["Grouped"] }

			-- What's set apart from the usual on a row, for its chips: { text,
			-- what (fade: an opacity; when: its When; nil: the rest), column
			-- (mark, plate or when: the mark's only in the row's tip) }. Nothing
			-- at 100%, normal size, no Also color and When on Always.
			local function RowChips(kind)
				local db, list = ns.GetDB(), {}
				local alpha = ns.TargetMarkSetting("Alpha", kind) or 1
				if alpha < 1 then
					list[#list + 1] = { ("%d%%"):format(alpha * 100 + 0.5), "fade", "plate" }
				end
				local key = kind .. "When"
				local rule = db.frameRules and db.frameRules[key]
				if type(rule) == "string" and rule:find("%S") then
					list[#list + 1] = { rule, "when", "when" }
				elseif not db[key] then
					local ticked = {}
					for _, word in ipairs(ns.MARK_WHEN_WORDS) do
						if db[key .. word[2]] then ticked[#ticked + 1] = WHEN_NAMES[word[1]] end
					end
					list[#list + 1] = { #ticked == 0 and L["Never"] or #ticked == 1 and ticked[1]
						or ticked[1] .. " +" .. (#ticked - 1), "when", "when" }
				end
				-- (The colors' chip with a swatch of the color they take: swatch.)
				local tintKind = ns.TargetMarkTintKind and ns.TargetMarkTintKind(kind) or kind
				local swatch = ns.TargetPlateColour and { ns.TargetPlateColour(nil, tintKind) } or nil
				if ns.MarkRowBase(kind) == "aggro" and ns.TargetMarkOwn("AlsoSame", kind) then
					list[#list + 1] = { L["Your target's"], nil, "plate", swatch = swatch }
				else
					local parts = {}
					for _, part in ipairs(ALSO_PARTS) do
						if ns.TargetMarkAlso("Color" .. part[1], kind) then parts[#parts + 1] = ALSO_SHORT[part[1]] end
					end
					if #parts > 0 then list[#list + 1] = { table.concat(parts, ", "), nil, "plate", swatch = swatch } end
				end
				if ns.PlateRowHasLook and ns.PlateRowHasLook(kind) then
					list[#list + 1] = { L["Own look"], nil, "plate" }
				end
				local size = ns.TargetMarkSetting("Size", kind) or 1
				if math.abs(size - 1) > 0.001 and ns.TargetMarkSetting("Style", kind) ~= "none" then
					list[#list + 1] = { (L["Size %d%%"]):format(size * 100 + 0.5), nil, "mark" }
				end
				local markAlpha = ns.TargetMarkSetting("Opacity", kind) or 1
				if markAlpha < 1 and ns.TargetMarkSetting("Style", kind) ~= "none" then
					list[#list + 1] = { (L["Mark %d%%"]):format(markAlpha * 100 + 0.5), "fade", "mark" }
				end
				local sizes = ns.plateSizes or {}
				local width = sizes.width and ns.TargetMarkSetting("PlateWidth", kind) or 1
				local height = sizes.height and ns.TargetMarkSetting("PlateHeight", kind) or 1
				if not sizes.height and math.abs(width - 1) > 0.001 then
					list[#list + 1] = { (L["Plate width %d%%"]):format(width * 100 + 0.5), nil, "plate" }
				elseif math.abs(width - height) > 0.001 then
					list[#list + 1] = { (L["Plate size %d%% x %d%%"]):format(width * 100 + 0.5, height * 100 + 0.5), nil,
						"plate" }
				elseif math.abs(width - 1) > 0.001 then
					list[#list + 1] = { (L["Plate size %d%%"]):format(width * 100 + 0.5), nil, "plate" }
				end
				return list
			end
			-- (Chip colors: an opacity amber, a When blue, the rest grey.)
			local CHIP_COLORS = { fade = { 0.35, 0.25, 0.05, 1, 0.8, 0.35 }, when = { 0.08, 0.2, 0.35, 0.55, 0.8, 1 } }
			local CHIP_PLAIN = { 0.18, 0.18, 0.18, 0.8, 0.8, 0.8 }

			-- The rows, each made the first time it's on the grid; a drawer each,
			-- open while opened says so (kept till /reload).
			local rows, moves, drawers, opened = {}, {}, {}, {}
			local MakeRow -- (below)
			local function RowList()
				local list = {}
				for _, id in ipairs(ns.TargetMarkOrder()) do list[#list + 1] = id end
				list[#list + 1] = "others"
				return list
			end
			local function Group(id) return ns.MarkRowBase(id) == "others" end
			-- (Whether row other is for all of row id's units and more: the same
			-- kind, or Units or Aggro for all of its, its Whos, any distance or the
			-- same.)
			local function Covers(other, id)
				local base, reaction, _, distance = ns.MarkRowBase(id)
				local otherBase, otherReaction, _, otherDistance = ns.MarkRowBase(other)
				if base == "others" or otherBase == "others" then return false end
				local flags = ns.MARK_UNIT_FLAGS[base] or ns.MARK_AGGRO_FLAGS[base]
				local otherFlags = ns.MARK_UNIT_FLAGS[otherBase] or ns.MARK_AGGRO_FLAGS[otherBase]
				if flags and otherFlags then
					for letter in flags:gmatch(".") do
						if not otherFlags:find(letter, 1, true) then return false end
					end
				elseif otherBase ~= base then
					return false
				end
				if otherReaction then
					if not reaction then return false end
					for who in reaction:gmatch("%u%l+") do
						if not otherReaction:find(who, 1, true) then return false end
					end
				end
				if otherDistance and otherDistance ~= distance then return false end
				return otherBase ~= base or otherReaction ~= reaction or otherDistance ~= distance
			end
			function grid:Refresh()
				local list = RowList()
				local at = {}
				for i, id in ipairs(list) do
					at[id] = i
					if not rows[id] then MakeRow(id) end
				end
				for id, row in pairs(rows) do
					if not at[id] then
						row:Hide()
						drawers[id]:Hide()
						drawers[id].searchAlways = false
					end
				end
				local y = 0
				for i, id in ipairs(list) do
					local row, drawer = rows[id], drawers[id]
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
					row:Show()
					-- (The row in the preview: a gold band behind it and a bar at its left.)
					if not row.picked then
						row.picked = row:CreateTexture(nil, "BACKGROUND", nil, 1)
						row.picked:SetAllPoints()
						row.picked:SetColorTexture(1, 0.82, 0, 0.14)
						row.pickedBar = row:CreateTexture(nil, "ARTWORK")
						row.pickedBar:SetPoint("TOPLEFT")
						row.pickedBar:SetPoint("BOTTOMLEFT")
						row.pickedBar:SetWidth(2)
						row.pickedBar:SetColorTexture(1, 0.82, 0, 0.9)
					end
					row.picked:SetShown(id == previewed)
					row.pickedBar:SetShown(id == previewed)
					y = y + ROW_H
					if moves[id] then
						moves[id].up:SetShown(i > 1 and Group(list[i - 1]) == Group(id))
						moves[id].down:SetShown(i < #list - 1 and Group(list[i + 1]) == Group(id))
					end
					-- (A row for some units under a row of its kind for more of
					-- them: that one sets first. Its Who and Distance in orange.)
					local below = false
					for j = 1, i - 1 do
						below = below or Covers(list[j], id) and list[j]
					end
					row.below = below
					row.number:SetText(id ~= "others" and i or "")
					row:SetName()
					-- (Its drawer: a closed one's settings still count for page
					-- search, which opens it.)
					drawer.searchAlways = true
					row.toggle:SetNormalTexture(opened[id] and "Interface\\Buttons\\UI-MinusButton-Up"
						or "Interface\\Buttons\\UI-PlusButton-Up")
					if opened[id] then
						drawer:ClearAllPoints()
						drawer:SetPoint("TOPLEFT", grid, "TOPLEFT", DRAWER_X, -y)
						drawer:Show()
						y = y + drawer:GetHeight() + 4
					else
						drawer:Hide()
					end
				end
				grid:SetHeight(math.max(y, 1))
			end
			controls[#controls + 1] = grid
			content.markGrid = grid -- (the Default Plate Style tab's Customize: its Default row's Look)
			RecordKey(content, "markOrder")
			-- (Right-click: folds or opens it, the preview left on its pick.)
			local function Toggle(id, button)
				opened[id] = not opened[id]
				grid:Refresh()
				if button ~= "RightButton" then preview:Pick(id) end
			end
			-- (A row picked for the preview: lit here.)
			preview.OnPicked = function() grid:Refresh() end
			-- (A plate clicked in the preview: its row opened.)
			preview.OnPlateClick = function(id)
				opened[id] = true
				grid:Refresh()
			end
			local function SetOrder(order)
				ns.GetDB().markOrder = table.concat(order, ",")
				Refresh()
				Changed()
			end
			local function Order()
				local order = {}
				for i, each in ipairs(ns.TargetMarkOrder()) do order[i] = each end
				return order
			end
			local function Move(kind, by)
				local order = Order()
				for i, each in ipairs(order) do
					if each == kind and order[i + by] then
						order[i], order[i + by] = order[i + by], each
						break
					end
				end
				SetOrder(order)
			end
			local function MoveButton(row, kind, by)
				local button = CreateFrame("Button", nil, row)
				button:SetSize(14, 14)
				button:SetPoint("LEFT", row, "LEFT", 0, by < 0 and 7 or -7)
				local art = by < 0 and "Interface\\Buttons\\Arrow-Up-" or "Interface\\Buttons\\Arrow-Down-"
				button:SetNormalTexture(art .. "Up")
				button:SetPushedTexture(art .. "Down")
				button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
				Tooltip(button, by < 0 and L["Move this row up: a plate tries it sooner."]
					or L["Move this row down: a plate tries it later."])
				button:SetScript("OnClick", function() Move(kind, by) end)
				return button
			end
			-- The next free row of a kind, Who and Distance: its own id while it
			-- isn't on the grid (Default's always is), else the first number
			-- free; nil with all of them taken.
			local function FreeRow(base, reaction, distance)
				local first, on = base .. (reaction or "") .. (distance or ""), {}
				for _, id in ipairs(ns.TargetMarkOrder()) do on[id] = true end
				if first ~= "others" and not on[first] then return first end
				for copy = 2, ns.MARK_COPIES do
					if not on[first .. copy] then return first .. copy end
				end
			end
			-- An added row, its look a copy of the first of its kind, Who and Distance (that
			-- one itself: its own look if it had one, else its kind's or its own
			-- to start with, as Normal NPC - Enemy's 40%), written out so its cells
			-- show it; its When afresh: Always, or its kind's rule (Core's
			-- MARK_ROW_RULES), every role. Just above the first row of its kind,
			-- or after the rest.
			local MARK_COPY = { "Show", "Style", "Color", "R", "G", "B", "Size", "Bob", "Alpha", "AlsoSame", "Opacity",
				"PlateWidth", "PlateHeight", "PlateColor", "PlateR", "PlateG", "PlateB" }
			-- (Fresh: its kind's defaults instead, at the end of the grid, opened.)
			local function AddRow(id, fresh)
				local db = ns.GetDB()
				local base, reaction, _, distance = ns.MarkRowBase(id)
				local first = base .. (reaction or "") .. (distance or "")
				for _, key in ipairs(MARK_COPY) do
					if fresh then
						db[MarkKey(id, key)] = ns.DEFAULTS[MarkKey(base, key)]
					else
						db[MarkKey(id, key)] = ns.TargetMarkOwn(key, first)
					end
				end
				for _, part in ipairs({ "Name", "Bar", "Border" }) do
					if fresh then
						db[id .. "Color" .. part] = ns.DEFAULTS[base .. "Color" .. part] and true or false
					else
						db[id .. "Color" .. part] = ns.TargetMarkOwn("Color" .. part, first) and true or false
					end
				end
				-- (Its plate color - to start with: it leaves the plate's colors to
				-- the rows below till you pick one.)
				db[MarkKey(id, "PlateColor")] = "-"
				db[MarkKey(id, "AlsoSame")] = false
				local rule = ns.MARK_ROW_RULES[first]
				db[id .. "When"] = not rule
				for _, word in ipairs(ns.MARK_WHEN_WORDS) do
					db[id .. "When" .. word[2]] = false
				end
				db.frameRules = db.frameRules or {}
				db.frameRules[id .. "When"] = rule
				local order = Order()
				local at = #order + 1
				for i, each in ipairs(order) do
					if not fresh and ns.MarkRowBase(each) == base then at = i break end
				end
				table.insert(order, at, id)
				if fresh then opened[id] = true end
				SetOrder(order)
				preview:Pick(id)
			end
			local function RemoveRow(id)
				local order = {}
				for _, each in ipairs(ns.TargetMarkOrder()) do
					if each ~= id then order[#order + 1] = each end
				end
				SetOrder(order)
			end

			-- Picking a row: a Kind; for Aggro and Units a Type (which of them:
			-- Units' ticks, any mix of Normal NPC, Elite NPC, Players and Minions);
			-- a Who (ticks of that kind's own: none for the aggro rows, no Neutral
			-- without NPCs; all ticked is Any); a Distance (Core's MARK_DISTANCES).
			-- In each drawer (Default's own aside) for changing its row. A pick:
			-- { kind, type, who, distance }, Kind and Type naming a row kind
			-- (Core's MARK_ROW_KINDS), who "Any" or one or more ("EnemyNeutral").
			local ADD_KINDS = {
				{ "target", L["Target"] }, { "focus", L["Focus"] }, { "mouseover", L["Mouseover"] },
				{ "aggro", L["Aggro"], { { "aggro", L["On you"] }, { "aggroother", L["Not on you"] },
					{ "aggrononank", L["On a non-tank"] }, { "aggrohealer", L["On a healer"] } } },
				{ "tapped", L["Not your kill"] },
				-- (Aggro's and Units' Type is ticks; these their steps on a client
				-- without menus, and their names for those mixes.)
				{ "units", L["Units"], { { "all", L["Any unit"] }, { "npcs", L["NPC"] }, { "npc", L["Normal NPC"] },
					{ "elite", L["Elite NPC"] }, { "players", L["Players"] }, { "minions", L["Minions"] } } },
				{ "others", L["Default"] },
			}
			-- (Their ticks, by Core's letters: the Aggro ones in two groups, who and
			-- role, at least one of each.)
			local TICKS = {
				units = { flags = ns.MARK_UNIT_FLAGS, Kind = ns.MarkUnitKind, all = "nepm",
					{ "n", L["Normal NPC"] }, { "e", L["Elite NPC"] }, { "p", L["Players"] }, { "m", L["Minions"] } },
				aggro = { flags = ns.MARK_AGGRO_FLAGS, Kind = ns.MarkAggroKind, all = "yothd",
					{ "y", L["You"] }, { "o", L["Not you"] }, { "t", L["Tank"], divider = true }, { "h", L["Healer"] },
					{ "d", L["DPS"] } },
			}
			local function KindInfo(pick)
				for _, kind in ipairs(ADD_KINDS) do
					if kind[1] == pick.kind then return kind end
				end
				return ADD_KINDS[1]
			end
			-- (The row kind picked: Kind's own, or its Type's.)
			local function PickedKind(pick)
				local kind = KindInfo(pick)
				return kind[3] and (pick.type or kind[3][1][1]) or kind[1]
			end
			local function KindChoices()
				local list = {}
				for _, kind in ipairs(ADD_KINDS) do list[#list + 1] = { value = kind[1], text = kind[2] } end
				return list
			end
			local function TypeChoices(pick)
				local list = {}
				for _, kind in ipairs(KindInfo(pick)[3] or {}) do list[#list + 1] = { value = kind[1], text = kind[2] } end
				return list
			end
			local function WhoChoices(pick)
				local list = { { value = "Any", text = L["Any"] } }
				for _, who in ipairs(ns.MARK_ROW_KINDS[PickedKind(pick)] or {}) do
					list[#list + 1] = { value = who, text = REACTION_NAMES[who] }
				end
				return list
			end
			local function DistanceChoices()
				local list = { { value = "Any", text = L["Any distance"] } }
				for _, band in ipairs(ns.MARK_DISTANCES) do
					list[#list + 1] = { value = band, text = DISTANCE_NAMES[band] }
				end
				return list
			end
			-- (A Who of those ticked the row kind picked has: none or all of them,
			-- Any. Whether one's ticked, and ticking or unticking one; the last
			-- one ticked stays.)
			local function WhoOf(pick, ticked)
				local whos, on = ns.MARK_ROW_KINDS[PickedKind(pick)] or {}, ""
				for _, who in ipairs(whos) do
					if ticked[who] then on = on .. who end
				end
				local all = ""
				for _, who in ipairs(whos) do all = all .. who end
				return (on == "" or on == all) and "Any" or on
			end
			local function WhoOn(pick, who)
				return pick.who == "Any" or pick.who:find(who, 1, true) ~= nil
			end
			local function KeepWho(pick)
				local ticked = {}
				for _, who in ipairs(ns.MARK_REACTIONS) do ticked[who] = WhoOn(pick, who) end
				pick.who = WhoOf(pick, ticked)
			end
			local function ToggleWho(pick, who)
				local ticked, count = {}, 0
				for _, each in ipairs(ns.MARK_ROW_KINDS[PickedKind(pick)] or {}) do
					ticked[each] = WhoOn(pick, each)
					if ticked[each] then count = count + 1 end
				end
				if ticked[who] and count == 1 then return false end
				ticked[who] = not ticked[who]
				pick.who = WhoOf(pick, ticked)
				return true
			end
			-- (Aggro's and Units' ticks: whether one's ticked, and ticking or
			-- unticking one; not the last one ticked, of a group for Aggro.)
			local function TypeOn(pick, letter)
				local ticks = TICKS[pick.kind]
				return ticks ~= nil and (ticks.flags[PickedKind(pick)] or ""):find(letter, 1, true) ~= nil
			end
			local function ToggleType(pick, letter)
				local ticks = TICKS[pick.kind]
				local flags = ticks and ticks.flags[PickedKind(pick)] or ""
				local new = ticks and ticks.Kind(TypeOn(pick, letter) and flags:gsub(letter, "") or flags .. letter)
				if not new then return false end
				pick.type = new
				KeepWho(pick)
				return true
			end
			-- (A row's own pick, from its id.)
			local function PickOf(id)
				local base, reaction, _, distance = ns.MarkRowBase(id)
				local pick = { kind = base, who = reaction or "Any", distance = distance or "Any" }
				for _, kind in ipairs(ADD_KINDS) do
					for _, sub in ipairs(kind[3] or {}) do
						if sub[1] == base then pick.kind, pick.type = kind[1], base end
					end
				end
				for family, ticks in pairs(TICKS) do
					if ticks.flags[base] then pick.kind, pick.type = family, base end
				end
				return pick
			end
			-- (The row a pick names, without its number.)
			local function PickedFirst(pick)
				return PickedKind(pick) .. (pick.who ~= "Any" and pick.who or "") .. (pick.distance ~= "Any" and pick.distance or "")
			end
			-- (With ticks, { Items(), On(value), Toggle(value): false if it can't,
			-- Text() } as Choices, Get and Set: ticks in the menu, kept open for
			-- ticking more; Choices, Get and Set still step a client without menus.)
			local function Choice(parent, width, Choices, Get, Set, ticks)
				local ok, dropdown = ns.MenuDropdown(parent)
				if ok and dropdown and dropdown.SetupMenu then
					dropdown:SetWidth(width)
					dropdown:SetupMenu(function(_, root)
						if ticks then
							for _, item in ipairs(ticks.Items()) do
								if item.divider then root:CreateDivider() end
								root:CreateCheckbox(item.text, function() return ticks.On(item.value) end, function()
									if ticks.Toggle(item.value) then Refresh() end
									return MenuResponse and MenuResponse.Refresh
								end)
							end
							return
						end
						for _, choice in ipairs(Choices()) do
							root:CreateRadio(choice.text, function() return Get() == choice.value end, function()
								Set(choice.value)
								Refresh()
							end)
						end
					end)
					if ticks and dropdown.SetSelectionText then
						dropdown:SetSelectionText(function() return ticks.Text() end)
					end
					dropdown.Refresh = function(self) self:GenerateMenu() end
				else
					dropdown = ns.PanelButton(parent)
					dropdown:SetSize(width, 22)
					dropdown:SetScript("OnClick", function()
						local list, now = Choices(), 0
						for i, choice in ipairs(list) do
							if Get() == choice.value then now = i end
						end
						Set(list[now % #list + 1].value)
						Refresh()
					end)
					dropdown.Refresh = function(self)
						for _, choice in ipairs(Choices()) do
							if Get() == choice.value then self:SetText(choice.text) end
						end
					end
				end
				dropdown.searchSkip = true
				controls[#controls + 1] = dropdown
				return dropdown
			end
			-- Kind, Type, Who and Distance dropdowns for a pick, in a line from
			-- first's right (Type and Who only with a choice to make; the rest
			-- close up to the left); changed: after each pick. Returns the Kind
			-- dropdown and a fn placing them (and after, if given, after the last).
			local function PickLine(parent, pick, widths, changed)
				local kindPick = Choice(parent, widths[1], KindChoices, function() return pick.kind end, function(value)
					pick.kind, pick.type = value, nil
					KeepWho(pick)
					changed()
				end)
				Tooltip(kindPick, L["What kind of plate this row is for."])
				-- (Aggro's and Units': ticks.)
				local typePick = Choice(parent, widths[2], function() return TypeChoices(pick) end,
					function() return PickedKind(pick) end, function(value)
						pick.type = value
						KeepWho(pick)
						changed()
					end, {
						Items = function()
							local list = {}
							for _, tick in ipairs(TICKS[pick.kind] or {}) do
								list[#list + 1] = { value = tick[1], text = tick[2], divider = tick.divider }
							end
							return list
						end,
						On = function(letter) return TypeOn(pick, letter) end,
						Toggle = function(letter)
							if not ToggleType(pick, letter) then return false end
							changed()
							return true
						end,
						Text = function()
							local kind = PickedKind(pick)
							for _, choice in ipairs(TypeChoices(pick)) do
								if choice.value == kind then return choice.text end
							end
							return AutoRowInfo(kind).label
						end,
					})
				Tooltip(typePick, L["Which units of that kind this row is for."])
				local whoPick = Choice(parent, widths[3], function() return WhoChoices(pick) end,
					function() return pick.who end, function(value)
						pick.who = value
						changed()
					end, {
						Items = function()
							local list = {}
							for _, who in ipairs(ns.MARK_ROW_KINDS[PickedKind(pick)] or {}) do
								list[#list + 1] = { value = who, text = REACTION_NAMES[who] }
							end
							return list
						end,
						On = function(who) return WhoOn(pick, who) end,
						Toggle = function(who)
							if not ToggleWho(pick, who) then return false end
							changed()
							return true
						end,
						Text = function() return pick.who == "Any" and L["Any"] or WhoName(pick.who) end,
					})
				Tooltip(whoPick, L["Tick Enemy, Neutral or Friendly for just those of them; all of them: any."])
				local distancePick = Choice(parent, widths[4], DistanceChoices, function() return pick.distance end,
					function(value)
						pick.distance = value
						changed()
					end)
				Tooltip(distancePick, L["How far from you the units must be."])
				return kindPick, function(after)
					local kind = KindInfo(pick)
					typePick:SetShown(kind[3] ~= nil)
					whoPick:SetShown(#(ns.MARK_ROW_KINDS[PickedKind(pick)] or {}) > 0)
					local last = kindPick
					for _, each in ipairs({ typePick, whoPick, distancePick, after }) do
						if each:IsShown() then
							each:ClearAllPoints()
							each:SetPoint("LEFT", last, "RIGHT", 6, 0)
							last = each
						end
					end
				end
			end

			-- A row made another kind, Who or Distance, in its place: its look,
			-- When, roles and name go over to the new id (the next free of them),
			-- the old id's back to its defaults. Nothing with five of them on the grid.
			local MARK_PARTS = { "Name", "Bar", "Border" }
			local function RetypeRow(id, pick)
				local db = ns.GetDB()
				local base, reaction, _, distance = ns.MarkRowBase(id)
				if PickedFirst(pick) == base .. (reaction or "") .. (distance or "") then return end
				local new = FreeRow(PickedKind(pick), pick.who ~= "Any" and pick.who or nil,
					pick.distance ~= "Any" and pick.distance or nil)
				if not new then return end
				local keys = {}
				for _, key in ipairs(MARK_COPY) do
					db[MarkKey(new, key)] = ns.TargetMarkOwn(key, id)
					keys[#keys + 1] = MarkKey(id, key)
				end
				for _, part in ipairs(MARK_PARTS) do
					db[new .. "Color" .. part] = ns.TargetMarkOwn("Color" .. part, id) and true or false
					keys[#keys + 1] = id .. "Color" .. part
				end
				db[new .. "When"] = db[id .. "When"]
				keys[#keys + 1] = id .. "When"
				for _, word in ipairs(ns.MARK_WHEN_WORDS) do
					db[new .. "When" .. word[2]] = db[id .. "When" .. word[2]]
					keys[#keys + 1] = id .. "When" .. word[2]
				end
				local profile = ns.ProfileBase()
				for _, key in ipairs(keys) do db[key] = profile[key] end
				if type(db.frameRules) == "table" then
					db.frameRules[new .. "When"], db.frameRules[id .. "When"] = db.frameRules[id .. "When"], nil
				end
				db.markNames = db.markNames or {}
				db.markNames[new], db.markNames[id] = db.markNames[id], nil
				opened[new], opened[id] = opened[id], nil
				local order = Order()
				for i, each in ipairs(order) do
					if each == id then order[i] = new end
				end
				SetOrder(order)
				preview:Pick(new)
			end
			-- A row copied: the next free of its kind, Who and Distance, with its
			-- look, When, roles and name (marked a copy), just below it, opened.
			-- Nothing with five of them on the grid.
			local function CopyRow(id)
				local db = ns.GetDB()
				local base, reaction, _, distance = ns.MarkRowBase(id)
				local new = FreeRow(base, reaction, distance)
				if not new then return end
				for _, key in ipairs(MARK_COPY) do
					db[MarkKey(new, key)] = ns.TargetMarkOwn(key, id)
				end
				for _, part in ipairs(MARK_PARTS) do
					db[new .. "Color" .. part] = ns.TargetMarkOwn("Color" .. part, id) and true or false
				end
				db[new .. "When"] = db[id .. "When"]
				for _, word in ipairs(ns.MARK_WHEN_WORDS) do
					db[new .. "When" .. word[2]] = db[id .. "When" .. word[2]]
				end
				if type(db.frameRules) == "table" then db.frameRules[new .. "When"] = db.frameRules[id .. "When"] end
				db.markNames = db.markNames or {}
				local own = db.markNames[id]
				db.markNames[new] = own and (L["%s (copy)"]):format(own):sub(1, 40) or nil
				local order = Order()
				local at = #order + 1
				for i, each in ipairs(order) do
					if each == id then at = i + 1 end
				end
				table.insert(order, at, new)
				opened[new] = true
				SetOrder(order)
				preview:Pick(new)
			end

			-- Look: a Look panel, as the Style pages': the bar's texture and
			-- border, the name's font, size, outline and shadow; and beside it
			-- the level box (Forever's). Each the Default row's to start (its
			-- own: the plate's usual look), in keys as the row's others
			-- (PlateRowLook.lua's, nil while it's the Default row's).
			function grid.BuildLookLine(kind, info, drawer, At, chips)
				local LOOK_DEFAULT = ns.PLATE_LOOK_DEFAULTS
				for _, key in ipairs(ns.PLATE_LOOK_KEYS) do RecordKey(content, MarkKey(kind, key)) end
				-- (The parts it colors: <kind>Color<part>, not the row's other keys;
				-- its custom color as the row has it, white to start.)
				local function FieldOf(key)
					local part = key:match("^Color(%u%l+)$")
					local dbKey = part and (kind .. key) or MarkKey(kind, key)
					return { get = function()
						if part then return ns.TargetMarkOwn(key, kind) and true or false end
						if key == "PlateR" or key == "PlateG" or key == "PlateB" then
							return ns.TargetMarkOwn(key, kind) or 1
						end
						local value = ns.GetDB()[dbKey]
						if value == nil then return LOOK_DEFAULT[key] end
						return value
					end, set = function(value)
						if LOOK_DEFAULT[key] ~= nil and value == LOOK_DEFAULT[key] then value = nil end
						ns.GetDB()[dbKey] = value
					end }
				end
				local function IsCustom()
					-- (The Default row's look always counts: its Customize always there.)
					if kind == "others" then return true end
					return ns.TargetMarkOwn("PlateColor", kind) == "custom"
						and not (ns.MarkRowBase(kind) == "aggro" and ns.TargetMarkOwn("AlsoSame", kind))
				end
				local function LookChanged()
					chips.Refresh()
					Changed()
				end
				-- (Each setting's first choice: Inherit, what's above the row.)
				local defaultName = L["Inherit"]
				local defaultTip = kind == "others"
					and L["Inherit: the plate's usual look."]
					or L["Inherit: as the Default row's Look has it."]
				-- (Its rows placed on the drawer's Look line: the panel's own are in it.)
				local onLine = { Add = function(_, control)
					control:SetParent(drawer)
					return At("Plate", control, LABEL_W + 106)
				end }
				local rows = ns.StyleRows(ns.lowHealthKit, content, onLine, LookChanged, "handlePlateStyle", FieldOf)
				local OUTLINE_NAMES = { [0] = L["None"], L["Thin"], L["Thick"] }
				local button = rows.Look("", info.full .. " - " .. L["Look"], {
					-- (Tabbed, the Look settings counted and reset; the row's color and
					-- the parts it paints are its own, left alone.)
					tabs = { default = function(key) return LOOK_DEFAULT[key] end,
						usual = function(key) return ns.PlateRowUsual(kind, key) end,
						-- (Where each comes from: This row, Default row's, General's...)
						source = function(key) return ns.PlateRowSource(kind, key) end,
						-- (Copy look / Paste between the rows; Start from a theme: its bar.)
						copyKind = "plateRow", copyName = info.full,
						themeLook = function(key) return ns.PlateThemeRowLook(key) end,
						themeList = function()
							local list = {}
							for _, theme in ipairs(ns.PlateThemeList()) do list[#list + 1] = { key = theme.key, name = L[theme.name] } end
							return list
						end,
						resetLabel = function() return kind == "others" and L["Reset all"] or L["Clear this row"] end },
					-- (A plate as this row's Look draws it: PlateRowLook.lua.)
					preview = function(parent, width) return ns.MakePlateRowLookPreview(parent, width, kind) end,
					texture = function(look)
						look.Dropdown(L["Texture:"], "LookTexture", function()
							local list = { { value = "default", text = defaultName } }
							for _, choice in ipairs(ns.StyleTextureChoices(L["The game's"], "LookTexture")) do
								list[#list + 1] = choice
							end
							return list
						end, L["The health bar's fill."] .. " " .. defaultTip)
					end,
					-- (Its color, and the parts that take it.)
					barColor = function(look)
						-- (Not on the Default row: it paints nothing, each plate keeping its
						-- own color, hostile, neutral or friendly. Its gradient still fades it.)
						if kind ~= "others" then
							look.Color(L["Color:"], { "PlateR", "PlateG", "PlateB" },
								L["The plate's color, for the parts ticked below."])
							for _, part in ipairs(ALSO_PARTS) do
								if not part.targetOnly or ns.MarkRowBase(kind) == "target" or ns.MarkRowBase(kind) == "aggro" then
									RecordKey(content, kind .. "Color" .. part[1])
									look.Check("Color" .. part[1], (L["%s in its color"]):format(part[2]), part[3])
								end
							end
						end
						-- (The fill fading, left to right, to a second color: PlateHealthStyle.lua.)
						look.Choices(L["Gradient:"], "LookGradient", { { "default", defaultName }, { "off", L["Off"] },
							{ "on", L["On"], L["The health bar's fill fades from its color on the left to the color " ..
								"below on the right."] } })
						look.Color(L["Fades to:"], { "LookGradR", "LookGradG", "LookGradB" },
							L["The color the health bar fades to, at its right end."],
							function(db) return look.On(db) and look.Get("LookGradient") == "on" end)
					end,
					ground = false,
					font = function(look)
						look.Font("LookFont", L["The name's font."] .. " " .. defaultTip, nil, { "default", defaultName })
					end,
					textSize = function(look)
						look.Slider("LookTextSize", L["Size"], 50, 200, 5, "%d%%", 100,
							L["The name's size, times its usual."])
					end,
					textColor = false, outlineColor = false, -- (its color: the Plate line's Name)
					outline = function(look)
						look.Outline("LookOutline", L["Outline"], 2, OUTLINE_NAMES, L["The name's outline."] .. " " ..
							defaultTip, nil, defaultName)
					end,
					shadow = function(look)
						look.Choices(L["Shadow:"], "LookShadow", { { "default", defaultName }, { "game", L["The game's"] },
							{ "on", L["Shadow"], L["A dark copy of the letters just behind them, down and to the right."] },
							{ "none", L["None"] } })
					end,
					border = function(look)
						look.Dropdown(L["Border:"], "LookBorder", function()
							-- (edge: a border's, drawn as one on the panel's tiles.)
							return { { value = "default", text = defaultName, edge = true },
								{ value = "game", text = L["The game's"], edge = true },
								{ value = "none", text = L["None"], edge = true }, { value = "thin", text = L["Thin"], edge = true },
								{ value = "thick", text = L["Thick"], edge = true },
								{ value = "custom", text = L["Custom"], edge = true } }
						end, L["The health bar's border."] .. " " .. defaultTip)
						local function Custom(db) return look.On(db) and look.Get("LookBorder") == "custom" end
						local line = look.Boxes()
						line:Box(L["Thickness"], look.K("LookBorderSize"), 1, 10, 1, "%d", 1,
							L["How thick the border is, in pixels."], Custom, "px")
						look.Swatch(line, "LookBorder", { "LookBorderR", "LookBorderG", "LookBorderB" },
							L["The border's color. Picking one turns it to Custom."])
					end,
					backColor = false, backAlpha = false,
					-- (Forever's level box at the bar's end: shown, hidden, or the Default row's.)
					level = not ns.isRetail and function(look)
						RecordKey(content, MarkKey(kind, "LookLevel"))
						look.Choices(L["Level box:"], "LookLevel", { { "default", defaultName },
							{ "show", L["Shown"] }, { "hide", L["Hidden"] } })
					end or false,
				})
				if button then
					grid.lookButtons = grid.lookButtons or {}
					grid.lookButtons[kind] = button
					button:SetParent(drawer)
					button:ClearAllPoints()
					At("Plate", button, LABEL_W + 106)
					-- (Its words: what the row has of its own, else Customize. Only on Custom.)
					local refresh = button.Refresh
					button.Refresh = function(self)
						refresh(self)
						self:SetShown(IsCustom())
						local parts = {}
						for _, each in ipairs({ { "LookTexture", L["Texture"] }, { "LookBorder", L["Border"] },
							{ "LookFont", L["Font"] }, { "LookTextSize", L["Size"] }, { "LookOutline", L["Outline"] },
							{ "LookShadow", L["Shadow"] }, { "LookGradient", L["Gradient"] } }) do
							local value = ns.GetDB() and ns.GetDB()[MarkKey(kind, each[1])]
							if value ~= nil and value ~= LOOK_DEFAULT[each[1]] then parts[#parts + 1] = each[2] end
						end
						self:SetText(#parts > 0 and table.concat(parts, " · ") or L["Customize"])
						self:SetWidth(math.max(120, self:GetFontString():GetStringWidth() + 30))
					end
					Tooltip(button, L["This row's own look on its plates."] ..
						" " .. defaultTip)
				end
			end

			function MakeRow(id)
				local info = RowInfo(id)
				local kind, base = id, info.base
				local row = CreateFrame("Button", nil, grid)
				row:SetSize(ROW_W, ROW_H)
				row:Hide()
				rows[kind] = row
				local hover = row:CreateTexture(nil, "HIGHLIGHT")
				hover:SetAllPoints()
				hover:SetColorTexture(1, 1, 1, 0.05)
				local line = row:CreateTexture(nil, "BACKGROUND")
				line:SetPoint("BOTTOMLEFT")
				line:SetPoint("BOTTOMRIGHT")
				line:SetHeight(1)
				line:SetColorTexture(1, 1, 1, 0.08)
				row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				row:SetScript("OnClick", function(_, button) Toggle(kind, button) end)
				local function Place(control, x, dy)
					control:SetPoint("LEFT", row, "LEFT", x, dy or 0)
					return control
				end
				local function Shown()
					return ns.TargetMarkSetting("Show", kind) and true or false
				end
				-- (Default stays last: no arrows.)
				if kind ~= "others" then
					moves[kind] = { up = MoveButton(row, kind, -1), down = MoveButton(row, kind, 1) }
				end

				local showKey = MarkKey(kind, "Show")
				RecordKey(content, showKey)
				local show = Place(Check(row, showKey, "", info.tip, function(value)
					ns.GetDB()[showKey] = value
					Refresh()
					Changed()
				end), SHOW_X)
				show.searchLabel = info.full

				-- Its Mark column: the mark in small over a plain grey bar (what
				-- the row does to the plate is the Plate column's), - for none.
				local preview = Place(CreateFrame("Frame", nil, row), PREVIEW_X)
				preview:SetSize(42, 22)
				if preview.SetClipsChildren then preview:SetClipsChildren(true) end
				local previewBack = preview:CreateTexture(nil, "BACKGROUND")
				previewBack:SetAllPoints()
				previewBack:SetColorTexture(0, 0, 0, 0.45)
				-- (Larger than the plate it stands for, a short bar low down: the
				-- mark over it is what to see, and round it room for brackets.)
				local holder = CreateFrame("Frame", nil, preview)
				holder:SetSize(94, 49)
				holder:SetScale(0.45)
				holder:SetPoint("CENTER")
				local bar = CreateFrame("Frame", nil, holder)
				bar:SetSize(60, 8)
				bar:SetPoint("CENTER", holder, "CENTER", 0, -16)
				bar:SetFrameLevel(holder:GetFrameLevel() + 2)
				local barEdge = bar:CreateTexture(nil, "BORDER")
				barEdge:SetPoint("TOPLEFT", -2, 2)
				barEdge:SetPoint("BOTTOMRIGHT", 2, -2)
				barEdge:SetColorTexture(0, 0, 0, 1)
				local barFill = bar:CreateTexture(nil, "ARTWORK")
				barFill:SetAllPoints()
				barFill:SetColorTexture(0.35, 0.35, 0.35, 1)
				-- (Default's: the game's own look, there being no row below it. Short,
				-- to fit its column.)
				local noMark = Label(row, "GameFontDisableSmall", kind == "others" and L["Game's"] or "-")
				noMark:SetPoint("CENTER", preview, "CENTER")
				noMark.searchSkip = true
				preview.Refresh = function()
					if not ns.MakeTargetArrow then return end
					local shown = Shown()
					local marked = ns.TargetMarkSetting("Style", kind) ~= "none"
					preview.arrow = preview.arrow or ns.MakeTargetArrow(holder, bar)
					ns.StyleTargetArrow(preview.arrow, nil, kind)
					preview.arrow:SetShown(marked)
					preview.arrow:SetAlpha(ns.TargetMarkSetting("Opacity", kind) or 1)
					holder:SetShown(marked)
					previewBack:SetShown(marked)
					noMark:SetShown(not marked)
					preview:SetAlpha(shown and 1 or 0.4)
				end
				controls[#controls + 1] = preview

				-- Its place in the order, grey before its name (set by the grid's
				-- Refresh): the first row that fits a plate decides. Default's
				-- none, as it has no arrows: it's for whatever none above fits.
				local number = Place(Label(row, "GameFontDisable", ""), NAME_X)
				number:SetWidth(NUMBER_W - 6)
				number:SetJustifyH("RIGHT")
				number.searchSkip = true
				row.number = number

				-- Its name: the kind's, its Who and number dimmed after it (orange
				-- while a row of its kind for all its units is above it).
				local name = Place(Label(row, "GameFontHighlight", ""), NAME_X + NUMBER_W)
				name:SetWidth(NAME_W - NUMBER_W)
				name:SetWordWrap(false)
				name.searchSkip = true
				function row:SetName()
					info = RowInfo(kind) -- (its own name may have changed)
					local sub = info.sub and ((self.below and " |cffff8c1a" or " |cff999999") .. info.sub .. "|r") or ""
					name:SetText(info.label .. sub)
					name:SetAlpha(Shown() and 1 or 0.5)
				end

				-- The Plate and When columns: each its chips (RowChips' column),
				-- as many as fit (hovering the row lists them all), or a grey word
				-- when the row sets nothing there.
				local function ChipColumn(x, width, column, empty)
					local holder2 = Place(CreateFrame("Frame", nil, row), x)
					holder2:SetSize(width, 16)
					holder2.searchSkip = true
					holder2.pool = {}
					holder2.empty = Label(holder2, "GameFontDisableSmall", empty)
					holder2.empty:SetPoint("LEFT", 2, 0)
					holder2.empty.searchSkip = true
					function holder2.Fill(list)
						local at, shownChips = 0, 0
						for _, each in ipairs(list) do
							if each[3] == column then
								local i = shownChips + 1
								local chip = holder2.pool[i]
								if not chip then
									chip = CreateFrame("Frame", nil, holder2)
									chip:SetHeight(16)
									chip.back = chip:CreateTexture(nil, "BACKGROUND")
									chip.back:SetAllPoints()
									chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
									chip.swatch = chip:CreateTexture(nil, "ARTWORK")
									chip.swatch:SetSize(10, 10)
									chip.swatch:SetPoint("LEFT", 4, 0)
									chip.swatchEdge = chip:CreateTexture(nil, "BORDER")
									chip.swatchEdge:SetPoint("TOPLEFT", chip.swatch, -1, 1)
									chip.swatchEdge:SetPoint("BOTTOMRIGHT", chip.swatch, 1, -1)
									chip.swatchEdge:SetColorTexture(0, 0, 0, 1)
									holder2.pool[i] = chip
								end
								chip.text:SetText(each[1])
								local swatch = each.swatch and each.swatch[1] and each.swatch
								chip.swatch:SetShown(swatch and true or false)
								chip.swatchEdge:SetShown(swatch and true or false)
								if swatch then chip.swatch:SetColorTexture(swatch[1], swatch[2], swatch[3], 1) end
								chip.text:ClearAllPoints()
								chip.text:SetPoint("CENTER", chip, "CENTER", swatch and 7 or 0, 0)
								local chipW = math.ceil(chip.text:GetStringWidth()) + 10 + (swatch and 14 or 0)
								if at + chipW > width then break end
								local c = CHIP_COLORS[each[2] or ""] or CHIP_PLAIN
								chip.back:SetColorTexture(c[1], c[2], c[3], 0.9)
								chip.text:SetTextColor(c[4], c[5], c[6])
								chip:SetWidth(chipW)
								chip:ClearAllPoints()
								chip:SetPoint("LEFT", holder2, "LEFT", at, 0)
								chip:Show()
								at, shownChips = at + chipW + 4, i
							end
						end
						for i = shownChips + 1, #holder2.pool do holder2.pool[i]:Hide() end
						holder2.empty:SetShown(shownChips == 0)
					end
					return holder2
				end
				local plateChips = ChipColumn(PLATE_X, PLATE_W, "plate", kind == "others" and L["Game's"] or "-")
				local whenChips = ChipColumn(WHEN_X, WHEN_W, "when", L["Always"])
				local chips = CreateFrame("Frame", nil, row) -- (a frame, for the page's Refresh to tell its page)
				chips:SetSize(1, 1)
				chips.searchSkip = true
				chips.Refresh = function()
					local list = RowChips(kind)
					row.chipList = list
					plateChips.Fill(list)
					whenChips.Fill(list)
					row:SetName()
				end
				controls[#controls + 1] = chips

				-- Its tip: what it's for, everything set apart, and the click.
				row:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(info.full, 1, 1, 1)
					GameTooltip:AddLine(info.tip, 0.8, 0.8, 0.8, true)
					for _, chip in ipairs(self.chipList or {}) do
						GameTooltip:AddLine("- " .. chip[1], 1, 0.82, 0)
					end
					if self.below then
						GameTooltip:AddLine((L["%s's own row is above this one, so it sets its parts first: move " ..
							"this one above it."]):format(RowInfo(self.below).label), 1, 0.55, 0.1, true)
					end
					GameTooltip:AddLine(L["Click to show or hide its settings."], 0.6, 0.6, 0.6)
					GameTooltip:Show()
				end)
				row:SetScript("OnLeave", function()
					GameTooltip:Hide()
					if preview.Hover then preview:Hover(nil) end
				end)
				row:HookScript("OnEnter", function()
					if preview.Hover then preview:Hover(kind) end
				end)

				-- Its drawer's button, and (every row but Default's own) a button
				-- to take it off.
				row.toggle = Place(CreateFrame("Button", nil, row), ROW_W - 44)
				row.toggle:SetSize(14, 14)
				row.toggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
				row.toggle:SetScript("OnClick", function() Toggle(kind) end)
				Tooltip(row.toggle, L["Show or hide this row's settings."])
				-- (Not shown: clicking the row opens and closes it. Kept, the grid's
				-- Refresh still sets its +/-.)
				row.toggle:Hide()
				if kind ~= "others" then
					-- (Copy: two squares, one over the other, drawn here, where the +/- was.)
					local copy = Place(CreateFrame("Button", nil, row), ROW_W - 44)
					copy:SetSize(16, 16)
					-- (Back one first, each its edge then its middle, so the front
					-- one's covers the back one's.)
					for i, square in ipairs({ { 0, 5 }, { 5, 0 } }) do
						local x, y = square[1], square[2]
						local edge = copy:CreateTexture(nil, "ARTWORK", nil, i * 2 - 2)
						edge:SetSize(11, 11)
						edge:SetPoint("TOPLEFT", x, -y)
						edge:SetColorTexture(1, 0.82, 0, 1)
						local inside = copy:CreateTexture(nil, "ARTWORK", nil, i * 2 - 1)
						inside:SetSize(7, 7)
						inside:SetPoint("TOPLEFT", x + 2, -y - 2)
						inside:SetColorTexture(0.1, 0.1, 0.1, 1)
					end
					copy:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
					Tooltip(copy, L["Copy this row."])
					copy:SetScript("OnClick", function() CopyRow(kind) end)
					copy.Refresh = function(self)
						local base, reaction, _, distance = ns.MarkRowBase(kind)
						local free = FreeRow(base, reaction, distance) ~= nil
						self:SetEnabled(free)
						self:SetAlpha(free and 1 or 0.35)
					end
					controls[#controls + 1] = copy
					local remove = Place(CreateFrame("Button", nil, row), ROW_W - 22)
					remove:SetSize(16, 16)
					remove:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
					remove:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
					Tooltip(remove, L["Remove this row."])
					remove:SetScript("OnClick", function() RemoveRow(kind) end)
				end

				-- The drawer: Name (your own), Row (its kind, Who and Distance),
				-- Mark (style, color, movement; size and opacity at the end),
				-- Plate (color and the parts it colors; size and opacity at the
				-- end) and When. Default's own no Row: it's always there. Page
				-- search finding something in it opens it (openSection).
				-- (Plate's line named Look: its color, and Custom's Look panel.)
				local LINES = { "Name", "Row", "Mark", "Plate", "When" }
				if kind == "others" then table.remove(LINES, 2) end
				local LINE_NAMES = { Row = L["Row"], Name = L["Name"], Mark = L["Mark"], Plate = L["Look"],
					When = L["When"] }
				local lineAt = {}
				for i, line in ipairs(LINES) do lineAt[line] = i end
				local drawer = CreateFrame("Frame", nil, grid)
				local DRAWER_W = ROW_W - DRAWER_X
				drawer:SetSize(DRAWER_W, LINE_H * #LINES + 8)
				drawer:Hide()
				drawers[kind] = drawer
				drawer.openSection = function()
					opened[kind] = true
					grid:Refresh()
				end
				local drawerBack = drawer:CreateTexture(nil, "BACKGROUND")
				drawerBack:SetAllPoints()
				drawerBack:SetColorTexture(0, 0, 0, 0.3)
				local function At(line, control, x, dy)
					control:SetPoint("LEFT", drawer, "TOPLEFT", x, -4 - LINE_H * (lineAt[line] - 0.5) + (dy or 0))
					return control
				end
				for _, line in ipairs(LINES) do
					local label = At(line, Label(drawer, "GameFontNormalSmall", LINE_NAMES[line]), 6)
					label.searchSkip = true
					-- (Look's the plate's too: the Plate column's color.)
					local tone = COLUMN_COLORS[line] or (line == "Look" and COLUMN_COLORS.Plate)
					if tone then label:SetTextColor(unpack(tone)) end
				end

				-- Look: its own line (grid.BuildLookLine, above: kept out of here, and on
				-- grid, for Lua's 60 upvalues a function).
				grid.BuildLookLine(kind, info, drawer, At, chips)

				-- A color's swatch: its R, G and B settings (keys), the color it
				-- shows (Current), the setting a pick puts on Custom (colorKey),
				-- shown while Visible says.
				local function Swatch(line, x, keys, colorKey, Current, Visible, tip)
					local swatch = At(line, CreateFrame("Button", nil, drawer), x)
					swatch:SetSize(18, 18)
					local swatchBorder = swatch:CreateTexture(nil, "BACKGROUND")
					swatchBorder:SetAllPoints()
					swatchBorder:SetColorTexture(0.6, 0.6, 0.6, 1)
					local swatchColor = swatch:CreateTexture(nil, "ARTWORK")
					swatchColor:SetPoint("TOPLEFT", 2, -2)
					swatchColor:SetPoint("BOTTOMRIGHT", -2, 2)
					Tooltip(swatch, tip)
					swatch.Refresh = function(self)
						local r, g, b = Current()
						swatchColor:SetColorTexture(r, g, b, 1)
						self:SetShown(Visible())
						self:SetEnabled(Shown())
						self:SetAlpha(Shown() and 1 or 0.4)
					end
					controls[#controls + 1] = swatch
					for _, key in ipairs(keys) do RecordKey(content, key) end
					swatch:SetScript("OnClick", function()
						local db = ns.GetDB()
						local r0, g0, b0 = Current()
						OpenColorPicker(r0, g0, b0, function(r, g, b)
							db[keys[1]], db[keys[2]], db[keys[3]] = r, g, b
							if colorKey then db[colorKey] = "custom" end
							Refresh()
							Changed()
						end)
					end)
					return swatch
				end

				-- A percent box at the end of a line (slot 1 the last, 2 before
				-- it), for a row's setting (or its kind's) as a whole percent, low
				-- to high: the mouse wheel steps it by 5, or type one and press
				-- Enter. Its name to its left.
				-- (x: its own place on the line, not its slot's.)
				local function PercentBox(line, slot, key, low, high, name, tip, x)
					local dbKey = MarkKey(kind, key)
					RecordKey(content, dbKey)
					local box = At(line, ns.SkinEditBox(CreateFrame("EditBox", nil, drawer, "InputBoxTemplate")),
						x or DRAWER_W - 60 - (slot - 1) * 100)
					box:SetSize(36, 20)
					box:SetAutoFocus(false)
					box:SetJustifyH("RIGHT")
					box:SetMaxLetters(4)
					box:EnableMouseWheel(true)
					box.searchLabel = info.full .. " " .. name
					box.settingKey = dbKey -- (its id for /cine find)
					local function Now()
						return math.floor((ns.TargetMarkSetting(key, kind) or 1) * 100 + 0.5)
					end
					-- (Just this row's parts drawn again: the whole page's Refresh
					-- on every wheel step hitched the game.)
					local function Set(percent)
						percent = math.max(low, math.min(high, math.floor(percent + 0.5)))
						ns.GetDB()[dbKey] = percent / 100
						-- (Typing in it: the bare number, still to edit.)
						box:SetText(tostring(Now()))
						box.edited = nil
						chips.Refresh()
						preview.Refresh()
						Changed()
					end
					box:SetScript("OnMouseWheel", function(self, delta)
						if self:IsEnabled() then Set(Now() + delta * 5) end
					end)
					box:SetScript("OnEditFocusGained", function(self)
						self:SetText(Now())
						self:HighlightText()
						self.edited = nil
					end)
					-- (Only a number typed in it is saved on leaving it: the wheel's
					-- steps are saved as they come.)
					box:SetScript("OnTextChanged", function(self, typed)
						if typed then self.edited = true end
					end)
					box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
					box:SetScript("OnEscapePressed", function(self)
						self.cancelled = true
						self:ClearFocus()
					end)
					box:SetScript("OnEditFocusLost", function(self)
						local typed = tonumber((self:GetText():gsub("%%", "")))
						if typed and self.edited and not self.cancelled then
							Set(typed)
						end
						self.cancelled, self.edited = nil, nil
						self:SetText(tostring(Now()))
					end)
					box.Refresh = function(self)
						if not self:HasFocus() then self:SetText(tostring(Now())) end
						if Shown() then self:Enable() else self:Disable() end
						self:SetAlpha(Shown() and 1 or 0.5)
					end
					controls[#controls + 1] = box
					Tooltip(box, tip)
					local label = Label(drawer, "GameFontHighlightSmall", name)
					label:SetPoint("RIGHT", box, "LEFT", -6, 0)
					label.searchSkip = true
					-- (The % after the box, the number alone in it.)
					local percent = Label(box, "GameFontHighlightSmall", "%") -- (on the box: hidden with it)
					percent:SetPoint("LEFT", box, "RIGHT", 3, 0)
					percent.searchSkip = true
					return box, label
				end

				-- Name: your own for the row, shown for it on the grid and the
				-- preview (empty: its kind's, greyed in the box).
				local nameBox = At("Name", ns.SkinEditBox(CreateFrame("EditBox", nil, drawer, "InputBoxTemplate")),
					LABEL_W + 6)
				nameBox:SetSize(220, 20)
				nameBox:SetAutoFocus(false)
				nameBox:SetMaxLetters(40)
				nameBox.searchSkip = true
				RecordKey(content, "markNames")
				local nameHint = nameBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
				nameHint:SetPoint("LEFT", 2, 0)
				nameHint:SetPoint("RIGHT", -2, 0)
				nameHint:SetJustifyH("LEFT")
				nameHint:SetWordWrap(false)
				local function OwnName()
					local db = ns.GetDB()
					local names = db and db.markNames
					return type(names) == "table" and names[kind] or ""
				end
				local function SaveName(self)
					local text = self:GetText():match("^%s*(.-)%s*$")
					local db = ns.GetDB()
					db.markNames = db.markNames or {}
					db.markNames[kind] = text ~= "" and text or nil
					row:SetName()
					Changed() -- (the page's preview's caption)
					nameHint:SetShown(text == "" and not self:HasFocus())
				end
				nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
				nameBox:SetScript("OnEditFocusLost", SaveName)
				nameBox:SetScript("OnEditFocusGained", function() nameHint:Hide() end)
				nameBox:SetScript("OnEscapePressed", function(self)
					self:SetText(OwnName())
					self:ClearFocus()
				end)
				nameBox.Refresh = function(self)
					if self:HasFocus() then return end
					self:SetText(OwnName())
					nameHint:SetText(AutoRowInfo(kind).full)
					nameHint:SetShown(OwnName() == "")
				end
				controls[#controls + 1] = nameBox
				Tooltip(nameBox, L["Your own name for this row; leave empty to use its kind's name."])

				-- Row: another kind, Who or Distance for it, as soon as it's picked
				-- (in its place, its settings with it: RetypeRow).
				if lineAt.Row then
					local pick = PickOf(kind)
					local kindPick, PlacePicks = PickLine(drawer, pick, { 100, 110, 90, 120 }, function()
						RetypeRow(kind, pick)
						-- (Nothing free to make it: back to its own.)
						local own = PickOf(kind)
						pick.kind, pick.type, pick.who, pick.distance = own.kind, own.type, own.who, own.distance
					end)
					At("Row", kindPick, LABEL_W)
					local placer = CreateFrame("Frame", nil, drawer)
					placer.Refresh = function() PlacePicks() end
					controls[#controls + 1] = placer
				end

				-- Mark: style, color (and its custom color's swatch), movement;
				-- size and opacity at the end.
				local style = At("Mark", Pick(drawer, MarkKey(kind, "Style"), base == "aggro" and AGGRO_STYLES
					or base == "others" and OTHERS_STYLES
					or base == "mouseover" and MOUSEOVER_STYLES or MARK_STYLES, 100), LABEL_W)
				style.searchLabel = info.full .. " " .. L["Style"]
				GreyUnless(style, Shown)
				-- (The rest of the line only with a mark: - has nothing to color,
				-- move or size.)
				local function MarkOn()
					return ns.TargetMarkSetting("Style", kind) ~= "none"
				end
				local function ShownWithMark(control, also)
					local refresh = control.Refresh
					control.Refresh = function(self)
						if refresh then refresh(self) end
						self:SetShown(MarkOn())
						if also then also:SetShown(MarkOn()) end
					end
				end
				local color = At("Mark", Pick(drawer, MarkKey(kind, "Color"), base == "aggro" and AGGRO_COLORS or MARK_COLORS,
					100), LABEL_W + 106)
				color.searchLabel = info.full .. " " .. L["Color"]
				Tooltip(color, L["The mark's color."])
				GreyUnless(color, Shown)
				-- (An aggro row on Your target's: your target's color, to start a custom one from.)
				local function MarkColour()
					if base == "aggro" and ns.TargetMarkOwn("Color", kind) == "same" and ns.TargetArrowColour then
						return ns.TargetArrowColour(nil, "target")
					end
					return ns.TargetMarkOwn("R", kind) or 1, ns.TargetMarkOwn("G", kind) or 1,
						ns.TargetMarkOwn("B", kind) or 1
				end
				Swatch("Mark", LABEL_W + 212, { MarkKey(kind, "R"), MarkKey(kind, "G"), MarkKey(kind, "B") },
					MarkKey(kind, "Color"), MarkColour, function() return MarkOn() and ns.TargetMarkOwn("Color", kind) == "custom" end,
					L["Click to choose the mark's custom color."])
				local bobKey = MarkKey(kind, "Bob")
				RecordKey(content, bobKey)
				local moving = At("Mark", Check(drawer, bobKey, L["Moving"],
					L["Makes the mark move or pulse."], function(value)
						ns.GetDB()[bobKey] = value
						Changed()
					end), LABEL_W + 234)
				moving.searchLabel = info.full .. " " .. L["Moving"]
				GreyUnless(moving, Shown)
				ShownWithMark(color)
				ShownWithMark(moving)
				ShownWithMark(PercentBox("Mark", 2, "Size", 50, 200, L["Size"], L["The mark's size."]))
				ShownWithMark(PercentBox("Mark", 1, "Opacity", 0, 100, L["Opacity"],
					L["The mark's own opacity (the plate's is on the Plate line)."]))

				-- Plate: its color (- for the next row's, the game's, the mark's,
				-- or its own) and the parts it colors; size (retail) and opacity
				-- at the end. An aggro row's first: Your target's (AlsoSame), your
				-- target's color and ticks.
				local sameKey = base == "aggro" and MarkKey(kind, "AlsoSame") or nil
				local plateKey = MarkKey(kind, "PlateColor")
				RecordKey(content, plateKey)
				if sameKey then RecordKey(content, sameKey) end
				local plateChoices = {}
				if sameKey then plateChoices[1] = { value = "target", text = L["Your target's"] } end
				for _, choice in ipairs(PLATE_COLORS) do
					-- (Default's - is the game's look, no row below it: one choice, named so.)
					if base ~= "others" then
						plateChoices[#plateChoices + 1] = choice
					elseif choice.value == "-" then
						plateChoices[#plateChoices + 1] = { value = "-", text = L["The game's"] }
					elseif choice.value ~= "game" then
						plateChoices[#plateChoices + 1] = choice
					end
				end
				local function PlateHow()
					if sameKey and ns.TargetMarkOwn("AlsoSame", kind) then return "target" end
					local how = ns.TargetMarkOwn("PlateColor", kind) or "-"
					if base == "others" and how == "game" then return "-" end
					return how
				end
				local plateColor = At("Plate", Choice(drawer, 100, function() return plateChoices end, PlateHow,
					function(value)
						local db = ns.GetDB()
						if sameKey then db[sameKey] = value == "target" end
						if value ~= "target" then db[plateKey] = value end
						-- (A color with no part ticked colors nothing: Bar ticked
						-- for it, so the plate and the previews show it.)
						if value ~= "-" and value ~= "game" then
							local any = false
							for _, part in ipairs(ALSO_PARTS) do
								if (not part.targetOnly or base == "target" or base == "aggro")
									and ns.TargetMarkOwn("Color" .. part[1], kind) then
									any = true
								end
							end
							if not any then db[kind .. "ColorBar"] = true end
						end
						Changed()
					end), LABEL_W)
				plateColor.searchLabel = info.full .. " " .. L["Plate color"]
				Tooltip(plateColor, L["Which color this row gives the plate, and on which parts."])
				GreyUnless(plateColor, Shown)
				-- (Not on the Default row: it paints nothing, 2026-11-16 (PlateParts' PlateHow):
				-- just its Customize, its look.)
				if kind == "others" then
					plateColor:Hide()
					plateColor.Show = plateColor.Hide
				end
				local function Colors()
					local how = PlateHow()
					return how ~= "-" and how ~= "game" and how ~= "target"
				end
				-- (Custom's color: in its Look panel, with the parts: grid.BuildLookLine.)
				-- (Its parts, ticks in one dropdown, closing up to the color with
				-- no swatch beside it.)
				local parts, partTips = {}, {}
				for _, part in ipairs(ALSO_PARTS) do
					if not part.targetOnly or base == "target" or base == "aggro" then
						RecordKey(content, kind .. "Color" .. part[1])
						parts[#parts + 1] = part
						partTips[#partTips + 1] = part[2] .. ": " .. part[3]
					end
				end
				local function PartOn(name)
					return ns.TargetMarkOwn("Color" .. name, kind) and true or false
				end
				local function PartItems()
					local list = {}
					for _, part in ipairs(parts) do list[#list + 1] = { value = part[1], text = ALSO_SHORT[part[1]] } end
					return list
				end
				local function TogglePart(name)
					ns.GetDB()[kind .. "Color" .. name] = not PartOn(name)
					Changed()
					return true
				end
				local partPick = Choice(drawer, 110, PartItems, function() end, TogglePart, {
					Items = PartItems,
					On = PartOn,
					Toggle = TogglePart,
					Text = function()
						local on = {}
						for _, part in ipairs(parts) do
							if PartOn(part[1]) then on[#on + 1] = ALSO_SHORT[part[1]] end
						end
						return #on > 0 and table.concat(on, ", ") or L["None"]
					end,
				})
				Tooltip(partPick, L["The parts of the plate in its color, ticks."] .. "\n\n" .. table.concat(partTips, "\n"))
				GreyUnless(partPick, Shown)
				local placer = CreateFrame("Frame", nil, drawer)
				placer.Refresh = function()
					partPick:ClearAllPoints()
					At("Plate", partPick, LABEL_W + 106)
					partPick:SetShown(kind ~= "others" and Colors() and PlateHow() ~= "custom")
				end
				controls[#controls + 1] = placer
				-- (Width and Height, W and H, the two boxes where one Size was.)
				-- (Just Width on WoW Forever, nothing on Classic Era: ns.plateSizes.)
				local sizes = ns.plateSizes or {}
				if sizes.width then
					local SIZE_TIP = L["Its name, mark and the rest of the plate move with the bar's edges."]
					local _, w = PercentBox("Plate", 2, "PlateWidth", 25, 300, L["Width"],
						L["The health bar's width."] .. " " .. SIZE_TIP .. (sizes.height and ""
							or (" " .. L["A long name is cut short to fit."])), DRAWER_W - 230)
					w:SetText(L["W"])
				end
				if sizes.height then
					local _, h = PercentBox("Plate", 2, "PlateHeight", 50, 300, L["Height"],
						L["The health bar's height."] .. " " .. L["Its name, mark and the rest of the plate move with " ..
						"the bar's edges."])
					h:SetText(L["H"])
				end
				PercentBox("Plate", 1, "Alpha", 0, 100, L["Opacity"], L["The plate's opacity while this row fits it."])

				-- When: as the Standard Frames page's rows.
				local whenKey = kind .. "When"
				RecordKey(content, whenKey)
				local menus, words = { {}, {}, {} }, {}
				for _, word in ipairs(ns.MARK_WHEN_WORDS) do
					local key = whenKey .. word[2]
					RecordKey(content, key)
					words[word[1]] = true
					local group = menus[WHEN_GROUP[word[1]] or 3]
					group[#group + 1] = { WHEN_NAMES[word[1]], function() return ns.GetDB()[key] and true or false end,
						function() ns.GetDB()[key] = not ns.GetDB()[key] end }
				end
				local function WhenChanged()
					Changed()
					chips.Refresh()
				end
				local when = ns.GridRow(ns.GRID_KIT, drawer, 0, WHEN_LAYOUT, {
					band = 1,
					always = { isOn = function() return ns.GetDB()[whenKey] end,
						set = function(value) ns.GetDB()[whenKey] = value end,
						tip = L["This row applies everywhere."] },
					menus = menus,
					rule = { key = function() return whenKey end, label = function() return info.full end, grid = words,
						words = function()
							local ticked = {}
							for _, word in ipairs(ns.MARK_WHEN_WORDS) do
								if ns.GetDB()[whenKey .. word[2]] then ticked[#ticked + 1] = word[1] end
							end
							return ticked
						end,
						apply = function(isAlways, ticked)
							local db = ns.GetDB()
							db[whenKey] = isAlways and true or false
							for _, word in ipairs(ns.MARK_WHEN_WORDS) do
								db[whenKey .. word[2]] = ticked[word[1]] and true or false
							end
						end,
						changed = WhenChanged },
					changed = WhenChanged,
				})
				At("When", when, LABEL_W)
				when:SetBand(1)
			end

			-- Adding a row: just a button. The row's an Any unit with its kind's
			-- look (no mark, plate color -) at the end of the grid, its drawer
			-- open to make it what you want (its Row line). With five of those,
			-- the first kind with one free.
			local adding = CreateFrame("Frame", nil, content)
			adding:SetSize(ROW_W, 24)
			stack:Add(adding, "label")
			local add = ns.PanelButton(adding)
			add:SetSize(90, 22)
			add:SetPoint("LEFT", adding, "LEFT", 0, 0)
			add:SetText(L["Add row"])
			Tooltip(add, L["Adds a new row at the end of the list."])
			local function NewRow()
				local id = FreeRow("all")
				for _, kind in ipairs(KINDS) do
					id = id or kind[1] ~= "others" and FreeRow(kind[1])
				end
				return id or nil
			end
			add:SetScript("OnClick", function()
				local id = NewRow()
				if id then AddRow(id, true) end
			end)
			add.Refresh = function(self) self:SetEnabled(NewRow() ~= nil) end
			controls[#controls + 1] = add

			grid:Refresh()

			-- (How fast a plate's opacity and size change, as CineMode's Fade in
			-- time: a quick look away from an elite and back barely shows.)
			stack:Header(content, L["All rows"])
			-- (On one line, small boxes: the time, and every plate's Width and
			-- Height, times each row's, as theirs: the ones this client takes.)
			local allRows = stack:Add(BoxLine(content), "label")
			allRows:Box(L["Change time"], "plateStyleFadeTime", 0, 10, 0.1, "%.1f", 1,
				L["How long plates take to change opacity or size."], nil, nil, L["sec"])
			if (ns.plateSizes or {}).width then
				allRows:Box(L["Width"], "plateStyleWidth", 25, 300, 5, "%d", 100,
					L["The health bar's width."], Changed, nil, "%")
			end
			if (ns.plateSizes or {}).height then
				allRows:Box(L["Height"], "plateStyleHeight", 50, 300, 5, "%d", 100,
					L["The health bar's height."], Changed, nil, "%")
			end
			-- (The game's Show Offscreen Nameplates in CineMode; none on a client
			-- without it.)
			if GetCVar("nameplateShowOffscreen") ~= nil then
				local offscreen = stack:Add(Check(content, "plateShowOffscreen", L["Off-screen plates in CineMode"],
					L["Keeps plates for units out of view pinned to the screen's edge in CineMode."]), "check")
				offscreen.searchLabel = L["Off-screen plates in CineMode"]
			end

			stack:Header(content, L["All marks"])
			-- (Two raises: on a showing plate, and with none; the marks move
			-- between them as the plate fades, as the quest mark does.)
			local marks = stack:Add(BoxLine(content), "label")
			marks:Box(L["Raise with a plate"], "targetArrowY", -40, 40, 1, "%d", 1,
				L["Moves the marks up or down while the plate shows."], Changed)
			marks:Box(L["without a plate"], "targetArrowBareY", -40, 40, 1, "%d", 1,
				L["Moves the marks up or down while the plate is hidden."], Changed)

			-- The two parts on frames of their own, each at the top where Show in
			-- was; the preview (and its spot) on the page, shown with both.
			local point, relative, relPoint, x, y = showHeader:GetPoint(1)
			local hosts = {}
			for i = 1, 2 do
				hosts[i] = CreateFrame("Frame", nil, content)
				hosts[i]:SetSize(1, 1)
				hosts[i]:SetPoint(point, relative, relPoint, x, y)
			end
			local keep = { [preview] = true, [preview.stackSpot or preview] = true, [preview.popSlot or preview] = true }
			for _, set in ipairs({ { content:GetChildren() }, { content:GetRegions() } }) do
				for _, object in ipairs(set) do
					if not before[object] and not keep[object] and object ~= hosts[1] and object ~= hosts[2] then
						object:SetParent(styleMade[object] and hosts[1] or hosts[2])
					end
				end
			end
			showHeader:ClearAllPoints()
			showHeader:SetPoint("TOPLEFT", hosts[1], "TOPLEFT", 0, 0)
			marksHeader:ClearAllPoints()
			marksHeader:SetPoint("TOPLEFT", hosts[2], "TOPLEFT", 0, 0)
			function ShowPart(i)
				hosts[1]:SetShown(i == 1)
				hosts[2]:SetShown(i == 2)
				ShowPlateTab(ns.ShowInIndex("plates", i == 1 and "Nameplate Style" or "Nameplate Marks"))
				FitContentHeight(content)
			end
			ShowPart(1)

			canvas:SetScript("OnShow", PageShown(Refresh, content))
		end
		local MakeStyle = lazyPages.Add(canvas, "Nameplate Style", MakeBody)
		-- (A hub tile each: Plate Style, and Marks hidden under the Nameplates icon too.)
		local function Pick(i)
			MakeStyle("its tab picked")
			if ShowPart then ShowPart(i) end
		end
		canvas.hubTabs = {
			{ name = "Nameplate Style", icon = "Interface\\Icons\\Ability_Marksmanship", label = "Nameplate Style",
				onSelect = function() Pick(1) end },
			{ name = "Nameplate Marks", icon = "Interface\\Icons\\Ability_Marksmanship", label = "Smart Style", own = true,
				onSelect = function() Pick(2) end },
		}
		canvas:Hide()
		RegisterSubpage(canvas, "Nameplate Style", L["Nameplate Style"])
	end
end

-- Sub-page for everything chat: fading, new-message peeks (by message type and
-- by channel) and when chat stays up. Its options on top, then sections that
-- open and close (as on the Standard Frames page), each a Standard Frames
-- table: the chat window's row, then a row per message type and per channel,
-- its columns saying when a new message shows chat (ns.RowOnNow).
-- (In a block: the main chunk's locals are near Lua's cap.)
local CreateChatPanel
do
	local CHAT_LABEL_WIDTH = 176 -- (wider and Edit goes under the scrollbar)
	local channelHolders = {} -- channel name -> its row's frame (made once, reused)

	-- The message types' and channels' tables: their tips, as what each column
	-- does for a message.
	local MESSAGE_TIPS = {
		cineShow = L["Its messages show chat any time the UI is faded."],
		combatShow = L["Its messages show chat in fights (while you stay cinematic in them)."],
		enemyShow = L["Its messages show chat out of combat with a living enemy targeted."],
		friendlyShow = L["Its messages show chat out of combat with anything else targeted."],
		bgShow = L["Its messages show chat in battlegrounds and arenas."],
		worldShow = L["Its messages show chat out in the world, inns included (capital cities are Cities)."],
		cityShow = L["Its messages show chat in capital cities."],
		groupShow = L["Its messages show chat while you're in a party or raid, wherever you are."],
		instanceShow = L["Its messages show chat in dungeons, scenarios and raids."],
	}
	local MESSAGE_COLUMN_TIPS = {}
	for c, column in ipairs(FRAME_COLUMNS) do
		MESSAGE_COLUMN_TIPS[c] = MESSAGE_TIPS[column[3]]
	end
	-- A message table's rows: these, its settings.
	local function MessageRows()
		return { labelWidth = CHAT_LABEL_WIDTH, columnTips = MESSAGE_COLUMN_TIPS }
	end

	-- The settings a table recorded on its own frame are the page's (its Reset),
	-- and its boxes grey while new messages don't show chat at all.
	local function ToPage(from)
		for key, section in pairs(pageKeys[from] or {}) do
			RecordKey(chatPanel, key, section)
		end
		for key, keyRows in pairs(pageRows[from] or {}) do
			for row, section in pairs(keyRows) do RecordRow(chatPanel, key, row, section) end
		end
		pageKeys[from], pageRows[from] = nil, nil
	end
	local function GreyUnlessPeek(parent)
		for _, object in ipairs({ parent:GetChildren() }) do
			if object.Refresh and object.SetEnabled then
				local refresh = object.Refresh
				object.Refresh = function(self)
					refresh(self)
					if not ns.GetDB().chatPeek then
						self:SetEnabled(false)
					end
				end
			end
		end
	end

	-- A channel's row, under the Channels table's headings: made the first
	-- time the channel is joined, kept for the next.
	local function ChannelHolder(name)
		local holder = channelHolders[name]
		if holder then
			return holder
		end
		holder = CreateFrame("Frame", nil, chatPanel.channelBody)
		holder:SetSize(1, 1)
		local rows = MessageRows()
		rows.noHeadings = true
		rows[1] = { key = ns.ChannelRowKey(name), label = name, alwaysTip = MESSAGE_TIPS.cineShow,
			alwaysOn = function() return ns.IsChannelPeekOn(name) end,
			setAlways = function(value) ns.GetDB().chatPeekChannelList[name] = value end }
		ShowTable(holder, holder, rows, "Chat", L["Channels"])
		GreyUnlessPeek(holder)
		ToPage(holder)
		channelHolders[name] = holder
		return holder
	end

	local function RefreshChannels()
		local channels = ns.GetJoinedChannels()
		local shown = {}
		for i, name in ipairs(channels) do
			local holder = ChannelHolder(name)
			holder:ClearAllPoints()
			holder:SetPoint("TOPLEFT", chatPanel.channelTop, "TOPLEFT", 0, -(i - 1) * 24)
			holder:Show()
			shown[holder] = true
		end
		for _, holder in pairs(channelHolders) do
			if not shown[holder] then holder:Hide() end
		end
		chatPanel.channelHeadings:SetShown(#channels > 0)
		chatPanel.noChannels:SetShown(#channels == 0)
		chatPanel.layoutSections()
	end

	function CreateChatPanel()
		local chatCanvas
		chatCanvas, chatPanel = CreateScrollPage()

		-- (The Chat icon's tabs over the title, 2026-11-16: this page's parts,
		-- the bubbles' pages, then its links: ns.ShowInTabs("chat").)
		local title = Label(chatPanel, "GameFontNormalLarge", L["Chat"])
		local outerTabs, ShowOuter = ns.PageTabs(chatPanel, ns.ShowInTabs("chat"), ns.ShowInIndex("chat", "Chat"))
		title:SetPoint("TOPLEFT", outerTabs, "BOTTOMLEFT", 8, -14)
		-- (When the chat window shows: its row is at the top of this page, Show in.)

		local subtitle = PageIntro(chatPanel, title,
			L["CineMode hides the chat window: pick what brings it back."])

		-- On top: the master switch and the peek's own options.
		local switch = PageSwitch(chatPanel, "handleChat", L["Enable Page"],
			L["Turns this page's chat settings on or off."],
			subtitle)

		-- (When the chat window shows at all: the Chat icon's Show in tab, the
		-- HUD page's Chat window section.)
		local tabsAnchor = switch

		local chatPeek = Check(chatPanel, "chatPeek", L["Show chat when a message arrives"],
			L["A new message briefly shows the chat window while the UI is faded."], function(value)
				ns.GetDB().chatPeek = value
				Refresh() -- grey out / enable the time and the messages below
			end)
		local function IfPeek(db) return db.chatPeek end

		-- (UI/Chat.lua's PeekLine: copies of just those lines over the faded window.)
		local linesOnly = Check(chatPanel, "chatPeekLinesOnly", L["Show just those messages"],
			L["Shows just the new messages, without the chat window around them."])
		linesOnly:SetPoint("TOPLEFT", chatPeek, "BOTTOMLEFT", 20, -2)
		GreyUnless(linesOnly, IfPeek)

		-- On top: how long chat stays up, in place of the mouseover time (all the way left: off).
		local peekTime = Slider(chatPanel, "chatPeekTime", L["Override Default Reveal Time"], 0, 60, 1,
			function(value) return value == 0 and L["Off"] or L["%d sec"]:format(value) end)
		peekTime:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 4, -26)
		Tooltip(peekTime, L["How long chat stays up after a message or after you finish typing."])
		chatPeek:SetPoint("TOPLEFT", peekTime, "BOTTOMLEFT", -4, -18)

		local hideOwn = Check(chatPanel, "chatHideOwn", L["Hide your messages"],
			L["Your own messages don't bring up chat."])
		hideOwn:SetPoint("TOPLEFT", linesOnly, "BOTTOMLEFT", -20, -2)
		GreyUnless(hideOwn, IfPeek)
		hideOwn:HookScript("OnClick", Refresh) -- (greys out / enables its exception)

		local ownNoBubble = Check(chatPanel, "chatOwnNoBubble", L["Except lines with no bubble"],
			L["Your messages without a chat bubble, like whispers, still bring up chat."])
		ownNoBubble:SetPoint("TOPLEFT", hideOwn, "BOTTOMLEFT", 20, -2)
		GreyUnless(ownNoBubble, function(db) return db.chatPeek and db.chatHideOwn end)

		local hideBubbled = Check(chatPanel, "chatHideBubbled", L["Hide speech you can see as a bubble"],
			L["Says and yells you can read in a bubble don't bring up chat."])
		hideBubbled:SetPoint("TOPLEFT", ownNoBubble, "BOTTOMLEFT", -20, -2)
		GreyUnless(hideBubbled, IfPeek)

		-- (Ticking it greys out / enables the Chat bubbles page's Behind you.)
		hideBubbled:HookScript("OnClick", Refresh)

		-- The tabs (ns.PageTabsBelow): Settings (the peek's own options and the
		-- chat window's), then a tab for each table of what shows chat, Other,
		-- and Addon Frame Links. A setting found by search on another tab opens it.
		local TAB_SETTINGS, TAB_LINKS = 1, 6
		local bodies = {}
		local Layout
		-- (Reveal's sub-tabs, all but the links: those are the Chat icon's own
		-- tab over the title, their row hidden there: chatCanvas.hubTabs, below.)
		local innerNow = 1 -- (the part shown now)
		local tabHosts, PickTab, TabsShown, _, _, innerPanel, innerTabs = ns.PageTabsBelow(chatPanel, tabsAnchor, {
			{ L["General"], L["When a new message shows chat, and what of the chat window comes up with it."] },
			{ L["Conversations"], L["Which people's messages show chat, and where: says, whispers, party, guild..."] },
			{ L["Game Messages"], L["Which of the game's messages show chat, and where."] },
			{ L["Channels"], L["Which channels you've joined show chat, and where."] },
			{ L["Other"], L["Chat lines of Cinematic's own."] },
			{ L["Addon Reveal Link"], L["Which frame each part of the chat is: the game's, or an addon's that draws its own."] },
		}, "Chat/page", nil, nil, nil, function(i)
			innerNow = i
			Layout()
		end)
		innerTabs[TAB_LINKS]:Hide()
		innerTabs[TAB_LINKS].Show = innerTabs[TAB_LINKS].Hide
		local settings = tabHosts[TAB_SETTINGS]
		for _, control in ipairs({ chatPeek, linesOnly, peekTime, hideOwn, ownNoBubble, hideBubbled }) do
			control:SetParent(settings)
		end
		peekTime:ClearAllPoints()
		peekTime:SetPoint("TOPLEFT", settings, "TOPLEFT", 4, -18)

		-- Each other tab's body: its rows under the tab's top, sized to them
		-- (the page's height is measured two frames deep).
		local function LayoutNow()
			for _, body in ipairs(bodies) do
				body:SetHeight(math.max(ContentDepth(body) or 1, 1))
			end
			FitContentHeight(chatPanel)
		end
		-- (Laid out again next frame too, once the rows have settled.)
		function Layout()
			LayoutNow()
			C_Timer.After(0, LayoutNow)
		end
		chatPanel.layoutSections = Layout
		local function TabBody(i)
			local body = CreateFrame("Frame", nil, tabHosts[i])
			body:SetPoint("TOPLEFT", tabHosts[i], "TOPLEFT", 2, 0)
			body:SetPoint("RIGHT", chatPanel, "RIGHT", -16, 0)
			body:SetHeight(1)
			bodies[#bodies + 1] = body
			return body
		end
		-- (A table's anchor: a point at the top of its body. Not the body
		-- itself: a table hangs under its anchor, and the body grows to fit it.)
		local function TableTop(body)
			local anchor = CreateFrame("Frame", nil, body)
			anchor:SetSize(1, 1)
			anchor:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
			return anchor
		end

		-- Chat window: plain ticks, on Settings under the peek's. (Where it
		-- stays up is its row on the Standard Frames page.)
		-- (Each part's settings under its old section's name, as the profile
		-- modules' scopes have them: Chat/Other and the rest.)
		SetSection(chatPanel, L["Chat window"])
		local windowHeading = Label(settings, "GameFontNormal", L["Chat window"])
		windowHeading:SetPoint("TOPLEFT", hideBubbled, "BOTTOMLEFT", 2, -18)
		local untilRead = Check(settings, "chatUntilWhisperRead", L["Keep chat up until whispers are read"],
			L["Keeps chat up until you click the tab with a new whisper."])
		untilRead:SetPoint("TOPLEFT", windowHeading, "BOTTOMLEFT", -2, -6)
		local tabHint = Check(settings, "chatHideTabHint", L["Hide the tabs' right-click hint"],
			L["Hides the right-click hint when you hover a chat tab."])
		tabHint:SetPoint("TOPLEFT", untilRead, "BOTTOMLEFT", 0, -2)
		-- What of the window a new message brings up with it (hovering,
		-- typing and unread whispers still bring it all).
		local partsLabel = Label(settings, "GameFontHighlight", L["A message shows"])
		partsLabel:SetPoint("TOPLEFT", tabHint, "BOTTOMLEFT", 2, -10)
		local PARTS_TIP = L["Hovering the chat, typing or a whisper to read still brings it all up."]
		for i, part in ipairs({
			{ "chatPeekBackground", L["Background"], L["Shows the chat window's background with a new message."] },
			{ "chatPeekTabs", L["Tabs"], L["The chat window's tabs (General, Combat Log...) come up with a new message."] },
			{ "chatPeekButtons", L["Buttons"], L["Shows the buttons beside the chat window with a new message."] },
		}) do
			local check = Check(settings, part[1], part[2], part[3] .. " " .. PARTS_TIP)
			check:SetPoint("TOPLEFT", partsLabel, "BOTTOMLEFT", -2 + (i - 1) * 110, -4)
			GreyUnless(check, IfPeek)
		end

		-- The message types that show chat: people's, then the game's.
		local function TypeSection(tab, heading, game)
			SetSection(chatPanel, heading)
			local body = TabBody(tab)
			local rows = MessageRows()
			for _, peekType in ipairs(ns.CHAT_PEEK_TYPES) do
				if (peekType.section == "game") == game then
					local key = peekType.key
					rows[#rows + 1] = { key = "chat:" .. key, label = peekType.label, tip = peekType.tip,
						alwaysTip = MESSAGE_TIPS.cineShow,
						alwaysOn = function() return ns.IsPeekTypeAlways(key) end,
						setAlways = function(value) ns.GetDB().chatPeekTypes[key] = value end }
				end
			end
			ShowTable(body, TableTop(body), rows, "Chat", heading)
			GreyUnlessPeek(body)
			return body, #rows
		end
		local conversationBody, conversationRows = TypeSection(2, L["Conversation"], false)
		-- Typing last, a row of its own (chatShowWhileTyping its Always; see
		-- Frames.lua): not a message, so not greyed with the peek off.
		local typing = CreateFrame("Frame", nil, conversationBody)
		typing:SetSize(1, 1)
		typing:SetPoint("TOPLEFT", conversationBody, "TOPLEFT", 0, -conversationRows * 24)
		local typingRows = MessageRows()
		typingRows.noHeadings = true
		typingRows.columnTips = nil
		typingRows[1] = { key = "chat:typing", label = L["Typing"],
			tip = L["Pressing Enter brings up the chat window where ticked, else just the input box."],
			alwaysTip = L["Typing brings up the chat window any time. (The other columns then have nothing to add.)"],
			alwaysOn = function() return ns.GetDB().chatShowWhileTyping end,
			setAlways = function(value) ns.GetDB().chatShowWhileTyping = value end }
		ShowTable(typing, typing, typingRows, "Chat", L["Conversation"])
		ToPage(typing)
		RecordKey(chatPanel, "chatShowWhileTyping")
		TypeSection(3, L["Game messages"], true)

		-- Channels the player has joined, a row each (ChannelHolder), listed
		-- again each time the page opens.
		SetSection(chatPanel, L["Channels"])
		local channelBody = TabBody(4)
		chatPanel.channelBody = channelBody
		local channelNote = Label(channelBody, "GameFontHighlightSmall",
			L["Channels you've joined, like General or Trade. The list updates each time you open this page."])
		channelNote:SetPoint("TOPLEFT", channelBody, "TOPLEFT", 0, 0)
		channelNote:SetWidth(560)
		channelNote:SetJustifyH("LEFT")
		local channelTop = CreateFrame("Frame", nil, channelBody)
		channelTop:SetSize(1, 1)
		channelTop:SetPoint("TOPLEFT", channelNote, "BOTTOMLEFT", 0, -8)
		chatPanel.channelTop = channelTop
		local headings = CreateFrame("Frame", nil, channelBody)
		headings:SetSize(1, 1)
		headings:SetPoint("TOPLEFT", channelTop, "TOPLEFT", 0, 0)
		ShowTable(headings, headings, MessageRows())
		chatPanel.channelHeadings = headings
		chatPanel.noChannels = Label(channelBody, "GameFontDisableSmall", L["No channels joined."])
		chatPanel.noChannels:SetPoint("TOPLEFT", channelTop, "TOPLEFT", 0, -10)

		-- Other: chat lines of Cinematic's own.
		SetSection(chatPanel, L["Other"])
		local otherBody = TabBody(5)
		-- (Attacks shown on the screen: the Cards page's now.)
		local attackAlert = ns.CardsLink(otherBody, L["Attacks shown on the screen:"], "attack")
		attackAlert:SetPoint("TOPLEFT", otherBody, "TOPLEFT", 0, -6)
		local updateNotice = Check(otherBody, "updateNotice", L["Get notified of updates"],
			L["Tells you in chat when Cinematic has updated."])
		updateNotice:SetPoint("TOPLEFT", attackAlert, "BOTTOMLEFT", -2, -4)

		for _, body in ipairs(bodies) do
			ToPage(body)
		end
		-- (The Always boxes' own settings, for the page's Reset too.)
		RecordKey(chatPanel, "chatPeekTypes")
		RecordKey(chatPanel, "chatPeekChannelList")

		-- Addon Frame Links, its tab's (made after the Always boxes' keys are
		-- recorded, so those stay Other's): which frame each part of the chat
		-- is, the game's or an addon's that draws its own (FrameLinks.lua). A
		-- jump to it from elsewhere opens the tab.
		SetSection(chatPanel, L["Addon Frame Links"])
		local linksBody = TabBody(TAB_LINKS)
		local linkBand = ns.BuildLinkBand(linksBody, "chat", Layout)
		ns.RegisterLinkSection("chat", tabHosts[TAB_LINKS], function() PickTab(TAB_LINKS) end)
		ToPage(linksBody)
		ns.WatchFrameLinks(function()
			if chatCanvas:IsVisible() then
				linkBand.Refresh()
				Layout()
			end
		end)

		chatCanvas:SetScript("OnShow", PageShown(function()
			if ns.GetDB() then RefreshChannels() end
			Refresh() -- (after: new channels' rows too)
			linkBand.Refresh()
			TabsShown()
		end, chatPanel))
		chatCanvas:Hide()
		-- Two hub tiles, hidden under the Chat icon (its Show in tab, the HUD
		-- page's: tabOf): Reveal (the part last shown, or General; the sub-tabs'
		-- row shown) and the links (their own tab over the title, the sub-tabs'
		-- row hidden, no On/Off: no switch of theirs).
		local function ShowPart(links)
			local part = links and TAB_LINKS or (innerNow ~= TAB_LINKS and innerNow or 1)
			PickTab(part)
			ShowOuter(ns.ShowInIndex("chat", links and "Chat Links" or "Chat"))
			innerPanel:SetShown(not links)
			for i, tab in ipairs(innerTabs) do
				if i ~= TAB_LINKS then tab:SetShown(not links) end
			end
			title:SetText(links and L["Addon Reveal Link"] or L["Chat"])
			chatPanel.headerSwitchOff = links
			local header = chatPanel.pageHeaderSwitch
			if header then header:SetShown(not links) end
		end
		chatCanvas.hubTabs = {
			{ name = "Chat", icon = "Interface\\Icons\\INV_Scroll_03", label = "Chat", section = "Chat",
				tabOf = "HUD:chat", onSelect = function() ShowPart(false) end },
			{ name = "Chat Links", icon = "Interface\\Icons\\INV_Scroll_03", label = "Chat", section = "Chat",
				own = true, tabOf = "HUD:chat", noSwitch = true, onSelect = function() ShowPart(true) end },
		}
		RegisterSubpage(chatCanvas, "Chat")
	end
end

-- Sub-page listing the built-in frames, each with a checkbox to keep it shown.
local RefreshExtras

-- The Advanced Frames page's columns, for the supported addons and the
-- custom frames alike: the name, then Always and the Standard Frames
-- page's columns ({ heading, isOn, list, needs "stay cinematic in combat" }).
local THIRD_PARTY_LABEL_WIDTH = FRAME_LABEL_WIDTH
local THIRD_PARTY_COLUMNS = { { L["Always"] } } -- (its own setting: the frames left alone)
for c = 2, #FRAME_COLUMNS do
	THIRD_PARTY_COLUMNS[c] = FRAME_COLUMNS[c]
end
-- Their rows as the Standard Frames page's: Always, the dropdowns, the roles and Edit (GridRows.lua).
local THIRD_PARTY_LAYOUT = { edit = true }

-- One row of the custom frames list, made as needed: a small X (takes it off
-- the list), the name, and the columns. row.item: { name, picked, kept, added,
-- found, addon }. Placed by the page's Layout, under its addon's header (so
-- the X and name sit a step in, past the header's +).
local function GetExtraRow(index)
	local row = extraRows[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, extrasPanel.box)
	row:SetSize(THIRD_PARTY_LABEL_WIDTH + ns.GridWidth(THIRD_PARTY_LAYOUT), 24)

	row.delete = ns.SkinClose(CreateFrame("Button", nil, row, "UIPanelCloseButton"))
	row.delete:SetSize(22, 22)
	row.delete:SetPoint("LEFT", 14, 0)
	Tooltip(row.delete, L["Removes this frame from the list."])
	row.delete:SetScript("OnClick", function()
		local item = row.item
		if item.picked then
			ns.DropPickedFrame(item.name)
		else
			ns.ForgetExtraFrame(item.name)
		end
		RefreshExtras()
	end)

	row.text = Label(row, "GameFontHighlight")
	row.text:SetPoint("LEFT", 38, 0)
	row.text:SetWidth(THIRD_PARTY_LABEL_WIDTH - 42 - ns.GRID_DOT_ROOM)
	row.text:SetWordWrap(false)
	-- (Hovering the name: what it is, and for a found one, why it's there.)
	row.hover = CreateFrame("Frame", nil, row)
	row.hover:SetAllPoints(row.text)
	row.hover:EnableMouse(true)
	row.hover.fullLabel = row.text -- (its full name over the tip while cut short)

	-- Its settings: Always (left alone), the Standard Frames page's lists,
	-- its roles and rule, all by its key (the row's reused for other frames).
	-- A picked frame has none yet; one kept up from the built-in list, just Always.
	local function Key() return row.item and "extra:" .. row.item.name end
	local function SetKept(value) ns.SetFrameKept(row.item.name, value) end
	local parts = ns.ListRowParts(Key, THIRD_PARTY_COLUMNS, nil, SetKept)
	row.grid = ns.GridRow(ns.GRID_KIT, row, THIRD_PARTY_LABEL_WIDTH, THIRD_PARTY_LAYOUT, {
		band = index, dot = true,
		enabled = function() return not row.unloaded end, -- (greyed on the Not running tab)
		always = { isOn = function() return row.item and row.item.kept end, set = SetKept,
			tip = L["Keeps this frame shown the whole time in CineMode."] },
		menus = parts.menus,
		rule = { key = Key, label = function() return row.item and row.item.name or "" end, grid = parts.grid,
			words = parts.words, apply = parts.apply },
		cells = function()
			local item = row.item
			if not item or item.picked then return "none" end
			return item.added and "full" or "always"
		end,
		changed = function() RefreshExtras() end,
	})
	row.grid:SetPoint("LEFT", row, "LEFT", THIRD_PARTY_LABEL_WIDTH, 0)
	extraRows[index] = row
	return row
end

RefreshExtras = function()
	local faded, ignored = ns.GetExtraFrames()
	local db = ns.GetDB()
	local items = {}
	-- Frames add mode has picked so far, at the top while it's on (/cine add
	-- mode's: Hover Find's are on the Find frames list).
	if not ns.addModeToList then
		for _, name in ipairs(ns.GetPickedFrames()) do items[#items + 1] = { name = name, picked = true } end
	end
	-- Faded ones and ones kept up (/cine keep, or Always ticked: added ones and
	-- built-in ones), in one order by name: ticking Always doesn't move a row.
	local listed = {}
	for _, name in ipairs(faded) do listed[#listed + 1] = { name = name, added = true } end
	for _, name in ipairs(ignored) do
		listed[#listed + 1] = { name = name, kept = true, added = db.extraFrames[name] or false }
	end
	table.sort(listed, function(a, b) return a.name:lower() < b.name:lower() end)
	for _, item in ipairs(listed) do items[#items + 1] = item end

	for i, item in ipairs(items) do
		local row = GetExtraRow(i)
		row.item = item
		local known = db.foundFrames[item.name]
		item.found = known ~= nil and not known.dismissed
		item.addon = ns.FrameAddon(item.name)
		-- (A built-in frame kept up has its rows on the Standard Frames page.)
		if not item.picked and item.added then
			local key = "extra:" .. item.name
			-- (For the page's Reset: just these rows of the shared lists, and its rule.)
			for c = 2, #THIRD_PARTY_COLUMNS do
				RecordKey(extrasPanel, THIRD_PARTY_COLUMNS[c][3])
				RecordRow(extrasPanel, THIRD_PARTY_COLUMNS[c][3], key, L["Custom frames"])
			end
			for _, list in ipairs({ "calmShow", "frameRules" }) do
				RecordKey(extrasPanel, list)
				RecordRow(extrasPanel, list, key, L["Custom frames"])
			end
		end
		row.grid:Refresh()
		-- (An addon's unnamed frames: one row, "@<addon>".)
		local unnamed = item.name:sub(1, #ns.UNNAMED_PREFIX) == ns.UNNAMED_PREFIX
		local label = unnamed and L["Its unnamed frames"] or item.name
		if item.picked then
			row.text:SetText("|cffffd100" .. label .. "|r |cff808080(" .. L["picked"] .. ")|r")
		elseif item.added then
			row.text:SetText(label .. " |cffd9b35a(" .. L["added"] .. ")|r")
		else
			row.text:SetText(label)
		end
		local tip = unnamed and L["Frames with no name that %s made."]:format(item.addon) or item.name
		-- (Added from the Find frames tab with a guess: the row it follows.)
		local follow = item.found and ns.RowLabel(known.follow)
		if follow then
			tip = tip .. "\n\n" .. L["It follows the HUD row of the game's %s until you give it its own."]:format(follow)
		end
		Tooltip(row.hover, tip)
	end
	extrasPanel.extraCount = #items
	extrasPanel.Layout()
	FitContentHeight(extrasPanel)
end

-- Sub-page: other addons' frames. The addons faded out of the box (a switch
-- for each one installed; the rest listed), then frames beyond the built-in
-- list, faded with /cine add.
-- Sub-page: the minimap in cinematic mode: what reveals it, what keeps it open.
local function CreateMinimapPanel()
	local canvas, content = CreateScrollPage()

	-- (The Minimap icon's Reveal and Frame Links tabs, its Show in the HUD
	-- page's: ns.ShowInTabs("minimap"), 2026-11-16.)
	local title = Label(content, "GameFontNormalLarge", L["Show Advanced"])
	local outer, ShowOuter = ns.PageTabs(content, ns.ShowInTabs("minimap"), 2)
	title:SetPoint("TOPLEFT", outer, "BOTTOMLEFT", 8, -14)

	local subtitle = PageIntro(content, title,
		L["CineMode hides the minimap: pick what brings it back."])
	local switch = PageSwitch(content, "handleMinimap", L["Enable Page"],
		L["Turns this tab's minimap settings on or off."], subtitle)

	-- Three parts (ns.PageTabsBelow, its tabs not drawn: the icon's pick them):
	-- Reveal, Keep Open (2026-11-16) and Addon Frame Links.
	local partHosts, PickPart, TabsShown, AdoptTab = ns.PageTabsBelow(content, switch, {
		{ L["Show Advanced"], L["What brings the hidden minimap up for a while."] },
		{ L["Keep Open"], L["Where and while what the minimap stays up the whole time."] },
		{ L["Addon Reveal Link"], L["Which supported addon's frames stand in for the minimap's parts."] },
	}, "Minimap/page", 3, "minimap", 1, nil, true)
	local keepHost = partHosts[2]
	ns.ShowInParts(canvas, content, title, "minimap", PickPart, ShowOuter, { label = "Minimap",
		icon = "Interface\\Icons\\INV_Misc_Map_01", titles = { L["Show Advanced"], L["Keep Open"], L["Addon Reveal Link"] },
		switchLabel = "Show Advanced" })

	-- Retail's quest waypoint (the marker in the world showing where to go).
	local aboveTracking
	if ns.OptionAvailable({ retail = true }) then
		local waypoint = Check(content, "alwaysShowWaypoint", L["Always show the quest waypoint"],
			L["Keeps the quest waypoint marker visible in CineMode."])
		waypoint:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 0, -10)
		aboveTracking = waypoint
	end

	-- Reveal: the faded minimap comes up for a while (pings), or while
	-- something is on it (NodeSweep.lua looks).
	local revealLabel = Label(content, "GameFontHighlight", L["Reveal"])
	revealLabel:SetPoint("TOPLEFT", aboveTracking or switch, "BOTTOMLEFT", 4, -14)
	local aboveReveal
	-- Reveal shows: which of the header's parts come up with the map
	-- (minimapRevealParts, row keys comma-separated; "" = just the map).
	-- Only the parts this client has (a managed frame in their row).
	local REVEAL_PARTS = {
		{ "minimapzone", L["Zone name"] }, { "minimapheader", L["Minimap header"] },
		{ "minimaptracking", L["Tracking button"] }, { "minimapcalendar", L["Calendar"] },
		{ "minimapclock", L["Clock"] }, { "minimapdial", L["Day/night dial"] },
		{ "minimapaddons", L["Addon buttons"] }, { "minimapcompartment", L["Addon compartment"] },
		{ "minimapcoords", L["Coordinates"] }, { "minimapmail", L["Mail"] },
	}
	local function PartsHere()
		local here, has = {}, {}
		for _, entry in ipairs(ns.managed or {}) do
			if entry.group then has[entry.group] = true end
		end
		for _, part in ipairs(REVEAL_PARTS) do
			if has[part[1]] then here[#here + 1] = part end
		end
		return here
	end
	local function PartShown(key)
		return ((ns.GetDB().minimapRevealParts or "") .. ","):find(key .. ",", 1, true) ~= nil
	end
	local function SetParts(keys)
		ns.GetDB().minimapRevealParts = table.concat(keys, ",")
	end
	local function TogglePart(key)
		local keys = {}
		for _, part in ipairs(REVEAL_PARTS) do
			if (part[1] == key) ~= PartShown(part[1]) then keys[#keys + 1] = part[1] end
		end
		SetParts(keys)
	end
	RecordKey(content, "minimapRevealParts")
	local okParts, parts = ns.MenuDropdown(content)
	if okParts and parts and parts.SetupMenu then
		-- (Straight under Reveal, no name of its own: "Reveal shows" under
		-- "Reveal" said it twice, the user 2026-11-13. Its tip says what it is.)
		parts:SetPoint("TOPLEFT", revealLabel, "BOTTOMLEFT", 8, -6)
		parts:SetWidth(260)
		parts.searchSkip = true -- (it shows the current ticks, not a label)
		parts:SetupMenu(function(_, root)
			root:CreateButton(L["Everything"], function()
				local keys = {}
				for _, part in ipairs(PartsHere()) do keys[#keys + 1] = part[1] end
				SetParts(keys)
				return MenuResponse and MenuResponse.Refresh
			end)
			root:CreateButton(L["Just the map"], function()
				SetParts({})
				return MenuResponse and MenuResponse.Refresh
			end)
			if root.CreateDivider then root:CreateDivider() end
			for _, part in ipairs(PartsHere()) do
				root:CreateCheckbox(part[2], function() return PartShown(part[1]) end, function()
					TogglePart(part[1])
					return MenuResponse and MenuResponse.Refresh
				end)
			end
		end)
		if parts.SetSelectionText then
			parts:SetSelectionText(function()
				local here, ticked = PartsHere(), {}
				for _, part in ipairs(here) do
					if PartShown(part[1]) then ticked[#ticked + 1] = part[2] end
				end
				if #ticked == 0 then return L["Just the map"] end
				return #ticked == #here and L["Everything"] or L["Map"] .. ", " .. table.concat(ticked, ", ")
			end)
		end
		parts.Refresh = function(self) self:GenerateMenu() end
		controls[#controls + 1] = parts
		Tooltip(parts, L["Which parts come up with the minimap when it's revealed."])
		aboveReveal = parts
	end
	local ping = Check(content, "minimapRevealOnPing", L["Pings"],
		L["Shows the minimap when someone pings it."], function(value)
			ns.GetDB().minimapRevealOnPing = value
			Refresh() -- grey out / enable the time below
		end)
	if aboveReveal then
		ping:SetPoint("TOPLEFT", aboveReveal, "BOTTOMLEFT", 4, -6)
	else
		ping:SetPoint("TOPLEFT", revealLabel, "BOTTOMLEFT", 12, -4)
	end
	local pingTime = Slider(content, "minimapPingTime", L["Override Default Reveal Time"], 0, 60, 1,
		function(value) return value == 0 and L["Off"] or L["%d sec"]:format(value) end)
	pingTime:SetPoint("TOPLEFT", ping, "BOTTOMLEFT", 4, -26)
	Tooltip(pingTime, L["How long the minimap stays up after a ping."])
	GreyUnless(pingTime, function(db) return db.minimapRevealOnPing end)
	-- (What goes under the slider lines up with the checkboxes again.)
	local pingSpacer = CreateFrame("Frame", nil, content)
	pingSpacer:SetSize(1, 1)
	pingSpacer:SetPoint("TOPLEFT", pingTime, "BOTTOMLEFT", -4, -14)
	local questsOnly = not ns.CanSweepMinimap() and ns.CanRevealQuestsOnly()
	-- (Nodes there by the cursor sweep instead, NodeSweep.lua: its own key,
	-- off to start with, and no marks, which need where each node is.)
	local byCursor = questsOnly and ns.CanCursorSweepMinimap and ns.CanCursorSweepMinimap()
	local function RevealKinds(list)
		if not questsOnly then return list end
		local kept = {}
		for _, kind in ipairs(list) do
			if kind[1] == "minimapRevealTurnIns" or kind[1] == "minimapRevealAreas"
				or (byCursor and kind[1] == "minimapRevealNodes") then
				kept[#kept + 1] = kind
			end
		end
		return kept
	end
	local previousReveal = pingSpacer
	-- (Hidden where the minimap can't be swept: retail, and Forever once the game stopped answering, NodeSweep.lua.)
	for _, kind in ipairs(RevealKinds(not (ns.CanSweepMinimap() or questsOnly) and {} or {
		{ "minimapRevealNodes", L["Nearby ore, herbs and treasure"],
			L["Shows the minimap while a vein, herb or chest is on it."] },
		{ "minimapRevealTurnIns", L["Quest turn-ins"],
			L["The minimap comes up while a quest of yours that's done shows on it, where you hand it in."] },
		{ "minimapRevealAreas", L["Quest areas"],
			L["Shows the minimap while one of your quest areas is on it."] },
		{ "minimapRevealIcons", L["Other icons"],
			L["Shows the minimap while another named icon is on it."] },
	})) do
		local cursorNodes = byCursor and kind[1] == "minimapRevealNodes"
		local key = cursorNodes and "minimapNodesByCursor" or kind[1]
		-- (The cursor sweep can't read names since Forever's 2026-11-12 patch,
		-- NodeSweep.lua: any dot counts, and its box says so.)
		local label, tip = kind[2], kind[3]
		if cursorNodes then
			label = L["Nearby Dots"]
			tip = L["Shows the minimap while a gathering dot is near you."]
		end
		local check = Check(content, key, label, tip,
			kind[1] == "minimapRevealNodes" and function(value)
				ns.GetDB()[key] = value
				Refresh()
			end or nil)
		check:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", -(previousReveal.revealIndent or 0),
			previousReveal.revealIndent and -6 or -2)
		previousReveal = check
		-- (Under it: how each node is marked, minimapNodeMark.)
		-- (The cursor sweep: a ping where it heard its find, just a box.)
		if cursorNodes then
			local ping = Check(content, "minimapNodePing", L["Ping where it is"],
				L["Pings the minimap where a dot shows up; your group sees it."])
			ping:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 20, -2)
			GreyUnless(ping, function(db) return db.minimapNodesByCursor end)
			ping.revealIndent = 20
			previousReveal = ping
		end
		if kind[1] == "minimapRevealNodes" and not cursorNodes then
			local function IfNodes(db) return db.minimapRevealNodes end
			local MARK_TIP = L["How a found vein, herb or chest is marked on the minimap."]
			local MARKS = {
				{ value = "mark", text = L["Our mark (no sound)"] },
				{ value = "ping", text = L["Ping"] },
				{ value = "off", text = L["Off"] },
			}
			local markLabel = Label(content, "GameFontHighlight", L["Mark where it is"])
			markLabel:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 20, -6)
			local mark = Dropdown(content, "minimapNodeMark", MARKS, 240)
			if mark then
				mark:SetPoint("TOPLEFT", markLabel, "BOTTOMLEFT", -4, -4)
				mark.rowName = markLabel
				Tooltip(mark, MARK_TIP)
				GreyUnless(mark, IfNodes)
				mark.revealIndent = 16
				previousReveal = mark
				-- Node icons (minimapNodeIcons, kinds comma-separated): which kinds
				-- get their icon on the node, kept there while it's on the minimap.
				local ICON_KINDS = { { "ore", L["Ore"] }, { "herb", L["Herbs"] } }
				-- (SetupMenu builds the menu right away, before saved settings load: no db yet, tested.)
				local function IconOn(key)
					local db = ns.GetDB()
					return db ~= nil and ((db.minimapNodeIcons or "") .. ","):find(key .. ",", 1, true) ~= nil
				end
				RecordKey(content, "minimapNodeIcons")
				local okIcons, icons = ns.MenuDropdown(content)
				if okIcons and icons and icons.SetupMenu then
					local iconsLabel = Label(content, "GameFontHighlight", L["Node icons"])
					iconsLabel:SetPoint("TOPLEFT", mark, "BOTTOMLEFT", 4, -8)
					icons:SetPoint("TOPLEFT", iconsLabel, "BOTTOMLEFT", -4, -4)
					icons:SetWidth(240)
					icons.searchSkip = true -- (it shows the current ticks, not a label)
					icons:SetupMenu(function(_, root)
						for _, iconKind in ipairs(ICON_KINDS) do
							root:CreateCheckbox(iconKind[2], function() return IconOn(iconKind[1]) end, function()
								local keys = {}
								for _, each in ipairs(ICON_KINDS) do
									if (each[1] == iconKind[1]) ~= IconOn(each[1]) then keys[#keys + 1] = each[1] end
								end
								ns.GetDB().minimapNodeIcons = table.concat(keys, ",")
								return MenuResponse and MenuResponse.Refresh
							end)
						end
					end)
					if icons.SetSelectionText then
						icons:SetSelectionText(function()
							local ticked = {}
							for _, iconKind in ipairs(ICON_KINDS) do
								if IconOn(iconKind[1]) then ticked[#ticked + 1] = iconKind[2] end
							end
							return #ticked > 0 and table.concat(ticked, ", ") or L["None"]
						end)
					end
					icons.Refresh = function(self) self:GenerateMenu() end
					controls[#controls + 1] = icons
					icons.rowName = iconsLabel
					Tooltip(icons, L["Shows the herb or ore icon on the ticked kinds of nodes."])
					GreyUnless(icons, IfNodes)
					icons.revealIndent = 16
					previousReveal = icons
				end
			else
				previousReveal = markLabel
				for _, choice in ipairs(MARKS) do
					local radio = Choice(content, "minimapNodeMark", choice.value, choice.text, MARK_TIP)
					radio:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", previousReveal == markLabel and -4 or 0, -2)
					GreyUnless(radio, IfNodes)
					previousReveal = radio
				end
				previousReveal.revealIndent = 16
			end
		end
		if cursorNodes then
			-- What the workaround costs: a red "!" after the box's name, the
			-- words in its tip (a block of red text under it was a lot, the
			-- user 2026-11-13).
			local warn = CreateFrame("Frame", nil, content)
			warn:SetSize(16, 18)
			local nameText = check.Text or check.text
			warn:SetPoint("LEFT", nameText or check, "RIGHT", 6, 0)
			local bang = warn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
			bang:SetPoint("CENTER")
			bang:SetText("!")
			bang:SetTextColor(1, 0.3, 0.25)
			warn:EnableMouse(true)
			Tooltip(warn, L["A workaround that briefly moves the hidden minimap under your mouse."])
			-- Where it looks: its Show in row (NodeSweep.lua's cursor.ROW), Open
			-- world ticked to start with, In combat its fights. (In place of In
			-- combat too and an Except in row, 2026-11-13.)
			local rowTop = CreateFrame("Frame", nil, content)
			rowTop:SetSize(1, 1)
			-- (Under Ping where it is, at its edge, close under it: the column
			-- headings make the gap. At the box's own edge it stuck out left
			-- of it, and a full gap left a hole, seen 2026-11-13.)
			rowTop:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", 0, 0)
			local lastRow = ShowTable(content, rowTop, {
				opts = { anyFight = true }, underHeader = true,
				-- (Its name 20 narrower for the indent: the columns end where
				-- the page's other tables do, clear of the scroll bar.)
				labelWidth = FRAME_LABEL_WIDTH - 20,
				-- (Just Combat and Location: where it looks and whether in fights,
				-- the user 2026-11-13. No Always: Location's every place is it.)
				layout = ns.GRID_PLACE_COMBAT_LAYOUT,
				{ key = ns.MINIMAP_DOTS_ROW, label = L["Nearby Dots"] },
			})
			-- (What comes next goes under the row's whole height, back at the
			-- box's edge: placed at its label, Quest turn-ins ran into it.)
			local rowEnd = CreateFrame("Frame", nil, content)
			rowEnd:SetSize(1, 1)
			rowEnd:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -8)
			rowEnd.revealIndent = (previousReveal.revealIndent or 0)
			previousReveal = rowEnd
		end
	end
	-- Quest givers nearby (QuestGlow.lua): NPC nameplates the game would show
	-- a quest cursor over. (Hidden on a client without SetUnitCursorTexture.)
	if ns.QuestGiversPossible and ns.QuestGiversPossible() then
		local givers = Check(content, "minimapQuestGivers", L["Quest givers nearby"],
			L["Shows the minimap while a quest giver is near you."])
		givers:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", -(previousReveal.revealIndent or 0),
			previousReveal.revealIndent and -6 or -2)
		previousReveal = givers
	end
	-- Use Questie DB (Support/QuestieMinimap.lua): Questie's own minimap
	-- icons reveal it too. Greyed out while Questie isn't loaded; hidden on
	-- retail, which Questie never runs on.
	if ns.QuestieMinimapPossible and ns.QuestieMinimapPossible() then
		local questie = Check(content, "minimapQuestie", L["Use Questie DB"],
			L["Shows the minimap while one of Questie's quest icons is on it."] ..
			(ns.QuestieLoaded() and "" or ("\n\n" .. L["Needs Questie: it isn't loaded."])))
		questie:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", -(previousReveal.revealIndent or 0),
			previousReveal.revealIndent and -6 or -2)
		GreyUnless(questie, function() return ns.QuestieLoaded() end)
		previousReveal = questie
	end
	local onTaxi = Check(content, "minimapHideOnTaxi", L["Not on flight paths"],
		L["Keeps the minimap hidden while you're on a flight path."])
	onTaxi:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", 0, -2)
	previousReveal = onTaxi


	-- Keep open: the minimap stays up the whole time. (Its own tab, Keep Open:
	-- what's made from here on goes onto it, at the end.)
	local beforeKeep = {}
	for _, object in ipairs({ content:GetChildren() }) do beforeKeep[object] = true end
	for _, object in ipairs({ content:GetRegions() }) do beforeKeep[object] = true end
	local keepLabel = Label(content, "GameFontHighlight", L["Keep open"])
	keepLabel:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", -12, -10)
	local indoors = Check(content, "minimapIndoors", L["Indoors"],
		L["Keeps the minimap up indoors during CineMode."])
	-- Zones you picked (minimapKeepZones, map IDs comma-separated): a row
	-- each (name, Remove), then a button to add the one you're in.
	-- (First under Keep open, at the checkboxes' edge: under Indoors it read
	-- as a part of Indoors, the user 2026-11-13.)
	local zonesLabel = Label(content, "GameFontHighlightSmall", L["In these zones:"])
	zonesLabel:SetPoint("TOPLEFT", keepLabel, "BOTTOMLEFT", 16, -6)
	local function ZoneEntries()
		local entries = {}
		for id in (ns.GetDB().minimapKeepZones or ""):gmatch("%d+") do
			entries[#entries + 1] = tonumber(id)
		end
		return entries
	end
	local function SaveZones(entries)
		ns.GetDB().minimapKeepZones = table.concat(entries, ", ")
		Refresh()
		FitContentHeight(content)
	end
	local function ZoneName(id)
		local ok, info = pcall(C_Map.GetMapInfo, id)
		return ok and type(info) == "table" and type(info.name) == "string" and info.name
			or ("|cff808080(%d)|r"):format(id)
	end
	local zoneRows = {}
	local function ZoneRow(i)
		local row = zoneRows[i]
		if not row then
			row = CreateFrame("Frame", nil, keepHost) -- (on the Keep Open tab, with the rest of Keep open)
			row:SetSize(200, 22) -- (Remove ends where the Add button does)
			row.text = Label(row, "GameFontHighlight")
			row.text:SetPoint("LEFT", 0, 0)
			row.remove = ns.PanelButton(row)
			row.remove:SetSize(70, 20)
			row.remove:SetPoint("RIGHT", 0, 0)
			row.remove:SetText(L["Remove"])
			row.remove:SetScript("OnClick", function(self)
				local entries = ZoneEntries()
				table.remove(entries, self:GetParent().index)
				SaveZones(entries)
			end)
			zoneRows[i] = row
		end
		return row
	end
	local addZone = ns.PanelButton(content)
	addZone:SetSize(200, 20)
	addZone:SetScript("OnClick", function()
		local map = ns.CurrentZoneMap()
		if not map then return end
		local entries = ZoneEntries()
		for _, id in ipairs(entries) do
			if id == map then return end
		end
		entries[#entries + 1] = map
		SaveZones(entries)
	end)
	Tooltip(addZone, L["Keeps the minimap up in the zones listed here."])
	-- Rebuilt as the page shows and after each change.
	controls[#controls + 1] = { debugName = "minimap zone list", owner = content, Refresh = function()
		local previous = zonesLabel
		local entries = ZoneEntries()
		local here, listed = ns.CurrentZoneMap(), false
		for i, id in ipairs(entries) do
			local row = ZoneRow(i)
			row.index = i
			row.text:SetText(ZoneName(id))
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -4 or -2)
			row:Show()
			previous = row
			listed = listed or id == here
		end
		for i = #entries + 1, #zoneRows do zoneRows[i]:Hide() end
		addZone:SetText(here and L["Add %s"]:format(ZoneName(here)) or L["Add this zone"])
		addZone:SetWidth(math.max(200, addZone:GetFontString():GetStringWidth() + 24))
		addZone:SetEnabled(here ~= nil and not listed)
		addZone:ClearAllPoints()
		addZone:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
	end }
	RecordKey(content, "minimapKeepZones") -- (for Reset page)

	local quest =Check(content, "minimapKeepQuest", L["Tracking a quest"],
		L["Keeps the minimap up while you track a quest."], function(value)
			ns.GetDB().minimapKeepQuest = value
			Refresh()
		end)
	indoors:SetPoint("TOPLEFT", addZone, "BOTTOMLEFT", -4, -6)
	quest:SetPoint("TOPLEFT", indoors, "BOTTOMLEFT", 0, -2)
	-- (Under it: how long after picking up a quest or progress on one.)
	local questFor = Slider(content, "minimapKeepQuestFor", L["Only after progress"], 0, 10, 1,
		function(value) return value == 0 and L["Off"] or L["%d min"]:format(value) end)
	questFor:SetPoint("TOPLEFT", quest, "BOTTOMLEFT", 24, -22)
	Tooltip(questFor, L["How long the minimap stays up after quest progress; Off keeps it up."])
	GreyUnless(questFor, function(db) return db.minimapKeepQuest end)
	-- (Retail: hunting your prey. Left off where the client has no prey hunts.)
	local aboveCreatures, creaturesGap = questFor, { -24, -10 }
	if ns.HasPreyHunts() then
		local prey = Check(content, "minimapKeepPrey", L["Hunting your prey"],
			L["Keeps the minimap up while you hunt your prey."])
		prey:SetPoint("TOPLEFT", questFor, "BOTTOMLEFT", -24, -10)
		aboveCreatures, creaturesGap = prey, { 0, -2 }
	end
	-- Tracking (Tracking.lua, minimapKeep<kind>): a tick per kind of tracking
	-- that keeps the minimap up while it's on.
	local TRACK_NAMES = { Ore = L["Ore"], Herbs = L["Herbs"], Treasure = L["Treasure"], Humanoids = L["Humanoids"],
		Fish = L["Fish"], Beasts = L["Beasts"], Demons = L["Demons"], Undead = L["Undead"], Dragonkin = L["Dragonkin"],
		Elementals = L["Elementals"], Giants = L["Giants"], Hidden = L["Hidden"] }
	local TRACK_TIP = L["Keeps the minimap up while the ticked tracking is on."]
	local trackLabel = Label(content, "GameFontHighlight", L["Tracking"])
	trackLabel:SetPoint("TOPLEFT", aboveCreatures, "BOTTOMLEFT", creaturesGap[1] + 4, creaturesGap[2] - 6)
	local aboveExcept, exceptX = trackLabel, 20
	local okTrack, track = ns.MenuDropdown(content)
	if okTrack and track and track.SetupMenu then
		track:SetPoint("TOPLEFT", trackLabel, "BOTTOMLEFT", -4, -4)
		track:SetWidth(240)
		-- (Found by its name and key, not the ticks it shows.)
		trackLabel.searchSkip = true
		track.searchLabel, track.settingKey = L["Tracking"], "minimapKeepOre"
		track.searchEdges = { top = trackLabel, bottom = track, left = track, right = track }
		track:SetupMenu(function(_, root)
			for _, kind in ipairs(ns.TRACKING_KINDS) do
				root:CreateCheckbox(TRACK_NAMES[kind.kind] or kind.kind,
					-- (SetupMenu builds the menu right away, before saved settings load.)
					function()
						local db = ns.GetDB()
						return db ~= nil and db[kind.key] and true or false
					end,
					function()
						local db = ns.GetDB()
						db[kind.key] = not db[kind.key]
						Refresh()
						return MenuResponse and MenuResponse.Refresh
					end)
			end
		end)
		if track.SetSelectionText then
			track:SetSelectionText(function()
				local db, ticked = ns.GetDB(), {}
				for _, kind in ipairs(ns.TRACKING_KINDS) do
					if db and db[kind.key] then ticked[#ticked + 1] = TRACK_NAMES[kind.kind] or kind.kind end
				end
				return #ticked > 0 and table.concat(ticked, ", ") or L["None"]
			end)
		end
		track.Refresh = function(self) self:GenerateMenu() end
		controls[#controls + 1] = track
		track.rowName = trackLabel
		Tooltip(track, TRACK_TIP)
		aboveExcept, exceptX = track, 24
	else
		for _, kind in ipairs(ns.TRACKING_KINDS) do
			local check = Check(content, kind.key, TRACK_NAMES[kind.kind] or kind.kind, TRACK_TIP, function(value)
				ns.GetDB()[kind.key] = value
				Refresh()
			end)
			check:SetPoint("TOPLEFT", aboveExcept, "BOTTOMLEFT", aboveExcept == trackLabel and -4 or 0, -2)
			aboveExcept, exceptX = check, 20
		end
	end
	for _, kind in ipairs(ns.TRACKING_KINDS) do RecordKey(content, kind.key) end
	-- Where gathering tracking keeps the minimap up: its Show in row (Core.lua's
	-- ns.IsTrackingOffHere), Combat and Location, as Nearby Dots' (in place of
	-- an Except in row, 2026-11-13). Open world and Combat to start with.
	local trackTop = CreateFrame("Frame", nil, content)
	trackTop:SetSize(1, 1)
	trackTop:SetPoint("TOPLEFT", aboveExcept, "BOTTOMLEFT", exceptX - 20, -2)
	ShowTable(content, trackTop, {
		opts = { anyFight = true }, underHeader = true, layout = ns.GRID_PLACE_COMBAT_LAYOUT,
		labelWidth = FRAME_LABEL_WIDTH - 20,
		{ key = ns.MINIMAP_TRACKING_ROW, label = L["Tracking"],
			tip = L["Where gathering tracking keeps the minimap up."] },
	})
	-- (Keep open onto its tab, its heading at the top; then the rest onto Reveal.)
	for _, set in ipairs({ { content:GetChildren() }, { content:GetRegions() } }) do
		for _, object in ipairs(set) do
			if not beforeKeep[object] then object:SetParent(keepHost) end
		end
	end
	keepLabel:ClearAllPoints()
	keepLabel:SetPoint("TOPLEFT", keepHost, "TOPLEFT", 4, 0)
	AdoptTab(switch) -- (everything above onto the Reveal tab)
	canvas:SetScript("OnShow", PageShown(function()
		Refresh()
		TabsShown()
	end, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Minimap")
end

-- Sub-page: the quest tracker in CineMode: the quest timer, and a look at
-- the tracker when you accept a quest.
local function CreateQuestTrackerPanel()
	local canvas, content = CreateScrollPage()

	-- (The Quest Tracker icon's Reveal and Frame Links tabs, its Show in the
	-- HUD page's: ns.ShowInTabs("quests"), 2026-11-16.)
	local title = Label(content, "GameFontNormalLarge", L["Show Advanced"])
	local outer, ShowOuter = ns.PageTabs(content, ns.ShowInTabs("quests"), 2)
	title:SetPoint("TOPLEFT", outer, "BOTTOMLEFT", 8, -14)

	local subtitle = PageIntro(content, title,
		L["CineMode hides the quest tracker: pick what brings it back."])

	local reveal = Check(content, "questRevealOnAccept", L["New quest"],
		L["Accepting a quest shows the quest tracker."])
	local switch = PageSwitch(content, "handleQuests", L["Enable Page"],
		L["Turns this page's quest tracker settings on or off."], subtitle)

	-- Two parts (ns.PageTabsBelow, its tabs not drawn: the icon's pick them):
	-- Reveal, and Addon Frame Links.
	local tabHosts, PickPart, TabsShown, AdoptTab = ns.PageTabsBelow(content, switch, {
		{ L["Show Advanced"], L["What brings the hidden quest tracker up for a while."] },
		{ L["Addon Reveal Link"], L["Which supported addon's frames stand in for the quest tracker."] },
	}, "Quest tracker/page", 2, "quests", 1, nil, true)
	ns.ShowInParts(canvas, content, title, "quests", PickPart, ShowOuter, { label = "Quest Tracker",
		icon = "Interface\\Icons\\INV_Misc_Note_01", titles = { L["Show Advanced"], L["Addon Reveal Link"] }, switchLabel = "Show Advanced" })
	reveal:SetParent(tabHosts[1]) -- (made before the switch: onto the tab too)

	-- On top: how long a reveal keeps the tracker up, in place of the mouseover time (all the way left: off).
	local revealTime = Slider(content, "questRevealTime", L["Override Default Reveal Time"], 0, 60, 1,
		function(value) return value == 0 and L["Off"] or L["%d sec"]:format(value) end)
	-- (On the tab's top, down by its label, which sits above the slider: not under
	-- the switch, which AdoptTab would move to the tab's very top, the label on the tabs.)
	revealTime:SetPoint("TOPLEFT", tabHosts[1], "TOPLEFT", 4, -16)
	Tooltip(revealTime, L["How long a quest update keeps the quest tracker up."])
	GreyUnless(revealTime, function(db) return db.questRevealOnAccept or db.questRevealOnProgress or db.questRevealOnScenario end)
	reveal:SetPoint("TOPLEFT", revealTime, "BOTTOMLEFT", -4, -18)
	reveal:HookScript("OnClick", Refresh) -- grey out / enable the option below

	-- Children: each reveal can stay up for the Calm Timer instead.
	local QUEST_INDENT = 16
	local calmTip = L["Keeps the quest tracker up for the Calm Timer instead."]
	local acceptCalm = Check(content, "questAcceptCalm", L["Keep up for the Calm Timer"], calmTip)
	acceptCalm:SetPoint("TOPLEFT", reveal, "BOTTOMLEFT", QUEST_INDENT, -2)
	GreyUnless(acceptCalm, function(db) return db.questRevealOnAccept end)

	local revealProgress = Check(content, "questRevealOnProgress", L["Quest progress"],
		L["Quest progress shows the quest tracker."])
	revealProgress:SetPoint("TOPLEFT", acceptCalm, "BOTTOMLEFT", -QUEST_INDENT, -2)
	revealProgress:HookScript("OnClick", Refresh) -- grey out / enable the option below

	local progressCalm = Check(content, "questProgressCalm", L["Keep up for the Calm Timer"], calmTip)
	progressCalm:SetPoint("TOPLEFT", revealProgress, "BOTTOMLEFT", QUEST_INDENT, -2)
	GreyUnless(progressCalm, function(db) return db.questRevealOnProgress end)

	-- Scenarios: raid bosses' and dungeons' stages, which aren't quests.
	local lastReveal = progressCalm
	if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
		local revealScenario = Check(content, "questRevealOnScenario", L["Scenario progress"],
			L["Scenario progress shows the quest tracker."])
		revealScenario:SetPoint("TOPLEFT", progressCalm, "BOTTOMLEFT", -QUEST_INDENT, -2)
		revealScenario:HookScript("OnClick", Refresh) -- grey out / enable the option below

		local scenarioCalm = Check(content, "questScenarioCalm", L["Keep up for the Calm Timer"], calmTip)
		scenarioCalm:SetPoint("TOPLEFT", revealScenario, "BOTTOMLEFT", QUEST_INDENT, -2)
		GreyUnless(scenarioCalm, function(db) return db.questRevealOnScenario end)
		lastReveal = scenarioCalm
	end

	local onlyThat = Check(content, "questRevealOnlyThat", L["Just that quest"],
		L["Shows just the quest that changed, not the whole tracker."])
	onlyThat:SetPoint("TOPLEFT", lastReveal, "BOTTOMLEFT", -QUEST_INDENT, -2)
	GreyUnless(onlyThat, function(db) return db.questRevealOnAccept or db.questRevealOnProgress or db.questRevealOnScenario end)
	onlyThat:HookScript("OnClick", Refresh) -- grey out / enable the option below

	local questCollapse = Check(content, "questRevealCollapse", L["Close the gaps"],
		L["Moves that quest to the top of the tracker."])
	questCollapse:SetPoint("TOPLEFT", onlyThat, "BOTTOMLEFT", QUEST_INDENT, -2)
	GreyUnless(questCollapse, function(db)
		return db.questRevealOnlyThat and (db.questRevealOnAccept or db.questRevealOnProgress or db.questRevealOnScenario)
	end)

	-- (Ticked In combat, the tracker stays for the Calm Timer after a fight: it's the fight still.)

	-- Classic's quest timer box; retail shows timers in the tracker itself.
	local timer
	if ns.OptionAvailable({ retail = false }) then
		timer = Check(content, "questTimerShow", L["Quest timer"],
			L["Keeps the quest timer up while a timed quest counts down."])
	else
		timer = Check(content, "questTimerShow", L["Show timers in the quest tracker while one is running"],
			L["Keeps the quest tracker's timers up while one is running."])
	end
	timer:SetPoint("TOPLEFT", questCollapse, "BOTTOMLEFT", -QUEST_INDENT, -2)
	local lastQuest = timer

	-- The durability figure (with the page on, as the rest).
	local durability = Check(content, "durabilityShow", L["Damaged gear"],
		L["Shows the damaged gear figure while your gear needs repair."])
	durability:SetPoint("TOPLEFT", lastQuest, "BOTTOMLEFT", 0, -16)
	durability:HookScript("OnClick", Refresh) -- grey out / enable the option below

	local durabilityCam = Check(content, "durabilityHideInCam", L["Hide in camera modes"],
		L["Hides the damaged gear figure during camera modes."])
	durabilityCam:SetPoint("TOPLEFT", durability, "BOTTOMLEFT", QUEST_INDENT, -2)
	GreyUnless(durabilityCam, function(db) return db.durabilityShow end)

	AdoptTab(switch) -- (everything above onto the Settings tab)

	canvas:SetScript("OnShow", PageShown(function()
		Refresh()
		TabsShown()
	end, content))
	canvas:Hide()
	RegisterSubpage(canvas, L["Quest tracker"], L["Quest Tracker"])
end

-- Folder tabs inside a page, under anchor (its switch), as the Cooldown
-- Manager's and Swing Timer's: list { label, tip } each. Each tab's
-- settings go on a frame of its own (hosts[i]: build them there), one shown
-- at a time (1 by 1: one with no height draws none of it); search still
-- finds them, and a match opens their tab (ShowMatch's openSection). The tab
-- last picked is kept (SectionState, id). linksTab: the tab that's the
-- page's Addon Frame Links (groupKey's, FrameLinks.lua), made here on its
-- frame without its band; a jump to it from elsewhere opens the tab.
-- adoptTab: for a page built as before, straight on content: what's made on
-- content after this call goes onto that tab's frame once Adopt(oldAnchor)
-- is called at the page's end (what was placed under oldAnchor, the page's
-- switch, then sits at the tab's top), and again as the page shows (rows a
-- page makes later).
-- onPick(i): after a tab's picked, before the page's height is fitted.
-- hidden: the tabs not drawn, picked by Pick(i) from elsewhere (folder
-- tabs over the page's title: the Unit Frames page's), the hosts at once
-- under anchor.
-- Gives the hosts, Pick(i), Shown() for the page's OnShow, Adopt, the links
-- section (linksTab's), and the panel and tab frames (to hide the row).
-- (On ns: this file's main chunk is near Lua's 200 locals.)
function ns.PageTabsBelow(content, anchor, list, id, linksTab, groupKey, adoptTab, onPick, hidden)
	local picked = { id = id, open = 1 }
	local Pick
	local panel, tabFrames, ShowTab, base = ns.FolderTabs(content, list, function(i) Pick(i) end)
	base:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, hidden and 0 or -(ns.FOLDER_TAB_HEIGHT + 14))
	panel:SetPoint("TOPLEFT", base)
	panel:SetPoint("RIGHT", content, "RIGHT", -8, 0)
	panel:SetHeight(1) -- (just its top edge, a line under the tabs)
	if hidden then
		panel:Hide()
		for _, tab in ipairs(tabFrames) do
			tab:Hide()
			tab.Show = tab.Hide
		end
	end
	local hosts = {}
	for i = 1, #list do
		local host = CreateFrame("Frame", nil, content)
		host:SetSize(1, 1)
		host:SetPoint("TOPLEFT", base, "TOPLEFT", 0, -14)
		host.recordAs = content -- (its settings are the page's: its Reset puts them back)
		host.searchAlways = true
		host.openSection = function() Pick(i) end
		hosts[i] = host
	end
	local links
	if linksTab then
		links = ns.BuildLinkSection(content, hosts[linksTab], groupKey, true)
		links.frame:SetParent(hosts[linksTab])
		local open = links.body.openSection
		links.body.openSection = function()
			Pick(linksTab)
			open()
		end
		ns.RegisterLinkSection(groupKey, links.frame, links.body.openSection)
	end
	-- (What's on content now stays there: the title, the switch, the tabs.)
	local before = {}
	if adoptTab then
		for _, object in ipairs({ content:GetChildren() }) do before[object] = true end
		for _, object in ipairs({ content:GetRegions() }) do before[object] = true end
	end
	local function Adopt(oldAnchor)
		if not adoptTab then return end
		local host = hosts[adoptTab]
		for _, set in ipairs({ { content:GetChildren() }, { content:GetRegions() } }) do
			for _, object in ipairs(set) do
				-- (noAdopt: one that stays on the page, a popped preview's slot)
				if not before[object] and not object.noAdopt then
					before[object] = true
					object:SetParent(host)
					-- (Placed under the switch: at the tab's top instead, its
					-- other points as they were.)
					local points, moved = {}, false
					for n = 1, (oldAnchor and object:GetNumPoints() or 0) do
						points[n] = { object:GetPoint(n) }
						if points[n][2] == oldAnchor then moved = true end
					end
					if moved then
						object:ClearAllPoints()
						for _, point in ipairs(points) do
							if point[2] == oldAnchor then
								object:SetPoint(point[1], host, "TOPLEFT", point[4] or 0, 0)
							else
								object:SetPoint(point[1], point[2] or content, point[3], point[4], point[5])
							end
						end
					end
				end
			end
		end
	end
	function Pick(i)
		if not hosts[i] then i = 1 end
		SectionState.Save(picked, i)
		ShowTab(i)
		for n, host in ipairs(hosts) do host:SetShown(n == i) end
		if links and i == linksTab then links.Show() end
		if onPick then onPick(i) end
		FitContentHeight(content)
		C_Timer.After(0, function() FitContentHeight(content) end)
	end
	local function Shown()
		Adopt()
		SectionState.Restore(picked)
		Pick(tonumber(picked.open) or 1)
	end
	return hosts, Pick, Shown, Adopt, links, panel, tabFrames
end

-- Sub-page: the Visions hub's General (2026-11-16): every Vision as a card,
-- on or off, what it does (its page's intro, the first line) and its
-- pages as chips; the card opens it. Made again as it shows, the switches
-- as they are now. (On ns: this file's main chunk is near Lua's 200 locals.)
function ns.CreateVisionsGeneralPanel()
	-- (Card Vision's event pages open from its rows, not as tabs: no chips.)
	local VISION_CHIPS_SKIP = { ["Card Settings"] = true, ["Card Style"] = true, ["Card Sounds"] = true }
	local canvas, content = CreateScrollPage()
	local title = Label(content, "GameFontNormalLarge", L["Visions"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = PageIntro(content, title, L["Every Vision at a glance; click a card to open it."])
	-- (Its switch, 2026-11-16: every Vision page off with it, and back on.)
	PageSwitch(content, "visionsAll", L["Enable Page"], L["Turns all Visions on or off."], intro, function(value)
		ns.CascadeHub("Visions", "visionsAll", value and true or false)
		if content.RefillCards then content.RefillCards() end -- (its cards' dots as they are now)
	end)
	local cards
	local function Fill()
		if cards then cards:Hide() end
		-- (In the hub's sections, each under its name, as its icons are
		-- banded: Combat, World; any in none last, under Other. 2026-11-16.)
		local groups, bySection, entries = {}, {}
		for _, page in ipairs(ns.HubPageStates("Visions") or {}) do
			local key = page.section or "Other"
			entries = bySection[key]
			if not entries then
				entries = {}
				bySection[key] = entries
				groups[#groups + 1] = { L[key], entries, last = not page.section }
			end
			if page.name ~= "Visions General" and not page.dev then
				local chips = {}
				for _, tab in ipairs(ns.HubTabsOf("Visions", page.name)) do
					if not VISION_CHIPS_SKIP[tab[2]] then chips[#chips + 1] = tab end
				end
				local note = page.intro and page.intro:match("^(.-[%.%!%?])%s") or page.intro or ""
				entries[#entries + 1] = { label = page.label, texture = page.icon, open = page.name, tabs = chips,
					note = note }
				-- (Off too: "a and false or nil" gave nil, no dot, 2026-11-16.)
				if page.hasSwitch then entries[#entries].state = page.on and not page.held end
			end
		end
		table.sort(groups, function(a, b) return not a.last and b.last end)
		cards = ns.MakeHubCardGroups(content, groups, 600)
		cards:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
		FitContentHeight(content)
	end
	content.RefillCards = Fill
	canvas:SetScript("OnShow", PageShown(function()
		Refresh()
		Fill()
	end, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Visions General", L["General"])
end

-- Sub-page: the breath bar (the game's mirror timers: breath underwater,
-- fatigue in deep water, Feign Death): hiding it always, and its look
-- (MirrorTimerStyle.lua). The Timers icon's Breath Bar tab (2026-11-16: once
-- under the HUD page's Trackers rows); when it shows: its row on Show in.
-- (On ns: this file's main chunk is near Lua's 200 locals.)
function ns.CreateBreathBarPanel()
	local canvas, content = CreateScrollPage()
	local title = Label(content, "GameFontNormalLarge", L["Breath Bar"])
	local tabs = ns.PageTabs(content, ns.ShowInTabs("timers"), ns.ShowInIndex("timers", "Breath Bar"))
	title:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 8, -14)
	local intro = PageIntro(content, title, L["The breath bar and the game's other bars like it."])

	local function Apply()
		if ns.ApplyMirrorTimers then ns.ApplyMirrorTimers() end
		Refresh()
	end
	local function Shown(db) return not db.mirrorHide end
	local function Worded(db) return not db.mirrorHide and not db.mirrorHideText end
	local hide = Check(content, "mirrorHide", L["Hide the breath bar"],
		L["Hides the breath bar and the game's other bars like it."], function(value)
			ns.GetDB().mirrorHide = value
			Apply()
		end)
	hide:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -2, -14)
	local words = Check(content, "mirrorHideText", L["Hide its text"],
		L["Hides the word on the bar (Breath, Fatigue...), leaving the bar."], function(value)
			ns.GetDB().mirrorHideText = value
			Apply()
		end)
	words:SetPoint("TOPLEFT", hide, "BOTTOMLEFT", 0, 0)
	GreyUnless(words, Shown)
	local last = words
	-- (A dropdown with its name before it; nil where the client has no menus.)
	local function Pick(label, key, choices, tip, test)
		local dropdown = Dropdown(content, key, choices, 180, Apply)
		if not dropdown then return end
		local name = Label(content, "GameFontHighlight", label)
		name:SetPoint("TOPLEFT", last, "BOTTOMLEFT", last == words and 4 or 0, -10)
		name:SetSize(90, 30)
		name:SetJustifyV("MIDDLE")
		dropdown:SetPoint("LEFT", name, "RIGHT", 4, 0)
		Tooltip(dropdown, tip)
		GreyUnless(dropdown, test)
		last = name
	end
	Pick(L["Bar texture:"], "mirrorTexture", function() return ns.StyleTextureChoices() end,
		L["The bar's fill texture."], Shown)
	Pick(L["Font:"], "mirrorFont", function() return ns.StyleFontChoices() end,
		L["The font of the word on the bar. (In Russian, Korean and Chinese it stays the game's.)"], Worded)
	local size = Slider(content, "mirrorTextScale", L["Text size"], 50, 200, 5, "%d%%", 100,
		function() if ns.ApplyMirrorTimers then ns.ApplyMirrorTimers() end end)
	size:SetPoint("TOPLEFT", last, "BOTTOMLEFT", last == words and 4 or 0, -22)
	Tooltip(size, L["The size of the word on the bar, against the game's."])
	GreyUnless(size, Worded)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Breath Bar")
end

-- Sub-page: Classic's swing timer bars: only the weapons in use, and the
-- off-hand's hidden. (Applies in CineMode and out.)
local function CreateSwingPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Swing Timer"])
	-- (The Timers icon's Swing Timer tab, 2026-11-16: its tabs over the title.)
	local timerTabs = ns.PageTabs(content, ns.ShowInTabs("timers"), ns.ShowInIndex("timers", "Swing timer"))
	title:SetPoint("TOPLEFT", timerTabs, "BOTTOMLEFT", 8, -14)

	local subtitle = PageIntro(content, title,
		L["Which swing timer bars show."])

	-- The page's master switch: off, everything below greys out and does
	-- nothing; the bars still fade as their Standard Frames row says.
	local handleCheck = PageSwitch(content, "handleSwing", L["Enable Page"],
		L["Turns this page's swing timer settings on or off."], subtitle)

	-- Two tabs: its settings, and Addon Frame Links.
	local hosts, _, TabsShown = ns.PageTabsBelow(content, handleCheck, {
		{ L["Settings"], L["Which bars show, and when they fade."] },
		{ L["Addon Reveal Link"], L["Which supported addon's frames stand in for the swing timer."] },
	}, "Swing timer/page", 2, "swing")
	local settings = hosts[1]

	local smart = Check(settings, "swingSmartShow", L["Only show the weapons you're using"],
		L["Shows only the bars for the weapons you're attacking with."])
	smart:SetPoint("TOPLEFT", settings, "TOPLEFT", 0, 0)
	smart:HookScript("OnClick", Refresh) -- grey out / enable the slider below

	local after = Slider(settings, "swingHideAfter", L["Fade out after the bar is done for"], 0, 30, 1, L["%d sec"])
	after:SetPoint("TOPLEFT", smart, "BOTTOMLEFT", 20, -24)
	Tooltip(after, L["How long a bar stays after you stop attacking."])
	GreyUnless(after, function(db) return db.handleSwing and db.swingSmartShow end)

	local offHand = Check(settings, "swingHideOffHand", L["Hide the off-hand bar"],
		L["Never show the off-hand swing timer, dual wielding or not."])
	offHand:SetPoint("TOPLEFT", after, "BOTTOMLEFT", -20, -16)

	-- (Per class: your current one's.)
	local className, class = UnitClass("player")
	local rangedTop = Check(settings, "swingRangedOnTop" .. class, L["Ranged bar on top for %s"]:format(className),
		L["Puts the ranged bar on top for this class."])
	rangedTop:SetPoint("TOPLEFT", offHand, "BOTTOMLEFT", 0, -2)

	canvas:SetScript("OnShow", PageShown(function()
		Refresh()
		TabsShown()
	end, content))
	canvas:Hide()
	RegisterSubpage(canvas, L["Swing timer"], L["Swing Timer"])
end

-- Sub-page: the Cooldown Manager (the game's, or Forever Enhanced Cooldown Manager).
local function CreateCooldownPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Cooldown Manager"])
	-- (The Timers icon's Cooldown Manager tab, 2026-11-16: its tabs over the title.)
	local timerTabs = ns.PageTabs(content, ns.ShowInTabs("timers"), ns.ShowInIndex("timers", "Cooldown Manager"))
	title:SetPoint("TOPLEFT", timerTabs, "BOTTOMLEFT", 8, -14)

	local subtitle = PageIntro(content, title,
		L["CineMode hides the Cooldown Manager: pick when it shows."])

	-- The page's master switch: off, everything below greys out and does
	-- nothing; the Cooldown Manager still fades as its Standard Frames row says.
	local handleCheck = PageSwitch(content, "handleCooldowns", L["Enable Page"],
		L["Turns this page's Cooldown Manager settings on or off."], subtitle)
	local function Handled() return ns.PageSetting("handleCooldowns") end

	-- The page's tabs (ns.PageTabsBelow): the spell icons and their
	-- situations (CDM), the Cooldown Manager's other settings, and Addon Frame Links.
	local tabHosts, _, TabsShown = ns.PageTabsBelow(content, handleCheck, {
		{ L["CDM"], L["Each spell's icon: when it shows, and in which situations."] },
		{ L["Settings"], L["Staying up while a cooldown recharges, keybinds, numbers and the Flash style."] },
		{ L["Addon Reveal Link"], L["Which supported addon's frames stand in for the Cooldown Manager's bars."] },
	}, "Cooldown Manager/page", 3, "cooldowns")
	local icons, settings = tabHosts[1], tabHosts[2]

	-- Stay up while recharging, each bar's own (Essential's keys also count
	-- Enhanced Cooldown Manager's bars).
	local afterCombat = settings
	for i, bar in ipairs({
		{ prefix = "cooldown", label = L["Essential: stay up while a cooldown is recharging"],
			tip = L["Keeps the Cooldown Manager up until every Essential cooldown is ready."] },
		{ prefix = "cooldownUtility", label = L["Utility: stay up while a cooldown is recharging"],
			tip = L["Keeps the Cooldown Manager up until every Utility cooldown is ready."] },
	}) do
		local whileKey = bar.prefix .. "WhileRecharging"
		local recharging = Check(settings, whileKey, bar.label, bar.tip)
		recharging:SetPoint("TOPLEFT", afterCombat, i == 1 and "TOPLEFT" or "BOTTOMLEFT", i == 1 and 0 or -16,
			i == 1 and 0 or -2)
		recharging:HookScript("OnClick", Refresh) -- grey out / enable the option below
		GreyUnless(recharging, function(db) return db.handleCooldowns end)

		afterCombat = Check(settings, bar.prefix .. "AfterCombat", L["Only after combat"],
			L["Only keeps it up during the Calm Timer after a fight."])
		afterCombat:SetPoint("TOPLEFT", recharging, "BOTTOMLEFT", 16, -2)
		GreyUnless(afterCombat, function(db) return db.handleCooldowns and db[whileKey] end)
	end

	-- Each spell's key on its icon (Frames.lua: ns.ApplyCooldownKeybinds).
	local keybinds = Check(settings, "cooldownKeybinds", L["Show keybinds"],
		L["Shows each spell's keybind on its icon."])
	keybinds:SetPoint("TOPLEFT", afterCombat, "BOTTOMLEFT", -16, -8)
	keybinds:HookScript("OnClick", function() ns.ApplyCooldownKeybinds() end)
	GreyUnless(keybinds, function(db) return db.handleCooldowns end)
	-- Its icons' countdown numbers as the game's option says (Frames.lua: ns.ApplyCooldownNumbers).
	local numbers = Check(settings, "cooldownFollowNumbers", L["Numbers follow the game's Show Numbers for Cooldowns"],
		L["Shows cooldown numbers only when the game's Show Numbers for Cooldowns is on."])
	numbers:SetPoint("TOPLEFT", keybinds, "BOTTOMLEFT", 0, -2)
	numbers:HookScript("OnClick", function() ns.ApplyCooldownNumbers() end)
	GreyUnless(numbers, function(db) return db.handleCooldowns end)
	-- Icons the game turns into a buff show the spell instead (Frames.lua: ns.CooldownNoBuff).
	local notBuff = Check(settings, "cooldownSpellNotBuff", L["Use the spell's cooldown, not its buff"],
		L["Icons show the spell's own cooldown instead of its buff."])
	notBuff:SetPoint("TOPLEFT", numbers, "BOTTOMLEFT", 0, -2)
	GreyUnless(notBuff, function(db) return db.handleCooldowns end)
	-- Stack numbers on tracked buffs of known stacking spells (CooldownStacks.lua).
	local stacks = Check(settings, "cooldownStacks", L["Show stacks and time left on tracked buffs"],
		L["Shows stacks and time left on tracked buff icons."])
	stacks:SetPoint("TOPLEFT", notBuff, "BOTTOMLEFT", 0, -2)
	stacks:HookScript("OnClick", function() ns.ApplyCooldownStacks() end)
	GreyUnless(stacks, function(db) return db.handleCooldowns end)

	-- Each spell's icon: always shown (the game's own), only when ready in
	-- fights, or only while recharging. A row per spell in the Cooldown
	-- Manager's spell bars now, grouped by bar as in its settings, then any
	-- set that aren't in it.
	local readyHeader = Label(icons, "GameFontNormal", L["Spell icons"])
	readyHeader:SetPoint("TOPLEFT", icons, "TOPLEFT", 2, 0)
	local readyNote = PageIntro(icons, readyHeader,
		L["Pick when each spell's icon shows; empty boxes mean %d%% of its cooldown."]:format(ns.READY_EARLY * 100))
	RecordKey(icons, "cooldownReadyOnly") -- (for the page's Reset)
	RecordKey(icons, "cooldownReadyEarly")
	RecordKey(icons, "cooldownEarlyOn")
	RecordKey(icons, "cooldownRechargeOnly")
	RecordKey(icons, "cooldownNeedsPower")
	RecordKey(icons, "cooldownReadyAnyTime")
	RecordKey(icons, "cooldownGroupDefaults")
	RecordKey(icons, "cooldownProcOnly")
	RecordKey(icons, "cooldownAlwaysShow")
	RecordKey(icons, "cooldownBuffMode")
	RecordKey(icons, "cooldownSmartDefaults")
	RecordKey(icons, "cooldownFlashReady")
	RecordKey(icons, "cooldownSituations")
	-- Columns: the spell, when it shows, (When ready only) its Resources, how
	-- early it's back and Out of fights, and Flash.
	-- (Narrower than before Out of fights came: all of it fits the page's width.)
	local MODE_X, POWER_X, EARLY_X, ANY_X, FLASH_X, ROW_HEIGHT = 180, 324, 384, 480, 556, 26
	local MODE_WIDTH, GROUP_HEIGHT, GROUP_WIDTH = 135, 36, 610
	-- Each group a tab of its own, in Heal Vision's folder look (ns.FolderTabs,
	-- made below), only those with spells now: the picked one's spells on the
	-- panel under them, the column headings at its top. The tab last picked
	-- is kept across reloads (SectionState, its id "Cooldown Manager/tab",
	-- open the group).
	local GROUP_ORDER = { "essential", "utility", "buffs", "bars", "other", "otherbuffs" }
	local picked = { id = "Cooldown Manager/tab", open = "essential" }
	-- (The panel's top left, under the tabs: placed once they're made.)
	local panelTop = CreateFrame("Frame", nil, icons)
	panelTop:SetSize(1, 1)
	local panel, groupTabs, ShowTab
	local spellHeading = Label(icons, "GameFontNormalSmall", L["Spell"])
	spellHeading:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12, -10)
	local modeHeading = Label(icons, "GameFontNormalSmall", L["Icon shows"])
	modeHeading:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12 + MODE_X, -10)
	local powerHeading = Label(icons, "GameFontNormalSmall", L["Resources"])
	powerHeading:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12 + POWER_X - 4, -10)
	local earlyHeading = Label(icons, "GameFontNormalSmall", L["Show early"] .. " (" .. L["sec"] .. ")")
	earlyHeading:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12 + EARLY_X, -10)
	local anyHeading = Label(icons, "GameFontNormalSmall", L["Out of fights"])
	anyHeading:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12 + ANY_X - 4, -10)
	local flashHeading = Label(icons, "GameFontNormalSmall", L["Flash"])
	flashHeading:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12 + FLASH_X - 4, -10)
	local noSpells = Label(icons, "GameFontDisable", L["Nothing in the Cooldown Manager right now."])
	-- (Where the spell list goes: placed under the Flash style, once it's made.)

	-- A heading over each bar's spells, as the Cooldown Manager's settings group them.
	local GROUP_NAMES = {
		essential = L["Essential Cooldowns"], utility = L["Utility Cooldowns"],
		buffs = L["Tracked Buffs"], bars = L["Tracked Bars"],
		other = L["Not in the Cooldown Manager now"], otherbuffs = L["Buffs not in the Cooldown Manager now"],
	}
	-- (Their tabs' names: the full name heads the panel.)
	local TAB_NAMES = {
		essential = L["Essential"], utility = L["Utility"], buffs = L["Buffs"], bars = L["Bars"],
		other = L["Other"], otherbuffs = L["Other buffs"],
	}
	-- The groups of tracked buffs and bars, with modes of their own (ns.CooldownBuffMode).
	local BUFF_GROUP = { buffs = true, bars = true, otherbuffs = true }
	-- A spell's mode: "always", "ready", "recharge" or "proc" (set on its own:
	-- db.cooldownAlwaysShow, ReadyOnly, RechargeOnly, ProcOnly; else its group's).
	local MODES = {
		{ value = "always", text = L["Always"] },
		{ value = "ready", text = L["When ready"] },
		{ value = "recharge", text = L["While recharging"] },
		{ value = "proc", text = L["When it procs"] },
	}
	local BUFF_MODES = {
		{ value = "always", text = L["Always"] },
		{ value = "combat", text = L["In combat"] },
		{ value = "quiet", text = L["Out of combat"] },
		{ value = "hidden", text = L["Hidden"] },
	}
	local groupOf, groupSpells = {}, {} -- spell ID -> its group; group -> its spells (as last listed)
	local buffGroupOf = {} -- (the same for tracked buffs and bars: a spell can be a cooldown and a buff)

	-- The situation the grid shows (CooldownSituations.lua's chips, made
	-- below): false for Default. Store: where its settings are kept, the
	-- profile's own for Default, else the situation's (the same tables).
	-- In a situation a row can also follow: "inherit", Same as group or Same
	-- as Default, not set there.
	local sits
	local function View() return sits and sits.View() or false end
	local function Store()
		local sit = View()
		return sit and sit.set or ns.GetDB()
	end

	-- Each group's settings (db.cooldownGroupDefaults[group]: mode, power,
	-- early = seconds or nil for the default share; a mode not set: the
	-- built-in one, ns.COOLDOWN_GROUP_MODES). A spell not set on its own
	-- follows its group; setting the group's mode puts every spell in it back
	-- to following it. A spell made When ready on its own starts with its
	-- group's Resources and Show early.
	local function GroupDefaults(group)
		local all = Store().cooldownGroupDefaults
		all[group] = all[group] or {}
		return all[group]
	end

	-- (A row following, in a situation: its group's there, or Default's, and
	-- what that is now.)
	local function ModeText(mode) return ns.COOLDOWN_MODE_TEXT[mode] or tostring(mode) end
	local function SameAs(fromGroup, mode)
		return (fromGroup and L["Group's (%s)"] or L["Default's (%s)"]):format(ModeText(mode))
	end

	local OWN_MODES = { ready = "cooldownReadyOnly", recharge = "cooldownRechargeOnly", proc = "cooldownProcOnly",
		always = "cooldownAlwaysShow" }
	local function ModeOf(spell)
		local sit = View()
		if sit then
			local mode, from = ns.CooldownSitSpellMode(sit, spell, groupOf[spell])
			return from == "spell" and mode or "inherit"
		end
		return (ns.CooldownSpellMode(spell, groupOf[spell], false))
	end
	-- (nil or "inherit": back to following its group)
	local function SetSpellMode(spell, mode)
		local store = Store()
		if mode == "inherit" then mode = nil end
		if mode == "ready" and not store.cooldownReadyOnly[spell] then
			-- (Newly When ready: as it was if it was When ready, else its
			-- group's Resources, Show early and Out of fights; the seconds box empty, the
			-- default share, unless the group says.)
			local group = groupOf[spell] or "other"
			local was, _, power, earlyOn, early, anyTime = ns.CooldownSpellMode(spell, group, View())
			if was ~= "ready" then
				earlyOn = true
				power, early, anyTime = select(2, ns.CooldownGroupSettings(group, View()))
			end
			store.cooldownEarlyOn[spell], store.cooldownReadyEarly[spell] = earlyOn and true or nil, early
			store.cooldownNeedsPower[spell] = power or nil
			store.cooldownReadyAnyTime[spell] = anyTime or nil
		end
		for value, key in pairs(OWN_MODES) do
			store[key][spell] = value == mode or nil
		end
	end
	-- A spell following its group's When ready gets its own (the same) before one part changes.
	local function OwnReady(spell)
		if not Store().cooldownReadyOnly[spell] then SetSpellMode(spell, "ready") end
	end

	-- What a row reads and sets, for a spell (key: its ID) or a group's
	-- settings (key: the group). Early returns the seconds box's text.
	local function EarlyText(earlyOn, seconds)
		if not earlyOn then return "0" end
		return seconds and tostring(seconds) or ""
	end
	local SPELL = {
		Mode = ModeOf,
		SetMode = SetSpellMode,
		Power = function(spell) return select(3, ns.CooldownSpellMode(spell, groupOf[spell], View())) end,
		SetPower = function(spell, value)
			OwnReady(spell)
			Store().cooldownNeedsPower[spell] = value or nil
		end,
		Early = function(spell)
			local _, _, _, earlyOn, seconds = ns.CooldownSpellMode(spell, groupOf[spell], View())
			return EarlyText(earlyOn, seconds)
		end,
		SetEarly = function(spell, seconds)
			OwnReady(spell)
			local store = Store()
			store.cooldownEarlyOn[spell], store.cooldownReadyEarly[spell] = true, seconds
		end,
		AnyTime = function(spell) return select(6, ns.CooldownSpellMode(spell, groupOf[spell], View())) end,
		SetAnyTime = function(spell, value)
			OwnReady(spell)
			Store().cooldownReadyAnyTime[spell] = value or nil
		end,
		Length = function(spell) return ns.CooldownLength(spell) end,
		Flash = function(spell) return ns.CooldownSpellFlash(spell, groupOf[spell], View()) end,
		SetFlash = function(spell, value) Store().cooldownFlashReady[spell] = value end,
		Inherit = function(spell)
			local sit, group = View(), groupOf[spell]
			local _, from = ns.CooldownSitSpellMode(sit, spell, group)
			return SameAs(from == "group", (ns.CooldownSpellMode(spell, group, sit)))
		end,
		modes = MODES,
		tip = L["When this spell's icon shows in the Cooldown Manager."],
	}
	local function GroupMode(group)
		local sit = View()
		if sit then return ns.CooldownSitGroup(sit, group) or "inherit" end
		return (ns.CooldownGroupSettings(group, false))
	end
	local function GroupInherit(group) return SameAs(false, (ns.CooldownGroupSettings(group, false))) end
	local GROUP = {
		Mode = GroupMode,
		SetMode = function(group, mode)
			GroupDefaults(group).mode = mode ~= "inherit" and mode or nil
			for _, spell in ipairs(groupSpells[group] or {}) do
				SetSpellMode(spell, nil)
			end
		end,
		Power = function(group) return GroupDefaults(group).power end,
		SetPower = function(group, value)
			GroupDefaults(group).power = value or nil
			for _, spell in ipairs(groupSpells[group] or {}) do
				if Store().cooldownReadyOnly[spell] then SPELL.SetPower(spell, value) end
			end
		end,
		Early = function(group) return EarlyText(true, GroupDefaults(group).early) end,
		SetEarly = function(group, seconds)
			GroupDefaults(group).early = seconds
			for _, spell in ipairs(groupSpells[group] or {}) do
				if Store().cooldownReadyOnly[spell] then SPELL.SetEarly(spell, seconds) end
			end
		end,
		AnyTime = function(group) return GroupDefaults(group).anyTime end,
		SetAnyTime = function(group, value)
			GroupDefaults(group).anyTime = value or nil
			for _, spell in ipairs(groupSpells[group] or {}) do
				if Store().cooldownReadyOnly[spell] then SPELL.SetAnyTime(spell, value) end
			end
		end,
		Length = function() return nil end,
		Flash = function(group) return ns.CooldownGroupFlash(group, View()) end,
		SetFlash = function(group, value)
			-- (Kept even when off: Smart set turns some groups' on until they're set.)
			GroupDefaults(group).flash = value and true or false
			for _, spell in ipairs(groupSpells[group] or {}) do
				Store().cooldownFlashReady[spell] = nil
			end
		end,
		Inherit = GroupInherit,
		modes = MODES,
		tip = L["Sets every spell in this group to this."],
	}
	-- A tracked buff or bar (db.cooldownBuffMode), and their groups' settings.
	-- (No Resources, Show early or Flash: those are for spells.)
	local function NoValue() return nil end
	local BUFF = {
		Mode = function(spell)
			local sit = View()
			if sit then
				local mode, from = ns.CooldownSitBuffMode(sit, spell, buffGroupOf[spell])
				return from == "spell" and mode or "inherit"
			end
			return (ns.CooldownBuffMode(spell, buffGroupOf[spell], false))
		end,
		SetMode = function(spell, mode) Store().cooldownBuffMode[spell] = mode ~= "inherit" and mode or nil end,
		Power = NoValue, SetPower = NoValue, Early = NoValue, SetEarly = NoValue, Length = NoValue,
		AnyTime = NoValue, SetAnyTime = NoValue,
		Inherit = function(spell)
			local sit, group = View(), buffGroupOf[spell]
			local _, from = ns.CooldownSitBuffMode(sit, spell, group)
			return SameAs(from == "group", (ns.CooldownBuffMode(spell, group, sit)))
		end,
		modes = BUFF_MODES,
		tip = L["When this buff's icon or bar shows."],
	}
	local BUFF_GROUP_ACCESS = {
		Mode = GroupMode,
		SetMode = function(group, mode)
			GroupDefaults(group).mode = mode ~= "inherit" and mode or nil
			for _, spell in ipairs(groupSpells[group] or {}) do
				Store().cooldownBuffMode[spell] = nil
			end
		end,
		Power = NoValue, SetPower = NoValue, Early = NoValue, SetEarly = NoValue, Length = NoValue,
		AnyTime = NoValue, SetAnyTime = NoValue,
		Inherit = GroupInherit,
		modes = BUFF_MODES,
		tip = L["Sets every buff in this group that you haven't set on its own."],
	}
	-- A row's choices: in a situation, following (Same as...) first.
	local function ModesFor(access, key)
		if not View() or key == nil then return access.modes end
		local list = { { value = "inherit", text = access.Inherit(key) } }
		for _, choice in ipairs(access.modes) do list[#list + 1] = choice end
		return list
	end

	local GetName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
	local GetIcon = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
	local rows, buffRows, groupRows = {}, {}, {}

	-- A row: a name, its mode (a dropdown, or on clients without the modern
	-- one a button stepping through them), and for When ready its Resources
	-- tick and seconds box. access: SPELL or GROUP; row.key what it's for.
	local function NewRow(access, font)
		local row = { access = access, font = font }
		row.name = Label(icons, font, "")
		row.name:SetWidth(MODE_X - 10)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)

		local function Pick(mode)
			if row.key == nil then return end
			access.SetMode(row.key, mode)
			Refresh() -- (a group's change shows on its spells' rows too)
		end
		local ok, dropdown = ns.MenuDropdown(icons)
		if ok and dropdown and dropdown.SetupMenu then
			dropdown:SetWidth(MODE_WIDTH)
			dropdown.searchSkip = true
			dropdown:SetupMenu(function(_, rootDescription)
				for _, choice in ipairs(ModesFor(access, row.key)) do
					rootDescription:CreateRadio(choice.text,
						function() return row.key ~= nil and access.Mode(row.key) == choice.value end,
						function() Pick(choice.value) end)
				end
			end)
			row.mode = dropdown
		else
			local button = ns.PanelButton(icons)
			button:SetSize(MODE_WIDTH, 22)
			button:SetScript("OnClick", function()
				local now = row.key ~= nil and access.Mode(row.key)
				local modes = ModesFor(access, row.key)
				for i, choice in ipairs(modes) do
					if choice.value == now then
						Pick(modes[i % #modes + 1].value)
						break
					end
				end
			end)
			row.mode = button
		end
		Tooltip(row.mode, access.tip)

		-- Resources (When ready only): ticked, ready also means you have the
		-- power to cast it (Maelstrom, mana...).
		local power = Check(icons, nil, "", L["The icon also waits until you have the resources to cast it."], function(value)
			if row.key ~= nil then
				access.SetPower(row.key, value)
				Refresh()
			end
		end)
		power.Refresh = function() end -- (set by its row's)
		power:SetPoint("LEFT", row.mode, "LEFT", POWER_X - MODE_X, 0)
		row.power = power

		-- Seconds before it's ready that it comes back: empty for the default,
		-- 0 for once it's ready. (Stored as before: Show early on or off, and
		-- its seconds.)
		local early = ns.SkinEditBox(CreateFrame("EditBox", nil, icons, "InputBoxTemplate"))
		early:SetSize(36, 20)
		early:SetAutoFocus(false)
		early:SetNumeric(true)
		early:SetMaxLetters(4)
		early:SetPoint("LEFT", row.mode, "LEFT", EARLY_X - MODE_X + 6, 0)
		Tooltip(early, L["Seconds before it's ready that the icon comes back; empty means %d%% of its cooldown."]:format(ns.READY_EARLY * 100))
		local function Save(self)
			self:ClearFocus()
			-- (Only when changed: a group's box left as it was doesn't reset its spells.)
			if row.key ~= nil and self:GetText() ~= access.Early(row.key) then
				access.SetEarly(row.key, tonumber(self:GetText()))
				Refresh()
			end
		end
		early:SetScript("OnEnterPressed", Save)
		early:SetScript("OnEditFocusLost", function(self)
			if self.saving then return end
			self.saving = true
			Save(self)
			self.saving = nil
		end)
		early:SetScript("OnEscapePressed", function(self)
			-- (Put back as it was: losing focus then saves nothing.)
			self:SetText(row.key ~= nil and access.Early(row.key) or "")
			self:ClearFocus()
		end)
		row.early = early
		-- (Empty: the default's seconds, greyed, in the box.)
		row.earlyText = early:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.earlyText:SetPoint("LEFT", early, "LEFT", 1, 0)
		early:HookScript("OnTextChanged", function(self)
			row.earlyText:SetShown(self:GetText() == "")
		end)

		-- Out of fights (When ready only): ticked, out of fights it shows once
		-- it's ready too, as in one, instead of fading.
		local anyTime = Check(icons, nil, "", L["Out of fights, the icon also shows once it's ready."], function(value)
			if row.key ~= nil then
				access.SetAnyTime(row.key, value)
				Refresh()
			end
		end)
		anyTime.Refresh = function() end -- (set by its row's)
		anyTime:SetPoint("LEFT", row.mode, "LEFT", ANY_X - MODE_X, 0)
		row.anyTime = anyTime

		-- Flash (any mode): its icon flashes for a few seconds as its cooldown
		-- ends, shown for it even if its mode has it faded.
		if access.SetFlash then
			local flash = Check(icons, nil, "", L["Flashes the icon for a few seconds when the spell's " ..
				"cooldown ends."], function(value)
				if row.key ~= nil then
					access.SetFlash(row.key, value)
					Refresh()
				end
			end)
			flash.Refresh = function() end -- (set by its row's)
			flash:SetPoint("LEFT", row.mode, "LEFT", FLASH_X - MODE_X, 0)
			row.flash = flash
		end

		-- (The page's Refresh greys the mode with the page switch, after this.)
		row.mode.Refresh = function(self)
			local key = row.key
			if self.GenerateMenu then
				self:GenerateMenu()
			end
			if key == nil then return end
			local mode = access.Mode(key)
			if not self.SetupMenu then
				for _, choice in ipairs(ModesFor(access, key)) do
					if choice.value == mode then self:SetText(choice.text) end
				end
			end
			local handled = Handled()
			SetLabelFont(row.name, handled and row.font or "GameFontDisable")
			local ready = mode == "ready" and row.shown
			if row.flash then
				row.flash:SetShown(row.shown)
				row.flash:SetChecked(access.Flash(key) and true or false)
				row.flash:SetEnabled(handled)
			end
			row.early:SetShown(ready)
			row.power:SetShown(ready)
			row.anyTime:SetShown(ready)
			if not ready then return end
			row.power:SetChecked(access.Power(key) and true or false)
			row.power:SetEnabled(handled)
			row.anyTime:SetChecked(access.AnyTime(key) and true or false)
			row.anyTime:SetEnabled(handled)
			local text = access.Early(key)
			if not row.early:HasFocus() then
				row.early:SetText(text)
			end
			local length = access.Length(key)
			row.earlyText:SetText(length and tostring(math.floor(length * ns.READY_EARLY + 0.5))
				or ("%d%%"):format(ns.READY_EARLY * 100))
			row.earlyText:SetShown(row.early:GetText() == "")
			row.early:SetEnabled(handled)
			row.early:SetAlpha(handled and 1 or 0.5)
		end
		controls[#controls + 1] = row.mode
		return row
	end

	-- Puts a row at y (below the column headings) and shows it (its name x across).
	local function PlaceRow(row, key, text, y, x)
		row.key, row.shown = key, true
		row.name:ClearAllPoints()
		row.name:SetPoint("TOPLEFT", spellHeading, "BOTTOMLEFT", x or 0, y - 5)
		row.mode:ClearAllPoints()
		row.mode:SetPoint("TOPLEFT", spellHeading, "BOTTOMLEFT", MODE_X, y)
		row.name:SetText(text)
		row.name:Show()
		row.mode:Show()
	end

	local function HideRow(row)
		row.key, row.shown = nil, false
		row.name:Hide()
		row.mode:Hide()
		row.early:Hide()
		row.earlyText:Hide()
		row.power:Hide()
		row.anyTime:Hide()
		if row.flash then row.flash:Hide() end
		if row.line then row.line:Hide() end
		if row.center then row.center:Hide() end
	end

	-- A group's heading row: its name in gold, its defaults beside it, and a
	-- rule under it across the columns; for a bar, its Close the gaps under
	-- that (db.cooldownGroupDefaults[group].center; not set: ns.COOLDOWN_GROUP_CENTER).
	local ListSpells
	local function GroupRow(group)
		if not groupRows[group] then
			local row = NewRow(BUFF_GROUP[group] and BUFF_GROUP_ACCESS or GROUP, "GameFontNormal")
			row.line = icons:CreateTexture(nil, "ARTWORK")
			row.line:SetColorTexture(1, 0.82, 0, 0.4)
			row.line:SetSize(GROUP_WIDTH, 1)
			if group ~= "other" and (not BUFF_GROUP[group] or group == "buffs") then
				row.center = Check(icons, nil, L["Close the gaps (centered)"], group == "buffs"
					and L["Closes the gaps so the shown buffs sit centered."]
					or L["Closes the gaps so the shown icons sit centered."], function(value)
					-- (Default's alone: where the icons sit is the bar's, in every situation.)
					local all = ns.GetDB().cooldownGroupDefaults
					all[group] = all[group] or {}
					all[group].center = value -- (false kept: Utility's is on until set)
				end)
				row.center.Refresh = function(self)
					self:SetChecked(ns.CooldownGroupCentered(group))
				end
			end
			groupRows[group] = row
		end
		return groupRows[group]
	end

	-- Every group's spells, then those set on their own that aren't in the
	-- Cooldown Manager now (spells, then buffs).
	function ListSpells()
		local db, store = ns.GetDB(), Store()
		local list = ns.CooldownManagerSpells()
		local listed = { spell = {}, buff = {} }
		for _, spell in ipairs(list) do
			listed[BUFF_GROUP[spell.group] and "buff" or "spell"][spell.id] = true
		end
		for _, set in ipairs({
			{ "other", "spell", { db.cooldownReadyOnly, db.cooldownRechargeOnly, db.cooldownProcOnly,
				store.cooldownReadyOnly, store.cooldownRechargeOnly, store.cooldownProcOnly, store.cooldownAlwaysShow } },
			{ "otherbuffs", "buff", { db.cooldownBuffMode, store.cooldownBuffMode } },
		}) do
			local group, seen, missing = set[1], listed[set[2]], {}
			for _, own in ipairs(set[3]) do
				for id in pairs(own) do
					if not seen[id] then
						seen[id] = true
						missing[#missing + 1] = id
					end
				end
			end
			table.sort(missing)
			for _, id in ipairs(missing) do list[#list + 1] = { id = id, group = group } end
		end
		wipe(groupOf)
		wipe(buffGroupOf)
		wipe(groupSpells)
		for _, row in pairs(groupRows) do HideRow(row) end
		for _, spell in ipairs(list) do
			local id, group = spell.id, spell.group
			if BUFF_GROUP[group] then buffGroupOf[id] = group else groupOf[id] = group end
			groupSpells[group] = groupSpells[group] or {}
			table.insert(groupSpells[group], id)
		end
		-- The tabs of the groups with spells; the picked one's, or the first.
		SectionState.Restore(picked)
		local shown
		for i, group in ipairs(GROUP_ORDER) do
			local has = groupSpells[group] ~= nil
			groupTabs[i]:SetShown(has)
			if has and (not shown or group == picked.open) then shown = i end
		end
		local group = shown and GROUP_ORDER[shown]
		local y = -2
		local used = { [rows] = 0, [buffRows] = 0 }
		if group then
			ShowTab(shown)
			local row = GroupRow(group)
			PlaceRow(row, group, GROUP_NAMES[group], y - 4)
			row.line:ClearAllPoints()
			row.line:SetPoint("TOPLEFT", spellHeading, "BOTTOMLEFT", 0, y - 30)
			row.line:Show()
			y = y - GROUP_HEIGHT
			if row.center then
				row.center:ClearAllPoints()
				row.center:SetPoint("TOPLEFT", spellHeading, "BOTTOMLEFT", -4, y + 2)
				row.center:Show()
				y = y - ROW_HEIGHT
			end
			local isBuff = BUFF_GROUP[group]
			for _, id in ipairs(groupSpells[group]) do
				local pool = isBuff and buffRows or rows
				used[pool] = used[pool] + 1
				local spellRow = pool[used[pool]] or NewRow(isBuff and BUFF or SPELL, "GameFontHighlight")
				pool[used[pool]] = spellRow
				local okName, name = pcall(GetName, id)
				local okIcon, icon = pcall(GetIcon, id)
				PlaceRow(spellRow, id, ("|T%s:16|t %s"):format(okIcon and icon or 134400,
					okName and name or L["Spell %d"]:format(id)), y)
				y = y - ROW_HEIGHT
			end
		end
		for pool, count in pairs(used) do
			for i = count + 1, #pool do
				HideRow(pool[i])
			end
		end
		-- (The panel down past the last row: its headings' 10 and theirs, the rows, 12 under.)
		panel:SetHeight(10 + spellHeading:GetStringHeight() - y + 12)
		panel:SetShown(group ~= nil)
		noSpells:SetShown(group == nil)
		spellHeading:SetShown(group ~= nil)
		modeHeading:SetShown(group ~= nil)
		earlyHeading:SetShown(group ~= nil)
		powerHeading:SetShown(group ~= nil)
		anyHeading:SetShown(group ~= nil)
		flashHeading:SetShown(group ~= nil and not BUFF_GROUP[group])
	end
	-- The tabs (their full names their tips).
	local tabList = {}
	for i, group in ipairs(GROUP_ORDER) do tabList[i] = { TAB_NAMES[group], GROUP_NAMES[group] } end
	local base, height
	panel, groupTabs, ShowTab, base, height = ns.FolderTabs(icons, tabList, function(i)
		SectionState.Save(picked, GROUP_ORDER[i])
		ListSpells()
		Refresh()
		FitContentHeight(content)
	end, nil, GROUP_WIDTH + 8)
	-- (Under Smart set and the Flash style: placed below, once they're made.)
	panel:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
	panel:SetWidth(FLASH_X + 64) -- (room for Flash's tick)
	base:SetPoint("TOPLEFT", panelTop, "TOPLEFT")

	-- Smart set (db.cooldownSmartDefaults): until you set a bar's mode, its
	-- spells with no cooldown that you haven't set yourself go by what they
	-- cost (ns.SmartCooldownMode): When ready with Resources for a resource you
	-- build up (Maelstrom), When it procs for the rest. Off: by their group's
	-- setting.
	local smartSet = Check(icons, "cooldownSmartDefaults", L["Smart set"],
		L["Sets spells you haven't set yourself based on what they cost."],
		function(value)
			KeyPut("cooldownSmartDefaults", value)
			ListSpells()
			Refresh()
		end)
	smartSet:SetPoint("TOPLEFT", readyNote, "BOTTOMLEFT", -2, -6)
	-- Reset: just the spell icons' settings (the page's Reset does the rest too).
	local SPELL_ICON_KEYS = { cooldownReadyOnly = true, cooldownReadyEarly = true, cooldownEarlyOn = true,
		cooldownRechargeOnly = true, cooldownNeedsPower = true, cooldownReadyAnyTime = true, cooldownGroupDefaults = true,
		cooldownProcOnly = true, cooldownAlwaysShow = true, cooldownBuffMode = true, cooldownSmartDefaults = true,
		cooldownFlashReady = true, cooldownSituations = true }
	local iconsReset = ns.PanelButton(icons)
	iconsReset:SetSize(60, 20)
	iconsReset:SetPoint("LEFT", smartSet.Text or smartSet.text or smartSet, "RIGHT", 16, 0)
	iconsReset:SetText(L["Reset"])
	iconsReset.searchSkip = true
	Tooltip(iconsReset, L["Resets every icon setting to the active profile's."])
	iconsReset:SetScript("OnClick", function()
		StaticPopup_Show("CINEMATIC_RESET_PART", nil, nil, { icons = icons, keys = SPELL_ICON_KEYS,
			after = function()
				ListSpells()
				Refresh()
			end })
	end)

	-- The Flash style, for every spell with Flash ticked (Frames.lua): a
	-- glow, the icon growing with each beat, a colored border, and how long.
	local flashLabel = Label(settings, "GameFontHighlight", L["Flash style:"])
	flashLabel:SetPoint("TOPLEFT", stacks, "BOTTOMLEFT", 2, -18)
	local flashGlow = Check(settings, "cooldownFlashGlow", L["Glow"],
		L["The icon glows bright and dim while it flashes."])
	flashGlow:SetPoint("LEFT", flashLabel, "RIGHT", 8, 0)
	local flashGrow = Check(settings, "cooldownFlashGrow", L["Grow"],
		L["The icon grows a little and back with each beat while it flashes."])
	flashGrow:SetPoint("LEFT", flashGlow.Text or flashGlow.text or flashGlow, "RIGHT", 12, 0)
	local flashBorder = Check(settings, "cooldownFlashBorder", L["Border"],
		L["A border in the color beside it around the icon while it flashes."])
	flashBorder:SetPoint("LEFT", flashGrow.Text or flashGrow.text or flashGrow, "RIGHT", 12, 0)
	local flashSwatch = CreateFrame("Button", nil, settings)
	flashSwatch:SetSize(20, 20)
	flashSwatch:SetPoint("LEFT", flashBorder.Text or flashBorder.text or flashBorder, "RIGHT", 6, 0)
	local swatchEdge = flashSwatch:CreateTexture(nil, "BACKGROUND")
	swatchEdge:SetAllPoints()
	swatchEdge:SetColorTexture(0.6, 0.6, 0.6, 1)
	local swatchColor = flashSwatch:CreateTexture(nil, "ARTWORK")
	swatchColor:SetPoint("TOPLEFT", 2, -2)
	swatchColor:SetPoint("BOTTOMRIGHT", -2, 2)
	Tooltip(flashSwatch, L["Click to choose the flash's border color."])
	RecordKey(content, "cooldownFlashR")
	RecordKey(content, "cooldownFlashG")
	RecordKey(content, "cooldownFlashB")
	flashSwatch.Refresh = function()
		local db = ns.GetDB()
		swatchColor:SetColorTexture(db.cooldownFlashR, db.cooldownFlashG, db.cooldownFlashB, 1)
	end
	flashSwatch:SetScript("OnClick", function()
		local db = ns.GetDB()
		OpenColorPicker(db.cooldownFlashR, db.cooldownFlashG, db.cooldownFlashB, function(r, g, b)
			db.cooldownFlashR, db.cooldownFlashG, db.cooldownFlashB = r, g, b
			flashSwatch.Refresh()
		end)
	end)
	controls[#controls + 1] = flashSwatch
	local flashTest = ns.PanelButton(settings)
	flashTest:SetSize(60, 20)
	flashTest:SetPoint("LEFT", flashSwatch, "RIGHT", 16, 0)
	flashTest:SetText(L["Test"])
	flashTest.searchSkip = true
	Tooltip(flashTest, L["Flashes every icon in the Essential and Utility bars once, in this style."])
	flashTest:SetScript("OnClick", function() ns.TestCooldownFlash() end)
	local flashTime = Slider(settings, "cooldownFlashTime", L["Flash for"], 1, 6, 0.5,
		function(value) return L["%.1f sec"]:format(value) end)
	flashTime:SetPoint("TOPLEFT", flashLabel, "BOTTOMLEFT", 0, -28)
	Tooltip(flashTime, L["How long the icon flashes once its cooldown ends."])
	for _, control in ipairs({ flashGlow, flashGrow, flashBorder, flashTime }) do
		GreyUnless(control, function(db) return db.handleCooldowns end)
	end
	-- The situations (CooldownSituations.lua): Default and each of yours, the
	-- picked one's When under them; the spells' tabs show the picked one's settings.
	sits = ns.BuildCooldownSituations(icons, {
		width = GROUP_WIDTH,
		Tooltip = Tooltip,
		Enabled = function() return Handled() end,
		Changed = function()
			ListSpells()
			Refresh()
			FitContentHeight(content)
		end,
	})
	sits:SetPoint("TOPLEFT", smartSet, "BOTTOMLEFT", 2, -16)
	controls[#controls + 1] = sits
	panelTop:SetPoint("TOPLEFT", sits, "BOTTOMLEFT", 0, -12 - height)
	noSpells:SetPoint("TOPLEFT", sits, "BOTTOMLEFT", 0, -16)

	local shown = PageShown(Refresh, content)
	canvas:SetScript("OnShow", function()
		ListSpells()
		shown()
		TabsShown()
	end)
	canvas:Hide()
	RegisterSubpage(canvas, L["Cooldown Manager"])
end

-- Sub-pages: the visions, each a way of showing just what matters, in a hub
-- of their own, each with its own switch (no General page). Duel Vision: the
-- plates of two players dueling near you (see Effects). Roll Vision: a window
-- of the group's loot rolls (RollWindow.lua). Heal Vision: the party and raid frames show only who
-- needs healing (HealVisionFrames.lua). Quest Vision: what you still need for
-- your quests (QuestMobs.lua, QuestGlow.lua).
local function CreateVisionPanel()
	local canvas, content, title, note
	local stack -- (the pages below each start their own)

	-- Quest Vision: mobs and NPCs you still need for a quest objective (see
	-- QuestMobs): their plates kept up, a quest icon on them and on the target frame.
	canvas, content = CreateScrollPage()
	title = Label(content, "GameFontNormalLarge", L["Quest Vision"])
	ns.QuestTabs(content, title, 1)
	note = PageIntro(content, title,
		L["Highlights mobs, NPCs and objects you still need for a quest."])
	local function ApplyQuest()
		if ns.RefreshTargetQuestIcon then ns.RefreshTargetQuestIcon() end
		if ns.UpdateQuestGlow then ns.UpdateQuestGlow() end
		if ns.RefreshQuestItemButton then ns.RefreshQuestItemButton() end
	end
	-- (Its switch: questVision, its Enable before it had a page.)
	local questSwitch = PageSwitch(content, "questVision", L["Enable Page"],
		L["Turns Quest Vision on or off."], note, ApplyQuest)
	local questStack = Stack(questSwitch, "check")
	local function QuestPlatesOn(db) return db.handlePlates end
	-- Ticks, each its own setting (Unit frame: the target frame's quest icon).
	local QUEST_SHOWS = {
		{ key = "questMobsMark", text = L["Quest mark (!)"] },
		{ key = "questMobsPlate", text = L["Nameplate"] },
		{ key = "questMobsName", text = L["Name"] },
		{ key = "targetQuestIcon", text = L["Unit frame"] },
	}
	local function QuestShowTicked(key)
		if key == "targetQuestIcon" and ns.RefreshTargetQuestIcon then ns.RefreshTargetQuestIcon() end
		Refresh()
	end
	local QUEST_SHOWS_TIP = L["What shows of mobs and NPCs you still need for a quest."]
	questStack:Add(Label(content, "GameFontHighlight", L["Always show their"]), "label")
	local okMenu, questShows = ns.MenuDropdown(content)
	if okMenu and questShows and questShows.SetupMenu then
		questShows:SetWidth(200)
		questShows.searchSkip = true -- (it shows the current ticks, not a label)
		questShows:SetupMenu(function(_, root)
			for _, choice in ipairs(QUEST_SHOWS) do
				root:CreateCheckbox(choice.text,
					function()
						local db = ns.GetDB()
						return db ~= nil and db[choice.key] and true or false
					end,
					function()
						local db = ns.GetDB()
						db[choice.key] = not db[choice.key]
						QuestShowTicked(choice.key)
						return MenuResponse and MenuResponse.Refresh
					end)
			end
		end)
		if questShows.SetSelectionText then
			questShows:SetSelectionText(function()
				local db, ticked = ns.GetDB(), {}
				for _, choice in ipairs(QUEST_SHOWS) do
					if db and db[choice.key] then ticked[#ticked + 1] = choice.text end
				end
				return #ticked > 0 and table.concat(ticked, ", ") or L["No action"]
			end)
		end
		questShows.Refresh = function(self) self:GenerateMenu() end
		controls[#controls + 1] = questShows
		for _, choice in ipairs(QUEST_SHOWS) do RecordKey(content, choice.key) end
		questStack:Add(questShows, "dropdown")
		Tooltip(questShows, QUEST_SHOWS_TIP)
	else
		for _, choice in ipairs(QUEST_SHOWS) do
			local check = questStack:Add(Check(content, choice.key, choice.text, QUEST_SHOWS_TIP, function(value)
				ns.GetDB()[choice.key] = value
				QuestShowTicked(choice.key)
			end), "check")
			if choice.key ~= "targetQuestIcon" then GreyUnless(check, QuestPlatesOn) end
		end
	end
	local questIcon = Check(content, "plateAlwaysPartQuestIcon", L["Quest icon by their nameplates or names"],
		L["Shows a gold ! beside the nameplates of quest mobs and NPCs."])
	GreyUnless(questIcon, function(db) return db.handlePlates and not db.questMobsMark end)
	questStack:Add(questIcon, "check")
	questIcon:HookScript("OnClick", Refresh) -- (grey out / enable what needs it)
	-- (Indented under it, as its sub-option.)
	-- Questie's own quest icons, where ours would show too (Support/Questie.lua).
	-- Shown with Questie loaded only.
	if ns.AddOnWillLoad("Questie") and ns.AddonSupportOn("Questie") then
		local QUESTIE_ICONS = {
			{ value = "ours", text = L["Cinematic's wins"] },
			{ value = "questie", text = L["Questie's wins"] },
			{ value = "both", text = L["Both show"] },
		}
		local QUESTIE_ICONS_TIP = L["Which quest icon shows when both Cinematic and Questie mark the same unit."]
		local questieIcons = Dropdown(content, "questieIcons", QUESTIE_ICONS, 180, function()
			if ns.RefreshTargetQuestIcon then ns.RefreshTargetQuestIcon() end
			if ns.RefreshClassIcon and C_NamePlate and C_NamePlate.GetNamePlates then
				for _, plate in ipairs(C_NamePlate.GetNamePlates()) do ns.RefreshClassIcon(plate) end
			end
		end)
		if questieIcons then
			questStack:Add(Label(content, "GameFontHighlight", L["Questie's icons"]), "label", 16)
			questStack:Add(questieIcons, "dropdown", 16)
			Tooltip(questieIcons, QUESTIE_ICONS_TIP)
			GreyUnless(questieIcons, function(db)
				return db.targetQuestIcon or (db.handlePlates and (db.questMobsMark or db.plateAlwaysPartQuestIcon))
			end)
		end
	end
	-- The mark's icon, one for friendly NPCs and one for enemies: a button
	-- showing the icon picked, and on a click the icon browser (search and
	-- scroll, as for profile icons: IconBrowser.lua) with every quest, talk and
	-- cursor icon this client has (QuestMarkIcons.lua).
	questStack:Add(Label(content, "GameFontHighlight", L["Quest mark icon"]), "label")
	local markRow = CreateFrame("Frame", nil, content)
	markRow:SetSize(300, 30)
	local markSource = ns.QuestMarkIconSource
	local markBrowser = ns.IconBrowser(canvas, function(pickedKey, icon)
		ns.GetDB()[pickedKey] = icon
		if ns.RepaintQuestMarks then ns.RepaintQuestMarks() end
		Refresh()
	end, markSource)
	-- (What the marks show: the pick, or the ! where this client lacks it.)
	local function MarkShown(key)
		local db = ns.GetDB()
		local icon = db and db[key]
		return markSource.usable(icon) and icon or "questnormal"
	end
	local function MarkButton(key, text, tip, x)
		local button = CreateFrame("Button", nil, markRow)
		button:SetSize(30, 30)
		button:SetPoint("LEFT", x, 0)
		local edge = button:CreateTexture(nil, "BACKGROUND")
		edge:SetAllPoints()
		edge:SetColorTexture(0.45, 0.38, 0.2, 1)
		local back = button:CreateTexture(nil, "BORDER")
		back:SetPoint("TOPLEFT", 2, -2)
		back:SetPoint("BOTTOMRIGHT", -2, 2)
		back:SetColorTexture(0.05, 0.05, 0.05, 1)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetAllPoints(back)
		local hl = button:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(back)
		hl:SetColorTexture(1, 1, 1, 0.2)
		local name = Label(markRow, "GameFontHighlight", text)
		name:SetPoint("LEFT", button, "RIGHT", 8, 0)
		button:SetScript("OnClick", function(self)
			markBrowser:Open(self, key, MarkShown(key))
		end)
		Tooltip(button, tip)
		button.Refresh = function(self)
			local icon = MarkShown(key)
			if markSource.usable(icon) and markSource.atlas(icon) then
				self.icon:SetAtlas(icon)
			else
				self.icon:SetTexture(markSource.usable(icon) and icon or ns.QUEST_MOB_TEXTURE)
				self.icon:SetTexCoord(0, 1, 0, 1)
			end
		end
		controls[#controls + 1] = button
		RecordKey(content, key)
	end
	MarkButton("questMarkStyle", L["Friendly"],
		L["The quest mark on friendly NPCs; click to pick another."], 0)
	MarkButton("questMarkStyleEnemy", L["Enemy"],
		L["The quest mark on enemies; click to pick another."], 140)
	questStack:Add(markRow, "dropdown")
	local questItem = Check(content, "questItemButton", L["Quest item button"],
		L["A big button for the nearest tracked quest's usable item."]
		.. L[" Its look: the Quest Item Button tab."], function(value)
		ns.GetDB().questItemButton = value
		if ns.RefreshQuestItemButton then ns.RefreshQuestItemButton() end
	end)
	questStack:Add(questItem, "check")
	questItem:HookScript("OnClick", Refresh) -- (grey out / enable what needs it)
	-- (Indented under it, as its sub-option.)
	local itemFade = Check(content, "questItemFade", L["Fade if another addon competes"],
		L["Hides this button when another addon shows one for the same item."],
		function(value)
			ns.GetDB().questItemFade = value
			if ns.RefreshQuestItemButton then ns.RefreshQuestItemButton() end
		end)
	questStack:Add(itemFade, "check", 16)
	GreyUnless(itemFade, function(db) return db.questItemButton end)
	local questGlow = Check(content, "questObjectGlow", L["Glow on quest objects"],
		L["The quest object in front of you glows gold."],
		function(value)
			ns.GetDB().questObjectGlow = value
			if ns.UpdateQuestGlow then ns.UpdateQuestGlow() end
		end)
	questStack:Add(questGlow, "check")
	local hideObjectIcons = Check(content, "hideObjectIcons", L["Hide object icons"],
		L["Hides the game's icon on the object your interact key would use."],
		function(value)
			ns.GetDB().hideObjectIcons = value
			if ns.UpdateQuestGlow then ns.UpdateQuestGlow() end
		end)
	-- (Only where the game has object icons.)
	if GetCVar("SoftTargetIconGameObject") ~= nil then
		questStack:Add(hideObjectIcons, "check")
	else
		hideObjectIcons:Hide()
	end
	-- Talking to NPCs in speech bubbles (QuestTalk.lua).
	do
		local function ApplyTalk()
			if ns.RefreshQuestTalk then ns.RefreshQuestTalk() end
		end
		local function TalkOn(db) return db.questTalk end
		-- Talking heads played before closed at once (TalkingHeads.lua); only
		-- where the game has them.
		if C_TalkingHead then
			questStack:Header(content, L["Talking heads"])
			questStack:Add(Check(content, "talkingHeadRepeats", L["Hide repeated talking heads"],
				L["Closes talking heads you've already seen."]), "check")
		end
		questStack:Header(content, L["Talking to NPCs"])
		-- Quest talk itself (questTalk; off to start with in every
		-- profile). How it looks, the "Show the game's window" link and the
		-- number keys: the Quest talk tab (QuestTalkStyle.lua).
		local talk = questStack:Add(Check(content, "questTalk", L["Custom dialogue frames"],
			L["NPC dialogue shows in a speech bubble and reply list instead of the game's windows."] ..
			L[" Its look: the Dialogue tab."], function(value)
				ns.GetDB().questTalk = value
				ApplyTalk()
			end), "check")
		talk:HookScript("OnClick", Refresh) -- (grey out / enable what needs it)
		-- (Indented under it, as its sub-option.)
		local talkFade = Check(content, "questTalkFade", L["Fade if another addon competes"],
			L["Hides Cinematic's dialogue when another dialogue addon is running."])
		questStack:Add(talkFade, "check", 16)
		GreyUnless(talkFade, TalkOn)
		do
			-- (Ours take no controller input; the game's windows do.)
			local talkPad = Check(content, "questTalkPadGame", L["Game's window with a controller"],
				L["Uses the game's own dialogue windows in gamepad mode."], function(value)
					ns.GetDB().questTalkPadGame = value
					ApplyTalk()
				end)
			questStack:Add(talkPad, "check", 16)
			GreyUnless(talkPad, TalkOn)
		end
		-- Where they go (the bubble and list; with quest talk off, the game's windows).
		local PLACES = {
			{ value = "fixed", text = L["Default"] },
			{ value = "head", text = L["Over the head"], enabled = TalkOn },
			{ value = "opposite", text = L["Opposite clicked"] },
		}
		local PLACE_TIP = L["Where the speech bubble goes."]
		local placeLabel = questStack:Add(Label(content, "GameFontHighlight", L["Bubble position"]), "label")
		local place = Dropdown(content, "questTalkPlace", PLACES, 200, ApplyTalk)
		if place then
			questStack:Add(place, "dropdown")
			Tooltip(place, PLACE_TIP)
		else
			for _, choice in ipairs(PLACES) do
				local check = questStack:Add(Choice(content, "questTalkPlace", choice.value, choice.text, PLACE_TIP),
					"check")
				if choice.enabled then
					GreyUnless(check, choice.enabled)
				end
			end
		end
		-- The bubble position's own settings, in a column to its right: only
		-- those for the position picked show (Default has none).
		local column = CreateFrame("Frame", nil, content)
		column:SetSize(1, 1)
		column:SetPoint("TOPLEFT", placeLabel, "TOPLEFT", 260, 0)
		local byPlace = { head = {}, opposite = {} }
		local function Own(mode, control)
			byPlace[mode][#byPlace[mode] + 1] = control
			return control
		end
		-- Over the head.
		local headStack = Stack(column, "label")
		local topGapLine = Own("head", headStack:Add(BoxLine(content), "label"))
		GreyUnless(topGapLine:Box(L["Space above the bubble"], "questTalkTopGap", 0, 30, 1, "%d%%", 100,
			L["How far the bubble stays from the top of the screen."], ApplyTalk), TalkOn)
		local still = Own("head", headStack:Add(Check(content, "questTalkStill", L["Hold the camera still"],
			L["Stops the camera drifting while you talk."],
			function(value)
				ns.GetDB().questTalkStill = value
			end), "check"))
		GreyUnless(still, TalkOn)
		local TURNS = {
			{ value = "follow", text = L["Follow"] },
			{ value = "fade", text = L["Fade out"] },
			{ value = "dim", text = L["Dim"] },
			{ value = "wait", text = L["Wait to the side"] },
		}
		local TURN_TIP = L["What the bubble and card do while the camera moves."]
		Own("head", headStack:Add(Label(content, "GameFontHighlight", L["While the camera moves"]), "label"))
		local turning = Dropdown(content, "questTalkCamMove", TURNS, 200, ApplyTalk)
		if turning then
			Own("head", headStack:Add(turning, "dropdown"))
			Tooltip(turning, TURN_TIP)
			GreyUnless(turning, TalkOn)
		else
			for _, choice in ipairs(TURNS) do
				local check = Own("head", headStack:Add(Choice(content, "questTalkCamMove", choice.value, choice.text,
					TURN_TIP), "check"))
				GreyUnless(check, TalkOn)
			end
		end
		-- Opposite clicked (with or without Custom dialogue frames).
		local oppositeStack = Stack(column, "label")
		Own("opposite", oppositeStack:Add(Check(content, "questTalkShopFollow", L["Shop window goes there too"],
			L["The shop window opens where the talk was."]), "check"))
		-- (Shown as the position is: refreshed with the page, so picking
		-- another in the dropdown swaps them.)
		controls[#controls + 1] = {
			debugName = "bubble position's settings", owner = content,
			Refresh = function()
				local mode = ns.GetDB().questTalkPlace
				for each, list in pairs(byPlace) do
					for _, control in ipairs(list) do
						control:SetShown(each == mode)
					end
				end
			end,
		}
	end
	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Quest Vision")

	-- Roll Vision: a window of the group's loot rolls (RollWindow.lua). Only
	-- where the game has a loot history. (Its switch: rollWindow, its Enable
	-- before it had a page.)
	if ns.hasRollWindow then
		canvas, content = CreateScrollPage()
		title = Label(content, "GameFontNormalLarge", L["Roll Vision"])
		ns.RollTabs(content, title, 1)
		note = PageIntro(content, title,
			L["Shows group loot rolls in a window instead of only in chat."])
		local rollSwitch = PageSwitch(content, "rollWindow", L["Enable Page"],
			L["Turns Roll Vision on or off."], note, function() ns.RefreshRollWindow() end)
		stack = Stack(rollSwitch, "check")
		local function RollsOn(db) return db.rollWindow end
		-- Which items get a panel (the grid), then the window's general settings.
		stack:Header(content, L["Which items"])
		do
			-- A folder tab per group (Party/Dungeon: a party, in a dungeon or out;
			-- Raid), each a grid of rules per item quality: rows Uncommon (and
			-- below), Rare, Epic, Legendary (and up), columns each a tick or a
			-- number (roll<Rule><Group><Q>). A row's other cells grey out while
			-- its Show is off.
			local GROUPS = {
				{ key = "Party", text = L["Party/Dungeon"], max = 5,
					tip = L["The rules while you're in a party: in a dungeon, a delve or out in the world."] },
				{ key = "Raid", text = L["Raid"], max = 10, tip = L["The rules while you're in a raid group."] },
			}
			local ROWS = { { "Uncommon", 2 }, { "Rare", 3 }, { "Epic", 4 }, { "Legendary", 5 } }
			local COLUMNS = {
				{ key = "Show", text = L["Show"], choices = {
					{ value = "off", text = L["Off"], tip = L["No panel; rolls show only in chat."] },
					{ value = "winner", text = L["Winner"], tip = L["Shows a panel with the winner once the item's won."] },
					{ value = "all", text = L["All Rolls"], tip = L["A panel as the item drops: everyone's pick " ..
						"as they make it, the numbers, then the winner."] },
				},
					tip = L["Whether items of this quality get a panel in the window."] },
				{ key = "Usable", text = L["Usable"],
					tip = L["Only items you can use get a panel."] },
				{ key = "Best", text = L["Hide Uncounted"],
					tip = L["Hides Greed and Transmog rolls once someone rolls Need."] },
				{ key = "Max", text = L["Max Players"], box = true,
					tip = L["Each item lists at most this many players' rolls; click its panel to see everyone."] },
			}
			local NAME_W, COL_W, HEAD_H, ROW_H, PAD = 100, 110, 30, 26, 8
			local GRID_W, GRID_H = NAME_W + COL_W * #COLUMNS, HEAD_H + ROW_H * #ROWS
			local labels, grids = {}, {}
			local panel, _, ShowTab, base, tabsH
			local picked = IsInRaid and IsInRaid() and 2 or 1 -- (the group you're in, to start)
			local function Pick(i)
				picked = i
				for g, each in ipairs(grids) do each:SetShown(g == i) end
				if ShowTab then ShowTab(i) end
				Refresh() -- (the shown grid's cells, as their settings are)
			end
			for g, group in ipairs(GROUPS) do
				local grid = CreateFrame("Frame", nil, content)
				grid:SetSize(GRID_W, GRID_H)
				grid.openSection = function() Pick(g) end -- (a search match on it: its tab first)
				grids[g] = grid
				for c, column in ipairs(COLUMNS) do
					local head = Label(grid, "GameFontNormalSmall", column.text)
					head:SetWidth(COL_W - 6)
					head:SetJustifyH("CENTER")
					head:SetJustifyV("BOTTOM")
					head:SetPoint("BOTTOM", grid, "TOPLEFT", NAME_W + COL_W * (c - 0.5), -HEAD_H + 2)
					head.searchSkip = true -- (each cell carries the words: below)
					labels[#labels + 1] = head
				end
				for r, row in ipairs(ROWS) do
					local quality, y = row[1], -HEAD_H - ROW_H * (r - 0.5)
					local name = Label(grid, "GameFontHighlight", L[quality])
					name:SetPoint("LEFT", grid, "TOPLEFT", 4, y)
					name.qualityColor = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row[2]]
					name.searchSkip = true
					labels[#labels + 1] = name
					local showKey = "rollShow" .. group.key .. quality
					-- (Usable: any panel; Hide Uncounted and Max: only All Rolls lists players)
					local function RowShown(db) return RollsOn(db) and (db[showKey] or "off") ~= "off" end
					local function RowAll(db) return RollsOn(db) and db[showKey] == "all" end
					for c, column in ipairs(COLUMNS) do
						local key = "roll" .. column.key .. group.key .. quality
						local x = NAME_W + COL_W * (c - 0.5)
						local tip = group.text .. ", " .. L[quality] .. ": " .. column.tip
						local search = group.text .. " " .. L[quality] .. " " .. column.text
						local dropdown = column.choices
							and Dropdown(grid, key, column.choices, COL_W - 8, function() ns.RefreshRollWindow() end)
						if dropdown then
							dropdown:SetPoint("CENTER", grid, "TOPLEFT", x, y)
							Tooltip(dropdown, tip)
							RecordKey(content, key)
							GreyUnless(dropdown, RollsOn)
						elseif column.box then
							-- (a number: the page's box, alone on its line, centered in its cell)
							local line = BoxLine(grid)
							local box = line:Box("", key, 1, group.max, 1, "%d", 1, tip,
								function() ns.RefreshRollWindow() end)
							line:SetPoint("LEFT", grid, "TOPLEFT", x - 18, y)
							box.searchLabel = search
							RecordKey(content, key)
							GreyUnless(box, RowAll)
						else
							-- (Show on a client without the game's menus: a tick, All Rolls or Off)
							local show = column.key == "Show"
							local cb = Check(grid, key, "", tip, function(value)
								ns.GetDB()[key] = show and (value and "all" or "off") or value
								ns.RefreshRollWindow()
								if show then Refresh() end -- (its row's other cells grey or not)
							end)
							if show then
								local refresh = cb.Refresh
								cb.Refresh = function(self)
									refresh(self)
									self:SetChecked((ns.GetDB()[key] or "off") ~= "off")
								end
							end
							cb:SetPoint("CENTER", grid, "TOPLEFT", x, y)
							cb.searchLabel = search
							RecordKey(content, key)
							GreyUnless(cb, show and RollsOn
								or column.key == "Best" and RowAll or RowShown)
						end
					end
				end
			end
			-- The tabs over a panel holding the picked group's grid; a spacer in
			-- the stack as tall as both.
			local list = {}
			for g, group in ipairs(GROUPS) do list[g] = { group.text, group.tip } end
			panel, _, ShowTab, base, tabsH = ns.FolderTabs(content, list, Pick)
			local host = CreateFrame("Frame", nil, content)
			host:SetSize(GRID_W + PAD * 2, (tabsH or 24) + GRID_H + PAD * 2)
			stack:Add(host, "label")
			panel:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -(tabsH or 24))
			panel:SetSize(GRID_W + PAD * 2, GRID_H + PAD * 2)
			base:SetPoint("TOPLEFT", panel, "TOPLEFT")
			for _, grid in ipairs(grids) do grid:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD) end
			-- (The headers and quality names dim with the page's switch.)
			host.Refresh = function()
				local on = RollsOn(ns.GetDB())
				for _, label in ipairs(labels) do
					local color = label.qualityColor
					if color then label:SetTextColor(color.r, color.g, color.b) end
					label:SetAlpha(on and 1 or 0.5)
				end
			end
			host.pageSwitch = false -- (dims itself above)
			controls[#controls + 1] = host
			for g, grid in ipairs(grids) do grid:SetShown(g == picked) end
			ShowTab(picked)
		end
		stack:Header(content, L["General"])
		-- Where the window comes up (rollPlace).
		local PLACES = {
			{ value = "down", text = L["Down"] },
			{ value = "right", text = L["Right"] },
			{ value = "left", text = L["Left"] },
			{ value = "separate", text = L["Separate window"] },
		}
		local PLACE_TIP = L["Where the roll window shows: beside the game's roll frames or as its own window."]
		local function PlacePicked()
			ns.RefreshRollWindow()
			Refresh()
		end
		stack:Add(Label(content, "GameFontHighlight", L["Popup location"]), "label")
		local place = Dropdown(content, "rollPlace", PLACES, 200, PlacePicked)
		if place then
			stack:Add(place, "dropdown")
			Tooltip(place, PLACE_TIP)
			GreyUnless(place, RollsOn)
		else
			for _, choice in ipairs(PLACES) do
				local check = stack:Add(Check(content, "rollPlace", choice.text, PLACE_TIP, function()
					ns.GetDB().rollPlace = choice.value
					PlacePicked()
				end), "check")
				check.Refresh = function(self) self:SetChecked((ns.GetDB().rollPlace or "down") == choice.value) end
				GreyUnless(check, RollsOn)
			end
		end
		GreyUnless(stack:Add(BoxLine(content), "label"):Box(L["Items shown at once"], "rollMaxPanels", 1, 8, 1, "%d",
			1, L["How many items the window shows at once; the oldest goes when a new one drops."]), RollsOn)
		local ownRoll = stack:Add(Check(content, "rollShowSelf", L["Always show your roll"],
			L["Your own roll always shows on an item's panel."]), "check")
		GreyUnless(ownRoll, RollsOn)
		local alwaysNeed = stack:Add(Check(content, "rollAlwaysNeed", L["Always show rolls I need"],
			L["Items you roll Need on always show everyone's rolls."],
			function(value)
				ns.GetDB().rollAlwaysNeed = value
				ns.RefreshRollWindow()
			end), "check")
		GreyUnless(alwaysNeed, RollsOn)
		-- Show selected count: a tick each for Party/Dungeon and Raid
		-- (rollFooterParty, rollFooterRaid), in one dropdown.
		local FOOTERS = {
			{ key = "rollFooterParty", text = L["Party/Dungeon"] },
			{ key = "rollFooterRaid", text = L["Raid"] },
		}
		local FOOTER_TIP = L["Shows the extra lines under an item's players, like who passed, in a party, raid or both."]
		stack:Add(Label(content, "GameFontHighlight", L["Show selected count"]), "label")
		local okFooterMenu, footer = ns.MenuDropdown(content)
		if okFooterMenu and footer and footer.SetupMenu then
			footer:SetWidth(200)
			footer.searchSkip = true -- (it shows the current ticks, not a label)
			footer:SetupMenu(function(_, root)
				for _, choice in ipairs(FOOTERS) do
					root:CreateCheckbox(choice.text,
						function()
							local db = ns.GetDB()
							return db ~= nil and db[choice.key] and true or false
						end,
						function()
							local db = ns.GetDB()
							db[choice.key] = not db[choice.key]
							ns.RefreshRollWindow()
							return MenuResponse and MenuResponse.Refresh
						end)
				end
			end)
			if footer.SetSelectionText then
				footer:SetSelectionText(function()
					local db, ticked = ns.GetDB(), {}
					for _, choice in ipairs(FOOTERS) do
						if db and db[choice.key] then ticked[#ticked + 1] = choice.text end
					end
					return #ticked > 0 and table.concat(ticked, ", ") or L["Off"]
				end)
			end
			footer.Refresh = function(self) self:GenerateMenu() end
			controls[#controls + 1] = footer
			for _, choice in ipairs(FOOTERS) do RecordKey(content, choice.key) end
			stack:Add(footer, "dropdown")
			Tooltip(footer, FOOTER_TIP)
			GreyUnless(footer, RollsOn)
		else
			for _, choice in ipairs(FOOTERS) do
				local check = stack:Add(Check(content, choice.key, L["Show selected count"] .. ": " .. choice.text,
					FOOTER_TIP, function(value)
						ns.GetDB()[choice.key] = value
						ns.RefreshRollWindow()
					end), "check")
				GreyUnless(check, RollsOn)
			end
		end
		local rollFade = stack:Add(Check(content, "rollFade", L["Fade if another addon competes"],
			L["Stays hidden while another addon handles loot rolls."],
			function(value)
				ns.GetDB().rollFade = value
				ns.RefreshRollWindow()
			end), "check")
		GreyUnless(rollFade, RollsOn)
		canvas:SetScript("OnShow", PageShown(Refresh, content))
		canvas:Hide()
		RegisterSubpage(canvas, "Roll Vision")
	end

	-- Duel Vision: the plates of two players dueling near you (see Effects).
	-- (Its switch: duelPlates, its Enable before it had a page.)
	canvas, content = CreateScrollPage()
	title = Label(content, "GameFontNormalLarge", L["Duel Vision"])
	title:SetPoint("TOPLEFT", 16, -16)
	note = PageIntro(content, title,
		L["In CineMode, shows the nameplates of players dueling near you so you can watch."])
	local duelSwitch = PageSwitch(content, "duelPlates", L["Enable Page"],
		L["Turns Duel Vision on or off."], note)
	GreyUnless(duelSwitch, function(db) return db.handlePlates end)
	stack = Stack(duelSwitch, "check")
	local duelCC = stack:Add(Check(content, "duelCC", L["Crowd control"],
		L["Shows an icon beside a duelist's nameplate while they're crowd controlled."]), "check")
	GreyUnless(duelCC, function(db) return db.handlePlates and db.duelPlates end)
	local duelInstants = stack:Add(Check(content, "duelInstants", L["Instant spells"],
		L["Shows a duelist's instant spells as icons beside their nameplate."]), "check")
	GreyUnless(duelInstants, function(db) return db.handlePlates and db.duelPlates end)
	local duelInstantNames = stack:Add(Check(content, "duelInstantNames", L["Spell names"],
		L["The newest instant spell's name shows above its icon."]), "check")
	GreyUnless(duelInstantNames, function(db) return db.handlePlates and db.duelPlates and db.duelInstants end)
	local duelHide = stack:Add(Check(content, "duelHideOthers", L["Hide other duels while you duel"],
		L["Hides other players' duels while you're in one."]), "check")
	GreyUnless(duelHide, function(db) return db.handlePlates and db.duelPlates end)
	-- Test: pretend duels for 30 seconds (see Effects); Stop with the seconds
	-- left meanwhile (as the camera tests').
	local duelTest = ns.PanelButton(content)
	duelTest:SetSize(90, 22)
	duelTest:SetText(L["Test"])
	Tooltip(duelTest, L["Shows a 30-second pretend duel between nearby players so you can see how it looks."])
	duelTest:SetScript("OnClick", function()
		if ns.DuelTestLeft() then
			ns.ToggleDuelTest()
		else
			local _, why = ns.ToggleDuelTest(30)
			if why then
				ns.Print(L["Duel Vision test: not shown now (%s)."]:format(why))
			end
		end
	end)
	local duelWait = 0
	ns.SetOnUpdate(duelTest, function(self, elapsed)
		duelWait = duelWait - elapsed
		if duelWait > 0 then return end
		duelWait = 0.2
		local left = ns.DuelTestLeft()
		self:SetText(left and L["Stop (%d)"]:format(math.ceil(left)) or L["Test"])
	end)
	stack:Add(duelTest, "label")
	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Duel Vision")

	-- Heal Vision.
	canvas, content = CreateScrollPage()
	do
		local function Apply()
			if ns.ApplyHealVisionFrames then ns.ApplyHealVisionFrames() end
			Refresh() -- grey out / enable the rest
		end
		-- (The sliders: their values grey nothing out, and a full Refresh on
		-- every step of a drag lags.)
		local function ApplyFrames()
			if ns.ApplyHealVisionFrames then ns.ApplyHealVisionFrames() end
		end
		local function IfAny(db) return ns.HealVisionAny(db) end

		local healTitle = Label(content, "GameFontNormalLarge", L["Heal Vision"])
		healTitle:SetPoint("TOPLEFT", 16, -16)
		local healIntro = PageIntro(content, healTitle,
			L["Party and raid frames show only the members who need healing."])

		-- Show in: Always, then the places and groups (a Location dropdown).
		-- Always greys the rest.
		local PLACES = {
			World = { L["Open world"], L["out in the world, inns included (capital cities are Cities)"] },
			Cities = { L["Cities"], L["in capital cities"] },
			Dungeons = { L["Dungeons"], L["in dungeons and scenarios"] },
			Raids = { L["Raids"], L["in raids"] },
			BGs = { L["BGs & arenas"], L["in battlegrounds and arenas"] },
		}
		local COLUMNS = { { key = "", heading = L["Always"] } }
		local function Place(where)
			COLUMNS[#COLUMNS + 1] = { key = "In" .. where, heading = PLACES[where][1], where = where }
		end
		Place("World")
		Place("Cities")
		Place("BGs")
		COLUMNS[#COLUMNS + 1] = { key = "InParty", heading = L["Party"] }
		COLUMNS[#COLUMNS + 1] = { key = "InRaid", heading = L["Raid"] }
		Place("Dungeons")
		Place("Raids")
		local healSwitch = PageSwitch(content, "handleHealVision", L["Enable Page"],
			L["Turns Heal Vision on or off."], healIntro, ApplyFrames)

		-- The row as the Standard Frames page's (GridRows.lua): Always, a
		-- Location dropdown of the places and groups.
		local NAME_WIDTH = 90
		local LAYOUT = { edit = true }
		local gridTop = CreateFrame("Frame", nil, content)
		gridTop:SetSize(NAME_WIDTH + ns.GridWidth(LAYOUT), FRAME_HEADING_HEIGHT)
		-- (Up into the headings' empty top, as ShowTable's underHeader.)
		gridTop:SetPoint("TOPLEFT", healSwitch, "BOTTOMLEFT", 2, 6)
		ns.GridHeadings(ns.GRID_KIT, content, gridTop, NAME_WIDTH, LAYOUT)
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(gridTop:GetWidth(), 24)
		row:SetPoint("TOPLEFT", gridTop, "TOPLEFT", 0, -FRAME_HEADING_HEIGHT - 4)
		Label(row, "GameFontHighlight", L["Show in"]):SetPoint("LEFT", row, "LEFT", 0, 0)
		local function Set(key, value)
			ns.GetDB()[key] = value
			Apply()
		end
		local places = {}
		for c = 2, #COLUMNS do
			local column = COLUMNS[c]
			local key = "healVision" .. column.key
			RecordKey(content, key) -- (for the page's Reset)
			local tip = (column.where and L["Heal Vision %s."]:format(PLACES[column.where][2]))
				or (column.key == "InParty" and L["Heal Vision while you're in a party (not a raid), wherever you are."])
				or L["Heal Vision while you're in a raid, wherever you are."]
			places[#places + 1] = { column.heading, function() return ns.GetDB()[key] and true or false end,
				function() Set(key, not ns.GetDB()[key]) end, nil, tip }
		end
		RecordKey(content, "healVision")
		local function Item(name, key, itemTip, usable)
			RecordKey(content, key)
			return { name, function() return ns.GetDB()[key] and true or false end,
				function() Set(key, not ns.GetDB()[key]) end, usable, itemTip }
		end
		local combat = { Item(L["In combat"], "healVisionInCombat", L["Heal Vision in fights."]),
			{ L["Calm Timer"], function() return ns.GetDB().healVisionCalm and true or false end,
				function() Set("healVisionCalm", not ns.GetDB().healVisionCalm) end, nil,
				L["Heal Vision after a fight, until the Calm Timer (CineMode page) has run out."] } }
		RecordKey(content, "healVisionCalm")
		local targets = { Item(L["Enemy targeted"], "healVisionTargetEnemy",
				L["Heal Vision out of fights while you have a living enemy targeted."]),
			Item(L["Friend targeted"], "healVisionTargetFriendly",
				L["Heal Vision out of fights while you have anything else targeted."]) }
		ns.GridRow(ns.GRID_KIT, row, NAME_WIDTH, LAYOUT, {
			band = 1,
			always = { isOn = function() return ns.GetDB().healVision end,
				set = function(value) Set("healVision", value) end,
				tip = L["Heal Vision everywhere."] },
			menus = { [ns.GRID_COMBAT] = combat, [ns.GRID_TARGET] = targets, [ns.GRID_LOCATION] = places },
			help = { [ns.GRID_COMBAT] = L["On in fights, and with the Calm Timer, after them till it's run out."],
				[ns.GRID_TARGET] = L["On while you have one of these targeted, out of fights."],
				[ns.GRID_LOCATION] = L["On while you're in any of these (Party and Raid: in one, wherever you are)."] },
			rule = { key = function() return "healVision" end, label = function() return L["Heal Vision"] end,
				changed = Apply },
			-- (Its ticks as a rule, for the editor to start from. Party and Raid
			-- are both "group": no word tells a party from a raid group.)
			liveRule = function()
				local db, words, seen = ns.GetDB(), {}, {}
				if db.healVision then return "always" end
				local function Add(key, word)
					if db[key] and not seen[word] then
						seen[word] = true
						words[#words + 1] = word
					end
				end
				Add("healVisionInCombat", "combat")
				Add("healVisionCalm", "calm")
				Add("healVisionTargetEnemy", "enemy")
				Add("healVisionTargetFriendly", "friendly")
				Add("healVisionInWorld", "world")
				Add("healVisionInCities", "city")
				Add("healVisionInBGs", "bg")
				Add("healVisionInDungeons", "dungeon")
				Add("healVisionInRaids", "raid")
				Add("healVisionInParty", "group")
				Add("healVisionInRaid", "group")
				return #words > 0 and table.concat(words, " or ") or "never"
			end,
		}):SetPoint("LEFT", row, "LEFT", NAME_WIDTH, 0)

		-- Default, Tank, Healer and Damage tabs: the settings below are the
		-- Default tab's, or a role's (ns.HEAL_VISION_ROLE_KEYS, <key>_<ROLE>),
		-- used while you're that role once its "Same as the Default tab" is unticked.
		local editing -- (nil: the Default tab; else "TANK", "HEALER" or "DAMAGER")
		local function UsesDefault(db) return editing and not db["healVisionOwn_" .. editing] end
		local function Editable(db) return IfAny(db) and not UsesDefault(db) end
		-- (A setting's key as a getter and setter: the tab's own value, or the
		-- Default tab's, shown while the role uses it.)
		local function KeyOf(db, key)
			return (editing and not UsesDefault(db)) and key .. "_" .. editing or key
		end
		local function Field(key)
			for _, role in ipairs(ns.HEAL_VISION_ROLES) do RecordKey(content, key .. "_" .. role) end
			RecordKey(content, key)
			return { key = key, get = function() local db = ns.GetDB() return db[KeyOf(db, key)] end,
				set = function(value) ns.GetDB()[editing and key .. "_" .. editing or key] = value end }
		end
		local ROLE_NAMES = { TANK = L["Tank"], HEALER = L["Healer"], DAMAGER = L["Damage"] }
		local ROLE_TIPS = { TANK = L["Heal Vision's settings while you're a tank."],
			HEALER = L["Heal Vision's settings while you're a healer."],
			DAMAGER = L["Heal Vision's settings while you're dealing damage."] }
		-- (Then the Nameplates tab: not a role's, it holds the Nameplates and
		-- Names sections instead of the table. plates: it's the one showing.)
		local TABS = { false, "TANK", "HEALER", "DAMAGER", "PLATES" }
		local ROLE_ICONS = { TANK = "0:19:22:41", HEALER = "20:39:1:20", DAMAGER = "20:39:22:41" }
		local ownCheck, tabNote
		local plates = false
		local roleWidgets, plateWidgets = {}, {} -- (shown on the role tabs, or on the Nameplates tab)
		local ShowSection -- (below, once both sets are made)
		-- Folder tabs (ns.FolderTabs), a role's each after Default's.
		local TAB_H = ns.FOLDER_TAB_HEIGHT
		local NOTE_H = 20 -- (Current role, over the tabs)
		local list = {}
		for i, role in ipairs(TABS) do
			if role == "PLATES" then
				list[i] = { L["Nameplates"], L["Heal Vision on friendly nameplates."] }
			else
				list[i] = { role and ROLE_NAMES[role] or L["Default"], role and ROLE_TIPS[role]
					or L["The settings below for every role that uses the default settings."] }
			end
		end
		local panel, tabs, ShowTab, base = ns.FolderTabs(content, list, function(i)
			plates = TABS[i] == "PLATES"
			editing = (not plates and TABS[i]) or nil
			ShowSection()
			Refresh() -- (the tabs too: ownCheck's Refresh)
		end, 90)
		panel:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -14 - NOTE_H - TAB_H - 4)
		-- (On the row, not the panel: the panel's bottom hangs on the rows under them.)
		base:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -14 - NOTE_H - TAB_H - 4)
		local function ShowTabs()
			local db = ns.GetDB()
			if not db then return end
			local current = plates and "PLATES" or editing
			for i, role in ipairs(TABS) do
				if (role or nil) == current then ShowTab(i) end
			end
			ownCheck:SetShown(editing ~= nil)
			local role = ns.PlayerRole()
			tabNote:SetText(L["Current role:"] .. " " .. (ROLE_ICONS[role] and
				"|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:" .. ROLE_ICONS[role] .. "|t"
				or L["None"]))
		end
		tabNote = Label(content, "GameFontHighlight")
		tabNote:SetPoint("BOTTOMLEFT", tabs[1], "TOPLEFT", 4, 6)
		tabNote.searchSkip = true
		for _, role in ipairs(ns.HEAL_VISION_ROLES) do RecordKey(content, "healVisionOwn_" .. role) end
		-- Use default settings: unticked, the role goes by its own values (each kept while ticked).
		ownCheck = Check(content, false, L["Same as the Default tab"],
			L["Uses the Default tab's settings for this role."], function(value)
				ns.GetDB()["healVisionOwn_" .. editing] = not value
				Apply()
			end)
		ownCheck.noSettingId = true -- (each role tab's own: no one setting for /cine find)
		ownCheck.Refresh = function(self)
			self:SetChecked(editing and not ns.GetDB()["healVisionOwn_" .. editing] or false)
			ShowTabs()
		end
		ownCheck:SetPoint("TOPLEFT", tabs[1], "BOTTOMLEFT", -2, -10)
		GreyUnless(ownCheck, IfAny)
		-- (Holds the place under the tabs, the check shown or not.)
		local tabsEnd = CreateFrame("Frame", nil, content)
		tabsEnd:SetSize(1, 26)
		tabsEnd:SetPoint("TOPLEFT", tabs[1], "BOTTOMLEFT", 0, -10)

		local previous = tabsEnd
		local function Option(key, label, tip, enabled)
			local field = Field(key)
			local check = Check(content, key, label, tip, function(value)
				field.set(value)
				Apply()
			end)
			check.Refresh = function(self) self:SetChecked(field.get()) end
			check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previous == tabsEnd and -2 or 0, -2)
			GreyUnless(check, function(db) return Editable(db) and (not enabled or enabled(db)) end)
			previous = check
			roleWidgets[#roleWidgets + 1] = check
		end
		-- (Any debuff takes in the ones you can dispel: that box greys while it's ticked.)
		-- Off for now on both clients: they won't let addons see members'
		-- debuffs in fights (HealVisionFrames.lua's ShownAnyway).
		if ns.HEAL_VISION_DEBUFFS then
			Option("healVisionDispel", L["Show members with a debuff you can dispel"],
				L["A member with a debuff you can dispel shows, at full health too."],
				function(db) return not db[KeyOf(db, "healVisionAnyDebuff")] end)
			Option("healVisionAnyDebuff", L["Show members with any debuff"],
				L["A member with any debuff at all shows, at full health too."])
		end

		-- A table, a line each: tanks, healers and damage, then pets, with the
		-- health they show below (Always: every line; < 100%: any damage, saved 99.9%) and how
		-- faded they are while hidden (0: gone); neither goes past the other: one
		-- set past pushes the other along. Then your target, hidden no fainter
		-- than its box (100%: always shown), and the dead, offline and far away:
		-- always hidden (nothing to heal; far: 100% leaves them be), only how
		-- faded. Only your target goes before them (HealVisionFrames.lua's Rule).
		local ROLE_ICON = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:%s|t"
		local PET_ICON = "|TInterface\\Icons\\Ability_Hunter_BeastCall:16:16:0:0:64:64:5:59:5:59|t"
		local TARGET_ICON = "|TInterface\\Cursor\\Crosshairs:16:16|t"
		local OFFLINE_ICON = "|TInterface\\CharacterFrame\\Disconnect-Icon:16:16:0:0:64:64:12:52:12:52|t"
		local FAR_ICON = "|TInterface\\Icons\\INV_Misc_Spyglass_03:16:16:0:0:64:64:5:59:5:59|t"
		local MOUSE_ICON = "|TInterface\\Cursor\\Point:16:16|t"
		local SKULL_ICON = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:16:16|t"
		local NAME_W, COLUMN_W = 150, 200
		local function Percent(value, default)
			return math.floor((value or default) * 100 + 0.5)
		end
		local heads = CreateFrame("Frame", nil, content)
		heads:SetSize(NAME_W + 2 * COLUMN_W, 16)
		heads:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previous == tabsEnd and 0 or 2, -10)
		roleWidgets[#roleWidgets + 1] = heads
		for column, text in ipairs({ L["Show below health"], L["Opacity while hidden"] }) do
			local head = Label(heads, "GameFontNormal", text)
			head:SetPoint("LEFT", heads, "LEFT", NAME_W + (column - 1) * COLUMN_W, 0)
			head.searchSkip = true -- (each box has its own)
		end
		local lastRow = heads
		local function Row(icon, name, gap)
			local row = CreateFrame("Frame", nil, content)
			row:SetSize(NAME_W + 2 * COLUMN_W, 24)
			row:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -(gap or 2))
			local label = Label(row, "GameFontHighlight", icon .. " " .. name)
			label:SetPoint("LEFT")
			label.searchSkip = true
			lastRow = row
			roleWidgets[#roleWidgets + 1] = row
			return row
		end
		-- A box in a column (1: show below, 2: opacity); searchName: what search finds it by.
		local function Cell(row, column, field, searchName, tip, onChange)
			local line = BoxLine(row)
			line:SetPoint("LEFT", row, "LEFT", NAME_W + (column - 1) * COLUMN_W, 0)
			local box = line:Box("", field, 0, 100, 1, "%d%%", 100, tip, onChange or ApplyFrames)
			box.searchLabel = searchName
			GreyUnless(box, Editable)
			return box
		end
		local function Kind(icon, heading, belowKey, belowTip, alphaKey, alphaTip)
			local row = Row(icon, heading)
			local belowField, alphaField = Field(belowKey), Field(alphaKey)
			local below, alpha
			-- (< 50%, < 100%: any damage at all, saved as 99.9%; Off; Always: BoxLine's ShareBox.)
			local belowLine = BoxLine(row)
			belowLine:SetPoint("LEFT", row, "LEFT", NAME_W, 0)
			below = belowLine:ShareBox(belowField, belowTip, function(value)
				-- (Below the opacity: takes it down too.)
				if value < Percent(alphaField.get(), 0.25) then
					alphaField.set(value / 100)
					alpha:Refresh()
				end
				ApplyFrames()
			end, 0.999)
			below.searchLabel = heading .. ": " .. L["Show below health"]
			GreyUnless(below, Editable)
			alpha = Cell(row, 2, alphaField, heading .. ": " .. L["Opacity while hidden"], alphaTip, function(value)
				-- (Above the health: takes it up too.)
				if value > Percent(belowField.get(), 0.95) then
					belowField.set(value / 100)
					below:Refresh()
				end
				ApplyFrames()
			end)
		end
		Kind(ROLE_ICON:format("0:19:22:41"), L["Tanks"], "healVisionTankBelow",
			L["A tank shows once their health drops below this."],
			"healVisionTankAlpha", L["How much of a hidden tank still shows."])
		Kind(ROLE_ICON:format("20:39:1:20"), L["Healers"], "healVisionHealerBelow",
			L["A healer shows once their health drops below this."],
			"healVisionHealerAlpha", L["How much of a hidden healer still shows."])
		-- (Anyone without a tank's or healer's role goes by these, and the group titles' opacity.)
		Kind(ROLE_ICON:format("20:39:22:41"), L["Damage"], "healVisionShowBelow",
			L["A damage dealer shows once their health drops below this."],
			"healVisionMinAlpha", L["How much of a hidden damage dealer and the group titles still show."])
		Kind(PET_ICON, L["Pets"], "healVisionPetBelow",
			L["A pet shows once its health drops below this."],
			"healVisionPetAlpha", L["How much of a hidden pet still shows."])
		-- (One for every kind above: how much health over its line they fade in over.)
		Cell(Row("", L["Fade range"], 12), 1, Field("healVisionFadeRange"), L["Fade range"],
			L["Members fade in gradually as their health nears the line instead of popping in."])

		Cell(Row(TARGET_ICON, L["Your target, at least"], 12), 2, Field("healVisionTargetAlpha"),
			L["Target min opacity"], L["Your target always shows at least this much."])
		Cell(Row(MOUSE_ICON, L["Mouseover, at least"]), 2, Field("healVisionMouseoverAlpha"),
			L["Mouseover min opacity"], L["The member under your mouse shows at least this much; 0% turns it off."])
		Cell(Row(SKULL_ICON, L["Dead"], 12), 2, Field("healVisionDeadAlpha"), L["Dead opacity"],
			L["How much of dead members still shows."])
		Cell(Row(OFFLINE_ICON, L["Offline"]), 2, Field("healVisionOfflineAlpha"), L["Offline opacity"],
			L["How much of offline members still shows."])
		Cell(Row(FAR_ICON, L["Far away"]), 2, Field("healVisionFarAlpha"), L["Far away opacity"],
			L["How much of members out of your healing range still shows."])
		-- Ready check marks (HealVisionFrames.lua's ReadyMark): ticked, they
		-- show on hidden members too; unticked, they fade with their member.
		do
			local field = Field("healVisionReadyCheck")
			local row = Row("|TInterface\\RaidFrame\\ReadyCheck-Ready:16:16|t", L["Ready check"], 12)
			local check = Check(content, "healVisionReadyCheck", L["Show while hidden"],
				L["Shows ready check marks on hidden members too."], function(value)
					field.set(value)
					ApplyFrames()
				end)
			check.Refresh = function(self) self:SetChecked(field.get() and true or false) end
			check.searchLabel = L["Ready check"] .. ": " .. L["Show while hidden"]
			check:SetPoint("LEFT", row, "LEFT", NAME_W + COLUMN_W - 4, 0)
			GreyUnless(check, Editable)
			roleWidgets[#roleWidgets + 1] = check
		end
		-- The Nameplates tab, in the same panel: first Nameplates (friendly
		-- players' and minions' plates by the role tabs' table:
		-- HealVisionFrames.lua's plates), then Names (names drawn by their
		-- plates in CineMode show health: PlateParts.lua's Fill; idea and first
		-- code: pkecerski). Neither by the grid's places.
		local barsHead = Label(content, "GameFontNormal", L["Nameplates"])
		barsHead:SetPoint("TOPLEFT", tabsEnd, "TOPLEFT", 2, -4)
		local barsCheck = Check(content, "healVisionPlates", L["Health bars only while hurt"],
			L["Friendly nameplates show their health bar only while they need healing, outside dungeons and raids."], function(value)
				ns.GetDB().healVisionPlates = value
				if ns.ApplyHealVisionPlates then ns.ApplyHealVisionPlates() end
				Refresh() -- (Don't fade greys with it)
			end)
		barsCheck:SetPoint("TOPLEFT", barsHead, "BOTTOMLEFT", -2, -6)
		GreyUnless(barsCheck, function() return ns.PageSetting("handleHealVision") end)

		-- Don't fade: the parts that stay while the rest fades (a tick menu;
		-- healVisionPlatesKeep<part>, the name only to start with).
		local KEEP_NAMES = { Health = L["Health bar"], Name = L["Name"], CastBar = L["Cast bar"], Buffs = L["Buffs"],
			Debuffs = L["Debuffs"], RaidMarker = L["Raid marker"], Level = L["Level"],
			Highlight = L["Target highlight"], Widgets = L["Quest/widget icons"] }
		local keepLabel = Label(content, "GameFontHighlight", L["Don't fade:"])
		keepLabel:SetPoint("TOPLEFT", barsCheck, "BOTTOMLEFT", 26, -8)
		local keepButton = ns.GridMenuButton(content, 180)
		keepButton:SetPoint("LEFT", keepLabel, "RIGHT", 8, 0)
		local keepEntries = {}
		for _, part in ipairs(ns.HEAL_PLATE_PARTS or {}) do
			local key = "healVisionPlatesKeep" .. part
			RecordKey(content, key)
			keepEntries[#keepEntries + 1] = { KEEP_NAMES[part] or part,
				function() return ns.Setting(key) and true or false end,
				function() ns.GetDB()[key] = not ns.GetDB()[key] end }
		end
		keepButton.Refresh = function(self)
			local names = {}
			for _, entry in ipairs(keepEntries) do
				if entry[2]() then names[#names + 1] = entry[1] end
			end
			self:SetText(#names == 0 and "|cff808080-|r" or #names == 1 and names[1]
				or #names == #keepEntries and L["All"] or (L["%d of %d"]):format(#names, #keepEntries))
		end
		keepButton:SetScript("OnClick", function(self)
			ns.TickMenu(self, keepEntries, function()
				self:Refresh()
				if ns.ApplyHealVisionPlates then ns.ApplyHealVisionPlates() end
			end)
		end)
		Tooltip(keepButton, L["The parts of a nameplate that stay while the rest fades."])
		GreyUnless(keepButton, function(db) return ns.PageSetting("handleHealVision") and db.healVisionPlates end)
		controls[#controls + 1] = keepButton -- (refreshed with the page)
		keepLabel.searchSkip = true

		local namesHead = Label(content, "GameFontNormal", L["Names"])
		namesHead:SetPoint("TOPLEFT", keepLabel, "BOTTOMLEFT", -24, -18)
		local fillCheck = Check(content, "plateNameHealthFill", L["Health fill"],
			L["Names over heads show health like a bar, turning grey as the unit takes damage."], function(value)
				ns.GetDB().plateNameHealthFill = value
				if ns.RefreshPlateNameStyle then ns.RefreshPlateNameStyle() end
			end)
		fillCheck:SetPoint("TOPLEFT", namesHead, "BOTTOMLEFT", -2, -6)
		GreyUnless(fillCheck, function() return ns.PageSetting("handleHealVision") end)
		-- (Where neither can work, at the foot of the tab, under both: tested on
		-- retail in a follower dungeon, every friendly plate locked from addons;
		-- Forever locks them too. Names are drawn by those plates.)
		local lockedNote = Label(content, "GameFontDisableSmall",
			L["Nameplates and Names don't work in dungeons and raids: the game locks friendly nameplates from " ..
			"addons there. Heal Vision on your party and raid frames still works there."])
		lockedNote:SetPoint("TOPLEFT", fillCheck, "BOTTOMLEFT", 2, -14)
		lockedNote:SetWidth(NAME_W + 2 * COLUMN_W - 4)
		lockedNote:SetJustifyH("LEFT")
		lockedNote.searchSkip = true
		-- (The panel's bottom while this tab shows: as wide as the table.)
		local platesEnd = CreateFrame("Frame", nil, content)
		platesEnd:SetSize(NAME_W + 2 * COLUMN_W, 1)
		platesEnd:SetPoint("TOPLEFT", lockedNote, "BOTTOMLEFT", -2, 0)
		for _, widget in ipairs({ barsHead, barsCheck, keepLabel, keepButton, lockedNote, namesHead, fillCheck }) do
			plateWidgets[#plateWidgets + 1] = widget
		end

		-- One tab's set shown, the other's hidden, the panel round the shown one.
		function ShowSection()
			for _, widget in ipairs(roleWidgets) do widget:SetShown(not plates) end
			for _, widget in ipairs(plateWidgets) do widget:SetShown(plates) end
			panel:SetPoint("BOTTOMRIGHT", plates and platesEnd or lastRow, "BOTTOMRIGHT", 12, -12)
		end
		ShowSection()
	end

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Heal Vision")
end

-- Sub-page: tooltips. In CineMode, world tooltips and unit frames' hide by
-- kind out of combat, enemies, friendlies or everything else (the UI's too) in combat,
-- and all of them in the camera modes ticked.
local function CreateTooltipPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Tooltips"])
	-- (The Mouse icon's Tooltips tab, 2026-11-16: its tabs over the title.)
	local mouseTabs = ns.PageTabs(content, ns.ShowInTabs("mouse"), ns.ShowInIndex("mouse", "Tooltips"))
	title:SetPoint("TOPLEFT", mouseTabs, "BOTTOMLEFT", 8, -14)

	local note = PageIntro(content, title, L["Hold your Show hidden tooltips key to see a hidden tooltip in CineMode."])
	local switch = PageSwitch(content, "handleTooltips", L["Enable Page"],
		L["Turns tooltip hiding in CineMode on or off."], note)

	-- Fade in/out (tooltipFadeTime): only with the page switched on.
	local fade = Slider(content, "tooltipFadeTime", L["Fade in/out"], 0, 3, 0.1, function(value)
		return value <= 0 and L["Off"] or L["%.1f sec"]:format(value)
	end)
	fade:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 6, -30)
	Tooltip(fade, L["How long tooltips take to fade in and out."])

	-- Mouse still: hide when or until the mouse is still, and the seconds
	-- beside it (each choice keeps its own: tooltipHideStill or tooltipShowStill).
	local stillHeader = Label(content, "GameFontNormal", L["Mouse still"])
	stillHeader:SetPoint("TOPLEFT", fade, "BOTTOMLEFT", -4, -20)
	local STILL_TIP = L["Hides tooltips once the mouse is still, or shows them only once it's still."]
	local STILL_MODES = {
		{ value = "hide", text = L["Hide when the mouse is still"] },
		{ value = "show", text = L["Hide until the mouse is still"] },
		{ value = "off", text = L["Off"] },
	}
	local mode = Dropdown(content, "tooltipStillMode", STILL_MODES, 220)
	if mode then
		mode:SetPoint("TOPLEFT", stillHeader, "BOTTOMLEFT", 4, -6)
		Tooltip(mode, STILL_TIP)
	else
		local previousChoice = stillHeader
		for _, choice in ipairs(STILL_MODES) do
			local check = Choice(content, "tooltipStillMode", choice.value, choice.text, STILL_TIP)
			check:SetPoint("TOPLEFT", previousChoice, "BOTTOMLEFT", previousChoice == stillHeader and 2 or 0, -2)
			previousChoice = check
			mode = check
		end
	end
	local function StillKey()
		return ns.GetDB().tooltipStillMode == "show" and "tooltipShowStill" or "tooltipHideStill"
	end
	RecordKey(content, "tooltipHideStill")
	RecordKey(content, "tooltipShowStill")
	local still = Slider(content, {
		get = function() return ns.GetDB()[StillKey()] or 0 end,
		set = function(value) ns.GetDB()[StillKey()] = value end,
	}, "", 0, 30, 1, function(value)
		return value <= 0 and L["Off"] or L["%d sec"]:format(value)
	end)
	still:SetPoint("LEFT", mode, "RIGHT", 24, 0)
	Tooltip(still, STILL_TIP)
	GreyUnless(still, function(db) return db.tooltipStillMode ~= "off" end)

	-- A header, then what's under it (a grid or slider: lined up by sectionX).
	local previous = mode
	local function Section(text)
		local x = previous == mode and -4 or previous.sectionX or -10
		local header = Label(content, "GameFontNormal", text)
		header:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", x, previous == mode and -16 or -14)
		previous = header
		return header
	end

	-- A grid of rows ({ label, tip, keys = column -> setting, tips = column
	-- -> tip }) by columns ({ key, heading, enabled = function(db, row) for
	-- a column that greys }), like the Visual Effects page's, under anchor.
	-- Returns the last row and the column headings.
	local GRID_NAME_WIDTH, GRID_COLUMN_WIDTH = 230, 90
	local function Grid(anchor, rows, columns)
		local top = CreateFrame("Frame", nil, content)
		top:SetSize(GRID_NAME_WIDTH + GRID_COLUMN_WIDTH * #columns, 16)
		top:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
		local headings = {}
		for c, column in ipairs(columns) do
			local heading = Label(top, "GameFontNormalSmall", column.heading)
			heading:SetWidth(GRID_COLUMN_WIDTH)
			heading:SetJustifyH("CENTER")
			heading:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", GRID_NAME_WIDTH + GRID_COLUMN_WIDTH * (c - 1), 0)
			headings[column.key] = heading
		end
		local last = top
		for _, info in ipairs(rows) do
			local row = CreateFrame("Frame", nil, content)
			row:SetSize(top:GetWidth(), 24)
			row:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
			row.sectionX = 0
			Label(row, "GameFontHighlight", info[1]):SetPoint("LEFT", row, "LEFT", 0, 0)
			for c, column in ipairs(columns) do
				local key = info.keys[column.key]
				local check = Check(content, key, "", info[2] .. " " .. info.tips[column.key], function(value)
					ns.GetDB()[key] = value
					Refresh() -- grey out / enable the row's other boxes
				end)
				check:SetPoint("CENTER", row, "LEFT", GRID_NAME_WIDTH + GRID_COLUMN_WIDTH * (c - 0.5), 0)
				if column.enabled then
					GreyUnless(check, function(db) return column.enabled(db, info) end)
				end
			end
			last = row
		end
		previous = last
		return last, headings
	end

	-- Show tooltips: one row, as the Standard Frames page's (GridRows.lua):
	-- where and when tooltips show in CineMode. Its rule can tell them apart
	-- by kind (the editor's Tooltip line: tipenemy and the rest).
	local hideHeader = Section(L["Show tooltips"])
	PageIntro(content, hideHeader,
		L["Pick where and when tooltips show in CineMode."])
	local tooltipRows = { opts = { quiet = true, cam = true, anyFight = true }, underHeader = true,
		{ key = "tooltip:All", label = L["Tooltips"],
			tip = L["Every tooltip, in the world and on the UI."],
			alwaysKey = "tooltipAlways",
			alwaysOn = function() return ns.GetDB().tooltipAlways end,
			setAlways = function(value) ns.GetDB().tooltipAlways = value end,
			alwaysTip = L["Tooltips show all through CineMode. (The other columns then have nothing to add.)"] } }
	previous = ShowTable(content, hideHeader, tooltipRows, L["Tooltips"])
	previous.sectionX = 0

	-- Tooltip look: where tooltips show (tooltipCursorMode), how long until the After column, then a grid of
	-- the parts (rows) by when each shows: on first hover, and after
	-- tooltipFullAfter seconds (columns).
	local partsHeader = Section(L["Tooltip look"])
	local partsNote = PageIntro(content, partsHeader,
		L["Pick which parts of the tooltip show and when."])
	local CURSOR_TIP = L["Where tooltips show: their usual corner or by your mouse."]
	local CURSOR_MODES = {
		{ value = "corner", text = L["Default position"] },
		{ value = "cursor", text = L["At the mouse cursor"] },
		{ value = "combat", text = L["At the mouse cursor in combat"] },
	}
	local cursorMode = Dropdown(content, "tooltipCursorMode", CURSOR_MODES, 220)
	local lastCursor
	if cursorMode then
		cursorMode:SetPoint("TOPLEFT", partsNote, "BOTTOMLEFT", 4, -10)
		Tooltip(cursorMode, CURSOR_TIP)
		lastCursor = cursorMode
	else
		lastCursor = partsNote
		for _, choice in ipairs(CURSOR_MODES) do
			local check = Choice(content, "tooltipCursorMode", choice.value, choice.text, CURSOR_TIP)
			check:SetPoint("TOPLEFT", lastCursor, "BOTTOMLEFT", lastCursor == partsNote and 2 or 0, -2)
			lastCursor = check
		end
	end

	-- How long until the After column (tooltipFullAfter): its heading says.
	local laterHeading
	local function LaterHeading(value)
		if laterHeading then
			laterHeading:SetText(value <= 0 and L["After (off)"] or L["After %d sec"]:format(value))
		end
	end
	local laterOn
	local fullAfter = Slider(content, "tooltipFullAfter", L["After hovering for"], 0, 10, 1, function(value)
		return value <= 0 and L["Off"] or L["%d sec"]:format(value)
	end, nil, function(value)
		LaterHeading(value)
		if (value > 0) ~= laterOn then
			laterOn = value > 0
			Refresh() -- grey out / enable the grid
		end
	end)
	fullAfter:SetPoint("TOPLEFT", lastCursor, "BOTTOMLEFT", cursorMode and 0 or 2, -30)
	Tooltip(fullAfter, L["How long you hover before the After column's parts show."])

	local PARTS = {
		Border = { L["Background and border"], L["The box around the tooltip."] },
		Health = { L["Health bar"], L["The health bar under the tooltips of players, NPCs and mobs."] },
		Guild = { L["Guild and title (<...>)"], L["A player's <Guild> line, or an NPC's <Innkeeper>-style title."] },
		Level = { L["Level (friends)"], L["The level line of players and NPCs you can't attack."] },
		LevelEnemy = { L["Level (enemies)"], L["The level line of players and NPCs you can attack."] },
		Spec = { L["Spec and class"], L["A player's spec and class line (\"Fury Warrior\")."] },
		Type = { L["Creature type"], L["The kind of creature: Elemental, Beast, Humanoid and so on."] },
		Corpse = { L["Corpse"], L["The Corpse line on a dead player, NPC or mob."] },
		Faction = { L["Faction and PvP"], L["The Horde or Alliance line and the PvP line."] },
		Rep = { L["Reputation faction"], L["The faction an NPC belongs to, whose reputation you earn (\"Hara'ti\")."] },
		Threat = { L["Threat"], L["How much of the mob's threat you have (\"100% Threat\")."] },
		Quest = { L["Quest lines"],
			L["The names of your quests the unit is for, and their objectives (\"5/7 Thistle Boar slain\")."] },
		ObjQuest = { L["Quest lines on objects"],
			L["The same on things in the world you use or pick up for a quest (\"0/1 Palehill Runestone\")."] },
		Hint = { L["Right-click hints"],
			L["The right-click hint lines on frames and items."] },
	}
	local PART_TIPS = { First = L["Shown as soon as the tooltip appears."],
		Later = L["Shown once you've hovered as long as set above."] }
	local partRows = {}
	for _, part in ipairs(ns.TOOLTIP_PARTS) do
		local info = PARTS[part]
		info.keys = { First = "tooltipShow" .. part .. "First", Later = "tooltipShow" .. part .. "Later" }
		info.tips = PART_TIPS
		partRows[#partRows + 1] = info
	end
	-- (Off: the whole grid greys, and tooltips show as the game has them.)
	local function LaterOn(db) return (db.tooltipFullAfter or 0) > 0 end

	-- No wait for: kinds of tooltip that skip the slider's wait and show the
	-- After column's parts as they appear; tick any (each its own setting).
	local NO_WAITS = {
		{ key = "tooltipNoWaitQuest", text = L["Quest objective mobs"] },
	}
	local NO_WAIT_TIP = L["These tooltips show the After column's parts right away."]
	local noWaitRow = CreateFrame("Frame", nil, content)
	noWaitRow:SetSize(400, 26)
	noWaitRow:SetPoint("TOPLEFT", fullAfter, "BOTTOMLEFT", 0, -10)
	local noWaitLabel = Label(noWaitRow, "GameFontHighlight", L["No wait for"])
	noWaitLabel:SetPoint("LEFT", noWaitRow, "LEFT", 0, 0)
	local okNoWait, noWait = ns.MenuDropdown(content)
	if okNoWait and noWait and noWait.SetupMenu then
		noWait:SetWidth(200)
		noWait.searchSkip = true -- (it shows the current ticks, not a label)
		noWait:SetupMenu(function(_, root)
			for _, choice in ipairs(NO_WAITS) do
				root:CreateCheckbox(choice.text,
					function()
						local db = ns.GetDB()
						return db ~= nil and db[choice.key] and true or false
					end,
					function()
						local db = ns.GetDB()
						db[choice.key] = not db[choice.key]
						Refresh()
						return MenuResponse and MenuResponse.Refresh
					end)
			end
		end)
		if noWait.SetSelectionText then
			noWait:SetSelectionText(function()
				local db, ticked = ns.GetDB(), {}
				for _, choice in ipairs(NO_WAITS) do
					if db and db[choice.key] then ticked[#ticked + 1] = choice.text end
				end
				return #ticked > 0 and table.concat(ticked, ", ") or L["None"]
			end)
		end
		noWait.Refresh = function(self) self:GenerateMenu() end
		controls[#controls + 1] = noWait
		for _, choice in ipairs(NO_WAITS) do RecordKey(content, choice.key) end
		noWait:SetPoint("LEFT", noWaitLabel, "RIGHT", 10, 0)
		Tooltip(noWait, NO_WAIT_TIP)
		GreyUnless(noWait, LaterOn)
	else
		local lastCheck = noWaitLabel
		for _, choice in ipairs(NO_WAITS) do
			local check = Check(content, choice.key, choice.text, NO_WAIT_TIP)
			check:SetPoint("LEFT", lastCheck, "RIGHT", lastCheck == noWaitLabel and 10 or 140, 0)
			GreyUnless(check, LaterOn)
			lastCheck = check
		end
	end

	local headings
	previous, headings = Grid(noWaitRow, partRows, {
		{ key = "First", heading = L["On first hover"], enabled = LaterOn },
		{ key = "Later", heading = "", enabled = LaterOn },
	})
	laterHeading = headings.Later
	-- (The heading follows the slider on a refresh too: a profile change, a reset.)
	local refreshSlider = fullAfter.Refresh
	fullAfter.Refresh = function(self)
		refreshSlider(self)
		local value = ns.GetDB().tooltipFullAfter or 0
		laterOn = value > 0
		LaterHeading(value)
	end

	-- Filtered tooltips: names CineMode never shows (Fishing Bobber...), a
	-- row each (name, Remove), then a box to add one, like the Buffs/Debuffs
	-- page's list. Saved as one comma-separated list (tooltipNeverShow),
	-- which Effects.lua reads.
	local filterHeader = Section(L["Filtered tooltips"])
	local filterNote = PageIntro(content, filterHeader,
		L["Tooltips with these names never show in CineMode."])
	local function FilterEntries()
		local entries = {}
		for entry in (ns.GetDB().tooltipNeverShow or ""):gmatch("[^,]+") do
			entry = entry:match("^%s*(.-)%s*$")
			if entry ~= "" then entries[#entries + 1] = entry end
		end
		return entries
	end
	local function SaveFilter(entries)
		ns.GetDB().tooltipNeverShow = table.concat(entries, ", ")
		Refresh()
		FitContentHeight(content)
	end
	local filterRows = {}
	local function FilterRow(i)
		local row = filterRows[i]
		if not row then
			row = CreateFrame("Frame", nil, content)
			row:SetSize(300, 22)
			row.text = Label(row, "GameFontHighlight")
			row.text:SetPoint("LEFT", 0, 0)
			row.remove = ns.PanelButton(row)
			row.remove:SetSize(70, 20)
			row.remove:SetPoint("RIGHT", 0, 0)
			row.remove:SetText(L["Remove"])
			row.remove:SetScript("OnClick", function(self)
				local entries = FilterEntries()
				table.remove(entries, self:GetParent().index)
				SaveFilter(entries)
			end)
			filterRows[i] = row
		end
		return row
	end
	local filterBox = ns.SkinEditBox(CreateFrame("EditBox", nil, content, "InputBoxTemplate"))
	filterBox:SetSize(200, 20)
	filterBox:SetAutoFocus(false)
	local filterAdd = ns.PanelButton(content)
	filterAdd:SetSize(70, 20)
	filterAdd:SetPoint("LEFT", filterBox, "RIGHT", 8, 0)
	filterAdd:SetText(L["Add"])
	local function AddFilter()
		local entry = filterBox:GetText():gsub(",", ""):match("^%s*(.-)%s*$")
		filterBox:SetText("")
		filterBox:ClearFocus()
		if entry ~= "" then
			local entries = FilterEntries()
			for _, existing in ipairs(entries) do
				if existing:lower() == entry:lower() then return end
			end
			entries[#entries + 1] = entry
			SaveFilter(entries)
		end
	end
	filterBox:SetScript("OnEnterPressed", AddFilter)
	filterBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	filterAdd:SetScript("OnClick", AddFilter)
	local FILTER_TIP = L["Type a tooltip's top line as the game shows it."]
	Tooltip(filterBox, FILTER_TIP)
	Tooltip(filterAdd, FILTER_TIP)
	-- Rebuilt as the page shows and after each change.
	controls[#controls + 1] = { debugName = "tooltip filter list", owner = content, Refresh = function()
		local enabled = ns.GetDB().handleTooltips and true or false
		local last = filterNote
		local entries = FilterEntries()
		for i, entry in ipairs(entries) do
			local row = FilterRow(i)
			row.index = i
			row.text:SetText(entry)
			row.remove:SetEnabled(enabled)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", last, "BOTTOMLEFT", i == 1 and 6 or 0, i == 1 and -6 or -2)
			row:Show()
			last = row
		end
		for i = #entries + 1, #filterRows do filterRows[i]:Hide() end
		filterBox:ClearAllPoints()
		filterBox:SetPoint("TOPLEFT", last, "BOTTOMLEFT", #entries == 0 and 12 or 6, -8)
		filterBox:SetEnabled(enabled)
		filterAdd:SetEnabled(enabled)
	end }
	RecordKey(content, "tooltipNeverShow") -- (for Reset page)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Tooltips")
end

local function CreateExtrasPanel()
	local canvas, content = CreateScrollPage()
	extrasPanel = content

	local title = Label(content, "GameFontNormalLarge", L["Addon Frames"])
	title:SetPoint("TOPLEFT", 16, -16)

	-- One grid for every addon's frames: the supported addons' and the custom
	-- frames', under one set of headings and the Default row. (Their settings
	-- stay in sections of those names, for the profile modules' scopes: the
	-- custom frames' and the Default row's recorded as Custom frames.)
	SetSection(content, L["Supported addons"])
	local note = PageIntro(content, title, L["CineMode hides these addons' frames: pick which show, and when."])
	local switch = PageSwitch(content, "handleAddonFrames", L["Enable Page"],
		L["Turns fading of other addons' frames in CineMode on or off."], note)
	local stack = Stack(switch, "check")

	-- In folder tabs: Loaded (the grid, for the addons loaded), Find frames
	-- (finding frames to add) and Not running (the addons installed but not
	-- loaded, then the rest supported). The grid's laid out afresh each time
	-- the page opens (most addons load after this one, so whether they're
	-- loaded isn't known when it's built). Each addon's rows (a suite's: suite
	-- = its name) sit under a header that opens and closes: its supported rows,
	-- then the frames you added (from no addon known: Other frames).
	local PANEL_W = THIRD_PARTY_LABEL_WIDTH + ns.GridWidth(THIRD_PARTY_LAYOUT) + 16
	local holder = CreateFrame("Frame", nil, content)
	holder:SetSize(PANEL_W, 1)
	stack:Add(holder, "label")
	local box = CreateFrame("Frame", nil, content)
	box:SetSize(PANEL_W - 16, 1)
	content.box = box
	local Layout, RefreshFound
	local tab = 1 -- (the tab picked: 1 Loaded, 2 Find frames, 3 Not running, 4 Support files)
	local supportPanel -- (the Support files tab's: FrameLinks.lua)
	-- (The Find frames tab's parts, made further down.)
	local smart, foundHead, noneFound
	local foundRows, foundCount = {}, 0
	local tabsPanel, ShowTab, tabsBase, tabsHeight, tabFrames
	local function PickTab(i)
		-- (Custom Support: the Addon Support page, in this row as its last tab, 2026-11-16.)
		if i == 5 then
			ShowTab(tab)
			ns.ShowHubPage("Addon Support")
			return
		end
		tab = i
		ShowTab(i)
		if i == 2 then
			ns.FindFoundFrames()
			RefreshFound()
		else
			Layout()
			FitContentHeight(content)
		end
	end
	tabsPanel, tabFrames, ShowTab, tabsBase, tabsHeight = ns.FolderTabs(content, {
		{ L["Loaded"], L["The addons loaded now: their frames, and the ones you added."] },
		{ L["Find frames"], L["Find other addons' frames to fade: search, hover, or Smart Find."] },
		{ L["Not running"], L["Addons installed but not loaded, and the ones supported but not installed."] },
		{ L["Support files"], L["Addons that replace the game's frames, and which one to use."] },
		{ L["Custom Support"], L["Settings for each supported addon you have installed."] },
	}, PickTab)
	-- (Shown by the Addon Support page as it's made: only with one of its addons.)
	tabFrames[5]:Hide()
	content.supportTab = tabFrames[5]
	content.tabsWidth = PANEL_W
	-- (A tab picked from the Addon Support page's copy of this row.)
	function content.PickAddonTab(i)
		ns.ShowHubPage("Advanced Frames")
		PickTab(i)
	end
	tabsBase:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -tabsHeight)
	tabsPanel:SetPoint("TOPLEFT", tabsBase, "TOPLEFT")
	tabsPanel:SetSize(PANEL_W, 1)
	box:SetPoint("TOPLEFT", tabsPanel, "TOPLEFT", 8, -10)
	supportPanel = ns.BuildSupportFilesPanel(box, PANEL_W - 16)
	supportPanel.onResize = function()
		Layout()
		FitContentHeight(content)
	end
	ns.WatchFrameLinks(function()
		if tab == 4 and box:IsVisible() then supportPanel.onResize() end
	end)

	local LABEL_WIDTH, ROW_HEIGHT, INDENT = THIRD_PARTY_LABEL_WIDTH, 24, 18
	local COLUMNS = THIRD_PARTY_COLUMNS
	-- The columns' headings, placed by Layout at the top.
	local headings = CreateFrame("Frame", nil, box)
	headings:SetSize(LABEL_WIDTH + ns.GridWidth(THIRD_PARTY_LAYOUT), FRAME_HEADING_HEIGHT)
	ns.GridHeadings(ns.GRID_KIT, headings, headings, LABEL_WIDTH, THIRD_PARTY_LAYOUT)

	-- A row per installed addon: CineMode (ticked: left alone, so shown), then
	-- the Standard Frames page's columns. Made once, placed by Layout. (The
	-- ticks belong to the page itself, for its Reset.)
	local rows = {}
	local function MakeRow(known)
		local row = { known = known }
		row.label = Label(box, "GameFontHighlight", known.short or known.label)
		row.label:SetWidth(LABEL_WIDTH - INDENT)
		row.label:SetJustifyH("LEFT")
		row.label:SetWordWrap(false)
		row.hover = ns.LabelHover(box, row.label) -- (its full name while cut short)
		local item = "addon:" .. known.key
		-- (For the page's Reset: just its rows of the shared lists.)
		for c = 2, #COLUMNS do
			RecordKey(content, COLUMNS[c][3])
			RecordRow(content, COLUMNS[c][3], item)
		end
		for _, list in ipairs({ "calmShow" }) do
			RecordKey(content, list)
			RecordRow(content, list, item)
		end
		-- Always: the addon's frames left alone (its switch off), greying the rest.
		local function Key() return item end
		local function SetAlways(value) ns.SetAddonFramesOn(known.key, not value) end
		local parts = ns.ListRowParts(Key, COLUMNS, nil, SetAlways)
		row.grid = ns.GridRow(ns.GRID_KIT, box, LABEL_WIDTH, THIRD_PARTY_LAYOUT, {
			band = 1, dot = true,
			enabled = function() return not row.unloaded end, -- (greyed on the Not running tab)
			always = { isOn = function() return not ns.IsAddonFramesOn(known.key) end, set = SetAlways,
				tip = (L["Show %s the whole time in CineMode.%s"]):format(known.about,
				known.note and " " .. known.note or "") },
			menus = parts.menus,
			rule = { key = Key, label = function() return known.label end, grid = parts.grid,
				words = parts.words, apply = parts.apply },
		})
		return row
	end
	for _, known in ipairs(ns.ADDON_FRAMES) do
		if ns.AddOnInstalled(known.addon) then
			rows[#rows + 1] = MakeRow(known)
		end
	end

	StaticPopupDialogs.CINEMATIC_SUPPORT_RELOAD = {
		text = L["Switching an addon's support on or off counts after a reload. Reload now?"],
		button1 = RELOADUI or L["Reload"], button2 = L["Later"],
		OnAccept = ReloadUI,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	-- A row per installed addon supported with no frames of its own (Support/,
	-- ns.ADDON_NOTES): its name and, across the columns, what's done for it.
	local notes = {}
	for _, note in ipairs(ns.ADDON_NOTES) do
		if ns.AddOnInstalled(note.addon) then
			local row = { note = note }
			row.frame = CreateFrame("Frame", nil, box)
			row.frame:SetSize(LABEL_WIDTH + ns.GridWidth(THIRD_PARTY_LAYOUT), ROW_HEIGHT)
			row.label = Label(row.frame, "GameFontHighlight", "")
			row.label:SetPoint("TOPLEFT", 0, -5)
			row.label:SetWidth(LABEL_WIDTH - INDENT)
			row.label:SetJustifyH("LEFT")
			row.label:SetWordWrap(false)
			row.frame.fullLabel = row.label -- (its full name over the tip while cut short)
			row.works = Label(row.frame, "GameFontDisable", "")
			row.works:SetPoint("TOPLEFT", LABEL_WIDTH, -5)
			Tooltip(row.frame, "")
			-- Its support on or off, in the Always column (only with setup code:
			-- a note alone has nothing to switch off). Counts after a /reload.
			if ns.HasAddonSetup(note.addon) then
				local addon = note.addon
				local supportBox = ns.SkinCheck(CreateFrame("CheckButton", nil, row.frame, "UICheckButtonTemplate"))
				supportBox:SetSize(26, 26)
				supportBox:SetPoint("LEFT", LABEL_WIDTH + (ns.GRID_ALWAYS_W - 26) / 2, 0)
				row.works:ClearAllPoints()
				row.works:SetPoint("TOPLEFT", LABEL_WIDTH + ns.GRID_ALWAYS_W + ns.GRID_GAP, -5)
				supportBox:SetScript("OnClick", function(self)
					local off = ns.GetDB().addonSupportOff
					off[addon] = not self:GetChecked() or nil
					row.works:SetAlpha(off[addon] and 0.5 or 1)
					StaticPopup_Show("CINEMATIC_SUPPORT_RELOAD")
				end)
				Tooltip(supportBox, L["Turns Cinematic's support for this addon on or off after a reload."])
				row.support = supportBox
			end
			notes[#notes + 1] = row
		end
	end

	local sectionBands, suiteHeaders = {}, {}
	-- Which sections are open, as on the Standard Frames page: a band each,
	-- clicked to open or close it (Not installed starts closed).
	local bandSections = {
		loaded = { id = "Advanced Frames/loaded", open = true },
		installed = { id = "Advanced Frames/installed", open = true },
		missing = { id = "Advanced Frames/missing", open = false },
	}
	local missingNote = Label(box, "GameFontHighlightSmall", "")
	missingNote:SetWidth(560)
	missingNote:SetJustifyH("LEFT")
	missingNote:SetJustifyV("TOP")

	-- The Default row, first under the headings: what a frame you add, or an
	-- addon you install later, starts with (ns.ApplyExtraDefault,
	-- ns.DefaultNewAddons), and Copy to all to give it to every row now.
	local defaultRow = CreateFrame("Frame", nil, box)
	defaultRow:SetSize(LABEL_WIDTH + ns.GridWidth(THIRD_PARTY_LAYOUT), ROW_HEIGHT)
	local defaultName = Label(defaultRow, "GameFontNormal", L["Default"])
	defaultName:SetPoint("LEFT", 0, 0)
	StaticPopupDialogs.CINEMATIC_EXTRA_COPY_ALL = {
		text = L["Give every addon's frames the Default row's settings?"],
		button1 = YES, button2 = NO,
		OnAccept = function()
			ns.CopyExtraDefaultToAll()
			RefreshExtras()
			Refresh()
		end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	local copyAll = ns.PanelButton(defaultRow)
	copyAll:SetSize(80, 20)
	copyAll:SetPoint("RIGHT", defaultRow, "LEFT", LABEL_WIDTH - 6, 0)
	copyAll:SetText(L["Copy to all"])
	Tooltip(copyAll, L["Gives every row on this page the Default row's settings."])
	copyAll:SetScript("OnClick", function() StaticPopup_Show("CINEMATIC_EXTRA_COPY_ALL") end)
	local function DefaultKey() return ns.EXTRA_DEFAULT_KEY end
	local function SetDefaultAlways(value) ns.GetDB().addonDefaultAlways = value end
	RecordKey(content, "addonDefaultAlways", L["Custom frames"])
	for c = 2, #COLUMNS do
		RecordKey(content, COLUMNS[c][3])
		RecordRow(content, COLUMNS[c][3], ns.EXTRA_DEFAULT_KEY, L["Custom frames"])
	end
	for _, list in ipairs({ "calmShow", "frameRules" }) do
		RecordKey(content, list)
		RecordRow(content, list, ns.EXTRA_DEFAULT_KEY, L["Custom frames"])
	end
	local defaultParts = ns.ListRowParts(DefaultKey, COLUMNS, nil, SetDefaultAlways)
	local defaultGrid = ns.GridRow(ns.GRID_KIT, defaultRow, LABEL_WIDTH, THIRD_PARTY_LAYOUT, {
		band = 1,
		always = { isOn = function() return ns.GetDB().addonDefaultAlways end, set = SetDefaultAlways,
			tip = L["Addons you install later start always shown in CineMode."] },
		menus = defaultParts.menus,
		rule = { key = DefaultKey, label = function() return L["Default"] end, grid = defaultParts.grid,
			words = defaultParts.words, apply = defaultParts.apply },
	})
	defaultGrid:SetPoint("LEFT", defaultRow, "LEFT", LABEL_WIDTH, 0)

	-- The tools for adding frames (the search box, then add mode's button;
	-- made below), at the top.
	local tools = CreateFrame("Frame", nil, box)
	-- (The settings search and /cine find reach its tab's tools from any tab:
	-- finding one picks the tab. Smart Find's the same, below.)
	tools.searchAlways = true
	tools.openSection = function() PickTab(2) end
	tools:SetSize(LABEL_WIDTH + ns.GridWidth(THIRD_PARTY_LAYOUT), 30)

	local function SectionBandFor(key, title)
		local holder = sectionBands[key]
		if not holder then
			holder = CreateFrame("Frame", nil, box)
			-- (The band hangs 18 left of its frame: placed 18 in, it stays in the box.)
			holder:SetSize(box:GetWidth() - 18, BAND_HEIGHT)
			holder.nameRow = SectionBand(holder, title, function()
				SectionState.Save(bandSections[key], not bandSections[key].open)
				Layout()
				FitContentHeight(content)
			end)
			sectionBands[key] = holder
		end
		holder.nameRow.title:SetText(title) -- (translated once the language is known)
		holder.nameRow:SetOpen(SectionState.Restore(bandSections[key]))
		return holder
	end

	-- An addon's header: + or - and its name, with how many rows it has.
	local function SuiteHeader(suite)
		local header = suiteHeaders[suite]
		if not header then
			header = CreateFrame("Button", nil, box)
			header:SetSize(LABEL_WIDTH, ROW_HEIGHT)
			header.icon = header:CreateTexture(nil, "ARTWORK")
			header.icon:SetSize(14, 14)
			header.icon:SetPoint("LEFT", 0, 0)
			header.text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			header.text:SetPoint("LEFT", header.icon, "RIGHT", 4, 0)
			header:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
			header:GetHighlightTexture():SetAllPoints(header.icon)
			header:SetScript("OnClick", function()
				local closed = ns.GetDB().addonGroupsClosed
				closed[suite] = not closed[suite] or nil
				Layout()
				FitContentHeight(content)
			end)
			Tooltip(header, L["Click to show or hide its parts."])
			suiteHeaders[suite] = header
		end
		return header
	end

	Layout = function()
		local db = ns.GetDB()
		local y = 0
		local function Place(region, x, height)
			region:ClearAllPoints()
			region:SetPoint("TOPLEFT", box, "TOPLEFT", x, -y)
			region:Show()
			y = y + height
		end
		for _, holder in pairs(sectionBands) do holder:Hide() end
		for _, header in pairs(suiteHeaders) do header:Hide() end
		for _, row in ipairs(rows) do
			row.label:Hide()
			row.hover:Hide()
			row.grid:Hide()
		end
		for _, row in ipairs(extraRows) do row:Hide() end
		for _, region in ipairs({ tools, headings, defaultRow, smart, foundHead, noneFound, missingNote, supportPanel }) do
			region:Hide()
		end
		for _, row in ipairs(foundRows) do row:Hide() end
		for _, row in ipairs(notes) do row.frame:Hide() end
		local function Fit()
			box:SetHeight(math.max(1, y))
			tabsPanel:SetHeight(y + 20)
			holder:SetHeight(tabsHeight + y + 20)
		end

		-- Find frames: the search and Hover Find, Smart Find, and what it found.
		if tab == 2 then
			Place(tools, 0, 30)
			smart:SetHeight(smart.Height()) -- (a frame with no height draws nothing in it)
			Place(smart, 0, smart:GetHeight())
			if foundCount > 0 then
				Place(foundHead, 0, 18)
				for i = 1, foundCount do Place(foundRows[i], 0, ROW_HEIGHT) end
			else
				Place(noneFound, 0, noneFound:GetStringHeight() + 6)
			end
			Fit()
			return
		end

		-- Support files: the clashes to pick, and what each addon replaces.
		if tab == 4 then
			Place(supportPanel, 0, supportPanel.Refresh())
			Fit()
			return
		end

		-- Loaded and Not running: the headings (and on Loaded, the Default row).
		Place(headings, 0, FRAME_HEADING_HEIGHT + 4)
		if tab == 1 then
			Place(defaultRow, 0, ROW_HEIGHT)
		end
		local band = 1

		local function PlaceRow(row, label)
			row.label:SetText(label)
			row.label:ClearAllPoints()
			row.label:SetPoint("TOPLEFT", box, "TOPLEFT", INDENT, -y - 5)
			row.label:Show()
			row.hover:Show()
			band = band + 1
			row.grid:SetBand(band)
			row.grid:ClearAllPoints()
			row.grid:SetPoint("TOPLEFT", box, "TOPLEFT", LABEL_WIDTH, -y)
			row.grid:Show()
			y = y + ROW_HEIGHT
		end

		local lastOpen = true
		local function Band(key, title)
			y = y + (y > 0 and (lastOpen and 12 or 6) or 0)
			Place(SectionBandFor(key, title), 18, BAND_HEIGHT)
			lastOpen = bandSections[key].open
			if lastOpen then
				y = y + 6
			end
			return lastOpen
		end

		-- The groups: by suite, else by addon; the frames you added and the
		-- found ones under their addon's (that addon's suite's, for a suite's
		-- part; the main addon's, for a module named after it:
		-- SilverDragon_History), the rest under Other frames (key "").
		local suiteOf = {}
		for _, known in ipairs(ns.ADDON_FRAMES) do
			if known.suite then suiteOf[known.addon] = known.suite end
		end
		local function GroupOf(addon)
			if not addon then return "" end
			if suiteOf[addon] then return suiteOf[addon] end
			for _, suite in pairs(suiteOf) do
				if addon:sub(1, #suite) == suite then return suite end
			end
			local main = addon:match("^(.-)_")
			if main and main ~= "" and ns.AddOnInstalled(main) then
				return GroupOf(main)
			end
			return addon
		end
		local groups, order = {}, {}
		local function Group(key)
			local group = groups[key]
			if not group then
				group = { key = key, rows = {}, notes = {}, extras = {}, loaded = false }
				groups[key] = group
				order[#order + 1] = group
			end
			return group
		end
		for _, row in ipairs(rows) do
			local group = Group(row.known.suite or row.known.addon)
			group.rows[#group.rows + 1] = row
			group.loaded = group.loaded or ns.AddOnLoaded(row.known.addon)
			group.title = group.title or row.known.suite
		end
		for _, row in ipairs(notes) do
			local group = Group(GroupOf(row.note.addon)) -- (a suite's part's under the suite)
			group.notes[#group.notes + 1] = row
			group.loaded = group.loaded or ns.AddOnLoaded(row.note.addon)
			group.title = group.title or row.note.label
		end
		for i = 1, content.extraCount or 0 do
			local row = extraRows[i]
			local addon = row.item.addon
			local group = Group(GroupOf(addon))
			group.extras[#group.extras + 1] = row
			group.loaded = group.loaded or not addon or ns.AddOnLoaded(addon)
		end
		-- Its name: the suite's, its one supported row's ("Deadly Boss Mods"),
		-- the addon's own title, or its folder's.
		local getInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
		for _, group in ipairs(order) do
			if group.key == "" then
				group.title = L["Other frames"]
			elseif not group.title and #group.rows == 1 then
				group.title = group.rows[1].known.label
			elseif not group.title then
				local title = getInfo and select(2, getInfo(group.key))
				-- (Without colors, bracketed bits and a version at the end:
				-- "Titan Panel [_Core_] 9.3.5" is Titan Panel.)
				title = type(title) == "string" and title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
					:gsub("%b[]", ""):gsub("%b<>", ""):gsub("%s+v?%d[%d%.]*%s*$", ""):gsub("%s+", " ")
					:match("^%s*(.-)%s*$") or ""
				group.title = title ~= "" and title or group.key
			end
		end
		table.sort(order, function(a, b)
			if (a.key == "") ~= (b.key == "") then return b.key == "" end
			return a.title:lower() < b.title:lower()
		end)

		-- A supported row's name under its addon's: without the addon's name
		-- ("Data Bars"), else what it fades ("Its meter windows").
		local function RowName(known, title)
			local label = known.label
			if label:sub(1, #title + 1) == title .. " " then
				label = label:sub(#title + 2)
			elseif label == title then
				label = known.about or label
			end
			return label:sub(1, 1):upper() .. label:sub(2)
		end

		local function PlaceGroup(group)
			local header = SuiteHeader(group.key)
			local closed = db.addonGroupsClosed[group.key]
			header.icon:SetTexture(closed and "Interface\\Buttons\\UI-PlusButton-Up"
				or "Interface\\Buttons\\UI-MinusButton-Up")
			header.text:SetText(("%s |cff808080(%d)|r"):format(group.title, #group.rows + #group.notes + #group.extras))
			Place(header, 0, ROW_HEIGHT)
			if closed then
				return
			end
			-- (Texts read now: they're translated once the language is known.)
			for _, row in ipairs(group.notes) do
				row.label:SetText(row.note.label)
				row.works:SetText(row.note.works)
				if row.support then
					local on = ns.AddonSupportOn(row.note.addon)
					row.support:SetChecked(on)
					row.works:SetAlpha(on and 1 or 0.5)
				end
				Tooltip(row.frame, row.note.about)
				Place(row.frame, INDENT, ROW_HEIGHT)
			end
			-- (An addon that isn't loaded: its rows greyed, nothing to fade yet.)
			local unloaded = not group.loaded
			for _, row in ipairs(group.rows) do
				PlaceRow(row, RowName(row.known, group.title))
				row.unloaded = unloaded
				row.label:SetAlpha(unloaded and 0.5 or 1)
				row.grid:Refresh()
			end
			for _, row in ipairs(group.extras) do
				band = band + 1
				row.grid:SetBand(band)
				Place(row, 0, ROW_HEIGHT)
				row.unloaded = unloaded
				row.text:SetAlpha(unloaded and 0.5 or 1)
				row.grid:Refresh()
			end
		end

		if tab == 1 then
			y = y + 6
			for _, group in ipairs(order) do
				if group.loaded then PlaceGroup(group) end
			end
		else
			local wanted = {}
			for _, group in ipairs(order) do
				if not group.loaded then wanted[#wanted + 1] = group end
			end
			if #wanted > 0 and Band("installed", L["Installed, not loaded"]) then
				for _, group in ipairs(wanted) do PlaceGroup(group) end
			end
		end

		-- The rest supported, by name (a suite once).
		local missing, listed = {}, {}
		for _, known in ipairs(ns.ADDON_FRAMES) do
			local name = known.suite or known.label
			if not ns.AddOnInstalled(known.addon) and not listed[name] then
				listed[name] = true
				missing[#missing + 1] = name
			end
		end
		for _, note in ipairs(ns.ADDON_NOTES) do
			if not ns.AddOnInstalled(note.addon) then
				missing[#missing + 1] = note.label
			end
		end
		if tab == 3 and #missing > 0 and Band("missing", L["Not installed"]) then
			missingNote:SetText("|cff808080" .. L["Also supported, when installed: %s"]:format(table.concat(missing, ", ")) .. "|r")
			Place(missingNote, 0, missingNote:GetStringHeight() + 4)
		end
		Fit()
	end
	content.Layout = Layout

	-- The Find frames tab's Smart Find: what it is, its background tick, and
	-- a button to run it for a while, up by Hover Find (counting down on it).
	smart = CreateFrame("Frame", nil, box)
	smart.searchAlways = true
	smart.openSection = tools.openSection
	smart:SetWidth(PANEL_W - 16)
	local smartTitle = Label(smart, "GameFontNormal", L["Smart Find"])
	smartTitle:SetPoint("TOPLEFT", 0, -6)
	local background = Check(content, "smartFindBackground", L["Look in the background"],
		L["Smart Find looks for new addons' frames in the background for a while."])
	background:SetParent(smart) -- (its setting recorded on the page, for its Reset)
	background:SetPoint("TOPLEFT", smartTitle, "BOTTOMLEFT", -4, -6)
	local runButton = ns.PanelButton(tools)
	runButton:SetSize(120, 22)
	runButton:SetPoint("TOPLEFT", tools, "TOPLEFT", 384, -3) -- (right of Hover Find and its spinner)
	Tooltip(runButton, L["Looks for other addons' frames that nothing fades yet."])
	local function ShowRun()
		local left = ns.SmartFindLeft()
		runButton:SetText(left and ("%s (%ds)"):format(L["Stop"], left) or L["Smart Find"])
	end
	runButton:SetScript("OnClick", function()
		if ns.SmartFindLeft() then
			ns.StopSmartFind()
			return
		end
		ns.StartSmartFind(function()
			ShowRun()
			if canvas:IsVisible() and tab == 2 then RefreshFound() end
		end)
	end)
	ShowRun()
	smart.Height = function()
		return 6 + smartTitle:GetStringHeight() + 6 + 26 + 12
	end

	-- What it found: the frame, its addon, the row it'd follow, and Add
	-- (ns.AdoptFoundFrame: onto the Loaded tab, faded).
	-- (The texts stop short of Add: their hover areas took its clicks.)
	local FIND_ADD_W = 80
	-- (A found frame whose addon isn't loaded now stays off this list: its row,
	-- if it has one, is on the Not running tab, and it's back with the addon.)
	local function FoundListed(known)
		return not known.dismissed and (not known.addon or ns.AddOnLoaded(known.addon))
	end
	local FIND_NAME_W, FIND_ADDON_X, FIND_ADDON_W, FIND_GUESS_X = 220, 230, 150, 390
	local FIND_GUESS_W = math.max(60, PANEL_W - 16 - FIND_ADD_W - 16 - FIND_GUESS_X)
	foundHead = CreateFrame("Frame", nil, box)
	foundHead:SetSize(PANEL_W - 16, 18)
	for _, column in ipairs({ { L["Frame"], 0 }, { L["Addon"], FIND_ADDON_X }, { L["Guess"], FIND_GUESS_X } }) do
		local heading = Label(foundHead, "GameFontNormalSmall", column[1])
		heading:SetPoint("LEFT", column[2], 0)
	end
	-- Add all: on Smart Find's button line, over the Add column, every found
	-- frame not added yet (Hover Find's picks still going aren't on the list
	-- yet: left out).
	local addAll = ns.PanelButton(smart)
	addAll:SetSize(FIND_ADD_W, 22)
	addAll:SetPoint("RIGHT", smart, "RIGHT", -4, 0)
	addAll:SetPoint("TOP", background, "TOP", 0, -2)
	addAll:SetText(L["Load all"])
	Tooltip(addAll, L["Loads every frame on this list that isn't loaded yet, as Load does for one."])
	foundHead.addAll = addAll
	addAll:SetScript("OnClick", function()
		local db = ns.GetDB()
		local names = {}
		for name, known in pairs(db.foundFrames) do
			if FoundListed(known) and not db.extraFrames[name] then names[#names + 1] = name end
		end
		for _, name in ipairs(names) do ns.AdoptFoundFrame(name) end
		RefreshExtras()
		RefreshFound()
	end)
	noneFound = Label(box, "GameFontDisableSmall", L["Nothing found yet. Smart Find looks at what's on screen: " ..
		"run it while the frames you want are showing."])
	noneFound:SetWidth(PANEL_W - 40)
	noneFound:SetJustifyH("LEFT")
	local function FoundRow(i)
		local row = foundRows[i]
		if row then return row end
		row = CreateFrame("Frame", nil, box)
		row:SetSize(PANEL_W - 16, ROW_HEIGHT)
		local function Text(x, width, font)
			local text = Label(row, font, "")
			text:SetPoint("LEFT", x, 0)
			text:SetWidth(width)
			text:SetJustifyH("LEFT")
			text:SetWordWrap(false)
			ns.LabelHover(row, text) -- (its full text while cut short)
			return text
		end
		row.name = Text(0, FIND_NAME_W, "GameFontHighlight")
		row.addon = Text(FIND_ADDON_X, FIND_ADDON_W, "GameFontHighlightSmall")
		row.guess = Text(FIND_GUESS_X, FIND_GUESS_W, "GameFontHighlightSmall")
		row.add = ns.PanelButton(row)
		row.add:SetSize(FIND_ADD_W, 22)
		row.add:SetPoint("RIGHT", -4, 0)
		row.add:SetFrameLevel(row:GetFrameLevel() + 5) -- (over the texts' hover areas)
		row.add:SetText(L["Load"])
		Tooltip(row.add, L["Puts it on the Loaded tab, under its addon, with the Default row's settings."])
		row.add:SetScript("OnClick", function()
			ns.AdoptFoundFrame(row.name.frameName)
			RefreshExtras()
			RefreshFound()
		end)
		row.added = Label(row, "GameFontDisableSmall", L["Loaded"])
		row.added:SetPoint("RIGHT", -14, 0)
		foundRows[i] = row
		return row
	end
	RefreshFound = function()
		local db = ns.GetDB()
		local names = {}
		for name, known in pairs(db.foundFrames) do
			if FoundListed(known) then names[#names + 1] = name end
		end
		-- (Hover Find's picks so far, at the top: on the list once it stops.)
		local picking = {}
		if ns.addModeToList then
			for _, name in ipairs(ns.GetPickedFrames()) do
				if not db.foundFrames[name] then picking[#picking + 1] = name end
			end
		end
		-- (Ones still to load first, then by name, numbers in order: Raid2
		-- before Raid10, as the numbers padded to the same length.)
		local function Key(name)
			return (name:lower():gsub("%d+", function(digits)
				return #digits < 10 and ("0"):rep(10 - #digits) .. digits or digits
			end))
		end
		table.sort(names, function(a, b)
			local loadedA, loadedB = db.extraFrames[a] and true or false, db.extraFrames[b] and true or false
			if loadedA ~= loadedB then return loadedB end
			return Key(a) < Key(b)
		end)
		for i, name in ipairs(picking) do
			local row = FoundRow(i)
			row.name.frameName = name
			row.name:SetText("|cffffd100" .. name .. "|r")
			row.addon:SetText(ns.FrameAddon(name) or "?")
			row.guess:SetText("|cff808080(" .. L["picked"] .. ")|r")
			row.add:Hide()
			row.added:Hide()
		end
		local toAdd = 0
		for n, name in ipairs(names) do
			local i = #picking + n
			local known, row = db.foundFrames[name], FoundRow(i)
			local unnamed = name:sub(1, #ns.UNNAMED_PREFIX) == ns.UNNAMED_PREFIX
			row.name.frameName = name
			row.name:SetText(unnamed and ("%s (%d)"):format(L["Its unnamed frames"], known.count or 0) or name)
			row.addon:SetText(known.addon or "?")
			row.guess:SetText(ns.RowLabel(known.follow) or L["Own row"])
			local added = db.extraFrames[name] and true or false
			row.add:SetShown(not added)
			row.added:SetShown(added)
			if not added then toAdd = toAdd + 1 end
		end
		foundHead.addAll:SetShown(toAdd > 0)
		foundCount = #picking + #names
		Layout()
		FitContentHeight(content)
	end
	SetSection(content, L["Custom frames"]) -- (what's below: the custom frames' tools)

	-- Add mode (/cine add mode): pick up frames by hovering, then fade them all.
	local addMode = ns.PanelButton(tools)
	addMode:SetSize(120, 22)
	addMode:SetPoint("TOPLEFT", tools, "TOPLEFT", 232, -3) -- (right of the search box)
	Tooltip(addMode, L["Hover over frames, then click Stop to add them to the list."])
	addMode:SetScript("OnClick", function() ns.ToggleAddMode(true) end)
	-- A spinner beside it while it's on, to show it's still watching the mouse.
	local spinner = addMode:CreateTexture(nil, "OVERLAY")
	spinner:SetTexture("Interface\\COMMON\\StreamCircle")
	spinner:SetSize(20, 20)
	spinner:SetPoint("LEFT", addMode, "RIGHT", 6, 0)
	spinner:SetVertexColor(0.3, 1, 0.3)
	local spin = spinner:CreateAnimationGroup()
	local turn = spin:CreateAnimation("Rotation")
	turn:SetDegrees(-360)
	turn:SetDuration(1)
	spin:SetLooping("REPEAT")

	-- Tinted green while it's on, in either menu look.
	local function ShowAddMode()
		local on = ns.IsAddModeOn()
		spinner:SetShown(on)
		if on then spin:Play() else spin:Stop() end
		addMode:SetText(on and L["Stop"] or L["Hover Find"])
		if on then addMode:SetSkinTint(0.3, 1, 0.3) else addMode:SetSkinTint(nil) end
	end
	content.addMode = addMode
	ShowAddMode()
	-- Kept up to date when /cine add mode turns it on or off.
	ns.OnAddModeChanged = function()
		ShowAddMode()
		if canvas:IsVisible() then
			RefreshExtras()
			RefreshFound()
		end
	end

	-- Or find them by name: other addons' frames not faded yet, matching what's
	-- typed (a frame's name or its addon's); hovering a match marks it on
	-- screen, clicking it fades it.
	local FIND_ROWS = 12
	local made, find = pcall(CreateFrame, "EditBox", nil, tools, "SearchBoxTemplate")
	if not made or not find then
		find = ns.SkinEditBox(CreateFrame("EditBox", nil, tools, "InputBoxTemplate"))
	end
	find:SetSize(215, 20)
	find:SetAutoFocus(false)
	find.searchSkip = true
	-- (In a step: the search box's art stands out past its left.)
	find:SetPoint("TOPLEFT", tools, "TOPLEFT", 5, -4)
	if find.Instructions then
		find.Instructions:SetText(L["Find frames by name or addon"])
	end
	Tooltip(find, L["Type part of a frame's or addon's name to find it."])

	local found = CreateFrame("Frame", nil, content)
	found.searchSkip = true
	found:SetPoint("TOPLEFT", find, "BOTTOMLEFT", -6, -2)
	found:SetWidth(420)
	found:SetFrameLevel(content:GetFrameLevel() + 20)
	found:EnableMouse(true)
	found:Hide()
	local border = found:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0.45, 0.38, 0.2, 1)
	local back = found:CreateTexture(nil, "BORDER")
	back:SetPoint("TOPLEFT", 1, -1)
	back:SetPoint("BOTTOMRIGHT", -1, 1)
	back:SetColorTexture(0.05, 0.05, 0.05, 0.97)

	local frames, matches, findRows, findOffset = nil, {}, {}, 0
	local DrawFound, UpdateFound
	local function FindRow(i)
		if findRows[i] then return findRows[i] end
		local row = CreateFrame("Button", nil, found)
		row:SetHeight(20)
		row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
		row:SetPoint("RIGHT", -4, 0)
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.1)
		row.text = Label(row, "GameFontHighlight")
		row.text:SetPoint("LEFT", 6, 0)
		row.text:SetPoint("RIGHT", -6, 0)
		row.text:SetWordWrap(false)
		row:SetScript("OnEnter", function(self)
			if self.entry and not ns.MarkFrame(self.entry.name) then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(L["Not on screen right now."], 1, 1, 1, 1, true)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function()
			ns.MarkFrame(nil)
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(self)
			if not self.entry then return end
			ns.MarkFrame(nil)
			ns.NoteFoundFrame(self.entry.name) -- (on the list below, to add)
			RefreshExtras()
			RefreshFound()
			-- (It's off the matches now; the rest stay up, where they were, to
			-- pick the next.)
			local offset = findOffset
			UpdateFound()
			findOffset = math.max(0, math.min(offset, #matches - FIND_ROWS))
			DrawFound()
			if self:IsShown() and self.entry then ns.MarkFrame(self.entry.name) end
		end)
		findRows[i] = row
		return row
	end

	-- The matches from findOffset on; the mouse wheel scrolls through the rest.
	DrawFound = function()
		local shown = math.min(#matches - findOffset, FIND_ROWS)
		for i = 1, shown do
			local entry, row = matches[findOffset + i], FindRow(i)
			row.entry = entry
			row.text:SetText("|cffffd100" .. entry.name .. "|r" ..
				(entry.source and ("  |cff808080" .. entry.source .. "|r") or ""))
			row:Show()
		end
		local lines = shown
		local below = #matches - findOffset - shown
		if #matches == 0 or below > 0 then
			lines = lines + 1
			local row = FindRow(lines)
			row.entry = nil
			row.text:SetText(#matches == 0 and L["|cff808080Nothing found|r"] or
				("|cff808080" .. L["Scroll for %d more"]:format(below) .. "|r"))
			row:Show()
		end
		for i = lines + 1, #findRows do findRows[i]:Hide() end
		found:SetHeight(lines * 20 + 8)
	end
	found:EnableMouseWheel(true)
	found:SetScript("OnMouseWheel", function(_, delta)
		findOffset = math.max(0, math.min(findOffset - delta, #matches - FIND_ROWS))
		DrawFound()
	end)

	-- Names starting with what's typed first, then the shortest (an addon's
	-- main window before its parts).
	UpdateFound = function()
		local query = (find:GetText() or ""):match("^%s*(.-)%s*$"):lower()
		if query == "" then
			found:Hide()
			return
		end
		frames = frames or ns.FindAddableFrames()
		matches = {}
		local listed = ns.GetDB().foundFrames
		for _, entry in ipairs(frames) do
			local known = listed[entry.name]
			if entry.lower:find(query, 1, true) and not (known and not known.dismissed) then
				matches[#matches + 1] = entry
			end
		end
		table.sort(matches, function(a, b)
			local aStarts = a.lower:sub(1, #query) == query
			local bStarts = b.lower:sub(1, #query) == query
			if aStarts ~= bStarts then return aStarts end
			if #a.name ~= #b.name then return #a.name < #b.name end
			return a.name < b.name
		end)
		findOffset = 0
		DrawFound()
		found:Show()
	end
	find:HookScript("OnTextChanged", UpdateFound)
	-- A fresh look at the frames each time you start searching (addons make
	-- frames as they go).
	find:HookScript("OnEditFocusGained", function()
		frames = nil
		UpdateFound()
	end)
	find:HookScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	canvas:HookScript("OnHide", function()
		found:Hide()
		ns.MarkFrame(nil)
	end)

	canvas:SetScript("OnShow", PageShown(function()
		if ns.GetDB() then
			if tab == 2 then ns.FindFoundFrames() end
			Layout()
			Refresh()
			RefreshExtras()
			RefreshFound()
		end
	end, content))
	canvas:Hide()
	RegisterSubpage(canvas, L["Advanced Frames"], L["Addon Frames"])
end

-- Sub-page: keybinds. The same bindings as Key Bindings > AddOns, with two
-- key slots each like Blizzard's page. section: a header above that row.
local KEYBINDS = {
	{ action = "CINEMATIC_TOGGLE", label = L["Toggle CineMode"], section = L["General"],
		tip = L["Turns CineMode on or off."] },
	{ action = "CINEMATIC_HIDEUI", label = L["Hide the UI"],
		tip = L["Hides the whole UI but keeps the CineMode effects."] },
	{ action = "CINEMATIC_SCREENSHOT", label = L["Take a CineShot"],
		tip = L["Takes a screenshot with the UI hidden."] },
	{ action = "CINEMATIC_TOGGLEEFFECTS", label = L["Toggle visual effects"],
		tip = L["Turns the visual effects on or off."] },
	{ action = "CINEMATIC_TOGGLELETTERBOX", label = L["Toggle letterbox bars"],
		tip = L["Shows or hides the letterbox bars."] },
	{ action = "CINEMATIC_HIDECURSOR", label = L["Hide Cursor till moves"],
		tip = L["Hides the cursor until you move the mouse."] },
	{ action = "CINEMATIC_RELOAD", label = L["Reload the UI"],
		tip = L["Reloads the UI."] },
	{ action = "CINEMATIC_TOGGLESETTINGS", label = L["Toggle settings"],
		tip = L["Opens or closes Cinematic's settings."] },
	{ action = "CINEMATIC_KEYMAP", label = L["Keyboard map"],
		tip = L["Hold or tap to see what each key on your keyboard does."] },
	{ action = "CLICK CinematicMasterWheelButton:LeftButton", label = L["Master wheel"], section = L["Wheels"],
		tip = L["Hold to open a wheel of all your wheels."] },
	{ action = "CINEMATIC_CAMWHEEL", label = L["Camera wheel"],
		tip = L["Hold to open a wheel of your cameras."] },
	{ action = "CLICK CinematicMenuWheelButton:LeftButton", label = L["Menu wheel"],
		tip = L["Hold to open a wheel of the game's menu buttons."] },
	{ action = "CLICK CinematicMarkerWheelButton:LeftButton", label = L["Marker wheel"],
		tip = L["Hold to open a wheel of raid target markers."] },
	{ action = "CLICK CinematicWorldMarkerWheelButton:LeftButton", label = L["Ground marker wheel"],
		show = function() return ns.hasWorldMarkerWheel end,
		tip = L["Hold to open a wheel of ground markers; only in a group."] },
	{ action = "CLICK CinematicVisionWheelButton:LeftButton", label = L["Vision wheel"],
		tip = L["Hold to open a wheel that turns the visions on or off."] },
	{ action = "CINEMATIC_VISION_HEAL", label = L["Toggle Heal Vision"], section = L["Visions"],
		tip = L["Turns Heal Vision on or off."] },
	{ action = "CINEMATIC_VISION_QUEST", label = L["Toggle Quest Vision"],
		tip = L["Turns Quest Vision on or off (its Enable Page switch)."] },
	{ action = "CLICK CinematicQuestItemButton:LeftButton", label = L["Use the quest item"],
		tip = L["Uses the item on Quest Vision's quest item button, while it shows."] },
	{ action = "CINEMATIC_VISION_DUEL", label = L["Toggle Duel Vision"],
		tip = L["Turns Duel Vision on or off."] },
	{ action = "CINEMATIC_VISION_ROLL", label = L["Toggle Roll Vision"],
		show = function() return ns.hasRollWindow end,
		tip = L["Turns Roll Vision on or off."] },
	{ action = "CINEMATIC_VISION_VITALS", label = L["Toggle Vitals Vision"],
		tip = L["Turns Vitals Vision on or off (its Enable Page switch)."] },
	{ action = "CINEMATIC_VISION_DAMAGE", label = L["Toggle Damage Vision"],
		show = function() return C_DamageMeter ~= nil end,
		tip = L["Turns Damage Vision on or off (its Enable Page switch)."] },
	{ action = "CINEMATIC_VISION_TELE", label = L["Toggle Teleport Vision"],
		tip = L["Turns Teleport Vision on or off (its Enable Page switch)."] },
	{ action = "CINEMATIC_VISION_EMOTE", label = L["Toggle Emote Vision"],
		tip = L["Turns Emote Vision on or off (its Enable Page switch)."] },
	{ action = "CINEMATIC_VISION_CARD", label = L["Toggle Card Vision"],
		tip = L["Turns Card Vision on or off (its Enable Page switch)."] },
	{ action = "CINEMATIC_CAM_IDLE", label = L["AFK camera"], section = L["Cameras"],
		tip = L["Starts the AFK camera now."] },
	{ action = "CINEMATIC_CAM_COZY", label = L["Cozy camera"],
		tip = L["Starts the cozy camera now."] },
	{ action = "CINEMATIC_CAM_VISTA", label = L["Vista camera"],
		tip = L["Starts the vista camera now."] },
	{ action = "CINEMATIC_CAM_FISH", label = L["Fish camera"],
		tip = L["Starts the fish camera now."] },
	{ action = "CINEMATIC_CAM_TELE", label = L["Tele camera"],
		tip = L["Starts the tele camera now."] },
	{ action = "CINEMATIC_CAM_WALK", label = L["RP walk camera"],
		tip = L["Starts or stops the RP walk camera."] },
	{ action = "CINEMATIC_CAM_RUN", label = L["Auto-run camera"],
		tip = L["Starts or stops the auto-run camera."] },
	{ action = "CINEMATIC_CAM_DEATH", label = L["Death camera test"],
		tip = L["Pretends you're dead for 30 seconds to test the death camera."] },
	{ action = "CINEMATIC_SHOULDERCAM", label = L["Toggle Shoulder Cam"],
		tip = L["Turns the Shoulder Cam on or off (its Enable Page switch)."] },
	{ action = "CINEMATIC_STOPCAM", label = L["Stop the camera"],
		tip = L["Stops whichever of Cinematic's cameras is running now, however it started."] },
}
if ns.ChatCamCommand then -- (ChatCam.lua; on the Cameras tab, before Stop the camera)
	table.insert(KEYBINDS, #KEYBINDS, { action = "CLICK CinematicChatTargetButton:LeftButton",
		label = L["Target the last speaker"],
		tip = L["Targets the last NPC who spoke near you."] })
end
-- Your own scenes' keys (a trigger on the Triggers page set to Scene key N).
-- (number: put in the label as the page is built, once it's translated.)
for n = 1, 5 do
	KEYBINDS[#KEYBINDS + 1] = { action = "CINEMATIC_CUSTOMTRIGGER" .. n, label = "Scene key %d", number = n,
		section = n == 1 and L["Scene keys"] or nil,
		tip = L["Plays your scenes that use this key."] }
end
-- The Frames tab: key groups (built in CreateKeybindsPanel, Frames.lua's
-- db.keyGroups) and then the tooltip keys. The rows a group can hold, by
-- the Standard Frames page's tabs, for its frame picker: ns.FRAME_KEY_ROWS,
-- the rows a Mouseover group can hold (not the Highlight rows: game
-- settings, no frame). (Single frames had keys of their own before key
-- groups: those still work, and move into a group of their own at login,
-- Frames.lua; their names here for the "was bound to" line.)
do
	local HEADINGS = {
		{ "units", L["Unit frames"] }, { "prd", L["Personal Resource Display"] }, { "bars", L["Action bars"] },
		{ "combat", L["Trackers"] }, { "interface", L["Info and menus"] }, { "minimap", L["Minimap"] },
		{ "party", L["Party frames (not raid-style)"] }, { "raid", L["Raid frames"] },
		{ "rsparty", L["Party frames (raid-style)"] }, { false, L["Other"] },
	}
	local known = { highlight = true }
	for _, heading in ipairs(HEADINGS) do if heading[1] then known[heading[1]] = true end end
	ns.FRAME_KEY_ROWS = {}
	for _, heading in ipairs(HEADINGS) do
		local page = heading[1]
		local picks = { heading = heading[2] }
		ns.FRAME_KEY_ROWS[#ns.FRAME_KEY_ROWS + 1] = picks
		for _, item in ipairs(ns.HOVER_ROWS) do
			local itemPage = item.page
			if not (itemPage and known[itemPage]) then itemPage = false end
			if itemPage == page and itemPage ~= "highlight" then
				picks[#picks + 1] = item
			end
		end
	end
	for _, item in ipairs(ns.COMBAT_SHOW) do
		_G["BINDING_NAME_CLICK " .. ns.FRAME_KEY_BUTTON .. ":" .. item.key] = (L["Hide/show: %s"]):format(item.label)
	end
end

-- (The tooltip keys under the key groups, on the Frames tab, under a heading of their own.)
for _, each in ipairs({
	{ action = "CINEMATIC_SHOWTOOLTIPS", label = L["Show hidden tooltips"], heading = L["Tooltips"],
		section = L["Frames"], clearAll = true,
		tip = L["Hold to see tooltips that are hidden."] },
	{ action = "CINEMATIC_TOGGLETOOLTIPS", label = L["Toggle tooltip hiding"],
		tip = L["Turns the Tooltips page on or off (its Enable Page switch)."] },
}) do KEYBINDS[#KEYBINDS + 1] = each end
local IGNORED_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true,
}
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local keybindButtons = {}
local listening -- the slot button waiting for a key, if any

local function KeyText(key)
	return GetBindingText and GetBindingText(key) or key
end

local frameKeyLabels = {} -- (the Frames tab's row names: "hidden" or "shown" after one forced by its key)
local function RefreshKeybinds()
	for _, each in ipairs(frameKeyLabels) do
		local state = ns.FrameKeyState(each.key)
		each.label:SetText(state == "hide" and each.text .. " |cffff6060(" .. L["hidden"] .. ")|r"
			or state == "show" and each.text .. " |cff60ff60(" .. L["shown"] .. ")|r" or each.text)
	end
	for _, button in ipairs(keybindButtons) do
		local key = select(button.slot, GetBindingKey(button.action))
		if button == listening then
			button:SetText(L["Press a key"])
		else
			button:SetText(key and KeyText(key) or L["|cff808080Not bound|r"])
		end
	end
end

ns.RefreshKeybindsPage = RefreshKeybinds -- (a frame's key pressed: its "hidden", Frames.lua)

local function StopListening()
	if listening then
		listening:EnableKeyboard(false)
		listening:UnlockHighlight()
		listening = nil
	end
	RefreshKeybinds()
end

-- Puts key (or nothing) in the button's slot, replacing what was there. The
-- game lists an action's keys in the order they were bound, so all of them
-- are unbound and bound again in slot order: binding just the new key would
-- add it at the end, and a key set in slot 1 would show up in slot 2. (A
-- slot with nothing before it takes the first free one.)
local function Bind(button, key)
	StopListening()
	if InCombatLockdown() then
		ns.Print(L["keybinds can't be changed in combat"])
		return
	end
	local action = button.action
	local keys = { GetBindingKey(action) }
	if key then
		local previous = GetBindingAction(key)
		if previous and previous ~= "" and previous ~= action then
			ns.Print(L["%s was bound to %s and now isn't"]:format(KeyText(key),
				_G["BINDING_NAME_" .. previous] or previous))
		end
	end
	for _, old in ipairs(keys) do
		SetBinding(old)
	end
	local wanted = {}
	for i = 1, math.max(#keys, button.slot) do
		if i == button.slot then
			wanted[#wanted + 1] = key -- (nil when clearing: adds nothing)
		elseif keys[i] and keys[i] ~= key then -- (the key moving here from the other slot)
			wanted[#wanted + 1] = keys[i]
		end
	end
	for _, k in ipairs(wanted) do
		SetBinding(k, action)
	end
	SaveBindings(GetCurrentBindingSet())
	RefreshKeybinds()
end

local function WithModifiers(key)
	if IsShiftKeyDown() then key = "SHIFT-" .. key end
	if IsControlKeyDown() then key = "CTRL-" .. key end
	if IsAltKeyDown() then key = "ALT-" .. key end
	return key
end

local function CreateKeybindButton(parent, action, slot)
	local button = ns.PanelButton(parent)
	button:SetSize(140, 22)
	button.action, button.slot = action, slot
	button:RegisterForClicks("AnyUp")
	button:SetScript("OnClick", function(self, mouseButton)
		if self == listening and MOUSE_KEYS[mouseButton] then
			Bind(self, WithModifiers(MOUSE_KEYS[mouseButton]))
		elseif mouseButton == "RightButton" then
			Bind(self, nil)
		elseif self == listening then
			StopListening()
		else
			StopListening()
			listening = self
			self:EnableKeyboard(true)
			self:LockHighlight()
			RefreshKeybinds()
		end
	end)
	button:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			StopListening()
		elseif not IGNORED_KEYS[key] then
			Bind(self, WithModifiers(key))
		end
	end)
	-- Setting OnKeyDown turns keyboard input on, which would have every slot
	-- grab the next key pressed on this page; only the clicked one listens.
	button:EnableKeyboard(false)
	Tooltip(button, L["Click, then press a key; right-click to clear."])
	keybindButtons[#keybindButtons + 1] = button
	return button
end

local function CreateKeybindsPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Keybinds"])
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title,
		L["Keys for Cinematic, the same as in the game's Key Bindings under AddOns."])

	-- Each section a folder tab of its own (ns.FolderTabs), its rows in a body
	-- on the panel under them, the one picked shown: search still finds the
	-- rest, and picks their tab. The tab last picked is kept across reloads
	-- (SectionState, open its number: section names change with the language).
	local SECTION_WIDTH = 530 -- (a row: its label, both slots and its "?")
	local sections = {}
	local picked = { id = "Keybinds/tab", open = 1 }
	local panelTop = CreateFrame("Frame", nil, content)
	panelTop:SetSize(1, 1)
	local panel, ShowTab
	local function Layout()
		SectionState.Restore(picked)
		local shown = sections[picked.open] and picked.open or 1
		for i, section in ipairs(sections) do section.body:SetShown(i == shown) end
		ShowTab(shown)
		panel:SetPoint("BOTTOMRIGHT", sections[shown].last, "BOTTOMLEFT", SECTION_WIDTH + 12, -12)
		FitContentHeight(content)
	end
	local function Pick(i)
		StopListening() -- (a slot waiting for a key may be on the tab going away)
		SectionState.Save(picked, i)
		Layout()
	end

	-- Key groups (the Frames tab, above the frames' own keys): a key for the
	-- frames you pick, showing or hiding just those (Frames.lua's
	-- db.keyGroups). Each group: its name, two key slots, delete, and its
	-- frames in a menu of ticks by heading. Laid out again on every change;
	-- the rows below hang on its box, so they move with it.
	local function BuildKeyGroups(body, above)
		local WIDTH, CARD, GAP = SECTION_WIDTH - 12, 54, 6
		local KEY_W = 130
		-- Heading, with New key group at its right; a line on what they do under it.
		local heading = Label(body, "GameFontNormal", L["Key groups"])
		heading:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 4, -20) -- (above: the Reset tick, 4 left)
		local add = ns.PanelButton(body)
		add:SetSize(KEY_W * 2 + 6, 22)
		add:SetText(L["New key group"])
		add:SetPoint("LEFT", heading, "LEFT", WIDTH - 2 - 22 - 4 - (KEY_W * 2 + 6), 0)
		Tooltip(add, L["A key group of your own: name it, set its key and pick its frames."])
		local intro = Label(body, "GameFontDisableSmall", L["Press a group's key to hide its frames, again to bring " ..
			"them back, in CineMode or out. They start as your Hover Groups."])
		intro:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
		intro:SetWidth(WIDTH)
		intro:SetJustifyH("LEFT")
		local box = CreateFrame("Frame", nil, body)
		box:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -8)
		box:SetSize(WIDTH, 30)
		local rows = {}
		local LayoutGroups -- (below)
		-- A group's frames: the picked rows' names (all of them: the card's
		-- line cuts it short, its tooltip shows the rest).
		local function MembersText(group)
			local names = {}
			for _, picks in ipairs(ns.FRAME_KEY_ROWS or {}) do
				for _, item in ipairs(picks) do
					for _, member in ipairs(group.members or {}) do
						if member == item.key then names[#names + 1] = item.hoverLabel or item.label break end
					end
				end
			end
			return names
		end
		local function HasMember(group, key)
			for i, member in ipairs(group.members or {}) do
				if member == key then return i end
			end
		end
		-- A card per group: its icon down the left; its name and keys on the
		-- top line, delete at the end; its frames under the name, and the
		-- menu that picks them under the keys.
		local function MakeRow()
			local row = CreateFrame("Frame", nil, box)
			row:SetSize(WIDTH, CARD)
			row.bg = row:CreateTexture(nil, "BACKGROUND")
			row.bg:SetAllPoints()
			row.bg:SetColorTexture(1, 1, 1, 0.04)
			row.edge = row:CreateTexture(nil, "BORDER")
			row.edge:SetPoint("TOPLEFT")
			row.edge:SetPoint("BOTTOMLEFT")
			row.edge:SetWidth(2)
			row.edge:SetColorTexture(0.8, 0.65, 0.2, 0.6)
			-- (Its icon: the Hover Group's it was copied from, else a key.)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(36, 36)
			row.icon:SetPoint("LEFT", 9, 0)
			row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			row.name = ns.SkinEditBox(CreateFrame("EditBox", nil, row, "InputBoxTemplate"))
			row.name:SetSize(WIDTH - 22 - KEY_W * 2 - 6 - 80, 20)
			row.name:SetPoint("TOPLEFT", 58, -5)
			row.name:SetAutoFocus(false)
			row.name:SetMaxLetters(40)
			row.name:SetFontObject("GameFontNormal")
			row.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
			row.name:SetScript("OnEscapePressed", function(self)
				self:SetText(row.group and row.group.name or "")
				self:ClearFocus()
			end)
			row.name:SetScript("OnEditFocusLost", function(self)
				local text = (self:GetText() or ""):match("^%s*(.-)%s*$")
				local group = row.group
				if group and text ~= "" and text ~= group.name then
					group.name = text
					ns.NameKeyGroupBinding(group)
				end
				self:SetText(group and group.name or "")
			end)
			Tooltip(row.name, L["The group's name: click to change it."])
			row.delete = ns.SkinClose(CreateFrame("Button", nil, row, "UIPanelCloseButton"))
			row.delete:SetSize(22, 22)
			row.delete:SetPoint("TOPRIGHT", -2, -4)
			Tooltip(row.delete, L["Deletes this group and its keys."])
			row.second = CreateKeybindButton(row, "", 2)
			row.second:SetWidth(KEY_W)
			row.second:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
			row.first = CreateKeybindButton(row, "", 1)
			row.first:SetWidth(KEY_W)
			row.first:SetPoint("RIGHT", row.second, "LEFT", -6, 0)
			-- ("hidden" or "shown" while its key has them, on the frames' line: RefreshKeybinds.)
			row.state = Label(row, "GameFontHighlightSmall", "")
			row.state:SetPoint("TOPRIGHT", row.first, "BOTTOMLEFT", -10, -8)
			row.stateEntry = { label = row.state, text = "" }
			frameKeyLabels[#frameKeyLabels + 1] = row.stateEntry
			-- Its frames, one line (cut short; the tooltip has them all).
			row.frames = Label(row, "GameFontHighlightSmall", "")
			row.frames:SetPoint("TOPLEFT", 64, -32)
			row.frames:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
			row.frames:SetJustifyH("LEFT")
			row.frames:SetWordWrap(false)
			row.framesHit = CreateFrame("Frame", nil, row)
			row.framesHit:SetAllPoints(row.frames)
			row.framesHit:SetScript("OnEnter", function(self)
				local names = row.group and MembersText(row.group) or {}
				if #names == 0 then return end
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(row.group.name or "", 1, 0.82, 0)
				GameTooltip:AddLine(table.concat(names, ", "), 1, 1, 1, true)
				GameTooltip:Show()
			end)
			row.framesHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
			-- The frame picker: a button with the count, its menu of ticks (by
			-- heading) made only when it's clicked: a dropdown per group built
			-- every group's 200-odd ticks each time the page was laid out.
			if MenuUtil and ns.ContextMenu then
				local menu = ns.PanelButton(row)
				row.menu = menu
				menu:SetSize(KEY_W * 2 + 6, 20)
				menu:SetPoint("TOPLEFT", row.first, "BOTTOMLEFT", 0, -4)
				menu.searchSkip = true -- (it shows a count, not a label)
				menu:SetScript("OnClick", function(self)
					local group = row.group
					if not group then return end
					ns.ContextMenu(self, function(_, root)
						for _, picks in ipairs(ns.FRAME_KEY_ROWS or {}) do
							local shown = {}
							for _, item in ipairs(picks) do
								if ns.OptionAvailable(item) then shown[#shown + 1] = item end
							end
							if #shown > 0 then
								local sub = root:CreateButton(picks.heading)
								for _, item in ipairs(shown) do
									sub:CreateCheckbox(item.hoverLabel or item.label,
										function() return HasMember(group, item.key) ~= nil end,
										function()
											group.members = group.members or {}
											local at = HasMember(group, item.key)
											if at then
												table.remove(group.members, at)
											else
												group.members[#group.members + 1] = item.key
											end
											ns.KeyGroupsChanged()
											LayoutGroups()
											return MenuResponse and MenuResponse.Refresh
										end)
								end
							end
						end
					end)
				end)
				Tooltip(menu, L["Pick the frames this group's key shows and hides."])
			end
			return row
		end
		add:SetScript("OnClick", function()
			-- (At the top, right under the button, its name picked to type over.)
			-- (Named Key group 1, 2...: the lowest number no group's name has.)
			local taken = {}
			for _, group in ipairs(ns.KeyGroups()) do taken[group.name or ""] = true end
			local number = 1
			while taken[L["Key group %d"]:format(number)] do number = number + 1 end
			ns.AddKeyGroup(L["Key group %d"]:format(number), nil, nil, true)
			LayoutGroups()
			local first = rows[1]
			if first then
				first.name:SetFocus()
				first.name:HighlightText()
			end
		end)
		function LayoutGroups()
			StopListening()
			local groups = ns.KeyGroups()
			local y = 0
			for index, group in ipairs(groups) do
				local row = rows[index] or MakeRow()
				rows[index] = row
				row.group = group
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
				row:Show()
				row.name:SetText(group.name or "")
				row.name:SetCursorPosition(0)
				row.icon:SetTexture(group.icon or "Interface\\Icons\\INV_Misc_Key_03")
				local names = MembersText(group)
				row.frames:SetText(#names > 0 and table.concat(names, ", ")
					or "|cff808080" .. L["No frames yet: pick them on the right"] .. "|r")
				local action = "CLICK " .. ns.FRAME_KEY_BUTTON .. ":g" .. tostring(group.id)
				row.first.action, row.second.action = action, action
				row.stateEntry.key = "g" .. tostring(group.id)
				row.delete:SetScript("OnClick", function()
					ns.DeleteKeyGroup(index)
					LayoutGroups()
				end)
				if row.menu then
					row.menu:SetText(L["Pick frames (%d)"]:format(#names))
				end
				y = y + CARD + GAP
			end
			for i = #groups + 1, #rows do
				rows[i]:Hide()
				rows[i].group = nil
				rows[i].stateEntry.key = nil
			end
			box:SetHeight(math.max(1, y - GAP))
			RefreshKeybinds()
			if panel then Layout() end -- (the page, once its tabs are made)
		end
		box:SetScript("OnShow", LayoutGroups)
		LayoutGroups()
		return box
	end

	local section, pendingHeading
	for _, bind in ipairs(KEYBINDS) do
		if bind.section then
			SetSection(content, bind.section)
			local number = #sections + 1
			section = { tab = bind.section, body = CreateFrame("Frame", nil, content) }
			section.body:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12, -12)
			section.body:SetSize(1, 1)
			section.body.searchAlways = true
			section.body.openSection = function() Pick(number) end
			section.last = section.body
			sections[number] = section
		end
		-- (The Frames tab: a button that hands every frame its key set back to its row.)
		if bind.clearAll then
			local body = section.body
			-- (Ticked to start with: a frame its key showed or hid is back to its
			-- row after a reload or logging in. Read as the settings load, Core.lua.)
			local reset = Check(body, "frameKeysReset", L["Reset frame keys after a reload"],
				L["Frames you showed or hid with their keys go back to normal after a reload."])
			-- (This page's opening doesn't refresh the settings' controls: its own tick, as it's saved.)
			reset:HookScript("OnShow", function(self) self:Refresh() end)
			reset:SetPoint("TOPLEFT", body, "BOTTOMLEFT", -4, -2)
			local clear = ns.PanelButton(body)
			clear:SetSize(200, 22)
			clear:SetText(L["Back to their Show in rows"])
			-- (Beside the tick, over the key columns.)
			clear:SetWidth(266)
			clear:SetPoint("LEFT", reset, "LEFT", SECTION_WIDTH - 12 - 2 - 22 - 4 - 266 + 4, 0)
			clear:SetScript("OnClick", function() ns.ShowAllFrameKeys() end)
			Tooltip(clear, L["Every frame shown or hidden by its key below goes back to showing as its Show in " ..
				"row says."])
			section.last = BuildKeyGroups(body, reset)
		end
		-- (A heading over a group of rows: the Frames tab's, by the Standard Frames page's tabs.)
		if bind.heading and (not bind.show or bind.show()) then
			local heading = Label(section.body, "GameFontNormal", bind.heading)
			heading:SetPoint("TOPLEFT", section.last, "BOTTOMLEFT", 0, section.last == section.body and -4 or -18)
			section.last = heading
		elseif bind.heading then
			pendingHeading = bind.heading
		end
		-- (A key for something this client doesn't have: no row.)
		if not bind.show or bind.show() then
			local body = section.body
			-- (Its heading's first row wasn't on this client: the heading over the next.)
			if pendingHeading and not bind.heading then
				local heading = Label(body, "GameFontNormal", pendingHeading)
				heading:SetPoint("TOPLEFT", section.last, "BOTTOMLEFT", 0, section.last == body and -4 or -18)
				section.last = heading
			end
			pendingHeading = nil
			local label = Label(body, "GameFontHighlight", bind.number and bind.label:format(bind.number) or bind.label)
			label:SetPoint("TOPLEFT", section.last, "BOTTOMLEFT", 0, section.last == body and -4 or -12)
			label:SetWidth(200)
			if bind.frameKey then
				frameKeyLabels[#frameKeyLabels + 1] = { label = label, key = bind.frameKey, text = bind.label }
			end
			local first = CreateKeybindButton(body, bind.action, 1)
			first:SetPoint("LEFT", label, "RIGHT", 10, 0)
			local second = CreateKeybindButton(body, bind.action, 2)
			second:SetPoint("LEFT", first, "RIGHT", 8, 0)
			-- What the key does, behind a "?" after its slots.
			section.last = PageIntro(body, second, bind.tip, label)
		end
	end

	-- The tabs, as high as their rows, under the title.
	local list, _, base, height = {}
	for i, each in ipairs(sections) do list[i] = { each.tab } end
	panel, _, ShowTab, base, height = ns.FolderTabs(content, list, Pick, nil, SECTION_WIDTH + 8)
	panelTop:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16 - height)
	panel:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
	-- (On panelTop, not the panel: the panel's bottom hangs on the rows under them.)
	base:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
	Layout()

	canvas:RegisterEvent("UPDATE_BINDINGS")
	canvas:SetScript("OnEvent", RefreshKeybinds)
	canvas:SetScript("OnShow", PageShown(function()
		RefreshKeybinds()
		Layout() -- (as last left, once the settings have loaded)
	end, content))
	canvas:SetScript("OnHide", StopListening)
	canvas:Hide()
	RegisterSubpage(canvas, "Keybinds")
end

ns.RefreshOptions = function() Refresh() end
-- Whether one of our settings pages is on the screen (our own canvases: the
-- game's settings window says nothing on Forever, its shown state secret).
function ns.OurSettingsShown()
	return next(ns.shownSettingsCanvases) ~= nil
end

-- Settings asked for in a fight that couldn't open: opened once it ends.
local openAfterFight = CreateFrame("Frame")
openAfterFight:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	ns.OpenOptions(self.page)
end)

-- Opens the settings, at a sub-page by name if given (else the main page).
-- In combat Settings.OpenToCategory is blocked for addons ("Interface action
-- failed because of an AddOn": its ShowUIPanel is). Where the window itself
-- isn't protected it's shown and the page picked directly; where it is
-- (retail, in a fight), it opens when the fight ends.
-- (Pages that went into others: their old names, for links and saved ones.)
local MOVED_PAGES = { ["Combat Vision"] = "Card Vision", ["Story Vision"] = "Card Vision", ["Cards"] = "Card Vision", ["Combat Style"] = "Card Style",
	["Story Style"] = "Card Style" }
-- A settings page's canvas by its name (RegisterSubpage's), for the test
-- commands that open and read pages (StyleSixTest.lua).
function ns.SettingsPageCanvas(name) return subpages[name] or (ns.settingsCanvases and ns.settingsCanvases[name]) end

function ns.OpenOptions(page)
	page = MOVED_PAGES[page] or page
	-- (a UI Manager page: that page, then UI Manager open at it)
	local hubName = page and HubTab(page)
	page = hubName or page
	-- (some pages are registered by their name as shown)
	if page and not subpages[page] and subpages[L[page]] then page = L[page] end
	-- (A hub's icon: opened on its own line in the left list, lit there.)
	local line = hubName and menu.lineNow[hubName]
	if InCombatLockdown() then
		local panel = category and SettingsPanel
		if panel and panel.SelectCategory and not panel:IsProtected() then
			panel:Show()
			panel:SelectCategory(line or subpages[page] or category)
		elseif not (panel and panel:IsShown()) then
			openAfterFight.page = page
			openAfterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
			ns.Print(L["settings can't be opened in combat; they'll open when the fight ends"])
		end
		return
	end
	if category and Settings and Settings.OpenToCategory then
		local target = line or subpages[page] or category
		Settings.OpenToCategory(target:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		-- Called twice: the first call can land on the wrong page in old clients.
		InterfaceOptionsFrame_OpenToCategory(subpages[page] or mainCanvas)
		InterfaceOptionsFrame_OpenToCategory(subpages[page] or mainCanvas)
	end
end

-- A page opened at one of its rows: scrolled to it and glowing, as a search
-- match is (the Why window's links). label: the row's text, matched whole;
-- not found on the page, the page alone opens.
function ns.OpenOptionsAt(page, label, settingKey)
	page = MOVED_PAGES[page] or page
	local found
	for _, each in ipairs(searchPages) do
		if each.key == page or (page and each.key == L[page]) then found = each break end
	end
	-- (By its setting's key first: that control, on its page or any.)
	if settingKey and not InCombatLockdown() and ns.OpenSettingByKey(settingKey, found) then return end
	local wanted = SearchText(label)
	if found and wanted and not InCombatLockdown() then
		wanted = wanted:lower()
		for _, entry in ipairs((BuildSearchIndex({ found }))) do
			if entry.lower == wanted and entry.edges then
				ShowMatch(entry)
				return
			end
		end
	end
	ns.OpenOptions(page)
end

-- A setting's own control, by its key (its id: nfHealthPlayer, and so
-- on): its page opened, scrolled to it and glowing. page: looked on first
-- (a key can have a control on more than one page). False: none found.
function ns.OpenSettingByKey(settingKey, page)
	if type(settingKey) ~= "string" or settingKey == "" then return false end
	local _, keyed = BuildSearchIndex(page and { page } or nil)
	local entry = keyed[settingKey]
	if not entry and page then
		_, keyed = BuildSearchIndex()
		entry = keyed[settingKey]
	end
	if not entry then return false end
	ShowMatch(entry)
	return entry.text, entry.page.name or "Cinematic"
end

-- /cine debug ids: every page's controls, those with an id (/cine find <id>)
-- and those without one yet (a checkbox, slider, box or button you could
-- click, made without a setting's key or a grid row), as text to copy.
-- (Hidden ones too: a closed section's, another tab's.)
-- ns.SettingIds(): the lines for both lists ("id | page | label" and "page |
-- label"), and the settings without one (the offline check's, before a
-- release): { page, label } each for a checkbox, slider or number box that
-- isn't marked noSettingId (a control with no one setting of its own: a
-- row's, a theme's or a wheel's value, a tab's switch).
local SETTING_CONTROLS = { CheckButton = true, Slider = true, EditBox = true }
function ns.SettingIds()
	ns.MakeLazyPages("the setting ids")
	Refresh()
	local CONTROLS = { CheckButton = true, Slider = true, EditBox = true, Button = true }
	local with, without, missing, seen = {}, {}, {}, {}
	for _, page in ipairs(searchPages) do
		local pageName = page.name or "Cinematic"
		local function walk(frame)
			if frame.searchSkip then return end
			local id = ns.SettingIdOf(frame)
			if not id and frame.RowId then
				local ok, rowId = pcall(frame.RowId)
				id = ok and type(rowId) == "string" and ("row:" .. rowId) or nil
			end
			local label = SearchText(frame.searchLabel)
			-- (A page's Enable switch: its checkbox hidden, its label taken off,
			-- the switch in the page's header: named so, not left blank.)
			if frame.hiddenSwitch then label = "Enable Page (page header switch)" end
			local kind = frame:GetObjectType()
			if id and not seen[id] then
				seen[id] = true
				with[#with + 1] = ("%s | %s | %s"):format(id, pageName, label or "")
			elseif not id and label and CONTROLS[kind] then
				without[#without + 1] = ("%s | %s"):format(pageName, label)
				if SETTING_CONTROLS[kind] and not frame.noSettingId then
					missing[#missing + 1] = { page = pageName, label = label }
				end
			end
			for _, child in ipairs({ frame:GetChildren() }) do walk(child) end
		end
		walk(page.canvas.content)
	end
	return with, without, missing
end
function ns.SettingIdsReport()
	local with, without = ns.SettingIds()
	table.sort(with)
	local out = { ("Cinematic %s: %d ids, %d controls without one"):format(ns.Version and ns.Version() or "?",
		#with, #without), "", "== Without an id (page | label) ==" }
	for _, line in ipairs(without) do out[#out + 1] = line end
	out[#out + 1] = ""
	out[#out + 1] = "== Ids (id | page | label): /cine find <id> =="
	for _, line in ipairs(with) do out[#out + 1] = line end
	ns.ShowReportText("Setting ids", "Press Ctrl+C to copy.", table.concat(out, "\n"))
end

-- The key (Bindings.xml): opens the settings at the Cinematic page last shown,
-- or closes them. Close(true): without it the window goes back to the Game
-- Menu, and ToggleGameMenu is blocked for addons. In a fight it goes as
-- ns.OpenOptions does: hidden directly where the window isn't protected, left
-- open where it is (Escape still closes it).
function Cinematic_ToggleSettings()
	local panel = SettingsPanel or InterfaceOptionsFrame
	if not (panel and ns.Flag(panel:IsShown())) then
		ns.OpenOptions(ns.lastOptionsPage)
	elseif InCombatLockdown() then
		if not panel:IsProtected() then panel:Hide() end
	elseif panel.Close then
		panel:Close(true) -- (through GuardGamepadClose's reload, in gamepad mode)
	else
		HideUIPanel(panel)
	end
end

-- Whether there's a settings page by that name on this client (a hub's
-- page or a page of its own), as ns.OpenOptions takes it.
function ns.HasOptionsPage(page)
	page = MOVED_PAGES[page] or page
	return (ns.IsHubPage ~= nil and ns.IsHubPage(page)) or subpages[page] ~= nil or subpages[L[page]] ~= nil
end

-- The Cinematic page the settings window shows, by name as ns.OpenOptions
-- takes it ("" for the main page), and its scroll frame if it has one; nil
-- with none shown. (DevReload.lua: reopened after a reload.)
function ns.ShownOptionsPage()
	for _, page in ipairs(searchPages) do
		if page.key and ns.Flag(page.canvas:IsVisible()) then return page.key, page.canvas.scroll end
	end
	if mainCanvas and ns.Flag(mainCanvas:IsVisible()) then return "", mainCanvas.scroll end
end

-- Sub-page: mouseover. Groups of frames that come up together when you
-- mouse over any of them (db.hoverGroups, Frames.lua's ns.GetHoverGroups),
-- and the events that bring each group up besides.
-- The text typed into a popup's edit box (named differently on some clients).
local function PopupText(popup)
	local box = popup.editBox or popup.EditBox or (popup.GetEditBox and popup:GetEditBox())
	return box and (box:GetText() or ""):match("^%s*(.-)%s*$") or "", box
end

-- The popup an edit box is in (on some clients it sits inside a holder frame).
local function PopupOf(box)
	local frame = box
	while frame and not frame.which do
		frame = frame:GetParent()
	end
	return frame
end

-- A popup asking for a profile name: Enter accepts, Escape cancels.
-- opts: initial(data) for the text it starts with (else data), maxLetters,
-- and width for a wider box than usual (put back after: the box is shared).
local function NamePopup(text, accept, opts)
	opts = opts or {}
	local usualWidth
	return {
		text = text, button1 = ACCEPT, button2 = CANCEL,
		hasEditBox = true, maxLetters = opts.maxLetters or 32,
		OnShow = function(self, data)
			local _, box = PopupText(self)
			if box then
				if opts.width then
					usualWidth = box:GetWidth()
					-- (No wider than the popup: the game doesn't widen it to fit,
					-- so a wider box ran out past its edges.)
					local room = (self:GetWidth() or 0) - 50
					box:SetWidth(room > usualWidth and math.min(opts.width, room) or usualWidth)
				end
				box:SetText((opts.initial and opts.initial(data)) or data or "")
				box:HighlightText()
				box:SetFocus()
			end
		end,
		OnHide = function(self)
			local _, box = PopupText(self)
			if box and usualWidth then
				box:SetWidth(usualWidth)
				usualWidth = nil
			end
		end,
		-- accept returns true to keep the popup open (a name that can't be used).
		OnAccept = function(self, data) return accept(PopupText(self), data) end,
		EditBoxOnEnterPressed = function(box)
			local popup = PopupOf(box)
			if popup and not accept(PopupText(popup), popup.data) then
				popup:Hide()
			end
		end,
		EditBoxOnEscapePressed = function(box)
			local popup = PopupOf(box)
			if popup then popup:Hide() end
		end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
end

ns.NamePopup = NamePopup -- (Vitals Vision's themes too: LowHealth.lua)

-- Checks a new profile name (old: the one being renamed); says why not on
-- screen if it can't be used. Names differing only in capitals count as the
-- same (/cine profile ignores them).
local function NameFree(name, old)
	local taken = ns.FindProfile(name)
	local why
	if name == "" then
		why = L["A profile needs a name."]
	elseif taken and taken ~= old then
		why = L["There's already a profile called %s."]:format(ns.ProfileLabel(taken))
	end
	if why then
		UIErrorsFrame:AddMessage(why, 1, 0.1, 0.1)
		ns.Print(why)
		return false
	end
	return true
end

-- (For the General page's cameras too: CameraManager.lua.)
ns.NamePopup = NamePopup
StaticPopupDialogs.CINEMATIC_PROFILE_RENAME = NamePopup(L["Rename the profile:"], function(name, old)
	if not old or name == old then return end
	if not NameFree(name, old) then return true end
	ns.RenameProfile(old, name)
	Refresh()
end)
StaticPopupDialogs.CINEMATIC_PROFILE_NOTE = NamePopup(L["Describe the profile:"], function(text, name)
	ns.SetProfileNote(name, text)
	Refresh()
end, { initial = function(name) return ns.ProfileNote(name) or "" end, maxLetters = 200, width = 360 })
StaticPopupDialogs.CINEMATIC_PROFILE_DELETE = {
	text = L["Delete the profile %s?"],
	button1 = YES, button2 = NO,
	OnAccept = function(_, name)
		ns.DeleteProfile(name)
		Refresh()
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs.CINEMATIC_PROFILE_RESET = {
	text = L["Put the profile %s back to how it started? Every change you've made to it goes."],
	button1 = YES, button2 = NO,
	OnAccept = function()
		ns.ResetSettings()
		Refresh()
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
-- (A profile with a reset point of the player's goes back to that: Profiles.lua.)
StaticPopupDialogs.CINEMATIC_PROFILE_RESET_POINT = {
	text = L["Put the profile %s back to how you last saved it? Changes you've made since then go."],
	button1 = YES, button2 = NO,
	OnAccept = function()
		ns.ResetSettings()
		Refresh()
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
-- Save: the profile as it is now becomes what Reset goes back to (the one
-- it replaces kept among the backups: Profiles.lua). No question asked.
local function SaveResetPoint(name)
	ns.SaveResetPoint(name)
	ns.Print(L["profile %s saved: Reset puts it back to this"]:format(ns.ProfileLabel(name)))
	Refresh()
end
-- Reset profile's question: back to the reset point, or to how it started.
local function AskResetProfile()
	local label = ns.ProfileLabel(ns.ActiveProfile())
	StaticPopup_Show(ns.HasResetPoint() and "CINEMATIC_PROFILE_RESET_POINT" or "CINEMATIC_PROFILE_RESET", label)
end
-- Reset Everything on the left, Reset Settings on the right; Reset Everything
-- asks again, as nothing it deletes comes back (ns.ResetAddon).
-- (Their paragraphs read left-aligned; centred again on hide, as the game
-- reuses the popup frames for its own.)
local function PopupFontString(popup)
	return popup.text or popup.Text or (popup.GetTextFontString and popup:GetTextFontString())
end
-- (The game's own width back on hide: see WidenPopupText.)
local function AlignPopupText(popup, side)
	local text = PopupFontString(popup)
	if not (text and text.SetJustifyH) then return end
	text:SetJustifyH(side)
	if side == "CENTER" and popup.cineTextWidth then
		text:SetWidth(popup.cineTextWidth)
		popup.cineTextWidth = nil
	end
end
-- The text wider than the game's 290 (narrow in a three-button popup, 440
-- wide), and the popup's height by what that saves. After the game has
-- built and sized the popup (it sets the width back as it shows one), and
-- once more a frame later in case it lays it out again.
local function WidenPopupText(popup, which, width)
	local text = PopupFontString(popup)
	if not (popup and popup.which == which and popup:IsShown() and text and text.SetWidth) then return end
	if math.abs(text:GetWidth() - width) < 1 then return end
	local before = text:GetHeight()
	popup.cineTextWidth = popup.cineTextWidth or text:GetWidth()
	text:SetWidth(width)
	popup:SetHeight(popup:GetHeight() + text:GetHeight() - before)
end
function ns.ShowResetPopup()
	local popup = StaticPopup_Show("CINEMATIC_ADDON_RESET")
	if not popup then return end
	WidenPopupText(popup, "CINEMATIC_ADDON_RESET", 400)
	C_Timer.After(0, function() WidenPopupText(popup, "CINEMATIC_ADDON_RESET", 400) end)
end
-- The question (the text's first line) centred over the left-aligned rest:
-- a line of its own on the popup, its place in the text left blank.
local function CenterPopupTitle(popup)
	local text = PopupFontString(popup)
	local full = text and text.GetText and text:GetText()
	if type(full) ~= "string" then return end
	local title, rest = full:match("^(.-)\n\n(.*)$")
	if not title then return end
	if not popup.cineTitle then
		popup.cineTitle = popup:CreateFontString(nil, "ARTWORK")
		popup.cineTitle:SetFontObject(text:GetFontObject() or "GameFontHighlight")
		popup.cineTitle:SetJustifyH("CENTER")
	end
	popup.cineTitle:ClearAllPoints()
	popup.cineTitle:SetPoint("TOP", text, "TOP")
	popup.cineTitle:SetText(title)
	popup.cineTitle:Show()
	text:SetText("\n\n" .. rest)
end
StaticPopupDialogs.CINEMATIC_ADDON_RESET = {
	OnShow = function(self)
		AlignPopupText(self, "LEFT")
		CenterPopupTitle(self)
	end,
	OnHide = function(self)
		AlignPopupText(self, "CENTER")
		if self.cineTitle then self.cineTitle:Hide() end
	end,
	text = L["Reset Cinematic?\n\nReset Settings: every setting goes back to how it was on install, and you start on " ..
		"the default profile. Nothing you made is deleted: your own profiles, cameras, scripts, themes, rules, " ..
		"wheels and backups stay, and so do flight times and what Cinematic has learned as you played.\n\n" ..
		"Reset EVERYTHING: deletes all of it, as on a fresh install.\n\n" ..
		"Either way the UI reloads, and Cinematic's Edit Mode layouts are removed so your own comes back."],
	button1 = L["Reset EVERYTHING"], button2 = CANCEL, button3 = L["Reset Settings"],
	OnAccept = function() StaticPopup_Show("CINEMATIC_ADDON_RESET_ALL") end,
	OnAlt = function() ns.ResetAddon(true) end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs.CINEMATIC_ADDON_RESET_ALL = {
	text = L["Delete everything in Cinematic? Your own profiles, cameras, scripts, themes, rules, wheels and " ..
		"backups are deleted for good, along with every setting. This can't be undone."],
	button1 = L["Reset EVERYTHING"], button2 = CANCEL,
	OnShow = function(self) AlignPopupText(self, "LEFT") end,
	OnHide = function(self) AlignPopupText(self, "CENTER") end,
	OnAccept = function() ns.ResetAddon() end,
	timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
}

-- The game's right-click menus (not on Classic Era): a profile card's.
local PROFILE_MENUS = MenuUtil and MenuUtil.CreateContextMenu and true or false

local function CreateProfilesPanel()
	local canvas, content = CreateScrollPage(true)

	local title = Label(content, "GameFontNormalLarge", L["Profiles"])
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title,
		L["A profile is a whole set of settings you can switch between."])

	-- Ticked, this character keeps the one it's on as its own.
	local perChar = Check(content, nil, L["Use a profile just for this character"],
		L["This character keeps its own profile."], function(value)
			ns.SetCharacterProfile(value)
			Refresh()
		end)
	perChar.noSettingId = true -- (the character's, not a profile setting: no id for /cine find)
	-- (With the profile your other characters use: the account's.)
	perChar.Refresh = function(self)
		self:SetChecked(ns.IsCharacterProfile())
		local text = self.Text or self.text
		if text and ns.GetDB() then
			text:SetText((L["Use a profile just for this character |cff808080(other characters use %s)|r"])
				:format(ns.ProfileLabel(ns.GetDB().profile or ns.ActiveProfile())))
		end
	end
	perChar:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -14)

	local header = Header(content, L["Profiles"], perChar, -12)
	header:SetPoint("TOPLEFT", perChar, "BOTTOMLEFT", 2, -12)

	-- Drawn as the welcome window is (Welcome.lua's flat look): a card per
	-- profile (its icon, name and a line) and one to start a new one, a box
	-- under them saying what the one pointed at does (a button's too, or else
	-- the active profile's), the welcome window's Customize panel, then flat
	-- buttons to manage and share. Clicking a card switches to it; clicking
	-- yours when it's active picks its icon.
	local S = ns.FlatStyle
	local WIDTH, GAP, PER_ROW, CARD_H = 580, 10, 4, 124
	local CARD_W = (WIDTH - (PER_ROW - 1) * GAP) / PER_ROW
	local LEVELS = {} -- built-in profile -> its welcome level (the card's line)
	for _, level in ipairs(ns.WELCOME_LEVELS) do LEVELS[level.profile] = level end
	local active -- (the gold one, or nil until a new player picks one)
	local cells = {}
	local tips = {} -- (every button's, to size the box)
	local Layout -- (below)
	-- (Any icon the game has: IconBrowser.lua.)
	local picker = ns.IconBrowser(canvas, function(name, file)
		ns.SetProfileIcon(name, file)
		Layout()
	end)

	local box = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate")
	box:SetSize(WIDTH, 56)
	S.Flat(box, S.BG)
	S.Skinnable(box)
	local about = S.Text(box, "GameFontHighlightSmall", "", S.SOFT, WIDTH - 24)
	about:SetPoint("TOPLEFT", 12, -10)
	about:SetSpacing(2)
	about.searchSkip = true -- (it changes with the mouse)

	-- A profile's description, with what a click on its card does.
	local function ProfileText(cell)
		local hint = cell.name ~= active and L["Click to switch to it."]
			or not ns.IsBuiltinProfile(cell.name) and L["Click to pick its icon."]
		if PROFILE_MENUS then
			hint = (hint and hint .. " " or "") .. L["Right-click for more."]
		end
		return "|cffffd100" .. ns.ProfileLabel(cell.name) .. "|r   " .. cell.tip
			.. (hint and "\n|cff808080" .. hint .. "|r" or "")
	end
	-- What the box says: the card or button pointed at, else the active profile.
	local function Describe(text)
		if text then
			about:SetText(text)
			return
		end
		for _, cell in ipairs(cells) do
			if cell:IsShown() and cell.name and cell.name == active then
				about:SetText(ProfileText(cell))
				return
			end
		end
		about:SetText(L["Pick a profile to switch to it."])
	end

	local function Card()
		local cell = CreateFrame("Button", nil, content, BackdropTemplateMixin and "BackdropTemplate")
		cell:SetSize(CARD_W, CARD_H)
		S.Flat(cell)
		S.Skinnable(cell)
		cell.icon = cell:CreateTexture(nil, "ARTWORK")
		cell.icon:SetSize(40, 40)
		cell.icon:SetPoint("TOP", 0, -14)
		cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		S.Rounded(cell, cell.icon)
		cell.label = S.Text(cell, "GameFontHighlightLarge", "", S.WHITE, CARD_W - 12)
		cell.label:SetJustifyH("CENTER")
		cell.label:SetWordWrap(false)
		cell.label:SetPoint("TOP", cell.icon, "BOTTOM", 0, -7)
		cell.line = S.Text(cell, "GameFontHighlightSmall", "", S.SOFT, CARD_W - 16)
		cell.line:SetJustifyH("CENTER")
		if cell.line.SetMaxLines then cell.line:SetMaxLines(3) end
		cell.line:SetPoint("TOP", cell.label, "BOTTOM", 0, -4)
		cell:SetScript("OnEnter", function(self)
			if self.name ~= active then self:SetBackdropBorderColor(unpack(S.LIT)) end
			Describe(self.name and ProfileText(self) or self.tip)
		end)
		cell:SetScript("OnLeave", function(self)
			if self.name ~= active then self:SetBackdropBorderColor(unpack(S.EDGE)) end
			Describe()
		end)
		return cell
	end

	-- The last card: a new profile of your own, from the settings you have now.
	local newTip = PROFILE_MENUS and L["Makes a copy of the active profile as your own."]
		or L["Makes a copy of the active profile as your own."]
	local newCard = Card()
	newCard.label:SetText(L["New profile"])
	newCard.line:SetText(L["From your settings now"])
	newCard.tip = newTip
	newCard.searchTip = newTip
	newCard.icon:Hide()
	-- (a plus where the icon goes: two thin bars)
	for _, size in ipairs({ { 20, 2 }, { 2, 20 } }) do
		local bar = newCard:CreateTexture(nil, "ARTWORK")
		bar:SetSize(size[1], size[2])
		bar:SetPoint("CENTER", newCard.icon, "CENTER")
		bar:SetColorTexture(unpack(S.DIM))
	end
	-- (Named after the one it starts from, no asking: My Cinema, or a copy of
	-- yours with a number; Rename is there for another name.)
	local function NewFromActive()
		local from = ns.ActiveProfile()
		local base = ns.IsBuiltinProfile(from) and L["My %s"]:format(ns.ProfileLabel(from)) or from
		local name, n = base, 1
		while ns.ProfileExists(name) do
			n = n + 1
			name = base .. " " .. n
		end
		ns.NewProfile(name)
		Refresh()
	end
	newCard:SetScript("OnClick", NewFromActive)
	tips[#tips + 1] = newTip

	local ProfileMenu -- (below)
	local function GetCell(i)
		if cells[i] then return cells[i] end
		local cell = Card()
		-- (a built-in that's been changed: a quiet tag in its corner)
		cell.changed = S.Text(cell, "GameFontHighlightSmall", L["(changed)"], S.DIM)
		cell.changed:SetPoint("TOPRIGHT", -6, -6)
		cell.changed.searchSkip = true
		cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		cell:SetScript("OnClick", function(self, mouse)
			if mouse == "RightButton" then
				ProfileMenu(self)
			elseif self.name ~= active then
				picker:Hide()
				if not ns.SetProfile(self.name) then return end -- (in a fight: it said so)
				ns.PreviewProfile(self.name)
				-- (Cinema: Vitals Vision's screen edges for a moment, as on the
				-- welcome window. Another profile ends that look at once.)
				if ns.StopVitalsFlash then ns.StopVitalsFlash() end
				local level = LEVELS[self.name]
				if level and level.flash == "vitals" and ns.FlashVitals then ns.FlashVitals(2) end
				-- (No Refresh here: switching refreshed every page already.)
			elseif not ns.IsBuiltinProfile(self.name) then
				picker:Open(self, self.name, ns.ProfileIcon(self.name))
			end
			Describe(ProfileText(self))
		end)
		cells[i] = cell
		return cell
	end

	-- The welcome window's Customize panel (Welcome.lua): one part of the
	-- active profile at a time. A change to a built-in starts My setup.
	local customizeHeader = Header(content, L["Customize"], box, -18)
	customizeHeader:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -18)
	local customize = ns.CustomizePanel(content, WIDTH, function() Refresh() end, true)
	customize:SetPoint("TOPLEFT", customizeHeader, "BOTTOMLEFT", 0, -10)
	-- (The part's own settings page, for everything else it has.)
	local more = S.Button(customize, L["Open its settings page"] .. " >", nil, function()
		local page = customize:SettingsPage()
		if page then ns.OpenOptions(page) end
	end)
	more:SetPoint("TOPRIGHT", customize, "BOTTOMRIGHT", 0, -4)

	local manageHeader = Header(content, L["Manage and share"], more, -14)
	manageHeader:SetPoint("TOPLEFT", customize, "BOTTOMLEFT", 0, -32)
	local buttons = CreateFrame("Frame", nil, content)
	buttons:SetSize(WIDTH, 28)
	buttons:SetPoint("TOPLEFT", manageHeader, "BOTTOMLEFT", 0, -10)
	-- (The menu look's own buttons, HD or SD. Its tip goes in the box, not a
	-- tooltip, as on the welcome window.)
	local function Button(parent, text, width, tip, onClick)
		local button = ns.PanelButton(parent)
		button:SetSize(width, 26)
		button:SetText(text)
		button:SetScript("OnClick", onClick)
		button.searchTip = tip
		button:HookScript("OnEnter", function() Describe(tip) end)
		button:HookScript("OnLeave", function() Describe() end)
		tips[#tips + 1] = tip
		return button
	end
	-- Sharing (Share.lua): a profile pasted in. Backups (Backups.lua): copies of
	-- every profile to go back to, and deleted ones. The rest is on a
	-- card's right-click menu (ProfileMenu below), for that profile; clients
	-- without the game's menus have buttons for the active one instead.
	local backups = Button(buttons, L["Backups"], 90, L["Brings back an older copy of a profile."], function()
		ns.ShowBackups()
	end)
	backups:SetPoint("LEFT", buttons, "LEFT", 0, 0)
	local import = Button(buttons, L["Import"], 84, L["Adds a profile someone shared with you."], function()
		ns.ShowImport()
	end)
	import:SetPoint("LEFT", backups, "RIGHT", 8, 0)
	-- (Export is on a card's right-click menu too, for that card's profile; this
	-- one is the active profile, where players look for it: beside Import.)
	local export = Button(buttons, L["Export"], 84, L["Gives you the active profile as text to share."], function()
		ns.ShowExport()
	end)
	export:SetPoint("LEFT", import, "RIGHT", 8, 0)
	local rename, note, delete, reset, savePoint
	if not PROFILE_MENUS then
		export:ClearAllPoints()
		rename = Button(buttons, L["Rename"], 90, L["Rename the active profile (your own ones only)."], function()
			local name = ns.ActiveProfile()
			StaticPopup_Show("CINEMATIC_PROFILE_RENAME", nil, nil, name)
		end)
		rename:SetPoint("LEFT", import, "RIGHT", 8, 0)
		note = Button(buttons, L["Description"], 96, L["Write what the active profile is for."], function()
			local name = ns.ActiveProfile()
			StaticPopup_Show("CINEMATIC_PROFILE_NOTE", nil, nil, name)
		end)
		note:SetPoint("LEFT", rename, "RIGHT", 8, 0)
		delete = Button(buttons, L["Delete"], 84, L["Delete the active profile (your own ones only), switching to %s."]:format(
			ns.ProfileLabel(ns.DEFAULT_PROFILE)), function()
			local name = ns.ActiveProfile()
			StaticPopup_Show("CINEMATIC_PROFILE_DELETE", name, nil, name)
		end)
		delete:SetPoint("LEFT", note, "RIGHT", 8, 0)
		reset = Button(buttons, L["Reset"], 100, L["Puts the active profile back to how you last saved it."], AskResetProfile)
		reset:SetPoint("TOPLEFT", backups, "BOTTOMLEFT", 0, -8)
		export:SetPoint("LEFT", reset, "RIGHT", 8, 0)
		savePoint = Button(buttons, L["Save"], 84, L["Saves the active profile as the point Reset goes back to."], function()
			SaveResetPoint(ns.ActiveProfile())
		end)
		savePoint:SetPoint("LEFT", export, "RIGHT", 8, 0)
	end
	-- Right-clicking a card: what's done to a profile, for that one.
	function ProfileMenu(cell)
		if not PROFILE_MENUS then return end
		local name = cell.name
		local own = not ns.IsBuiltinProfile(name)
		ns.ContextMenu(cell, function(_, root)
			root:CreateTitle(ns.ProfileLabel(name))
			if name ~= active then
				root:CreateButton(L["Switch to it"], function() cell:Click("LeftButton") end)
			end
			-- (A copy of that one: switched to first, as New profile copies the active one.)
			root:CreateButton(L["Copy profile"], function()
				picker:Hide()
				if name ~= ns.ActiveProfile() and not ns.SetProfile(name) then return end
				NewFromActive()
			end)
			if own then
				root:CreateButton(L["Rename"], function() StaticPopup_Show("CINEMATIC_PROFILE_RENAME", nil, nil, name) end)
				root:CreateButton(L["Description"], function() StaticPopup_Show("CINEMATIC_PROFILE_NOTE", nil, nil, name) end)
				root:CreateButton(L["Change icon"], function() picker:Open(cell, name, ns.ProfileIcon(name)) end)
			end
			root:CreateButton(L["Export"], function() ns.ShowExport(name) end)
			if name == active and (not own or ns.HasResetPoint(name)) then
				root:CreateButton(L["Reset"], AskResetProfile)
			end
			-- (Reset points: what Reset goes back to, the player's own.)
			root:CreateButton(L["Save"], function() SaveResetPoint(name) end)
			root:CreateButton(L["Backups"], function() ns.ShowBackups(name) end)
			if own then
				root:CreateDivider()
				root:CreateButton("|cffff4040" .. L["Delete"] .. "|r", function()
					StaticPopup_Show("CINEMATIC_PROFILE_DELETE", name, nil, name)
				end)
			end
		end)
	end

	-- (Managing comes right under the cards and their box, Customize after.)
	manageHeader:ClearAllPoints()
	manageHeader:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -18)
	customizeHeader:ClearAllPoints()
	customizeHeader:SetPoint("TOPLEFT", reset or backups, "BOTTOMLEFT", 0, -22)

	-- A card's place in the grid.
	local function Place(cell, i)
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", header, "BOTTOMLEFT", ((i - 1) % PER_ROW) * (CARD_W + GAP),
			-10 - math.floor((i - 1) / PER_ROW) * (CARD_H + GAP))
		cell:Show()
	end

	function Layout()
		if not ns.GetDB() then return end
		-- (None gold until a new player picks one; Cinematic does nothing till then.)
		active = ns.ProfileChosen() and ns.ActiveProfile() or nil
		local names = ns.ProfileNames()
		for i, name in ipairs(names) do
			local cell = GetCell(i)
			cell.name = name
			local builtin
			for _, profile in ipairs(ns.BUILTIN_PROFILES) do
				if profile.name == name then builtin = profile end
			end
			cell.label:SetText(ns.ProfileLabel(name))
			-- (Only a built-in's: one of yours saves as you go, so there's nothing to go back to.)
			cell.changed:SetShown(name == active and builtin ~= nil and ns.ProfileChanged())
			local written = ns.ProfileNote(name)
			cell.line:SetText(LEVELS[name] and LEVELS[name].line or written or L["Your own profile"])
			cell.tip = builtin and builtin.tip or written
				or (PROFILE_MENUS and L["Your own profile."]
				or L["Your own profile."])
			-- (Gold for the active one, its name and edge.)
			S.Color(cell.label, name == active and S.GOLD or S.WHITE)
			cell:SetBackdropBorderColor(unpack(name == active and S.GOLD or S.EDGE))
			cell.icon:SetTexture(ns.ProfileIcon(name))
			Place(cell, i)
		end
		for i = #names + 1, #cells do cells[i]:Hide() end
		Place(newCard, #names + 1)
		-- (The box as tall as the longest it can say, in this language, so
		-- what's under it doesn't move with the mouse.)
		local tallest = 0
		for i = 1, #names do
			about:SetText(ProfileText(cells[i]))
			tallest = math.max(tallest, about:GetStringHeight())
		end
		for _, tip in ipairs(tips) do
			about:SetText(tip)
			tallest = math.max(tallest, about:GetStringHeight())
		end
		box:SetHeight(math.max(56, math.ceil(tallest) + 20))
		Describe()
		local rows = math.ceil((#names + 1) / PER_ROW)
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10 - rows * (CARD_H + GAP))
		customize:Refresh()
		local own = active ~= nil and not ns.IsBuiltinProfile(active)
		if rename then
			rename:SetEnabled(own)
			note:SetEnabled(own)
			delete:SetEnabled(own)
			reset:SetEnabled(active ~= nil and (not own or ns.HasResetPoint(active)))
			export:SetEnabled(active ~= nil)
			savePoint:SetEnabled(active ~= nil)
		end
		FitContentHeight(content)
	end
	controls[#controls + 1] = { debugName = "Profiles page layout", owner = canvas, Refresh = function()
		if canvas:IsVisible() then Layout() end -- (IsShown stays true with its hub hidden: ~20 ms on every page switch)
	end }

	canvas:SetScript("OnShow", function()
		Refresh() -- (Layout too: its control above, the canvas shown now)
		C_Timer.After(0, function() FitContentHeight(content) end)
	end)
	canvas:Hide()
	RegisterSubpage(canvas, "Profiles")
end

local function CreateMouseoverPanel()
	local canvas, content = CreateScrollPage()
	local LEFT, WIDTH, ROW = 16, 560, 22
	local RESULTS_SHOWN = 8

	local title = Label(content, "GameFontNormalLarge", L["Hover Groups"])
	-- (The Mouse icon's Mouseover groups tab, 2026-11-16: its tabs over the title.)
	local mouseTabs = ns.PageTabs(content, ns.ShowInTabs("mouse"), ns.ShowInIndex("mouse", "Mouseover groups"))
	title:SetPoint("TOPLEFT", mouseTabs, "BOTTOMLEFT", 8, -14)
	local subtitle = PageIntro(content, title,
		L["Frames in the same group come up together when you mouse over any of them."] .. " " ..
		L["Click a group's icon below to go to it, or the + to make one of your own."])

	local mouseover = Check(content, "mouseover", L["Enable Page"],
		L["Pointing at a faded frame shows it, with the rest of its groups."], function(value)
			ns.GetDB().mouseover = value
			Refresh() -- grey out / enable the hold time
		end)
	mouseover:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -14)
	RegisterPageSwitch(content, "mouseover", mouseover)
	local hold = Slider(content, "mouseoverHold", L["Stays after mouseover"], 0, 30, 1, L["%d sec"])
	hold:SetPoint("TOPLEFT", mouseover, "BOTTOMLEFT", 4, -26)
	Tooltip(hold, L["How long a frame stays after your mouse leaves it."])
	GreyUnless(hold, function(db) return db.mouseover end)
	-- (The groups go back to the defaults with the rest of the page.)
	RecordKey(content, "hoverGroups")
	-- (Everything below is made the first time the page is needed: lazyPages.)
	local function MakeBody()

		-- The frames you can add: the rows (Standard Frames, the supported
		-- addons, a few more), your Advanced Frames additions, and any other
		-- named frame on screen (adding one of those fades it too).
		local catalog, byKey = {}, {}
		local function AddToCatalog(key, label, tag)
			if not byKey[key] then
				local item = { key = key, label = label, tag = tag }
				catalog[#catalog + 1], byKey[key] = item, item
			end
		end
		for _, item in ipairs(ns.HOVER_ROWS) do
			if ns.OptionAvailable(item) then
				AddToCatalog(item.key, item.hoverLabel or item.label, item.key:find("^addon:") and L["addon"])
			end
		end
		local function ScanCatalog()
			for name in pairs(ns.GetDB().extraFrames or {}) do
				AddToCatalog("extra:" .. name, name, L["custom"])
			end
			local faded = {}
			for _, entry in ipairs(ns.managed) do
				if entry.name then faded[entry.name] = true end
			end
			for _, frame in ipairs({ UIParent:GetChildren() }) do
				local name = not (frame.IsForbidden and frame:IsForbidden()) and frame:GetName()
				if name and frame:IsShown() and not faded[name] and not name:find("^Cinematic") then
					AddToCatalog("frame:" .. name, name, L["not faded yet"])
				end
			end
		end

		-- The groups shown are the ones in use; the first change makes them the
		-- player's own copy (until then they're the defaults, and follow them).
		local function Groups()
			return ns.GetHoverGroups()
		end
		local function Writable()
			local db = ns.GetDB()
			if not db.hoverGroups then
				db.hoverGroups = ns.CopyHoverGroups()
			end
			return db.hoverGroups
		end

		-- Whether a group has an action bar in it (the rows of the faded bars:
		-- its hover reach works only on those).
		local function HasBarMember(group)
			local barRows = {}
			for _, entry in ipairs(ns.managed) do
				if entry.group == "bars" or entry.group == "sidebars" then
					barRows[entry.row or ns.HoverRowFor(entry)] = true
				end
			end
			for _, key in ipairs(group.members) do
				if barRows[key] then return true end
			end
			return false
		end

		local function GroupsWith(key, exceptIndex)
			local names = {}
			for i, group in ipairs(Groups()) do
				if i ~= exceptIndex then
					for _, member in ipairs(group.members) do
						if member == key then names[#names + 1] = group.name break end
					end
				end
			end
			return names
		end

		-- The unit frames' rows: each one's section (as the Unit Frames page's) and parts.
		local UNIT_ROWS = {
			player = { "Player", ns.UNIT_PARTS_PLAYER }, petframe = { "Pet", ns.UNIT_PARTS_PET },
			target = { "Target", ns.UNIT_PARTS_TARGET }, tot = { "ToT", ns.UNIT_PARTS_TOT },
			focus = { "Focus", ns.UNIT_PARTS_TARGET },
		}
		-- The parts a row's frame has here, or nil for a frame that hasn't any.
		local function RowParts(key)
			local info = UNIT_ROWS[key]
			if not (info and MenuUtil and ns.HasUnitFrameParts and ns.HasUnitFrameParts()) then return nil end
			local list = {}
			for _, part in ipairs(ns.UnitPartLabels()) do
				local only = ns.UNIT_PART_ONLY[part[1]]
				if info[2][part[1]] ~= nil and (not only or only[info[1]] == true) then
					list[#list + 1] = part
				end
			end
			return list
		end
		local function PartOff(index, key, part)
			local group = Groups()[index]
			local off = group and group.parts and group.parts[key]
			return off and off[part] or false
		end
		-- (Only what's unticked is kept: none, and the group has every part, as
		-- groups made before there were parts have.)
		local function SetRowOff(index, key, off)
			local group = Writable()[index]
			local parts = group.parts or {}
			parts[key] = off and next(off) and off or nil
			group.parts = next(parts) and parts or nil
		end
		local function TogglePart(index, key, part)
			local group = Writable()[index]
			local off = group.parts and group.parts[key] or {}
			off[part] = not off[part] or nil
			SetRowOff(index, key, off)
		end

		local triggers = {}
		for _, trigger in ipairs(ns.HOVER_TRIGGERS) do
			if not trigger.gamepad or (C_GamePad and not ns.isRetail) then
				triggers[#triggers + 1] = trigger
			end
		end

		-- Widgets are pooled and laid out top to bottom again on every change.
		local pools = {}
		local function Take(kind, make)
			local pool = pools[kind] or { list = {}, used = 0 }
			pools[kind] = pool
			pool.used = pool.used + 1
			local widget = pool.list[pool.used]
			if not widget then
				widget = make()
				pool.list[pool.used] = widget
			end
			widget:ClearAllPoints()
			widget:Show()
			return widget
		end
		local Layout -- (below)

		-- The search results list, shared by every group's add boxes (frames and events).
		-- (On the canvas, not the scrolling content, so the scroll frame doesn't clip it.)
		local results = CreateFrame("Frame", nil, canvas)
		results:SetFrameStrata("DIALOG")
		results:SetSize(320, RESULTS_SHOWN * 20 + 8)
		local resultsBg = results:CreateTexture(nil, "BACKGROUND")
		resultsBg:SetAllPoints()
		resultsBg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
		local resultsEdge = results:CreateTexture(nil, "BORDER")
		resultsEdge:SetPoint("TOPLEFT", -1, 1)
		resultsEdge:SetPoint("BOTTOMRIGHT", 1, -1)
		resultsEdge:SetColorTexture(0.4, 0.4, 0.4, 1)
		resultsEdge:SetDrawLayer("BACKGROUND", -1)
		results:Hide()
		local resultButtons = {}
		for i = 1, RESULTS_SHOWN do
			local button = CreateFrame("Button", nil, results)
			button:SetSize(298, 20)
			button:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
			button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			button.text = Label(button, "GameFontHighlight")
			button.text:SetPoint("LEFT", 4, 0)
			button.tag = Label(button, "GameFontDisableSmall")
			button.tag:SetPoint("RIGHT", -4, 0)
			-- (An event's tip says what it is.)
			button:SetScript("OnEnter", function(self)
				if self.tip then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
					GameTooltip:Show()
				end
			end)
			button:SetScript("OnLeave", function() GameTooltip:Hide() end)
			resultButtons[i] = button
		end
		local noMatch = Label(results, "GameFontDisable", L["No frames match"])
		noMatch:SetPoint("TOPLEFT", 8, -8)

		-- The scroll bar down the right edge: drag it, or scroll the wheel over the list.
		local scrollBar = CreateFrame("Slider", nil, results)
		scrollBar:SetOrientation("VERTICAL")
		scrollBar:SetWidth(10)
		scrollBar:SetPoint("TOPRIGHT", -3, -4)
		scrollBar:SetPoint("BOTTOMRIGHT", -3, 4)
		local track = scrollBar:CreateTexture(nil, "BACKGROUND")
		track:SetAllPoints()
		track:SetColorTexture(1, 1, 1, 0.08)
		local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
		thumb:SetColorTexture(0.8, 0.7, 0.3, 0.8)
		thumb:SetSize(10, 30)
		scrollBar:SetThumbTexture(thumb)
		scrollBar:SetValueStep(1)
		if scrollBar.SetObeyStepOnDrag then scrollBar:SetObeyStepOnDrag(true) end

		-- Adding a frame to group number index. A frame on screen that isn't
		-- faded yet is added to the Advanced Frames list first (as /cine add
		-- does; windows are turned down there).
		local function AddMember(index, item)
			local key = item.key
			local name = key:match("^frame:(.+)$")
			if name then
				ns.AddUnderMouse(name)
				if not ns.GetDB().extraFrames[name] then
					return
				end
				key = "extra:" .. name
				AddToCatalog(key, name, L["custom"])
			end
			local members = Writable()[index].members
			for _, member in ipairs(members) do
				if member == key then return end
			end
			members[#members + 1] = key
		end

		local list = { matches = {}, offset = 0 }
		local function RenderResults()
			local matches, index, box = list.matches, list.index, list.box
			local maxOffset = math.max(0, #matches - RESULTS_SHOWN)
			list.offset = math.max(0, math.min(list.offset, maxOffset))
			local shown = math.min(#matches, RESULTS_SHOWN)
			results:SetHeight(math.max(1, shown) * 20 + 8)
			noMatch:SetText(list.events and L["No events match"] or L["No frames match"])
			noMatch:SetShown(shown == 0)
			scrollBar:SetShown(maxOffset > 0)
			if maxOffset > 0 then
				list.syncing = true
				scrollBar:SetMinMaxValues(0, maxOffset)
				scrollBar:SetValue(list.offset)
				list.syncing = false
				-- (The thumb's length shows how much of the list fits.)
				thumb:SetHeight(math.max(16, (shown * 20) * RESULTS_SHOWN / #matches))
			end
			for i, button in ipairs(resultButtons) do
				local item = matches[i + list.offset]
				button:SetShown(item ~= nil)
				if item then
					local here, tag
					if list.events then
						local group = Groups()[index]
						here = group and group.triggers and group.triggers[item.key] and true or false
						tag = ""
					else
						local others = GroupsWith(item.key, index)
						here = #GroupsWith(item.key) > #others
						tag = #others > 0 and L["in %s"]:format(table.concat(others, ", ")) or item.tag or ""
					end
					button.text:SetText(item.label)
					SetLabelFont(button.text, here and "GameFontDisable" or "GameFontHighlight")
					button.tag:SetText(here and L["already here"] or tag)
					button.tip = list.events and item.tip or nil
					button:SetEnabled(not here)
					button:SetScript("OnClick", function()
						if list.events then
							local editable = Writable()[index]
							editable.triggers = editable.triggers or {}
							editable.triggers[item.key] = true
						else
							AddMember(index, item)
						end
						box:SetText("")
						box:ClearFocus()
						results:Hide()
						Layout()
					end)
				end
			end
		end
		scrollBar:SetScript("OnValueChanged", function(_, value)
			if list.syncing then return end
			list.offset = math.floor(value + 0.5)
			RenderResults()
		end)
		results:EnableMouseWheel(true)
		results:SetScript("OnMouseWheel", function(_, delta)
			list.offset = list.offset - delta * 3
			RenderResults()
		end)
		-- Clicking the scroll bar takes the focus from the search box, so the list
		-- stays open while the mouse is on it and closes on a click anywhere else.
		ns.SetOnUpdate(results, function(self)
			if not (list.box and list.box:HasFocus()) and not self:IsMouseOver()
				and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
				self:Hide()
			end
		end)

		-- events: search the events that bring a group up instead of the frames.
		local function ShowResults(box, index, events)
			local query = box:GetText():lower()
			local matches = {}
			for _, item in ipairs(events and triggers or catalog) do
				if query == "" or item.label:lower():find(query, 1, true) then
					matches[#matches + 1] = item
				end
			end
			list.matches, list.index, list.box, list.offset = matches, index, box, 0
			list.events = events
			results:ClearAllPoints()
			results:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -2)
			RenderResults()
			results:Show()
		end

		-- Each group's heading is a band that opens and closes it, as on the
		-- Standard Frames page: closed until clicked open (remembered by its
		-- default's key, or its name). A new group opens, to add its frames.
		local function GroupSection(group)
			local preset = ns.HoverGroupPreset(group)
			return { id = "Mouseover groups/" .. (preset and "preset:" .. preset.preset or "name:" .. (group.name or "")) }
		end
		local function IsOpen(group)
			return SectionState.Saved(GroupSection(group).id, false)
		end

		local newGroup = ns.PanelButton(content)
		newGroup:SetSize(120, 22)
		newGroup:SetText(L["New group"])
		newGroup:SetScript("OnClick", function()
			local groups = Writable()
			groups[#groups + 1] = { name = L["Group %d"]:format(#groups + 1), members = {}, triggers = {},
				icon = ns.UnusedHoverGroupIcon() }
			SectionState.Save(GroupSection(groups[#groups]), true)
			Layout()
		end)

		-- The icon picker for a group you made, under the icon clicked: any icon
		-- the game has (IconBrowser.lua).
		local picker = ns.IconBrowser(canvas, function(index, file)
			local group = Writable()[index]
			if group then group.icon = file end
			Layout()
		end)
		local function ShowPicker(owner, index)
			results:Hide()
			picker:Open(owner, index, ns.HoverGroupIcon(Groups()[index]))
		end

		-- A square icon: gold edge, a darker one when dim. (The row of groups at
		-- the top, and each group's heading.)
		local function IconTile(size)
			local tile = CreateFrame("Button", nil, content)
			tile:SetSize(size, size)
			tile.border = tile:CreateTexture(nil, "BACKGROUND")
			tile.border:SetAllPoints()
			tile.border:SetColorTexture(0.45, 0.38, 0.2, 1)
			local bg = tile:CreateTexture(nil, "BORDER")
			bg:SetPoint("TOPLEFT", 1, -1)
			bg:SetPoint("BOTTOMRIGHT", -1, 1)
			bg:SetColorTexture(0.06, 0.05, 0.04, 0.95)
			tile.icon = tile:CreateTexture(nil, "ARTWORK")
			tile.icon:SetPoint("TOPLEFT", 2, -2)
			tile.icon:SetPoint("BOTTOMRIGHT", -2, 2)
			tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			local hl = tile:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints(tile.icon)
			hl:SetColorTexture(1, 1, 1, 0.15)
			tile:SetScript("OnEnter", function(self)
				if not self.tipTitle then return end
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
				GameTooltip:SetText(self.tipTitle, 1, 0.82, 0)
				for _, line in ipairs(self.tipLines or {}) do
					GameTooltip:AddLine(line, 1, 1, 1, true)
				end
				GameTooltip:Show()
			end)
			tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
			return tile
		end

		-- Scrolls the page to a group's heading.
		local headingY = {}
		local function JumpTo(index)
			local scroll = canvas.scroll
			local y = headingY[index]
			if not (scroll and y) then return end
			local range = scroll:GetVerticalScrollRange() or 0
			scroll:SetVerticalScroll(math.max(0, math.min(range, y - 8)))
		end

		-- A row in a group: remove button, label, a note after it.
		local function MemberRow()
			local frame = CreateFrame("Frame", nil, content)
			frame:SetSize(WIDTH - 10, ROW)
			frame.remove = ns.SkinClose(CreateFrame("Button", nil, frame, "UIPanelCloseButton"))
			frame.remove:SetSize(22, 22)
			frame.remove:SetPoint("LEFT", 0, 0)
			Tooltip(frame.remove, L["Take it out of this group."])
			frame.text = Label(frame, "GameFontHighlight")
			frame.text:SetPoint("LEFT", frame.remove, "RIGHT", 4, 0)
			frame.also = Label(frame, "GameFontDisableSmall")
			frame.also:SetPoint("LEFT", frame.text, "RIGHT", 10, 0)
			return frame
		end

		-- In a unit frame's row, for its label: its name and how many parts come up
		-- with the group, a click ticking them. (index, key, label: the row it's on now.)
		local function PartsMenu()
			local _, menu = ns.MenuDropdown(content)
			menu:SetSize(250, 22)
			menu.searchSkip = true -- (it shows the current ticks, not a label)
			menu:SetupMenu(function(_, root)
				root:CreateButton(L["All parts"], function()
					SetRowOff(menu.index, menu.key, nil)
					return MenuResponse and MenuResponse.Refresh
				end)
				if root.CreateDivider then root:CreateDivider() end
				for _, part in ipairs(RowParts(menu.key) or {}) do
					root:CreateCheckbox(part[2], function() return not PartOff(menu.index, menu.key, part[1]) end, function()
						TogglePart(menu.index, menu.key, part[1])
						return MenuResponse and MenuResponse.Refresh
					end)
				end
			end)
			if menu.SetSelectionText then
				menu:SetSelectionText(function()
					local parts, ticked = RowParts(menu.key) or {}, 0
					for _, part in ipairs(parts) do
						if not PartOff(menu.index, menu.key, part[1]) then ticked = ticked + 1 end
					end
					if ticked == #parts then return L["%s (all parts)"]:format(menu.label) end
					return L["%s (%d of %d parts)"]:format(menu.label, ticked, #parts)
				end)
			end
			Tooltip(menu, L["Which parts of this frame come up with this group."])
			return menu
		end

		-- A type-to-search box adding to group number index: frames, or with
		-- events set, the events that bring the group up.
		local function AddBox(kind, hint, index, events)
			local add = Take(kind, function()
				local box = ns.SkinEditBox(CreateFrame("EditBox", nil, content, "InputBoxTemplate"))
				box:SetSize(260, 20)
				box:SetAutoFocus(false)
				box.hint = Label(box, "GameFontDisable", hint)
				box.hint:SetPoint("LEFT", 2, 0)
				box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
				box:SetScript("OnEditFocusLost", function(self)
					self.hint:SetShown(self:GetText() == "")
					C_Timer.After(0.2, function()
						if not self:HasFocus() and not results:IsMouseOver() then results:Hide() end
					end)
				end)
				return box
			end)
			add:SetText("")
			add.hint:Show()
			add:SetScript("OnEditFocusGained", function(self)
				if not events then ScanCatalog() end
				self.hint:Hide()
				ShowResults(self, index, events)
			end)
			add:SetScript("OnTextChanged", function(self)
				if self:HasFocus() then ShowResults(self, index, events) end
			end)
			add:SetScript("OnEnterPressed", function(self)
				local first = resultButtons[1]
				if results:IsShown() and first:IsShown() and first:IsEnabled() then first:Click() end
				self:ClearFocus()
			end)
			return add
		end

		function Layout()
			for _, pool in pairs(pools) do
				for _, widget in ipairs(pool.list) do widget:Hide() end
				pool.used = 0
			end
			-- (Below the main switch and slider.)
			local top, bottom = content:GetTop(), hold:GetBottom()
			local y = (top and bottom) and (top - bottom + 22) or 180
			-- (dim: the alpha for what's placed, lower for a group that's off.)
			local dim = 1
			local function At(widget, x, extraY)
				widget:SetPoint("TOPLEFT", content, "TOPLEFT", x, -(y + (extraY or 0)))
				widget:SetAlpha(dim)
			end

			-- A row of every group's icon: click one to go to it. The + at the
			-- end makes a new group.
			local TILE, GAP = 32, 6
			local perRow = math.max(1, math.floor((WIDTH + GAP) / (TILE + GAP)))
			local groups = Groups()
			local function TileAt(tile, i)
				tile:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT + ((i - 1) % perRow) * (TILE + GAP),
					-(y + math.floor((i - 1) / perRow) * (TILE + GAP)))
			end
			for index, group in ipairs(groups) do
				local tile = Take("tile", function() return IconTile(TILE) end)
				TileAt(tile, index)
				tile.icon:SetTexture(ns.HoverGroupIcon(group))
				tile.icon:SetDesaturated(group.off and true or false)
				tile.tipTitle = group.off and group.name .. " |cff808080(" .. L["Off"] .. ")|r" or group.name
				local names = {}
				for _, key in ipairs(group.members) do
					local item = byKey[key]
					if item or key:find("^extra:") then
						names[#names + 1] = item and item.label or key:gsub("^extra:", "")
					end
				end
				tile.tipLines = { #names > 0 and table.concat(names, ", ") or L["No frames yet."],
					"|cff808080" .. L["Click to go to it."] .. "|r" }
				tile:SetScript("OnClick", function()
					if IsOpen(group) then
						JumpTo(index)
					else
						SectionState.Save(GroupSection(group), true)
						Layout()
						-- (Once the page has grown to fit it.)
						C_Timer.After(0, function() JumpTo(index) end)
					end
				end)
			end
			local add = Take("tile", function() return IconTile(TILE) end)
			TileAt(add, #groups + 1)
			add.icon:SetTexture("Interface\\Icons\\Spell_ChargePositive")
			add.icon:SetDesaturated(false)
			add.tipTitle, add.tipLines = L["New group"], { L["A group of your own, to pick its frames and icon."] }
			add:SetScript("OnClick", function()
				newGroup:Click()
				-- (Once the page has grown to fit it.)
				C_Timer.After(0, function() JumpTo(#Groups()) end)
			end)
			y = y + math.ceil((#groups + 1) / perRow) * (TILE + GAP) + 14

			wipe(headingY)
			for index, group in ipairs(groups) do
				-- Heading, on its band: icon, name box, when, on/off, delete.
				dim = 1
				headingY[index] = y
				y = y + 4
				local open = IsOpen(group)
				local band = Take("band", function()
					local holder = CreateFrame("Frame", nil, content)
					holder:SetSize(WIDTH - 2, BAND_HEIGHT)
					holder.nameRow = SectionBand(holder, "")
					return holder
				end)
				At(band, LEFT + 2, -3)
				band.nameRow:SetOpen(open)
				band.nameRow:SetScript("OnClick", function()
					SectionState.Save(GroupSection(group), not open)
					Layout()
				end)
				-- (The heading's buttons above the band, to take their own clicks.)
				local function Raise(widget)
					widget:SetFrameLevel(band.nameRow:GetFrameLevel() + 2)
				end
				-- (An off group is greyed out, all but its On/Off and Delete buttons.)
				dim = group.off and 0.4 or 1

				-- Its icon: one you pick. Right-click: a default group's own back.
				local preset = ns.HoverGroupPreset(group)
				local icon = Take("headIcon", function() return IconTile(26) end)
				At(icon, LEFT + 4, -3)
				Raise(icon)
				icon.icon:SetTexture(ns.HoverGroupIcon(group))
				icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				icon.tipTitle, icon.tipLines = group.name, { L["Click to pick its icon."] }
				if preset then
					icon.tipLines[2] = L["Right-click: back to its own icon."]
				end
				icon:SetScript("OnClick", function(self, button)
					if button ~= "RightButton" then
						ShowPicker(self, index)
					elseif preset and group.icon then
						picker:Hide()
						Writable()[index].icon = nil
						Layout()
					end
				end)

				local nameBox = Take("name", function()
					local box = ns.SkinEditBox(CreateFrame("EditBox", nil, content, "InputBoxTemplate"))
					box:SetSize(170, 20)
					box:SetAutoFocus(false)
					box:SetFontObject("GameFontNormal")
					box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
					box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
					Tooltip(box, L["The group's name: click to change it."])
					return box
				end)
				At(nameBox, LEFT + 40)
				Raise(nameBox)
				nameBox:SetText(group.name or "")
				-- (Search and /cine find: a box's text isn't read, so the group's
				-- name is given, found with its whole heading glowing.)
				nameBox.searchLabel = group.name
				nameBox.searchEdges = { top = band, bottom = band, left = band, right = band }
				nameBox:SetScript("OnEditFocusLost", function(self)
					local text = self:GetText()
					if text ~= "" and text ~= group.name then
						local editable = Writable()[index]
						-- (A default group stays one, with its icon, under a new name.)
						editable.preset = preset and preset.preset or editable.preset
						editable.name = text
						Layout()
					end
				end)

				-- When it works: any time, or only out of fights or in them (click
				-- for the next). (when: nil, "calm" or "combat".)
				local when = Take("when", function()
					local button = ns.PanelButton(content)
					button:SetSize(140, 22)
					Tooltip(button, L["When this group works: any time, in combat or out of combat."])
					return button
				end)
				At(when, LEFT + 224, -1)
				Raise(when)
				when:SetText(group.when == "calm" and L["Only out of combat"]
					or group.when == "combat" and L["Only in combat"] or L["Any time"])
				when:SetScript("OnClick", function()
					local editable = Writable()[index]
					editable.when = (editable.when == nil and "calm") or (editable.when == "calm" and "combat") or nil
					Layout()
				end)

				-- On or off: an off group is kept, but does nothing. (off: nil or true.)
				local onOff = Take("onOff", function()
					local button = ns.PanelButton(content)
					button:SetSize(80, 22)
					Tooltip(button, L["Turns this group on or off."])
					return button
				end)
				At(onOff, LEFT + 372, -1)
				Raise(onOff)
				onOff:SetAlpha(1)
				onOff:SetText(group.off and L["Off"] or L["On"])
				onOff:SetScript("OnClick", function()
					local editable = Writable()[index]
					editable.off = not editable.off or nil
					Layout()
				end)
				icon.icon:SetDesaturated(group.off and true or false)

				local delete = Take("delete", function()
					local button = ns.PanelButton(content)
					button:SetSize(100, 22)
					button:SetText(L["Delete group"])
					Tooltip(button, L["Its frames come up on their own again (or with their other groups)."])
					return button
				end)
				At(delete, LEFT + WIDTH - 100, -1)
				Raise(delete)
				delete:SetAlpha(1)
				delete:SetScript("OnClick", function()
					SectionState.Save(GroupSection(group), nil)
					table.remove(Writable(), index)
					Layout()
				end)
				y = y + 28
				if open then
					-- Members: label, other groups it's in, remove. (Frames this client
					-- doesn't have stay in the group, unlisted.)
					local listed = 0
					for _, key in ipairs(group.members) do
						local item = byKey[key]
						if item or key:find("^extra:") then
							listed = listed + 1
							local row = Take("member", MemberRow)
							At(row, LEFT + 4)
							local label = item and item.label or key:gsub("^extra:", "")
							row.text:SetText(label)
							row.also:ClearAllPoints()
							row.also:SetPoint("LEFT", row.text, "RIGHT", 10, 0)
							-- (A unit frame's label is its menu of parts.)
							if RowParts(key) then
								local menu = Take("partsMenu", PartsMenu)
								menu.index, menu.key, menu.label = index, key, label
								At(menu, LEFT + 30, 1)
								menu:GenerateMenu()
								row.text:SetText("")
								row.also:ClearAllPoints()
								row.also:SetPoint("LEFT", menu, "RIGHT", 10, 0)
								y = y + 8 -- (a menu fills its row: a gap, or they touch)
							end
							local others = GroupsWith(key, index)
							row.also:SetText(#others > 0 and L["also in %s"]:format(table.concat(others, ", "))
								or (item and item.tag) or (item and "" or L["custom"]))
							row.remove:SetScript("OnClick", function()
								local members = Writable()[index].members
								for i, member in ipairs(members) do
									if member == key then table.remove(members, i) break end
								end
								SetRowOff(index, key, nil)
								Layout()
							end)
							y = y + ROW
						end
					end
					if listed == 0 then
						local empty = Take("empty", function() return Label(content, "GameFontDisable", L["No frames yet."]) end)
						At(empty, LEFT + 10, 4)
						y = y + ROW
					end

					-- Add a frame: type to search the list.
					At(AddBox("add", L["Add a frame: type to search..."], index), LEFT + 34, 4)
					y = y + 30

					-- Hover reach: only for a group with an action bar in it (the
					-- one kind it works on).
					if HasBarMember(group) then
						local reach = Take("reach", function()
							local slider
							slider = Slider(content, {
								get = function()
									local current = slider.index and Groups()[slider.index]
									return current and ns.HoverGroupReach(current) or 0
								end,
								set = function(value)
									if slider.index then Writable()[slider.index].reach = value end
								end,
							}, L["Hover reach"], 0, 40, 1, L["%d px"])
							Tooltip(slider, L["How close the mouse must come to this group's buttons to bring it up."])
							return slider
						end)
						reach.index = index
						At(reach, LEFT + 14, 20)
						reach:Refresh()
						y = y + 52
					end

					-- The events that bring the group up besides the mouse: one row
					-- each, then a box to add more.
					local alsoLabel = Take("alsoLabel", function()
						return Label(content, "GameFontNormalSmall", L["Also bring this group up for:"])
					end)
					At(alsoLabel, LEFT + 10, 2)
					y = y + 18
					for _, trigger in ipairs(triggers) do
						if group.triggers and group.triggers[trigger.key] then
							local row = Take("member", MemberRow)
							At(row, LEFT + 4)
							row.text:SetText(trigger.label)
							row.also:SetText("")
							row.remove:SetScript("OnClick", function()
								local editable = Writable()[index]
								if editable.triggers then editable.triggers[trigger.key] = nil end
								Layout()
							end)
							y = y + ROW
						end
					end
					At(AddBox("addEvent", L["Add an event: type to search..."], index, true), LEFT + 34, 4)
					y = y + 48
				end
			end
			dim = 1

			newGroup:ClearAllPoints()
			newGroup:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT, -(y + 4))
			FitContentHeight(content)
		end
		-- (Laid out again whenever the page refreshes, a Reset page included.)
		controls[#controls + 1] = { debugName = "Hover Groups layout", owner = canvas, Refresh = function()
			if canvas:IsVisible() then Layout() end -- (IsShown stays true with its hub hidden: ~20 ms on every page switch)
		end }
		-- (The search looks at pages that aren't open: the groups laid out for it,
		-- or it would find none of them until the page had been opened.)
		ns.searchPrepare[#ns.searchPrepare + 1] = function()
			if not canvas:IsVisible() then Layout() end
		end

		canvas:SetScript("OnShow", function()
			Refresh()
			Layout()
			C_Timer.After(0, function() FitContentHeight(content) end)
		end)
		canvas:SetScript("OnHide", function()
			results:Hide()
			picker:Hide()
		end)
	end
	lazyPages.Add(canvas, "Hover Groups", MakeBody)
	canvas:Hide()
	RegisterSubpage(canvas, "Mouseover groups", L["Hover Groups"])
end

-- WoW Forever freezes closing Settings in gamepad mode once one of our
-- controls has been used (a Blizzard bug: an empty addon does it too).
-- With forceReloadOnSettingsExit (Gamepad page), closing reloads the UI
-- instead: our settings are saved already, and the reload closes the window
-- without the freeze. The X, Close, Escape and the gamepad's own presses all
-- go through SettingsPanel:Close (the gamepad clicks buttons itself, past
-- anything laid over them), so that's replaced, once one of our pages has
-- shown in gamepad mode. Replacing it taints the close from then on, so every
-- close in gamepad mode reloads after that (until a reload, if the setting
-- is turned off).
local function GuardGamepadClose()
	local panel = _G.SettingsPanel
	local InputUtil = _G.InputUtil
	if ns.isRetail or not panel or not panel.Close or not InputUtil or not InputUtil.IsGamepadUIEnabled then
		return
	end
	local function Wanted()
		return ns.db and ns.db.forceReloadOnSettingsExit and ns.db.handleGamepad ~= false
			and InputUtil.IsGamepadUIEnabled()
	end
	local function Install()
		local Close = panel.Close
		panel.Close = function(...)
			if Wanted() then
				ReloadUI()
				return
			end
			return Close(...)
		end
		print("|cffffd100Cinematic:|r " .. L["closing Settings now reloads the UI (Force reload on Settings exit, " ..
			"Gamepad Frames page)."])
	end
	-- Runs only while Settings is open (a child of it).
	local watcher = CreateFrame("Frame", nil, panel)
	ns.SetOnUpdate(watcher, function(self)
		if not Wanted() then
			return
		end
		for _, page in ipairs(searchPages) do
			if page.canvas:IsVisible() then
				Install()
				ns.SetOnUpdate(self, nil)
				return
			end
		end
	end)
end

-- The page helpers LowHealth.lua's Vitals Vision page uses. (Out here: the
-- function below is at Lua's cap of 60 outside locals it can use.)
ns.lowHealthKit = { CreateScrollPage = CreateScrollPage, Label = Label, PageShown = PageShown,
	RegisterSubpage = RegisterSubpage, Tooltip = Tooltip, PageIntro = PageIntro, Stack = Stack,
	Check = Check, Slider = Slider, GreyUnless = GreyUnless, Refresh = Refresh, Dropdown = Dropdown,
	PageSwitch = PageSwitch, AddControl = function(control) controls[#controls + 1] = control end,
	Header = Header, CreateKeybindButton = CreateKeybindButton, RefreshKeybinds = RefreshKeybinds,
	StopListening = StopListening, FitContentHeight = FitContentHeight, SectionState = SectionState,
	Choice = Choice, OpenColorPicker = OpenColorPicker, BoxLine = BoxLine, RecordKey = RecordKey,
	-- (fn after the page's Reset page has put its settings back)
	OnReset = function(content, fn) resetHooks[content] = fn end }

-- The pages are built once the language is known (Locales.lua): first the
-- text this file made as it ran is translated again.
ns.OnLanguage(function()
	-- (How long making every page takes at login, in the log: for deciding
	-- whether pages should be made as they first open. Tools/growth-plan.md.)
	local buildStarted = type(debugprofilestop) == "function" and debugprofilestop()
	-- (Each page's own time, between laps: the slowest go in the log too.)
	local laps, lastLap = {}, buildStarted
	local function Lap(name)
		if type(lastLap) ~= "number" then return end
		local now = debugprofilestop()
		laps[#laps + 1] = { name = name, ms = now - lastLap }
		lastLap = now
	end
	PVP_TIP, ZOOM_TIP, INPUT_PAUSE_TIP = L[PVP_TIP], L[ZOOM_TIP], L[INPUT_PAUSE_TIP]
	ns.TranslateFields(PLACES, 2)
	ns.TranslateFields(QUEST_SIDES, "text")
	for key, tip in pairs(EVENT_TIPS) do
		EVENT_TIPS[key] = L[tip]
	end
	ns.TranslateFields(FRAME_COLUMNS, 1, 5)
	ns.TranslateFields(THIRD_PARTY_COLUMNS, 1) -- (the rest are FRAME_COLUMNS' own)
	ns.TranslateFields(KEYBINDS, "label", "tip", "section")
	for _, popup in ipairs({ "CINEMATIC_RESET_PAGE", "CINEMATIC_RESET_PART", "CINEMATIC_PROFILE_RENAME",
		"CINEMATIC_PROFILE_NOTE", "CINEMATIC_PROFILE_DELETE", "CINEMATIC_PROFILE_RESET", "CINEMATIC_PROFILE_RESET_POINT",
		"CINEMATIC_ADDON_RESET", "CINEMATIC_ADDON_RESET_ALL", "CINEMATIC_RESET_SECTION" }) do
		local dialog = StaticPopupDialogs[popup]
		dialog.text = L[dialog.text]
		-- (Its own buttons' words too, made before the language was known. The
		-- game's own, like YES, are in the player's language already.)
		for _, button in ipairs({ "button1", "button2", "button3" }) do
			if type(dialog[button]) == "string" then dialog[button] = L[dialog[button]] end
		end
	end
	StaticPopupDialogs.CINEMATIC_LANGUAGE_RELOAD = {
		text = L["Cinematic's language changes after a reload. Reload now?"],
		button1 = RELOADUI or L["Reload"], button2 = L["Later"],
		OnAccept = ReloadUI,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	-- The game keeps the floating-text font it first loaded, so only a fresh start applies it
	StaticPopupDialogs.CINEMATIC_WORLD_TEXT_RESTART = {
		-- (No Exit button: Quit is the game's alone, forbidden from an addon's
		-- popup, tested on Forever 2026-11-10.)
		text = L["Floating text changes after you fully restart the game (/reload isn't enough). The same goes for getting it back: until a full restart it stays hidden, even with Cinematic turned off."],
		button1 = CLOSE or L["Close"],
		timeout = 0, whileDead = true, hideOnEscape = true,
	}

	Lap("(texts and popups)")
	CreatePanel()
	Lap("CreatePanel")
	CreateProfilesPanel()
	Lap("CreateProfilesPanel")
	-- Sub-pages in the order they're listed: what fades and shows, then the look
	-- and sound, then the camera modes (their shared page and events first),
	-- keybinds. (Their place in the left list: menu.order.)
	CreateRevealPanel()
	Lap("CreateRevealPanel")
	CreateCombatPanel()
	Lap("CreateCombatPanel")
	if ns.CreatePersonalResourcesPanel then -- (PersonalResources.lua)
		ns.CreatePersonalResourcesPanel(ns.lowHealthKit)
		Lap("CreatePersonalResourcesPanel")
	end
	if ns.CreateCursorHidePage then -- (CursorHide.lua)
		ns.CreateCursorHidePage(ns.lowHealthKit)
		Lap("CreateCursorHidePage")
	end
	-- WoW Forever's gamepad mode (retail's has no frames of its own).
	if C_GamePad and not ns.isRetail then
		CreateGamepadPanel()
		Lap("CreateGamepadPanel")
	end
	CreateExtrasPanel()
	Lap("CreateExtrasPanel")
	CreateMouseoverPanel()
	Lap("CreateMouseoverPanel")
	CreateMinimapPanel()
	Lap("CreateMinimapPanel")
	CreateQuestTrackerPanel()
	Lap("CreateQuestTrackerPanel")
	-- (Classic clients' own swing timer.)
	if not ns.isRetail then
		CreateSwingPanel()
		Lap("CreateSwingPanel")
	end
	ns.CreateBreathBarPanel() -- (the Timers icon's Breath Bar tab)
	Lap("CreateBreathBarPanel")
	-- (Only with a Cooldown Manager: the game's, on clients that have it, or the addon.
	-- ProfileModules.lua.)
	if ns.HasCooldownManager() then
		CreateCooldownPanel()
		Lap("CreateCooldownPanel")
	end
	CreateTooltipPanel()
	Lap("CreateTooltipPanel")
	-- (its hub listed after UI Manager's)
	CreateVisionPanel()
	Lap("CreateVisionPanel")
	if ns.CreateVitalsVisionPanel then -- (LowHealth.lua)
		ns.CreateVitalsVisionPanel(ns.lowHealthKit)
		Lap("CreateVitalsVisionPanel")
	end
	if ns.CreateCardsPanel then -- (CardsPage.lua)
		ns.CreateCardsPanel(ns.lowHealthKit)
		Lap("CreateCardsPanel")
		ns.CreateCardStylesPanel(ns.lowHealthKit)
		Lap("CreateCardStylesPanel")
		ns.CreateCardSettingsPanel(ns.lowHealthKit)
		Lap("CreateCardSettingsPanel")
		ns.CreateCardStylePanel(ns.lowHealthKit)
		Lap("CreateCardStylePanel")
		ns.CreateCardSoundsPanel(ns.lowHealthKit)
		Lap("CreateCardSoundsPanel")
	end
	if ns.CreateWindGuidePanel then -- (WindGuide.lua: the dev copy only, CinematicDev.toc)
		ns.CreateWindGuidePanel(ns.lowHealthKit)
		Lap("CreateWindGuidePanel")
	end
	if ns.CreateDamageVisionPanel then -- (DamageVision.lua)
		ns.CreateDamageVisionPanel(ns.lowHealthKit)
		Lap("CreateDamageVisionPanel")
		ns.CreateDamageVisionLookPanel(ns.lowHealthKit)
		Lap("CreateDamageVisionLookPanel")
	end
	if ns.CreateTeleportVisionPanel then -- (TeleportVision.lua)
		ns.CreateTeleportVisionPanel(ns.lowHealthKit)
		Lap("CreateTeleportVisionPanel")
	end
	if ns.CreateEmoteVisionPanel then -- (EmoteVision.lua)
		ns.CreateEmoteVisionPanel(ns.lowHealthKit)
		Lap("CreateEmoteVisionPanel")
		ns.CreateEmoteVisionSettingsPanel(ns.lowHealthKit)
		Lap("CreateEmoteVisionSettingsPanel")
		ns.CreateEmoteVisionStylePanel(ns.lowHealthKit)
		Lap("CreateEmoteVisionStylePanel")
	end
	CreateBuffsPanel()
	Lap("CreateBuffsPanel")
	CreatePlatesPanel()
	Lap("CreatePlatesPanel")
	if ns.CreatePlateIconsPage then -- (PlateIcons.lua: the Nameplates hub's Icons page)
		ns.CreatePlateIconsPage(ns.lowHealthKit)
		Lap("CreatePlateIconsPage")
	end
	CreateChatPanel()
	Lap("CreateChatPanel")
	CreateBubblesPanel()
	Lap("CreateBubblesPanel")
	-- (their hub, Style, listed after Visions)
	CreateNameStylePanel()
	Lap("CreateNameStylePanel")
	CreateTargetArrowPanel()
	Lap("CreateTargetArrowPanel")
	if ns.CreateLetterboxStylePanel then -- (LetterboxStyle.lua)
		ns.CreateEffectPanel(ns.lowHealthKit, "letterbox")
		Lap("CreateEffectPanel")
		ns.CreateLetterboxStylePanel(ns.lowHealthKit)
		Lap("CreateLetterboxStylePanel")
	end
	if ns.CreateQuestItemStylePanel then -- (QuestItemStyle.lua)
		ns.CreateQuestItemStylePanel(ns.lowHealthKit)
		Lap("CreateQuestItemStylePanel")
	end
	if ns.CreateRollStylePanel then -- (RollStyle.lua)
		ns.CreateRollStylePanel(ns.lowHealthKit)
		Lap("CreateRollStylePanel")
	end
	if ns.CreateVitalsStylePanel then -- (LowHealth.lua)
		ns.CreateVitalsStylePanel(ns.lowHealthKit)
		Lap("CreateVitalsStylePanel")
	end
	if ns.CreateQuestTalkStylePanel then -- (QuestTalkStyle.lua)
		ns.CreateQuestTalkStylePanel(ns.lowHealthKit)
		Lap("CreateQuestTalkStylePanel")
	end
	if ns.CreateBubbleStylePanel then -- (BubbleStyle.lua)
		ns.CreateBubbleStylePanel(ns.lowHealthKit)
		Lap("CreateBubbleStylePanel")
	end
	if ns.CreateConflictsPanel then -- (Conflicts.lua)
		ns.CreateConflictsPanel(ns.lowHealthKit)
		Lap("CreateConflictsPanel")
	end
	if ns.CreateCombatTextStylePanel then -- (CombatTextStyle.lua)
		ns.CreateCombatTextStylePanel(ns.lowHealthKit)
		Lap("CreateCombatTextStylePanel")
	end
	if ns.CreateTooltipStylePanel then -- (TooltipStyle.lua)
		ns.CreateTooltipStylePanel(ns.lowHealthKit)
		Lap("CreateTooltipStylePanel")
	end
	if ns.CreateActionBarStylePanel then -- (ActionBarStyle.lua)
		ns.CreateActionBarStylePanel(ns.lowHealthKit)
		Lap("CreateActionBarStylePanel")
	end
	if ns.CreateInterfaceRecolorPanel then -- (InterfaceRecolor.lua)
		ns.CreateInterfaceRecolorPanel(ns.lowHealthKit)
		Lap("CreateInterfaceRecolorPanel")
	end
	if ns.CreatePersonalStylePanel then -- (PersonalStyle.lua)
		ns.CreatePersonalStylePanel(ns.lowHealthKit)
		Lap("CreatePersonalStylePanel")
	end
	if ns.CreateUnitStylePanel then -- (UnitStyle.lua)
		ns.CreateUnitStylePanel(ns.lowHealthKit)
		Lap("CreateUnitStylePanel")
	end
	if ns.CreateRaidStylePanel then -- (RaidStyle.lua)
		ns.CreateRaidStylePanel(ns.lowHealthKit)
		Lap("CreateRaidStylePanel")
	end
	if ns.CreateGeneralStylePanel then -- (GeneralStyle.lua)
		ns.CreateGeneralStylePanel(ns.lowHealthKit)
		Lap("CreateGeneralStylePanel")
		ns.CreateStylePagesPanel(ns.lowHealthKit)
		Lap("CreateStylePagesPanel")
		ns.CreateStyleOverridesPanel(ns.lowHealthKit)
		Lap("CreateStyleOverridesPanel")
	end
	ns.CreateVisionsGeneralPanel() -- (the Visions hub's General: its cards)
	Lap("CreateVisionsGeneralPanel")
	if ns.CreateVisionsStylePanel then -- (VisionsStyle.lua)
		ns.CreateVisionsStylePanel(ns.lowHealthKit)
		Lap("CreateVisionsStylePanel")
	end
	if ns.CreatePlateCastStylePanel then -- (PlateCastStyle.lua)
		ns.CreatePlateCastStylePanel(ns.lowHealthKit)
		Lap("CreatePlateCastStylePanel")
		ns.CreateUnitCastStylePanel(ns.lowHealthKit) -- (the unit frames' cast bars: Unit Frames' Cast Style tab)
		Lap("CreateUnitCastStylePanel")
	end
	CreateEffectsPanel()
	Lap("CreateEffectsPanel")
	ns.CreateEffectPanel(ns.lowHealthKit, "tint") -- (LetterboxStyle.lua: its Show in row)
	Lap("CreateEffectPanel")
	ns.CreateTintStylePanel(ns.lowHealthKit) -- (TintStyle.lua)
	Lap("CreateTintStylePanel")
	CreateGraphicsPanel()
	Lap("CreateGraphicsPanel")
	CreateAudioPanel()
	Lap("CreateAudioPanel")
	CreateCamerasPanel()
	Lap("CreateCamerasPanel")
	if ns.CreateTriggersPanels then -- (TriggersPage.lua)
		ns.CreateTriggersPanels(ns.lowHealthKit)
		Lap("CreateTriggersPanels")
	end
	-- Each camera's own settings, in a section apiece.
	CreateCameraSettingsPanel()
	Lap("CreateCameraSettingsPanel")
	if ns.CreateMyShotsPanel and not ns.SHOTS_RETIRED then -- (ShotsPage.lua; retired in the dev copy)
		ns.CreateMyShotsPanel(ns.lowHealthKit)
		Lap("CreateMyShotsPanel")
	end
	if ns.CreateShoulderCamPanel then -- (ShoulderCam.lua)
		ns.CreateShoulderCamPanel(ns.lowHealthKit)
		Lap("CreateShoulderCamPanel")
	end
	if ns.CreateSkyrideCamPanel then -- (SkyrideCam.lua: retail)
		ns.CreateSkyrideCamPanel(ns.lowHealthKit)
		Lap("CreateSkyrideCamPanel")
	end
	if ns.CreateCameraScriptsPanel then -- (CameraScriptsPage.lua)
		ns.CreateCameraScriptsPanel(ns.lowHealthKit)
		Lap("CreateCameraScriptsPanel")
	end
	if ns.CreateWheelsPanels then -- (WheelsPage.lua; its hub listed after Camera)
		ns.CreateWheelsPanels(ns.lowHealthKit)
		Lap("CreateWheelsPanels")
	end
	CreateFishingPanel()
	Lap("CreateFishingPanel")
	CreateQualityPanel()
	Lap("CreateQualityPanel")
	if ns.CreateKeyboardMapPage then -- (KeyboardMap.lua)
		ns.CreateKeyboardMapPage(ns.lowHealthKit)
		Lap("CreateKeyboardMapPage")
	end
	CreateKeybindsPanel()
	Lap("CreateKeybindsPanel")
	-- Community, last (WhatsNew.lua, with the helpers it shares from here).
	if ns.CreateWhatsNewPanels then
		ns.CreateWhatsNewPanels({ CreateScrollPage = CreateScrollPage, Label = Label, PageShown = PageShown,
			RegisterSubpage = RegisterSubpage, Tooltip = Tooltip })
		Lap("CreateWhatsNewPanels")
	end
	if ns.CreateProfilerPanel then -- (ProfilerPage.lua: the Help hub)
		ns.CreateProfilerPanel(ns.lowHealthKit)
		Lap("CreateProfilerPanel")
	end
	if ns.CreateWhyPanel then -- (Why.lua: the Help hub)
		ns.CreateWhyPanel(ns.lowHealthKit)
		Lap("CreateWhyPanel")
	end
	if ns.CreateGameSettingsPage then -- (GameSettingsPage.lua: the Help hub)
		ns.CreateGameSettingsPage(ns.lowHealthKit)
		Lap("CreateGameSettingsPage")
	end
	-- The dev build's Module Editor, Community's last page (ModuleEditor.lua).
	if ns.isDev and ns.CreateModuleEditor then
		ns.CreateModuleEditor({ CreateScrollPage = CreateScrollPage, Label = Label, PageShown = PageShown,
			RegisterSubpage = RegisterSubpage, Tooltip = Tooltip, PageIntro = PageIntro, Header = Header })
		Lap("CreateModuleEditor")
	end
	if ns.isDev and ns.CreateHeldSettingsPage then -- (HeldSettingsPage.lua: the Dev hub)
		ns.CreateHeldSettingsPage(ns.lowHealthKit)
		Lap("CreateHeldSettingsPage")
	end
	if ns.isDev and ns.CreateDemoHubPage then -- (DemoHub.lua: the Dev hub)
		ns.CreateDemoHubPage(ns.lowHealthKit)
		Lap("CreateDemoHubPage")
	end
	if ns.isDev and ns.CreateMinimapCopyPage then -- (MinimapCopy.lua: the Dev hub)
		ns.CreateMinimapCopyPage(ns.lowHealthKit)
		Lap("CreateMinimapCopyPage")
	end
	ns.AddBandShortcuts("UI Manager") -- (a line for each of the Interface hub's bands, under it)
	ns.AddBandShortcuts("Visions") -- (and the Visions hub's: Combat, World, each Vision under its band)
	menu.Flush() -- (the left list, in menu.order)
	menu.AutoFold()
	GuardGamepadClose()
	Lap("(the left list)")
	local buildEnded = type(buildStarted) == "number" and debugprofilestop()
	if type(buildEnded) == "number" and ns.Log then
		ns.Log("load", ("settings pages made in %d ms"):format(buildEnded - buildStarted))
		table.sort(laps, function(a, b) return a.ms > b.ms end)
		for index = 1, math.min(12, #laps) do
			ns.Log("load", ("  %d ms  %s"):format(laps[index].ms, laps[index].name))
		end
	end
end)
