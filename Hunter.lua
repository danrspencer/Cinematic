-- Cinematic: right-click pulls with Auto Shot (hunterRightClickShot, Quality of
-- life page, Hunter section). Classic Era only: retail's right-click already
-- shoots, and WoW Forever has the game's own Auto Attack/Auto Shot setting.
--
-- Addons can't cast by themselves, so this works through a secure button your
-- own click lands on: while the mouse is on a living enemy, right-click is
-- bound to a button that targets it and starts Auto Shot. In melee range Auto
-- Shot fails ("too close") and the swing carries on. Out of combat that's done
-- here, watching the mouse buttons too. In a fight bindings only change from
-- secure code, so a state driver ([combat,@mouseover,harm,nodead]) does it
-- there: the game checks that a few times a second, so a very quick
-- right-click on a new enemy can still be a melee one.
local _, ns = ...

if not ns.isClassicEra then
	return
end

local AUTO_SHOT = 75

local function AutoShotName()
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(AUTO_SHOT)
		or GetSpellInfo and GetSpellInfo(AUTO_SHOT)
	return type(name) == "string" and name or "Auto Shot"
end

-- (Click on key down or up, as the game's action buttons do, not both: that
-- would run it twice. The "!" keeps Auto Shot on when it already is, rather
-- than toggling it off.)
local pullButton = CreateFrame("Button", "CinematicHunterPullButton", UIParent, "SecureActionButtonTemplate")
pullButton:SetAttribute("type", "macro")
pullButton:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")

local BOTH_BUTTONS_WINDOW = 0.25 -- seconds: a left-click this close before the right one counts as both
local leftDownAt = -math.huge
local bound = false -- right-click is ours

local function Wanted()
	return ns.Setting("hunterRightClickShot") and true or false
end

local function SetPull(on)
	if bound == on or InCombatLockdown() then
		return
	end
	bound = on
	if on then
		SetOverrideBindingClick(pullButton, true, "BUTTON2", pullButton:GetName())
	else
		ClearOverrideBindings(pullButton)
	end
end

-- The mouse on a living enemy you could shoot, and nothing in the way.
local function WantPull()
	if not Wanted() or ns.Flag(UnitAffectingCombat("player")) then
		return false
	end
	if IsMouseButtonDown("LeftButton") or GetTime() - leftDownAt < BOTH_BUTTONS_WINDOW then
		return false -- (both buttons run you forward)
	end
	if ns.Flag(UnitIsDeadOrGhost("player")) or (IsMounted and ns.Flag(IsMounted()))
		or ns.Flag(UnitOnTaxi("player")) then
		return false
	end
	if not ns.Flag(UnitExists("mouseover")) then
		return false
	end
	-- (Dead: right-click loots it.)
	if ns.Flag(UnitIsDead("mouseover")) then
		return false
	end
	return ns.Flag(UnitCanAttack("player", "mouseover"))
end

-- In a fight: its own binding, set and cleared by the state driver.
local combatHandler = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
combatHandler:SetAttribute("_onstate-pull", [[
	if newstate == "on" then
		self:SetBindingClick(true, "BUTTON2", "CinematicHunterPullButton")
	else
		self:ClearBindings()
	end
]])
local driverOn = false

-- The state driver follows the setting (not in a fight: once it's over).
local function ApplyDriver()
	local want = Wanted()
	if want == driverOn or InCombatLockdown() then
		return
	end
	driverOn = want
	if want then
		RegisterStateDriver(combatHandler, "pull", "[nocombat] off; [@mouseover,harm,nodead,nomounted] on; off")
	else
		UnregisterStateDriver(combatHandler, "pull")
		combatHandler:SetAttribute("state-pull", "off")
		ClearOverrideBindings(combatHandler)
	end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
watcher:SetScript("OnEvent", function(_, event, mouseButton)
	if event == "GLOBAL_MOUSE_DOWN" then
		if mouseButton == "LeftButton" then
			leftDownAt = GetTime()
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		SetPull(false) -- a fight: the state driver's binding takes over (let go just before lockdown)
	elseif event == "PLAYER_LOGIN" then
		if select(2, UnitClass("player")) ~= "HUNTER" then
			watcher:UnregisterAllEvents()
			return
		end
		pullButton:SetAttribute("macrotext", "/target mouseover\n/startattack\n/cast !" .. AutoShotName())
		ApplyDriver()
		watcher:SetScript("OnUpdate", ns.Profiled("Hunter right-click watch", function()
			-- Right button held: the binding stays as it was pressed (swapping it
			-- mid-press would leave a right-drag turning stuck).
			if not IsMouseButtonDown("RightButton") then
				SetPull(WantPull())
			end
			ApplyDriver() -- (the setting changed: page, profile or Reset)
		end))
	end
end)
