-- Окошко «Добыча»: открыли тело босса (или ответственный за добычу скинул в рейд список предметов) —
-- видно предметы, «+» добавляет предмет в список розыгрыша, «Добавить всё» — все сразу.
-- Данные — ns.drop (LootList.lua).

local _, ns = ...
local UI = ns.UI

local ROWS, ROW_H, W = 10, 24, 320

local panel, subtitle, more, addAll
local rows = {}

local function MakeRow(i)
	local row = CreateFrame("Button", nil, panel)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -52 - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
	row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
	row:GetHighlightTexture():SetVertexColor(0.45, 0.54, 0.85, 0.2)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetWidth(20)
	row.icon:SetHeight(20)
	row.icon:SetPoint("LEFT", 2, 0)

	row.add = UI.Button(row, "+", 30, function(self)
		local item = self:GetParent().item
		if item then ns.AddDropItem(item) end
	end)
	row.add:SetHeight(20)
	row.add:SetPoint("RIGHT", -2, 0)
	row.done = UI.Text(row, "GameFontDisableSmall", "RIGHT")
	row.done:SetPoint("RIGHT", -4, 0)
	row.done:SetText("в списке")

	row.name = UI.Text(row, "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.add, "LEFT", -6, 0)

	row:SetScript("OnClick", function(self)
		if self.item and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.item.link) end
	end)
	UI.Tooltip(row, function(tt, self)
		if not self.item then return false end
		tt:SetHyperlink(self.item.link)
	end)
	rows[i] = row
end

local function Create()
	panel = CreateFrame("Frame", "RaidMinusDropFrame", UIParent)
	panel:SetWidth(W)
	panel:SetFrameStrata("HIGH")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.DB.dropPos = {point, relPoint, x, y}
	end)
	local pos = ns.DB.dropPos
	if pos then
		panel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 270, -110) -- справа от окна добычи
	end
	tinsert(UISpecialFrames, "RaidMinusDropFrame")

	UI.Panel(panel)
	UI.TitleBar(panel, "Raid|cffff5050Minus|r: добыча")
	subtitle = UI.Text(panel, "GameFontNormal")
	subtitle:SetPoint("TOPLEFT", 10, -34)
	subtitle:SetPoint("RIGHT", panel, "RIGHT", -10, 0)

	for i = 1, ROWS do MakeRow(i) end
	more = UI.Text(panel, "GameFontDisableSmall")

	addAll = UI.Button(panel, "Добавить всё", 120, function() ns.AddDropItems() end)
	local open = UI.Button(panel, "Розыгрыш", 100, function() ns.ShowTab("loot") end)
	open:SetPoint("BOTTOMRIGHT", -8, 8)
	addAll:SetPoint("RIGHT", open, "LEFT", -4, 0)
end

function ns.ShowDropPanel()
	local d = ns.drop
	if not d then return end
	if not panel then Create() end
	subtitle:SetText(d.title)
	local shown = math.min(#d.items, ROWS)
	local left = 0
	for i = 1, ROWS do
		local row, item = rows[i], d.items[i]
		row.item = item
		if item and i <= shown then
			row.icon:SetTexture(item.texture or select(10, GetItemInfo(item.link)) or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.name:SetText(item.link)
			local added = item.added and ns.LootById(item.added)
			if added then
				row.add:Hide()
				row.done:Show()
			else
				row.add:Show()
				row.done:Hide()
				left = left + 1
			end
			row:Show()
		else
			row:Hide()
		end
	end
	if #d.items > ROWS then
		more:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -56 - shown * ROW_H)
		more:SetText(string.format("... и ещё %d (добавятся кнопкой «Добавить всё»)", #d.items - ROWS))
		more:Show()
	else
		more:Hide()
	end
	if left > 0 or #d.items > ROWS then addAll:Enable() else addAll:Disable() end
	panel:SetHeight(52 + shown * ROW_H + (#d.items > ROWS and 16 or 0) + 38)
	panel:Show()
end
