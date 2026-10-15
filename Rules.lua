-- Своды правил: минусы и плюсы по разделам (боссы, «Общее», «Плюсы»).
-- Правила — данные: РЛ правит их в игре (Options.lua) и делится строкой (экспорт/импорт).
-- Правило: {id, boss = раздел, text, value, kick = пометка «на кик», off = выключено,
--   who = видно, кто нарушил (оранжевая метка; иначе белая — только вручную),
--   auto = ключ автоправила (Data/Detectors.lua; красная метка), params = числа РЛа,
--   instant = находку автоправила сразу ставить игроку (без вкладки «На проверку»)}.
-- Автоправила есть в каждом своде: их нельзя удалить, только выключить.

local _, ns = ...

local tinsert, tremove = table.insert, table.remove
local pairs, ipairs, type, tonumber = pairs, ipairs, type, tonumber

local EXPORT_PREFIX = "RM1:"
local AUTO_DEFAULT = -10

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

-- opts: kick, who, off, auto (ключ автоправила), params, instant
local function MakeRule(rs, boss, text, value, opts)
	local r = {id = NewRuleId(rs), boss = boss, text = text, value = value or 0}
	if opts then
		r.kick = opts.kick and true or nil
		r.who = opts.who and true or nil
		r.off = opts.off and true or nil
		local d = ns.Detector(opts.auto)
		if d then
			r.auto, r.boss, r.text = d.key, d.boss, d.text
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

-- правила раздела по порядку
function ns.RulesFor(rs, section)
	local out = {}
	for _, r in ipairs(rs.rules) do
		if r.boss == section then tinsert(out, r) end
	end
	return out
end

function ns.RuleById(rs, id)
	for _, r in ipairs(rs.rules) do
		if r.id == id then return r end
	end
end

function ns.AddRule(rs, section)
	local r = MakeRule(rs, section, "Новое правило", -10)
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

-- сдвиг внутри раздела: dir = -1 выше, 1 ниже
function ns.MoveRule(rs, rule, dir)
	local list = rs.rules
	local i
	for k, r in ipairs(list) do
		if r == rule then i = k break end
	end
	if not i then return end
	local j = i + dir
	while list[j] and list[j].boss ~= rule.boss do j = j + dir end
	if list[j] then list[i], list[j] = list[j], list[i] end
end

-------------------------------------------------------------------------------
-- обмен строкой: RM1: + сжатые данные (AceSerializer + LibDeflate)

local function Libs()
	return LibStub("AceSerializer-3.0", true), LibStub("LibDeflate", true)
end

function ns.ExportRuleset(rs)
	local AS, LD = Libs()
	if not AS or not LD then return "" end
	local data = {v = 1, name = rs.name, rules = {}}
	for _, r in ipairs(rs.rules) do
		tinsert(data.rules, {
			b = r.boss, t = r.text, v = r.value, k = r.kick and 1 or nil, w = r.who and 1 or nil,
			a = r.auto, p = r.params, o = r.off and 1 or nil, i = r.instant and 1 or nil,
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
		if type(r) == "table" and ns.Section(r.b) and type(r.t) == "string" then
			local auto = ns.Detector(r.a) and not seen[r.a] and r.a or nil
			if auto then seen[auto] = true end
			if auto or not r.a then
				tinsert(rs.rules, MakeRule(rs, r.b, r.t:sub(1, 150), tonumber(r.v) or 0,
					{kick = r.k, who = r.w, auto = auto, params = r.p, off = r.o, instant = r.i}))
			end
		end
	end
	ns.EnsureAutoRules(rs)
	return rs
end

ns.OnLoad(function()
	-- своды, созданные до появления автоправил, получают их
	for _, rs in ipairs(ns.DB.rulesets) do ns.EnsureAutoRules(rs) end
	ns.ActiveRuleset() -- при первом запуске создаёт пустой свод со встроенными автоправилами
end)
