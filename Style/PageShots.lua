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
-- its right edge, and text under a bar of another part (a preview's plates
-- over the rows, 2026-11-17). Only what's shown (a closed section's or
-- another tab's not). Also ns.PageLayoutFindings, for /cine debug sweep.
local function Measure(canvas)
	local root = canvas.content or canvas
	-- (A page that puts its own scroll away (Why Is It Showing?, its list in
	-- a box of its own): its edge the page's, not the hidden scroll's.)
	local pageScroll = canvas.scroll and ns.Flag(canvas.scroll:IsShown()) and canvas.scroll or nil
	local right = (pageScroll or root or canvas):GetRight()
	local cut, over, past, under, covered, texts, bars = {}, {}, {}, {}, {}, {}, {}
	local pastSeen = {}
	local clip -- (the box the nearest clipping frame (a scroll box, a preview) shows: walk)
	-- (Only text in the page's view counts for overlaps: rows scrolled out of
	-- it are cut off by it, whatever's drawn there.)
	local view = pageScroll
	local viewBottom, viewTop = view and view:GetBottom(), view and view:GetTop()
	-- (A style preview (StylePages.lua marks it stackSpot): its own labels on
	-- its own bars are how it's drawn, not an overlap.)
	local function PreviewOf(frame)
		local depth = 0
		while frame and depth < 12 do
			if frame.stackSpot then return frame end
			frame, depth = frame:GetParent(), depth + 1
		end
	end
	-- (Faded to nothing (a hidden label kept at alpha 0, a card over the
	-- page): seen as nothing, so no overlap. 2026-11-17's false ones.)
	local function Seen(frame, region)
		local ok, alpha = pcall(frame.GetEffectiveAlpha, frame)
		alpha = ok and tonumber(alpha) or 1
		if region and region.GetAlpha then alpha = alpha * (tonumber(region:GetAlpha()) or 1) end
		return alpha > 0.05
	end
	-- (A card over the page (layoutCover: Cursor Hide's Experimental one):
	-- what's under it isn't seen.)
	local covers = {}
	local function CoverOf(frame)
		local depth = 0
		while frame and depth < 30 do
			if frame.layoutCover then return frame end
			frame, depth = frame:GetParent(), depth + 1
		end
	end
	local function walk(frame, depth)
		if depth > 30 or not ns.Flag(frame:IsVisible()) then return end
		-- (layoutSkip: drawn over the page on purpose, moving, not laid out:
		-- Combat Text Style's sample numbers.)
		if frame.layoutSkip then return end
		if frame.layoutCover then
			local l, b, w, h = frame:GetRect()
			if l and w then covers[#covers + 1] = { frame = frame, l = l, b = b, r = l + w, t = b + h } end
		end
		local isButton = frame.GetObjectType and frame:GetObjectType() == "Button"
		if frame.GetObjectType and frame:GetObjectType() == "StatusBar" and Seen(frame) then
			local l, b, w, h = frame:GetRect()
			if l and w and w > 0 and h > 0 then
				bars[#bars + 1] = { frame = frame, l = l, b = b, r = l + w, t = b + h, preview = PreviewOf(frame) }
			end
		end
		for _, region in ipairs({ frame:GetRegions() }) do
			if region.IsTruncated and ns.Flag(region:IsVisible()) then
				local words = Text(region)
				if words then
					local wide = isButton and region:GetStringWidth() > frame:GetWidth() + 1
					if wide or ns.Flag(region:IsTruncated()) then Add(cut, words) end
					local l, b, w, h = region:GetRect()
					local inView = not (viewBottom and viewTop) or (l and b + h > viewBottom + 2 and b < viewTop - 2)
					if l and w and w > 0 and h > 0 and inView and Seen(frame, region) then
						local text = { words = words, l = l, b = b, r = l + math.min(w, region:GetStringWidth()), t = b + h,
							frame = frame, preview = PreviewOf(frame) }
						-- (In a clipping box (a list scrolling in its own box): only
						-- the part it shows; one wholly outside it isn't drawn.)
						if clip then
							text.l, text.r = math.max(text.l, clip.l), math.min(text.r, clip.r)
							text.b, text.t = math.max(text.b, clip.b), math.min(text.t, clip.t)
						end
						-- (And to the page's view: a line half scrolled out of it
						-- is drawn only inside. 2026-11-18: Name Style's, 4 px over
						-- the top, "under" the preview held above it.)
						if viewBottom and viewTop then
							text.b, text.t = math.max(text.b, viewBottom), math.min(text.t, viewTop)
						end
						if text.r - text.l > 1 and text.t - text.b > 1 then texts[#texts + 1] = text end
					end
				end
			end
		end
		-- (Inside a frame that clips (a preview): only what shows in it counts;
		-- one wholly outside it is drawn nowhere.)
		local l, r = frame:GetLeft(), frame:GetRight()
		local b, t = frame:GetBottom(), frame:GetTop()
		local hidden = clip and l and r and b and t and (l >= clip.r or r <= clip.l or b >= clip.t or t <= clip.b)
		if right and r and r > right + 2 and frame ~= root and not hidden then
			-- (Shown past its clip's edge: only as far as the clip shows it.)
			local shownRight = clip and math.min(r, clip.r) or r
			-- (Named by its words, else its kind, size and the words of what
			-- it's in: "Frame (+2023)" told nothing.)
			local name = FirstText(frame)
			if not name then
				local parent = frame:GetParent()
				local w, h = frame:GetSize()
				name = ("%s %dx%d in %s"):format(frame:GetObjectType(), tonumber(w) or 0, tonumber(h) or 0,
					parent and (FirstText(parent) or parent:GetObjectType()) or "?")
			end
			if shownRight > right + 2 and not pastSeen[name] then
				pastSeen[name] = true
				Add(past, ("%s (+%d)"):format(name, shownRight - right))
			end
		end
		local was = clip
		local clips = frame:GetObjectType() == "ScrollFrame"
			or (frame.DoesClipChildren and ns.Flag(frame:DoesClipChildren()))
		if clips and l and r and b and t then
			clip = { l = was and math.max(l, was.l) or l, r = was and math.min(r, was.r) or r,
				b = was and math.max(b, was.b) or b, t = was and math.min(t, was.t) or t }
		end
		if not hidden then
			for _, child in ipairs({ frame:GetChildren() }) do walk(child, depth + 1) end
		end
		clip = was
	end
	pcall(walk, root, 0)
	-- (Text under a cover, not on it: dropped.)
	if #covers > 0 then
		local kept = {}
		for _, text in ipairs(texts) do
			local own, hid = CoverOf(text.frame), false
			for _, cover in ipairs(covers) do
				if cover.frame ~= own and text.l >= cover.l - 1 and text.r <= cover.r + 1
					and text.b >= cover.b - 1 and text.t <= cover.t + 1 then hid = true end
			end
			if not hid then kept[#kept + 1] = text end
		end
		texts = kept
	end
	-- (Text over text: two lines' boxes crossing by more than 3 px each way.)
	for i = 1, #texts do
		local a = texts[i]
		for j = i + 1, #texts do
			local b = texts[j]
			local x = math.min(a.r, b.r) - math.max(a.l, b.l)
			local y = math.min(a.t, b.t) - math.max(a.b, b.b)
			if x > 3 and y > 3 and a.words ~= b.words and not (a.preview and a.preview == b.preview) then
				Add(over, ("%s / %s"):format(a.words, b.words))
			end
		end
	end
	-- (Text under a bar: crossing by more than 3 px each way, the bar not the
	-- text's own (its own number, its own name on it).)
	local function Within(frame, bar)
		local depth = 0
		while frame and depth < 8 do
			if frame == bar or frame == bar:GetParent() then return true end
			frame, depth = frame:GetParent(), depth + 1
		end
	end
	for _, text in ipairs(texts) do
		for _, bar in ipairs(bars) do
			local x = math.min(text.r, bar.r) - math.max(text.l, bar.l)
			local y = math.min(text.t, bar.t) - math.max(text.b, bar.b)
			if x > 3 and y > 3 and not Within(text.frame, bar.frame)
				and not (text.preview and text.preview == bar.preview) then
				Add(under, text.words)
				break
			end
		end
	end
	-- (Text under a style preview: the preview found wherever it's hung (a
	-- sticky one's lifted onto the hub, 2026-11-17: one left full size there
	-- covers the rows scrolling under it), the page's text in view under it.)
	local top = canvas
	while top:GetParent() and top:GetParent() ~= UIParent do top = top:GetParent() end
	local previews = {}
	local function find(frame, depth)
		if depth > 25 or not ns.Flag(frame:IsVisible()) then return end
		if frame.stackSpot then
			local l, b, w, h = frame:GetRect()
			local scale = frame:GetEffectiveScale() / math.max(root:GetEffectiveScale(), 0.01)
			if l and w and w > 0 and h > 0 then
				previews[#previews + 1] = { frame = frame, l = l * scale, b = b * scale, r = (l + w) * scale, t = (b + h) * scale }
			end
			return
		end
		for _, child in ipairs({ frame:GetChildren() }) do find(child, depth + 1) end
	end
	pcall(find, top, 0)
	-- (And one popped out into its own window: on the screen, not the settings.)
	local window = _G.CinematicPreviewWindow
	if window and ns.Flag(window:IsVisible()) then pcall(find, window, 0) end
	for _, text in ipairs(texts) do
		for _, preview in ipairs(previews) do
			local x = math.min(text.r, preview.r) - math.max(text.l, preview.l)
			local y = math.min(text.t, preview.t) - math.max(text.b, preview.b)
			if x > 3 and y > 3 and text.preview ~= preview.frame then
				-- (Its state with it, so a run says why: held in the hub's corner
				-- or on its page, how far along, its size, and where it sits
				-- against the page's view top. 2026-11-18.)
				local frame, pin = preview.frame, preview.frame.pin
				local state = ("%s t %.2f, scale %.2f, %dx%d, bottom %+d from view top, crossing %dx%d"):format(
					pin and pin.on and "held" or "on page", pin and pin.t or 0, frame:GetScale() or 1,
					preview.r - preview.l, preview.t - preview.b,
					viewTop and (preview.b - viewTop) or 0, x, y)
				Add(covered, ("%s [%s]"):format(text.words, state))
				break
			end
		end
	end
	return cut, over, past, under, covered
end
ns.PageLayoutFindings = Measure

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
ns.PageTabSets = TabSets -- (/cine debug sweep, Dev/Sweep.lua: clicks through them too)

-- One look at the page as it is now (its tabs picked: path): measured, then
-- shot a screenful at a time, top down. Then done().
local function ShootState(ctx, path, done)
	local canvas, entry, token = ctx.page.canvas, ctx.entry, ctx.token
	local state = { tabs = path ~= "" and path or nil, shots = {} }
	entry.states[#entry.states + 1] = state
	state.cut, state.over, state.past, state.under, state.covered = Measure(canvas)
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
		-- (Then the page's other parts, each an icon of its own on its canvas
		-- (canvas.hubTabs: Nameplate Style's Smart, the HUD's sections): its
		-- tab row's left out as pages of their own, so these were never shot.)
		local parts = {}
		for _, part in ipairs(page.canvas.hubTabs or {}) do
			if part.name and part.name ~= page.key then parts[#parts + 1] = part end
		end
		local function Part(n)
			if run ~= token then return end
			local part = parts[n]
			if not part or not ns.ShowHubPage then
				Shots(pages, index + 1, last, token, out)
				return
			end
			pcall(ns.ShowHubPage, part.name)
			C_Timer.After(OPEN_WAIT, function()
				if run ~= token then return end
				if not ns.Flag(page.canvas:IsVisible()) then return Part(n + 1) end
				Explore(ctx, {}, part.label or part.name, function() Part(n + 1) end)
			end)
		end
		Explore(ctx, {}, "", function() Part(1) end)
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
	-- (Page words in place of numbers: only the pages whose name has them, as
	-- the sweep's, "/cine debug pageshots combat text".)
	if arg ~= "" and not arg:match("^%d") then
		local kept = {}
		for _, page in ipairs(pages) do
			local name = tostring(page.name or ""):lower()
			if name:find(arg, 1, true) then kept[#kept + 1] = page end
		end
		if #kept == 0 then
			ns.Print("pageshots: no page has \"" .. arg .. "\" in its name")
			return
		end
		pages, arg = kept, ""
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
