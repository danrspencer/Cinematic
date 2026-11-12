-- Cinematic: Deadly Boss Mods. Its timer bars all sit in one unnamed anchor
-- on UIParent (its big bars are only placed by a second anchor, they stay in
-- the first), so fading that fades them all. It's found by its first bar,
-- which DBM makes at the first timer: until then there's nothing to fade.
-- Its info frame, range check, arrow and battle res timer are named frames.
-- Its raid warnings and special warnings aren't faded, like the game's.
-- It leaves those frames' alpha alone (its bars fade in their own frames),
-- so they aren't hooked.
local _, ns = ...
local L = ns.L

-- One frame a row. (from: the row that held them all till 2026-11-12, whose
-- settings each starts with: ns.SplitAddonRows.)
for _, known in ipairs({
	{
		key = "dbmBars", label = "Deadly Boss Mods timer bars", short = "DBM timer bars",
		about = L["its timer bars"],
		note = L["Its warnings aren't faded, like the game's raid warnings."],
		match = function(frame)
			local first = frame:GetChildren()
			-- (an unnamed frame of the game's can hold a forbidden one first)
			if not first or (first.IsForbidden and first:IsForbidden()) then
				return false
			end
			local name = first:GetName()
			return name and name:find("^DBT_Bar_%d+$") and true or false
		end,
	},
	{
		key = "dbmInfo", label = "Deadly Boss Mods info frame", short = "DBM info frame",
		about = L["its info frame"], names = { "DBMInfoFrame" },
	},
	{
		key = "dbmRange", label = "Deadly Boss Mods range check", short = "DBM range check",
		about = L["its range check"], names = { "DBMRangeCheck" },
	},
	{
		key = "dbmRadar", label = "Deadly Boss Mods range radar", short = "DBM range radar",
		about = L["its range check radar"], names = { "DBMRangeCheckRadar" },
	},
	{
		key = "dbmArrow", label = "Deadly Boss Mods arrow", short = "DBM arrow",
		about = L["its arrow"], names = { "DBMArrow" },
	},
	{
		key = "dbmBattleRes", label = "Deadly Boss Mods battle res timer", short = "DBM battle res",
		about = L["its battle res timer"], names = { "DBMBattleRezTimerFrame" },
	},
}) do
	known.addon, known.suite, known.from = "DBM-Core", "Deadly Boss Mods", "dbm"
	table.insert(ns.ADDON_FRAMES, known)
end
