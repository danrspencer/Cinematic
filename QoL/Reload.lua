local _, ns = ...
local L = ns.L

-- Reloading the UI (Quality of life > General). A Reload button on the
-- screen (reloadButton, off to start with), up even with the UI hidden, and
-- a key for it (Bindings.xml: CINEMATIC_RELOAD). After a reload, what was open
-- comes back (reloadKeepWindows): the settings window at the page you were on
-- (scrolled where it was), the game's windows and bags, and Cinematic's own
-- windows. A /reload of your own does the same. Drag the button to move it
-- (db.reloadPoint, for the account).

local STALE = 120 -- seconds: what was open, saved longer ago than this, isn't reopened

-- Windows by frame name: the addon they're in when it isn't loaded at start,
-- and how to open them (else ShowUIPanel).
local WINDOWS = {
	{ "CharacterFrame", open = function() ToggleCharacter("PaperDollFrame") end },
	{ "WorldMapFrame", open = function() ToggleWorldMap() end },
	{ "QuestLogFrame", open = function() ToggleQuestLog() end },
	{ "SpellBookFrame", open = function() ToggleSpellBook(BOOKTYPE_SPELL) end },
	{ "PlayerSpellsFrame", addon = "Blizzard_PlayerSpells" },
	{ "PlayerTalentFrame", addon = "Blizzard_TalentUI" },
	{ "TalentFrame", addon = "Blizzard_TalentUI" },
	{ "FriendsFrame", open = function() ToggleFriendsFrame() end },
	{ "CommunitiesFrame", addon = "Blizzard_Communities" },
	{ "CollectionsJournal", addon = "Blizzard_Collections" },
	{ "EncounterJournal", addon = "Blizzard_EncounterJournal" },
	{ "AchievementFrame", addon = "Blizzard_AchievementUI" },
	{ "PVEFrame", open = function() PVEFrame_ToggleFrame() end },
	{ "MacroFrame", addon = "Blizzard_MacroUI" },
	{ "AddonList" },
	-- Cinematic's own
	{ "CinematicWelcome", open = function() ns.ShowWelcome() end },
	{ "CinematicLogWindow", open = function() ns.ShowLog() end },
	{ "CinematicTalentCalc", open = function() ns.ToggleTalentCalc() end },
	{ "CinematicRolls", open = function() ns.ToggleRollWindow() end },
}

local function Shown(frame)
	return frame and frame.IsShown and ns.Flag(frame:IsShown()) or false
end

local function BagsOpen()
	if Shown(_G.ContainerFrameCombinedBags) then return true end
	for i = 1, 13 do
		if Shown(_G["ContainerFrame" .. i]) then return true end
	end
	return false
end

-- What's open now, into db.reloadState (for the account: the profile may
-- not be the same one after).
local function Save()
	if not ns.db or not ns.Setting("reloadKeepWindows") then return end
	local state = { at = time(), windows = {}, bags = BagsOpen() }
	for _, window in ipairs(WINDOWS) do
		if Shown(_G[window[1]]) then state.windows[#state.windows + 1] = window[1] end
	end
	local panel = SettingsPanel or InterfaceOptionsFrame
	if Shown(panel) then
		local page, scroll = ns.ShownOptionsPage()
		if page then
			state.page, state.scroll = page, scroll and scroll:GetVerticalScroll() or nil
		elseif SettingsPanel and SettingsPanel.GetCurrentCategory then
			-- (a page of the game's own, or another addon's)
			local category = SettingsPanel:GetCurrentCategory()
			state.category = category and category.GetID and category:GetID() or true
		else
			state.category = true
		end
	end
	ns.db.reloadState = state
end

-- (A window that won't open: the rest still do. Said in the dev copy only.)
local function Try(what, fn)
	local ok, err = pcall(fn)
	if not ok and ns.isDev then ns.Print(("reload: couldn't open %s again (%s)"):format(what, tostring(err))) end
end

local LoadAddOn = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn

-- Opens again what was open, if it was saved just now (this reload's).
local function Restore()
	if not ns.db then return end
	local state = ns.db.reloadState
	ns.db.reloadState = nil
	if not state or not state.at or time() - state.at > STALE or not ns.Setting("reloadKeepWindows") then return end
	local byName = {}
	for _, window in ipairs(WINDOWS) do byName[window[1]] = window end
	for _, name in ipairs(state.windows or {}) do
		local window = byName[name]
		if window then
			Try(name, function()
				if window.addon then LoadAddOn(window.addon) end
				if window.open then
					window.open()
				elseif _G[name] and not Shown(_G[name]) then
					ShowUIPanel(_G[name])
				end
			end)
		end
	end
	if state.bags then Try("bags", OpenAllBags) end
	if state.page then
		Try("the settings", function() ns.OpenOptions(state.page ~= "" and state.page or nil) end)
		-- (Scrolled once the page has laid itself out: tried again a moment later.)
		if state.scroll and state.scroll > 0 then
			local function Scroll()
				local _, scroll = ns.ShownOptionsPage()
				if scroll then
					scroll:SetVerticalScroll(math.min(state.scroll, scroll:GetVerticalScrollRange()))
				end
			end
			C_Timer.After(0.1, Scroll)
			C_Timer.After(0.5, Scroll)
		end
	elseif state.category then
		Try("the settings", function()
			if type(state.category) == "number" and Settings and Settings.OpenToCategory then
				ns.OpenSettingsCategory(state.category)
			elseif SettingsPanel then
				ShowUIPanel(SettingsPanel)
			elseif InterfaceOptionsFrame then
				ShowUIPanel(InterfaceOptionsFrame)
			end
		end)
	end
end

-- Forever blocks ReloadUI from addon code (2026-11-20: ADDON_ACTION_BLOCKED
-- UNKNOWN() via C_UI.Reload, from a timer and from a plain button's click),
-- while a secure button running /reload as a macro, clicked by the player,
-- works (Dev/BlockedLineTest.lua's taint test). So there: the Reload button
-- and the Reload key are such buttons, and a popup of ours that reloads
-- (cineReload = the number of its button that does) gets one laid over that
-- button. Retail as before: ReloadUI. (/cine debug reloadpaths)
ns.reloadBlocked = not ns.isRetail

local secureNext -- a secure click's PreClick running: its macro reloads next

-- Where our code can't reload and no secure click is under way (in a fight,
-- where the cover can't go on; a popup's button taken by Enter or the gamepad).
function ns.ReloadFallback()
	ns.Print(L["Type /reload to finish."])
end

-- Reload the UI (a popup's OnAccept, a reset): what was open saved first.
function ns.Reload()
	Save()
	if secureNext then return end
	if ns.reloadBlocked then return ns.ReloadFallback() end
	ReloadUI()
end

-- A secure button that runs /reload. (Down or up as the game's own buttons,
-- not both: two reloads. upOnly for the button you drag, so pressing to drag
-- it isn't a reload.)
local function SecureReload(name, parent, template, upOnly)
	local button = CreateFrame("Button", name, parent,
		template and ("SecureActionButtonTemplate, " .. template) or "SecureActionButtonTemplate")
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", "/reload")
	if upOnly then
		button:SetAttribute("useOnKeyDown", false)
		button:RegisterForClicks("LeftButtonUp")
	else
		button:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
	end
	return button
end

-- The key (Bindings.xml). (On Forever its keys click CinematicReloadKey
-- instead, below; this is left for when that can't be set up.)
function Cinematic_Reload()
	ns.Reload()
end
-- (Your own /reload too. Saved again by the key's own call: no harm.)
if ReloadUI then hooksecurefunc("ReloadUI", Save) end
if C_UI and C_UI.Reload then hooksecurefunc(C_UI, "Reload", Save) end

-- A popup's reload button covered by a secure one (Forever): its PreClick runs
-- what the popup's button does (ns.Reload left to the macro), then the macro
-- reloads. Over the popup while it's up, off when it goes, and off for a
-- fight (the fight's start event comes just before the lockdown).
local cover, coverTicker
local function PopupButton(dialog, index)
	return dialog["button" .. index] or (dialog.GetButton and dialog:GetButton(index))
		or (dialog.ButtonContainer and dialog.ButtonContainer["Button" .. index])
end
local function Uncover()
	if coverTicker then
		coverTicker:Cancel()
		coverTicker = nil
	end
	if cover and cover:IsShown() and not InCombatLockdown() then cover:Hide() end
end
-- Laid over the button by screen position, from UIParent: Forever won't
-- anchor a secure frame to the popup's own button ("Cannot anchor protected
-- frames to regions", 2026-11-20). Again from the ticker, if the popup moves.
local function PlaceCover(target)
	local ok, left, bottom, width, height, scale = pcall(function()
		return target:GetLeft(), target:GetBottom(), target:GetWidth(), target:GetHeight(),
			target:GetEffectiveScale() / UIParent:GetEffectiveScale()
	end)
	if not (ok and left and bottom and width and height) then return false end
	left, bottom, width, height = left * scale, bottom * scale, width * scale, height * scale
	local at = cover.placedAt
	if at and at[1] == left and at[2] == bottom and at[3] == width and at[4] == height then return true end
	cover.placedAt = { left, bottom, width, height }
	cover:ClearAllPoints()
	cover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
	cover:SetSize(width, height)
	return true
end

local function Cover(dialog, which, index)
	if not ns.reloadBlocked or InCombatLockdown() or not dialog then return end
	local target = PopupButton(dialog, index)
	if not target then return end
	if not cover then
		cover = SecureReload("CinematicReloadCover", UIParent)
		cover:SetFrameStrata("FULLSCREEN_DIALOG")
		cover:Hide()
		cover:SetScript("PreClick", function(self)
			local shown, info = self.dialog, StaticPopupDialogs[self.which]
			local fn = info and (self.index == 3 and info.OnAlt or self.index == 2 and info.OnCancel or info.OnAccept)
			secureNext = true
			if fn and shown then xpcall(fn, geterrorhandler(), shown, shown.data, shown.data2) end
			secureNext = nil
			Save()
			if shown and shown:IsShown() then shown:Hide() end
		end)
		cover:SetScript("OnEnter", function(self) if self.target then self.target:LockHighlight() end end)
		cover:SetScript("OnLeave", function(self) if self.target then self.target:UnlockHighlight() end end)
		cover:RegisterEvent("PLAYER_REGEN_DISABLED")
		cover:RegisterEvent("PLAYER_REGEN_ENABLED")
		cover:SetScript("OnEvent", function(self, event)
			if event == "PLAYER_REGEN_DISABLED" then
				if self:IsShown() then self:Hide() end
			elseif self.dialog and self.dialog:IsShown() and self.dialog.which == self.which then
				Cover(self.dialog, self.which, self.index)
			end
		end)
	end
	cover.dialog, cover.which, cover.index, cover.target = dialog, which, index, target
	cover.placedAt = nil
	if not PlaceCover(target) then return end
	cover:SetFrameLevel(math.min(dialog:GetFrameLevel() + 20, 9000))
	cover:Show()
	if not coverTicker then
		coverTicker = C_Timer.NewTicker(0.2, function()
			if not (cover.dialog:IsShown() and cover.dialog.which == cover.which) then return Uncover() end
			if cover:IsShown() and not InCombatLockdown() then PlaceCover(cover.target) end
		end)
	end
end
function ns.ReloadCover() return cover end -- (the test's)

local function FindPopup(which)
	if StaticPopup_FindVisible then return StaticPopup_FindVisible(which) end
	for i = 1, (_G.STATICPOPUP_NUMDIALOGS or 4) do
		local dialog = _G["StaticPopup" .. i]
		if dialog and dialog:IsShown() and dialog.which == which then return dialog end
	end
end
if ns.reloadBlocked and StaticPopup_Show then
	hooksecurefunc("StaticPopup_Show", function(which)
		local info = StaticPopupDialogs[which]
		if info and info.cineReload then Cover(FindPopup(which), which, info.cineReload) end
	end)
end

-- Asks to reload (a popup with Reload, covered on Forever), or reloads
-- straight away where our code can.
function ns.ReloadOrAsk(text)
	if not ns.reloadBlocked then return ReloadUI() end
	StaticPopupDialogs.CINEMATIC_RELOAD_NOW = {
		text = "%s",
		button1 = RELOADUI or L["Reload"], button2 = L["Later"],
		OnAccept = function() ns.Reload() end,
		cineReload = 1,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	StaticPopup_Show("CINEMATIC_RELOAD_NOW", text)
end

-- The Reload key on Forever: the keys CINEMATIC_RELOAD has click
-- CinematicReloadKey instead (an override, set out of fights and kept through
-- them), unless the Keybinds tab has it off.
local keyOwner, boundKeys
if ns.reloadBlocked then
	local reloadKey = SecureReload("CinematicReloadKey", UIParent)
	reloadKey:SetScript("PreClick", Save)
	_G["BINDING_NAME_CLICK CinematicReloadKey:LeftButton"] = L["Reload the UI"]
	keyOwner = CreateFrame("Frame")
end
local function BindKey()
	if not keyOwner or InCombatLockdown() then return end
	local on = not Cinematic_KeyOn or Cinematic_KeyOn("CINEMATIC_RELOAD")
	local keys = on and table.concat({ GetBindingKey("CINEMATIC_RELOAD") }, " ") or ""
	if keys == boundKeys then return end
	boundKeys = keys
	ClearOverrideBindings(keyOwner)
	for key in keys:gmatch("%S+") do
		SetOverrideBindingClick(keyOwner, false, key, "CinematicReloadKey", "LeftButton")
	end
end

-- The button. No parent, so hiding the UI (Alt+Z, CineMode) leaves it up;
-- scaled as UIParent is so it's the size of the rest. (Forever: a secure
-- one, see above. It can't be shown, hidden or moved in a fight: those wait.)
local button = ns.reloadBlocked and SecureReload("CinematicReloadButton", nil, "UIPanelButtonTemplate", true)
	or CreateFrame("Button", "CinematicReloadButton", nil, "UIPanelButtonTemplate")
local function Locked() return ns.reloadBlocked and InCombatLockdown() end
button:SetSize(64, 20)
button:SetFrameStrata("FULLSCREEN_DIALOG")
button:SetMovable(true)
button:SetClampedToScreen(true)
button:RegisterForDrag("LeftButton")
button:Hide()
if ns.reloadBlocked then
	button:SetScript("PreClick", Save)
else
	button:SetScript("OnClick", Cinematic_Reload)
end
button:SetScript("OnDragStart", function(self) if not Locked() then self:StartMoving() end end)
button:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relativePoint, x, y = self:GetPoint()
	ns.db.reloadPoint = { point, relativePoint, x, y }
end)
button:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:SetText(L["Reload the UI"])
	if ns.Setting("reloadKeepWindows") then
		GameTooltip:AddLine(L["Windows you have open reopen after the reload."], 1, 1, 1, true)
	end
	GameTooltip:AddLine(L["Drag to move it."], 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function Place()
	button:SetText(L["Reload"])
	if Locked() then return end
	button:SetScale(UIParent:GetEffectiveScale())
	button:ClearAllPoints()
	local saved = ns.db and ns.db.reloadPoint
	if saved then
		button:SetPoint(saved[1], nil, saved[2], saved[3], saved[4])
	else
		button:SetPoint("TOP", nil, "TOP", 300, -4)
	end
end

-- Shown while ticked (and its page on), checked now and then: the tick, the
-- page's switch and a profile change all come round to it.
local function Update()
	BindKey()
	if Locked() then return end
	local on = (ns.reloadTestShowButton or ns.Setting("reloadButton")) and true or false
	if on ~= button:IsShown() then button:SetShown(on) end
end

button:RegisterEvent("PLAYER_ENTERING_WORLD")
button:RegisterEvent("UI_SCALE_CHANGED")
button:RegisterEvent("DISPLAY_SIZE_CHANGED")
button:SetScript("OnEvent", function(_, event, _, isReload)
	Place()
	if event == "PLAYER_ENTERING_WORLD" then
		Update()
		if isReload then
			-- (A moment for the settings pages and the rest to be made.)
			C_Timer.After(0.5, Restore)
		elseif ns.db then
			ns.db.reloadState = nil
		end
	end
end)
C_Timer.NewTicker(0.5, Update)
