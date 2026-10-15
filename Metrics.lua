-- Цифры Skada для автоправил: планка ДПС на Саурфанге и бонус за урон на Профессоре.
-- Считаются после убийства по законченному бою Skada — те же цифры, что видит рейд.
-- Планка — только у основной роли мдд/рдд: хил или танк, переодетый в ДД, не считается.

local _, ns = ...

local format, pairs, next = string.format, pairs, next

local PUTRICIDE = 36678
local OOZES = {[37697] = true, [37562] = true} -- нестабильный слизнюк, газовое облако
-- если Skada не ведёт врагов по ID — ищем слизней по имени
local OOZE_NAMES = {
	["Нестабильный слизнюк"] = true, ["Нестабильная слизь"] = true, ["Газовое облако"] = true,
	["Volatile Ooze"] = true, ["Gas Cloud"] = true,
}
local WAIT_SKADA = 5 -- сек после убийства: Skada могла ещё не закрыть бой

local function Param(key, pkey)
	local rule = ns.AutoRule(ns.ActiveRuleset(), key)
	return rule and ns.RuleParam(rule, pkey)
end

local function Damage(actor, abs)
	return (abs and actor.totaldamage or actor.damage) or 0
end

-- урон игрока по целям: имя цели -> урон
local function TargetDamage(actor, abs)
	local out = {}
	for _, spell in pairs(actor.damagespells or {}) do
		for tname, info in pairs(spell.targets or {}) do
			local amount = abs and info.total or info.amount
			if amount and amount > 0 then out[tname] = (out[tname] or 0) + amount end
		end
	end
	return out
end

-- имена врагов этого боя с нужными NPC ID
local function EnemyNames(set, ids)
	local out = {}
	for name, actor in pairs(set.actors) do
		if actor.enemy and not actor.fake and ids[ns.NpcId(actor.id) or 0] then out[name] = true end
	end
	return out
end

local function CheckDps(set)
	local Skada = _G.Skada
	local abs = Skada.profile and Skada.profile.absdamage
	local need = Param("sf_dps", "dps") or 17000
	for name, actor in pairs(set.actors) do
		if not actor.enemy and ns.IsHere(name) then
			local role = ns.PlayerRole(name)
			if role == "melee" or role == "caster" then
				local dps = Damage(actor, abs) / Skada:GetActiveTime(set, actor)
				if dps < need then
					ns.Detected("sf_dps", name, format("ДПС %d < %d (Skada)", math.floor(dps), need))
				end
			end
		end
	end
end

local function CheckPutricide(set)
	local Skada = _G.Skada
	local abs = Skada.profile and Skada.profile.absdamage
	local needBoss, needOoze = Param("pp_bonus", "boss") or 2500000, Param("pp_bonus", "ooze") or 650000
	local bossNames = EnemyNames(set, {[PUTRICIDE] = true})
	if not next(bossNames) and set.mobname then bossNames[set.mobname] = true end
	local oozeNames = EnemyNames(set, OOZES)
	if not next(oozeNames) then oozeNames = OOZE_NAMES end
	for name, actor in pairs(set.actors) do
		if not actor.enemy and ns.IsHere(name) then
			local b, o = 0, 0
			for target, amount in pairs(TargetDamage(actor, abs)) do
				if bossNames[target] then
					b = b + amount
				elseif oozeNames[target] then
					o = o + amount
				end
			end
			if b >= needBoss and o >= needOoze then
				ns.Detected("pp_bonus", name, format("в Профа %s, в слизней %s (Skada)", ns.ShortNumber(b), ns.ShortNumber(o)))
			end
		end
	end
end

local CHECKS = {saurfang = CheckDps, putricide = CheckPutricide}

-- один раз за убийство
local function Evaluate(key, set)
	local s = ns.Session()
	if not s or not CHECKS[key] or not set or not set.actors then return end
	local tag = key .. ":" .. tostring(s.pulls[key] or 0)
	s.metricsDone = s.metricsDone or {}
	if s.metricsDone[tag] then return end
	s.metricsDone[tag] = true
	CHECKS[key](set)
end

-- Skada закрыла бой
local handler = {}
function handler:OnSetComplete(_, set)
	local s = ns.Session()
	local key = s and s.boss
	if not key or not CHECKS[key] or not set or not set.gotboss then return end
	if set.success or (s.killed and s.killed[key]) then Evaluate(key, set) end
end

-- DBM сказал «убит»: если Skada не отметила убийство, берём её последний бой
function ns.MetricsOnKill(key)
	if not CHECKS[key] then return end
	ns.After(WAIT_SKADA, function()
		local Skada = _G.Skada
		local s = ns.Session()
		if not Skada or not s or s.boss ~= key then return end
		local set = Skada.last or (Skada.sets and Skada.sets[1])
		if set and set.gotboss then Evaluate(key, set) end
	end)
end

ns.OnLoad(function()
	local Skada = _G.Skada
	if Skada and Skada.RegisterCallback then
		Skada.RegisterCallback(handler, "Skada_SetComplete", "OnSetComplete")
	end
end)
