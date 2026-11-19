-- /cine debug zonecard: one run checking that a zone change shows one zone
-- title, not two (2026-11-19: at the Lion's Pride Inn DaylightUI's zone title
-- and a big cream one showed at once). Changes no settings. For 90 seconds,
-- at every zone change (ZONE_CHANGED, _INDOORS, _NEW_AREA) it logs
-- ("zonecardtest") the zone and subzone, whether our Zone and Subzone cards
-- are on, what each Addon Conflicts row for the Zone card says (the addon's
-- own on or off, the pick), then looks 0.3, 1, 2, 4, 6 and 9 s after at what
-- draws: the game's zone lines (alpha, shown, text), DaylightUI's zone title,
-- and our card (the one playing, its text drawn). A screenshot a second
-- after each change. A verdict per change: ONE (one of them drew), BOTH
-- (two drew at once, and which), or NONE. Typed again while running: stops.
-- Dev copy only (CinematicDev.toc).
local _, ns = ...

local LENGTH = 90
local LOOKS = { 0.3, 1, 2, 4, 6, 9 } -- (to 9 s: a card waiting for another title shows after it)
local SHOT_AT = 1
local GAME = { "ZoneTextString", "SubZoneTextString", "PVPInfoTextString", "PVPArenaTextString" }
local EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }

local run
local watcher = CreateFrame("Frame")
local function Log(text) ns.Log("zonecardtest", text) end
local function Shot() Screenshot() end
local function Plain(value) return not (issecretvalue and issecretvalue(value)) end
local function Num(value)
	if type(value) ~= "number" then return tostring(value) end
	return Plain(value) and ("%.2f"):format(value) or "secret"
end

-- Its alpha on screen: a font string has no GetEffectiveAlpha on WoW Forever,
-- so its own alpha times its frame's.
local function OnScreen(text)
	if text.GetEffectiveAlpha then return text:GetEffectiveAlpha() end
	local own, parent = text:GetAlpha(), text:GetParent()
	local above = parent and parent.GetEffectiveAlpha and parent:GetEffectiveAlpha() or 1
	if type(own) ~= "number" or type(above) ~= "number" or not Plain(own) or not Plain(above) then return nil end
	return own * above
end

-- A font string's text drawn: shown, some alpha on screen, and words.
local function Drawn(text)
	if type(text) ~= "table" or not text.IsVisible or not ns.Flag(text:IsVisible()) then return nil end
	local alpha = OnScreen(text)
	local words = text.GetText and text:GetText()
	if type(alpha) ~= "number" or not Plain(alpha) or alpha <= 0.05 then return nil end
	if type(words) ~= "string" or not Plain(words) or words == "" then return nil end
	return words, alpha
end

-- The first drawn text in a frame, a few levels down.
local function DrawnIn(frame, depth)
	if type(frame) ~= "table" or not frame.GetRegions then return nil end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" then
			local words, alpha = Drawn(region)
			if words then return words, alpha end
		end
	end
	if (depth or 0) < 3 then
		for _, child in ipairs({ frame:GetChildren() }) do
			local words, alpha = DrawnIn(child, (depth or 0) + 1)
			if words then return words, alpha end
		end
	end
	return nil
end

local function ConflictLines()
	local out = {}
	for _, row in ipairs(ns.CONFLICTS or {}) do
		if row.key == "card:zone" then
			local pick, picked = ns.ConflictPick(row)
			out[#out + 1] = ("%s's own %s, pick %s%s"):format(tostring(row.addon),
				ns.ConflictTheirsOn(row) and "on" or "off", pick, picked and "" or " (not picked)")
		end
	end
	return #out > 0 and table.concat(out, "; ") or "no Addon Conflicts row for it"
end

-- What draws now: { game = text, addon = text, ours = text } and a line.
local function Look()
	local seen, parts = {}, {}
	for _, name in ipairs(GAME) do
		local line = _G[name]
		if line then
			local words, alpha = Drawn(line)
			parts[#parts + 1] = ("%s alpha %s%s"):format(name, Num(line:GetAlpha()),
				words and (" DRAWN \"%s\" at %s"):format(words, Num(alpha)) or "")
			if words and not seen.game then seen.game = words end
		end
	end
	local title = _G.DaylightUIZoneTitle
	if title then
		local words = DrawnIn(title)
		seen.addon = words
		parts[#parts + 1] = ("DaylightUIZoneTitle %s%s"):format(ns.Flag(title:IsShown()) and "shown" or "hidden",
			words and (" DRAWN \"%s\""):format(words) or "")
	end
	local card = ns.Cards and ns.Cards.Current and ns.Cards.Current()
	local words = DrawnIn(_G.CinematicCard)
	seen.ours = words
	parts[#parts + 1] = ("our card %s%s"):format(card and tostring(card.id) .. " \"" .. tostring(card.name) .. "\"" or "none",
		words and (" DRAWN \"%s\""):format(words) or "")
	return seen, table.concat(parts, ", ")
end

local function Verdict(change)
	local who = {}
	for _, key in ipairs({ "game", "addon", "ours" }) do
		if change.drew[key] then who[#who + 1] = key == "game" and "the game's" or key == "addon" and "DaylightUI's" or "ours" end
	end
	local what = #who >= 2 and "BOTH" or #who == 1 and "ONE" or "NONE"
	return ("%s at \"%s\": %s%s"):format(what, change.place, what == "NONE" and "nothing drew" or table.concat(who, " + "),
		change.together and "" or (#who >= 2 and " (not at the same moment)" or ""))
end

local function OnZone(event)
	local zone, sub = GetZoneText() or "", GetSubZoneText() or ""
	local change = { place = sub ~= "" and sub or zone, drew = {}, at = GetTime() }
	run.changes[#run.changes + 1] = change
	local n = #run.changes
	Log(("change %d %s: zone \"%s\", subzone \"%s\", Zone card %s, Subzone card %s; %s"):format(n, event, zone, sub,
		ns.CardOn("zone") and "on" or "off", ns.CardOn("subzone") and "on" or "off", ConflictLines()))
	for _, after in ipairs(LOOKS) do
		C_Timer.After(after, function()
			if not run then return end
			local ok, seen, line = pcall(Look)
			if not ok then
				Log(("change %d +%.1fs: error: %s"):format(n, after, tostring(seen)))
				return
			end
			local count = 0
			for key, words in pairs(seen) do
				if words then change.drew[key] = true count = count + 1 end
			end
			if count >= 2 then change.together = true end
			Log(("change %d +%.1fs: %s"):format(n, after, line))
		end)
	end
	C_Timer.After(SHOT_AT, function()
		if run then pcall(Shot) Log(("change %d screenshot at %s"):format(n, date("%H:%M:%S"))) end
	end)
end

local function Finish(stopped)
	if not run then return end
	watcher:UnregisterAllEvents()
	watcher:SetScript("OnUpdate", nil)
	local both = 0
	for i, change in ipairs(run.changes) do
		local verdict = Verdict(change)
		if verdict:find("^BOTH") then both = both + 1 end
		Log(("verdict %d: %s"):format(i, verdict))
	end
	local summary = ("%d zone changes, %d with two titles"):format(#run.changes, both)
	Log("summary: " .. summary)
	ns.Print(("Zone card test %s: %s"):format(stopped and "stopped" or "done", summary))
	ns.PadTestBox(stopped and "Test stopped." or "Test done.", "/reload, then say: check log", 1, 0.82, 0)
	C_Timer.After(20, function() if not run then ns.PadTestBoxHide() end end)
	run = nil
end

function ns.ZoneCardTest()
	if run then return Finish(true) end
	run = { changes = {}, started = GetTime() }
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
	Log(("start: DaylightUI_QoL loaded %s, Card Vision %s, Zone card %s, Subzone card %s; %s"):format(
		tostring(ns.Flag(isLoaded("DaylightUI_QoL"))), ns.Setting("cards") and "on" or "off",
		ns.CardOn("zone") and "on" or "off", ns.CardOn("subzone") and "on" or "off", ConflictLines()))
	local ok, _, line = pcall(Look)
	Log("start look: " .. tostring(ok and line or ("error: " .. tostring(_))))
	for _, event in ipairs(EVENTS) do watcher:RegisterEvent(event) end
	watcher:SetScript("OnEvent", function(_, event)
		local ok, err = pcall(OnZone, event)
		if not ok then Log("error: " .. tostring(err)) end
	end)
	watcher:SetScript("OnUpdate", function()
		local left = LENGTH - (GetTime() - run.started)
		if left <= 0 then return Finish(false) end
		ns.PadTestBox("Walk into a subzone (an inn) and back out, 2 or 3 times. Watch the zone names: one or two?",
			("RECORDING: %d sec left, %d zone changes"):format(math.ceil(left), #run.changes), 0.2, 1, 0.2)
	end)
	ns.Print("Zone card test: 90 seconds, follow the box (type it again to stop)")
end
