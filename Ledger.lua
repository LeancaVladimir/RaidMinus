-- Журнал минусов и плюсов текущего рейда: поставить, снять (с причиной), вернуть, отменить
-- последний клик; итог игрока.
-- Запись хранит текст и очки правила целиком, поэтому правка свода не меняет журнал.
-- Ставит РЛ кликом или триггер правила (Triggers.lua) — тогда в записи auto и detail «что произошло».

local _, ns = ...

local format, tinsert, tremove = string.format, table.insert, table.remove
local ipairs = ipairs

local function NeedSession()
	local s = ns.Session()
	if not s then ns.Print("сначала начните рейд: кнопка «Начать рейд» или /rm старт.") end
	return s
end

-- сколько раз правило уже стоит игроку; fight = {boss, pull} — только в этом бою
function ns.RuleCount(name, ruleId, fight)
	local s = ns.Session()
	if not s or not ruleId then return 0 end
	local n = 0
	for _, ev in ipairs(s.events) do
		if ev.player == name and ev.rule == ruleId and ev.status ~= "cancelled"
			and (not fight or (ev.boss == fight.boss and ev.pull == fight.pull)) then
			n = n + 1
		end
	end
	return n
end

-- names — список имён; rule — правило свода или {boss, text, value} (свой минус);
-- auto — {detail = «что произошло», boss, pull}: запись от триггера, не попадает в «Отменить последнее».
-- Возвращает новые записи.
function ns.AddEvents(names, rule, auto)
	local s = NeedSession()
	local made = {}
	if not s or #names == 0 then return made end
	local group = {}
	local me = ns.PlayerName()
	for _, name in ipairs(names) do
		local p = s.roster[name]
		local boss = (auto and auto.boss) or (ns.IsBoss(rule.boss) and rule.boss) or s.boss
		local pull = (auto and auto.pull) or (boss and s.pulls[boss])
		s.nextId = s.nextId + 1
		local ev = {
			id = s.nextId,
			t = time(),
			player = name,
			class = p and p.class,
			text = ns.RuleText(rule),
			value = rule.value or 0,
			rule = rule.id,
			sec = rule.boss,
			boss = boss,
			pull = pull,
			by = auto and "триггер" or me,
			auto = auto and true or nil,
			detail = auto and auto.detail,
		}
		tinsert(s.events, ev)
		tinsert(group, ev.id)
		tinsert(made, ev)
		ns.QueueAnnounce(ev)
	end
	if not auto and #group > 0 then
		s.lastGroup = group
		if ns.OnEventsAdded then ns.OnEventsAdded(made) end
	end
	ns.Refresh()
	return made
end

-- /rm Имя -20 причина
function ns.AddCustom(nameQuery, value, text)
	local s = NeedSession()
	if not s then return end
	local name = ns.MatchName(nameQuery, ns.RosterNames())
	if not name then
		ns.Print(format("игрок «%s» не найден в составе рейда.", tostring(nameQuery)))
		return
	end
	text = strtrim(text or "")
	if text == "" then text = value >= 0 and "Плюс от РЛа" or "Минус от РЛа" end
	ns.AddEvents({name}, {boss = "general", text = text, value = value})
end

function ns.EventById(id)
	local s = ns.Session()
	if not s then return end
	for _, ev in ipairs(s.events) do
		if ev.id == id then return ev end
	end
end

local function RemoveEvent(ev)
	local s = ns.Session()
	for i, x in ipairs(s.events) do
		if x == ev then tremove(s.events, i) break end
	end
	ns.DropFromAnnounce(ev)
end

function ns.CancelEvent(ev, reason)
	if not ev or ev.status == "cancelled" then return end
	ev.status = "cancelled"
	ev.reason = reason ~= "" and reason or nil
	ev.cancelledBy = ns.PlayerName()
	ns.AnnounceCancel(ev)
	ns.Refresh()
end

function ns.RestoreEvent(ev)
	if not ev or ev.status ~= "cancelled" then return end
	ev.status, ev.reason, ev.cancelledBy = nil, nil, nil
	ns.QueueAnnounce(ev)
	ns.Refresh()
end

-- последний клик: записи, которые ещё можно отменить
function ns.LastGroup()
	local s = ns.Session()
	local out = {}
	if not s or not s.lastGroup then return out end
	for _, id in ipairs(s.lastGroup) do
		local ev = ns.EventById(id)
		if ev and ev.status ~= "cancelled" then tinsert(out, ev) end
	end
	return out
end

-- отмена последнего клика: ещё не объявленное удаляется молча, объявленное снимается с объявлением
function ns.UndoLast()
	local s = ns.Session()
	if not s or not s.lastGroup then
		ns.Print("нечего отменять.")
		return
	end
	local n = 0
	for _, ev in ipairs(ns.LastGroup()) do
		if ev.announced then
			ns.CancelEvent(ev, "ошибка")
		else
			RemoveEvent(ev)
		end
		n = n + 1
	end
	s.lastGroup = nil
	ns.Print(format("отменено записей: %d.", n))
	ns.Refresh()
end

-------------------------------------------------------------------------------
-- итоги

-- сумма и число записей
function ns.PlayerState(name)
	local s = ns.Session()
	local total, n = 0, 0
	if not s then return total, n end
	for _, ev in ipairs(s.events) do
		if ev.player == name and ev.status ~= "cancelled" then
			total = total + (ev.value or 0)
			n = n + 1
		end
	end
	return total, n
end

function ns.PlayerEvents(name)
	local s = ns.Session()
	local out = {}
	if not s then return out end
	for _, ev in ipairs(s.events) do
		if ev.player == name and ev.status ~= "cancelled" then tinsert(out, ev) end
	end
	return out
end

-- текст правила без пояснения в скобках в конце: «Дух (оспаривается с видео)» -> «Дух»
function ns.ShortText(text)
	local short = tostring(text or ""):gsub("%s*%b()%s*$", "")
	if short == "" then return tostring(text or "") end
	return short
end

-- текст записи для чата
function ns.EventChat(ev) return ns.ShortText(ev.text) end

-- «Вася -30 (Дух)»; withName = false — «Дух -30»
function ns.EventShort(ev, withName)
	if withName == false then return ns.EventChat(ev) .. " " .. ns.ValueText(ev.value) end
	return format("%s %s (%s)", ev.player, ns.ValueText(ev.value), ns.EventChat(ev))
end

-- «-40»
function ns.StateText(name, colored)
	local total = ns.PlayerState(name)
	return colored and ns.ValueColor(total) or ns.ValueText(total)
end
