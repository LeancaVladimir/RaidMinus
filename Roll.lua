-- Розыгрыш: приём /roll, итог = ролл + сумма минусов и плюсов игрока.
-- Засчитывается первый бросок 1-rollMax; повторные подсвечиваются; бросок не того диапазона
-- в таблице, но не побеждает. Ничья на первом месте — переролл только для них.
-- Наблюдение: ролл объявил другой (LootList.lua) — аддон молча считает броски с минусами,
-- в чат пишет только по кнопке «Закончить розыгрыш».
-- Текущий ролл живёт в памяти (ns.roll); итог пишется в запись добычи (loot.result).

local _, ns = ...

local format, tinsert, tconcat = string.format, table.insert, table.concat
local ipairs, pairs, min, max = ipairs, pairs, math.min, math.max

local WATCH_TIME = 60   -- наблюдение закрывается само, если столько секунд никто не бросает
local WATCH_EXTEND = 20

ns.roll = nil

local ROLL_PATTERN = ns.ToPattern(RANDOM_ROLL_RESULT)

local function Settings() return ns.DB.settings end

local function Tick()
	local r = ns.roll
	if not r or r.state ~= "open" then return end
	local left = r.ends - GetTime()
	if left <= 0 then
		ns.FinishRoll()
		return
	end
	if not r.watch and Settings().rollCountdown and not r.warned and r.duration > 15 and left <= 10.5 then
		r.warned = true
		ns.Announce("Ролл " .. r.link .. ": осталось 10 сек")
	end
	if ns.RefreshRoll then ns.RefreshRoll() end
	r.timer = ns.After(min(1, left), Tick)
end

-- only — список имён для переролла ничьей; watchBy — ролл объявил этот игрок, только наблюдаем;
-- off — ролл на офф-спек (второй ролл, если на основной спек никто не взял)
function ns.StartRoll(e, only, watchBy, off)
	if e then ns.FreshLink(e) end
	if not e then return end
	if not watchBy then
		if not ns.CanManageLoot() then
			ns.Print(ns.NO_LOOT_RIGHTS)
			return
		end
		local busy, busyLink = ns.RollBusyBy(e)
		if busy then
			ns.Print(format("%s сейчас разыгрывает %s — дождитесь итога.", busy, busyLink or e.link))
			return
		end
		local by = e.result and (e.result.remote or (e.remote and e.remote.done and e.remote.by))
		if by then
			ns.Print(format("%s уже разыграл %s — второй раз не разыгрываем.", by, e.link))
			return
		end
	end
	if ns.roll and ns.roll.state == "open" then
		if not ns.roll.watch then
			ns.Print("уже идёт ролл — сначала закончите его.")
			return
		end
		ns.CancelRoll(true)
	end
	local duration = watchBy and WATCH_TIME or (only and Settings().tieTime or Settings().rollTime)
	local r = {
		loot = e.id, link = e.link, cat = e.cat,
		state = "open", duration = duration, ends = GetTime() + duration,
		entries = {}, byName = {}, watch = watchBy, off = off or nil,
		round = only and ((ns.roll and ns.roll.round or 1) + 1) or 1,
	}
	if only then
		r.only = {}
		for _, name in ipairs(only) do r.only[name] = true end
	end
	ns.roll = r
	e.result = nil
	if not only then e.winner, e.rounds = nil, nil end
	if only then
		ns.Announce(format("{rt3} Ничья! Перекидывают %s: /roll, %d сек", tconcat(only, ", "), duration), true)
	elseif off then
		ns.Announce(format("Ролл на ОФФ-СПЕК %s (%s): /roll, %d сек", e.link, ns.CategoryName(e.cat), duration), true)
	elseif not watchBy then
		ns.Announce(format("Ролл %s (%s): /roll, %d сек", e.link, ns.CategoryName(e.cat), duration), true)
	end
	if not watchBy then
		e.remote = nil
		if ns.SyncRollStart then ns.SyncRollStart(r) end
	end
	Tick()
	ns.Refresh()
end

-- кто другой сейчас разыгрывает (виден ролл: объявление в чате или синхронизация); nil — никто.
-- Пока идёт чужой ролл, свой не начать: броски игроков засчитались бы в оба.
function ns.RollBusyBy(e)
	local r = ns.roll
	if r and r.state == "open" and r.watch then return r.watch, r.link end
	if e.remote and not e.remote.done and e.remote.t and time() - e.remote.t < 180 then return e.remote.by end
end

-- ролл объявил другой: не мешаем своему роллу, иначе начинаем наблюдение
function ns.WatchRoll(e, by)
	local r = ns.roll
	if r and r.state == "open" and not r.watch then return end
	ns.StartRoll(e, nil, by)
	ns.NotifyWatch(e, by)
end

-- чужой ролл пошёл: сказать РЛу и показать «Розыгрыш» с этим предметом (иначе подсчёт идёт незаметно)
function ns.NotifyWatch(e, by)
	local r = ns.roll
	if not r or r.state ~= "open" or r.loot ~= e.id then return end
	ns.Print(format("идёт ролл %s (объявил %s) — считаю броски с минусами. Итог в чат — «Закончить розыгрыш».", e.link, tostring(by)))
	if Settings().rollPopup and not InCombatLockdown() and ns.ShowTab then
		ns.ui.loot = e.id
		ns.ShowTab("loot")
	end
end

function ns.OnRoll(name, roll, low, high)
	local r = ns.roll
	if not r or r.state ~= "open" then return end
	if r.only and not r.only[name] then return end
	if not ns.IsHere(name) then return end
	local bad
	if low ~= 1 or high ~= Settings().rollMax then bad = format("%d-%d", low, high) end
	local e = r.byName[name]
	if e then
		if e.bad and not bad then
			-- сначала кинул не тот диапазон, теперь правильный — засчитываем правильный
			e.roll, e.low, e.high, e.bad = roll, low, high, nil
		else
			e.extra = (e.extra or 0) + 1
		end
	else
		e = {name = name, roll = roll, low = low, high = high, bad = bad}
		r.byName[name] = e
		tinsert(r.entries, e)
	end
	if r.watch then r.ends = max(r.ends, GetTime() + WATCH_EXTEND) end
	if ns.RefreshRoll then ns.RefreshRoll() end
end

local LINKED_WAIT = 30 -- сек: ссылку без слов считаем роллом, если броски пошли в это время

ns.On("CHAT_MSG_SYSTEM", function(msg)
	local open = ns.roll and ns.roll.state == "open"
	if not open and not ns.lastLinked then return end
	local name, roll, low, high
	if ROLL_PATTERN then name, roll, low, high = msg:match(ROLL_PATTERN) end
	if not name then
		-- запасной разбор: «Имя ... 57 (1-100)»
		name, roll, low, high = msg:match("^(%S+) .-(%d+) %((%d+)%-(%d+)%)")
	end
	if not name then return end
	if not open then
		-- РЛ или лутер кинул ссылку без слов, и пошли броски — значит, это ролл: начинаю считать
		local l = ns.lastLinked
		if GetTime() - l.t > LINKED_WAIT then
			ns.lastLinked = nil
			return
		end
		if not ns.Session() or not ns.IsHere(name) then return end
		ns.lastLinked = nil
		local e = ns.AddLoot(l.link, "announce", l.sender)
		ns.LootLog("announce", l.sender, l.link .. " — пошли броски, считаю")
		if e then ns.WatchRoll(e, l.sender) end
		if not (ns.roll and ns.roll.state == "open") then return end
	end
	ns.OnRoll(name, tonumber(roll), tonumber(low), tonumber(high))
end)

-- считает модификатор, итог и допуск; сортирует: допущенные выше, по итогу
function ns.ComputeRoll(r)
	for _, e in ipairs(r.entries) do
		local mod = ns.PlayerState(e.name)
		e.mod = mod
		e.final = e.roll + mod
		e.ok = not e.bad
		e.reason = e.bad and ("ролл " .. e.bad) or nil
	end
	table.sort(r.entries, function(a, b)
		if a.ok ~= b.ok then return a.ok end
		if a.final ~= b.final then return a.final > b.final end
		return a.name < b.name
	end)
end

-- «57 -20 = 37» или «57»
function ns.RollText(e)
	if not e.mod or e.mod == 0 then return tostring(e.roll) end
	return format("%d %s = %d", e.roll, ns.ValueText(e.mod), e.final)
end

local function CopyEntries(list)
	local out = {}
	for _, e in ipairs(list) do
		tinsert(out, {name = e.name, roll = e.roll, mod = e.mod, final = e.final, ok = e.ok, reason = e.reason, extra = e.extra})
	end
	return out
end

-- кому достаётся предмет: выбранный РЛом (получил другой) или победитель
function ns.LootOwner(e)
	return e and (e.receiver or e.winner)
end

-- объявить итог в обычный чат рейда одной строкой: «[предмет] — Имя» (после своего ролла — сразу,
-- после наблюдения — по кнопке). Таблица бросков в чат не идёт: она видна в окне.
function ns.AnnounceResult(e)
	local res = e and e.result
	if not res then return end
	if not ns.CanManageLoot() then
		ns.Print(ns.NO_LOOT_RIGHTS)
		return
	end
	res.announced = true
	local owner = ns.LootOwner(e)
	if owner then
		ns.Announce(format("%s — %s%s", e.link, owner, res.off and " (офф-спек)" or ""))
	elseif res.tie then
		ns.Announce(format("%s — ничья: %s", e.link, tconcat(res.tie, ", ")))
	else
		ns.Announce(format("%s — никто", e.link))
	end
	ns.Refresh()
end

-- announce: писать ли в чат (по умолчанию — да для своего ролла, нет для наблюдения)
function ns.FinishRoll(announce)
	local r = ns.roll
	if not r or r.state ~= "open" then return end
	if announce == nil then announce = not r.watch end
	if announce and r.watch and not ns.CanManageLoot() then
		ns.Print(ns.NO_LOOT_RIGHTS)
		announce = false
	end
	ns.Cancel(r.timer)
	r.state = "done"
	ns.ComputeRoll(r)
	local e = ns.LootById(r.loot)
	if not e then
		ns.Refresh()
		return
	end

	local best = r.entries[1]
	local tied = {}
	if best and best.ok then
		for _, x in ipairs(r.entries) do
			if x.ok and x.final == best.final then tinsert(tied, x.name) end
		end
	end

	if #tied > 1 then
		if announce then
			-- ничья: объявление переролла («Ничья! Перекидывают …») делает StartRoll
			e.rounds = e.rounds or {}
			tinsert(e.rounds, CopyEntries(r.entries))
			ns.StartRoll(e, tied, nil, r.off)
		else
			e.result = {entries = CopyEntries(r.entries), tie = tied, watched = r.watch, off = r.off, t = time()}
			ns.Refresh()
		end
		return
	end

	if best and best.ok then
		e.winner = best.name
		e.result = {winner = best.name, roll = best.roll, mod = best.mod, final = best.final,
			entries = CopyEntries(r.entries), watched = r.watch, off = r.off, t = time()}
	else
		e.winner = nil
		e.result = {entries = CopyEntries(r.entries), none = true, watched = r.watch, off = r.off, t = time()}
	end
	if announce then ns.AnnounceResult(e) end
	if not r.watch and ns.SyncRollEnd then ns.SyncRollEnd(e) end
	ns.Refresh()
end

-- silent — без объявления (завершение рейда, смена наблюдения)
function ns.CancelRoll(silent)
	local r = ns.roll
	if not r then return end
	ns.Cancel(r.timer)
	if r.state == "open" and not silent and not r.watch then ns.Announce("Ролл " .. r.link .. " отменён") end
	if r.state == "open" and not r.watch and ns.SyncRollCancel then ns.SyncRollCancel(r.link) end
	ns.roll = nil
	ns.Refresh()
end

-- тестовый рейд: выдуманные игроки бросают за несколько секунд
function ns.TestRolls()
	local s = ns.Session()
	local r = ns.roll
	if not s or not s.test then
		ns.Print("тест-броски работают только в тестовом рейде: /rm тест.")
		return
	end
	if not r or r.state ~= "open" then
		ns.Print("сначала начните ролл (вкладка «Розыгрыш»).")
		return
	end
	local window = min(6, r.ends - GetTime() - 1)
	local n = 0
	for name in pairs(s.roster) do
		if name ~= ns.PlayerName() and (not r.only or r.only[name]) and (r.only or math.random() < 0.6) then
			n = n + 1
			local high = (n == 3 and not r.only) and 50 or Settings().rollMax -- один бросит не тот диапазон
			ns.After(math.random() * window, function()
				ns.OnRoll(name, math.random(1, high), 1, high)
			end)
		end
	end
	ns.Print(format("бросают %d игроков.", n))
end
