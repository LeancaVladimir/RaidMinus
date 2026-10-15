-- Автоматика по журналу боя: ловит встроенные автоправила (Data/Detectors.lua).
-- Находка → вкладка «На проверку», а если у правила включено «ставить сразу» — сразу минус игроку.
-- Работает в бою с боссом (от пула DBM до убийства или вайпа); «пул раньше таймера» — по таймеру DBM.
-- Номера способностей — по LibFail и базам 3.3.5, их надо сверить на Circle: в боях аддон записывает
-- способности боссов в RaidMinusDB.spellLog.

local _, ns = ...

local format, tinsert, tconcat = string.format, table.insert, table.concat
local band, abs, floor = bit.band, math.abs, math.floor
local pairs, ipairs, tonumber, select = pairs, ipairs, tonumber, select

local function Set(list)
	local t = {}
	for _, id in ipairs(list) do t[id] = true end
	return t
end

local SPELL = {
	saberLash = Set{69055, 70814, 71021},          -- клив Ребра
	coldflame = Set{69146, 70823, 70824, 70825},   -- холодное пламя
	dominateMind = Set{71289},                     -- МК Леди
	pungentBlight = Set{69195, 71219, 73031, 73032},
	stickyOoze = Set{69774, 69776, 69778, 71208},  -- лужа Гниломорда
	vileGas = Set{72272, 72273},                   -- газ Профессора на Гниломорде (гер.)
	unboundPlague = Set{70911, 72854, 72855, 72856},
	oozeEruption = Set{70492, 72505, 72624, 72625}, -- пельмень
	malleableGoo = Set{70853, 72458, 72873, 72874}, -- колба
	flames = Set{71393, 72789, 72790, 72791},      -- апельсин
	shadowsAura = Set{71264, 71265},               -- Рой теней на игроке
	shadowsDamage = Set{71268, 72635, 72636, 72637},
	frostBomb = Set{69845, 71053, 71054, 71055},
	frostBreath = Set{69649, 71056, 71057, 71058, 73061, 73062, 73063, 73064},
	blisteringCold = Set{70123, 71047, 71048, 71049}, -- кольцо после притяжки
	icyGrip = Set{70117},
	divineSacrifice = Set{64205},
	auraMastery = Set{31821},
	sunder = Set{7386, 7405, 8380, 11596, 11597, 25225, 47467},
}
local NPC_SHADE = 38222
local NO_SUNDER = {gunship = true, valithria = true}
local SPELL_LOG_LIMIT = 400

local fight          -- текущий бой: {boss, pull, start, fired, coldflame, mc, shades, sunders, ...}
local pullTimer      -- {ends} — идёт пулл-таймер DBM
local firstHit       -- {name, t} — кто первым ударил врага, пока шёл таймер

-------------------------------------------------------------------------------
-- общее

-- находка по автоправилу: на проверку или сразу (настройка правила)
function ns.Detected(key, player, detail)
	local rule = ns.AutoRule(ns.ActiveRuleset(), key)
	if not rule or rule.off or not player then return end
	ns.AddFinding(player, rule, detail)
end

-- один раз за пул на игрока (или на «extra» — один дух, одна лужа)
local function Fire(key, player, detail, extra)
	if not fight or not player then return end
	local tag = key .. "|" .. player .. "|" .. tostring(extra or "")
	if fight.fired[tag] then return end
	fight.fired[tag] = true
	ns.Detected(key, player, detail)
end

local function Param(key, pkey)
	local rule = ns.AutoRule(ns.ActiveRuleset(), key)
	return rule and ns.RuleParam(rule, pkey)
end

local function Role(name)
	return (ns.PlayerRole(name))
end

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

-------------------------------------------------------------------------------
-- отдельные проверки

local function Coldflame(name)
	local now = GetTime()
	local c = fight.coldflame[name]
	if not c or now - c.last > 2.1 then
		c = {start = now, last = now}
		fight.coldflame[name] = c
	else
		c.last = now
	end
	local limit = Param("mg_coldflame", "sec") or 3
	if c.last - c.start >= limit then
		Fire("mg_coldflame", name, format("в холодном пламени %d сек", floor(c.last - c.start + 0.5)))
	end
end

local function Shade(shadeGUID, name)
	Fire("ld_shade", name, "дух догнал", shadeGUID)
end

-- под МК с оружием: мили-ДД или охотник
local function WeaponCheck(name)
	local s = ns.Session()
	local p = s and s.roster[name]
	local hunter = p and p.class == "HUNTER"
	if Role(name) ~= "melee" and not hunter then return end
	local unit = ns.UnitByName(name)
	if not unit then return end
	local slots = hunter and {16, 17, 18} or {16, 17}
	for _, slot in ipairs(slots) do
		if GetInventoryItemID(unit, slot) or GetInventoryItemLink(unit, slot) then
			Fire("ld_mc_weapon", name, "под МК с оружием в руках")
			return
		end
	end
end

local function Puddle(victim)
	local pd = fight.puddle
	if not pd or (pd.ends and GetTime() > pd.ends) then return end
	if victim == pd.carrier or pd.hits[victim] then return end
	pd.hits[victim] = true
	tinsert(pd.list, victim)
	if #pd.list >= (Param("bq_puddle", "hits") or 2) then
		Fire("bq_puddle", pd.carrier, "лужа задела: " .. tconcat(pd.list, ", "), pd.start)
	end
end

local function Gas(victim)
	local g = fight.gas
	if not g or GetTime() - g.t > 2 or victim == g.target then return end
	local role = Role(victim)
	if role ~= "melee" and role ~= "tank" then return end
	local targetRole = Role(g.target)
	if targetRole == "melee" or targetRole == "tank" then return end -- газ лёг на мили — не его вина
	tinsert(g.list, victim)
	Fire("rf_vilegas", g.target, "газ задел мили: " .. tconcat(g.list, ", "), g.t)
end

local function GripDeath(name)
	local now, f = GetTime(), fight
	if f.grip and now - f.grip < 10 and f.ds and abs(f.ds - f.grip) < 10 and f.am and abs(f.am - f.grip) < 10 then
		Fire("sg_breath", name, "умер от кольца после притяжки (сакра и мастер аур были)")
	end
end

local DEATHS = {
	{SPELL.pungentBlight, "fg_blight", "умер от гнили"},
	{SPELL.stickyOoze, "rf_ooze", "умер в луже"},
	{SPELL.unboundPlague, "pp_death", "умер от чумы"},
	{SPELL.oozeEruption, "pp_death", "умер от пельменя"},
	{SPELL.malleableGoo, "pp_death", "умер от колбы"},
	{SPELL.flames, "bp_flames", "умер от апельсина"},
	{SPELL.frostBomb, "sg_bomb", "умер от ледяной бомбы"},
}

local function Damage(spellId, srcGUID, srcName, dstName, overkill)
	if not dstName or not ns.IsHere(dstName) then return end
	local died = (overkill or 0) > 0

	if not spellId and NpcId(srcGUID) == NPC_SHADE then Shade(srcGUID, dstName) end
	if died and srcName and fight.mc[srcName] and srcName ~= dstName then
		Fire("ld_mc_kill", srcName, "под МК убил " .. dstName, dstName)
	end
	if not spellId then return end

	if died then
		if SPELL.saberLash[spellId] then
			if Role(dstName) ~= "tank" then Fire("mg_cleave", dstName, "умер от клива") end
		elseif SPELL.frostBreath[spellId] then
			if Role(dstName) ~= "tank" then Fire("sg_breath", dstName, "умер от дыхания") end
		elseif SPELL.blisteringCold[spellId] then
			GripDeath(dstName)
		else
			for _, d in ipairs(DEATHS) do
				if d[1][spellId] then
					Fire(d[2], dstName, d[3])
					break
				end
			end
		end
	end
	if SPELL.coldflame[spellId] then Coldflame(dstName) end
	if SPELL.shadowsDamage[spellId] then Puddle(dstName) end
	if SPELL.vileGas[spellId] then Gas(dstName) end
end

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

-------------------------------------------------------------------------------
-- журнал боя

local NPC_FLAG = COMBATLOG_OBJECT_TYPE_NPC or 0x800

ns.On("COMBAT_LOG_EVENT_UNFILTERED", function(_, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
	if not ns.Session() then return end

	-- пока идёт пулл-таймер: кто первым ударил врага
	if pullTimer and not firstHit and srcName and (event:find("_DAMAGE", 1, true) or event:find("_MISSED", 1, true))
		and band(dstFlags or 0, NPC_FLAG) > 0 and ns.IsHere(srcName) then
		firstHit = {name = srcName, t = GetTime()}
	end

	if not fight or fight.over then return end
	local spellId = select(1, ...)
	if band(srcFlags or 0, NPC_FLAG) > 0 and type(spellId) == "number" and event:sub(1, 5) == "SPELL" then
		RecordSpell(fight.boss, spellId, (select(2, ...)))
	end

	if event == "SWING_DAMAGE" then
		local _, overkill = ...
		Damage(nil, srcGUID, srcName, dstName, overkill)
	elseif event == "SWING_MISSED" then
		if dstName and ns.IsHere(dstName) and NpcId(srcGUID) == NPC_SHADE then Shade(srcGUID, dstName) end
	elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE" or event == "RANGE_DAMAGE" then
		local _, _, _, _, overkill = ...
		Damage(spellId, srcGUID, srcName, dstName, overkill)
	elseif event == "SPELL_AURA_APPLIED" then
		if SPELL.dominateMind[spellId] and dstName then
			fight.mc[dstName] = true
			WeaponCheck(dstName)
		elseif SPELL.shadowsAura[spellId] and dstName and ns.IsHere(dstName) then
			fight.puddle = {carrier = dstName, start = GetTime(), hits = {}, list = {}}
		end
	elseif event == "SPELL_AURA_REMOVED" then
		if SPELL.dominateMind[spellId] and dstName then
			fight.mc[dstName] = nil
		elseif SPELL.shadowsAura[spellId] and fight.puddle and fight.puddle.carrier == dstName then
			fight.puddle.ends = GetTime() + 10 -- лужи ещё лежат
		end
	elseif event == "SPELL_CAST_SUCCESS" then
		if SPELL.sunder[spellId] and srcName then
			fight.sunders[srcName] = true
		elseif SPELL.vileGas[spellId] and dstName and ns.IsHere(dstName) then
			fight.gas = {target = dstName, t = GetTime(), list = {}}
		elseif SPELL.icyGrip[spellId] then
			fight.grip = GetTime()
		elseif SPELL.divineSacrifice[spellId] then
			fight.ds = GetTime()
		elseif SPELL.auraMastery[spellId] then
			fight.am = GetTime()
		end
	end
end)

-- пулл-таймер DBM (/pull): «секунды\tцель»; 0 — отмена
ns.On("CHAT_MSG_ADDON", function(prefix, msg)
	if prefix ~= "DBMv4-PT" then return end
	local timer = tonumber((strsplit("\t", msg or "")))
	if timer and timer > 0 then
		pullTimer = {ends = GetTime() + timer}
		firstHit = nil
	else
		pullTimer, firstHit = nil, nil
	end
end)

-------------------------------------------------------------------------------
-- начало и конец боя (Session.lua: ns.BossPulled / BossKilled / BossWiped)

local function CheckSunder(f)
	if fight ~= f or f.over then return end
	local s = ns.Session()
	if not s or s.test then return end -- у выдуманных игроков нет журнала боя
	local sec = Param("sunder", "sec") or 10
	for name in pairs(ns.here) do
		local p = s.roster[name]
		if p and p.class == "WARRIOR" and Role(name) ~= "tank" and not f.sunders[name] then
			local unit = ns.UnitByName(name)
			if not unit or not UnitIsDeadOrGhost(unit) then
				Fire("sunder", name, format("нет раскола за первые %d сек", sec))
			end
		end
	end
end

function ns.OnFightStart(key)
	local s = ns.Session()
	fight = {
		boss = key, pull = s and s.pulls[key], start = GetTime(),
		fired = {}, coldflame = {}, mc = {}, sunders = {},
	}
	local f = fight

	-- пул раньше таймера: виноват тот, кто первым ударил
	if pullTimer then
		local early = pullTimer.ends - GetTime()
		pullTimer = nil
		if early > 1 then
			ns.After(1, function()
				if fight ~= f then return end
				local who = firstHit and firstHit.name
				firstHit = nil
				if who then
					Fire("pull_early", who, format("пул за %d сек до конца таймера", floor(early + 0.5)))
				else
					ns.Print(format("пул на %d сек раньше таймера — кто, не видно (стянули телом?).", floor(early + 0.5)))
				end
			end)
		else
			firstHit = nil
		end
	end

	if not NO_SUNDER[key] then
		ns.After(Param("sunder", "sec") or 10, function() CheckSunder(f) end)
	end
end

function ns.OnFightEnd()
	if fight then fight.over = true end
end

-- для тестов и отладки
function ns.CurrentFight() return fight end
