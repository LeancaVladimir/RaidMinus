-- Добыча рейда: что упало с каждого босса (страницы s.drops) и список для розыгрыша (s.loot).
--
-- Откуда аддон узнаёт, что упало (тело может открыть кто угодно, не только РЛ):
--   corpse — я открыл тело или сундук (LOOT_OPENED);
--   rrl    — тело открыл другой игрок с аддоном RaidRoll: он рассылает добычу в рейд по скрытому
--            каналу RRL («Beta_2\aЛутер\aМоб\aID\aИмя\aiLvl»);
--   chat   — строки «Вася получает добычу: [предмет]» и «Ваша добыча: [предмет]»;
--   list   — лидер, ассистент или ответственный за добычу скинул в рейд список ссылок.
-- Один предмет из разных источников не дублируется: на странице босса для каждого предмета
-- берётся наибольшее число, которое назвал один источник (tallies).
--
-- Фильтр (Data\Loot.lua): гер. снаряжение ЦЛК 25, жетоны, маунт; осколки и саронит скрыты.
-- Что прошло фильтр, сразу попадает в розыгрыш (настройка lootAuto). Убранное из розыгрыша
-- остаётся на странице с пометкой «не включено» — окно «Добыча» показывает это знаком ⚠.
--
-- Список розыгрыша (s.loot): записи {id, link, item, cat, t, src, boss, drop, result, winner}.
-- Кроме добычи с боссов, туда попадает предмет, ролл которого объявил ответственный (announce),
-- и добавленный вручную (manual: shift+клик, перетаскивание, /rm лут).

local _, ns = ...

local format, tinsert, tremove = string.format, table.insert, table.remove
local ipairs, pairs, tonumber, max = ipairs, pairs, tonumber, math.max

local LINK = "|c%x+|Hitem:.-|h.-|h|r"
local QUALITY_BY_COLOR = {ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5}
local COLOR_BY_QUALITY = {[2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ff8000"}
local PAGE_GAP = 600  -- сек: добыча без босса в пределах этого времени — на ту же страницу
local KILL_LINK = 900 -- сек: добыча без явного босса — к последнему убитому, если он убит недавно
local RRL_QUIET = 1.5 -- сек тишины от одного лутера RaidRoll — его список закончен

-- слова в объявлении (без текста ссылок): начало ролла и объявление победителя
local ROLL_WORDS = {"ролл", "ролим", "роллим", "рол ", "кидаем", "кидайте", "roll"}
local WIN_WORDS = {"выиграл", "победил", "побеждает", "забирает", "won", "wins", "winner"}

ns.SOURCES = {corpse = "тело", rrl = "RaidRoll", chat = "чат лута", list = "список", announce = "объявлен ролл", manual = "вручную", drop = "добыча босса", sync = "RaidMinus"}

local function Settings() return ns.DB.settings end

local TRADE_TIME = 7200 -- 2 часа: столько предмет из рейда можно передать тем, кто был в рейде
local LOG_LIMIT = 80

-- журнал добычи: откуда что пришло и что отброшено (/rm лог) — чтобы разобраться, почему предмет не записался
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

-- «RaidRoll (Холпал), чат лута»
function ns.SourceText(src)
	local parts = {}
	for _, key in ipairs({"corpse", "sync", "rrl", "chat", "list", "drop", "announce", "manual"}) do
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

function ns.LootSourceText(e)
	local page = e.drop and ns.DropById(e.drop)
	if page then return (page.boss and ns.ShortName(page.boss) or page.title) .. ": " .. ns.SourceText(page.src) end
	return ns.SourceText(Src(e))
end

-- src — откуда (manual, announce, drop), by — кто объявил; page/item — страница добычи и предмет на ней.
-- Возвращает запись и true, если она новая.
function ns.AddLoot(link, src, by, page, item)
	local s = ns.Session()
	if not s then
		ns.Print("сначала начните рейд: /rm старт.")
		return
	end
	src = src or "manual"
	local id = ns.ItemId(link)
	if src == "announce" then
		-- объявили ролл предмета, который уже в списке: та же запись
		for _, e in ipairs(s.loot) do
			local busy = ns.roll and ns.roll.loot == e.id and ns.roll.state == "open"
			if e.item == id and not e.result and not busy and not Src(e).announce then
				Src(e).announce = by or true
				ns.Refresh()
				return e, false
			end
		end
	end
	s.nextLoot = (s.nextLoot or 0) + 1
	local e = {
		id = s.nextLoot, link = link, item = id, cat = ns.ItemCategory(link), t = time(),
		src = {[src] = by or true}, boss = page and page.boss or s.boss, drop = page and page.id,
	}
	tinsert(s.loot, e)
	if item then item.loot, item.removed = e.id, nil end
	if ns.OnLootAdded then ns.OnLootAdded(e) end
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
	local page = e.drop and ns.DropById(e.drop)
	if page then
		for _, item in ipairs(page.items) do
			if item.loot == e.id then item.loot, item.removed = nil, true end
		end
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

-------------------------------------------------------------------------------
-- страницы добычи по боссам

function ns.Drops()
	local s = ns.Session()
	if not s then return {} end
	s.drops = s.drops or {}
	return s.drops
end

function ns.PageTitle(page)
	return page.boss and ns.Section(page.boss).name or page.title or "Добыча"
end

function ns.DropById(id)
	for _, page in ipairs(ns.Drops()) do
		if page.id == id then return page end
	end
end

-- нужен ли предмет розыгрышу, но его там нет
function ns.ItemMissing(item) return item.wanted and not (item.loot and ns.LootById(item.loot)) end

-- сколько на странице: всего важных, в розыгрыше, не включено, скрыто фильтром
function ns.DropCounts(page)
	local wanted, inRoll, missing, hidden = 0, 0, 0, 0
	for _, item in ipairs(page.items) do
		if item.wanted then
			wanted = wanted + 1
			if ns.ItemMissing(item) then missing = missing + 1 else inRoll = inRoll + 1 end
		else
			hidden = hidden + 1
		end
	end
	return wanted, inRoll, missing, hidden
end

function ns.MissingTotal()
	local n = 0
	for _, page in ipairs(ns.Drops()) do n = n + select(3, ns.DropCounts(page)) end
	return n
end

function ns.IncludeDropItem(page, item)
	if not page or not item or (item.loot and ns.LootById(item.loot)) then return end
	ns.AddLoot(item.link, "drop", nil, page, item)
end

function ns.ExcludeDropItem(page, item)
	local e = item and item.loot and ns.LootById(item.loot)
	if e then ns.RemoveLoot(e) end
end

function ns.IncludeAllMissing(page)
	for _, p in ipairs(page and {page} or ns.Drops()) do
		for _, item in ipairs(p.items) do
			if ns.ItemMissing(item) then ns.IncludeDropItem(p, item) end
		end
	end
end

local function NewPage(boss, title)
	local s = ns.Session()
	s.nextDrop = (s.nextDrop or 0) + 1
	local kill = s.lastKill and s.lastKill.boss == boss and s.lastKill.t or time()
	local page = {id = s.nextDrop, boss = boss, title = title, t = time(), kill = kill, src = {}, items = {}, tallies = {}}
	tinsert(ns.Drops(), page)
	return page
end

local function PageForBoss(boss)
	for _, page in ipairs(ns.Drops()) do
		if page.boss == boss then return page end
	end
	return NewPage(boss, ns.Section(boss).name)
end

-- босс по предметам отчёта (большинство уникальных предметов), иначе по имени тела, иначе последний убитый
local function BossFor(items, mob)
	local votes, best, bestN = {}, nil, 0
	for _, x in ipairs(items) do
		local b = ns.LootBoss(x.id)
		if b then
			votes[b] = (votes[b] or 0) + 1
			if votes[b] > bestN then best, bestN = b, votes[b] end
		end
	end
	if best then return best end
	if mob then
		local low = ns.Lower(mob)
		for _, sec in ipairs(ns.SECTIONS) do
			if not sec.general and ns.Lower(sec.name) == low then return sec.key end
		end
	end
	local s = ns.Session()
	local k = s and s.lastKill
	if k and time() - k.t < KILL_LINK then return k.boss end
end

-- страница для добычи без босса (треш): одна на тело в пределах PAGE_GAP
local function PageForMob(mob)
	local title = (mob and mob ~= "" and mob ~= "Unknown") and mob or "Прочая добыча"
	local drops = ns.Drops()
	local last = drops[#drops]
	if last and not last.boss and last.title == title and time() - last.t < PAGE_GAP then return last end
	return NewPage(nil, title)
end

-- добавить на страницу недостающие экземпляры предмета (столько, сколько назвал самый щедрый источник)
local function Sync(page, info, opened)
	local need = 0
	for _, tally in pairs(page.tallies) do need = max(need, tally[info.id] or 0) end
	local have = 0
	for _, item in ipairs(page.items) do
		if item.id == info.id then have = have + 1 end
	end
	for _ = have + 1, need do
		local wanted, why = ns.LootWanted(info.id, info.link, info.ilvl, info.quality)
		local item = {id = info.id, link = info.link, wanted = wanted or nil, why = why}
		tinsert(page.items, item)
		opened.added = true
		if wanted and Settings().lootAuto then ns.IncludeDropItem(page, item) end
	end
end

-- окно «Добыча» после новой добычи (по настройке)
local function Popup(page)
	local mode = Settings().lootPopup
	if mode == "off" or not ns.ShowLootWindow then return end
	local wanted, _, missing = ns.DropCounts(page)
	if wanted == 0 or (mode == "missing" and missing == 0) then return end -- только мусор (треш, саронит)
	ns.ShowLootWindow(page.id)
end

-- предметы, которых клиент не знал при получении (нет уровня), — проверить снова
function ns.RecheckDrops()
	for _, page in ipairs(ns.Drops()) do
		for _, item in ipairs(page.items) do
			if not item.wanted and item.why == "уровень неизвестен" then
				local wanted, why = ns.LootWanted(item.id, item.link)
				item.wanted, item.why = wanted or nil, why
				if wanted then
					local _, link = GetItemInfo(item.id)
					if link then item.link = link end
					if Settings().lootAuto then ns.IncludeDropItem(page, item) end
				end
			end
		end
	end
end

-- отчёт источника: kind — corpse/rrl/list/chat, by — кто (лутер, автор списка), mob — имя тела,
-- items — {{id, link, ilvl, quality}}. Для chat счёт копится (каждая строка — новый предмет),
-- для остальных отчёт — весь список целиком (повтор того же списка ничего не добавит).
function ns.ReportLoot(kind, by, mob, items)
	local s = ns.Session()
	if not s or #items == 0 then return end
	local boss = BossFor(items, mob)
	local page = boss and PageForBoss(boss) or PageForMob(mob)
	local key = kind .. ":" .. tostring(by or "")
	local counts = {}
	for _, x in ipairs(items) do counts[x.id] = (counts[x.id] or 0) + 1 end
	local tally = page.tallies[key] or {}
	page.tallies[key] = tally
	for id, n in pairs(counts) do tally[id] = max(tally[id] or 0, n) end
	page.src[kind] = by or true
	local opened = {}
	local seen = {}
	for _, x in ipairs(items) do
		if not seen[x.id] then
			seen[x.id] = true
			Sync(page, x, opened)
		end
	end
	local wanted, inRoll, _, hidden = ns.DropCounts(page)
	ns.LootLog(kind, by, format("%s: %d предм. → «%s»%s, важных %d, в розыгрыше %d, скрыто %d", tostring(mob or "?"),
		#items, ns.PageTitle(page), opened.added and "" or " (без новых)", wanted, inRoll, hidden))
	if opened.added then
		page.t = time()
		Popup(page)
	end
	ns.Refresh()
	return page
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
-- иначе любая разыгранная). Ещё не разыгран — он только держит предмет до ролла (взял из тела, передали).
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

-- время на передачу: точное (из сумки, от лутера) или оценка от времени убийства
function ns.TradeExpires(e)
	if e.expires then return e.expires, e.exact end
	local page = e.drop and ns.DropById(e.drop)
	if page then
		for _, item in ipairs(page.items) do
			if item.loot == e.id and item.expires then return item.expires, item.exact end
		end
		return (page.kill or page.t) + TRADE_TIME, false
	end
	return (e.t or time()) + TRADE_TIME, false
end

-- кто взял предмет из тела: ответственный (держит у себя — пошли 2 часа на передачу) или игрок (получил)
local function MarkLooted(page, id, looter)
	local item
	for _, it in ipairs(page.items) do
		if it.id == id and not it.looted then item = it break end
	end
	if item then item.looted = looter end
	local holder = not looter or looter == ns.masterLooter
	if holder then
		if item and not item.exact then item.expires = time() + TRADE_TIME end
		local e = item and item.loot and ns.LootById(item.loot)
		if e then
			e.holder = looter
			if not e.exact then e.expires = item.expires end
		end
		return
	end
	ns.AutoReceiver(id, looter, "чат лута")
end

-- строка чата лута: один предмет. Сначала — страница, где этот предмет уже известен от другого
-- источника и ещё не подтверждён чатом; иначе — по таблице боссов или последнему убийству.
local function ChatLoot(looter, link, count)
	local id = ns.ItemId(link)
	if not id then return end
	local info = {id = id, link = link}
	local target
	local drops = ns.Drops()
	for i = #drops, 1, -1 do
		local page = drops[i]
		local key = "chat:"
		local chat = page.tallies[key] and page.tallies[key][id] or 0
		local other = 0
		for k, tally in pairs(page.tallies) do
			if k ~= key then other = max(other, tally[id] or 0) end
		end
		if other > chat then target = page break end
	end
	if not target then
		local boss = BossFor({info})
		target = boss and PageForBoss(boss) or PageForMob(nil)
	end
	local tally = target.tallies["chat:"] or {}
	target.tallies["chat:"] = tally
	tally[id] = (tally[id] or 0) + (count or 1)
	target.src.chat = looter or true
	local opened = {}
	Sync(target, info, opened)
	MarkLooted(target, id, looter)
	ns.LootLog("chat", looter, format("%s → «%s»%s", link, ns.PageTitle(target), opened.added and " (новый)" or ""))
	if opened.added then
		target.t = time()
		Popup(target)
	end
	ns.Refresh()
end

-- кто получил добычу: свои и чужие строки (LOOT_ITEM — «%s получает добычу: %s.»)
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
	if not ns.Session() or not Settings().srcChat then return end
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
			if link and (ns.LinkQuality(link) or 0) >= 4 then ChatLoot(who, link, tonumber(count) or 1) end
			return
		end
	end
end

ns.On("CHAT_MSG_LOOT", function(msg) ns.OnLootMessage(msg) end)

-- открыл тело или сундук сам
ns.On("LOOT_OPENED", function()
	if not ns.Session() or not Settings().srcCorpse then return end
	local items = {}
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		local _, _, _, quality = GetLootSlotInfo(slot)
		local id = link and ns.ItemId(link)
		if id and (quality or ns.LinkQuality(link) or 0) >= 4 then
			tinsert(items, {id = id, link = link, quality = quality})
		end
	end
	if #items == 0 then return end
	local mob = UnitExists("target") and UnitIsDead("target") and UnitName("target") or nil
	ns.ReportLoot("corpse", ns.PlayerName(), mob, items)
	-- другим РЛам и помощникам с RaidMinus: что лежит в теле (один раз на тело)
	if ns.SyncLoot then ns.SyncLoot(mob, items, UnitExists("target") and UnitGUID("target")) end
end)

-------------------------------------------------------------------------------
-- RaidRoll: добыча тела от другого игрока (скрытый канал RRL)

local rrlBuffer = {} -- лутер -> {mob, items, timer}

local function FlushRRL(sender)
	local b = rrlBuffer[sender]
	rrlBuffer[sender] = nil
	if b and ns.Session() then ns.ReportLoot("rrl", b.looter or sender, b.mob, b.items) end
end

function ns.OnRaidRollMessage(msg, channel, sender)
	if not ns.Session() or not Settings().srcRaidRoll then return end
	if channel ~= "RAID" and channel ~= "PARTY" then return end -- RaidRoll шлёт то же и в гильдию
	local parts = {strsplit("\a", msg or "")}
	local id, mob, looter, ilvl, quality, name, link
	if parts[1] == "Beta_2" then
		looter, mob, id, name, ilvl = parts[2], parts[3], tonumber(parts[4]), parts[5], tonumber(parts[6])
	elseif parts[1] == "Alpha" then
		looter, mob, link, quality, name, ilvl = parts[3], parts[4], parts[6], tonumber(parts[7]), parts[9], tonumber(parts[10])
		id = ns.ItemId(link)
		link = link and link:match(LINK)
	else
		return
	end
	if not id then return end
	link = link or ns.ItemLink(id, name, quality)
	local b = rrlBuffer[sender]
	if not b then
		b = {mob = mob, looter = looter, items = {}}
		rrlBuffer[sender] = b
	end
	tinsert(b.items, {id = id, link = link, ilvl = ilvl, quality = quality})
	ns.Cancel(b.timer)
	b.timer = ns.After(RRL_QUIET, function() FlushRRL(sender) end)
end

ns.On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
	if prefix == "RRL" then ns.OnRaidRollMessage(msg, channel, sender) end
end)

-------------------------------------------------------------------------------
-- объявления других: ролл предмета, список добычи, победитель

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
--   несколько ссылок — список добычи.
-- Свои сообщения РЛа тоже считаются (он мог кинуть ссылку руками), кроме того, что написал сам аддон.
function ns.OnGroupMessage(msg, sender, event)
	local me = sender == ns.PlayerName()
	if me and (ns.SentByAddon(msg) or msg:find("{rt", 1, true)) then return end -- это написал аддон
	-- ссылки: эпики — добыча и ролл сразу; синие и зелёные — ролл, только если пошли броски
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
	if not me and not ns.officers[sender] and not warning then
		ns.LootLog("list", sender, format("%d ссылок — пропущено: не РЛ, не помощник и не ответственный за добычу", #links))
		return
	end
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

	if #links == 1 then
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
			ns.LootLog("list", sender, link .. " — без слова «ролл»: начну считать, если пойдут броски")
		end
		return
	end

	if Settings().srcList and epic >= 2 then
		local items = {}
		for _, link in ipairs(links) do
			if (ns.LinkQuality(link) or 0) >= 4 then tinsert(items, {id = ns.ItemId(link), link = link}) end
		end
		ns.ReportLoot("list", sender, nil, items)
	end
end

for _, event in ipairs({"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER"}) do
	ns.On(event, function(msg, sender) ns.OnGroupMessage(msg, sender, event) end)
end
