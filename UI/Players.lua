-- Вкладка «Минусы» (вариант A): слева разделы — 12 боссов со статусом (убит / сейчас / пулы) и «Общие»;
-- в центре правила выбранного босса (минусы и плюсы), а ниже всегда «Общие»; справа состав рейда.
-- Клик по игроку — выбрать (Ctrl — несколько, Shift — весь класс, ПКМ — роль), клик по правилу —
-- поставить выбранным. Шестерёнка у правила — настройка во вкладке «Правила», ПКМ — быстрое меню.

local _, ns = ...
local UI = ns.UI

local format, tinsert, tconcat = string.format, table.insert, table.concat
local ipairs, pairs = ipairs, pairs

local RULE_ROWS, RULE_H, ROSTER_ROWS, ROSTER_H = 19, 24, 25, 17
local RAIL_W, ROSTER_W = 150, 244
local CHECK = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local GEAR = "Interface\\Icons\\INV_Misc_Gear_01"
local ROLE_FILTERS = {{"all", "все", 36}, {"tank", "танки", 44}, {"healer", "хилы", 40}, {"melee", "мдд", 38}, {"caster", "рдд", 36}}

local railButtons, generalBtn = {}, nil
local rules, roster, headName, headMeta, search, rosterTitle, selText, valueEdit, textEdit, putBtn
local rolePills = {}
local rosterItems = {}

local function ViewSection()
	if not ns.ui.viewBoss then ns.ui.viewBoss = ns.CurrentBoss() or ns.SECTIONS[1].key end
	return ns.ui.viewBoss
end

-- выбранные игроки по порядку состава
function ns.SelectedNames()
	local out = {}
	for _, p in ipairs(ns.RosterList()) do
		if ns.ui.selected[p.name] then tinsert(out, p.name) end
	end
	return out
end

local function Apply(rule)
	local names = ns.SelectedNames()
	if #names == 0 then
		ns.Print("сначала выберите игрока в списке справа.")
		return
	end
	ns.AddEvents(names, rule)
end

-------------------------------------------------------------------------------
-- меню по ПКМ

local menuFrame
local function Menu(menu)
	if not menuFrame then menuFrame = CreateFrame("Frame", "RaidMinusMenu", UIParent, "UIDropDownMenuTemplate") end
	EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
end

-- основная роль на этот рейд (хил, переодетый в ДД, остаётся хилом)
local function RoleMenu(name)
	local role, cur, manual = ns.PlayerRole(name)
	local menu = {{text = name, isTitle = true, notCheckable = true}}
	for _, r in ipairs(ns.ROLES) do
		local key = r.key
		tinsert(menu, {text = ns.RoleName(key, true), checked = manual and role == key, func = function() ns.SetRole(name, key) end})
	end
	tinsert(menu, {text = "авто по спеку" .. (cur and (": " .. ns.RoleName(cur)) or ""), checked = not manual, func = function() ns.SetRole(name, nil) end})
	Menu(menu)
end

function ns.RuleMenu(rule)
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
	tinsert(menu, {text = "Быстрая кнопка (мини-панель, меню цели)", checked = rule.quick, func = function()
		rule.quick = (not rule.quick) or nil
		ns.Refresh()
	end})
	tinsert(menu, {text = "Настроить…", notCheckable = true, func = function() ns.EditRule(rule) end})
	Menu(menu)
end

-------------------------------------------------------------------------------
-- левая колонка: разделы

local function SectionLabel(sec)
	local s = ns.Session()
	local mark = "|cff4d5060o|r"
	if sec.general then
		mark = "|cffffd100=|r"
	elseif s and s.boss == sec.key and not (s.killed and s.killed[sec.key]) then
		mark = "|cff60e860*|r"
	elseif s and s.killed and s.killed[sec.key] then
		mark = "|T" .. CHECK .. ":12|t"
	end
	local pulls = s and s.pulls[sec.key]
	local tail = pulls and format("  |cff8e8e9bпул %d|r", pulls) or ""
	return mark .. "  " .. sec.short .. tail
end

local function CreateRail(f)
	local title = UI.Text(f, "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 4, -2)
	title:SetText("Разделы")
	local box = UI.Box(f)
	box:SetPoint("TOPLEFT", 0, -18)
	box:SetWidth(RAIL_W)
	local y = -4
	for _, sec in ipairs(ns.SECTIONS) do
		local key = sec.key
		if sec.general then
			local sep = UI.Flat(box, "ARTWORK", 0.16, 0.18, 0.22, 1)
			sep:SetPoint("TOPLEFT", 6, y - 4)
			sep:SetPoint("TOPRIGHT", -6, y - 4)
			sep:SetHeight(1)
			y = y - 9
		end
		local b = UI.FlatButton(box, sec.short, RAIL_W - 8, 25, function()
			ns.ui.viewBoss = key
			ns.ui.search = nil
			if search and search:GetText() ~= "" then search:SetText("") end
			ns.RefreshUI()
		end, "row")
		b:SetPoint("TOPLEFT", 4, y)
		b.tooltip = function(tt)
			tt:SetText(sec.name)
			local n = #ns.RulesFor(ns.ActiveRuleset(), key)
			tt:AddLine("Правил: " .. n, 1, 1, 1)
			if sec.general then tt:AddLine("Минусы и плюсы на любом боссе — видны всегда под правилами босса.", 0.7, 0.7, 0.7, true) end
		end
		railButtons[key] = b
		if sec.general then generalBtn = b end
		y = y - 26
	end
	box:SetHeight(-y + 4)

	local legend = UI.Text(f, "GameFontDisableSmall")
	legend:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 4, -8)
	legend:SetWidth(RAIL_W - 8)
	legend:SetText("Метка правила:\n|c" .. ns.KIND_HEX.auto .. "автоматика|r\n|c" .. ns.KIND_HEX.known .. "видно, кто нарушил|r\n|c"
		.. ns.KIND_HEX.manual .. "вручную|r\n|cffffd100»|r быстрая кнопка")
	local now = UI.FlatButton(f, "К текущему боссу", RAIL_W, 22, function()
		ns.ui.viewBoss = ns.CurrentBoss() or ns.ui.viewBoss
		ns.RefreshUI()
	end, "ghost")
	now:SetPoint("TOPLEFT", legend, "BOTTOMLEFT", -4, -8)
end

local function UpdateRail()
	local view = ViewSection()
	for _, sec in ipairs(ns.SECTIONS) do
		local b = railButtons[sec.key]
		b:SetLabel(SectionLabel(sec))
		b:SetSelected(view == sec.key and not ns.ui.search)
	end
end

-------------------------------------------------------------------------------
-- центр: правила

local function RuleChips(r)
	local parts = {}
	if r.off then return "|cff707070выкл|r" end
	if r.instant then tinsert(parts, "|cffffd100сразу|r") end
	if r.kick then tinsert(parts, "|cffff5050кик|r") end
	if r.rep == "fight" then tinsert(parts, "|cff9d9d9d1/бой|r") elseif r.rep == "raid" then tinsert(parts, "|cff9d9d9d1/рейд|r") end
	if r.step then tinsert(parts, "|cff9d9d9d" .. ns.ValueText(r.step) .. "/раз|r") end
	if not ns.RuleDiffOk(r) then tinsert(parts, "|cff707070не эта сложность|r") end
	return tconcat(parts, " ")
end

local function MakeRuleRow(row)
	row.kind = UI.KindMark(row)
	row.kind:SetPoint("LEFT", 4, 0)
	row.gear = CreateFrame("Button", nil, row)
	row.gear:SetWidth(16)
	row.gear:SetHeight(16)
	row.gear:SetPoint("RIGHT", -4, 0)
	row.gear:SetNormalTexture(GEAR)
	row.gear:GetNormalTexture():SetDesaturated(true)
	row.gear:SetHighlightTexture(GEAR, "ADD")
	row.gear:SetScript("OnClick", function(self)
		local item = self:GetParent().item
		if item and item.rule then ns.EditRule(item.rule) end
	end)
	UI.Tooltip(row.gear, function(tt) tt:SetText("Настроить правило") end)
	row.value = UI.Text(row, "GameFontHighlight", "RIGHT")
	row.value:SetPoint("RIGHT", row.gear, "LEFT", -6, 0)
	row.value:SetWidth(44)
	row.chips = UI.Text(row, "GameFontHighlightSmall", "RIGHT")
	row.chips:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	row.text = UI.Text(row, "GameFontHighlight")
	row.text:SetPoint("LEFT", 16, 0)
	row.text:SetPoint("RIGHT", row.chips, "LEFT", -6, 0)
	row.text:SetHeight(14)

	row:SetScript("OnClick", function(self, button)
		local r = self.item and self.item.rule
		if not r then return end
		if button == "RightButton" then
			ns.RuleMenu(r)
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
		if r.note then tt:AddLine(r.note, 0.8, 0.8, 0.8, true) end
		if ns.ChatText(r) ~= ns.RuleText(r) then tt:AddLine("В чат: " .. ns.ChatText(r), 0.6, 0.8, 1, true) end
		local d = ns.Detector(r.auto)
		if d then
			tt:AddLine(d.how, 0.7, 0.7, 0.7, true)
			tt:AddLine(r.instant and "Находка сразу ставится игроку" or "Находка идёт во вкладку «На проверку»", 1, 0.82, 0)
		end
		if r.off then tt:AddLine("Выключено", 1, 0.3, 0.3) end
		local names = ns.SelectedNames()
		if #names == 0 then
			tt:AddLine("Сначала выберите игроков справа", 1, 0.5, 0.3)
		else
			tt:AddLine("Поставить: " .. tconcat(names, ", "), 0.6, 1, 0.6, true)
		end
		tt:AddLine("ПКМ — включить, «сразу», быстрая кнопка; шестерёнка — настройка", 0.6, 0.6, 0.6, true)
	end)
end

local function DrawRuleRow(row, item)
	row.text:SetFontObject(item.header and "GameFontNormalSmall" or "GameFontHighlight")
	if item.header then
		row:Disable()
		row.kind:Hide()
		row.gear:Hide()
		row.text:SetText(item.header)
		row.chips:SetText("")
		row.value:SetText("")
		row.bg:SetTexture(0, 0, 0, 0)
		return
	end
	local r = item.rule
	row:Enable()
	row.gear:Show()
	row.kind:SetVertexColor(unpack(ns.KIND_COLORS[ns.RuleKind(r)]))
	row.kind:SetAlpha(r.off and 0.3 or 1)
	row.kind:Show()
	local text = ns.RuleText(r)
	if item.prefix then text = "|cff8e8e9b" .. item.prefix .. ":|r " .. text end
	if r.quick then text = text .. " |cffffd100»|r" end
	row.text:SetText(r.off and ("|cff707070" .. ns.RuleText(r) .. "|r") or text)
	row.chips:SetText(RuleChips(r))
	if r.kick and r.value == 0 then
		row.value:SetText("")
	else
		row.value:SetText(r.off and ("|cff707070" .. ns.ValueText(r.value) .. "|r") or ns.ValueColor(r.value))
	end
	row.bg:SetTexture(0, 0, 0, 0)
end

-- строки центра: правила босса (минусы, плюсы) и «Общие»; при поиске — совпадения из всех разделов
local function RuleItems()
	local rs = ns.ActiveRuleset()
	local items = {}
	local query = ns.ui.search and ns.Lower(ns.ui.search)
	if query and query ~= "" then
		for _, sec in ipairs(ns.SECTIONS) do
			for _, r in ipairs(ns.RulesFor(rs, sec.key)) do
				if ns.Lower(ns.RuleText(r)):find(query, 1, true) then
					tinsert(items, {rule = r, prefix = sec.short})
				end
			end
		end
		if #items == 0 then tinsert(items, {header = "|cff9d9d9dНичего не найдено|r"}) end
		return items
	end
	local function Group(sec, sign, title, always)
		local list = ns.RulesFor(rs, sec, sign)
		if #list == 0 and not always then return end
		tinsert(items, {header = title .. (#list == 0 and " |cff707070— нет|r" or format(" |cff707070%d|r", #list))})
		for _, r in ipairs(list) do tinsert(items, {rule = r}) end
	end
	local view = ViewSection()
	if view ~= "general" then
		Group(view, "minus", "МИНУСЫ БОССА", true)
		Group(view, "plus", "ПЛЮСЫ БОССА")
	end
	tinsert(items, {header = "|cffffd100ОБЩИЕ — НА ЛЮБОМ БОССЕ|r"})
	Group("general", "minus", "  минусы", true)
	Group("general", "plus", "  плюсы", true)
	return items
end

local function CreateCenter(f)
	local x = RAIL_W + 10
	headName = UI.Text(f, "GameFontNormalLarge")
	headName:SetPoint("TOPLEFT", x + 2, -2)
	headMeta = UI.Text(f, "GameFontDisableSmall")
	headMeta:SetPoint("LEFT", headName, "RIGHT", 10, -1)
	search = UI.EditBox(f, 160, "поиск правила")
	search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(ROSTER_W + 16), 0)
	search:SetScript("OnTextChanged", function(self)
		local t = strtrim(self:GetText())
		ns.ui.search = t ~= "" and t or nil
		if self.UpdateHint then self.UpdateHint() end
		ns.RefreshUI()
	end)

	rules = UI.List(f, RULE_ROWS, RULE_H, MakeRuleRow)
	rules:SetPoint("TOPLEFT", x, -24)
	rules:SetPoint("RIGHT", f, "RIGHT", -(ROSTER_W + 10), 0)
	rules.redraw = ns.RefreshUI

	-- свой минус или плюс
	local label = UI.Text(f, "GameFontDisableSmall")
	label:SetPoint("TOPLEFT", rules, "BOTTOMLEFT", 2, -10)
	label:SetText("Свой:")
	valueEdit = UI.EditBox(f, 46, "-20")
	valueEdit:SetPoint("LEFT", label, "RIGHT", 10, 0)
	putBtn = UI.Button(f, "Поставить", 130, nil)
	putBtn:SetPoint("TOPRIGHT", rules, "BOTTOMRIGHT", 0, -5)
	textEdit = UI.EditBox(f, 200, "причина своего минуса или плюса")
	textEdit:SetPoint("LEFT", valueEdit, "RIGHT", 10, 0)
	textEdit:SetPoint("RIGHT", putBtn, "LEFT", -8, 0)
	local function ApplyCustom()
		local value = tonumber(valueEdit:GetText())
		if not value then
			ns.Print("впишите число, например -20 или 10.")
			return
		end
		local text = strtrim(textEdit:GetText())
		if text == "" then text = value >= 0 and "Плюс от РЛа" or "Минус от РЛа" end
		local view = ViewSection()
		Apply({boss = view, text = text, value = value})
		valueEdit:SetText("")
		textEdit:SetText("")
	end
	putBtn:SetScript("OnClick", ApplyCustom)
	textEdit:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		ApplyCustom()
	end)
end

local function UpdateCenter()
	local s = ns.Session()
	local view = ViewSection()
	local sec = ns.Section(view)
	if ns.ui.search then
		headName:SetText("Поиск")
		headMeta:SetText("по всем разделам")
	elseif sec.general then
		headName:SetText("Общие")
		headMeta:SetText("минусы и плюсы на любом боссе")
	else
		headName:SetText(sec.name)
		local pulls = s and s.pulls[view]
		local meta = pulls and format("пулов: %d", pulls) or "ещё не пулили"
		if s and s.killed and s.killed[view] then meta = meta .. " · убит" elseif view == ns.CurrentBoss() then meta = meta .. " · |cff60e860сейчас|r" end
		headMeta:SetText(meta)
	end
	rules:Draw(RuleItems(), DrawRuleRow)
	local n = #ns.SelectedNames()
	putBtn:SetText(n > 0 and format("Поставить (%d)", n) or "Поставить")
end

-------------------------------------------------------------------------------
-- справа: состав

local function MakeRosterRow(row)
	row.group = UI.Text(row, "GameFontDisableSmall", "CENTER")
	row.group:SetPoint("LEFT", 2, 0)
	row.group:SetWidth(12)
	row.total = UI.Text(row, "GameFontHighlightSmall", "RIGHT")
	row.total:SetPoint("RIGHT", -4, 0)
	row.total:SetWidth(70)
	row.role = UI.Text(row, "GameFontHighlightSmall", "LEFT")
	row.role:SetPoint("RIGHT", row.total, "LEFT", -2, 0)
	row.role:SetWidth(34)
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
			local only = sel[p.name] and #ns.SelectedNames() == 1
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
			tt:AddDoubleLine(ns.ShortName(ev.boss) .. ": " .. ns.EventChat(ev), ns.ValueColor(ev.value), 0.9, 0.9, 0.9)
		end
		tt:AddLine(" ")
		tt:AddLine("Ctrl+клик — несколько, Shift+клик — весь класс, ПКМ — роль", 0.6, 0.6, 0.6, true)
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

local function CreateRoster(f)
	rosterTitle = UI.Text(f, "GameFontNormalSmall")
	rosterTitle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(ROSTER_W - 40), -2)
	rosterTitle:SetPoint("TOPLEFT", f, "TOPRIGHT", -ROSTER_W + 2, -2)
	local hint = UI.Text(f, "GameFontDisableSmall", "RIGHT")
	hint:SetPoint("TOPRIGHT", -2, -2)
	hint:SetText("ПКМ — роль")

	local prev
	for _, rf in ipairs(ROLE_FILTERS) do
		local key = rf[1]
		local b = UI.FlatButton(f, rf[2], rf[3] + 8, 20, function()
			ns.ui.roleFilter = key ~= "all" and key or nil
			ns.RefreshUI()
		end, "pill")
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("TOPLEFT", f, "TOPRIGHT", -ROSTER_W, -18) end
		rolePills[key] = b
		prev = b
	end

	roster = UI.List(f, ROSTER_ROWS, ROSTER_H, MakeRosterRow)
	roster:SetPoint("TOPLEFT", f, "TOPRIGHT", -ROSTER_W, -42)
	roster:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	roster.redraw = ns.RefreshUI

	local clear = UI.FlatButton(f, "Снять выбор", 92, 20, function()
		wipe(ns.ui.selected)
		ns.RefreshUI()
	end, "ghost")
	clear:SetPoint("TOPRIGHT", roster, "BOTTOMRIGHT", 0, -6)
	selText = UI.Text(f, "GameFontHighlightSmall")
	selText:SetPoint("LEFT", roster, "BOTTOMLEFT", 2, -16)
	selText:SetPoint("RIGHT", clear, "LEFT", -6, 0)
	selText:SetHeight(14)
end

local function UpdateRoster()
	local filter = ns.ui.roleFilter
	rosterItems = {}
	local here = 0
	for _, p in ipairs(ns.RosterList()) do
		if not p.gone then here = here + 1 end
		if not filter or ns.PlayerRole(p.name) == filter then tinsert(rosterItems, p) end
	end
	rosterTitle:SetText(format("Игроки: %d", here))
	for key, b in pairs(rolePills) do b:SetSelected((filter or "all") == key) end
	roster:Draw(rosterItems, DrawRosterRow)

	local names = ns.SelectedNames()
	if #names == 0 then
		selText:SetText("|cff9d9d9dНикто не выбран|r")
	elseif #names <= 3 then
		selText:SetText("Выбрано: " .. tconcat(names, ", "))
	else
		selText:SetText(format("Выбрано: %d", #names))
	end
end

-------------------------------------------------------------------------------

local function Create(f)
	CreateRail(f)
	CreateCenter(f)
	CreateRoster(f)
end

local function Update()
	UpdateRail()
	UpdateCenter()
	UpdateRoster()
end

ns.RegisterPage("players", Create, Update)
