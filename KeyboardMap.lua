-- Keyboard Map (Quality of life > Keyboard Map): your keyboard on screen, each
-- key showing what it does now: its action's icon, cooldown and count, or the
-- command's short name. Holding Shift, Ctrl or Alt (any mix) shows those keys'
-- bindings; clicking one of them on the map keeps its layer up.
-- Opened with its key (CINEMATIC_KEYMAP: hold to peek, tap to keep it up) or
-- /cine keys. View only: no secure buttons, so it opens, closes and changes in
-- fights too, and clicking a key casts nothing.
-- Based on Keyboard Bars by Ben (Discipline), with his OK: the Norwegian
-- layout and its key tokens, the short command names and the idea are his.
-- Each key is one of five kinds, each with its own color (the Colors rows):
--   action: bound to an action button with something on it (its icon)
--   empty: bound to an action button with nothing on it (the empty slot picture)
--   command: bound to something else (menus, movement, addons' commands)
--   unbound: no binding at all on this layer
--   modifier: Shift, Ctrl, Alt (lit while held or kept)
local ADDON_NAME, ns = ...
local L = ns.L

local DEFAULTS = ns.DEFAULTS
DEFAULTS.kbLayout = "auto"     -- "auto" (the game's language), "us", "uk", "de", "no"
DEFAULTS.kbExtended = false    -- navigation keys, arrows and Print Screen
DEFAULTS.kbNumpad = false      -- the numpad (its tick on the map's top bar)
DEFAULTS.kbMouse = true        -- the mouse buttons and wheel, at the right
DEFAULTS.kbKeySize = 40        -- a key's width and height
DEFAULTS.kbTextScale = 1       -- the names' size
DEFAULTS.kbRound = false       -- round keys and icons
DEFAULTS.kbHideUnbound = false -- keys with nothing bound aren't drawn (their space stays)
DEFAULTS.kbHideEmpty = false   -- nor keys bound to an action button with nothing on it
DEFAULTS.kbHideCommands = false -- nor keys bound to menus, movement and the like
DEFAULTS.kbSplitWords = true   -- a one-word name too wide for its key goes over two lines
DEFAULTS.kbWidth, DEFAULTS.kbHeight = false, false -- the size it was dragged to (false: as Key size makes it)
DEFAULTS.kbX, DEFAULTS.kbY = 0, -120 -- where it sits: its middle, from the screen's

-- The colors to pick from (names translated as the menu opens).
local PRESETS = {
	{ "blue", "Light blue", 0.30, 0.65, 0.85 }, { "cyan", "Cyan", 0.15, 0.85, 1 },
	{ "teal", "Teal", 0.44, 0.71, 0.60 }, { "green", "Green", 0.25, 0.85, 0.50 },
	{ "gold", "Gold", 1, 0.75, 0.20 }, { "orange", "Orange", 1, 0.55, 0.15 },
	{ "red", "Red", 1, 0.30, 0.35 }, { "pink", "Pink", 1, 0.40, 0.65 },
	{ "violet", "Violet", 0.65, 0.40, 1 }, { "white", "White", 0.95, 0.95, 0.95 },
	{ "grey", "Gray", 0.45, 0.45, 0.50 }, { "dark", "Dark", 0.16, 0.20, 0.27 },
	{ "black", "Black", 0, 0, 0 },
}
local PRESET = {}
for _, each in ipairs(PRESETS) do PRESET[each[1]] = each end
-- Modifiers' own choice: each its own color (Shift blue, Ctrl red, Alt amber).
local EACH = { shift = { 0.15, 0.65, 1 }, ctrl = { 0.90, 0.25, 0.30 }, alt = { 1, 0.65, 0.20 } }

-- The kinds' color settings: kb<Name> a preset's id or "custom" (then
-- kb<Name>R/G/B), in the order the page lists them.
local KINDS = {
	{ kind = "action", setting = "kbColorAction", preset = "blue", label = "Action buttons",
		tip = "Keys bound to an action button with a spell, item or macro on it." },
	{ kind = "empty", setting = "kbColorEmpty", preset = "gold", label = "Empty action slots",
		tip = "Keys bound to an action button with nothing on it yet: drag something to that button to use the key." },
	{ kind = "command", setting = "kbColorCommand", preset = "teal", label = "Menus and movement",
		tip = "Keys bound to anything else: moving, targeting, opening windows, other addons' commands." },
	{ kind = "unbound", setting = "kbColorUnbound", preset = "dark", label = "Unbound keys",
		tip = "Keys with nothing bound to them with the modifiers shown (Ctrl+the key, say): free to use." },
	{ kind = "modifier", setting = "kbColorModifier", preset = "each", label = "Modifiers",
		tip = "Shift, Ctrl and Alt: lit while you hold them, or after clicking them on the map." },
}
local KIND = {}
for _, info in ipairs(KINDS) do
	KIND[info.kind] = info
	DEFAULTS[info.setting] = info.preset
	local start = PRESET[info.preset] or { nil, nil, EACH.shift[1], EACH.shift[2], EACH.shift[3] }
	DEFAULTS[info.setting .. "R"], DEFAULTS[info.setting .. "G"], DEFAULTS[info.setting .. "B"] =
		start[3], start[4], start[5]
end

-- A kind's color now (mod: which modifier, for "each").
local function ColorOf(kind, mod)
	local db, info = ns.db, KIND[kind]
	local id = db and db[info.setting] or info.preset
	if id == "custom" then
		return db[info.setting .. "R"] or 1, db[info.setting .. "G"] or 1, db[info.setting .. "B"] or 1
	elseif id == "each" then
		local c = EACH[mod or "shift"]
		return c[1], c[2], c[3]
	end
	local p = PRESET[id] or PRESET[KIND[kind].preset] or PRESET.blue
	return p[3], p[4], p[5]
end

-- Layouts ---------------------------------------------------------------------
-- A key: { label, token (the binding's key name; nil for a modifier), width,
-- modifier }. Rows 1-4 differ by layout; the rest are shared. Tokens of
-- letters past A-Z are lowercase, as the game saves them (Keyboard Bars,
-- tested on Norwegian).
local function Letters(s)
	local t = {}
	for c in s:gmatch(".") do t[#t + 1] = { c, c } end
	return t
end
local function Join(...)
	local out = {}
	for i = 1, select("#", ...) do
		for _, e in ipairs((select(i, ...))) do out[#out + 1] = e end
	end
	return out
end
local DIGITS = Letters("1234567890")
local BACK, TAB, CAPS = { "Back", "BACKSPACE", 2 }, { "Tab", "TAB", 1.5 }, { "Caps", "CAPSLOCK", 1.75 }
local ISO_SHIFT = { "Shift", nil, 1.25, "shift" }
local COMMA_DOT = { { ",", "," }, { ".", "." } }

local LAYOUTS = {
	{ id = "us", text = "US (ANSI)", rows = {
		Join({ { "`", "`" } }, DIGITS, { { "-", "-" }, { "=", "=" }, BACK }),
		Join({ TAB }, Letters("QWERTYUIOP"), { { "[", "[" }, { "]", "]" }, { "\\", "\\", 1.5 } }),
		Join({ CAPS }, Letters("ASDFGHJKL"), { { ";", ";" }, { "'", "'" }, { "Enter", "ENTER", 2.25 } }),
		Join({ { "Shift", nil, 2.25, "shift" } }, Letters("ZXCVBNM"), COMMA_DOT, { { "/", "/" } }),
	} },
	{ id = "uk", text = "UK (ISO)", iso = true, rows = {
		Join({ { "`", "`" } }, DIGITS, { { "-", "-" }, { "=", "=" }, BACK }),
		Join({ TAB }, Letters("QWERTYUIOP"), { { "[", "[" }, { "]", "]" } }),
		Join({ CAPS }, Letters("ASDFGHJKL"), { { ";", ";" }, { "'", "'" }, { "#", "#" } }),
		Join({ ISO_SHIFT, { "\\", "\\" } }, Letters("ZXCVBNM"), COMMA_DOT, { { "/", "/" } }),
	} },
	{ id = "de", text = "German (QWERTZ)", iso = true, altGr = true, rows = {
		Join({ { "^", "^" } }, DIGITS, { { "ß", "ß" }, { "´", "´" }, BACK }),
		Join({ TAB }, Letters("QWERTZUIOP"), { { "Ü", "ü" }, { "+", "+" } }),
		Join({ CAPS }, Letters("ASDFGHJKL"), { { "Ö", "ö" }, { "Ä", "ä" }, { "#", "#" } }),
		Join({ ISO_SHIFT, { "<", "<" } }, Letters("YXCVBNM"), COMMA_DOT, { { "-", "-" } }),
	} },
	{ id = "no", text = "Norwegian", iso = true, altGr = true, rows = {
		Join({ { "||", "|" } }, DIGITS, { { "+", "+" }, { "\\", "\\" }, BACK }),
		Join({ TAB }, Letters("QWERTYUIOP"), { { "Å", "å" }, { "¨", "¨" } }),
		Join({ CAPS }, Letters("ASDFGHJKL"), { { "Ø", "ø" }, { "Æ", "æ" }, { "'", "'" } }),
		Join({ ISO_SHIFT, { "<", "<" } }, Letters("ZXCVBNM"), COMMA_DOT, { { "-", "-" } }),
	} },
}
local LAYOUT = {}
for _, layout in ipairs(LAYOUTS) do LAYOUT[layout.id] = layout end

-- The layout in use: Auto picks by the game's language.
local function AutoLayoutId()
	local locale = GetLocale and GetLocale()
	if locale == "deDE" then return "de" elseif locale == "enGB" then return "uk" end
	return "us"
end
local function LayoutId()
	local id = ns.db and ns.db.kbLayout
	return LAYOUT[id] and id or AutoLayoutId()
end

-- Every key to draw: { label, token, x, y, w, h, mod, arm } in key units
-- (1 = a letter key), for the layout and the page's Show ticks.
local function BuildKeys()
	local db = ns.db
	local layout = LAYOUT[LayoutId()]
	local keys = {}
	local function Key(label, token, x, y, w, h, mod)
		local def = { label = label, token = token, x = x, y = y, w = w or 1, h = h or 1, mod = mod }
		keys[#keys + 1] = def
		return def
	end
	Key("Esc", "ESCAPE", 0, 0)
	for i = 1, 12 do Key("F" .. i, "F" .. i, 2 + (i - 1) + math.floor((i - 1) / 4) * 0.5, 0) end
	for r, entries in ipairs(layout.rows) do
		local x = 0
		for _, e in ipairs(entries) do
			Key(e[1], e[2], x, 0.5 + r, e[3], 1, e[4])
			x = x + (e[3] or 1)
		end
	end
	-- ISO's tall Enter: the key on the home row, its wider arm on the row above.
	if layout.iso then
		Key("Enter", "ENTER", 13.75, 3.5, 1.25).arm = { x = 13.5, y = 2.5, w = 1.5 }
	end
	-- (The right Shift, Ctrl, Windows and menu keys aren't drawn: their space stays.)
	Key("Ctrl", nil, 0, 5.5, 1.25, 1, "ctrl")
	Key("Alt", nil, 2.5, 5.5, 1.25, 1, "alt")
	Key("Space", "SPACE", 3.75, 5.5, 6.25)
	Key(layout.altGr and "AltGr" or "Alt", nil, 10, 5.5, 1.25, 1, "alt")
	local right = 15
	local mouseSpot
	if db.kbExtended then
		Key("PrtSc", "PRINTSCREEN", 15.5, 0)
		Key("Scroll", "SCROLLLOCK", 16.5, 0)
		Key("Pause", "PAUSE", 17.5, 0)
		for i, e in ipairs({ { "Ins", "INSERT" }, { "Home", "HOME" }, { "PgUp", "PAGEUP" },
			{ "Del", "DELETE" }, { "End", "END" }, { "PgDn", "PAGEDOWN" } }) do
			Key(e[1], e[2], 15.5 + (i - 1) % 3, 1.5 + math.floor((i - 1) / 3))
		end
		-- (Words: the key names' plain font has no arrows.)
		Key("Up", "UP", 16.5, 4.5)
		Key("Left", "LEFT", 15.5, 5.5)
		Key("Down", "DOWN", 16.5, 5.5)
		Key("Right", "RIGHT", 17.5, 5.5)
		right = 18.5
	end
	-- The numpad: past the navigation keys, or beside the main ones without them.
	if db.kbNumpad then
		local x = right + 0.5
		Key("Num", "NUMLOCK", x, 1.5)
		Key("/", "NUMPADDIVIDE", x + 1, 1.5)
		Key("*", "NUMPADMULTIPLY", x + 2, 1.5)
		Key("-", "NUMPADMINUS", x + 3, 1.5)
		for i, n in ipairs({ 7, 8, 9, 4, 5, 6, 1, 2, 3 }) do
			Key(tostring(n), "NUMPAD" .. n, x + (i - 1) % 3, 2.5 + math.floor((i - 1) / 3))
		end
		Key("+", "NUMPADPLUS", x + 3, 2.5, 1, 2)
		Key("Enter", "ENTER", x + 3, 4.5, 1, 2) -- (the game binds both Enters as one)
		Key("0", "NUMPAD0", x, 5.5, 2)
		Key(",", "NUMPADDECIMAL", x + 2, 5.5)
		right = x + 4
	end
	-- The mouse: a big picture, its keys around it, each with a line to its
	-- part (point: where, in key units). The side buttons on the left (5 the
	-- front, upper; 4 the back), the wheel's on the right.
	if db.kbMouse then
		local x = right + 0.75
		-- (The picture: 1 wide to 2 tall, as tall as the main rows less a
		-- little and centered on them, rows 1.5 to 6.5.)
		local px, py, pw = x + 1.75, 1.5 + 0.1, 2.4
		-- A spot on the picture, on Media/make_keyboard_mouse.py's 64x128 grid
		-- (where it lands: Layout, the picture kept in shape as the map stretches).
		local function Point(gx, gy) return { gx = gx, gy = gy, x = px + gx / 64 * pw } end
		Key("Mouse 5", "BUTTON5", x, py + 1.5, 1.5).point = Point(3, 65)
		Key("Mouse 4", "BUTTON4", x, py + 2.85, 1.5).point = Point(3, 83)
		Key("Wheel up", "MOUSEWHEELUP", x + 4.5, py - 0.1, 1.5).point = Point(37, 21)
		Key("Middle", "BUTTON3", x + 4.5, py + 1.1, 1.5).point = Point(37, 29)
		Key("Wheel down", "MOUSEWHEELDOWN", x + 4.5, py + 2.3, 1.5).point = Point(37, 37)
		mouseSpot = { x = px, y = py, w = pw, h = pw * 2 }
		right = x + 6
	end
	return keys, right, mouseSpot
end

-- What a binding does ----------------------------------------------------------
-- Short names for the game's commands (by the command, never the key: rebind
-- J to Jump and it says Jump). Others show the game's own name.
local SHORT = {
	TOGGLEGAMEMENU = "Menu", TOGGLEWORLDMAP = "Map", TOGGLEGUILDTAB = "Guild", TOGGLEGUILD = "Guild",
	-- (Words, not arrows: the game's name font has no arrows, they'd be boxes.)
	MOVEFORWARD = "Forward", MOVEBACKWARD = "Back", STRAFELEFT = "Strafe left", STRAFERIGHT = "Strafe right",
	TARGETPARTYMEMBER1 = "Party 1", TARGETPARTYMEMBER2 = "Party 2", TARGETPARTYMEMBER3 = "Party 3",
	TARGETPARTYMEMBER4 = "Party 4", TARGETPET = "Pet", MOVEANDSTEER = "Move and steer",
	TOGGLEKEYBINDINGS = "Keybinds",
	TURNLEFT = "Turn left", TURNRIGHT = "Turn right", JUMP = "Jump", SITORSTAND = "Sit",
	TARGETNEARESTENEMY = "Target", TARGETPREVIOUSENEMY = "Prev enemy", TARGETNEARESTFRIEND = "Ally",
	OPENALLBAGS = "Bags", TOGGLEBACKPACK = "Backpack", TOGGLESPELLBOOK = "Spells",
	TOGGLEPROFESSIONBOOK = "Professions", TOGGLEQUESTLOG = "Quests", TOGGLETALENTS = "Talents",
	TOGGLESOCIAL = "Social", TOGGLEGROUPFINDER = "Group", TOGGLECHARACTER0 = "Character",
	TOGGLECHARACTER2 = "Reputation", TOGGLECHARACTER4 = "Skills", TOGGLERAIDTAB = "Raid",
	INTERACTTARGET = "Interact", FOLLOWTARGET = "Follow", SCREENSHOT = "Screenshot",
	OPENCHAT = "Chat", REPLY = "Reply", CHATPAGEUP = "Chat up", CHATPAGEDOWN = "Chat down",
	TOGGLERUN = "Run / walk", TOGGLESHEATH = "Sheathe", TOGGLEUI = "Hide UI", TOGGLEFPS = "FPS",
	NAMEPLATES = "Nameplates", FRIENDNAMEPLATES = "Ally plates", TOGGLESOUND = "Sound",
	TOGGLEMUSIC = "Music", VEHICLEEXIT = "Exit vehicle", TOGGLECOOLDOWNVIEWERSETTINGS = "Cooldowns",
	TOGGLEAUTORUN = "Autorun", TOGGLEMINIMAP = "Minimap", TOGGLEACHIEVEMENT = "Achievements",
	TOGGLECOLLECTIONS = "Collections", TOGGLEENCOUNTERJOURNAL = "Journal", TOGGLEMOUNTJOURNAL = "Mounts",
	ASSISTTARGET = "Assist", TARGETSELF = "Self", TARGETFOCUS = "Focus",
	-- (The game's longer names, as they'd read on a key.)
	TARGETLASTTARGET = "Last target", TARGETLASTHOSTILE = "Last enemy",
	TARGETNEARESTENEMYPLAYER = "Enemy player", TARGETPREVIOUSENEMYPLAYER = "Prev player",
	TARGETNEARESTFRIENDPLAYER = "Ally player", TARGETPREVIOUSFRIEND = "Prev ally",
	TARGETMOUSEOVER = "Mouseover", FOCUSTARGET = "Set focus", INTERACTMOUSEOVER = "Interact",
	ATTACKTARGET = "Attack", STARTATTACK = "Attack", PETATTACK = "Pet attack", STOPATTACK = "Stop attack",
	STOPCASTING = "Stop cast", CAMERAZOOMIN = "Zoom in", CAMERAZOOMOUT = "Zoom out",
	NEXTVIEW = "Next view", PREVVIEW = "Prev view", PITCHUP = "Pitch up", PITCHDOWN = "Pitch down",
	TOGGLEWORLDSTATESCORES = "Scores", TOGGLEBATTLEFIELDMINIMAP = "Zone map", TOGGLELFGPARENT = "Dungeons",
	TOGGLEPETJOURNAL = "Pets", TOGGLETOYBOX = "Toys", TOGGLEFRIENDSTAB = "Friends", TOGGLEWHOTAB = "Who",
	TOGGLECHANNELTAB = "Channels", TOGGLESTATISTICS = "Statistics", TOGGLEKEYRING = "Keyring",
	TOGGLEBAG1 = "Bag 1", TOGGLEBAG2 = "Bag 2", TOGGLEBAG3 = "Bag 3", TOGGLEBAG4 = "Bag 4", TOGGLEBAG5 = "Bag 5",
	ALLNAMEPLATES = "All plates", TOGGLECHATTAB = "Chat tab", COMBATLOGPAGEUP = "Log up",
	COMBATLOGPAGEDOWN = "Log down", CHATBOTTOM = "Chat end", TOGGLECOMBATLOG = "Combat log",
	TOGGLEACTIONBARLOCK = "Bar lock", ACTIONPAGE1 = "Bar 1", ACTIONPAGE2 = "Bar 2", NEXTACTIONPAGE = "Next bar",
	PREVIOUSACTIONPAGE = "Prev bar", RAIDTARGET1 = "Star", RAIDTARGET2 = "Circle", RAIDTARGET3 = "Diamond",
	RAIDTARGET4 = "Triangle", RAIDTARGET5 = "Moon", RAIDTARGET6 = "Square", RAIDTARGET7 = "Cross",
	RAIDTARGET8 = "Skull", RAIDTARGETNONE = "No marker", DISMOUNT = "Dismount", TOGGLEPINGLISTENER = "Ping",
	OPENCHATSLASH = "Slash",
	-- (Cinematic's own, short enough for a key.)
	CINEMATIC_TOGGLE = "CineMode", CINEMATIC_HIDEUI = "Hide UI", CINEMATIC_SCREENSHOT = "CineShot",
	CINEMATIC_TOGGLEEFFECTS = "Effects", CINEMATIC_TOGGLELETTERBOX = "Letterbox", CINEMATIC_RELOAD = "Reload",
	CINEMATIC_TOGGLESETTINGS = "Cinematic", CINEMATIC_KEYMAP = "Key map", CINEMATIC_CAMWHEEL = "Cam wheel",
	["CLICK CinematicMasterWheelButton:LeftButton"] = "Wheels",
	["CLICK CinematicMenuWheelButton:LeftButton"] = "Menu wheel",
	["CLICK CinematicMarkerWheelButton:LeftButton"] = "Markers",
	["CLICK CinematicVisionWheelButton:LeftButton"] = "Visions",
}
local function FullName(command)
	if command == nil or command == "" or command == "NONE" then return nil end
	local name = _G["BINDING_NAME_" .. command]
	if not name and GetBindingText then name = GetBindingText(command, "BINDING_NAME_") end
	return name or command
end

-- Where a binding sits in the game's Key Bindings list: an addon's own
-- section (its header, as Bartender4 or DBM name theirs) or the game's
-- category (Movement Keys...). Read once, again after bindings change. A key
-- an addon binds for itself (an override) isn't on the list: nil.
local sections
local function SectionOf(command)
	if not command or command == "" then return nil end
	if not sections then
		sections = {}
		if GetNumBindings and GetBinding then
			local header, lastCategory
			for i = 1, GetNumBindings() do
				local each, category = GetBinding(i)
				if type(each) == "string" then
					if category ~= lastCategory then header, lastCategory = nil, category end
					local headerKey = each:match("^HEADER_(.+)")
					if headerKey then
						local text = _G["BINDING_HEADER_" .. headerKey]
						if type(text) == "string" and text ~= "" then header = text end -- (blank ones: spacers)
					elseif each ~= "" then
						local categoryText = type(category) == "string" and _G[category] or nil
						if type(categoryText) ~= "string" then categoryText = nil end
						-- (Addons' all share AddOns: their header says whose.)
						sections[each] = (category == "ADDONS" and header) or categoryText or header
					end
				end
			end
		end
	end
	return sections[command]
end

local function ShortName(command)
	local short = SHORT[command]
	if short then return L[short] end
	local name = FullName(command)
	if not name then return nil end
	-- (Display only: the English word Toggle goes, and Cinematic's "Cinematic: ".)
	name = name:gsub("^Cinematic: ", ""):gsub("%f[%a][Tt]oggle%f[%A]%s*", "")
	-- (A note in brackets at the end goes: "Master wheel (hold)", "Keyboard
	-- map (hold, or tap to keep it up)".)
	name = name:gsub("%s*%b()$", "")
	-- A clicked button with no name of its own (an addon's): its frame's,
	-- made readable (CinematicMasterWheelButton: Master Wheel; OPieRing_3:
	-- OPie Ring 3). A spell, macro or item bound straight to the key: its name.
	local frame = name:match("^CLICK ([^:]+)")
	if frame then
		name = frame:gsub("^Cinematic", ""):gsub("Button$", ""):gsub("_", " ")
		name = name:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2")
	end
	name = name:gsub("^SPELL ", ""):gsub("^MACRO ", ""):gsub("^ITEM ", "")
	name = name:gsub("^[_%s]+", ""):gsub("[_%s]+$", "")
	-- (With Toggle gone, "Toggle settings" would start small.)
	return (name:gsub("^%l", string.upper))
end

local BAR_PREFIXES = { "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
	"MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

-- An action button's slot now (its bar's page, stance and vehicle counted).
local function SlotOf(button)
	if button.CalculateAction then
		local ok, slot = pcall(button.CalculateAction, button, "LeftButton")
		if ok and type(slot) == "number" then return slot end
	end
	if ActionButton_CalculateAction then
		local ok, slot = pcall(ActionButton_CalculateAction, button, "LeftButton")
		if ok and type(slot) == "number" then return slot end
	end
	-- (Addon bars built on LibActionButton: Bartender, ElvUI...)
	if button._state_type ~= nil and button._state_type ~= "action" then return nil end
	local slot = button._state_action or button.action
	if type(slot) ~= "number" and button.GetAttribute then slot = button:GetAttribute("action") end
	return type(slot) == "number" and slot or nil
end
local function HasActionIn(slot)
	local has = C_ActionBar and C_ActionBar.HasAction or HasAction
	if not has then return false end
	local value = has(slot)
	-- (Secret in a fight: taken as there, its picture then says.)
	if issecretvalue and issecretvalue(value) then return true end
	return value and true or false
end
local function ActionTexture(slot)
	local get = C_ActionBar and C_ActionBar.GetActionTexture or GetActionTexture
	return get and get(slot)
end
local function ButtonIcon(button)
	local icon = button.icon or button.Icon or (button.GetName and button:GetName() and _G[button:GetName() .. "Icon"])
	local texture = icon and icon.GetTexture and icon:GetTexture()
	if texture and icon:IsShown() then return texture end
end

-- What a command is: kind, and what to draw (info: slot, texture, button,
-- stance or pet index).
local function Classify(command)
	if command == nil or command == "" then return "unbound" end
	local button
	local n = command:match("^ACTIONBUTTON(%d+)$")
	if n then button = _G["ActionButton" .. n] end
	local bar, index = command:match("^MULTIACTIONBAR(%d+)BUTTON(%d+)$")
	if bar and BAR_PREFIXES[tonumber(bar)] then button = _G[BAR_PREFIXES[tonumber(bar)] .. index] end
	local stance = command:match("^SHAPESHIFTBUTTON(%d+)$")
	if stance and GetShapeshiftFormInfo then
		stance = tonumber(stance)
		local texture = (GetNumShapeshiftForms and stance <= GetNumShapeshiftForms()) and GetShapeshiftFormInfo(stance)
		return texture and "action" or "empty", { stance = stance, texture = texture }
	end
	local pet = command:match("^BONUSACTIONBUTTON(%d+)$")
	if pet and GetPetActionInfo then
		pet = tonumber(pet)
		local name, texture, isToken = GetPetActionInfo(pet)
		if isToken and texture then texture = _G[texture] end
		return (name and texture) and "action" or "empty", { pet = pet, texture = texture }
	end
	-- A spell, macro or item bound straight to the key (SetBindingSpell and
	-- the like: Clique, BindPad, OPie...): its icon.
	local kindOf, what = command:match("^(%u+) (.+)$")
	if kindOf == "SPELL" then
		local texture = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(what))
			or (GetSpellTexture and GetSpellTexture(what))
		return texture and "action" or "command", { spell = what, texture = texture, label = what }
	elseif kindOf == "MACRO" and GetMacroInfo then
		local name, texture = GetMacroInfo(what)
		return texture and "action" or "command", { macro = what, texture = texture, label = name or what }
	elseif kindOf == "ITEM" then
		local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
		local id, texture
		if instant then
			local results = { pcall(instant, what) }
			if results[1] then id, texture = results[2], results[6] end
		end
		return texture and "action" or "command", { itemID = id, texture = texture, label = what }
	end
	local clicked = command:match("^CLICK ([^:]+)")
	if clicked then
		button = _G[clicked]
		-- (Only an action button counts by its slot: the game's helper gives
		-- any button a slot, so a wheel's key showed slot 1's Attack.)
		if type(button) ~= "table" or not button.GetObjectType then return "command" end
		local isAction = button._state_type == "action" or type(button.action) == "number"
			or (button.GetAttribute and button:GetAttribute("type") == "action")
		if not isAction then
			local texture = ButtonIcon(button)
			if texture then return "action", { texture = texture, button = button } end
			return "command"
		end
	end
	if type(button) ~= "table" or not button.GetObjectType then
		return "command"
	end
	local slot = SlotOf(button)
	if slot then
		if HasActionIn(slot) then return "action", { slot = slot, texture = ActionTexture(slot), button = button } end
		return "empty", { slot = slot, button = button }
	end
	-- (A clicked button of some other kind: its own picture, if it has one.)
	local texture = clicked and ButtonIcon(button)
	if texture then return "action", { texture = texture, button = button } end
	return "command"
end

-- Searching -------------------------------------------------------------------
-- A text the search can use: a plain string (in a fight some may be secret).
local function Plain(value)
	if value == nil or (issecretvalue and issecretvalue(value)) or type(value) ~= "string" then return nil end
	return value
end
local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function ItemName(id)
	if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
	if GetItemInfo then return (GetItemInfo(id)) end
end
-- The names a key is found by: its action's (spell, item or macro), its
-- stance's or pet action's, its command's.
local function NamesOf(kind, info, command)
	local names = {}
	local function Add(value)
		value = Plain(value)
		if value and value ~= "" then names[#names + 1] = value:lower() end
	end
	info = info or {}
	if info.slot then
		local ok, actionType, id = pcall(GetActionInfo, info.slot)
		if ok and Plain(actionType) and type(id) == "number" and not (issecretvalue and issecretvalue(id)) then
			if actionType == "spell" then Add(SpellName(id))
			elseif actionType == "item" then Add(ItemName(id)) end
		end
		if GetActionText then Add(GetActionText(info.slot)) end -- (a macro's name)
	elseif info.stance and GetShapeshiftFormInfo then
		local _, second, _, spellID = GetShapeshiftFormInfo(info.stance)
		if type(spellID) == "number" then Add(SpellName(spellID)) end
		if type(second) == "string" then Add(second) end -- (Classic gives the name second)
	elseif info.pet and GetPetActionInfo then
		local name, _, isToken = GetPetActionInfo(info.pet)
		if isToken and name then name = _G[name] end
		Add(name)
	end
	Add(info.label) -- (a spell, macro or item bound to the key)
	if kind == "command" or kind == "empty" or info.label then
		Add(FullName(command))
		Add(ShortName(command))
	end
	Add(SectionOf(command)) -- (its addon: "dbm" finds DBM's keys)
	return names
end
local function Matches(names, query)
	for _, name in ipairs(names) do
		if name:find(query, 1, true) then return true end
	end
	return false
end

-- The map ---------------------------------------------------------------------
local board, measure, keyFrames, defs = nil, nil, {}, {}
local elsewhere, elsewhereFor -- (other layers' matches, and the query they're for: nil when out of date)
local held = {}     -- modifiers clicked on the map: kept down
local stayOpen      -- opened to stay (a tap, /cine keys, the page): the key closes it
local downAt        -- when its key went down (to tell a hold from a tap)
local dirty, layoutDirty = false, false
local TAP = 0.3     -- seconds: a shorter press keeps it up
local MIN_KEY = 22  -- (stretched no smaller than this a key, across or down)
local MIN_MAP_W, MIN_MAP_H = 420, 220 -- (the smallest it's dragged to)
local PAD, TOP, BOTTOM = 10, 44, 22
local EMPTY_SLOT = "Interface\\Buttons\\UI-Quickslot2"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MOUSE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\KeyboardMouse" -- (Media/make_keyboard_mouse.py)
local DOT_MODS = { "shift", "ctrl", "alt" }
local DOT_PREFIX = { shift = "SHIFT-", ctrl = "CTRL-", alt = "ALT-" }
local MAX_ELSEWHERE = 8 -- (other layers' matches listed at the bottom)

-- The modifiers shown: held on the keyboard, or kept from the map. (Not the
-- held ones while you type in the search box: Shift for a capital would swap
-- the layer under you.)
local function Mods()
	local typing = board and board.search and board.search:HasFocus()
	return {
		shift = held.shift or (not typing and IsShiftKeyDown() and true or false),
		ctrl = held.ctrl or (not typing and IsControlKeyDown() and true or false),
		alt = held.alt or (not typing and IsAltKeyDown() and true or false),
	}
end
-- The binding's prefix for those (the game's order: ALT-CTRL-SHIFT-).
local function Prefix(mods)
	return (mods.alt and "ALT-" or "") .. (mods.ctrl and "CTRL-" or "") .. (mods.shift and "SHIFT-" or "")
end
-- Every layer's prefix, no modifier first.
local PREFIXES = {}
for mask = 0, 7 do
	PREFIXES[#PREFIXES + 1] = Prefix({ shift = mask % 2 == 1, ctrl = math.floor(mask / 2) % 2 == 1, alt = mask >= 4 })
end
local function LayerName(mods)
	local parts = {}
	if mods.shift then parts[#parts + 1] = L["Shift"] end
	if mods.ctrl then parts[#parts + 1] = L["Ctrl"] end
	if mods.alt then parts[#parts + 1] = L["Alt"] end
	return #parts > 0 and table.concat(parts, " + ") or L["No modifier"]
end

local function SetScaledText(fs, scale)
	if fs.SetTextScale then fs:SetTextScale(scale) end
end
-- No drop shadow: the game's fonts' smudge one down and to the right.
local function NoShadow(fs)
	fs:SetShadowOffset(0, 0)
	fs:SetShadowColor(0, 0, 0, 0)
	return fs
end
-- A key's name: plain, or in the game's outlined hotkey font over an icon
-- (readable on any picture). Its text is set again after the swap.
local KEY_FONT, KEY_FONT_ICON = "GameFontNormalSmall", "NumberFontNormalSmall"
local function KeyLabelFont(f, overIcon)
	if f.overIcon == overIcon then return end
	f.overIcon = overIcon
	local label = f.keyLabel
	label:SetFontObject(overIcon and KEY_FONT_ICON or KEY_FONT)
	NoShadow(label)
	label:SetTextColor(1, 0.82, 0)
	SetScaledText(label, f.labelScale or ns.db.kbTextScale or 1)
	label:SetText(label:GetText() or "")
end

-- How a name fits its key. Each try is set on the key's own text and kept
-- if the game says nothing's cut off (IsTruncated): a copy measured on its
-- own read differently in the game ("Command" too wide, "Keyboard map" not).
-- In order: as it is (wrapping at its spaces), a hair smaller (NUDGE) still
-- whole, then over two lines at the best split, then smaller steps of both
-- down to SMALLEST. A split is at a space, or inside a one-word name of
-- LONG_WORD letters or more with MIN_PART at least each side (Split long names): the
-- splits are tried narrowest first, a space ahead unless a word's split is
-- clearly narrower (MID_WORD). The copy (measure) only ranks them.
local NUDGE, SMALLEST, MIN_PART, MID_WORD = 0.85, 0.65, 3, 1.15
local LONG_WORD = 8 -- (a shorter word is never split: "Aut / orun" reads worse than a little smaller)
local STEPS = { 1, 0.9, 0.8, 0.72, SMALLEST }
local MAX_SPLITS = 3
local function Width(text)
	measure:SetText(text)
	return measure:GetStringWidth() or 0
end
-- A name's two-line splits, best first.
local function Splits(text)
	local chars = {}
	for c in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = c end
	-- (Each letter's place in its word, from the start and from the end.)
	local fromStart, fromEnd = {}, {}
	for i, c in ipairs(chars) do fromStart[i] = c == " " and 0 or ((fromStart[i - 1] or 0) + 1) end
	for i = #chars, 1, -1 do fromEnd[i] = chars[i] == " " and 0 or ((fromEnd[i + 1] or 0) + 1) end
	local list = {}
	local oneWord = not text:find(" ") -- (a name with spaces splits only at one: never "Keybo / ard map")
	for i = 1, #chars - 1 do
		local head, tail, inWord
		if chars[i + 1] == " " then
			head, tail = table.concat(chars, "", 1, i), table.concat(chars, "", i + 2)
		elseif oneWord and ns.db.kbSplitWords and fromStart[i] >= MIN_PART and fromEnd[i + 1] >= MIN_PART
			and fromStart[i] + fromEnd[i + 1] >= LONG_WORD then
			head, tail, inWord = table.concat(chars, "", 1, i), table.concat(chars, "", i + 1), true
		end
		if head and head ~= "" and tail ~= "" then
			local score = math.max(Width(head), Width(tail)) * (inWord and MID_WORD or 1)
			list[#list + 1] = { text = head .. "\n" .. tail, score = score }
		end
	end
	table.sort(list, function(a, b) return a.score < b.score end)
	for i = #list, MAX_SPLITS + 1, -1 do list[i] = nil end
	return list
end
-- Puts the command's name on key f, at the page's text size (base) or as
-- much smaller as it takes.
local function FitName(f, text, base)
	local fs = f.name
	local function Try(shown, smaller)
		SetScaledText(fs, base * smaller)
		fs:SetText(shown)
		return not (fs.IsTruncated and fs:IsTruncated())
	end
	if not text or text == "" then
		Try("", 1)
		return
	end
	if Try(text, 1) or Try(text, NUDGE) then return end
	local splits = Splits(text)
	for _, smaller in ipairs(STEPS) do
		for _, split in ipairs(splits) do
			if Try(split.text, smaller) then return end
		end
		if smaller < NUDGE and Try(text, smaller) then return end
	end
	Try(splits[1] and splits[1].text or text, SMALLEST) -- (nothing fit: the best at the smallest, cut off)
end

-- A spell's ID from its name, for its tooltip (nil if the game won't say).
local function SpellID(name)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(name)
		return type(info) == "table" and info.spellID or nil
	end
	if GetSpellInfo then return (select(7, GetSpellInfo(name))) end
end

local function ShowTooltip(f)
	local def, info = f.def, f.info or {}
	GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
	if def.mod then
		GameTooltip:SetText(L[def.label], 1, 1, 1)
		GameTooltip:AddLine(held[def.mod] and L["Kept down: click to let go."]
			or L["Click to keep it down and see its keys' bindings without holding it."], nil, nil, nil, true)
		GameTooltip:Show()
		return
	end
	local combo = f.combo or ""
	local keyText = GetBindingText and GetBindingText(combo) or combo
	if f.kind == "action" and info.slot then
		GameTooltip:SetAction(info.slot)
	elseif f.kind == "action" and info.stance then
		GameTooltip:SetShapeshift(info.stance)
	elseif f.kind == "action" and info.pet then
		GameTooltip:SetPetAction(info.pet)
	elseif f.kind == "action" and info.itemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(info.itemID)
	elseif f.kind == "action" and info.spell and GameTooltip.SetSpellByID and SpellID(info.spell) then
		GameTooltip:SetSpellByID(SpellID(info.spell))
	elseif info.label then
		GameTooltip:SetText(info.label, 1, 1, 1)
		GameTooltip:AddLine(info.macro and L["Macro"] or info.spell and L["Spell"] or L["Item"], 0.7, 0.7, 0.7)
	else
		GameTooltip:SetText(keyText, 1, 1, 1)
		if f.kind == "unbound" then
			GameTooltip:AddLine(L["Not bound: free to use."], 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine(FullName(f.command) or "", nil, nil, nil, true)
		end
		if f.kind == "empty" then
			GameTooltip:AddLine(L["Bound to an action button with nothing on it."], 1, 0.82, 0, true)
		end
		local section = SectionOf(f.command)
		if section then GameTooltip:AddLine(L["From: %s"]:format(section), 0.6, 0.6, 0.6) end
		GameTooltip:AddLine((f.info and f.info.slot) and L["Drop a spell, macro or item here to put it on this " ..
			"action button. Right-click to clear the key."]
			or f.kind == "unbound" and L["Drop a spell, macro, item or mount here to bind it."]
			or L["Drop a spell, macro, item or mount here to bind it instead. Right-click to clear it."],
			0.5, 0.75, 1, true)
		GameTooltip:Show()
		return
	end
	GameTooltip:AddLine(keyText, 0.6, 0.8, 1)
	local section = SectionOf(f.command)
	if section then GameTooltip:AddLine(L["From: %s"]:format(section), 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

-- Binding from the map ----------------------------------------------------------
-- What's on the cursor, as something a key can be bound to: "spell", "macro"
-- or "item" and its name (a mount: its spell). nil if nothing or not those.
local function CursorBinding()
	local kind, a, b, c = GetCursorInfo()
	if kind == "spell" then
		local name = type(c) == "number" and SpellName(c) or nil
		if not name and GetSpellBookItemName and a then name = GetSpellBookItemName(a, b) end
		return "spell", Plain(name)
	elseif kind == "macro" and GetMacroInfo then
		return "macro", Plain((GetMacroInfo(a)))
	elseif kind == "item" then
		return "item", Plain(ItemName(a)) or (type(b) == "string" and b:match("%[(.-)%]"))
	elseif kind == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID then
		local _, spellID = C_MountJournal.GetMountInfoByID(a)
		return "spell", spellID and Plain(SpellName(spellID))
	end
	return kind and "other" or nil
end

local function Combo(f)
	return GetBindingText and GetBindingText(f.combo) or f.combo
end
-- What the key does now, in a few words (for the chat line after a change).
local function Doing(f)
	if f.kind == "unbound" then return nil end
	return (f.info and f.info.label) or ShortName(f.command) or f.command
end
local function SaveKeys()
	if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
end

-- Binds what's on the cursor to key f, on the layer shown. Out of fights only.
function ns.KeyboardMapBind(f)
	if not f.combo then return end
	local what, name = CursorBinding()
	if not what then return end
	if InCombatLockdown() then
		ns.Print(L["keys can't be bound in a fight: try again after it"])
		return
	end
	-- A key bound to an action button (gold, empty, or with something on
	-- it): the spell goes on that button, as dropping it on the bar does,
	-- what was there picked up. The key stays as it is.
	if f.info and f.info.slot and PlaceAction then
		PlaceAction(f.info.slot)
		ns.Print(L["%s: put on its action button"]:format(Combo(f)))
		elsewhereFor, dirty = nil, true
		return
	end
	if what == "other" then
		ns.Print(L["only spells, macros, items and mounts can be bound to a key from the map"])
		return
	end
	if not name then
		ns.Print(L["the game hasn't given its name yet: try again in a moment"])
		return
	end
	local set = what == "spell" and SetBindingSpell or what == "macro" and SetBindingMacro or SetBindingItem
	if not (set and set(f.combo, name)) then
		ns.Print(L["%s couldn't be bound to %s"]:format(name, Combo(f)))
		return
	end
	local was = Doing(f)
	SaveKeys()
	ClearCursor()
	ns.Print(was and L["%s is now %s (it was %s)"]:format(Combo(f), name, was)
		or L["%s is now %s"]:format(Combo(f), name))
	elsewhereFor, dirty = nil, true
end

-- Asks, then clears key f's binding on the layer shown.
function ns.KeyboardMapClear(f)
	if not f.combo then return end
	if InCombatLockdown() then
		ns.Print(L["keys can't be changed in a fight: try again after it"])
		return
	end
	if not StaticPopupDialogs.CINEMATIC_KEYMAP_CLEAR then
		StaticPopupDialogs.CINEMATIC_KEYMAP_CLEAR = {
			text = L["Clear %s? It does %s now."],
			button1 = YES or L["Yes"], button2 = NO or L["No"],
			OnAccept = function(_, data)
				if InCombatLockdown() then return end
				SetBinding(data.combo)
				SaveKeys()
				ns.Print(L["%s is unbound now (it was %s)"]:format(data.text, data.was))
				elsewhereFor, dirty = nil, true
			end,
			timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
		}
	end
	local was = Doing(f) or ""
	local dialog = StaticPopup_Show("CINEMATIC_KEYMAP_CLEAR", Combo(f), was)
	if dialog then dialog.data = { combo = f.combo, text = Combo(f), was = was } end
end

local function MakeKey(i)
	local f = CreateFrame("Button", nil, board)
	f.rim = f:CreateTexture(nil, "BACKGROUND")
	f.rim:SetAllPoints()
	f.face = f:CreateTexture(nil, "BORDER")
	f.face:SetPoint("TOPLEFT", 2, -2)
	f.face:SetPoint("BOTTOMRIGHT", -2, 2)
	f.slot = f:CreateTexture(nil, "ARTWORK", nil, -1)
	f.slot:SetPoint("TOPLEFT", 3, -3)
	f.slot:SetPoint("BOTTOMRIGHT", -3, 3)
	f.slot:SetTexture(EMPTY_SLOT)
	f.slot:SetTexCoord(0.2, 0.8, 0.2, 0.8)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("CENTER")
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.mask = f:CreateMaskTexture()
	f.mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	f.mask:SetAllPoints(f.icon)
	f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cooldown:SetAllPoints(f.icon)
	if f.cooldown.SetDrawEdge then f.cooldown:SetDrawEdge(false) end
	f.over = CreateFrame("Frame", nil, f)
	f.over:SetAllPoints()
	f.over:SetFrameLevel(f.cooldown:GetFrameLevel() + 2)
	-- (The key's name: KeyLabelFont's.)
	f.keyLabel = NoShadow(f.over:CreateFontString(nil, "OVERLAY", KEY_FONT))
	f.keyLabel:SetPoint("TOPLEFT", 3, -2)
	f.keyLabel:SetJustifyH("LEFT")
	f.keyLabel:SetTextColor(1, 0.82, 0)
	f.overIcon = false
	f.name = NoShadow(f.over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
	f.name:SetJustifyH("CENTER")
	f.name:SetJustifyV("MIDDLE")
	f.name:SetWordWrap(true)
	if f.name.SetNonSpaceWrap then f.name:SetNonSpaceWrap(false) end
	if f.name.SetMaxLines then f.name:SetMaxLines(2) end
	f.count = f.over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	f.count:SetPoint("BOTTOMRIGHT", -3, 3)
	f.armRim = board:CreateTexture(nil, "BACKGROUND")
	f.armFace = board:CreateTexture(nil, "BORDER")
	f:SetScript("OnEnter", function(self)
		self.hover = true
		ShowTooltip(self)
		dirty = true
	end)
	f:SetScript("OnLeave", function(self)
		self.hover = false
		GameTooltip:Hide()
		dirty = true
	end)
	-- Modifiers: click to keep down. Other keys: drop a spell, macro, item
	-- or mount on one (or click it holding one) to bind it there, on the
	-- layer shown; right-click a bound one to clear it.
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f:SetScript("OnReceiveDrag", function(self)
		if not self.def.mod then ns.KeyboardMapBind(self) end
	end)
	f:SetScript("OnClick", function(self, button)
		if self.def.mod then
			if button ~= "LeftButton" then return end
			held[self.def.mod] = not held[self.def.mod] or nil
			dirty = true
			if GameTooltip:IsOwned(self) then ShowTooltip(self) end
		elseif button == "LeftButton" and GetCursorInfo() then
			ns.KeyboardMapBind(self)
		elseif button == "RightButton" and self.kind ~= "unbound" then
			ns.KeyboardMapClear(self)
		end
	end)
	-- Dots at the top right: this key's bindings on the Shift, Ctrl and Alt
	-- layers (Paint), in the modifiers' own colors.
	f.dots = {}
	for d = 1, 3 do
		local dot = f.over:CreateTexture(nil, "OVERLAY")
		dot:SetSize(5, 5)
		dot:SetPoint("TOPRIGHT", -3 - (3 - d) * 6, -3)
		f.dots[d] = dot
	end
	keyFrames[i] = f
	return f
end

-- Places every key for the settings now.
local function Layout()
	local db = ns.db
	local keys, right, mouseSpot = BuildKeys()
	board.numpad:SetChecked(db.kbNumpad and true or false)
	board.hideUnbound:SetChecked(db.kbHideUnbound and true or false)
	board.hideEmpty:SetChecked(db.kbHideEmpty and true or false)
	defs = keys
	local size = math.floor(db.kbKeySize or 40)
	local gap = math.max(2, math.floor(size / 10))
	-- A key's step across and down: from Key size, or stretched to the size
	-- the map was dragged to (kbWidth/kbHeight: the window's own).
	local stepX, stepY = size + gap, size + gap
	if db.kbWidth and db.kbHeight then
		stepX = math.max(MIN_KEY + gap, (db.kbWidth - PAD * 2 + gap) / right)
		stepY = math.max(MIN_KEY + gap, (db.kbHeight - TOP - BOTTOM - 4 + gap) / 6.5)
	end
	local keyW, keyH = stepX - gap, stepY - gap
	local round = db.kbRound
	local disc = ns.HELP_DISC or WHITE
	board:SetSize(right * stepX - gap + PAD * 2, 6.5 * stepY - gap + TOP + BOTTOM + 4)
	board.right = right
	-- The mouse picture, among its keys: half as wide as it's tall however
	-- the map's stretched, in the middle of its space.
	board.mouse:SetShown(mouseSpot ~= nil)
	local picX, picY, picW, picH
	if mouseSpot then
		local spaceW, spaceH = mouseSpot.w * stepX, mouseSpot.h * stepY
		picW = math.min(spaceW, spaceH / 2)
		picH = picW * 2
		picX = PAD + mouseSpot.x * stepX + (spaceW - picW) / 2
		picY = TOP + mouseSpot.y * stepY + (spaceH - picH) / 2
		board.mouse:SetSize(picW, picH)
		board.mouse:ClearAllPoints()
		board.mouse:SetPoint("TOPLEFT", board, "TOPLEFT", picX, -picY)
	end
	for i, def in ipairs(keys) do
		local f = keyFrames[i] or MakeKey(i)
		f.def = def
		local w, h = def.w * stepX - gap, def.h * stepY - gap
		local x, y = PAD + def.x * stepX, -(TOP + def.y * stepY)
		f:ClearAllPoints()
		if round then
			-- (Round: a key's width disc, at the left of a wide key's space.)
			local d = math.min(keyW, keyH, h)
			f:SetSize(d, d)
			f:SetPoint("TOPLEFT", board, "TOPLEFT", x + (def.x == 0 and 0 or (w - d) / 2), y - (h - d) / 2)
			w, h = d, d
		else
			f:SetSize(w, h)
			f:SetPoint("TOPLEFT", board, "TOPLEFT", x, y)
		end
		local texture = round and disc or WHITE
		f.rim:SetTexture(texture)
		f.face:SetTexture(texture)
		f.slot:SetShown(false)
		local iconSize = math.min(w, h) - 6
		f.icon:SetSize(iconSize, iconSize)
		if round and not f.masked then
			f.icon:AddMaskTexture(f.mask)
			f.masked = true
		elseif not round and f.masked then
			f.icon:RemoveMaskTexture(f.mask)
			f.masked = false
		end
		if f.cooldown.SetSwipeTexture then pcall(f.cooldown.SetSwipeTexture, f.cooldown, texture) end
		local scale = db.kbTextScale or 1
		SetScaledText(f.keyLabel, scale)
		SetScaledText(f.name, scale)
		f.keyLabel:SetText(def.label:len() > 2 and L[def.label] or def.label)
		-- (A key name too wide for its key, like Wheel down, drawn smaller to fit.)
		local labelWidth = f.keyLabel:GetStringWidth() or 0
		f.labelScale = labelWidth > w - 6 and math.max(0.6, scale * (w - 6) / labelWidth) or scale
		SetScaledText(f.keyLabel, f.labelScale)
		f.name:ClearAllPoints()
		-- (The key's whole width, but for its edge line.)
		f.name:SetPoint("TOPLEFT", 1, -(f.keyLabel:GetStringHeight() + 2))
		f.name:SetPoint("BOTTOMRIGHT", -1, 2)
		f.nameWidth = w - 4
		f.shownText = nil
		local arm = def.arm and not round
		f.armRim:SetShown(arm)
		f.armFace:SetShown(arm)
		if arm then
			local ax, ay, aw = PAD + def.arm.x * stepX, -(TOP + def.arm.y * stepY), def.arm.w * stepX - gap
			f.armRim:ClearAllPoints()
			f.armRim:SetPoint("TOPLEFT", board, "TOPLEFT", ax, ay)
			f.armRim:SetSize(aw, stepY) -- (down into the key below: one shape)
			f.armFace:ClearAllPoints()
			f.armFace:SetPoint("TOPLEFT", board, "TOPLEFT", ax + 2, ay - 2)
			f.armFace:SetSize(aw - 4, stepY)
			f.armRim:SetTexture(WHITE)
			f.armFace:SetTexture(WHITE)
		end
		-- A mouse key's line to its part of the picture, from the key's side
		-- that faces it, a dot where it lands (colored as the key: Paint).
		if def.point then
			if not f.line then
				f.line = board:CreateLine(nil, "BORDER")
				f.line:SetColorTexture(1, 1, 1, 1)
				f.dot = board:CreateTexture(nil, "OVERLAY")
			end
			local tx, ty = picX + def.point.gx / 64 * picW, -(picY + def.point.gy / 128 * picH)
			f.line:SetThickness(2)
			f.line:SetStartPoint(def.point.x > def.x and "RIGHT" or "LEFT", f, 0, 0)
			f.line:SetEndPoint("TOPLEFT", board, tx, ty)
			f.dot:SetTexture(disc)
			f.dot:SetSize(7, 7)
			f.dot:ClearAllPoints()
			f.dot:SetPoint("CENTER", board, "TOPLEFT", tx, ty)
		end
		f.hasLine = def.point ~= nil and f.line ~= nil
		if f.line then
			f.line:SetShown(f.hasLine)
			f.dot:SetShown(f.hasLine)
		end
		f:Show()
	end
	for i = #keys + 1, #keyFrames do
		keyFrames[i]:Hide()
		keyFrames[i].armRim:Hide()
		keyFrames[i].armFace:Hide()
		if keyFrames[i].line then
			keyFrames[i].hasLine = false
			keyFrames[i].line:Hide()
			keyFrames[i].dot:Hide()
		end
	end
	SetScaledText(measure, db.kbTextScale or 1)
	layoutDirty = false
end

local function SetCooldown(f, info)
	local cd = f.cooldown
	if info.slot and C_ActionBar and C_ActionBar.GetActionCooldownDuration and cd.SetCooldownFromDurationObject then
		local duration = C_ActionBar.GetActionCooldownDuration(info.slot)
		if duration then cd:SetCooldownFromDurationObject(duration, true) else cd:Clear() end
		return
	end
	local start, duration, enable
	if info.slot and GetActionCooldown then
		start, duration, enable = GetActionCooldown(info.slot)
	elseif info.stance and GetShapeshiftFormCooldown then
		start, duration, enable = GetShapeshiftFormCooldown(info.stance)
	elseif info.pet and GetPetActionCooldown then
		start, duration, enable = GetPetActionCooldown(info.pet)
	end
	if not (start and CooldownFrame_Set and pcall(CooldownFrame_Set, cd, start, duration, enable)) then cd:Clear() end
end

-- The search box's words, lowercase ("" with none).
local function Query()
	local text = board.search and board.search:GetText() or ""
	return (text:lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The bottom line: while searching, the matches on the other layers (each
-- key once), so you needn't hold every modifier to find one; else the hint.
local function ShowElsewhere(query, prefix)
	if query == "" then
		board.elsewhere:SetText("")
		board.hint:Show()
		board.credit:Show()
		return
	end
	board.hint:Hide()
	board.credit:Hide()
	if elsewhereFor ~= query then
		elsewhere, elsewhereFor = {}, query
		local seen = {}
		for _, p in ipairs(PREFIXES) do
			for _, def in ipairs(defs) do
				local combo = def.token and p .. def.token
				if combo and not seen[combo] then
					seen[combo] = true
					local command = GetBindingAction(combo, true)
					local kind, info = Classify(command)
					if kind ~= "unbound" and Matches(NamesOf(kind, info, command), query) then
						elsewhere[#elsewhere + 1] = { prefix = p, combo = combo }
					end
				end
			end
		end
	end
	local list = {}
	for _, found in ipairs(elsewhere) do
		if found.prefix ~= prefix then
			list[#list + 1] = GetBindingText and GetBindingText(found.combo) or found.combo
		end
	end
	if #list == 0 then
		board.elsewhere:SetText(L["Not on any other layer."])
	else
		local more = #list - MAX_ELSEWHERE
		for i = #list, MAX_ELSEWHERE + 1, -1 do list[i] = nil end
		board.elsewhere:SetText(L["Also on: %s"]:format(table.concat(list, ", ")) ..
			(more > 0 and (" " .. L["and %d more"]:format(more)) or ""))
	end
end

-- Draws every key for the modifiers shown now.
local function Paint()
	local db = ns.db
	local mods = Mods()
	local prefix = Prefix(mods)
	local query = Query()
	board.title:SetText(L["Keyboard Map"] .. "  |cff999999·|r  " .. LayerName(mods))
	ShowElsewhere(query, prefix)
	for i, def in ipairs(defs) do
		local f = keyFrames[i]
		local kind, info, command
		if def.mod then
			kind = "modifier"
		else
			f.combo = prefix .. def.token
			command = GetBindingAction(f.combo, true)
			kind, info = Classify(command)
		end
		f.kind, f.info, f.command = kind, info, command
		local hidden = (kind == "unbound" and db.kbHideUnbound) or (kind == "empty" and db.kbHideEmpty)
			or (kind == "command" and db.kbHideCommands)
		f:SetShown(not hidden)
		f.armRim:SetShown(def.arm ~= nil and not hidden and not db.kbRound)
		f.armFace:SetShown(def.arm ~= nil and not hidden and not db.kbRound)
		if f.hasLine then
			f.line:SetShown(not hidden)
			f.dot:SetShown(not hidden)
		end
		if not hidden then
			local r, g, b = ColorOf(kind, def.mod)
			local lit = kind ~= "unbound" and (kind ~= "modifier" or mods[def.mod])
			local fr, fg, fb = 0.05, 0.07, 0.10
			if kind == "command" then
				fr, fg, fb = r * 0.25, g * 0.25, b * 0.25
			elseif kind == "modifier" and lit then
				fr, fg, fb = r * 0.35, g * 0.35, b * 0.35
			elseif kind == "unbound" then
				fr, fg, fb = 0.03, 0.035, 0.05
			end
			if f.hover then r, g, b = r + (1 - r) * 0.5, g + (1 - g) * 0.5, b + (1 - b) * 0.5 end
			local edge = (kind == "modifier" and not lit) and 0.6 or 1
			f.rim:SetVertexColor(r * edge, g * edge, b * edge, 1)
			f.face:SetVertexColor(fr, fg, fb, 1)
			f.armRim:SetVertexColor(r * edge, g * edge, b * edge, 1)
			f.armFace:SetVertexColor(fr, fg, fb, 1)
			-- (A mouse key's line: its color; an unbound one's grey enough to see.)
			if f.hasLine then
				local lr, lg, lb = r, g, b
				if kind == "unbound" then lr, lg, lb = 0.4, 0.45, 0.5 end
				f.line:SetVertexColor(lr, lg, lb, 0.9)
				f.dot:SetVertexColor(lr, lg, lb, 1)
			end
			-- Empty: the empty slot picture, tinted. Unbound: a dim key name.
			f.slot:SetShown(kind == "empty")
			if kind == "empty" then f.slot:SetVertexColor(r, g, b, 0.55) end
			f.keyLabel:SetAlpha(kind == "unbound" and 0.45 or 1)
			-- (Dots: bound on the Shift, Ctrl or Alt layer, other than the one shown.)
			for d, mod in ipairs(DOT_MODS) do
				local dot = f.dots[d]
				local layer = DOT_PREFIX[mod]
				local bound = def.token and layer ~= prefix and (GetBindingAction(layer .. def.token, true) or "") ~= ""
				dot:SetShown(bound and true or false)
				if bound then
					local c = EACH[mod]
					dot:SetTexture(ns.HELP_DISC or WHITE)
					dot:SetVertexColor(c[1], c[2], c[3], 1)
				end
			end
			local texture = kind == "action" and info and info.texture
			f.icon:SetTexture(texture or nil)
			f.icon:SetShown(texture and true or false)
			KeyLabelFont(f, texture and true or false)
			if texture then
				SetCooldown(f, info)
				local count = info.button and (info.button.Count or info.button.count)
				-- (Counts may be secret in fights: passed straight to the text. One
				-- the game hides, like a 0 it keeps, isn't shown; hidden or not
				-- may be secret on Forever too, and then it's shown.)
				local countShown = count and count.GetText and count:IsShown()
				if countShown and issecretvalue and issecretvalue(countShown) then countShown = true end
				if countShown then f.count:SetText(count:GetText()) else f.count:SetText("") end
			else
				f.cooldown:Clear()
				f.count:SetText("")
			end
			local text = kind == "command" and ShortName(command) or nil
			if text ~= f.shownText then
				f.shownText = text
				FitName(f, text, db.kbTextScale or 1)
			end
			-- (Searching: the keys that don't match are dimmed; modifiers stay.)
			local match = query == "" or kind == "modifier"
				or (kind ~= "unbound" and Matches(NamesOf(kind, info, command), query))
			f:SetAlpha(match and 1 or 0.2)
			f.armRim:SetAlpha(match and 1 or 0.2)
			f.armFace:SetAlpha(match and 1 or 0.2)
			if f.hasLine then
				f.line:SetAlpha(match and 1 or 0.2)
				f.dot:SetAlpha(match and 1 or 0.2)
			end
			if f.hover and GameTooltip:IsOwned(f) then ShowTooltip(f) end
		end
	end
	dirty = false
end

local EVENTS = { "MODIFIER_STATE_CHANGED", "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
	"UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_SHAPESHIFT_FORMS",
	"UPDATE_SHAPESHIFT_FORM", "PET_BAR_UPDATE", "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN",
	"SPELL_UPDATE_CHARGES", "UPDATE_MACROS", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" }

local function CreateBoard()
	board = CreateFrame("Frame", "CinematicKeyboardMap", UIParent)
	board:SetFrameStrata("DIALOG")
	board:SetClampedToScreen(true)
	board:SetMovable(true)
	board:EnableMouse(true)
	board:RegisterForDrag("LeftButton")
	board:Hide()
	local bg = board:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(0.02, 0.025, 0.04, 0.92)
	board.title = NoShadow(board:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
	board.mouse = board:CreateTexture(nil, "ARTWORK")
	board.mouse:SetTexture(MOUSE)
	board.mouse:SetVertexColor(0.55, 0.62, 0.72, 0.9)
	board.title:SetPoint("TOPLEFT", PAD, -16)
	-- (Inside the board's top bar, the title on its line, not on the edge.)
	local close = CreateFrame("Button", nil, board, "UIPanelCloseButton")
	close:SetPoint("RIGHT", board, "TOPRIGHT", -6, -22)
	close:SetScript("OnClick", function() ns.KeyboardMapClose() end)
	-- The search box, at the top by the close button (clear of the title as
	-- it grows): typing dims the keys that don't match (their spell, item,
	-- macro or command's name).
	local okSearch, search = pcall(CreateFrame, "EditBox", "CinematicKeyboardMapSearch", board, "SearchBoxTemplate")
	if not okSearch then
		search = CreateFrame("EditBox", "CinematicKeyboardMapSearch", board, "InputBoxTemplate")
	end
	search:SetSize(190, 20)
	search:SetPoint("RIGHT", close, "LEFT", -6, 0)
	search:SetAutoFocus(false)
	search:SetMaxLetters(40)
	if search.Instructions then search.Instructions:SetText(L["Search abilities"]) end
	search:HookScript("OnTextChanged", function() dirty = true end)
	-- (Clicked in: the map stays up as you type, its key let go or not.)
	search:HookScript("OnEditFocusGained", function()
		stayOpen, downAt = true, nil
		dirty = true
	end)
	search:HookScript("OnEditFocusLost", function() dirty = true end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
	end)
	board.search = search
	-- Ticks on the top bar, right to left from the search box: Numpad, Hide
	-- unbound, Hide empty (the page's ticks too). Clicking one keeps the map up.
	local function TopTick(key, label, tip, rightOf)
		local text = NoShadow(board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
		text:SetPoint("RIGHT", rightOf, "LEFT", -14, 0)
		text:SetText(label)
		local tick = CreateFrame("CheckButton", nil, board, "UICheckButtonTemplate")
		if ns.SkinCheck then ns.SkinCheck(tick) end
		tick:SetSize(22, 22)
		tick:SetPoint("RIGHT", text, "LEFT", -2, 0)
		tick:SetScript("OnClick", function(self)
			ns.db[key] = self:GetChecked() and true or false
			stayOpen, downAt = true, nil
			ns.KeyboardMapChanged()
		end)
		tick:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(label, 1, 1, 1)
			GameTooltip:AddLine(tip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		tick:SetScript("OnLeave", function() GameTooltip:Hide() end)
		tick.settingKey = key
		return tick
	end
	board.numpad = TopTick("kbNumpad", L["Numpad"], L["Show the numpad, at the right of the keyboard."], search)
	board.hideUnbound = TopTick("kbHideUnbound", L["Hide unbound"], L["Keys with nothing bound to them " ..
		"(with the modifiers shown) aren't drawn. The keyboard keeps its shape."], board.numpad)
	board.hideEmpty = TopTick("kbHideEmpty", L["Hide empty"], L["Keys bound to an action button with nothing " ..
		"on it aren't drawn. The keyboard keeps its shape."], board.hideUnbound)
	board.hint = NoShadow(board:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
	board.hint:SetPoint("BOTTOMRIGHT", -PAD - 14, 7) -- (clear of the size grip)
	board.hint:SetText(L["Drag to move. Click Shift, Ctrl or Alt to keep them down. Drop a spell on a key to bind it."])
	-- (Searching: where else it's bound, in place of the hint.)
	board.elsewhere = NoShadow(board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
	board.elsewhere:SetPoint("BOTTOMLEFT", PAD, 7)
	board.elsewhere:SetPoint("BOTTOMRIGHT", -PAD - 14, 7)
	-- A quiet nod to who first made it (Keyboard Bars), bottom left; the
	-- search's line has the spot while you search. (A name: not translated.)
	board.credit = NoShadow(board:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
	board.credit:SetPoint("BOTTOMLEFT", PAD, 7)
	board.credit:SetText(L["Made by %s"]:format("Discipline"))
	board.credit:SetAlpha(0.45)
	board.elsewhere:SetJustifyH("LEFT")
	board.elsewhere:SetWordWrap(false)
	measure = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	measure:SetAlpha(0)
	measure:SetWordWrap(false)
	measure:SetPoint("TOPLEFT")
	board:SetScript("OnDragStart", function(self) self:StartMoving() end)
	-- Where it is saved, kept by its middle (and put back by it).
	local function SavePlace(self)
		local x, y = self:GetCenter()
		local ux, uy = UIParent:GetCenter()
		local ratio = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
		ns.db.kbX, ns.db.kbY = math.floor(x * ratio - ux + 0.5), math.floor(y * ratio - uy + 0.5)
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", ns.db.kbX, ns.db.kbY)
	end
	board:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePlace(self)
	end)
	-- The size grip, bottom right: drag to stretch the map to any width and
	-- height (the keys stretch to fill it; kbWidth/kbHeight); right-click
	-- for the size Key size makes. Its top left stays put as it's dragged.
	local grip = CreateFrame("Button", nil, board)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(board:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:RegisterForClicks("RightButtonUp")
	local sizing
	local function Cursor()
		local x, y = GetCursorPosition()
		local scale = board:GetEffectiveScale()
		return x / scale, y / scale
	end
	grip:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		local cx, cy = Cursor()
		local w, h = board:GetSize()
		local left, top = board:GetLeft(), board:GetTop()
		board:ClearAllPoints()
		board:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		sizing = { cx = cx, cy = cy, w = w, h = h }
		stayOpen, downAt = true, nil
	end)
	grip:SetScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" or not sizing then return end
		sizing = nil
		SavePlace(board)
	end)
	grip:SetScript("OnClick", function()
		ns.db.kbWidth, ns.db.kbHeight = false, false
		ns.KeyboardMapChanged()
	end)
	ns.SetOnUpdate(grip, function()
		if not sizing then return end
		if not IsMouseButtonDown("LeftButton") then -- (let go off the grip)
			sizing = nil
			SavePlace(board)
			return
		end
		local cx, cy = Cursor()
		local w = math.floor(math.max(MIN_MAP_W, sizing.w + cx - sizing.cx) + 0.5)
		local h = math.floor(math.max(MIN_MAP_H, sizing.h + sizing.cy - cy) + 0.5)
		if w ~= ns.db.kbWidth or h ~= ns.db.kbHeight then
			ns.db.kbWidth, ns.db.kbHeight = w, h
			layoutDirty = true
		end
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["Drag to stretch the map"], 1, 1, 1)
		GameTooltip:AddLine(L["Right-click for the size Key size makes."], nil, nil, nil, true)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
	board:SetScript("OnEvent", function(_, event)
		if event == "UPDATE_BINDINGS" then
			for _, f in ipairs(keyFrames) do f.shownText = nil end
			sections = nil
		end
		-- (Other layers' matches: found again, unless only a modifier changed.)
		if event ~= "MODIFIER_STATE_CHANGED" then elsewhereFor = nil end
		dirty = true
	end)
	board:SetScript("OnShow", function(self)
		for _, event in ipairs(EVENTS) do pcall(self.RegisterEvent, self, event) end
	end)
	board:SetScript("OnHide", function(self)
		self:UnregisterAllEvents()
		wipe(held)
		stayOpen, downAt = nil, nil
		-- (Each time it opens, a fresh search.)
		self.search:ClearFocus()
		self.search:SetText("")
		elsewhereFor = nil
		if ns.KeyboardMapShownChanged then ns.KeyboardMapShownChanged() end
	end)
	-- (One draw a frame at most, however many events came: only while it's up.)
	ns.SetOnUpdate(board, function()
		if layoutDirty then Layout() dirty = true end
		if dirty then Paint() end
	end)
	-- (Escape closes it, like the game's windows.)
	tinsert(UISpecialFrames, "CinematicKeyboardMap")
end

function ns.KeyboardMapShown()
	return board ~= nil and board:IsShown()
end

-- Opens it (stay: up till closed, rather than while its key's held).
function ns.KeyboardMapOpen(stay)
	if not ns.db then return end
	if not board then CreateBoard() end
	stayOpen = stay or stayOpen
	if not board:IsShown() then
		board:ClearAllPoints()
		board:SetPoint("CENTER", UIParent, "CENTER", ns.db.kbX or 0, ns.db.kbY or 0)
		Layout()
		board:Show()
		Paint()
		if ns.KeyboardMapShownChanged then ns.KeyboardMapShownChanged() end
	end
end
-- /cine keys <words>: opens it searching for them.
function ns.KeyboardMapSearch(words)
	ns.KeyboardMapOpen(true)
	if board and board.search then
		board.search:SetText(words or "")
		dirty = true
	end
end
function ns.KeyboardMapClose()
	if board then board:Hide() end
end
function ns.KeyboardMapToggle()
	if ns.KeyboardMapShown() then ns.KeyboardMapClose() else ns.KeyboardMapOpen(true) end
end
-- A setting changed: placed and drawn again, if it's up.
function ns.KeyboardMapChanged()
	layoutDirty, dirty = true, true
end

-- /cine debug keys: the layout, the layer and how many keys of each kind it
-- has, then each key that isn't unbound (key, kind, its command), as the map
-- draws them now (open or not).
function ns.KeyboardMapDebug()
	if not ns.db then return end
	local mods = Mods()
	local prefix = Prefix(mods)
	local keys = BuildKeys()
	local counts, lines = {}, {}
	for _, def in ipairs(keys) do
		local kind, command = "modifier", nil
		if not def.mod then
			command = GetBindingAction(prefix .. def.token, true)
			kind = Classify(command)
		end
		counts[kind] = (counts[kind] or 0) + 1
		if kind ~= "unbound" and kind ~= "modifier" then
			lines[#lines + 1] = ("  %s%s: %s (%s)"):format(prefix, def.token, kind, tostring(command))
		end
	end
	ns.Print(("keyboard map: layout %s (setting %s), layer %s, shown %s, kept down %s%s%s, in a fight %s"):format(
		LayoutId(), tostring(ns.db.kbLayout), LayerName(mods), tostring(ns.KeyboardMapShown()),
		held.shift and "Shift " or "", held.ctrl and "Ctrl " or "", held.alt and "Alt" or "",
		tostring(InCombatLockdown and InCombatLockdown() or false)))
	print(("  action %d, empty %d, command %d, unbound %d, modifier %d"):format(counts.action or 0,
		counts.empty or 0, counts.command or 0, counts.unbound or 0, counts.modifier or 0))
	for _, line in ipairs(lines) do print(line) end
end

-- The key binding (CINEMATIC_KEYMAP, run on down and up): held, it's up till
-- you let go; tapped, it stays up till you press it again (or Escape).
function Cinematic_KeyboardMap(keystate)
	if keystate == "down" then
		if ns.KeyboardMapShown() and stayOpen then
			ns.KeyboardMapClose()
			return
		end
		ns.KeyboardMapOpen(false)
		downAt = GetTime()
	elseif downAt then
		if GetTime() - downAt < TAP then
			stayOpen = true
		else
			ns.KeyboardMapClose()
		end
		downAt = nil
	end
end

-- The page ----------------------------------------------------------------------
function ns.CreateKeyboardMapPage(kit)
	local canvas, content = kit.CreateScrollPage()
	local title = kit.Label(content, "GameFontNormalLarge", L["Keyboard Map"])
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = kit.PageIntro(content, title, L["Your keyboard on screen: what each key does, with your action " ..
		"buttons' icons and cooldowns. Hold Shift, Ctrl or Alt (or click them on the map) to see those keys' other " ..
		"bindings. Hold its key to peek, or tap it to keep the map up. It only shows your keys: place spells on " ..
		"your action bars and set keys in the game's Key Bindings."])
	local stack = kit.Stack(intro, "label")

	local function Changed() ns.KeyboardMapChanged() end

	-- Its key (two slots, as on the Keybinds page) and a button to open it.
	local keyLabel = stack:Add(kit.Label(content, "GameFontHighlight", L["Key"]), "label")
	keyLabel:SetSize(150, 24)
	local first = kit.CreateKeybindButton(content, "CINEMATIC_KEYMAP", 1)
	first:SetPoint("LEFT", keyLabel, "RIGHT", 4, 0)
	local second = kit.CreateKeybindButton(content, "CINEMATIC_KEYMAP", 2)
	second:SetPoint("LEFT", first, "RIGHT", 8, 0)
	local open = ns.PanelButton(content)
	open:SetSize(140, 22)
	open:SetPoint("LEFT", second, "RIGHT", 16, 0)
	local function OpenText() open:SetText(ns.KeyboardMapShown() and L["Close the map"] or L["Open the map"]) end
	open:SetScript("OnClick", ns.KeyboardMapToggle)
	kit.Tooltip(open, L["Opens the map till you close it (also /cine keys)."])
	ns.KeyboardMapShownChanged = OpenText
	OpenText()

	stack:Header(content, L["Keyboard"])
	local layoutName = stack:Add(kit.Label(content, "GameFontHighlight", L["Layout:"]), "label")
	layoutName:SetSize(150, 30)
	layoutName:SetJustifyV("MIDDLE")
	local layoutMenu = kit.Dropdown(content, "kbLayout", function()
		local list = { { value = "auto", text = L["Auto: %s"]:format(L[LAYOUT[AutoLayoutId()].text]) } }
		for _, layout in ipairs(LAYOUTS) do list[#list + 1] = { value = layout.id, text = L[layout.text] } end
		return list
	end, 200, Changed)
	if layoutMenu then
		layoutMenu:SetPoint("LEFT", layoutName, "RIGHT", 4, 0)
		kit.Tooltip(layoutMenu, L["Which keyboard to draw. Auto goes by your game's language: German, UK English, " ..
			"or US for the rest."])
	end
	local function Tick(key, label, tip)
		local check = stack:Add(kit.Check(content, key, label, tip), "check")
		check:HookScript("OnClick", Changed)
		return check
	end
	Tick("kbExtended", L["Show navigation and arrow keys"], L["Insert, Home, Page Up and the rest, the arrow " ..
		"keys and Print Screen, at the right. The numpad has its own tick on the map's top bar."])
	Tick("kbMouse", L["Show mouse buttons"], L["The middle button, buttons 4 and 5 and the wheel, at the right."])
	Tick("kbRound", L["Round keys"], L["Round keys and icons, each at the left of a wide key's space."])
	-- (Key size: the map as it makes it again, not stretched.)
	stack:Add(kit.Slider(content, "kbKeySize", L["Key size"], 28, 64, 1, "%d", nil, function()
		local db = ns.GetDB()
		db.kbWidth, db.kbHeight = false, false
		Changed()
	end), "slider")
	kit.RecordKey(content, "kbWidth")
	kit.RecordKey(content, "kbHeight")
	stack:Add(kit.Slider(content, "kbTextScale", L["Text size"], 70, 160, 5, "%d%%", 100, Changed), "slider")

	stack:Header(content, L["Keys"])
	Tick("kbHideUnbound", L["Hide unbound keys"], L["Keys with nothing bound to them aren't drawn (with the " ..
		"modifiers shown). The keyboard keeps its shape."])
	Tick("kbHideEmpty", L["Hide keys bound to empty action buttons"], L["Keys bound to an action button with " ..
		"nothing on it aren't drawn. The keyboard keeps its shape."])
	Tick("kbHideCommands", L["Hide keys bound to menus and movement"], L["Only keys bound to action buttons " ..
		"are drawn: not moving, targeting, windows or other commands. The keyboard keeps its shape."])
	Tick("kbSplitWords", L["Split long names over two lines"], L["A one-word name too wide for its key " ..
		"(Screenshot, Professions) goes over two lines instead of being cut off."])

	-- Colors: a dropdown of colors for each kind of key, and a swatch for your own.
	stack:Header(content, L["Colors"])
	for _, info in ipairs(KINDS) do
		local name = stack:Add(kit.Label(content, "GameFontHighlight", L[info.label]), "label")
		name:SetSize(150, 30)
		name:SetJustifyV("MIDDLE")
		local menu = kit.Dropdown(content, info.setting, function()
			local list = {}
			if info.kind == "modifier" then
				list[1] = { value = "each", text = L["Each its own"],
					tip = L["Shift blue, Ctrl red, Alt amber."] }
			end
			for _, p in ipairs(PRESETS) do
				list[#list + 1] = { value = p[1], text = L[p[2]], texture = WHITE, tint = { p[3], p[4], p[5] } }
			end
			list[#list + 1] = { value = "custom", text = L["Your own"], tip = L["Pick it with the square at the right."] }
			return list
		end, 160, Changed)
		local swatch = CreateFrame("Button", nil, content)
		swatch:SetSize(18, 18)
		swatch:SetPoint("LEFT", menu or name, "RIGHT", 10, 0)
		local border = swatch:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.6, 0.6, 0.6, 1)
		local color = swatch:CreateTexture(nil, "ARTWORK")
		color:SetPoint("TOPLEFT", 2, -2)
		color:SetPoint("BOTTOMRIGHT", -2, 2)
		swatch.Refresh = function()
			if ns.db then color:SetColorTexture(ColorOf(info.kind, "shift")) end
		end
		swatch:SetScript("OnClick", function()
			local r, g, b = ColorOf(info.kind, "shift")
			kit.OpenColorPicker(r, g, b, function(nr, ng, nb)
				local db = ns.GetDB()
				db[info.setting .. "R"], db[info.setting .. "G"], db[info.setting .. "B"] = nr, ng, nb
				db[info.setting] = "custom"
				Changed()
				kit.Refresh()
			end)
		end)
		kit.Tooltip(swatch, L["Pick your own color."])
		if menu then
			menu:SetPoint("LEFT", name, "RIGHT", 4, 0)
			kit.Tooltip(menu, L[info.tip])
		end
		kit.AddControl(swatch)
		kit.RecordKey(content, info.setting .. "R")
		kit.RecordKey(content, info.setting .. "G")
		kit.RecordKey(content, info.setting .. "B")
	end
	stack:Note(content, L["Based on Keyboard Bars by Ben."], 540)

	canvas:RegisterEvent("UPDATE_BINDINGS")
	canvas:SetScript("OnEvent", kit.RefreshKeybinds)
	kit.OnReset(content, Changed)
	canvas:SetScript("OnShow", kit.PageShown(function()
		kit.RefreshKeybinds()
		OpenText()
		kit.Refresh()
	end, content))
	canvas:SetScript("OnHide", kit.StopListening)
	canvas:Hide()
	kit.RegisterSubpage(canvas, "Keyboard Map")
end
