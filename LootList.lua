-- Список добычи для розыгрыша. Откуда берётся предмет (loot.src):
--   self     — я залутал (CHAT_MSG_LOOT);
--   corpse   — увидел на теле босса или в списке, который скинул в рейд ответственный за добычу
--              (окошко «Добыча», UI\BossLoot.lua, добавляется кнопкой «+»);
--   announce — лидер, ассистент или ответственный за добычу объявил ролл предмета: предмет сам
--              попадает в список, а аддон тихо считает броски с учётом минусов (Roll.lua);
--   manual   — вручную: shift+клик, перетаскивание, /rm лут.
-- Один предмет из разных источников не дублируется: «увидел на теле» + «залутал» — одна запись.

local _, ns = ...

local format, tinsert, tremove = string.format, table.insert, table.remove
local ipairs = ipairs

local LINK = "|c%x+|Hitem:.-|h.-|h|r"
local QUALITY_BY_COLOR = {ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5}

-- слова в объявлении (без текста ссылок): начало ролла и объявление победителя
local ROLL_WORDS = {"ролл", "ролим", "роллим", "рол ", "кидаем", "кидайте", "roll"}
local WIN_WORDS = {"выиграл", "победил", "побеждает", "забирает", "won", "wins", "winner"}

ns.SOURCES = {self = "залутал я", corpse = "с тела / из списка", announce = "объявлен ролл", manual = "вручную"}

local function Settings() return ns.DB.settings end

local function LootPatterns()
	return {ns.ToPattern(LOOT_ITEM_SELF_MULTIPLE), ns.ToPattern(LOOT_ITEM_SELF)}
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

local function Src(e)
	if not e.src then e.src = {manual = true} end
	return e.src
end

function ns.LootById(id)
	local s = ns.Session()
	if not s or not id then return end
	for _, e in ipairs(s.loot) do
		if e.id == id then return e end
	end
end

-- «залутал я, с тела, объявил Вася»
function ns.LootSourceText(e)
	local parts = {}
	for _, key in ipairs({"corpse", "self", "announce", "manual"}) do
		local v = Src(e)[key]
		if v then
			if key == "announce" and type(v) == "string" then
				tinsert(parts, "ролл объявил " .. v)
			elseif key == "corpse" and type(v) == "string" then
				tinsert(parts, "из списка " .. v)
			else
				tinsert(parts, ns.SOURCES[key])
			end
		end
	end
	return table.concat(parts, ", ")
end

-- src — откуда (см. начало файла), by — кто объявил. Возвращает запись и true, если она новая.
function ns.AddLoot(link, src, by)
	local s = ns.Session()
	if not s then
		ns.Print("сначала начните рейд: /rm старт.")
		return
	end
	src = src or "manual"
	local item = ns.ItemId(link)
	if src ~= "manual" then
		for _, e in ipairs(s.loot) do
			local busy = ns.roll and ns.roll.loot == e.id and ns.roll.state == "open"
			if e.item == item and not e.result and not busy and not Src(e)[src] then
				Src(e)[src] = by or true
				ns.Refresh()
				return e, false
			end
		end
	end
	s.nextLoot = (s.nextLoot or 0) + 1
	local e = {
		id = s.nextLoot, link = link, item = item, cat = ns.ItemCategory(link), t = time(),
		src = {[src] = by or true}, boss = s.boss,
	}
	tinsert(s.loot, e)
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

ns.On("CHAT_MSG_LOOT", function(msg)
	if not ns.Session() or not Settings().collectLoot then return end
	for _, p in ipairs(LootPatterns()) do
		local found = p and msg:match(p)
		if found then
			local link = found:match(LINK)
			if link and (ns.LinkQuality(link) or 0) >= Settings().lootQuality then ns.AddLoot(link, "self") end
			return
		end
	end
end)

-------------------------------------------------------------------------------
-- окошко «Добыча»: тело босса или список, скинутый в рейд

ns.drop = nil -- {key, title, items = {{key, link, texture, added = id записи}}}

function ns.ShowDrop(key, title, links, by)
	local s = ns.Session()
	s.drops = s.drops or {}
	local seen = s.drops[key] or {}
	s.drops[key] = seen
	local items, count = {}, {}
	for _, x in ipairs(links) do
		count[x.link] = (count[x.link] or 0) + 1
		local ikey = x.link .. "#" .. count[x.link]
		local added = seen[ikey] and ns.LootById(seen[ikey]) and seen[ikey] or nil
		tinsert(items, {key = ikey, link = x.link, texture = x.texture, added = added})
	end
	ns.drop = {key = key, title = title, by = by, items = items}
	if Settings().autoDropLoot then ns.AddDropItems() end
	if ns.ShowDropPanel then ns.ShowDropPanel() end
end

function ns.AddDropItem(item)
	local s, d = ns.Session(), ns.drop
	if not s or not d or (item.added and ns.LootById(item.added)) then return end
	local e = ns.AddLoot(item.link, "corpse", d.by)
	if e then
		item.added = e.id
		s.drops[d.key][item.key] = e.id
	end
	if ns.ShowDropPanel then ns.ShowDropPanel() end
end

function ns.AddDropItems()
	if not ns.drop then return end
	for _, item in ipairs(ns.drop.items) do ns.AddDropItem(item) end
end

ns.On("LOOT_OPENED", function()
	if not ns.Session() or not Settings().dropPanel then return end
	local guid = UnitExists("target") and UnitIsDead("target") and UnitGUID("target")
	local links = {}
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		local texture, _, _, quality = GetLootSlotInfo(slot)
		if link and (quality or ns.LinkQuality(link) or 0) >= Settings().lootQuality then
			tinsert(links, {link = link, texture = texture})
		end
	end
	if #links == 0 then return end
	local title = guid and UnitName("target") or "Добыча"
	ns.ShowDrop(guid or ("open" .. time()), title, links)
end)

-------------------------------------------------------------------------------
-- объявления других: ролл предмета, список добычи, победитель

local function HasWord(text, words)
	for _, w in ipairs(words) do
		if text:find(w, 1, true) then return true end
	end
end

-- сообщение в рейд или группу (тестовый рейд вызывает напрямую — «ответственный объявил ролл»)
function ns.OnGroupMessage(msg, sender)
	if not ns.Session() or not Settings().watchOthers then return end
	if sender == ns.PlayerName() or not ns.officers[sender] then return end
	local links = {}
	for link in msg:gmatch(LINK) do
		if (ns.LinkQuality(link) or 0) >= Settings().lootQuality then tinsert(links, link) end
	end
	if #links == 0 then return end
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

	if #links == 1 and HasWord(text, ROLL_WORDS) then
		local e = ns.AddLoot(links[1], "announce", sender)
		if e then ns.WatchRoll(e, sender) end
		return
	end

	if #links >= 2 then
		local list = {}
		for _, link in ipairs(links) do
			tinsert(list, {link = link, texture = select(10, GetItemInfo(link))})
		end
		ns.ShowDrop("list:" .. sender .. ":" .. time(), "Список от " .. sender, list, sender)
	end
end

for _, event in ipairs({"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER"}) do
	ns.On(event, function(msg, sender) ns.OnGroupMessage(msg, sender) end)
end
