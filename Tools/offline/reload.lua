-- Reload paths (dev tool, offline, Lua 5.1 via Tools/offline/run.py):
--   python -I Tools/offline/run.py Tools/offline/reload.lua <forever|retail>
-- QoL/Reload.lua on the stand-in. Forever (ReloadUI blocked from our code):
-- a popup of ours that reloads (cineReload) gets the secure /reload button laid
-- over the right button, whose PreClick runs the popup's own work without our
-- ReloadUI; ns.Reload with no secure click says "type /reload" instead; the
-- Reload button and key are secure /reload buttons. Retail: ns.Reload calls
-- ReloadUI and nothing is covered. Says PASS or FAIL per check.
local client = arg and arg[1] or "forever"
local reloads, printed = 0, {}
local popups = {}
-- luacheck: push ignore 111 112 113 121 122 212
local ns = dofile("Tools/offline/load.lua")(client, nil, function()
	-- (A real hooksecurefunc for the popup hook only: the stand-in's does nothing.)
	hooksecurefunc = function(a, b, c)
		local t, name, fn = _G, a, b
		if type(a) == "table" then t, name, fn = a, b, c end
		if t ~= _G or name ~= "StaticPopup_Show" then return end
		local orig = t[name]
		t[name] = function(...)
			local r = { orig(...) }
			fn(...)
			return unpack(r)
		end
	end
	ReloadUI = function() reloads = reloads + 1 end
	StaticPopupDialogs = {}
	StaticPopup_Show = function(which)
		local dialog = popups[which]
		if not dialog then
			dialog = CreateFrame("Frame", nil, UIParent)
			dialog.button1 = CreateFrame("Button", nil, dialog)
			dialog.button2 = CreateFrame("Button", nil, dialog)
			dialog.button3 = CreateFrame("Button", nil, dialog)
			popups[which] = dialog
		end
		dialog.which = which
		dialog:Show()
		return dialog
	end
	StaticPopup_FindVisible = function(which)
		local d = popups[which]
		return d and d:IsShown() and d or nil
	end
	InCombatLockdown = function() return false end
end)
-- luacheck: pop
local origPrint = ns.Print
ns.Print = function(text, ...) printed[#printed + 1] = tostring(text) return origPrint(text, ...) end

local fails = 0
local function Check(name, ok, detail)
	if not ok then fails = fails + 1 end
	print((ok and "PASS " or "FAIL ") .. client .. " " .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
end
local blocked = client ~= "retail"
Check("reloadBlocked as the client", ns.reloadBlocked == blocked, tostring(ns.reloadBlocked))

-- A popup that reloads from button 1, and one from button 3 (Reset Settings).
local ran = {}
StaticPopupDialogs.TEST_ONE = { OnAccept = function() ran.one = true ns.Reload() end, cineReload = 1 }
StaticPopupDialogs.TEST_ALT = { OnAccept = function() ran.wrong = true end,
	OnAlt = function() ran.alt = true ns.Reload() end, cineReload = 3 }
StaticPopupDialogs.TEST_PLAIN = { OnAccept = function() end }

reloads = 0
local one = StaticPopup_Show("TEST_ONE")
local cover = ns.ReloadCover()
if blocked then
	Check("popup covered", cover and cover:IsShown())
	local pre = cover and cover:GetScript("PreClick")
	if pre then pre(cover, "LeftButton", false) end
	Check("cover click ran OnAccept", ran.one)
	Check("cover click: no ReloadUI from our code (the macro does it)", reloads == 0, reloads)
	Check("cover click hid the popup", not one:IsShown())

	ran = {}
	StaticPopup_Show("TEST_ALT")
	cover = ns.ReloadCover()
	pre = cover:GetScript("PreClick")
	pre(cover, "LeftButton", false)
	Check("button 3 cover ran OnAlt, not OnAccept", ran.alt and not ran.wrong)

	-- No secure click (Enter, gamepad, in a fight): the message, no ReloadUI.
	local before = #printed
	reloads = 0
	ns.Reload()
	Check("ns.Reload alone: no ReloadUI", reloads == 0, reloads)
	Check("ns.Reload alone: says type /reload", #printed > before and printed[#printed]:find("/reload") ~= nil,
		printed[#printed])

	-- A plain popup isn't covered.
	ns.ReloadCover():Hide()
	StaticPopup_Show("TEST_PLAIN")
	Check("a popup without cineReload isn't covered", not ns.ReloadCover():IsShown())

	Check("Reload key button made", rawget(_G, "CinematicReloadKey") ~= nil)
	Check("Reload button has PreClick (secure)", _G.CinematicReloadButton:GetScript("PreClick") ~= nil)

	-- ns.ReloadOrAsk: a covered popup, no ReloadUI.
	reloads = 0
	ns.ReloadOrAsk("x")
	Check("ReloadOrAsk shows a covered popup", popups.CINEMATIC_RELOAD_NOW and popups.CINEMATIC_RELOAD_NOW:IsShown()
		and ns.ReloadCover().which == "CINEMATIC_RELOAD_NOW" and reloads == 0)
else
	Check("retail: nothing covered", cover == nil)
	reloads = 0
	local accept = StaticPopupDialogs.TEST_ONE.OnAccept
	accept(one)
	Check("retail: OnAccept reloads with ReloadUI", reloads == 1, reloads)
	reloads = 0
	ns.ReloadOrAsk("x")
	Check("retail: ReloadOrAsk reloads straight away", reloads == 1, reloads)
	Check("retail: Reload key button not made", rawget(_G, "CinematicReloadKey") == nil)
	Check("retail: Reload button clicks as before", _G.CinematicReloadButton:GetScript("OnClick") ~= nil)
end

-- Every popup of ours whose button reloads is marked.
for _, which in ipairs({ "CINEMATIC_LANGUAGE_RELOAD", "CINEMATIC_SUPPORT_RELOAD", "CINEMATIC_LAYOUT_RELOAD",
	"CINEMATIC_BARS_RELOAD", "CINEMATIC_ADDON_RESET", "CINEMATIC_ADDON_RESET_ALL" }) do
	local info = StaticPopupDialogs[which]
	if info then
		Check(which .. " marked cineReload", info.cineReload ~= nil)
		Check(which .. " no bare ReloadUI", info.OnAccept ~= ReloadUI)
	else
		print("SKIP " .. which .. " (not made in the stand-in)")
	end
end

print(fails == 0 and "ALL PASS" or (fails .. " FAIL"))
os.exit(fails == 0 and 0 or 1)
