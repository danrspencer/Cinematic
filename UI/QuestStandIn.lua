-- Cinematic: a stand-in for a tracked quest the game's tracker has no room
-- to draw (Quest tracker page, "Show just that quest"). A full tracker lists
-- only as many quests as fit on the screen (16 of 20 on Forever, tested
-- 2026-11-18: no height change makes it draw more), so a quest past the end
-- has no block: a reveal for it showed the whole tracker, then nothing. Now
-- Frames.lua's ns.QuestFocusTick asks for its stand-in: a copy made from a
-- quest the tracker did draw (the model), its name's and objectives' fonts,
-- colors, shadows, offsets, wrap width and line spacing, and its quest icon
-- (a model in the same state: done or not), drawn with that quest's own
-- name and objectives at the top of the tracker, or under the quests the
-- reveal shows there. A name the model's has a level put in front of (as
-- Questie does: "[24] Supplies from Darkshire") gets this quest's level the
-- same way, in its difficulty color. Read-only on the game's frames: ours
-- are copies on a holder of our own. Nothing to copy from (no drawn quest):
-- no stand-in, and the reveal ends.
local _, ns = ...

local REBUILD = 0.2 -- seconds between rebuilds (the placing follows every pass)
local GAP = 10 -- between quests stacked (tracker units, as Close the gaps)

local holder, holderScale
local textures, texts = {}, {}
local usedTextures, usedTexts = 0, 0
local builtAt, builtFor = -math.huge, ""
ns.questStandInProblem = nil -- (the last reason one couldn't be drawn: /cine debug questfocus)

local function IsForbidden(frame)
	return frame.IsForbidden and frame:IsForbidden()
end

local function Visible(frame)
	if type(frame) ~= "table" or not frame.IsVisible or IsForbidden(frame) then return false end
	local ok, shown = pcall(frame.IsVisible, frame)
	return ok and ns.Flag(shown) and true or false
end

local function Plain(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

-- A frame's rect on the screen (pixels), or nil.
local function ScreenRect(frame)
	local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
	local okScale, scale = pcall(frame.GetEffectiveScale, frame)
	if ok and okScale and Plain(left) and Plain(bottom) and Plain(width) and Plain(height) and Plain(scale) then
		return left * scale, bottom * scale, width * scale, height * scale
	end
end

local function NewTexture()
	usedTextures = usedTextures + 1
	local copy = textures[usedTextures]
	if not copy then
		copy = holder:CreateTexture(nil, "ARTWORK")
		textures[usedTextures] = copy
	end
	return copy
end

local function NewText()
	usedTexts = usedTexts + 1
	local copy = texts[usedTexts]
	if not copy then
		copy = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		texts[usedTexts] = copy
	end
	return copy
end

-- (Screen pixels to the holder's units.)
local function Put(copy, left, top, width, height)
	copy:ClearAllPoints()
	copy:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", left / holderScale, top / holderScale)
	if width then copy:SetWidth(width / holderScale) end
	if height then copy:SetHeight(height / holderScale) end
end

local function CopyTexture(region, left, top)
	local _, _, width, height = ScreenRect(region)
	if not width then return end
	local copy = NewTexture()
	Put(copy, left, top, width, height)
	local atlas = region.GetAtlas and region:GetAtlas()
	if atlas then
		copy:SetAtlas(atlas)
	else
		local file = region:GetTexture()
		if not file then copy:Hide() return end
		copy:SetTexture(file)
	end
	copy:SetTexCoord(region:GetTexCoord())
	copy:SetVertexColor(region:GetVertexColor())
	if region.IsDesaturated then copy:SetDesaturated(region:IsDesaturated()) end
	copy:SetBlendMode(region:GetBlendMode())
	copy:SetDrawLayer(region:GetDrawLayer())
	copy:SetAlpha(region:GetAlpha())
	copy:Show()
end

-- A copy of a font string's look (not its words), its width the source's on
-- screen (so it wraps the same); r, g, b: another color. Returns its height.
local function CopyText(region, left, top, words, r, g, b)
	local _, _, width = ScreenRect(region)
	local okScale, scale = pcall(region.GetEffectiveScale, region)
	if not (width and okScale and Plain(scale)) then return 0 end
	local copy = NewText()
	local font, size, flags = region:GetFont()
	copy:SetText("")
	local object = region:GetFontObject()
	if object then copy:SetFontObject(object) end
	if font then copy:SetFont(font, size * scale / holderScale, flags) end
	copy:SetJustifyH(region:GetJustifyH())
	copy:SetJustifyV("TOP")
	copy:SetWordWrap(region:CanWordWrap())
	if region.GetSpacing then copy:SetSpacing(region:GetSpacing()) end
	copy:SetShadowColor(region:GetShadowColor())
	copy:SetShadowOffset(region:GetShadowOffset())
	copy:SetDrawLayer(region:GetDrawLayer())
	if r then
		copy:SetTextColor(r, g, b, 1)
	else
		copy:SetTextColor(region:GetTextColor())
	end
	Put(copy, left, top, width)
	copy:SetText(words)
	copy:SetAlpha(region:GetAlpha())
	copy:Show()
	local height = copy:GetStringHeight()
	return Plain(height) and height * holderScale or 0
end

-- A block's objective lines, top to bottom (each with .Text), and its quest
-- icon. Retail's and Forever's blocks keep their lines in usedLines.
local lineList = {}
local function Lines(block)
	wipe(lineList)
	if type(block.usedLines) == "table" then
		for _, line in pairs(block.usedLines) do
			if type(line) == "table" and type(line.Text) == "table" and Visible(line) then
				lineList[#lineList + 1] = line
			end
		end
	end
	table.sort(lineList, function(a, b)
		local _, ab, _, ah = ScreenRect(a)
		local _, bb, _, bh = ScreenRect(b)
		return (ab or 0) + (ah or 0) > (bb or 0) + (bh or 0)
	end)
	return lineList
end

local function Icon(block)
	local button = block.poiButton or block.POIButton
	if Visible(button) then return button end
end

local function QuestComplete(questID)
	local log = C_QuestLog
	if log and log.ReadyForTurnIn then
		local ok, ready = pcall(log.ReadyForTurnIn, questID)
		if ok and ready ~= nil then return ns.Flag(ready) and true or false end
	end
	if log and log.IsComplete then
		local ok, done = pcall(log.IsComplete, questID)
		return ok and ns.Flag(done) and true or false
	end
	return false
end

-- The model: a drawn quest block with a name and a line, in the same state if
-- there's one (its icon then matches).
local function Model(complete)
	local section = _G.QuestObjectiveTracker
	if type(section) ~= "table" or type(section.usedBlocks) ~= "table" then return nil, "no quest section" end
	local best, other
	for _, blocks in pairs(section.usedBlocks) do
		if type(blocks) == "table" then
			for id, block in pairs(blocks) do
				if type(id) == "number" and type(block) == "table" and type(block.HeaderText) == "table"
					and Visible(block) and #Lines(block) > 0 then
					if QuestComplete(id) == complete then
						best = best or { block = block, id = id }
					else
						other = other or { block = block, id = id }
					end
				end
			end
		end
	end
	local model = best or other
	if not model then return nil, "no drawn quest to copy" end
	model.sameState = best ~= nil
	return model
end

local function QuestTitle(questID)
	local log = C_QuestLog
	local title = log and log.GetTitleForQuestID and log.GetTitleForQuestID(questID)
	if type(title) == "string" and title ~= "" then return title end
end

local function QuestLevel(questID)
	local log = C_QuestLog
	local index = log and log.GetLogIndexForQuestID and log.GetLogIndexForQuestID(questID)
	local info = index and log.GetInfo and log.GetInfo(index)
	return info and Plain(info.level) and info.level or nil, index
end

-- The name as the model's is written: whatever's put round its title (a
-- level in front, as Questie does), with this quest's level in it.
local function Name(model, questID)
	local title = QuestTitle(questID)
	if not title then return nil end
	local okText, shown = pcall(model.block.HeaderText.GetText, model.block.HeaderText)
	local modelTitle = QuestTitle(model.id)
	if not (okText and type(shown) == "string" and modelTitle) then return title end
	local plain = shown:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local at = plain:find(modelTitle, 1, true)
	if not at or at == 1 then return title end
	local before = plain:sub(1, at - 1)
	local level = QuestLevel(questID)
	if not level then return title end
	local r, g, b
	if _G.GetQuestDifficultyColor then
		local color = _G.GetQuestDifficultyColor(level)
		if color then r, g, b = color.r, color.g, color.b end
	end
	return (before:gsub("%d+", tostring(level), 1)) .. title, r, g, b
end

-- Its lines as the tracker words them: each objective, or the turn-in line.
local function ObjectiveLines(questID, out)
	wipe(out)
	if QuestComplete(questID) then
		local _, index = QuestLevel(questID)
		local text = index and _G.GetQuestLogCompletionText and _G.GetQuestLogCompletionText(index)
		out[1] = { text = (type(text) == "string" and text ~= "") and text or (_G.QUEST_WATCH_QUEST_READY or "Ready for turn-in") }
		return out
	end
	local objectives = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)
	for _, objective in ipairs(objectives or {}) do
		if type(objective.text) == "string" and objective.text ~= "" then
			out[#out + 1] = { text = objective.text, finished = objective.finished }
		end
	end
	return out
end

local DONE_COLOR = { 0.6, 0.6, 0.6 }
local lines = {}
-- One quest's stand-in under top (screen pixels); returns its bottom.
local function DrawQuest(model, questID, top)
	local block = model.block
	local left, bottom, _, height = ScreenRect(block)
	if not left then return nil, "model unreadable" end
	local blockTop = bottom + height
	-- (Every part at its place under the model block's top.)
	local function At(region)
		local rLeft, rBottom, _, rHeight = ScreenRect(region)
		if rLeft then return rLeft, top - (blockTop - (rBottom + rHeight)) end
	end
	local name, r, g, b = Name(model, questID)
	if not name then return nil, "no name for quest " .. questID end
	local x, y = At(block.HeaderText)
	if not x then return nil, "model name unreadable" end
	local lowest = y - CopyText(block.HeaderText, x, y, name, r, g, b)
	local icon = model.sameState and Icon(block)
	if icon then
		for _, region in ipairs({ icon:GetRegions() }) do
			if region:GetObjectType() == "Texture" and Visible(region) then
				local tx, ty = At(region)
				if tx then CopyTexture(region, tx, ty) end
			end
		end
	end
	-- (The lines: the model's first one's look and place, each next one
	-- under the last as far down as the model's second is under its first.)
	local modelLines = Lines(block)
	local first = modelLines[1]
	local firstX, firstY = At(first.Text)
	if not firstX then return nil, "model line unreadable" end
	local step = 0
	if modelLines[2] then
		local _, secondY = At(modelLines[2].Text)
		local _, _, _, firstHeight = ScreenRect(first.Text)
		if secondY and firstHeight then step = (firstY - secondY) - firstHeight end
	end
	step = math.max(step, 2)
	local dash = type(first.Dash) == "table" and Visible(first.Dash) and first.Dash
	local dashX, dashY = 0, 0
	if dash then
		local dx, dy = At(dash)
		if dx then dashX, dashY = dx - firstX, dy - firstY else dash = nil end
	end
	local y2 = firstY
	for _, line in ipairs(ObjectiveLines(questID, lines)) do
		local lr, lg, lb
		if line.finished then
			local colors = _G.OBJECTIVE_TRACKER_COLOR
			local done = colors and colors.Complete
			lr, lg, lb = done and done.r or DONE_COLOR[1], done and done.g or DONE_COLOR[2], done and done.b or DONE_COLOR[3]
		end
		if dash then CopyText(dash, firstX + dashX, y2 + dashY, dash:GetText() or "-", lr, lg, lb) end
		local used = CopyText(first.Text, firstX, y2, line.text, lr, lg, lb)
		lowest = math.min(lowest, y2 - used)
		y2 = y2 - used - step
	end
	return lowest
end

function ns.QuestStandInHide()
	if holder and holder:IsShown() then holder:Hide() end
	builtFor = ""
end

-- Draws the stand-ins for quests (a list of quest IDs) on the tracker, from
-- under below (screen pixels; nil: the top of its first quest). True if any.
function ns.QuestStandIn(tracker, quests, below)
	if #quests == 0 then
		ns.QuestStandInHide()
		return false
	end
	if not holder then
		holder = CreateFrame("Frame", nil, UIParent)
		holder:SetAllPoints(UIParent)
	end
	local ok, problem = pcall(function()
		holder:SetFrameStrata(tracker:GetFrameStrata())
		holder:SetFrameLevel(math.min(9000, tracker:GetFrameLevel() + 50))
		local scale = tracker:GetEffectiveScale()
		local parentAlpha = UIParent:GetEffectiveAlpha()
		holder:SetAlpha(parentAlpha > 0 and math.min(1, tracker:GetEffectiveAlpha() / parentAlpha) or 0)
		local key = table.concat(quests, ",") .. "@" .. tostring(below)
		local now = GetTime()
		if key == builtFor and now - builtAt < REBUILD and scale == holderScale then return end
		holderScale = scale
		holder:SetScale(scale / UIParent:GetEffectiveScale())
		usedTextures, usedTexts = 0, 0
		local model, why = Model(QuestComplete(quests[1]))
		if not model then error(why, 0) end
		local top = below
		if not top then
			local left, bottom, _, height = ScreenRect(model.block)
			if not left then error("model unreadable", 0) end
			-- (The top of the tracker's first quest: the highest drawn block.)
			top = bottom + height
			local section = _G.QuestObjectiveTracker
			for _, blocks in pairs(section.usedBlocks) do
				if type(blocks) == "table" then
					for _, block in pairs(blocks) do
						if type(block) == "table" and Visible(block) then
							local _, b, _, h = ScreenRect(block)
							if b and b + h > top then top = b + h end
						end
					end
				end
			end
		end
		for i, questID in ipairs(quests) do
			if i > 1 then model = Model(QuestComplete(questID)) or model end
			local lowest, failed = DrawQuest(model, questID, top)
			if not lowest then error(failed, 0) end
			top = lowest - GAP * holderScale
		end
		for i = usedTextures + 1, #textures do textures[i]:Hide() end
		for i = usedTexts + 1, #texts do texts[i]:Hide() end
		builtFor, builtAt = key, now
	end)
	if not ok then
		ns.questStandInProblem = tostring(problem)
		ns.QuestStandInHide()
		return false
	end
	holder:Show()
	return true
end
