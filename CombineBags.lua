-- Cinematic: Combine profession bags (combineProfessionBags, Quality of life >
-- General; WoW Forever only, off by default). The game's Combine Bags leaves
-- the bag in the fifth slot (a profession bag on Forever) in its own window:
-- its combined window takes bags 0 to ENDING_BAG_INDEX, which is 4, and only
-- the gamepad UI widens it to every bag (ContainerFrame.lua sets it to
-- NUM_TOTAL_BAG_FRAMES there). Ticked, we widen it the same way, so that bag's
-- slots join the Combined Backpack (at the bottom: the game lays out the
-- highest bag first, from the bottom right) and its own window stops opening.
-- Its empty slots look like the rest: in the combined window the game draws an
-- empty slot with its bag's icon, which for a profession bag is that bag (a
-- creature head for a skinning bag); we give them the backpack's (user's pick).
--
-- Item use stays the game's: buttons take their bag through an attribute
-- (ContainerFrameItemButtonMixin:SetBagID), and C_Container.UseContainerItem
-- isn't protected.
local _, ns = ...

if ns.isRetail or not ContainerFrameCombinedBags or type(ENDING_BAG_INDEX) ~= "number"
	or type(NUM_BAG_FRAMES) ~= "number" or type(NUM_TOTAL_BAG_FRAMES) ~= "number"
	or NUM_TOTAL_BAG_FRAMES <= NUM_BAG_FRAMES then
	return
end

ns.CanCombineProfessionBags = true

local bags = ContainerFrameCombinedBags
local gameEnd = ENDING_BAG_INDEX -- the game's own (4; every bag with the gamepad UI)
local gameIsBagOpen = bags.IsBagOpen
local applied = false

-- (ContainerFrameItemButtonMixin:GetBagIcon's for the backpack.)
local BACKPACK_ICON = [[Interface\Icons\ui-hud-actionbar-bag]]

-- The combined window says which bags it holds for the bag buttons' highlight
-- and IsBagOpen; the game's stops at NUM_BAG_FRAMES, which would have opening
-- every bag build it again for the fifth.
local function CombinedIsBagOpen(self, id)
	if self:IsShown() and type(id) == "number" and id <= ENDING_BAG_INDEX then
		return id
	end
	return nil
end

local function IsExtraBag(bag)
	return type(bag) == "number" and bag > NUM_BAG_FRAMES and bag <= NUM_TOTAL_BAG_FRAMES
end

-- After the game draws a slot empty: in the combined window, the profession
-- bag's get the backpack's icon (its color and grey the game's).
local function EmptyLikeTheRest(button)
	if not applied or not button.EmptyBagIcon or not (button.IsCombined and button:IsCombined()) then return end
	if IsExtraBag(button.GetBagID and button:GetBagID()) then
		button.EmptyBagIcon:SetTexture(BACKPACK_ICON)
	end
end

local function Hook(button)
	if button.SetAppearanceToEmptyBagSlot and not button.cinematicEmptyHooked then
		button.cinematicEmptyHooked = true
		hooksecurefunc(button, "SetAppearanceToEmptyBagSlot", function(self) ns.Guard(EmptyLikeTheRest, self) end)
	end
end

-- Item buttons copy the mixin's methods when made: hooking the mixin covers
-- the ones made from now on, and the window's own the ones made already.
if ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.SetAppearanceToEmptyBagSlot then
	hooksecurefunc(ContainerFrameItemButtonMixin, "SetAppearanceToEmptyBagSlot",
		function(self) ns.Guard(EmptyLikeTheRest, self) end)
end
local function HookMadeButtons()
	if bags.itemButtonPool and bags.itemButtonPool.EnumerateActive then
		for button in bags.itemButtonPool:EnumerateActive() do
			if button.SetAppearanceToEmptyBagSlot ~= ContainerFrameItemButtonMixin.SetAppearanceToEmptyBagSlot then
				Hook(button)
			end
		end
	end
end

local function Wanted()
	return ns.Setting("combineProfessionBags") and true or false
end

-- Opens what was open again after the switch, so the bag is in (or out of)
-- the combined window at once.
local function Sync()
	local want = Wanted()
	if want == applied then return end
	-- (The gamepad UI already shows every bag combined.)
	if gameEnd >= NUM_TOTAL_BAG_FRAMES then return end
	local wasOpen = IsAnyBagOpen and IsAnyBagOpen()
	if wasOpen and CloseAllBags then CloseAllBags() end
	applied = want
	ENDING_BAG_INDEX = want and NUM_TOTAL_BAG_FRAMES or gameEnd
	bags.IsBagOpen = want and CombinedIsBagOpen or gameIsBagOpen -- luacheck: ignore 122
	HookMadeButtons()
	if wasOpen and OpenAllBags then OpenAllBags() end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	ns.Guard(Sync)
	-- (Settings are read live: a tick, a profile load or the page's switch
	-- reaches the bags within a second.)
	C_Timer.NewTicker(1, function() ns.Guard(Sync) end)
end)
