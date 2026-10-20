-- Пулл-таймер DBM: был ли пул раньше таймера и кто первым тронул босса. Журнал пулов — /rm лог пул.
-- Пул раньше таймера ловит триггер «DBM: пул раньше таймера» (Triggers.lua, ns.TriggerPullEarly).
-- На Circle DBM (форк DBM-wowcircle) делает /pull «пиццей» с текстом «Атака» и рассылает её как
-- DBMv4-Pizza, а не DBMv4-PT — поэтому слушаем все пути: перехват DBM:CreatePizzaTimer (свой и чужой /pull),
-- оба сообщения DBM и, на крайний случай, объявление «Атака через 10 сек.» от РЛа или помощника.

local _, ns = ...

local format, tinsert = string.format, table.insert
local band, abs, floor = bit.band, math.abs, math.floor
local ipairs, tonumber, select = ipairs, tonumber, select

local NPC_FLAG = COMBATLOG_OBJECT_TYPE_NPC or 0x800
local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40
-- чем можно спулить босса: урон, промах, дебаф, таунт (метка охотника, рык, хватка смерти)
local PULL_EVENTS = {
	SWING_DAMAGE = true, SWING_MISSED = true, RANGE_DAMAGE = true, RANGE_MISSED = true,
	SPELL_DAMAGE = true, SPELL_MISSED = true, SPELL_PERIODIC_DAMAGE = true, SPELL_PERIODIC_MISSED = true,
	SPELL_AURA_APPLIED = true, SPELL_CAST_SUCCESS = true,
}
local PULL_TEXTS = {["Атака"] = true, ["Pull in"] = true}

local pullTimer -- {ends, source, sec} — идёт пулл-таймер DBM
local firstHit  -- {name, pet, t, how, target} — кто первым тронул врага, пока шёл таймер

local function IsPullText(text)
	return text and (PULL_TEXTS[text] or (DBM_CORE_TIMER_PULL and text == tostring(DBM_CORE_TIMER_PULL)))
end

-- пока идёт пулл-таймер: кто первым тронул врага (ударил, повесил дебаф, таунтнул; питомец — хозяин)
ns.On("COMBAT_LOG_EVENT_UNFILTERED", function(_, event, srcGUID, srcName, srcFlags, _, dstName, dstFlags, ...)
	if not pullTimer or firstHit or not PULL_EVENTS[event] or not dstName or not ns.Session() then return end
	if band(dstFlags or 0, NPC_FLAG) == 0 or band(dstFlags or 0, HOSTILE) == 0 then return end
	local who, pet = ns.Culprit(srcGUID, srcName, srcFlags)
	if who then
		local how = event:sub(1, 5) == "SWING" and "автоатака" or select(2, ...)
		firstHit = {name = who, pet = pet, t = GetTime(), how = how, target = dstName}
	end
end)

-- sec > 0 — таймер пошёл (повтор того же таймера из другого источника ничего не меняет), 0 — отмена
function ns.SetPullTimer(sec, source)
	sec = tonumber(sec) or 0
	if sec > 0 then
		local ends = GetTime() + sec
		if pullTimer and abs(pullTimer.ends - ends) < 1.5 then return end
		pullTimer = {ends = ends, source = source, sec = sec}
		firstHit = nil
		ns.RefreshPets()
	else
		pullTimer, firstHit = nil, nil
	end
end

ns.On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
	if prefix == "DBMv4-PT" then
		if sender and not ns.officers[sender] and sender ~= ns.PlayerName() then return end
		ns.SetPullTimer((strsplit("\t", msg or "")), "DBM")
	elseif prefix == "DBMv4-Pizza" then
		if sender and not ns.officers[sender] and sender ~= ns.PlayerName() then return end
		local sec, text = strsplit("\t", msg or "")
		if IsPullText(text) then ns.SetPullTimer(sec, "DBM") end
	end
end)

local announcePattern
local function OnPullAnnounce(msg, sender)
	if not ns.Session() or not sender or not ns.officers[sender] then return end
	if announcePattern == nil then
		announcePattern = DBM_CORE_ANNOUNCE_PULL and ns.ToPattern(DBM_CORE_ANNOUNCE_PULL) or false
	end
	local sec = announcePattern and msg:match(announcePattern) or msg:match("^Атака через (%d+) сек") or msg:match("^Pull in (%d+) sec")
	if sec then ns.SetPullTimer(sec, "чат") end
end

for _, event in ipairs({"CHAT_MSG_RAID_WARNING", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER"}) do
	ns.On(event, OnPullAnnounce)
end

ns.OnLoad(function()
	local DBM = _G.DBM
	if DBM and type(DBM.CreatePizzaTimer) == "function" then
		hooksecurefunc(DBM, "CreatePizzaTimer", function(_, time, text, _, _, _, terminate)
			if IsPullText(text) then ns.SetPullTimer(not terminate and time or 0, "DBM") end
		end)
	end
end)

-- журнал пулов: был ли таймер, на сколько раньше, кто первым (/rm лог пул)
local function PullLog(entry)
	local s = ns.Session()
	if not s then return end
	s.pullLog = s.pullLog or {}
	tinsert(s.pullLog, entry)
	while #s.pullLog > 40 do table.remove(s.pullLog, 1) end
end

local function PullLine(x)
	if not x.timer then return format("%s, пул %d: без таймера", ns.ShortName(x.boss), x.pull or 0) end
	if x.early < 1 then return format("%s, пул %d: по таймеру", ns.ShortName(x.boss), x.pull or 0) end
	local who = x.who and (x.who .. (x.pet and (" (питомец " .. x.pet .. ")") or "") .. (x.how and (", " .. x.how) or ""))
		or "кто — не видно (стянули телом?)"
	return format("%s, пул %d: на %d сек раньше таймера — %s", ns.ShortName(x.boss), x.pull or 0, floor(x.early + 0.5), who)
end

function ns.PrintPullLog()
	local s = ns.Session()
	local log = s and s.pullLog
	if not log or #log == 0 then
		ns.Print("пулов ещё не было.")
		return
	end
	ns.Print("пулы боссов:")
	for _, x in ipairs(log) do
		DEFAULT_CHAT_FRAME:AddMessage(format("  |cff9d9d9d%s|r %s", date("%H:%M", x.t), PullLine(x)))
	end
end

-- начало боя (Triggers.lua, ns.OnFightStart): пул раньше таймера? Виноват тот, кто первым тронул босса.
-- Время — по первому удару (DBM замечает бой на секунду-две позже). Удар мог прийти и чуть после DBM —
-- таймер живёт ещё секунду.
function ns.CheckPull(f, key)
	local timer = pullTimer
	if not timer then
		firstHit = nil
		PullLog({t = time(), boss = key, pull = f.pull})
		return
	end
	ns.After(1, function()
		if pullTimer == timer then pullTimer = nil end
		if ns.CurrentFight() ~= f then return end
		local hit = firstHit
		firstHit = nil
		local early = timer.ends - (hit and hit.t or f.start)
		local entry = {t = time(), boss = key, pull = f.pull, timer = true, early = early, source = timer.source}
		if early >= 1 and hit then
			entry.who, entry.pet, entry.how = hit.name, hit.pet, hit.how and tostring(hit.how)
		end
		PullLog(entry)
		if early < 1 then return end
		ns.Print(PullLine(entry))
		if hit then
			ns.TriggerPullEarly(hit.name, early, format("пул за %d сек до конца таймера%s", floor(early + 0.5),
				hit.pet and (", питомец " .. hit.pet) or ""))
		end
	end)
end
