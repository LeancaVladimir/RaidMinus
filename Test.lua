-- Тестовый рейд (/rm тест): прогнать всё до настоящего рейда, ничего не отправляя в чат.
--   «Тест: босс» — пул и убийство следующего босса ЦЛК; автоправила этого босса «ловят» игроков
--     (во вкладку «На проверку» или сразу минусом — как настроено у правила), шёпот !минус
--     от пойманного, добыча как будто тело открыл ответственный с RaidRoll (фильтр, окно «Добыча»).
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

-- кого может «поймать» автоправило (по роли и классу)
local PICK = {
	mg_cleave = function(p) return p.role ~= "tank" end,
	ld_mc_weapon = function(p) return p.role == "melee" or p.class == "HUNTER" end,
	sf_dps = function(p) return p.role == "melee" or p.role == "caster" end,
	sg_breath = function(p) return p.role ~= "tank" end,
	rf_vilegas = function(p) return p.role == "caster" or p.role == "healer" end,
	sunder = function(p) return p.class == "WARRIOR" and p.role ~= "tank" end,
}

local function Candidates(dkey)
	local s = ns.Session()
	local out = {}
	for _, name in ipairs(TestPlayers()) do
		local p = s.roster[name]
		if p and (not PICK[dkey] or PICK[dkey](p)) then tinsert(out, name) end
	end
	return out
end

local function TestDetail(dkey, rule)
	if dkey == "sf_dps" then
		local need = ns.RuleParam(rule, "dps")
		return format("тест: ДПС %d < %d (Skada)", need - random(300, 3000), need)
	end
	if dkey == "pp_bonus" then return "тест: в Профа 2,7М, в слизней 0,7М (Skada)" end
	return "тест: " .. ns.RuleText(rule)
end

function ns.TestBoss()
	local s = TestSession()
	if not s then return end
	local key = NextBoss(s)
	local sec = ns.Section(key)
	ns.BossPulled(key)

	-- автоматика: правила этого босса (и иногда общие — пул, раскол) «ловят» случайных игроков
	local rs = ns.ActiveRuleset()
	local victims, instant = {}, 0
	for _, d in ipairs(ns.DETECTORS) do
		if d.boss == key or (d.boss == "general" and random() < 0.5) then
			local rule = ns.AutoRule(rs, d.key)
			if rule and not rule.off then
				for _, name in ipairs(Pick(Candidates(d.key), d.key == "sf_dps" and 3 or 1)) do
					ns.Detected(d.key, name, TestDetail(d.key, rule))
					tinsert(victims, name)
					if rule.instant then instant = instant + 1 end
				end
			end
		end
	end
	ns.BossKilled(key)

	-- через 15 сек кто-то из пойманных спрашивает свои минусы (успейте принять находки)
	if #victims > 0 then
		ns.After(15, function()
			local now = ns.Session()
			if not now or not now.test then return end -- тестовый рейд могли уже закрыть
			local who = victims[1]
			for _, name in ipairs(victims) do
				if #ns.PlayerEvents(name) > 0 then who = name break end
			end
			ns.HandleWhisper("!минус", who)
		end)
	end

	-- добыча: тело открыл Холпал с аддоном RaidRoll (рассылка по каналу RRL), саронит фильтр скроет;
	-- через 3 сек Холпал забирает два предмета себе — строки чата лута не должны их задвоить
	local ids = Pick(TEST_LOOT[key] or {}, random(3, 4))
	tinsert(ids, SARONITE)
	for _, id in ipairs(ids) do
		local name = GetItemInfo(id) or ("Предмет " .. id)
		ns.OnRaidRollMessage(format("Beta_2\a%s\a%s\a%d\a%s\a277", LOOT_MASTER, sec.name, id, name), "RAID", LOOT_MASTER)
	end
	ns.After(3, function()
		local now = ns.Session()
		if not now or not now.test then return end
		for i = 1, 2 do
			if ids[i] then ns.OnLootMessage(format(LOOT_ITEM, LOOT_MASTER, ItemLink(ids[i]))) end
		end
	end)

	ns.Print(format("тест: %s убит. Автоматика: находок %d (сразу минусом %d, на проверку %d). Добыча — в окне «Добыча» (тело открыл Холпал с RaidRoll).",
		sec.name, #victims, instant, #victims - instant))
	if key == "saurfang" then
		ns.Print("тест: Холпал — хил, переодетый в ДД: планка ДПС его не касается.")
	end
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
