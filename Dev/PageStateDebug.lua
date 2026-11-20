-- /cine debug pagestate: a snapshot of the Style page on screen, for the
-- settings that sometimes vanish under its preview (2026-11-20, Combat Text
-- Style: the tab row and every setting gone, the page still as long). The
-- tab row's base hangs from the preview, and the preview's moves (sticky to
-- the hub's corner and back, pop out and put back, StylePages.lua) move what
-- hangs from it onto a stand-in (its spot, its slot) and back. Logged for
-- each preview on screen: where it is (parent, points, place, scale, levels),
-- its sticky state (on, how far, held, what it moved), popped or not, its
-- spot and slot, the page's scroll view (place, offset, range, length), and
-- each frame hanging from the preview, spot or slot (the tab row's base) and
-- from those (the tab panel, the tabs' frames): shown, alpha, place, whether
-- the game could place it at all, inside the page's view or how far out, and
-- its anchor chain up to the page (a loop called out). A screenshot too.
-- Into CinematicDB.pageStateLog. Dev copy only (CinematicDev.toc).
local _, ns = ...

local MAX_HANGING = 40 -- frames listed under a preview
local CHAIN = 14       -- anchor steps followed

local lines

local function Say(text)
	lines[#lines + 1] = text
end

local function Num(value)
	if value == nil then return "nil" end
	if issecretvalue and issecretvalue(value) then return "<secret>" end
	if type(value) ~= "number" then return tostring(value) end
	return ("%.1f"):format(value)
end

-- A name for a frame: one of the known ones, its global name, else its type.
local function Namer(known)
	return function(frame)
		if frame == nil then return "nil" end
		if known[frame] then return known[frame] end
		local okN, name = pcall(frame.GetName, frame)
		if okN and type(name) == "string" then return name end
		local okT, kind = pcall(frame.GetObjectType, frame)
		return (okT and kind or "?") .. "@" .. tostring(frame):gsub("^table: ", ""):gsub("^%a+: ", "")
	end
end

local function Points(frame, Name)
	local parts = {}
	local okN, count = pcall(frame.GetNumPoints, frame)
	for i = 1, (okN and type(count) == "number") and count or 0 do
		local ok, point, relative, relPoint, x, y = pcall(frame.GetPoint, frame, i)
		if ok then
			parts[#parts + 1] = ("%s to %s %s %s,%s"):format(tostring(point), Name(relative), tostring(relPoint), Num(x),
				Num(y))
		end
	end
	return #parts > 0 and table.concat(parts, "; ") or "no points"
end

-- Where it is on screen, and against the page's view (top, bottom).
local function Place(frame, viewTop, viewBottom)
	local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
	if not ok then return "place: error" end
	if type(left) ~= "number" then return "place: NONE (the game couldn't place it: anchors unresolved or a loop)" end
	if issecretvalue and issecretvalue(left) then return "place: <secret>" end
	local top = bottom + height
	local where = ""
	if type(viewTop) == "number" and type(viewBottom) == "number" then
		if bottom >= viewTop then where = (" ABOVE the view by %.0f"):format(bottom - viewTop)
		elseif top <= viewBottom then where = (" BELOW the view by %.0f"):format(viewBottom - top)
		elseif top > viewTop + 0.5 or bottom < viewBottom - 0.5 then where = " partly in the view"
		else where = " in the view" end
	end
	return ("place: left %s top %s, %sx%s%s"):format(Num(left), Num(top), Num(width), Num(height), where)
end

local function Describe(frame, Name, label, viewTop, viewBottom)
	local function Ask(method, ...)
		local fn = frame[method]
		if not fn then return "none" end
		local ok, value = pcall(fn, frame, ...)
		return ok and tostring(value) or "error"
	end
	Say(("  %s [%s]: parent %s, shown %s, visible %s, alpha %s (on screen %s), scale %s (on screen %s), %s %s"):format(
		label, Name(frame), Name(frame:GetParent()), Ask("IsShown"), Ask("IsVisible"), Ask("GetAlpha"),
		Ask("GetEffectiveAlpha"), Ask("GetScale"), Ask("GetEffectiveScale"), Ask("GetFrameStrata"), Ask("GetFrameLevel")))
	Say("    points: " .. Points(frame, Name))
	Say("    " .. Place(frame, viewTop, viewBottom))
end

-- The anchor chain from frame up: each step's first point's relative.
local function Chain(frame, Name)
	local seen, steps, each = {}, {}, frame
	for _ = 1, CHAIN do
		if seen[each] then
			steps[#steps + 1] = "LOOP back to " .. Name(each)
			break
		end
		seen[each] = true
		local ok, _, relative = pcall(each.GetPoint, each, 1)
		if not ok or relative == nil or type(relative) ~= "table" then break end
		steps[#steps + 1] = Name(relative)
		each = relative
	end
	return Name(frame) .. " -> " .. (#steps > 0 and table.concat(steps, " -> ") or "(none)")
end

local function ScrollOf(frame)
	local each = frame and frame:GetParent()
	while each and each ~= UIParent do
		if each.GetObjectType and each:GetObjectType() == "ScrollFrame" then return each end
		each = each:GetParent()
	end
end

-- Frames (children and regions of parent) with a point on one of froms.
local function HangingFrom(parent, froms)
	local found = {}
	if not parent then return found end
	local function Check(object)
		if froms[object] or not object.GetNumPoints then return end
		local okN, count = pcall(object.GetNumPoints, object)
		for i = 1, (okN and type(count) == "number") and count or 0 do
			local ok, _, relative = pcall(object.GetPoint, object, i)
			if ok and relative and froms[relative] then
				found[#found + 1] = { object, relative }
				return
			end
		end
	end
	for _, child in ipairs({ parent:GetChildren() }) do Check(child) end
	for _, region in ipairs({ parent:GetRegions() }) do Check(region) end
	return found
end

local function OnScreen(preview)
	local function Up(frame) return frame and frame:IsVisible() end
	return Up(preview) or Up(preview.stackSpot) or Up(preview.popSlot)
end

local function Snapshot(preview, index, popped, popWindow)
	local pin, spot, slot = preview.pin, preview.stackSpot, preview.popSlot
	local scroll = (pin and pin.scroll) or ScrollOf(spot or preview)
	local child = scroll and scroll:GetScrollChild()
	local known = { [preview] = "preview", [UIParent] = "UIParent" }
	if spot then known[spot] = "spot" end
	if slot then known[slot] = "slot" end
	if popWindow then known[popWindow] = "popWindow" end
	if scroll then known[scroll] = "scroll" end
	if child then known[child] = "content" end
	if pin and pin.hub then known[pin.hub] = "hub" end
	if pin and pin.floor then known[pin.floor] = "floor" end
	local Name = Namer(known)
	local viewTop, viewBottom
	if scroll then viewTop, viewBottom = scroll:GetTop(), scroll:GetBottom() end
	Say(("preview %d (%s): popped %s, kept in %s, borrowed %s"):format(index, tostring(preview.popTitle or "?"),
		tostring(popped == preview), tostring(preview.keptIn), tostring(preview.borrowedBy ~= nil)))
	if pin then
		local moved = {}
		for _, each in ipairs(pin.moved or {}) do moved[#moved + 1] = Name(each) end
		Say(("  sticky: on %s, how far %s, held %s, raised %s, home %s, moved onto spot: %s, floor %s"):format(
			tostring(pin.on), Num(pin.t), tostring(pin.target), tostring(pin.raise), Name(pin.home),
			#moved > 0 and table.concat(moved, ", ") or "none", pin.floor and tostring(pin.floor:IsShown()) or "none"))
	else
		Say("  sticky: no pin (never held, or not on a hub page)")
	end
	if scroll then
		local okR, range = pcall(scroll.GetVerticalScrollRange, scroll)
		local okS, offset = pcall(scroll.GetVerticalScroll, scroll)
		Say(("  page view: top %s bottom %s, scrolled %s of %s, page length %s"):format(Num(viewTop), Num(viewBottom),
			okS and Num(offset) or "error", okR and Num(range) or "error", child and Num(child:GetHeight()) or "none"))
	else
		Say("  page view: none found")
	end
	Describe(preview, Name, "preview", viewTop, viewBottom)
	if spot then Describe(spot, Name, "spot", viewTop, viewBottom) end
	if slot then Describe(slot, Name, "slot", viewTop, viewBottom) end
	-- What hangs from them (the tab row's base), then from those (its panel,
	-- the tabs' frames, the settings), on the page and on the hub.
	local froms = { [preview] = true }
	if spot then froms[spot] = true end
	if slot then froms[slot] = true end
	-- (The page, the spot's parent (the same in game), the hub, the window.)
	local parents, added = {}, {}
	for _, each in ipairs({ child or false, spot and spot:GetParent() or false, pin and pin.hub or false,
		popWindow or false }) do
		if each and not added[each] and type(each.GetChildren) == "function" then
			added[each] = true
			parents[#parents + 1] = each
		end
	end
	local listed = 0
	for _, parent in ipairs(parents) do
		for _, hit in ipairs(HangingFrom(parent, froms)) do
			if listed >= MAX_HANGING then break end
			listed = listed + 1
			local frame = hit[1]
			known[frame] = known[frame] or ("hanging" .. listed)
			Describe(frame, Name, ("hangs from %s"):format(Name(hit[2])), viewTop, viewBottom)
			Say("    chain: " .. Chain(frame, Name))
			local under = 0
			for _, sub in ipairs(HangingFrom(parent, { [frame] = true })) do
				if listed >= MAX_HANGING then break end
				listed, under = listed + 1, under + 1
				known[sub[1]] = known[sub[1]] or (known[frame] .. "." .. under)
				Describe(sub[1], Name, ("under %s"):format(known[frame]), viewTop, viewBottom)
			end
		end
	end
	if listed == 0 then Say("  NOTHING hangs from the preview, its spot or its slot") end
end

function ns.PageStateDebug()
	ns.debugNoCopyWindow = true
	CinematicDB.pageStateLog = {}
	lines = CinematicDB.pageStateLog
	local settings = _G.SettingsPanel or _G.InterfaceOptionsFrame
	Say(("pagestate %s: %s (game %s), fight %s, CineMode %s, settings window shown %s"):format(date("%Y-%m-%d %H:%M:%S"),
		ns.isRetail and "retail" or "Forever", tostring((select(4, GetBuildInfo()))), tostring(InCombatLockdown()),
		tostring(ns.IsCineModeOn and ns.IsCineModeOn() or false), tostring(settings and settings:IsShown() or false)))
	local popped, popWindow, slid
	if ns.StylePreviewDebug then popped, popWindow, slid = ns.StylePreviewDebug() end
	Say(("pop out window shown %s, settings slid down %s, a preview moving %s"):format(
		tostring(popWindow and popWindow:IsShown() or false), tostring(slid ~= nil),
		tostring(ns.StickyPreviewMoving and ns.StickyPreviewMoving() or false)))
	local count = 0
	for index, preview in ipairs(ns.STYLE_PREVIEWS or {}) do
		if OnScreen(preview) or popped == preview then
			count = count + 1
			local ok, err = pcall(Snapshot, preview, index, popped, popWindow)
			if not ok then Say("  error: " .. tostring(err)) end
		end
	end
	if count == 0 then Say("no Style preview on screen: open the page where the settings vanished first") end
	pcall(function() Screenshot() end)
	local outside = 0
	for _, line in ipairs(lines) do
		if line:find("BELOW the view", 1, true) or line:find("ABOVE the view", 1, true) or line:find("NONE (", 1, true) then
			outside = outside + 1
		end
	end
	ns.Print(("pagestate: %d previews, %d lines logged, %d places off the page or unplaced, screenshot taken."
		.. " /reload, then say 'check log'."):format(count, #lines, outside))
end
