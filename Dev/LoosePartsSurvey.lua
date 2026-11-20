-- /cine debug loose: step A of Tools/loose-parts-plan.md. For every frame the
-- fade manages, the parts under it (children and regions, up to MAX_DEPTH
-- levels) that ignore their parent's alpha: our fade of that frame doesn't
-- reach them (FlareUI 6.13 detaching bar 1's gryphons, 2026-11-20). Changes
-- nothing on screen. Each part to the log (category "loose") with its frame,
-- row group, depth, alpha, shown, size and what it draws; a summary in chat:
-- how many parts, at which depths, under which frames, and how long the walk
-- took (what a rescan would cost). Not counted as loose: frames with a row of
-- their own (they fade by it) and our own detached parts (DetachWhileFading).
-- Secret answers are counted apart, never compared, and per frame (which
-- frames a walk can't see into). Dev copy only.
local _, ns = ...

local MAX_DEPTH = 6

local function Secret(value) return issecretvalue and issecretvalue(value) end

local function Label(object)
	local ok, name = pcall(object.GetDebugName, object)
	if ok and type(name) == "string" and name ~= "" then return name end
	ok, name = pcall(object.GetName, object)
	return ok and name or tostring(object)
end

-- What a texture draws (atlas or file), short.
local function Draws(object)
	if object.GetObjectType and object:GetObjectType() ~= "Texture" then return "" end
	local okA, atlas = pcall(object.GetAtlas, object)
	if okA and atlas and not Secret(atlas) then return " atlas=" .. tostring(atlas) end
	local okF, file = pcall(object.GetTexture, object)
	if okF and file and not Secret(file) then return " file=" .. tostring(file) end
	return ""
end

local function Number(value)
	if value == nil then return "nil" end
	if Secret(value) then return "secret" end
	return ("%.2f"):format(value)
end

local function Bool(value)
	if Secret(value) then return "secret" end
	return tostring(value and true or false)
end

-- Walks frame's children and regions; found(part, depth) for each one that
-- ignores its parent's alpha. A frame with a row of its own isn't walked into
-- (its own entry walks it). Returns the counts it skipped.
local function Walk(frame, depth, found, skipped)
	if depth > MAX_DEPTH then return end
	local function Look(object, isFrame)
		-- (Each object once, whichever list it came through.)
		if skipped.visited[object] then return end
		skipped.visited[object] = true
		if object.IsForbidden and object:IsForbidden() then
			skipped.forbidden = skipped.forbidden + 1
			return
		end
		if isFrame and ns.IsManagedFrame(object) then
			skipped.managed = skipped.managed + 1
			return
		end
		local ignoring = object.IsIgnoringParentAlpha and object:IsIgnoringParentAlpha()
		if Secret(ignoring) then
			skipped.secret = skipped.secret + 1
		elseif ignoring then
			if ns.IsOwnDetached(object) then
				skipped.own = skipped.own + 1
			else
				found(object, depth)
			end
		end
		if isFrame and object.GetChildren then Walk(object, depth + 1, found, skipped) end
	end
	for _, region in ipairs({ frame:GetRegions() }) do Look(region, false) end
	for _, child in ipairs({ frame:GetChildren() }) do Look(child, true) end
end

-- The frame's name for the report: its row's name, else its own.
local function KeyOf(entry) return tostring(entry.name or Label(entry.frame)) end

-- Returns parts (list of { entry, part, depth }), skipped counts (with
-- secretBy: frame name -> parts under it whose answer read back secret), ms.
function ns.SurveyLooseParts()
	local parts = {}
	local skipped = { forbidden = 0, managed = 0, secret = 0, own = 0, visited = {}, secretBy = {} }
	local started = debugprofilestop()
	for _, entry in ipairs(ns.managed or {}) do
		local frame = entry.frame
		if type(frame) == "table" and frame.GetChildren and not (frame.IsForbidden and frame:IsForbidden()) then
			local before = skipped.secret
			Walk(frame, 1, function(part, depth)
				parts[#parts + 1] = { entry = entry, part = part, depth = depth }
			end, skipped)
			if skipped.secret > before then
				local key = KeyOf(entry)
				skipped.secretBy[key] = (skipped.secretBy[key] or 0) + skipped.secret - before
			end
		end
	end
	return parts, skipped, debugprofilestop() - started
end

-- "name count, ..." for the counts' top few, biggest first.
local function Top(counts, few)
	local list = {}
	for name, count in pairs(counts) do list[#list + 1] = { name = name, count = count } end
	table.sort(list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.name < b.name
	end)
	local names = {}
	for i = 1, math.min(few, #list) do names[i] = ("%s %d"):format(list[i].name, list[i].count) end
	return table.concat(names, ", "), #list
end

function ns.LoosePartsSurvey()
	local parts, skipped, ms = ns.SurveyLooseParts()
	local byDepth, byFrame, frames = {}, {}, 0
	ns.Log("loose", ("survey: client %s, game %s, CineMode %s, combat %s, %d managed frames, walk %.2f ms"):format(
		ns.isRetail and "retail" or "Forever/Classic", tostring(select(4, GetBuildInfo())), tostring(ns.IsCineModeOn and ns.IsCineModeOn()),
		tostring(InCombatLockdown()), #(ns.managed or {}), ms))
	for _, found in ipairs(parts) do
		local entry, part = found.entry, found.part
		byDepth[found.depth] = (byDepth[found.depth] or 0) + 1
		local key = KeyOf(entry)
		if not byFrame[key] then frames = frames + 1 end
		byFrame[key] = (byFrame[key] or 0) + 1
		local okW, w = pcall(part.GetWidth, part)
		local okH, h = pcall(part.GetHeight, part)
		ns.Log("loose", ("%s [%s, frame alpha %s] depth %d: %s (%s) alpha %s shown %s visible %s %sx%s%s"):format(
			key, tostring(entry.group), Number(entry.frame:GetAlpha()), found.depth, Label(part),
			part.GetObjectType and part:GetObjectType() or "?", Number(part:GetAlpha()), Bool(part:IsShown()),
			Bool(part.IsVisible and part:IsVisible()), okW and Number(w) or "?", okH and Number(h) or "?", Draws(part)))
	end
	local depths = {}
	for depth = 1, MAX_DEPTH do
		if byDepth[depth] then depths[#depths + 1] = ("d%d %d"):format(depth, byDepth[depth]) end
	end
	local most = Top(byFrame, 6)
	local secretMost, secretFrames = Top(skipped.secretBy, 8)
	local summary = ("loose parts: %d under %d frames (%s); skipped %d with a row, %d ours, %d secret, %d forbidden; "
		.. "walk %.2f ms"):format(#parts, frames, #depths > 0 and table.concat(depths, ", ") or "none",
		skipped.managed, skipped.own, skipped.secret, skipped.forbidden, ms)
	-- (ns.Print logs it too: printed only, or the report has it twice.)
	ns.Print(summary)
	if most ~= "" then ns.Print("most: " .. most) end
	-- (Parts a walk can't tell about: only a hook on SetIgnoreParentAlpha would catch them.)
	if secretMost ~= "" then ns.Print(("secret answers under %d frames, most: %s"):format(secretFrames, secretMost)) end
	for name, count in pairs(skipped.secretBy) do
		ns.Log("loose", ("%s: %d parts answered secret"):format(name, count))
	end
	ns.Print("Each part is in the log (/cine log, \"loose\" lines).")
end
