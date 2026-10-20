-- Шаблоны правил с триггером (кнопка «+ Из шаблона» во вкладке «Правила») и неудачи LibFail для триггера
-- «Неудача (Skada)». Шаблоны — бывшие встроенные автоправила 0.1–0.3: при переносе старого свода правило
-- с auto = ключ становится обычным правилом с триггером из шаблона (выключенным — включает РЛ).
-- Сложные проверки (МК с оружием, газ, лужа Ланы, кольцо, раскол, бонус Профа) — «Свой код»: его видно и
-- можно поправить в редакторе. Числа РЛа подставляются в текст (%s) и в код ({ключ}).

local _, ns = ...

local format, tinsert = string.format, table.insert
local ipairs, tostring = ipairs, tostring

-------------------------------------------------------------------------------
-- неудачи LibFail (из Skada) в ЦЛК: ключ, раздел, название

ns.FAILS = {
	{"Fail_Marrowgar_SaberLash", "marrowgar", "Ребро: попал под клив"},
	{"Fail_Marrowgar_Coldflame", "marrowgar", "Ребро: стоял в холодном пламени"},
	{"Fail_Marrowgar_Whirlwind", "marrowgar", "Ребро: попал под вихрь костей"},
	{"Fail_Deathwhisper_Shade", "deathwhisper", "Леди: дух догнал"},
	{"Fail_Deathwhisper_ShadeExplosion", "deathwhisper", "Леди: умер от взрыва духа"},
	{"Fail_Deathwhisper_DeathNDecay", "deathwhisper", "Леди: стоял в Смерти и разложении"},
	{"Fail_Gunship_Explosion", "gunship", "Корабли: взрыв"},
	{"Fail_Gunship_Explosion_Knockback", "gunship", "Корабли: сбит взрывом"},
	{"Fail_Saurfang_Rune", "saurfang", "Орк: руна крови"},
	{"Fail_Saurfang_Beasts", "saurfang", "Орк: кровавые твари"},
	{"Fail_Festergut_PungentBlight", "festergut", "Тухлопуз: едкая гниль"},
	{"Fail_Festergut_VileGas", "festergut", "Тухлопуз: газ задел других"},
	{"Fail_Festergut_MalleableGoo", "festergut", "Тухлопуз: колба"},
	{"Fail_Rotface_StickyOoze", "rotface", "Гниломорд: стоял в луже"},
	{"Fail_Rotface_SlimeSpray", "rotface", "Гниломорд: под струёй слизи"},
	{"Fail_Rotface_OozeExplosion", "rotface", "Гниломорд: взрыв большого слизнюка"},
	{"Fail_Professor_MalleableGoo", "putricide", "Проф: колба"},
	{"Fail_Professor_ChokingGas", "putricide", "Проф: удушливый газ"},
	{"Fail_Professor_MutatedSlime", "putricide", "Проф: мутировавшая слизь"},
	{"Fail_BloodPrinces_Flames", "princes", "Принцы: апельсин"},
	{"Fail_BloodPrinces_KineticBomb", "princes", "Принцы: кинетическая бомба"},
	{"Fail_BloodPrinces_SystemicShockVortex", "princes", "Принцы: шоковый вихрь"},
	{"Fail_LanaThel_SwarmingShadows", "lanathel", "Лана: рой теней"},
	{"Fail_LanaThel_Pact", "lanathel", "Лана: пакт тёмных"},
	{"Fail_LanaThel_BloodboltSplash", "lanathel", "Лана: брызги кровавой стрелы"},
	{"Fail_LanaThel_DeliriousSlash", "lanathel", "Лана: исступлённый удар"},
	{"Fail_LanaThel_UncontrollableFrenzy", "lanathel", "Лана: не укусил (неутолимое бешенство)"},
	{"Fail_Valithria_ColumnofFrost", "valithria", "Валитрия: ледяной столп"},
	{"Fail_Valithria_EmeraldVigor", "valithria", "Валитрия: изумрудная бодрость"},
	{"Fail_Sindragosa_FrostBomb", "sindragosa", "Синдра: ледяная бомба"},
	{"Fail_Sindragosa_FrostBreath", "sindragosa", "Синдра: дыхание"},
	{"Fail_Sindragosa_BlisteringCold", "sindragosa", "Синдра: кольцо после притяжки"},
	{"Fail_Sindragosa_Instability", "sindragosa", "Синдра: нестабильность"},
	{"Fail_Sindragosa_ChilledtotheBone", "sindragosa", "Синдра: продрог до костей"},
	{"Fail_Sindragosa_MysticBuffet", "sindragosa", "Синдра: магический удар"},
	{"Fail_Sindragosa_IceTomb", "sindragosa", "Синдра: ледяная глыба"},
	{"Fail_Sindragosa_Cleave", "sindragosa", "Синдра: клив"},
	{"Fail_Sindragosa_TailSmash", "sindragosa", "Синдра: удар хвостом"},
	{"Fail_TheLichKing_Defile", "lichking", "Лич: осквернение"},
	{"Fail_TheLichKing_NecroticPlague", "lichking", "Лич: мертвящая чума"},
	{"Fail_TheLichKing_ShadowTrap", "lichking", "Лич: теневая ловушка"},
	{"Fail_TheLichKing_Shockwave", "lichking", "Лич: ударная волна"},
	{"Fail_TheLichKing_IceBurst", "lichking", "Лич: ледяной взрыв"},
	{"Fail_TheLichKing_RemorselessWinter", "lichking", "Лич: беспощадная зима"},
	{"Fail_TheLichKing_SoulShriek", "lichking", "Лич: вопль души"},
	{"Fail_TheLichKing_SpiritBomb", "lichking", "Лич: бомба духа"},
	{"Fail_ColdflameTrap", "general", "Ловушка холодного пламени"},
}

local failByKey = {}
for _, f in ipairs(ns.FAILS) do failByKey[f[1]] = f end

-- русское название неудачи (нет в списке — сам ключ LibFail)
function ns.FailName(key)
	local f = key and failByKey[key]
	return f and f[3] or tostring(key or "")
end

-- неудачи для раздела: босс — его, «Общие» — все
function ns.FailsFor(section)
	local out = {}
	for _, f in ipairs(ns.FAILS) do
		if section == "general" or f[2] == section then tinsert(out, f) end
	end
	return out
end

-------------------------------------------------------------------------------
-- шаблоны

local NOT_TANK = {healer = true, melee = true, caster = true}
local DD = {melee = true, caster = true}

local CODE_MC_WEAPON = [[
function(event, _, sub, _, _, _, _, dstName, _, spellId)
  -- на мили-ДД или охотника легло Подчинение разума, а оружие надето
  if sub ~= "SPELL_AURA_APPLIED" or spellId ~= 71289 or not RM.InRaid(dstName) then return end
  local hunter = RM.Class(dstName) == "HUNTER"
  if RM.Role(dstName) ~= "melee" and not hunter then return end
  local unit = RM.Unit(dstName)
  if not unit then return end
  for _, slot in ipairs(hunter and {16, 17, 18} or {16, 17}) do
    if GetInventoryItemLink(unit, slot) then return dstName, "под МК с оружием в руках" end
  end
end]]

local CODE_VILE_GAS = [[
function(event, _, sub, _, _, _, _, dstName, _, spellId)
  -- газ лёг на игрока (не мили) и задел мили — виноват тот, на кого лёг газ (один газ — один минус)
  if spellId ~= 72272 and spellId ~= 72273 then return end
  if sub == "SPELL_CAST_SUCCESS" then
    if RM.InRaid(dstName) then fight.gas = {target = dstName, t = RM.Time(), list = {}} end
    return
  end
  local g = fight.gas
  if sub ~= "SPELL_DAMAGE" or not g or g.done or RM.Time() - g.t > 2 then return end
  if dstName == g.target or not RM.InRaid(dstName) then return end
  local role = RM.Role(dstName)
  if role ~= "melee" and role ~= "tank" then return end
  local carrier = RM.Role(g.target)
  if carrier == "melee" or carrier == "tank" then return end
  table.insert(g.list, dstName)
  g.done = true
  return g.target, "газ задел мили: " .. table.concat(g.list, ", ")
end]]

local CODE_PUDDLE = [[
function(event, _, sub, _, _, _, _, dstName, _, spellId)
  -- пока на игроке Рой теней, его лужа задела {hits} и больше игроков — минус носителю (одна лужа — один минус)
  if RM.Is(spellId, 71264, 71265) then
    if sub == "SPELL_AURA_APPLIED" and RM.InRaid(dstName) then
      fight.puddle = {carrier = dstName, hits = {}, list = {}}
    elseif sub == "SPELL_AURA_REMOVED" and fight.puddle and fight.puddle.carrier == dstName then
      fight.puddle.ends = RM.Time() + 10 -- лужи ещё лежат
    end
    return
  end
  if (sub ~= "SPELL_DAMAGE" and sub ~= "SPELL_PERIODIC_DAMAGE") or not RM.Is(spellId, 71268, 72635, 72636, 72637) then return end
  local p = fight.puddle
  if not p or p.done or (p.ends and RM.Time() > p.ends) then return end
  if dstName == p.carrier or p.hits[dstName] or not RM.InRaid(dstName) then return end
  p.hits[dstName] = true
  table.insert(p.list, dstName)
  if #p.list >= {hits} then
    p.done = true
    return p.carrier, "лужа задела: " .. table.concat(p.list, ", ")
  end
end]]

local CODE_GRIP = [[
function(event, _, sub, _, _, _, _, dstName, _, spellId, _, _, _, overkill)
  -- умер от кольца после притяжки, хотя паладины нажали масс-сакру и мастер аур
  local now = RM.Time()
  if sub == "SPELL_CAST_SUCCESS" then
    if spellId == 70117 then fight.grip = now
    elseif spellId == 64205 then fight.ds = now
    elseif spellId == 31821 then fight.am = now end
    return
  end
  if sub ~= "SPELL_DAMAGE" or not RM.Is(spellId, 70123, 71047, 71048, 71049) then return end
  if (overkill or 0) <= 0 or not RM.InRaid(dstName) then return end
  local g = fight.grip
  if g and now - g < 10 and fight.ds and math.abs(fight.ds - g) < 10 and fight.am and math.abs(fight.am - g) < 10 then
    return dstName, "умер от кольца после притяжки (сакра и мастер аур были)"
  end
end]]

local CODE_SUNDER = [[
function(event, a, sub, _, srcName, _, _, _, _, spellId)
  -- воин (не танк) за первые {sec} сек боя ни разу не наложил Раскол брони
  if event == "RM_START" then
    if a == "gunship" or a == "valithria" then return end
    fight.sunders = {}
    RM.After({sec}, function()
      for _, name in ipairs(RM.Players()) do
        if RM.Class(name) == "WARRIOR" and RM.Role(name) ~= "tank" and not fight.sunders[name] then
          local unit = RM.Unit(name)
          if not unit or not UnitIsDeadOrGhost(unit) then RM.Fire(name, "нет раскола за первые {sec} сек") end
        end
      end
    end)
  elseif sub == "SPELL_CAST_SUCCESS" and fight.sunders and RM.Is(spellId, 7386, 7405, 8380, 11596, 11597, 25225, 47467) then
    fight.sunders[srcName] = true
  end
end]]

local CODE_PP_BONUS = [[
function(event, set)
  -- после убийства Профа: урон по Skada в босса от {boss} и в слизней от {ooze}
  local bossNames = RM.SkadaEnemies(set, 36678)
  if not next(bossNames) and set.mobname then bossNames[set.mobname] = true end
  local oozes = RM.SkadaEnemies(set, 37697, 37562)
  if not next(oozes) then
    oozes = {["Нестабильный слизнюк"] = true, ["Нестабильная слизь"] = true, ["Газовое облако"] = true,
      ["Volatile Ooze"] = true, ["Gas Cloud"] = true}
  end
  for _, p in ipairs(RM.SkadaPlayers(set)) do
    local b, o = 0, 0
    for target, amount in pairs(RM.SkadaTargets(p.actor)) do
      if bossNames[target] then b = b + amount elseif oozes[target] then o = o + amount end
    end
    if b >= {boss} and o >= {ooze} then
      RM.Fire(p.name, "в Профа " .. RM.Short(b) .. ", в слизней " .. RM.Short(o) .. " (Skada)")
    end
  end
end]]

-- params: {ключ, название, по умолчанию}; trig(числа) -> триггер; текст с %s — числа по порядку
ns.PRESETS = {
	{key = "mg_cleave", boss = "marrowgar", text = "Смерть от клива (не танк)",
		trig = function() return {type = "death", spell = "69055, 70814, 71021", roles = NOT_TANK} end},
	{key = "mg_coldflame", boss = "marrowgar", text = "Стоял в холодном пламени дольше %s сек",
		params = {{"sec", "Секунд", 3}},
		trig = function(p) return {type = "combat", event = "damage", spell = "69146, 70823, 70824, 70825", who = "dst", streak = p.sec} end},

	{key = "ld_shade", boss = "deathwhisper", text = "Дух догнал игрока",
		trig = function() return {type = "fail", fail = "Fail_Deathwhisper_Shade", per = "each"} end},
	{key = "ld_mc_kill", boss = "deathwhisper", text = "Под МК убил своего",
		trig = function() return {type = "death", who = "src", per = "each"} end},
	{key = "ld_mc_weapon", boss = "deathwhisper", text = "Под МК с оружием (мдд и охотники)",
		trig = function() return {type = "code", events = "COMBAT_LOG_EVENT_UNFILTERED", code = CODE_MC_WEAPON, per = "each"} end},

	{key = "sf_dps", boss = "saurfang", text = "Планка ДПС: меньше %s",
		params = {{"dps", "Мин. ДПС", 17000}},
		trig = function(p) return {type = "skada", metric = "dps", op = "lt", num = p.dps, roles = DD} end},

	{key = "fg_blight", boss = "festergut", text = "Смерть от гнили (не взял спору)",
		trig = function() return {type = "death", spell = "69195, 71219, 73031, 73032"} end},

	{key = "rf_ooze", boss = "rotface", text = "Смерть в луже",
		trig = function() return {type = "death", spell = "69774, 69776, 69778, 71208"} end},
	{key = "rf_vilegas", boss = "rotface", text = "Заблевал милишников (гер.)",
		trig = function() return {type = "code", events = "COMBAT_LOG_EVENT_UNFILTERED", code = CODE_VILE_GAS, per = "each"} end},

	{key = "pp_death", boss = "putricide", text = "Смерть от чумы / пельменя / колбы",
		trig = function() return {type = "death",
			spell = "70911, 72854, 72855, 72856, 70492, 72505, 72624, 72625, 70853, 72458, 72873, 72874"} end},
	{key = "pp_bonus", boss = "putricide", value = 10, text = "Проф: %s в босса и %s в слизней",
		params = {{"boss", "Урон в Профа", 2500000}, {"ooze", "Урон в слизней", 650000}},
		trig = function(p) return {type = "code", events = "RM_SKADA", code = CODE_PP_BONUS, per = "fight", vars = p} end},

	{key = "bp_flames", boss = "princes", text = "Смерть от апельсина",
		trig = function() return {type = "death", spell = "71393, 72789, 72790, 72791"} end},

	{key = "bq_puddle", boss = "lanathel", text = "Лужа в рейд (носитель метки)",
		params = {{"hits", "Задел игроков", 2}},
		trig = function(p) return {type = "code", events = "COMBAT_LOG_EVENT_UNFILTERED", code = CODE_PUDDLE, per = "each", vars = p} end},

	{key = "sg_bomb", boss = "sindragosa", text = "Смерть от ледяной бомбы",
		trig = function() return {type = "death", spell = "69845, 71053, 71054, 71055"} end},
	{key = "sg_breath", boss = "sindragosa", text = "Смерть от дыхания (не танк)",
		trig = function() return {type = "death", spell = "69649, 71056, 71057, 71058, 73061, 73062, 73063, 73064", roles = NOT_TANK} end},
	{key = "sg_grip", boss = "sindragosa", text = "Смерть от кольца после притяжки (были сакра и мастер аур)",
		trig = function() return {type = "code", events = "COMBAT_LOG_EVENT_UNFILTERED", code = CODE_GRIP} end},

	{key = "pull_early", boss = "general", text = "Пул раньше таймера",
		trig = function() return {type = "pull", early = 1, per = "each"} end},
	{key = "sunder", boss = "general", text = "Воин без раскола в начале боя (%s сек)",
		params = {{"sec", "Секунд", 10}},
		trig = function(p) return {type = "code", events = "RM_START, COMBAT_LOG_EVENT_UNFILTERED", code = CODE_SUNDER, vars = p} end},
}

local presetByKey = {}
for _, p in ipairs(ns.PRESETS) do presetByKey[p.key] = p end

function ns.Preset(key) return key and presetByKey[key] end

-- шаблоны раздела (босс — его; «Общие» — общие)
function ns.PresetsFor(section)
	local out = {}
	for _, p in ipairs(ns.PRESETS) do
		if p.boss == section then tinsert(out, p) end
	end
	return out
end

-- числа шаблона: свои у РЛа (старый свод) или по умолчанию
local function Params(p, given)
	local out = {}
	for _, x in ipairs(p.params or {}) do
		out[x[1]] = (given and tonumber(given[x[1]])) or x[3]
	end
	return out
end

-- текст правила по шаблону: «Планка ДПС: меньше 17к»
function ns.PresetText(p, given)
	if not p.params then return p.text end
	local values = Params(p, given)
	local list = {}
	for i, x in ipairs(p.params) do
		local v = values[x[1]]
		list[i] = v >= 1000 and ns.ShortNumber(v) or tostring(v)
	end
	return format(p.text, unpack(list))
end

-- триггер по шаблону (выключен); числа РЛа — в поля и в код ({ключ})
function ns.PresetTrig(p, given)
	local values = Params(p, given)
	local t = p.trig(values)
	local vars = t.vars
	t.vars = nil
	if t.code and vars then
		t.code = t.code:gsub("{(%w+)}", function(k) return vars[k] and tostring(vars[k]) or nil end)
	end
	if t.roles then
		local copy = {}
		for k in pairs(t.roles) do copy[k] = true end
		t.roles = copy
	end
	t.on = nil
	return t
end
