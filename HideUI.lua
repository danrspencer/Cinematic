-- Hide the UI like Blizzard's Alt+Z, but keep the addon's own overlays (tint,
-- letterbox, death screen, time-of-day title) on screen.
--
-- The overlays live on UIParent, so hiding it would take them along. While
-- the UI is hidden they move to a parentless holder that copies UIParent's
-- size and scale, then go back when UIParent shows again (by this key,
-- Blizzard's own, or anything else).
local _, ns = ...
local L = ns.L

local overlays = {}  -- frame -> { parent, strata, level }
local holder
local hidden = false

local function SyncHolder()
	holder:SetScale(UIParent:GetScale())
	holder:ClearAllPoints()
	holder:SetAllPoints(UIParent)
end

local function Move(frame, parent)
	local saved = overlays[frame]
	frame:SetParent(parent)
	frame:SetFrameStrata(saved.strata)
	frame:SetFrameLevel(saved.level)
end

local function Restore()
	if not hidden then
		return
	end
	hidden = false
	for frame, saved in pairs(overlays) do
		Move(frame, saved.parent)
	end
	holder:Hide()
end

local function Detach()
	if not holder then
		holder = CreateFrame("Frame", "CinematicOverlayHolder")
		holder:SetFrameStrata("BACKGROUND")
		holder:SetFrameLevel(0)
		holder:EnableMouse(false)
		holder:RegisterEvent("UI_SCALE_CHANGED")
		holder:RegisterEvent("DISPLAY_SIZE_CHANGED")
		holder:SetScript("OnEvent", SyncHolder)
		UIParent:HookScript("OnShow", Restore)
	end
	SyncHolder()
	holder:Show()
	hidden = true
	for frame in pairs(overlays) do
		Move(frame, holder)
	end
end

-- Called by each overlay when it's created (some are made on demand, perhaps
-- while the UI is already hidden).
function ns.AddOverlay(frame)
	overlays[frame] = {
		parent = frame:GetParent(),
		strata = frame:GetFrameStrata(),
		level = frame:GetFrameLevel(),
	}
	if hidden then
		Move(frame, holder)
	end
end

-- The release and resurrect popups are never hidden: dying, offered a
-- resurrect, or at your corpse or a spirit healer with the UI hidden (by our
-- key or the game's), it comes back. (CineMode's fade still hides the rest:
-- the death camera's included. The popups are never faded.)
-- (SetUIVisibility is blocked in a fight, from an addon: tested. So is
-- UIParent. Here it waits for the fight to end.)
local showAfterFight = false
local function BringBack()
	if UIParent:IsShown() then
		showAfterFight = false
		return
	end
	if InCombatLockdown() then
		showAfterFight = true
		return
	end
	showAfterFight = false
	if SetUIVisibility then
		SetUIVisibility(true)
	else
		UIParent:Show()
	end
	if UIParent:IsShown() then
		Restore()
	end
end
ns.BringBackUI = BringBack

local resWatcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_DEAD", "RESURRECT_REQUEST", "CORPSE_IN_RANGE", "CONFIRM_XP_LOSS",
	"PLAYER_REGEN_ENABLED" }) do
	pcall(resWatcher.RegisterEvent, resWatcher, event) -- (each client that has them)
end
resWatcher:SetScript("OnEvent", function(_, event)
	if event ~= "PLAYER_REGEN_ENABLED" or showAfterFight then
		BringBack()
	end
end)

function ns.ToggleUI()
	if InCombatLockdown() then
		ns.Print(L["can't hide or show the UI in a fight: the game's own key still can"])
		return
	end
	local show = not UIParent:IsShown()
	if not show then
		Detach()
	end
	if SetUIVisibility then
		-- What Blizzard's key uses: hides nameplates too.
		SetUIVisibility(show)
	else
		UIParent:SetShown(show)
	end
	if UIParent:IsShown() then
		Restore() -- shown, or the hide was blocked
	end
end

-- The screenshot key: the shot as Hide UI would show it (tint, letterbox,
-- vignette, depth of field, time-of-day title), then the UI straight back.
-- Hidden by the Hide UI key (or the game's) already, it stays hidden after.
--
-- Hiding waits a frame before the shot so the hidden UI has been drawn. The
-- game's "Screen captured" line comes once the shot is taken, so it's never
-- in it; one still fading from the last shot is hidden first. Bringing the
-- UI back waits for the game to say the shot is done (or failed), with a
-- timeout in case it never says, so the UI can't be left hidden.
local SHOT_TIMEOUT = 3 -- seconds
local shotPending = false -- a shot asked for and not done yet
local shotHidUI = false   -- ...and the UI hidden for it (to bring back)
local shotTimer

local function ShotDone()
	if not shotPending then
		return
	end
	shotPending = false
	if shotTimer then
		shotTimer:Cancel()
		shotTimer = nil
	end
	-- (Unless something brought the UI back in the meantime: Blizzard's key.)
	if shotHidUI then
		BringBack()
	end
	shotHidUI = false
end

local shotWatcher = CreateFrame("Frame")
for _, event in ipairs({ "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED" }) do
	pcall(shotWatcher.RegisterEvent, shotWatcher, event)
end
shotWatcher:SetScript("OnEvent", ShotDone)

function ns.TakeScreenshot()
	if shotPending then
		return
	end
	-- (The UI can't be hidden in a fight: see BringBack.)
	if InCombatLockdown() then
		ns.Print(L["can't take a CineShot in a fight: try again once it's over"])
		return
	end
	shotPending = true
	if ActionStatus then
		ActionStatus:Hide() -- (the game shows it again for this shot's line)
	end
	shotHidUI = UIParent:IsShown()
	if shotHidUI then
		ns.ToggleUI()
	end
	shotTimer = C_Timer.NewTimer(SHOT_TIMEOUT, ShotDone)
	-- (Called from a function of ours: the timer may turn the game's own down.)
	C_Timer.After(0, function() Screenshot() end)
end
