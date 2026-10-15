-- Вкладка «Правила»: редактор свода (работает и без рейда).
-- Слева разделы (12 боссов и «Общие»), в центре правила раздела (минусы и плюсы), справа — все
-- настройки выбранного правила (что они значат — Rules.lua). Правка сразу видна в окне;
-- уже поставленные минусы не меняются: запись журнала хранит текст и очки.

local _, ns = ...
local UI = ns.UI

local format, tinsert = string.format, table.insert
local ipairs, pairs, tonumber, tostring = ipairs, pairs, tonumber, tostring

local SEC_W, LIST_W, ROWS, ROW_H, FIELD_H = 140, 286, 21, 22, 27
local LABEL_W = 116

local secButtons = {}
local rulesetDD, list, addMinus, addPlus
local form, empty, kindTag, header, enabled
local f_text, f_chat, f_note, f_section, f_sign, f_value, f_kick, f_rep, f_step, f_diff, f_ann, f_whisper, f_who, f_quick
local rolePills = {}
local autoBox, f_mode, f_how, paramEdits = nil, nil, nil, {}
local upBtn, downBtn, dupBtn, delBtn
local loaded -- правило, чьи поля сейчас в форме

local function RS() return ns.ActiveRuleset() end

local function Section()
	if not ns.ui.editSection then ns.ui.editSection = ns.ui.viewBoss or ns.SECTIONS[1].key end
	return ns.ui.editSection
end

local function Rule()
	local r = ns.ui.editRule and ns.RuleById(RS(), ns.ui.editRule)
	if r and r.boss ~= Section() then r = nil end
	if not r then
		r = ns.RulesFor(RS(), Section())[1]
		ns.ui.editRule = r and r.id
	end
	return r
end

local function Changed(reload)
	if reload then loaded = nil end
	ns.Refresh()
end

-- открыть правило в редакторе (шестерёнка, ПКМ → «Настроить…»)
function ns.EditRule(rule)
	ns.ui.editSection = rule.boss
	ns.ui.editRule = rule.id
	loaded = nil
	ns.ShowTab("rules")
end

StaticPopupDialogs["RAIDMINUS_DELETE_RULE"] = {
	text = "Удалить правило «%s»?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, rule)
		ns.RemoveRule(RS(), rule)
		ns.ui.editRule = nil
		Changed(true)
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

StaticPopupDialogs["RAIDMINUS_DELETE_SET"] = {
	text = "Удалить свод «%s»?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, rs)
		ns.DeleteRuleset(rs)
		Changed(true)
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

-------------------------------------------------------------------------------
-- поля формы

local function Label(parent, text, y)
	local fs = UI.Text(parent, "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", 0, y - 5)
	fs:SetWidth(LABEL_W)
	fs:SetTextColor(0.66, 0.66, 0.71)
	fs:SetText(text)
	return fs
end

-- текстовое поле: get(rule) -> text, set(rule, text); правится по Enter или при уходе фокуса
local function TextField(parent, y, label, width, placeholder, get, set)
	Label(parent, label, y)
	local e = UI.EditBox(parent, width, placeholder)
	e:SetPoint("TOPLEFT", LABEL_W + 6, y - 2)
	local function Commit(self)
		local r = Rule()
		if not r or loaded ~= r then return end
		local text = strtrim(self:GetText())
		if text ~= (get(r) or "") then
			set(r, text)
			Changed()
		end
	end
	e:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	e:HookScript("OnEditFocusLost", Commit)
	e.Load = function(r)
		e:SetText(get(r) or "")
		e:SetCursorPosition(0)
		if e.UpdateHint then e.UpdateHint() end
	end
	return e
end

local function CheckField(parent, x, y, label, onClick)
	local cb = UI.Check(parent, label, function(v)
		local r = Rule()
		if r then
			onClick(r, v)
			Changed()
		end
	end)
	cb:SetPoint("TOPLEFT", x, y)
	return cb
end

local function SegField(parent, y, label, options, onSelect)
	Label(parent, label, y)
	local seg = UI.Seg(parent, options, function(key)
		local r = Rule()
		if r then
			onSelect(r, key)
			Changed()
		end
	end)
	seg:SetPoint("TOPLEFT", LABEL_W + 6, y - 2)
	return seg
end

local SIGN = {{"minus", "Минус", 70}, {"plus", "Плюс", 70}}
local REPEAT = {{"each", "Каждый раз", 96}, {"fight", "Раз за бой", 90}, {"raid", "Раз за рейд", 96}}
local DIFF = {{"any", "Любая", 70}, {"hc", "Только гер.", 96}, {"nm", "Только об.", 90}}
local MODE = {{"off", "Выкл", 56}, {"review", "На проверку", 100}, {"instant", "Сразу", 64}}
local ANN = {{"default", "Как в настройках"}, {"instant", "Сразу"}, {"combat", "После боя"}, {"off", "Не объявлять"}}
local ANN_TEXT = {}
for _, a in ipairs(ANN) do ANN_TEXT[a[1]] = a[2] end

local function SetValue(r, abs)
	abs = math.abs(abs or 0)
	r.value = ns.IsPlus(r) and abs or -abs
end

local function CreateForm(parent)
	form = CreateFrame("Frame", nil, parent)
	form:SetPoint("TOPLEFT", SEC_W + LIST_W + 20, -30)
	form:SetPoint("BOTTOMRIGHT", 0, 0)
	local bg = UI.Box(parent)
	bg:SetPoint("TOPLEFT", form, "TOPLEFT", -8, 6)
	bg:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", 0, 0)
	bg:SetFrameLevel(form:GetFrameLevel() - 1)

	empty = UI.Text(parent, "GameFontDisable", "CENTER")
	empty:SetPoint("CENTER", form, "CENTER")
	empty:SetText("В разделе нет правил — «+ Минус» или «+ Плюс».")

	kindTag = UI.Text(form, "GameFontHighlightSmall")
	kindTag:SetPoint("TOPLEFT", 0, -2)
	header = UI.Text(form, "GameFontNormal")
	header:SetPoint("LEFT", kindTag, "RIGHT", 8, 0)
	header:SetPoint("RIGHT", form, "TOPRIGHT", -120, -9)
	header:SetHeight(14)
	enabled = CheckField(form, 0, -2, "Включено", function(r, v) r.off = (not v) or nil end)
	enabled:ClearAllPoints()
	enabled:SetPoint("TOPRIGHT", -96, 2)
	local line = UI.Flat(form, "ARTWORK", 0.16, 0.18, 0.22, 1)
	line:SetPoint("TOPLEFT", 0, -22)
	line:SetPoint("TOPRIGHT", -8, -22)
	line:SetHeight(1)

	local y = -28
	f_text = TextField(form, y, "Текст в окне", 330, nil, function(r)
		if r.auto then return r.label end
		return r.text
	end, function(r, t)
		if r.auto then
			r.label = t ~= "" and t or nil
		elseif t ~= "" then
			r.text = t
		end
	end)
	y = y - FIELD_H
	f_chat = TextField(form, y, "Текст в чат", 330, "как в окне, без пояснения в скобках",
		function(r) return r.chat end, function(r, t) r.chat = t ~= "" and t or nil end)
	y = y - FIELD_H
	f_note = TextField(form, y, "Пояснение", 330, "видно только в подсказке",
		function(r) return r.note end, function(r, t) r.note = t ~= "" and t or nil end)
	y = y - FIELD_H

	Label(form, "Раздел", y)
	f_section = UI.Dropdown(form, 180, function()
		local items = {}
		for _, sec in ipairs(ns.SECTIONS) do tinsert(items, {sec.key, sec.name}) end
		return items
	end, function(key)
		local r = Rule()
		if not r then return end
		ns.SetRuleSection(r, key)
		ns.ui.editSection = key
		Changed(true)
	end)
	f_section:SetPoint("TOPLEFT", LABEL_W + 6, y - 2)
	y = y - FIELD_H

	f_sign = SegField(form, y, "Минус или плюс", SIGN, function(r, key)
		local abs = math.abs(r.value or 0)
		if abs == 0 then abs = 10 end
		r.value = key == "plus" and abs or -abs
		loaded = nil
	end)
	local vLabel = UI.Text(form, "GameFontHighlightSmall")
	vLabel:SetPoint("LEFT", f_sign, "RIGHT", 12, 0)
	vLabel:SetTextColor(0.66, 0.66, 0.71)
	vLabel:SetText("Очки")
	f_value = UI.EditBox(form, 40, nil)
	f_value:SetPoint("LEFT", vLabel, "RIGHT", 8, 0)
	f_value:SetNumeric(true)
	f_value:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	f_value:HookScript("OnEditFocusLost", function(self)
		local r = Rule()
		if not r or loaded ~= r then return end
		local v = tonumber(self:GetText())
		if v and v ~= math.abs(r.value or 0) then
			SetValue(r, v)
			Changed()
		end
	end)
	local prev = f_value
	for _, n in ipairs({10, 20, 30, 50}) do
		local b = UI.FlatButton(form, tostring(n), 26, 20, function()
			local r = Rule()
			if not r then return end
			SetValue(r, n)
			loaded = nil
			Changed()
		end, "ghost")
		b:SetPoint("LEFT", prev, "RIGHT", prev == f_value and 8 or 3, 0)
		prev = b
	end
	y = y - FIELD_H

	Label(form, "Кик", y)
	f_kick = CheckField(form, LABEL_W + 2, y, "Пометка «на кик»: пока не снята, не побеждает в ролле",
		function(r, v) r.kick = v or nil end)
	y = y - FIELD_H

	f_rep = SegField(form, y, "Повтор", REPEAT, function(r, key) r.rep = key ~= "each" and key or nil end)
	y = y - FIELD_H

	Label(form, "Нарастание", y)
	f_step = UI.EditBox(form, 40, nil)
	f_step:SetPoint("TOPLEFT", LABEL_W + 6, y - 2)
	f_step:SetNumeric(true)
	f_step:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	f_step:HookScript("OnEditFocusLost", function(self)
		local r = Rule()
		if not r or loaded ~= r then return end
		local v = tonumber(self:GetText())
		local step = (v and v > 0) and (ns.IsPlus(r) and v or -v) or nil
		if step ~= r.step then
			r.step = step
			Changed()
		end
	end)
	local stepHint = UI.Text(form, "GameFontDisableSmall")
	stepHint:SetPoint("LEFT", f_step, "RIGHT", 8, 0)
	stepHint:SetText("ещё столько очков за каждый следующий раз тому же игроку (пусто — нет)")
	stepHint:SetWidth(300)
	y = y - FIELD_H

	Label(form, "Кому", y)
	local px = LABEL_W + 6
	for _, role in ipairs(ns.ROLES) do
		local key = role.key
		local b = UI.FlatButton(form, role.name, 52, 20, function()
			local r = Rule()
			if not r then return end
			local set = r.roles or {tank = true, healer = true, melee = true, caster = true}
			set[key] = (not set[key]) or nil
			local n = 0
			for _ in pairs(set) do n = n + 1 end
			r.roles = (n > 0 and n < 4) and set or nil
			Changed()
		end, "pill")
		b:SetPoint("TOPLEFT", px, y - 2)
		rolePills[key] = b
		px = px + 56
	end
	local roleHint = UI.Text(form, "GameFontDisableSmall")
	roleHint:SetPoint("TOPLEFT", px + 4, y - 6)
	roleHint:SetText("по основной роли на рейд")
	y = y - FIELD_H

	f_diff = SegField(form, y, "Сложность", DIFF, function(r, key) r.diff = key ~= "any" and key or nil end)
	y = y - FIELD_H

	Label(form, "Объявление", y)
	f_ann = UI.Dropdown(form, 150, function() return ANN end, function(key)
		local r = Rule()
		if not r then return end
		r.ann = key ~= "default" and key or nil
		Changed()
	end)
	f_ann:SetPoint("TOPLEFT", LABEL_W + 6, y - 2)
	f_whisper = CheckField(form, LABEL_W + 166, y, "Шепнуть игроку причину", function(r, v) r.whisper = v or nil end)
	y = y - FIELD_H

	Label(form, "Быстрый доступ", y)
	f_quick = CheckField(form, LABEL_W + 2, y, "Кнопка на мини-панели и в меню «минус цели»", function(r, v) r.quick = v or nil end)
	y = y - FIELD_H

	-- вручную: видно ли нарушителя; автоматика: режим, пороги, как ловится
	f_who = CheckField(form, LABEL_W + 2, y, "Видно, кто нарушил (оранжевая метка; без неё — белая)", function(r, v) r.who = v or nil end)
	autoBox = CreateFrame("Frame", nil, form)
	autoBox:SetPoint("TOPLEFT", 0, y)
	autoBox:SetPoint("RIGHT", form, "RIGHT", -8, 0)
	autoBox:SetHeight(84)
	f_mode = SegField(autoBox, 0, "|cffff7070Автоматика|r", MODE, function(r, key)
		r.off = key == "off" or nil
		r.instant = key == "instant" or nil
	end)
	for i = 1, 2 do
		local lab = UI.Text(autoBox, "GameFontHighlightSmall")
		lab:SetTextColor(0.66, 0.66, 0.71)
		local e = UI.EditBox(autoBox, 70, nil)
		lab:SetPoint("TOPLEFT", LABEL_W + 6 + (i - 1) * 190, -FIELD_H - 5)
		e:SetPoint("LEFT", lab, "RIGHT", 8, 0)
		e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		e:HookScript("OnEditFocusLost", function(self)
			local r = Rule()
			if not r or loaded ~= r or not self.pkey then return end
			local v = tonumber(self:GetText())
			if v and v >= 0 and v ~= ns.RuleParam(r, self.pkey) then
				r.params = r.params or {}
				r.params[self.pkey] = v
				Changed()
			end
		end)
		e.label = lab
		paramEdits[i] = e
	end
	f_how = UI.Text(autoBox, "GameFontDisableSmall")
	f_how:SetPoint("TOPLEFT", 0, -2 * FIELD_H - 4)
	f_how:SetPoint("RIGHT", autoBox, "RIGHT", 0, 0)
	f_how:SetHeight(28)
	f_how:SetJustifyV("TOP")

	-- кнопки снизу
	upBtn = UI.FlatButton(form, "Выше", 56, 22, function()
		local r = Rule()
		if r then ns.MoveRule(RS(), r, -1) Changed() end
	end, "ghost")
	upBtn:SetPoint("BOTTOMLEFT", 0, 8)
	downBtn = UI.FlatButton(form, "Ниже", 56, 22, function()
		local r = Rule()
		if r then ns.MoveRule(RS(), r, 1) Changed() end
	end, "ghost")
	downBtn:SetPoint("LEFT", upBtn, "RIGHT", 4, 0)
	dupBtn = UI.FlatButton(form, "Дублировать", 96, 22, function()
		local r = Rule()
		local copy = r and ns.DuplicateRule(RS(), r)
		if copy then
			ns.ui.editRule = copy.id
			Changed(true)
		end
	end, "ghost")
	dupBtn:SetPoint("LEFT", downBtn, "RIGHT", 4, 0)
	delBtn = UI.FlatButton(form, "Удалить", 80, 22, function()
		local r = Rule()
		if r and not r.auto then StaticPopup_Show("RAIDMINUS_DELETE_RULE", ns.ShortText(r.text), nil, r) end
	end, "ghost")
	delBtn:SetPoint("BOTTOMRIGHT", -8, 8)
	delBtn.tooltip = function(tt)
		local r = Rule()
		tt:SetText(r and r.auto and "Встроенное правило можно только выключить" or "Удалить правило")
	end
end

-- поля из правила (текст — только при смене правила, чтобы не стереть набираемое)
local function LoadForm(r)
	local kind = ns.RuleKind(r)
	kindTag:SetText("|c" .. ns.KIND_HEX[kind] .. "[" .. ns.KIND_NAMES[kind] .. "]|r")
	header:SetText(ns.RuleText(r))
	enabled:SetChecked(not r.off)
	if loaded ~= r then
		f_text.Load(r)
		f_chat.Load(r)
		f_note.Load(r)
		f_value:SetText(tostring(math.abs(r.value or 0)))
		f_step:SetText(r.step and tostring(math.abs(r.step)) or "")
		loaded = r
	end
	local sec = ns.Section(r.boss)
	f_section:SetValue(r.boss, sec and sec.name or r.boss)
	if r.auto then f_section:SetEnabledFlat(false) else f_section:SetEnabledFlat(true) end
	f_sign:SetValue(ns.IsPlus(r) and "plus" or "minus")
	f_kick:SetChecked(r.kick)
	f_rep:SetValue(r.rep or "each")
	for key, b in pairs(rolePills) do b:SetSelected(not r.roles or r.roles[key]) end
	f_diff:SetValue(r.diff or "any")
	f_ann:SetValue(r.ann or "default", ANN_TEXT[r.ann or "default"])
	f_whisper:SetChecked(r.whisper)
	f_quick:SetChecked(r.quick)

	local d = ns.Detector(r.auto)
	if d then
		f_who:Hide()
		autoBox:Show()
		f_mode:SetValue(r.off and "off" or (r.instant and "instant" or "review"))
		for i, e in ipairs(paramEdits) do
			local p = d.params and d.params[i]
			if p then
				e.pkey = p.key
				e.label:SetText(p.name)
				if not e:HasFocus() then e:SetText(tostring(ns.RuleParam(r, p.key))) end
				e.label:Show()
				e:Show()
			else
				e.pkey = nil
				e.label:Hide()
				e:Hide()
			end
		end
		f_how:SetText("Как ловится: " .. d.how .. (r.label and "\nСвой текст: числа в нём сами не меняются." or ""))
		delBtn:SetEnabledFlat(false)
		dupBtn:SetEnabledFlat(false)
	else
		autoBox:Hide()
		f_who:Show()
		f_who:SetChecked(r.who)
		delBtn:SetEnabledFlat(true)
		dupBtn:SetEnabledFlat(true)
	end
end

-------------------------------------------------------------------------------
-- разделы и список правил

-- перед сменой правила: дописать то, что набрано в полях (фокус в WoW сам не уходит)
local function CommitAll()
	if not form then return end
	for _, e in ipairs({f_text, f_chat, f_note, f_value, f_step, paramEdits[1], paramEdits[2]}) do
		if e:HasFocus() then e:ClearFocus() end
	end
end

local function MakeRow(row)
	row.kind = UI.KindMark(row)
	row.kind:SetPoint("LEFT", 4, 0)
	row.value = UI.Text(row, "GameFontHighlight", "RIGHT")
	row.value:SetPoint("RIGHT", -4, 0)
	row.value:SetWidth(40)
	row.text = UI.Text(row, "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 14, 0)
	row.text:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
	row.text:SetHeight(14)
	row:SetScript("OnClick", function(self, button)
		local r = self.item and self.item.rule
		if not r then return end
		if button == "RightButton" then
			ns.RuleMenu(r)
			return
		end
		CommitAll()
		ns.ui.editRule = r.id
		loaded = nil
		ns.RefreshUI()
	end)
end

local function DrawRow(row, item)
	if item.header then
		row:Disable()
		row.kind:Hide()
		row.text:SetText(item.header)
		row.value:SetText("")
		row.bg:SetTexture(0, 0, 0, 0)
		return
	end
	local r = item.rule
	row:Enable()
	row.kind:SetVertexColor(unpack(ns.KIND_COLORS[ns.RuleKind(r)]))
	row.kind:SetAlpha(r.off and 0.3 or 1)
	row.kind:Show()
	local text = ns.RuleText(r)
	if r.off then text = "|cff707070" .. text .. "|r" end
	if r.quick then text = text .. " |cffffd100»|r" end
	row.text:SetText(text)
	row.value:SetText((r.kick and r.value == 0) and "|cffff5050кик|r" or ns.ValueColor(r.value))
	UI.Select(row, ns.ui.editRule == r.id)
end

local function Items()
	local rs = RS()
	local items = {}
	for _, sign in ipairs({"minus", "plus"}) do
		local list = ns.RulesFor(rs, Section(), sign)
		tinsert(items, {header = format("|cff9d9d9d%s · %d|r", sign == "plus" and "ПЛЮСЫ" or "МИНУСЫ", #list)})
		for _, r in ipairs(list) do tinsert(items, {rule = r}) end
	end
	return items
end

local function Create(f)
	local setLabel = UI.Text(f, "GameFontHighlightSmall")
	setLabel:SetPoint("TOPLEFT", 2, -6)
	setLabel:SetText("Свод:")
	rulesetDD = UI.Dropdown(f, 200, function()
		local items = {}
		for _, rs in ipairs(ns.DB.rulesets) do tinsert(items, {rs.id, rs.name}) end
		return items
	end, function(id)
		CommitAll()
		ns.SetActiveRuleset(id)
		ns.ui.editRule = nil
		Changed(true)
	end)
	rulesetDD:SetPoint("LEFT", setLabel, "RIGHT", 8, 0)
	local newBtn = UI.FlatButton(f, "Новый", 64, 22, function()
		local rs = ns.EmptyRuleset("Новый свод")
		ns.SetActiveRuleset(rs.id)
		Changed(true)
	end, "ghost")
	newBtn:SetPoint("LEFT", rulesetDD, "RIGHT", 6, 0)
	newBtn.tooltip = function(tt) tt:SetText("Новый свод: только встроенные автоправила") end
	local copyBtn = UI.FlatButton(f, "Копия", 64, 22, function()
		local rs = ns.CopyRuleset(RS())
		ns.SetActiveRuleset(rs.id)
		Changed(true)
	end, "ghost")
	copyBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
	local delSet = UI.FlatButton(f, "Удалить", 70, 22, function()
		if #ns.DB.rulesets < 2 then
			ns.Print("это единственный свод.")
			return
		end
		StaticPopup_Show("RAIDMINUS_DELETE_SET", RS().name, nil, RS())
	end, "ghost")
	delSet:SetPoint("LEFT", copyBtn, "RIGHT", 4, 0)
	local share = UI.FlatButton(f, "Название, обмен строкой", 170, 22, function() ns.OpenOptions("sets") end, "ghost")
	share:SetPoint("LEFT", delSet, "RIGHT", 4, 0)
	local hint = UI.Text(f, "GameFontDisableSmall", "RIGHT")
	hint:SetPoint("TOPRIGHT", 0, -6)
	hint:SetPoint("LEFT", share, "RIGHT", 10, 0)
	hint:SetText("Поставленные минусы правка не меняет")

	-- разделы
	local box = UI.Box(f)
	box:SetPoint("TOPLEFT", 0, -30)
	box:SetWidth(SEC_W)
	local y = -4
	for _, sec in ipairs(ns.SECTIONS) do
		local key = sec.key
		if sec.general then y = y - 6 end
		local b = UI.FlatButton(box, sec.short, SEC_W - 8, 24, function()
			CommitAll()
			ns.ui.editSection = key
			ns.ui.editRule = nil
			loaded = nil
			ns.RefreshUI()
		end, "row")
		b:SetPoint("TOPLEFT", 4, y)
		b.label:SetFontObject("GameFontHighlightSmall")
		secButtons[key] = b
		y = y - 25
	end
	box:SetHeight(-y + 4)

	list = UI.List(f, ROWS, ROW_H, MakeRow)
	list:SetPoint("TOPLEFT", SEC_W + 10, -30)
	list:SetWidth(LIST_W)
	list.redraw = ns.RefreshUI
	addMinus = UI.FlatButton(f, "+ Минус", LIST_W / 2 - 2, 22, function()
		CommitAll()
		local r = ns.AddRule(RS(), Section(), false)
		ns.ui.editRule = r.id
		Changed(true)
	end, "ghost")
	addMinus:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)
	addMinus:SetTextColor({1, 0.45, 0.45})
	addPlus = UI.FlatButton(f, "+ Плюс", LIST_W / 2 - 2, 22, function()
		CommitAll()
		local r = ns.AddRule(RS(), Section(), true)
		ns.ui.editRule = r.id
		Changed(true)
	end, "ghost")
	addPlus:SetPoint("LEFT", addMinus, "RIGHT", 4, 0)
	addPlus:SetTextColor({0.45, 1, 0.45})

	CreateForm(f)
end

local function Update()
	local rs = RS()
	rulesetDD:SetValue(rs.id, rs.name)
	for _, sec in ipairs(ns.SECTIONS) do
		local b = secButtons[sec.key]
		local n = #ns.RulesFor(rs, sec.key)
		b:SetLabel((sec.general and "|cffffd100" .. sec.short .. "|r" or sec.short) .. format("  |cff8e8e9b%d|r", n))
		b:SetSelected(Section() == sec.key)
	end
	local r = Rule()
	list:Draw(Items(), DrawRow)
	if r then
		form:Show()
		empty:Hide()
		LoadForm(r)
	else
		form:Hide()
		empty:Show()
	end
end

ns.RegisterPage("rules", Create, Update)
