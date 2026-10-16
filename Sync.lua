-- Синхронизация между игроками с RaidMinus в одном рейде (скрытый канал аддонов «RaidMinus», рейд или группа).
-- Аддон не делит минусы (их ставит РЛ у себя), а сообщает остальным о добыче и розыгрыше:
--   RS ссылка сек флаги — я начал ролл (o — офф-спек, t — переролл ничьей): у других предмет «разыгрывается»,
--                         их кнопка «Начать ролл» недоступна, броски они тихо считают со своими минусами;
--   RE ссылка победитель ничья — ролл закончен; RC ссылка — ролл отменён;
--   AW ссылка игрок      — предмет фактически получил другой игрок (не победитель); пусто — сброс;
--   LT тело номера       — я открыл тело: что в нём лежит (как RaidRoll, но не нужен второй аддон);
--   TT номер:сек,...     — сколько осталось на передачу предметов из моей сумки (я ответственный за добычу);
--   HI                   — я только вошёл (/reload): кто сейчас разыгрывает — напомните.
-- Ролл, итог и «получил» принимаются только от РЛа, помощника и ответственного за добычу.

local _, ns = ...

local format, tinsert, tconcat = string.format, table.insert, table.concat
local ipairs, tonumber, floor = ipairs, tonumber, math.floor

local PREFIX = "RaidMinus"
local LINK = "|c%x+|Hitem:.-|h.-|h|r"

local function Settings() return ns.DB.settings end

-- канал для синхронизации; нет — не шлём (не в группе, тестовый рейд, выключено)
local function Channel()
	local s = ns.Session()
	if not s or s.test or not Settings().sync then return end
	if GetNumRaidMembers() > 0 then return "RAID" end
	if GetNumPartyMembers() > 0 then return "PARTY" end
end

local function Send(...)
	local ch = Channel()
	if not ch then return end
	local msg = tconcat({...}, "\t")
	if #msg > 250 then return end
	SendAddonMessage(PREFIX, msg, ch)
end

function ns.SyncRollStart(r)
	Send("RS", r.link, floor(r.duration), (r.off and "o" or "") .. (r.only and "t" or ""))
end

function ns.SyncRollEnd(e)
	local res = e.result or {}
	Send("RE", e.link, res.winner or "", res.tie and tconcat(res.tie, ",") or "")
end

function ns.SyncRollCancel(link) Send("RC", link) end

function ns.SyncAward(e) Send("AW", e.link, e.receiver or "") end

-- я открыл тело: остальным — номера предметов (один раз на тело)
function ns.SyncLoot(mob, items, guid)
	local s = ns.Session()
	if not s or not Channel() then return end
	s.syncedBodies = s.syncedBodies or {}
	local key = guid or ((mob or "?") .. date("%H%M"))
	if s.syncedBodies[key] then return end
	s.syncedBodies[key] = true
	local ids = {}
	for _, x in ipairs(items) do tinsert(ids, x.id) end
	Send("LT", mob or "", tconcat(ids, ","))
end

-- время на передачу из моей сумки: {[номер] = {сек, ...}}
local lastTT = 0
function ns.SyncTradeTimes(byId)
	if not ns.CanManageLoot() or GetTime() - lastTT < 60 then return end
	local parts = {}
	for id, list in pairs(byId) do
		for _, sec in ipairs(list) do tinsert(parts, id .. ":" .. floor(sec)) end
	end
	if #parts == 0 then return end
	lastTT = GetTime()
	local msg = tconcat(parts, ",")
	Send("TT", msg:sub(1, 240))
end

-------------------------------------------------------------------------------
-- приём

-- запись для чужого ролла: та, что ещё не разыграна; нет — новая
local function EntryFor(link, sender)
	return (ns.AddLoot(link, "announce", sender))
end

-- запись с этим предметом, которую разыгрывал (или разыгрывает) sender
local function RemoteEntry(id, sender)
	local found
	for _, e in ipairs(ns.LootByItem(id)) do
		if e.remote and e.remote.by == sender then found = e end
	end
	return found
end

local function OnRollStart(link, sec, flags, sender)
	local id = ns.ItemId(link)
	local r = ns.roll
	if r and r.state == "open" and ns.ItemId(r.link) == id then
		-- уже считаю этот предмет (увидел объявление в чате раньше синхронизации)
		local e = ns.LootById(r.loot)
		if e then e.remote = {by = sender, t = time()} end
		if r.watch then
			r.watch = sender
			r.ends = GetTime() + (tonumber(sec) or 30) + 5
		end
		return
	end
	if r and r.state == "open" and not r.watch then
		ns.Print(format("%s тоже начал ролл %s, а у вас идёт свой — договоритесь, кто разыгрывает.", sender, link))
		return
	end
	local e = EntryFor(link, sender)
	if not e then return end
	e.remote = {by = sender, t = time()}
	ns.StartRoll(e, nil, sender, flags and flags:find("o", 1, true) and true or nil)
	local now = ns.roll
	if now and now.loot == e.id then
		now.ends = GetTime() + (tonumber(sec) or 30) + 5
		now.synced = true
	end
end

local function OnRollEnd(link, winner, tie, sender)
	local id = ns.ItemId(link)
	winner = winner ~= "" and winner or nil
	local r = ns.roll
	local e
	if r and r.state == "open" and r.watch and ns.ItemId(r.link) == id then
		e = ns.LootById(r.loot)
		ns.FinishRoll(false)
	end
	e = e or RemoteEntry(id, sender)
	if not e then return end
	e.remote = e.remote or {by = sender}
	e.remote.done, e.remote.winner = true, winner
	if not e.result then
		e.result = {entries = {}, winner = winner, none = not winner or nil, remote = sender, t = time()}
		if tie and tie ~= "" then
			e.result.tie = {strsplit(",", tie)}
			e.result.none = nil
		end
		e.winner = winner
	elseif winner and e.result.winner ~= winner then
		e.result.remoteWinner = winner -- у разыгрывавшего (его минусы) — другой победитель
	end
end

local function OnRollCancel(link, sender)
	local id = ns.ItemId(link)
	local r = ns.roll
	if r and r.state == "open" and r.watch and ns.ItemId(r.link) == id then ns.CancelRoll(true) end
	local e = RemoteEntry(id, sender)
	if e and not e.result then e.remote = nil end
end

local function OnAward(link, name, sender)
	local id = ns.ItemId(link)
	name = name ~= "" and name or nil
	local target
	for _, e in ipairs(ns.LootByItem(id)) do
		if name == nil and e.receiver then target = e break end
		if name and not e.receiver and (e.result or not target) then target = e end
	end
	if target then ns.SetReceiver(target, name, "от " .. sender) end
end

local function OnLootList(mob, list, sender)
	if not Settings().srcSync or not ns.IsHere(sender) then return end
	local items = {}
	for n in tostring(list or ""):gmatch("%d+") do
		local id = tonumber(n)
		tinsert(items, {id = id, link = ns.ItemLink(id)})
	end
	if #items > 0 then ns.ReportLoot("sync", sender, mob ~= "" and mob or nil, items) end
end

local function OnTradeTimes(list, sender)
	if not ns.officers[sender] then return end
	local byId = {}
	for id, sec in tostring(list or ""):gmatch("(%d+):(%d+)") do
		id = tonumber(id)
		byId[id] = byId[id] or {}
		tinsert(byId[id], tonumber(sec))
	end
	if ns.ApplyTradeTimes then ns.ApplyTradeTimes(byId, false) end
end

-- кто-то вошёл: если я сейчас разыгрываю — напомнить
local function OnHello()
	local r = ns.roll
	if r and r.state == "open" and not r.watch then
		Send("RS", r.link, floor(math.max(5, r.ends - GetTime())), (r.off and "o" or "") .. (r.only and "t" or ""))
	end
end

function ns.OnSyncMessage(msg, channel, sender)
	if not ns.Session() or not Settings().sync or sender == ns.PlayerName() then return end
	local cmd, a, b, c = strsplit("\t", msg or "")
	if cmd == "LT" then
		OnLootList(a, b, sender)
	elseif cmd == "TT" then
		OnTradeTimes(a, sender)
	elseif cmd == "HI" then
		OnHello()
	elseif cmd == "RS" or cmd == "RE" or cmd == "RC" or cmd == "AW" then
		if not ns.officers[sender] then return end -- разыгрывать могут только РЛ, помощник и ответственный
		local link = a and a:match(LINK)
		if not link then return end
		if cmd == "RS" then
			OnRollStart(link, b, c, sender)
		elseif cmd == "RE" then
			OnRollEnd(link, b or "", c or "", sender)
		elseif cmd == "RC" then
			OnRollCancel(link, sender)
		else
			OnAward(link, b or "", sender)
		end
	else
		return
	end
	ns.Refresh()
end

ns.On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
	if prefix == PREFIX and msg and msg:sub(1, 2) ~= "V:" then ns.OnSyncMessage(msg, channel, sender) end
end)

-- после /reload или входа в рейд: спросить, не идёт ли сейчас ролл
ns.On("PLAYER_ENTERING_WORLD", function()
	ns.After(6, function() if ns.Session() then Send("HI") end end)
end)
