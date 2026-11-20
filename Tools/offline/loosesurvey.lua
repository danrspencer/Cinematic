-- Loose parts survey test (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/loosesurvey.lua < /dev/null
-- /cine debug loose (Dev/LoosePartsSurvey.lua, step A of Tools/loose-parts-plan.md)
-- on the dev copy: a faded frame with a region and a child that ignore its
-- alpha, one two levels down, one that follows it, a frame with a row of its
-- own inside it (not walked into), our own detached part and a secret answer.
-- It must find exactly the loose ones, change no alpha, and print its summary.
-- Says PASS or FAIL per check.
-- luacheck: push ignore 111 112 113 121 122 212
local function Alpha(frame, ignore)
	frame._alpha, frame._ignore = 1, ignore and true or false
	frame.SetAlpha = function(self, a) self._alpha = a end
	frame.GetAlpha = function(self) return self._alpha end
	frame.SetIgnoreParentAlpha = function(self, on) self._ignore = on and true or false end
	frame.IsIgnoringParentAlpha = function(self) return self._ignore end
	frame.IsForbidden = function() return false end
	return frame
end
local made = {}
local ns, wow = dofile("Tools/offline/load.lua")("forever", "CinematicDev.toc", function()
	debugstack = function() return "" end
	debugprofilestop = function() return 0 end
	local bar = Alpha(CreateFrame("Frame", "LooseTestBar", UIParent))
	made.bar = bar
	made.looseRegion = Alpha(bar:CreateTexture(), true)
	made.followRegion = Alpha(bar:CreateTexture(), false)
	made.looseChild = Alpha(CreateFrame("Frame", "LooseTestChild", bar), true)
	local inner = Alpha(CreateFrame("Frame", nil, bar), false)
	made.deepLoose = Alpha(CreateFrame("Frame", "LooseTestDeep", inner), true)
	made.ownRow = Alpha(CreateFrame("Frame", "LooseTestOwnRow", bar), true)
	made.underOwnRow = Alpha(CreateFrame("Frame", nil, made.ownRow), true)
	made.ours = Alpha(CreateFrame("Frame", nil, bar), true)
	made.secret = Alpha(CreateFrame("Frame", nil, bar), false)
	made.secret.IsIgnoringParentAlpha = function() return "SECRET" end
	issecretvalue = function(v) return v == "SECRET" end
end)
-- luacheck: pop
local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end
Check("the dev copy loaded the survey", type(ns.LoosePartsSurvey) == "function" and type(ns.SurveyLooseParts) == "function")
for _, w in ipairs(wow.warnings) do if w:find("LoosePartsSurvey") then Check("survey file loads", false, w) end end
if type(ns.SurveyLooseParts) ~= "function" then os.exit(1) end

-- The test frame managed (as a row's frame), one inside it with a row of its own, one of our own detached parts.
ns.managed = { { frame = made.bar, name = "LooseTestBar", group = "test" },
	{ frame = made.ownRow, name = "LooseTestOwnRow", group = "test2" } }
local IsManagedFrame, IsOwnDetached = ns.IsManagedFrame, ns.IsOwnDetached
ns.IsManagedFrame = function(f) return f == made.bar or f == made.ownRow end
ns.IsOwnDetached = function(r) return r == made.ours end

local parts, skipped = ns.SurveyLooseParts()
local found = {}
for _, p in ipairs(parts) do found[p.part] = p end
Check("a region ignoring its frame found", found[made.looseRegion] ~= nil)
Check("a child ignoring its frame found", found[made.looseChild] ~= nil)
Check("one two levels down found, at depth 2", found[made.deepLoose] and found[made.deepLoose].depth == 2,
	found[made.deepLoose] and found[made.deepLoose].depth)
Check("a region following its frame not listed", found[made.followRegion] == nil)
Check("a frame with its own row not listed", found[made.ownRow] == nil)
Check("a loose part under that frame listed once, under its own row",
	found[made.underOwnRow] and found[made.underOwnRow].entry.frame == made.ownRow)
Check("our own detached part not listed", found[made.ours] == nil and skipped.own == 1, skipped.own)
Check("a secret answer counted apart", found[made.secret] == nil and skipped.secret == 1, skipped.secret)
Check("frames with a row skipped while walking", skipped.managed == 1, skipped.managed)
local count = 0
for _ in pairs(found) do count = count + 1 end
Check("exactly the loose ones", count == 4, count)

local before = {}
for key, object in pairs(made) do before[key] = object:GetAlpha() end
local printed = {}
local Print = ns.Print
ns.Print = function(text) printed[#printed + 1] = text end
ns.LoosePartsSurvey()
ns.Print = Print
local changed = false
for key, object in pairs(made) do if object:GetAlpha() ~= before[key] then changed = key end end
Check("the survey changes no alpha", not changed, changed)
Check("chat summary counts the parts", printed[1] and printed[1]:find("loose parts: 4 under 2 frames") ~= nil, printed[1])
ns.IsManagedFrame, ns.IsOwnDetached = IsManagedFrame, IsOwnDetached

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
