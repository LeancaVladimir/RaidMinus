-- RaidMinus: минусы и плюсы от РЛа за рейд. Их сумма прибавляется к /roll на итоговом розыгрыше лута.
-- Ядро: база (SavedVariables), события, таймеры, общие помощники и слеш-команды.
-- Порядок модулей — в RaidMinus.toc; каждый регистрирует запуск через ns.OnLoad.

local ADDON, ns = ...

local format, tostring, tonumber, type = string.format, tostring, tonumber, type
local pairs, ipairs = pairs, ipairs
local tinsert, tremove, tconcat = table.insert, table.remove, table.concat

ns.VERSION = GetAddOnMetadata(ADDON, "Version") or "?"

local DEFAULTS = {
	announce = "combat",   -- объявлять минусы в рейд: instant — сразу, combat — после боя, off — нет
	whisper = true,        -- отвечать на !минус в шёпот
	whisperOthers = false, -- можно ли узнать чужие минусы (!минус Имя)
	hideWhispers = true,   -- прятать команды и ответы из своего чата
	rollTime = 30,         -- секунд на ролл
	tieTime = 15,          -- секунд на переролл ничьей
	rollMax = 100,         -- засчитывается только /roll 1-rollMax
	rollCountdown = true,  -- «осталось 10 сек»
	-- добыча (LootList.lua): откуда узнаём, что упало, и что из этого разыгрываем
	lootFilter = "boss",   -- boss — снаряжение с боссов ЦЛК любой сложности; heroic — только гер.; epic — все эпики
	lootMinIlvl = 277,     -- предметы не из таблиц ЦЛК: эпик, надевается, уровень не ниже этого
	lootQuality = 4,       -- для фильтра epic: от какого качества
	lootAuto = true,       -- добыча, прошедшая фильтр, сразу попадает в розыгрыш
	lootPopup = "new",     -- окно «Добыча»: new — при новой добыче, missing — если что-то не в розыгрыше, off — само не открывать
	srcCorpse = true,      -- открыл тело сам
	srcRaidRoll = true,    -- тело открыл другой с аддоном RaidRoll (скрытый канал RRL)
	srcChat = true,        -- строки «Вася получает добычу: [предмет]»
	srcList = true,        -- лидер, ассистент или ответственный за добычу скинул в рейд список ссылок
	srcSync = true,        -- тело открыл другой игрок с RaidMinus (рассылает добычу сам)
	sync = true,           -- ролл виден у всех с RaidMinus: кто разыгрывает, итог, кто получил (Sync.lua)
	tradeWarn = true,      -- предупреждать, когда на передачу предмета остаётся мало времени
	watchOthers = true,    -- ролл объявил ответственный за добычу — предмет в список, броски считаются с минусами
	rollLines = 10,        -- сколько строк итога ролла писать в рейд (каждый игрок — отдельной строкой)
	reloadPrompt = true,   -- после убийства босса предложить /reload, чтобы журнал записался на диск
	compactAuto = false,   -- мини-панель сама появляется на пуле босса, если окно закрыто
	versionCheck = true,   -- узнавать о новой версии от других игроков с RaidMinus (рейд, гильдия)
}
ns.RELEASES = "github.com/LeancaVladimir/RaidMinus/releases"
ns.HISTORY = 20 -- сколько прошлых рейдов хранить

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff5050RaidMinus|r: " .. tostring(msg))
end

-------------------------------------------------------------------------------
-- события и таймеры

local frame = CreateFrame("Frame")
local handlers, loaders, timers = {}, {}, {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		frame:RegisterEvent(event)
	end
	tinsert(handlers[event], fn)
end

function ns.OnLoad(fn) tinsert(loaders, fn) end

frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do fn(...) end
end)

-- ns.After(сек, функция) -> таймер; ns.Cancel(таймер)
function ns.After(sec, fn)
	local t = {at = GetTime() + sec, fn = fn}
	tinsert(timers, t)
	return t
end

function ns.Cancel(t)
	if t then t.cancelled = true end
end

frame:SetScript("OnUpdate", function()
	if #timers == 0 then return end
	local now = GetTime()
	for i = #timers, 1, -1 do
		local t = timers[i]
		if t.cancelled then
			tremove(timers, i)
		elseif now >= t.at then
			tremove(timers, i)
			t.fn()
		end
	end
end)

-------------------------------------------------------------------------------
-- помощники

-- string.lower в WoW не трогает кириллицу: А-П -> а-п, Р-Я -> р-я, Ё -> ё
local function LowerCyr(c)
	local b = c:byte()
	if b >= 144 and b <= 159 then return "\208" .. string.char(b + 32) end
	if b >= 160 and b <= 175 then return "\209" .. string.char(b - 32) end
	if b == 129 then return "\209\145" end
end

function ns.Lower(s)
	return (tostring(s or ""):lower():gsub("\208([\128-\191])", LowerCyr))
end

-- имя из списка: точное совпадение без учёта регистра, иначе единственное по началу
function ns.MatchName(query, names)
	query = ns.Lower(query)
	if query == "" then return end
	local found, count = nil, 0
	for _, name in ipairs(names) do
		local low = ns.Lower(name)
		if low == query then return name end
		if low:sub(1, #query) == query then found, count = name, count + 1 end
	end
	if count == 1 then return found end
end

function ns.ValueText(v)
	v = v or 0
	if v > 0 then return "+" .. v end
	return tostring(v)
end

function ns.ValueColor(v)
	v = v or 0
	if v > 0 then return "|cff40ff40" .. ns.ValueText(v) .. "|r" end
	if v < 0 then return "|cffff5050" .. ns.ValueText(v) .. "|r" end
	return "|cff9d9d9d0|r"
end

-- 6300 -> «1:45», 900 -> «15 мин», 40 -> «40 сек»
function ns.Duration(sec)
	sec = math.max(0, math.floor(sec or 0))
	if sec >= 3600 then return format("%d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
	if sec >= 60 then return format("%d мин", math.floor(sec / 60)) end
	return format("%d сек", sec)
end

function ns.ClassHex(class)
	local c = class and RAID_CLASS_COLORS[class]
	if not c then return "ffcccccc" end
	return format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

function ns.ColorName(name, class)
	return "|c" .. ns.ClassHex(class) .. tostring(name) .. "|r"
end

-- обрезка по байтам, не разрезая букву UTF-8
local function CutUTF8(s, limit)
	if #s <= limit then return s end
	local cut = limit
	while cut > 0 do
		local b = s:byte(cut + 1)
		if not b or b < 128 or b >= 192 then break end
		cut = cut - 1
	end
	return s:sub(1, cut)
end

-- склеивает части в сообщения чата (лимит WoW — 255 байт, русская буква — 2 байта)
function ns.Chunks(head, parts, sep, limit)
	limit = limit or 250
	local out, cur = {}, head
	local empty = true
	for _, p in ipairs(parts) do
		local piece = empty and p or (sep .. p)
		if not empty and #cur + #piece > limit then
			tinsert(out, cur)
			cur, empty = "... ", true
			piece = p
		end
		cur = CutUTF8(cur .. piece, limit)
		empty = false
	end
	if not empty or #out == 0 then tinsert(out, cur) end
	return out
end

-- как выглядел бы канал в тестовом рейде
local TEST_CHANNELS = {
	RAID = "|cffff7f00[Рейд]|r", RAID_WARNING = "|cffff4800[Объявление рейду]|r",
	PARTY = "|cffaaaaff[Группа]|r", WHISPER = "|cffff80ff[Шёпот для %s]|r",
}

-- отправка в чат; в тестовом рейде ничего не уходит в чат, только печатается у себя
-- test — сообщение из тестового рейда (даже если в очереди оно дождалось уже настоящего рейда)
function ns.Send(msg, chatType, target, test)
	local s = ns.Session and ns.Session()
	if test or (s and s.test) then
		local label = TEST_CHANNELS[chatType or ""] or "[себе]"
		ns.Print("|cff9d9d9d(тест)|r " .. format(label, tostring(target)) .. " " .. msg)
		return
	end
	if not chatType then
		ns.Print(msg)
		return
	end
	SendChatMessage(msg, chatType, nil, target)
end

function ns.GroupChannel(warning)
	local s = ns.Session and ns.Session()
	if s and s.test then return warning and "RAID_WARNING" or "RAID" end -- тестовый рейд: как будто в рейде
	if GetNumRaidMembers() > 0 then
		if warning and (IsRaidLeader() or IsRaidOfficer()) then return "RAID_WARNING" end
		return "RAID"
	end
	if GetNumPartyMembers() > 0 then return "PARTY" end
end

-- сообщения уходят по очереди с паузой: много строк подряд сервер считает флудом
local chatQueue, chatTimer = {}, nil
local CHAT_GAP = 0.35

local function PumpChat()
	chatTimer = nil
	local item = tremove(chatQueue, 1)
	if not item then return end
	ns.Send(item[1], item[2], item[4], item[3])
	if #chatQueue > 0 then chatTimer = ns.After(CHAT_GAP, PumpChat) end
end

local function Queue(msg, chatType, target)
	local s = ns.Session and ns.Session()
	tinsert(chatQueue, {msg, chatType, s and s.test, target})
	if not chatTimer then chatTimer = ns.After(0, PumpChat) end
end

function ns.Announce(msg, warning) Queue(msg, ns.GroupChannel(warning)) end

-- шёпот через ту же очередь (несколько шёпотов подряд — тоже флуд)
function ns.QueueWhisper(target, msg) Queue(msg, "WHISPER", target) end

-- перерисовать окно и кнопку у миникарты
function ns.Refresh()
	if ns.RefreshUI then ns.RefreshUI() end
	if ns.UpdateLDB then ns.UpdateLDB() end
end

-------------------------------------------------------------------------------
-- запуск

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	RaidMinusDB = RaidMinusDB or {}
	local db = RaidMinusDB
	db.settings = db.settings or {}
	for k, v in pairs(DEFAULTS) do
		if db.settings[k] == nil then db.settings[k] = v end
	end
	-- 0.3.0: «только гер. ЦЛК 25» прятал добычу босса, убитого на обычной сложности (Профа)
	if not db.settings.v3 then
		if db.settings.lootFilter == "heroic" then db.settings.lootFilter = "boss" end
		db.settings.v3 = true
	end
	db.rulesets = db.rulesets or {}
	db.history = db.history or {}
	db.minimap = db.minimap or {}
	ns.DB = db
	for _, fn in ipairs(loaders) do fn() end
end)

-------------------------------------------------------------------------------
-- слеш-команды

local HELP = {
	"|cffffd100/rm|r — окно, |cffffd100/rm мини|r — мини-панель, |cffffd100/rm добыча|r — окно добычи",
	"|cffffd100/rm старт|r — начать рейд, |cffffd100/rm конец|r — завершить",
	"|cffffd100/rm Имя -20 причина|r — свой минус (или +10 — плюс)",
	"|cffffd100/rm ролл [предмет]|r — разыграть (shift+клик по предмету), |cffffd100/rm лут [предмет]|r — в список",
	"|cffffd100/rm правила|r, |cffffd100/rm настройки|r, |cffffd100/rm история|r, |cffffd100/rm версия|r",
	"|cffffd100/rm лог|r — откуда пришла добыча и что отброшено, |cffffd100/rm лог пул|r — пулы боссов и таймер",
	"|cffffd100/rm тест|r — тестовый рейд (25 выдуманных игроков, в чат ничего не уходит), |cffffd100/rm тест босс|r — убить босса (автоминусы, добыча), |cffffd100/rm тест чужой|r — ролл от ответственного, |cffffd100/rm тест ролл|r — броски",
	"Клавиши (Esc, «Назначение клавиш», раздел RaidMinus): окно, мини-панель, |cffffd100минус цели|r — меню правил с цифрами 1-9.",
	"Игроки шепчут вам |cffffd100!минус|r и получают свою сумму.",
}

local function Help()
	ns.Print("v" .. ns.VERSION)
	for _, line in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
end

function ns.Command(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	local c = ns.Lower(cmd)
	local r = ns.Lower(rest)
	if c == "" then
		ns.ToggleWindow()
	elseif c == "старт" or c == "start" then
		ns.StartSession()
	elseif c == "конец" or c == "end" then
		ns.ConfirmEndSession()
	elseif c == "тест" or c == "test" then
		if r == "ролл" or r == "roll" then
			ns.TestRolls()
		elseif r == "босс" or r == "boss" then
			ns.TestBoss()
		elseif r == "чужой" or r == "foreign" then
			ns.TestForeignRoll()
		else
			ns.StartSession(true)
		end
	elseif c == "ролл" or c == "roll" then
		ns.AddLootFromText(rest, true)
	elseif c == "лут" or c == "loot" then
		ns.AddLootFromText(rest, false)
	elseif c == "мини" or c == "mini" then
		ns.ToggleCompact()
	elseif c == "добыча" or c == "drops" then
		ns.ShowLootWindow()
	elseif c == "версия" or c == "version" then
		ns.VersionInfo()
	elseif c == "история" or c == "history" then
		ns.ShowTab("history")
	elseif c == "лог" or c == "log" then
		if r == "пул" or r == "pull" then ns.PrintPullLog() else ns.PrintLootLog() end
	elseif c == "правила" or c == "rules" then
		ns.ShowTab("rules")
	elseif c == "настройки" or c == "config" then
		ns.OpenOptions("general")
	elseif c == "помощь" or c == "help" then
		Help()
	else
		local value, text = rest:match("^([%+%-]?%d+)%s*(.*)$")
		if value then
			ns.AddCustom(cmd, tonumber(value), text)
		else
			Help()
		end
	end
end

SLASH_RAIDMINUS1 = "/rm"
SLASH_RAIDMINUS2 = "/raidminus"
SLASH_RAIDMINUS3 = "/минус"
SlashCmdList.RAIDMINUS = function(msg) ns.Command(msg) end
