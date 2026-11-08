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

local function Tooltip(widget, tip)
	widget.searchTip = tip
	widget:SetScript("OnEnter", function(self)
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
			GameTooltip:AddLine(tip, 1, 1, 1, true)
		else
			GameTooltip:SetText(tip, 1, 1, 1, 1, true)
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

-- A row with a page of its own (item.morePage, its English name): a » at the
-- right end of its label, the label that much narrower, that opens the page.
-- (Before ns.LabelHover, which covers the label as it then is.)
function ns.MoreLink(parent, label, page)
	label:SetWidth(label:GetWidth() - 16)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(16, 16)
	button:SetPoint("LEFT", label, "RIGHT", 0, 0)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("CENTER")
	text:SetText("»")
	text.searchSkip = true
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	Tooltip(button, (L["More settings on the %s page. They can keep it up beyond what's ticked here (hovering, " ..
		"tracking, new auras, cooldowns recharging and the like)."]):format(ns.PageLabel(page)) .. "\n\n" ..
		L["Click to open it."])
	button:SetScript("OnClick", function() ns.OpenOptions(page) end)
	return button
end

-- The way back from such a page: a button right of its title (or after, a
-- button there already) to the Game Frames page at its rows' tab (section:
-- its key there, as Frames.lua's ROW_SECTIONS).
function ns.FramesLink(content, title, section, after)
	local button = ns.StyleLink(content, title, "Standard Frames", L["When it shows in CineMode (always, in " ..
		"fights, in places): its rows on the Game Frames page."], Tooltip, L["Game Frames"] .. " »", after)
	button:SetScript("OnClick", function() ns.OpenFramesSection(section) end)
	return button
end

-- What the PvP column or box covers, wherever it appears.
local PVP_TIP = L["While you're flagged for PvP (not in dungeons or raids, nor on flights), and in " ..
	"battlegrounds and arenas."]

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
local function PageIntro(parent, title, text, under)
	-- (A page's first: its intro, behind the "?" on its card on the CineMode page.)
	if parent.introText == nil then parent.introText = text end
	local anchor = CreateFrame("Frame", nil, parent)
	anchor:SetSize(1, 1)
	anchor:SetPoint("TOPLEFT", under or title, "BOTTOMLEFT", 0, -2)

	local help = CreateFrame("Button", nil, anchor)
	help:SetSize(18, 18)
	help:SetPoint("LEFT", title, "RIGHT", 6, 0)
	-- (Above the title's own frame: a camera section's title is on its header.)
	help:SetFrameLevel(math.max(anchor:GetFrameLevel(), title:GetParent():GetFrameLevel()) + 2)
	local ring = help:CreateTexture(nil, "BACKGROUND")
	ring:SetAllPoints()
	ring:SetTexture(ns.HELP_DISC)
	ring:SetVertexColor(0.3, 0.3, 0.3, 0.9)
	local mark = help:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mark:SetPoint("CENTER", 1, 0)
	mark:SetText("?")
	mark.searchSkip = true
	Tooltip(help, text)
	help:HookScript("OnEnter", function() mark:SetTextColor(1, 1, 1) end)
	help:HookScript("OnLeave", function() mark:SetTextColor(1, 0.82, 0) end)
	help.searchNote = text
	help.searchEdges = { top = title, bottom = title, left = title, right = help }
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
	if type(key) ~= "string" then return end
	control.settingKey = key
	if not settingMakers[key] then settingMakers[key] = { make = make, control = control } end
end

local function Stack(anchor, kind, inline)
	local stack = { last = anchor, kind = kind or "header", indent = 0, inline = inline, rows = {} }
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
		indent = indent or 0
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
		Tooltip(box, (tip and tip .. " " or "") .. L["Scroll the mouse wheel over it, or type a number and press Enter."])
		return box, name
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
	local frame = control.GetParent and control:GetParent()
	while frame and not frame.pageWatch do
		frame = frame:GetParent()
	end
	control.onSettingsPage = frame -- (not kept when nil: its page may not be registered yet)
	return frame
end

-- Every control as its setting is now. Only the pages on screen: a page out
-- of sight is marked stale and refreshed as it comes into view (its
-- pageWatch), as a switch of profile refreshing them all took ~130 ms.
local function Refresh()
	if not ns.GetDB() then return end
	local timing = ns.isDev and { count = #controls, slowest = {} }
	ns.pageTiming = timing
	for _, control in ipairs(controls) do
		local page = PageOf(control)
		if page and not page:IsVisible() then
			page.stale = true
		else
			if page then page.stale = nil end -- (refreshed now: its pageWatch needn't again)
			RefreshControl(control, timing)
		end
	end
	if ns.PaintPageSwitches then ns.PaintPageSwitches() end -- (the hub icons' Off marks)
end

-- A page's master switch at the top (below anchor): "CineMode <page>". Not
-- shown: a right-click on the page's icon (or folder tab) flips it, and the
-- icon says whether it's on. (Kept, 1 high, for the page's layout and greying.)
local function RegisterPageSwitch(content, key, check)
	pageSwitches[content] = { key = key, check = check }
	if check then
		check:Hide()
		check:SetHeight(1)
		check.searchLabel = nil
		check.hiddenSwitch = true -- (the stack under it starts close: Stack's Add)
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
		{ "Health", L["Health bar"] }, { "Power", L["Power bar"] }, { "Numbers", L["Bar numbers"] },
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
	Tooltip(reset, L["Put this page's settings back to the active profile's own values (the defaults, " ..
		"or a built-in profile's)."])
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
		C_Timer.After(0, function() FitContentHeight(content) end)
	end
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
local function BuildSearchIndex(pages)
	Refresh() -- (slider titles and some rows are only filled in on refresh)
	local entries = {}
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
	end
	return entries
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
	if not entry.edges then return end
	local canvas = entry.page.canvas
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
	local parts = {}
	for part in (type(query) == "string" and query or ""):gmatch("[^|]+") do
		part = part:match("^%s*(.-)%s*$"):lower()
		if part ~= "" then parts[#parts + 1] = part end
	end
	local words = table.remove(parts)
	if not words then return nil end
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
	versionLabel:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)

	local subtitle = PageIntro(panel, title,
		L["Fades the UI and adds letterbox bars between fights. Combat, casting " ..
		"and opening windows like the spellbook bring it back. Typing just shows the chat. The " ..
		"pages under this one cover what shows when (CineMode, Game Frames, Addon Frames, Minimap, Quest tracker, Nameplates, " ..
		"Chat), visual effects and sound, the camera modes and triggers, and keybinds."])

	local searchBox = CreateSearch(mainCanvas, panel)
	searchBox:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 6, -14)

	-- Left column: general
	local general = Header(panel, L["General"], subtitle, -54)

	local enabled
	enabled = Check(panel, "enabled", L["Enable Cinematic"],
		L["Off turns Cinematic off completely: it asks, then turns it off in the game's AddOns list and " ..
		"reloads, so nothing of it runs. Tick it in the AddOns list to bring it back. Also with /cine."],
		function(value)
			if value then
				ns.SetEnabled(true)
			else
				-- (Stays ticked till the reload; ticked again if you cancel.)
				enabled:SetChecked(true)
				ns.TurnOffCompletely()
			end
		end)
	enabled:SetPoint("TOPLEFT", general, "BOTTOMLEFT", -2, -6)

	local fadeUI = Check(panel, "fadeUI", L["Start in CineMode (fade UI, queue music, etc.)"],
		L["Off: the UI stays as it is and the camera's left to you, with just the visual effects " ..
		"over it (as the Visual Effects page says), as in the Subtle profile. Triggers with CineMode " ..
		"ticked on the Scenes page still bring CineMode on while their camera " ..
		"runs: standing still or going AFK, say, for a screensaver."])
	fadeUI:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -2)

	local minimapButton = Check(panel, "minimapButton", L["Show minimap button"],
		L["Click it for quick options and a link to these settings, drag to move it."], function(value)
			ns.GetDB().minimapButton = value
			if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		end)
	minimapButton:SetPoint("TOPLEFT", fadeUI, "BOTTOMLEFT", 0, -2)

	-- (Only where the game has a compartment.)
	local aboveGlow = minimapButton
	if AddonCompartmentFrame then
		aboveGlow = Check(panel, "addonCompartment", L["Show in addon compartment"],
			L["Lists Cinematic in the game's addon list by the minimap. Its clicks work like the minimap button's."],
			function(value)
				ns.GetDB().addonCompartment = value
				if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
			end)
		aboveGlow:SetPoint("TOPLEFT", minimapButton, "BOTTOMLEFT", 0, -2)
	end

	local glowHelper = Check(panel, "minimapHelper", L["Minimap Glow Helper"],
		L["While a vision is doing something (Heal Vision fading frames, a duel being watched, the roll " ..
		"window up...), the minimap button glows in its color. Its menu and tooltip list that vision, and " ..
		"the camera running, with a link to its page."])
	glowHelper:SetPoint("TOPLEFT", aboveGlow, "BOTTOMLEFT", 0, -2)

	local slashComplete = Check(panel, "slashComplete", L["Suggest /cine commands while typing"],
		L["Typing /cine in the chat box lists the commands that fit, the ones you use most first. " ..
		"Up and Down pick one (Enter runs it), Tab or a click fills it in and shows what can follow it."])
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
	Tooltip(language, L["The language Cinematic's text is in, for all your characters. Game language " ..
		"follows the game's (English where Cinematic has no translation yet). A change needs a reload."])
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
		Tooltip(skinMenu, L["The look of Cinematic's settings pages and windows, for all your characters. HD: " ..
			"flat and dark, with thin edges. SD: the game's own buttons and windows. Auto: HD on retail, SD on " ..
			"classic, and on WoW Forever as your Character Models setting is (Standard: SD)."])
		controls[#controls + 1] = skinMenu
	end

	-- Right column: places
	local placesHeader = Label(panel, "GameFontNormal", L["Turn off in"])
	placesHeader:SetPoint("TOPLEFT", general, "TOPLEFT", 320, 0)

	-- Stored the other way round (stayInCombat), as the Standard Frames page's lists apply while staying.
	local combat = Check(panel, "stayInCombat", L["Combat"],
		L["Being in combat brings the UI back. Unticked, CineMode stays on in fights: only the frames " ..
		"ticked under In combat on the Game Frames page show. (Targeting an enemy only ever shows " ..
		"the frames chosen for it there.)"], function(value)
			ns.GetDB().stayInCombat = not value
			Refresh()
		end)
	combat.Refresh = function(self) self:SetChecked(not ns.GetDB().stayInCombat) end
	combat:SetPoint("TOPLEFT", placesHeader, "BOTTOMLEFT", -2, -6)

	-- Places in the same order as every other place list (PlaceList).
	local world = Check(panel, "offInWorld", L["Open world"],
		L["Anywhere outside cities, dungeons and raids (inns too), while you're not PvP flagged. " ..
		"Flights still go cinematic."])
	world:SetPoint("TOPLEFT", combat, "BOTTOMLEFT", 0, -2)

	local cities = Check(panel, "offInCities", L["Cities"],
		L["Capital cities, including Dalaran. Flights leaving a city still go cinematic."])
	cities:SetPoint("TOPLEFT", world, "BOTTOMLEFT", 0, -2)

	local dungeons = Check(panel, "offInDungeons", L["Dungeons"],
		L["Keep the normal UI in dungeons and scenarios."])
	dungeons:SetPoint("TOPLEFT", cities, "BOTTOMLEFT", 0, -2)

	local raids = Check(panel, "offInRaids", L["Raids"])
	raids:SetPoint("TOPLEFT", dungeons, "BOTTOMLEFT", 0, -2)

	local pvp = Check(panel, "offInPvP", L["PvP"], PVP_TIP)
	pvp:SetPoint("TOPLEFT", raids, "BOTTOMLEFT", 0, -2)

	local party = Check(panel, "offInParty", L["Party"],
		L["Keep the normal UI while you're in a party (but not a raid group)."])
	party:SetPoint("TOPLEFT", pvp, "BOTTOMLEFT", 0, -2)

	local raidGroup = Check(panel, "offInRaidGroup", L["Raid group"],
		L["Keep the normal UI while you're in a raid group, wherever you are."])
	raidGroup:SetPoint("TOPLEFT", party, "BOTTOMLEFT", 0, -2)

	local moving = Check(panel, "offWhileMoving", L["Moving"],
		L["Walking or riding about yourself brings the UI back (names too), say to look for an NPC " ..
		"in a city. CineMode comes back once you've stood still, or kept moving, for the time " ..
		"below. Auto-run, RP walking and flights stay in CineMode."],
		function(value)
			ns.GetDB().offWhileMoving = value
			Refresh()
		end)
	moving:SetPoint("TOPLEFT", raidGroup, "BOTTOMLEFT", 0, -2)

	-- (Indented under Moving, as its sub-options.)
	local movingVFX = Check(panel, "movingKeepVFX", L["Keep VFX on"],
		L["The visual effects (letterbox, tint and the rest on the Visual Effects page) stay on " ..
		"while moving brings the UI back."])
	movingVFX:SetPoint("TOPLEFT", moving, "BOTTOMLEFT", 24, -2)
	GreyUnless(movingVFX, function(db) return db.offWhileMoving end)

	local movingBack = Slider(panel, "movingBackAfter", L["Back after"], 1, 60, 1, L["%d sec"])
	movingBack:SetPoint("TOPLEFT", movingVFX, "BOTTOMLEFT", 4, -26)
	movingBack:SetWidth(176)
	Tooltip(movingBack, L["CineMode comes back once you've stood still this long, or kept moving " ..
		"this long without stopping (a long walk or ride)."])
	GreyUnless(movingBack, function(db) return db.offWhileMoving end)

	local defaults = ns.PanelButton(panel)
	defaults:SetSize(140, 22)
	defaults:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -12)
	defaults:SetText(L["Reset addon"])
	defaults.searchSkip = true
	Tooltip(defaults, L["Reset Settings puts every setting back and keeps what you made: your own profiles, " ..
		"cameras, scripts, themes and backups. Reset EVERYTHING deletes all of it. Either reloads the UI."])
	defaults:SetScript("OnClick", function()
		ns.ShowResetPopup()
	end)
	-- The active profile, under the button (picked on the Profiles page).
	local profileLabel = Label(panel, "GameFontHighlightSmall")
	profileLabel:SetPoint("RIGHT", defaults, "LEFT", -10, 0)
	profileLabel:SetJustifyH("RIGHT")
	controls[#controls + 1] = { Refresh = function()
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

-- Hubs: a sub-page holding several pages, picked from a row of icons at its
-- top (the page shows under them, its name on the icon's mouseover). Above
-- the icons, a search box for all its pages and Reset page for the one shown.
-- HubAdd(canvas, name, searchPage) takes a page into its hub (false: in none);
-- HubTab(name) shows a page in its hub and gives the hub's name (false: in none).
do
	-- Each hub (by English name) and its pages in order, with their icons
	-- (or a function that gives one).
	local HUBS = {
		-- (sections: when frames show (Visibility), then each frame's own page:
		-- the HUD's, then what floats over heads, as on the Style hub. label: the
		-- hub's name as shown, its pages' ids staying "UI Manager"'s.)
		{ name = "UI Manager", label = "Interface", colors = {
			Visibility = { 0.75, 0.65, 0.45 }, HUD = { 0.35, 0.6, 0.9 }, Overhead = { 0.65, 0.45, 0.9 },
		}, pages = {
			-- (A standard: your faction's battle banner.)
			{ "Standard Frames", function()
				return UnitFactionGroup("player") == "Horde" and "Interface\\Icons\\INV_BannerPVP_01"
					or "Interface\\Icons\\INV_BannerPVP_02"
			end, label = "Game Frames", section = "Visibility" },
			{ "Advanced Frames", "Interface\\Icons\\INV_Misc_Gear_01", label = "Addon Frames", section = "Visibility" },
			{ "Mouseover groups", "Interface\\Icons\\Spell_Holy_MindVision", label = "Hover Groups", section = "Visibility" },
			{ "Gamepad", "Interface\\Icons\\INV_Gizmo_01", label = "Gamepad Frames", section = "Visibility" },
			{ "Unit Frames", "Interface\\Icons\\INV_Misc_Head_Dwarf_01", section = "HUD" },
			{ "Personal Resources", "Interface\\Icons\\Ability_Racial_BloodRage", -- (Bloodrage: health into power)
				label = "Resource Display", section = "HUD" },
			{ "Buffs/debuffs", "Interface\\Icons\\Spell_Holy_WordFortitude", label = "Buffs/Debuffs", section = "HUD" },
			{ "Cooldown Manager", "Interface\\Icons\\INV_Misc_PocketWatch_01", section = "HUD" },
			{ "Swing timer", "Interface\\Icons\\INV_Sword_04", label = "Swing Timer", section = "HUD" },
			{ "Minimap", "Interface\\Icons\\INV_Misc_Map_01", section = "HUD" },
			{ "Quest tracker", "Interface\\Icons\\INV_Misc_Note_01", label = "Quest Tracker", section = "HUD" },
			{ "Tooltips", "Interface\\Icons\\INV_Misc_Book_09", section = "HUD" },
			{ "Chat", "Interface\\Icons\\INV_Scroll_03", section = "HUD" },
			{ "Nameplates", "Interface\\Icons\\Ability_Hunter_SniperShot", section = "Overhead" },
			{ "Chat bubbles", "Interface\\Icons\\Ability_Warrior_BattleShout", label = "Chat Bubbles", section = "Overhead" },
			{ "Cursor Hide", "Interface\\Icons\\INV_Misc_Eye_01", section = "Overhead" }, -- (CursorHide.lua)
		} },
		-- (Cameras: what everyone has; Dev: the dev copy's own, to the right)
		-- (master: Enable Cameras; its pages with no switch of their own show Off with it)
		{ name = "Camera", master = "cameraModes", colors = { Cameras = { 0.35, 0.6, 0.9 }, Dev = { 0.85, 0.3, 0.25 } },
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
			end, section = "Cameras" },
			{ "Camera Settings", "Interface\\Icons\\Trade_Engineering", dev = true, section = "Dev" }, -- (settings no script step uses)
			{ "Shoulder Cam", "Interface\\Icons\\INV_Shoulder_02", dev = true, section = "Dev" }, -- (ShoulderCam.lua)
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
			{ "Graphics+", "Interface\\Icons\\INV_Misc_Gem_Pearl_04", section = "Visuals" },
			{ "Audio", "Interface\\Icons\\INV_Misc_Drum_01", section = "Audio" },
		} },
		-- (section: its pages on a band in its color, its name above it; all in
		-- one row: the HUD's frames, then what floats over heads in the world.
		-- The picked page's band in gold, the rest faded. Cinematic's own looks
		-- are Style tabs on their own pages. after: listed right after UI
		-- Manager, at the same level.)
		{ name = "Style", after = "UI Manager", colors = {
			HUD = { 0.35, 0.6, 0.9 }, Overhead = { 0.65, 0.45, 0.9 },
		}, pages = {
			{ "Style General", "Interface\\Icons\\INV_Misc_Gear_08", label = "General" },
			{ "Style Pages", "Interface\\Icons\\INV_Misc_Gear_08", tabOf = "Style General" }, -- (GeneralStyle.lua)
			{ "Style Overrides", "Interface\\Icons\\INV_Misc_Gear_08", tabOf = "Style General" }, -- (StyleOverrides.lua)
			{ "Unit Style", "Interface\\Icons\\INV_Misc_Head_Human_01", label = "Unit Frames", section = "HUD" },
			{ "Raid Style", "Interface\\Icons\\INV_Misc_GroupNeedMore", label = "Raid Frames", section = "HUD" },
			{ "Action Style", "Interface\\Icons\\Ability_DualWield", label = "Action Bars", section = "HUD" },
			{ "Personal Style", "Interface\\Icons\\Spell_Holy_SealOfVengeance", label = "Personal Resource Display",
				section = "HUD" },
			{ "Tooltip Style", "Interface\\Icons\\INV_Misc_Note_05", label = "Tooltips", section = "HUD" },
			{ "Nameplate Style", "Interface\\Icons\\Ability_Marksmanship", label = "Nameplates", section = "Overhead" },
			{ "Name Style", "Interface\\Icons\\INV_Misc_Note_02", label = "Names", section = "Overhead" },
			{ "Cast Bar Style", "Interface\\Icons\\Spell_Nature_Lightning", label = "Cast Bars", section = "Overhead" },
			{ "Bubble Style", "Interface\\Icons\\Ability_Warrior_RallyingCry", label = "Chat Bubbles",
				section = "Overhead" },
		} },
		-- (General and the dev copy's Wind Guide in no section: plain icons)
		{ name = "Visions", colors = { Combat = { 0.85, 0.3, 0.25 }, World = { 0.35, 0.6, 0.9 } }, pages = {
			-- (VisionsStyle.lua: the look they share; in no section, a band of its own)
			{ "Visions Style", "Interface\\Icons\\INV_Misc_Gear_08", label = "Style" },
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
			{ "Teleport Vision", "Interface\\Icons\\Spell_Arcane_TeleportStormWind", label = "Tele Vision",
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
		{ name = "Quality of life", colors = { Helpers = { 0.3, 0.7, 0.5 } }, pages = {
			{ "General", "Interface\\Icons\\INV_Misc_Bag_07" },
			{ "Fishing", "Interface\\Icons\\Trade_Fishing", section = "Helpers" },
			{ "Hunter", "Interface\\Icons\\INV_Weapon_Bow_07", section = "Helpers" },
			{ "Keyboard Map", "Interface\\Icons\\INV_Misc_Note_06", section = "Helpers" }, -- (KeyboardMap.lua)
		} },
		-- (WheelsPage.lua's pages; listed under Quality of life. The master wheel first, plain; the wheels it opens on a band.)
		{ name = "Wheels", under = "Quality of life", colors = { Wheels = { 0.65, 0.45, 0.9 } }, pages = {
			{ "Master wheel", "Interface\\Icons\\Spell_Nature_WispSplode" },
			{ "Your wheels", "Interface\\Icons\\INV_Misc_Note_01" },
			{ "Camera wheel", "Interface\\Icons\\INV_Misc_Spyglass_03", section = "Wheels" },
			{ "Menu wheel", "Interface\\Icons\\INV_Misc_Gear_01", section = "Wheels" },
			{ "Marker wheel", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", section = "Wheels" },
			{ "Ground marker wheel", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", section = "Wheels" },
			{ "Vision wheel", "Interface\\Icons\\Ability_EyeOfTheOwl", section = "Wheels" },
		} },
		-- (WhatsNew.lua's pages, after Keybinds)
		-- (Help: where to read up and report a problem, and the Profiler; Dev:
		-- the dev copy's own tools)
		{ name = "Community", colors = { Updates = { 0.35, 0.6, 0.9 }, People = { 0.3, 0.7, 0.5 },
			Help = { 0.85, 0.6, 0.3 }, Dev = { 0.85, 0.3, 0.25 } }, pages = {
			{ "New features", "Interface\\Icons\\INV_Misc_Gift_01", section = "Updates" },
			{ "All changes", "Interface\\Icons\\INV_Misc_Book_11", section = "Updates" },
			{ "Socials", "Interface\\Icons\\INV_Letter_15", section = "People" },
			{ "Thanks", "Interface\\Icons\\INV_ValentinesCard02", section = "People" },
			{ "Help", "Interface\\Icons\\INV_Misc_QuestionMark", section = "Help" }, -- (WhatsNew.lua)
			{ "Profiler", "Interface\\Icons\\INV_Misc_PocketWatch_02", section = "Help" }, -- (ProfilerPage.lua)
			{ "Why showing", "Interface\\Icons\\Ability_Hunter_EagleEye", label = "Why Is It Showing?", section = "Help" }, -- (Why.lua)
			{ "Module Editor", "Interface\\Icons\\INV_Misc_Wrench_01", section = "Dev", dev = true }, -- (ModuleEditor.lua)
		} },
		-- (The dev copy's own hub: none of its pages are in the release, so neither is it.)
		{ name = "Dev", pages = {
			{ "Held Game Settings", "Interface\\Icons\\INV_Gizmo_02", dev = true }, -- (HeldSettingsPage.lua)
			{ "Demo Commands", "Interface\\Icons\\INV_Misc_Film_01", dev = true }, -- (DemoHub.lua)
		} },
	}
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
			if x > EDGE and x + wide > width - EDGE then
				x, y = EDGE, y - LABEL_H - high - TILE_GAP
			end
			local band = Band(hub, run.section or index, run.section)
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
			x = x + wide + SECTION_GAP
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
		local left = EDGE
		local perRow = math.max(1, math.floor((width - left - EDGE + TILE_GAP) / (TILE + TILE_GAP)))
		local column, row = 0, 0
		local function Place(tile)
			if column >= perRow then
				column, row = 0, row + 1
			end
			local y = -BAR - EDGE - row * (TILE + TILE_GAP)
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", hub.frame, "TOPLEFT", left + column * (TILE + TILE_GAP), y)
			tile:Show()
			column = column + 1
		end
		for _, tile in ipairs(hub.tiles) do Place(tile) end
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
		local previous = hub.current
		if previous then
			if previous.canvas ~= tile.canvas then previous.canvas:Hide() end
			Light(Lit(previous), false)
		end
		hub.current = tile
		Light(Lit(tile), true)
		PaintBands(hub)
		if tile.onSelect then tile.onSelect() end
		tile.canvas:Show()
		-- (Reset page: for a page with settings of its own)
		hub.reset:SetShown(pageKeys[tile.resetContent or tile.canvas.content] ~= nil)
		if ns.PaintPageSwitches then ns.PaintPageSwitches() end -- (its off card)
	end

	-- (made when its first page comes, so it's listed where that page would be)
	local function CreateHub(hub)
		-- (hub.under: listed under that hub, made first, not under Cinematic.
		-- hub.after: that hub made first, so this one is listed right after it.)
		local parentHub
		for _, each in ipairs(HUBS) do
			if each.name == hub.under then parentHub = each end
			if each.name == hub.after and not each.frame then CreateHub(each) end
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
		Tooltip(reset, L["Put this page's settings back to the active profile's own values (the defaults, " ..
			"or a built-in profile's)."])
		reset:SetScript("OnClick", function()
			if hub.current then
				StaticPopup_Show("CINEMATIC_RESET_PAGE", nil, nil,
					hub.current.resetContent or hub.current.canvas.content)
			end
		end)
		hub.reset = reset
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
		if category and Settings and Settings.RegisterCanvasLayoutSubcategory then
			local parentSub = parentHub and subpages[parentHub.name] or category
			local sub = Settings.RegisterCanvasLayoutSubcategory(parentSub, frame, L[hub.label or hub.name])
			-- (the hub it's under starts open in the list, so this one shows)
			if parentHub then
				if parentSub.SetExpanded then parentSub:SetExpanded(true) else parentSub.expanded = true end
			end
			Settings.RegisterAddOnCategory(sub)
			subpages[hub.name] = sub
		else
			subpages[hub.name] = frame
			if parentHub then parentHub.frame.collapsed = false end
			if InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(frame) end
		end
	end

	-- A tile's page switch (its hidden Enable Page: RegisterPageSwitch), or nil.
	-- A page with none in a hub with a master (hub.master: Enable Cameras)
	-- follows that: Off on its icon with it, nothing to flip.
	local function TileSwitch(tile)
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
	-- A page's icon darkened, "Off" on it, while its switch is off.
	local function PaintSwitch(tile)
		local switch = TileSwitch(tile)
		local off = switch and not SwitchState(switch) or false
		if off and not tile.offMark then
			tile.offMark = tile:CreateTexture(nil, "OVERLAY")
			tile.offMark:SetAllPoints(tile.icon)
			tile.offMark:SetColorTexture(0, 0, 0, 0.55)
			tile.offText = tile:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
			tile.offText:SetPoint("BOTTOM", tile.icon, "BOTTOM", 0, 2)
			tile.offText.searchSkip = true
		end
		if tile.offMark then
			tile.offText:SetText(L["Off"])
			tile.offMark:SetShown(off)
			tile.offText:SetShown(off)
		end
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
		-- (the page it faded last time back, whichever shows now)
		if card and card.faded then
			card.faded:SetAlpha(1)
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
		local name = L[tile.label or tile.english]
		card.icon:SetTexture(tile.icon:GetTexture())
		card.title:SetText("|cffff5a40" .. L["%s is off"]:format(name) .. "|r")
		card.text:SetText(stuck and L["Off with the General page's switch."]
			or L["Turn it on to see and change its settings."])
		card.button:SetText(L["Turn on %s"]:format(name))
		card.button.switch = box
		card.button:SetShown(not stuck)
		card.box:SetHeight(math.max(32, card.title:GetStringHeight() + 3 + card.text:GetStringHeight()) + 20)
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
			local switch = TileSwitch(self)
			if switch then SwitchLine(switch) end
			GameTooltip:Show()
		end)
		tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
		-- (Right-click: its page's switch flipped, the page left as it is.)
		tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		tile:SetScript("OnClick", function(self, button)
			if button ~= "RightButton" then return Select(self) end
			local switch = TileSwitch(self)
			if not switch then return end
			FlipSwitch(switch)
			if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
		end)
		return tile
	end

	function HubAdd(canvas, name, searchPage)
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
						tile.section = tab.section or page.section
						tile.onSelect, tile.resetContent = tab.onSelect, tab.resetContent
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
						if page.tabOf then
							tile.tabOf = page.tabOf
							tile:Hide()
						else
							hub.tiles[#hub.tiles + 1] = tile
						end
						if i == 1 then
							byName[name], byName[english] = tile, tile
						end
					end
					table.sort(hub.tiles, function(a, b) return a.order < b.order end)
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

	function HubTab(name)
		local tile = byName[name]
		if not tile then return false end
		-- (already on that page, at another of its tabs: left there)
		local current = tile.hub.current
		if not (current and current.canvas == tile.canvas) then
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
		local switch = byName[name] and TileSwitch(byName[name])
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
						local switch = TileSwitch(tile)
						local on, held = false, false
						if switch then on, held = SwitchState(switch) end
						local content = tile.resetContent or (tile.canvas and tile.canvas.content)
						list[#list + 1] = { name = page[1], label = L[page.label or page[1]],
							icon = type(page[2]) == "function" and page[2]() or page[2],
							intro = content and content.introText, hasSwitch = switch ~= nil, dev = page.dev,
							on = on, held = held, fixed = (switch and switch.follows or held) and true or false }
					end
				end
				return list, L[hub.label or hub.name]
			end
		end
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
	local page = { name = shown or L[name], key = name, canvas = subpanel }
	searchPages[#searchPages + 1] = page
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
	end
	if category and Settings and Settings.RegisterCanvasLayoutSubcategory then
		local sub = Settings.RegisterCanvasLayoutSubcategory(category, subpanel, L[name])
		Settings.RegisterAddOnCategory(sub)
		subpages[name] = sub
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(subpanel)
	end
end

-- Sub-page: what brings faded things back, and what stays up.
local function CreateRevealPanel()
	local canvas, content = CreateScrollPage()

	-- Folder tabs at the top: one for each hub CineMode works through, its pages
	-- on cards (on or off, a click away) built from the hubs as they first show;
	-- then Settings, this page's own (everything made on it below the cards,
	-- moved onto host).
	local OVERVIEW_HUBS = {
		{ "UI Manager", L["Interface"], L["What fades in CineMode, and what brings it back."] },
		{ "Atmosphere", L["Atmosphere"], L["How the world looks and sounds in CineMode."] },
		{ "Camera", L["Camera"], L["The camera coming alive while CineMode is on."] },
	}
	local SETTINGS_TAB = #OVERVIEW_HUBS + 1
	local overview, host, PickTab, FillOverview
	local picked = 1 -- (the tab shown, kept while the game runs)
	local tabList = {}
	for i, group in ipairs(OVERVIEW_HUBS) do tabList[i] = { group[2], group[3] } end
	tabList[SETTINGS_TAB] = { L["Settings"], L["How fast the UI fades, the Calm Timer, combat text and error messages."] }
	local tabsPanel, _, ShowTab, tabsBase = ns.FolderTabs(content, tabList, function(i) PickTab(i) end)
	tabsBase:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -(ns.FOLDER_TAB_HEIGHT + 16))
	tabsPanel:SetPoint("TOPLEFT", tabsBase)
	tabsPanel:SetPoint("RIGHT", content, "RIGHT", -8, 0)
	tabsPanel:SetHeight(1) -- (just its top edge, a line under the tabs)

	local title = Label(content, "GameFontNormalLarge", "CineMode")
	title:SetPoint("TOPLEFT", tabsPanel, "BOTTOMLEFT", 8, -14)

	-- A hub's tab: a card for each of its pages, in two columns either side of
	-- mid (icon, name, its intro behind a "?", a switch; a click opens the page).
	-- Dev-only pages have a red X over the icon, as on their hub's.
	overview = CreateFrame("Frame", nil, content)
	overview:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
	overview:SetPoint("RIGHT", content, "RIGHT", -16, 0)
	overview:SetHeight(1)
	overview.searchSkip = true -- (the settings' own pages are what search finds)
	local mid = CreateFrame("Frame", nil, overview)
	mid:SetSize(1, 1)
	mid:SetPoint("TOP", overview, "TOP")
	local summary = Label(overview, "GameFontHighlightSmall")
	summary:SetPoint("BOTTOMRIGHT", overview, "TOPRIGHT", 0, 16)
	local CARD_H, CARD_GAP = 42, 8
	local SWITCH_W, SWITCH_H, KNOB = 34, 16, 12
	local cards = {}
	local function StateTip(self)
		local page = self.page
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.title, 1, 0.82, 0)
		if page.held then
			GameTooltip:AddLine(L["Off with the General page's switch."], 1, 0.25, 0.25, true)
		elseif page.fixed then
			GameTooltip:AddLine(L["On and off with the General page's switch."], 1, 1, 1, true)
		elseif page.on then
			GameTooltip:AddLine(L["On. Click to turn this page off."], 0.25, 1, 0.25, true)
		else
			GameTooltip:AddLine(L["Off. Click to turn this page on."], 1, 0.25, 0.25, true)
		end
		GameTooltip:Show()
	end
	local function MakeCard(page, tab, spot)
		local card = CreateFrame("Button", nil, overview)
		card:SetHeight(CARD_H)
		local y = -math.floor((spot - 1) / 2) * (CARD_H + CARD_GAP)
		if spot % 2 == 1 then
			card:SetPoint("TOPLEFT", overview, "TOPLEFT", 0, y)
			card:SetPoint("TOPRIGHT", mid, "TOP", -CARD_GAP / 2, y)
		else
			card:SetPoint("TOPLEFT", mid, "TOP", CARD_GAP / 2, y)
			card:SetPoint("TOPRIGHT", overview, "TOPRIGHT", 0, y)
		end
		local bg = card:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.06, 0.75)
		for i, corners in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
			{ "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
			local line = card:CreateTexture(nil, "BORDER")
			line:SetColorTexture(0.22, 0.22, 0.22, 1)
			line:SetPoint(corners[1])
			line:SetPoint(corners[2])
			if i <= 2 then line:SetHeight(1) else line:SetWidth(1) end
		end
		local hover = card:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 0.82, 0, 0.07)
		card.icon = card:CreateTexture(nil, "ARTWORK")
		card.icon:SetSize(28, 28)
		card.icon:SetPoint("LEFT", 8, 0)
		card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		card.icon:SetTexture(page.icon)
		if page.dev and card.CreateLine then
			for _, corners in ipairs({ { "TOPLEFT", "BOTTOMRIGHT" }, { "TOPRIGHT", "BOTTOMLEFT" } }) do
				local line = card:CreateLine(nil, "OVERLAY")
				line:SetThickness(2)
				line:SetColorTexture(1, 0.15, 0.15, 0.9)
				line:SetStartPoint(corners[1], card.icon, 0, 0)
				line:SetEndPoint(corners[2], card.icon, 0, 0)
			end
		end
		-- (A hub's General page by its own name: Effects, Cameras)
		card.label = Label(card, "GameFontHighlight", page.label == L["General"] and L[page.name] or page.label)
		card.label:SetPoint("LEFT", card.icon, "RIGHT", 10, 0)
		-- (Its page's whole intro on a "?" beside the name, as on the page itself.)
		if type(page.intro) == "string" then PageIntro(card, card.label, page.intro) end
		Tooltip(card, L["Go to this page."])
		card:SetScript("OnClick", function() ns.OpenOptions(page.name) end)
		-- (The switch: a click flips the page's, as a right-click on its icon does.)
		local state = CreateFrame("Button", nil, card)
		state:SetSize(SWITCH_W + 20, CARD_H) -- (more to click than the switch drawn)
		state:SetPoint("RIGHT", 0, 0)
		state.track = state:CreateTexture(nil, "ARTWORK")
		state.track:SetSize(SWITCH_W, SWITCH_H)
		state.track:SetPoint("CENTER")
		state.knob = state:CreateTexture(nil, "OVERLAY")
		state.knob:SetSize(KNOB, KNOB)
		state:SetScript("OnEnter", StateTip)
		state:SetScript("OnLeave", function() GameTooltip:Hide() end)
		state:SetScript("OnClick", function(self)
			if self.page.fixed then return end
			ns.FlipPageSwitch(self.page.name)
			FillOverview()
			if GameTooltip:IsOwned(self) then StateTip(self) end
		end)
		state.title = card.label:GetText()
		card.state = state
		card.tab = tab
		return card
	end
	local function PaintSwitch(state, page)
		local dim = page.fixed and 0.6 or 1
		if page.on then
			state.track:SetColorTexture(0.16 * dim, 0.62 * dim, 0.24 * dim, 1)
		else
			state.track:SetColorTexture(0.2, 0.2, 0.22, 1)
		end
		state.knob:SetColorTexture(0.92 * dim, 0.92 * dim, 0.92 * dim, 1)
		state.knob:ClearAllPoints()
		local inset = (SWITCH_H - KNOB) / 2
		if page.on then
			state.knob:SetPoint("RIGHT", state.track, "RIGHT", -inset, 0)
		else
			state.knob:SetPoint("LEFT", state.track, "LEFT", inset, 0)
		end
	end
	-- Every card as its page is now, the picked tab's shown, and how many of
	-- those are on.
	function FillOverview()
		if not ns.GetDB() then return end
		local states = {}
		for tab, group in ipairs(OVERVIEW_HUBS) do
			for spot, page in ipairs(ns.HubPageStates(group[1]) or {}) do
				states[page.name] = page
				cards[page.name] = cards[page.name] or MakeCard(page, tab, spot)
			end
		end
		local count, onCount = 0, 0
		for name, card in pairs(cards) do
			local page, state = states[name], card.state
			card:SetShown(card.tab == picked)
			if page and page.hasSwitch then
				if card.tab == picked then
					count = count + 1
					if page.on then onCount = onCount + 1 end
				end
				state.page = page
				PaintSwitch(state, page)
				state:Show()
			else
				state:Hide()
			end
			local off = page and page.hasSwitch and not page.on or false
			card.icon:SetDesaturated(off)
			card.icon:SetAlpha(off and 0.6 or 1)
			local tone = off and 0.6 or 1
			card.label:SetTextColor(tone, tone, tone)
			card.label:SetVertexColor(tone, tone, tone) -- (one on Forever)
		end
		summary:SetText(L["%d of %d pages on."]:format(onCount, count))
		FitContentHeight(content)
	end

	-- (What's on the page so far: the tabs, title and overview stay where they
	-- are; whatever's made after goes onto the Settings tab's host, below.)
	local before = {}
	for _, object in ipairs({ content:GetChildren() }) do before[object] = true end
	for _, object in ipairs({ content:GetRegions() }) do before[object] = true end

	local subtitle = PageIntro(content, title,
		L["How fast the UI fades, what brings it (or parts of it) back while CineMode " ..
		"is on, and combat text. Fights and targeting are on the Game Frames page, names and " ..
		"nameplates on the Nameplates page, buffs on the " ..
		"Buffs/debuffs page, the minimap on the Minimap page, the quest tracker on the Quest tracker page, " ..
		"chat on the Chat page."])

	-- Each slider on one line with its name (an inline stack, as on Graphics+).
	local stack = Stack(subtitle, "label", true)

	-- Fading: how fast the UI goes and comes back
	stack:Header(content, L["Fading"])

	local fadeIn = stack:Add(Slider(content, "fadeInTime", L["Fade in time"], 0, 10, 0.1, L["%.1f sec"]), "slider")
	Tooltip(fadeIn, L["How long things take to fade in out of combat: targeting something, a mouseover, " ..
		"a window opening. In fights the Combat fade in time is used."])

	local fadeOut = stack:Add(Slider(content, "fadeOutTime", L["Fade out time"], 0, 10, 0.1, L["%.1f sec"]), "slider")
	Tooltip(fadeOut, L["How long things take to fade out, in and out of fights: letting go of a target, after a " ..
		"mouseover, and after a fight once the Calm Timer below is over. The mouseover time (Mouseover " ..
		"groups page) includes it: a time shorter than the fade just fades straight away."])

	local combatFadeIn = stack:Add(Slider(content, "combatFadeInTime", L["Combat fade in time"], 0, 10, 0.1,
		L["%.1f sec"]), "slider")
	Tooltip(combatFadeIn, L["How long things take to fade in during a fight: the UI coming back as " ..
		"one starts, and anything else that shows mid-fight. Other times use the Fade in time."] .. " " ..
		L["Casts count too when a rule uses Casting."])

	local calm = stack:Add(Slider(content, "calmTime", L["Calm Timer"], 0, 120, 5, L["%d sec after a fight"]), "slider")
	Tooltip(calm, L["How long things take to settle back into CineMode after a fight. " ..
		"Nameplates and names ticked In combat stay up this long (so they don't drop away " ..
		"between pulls), and visual effects that step aside for fights wait this " ..
		"long before fading back in. Your portrait and buffs, if they only show after combat, " ..
		"count a fight as recent for this long too, the RP walk, auto-run and cozy cameras " ..
		"wait this long before starting, and music muted for fights comes back after it. Then " ..
		"things fade out at the Fade out time. 0 settles at once. Exit Calm Timer when healthy, " ..
		"below, can end it early."])

	-- Off at the left end; past it, how long after you're back to full the
	-- Calm Timer ends (calmEndsAtFull and calmFullAfter).
	RecordKey(content, "calmEndsAtFull")
	RecordKey(content, "calmFullAfter")
	local calmPet -- (below; greys out with this Off)
	local calmFull = Slider(content, {
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
	Tooltip(calmFull, L["The Calm Timer runs out early once your health and power are back to full " ..
		"after a fight (mana, energy and focus refilled; rage, runic power, Insanity and the like " ..
		"drained). The seconds: how long things stay up once you're full, before they fade out at the " ..
		"Fade out time (a little wait keeps them up between pulls when you took no damage). Off: the " ..
		"Calm Timer always runs its full length."])

	-- (Indented under it, as its sub-option.)
	calmPet = Check(content, "calmEndsAtFullPet", L["Include your pet"],
		L["With a pet out, the Calm Timer only ends early once its health is back to full as well. " ..
		"No pet, or a dead one: just yours counts."])
	stack:Add(calmPet, "check", 16)
	GreyUnless(calmPet, function(db) return db.calmEndsAtFull end)

	-- Set aside for now (hidden, their settings kept as they are): the Exit
	-- CineMode section. (Mouseover has its own page.)
	local setAside = {}

	-- One column of sections, each below the last: what brings the UI back,
	-- combat text, your portrait.
	local revealHeader = Header(content, L["Exit CineMode"], calm, -24)
	revealHeader:SetPoint("TOPLEFT", calm, "BOTTOMLEFT", -2, -24)

	local cast = Check(content, "revealOnCast", L["While casting"],
		L["Includes mounting and hearthstone casts."])
	cast:SetPoint("TOPLEFT", revealHeader, "BOTTOMLEFT", -2, -6)

	local npcs = Check(content, "revealAtNPCs", L["At vendors, banks, mail and trainers"],
		L["Exit CineMode while a vendor, bank, mailbox, class trainer, trade or auction " ..
		"house window is open. When off, the window still shows but the rest stays hidden."])
	npcs:SetPoint("TOPLEFT", cast, "BOTTOMLEFT", 0, -2)

	-- Stored the other way round (stayWithWindows), like the rest of this
	-- section reading as what brings the UI back.
	local windows = Check(content, "stayWithWindows", L["Opening windows"],
		L["Exit CineMode while the spellbook, character sheet, talents, macros, key " ..
		"bindings or these options are open. When off, the window still shows but the rest " ..
		"stays hidden."], function(value)
			ns.GetDB().stayWithWindows = not value
		end)
	windows.Refresh = function(self) self:SetChecked(not ns.GetDB().stayWithWindows) end
	windows:SetPoint("TOPLEFT", npcs, "BOTTOMLEFT", 0, -2)

	local drag = Check(content, "revealOnDrag", L["While dragging something"],
		L["Picking up an item or spell (to drag it to your action bars, say) brings the UI back " ..
		"until you put it down. Off: picking things up never does; mouse over a faded bar to " ..
		"see it when dragging there."])
	drag:SetPoint("TOPLEFT", windows, "BOTTOMLEFT", 0, -2)

	local returnDelay = Slider(content, "returnDelay", L["Back into CineMode after"], 0, 60, 1, L["%d sec"])
	returnDelay:SetPoint("TOPLEFT", drag, "BOTTOMLEFT", 4, -26)
	Tooltip(returnDelay, L["How long things must stay calm (no cast, window, dragging and the like) " ..
		"before CineMode comes back. After a fight it comes back at once instead. 0 returns at once."])

	for _, control in ipairs({ revealHeader, cast, npcs, windows, drag, returnDelay }) do
		setAside[#setAside + 1] = control
	end
	for _, control in ipairs(setAside) do
		control:Hide()
	end

	-- (Standard Frames' In combat rows, brought up early.)
	local hostileCast = Check(content, "fadeInOnHostileCast", L["Cast fade into combat"],
		L["Out of combat, casting a spell at an enemy brings up the frames ticked In combat, as if the fight " ..
		"had started: they fade in over the cast and are fully up as it lands. Instant spells bring them up " ..
		"at the Combat fade in time."])
	stack:Add(hostileCast, "check")
	GreyUnless(hostileCast, function(db) return db.stayInCombat end)

	stack:Header(content, L["Combat text"])

	local combatText = Check(content, "hideCombatText", L["Hide combat text out of combat"],
		L["No floating damage and healing numbers (like \"+10\" from a heal or regen) in cinematic " ..
		"mode while you're out of combat. They come back the moment a fight starts and stay for the " ..
		"Calm Timer after it, and your " ..
		"combat text settings are put back when the UI returns."])
	stack:Add(combatText, "check")

	local worldText = Check(content, "hideWorldText", L["Hide all floating text: XP, damage, healing (restart required)"],
		L["The game has no way to hide just the XP you gain over your character: it draws that, " ..
		"the damage and healing numbers, misses and the like all in one font. This blanks that " ..
		"font, so they all go, always (not just in CineMode). Takes effect after you fully " ..
		"restart the game; /reload isn't enough."])
	stack:Add(worldText, "check")
	worldText:HookScript("OnClick", function()
		StaticPopup_Show("CINEMATIC_WORLD_TEXT_RESTART")
	end)

	-- The red error text at the top of the screen, in and out of fights
	-- (CineMode or not).
	stack:Header(content, L["Hide error messages"])

	local errorsInCombat = Check(content, "hideErrorsInCombat", L["In combat"],
		L["No red error text at the top of the screen (like \"Target not in line of sight\" or " ..
		"\"Can't do that while moving\") while you're fighting, and for the Calm Timer after it."])
	stack:Add(errorsInCombat, "check")

	local errorsOutOfCombat = Check(content, "hideErrorsOutOfCombat", L["Out of combat"],
		L["No red error text at the top of the screen (like \"Target not in line of sight\" or " ..
		"\"Can't do that while moving\") while you're out of combat."])
	stack:Add(errorsOutOfCombat, "check")

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
		if i ~= SETTINGS_TAB and ns.Flag(canvas:IsVisible()) then FillOverview() end
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
	-- (The welcome window's See Profile: the CineMode page on its first tab.)
	function ns.OpenCineModeOverview()
		PickTab(1)
		ns.OpenOptions("CineMode")
	end
end

-- Sub-page: your buffs and debuffs, shown when you gain one and on hover.
local function CreateBuffsPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Buffs/Debuffs"])
	title:SetPoint("TOPLEFT", 16, -16)
	ns.FramesLink(content, title, "combat")

	local note = PageIntro(content, title,
		L["Your buff and debuff icons. They fade with the UI in CineMode; these bring them back."])

	local buffPeek = Check(content, "buffPeek", L["Show buffs when you gain or refresh one"],
		L["Gaining or refreshing a buff briefly shows your buffs and debuffs. Not on flights."])
	buffPeek:SetPoint("TOPLEFT", note, "BOTTOMLEFT", -2, -17) -- (as under the other pages' hidden switch)
	PageSwitch(content, "handleBuffs", L["Enable Page"],
		L["On: this page's peeks bring your buffs and debuffs up in CineMode. Off: no peeks; they still " ..
		"fade as their Game Frames row says."], note)
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
		L["Your own buffs on yourself (Power Word: Fortitude, Arcane Intellect, a self-cast shield...) " ..
		"and your pet's don't bring them up; ones from other players and the world still do."])
	buffIgnoreSelf:SetPoint("TOPLEFT", buffAfterCombat, "BOTTOMLEFT", 0, -2)
	GreyUnless(buffIgnoreSelf, IfBuffPeek)

	-- (Only where there's skyriding: as SkyrideCam.lua decides that.)
	local aboveOnlyNew = buffIgnoreSelf
	if ns.isRetail and C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
		local buffNotSkyriding = Check(content, "buffPeekNotSkyriding", L["Not while skyriding"],
			L["No buff brings them up while you're on a mount that can skyride, in the air or on the ground, " ..
			"so skyriding's own buffs stay out of the way. Debuffs still do."])
		buffNotSkyriding:SetPoint("TOPLEFT", buffIgnoreSelf, "BOTTOMLEFT", 0, -2)
		GreyUnless(buffNotSkyriding, IfBuffPeek)
		aboveOnlyNew = buffNotSkyriding
	end

	local buffOnlyNew = Check(content, "buffPeekOnlyNew", L["Just the new one"],
		L["Only the buff you gained or refreshed shows; your other buffs stay faded. Hovering shows them all. " ..
		"In fights too, for new buffs (procs and the like)."])
	buffOnlyNew:SetPoint("TOPLEFT", aboveOnlyNew, "BOTTOMLEFT", 0, -2)
	GreyUnless(buffOnlyNew, IfBuffPeek)
	buffOnlyNew:HookScript("OnClick", Refresh)

	local buffCollapse = Check(content, "buffPeekCollapse", L["Close the gaps"],
		L["The new buff shows at the start of the row, not in its own place among empty spaces."])
	buffCollapse:SetPoint("TOPLEFT", buffOnlyNew, "BOTTOMLEFT", BUFF_INDENT, -2)
	GreyUnless(buffCollapse, function(db) return db.buffPeek and db.buffPeekOnlyNew end)

	local debuffPeek = Check(content, "debuffPeek", L["Show debuffs when you gain or refresh one"],
		L["Gaining or refreshing a debuff briefly shows your debuffs (not your buffs), in fights too. Not on flights."])
	debuffPeek:SetPoint("TOPLEFT", buffCollapse, "BOTTOMLEFT", -2 * BUFF_INDENT, -2)
	debuffPeek:HookScript("OnClick", Refresh)

	local debuffAfterCombat = Check(content, "debuffPeekAfterCombat", L["Only after combat"],
		L["Only within the Calm Timer after a fight. Off: debuffs like Hunter's Mark show any time."])
	debuffAfterCombat:SetPoint("TOPLEFT", debuffPeek, "BOTTOMLEFT", BUFF_INDENT, -2)
	GreyUnless(debuffAfterCombat, IfDebuffPeek)

	local debuffUntilGone = Check(content, "debuffPeekUntilGone", L["Keep them up until the debuff is gone"],
		L["A debuff that brings them up keeps them up while you have any debuff (bar the ones listed below), " ..
		"however long that is, fights included."])
	debuffUntilGone:SetPoint("TOPLEFT", debuffAfterCombat, "BOTTOMLEFT", 0, -2)
	GreyUnless(debuffUntilGone, IfDebuffPeek)

	-- (Debuffs only: a long debuff doesn't keep them up either.)
	local ignoreLong = Check(content, "buffPeekIgnoreLong", L["Not ones lasting longer than"],
		L["Debuffs that last longer than this (their full time, not what's left: Deserter, Resurrection " ..
		"Sickness...) don't bring them up, nor keep them up until gone. Not in fights, when what they are " ..
		"can't be seen. Buffs always do."], function(value)
			ns.GetDB().buffPeekIgnoreLong = value
			Refresh()
		end)
	ignoreLong:SetPoint("TOPLEFT", debuffUntilGone, "BOTTOMLEFT", 0, -2)
	GreyUnless(ignoreLong, IfDebuffPeek)
	local longMinutes = Slider(content, "buffPeekLongMinutes", "", 1, 60, 1, L["%d min"])
	longMinutes:SetPoint("TOPLEFT", ignoreLong, "BOTTOMLEFT", 24, -10)
	GreyUnless(longMinutes, function(db) return IfDebuffPeek(db) and db.buffPeekIgnoreLong end)

	local buffPeekTime = Slider(content, "buffPeekTime", L["Show buffs for"], 0.5, 30, 0.5, L["%.1f sec"])
	buffPeekTime:SetPoint("TOPLEFT", longMinutes, "BOTTOMLEFT", 4 - BUFF_INDENT - 24, -30)
	GreyUnless(buffPeekTime, IfBuffPeek)

	local debuffPeekTime = Slider(content, "debuffPeekTime", L["Show debuffs for"], 0.5, 30, 0.5, L["%.1f sec"])
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
	local ADD_TIP = L["Gaining or stacking this doesn't bring your buffs up. Type a spell ID or a " ..
		"name. Names must match your game language; spell IDs work in any language (2479 is " ..
		"Honorless Target, 8326 and 20584 are Ghost)."]
	Tooltip(addBox, ADD_TIP)
	Tooltip(addButton, ADD_TIP)

	-- Rebuilt as the page shows and after each change.
	local ignoreList = { Refresh = function()
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

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Buffs/debuffs", L["Buffs/Debuffs"])
end

-- Slow zoom controls for one profile (idleZoom* or taxiZoom*), stacked under
-- `anchor` (a checkbox). Returns the last control, for anchoring below it.
local function BuildZoomControls(parent, stack, prefix)
	local function key(name) return prefix .. name end

	stack:Add(Check(parent, key("Random"), L["Random zoom in and out"],
		L["After the first pull-back, keep drifting to new random distances (within the " ..
		"limits below), pausing between each. Off: a single pull-back that then holds."]), "check")

	local zoomDistance = stack:Add(Slider(parent, key("Distance"), L["Zoom out up to"], 1, 40, 1, L["%d yards"]), "slider")
	Tooltip(zoomDistance, L["How far past your own zoom the camera pulls back (the first move always " ..
		"goes this far)."])

	local zoomIn = stack:Add(Slider(parent, key("In"), L["Zoom in up to"], 0, 10, 1, L["%d yards"]), "slider")
	Tooltip(zoomIn, L["Random zoom only. How much closer than your own zoom it may come."])

	stack:Add(Slider(parent, key("Time"), L["Each zoom takes"], 5, 60, 1, L["%d sec"]), "slider")

	local zoomEase = stack:Add(Slider(parent, key("Ease"), L["Zoom ease in/out"], 10, 50, 5, "%d%%", 100), "slider")
	Tooltip(zoomEase, L["How much of each zoom is spent speeding up, and again slowing down. " ..
		"50% is one smooth swell; lower gets moving sooner and glides in the middle."])

	local zoomPause = stack:Add(Slider(parent, key("Pause"), L["Pause between zooms"], 0, 60, 1, L["%d sec"]), "slider")
	Tooltip(zoomPause, L["Random zoom only."])

	local zoomPauseVary = stack:Add(Slider(parent, key("PauseVary"), L["Pause varies by up to"], 0, 30, 0.5,
		L["%.1f sec"]), "slider")
	Tooltip(zoomPauseVary, L["Random zoom only. Each pause is picked at random this much shorter or " ..
		"longer than the pause above: 3 sec with a 10 sec pause waits anywhere from 7 to 13 sec. " ..
		"0 keeps every pause the same."])

	stack:Add(Check(parent, key("PastMax"), L["Allow zooming past your maximum"],
		L["Raises the game's max camera distance (to 2.6) while pulled back, so the zoom " ..
		"isn't cut short. Your own maximum comes back once you've zoomed in again."]), "check")
end

-- The camera modes' switch, on the Cameras page: off, no camera mode
-- starts, Shoulder Cam lets go, and it and the Camera Settings page grey out.
local function CameraModesSwitch(content, anchor)
	return PageSwitch(content, "cameraModes", L["Enable Cameras"],
		L["On: the cameras start as the rows below say. Off: none of them ever starts, and the camera is " ..
		"left to you; CineMode still fades the UI."], anchor, function()
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
				L["Each time the camera starts, it picks clockwise or anticlockwise at random " ..
				"(and keeps to it until it stops)."], function(value)
					ns.GetDB()[key("RandomDir")] = value
					Refresh()
				end), "check")
			GreyUnless(orbitRight, function(db) return not db[key("RandomDir")] end)
		end

		local orbitStep = stack:Add(Slider(container, key("Step"), L["Turn per sweep"], 10, 90, 5, "%d°"), "slider")
		Tooltip(orbitStep, L["How far each sweep turns, always the same way, staying level."])

		local orbitSpeed = stack:Add(Slider(container, key("Speed"), L["Turn speed"], 1, 45, 1, "%d°/sec"), "slider")
		Tooltip(orbitSpeed, L["Top speed in the middle of a sweep. At 6°/sec with 50% ease, a 30° " ..
			"sweep takes 10 seconds."])
	else
		local minChange = stack:Add(Slider(container, key("MinChange"), L["Minimum change"], 10, 120, 5, "%d°"), "slider")
		Tooltip(minChange, L["The new angle is never within this many degrees of the current " ..
			"one, either way. Keep it below the swing for varied moves."])

		local backArc = stack:Add(Slider(container, key("BackArc"), L["Sway either side"], 0, 90, 5, "%d°"), "slider")
		Tooltip(backArc, L["How far the camera may sway to either side of where it was as the sway began. " ..
			"(The game doesn't tell addons which way the camera points, so that's wherever it was, " ..
			"not always straight behind you.)"])

		local pitchUp = stack:Add(Slider(container, key("PitchUp"), L["Tilt up as far as"], 0, 45, 5, "%d°"), "slider")
		Tooltip(pitchUp, L["Each move also tilts the camera to a random angle between the down " ..
			"and up limits. 0 on both keeps it level."])

		local pitchDown = stack:Add(Slider(container, key("PitchDown"), L["Tilt down as far as"], 0, 45, 5, "%d°"), "slider")
		Tooltip(pitchDown, L["How far below level a move may tilt."])

		if prefix == "runOrbit" then
			local pitchFloor = stack:Add(Slider(container, key("PitchFloor"), L["Lowest tilt"], 0, 45, 1, "%d°"), "slider")
			Tooltip(pitchFloor, L["The camera never tilts more than this far below where it was " ..
				"when auto-run started, even when it lowers while you steer."])
		end

		local moveTime = stack:Add(Slider(container, key("MoveTime"), L["Each move takes"], 1, 20, 0.5, L["%.1f sec"]), "slider")
		Tooltip(moveTime, L["How long each move takes, however far it goes."])
	end

	local ease = stack:Add(Slider(container, key("Ease"), L["Ease in/out"], 10, 50, 5, "%d%%", 100), "slider")
	Tooltip(ease, L["How much of each move is spent speeding up, and again slowing down. " ..
		"50% is one smooth swell, gentlest at the ends. Lower values get up to speed " ..
		"quicker and cruise in the middle."])

	local orbitPause = stack:Add(Slider(container, key("Pause"), L["Pause between moves"], 0, 60, 0.5, L["%.1f sec"]), "slider")
	if style == "sweep" then
		Tooltip(orbitPause, L["How long the camera rests between sweeps. 0 keeps it turning " ..
			"continuously at the turn speed, without slowing between sweeps."])
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
	Tooltip(reset, L["Put this camera's settings back to the active profile's own values (the defaults, " ..
		"or a built-in profile's)."])
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
			or L["Runs this camera for 30 seconds where you stand, to see your settings at work. " ..
			"Moving, or clicking Stop, ends it."])
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
local ZOOM_TIP = L["The camera slowly pulls back, then (with random zoom) drifts in and out. Moving " ..
	"glides it back to your distance; zooming yourself keeps your new distance."]
local INPUT_PAUSE_TIP = L["After you drag the camera, use camera keys or zoom, this camera waits " ..
	"this long, then carries on from your new view."]

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
	Tooltip(dof, L["A soft haze around the edges of the screen in this camera mode, as if the " ..
		"camera had focused on you. 0% leaves it off. Moving the slider shows it for a moment. " ..
		"Needs \"Camera haze\" on the Visual Effects page, which also turns it up or down."])
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
	Sit = L["Doing the emote (or pressing the sit key). Moving, jumping or another emote ends it."],
	SitButton = L["Clicking the Campfire button (Quality of life page). Once the campfire's buff " ..
		"comes, the first row's camera takes over. Moving, jumping or another emote ends it."],
	Sleep = L["Doing the emote. Moving, jumping or another emote ends it."],
	Dance = L["Doing the emote. Moving, jumping or another emote ends it."],
	Kneel = L["Doing the emote. Moving, jumping or another emote ends it."],
	Chair = L["Right-clicking a seat to sit on it; standing up ends it. Seats are recognized by name, " ..
		"using the words below."],
	Weapon = L["Unsheathing your weapon with your Sheathe/Unsheathe key out of combat, for a \"hero shot\" " ..
		"(not when it comes out from attacking or casting). Putting it away, running or " ..
		"combat ends it. With the cozy camera it carries on while you auto-walk (even with Stop " ..
		"on move)."],
	Hearth = L["Casting your Hearthstone (or Astral Recall, or any spell with \"Hearthstone\" in its " ..
		"name). The tele camera turns half round and spins faster and faster as it " ..
		"zooms in, until you go. The cast doesn't bring the UI back " ..
		"or pause the camera."],
	Teleport = L["Casting a teleport (a mage's \"Teleport: Stormwind\" and the like, or a druid's " ..
		"Teleport: Moonglade). The tele camera, as for the Hearthstone."],
	Logout = L["Logging out or quitting where the game counts down 20 seconds first (out in the " ..
		"world). In an inn or a city, logging out is instant, so there's nothing to see. Moving, " ..
		"jumping, casting or Cancel ends it. It comes before any other event (a Hearthstone or " ..
		"teleport cast calls it off)."],
	Stare = L["Doing the emote while standing still. Moving, jumping or another emote ends it."],
	Fishing = L["Casting Fishing. It carries on after the cast ends (looting, casting again) until " ..
		"you move or jump. The cast doesn't bring the UI back or pause the camera."],
	AFK = L["Being flagged AFK (/afk, or away long enough). With \"No camera\", Stand still below " ..
		"still applies once you've stood still for its time."],
	Still = L["Standing still for the time below with nothing else going on (no emote, no other event). " ..
		"\"No camera\": standing still starts nothing, though going AFK and the other events still do."],
	Flight = L["Taking off on a flight path. With \"No camera\", the camera is left to you for " ..
		"the whole flight."],
	Quest = L["Talking to a quest giver (a quest to pick up or hand in). Works whether or not " ..
		"CineMode is on."],
	QuestGossip = L["Talking to an NPC with a \"(Quest)\" line to pick but no quest to pick up or " ..
		"hand in: a quest step done by talking to them. Works whether or not CineMode is on."],
}
local function CreateFlightPanel()
	CreateCameraModePanel({
		name = L["Flight Cam"],
		description = L["On flight paths. The camera sways from side to side on the way, with a fly-by " ..
			"now and then, and turns back to where it started before landing."],
		start = function(content, stack)
			stack:Add(Check(content, "dropTargetOnFlights", L["Drop your target at takeoff"],
				L["Your target's frames fade as if nothing were targeted, until you pick a new target " ..
				"or land. (Addons can't clear the target itself; the game doesn't allow it.)"]), "check")
		end,
		inputPauseKey = "taxiInputPause",
		orbitPrefix = "taxiOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["The camera sways from side to side around where it started, pausing between " ..
			"moves. Dragging the camera pauses it."],
		extras = function(content, stack)
			stack:Header(content, L["Fly-bys"])
			stack:Add(Check(content, "taxiFlyBy", L["Random fly-bys"],
				L["Now and then in the middle of a flight, the camera slowly turns round to look back " ..
				"past you, holds there, then turns back. On a route's first flight (its " ..
				"length not known yet), just one, early on. Dragging the camera stops it. /cine flyby " ..
				"starts one whenever you like. Once you move the camera yourself on a flight, " ..
				"there are no more for that flight."]), "check")
			stack:Add(Check(content, "flyByLook", L["Do /look as a fly-by starts"],
				L["Your character looks around as the camera starts turning, as if they'd spotted " ..
				"something. Players nearby see the emote in chat. Fly-bys you start count too."]), "check")
			local every = stack:Add(Slider(content, "taxiFlyByEvery", L["About one every"], 30, 300, 10, L["%d sec"]), "slider")
			Tooltip(every, L["Random fly-bys are spread over the part of the flight below: one per this " ..
				"many seconds of it (at least one), each at a random moment in its share."])
			local from = stack:Add(Slider(content, "taxiFlyByFrom", L["Not before"], 0, 100, 5, L["%d%% of the way"]), "slider")
			Tooltip(from, L["Keeps random fly-bys away from takeoff."])
			local to = stack:Add(Slider(content, "taxiFlyByTo", L["Not after"], 0, 100, 5, L["%d%% of the way"]), "slider")
			Tooltip(to, L["Keeps random fly-bys away from landing (and the settle before it)."])
			local angle = stack:Add(Slider(content, "flyByAngle", L["Turn round"], 90, 180, 5, "%d°"), "slider")
			Tooltip(angle, L["The camera undoes the flight's sway, then turns this far round: 180 is " ..
				"half a turn, so if it started behind you it looks straight back at you."])
			local turnTime = stack:Add(Slider(content, "flyByTurnTime", L["Turn round takes"], 3, 20, 1, L["%d sec"]), "slider")
			Tooltip(turnTime, L["How long the turn round takes, easing in and out."])
			stack:Add(Slider(content, "flyByHold", L["Look back for"], 0, 20, 1, L["%d sec"]), "slider")
			stack:Add(Slider(content, "flyByBackTime", L["Turn back takes"], 3, 20, 1, L["%d sec"]), "slider")

			stack:Header(content, L["Landing"])
			stack:Add(Check(content, "taxiSettle", L["Turn back before landing"],
				L["Shortly before you land, the sway stops and the camera turns back to where it was at " ..
				"takeoff, and stays there until you touch down. Needs one flight on a " ..
				"route to learn how long it takes. Skipped if you've moved the camera yourself on that " ..
				"flight: it stays how you set it."]), "check")
			stack:Add(Check(content, "taxiLandZoom", L["Put the zoom back when you land"],
				L["As you land, the camera glides back to the zoom distance you had when you took " ..
				"off. If you zoomed yourself on the way, it stays where you put it."]), "check")
			local settleLead = stack:Add(Slider(content, "taxiSettleLead", L["Turned back by"], 2, 20, 1,
				L["%d sec before landing"]), "slider")
			Tooltip(settleLead, L["The camera turns back over the 12 seconds before this, so it's settled " ..
				"this long before you land."])
		end,
		zoomPrefix = "taxiZoom", dofKey = "dofFlight",
	})
end

local function CreateStandingPanel()
	CreateCameraModePanel({
		name = L["AFK Cam"],
		description = L["Once you've stood still for a while with the UI faded, or as soon as you " ..
			"go AFK, the camera slowly sweeps around your character. Moving stops it. What starts it, " ..
			"and how long you stand still first, is on the Scenes page."],
		inputPauseKey = "idleInputPause",
		orbitPrefix = "idleOrbit", style = "sweep",
		rotateLabel = L["Sweep around you"],
		rotateTip = L["The camera sweeps around your character, pausing between sweeps. Moving or " ..
			"dragging the camera stops it."],
		zoomPrefix = "idleZoom",
		dofKey = "dofIdle",
	})
end

local function CreateAutoRunPanel()
	CreateCameraModePanel({
		name = L["Auto-run Cam"],
		description = L["While you're auto-running (the auto-run key). Pressing forward or back, or " ..
			"stopping, ends it; stop and stand, and the AFK camera takes over. Auto-" ..
			"walking counts as RP walk instead."],
		inputPauseKey = "runInputPause",
		orbitPrefix = "runOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["The camera sways gently from side to side around where it started, pausing " ..
			"between moves."],
		zoomPrefix = "runZoom",
		zoomTip = L["The camera eases out a little, then drifts in and out around your own distance. " ..
			"When you stop it glides back."],
		dofKey = "dofRun",
	})
end

local function CreateCozyPanel()
	CreateCameraModePanel({
		name = L["Cozy Cam"],
		description = L["Resting at a campfire, sitting, sleeping, dancing and the like (whichever " ..
			"events pick it on the Scenes page): the camera turns slowly half round (180°, so if it " ..
			"started behind you it faces you), then sways gently from side to side there, and eases " ..
			"in close. Moving (or standing up) ends it."],
		inputPauseKey = "cozyInputPause",
		orbitPrefix = "cozyOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["Once it has turned half round, the camera sways gently from side to side " ..
			"there, pausing between moves."],
		extras = HeightExtras("cozyLevel", -30, 80, L["As it turns round, the camera also comes down " ..
			"this much toward the ground, so it feels low and close rather than looking down from " ..
			"above. It stops at the ground, so a big number just means \"as low as it goes\". 0 " ..
			"keeps your angle."]),
		zoomPrefix = "cozyZoom",
		zoomTip = L["A close, gentle zoom: it starts by easing in to the close-up distance below, then " ..
			"drifts a little in and out around it."],
		zoomExtras = function(content, stack)
			local close = stack:Add(Slider(content, "cozyZoomClose", L["Zoom in to about"], 2, 20, 0.5,
				L["%.1f yards"]), "slider")
			Tooltip(close, L["The close-up distance the cozy camera zooms in to, if you're further out. " ..
				"The zoom settings above then work around it. Your own distance comes back afterwards."])
		end,
		dofKey = "dofCozy",
	})
end

local function CreateVistaPanel()
	CreateCameraModePanel({
		name = L["Vista Cam"],
		description = L["Stop and /stare out at the view (or any event set to it on the Scenes page): " ..
			"the camera sways very gently from side to side from where it is. Like the RP walk camera, " ..
			"only slower and softer. Moving, jumping or another emote ends it."],
		inputPauseKey = "vistaInputPause",
		orbitPrefix = "vistaOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["The camera sways very gently from side to side around where it started, " ..
			"pausing between moves."],
		extras = HeightExtras("vistaLevel", -30, 45, L["The camera sways this much lower than where " ..
			"it started, so it looks out across the view rather than down at it. 0 " ..
			"keeps your angle."]),
		zoomPrefix = "vistaZoom",
		zoomTip = L["The camera eases out a little, then drifts slowly in and out around your own " ..
			"distance. Your own distance comes back afterwards."],
		dofKey = "dofVista",
	})
end

local function CreateFishPanel()
	CreateCameraModePanel({
		name = L["Fish Cam"],
		description = L["Cast Fishing (or any event set to it on the Scenes page): the vista camera, " ..
			"made for fishing. The camera sways only a little either side of where it is, so your " ..
			"bobber stays in view. It carries on after the cast until you move or jump."],
		inputPauseKey = "fishInputPause",
		orbitPrefix = "fishOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["The camera sways a little from side to side around where it started, " ..
			"pausing between moves. Narrower than the vista camera's sway."],
		extras = HeightExtras("fishLevel", -30, 45, L["The camera sways this much lower than where " ..
			"it started, so it looks out across the water rather than down at it. 0 " ..
			"keeps your angle."]),
		zoomPrefix = "fishZoom",
		zoomTip = L["The camera eases out a little, then drifts slowly in and out around your own " ..
			"distance. Your own distance comes back afterwards."],
		dofKey = "dofFish",
	})
end

local function CreateWalkPanel()
	CreateCameraModePanel({
		name = L["RP Walk Cam"],
		description = L["While you're auto-walking (auto-run in walk mode). Walking by hand cancels " ..
			"the camera, as all moving by hand does. Stop and stand, and the AFK camera takes over. " ..
			"Walking is recognized from your speed; /cine walk shows what the addon thinks."],
		inputPauseKey = "walkInputPause",
		inputPauseTip = L["Keep it short, so it's back in time if you need to steer."],
		orbitPrefix = "walkOrbit", style = "back",
		rotateLabel = L["Sway from side to side"],
		rotateTip = L["The camera sways gently from side to side around where it started, pausing " ..
			"between moves."],
		zoomPrefix = "walkZoom",
		zoomTip = L["The camera eases out a little, then drifts in and out around your own distance. " ..
			"When you stop walking it glides back."],
		dofKey = "dofWalk",
	})
end

-- Not a CreateCameraModePanel page (no sway, zoom profile or music switch of
-- its own), but laid out the same way.
local function CreateDeathPanel()
	local content, top, title = CameraSection(L["Death Cam"], "Death Cam")
	local subtitle = PageIntro(content, title, L["When you die, the camera turns " ..
		"slowly round your body until you release or are resurrected. CineMode stays on " ..
		"(straight away), with the release button (and any soulstone or Reincarnation " ..
		"button) still showing."], top)
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
		L["Dying while a boss fight is on, you keep your own view to watch the rest of it. The death " ..
		"camera starts once the encounter ends (a kill or a wipe), if you're still dead."]), "check")
	GreyUnless(afterBoss, IfOn)
	local selfRes = stack:Add(Check(content, "deathOffWithSelfRes", L["Not with a soulstone or Reincarnation"],
		L["When the release popup offers a way to come back yourself (a soulstone, Reincarnation, an " ..
		"ankh...), there's no death camera: you keep your own view to pick your moment."]), "check")
	GreyUnless(selfRes, IfOn)
	local exitButton = stack:Add(Check(content, "deathExitButton", L["Exit camera button"],
		L["A button under the release popup while the death camera's on: click it for your own view back " ..
		"until you release or come back. The Stop the camera key binding does the same."]), "check")
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
	Tooltip(zoom, L["Meanwhile the camera pulls back this far, and returns to your own distance " ..
		"afterwards. Zooming yourself leaves it where you put it."])
	GreyUnless(zoom, IfOn)

	stack:Header(content, L["Height"])
	local level = stack:Add(Slider(content, "deathLevel", L["Raise the camera"], 0, 90, 5, "%d°"), "slider")
	Tooltip(level, L["As it starts, the camera rises this much to look down on your body; it comes " ..
		"back down afterwards. The game stops it just short of straight down, so a big number " ..
		"means \"as high as it goes\". 0 keeps your angle."])
	GreyUnless(level, IfOn)

	stack:Header(content, L["Screen"])
	-- Hide all except: the Mouseover page's groups, ticked (deathKeepGroups:
	-- ns.HoverGroupId -> true). (The release and resurrect popups always show.)
	local KEEP_TIP = L["In CineMode the death camera hides all the frames it fades (bars, chat, unit frames...). " ..
		"The Mouseover page's groups ticked here stay up throughout, party or raid frames say, to watch " ..
		"your group. The release and resurrect popups always show."]
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
		L["The world dims and goes cold and gray-blue, with a heavy vignette closing in from the " ..
		"edges. It clears when you release or come back."]), "check")
	screen:HookScript("OnClick", Refresh) -- grey out / enable the strength below
	GreyUnless(screen, IfOn)
	local screenStrength = stack:Add(Slider(content, "deathScreenStrength", L["Strength"], 10, 100, 5,
		"%d%%", 100), "slider")
	GreyUnless(screenStrength, function(db) return IfOn(db) and db.deathScreen end)
	local creep = stack:Add(Slider(content, "deathVignetteTime", L["Edges creep in over"], 1, 30, 1,
		L["%d sec"]), "slider")
	Tooltip(creep, L["How long the dark edges take to close in after you die, starting gently and " ..
		"settling at the end."])
	GreyUnless(creep, function(db) return IfOn(db) and db.deathScreen end)
	local reach = stack:Add(Slider(content, "deathVignetteSize", L["Edges reach in"], 15, 50, 5,
		"%d%%", 100), "slider")
	Tooltip(reach, L["How far the dark edges reach in once they've closed in, as a share of the " ..
		"screen from each side."])
	GreyUnless(reach, function(db) return IfOn(db) and db.deathScreen end)
	local corpseRun = stack:Add(Check(content, "deathCorpseRun", L["Edges lift as you near your body"],
		L["Released to a graveyard with no spirit healer's countdown, the dark edges stay as you walk " ..
		"back, and lift the closer you get to your body, gone once you're there."]), "check")
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
	Tooltip(songBox, L["Music file IDs, separated by commas; one is picked at random each time " ..
		"you die (Wowhead lists the IDs on each sound's page). Try one with /cine songtest <ID>."])
	stack:Note(content, L["Music file IDs, separated by commas. One is picked at random while the " ..
		"Die row's Music is ticked on the Scenes page."], 280)
end

-- Chat Cam (ChatCam.lua), started by NPCs talking; laid
-- out as the Quest Cam's below.
local function CreateChatCamPanel()
	local content, top, title = CameraSection(L["Chat Cam"], "Chat Cam")
	local subtitle = PageIntro(content, title, L["As NPCs talk near you, the camera zooms in and " ..
		"swings toward whoever's talking (by their chat bubble), drifting slowly while they go on. It " ..
		"swings again only when someone else speaks, and turns back and zooms out once no one's " ..
		"talked for a while. Moving, or moving the camera yourself, hands it straight back to you."], top)
	-- (On or off: its two rows' cameras, on the Cameras page.)
	local function IfOn() return ns.TriggerAnyRow("Chat") or ns.TriggerAnyRow("ChatNearby") end

	local stack = Stack(subtitle, "label", true)
	stack:Header(content, L["Rotation"])
	local speed = stack:Add(Slider(content, "chatCamSwingSpeed", L["Swing speed"], 5, 40, 1, L["%d°/sec"]), "slider")
	Tooltip(speed, L["The fastest the camera swings toward a new speaker. Each swing speeds up and " ..
		"slows down gently, as the flight camera's fly-bys do, so a short one never gets this fast " ..
		"and takes a few seconds."])
	GreyUnless(speed, IfOn)
	local frame = stack:Add(Slider(content, "chatCamFrame", L["Leave the speaker off center"], 0, 20, 1, "%d°"), "slider")
	Tooltip(frame, L["The swing stops with the speaker this far from the middle of the screen, on " ..
		"their side, so you stay in the shot beside them. 0 aims right at them (you may block the view)."])
	GreyUnless(frame, IfOn)
	local drift = stack:Add(Slider(content, "chatCamDrift", L["Drift"], 0, 10, 1, "%d°"), "slider")
	Tooltip(drift, L["Once the camera has settled on a speaker, it drifts slowly to and fro, side " ..
		"to side, across this many degrees, so the shot isn't stock-still. 0 holds still."])
	GreyUnless(drift, IfOn)
	local search = stack:Add(Check(content, "chatCamSearch", L["Look around for speakers off screen"],
		L["When someone talks out of sight (behind you, say), the camera turns around, a full turn " ..
		"at most, until their chat bubble shows, then frames them. If they're nowhere to be seen, " ..
		"it ends up back where it was."]), "check")
	GreyUnless(search, IfOn)
	local immersive = stack:Add(Check(content, "chatCamImmersive", L["Ultra immersive"],
		L["The camera snaps straight to whoever's talking instead of swinging, the letterbox comes " ..
		"in twice as tall for the conversation with subtitles in its bottom bar, and the " ..
		"whole UI fades out: the minimap, frames, nameplates, names and the circle under your target."]), "check")
	GreyUnless(immersive, IfOn)

	stack:Header(content, L["Zoom"])
	local distance = stack:Add(Slider(content, "chatCamDistance", L["Zoom in to about"], 1.5, 10, 0.5, L["%.1f yards"]), "slider")
	Tooltip(distance, L["If you're further out than this. Closer already, it stays where it is."])
	GreyUnless(distance, IfOn)
	local zoomSpeed = stack:Add(Slider(content, "chatCamZoomSpeed", L["Zoom in speed"], 0.25, 10, 0.25, L["%.2f yards/sec"]), "slider")
	Tooltip(zoomSpeed, L["The first swing waits for the zoom in to finish."])
	GreyUnless(zoomSpeed, IfOn)
	local zoomOutSpeed = stack:Add(Slider(content, "chatCamZoomOutSpeed", L["Zoom back out speed"], 0, 10, 0.25, L["%.2f yards/sec"]), "slider")
	Tooltip(zoomOutSpeed, L["Once the conversation's over, the camera zooms back out to your own " ..
		"distance at this speed (not if you zoomed yourself meanwhile). At 0 it stays in."])
	GreyUnless(zoomOutSpeed, IfOn)
	local zoomMax = stack:Add(Slider(content, "chatCamZoomMaxTime", L["Zoom takes at most"], 2, 30, 1, L["%d sec"]), "slider")
	Tooltip(zoomMax, L["From far out, the zoom in or back out speeds up so it's done in this long. " ..
		"A short zoom still goes at the speeds above."])
	GreyUnless(zoomMax, IfOn)

	stack:Header(content, L["Ending"])
	local quiet = stack:Add(Slider(content, "chatCamQuiet", L["Over after no one talks for"], 3, 30, 1, L["%d sec"]), "slider")
	Tooltip(quiet, L["With no one talking for this long, the camera turns back and zooms back out. " ..
		"Moving ends it at once, leaving the camera where it is."])
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
	local subtitle = PageIntro(content, title, L["Talking to a quest giver, the " ..
		"camera zooms in and turns a little to one side, looking past you at them. It goes back " ..
		"once you close the window or move off (your zoom stays if you zoomed yourself meanwhile). Works " ..
		"whether or not CineMode is on. The \"Talk to a quest giver\" and \"Talk about a quest\" " ..
		"events on the Scenes page can also turn it off or make it wait a moment."], top)
	-- (On or off, and the wait before starting: its two rows', on the Cameras page.)
	local function IfOn() return ns.TriggerAnyRow("Quest") or ns.TriggerAnyRow("QuestGossip") end

	local stack = Stack(subtitle, "label", true)
	stack:Header(content, L["Starting"])
	local gossip = stack:Add(Check(content, "questCamAllGossip", L["Every NPC you talk to"],
		L["Also for NPCs with nothing to say about quests (innkeepers, guards...), as the \"Talk " ..
		"to a quest giver\" event. Off: only when they have a quest to offer or take in, or a " ..
		"\"(Quest)\" line (the \"Talk about a quest\" event)."]), "check")
	GreyUnless(gossip, function() return ns.TriggerAnyRow("Quest") end)
	local mounted = stack:Add(Check(content, "questCamNotMounted", L["Not while mounted"],
		L["Talking to a quest giver from your mount, the camera stays as it is."]), "check")
	GreyUnless(mounted, IfOn)
	local daily = stack:Add(Check(content, "questCamNotDaily", L["Not for dailies"],
		L["When all a quest giver has to offer or take in is daily or weekly quests, the camera " ..
		"stays as it is."]), "check")
	GreyUnless(daily, IfOn)

	stack:Header(content, L["Rotation"])
	local angle = stack:Add(Slider(content, "questCamAngle", L["Come round to the side"], 0, 90, 5, "%d°"), "slider")
	Tooltip(angle, L["The camera turns this far to one side, so you see the quest giver past you " ..
		"at an angle rather than straight over your head. 0: no turn. It turns back as the window closes."])
	GreyUnless(angle, IfOn)
	local turnTime = stack:Add(Slider(content, "questCamTurnTime", L["Turn to the side takes"], 1, 8, 0.5, L["%.1f sec"]), "slider")
	Tooltip(turnTime, L["It turns while the zoom carries on. The tilt down follows."])
	GreyUnless(turnTime, IfOn)
	local SIDE_TIP = L["Which side the camera comes round to. On your right, the quest giver is on " ..
		"the right of the screen. (The game doesn't tell addons where the quest giver stands, or " ..
		"what's around you, so it can't pick the open side.) \"Where you clicked them\": the side " ..
		"of the screen you clicked the quest giver on, and the camera turns toward it; talking " ..
		"to them with a key instead, the side is picked at random."]
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
	Tooltip(drift, L["Once the camera has settled, it drifts slowly to and fro, side to side, " ..
		"across this many degrees, so the shot isn't stock-still. 0 holds still."])
	GreyUnless(drift, IfOn)

	stack:Header(content, L["Zoom"])
	local distance = stack:Add(Slider(content, "questCamDistance", L["Zoom in to about"], 1.5, 10, 0.5, L["%.1f yards"]), "slider")
	Tooltip(distance, L["If you're further out than this. Closer already, it stays where it is."])
	GreyUnless(distance, IfOn)
	local zoomSpeed = stack:Add(Slider(content, "questCamZoomSpeed", L["Zoom in speed"], 0.25, 10, 0.25, L["%.2f yards/sec"]), "slider")
	Tooltip(zoomSpeed, L["The turn to the side happens along the way, then the tilt down."])
	GreyUnless(zoomSpeed, IfOn)
	local zoomOutSpeed = stack:Add(Slider(content, "questCamZoomOutSpeed", L["Zoom back out speed"], 0, 10, 0.25, L["%.2f yards/sec"]), "slider")
	Tooltip(zoomOutSpeed, L["Leaving the quest giver, the camera stays close until you walk more than " ..
		"10 yards from where you started talking (talk to another quest giver and it counts from there), " ..
		"then zooms back out to your own distance at this speed, in a few seconds at most. At 0 it stays in."])
	GreyUnless(zoomOutSpeed, IfOn)
	local zoomMax = stack:Add(Slider(content, "questCamZoomMaxTime", L["Zoom takes at most"], 2, 30, 1, L["%d sec"]), "slider")
	Tooltip(zoomMax, L["From far out, the zoom in or back out speeds up so it's done in this long. " ..
		"A short zoom still goes at the speeds above."])
	GreyUnless(zoomMax, IfOn)

	stack:Header(content, L["Height"])
	local lower = stack:Add(Slider(content, "questCamLower", L["Lower the camera"], 0, 45, 5, "%d°"), "slider")
	Tooltip(lower, L["How far the camera comes down toward eye level, from wherever you had it. " ..
		"Much more and, close up, it can meet the ground or scenery behind you (a small jump). " ..
		"It goes back up as the window closes (unless you moved the camera yourself meanwhile). " ..
		"0 keeps your angle."])
	GreyUnless(lower, IfOn)
end

local function CreateTelePanel()
	local content, sectionTop, title = CameraSection(L["Tele Cam"], "Tele Cam")
	local subtitle = PageIntro(content, title, L["Casting your Hearthstone or a " ..
		"teleport, the camera turns half round, then spins around you faster and faster as it " ..
		"zooms in. Cancel the cast and it goes back to where it was. Its music, haze and " ..
		"tooltips follow the Cozy Cam's settings. The events on the Scenes page can also make it " ..
		"wait a moment."], sectionTop)
	-- (On or off: the Hearthstone and teleport rows' cameras, on the Cameras page.)
	local function IfOn() return ns.TriggerAnyRow("Hearth") or ns.TriggerAnyRow("Teleport") end

	local stack = Stack(subtitle, "label", true)

	stack:Header(content, L["Rotation"])
	local accel = stack:Add(Slider(content, "teleSpinAccel", L["Then speeds up by"], 0, 30, 1,
		L["%d° per sec, each sec"]), "slider")
	Tooltip(accel, L["Once half round, the spin keeps going and picks up speed until you go. " ..
		"0 keeps a steady speed."])
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
	Tooltip(close, L["Where the zoom ends as the cast does, if you're further out. Closer already, it " ..
		"stays where it is. Arriving, the camera is back at your own distance."])
	GreyUnless(close, IfZoom)
	local zoomBack = stack:Add(Slider(content, "teleZoomBackTime", L["If you cancel, zoom back out in"],
		0.5, 3, 0.25, L["%.2f sec"]), "slider")
	Tooltip(zoomBack, L["Canceling the cast, the camera zooms back out to your own distance this quickly."])
	GreyUnless(zoomBack, IfZoom)

	stack:Header(content, L["Canceling"])
	local back = stack:Add(Check(content, "teleReturn", L["Turn back if you cancel"],
		L["Moving, jumping or Esc cancels the cast: the spin slows to a stop and turns back to where " ..
		"the camera was before you started. Off: it stops where it is."]), "check")
	GreyUnless(back, IfOn)
end

-- The Camera Settings page, with a section for each camera.
local function CreateCameraSettingsPanel()
	local canvas, content = CreateScrollPage(true) -- (each section has its own Reset)
	cameraSettingsContent = content
	local title = Label(content, "GameFontNormalLarge", L["Camera Settings"])
	title:SetPoint("TOPLEFT", 16, -16)
	local subtitle = PageIntro(content, title, L["Camera settings that aren't on the Scripts page yet, a tab " ..
		"for each camera that has some. The rest of each camera's settings are on the Scripts page, under the steps " ..
		"they make; the Scenes page has what starts each one."])
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
		L["Turns the whole Atmosphere hub on or off at once: the letterbox, tint, time of day, zone tints, " ..
		"vignette, inn glow, weather, depth of field, Graphics+ and Audio. Each keeps its own settings for " ..
		"when you turn this back on."], function(value)
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
		L["How the game world looks in CineMode (or over the normal UI, with Start in CineMode off on the " ..
		"main page): vignette, inn glow, weather and depth of field. The letterbox bars and the color " ..
		"grading have pages of their own (Letterbox, Tint). The UI isn't tinted. Names and nameplates are " ..
		"on the Nameplates page."])

	local master = VisualEffectsSwitch(content, subtitle)

	-- Show in: a row each for the vignette and weather, as the Standard
	-- Frames page's (GridRows.lua): where and when each shows. A row off
	-- everywhere switches its effect off (its own switch follows). (The
	-- letterbox's and tint's rows: their own pages, LetterboxStyle.lua.)
	local gridHeader = Header(content, L["Show in"], master, -18)
	gridHeader:SetPoint("TOPLEFT", master, "BOTTOMLEFT", 2, -18)
	PageIntro(content, gridHeader,
		L["Where and when each effect shows in CineMode. Always: everywhere. Combat: In combat, Calm Timer (after a " ..
		"fight, till it's run out), Out of combat (the rest of the time), In a camera mode (flights, AFK, cozy and the " ..
		"rest). Location: the places. Nothing ticked: it's off."])
	local EFFECT_LABELS = { vignette = L["Vignette"], weather = L["Weather"] }
	local effectRows = { opts = { quiet = true, cam = true, anyFight = true }, underHeader = true }
	for _, effect in ipairs(ns.EFFECT_GRID) do
		if EFFECT_LABELS[effect] then
			local key, alwaysKey = "effect:" .. effect, effect .. "Always"
			effectRows[#effectRows + 1] = { key = key, label = EFFECT_LABELS[effect], alwaysKey = alwaysKey,
				alwaysOn = function() return ns.GetDB()[alwaysKey] end,
				setAlways = function(value) ns.GetDB()[alwaysKey] = value end,
				alwaysTip = L["Shows all through CineMode. (The other columns then have nothing to add.)"],
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
	Tooltip(vignetteStrength, L["Soft dark edges that draw the eye to the middle. Works with any tint."])
	GreyRow(vignetteStrength, function(db) return db.vignette end)

	-- Inns: Off is the inn glow switched off (its amount kept for next time).
	local innGlowStrength = InlineSlider(vignetteStrength.rowName, 18, {
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
	Tooltip(innGlowStrength, L["Indoors in an inn, the outdoor tint (a gloomy marsh, a moonlit night) partly lifts and a " ..
		"soft firelit glow fades in, colored by the zone: cooler in the snow, greener in a swamp. " ..
		"Blends over a few seconds as you go through the door."] .. " " ..
		L["How much light the glow adds at its brightest, low on the screen."])

	-- Weather
	local weatherTintStrength = InlineSlider(innGlowStrength.rowName, 18, "weatherTintStrength", L["Weather strength"], 100, 5,
		ns.RefreshTint)
	Tooltip(weatherTintStrength, L["Rain grays and cools the scene, snow turns it pale blue and a sandstorm " ..
		"gives it a dusty orange haze, more strongly the heavier the weather. Works with any tint (None " ..
		"included), lifts under a roof and blends in as a storm builds. Needs a game version that " ..
		"reports the weather."])
	GreyRow(weatherTintStrength, function(db) return db.weatherTint end)

	-- View distance in bad weather (Graphics.lua): only where the game says the
	-- weather and has the view distance setting.
	local lastRow = weatherTintStrength
	if C_Weather and C_Weather.GetCurrentWeather and GetCVar("horizonStart") ~= nil then
		lastRow = InlineSlider(weatherTintStrength.rowName, 18, "rainViewScale", L["Reduce view distance in bad weather"], 100, 5)
		Tooltip(lastRow, L["In CineMode, in rain, snow or a sandstorm, the view distance comes in from yours: the " ..
			"heavier the weather, the closer. At 100% a downpour or blizzard brings it all the way in, as far as " ..
			"the Graphics menu's lowest View distance; it never goes further out than yours. Yours is put back " ..
			"once the weather clears or you go indoors."])
	end

	-- Camera haze (depth of field): each camera mode's page sets its own
	-- strength, this scales them all. Off is the haze switched off (the
	-- scale kept for next time).
	local cameraHaze = InlineSlider(lastRow.rowName, 18, {
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
	Tooltip(cameraHaze, L["A soft haze around the edges of the screen in the camera modes, as if the camera " ..
		"had focused on you. Each camera mode's page sets its own strength: this turns them all up or down. " ..
		"/cine doftest shows it on demand."])

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

-- Sub-page: the visual effects' Tint tab: the colour grading (a preset, its
-- strength and drift), time of day and zone tints. Its Enable Page switch is
-- the General tab's too.
local function CreateTintPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Tint"])
	ns.EffectTabs(content, title, "tint", 2)

	local subtitle = PageIntro(content, title,
		L["The color grading over the game world: a preset, the time of day and each zone's mood. Where and " ..
		"when it shows: the Tint tab. The UI isn't tinted."])

	local lookHeader = Header(content, L["Preset"], subtitle, -18)
	lookHeader:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)

	local choices = {}
	for _, preset in ipairs(ns.TINT_PRESETS) do
		choices[#choices + 1] = { value = preset.key, text = preset.label, tip = preset.tip }
	end
	local presetControl = Dropdown(content, "tintPreset", choices, 220, ns.RefreshTint)
	if presetControl then
		presetControl:SetPoint("TOPLEFT", lookHeader, "BOTTOMLEFT", 0, -8)

		-- Time of day only: preview the tint at any hour (until you leave the page).
		-- Empty (-2) until you pick one; Current time (-1) shows no preview.
		local hours = { { value = -1, text = L["Current time"] } }
		for hour = 0, 23 do
			hours[#hours + 1] = {
				value = hour,
				text = ("%02d:00 - %s"):format(hour, L[ns.GetTimeOfDayPhaseAt(hour)]),
			}
		end
		local previewTime = Dropdown(content, "tintPreviewHour", hours, 200, ns.RefreshTint)
		if previewTime then
			previewTime:SetPoint("LEFT", presetControl, "RIGHT", 16, 0)
			if previewTime.SetDefaultText then
				previewTime:SetDefaultText("") -- (shown until an hour or Current time is picked)
			end
			local previewLabel = Label(content, "GameFontHighlightSmall", L["Preview time"])
			previewLabel:SetPoint("BOTTOMLEFT", previewTime, "TOPLEFT", 2, 2)
			local refreshMenu = previewTime.Refresh
			previewTime.Refresh = function(self)
				refreshMenu(self)
				local preset, here = ns.GetDB().tintPreset, ns.GetTintPresetHere()
				local shown = preset == "timeofday" or preset == "zonetime"
					or here == "timeofday" or here == "zonetime"
				self:SetShown(shown)
				previewLabel:SetShown(shown)
			end
			Tooltip(previewTime, L["See how the tint looks at another time of day. Only a preview: " ..
				"it goes back to the real clock when you leave this page."])
		end
	else
		local previous = lookHeader
		for i, choice in ipairs(choices) do
			local check = Choice(content, "tintPreset", choice.value, choice.text, choice.tip)
			check:HookScript("OnClick", ns.RefreshTint)
			check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
			previous = check
		end
		presetControl = previous
	end

	local presetText = Label(content, "GameFontHighlightSmall")
	presetText:SetPoint("TOPLEFT", presetControl, "BOTTOMLEFT", 2, -8)
	presetText:SetWidth(320)
	presetText:SetJustifyV("TOP")
	presetText.Refresh = function(self)
		local db = ns.GetDB()
		local here, from = ns.GetTintPresetHere()
		for _, choice in ipairs(choices) do
			if choice.value == db.tintPreset then
				local text = choice.tip
				-- A zone or area with its own preset: say so, and describe that one.
				if from then
					text = text .. "\n|cffffd100" .. L["Here: %s (%s's own preset)"]:format(
						ns.GetTintPresetLabel(here),
						from == "area" and ns.GetAreaTintInfo() or GetRealZoneText() or "?") .. "|r"
				end
				if here == "zone" or here == "zonetime" then
					local zone, label, isOverride = ns.GetZoneTintInfo()
					text = text .. "\n|cffffd100" .. L["Here: %s (%s%s)"]:format(
						label, zone, isOverride and L[", your choice"] or "") .. "|r"
				end
				if here == "timeofday" or here == "zonetime" then
					local phase, hour, minute = ns.GetTimeOfDayInfo()
					if (db.tintPreviewHour or -1) >= 0 then
						text = text .. "\n|cffffd100" .. L["Previewing: %s (%02d:00)"]:format(L[phase], hour) .. "|r"
					else
						text = text .. "\n|cffffd100" .. (db.tintClock == "local" and L["Now: %s (%02d:%02d your time)"]
							or L["Now: %s (%02d:%02d game time)"]):format(L[phase], hour, minute) .. "|r"
					end
				end
				self:SetText(text)
			end
		end
	end
	controls[#controls + 1] = presetText

	-- (The strengths, the drift and the zone borders' timing: the Tint tab's,
	-- LetterboxStyle.lua.)

	-- Custom colour swatch
	local swatch = CreateFrame("Button", nil, content)
	swatch:SetSize(22, 22)
	swatch:SetPoint("TOPLEFT", presetText, "BOTTOMLEFT", 2, -16)
	local swatchBorder = swatch:CreateTexture(nil, "BACKGROUND")
	swatchBorder:SetAllPoints()
	swatchBorder:SetColorTexture(0.6, 0.6, 0.6, 1)
	local swatchColor = swatch:CreateTexture(nil, "ARTWORK")
	swatchColor:SetPoint("TOPLEFT", 2, -2)
	swatchColor:SetPoint("BOTTOMRIGHT", -2, 2)
	local swatchLabel = Label(content, "GameFontHighlight", L["Custom color"])
	swatchLabel:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
	Tooltip(swatch, L["Click to choose the color used by the Custom preset."])
	swatch.Refresh = function()
		local db = ns.GetDB()
		swatchColor:SetColorTexture(db.tintCustomR, db.tintCustomG, db.tintCustomB, 1)
	end
	controls[#controls + 1] = swatch
	swatch:SetScript("OnClick", function()
		local db = ns.GetDB()
		OpenColorPicker(db.tintCustomR, db.tintCustomG, db.tintCustomB, function(r, g, b)
			db.tintCustomR, db.tintCustomG, db.tintCustomB = r, g, b
			swatch.Refresh()
			ns.RefreshTint()
		end)
	end)

	-- Time of day: which clock, strength, your own phases
	local timeHeader = Header(content, L["Time of day"], swatch, -24)
	timeHeader:SetPoint("TOPLEFT", swatch, "BOTTOMLEFT", -2, -24)
	local timeHelp = Label(content, "GameFontHighlightSmall",
		L["For the Time of day and Zone + time of day presets, and the time of day message."])
	timeHelp:SetPoint("TOPLEFT", timeHeader, "BOTTOMLEFT", 0, -6)

	-- (Its title on the screen, at login and as it changes: the Cards page's now.)
	local timeMessage = ns.CardsLink(content, L["The time of day's title and sound:"], "time")
	timeMessage:SetPoint("TOPLEFT", timeHelp, "BOTTOMLEFT", 0, -8)

	local clockLabel = Label(content, "GameFontHighlight", L["Follows"])
	clockLabel:SetPoint("TOPLEFT", timeMessage, "BOTTOMLEFT", 0, -10)
	local CLOCKS = {
		{ value = "game", text = L["Game time (matches the game's day and night)"] },
		{ value = "local", text = L["Your computer's clock"] },
	}
	local clockControl = Dropdown(content, "tintClock", CLOCKS, 300, function()
		ns.RefreshTint()
	end)
	if clockControl then
		clockControl:SetPoint("TOPLEFT", clockLabel, "BOTTOMLEFT", 0, -6)
	else
		local previous = clockLabel
		for i, clock in ipairs(CLOCKS) do
			local check = Choice(content, "tintClock", clock.value, clock.text)
			check:HookScript("OnClick", ns.RefreshTint)
			check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -6 or -2)
			previous = check
		end
		clockControl = previous
	end

	-- Time of day: your own phase colours (its strength: the Tint tab's)
	local phaseLabel = Label(content, "GameFontHighlight", L["Phases (click a color to change it)"])
	phaseLabel:SetPoint("TOPLEFT", clockControl, "BOTTOMLEFT", 0, -16)
	local previousPhase = phaseLabel
	for i, phase in ipairs(ns.GetTimePhases()) do
		local name = phase.name
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(460, 40) -- room for the strength slider's label above it
		row:SetPoint("TOPLEFT", previousPhase, "BOTTOMLEFT", 0, i == 1 and -2 or 0)
		local swatch = CreateFrame("Button", nil, row)
		swatch:SetSize(20, 20)
		swatch:SetPoint("BOTTOMLEFT", 0, 4)
		local border = swatch:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.6, 0.6, 0.6, 1)
		local fill = swatch:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("TOPLEFT", 2, -2)
		fill:SetPoint("BOTTOMRIGHT", -2, 2)
		local text = Label(row, "GameFontHighlightSmall", L[name])
		text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
		text:SetWidth(110)
		text:SetJustifyH("LEFT")
		local strength = Slider(row, {
			get = function()
				for _, p in ipairs(ns.GetTimePhases()) do
					if p.name == name then return p.strength end
				end
				return 1
			end,
			set = function(value) ns.SetTimePhaseStrength(name, value) end,
		}, L["Strength"], 0, 100, 5, "%d%%", 100, function()
			ns.PreviewTintHour(phase.hour) -- show the phase you're adjusting
		end)
		strength:SetWidth(150)
		strength:SetPoint("LEFT", text, "RIGHT", 4, 0)
		local reset = ns.PanelButton(row)
		reset:SetSize(60, 20)
		reset:SetPoint("LEFT", strength, "RIGHT", 16, 0)
		reset:SetText(L["Reset"])
		Tooltip(reset, L["Back to the built-in color and strength."])
		Tooltip(swatch, L["Choose your own color for %s."]:format(L[name]))
		swatch:SetScript("OnClick", function()
			local color
			for _, p in ipairs(ns.GetTimePhases()) do
				if p.name == name then color = p.color end
			end
			OpenColorPicker(color[1], color[2], color[3], function(r, g, b)
				ns.SetTimePhaseColor(name, { r, g, b })
				Refresh()
			end)
		end)
		reset:SetScript("OnClick", function()
			ns.SetTimePhaseColor(name, nil)
			ns.SetTimePhaseStrength(name, nil)
			Refresh()
		end)
		row.Refresh = function()
			for _, p in ipairs(ns.GetTimePhases()) do
				if p.name == name then
					fill:SetColorTexture(p.color[1], p.color[2], p.color[3], 1)
					reset:SetEnabled(p.own or p.ownStrength)
				end
			end
		end
		controls[#controls + 1] = row
		previousPhase = row
	end

	-- Per-zone overrides: a preset of its own, and colours for the Zone presets
	local zoneHeader = Header(content, L["Zone tints"], previousPhase, -24)
	local zoneHelp = PageIntro(content, zoneHeader,
		L["Give the zone you're standing in, or just the area within it (a town, a port), a " ..
		"preset of its own: it replaces your main preset there. With a Zone preset you can also " ..
		"choose its color, which replaces the built-in mood. An area's choices win over its zone's."])

	local zoneText = Label(content, "GameFontHighlight")
	zoneText:SetPoint("TOPLEFT", zoneHelp, "BOTTOMLEFT", 0, -10)
	zoneText:SetWidth(420)
	zoneText:SetJustifyH("LEFT")
	zoneText.Refresh = function(self)
		local zone, label, isOverride = ns.GetZoneTintInfo()
		local strength, ownStrength = ns.GetZoneTintStrength(zone)
		local function PresetNote(name)
			local preset = ns.GetZonePreset(name)
			return preset and (L[", |cffffd100%s|r preset"]):format(ns.GetTintPresetLabel(preset)) or ""
		end
		local text = (L["This zone: |cffffd100%s|r - %s%s, %d%% strength%s%s"]):format(
			zone ~= "" and zone or "?", label, isOverride and L[" (your choice)"] or L[" (built in)"],
			strength * 100 + 0.5, ownStrength and L[" (its own)"] or "", PresetNote(zone))
		local area, areaLabel, areaOwn, _, areaStrength, _, areaOwnStrength = ns.GetAreaTintInfo()
		if area then
			text = text .. "\n" .. (L["This area: |cffffd100%s|r - %s%s, %d%% strength%s%s"]):format(
				area, areaLabel, areaOwn and L[" (your choice)"] or "", areaStrength * 100 + 0.5,
				areaOwnStrength and L[" (its own)"] or "", PresetNote(area))
		end
		self:SetText(text)
	end
	controls[#controls + 1] = zoneText

	-- Which the choices below change: the zone, or just the area you're in.
	local tintTarget = "zone"
	local function TargetName()
		local area = ns.GetAreaTintInfo()
		if tintTarget == "area" and area then
			return area
		end
		return GetRealZoneText() or ""
	end
	local function TargetColor()
		local area, _, _, areaColor = ns.GetAreaTintInfo()
		if tintTarget == "area" and area then
			return areaColor
		end
		local _, _, _, color = ns.GetZoneTintInfo()
		return color
	end
	local targetLabel = Label(content, "GameFontHighlight", L["Change:"])
	targetLabel:SetPoint("TOPLEFT", zoneText, "BOTTOMLEFT", 0, -10)
	local targetButtons = {}
	local function TargetButton(value, x)
		local ok, button = pcall(CreateFrame, "CheckButton", nil, content, "UIRadioButtonTemplate")
		if ok and button then ns.SkinCheck(button, true) end
		if not ok or not button then
			button = ns.SkinCheck(CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate"))
			button:SetSize(22, 22)
		end
		button:SetPoint("LEFT", targetLabel, "RIGHT", x, 0)
		button.text = Label(content, "GameFontHighlight")
		button.text:SetPoint("LEFT", button, "RIGHT", 2, 0)
		button:SetScript("OnClick", function()
			tintTarget = value
			Refresh()
		end)
		button.Refresh = function(self)
			local area = ns.GetAreaTintInfo()
			self:SetChecked(tintTarget == value or (value == "zone" and not area))
			if value == "zone" then
				self.text:SetText(L["the zone"])
			else
				self.text:SetText(area and L["this area (%s)"]:format(area) or L["this area (none here)"])
				self:SetEnabled(area ~= nil)
			end
		end
		controls[#controls + 1] = button
		targetButtons[#targetButtons + 1] = button
		return button
	end
	TargetButton("zone", 8)
	TargetButton("area", 110)

	local function SetHere(value)
		local name = TargetName()
		if name ~= "" then
			ns.SetZoneTint(name, value)
			Refresh()
			FitContentHeight(content)
		end
	end

	-- Menu of presets for this zone or area (left out on clients without the dropdown).
	local presetMenu
	local ok, dropdown = ns.MenuDropdown(content)
	if ok and dropdown and dropdown.SetupMenu then
		presetMenu = dropdown
		presetMenu:SetWidth(200)
		presetMenu:SetupMenu(function(_, root)
			local function current() return ns.GetZonePreset(TargetName()) end
			local function set(value)
				local name = TargetName()
				if name ~= "" then
					ns.SetZonePreset(name, value)
					Refresh()
					FitContentHeight(content)
				end
			end
			local isArea = tintTarget == "area" and ns.GetAreaTintInfo()
			root:CreateRadio(isArea and L["Same as the zone"] or L["Main preset"],
				function() return current() == nil end, function() set(nil) end)
			for _, preset in ipairs(ns.TINT_PRESETS) do
				root:CreateRadio(preset.label, function() return current() == preset.key end,
					function() set(preset.key) end)
			end
		end)
		presetMenu.Refresh = function(self) self:GenerateMenu() end
		controls[#controls + 1] = presetMenu
		presetMenu:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -10)
		local presetMenuLabel = Label(content, "GameFontHighlight", L["Preset here"])
		presetMenuLabel:SetPoint("LEFT", presetMenu, "RIGHT", 12, 0)
		Tooltip(presetMenu, L["A preset for the zone or area chosen above, used there instead of your " ..
			"main preset."])
	end

	-- Menu of tints for this zone (left out on clients without the dropdown).
	local zoneMenu
	ok, dropdown = ns.MenuDropdown(content)
	if ok and dropdown and dropdown.SetupMenu then
		zoneMenu = dropdown
		zoneMenu:SetWidth(200)
		zoneMenu:SetupMenu(function(_, root)
			local function current()
				local db = ns.GetDB()
				return db and db.zoneTints and db.zoneTints[TargetName()]
			end
			root:CreateRadio(L["Built-in mood"], function() return current() == nil end,
				function() SetHere(nil) end)
			root:CreateRadio(L["No tint"], function() return current() == "none" end,
				function() SetHere("none") end)
			for _, mood in ipairs(ns.GetZoneMoods()) do
				local hex = ("|cff%02x%02x%02x"):format(mood.color[1] * 255, mood.color[2] * 255, mood.color[3] * 255)
				root:CreateRadio(hex .. mood.label .. "|r", function() return current() == mood.key end,
					function() SetHere(mood.key) end)
			end
			root:CreateRadio(L["Custom color"], function() return type(current()) == "table" end,
				function()
					local color = TargetColor()
					SetHere({ color[1], color[2], color[3] })
				end)
		end)
		zoneMenu.Refresh = function(self) self:GenerateMenu() end
		controls[#controls + 1] = zoneMenu
		zoneMenu:SetPoint("TOPLEFT", presetMenu or targetLabel, "BOTTOMLEFT", 0, -10)
	end

	local pickColor = ns.PanelButton(content)
	pickColor:SetSize(140, 22)
	pickColor:SetText(L["Pick a color..."])
	if zoneMenu then
		pickColor:SetPoint("LEFT", zoneMenu, "RIGHT", 12, 0)
	else
		pickColor:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -10)
	end
	Tooltip(pickColor, L["Choose your own color for the zone or area chosen above (for the Zone presets)."])
	pickColor:SetScript("OnClick", function()
		local name = TargetName()
		if name == "" then
			return
		end
		local color = TargetColor()
		OpenColorPicker(color[1], color[2], color[3], function(r, g, b)
			ns.SetZoneTint(name, { r, g, b })
			Refresh()
			FitContentHeight(content)
		end)
	end)

	-- Your overrides, each with a reset button.
	local overridesLabel = Label(content, "GameFontNormalSmall", L["Your zone tints"])
	overridesLabel:SetPoint("TOPLEFT", zoneMenu or pickColor, "BOTTOMLEFT", 0, -16)
	local MAX_ZONE_ROWS = 15
	local zoneRows = {}
	for i = 1, MAX_ZONE_ROWS do
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(420, 22)
		row:SetPoint("TOPLEFT", overridesLabel, "BOTTOMLEFT", 0, -6 - (i - 1) * 24)
		row.button = ns.PanelButton(row)
		row.button:SetSize(70, 20)
		row.button:SetPoint("LEFT")
		row.button:SetText(L["Reset"])
		row.button:SetScript("OnClick", function()
			if row.zone then
				ns.SetZoneTint(row.zone, nil)
				ns.SetZoneTintStrength(row.zone, nil)
				ns.SetZonePreset(row.zone, nil)
				Refresh()
				FitContentHeight(content)
			end
		end)
		row.swatch = row:CreateTexture(nil, "ARTWORK")
		row.swatch:SetSize(14, 14)
		row.swatch:SetPoint("LEFT", row.button, "RIGHT", 8, 0)
		row.text = Label(row, "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", row.swatch, "RIGHT", 8, 0)
		row.text:SetPoint("RIGHT")
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row:Hide()
		zoneRows[i] = row
	end
	local zoneMore = Label(content, "GameFontHighlightSmall")
	zoneMore.Refresh = function(self)
		local zones = {}
		local db, listed = ns.GetDB(), {}
		for _, source in ipairs({ db.zoneTints or {}, db.zoneTintStrength or {}, db.zonePresets or {} }) do
			for zone in pairs(source) do
				if not listed[zone] then
					listed[zone] = true
					zones[#zones + 1] = zone
				end
			end
		end
		table.sort(zones)
		for i, row in ipairs(zoneRows) do
			local zone = zones[i]
			row.zone = zone
			if zone then
				local _, label, _, color = ns.GetZoneTintInfo(zone)
				row.swatch:SetColorTexture(color[1], color[2], color[3], 1)
				local strength, ownStrength = ns.GetZoneTintStrength(zone)
				local preset = ns.GetZonePreset(zone)
				row.text:SetText(("%s: %s%s%s"):format(zone,
					preset and L["%s preset, "]:format(ns.GetTintPresetLabel(preset)) or "", label,
					ownStrength and (L[", %d%% strength"]):format(strength * 100 + 0.5) or ""))
			end
			row:SetShown(zone ~= nil)
		end
		local shownRows = math.min(#zones, MAX_ZONE_ROWS)
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", overridesLabel, "BOTTOMLEFT", 0, -8 - shownRows * 24)
		if #zones == 0 then
			self:SetText(L["None yet."])
		elseif #zones > MAX_ZONE_ROWS then
			self:SetText((L["...and %d more."]):format(#zones - MAX_ZONE_ROWS))
		else
			self:SetText("")
		end
	end
	controls[#controls + 1] = zoneMore

	-- Keep "This zone" up to date if you cross a border with the page open.
	local zoneWatcher = CreateFrame("Frame", nil, canvas)
	zoneWatcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	zoneWatcher:RegisterEvent("ZONE_CHANGED") -- moving between areas within a zone
	zoneWatcher:SetScript("OnEvent", function()
		if canvas:IsVisible() then
			Refresh()
		end
	end)

	canvas:SetScript("OnShow", PageShown(function()
		Refresh()
		ns.SetTintPreview(true)
	end, content))
	canvas:SetScript("OnHide", function() ns.SetTintPreview(false) end)
	canvas:Hide()
	RegisterSubpage(canvas, "Tint Style", L["Tint"])
end

-- Sub-page: Graphics+, the game's graphics settings past its menu's most
-- (Graphics.lua). Each slider only on clients that have its setting.
local function CreateGraphicsPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Graphics+"])
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title,
		L["The game's own graphics settings one by one, past its Graphics menu either way: higher for a better " ..
		"look, lower for a faster game. They're this computer's: the same in every profile."] .. "\n\n" ..
		L["A slider changes nothing until you move it. Higher (in gold) costs frame rate, lower " ..
		"(in blue) saves it. Tick and untick a setting to compare it with the game's own; Reset page leaves them " ..
		"all alone again."] .. "\n\n" ..
		L["Ground clutter changes show as the ground around you loads again: move on a " ..
		"little, or /reload. Changing the game's Graphics menu doesn't undo these: they're written again " ..
		"over its new settings."])

	local function Changed() ns.ApplyGraphicsPlus() end
	local switch = PageSwitch(content, "graphicsPlus", L["Enable Page"],
		L["On: the settings below, as you've set them. Off: the game's own settings, put back as they were."],
		subtitle, Changed)
	local stack = Stack(switch, "check")

	local LABELS = {
		graphicsPlusClutter = { L["Ground clutter density"], L["How thickly grass, flowers and stones grow " ..
			"on the ground."] },
		graphicsPlusClutterDistance = { L["Ground clutter distance"], L["How far away grass and flowers still " ..
			"show."] },
		graphicsPlusClutterFade = { L["Ground clutter fade"], L["How far away grass and flowers grow full " ..
			"before they start thinning out towards the clutter distance. Above the clutter distance it makes " ..
			"no more difference."] },
		graphicsPlusView = { L["View distance"], L["How far away the land is drawn in full before it turns " ..
			"into the flat, faded horizon, and how far anything is drawn at all. Very demanding: with terrain " ..
			"and building detail turned up too, most of all."] },
		graphicsPlusTerrain = { L["Terrain detail distance"], L["How far away the land keeps its full shape " ..
			"before it turns low detail."] },
		graphicsPlusBuildings = { L["Building detail distance"], L["How far away buildings keep their full " ..
			"detail."] },
		graphicsPlusObjects = { L["Object detail distance"], L["How far away trees, rocks and other objects " ..
			"keep their full detail before they're swapped for simpler ones or fade out."] },
		graphicsPlusObjectFade = { L["Object fade distance"], L["How far away small objects stay before they " ..
			"fade out. Much higher costs a lot of frame rate for little to see."] },
		graphicsPlusCreatures = { L["Creature detail distance"], L["How far away creatures and characters keep " ..
			"their full detail before they're swapped for simpler models."] },
		graphicsPlusPlateDistance = { L["Nameplate distance"], L["How far away nameplates show, in yards. " ..
			"The game won't go past its own limit. Reset page puts the game's default back."] },
		graphicsPlusZoomMax = { L["Max zoom distance"], L["How far out you can zoom the camera, as times the " ..
			"game's base distance. The game won't go past its own limit. Idle zoom's \"past your max\" still " ..
			"raises it to 2.6 while it zooms, if it's lower."] },
		graphicsPlusShadows = { L["Shadow sharpness"], L["The size of the game's shadow maps: bigger gives " ..
			"crisper shadow edges, smaller saves frame rate. Players found nothing more above 2048, so 4096 may " ..
			"look the same. Needs shadows on in the game's menu."] },
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
			local tip = text[2] .. " " .. ((setting.noMenu
				and L["The game's menu doesn't change it. Its default is %s."]:format(
					tostring(ns.GraphicsPlusDefault(setting.cvar))))
				or (setting.min == 0 and L["The game's menu doesn't change it: it's %s."]:format(setting.menu))
				or L["The game's menu goes from %s to %s."]:format(setting.min, setting.menu))
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
	RegisterSubpage(canvas, "Graphics+")
end

-- Sub-page for audio: music during cinematic mode.
local function CreateAudioPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Audio"])
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title,
		L["Sound during CineMode. Your own sound settings are saved first and put " ..
		"back afterwards, even after a crash. Pick which cameras play music as they start."])

	-- The page's switch: off, CineMode leaves music alone (nothing below applies).
	local music = PageSwitch(content, "musicInCinematic", L["Enable Page"],
		L["On: with your game music off, a camera starting (the ones ticked under Music on the Camera " ..
		"Triggers page) switches it on and fades it in, at your music volume; it fades out when " ..
		"the UI returns and your music is switched off again (logging out too). With your game " ..
		"music on, it's left alone, bar the stops below. Off: CineMode leaves your music alone."], subtitle)

	-- One column, each slider on one line with its name (an inline stack, as on Graphics+).
	local stack = Stack(music, "check", true)

	-- First: where and when music plays, a row as the Standard Frames
	-- page's (GridRows.lua). Off: it fades out (your own game music too), back after.
	local playsHeader = stack:Header(content, L["Music plays in"])
	stack:Help(content,
		L["Where and when music can play in CineMode; anywhere else it fades out (your own game music too) " ..
		"and back in after. Always: everywhere. Out of combat: back once the Calm Timer has run out after a " ..
		"fight (with Calm Timer too: as soon as the fight ends)."])
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
	Tooltip(fatigue, L["Once a camera has started music, no camera starts it again for this long, " ..
		"counted from when it started. The first camera after a login or /reload always can. " ..
		"Music coming back after a mute doesn't count. 0 turns this off."])

	-- Stopping as you leave the camera modes.
	stack:Add(Check(content, "musicPauseWhenMoving", L["Stop music leaving a camera mode"],
		L["Music fades out once you leave the camera modes and move on: walking off from the cozy " ..
		"camera, say. Going from one camera straight to another (vista to cozy) keeps it playing, " ..
		"as does standing still. A fresh track fades in when the next camera starts (standing " ..
		"still counts once the AFK camera starts, with Go AFK's music on, Scenes page). " ..
		"Fades at the music fade time."]), "check")

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
	Refresh = Refresh, headingHeight = FRAME_HEADING_HEIGHT, ShowBox = ShowBox, RowShown = RowShown }

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
		L["While CineMode is on, the camera comes alive when something happens: an emote, a campfire, " ..
		"going AFK, your Hearthstone, fishing, a flight, a quest giver, auto-walking or dying. The Scenes page " ..
		"says what starts which camera; the Scripts page has each camera's steps and settings. Moving " ..
		"by hand cancels them all, and everything goes back to normal when the UI returns."] .. "\n\n" ..
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
		L["Each row is a scene: when one of its triggers happens, it plays its camera. When two scenes are on at " ..
		"once, a Hearthstone or teleport cast comes first, then logging out, going AFK, the latest emote, a drawn " ..
		"weapon, a campfire, and standing still last. Click a row to open its settings: its camera, Music and " ..
		"CineMode, When it may start, its triggers, and anything it needs. The chips beside its name show what's " ..
		"set apart from the usual. Where its When doesn't fit, a row starts no camera. Untick the box at the start " ..
		"of a row to turn it off for now."])

	-- Each trigger's name and tip (the events' from ns.EVENTS and EVENT_TIPS).
	local LABELS = { Walk = L["Auto-walk (RP walk)"], Run = L["Auto-run"], Death = L["Die"],
		Chat = L["NPCs you talk to"], ChatNearby = L["NPCs chatting nearby"] }
	for _, event in ipairs(ns.EVENTS) do LABELS[event.key] = event.label end
	local TIPS = {
		Walk = L["Auto-walking (auto-run in walk mode). The camera's settings are under RP Walk Cam on the " ..
			"Camera Settings page."],
		Run = L["Auto-running. The camera's settings are under Auto-run Cam on the Camera Settings page."],
		Death = L["Dying, until you release or are resurrected. The camera's settings are under Death Cam on " ..
			"the Camera Settings page."],
		Chat = L["An NPC you're talking to (its window open, or closed in the last 30 seconds), your target, or " ..
			"a party NPC talking (their chat bubbles). The camera zooms in and swings toward whoever's talking, " ..
			"drifting while they go on, and turns back once no one's talked for a while. Moving hands the camera " ..
			"straight back to you. Its settings are under Chat Cam on the Camera Settings page."],
		ChatNearby = L["Other NPCs talking near you, such as a city's citizens chatting among themselves. The " ..
			"same chat camera, once you've stood still for the time below, so passers-by don't swing it about while " ..
			"you're busy."],
	}
	local MUSIC_TIP = L["Music starts as this event's camera starts, unless the addon started music " ..
		"within the fatigue time (Audio page). Music already playing just carries on. Off: this " ..
		"camera never starts music. Needs the Audio page enabled."]
	local MUSIC_TIPS = {
		AFK = MUSIC_TIP .. L[" While you're flagged AFK, whatever the camera. Off also keeps music from coming back " ..
			"after a pause while you're away."],
		Still = MUSIC_TIP .. L[" Off also keeps music from coming back after a pause while you stand still."],
		Death = L["A song of its own plays while the death camera runs, in place of the zone music " ..
			"(pick the songs under Death Cam on the Camera Settings page). With CineMode music off, " ..
			"only if your game music is on."],
	}
	local CINE_TIP = L["With \"Start in CineMode\" off (Cinematic's main page), this event's camera " ..
		"starting brings CineMode on (the UI fades, music, visual effects), and it ends with the " ..
		"camera. Tick Stand still and Go AFK for a screensaver: the normal UI while you play, " ..
		"CineMode once you've been idle a while."]
	-- What each trigger needs besides (its own row's drawer only: the copies share it).
	local EXTRAS = {
		Campfire = { L["Buffs"], list = "cozyBuffs", tip = L["Buff names or spell IDs, separated by commas. Names " ..
			"must match your game language; spell IDs work in any language."] },
		Chair = { L["Seats"], list = "cozyChairWords", tip = L["Words that mark a seat when they're in an " ..
			"object's name (\"Wooden Chair\"), separated by commas. Use words in your game language."] },
		Still = { L["Wait"], slider = { "idleOrbitDelay", L["After standing still for"], 5, 300, 5, L["%d sec"] },
			tip = L["How long you stand still before this row's camera starts (an event set to the AFK camera, " ..
			"like going AFK, skips the wait). Also used by the other options that mention standing still (tint, " ..
			"tracking, music, tooltips)."] },
		Quest = { L["Wait"], slider = { "questCamDelay", L["Wait before starting"], 0, 10, 0.5, L["%.1f sec"] },
			tip = L["The camera waits this long on a quest window before starting. Accept a quest and go " ..
			"sooner, and it doesn't move at all; stay to read, and it starts. Clicking through several " ..
			"quests, each new window adds a second to the wait. 0 starts at once."] },
		QuestGossip = { L["Wait"], slider = { "questCamGossipDelay", L["Wait before starting"], 0, 10, 0.5,
			L["%.1f sec"] }, tip = L["The camera waits this long on the window before starting. Close it sooner, " ..
			"and it doesn't move at all. 0 starts at once."] },
		Walk = { L["Wait"], slider = { "walkCameraDelay", L["After auto-walking for"], 0, 60, 1, L["%d sec"] } },
		Run = { L["Wait"], slider = { "runCameraDelay", L["After auto-running for"], 0, 60, 1, L["%d sec"] } },
		ChatNearby = { L["Wait"], slider = { "chatNearbyDelay", L["After standing still for"], 0, 60, 1,
			L["%d sec"] }, tip = L["How long you stand still before NPCs chatting nearby start this row's camera. " ..
			"0: straight away. Moving starts the count over."] },
	}
	-- (Fade at once, beside CineMode on these rows: the trigger's own row's.)
	local INSTANT = { Flight = "taxiInstant", Walk = "walkInstant", Run = "runInstant" }
	local GO_TIP = L["How long you keep going before this row's camera starts (and CineMode, if its CineMode box " ..
		"is ticked). 0: straight away. Stopping or moving by hand first starts the count over."]
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
	local WHEN_HELP = { [ns.GRID_COMBAT] = L["Whether this row's camera may start in a fight (unticked, one " ..
		"running stops when a fight starts), and whether it waits for things to calm down after one."],
		[ns.GRID_LOCATION] = L["Where this row's camera may start (Grouped: in a party or raid). Anywhere else the " ..
		"next row of its trigger is tried, and with none the camera doesn't start (or stops if it's running). For " ..
		"flights, Cities means taking off from one, and Open world taking off anywhere else."] }

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
			L["With a window like the spellbook, the map or these options open, a playing scene waits where it is " ..
			"and carries on as the window closes, and no new one starts. A quest giver's scene and Interaction " ..
			"triggers still play, as their window is what starts them."])
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
	Tooltip(sort, L["How the rows are listed: Camera groups them by camera name, Scene by scene " ..
		"name. Either way a scene's rows stay together, in the order they're tried."])
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
		Tooltip(newTrigger, L["Make a scene of your own: its triggers (an emote, a spell, a buff, a place, a moment, " ..
			"something you are, or a key), the camera it plays and when it ends."])
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
		local on = Place(Check(row, nil, "", L["Use this row. Unticked, its trigger passes it over: the next row " ..
			"for it is tried, and with none it starts no camera. Its settings stay for when you tick it again."],
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
			local tip = EVENT_TIPS[key] or TIPS[key] or (trigger.custom and L["A scene of your own. Open it to set " ..
				"its triggers, when it ends, and where it comes among the others."])
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
			Tooltip(copyButton, L["Copy this row: another row for its trigger, just below, its settings open. Give it " ..
				"another camera and When, and move it above to have it tried first."])
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
				or L["Delete this scene: its rows go and it starts no camera. Add back, above the rows, brings it " ..
				"back with its settings."])
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
		Tooltip(nameBox, L["A name of your own for this row, shown on the grid, say AFK in dungeons. Empty: its " ..
			"trigger's."])

		-- Camera: its camera, its Music and CineMode.
		local pick = At("Camera", CameraPick(drawer, id), LABEL_W)
		Tooltip(pick, trigger.custom and L[ns.CUSTOM_CAMERA_TIP]
			or L["The camera this row starts. No camera: none (and its trigger's rows below aren't tried)."])
		local x = LABEL_W + 166
		if trigger.music then
			local music = Check(drawer, nil, L["Music"], MUSIC_TIPS[key] or MUSIC_TIP, function(value)
				ns.SetCameraRowValue(id, "music", value)
				Changed()
			end)
			music.Refresh = function(self) self:SetChecked(ns.CameraRowValue(id, "music") and true or false) end
			GreyUnless(music, function()
				return (key == "Death" or ns.Setting("musicInCinematic")) and (key == "AFK" or HasCamera(id))
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
				tip = L["This row's camera may start anywhere. The rest of the row keeps its ticks for when you " ..
				"untick this."] },
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
			L["Inside buildings and caves, the camera modes zoom out less and swing less, so the " ..
			"camera doesn't keep pushing into walls and ceilings. Uses the game's own indoor check."])
		indoorLimits:SetPoint("TOPLEFT", indoorHeader, "BOTTOMLEFT", -2, -6)
		indoorLimits:HookScript("OnClick", Refresh) -- grey out / enable the options below
		local function IfIndoorLimits(db) return db.indoorLimits end

		local indoorZoom = Slider(content, "indoorZoomOut", L["Zoom out indoors up to"], 0, 10, 0.5, L["%.1f yards"])
		indoorZoom:SetPoint("TOPLEFT", indoorLimits, "BOTTOMLEFT", 4, -26)
		Tooltip(indoorZoom, L["How far past your own distance the slow zoom may pull back indoors. It " ..
			"also never raises the max zoom distance indoors. Walking in pulled back, the camera " ..
			"glides in to this."])
		GreyUnless(indoorZoom, IfIndoorLimits)

		local indoorSwing = Slider(content, "indoorSwing", L["Swing indoors up to"], 0, 90, 5, "%d°")
		indoorSwing:SetPoint("TOPLEFT", indoorZoom, "BOTTOMLEFT", 0, -34)
		Tooltip(indoorSwing, L["How far either side of behind the flight, RP walk and auto-run cameras " ..
			"may swing indoors."])
		GreyUnless(indoorSwing, IfIndoorLimits)

		local indoorSweep = Check(content, "indoorNoSweep", L["No AFK camera sweep indoors"],
			L["The AFK camera sweeps right round your character, which can bump into walls " ..
			"in tight rooms. Its zoom still runs (within the limit above)."])
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
	for r, item in ipairs(rows) do
		local y = -FRAME_HEADING_HEIGHT - 4 - (r - 1) * ROW_HEIGHT
		local rowLabel = Label(content, "GameFontHighlight", item.label)
		rowLabel:SetPoint("TOPLEFT", columnTop, "TOPLEFT", 0, y - 5)
		rowLabel:SetWidth(LABEL_WIDTH - 4)
		rowLabel:SetJustifyH("LEFT")
		rowLabel:SetWordWrap(false)
		ShowBox(content, item, rowLabel)
		-- A » to its page on rows that have a page of their own.
		if item.morePage then ns.MoreLink(content, rowLabel, item.morePage) end
		ns.LabelHover(content, rowLabel, item.tip)
		if ns.CINE_SHOW_SETTING[item.key] then
			RecordKey(content, ns.CINE_SHOW_SETTING[item.key]) -- (for the page's Reset)
		end
		local alwaysOn = item.alwaysOn or ns.IsCineShowOn
		for c, column in ipairs(item.alwaysOnly and { COLUMNS[1] } or COLUMNS) do
			local isOn, tableKey, needsStay = column[2], column[3], column[4]
			if c == 1 then isOn = alwaysOn end
			local alwaysTip = item.alwaysTip or item.part
				and L["Show it whenever its frame shows. This overrides its Hover groups: untick it to " ..
				"hide it in CineMode except when hovered or brought up by the other columns."]
				or L["Show it all through CineMode, instead of hiding it. (The other columns then have nothing to add.)"]
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
	if ns.IsQuietShowOn(key) or ns.IsCamShowOn(key) or ns.IsCineModeShowOn(key) then return true end
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

-- Sub-page for combat: staying cinematic in fights, and what to show then.
local function CreateCombatPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Game Frames"])
	title:SetPoint("TOPLEFT", 16, -16)

	-- (The rows are dropdowns where the client has menus, else a column each: GridRows.lua.)
	local subtitle = PageIntro(content, title, ns.GRID_MENUS
		and L["Everything here is hidden in CineMode unless ticked. Always shows a frame the whole time; " ..
		"its Fights dropdown, only while you fight or have something targeted; its Places dropdown, the " ..
		"whole time while you're there (Grouped: in a party or raid). Edit turns a row into a rule, for AND, " ..
		"NOT and more places. Frames fade in and out at the fade times on the CineMode page. Other addons' " ..
		"frames are on the Addon Frames page."]
		or L["Everything here is hidden in CineMode unless ticked. Tick a column to show that frame: " ..
		"Always shows it the whole time, the next three only while you fight or have something " ..
		"targeted, and the places the whole time while you're there (Grouped: in a party or raid). " ..
		"Frames fade in and out at the fade times on the CineMode page. Other addons' " ..
		"frames are on the Addon Frames page."])

	-- The game's frames this client has, in sections (their page: see
	-- ROW_SECTIONS), each a table of its own; the gamepad's are on the
	-- Gamepad page, other addons' frames on the Advanced Frames page.
	local switch = PageSwitch(content, "handleFrames", L["Enable Page"],
		L["On: CineMode fades the frames on this page as their rows say. Off: it leaves them all " ..
		"alone, the minimap, quest tracker, buffs and Cooldown Manager included (their pages' " ..
		"switches only count while this is on)."], subtitle, function()
		if ns.ApplyUnitFrameParts then ns.ApplyUnitFrameParts() end
	end)
	-- (With the rows as dropdowns, each row's Combat dropdown has a Calm Timer
	-- of its own instead, GridRows.lua; this stays what rows without one go by.)
	local calm
	if not ns.GRID_MENUS then
		calm = Check(content, "combatShowCalm", L["In combat rows stay for the Calm Timer"],
			L["Frames ticked In combat (here and on the Addon Frames page) stay up after a fight " ..
			"until the Calm Timer (CineMode page) has run out, then fade. Off: they fade as soon as the fight ends."])
		calm:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 0, -2)
		GreyUnless(calm, function(db) return db.stayInCombat end)
	end

	-- (Your player frame kept up while you recover: the Personal Resources page.)
	-- (Pet happiness: the Quality of life > Hunter page.)
	-- The lowest option so far, and how far in from the column edge it sits.
	local lastCheck, lastIndent = calm or switch, 0

	-- Each section a tab of its own, in Heal Vision's folder look
	-- (ns.FolderTabs, made once every section is): the picked one's table
	-- shows on the panel under them, its full name at its top. The raid-style
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
	local panel, ShowTab
	local function OwnPartyRows()
		-- (The page is built before the settings load: the default then.)
		local db = ns.GetDB()
		return db ~= nil and db.raidStylePartySame == false
	end
	-- Shows the picked section, the panel down to its last row.
	local function Layout()
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
		ShowTab(shown)
		panel:SetPoint("BOTTOMRIGHT", sections[shown].last, "BOTTOMLEFT", sections[shown].width + 6, -12)
		FitContentHeight(content)
	end
	local function Pick(section)
		SectionState.Save(picked, section.key)
		Layout()
	end
	-- (ns.FramesLink's: the page opened at a section's tab.)
	function ns.OpenFramesSection(key)
		SectionState.Restore(picked)
		SectionState.Save(picked, key)
		Layout()
		ns.OpenOptions("Standard Frames")
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

	local SECTION_WIDTH = ns.GRID_MENUS and ns.GridTableWidth(FRAME_LABEL_WIDTH, true)
		or FRAME_LABEL_WIDTH + #FRAME_COLUMNS * FRAME_COLUMN_WIDTH
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
		local section = { key = page or "other", tab = tab or heading, width = SECTION_WIDTH }
		local frame = CreateFrame("Frame", nil, content)
		frame:SetSize(SECTION_WIDTH, 20)
		frame:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12, -10)
		frame.searchAlways = true
		section.frame = frame
		local title = Label(frame, "GameFontNormal", heading)
		title:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -3)
		if link then
			ns.StyleLink(frame, title, link[1], link[2], Tooltip, (link[3] or ns.PageLabel(link[1])) .. " »")
				:SetPoint("LEFT", title, "RIGHT", 12, 0)
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
				L["Ticked: party frames shown raid-style (the game's Use Raid-Style Party Frames, in Edit Mode) " ..
				"fade as the Raid tab's rows say. Untick it to give them rows of their own."], function(value)
				ns.GetDB().raidStylePartySame = value
				if not value then
					CopyRaidRows()
				end
				Refresh()
			end)
			-- (At the right end of its name: the label on the right edge, the
			-- box left of it, whatever its width. Hidden with its tab.)
			same:SetParent(frame)
			local text = same.Text or same.text
			text:ClearAllPoints()
			text:SetPoint("RIGHT", frame, "TOPRIGHT", -6, -10)
			same:SetPoint("RIGHT", text, "LEFT", -2, 0)
		end
		local before = Widgets()
		sectionRows.underHeader = true
		sectionRows.noCine = true -- (frames only fade in CineMode: Always says it all)
		section.last = ShowTable(content, frame, sectionRows, "Standard Frames", heading)
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
			section.last = macros
		end
		-- (Under the trackers' rows: the breath bar's look, and hiding it
		-- always. MirrorTimerStyle.lua.)
		if page == "combat" then
			local function Apply()
				if ns.ApplyMirrorTimers then ns.ApplyMirrorTimers() end
				Refresh()
			end
			local function Shown(db) return not db.mirrorHide end
			local function Worded(db) return not db.mirrorHide and not db.mirrorHideText end
			local heading = Label(section.body, "GameFontNormal", L["Breath bar"])
			heading:SetPoint("TOPLEFT", section.last, "BOTTOMLEFT", 0, -14)
			local hide = Check(content, "mirrorHide", L["Hide the breath bar"],
				L["Hides the bar that runs down while you hold your breath underwater, and the game's other bars " ..
				"like it (fatigue in deep water, Feign Death), CineMode or not."], function(value)
					ns.GetDB().mirrorHide = value
					Apply()
				end)
			hide:SetParent(section.body)
			hide:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", -4, -4)
			local words = Check(content, "mirrorHideText", L["Hide its text"],
				L["Hides the word on the bar (Breath, Fatigue...), leaving the bar."], function(value)
					ns.GetDB().mirrorHideText = value
					Apply()
				end)
			words:SetParent(section.body)
			words:SetPoint("TOPLEFT", hide, "BOTTOMLEFT", 0, 0)
			GreyUnless(words, Shown)
			local last = words
			-- (A dropdown with its name before it; nil where the client has no menus.)
			local function Pick(label, key, choices, tip, test)
				local dropdown = Dropdown(content, key, choices, 180, Apply)
				if not dropdown then return end
				local name = Label(section.body, "GameFontHighlight", label)
				name:SetPoint("TOPLEFT", last, "BOTTOMLEFT", last == words and 4 or 0, -10)
				name:SetSize(90, 30)
				name:SetJustifyV("MIDDLE")
				dropdown:SetParent(section.body)
				dropdown:SetPoint("LEFT", name, "RIGHT", 4, 0)
				Tooltip(dropdown, tip)
				GreyUnless(dropdown, test)
				last = name
			end
			Pick(L["Bar texture:"], "mirrorTexture", function() return ns.StyleTextureChoices() end,
				L["The bar's fill. The game's: as it comes."], Shown)
			Pick(L["Font:"], "mirrorFont", function() return ns.StyleFontChoices() end,
				L["The font of the word on the bar. (In Russian, Korean and Chinese it stays the game's.)"], Worded)
			local size = Slider(content, "mirrorTextScale", L["Text size"], 50, 200, 5, "%d%%", 100,
				function() if ns.ApplyMirrorTimers then ns.ApplyMirrorTimers() end end)
			size:SetParent(section.body)
			size:SetPoint("TOPLEFT", last, "BOTTOMLEFT", last == words and 4 or 0, -22)
			Tooltip(size, L["The size of the word on the bar, against the game's."])
			GreyUnless(size, Worded)
			section.last = size
		end
		sections[#sections + 1] = section
	end
	local raidStyle = { "Raid Style", L["Opens the Style hub's Raid frames page: how the raid and raid-style " ..
		"party frames look."], L["Style"] }
	local SECTIONS = {
		{ "units", L["Unit frames"], nil, { "Unit Frames", L["Opens the Unit Frames page: which parts of your " ..
			"own, your target's and the other unit frames show, and when."], L["Parts"] } },
		{ "bars", L["Action bars"] }, { "combat", L["Trackers"] },
		{ "interface", L["Info and menus"] }, { "minimap", L["Minimap"] },
		{ "party", L["Party frames (not raid-style)"], L["Party"] },
		-- (Their look: the Style hub's Raid frames page, RaidStyle.lua.)
		{ "raid", L["Raid frames"], L["Raid"], raidStyle },
		{ "rsparty", L["Party frames (raid-style)"], L["Raid-style"], raidStyle },
		{ false, L["Other"] }, -- (any row not given a section)
	}
	for _, section in ipairs(SECTIONS) do
		Section(section[1] or nil, section[2], section[3], section[4])
	end
	local list, _, base, height = {}
	for i, section in ipairs(sections) do list[i] = { section.tab } end
	panel, _, ShowTab, base, height = ns.FolderTabs(content, list, function(i) Pick(sections[i]) end, nil,
		SECTION_WIDTH + 8)
	panelTop:SetPoint("TOPLEFT", lastCheck, "BOTTOMLEFT", 2 - lastIndent, -16 - height) -- (back to the column edge)
	panel:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
	-- (On panelTop, not the panel: the panel's bottom hangs on the rows under them.)
	base:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
	Layout()

	canvas:SetScript("OnShow", PageShown(function()
		Refresh()
		Layout() -- (as last left, once the settings have loaded)
	end, content))
	canvas:Hide()
	RegisterSubpage(canvas, L["Standard Frames"], L["Game Frames"])
end

-- Sub-page: the Unit frame parts grid: the pieces of the player, target,
-- focus and pet frames each kind of unit shows. (Keeping your frame up while
-- you recover is on the Standard Frames page.)
local function CreatePortraitsPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Unit Frames"])
	title:SetPoint("TOPLEFT", 16, -16)
	-- Their look: the Style hub's Unit frames page (UnitStyle.lua).
	local styleLink = ns.StyleLink(content, title, "Unit Style", L["Opens the Style hub's Unit frames page: how the " ..
		"frames look."], Tooltip)
	ns.FramesLink(content, title, "units", styleLink)

	-- (With the grids the page's own ? says what they do: no header of their
	-- own under the title, which would only say Unit frame parts again.)
	local hasParts = ns.HasUnitFrameParts and ns.HasUnitFrameParts()
	local subtitle = PageIntro(content, title, hasParts
		and L["Which parts of the unit frames show, CineMode or not: your own frame and your pet's, and " ..
		"the target, focus and target of target frames. Pick a frame's tab to see " ..
		"its grid: the focus and target of target go as the target's grid says until you untick Same " ..
		"as target. Untick parts to keep just the bars. The frame art is the portrait ring, the name " ..
		"box and the bars' borders: the game draws them as one picture. Icons are the rest Zzz, the " ..
		"group leader's crown, role and quest icons, and the raid marker (skull, moon...) on the target " ..
		"and focus frames. Auras are the buffs and debuffs on the target and " ..
		"focus frames. Hit text is the damage and healing numbers on your and your pet's portraits. " ..
		"Threat is the threat percentage and aggro glow on the target and focus frames, for NPCs you " ..
		"can fight."] .. " " .. L["Cast bar is the bar under the target and focus frames as they cast."] ..
		" " .. L["Health bar and Power bar are the bars (Power: mana, rage, energy...). Bar numbers are the " ..
		"percent and value on them, hidden with their bar too."] ..
		" " .. L["Name background is the colored strip behind the name on the target and focus frames, " ..
		"hidden with the name too."] ..
		" " .. L["Level background is the ring behind the level number, hidden with the level too."] ..
		" " .. L["Keeping a frame up, always or in fights, is on the Game Frames page; your own while you " ..
		"recover, on the Resource Display page."]
		or L["Which parts of the player, target, focus and pet frames show. Keeping a frame up, always or " ..
		"in fights, is on the Game Frames page; your own while you recover, on the Resource Display page."])

	-- The Unit frame parts (frames laid out as retail's: see
	-- ns.ApplyUnitFrameParts), a section per frame that opens and closes with
	-- a click on its name: a row per part the frame has, as the Standard
	-- Frames page's (GridRows.lua): Always (its unitPart<frame><part>
	-- setting, ticked to start with), the Combat, Target and Location
	-- dropdowns, the roles and Edit, keyed by that setting. Unticked Always:
	-- hidden but as the rest of the row says (ns.RowOnNow), CineMode or not.
	-- The focus and target of target sections have a "Same as target" tick:
	-- ticked, the rows grey and the section closes, and the frame goes by the
	-- target's; unticked, it opens with the target's rows to start from.
	local OpenSections -- (opens You, your pet and Target, and the frames set apart from the target)
	if hasParts then
		local note = PageSwitch(content, "handleUnitFrames", L["Enable Page"],
			L["On: the unit frames show the parts the grids below say. Off: CineMode leaves them alone, " ..
			"every part showing as the game has it."], subtitle, function() ns.ApplyUnitFrameParts() end)

		local LABEL_WIDTH, ROW_HEIGHT = 150, 24
		local PARTS = ns.UnitPartLabels()
		-- Each section: its title, its frame (unit: the settings' unitPart<unit><part>),
		-- the frame's parts and its "Same as target" setting.
		local SECTIONS = {
			{ title = L["You"], unit = "Player", parts = ns.UNIT_PARTS_PLAYER },
			{ title = L["Your pet"], unit = "Pet", parts = ns.UNIT_PARTS_PET },
			{ title = L["Target"], unit = "Target", parts = ns.UNIT_PARTS_TARGET },
		}
		if _G.TargetFrameToT then
			SECTIONS[#SECTIONS + 1] = { title = L["Target of target"], unit = "ToT", same = "unitPartsToTSame",
				parts = ns.UNIT_PARTS_TOT }
		end
		if _G.FocusFrame then
			SECTIONS[#SECTIONS + 1] = { title = L["Focus"], unit = "Focus", same = "unitPartsFocusSame",
				parts = ns.UNIT_PARTS_TARGET }
		end
		if _G.FocusFrame and _G.FocusFrameToT then
			SECTIONS[#SECTIONS + 1] = { title = L["Focus target of target"], unit = "FocusToT",
				same = "unitPartsFocusToTSame", parts = ns.UNIT_PARTS_TOT }
		end
		-- Whether a section has a part: its frame has it, and it's not one only
		-- some frames have (UNIT_PART_ONLY: hit text).
		local function Has(section, part)
			local only = ns.UNIT_PART_ONLY[part]
			return section.parts[part] ~= nil and (not only or only[section.unit] == true)
		end

		local LAYOUT = { edit = true }
		local OPTS = { quiet = true, cam = true, anyFight = true }
		-- The lists a row keeps its dropdowns' ticks in.
		local LISTS = { "calmShow", "quietShow", "camShow" }
		for c = 2, #FRAME_COLUMNS do
			LISTS[#LISTS + 1] = FRAME_COLUMNS[c][3]
		end
		local ALWAYS_TIP = L["Show it the whole time, CineMode or not. Unticked, it's hidden, except as the other " ..
			"columns say."]
		local liveRows = {}

		-- Each frame a tab of its own, in Heal Vision's folder look
		-- (ns.FolderTabs, made once every section is): the picked one's
		-- section shows on the panel under them, its name at its top. The tab
		-- last picked is kept across reloads (SectionState, its id
		-- "Unit Frames/tab", open the frame's unit).
		local picked = { id = "Unit Frames/tab", open = "Player" }
		-- (The panel's top left, under the tabs (placed once they're made, as
		-- high as their rows); the sections' frames hang on it.)
		local panelTop = CreateFrame("Frame", nil, content)
		panelTop:SetSize(1, 1)
		local panel, ShowTab

		-- Shows the picked section, the panel down to its last row.
		local function Layout()
			local shown
			for i, section in ipairs(SECTIONS) do
				if section.unit == picked.open then shown = i end
			end
			shown = shown or 1
			for i, section in ipairs(SECTIONS) do
				section.frame:SetShown(i == shown)
				section.body:SetShown(i == shown)
			end
			ShowTab(shown)
			panel:SetPoint("BOTTOMRIGHT", SECTIONS[shown].frame, "BOTTOMRIGHT", 12, -12)
			FitContentHeight(content)
		end
		local function Pick(section)
			SectionState.Save(picked, section.unit)
			Layout()
		end
		function OpenSections()
			-- (The page is built before the settings load: the first tab then.)
			SectionState.Restore(picked)
			Layout()
		end
		resetHooks[content] = OpenSections

		-- Set apart from the target: its rows start as the target's, unless it
		-- has choices of its own from before (Always unticked, a dropdown or
		-- role ticked, a rule).
		local function CopyTarget(section)
			local db = ns.GetDB()
			for _, key in ipairs(section.keys) do
				local own = "unitPart" .. section.unit .. key
				if db[own] == false or (db.frameRules and db.frameRules[own]) then
					return
				end
				for _, list in ipairs(LISTS) do
					if db[list] and db[list][own] ~= nil then return end
				end
			end
			for _, key in ipairs(section.keys) do
				local own, target = "unitPart" .. section.unit .. key, "unitPartTarget" .. key
				db[own] = db[target]
				for _, list in ipairs(LISTS) do
					if db[list] then db[list][own] = db[list][target] end
				end
				if db.frameRules then db.frameRules[own] = db.frameRules[target] end
			end
		end

		for _, section in ipairs(SECTIONS) do
			section.widgets, section.keys = {}, {}
			SetSection(content, section.title)
			local frame = CreateFrame("Frame", nil, content)
			frame:SetWidth(LABEL_WIDTH + ns.GridWidth(LAYOUT))
			frame:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12, -10)
			frame.searchAlways = true
			section.frame = frame
			local heading = Label(frame, "GameFontNormal", section.title)
			heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -3)
			-- (Its rows, hidden on other tabs: search still finds them, and picks this one.)
			section.body = CreateFrame("Frame", nil, content)
			section.body:SetPoint("TOPLEFT", frame, "TOPLEFT")
			section.body:SetSize(1, 1)
			section.body.searchAlways = true
			section.body.openSection = function() Pick(section) end
			frame.openSection = section.body.openSection

			-- Same as target, at the right end of its name.
			local same = section.same
			if same then
				local check = Check(content, same, L["Same as target"],
					L["Ticked: this frame shows the parts the Target grid says. Untick it to give the frame " ..
					"choices of its own."], function(value)
					ns.GetDB()[same] = value
					if not value then
						CopyTarget(section)
					end
					ns.ApplyUnitFrameParts()
					Refresh()
				end)
				check:SetParent(frame) -- (hidden with its tab)
				-- (The label on the right edge, the box left of it, whatever its width.)
				local text = check.Text or check.text
				text:ClearAllPoints()
				text:SetPoint("RIGHT", frame, "TOPRIGHT", -6, -10)
				check:SetPoint("RIGHT", text, "LEFT", -2, 0)
			end

			local gridTop = -30
			local headings = CreateFrame("Frame", nil, content)
			headings:SetSize(1, 1)
			headings:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, gridTop)
			for _, heading in ipairs(ns.GridHeadings(ns.GRID_KIT, content, headings, LABEL_WIDTH, LAYOUT)) do
				section.widgets[#section.widgets + 1] = heading
			end
			local r = 0
			for _, part in ipairs(PARTS) do
				if Has(section, part[1]) then
					r = r + 1
					section.keys[#section.keys + 1] = part[1]
					local key = "unitPart" .. section.unit .. part[1]
					local y = gridTop - FRAME_HEADING_HEIGHT - 4 - (r - 1) * ROW_HEIGHT
					RecordKey(content, key)
					for _, list in ipairs(LISTS) do
						RecordKey(content, list)
						RecordRow(content, list, key)
					end
					local label = Label(content, "GameFontHighlight", part[2])
					label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y - 5)
					label:SetWidth(LABEL_WIDTH - 4 - ns.GRID_DOT_ROOM)
					label:SetJustifyH("LEFT")
					label:SetWordWrap(false)
					section.widgets[#section.widgets + 1] = label
					section.widgets[#section.widgets + 1] = ns.LabelHover(content, label) -- (full name while cut short)
					local function Key() return key end
					local function SetAlways(value) ns.GetDB()[key] = value end
					local parts = ns.ListRowParts(Key, FRAME_COLUMNS, nil, SetAlways, OPTS)
					local row = ns.GridRow(ns.GRID_KIT, content, LABEL_WIDTH, LAYOUT, {
						band = r, dot = true,
						always = { isOn = function() return ns.GetDB()[key] ~= false end, set = SetAlways, tip = ALWAYS_TIP },
						menus = parts.menus,
						rule = { key = Key, label = function() return section.title .. ": " .. part[2] end,
							grid = parts.grid, words = parts.words, apply = parts.apply, changed = ns.ApplyUnitFrameParts },
						changed = ns.ApplyUnitFrameParts,
						-- (Greyed while it goes by the target's.)
						enabled = same and function() return ns.GetDB()[same] == false end or nil,
						override = function() return ns.StyleOverrideText(key) end,
					})
					row.debugName = section.title .. ": " .. part[2] -- (for the dev copy's page timing)
					row:SetPoint("TOPLEFT", frame, "TOPLEFT", LABEL_WIDTH, y)
					section.widgets[#section.widgets + 1] = row
					liveRows[#liveRows + 1] = row
				end
			end
			frame:SetHeight(-gridTop + FRAME_HEADING_HEIGHT + 4 + r * ROW_HEIGHT)
			for _, widget in ipairs(section.widgets) do widget:SetParent(section.body) end
		end
		ns.GridDots(content, liveRows)
		local list, _, base, height = {}
		for i, section in ipairs(SECTIONS) do list[i] = { section.title } end
		panel, _, ShowTab, base, height = ns.FolderTabs(content, list, function(i) Pick(SECTIONS[i]) end, nil,
			LABEL_WIDTH + ns.GridWidth(LAYOUT) + 8)
		panelTop:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 2, -14 - height)
		panel:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
		-- (On panelTop, not the panel: the panel's bottom hangs on the rows under them.)
		base:SetPoint("TOPLEFT", panelTop, "TOPLEFT")
		OpenSections()
	end

	local pageShown = PageShown(Refresh, content)
	canvas:SetScript("OnShow", function()
		if OpenSections then OpenSections() end
		pageShown()
	end)
	canvas:Hide()
	RegisterSubpage(canvas, "Unit Frames")
end

-- Sub-page: chat bubbles (where they show; how they look: BubbleStyle.lua).
local function CreateBubblesPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Chat Bubbles"])
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title,
		L["Where chat bubbles show. How they look: the Style hub's Chat bubbles page."])
	-- Their look: the Style hub's Chat bubbles page (BubbleStyle.lua), a
	-- button away, right of the page's title (past its "?").
	local styleButton = ns.PanelButton(content)
	styleButton:SetSize(120, 22)
	styleButton:SetText(L["Style"])
	Tooltip(styleButton, L["Opens the Style hub's Chat bubbles page: how the bubbles and speech from behind " ..
		"you look."])
	styleButton:SetScript("OnClick", function() ns.OpenOptions("Bubble Style") end)
	styleButton:SetPoint("LEFT", title, "RIGHT", 34, 0)

	local function Changed() if ns.ApplyBubbles then ns.ApplyBubbles() end end

	local switch = PageSwitch(content, "handleBubbles", L["Enable Page"],
		L["On: chat bubbles show where this page says. Off: the game's own chat bubble settings, as " ..
		"you had them."], subtitle, Changed)
	-- Show in: a row per kind of bubble, as the Standard Frames page's
	-- (GridRows.lua): where and when each shows.
	local stack = Stack(switch, "check")
	local bubbleHeader = stack:Header(content, L["Show in"])
	stack:Help(content, L["Where and when each kind of bubble shows. Always: everywhere. Nothing ticked: never."])
	local bubbleRows = { opts = { quiet = true, cam = true, anyFight = true }, underHeader = true }
	for _, bubble in ipairs({ { "Say", L["Say"] }, { "Yell", L["Yell"] }, { "Party", L["Party"] }, { "NPC", L["NPCs"] } }) do
		local alwaysKey = "bubbles" .. bubble[1] .. "Always"
		bubbleRows[#bubbleRows + 1] = { key = "bubble:" .. bubble[1], label = bubble[2], alwaysKey = alwaysKey,
			alwaysOn = function() return ns.GetDB()[alwaysKey] end,
			setAlways = function(value) ns.GetDB()[alwaysKey] = value end,
			alwaysTip = L["These bubbles show everywhere, in fights and out. (The other columns then have nothing to add.)"],
			apply = Changed }
	end
	stack:Continue(ShowTable(content, bubbleHeader, bubbleRows, L["Chat bubbles"]), "label")

	-- Custom bubbles: ones Cinematic draws itself, looking like the game's.
	-- Speech from behind you (Speech.lua): says and yells with no bubble on
	-- screen, shown low on the screen. Keep bubbles on screen (Bubbles.lua):
	-- retail's drawn again below the bar, classic's moved.
	stack:Header(content, L["Custom bubbles"])
	stack:Help(content, L["The game only shows a bubble over someone on your screen, and puts one from someone " ..
		"above you at the very top of the screen, under the letterbox bar. So Cinematic draws bubbles of its own, " ..
		"looking like the game's, for speech whose bubble you can't see. How they look, and where speech from " ..
		"behind you shows: the Style hub's Chat bubbles page."])
	local offScreen = stack:Add(Check(content, "chatSpeechBehind", L["Show off-screen bubbles"],
		L["Says and yells whose bubble isn't on your screen (the speaker is behind you, or out of view) show in " ..
		"a bubble low on the screen, with the speaker's name, instead of bringing up chat. It needs the Chat " ..
		"page's Show chat when a message arrives and Hide speech you can see as a bubble."]), "check")
	GreyUnless(offScreen, function(db) return db.chatPeek and db.chatHideBubbled end)
	offScreen:HookScript("OnClick", Refresh) -- (greys out / enables Show emotes too)
	-- (How they look: a button right of it, to the Style hub's Chat bubbles page.)
	local offScreenStyle = ns.PanelButton(content)
	offScreenStyle:SetSize(70, 20)
	offScreenStyle:SetText(L["Style"])
	offScreenStyle:SetPoint("LEFT", offScreen.Text or offScreen.text, "RIGHT", 16, 0)
	Tooltip(offScreenStyle, L["Opens the Style hub's Chat bubbles page: how off-screen bubbles look and where they show."])
	offScreenStyle:SetScript("OnClick", function() ns.OpenOptions("Bubble Style") end)
	local emotes = stack:Add(Check(content, "chatSpeechEmotes", L["Show emotes too"],
		L["Emotes (someone's /point, an NPC that laughs or looks around) never have a bubble: they show with " ..
		"the off-screen bubbles too, in a bubble with no tail so they don't read as speech, instead of bringing " ..
		"up chat."]), "check")
	GreyUnless(emotes, function(db) return db.chatPeek and db.chatHideBubbled and db.chatSpeechBehind end)
	stack:Add(Check(content, "bubblesOffTop", L["Keep bubbles on screen"],
		L["A bubble the game would put at the very top of the screen (someone above you, up some stairs say) " ..
		"shows a little lower instead, below the letterbox bar (or a bit down from the top with the bars off), " ..
		"where you can read it."]), "check")

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

	local subtitle = PageIntro(content, title, L["Small helpers for getting about the world. Ideas for more in the spirit of this page are " ..
		"welcome: please send them to the developer."])
	local switch = PageSwitch(content, "handleQuality", L["Enable Page"],
		L["On: everything below works as ticked. Off: none of it does, and each keeps its tick for " ..
		"when you turn this back on."], subtitle, function()
		if ns.RefreshTalentLink then ns.RefreshTalentLink() end
		if ns.RefreshTalentCalc then ns.RefreshTalentCalc() end
	end)

	local stack = Stack(switch, "check")
	-- (Campfire.lua.)
	do
		local sit = stack:Add(Check(content, "campfireSitButton", L["Campfire button"],
			L["Hovering a campfire with the cursor near the middle of the screen shows a campfire icon where " ..
			"the cursor is: click it to settle down by the fire (sit, kneel or lie down, as ticked below), " ..
			"without typing the emote. Moving the cursor off it puts it away. Not in a fight or while mounted."]), "check")
		sit:HookScript("OnClick", Refresh) -- grey out / enable the options below
		local EMOTE_TIP = L["What clicking the Campfire button does. With more than one ticked, it's one of " ..
			"them at random each time."]
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
		local NAMES_TIP = L["Words that mark a campfire when they're in the name its tooltip shows " ..
			"(\"Campfire\"), separated by commas. Use words in your game language."]
		local namesLabel = Label(content, "GameFontHighlightSmall", L["Campfire names:"])
		stack:Add(namesLabel, "label", 24)
		local names = stack:Add(ListBox(content, "campfireNames", 300, NAMES_TIP), "box", 24)
		GreyUnless(names, function(db) return db.campfireSitButton end)
		-- (Only where the game has Camp Benefits: WoW Forever.)
		if ns.HasCampBenefits and ns.HasCampBenefits() then
			local stand = stack:Add(Check(content, "campfireStandUp", L["Stand up once you get Camp Benefits"],
				L["Sitting by a Welcoming Campfire for its minute gives you Camp Benefits: as it arrives, " ..
				"you stand up again, ready to go."]), "check", 24)
			GreyUnless(stand, function(db) return db.campfireSitButton end)
		end
	end
	-- (DragEquip.lua.)
	stack:Add(Check(content, "dragEquipCharacter", L["Open the character window when dragging gear out of your bags"],
		L["Dragging something you can wear out of your bags, over the game world, opens the character window, " ..
		"so its slots are there to drop it on. Moving it between bags doesn't. Put it back without wearing it " ..
		"and the window closes again. Not in a fight."]
		.. (issecretvalue and "\n\n" .. L["Off by default on this client: opened by an addon, the window makes your player frame's health and power numbers show errors in BugSack and other error catchers. They're harmless."] or "")), "check")
	-- (TalentLink.lua; WoW Forever only.)
	if not ns.isRetail then
		stack:Add(Check(content, "talentLink", L["Talents button when inspecting someone"],
			L["Inspecting someone, a button just right of their level and class opens their talents, and one " ..
			"with their portrait on the talents window takes you back to the inspect window. Not in a fight."],
			function(value)
				ns.GetDB().talentLink = value
				if ns.RefreshTalentLink then
					ns.RefreshTalentLink()
				end
			end), "check")
		-- (TalentCalc.lua.)
		stack:Add(Check(content, "talentCalc", L["Talent calculator button on the talents window"],
			L["A button on your talents window opens a talent calculator: your class's three trees side by side, " ..
			"to plan a build without learning anything. Left-click adds a point, right-click takes one back; above " ..
			"the trees, the level the build needs and the points left. It opens in the talents window's place, " ..
			"and a button on it takes you back. It starts from the talents you have; Copy over changes puts what the plan " ..
			"adds in your talents window, to apply there. Also /cine talents."],
			function(value)
				ns.GetDB().talentCalc = value
				if ns.RefreshTalentCalc then
					ns.RefreshTalentCalc()
				end
			end), "check")
	end
	-- (CenterPanels.lua.)
	stack:Add(Check(content, "centerPanels", L["Open windows in the middle of the screen"],
		L["Windows the game opens on the left (quest log, group finder, profession book and the like) " ..
			"open on the right instead, near the top, leaving your character in view. Two open at once still sit " ..
			"side by side. Narrow ones on their own (character, trade, merchant, mail) and quest givers' windows " ..
			"open a little in from the left edge instead, halfway up the screen, leaving the world and the quest " ..
			"giver in view. A window another addon has moved stays where that addon put it."]), "check")
	stack:Add(Check(content, "dragPanels", L["Drag windows to move them"],
		L["Drag the game's windows (quest log, group finder, character, spellbook and the like) to move them. " ..
		"A window opens where you last dropped it from then on, in this profile. Some windows can't be " ..
		"moved in a fight."]), "check")
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
		L["A small icon in the bottom right of a chat window, while your mouse is over it, opens " ..
		"that window's lines as text you can select and copy with Ctrl+C."]), "check")
	local keepChat = stack:Add(Check(content, "chatHistory", L["Keep chat history"],
		L["Chat windows bring back their last 200 lines after a reload or login, for up to a day. " ..
		"Lines are saved on your computer, whispers too. Turn this off and they're deleted at your next login."]), "check")
	keepChat:HookScript("OnClick", Refresh) -- grey out / enable the option below
	local chatTime = stack:Add(Check(content, "chatHistoryTime", L["Show the time on those lines"],
		L["Lines brought back start with the time they were said. Not needed with the game's own Chat Timestamps " ..
		"on: their lines have the time already, so nothing is added."]), "check", 24)
	GreyUnless(chatTime, function(db) return db.chatHistory end)
	-- (Camera.lua.)
	local loginZoom = stack:Add(Check(content, "loginZoom", L["Reset the zoom on login and /reload"],
		L["After you log in or /reload, the camera zooms to the distance below, rather than staying " ..
		"wherever you left it."]), "check")
	loginZoom:HookScript("OnClick", Refresh) -- grey out / enable the slider below
	local loginDistance = stack:Add(Slider(content, "loginZoomDistance", L["Zoom to"], 2, 39, 0.5,
		L["%.1f yards"]), "slider", 24)
	Tooltip(loginDistance, L["The camera distance to start at. The game's furthest out may be less than this."])
	GreyUnless(loginDistance, function(db) return db.loginZoom end)
	-- (Reload.lua.)
	stack:Add(Check(content, "reloadButton", L["Reload button on the screen"],
		L["A small Reload button at the top of the screen reloads the UI in one click. It stays up with " ..
		"the UI hidden. Drag it to move it. There's a key for it too (Keybinds page)."]), "check")
	stack:Add(Check(content, "reloadKeepWindows", L["Keep windows open across a reload"],
		L["After a reload (/reload, the Reload button or its key), what you had open opens again: these " ..
		"settings at the page you were on, your bags, the character window, map, spellbook and the game's " ..
		"other windows, and Cinematic's own."]), "check")
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
			L["On: everything below works as ticked. Off: none of it does, and each keeps its tick for " ..
			"when you turn this back on."], title)
		stack = Stack(switch, "check")
		-- (Hunter.lua: Classic Era only. WoW Forever has the game's own setting.)
		if ns.isClassicEra then
			stack:Add(Check(content, "hunterRightClickShot", L["Right click attack also uses Auto-shot"],
				L["Right-clicking an enemy targets it and attacks: Auto Shot when it's far enough away to shoot, " ..
				"a melee swing when it's too close, in a fight or out of one. In a fight the game only checks " ..
				"what's under the mouse a few times a second, so a very quick right-click on a new enemy can " ..
				"still be a melee one."]), "check")
		end
		-- (HunterAmmo.lua.)
		stack:Add(Check(content, "hunterAmmoSort", L["Smallest ammo stack first after Clean Up Bags"],
			L["Clean Up Bags leaves the part stack of arrows or bullets last, but you shoot from the first stack, " ..
			"so a full one would run down and leave you with two part stacks. Once the bags are cleaned up, the " ..
			"smallest stack is moved first, to be shot first."]), "check")
		stack:Add(Check(content, "hunterQuiverFill", L["Fill quiver button at vendors"],
			L["Arrows and bullets at a vendor get a Fill button: it buys enough to fill your quiver or ammo pouch, " ..
			"topping up its part stacks and filling its empty slots, as far as your money goes. Point at it to see " ..
			"how many and the cost first."]), "check")
		-- (Pet happiness, Frames.lua. Off to start with.)
		local pet = Check(content, "petUnhappyShow", L["Show the pet frame when your pet isn't happy"],
			L["Keeps your pet frame up in CineMode, and in fights, while its happiness isn't green: " ..
			"content (yellow) or unhappy (red). It goes again once your pet is happy."])
		stack:Add(pet, "check")
		pet:HookScript("OnClick", Refresh) -- grey out / enable the option below
		local petCam = Check(content, "petUnhappyHideInCam", L["Hide in camera modes"],
			L["While a camera mode runs (AFK, auto-run, RP walk, flights and the rest), the pet frame fades " ..
			"with the rest of the UI. It comes back when the camera mode ends."])
		stack:Add(petCam, "check", 16)
		GreyUnless(petCam, function(db) return db.petUnhappyShow end)
		canvas:SetScript("OnShow", PageShown(Refresh, content))
		canvas:Hide()
		RegisterSubpage(canvas, "Hunter")
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
		L["On: right-click (or a gamepad button) casts again, and the Fishing cast bar hides, as this " ..
		"page says. Off: fishing is left to the game. (The fish camera is on the Scenes " ..
		"page.)"], subtitle)
	local stack = Stack(switch, "check")
	stack:Header(content, L["Casting"])
	stack:Add(Check(content, "hideFishingCastBar", L["Hide the Fishing cast bar"],
		L["Your cast bar stays hidden while it shows Fishing. Every other spell shows it as usual."]),
		"check")
	local recast = stack:Add(Check(content, "fishRightClickCast", L["Right-click to cast"],
		L["Works only with a fishing pole equipped. Right-clicking in the world casts Fishing: " ..
		"the first cast too, standing still, and again after each catch. Each cast still comes " ..
		"from your own click. Swap the pole out to have right-click back everywhere. While the " ..
		"bobber is out, right-click clicks it as usual (or reels in from anywhere: see below); in " ..
		"combat, with the loot window open or with your mouse on a player, NPC or object (mailbox, " ..
		"corpse, mining node...), right-click is left alone. (Meanwhile right-drag doesn't turn " ..
		"the camera: left-drag still does.)"]), "check")
	recast:HookScript("OnClick", Refresh) -- grey out / enable the options below
	-- (They apply to the gamepad button too.)
	local function IfRecast(db) return db.fishRightClickCast or (C_GamePad ~= nil and db.fishGamepadCast) end
	local delay = stack:Add(Slider(content, "fishRecastDelay", L["Wait after a cast ends"], 0, 3, 0.1,
		L["%.1f sec"]), "slider")
	Tooltip(delay, L["How long after a cast ends (a catch looted, or the bobber gone) before " ..
		"right-click casts again, so the click that loots the fish doesn't cast straight away."])
	GreyUnless(delay, IfRecast)
	local missPause = stack:Add(Slider(content, "fishMissPause", L["Pause after a missed cast"], 0, 30, 1,
		function(value) return value == 0 and L["Off"] or (L["%d sec"]):format(value) end), "slider")
	Tooltip(missPause, L["When a cast fails or doesn't land in fishable water (say, a pole left equipped " ..
		"away from water), right-click goes back to normal for this long before it casts again. " ..
		"It ends early when you cast Fishing yourself (a key or an action bar), when you catch " ..
		"something, when you stand still for 5 sec doing nothing else (no mining or picking herbs), " ..
		"or when you move 20 yards or more and then stand still for 1 sec: you're likely " ..
		"at a new spot to fish from (a few steps up to a mining node or herb don't). " ..
		"Off doesn't pause. (\"Skill not high enough\" always pauses it for 30 sec, moving or not.)"])
	GreyUnless(missPause, IfRecast)
	stack:Add(Check(content, "fishRightClickReel", L["Reel in with same key/click"],
		L["While the bobber is out, the way you cast reels it in, with no need to find the bobber " ..
		"with the mouse: right-click anywhere in the world, the key of Fishing on one of the game's " ..
		"action bars (the spell, or a macro that casts it: press 1 to cast, then 1 again to reel in), " ..
		"or in gamepad mode the cast button below. It uses the game's \"Interact with target\" key, " ..
		"so the game's soft targeting of objects is on while you fish, and your own setting comes " ..
		"back after. Reeling in before a bite ends the cast. Not in combat; right-click not with your " ..
		"mouse on a player or NPC. (While the bobber is out, right-drag doesn't turn the camera: " ..
		"left-drag still does.)"]), "check")

	-- Gamepad mode: a gamepad button does what right-click does.
	if C_GamePad then
		local padCast = stack:Add(Check(content, "fishGamepadCast", L["Gamepad: a button casts too"],
			L["In gamepad mode, the button below casts Fishing whenever right-click would: with a " ..
			"pole equipped, standing still or in the fish camera, no bobber out. The rest of the time it does what it usually does. Each cast still comes from " ..
			"your own press."]), "check")
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
		L["While your bobber is out, the game's volume goes up to the levels below, so you hear a bite " ..
		"even with the game on another screen. It goes back to your own levels a few seconds after " ..
		"your last cast ends. It never turns a volume down, and a volume you change yourself while " ..
		"fishing is kept."]), "check")
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
		L["While you fish, the game's sound keeps playing with another window in front (the game's " ..
		"Sound in Background setting), and goes back to your own setting after."]), "check", 16)
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
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title,
		L["The frames gamepad mode adds (Options, Controls, Gamepad): its action bars, the button hints " ..
		"and the reticle (the dot you aim with). As on the Game Frames page, " ..
		"each is hidden in CineMode unless ticked: Always shows it the whole time, the next three only " ..
		"while you fight or have something targeted, and the places while you're there. Rows also on the Game Frames page (the " ..
		"experience bars) follow this page in gamepad mode, and that one otherwise."])

	local rows = {}
	for _, item in ipairs(ns.COMBAT_SHOW) do
		if item.page == "gamepad" then
			rows[#rows + 1] = item
		end
	end
	local switch = PageSwitch(content, "handleGamepad", L["Enable Page"],
		L["On: CineMode fades the gamepad's bars, button hints and reticle as this page says. Off: it " ..
		"leaves them alone."], subtitle)
	rows.underHeader = true
	rows.noCine = true -- (CineMode only: Always says it all)
	local lastRow = ShowTable(content, switch, rows, "Gamepad")

	-- The prompt sits on a nameplate, not a frame of its own: a setting for
	-- the plates' fade rather than a row.
	local prompt = Check(content, "showInteractPrompt", L["Show the interact prompt (X)"],
		L["The button prompt over things you can use or talk to (your bobber, an NPC) stays up in " ..
		"CineMode while the nameplates fade, so you can see what the gamepad can reach: a bobber " ..
		"showing it can be caught. Unticked, it fades with them."])
	prompt:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", -2, -16)
	local press = Check(content, "gamepadPressReveal", L["Show the action bars when you press a button"],
		L["Gamepad mode's mouseover: pressing any gamepad button brings the action bars up. They " ..
		"stay while you hold it (not stick directions), and fade out your \"Stay after a press\" " ..
		"time after you let go. Each press starts that time again. Choose the buttons in the list below. Presses that " ..
		"make you jump don't count (whichever button jumps), nor presses while you fish (the " ..
		"fish camera on, a cast going, or looting)."])
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
	Tooltip(listToggle, L["Click to show or hide the list of buttons: untick one and pressing it " ..
		"doesn't bring the action bars up."])
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
	Tooltip(stay, L["How long the action bars stay after your last button press, or after you let go of a held button, counting their fade out."])
	GreyUnless(stay, function(db) return db.gamepadPressReveal end)
	local fadeIn = stack:Add(Slider(content, "gamepadBarsFadeIn", L["Fade in time"], 0, 3, 0.1, L["%.1f sec"]),
		"slider")
	Tooltip(fadeIn, L["How long the gamepad action bars take to fade in: for button presses, fights and " ..
		"targets alike. The rest of the UI uses the fade times on the CineMode page."])
	local fadeOut = stack:Add(Slider(content, "gamepadBarsFadeOut", L["Fade out time"], 0, 3, 0.1, L["%.1f sec"]),
		"slider")
	Tooltip(fadeOut, L["How long the gamepad action bars take to fade out."])

	stack:Header(content, L["Settings window"])
	-- (These two guard against freezes, so they work with the page off too: not greyed with it.)
	local forceReload = stack:Add(Check(content, "forceReloadOnSettingsExit", L["Force reload on Settings exit"],
		L["A workaround for a game bug: in gamepad mode, closing the Settings window after using an " ..
		"addon's settings (any addon's, not just Cinematic's) can freeze the game. With this on, once " ..
		"you've opened a Cinematic page, closing Settings (X, Close, Escape or the gamepad) reloads " ..
		"the UI instead, which closes it without the freeze. Your settings are saved first, as they are " ..
		"on every reload. Turning it off takes effect after a reload."] .. " "
		.. L["Works with this page switched off too."]), "check")
	forceReload.pageSwitch = false -- (not greyed with the switch: see SwitchOf)
	local hideButton = stack:Add(Check(content, "hideMinimapButtonGamepad", L["Hide the minimap button in gamepad mode"],
		L["Using Cinematic's minimap button in gamepad mode tends to freeze the game, like closing " ..
		"Settings does. With this on, the button is hidden while gamepad mode is on and comes back " ..
		"when it's off. Cinematic's settings are still in the game's Settings (AddOns tab), or type /cine."]
		.. " " .. L["Works with this page switched off too."],
		function(value)
			ns.GetDB().hideMinimapButtonGamepad = value
			if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		end), "check")
	hideButton.pageSwitch = false

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
	end
	-- The rows of the tabs shown (a caller can hide some), as many on each as
	-- fit (tab.row: its row's number).
	local rows
	local function Rows()
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
		Rows()
		-- (The picked one's row at the bottom, the rest above it in order.
		-- Each row up clears the picked tab's extra height.)
		local order = { tabs[picked].row }
		for r = 1, #rows do
			if r ~= tabs[picked].row then order[#order + 1] = r end
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
	end
	Show(1)
	return panel, tabs, Show, base, #rows * (TAB_H + 4)
end

-- Sub-page: which nameplates show (mobs, your faction, the other faction),
-- which stay up in cinematic mode, and how far away they show.
local function CreatePlatesPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Nameplates"])
	title:SetPoint("TOPLEFT", 16, -16)
	-- Their look: the Style hub's Nameplates, Names and Cast bars pages.
	local plateLink = ns.StyleLink(content, title, "Nameplate Style",
		L["Opens the Style hub's Nameplates page: how nameplates look."], Tooltip, L["Plate style"])
	local nameLink = ns.StyleLink(content, title, "Name Style",
		L["Opens the Style hub's Names page: how names over heads look."], Tooltip, L["Name style"], plateLink)
	ns.StyleLink(content, title, "Cast Bar Style",
		L["Opens the Style hub's Cast bars page: how nameplate cast bars look."], Tooltip, L["Cast bar style"],
		nameLink)

	local subtitle = PageIntro(content, title,
		L["Which nameplates and names stay up in CineMode: in groups, in fights and in each kind of place."])

	-- The page's master switch: off, CineMode leaves nameplates and names to
	-- the game's own options (everything below greys out).
	local handleCheck = Check(content, "handlePlates", L["Enable Page"],
		L["On: CineMode fades nameplates and names as this page says. Off: it leaves them alone, " ..
		"and the game's own options decide, in CineMode and out."],
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
		rowLabel.indentX = indent and 18 or 0 -- (what goes below lines up with the grid, not the indent)
		rowLabel:SetPoint("TOPLEFT", top, "TOPLEFT", rowLabel.indentX, y - 5)
		rowLabel:SetWidth(GRID_LABEL - 4 - ns.GRID_DOT_ROOM - rowLabel.indentX)
		rowLabel:SetJustifyH("LEFT")
		rowLabel:SetWordWrap(false)
		ns.LabelHover(content, rowLabel)
		spec.band = r
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
	local ALWAYS_TIP = L["Show everywhere, in fights and out. The rest of the row keeps its ticks for when you untick this."]
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
	local picked = { id = "Nameplates/tab", open = "Target" }
	local SECTION_WIDTH = GRID_LABEL + ns.GridWidth(PLATE_LAYOUT)
	-- (The panel's top left, under the tabs (placed once they're made, as high
	-- as their rows); the sections' frames hang on it.)
	local panelTop = CreateFrame("Frame", nil, content)
	panelTop:SetSize(1, 1)
	-- (Under the picked section's last row, at its left: the panel's bottom.)
	local foot = CreateFrame("Frame", nil, content)
	foot:SetSize(1, 1)
	local panel, ShowTab
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
		ShowTab(shown)
		local last = sections[shown].last
		foot:ClearAllPoints()
		foot:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -(last.indentX or 0), 0)
		FitContentHeight(content)
	end
	local function Pick(section)
		SectionState.Save(picked, section.key)
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
		YourTarget = L[" Your target's nameplate, whatever the Nameplates grid says. For some kinds only, name " ..
			"them in its rule (Edit): Enemy players, Hostile NPCs, Neutral players... In dungeons and raids, " ..
			"friendly targets go by Friendly plates in dungeons and raids."],
		MyPet = L[" Your pet's nameplate, whatever the Minions rows say, grouped or not."],
		GroupMembers = L[" Your party or raid members' nameplates, whatever Friendly players says. Not in dungeons " ..
			"and raids: there, Friendly plates in dungeons and raids decides."],
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
			rule = layout.edit and { key = RuleKey, label = function() return kind[2] end,
				changed = function()
					local text = ns.GetDB().frameRules[ruleKey]
					if text and text:find("%S") then ns.EnablePlateRow(kind[1]) end
				end } or nil,
			liveRule = function() return TicksRule(alwaysKey, ticks) end,
		})
	end
	for r, kind in ipairs(FRIENDLY_KINDS) do
		AddPlateRow(columnTop, r, kind)
	end
	EndSection(friendlySection, lastLabel)

	-- Friendly plates in dungeons and raids: the game won't let addons fade
	-- them there, so each kind is just on or off (see Effects). The grids
	-- have no Instances boxes for them (INSTANCE_LOCKED, AddPlateRow).
	local instanceSection = Section(L["Friendly plates in dungeons and raids"], "Instances", L["Dungeons & raids"])
	local instanceAnchor = PageIntro(instanceSection.frame, instanceSection.title,
		L["In dungeons and raids the game won't let addons fade friendly nameplates, so each kind below is " ..
		"either all on or all off there, in CineMode. The grids' friendly rows (your target's included) have no " ..
		"Instances box: these take its place.\n\nWith a friendly target: on while you have one of that kind " ..
		"targeted, out of fights. Every plate of that kind shows then, not just your target's.\n\nThe game won't " ..
		"switch nameplates on or off during a fight: they stay as the fight found them.\n\nFriendly players' " ..
		"setting covers their pets too, so with pets shown, friendly players' plates show as well."])
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
	for r, kind in ipairs(ENEMY_KINDS) do
		AddPlateRow(enemyTop, r, kind)
	end
	EndSection(enemySection, lastLabel)

	-- The parts of the plates that are up (see PlateParts), laid out the same
	-- way. Retail's plates have no level.
	local partTip = L[" In CineMode, on the nameplates that are up."]
	-- (Raid markers beyond plate range are the game's, and so is yours.)
	local markerRangeTip = L[" Beyond nameplate range (the game's nameplateMaxDistance setting: 60 yards on retail) " ..
		"the game draws raid markers over units itself, as it does over your own head, and addons can't hide them."]
	local PARTS = {
		{ "Health", L["Health bar"], L[" The health bar."] },
		{ "Name", L["Name"], L[" The name on the plate (the Names grid below is for names without a plate)."] },
		{ "CastBar", L["Cast bar"], L[" The cast bar."] },
		{ "Buffs", L["Buffs"], L[" The buffs shown on the plate."] },
		{ "Debuffs", L["Debuffs"], L[" The debuffs (and crowd control) shown on the plate."] },
		{ "RaidMarker", L["Raid marker"], L[" The raid target marker (skull, star...)."] .. markerRangeTip },
		{ "Classification", L["Elite/rare icon"], L[" The elite, rare or boss icon."] },
		{ "Level", L["Level"], L[" The level."] },
		{ "Threat", L["Threat glow"], L[" The glow while a mob has you (or is about to) as its target."] },
		{ "Highlight", L["Target highlight"], L[" The border round your target's or mouseover's plate."] },
		{ "Widgets", L["Quest/widget icons"], L[" Quest objective icons and other widgets over the plate."] },
		{ "ClassFriendly", L["Class icon (friendly)"], L[" A class icon beside friendly players' health bars."], icon = true },
		{ "ClassEnemy", L["Class icon (enemy)"], L[" A class icon beside enemy players' health bars."], icon = true },
		{ "RoleTank", L["Role icon (tank)"], L[" A role icon beside your group's tanks' health bars."], icon = true },
		{ "RoleHealer", L["Role icon (healer)"], L[" A role icon beside your group's healers' health bars."], icon = true },
		{ "RoleDamager", L["Role icon (damage)"], L[" A role icon beside your group's damage dealers' health bars."],
			icon = true },
		{ "TargetArrow", L["Target Indicator"], L[" A mark on your target's nameplate (and its name, health bar or " ..
			"border in its color), shown even while the rest of the plate is faded or shows just its name. Its " ..
			"look: the Style hub's Nameplates page."], icon = true },
	}
	-- (The class and role icons and the arrow are the addon's own: off unless
	-- ticked, outside CineMode shown only with Always ticked, and in a section
	-- of their own, Cinematic plate parts, below the game's.)
	local iconTip = L[" Off unless ticked. In CineMode, on the nameplates that are up; outside it, only with Always ticked."]
	local r
	local function PartsSection(heading, key, tab, ours)
		local section = Section(heading, key, tab)
		BeginSection(section)
		local top = TableTop(section.frame, PLATE_LAYOUT)
		r = 0
		for _, part in ipairs(PARTS) do
			if (not part.icon) == (not ours) and not (part[1] == "Level" and ns.isRetail) then
				r = r + 1
				UNIT_ROW_TIPS["Part" .. part[1]] = part[3] .. (part.icon and iconTip or partTip)
				AddPlateRow(top, r, { "Part" .. part[1], part[2] })
			end
		end
		EndSection(section, lastLabel)
		return top
	end
	local partsTop = PartsSection(L["Plate parts"], "Parts")
	local ourPartsTop = PartsSection(L["Cinematic plate parts"], "CinematicParts", L["Cinematic"], true)

	-- Names, laid out the same way. Outside cinematic mode the game's own
	-- name options decide.
	local namesSection = Section(L["Names"], "Names")
	local namesHeader = namesSection.title
	-- (A warning beside it: on faded plates the names are ours. See PlateParts.)
	local namesNote = CreateFrame("Button", nil, namesSection.frame)
	namesNote:SetSize(16, 16)
	namesNote:SetPoint("LEFT", namesHeader, "RIGHT", 6, 0)
	local namesNoteIcon = namesNote:CreateTexture(nil, "ARTWORK")
	namesNoteIcon:SetAllPoints()
	namesNoteIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
	local namesNoteText = L["In CineMode, away from dungeons and raids, nameplates stay on (just faded), and the game takes its " ..
		"own names away from over the heads of units with a plate. So where a name is kept up over a faded " ..
		"plate, Cinematic draws it on the plate itself, made to look like the game's names: colored, and " ..
		"smaller further off. Beyond nameplate range the game's own names show, so a name can " ..
		"change a little in size or place as its unit crosses that range."] ..
		L[" Their look: the Style hub's Names page."]
	Tooltip(namesNote, namesNoteText)
	namesNote.searchNote = namesNoteText
	namesNote.searchEdges = { top = namesHeader, bottom = namesHeader, left = namesHeader, right = namesNote }
	BeginSection(namesSection)
	local namesTop = TableTop(namesSection.frame, NAME_LAYOUT)
	local nameTip = L[" Ticking any box turns these names on in the game's options. Ticking none turns them off."]
	-- (Units with plates show a kept name on theirs in CineMode: see Effects.)
	local plateNameTip = L[" In CineMode, away from dungeons and raids, the name shows on the unit's nameplate instead, with the rest of the plate hidden."]
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
	local targetGroup
	r = 0
	for _, group in ipairs(ns.NAME_GROUPS) do
		if group.rows then
			targetGroup = group
		else
			r = r + 1
			local tip = (group.tip or "") .. (group.plate and (plateNameTip .. nameTip) or nameTip)
			AddNameRow(namesTop, r, group, group.key, group.label, group.indent, tip)
		end
	end
	-- Raid markers (skull, moon...) kept up over their units as the rest of
	-- their plates fades or shows their names alone (see KeepRaidMarker).
	UNIT_ROW_TIPS.PartMarker = L[" Ticked, raid markers (skull, moon...) stay over their units in CineMode as the " ..
		"rest of their nameplates fades, or shows just their names, so your group can still see what's marked. " ..
		"Unticked, they fade with the plates (the Plate parts row decides them on the plates that are up)."]
		.. markerRangeTip
	AddPlateRow(namesTop, r + 1, { "PartMarker", L["Raid marker"] })
	-- The Service NPCs row's own settings, under the grid: whether it shows
	-- names or titles alone, and which titles it keeps (Effects, PlateGuild).
	local serviceTitle = Label(content, "GameFontNormal", L["Service NPCs"])
	serviceTitle:SetPoint("TOPLEFT", lastLabel, "BOTTOMLEFT", 0, -24)
	local serviceShowLabel = Label(content, "GameFontHighlight", L["Show"])
	serviceShowLabel:SetPoint("TOPLEFT", serviceTitle, "BOTTOMLEFT", 0, -16)
	local serviceShowTip = L["Names and titles: a service NPC's name shows on its nameplate with its title under it. " ..
		"Titles only: just its title (<Repair Vendor>) where its name would be, unless its own row (or your target's) " ..
		"shows its name too. Beyond nameplate range, and in dungeons and raids, the game shows names and titles together."]
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
	local serviceKindsLabel = Label(content, "GameFontHighlight", L["Kinds"])
	serviceKindsLabel:SetPoint("TOPLEFT", serviceShowLabel, "BOTTOMLEFT", 0, -22)
	local lastServiceKind = serviceKindsLabel
	for i, kind in ipairs(ns.SERVICE_KINDS) do
		local key = "nameService" .. kind.key
		local tip = kind.key == "Other" and L["Any other title, lore titles too (<Ranger-General of Silvermoon>)."]
			or L["NPCs whose title has one of these words in it: %s."]:format((kind.words:gsub(",", ", ")))
		local check = Check(content, key, kind.label, tip, function(value)
			ns.GetDB()[key] = value
			if ns.ServiceKindsChanged then ns.ServiceKindsChanged() end
			if ns.RefreshAllPlates then ns.RefreshAllPlates() end
		end)
		local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
		check:SetPoint("TOPLEFT", serviceKindsLabel, "TOPLEFT", GRID_LABEL + 26 + column * 200, 6 - row * 26)
		if column == 0 then lastServiceKind = check end
	end
	EndSection(namesSection, lastServiceKind)

	-- Your target: its plate and its name, whatever its kind's rows say, a
	-- row each (their rules naming kinds of target where they differ). Made
	-- here, after the Names grid's rows, and laid out at the top.
	local targetSection = Section(L["Target"], "Target")
	table.insert(sections, 1, table.remove(sections))
	BeginSection(targetSection)
	local targetTop = TableTop(targetSection.frame, PLATE_LAYOUT)
	AddPlateRow(targetTop, 1, { "YourTarget", L["Nameplates"] })
	local targetNameTip = L[" Your target's name, even with its kind's names off in the Names grid. For some kinds " ..
		"only, name them in its rule (Edit): Enemy players, Hostile NPCs, Neutral players... Beyond nameplate range, " ..
		"and in dungeons and raids, the game has one setting for your target's name, which can't change in fights: " ..
		"it stays as the fight found it."] .. nameTip
	AddNameRow(targetTop, 2, targetGroup, "YourTarget", L["Names"], nil, targetNameTip)
	EndSection(targetSection, lastLabel)

	for _, top in ipairs({ targetTop, columnTop, enemyTop, partsTop, ourPartsTop, namesTop }) do
		ns.GridDots(content, top.rows or {})
	end

	-- The tabs, in order: your target's plate and name, enemy nameplates,
	-- friendly nameplates, friendly plates in dungeons and raids, their parts,
	-- then names and raid markers.
	local list, _, base, height = {}
	for i, section in ipairs(sections) do list[i] = { section.tab } end
	panel, _, ShowTab, base, height = ns.FolderTabs(content, list, function(i) Pick(sections[i]) end, nil,
		SECTION_WIDTH + 8)
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
	canvas:Hide()
	RegisterSubpage(canvas, "Nameplates", L["Nameplates"])
end

-- The Style hub's Names page: how names look on nameplates showing just the
-- name (CineMode), with a preview of them at the top. PlateParts draws them.
local function CreateNameStylePanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Names"])
	title:SetPoint("TOPLEFT", 16, -16)
	local subtitle = PageIntro(content, title,
		L["How names look on nameplates showing just the name: in CineMode, away from dungeons and raids, " ..
		"a name kept up over a faded plate is drawn by the plate. Changes show at once, here and on the " ..
		"plates around you."])

	local preview -- (below: drawn again as each setting changes)
	local function Changed()
		if ns.RefreshPlateNameStyle then ns.RefreshPlateNameStyle() end
		if preview then preview:Refresh() end
	end
	local function On(db) return db.plateNameStyle end

	-- (Its switch: names as this page says, or as the plates draw them.)
	local switch = PageSwitch(content, "plateNameStyle", L["Enable Page"],
		L["On: these names look as this page says. Off: as the nameplate draws them: white or gray " ..
		"for every unit, with a heavy black outline, growing and shrinking with distance (the preview shows " ..
		"that too). Each setting keeps its value for when you turn this back on."], subtitle, Changed)
	local stack = Stack(switch, "check")

	-- The preview: a strip of names on a dark ground, one of each colour and
	-- your own name for a friendly player, drawn as the plates would draw them.
	local SAMPLES = {
		{ text = L["Hostile"], color = { 1, 0, 0 } },
		{ text = L["Neutral"], color = { 1, 1, 0 } },
		{ text = L["Friendly NPC"], color = { 0, 1, 0 } },
		{ player = true },
	}
	local PREVIEW_W, PREVIEW_H = 480, 84
	preview = CreateFrame("Frame", nil, content)
	preview:SetSize(PREVIEW_W, PREVIEW_H)
	stack:Add(preview, "label")
	ns.StylePopout(preview, Tooltip) -- (StylePages.lua)
	ns.StyleScene(preview, 0.55, 0.8) -- (the Style pages' scene, darker under the names: StylePages.lua)
	local caption = Label(preview, "GameFontDisableSmall", L["Preview"])
	caption:SetPoint("TOPLEFT", 6, -5)
	caption.searchSkip = true
	local texts = {}
	for i in ipairs(SAMPLES) do
		local text = preview:CreateFontString(nil, "ARTWORK")
		text:SetFontObject("GameFontNormal")
		text.searchSkip = true
		texts[i] = text
	end
	-- (Spread evenly, however wide the page makes it: StylePopout.)
	local function PlaceTexts(_, width)
		for i, text in ipairs(texts) do
			text:ClearAllPoints()
			text:SetPoint("CENTER", preview, "LEFT", width * (i - 0.5) / #SAMPLES, -4)
		end
	end
	PlaceTexts(nil, PREVIEW_W)
	preview:HookScript("OnSizeChanged", PlaceTexts)
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
	function preview:Refresh()
		local db = ns.GetDB()
		local styledNames = db.plateNameStyle
		local object, file, size, flags = PlateFont()
		local _, class = UnitClass("player")
		local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		for i, sample in ipairs(SAMPLES) do
			local text = texts[i]
			-- (The plates' own colours: white, players in their class colours.)
			local r, g, b = 1, 1, 1
			local ours = styledNames and db.plateNameColour
			if sample.player then
				if ours and db.plateNameFriends == "blue" then
					r, g, b = unpack(ns.PLATE_FRIEND_COLOURS.blue)
				elseif classColor and not (ours and db.plateNameFriends == "white") then
					r, g, b = classColor.r, classColor.g, classColor.b
				end
			elseif ours then
				r, g, b = unpack(sample.color)
			end
			if styledNames then
				ns.SetPlateNameFont(text, object, file, size, db.plateNameSize,
					ns.OutlinedFlags(flags, db.plateNameOutline))
				if db.plateNameShadow then
					text:SetShadowOffset(db.plateNameShadowX, db.plateNameShadowY)
					text:SetShadowColor(0, 0, 0, db.plateNameShadowAlpha)
				else
					text:SetShadowOffset(0, 0)
				end
				text:SetAlpha(db.plateNameAlpha)
			else
				text:SetFontObject(object)
				text:SetShadowOffset(0, 0)
				text:SetAlpha(1)
			end
			text:SetTextColor(r, g, b)
			-- (Set after the font, so it takes the font's alphabet for its letters.)
			text:SetText(sample.player and (UnitName("player") or L["Friendly player"]) or sample.text)
			text:SetPoint("CENTER", preview, "LEFT", PREVIEW_W * (i - 0.5) / #SAMPLES,
				-4 + (styledNames and db.plateNameY or 0))
		end
	end
	controls[#controls + 1] = preview

	-- (The Style pages' rows, StylePages.lua: each greyed by this page's own
	-- switch, as General's doesn't reach these names.)
	local rows = ns.StyleRows(ns.lowHealthKit, content, stack, Changed, "plateNameStyle")

	-- Presets: a few looks to start from.
	local PRESETS = {
		{ L["Like the game's names"], L["Colored, no outline or shadow (the defaults)."], {} },
		{ L["Bold"], L["Colored, with a thin black outline, a little bigger."],
			{ plateNameOutline = 1, plateNameShadow = false, plateNameSize = 1.1 } },
		{ L["Subtle"], L["Colored, a little smaller and see-through."],
			{ plateNameSize = 0.9, plateNameAlpha = 0.75 } },
	}
	local PRESET_KEYS = { "plateNameColour", "plateNameFriends", "plateNameOutline", "plateNameSize",
		"plateNameAlpha", "plateNameY", "plateNameFixedSize", "plateNameShadow", "plateNameShadowX",
		"plateNameShadowY", "plateNameShadowAlpha", "plateNameCloseSize", "plateNameCloseY", "plateNameFarSize",
		"plateNameFarY" }
	-- (The Style pages' Preset: row, greyed by this page's switch alone;
	-- Custom while none matches, and picking it puts back your own settings
	-- from before a preset, as rows.PresetMenu's.)
	local function PresetValue(preset, key)
		local value = preset[3][key]
		if value == nil then value = ns.DEFAULTS[key] end
		return value
	end
	local KEPT_ID = "plateNameStyle:" .. PRESET_KEYS[1]
	local function Kept()
		local db = ns.GetDB()
		return db and db.presetCustom and db.presetCustom[KEPT_ID]
	end
	local presetField
	presetField = {
		get = function()
			local db = ns.GetDB()
			if not (db and db.plateNameStyle) then return "custom" end
			for i, preset in ipairs(PRESETS) do
				local match = true
				for _, key in ipairs(PRESET_KEYS) do
					if db[key] ~= PresetValue(preset, key) then match = false break end
				end
				if match then return i end
			end
			return "custom"
		end,
		set = function(i)
			local db = ns.GetDB()
			if i == "custom" then
				local kept = Kept()
				if not kept then return end
				db.plateNameStyle = true
				for _, key in ipairs(PRESET_KEYS) do
					if kept[key] ~= nil then db[key] = kept[key] end
				end
				return
			end
			local preset = PRESETS[i]
			if not preset then return end
			if presetField.get() == "custom" then
				local kept = {}
				for _, key in ipairs(PRESET_KEYS) do kept[key] = db[key] end
				db.presetCustom = db.presetCustom or {}
				db.presetCustom[KEPT_ID] = kept
			end
			db.plateNameStyle = true
			for _, key in ipairs(PRESET_KEYS) do db[key] = PresetValue(preset, key) end
		end,
	}
	rows.Dropdown(L["Preset:"], presetField, function()
		local list = {}
		for i, preset in ipairs(PRESETS) do list[i] = { value = i, text = preset[1], tip = preset[2] } end
		list[#list + 1] = { value = "custom", text = L["Custom"],
			tip = L["Your own settings, as they were before you picked a preset."],
			enabled = function() return Kept() ~= nil end }
		return list
	end, L["A whole look in one pick. Changing a setting after it shows Custom; picking Custom puts back " ..
		"your own settings from before the preset."], On)

	stack:Header(content, L["Text"])
	rows.Look(L["Look:"], L["Names"], {
		textColor = function(look)
			look.Check("plateNameColour", L["Color by how the unit sees you"],
				L["Red for hostile units, yellow for neutral ones and green for friendly ones, as over their heads. " ..
				"Unticked: the plate's own color, white or gray."], On)
			look.Choices(L["Friendly players:"], "plateNameFriends", {
				{ "blue", L["Blue"], L["Blue, as the game's names over their heads (green while they're PvP flagged, " ..
					"as there too)."] },
				{ "class", L["Class colors"], L["Their class's color, as the plates draw them."] },
				{ "white", L["White"], nil },
			}, function(db) return db.plateNameStyle and db.plateNameColour end)
		end,
		outline = function(look)
			look.Choices(L["Outline:"], "plateNameOutline", {
				{ 0, L["None"], L["No border around the letters, like the game's names over heads."] },
				{ 1, L["Thin"], L["A thin black border around the letters."] },
				{ 2, L["Thick"], L["A thick black border around the letters."] },
			}, On)
		end,
		shadow = function(look)
			local shadow = look.Check("plateNameShadow", L["Shadow"], L["A dark copy of the letters just behind " ..
				"them, to lift them off the world."], On)
			local function Shadowed(db) return On(db) and db.plateNameShadow end
			local boxes = look.Boxes(shadow)
			boxes:Box(L["X"], "plateNameShadowX", -4, 4, 1, "%d", 1, L["How far right of the letters it falls " ..
				"(left, below 0)."], Shadowed)
			boxes:Box(L["Y"], "plateNameShadowY", -4, 4, 1, "%d", 1, L["How far above the letters it falls " ..
				"(below, below 0)."], Shadowed)
			boxes:Box(L["Opacity"], "plateNameShadowAlpha", 0, 100, 5, "%d", 100, L["How dark the shadow is."],
				Shadowed, "%")
		end,
		outlineColor = false, -- (the game's outline is always black)
	})

	-- Size and height by distance. Retail's plates scale themselves: one of
	-- each. WoW Forever's don't, so names are sized and placed by the camera's
	-- zoom (PlateParts' Look): set at two points, close and far, following
	-- perspective between them and on past far. The camera's distance
	-- now shows under them, to set each with the camera there. (Sizes and
	-- the like as small boxes on a line, as the other Style pages'.)
	local function HideDelayBox(boxes)
		boxes:Box(L["Hide delay"], "plateNameHideDelay", 0, 10, 0.1, "%.1f", 1,
			L["How long a unit has to stay out of sight before its name hides, so a short gap like the edge " ..
			"of a stair doesn't take it away. 0: at once."], On, L["sec"])
		boxes:Box(L["Fade time"], "plateNameFadeTime", 0, 5, 0.1, "%.1f", 1,
			L["How long a name takes to fade out as its unit leaves sight, and in as it comes into sight. " ..
			"0: at once."], On, L["sec"])
	end
	if ns.isRetail then
		local sizes = rows.Boxes()
		sizes:Box(L["Size"], "plateNameSize", 50, 200, 5, "%d", 100,
			L["How big the names are, next to the plates' own."], On, "%")
		sizes:Box(L["Raise"], "plateNameY", -30, 30, 1, "%d", 1,
			L["Moves the names up (or down, below 0) from where the plates put them."], On)
		sizes:Box(L["Opacity"], "plateNameAlpha", 20, 100, 5, "%d", 100,
			L["How see-through the names are, on top of their fades."], On, "%")
		HideDelayBox(sizes)
		rows.Check("plateNameFixedSize", L["Same size at any distance"],
			L["One size at any distance. Unticked, a name grows and shrinks with its plate as its unit comes " ..
			"nearer or goes."], On)
	else
		local fades = rows.Boxes()
		fades:Box(L["Opacity"], "plateNameAlpha", 20, 100, 5, "%d", 100,
			L["How see-through the names are, on top of their fades."], On, "%")
		HideDelayBox(fades)
		stack:Header(content, L["Close (camera zoomed all the way in)"])
		local close = rows.Boxes()
		close:Box(L["Size"], "plateNameCloseSize", 50, 300, 5, "%d", 100,
			L["How big names are with the camera zoomed all the way in, next to the plates' own. Zooming " ..
			"out, they shrink toward the Far size."], On, "%")
		close:Box(L["Raise"], "plateNameCloseY", -40, 60, 1, "%d", 1,
			L["Moves names up (or down, below 0) from where the plates put them, with the camera zoomed " ..
			"all the way in."], On)
		stack:Header(content, L["Far (camera about 34 yards from you)"])
		local far = rows.Boxes()
		far:Box(L["Size"], "plateNameFarSize", 20, 100, 5, "%d", 100,
			L["How big names are with the camera about 34 yards from you. Further out, they keep shrinking."],
			On, "%")
		far:Box(L["Raise"], "plateNameFarY", -60, 10, 1, "%d", 1,
			L["Moves names up (or down, below 0) with the camera about 34 yards from you, as the game's " ..
			"names over heads sit closer to the head further off."], On)
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
	RegisterSubpage(canvas, "Name Style", "Name Style")
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
		{ "aggro", L["Aggro on you"], L["Any enemy attacking you (you have its aggro). Above the Target row, " ..
			"or that one wins on your target. A cell set to Your target's takes the Target row's; change it to " ..
			"set this one apart."] },
		{ "target", L["Target"], L["Your target."] },
		{ "focus", L["Focus"], L["Your focus."] },
		{ "mouseover", L["Mouseover"], L["The unit under the mouse. " ..
			"Hovering a unit itself works too, not just its plate. Just the marks over the plate: the others " ..
			"hang in the air where its plate is hidden."] },
		{ "others", L["Default"], L["Every other plate, when no row above fits it: the game's own look " ..
			"to start with (no mark, its own colors). Give it a mark or an Also color to change them all."] },
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
	local OTHERS_STYLES = MARK_STYLES
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
	local SHOW_X, PREVIEW_X, NAME_X, CHIPS_X = 16, 44, 92, 290
	local ROW_W, NAME_W, CHIPS_W, NUMBER_W = 590, 192, 228, 22
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

		local title = Label(content, "GameFontNormalLarge", L["Nameplates"])
		title:SetPoint("TOPLEFT", 16, -16)
		local subtitle = PageIntro(content, title,
			L["How your target, focus and the unit under the mouse stand out on the nameplates, for when no " ..
			"target frame shows them: a mark on each one's plate, a row for each in the grid, and its name, " ..
			"health bar or border in its mark's color (the row's Also color). When they show is the Target Indicator row's, on " ..
			"the Nameplates page's Cinematic plate parts grid. Changes show at once, here and on the plates."])

		local preview -- (below: drawn again as each setting changes)
		local function Changed()
			if ns.RefreshTargetArrows then ns.RefreshTargetArrows() end
			if preview then preview:Refresh() end
		end
		-- (Its switch: the marks and their colors on the plates, or none at all.)
		local switch = PageSwitch(content, "handlePlateStyle", L["Enable Page"],
			L["On: the marks and colors on this page show on the plates, when the Nameplates page's Target " ..
			"Indicator row says. Off: none of them do. Each setting keeps its value for when you turn this " ..
			"back on."], subtitle, Changed)
		local stack = Stack(switch, "check")

		-- The preview: one plate, large, with the look of the row last picked
		-- (clicked, or added; Default to start with): its mark, its name and
		-- health bar in their colors or its Also color's, the game's border
		-- round your target's bar, at its opacity.
		local previewed = "others"
		preview = CreateFrame("Frame", nil, content)
		preview:SetSize(560, 160)
		stack:Add(preview, "label")
		ns.StylePopout(preview, Tooltip) -- (StylePages.lua)
		ns.StyleScene(preview, 0.55, 0.8) -- (the Style pages' scene, darker under the plate: StylePages.lua)
		local caption = Label(preview, "GameFontNormal", "")
		caption:SetPoint("TOPLEFT", 8, -7)
		caption.searchSkip = true
		local holder = CreateFrame("Frame", nil, preview)
		holder:SetSize(240, 80)
		holder:SetScale(1.6)
		holder:SetPoint("CENTER", preview, "CENTER", 0, -6)
		local bar = CreateFrame("Frame", nil, holder)
		bar:SetSize(150, 11)
		bar:SetPoint("CENTER", holder, "CENTER", 0, -6)
		bar:SetFrameLevel(holder:GetFrameLevel() + 2)
		local barEdge = bar:CreateTexture(nil, "BORDER")
		barEdge:SetPoint("TOPLEFT", -1, 1)
		barEdge:SetPoint("BOTTOMRIGHT", 1, -1)
		barEdge:SetColorTexture(0, 0, 0, 1)
		-- (The health left, from the left; the lost part dark in its color.)
		local barBack = bar:CreateTexture(nil, "ARTWORK", nil, -1)
		barBack:SetAllPoints()
		local barFill = bar:CreateTexture(nil, "ARTWORK")
		barFill:SetPoint("TOPLEFT")
		barFill:SetPoint("BOTTOMLEFT")
		local function BarColour(r, g, b)
			barFill:SetColorTexture(r, g, b, 1)
			barBack:SetColorTexture(r * 0.25, g * 0.25, b * 0.25, 1)
		end
		-- (The game's border round your target's bar: 2 pixels, just outside its black edge.)
		local border = {}
		for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local edge = bar:CreateTexture(nil, "BORDER", nil, 1)
			if side == "TOP" or side == "BOTTOM" then
				edge:SetPoint(side .. "LEFT", barEdge, side .. "LEFT", -2, side == "TOP" and 2 or -2)
				edge:SetPoint(side .. "RIGHT", barEdge, side .. "RIGHT", 2, side == "TOP" and 2 or -2)
				edge:SetHeight(2)
			else
				edge:SetPoint("TOP" .. side, barEdge, "TOP" .. side, side == "LEFT" and -2 or 2, 0)
				edge:SetPoint("BOTTOM" .. side, barEdge, "BOTTOM" .. side, side == "LEFT" and -2 or 2, 0)
				edge:SetWidth(2)
			end
			border[#border + 1] = edge
		end
		local unitName = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		unitName:SetPoint("BOTTOM", bar, "TOP", 0, 3)
		unitName.searchSkip = true
		-- (The rest of a plate, just for the look: your debuffs over its name,
		-- a buff of its own at their right, and a cast under its bar.)
		local function AuraIcon(icon, size)
			local frame = CreateFrame("Frame", nil, bar)
			frame:SetSize(size, size)
			local edge = frame:CreateTexture(nil, "BACKGROUND")
			edge:SetPoint("TOPLEFT", -1, 1)
			edge:SetPoint("BOTTOMRIGHT", 1, -1)
			edge:SetColorTexture(0, 0, 0, 1)
			local art = frame:CreateTexture(nil, "ARTWORK")
			art:SetAllPoints()
			art:SetTexture("Interface\\Icons\\" .. icon)
			art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			return frame
		end
		local DEBUFF_ICONS = { "Spell_Shadow_ShadowWordPain", "Spell_Fire_Immolation", "Spell_Nature_Slow",
			"Spell_Frost_FrostNova", "Spell_Shadow_CurseOfTounges" }
		for i, icon in ipairs(DEBUFF_ICONS) do
			AuraIcon(icon, 13):SetPoint("BOTTOMLEFT", bar, "TOPLEFT", (i - 1) * 15, 16)
		end
		AuraIcon("Spell_Holy_PowerWordShield", 13):SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 16)
		local cast = CreateFrame("Frame", nil, bar)
		cast:SetSize(150, 7)
		cast:SetPoint("TOP", bar, "BOTTOM", 0, -3)
		local castEdge = cast:CreateTexture(nil, "BACKGROUND")
		castEdge:SetPoint("TOPLEFT", -1, 1)
		castEdge:SetPoint("BOTTOMRIGHT", 1, -1)
		castEdge:SetColorTexture(0, 0, 0, 1)
		local castBack = cast:CreateTexture(nil, "BORDER")
		castBack:SetAllPoints()
		castBack:SetColorTexture(0.2, 0.2, 0.2, 1)
		local castFill = cast:CreateTexture(nil, "ARTWORK")
		castFill:SetPoint("TOPLEFT")
		castFill:SetPoint("BOTTOMLEFT")
		castFill:SetWidth(150 * 0.4)
		castFill:SetColorTexture(1, 0.7, 0, 1)
		local castIcon = cast:CreateTexture(nil, "ARTWORK")
		castIcon:SetSize(10, 10)
		castIcon:SetPoint("TOPLEFT", cast, "BOTTOMLEFT", 0, -2)
		castIcon:SetTexture("Interface\\Icons\\Spell_Fire_FlameBolt")
		castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local spellName = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		spellName:SetPoint("LEFT", castIcon, "RIGHT", 3, 0)
		spellName:SetText(L["Spell Name"])
		spellName.searchSkip = true
		-- (The unit shown: red for enemies, yellow neutral, green friends;
		-- players and minions named as such.)
		local WHO_COLORS = { Enemy = { 1, 0.2, 0.2, 0.75, 0.1, 0.1 }, Neutral = { 1, 1, 0, 0.85, 0.75, 0 },
			Friendly = { 0.1, 1, 0.1, 0, 0.6, 0.1 } }
		local PREVIEW_NAMES = { players = L["Player"], minions = L["Minion"], elite = L["Elite NPC"] }
		-- Picks a row to preview (one taken off: back to Default).
		function preview:Pick(id)
			previewed = id or "others"
			self:Refresh()
		end
		function preview:Refresh()
			if not ns.MakeTargetArrow then return end
			local onGrid = previewed == "others"
			for _, id in ipairs(ns.TargetMarkOrder()) do onGrid = onGrid or id == previewed end
			if not onGrid then previewed = "others" end
			local kind = previewed
			local base, reaction = ns.MarkRowBase(kind)
			local info = self.RowInfo and self.RowInfo(kind)
			caption:SetText((L["Previewing - %s"]):format(info and info.full or L["Default"]))
			local shown = ns.TargetMarkSetting("Show", kind) and true or false
			self.arrow = self.arrow or ns.MakeTargetArrow(holder, bar)
			ns.StyleTargetArrow(self.arrow, nil, kind)
			self.arrow:SetShown(shown and ns.TargetMarkSetting("Style", kind) ~= "none")
			self.arrow:SetAlpha(ns.TargetMarkSetting("Opacity", kind) or 1)
			local colors = WHO_COLORS[(reaction or ""):match("^%u%l+") or ""] or WHO_COLORS.Enemy
			local tintKind = ns.TargetMarkTintKind(kind)
			local r, g, b = ns.TargetPlateColour(nil, tintKind)
			if shown and ns.TargetMarkAlso("ColorName", tintKind) then
				unitName:SetTextColor(r, g, b)
			else
				unitName:SetTextColor(colors[1], colors[2], colors[3])
			end
			if shown and ns.TargetMarkAlso("ColorBar", tintKind) then
				BarColour(r, g, b)
			else
				BarColour(colors[4], colors[5], colors[6])
			end
			-- (The border: your target's own, white unless its Also color takes it.)
			local targeted = base == "target" or base == "aggro"
			for _, edge in ipairs(border) do
				edge:SetShown(targeted)
				if shown and ns.TargetMarkAlso("ColorBorder", tintKind) then
					edge:SetColorTexture(r, g, b, 1)
				else
					edge:SetColorTexture(1, 1, 1, 1)
				end
			end
			-- (A mix of units: named as its first.)
			local first = ({ n = "npc", e = "elite", p = "players", m = "minions" })
				[base:match("^u(%l)") or ""]
			unitName:SetText(PREVIEW_NAMES[first or base] or L["Unit Name"])
			-- (The cast bar at the Cast bars page's size.)
			local castLook = ns.PlateCastLook and ns.PlateCastLook()
			local castWidth = castLook and castLook.plateCastWidth or 1
			cast:SetSize(150 * castWidth, 7 * (castLook and castLook.plateCastHeight or 1))
			castFill:SetWidth(150 * castWidth * 0.4)
			-- (Its opacity and health bar's size, on retail: Forever's plates
			-- don't change size; moved to by the OnUpdate below, as plates do.)
			local goal = self.goal
			goal.alpha = shown and (ns.TargetMarkSetting("Alpha", kind) or 1) or 0.35
			local sized = shown and ns.isRetail
			local db = ns.GetDB()
			goal.width = (sized and ns.TargetMarkSetting("PlateWidth", kind) or 1)
				* (ns.isRetail and db.plateStyleWidth or 1)
			goal.height = (sized and ns.TargetMarkSetting("PlateHeight", kind) or 1)
				* (ns.isRetail and db.plateStyleHeight or 1)
			-- (db.plateStyle*: filled from DEFAULTS at load, 1 for none.)
		end
		-- Moving like a plate in a fight: its health dropping in hits and
		-- filling again, the cast filling over and over, and its opacity and
		-- size going to a newly picked row's in the Change time
		-- (plateStyleFadeTime), as PlateParts' easer moves them. The mark bobs
		-- on its own (StyleTargetArrow). Each frame while the page shows.
		preview.goal = { alpha = 1, width = 1, height = 1 }
		local now = { alpha = 1, width = 1, height = 1 }
		local HEALTH_TIME, CAST_TIME = 9, 3
		local started, health = GetTime(), 1
		-- (The health for a time in the loop: full, five hits, a pause, filled again.)
		local function HealthAt(t)
			if t < 1.5 then return 1 end
			if t < 4.5 then return 1 - 0.13 * (math.floor((t - 1.5) / 0.6) + 1) end
			if t < 6 then return 0.35 end
			return math.min(1, 0.35 + (t - 6) / 2 * 0.65)
		end
		-- (Shown again: at its row's look at once, as a plate just come.)
		-- (Hooked: StylePopout's own OnShow fits it to the page's width.)
		preview:HookScript("OnShow", function(self) self.snap = true end)
		preview.snap = true
		ns.SetOnUpdate(preview, function(self, elapsed)
			local time = ns.GetDB().plateStyleFadeTime or 1.5
			for what, goal in pairs(self.goal) do
				now[what] = self.snap and goal or ns.Approach(now[what], goal, elapsed, time)
			end
			self.snap = nil
			holder:SetAlpha(now.alpha)
			bar:SetSize(150 * now.width, 11 * now.height)
			local t = GetTime() - started
			health = ns.Approach(health, HealthAt(t % HEALTH_TIME), elapsed, 0.25)
			barFill:SetWidth(math.max(0.01, bar:GetWidth() * health))
			castFill:SetWidth(math.max(0.01, cast:GetWidth() * math.min(1, t % CAST_TIME / (CAST_TIME - 0.5))))
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

		-- The grid: a line for each row in the order a plate tries them, its
		-- mark's preview, name and what's set apart from the usual (chips);
		-- its settings in a drawer under it, opened by clicking the line.
		stack:Header(content, L["Marks"])
		stack:Help(content, L["A plate takes its whole look (mark, colors, opacity) from the first row that " ..
			"fits it, top to bottom; the rows below aren't looked at. Click a row to open its settings: its " ..
			"mark, the plate's colors and opacity, and When it fits. The chips beside its name show what's set " ..
			"apart from the usual. Move a row with its arrows, copy it with its two squares, take it off with its x. " ..
			"Add row puts a new one at " ..
			"the end; its Row line says what it's for: a Kind, for Aggro and Units which of them, Who for just its " ..
			"enemies, neutral units or friends, and Distance for just those within or past 11, 28 or 40 yards (Any " ..
			"unit past 40 yards fades far plates). The same kind again is another row of it (Target (2)), say with " ..
			"a different When for raids. Put a " ..
			"row for just some units above its kind's own row, so it comes first for them. Default, always " ..
			"last, is for plates no row fits: the game's look unless you change it."])
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
			{ "aggroother", L["Aggro on not you"], L["Any enemy in a fight attacking someone friendly other " ..
				"than you: a group member, a pet or another player. For a tank, the ones to pick up."] },
			{ "aggrononank", L["Aggro on non-tank"], L["Any enemy attacking a player who isn't a tank (you too, " ..
				"unless you're one): for a healer, who's in trouble; for a tank, the ones to taunt. A pet tanking " ..
				"doesn't count."] },
			{ "aggrohealer", L["Aggro on a healer"], L["Any enemy attacking a healer (you too, if you're " ..
				"one): for a healer, who's after you or the other healers; for a tank, the ones to pull off them."] },
			{ "tapped", L["Not your kill"], L["An NPC someone outside your group hit first: killing it gives you " ..
				"no loot, experience or quest credit. Its name and health bar gray to start with."] },
			{ "npc", L["Normal NPC"], L["Living NPCs that aren't elite, rare elite or a boss (minor critters " ..
				"too). Normal NPC - Enemy starts faded to 40% while an elite enemy is within about 28 yards (its " ..
				"When rule: elite28), so in a pull the elites stand out."] },
			{ "elite", L["Elite NPC"], L["Living elite, rare elite and boss NPCs."] },
			{ "npcs", L["NPC"], L["Any living NPC, normal or elite."] },
			{ "players", L["Players"], L["Players, friendly or enemy as the Nameplates page has them (the other " ..
				"faction's are enemies)."] },
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
			OutOfRange = L["Out of range"] }
		local DISTANCE_SHORT = { In11 = L["in 11 yd"], In28 = L["in 28 yd"], In40 = L["in 40 yd"],
			Past28 = L["past 28 yd"], Past40 = L["past 40 yd"], OutOfRange = L["out of range"] }
		local DISTANCE_TIP = L["This row: just those about that far from you. 11 and 28 yards are the " ..
			"game's interact distances; 40 asks a 40-yard spell on your action bars (harmful for enemies, " ..
			"helpful for friends), and with none there the row fits no unit past 28 yards. Out of range: " ..
			"none of the spells on your action bars reaches it (attacks for enemies, helpful spells for " ..
			"friends), as their buttons turn red."]
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
				kind = { base, AggroName(ns.MARK_AGGRO_FLAGS[base]), L["Any enemy in a fight attacking whoever " ..
					"its ticks say: you or someone friendly other than you, and their role (no role set counts as " ..
					"DPS; a pet only with all three roles ticked)."] }
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
					.. (distance and " " .. DISTANCE_TIP or "") }
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
		-- what (fade: an opacity; when: its When; nil: the rest) }. Nothing at
		-- 100%, normal size, no Also color and When on Always.
		local function RowChips(kind)
			local db, list = ns.GetDB(), {}
			local alpha = ns.TargetMarkSetting("Alpha", kind) or 1
			if alpha < 1 then
				list[#list + 1] = { ("%d%%"):format(alpha * 100 + 0.5), "fade" }
			end
			local key = kind .. "When"
			local rule = db.frameRules and db.frameRules[key]
			if type(rule) == "string" and rule:find("%S") then
				list[#list + 1] = { rule, "when" }
			elseif not db[key] then
				local ticked = {}
				for _, word in ipairs(ns.MARK_WHEN_WORDS) do
					if db[key .. word[2]] then ticked[#ticked + 1] = WHEN_NAMES[word[1]] end
				end
				list[#list + 1] = { #ticked == 0 and L["Never"] or #ticked == 1 and ticked[1]
					or ticked[1] .. " +" .. (#ticked - 1), "when" }
			end
			if ns.MarkRowBase(kind) == "aggro" and ns.TargetMarkOwn("AlsoSame", kind) then
				list[#list + 1] = { L["Your target's"] }
			else
				local parts = {}
				for _, part in ipairs(ALSO_PARTS) do
					if ns.TargetMarkAlso("Color" .. part[1], kind) then parts[#parts + 1] = ALSO_SHORT[part[1]] end
				end
				if #parts > 0 then list[#list + 1] = { table.concat(parts, ", ") } end
			end
			local size = ns.TargetMarkSetting("Size", kind) or 1
			if math.abs(size - 1) > 0.001 and ns.TargetMarkSetting("Style", kind) ~= "none" then
				list[#list + 1] = { (L["Size %d%%"]):format(size * 100 + 0.5) }
			end
			local markAlpha = ns.TargetMarkSetting("Opacity", kind) or 1
			if markAlpha < 1 and ns.TargetMarkSetting("Style", kind) ~= "none" then
				list[#list + 1] = { (L["Mark %d%%"]):format(markAlpha * 100 + 0.5), "fade" }
			end
			local width = ns.TargetMarkSetting("PlateWidth", kind) or 1
			local height = ns.TargetMarkSetting("PlateHeight", kind) or 1
			if ns.isRetail and math.abs(width - height) > 0.001 then
				list[#list + 1] = { (L["Plate size %d%% x %d%%"]):format(width * 100 + 0.5, height * 100 + 0.5) }
			elseif ns.isRetail and math.abs(width - 1) > 0.001 then
				list[#list + 1] = { (L["Plate size %d%%"]):format(width * 100 + 0.5) }
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
		RecordKey(content, "markOrder")
		-- (Right-click: folds or opens it, the preview left on its pick.)
		local function Toggle(id, button)
			opened[id] = not opened[id]
			grid:Refresh()
			if button ~= "RightButton" then preview:Pick(id) end
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
			Tooltip(kindPick, L["The kind of plate the row is for: your target, focus or the unit under the " ..
				"mouse; Aggro, enemies by who they're attacking; Units, by what they are; or Default, every other plate."])
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
			Tooltip(typePick, L["Which of them, ticks. Aggro: who the enemy's attacking, You or Not you (someone " ..
				"friendly: a group member, a pet or another player), and their role, Tank, Healer or DPS (no role " ..
				"set counts as DPS; a pet only with all three ticked). Units: any of Normal NPC, Elite NPC (elite, " ..
				"rare elite and bosses), Players, and Minions (their pets, totems and guardians); all four, any unit."])
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
			Tooltip(distancePick, L["Any distance: all of them, near or far. Within or past 11, 28 or 40 yards: just " ..
				"those that far from you, say Any unit past 40 yards to fade the plates far off. 40 yards asks a " ..
				"40-yard spell on your action bars; with none there, the row fits no unit past 28 yards. Out of " ..
				"range: none of the spells on your action bars reaches them, as their buttons turn red."])
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

			-- Its mark's preview: a plate in small (its bar, in its Also
			-- color's color if it takes one), the mark on it, at its opacity.
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
			preview.Refresh = function()
				if not ns.MakeTargetArrow then return end
				local shown = Shown()
				preview.arrow = preview.arrow or ns.MakeTargetArrow(holder, bar)
				ns.StyleTargetArrow(preview.arrow, nil, kind)
				preview.arrow:SetShown(shown and ns.TargetMarkSetting("Style", kind) ~= "none")
				preview.arrow:SetAlpha(ns.TargetMarkSetting("Opacity", kind) or 1)
				local tintKind = ns.TargetMarkTintKind(kind)
				if shown and ns.TargetMarkAlso("ColorBar", tintKind) then
					local r, g, b = ns.TargetPlateColour(nil, tintKind)
					barFill:SetColorTexture(r, g, b, 1)
				else
					barFill:SetColorTexture(0.6, 0.12, 0.12, 1)
				end
				holder:SetAlpha(shown and (ns.TargetMarkSetting("Alpha", kind) or 1) or 0.3)
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

			-- The chips: what's set apart from the usual, in order, as many as
			-- fit (hovering the row lists them all).
			local chips = Place(CreateFrame("Frame", nil, row), CHIPS_X)
			chips:SetSize(CHIPS_W, 16)
			chips.searchSkip = true
			chips.pool = {}
			chips.Refresh = function()
				local list = RowChips(kind)
				row.chipList = list
				local x, shownChips = 0, 0
				for i, info2 in ipairs(list) do
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
					chip.text:SetText(info2[1])
					local width = math.ceil(chip.text:GetStringWidth()) + 10
					if x + width > CHIPS_W then break end
					local c = CHIP_COLORS[info2[2] or ""] or CHIP_PLAIN
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
			row:SetScript("OnLeave", GameTooltip_Hide)

			-- Its drawer's button, and (every row but Default's own) a button
			-- to take it off.
			row.toggle = Place(CreateFrame("Button", nil, row), ROW_W - 44)
			row.toggle:SetSize(14, 14)
			row.toggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			row.toggle:SetScript("OnClick", function() Toggle(kind) end)
			Tooltip(row.toggle, L["Show or hide this row's settings."])
			if kind ~= "others" then
				-- (Copy: two squares, one over the other, drawn here.)
				local copy = Place(CreateFrame("Button", nil, row), ROW_W - 66)
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
				Tooltip(remove, L["Remove this row. Add it again under the grid."])
				remove:SetScript("OnClick", function() RemoveRow(kind) end)
			end

			-- The drawer: Name (your own), Row (its kind, Who and Distance),
			-- Mark (style, color, movement; size and opacity at the end),
			-- Plate (color and the parts it colors; size and opacity at the
			-- end) and When. Default's own no Row: it's always there. Page
			-- search finding something in it opens it (openSection).
			local LINES = { "Name", "Row", "Mark", "Plate", "When" }
			if kind == "others" then table.remove(LINES, 2) end
			local LINE_NAMES = { Row = L["Row"], Name = L["Name"], Mark = L["Mark"], Plate = L["Plate"],
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
			end

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
				Tooltip(box, tip .. " " .. L["Scroll the mouse wheel over it, or type a number and press Enter."])
				local label = Label(drawer, "GameFontHighlightSmall", name)
				label:SetPoint("RIGHT", box, "LEFT", -6, 0)
				label.searchSkip = true
				-- (The % after the box, the number alone in it.)
				local percent = Label(drawer, "GameFontHighlightSmall", "%")
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
			Tooltip(nameBox, L["A name of your own for this row, shown on the grid and the preview, say Far " ..
				"trash. Empty: its kind's name."])

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
				L["The arrow, chevron and diamond bob up and down, the brackets, carets and corners close " ..
				"in and out, the glow and underline pulse. Unticked, it holds still."], function(value)
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
			for _, choice in ipairs(PLATE_COLORS) do plateChoices[#plateChoices + 1] = choice end
			local function PlateHow()
				if sameKey and ns.TargetMarkOwn("AlsoSame", kind) then return "target" end
				return ns.TargetMarkOwn("PlateColor", kind) or "-"
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
			Tooltip(plateColor, L["The plate's color, for the parts ticked beside it. -: the next row that fits " ..
				"the plate decides (the game's if none does). The game's: the game's, whatever the rows below say. " ..
				"Mark's: the mark's color. The rest as the mark's colors."])
			GreyUnless(plateColor, Shown)
			local function Colors()
				local how = PlateHow()
				return how ~= "-" and how ~= "game" and how ~= "target"
			end
			local plateSwatch = Swatch("Plate", LABEL_W + 106,
				{ MarkKey(kind, "PlateR"), MarkKey(kind, "PlateG"), MarkKey(kind, "PlateB") }, plateKey,
				function()
					return ns.TargetMarkOwn("PlateR", kind) or 1, ns.TargetMarkOwn("PlateG", kind) or 1,
						ns.TargetMarkOwn("PlateB", kind) or 1
				end, function() return PlateHow() == "custom" end, L["Click to choose the plate's custom color."])
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
				At("Plate", partPick, LABEL_W + (plateSwatch:IsShown() and 132 or 106))
				partPick:SetShown(Colors())
			end
			controls[#controls + 1] = placer
			-- (Width and Height, W and H, the two boxes where one Size was.)
			if ns.isRetail then
				local SIZE_TIP = L["Its name, mark and the rest of the plate move with the bar's edges. Not on " ..
					"WoW Forever: its plates don't change size."]
				local _, w = PercentBox("Plate", 2, "PlateWidth", 50, 300, L["Width"],
					L["The health bar's width."] .. " " .. SIZE_TIP, DRAWER_W - 230)
				w:SetText(L["W"])
				local _, h = PercentBox("Plate", 2, "PlateHeight", 50, 300, L["Height"],
					L["The health bar's height."] .. " " .. SIZE_TIP)
				h:SetText(L["H"])
			end
			PercentBox("Plate", 1, "Alpha", 0, 100, L["Opacity"], L["The whole plate's opacity while this row fits " ..
				"it, whether it has a mark or not. CineMode's own fade comes on top."])

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
					tip = L["This row fits everywhere. The rest of the row keeps its ticks for when you untick this."] },
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
		Tooltip(add, L["Adds a row at the end of the grid, for any unit to start with, its settings open: " ..
			"pick what it's for on its Row line, and its look."])
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
		-- (On one line, small boxes: the time, and on retail every plate's
		-- Width and Height, times each row's, as theirs.)
		local allRows = stack:Add(BoxLine(content), "label")
		allRows:Box(L["Change time"], "plateStyleFadeTime", 0, 10, 0.1, "%.1f", 1,
			L["How long a plate takes to change its opacity or size a whole 100% when the row it " ..
			"goes by changes: from 100% to 15% takes a bit less. If it changes back before it's there, it turns " ..
			"back from where it is, so a quick look away from an elite and back barely shows. A plate just come " ..
			"into view starts at its row's. 0: at once."], nil, nil, L["sec"])
		if ns.isRetail then
			local MASTER_TIP = L["Every plate's, those no row fits too, times its row's own. When they show is the " ..
				"Target Indicator row's, as the rows'."]
			allRows:Box(L["Width"], "plateStyleWidth", 50, 300, 5, "%d", 100,
				L["The health bar's width."] .. " " .. MASTER_TIP, Changed, nil, "%")
			allRows:Box(L["Height"], "plateStyleHeight", 50, 300, 5, "%d", 100,
				L["The health bar's height."] .. " " .. MASTER_TIP, Changed, nil, "%")
		end
		-- (The game's Show Offscreen Nameplates in CineMode; none on a client
		-- without it.)
		if GetCVar("nameplateShowOffscreen") ~= nil then
			local offscreen = stack:Add(Check(content, "plateShowOffscreen", L["Off-screen plates in CineMode"],
				L["The game's Show Offscreen Nameplates in CineMode. Ticked: on, plates for units out of view stay, " ..
				"pinned to the edge of the screen, so rows and rules that look for plates still find them, like an " ..
				"elite behind you for the elite rules. Unticked: off in CineMode. Your own setting comes back when " ..
				"CineMode ends."]), "check")
			offscreen.searchLabel = L["Off-screen plates in CineMode"]
		end

		stack:Header(content, L["All marks"])
		-- (Two raises: on a showing plate, and with none; the marks move
		-- between them as the plate fades, as the quest mark does.)
		local marks = stack:Add(BoxLine(content), "label")
		marks:Box(L["Raise with a plate"], "targetArrowY", -40, 40, 1, "%d", 1,
			L["Moves the marks drawn over the plate (arrow, chevron, diamond) up, or down below 0, " ..
			"from just over the name, while the plate shows."], Changed)
		marks:Box(L["without a plate"], "targetArrowBareY", -40, 40, 1, "%d", 1,
			L["Moves the marks drawn over the plate up, or down below 0, from where the plate's " ..
			"middle is, while nothing of the plate shows. As the plate fades in or out, the marks move between " ..
			"the two heights."], Changed)

		canvas:SetScript("OnShow", PageShown(Refresh, content))
		canvas:Hide()
		RegisterSubpage(canvas, "Nameplate Style", L["Nameplates"])
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
		cineShow = L["Its messages show chat any time the UI is faded. (The other columns then have nothing to add.)"],
		combatShow = L["Its messages show chat in fights (while you stay cinematic in them)."],
		enemyShow = L["Its messages show chat out of combat with a living enemy targeted."],
		friendlyShow = L["Its messages show chat out of combat with anything else targeted (friends, NPCs, dead enemies)."],
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
			holder:SetPoint("TOPLEFT", chatPanel.channelBody, "TOPLEFT", 0, -(i - 1) * 24)
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

		local title = Label(chatPanel, "GameFontNormalLarge", L["Chat"])
		title:SetPoint("TOPLEFT", 16, -16)
		ns.FramesLink(chatPanel, title, "interface")

		local subtitle = PageIntro(chatPanel, title,
			L["The chat window fades with the rest of the UI in CineMode. Mousing over it or typing " ..
			"always shows it."])

		-- On top: the master switch and the peek's own options.
		local switch = PageSwitch(chatPanel, "handleChat", L["Enable Page"],
			L["On: new messages, typing, unread whispers and scrolling back bring up the chat windows as this " ..
			"page says. Off: none of them do, and the chat windows fade as their Game Frames row says."],
			subtitle)

		local chatPeek = Check(chatPanel, "chatPeek", L["Show chat when a message arrives"],
			L["While the UI is faded, a new message briefly shows just the chat window it " ..
			"arrived in. Choose which messages below, and what of the window comes up with them under Chat window."], function(value)
				ns.GetDB().chatPeek = value
				Refresh() -- grey out / enable the time and the messages below
			end)
		chatPeek:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 0, -2)
		local function IfPeek(db) return db.chatPeek end

		local peekTime = Slider(chatPanel, "chatPeekTime", L["Show chat for"], 2, 30, 1, L["%d sec"])
		peekTime:SetPoint("TOPLEFT", chatPeek, "BOTTOMLEFT", 4, -26)
		Tooltip(peekTime, L["How long chat stays up after a message arrives or after you finish typing."])
		GreyUnless(peekTime, IfPeek)

		local hideOwn = Check(chatPanel, "chatHideOwn", L["Hide your messages"],
			L["Your own messages don't show chat: your emotes (a /bow, or sitting or kneeling at the " ..
			"campfire), and what you say in /say, party, guild and so on. Other people's still do."])
		hideOwn:SetPoint("TOPLEFT", peekTime, "BOTTOMLEFT", -4, -18)
		GreyUnless(hideOwn, IfPeek)
		hideOwn:HookScript("OnClick", Refresh) -- (greys out / enables its exception)

		local ownNoBubble = Check(chatPanel, "chatOwnNoBubble", L["Except lines with no bubble"],
			L["What you type still shows chat when no chat bubble shows it: your whispers, guild lines, " ..
			"channels and so on, so you can see them sent, even where that type or channel is off below. A " ..
			"whisper to no one does too. Your emotes and lines with a bubble don't."])
		ownNoBubble:SetPoint("TOPLEFT", hideOwn, "BOTTOMLEFT", 20, -2)
		GreyUnless(ownNoBubble, function(db) return db.chatPeek and db.chatHideOwn end)

		local hideBubbled = Check(chatPanel, "chatHideBubbled", L["Hide speech you can see as a bubble"],
			L["Says and yells (people's and NPCs') don't show chat when their chat bubble shows on your " ..
			"screen: you can read it there. Ones from out of view, or where bubbles are off, still do."])
		hideBubbled:SetPoint("TOPLEFT", ownNoBubble, "BOTTOMLEFT", -20, -2)
		GreyUnless(hideBubbled, IfPeek)

		-- (Ticking it greys out / enables the Chat bubbles page's Behind you.)
		hideBubbled:HookScript("OnClick", Refresh)

		-- The sections, each a band that opens and closes with a click and its
		-- body under it (all open to start with). A setting found by search in a
		-- closed one opens it.
		local sections = {}
		local top = CreateFrame("Frame", nil, chatPanel)
		top:SetSize(1, 1)
		top:SetPoint("TOPLEFT", hideBubbled, "BOTTOMLEFT", 2, -16) -- (back to the column edge)
		local function LayoutNow()
			local above
			for _, section in ipairs(sections) do
				local frame = section.frame
				frame:ClearAllPoints()
				if above then
					frame:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -6)
				else
					frame:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 0)
				end
				frame:SetPoint("RIGHT", chatPanel, "RIGHT", -16, 0)
				SectionState.Restore(section)
				section.body:SetShown(section.open)
				section.nameRow:SetOpen(section.open)
				frame:SetHeight(BAND_HEIGHT + (section.open and (ContentDepth(section.body) or 0) + 10 or 0))
				above = frame
			end
			FitContentHeight(chatPanel)
		end
		-- (Laid out again next frame too, once the rows have settled.)
		local function Layout()
			LayoutNow()
			C_Timer.After(0, LayoutNow)
		end
		chatPanel.layoutSections = Layout
		local function Section(heading, key)
			local frame = CreateFrame("Frame", nil, chatPanel)
			frame:SetHeight(BAND_HEIGHT)
			local body = CreateFrame("Frame", nil, frame)
			body:SetPoint("TOPLEFT", 0, -BAND_HEIGHT)
			body:SetPoint("TOPRIGHT", 0, -BAND_HEIGHT)
			body:SetHeight(1)
			body.searchAlways = true
			local section = { frame = frame, body = body, open = true, id = "Chat/" .. key }
			section.nameRow = SectionBand(frame, heading, function()
				SectionState.Save(section, not section.open)
				Layout()
			end)
			function body.openSection()
				if not section.open then
					SectionState.Save(section, true)
					Layout()
				end
			end
			sections[#sections + 1] = section
			return body, section.nameRow
		end
		-- (A table's anchor: the top of its section's body.)
		local function TableTop(body)
			local anchor = CreateFrame("Frame", nil, body)
			anchor:SetSize(1, 1)
			anchor:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
			return anchor
		end

		-- Chat window: plain ticks. (Where it stays up is its row on the
		-- Standard Frames page.)
		local windowBody = Section(L["Chat window"], "Chat window")
		local untilRead = Check(windowBody, "chatUntilWhisperRead", L["Keep chat up until whispers are read"],
			L["When a whisper arrives in its own tab, the whole chat window stays up in CineMode " ..
			"while that tab flashes, until you click it. Whispers that land in the tab you're " ..
			"looking at don't flash, so they just show as above."])
		untilRead:SetPoint("TOPLEFT", windowBody, "TOPLEFT", -2, -6)
		-- What of the window a new message brings up with it (hovering,
		-- typing and unread whispers still bring it all).
		local partsLabel = Label(windowBody, "GameFontHighlight", L["A message shows"])
		partsLabel:SetPoint("TOPLEFT", untilRead, "BOTTOMLEFT", 2, -10)
		local PARTS_TIP = L["Hovering the chat, typing or a whisper to read still brings it all up."]
		for i, part in ipairs({
			{ "chatPeekBackground", L["Background"], L["The chat window's dark background comes up with a new " ..
				"message. Untick for just the lines of text."] },
			{ "chatPeekTabs", L["Tabs"], L["The chat window's tabs (General, Combat Log...) come up with a new message."] },
			{ "chatPeekButtons", L["Buttons"], L["The buttons beside the chat window (chat menu, channels, voice...) " ..
				"come up with a new message."] },
		}) do
			local check = Check(windowBody, part[1], part[2], part[3] .. " " .. PARTS_TIP)
			check:SetPoint("TOPLEFT", partsLabel, "BOTTOMLEFT", -2 + (i - 1) * 110, -4)
			GreyUnless(check, IfPeek)
		end

		-- The message types that show chat: people's, then the game's.
		local function TypeSection(heading, game)
			local body = Section(heading, game and "Game messages" or "Conversation")
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
		local conversationBody, conversationRows = TypeSection(L["Conversation"], false)
		-- Typing last, a row of its own (chatShowWhileTyping its Always; see
		-- Frames.lua): not a message, so not greyed with the peek off.
		local typing = CreateFrame("Frame", nil, conversationBody)
		typing:SetSize(1, 1)
		typing:SetPoint("TOPLEFT", conversationBody, "TOPLEFT", 0, -conversationRows * 24)
		local typingRows = MessageRows()
		typingRows.noHeadings = true
		typingRows.columnTips = nil
		typingRows[1] = { key = "chat:typing", label = L["Typing"],
			tip = L["Pressing Enter to type brings up the chat window with the input box where it's ticked. " ..
			"Elsewhere just the input box comes up, so you can type without the chat window (or Mouseover " ..
			"groups set to come up for Typing) showing."],
			alwaysTip = L["Typing brings up the chat window any time. (The other columns then have nothing to add.)"],
			alwaysOn = function() return ns.GetDB().chatShowWhileTyping end,
			setAlways = function(value) ns.GetDB().chatShowWhileTyping = value end }
		ShowTable(typing, typing, typingRows, "Chat", L["Conversation"])
		ToPage(typing)
		RecordKey(chatPanel, "chatShowWhileTyping")
		TypeSection(L["Game messages"], true)

		-- Channels the player has joined, a row each (ChannelHolder), listed
		-- again each time the page opens.
		local channelBody, channelBand = Section(L["Channels"], "Channels")
		chatPanel.channelBody = channelBody
		local headings = CreateFrame("Frame", nil, channelBody)
		headings:SetSize(1, 1)
		headings:SetPoint("TOPLEFT", channelBody, "TOPLEFT", 0, 0)
		ShowTable(headings, headings, MessageRows())
		chatPanel.channelHeadings = headings
		PageIntro(channelBand, channelBand.title,
			L["Channels you've joined, like General or Trade. The list updates each time " ..
			"you open this page."])
		chatPanel.noChannels = Label(channelBody, "GameFontDisableSmall", L["No channels joined."])
		chatPanel.noChannels:SetPoint("TOPLEFT", channelBody, "TOPLEFT", 0, -10)

		-- Other: chat lines of Cinematic's own.
		local otherBody = Section(L["Other"], "Other")
		-- (Attacks shown on the screen: the Cards page's now.)
		local attackAlert = ns.CardsLink(otherBody, L["Attacks shown on the screen:"], "attack")
		attackAlert:SetPoint("TOPLEFT", otherBody, "TOPLEFT", 0, -6)
		local updateNotice = Check(otherBody, "updateNotice", L["Get notified of updates"],
			L["The first time you log in after Cinematic updates, a line in chat says so, with a " ..
			"What's new link to what's been added. Chat shows for it while the UI is faded."] .. " "
			.. L["Works with this page switched off too."])
		updateNotice.pageSwitch = false -- (not greyed with the switch: see SwitchOf)
		updateNotice:SetPoint("TOPLEFT", attackAlert, "BOTTOMLEFT", -2, -4)

		for _, section in ipairs(sections) do
			ToPage(section.body)
		end
		-- (The Always boxes' own settings, for the page's Reset too.)
		RecordKey(chatPanel, "chatPeekTypes")
		RecordKey(chatPanel, "chatPeekChannelList")

		chatCanvas:SetScript("OnShow", PageShown(function()
			if ns.GetDB() then RefreshChannels() end
			Refresh() -- (after: new channels' rows too)
			Layout()
		end, chatPanel))
		chatCanvas:Hide()
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
	Tooltip(row.delete, L["Takes this frame off the list. A frame you added stops fading; " ..
		"one you kept up fades again if it's one the addon fades by itself."])
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
			tip = L["Show this frame the whole time in CineMode (Cinematic leaves it " ..
			"alone). Unticked, it's hidden, except as the other columns say."] },
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
			tip = tip .. "\n\n" .. L["It sits where the game's %s was, or is named like it: it takes that " ..
				"row's ticks on the Game Frames page until you give it its own."]:format(follow)
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

	local title = Label(content, "GameFontNormalLarge", L["Minimap"])
	title:SetPoint("TOPLEFT", 16, -16)
	ns.FramesLink(content, title, "minimap")

	local subtitle = PageIntro(content, title,
		L["When the minimap (and on retail the quest waypoint) stays up in CineMode. " ..
		"Hovering the minimap always shows it. To keep it up all the time, or in fights, " ..
		"see the Game Frames page."])
	local switch = PageSwitch(content, "handleMinimap", L["Enable Page"],
		L["On: this page's settings can bring the minimap up or keep it up in CineMode. Off: they don't; " ..
		"it still fades as its Game Frames rows say."], subtitle)

	-- Retail's quest waypoint (the marker in the world showing where to go).
	local aboveTracking
	if ns.OptionAvailable({ retail = true }) then
		local waypoint = Check(content, "alwaysShowWaypoint", L["Always show the quest waypoint"],
			L["Keeps the marker showing where your tracked quest or map pin is, with its " ..
			"distance, visible in CineMode. Off, it fades with the rest of the UI."])
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
		{ "minimapcoords", L["Coordinates"] },
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
		local partsLabel = Label(content, "GameFontHighlight", L["Reveal shows"])
		partsLabel:SetPoint("TOPLEFT", revealLabel, "BOTTOMLEFT", 12, -6)
		parts:SetPoint("TOPLEFT", partsLabel, "BOTTOMLEFT", -4, -4)
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
		Tooltip(parts, L["When a ping, a reveal below or Keep open's tracking brings the faded minimap up, " ..
			"only the map comes up with what's ticked here; the rest of the header stays faded. " ..
			"Hovering the minimap shows it all."])
		aboveReveal = parts
	end
	local ping = Check(content, "minimapRevealOnPing", L["Pings"],
		L["You or someone in your party or raid pinging the minimap shows it as if you'd hovered it, so " ..
		"you can see where, with the rest of the Hover groups that have Minimap ping ticked, for " ..
		"as long as the slider under it says. Ore, herbs and treasure pinged by Mark where it is don't count."], function(value)
			ns.GetDB().minimapRevealOnPing = value
			Refresh() -- grey out / enable the time below
		end)
	if aboveReveal then
		ping:SetPoint("TOPLEFT", aboveReveal, "BOTTOMLEFT", 4, -6)
	else
		ping:SetPoint("TOPLEFT", revealLabel, "BOTTOMLEFT", 12, -4)
	end
	local pingTime = Slider(content, "minimapPingTime", L["Show for"], 2, 60, 1, L["%d sec"])
	pingTime:SetPoint("TOPLEFT", ping, "BOTTOMLEFT", 4, -26)
	Tooltip(pingTime, L["How long the minimap stays up after someone pings it, before it fades."])
	GreyUnless(pingTime, function(db) return db.minimapRevealOnPing end)
	-- (What goes under the slider lines up with the checkboxes again.)
	local pingSpacer = CreateFrame("Frame", nil, content)
	pingSpacer:SetSize(1, 1)
	pingSpacer:SetPoint("TOPLEFT", pingTime, "BOTTOMLEFT", -4, -14)
	local SWEEP_NOTE = L["Cinematic looks every second or two by pointing at the minimap the way your " ..
		"mouse would (not in combat), and the minimap fades again a few seconds after it's gone. While " ..
		"any of these is ticked, the faded minimap stays in its place, invisible, instead of being " ..
		"shrunk away."]
	-- (The game not answering the sweep, NodeSweep.lua: only the quest boxes,
	-- from the quest log instead.)
	local questsOnly = not ns.CanSweepMinimap() and ns.CanRevealQuestsOnly()
	if questsOnly then
		SWEEP_NOTE = L["Cinematic checks every second or two how far that place is from you on the map."]
	end
	local function RevealKinds(list)
		if not questsOnly then return list end
		local kept = {}
		for _, kind in ipairs(list) do
			if kind[1] == "minimapRevealTurnIns" or kind[1] == "minimapRevealAreas" then kept[#kept + 1] = kind end
		end
		return kept
	end
	local previousReveal = pingSpacer
	-- (Hidden where the minimap can't be swept: retail, and Forever once the game stopped answering, NodeSweep.lua.)
	for _, kind in ipairs(RevealKinds(not (ns.CanSweepMinimap() or questsOnly) and {} or {
		{ "minimapRevealNodes", L["Nearby ore, herbs and treasure"],
			L["With Find Minerals, Find Herbs or Find Treasure on, the minimap comes up while a vein, " ..
			"herb or chest shows on it."] },
		{ "minimapRevealTurnIns", L["Quest turn-ins"],
			L["The minimap comes up while a quest of yours that's done shows on it, where you hand it in."] },
		{ "minimapRevealAreas", L["Quest areas"],
			L["The minimap comes up while the area of a quest of yours that isn't done shows on it, " ..
			"the shaded part where its objectives are."] },
		{ "minimapRevealIcons", L["Other icons"],
			L["The minimap comes up while anything else with a name shows on it: quest givers with a " ..
			"quest for you, flight masters and innkeepers you track and the like. Your group and pets " ..
			"don't count."] },
	})) do
		local check = Check(content, kind[1], kind[2], kind[3] .. " " .. SWEEP_NOTE,
			kind[1] == "minimapRevealNodes" and function(value)
				ns.GetDB().minimapRevealNodes = value
				Refresh()
			end or nil)
		check:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", -(previousReveal.revealIndent or 0),
			previousReveal.revealIndent and -6 or -2)
		previousReveal = check
		-- (Under it: how each node is marked, minimapNodeMark.)
		if kind[1] == "minimapRevealNodes" then
			local function IfNodes(db) return db.minimapRevealNodes end
			local MARK_TIP = L["How a vein, herb or chest is marked where it shows up on the minimap. " ..
				"Our mark: a ring of Cinematic's that pulses on it a few seconds, no sound, only you see it. " ..
				"Ping: the same ping as clicking the minimap, with its sound; in a group, everyone sees it."]
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
					Tooltip(icons, L["The kinds ticked here get their icon on the node, the herb's own or the vein's ore, " ..
						"kept there for as long as it's on the minimap."])
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
	end
	-- Quest givers nearby (QuestGlow.lua): NPC nameplates the game would show
	-- a quest cursor over. (Hidden on a client without SetUnitCursorTexture.)
	if ns.QuestGiversPossible and ns.QuestGiversPossible() then
		local givers = Check(content, "minimapQuestGivers", L["Quest givers nearby"],
			L["The minimap comes up while an NPC with a quest you can pick up is near you, as the game's quest " ..
			"cursor over them says (no other addon needed), and an NPC you can hand a quest in to with Quest " ..
			"turn-ins ticked. Only NPCs with their nameplate up count: turn on friendly NPC nameplates in the " ..
			"game's settings. The minimap fades again a few seconds after they're gone."])
		givers:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", -(previousReveal.revealIndent or 0),
			previousReveal.revealIndent and -6 or -2)
		previousReveal = givers
	end
	-- Use Questie DB (Support/QuestieMinimap.lua): Questie's own minimap
	-- icons reveal it too. Greyed out while Questie isn't loaded; hidden on
	-- retail, which Questie never runs on.
	if ns.QuestieMinimapPossible and ns.QuestieMinimapPossible() then
		local questie = Check(content, "minimapQuestie", L["Use Questie DB"],
			L["With Questie loaded, the minimap comes up while one of Questie's own icons for a quest you can pick " ..
			"up (its \"!\") is on it, and its turn-ins (\"?\") too with Quest turn-ins ticked. A quest giver who " ..
			"walks around counts anywhere along their route, and when their nameplate is near you. Questie's own " ..
			"settings decide which icons it shows (its level filter, for one), and only those count. Cinematic " ..
			"checks every second; the minimap fades again a few seconds after the last one is gone."] ..
			(ns.QuestieLoaded() and "" or ("\n\n" .. L["Needs Questie: it isn't loaded."])))
		questie:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", -(previousReveal.revealIndent or 0),
			previousReveal.revealIndent and -6 or -2)
		GreyUnless(questie, function() return ns.QuestieLoaded() end)
		previousReveal = questie
	end
	local onTaxi = Check(content, "minimapHideOnTaxi", L["Not on flight paths"],
		L["On a flight path the minimap stays hidden: pings, the reveals above and the tracking and zones under " ..
		"Keep open don't bring it up (you can't gather while flying), and nothing is pinged. Hovering it " ..
		"still shows it."])
	onTaxi:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", 0, -2)
	previousReveal = onTaxi


	-- Keep open: the minimap stays up the whole time.
	local keepLabel = Label(content, "GameFontHighlight", L["Keep open"])
	keepLabel:SetPoint("TOPLEFT", previousReveal, "BOTTOMLEFT", -12, -10)
	local indoors = Check(content, "minimapIndoors", L["Indoors"],
		L["Inside buildings, caves and cities like Ironforge, the minimap stays up during CineMode. " ..
		"The game stops updating the indoor map while the minimap is hidden, so after walking " ..
		"around it can come back blank or out of date for a moment. Off, it's redrawn as it comes back."])
	indoors:SetPoint("TOPLEFT", keepLabel, "BOTTOMLEFT", 12, -4)

	-- Zones you picked (minimapKeepZones, map IDs comma-separated): a row
	-- each (name, Remove), then a button to add the one you're in.
	local zonesLabel = Label(content, "GameFontHighlightSmall", L["In these zones:"])
	-- (Lined up with the checkboxes' text.)
	zonesLabel:SetPoint("TOPLEFT", indoors, "BOTTOMLEFT", 28, -4)
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
			row = CreateFrame("Frame", nil, content)
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
	Tooltip(addZone, L["In the zones listed here, the minimap stays up during CineMode: say, one where " ..
		"you do a lot of dailies. Caves and towns inside a zone count as the zone."])
	-- Rebuilt as the page shows and after each change.
	controls[#controls + 1] = { Refresh = function()
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
		L["While a quest is tracked in the quest tracker, the minimap stays up during CineMode, so you " ..
		"can see where to go. Untrack your quests and it fades again."], function(value)
			ns.GetDB().minimapKeepQuest = value
			Refresh()
		end)
	quest:SetPoint("TOPLEFT", addZone, "BOTTOMLEFT", -28, -6)
	-- (Under it: how long after picking up a quest or progress on one.)
	local questFor = Slider(content, "minimapKeepQuestFor", L["Only after progress"], 0, 10, 1,
		function(value) return value == 0 and L["Off"] or L["%d min"]:format(value) end)
	questFor:SetPoint("TOPLEFT", quest, "BOTTOMLEFT", 24, -22)
	Tooltip(questFor, L["The minimap stays up only this long after you pick up a quest or make progress " ..
		"on a tracked one, then fades until you do again. Off: it stays up the whole time a quest is tracked."])
	GreyUnless(questFor, function(db) return db.minimapKeepQuest end)
	-- (Retail: hunting your prey. Left off where the client has no prey hunts.)
	local aboveCreatures, creaturesGap = questFor, { -24, -10 }
	if ns.HasPreyHunts() then
		local prey = Check(content, "minimapKeepPrey", L["Hunting your prey"],
			L["While you're on a prey hunt, the minimap stays up during CineMode, so you can see " ..
			"the activities, world quests, rares and treasures that lure your prey out."])
		prey:SetPoint("TOPLEFT", questFor, "BOTTOMLEFT", -24, -10)
		aboveCreatures, creaturesGap = prey, { 0, -2 }
	end
	local creatures = Check(content, "minimapKeepCreatures", L["Tracking creatures or fish"],
		L["While hunter, druid or warlock creature tracking, or Find Fish, is on, the minimap stays " ..
		"up during CineMode."])
	creatures:SetPoint("TOPLEFT", aboveCreatures, "BOTTOMLEFT", creaturesGap[1], creaturesGap[2])
	local gathering = Check(content, "minimapKeepGathering", L["Tracking herbs, minerals or treasure"],
		L["While Find Herbs, Find Minerals or Find Treasure is on, the minimap stays up during CineMode, " ..
		"except in the places below."], function(value)
			ns.GetDB().minimapKeepGathering = value
			Refresh()
		end)
	gathering:SetPoint("TOPLEFT", creatures, "BOTTOMLEFT", 0, -2)
	-- Places where gathering tracking doesn't keep the minimap up, in the usual place order.
	local exceptIn = Label(content, "GameFontHighlight", L["Except in"])
	exceptIn:SetPoint("TOPLEFT", gathering, "BOTTOMLEFT", 20, -4)
	local PLACE_TIPS = {
		Cities = L["Capital cities. "],
		PvP = L["Battlegrounds and arenas (being flagged for PvP out in the world doesn't count). " ..
			"Alterac Valley's mines do have ore, so untick this if you mine there. "],
	}
	-- (In a row.)
	local PLACE_COLUMN = 120
	for i, place in ipairs(PLACES) do
		-- (PvP here is battlegrounds and arenas only, so it's named for them.)
		local label = place[1] == "PvP" and L["BGs"] or place[2]
		local check = Check(content, "trackingOffIn" .. place[1], label, (PLACE_TIPS[place[1]] or "") ..
			L["Tracking doesn't keep the minimap up here. Hovering it still shows it."])
		check:SetPoint("TOPLEFT", exceptIn, "BOTTOMLEFT", 12 + (i - 1) * PLACE_COLUMN, -4)
		GreyUnless(check, function(db) return db.minimapKeepGathering end)
	end
	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, "Minimap")
end

-- Sub-page: the quest tracker in CineMode: the quest timer, and a look at
-- the tracker when you accept a quest.
local function CreateQuestTrackerPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Quest Tracker"])
	title:SetPoint("TOPLEFT", 16, -16)
	ns.FramesLink(content, title, "interface")

	local subtitle = PageIntro(content, title,
		L["When the quest tracker comes up in CineMode. Hovering it always shows it. To keep it " ..
		"up all the time, or in fights, see the Game Frames page."])

	local reveal = Check(content, "questRevealOnAccept", L["Reveal on new quest"],
		L["Accepting a quest shows the quest tracker as if you'd hovered it (with the rest of the " ..
		"Hover groups that have Quest progress ticked): it goes after \"Stays after " ..
		"mouseover\" (Hover groups page)."])
	reveal:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -17) -- (as under the other pages' hidden switch)
	PageSwitch(content, "handleQuests", L["Enable Page"],
		L["On: this page's settings can bring the quest tracker, quest timer and durability figure up in " ..
		"CineMode. Off: they don't; they still fade as their Game Frames rows say."], subtitle)
	reveal:HookScript("OnClick", Refresh) -- grey out / enable the option below

	-- Children: each reveal can stay up for the Calm Timer instead.
	local QUEST_INDENT = 16
	local calmTip = L["The quest tracker stays up for the Calm Timer (CineMode page) instead of the " ..
		"mouseover time, if that's longer."]
	local acceptCalm = Check(content, "questAcceptCalm", L["Keep up for the Calm Timer"], calmTip)
	acceptCalm:SetPoint("TOPLEFT", reveal, "BOTTOMLEFT", QUEST_INDENT, -2)
	GreyUnless(acceptCalm, function(db) return db.questRevealOnAccept end)

	local revealProgress = Check(content, "questRevealOnProgress", L["Reveal on receiving quest objective"],
		L["Progress on a quest's objectives (a kill or item counted towards it) shows the quest " ..
		"tracker the same way."])
	revealProgress:SetPoint("TOPLEFT", acceptCalm, "BOTTOMLEFT", -QUEST_INDENT, -2)
	revealProgress:HookScript("OnClick", Refresh) -- grey out / enable the option below

	local progressCalm = Check(content, "questProgressCalm", L["Keep up for the Calm Timer"], calmTip)
	progressCalm:SetPoint("TOPLEFT", revealProgress, "BOTTOMLEFT", QUEST_INDENT, -2)
	GreyUnless(progressCalm, function(db) return db.questRevealOnProgress end)

	-- Scenarios: raid bosses' and dungeons' stages, which aren't quests.
	local lastReveal = progressCalm
	if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
		local revealScenario = Check(content, "questRevealOnScenario", L["Reveal on scenario progress"],
			L["Progress in a scenario (the stages and objectives the tracker shows for some raid bosses, " ..
			"dungeons and events) shows the quest tracker the same way."])
		revealScenario:SetPoint("TOPLEFT", progressCalm, "BOTTOMLEFT", -QUEST_INDENT, -2)
		revealScenario:HookScript("OnClick", Refresh) -- grey out / enable the option below

		local scenarioCalm = Check(content, "questScenarioCalm", L["Keep up for the Calm Timer"], calmTip)
		scenarioCalm:SetPoint("TOPLEFT", revealScenario, "BOTTOMLEFT", QUEST_INDENT, -2)
		GreyUnless(scenarioCalm, function(db) return db.questRevealOnScenario end)
		lastReveal = scenarioCalm
	end

	local onlyThat = Check(content, "questRevealOnlyThat", L["Show just that quest"],
		L["When accepting a quest or progress on one brings the quest tracker up, just that quest shows " ..
		"(and any others accepted or moved on while it's up); the rest of the tracker, headers and all, " ..
		"stays faded. Scenario progress shows just the scenario. Hovering it shows it all."])
	onlyThat:SetPoint("TOPLEFT", lastReveal, "BOTTOMLEFT", -QUEST_INDENT, -2)
	GreyUnless(onlyThat, function(db) return db.questRevealOnAccept or db.questRevealOnProgress or db.questRevealOnScenario end)
	onlyThat:HookScript("OnClick", Refresh) -- grey out / enable the option below

	local questCollapse = Check(content, "questRevealCollapse", L["Close the gaps"],
		L["The quest shows at the top of the quest tracker, not in its own place under empty space. " ..
		"Hovering the tracker puts it back."])
	questCollapse:SetPoint("TOPLEFT", onlyThat, "BOTTOMLEFT", QUEST_INDENT, -2)
	GreyUnless(questCollapse, function(db)
		return db.questRevealOnlyThat and (db.questRevealOnAccept or db.questRevealOnProgress or db.questRevealOnScenario)
	end)

	local combatCalm = Check(content, "questCombatCalm", L["Stay up for the Calm Timer after a fight"],
		L["With the quest tracker ticked In combat (Game Frames page), it stays up after a fight " ..
		"until the Calm Timer (CineMode page) has run out, then fades. Off: it fades as soon as the fight ends."])
	combatCalm:SetPoint("TOPLEFT", questCollapse, "BOTTOMLEFT", -QUEST_INDENT, -2)
	GreyUnless(combatCalm, function(db) return db.stayInCombat end)

	-- Classic's quest timer box; retail shows timers in the tracker itself.
	local timer
	if ns.OptionAvailable({ retail = false }) then
		timer = Check(content, "questTimerShow", L["Show the quest timer while one is running"],
			L["Keeps the quest timer box up in CineMode, and in fights, while a timed quest " ..
			"counts down. Just the timer: the quest tracker stays faded."])
	else
		timer = Check(content, "questTimerShow", L["Show timers in the quest tracker while one is running"],
			L["Keeps the quest tracker's timers up in CineMode, and in fights, while one counts down: " ..
			"a scenario's or assault's timer, a dungeon's clock, a timed quest's bar. Just the timer's quest " ..
			"or scenario: the rest of the tracker stays faded. Hovering it shows it all."])
	end
	timer:SetPoint("TOPLEFT", combatCalm, "BOTTOMLEFT", 0, -2)
	local lastQuest = timer

	-- The durability figure: not the quest tracker's, so the page's switch
	-- leaves it be (pageSwitch = false).
	local durability = Check(content, "durabilityShow", L["Show the durability figure when gear is damaged"],
		L["Keeps the armor figure (by the minimap) up in CineMode, and in fights, while the game shows it: " ..
		"some of your gear is badly damaged (yellow) or broken (red). It goes again once you repair. Off, " ..
		"it fades with the rest of the UI."])
	durability:SetPoint("TOPLEFT", lastQuest, "BOTTOMLEFT", 0, -16)
	durability:HookScript("OnClick", Refresh) -- grey out / enable the option below
	durability.pageSwitch = false

	local durabilityCam = Check(content, "durabilityHideInCam", L["Hide in camera modes"],
		L["While a camera mode runs (AFK, auto-run, RP walk, flights and the rest), the figure fades " ..
		"with the rest of the UI. It comes back when the camera mode ends."])
	durabilityCam:SetPoint("TOPLEFT", durability, "BOTTOMLEFT", QUEST_INDENT, -2)
	GreyUnless(durabilityCam, function(db) return db.durabilityShow end)
	durabilityCam.pageSwitch = false

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, L["Quest tracker"], L["Quest Tracker"])
end

-- Sub-page: Classic's swing timer bars: only the weapons in use, and the
-- off-hand's hidden. (Applies in CineMode and out.)
local function CreateSwingPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Swing Timer"])
	title:SetPoint("TOPLEFT", 16, -16)
	ns.FramesLink(content, title, "combat")

	local subtitle = PageIntro(content, title,
		L["Which of the game's swing timer bars show, in CineMode and out. When they come up in " ..
		"CineMode is the Swing timer row on the Game Frames page."])

	-- The page's master switch: off, everything below greys out and does
	-- nothing; the bars still fade as their Standard Frames row says.
	local handleCheck = PageSwitch(content, "handleSwing", L["Enable Page"],
		L["On: this page's settings can fade out the bars you aren't using. Off: they don't; the swing " ..
		"timer still fades as its Game Frames row says, every bar alike."], subtitle)

	local smart = Check(content, "swingSmartShow", L["Only show the weapons you're using"],
		L["The main hand (and off-hand) bars show while you auto-attack, the ranged bar while you " ..
		"shoot. A hunter's main hand bar comes up when they melee, a warrior's ranged bar when " ..
		"they shoot, and each fades out a while after (the slider below)."])
	smart:SetPoint("TOPLEFT", handleCheck, "BOTTOMLEFT", 0, -8)
	smart:HookScript("OnClick", Refresh) -- grey out / enable the slider below

	local after = Slider(content, "swingHideAfter", L["Fade out after the bar is done for"], 0, 30, 1, L["%d sec"])
	after:SetPoint("TOPLEFT", smart, "BOTTOMLEFT", 20, -24)
	Tooltip(after, L["Once you stop swinging or shooting and the bar has run down to 0, it stays this " ..
		"long before fading out."])
	GreyUnless(after, function(db) return db.handleSwing and db.swingSmartShow end)

	local offHand = Check(content, "swingHideOffHand", L["Hide the off-hand bar"],
		L["Never show the off-hand swing timer, dual wielding or not."])
	offHand:SetPoint("TOPLEFT", after, "BOTTOMLEFT", -20, -16)

	-- (Per class: your current one's.)
	local className, class = UnitClass("player")
	local rangedTop = Check(content, "swingRangedOnTop" .. class, L["Ranged bar on top for %s"]:format(className),
		L["The ranged bar goes on top, where the main hand's was, and the main hand and off-hand bars " ..
		"each move down one. Set for each class on its own, so one profile " ..
		"suits all your characters."])
	rangedTop:SetPoint("TOPLEFT", offHand, "BOTTOMLEFT", 0, -2)

	canvas:SetScript("OnShow", PageShown(Refresh, content))
	canvas:Hide()
	RegisterSubpage(canvas, L["Swing timer"], L["Swing Timer"])
end

-- Sub-page: the Cooldown Manager (the game's, or Forever Enhanced Cooldown Manager).
local function CreateCooldownPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Cooldown Manager"])
	title:SetPoint("TOPLEFT", 16, -16)
	ns.FramesLink(content, title, "combat")

	local subtitle = PageIntro(content, title,
		L["When the Cooldown Manager comes up in CineMode (Enhanced Cooldown Manager's bars too). Hovering " ..
		"it always shows it. To keep it up all the time, or in fights, see the Game Frames page; " ..
		"what comes up with it is on the Hover groups page."])

	-- The page's master switch: off, everything below greys out and does
	-- nothing; the Cooldown Manager still fades as its Standard Frames row says.
	local handleCheck = PageSwitch(content, "handleCooldowns", L["Enable Page"],
		L["On: this page's settings can keep the Cooldown Manager up in CineMode, or show only the icons " ..
		"you pick. Off: they don't; it still fades as its Game Frames row says."], subtitle)
	local function Handled() return ns.GetDB().handleCooldowns end

	-- Stay up while recharging, each bar's own (Essential's keys also count
	-- Enhanced Cooldown Manager's bars).
	local afterCombat = handleCheck
	for i, bar in ipairs({
		{ prefix = "cooldown", label = L["Essential: stay up while a cooldown is recharging"],
			tip = L["Keeps the Cooldown Manager up until every cooldown in its Essential bar (and Enhanced " ..
			"Cooldown Manager's cooldown bars) is ready again, then it fades. Not the global cooldown, nor its " ..
			"buff bars. (It brings up the Hover groups with Cooldown recharging ticked: the Cooldowns " ..
			"group by default.)"] },
		{ prefix = "cooldownUtility", label = L["Utility: stay up while a cooldown is recharging"],
			tip = L["Keeps the Cooldown Manager up until every cooldown in its Utility bar is ready again, " ..
			"then it fades. (It brings up the Hover groups with Cooldown recharging ticked: the Cooldowns " ..
			"group by default.)"] },
	}) do
		local whileKey = bar.prefix .. "WhileRecharging"
		local recharging = Check(content, whileKey, bar.label, bar.tip)
		recharging:SetPoint("TOPLEFT", afterCombat, "BOTTOMLEFT", i == 1 and 0 or -16, i == 1 and -8 or -2)
		recharging:HookScript("OnClick", Refresh) -- grey out / enable the option below
		GreyUnless(recharging, function(db) return db.handleCooldowns end)

		afterCombat = Check(content, bar.prefix .. "AfterCombat", L["Only after combat"],
			L["Only within the Calm Timer after a fight (CineMode page): after that it fades even with a " ..
			"long cooldown still going, and cooldowns used out of fights don't bring it up."])
		afterCombat:SetPoint("TOPLEFT", recharging, "BOTTOMLEFT", 16, -2)
		GreyUnless(afterCombat, function(db) return db.handleCooldowns and db[whileKey] end)
	end

	-- Each spell's key on its icon (Frames.lua: ns.ApplyCooldownKeybinds).
	local keybinds = Check(content, "cooldownKeybinds", L["Show keybinds"],
		L["Shows the key each spell is bound to in the corner of its icon in the Essential and Utility bars, " ..
		"as on an action button: the key of the first action bar button holding it (or a macro casting it)."])
	keybinds:SetPoint("TOPLEFT", afterCombat, "BOTTOMLEFT", -16, -8)
	keybinds:HookScript("OnClick", function() ns.ApplyCooldownKeybinds() end)
	GreyUnless(keybinds, function(db) return db.handleCooldowns end)
	-- Its icons' countdown numbers as the game's option says (Frames.lua: ns.ApplyCooldownNumbers).
	local numbers = Check(content, "cooldownFollowNumbers", L["Numbers follow the game's Show Numbers for Cooldowns"],
		L["The seconds left on the Cooldown Manager's icons show only when the game's Show Numbers for " ..
		"Cooldowns (Options > Action Bars) is on. Unticked, the Cooldown Manager shows them as it likes."])
	numbers:SetPoint("TOPLEFT", keybinds, "BOTTOMLEFT", 0, -2)
	numbers:HookScript("OnClick", function() ns.ApplyCooldownNumbers() end)
	GreyUnless(numbers, function(db) return db.handleCooldowns end)
	afterCombat = numbers

	-- Each spell's icon: always shown (the game's own), only when ready in
	-- fights, or only while recharging. A row per spell in the Cooldown
	-- Manager's spell bars now, grouped by bar as in its settings, then any
	-- set that aren't in it.
	local readyHeader = Label(content, "GameFontNormal", L["Spell icons"])
	readyHeader:SetPoint("TOPLEFT", afterCombat, "BOTTOMLEFT", 2, -18)
	local readyNote = PageIntro(content, readyHeader,
		L["Pick when each spell's icon shows. Always: as the game shows it. When ready: out of " ..
		"fights, and while it recharges, it fades out; it comes back once it's ready, or the seconds in " ..
		"its box before (empty: %d%% of its cooldown). While recharging: in fights or not, it shows " ..
		"only while it recharges. When it procs: in fights or not, it shows only while the game makes it " ..
		"glow (a proc, like an instant Lightning Bolt). A faded icon keeps its place in the bar. In " ..
		"fights the game may not say how long is left, so then it goes by when you last cast it. The " ..
		"settings beside each group's name set every spell in it at once."]:format(ns.READY_EARLY * 100) .. " " ..
		L["Flash: the icon flashes for a few seconds as its cooldown ends, shown then even if its setting has it faded."] .. " " ..
		L["Tracked buffs and bars: Always, In combat, Out of combat or Hidden (the game keeps your buffs " ..
		"secret in fights, so they go by that alone). Each group has a tab of its own."] .. " " ..
		L["With Smart set ticked, until you set a bar's mode, its spells with no cooldown go by what they " ..
		"cost; unticked, by their group's setting."])
	RecordKey(content, "cooldownReadyOnly") -- (for the page's Reset)
	RecordKey(content, "cooldownReadyEarly")
	RecordKey(content, "cooldownEarlyOn")
	RecordKey(content, "cooldownRechargeOnly")
	RecordKey(content, "cooldownNeedsPower")
	RecordKey(content, "cooldownGroupDefaults")
	RecordKey(content, "cooldownProcOnly")
	RecordKey(content, "cooldownAlwaysShow")
	RecordKey(content, "cooldownBuffMode")
	RecordKey(content, "cooldownSmartDefaults")
	RecordKey(content, "cooldownFlashReady")
	-- Columns: the spell, when it shows, (When ready only) its Resources and
	-- how early it's back, and Flash.
	local MODE_X, POWER_X, EARLY_X, FLASH_X, ROW_HEIGHT = 200, 360, 440, 556, 26
	local GROUP_HEIGHT, GROUP_WIDTH = 36, 610
	-- Each group a tab of its own, in Heal Vision's folder look (ns.FolderTabs,
	-- made below), only those with spells now: the picked one's spells on the
	-- panel under them, the column headings at its top. The tab last picked
	-- is kept across reloads (SectionState, its id "Cooldown Manager/tab",
	-- open the group).
	local GROUP_ORDER = { "essential", "utility", "buffs", "bars", "other", "otherbuffs" }
	local picked = { id = "Cooldown Manager/tab", open = "essential" }
	-- (The panel's top left, under the tabs: placed once they're made.)
	local panelTop = CreateFrame("Frame", nil, content)
	panelTop:SetSize(1, 1)
	local panel, groupTabs, ShowTab
	local spellHeading = Label(content, "GameFontNormalSmall", L["Spell"])
	spellHeading:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12, -10)
	local modeHeading = Label(content, "GameFontNormalSmall", L["Icon shows"])
	modeHeading:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12 + MODE_X, -10)
	local powerHeading = Label(content, "GameFontNormalSmall", L["Resources"])
	powerHeading:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12 + POWER_X - 4, -10)
	local earlyHeading = Label(content, "GameFontNormalSmall", L["Show early"] .. " (" .. L["sec"] .. ")")
	earlyHeading:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12 + EARLY_X, -10)
	local flashHeading = Label(content, "GameFontNormalSmall", L["Flash"])
	flashHeading:SetPoint("TOPLEFT", panelTop, "TOPLEFT", 12 + FLASH_X - 4, -10)
	local noSpells = Label(content, "GameFontDisable", L["Nothing in the Cooldown Manager right now."])
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

	-- Each group's settings (db.cooldownGroupDefaults[group]: mode, power,
	-- early = seconds or nil for the default share; a mode not set: the
	-- built-in one, ns.COOLDOWN_GROUP_MODES). A spell not set on its own
	-- follows its group; setting the group's mode puts every spell in it back
	-- to following it. A spell made When ready on its own starts with its
	-- group's Resources and Show early.
	local function GroupDefaults(group)
		local all = ns.GetDB().cooldownGroupDefaults
		all[group] = all[group] or {}
		return all[group]
	end

	local OWN_MODES = { ready = "cooldownReadyOnly", recharge = "cooldownRechargeOnly", proc = "cooldownProcOnly",
		always = "cooldownAlwaysShow" }
	local function ModeOf(spell)
		return (ns.CooldownSpellMode(spell, groupOf[spell]))
	end
	-- (nil: back to following its group)
	local function SetSpellMode(spell, mode)
		local db = ns.GetDB()
		if mode == "ready" and not db.cooldownReadyOnly[spell] then
			-- (Newly When ready: as it was following its group, or its group's
			-- Resources and Show early; the seconds box empty, the default
			-- share, unless the group says.)
			local _, power, early = ns.CooldownGroupSettings(groupOf[spell] or "other")
			db.cooldownEarlyOn[spell], db.cooldownReadyEarly[spell] = true, early
			db.cooldownNeedsPower[spell] = power or nil
		end
		for value, key in pairs(OWN_MODES) do
			db[key][spell] = value == mode or nil
		end
	end
	-- A spell following its group's When ready gets its own (the same) before one part changes.
	local function OwnReady(spell)
		if not ns.GetDB().cooldownReadyOnly[spell] then SetSpellMode(spell, "ready") end
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
		Power = function(spell) return select(3, ns.CooldownSpellMode(spell, groupOf[spell])) end,
		SetPower = function(spell, value)
			OwnReady(spell)
			ns.GetDB().cooldownNeedsPower[spell] = value or nil
		end,
		Early = function(spell)
			local _, _, _, earlyOn, seconds = ns.CooldownSpellMode(spell, groupOf[spell])
			return EarlyText(earlyOn, seconds)
		end,
		SetEarly = function(spell, seconds)
			OwnReady(spell)
			local db = ns.GetDB()
			db.cooldownEarlyOn[spell], db.cooldownReadyEarly[spell] = true, seconds
		end,
		Length = function(spell) return ns.CooldownLength(spell) end,
		Flash = function(spell) return ns.CooldownSpellFlash(spell, groupOf[spell]) end,
		SetFlash = function(spell, value) ns.GetDB().cooldownFlashReady[spell] = value end,
		modes = MODES,
		tip = L["When this spell's icon shows in the Cooldown Manager."],
	}
	local GROUP = {
		Mode = function(group) return (ns.CooldownGroupSettings(group)) end,
		SetMode = function(group, mode)
			GroupDefaults(group).mode = mode
			for _, spell in ipairs(groupSpells[group] or {}) do
				SetSpellMode(spell, nil)
			end
		end,
		Power = function(group) return GroupDefaults(group).power end,
		SetPower = function(group, value)
			GroupDefaults(group).power = value or nil
			for _, spell in ipairs(groupSpells[group] or {}) do
				if ns.GetDB().cooldownReadyOnly[spell] then SPELL.SetPower(spell, value) end
			end
		end,
		Early = function(group) return EarlyText(true, GroupDefaults(group).early) end,
		SetEarly = function(group, seconds)
			GroupDefaults(group).early = seconds
			for _, spell in ipairs(groupSpells[group] or {}) do
				if ns.GetDB().cooldownReadyOnly[spell] then SPELL.SetEarly(spell, seconds) end
			end
		end,
		Length = function() return nil end,
		Flash = function(group) return ns.CooldownGroupFlash(group) end,
		SetFlash = function(group, value)
			-- (Kept even when off: Smart set turns some groups' on until they're set.)
			GroupDefaults(group).flash = value and true or false
			for _, spell in ipairs(groupSpells[group] or {}) do
				ns.GetDB().cooldownFlashReady[spell] = nil
			end
		end,
		modes = MODES,
		tip = L["Sets every spell in this group to this. Spells you haven't set on their own follow it, " ..
			"and a spell here made When ready on its own starts with its Resources and Show early."],
	}
	-- A tracked buff or bar (db.cooldownBuffMode), and their groups' settings.
	-- (No Resources, Show early or Flash: those are for spells.)
	local function NoValue() return nil end
	local BUFF = {
		Mode = function(spell) return (ns.CooldownBuffMode(spell, buffGroupOf[spell])) end,
		SetMode = function(spell, mode) ns.GetDB().cooldownBuffMode[spell] = mode end,
		Power = NoValue, SetPower = NoValue, Early = NoValue, SetEarly = NoValue, Length = NoValue,
		modes = BUFF_MODES,
		tip = L["When this buff's icon or bar shows. The game keeps your buffs secret in fights, so these go " ..
			"by whether you're in one."],
	}
	local BUFF_GROUP_ACCESS = {
		Mode = function(group) return (ns.CooldownGroupSettings(group)) end,
		SetMode = function(group, mode)
			GroupDefaults(group).mode = mode
			for _, spell in ipairs(groupSpells[group] or {}) do
				ns.GetDB().cooldownBuffMode[spell] = nil
			end
		end,
		Power = NoValue, SetPower = NoValue, Early = NoValue, SetEarly = NoValue, Length = NoValue,
		modes = BUFF_MODES,
		tip = L["Sets every buff in this group to this. Buffs you haven't set on their own follow it."],
	}

	local GetName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
	local GetIcon = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
	local rows, buffRows, groupRows = {}, {}, {}

	-- A row: a name, its mode (a dropdown, or on clients without the modern
	-- one a button stepping through them), and for When ready its Resources
	-- tick and seconds box. access: SPELL or GROUP; row.key what it's for.
	local function NewRow(access, font)
		local row = { access = access, font = font }
		row.name = Label(content, font, "")
		row.name:SetWidth(MODE_X - 10)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)

		local function Pick(mode)
			if row.key == nil then return end
			access.SetMode(row.key, mode)
			Refresh() -- (a group's change shows on its spells' rows too)
		end
		local ok, dropdown = ns.MenuDropdown(content)
		if ok and dropdown and dropdown.SetupMenu then
			dropdown:SetWidth(150)
			dropdown.searchSkip = true
			dropdown:SetupMenu(function(_, rootDescription)
				for _, choice in ipairs(access.modes) do
					rootDescription:CreateRadio(choice.text,
						function() return row.key ~= nil and access.Mode(row.key) == choice.value end,
						function() Pick(choice.value) end)
				end
			end)
			row.mode = dropdown
		else
			local button = ns.PanelButton(content)
			button:SetSize(150, 22)
			button:SetScript("OnClick", function()
				local now = row.key ~= nil and access.Mode(row.key)
				local modes = access.modes
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
		local power = Check(content, nil, "", L["Ready also needs the resources to cast it: Maelstrom, " ..
			"mana, rage and so on. Until you have them the icon stays faded."], function(value)
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
		local early = ns.SkinEditBox(CreateFrame("EditBox", nil, content, "InputBoxTemplate"))
		early:SetSize(36, 20)
		early:SetAutoFocus(false)
		early:SetNumeric(true)
		early:SetMaxLetters(4)
		early:SetPoint("LEFT", row.mode, "LEFT", EARLY_X - MODE_X + 6, 0)
		Tooltip(early, L["How many seconds before it's ready the icon comes back: 0 for once it's ready. " ..
			"Leave it empty for %d%% of its cooldown."]:format(ns.READY_EARLY * 100))
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

		-- Flash (any mode): its icon flashes for a few seconds as its cooldown
		-- ends, shown for it even if its mode has it faded.
		if access.SetFlash then
			local flash = Check(content, nil, "", L["Flashes the icon for a few seconds when the spell's " ..
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
				for _, choice in ipairs(access.modes) do
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
			if not ready then return end
			row.power:SetChecked(access.Power(key) and true or false)
			row.power:SetEnabled(handled)
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
			row.line = content:CreateTexture(nil, "ARTWORK")
			row.line:SetColorTexture(1, 0.82, 0, 0.4)
			row.line:SetSize(GROUP_WIDTH, 1)
			if group ~= "other" and (not BUFF_GROUP[group] or group == "buffs") then
				row.center = Check(content, nil, L["Close the gaps (centered)"], group == "buffs"
					and L["The buffs this bar shows sit together in their order, centered on the bar, instead of " ..
					"inactive or faded ones leaving gaps. Edit Mode shows the game's own layout."]
					or L["The icons this bar shows sit together in their order, centered on the bar, instead of " ..
					"faded ones leaving gaps. Edit Mode shows the game's own layout."], function(value)
					GroupDefaults(group).center = value -- (false kept: Utility's is on until set)
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
		local db = ns.GetDB()
		local list = ns.CooldownManagerSpells()
		local listed = { spell = {}, buff = {} }
		for _, spell in ipairs(list) do
			listed[BUFF_GROUP[spell.group] and "buff" or "spell"][spell.id] = true
		end
		for _, set in ipairs({
			{ "other", "spell", { db.cooldownReadyOnly, db.cooldownRechargeOnly, db.cooldownProcOnly } },
			{ "otherbuffs", "buff", { db.cooldownBuffMode } },
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
		flashHeading:SetShown(group ~= nil and not BUFF_GROUP[group])
	end
	-- The tabs (their full names their tips).
	local tabList = {}
	for i, group in ipairs(GROUP_ORDER) do tabList[i] = { TAB_NAMES[group], GROUP_NAMES[group] } end
	local base, height
	panel, groupTabs, ShowTab, base, height = ns.FolderTabs(content, tabList, function(i)
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
	local smartSet = Check(content, "cooldownSmartDefaults", L["Smart set"],
		L["Ticked: the spells with no cooldown you haven't set yourself go by what they cost, until you set " ..
		"their group's mode: When ready with Resources if they spend a resource you build up (like Maelstrom), " ..
		"else When it procs (like Lightning Bolt). Spells with a cooldown or charges go by their group's " ..
		"setting. It also turns on Flash for Utility Cooldowns, until you set that group's Flash. Unticked: " ..
		"every spell you haven't set yourself goes by its group's setting."],
		function(value)
			KeyPut("cooldownSmartDefaults", value)
			ListSpells()
			Refresh()
		end)
	smartSet:SetPoint("TOPLEFT", readyNote, "BOTTOMLEFT", -2, -6)
	-- Reset: just the spell icons' settings (the page's Reset does the rest too).
	local SPELL_ICON_KEYS = { cooldownReadyOnly = true, cooldownReadyEarly = true, cooldownEarlyOn = true,
		cooldownRechargeOnly = true, cooldownNeedsPower = true, cooldownGroupDefaults = true,
		cooldownProcOnly = true, cooldownAlwaysShow = true, cooldownBuffMode = true, cooldownSmartDefaults = true,
		cooldownFlashReady = true }
	local iconsReset = ns.PanelButton(content)
	iconsReset:SetSize(60, 20)
	iconsReset:SetPoint("LEFT", smartSet.Text or smartSet.text or smartSet, "RIGHT", 16, 0)
	iconsReset:SetText(L["Reset"])
	iconsReset.searchSkip = true
	Tooltip(iconsReset, L["Put every spell's, buff's and group's icon setting, and Smart set, back to the " ..
		"active profile's own."])
	iconsReset:SetScript("OnClick", function()
		StaticPopup_Show("CINEMATIC_RESET_PART", nil, nil, { content = content, keys = SPELL_ICON_KEYS,
			after = function()
				ListSpells()
				Refresh()
			end })
	end)

	-- The Flash style, for every spell with Flash ticked (Frames.lua): a
	-- glow, the icon growing with each beat, a colored border, and how long.
	local flashLabel = Label(content, "GameFontHighlight", L["Flash style:"])
	flashLabel:SetPoint("TOPLEFT", smartSet, "BOTTOMLEFT", 2, -12)
	local flashGlow = Check(content, "cooldownFlashGlow", L["Glow"],
		L["The icon glows bright and dim while it flashes."])
	flashGlow:SetPoint("LEFT", flashLabel, "RIGHT", 8, 0)
	local flashGrow = Check(content, "cooldownFlashGrow", L["Grow"],
		L["The icon grows a little and back with each beat while it flashes."])
	flashGrow:SetPoint("LEFT", flashGlow.Text or flashGlow.text or flashGlow, "RIGHT", 12, 0)
	local flashBorder = Check(content, "cooldownFlashBorder", L["Border"],
		L["A border in the color beside it around the icon while it flashes."])
	flashBorder:SetPoint("LEFT", flashGrow.Text or flashGrow.text or flashGrow, "RIGHT", 12, 0)
	local flashSwatch = CreateFrame("Button", nil, content)
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
	local flashTest = ns.PanelButton(content)
	flashTest:SetSize(60, 20)
	flashTest:SetPoint("LEFT", flashSwatch, "RIGHT", 16, 0)
	flashTest:SetText(L["Test"])
	flashTest.searchSkip = true
	Tooltip(flashTest, L["Flashes every icon in the Essential and Utility bars once, in this style."])
	flashTest:SetScript("OnClick", function() ns.TestCooldownFlash() end)
	local flashTime = Slider(content, "cooldownFlashTime", L["Flash for"], 1, 6, 0.5,
		function(value) return L["%.1f sec"]:format(value) end)
	flashTime:SetPoint("TOPLEFT", flashLabel, "BOTTOMLEFT", 0, -28)
	Tooltip(flashTime, L["How long the icon flashes once its cooldown ends."])
	for _, control in ipairs({ flashGlow, flashGrow, flashBorder, flashTime }) do
		GreyUnless(control, function(db) return db.handleCooldowns end)
	end
	panelTop:SetPoint("TOPLEFT", flashTime, "BOTTOMLEFT", 0, -16 - height)
	noSpells:SetPoint("TOPLEFT", flashTime, "BOTTOMLEFT", 0, -20)

	local shown = PageShown(Refresh, content)
	canvas:SetScript("OnShow", function()
		ListSpells()
		shown()
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
		L["Mobs and NPCs you still need for a quest objective keep their nameplates up, with a quest mark on " ..
		"them and on your target frame, and the quest object in front of you glows."])
	local function ApplyQuest()
		if ns.RefreshTargetQuestIcon then ns.RefreshTargetQuestIcon() end
		if ns.UpdateQuestGlow then ns.UpdateQuestGlow() end
		if ns.RefreshQuestItemButton then ns.RefreshQuestItemButton() end
	end
	-- (Its switch: questVision, its Enable before it had a page.)
	local questSwitch = PageSwitch(content, "questVision", L["Enable Page"],
		L["On: everything below works as ticked. Off: none of it does, and each keeps its tick for " ..
		"when you turn this back on."], note, ApplyQuest)
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
	local QUEST_SHOWS_TIP = L["What shows of mobs and NPCs you still need for a quest objective (a mob to kill, " ..
		"an NPC to talk to), whatever the Nameplates page's grids say; tick any. Nameplate: their whole " ..
		"nameplates. Name: their names, on their nameplates. Quest mark: a golden ! added to the nameplate or " ..
		"name shown, else the ! alone. These three in CineMode, in fights and out, and need the Nameplates page " ..
		"enabled; once the objective is done, they fade with the rest. Unit frame: the same mark beside your " ..
		"target frame's health bar while your target is one of them, in CineMode and out. None ticked: as the " ..
		"Nameplates page's settings say."]
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
		L["A golden exclamation mark beside their nameplates' health bars, wherever their plates show " ..
		"(beside their names when just their names show). Always on with Quest mark above. Needs the " ..
		"Nameplates page enabled."])
	GreyUnless(questIcon, function(db) return db.handlePlates and not db.questMobsMark end)
	questStack:Add(questIcon, "check")
	questIcon:HookScript("OnClick", Refresh) -- (grey out / enable what needs it)
	-- (Indented under it, as its sub-option.)
	local markFade = Check(content, "questMarkFade", L["Fade if another addon competes"],
		L["When another addon has its own icon on a unit (Questie, on nameplates and the target frame), Cinematic's " ..
		"quest mark stays off it, so only one shows. Unticked, both show."], function(value)
			ns.GetDB().questMarkFade = value
			if ns.RefreshTargetQuestIcon then ns.RefreshTargetQuestIcon() end
		end)
	questStack:Add(markFade, "check", 16)
	GreyUnless(markFade, function(db)
		return db.targetQuestIcon or (db.handlePlates and (db.questMobsMark or db.plateAlwaysPartQuestIcon))
	end)
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
		L["The quest mark's icon on friendly NPCs you still need for a quest (an NPC to talk to): on their " ..
		"nameplates or names, on your target frame, and over the quest object that glows. One you can't do " ..
		"anything with yourself shows it grayed (with the !, the game's \"in progress\" mark). Click to pick another."], 0)
	MarkButton("questMarkStyleEnemy", L["Enemy"],
		L["The quest mark's icon on enemies you still need for a quest (a mob to kill): on their nameplates " ..
		"or names, and on your target frame. Click to pick another."], 140)
	questStack:Add(markRow, "dropdown")
	local questItem = Check(content, "questItemButton", L["Quest item button"],
		L["Where your extra ability button goes (the extra abilities frame's place in Edit Mode), a big button " ..
		"with the item the nearest tracked quest gives you to use, the one in the quest tracker. Click it or press its " ..
		"key (Keybinds page). Shows near the quest's area, beside the game's own button when that's up. " ..
		"It can't show, hide or move in a fight: it stays as it was until the fight ends."]
		.. L[" Its look: the Quest Item Button tab."], function(value)
		ns.GetDB().questItemButton = value
		if ns.RefreshQuestItemButton then ns.RefreshQuestItemButton() end
	end)
	questStack:Add(questItem, "check")
	questItem:HookScript("OnClick", Refresh) -- (grey out / enable what needs it)
	-- (Indented under it, as its sub-option.)
	local itemFade = Check(content, "questItemFade", L["Fade if another addon competes"],
		L["When another addon has a button up for the same item (Questie, in its tracker), Cinematic's big button " ..
		"stays away, so only one shows, and its key does nothing until it's back. Unticked, both show."],
		function(value)
			ns.GetDB().questItemFade = value
			if ns.RefreshQuestItemButton then ns.RefreshQuestItemButton() end
		end)
	questStack:Add(itemFade, "check", 16)
	GreyUnless(itemFade, function(db) return db.questItemButton end)
	local questGlow = Check(content, "questObjectGlow", L["Glow on quest objects"],
		L["The thing on the ground you pick up or use for a quest objective glows gold, with the quest mark " ..
		"over it, in CineMode and out. One at a time: the one in front of you that your interact key would " ..
		"use, up to 20 yards away. Only while a quest in this zone still needs something picked up or used. " ..
		"Then it turns on the game's soft targeting for things to interact with (Interact key on keyboard " ..
		"and mouse too); your own settings come back after."],
		function(value)
			ns.GetDB().questObjectGlow = value
			if ns.UpdateQuestGlow then ns.UpdateQuestGlow() end
		end)
	questStack:Add(questGlow, "check")
	local hideObjectIcons = Check(content, "hideObjectIcons", L["Hide object icons"],
		L["Keeps the game's icon and name off the thing in front of you that your interact key would use (a " ..
		"gear over a gate, a hand over a chest). The game turns them back on each time you log in, so this " ..
		"keeps them off for you. While the glow on quest objects is lit, the glow decides instead. Your own " ..
		"setting comes back when you untick it."],
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
				L["The game's talking head (the NPC portrait at the top of the screen, with their line and voice) " ..
				"closes at once when it's a line you've already seen. Daily and world quest lines come back every " ..
				"day, so you see them once; the story's lines play only once anyway. Each character remembers its own, " ..
				"ticked or not, so an alt still sees the story's."]), "check")
		end
		questStack:Header(content, L["Talking to NPCs"])
		-- Quest talk itself (questTalk; off to start with, on in the Cinema
		-- profile). How it looks, the "Show the game's window" link and the
		-- number keys: the Quest talk tab (QuestTalkStyle.lua).
		local talk = questStack:Add(Check(content, "questTalk", L["Custom dialogue frames"],
			L["Talking to an NPC, what they say shows in a speech bubble over their head, and what you can say " ..
			"back in a list near the bottom of the screen, instead of the game's gossip and quest windows. " ..
			"The list has everything the window would: quests to turn in, pick up or still in progress, " ..
			"and every other option (vendor, trainer, inn, flight master...). A quest offered or turned in " ..
			"shows its objective and rewards on a card, with its buttons; click a reward to choose it. " ..
			"\"Show the game's window\" on the card brings the game's window back for that conversation. " ..
			"The game's popups (a cost to confirm, a party member's escort quest) come up as usual."] ..
			L[" Its look: the Dialogue tab."], function(value)
				ns.GetDB().questTalk = value
				ApplyTalk()
			end), "check")
		talk:HookScript("OnClick", Refresh) -- (grey out / enable what needs it)
		-- (Indented under it, as its sub-option.)
		local talkFade = Check(content, "questTalkFade", L["Fade if another addon competes"],
			L["When another addon takes over talking to NPCs (Immersion, Dialogue UI and the like), Cinematic's " ..
			"dialogue frames stay out of the way, so only one shows. Unticked, they show as well wherever the " ..
			"game's window still opens. An addon that stops that window opening always wins."])
		questStack:Add(talkFade, "check", 16)
		GreyUnless(talkFade, TalkOn)
		-- Where they go (the bubble and list; with quest talk off, the game's windows).
		local PLACES = {
			{ value = "fixed", text = L["Default"] },
			{ value = "head", text = L["Over the head"], enabled = TalkOn },
			{ value = "opposite", text = L["Opposite clicked"] },
		}
		local PLACE_TIP = L["Where the bubble goes. Over the head: over the NPC's nameplate, following them on " ..
			"the screen. Default: where the game's quest window opens, or wherever you drag it. Opposite clicked: " ..
			"wherever you drag it, but when you clicked the NPC on that half of the screen, at the same spot on " ..
			"the other half (they stand where you clicked, so that half is clearer), the quest card beside it. " ..
			"With nobody to stand over or no click (a quest from an item, or the interact key), it goes where " ..
			"Default would."] .. "\n\n" .. L["With Custom dialogue frames unticked, it places the game's own gossip and " ..
			"quest window instead. Default: wherever you drag it (else where the game puts it). Opposite clicked: " ..
			"the same, but on the other half of the screen from where you clicked the NPC. Over the head isn't " ..
			"for a whole window (it would cover them): the game's window is left where the game puts it."]
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
			L["Over the NPC's head, the bubble always stays at least this far down from the top of " ..
			"the screen (and below the letterbox), so it never sits right against the edge."], ApplyTalk), TalkOn)
		local still = Own("head", headStack:Add(Check(content, "questTalkStill", L["Hold the camera still"],
			L["With the bubble over the head, the quest camera turns in as usual but doesn't drift to and fro " ..
			"while you talk: following the NPC on the screen, the bubble and card would jiggle as it moved."],
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
		local TURN_TIP = L["What the bubble and card do while the camera moves: the quest camera's swing, zoom " ..
			"and turn (its drift is Hold the camera still's), or you turning it. Follow: they stay over the " ..
			"NPC's nameplate, sliding with it. Fade out: they fade out, and back in over the NPC once it's " ..
			"still. Dim: they fade down, still readable. Wait to the side: they stay still where Default would " ..
			"put them, and fade over to the NPC once the camera's still."]
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
			L["Picking a vendor's \"let me browse your goods\", the shop window opens where the talk was, on the " ..
			"other half of the screen from the NPC, instead of where the game puts it. A shop opened straight from " ..
			"a right click on the vendor opens where the game puts it. Drag it and it stays where you drop it " ..
			"until it closes."]), "check"))
		-- (Shown as the position is: refreshed with the page, so picking
		-- another in the dropdown swaps them.)
		controls[#controls + 1] = {
			debugName = "bubble position's settings",
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
			L["In a group, items rolled on show in a window instead of only as lines in chat: each item, a bar " ..
			"for the time left, and everyone's pick (need, greed, transmog) and number, the winner lit at the top. " ..
			"It opens as an item drops, just under the game's roll frame, so you can see who's picked what before you choose, and takes its place once you have. Each item fades a few seconds after it's won (point at them to keep them). It stays with the game's roll frames: with \"Drag windows to move them\" on, dragging either moves both. " ..
			"/cine rolls shows the latest rolls."])
		local rollSwitch = PageSwitch(content, "rollWindow", L["Enable Page"],
			L["On: everything below works as ticked. Off: none of it does, and each keeps its tick for " ..
			"when you turn this back on."], note, function() ns.RefreshRollWindow() end)
		stack = Stack(rollSwitch, "check")
		local function RollsOn(db) return db.rollWindow end
		local rollFade = stack:Add(Check(content, "rollFade", L["Fade if another addon competes"],
			L["While another addon has the loot rolls (XLoot, ElvUI's Loot Roll, or any that takes over the " ..
			"game's roll frames), the window stays away and leaves them to it. /cine rolls still opens it."],
			function(value)
				ns.GetDB().rollFade = value
				ns.RefreshRollWindow()
			end), "check")
		GreyUnless(rollFade, RollsOn)
		local QUALITIES = {
			{ value = 2, text = L["Uncommon and up"] },
			{ value = 3, text = L["Rare and up"] },
			{ value = 4, text = L["Epic and up"] },
		}
		local QUALITY_TIP = L["Only items of this quality and better get a panel in the window. Rolls on the " ..
			"rest are only in chat, unless the game asks you to roll on one. The test (/cine rolls test) goes by it too."]
		-- Which items get a panel, then whose rolls each lists, then where the window goes.
		stack:Header(content, L["Which items"])
		stack:Add(Label(content, "GameFontHighlight", L["Show rolls on"]), "label")
		local quality = Dropdown(content, "rollMinQuality", QUALITIES, 200)
		if quality then
			stack:Add(quality, "dropdown")
			Tooltip(quality, QUALITY_TIP)
			GreyUnless(quality, RollsOn)
		else
			for _, choice in ipairs(QUALITIES) do
				local check = stack:Add(Choice(content, "rollMinQuality", choice.value, choice.text, QUALITY_TIP), "check")
				GreyUnless(check, RollsOn)
			end
		end
		local usable = stack:Add(Check(content, "rollUsableOnly", L["Only items you can use"],
			L["Items you can't use (armor or weapons you can't wear, another class's, or a level you're not " ..
			"yet: anything in red on its tooltip) don't get a panel, unless the game asks you to roll on one. " ..
			"Their rolls are only in chat."]), "check")
		GreyUnless(usable, RollsOn)
		GreyUnless(stack:Add(BoxLine(content), "label"):Box(L["Items shown at once"], "rollMaxPanels", 1, 8, 1, "%d",
			1, L["The window shows this many items at once, newest at the top: four down, the " ..
			"rest in a second column. When another drops, the oldest goes."]), RollsOn)
		stack:Header(content, L["Players"])
		GreyUnless(stack:Add(BoxLine(content), "label"):Box(L["Players shown per item in a raid"], "rollRaidRows", 1,
			10, 1, "%d", 1, L["In a raid, each item lists only this many players' rolls: the winner, then need " ..
			"before greed, the highest numbers first. The rest are counted on an \"and N more\" line. " ..
			"In a party, everyone is listed. Click an item's panel to list everyone on it."]), RollsOn)
		local ownRoll = stack:Add(Check(content, "rollShowSelf", L["Always list your own roll"],
			L["Your own pick and number are always on an item's panel, even when it lists only the top few " ..
			"players or only the best pick."]), "check")
		GreyUnless(ownRoll, RollsOn)
		local topPick = stack:Add(Check(content, "rollTopPick", L["Only show the best pick"],
			L["Once anyone picks need, players on greed or transmog for that item aren't listed (they can't " ..
			"win it), only counted on a \"Lower picks\" line. Players still choosing stay listed. Click an " ..
			"item's panel to list everyone on it."]), "check")
		GreyUnless(topPick, RollsOn)
		local footer = stack:Add(Check(content, "rollFooter", L["Show the counts under each item"],
			L["The lines under an item's players: \"and N more\", \"Lower picks\", who passed, and " ..
			"\"Click to list everyone\". Off: just the players. Clicking an item's panel still lists everyone."]),
			"check")
		GreyUnless(footer, RollsOn)
		stack:Header(content, L["Where"])
		local beside = stack:Add(Check(content, "rollBeside", L["Beside the game's roll frames"],
			L["The window sits to the right of the game's roll frames, level with their top, instead of under " ..
			"them, so a long list of drops doesn't push it down the screen. It stays there once you've chosen."],
			function(value)
				ns.GetDB().rollBeside = value
				ns.RefreshRollWindow()
			end), "check")
		GreyUnless(beside, function(db) return db.rollWindow and not db.rollSeparate end)
		local separate = stack:Add(Check(content, "rollSeparate", L["Move apart from the game's roll frames"],
			L["Dragging the window moves only it, not the game's roll frames, and dragging those moves only " ..
			"them, so the two can sit anywhere on the screen. The window comes up where you last dropped it. " ..
			"Until you've dragged it, it comes up by the game's roll frames as usual. Its dragging works even " ..
			"with \"Drag windows to move them\" off."],
			function(value)
				ns.GetDB().rollSeparate = value
				ns.RefreshRollWindow()
				Refresh() -- ("Beside the game's roll frames" greys out)
			end), "check")
		GreyUnless(separate, RollsOn)
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
		L["In CineMode, the nameplates of two players dueling near you show, so you can watch their health. " ..
		"Only in the open world, out of fights. Turns on friendly player nameplates while it watches, " ..
		"kept invisible and click-through bar the duelists'. Each duel has its own color, and the winner " ..
		"and loser show when it ends. Needs the Nameplates page enabled."])
	local duelSwitch = PageSwitch(content, "duelPlates", L["Enable Page"],
		L["On: everything below works as ticked. Off: none of it does, and each keeps its tick for " ..
		"when you turn this back on."], note)
	GreyUnless(duelSwitch, function(db) return db.handlePlates end)
	stack = Stack(duelSwitch, "check")
	local duelCC = stack:Add(Check(content, "duelCC", L["Crowd control"],
		L["A feared, stunned, polymorphed, rooted or silenced duelist gets an icon of the spell beside their " ..
		"nameplate, with the time left."]), "check")
	GreyUnless(duelCC, function(db) return db.handlePlates and db.duelPlates end)
	local duelHide = stack:Add(Check(content, "duelHideOthers", L["Hide other duels while you duel"],
		L["While you're in a duel (or have asked for one, or been asked), other players' duels nearby don't " ..
		"show. Off: they show all through yours."]), "check")
	GreyUnless(duelHide, function(db) return db.handlePlates and db.duelPlates end)
	-- Test: pretend duels for 30 seconds (see Effects); Stop with the seconds
	-- left meanwhile (as the camera tests').
	local duelTest = ns.PanelButton(content)
	duelTest:SetSize(90, 22)
	duelTest:SetText(L["Test"])
	Tooltip(duelTest, L["Friendly players around you duel for 30 seconds, in pretend: their nameplates, " ..
		"made-up crowd control, and winners and losers, to see how it looks. Needs CineMode and other " ..
		"players nearby. Clicking Stop ends it."])
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
			L["The game's party and raid frames show only who needs healing: everyone (pets too) while below full " ..
			"health, and tanks as set below. The group titles hide. The members stay " ..
			"in their places, so there are gaps. Out of combat, the mouse over the frames brings everyone back. " ..
			"Ticked in the grid, it's on there. Always: everywhere. Party and Raid: while you're in one, wherever you are. " ..
			"Members with debuffs can't be shown: the game doesn't let addons see your group's debuffs in fights."])

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
			L["On: Heal Vision works as ticked below. Off: it doesn't, and each keeps its tick for " ..
			"when you turn this back on."], healIntro, ApplyFrames)

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
				L["Heal Vision out of fights while you have anything else targeted: friends, NPCs, dead enemies."]) }
		ns.GridRow(ns.GRID_KIT, row, NAME_WIDTH, LAYOUT, {
			band = 1,
			always = { isOn = function() return ns.GetDB().healVision end,
				set = function(value) Set("healVision", value) end,
				tip = L["Heal Vision everywhere. The rest of the row keeps its ticks for when you untick this."] },
			menus = { [ns.GRID_COMBAT] = combat, [ns.GRID_TARGET] = targets, [ns.GRID_LOCATION] = places },
			help = { [ns.GRID_COMBAT] = L["On in fights, and with the Calm Timer, after them till it's run out."],
				[ns.GRID_TARGET] = L["On while you have one of these targeted, out of fights."],
				[ns.GRID_LOCATION] = L["On while you're in any of these (Party and Raid: in one, wherever you are)."] },
			rule = { key = function() return "healVision" end, label = function() return L["Heal Vision"] end,
				changed = Apply },
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
			return { get = function() local db = ns.GetDB() return db[KeyOf(db, key)] end,
				set = function(value) ns.GetDB()[editing and key .. "_" .. editing or key] = value end }
		end
		local ROLE_NAMES = { TANK = L["Tank"], HEALER = L["Healer"], DAMAGER = L["Damage"] }
		local TABS = { false, "TANK", "HEALER", "DAMAGER" }
		local ROLE_ICONS = { TANK = "0:19:22:41", HEALER = "20:39:1:20", DAMAGER = "20:39:22:41" }
		local ownCheck, tabNote
		-- Folder tabs (ns.FolderTabs), a role's each after Default's.
		local TAB_H = ns.FOLDER_TAB_HEIGHT
		local list = {}
		for i, role in ipairs(TABS) do
			list[i] = { role and ROLE_NAMES[role] or L["Default"], role and L["The settings below as they are " ..
				"while you're this role (your specialization's, or the one picked in the group finder)."]
				or L["The settings below for every role that uses the default settings."] }
		end
		local panel, tabs, ShowTab, base = ns.FolderTabs(content, list, function(i)
			editing = TABS[i] or nil
			Refresh() -- (the tabs too: ownCheck's Refresh)
		end, 90)
		panel:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -14 - TAB_H - 4)
		-- (On the row, not the panel: the panel's bottom hangs on the rows under them.)
		base:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -14 - TAB_H - 4)
		local function ShowTabs()
			local db = ns.GetDB()
			if not db then return end
			for i, role in ipairs(TABS) do
				if (role or nil) == editing then ShowTab(i) end
			end
			ownCheck:SetShown(editing ~= nil)
			local role = ns.PlayerRole()
			tabNote:SetText(L["Current role:"] .. " " .. (ROLE_ICONS[role] and
				"|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:" .. ROLE_ICONS[role] .. "|t"
				or L["None"]))
		end
		tabNote = Label(content, "GameFontHighlight")
		tabNote:SetPoint("LEFT", tabs[#tabs], "BOTTOMRIGHT", 10, TAB_H / 2)
		tabNote.searchSkip = true
		for _, role in ipairs(ns.HEAL_VISION_ROLES) do RecordKey(content, "healVisionOwn_" .. role) end
		-- Use default settings: unticked, the role goes by its own values (each kept while ticked).
		ownCheck = Check(content, false, L["Same as the Default tab"],
			L["Ticked: while you're this role, Heal Vision goes by the Default tab. Unticked: by the " ..
			"settings on this tab."], function(value)
				ns.GetDB()["healVisionOwn_" .. editing] = not value
				Apply()
			end)
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
		-- health they show below (100%: any damage; tanks: always) and how
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
			below = Cell(row, 1, belowField, heading .. ": " .. L["Show below health"], belowTip, function(value)
				-- (Below the opacity: takes it down too.)
				if value < Percent(alphaField.get(), 0.05) then
					alphaField.set(value / 100)
					alpha:Refresh()
				end
				ApplyFrames()
			end)
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
			L["A tank (by role, or main tank in a raid) shows once their health drops below this. " ..
			"100% shows tanks always, at full health too."],
			"healVisionTankAlpha", L["How much of a hidden tank still shows. 0% hides them completely."])
		Kind(ROLE_ICON:format("20:39:1:20"), L["Healers"], "healVisionHealerBelow",
			L["A healer shows once their health drops below this. 100% shows them at any damage; lower " ..
			"keeps them hidden through small hits."],
			"healVisionHealerAlpha", L["How much of a hidden healer still shows. 0% hides them completely."])
		-- (Anyone without a tank's or healer's role goes by these, and the group titles' opacity.)
		Kind(ROLE_ICON:format("20:39:22:41"), L["Damage"], "healVisionShowBelow",
			L["A damage dealer (or anyone without a role) shows once their health drops below this. 100% " ..
			"shows them at any damage; lower keeps them hidden through small hits."],
			"healVisionMinAlpha", L["How much of a hidden damage dealer still shows, and of the group titles. " ..
			"0% hides them completely."])
		Kind(PET_ICON, L["Pets"], "healVisionPetBelow",
			L["A pet shows once its health drops below this. 100% shows it at any damage."],
			"healVisionPetAlpha", L["How much of a hidden pet still shows. 0% hides them completely."])

		Cell(Row(TARGET_ICON, L["Your target, at least"], 12), 2, Field("healVisionTargetAlpha"),
			L["Target min opacity"], L["The least of the member you've targeted that shows while they'd be hidden. " ..
			"It only ever makes them more visible: a target whose own opacity above is higher (a tank shown always, " ..
			"say) keeps it. 100% always shows them, at full health too."])
		Cell(Row(MOUSE_ICON, L["Mouseover, at least"]), 2, Field("healVisionMouseoverAlpha"),
			L["Mouseover min opacity"], L["The member under your mouse fades in to at least this, in fights too, " ..
			"and starts fading out the moment the mouse leaves them. 0% turns it off."])
		Cell(Row(SKULL_ICON, L["Dead"], 12), 2, Field("healVisionDeadAlpha"), L["Dead opacity"],
			L["Dead members are hidden whatever their health, debuffs or role (unless one is your " ..
			"target). How much of them still shows. 0% hides them completely."])
		Cell(Row(OFFLINE_ICON, L["Offline"]), 2, Field("healVisionOfflineAlpha"), L["Offline opacity"],
			L["Offline members are hidden whatever their health, debuffs or role (unless one is " ..
			"your target). How much of them still shows. 0% hides them completely."])
		Cell(Row(FAR_ICON, L["Far away"]), 2, Field("healVisionFarAlpha"), L["Far away opacity"],
			L["Members more than 100 yards away show this much, out of reach of your heals, whatever " ..
			"their health, debuffs or role (unless one is your target). In a dungeon or raid, so does anyone not " ..
			"in it with you. In battlegrounds, where WoW Forever won't say how far anyone is, members out of " ..
			"range of your heals (about 40 yards) fade to this instead of the game's own dimming, on top of the " ..
			"rest of the page. 100% leaves them be; 0% hides them completely."])
		panel:SetPoint("BOTTOMRIGHT", lastRow, "BOTTOMRIGHT", 12, -12)
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
	title:SetPoint("TOPLEFT", 16, -16)

	local note = PageIntro(content, title, L["Only in CineMode. Hold your Show hidden tooltips " ..
		"key (set it on the Keybinds page) to see a hidden one anyway."])
	-- Their look: the Style hub's Tooltips page (TooltipStyle.lua).
	ns.StyleLink(content, title, "Tooltip Style", L["Opens the Style hub's Tooltips page: how tooltips look."], Tooltip)
	local switch = PageSwitch(content, "handleTooltips", L["Enable Page"],
		L["On: CineMode hides tooltips as this page says. Off: every tooltip shows as normal."], note)

	-- Fade in/out (tooltipFadeTime): with the page switched off too.
	local fade = Slider(content, "tooltipFadeTime", L["Fade in/out"], 0, 3, 0.1, function(value)
		return value <= 0 and L["Off"] or L["%.1f sec"]:format(value)
	end)
	fade:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 6, -30)
	Tooltip(fade, L["How long tooltips take to fade in as they show, and to fade out when the mouse has been " ..
		"still too long (Mouse still, below). Off: no fading."] .. " " .. L["Works with this page switched off too."])
	fade.pageSwitch = false -- (not greyed with the switch: see SwitchOf)

	-- Mouse still: hide when or until the mouse is still, and the seconds
	-- beside it (each choice keeps its own: tooltipHideStill or tooltipShowStill).
	local stillHeader = Label(content, "GameFontNormal", L["Mouse still"])
	stillHeader:SetPoint("TOPLEFT", fade, "BOTTOMLEFT", -4, -20)
	local STILL_TIP = L["Hide when the mouse is still: a tooltip in the world or on a unit frame hides " ..
		"once it's been up this long with the mouse still. Move the mouse and it comes back. Hide until the " ..
		"mouse is still: it shows only once the mouse has rested on it this long. Off leaves tooltips be."]
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
		L["In CineMode, where and when tooltips show; the rest of the time they're hidden. For some kinds " ..
		"only (enemies, friendlies, gatherables, quest objectives, anything else), Edit its rule: the " ..
		"Tooltip line has a word for each."])
	local tooltipRows = { opts = { quiet = true, cam = true, anyFight = true }, underHeader = true, noCine = true,
		{ key = "tooltip:All", label = L["Tooltips"],
			tip = L["Every tooltip: units, things in the world and the UI's (action bars, bags, menus and the rest)."],
			alwaysKey = "tooltipAlways",
			alwaysOn = function() return ns.GetDB().tooltipAlways end,
			setAlways = function(value) ns.GetDB().tooltipAlways = value end,
			alwaysTip = L["Tooltips show all through CineMode. (The other columns then have nothing to add.)"] } }
	previous = ShowTable(content, hideHeader, tooltipRows, L["Tooltips"])
	previous.sectionX = 0

	-- Tooltip look: where tooltips show (tooltipCursorMode, with the page
	-- switched off too), how long until the After column, then a grid of
	-- the parts (rows) by when each shows: on first hover, and after
	-- tooltipFullAfter seconds (columns).
	local partsHeader = Section(L["Tooltip look"])
	local partsNote = PageIntro(content, partsHeader,
		L["Ticked, that part of the tooltip shows: On first hover, as soon as it appears; After, once you've " ..
		"hovered as long as set above, until you mouse over something else. In and out of CineMode."])
	local CURSOR_TIP = L["Where the game's tooltips (things in the world, unit frames, action bars, bags) show: " ..
		"in their default position (the bottom-right corner, or wherever you've moved it), or by the mouse " ..
		"cursor, following it (or just in fights)."] .. " " .. L["Works with this page switched off too."]
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
		cursorMode.pageSwitch = false -- (not greyed with the switch: see SwitchOf)
		lastCursor = cursorMode
	else
		lastCursor = partsNote
		for _, choice in ipairs(CURSOR_MODES) do
			local check = Choice(content, "tooltipCursorMode", choice.value, choice.text, CURSOR_TIP)
			check:SetPoint("TOPLEFT", lastCursor, "BOTTOMLEFT", lastCursor == partsNote and 2 or 0, -2)
			check.pageSwitch = false
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
	Tooltip(fullAfter, L["How long you hover over something before the After column's parts take over, " ..
		"until you mouse over something else. Off: tooltips show as normal, every part of them."])

	local PARTS = {
		Border = { L["Background and border"], L["The box around the tooltip. Unticked, just the text shows."] },
		Health = { L["Health bar"], L["The health bar under the tooltips of players, NPCs and mobs."] },
		Guild = { L["Guild and title (<...>)"], L["A player's <Guild> line, or an NPC's <Innkeeper>-style title."] },
		Level = { L["Level (friends)"], L["The level line of players, NPCs and mobs you can't attack " ..
			"(for players, with their race and class)."] },
		LevelEnemy = { L["Level (enemies)"], L["The level line of players, NPCs and mobs you can attack " ..
			"(for players, with their race and class)."] },
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
		Hint = { L["Right-click hint"],
			L["The <Right click for Frame Settings> line on the tooltips of your player, target and party frames."] },
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
	local headings
	previous, headings = Grid(fullAfter, partRows, {
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
		L["In CineMode, tooltips with these names never show, whatever the Show tooltips row says. " ..
		"Hold your Show hidden tooltips key to see one anyway."])
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
	local FILTER_TIP = L["Type a tooltip's name, its top line, as your game shows it (\"Fishing Bobber\"). " ..
		"Any case."]
	Tooltip(filterBox, FILTER_TIP)
	Tooltip(filterAdd, FILTER_TIP)
	-- Rebuilt as the page shows and after each change.
	controls[#controls + 1] = { Refresh = function()
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
	local note = PageIntro(content, title, L["These addons' frames are hidden in CineMode unless ticked, like the game's " ..
		"frames on the Game Frames page. Tick Always to leave an addon's frames alone (shown the " ..
		"whole time); the next three show them only while you fight or have something targeted, and " ..
		"the places while you're there."] .. "\n\n" ..
		L["To fade something else, use the Find frames tab: search by name, pick frames by hovering, or let " ..
		"Smart Find look for them. Or hover over a frame and type |cffffd100/cine add|r. Frames you add are " ..
		"listed under their addon, with the same columns; the X takes one off the list."] .. "\n\n" ..
		L["The Not running tab has the addons installed but not loaded, to set them up before you turn them " ..
		"on, and the ones supported but not installed."] .. "\n\n" ..
		L["The Default row is what frames you add, and addons you install later, start with; its Copy to all " ..
		"gives it to every row here."])
	local switch = PageSwitch(content, "handleAddonFrames", L["Enable Page"],
		L["On: CineMode fades the supported addons' frames, and frames you added, as this page says. " ..
		"Off: it leaves them all alone."], note)
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
	local tab = 1 -- (the tab picked: 1 Loaded, 2 Find frames, 3 Not running)
	-- (The Find frames tab's parts, made further down.)
	local smart, foundHead, noneFound
	local foundRows, foundCount = {}, 0
	local tabsPanel, ShowTab, tabsBase, tabsHeight, _
	local function PickTab(i)
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
	tabsPanel, _, ShowTab, tabsBase, tabsHeight = ns.FolderTabs(content, {
		{ L["Loaded"], L["The addons loaded now: their frames, and the ones you added."] },
		{ L["Find frames"], L["Find other addons' frames to fade: search, hover, or Smart Find."] },
		{ L["Not running"], L["Addons installed but not loaded, and the ones supported but not installed."] },
	}, PickTab)
	tabsBase:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -tabsHeight)
	tabsPanel:SetPoint("TOPLEFT", tabsBase, "TOPLEFT")
	tabsPanel:SetSize(PANEL_W, 1)
	box:SetPoint("TOPLEFT", tabsPanel, "TOPLEFT", 8, -10)

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
				tip = (L["Show %s the whole time in CineMode (Cinematic leaves them " ..
				"alone). Unticked, they're hidden, except as the other columns say.%s"]):format(known.about,
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
	Tooltip(copyAll, L["Gives every row on this page, supported addons and custom frames, the Default row's " ..
		"settings, replacing their own."])
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
			tip = L["Ticked, supported addons you install later start with Always ticked: shown the whole " ..
			"time in CineMode. Unticked, they start hidden, except as the other columns say. (Frames you add " ..
			"yourself start faded either way.)"] },
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
		for _, region in ipairs({ tools, headings, defaultRow, smart, foundHead, noneFound, missingNote }) do
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
			local group = Group(row.note.addon)
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
		L["Smart Find every 20 seconds while an addon is new to it (its first 15 minutes of play, for each " ..
		"addon you install that isn't supported), not in fights, so frames that come and go (another addon's " ..
		"popups) are caught while they're up. After that, look with the Smart Find button."])
	background:SetParent(smart) -- (its setting recorded on the page, for its Reset)
	background:SetPoint("TOPLEFT", smartTitle, "BOTTOMLEFT", -4, -6)
	local runButton = ns.PanelButton(tools)
	runButton:SetSize(120, 22)
	runButton:SetPoint("TOPLEFT", tools, "TOPLEFT", 384, -3) -- (right of Hover Find and its spinner)
	Tooltip(runButton, L["Looks for other addons' frames that nothing " ..
		"fades, on screen or hidden, and guesses which Game Frames row each stands in for. Load one to put " ..
		"it on the Loaded tab, under its addon, with the Default row's settings."] .. "\n\n" ..
		L["Looks once a second for a while, so a frame that only shows now and then is caught: " ..
		"bring it up while it runs. Click again to stop."])
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
		-- (Ones still to load first, then by name.)
		table.sort(names, function(a, b)
			local loadedA, loadedB = db.extraFrames[a] and true or false, db.extraFrames[b] and true or false
			if loadedA ~= loadedB then return loadedB end
			return a:lower() < b:lower()
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
	Tooltip(addMode, L["Hover over the frames you want (move this window out of the way, or close it), " ..
		"then click Stop: they go on the list below, to load. The game's own frames and ones already faded " ..
		"are left out. /cine add cancel drops them."])
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
	Tooltip(find, L["Type part of a frame's name or of the addon that made it. Hover over a match to see " ..
		"it marked on screen, click it to put it on the list below, to load. Only other addons' frames that " ..
		"aren't faded yet are listed."])

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
		tip = L["Turns CineMode on or off, leaving the rest of Cinematic running. Off lasts until you press " ..
			"it again or reload."] },
	{ action = "CINEMATIC_HIDEUI", label = L["Hide the UI"],
		tip = L["Like Blizzard's Alt+Z: hides the whole UI, but keeps the tint, letterbox " ..
			"and time-of-day title. Press again (or Blizzard's key) to bring it back. Not in a fight."] },
	{ action = "CINEMATIC_SCREENSHOT", label = L["Take a CineShot"],
		tip = L["Hides the UI but keeps the tint and letterbox, takes a screenshot, then brings the UI " ..
			"straight back. Not in a fight."] },
	{ action = "CINEMATIC_TOGGLEEFFECTS", label = L["Toggle visual effects"],
		tip = L["Turns the visual effects on or off (their Enable Visual Effects switch): the letterbox, tint, " ..
			"vignette, weather and the rest."] },
	{ action = "CINEMATIC_TOGGLELETTERBOX", label = L["Toggle letterbox bars"],
		tip = L["Brings the letterbox bars in, or takes them out, in or out of CineMode. Turning CineMode on " ..
			"or off puts them back as the Letterbox page says."] },
	{ action = "CINEMATIC_RELOAD", label = L["Reload the UI"],
		tip = L["Reloads the UI, like /reload. With Keep windows open across a reload ticked (Quality of " ..
			"life > General), what you had open opens again after."] },
	{ action = "CINEMATIC_TOGGLESETTINGS", label = L["Toggle settings"],
		tip = L["Opens Cinematic's settings at the page you were last on. Press it again to close them."] },
	{ action = "CINEMATIC_KEYMAP", label = L["Keyboard map"],
		tip = L["Hold to see your keyboard with what each key does (Shift, Ctrl and Alt show their keys too); let " ..
			"go and it's gone. Tap it instead and it stays up till you press it again. Its settings are on " ..
			"Quality of life > Keyboard Map."] },
	{ action = "CLICK CinematicMasterWheelButton:LeftButton", label = L["Master wheel"], section = L["Wheels"],
		tip = L["Hold to bring up a wheel of the wheels below (camera, menu, marker...): point at one and " ..
			"let go to open it, then click what you want on it. Tap it instead and the wheel stays up for you " ..
			"to click one. The camera wheel can't open in a fight."] },
	{ action = "CINEMATIC_CAMWHEEL", label = L["Camera wheel"],
		tip = L["Hold to bring up a wheel of the cameras on the Cameras tab, an icon " ..
			"for each: point at one and let go to start it. Tap it instead and the wheel stays up for you to " ..
			"click one. Picking the camera that's running stops it. It can't open in a fight."] },
	{ action = "CLICK CinematicMenuWheelButton:LeftButton", label = L["Menu wheel"],
		tip = L["Hold to bring up a wheel of the game's menu buttons (character, spellbook, quest log...), " ..
			"the ones on your menu bar: point at one and let go to open its window, even with the UI hidden. " ..
			"Tap it instead and the wheel stays up for you to click one."] },
	{ action = "CLICK CinematicMarkerWheelButton:LeftButton", label = L["Marker wheel"],
		tip = L["Hold to bring up a wheel of the raid target markers (skull, cross, square...) for your " ..
			"target, or with none, whatever the cursor is on: point at one and let go to put it on them, or at None to take theirs off. Tap it instead " ..
			"and the wheel stays up for you to click one."] },
	{ action = "CLICK CinematicWorldMarkerWheelButton:LeftButton", label = L["Ground marker wheel"],
		show = function() return ns.hasWorldMarkerWheel end,
		tip = L["Hold to bring up a wheel of the ground markers (the colored lights you drop on the floor): " ..
			"point at one and let go, and it drops under the cursor. Picking one that's down moves it; Clear " ..
			"all takes them all up. Tap it instead and the wheel stays up for you to click one. Only in a group."] },
	{ action = "CLICK CinematicVisionWheelButton:LeftButton", label = L["Vision wheel"],
		tip = L["Hold to bring up a wheel of the visions (Heal, Quest, Duel...), ringed while they're on: " ..
			"point at one and let go to turn it on or off, in a fight too. Tap it instead and the wheel stays " ..
			"up for you to click one."] },
	{ action = "CINEMATIC_VISION_HEAL", label = L["Toggle Heal Vision"], section = L["Visions"],
		tip = L["Turns Heal Vision on or off (its Enable Page switch), in a fight too: off, the party and " ..
			"raid frames all show again."] },
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
	{ action = "CINEMATIC_VISION_TELE", label = L["Toggle Tele Vision"],
		tip = L["Turns Tele Vision on or off (its Enable Page switch)."] },
	{ action = "CINEMATIC_VISION_EMOTE", label = L["Toggle Emote Vision"],
		tip = L["Turns Emote Vision on or off (its Enable Page switch)."] },
	{ action = "CINEMATIC_VISION_CARD", label = L["Toggle Card Vision"],
		tip = L["Turns Card Vision on or off (its Enable Page switch)."] },
	{ action = "CINEMATIC_CAM_IDLE", label = L["AFK camera"], section = L["Cameras"],
		tip = L["Starts the AFK camera now, without waiting out its delay. " ..
			"Press again, move or jump to stop it."] },
	{ action = "CINEMATIC_CAM_COZY", label = L["Cozy camera"],
		tip = L["Starts the cozy camera now, as if you'd sat down. Press again, move or jump to stop it."] },
	{ action = "CINEMATIC_CAM_VISTA", label = L["Vista camera"],
		tip = L["Starts the vista camera now, as if you'd done a /stare. Press again, move or jump to stop it."] },
	{ action = "CINEMATIC_CAM_FISH", label = L["Fish camera"],
		tip = L["Starts the fish camera now, without casting. Press again, move or jump to stop it."] },
	{ action = "CINEMATIC_CAM_TELE", label = L["Tele camera"],
		tip = L["Starts the tele camera now, as if you were casting your Hearthstone. Press again, move or " ..
			"jump to stop it."] },
	{ action = "CINEMATIC_CAM_WALK", label = L["RP walk camera"],
		tip = L["Starts the RP walk camera now, walking or not. Press again to stop it; its stop rules (its Scripts " ..
			"page) say what else does."] },
	{ action = "CINEMATIC_CAM_RUN", label = L["Auto-run camera"],
		tip = L["Starts the auto-run camera now, running or not. Press again to stop it; its stop rules (its Scripts " ..
			"page) say what else does."] },
	{ action = "CINEMATIC_CAM_DEATH", label = L["Death camera test"],
		tip = L["Pretends you're dead for 30 seconds so the death camera runs. Press again to stop. " ..
			"Like /cine deathtest."] },
	{ action = "CINEMATIC_STOPCAM", label = L["Stop the camera"],
		tip = L["Stops whichever of Cinematic's cameras is running now, however it started."] },
}
-- Your own scenes' keys (a trigger on the Triggers page set to Scene key N).
-- (number: put in the label as the page is built, once it's translated.)
for n = 1, 5 do
	KEYBINDS[#KEYBINDS + 1] = { action = "CINEMATIC_CUSTOMTRIGGER" .. n, label = "Scene key %d", number = n,
		section = n == 1 and L["Scene keys"] or nil,
		tip = L["Plays your scenes that use this key: on the Triggers page make a Key binding trigger for it, " ..
			"then pick that trigger for a scene on the Scenes page. Press again to stop it."] }
end
for _, each in ipairs({
	{ action = "CINEMATIC_SHOWTOOLTIPS", label = L["Show hidden tooltips"], section = L["Tooltips"],
		tip = L["Hold to see the tooltips the Tooltips page hides, in combat and in CineMode. Pressing it " ..
			"while you're on a unit or something in the world brings its tooltip up; anything else, " ..
			"hover it again with the key held."] },
	{ action = "CINEMATIC_TOGGLETOOLTIPS", label = L["Toggle tooltip hiding"],
		tip = L["Turns the Tooltips page on or off (its Enable Page switch)."] },
}) do KEYBINDS[#KEYBINDS + 1] = each end
if ns.ChatCamCommand then -- (ChatCam.lua)
	KEYBINDS[#KEYBINDS + 1] = { action = "CLICK CinematicChatTargetButton:LeftButton",
		label = L["Target the last speaker"], section = L["Chat Cam"],
		tip = L["Targets the last NPC who spoke near you (your character turns their head to them). " ..
			"Addons can't target on their own: the game only lets a key press do it. Out of fights."] }
end

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

local function RefreshKeybinds()
	for _, button in ipairs(keybindButtons) do
		local key = select(button.slot, GetBindingKey(button.action))
		if button == listening then
			button:SetText(L["Press a key"])
		else
			button:SetText(key and KeyText(key) or L["|cff808080Not bound|r"])
		end
	end
end

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
	Tooltip(button, L["Click, then press a key (with Shift, Ctrl or Alt if you like). " ..
		"Right-click to clear. Escape cancels."])
	keybindButtons[#keybindButtons + 1] = button
	return button
end

local function CreateKeybindsPanel()
	local canvas, content = CreateScrollPage()

	local title = Label(content, "GameFontNormalLarge", L["Keybinds"])
	title:SetPoint("TOPLEFT", 16, -16)

	local subtitle = PageIntro(content, title,
		L["Keys for Cinematic. These are the same bindings as under Key Bindings > AddOns, " ..
		"so setting them in either place works. The keys for wheels you make are on the Wheels page."])

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

	local section
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
		-- (A key for something this client doesn't have: no row.)
		if not bind.show or bind.show() then
			local body = section.body
			local label = Label(body, "GameFontHighlight", bind.number and bind.label:format(bind.number) or bind.label)
			label:SetPoint("TOPLEFT", section.last, "BOTTOMLEFT", 0, section.last == body and -4 or -12)
			label:SetWidth(200)
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
function ns.OpenOptions(page)
	page = MOVED_PAGES[page] or page
	-- (a UI Manager page: that page, then UI Manager open at it)
	page = page and HubTab(page) or page
	-- (some pages are registered by their name as shown)
	if page and not subpages[page] and subpages[L[page]] then page = L[page] end
	if InCombatLockdown() then
		local panel = category and SettingsPanel
		if panel and panel.SelectCategory and not panel:IsProtected() then
			panel:Show()
			panel:SelectCategory(subpages[page] or category)
		elseif not (panel and panel:IsShown()) then
			openAfterFight.page = page
			openAfterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
			ns.Print(L["settings can't be opened in combat; they'll open when the fight ends"])
		end
		return
	end
	if category and Settings and Settings.OpenToCategory then
		local target = subpages[page] or category
		Settings.OpenToCategory(target:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		-- Called twice: the first call can land on the wrong page in old clients.
		InterfaceOptionsFrame_OpenToCategory(subpages[page] or mainCanvas)
		InterfaceOptionsFrame_OpenToCategory(subpages[page] or mainCanvas)
	end
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
		L["A profile is a whole set of settings. Pick one to switch to it; changes you make go into the " ..
		"active profile and stay with it. The built-in ones keep your changes too, until you reset them. " ..
		"New profile starts one of your own from the settings you have now. Every character uses " ..
		"the same profile unless you tick the box below for one. Not part of a profile: the minimap button, frames you added or stopped fading, " ..
		"and the zone and time tint colors you picked."])

	-- Ticked, this character keeps the one it's on as its own.
	local perChar = Check(content, nil, L["Use a profile just for this character"],
		L["Ticked: switching profiles changes only this character's, and it stays on it whatever " ..
		"your other characters use. Unticked: this character uses the same profile as the rest " ..
		"(switching back to it now if this one's differs)."], function(value)
			ns.SetCharacterProfile(value)
			Refresh()
		end)
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
	local newTip = PROFILE_MENUS and L["A profile of your own, a copy of the active one as you have it now, named " ..
		"after it. To copy another profile, right-click it, then Copy profile."]
		or L["A profile of your own, a copy of the active one as you have it now, named after it. " ..
		"To copy another profile, switch to it first."]
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
	local backups = Button(buttons, L["Backups"], 90, L["Copies of your profiles from earlier days and from " ..
		"just before Delete or Reset, to bring one back as a new profile. Deleted profiles too."], function()
		ns.ShowBackups()
	end)
	backups:SetPoint("LEFT", buttons, "LEFT", 0, 0)
	local import = Button(buttons, L["Import"], 84, L["Add a profile someone shared with you, from the text they " ..
		"gave you. Your own profiles stay as they are."], function()
		ns.ShowImport()
	end)
	import:SetPoint("LEFT", backups, "RIGHT", 8, 0)
	local rename, note, delete, reset, export, savePoint
	if not PROFILE_MENUS then
		rename = Button(buttons, L["Rename"], 90, L["Rename the active profile (your own ones only)."], function()
			local name = ns.ActiveProfile()
			StaticPopup_Show("CINEMATIC_PROFILE_RENAME", nil, nil, name)
		end)
		rename:SetPoint("LEFT", import, "RIGHT", 8, 0)
		note = Button(buttons, L["Description"], 96, L["Write what the active profile is for, shown when you point " ..
			"at its icon (your own ones only)."], function()
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
		reset = Button(buttons, L["Reset"], 100, L["Put the active profile back to how you last saved it, or a " ..
			"built-in one back to its own values (your own profiles keep your changes as you go)."], AskResetProfile)
		reset:SetPoint("TOPLEFT", backups, "BOTTOMLEFT", 0, -8)
		export = Button(buttons, L["Export"], 84, L["The active profile as a line of text to copy and paste " ..
			"wherever your friends will see it, so they can import it (your own ones only: everyone has the built-in ones)."], function()
			ns.ShowExport()
		end)
		export:SetPoint("LEFT", reset, "RIGHT", 8, 0)
		savePoint = Button(buttons, L["Save"], 84, L["Keep the active profile as it is now: Reset and each " ..
			"page's Reset put it back to this instead of Cinematic's own settings."], function()
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
				root:CreateButton(L["Export"], function() ns.ShowExport(name) end)
			end
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
				or (PROFILE_MENUS and L["Your own profile. Right-click it, then Description to say what it's for."]
				or L["Your own profile. Pick it, then Description to say what it's for."])
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
			export:SetEnabled(own)
			savePoint:SetEnabled(active ~= nil)
		end
		FitContentHeight(content)
	end
	controls[#controls + 1] = { Refresh = function()
		if canvas:IsShown() then Layout() end
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
	title:SetPoint("TOPLEFT", LEFT, -16)
	local subtitle = PageIntro(content, title,
		L["Frames in the same group come up together when you mouse over any of them. A frame can " ..
		"be in more than one group; one in no group comes up on its own."] .. " " ..
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
	Tooltip(hold, L["How long until a frame is gone after your mouse leaves it (and its groups), fade " ..
		"included. Events that bring a group up hold it this long too. In the camera modes the " ..
		"shorter default is used."])
	GreyUnless(hold, function(db) return db.mouseover end)
	-- (The groups go back to the defaults with the rest of the page.)
	RecordKey(content, "hoverGroups")

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
		Tooltip(menu, L["Which parts of this frame come up with this group. An unticked part stays hidden while " ..
			"this group is what's bringing the frame up. Up for anything else, like a fight, it shows as usual."])
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
				Tooltip(button, L["When this group works: any time, only out of combat or only in combat. " ..
					"Click to change. The rest of the time its frames come up on their own (or with their other " ..
					"groups), and its events don't bring it up."])
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
				Tooltip(button, L["Turns this group on or off. While it's off it's kept as it is, but its frames " ..
					"come up on their own (or with their other groups), and its events don't bring it up."])
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
						Tooltip(slider, L["How close the mouse must come to this group's action bar buttons to " ..
							"bring it up, so the gaps between the buttons count too. 0: only on the buttons themselves."])
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
	controls[#controls + 1] = { Refresh = function()
		if canvas:IsShown() then Layout() end
	end }

	canvas:SetScript("OnShow", function()
		Refresh()
		Layout()
		C_Timer.After(0, function() FitContentHeight(content) end)
	end)
	canvas:SetScript("OnHide", function()
		results:Hide()
		picker:Hide()
	end)
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
		return ns.db and ns.db.forceReloadOnSettingsExit and InputUtil.IsGamepadUIEnabled()
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
		text = L["Floating text changes after you fully restart the game (/reload isn't enough). Exit the game now?"],
		button1 = EXIT_GAME or L["Exit game"], button2 = L["Later"],
		OnAccept = Quit,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}

	CreatePanel()
	CreateProfilesPanel()
	-- Sub-pages in the order they're listed: what fades and shows, then the look
	-- and sound, then the camera modes (their shared page and events first),
	-- keybinds. (Standard Frames and Advanced Frames come right after CineMode.)
	CreateRevealPanel()
	CreateCombatPanel()
	if ns.HasUnitFrameParts and ns.HasUnitFrameParts() then -- (nothing else on it)
		CreatePortraitsPanel()
	end
	if ns.CreatePersonalResourcesPanel then -- (PersonalResources.lua)
		ns.CreatePersonalResourcesPanel(ns.lowHealthKit)
	end
	if ns.CreateCursorHidePage then -- (CursorHide.lua)
		ns.CreateCursorHidePage(ns.lowHealthKit)
	end
	-- WoW Forever's gamepad mode (retail's has no frames of its own).
	if C_GamePad and not ns.isRetail then
		CreateGamepadPanel()
	end
	CreateExtrasPanel()
	CreateMouseoverPanel()
	CreateMinimapPanel()
	CreateQuestTrackerPanel()
	-- (Classic clients' own swing timer.)
	if not ns.isRetail then
		CreateSwingPanel()
	end
	-- (Only with a Cooldown Manager: the game's, on clients that have it, or the addon.
	-- ProfileModules.lua.)
	if ns.HasCooldownManager() then
		CreateCooldownPanel()
	end
	CreateTooltipPanel()
	-- (its hub listed after UI Manager's)
	CreateVisionPanel()
	if ns.CreateVitalsVisionPanel then -- (LowHealth.lua)
		ns.CreateVitalsVisionPanel(ns.lowHealthKit)
	end
	if ns.CreateCardsPanel then -- (CardsPage.lua)
		ns.CreateCardsPanel(ns.lowHealthKit)
		ns.CreateCardStylesPanel(ns.lowHealthKit)
		ns.CreateCardSettingsPanel(ns.lowHealthKit)
		ns.CreateCardStylePanel(ns.lowHealthKit)
		ns.CreateCardSoundsPanel(ns.lowHealthKit)
	end
	if ns.CreateWindGuidePanel then -- (WindGuide.lua: the dev copy only, CinematicDev.toc)
		ns.CreateWindGuidePanel(ns.lowHealthKit)
	end
	if ns.CreateDamageVisionPanel then -- (DamageVision.lua)
		ns.CreateDamageVisionPanel(ns.lowHealthKit)
		ns.CreateDamageVisionLookPanel(ns.lowHealthKit)
	end
	if ns.CreateTeleportVisionPanel then -- (TeleportVision.lua)
		ns.CreateTeleportVisionPanel(ns.lowHealthKit)
	end
	if ns.CreateEmoteVisionPanel then -- (EmoteVision.lua)
		ns.CreateEmoteVisionPanel(ns.lowHealthKit)
		ns.CreateEmoteVisionSettingsPanel(ns.lowHealthKit)
		ns.CreateEmoteVisionStylePanel(ns.lowHealthKit)
	end
	CreateBuffsPanel()
	CreatePlatesPanel()
	CreateChatPanel()
	CreateBubblesPanel()
	-- (their hub, Style, listed after Visions)
	CreateNameStylePanel()
	CreateTargetArrowPanel()
	if ns.CreateLetterboxStylePanel then -- (LetterboxStyle.lua)
		ns.CreateEffectPanel(ns.lowHealthKit, "letterbox")
		ns.CreateLetterboxStylePanel(ns.lowHealthKit)
	end
	if ns.CreateQuestItemStylePanel then -- (QuestItemStyle.lua)
		ns.CreateQuestItemStylePanel(ns.lowHealthKit)
	end
	if ns.CreateRollStylePanel then -- (RollStyle.lua)
		ns.CreateRollStylePanel(ns.lowHealthKit)
	end
	if ns.CreateVitalsStylePanel then -- (LowHealth.lua)
		ns.CreateVitalsStylePanel(ns.lowHealthKit)
	end
	if ns.CreateQuestTalkStylePanel then -- (QuestTalkStyle.lua)
		ns.CreateQuestTalkStylePanel(ns.lowHealthKit)
	end
	if ns.CreateBubbleStylePanel then -- (BubbleStyle.lua)
		ns.CreateBubbleStylePanel(ns.lowHealthKit)
	end
	if ns.CreateTooltipStylePanel then -- (TooltipStyle.lua)
		ns.CreateTooltipStylePanel(ns.lowHealthKit)
	end
	if ns.CreateActionBarStylePanel then -- (ActionBarStyle.lua)
		ns.CreateActionBarStylePanel(ns.lowHealthKit)
	end
	if ns.CreatePersonalStylePanel then -- (PersonalStyle.lua)
		ns.CreatePersonalStylePanel(ns.lowHealthKit)
	end
	if ns.CreateUnitStylePanel then -- (UnitStyle.lua)
		ns.CreateUnitStylePanel(ns.lowHealthKit)
	end
	if ns.CreateRaidStylePanel then -- (RaidStyle.lua)
		ns.CreateRaidStylePanel(ns.lowHealthKit)
	end
	if ns.CreateGeneralStylePanel then -- (GeneralStyle.lua)
		ns.CreateGeneralStylePanel(ns.lowHealthKit)
		ns.CreateStylePagesPanel(ns.lowHealthKit)
		ns.CreateStyleOverridesPanel(ns.lowHealthKit)
	end
	if ns.CreateVisionsStylePanel then -- (VisionsStyle.lua)
		ns.CreateVisionsStylePanel(ns.lowHealthKit)
	end
	if ns.CreatePlateCastStylePanel then -- (PlateCastStyle.lua)
		ns.CreatePlateCastStylePanel(ns.lowHealthKit)
	end
	CreateEffectsPanel()
	ns.CreateEffectPanel(ns.lowHealthKit, "tint") -- (LetterboxStyle.lua: its Show in row)
	CreateTintPanel()
	CreateGraphicsPanel()
	CreateAudioPanel()
	CreateCamerasPanel()
	if ns.CreateTriggersPanels then -- (TriggersPage.lua)
		ns.CreateTriggersPanels(ns.lowHealthKit)
	end
	-- Each camera's own settings, in a section apiece.
	CreateCameraSettingsPanel()
	if ns.CreateMyShotsPanel and not ns.SHOTS_RETIRED then -- (ShotsPage.lua; retired in the dev copy)
		ns.CreateMyShotsPanel(ns.lowHealthKit)
	end
	if ns.CreateShoulderCamPanel then -- (ShoulderCam.lua)
		ns.CreateShoulderCamPanel(ns.lowHealthKit)
	end
	if ns.CreateSkyrideCamPanel then -- (SkyrideCam.lua: retail)
		ns.CreateSkyrideCamPanel(ns.lowHealthKit)
	end
	if ns.CreateCameraScriptsPanel then -- (CameraScriptsPage.lua)
		ns.CreateCameraScriptsPanel(ns.lowHealthKit)
	end
	if ns.CreateWheelsPanels then -- (WheelsPage.lua; its hub listed after Camera)
		ns.CreateWheelsPanels(ns.lowHealthKit)
	end
	CreateFishingPanel()
	CreateQualityPanel()
	if ns.CreateKeyboardMapPage then -- (KeyboardMap.lua)
		ns.CreateKeyboardMapPage(ns.lowHealthKit)
	end
	CreateKeybindsPanel()
	-- Community, last (WhatsNew.lua, with the helpers it shares from here).
	if ns.CreateWhatsNewPanels then
		ns.CreateWhatsNewPanels({ CreateScrollPage = CreateScrollPage, Label = Label, PageShown = PageShown,
			RegisterSubpage = RegisterSubpage, Tooltip = Tooltip })
	end
	if ns.CreateProfilerPanel then -- (ProfilerPage.lua: Community's last page)
		ns.CreateProfilerPanel(ns.lowHealthKit)
	end
	if ns.CreateWhyPanel then -- (Why.lua: after the Profiler, in Community's Help)
		ns.CreateWhyPanel(ns.lowHealthKit)
	end
	-- The dev build's Module Editor, Community's last page (ModuleEditor.lua).
	if ns.isDev and ns.CreateModuleEditor then
		ns.CreateModuleEditor({ CreateScrollPage = CreateScrollPage, Label = Label, PageShown = PageShown,
			RegisterSubpage = RegisterSubpage, Tooltip = Tooltip, PageIntro = PageIntro, Header = Header })
	end
	if ns.isDev and ns.CreateHeldSettingsPage then -- (HeldSettingsPage.lua: the Dev hub)
		ns.CreateHeldSettingsPage(ns.lowHealthKit)
	end
	if ns.isDev and ns.CreateDemoHubPage then -- (DemoHub.lua: the Dev hub)
		ns.CreateDemoHubPage(ns.lowHealthKit)
	end
	GuardGamepadClose()
end)
