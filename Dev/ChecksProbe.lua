-- /cine debug checks: step 1 of Tools/pcall-plan.md. Lists, on this client,
-- which checks exist that could replace a pcall (secret values, forbidden or
-- protected frames, events, templates), and whether each one agrees with
-- what really happens. Read only, out of a fight. Saved in
-- CinematicDB.checksProbe[client] (read after /reload) and shown to copy.
local _, ns = ...

local EVENTS = { -- (every event the addon registers by name, plus made-up ones)
	"ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "ADDON_LOADED", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
	"CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_YELL", "COMBAT_LOG_EVENT_UNFILTERED",
	"COMBAT_LOG_MESSAGE", "CURSOR_CHANGED", "CVAR_UPDATE", "DISPLAY_SIZE_CHANGED", "EDIT_MODE_LAYOUTS_UPDATED",
	"GAME_PAD_BUTTON_DOWN", "GLOBAL_MOUSE_DOWN", "GLOBAL_MOUSE_UP", "GOSSIP_SHOW", "GROUP_ROSTER_UPDATE",
	"ITEM_LOCK_CHANGED", "LOADING_SCREEN_DISABLED", "LOOT_CLOSED", "LOOT_OPENED", "MINIMAP_PING",
	"MIRROR_TIMER_START", "MODIFIER_STATE_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
	"PLAYER_ALIVE", "PLAYER_DEAD", "PLAYER_ENTERING_WORLD", "PLAYER_ENTER_COMBAT", "PLAYER_EQUIPMENT_CHANGED",
	"PLAYER_FOCUS_CHANGED", "PLAYER_LEAVE_COMBAT", "PLAYER_LEVEL_UP", "PLAYER_LOGIN", "PLAYER_LOGOUT",
	"PLAYER_MONEY", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"PLAYER_ROLES_ASSIGNED", "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
	"PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_TARGET_CHANGED", "PLAYER_UNGHOST",
	"QUEST_GREETING", "QUEST_LOG_UPDATE", "RAID_TARGET_UPDATE", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
	"SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
	"TALKINGHEAD_REQUESTED", "UI_ERROR_MESSAGE", "UI_SCALE_CHANGED", "UNIT_AURA", "UNIT_COMBAT",
	"UNIT_DISPLAYPOWER", "UNIT_FACTION", "UNIT_HEALTH", "UNIT_INVENTORY_CHANGED", "UNIT_MAXHEALTH",
	"UNIT_MAXPOWER", "UNIT_MODEL_CHANGED", "UNIT_NAME_UPDATE", "UNIT_PET", "UNIT_POWER_FREQUENT",
	"UNIT_POWER_UPDATE", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_TARGET", "UNIT_THREAT_SITUATION_UPDATE",
	"UPDATE_BINDINGS", "UPDATE_MOUSEOVER_UNIT", "UPDATE_SHAPESHIFT_FORM", "WEAPON_ENCHANT_CHANGED",
	"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "LUA_WARNING", "MACRO_ACTION_BLOCKED",
	"MACRO_ACTION_FORBIDDEN",
	"CINEMATIC_NOT_AN_EVENT", "UNIT_NOT_AN_EVENT_EITHER",
}

local TEMPLATES = { -- (every template the addon names, plus a made-up one)
	{ "Frame", "BackdropTemplate" }, { "EditBox", "InputBoxTemplate" }, { "Button", "UIPanelButtonTemplate" },
	{ "ScrollFrame", "UIPanelScrollFrameTemplate" }, { "CheckButton", "UICheckButtonTemplate" },
	{ "Button", "SecureActionButtonTemplate" }, { "EditBox", "SearchBoxTemplate" },
	{ "Cooldown", "CooldownFrameTemplate" }, { "Frame", "NineSlicePanelTemplate" },
	{ "ScrollFrame", "ScrollFrameTemplate" }, { "Slider", "OptionsSliderTemplate" },
	{ "Frame", "ButtonFrameTemplate" }, { "CheckButton", "UIRadioButtonTemplate" },
	{ "Frame", "SecureHandlerStateTemplate" }, { "GameTooltip", "GameTooltipTemplate" },
	{ "Frame", "DialogBorderTemplate" }, { "Frame", "CinematicNotATemplate" },
}

-- Words that mark a check worth knowing about, in global and method names.
local WORDS = { "secret", "access", "forbidden", "protected", "restrict", "taint", "secure" }

local function Client()
	local interface = tonumber((select(4, GetBuildInfo()))) or 0
	return interface >= 100000 and "retail" or (interface >= 16000 and interface < 20000) and "forever"
		or (interface >= 10000 and interface < 16000) and "era" or ("game" .. interface)
end

local function Matches(name)
	if type(name) ~= "string" then return false end
	local lower = name:lower()
	for _, word in ipairs(WORDS) do
		if lower:find(word, 1, true) then return true end
	end
	return false
end

local function Sorted(set)
	local list = {}
	for name in pairs(set) do list[#list + 1] = name end
	table.sort(list)
	return list
end

-- Method names on a widget's shared method table.
local function Methods(object)
	local found = {}
	local meta = getmetatable(object)
	local index = meta and meta.__index
	if type(index) == "table" then
		for name, value in pairs(index) do
			if type(value) == "function" and Matches(name) then found[name] = true end
		end
	end
	return Sorted(found)
end

function ns.ChecksProbe()
	if InCombatLockdown() then
		ns.Print("/cine debug checks: out of a fight, please (it makes test frames).")
		return
	end
	local lines = {}
	local function Say(text) lines[#lines + 1] = text end
	local _, build, _, interface = GetBuildInfo()
	Say(("checks probe: %s, game %s (%s), %s"):format(Client(), tostring(interface), tostring(build), date("%Y-%m-%d %H:%M")))

	-- 1. Global functions and tables named for secrets, access, protection.
	local globals, tables = {}, {}
	for name, value in pairs(_G) do
		if Matches(name) then
			if type(value) == "function" then globals[name] = true
			elseif type(value) == "table" and name:match("^C_") then tables[name] = true end
		end
	end
	Say("global functions: " .. table.concat(Sorted(globals), ", "))
	for _, name in ipairs(Sorted(tables)) do
		local fns = {}
		for key, value in pairs(_G[name]) do
			if type(value) == "function" then fns[key] = true end
		end
		Say(("%s: %s"):format(name, table.concat(Sorted(fns), ", ")))
	end
	-- (C_ tables whose functions are named for it, under any table name.)
	local more = {}
	for name, value in pairs(_G) do
		if type(name) == "string" and name:match("^C_") and type(value) == "table" and not tables[name] then
			for key, fn in pairs(value) do
				if type(fn) == "function" and Matches(key) then more[name .. "." .. key] = true end
			end
		end
	end
	Say("C_ functions: " .. table.concat(Sorted(more), ", "))

	-- 2. Methods on each kind of region.
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:Hide()
	local kinds = {
		Frame = holder, Button = CreateFrame("Button", nil, holder), StatusBar = CreateFrame("StatusBar", nil, holder),
		FontString = holder:CreateFontString(nil, "OVERLAY"), Texture = holder:CreateTexture(nil, "ARTWORK"),
		Cooldown = CreateFrame("Cooldown", nil, holder),
	}
	for _, kind in ipairs({ "Frame", "Button", "StatusBar", "Cooldown", "FontString", "Texture" }) do
		Say(("%s methods: %s"):format(kind, table.concat(Methods(kinds[kind]), ", ")))
	end
	-- (A game nameplate if one is up: does it say forbidden, and how.)
	local plate = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
	Say(("nameplates readable now: %s"):format(type(plate) == "table" and tostring(#plate) or "?"))

	-- 3. Events: does C_EventUtils.IsEventValid agree with RegisterEvent?
	local events = _G.C_EventUtils
	local IsEventValid = events and events.IsEventValid
	Say("C_EventUtils.IsEventValid: " .. (IsEventValid and "yes" or "no"))
	local scratch = CreateFrame("Frame")
	local missing, disagree = {}, {}
	for _, event in ipairs(EVENTS) do
		local registers = pcall(scratch.RegisterEvent, scratch, event) -- (the truth, for this probe only)
		scratch:UnregisterAllEvents()
		if not registers then missing[#missing + 1] = event end
		if IsEventValid then
			local valid = IsEventValid(event) and true or false
			if valid ~= registers then
				disagree[#disagree + 1] = ("%s (valid %s, registers %s)"):format(event, tostring(valid), tostring(registers))
			end
		end
	end
	Say("events that don't register: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
	Say("IsEventValid disagrees: " .. (#disagree > 0 and table.concat(disagree, ", ") or "never"))

	-- 4. Templates: does C_XMLUtil.GetTemplateInfo agree with CreateFrame?
	local xml = _G.C_XMLUtil
	local GetTemplateInfo = xml and xml.GetTemplateInfo
	Say("C_XMLUtil.GetTemplateInfo: " .. (GetTemplateInfo and "yes" or "no"))
	local noTemplate, tDisagree = {}, {}
	for _, pair in ipairs(TEMPLATES) do
		local kind, template = pair[1], pair[2]
		local made, frame = pcall(CreateFrame, kind, nil, holder, template) -- (the truth, for this probe only)
		if made and frame and frame.Hide then frame:Hide() end
		if not made then noTemplate[#noTemplate + 1] = template end
		if GetTemplateInfo then
			local ok, info = pcall(GetTemplateInfo, template)
			local known = ok and info ~= nil
			if known ~= made then
				tDisagree[#tDisagree + 1] = ("%s (info %s, makes %s)"):format(template, tostring(known), tostring(made))
			end
		end
	end
	Say("templates that don't make: " .. (#noTemplate > 0 and table.concat(noTemplate, ", ") or "none"))
	Say("GetTemplateInfo disagrees: " .. (#tDisagree > 0 and table.concat(tDisagree, ", ") or "never"))

	-- 5. The secret checks on plain values (out of a fight nothing's secret).
	for _, name in ipairs({ "issecretvalue", "issecrettable", "canaccessvalue", "canaccesstable",
		"canaccessallvalues", "hasanysecretvalues", "scrubsecretvalues" }) do
		local fn = _G[name]
		if type(fn) == "function" then
			local ok, a = pcall(fn, 5)
			local okT, b = pcall(fn, {})
			Say(("%s(5) = %s, ({}) = %s"):format(name, ok and tostring(a) or "error", okT and tostring(b) or "error"))
		else
			Say(name .. ": none")
		end
	end

	CinematicDB.checksProbe = CinematicDB.checksProbe or {}
	CinematicDB.checksProbe[Client()] = lines
	ns.Print(("checks probe: %d lines saved for %s. /reload to write them, then tell Claude 'check log'."):format(#lines, Client()))
	if ns.ShowText then ns.ShowText("/cine debug checks: press Ctrl+C to copy", table.concat(lines, "\n")) end
end
