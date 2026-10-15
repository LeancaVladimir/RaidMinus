-- Вкладка «Минусы»: слева состав рейда с суммами, справа правила босса, «Общее» и «Плюсы».
-- Клик по игроку — выбрать (Ctrl — несколько, Shift — весь класс), клик по правилу — поставить выбранным.

local _, ns = ...
local UI = ns.UI

local format, tinsert, tconcat = string.format, table.insert, table.concat
local ipairs, pairs = ipairs, pairs

local ROSTER_ROWS, RULE_ROWS, ROW_H = 19, 17, 18

local roster, rules, rosterTitle, selText, bossText, valueEdit, textEdit
local rosterItems = {}

local function BossKeys()
	local out = {}
	for _, sec in ipairs(ns.SECTIONS) do
		if not sec.general then tinsert(out, sec.key) end
	end
	return out
end

local function ViewBoss()
	if not ns.ui.viewBoss then ns.ui.viewBoss = ns.CurrentBoss() or ns.SECTIONS[1].key end
	return ns.ui.viewBoss
end

local function ShiftBoss(dir)
	local keys = BossKeys()
	local cur = ViewBoss()
	for i, key in ipairs(keys) do
		if key == cur then
			ns.ui.viewBoss = keys[(i - 1 + dir) % #keys + 1]
			break
		end
	end
	ns.RefreshUI()
end

-- выбранные игроки по порядку состава
local function SelectedNames()
	local out = {}
	for _, p in ipairs(rosterItems) do
		if ns.ui.selected[p.name] then tinsert(out, p.name) end
	end
	return out
end

local function Apply(rule)
	local names = SelectedNames()
	if #names == 0 then
		ns.Print("сначала выберите игрока в списке слева.")
		return
	end
	ns.AddEvents(names, rule)
end

-------------------------------------------------------------------------------
-- строки

-- ПКМ по игроку: основная роль на этот рейд (хил, переодетый в ДД, остаётся хилом)
local menuFrame
local function RoleMenu(name)
	if not menuFrame then menuFrame = CreateFrame("Frame", "RaidMinusRoleMenu", UIParent, "UIDropDownMenuTemplate") end
	local role, cur, manual = ns.PlayerRole(name)
	local menu = {{text = name, isTitle = true, notCheckable = true}}
	for _, r in ipairs(ns.ROLES) do
		local key = r.key
		tinsert(menu, {text = ns.RoleName(key, true), checked = manual and role == key, func = function() ns.SetRole(name, key) end})
	end
	tinsert(menu, {text = "авто по спеку" .. (cur and (": " .. ns.RoleName(cur)) or ""), checked = not manual, func = function() ns.SetRole(name, nil) end})
	EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
end

local function MakeRosterRow(row)
	row.group = UI.Text(row, "GameFontDisableSmall", "CENTER")
	row.group:SetPoint("LEFT", 2, 0)
	row.group:SetWidth(14)
	row.total = UI.Text(row, "GameFontHighlightSmall", "RIGHT")
	row.total:SetPoint("RIGHT", -4, 0)
	row.total:SetWidth(90)
	row.role = UI.Text(row, "GameFontHighlightSmall", "CENTER")
	row.role:SetPoint("RIGHT", row.total, "LEFT", -2, 0)
	row.role:SetWidth(40)
	row.name = UI.Text(row, "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.group, "RIGHT", 4, 0)
	row.name:SetPoint("RIGHT", row.role, "LEFT", -4, 0)

	row:SetScript("OnClick", function(self, button)
		local p = self.item
		if not p then return end
		if button == "RightButton" then
			RoleMenu(p.name)
			return
		end
		local sel = ns.ui.selected
		if IsControlKeyDown() then
			sel[p.name] = not sel[p.name] or nil
		elseif IsShiftKeyDown() then
			for _, x in ipairs(rosterItems) do
				if x.class == p.class and not x.gone then sel[x.name] = true end
			end
		else
			local only = sel[p.name] and #SelectedNames() == 1
			wipe(sel)
			if not only then sel[p.name] = true end
		end
		ns.RefreshUI()
	end)

	UI.Tooltip(row, function(tt, self)
		local p = self.item
		if not p then return false end
		tt:SetText(ns.ColorName(p.name, p.class))
		if p.gone then tt:AddLine("Ушёл из рейда", 0.6, 0.6, 0.6) end
		local role, cur, manual = ns.PlayerRole(p.name)
		local roleLine = "Роль: " .. ns.RoleName(role, true) .. (manual and " (выставлена вручную)" or "")
		if cur and role and cur ~= role then roleLine = roleLine .. ", сейчас в спеке " .. ns.RoleName(cur, true) end
		tt:AddLine(roleLine, 1, 1, 1)
		tt:AddLine("Итого: " .. ns.StateText(p.name, true), 1, 1, 1)
		for _, ev in ipairs(ns.PlayerEvents(p.name)) do
			tt:AddDoubleLine(ns.ShortName(ev.boss) .. ": " .. ns.ShortText(ev.text), ns.ValueColor(ev.value), 0.9, 0.9, 0.9)
		end
		tt:AddLine(" ")
		tt:AddLine("Ctrl+клик — выбрать несколько, Shift+клик — весь класс, ПКМ — роль", 0.6, 0.6, 0.6, true)
	end)
end

local function DrawRosterRow(row, p)
	row.group:SetText(p.group or "")
	row.name:SetText(p.gone and ("|cff808080" .. p.name .. "|r") or ns.ColorName(p.name, p.class))
	local total, kick, n = ns.PlayerState(p.name)
	local text = n > 0 and ns.ValueColor(total) or ""
	if kick then text = "|cffff2020кик|r " .. text end
	row.total:SetText(text)
	local role, cur = ns.PlayerRole(p.name)
	row.role:SetText(ns.RoleName(role, true) .. ((cur and role and cur ~= role) and "|cffff9020*|r" or ""))
	UI.Select(row, ns.ui.selected[p.name])
end

-- ПКМ по правилу: включить/выключить, у автоправила — «ставить сразу»
local ruleMenu
local function RuleMenu(rule)
	if not ruleMenu then ruleMenu = CreateFrame("Frame", "RaidMinusRuleMenu", UIParent, "UIDropDownMenuTemplate") end
	local menu = {
		{text = ns.ShortText(ns.RuleText(rule)), isTitle = true, notCheckable = true},
		{text = "Включено", checked = not rule.off, func = function()
			rule.off = (not rule.off) or nil
			ns.Refresh()
		end},
	}
	if rule.auto then
		tinsert(menu, {text = "Ставить сразу (без проверки)", checked = rule.instant, func = function()
			rule.instant = (not rule.instant) or nil
			ns.Refresh()
		end})
	end
	tinsert(menu, {text = "Править в редакторе", notCheckable = true, func = function() ns.OpenOptions("rules") end})
	EasyMenu(menu, ruleMenu, "cursor", 0, 0, "MENU")
end

local function MakeRuleRow(row)
	row.kind = row:CreateTexture(nil, "ARTWORK")
	row.kind:SetTexture("Interface\\Buttons\\WHITE8X8")
	row.kind:SetWidth(6)
	row.kind:SetHeight(12)
	row.kind:SetPoint("LEFT", 2, 0)
	row.value = UI.Text(row, "GameFontHighlightSmall", "RIGHT")
	row.value:SetPoint("RIGHT", -4, 0)
	row.value:SetWidth(120)
	row.text = UI.Text(row, "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 14, 0)
	row.text:SetPoint("RIGHT", row.value, "LEFT", -6, 0)

	row:SetScript("OnClick", function(self, button)
		local r = self.item and self.item.rule
		if not r then return end
		if button == "RightButton" then
			RuleMenu(r)
		elseif r.off then
			ns.Print("правило выключено — включите его (ПКМ по правилу).")
		else
			Apply(r)
		end
	end)
	UI.Tooltip(row, function(tt, self)
		local r = self.item and self.item.rule
		if not r then return false end
		local kind = ns.RuleKind(r)
		tt:SetText(ns.RuleText(r), 1, 1, 1, true)
		tt:AddLine(ns.KIND_NAMES[kind], unpack(ns.KIND_COLORS[kind]))
		local d = ns.Detector(r.auto)
		if d then
			tt:AddLine(d.how, 0.7, 0.7, 0.7, true)
			tt:AddLine(r.instant and "Находка сразу ставится игроку" or "Находка идёт во вкладку «На проверку»", 1, 0.82, 0)
		end
		if r.off then tt:AddLine("Выключено", 1, 0.3, 0.3) end
		local names = SelectedNames()
		if #names == 0 then
			tt:AddLine("Сначала выберите игроков слева", 1, 0.5, 0.3)
		else
			tt:AddLine("Поставить: " .. tconcat(names, ", "), 0.6, 1, 0.6, true)
		end
		tt:AddLine("ПКМ — включить / выключить" .. (d and ", ставить сразу" or ""), 0.6, 0.6, 0.6)
	end)
end

local function RuleValueText(r)
	local parts = {}
	if r.instant and not r.off then tinsert(parts, "|cffffd100сразу|r") end
	if r.kick then tinsert(parts, "|cffff2020кик|r") end
	if r.value ~= 0 or not r.kick then tinsert(parts, ns.ValueColor(r.value)) end
	return tconcat(parts, " ")
end

local function DrawRuleRow(row, item)
	if item.header then
		row:Disable()
		row.kind:Hide()
		row.text:SetText("|cffffd100" .. item.header .. "|r")
		row.value:SetText("")
		return
	end
	local r = item.rule
	row:Enable()
	row.kind:SetVertexColor(unpack(ns.KIND_COLORS[ns.RuleKind(r)]))
	row.kind:SetAlpha(r.off and 0.3 or 1)
	row.kind:Show()
	if r.off then
		row.text:SetText("|cff707070" .. ns.RuleText(r) .. " (выкл)|r")
		row.value:SetText("|cff707070" .. ns.ValueText(r.value) .. "|r")
	else
		row.text:SetText(ns.RuleText(r))
		row.value:SetText(RuleValueText(r))
	end
end

-------------------------------------------------------------------------------
-- вкладка

local function Create(f)
	rosterTitle = UI.Text(f, "GameFontNormal")
	rosterTitle:SetPoint("TOPLEFT", 2, -4)

	roster = UI.List(f, ROSTER_ROWS, ROW_H, MakeRosterRow)
	roster:SetPoint("TOPLEFT", 0, -24)
	roster:SetWidth(270)
	roster.redraw = ns.RefreshUI

	selText = UI.Text(f, "GameFontHighlightSmall")
	selText:SetPoint("TOPLEFT", roster, "BOTTOMLEFT", 2, -8)
	local clear = UI.Button(f, "Снять выбор", 100, function()
		wipe(ns.ui.selected)
		ns.RefreshUI()
	end)
	clear:SetPoint("TOPRIGHT", roster, "BOTTOMRIGHT", 0, -3)

	-- правая колонка: выбор босса
	local prev = UI.Button(f, "<", 26, function() ShiftBoss(-1) end)
	prev:SetPoint("TOPLEFT", roster, "TOPRIGHT", 14, 24)
	local now = UI.Button(f, "К текущему", 100, function()
		ns.ui.viewBoss = ns.CurrentBoss()
		ns.RefreshUI()
	end)
	now:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	UI.Tooltip(now, function(tt)
		tt:SetText("Босс, которого пулили последним (по DBM)")
	end)
	local nextBtn = UI.Button(f, ">", 26, function() ShiftBoss(1) end)
	nextBtn:SetPoint("RIGHT", now, "LEFT", -8, 0)
	bossText = UI.Text(f, "GameFontNormal", "CENTER")
	bossText:SetPoint("LEFT", prev, "RIGHT", 4, 0)
	bossText:SetPoint("RIGHT", nextBtn, "LEFT", -4, 0)

	rules = UI.List(f, RULE_ROWS, ROW_H, MakeRuleRow)
	rules:SetPoint("TOPLEFT", roster, "TOPRIGHT", 14, 0)
	rules:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	rules.redraw = ns.RefreshUI

	-- свой минус
	valueEdit = UI.EditBox(f, 50, "-20")
	valueEdit:SetPoint("TOPLEFT", rules, "BOTTOMLEFT", 6, -6)
	textEdit = UI.EditBox(f, 250, "причина своего минуса или плюса")
	textEdit:SetPoint("LEFT", valueEdit, "RIGHT", 10, 0)
	local function ApplyCustom()
		local value = tonumber(valueEdit:GetText())
		if not value then
			ns.Print("впишите число, например -20 или 10.")
			return
		end
		local text = strtrim(textEdit:GetText())
		if text == "" then text = value >= 0 and "Плюс от РЛа" or "Минус от РЛа" end
		Apply({boss = ViewBoss(), text = text, value = value})
		valueEdit:SetText("")
		textEdit:SetText("")
	end
	textEdit:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		ApplyCustom()
	end)
	local put = UI.Button(f, "Поставить", 90, ApplyCustom)
	put:SetPoint("LEFT", textEdit, "RIGHT", 6, 0)

	local undo = UI.Button(f, "Отменить последнее", 150, function() ns.UndoLast() end)
	undo:SetPoint("TOPLEFT", valueEdit, "BOTTOMLEFT", -6, -6)
	UI.Tooltip(undo, function(tt)
		tt:SetText("Отменить последний клик")
		tt:AddLine("Если минус ещё не объявлен — удаляется молча, если объявлен — снимается с объявлением.", 1, 1, 1, true)
	end)
	local hint = UI.Text(f, "GameFontDisableSmall")
	hint:SetPoint("LEFT", undo, "RIGHT", 10, 0)
	hint:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	hint:SetText("|c" .. ns.KIND_HEX.auto .. "автоматика|r · |c" .. ns.KIND_HEX.known .. "видно, кто нарушил|r · |c" .. ns.KIND_HEX.manual .. "вручную|r · ПКМ — вкл/выкл")
end

local function Update()
	local s = ns.Session()
	rosterItems = ns.RosterList()
	local here = 0
	for _, p in ipairs(rosterItems) do
		if not p.gone then here = here + 1 end
	end
	rosterTitle:SetText(format("Игроки: %d", here))
	roster:Draw(rosterItems, DrawRosterRow)

	local names = SelectedNames()
	if #names == 0 then
		selText:SetText("|cff9d9d9dНикто не выбран|r")
	elseif #names <= 3 then
		selText:SetText("Выбрано: " .. tconcat(names, ", "))
	else
		selText:SetText(format("Выбрано: %d", #names))
	end

	local boss = ViewBoss()
	local label = ns.Section(boss).name
	if s and s.pulls[boss] then label = label .. format(" |cff9d9d9d(пулов: %d)|r", s.pulls[boss]) end
	if boss == ns.CurrentBoss() then label = label .. " |cff40ff40• сейчас|r" end
	bossText:SetText(label)

	local rs = ns.ActiveRuleset()
	local items = {}
	for _, key in ipairs({boss, "general", "bonus"}) do
		local list = ns.RulesFor(rs, key)
		if #list > 0 or key == boss then
			tinsert(items, {header = ns.Section(key).name .. (#list == 0 and " — правил нет" or "")})
			for _, r in ipairs(list) do tinsert(items, {rule = r}) end
		end
	end
	rules:Draw(items, DrawRuleRow)
end

ns.RegisterPage("players", Create, Update)
