-- /cine debug previewwatch [off]: records how the Style previews move while
-- you use the settings as usual, to find how one ends up over a page's rows
-- (2026-11-17: the Smart tab's preview over its rows, seen once, not on
-- purpose). On till turned off, across reloads. Logged, into
-- CinematicDB.previewWatchLog (the last 400 lines):
--   - every move StylePages.lua makes (ns.PreviewTrace): pop out, put back,
--     the window placed (which side), the settings slid down or back, the
--     sticky preview lifted, dropped, held or let go; each with the state;
--   - every half second with our settings up, the page's text measured
--     (PageShots.lua's ns.PageLayoutFindings): text under a preview starts an
--     OVERLAP: what's covered, the full state, and a screenshot; "gone" when
--     it ends.
-- Dev copy only.
local _, ns = ...

local CHECK, KEEP = 0.5, 400

local function Say(text)
	local log = CinematicDB and CinematicDB.previewWatchLog
	if not log then return end
	log[#log + 1] = ("%s %s"):format(date("%H:%M:%S"), text)
	while #log > KEEP do table.remove(log, 1) end
end

local function Rect(frame)
	if not frame then return "-" end
	local ok, l, b, w, h = pcall(frame.GetRect, frame)
	if not (ok and tonumber(l) and tonumber(b) and tonumber(w) and tonumber(h)) then return "no rect" end
	return ("%.0f,%.0f %.0fx%.0f"):format(l, b + h, w, h)
end
local function Name(frame)
	if not frame then return "nil" end
	return frame:GetName() or frame.pageName or (frame.hubSearch and "hub") or frame:GetObjectType()
end

-- The state of a preview and of the pop-out window and settings window.
local function State(preview)
	local popped, window, slid = ns.StylePreviewDebug()
	local db = ns.db or {}
	local parts = {}
	parts[#parts + 1] = ("popped %s, window %s %s side %s, dragged %s, slid %s, out %s, folded %s"):format(
		popped and "yes" or "no", window and window:IsShown() and "shown" or "hidden", Rect(window),
		tostring(window and window.side), type(db.stylePreviewPos) == "table" and "yes" or "no", slid and "yes" or "no",
		tostring(db.stylePreviewOut), tostring(db.stylePreviewFolded))
	local settings = _G.SettingsPanel or _G.InterfaceOptionsFrame
	parts[#parts + 1] = ("settings %s"):format(Rect(settings))
	preview = preview or popped
	if preview then
		local pin = preview.pin
		local spot = preview.stackSpot
		local scroll = pin and pin.scroll
		parts[#parts + 1] = ("preview %s on %s, scale %.2f, alpha %.2f, shown %s; spot %s; pin on %s target %s t %s; scroll %s of %s")
			:format(Rect(preview), Name(preview:GetParent()), preview:GetScale(), preview:GetEffectiveAlpha(),
			tostring(preview:IsVisible()), Rect(spot), tostring(pin and pin.on), tostring(pin and pin.target),
			pin and pin.t and ("%.2f"):format(pin.t) or "-",
			scroll and ("%.0f"):format(scroll:GetVerticalScroll()) or "-",
			scroll and ("%.0f"):format(scroll:GetVerticalScrollRange()) or "-")
	end
	return table.concat(parts, " | ")
end

-- (StylePages.lua calls this at each move while it's set.)
local function Trace(event, preview, detail)
	Say(("%s%s | %s"):format(event, detail ~= nil and detail ~= "" and (" (" .. tostring(detail) .. ")") or "",
		State(preview)))
end

-- The previews on a canvas now (marked stackSpot), the popped one too.
local function PreviewsOn(canvas)
	local found = {}
	local function Walk(frame, depth)
		if depth > 25 or not frame:IsVisible() then return end
		if frame.stackSpot then
			found[#found + 1] = frame
			return
		end
		for _, child in ipairs({ frame:GetChildren() }) do Walk(child, depth + 1) end
	end
	pcall(Walk, canvas, 0)
	return found
end

local overlap -- { page, since } while one's going on
local ticker
local function Check()
	if not ns.OurSettingsShown or not ns.OurSettingsShown() or not ns.PageLayoutFindings then return end
	local covered, page, canvas
	for each in pairs(ns.shownSettingsCanvases or {}) do
		if each:IsVisible() and each.scroll then
			local _, _, _, _, under = ns.PageLayoutFindings(each)
			if under and (under.total or 0) > 0 then
				covered, page, canvas = under, each.pageName or "?", each
				break
			end
		end
	end
	if covered and not overlap then
		overlap = { page = page, since = GetTime() }
		local popped = ns.StylePreviewDebug()
		local preview = popped or PreviewsOn(canvas)[1]
		Say(("OVERLAP on %s: under a preview: %s"):format(page, table.concat(covered, "; ")))
		Say("  state: " .. State(preview))
		local ok = pcall(Screenshot)
		Say(("  screenshot at %s%s"):format(date("%m%d%y_%H%M%S"), ok and "" or " (failed)"))
		ns.Print("preview watch: caught a preview over the rows (logged, screenshot taken)")
	elseif overlap and not covered then
		Say(("overlap on %s gone after %.1f sec | %s"):format(overlap.page, GetTime() - overlap.since, State()))
		overlap = nil
	end
end

local function Start(quiet)
	ns.PreviewTrace = Trace
	if not ticker then ticker = C_Timer.NewTicker(CHECK, function() ns.Guard(Check) end) end
	if not quiet then
		Say("--- watch on: " .. State())
		ns.Print("preview watch on: use the Style pages as usual (scroll, tabs, pop out, put back); "
			.. "it records till /cine debug previewwatch off")
	end
end

function ns.PreviewWatch(arg)
	if arg == "off" then
		CinematicDB.previewWatchOn = nil
		ns.PreviewTrace = nil
		if ticker then ticker:Cancel() end
		ticker, overlap = nil, nil
		Say("--- watch off")
		ns.Print("preview watch off: say \"check log\" (after a /reload)")
		return
	end
	CinematicDB.previewWatchOn = true
	CinematicDB.previewWatchLog = CinematicDB.previewWatchLog or {}
	Start()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	if CinematicDB and CinematicDB.previewWatchOn then
		Say("--- after a reload: still watching")
		Start(true)
	end
end)
