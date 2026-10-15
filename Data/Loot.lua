-- Добыча ЦЛК 25 гер. по боссам (из AtlasLoot) и фильтр «важной» добычи.
-- По таблице аддон узнаёт, с какого босса предмет, даже если тело открывал не РЛ,
-- и отличает гер. снаряжение от мусора (осколки, саронит). Предмет не из таблицы
-- проходит фильтр, если он эпический, надевается и его уровень не ниже настройки (277).

local _, ns = ...

local tonumber, ipairs, pairs, select = tonumber, ipairs, pairs, select

local ICC25H = {
	marrowgar = {50613, 50615, 50607, 50605, 50617, 50606, 50611, 50612, 50609, 50604, 50614, 50610, 50608, 50709, 50616},
	deathwhisper = {50643, 50651, 50646, 50649, 50645, 50652, 50640, 50650, 50639, 50647, 50642, 50644, 50641, 50648, 50638},
	gunship = {50653, 50661, 50663, 50656, 50665, 50655, 50660, 50659, 50667, 50658, 50664, 50657, 50366, 50349, 50654},
	saurfang = {50668, 50670, 50671, 50363, 50672},
	festergut = {50702, 50694, 50699, 50697, 50696, 50698, 50689, 50703, 50688, 50701, 50690, 50691, 50700, 50693, 50692, 50695},
	rotface = {50677, 50686, 50679, 50675, 50673, 50687, 50674, 50681, 50680, 50682, 50678, 50348, 50685, 50676, 50684, 50231},
	putricide = {50707, 50705, 50706, 50708, 50704},
	princes = {50718, 50717, 50722, 50713, 50715, 50723, 50711, 50712, 50716, 50721, 50720, 50714, 50719, 50710, 50603},
	lanathel = {50724, 50728, 50726, 50727, 50725, 50729},
	valithria = {50628, 50629, 50630, 50626, 50619, 50620, 50623, 50624, 50632, 50625, 50627, 50622, 50618, 50621, 50631},
	sindragosa = {50633, 50636, 50365, 50364, 50635},
	lichking = {50736, 50732, 50730, 50737, 50734, 50738, 50735, 50731, 50733, 50818},
}

-- жетоны на комплект (знаки освящения) — с нескольких боссов
local TOKENS = {[52025] = true, [52026] = true, [52027] = true, [52028] = true, [52029] = true, [52030] = true}
-- никогда не в розыгрыш: осколок Льда Тьмы (квест), древнейший саронит, эмблемы, кристаллы
local JUNK = {[50274] = true, [49908] = true, [49426] = true, [47241] = true, [34057] = true, [51026] = true}
local MOUNT = {[50818] = true} -- Поводья Непобедимого

local bossOf = {}
for boss, ids in pairs(ICC25H) do
	for _, id in ipairs(ids) do bossOf[id] = boss end
end

-- босс по предмету (нет — предмет общий или не из ЦЛК 25 гер.)
function ns.LootBoss(id) return id and bossOf[id] end

function ns.IsToken(id) return id and TOKENS[id] or false end

-- проходит ли предмет фильтр «важной» добычи; второе значение — почему нет
-- (ilvl и качество берутся из ссылки или из сообщения RaidRoll, если клиент ещё не знает предмет)
function ns.LootWanted(id, link, ilvl, quality)
	if not id then return false, "нет предмета" end
	if JUNK[id] then return false, "мусор" end
	if TOKENS[id] or MOUNT[id] or bossOf[id] then return true end
	local set = ns.DB.settings
	local name, _, q, level, _, _, _, _, equip = GetItemInfo(link or id)
	q = q or quality
	level = level or ilvl
	if set.lootFilter == "epic" then
		if (q or 0) >= (set.lootQuality or 4) then return true end
		return false, "качество"
	end
	if (q or 0) < 4 then return false, "не эпик" end
	if name and (not equip or equip == "") then return false, "не надевается" end
	if not level then return false, "уровень неизвестен" end
	if level < (set.lootMinIlvl or 277) then return false, "ilvl " .. level end
	return true
end

-- подпись категории для списка добычи
function ns.LootKind(id, link)
	if not id then return "" end
	if TOKENS[id] then return "жетон" end
	if MOUNT[id] then return "маунт" end
	local cat = ns.ItemCategory(link or ("item:" .. id))
	if cat == "trinket" then return "тринкет" end
	if cat == "lk_weapon" then return "оружие Лича" end
	local equip = select(9, GetItemInfo(link or id))
	return equip and _G[equip] or ""
end

ns.LOOT_TABLE = ICC25H
