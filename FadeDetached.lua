-- Cinematic: parts that ignore their frame's alpha. A frame Cinematic fades
-- takes its parts with it, unless a part ignores its parent's alpha
-- (SetIgnoreParentAlpha): that one is drawn at its own alpha while the frame
-- is gone. The game does it to some parts, and another addon can do it to any
-- part at any time (FlareUI 6.13 to bar 1's gryphons on Forever, to fade them
-- by its own choice, and Cinematic's hide stopped reaching them).
--
-- So each frame whose alpha Cinematic sets is a root (ns.SyncDetached). While
-- a root is below full, every part under it that ignores its parent gets the
-- alpha it'd have if it followed it: its own alpha times its parent's
-- effective alpha. Its own alpha is kept as it's set meanwhile (another
-- addon's fade of it), and handed back once no root over it is faded.
-- Found two ways: a walk of the root's parts when it goes down, and a hook on
-- the game's shared SetIgnoreParentAlpha, for parts detached later.
--
-- Parts Cinematic detaches itself (a prompt kept up while the UI fades, the
-- fade's own parts) are left alone: marked as they're set, by the call stack.
-- Loads early (after FrameGuess.lua) so that's all of them.
local ADDON_NAME, ns = ...

-- (Depth 4: the survey, /cine debug loose, found loose parts at depths 1-3
-- only. A walk of every faded frame at depth 6 took 37 ms on Forever, 84 ms
-- with FlareUI: so walks share a budget per frame, the rest wait their turn.)
local MAX_DEPTH, MAX_NODES, BUDGET_MS = 4, 800, 1.5
local OUR_FOLDER = "AddOns[/\\]" .. ADDON_NAME:gsub("%p", "%%%0") .. "[/\\]"
local roots = setmetatable({}, { __mode = "k" }) -- root -> { owner, down, list }
local taken = setmetatable({}, { __mode = "k" }) -- part -> { own = its own alpha, by = who detached it }
local ours = setmetatable({}, { __mode = "k" }) -- part -> true: Cinematic detached it
local by = setmetatable({}, { __mode = "k" }) -- part -> the addon that detached it, when seen
local hooked = setmetatable({}, { __mode = "k" })
local logged = setmetatable({}, { __mode = "k" })
local busy = false

local function Plain(value)
	if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
	return value
end
local function Usable(region)
	return type(region) == "table" and type(region.SetAlpha) == "function"
		and type(region.IsIgnoringParentAlpha) == "function"
		and not (region.IsForbidden and region:IsForbidden())
end
-- Whether it ignores its parent's alpha; nil when the game won't say (a secret
-- answer: 1247 parts with FlareUI 6.13 on Forever). Those only the hook catches.
local function Ignoring(region)
	local on = region:IsIgnoringParentAlpha()
	if issecretvalue and issecretvalue(on) then return nil end
	return on == true
end
local function NameOf(region)
	local name = region.GetDebugName and region:GetDebugName() or region.GetName and region:GetName()
	return type(name) == "string" and name ~= "" and name or "?"
end

-- Who called SetIgnoreParentAlpha: the first addon on the stack (not this file).
local function Caller()
	local stack = debugstack and debugstack(2, 10, 0) or ""
	for line in stack:gmatch("[^\n]+") do
		if not line:find("FadeDetached.lua", 1, true) then
			if line:find(OUR_FOLDER) then return ADDON_NAME end
			local addon = line:match("AddOns[/\\]([^/\\]+)[/\\]")
			if addon then return addon end
		end
	end
	return "game"
end

-- The nearest root over a part that's faded (below full, however: ours, or
-- the whole UI's).
local function FadedRoot(region)
	local parent, depth = region:GetParent(), 0
	while parent and depth < 40 do
		if roots[parent] and parent.GetEffectiveAlpha then
			local alpha = Plain(parent:GetEffectiveAlpha())
			if alpha and alpha < 1 then return parent end
		end
		parent, depth = parent.GetParent and parent:GetParent(), depth + 1
	end
end

local Apply, Detached, Drain
local function Release(region)
	local info = taken[region]
	if not info then return end
	taken[region] = nil
	busy = true
	region:SetAlpha(info.own)
	busy = false
end
function Apply(region)
	local info = taken[region]
	if not info or busy or not Usable(region) then return end
	if not Detached(region) or not FadedRoot(region) then
		return Release(region)
	end
	local parent = region:GetParent()
	local alpha = parent and parent.GetEffectiveAlpha and Plain(parent:GetEffectiveAlpha())
	if not alpha then return end
	local want = info.own * alpha
	if Plain(region:GetAlpha()) ~= want then
		busy = true
		region:SetAlpha(want)
		busy = false
	end
end

local function OnOwnAlpha(region, alpha)
	local info = taken[region]
	if busy or not info then return end
	-- (Its own alpha, as another addon sets it: kept, to hand back and to fade by.)
	alpha = Plain(alpha)
	if alpha then info.own = alpha end
	Apply(region)
end

local function Take(region, root)
	if taken[region] then return Apply(region) end
	local own = Plain(region:GetAlpha()) or 1
	taken[region] = { own = own }
	if not hooked[region] then
		hooked[region] = true
		hooksecurefunc(region, "SetAlpha", OnOwnAlpha)
	end
	-- (Logged when an addon detached it, as Cinematic watched: the game's own,
	-- set before we loaded, would fill /cine log: the chat edit box's prompt.)
	if not logged[region] and ns.Log and by[region] and by[region] ~= "game" then
		logged[region] = true
		ns.Log("fade", ("%s ignores its frame's alpha (detached by %s), inside %s: faded with it"):format(
			NameOf(region), by[region], NameOf(root)))
	end
	Apply(region)
end

-- A part that ignores its parent and isn't ours: not one Cinematic detached,
-- not a frame with a row of its own (it fades as that), not a raid tile's
-- loose part (Frames.lua's FadeLooseParts has those: cinematicAlpha), and not
-- an Edit Mode system's Selection box (the game's, shown only in Edit Mode,
-- which must see it: 84 of them on Forever, tested 2026-11-20).
function Detached(region)
	local parent = Usable(region) and region:GetParent()
	if parent and parent.Selection == region then return false end
	return Usable(region) and not ours[region] and Ignoring(region) == true
		and region.cinematicAlpha == nil
		and not (ns.IsOwnDetached and ns.IsOwnDetached(region))
		and not (ns.IsManagedFrame and ns.IsManagedFrame(region))
end

local function Walk(frame, depth, list, count)
	if depth > MAX_DEPTH or count[1] > MAX_NODES then return end
	if frame.GetRegions then
		for _, region in ipairs({ frame:GetRegions() }) do
			count[1] = count[1] + 1
			if Detached(region) then list[#list + 1] = region end
		end
	end
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			count[1] = count[1] + 1
			if Detached(child) then list[#list + 1] = child end
			if not (child.IsForbidden and child:IsForbidden()) then Walk(child, depth + 1, list, count) end
		end
	end
end

-- The walks waiting, done a budget's worth a frame (now, then each frame).
local queue, spentFrame, spent = {}, nil, 0
local walker
local function WalkRoot(root)
	local info = roots[root]
	if not (info and info.down and Usable(root)) then return end
	local list = {}
	Walk(root, 1, list, { 0 })
	local seen = {}
	for _, region in ipairs(list) do seen[region] = true end
	for _, region in ipairs(info.list) do
		if taken[region] and not seen[region] then list[#list + 1] = region end
	end
	info.list = list
	for _, region in ipairs(list) do Take(region, root) end
end
function Drain()
	local frame = GetTime()
	if spentFrame ~= frame then spentFrame, spent = frame, 0 end
	while queue[1] and spent < BUDGET_MS do
		local start = debugprofilestop()
		WalkRoot(table.remove(queue, 1))
		spent = spent + (debugprofilestop() - start)
	end
	if not walker then walker = CreateFrame("Frame") end
	if queue[1] then
		ns.SetOnUpdate(walker, Drain)
	else
		ns.SetOnUpdate(walker, nil)
	end
end

-- A frame whose alpha Cinematic just set: its detached parts follow it while
-- it's faded, and are handed back once it's up. owner: the frame /cine why
-- shows it under (the action bar art's stand-in, say), the root if none.
function ns.SyncDetached(root, owner)
	if not Usable(root) or not root.GetEffectiveAlpha then return end
	local info = roots[root]
	if not info then
		info = { owner = owner or root, down = false, list = {} }
		roots[root] = info
	end
	local alpha = Plain(root:GetEffectiveAlpha())
	if not alpha then return end
	if alpha < 1 and not info.down then
		-- (Gone down: its parts looked over once, as the budget allows; ones
		-- detached later come by the hook.)
		info.down = true
		queue[#queue + 1] = root
		Drain()
	elseif alpha >= 1 then
		info.down = false
	end
	for _, region in ipairs(info.list) do Apply(region) end
end

-- The shared SetIgnoreParentAlpha, after the game's: who detached it, and a
-- part detached inside a faded root taken at once (one let go again released).
local function OnIgnore(region, on)
	if busy or type(region) ~= "table" or (issecretvalue and issecretvalue(on)) then return end
	if on then
		local who = Caller()
		by[region] = who
		ours[region] = who == ADDON_NAME or nil
		if ours[region] then return Release(region) end
		local root = Detached(region) and FadedRoot(region)
		if root then
			local list = roots[root].list
			list[#list + 1] = region
			Take(region, root)
		end
	else
		ours[region] = nil
		Release(region)
	end
end
ns.OnIgnoreParentAlpha = OnIgnore -- (Tools/offline/gryphons.lua: its stand-in has no shared methods)

-- Hooked once per kind of frame (each kind's methods are one table, shared).
do
	local done = {}
	local function HookKind(object)
		local meta = type(object) == "table" and getmetatable(object)
		local methods = type(meta) == "table" and meta.__index
		if type(methods) == "table" and not done[methods] and type(methods.SetIgnoreParentAlpha) == "function" then
			done[methods] = true
			hooksecurefunc(methods, "SetIgnoreParentAlpha", OnIgnore)
		end
	end
	local probe = CreateFrame("Frame")
	probe:Hide()
	HookKind(probe)
	for _, kind in ipairs({ "Button", "CheckButton", "StatusBar", "Cooldown", "Slider", "EditBox", "ScrollFrame",
		"MessageFrame", "SimpleHTML", "PlayerModel", "ModelScene" }) do
		local ok, frame = pcall(CreateFrame, kind, nil, probe)
		if ok then HookKind(frame) end
	end
	HookKind(probe:CreateTexture())
	HookKind(probe:CreateFontString())
	if probe.CreateLine then HookKind(probe:CreateLine()) end
end

-- For /cine why: the parts of a frame (or of the roots it stands for) that
-- ignore its alpha and are faded with it now. Each: { name, by, drawn } (drawn:
-- still showing while its frame is gone).
function ns.DetachedFor(owner)
	local out = {}
	for root, info in pairs(roots) do
		if info.owner == owner then
			local rootAlpha = Plain(root:GetEffectiveAlpha())
			for _, region in ipairs(info.list) do
				if taken[region] then
					local alpha = region.GetEffectiveAlpha and Plain(region:GetEffectiveAlpha())
					out[#out + 1] = { name = NameOf(region), by = by[region],
						drawn = rootAlpha == 0 and alpha ~= nil and alpha > 0 and Plain(region:IsVisible()) == true }
				end
			end
		end
	end
	return out
end
