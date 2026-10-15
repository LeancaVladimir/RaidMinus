-- Встроенные автоправила (выбор РЛа): есть в каждом своде, по умолчанию -10 (бонус Профа +10).
-- Ловит их Detect.lua (журнал боя, DBM) и Metrics.lua (Skada). Находка идёт во вкладку «На проверку»;
-- у правила можно включить «ставить сразу» (rule.instant) — тогда минус игроку без проверки.
-- В своде у такого правила: rule.auto = ключ, rule.params = числа РЛа, rule.off = выключено.
-- Текст правила собирается из шаблона text и чисел params («дольше 3 сек»).

local _, ns = ...

local format = string.format

-- 2500000 -> «2,5М», 650000 -> «0,65М», 17000 -> «17к»
function ns.ShortNumber(n)
	n = tonumber(n) or 0
	if n >= 1000000 then
		return (format("%.2f", n / 1000000):gsub("0+$", ""):gsub("%.$", ""):gsub("%.", ",")) .. "М"
	end
	if n >= 1000 then
		return (format("%.1f", n / 1000):gsub("%.0$", ""):gsub("%.", ",")) .. "к"
	end
	return tostring(n)
end

ns.DETECTORS = {
	{key = "mg_cleave", boss = "marrowgar", hard = true, text = "Смерть от клива (не танк)",
		how = "Последний удар — клив Ребра (Удар саблей), игрок не танк по основной роли."},
	{key = "mg_coldflame", boss = "marrowgar", hard = true, text = "Стоял в холодном пламени дольше %s сек",
		params = {{key = "sec", name = "Секунд", default = 3}},
		how = "Холодное пламя било игрока без перерыва дольше заданного."},

	{key = "ld_shade", boss = "deathwhisper", hard = true, text = "Дух догнал игрока",
		how = "Мстительный дух ударил того, за кем шёл (один дух — один минус)."},
	{key = "ld_mc_kill", boss = "deathwhisper", hard = true, text = "Под МК убил своего",
		how = "Игрок под Подчинением разума нанёс смертельный удар игроку рейда."},
	{key = "ld_mc_weapon", boss = "deathwhisper", hard = true, text = "Под МК с оружием (мдд и охотники)",
		how = "На мили-ДД или охотника легло Подчинение разума, а оружие надето."},

	{key = "sf_dps", boss = "saurfang", hard = true, text = "Планка ДПС: меньше %s",
		params = {{key = "dps", name = "Мин. ДПС", default = 17000}},
		how = "После убийства — ДПС по Skada у основной роли мдд/рдд. Хил или танк, переодетый в ДД, не считается."},

	{key = "fg_blight", boss = "festergut", hard = true, text = "Смерть от гнили (не взял спору)",
		how = "Последний удар — Едкая гниль."},

	{key = "rf_ooze", boss = "rotface", hard = true, text = "Смерть в луже",
		how = "Последний удар — Липкая слизь (лужа)."},
	{key = "rf_vilegas", boss = "rotface", text = "Заблевал милишников (гер.)",
		how = "Газ лёг на игрока (не мили), и он задел мили. Виноват тот, на кого лёг газ."},

	{key = "pp_death", boss = "putricide", hard = true, text = "Смерть от чумы / пельменя / колбы",
		how = "Последний удар — Чума, взрыв слизи (пельмень) или Податливая слизь (колба)."},

	{key = "bp_flames", boss = "princes", hard = true, text = "Смерть от апельсина",
		how = "Последний удар — Пламя (апельсин)."},

	{key = "bq_puddle", boss = "lanathel", text = "Лужа в рейд (носитель метки)",
		params = {{key = "hits", name = "Задел игроков", default = 2}},
		how = "Пока на игроке Рой теней, его лужа задела других — минус носителю."},

	{key = "sg_bomb", boss = "sindragosa", hard = true, text = "Смерть от ледяной бомбы",
		how = "Последний удар — Ледяная бомба."},
	{key = "sg_breath", boss = "sindragosa", hard = true, text = "Смерть от дыхания или от притяжки (была сакра и мастер аур)",
		how = "Умер от дыхания (не танк) или от кольца после притяжки, хотя паладины нажали масс-сакру и мастер аур."},

	{key = "pull_early", boss = "general", hard = true, text = "Пул раньше таймера",
		how = "DBM-таймер пула ещё шёл, а босс уже в бою. Виноват тот, кто первым ударил."},
	{key = "sunder", boss = "general", hard = true, text = "Воин без раскола в начале боя (%s сек)",
		params = {{key = "sec", name = "Секунд", default = 10}},
		how = "Воин (не танк) за первые секунды боя ни разу не наложил Раскол брони."},

	{key = "pp_bonus", boss = "putricide", hard = true, value = 10, text = "Проф: %s в босса и %s в слизней",
		params = {{key = "boss", name = "Урон в Профа", default = 2500000}, {key = "ooze", name = "Урон в слизней", default = 650000}},
		how = "После убийства Профа — урон по Skada: в босса и в слизней (оба порога)."},
}

local byKey = {}
for _, d in ipairs(ns.DETECTORS) do byKey[d.key] = d end

function ns.Detector(key) return key and byKey[key] end

-- число правила (своё у РЛа или по умолчанию)
function ns.RuleParam(rule, pkey)
	local d = ns.Detector(rule.auto)
	if rule.params and rule.params[pkey] ~= nil then return rule.params[pkey] end
	if d and d.params then
		for _, p in ipairs(d.params) do
			if p.key == pkey then return p.default end
		end
	end
end

-- текст правила: у автоправил — свой текст РЛа (rule.label) или шаблон с числами РЛа
function ns.RuleText(rule)
	local d = rule and ns.Detector(rule.auto)
	if not d then return rule and rule.text or "" end
	if rule.label and rule.label ~= "" then return rule.label end
	if not d.params then return d.text end
	local values = {}
	for i, p in ipairs(d.params) do
		local v = ns.RuleParam(rule, p.key)
		values[i] = (v and v >= 1000) and ns.ShortNumber(v) or tostring(v)
	end
	return format(d.text, unpack(values))
end

-- вид правила для цветной метки: auto — автоматика, known — видно, кто нарушил, manual — вручную
function ns.RuleKind(rule)
	if rule.auto then return "auto" end
	if rule.who then return "known" end
	return "manual"
end

ns.KIND_COLORS = {auto = {1, 0.25, 0.25}, known = {1, 0.55, 0.1}, manual = {0.85, 0.85, 0.85}}
ns.KIND_HEX = {auto = "ffff4040", known = "ffff8c1a", manual = "ffd9d9d9"}
ns.KIND_NAMES = {auto = "автоматика", known = "видно, кто нарушил", manual = "вручную"}
