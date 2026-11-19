-- /cine debug numbers: which shortened number styles the game can give our
-- combat text (2026-11-19, the user's ask: 22,245 shown as 22.2K, 22K, 22,
-- or scaled down by 10, 100 or 1,000). Hit amounts are secret in fights: we
-- can't divide them, only hand them to the game's AbbreviateNumbers, which
-- takes secret ones. Whether it takes rules of our own (a divisor, no
-- letter) is what this finds out, on each client.
--
-- One run: (1) every style on plain numbers (22245, 887, 46), results logged
-- as they are, each with its verdict against what it should give; (2) then
-- it waits for your next hit on a target (hit a training dummy): every style
-- on that hit's amount (secret in a fight), drawn in a panel mid-screen, and
-- a screenshot; secret results can't be read back, so the screenshot is the
-- answer. Everything goes to /cine log ("numbers").
local _, ns = ...

local WAIT = 180 -- seconds to wait for a hit (60 ran out before a first test's fight, 2026-11-19)

-- The rules: the game's own data shape (FormattingUtil's
-- NUMBER_ABBREVIATION_DATA: breakpoint, abbreviation, significandDivisor,
-- fractionDivisor, abbreviationIsGlobal).
local function Rule(breakpoint, abbreviation, divisor, fraction)
	return { { breakpoint = breakpoint, abbreviation = abbreviation, significandDivisor = divisor,
		fractionDivisor = fraction or 1, abbreviationIsGlobal = false } }
end
-- label, rules (nil: the game's own), expected for 22245 / 887 / 46 (our
-- guess at its rounding: a FAIL may only be rounding, read the result)
local STYLES = {
	{ "game's own", nil, { "22.2K", "887", "46" }, "AbbreviateNumbers" },
	{ "game's large", nil, { "22.2K", "887", "46" }, "AbbreviateLargeNumbers" },
	{ "22.2K", Rule(1000, "K", 100, 10), { "22.2K", "887", "46" } },
	{ "22K", Rule(1000, "K", 1000, 1), { "22K", "887", "46" } },
	{ "22", Rule(1000, "", 1000, 1), { "22", "887", "46" } },
	{ "/10", Rule(1, "", 10, 1), { "2224", "88", "4" } },
	{ "/100", Rule(1, "", 100, 1), { "222", "8", "0" } },
	{ "/1000", Rule(1, "", 1000, 1), { "22", "0", "0" } },
}
local PLAIN = { 22245, 887, 46 }

local function Secret(value)
	return issecretvalue and issecretvalue(value) and true or false
end

-- The ways a rule might be passed: found on plain numbers, then used on
-- the secret one. Each gives (ok, result).
local FORMS = {
	{ "data", function(value, rules) return AbbreviateNumbers(value, rules) end },
	{ "config", function(value, rules) return AbbreviateNumbers(value, { config = _G.CreateAbbreviateConfig(rules) }) end },
	{ "config bare", function(value, rules) return AbbreviateNumbers(value, _G.CreateAbbreviateConfig(rules)) end },
}

local function Run(style, value, form)
	local name, rules, _, own = style[1], style[2], style[3], style[4]
	if own then
		local fn = _G[own]
		if type(fn) ~= "function" then return false, own .. " missing" end
		return pcall(fn, value)
	end
	if type(AbbreviateNumbers) ~= "function" then return false, "AbbreviateNumbers missing" end
	-- (Not "pcall(...), name": that keeps pcall's first value only.)
	if not name then return false, "no style" end
	return pcall(form[2], value, rules)
end

local function Show(result)
	if result == nil then return "nil" end
	if Secret(result) then return "SECRET" end
	return '"' .. tostring(result) .. '"'
end

local panel, running

local function Panel()
	if panel then return panel end
	panel = CreateFrame("Frame", nil, UIParent)
	panel:SetSize(420, 40 + #STYLES * 30)
	panel:SetPoint("CENTER", 0, 120)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	local back = panel:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.8)
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.title:SetPoint("TOP", 0, -10)
	panel.rows = {}
	for i = 1, #STYLES do
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("TOPLEFT", 16, -14 - i * 30)
		local result = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		result:SetPoint("LEFT", label, "LEFT", 170, 0)
		panel.rows[i] = { label = label, result = result }
	end
	return panel
end

-- The secret hit: every style drawn, then a screenshot.
local function OnSecret(amount)
	local log = function(text) ns.Log("numbers", text) end
	log(("hit amount: secret=%s"):format(tostring(Secret(amount))))
	local okMath, quotient = pcall(function() return amount / 1000 end)
	log(("our own math on it (amount / 1000): %s"):format(okMath and ("works, " .. Show(quotient)) or "refused"))
	local p = Panel()
	p.title:SetText("Your hit, in each style (screenshot taken)")
	for i, style in ipairs(STYLES) do
		local row = p.rows[i]
		row.label:SetText(style[1])
		local shown
		for _, form in ipairs(style[4] and { FORMS[1] } or FORMS) do
			local ok, result = Run(style, amount, form)
			local formName = style[4] and style[4] or form[1]
			if ok and result ~= nil then
				local drew = pcall(row.result.SetText, row.result, result)
				log(("secret %s via %s: %s, drawn %s"):format(style[1], formName, Show(result), tostring(drew)))
				if drew then shown = true break end
			else
				log(("secret %s via %s: error %s"):format(style[1], formName, tostring(result):match("^[^\n]*")))
			end
		end
		if not shown then row.result:SetText("|cffff5555failed|r") end
	end
	p:Show()
	C_Timer.After(0.5, function() pcall(Screenshot) end)
	C_Timer.After(20, function() if panel then panel:Hide() end end)
	ns.TestPrompt("Done. Now /reload, then tell Claude 'check log'.", 20)
end

local function Stop(why)
	if not running then return end
	running:UnregisterAllEvents()
	running = nil
	ns.Log("numbers", "stopped: " .. why)
end

function ns.NumberStyleTest()
	if running then
		Stop("run again")
		ns.Print("numbers: stopped.")
		return
	end
	local log = function(text) ns.Log("numbers", text) end
	log(("start: client %s, AbbreviateNumbers %s, AbbreviateLargeNumbers %s, CreateAbbreviateConfig %s"):format(
		ns.isRetail and "retail" or "forever", type(AbbreviateNumbers), type(AbbreviateLargeNumbers),
		type(_G.CreateAbbreviateConfig)))
	-- (1) Plain numbers: which form each style works in, and its verdict.
	for _, style in ipairs(STYLES) do
		for _, form in ipairs(style[4] and { FORMS[1] } or FORMS) do
			local got, pass = {}, true
			for n, value in ipairs(PLAIN) do
				local ok, result = Run(style, value, form)
				local text = ok and Show(result) or ("error " .. tostring(result):match("^[^\n]*"))
				got[#got + 1] = text
				if text ~= '"' .. style[3][n] .. '"' then pass = false end
			end
			log(("plain %s via %s: %s -> %s (wanted %s)"):format(style[1], style[4] or form[1], table.concat(got, ", "),
				pass and "PASS" or "FAIL", table.concat(style[3], ", ")))
		end
	end
	-- (2) The next hit on your target, its amount secret in a fight.
	running = CreateFrame("Frame")
	running:RegisterUnitEvent("UNIT_COMBAT", "target")
	running:SetScript("OnEvent", function(_, _, _, action, _, amount)
		if action ~= "WOUND" or amount == nil then return end
		Stop("got a hit")
		local ok, err = pcall(OnSecret, amount)
		if not ok then ns.Log("numbers", "error: " .. tostring(err)) end
	end)
	C_Timer.After(WAIT, function() if running then Stop("no hit in " .. WAIT .. " s") ns.Print("numbers: no hit came.") end end)
	ns.TestPrompt("Plain numbers tested.\nNow hit a training dummy (target it first).\n"
		.. "Waiting up to 3 minutes; don't /reload till the panel shows.", 10)
end
