-- Рейд-сессия: кто был в рейде, какой босс сейчас (по DBM), номера пулов.
-- Живёт в RaidMinusDB.session и переживает /reload; «Завершить рейд» переносит её в историю.
-- Тестовый рейд: 25 выдуманных игроков, в чат ничего не уходит (ns.Send печатает у себя).

local _, ns = ...

local format, tinsert, tremove = string.format, table.insert, table.remove
local pairs, ipairs = pairs, ipairs

-- имя, класс, группа, основная роль, текущий спек (Холпал — хил, переодетый в ДД)
local TEST_ROSTER = {
	{"Танкист", "WARRIOR", 1, "tank"}, {"Щитонос", "PALADIN", 1, "tank"}, {"Яростька", "WARRIOR", 1, "melee"},
	{"Рогалик", "ROGUE", 1, "melee"}, {"Дедуля", "DEATHKNIGHT", 1, "melee"},
	{"Котопёс", "DRUID", 2, "melee"}, {"Ретрик", "PALADIN", 2, "melee"}, {"Энхик", "SHAMAN", 2, "melee"},
	{"Морозко", "DEATHKNIGHT", 2, "melee"}, {"Тенелап", "ROGUE", 2, "melee"},
	{"Стрелок", "HUNTER", 3, "caster"}, {"Ханточка", "HUNTER", 3, "caster"}, {"Огнемаг", "MAGE", 3, "caster"},
	{"Аркана", "MAGE", 3, "caster"}, {"Совушка", "DRUID", 3, "caster"},
	{"Варлок", "WARLOCK", 4, "caster"}, {"Демонюга", "WARLOCK", 4, "caster"}, {"Элемка", "SHAMAN", 4, "caster"},
	{"Шпшка", "PRIEST", 4, "caster"}, {"Бумкин", "DRUID", 4, "caster"},
	{"Холпал", "PALADIN", 5, "healer", "melee"}, {"Дископрист", "PRIEST", 5, "healer"}, {"Рестошам", "SHAMAN", 5, "healer"},
	{"Деревце", "DRUID", 5, "healer"}, {"Холиприст", "PRIEST", 5, "healer"},
}

ns.here = {}     -- кто сейчас в группе: имя -> номер группы
ns.officers = {} -- лидер, ассистенты и ответственный за добычу: их объявления ролла попадают в список

-------------------------------------------------------------------------------
-- роли: основная (первая замеченная за рейд или выставленная РЛом) и текущий спек.
-- Хил, переодетый на Орке в ДД, остаётся хилом — планка ДПС его не касается.

ns.ROLES = {
	{key = "tank", name = "танк", color = "ffc79c6e"},
	{key = "healer", name = "хил", color = "ff40ff40"},
	{key = "melee", name = "мдд", color = "ffff8040"},
	{key = "caster", name = "рдд", color = "ff69ccf0"},
}
local roleInfo = {}
for _, r in ipairs(ns.ROLES) do roleInfo[r.key] = r end

function ns.RoleName(key, colored)
	local r = roleInfo[key or ""]
	if not r then return colored and "|cff707070?|r" or "?" end
	return colored and ("|c" .. r.color .. r.name .. "|r") or r.name
end

-- охотник для правил — РДД (LibGroupTalents считает его мили)
local PURE = {ROGUE = "melee", HUNTER = "caster", MAGE = "caster", WARLOCK = "caster"}

local function DetectRole(p, unit)
	local LGT = LibStub("LibGroupTalents-1.0", true)
	local role = PURE[p.class] or (LGT and LGT:GetUnitRole(unit))
	if not role then return end
	p.cur = role
	if not p.role then p.role = role end
end

-- role = nil — снова определять автоматически
function ns.SetRole(name, role)
	local s = ns.Session()
	local p = s and s.roster[name]
	if not p then return end
	if role then
		p.role, p.manual = role, true
	else
		p.role, p.manual = p.cur, nil
	end
	ns.Refresh()
end

-- основная роль, текущий спек, выставлена ли вручную
function ns.PlayerRole(name)
	local s = ns.Session()
	local p = s and s.roster[name]
	if not p then return end
	return p.role, p.cur, p.manual
end

function ns.Session() return ns.DB and ns.DB.session end

function ns.PlayerName() return UnitName("player") end

local function Archive(s)
	local db = ns.DB
	s.ended = s.ended or time()
	s.pending = nil
	if not s.test and (#s.events > 0 or #s.loot > 0) then
		tinsert(db.history, 1, s)
		while #db.history > ns.HISTORY do tremove(db.history) end
	end
end

function ns.StartSession(test)
	local db = ns.DB
	if ns.CancelRoll then ns.CancelRoll(true) end
	if db.session then Archive(db.session) end
	local rs = ns.ActiveRuleset()
	db.session = {
		id = date("%Y%m%d-%H%M%S"),
		started = time(),
		leader = ns.PlayerName(),
		ruleset = rs.name,
		test = test or nil,
		roster = {},
		events = {},
		nextId = 0,
		pulls = {},
		loot = {},
		nextLoot = 0,
	}
	if test then
		for _, p in ipairs(TEST_ROSTER) do
			db.session.roster[p[1]] = {class = p[2], group = p[3], role = p[4], cur = p[5] or p[4]}
		end
	end
	ns.UpdateRoster()
	if test then
		ns.Print("тестовый рейд начат: 25 выдуманных игроков, объявления и шёпот печатаются только у вас. Свод: " .. rs.name)
	else
		ns.Print("рейд начат, свод правил: " .. rs.name)
	end
	ns.Refresh()
end

function ns.EndSession()
	local db = ns.DB
	if not db.session then return end
	if ns.CancelRoll then ns.CancelRoll(true) end
	if ns.FlushAnnounce then ns.FlushAnnounce(true) end
	Archive(db.session)
	db.session = nil
	wipe(ns.here)
	ns.Print("рейд завершён, журнал перенесён в историю.")
	ns.Refresh()
end

StaticPopupDialogs["RAIDMINUS_END"] = {
	text = "Завершить рейд?\nМинусы обнулятся, журнал уйдёт в историю.",
	button1 = YES,
	button2 = NO,
	OnAccept = function() ns.EndSession() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	preferredIndex = 3,
}

function ns.ConfirmEndSession()
	if not ns.Session() then
		ns.Print("рейд не начат.")
		return
	end
	StaticPopup_Show("RAIDMINUS_END")
end

-------------------------------------------------------------------------------
-- состав

function ns.UpdateRoster()
	local s = ns.Session()
	wipe(ns.here)
	wipe(ns.officers)
	if not s then return end
	local me = ns.PlayerName()
	if s.test then
		for name, p in pairs(s.roster) do
			ns.here[name] = p.group
			ns.officers[name] = true
		end
		local _, class = UnitClass("player")
		if not s.roster[me] then
			s.roster[me] = {class = class, group = 1}
			DetectRole(s.roster[me], "player")
		end
		ns.here[me] = 1
		return
	end
	local n = GetNumRaidMembers()
	if n > 0 then
		for i = 1, n do
			local name, rank, group, _, _, class, _, _, _, _, isML = GetRaidRosterInfo(i)
			if name and name ~= UNKNOWN then
				local p = s.roster[name] or {}
				p.class, p.group = class, group
				s.roster[name] = p
				ns.here[name] = group
				if (rank or 0) >= 1 or isML then ns.officers[name] = true end
				DetectRole(p, "raid" .. i)
			end
		end
	else
		local units = {"player"}
		for i = 1, GetNumPartyMembers() do units[#units + 1] = "party" .. i end
		for _, unit in ipairs(units) do
			local name = UnitName(unit)
			if name and name ~= UNKNOWN then
				local _, class = UnitClass(unit)
				local p = s.roster[name] or {}
				p.class, p.group = class, 1
				s.roster[name] = p
				ns.here[name] = 1
				ns.officers[name] = true
				DetectRole(p, unit)
			end
		end
	end
end

-- в группе ли игрок (для приёма бросков)
function ns.IsHere(name) return name and ns.here[name] ~= nil end

-- список для окна: кто в группе (по группам), затем ушедшие, у кого есть записи в журнале
function ns.RosterList()
	local s = ns.Session()
	local out = {}
	if not s then return out end
	local hasEvents = {}
	for _, ev in ipairs(s.events) do hasEvents[ev.player] = true end
	for name, p in pairs(s.roster) do
		local group = ns.here[name]
		if group or hasEvents[name] then
			tinsert(out, {name = name, class = p.class, group = group, gone = not group})
		end
	end
	table.sort(out, function(a, b)
		if (a.gone or false) ~= (b.gone or false) then return not a.gone end
		if (a.group or 9) ~= (b.group or 9) then return (a.group or 9) < (b.group or 9) end
		return a.name < b.name
	end)
	return out
end

function ns.RosterNames()
	local s = ns.Session()
	local out = {}
	if s then
		for name in pairs(s.roster) do tinsert(out, name) end
	end
	return out
end

ns.On("RAID_ROSTER_UPDATE", function() ns.UpdateRoster() ns.Refresh() end)
ns.On("PARTY_MEMBERS_CHANGED", function() ns.UpdateRoster() ns.Refresh() end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.UpdateRoster() ns.Refresh() end)

-------------------------------------------------------------------------------
-- босс сейчас: по событиям DBM (пул, убийство, вайп)

function ns.CurrentBoss()
	local s = ns.Session()
	return s and s.boss
end

-- текст «Леди, пул 2»
function ns.BossText(key, pull)
	if not key then return "—" end
	if pull and pull > 0 then return format("%s, пул %d", ns.ShortName(key), pull) end
	return ns.ShortName(key)
end

StaticPopupDialogs["RAIDMINUS_RELOAD"] = {
	text = "RaidMinus: записать журнал на диск (/reload)?\nWoW сохраняет данные аддонов только при /reload и выходе — при вылете игры минусы этого рейда пропадут.",
	button1 = "/reload",
	button2 = "Позже",
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	preferredIndex = 3,
}

local function ReloadPrompt()
	-- SkadaDiscord сама делает /reload после убийства
	if not ns.DB.settings.reloadPrompt or IsAddOnLoaded("SkadaDiscord") then return end
	local s = ns.Session()
	if not s or s.test then return end
	if InCombatLockdown() or (ns.roll and ns.roll.state == "open") then
		ns.After(5, ReloadPrompt)
		return
	end
	StaticPopup_Show("RAIDMINUS_RELOAD")
end

-- пул и убийство босса (по DBM; тестовый рейд вызывает напрямую)
function ns.BossPulled(key)
	local s = ns.Session()
	if not s or not key then return end
	s.pulls[key] = (s.pulls[key] or 0) + 1
	s.boss = key
	if ns.OnBossChanged then ns.OnBossChanged(key) end
	if ns.OnFightStart then ns.OnFightStart(key) end
	ns.Refresh()
end

function ns.BossKilled(key)
	local s = ns.Session()
	if not s or not key then return end
	s.killed = s.killed or {}
	s.killed[key] = true
	if ns.OnFightEnd then ns.OnFightEnd(key, "kill") end
	if ns.MetricsOnKill then ns.MetricsOnKill(key) end
	ns.Refresh()
	ns.After(8, ReloadPrompt)
end

local function OnPull(_, mod) ns.BossPulled(mod and ns.BossByDBM(mod.id)) end
local function OnKill(_, mod) ns.BossKilled(mod and ns.BossByDBM(mod.id)) end

function ns.BossWiped(key)
	if not ns.Session() or not key then return end
	if ns.OnFightEnd then ns.OnFightEnd(key, "wipe") end
	ns.Refresh()
end

local function OnWipe(_, mod) ns.BossWiped(mod and ns.BossByDBM(mod.id)) end

ns.OnLoad(function()
	ns.UpdateRoster()
	local DBM = _G.DBM
	if DBM and DBM.RegisterCallback then
		DBM:RegisterCallback("DBM_Pull", OnPull)
		DBM:RegisterCallback("DBM_Kill", OnKill)
		DBM:RegisterCallback("DBM_Wipe", OnWipe)
	end
	-- спеки других игроков приходят не сразу
	local LGT = LibStub("LibGroupTalents-1.0", true)
	if LGT and LGT.RegisterCallback then
		local function TalentsChanged()
			ns.UpdateRoster()
			ns.Refresh()
		end
		LGT.RegisterCallback(ns, "LibGroupTalents_Update", TalentsChanged)
		LGT.RegisterCallback(ns, "LibGroupTalents_RoleChange", TalentsChanged)
	end
end)
