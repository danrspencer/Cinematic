-- /cine debug lookdock: a Look panel and the popped preview both in sight on
-- every Style page with a preview (the user's ask, 2026-11-19). Nothing to do
-- but watch: for each settings page with a button that opens a Look panel
-- (button.opensLook: rows.Look's, and the rows that make theirs on a first
-- click), it opens the page, pops its preview out, opens that Look panel
-- docked (its button's click run straight: works with the page off too),
-- and checks:
--   both shown          the preview window not hidden for the panel
--   no overlap          the two windows don't cover each other
--   on screen           the panel's whole height inside the screen
--   settings clear      neither covers the settings window
--   not empty           the panel shows its rows (6 words or more)
--   one preview         one preview in sight, not two (pages with no
--                       Look panel are checked for this too)
--   under               the panel hung under the preview (else where the
--                       preview went: above or left of the settings)
-- then closes the panel and checks the preview is back beside the settings.
-- A screenshot a page (skipped ones too). Into CinematicDB.lookDockTestLog, a verdict a page
-- and a count at the end. Both run docked: spots you dragged the panel or
-- the preview window to, the preview's Pop out and the page opened are put
-- back after. Pages with their Look rows on a tab count too. Run again to
-- stop it.
-- Dev copy only.
local _, ns = ...

local OPEN_WAIT, LOOK_WAIT, CLOSE_WAIT = 1.0, 1.0, 0.6 -- seconds

local run -- { at, pages, index, pass, fail, kept }

local function Say(text)
	local log = CinematicDB and CinematicDB.lookDockTestLog
	if log then log[#log + 1] = ("%s %.1f %s"):format(date("%H:%M:%S"), run and GetTime() - run.at or 0, text) end
end
local function Shot(what)
	local ok = pcall(function() Screenshot() end)
	Say(("  screenshot %s at %s%s"):format(what, date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
end

-- A frame's box in screen pixels (frames with scales of their own compare).
local function Box(frame)
	if not (frame and frame:IsVisible() and frame:GetLeft()) then return end
	local k = frame:GetEffectiveScale()
	return { l = frame:GetLeft() * k, r = frame:GetRight() * k, t = frame:GetTop() * k, b = frame:GetBottom() * k }
end
local function BoxText(box)
	if not box then return "none" end
	return ("%.0f,%.0f to %.0f,%.0f"):format(box.l, box.b, box.r, box.t)
end
-- (Covering each other by more than 2 pixels either way: a shared edge isn't.)
local function Overlap(a, b)
	if not (a and b) then return false end
	return math.min(a.r, b.r) - math.max(a.l, b.l) > 2 and math.min(a.t, b.t) - math.max(a.b, b.b) > 2
end
local function TopWindow(frame)
	while frame and frame:GetParent() and frame:GetParent() ~= UIParent do frame = frame:GetParent() end
	return frame
end
-- (Whether frame sits somewhere under canvas.)
local function Inside(frame, canvas)
	for _ = 1, 30 do
		if not frame then return false end
		if frame == canvas then return true end
		frame = frame:GetParent()
	end
	return false
end

-- The settings page a frame is on (a Look panel on a tab: the tab's frame
-- is its canvas, the page a few parents up).
local function PageOf(frame)
	for _ = 1, 30 do
		if not frame then return end
		if frame.pageName then return frame end
		frame = frame:GetParent()
	end
end
-- A page's first button that opens a Look panel (depth first, every tab).
local function LookButton(frame, depth)
	if depth > 25 then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child.opensLook and child:GetScript("OnClick") then return child end
		local found = LookButton(child, depth + 1)
		if found then return found end
	end
end
-- (A hub's canvas holds its pages': only a button on the page itself.)
local function OwnLookButton(canvas)
	local button = LookButton(canvas, 0)
	if button and PageOf(button) == canvas then return button end
end
-- Every settings page with a preview or a Look button: its canvas and page
-- name. (Some pages make their rows as they first show, the Nameplate
-- Style grid: their button is looked for again once the page is open.)
local function Pages()
	local list, seen = {}, {}
	local function Add(canvas, name)
		if not canvas or seen[canvas] then return end
		seen[canvas] = true
		list[#list + 1] = { canvas = canvas, name = canvas.pageName or name }
	end
	for _, preview in ipairs(ns.STYLE_PREVIEWS or {}) do
		local canvas = PageOf(preview.popSlot and preview.popSlot:IsShown() and preview.popSlot or preview)
		if canvas and canvas.pageName then Add(canvas) end
	end
	for name, canvas in pairs(ns.settingsCanvases or {}) do
		if OwnLookButton(canvas) then Add(canvas, name) end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end
-- Its Look panel opened (made on the first click, for some): the one open now.
local function OpenLook(page)
	page.button = page.button or OwnLookButton(page.canvas)
	if not page.button then return end
	page.title = page.button.searchLabel
	if not (ns.LookPanelOpen and ns.LookPanelOpen()) then
		page.button:GetScript("OnClick")(page.button)
	end
	page.pop = ns.LookPanelOpen and ns.LookPanelOpen()
	return page.pop
end
-- The page's own preview (in it, or popped from a slot in it).
local function OwnPreview(canvas)
	for _, preview in ipairs(ns.STYLE_PREVIEWS or {}) do
		if Inside(preview.popSlot and preview.popSlot:IsShown() and preview.popSlot or preview, canvas) then return preview end
	end
end

local Next

local function Finish(done)
	if not run then return end
	local kept, this = run.kept, run
	run = nil
	ns.MenuTestBackdrop("lookdock", false)
	local open = ns.LookPanelOpen and ns.LookPanelOpen()
	if open then open:Hide() end
	local db = ns.GetDB()
	if db then db.lookPanel, db.stylePreviewPos = kept.lookPanel, kept.previewPos end
	-- (The preview put back, and popped again where it was if it was out.)
	local popped = ns.StylePreviewDebug and ns.StylePreviewDebug()
	if popped and popped.popButton then
		popped.popButton:Click()
		if kept.previewOut then popped.popButton:Click() end
	end
	if db then db.stylePreviewOut = kept.previewOut end
	if kept.page then ns.OpenOptions(kept.page) end
	local line = ("%s: %d pages, %d pass, %d fail, %d skipped"):format(done and "done" or "stopped",
		math.min(this.index or 0, #this.pages), this.pass, this.fail, this.skip)
	Say(line)
	ns.TestPrompt(("Look dock test %s. /reload, then say \"check log\". (A yellow \"Interface action failed\" is the settings opened by the test: the game's, harmless.)"):format(line), 12)
end

-- (Words shown in a frame and under it: a panel with next to none is empty.)
local function Words(frame, depth)
	if depth > 12 or not frame:IsVisible() then return 0 end
	local count = 0
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetText and region:IsVisible() then
			local ok, text = pcall(region.GetText, region)
			if ok and type(text) == "string" and text ~= "" then count = count + 1 end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do count = count + Words(child, depth + 1) end
	return count
end
-- Every preview in sight now (on its page or popped), by its title.
local function PreviewsShown()
	local list = {}
	local _, window = ns.StylePreviewDebug()
	for _, preview in ipairs(ns.STYLE_PREVIEWS or {}) do
		if preview:IsVisible() and preview:GetEffectiveAlpha() > 0.05 then
			list[#list + 1] = ("%s (%s, %.0f x %.0f)"):format(tostring(preview.popTitle or "Preview"),
				preview:GetParent() == window and "popped" or "on its page", preview:GetWidth(), preview:GetHeight())
		end
	end
	return list
end
-- The previews in sight, logged; two or more is a problem.
local function CheckPreviews(problems)
	local shown = PreviewsShown()
	Say(("  previews in sight: %d %s"):format(#shown, table.concat(shown, ", ")))
	if #shown > 1 then problems[#problems + 1] = ("%d previews in sight"):format(#shown) end
	if #shown == 0 then problems[#problems + 1] = "no preview in sight" end
end

-- One page, checked with its Look panel open.
local function Check(page)
	local popped, window = ns.StylePreviewDebug()
	local pop = page.pop
	local problems = {}
	local settings = TopWindow(page.canvas)
	local winBox, popBox, setBox = Box(window), Box(pop), Box(settings)
	local screenH = UIParent:GetHeight() * UIParent:GetEffectiveScale()
	local screenW = UIParent:GetWidth() * UIParent:GetEffectiveScale()
	if not pop:IsShown() then problems[#problems + 1] = "Look panel not shown" end
	if not (window and window:IsShown()) then
		problems[#problems + 1] = ("preview window hidden (aside %s)"):format(tostring(window and window.lookAside))
	end
	if window and window:IsShown() and not window.side then problems[#problems + 1] = "preview not docked to the settings" end
	if Overlap(winBox, popBox) then problems[#problems + 1] = "preview and Look panel overlap" end
	if popBox and (popBox.b < -1 or popBox.t > screenH + 1 or popBox.l < -1 or popBox.r > screenW + 1) then
		problems[#problems + 1] = "Look panel off the screen"
	end
	if winBox and (winBox.b < -1 or winBox.t > screenH + 1) then problems[#problems + 1] = "preview off the screen" end
	if Overlap(winBox, setBox) then problems[#problems + 1] = "preview covers the settings" end
	if Overlap(popBox, setBox) then problems[#problems + 1] = "Look panel covers the settings" end
	local words = Words(pop, 0)
	if words < 6 then problems[#problems + 1] = ("Look panel looks empty (%d words shown)"):format(words) end
	CheckPreviews(problems)
	-- (The panel's own sample, a second preview, while the popped one shows.)
	if pop.sampleShown and ns.PreviewWindowShown and ns.PreviewWindowShown() then
		problems[#problems + 1] = "the Look panel's own sample shows too: two previews"
	end
	local where = pop.underPreview and "under the preview" or pop.besideSettings and "beside the settings" or "its own spot"
	Say(("  preview %s, side %s, scale %.2f, window %s | panel %s (%s), height %.0f, %d words | settings %s"):format(
		popped and "popped" or "not popped", tostring(window and window.side), popped and popped:GetScale() or 0,
		BoxText(winBox), BoxText(popBox), where, pop:GetHeight(), words, BoxText(setBox)))
	return problems, where
end

local function Step()
	if not run then return end
	run.index = run.index + 1
	local page = run.pages[run.index]
	if not page then
		Finish(true)
		return
	end
	Say(("--- %d of %d: %s ---"):format(run.index, #run.pages, page.name))
	ns.TestPrompt(("Look dock test: %d of %d, %s. Just watch."):format(run.index, #run.pages, page.name), OPEN_WAIT + LOOK_WAIT)
	ns.OpenOptions(page.name)
	C_Timer.After(OPEN_WAIT, function()
		if not run then return end
		-- (The page itself drawn: a page with next to no words shown is blank.
		-- Under 5: a short page, Cast Bar Style's Look tab, shows 6.)
		local pageWords = Words(page.canvas, 0)
		Say(("  page shows %d words"):format(pageWords))
		page.blank = pageWords < 5 and ("the page looks blank (%d words shown)"):format(pageWords) or nil
		local popped = ns.StylePreviewDebug()
		if not popped then
			local own = OwnPreview(page.canvas)
			if own and own.popButton then own.popButton:Click() end
			popped = ns.StylePreviewDebug()
		end
		if not popped then
			run.skip = run.skip + 1
			Say("  verdict SKIP: no preview pops out on this page")
			Shot(page.name)
			return Next(0.4)
		end
		local open = ns.LookPanelOpen and ns.LookPanelOpen()
		if open then open:Hide() end -- (the last page's, if left up)
		if not OpenLook(page) then
			if page.button then
				run.fail = run.fail + 1
				Say(("  verdict FAIL: its Look button (%s) opened no Look panel"):format(tostring(page.title)))
			else
				-- (No Look panel: the preview alone checked, docked and single.)
				local problems = { page.blank }
				CheckPreviews(problems)
				if #problems == 0 then
					run.skip = run.skip + 1
					Say("  verdict SKIP: a preview but no Look panel button on this page")
				else
					run.fail = run.fail + 1
					Say(("  verdict FAIL: %s (no Look panel on this page)"):format(table.concat(problems, "; ")))
				end
			end
			Shot(page.name)
			return Next(0.4)
		end
		Say(("  Look panel: %s"):format(tostring(page.title)))
		C_Timer.After(LOOK_WAIT, function()
			if not run then return end
			local ok, problems, where = pcall(Check, page)
			if not ok then problems, where = { "test error: " .. tostring(problems) }, "?" end
			if page.blank then problems[#problems + 1] = page.blank end
			-- (The screenshot's taken as the frame ends: the panel closed a
			-- moment after, not in the same frame, or it isn't in the picture.)
			Shot(page.name)
			C_Timer.After(0.3, function() if run then page.pop:Hide() end end)
			C_Timer.After(0.3 + CLOSE_WAIT, function()
				if not run then return end
				local _, window = ns.StylePreviewDebug()
				if not (window and window:IsShown()) then
					problems[#problems + 1] = "preview window not back after the panel closed"
				end
				Say(("  closed: preview window shown %s, side %s"):format(tostring(window and window:IsShown()),
					tostring(window and window.side)))
				if #problems == 0 then
					run.pass = run.pass + 1
					Say(("  verdict PASS: both in sight, panel %s"):format(where))
				else
					run.fail = run.fail + 1
					Say(("  verdict FAIL: %s (panel %s)"):format(table.concat(problems, "; "), where))
				end
				Next()
			end)
		end)
	end)
end
Next = function(wait)
	C_Timer.After(wait or 0.1, function()
		local ok, err = pcall(Step)
		if not ok then
			Say("error: " .. tostring(err))
			Finish(false)
		end
	end)
end

function ns.LookDockTest()
	if run then
		Finish(false)
		return
	end
	local db = ns.GetDB()
	if not (db and CinematicDB) then return end
	if InCombatLockdown() then
		ns.Print("/cine debug lookdock: not in a fight (the settings can't be moved then).")
		return
	end
	local pages = Pages()
	if #pages == 0 then
		ns.Print("/cine debug lookdock: no Look panels made yet; open the settings once, then run it again.")
		return
	end
	CinematicDB.lookDockTestLog = {}
	run = { at = GetTime(), pages = pages, index = 0, pass = 0, fail = 0, skip = 0,
		kept = { lookPanel = db.lookPanel, previewOut = db.stylePreviewOut, previewPos = db.stylePreviewPos,
			page = ns.lastOptionsPage } }
	ns.MenuTestBackdrop("lookdock", true)
	ns.debugNoCopyWindow = true -- (its copy window would sit over the checks)
	-- (Both docked, as they start: spots you dragged the panel or the preview
	-- to are put back after.)
	db.lookPanel, db.stylePreviewPos = nil, nil
	db.stylePreviewOut = true -- (each page's preview pops out as the page shows)
	-- (One popped already, where you dragged it: put back and popped again, docked.)
	local already = ns.StylePreviewDebug and ns.StylePreviewDebug()
	if already and already.popButton then
		already.popButton:Click()
		already.popButton:Click()
	end
	local w, h = UIParent:GetWidth(), UIParent:GetHeight() -- (UI units)
	Say(("start: %s (game %s), %d pages, screen %.0f x %.0f, UI scale %.2f, preview popped out before %s"):format(
		ns.isRetail and "retail" or "Forever", tostring((select(4, GetBuildInfo()))), #pages, w, h,
		UIParent:GetEffectiveScale(), tostring(run.kept.previewOut)))
	Next()
end
