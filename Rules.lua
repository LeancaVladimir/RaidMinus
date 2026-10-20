-- Своды правил: минусы и плюсы по разделам (12 боссов и «Общие»).
-- Правила — данные: РЛ правит их во вкладке «Правила» (UI\RulesTab.lua) и делится строкой.
-- Правило:
--   id, boss = раздел, text = текст, value = очки (минус < 0 < плюс),
--   trig = триггер (нет — правило ставится только вручную), см. Triggers.lua:
--     on = включён, type = fail | combat | death | aura | yell | pull | skada | code, поля типа,
--     условия: count = с N-го раза за бой, per = each | fight | raid (не чаще), diff = hc | nm,
--     roles = {tank, healer, melee, caster} — роль виновного.
-- Своды до 0.4.0 переносятся при загрузке: встроенные автоправила (auto = ключ) становятся правилами
-- с триггером из шаблона (Data\Presets.lua), выключенными; лишние поля правила стираются.

local _, ns = ...

local tinsert, tremove = table.insert, table.remove
local pairs, ipairs, type, tonumber, tostring = pairs, ipairs, type, tonumber, tostring

local EXPORT_PREFIX = "RM2:"
local OLD_PREFIX = "RM1:"
local CODE_LIMIT = 6000

ns.ROLE_KEYS = {"tank", "healer", "melee", "caster"}
local ROLE_SET = {tank = true, healer = true, melee = true, caster = true}

ns.TRIG_TYPES = {
	{key = "fail", name = "Неудача (Skada)"},
	{key = "combat", name = "Журнал боя"},
	{key = "death", name = "Смерть"},
	{key = "aura", name = "Аура"},
	{key = "yell", name = "Сообщение босса"},
	{key = "pull", name = "DBM: пул раньше таймера"},
	{key = "skada", name = "Skada после убийства"},
	{key = "code", name = "Свой код (Lua)"},
}
local TYPE_SET = {}
for _, t in ipairs(ns.TRIG_TYPES) do TYPE_SET[t.key] = t.name end

function ns.TrigTypeName(key) return TYPE_SET[key or ""] or "—" end

local function NewRuleId(rs)
	rs.nextId = (rs.nextId or 0) + 1
	return "r" .. rs.nextId
end

local function Str(v, limit)
	if type(v) ~= "string" then return end
	v = strtrim(v)
	if v == "" then return end
	return v:sub(1, limit or 150)
end

local function Num(v)
	v = tonumber(v)
	if v and v > 0 then return v end
end

local function CopyRoles(roles)
	if type(roles) ~= "table" then return end
	local out, n = {}, 0
	for k, v in pairs(roles) do
		if ROLE_SET[k] and v then
			out[k] = true
			n = n + 1
		end
	end
	if n == 0 or n == 4 then return end -- все роли — то же, что без ограничения
	return out
end

-- триггер из чужих данных (импорт, копия): только известные поля
function ns.CopyTrig(t)
	if type(t) ~= "table" or not TYPE_SET[t.type or ""] then return end
	local code = type(t.code) == "string" and t.code:sub(1, CODE_LIMIT) or nil
	return {
		on = t.on and true or nil,
		type = t.type,
		fail = Str(t.fail, 60),
		event = Str(t.event, 20),
		spell = Str(t.spell, 400),
		from = Str(t.from, 200),
		who = Str(t.who, 10),
		amount = Num(t.amount),
		streak = Num(t.streak),
		stacks = Num(t.stacks),
		dur = Num(t.dur),
		text = Str(t.text, 150),
		early = Num(t.early),
		metric = Str(t.metric, 10),
		target = Str(t.target, 200),
		op = Str(t.op, 4),
		num = Num(t.num),
		events = Str(t.events, 300),
		code = code and code ~= "" and code or nil,
		count = Num(t.count),
		per = (t.per == "each" or t.per == "fight" or t.per == "raid") and t.per or nil,
		diff = (t.diff == "hc" or t.diff == "nm") and t.diff or nil,
		roles = CopyRoles(t.roles),
	}
end

local function MakeRule(rs, boss, text, value, trig)
	return {id = NewRuleId(rs), boss = boss, text = text, value = value or 0, trig = ns.CopyTrig(trig)}
end

-- правило из шаблона (Data\Presets.lua); given — числа РЛа (старый свод)
local function FromPreset(rs, p, given, text, value)
	local r = MakeRule(rs, p.boss, text or ns.PresetText(p, given), value or p.value or -10)
	r.trig = ns.PresetTrig(p, given)
	return r
end

-- старое правило (до 0.4.0): автоправило → шаблон; остальное — только текст, раздел, очки
local OLD_FIELDS = {"kick", "who", "off", "chat", "note", "rep", "step", "roles", "diff", "ann", "whisper", "quick",
	"auto", "params", "label", "instant"}

local function Upgrade(rs)
	local out = {}
	for _, r in ipairs(rs.rules) do
		if r.boss == "bonus" then r.boss = r.auto == "pp_bonus" and "putricide" or "general" end
		local p = ns.Preset(r.auto)
		if p then
			local text = (type(r.label) == "string" and r.label ~= "" and r.label) or ns.PresetText(p, r.params)
			local nr = FromPreset(rs, p, r.params, text, r.value)
			nr.id = r.id
			tinsert(out, nr)
			-- «дыхание или кольцо» было одним правилом — теперь два
			if p.key == "sg_breath" then tinsert(out, FromPreset(rs, ns.Preset("sg_grip"), nil, nil, r.value)) end
		elseif not r.auto then
			for _, k in ipairs(OLD_FIELDS) do r[k] = nil end
			if not ns.Section(r.boss) then r.boss = "general" end
			tinsert(out, r)
		end
	end
	rs.rules = out
	rs.v4 = true
end

local function UniqueName(name)
	local taken = {}
	for _, rs in ipairs(ns.DB.rulesets) do taken[rs.name] = true end
	if not taken[name] then return name end
	local i = 2
	while taken[name .. " (" .. i .. ")"] do i = i + 1 end
	return name .. " (" .. i .. ")"
end

function ns.NewRuleset(name)
	local db = ns.DB
	db.nextRulesetId = (db.nextRulesetId or 0) + 1
	local rs = {id = "s" .. db.nextRulesetId, name = UniqueName(name), rules = {}, v4 = true}
	tinsert(db.rulesets, rs)
	ns.TriggersDirty()
	return rs
end

-- новый свод — пустой: свои правила РЛ пишет сам или берёт из шаблонов
function ns.EmptyRuleset(name)
	return ns.NewRuleset(name or "Мой свод")
end

function ns.CopyRuleset(src)
	local rs = ns.NewRuleset(src.name)
	for _, r in ipairs(src.rules) do
		tinsert(rs.rules, MakeRule(rs, r.boss, r.text, r.value, r.trig))
	end
	return rs
end

function ns.RulesetById(id)
	for _, rs in ipairs(ns.DB.rulesets) do
		if rs.id == id then return rs end
	end
end

function ns.ActiveRuleset()
	local db = ns.DB
	local rs = ns.RulesetById(db.active) or db.rulesets[1]
	if not rs then rs = ns.EmptyRuleset() end
	db.active = rs.id
	return rs
end

-- смена свода посреди рейда: окно сразу показывает новые правила
function ns.SetActiveRuleset(id)
	local rs = ns.RulesetById(id)
	if rs then
		ns.DB.active = id
		local s = ns.Session()
		if s then s.ruleset = rs.name end
	end
	ns.TriggersDirty()
	ns.Refresh()
end

function ns.RenameRuleset(rs, name)
	rs.name = name
	local s = ns.Session()
	if s and rs == ns.ActiveRuleset() then s.ruleset = name end
end

function ns.DeleteRuleset(rs)
	local list = ns.DB.rulesets
	for i, x in ipairs(list) do
		if x == rs then tremove(list, i) break end
	end
	ns.ActiveRuleset()
	ns.TriggersDirty()
	ns.Refresh()
end

function ns.IsPlus(rule) return (rule.value or 0) > 0 end

-- правила раздела по порядку; sign: "minus" | "plus" | nil — все
function ns.RulesFor(rs, section, sign)
	local out = {}
	for _, r in ipairs(rs.rules) do
		if r.boss == section and (not sign or (sign == "plus") == ns.IsPlus(r)) then tinsert(out, r) end
	end
	return out
end

function ns.RuleById(rs, id)
	for _, r in ipairs(rs.rules) do
		if r.id == id then return r end
	end
end

-- plus — новый плюс (иначе минус)
function ns.AddRule(rs, section, plus)
	local r = MakeRule(rs, section, plus and "Новый плюс" or "Новый минус", plus and 10 or -10)
	tinsert(rs.rules, r)
	ns.TriggersDirty()
	return r
end

-- правило из шаблона в его раздел (выключено — включает РЛ)
function ns.AddPresetRule(rs, key)
	local p = ns.Preset(key)
	if not p then return end
	local r = FromPreset(rs, p)
	tinsert(rs.rules, r)
	ns.TriggersDirty()
	return r
end

function ns.DuplicateRule(rs, rule)
	local r = MakeRule(rs, rule.boss, rule.text .. " (копия)", rule.value, rule.trig)
	if r.trig then r.trig.on = nil end
	for i, x in ipairs(rs.rules) do
		if x == rule then tinsert(rs.rules, i + 1, r) return r end
	end
	tinsert(rs.rules, r)
	return r
end

function ns.RemoveRule(rs, rule)
	for i, r in ipairs(rs.rules) do
		if r == rule then tremove(rs.rules, i) break end
	end
	ns.TriggersDirty()
end

function ns.SetRuleSection(rule, section)
	if not ns.Section(section) then return end
	rule.boss = section
	ns.TriggersDirty()
end

-- сдвиг внутри раздела и группы (минусы / плюсы): dir = -1 выше, 1 ниже
function ns.MoveRule(rs, rule, dir)
	local list = rs.rules
	local i
	for k, r in ipairs(list) do
		if r == rule then i = k break end
	end
	if not i then return end
	local plus = ns.IsPlus(rule)
	local j = i + dir
	while list[j] and (list[j].boss ~= rule.boss or ns.IsPlus(list[j]) ~= plus) do j = j + dir end
	if list[j] then list[i], list[j] = list[j], list[i] end
end

-------------------------------------------------------------------------------
-- текст и вид правила

function ns.RuleText(rule) return rule and rule.text or "" end

-- текст в чат — без пояснения в скобках в конце: «Дух (оспаривается с видео)» -> «Дух»
function ns.ChatText(rule) return ns.ShortText(ns.RuleText(rule)) end

-- вид правила для цветной метки: auto — триггер включён, manual — только вручную
function ns.RuleKind(rule)
	if rule.trig and rule.trig.on then return "auto" end
	return "manual"
end

ns.KIND_COLORS = {auto = {1, 0.25, 0.25}, manual = {0.85, 0.85, 0.85}}
ns.KIND_HEX = {auto = "ffff4040", manual = "ffd9d9d9"}
ns.KIND_NAMES = {auto = "триггер включён", manual = "вручную"}

-- сложность рейда сейчас: "hc", "nm" или nil (не в рейде, тестовый рейд)
function ns.Difficulty()
	local s = ns.Session()
	if s and s.test then return end
	local _, kind = IsInInstance()
	if kind ~= "raid" then return end
	local d = GetInstanceDifficulty()
	return (d == 3 or d == 4) and "hc" or "nm"
end

-------------------------------------------------------------------------------
-- обмен строкой: RM2: + сжатые данные (AceSerializer + LibDeflate); RM1: (до 0.4.0) тоже читается

local function Libs()
	return LibStub("AceSerializer-3.0", true), LibStub("LibDeflate", true)
end

function ns.ExportRuleset(rs)
	local AS, LD = Libs()
	if not AS or not LD then return "" end
	local data = {v = 4, name = rs.name, rules = {}}
	for _, r in ipairs(rs.rules) do
		tinsert(data.rules, {b = r.boss, t = r.text, v = r.value, g = r.trig})
	end
	return EXPORT_PREFIX .. LD:EncodeForPrint(LD:CompressDeflate(AS:Serialize(data)))
end

-- импорт: свод, число правил со своим кодом (они приходят выключенными) или nil, ошибка
function ns.ImportRuleset(str)
	local AS, LD = Libs()
	if not AS or not LD then return nil, "нет библиотек AceSerializer/LibDeflate" end
	str = (tostring(str or ""):gsub("%s", ""))
	local prefix = str:sub(1, #EXPORT_PREFIX)
	if prefix ~= EXPORT_PREFIX and prefix ~= OLD_PREFIX then return nil, "это не строка RaidMinus (должна начинаться с RM2: или RM1:)" end
	local raw = LD:DecodeForPrint(str:sub(#EXPORT_PREFIX + 1))
	local text = raw and LD:DecompressDeflate(raw)
	if not text then return nil, "строка повреждена (скопирована не целиком?)" end
	local ok, data = AS:Deserialize(text)
	if not ok or type(data) ~= "table" or type(data.rules) ~= "table" then return nil, "строка повреждена" end

	local rs = ns.NewRuleset(type(data.name) == "string" and data.name:sub(1, 60) or "Импорт")
	local seen, code = {}, 0
	for _, r in ipairs(data.rules) do
		local sec = type(r) == "table" and (r.b == "bonus" and "general" or r.b)
		local p = type(r) == "table" and ns.Preset(r.a)
		if p and not seen[p.key] then
			-- автоправило из строки RM1
			seen[p.key] = true
			local label = type(r.l) == "string" and r.l ~= "" and r.l:sub(1, 150) or nil
			tinsert(rs.rules, FromPreset(rs, p, type(r.p) == "table" and r.p or nil, label, tonumber(r.v)))
		elseif not (type(r) == "table" and r.a) and sec and ns.Section(sec) and type(r.t) == "string" then
			local nr = MakeRule(rs, sec, r.t:sub(1, 150), tonumber(r.v) or 0, r.g)
			if nr.trig and nr.trig.type == "code" then
				nr.trig.on = nil -- чужой код не запускаем, пока РЛ его не посмотрел
				code = code + 1
			end
			tinsert(rs.rules, nr)
		end
	end
	return rs, code
end

ns.OnLoad(function()
	for _, rs in ipairs(ns.DB.rulesets) do
		if not rs.v4 then Upgrade(rs) end
	end
	ns.ActiveRuleset() -- при первом запуске создаёт пустой свод
end)
