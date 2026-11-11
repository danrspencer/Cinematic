-- Cinematic: the Tooltips page's parts grid (with the page switched on, in
-- and out of CineMode). Each part shows on first hover or not
-- (tooltipShow<part>First), and once the tooltip's been up tooltipFullAfter
-- seconds or not (...Later): the background and border, the health bar
-- under unit tooltips, and lines of unit tooltips (players, NPCs and mobs):
-- guild and titles, level, spec and class, creature type, corpse, faction and PvP,
-- reputation faction, threat, quest lines; the quest lines of objects
-- in the world; and items' green click hints ("<Right Click to Read>").
-- A line is taken out by moving the lines under it up one (text and colour,
-- both sides) and clearing the last, then letting the tooltip size itself
-- again. Unreadable (secret) lines are kept, and a tooltip whose lines can't
-- all be read is left as it is.
local _, ns = ...

-- Hovered long enough (tooltipFullAfter): the After column's parts, until
-- the tooltip hides or moves on to another unit.
local revealed = false
-- Whether this tooltip's lines were cut (to fill in again for the After column).
local linesCut = false
-- Whether that cut was a unit's lines (not an object's or item's): the
-- Show hook cuts again with no readable unit then (see HookTooltipParts).
local unitLinesCut = false

-- Whether a part (ns.TOOLTIP_PARTS) is taken out now: unticked in the
-- column for now (On first hover, or After once revealed). With
-- tooltipFullAfter off, none is.
local function Cut(part)
	local db = ns.db
	if not (db and db.enabled and db.handleTooltips) or (db.tooltipFullAfter or 0) <= 0 then
		return false
	end
	return not db["tooltipShow" .. part .. (revealed and "Later" or "First")]
end

-- Fade in/out's seconds (tooltipFadeTime; nil: no fading, as with the
-- Tooltips page switched off: then tooltips are left as the game has them).
local function FadeTime()
	local db = ns.db
	local time = db and db.enabled and db.handleTooltips and db.tooltipFadeTime
	return time and time > 0 and time or nil
end

local function Left(i)
	return _G["GameTooltipTextLeft" .. i]
end
local function Right(i)
	return _G["GameTooltipTextRight" .. i]
end

-- Whether a and b are the same string (secret: no).
local function Same(a, b)
	local ok, same = pcall(function() return a ~= nil and a == b end)
	return ok and same
end

-- The titles of the quests in your log.
local function QuestTitles()
	local titles = {}
	pcall(function()
		if C_QuestLog and C_QuestLog.GetInfo then
			for i = 1, C_QuestLog.GetNumQuestLogEntries() do
				local info = C_QuestLog.GetInfo(i)
				if info and not info.isHeader and info.title then
					titles[info.title] = true
				end
			end
		elseif GetQuestLogTitle then
			for i = 1, GetNumQuestLogEntries() do
				local title, _, _, isHeader = GetQuestLogTitle(i)
				if title and not isHeader then
					titles[title] = true
				end
			end
		end
	end)
	return titles
end

-- A quest title as Questie writes it, down to the bare title: colour codes
-- and icons off, then its "[15] " level in front and " (123)" ID or "(Complete)" behind.
-- (Its lines aren't the game's quest lines, so the client gives no kind.)
local function BareTitle(text)
	local bare = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", ""):gsub("|T.-|t", "")
	bare = bare:gsub("^%s*%[[^%]]*%]%s*", ""):gsub("%s*%(%d+%)%s*$", ""):gsub("%s*%([^%(%)]*%)%s*$", "")
	return bare
end

-- The texts of the tooltip's lines whose kind the client gives, -> part:
-- quest lines (titles, objectives, party members on the quest) and threat.
local function TypedTexts(tooltip)
	local texts = {}
	local kinds = Enum and Enum.TooltipDataLineType
	if not (kinds and tooltip.GetTooltipData) then
		return texts
	end
	local KEYS = {
		[kinds.QuestObjective or false] = "Quest", [kinds.QuestTitle or false] = "Quest",
		[kinds.QuestPlayer or false] = "Quest", [kinds.UnitThreat or false] = "Threat",
	}
	KEYS[false] = nil
	pcall(function()
		local data = tooltip:GetTooltipData()
		for _, line in ipairs(data and data.lines or {}) do
			if line.leftText and KEYS[line.type] then
				texts[line.leftText] = KEYS[line.type]
			end
		end
	end)
	return texts
end

-- The threat line ("100% Threat"), from the game's own wording.
-- Reputation factions' names (an NPC's "Hara'ti" line), every one the game
-- knows, read once: by ID, so ones under collapsed headers count too.
local MAX_FACTION_ID = 5000
local repFactions
local function RepFactions()
	if not repFactions then
		repFactions = {}
		pcall(function()
			for id = 1, MAX_FACTION_ID do
				local name
				if C_Reputation and C_Reputation.GetFactionDataByID then
					local data = C_Reputation.GetFactionDataByID(id)
					name = data and data.name
				elseif GetFactionInfoByID then
					name = GetFactionInfoByID(id)
				end
				if type(name) == "string" and name ~= "" then
					repFactions[name] = true
				end
			end
		end)
	end
	return repFactions
end

local threatPattern
local function ThreatPattern()
	if not threatPattern then
		local format = type(THREAT_TOOLTIP) == "string" and THREAT_TOOLTIP or "%d%% Threat"
		-- (Magic characters escaped bar %, so %% stays a literal %; %d is any number.)
		local pattern = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%d", "%%d+")
		threatPattern = "^" .. pattern .. "$"
	end
	return threatPattern
end

-- The PvP line ("PvP", as the game words it; any case) and the faction lines.
local function IsFactionLine(text)
	if text == FACTION_HORDE or text == FACTION_ALLIANCE then
		return true
	end
	local plain = text:match("^%s*(.-)%s*$"):lower()
	for _, word in ipairs({ PVP or false, PVP_ENABLED or false, "PvP" }) do
		if type(word) == "string" and plain == word:lower() then
			return true
		end
	end
	return false
end

-- A class's name alone on a line ("Paladin"): the class line of a party
-- member's short tooltip, from the game's own class names.
local function IsClassName(text)
	for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE or false, LOCALIZED_CLASS_NAMES_FEMALE or false }) do
		if type(names) == "table" then
			for _, name in pairs(names) do
				if text == name then
					return true
				end
			end
		end
	end
	return false
end

-- A unit frame's own unit (party1, target...), while its tooltip is about a
-- unit or built by hand. A party member out of sight gets the game's short
-- tooltip (name, guild, class, zone, right-click hint), with no unit the
-- tooltip can give: without this, none of it was taken out (tested in videos,
-- WoW Forever 2026-11-09, in and out of fights).
local function FrameUnit(tooltip)
	local ok, unit = pcall(function()
		if tooltip.GetTooltipData then
			local data = tooltip:GetTooltipData()
			local kinds = Enum and Enum.TooltipDataType
			-- (A secret kind, as an enemy's in a dungeon: taken as a unit's.
			-- Comparing it errored, so an enemy target's hint stayed.)
			local secret = issecretvalue and (issecretvalue(data) or (data and issecretvalue(data.type)))
			if not secret and data and data.type ~= nil and kinds and data.type ~= kinds.Unit then
				return nil -- (an aura's or item's tooltip, owned by the frame)
			end
		end
		local owner = tooltip:GetOwner()
		local unit = owner and owner.unit
		if type(unit) ~= "string" or (issecretvalue and issecretvalue(unit)) then
			return nil
		end
		return unit
	end)
	return ok and unit or nil
end

-- The "<Right click for Frame Settings>" line of a unit frame's tooltip.
local function IsHintLine(text)
	local hint = type(UNIT_POPUP_RIGHT_CLICK) == "string" and UNIT_POPUP_RIGHT_CLICK or nil
	return text == hint or text == "<Right click for Frame Settings>"
end

-- An item's green click hint ("<Right Click to Read>", "<Right Click to
-- Open>", "<Shift Right Click to Socket>"), from the game's own wording;
-- else an English "<...Click...>" (not "<Made by ...>", green too).
local ITEM_HINTS = { "ITEM_READABLE", "ITEM_OPENABLE", "ITEM_SOCKETABLE", "ITEM_AZERITE_EMPOWERED_VIEWABLE",
	"ITEM_AZERITE_ESSENCES_VIEWABLE", "ITEM_ARTIFACT_VIEWABLE" }
local function IsItemHint(text)
	for _, name in ipairs(ITEM_HINTS) do
		if text == _G[name] then
			return true
		end
	end
	return text:find("^<.*[Cc]lick.*>$") ~= nil
end

-- Whether a line is in the game's green for instruction lines (the hint's).
local function IsHintColor(fs)
	local ok, green = pcall(function()
		local r, g, b = fs:GetTextColor()
		if issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then
			return false
		end
		local c = _G.GREEN_FONT_COLOR
		local gr, gg, gb = c and c.r or 0.1, c and c.g or 1, c and c.b or 0.1
		return math.abs(r - gr) < 0.03 and math.abs(g - gg) < 0.03 and math.abs(b - gb) < 0.03
	end)
	return ok and green
end

-- Whether a line's text can't be read (secret).
local function Unreadable(fs)
	local ok, secret = pcall(function()
		local text = fs:GetText()
		return issecretvalue and issecretvalue(text) or false
	end)
	return not ok or secret
end

-- The lines taken out: line number -> true. An object in the world (object
-- "object") has just its quest lines taken out, by their own row (ObjQuest);
-- an item ("item") just its green click hints, by the Hint row.
local function LinesToCut(tooltip, count, unit, object)
	local cut = {}
	local level = LEVEL or "Level"
	local creatureType, className, isPlayer, guildName
	local enemy = false -- (one you can attack: its level is LevelEnemy's)
	if unit then
		local okPlayer, player = pcall(function()
			return ns.Flag(UnitIsPlayer(unit)) or tostring(UnitGUID(unit)):find("^Player%-") ~= nil
		end)
		isPlayer = okPlayer and player
		local okEnemy, canAttack = pcall(function() return ns.Flag(UnitCanAttack("player", unit)) end)
		enemy = okEnemy and canAttack or false
		local ok, kind = pcall(UnitCreatureType, unit)
		creatureType = ok and kind or nil
		local okClass, class = pcall(UnitClass, unit)
		className = okClass and type(class) == "string" and class or nil
		local okGuild, guild = pcall(GetGuildInfo, unit)
		guildName = okGuild and type(guild) == "string" and guild ~= ""
			and not (issecretvalue and issecretvalue(guild)) and guild or nil
	end
	local questTitles, typed = QuestTitles(), TypedTexts(tooltip)
	-- (Questie's own lines, as it gives them: Support/Questie.lua.)
	local questie = ns.QuestieTooltipLines and not object and ns.QuestieTooltipLines(unit) or {}
	local inQuest = false
	for i = 2, count do
		local text = Left(i) and Left(i):GetText()
		-- A line we emptied and hid on an earlier cut, still counted: lines
		-- added after it (Questie's quest lines) would sit under a blank gap.
		local okShown, hidden = pcall(function()
			return text == nil and not ns.Flag(Left(i):IsShown())
		end)
		if okShown and hidden then
			cut[i] = true
		end
		local ok, key = pcall(function()
			if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
				return nil
			end
			if typed[text] == "Threat" or text:find(ThreatPattern()) then
				inQuest = false
				return "Threat"
			elseif typed[text] or questie[text] or questTitles[text] or questTitles[BareTitle(text)]
				-- (A quest the mob starts or ends, not in your log: Questie
				-- puts one of its own icons in front of the title.)
				or text:lower():find("addons\\questie\\icons", 1, true) then
				inQuest = true
				return "Quest"
			elseif inQuest and text:find("^%s") then
				return "Quest" -- (an objective under its quest)
			end
			inQuest = false
			if text == (CORPSE or "Corpse") then
				return "Corpse"
			elseif IsHintLine(text) then
				return "Hint" -- (before Guild: it's in <...> too)
			elseif text:find("^<.*>$") then
				return "Guild"
			elseif guildName and text:find(guildName, 1, true) then
				return "Guild" -- (a player's guild with no brackets, as on retail: "Top Opp")
			elseif text:find(level, 1, true) then
				return enemy and "LevelEnemy" or "Level"
			elseif className and isPlayer and text:find(className, 1, true) then
				return "Spec" -- (a player's "Fury Warrior")
			elseif unit and IsClassName(text) then
				return "Spec" -- (a party member's short tooltip: the class alone)
			elseif unit and IsClassName(Left(i - 1):GetText()) then
				return "Spec" -- (and the zone under the class there: "Stormwind City")
			elseif i == 2 and unit and Left(3) and IsClassName(Left(3):GetText()) then
				return "Guild" -- (the short tooltip's guild, over its class: "Requiem")
			elseif Same(text, creatureType) then
				return "Type"
			elseif IsFactionLine(text) then
				return "Faction"
			elseif RepFactions()[text] then
				return "Rep"
			elseif i == 2 and unit and not isPlayer then
				return "Guild" -- (an NPC's title with no brackets: "Ranger-General of Silvermoon")
			end
		end)
		if object == "item" then
			local okHint, hint = pcall(function()
				return type(text) == "string" and not (issecretvalue and issecretvalue(text))
					and IsItemHint(text) and IsHintColor(Left(i))
			end)
			key = okHint and hint and "Hint" or nil
		elseif object then
			key = key == "Quest" and "ObjQuest" or nil
		end
		if ok and key and Cut(key) then
			cut[i] = true
		end
	end
	-- A unit frame's hint whose text can't be read (an enemy target's tooltip
	-- in a dungeon): the last line, in the hint's green.
	local last = Left(count)
	if Cut("Hint") and not object and not cut[count] and last and Unreadable(last) and IsHintColor(last)
		and FrameUnit(tooltip) then
		cut[count] = true
	end
	-- Blank lines left at the bottom once others are cut (the game's spacer
	-- above a unit frame's right-click hint): an empty strip under the last line.
	if next(cut) then
		for i = count, 2, -1 do
			if not cut[i] then
				local okBlank, blank = pcall(function()
					local function Empty(fs)
						local t = fs and ns.Flag(fs:IsShown()) and fs:GetText()
						if issecretvalue and issecretvalue(t) then
							return false
						end
						return t == nil or t == false or (type(t) == "string" and not t:find("%S"))
					end
					return Empty(Left(i)) and Empty(Right(i))
				end)
				if not (okBlank and blank) then
					break
				end
				cut[i] = true
			end
		end
	end
	return cut
end

-- One line's text and colour, both sides (nil: unreadable).
local function Snapshot(i)
	local ok, line = pcall(function()
		local left, right = Left(i), Right(i)
		local line = { left = left:GetText(), lr = { left:GetTextColor() } }
		if right and ns.Flag(right:IsShown()) then
			line.right, line.rr = right:GetText(), { right:GetTextColor() }
		end
		return line
	end)
	if ok and line then
		-- Its row's layout too (wrap, width, justify, indent): these stay with
		-- the row, not the text, so text moved into a row laid out for another
		-- line wrapped or sat indented (Questie's quest lines, several quests).
		-- (Each read on its own, so one refused read keeps the rest. A row is
		-- held by two points: under the row above, and LEFT of the tooltip by
		-- its indent, 10 or 28 for an objective: read in game, WoW Forever
		-- 2026-11-11. The tooltip's points carry the indent.)
		local left = Left(i)
		pcall(function() line.wrap = left:CanWordWrap() end)
		pcall(function() line.width = left:GetWidth() end)
		pcall(function() line.justify = left:GetJustifyH() end)
		pcall(function()
			local points = {}
			for p = 1, left:GetNumPoints() do
				local point, relativeTo, relative, x, y = left:GetPoint(p)
				if relativeTo == GameTooltip then
					points[#points + 1] = { point, relative, x, y }
				end
			end
			line.points = points
		end)
		pcall(function() line.indent = left:GetLeft() - GameTooltip:GetLeft() end)
	end
	return ok and line or nil
end

-- Lays a row out as the moved line's own row was (Snapshot): each piece on
-- its own, so one refused call keeps the rest.
local function ApplyLayout(left, line)
	if line.wrap ~= nil then
		pcall(left.SetWordWrap, left, line.wrap)
	end
	if type(line.width) == "number" then
		pcall(left.SetWidth, left, line.width)
	end
	if line.justify then
		pcall(left.SetJustifyH, left, line.justify)
	end
	for _, p in ipairs(line.points or {}) do
		pcall(left.SetPoint, left, p[1], GameTooltip, p[2], p[3], p[4])
	end
end

-- Sizes a row to the text moved into it, as the game does for a line it
-- adds (a row's width and height read the same as its text's there: WoW
-- Forever, 2026-11-11). A row keeps the size of its last line otherwise: a
-- title moved into a two-line row left a blank gap under it, and the last
-- line spilled out of the tooltip.
local function FitRow(left, line)
	if not line.wrap then
		pcall(function()
			local width = left.GetUnboundedStringWidth and left:GetUnboundedStringWidth() or left:GetStringWidth()
			if width > 0 then
				left:SetWidth(width)
			end
		end)
	end
	pcall(function()
		local height = left:GetStringHeight()
		if height > 0 then
			left:SetHeight(height)
		end
	end)
end

-- A moved row that didn't land at its line's indent: noted in the log (a
-- few times a session), with how the row is held, to read back later.
local indentNotes = 0
local function CheckIndent(n, line)
	pcall(function()
		local left = Left(n)
		local indent = left:GetLeft() - GameTooltip:GetLeft()
		if not line.indent or math.abs(indent - line.indent) <= 1 or indentNotes >= 5 then
			return
		end
		indentNotes = indentNotes + 1
		local held = {}
		for p = 1, left:GetNumPoints() do
			local point, relativeTo, relative, x, y = left:GetPoint(p)
			held[#held + 1] = ("%s of %s %s %.1f,%.1f"):format(point,
				relativeTo and relativeTo:GetDebugName() or "-", relative, x, y)
		end
		ns.Log("tooltip", ("row %d indent %.1f, wanted %.1f | %s"):format(n, indent, line.indent,
			table.concat(held, "; ")))
	end)
end

-- The icons beside lines (a quest objective's bullet, or its tick once done):
-- textures of their own, held to their line, so they move with it, or hide
-- with it taken out. One whose line can't be read (restricted) hides.
local function MoveIcons(cut, count, newIndex)
	for k = 1, 30 do
		local icon = _G["GameTooltipTexture" .. k]
		if not icon then
			break
		end
		if ns.Flag(icon:IsShown()) then
			local ok, point, line, relative, x, y = pcall(function()
				local point, relativeTo, relative, x, y = icon:GetPoint(1)
				for i = 2, count do
					if relativeTo == Left(i) then
						return point, i, relative, x, y
					end
				end
			end)
			local new = ok and line and not cut[line] and newIndex[line]
			if new then
				if new ~= line then
					icon:ClearAllPoints()
					icon:SetPoint(point, Left(new), relative, x, y)
				end
			else
				icon:Hide()
			end
		end
	end
end

-- /cine debug tooltipparts' second reading: no lines are moved meanwhile, so
-- the rows read as the game (and other addons) laid them out.
local leaveLines = false

local function CutLines(tooltip, object)
	local okCount, count = pcall(tooltip.NumLines, tooltip)
	if leaveLines or not okCount or type(count) ~= "number" or count < 2 then
		return
	end
	local unit
	pcall(function()
		local _, u = tooltip:GetUnit()
		unit = u
	end)
	-- (No unit, or a secret one, as in instances and fights: the frame's own.)
	local okPlain, plain = pcall(function()
		return not (issecretvalue and issecretvalue(unit)) and unit ~= nil
	end)
	if not (okPlain and plain) and not object then
		unit = FrameUnit(tooltip)
	end
	local cut = LinesToCut(tooltip, count, unit, object)
	if not next(cut) then
		return
	end
	-- (Lines above the first cut stay as they are, untouched: an enemy's
	-- secret lines in a dungeon over its cut hint aren't set again.)
	local first = count
	for i in pairs(cut) do
		first = math.min(first, i)
	end
	local kept, newIndex = {}, {}
	for i = 2, count do
		if i < first then
			kept[#kept + 1] = false
			newIndex[i] = i
		elseif not cut[i] then
			local line = Snapshot(i)
			if not line then
				return -- (unreadable: leave the tooltip as it is)
			end
			kept[#kept + 1] = line
			newIndex[i] = #kept + 1
		end
	end
	pcall(function()
		for n = first, count do
			local line, left, right = kept[n - 1], Left(n), Right(n)
			if line then
				ApplyLayout(left, line)
				left:SetText(line.left)
				left:SetTextColor(line.lr[1], line.lr[2], line.lr[3])
				left:Show()
				FitRow(left, line)
				if right then
					if line.right then
						right:SetText(line.right)
						right:SetTextColor(line.rr[1], line.rr[2], line.rr[3])
						right:Show()
					else
						right:SetText(nil)
						right:Hide()
					end
				end
			else
				left:SetText(nil)
				left:Hide()
				if right then
					right:SetText(nil)
					right:Hide()
				end
			end
		end
	end)
	pcall(MoveIcons, cut, count, newIndex)
	linesCut = true
	unitLinesCut = not object
	if ns.Flag(tooltip:IsShown()) then
		pcall(tooltip.Show, tooltip) -- (sizes itself to the lines again)
		for n = first, count do
			if kept[n - 1] then
				CheckIndent(n, kept[n - 1])
			end
		end
	end
end

-- Where the client fills tooltips through its data (TooltipDataProcessor),
-- lines are taken out once the game has shown the tooltip, not as it's filled:
-- other addons' lines (Questie's) are all in by then and every row is laid
-- out. Taken out while filling, rows read as their last line left them
-- (titles indented or over a blank gap when switching between mobs: seen in
-- a video, WoW Forever 2026-11-11), and Questie, which counts the tooltip's
-- lines to tell whether its own are still there, counted ours gone and left
-- its lines out of later fills. pendingCut: the kind waiting for that show
-- ("unit", true for an object, "item"). cutting: our own Show, as CutLines
-- resizes the tooltip.
local deferCuts, pendingCut, cutting = false, nil, false
local function RunPendingCut(tooltip)
	local kind = pendingCut
	if not kind or cutting then
		return false
	end
	pendingCut = nil
	cutting = true
	pcall(CutLines, tooltip, kind ~= "unit" and kind or nil)
	cutting = false
	return true
end
local function CutWhenShown(tooltip, kind)
	if not deferCuts then
		CutLines(tooltip, kind ~= "unit" and kind or nil)
		return
	end
	pendingCut = kind
	-- (Should no show follow: on the next frame.)
	C_Timer.After(0, function() RunPendingCut(tooltip) end)
end

local LINE_PARTS = { "Guild", "Level", "LevelEnemy", "Spec", "Type", "Corpse", "Faction", "Rep", "Threat", "Quest",
	"Hint" }
local function AnyLineCut()
	for _, part in ipairs(LINE_PARTS) do
		if Cut(part) then
			return true
		end
	end
	return false
end

-- The background and border: see-through while taken out (put back once, after).
local borderHidden = false
local function UpdateBorder(tooltip)
	local slice = tooltip.NineSlice
	if not slice then
		return
	end
	if Cut("Border") then
		slice:SetAlpha(0)
		borderHidden = true
	elseif borderHidden then
		slice:SetAlpha(1)
		borderHidden = false
	end
end

-- The health bars (both names, where they're two bars), and the ones hidden: bar -> true.
local bars, hiddenBars = {}, {}

-- A bar hides as it shows, and as the tooltip moves on to another unit
-- (it stays shown then, so shows no more).
local function HideBar(bar)
	if Cut("Health") and ns.Flag(bar:IsShown()) then
		hiddenBars[bar] = true
		bar:Hide()
	end
end

-- Shown in full: the border and bars back, and the lines filled in again
-- (refilling: our own refill, not a new tooltip): the game fills the
-- tooltip again where it can, or else a unit's is set again.
local refilling = false
-- The tooltip's unit, if any (nil: none, or unreadable).
local function TooltipUnit(tooltip)
	local ok, unit = pcall(function()
		local _, unit = tooltip:GetUnit()
		if issecretvalue and issecretvalue(unit) then
			return nil
		end
		return unit
	end)
	return ok and unit or nil
end

-- Whether the tooltip's unit token is secret (retail instances, even out of
-- a fight): the game's refill of it then errors, blamed on us.
local function UnitSecret(tooltip)
	local ok, secret = pcall(function()
		local _, unit = tooltip:GetUnit()
		return issecretvalue and issecretvalue(unit) or false
	end)
	return not ok or secret
end

-- An object in the world (a quest's rune, chest or herb): no unit, and
-- owned by UIParent or the world.
local function IsWorldObject(tooltip)
	local ok, isObject = pcall(function()
		local owner = tooltip:GetOwner()
		return TooltipUnit(tooltip) == nil and (owner == nil or owner == UIParent or owner == WorldFrame)
	end)
	return ok and isObject
end

-- Whether the tooltip shows an item (in your bags, on a bar, a link).
local function IsItemTooltip(tooltip)
	local ok, item = pcall(function()
		local _, link = tooltip:GetItem()
		return link ~= nil and not (issecretvalue and issecretvalue(link))
	end)
	return ok and item
end

-- Fade in/out (tooltipFadeTime seconds, Tooltips page, with its switch
-- on): tooltips fade in as they show, cross-fade into the After column's
-- look, and fade out before Effects.lua hides one for the mouse being still
-- too long. The game hides others at once (or fades a world one out
-- itself), so those can't. A fade stops once something else takes the
-- tooltip's alpha the other way (the game's own fade out of a world
-- tooltip, as one fades in).
local fader = CreateFrame("Frame")
fader:Hide()
local fade -- { from, to, start, length, set (the alpha last set), done, kind ("in", "reveal", "out") }

local function Alpha(tooltip)
	local ok, alpha = pcall(tooltip.GetAlpha, tooltip)
	return ok and type(alpha) == "number" and not (issecretvalue and issecretvalue(alpha)) and alpha or nil
end

local function StopFade(restore)
	if fade and restore then
		GameTooltip:SetAlpha(1)
	end
	fade = nil
	fader:Hide()
end

ns.SetOnUpdate(fader, function()
	local alpha = Alpha(GameTooltip)
	local against = alpha and fade and (fade.to > fade.from and alpha < fade.set - 0.02
		or fade.to < fade.from and alpha > fade.set + 0.02)
	if not fade or not ns.Flag(GameTooltip:IsShown()) or against then
		StopFade()
		return
	end
	local t = fade.length > 0 and math.min(1, (GetTime() - fade.start) / fade.length) or 1
	fade.set = fade.from + (fade.to - fade.from) * t
	GameTooltip:SetAlpha(fade.set)
	if t >= 1 then
		local done = fade.done
		StopFade()
		if done then done() end
	end
end)

-- The fade in is the tooltip coming up at all, not each new thing in it: the
-- game hides and shows it again for every new thing hovered, so a show within
-- KEEP_UP seconds of a hide carries on from the alpha it had then (sweeping
-- the mouse across buttons doesn't flicker it).
local KEEP_UP = 0.3
local hiddenAt, hiddenAlpha = 0, 0

local function StartFade(kind, from, to, length, done)
	fade = { kind = kind, from = from, to = to, start = GetTime(), length = length, set = from, done = done }
	GameTooltip:SetAlpha(from)
	fader:Show()
end

-- Hovered long enough: the After column's parts. Lines taken out on first
-- hover are filled in again (the game fills the tooltip again where it
-- can, or else a unit's is set again; refilling: our own refill, not a new
-- tooltip), and its fill takes out the After column's; with none taken out
-- yet, they're taken out from what's there.
local function ShowLater(tooltip)
	revealed = true
	UpdateBorder(tooltip)
	if not Cut("Health") then
		for bar in pairs(hiddenBars) do
			bar:Show()
		end
		hiddenBars = {}
	end
	for _, bar in ipairs(bars) do
		HideBar(bar)
	end
	local unit = TooltipUnit(tooltip)
	-- (Not in a fight, nor for a secret unit: the game's refill then reads
	-- secret line colors or unit and errors, blamed on us; securecallfunction
	-- reports it past our pcall. The lines stay as they are.)
	if linesCut and (InCombatLockdown() or UnitSecret(tooltip)) then
		return
	end
	if linesCut then
		linesCut = false
		refilling = true
		if tooltip.RefreshData then
			pcall(tooltip.RefreshData, tooltip)
		elseif unit then
			pcall(tooltip.SetUnit, tooltip, unit)
		end
		refilling = false
		RunPendingCut(tooltip)
	elseif unit or FrameUnit(tooltip) then
		CutLines(tooltip)
	elseif IsWorldObject(tooltip) then
		CutLines(tooltip, true)
	elseif IsItemTooltip(tooltip) then
		CutLines(tooltip, "item")
	end
end

-- Whether showing in full changes anything on this tooltip: lines filled in
-- or taken out, the border or a health bar. A tooltip it leaves as it is
-- (a settings button's tip) isn't faded out and in again for nothing: that
-- looked like the tooltip blinking a few seconds into hovering.
local function RevealChanges(tooltip)
	if linesCut then
		return true
	end
	revealed = true -- (Cut reads the After column)
	local border, health = Cut("Border"), Cut("Health")
	local lines = ((TooltipUnit(tooltip) or FrameUnit(tooltip)) and AnyLineCut())
		or (IsWorldObject(tooltip) and Cut("ObjQuest"))
		or (IsItemTooltip(tooltip) and Cut("Hint"))
	revealed = false
	if lines or (tooltip.NineSlice and border ~= borderHidden) or (not health and next(hiddenBars)) then
		return true
	end
	if health then
		for _, bar in ipairs(bars) do
			if ns.Flag(bar:IsShown()) then
				return true
			end
		end
	end
	return false
end

-- With Fade in/out, the whole tooltip fades out, takes on the After look
-- while it can't be seen (the lines move and the box resizes then), and
-- fades back in: half the fade time each way.
local function Reveal(tooltip)
	if revealed or not ns.Flag(tooltip:IsShown()) or (fade and (fade.kind == "reveal" or fade.kind == "out")) then
		return -- (already on its way, or fading out to hide)
	end
	local time = FadeTime()
	if not time or not RevealChanges(tooltip) then
		ShowLater(tooltip)
		return
	end
	StartFade("reveal", Alpha(tooltip) or 1, 0, time / 2, function()
		if ns.Flag(tooltip:IsShown()) then
			ShowLater(tooltip)
			StartFade("in", 0, 1, time / 2)
		end
	end)
end

-- The countdown to showing in full, from each new tooltip or unit.
local fullTimer
local function StartCountdown(tooltip)
	if fullTimer then
		fullTimer:Cancel()
		fullTimer = nil
	end
	-- (Page switched off: the After column changes nothing, so no countdown.)
	local db = ns.db
	local after = db and db.enabled and db.handleTooltips and db.tooltipFullAfter or 0
	if after > 0 then
		fullTimer = C_Timer.NewTimer(after, function()
			fullTimer = nil
			Reveal(tooltip)
		end)
	end
end

-- A hide followed at once by a show from the same owner is the game setting
-- the tooltip again, not a new one: a unit frame does it every moment while
-- hovered (SetOwner hides it, SetUnit fills it again). That keeps its look
-- (shown in full stays in full, the countdown runs on) instead of starting
-- again, taken out. pendingHide: hidden, not yet known which.
local shownName
local pendingHide, hiddenOwner = false, nil
-- The last hide was the game setting it again (for the show that follows).
local carriedOn = false
local function Owner(tooltip)
	local ok, owner = pcall(tooltip.GetOwner, tooltip)
	return ok and owner or nil
end
local function StartsAgain(tooltip)
	if not pendingHide then
		return false
	end
	pendingHide = false
	local owner = Owner(tooltip)
	carriedOn = owner ~= nil and owner == hiddenOwner and GetTime() - hiddenAt <= KEEP_UP
	if carriedOn then
		return false
	end
	if fullTimer then
		fullTimer:Cancel()
		fullTimer = nil
	end
	revealed, linesCut, shownName = false, false, nil
	hiddenBars = {}
	return true
end

-- A new unit in the tooltip (its name changed) starts again, taken out.
local function OnUnitTooltip(tooltip)
	if tooltip ~= GameTooltip then
		return
	end
	StartsAgain(tooltip)
	local name = Left(1) and Left(1):GetText()
	if not refilling and not Same(name, shownName) then
		shownName = name
		if fade and fade.kind == "reveal" then
			StopFade(true) -- (a new unit: its own first look)
		end
		if revealed then
			revealed = false
			UpdateBorder(tooltip)
		end
		StartCountdown(tooltip)
	end
	for _, bar in ipairs(bars) do
		HideBar(bar)
	end
	if AnyLineCut() then
		CutWhenShown(tooltip, "unit")
	end
end

-- An object in the world (a quest's rune, chest or herb): its quest lines.
-- World tooltips have no unit and are owned by UIParent or the world.
local function OnObjectTooltip(tooltip)
	if tooltip == GameTooltip and Cut("ObjQuest") and IsWorldObject(tooltip) then
		CutWhenShown(tooltip, true)
	end
end

-- An item: its green click hints ("<Right Click to Read>"), by the Hint row.
local function OnItemTooltip(tooltip)
	if tooltip == GameTooltip and Cut("Hint") and IsItemTooltip(tooltip) then
		CutWhenShown(tooltip, "item")
	end
end

-- Fades the tooltip out and then runs done (Effects.lua's hide). False with
-- fading off: the caller hides it now.
function ns.TooltipFadeOut(done)
	local time = FadeTime()
	if not time then
		return false
	end
	if not (fade and fade.kind == "out") then
		StartFade("out", Alpha(GameTooltip) or 1, 0, time, done)
	end
	return true
end

-- A fade out that's no longer wanted (the mouse moved): the tooltip back.
function ns.TooltipFadeCancel()
	if fade and fade.kind == "out" then
		StopFade(true)
	end
end

-- /cine debug tooltipparts: the next tooltip's shown parts (name, kind,
-- size, where) and its lines' text, printed a moment after it shows.
local listParts = false
function ns.TooltipPartsDebug()
	listParts = true
	ns.Print("Mouse over something: its tooltip's parts print in a moment.")
end

-- Each piece read on its own, so one restricted call doesn't lose the rest.
local function Describe(part)
	local function Try(f)
		local ok, text = pcall(f)
		return ok and text or "?"
	end
	return ("%s (%s) %s at %s, %s"):format(
		Try(function() return part:GetDebugName() end),
		Try(function() return part:GetObjectType() end),
		Try(function() return ("%.0fx%.0f"):format(part:GetSize()) end),
		Try(function()
			local point, relativeTo, _, x, y = part:GetPoint(1)
			return ("%s of %s %.0f,%.0f"):format(point, relativeTo and relativeTo:GetDebugName() or "-", x, y)
		end),
		Try(function() return part.GetAtlas and part:GetAtlas() or part.GetTexture and part:GetTexture() end))
end

-- Each line's text and where its row sits (secret: "?"): its anchor, indent
-- and wrap stay with the row, not the text, when CutLines moves texts up.
local function ListLines(tooltip, title)
	ns.Print(title)
	pcall(function()
		for i = 1, tooltip:NumLines() do
			local fs = Left(i)
			local text = fs and fs:GetText()
			local plain = type(text) == "string" and not (issecretvalue and issecretvalue(text))
			local okColor, color = pcall(function()
				local r, g, b = fs:GetTextColor()
				return ("%.2f %.2f %.2f"):format(r, g, b)
			end)
			local function Try(f)
				local ok, value = pcall(f)
				return ok and tostring(value) or "?"
			end
			local right = Right(i)
			local place = ("%s of %s x %s y %s (%s points) | left %s | shown %s wrap %s justify %s | w %s text w %s"
				.. " h %s text h %s rows %s | right shown %s"):format(
				Try(function() return (fs:GetPoint(1)) end),
				Try(function() return select(2, fs:GetPoint(1)):GetDebugName() end),
				Try(function() return ("%.1f"):format(select(4, fs:GetPoint(1))) end),
				Try(function() return ("%.1f"):format(select(5, fs:GetPoint(1))) end),
				Try(function() return fs:GetNumPoints() end),
				Try(function() return ("%.1f"):format(fs:GetLeft() - tooltip:GetLeft()) end),
				Try(function() return ns.Flag(fs:IsShown()) end), Try(function() return fs:CanWordWrap() end),
				Try(function() return fs:GetJustifyH() end),
				Try(function() return ("%.1f"):format(fs:GetWidth()) end),
				Try(function() return ("%.1f"):format(fs:GetStringWidth()) end),
				Try(function() return ("%.1f"):format(fs:GetHeight()) end),
				Try(function() return ("%.1f"):format(fs:GetStringHeight()) end),
				Try(function() return fs:GetNumLines() end),
				Try(function() return right and ns.Flag(right:IsShown()) end))
			ns.Print(("Line %d: %s (color %s%s) %s"):format(i,
				plain and ("%q"):format(text) or (Unreadable(fs) and "secret" or "?"),
				okColor and color or "secret", IsHintColor(fs) and ", hint green" or "", place))
		end
		ns.Print(("Lines cut %s (a unit's %s) | tooltip w %.0f h %.0f"):format(tostring(linesCut),
			tostring(unitLinesCut), tooltip:GetWidth(), tooltip:GetHeight()))
	end)
end

local function ListParts(tooltip)
	local function Walk(frame, depth)
		for _, region in ipairs({ frame:GetRegions() }) do
			if ns.Flag(region:IsShown()) and region:GetObjectType() ~= "FontString" then
				ns.Print(("%s%s"):format(("  "):rep(depth), Describe(region)))
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			if ns.Flag(child:IsShown()) then
				ns.Print(("%s%s"):format(("  "):rep(depth), Describe(child)))
				if depth < 2 then
					Walk(child, depth + 1)
				end
			end
		end
	end
	pcall(Walk, tooltip, 0)
	-- Then each line's text, for a line the parts grid misses.
	ListLines(tooltip, "Lines as shown:")
	-- And once more with the tooltip filled again and nothing moved: the rows
	-- as the game and other addons (Questie) lay them out, to compare. (Not in
	-- a fight, nor for a secret unit: the game's refill errors then.)
	if tooltip.RefreshData and not InCombatLockdown() and not UnitSecret(tooltip) then
		leaveLines, refilling = true, true
		pcall(tooltip.RefreshData, tooltip)
		refilling = false
		C_Timer.After(0.2, function()
			ListLines(tooltip, "Lines filled again, nothing moved:")
			leaveLines = false
			ns.Print("Done.")
		end)
	else
		ns.Print("Done (no second reading: in a fight, or the tooltip can't be filled again).")
	end
	-- And what the hint's taking out goes by: the unit, the frame's, the data kind.
	pcall(function()
		local okData, kind = pcall(function()
			local data = tooltip.GetTooltipData and tooltip:GetTooltipData()
			if issecretvalue and (issecretvalue(data) or (data and issecretvalue(data.type))) then
				return "secret"
			end
			return data and tostring(data.type) or "none"
		end)
		ns.Print(("Unit %s | frame's unit %s | data kind %s | secret unit %s | hint cut %s"):format(
			tostring(TooltipUnit(tooltip)), tostring(FrameUnit(tooltip)), okData and kind or "error",
			tostring(UnitSecret(tooltip)), tostring(Cut("Hint"))))
	end)
end

function ns.HookTooltipParts()
	-- Unit lines (and objects'): after every fill (refreshes too) where the
	-- client says so, else as the tooltip's set or shows.
	local processor = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum
		and Enum.TooltipDataType
	if processor then
		deferCuts = true
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
		TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes or "ALL", function(tooltip, data)
			if not (data and data.type == Enum.TooltipDataType.Unit) then
				if tooltip == GameTooltip then
					pendingCut = nil -- (filled with something else since)
				end
				OnObjectTooltip(tooltip)
				OnItemTooltip(tooltip)
			end
		end)
	elseif GameTooltip:HasScript("OnTooltipSetUnit") then
		-- (Classic: the game fills a mouseover unit's tooltip itself, past the
		-- Lua SetUnit, so only this script hears it.)
		GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
	else
		hooksecurefunc(GameTooltip, "SetUnit", OnUnitTooltip)
	end
	-- Lines the game adds after a unit's tooltip is filled (a unit frame's
	-- right-click hint, a PvP line): taken out as it shows the tooltip again
	-- to fit them. A tooltip
	-- already cut counts too, with no readable unit (a mob in a fight on
	-- Forever): lines added under our emptied last line (Questie's quest
	-- lines) sat under a blank gap until this pass took it out.
	hooksecurefunc(GameTooltip, "Show", function(tooltip)
		if cutting or RunPendingCut(tooltip) or refilling or not AnyLineCut()
			or not ((linesCut and unitLinesCut) or TooltipUnit(tooltip) or FrameUnit(tooltip)) then
			return
		end
		cutting = true
		pcall(CutLines, tooltip)
		cutting = false
	end)
	GameTooltip:HookScript("OnShow", function(tooltip)
		if refilling then
			return
		end
		-- (A unit's lines are cut before it shows: linesCut stays as it is.
		-- The game setting it again keeps its look and countdown.)
		StartsAgain(tooltip)
		local again = not carriedOn
		carriedOn = false
		if again then
			revealed = false
			StartCountdown(tooltip)
		end
		UpdateBorder(tooltip)
		if FadeTime() and tooltip == GameTooltip then
			local from = GetTime() - hiddenAt <= KEEP_UP and hiddenAlpha or 0
			StartFade("in", from, 1, FadeTime() * (1 - from))
		elseif fade then
			StopFade(true)
		end
		if not processor then
			OnObjectTooltip(tooltip)
			OnItemTooltip(tooltip)
		end
		if listParts then
			listParts = false
			C_Timer.After(0.3, function() ListParts(tooltip) end)
		end
	end)
	GameTooltip:HookScript("OnHide", function(tooltip)
		-- (Cleared on the next show, unless that's the game setting it again.
		-- A countdown that ends while it's hidden reveals nothing.)
		pendingHide, hiddenOwner = true, Owner(tooltip)
		pendingCut = nil
		hiddenAt, hiddenAlpha = GetTime(), Alpha(GameTooltip) or (fade and fade.set) or 1
		StopFade(true)
	end)
	-- The health bar hides each time it shows.
	for _, bar in ipairs({ GameTooltipStatusBar or false, GameTooltip.StatusBar or false }) do
		if bar and bar ~= bars[1] then
			bars[#bars + 1] = bar
			bar:HookScript("OnShow", HideBar)
		end
	end
end
