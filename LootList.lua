-- Добыча рейда: список розыгрыша (s.loot). РЛ делает с предметом одно из двух:
--   в сумку — «Холпал получает добычу: [предмет]» (взял РЛ, помощник или ответственный за добычу;
--     эпик, не мусор) → запись «в сумке у Холпала», 2 часа на передачу (точнее — по сумке, TradeTime.lua);
--   ролл сразу — ссылка в объявлении рейду (/ов) от РЛа, помощника или ответственного → ролл с подсчётом
--     минусов (Roll.lua) и окно «Розыгрыш» с этим предметом.
-- Без дублей: объявление берёт запись того же предмета, которая ещё не разыграна (лежит в сумке), затем
-- разыгранную без победителя (переролл, офф-спек); новая — только если таких нет.
-- Вручную: shift+клик по предмету в поле вкладки «Розыгрыш», перетащить предмет, /rm лут [предмет].
-- Запись: {id, link, item, cat, t, src, boss, holder, expires, exact, result, winner, receiver}.

local _, ns = ...

local format, tinsert, tremove = string.format, table.insert, table.remove
local ipairs, pairs, tonumber = ipairs, pairs, tonumber

local LINK = "|c%x+|Hitem:.-|h.-|h|r"
local QUALITY_BY_COLOR = {ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5}
local COLOR_BY_QUALITY = {[2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ff8000"}
local KILL_LINK = 900    -- сек: предмет не из таблиц ЦЛК — к последнему убитому боссу, если он убит недавно
local JUST_ROLLED = 900  -- сек: разыгранный предмет ушёл в сумку ответственного — он отдаст его позже
local TRADE_TIME = 7200  -- 2 часа: столько предмет из рейда можно передать тем, кто был в рейде
local LOG_LIMIT = 80

-- слова в объявлении (без текста ссылок): начало ролла и объявление победителя
local ROLL_WORDS = {"ролл", "ролим", "роллим", "рол ", "кидаем", "кидайте", "roll"}
local WIN_WORDS = {"выиграл", "победил", "побеждает", "забирает", "won", "wins", "winner"}

-- откуда запись (старые рейды — тело, RaidRoll, чат, список — тоже показываются)
ns.SOURCES = {bag = "в сумку", announce = "объявлен ролл", manual = "вручную", sync = "RaidMinus",
	corpse = "тело", rrl = "RaidRoll", chat = "чат лута", list = "список", drop = "добыча босса"}
local SOURCE_ORDER = {"bag", "announce", "sync", "manual", "corpse", "rrl", "chat", "list", "drop"}

local function Settings() return ns.DB.settings end

-- журнал добычи: откуда что пришло и что пропущено (/rm лог) — чтобы разобраться, почему предмет не записался
function ns.LootLog(src, who, text)
	local s = ns.Session()
	if not s then return end
	s.lootLog = s.lootLog or {}
	tinsert(s.lootLog, {t = time(), src = src, who = who, text = text})
	while #s.lootLog > LOG_LIMIT do tremove(s.lootLog, 1) end
end

function ns.PrintLootLog()
	local s = ns.Session()
	local log = s and s.lootLog
	if not log or #log == 0 then
		ns.Print("журнал добычи пуст.")
		return
	end
	ns.Print(format("журнал добычи (последние %d):", math.min(#log, 30)))
	for i = math.max(1, #log - 29), #log do
		local x = log[i]
		DEFAULT_CHAT_FRAME:AddMessage(format("  |cff9d9d9d%s|r %s%s: %s", date("%H:%M", x.t), ns.SOURCES[x.src] or x.src,
			x.who and (" (" .. x.who .. ")") or "", x.text))
	end
end

-- шаблон Lua из строки формата клиента: «%s выбрасывает %d (%d-%d)»
function ns.ToPattern(fmt)
	if not fmt then return end
	local p = fmt:gsub("%%%d%$s", "\001"):gsub("%%%d%$d", "\002"):gsub("%%s", "\001"):gsub("%%d", "\002")
	p = p:gsub("([%(%)%.%-%+%*%?%[%]%^%$%%])", "%%%1")
	p = p:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
	return "^" .. p .. "$"
end

function ns.LinkQuality(link)
	local q = select(3, GetItemInfo(link))
	if q then return q end
	local color = tostring(link):match("^|c(%x+)|")
	return color and QUALITY_BY_COLOR[color:lower()]
end

-- ссылка на предмет по номеру: от клиента, иначе собранная из имени (клиент подгрузит предмет сам)
local scanTip
function ns.ItemLink(id, name, quality)
	local _, link = GetItemInfo(id)
	if link then return link end
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "RaidMinusScanTip", UIParent, "GameTooltipTemplate")
		scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	end
	-- просим сервер прислать данные предмета (только известные предметы ЦЛК: чужой номер может быть любым)
	if ns.LootBoss(id) or ns.IsToken(id) then scanTip:SetHyperlink("item:" .. id) end
	return format("|c%s|Hitem:%d:0:0:0:0:0:0:0:80|h[%s]|h|r", COLOR_BY_QUALITY[quality or 4] or "ffa335ee", id, name or ("Предмет " .. id))
end

-- свежая ссылка (собранная из имени могла быть временной)
function ns.FreshLink(e)
	local _, link = GetItemInfo(e.item or e.link)
	if link then e.link = link end
	return e.link
end

-------------------------------------------------------------------------------
-- список розыгрыша

function ns.LootById(id)
	local s = ns.Session()
	if not s or not id then return end
	for _, e in ipairs(s.loot) do
		if e.id == id then return e end
	end
end

local function Src(e)
	if not e.src then e.src = {manual = true} end
	return e.src
end

-- «в сумку: Холпал, объявлен ролл: Вася»
function ns.SourceText(src)
	local parts = {}
	for _, key in ipairs(SOURCE_ORDER) do
		local v = src and src[key]
		if v then
			if type(v) == "string" then
				tinsert(parts, (key == "announce" and "ролл объявил " or (ns.SOURCES[key] .. ": ")) .. v)
			else
				tinsert(parts, ns.SOURCES[key])
			end
		end
	end
	return table.concat(parts, ", ")
end

function ns.LootSourceText(e) return ns.SourceText(Src(e)) end

-- босс предмета: по таблице ЦЛК, иначе последний убитый (если недавно), иначе текущий
local function BossOf(id)
	local s = ns.Session()
	local b = ns.LootBoss(id)
	if b then return b end
	local k = s and s.lastKill
	if k and time() - k.t < KILL_LINK then return k.boss end
	return s and s.boss
end

local function NewEntry(link, src, by)
	local s = ns.Session()
	s.nextLoot = (s.nextLoot or 0) + 1
	local id = ns.ItemId(link)
	local e = {id = s.nextLoot, link = link, item = id, cat = ns.ItemCategory(link), t = time(),
		src = {[src] = by or true}, boss = BossOf(id)}
	tinsert(s.loot, e)
	if ns.OnLootAdded then ns.OnLootAdded(e) end
	return e
end

-- запись для объявленного ролла: ещё не разыгранная (лежит в сумке), затем разыгранная без победителя
-- (переролл, офф-спек). Тот, что сейчас разыгрывается, не трогаем.
local function EntryForRoll(id)
	local s = ns.Session()
	local rolled
	for _, e in ipairs(s.loot) do
		local busy = ns.roll and ns.roll.loot == e.id and ns.roll.state == "open"
		if e.item == id and not busy and not e.receiver then
			if not e.result then return e end
			if not rolled and not e.winner then rolled = e end
		end
	end
	return rolled
end

-- src — откуда (manual, announce, sync), by — кто объявил. Возвращает запись и true, если она новая.
function ns.AddLoot(link, src, by)
	local s = ns.Session()
	if not s then
		ns.Print("сначала начните рейд: /rm старт.")
		return
	end
	src = src or "manual"
	if src == "announce" or src == "sync" then
		local e = EntryForRoll(ns.ItemId(link))
		if e then
			Src(e).announce = by or true
			ns.Refresh()
			return e, false
		end
		src = "announce"
	end
	local e = NewEntry(link, src, by)
	ns.Refresh()
	return e, true
end

function ns.RemoveLoot(e)
	local s = ns.Session()
	if not s or not e then return end
	if ns.roll and ns.roll.loot == e.id then ns.CancelRoll() end
	for i, x in ipairs(s.loot) do
		if x == e then tremove(s.loot, i) break end
	end
	ns.Refresh()
end

-- из текста со ссылкой: /rm ролл [предмет]
function ns.AddLootFromText(text, start)
	local link = tostring(text or ""):match(LINK)
	if not link then
		ns.Print("нужна ссылка на предмет: /rm ролл и shift+клик по предмету.")
		return
	end
	local e = ns.AddLoot(link, "manual")
	if e and start then ns.StartRoll(e) end
	return e
end

-- записи розыгрыша с этим предметом
function ns.LootByItem(id)
	local s = ns.Session()
	local out = {}
	for _, e in ipairs(s and s.loot or {}) do
		if e.item == id then tinsert(out, e) end
	end
	return out
end

-- неразыгранных записей (счётчик на мини-панели)
function ns.UnrolledCount()
	local s = ns.Session()
	local n = 0
	for _, e in ipairs(s and s.loot or {}) do
		if not e.result and not e.receiver then n = n + 1 end
	end
	return n
end

-- кто фактически получил предмет (выиграл один, а забрал другой — ролл за друга, случайный бросок).
-- how — откуда известно: «вручную», «чат лута», «обмен»; name = nil — сбросить
function ns.SetReceiver(e, name, how, note)
	if not e then return end
	e.receiver = name
	e.receiverBy = name and how or nil
	e.receiverNote = name and note or nil
	if name and e.winner and e.winner ~= name then
		ns.Print(format("%s: выиграл %s, получил %s (%s).", e.link, e.winner, name, how or "?"))
	end
	if how == "вручную" and ns.SyncAward then ns.SyncAward(e) end
	ns.Refresh()
end

-- предмет попал к игроку (чат лута, обмен). Уже разыгран — он «получил» (запись, где он победитель,
-- иначе любая разыгранная). Ещё не разыгран — он только держит предмет до ролла.
function ns.AutoReceiver(id, name, how)
	local best, rolled, unrolled
	for _, e in ipairs(ns.LootByItem(id)) do
		if not e.receiver then
			if e.result and e.winner == name and not best then best = e end
			if e.result and not rolled then rolled = e end
			if not e.result and not unrolled then unrolled = e end
		end
	end
	local e = best or rolled
	if e then
		ns.SetReceiver(e, name, how)
		return e
	end
	if unrolled then
		unrolled.holder = name
		ns.Refresh()
	end
	return unrolled
end

-- время на передачу: точное (из сумки, от ответственного, по строке «получает добычу») или оценка
function ns.TradeExpires(e)
	if e.expires then return e.expires, e.exact end
	return (e.t or time()) + TRADE_TIME, false
end

-------------------------------------------------------------------------------
-- в сумку: строки «Холпал получает добычу: [предмет]» и «Вы получаете добычу: [предмет]»

local function InBag(e, who)
	e.holder = who
	if not e.exact then e.expires, e.exact = time() + TRADE_TIME, true end
end

-- взял РЛ, помощник или ответственный: его выигрыш → «получил»; только что разыгранное → держит, отдаст;
-- иначе новая запись «в сумке» (её потом разыгрывают объявлением). Взял обычный игрок → «получил».
local function Looted(who, link)
	local id = ns.ItemId(link)
	if not id then return end
	if ns.IsJunk(id) then
		ns.LootLog("bag", who, link .. " — мусор, не разыгрывается")
		return
	end
	if not ns.officers[who] then
		local e = ns.AutoReceiver(id, who, "чат лута")
		ns.LootLog("chat", who, link .. (e and " — получил" or " — нет в списке"))
		return
	end
	local entries = ns.LootByItem(id)
	for _, e in ipairs(entries) do
		if e.result and e.winner == who and not e.receiver then
			ns.SetReceiver(e, who, "чат лута")
			ns.LootLog("chat", who, link .. " — получил свой выигрыш")
			return
		end
	end
	for _, e in ipairs(entries) do
		if e.result and e.winner and not e.receiver and not e.holder and time() - (e.result.t or 0) < JUST_ROLLED then
			InBag(e, who)
			ns.LootLog("bag", who, link .. " — разыгран, у него в сумке до передачи " .. e.winner)
			ns.Refresh()
			return
		end
	end
	local e = NewEntry(link, "bag", who)
	InBag(e, who)
	ns.LootLog("bag", who, link .. " — в сумку, в списке розыгрыша")
	ns.Refresh()
end

local lootPatterns
local function LootPatterns()
	if not lootPatterns then
		lootPatterns = {}
		local function add(fmt, self, multi)
			local p = ns.ToPattern(fmt)
			if p then tinsert(lootPatterns, {p, self, multi}) end
		end
		add(LOOT_ITEM_SELF_MULTIPLE, true, true)
		add(LOOT_ITEM_SELF, true, false)
		add(LOOT_ITEM_MULTIPLE, false, true)
		add(LOOT_ITEM, false, false)
	end
	return lootPatterns
end

function ns.OnLootMessage(msg)
	if not ns.Session() then return end
	for _, p in ipairs(LootPatterns()) do
		local a, b, c = msg:match(p[1])
		if a then
			local who, link, count
			if p[2] then
				who, link, count = ns.PlayerName(), a, b
			else
				who, link, count = a, b, c
			end
			link = tostring(link):match(LINK)
			if link and (ns.LinkQuality(link) or 0) >= 4 then
				for _ = 1, math.min(tonumber(count) or 1, 5) do Looted(who, link) end
			end
			return
		end
	end
end

ns.On("CHAT_MSG_LOOT", function(msg) ns.OnLootMessage(msg) end)

-------------------------------------------------------------------------------
-- объявления: ролл предмета, победитель

local function HasWord(text, words)
	for _, w in ipairs(words) do
		if text:find(w, 1, true) then return true end
	end
end

-- Сообщение в рейд или группу (тестовый рейд вызывает напрямую — «ответственный объявил ролл»).
-- Как обычно разыгрывают: РЛ, помощник или ответственный кидает ссылку на предмет в объявление рейду
-- (/ов) — без слов — и игроки бросают /roll. Поэтому:
--   одна ссылка в объявлении рейду — ролл (слово «ролл» не нужно);
--   одна ссылка в обычном чате рейда со словом «ролл»/«кидаем» — тоже ролл;
--   одна ссылка без слов в обычном чате — ролл, если в следующие 30 сек пошли броски (Roll.lua);
--   несколько ссылок — не ролл (пропускаем).
-- Свои сообщения РЛа тоже считаются (он мог кинуть ссылку руками), кроме того, что написал сам аддон.
function ns.OnGroupMessage(msg, sender, event)
	local me = sender == ns.PlayerName()
	if me and (ns.SentByAddon(msg) or msg:find("{rt", 1, true)) then return end -- это написал аддон
	-- ссылки: эпики — ролл сразу; синие и зелёные — ролл, только если пошли броски
	local links, epic = {}, 0
	for link in msg:gmatch(LINK) do
		local q = ns.LinkQuality(link) or 0
		if q >= 2 then
			tinsert(links, link)
			if q >= 4 then epic = epic + 1 end
		end
	end
	if #links == 0 then return end
	local warning = event == "CHAT_MSG_RAID_WARNING" -- объявление рейду пишут только РЛ и помощники
	if not ns.Session() then
		-- рейд не начат, а в объявлении рейду разыгрывают — начать самим, иначе ролл пропадёт
		if not (Settings().autoSession and warning and #links == 1 and GetNumRaidMembers() > 0) then return end
		ns.StartSession()
		ns.Print("рейд начат сам: в объявлении рейду разыгрывают " .. links[1] .. ". Закончить — «Завершить рейд».")
	end
	if not me and not ns.officers[sender] and not warning then return end
	local text = ns.Lower((msg:gsub(LINK, " ")))

	if HasWord(text, WIN_WORDS) then
		-- объявили победителя: наблюдение за этим предметом закончено (без объявления от меня)
		local r = ns.roll
		if r and r.watch and r.state == "open" then
			for _, link in ipairs(links) do
				if ns.ItemId(link) == ns.ItemId(r.link) then
					ns.FinishRoll(false)
					break
				end
			end
		end
		return
	end

	if #links > 1 then
		ns.LootLog("list", sender, format("%d ссылок в одном сообщении — не ролл, пропущено", #links))
		return
	end
	local link = links[1]
	local r = ns.roll
	if r and r.state == "open" and ns.ItemId(r.link) == ns.ItemId(link) then return end -- уже считаю
	if epic == 1 and (warning or HasWord(text, ROLL_WORDS)) then
		if not Settings().watchOthers then return end
		ns.lastLinked = nil
		local e = ns.AddLoot(link, "announce", sender)
		ns.LootLog("announce", sender, link .. " — ролл, считаю броски")
		if e then ns.WatchRoll(e, sender) end
	else
		-- ссылка без слов: ролл ли это, станет ясно по броскам
		ns.lastLinked = {link = link, sender = sender, t = GetTime()}
		ns.LootLog("announce", sender, link .. " — без слова «ролл»: начну считать, если пойдут броски")
	end
end

for _, event in ipairs({"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER"}) do
	ns.On(event, function(msg, sender) ns.OnGroupMessage(msg, sender, event) end)
end
