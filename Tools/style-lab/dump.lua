-- Runs the addon's own preview code on real layout (frames.lua), once per
-- style theme, and writes what each frame drew as JSON, for build.py. From the
-- repo root:
--
--   python -I Tools/offline/run.py Tools/style-lab/dump.lua <client> <out.json>
--
-- Nothing here draws a frame by hand: a change to a preview or a theme shows
-- at the next build.

local F = dofile("Tools/style-lab/frames.lua")
local client, outPath = ...
client, outPath = client or "retail", outPath or "Tools/style-lab/out/dump.json"

local ns, wow = dofile("Tools/offline/load.lua")(client, "CinematicDev.toc", function(w)
	F.Install(w)
	local M = w.Methods
	-- (A scroll frame's child sits at its top left, as wide as it.)
	M.SetScrollChild = function(self, child)
		child:ClearAllPoints()
		child:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
		self._scrollChild = child
	end
	-- (The sample names the previews ask the game for. A stub here would loop
	-- for ever in a card's letter by letter text.)
	-- (No font families here: text keeps the plain font it's given.)
	rawset(_G, "CreateFontFamily", false)
	_G.GetBindingKey = function() return nil end
	-- (Lists of spells on a page, shown by name.)
	_G.C_Spell = _G.C_Spell or {}
	_G.C_Spell.GetSpellInfo = function() return { name = "Spell", iconID = 134400 } end
	_G.GetTime = function() return F.now or 0 end
	_G.ChatTypeInfo = { SAY = { r = 1, g = 1, b = 1 }, YELL = { r = 1, g = 0.25, b = 0.25 } }
	_G.GetRealZoneText = function() return "Darkshore" end
	_G.GetZoneText = _G.GetRealZoneText
	_G.GetSubZoneText = function() return "Auberdine" end
	_G.GetMinimapZoneText = _G.GetSubZoneText
	-- (The game's quest window isn't here: the dialogue preview uses its own page.)
	for _, name in ipairs({ "QuestFrameRewardPanel", "QuestFrameProgressPanel", "QuestFrameDetailPanel",
		"QuestFrameGreetingPanel" }) do
		rawset(_G, name, false)
	end
end)

-- JSON (numbers to two places: the page draws at pixels).
local function Json(value, out)
	local kind = type(value)
	if kind == "nil" then
		out[#out + 1] = "null"
	elseif kind == "boolean" then
		out[#out + 1] = tostring(value)
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then value = 0 end
		out[#out + 1] = ("%.3f"):format(value):gsub("0+$", ""):gsub("%.$", "")
	elseif kind == "string" then
		out[#out + 1] = '"' .. value:gsub('[%c"\\]', function(c)
			local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
			return named[c] or ("\\u%04x"):format(c:byte())
		end) .. '"'
	elseif kind == "table" then
		if value[1] ~= nil or next(value) == nil then
			out[#out + 1] = "["
			for i, each in ipairs(value) do
				if i > 1 then out[#out + 1] = "," end
				Json(each, out)
			end
			out[#out + 1] = "]"
		else
			out[#out + 1] = "{"
			local first = true
			for k, each in pairs(value) do
				if type(k) == "string" and type(each) ~= "function" and not (type(each) == "table" and rawget(each, "_kind")) then
					if not first then out[#out + 1] = "," end
					first = false
					Json(k, out)
					out[#out + 1] = ":"
					Json(each, out)
				end
			end
			out[#out + 1] = "}"
		end
	else
		out[#out + 1] = "null"
	end
end

-- The frames: a preview's maker on the addon's namespace, drawn at 480 wide,
-- as the Style pages show them.
local FRAMES = {
	{ id = "unit", name = "Unit frames", group = "HUD", page = "Style > Unit Frames", make = "MakeUnitStylePreview" },
	{ id = "raid", name = "Raid frames", group = "HUD", page = "Style > Raid Frames", make = "MakeRaidStylePreview" },
	{ id = "prd", name = "Personal resource display", group = "HUD", page = "Style > Personal Resource Display",
		make = "MakePersonalPreview" },
	{ id = "action", name = "Action bars", group = "HUD", page = "Style > Action Bars", make = "MakeActionBarPreview",
		content = true },
	{ id = "tooltip", name = "Tooltips", group = "HUD", page = "Style > Tooltips", make = "MakeTooltipPreview" },
	{ id = "plate", name = "Nameplate and cast bar", group = "Overhead", page = "Style > Nameplates, Cast Bars",
		make = "MakeGeneralPlatePreview", settle = 1.4 },
	{ id = "bubble", name = "Chat bubbles", group = "Overhead", page = "Style > Chat Bubbles", make = "MakeBubblePreview" },
	{ id = "talk", name = "Quest dialogue", group = "Visions", page = "Quest Vision > Dialogue",
		make = "MakeQuestTalkPreview" },
	{ id = "item", name = "Quest item button", group = "Visions", page = "Quest Vision > Quest Item Button",
		make = "MakeQuestItemPreview" },
	{ id = "roll", name = "Roll window", group = "Visions", page = "Roll Vision > Style", make = "MakeRollPreview" },
	{ id = "card", name = "Zone card", group = "Visions", page = "Card Vision", make = "MakeCardPreview", width = 960, height = 540, crop = { 0, 340, 520, 170 },
		settle = 1.6 },
}
-- Whole settings pages, drawn as the menu draws them.
local PAGES = {
	{ id = "page-cinemode", name = "CineMode page", group = "Menu", page = "CineMode", pageName = "CineMode" },
	{ id = "page-general", name = "Style: General page", group = "Menu", page = "Style > General", pageName = "Style General" },
	{ id = "page-pages", name = "Style: Pages tab", group = "Menu", page = "Style > General > Pages", pageName = "Style Pages" },
	{ id = "page-overrides", name = "Style: Overrides tab", group = "Menu", page = "Style > General > Overrides", pageName = "Style Overrides" },
	{ id = "page-tooltip", name = "Style: Tooltips page", group = "Menu", page = "Style > Tooltips", pageName = "Tooltip Style" },
	{ id = "page-cast", name = "Style: Cast Bars page", group = "Menu", page = "Style > Cast Bars", pageName = "Cast Bar Style" },
	{ id = "page-damage", name = "Damage Vision: Style page", group = "Menu", page = "Damage Vision > Style", pageName = "Damage Vision Look" },
}

local holders = {}
local function Holder(info)
	local holder = holders[info.id]
	if holder then return holder end
	local make = ns[info.make]
	if not make then return nil end
	local ok, made
	if info.content then
		ok, made = pcall(make, UIParent)
	else
		ok, made = pcall(make, UIParent, info.width or 480, info.height)
	end
	if not ok then
		wow.Warn(info.id .. ": " .. tostring(made))
		return nil
	end
	made:ClearAllPoints()
	made:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	holders[info.id] = made
	return made
end

-- OnUpdates under frame run for seconds (a card plays in).
local function Settle(frame, seconds)
	local step = 0.1
	local function Tick(each)
		local fn = each._scripts and each._scripts.OnUpdate
		if fn then pcall(fn, each, step) end
		for _, child in ipairs(each._children or {}) do
			if child._scripts then Tick(child) end
		end
	end
	for _ = 1, math.floor(seconds / step) do
		F.now = (F.now or 0) + step
		Tick(frame)
	end
end

local function Shot(info)
	local holder = Holder(info)
	if not holder then return nil end
	local ok, err = pcall(holder.Refresh, holder)
	if not ok then wow.Warn(info.id .. " refresh: " .. tostring(err)) end
	if info.settle then Settle(holder, info.settle) end
	local items, w, h = F.Dump(holder)
	return { w = w, h = h, items = items, crop = info.crop }
end

local function PageCanvas(name)
	for _, frame in ipairs(wow.frames) do
		if rawget(frame, "pageName") == name then return frame end
	end
end

local function PageShot(info)
	local canvas = PageCanvas(info.pageName)
	if not canvas then
		wow.Warn("no page " .. info.pageName)
		return nil
	end
	canvas:SetParent(UIParent)
	canvas:ClearAllPoints()
	canvas:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	canvas:SetSize(660, 1060)
	if canvas.content then canvas.content:SetWidth(640) end
	-- (Shown, as the game would: everything under it hears OnShow.)
	local function Shown(frame)
		local fn = frame._scripts and frame._scripts.OnShow
		if fn and frame:IsVisible() then pcall(fn, frame) end
		-- (The page's own refresh, control by control.)
		local refresh = rawget(frame, "Refresh")
		if type(refresh) == "function" and frame:IsVisible() then pcall(refresh, frame) end
		for _, child in ipairs(frame._children or {}) do
			if child._scripts then Shown(child) end
		end
	end
	canvas:Show()
	Shown(canvas)
	if ns.lowHealthKit and ns.lowHealthKit.Refresh then pcall(ns.lowHealthKit.Refresh) end
	if ns.ApplyMenuSkin then ns.ApplyMenuSkin(true) end
	local items, w, h = F.Dump(canvas)
	return { w = w, h = h, items = items }
end

local function ThemeList()
	if ns.StyleThemeList then return ns.StyleThemeList() end
	return { { key = "game", name = "The game's" } }
end

local result = { frames = {}, themes = {}, shots = {} }
for _, info in ipairs(FRAMES) do
	result.frames[#result.frames + 1] = { id = info.id, name = info.name, group = info.group, page = info.page }
end
for _, info in ipairs(PAGES) do
	result.frames[#result.frames + 1] = { id = info.id, name = info.name, group = info.group, page = info.page }
end
_G.CinematicDB = _G.CinematicDB or {}
_G.CinematicDB.menuSkin = "HD"
for _, theme in ipairs(ThemeList()) do
	if ns.ApplyStyleTheme then ns.ApplyStyleTheme(theme.key) end
	ns.db.cards = true -- (Card Vision on: off, its look reads as its defaults)
	result.themes[#result.themes + 1] = { key = theme.key, name = theme.name, tip = theme.tip, swatch = theme.swatch }
	local shots = {}
	for _, info in ipairs(FRAMES) do shots[info.id] = Shot(info) end
	for _, info in ipairs(PAGES) do shots[info.id] = PageShot(info) end
	result.shots[theme.key] = shots
end
result.warnings = wow.warnings

local out = {}
Json(result, out)
local file = assert(io.open(outPath, "w"))
file:write(table.concat(out))
file:close()
print(("%d themes, %d frames, %d warnings"):format(#result.themes, #result.frames, #wow.warnings))
for i = 1, math.min(#wow.warnings, 20) do print(wow.warnings[i]) end
