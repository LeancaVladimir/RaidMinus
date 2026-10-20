-- Тестовый рейд (/rm тест): прогнать всё до настоящего рейда, ничего не отправляя в чат.
--   «Тест: босс» — пул и убийство следующего босса ЦЛК; включённые триггеры его правил (и иногда
--     «Общих») «ловят» подходящих выдуманных игроков — с условиями правила, шёпот !минус от пойманного;
--     ответственный Холпал берёт добычу в сумку (вкладка «Розыгрыш», кнопка «Ролл»).
--   «Тест: чужой ролл» — ответственный за добычу (Холпал) объявляет ролл, выдуманные игроки бросают.
-- Всё, что ушло бы в чат, печатается у вас с пометкой (тест) [Рейд] / [Объявление рейду] / [Шёпот].

local _, ns = ...

local format, tinsert, tremove = string.format, table.insert, table.remove
local ipairs, random = ipairs, math.random

local LOOT_MASTER = "Холпал"
local SARONITE = 49908

-- эпики ЦЛК 25 гер. по боссам (из AtlasLoot)
local TEST_LOOT = {
	marrowgar = {50604, 50605, 50606, 50607, 50608, 50609, 50610, 50611, 50612, 50613, 50614, 50615, 50616, 50617, 50709},
	deathwhisper = {50638, 50639, 50640, 50641, 50642, 50643, 50644, 50645, 50646, 50647, 50648, 50649, 50650, 50651, 50652},
	gunship = {50349, 50366, 50653, 50654, 50655, 50656, 50657, 50658, 50659, 50660, 50661, 50663, 50664, 50665, 50667},
	saurfang = {50363, 50668, 50670, 50671, 50672, 52025, 52026, 52027},
	festergut = {50688, 50689, 50690, 50691, 50692, 50693, 50694, 50695, 50696, 50697, 50698, 50699, 50700, 50701, 50702, 50703},
	rotface = {50231, 50348, 50673, 50674, 50675, 50676, 50677, 50678, 50679, 50680, 50681, 50682, 50684, 50685, 50686, 50687},
	putricide = {50704, 50705, 50706, 50707, 50708, 52028, 52029, 52030},
	princes = {50603, 50710, 50711, 50712, 50713, 50714, 50715, 50716, 50717, 50718, 50719, 50720, 50721, 50722, 50723},
	lanathel = {50724, 50725, 50726, 50727, 50728, 50729, 52025, 52026, 52027},
	valithria = {50618, 50619, 50620, 50621, 50622, 50623, 50624, 50625, 50626, 50627, 50628, 50629, 50630, 50631, 50632},
	sindragosa = {50364, 50365, 50633, 50635, 50636, 52028, 52029, 52030},
	lichking = {50730, 50731, 50732, 50733, 50734, 50735, 50736, 50737, 50738, 50818, 52025, 52026, 52027},
}

local function TestSession()
	local s = ns.Session()
	if not s or not s.test then
		ns.Print("это работает только в тестовом рейде: кнопка «Тест» или /rm тест.")
		return
	end
	return s
end

-- ссылка на предмет; если клиент его ещё не видел — временное имя (наведите мышь — подгрузится)
local function ItemLink(id)
	local _, link = GetItemInfo(id)
	return link or format("|cffa335ee|Hitem:%d:0:0:0:0:0:0:0:80|h[Предмет %d]|h|r", id, id)
end

local function Pick(list, n)
	local pool, out = {}, {}
	for _, x in ipairs(list) do tinsert(pool, x) end
	for _ = 1, math.min(n, #pool) do tinsert(out, tremove(pool, random(#pool))) end
	return out
end

local function TestPlayers()
	local out = {}
	for _, name in ipairs(ns.RosterNames()) do
		if name ~= ns.PlayerName() and name ~= LOOT_MASTER then tinsert(out, name) end
	end
	return out
end

local function NextBoss(s)
	local keys = {}
	for _, sec in ipairs(ns.SECTIONS) do
		if not sec.general then tinsert(keys, sec.key) end
	end
	s.testBoss = (s.testBoss or 0) % #keys + 1
	return keys[s.testBoss]
end

function ns.TestBoss()
	local s = TestSession()
	if not s then return end
	local key = NextBoss(s)
	local sec = ns.Section(key)
	ns.BossPulled(key)
	local before = #s.events
	local caught = ns.TestTriggers(key)
	ns.BossKilled(key)

	-- через 15 сек кто-то из пойманных спрашивает свои минусы
	local victims = {}
	for i = before + 1, #s.events do tinsert(victims, s.events[i].player) end
	if #victims > 0 then
		ns.After(15, function()
			local now = ns.Session()
			if not now or not now.test then return end -- тестовый рейд могли уже закрыть
			ns.HandleWhisper("!минус", victims[1])
		end)
	end

	-- добыча: ответственный Холпал берёт три предмета в сумку (саронит — мусор, не записывается)
	local ids = Pick(TEST_LOOT[key] or {}, 3)
	tinsert(ids, SARONITE)
	for _, id in ipairs(ids) do ns.OnLootMessage(format(LOOT_ITEM, LOOT_MASTER, ItemLink(id))) end

	ns.Print(format("тест: %s убит. Триггеры поймали: %d%s. Холпал взял в сумку %d предм. — вкладка «Розыгрыш», кнопка «Ролл».",
		sec.name, caught, caught == 0 and " (включите триггеры правил этого босса во вкладке «Правила»)" or "", #ids - 1))
end

-- ответственный за добычу объявляет ролл предмета из списка (или с последнего босса)
function ns.TestForeignRoll()
	local s = TestSession()
	if not s then return end
	local link
	for _, e in ipairs(s.loot) do
		if not e.result and not e.winner then link = e.link break end
	end
	if not link then link = ItemLink(TEST_LOOT[s.boss or "marrowgar"][1]) end
	ns.Print(format("|cff9d9d9d(тест)|r |cffff4800[Объявление рейду]|r %s: Ролл %s — кидаем /roll, 30 сек", LOOT_MASTER, link))
	ns.OnGroupMessage("Ролл " .. link .. " — кидаем /roll, 30 сек", LOOT_MASTER)
	ns.TestRolls()
	ns.ShowTab("loot")
end
