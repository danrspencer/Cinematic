-- Gryphons test (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/gryphons.lua < /dev/null
-- Parts that ignore their frame's alpha (FadeDetached.lua). The case that
-- found it: action bar 1's art on Forever, where each gryphon (MainActionBar.
-- EndCaps' LeftEndCap and RightEndCap) is an Edit Mode system of its own and
-- another addon (FlareUI 6.13) makes it ignore EndCaps' alpha. The HUD's
-- Action bar art row faded out must reach the gryphons then too, keep them
-- down if that addon raises them, follow a half fade, hand them back when the
-- art comes back, and leave gryphons that follow EndCaps alone; the Overrides
-- tab's Hide too. And for any faded frame: another addon's detached part
-- follows it, one Cinematic detached itself is left alone, and /cine why
-- lists what it caught. Says PASS or FAIL per check.
local stack = "" -- (what debugstack says: who called SetIgnoreParentAlpha)
-- luacheck: push ignore 111 112 113 121 122 212
local function RealHook(obj, name, fn)
	if type(obj) == "string" then obj, name, fn = _G, obj, name end -- (the global form)
	local orig = obj[name]
	if orig == nil then return end -- (the stand-in's unknown methods are callable stubs, not functions)
	obj[name] = function(...)
		local a, b, c = orig(...)
		fn(...)
		return a, b, c
	end
end
-- A region with a real alpha and parent-alpha flag.
local function Alpha(frame)
	frame._alpha, frame._ignore = 1, false
	frame.SetAlpha = function(self, a) self._alpha = a end
	frame.GetAlpha = function(self) return self._alpha end
	frame.SetIgnoreParentAlpha = function(self, on)
		self._ignore = on and true or false
		-- (The game's shared method, hooked by FadeDetached.lua: the stand-in has none.)
		if _G.CinematicTestNS and _G.CinematicTestNS.OnIgnoreParentAlpha then
			_G.CinematicTestNS.OnIgnoreParentAlpha(self, on)
		end
	end
	frame.IsIgnoringParentAlpha = function(self) return self._ignore end
	frame.GetEffectiveAlpha = function(self)
		local a, parent = self._alpha, self:GetParent()
		if not self._ignore and parent and parent.GetEffectiveAlpha then a = a * parent:GetEffectiveAlpha() end
		return a
	end
	frame.IsVisible = function() return true end
	frame.IsForbidden = function() return false end
	return frame
end
local ns = dofile("Tools/offline/load.lua")("forever", nil, function(wow)
	hooksecurefunc = RealHook
	debugstack = function() return stack end -- (FrameGuess.lua and FadeDetached.lua read it)
	local bar = Alpha(CreateFrame("Frame", "MainActionBar", UIParent))
	bar.EndCaps = Alpha(CreateFrame("Frame", nil, bar))
	bar.EndCaps.LeftEndCap = Alpha(CreateFrame("Frame", nil, bar.EndCaps))
	bar.EndCaps.RightEndCap = Alpha(CreateFrame("Frame", nil, bar.EndCaps))
	bar.BorderArt = Alpha(CreateFrame("Frame", nil, bar))
end)
-- luacheck: pop
local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end
_G.CinematicTestNS = ns
local bar = _G.MainActionBar
local caps, left, right = bar.EndCaps, bar.EndCaps.LeftEndCap, bar.EndCaps.RightEndCap
ns.db.handleFrames = true
if ns.BuildManagedList then ns.BuildManagedList() end
local standIn = ns.barArtStandIn
Check("the art's stand-in made (HUD Action bar art row handled)", standIn ~= nil)
if not standIn then os.exit(1) end

-- Another addon makes the left gryphon fade on its own (FlareUI): it ignores EndCaps.
left:SetIgnoreParentAlpha(true)
standIn:SetAlpha(0)
Check("faded out: EndCaps at 0", caps:GetAlpha() == 0, caps:GetAlpha())
Check("faded out: the band at 0", bar.BorderArt:GetAlpha() == 0, bar.BorderArt:GetAlpha())
Check("faded out: a gryphon ignoring EndCaps gets 0 itself", left:GetAlpha() == 0, left:GetAlpha())
Check("faded out: a gryphon following EndCaps is left at its own 1", right:GetAlpha() == 1, right:GetAlpha())

left:SetAlpha(1) -- (that addon's fade raising it again)
Check("raised by another addon while faded: put back to 0", left:GetAlpha() == 0, left:GetAlpha())

right:SetIgnoreParentAlpha(true) -- (made to ignore EndCaps after the fade)
Check("made to ignore EndCaps while faded: gets 0 then", right:GetAlpha() == 0, right:GetAlpha())

standIn:SetAlpha(0.5)
Check("half faded: a gryphon ignoring EndCaps at 0.5", left:GetAlpha() == 0.5, left:GetAlpha())

standIn:SetAlpha(1)
Check("back up: the gryphons handed back at 1", left:GetAlpha() == 1 and right:GetAlpha() == 1,
	left:GetAlpha() .. "/" .. right:GetAlpha())
left:SetAlpha(0.3) -- (that addon fading it by its own choice, ours up)
Check("back up: another addon's own fade left be", left:GetAlpha() == 0.3, left:GetAlpha())
left:SetAlpha(1)

-- The Overrides tab's Action bar art: Hide.
if ns.ApplyBarArtOverride then
	local StyleOverride = ns.StyleOverride
	ns.StyleOverride = function(key) if key == "barArt" then return "hide" end return StyleOverride(key) end
	ns.ApplyBarArtOverride()
	Check("Overrides Hide: each gryphon at 0", left:GetAlpha() == 0 and right:GetAlpha() == 0,
		left:GetAlpha() .. "/" .. right:GetAlpha())
	left:SetAlpha(1)
	Check("Overrides Hide: kept at 0 when another addon raises it", left:GetAlpha() == 0, left:GetAlpha())
	standIn:SetAlpha(0.5)
	standIn:SetAlpha(1)
	Check("Overrides Hide: the HUD row coming back up doesn't raise it", left:GetAlpha() == 0, left:GetAlpha())
	ns.StyleOverride = function(key) if key == "barArt" then return nil end return StyleOverride(key) end
	ns.ApplyBarArtOverride()
	Check("Overrides back to the row: gryphons at 1", left:GetAlpha() == 1 and right:GetAlpha() == 1,
		left:GetAlpha() .. "/" .. right:GetAlpha())
	ns.StyleOverride = StyleOverride
else
	Check("ns.ApplyBarArtOverride there", false)
end

-- /cine why: the art's card lists the caught gryphons while faded.
standIn:SetAlpha(0)
local caught = ns.DetachedFor and ns.DetachedFor(standIn) or {}
local names = {}
for _, part in ipairs(caught) do names[#names + 1] = part.name end
Check("/cine why: the art lists the gryphons it fades", #caught == 2, table.concat(names, ", "))
standIn:SetAlpha(1)

-- Any faded frame, not only the art: another addon's part follows it; ours doesn't.
local panel = Alpha(CreateFrame("Frame", "TestLoosePanel", UIParent))
local theirs = Alpha(CreateFrame("Frame", "TestTheirPart", panel))
local mine = Alpha(CreateFrame("Frame", "TestOurPart", panel))
stack = "[string \"@Interface/AddOns/SomeAddon/Bars.lua\"]:10: in function"
theirs:SetIgnoreParentAlpha(true)
stack = "[string \"@Interface/AddOns/Cinematic/Effects.lua\"]:1487: in function"
mine:SetIgnoreParentAlpha(true)
stack = ""
panel:SetAlpha(0)
ns.SyncDetached(panel)
Check("a faded frame: another addon's detached part faded with it", theirs:GetAlpha() == 0, theirs:GetAlpha())
Check("a faded frame: a part Cinematic detached left as it is", mine:GetAlpha() == 1, mine:GetAlpha())
local selection = Alpha(CreateFrame("Frame", "TestPanelSelection", panel))
panel.Selection = selection
selection:SetIgnoreParentAlpha(true)
ns.SyncDetached(panel)
Check("an Edit Mode Selection box left as the game made it", selection:GetAlpha() == 1, selection:GetAlpha())
local who = (ns.DetachedFor(panel)[1] or {}).by
Check("/cine why: says which addon detached it", who == "SomeAddon", who)
panel:SetAlpha(1)
ns.SyncDetached(panel)
Check("the frame back up: the part has its own alpha back", theirs:GetAlpha() == 1, theirs:GetAlpha())

-- A part that answers whether it's detached with a secret (FlareUI's frames
-- on Forever): faded when the hook saw an addon detach it, left when it didn't.
local SECRET = {}
local realIsSecret = issecretvalue
issecretvalue = function(value) return value == SECRET end -- luacheck: ignore 121
local panel2 = Alpha(CreateFrame("Frame", "TestSecretPanel", UIParent))
local seenPart = Alpha(CreateFrame("Frame", "TestSeenPart", panel2))
local unseenPart = Alpha(CreateFrame("Frame", "TestUnseenPart", panel2))
seenPart.SetAlphaFromBoolean = function(self, on, ifTrue, ifFalse) self._alpha = on and ifTrue or ifFalse end
stack = "[string \"@Interface/AddOns/SomeAddon/Raid.lua\"]:5: in function"
seenPart:SetIgnoreParentAlpha(true) -- (while the panel is up: the hook sees it)
stack = ""
unseenPart._ignore = true -- (set before we watched)
seenPart.IsIgnoringParentAlpha = function() return SECRET end
unseenPart.IsIgnoringParentAlpha = function() return SECRET end
panel2:SetAlpha(0)
ns.SyncDetached(panel2)
Check("a secret answer, detached as the hook watched: faded with its frame", seenPart:GetAlpha() == 0,
	seenPart:GetAlpha())
Check("a secret answer the hook never saw: left (nothing to go by)", unseenPart:GetAlpha() == 1, unseenPart:GetAlpha())
seenPart:SetAlphaFromBoolean(true, 1, 0)
Check("raised by SetAlphaFromBoolean while faded: put back to 0", seenPart:GetAlpha() == 0, seenPart:GetAlpha())
panel2:SetAlpha(1)
ns.SyncDetached(panel2)
Check("its frame back up: the secret part back at 1", seenPart:GetAlpha() == 1, seenPart:GetAlpha())
issecretvalue = realIsSecret -- luacheck: ignore 121

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
