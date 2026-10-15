-- Своды правил: минусы и плюсы по разделам (12 боссов и «Общие»).
-- Правила — данные: РЛ правит их во вкладке «Правила» (UI\RulesTab.lua) и делится строкой.
-- Правило:
--   id, boss = раздел, text = текст в окне, value = очки (минус < 0 < плюс), kick = «на кик»,
--   off = выключено, who = видно, кто нарушил (оранжевая метка; иначе белая — только вручную),
--   chat = текст в чат (пусто — текст в окне без пояснения в скобках), note = пояснение (подсказка),
--   rep = повтор: nil — каждый раз, "fight" — раз за бой, "raid" — раз за рейд (одному игроку),
--   step = нарастание: каждый следующий раз тому же игроку ещё столько очков (-10: -10, -20, -30),
--   roles = {tank, healer, melee, caster} — кому можно ставить (нет — всем), по основной роли,
--   diff = "hc" | "nm" — только на этой сложности (нет — на любой),
--   ann = объявление: nil — как в настройках, "instant", "combat", "off"; whisper = шепнуть игроку причину,
--   quick = быстрая кнопка (мини-панель и меню «минус цели»).
-- Автоправило (Data\Detectors.lua): auto = ключ, label = свой текст (пусто — шаблон с числами),
--   params = числа РЛа, instant = находку сразу ставить игроку (иначе — во вкладку «На проверку»).
-- Автоправила есть в каждом своде: их нельзя удалить, только выключить.

local _, ns = ...

local tinsert, tremove = table.insert, table.remove
local pairs, ipairs, type, tonumber, tostring = pairs, ipairs, type, tonumber, tostring

local EXPORT_PREFIX = "RM1:"
local AUTO_DEFAULT = -10

ns.ROLE_KEYS = {"tank", "healer", "melee", "caster"}
local ROLE_SET = {tank = true, healer = true, melee = true, caster = true}
local REP = {fight = true, raid = true}
local DIFF = {hc = true, nm = true}
local ANN = {instant = true, combat = true, off = true}

local function NewRuleId(rs)
	rs.nextId = (rs.nextId or 0) + 1
	return "r" .. rs.nextId
end

local function CopyParams(params)
	if type(params) ~= "table" then return end
	local out
	for k, v in pairs(params) do
		if type(k) == "string" and tonumber(v) then
			out = out or {}
			out[k] = tonumber(v)
		end
	end
	return out
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

local function Str(v, limit)
	if type(v) ~= "string" then return end
	v = strtrim(v)
	if v == "" then return end
	return v:sub(1, limit or 150)
end

-- настройки правила из таблицы opts (правило, копия, импорт)
local function ApplyOpts(r, opts)
	r.kick = opts.kick and true or nil
	r.who = opts.who and true or nil
	r.off = opts.off and true or nil
	r.chat = Str(opts.chat, 120)
	r.note = Str(opts.note, 250)
	r.rep = REP[opts.rep or ""] and opts.rep or nil
	r.step = tonumber(opts.step)
	if r.step == 0 then r.step = nil end
	r.roles = CopyRoles(opts.roles)
	r.diff = DIFF[opts.diff or ""] and opts.diff or nil
	r.ann = ANN[opts.ann or ""] and opts.ann or nil
	r.whisper = opts.whisper and true or nil
	r.quick = opts.quick and true or nil
end

-- opts — настройки (см. начало файла); auto — ключ автоправила
local function MakeRule(rs, boss, text, value, opts)
	local r = {id = NewRuleId(rs), boss = boss, text = text, value = value or 0}
	if opts then
		ApplyOpts(r, opts)
		local d = ns.Detector(opts.auto)
		if d then
			r.auto, r.boss, r.text = d.key, d.boss, d.text
			r.label = Str(opts.label, 150)
			r.params = CopyParams(opts.params)
			r.instant = opts.instant and true or nil
			r.who = nil
		end
	end
	return r
end

function ns.AutoRule(rs, key)
	for _, r in ipairs(rs.rules) do
		if r.auto == key then return r end
	end
end

-- каждое автоправило — в своде; нового — в начало раздела, со значением по умолчанию
function ns.EnsureAutoRules(rs)
	for _, d in ipairs(ns.DETECTORS) do
		if not ns.AutoRule(rs, d.key) then
			local r = MakeRule(rs, d.boss, d.text, d.value or AUTO_DEFAULT, {auto = d.key})
			local at = #rs.rules + 1
			for i, x in ipairs(rs.rules) do
				if x.boss == d.boss then at = i break end
			end
			tinsert(rs.rules, at, r)
		end
	end
end

-- старые своды: «Общее» и «Плюсы» стали одним разделом «Общие», бонус Профа — у Профа
local function Migrate(rs)
	for _, r in ipairs(rs.rules) do
		if r.boss == "bonus" then r.boss = r.auto == "pp_bonus" and "putricide" or "general" end
		local d = ns.Detector(r.auto)
		if d then r.boss = d.boss end
		if not ns.Section(r.boss) then r.boss = "general" end
	end
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
	local rs = {id = "s" .. db.nextRulesetId, name = UniqueName(name), rules = {}}
	tinsert(db.rulesets, rs)
	return rs
end

-- новый свод: только встроенные автоправила, свои правила РЛ добавляет сам
function ns.EmptyRuleset(name)
	local rs = ns.NewRuleset(name or "Мой свод")
	ns.EnsureAutoRules(rs)
	return rs
end

function ns.CopyRuleset(src)
	local rs = ns.NewRuleset(src.name)
	for _, r in ipairs(src.rules) do
		tinsert(rs.rules, MakeRule(rs, r.boss, r.text, r.value, r))
	end
	ns.EnsureAutoRules(rs)
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
	return r
end

function ns.DuplicateRule(rs, rule)
	if rule.auto then return end
	local r = MakeRule(rs, rule.boss, rule.text .. " (копия)", rule.value, rule)
	for i, x in ipairs(rs.rules) do
		if x == rule then tinsert(rs.rules, i + 1, r) return r end
	end
	tinsert(rs.rules, r)
	return r
end

-- автоправило не удаляется (его можно выключить)
function ns.RemoveRule(rs, rule)
	if rule.auto then return end
	for i, r in ipairs(rs.rules) do
		if r == rule then tremove(rs.rules, i) return end
	end
end

-- перенос в другой раздел (у автоправила раздел свой, не меняется)
function ns.SetRuleSection(rule, section)
	if rule.auto or not ns.Section(section) then return end
	rule.boss = section
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
-- можно ли поставить правило

-- сложность рейда сейчас: "hc", "nm" или nil (не в рейде, тестовый рейд)
function ns.Difficulty()
	local s = ns.Session()
	if s and s.test then return end
	local _, kind = IsInInstance()
	if kind ~= "raid" then return end
	local d = GetInstanceDifficulty()
	return (d == 3 or d == 4) and "hc" or "nm"
end

function ns.RuleDiffOk(rule)
	if not rule.diff then return true end
	local d = ns.Difficulty()
	return not d or d == rule.diff
end

function ns.RuleRoleOk(rule, name)
	if not rule.roles then return true end
	local role = ns.PlayerRole(name)
	return not role or rule.roles[role] or false
end

-- текст в чат: свой или текст правила без пояснения в скобках
function ns.ChatText(rule)
	if rule.chat and rule.chat ~= "" then return rule.chat end
	return ns.ShortText(ns.RuleText(rule))
end

-------------------------------------------------------------------------------
-- обмен строкой: RM1: + сжатые данные (AceSerializer + LibDeflate)

local function Libs()
	return LibStub("AceSerializer-3.0", true), LibStub("LibDeflate", true)
end

local function RolesString(roles)
	if not roles then return end
	local parts = {}
	for _, k in ipairs(ns.ROLE_KEYS) do
		if roles[k] then tinsert(parts, k) end
	end
	return table.concat(parts, ",")
end

local function RolesFromString(str)
	if type(str) ~= "string" then return end
	local out = {}
	for k in str:gmatch("[^,]+") do out[k] = true end
	return out
end

function ns.ExportRuleset(rs)
	local AS, LD = Libs()
	if not AS or not LD then return "" end
	local data = {v = 2, name = rs.name, rules = {}}
	for _, r in ipairs(rs.rules) do
		tinsert(data.rules, {
			b = r.boss, t = r.text, v = r.value, k = r.kick and 1 or nil, w = r.who and 1 or nil,
			a = r.auto, p = r.params, o = r.off and 1 or nil, i = r.instant and 1 or nil,
			l = r.label, c = r.chat, n = r.note, r = r.rep, s = r.step, ro = RolesString(r.roles),
			d = r.diff, an = r.ann, wh = r.whisper and 1 or nil, q = r.quick and 1 or nil,
		})
	end
	return EXPORT_PREFIX .. LD:EncodeForPrint(LD:CompressDeflate(AS:Serialize(data)))
end

function ns.ImportRuleset(str)
	local AS, LD = Libs()
	if not AS or not LD then return nil, "нет библиотек AceSerializer/LibDeflate" end
	str = (tostring(str or ""):gsub("%s", ""))
	if str:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then return nil, "это не строка RaidMinus (должна начинаться с RM1:)" end
	local raw = LD:DecodeForPrint(str:sub(#EXPORT_PREFIX + 1))
	local text = raw and LD:DecompressDeflate(raw)
	if not text then return nil, "строка повреждена (скопирована не целиком?)" end
	local ok, data = AS:Deserialize(text)
	if not ok or type(data) ~= "table" or type(data.rules) ~= "table" then return nil, "строка повреждена" end

	local rs = ns.NewRuleset(type(data.name) == "string" and data.name:sub(1, 60) or "Импорт")
	local seen = {}
	for _, r in ipairs(data.rules) do
		local sec = type(r) == "table" and (r.b == "bonus" and "general" or r.b)
		if sec and ns.Section(sec) and type(r.t) == "string" then
			local auto = ns.Detector(r.a) and not seen[r.a] and r.a or nil
			if auto then seen[auto] = true end
			if auto or not r.a then
				tinsert(rs.rules, MakeRule(rs, sec, r.t:sub(1, 150), tonumber(r.v) or 0, {
					kick = r.k, who = r.w, auto = auto, params = r.p, off = r.o, instant = r.i,
					label = r.l, chat = r.c, note = r.n, rep = r.r, step = r.s, roles = RolesFromString(r.ro),
					diff = r.d, ann = r.an, whisper = r.wh, quick = r.q,
				}))
			end
		end
	end
	ns.EnsureAutoRules(rs)
	return rs
end

ns.OnLoad(function()
	for _, rs in ipairs(ns.DB.rulesets) do
		Migrate(rs)
		ns.EnsureAutoRules(rs) -- своды, созданные до появления автоправил, получают их
	end
	ns.ActiveRuleset() -- при первом запуске создаёт пустой свод со встроенными автоправилами
end)
