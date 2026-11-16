-- The dev copy's Minimap Copy page (the Dev hub): can we draw our own copy of
-- the minimap from the game's own minimap tile images, so the real one is
-- free to do the node sweep (NodeSweep.lua moves it under the mouse) while
-- the copy is what people see?
--
-- Test tiles: tries to load the tile under you by every path shape it could
-- have, next to two known answers (a file that's there, one that isn't) so
-- each try gets its own verdict. Everything goes to the saved log
-- ("minimapcopy") and the Cinematic chat tab; the tries show as squares on
-- the page too.
-- Show copy: a live copy (north up, outdoors only) to the left of the real
-- minimap, the same size and zoom, with its own player arrow.
-- /cine debug minimapcopy [show|hide]. Only in CinematicDev.toc.
local _, ns = ...

local TILE = 1600 / 3 -- yards across one map square (and its minimap tile)
local GRID = 32 -- the map's middle square (squares 0-63 each way)
-- The folder each world's tiles are in, by the instance ID GetInstanceInfo gives.
local DIRS = { [0] = "Azeroth", [1] = "Kalimdor", [530] = "Expansion01", [571] = "Northrend" }
local KNOWN_THERE = "Interface\\Icons\\INV_Misc_QuestionMark"
local KNOWN_MISSING = "World\\Minimaps\\NoSuchFolder\\map99_99"
local MISSING_ID = 2147480000 -- (far past any file the game has)
local UPDATE = 0 -- seconds between moves of the copy (every frame: at 1/30 it lagged the real one)

local copy -- the live copy's frame
local pattern -- the path shape that worked (a format: dir, column, row), once tested
local results = {} -- the last test's tries, for the page

local function Say(text)
	ns.Log("minimapcopy", text)
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local name = GetChatWindowInfo and GetChatWindowInfo(i)
		local frame = _G["ChatFrame" .. i]
		if type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name:lower() == "cinematic"
				and frame then
			frame:AddMessage("|cffe0b050Minimap copy:|r " .. text)
			return
		end
	end
end

-- Where you are on the map's grid: world folder, column and row as decimals
-- (the whole part is the tile, the rest how far across it), or nil and why.
local function Where()
	local north, west, _, instance = UnitPosition("player")
	if not north or (issecretvalue and (issecretvalue(north) or issecretvalue(west))) then
		return nil, "no position here (instance or secret)"
	end
	local mapInstance = select(8, GetInstanceInfo())
	instance = instance or mapInstance
	local dir = DIRS[instance]
	if not dir then return nil, ("no folder known for instance %s"):format(tostring(instance)) end
	return dir, GRID - west / TILE, GRID - north / TILE, north, west, instance
end

-- One try: sets the texture, reads what the game says back.
local function Try(texture, path)
	local ok, set = pcall(texture.SetTexture, texture, path)
	local id = texture.GetTextureFileID and texture:GetTextureFileID()
	local now = texture:GetTexture()
	return { path = path, ok = ok, set = set, id = id, now = now }
end

-- How to name a tile: by path (Forever knows none of these: tested
-- 2026-11-12, kept to see if a client ever does) or by file ID from
-- MinimapTiles.lua (column then row; the swapped one in case it's the
-- other way round).
local SHAPES = {
	{ "file ID", false, id = true },
	{ "file ID, column and row swapped", true, id = true },
	{ "World\\Minimaps\\%s\\map%d_%02d", false },
	{ "World\\Minimaps\\%s\\map%d_%d", false },
}

local function PathFor(shape, dir, col, row)
	if shape[2] then col, row = row, col end
	if shape.id then
		local world = ns.minimapTiles and ns.minimapTiles[dir]
		return world and world[col] and world[col][row]
	end
	return shape[1]:format(dir, col, row)
end

-- How a try reads next to the two known answers: "loaded", "missing" or
-- "can't tell" (when the known file and the missing one read the same).
local function Verdict(try, there, missing, missingID)
	if type(try.path) == "number" then
		-- (A made-up file ID read back as itself: the game echoes IDs, so no telling.)
		if missingID.id == missingID.path then return "can't tell" end
		return type(try.id) == "number" and try.id > 0 and "loaded" or "missing"
	end
	local function Sign(t) return tostring(t.set) .. "/" .. tostring(t.id) end
	if Sign(there) == Sign(missing) then return "can't tell" end
	if Sign(try) == Sign(missing) then return "missing" end
	if type(try.id) == "number" and try.id > 0 then return "loaded" end
	return Sign(try) == Sign(there) and "loaded" or "can't tell"
end

local scratch -- a hidden texture for tries
function ns.MinimapCopyTest()
	scratch = scratch or UIParent:CreateTexture()
	scratch:Hide()
	wipe(results)
	local dir, gx, gy, north, west, instance = Where()
	Say(("test: client %s, instance %s, indoors %s, rotate minimap %s, view radius %s"):format(
		tostring((select(4, GetBuildInfo()))), tostring(instance or select(8, GetInstanceInfo())),
		tostring(IsIndoors and IsIndoors()), tostring(GetCVar("rotateMinimap")),
		tostring(C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius())))
	local there = Try(scratch, KNOWN_THERE)
	local missing = Try(scratch, KNOWN_MISSING)
	local missingID = Try(scratch, MISSING_ID)
	Say(("known file: set %s, file ID %s | missing file: set %s, file ID %s | made-up ID %d: set %s, reads %s"):format(
		tostring(there.set), tostring(there.id), tostring(missing.set), tostring(missing.id), MISSING_ID,
		tostring(missingID.set), tostring(missingID.id)))
	if there.id == missing.id and there.set == missing.set then
		Say("VERDICT: the game answers the same for a file that's there and one that isn't; judge by the squares")
	end
	if not dir then
		Say("VERDICT: can't test here: " .. tostring(gx))
		return results
	end
	local col, row = math.floor(gx), math.floor(gy)
	Say(("you: north %.1f, west %.1f -> folder %s, tile column %d row %d (%.2f, %.2f across)"):format(
		north, west, dir, col, row, gx - col, gy - row))
	if not (ns.minimapTiles and ns.minimapTiles[dir]) then
		Say(("no file ID table for %s yet (MinimapTiles.lua; Tools/minimap-tiles makes one)"):format(dir))
	end
	pattern = nil
	local guess
	for i, shape in ipairs(SHAPES) do
		local path = PathFor(shape, dir, col, row)
		local try = path and Try(scratch, path) or { verdict = "no entry" }
		if path then try.verdict = Verdict(try, there, missing, missingID) end
		try.shape = shape
		results[i] = try
		Say(("%d. %s (%s): set %s, file ID %s -> %s"):format(i, shape.id and shape[1] or tostring(path),
			tostring(path), tostring(try.set), tostring(try.id), try.verdict:upper()))
		if try.verdict == "loaded" and not pattern then pattern = shape end
		-- (Forever reads any file ID back as itself, so an ID try can't be told
		-- apart; the first one with an entry is used: column then row showed the
		-- right art, tested 2026-11-12.)
		if try.verdict == "can't tell" and shape.id and not guess then guess = shape end
	end
	pattern = pattern or guess
	if pattern then
		Say(("VERDICT: using %s%s. Show copy draws from it."):format(pattern[1],
			pattern == guess and " (can't be checked: look at its square)" or ", it loads"))
	else
		Say("VERDICT: no tile loaded. Look at the squares on the page: any map art in one?")
	end
	return results
end

-- The live copy ---------------------------------------------------------------

-- The game's ring round the minimap (as MinimapStyle.lua: Forever's and
-- retail's compass, classic clients' border), mirrored onto the copy every
-- frame: its art, color, grey and place next to the minimap, so a Style
-- theme's recolor comes along too.
local RINGS = { "MinimapCompassTexture", "MinimapBorder" }

-- Where a region sits next to the minimap's top left, in the minimap's units.
local function Offsets(region)
	local left, top, right, bottom = region:GetLeft(), region:GetTop(), region:GetRight(), region:GetBottom()
	local mLeft, mTop = Minimap:GetLeft(), Minimap:GetTop()
	if not (left and top and right and bottom and mLeft and mTop) then return nil end
	local k = region:GetEffectiveScale() / Minimap:GetEffectiveScale()
	return left * k - mLeft, top * k - mTop, right * k - mLeft, bottom * k - mTop
end

-- (Returns how far the rings stick out past the minimap's sides.)
local function MirrorRings()
	copy.rings = copy.rings or {}
	local out = 0
	for i, name in ipairs(RINGS) do
		local game = _G[name]
		local ours = copy.rings[i]
		local left, top, right, bottom
		if game and game.IsVisible and game:IsVisible() then left, top, right, bottom = Offsets(game) end
		if left then
			if not ours then
				ours = copy:CreateTexture(nil, "OVERLAY", nil, 7)
				copy.rings[i] = ours
			end
			local atlas = game.GetAtlas and game:GetAtlas()
			if atlas then
				if ours.atlas ~= atlas then ours:SetAtlas(atlas) end
			else
				local file = game:GetTexture()
				if ours.file ~= file then ours:SetTexture(file) end
				ours:SetTexCoord(game:GetTexCoord())
				ours.file = file
			end
			ours.atlas = atlas
			ours:SetVertexColor(game:GetVertexColor())
			ours:SetDesaturated(game:IsDesaturated())
			ours:SetBlendMode(game:GetBlendMode())
			ours:ClearAllPoints()
			ours:SetPoint("TOPLEFT", copy, "TOPLEFT", left, top)
			ours:SetPoint("BOTTOMRIGHT", copy, "TOPLEFT", right, bottom)
			ours:Show()
			out = math.max(out, -left, right - Minimap:GetWidth())
		elseif ours then
			ours:Hide()
		end
	end
	return out
end

-- What the copy's ring is made of, for the test's log.
local function DescribeRings()
	for _, name in ipairs(RINGS) do
		local game = _G[name]
		if not game then
			Say(("ring %s: not on this client"):format(name))
		else
			local left, top, right, bottom = Offsets(game)
			Say(("ring %s: shown %s, alpha %.2f, atlas %s, file %s, color %s, grey %s, layer %s, at %s"):format(name,
				tostring(game:IsVisible()), game:GetAlpha(), tostring(game.GetAtlas and game:GetAtlas()),
				tostring(game:GetTexture()), table.concat({ game:GetVertexColor() }, "/"),
				tostring(game:IsDesaturated()), tostring(game:GetDrawLayer()), left and
				("%.0f, %.0f to %.0f, %.0f (minimap %.0f x %.0f)"):format(left, top, right, bottom, Minimap:GetWidth(),
				Minimap:GetHeight()) or "?"))
		end
	end
end

local function Build()
	copy = CreateFrame("Frame") -- (not UIParent's: CineMode can't hide it)
	copy:SetFrameStrata("HIGH")
	local back = copy:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 1)
	local mask = copy:CreateMaskTexture()
	mask:SetAllPoints()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	back:AddMaskTexture(mask)
	copy.tiles = {}
	for i = 1, 9 do
		local tile = copy:CreateTexture(nil, "ARTWORK")
		tile:AddMaskTexture(mask)
		copy.tiles[i] = tile
	end
	copy.arrow = copy:CreateTexture(nil, "OVERLAY")
	copy.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
	copy.arrow:SetSize(32, 32)
	copy.arrow:SetPoint("CENTER")
	copy.note = copy:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	copy.note:SetPoint("TOP", copy, "BOTTOM", 0, -4)
	copy.note:SetText("Copy")
	copy.status = copy:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	copy.status:SetPoint("CENTER")
	copy.status:SetWidth(120)
	local since = 0
	ns.SetOnUpdate(copy, function(_, elapsed)
		since = since + elapsed
		if since < UPDATE then return end
		since = 0
		ns.MinimapCopyUpdate()
	end)
end

function ns.MinimapCopyUpdate()
	if not (copy and copy:IsShown()) then return end
	copy:SetScale(Minimap:GetEffectiveScale())
	local size = Minimap:GetWidth()
	copy:SetSize(size, Minimap:GetHeight())
	copy:ClearAllPoints()
	-- (scales match, so offsets do; both rings' overhang kept clear)
	copy:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -12 - 2 * MirrorRings(), 0)
	local dir, gx, gy = Where()
	local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
	local why = not pattern and "no tile path found yet: Test tiles first"
		or not dir and gx or not radius and "no view radius"
		or IsIndoors and IsIndoors() and "indoors: the game draws building maps here, not tiles"
		or GetCVar("rotateMinimap") == "1" and "Rotate Minimap is on: copy is north-up only"
	copy.status:SetText(why or "")
	for _, tile in ipairs(copy.tiles) do tile:SetShown(not why) end
	local facing = GetPlayerFacing()
	copy.arrow:SetShown(facing ~= nil)
	if facing then copy.arrow:SetRotation(facing) end
	if why then return end
	local perYard = size / (2 * radius)
	local tilePx = TILE * perYard
	local col, row = math.floor(gx), math.floor(gy)
	local i = 0
	for dr = -1, 1 do
		for dc = -1, 1 do
			i = i + 1
			local tile = copy.tiles[i]
			local path = PathFor(pattern, dir, col + dc, row + dr)
			if tile.path ~= path then
				tile:SetTexture(path) -- (nil past the world's edge: no tile there)
				tile.path = path
			end
			tile:SetShown(path ~= nil)
			tile:SetSize(tilePx, tilePx)
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", copy, "CENTER", (col + dc - gx) * tilePx, -(row + dr - gy) * tilePx)
		end
	end
end

function ns.MinimapCopyShow(show)
	if show == nil then show = not (copy and copy:IsShown()) end
	if show then
		if not pattern then ns.MinimapCopyTest() end
		if not copy then Build() end
		copy:Show()
		ns.MinimapCopyUpdate()
		Say(pattern and "copy shown left of the minimap" or "copy shown, but no tile path loaded")
		DescribeRings()
	elseif copy then
		copy:Hide()
	end
	return copy and copy:IsShown() or false
end

-- /cine debug minimapcopy [show|hide]
function ns.MinimapCopyCommand(arg)
	if arg == "show" then ns.MinimapCopyShow(true)
	elseif arg == "hide" then ns.MinimapCopyShow(false)
	else ns.MinimapCopyTest() end
end

-- The page ---------------------------------------------------------------------

function ns.CreateMinimapCopyPage(kit)
	local canvas, content = kit.CreateScrollPage(true)
	local title = kit.Label(content, "GameFontNormalLarge", "Minimap Copy")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title, "Testing a copy of the minimap drawn from the game's own tile " ..
		"images, so the real minimap can do the node sweep out of sight while the copy is what you see. " ..
		"Test tiles tries every path a tile could have and logs a verdict for each (saved log, \"minimapcopy\"). " ..
		"Show copy puts a live copy left of the real minimap. /cine debug minimapcopy [show|hide].")
	local test = ns.PanelButton(content)
	test:SetSize(120, 22)
	test:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
	test:SetText("Test tiles")
	local show = ns.PanelButton(content)
	show:SetSize(120, 22)
	show:SetPoint("LEFT", test, "RIGHT", 8, 0)
	local status = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	status:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -10)
	status:SetWidth(560)
	status:SetJustifyH("LEFT")

	local squares = {}
	local function Square(i)
		if squares[i] then return squares[i] end
		local holder = CreateFrame("Frame", nil, content)
		holder:SetSize(96, 120)
		holder:SetPoint("TOPLEFT", status, "BOTTOMLEFT", (i - 1) * 104, -10)
		local edge = holder:CreateTexture(nil, "BACKGROUND")
		edge:SetPoint("TOPLEFT")
		edge:SetSize(96, 96)
		edge:SetColorTexture(0.3, 0.3, 0.3, 1)
		holder.tex = holder:CreateTexture(nil, "ARTWORK")
		holder.tex:SetPoint("TOPLEFT", 2, -2)
		holder.tex:SetSize(92, 92)
		holder.label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		holder.label:SetPoint("TOP", edge, "BOTTOM", 0, -4)
		holder.label:SetWidth(96)
		squares[i] = holder
		return holder
	end

	local function Refresh()
		show:SetText(copy and copy:IsShown() and "Hide copy" or "Show copy")
		local dir, gx = Where()
		if #results == 0 then
			status:SetText(dir and "Not tested yet." or ("Can't test here: " .. tostring(gx)))
		else
			status:SetText(pattern and ("|cff40ff40Using:|r " .. pattern[1] .. ". Show copy draws from it.") or
				"|cffff4040No tile loaded.|r Any map art in a square below?")
		end
		for i, try in ipairs(results) do
			local square = Square(i)
			square.tex:SetTexture(try.path)
			local color = try.verdict == "loaded" and "|cff40ff40" or try.verdict == "can't tell" and "|cffffd100"
				or "|cffff4040"
			square.label:SetText(("%d. %s%s|r\n|cff999999%s|r"):format(i, color, try.verdict,
				try.shape.id and (try.shape[2] and "ID, swapped" or "file ID") or "path"))
			square:Show()
		end
		for i = #results + 1, #squares do squares[i]:Hide() end
	end
	test:SetScript("OnClick", function()
		ns.MinimapCopyTest()
		Refresh()
	end)
	show:SetScript("OnClick", function()
		ns.MinimapCopyShow()
		Refresh()
	end)
	canvas:SetScript("OnShow", kit.PageShown(Refresh, content))
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Minimap Copy", "Minimap Copy")
end
