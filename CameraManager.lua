-- Cinematic: the Camera hub's General page as a camera manager. Every camera
-- (each built-in script, then yours) as an icon; a click opens a folder tab of
-- its own beside General with its script and the Scenes rows that play it,
-- each a link to its place on the Scripts or Scenes page. The General tab
-- again closes the camera's tab. (Built from Options.lua's CreateCamerasPanel.)
local _, ns = ...
local L = ns.L

local WIDTH = 568
local TILE_W, TILE_H, TILE_GAP, PER_ROW = 88, 84, 8, 6
local LINK_H = 40
local NONE_COLOR = { 0.85, 0.35, 0.28 }

-- Each built-in camera's icon (by script id); yours share one.
local ICONS = {
	afk = "Interface\\Icons\\Spell_Nature_Sleep", still = "Interface\\Icons\\Spell_Nature_TimeStop",
	cozy = "Interface\\Icons\\Spell_Fire_Fire", vista = "Interface\\Icons\\Ability_EyeOfTheOwl",
	fish = "Interface\\Icons\\Trade_Fishing", tele = "Interface\\Icons\\INV_Misc_Rune_01",
	flight = "Interface\\Icons\\Ability_Mount_Wyvern_01", flyby = "Interface\\Icons\\Ability_Hunter_EagleEye",
	walk = "Interface\\Icons\\INV_Boots_01", run = "Interface\\Icons\\Ability_Rogue_Sprint",
	death = "Interface\\Icons\\Ability_Rogue_FeignDeath", quest = "Interface\\Icons\\INV_Misc_Note_01",
	chat = "Interface\\Icons\\Ability_Warrior_RallyingCry",
}
local MINE_ICON = "Interface\\Icons\\INV_Misc_Spyglass_02"
local SCRIPT_ICON = "Interface\\Icons\\INV_Scroll_05"
local function IconOf(script) return ICONS[script.id] or MINE_ICON end

-- A row's camera value and the script that is it (CameraRows.lua's values:
-- a built-in camera's, true for the Die row's, "script:<id>" for a script).
local VALUE_SCRIPT = { cozy = "cozy", vista = "vista", fish = "fish", afk = "afk", tele = "tele", flight = "flight",
	quest = "quest", walk = "walk", run = "run", [true] = "death", death = "death", chat = "chat" }
-- Scripts that run as part of another camera: a flight's fly-bys, the AFK
-- camera's standing-still zoom.
local PART_OF = { flight = "flyby", afk = "still" }

-- Every Scenes row that plays each script: uses[id] = { { row, via } ... }
-- (via: the camera it's part of, for a part).
local function Uses()
	local uses = {}
	local function Add(id, row, via)
		uses[id] = uses[id] or {}
		table.insert(uses[id], { row = row, via = via })
	end
	for _, row in ipairs(ns.CameraRowOrder()) do
		local trigger = ns.CameraRowTrigger(row)
		local value = ns.CameraRowValue(row, "camera")
		if trigger and value ~= trigger.off then
			if ns.ShotBase then value = ns.ShotBase(value) end
			local id = ns.IsScriptCamera(value) and value:sub(8) or VALUE_SCRIPT[value]
			if id then
				Add(id, row)
				if PART_OF[id] then Add(PART_OF[id], row, id) end
			end
		end
	end
	return uses
end

local function Paint(text, color)
	text:SetTextColor(color[1], color[2], color[3])
	text:SetVertexColor(color[1], color[2], color[3]) -- (one on Forever)
end

-- A camera's icon on the grid: its icon, name and how many scenes play it.
local function Tile(parent, kit, onClick)
	local tile = CreateFrame("Button", nil, parent)
	tile:SetSize(TILE_W, TILE_H)
	local bg = tile:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.04)
	local hover = tile:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 0.82, 0, 0.1)
	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetSize(40, 40)
	tile.icon:SetPoint("TOP", 0, -6)
	tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	tile.name = kit.Label(tile, "GameFontHighlightSmall", "")
	tile.name:SetPoint("TOP", tile.icon, "BOTTOM", 0, -3)
	tile.name:SetWidth(TILE_W - 6)
	tile.name:SetJustifyH("CENTER")
	if tile.name.SetMaxLines then tile.name:SetMaxLines(2) end
	tile.count = kit.Label(tile, "GameFontDisableSmall", "")
	tile.count:SetPoint("BOTTOM", 0, 4)
	tile:SetScript("OnClick", function(self) onClick(self.script) end)
	tile:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.name:GetText() or "", 1, 0.82, 0)
		GameTooltip:AddLine(self.script and L["Click to see its script and the scenes that play it."]
			or L["A new camera of yours, with a few steps to start from."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return tile
end

-- A line on the camera's tab that opens something: an icon, a name, a line
-- under it, and where it goes on the right.
local function LinkRow(parent, kit)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(WIDTH, LINK_H)
	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.04)
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 0.82, 0, 0.1)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(28, 28)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.go = kit.Label(row, "GameFontNormalSmall", "")
	row.go:SetPoint("RIGHT", -10, 0)
	row.title = kit.Label(row, "GameFontHighlight", "")
	row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
	row.title:SetPoint("RIGHT", row.go, "LEFT", -10, 0)
	row.title:SetJustifyH("LEFT")
	row.title:SetWordWrap(false)
	row.sub = kit.Label(row, "GameFontDisableSmall", "")
	row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
	row.sub:SetPoint("RIGHT", row.go, "LEFT", -10, 0)
	row.sub:SetJustifyH("LEFT")
	row.sub:SetWordWrap(false)
	return row
end

-- canvas, content: the General page's; title, intro, switch: what's on it
-- now (hidden while a camera's tab is open).
function ns.CameraManager(kit, canvas, content, title, intro, switch)
	local openId -- (the camera whose tab is open, or nil)
	local Pick -- (below)

	-- The folder tabs: General, and the camera's (hidden while none is open).
	local panel, tabs, ShowTab, base = ns.FolderTabs(content, { { L["General"] }, { "" } }, function(i) Pick(i) end)
	base:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -(ns.FOLDER_TAB_HEIGHT + 16))
	panel:SetPoint("TOPLEFT", base)
	panel:SetPoint("RIGHT", content, "RIGHT", -8, 0)
	panel:SetHeight(1)
	tabs[2]:Hide()
	ShowTab(1)
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)

	-- The General tab: every camera, built in then yours.
	local grid = CreateFrame("Frame", nil, content)
	grid:SetSize(WIDTH, 1)
	grid:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 2, -16)
	local builtInHead = kit.Label(grid, "GameFontNormal", L["Built in"])
	local mineHead = kit.Label(grid, "GameFontNormal", L["Yours"])
	local tiles = {}

	-- A camera's tab.
	local view = CreateFrame("Frame", nil, content)
	view:SetSize(WIDTH, 1)
	view:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -14)
	view:Hide()
	local bigIcon = view:CreateTexture(nil, "ARTWORK")
	bigIcon:SetSize(44, 44)
	bigIcon:SetPoint("TOPLEFT")
	bigIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local camName = kit.Label(view, "GameFontNormalLarge", "")
	camName:SetPoint("TOPLEFT", bigIcon, "TOPRIGHT", 10, -4)
	local camKind = kit.Label(view, "GameFontDisableSmall", "")
	camKind:SetPoint("TOPLEFT", camName, "BOTTOMLEFT", 0, -6)
	local scriptHead = kit.Label(view, "GameFontNormal", L["Script"])
	scriptHead:SetPoint("TOPLEFT", bigIcon, "BOTTOMLEFT", 0, -18)
	local scriptRow = LinkRow(view, kit)
	scriptRow:SetPoint("TOPLEFT", scriptHead, "BOTTOMLEFT", 0, -6)
	scriptRow.icon:SetTexture(SCRIPT_ICON)
	scriptRow.go:SetText(L["Open on Scripts >"])
	scriptRow:SetScript("OnClick", function()
		if openId and ns.ShowCameraScript then ns.ShowCameraScript(openId) end
	end)
	local scenesHead = kit.Label(view, "GameFontNormal", L["Played by"])
	scenesHead:SetPoint("TOPLEFT", scriptRow, "BOTTOMLEFT", 0, -18)
	local noScenes = kit.Label(view, "GameFontDisable", L["No scene plays this camera yet: pick it as a scene's camera on the Scenes page."])
	noScenes:SetPoint("TOPLEFT", scenesHead, "BOTTOMLEFT", 0, -8)
	noScenes:SetWidth(WIDTH)
	noScenes:SetJustifyH("LEFT")
	local sceneRows = {}
	local run = ns.PanelButton(view)
	run:SetSize(70, 22)
	run:SetText(L["Run"])
	kit.Tooltip(run, L["Moves the real camera through this script now (click again to stop it). Its stop rules count, as for a trigger."])
	local function Running()
		local state = ns.CameraScriptState and ns.CameraScriptState()
		return state and state.script.id == openId
	end
	run:SetScript("OnClick", function()
		if Running() then
			ns.StopCameraScript()
		else
			local played, why = ns.PlayCameraScript(ns.FindCameraScript(openId))
			if not played then ns.Print(why) end
		end
	end)
	local runningWas
	run:SetScript("OnUpdate", function(self)
		local running = Running() and true or false
		if running ~= runningWas then
			runningWas = running
			self:SetText(running and L["Stop"] or L["Run"])
		end
	end)
	local copy = ns.PanelButton(view)
	copy:SetSize(110, 22)
	copy:SetText(L["Copy to yours"])
	copy:SetPoint("LEFT", run, "RIGHT", 6, 0)
	kit.Tooltip(copy, L["A copy of this camera's script, yours to change, and its tab opened."])

	local function Fit()
		C_Timer.After(0, function() kit.FitContentHeight(content) end)
	end

	-- The General tab's icons, as the scripts are now.
	local function LayoutGrid()
		local scripts, uses = ns.CameraScripts(), Uses()
		local builtIn, mine = {}, {}
		for _, script in ipairs(scripts) do
			table.insert(script.builtin and builtIn or mine, script)
		end
		local used, y = 0, 0
		local function Place(list, head, withNew)
			head:ClearAllPoints()
			head:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
			y = y + 20
			local count = #list + (withNew and 1 or 0)
			for i = 1, count do
				used = used + 1
				local tile = tiles[used] or Tile(grid, kit, function(script) Pick(2, script and script.id) end)
				tiles[used] = tile
				local script = list[i]
				tile.script = script
				if script then
					local n = uses[script.id] and #uses[script.id] or 0
					tile.icon:SetTexture(IconOf(script))
					tile.icon:SetDesaturated(false)
					tile.name:SetText(script.name)
					tile.count:SetText(n == 0 and L["In no scene"] or n == 1 and L["1 scene"] or L["%d scenes"]:format(n))
					Paint(tile.count, n == 0 and NONE_COLOR or { 0.6, 0.6, 0.6 })
				else
					tile.icon:SetTexture("Interface\\PaperDollInfoFrame\\Character-Plus")
					tile.name:SetText(L["+ New camera"])
					tile.count:SetText("")
				end
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", grid, "TOPLEFT", ((i - 1) % PER_ROW) * (TILE_W + TILE_GAP),
					-(y + math.floor((i - 1) / PER_ROW) * (TILE_H + TILE_GAP)))
				tile:Show()
			end
			y = y + math.ceil(count / PER_ROW) * (TILE_H + TILE_GAP) + 10
		end
		Place(builtIn, builtInHead)
		Place(mine, mineHead, true)
		for i = used + 1, #tiles do tiles[i]:Hide() end
		grid:SetHeight(y)
	end

	-- The open camera's tab: its script and the rows that play it.
	local function LayoutView()
		local script = ns.FindCameraScript(openId)
		if not script then return false end
		local uses = Uses()[openId] or {}
		bigIcon:SetTexture(IconOf(script))
		camName:SetText(script.name)
		local kind = script.builtin and L["Built-in camera"] or L["Your camera"]
		camKind:SetText(kind .. " · " .. (#uses == 0 and L["in no scene"] or #uses == 1 and L["1 scene"]
			or L["%d scenes"]:format(#uses)))
		scriptRow.title:SetText(script.name)
		scriptRow.sub:SetText(ns.CameraScriptSummary and ns.CameraScriptSummary(script) or "")
		scriptRow:SetShown(ns.ShowCameraScript ~= nil)
		local last = scenesHead
		for i, use in ipairs(uses) do
			local row = sceneRows[i] or LinkRow(view, kit)
			sceneRows[i] = row
			local trigger = ns.CameraRowTrigger(use.row)
			local name = ns.SceneRowLabel and ns.SceneRowLabel(use.row) or trigger.key
			if not ns.CameraRowOn(use.row) then name = name .. " " .. L["(off)"] end
			local sub = ns.SceneRowTriggers and ns.SceneRowTriggers(use.row) or ""
			if use.via then
				local via = ns.FindCameraScript(use.via)
				sub = L["With the %s"]:format(via and via.name or use.via) .. (sub ~= "" and " · " .. sub or "")
			end
			row.title:SetText(name)
			row.sub:SetText(sub)
			row.go:SetText(L["Open on Scenes >"])
			local value = ns.CameraRowValue(use.row, "camera")
			if ns.ShotBase then value = ns.ShotBase(value) end
			local id = ns.IsScriptCamera(value) and value:sub(8) or VALUE_SCRIPT[value]
			local of = id and ns.FindCameraScript(id)
			row.icon:SetTexture(of and IconOf(of) or MINE_ICON)
			row:SetScript("OnClick", function()
				if ns.ShowSceneRow then ns.ShowSceneRow(use.row) end
			end)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, i == 1 and -6 or -4)
			row:Show()
			last = row
		end
		for i = #uses + 1, #sceneRows do sceneRows[i]:Hide() end
		noScenes:SetShown(#uses == 0)
		if #uses == 0 then last = noScenes end
		run:ClearAllPoints()
		run:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -18)
		copy:SetShown(script.builtin and true or false)
		local tab = tabs[2]
		tab:SetText(("|T%s:16:16:0:0:64:64:5:59:5:59|t %s"):format(IconOf(script), script.name))
		tab:SetWidth(math.max(48, math.ceil(tab:GetFontString():GetStringWidth()) + 18))
		return true
	end

	-- Tab 1: General (the camera's tab closes); tab 2: id's (a new camera of
	-- yours for none), or the one open.
	function Pick(i, id)
		if i == 2 and id == nil and openId == nil then
			local script = ns.AddCameraScript(nil, L["My camera %d"]:format(#ns.CameraScripts() + 1))
			if not script then
				ns.Print(L["You have 30 camera scripts already: delete one to add another."])
				return
			end
			id = script.id
		end
		if i == 2 then openId = id or openId end
		if i == 2 and not LayoutView() then i, openId = 1, nil end
		if i == 1 then openId = nil end
		tabs[2]:SetShown(openId ~= nil)
		ShowTab(i)
		local general = i == 1
		title:SetShown(general)
		intro:SetShown(general)
		switch:SetShown(general)
		grid:SetShown(general)
		view:SetShown(not general)
		if general then LayoutGrid() end
		if canvas.scroll then canvas.scroll:SetVerticalScroll(0) end
		Fit()
	end
	copy:SetScript("OnClick", function()
		local script = ns.AddCameraScript(ns.FindCameraScript(openId))
		if script then
			Pick(2, script.id)
		else
			ns.Print(L["You have 30 camera scripts already: delete one to add another."])
		end
	end)

	-- Kept up with the page's Refresh (a script added or renamed, a row's
	-- camera changed), the tab that's showing.
	grid.Refresh = function()
		if not content:IsVisible() then return end
		if openId then
			if not LayoutView() then Pick(1) end
		else
			LayoutGrid()
		end
		Fit()
	end
	kit.AddControl(grid) -- (the page's Refresh runs as it's shown too)
	-- Off to another page (a camera tab's link to Scenes or Scripts, say):
	-- back here, it's the General tab again, the camera's tab closed.
	canvas:HookScript("OnHide", function()
		if openId then Pick(1) end
	end)
end
