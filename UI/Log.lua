-- Вкладка «Журнал»: все записи рейда, новые сверху. Снять минус (с причиной — для споров) и вернуть.
-- Снятая запись остаётся в журнале серой: кто снял и почему.

local _, ns = ...
local UI = ns.UI

local format, tinsert, date = string.format, table.insert, date
local ipairs = ipairs

local ROWS, ROW_H = 18, 18

local list, onlySel, countText, cancelBtn, restoreBtn, selInfo
local onlySelected = false

StaticPopupDialogs["RAIDMINUS_CANCEL"] = {
	text = "Снять: %s\n\nПричина (необязательно):",
	button1 = "Снять",
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 80,
	OnShow = function(self)
		local edit = _G[self:GetName() .. "EditBox"]
		edit:SetText("")
		edit:SetFocus()
	end,
	OnAccept = function(self, ev)
		ns.CancelEvent(ev, strtrim(_G[self:GetName() .. "EditBox"]:GetText()))
	end,
	EditBoxOnEnterPressed = function(self)
		local dialog = self:GetParent()
		ns.CancelEvent(dialog.data, strtrim(self:GetText()))
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	preferredIndex = 3,
}

local function SelectedEvent()
	return ns.ui.event and ns.EventById(ns.ui.event)
end

local function Col(row, x, width, justify)
	local fs = UI.Text(row, "GameFontHighlightSmall", justify)
	fs:SetPoint("LEFT", x, 0)
	fs:SetWidth(width)
	return fs
end

local function MakeRow(row)
	row.time = Col(row, 4, 36)
	row.boss = Col(row, 44, 96)
	row.player = Col(row, 144, 100)
	row.text = Col(row, 248, 300)
	row.value = Col(row, 552, 64, "RIGHT")
	row.by = Col(row, 624, 100)

	row:SetScript("OnClick", function(self)
		if not self.item then return end
		ns.ui.event = ns.ui.event ~= self.item.id and self.item.id or nil
		ns.RefreshUI()
	end)
	UI.Tooltip(row, function(tt, self)
		local ev = self.item
		if not ev then return false end
		tt:SetText(ns.ColorName(ev.player, ev.class) .. "  " .. ns.ValueColor(ev.value))
		tt:AddLine(ev.text, 1, 1, 1, true)
		if ev.kick then tt:AddLine("Пометка: на кик", 1, 0.2, 0.2) end
		if ev.detail then tt:AddLine("Автоматика: " .. ev.detail, 0.6, 0.8, 1, true) end
		tt:AddLine(format("%s · %s · поставил %s", date("%H:%M", ev.t), ns.BossText(ev.boss, ev.pull), tostring(ev.by)), 0.6, 0.6, 0.6)
		if ev.status == "cancelled" then
			tt:AddLine("Снято: " .. tostring(ev.cancelledBy) .. (ev.reason and (" — " .. ev.reason) or ""), 1, 0.5, 0.3, true)
		end
	end)
end

local function DrawRow(row, ev)
	local gone = ev.status == "cancelled"
	local gray = "|cff707070"
	row.time:SetText(date("%H:%M", ev.t))
	row.boss:SetText(ns.BossText(ev.boss, ev.pull))
	row.player:SetText(gone and (gray .. ev.player .. "|r") or ns.ColorName(ev.player, ev.class))
	row.text:SetText(gone and (gray .. ev.text .. "|r") or ev.text)
	local v = ns.ValueColor(ev.value)
	if ev.kick then v = "|cffff2020кик|r " .. v end
	row.value:SetText(gone and (gray .. ns.ValueText(ev.value) .. "|r") or v)
	row.by:SetText(gone and "|cffff8040снято|r" or ("|cff9d9d9d" .. tostring(ev.by) .. "|r"))
	UI.Select(row, ns.ui.event == ev.id)
end

local function Create(f)
	onlySel = UI.Check(f, "Только выбранные игроки", function(v)
		onlySelected = v
		ns.RefreshUI()
	end)
	onlySel:SetPoint("TOPLEFT", 0, 2)
	countText = UI.Text(f, "GameFontHighlightSmall", "RIGHT")
	countText:SetPoint("TOPRIGHT", -2, -4)

	list = UI.List(f, ROWS, ROW_H, MakeRow)
	list:SetPoint("TOPLEFT", 0, -24)
	list:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	list.redraw = ns.RefreshUI

	cancelBtn = UI.Button(f, "Снять", 90, function()
		local ev = SelectedEvent()
		if ev then StaticPopup_Show("RAIDMINUS_CANCEL", ns.EventShort(ev), nil, ev) end
	end)
	cancelBtn:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)
	restoreBtn = UI.Button(f, "Вернуть", 90, function() ns.RestoreEvent(SelectedEvent()) end)
	restoreBtn:SetPoint("LEFT", cancelBtn, "RIGHT", 4, 0)
	selInfo = UI.Text(f, "GameFontDisableSmall")
	selInfo:SetPoint("LEFT", restoreBtn, "RIGHT", 10, 0)
	selInfo:SetPoint("RIGHT", f, "RIGHT", 0, 0)
end

local function Update()
	local s = ns.Session()
	local items, cancelled = {}, 0
	for i = #s.events, 1, -1 do
		local ev = s.events[i]
		if ev.status == "cancelled" then cancelled = cancelled + 1 end
		if not onlySelected or ns.ui.selected[ev.player] then tinsert(items, ev) end
	end
	countText:SetText(format("Записей: %d, снято: %d", #s.events - cancelled, cancelled))
	onlySel:SetChecked(onlySelected)
	list:Draw(items, DrawRow)

	local ev = SelectedEvent()
	if ev then
		cancelBtn[ev.status == "cancelled" and "Disable" or "Enable"](cancelBtn)
		restoreBtn[ev.status == "cancelled" and "Enable" or "Disable"](restoreBtn)
		selInfo:SetText(ns.EventShort(ev))
	else
		cancelBtn:Disable()
		restoreBtn:Disable()
		selInfo:SetText("Выберите запись, чтобы снять или вернуть её.")
	end
end

ns.RegisterPage("log", Create, Update)
