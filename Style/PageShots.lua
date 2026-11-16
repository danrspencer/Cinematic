-- /cine debug pageshots [first] [last] | off: a screenshot of every settings
-- page, for looking them over outside the game. Each page in turn is opened
-- (ns.OpenOptions, as /cine find does) and shot from its top down, one
-- screenful at a time; a strip along the screen's top names the page and
-- part. Each page's layout is measured too, by the game's own fonts: words cut
-- off, text that runs over other text, and parts sticking out past the page's
-- right edge. All of it goes to db.pageShots (each shot's file time, to find
-- its WoWScrnShot_ file), so "check log" is enough.
-- Every folder tab on a page is clicked through too (tabs in tabs as well:
-- a Style page's Player, Target... and their own rows), each one shot.
-- Nothing is changed: only the page shown, its tabs (each row's pick put
-- back) and its scroll. A fight stops it. Closed sections stay closed.

local _, ns = ...

local OPEN_WAIT, TAB_WAIT, SCROLL_WAIT, AFTER_SHOT = 1.0, 0.6, 0.5, 0.8 -- (seconds; shots 1 s+ apart, files named by the second)
local MAX_PARTS, MAX_FINDINGS, MAX_STATES = 8, 15, 30
local STRIP_H = 26

local strip, label, watcher -- (made once)
local run -- (the run going: a token, replaced to stop it)

local function Strip()
	if strip then return end
	strip = CreateFrame("Frame", nil, UIParent)
	strip:SetFrameStrata("TOOLTIP")
	strip:SetPoint("TOPLEFT")
	strip:SetPoint("TOPRIGHT")
	strip:SetHeight(STRIP_H)
	local back = strip:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.85)
	label = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", 12, 0)
	strip:Hide()
end

local function Shoot() Screenshot() end -- (a function of ours: C_Timer refused the game's)

local function Text(region)
	local ok, words = pcall(region.GetText, region)
	if ok and type(words) == "string" and words ~= "" then
		return (words:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " "):sub(1, 40))
	end
end

-- The first words in a frame (to name a control in the log).
local function FirstText(frame, depth)
	depth = depth or 0
	if depth > 4 then return nil end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetText then
			local words = Text(region)
			if words then return words end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local words = FirstText(child, depth + 1)
		if words then return words end
	end
end

local function Add(list, line)
	if #list < MAX_FINDINGS then list[#list + 1] = line end
	list.total = (list.total or 0) + 1
end

-- A page's layout by the game's measure: cut words, text over text, parts past
-- its right edge. Only what's shown (a closed section's or another tab's not).
local function Measure(canvas)
	local root = canvas.content or canvas
	local right = (canvas.scroll or canvas):GetRight()
	local cut, over, past, texts = {}, {}, {}, {}
	local pastSeen = {}
	local function walk(frame, depth)
		if depth > 30 or not ns.Flag(frame:IsVisible()) then return end
		local isButton = frame.GetObjectType and frame:GetObjectType() == "Button"
		for _, region in ipairs({ frame:GetRegions() }) do
			if region.IsTruncated and ns.Flag(region:IsVisible()) then
				local words = Text(region)
				if words then
					local wide = isButton and region:GetStringWidth() > frame:GetWidth() + 1
					if wide or ns.Flag(region:IsTruncated()) then Add(cut, words) end
					local l, b, w, h = region:GetRect()
					if l and w and w > 0 and h > 0 then
						texts[#texts + 1] = { words = words, l = l, b = b, r = l + math.min(w, region:GetStringWidth()), t = b + h }
					end
				end
			end
		end
		local r = frame:GetRight()
		if right and r and r > right + 2 and frame ~= root then
			local name = FirstText(frame) or frame:GetObjectType()
			if not pastSeen[name] then
				pastSeen[name] = true
				Add(past, ("%s (+%d)"):format(name, r - right))
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do walk(child, depth + 1) end
	end
	pcall(walk, root, 0)
	-- (Text over text: two lines' boxes crossing by more than 3 px each way.)
	for i = 1, #texts do
		local a = texts[i]
		for j = i + 1, #texts do
			local b = texts[j]
			local x = math.min(a.r, b.r) - math.max(a.l, b.l)
			local y = math.min(a.t, b.t) - math.max(a.b, b.b)
			if x > 3 and y > 3 and a.words ~= b.words then
				Add(over, ("%s / %s"):format(a.words, b.words))
			end
		end
	end
	return cut, over, past
end

local function Finish(text)
	run = nil
	if strip then strip:Hide() end
	if watcher then watcher:UnregisterAllEvents() end
	ns.Print(text)
	ns.Log("cmd", text)
end

-- The folder tab rows shown on a page now (ns.FolderTabs marks its tabs), in
-- the order met top down; a hub's page tabs (shotSkip) left out: each of those
-- is a page of its own, shot in its turn.
local function TabSets(root)
	local sets, seen = {}, {}
	local function walk(frame, depth)
		if depth > 30 or not ns.Flag(frame:IsVisible()) then return end
		local set = frame.shotSet
		if set and not set.shotSkip and not seen[set] then
			seen[set] = true
			sets[#sets + 1] = set
		end
		for _, child in ipairs({ frame:GetChildren() }) do walk(child, depth + 1) end
	end
	pcall(walk, root, 0)
	return sets
end

-- One look at the page as it is now (its tabs picked: path): measured, then
-- shot a screenful at a time, top down. Then done().
local function ShootState(ctx, path, done)
	local canvas, entry, token = ctx.page.canvas, ctx.entry, ctx.token
	local state = { tabs = path ~= "" and path or nil, shots = {} }
	entry.states[#entry.states + 1] = state
	state.cut, state.over, state.past = Measure(canvas)
	local scroll = canvas.scroll
	local range, view = 0, canvas:GetHeight() or 0
	if scroll and scroll.GetVerticalScrollRange then
		range, view = scroll:GetVerticalScrollRange() or 0, scroll:GetHeight() or view
	end
	state.range, state.view = math.floor(range), math.floor(view)
	local step = math.max(100, view * 0.85)
	local parts = range < 4 and 1 or math.min(MAX_PARTS, 1 + math.ceil(range / step))
	state.parts = parts
	local function Part(part)
		if run ~= token then return end
		if part > parts then
			if scroll then scroll:SetVerticalScroll(0) end
			done()
			return
		end
		if scroll and parts > 1 then scroll:SetVerticalScroll(math.min(range, (part - 1) * step)) end
		C_Timer.After(part == 1 and 0.1 or SCROLL_WAIT, function()
			if run ~= token then return end
			GameTooltip:Hide()
			label:SetText(("Cinematic pageshots %d/%d: %s%s - part %d/%d"):format(ctx.index, ctx.last, entry.label,
				path ~= "" and (" > " .. path) or "", part, parts))
			strip:Show()
			state.shots[#state.shots + 1] = date("%m%d%y_%H%M%S")
			ctx.out.shotCount = ctx.out.shotCount + 1
			Shoot()
			C_Timer.After(AFTER_SHOT, function() Part(part + 1) end)
		end)
	end
	Part(1)
end

-- Every tab of the page's first tab row not yet gone through, each in turn,
-- and the rows a tab brings up under it the same way (tabs in tabs); the page
-- shot at each end. The row's own pick put back after. Up to MAX_STATES looks
-- a page; a tab that leaves the page (opens another) ends its row.
local function Explore(ctx, visited, path, done)
	if run ~= ctx.token then return end
	local canvas = ctx.page.canvas
	local set
	for _, each in ipairs(TabSets(canvas.content or canvas)) do
		if not visited[each] then set = each break end
	end
	if not set or #ctx.entry.states >= MAX_STATES then
		ShootState(ctx, path, done)
		return
	end
	local inner = {}
	for k in pairs(visited) do inner[k] = true end
	inner[set] = true
	local was = set.picked or 1
	local order = {}
	for i, tab in ipairs(set) do
		if tab:IsShown() then order[#order + 1] = i end
	end
	local left -- (a tab of this row opened another page: its pick isn't clicked back)
	local function Next(n)
		if run ~= ctx.token then return end
		if n > #order or #ctx.entry.states >= MAX_STATES then
			if set[was] and not left and ns.Flag(canvas:IsVisible()) then pcall(set[was].Click, set[was]) end
			C_Timer.After(TAB_WAIT, done)
			return
		end
		local tab = set[order[n]]
		pcall(tab.Click, tab)
		C_Timer.After(TAB_WAIT, function()
			if run ~= ctx.token then return end
			local name = Text(tab.label or tab) or ("tab " .. order[n])
			local here = path ~= "" and (path .. " > " .. name) or name
			if not ns.Flag(canvas:IsVisible()) then
				ctx.entry.left = (ctx.entry.left and ctx.entry.left .. ", " or "") .. here
				left = true
				pcall(ns.OpenOptions, ctx.page.key)
				C_Timer.After(OPEN_WAIT, function()
					if run ~= ctx.token then return end
					-- (Nothing shot of the page yet: it is, as it opens.)
					if #ctx.entry.states == 0 and ns.Flag(canvas:IsVisible()) then
						ShootState(ctx, path, function() Next(#order + 1) end)
					else
						Next(#order + 1)
					end
				end)
				return
			end
			Explore(ctx, inner, here, function() Next(n + 1) end)
		end)
	end
	Next(1)
end

local function Shots(pages, index, last, token, out)
	if run ~= token then return end
	if index > last then
		out.done = date("%H:%M:%S")
		Finish(("pageshots: done, %d pages, %d shots - say \"check log\""):format(out.pageCount, out.shotCount))
		return
	end
	token.at = index
	local page = pages[index]
	local name = page.key or "Cinematic"
	local ok, err = pcall(ns.OpenOptions, page.key)
	if not ok then
		out.pages[#out.pages + 1] = { index = index, page = name, error = tostring(err) }
		Shots(pages, index + 1, last, token, out)
		return
	end
	C_Timer.After(OPEN_WAIT, function()
		if run ~= token then return end
		local entry = { index = index, page = name, label = ns.PageLabel and ns.PageLabel(name) or name, states = {} }
		out.pages[#out.pages + 1] = entry
		out.pageCount = out.pageCount + 1
		if not ns.Flag(page.canvas:IsVisible()) then
			entry.error = "didn't show"
			Shots(pages, index + 1, last, token, out)
			return
		end
		local ctx = { page = page, entry = entry, token = token, out = out, index = index, last = last }
		Explore(ctx, {}, "", function() Shots(pages, index + 1, last, token, out) end)
	end)
end

function ns.PageShots(arg)
	arg = (arg or ""):lower()
	if arg == "off" then
		if run then Finish("pageshots: stopped") else ns.Print("pageshots: not running") end
		return
	end
	if InCombatLockdown() then
		ns.Print("pageshots: not in a fight (the settings can't open)")
		return
	end
	local pages = ns.SettingsPages and ns.SettingsPages()
	if not pages or #pages == 0 then
		ns.Print("pageshots: no settings pages yet")
		return
	end
	local first, last = arg:match("^(%d+)%s*(%d*)$")
	first = tonumber(first) or 1
	last = math.min(#pages, tonumber(last) or #pages)
	if first > last then
		ns.Print(("pageshots: pages go 1 to %d"):format(#pages))
		return
	end
	Strip()
	if not watcher then
		watcher = CreateFrame("Frame")
		watcher:SetScript("OnEvent", function()
			if run then Finish("pageshots: stopped by a fight; carry on with /cine debug pageshots " .. (run.at or 1)) end
		end)
	end
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	local db = ns.GetDB()
	local out = { started = date("%m/%d/%y %H:%M:%S"), version = ns.Version and ns.Version() or "?",
		client = ns.isRetail and "retail" or (ns.isClassicEra and "classic era" or "forever"),
		screen = _G.GetPhysicalScreenSize and ("%dx%d"):format(_G.GetPhysicalScreenSize()) or "?", uiScale = ("%.2f"):format(UIParent:GetEffectiveScale()),
		first = first, last = last, total = #pages, pageCount = 0, shotCount = 0, pages = {} }
	if db then db.pageShots = out end
	local token = {}
	run = token
	ns.Print(("pageshots: %d pages, about %d min - leave the mouse off the window; /cine debug pageshots off stops"):format(
		last - first + 1, math.ceil((last - first + 1) * 6 / 60)))
	Shots(pages, first, last, token, out)
end
