-- /cine debug secreterror: an error whose text is a secret (Forever: another
-- addon's or the game's, relayed by BugGrabber) once made our error catcher
-- read it, "attempt to index local 'text' (a secret string value)" at
-- Diagnostics.lua IsOurs, a warning in the dev box (2026-11-20, x3). Nothing
-- to do but watch, one go:
--   1 make     a secret string, from your mana (secret on Forever, even out of
--              a fight); none on this client = INFO, nothing to test
--   2 ours     the "is this error ours" check given it: no error, "no" (PASS/FAIL)
--   3 report   recording it as an error: no error, logged under a plain stand-in
--              text (PASS/FAIL)
-- Into CinematicDB.secretErrorTestLog. Dev copy only.
local _, ns = ...

function ns.SecretErrorTest()
	if not CinematicDB then return end
	local log = {}
	CinematicDB.secretErrorTestLog = log
	local pass, fail, info = 0, 0, 0
	local function Say(text) log[#log + 1] = ("%s %s"):format(date("%H:%M:%S"), text) end
	local function Verdict(ok, text)
		if ok then pass = pass + 1 else fail = fail + 1 end
		Say(("  verdict %s: %s"):format(ok and "PASS" or "FAIL", text))
	end
	Say(("start: %s (game %s), in a fight %s"):format(ns.isRetail and "retail" or "Forever",
		tostring((select(4, GetBuildInfo()))), tostring(InCombatLockdown())))

	Say("--- 1 of 3: a secret string ---")
	local secret
	if issecretvalue then
		for _, kind in ipairs({ 0, 1, 3, 6 }) do -- (mana, rage, energy, runic power)
			local ok, value = pcall(UnitPower, "player", kind)
			if ok and issecretvalue(value) then
				local fine, text = pcall(function() return "Interface/AddOns/Other/Thing.lua:1: " .. value end)
				if fine and issecretvalue(text) then secret = text break end
				fine, text = pcall(tostring, value)
				if fine and issecretvalue(text) then secret = text break end
			end
		end
	end
	if not secret then
		info = info + 1
		Say("  verdict INFO: no secret string to be had here (no secret power value): nothing to test")
	else
		Say("  made one from a secret power value")

		Say("--- 2 of 3: is it ours ---")
		local ok, ours = pcall(ns.ErrorTextIsOurs, secret)
		Verdict(ok and ours == false, ("check %s, answer %s (no error, false wanted)"):format(ok and "ran" or "ERRORED: " .. tostring(ours),
			ok and tostring(ours) or "-"))

		Say("--- 3 of 3: recorded as an error ---")
		local before = #(ns.db and ns.db.log or {})
		local fine, err = pcall(ns.ReportError, secret, "test stack", false)
		local logged
		for i = before + 1, #(ns.db and ns.db.log or {}) do
			local line = ns.db.log[i]
			if type(line) == "string" and line:find("kept secret by the game", 1, true) then logged = true end
		end
		Verdict(fine and logged, ("report %s, stand-in line in the log %s (no error, yes wanted)"):format(
			fine and "ran" or "ERRORED: " .. tostring(err), logged and "yes" or "no"))
	end
	local line = ("done: %d pass, %d fail, %d info"):format(pass, fail, info)
	Say(line)
	ns.TestPrompt(("Secret error test %s. Say \"check log\"."):format(line), 10)
end
