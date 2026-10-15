-- Разделы правил: боссы ЦЛК (по порядку прохождения), «Общее» и «Плюсы».
-- dbm — id мода DBM (DBM-Icecrown), по нему аддон узнаёт, какой босс сейчас.

local _, ns = ...

ns.SECTIONS = {
	{key = "marrowgar", name = "Лорд Ребрад", short = "Ребро", dbm = "LordMarrowgar"},
	{key = "deathwhisper", name = "Леди Смертный Шёпот", short = "Леди", dbm = "Deathwhisper"},
	{key = "gunship", name = "Битва на кораблях", short = "Корабли", dbm = "GunshipBattle"},
	{key = "saurfang", name = "Саурфанг Смертоносный", short = "Орк", dbm = "Deathbringer"},
	{key = "festergut", name = "Тухлопуз", short = "Тухлопуз", dbm = "Festergut"},
	{key = "rotface", name = "Гниломорд", short = "Гниломорд", dbm = "Rotface"},
	{key = "putricide", name = "Профессор Мерзоцид", short = "Проф", dbm = "Putricide"},
	{key = "princes", name = "Кровавый совет", short = "Принцы", dbm = "BPCouncil"},
	{key = "lanathel", name = "Королева Лана'тель", short = "Лана", dbm = "Lanathel"},
	{key = "valithria", name = "Валитрия Сноходица", short = "Валитрия", dbm = "Valithria"},
	{key = "sindragosa", name = "Синдрагоса", short = "Синдра", dbm = "Sindragosa"},
	{key = "lichking", name = "Король-лич", short = "Лич", dbm = "LichKing"},
	{key = "general", name = "Общее", short = "Общее", general = true},
	{key = "bonus", name = "Плюсы", short = "Плюсы", general = true},
}

local byKey, byDBM = {}, {}
for i, sec in ipairs(ns.SECTIONS) do
	sec.order = i
	byKey[sec.key] = sec
	if sec.dbm then byDBM[sec.dbm] = sec.key end
end

function ns.Section(key) return key and byKey[key] end

-- босс (не «Общее» и не «Плюсы»)
function ns.IsBoss(key)
	local sec = byKey[key or ""]
	return sec and not sec.general
end

function ns.BossByDBM(modId) return modId and byDBM[modId] end

function ns.ShortName(key)
	local sec = byKey[key or ""]
	return sec and sec.short or "—"
end

