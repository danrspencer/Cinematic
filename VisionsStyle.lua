-- The Visions hub's Style page: the look every Vision shares (font, outline,
-- shadow, bar texture, border, text size), each starting on the Style hub's
-- General page's (StylePages.lua's visionStyle* settings: a Vision's shared
-- setting on "general" follows this page, and this page's on "general"
-- follows General), and which Visions follow it.

local _, ns = ...
local L = ns.L

-- The Visions that share settings, as the list shows them: name, the page
-- to open (ns.OpenOptions), how their shared settings' keys start.
local VISIONS = {
	{ "Damage Vision", "Damage Vision Look", "damageVision" },
	{ "Dialogue", "Quest Talk Style", "questTalk" },
	{ "Quest item button", "Quest Item Style", "questItem" },
	{ "Roll Vision", "Roll Style", "roll" },
	{ "Card Vision", "Card Styles", "card" },
}
local KIND_NAMES = { texture = "Texture", font = "Font", outline = "Outline", shadow = "Shadow", border = "Border" }
-- (Its own settings, for Reset.)
local OWN_KEYS = { "visionStyleTexture", "visionStyleFont", "visionStyleOutline", "visionStyleShadow",
	"visionStyleBorder", "visionStyleBorderSize", "visionStyleBorderR", "visionStyleBorderG", "visionStyleBorderB",
	"visionStyleTextSize" }

-- A Vision's shared settings (not a border's thickness or color: those go
-- with the border), sorted so the list reads the same each time.
local function KeysOf(prefix)
	local keys = {}
	for key, entry in pairs(ns.SHARED_STYLE) do
		if entry.visions and not entry.follows and key:sub(1, #prefix) == prefix then keys[#keys + 1] = key end
	end
	table.sort(keys)
	return keys
end

-- Which kinds of a Vision's shared settings are its own (not on Visions Style).
local function OwnKinds(keys)
	local db = ns.GetDB()
	local own, seen = {}, {}
	for _, key in ipairs(keys) do
		local value = db and db[key]
		local kind = ns.SHARED_STYLE[key].kind
		if value ~= nil and not ns.IsGeneralStyle(value) and not seen[kind] then
			seen[kind] = true
			own[#own + 1] = L[KIND_NAMES[kind] or "Texture"]
		end
	end
	return own
end

local function RefreshVisions()
	if ns.RefreshAllStyles then ns.RefreshAllStyles() end
	for _, refresh in ipairs({ ns.RefreshDamageVision, ns.RefreshQuestTalk }) do
		pcall(refresh)
	end
end

function ns.CreateVisionsStylePanel(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Visions Style"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title,
		L["The look every Vision shares. Each setting starts on the Style hub's General page's; a Vision with a " ..
		"setting of its own on its page keeps it."])

	local visionRows = {}
	local function Changed()
		RefreshVisions()
		for _, row in ipairs(visionRows) do row:Refresh() end
	end

	local stack = kit.Stack(intro, "label")
	local rows = ns.StyleRows(kit, content, stack, Changed) -- (greyed with the Style hub's Enable Style)
	local OWN = L["Each Vision's own"]

	stack:Header(content, L["Shared look"])
	rows.Font("visionStyleFont", L["Every Vision's words that follow this page. Each Vision's own: the game's " ..
		"font, or the one its page starts with."])
	rows.Outline("visionStyleOutline", L["Outline"], 2, { [0] = L["None"], L["Thin"], L["Thick"], game = OWN },
		L["A black border round the letters, on every Vision that follows this page."])
	rows.Choices(L["Shadow:"], "visionStyleShadow", {
		{ "general", L["Interface Style"], L["As the Style hub's General page says."] },
		{ "game", L["The game's"] },
		{ "on", L["Shadow"], L["A dark copy of the letters just behind them, down and to the right."] },
		{ "none", L["None"] },
	})
	rows.Slider("visionStyleTextSize", L["Text size"], 70, 150, 5, "%d%%", 100,
		L["Every Vision's words bigger or smaller, times each one's own size on its page (cards too)."])
	rows.Texture(L["Bar texture:"], "visionStyleTexture", L["The bars of every Vision that follows this page " ..
		"(Damage Vision's, Roll Vision's time left). Below the game's own few: any other addon shares (through " ..
		"LibSharedMedia)."], nil, { 0.25, 0.75, 0.3 }, OWN)
	rows.Border(L["Border:"], "visionStyleBorder", { game = OWN }, L["The border round the Vision parts that " ..
		"follow this page (the quest item button's frame). Custom: its thickness and color under it."])

	stack:Header(content, L["Visions"])
	stack:Help(content, L["Which Visions follow this page. One with a setting of its own shows which; Use " ..
		"Visions Style puts them all back on this page. The name opens its page."])
	local lists = {}
	for _, vision in ipairs(VISIONS) do
		local keys = KeysOf(vision[3])
		-- (Only the ones this client has: one it lacks, like Roll Vision with
		-- no loot history, never set its defaults.)
		if #keys > 0 and ns.DEFAULTS[keys[1]] ~= nil then
			lists[#lists + 1] = keys
			local row = CreateFrame("Frame", nil, content)
			row:SetSize(480, 22)
			stack:Add(row, "label")
			local open = CreateFrame("Button", nil, row)
			open:SetSize(160, 22)
			open:SetPoint("LEFT")
			local name = open:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			name:SetPoint("LEFT")
			name:SetText(L[vision[1]])
			open:SetScript("OnClick", function() ns.OpenOptions(vision[2]) end)
			open:SetScript("OnEnter", function() name:SetTextColor(1, 0.82, 0) end)
			open:SetScript("OnLeave", function() name:SetTextColor(1, 1, 1) end)
			local status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			status:SetPoint("LEFT", open, "RIGHT", 4, 0)
			status.searchSkip = true
			local back = ns.PanelButton(row)
			back:SetSize(140, 20)
			back:SetPoint("LEFT", status, "RIGHT", 10, 0)
			back:SetText(L["Use Visions Style"])
			kit.Tooltip(back, L["This Vision's shared settings back on Visions Style."])
			back:SetScript("OnClick", function()
				local db = ns.GetDB()
				for _, key in ipairs(keys) do db[key] = ns.DEFAULTS[key] end
				Changed()
				kit.Refresh()
			end)
			function row:Refresh()
				local own = OwnKinds(keys)
				if #own == 0 then
					status:SetText(L["Follows Visions Style"])
					status:SetTextColor(0.6, 0.6, 0.6)
					back:Hide()
				else
					status:SetText(L["Its own:"] .. " " .. table.concat(own, ", "))
					status:SetTextColor(1, 0.82, 0)
					back:Show()
				end
			end
			visionRows[#visionRows + 1] = row
		end
	end

	-- (Reset page: its own settings, and the Visions listed back on it, as the
	-- profile has them.)
	kit.OnReset(content, function()
		local db, base = ns.GetDB(), ns.ResetBase()
		for _, key in ipairs(OWN_KEYS) do db[key] = base[key] end
		for _, keys in ipairs(lists) do
			for _, key in ipairs(keys) do db[key] = base[key] end
		end
		Changed()
	end)

	local shown = kit.PageShown(kit.Refresh, content)
	canvas:SetScript("OnShow", function()
		for _, row in ipairs(visionRows) do row:Refresh() end
		shown()
	end)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Visions Style", L["Visions Style"])
end
