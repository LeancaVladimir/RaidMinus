-- Триггеры правил — как в WeakAuras, но внутри RaidMinus. У правила свода может быть rule.trig
-- (Rules.lua): тип, поля типа и условия. Включённый триггер сам ставит минус (или плюс) виноватому —
-- сразу, без проверки; снять — во вкладке «Журнал».
-- Работают в бою с боссом (от пула DBM до убийства или вайпа): правила раздела этого босса и «Общие».
--
-- Типы:
--   fail   — неудача из LibFail (её ведёт Skada): trig.fail = ключ;
--   combat — событие журнала боя: event, spell (номера или названия), from (NPC ID или имя источника),
--            who = dst | src (кто виноват), amount (урон от), streak (держался под уроном дольше N сек);
--   death  — смерть игрока рейда: последний удар spell, from; who = dst (умерший) | src (убийца);
--   aura   — аура на игроке: spell, stacks (от N стаков), dur (держится дольше N сек);
--   yell   — крик / эмоция / шёпот босса содержит text: виноват названный в нём игрок;
--   pull   — DBM: пул раньше таймера на early сек (Pull.lua): виноват первый, кто тронул босса;
--   skada  — после убийства, по Skada: metric = dps | damage | target (урон по цели target), op = lt | ge, num;
--   code   — свой код: events (через запятую, плюс RM_START / RM_END / RM_SKADA) и
--            code = function(event, ...) return "Имя", "что было" end; в коде есть RM (помощники) и fight.
-- Условия: count — с N-го раза за бой; per — each (каждый раз, но тому же игроку не чаще раза в 5 сек),
--   fight (раз за бой, по умолчанию), raid (раз за рейд); diff — сложность; roles — роль виновного.

local _, ns = ...

local format, tinsert, tconcat = string.format, table.insert, table.concat
local band, floor = bit.band, math.floor
local pairs, ipairs, tonumber, tostring, type, select = pairs, ipairs, tonumber, tostring, type, select

local EACH_GAP = 5       -- сек: «каждый раз» тому же игроку — не чаще
local STREAK_GAP = 2.1   -- сек: удары реже — серия прервалась
local WAIT_SKADA = 5     -- сек после убийства: Skada могла ещё не закрыть бой
local SPELL_LOG_LIMIT = 400

ns.COMBAT_EVENTS = {
	{key = "damage", name = "Урон", who = "dst",
		list = {"SWING_DAMAGE", "RANGE_DAMAGE", "SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE"}},
	{key = "hit", name = "Попадание (урон или промах)", who = "dst",
		list = {"SWING_DAMAGE", "RANGE_DAMAGE", "SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE",
			"SWING_MISSED", "RANGE_MISSED", "SPELL_MISSED", "SPELL_PERIODIC_MISSED"}},
	{key = "aura", name = "Наложена аура", who = "dst", list = {"SPELL_AURA_APPLIED", "SPELL_AURA_APPLIED_DOSE"}},
	{key = "cast", name = "Применение заклинания", who = "src", list = {"SPELL_CAST_SUCCESS"}},
	{key = "start", name = "Начало произнесения", who = "src", list = {"SPELL_CAST_START"}},
	{key = "summon", name = "Призыв", who = "src", list = {"SPELL_SUMMON"}},
	{key = "interrupt", name = "Прерывание", who = "src", list = {"SPELL_INTERRUPT"}},
	{key = "dispel", name = "Рассеивание", who = "src", list = {"SPELL_DISPEL"}},
}
local combatByKey = {}
for _, c in ipairs(ns.COMBAT_EVENTS) do combatByKey[c.key] = c end
function ns.CombatEvent(key) return combatByKey[key or ""] end

-- события с уроном: где сумма и перебор (смертельный удар — overkill > 0)
local DAMAGE = {
	SWING_DAMAGE = 1, RANGE_DAMAGE = 4, SPELL_DAMAGE = 4, SPELL_PERIODIC_DAMAGE = 4, DAMAGE_SHIELD = 4,
	ENVIRONMENTAL_DAMAGE = 2,
}
local AURA = {SPELL_AURA_APPLIED = true, SPELL_AURA_APPLIED_DOSE = true, SPELL_AURA_REMOVED = true, SPELL_AURA_REMOVED_DOSE = true}
local YELL_EVENTS = {"CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_RAID_BOSS_WHISPER", "CHAT_MSG_MONSTER_WHISPER"}
local NPC_FLAG = COMBATLOG_OBJECT_TYPE_NPC or 0x800
local PET_FLAGS = (COMBATLOG_OBJECT_TYPE_PET or 0x1000) + (COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x2000)

local fight     -- текущий (или последний) бой: {boss, pull, start, over, counts, last, streak, auras}
local index     -- включённые правила этого боя по типам
local dirty = true
local compiled = setmetatable({}, {__mode = "k"}) -- правило -> разобранный триггер
local info = setmetatable({}, {__mode = "k"})     -- правило -> {last = {t, name, detail}, err}

function ns.TriggersDirty() dirty = true end

-- последнее срабатывание и ошибка — для редактора
function ns.TrigInfo(rule) return info[rule] end

local function Info(rule)
	local x = info[rule]
	if not x then
		x = {}
		info[rule] = x
	end
	return x
end

-------------------------------------------------------------------------------
-- описание триггера одной строкой (подсказки, вкладка «Правила»)

local PER_TEXT = {each = "каждый раз", fight = "раз за бой", raid = "раз за рейд"}
local ROLE_SHORT = {tank = "танк", healer = "хил", melee = "мдд", caster = "рдд"}

local function Short(s, n)
	s = tostring(s or "")
	if #s > n then
		local cut = n
		while cut > 0 and s:byte(cut + 1) and s:byte(cut + 1) >= 128 and s:byte(cut + 1) < 192 do cut = cut - 1 end
		s = s:sub(1, cut) .. "..."
	end
	return s
end

function ns.TrigSummary(rule)
	local t = rule and rule.trig
	if not t then return "нет — правило ставится только вручную" end
	local what
	if t.type == "fail" then
		what = t.fail and ns.FailName(t.fail) or "неудача не выбрана"
	elseif t.type == "combat" then
		local ce = combatByKey[t.event or "damage"]
		what = (ce and ce.name or "?") .. (t.spell and (": " .. Short(t.spell, 40)) or "")
			.. (t.streak and format(", дольше %s сек", t.streak) or "")
	elseif t.type == "death" then
		what = (t.who == "src" and "виноват убийца" or "умер") .. (t.spell and (" от " .. Short(t.spell, 40)) or "")
	elseif t.type == "aura" then
		what = Short(t.spell or "аура не указана", 40) .. (t.stacks and format(", от %s стаков", t.stacks) or "")
			.. (t.dur and format(", дольше %s сек", t.dur) or "")
	elseif t.type == "yell" then
		what = "«" .. Short(t.text or "", 40) .. "»"
	elseif t.type == "pull" then
		what = format("раньше на %s сек", t.early or 1)
	elseif t.type == "skada" then
		local m = {dps = "ДПС", damage = "урон", target = "урон по цели"}
		what = format("%s %s %s", m[t.metric or "dps"] or "ДПС", t.op == "ge" and ">=" or "<", ns.ShortNumber(t.num or 0))
	elseif t.type == "code" then
		what = Short(t.events or "события не указаны", 40)
	end
	local cond = {}
	if (t.count or 1) > 1 then tinsert(cond, format("с %d-го раза", t.count)) end
	tinsert(cond, PER_TEXT[t.per or "fight"])
	if t.diff then tinsert(cond, t.diff == "hc" and "гер." or "об.") end
	if t.roles then
		local r = {}
		for _, k in ipairs(ns.ROLE_KEYS) do
			if t.roles[k] then tinsert(r, ROLE_SHORT[k]) end
		end
		tinsert(cond, tconcat(r, "/"))
	end
	return format("%s%s: %s (%s)", t.on and "" or "|cff9d9d9d[выкл]|r ", ns.TrigTypeName(t.type), tostring(what), tconcat(cond, ", "))
end

-------------------------------------------------------------------------------
-- помощники: кто есть кто

-- NPC ID из GUID 3.3.5: 0xF130 00 954E 001234 -> 0x954E
function ns.NpcId(guid)
	if type(guid) ~= "string" or guid:sub(1, 5) ~= "0xF13" then return end
	return tonumber(guid:sub(9, 12), 16)
end
local NpcId = ns.NpcId

function ns.UnitByName(name)
	if UnitName("player") == name then return "player" end
	for i = 1, GetNumRaidMembers() do
		if UnitName("raid" .. i) == name then return "raid" .. i end
	end
	for i = 1, GetNumPartyMembers() do
		if UnitName("party" .. i) == name then return "party" .. i end
	end
end

local petOwner = {} -- GUID питомца -> хозяин

function ns.RefreshPets()
	wipe(petOwner)
	local function add(unit, owner)
		local guid = UnitGUID(unit)
		if guid then petOwner[guid] = UnitName(owner) end
	end
	add("pet", "player")
	for i = 1, GetNumRaidMembers() do add("raid" .. i .. "pet", "raid" .. i) end
	for i = 1, GetNumPartyMembers() do add("party" .. i .. "pet", "party" .. i) end
end

function ns.PetOwner(guid) return guid and petOwner[guid] end

-- кто сделал: игрок рейда или хозяин питомца (второе значение — имя питомца)
function ns.Culprit(srcGUID, srcName, srcFlags)
	if srcName and ns.IsHere(srcName) then return srcName end
	if band(srcFlags or 0, PET_FLAGS) > 0 then
		local owner = petOwner[srcGUID or ""]
		if owner and ns.IsHere(owner) then return owner, srcName end
	end
end

-------------------------------------------------------------------------------
-- разбор полей триггера

-- «69055, 70814, Мстительный взрыв» -> {ids, names, empty}
local function ParseList(str)
	local out = {ids = {}, names = {}, empty = true}
	for part in tostring(str or ""):gmatch("[^,;]+") do
		part = strtrim(part)
		if part ~= "" then
			out.empty = false
			local id = tonumber(part)
			if id then out.ids[id] = true else out.names[ns.Lower(part)] = true end
		end
	end
	return out
end
ns.ParseTrigList = ParseList

local function Matches(list, id, name)
	if list.empty then return true end
	if id and list.ids[id] then return true end
	return name ~= nil and list.names[ns.Lower(name)] or false
end

-- источник: NPC ID из GUID или имя
local function FromMatches(list, guid, name)
	if list.empty then return true end
	local npc = NpcId(guid)
	if npc and list.ids[npc] then return true end
	return name ~= nil and list.names[ns.Lower(name)] or false
end

-------------------------------------------------------------------------------
-- срабатывание и условия

-- rule сработал на игрока name; opts.test — тестовый рейд (без счёта «с N-го раза»)
local function Fire(rule, name, detail, opts)
	local s = ns.Session()
	local t = rule.trig
	if not s or not t or not name or not s.roster[name] then return end
	local f = fight or {counts = {}, last = {}}
	local ctx = {boss = f.boss or s.boss}
	ctx.pull = f.pull or (ctx.boss and s.pulls[ctx.boss])
	if t.diff then
		local d = ns.Difficulty()
		if d and d ~= t.diff then return end
	end
	if t.roles then
		local role = ns.PlayerRole(name)
		if role and not t.roles[role] then return end
	end
	if (t.count or 1) > 1 and not (opts and opts.test) then
		f.counts[rule] = f.counts[rule] or {}
		local n = (f.counts[rule][name] or 0) + 1
		f.counts[rule][name] = n
		if n < t.count then return end
	end
	local per = t.per or "fight"
	if per == "raid" and ns.RuleCount(name, rule.id) > 0 then return end
	if per == "fight" and ns.RuleCount(name, rule.id, ctx) > 0 then return end
	if per == "each" then
		f.last[rule] = f.last[rule] or {}
		local prev = f.last[rule][name]
		if prev and GetTime() - prev < EACH_GAP then return end
		f.last[rule][name] = GetTime()
	end
	ns.AddEvents({name}, rule, {detail = detail, boss = ctx.boss, pull = ctx.pull})
	Info(rule).last = {t = time(), name = name, detail = detail}
	local p = s.roster[name]
	ns.Print(format("триггер: %s %s (%s)%s", ns.ColorName(name, p and p.class), ns.ValueColor(rule.value),
		ns.ShortText(rule.text), detail and ("|cff9d9d9d — " .. detail .. "|r") or ""))
end
ns.FireTrigger = Fire

-------------------------------------------------------------------------------
-- свой код

local API = {}

function API.Role(name) return (ns.PlayerRole(name)) end
function API.Class(name)
	local s = ns.Session()
	local p = s and s.roster[name or ""]
	return p and p.class
end
function API.InRaid(name) return ns.IsHere(name) end
function API.Players()
	local out = {}
	for name in pairs(ns.here) do tinsert(out, name) end
	table.sort(out)
	return out
end
API.NpcId = NpcId
API.Unit = ns.UnitByName
API.Owner = ns.PetOwner
API.Time = GetTime
function API.FightTime() return fight and (GetTime() - fight.start) or 0 end
function API.Boss() return fight and fight.boss end
function API.Short(n) return ns.ShortNumber(n) end
function API.Test()
	local s = ns.Session()
	return s and s.test or false
end
-- RM.Is(spellId, 1, 2, 3) — одно из
function API.Is(x, ...)
	for i = 1, select("#", ...) do
		if x == select(i, ...) then return true end
	end
	return false
end

-- Skada: урон игрока (с поглощённым — как в настройке Skada), время в бою, урон по целям, враги по NPC ID
local function SkadaAbs()
	local Skada = _G.Skada
	return Skada and Skada.profile and Skada.profile.absdamage
end
function API.SkadaDamage(actor)
	if not actor then return 0 end
	return (SkadaAbs() and actor.totaldamage or actor.damage) or 0
end
function API.SkadaTime(set, actor)
	local Skada = _G.Skada
	return Skada and Skada.GetActiveTime and Skada:GetActiveTime(set, actor) or 1
end
function API.SkadaTargets(actor)
	local out, abs = {}, SkadaAbs()
	for _, spell in pairs(actor and actor.damagespells or {}) do
		for tname, x in pairs(spell.targets or {}) do
			local amount = abs and x.total or x.amount
			if amount and amount > 0 then out[tname] = (out[tname] or 0) + amount end
		end
	end
	return out
end
function API.SkadaEnemies(set, ...)
	local ids = {}
	for i = 1, select("#", ...) do ids[select(i, ...)] = true end
	local out = {}
	for name, actor in pairs(set and set.actors or {}) do
		if actor.enemy and not actor.fake and ids[NpcId(actor.id) or 0] then out[name] = true end
	end
	return out
end
-- игроки рейда в бою Skada: {{name, actor}}
function API.SkadaPlayers(set)
	local out = {}
	for name, actor in pairs(set and set.actors or {}) do
		if not actor.enemy and ns.IsHere(name) then tinsert(out, {name = name, actor = actor}) end
	end
	return out
end

local function CodeError(rule, c, err)
	c.broken = true
	Info(rule).err = tostring(err)
	ns.Print(format("|cffff5050ошибка в коде правила «%s»:|r %s — до конца боя правило молчит.", ns.ShortText(rule.text), tostring(err)))
end

-- компиляция: «local RM, fight = ...; return <код>» -> функция (без setfenv: RM и fight — обычные переменные)
local function CompileCode(rule, c)
	local t = rule.trig
	c.fight = {}
	c.rm = setmetatable({
		Fire = function(name, detail) Fire(rule, name, detail) end,
		After = function(sec, fn)
			local f = fight
			ns.After(tonumber(sec) or 0, function()
				if fight ~= f or not f or f.over then return end
				local ok, err = pcall(fn)
				if not ok then CodeError(rule, c, err) end
			end)
		end,
	}, {__index = API})
	local loader = loadstring or load
	local chunk, err = loader("local RM, fight = ...; return " .. tostring(t.code or ""), "=" .. ns.ShortText(rule.text))
	if not chunk then
		c.err = err
		return
	end
	local ok, fn = pcall(chunk, c.rm, c.fight)
	if not ok then
		c.err = fn
	elseif type(fn) ~= "function" then
		c.err = "код должен быть функцией: function(event, ...) ... end"
	else
		c.fn = fn
	end
end

-- проверка кода из редактора: nil — всё в порядке, иначе текст ошибки
function ns.CheckTriggerCode(code)
	local loader = loadstring or load
	local chunk, err = loader("local RM, fight = ...; return " .. tostring(code or ""), "=код")
	if not chunk then return err end
	local ok, fn = pcall(chunk, API, {})
	if not ok then return fn end
	if type(fn) ~= "function" then return "код должен быть функцией: function(event, ...) ... end" end
end

local function RunCode(rule, c, event, ...)
	if c.broken or not c.fn then return end
	local ok, name, detail = pcall(c.fn, event, ...)
	if not ok then
		CodeError(rule, c, name)
	elseif name then
		Fire(rule, name, detail)
	end
end

-- события WoW для своего кода (кроме журнала боя и RM_*): свой кадр, регистрируем по требованию
local codeFrame = CreateFrame("Frame")
local codeEvents = {}

local function RegisterCodeEvent(event)
	if codeEvents[event] ~= nil or event:sub(1, 3) == "RM_" or event == "COMBAT_LOG_EVENT_UNFILTERED" then return end
	codeEvents[event] = pcall(codeFrame.RegisterEvent, codeFrame, event) and true or false
end

-------------------------------------------------------------------------------
-- включённые правила боя

local function Compile(rule)
	local t = rule.trig
	local key = tconcat({t.type or "", t.event or "", t.spell or "", t.from or "", t.events or "", t.code or "", t.fail or "", t.text or "", t.target or ""}, "\001")
	local c = compiled[rule]
	if c and c.key == key then return c end
	c = {key = key}
	c.spells = ParseList(t.spell)
	c.from = ParseList(t.from)
	c.target = ParseList(t.target)
	if t.type == "code" then
		c.events = {}
		for ev in tostring(t.events or ""):gmatch("[%w_]+") do
			c.events[ev] = true
			RegisterCodeEvent(ev)
		end
		CompileCode(rule, c)
		Info(rule).err = c.err
	end
	compiled[rule] = c
	return c
end

local function Add(map, key, rule)
	local list = map[key]
	if not list then
		list = {}
		map[key] = list
	end
	tinsert(list, rule)
end

local function Rebuild()
	dirty = false
	index = {fail = {}, combat = {}, death = {}, aura = {}, yell = {}, pull = {}, skada = {}, code = {}}
	if not fight or not ns.DB then return end
	for _, rule in ipairs(ns.ActiveRuleset().rules) do
		local t = rule.trig
		if t and t.on and (rule.boss == fight.boss or rule.boss == "general") then
			local c = Compile(rule)
			if t.type == "fail" then
				if t.fail then Add(index.fail, t.fail, rule) end
			elseif t.type == "combat" then
				local ce = combatByKey[t.event or "damage"]
				for _, sub in ipairs(ce and ce.list or {}) do Add(index.combat, sub, rule) end
			elseif t.type == "code" then
				for ev in pairs(c.events) do Add(index.code, ev, rule) end
			elseif index[t.type] then
				tinsert(index[t.type], rule)
			end
		end
	end
end

local function Index()
	if dirty or not index then Rebuild() end
	return index
end

-- свой код получает событие (в тестовом рейде журнала боя нет — код молчит)
local function Dispatch(event, ...)
	local s = ns.Session()
	if not s or s.test or not fight then return end
	local list = Index().code[event]
	if not list then return end
	for _, rule in ipairs(list) do RunCode(rule, Compile(rule), event, ...) end
end

codeFrame:SetScript("OnEvent", function(_, event, ...)
	if fight and not fight.over then Dispatch(event, ...) end
end)

-------------------------------------------------------------------------------
-- журнал боя

local function RecordSpell(boss, spellId, spellName)
	local log = ns.DB.spellLog
	if not log then
		log = {}
		ns.DB.spellLog = log
	end
	local b = log[boss]
	if not b then
		b = {n = 0}
		log[boss] = b
	end
	if not b[spellId] and b.n < SPELL_LOG_LIMIT then
		b[spellId] = spellName
		b.n = b.n + 1
	end
end

-- заклинания, замеченные у врагов в бою с боссом (для поля «Заклинание»): {{id, name}}
function ns.SeenSpells(boss)
	local out = {}
	local b = ns.DB.spellLog and ns.DB.spellLog[boss]
	for id, name in pairs(b or {}) do
		if type(id) == "number" then tinsert(out, {id = id, name = name}) end
	end
	table.sort(out, function(a, b2) return a.name == b2.name and a.id < b2.id or tostring(a.name) < tostring(b2.name) end)
	return out
end

local function Combat(rule, sub, srcGUID, srcName, srcFlags, dstGUID, dstName, ...)
	local t, c = rule.trig, Compile(rule)
	local spellId, spellName
	if sub:sub(1, 5) ~= "SWING" then spellId, spellName = ... end
	if not Matches(c.spells, spellId, spellName) then return end
	if not FromMatches(c.from, srcGUID, srcName) then return end
	local pos = DAMAGE[sub]
	local amount = pos and select(pos, ...)
	if t.amount and (not amount or amount < t.amount) then return end
	local ce = combatByKey[t.event or "damage"]
	local who = t.who or (ce and ce.who) or "dst"
	local name
	if who == "src" then
		name = ns.Culprit(srcGUID, srcName, srcFlags)
	elseif dstName and ns.IsHere(dstName) then
		name = dstName
	end
	if not name then return end
	local what = spellName or "ближний бой"
	if t.streak then
		local now = GetTime()
		fight.streak[rule] = fight.streak[rule] or {}
		local st = fight.streak[rule][name]
		if not st or now - st.last > STREAK_GAP then
			st = {start = now, last = now}
			fight.streak[rule][name] = st
		else
			st.last = now
		end
		if st.last - st.start < t.streak then return end
		Fire(rule, name, format("%s: %d сек подряд", what, floor(st.last - st.start + 0.5)))
		return
	end
	local detail = (ce and ce.name or sub) .. ": " .. what
	if who == "src" and dstName then detail = detail .. " → " .. dstName end
	if amount then detail = detail .. " (" .. ns.ShortNumber(amount) .. ")" end
	Fire(rule, name, detail)
end

local function Death(sub, srcGUID, srcName, srcFlags, dstName, ...)
	local list = Index().death
	if #list == 0 then return end
	local spellId, spellName
	if sub == "ENVIRONMENTAL_DAMAGE" then
		spellName = ...
	elseif sub:sub(1, 5) ~= "SWING" then
		spellId, spellName = ...
	end
	for _, rule in ipairs(list) do
		local t, c = rule.trig, Compile(rule)
		if Matches(c.spells, spellId, spellName) and FromMatches(c.from, srcGUID, srcName) then
			local what = spellName or "ближний бой"
			if t.who == "src" then
				local killer = ns.Culprit(srcGUID, srcName, srcFlags)
				if killer and killer ~= dstName then Fire(rule, killer, format("убил %s (%s)", dstName, what)) end
			else
				Fire(rule, dstName, "умер от: " .. what)
			end
		end
	end
end

local function AuraCheck(rule, name, spellId, spellName, sub, amount)
	local t = rule.trig
	local key = name .. ":" .. tostring(spellId)
	fight.auras[rule] = fight.auras[rule] or {}
	local state = fight.auras[rule]
	if sub == "SPELL_AURA_REMOVED" then
		state[key] = nil
		return
	end
	local stacks = (sub == "SPELL_AURA_APPLIED") and 1 or (tonumber(amount) or 1)
	local x = state[key]
	if not x or sub == "SPELL_AURA_APPLIED" then
		x = {t = GetTime(), stacks = stacks}
		state[key] = x
	else
		x.stacks = stacks
	end
	if sub == "SPELL_AURA_REMOVED_DOSE" then return end
	local need = t.stacks or 1
	if t.dur then
		if sub ~= "SPELL_AURA_APPLIED" then return end
		local f = fight
		ns.After(t.dur, function()
			if fight ~= f or f.over or state[key] ~= x then return end
			if x.stacks >= need then
				Fire(rule, name, format("%s: дольше %d сек%s", tostring(spellName), t.dur, need > 1 and (", стаков " .. x.stacks) or ""))
			end
		end)
		return
	end
	if stacks >= need and (need > 1 or sub == "SPELL_AURA_APPLIED") then
		Fire(rule, name, need > 1 and format("%s: стаков %d", tostring(spellName), stacks) or tostring(spellName))
	end
end

ns.On("COMBAT_LOG_EVENT_UNFILTERED", function(timestamp, sub, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
	if not fight or fight.over or not ns.Session() then return end
	local idx = Index()

	local spellId = ...
	if band(srcFlags or 0, NPC_FLAG) > 0 and type(spellId) == "number" and sub:sub(1, 5) == "SPELL" then
		RecordSpell(fight.boss, spellId, (select(2, ...)))
	end

	local list = idx.combat[sub]
	if list then
		for _, rule in ipairs(list) do Combat(rule, sub, srcGUID, srcName, srcFlags, dstGUID, dstName, ...) end
	end

	local pos = DAMAGE[sub]
	if pos and dstName and ns.IsHere(dstName) then
		local overkill = select(pos + 1, ...)
		if (tonumber(overkill) or 0) > 0 then Death(sub, srcGUID, srcName, srcFlags, dstName, ...) end
	end

	if AURA[sub] and #idx.aura > 0 and dstName and ns.IsHere(dstName) then
		local _, spellName, _, _, amount = ...
		for _, rule in ipairs(idx.aura) do
			if Matches(Compile(rule).spells, spellId, spellName) then AuraCheck(rule, dstName, spellId, spellName, sub, amount) end
		end
	end

	if idx.code.COMBAT_LOG_EVENT_UNFILTERED then
		Dispatch("COMBAT_LOG_EVENT_UNFILTERED", timestamp, sub, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
	end
end)

-------------------------------------------------------------------------------
-- сообщения босса: виноват названный игрок (или я — шёпот босса)

local function NamedPlayer(msg, target)
	if target and ns.IsHere(target) then return target end
	local best
	for name in pairs(ns.here) do
		if msg:find(name, 1, true) and (not best or #name > #best) then best = name end
	end
	return best
end

local function OnBossMessage(event, msg, sender, _, _, target)
	if not fight or fight.over then return end
	local list = Index().yell
	if #list == 0 then return end
	local low = ns.Lower(msg)
	for _, rule in ipairs(list) do
		local text = rule.trig.text
		if text and low:find(ns.Lower(text), 1, true) then
			local name = event == "CHAT_MSG_RAID_BOSS_WHISPER" and ns.PlayerName() or NamedPlayer(msg, target)
			if name then Fire(rule, name, tostring(sender or "босс") .. ": " .. msg) end
		end
	end
end

for _, event in ipairs(YELL_EVENTS) do
	ns.On(event, function(...) OnBossMessage(event, ...) end)
end

-------------------------------------------------------------------------------
-- неудачи LibFail (Skada)

local function OnFail(_, failname, playername)
	if not fight or fight.over or not failname or not playername then return end
	local list = Index().fail[failname]
	if not list then return end
	for _, rule in ipairs(list) do Fire(rule, playername, ns.FailName(failname)) end
end

-------------------------------------------------------------------------------
-- пул раньше таймера (Pull.lua)

function ns.TriggerPullEarly(who, early, detail)
	if not fight then return end
	for _, rule in ipairs(Index().pull) do
		if early >= (rule.trig.early or 1) then Fire(rule, who, detail) end
	end
end

-------------------------------------------------------------------------------
-- Skada после убийства

local METRIC_NAMES = {dps = "ДПС", damage = "урон", target = "урон по цели"}
ns.SKADA_METRICS = {{"dps", "ДПС"}, {"damage", "Урон"}, {"target", "Урон по цели"}}

local function SkadaCheck(rule, set)
	local t, c = rule.trig, Compile(rule)
	local num = t.num or 0
	local targets
	if t.metric == "target" then
		targets = {}
		for name in pairs(c.target.names) do targets[name] = true end
		local ids = {}
		for id in pairs(c.target.ids) do tinsert(ids, id) end
		if #ids > 0 then
			for name in pairs(API.SkadaEnemies(set, unpack(ids))) do targets[ns.Lower(name)] = true end
		end
	end
	for _, p in ipairs(API.SkadaPlayers(set)) do
		local value
		if t.metric == "target" then
			value = 0
			for tname, amount in pairs(API.SkadaTargets(p.actor)) do
				if targets[ns.Lower(tname)] then value = value + amount end
			end
		elseif t.metric == "damage" then
			value = API.SkadaDamage(p.actor)
		else
			value = API.SkadaDamage(p.actor) / math.max(1, API.SkadaTime(set, p.actor))
		end
		local hit = (t.op == "ge") and value >= num or (t.op ~= "ge" and value < num)
		if hit then
			Fire(rule, p.name, format("%s %s %s %s (Skada)", METRIC_NAMES[t.metric or "dps"] or "ДПС", ns.ShortNumber(floor(value)),
				t.op == "ge" and ">=" or "<", ns.ShortNumber(num)))
		end
	end
end

-- один раз за убийство
local function EvaluateSkada(set)
	local s = ns.Session()
	if not s or not fight or not set or not set.actors then return end
	local tag = tostring(fight.boss) .. ":" .. tostring(fight.pull or 0)
	s.metricsDone = s.metricsDone or {}
	if s.metricsDone[tag] then return end
	s.metricsDone[tag] = true
	for _, rule in ipairs(Index().skada) do SkadaCheck(rule, set) end
	Dispatch("RM_SKADA", set)
end

local skadaHandler = {}
function skadaHandler:OnSetComplete(_, set)
	local s = ns.Session()
	if not s or not fight or not fight.killed or not set or not set.gotboss then return end
	EvaluateSkada(set)
end

-- DBM сказал «убит»: если Skada не отметила убийство, берём её последний бой
local function SkadaOnKill(f)
	ns.After(WAIT_SKADA, function()
		local Skada = _G.Skada
		if not Skada or fight ~= f then return end
		local set = Skada.last or (Skada.sets and Skada.sets[1])
		if set and set.gotboss then EvaluateSkada(set) end
	end)
end

-------------------------------------------------------------------------------
-- начало и конец боя (Session.lua: ns.BossPulled / BossKilled / BossWiped)

function ns.OnFightStart(key)
	local s = ns.Session()
	fight = {boss = key, pull = s and s.pulls[key], start = GetTime(), counts = {}, last = {}, streak = {}, auras = {}}
	dirty = true
	Rebuild()
	for _, list in pairs(index.code) do
		for _, rule in ipairs(list) do
			local c = Compile(rule)
			wipe(c.fight)
			c.broken = nil
			if c.err then Info(rule).err = c.err end
		end
	end
	ns.RefreshPets()
	if ns.CheckPull then ns.CheckPull(fight, key) end
	Dispatch("RM_START", key)
end

function ns.OnFightEnd(key, how)
	if not fight or fight.over then return end
	Dispatch("RM_END", key, how)
	fight.over = true
	if how == "kill" then
		fight.killed = true
		if index and #index.skada + (index.code.RM_SKADA and 1 or 0) > 0 then SkadaOnKill(fight) end
	end
end

function ns.CurrentFight() return fight end

-- тестовый рейд: включённые триггеры босса (и иногда общие) «ловят» подходящих выдуманных игроков
function ns.TestTriggers(key)
	local s = ns.Session()
	if not s or not s.test then return 0 end
	local names = {}
	for _, name in ipairs(ns.RosterNames()) do
		if name ~= ns.PlayerName() then tinsert(names, name) end
	end
	local n = 0
	for _, rule in ipairs(ns.ActiveRuleset().rules) do
		local t = rule.trig
		if t and t.on and (rule.boss == key or (rule.boss == "general" and math.random() < 0.5)) then
			local pool = {}
			for _, name in ipairs(names) do
				local role = ns.PlayerRole(name)
				if not t.roles or not role or t.roles[role] then tinsert(pool, name) end
			end
			if #pool > 0 then
				local before = #s.events
				Fire(rule, pool[math.random(#pool)], "тест: " .. ns.TrigTypeName(t.type), {test = true})
				if #s.events > before then n = n + 1 end
			end
		end
	end
	return n
end

ns.OnLoad(function()
	local LibFail = LibStub("LibFail-1.0", true)
	if LibFail and LibFail.RegisterCallback then LibFail.RegisterCallback(ns, "AnyFail", OnFail) end
	local Skada = _G.Skada
	if Skada and Skada.RegisterCallback then Skada.RegisterCallback(skadaHandler, "Skada_SetComplete", "OnSetComplete") end
end)
