-- Объявления в рейд и шёпот-команды.
-- Новые минусы копятся и уходят одним сообщением: сразу после серии кликов или после боя
-- (настройка announce). Игроку аддон не нужен: !минус в шёпот — его сумма и список.

local _, ns = ...

local format, tinsert, tremove = string.format, table.insert, table.remove
local ipairs = ipairs

local MINUS_CMDS = {["!минус"] = true, ["!минусы"] = true, ["!minus"] = true, ["!rm"] = true}
local REPLY_PREFIX = "[RaidMinus] "

local flushTimer

-------------------------------------------------------------------------------
-- объявления

local function Settings() return ns.DB.settings end

-- режим объявления (общий для всех правил)
local function Mode() return Settings().announce end

local function ScheduleFlush(delay)
	ns.Cancel(flushTimer)
	flushTimer = ns.After(delay, function()
		flushTimer = nil
		ns.FlushAnnounce()
	end)
end

function ns.QueueAnnounce(ev)
	local mode = Mode(ev)
	local s = ns.Session()
	if mode == "off" or not s then return end
	s.pending = s.pending or {}
	tinsert(s.pending, ev.id)
	if mode == "instant" then
		ScheduleFlush(1.5) -- серия быстрых кликов уходит одним сообщением
	elseif not InCombatLockdown() then
		ScheduleFlush(4)
	end
end

function ns.DropFromAnnounce(ev)
	local s = ns.Session()
	if not s or not s.pending then return end
	for i, id in ipairs(s.pending) do
		if id == ev.id then tremove(s.pending, i) return end
	end
end

-- force — отправить всё сейчас, даже в бою (завершение рейда). В бою уходят только записи «сразу».
function ns.FlushAnnounce(force)
	local s = ns.Session()
	if not s or not s.pending or #s.pending == 0 then return end
	local combat = InCombatLockdown() and not force

	-- группируем по боссу в порядке появления
	local order, byBoss, keep = {}, {}, {}
	for _, id in ipairs(s.pending) do
		local ev = ns.EventById(id)
		if ev and ev.status ~= "cancelled" then
			if combat and Mode(ev) == "combat" then
				tinsert(keep, id)
			else
				local key = ev.boss or "general"
				if not byBoss[key] then
					byBoss[key] = {}
					tinsert(order, key)
				end
				tinsert(byBoss[key], ev)
				ev.announced = true
			end
		end
	end
	s.pending = #keep > 0 and keep or nil
	for _, key in ipairs(order) do
		local parts = {}
		for _, ev in ipairs(byBoss[key]) do tinsert(parts, ns.EventShort(ev)) end
		local head = key == "general" and "Минусы: " or (ns.ShortName(key) .. ": ")
		for _, msg in ipairs(ns.Chunks(head, parts, "; ")) do ns.Announce(msg) end
	end
end

function ns.AnnounceCancel(ev)
	if not ev.announced then
		ns.DropFromAnnounce(ev)
		return
	end
	if Mode(ev) == "off" then return end
	local msg = "Снято: " .. ns.EventShort(ev)
	if ev.reason then msg = msg .. " — " .. ev.reason end
	ns.Announce(msg)
end

ns.On("PLAYER_REGEN_ENABLED", function()
	local s = ns.Session()
	if s and s.pending and #s.pending > 0 then ScheduleFlush(2) end
end)

-------------------------------------------------------------------------------
-- шёпот

local lastReply = {}

local function Reply(target, lines)
	for _, line in ipairs(lines) do
		ns.Send(line, "WHISPER", target) -- в тестовом рейде печатается у себя
	end
end

local function MinusReply(sender, arg)
	local name = sender
	if arg ~= "" then
		local found = ns.MatchName(arg, ns.RosterNames())
		if found and found ~= sender and not Settings().whisperOthers then
			return {REPLY_PREFIX .. "можно узнать только свои минусы."}
		end
		if not found then
			return {REPLY_PREFIX .. format("игрок «%s» не найден в рейде.", arg)}
		end
		name = found
	end
	local events = ns.PlayerEvents(name)
	local head = REPLY_PREFIX .. name .. ": итого " .. ns.StateText(name, false)
	if #events == 0 then
		return {head .. ". Записей нет."}
	end
	local parts = {}
	for _, ev in ipairs(events) do
		tinsert(parts, ns.ShortName(ev.boss) .. ": " .. ns.EventShort(ev, false))
	end
	return ns.Chunks(head .. ". ", parts, "; ")
end

-- !минус [имя]: возвращает "minus" и аргумент
local function ParseCommand(msg)
	local cmd, arg = tostring(msg or ""):match("^%s*(!%S+)%s*(.-)%s*$")
	if not cmd then return end
	cmd = ns.Lower(cmd)
	if MINUS_CMDS[cmd] then return "minus", arg end
end

-- входящий шёпот (тестовый рейд вызывает напрямую — «игрок спросил свои минусы»)
function ns.HandleWhisper(msg, sender)
	local s = ns.Session()
	if not s or not Settings().whisper then return end
	local kind, arg = ParseCommand(msg)
	if not kind then return end
	local now = GetTime()
	if lastReply[sender] and now - lastReply[sender] < 3 then return end
	lastReply[sender] = now
	Reply(sender, MinusReply(sender, arg))
end

ns.On("CHAT_MSG_WHISPER", function(msg, sender) ns.HandleWhisper(msg, sender) end)

-- прячем команды и ответы из чата РЛа
local function HideIncoming(_, _, msg)
	if Settings().hideWhispers and Settings().whisper and ns.Session() and ParseCommand(msg) then return true end
end

local function HideOutgoing(_, _, msg)
	if Settings().hideWhispers and tostring(msg):sub(1, #REPLY_PREFIX) == REPLY_PREFIX then return true end
end

ns.OnLoad(function()
	ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", HideIncoming)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", HideOutgoing)
end)
