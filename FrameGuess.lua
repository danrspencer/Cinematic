-- Cinematic: the frame guesser (/cine debug guess). Looks over the shown
-- frames for other addons' ones that nothing fades, says which addon made
-- each (the game tells, for named frames: an addon's CreateFrame taints the
-- global) and guesses which Standard Frames row it would follow: the game
-- frame it sits on top of, while that one is hidden (whole-UI addons swap
-- the game's frames for their own in the same spot), or else words in its
-- name. All of it goes in the saved log, for writing support (Support/).
--
-- Unnamed frames have no global to ask about: whose each is comes from where
-- it was made (below) or from the fields written on it.
local ADDON_NAME, ns = ...

-- Who made each frame put straight on UIParent: the first addon on the call
-- stack that isn't the game's (Blizzard_), or "game". Frames made before this
-- file loads are missed (it's early in the .toc, so Cinematic's own are all
-- caught), and so are ones made on nothing and moved onto UIParent later.
-- One comparison per frame made; only those are looked at. (For named ones
-- the game also says who wrote the global, but that can name another addon:
-- whichever's code the call ran under, a library's first loader.)
local madeBy = setmetatable({}, { __mode = "k" })
local GAME = "game"

local function StackAddon(stack)
	for line in stack:gmatch("[^\n]+") do
		if not line:find("FrameGuess.lua", 1, true) then
			local addon = line:match("AddOns[/\\]([^/\\]+)[/\\]")
			if addon and not addon:find("^Blizzard_") then
				return addon
			end
		end
	end
	return GAME
end

-- The unnamed ones already there: the game's, or an addon's loaded before
-- this one (folder names before Cinematic's, and their libraries).
local before = setmetatable({}, { __mode = "k" })
for _, frame in ipairs({ UIParent:GetChildren() }) do
	if not (frame.IsForbidden and frame:IsForbidden()) and not frame:GetName() then
		before[frame] = true
	end
end

-- (The hook isn't handed the new frame: its global, or UIParent's newest child.)
hooksecurefunc("CreateFrame", function(_, name, parent)
	if parent ~= nil and parent == UIParent then
		local frame
		if type(name) == "string" then
			frame = _G[name]
		else
			local count = UIParent:GetNumChildren()
			frame = count > 0 and select(count, UIParent:GetChildren())
		end
		if type(frame) == "table" then
			madeBy[frame] = StackAddon(debugstack(2, 8, 0) or "")
		end
	end
end)

-- Words in a frame's name, by the row they point to: the first that's in
-- the name wins, so longer words go before the ones inside them.
local NAME_WORDS = {
	{ "targettarget", "tot" }, { "targetoftarget", "tot" }, { "focustarget", "focustot" },
	{ "player", "player" }, { "target", "target" }, { "focus", "focus" },
	{ "petbar", "pet" }, { "pet", "petframe" }, { "party", "party" }, { "raid", "raidplayers" },
	{ "castbar", "castbar" }, { "debuff", "buffs" }, { "buff", "buffs" }, { "aura", "buffs" },
	{ "minimap", "minimap" }, { "chat", "chat" },
	{ "objective", "quests" }, { "quest", "quests" }, { "tracker", "quests" },
	{ "experience", "xp" }, { "xpbar", "xp" }, { "reputation", "xp" },
	{ "micro", "micro" }, { "bag", "bags" }, { "stance", "stance" }, { "totem", "totems" },
	{ "swing", "swing" }, { "cooldown", "cooldowns" }, { "meter", "meters" },
	{ "actionbar", "mainbar (or another bar)" }, { "bar", "a bar row?" },
}

-- Shown frames this big are holders: what's just inside them is looked at.
local HOLDER_SHARE = 0.5
-- On top of a hidden game frame: overlapping this much of the smaller one.
local SPOT_SHARE = 0.5
local MAX_UNNAMED = 15 -- unnamed frames listed (the rest counted)

local function IsForbidden(frame)
	return frame.IsForbidden and frame:IsForbidden()
end

local function Plain(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

-- Whether the game made the global, and if not, the addon that did.
local function GlobalSource(name)
	if type(issecurevariable) ~= "function" then
		return false
	end
	local ok, secure, source = pcall(issecurevariable, name)
	if not ok then
		return false
	end
	return secure == true, type(source) == "string" and source or nil
end

-- The loaded addons' folder names (not the game's), longest first. Looked
-- up again after a few seconds (addons load on demand).
local LIST_AGE = 5
local folders, foldersAt = {}, nil
local function LoadedFolders()
	if not foldersAt or GetTime() - foldersAt > LIST_AGE then
		foldersAt = GetTime()
		wipe(folders)
		local count = C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or GetNumAddOns and GetNumAddOns() or 0
		local info = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
		for i = 1, type(count) == "number" and count or 0 do
			local folder = info and info(i)
			if type(folder) == "string" and ns.AddOnLoaded(folder) and not folder:find("^Blizzard_") then
				folders[#folders + 1] = folder
			end
		end
		table.sort(folders, function(a, b) return #a > #b end)
	end
	return folders
end

-- The addon a frame's named after ("SilverDragonPopupButton"), or nil.
local function NamedAfter(name)
	for _, folder in ipairs(LoadedFolders()) do
		-- (Not a longer word: "Details" names DetailsBaseFrame1, not "Detailsome".
		-- Not a short name either: too likely by chance.)
		if #folder >= 4 and name:sub(1, #folder) == folder and not name:sub(#folder + 1, #folder + 1):find("%l") then
			return folder
		end
	end
	return nil
end

-- Whose a named frame is: who made it, else the addon it's named after,
-- else who wrote its global. GAME for the game's; nil if none tells. (Made
-- by the game only counts if its global says so too: a long file path can
-- be cut short on the call stack, leaving no addon to read there.)
local function NamedOwner(frame, name)
	local maker = madeBy[frame]
	if maker and maker ~= GAME then
		return maker, "made by it"
	end
	local game, source = GlobalSource(name)
	if game then
		return GAME, "the game's global"
	end
	local after = NamedAfter(name)
	if after then
		return after, "named after it"
	end
	return source, "wrote its global"
end

-- left, bottom, width, height in UIParent's units, or nil.
local function Rect(frame)
	local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
	if not (ok and Plain(left) and Plain(bottom) and Plain(width) and Plain(height)) then
		return nil
	end
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	if not Plain(scale) then
		return nil
	end
	return left * scale, bottom * scale, width * scale, height * scale
end

-- A holder: an addon's frame covering most of the screen that its other
-- frames sit in (ElvUI's ElvUIParent). Never offered on its own: fading it
-- would fade all that addon's frames as one, and what's inside is looked at.
local function IsBigHolder(frame)
	local _, _, width, height = Rect(frame)
	return width ~= nil and width * height > UIParent:GetWidth() * UIParent:GetHeight() * HOLDER_SHARE
end

-- How much of the smaller of two rects the other covers (0 to 1).
local function Overlap(a, b)
	local across = math.min(a[1] + a[3], b[1] + b[3]) - math.max(a[1], b[1])
	local up = math.min(a[2] + a[4], b[2] + b[4]) - math.max(a[2], b[2])
	local smaller = math.min(a[3] * a[4], b[3] * b[4])
	if across <= 0 or up <= 0 or smaller <= 0 then
		return 0
	end
	return across * up / smaller
end

-- The game's frames on the Standard Frames rows that aren't showing (and
-- aren't faded by us): the spots an addon's frame may have taken.
local function HiddenGameFrames()
	local list = {}
	for _, row in ipairs(ns.COMBAT_SHOW) do
		for _, name in ipairs(row.frames or {}) do
			local frame = _G[name]
			if type(frame) == "table" and frame.GetRect and not IsForbidden(frame) and GlobalSource(name)
				and not ns.IsFaded(frame) then
				local alpha = frame:GetEffectiveAlpha()
				local hidden = not ns.Flag(frame:IsVisible()) or (Plain(alpha) and alpha < 0.05)
				local left, bottom, width, height = Rect(frame)
				if hidden and left and width > 0 and height > 0 then
					list[#list + 1] = { row = row.key, name = name, rect = { left, bottom, width, height } }
				end
			end
		end
	end
	return list
end

local function NameGuess(name)
	local lower = name:lower()
	for _, word in ipairs(NAME_WORDS) do
		if lower:find(word[1], 1, true) then
			return word[2], word[1]
		end
	end
	return nil
end

-- The row a frame would follow, and why.
local function RowGuess(name, rect, hiddenGame)
	local best, bestShare = nil, SPOT_SHARE
	for _, spot in ipairs(hiddenGame) do
		local share = rect and Overlap(rect, spot.rect) or 0
		if share >= bestShare then
			best, bestShare = spot, share
		end
	end
	if best then
		return best.row, ("on hidden %s (%d%%)"):format(best.name, bestShare * 100 + 0.5)
	end
	local row, word = NameGuess(name)
	if row then
		return row, ("name has \"%s\""):format(word)
	end
	return "own row", "no clue"
end

-- The first named frame a few levels into an unnamed one, with its addon:
-- a hint at whose it is.
local function NamedInside(frame, depth)
	for _, child in ipairs({ frame:GetChildren() }) do
		if not IsForbidden(child) then
			local name = child:GetName()
			if name then
				local game, source = GlobalSource(name)
				if not game then
					return name, source
				end
			elseif depth > 0 then
				local found, source = NamedInside(child, depth - 1)
				if found then
					return found, source
				end
			end
		end
	end
	return nil
end

-- Whose an unnamed frame is, and how that's known: who made it, or else the
-- addon that wrote most of the fields on it (the game's own writes don't
-- taint them; ours on others' frames, cinematic..., are left out). nil if
-- neither tells.
local MAX_FIELDS = 60
local function UnnamedOwner(frame)
	local maker = madeBy[frame]
	if maker then
		return maker, "made by it"
	end
	if type(issecurevariable) ~= "function" then
		return nil
	end
	local counts, looked, best = {}, 0, nil
	for key in pairs(frame) do
		looked = looked + 1
		if looked > MAX_FIELDS then
			break
		end
		if type(key) == "string" and not key:find("^cinematic") then
			local ok, secure, source = pcall(issecurevariable, frame, key)
			if ok and not secure and type(source) == "string" then
				counts[source] = (counts[source] or 0) + 1
				if not best or counts[source] > counts[best] then
					best = source
				end
			end
		end
	end
	if best then
		return best, ("wrote %d of its fields"):format(counts[best])
	end
	return nil
end

-- Whether a supported addon's row takes the frame (Support/): one left
-- alone there (Always ticked) isn't a frame nothing fades.
local function Covered(frame, name)
	for _, known in ipairs(ns.ADDON_FRAMES) do
		for _, listed in ipairs(known.names or {}) do
			if listed == name then
				return true
			end
		end
		if name then
			for _, pattern in ipairs(known.patterns or {}) do
				if name:find(pattern) then
					return true
				end
			end
		elseif known.match then
			local ok, yes = pcall(known.match, frame)
			if ok and yes then
				return true
			end
		end
	end
	return false
end

-- Whether a frame draws anything: a shown texture or text in it, or in a
-- frame a few levels in. Anchors and movers (DetailsTooltipAnchor: where an
-- addon puts its tooltips) draw nothing, so there's nothing to fade.
-- Frames with too many parts count as drawing: unpacking thousands of them
-- overflows the game's stack (a client crash pcall can't catch).
local MAX_PARTS = 100
local function Parts(frame, count, method)
	local ok, n = pcall(frame[count], frame)
	if not ok or type(n) ~= "number" then
		return nil
	end
	if n > MAX_PARTS then
		return false
	end
	local list = { pcall(frame[method], frame) }
	return table.remove(list, 1) and list or nil
end
local function Draws(frame, depth)
	local regions = Parts(frame, "GetNumRegions", "GetRegions")
	if regions == false then
		return true
	end
	for _, region in ipairs(regions or {}) do
		if not IsForbidden(region) and ns.Flag(region:IsShown()) then
			local kind = region:GetObjectType()
			if kind == "Texture" then
				return true
			elseif kind == "FontString" then
				local text = region:GetText()
				if text == nil or (issecretvalue and issecretvalue(text)) or text ~= "" then
					return true
				end
			end
		end
	end
	if depth > 0 then
		local children = Parts(frame, "GetNumChildren", "GetChildren")
		if children == false then
			return true
		end
		for _, child in ipairs(children or {}) do
			if not IsForbidden(child) and ns.Flag(child:IsShown()) and Draws(child, depth - 1) then
				return true
			end
		end
	end
	return false
end

-- A window by its name (an addon's own, not on the game's lists of them):
-- its options, config or settings, or one called a window or dialog. Fading
-- one you're using leaves it invisible, still taking clicks.
local WINDOW_WORDS = { "window%d*$", "options", "config", "settings", "dialog" }
local function NamedLikeWindow(name)
	local lower = name and name:lower()
	if not lower then
		return false
	end
	for _, word in ipairs(WINDOW_WORDS) do
		if lower:find(word) then
			return true
		end
	end
	return false
end

-- Whether a frame in the dialog or fullscreen strata is an addon's part of
-- the screen, not a window: named by an addon we've no support for (those
-- have their rows), and not named like a window. (RoC UI draws its player
-- panel and portrait there.)
function ns.IsAddonDialogFrame(name)
	local game, source = GlobalSource(name)
	return not game and source ~= nil and not ns.IsSupportedAddon(source) and not NamedLikeWindow(name)
end

-- Other addons' shown frames that nothing fades, by addon: byAddon[addon] =
-- { frames = { { name (nil: unnamed), row, why, text }... } }, order (the
-- addons as found), and what was passed over, for the report.
-- (wantText: each frame's line for the log, GuessFrames; the background
-- look doesn't use them, and making them was much of its work. Run inside
-- the background look's coroutine, it yields every few top-level frames.)
local findThread
local COLLECT_SLICE = 20 -- top-level frames looked at between yields
local NAMED_SLICE = 150 -- named frames looked at between yields (FindNamedFrames)
local GLOBALS_SLICE = 4000 -- globals gone over between yields (FindNamedFrames)
local function Collect(wantText)
	local screen = UIParent:GetWidth() * UIParent:GetHeight()
	local hiddenGame = HiddenGameFrames()
	local byAddon, order = {}, {}
	local unnamed, unnamedCount, windows, own, covered, empty = {}, 0, 0, 0, 0, 0

	local function Consider(frame, depth, holder)
		-- (What's in a faded frame fades with it.)
		if IsForbidden(frame) or ns.IsFaded(frame) or not ns.Flag(frame:IsVisible()) or frame == ns.letterbox then
			return
		end
		local name = frame:GetName()
		local left, bottom, width, height = Rect(frame)
		local rect = left and { left, bottom, width, height } or nil
		local area = rect and width * height or 0
		local big = area > screen * HOLDER_SHARE
		local source, how
		if name then
			source, how = NamedOwner(frame, name)
		else
			source, how = UnnamedOwner(frame)
		end
		if source == ADDON_NAME then
			own = own + 1
			return
		end
		-- What's inside a holder (screen-sized, unsized, or unnamed and no
		-- one's known) is looked at too.
		if depth == 0 and (big or area <= 0 or not source) then
			for _, child in ipairs({ frame:GetChildren() }) do
				Consider(child, 1, name or frame:GetDebugName())
			end
		end
		if source == GAME or (name and not source) or area <= 0 then
			return
		elseif not source then
			if depth == 0 then
				unnamedCount = unnamedCount + 1
				if wantText and #unnamed < MAX_UNNAMED then
					local inside, insideSource = NamedInside(frame, 2)
					unnamed[#unnamed + 1] = ("  %s %s %dx%d at %d,%d strata=%s holds %s%s"):format(
						frame:GetDebugName(), frame:GetObjectType(), width, height, left, bottom,
						frame:GetFrameStrata(), inside and ("%s (%s)"):format(inside, insideSource or "?")
						or "nothing named", before[frame] and ", made before Cinematic loaded (the game's " ..
						"or an earlier addon's)" or "")
				end
			end
			return
		end
		local status = big and "a holder: what's inside is listed too" or nil
		if name and ns.db.ignoredFrames[name] then
			status = "you keep it shown"
		elseif ns.IsWindow(frame, name) or NamedLikeWindow(name) then
			windows = windows + 1
			return
		elseif Covered(frame, name) then
			covered = covered + 1
			return
		elseif not Draws(frame, 2) then
			empty = empty + 1
			return
		end
		local entry = byAddon[source]
		if not entry then
			entry = { frames = {} }
			byAddon[source] = entry
			order[#order + 1] = source
		end
		local row, why = RowGuess(name or "", rect, hiddenGame)
		local alpha = frame:GetAlpha()
		entry.frames[#entry.frames + 1] = {
			name = name, row = row, why = why, kept = status == "you keep it shown", top = depth == 0, holder = big,
			text = wantText and ("  %s %s %dx%d at %d,%d strata=%s alpha=%s mouse=%s%s -> %s (%s)%s")
				:format(name or ("(unnamed: %s) %s"):format(how, frame:GetDebugName()), frame:GetObjectType(),
				width, height, left, bottom, frame:GetFrameStrata(),
				Plain(alpha) and ("%.2f"):format(alpha) or "secret", tostring(ns.Flag(frame:IsMouseEnabled())),
				holder and (" in " .. holder) or "", row, why, status and (", " .. status) or ""),
		}
	end
	local inThread = findThread ~= nil and coroutine.running() == findThread
	for i, frame in ipairs({ UIParent:GetChildren() }) do
		Consider(frame, 0)
		if inThread and i % COLLECT_SLICE == 0 then coroutine.yield() end
	end
	return {
		byAddon = byAddon, order = order, unnamed = unnamed, unnamedCount = unnamedCount, windows = windows,
		own = own, covered = covered, empty = empty, hiddenGame = hiddenGame,
	}
end

function ns.GuessFrames()
	local function Line(text)
		ns.Log("guess", text)
	end
	local build = GetBuildInfo and select(4, GetBuildInfo()) or "?"
	Line(("client %s (%s), %s, %s, %s"):format(tostring(build),
		ns.isRetail and (ns.isClassicEra and "Classic Era" or "retail/Forever") or "classic",
		ns.lastCinematic and "in CineMode (rows' game frames faded by us aren't spots)" or "not in CineMode",
		InCombatLockdown() and "in combat" or "out of combat", IsInRaid() and "in a raid"
			or IsInGroup() and "in a group" or "solo"))
	local found = Collect(true)
	local byAddon, order, unnamed, unnamedCount = found.byAddon, found.order, found.unnamed, found.unnamedCount
	local windows, own, hiddenGame = found.windows, found.own, found.hiddenGame
	local covered, empty = found.covered, found.empty

	table.sort(order)
	local summary = {}
	for _, source in ipairs(order) do
		local entry = byAddon[source]
		local supported = ns.IsSupportedAddon(source)
		Line(("%s%s: %d frame(s)"):format(source, supported and " (supported, so these were missed)" or "",
			#entry.frames))
		for _, item in ipairs(entry.frames) do
			Line(item.text)
		end
		summary[#summary + 1] = ("%s %d"):format(source, #entry.frames)
	end
	Line(("unnamed shown frames on the screen, not faded, whose no one can tell: %d"):format(unnamedCount))
	for _, text in ipairs(unnamed) do
		Line(text)
	end
	if unnamedCount > #unnamed then
		Line(("  ...and %d more"):format(unnamedCount - #unnamed))
	end
	local spots = {}
	for _, spot in ipairs(hiddenGame) do
		spots[#spots + 1] = spot.name
	end
	local new = ns.NewAddons()
	Line(("background looks (%s): still for %s"):format(ns.db.smartFindBackground and "on" or "off",
		#new > 0 and table.concat(new, ", ") or "none: every loaded addon has had its looks"))
	Line(("hidden game frames an addon may stand in for: %s"):format(#spots > 0 and table.concat(spots, ", ")
		or "none"))
	Line(("skipped: %d window(s), %d of Cinematic's own, %d a supported addon's row takes (left alone there), "
		.. "%d drawing nothing (anchors)"):format(windows, own, covered, empty))

	ns.Print(("frame guess: %d addon(s) with frames nothing fades%s"):format(#order,
		#order > 0 and (": " .. table.concat(summary, ", ")) or ""))
	ns.Print(("frame guess: %d unnamed, %d hidden game frame(s) as spots. Every frame and its guess is in the " ..
		"saved log (/cine log, or /reload to save it)."):format(unnamedCount, #spots))
end

-- Found frames (the Advanced Frames page) ------------------------------------

-- db.foundFrames[name] = { addon, follow, dismissed, count }: frames the Find
-- frames tab lists, each with Add (then it's an added frame, db.extraFrames,
-- faded by name like those, on the Loaded tab). An addon's unnamed
-- frames on UIParent are one row of their own, "@<addon>" (count: how many
-- were seen). follow: the Standard Frames row a found frame takes its ticks
-- from until it has its own (ns.ROW_FALLBACK), when there was a guess.
local UNNAMED = "@"
ns.UNNAMED_PREFIX = UNNAMED

local rowKeys -- (the Standard Frames rows' keys, made when first needed)
local function IsRowKey(key)
	if not rowKeys then
		rowKeys = {}
		for _, item in ipairs(ns.COMBAT_SHOW) do
			rowKeys[item.key] = true
		end
	end
	return key ~= nil and rowKeys[key] or false
end

local function Follow(name, row)
	if IsRowKey(row) then
		ns.ROW_FALLBACK["extra:" .. name] = row
	end
end

-- A Standard Frames row's name on the page, or nil.
function ns.RowLabel(key)
	for _, item in ipairs(ns.COMBAT_SHOW) do
		if item.key == key then
			return item.label
		end
	end
	return nil
end

-- Add on the Find frames tab: an added frame from then on, faded,
-- with the Default row's settings as they are now, Always too. (Changing that
-- row later leaves it be: Copy to all is for that.)
function ns.AdoptFoundFrame(name)
	ns.db.extraFrames[name] = true
	ns.ApplyExtraDefault(name, true)
	ns.BuildManagedList()
end

local MAX_PER_ADDON = 20 -- frames listed for one addon, at most

-- A frame you picked (the search, Hover Find): onto the list as Smart Find's
-- are, with its addon and the row it'd follow. picked: kept on the list
-- whatever the checks below say (you chose it). Whether it could be listed.
function ns.NoteFoundFrame(name)
	local db, frame = ns.db, _G[name]
	if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" or IsForbidden(frame) then
		return false
	end
	local known = db.foundFrames[name]
	if not known then
		local left, bottom, width, height = Rect(frame)
		local row = RowGuess(name, left and { left, bottom, width, height }, HiddenGameFrames())
		local addon = NamedOwner(frame, name)
		known = { addon = addon ~= GAME and addon or nil, follow = IsRowKey(row) and row or nil }
		db.foundFrames[name] = known
		Follow(name, known.follow)
	end
	known.dismissed, known.picked = nil, true
	return true
end

-- A look for found frames now (the Find frames tab, Smart Find): new ones are noted,
-- ones noted before are kept (they may be hidden now).
function ns.FindFoundFrames()
	local db = ns.db
	-- (Ones a supported row takes now, noted before it did, or while that
	-- row's Always was ticked: let go, unless you faded them already.)
	for name in pairs(db.foundFrames) do
		local frame = _G[name]
		local known = db.foundFrames[name]
		if not db.extraFrames[name] and not known.picked and type(frame) == "table"
			and frame.GetObjectType and not IsForbidden(frame) and (Covered(frame, name) or NamedLikeWindow(name)
			or (not known.byName and (not Draws(frame, 2) or IsBigHolder(frame)))) then
			db.foundFrames[name] = nil
			ns.ROW_FALLBACK["extra:" .. name] = nil
		end
	end
	local found = Collect()
	-- (How many each addon has listed already: MAX_PER_ADDON at most, so an
	-- addon making frames by the hundred doesn't fill the list.)
	local listed = {}
	for _, known in pairs(db.foundFrames) do
		if known.addon then listed[known.addon] = (listed[known.addon] or 0) + 1 end
	end
	for addon, entry in pairs(found.byAddon) do
		local unnamed = 0
		for _, item in ipairs(entry.frames) do
			if item.name then
				if not item.kept and not item.holder and not db.extraFrames[item.name] and not db.foundFrames[item.name]
					and (listed[addon] or 0) < MAX_PER_ADDON then
					listed[addon] = (listed[addon] or 0) + 1
					local follow = IsRowKey(item.row) and item.row or nil
					db.foundFrames[item.name] = { addon = addon, follow = follow }
					Follow(item.name, follow)
				end
			elseif item.top and not item.holder then
				unnamed = unnamed + 1
			end
		end
		local key = UNNAMED .. addon
		if unnamed > 0 and not db.extraFrames[key] then
			local known = db.foundFrames[key] or { addon = addon }
			known.count = unnamed
			db.foundFrames[key] = known
		end
	end
end

-- Whether a frame comes along with one above it: that one's faded, the
-- game's, or an addon's named frame that could be added itself. Only an
-- addon's root (straight on UIParent, screen-sized or unsized) doesn't count:
-- a whole-UI addon keeps everything in one (Reforged UI), and each part is
-- wanted on its own. Not under UIParent at all: not part of the UI.
local function ComesWithParent(frame)
	local parent = frame:GetParent()
	while parent and parent ~= UIParent do
		if IsForbidden(parent) or ns.IsFaded(parent) then
			return true
		end
		if parent:GetName() then
			local _, _, width, height = Rect(parent)
			local root = parent:GetParent() == UIParent and (not width or width * height <= 0 or IsBigHolder(parent))
			if not root then
				return true
			end
		end
		parent = parent:GetParent()
	end
	return parent == nil
end

-- The addon to list a named frame under, or nil: not the game's or ours, not
-- a supported addon's (its rows have it), and something that could be faded.
local function NamedFrameAddon(frame, name)
	local db = ns.db
	if frame:GetName() ~= name or IsForbidden(frame) or db.foundFrames[name] or db.extraFrames[name]
		or db.ignoredFrames[name] or not frame:IsObjectType("Frame") or frame:IsObjectType("GameTooltip") then
		return nil
	end
	local addon = NamedOwner(frame, name)
	if not addon or addon == GAME or addon == ADDON_NAME or not ns.AddOnLoaded(addon)
		or ns.IsSupportedAddon(addon) then
		return nil
	end
	if ns.IsFaded(frame) or ns.IsWindow(frame, name) or NamedLikeWindow(name) or Covered(frame, name)
		or ComesWithParent(frame) or not Draws(frame, 2) then
		return nil
	end
	return addon
end

-- A look through every named frame, by elimination: what isn't the game's or
-- ours is another addon's, shown or not (a target frame with no target), and
-- however deep. Goes through all the globals, so once per Smart Find, not each
-- look. Screen-sized frames are told by their names: their spot says nothing.
function ns.FindNamedFrames()
	if InCombatLockdown() then
		return
	end
	local db = ns.db
	local byAddon = {}
	-- (First the names that could be frames, then the dear look at each,
	-- both a slice a frame inside the background look's coroutine: all at
	-- once it took 80 ms, the trip over the globals alone 30. Addons add
	-- globals between slices, which can upset next(): then the trip starts
	-- over, keeping the names already found, as it's only a guess anyway.)
	local inThread = findThread ~= nil and coroutine.running() == findThread
	local names, have = {}, {}
	local key, count, restarts = nil, 0, 0
	repeat
		local ok, name, frame = pcall(next, _G, key)
		if not ok then
			-- (The globals changed under it: from the top. Over and over: not
			-- this look, the next one tries again.)
			restarts = restarts + 1
			if restarts > 3 then return end
			key = nil
		else
			key = name
			if type(name) == "string" and not have[name] and type(frame) == "table"
				and type(frame.GetObjectType) == "function" and type(frame.SetAlpha) == "function" then
				have[name] = true
				names[#names + 1] = name
			end
			count = count + 1
			if inThread and count % GLOBALS_SLICE == 0 then coroutine.yield() end
		end
	until ok and key == nil
	if inThread then coroutine.yield() end
	for i, name in ipairs(names) do
		local frame = _G[name]
		-- (pcall: a mixin table can look like a frame and error on its methods.)
		if type(frame) == "table" then
			local ok, addon = pcall(NamedFrameAddon, frame, name)
			if ok and addon then
				byAddon[addon] = byAddon[addon] or {}
				table.insert(byAddon[addon], name)
			end
		end
		if inThread and i % NAMED_SLICE == 0 then
			coroutine.yield()
			if InCombatLockdown() then return end -- (a fight started: next look)
		end
	end
	local listed = {}
	for _, known in pairs(db.foundFrames) do
		if known.addon then listed[known.addon] = (listed[known.addon] or 0) + 1 end
	end
	local hiddenGame = HiddenGameFrames()
	for addon, names in pairs(byAddon) do
		-- (The shortest first: an addon's main frames before its parts.)
		table.sort(names, function(a, b)
			if #a ~= #b then return #a < #b end
			return a < b
		end)
		for _, name in ipairs(names) do
			if (listed[addon] or 0) >= MAX_PER_ADDON then
				break
			end
			listed[addon] = (listed[addon] or 0) + 1
			local frame = _G[name]
			local left, bottom, width, height = Rect(frame)
			local rect = left and not IsBigHolder(frame) and { left, bottom, width, height } or nil
			local row = RowGuess(name, rect, hiddenGame)
			local follow = IsRowKey(row) and row or nil
			db.foundFrames[name] = { addon = addon, follow = follow, byName = true }
			Follow(name, follow)
		end
	end
	return true
end

-- The addon a found or added frame belongs to, or nil (the game's, or not
-- known: not loaded now). Remembered once known.
function ns.FrameAddon(name)
	local db = ns.db
	if name:sub(1, #UNNAMED) == UNNAMED then
		return name:sub(#UNNAMED + 1)
	end
	local found = db.foundFrames[name]
	if found then
		return found.addon
	end
	if db.frameAddons[name] then
		return db.frameAddons[name]
	end
	local frame = _G[name]
	if type(frame) == "table" then
		local source = NamedOwner(frame, name)
		if source and source ~= GAME then
			db.frameAddons[name] = source
			return source
		end
	end
	return nil
end

-- An addon's own fade animation on one of the frames below (an alpha animation
-- on the frame itself: SilverDragon's popup fading out after a while) sets
-- its alpha every frame it runs, against the fade: it flickered. So while
-- the frame's faded the animation is stopped, and played again from the start
-- once the frame's back (a popup's timer starts over then).
local FADE_CHECK = 0.1 -- seconds between looks at those animations
local fadeGroups = {} -- frame -> its fade animation groups
local stopped = {} -- group -> true: stopped while its frame was faded
local fadeTicker

local function Faded(frame)
	for _, entry in ipairs(ns.managed) do
		if entry.frame == frame then
			return entry.alpha < 1
		end
	end
	return false
end

local function FadesFrame(group, frame)
	for _, anim in ipairs({ group:GetAnimations() }) do
		if anim:GetObjectType() == "Alpha" and (anim:GetTarget() or group:GetParent()) == frame then
			return true
		end
	end
	return false
end

local function OnFadePlay(group)
	if Faded(group:GetParent()) then
		group:Stop()
		stopped[group] = true
	end
end

local function CheckFades()
	for frame, groups in pairs(fadeGroups) do
		local faded = Faded(frame)
		for _, group in ipairs(groups) do
			if faded and group:IsPlaying() then
				group:Stop()
				stopped[group] = true
			elseif not faded and stopped[group] then
				stopped[group] = nil
				group:Play()
			end
		end
	end
end

local function WatchFades(frame)
	if fadeGroups[frame] or type(frame.GetAnimationGroups) ~= "function" then
		return
	end
	local groups = {}
	for _, group in ipairs({ frame:GetAnimationGroups() }) do
		local ok, fades = pcall(FadesFrame, group, frame)
		if ok and fades then
			groups[#groups + 1] = group
			group:HookScript("OnPlay", OnFadePlay)
		end
	end
	fadeGroups[frame] = groups
	if #groups > 0 and not fadeTicker then
		-- (Profiled here: this file loads before the profiler.)
		fadeTicker = C_Timer.NewTicker(FADE_CHECK, ns.Profiled("Found frames' own fades", CheckFades))
	end
end

-- An addon's unnamed frames, once its row is unticked: faded with each scan
-- in its own group ("extra:@<addon>"), followed when they set their own
-- alpha (they're its own frames). Whose each is, is worked out once.
local owners = setmetatable({}, { __mode = "k" })
local function ScanUnnamed()
	local db = ns.db
	local any = false
	for name in pairs(db.extraFrames) do
		if name:sub(1, #UNNAMED) == UNNAMED and not db.ignoredFrames[name] then
			any = true
			break
		end
	end
	if not any then
		return
	end
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if not IsForbidden(frame) and not ns.IsFaded(frame) and not frame:GetName() then
			local owner = owners[frame]
			if owner == nil then
				owner = UnnamedOwner(frame) or false
				owners[frame] = owner
			end
			local key = owner and UNNAMED .. owner
			if key and db.extraFrames[key] and not db.ignoredFrames[key] and not ns.IsWindow(frame, nil) then
				ns.AddFoundFrame(frame, "extra:" .. key, true, true)
				WatchFades(frame)
			end
		end
	end
end

-- Frames you added or unticked here that an addon made: they're its own, so
-- they're faded as ones that set their own alpha (followed at once, hooked),
-- or a frame whose addon fades it in and out flickered. (Found before the
-- page's own scan of added frames, which would take them plainly; the
-- game's frames never are.)
local function ScanAdded()
	local db = ns.db
	for name in pairs(db.extraFrames) do
		local frame = _G[name]
		if type(frame) == "table" and type(frame.GetObjectType) == "function" and not IsForbidden(frame)
			and not ns.IsFaded(frame) and not db.ignoredFrames[name] and ns.FrameAddon(name)
			and not ns.IsWindow(frame, name) then
			ns.AddFoundFrame(frame, "extra:" .. name, true, true)
			WatchFades(frame)
		end
	end
end

local FIND_EVERY = 20 -- seconds between looks for found frames
-- Looks in the background each addon gets (across logins: db.smartFindLooks),
-- 15 minutes' worth; then it's known, and looked at only by hand (the tab, its
-- button). One installed later gets its own.
local SETTLE_LOOKS = 45

-- The loaded addons the background still looks for: not supported, not this
-- one, not yet given their looks.
function ns.NewAddons()
	local new, looks = {}, ns.db.smartFindLooks
	for _, folder in ipairs(LoadedFolders()) do
		if folder ~= ADDON_NAME and (looks[folder] or 0) < SETTLE_LOOKS and not ns.IsSupportedAddon(folder) then
			new[#new + 1] = folder
		end
	end
	return new
end
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
	for name, found in pairs(ns.db.foundFrames) do
		if not found.dismissed then
			Follow(name, found.follow)
		end
	end
	ns.AddScanner(ScanUnnamed)
	ns.AddScanner(ScanAdded)
	-- Smart Find in the background (its tick on the Find frames tab): a look
	-- now and then, so frames that come and go (another addon's popups) are
	-- caught while they're up. Only while an addon is new to it (NewAddons),
	-- and not in fights.
	-- (Each look a slice of the top-level frames a frame, in a coroutine,
	-- rather than all of them in one frame: it took 2.5 ms in one go.)
	local lookedByName = false
	local function Look(new)
		ns.FindFoundFrames()
		if not lookedByName then
			-- (Done once a session; cut short by a fight, the next look tries again.)
			lookedByName = ns.FindNamedFrames() and true or false
		end
		local looks = ns.db.smartFindLooks
		for _, addon in ipairs(new) do
			looks[addon] = (looks[addon] or 0) + 1
		end
	end
	local driver = CreateFrame("Frame")
	local function Resume()
		if InCombatLockdown() then return end -- (waits out a fight)
		local ok, err = coroutine.resume(findThread)
		if not ok then
			ns.Log("guess", "background look failed: " .. tostring(err))
		end
		if not ok or coroutine.status(findThread) == "dead" then
			findThread = nil
			ns.SetOnUpdate(driver, nil)
		end
	end
	C_Timer.NewTicker(FIND_EVERY, ns.Profiled("Find found frames", function()
		if findThread or not (ns.db.smartFindBackground and ns.db.handleAddonFrames) or InCombatLockdown() then
			return
		end
		local new = ns.NewAddons()
		if #new > 0 then
			findThread = coroutine.create(Look)
			local ok, err = coroutine.resume(findThread, new)
			if not ok then
				ns.Log("guess", "background look failed: " .. tostring(err))
				findThread = nil
			elseif coroutine.status(findThread) ~= "dead" then
				ns.SetOnUpdate(driver, Resume)
			else
				findThread = nil
			end
		end
	end))
end)

-- /cine debug guess <frame>: why the guesser lists a frame or passes it by.
function ns.ExplainGuess(name)
	local function Say(text)
		ns.Print(("guess %s: %s"):format(name, text)) -- (printed lines go in the log too)
	end
	local frame = _G[name]
	if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then
		Say("no frame by that name")
		return
	elseif IsForbidden(frame) then
		Say("forbidden: off limits")
		return
	end
	local function Label(other)
		if IsForbidden(other) then
			return "(forbidden)"
		end
		return (other:GetName() or other:GetDebugName()) .. (ns.Flag(other:IsShown()) and "" or " (hidden)")
	end
	local chain, parent = {}, frame:GetParent()
	while parent and #chain < 6 do
		chain[#chain + 1] = Label(parent)
		if parent == UIParent or IsForbidden(parent) then
			break
		end
		parent = parent:GetParent()
	end
	Say("parents: " .. (#chain > 0 and table.concat(chain, " < ") or "none"))
	-- (Looked at: UIParent's own frames, and what's just inside the big,
	-- unsized or unnamed ones.)
	local holder = frame:GetParent()
	local looked = holder == UIParent
	if not looked and holder and not IsForbidden(holder) and holder:GetParent() == UIParent then
		local _, _, width, height = Rect(holder)
		local area = width and width * height or 0
		looked = area <= 0 or area > UIParent:GetWidth() * UIParent:GetHeight() * HOLDER_SHARE
			or not holder:GetName()
	end
	Say(looked and "looked at: yes" or "looked at: no (only UIParent's frames, and what's just inside the big, "
		.. "unsized or unnamed ones, are)")
	local left, bottom, width, height = Rect(frame)
	local alpha = frame:GetAlpha()
	Say(("shown=%s visible=%s alpha=%s size=%s at %s strata=%s"):format(tostring(ns.Flag(frame:IsShown())),
		tostring(ns.Flag(frame:IsVisible())), Plain(alpha) and ("%.2f"):format(alpha) or "secret",
		width and ("%dx%d"):format(width, height) or "?", left and ("%d,%d"):format(left, bottom) or "?",
		frame:GetFrameStrata()))
	local game, source = GlobalSource(name)
	local owner, how = NamedOwner(frame, name)
	Say(("whose: %s (%s); made by %s; named after %s; global by %s"):format(tostring(owner), tostring(how),
		tostring(madeBy[frame] or "? (before Cinematic loaded, or not on UIParent then)"),
		tostring(NamedAfter(name)), game and "the game" or tostring(source)))
	-- (And what a look now makes of it.)
	local now = "no"
	for addon, entry in pairs(Collect().byAddon) do
		for _, item in ipairs(entry.frames) do
			if item.name == name then
				now = ("yes, under %s, row %s (%s)"):format(addon, item.row, item.why)
			end
		end
	end
	Say("a look now finds it: " .. now)
	local found = ns.db.foundFrames[name]
	Say(("faded by Cinematic %s; window %s (by name %s); draws something %s; a supported row takes it %s; "
		.. "kept shown by you %s; listed %s"):format(tostring(ns.IsFaded(frame)),
		tostring(ns.IsWindow(frame, name)), tostring(NamedLikeWindow(name)), tostring(Draws(frame, 2)),
		tostring(Covered(frame, name)),
		tostring(ns.db.ignoredFrames[name] or false),
		found and (found.dismissed and "no (taken off)" or found.byName and "yes (by name)" or "yes") or "no"))
end

-- Smart Find for a while (the Find frames tab's button): a look once a
-- second, onTick after each (and once more as it ends) for the tab's
-- countdown and list.
ns.SMART_FIND_SECONDS = 20
local run -- { ticker, left, onTick } while on

function ns.SmartFindLeft()
	return run and run.left or nil
end

function ns.StopSmartFind()
	if not run then
		return
	end
	run.ticker:Cancel()
	local onTick = run.onTick
	run = nil
	if onTick then onTick() end
end

function ns.StartSmartFind(onTick)
	ns.StopSmartFind()
	run = { left = ns.SMART_FIND_SECONDS, onTick = onTick }
	ns.FindFoundFrames()
	ns.FindNamedFrames()
	run.ticker = C_Timer.NewTicker(1, function()
		if not run then return end
		run.left = run.left - 1
		if not InCombatLockdown() then
			ns.FindFoundFrames()
		end
		if run.left <= 0 then
			ns.StopSmartFind()
		elseif run.onTick then
			run.onTick()
		end
	end)
	if onTick then onTick() end
end
