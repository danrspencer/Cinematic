-- /cine debug templates: step 0 of the Preview Match plan
-- (Tools/preview-match-plan.md). Which of the game's own frame templates
-- could our Style previews be built from, on this client? Dev copy only.
--
-- 1. Lists the game's templates whose names match the frames we preview
--    (cast bars, unit frames, nameplates, action buttons, raid, tooltip,
--    loot roll...), each with its type, size and what it inherits
--    (C_XMLUtil; the whole list where the client gives one, else a fixed
--    list of names to ask about).
-- 2. Tries to make each frame one, out of a fight, under a hidden holder,
--    never a secure one or one that joins Edit Mode (those spread taint).
--    Per template: made or not, any error its own setup code threw (caught
--    here, not shown), the parts it came with (Icon, Text, Spark...: what
--    our style code would hook) and the scripts it runs. Each one made is
--    then quieted (events off, scripts off, hidden).
-- 3. The game's live frames we stand in for (TargetFrameSpellBar...): their
--    type, size and parts, to compare with the templates.
-- Also watches ADDON_ACTION_BLOCKED during the run.
-- Saved into CinematicDB.templateProbe[client]. /reload after it (the made
-- frames go away), then "check log".
local _, ns = ...

-- Names worth a look (lowercase parts of a template's name).
local MATCH = {
	"castingbar", "castbar", "spellbar", "actionbutton", "tooltip", "compactunit", "compactraid", "compactparty",
	"nameplate", "grouploot", "lootroll", "bonusroll", "targetframe", "playerframe", "focusframe", "partymember",
	"partyframe", "unitframe", "healthbar", "manabar", "powerbar", "statusbar", "buffbutton", "aurabutton",
	"debuffbutton", "chatbubble", "personalresource", "classnameplate", "questobjectiveitem", "extraaction",
	"bossframe", "bosstarget", "arenaenemy", "totemframe", "mirrortimer",
}
-- Asked by name where the client can't list its templates.
local NAMES = {
	"CastingBarFrameTemplate", "SmallCastingBarFrameTemplate", "PlayerCastingBarFrameTemplate",
	"TargetSpellBarTemplate", "FocusSpellBarTemplate", "NamePlateCastingBarTemplate", "ArenaCastingBarFrameTemplate",
	"BossTargetFrameTemplate", "ActionButtonTemplate", "ActionBarButtonTemplate", "GameTooltipTemplate",
	"SharedTooltipTemplate", "CompactUnitFrameTemplate", "CompactPartyFrameTemplate", "CompactRaidFrameTemplate",
	"NamePlateUnitFrameTemplate", "NamePlateFullBorderTemplate", "GroupLootFrameTemplate", "LootRollTemplate",
	"BonusRollFrameTemplate", "TargetFrameTemplate", "TargetofTargetFrameTemplate", "PartyMemberFrameTemplate",
	"TextStatusBar", "UnitFrameHealthBarTemplate", "UnitFrameManaBarTemplate", "BuffButtonTemplate",
	"DebuffButtonTemplate", "AuraButtonTemplate", "QuestObjectiveItemButtonTemplate", "MirrorTimerTemplate",
	"ChatBubbleTemplate",
}
-- Never made: secure code, or joins a game system (Edit Mode) on setup.
-- Nor bases only meant to be built on (ClassPowerBar, ClassNameplateBar, pet
-- battle frames: the game warns of their missing OnLoad/OnEvent when made
-- alone, Forever 2026-11-19).
local SKIP = { "secure", "editmodesystem", "editmode", "classpowerbar", "classnameplatebar", "petbattle" }
-- Frame types CreateFrame can make (others are textures, fonts, animations).
local FRAME_TYPES = {
	Frame = true, Button = true, CheckButton = true, StatusBar = true, GameTooltip = true, Cooldown = true,
	ScrollFrame = true, EditBox = true, Slider = true, Model = true, PlayerModel = true, ModelScene = true,
}
-- The game's live frames we stand in for.
local LIVE = {
	"CastingBarFrame", "PlayerCastingBarFrame", "TargetFrameSpellBar", "FocusFrameSpellBar", "PetCastingBarFrame",
	"TargetFrame", "PlayerFrame", "FocusFrame", "TargetFrameToT", "PartyMemberFrame1", "Boss1TargetFrame",
	"GameTooltip", "GroupLootFrame1", "ActionButton1", "MultiBarBottomLeftButton1", "CompactPartyFrameMember1",
	"CompactRaidFrame1", "PersonalResourceDisplayFrame", "MirrorTimer1", "ExtraActionButton1",
}
-- (120 left 22 unmade on Forever, 2026-11-19.)
local MAX_MADE, MAX_PARTS = 250, 30

local function Client()
	local interface = tonumber((select(4, GetBuildInfo()))) or 0
	return interface >= 100000 and "retail" or (interface >= 16000 and interface < 20000) and "forever"
		or (interface >= 10000 and interface < 16000) and "era" or ("game" .. interface)
end

local function Has(list, lower)
	for _, part in ipairs(list) do
		if lower:find(part, 1, true) then return true end
	end
	return false
end

-- A region's look in a few words: its type, and its atlas, file or font.
local function Look(region)
	local okType, kind = pcall(region.GetObjectType, region)
	kind = okType and kind or "?"
	local extra
	if kind == "Texture" then
		local okA, atlas = pcall(region.GetAtlas, region)
		if okA and atlas and atlas ~= "" then
			extra = "atlas " .. tostring(atlas)
		else
			local okT, file = pcall(region.GetTexture, region)
			if okT and file then extra = tostring(file) end
		end
	elseif kind == "FontString" then
		local okF, font, size = pcall(region.GetFont, region)
		if okF and font then extra = ("%s %s"):format(tostring(font):match("[^\\/]+$") or tostring(font), tostring(size)) end
	end
	local okSize, w, h = pcall(region.GetSize, region)
	local size = (okSize and tonumber(w) and tonumber(h)) and ("%.0fx%.0f"):format(w, h) or ""
	return kind .. (extra and ("(" .. extra .. ")") or "") .. (size ~= "" and (" " .. size) or "")
end

-- The parts a frame keeps by name (bar.Icon, bar.Text...), sorted.
local function Parts(frame)
	local list = {}
	for key, value in pairs(frame) do
		if type(key) == "string" and type(value) == "table" and key ~= "__index" then
			local okIs, isRegion = pcall(function() return value.GetObjectType ~= nil and value.GetParent ~= nil end)
			if okIs and isRegion then list[#list + 1] = key .. ":" .. Look(value) end
		end
	end
	table.sort(list)
	if #list > MAX_PARTS then
		local more = #list - MAX_PARTS
		for i = #list, MAX_PARTS + 1, -1 do list[i] = nil end
		list[#list + 1] = ("+%d more"):format(more)
	end
	return #list > 0 and table.concat(list, ", ") or "none"
end

local function Scripts(frame)
	local list = {}
	for _, name in ipairs({ "OnLoad", "OnEvent", "OnUpdate", "OnShow", "OnHide" }) do
		local ok, has = pcall(frame.HasScript, frame, name)
		if ok and has then
			local okGet, fn = pcall(frame.GetScript, frame, name)
			if okGet and fn then list[#list + 1] = name end
		end
	end
	return #list > 0 and table.concat(list, " ") or "none"
end

local function Info(GetTemplateInfo, name)
	if not GetTemplateInfo then return nil end
	local ok, info = pcall(GetTemplateInfo, name)
	return ok and type(info) == "table" and info or nil
end

-- Every template the client lists, or the fixed names.
local function Candidates(xml)
	local found, seen = {}, {}
	local GetTemplates = xml and xml.GetTemplates
	local listed = false
	if GetTemplates then
		local ok, all = pcall(GetTemplates)
		if ok and type(all) == "table" then
			listed = true
			for _, entry in ipairs(all) do
				local name = type(entry) == "table" and entry.name or entry
				if type(name) == "string" and not seen[name] and Has(MATCH, name:lower()) then
					seen[name] = true
					found[#found + 1] = name
				end
			end
		end
	end
	for _, name in ipairs(NAMES) do
		if not seen[name] then
			seen[name] = true
			found[#found + 1] = name
		end
	end
	table.sort(found)
	return found, listed
end

local holder -- (hidden, off screen; the made frames sit in it)

function ns.TemplateProbe()
	if InCombatLockdown() then
		ns.Print("/cine debug templates: not in a fight. Try again after it.")
		return
	end
	local client = Client()
	local lines = {}
	local function Say(text) lines[#lines + 1] = text end
	local version, build, _, interface = GetBuildInfo()
	Say(("client %s, version %s build %s interface %s"):format(client, tostring(version), tostring(build), tostring(interface)))

	local xml = _G.C_XMLUtil
	local GetTemplateInfo = xml and xml.GetTemplateInfo
	local names, listed = Candidates(xml)
	Say(("C_XMLUtil.GetTemplates: %s; GetTemplateInfo: %s; %d templates to look at"):format(
		listed and "listed" or "none (fixed names only)", GetTemplateInfo and "yes" or "no", #names))

	if not holder then
		holder = CreateFrame("Frame", nil, UIParent)
		holder:SetSize(1, 1)
		holder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
		holder:Hide()
	end

	-- Blocked actions during the run (a template's setup touching secure code).
	local blocked = {}
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
	watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	watcher:SetScript("OnEvent", function(_, event, who, what)
		blocked[#blocked + 1] = ("%s %s %s"):format(event, tostring(who), tostring(what))
	end)

	-- Errors a template's own setup throws go here, not to the error window.
	local caught
	local previous = geterrorhandler()
	seterrorhandler(function(message) caught = caught or tostring(message) end)

	local made, failed, skipped, unknown = 0, 0, 0, 0
	Say("-- templates: name | type size | inherits | result | scripts | parts")
	for _, name in ipairs(names) do
		local info = Info(GetTemplateInfo, name)
		local kind = info and info.type
		local inherits = info and tostring(info.inherits or "") or ""
		local head = ("%s | %s %sx%s | %s"):format(name, tostring(kind or "?"),
			tostring(info and info.width or "?"), tostring(info and info.height or "?"),
			inherits ~= "" and inherits or "-")
		local lower = (name .. " " .. inherits):lower()
		if GetTemplateInfo and not info then
			unknown = unknown + 1
			Say(head .. " | not on this client")
		elseif Has(SKIP, lower) then
			skipped = skipped + 1
			Say(head .. " | skipped (secure or Edit Mode)")
		elseif kind and not FRAME_TYPES[kind] then
			Say(head .. " | not a frame (" .. tostring(kind) .. "), not made")
		elseif made >= MAX_MADE then
			Say(head .. " | not made (over " .. MAX_MADE .. " this run)")
		else
			caught = nil
			-- (Named: action buttons and compact unit frames need a name for
			-- their own setup, Forever 2026-11-19.)
			local ok, frame = pcall(CreateFrame, kind or "Frame", "CinematicTemplateProbe" .. (made + failed + 1), holder, name)
			if ok and frame then
				made = made + 1
				local scripts = Scripts(frame)
				local parts = Parts(frame)
				pcall(frame.UnregisterAllEvents, frame)
				for _, script in ipairs({ "OnEvent", "OnUpdate", "OnShow", "OnHide" }) do
					pcall(frame.SetScript, frame, script, nil)
				end
				pcall(frame.Hide, frame)
				Say(("%s | made%s | %s | %s"):format(head, caught and (", its setup errored: " .. caught) or "",
					scripts, parts))
			else
				failed = failed + 1
				Say(("%s | FAILED: %s"):format(head, tostring(frame or caught)))
			end
		end
	end

	seterrorhandler(previous)
	watcher:UnregisterAllEvents()

	Say("-- live game frames: name | parts")
	for _, name in ipairs(LIVE) do
		local frame = _G[name]
		if type(frame) == "table" and frame.GetObjectType then
			local okShown, shown = pcall(frame.IsShown, frame)
			Say(("%s | %s%s | %s"):format(name, Look(frame), (okShown and shown) and " shown" or " hidden", Parts(frame)))
		else
			Say(name .. " | none on this client")
		end
	end

	Say(("blocked during the run: %s"):format(#blocked > 0 and table.concat(blocked, "; ") or "none"))
	Say(("made %d, failed %d, skipped %d, not on this client %d"):format(made, failed, skipped, unknown))

	CinematicDB.templateProbe = CinematicDB.templateProbe or {}
	CinematicDB.templateProbe[client] = lines
	ns.Log("debug", ("templates probe (%s): made %d, failed %d, skipped %d, blocked %d; %d lines in CinematicDB.templateProbe")
		:format(client, made, failed, skipped, #blocked, #lines))
	ns.Print(("templates probe done on %s: made %d, failed %d, skipped %d, blocked %d. /reload now, then tell Claude 'check log'.")
		:format(client, made, failed, skipped, #blocked))
end
