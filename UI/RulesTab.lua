-- Вкладка «Правила»: редактор свода (работает и без рейда).
-- Слева разделы (12 боссов и «Общие»), в центре правила раздела (минусы и плюсы), справа выбранное
-- правило — три подвкладки, как в WeakAuras:
--   «Правило»  — текст, раздел, минус или плюс и очки;
--   «Триггер»  — тип и его поля (что ловить и кто виноват), у «Своего кода» — поле кода;
--   «Условия»  — с какого раза, не чаще, сложность, роль виновного.
-- Правка сразу видна в окне; уже поставленные минусы не меняются: запись журнала хранит текст и очки.

local _, ns = ...
local UI = ns.UI

local format, tinsert = string.format, table.insert
local ipairs, pairs, tonumber, tostring = ipairs, pairs, tonumber, tostring

local SEC_W, LIST_W, ROWS, ROW_H, FIELD_H = 140, 286, 21, 22, 27
local LABEL_W = 116
local SEEN_MENU = 30 -- больше замеченных заклинаний — список в чат

local secButtons = {}
local rulesetDD, list
local form, empty, kindTag, header, onCheck
local subButtons, subPages = {}, {}
local edits = {}   -- поля ввода формы: перед сменой правила снять фокус (дописать набранное)
local loaders = {} -- function(rule, full): full — заново и текстовые поля (сменилось правило или тип)
local typeFrames = {}
local trigInfo, noTrig
local loaded, loadedType -- правило (и тип его триггера), чьи поля сейчас в форме

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

local function SubTab() return ns.ui.ruleTab or "rule" end

local function Changed(reload)
	if reload then loaded = nil end
	ns.TriggersDirty()
	ns.Refresh()
end

-- открыть правило в редакторе (шестерёнка, ПКМ → «Настроить…»); tab — подвкладка
function ns.EditRule(rule, tab)
	ns.ui.editSection = rule.boss
	ns.ui.editRule = rule.id
	if tab then ns.ui.ruleTab = tab end
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

local menuFrame
local function Menu(menu)
	if not menuFrame then menuFrame = CreateFrame("Frame", "RaidMinusRulesMenu", UIParent, "UIDropDownMenuTemplate") end
	EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
end

-------------------------------------------------------------------------------
-- поля формы: подпись слева, поле справа; get(rule) / set(rule, value)

local function Label(parent, text, y)
	local fs = UI.Text(parent, "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", 0, y - 5)
	fs:SetWidth(LABEL_W)
	fs:SetTextColor(0.66, 0.66, 0.71)
	fs:SetText(text)
	return fs
end

local function Hint(parent, anchor, text, width)
	local fs = UI.Text(parent, "GameFontDisableSmall")
	fs:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
	fs:SetWidth(width or 200)
	fs:SetText(text)
	return fs
end

-- текстовое (или числовое: num) поле; правится по Enter или при уходе фокуса
local function TextField(parent, y, label, width, placeholder, get, set, num)
	Label(parent, label, y)
	local e = UI.EditBox(parent, width, placeholder)
	e:SetPoint("TOPLEFT", LABEL_W + 6, y - 2)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	e:HookScript("OnEditFocusLost", function(self)
		local r = Rule()
		if not r or loaded ~= r then return end
		local text = strtrim(self:GetText())
		local value = text
		if num then
			value = tonumber((text:gsub(",", ".")))
			if value and value <= 0 then value = nil end
		elseif text == "" then
			value = nil
		end
		if value ~= get(r) then
			set(r, value)
			Changed()
		end
		local v = get(r)
		self:SetText(v and tostring(v) or "")
	end)
	tinsert(edits, e)
	tinsert(loaders, function(r, full)
		if not full or e:HasFocus() then return end
		local v = get(r)
		e:SetText(v and tostring(v) or "")
		e:SetCursorPosition(0)
		if e.UpdateHint then e.UpdateHint() end
	end)
	return e
end

local function SegField(parent, y, label, options, get, set)
	Label(parent, label, y)
	local seg = UI.Seg(parent, options, function(key)
		local r = Rule()
		if r then
			set(r, key)
			Changed()
		end
	end)
	seg:SetPoint("TOPLEFT", LABEL_W + 6, y - 2)
	tinsert(loaders, function(r) seg:SetValue(get(r)) end)
	return seg
end

-- items() -> {{key, text}}
local function DropField(parent, y, label, width, items, get, set)
	Label(parent, label, y)
	local dd = UI.Dropdown(parent, width, items, function(key)
		local r = Rule()
		if r then
			set(r, key)
			Changed(true)
		end
	end)
	dd:SetPoint("TOPLEFT", LABEL_W + 6, y - 2)
	tinsert(loaders, function(r)
		local key = get(r)
		local text = "—"
		for _, it in ipairs(items()) do
			if it[1] == key then text = it[2] end
		end
		dd:SetValue(key, text)
	end)
	return dd
end

-------------------------------------------------------------------------------
-- подвкладка «Правило»

local SIGN = {{"minus", "Минус", 70}, {"plus", "Плюс", 70}}

local function SetValue(r, abs)
	abs = math.abs(abs or 0)
	r.value = ns.IsPlus(r) and abs or -abs
end

local function CreateRulePage(p)
	local y = 0
	TextField(p, y, "Текст", 340, nil, function(r) return r.text end, function(r, t)
		if t and t ~= "" then r.text = t end
	end)
	y = y - FIELD_H
	local hint = UI.Text(p, "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", LABEL_W + 8, y + 4)
	hint:SetText("Пояснение в скобках в конце текста видно в окне, но в чат не идёт.")
	y = y - 14

	DropField(p, y, "Раздел", 180, function()
		local items = {}
		for _, sec in ipairs(ns.SECTIONS) do tinsert(items, {sec.key, sec.name}) end
		return items
	end, function(r) return r.boss end, function(r, key)
		ns.SetRuleSection(r, key)
		ns.ui.editSection = key
	end)
	y = y - FIELD_H

	local sign = SegField(p, y, "Минус или плюс", SIGN, function(r) return ns.IsPlus(r) and "plus" or "minus" end, function(r, key)
		local abs = math.abs(r.value or 0)
		if abs == 0 then abs = 10 end
		r.value = key == "plus" and abs or -abs
		loaded = nil
	end)
	local vLabel = UI.Text(p, "GameFontHighlightSmall")
	vLabel:SetPoint("LEFT", sign, "RIGHT", 12, 0)
	vLabel:SetTextColor(0.66, 0.66, 0.71)
	vLabel:SetText("Очки")
	local value = UI.EditBox(p, 40, nil)
	value:SetPoint("LEFT", vLabel, "RIGHT", 8, 0)
	value:SetNumeric(true)
	value:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	value:HookScript("OnEditFocusLost", function(self)
		local r = Rule()
		if not r or loaded ~= r then return end
		local v = tonumber(self:GetText())
		if v and v ~= math.abs(r.value or 0) then
			SetValue(r, v)
			Changed()
		end
	end)
	tinsert(edits, value)
	tinsert(loaders, function(r, full)
		if full and not value:HasFocus() then value:SetText(tostring(math.abs(r.value or 0))) end
	end)
	local prev = value
	for _, n in ipairs({10, 20, 30, 50}) do
		local b = UI.FlatButton(p, tostring(n), 26, 20, function()
			local r = Rule()
			if not r then return end
			SetValue(r, n)
			loaded = nil
			Changed()
		end, "ghost")
		b:SetPoint("LEFT", prev, "RIGHT", prev == value and 8 or 3, 0)
		prev = b
	end
	y = y - FIELD_H - 10

	local line = UI.Flat(p, "ARTWORK", 0.16, 0.18, 0.22, 1)
	line:SetPoint("TOPLEFT", 0, y)
	line:SetPoint("TOPRIGHT", -8, y)
	line:SetHeight(1)
	y = y - 10
	Label(p, "Триггер", y)
	local summary = UI.Text(p, "GameFontHighlightSmall")
	summary:SetPoint("TOPLEFT", LABEL_W + 8, y - 5)
	summary:SetPoint("RIGHT", p, "RIGHT", -8, 0)
	summary:SetJustifyV("TOP")
	summary:SetHeight(42)
	tinsert(loaders, function(r) summary:SetText(ns.TrigSummary(r)) end)
	y = y - 48
	local go = UI.FlatButton(p, "Настроить триггер", 140, 22, function()
		ns.ui.ruleTab = "trig"
		ns.RefreshUI()
	end, "ghost")
	go:SetPoint("TOPLEFT", LABEL_W + 6, y)
	local goCond = UI.FlatButton(p, "Условия", 80, 22, function()
		ns.ui.ruleTab = "cond"
		ns.RefreshUI()
	end, "ghost")
	goCond:SetPoint("LEFT", go, "RIGHT", 4, 0)
	y = y - 34
	local about = UI.Text(p, "GameFontDisableSmall")
	about:SetPoint("TOPLEFT", 0, y)
	about:SetPoint("RIGHT", p, "RIGHT", -8, 0)
	about:SetJustifyV("TOP")
	about:SetHeight(60)
	about:SetText("Вручную правило ставится всегда: выберите игроков во вкладке «Минусы» и нажмите правило "
		.. "(или клавиша «минус цели»). Включённый триггер ставит минус сам — сразу, без проверки; "
		.. "ошибку снимают во вкладке «Журнал».")
end

-------------------------------------------------------------------------------
-- подвкладка «Триггер»: поля каждого типа — на своей панели

-- поле триггера (правило без триггера — пусто, правка ничего не делает)
local function T(r) return r.trig or {} end

-- поле «Заклинание» + кнопка «Из боя»: способности, замеченные у врагов в бою с этим боссом
local function SeenButton(parent, anchor, key)
	local b = UI.FlatButton(parent, "Из боя", 56, 20, function()
		local r = Rule()
		if not r or not r.trig then return end
		local boss = r.boss ~= "general" and r.boss or ns.CurrentBoss()
		local spells = boss and ns.SeenSpells(boss) or {}
		if #spells == 0 then
			ns.Print("заклинаний этого босса ещё не видно: они записываются в бою с ним.")
			return
		end
		local function add(id)
			local cur = r.trig[key]
			r.trig[key] = (cur and cur ~= "") and (cur .. ", " .. id) or tostring(id)
			Changed(true)
		end
		if #spells > SEEN_MENU then
			ns.Print(format("замечено в бою с боссом %s (%d) — впишите номер в поле:", ns.ShortName(boss), #spells))
			for _, s in ipairs(spells) do DEFAULT_CHAT_FRAME:AddMessage(format("  |cffffd100%d|r %s", s.id, tostring(s.name))) end
			return
		end
		local menu = {{text = "Замечено в бою: " .. ns.ShortName(boss), isTitle = true, notCheckable = true}}
		for _, s in ipairs(spells) do
			local id = s.id
			tinsert(menu, {text = format("%s |cff9d9d9d%d|r", tostring(s.name), id), notCheckable = true, func = function() add(id) end})
		end
		Menu(menu)
	end, "ghost")
	b:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
	b.tooltip = function(tt)
		tt:SetText("Заклинания из боя")
		tt:AddLine("Способности врагов, замеченные в бою с боссом этого раздела: клик — добавить номер в поле.", 1, 1, 1, true)
	end
	return b
end

local function TrigText(p, y, label, key, width, placeholder, seen)
	local e = TextField(p, y, label, width or 250, placeholder, function(r) return T(r)[key] end, function(r, v) T(r)[key] = v end)
	if seen then SeenButton(p, e, key) end
	return e
end

local function TrigNum(p, y, label, key, placeholder, hint)
	local e = TextField(p, y, label, 60, placeholder, function(r) return T(r)[key] end, function(r, v) T(r)[key] = v end, true)
	if hint then Hint(p, e, hint, 260) end
	return e
end

local function TrigSeg(p, y, label, key, options, default)
	return SegField(p, y, label, options, function(r)
		local v = T(r)[key]
		if v == nil then v = type(default) == "function" and default(T(r)) or default end
		return v
	end, function(r, v) T(r)[key] = v end)
end

local SPELLS = "номера или названия через запятую; пусто — любое"
local FROM = "NPC ID или имя; пусто — любой"

local BUILD = {}

BUILD.fail = function(p, y)
	DropField(p, y, "Неудача", 300, function()
		local r = Rule()
		local items = {}
		for _, f in ipairs(ns.FailsFor(r and r.boss or "general")) do tinsert(items, {f[1], f[3]}) end
		return items
	end, function(r) return T(r).fail end, function(r, key) T(r).fail = key end)
	return "LibFail (входит в Skada) сам решает, кто ошибся. Нужна включённая Skada. Неудачи босса раздела; в «Общих» — все."
end

BUILD.combat = function(p, y)
	DropField(p, y, "Событие", 220, function()
		local items = {}
		for _, c in ipairs(ns.COMBAT_EVENTS) do tinsert(items, {c.key, c.name}) end
		return items
	end, function(r) return T(r).event or "damage" end, function(r, key)
		T(r).event = key
		local ce = ns.CombatEvent(key)
		T(r).who = ce and ce.who or nil
	end)
	y = y - FIELD_H
	TrigText(p, y, "Заклинание", "spell", 250, SPELLS, true)
	y = y - FIELD_H
	TrigText(p, y, "От кого", "from", 250, FROM)
	y = y - FIELD_H
	TrigSeg(p, y, "Виноват", "who", {{"dst", "цель", 70}, {"src", "источник", 80}}, function(t)
		local ce = ns.CombatEvent(t.event or "damage")
		return ce and ce.who or "dst"
	end)
	y = y - FIELD_H
	TrigNum(p, y, "Урон от", "amount", nil, "пусто — любой")
	y = y - FIELD_H
	TrigNum(p, y, "Серия дольше, сек", "streak", nil, "стоял под уроном (удары не реже раза в 2 сек)")
	return "Цель — на ком урон или аура; источник — кто применил (питомец — его хозяин). Виноватый должен быть в рейде."
end

BUILD.death = function(p, y)
	TrigText(p, y, "Последний удар", "spell", 250, SPELLS, true)
	y = y - FIELD_H
	TrigText(p, y, "От кого", "from", 250, FROM)
	y = y - FIELD_H
	TrigSeg(p, y, "Виноват", "who", {{"dst", "умерший", 80}, {"src", "убийца (игрок рейда)", 150}}, "dst")
	return "Смерть — удар с перебором здоровья по игроку рейда. «Убийца» — для МК и подобного: игрок рейда, чей удар убил."
end

BUILD.aura = function(p, y)
	TrigText(p, y, "Аура", "spell", 250, SPELLS, true)
	y = y - FIELD_H
	TrigNum(p, y, "Стаков от", "stacks", nil, "пусто — сразу, как легла")
	y = y - FIELD_H
	TrigNum(p, y, "Дольше, сек", "dur", nil, "держится дольше (не сняли вовремя)")
	return "Виноват игрок рейда, на котором аура."
end

BUILD.yell = function(p, y)
	TrigText(p, y, "Текст содержит", "text", 330, "часть крика, эмоции или шёпота босса")
	return "Виноват игрок, чьё имя есть в сообщении босса (шёпот босса — вы)."
end

BUILD.pull = function(p, y)
	TrigNum(p, y, "Раньше на, сек", "early", "1", "пусто — на 1 сек и больше")
	return "Пулл-таймер DBM ещё шёл, а босса уже тронули: виноват первый, кто ударил, повесил дебафф или таунтнул "
		.. "(питомец — хозяин). Пулы видно командой /rm лог пул."
end

BUILD.skada = function(p, y)
	TrigSeg(p, y, "Показатель", "metric", {{"dps", "ДПС", 60}, {"damage", "Урон", 60}, {"target", "Урон по цели", 110}}, "dps")
	y = y - FIELD_H
	TrigText(p, y, "Цель", "target", 250, "для «урон по цели»: имена или NPC ID")
	y = y - FIELD_H
	TrigSeg(p, y, "Условие", "op", {{"lt", "меньше", 80}, {"ge", "не меньше", 90}}, "lt")
	y = y - FIELD_H
	TrigNum(p, y, "Число", "num", "17000")
	return "После убийства босса, по законченному бою Skada — каждому игроку рейда, кто подходит "
		.. "(роль — во вкладке «Условия»: например, только мдд и рдд)."
end

local CODE_EXAMPLE = [[
function(event, _, sub, _, srcName, _, _, dstName, _, spellId)
  -- журнал боя: event, timestamp, subevent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, ...
  if sub == "SPELL_DAMAGE" and spellId == 12345 and RM.InRaid(dstName) then
    return dstName, "попал под заклинание"
  end
end]]

BUILD.code = function(p, y)
	TrigText(p, y, "События", "events", 330, "COMBAT_LOG_EVENT_UNFILTERED, RM_START")
	y = y - FIELD_H - 2
	local box = UI.CodeBox(p, 474, 230, function(text)
		local r = Rule()
		if not r or loaded ~= r or not r.trig then return end
		text = strtrim(text)
		if text == "" then text = nil end
		if text ~= r.trig.code then
			r.trig.code = text
			Changed()
		end
	end)
	box:SetPoint("TOPLEFT", 0, y)
	tinsert(edits, box.edit)
	tinsert(loaders, function(r, full)
		if full and not box.edit:HasFocus() then box:SetCode(T(r).code) end
	end)
	y = y - 236
	local check = UI.FlatButton(p, "Проверить код", 110, 22, function()
		local r = Rule()
		if not r or not r.trig then return end
		if box.edit:HasFocus() then box.edit:ClearFocus() end
		local err = ns.CheckTriggerCode(r.trig.code)
		if err then ns.Print("|cffff5050ошибка в коде:|r " .. err) else ns.Print("код без ошибок.") end
	end, "ghost")
	check:SetPoint("TOPLEFT", 0, y)
	local example = UI.FlatButton(p, "Пример", 70, 22, function()
		local r = Rule()
		if not r or not r.trig then return end
		r.trig.code = CODE_EXAMPLE
		if not r.trig.events then r.trig.events = "COMBAT_LOG_EVENT_UNFILTERED" end
		Changed(true)
	end, "ghost")
	example:SetPoint("LEFT", check, "RIGHT", 4, 0)
	example.tooltip = function(tt) tt:SetText("Заменить код примером") end
	local help = UI.FlatButton(p, "Справка", 70, 22, nil, "ghost")
	help:SetPoint("LEFT", example, "RIGHT", 4, 0)
	help.tooltip = function(tt)
		tt:SetText("Свой код")
		tt:AddLine("function(event, ...) ... return \"Имя\", \"что было\" end — вернуть имя виноватого (игрок рейда).", 1, 1, 1, true)
		tt:AddLine("События — через запятую: любые события WoW, COMBAT_LOG_EVENT_UNFILTERED (журнал боя), "
			.. "RM_START (начало боя, ключ босса), RM_END (конец: ключ, kill или wipe), RM_SKADA (после убийства: бой Skada).", 0.8, 0.8, 0.8, true)
		tt:AddLine("RM.Fire(имя, текст) — поставить сейчас; RM.After(сек, функция) — позже в этом бою; "
			.. "RM.Role, RM.Class, RM.InRaid, RM.Players, RM.Unit, RM.NpcId, RM.Owner, RM.Is(x, 1, 2, ...), RM.Time, "
			.. "RM.FightTime, RM.Boss, RM.Short; Skada: RM.SkadaPlayers, RM.SkadaDamage, RM.SkadaTime, RM.SkadaTargets, RM.SkadaEnemies.", 0.8, 0.8, 0.8, true)
		tt:AddLine("fight — таблица на бой (очищается на пуле): храните в ней, что нужно.", 0.8, 0.8, 0.8, true)
		tt:AddLine("Код работает только в бою с боссом раздела; ошибка — правило молчит до конца боя.", 1, 0.82, 0, true)
	end
	return nil
end

local TYPE_ITEMS
local function TypeItems()
	if not TYPE_ITEMS then
		TYPE_ITEMS = {{"none", "Нет — только вручную"}}
		for _, t in ipairs(ns.TRIG_TYPES) do tinsert(TYPE_ITEMS, {t.key, t.name}) end
	end
	return TYPE_ITEMS
end

local function CreateTrigPage(p)
	DropField(p, 0, "Тип триггера", 220, TypeItems, function(r) return r.trig and r.trig.type or "none" end,
		function(r, key)
			if key == "none" then
				r.trig = nil
			elseif r.trig then
				r.trig.type = key
			else
				r.trig = {type = key}
			end
		end)
	local line = UI.Flat(p, "ARTWORK", 0.16, 0.18, 0.22, 1)
	line:SetPoint("TOPLEFT", 0, -FIELD_H - 4)
	line:SetPoint("TOPRIGHT", -8, -FIELD_H - 4)
	line:SetHeight(1)

	noTrig = UI.Text(p, "GameFontDisable")
	noTrig:SetPoint("TOPLEFT", 0, -FIELD_H - 16)
	noTrig:SetPoint("RIGHT", p, "RIGHT", -8, 0)
	noTrig:SetJustifyV("TOP")
	noTrig:SetHeight(120)
	noTrig:SetText("У правила нет триггера — его ставит только РЛ.\n\nВыберите тип, чтобы правило ставилось само:\n"
		.. "неудача из Skada, событие журнала боя, смерть, аура, сообщение босса, пул раньше таймера, цифры Skada после убийства "
		.. "или свой код на Lua. Готовые правила — кнопка «+ Шаблон» под списком.")

	for _, t in ipairs(ns.TRIG_TYPES) do
		local f = CreateFrame("Frame", nil, p)
		f:SetPoint("TOPLEFT", 0, -FIELD_H - 12)
		f:SetPoint("BOTTOMRIGHT", 0, 0)
		local first = #loaders + 1
		local help = BUILD[t.key](f, 0)
		f.loaders = {}
		for i = first, #loaders do tinsert(f.loaders, loaders[i]) end
		for i = #loaders, first, -1 do table.remove(loaders, i) end
		if help then
			local h = UI.Text(f, "GameFontDisableSmall")
			h:SetPoint("BOTTOMLEFT", 0, 22)
			h:SetPoint("RIGHT", f, "RIGHT", -8, 0)
			h:SetJustifyV("BOTTOM")
			h:SetHeight(40)
			h:SetText(help)
		end
		f:Hide()
		typeFrames[t.key] = f
	end

	trigInfo = UI.Text(p, "GameFontHighlightSmall")
	trigInfo:SetPoint("BOTTOMLEFT", 0, 4)
	trigInfo:SetPoint("RIGHT", p, "RIGHT", -8, 0)
	trigInfo:SetHeight(14)
end

local function TrigInfoText(r)
	local x = ns.TrigInfo(r)
	if x and x.err then return "|cffff5050Ошибка в коде:|r " .. x.err end
	if x and x.last then
		return format("|cff9d9d9dПоследнее срабатывание:|r %s %s%s", date("%H:%M", x.last.t), x.last.name,
			x.last.detail and ("|cff9d9d9d — " .. x.last.detail .. "|r") or "")
	end
	if r.trig and not r.trig.on then return "|cffffd100Триггер выключен — включите галочкой вверху справа.|r" end
	return "|cff9d9d9dВ этом рейде ещё не срабатывал.|r"
end

-------------------------------------------------------------------------------
-- подвкладка «Условия»

local function CreateCondPage(p)
	local y = 0
	local c = TextField(p, y, "С какого раза", 40, nil, function(r) return r.trig and r.trig.count end,
		function(r, v) if r.trig then r.trig.count = v and math.floor(v) or nil end end, true)
	Hint(p, c, "за бой у одного игрока (пусто — с первого)", 300)
	y = y - FIELD_H
	SegField(p, y, "Не чаще", {{"each", "Каждый раз", 96}, {"fight", "Раз за бой", 90}, {"raid", "Раз за рейд", 96}},
		function(r) return r.trig and r.trig.per or "fight" end, function(r, v) if r.trig then r.trig.per = v end end)
	y = y - FIELD_H
	local hint = UI.Text(p, "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", LABEL_W + 8, y + 4)
	hint:SetText("«Каждый раз» — тому же игроку не чаще раза в 5 сек.")
	y = y - 14
	SegField(p, y, "Сложность", {{"any", "Любая", 70}, {"hc", "Только гер.", 96}, {"nm", "Только об.", 90}},
		function(r) return r.trig and r.trig.diff or "any" end,
		function(r, v) if r.trig then r.trig.diff = v ~= "any" and v or nil end end)
	y = y - FIELD_H

	Label(p, "Роль виновного", y)
	local px = LABEL_W + 6
	local pills = {}
	for _, role in ipairs(ns.ROLES) do
		local key = role.key
		local b = UI.FlatButton(p, role.name, 52, 20, function()
			local r = Rule()
			if not r or not r.trig then return end
			local set = r.trig.roles or {tank = true, healer = true, melee = true, caster = true}
			set[key] = (not set[key]) or nil
			local n = 0
			for _ in pairs(set) do n = n + 1 end
			r.trig.roles = (n > 0 and n < 4) and set or nil
			Changed()
		end, "pill")
		b:SetPoint("TOPLEFT", px, y - 2)
		pills[key] = b
		px = px + 56
	end
	tinsert(loaders, function(r)
		local roles = r.trig and r.trig.roles
		for key, b in pairs(pills) do b:SetSelected(not roles or roles[key]) end
	end)
	y = y - FIELD_H
	local roleHint = UI.Text(p, "GameFontDisableSmall")
	roleHint:SetPoint("TOPLEFT", LABEL_W + 8, y + 4)
	roleHint:SetText("По основной роли на рейд (хил, переодетый в ДД, — хил). Все включены — любая.")
	y = y - 30

	local about = UI.Text(p, "GameFontDisableSmall")
	about:SetPoint("TOPLEFT", 0, y)
	about:SetPoint("RIGHT", p, "RIGHT", -8, 0)
	about:SetJustifyV("TOP")
	about:SetHeight(60)
	about:SetText("Условия проверяются, когда сработал триггер. Вручную правило ставится всегда, без условий. "
		.. "«Раз за бой» и «раз за рейд» считают записи журнала: снятый минус можно поставить снова.")
end

-------------------------------------------------------------------------------
-- форма целиком

local SUBTABS = {{"rule", "Правило"}, {"trig", "Триггер"}, {"cond", "Условия"}}

local function CommitAll()
	for _, e in ipairs(edits) do
		if e:HasFocus() then e:ClearFocus() end
	end
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
	empty:SetText("В разделе нет правил — «+ Минус», «+ Плюс» или «+ Шаблон».")

	kindTag = UI.Text(form, "GameFontHighlightSmall")
	kindTag:SetPoint("TOPLEFT", 0, -2)
	header = UI.Text(form, "GameFontNormal")
	header:SetPoint("LEFT", kindTag, "RIGHT", 8, 0)
	header:SetPoint("RIGHT", form, "TOPRIGHT", -150, -9)
	header:SetHeight(14)
	onCheck = UI.Check(form, "Триггер включён", function(v)
		local r = Rule()
		if r and r.trig then
			r.trig.on = v or nil
			Changed()
		end
	end)
	onCheck:SetPoint("TOPRIGHT", -126, 2)
	local line = UI.Flat(form, "ARTWORK", 0.16, 0.18, 0.22, 1)
	line:SetPoint("TOPLEFT", 0, -22)
	line:SetPoint("TOPRIGHT", -8, -22)
	line:SetHeight(1)

	local prev
	for _, st in ipairs(SUBTABS) do
		local key = st[1]
		local b = UI.FlatButton(form, st[2], 90, 22, function()
			CommitAll()
			ns.ui.ruleTab = key
			ns.RefreshUI()
		end, "tab")
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("TOPLEFT", 0, -28) end
		subButtons[key] = b
		prev = b
	end

	for _, st in ipairs(SUBTABS) do
		local p = CreateFrame("Frame", nil, form)
		p:SetPoint("TOPLEFT", 0, -58)
		p:SetPoint("BOTTOMRIGHT", 0, 36)
		subPages[st[1]] = p
	end
	CreateRulePage(subPages.rule)
	CreateTrigPage(subPages.trig)
	CreateCondPage(subPages.cond)

	-- кнопки снизу
	local upBtn = UI.FlatButton(form, "Выше", 56, 22, function()
		local r = Rule()
		if r then ns.MoveRule(RS(), r, -1) Changed() end
	end, "ghost")
	upBtn:SetPoint("BOTTOMLEFT", 0, 8)
	local downBtn = UI.FlatButton(form, "Ниже", 56, 22, function()
		local r = Rule()
		if r then ns.MoveRule(RS(), r, 1) Changed() end
	end, "ghost")
	downBtn:SetPoint("LEFT", upBtn, "RIGHT", 4, 0)
	local dupBtn = UI.FlatButton(form, "Дублировать", 96, 22, function()
		CommitAll()
		local r = Rule()
		local copy = r and ns.DuplicateRule(RS(), r)
		if copy then
			ns.ui.editRule = copy.id
			Changed(true)
		end
	end, "ghost")
	dupBtn:SetPoint("LEFT", downBtn, "RIGHT", 4, 0)
	dupBtn.tooltip = function(tt) tt:SetText("Копия правила (триггер копии выключен)") end
	local delBtn = UI.FlatButton(form, "Удалить", 80, 22, function()
		local r = Rule()
		if r then StaticPopup_Show("RAIDMINUS_DELETE_RULE", ns.ShortText(r.text), nil, r) end
	end, "ghost")
	delBtn:SetPoint("BOTTOMRIGHT", -8, 8)
end

-- поля из правила: текстовые — только при смене правила или типа триггера (чтобы не стереть набираемое)
local function LoadForm(r)
	local kind = ns.RuleKind(r)
	kindTag:SetText("|c" .. ns.KIND_HEX[kind] .. "[" .. (r.trig and "триггер" or "вручную") .. "]|r")
	header:SetText(ns.RuleText(r))
	if r.trig then
		onCheck:Show()
		onCheck:SetChecked(r.trig.on)
	else
		onCheck:Hide()
	end
	local tab = SubTab()
	for key, b in pairs(subButtons) do b:SetSelected(key == tab) end
	for key, p in pairs(subPages) do
		if key == tab then p:Show() else p:Hide() end
	end

	local ttype = r.trig and r.trig.type
	local full = loaded ~= r or loadedType ~= ttype
	loaded, loadedType = r, ttype
	for _, fn in ipairs(loaders) do fn(r, full) end
	for key, f in pairs(typeFrames) do
		if key == ttype then
			f:Show()
			for _, fn in ipairs(f.loaders) do fn(r, full) end
		else
			f:Hide()
		end
	end
	if ttype then noTrig:Hide() else noTrig:Show() end
	trigInfo:SetText(r.trig and TrigInfoText(r) or "")
end

-------------------------------------------------------------------------------
-- разделы и список правил

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
	UI.Tooltip(row, function(tt, self)
		local r = self.item and self.item.rule
		if not r then return false end
		tt:SetText(ns.RuleText(r), 1, 1, 1, true)
		tt:AddLine("Триггер: " .. ns.TrigSummary(r), 0.8, 0.8, 0.8, true)
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
	row.kind:SetAlpha((r.trig and not r.trig.on) and 0.35 or 1)
	row.kind:Show()
	local text = ns.RuleText(r)
	if r.trig and not r.trig.on then text = text .. " |cff707070(выкл)|r" end
	row.text:SetText(text)
	row.value:SetText(ns.ValueColor(r.value))
	UI.Select(row, ns.ui.editRule == r.id)
end

local function Items()
	local rs = RS()
	local items = {}
	for _, sign in ipairs({"minus", "plus"}) do
		local rules = ns.RulesFor(rs, Section(), sign)
		tinsert(items, {header = format("|cff9d9d9d%s · %d|r", sign == "plus" and "ПЛЮСЫ" or "МИНУСЫ", #rules)})
		for _, r in ipairs(rules) do tinsert(items, {rule = r}) end
	end
	return items
end

-- «+ Шаблон»: готовые правила раздела (бывшие встроенные автоправила)
local function PresetMenu()
	local sec = Section()
	local presets = ns.PresetsFor(sec)
	if #presets == 0 then
		ns.Print("для раздела «" .. ns.Section(sec).name .. "» шаблонов нет — напишите правило сами.")
		return
	end
	local menu = {{text = "Шаблоны: " .. ns.Section(sec).name, isTitle = true, notCheckable = true}}
	for _, p in ipairs(presets) do
		local key = p.key
		tinsert(menu, {text = ns.PresetText(p) .. " |cff9d9d9d(" .. ns.TrigTypeName(p.trig({}).type) .. ")|r", notCheckable = true,
			func = function()
				CommitAll()
				local r = ns.AddPresetRule(RS(), key)
				if r then
					ns.ui.editRule = r.id
					ns.ui.ruleTab = "trig"
					ns.Print("добавлено правило «" .. r.text .. "» — триггер выключен: проверьте и включите.")
				end
				Changed(true)
			end})
	end
	Menu(menu)
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
	newBtn.tooltip = function(tt) tt:SetText("Новый пустой свод (готовые правила — «+ Шаблон»)") end
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
	local third = math.floor(LIST_W / 3) - 3
	local addMinus = UI.FlatButton(f, "+ Минус", third, 22, function()
		CommitAll()
		local r = ns.AddRule(RS(), Section(), false)
		ns.ui.editRule = r.id
		ns.ui.ruleTab = "rule"
		Changed(true)
	end, "ghost")
	addMinus:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)
	addMinus:SetTextColor({1, 0.45, 0.45})
	local addPlus = UI.FlatButton(f, "+ Плюс", third, 22, function()
		CommitAll()
		local r = ns.AddRule(RS(), Section(), true)
		ns.ui.editRule = r.id
		ns.ui.ruleTab = "rule"
		Changed(true)
	end, "ghost")
	addPlus:SetPoint("LEFT", addMinus, "RIGHT", 4, 0)
	addPlus:SetTextColor({0.45, 1, 0.45})
	local addPreset = UI.FlatButton(f, "+ Шаблон", third, 22, PresetMenu, "ghost")
	addPreset:SetPoint("LEFT", addPlus, "RIGHT", 4, 0)
	addPreset.tooltip = function(tt)
		tt:SetText("Готовое правило с триггером")
		tt:AddLine("Шаблоны этого раздела: смерти от способностей босса, дух на Леди, планка ДПС, пул раньше таймера и др. "
			.. "Триггер добавленного правила выключен — проверьте и включите.", 1, 1, 1, true)
	end

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
