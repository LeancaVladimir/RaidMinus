-- Вкладка «На проверку»: находки автоматики ждут решения РЛа. Правило с «ставить сразу» сюда не попадает —
-- минус игроку ставится сам. Зелёная галочка — поставить минус, красный крест — отклонить.

local _, ns = ...
local UI = ns.UI

local format, date = string.format, date
local ipairs = ipairs

local ROWS, ROW_H = 16, 20
local READY = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local NOT_READY = "Interface\\RAIDFRAME\\ReadyCheck-NotReady"

local list, countText, acceptAll, rejectAll, empty

local function IconButton(parent, texture, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(18)
	b:SetHeight(18)
	b:SetNormalTexture(texture)
	b:SetHighlightTexture(texture, "ADD")
	b:SetScript("OnClick", onClick)
	return b
end

local function Col(row, x, width, justify)
	local fs = UI.Text(row, "GameFontHighlightSmall", justify)
	fs:SetPoint("LEFT", x, 0)
	fs:SetWidth(width)
	return fs
end

local function MakeRow(row)
	row.time = Col(row, 4, 36)
	row.boss = Col(row, 44, 80)
	row.player = Col(row, 128, 100)
	row.role = Col(row, 230, 34)
	row.text = Col(row, 268, 290)
	row.value = Col(row, 562, 60, "RIGHT")
	row.no = IconButton(row, NOT_READY, function(self) ns.RejectFinding(self:GetParent().item) end)
	row.no:SetPoint("RIGHT", -6, 0)
	row.yes = IconButton(row, READY, function(self) ns.AcceptFinding(self:GetParent().item) end)
	row.yes:SetPoint("RIGHT", row.no, "LEFT", -10, 0)
	UI.Tooltip(row, function(tt, self)
		local f = self.item
		if not f then return false end
		local s = ns.Session()
		local p = s and s.roster[f.player]
		tt:SetText(ns.ColorName(f.player, p and p.class) .. "  " .. ns.ValueColor(f.rule.value))
		tt:AddLine(f.rule.text, 1, 1, 1, true)
		if f.detail then tt:AddLine("Автоматика: " .. f.detail, 0.6, 0.8, 1, true) end
		tt:AddLine(" ")
		tt:AddLine("Галочка — поставить, крест — отклонить", 0.6, 0.6, 0.6)
	end)
end

local function DrawRow(row, f)
	local s = ns.Session()
	local p = s and s.roster[f.player]
	row.time:SetText(date("%H:%M", f.t))
	row.boss:SetText(ns.BossText(f.boss, f.pull))
	row.player:SetText(ns.ColorName(f.player, p and p.class))
	row.role:SetText(ns.RoleName(ns.PlayerRole(f.player), true))
	row.text:SetText(f.rule.text)
	local v = ns.ValueColor(f.rule.value)
	if f.rule.kick then v = "|cffff2020кик|r " .. v end
	row.value:SetText(v)
end

local function Create(f)
	local hint = UI.Text(f, "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", 2, -4)
	hint:SetText("Находки автоматики ждут вашего решения: галочка — поставить минус, крест — отклонить.")
	hint:SetPoint("RIGHT", f, "RIGHT", -150, 0)
	countText = UI.Text(f, "GameFontNormal", "RIGHT")
	countText:SetPoint("TOPRIGHT", -2, -4)

	list = UI.List(f, ROWS, ROW_H, MakeRow)
	list:SetPoint("TOPLEFT", 0, -24)
	list:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	list.redraw = ns.RefreshUI

	empty = UI.Text(f, "GameFontDisable", "CENTER")
	empty:SetPoint("CENTER", list, "CENTER")
	empty:SetText("Нечего проверять.")

	acceptAll = UI.Button(f, "Принять все", 110, function() ns.AcceptAllFindings() end)
	acceptAll:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)
	rejectAll = UI.Button(f, "Отклонить все", 110, function() ns.RejectAllFindings() end)
	rejectAll:SetPoint("LEFT", acceptAll, "RIGHT", 4, 0)
end

local function Update()
	local items = ns.QueueList()
	local s = ns.Session()
	list:Draw(items, DrawRow)
	countText:SetText(format("Ждут: %d · отклонено: %d", #items, s.rejected or 0))
	if #items == 0 then
		empty:Show()
		acceptAll:Disable()
		rejectAll:Disable()
	else
		empty:Hide()
		acceptAll:Enable()
		rejectAll:Enable()
	end
end

ns.RegisterPage("queue", Create, Update)
