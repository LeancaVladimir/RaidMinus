-- Журнал минусов и плюсов текущего рейда: поставить, снять (с причиной), вернуть, отменить
-- последний клик; итог игрока и допуск к роллу.
-- Запись хранит текст и очки правила целиком, поэтому правка свода не меняет журнал.
-- Настройки правила (Rules.lua) работают здесь: повтор, нарастание, роли, шёпот игроку, объявление.

local _, ns = ...

local format, tinsert, tremove, tconcat = string.format, table.insert, table.remove, table.concat
local ipairs = ipairs

local function NeedSession()
	local s = ns.Session()
	if not s then ns.Print("сначала начните рейд: кнопка «Начать рейд» или /rm старт.") end
	return s
end

-- сколько раз правило уже стоит игроку; scope "fight" — только в этом бою (босс и пул)
local function Count(s, name, ruleId, boss, pull, scope)
	if not ruleId then return 0 end
	local n = 0
	for _, ev in ipairs(s.events) do
		if ev.player == name and ev.rule == ruleId and ev.status ~= "cancelled"
			and (scope ~= "fight" or (ev.boss == boss and ev.pull == pull)) then
			n = n + 1
		end
	end
	return n
end

-- почему правило нельзя поставить игроку (nil — можно)
function ns.RuleBlock(rule, name, boss, pull)
	local s = ns.Session()
	if not s then return "рейд не начат" end
	if not ns.RuleRoleOk(rule, name) then return "не та роль" end
	if rule.rep == "raid" and Count(s, name, rule.id, boss, pull) > 0 then return "уже стоит за этот рейд" end
	if rule.rep == "fight" and Count(s, name, rule.id, boss, pull, "fight") > 0 then return "уже стоит за этот бой" end
end

-- names — список имён; rule — правило свода, его копия (находка) или {boss, text, value, kick};
-- auto — {detail = «что увидела автоматика», boss, pull}: запись от автоматики, не попадает в «Отменить последнее».
-- Возвращает новые записи.
function ns.AddEvents(names, rule, auto)
	local s = NeedSession()
	local made = {}
	if not s or #names == 0 then return made end
	local group, skipped = {}, {}
	local me = ns.PlayerName()
	for _, name in ipairs(names) do
		local p = s.roster[name]
		local boss = (auto and auto.boss) or (ns.IsBoss(rule.boss) and rule.boss) or s.boss
		local pull = (auto and auto.pull) or (boss and s.pulls[boss])
		local block = ns.RuleBlock(rule, name, boss, pull)
		if block then
			tinsert(skipped, name .. " — " .. block)
		else
			local value = rule.value or 0
			if rule.step then value = value + rule.step * Count(s, name, rule.id, boss, pull) end
			s.nextId = s.nextId + 1
			local ev = {
				id = s.nextId,
				t = time(),
				player = name,
				class = p and p.class,
				text = ns.RuleText(rule),
				chat = rule.chat or (rule.id and ns.ChatText(rule)) or nil,
				value = value,
				kick = rule.kick or nil,
				rule = rule.id,
				sec = rule.boss,
				boss = boss,
				pull = pull,
				by = auto and "авто" or me,
				auto = auto and true or nil,
				detail = auto and auto.detail,
				ann = rule.ann,
			}
			tinsert(s.events, ev)
			tinsert(group, ev.id)
			tinsert(made, ev)
			ns.QueueAnnounce(ev)
			if rule.whisper then ns.WhisperEvent(ev) end
		end
	end
	if #skipped > 0 then ns.Print("не поставлено: " .. tconcat(skipped, "; ") .. ".") end
	if not auto and #group > 0 then
		s.lastGroup = group
		if ns.OnEventsAdded then ns.OnEventsAdded(made) end
	end
	ns.Refresh()
	return made
end

-------------------------------------------------------------------------------
-- находки автоматики: ждут РЛа во вкладке «На проверку»;
-- у правила с «ставить сразу» (rule.instant) — сразу минус игроку

-- копия правила на момент находки (текст уже с числами РЛа)
local function CopyRule(rule)
	return {
		id = rule.id, boss = rule.boss, text = ns.RuleText(rule), chat = ns.ChatText(rule),
		value = rule.value, kick = rule.kick, det = rule.auto,
		rep = rule.rep, step = rule.step, ann = rule.ann, whisper = rule.whisper,
	}
end

-- player — кто, rule — правило свода, detail — что увидела автоматика
function ns.AddFinding(player, rule, detail)
	local s = ns.Session()
	if not s then return end
	if not ns.RuleDiffOk(rule) or not ns.RuleRoleOk(rule, player) then return end
	local boss = ns.IsBoss(rule.boss) and rule.boss or s.boss
	local pull = boss and s.pulls[boss]
	if ns.RuleBlock(rule, player, boss, pull) then return end
	local f = {player = player, rule = CopyRule(rule), detail = detail, boss = boss, pull = pull, t = time()}
	if rule.instant then
		ns.AddEvents({player}, f.rule, f)
		return
	end
	s.queue = s.queue or {}
	s.nextFinding = (s.nextFinding or 0) + 1
	f.id = s.nextFinding
	tinsert(s.queue, f)
	ns.Print(format("на проверку: %s — %s (%s).", player, ns.ShortText(f.rule.text), ns.ValueText(rule.value)))
	ns.Refresh()
end

function ns.QueueList()
	local s = ns.Session()
	return s and s.queue or {}
end

local function DropFinding(f)
	local s = ns.Session()
	if not s or not s.queue then return end
	for i, x in ipairs(s.queue) do
		if x == f then tremove(s.queue, i) break end
	end
end

function ns.AcceptFinding(f)
	if not f then return end
	DropFinding(f)
	ns.AddEvents({f.player}, f.rule, f)
end

function ns.RejectFinding(f)
	if not f then return end
	DropFinding(f)
	local s = ns.Session()
	s.rejected = (s.rejected or 0) + 1
	ns.Refresh()
end

function ns.AcceptAllFindings()
	local list = ns.QueueList()
	while list[1] do ns.AcceptFinding(list[1]) end
end

function ns.RejectAllFindings()
	local list = ns.QueueList()
	while list[1] do ns.RejectFinding(list[1]) end
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

-- сумма, пометка «на кик», число записей
function ns.PlayerState(name)
	local s = ns.Session()
	local total, kick, n = 0, false, 0
	if not s then return total, kick, n end
	for _, ev in ipairs(s.events) do
		if ev.player == name and ev.status ~= "cancelled" then
			total = total + (ev.value or 0)
			n = n + 1
			if ev.kick then kick = true end
		end
	end
	return total, kick, n
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

-- допуск к роллу: ok, причина, модификатор (не побеждает только тот, кто на кике)
function ns.CanRoll(name)
	local total, kick = ns.PlayerState(name)
	if kick then return false, "на кик", total end
	return true, nil, total
end

-- текст правила без пояснения в скобках в конце: «Дух (оспаривается с видео)» -> «Дух»
function ns.ShortText(text)
	local short = tostring(text or ""):gsub("%s*%b()%s*$", "")
	if short == "" then return tostring(text or "") end
	return short
end

-- «-30», «кик», «-30, кик»
function ns.EffectText(ev)
	local parts = {}
	if ev.value ~= 0 then tinsert(parts, ns.ValueText(ev.value)) end
	if ev.kick then tinsert(parts, "кик") end
	return #parts > 0 and tconcat(parts, ", ") or "0"
end

-- текст записи для чата
function ns.EventChat(ev) return ev.chat or ns.ShortText(ev.text) end

-- «Вася -30 (Дух)»; withName = false — «Дух -30»
function ns.EventShort(ev, withName)
	if withName == false then return ns.EventChat(ev) .. " " .. ns.EffectText(ev) end
	return format("%s %s (%s)", ev.player, ns.EffectText(ev), ns.EventChat(ev))
end

-- «-40» или «-40, кик»
function ns.StateText(name, colored)
	local total, kick = ns.PlayerState(name)
	local parts = {colored and ns.ValueColor(total) or ns.ValueText(total)}
	if kick then tinsert(parts, colored and "|cffff2020кик|r" or "кик") end
	return tconcat(parts, ", ")
end
