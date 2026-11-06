-- /cine debug themeshots [theme] | off: screenshots of the style themes in the
-- game itself, for looking at them outside it (Tools/style-lab draws them from
-- the code; only these show the game's real art and text). Each theme in turn:
-- two boards of the Style pages' previews, then the real screen: every kind of
-- nameplate on, the tooltip on you, a zone card and Damage Vision's test. Every
-- shot names itself, in a strip along its top. The settings window, if open,
-- shows in that last shot: it's left alone (opening or closing it from here
-- risks taint).
--
-- Your settings and the nameplate CVars come back at the end, on off, and at
-- the next login if a reload cuts it short (db.themeShotsKept, themeShotsCVars).

local _, ns = ...

local SETTLE, AFTER = 1.8, 0.7 -- (seconds: a card plays in; the shot's written)
local COLUMNS, CELL_W, CELL_H, HEAD_H, GAP = 3, 480, 300, 22, 12
local STRIP_H = 30

local BOARDS = {
	{ name = "HUD and overhead", cells = {
		{ "Unit frames", "MakeUnitStylePreview" }, { "Raid frames", "MakeRaidStylePreview" },
		{ "Personal resource display", "MakePersonalPreview" }, { "Tooltips", "MakeTooltipPreview" },
		{ "Nameplate and cast bar", "MakeGeneralPlatePreview" }, { "Chat bubbles", "MakeBubblePreview" },
	} },
	{ name = "Visions", cells = {
		{ "Quest dialogue", "MakeQuestTalkPreview" }, { "Quest item button", "MakeQuestItemPreview" },
		{ "Roll window", "MakeRollPreview" }, { "Zone card", "MakeCardPreview", 480, 270 },
		{ "Action bars", "MakeActionBarPreview", content = true },
	} },
}

-- (On for the whole run, so the plates are up by the first screen shot.)
local PLATE_CVARS = { "nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriends", "nameplateShowFriendlyPlayers",
	"nameplateShowFriendlyNPCs" }

local screen, strip, label -- (made once)
local run -- (the run going: stops it when it's replaced)

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

-- The boards: every preview on a dark screen, scaled to fit three across.
local function Boards()
	if screen then return end
	screen = CreateFrame("Frame", nil, UIParent)
	screen:SetFrameStrata("FULLSCREEN_DIALOG")
	screen:SetAllPoints(UIParent)
	screen:EnableMouse(true)
	local back = screen:CreateTexture(nil, "BACKGROUND", nil, -8)
	back:SetAllPoints()
	back:SetColorTexture(0.05, 0.05, 0.06, 1)
	local scale = math.min((UIParent:GetWidth() - GAP * (COLUMNS + 1)) / (COLUMNS * CELL_W),
		(UIParent:GetHeight() - STRIP_H - GAP * 3) / (2 * (CELL_H + HEAD_H)))
	for _, board in ipairs(BOARDS) do
		board.frame = CreateFrame("Frame", nil, screen)
		board.frame:SetAllPoints()
		board.previews = {}
		for i, cell in ipairs(board.cells) do
			local make = ns[cell[2]]
			local ok, preview
			if make then
				if cell.content then
					ok, preview = pcall(make, board.frame)
				else
					ok, preview = pcall(make, board.frame, cell[3] or CELL_W, cell[4])
				end
			end
			if ok and preview then
				local column, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
				local x = GAP + column * (CELL_W * scale + GAP)
				local y = -(STRIP_H + GAP + row * ((CELL_H + HEAD_H) * scale + GAP))
				local name = board.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				name:SetPoint("TOPLEFT", board.frame, "TOPLEFT", x, y)
				name:SetText(cell[1])
				preview:ClearAllPoints()
				preview:SetScale(scale)
				preview:SetPoint("TOPLEFT", board.frame, "TOPLEFT", x / scale, (y - HEAD_H * scale) / scale)
				board.previews[#board.previews + 1] = preview
			end
		end
	end
	screen:Hide()
end

local function ShowBoard(which)
	screen:Show()
	for _, board in ipairs(BOARDS) do
		board.frame:SetShown(board == which)
		if board == which then
			for _, preview in ipairs(board.previews) do
				if preview.Refresh then pcall(preview.Refresh, preview) end
			end
		end
	end
end

local function Label(theme, scene, index, total)
	label:SetText(("Cinematic themeshots %d/%d: %s - %s (%s, scale %.2f)"):format(index, total, theme.name, scene,
		ns.isRetail and "retail" or "classic", UIParent:GetEffectiveScale()))
	strip:Show()
end

-- The settings from before a run, back.
local function Restore()
	local db = ns.GetDB()
	if not db then return end
	if type(db.themeShotsCVars) == "table" then
		for name, value in pairs(db.themeShotsCVars) do pcall(SetCVar, name, value) end
		db.themeShotsCVars = nil
	end
	local kept = db.themeShotsKept
	if type(kept) ~= "table" then return end
	ns.RestoreStyleSnapshot(kept)
	db.themeShotsKept = nil
end

-- Gives how many it left alone: one held by CineMode can't be touched. A write
-- reads as the player's own change, so the hold would let go of the value it's
-- keeping for you, and that value would be lost.
local function PlatesOn(db)
	local kept, held = {}, 0
	for _, name in ipairs(PLATE_CVARS) do
		local ok, value = pcall(GetCVar, name)
		if ns.IsCVarHeld(name) then
			held = held + 1
		elseif ok and value ~= nil then
			kept[name] = value
			pcall(SetCVar, name, "1")
		end
	end
	db.themeShotsCVars = kept
	return held
end

local function StopTests()
	if ns.StopDamageVisionTest then pcall(ns.StopDamageVisionTest) end
end

local function Finish(text)
	run = nil
	if screen then screen:Hide() end
	if strip then strip:Hide() end
	GameTooltip:Hide()
	StopTests()
	Restore()
	ns.Print(text)
end

local function Steps(themes)
	local steps = {}
	for _, theme in ipairs(themes) do
		for _, board in ipairs(BOARDS) do
			steps[#steps + 1] = { theme = theme, board = board, scene = board.name }
		end
		steps[#steps + 1] = { theme = theme, scene = "real frames, nameplates on" }
	end
	return steps
end

local function Play(steps, index, token)
	if run ~= token then return end
	local step = steps[index]
	if not step then
		local db = ns.GetDB()
		if db then
			db.themeShotsLast = { at = time(), shots = #steps, retail = ns.isRetail and true or false,
				scale = UIParent:GetEffectiveScale() }
		end
		Finish(("themeshots: %d shots done, in the Screenshots folder. Your settings are back."):format(#steps))
		return
	end
	if InCombatLockdown() then
		Finish("themeshots: stopped, a fight started. Your settings are back.")
		return
	end
	local ok, err = pcall(function()
		local last = steps[index - 1]
		if not last or last.theme ~= step.theme then ns.ApplyStyleTheme(step.theme.key, true) end
		Label(step.theme, step.scene, index, #steps)
		if step.board then
			StopTests()
			ShowBoard(step.board)
			GameTooltip:Hide()
		else
			screen:Hide()
			GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
			GameTooltip:SetUnit("player")
			GameTooltip:Show()
			if ns.CardTest then pcall(ns.CardTest, "zone") end
			if ns.TestDamageVision then pcall(ns.TestDamageVision, true) end
			if ns.ReportPlateHealthStyle then pcall(ns.ReportPlateHealthStyle, true) end
		end
	end)
	if not ok then
		Finish("themeshots: stopped on an error, your settings are back: " .. tostring(err))
		return
	end
	C_Timer.After(SETTLE, function()
		if run ~= token then return end
		Screenshot()
		C_Timer.After(AFTER, function() Play(steps, index + 1, token) end)
	end)
end

function ns.ThemeShots(text)
	text = (text or ""):match("^%s*(.-)%s*$"):lower()
	if text == "off" then
		if run then
			Finish("themeshots: stopped. Your settings are back.")
		else
			ns.Print("themeshots: not running.")
		end
		return
	end
	if run then
		ns.Print("themeshots: already running. /cine debug themeshots off stops it.")
		return
	end
	if InCombatLockdown() then
		ns.Print("themeshots: not in a fight.")
		return
	end
	if not Screenshot then
		ns.Print("themeshots: this client has no Screenshot.")
		return
	end
	local themes = {}
	for _, theme in ipairs(ns.StyleThemeList()) do
		if text == "" or text == theme.key or text == theme.name:lower() then themes[#themes + 1] = theme end
	end
	if #themes == 0 then
		local keys = {}
		for i, theme in ipairs(ns.StyleThemeList()) do keys[i] = theme.key end
		ns.Print("themeshots: no such theme. Themes: " .. table.concat(keys, ", "))
		return
	end
	local db = ns.GetDB()
	db.themeShotsKept = ns.StyleSnapshot()
	db.themeShotsKept.cards = db.cards
	db.cards = true -- (off, a card's look reads as its defaults)
	local held = PlatesOn(db)
	Strip()
	Boards()
	local steps = Steps(themes)
	ns.Print(("themeshots: %d shots, about %d seconds. Client %s, theme now %s, Style %s, UI scale %.2f, UI alpha %.2f."):format(
		#steps, math.ceil(#steps * (SETTLE + AFTER)), ns.isRetail and "retail" or "classic", tostring(db.styleTheme),
		db.styleGeneral and "on" or "off", UIParent:GetEffectiveScale(), UIParent:GetAlpha()))
	-- (Two lines at most: three open the debug copy window, over the shots.)
	ns.Print(("themeshots: %d nameplate settings held by CineMode, left alone. %s Best beside NPCs, with a target, outside CineMode."):format(
		held, (_G.SettingsPanel and _G.SettingsPanel:IsShown()) and "" or "Open Style > General first for the menus."))
	run = {}
	Play(steps, 1, run)
end

-- A reload cut a run short: its settings back as you log in.
local watch = CreateFrame("Frame")
watch:RegisterEvent("PLAYER_LOGIN")
watch:SetScript("OnEvent", Restore)
