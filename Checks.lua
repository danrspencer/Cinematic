-- Checks before calling: what the game and this client allow, asked ahead,
-- so the code calls only what can work instead of trying it in a pcall and
-- seeing (Tools/pcall-plan.md). Loaded first; needs nothing else.
--
-- What each client has (Tools/pcall-plan.md, /cine debug checks, 2026-11-19):
-- Forever and retail have every check used here. Older clients may have none
-- of them; a missing check means there's nothing to check there (no secret
-- values, no forbidden plates), never an error.
local _, ns = ...

local Check = {}
ns.Check = Check

local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown

-- Values ------------------------------------------------------------------------

-- A secret value (fights, Forever and retail): may be passed on to the game
-- (SetText, SetValue...) but not compared, added or tested for truth.
function Check.Secret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

-- Not nil and not secret: safe to compare and test.
function Check.Known(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- The number, if it's a number and not secret; else nil.
function Check.Number(value)
	if type(value) ~= "number" or (issecretvalue and issecretvalue(value)) then return nil end
	return value
end

-- True only for a true that isn't secret.
function Check.True(value)
	if issecretvalue and issecretvalue(value) then return false end
	return value and true or false
end

-- Frames and regions ------------------------------------------------------------

-- A frame or region we may call methods on: a widget, and not forbidden
-- (forbidden ones, like nameplates in instances, error on almost any call).
function Check.Usable(object)
	if type(object) ~= "table" or type(object.GetObjectType) ~= "function" then return false end
	return not (object.IsForbidden and object:IsForbidden())
end

-- Whether moving, showing or hiding it works now: a protected frame can't be
-- in a fight.
function Check.Movable(frame)
	if not Check.Usable(frame) then return false end
	if not (InCombatLockdown and InCombatLockdown()) then return true end
	return not (frame.IsProtected and frame:IsProtected())
end

-- Whether its place reads as plain numbers (GetPoint, GetLeft, GetCenter...).
-- A secret place can't be compared, and moving it ourselves taints the game's
-- own reads of it (the combat text error, 2026-11-19).
function Check.PlaceKnown(region)
	if not Check.Usable(region) then return false end
	return not (region.IsAnchoringSecret and region:IsAnchoringSecret())
end

-- Whether any value it gives back may be secret (its size, value, text...).
function Check.ValuesKnown(region)
	if not Check.Usable(region) then return false end
	return not (region.HasSecretValues and region:HasSecretValues())
end

-- The client ---------------------------------------------------------------------

-- A function by its path ("C_Secrets.ShouldAurasBeSecret", "GetUnitPitch"),
-- or nil where this client hasn't got it.
local found = {}
function Check.Api(path)
	local fn = found[path]
	if fn ~= nil then return fn or nil end
	local value = _G
	for name in path:gmatch("[^.]+") do
		value = type(value) == "table" and value[name] or nil
	end
	found[path] = type(value) == "function" and value or false
	return found[path] or nil
end

-- Whether this client has the event. IsEventValid (Forever, retail: agreed
-- with registering every time) where there is one; else one try, kept.
local events = {}
local probe
function Check.Event(event)
	local known = events[event]
	if known ~= nil then return known end
	local IsEventValid = Check.Api("C_EventUtils.IsEventValid")
	if IsEventValid then
		known = IsEventValid(event) and true or false
	else
		probe = probe or CreateFrame("Frame")
		-- pcall: older clients have no way to ask, so it's tried once here.
		known = pcall(probe.RegisterEvent, probe, event) and true or false
		probe:UnregisterAllEvents()
	end
	events[event] = known
	return known
end

-- frame:RegisterEvent(event) where the client has it; whether it did.
function Check.RegisterEvent(frame, event)
	if not Check.Event(event) then return false end
	frame:RegisterEvent(event)
	return true
end

-- frame:RegisterUnitEvent(event, ...) where the client has it; whether it did.
function Check.RegisterUnitEvent(frame, event, ...)
	if not Check.Event(event) then return false end
	frame:RegisterUnitEvent(event, ...)
	return true
end

-- Whether this client has the template. GetTemplateInfo (Forever, retail:
-- agreed with CreateFrame every time) where there is one; else one try, kept.
local templates = {}
function Check.Template(template, kind)
	local known = templates[template]
	if known ~= nil then return known end
	local GetTemplateInfo = Check.Api("C_XMLUtil.GetTemplateInfo")
	if GetTemplateInfo then
		known = GetTemplateInfo(template) ~= nil
	else
		-- pcall: older clients have no way to ask, so it's tried once here.
		local made, frame = pcall(CreateFrame, kind or "Frame", nil, nil, template)
		if made and frame and frame.Hide then frame:Hide() end
		known = made and true or false
	end
	templates[template] = known
	return known
end
