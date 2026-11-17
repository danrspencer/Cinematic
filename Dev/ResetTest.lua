-- /cine debug resettest: one run checking what a reset puts back (a
-- player's report 2026-11-17: removing the addon left Edit Mode layouts
-- and plate settings behind), across one reload. Without wiping your
-- settings: it runs the reset's own steps, not the reset.
--   1 plate: a plate setting set off as yours, the Nameplates row's write
--            (ns.EnablePlateRow) turns it on and keeps "off" as yours, and
--            ns.PutBackOwnCVars puts "off" back; then as it was.
--   2 layouts: ns.ResetLayouts deletes every one of ours and keeps all of
--            yours, then the profile's own layout (if it has one of ours)
--            is made again as on picking it (ns.ApplyProfileLayout).
--   3 login (after the reload): no layout of ours made just for logging
--            in, only the profile's.
-- A verdict per check, into CinematicDB.resetTestLog. Dev copy only.
local _, ns = ...

local RESUME = 6 -- seconds after the reload before step 3

local function Log(text)
	local log = CinematicDB and CinematicDB.resetTestLog
	if log then log[#log + 1] = text end
end
local function Verdict(name, ok, detail)
	Log(("%s %s: %s"):format(ok and "PASS" or "FAIL", name, detail))
	ns.Print(("%s %s"):format(ok and "|cff40ff40PASS|r" or "|cffff4040FAIL|r", name))
end

-- Ours in Edit Mode now, by name, and the player's own (not ours).
local function Layouts()
	local ours, yours = {}, {}
	for name in pairs(ns.EDIT_MODE_LAYOUTS) do
		if ns.LayoutState(name) then ours[#ours + 1] = name end
	end
	for _, layout in ipairs(C_EditMode.GetLayouts().layouts) do
		local name = layout.layoutName
		if not ns.EDIT_MODE_LAYOUTS[ns.LAYOUT_RENAMED[name] or name] then yours[#yours + 1] = name end
	end
	table.sort(ours)
	table.sort(yours)
	return ours, yours
end

-- The profile's layout if it's one of ours, else nil.
local function ProfileOurs()
	local want = ns.db.editModeLayout or ""
	want = ns.LAYOUT_RENAMED[want] or want
	return ns.EDIT_MODE_LAYOUTS[want] and want or nil
end

local function State(label)
	local ours, yours = Layouts()
	Log(("%s: active %s; ours [%s]; yours [%s]; profile %s, its layout %q"):format(label,
		tostring(ns.ActiveLayoutName()), table.concat(ours, ", "), table.concat(yours, ", "),
		tostring(ns.ActiveProfile and ns.ActiveProfile()), tostring(ns.db.editModeLayout)))
	return ours, yours
end

local function PlateStep()
	local cvar, kind
	for _, try in ipairs({ { "nameplateShowFriendlyNPCs", "FriendlyNPCs" }, { "nameplateShowEnemyMinus", "EnemyMinor" } }) do
		if GetCVar(try[1]) ~= nil then cvar, kind = try[1], try[2] break end
	end
	if not cvar then return Verdict("1 plate", false, "no plate setting to try on this client") end
	local keep = ns.chardb or ns.db
	local was, wasBefore, wasHeld = GetCVar(cvar), keep.cvarsBefore, ns.IsCVarHeld(cvar)
	Log(("1 plate: %s is %s, held %s, cvarsBefore had %d"):format(cvar, tostring(was), tostring(wasHeld),
		wasBefore and (function() local n = 0 for _ in pairs(wasBefore) do n = n + 1 end return n end)() or 0))
	keep.cvarsBefore = nil
	SetCVar(cvar, "0")
	ns.EnablePlateRow(kind)
	local on, saved = GetCVar(cvar), keep.cvarsBefore and keep.cvarsBefore[cvar]
	Verdict("1a row writes it on", on == "1" or wasHeld, ("%s now %s (held %s)"):format(cvar, tostring(on), tostring(wasHeld)))
	Verdict("1b yours kept first", saved == "0", ("cvarsBefore %s = %s"):format(cvar, tostring(saved)))
	ns.PutBackOwnCVars()
	local back = GetCVar(cvar)
	Verdict("1c reset puts yours back", back == "0" and keep.cvarsBefore == nil,
		("%s now %s, cvarsBefore %s"):format(cvar, tostring(back), tostring(keep.cvarsBefore)))
	SetCVar(cvar, was)
	keep.cvarsBefore = wasBefore
	Log(("1 plate: %s back to %s"):format(cvar, tostring(GetCVar(cvar))))
end

local function LayoutStep()
	local _, yoursBefore = State("2 before")
	local ok = ns.ResetLayouts()
	local ours, yours = State("2 after reset")
	Verdict("2a reset deletes ours", ok and #ours == 0, ("returned %s, ours left [%s]"):format(tostring(ok),
		table.concat(ours, ", ")))
	Verdict("2b yours all kept", table.concat(yours, "|") == table.concat(yoursBefore, "|"),
		("before [%s] after [%s]"):format(table.concat(yoursBefore, ", "), table.concat(yours, ", ")))
	local active = ns.ActiveLayoutName()
	Verdict("2c on a layout not ours", active ~= nil and not ns.EDIT_MODE_LAYOUTS[active], tostring(active))
	local want = ProfileOurs()
	ns.ApplyProfileLayout()
	ours = State("2 profile's applied")
	if want then
		Verdict("2d profile's made on picking", #ours == 1 and ours[1] == want and ns.ActiveLayoutName() == want,
			("want %s, ours [%s], active %s"):format(want, table.concat(ours, ", "), tostring(ns.ActiveLayoutName())))
	else
		Verdict("2d none made (profile uses yours)", #ours == 0, ("ours [%s]"):format(table.concat(ours, ", ")))
	end
end

local function LoginStep()
	CinematicDB.resetTest = nil
	local want = ProfileOurs()
	local ours = State("3 after login")
	if want then
		Verdict("3 login made no others", #ours == 1 and ours[1] == want, ("want %s, ours [%s]"):format(want,
			table.concat(ours, ", ")))
	else
		Verdict("3 login made none", #ours == 0, ("ours [%s]"):format(table.concat(ours, ", ")))
	end
	ns.Print("reset test done: say \"check log\" (then /reload saves it)")
	Log("done")
end

function ns.ResetTest()
	if not (C_EditMode and C_EditMode.GetLayouts) then return ns.Print("no Edit Mode on this client") end
	if InCombatLockdown() then return ns.Print("not in a fight") end
	local manager = _G.EditModeManagerFrame
	if manager and manager:IsShown() then return ns.Print("close Edit Mode first") end
	CinematicDB.resetTestLog = {}
	Log(("start %s, client %s"):format(date("%Y-%m-%d %H:%M:%S"), tostring(ns.CLIENT)))
	ns.Guard(PlateStep)
	ns.Guard(LayoutStep)
	CinematicDB.resetTest = { stage = 3 }
	ns.Print("steps 1-2 done: now /reload (or Reload on the game's window) for step 3")
end

local resume = CreateFrame("Frame")
resume:RegisterEvent("PLAYER_ENTERING_WORLD")
resume:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	if CinematicDB and CinematicDB.resetTest and CinematicDB.resetTest.stage == 3 then
		C_Timer.After(RESUME, function() ns.Guard(LoginStep) end)
	end
end)
