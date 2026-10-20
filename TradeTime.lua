-- Время на передачу добычи. Предмет из рейда можно передать игрокам, которые были в рейде, только 2 часа
-- после того, как его взяли из тела. Откуда аддон знает, сколько осталось:
--   точно — предмет в моей сумке: подсказка «можно передать … в течение 1 ч. 12 мин.» (я ответственный за добычу);
--   точно — ответственный с RaidMinus прислал время из своей сумки (Sync.lua, TT);
--   почти точно — строка «Холпал получает добычу» (пошли 2 часа, LootList.lua);
--   оценка (~) — 2 часа от появления предмета в списке.
-- Здесь же: мой обмен с игроком — он «получил» предмет (выиграл один, а отдали другому — видно сразу),
-- и предупреждение, когда на передачу неразданного предмета остаётся мало времени.

local _, ns = ...

local format, tinsert, sort = string.format, table.insert, table.sort
local ipairs, pairs, tonumber = ipairs, pairs, tonumber

local WARN = {900, 300} -- предупредить за 15 и за 5 минут

local function Settings() return ns.DB.settings end

-- «1 ч. 12 мин.» / «59 мин.» / «1 hour 5 min» -> секунды
function ns.ParseDuration(text)
	text = tostring(text or "")
	local h = tonumber(text:match("(%d+)%s*ч")) or tonumber(text:match("(%d+)%s*[Hh]our")) or 0
	local m = tonumber(text:match("(%d+)%s*мин")) or tonumber(text:match("(%d+)%s*[Mm]in")) or 0
	local s = tonumber(text:match("(%d+)%s*сек")) or tonumber(text:match("(%d+)%s*[Ss]ec")) or 0
	if h + m + s == 0 then return end
	return h * 3600 + m * 60 + s
end

local tradePattern
local function TradePattern()
	if tradePattern == nil then
		tradePattern = BIND_TRADE_TIME_REMAINING and ns.ToPattern(BIND_TRADE_TIME_REMAINING) or false
	end
	return tradePattern
end

-- из строки подсказки: сколько секунд осталось на передачу
function ns.TradeSecondsFromLine(line)
	if not line then return end
	local p = TradePattern()
	local rest = p and line:match(p)
	if not rest then rest = line:match("в течение (.+)%.?$") or line:match("for the next (.+)%.?$") end
	return rest and ns.ParseDuration(rest)
end

-- времена по номерам предметов -> записи розыгрыша, которые ещё никому не отданы (раньше упавшие — первыми)
function ns.ApplyTradeTimes(byId, mine)
	local now = time()
	for id, list in pairs(byId) do
		sort(list)
		local entries = {}
		for _, e in ipairs(ns.LootByItem(id)) do
			if not e.receiver and (mine or not e.exact) then tinsert(entries, e) end
		end
		sort(entries, function(a, b) return (a.t or 0) < (b.t or 0) end)
		for i, e in ipairs(entries) do
			local sec = list[i]
			if not sec then break end
			e.expires, e.exact = now + sec, true
			if mine then e.holder = ns.PlayerName() end
		end
	end
	ns.Refresh()
end

-- сумка: предметы из списка розыгрыша, у которых есть время на передачу
local tip
function ns.ScanBagsForTrade()
	local s = ns.Session()
	if not s or s.test or #s.loot == 0 then return end
	local wanted = {}
	for _, e in ipairs(s.loot) do
		if not e.receiver then wanted[e.item] = true end
	end
	if not tip then
		tip = CreateFrame("GameTooltip", "RaidMinusTradeTip", UIParent, "GameTooltipTemplate")
	end
	local byId, found = {}, false
	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) or 0 do
			local id = ns.ItemId(GetContainerItemLink(bag, slot))
			if id and wanted[id] then
				tip:SetOwner(UIParent, "ANCHOR_NONE")
				tip:ClearLines()
				tip:SetBagItem(bag, slot)
				for i = 1, tip:NumLines() or 0 do
					local fs = _G["RaidMinusTradeTipTextLeft" .. i]
					local sec = ns.TradeSecondsFromLine(fs and fs:GetText())
					if sec then
						byId[id] = byId[id] or {}
						tinsert(byId[id], sec)
						found = true
						break
					end
				end
				tip:Hide()
			end
		end
	end
	if not found then return end
	ns.ApplyTradeTimes(byId, true)
	if ns.SyncTradeTimes then ns.SyncTradeTimes(byId) end
end

local scanTimer
local function ScheduleScan(delay)
	ns.Cancel(scanTimer)
	scanTimer = ns.After(delay or 1.5, function()
		scanTimer = nil
		ns.ScanBagsForTrade()
	end)
end

ns.On("BAG_UPDATE", function() if ns.Session() then ScheduleScan() end end)
ns.On("PLAYER_ENTERING_WORLD", function() ScheduleScan(8) end)

-- сколько осталось на передачу: секунды, точно ли; nil — уже отдан (время не нужно)
function ns.TradeLeft(e)
	if not e or e.receiver then return end
	local expires, exact = ns.TradeExpires(e)
	return expires - time(), exact
end

-- подпись для окон: «передать: 1:42», «~42 мин», красным — меньше 10 минут
function ns.TradeText(e, short)
	local left, exact = ns.TradeLeft(e)
	if not left then return "" end
	if left <= 0 then return "|cff707070передать нельзя|r" end
	local color = left < 600 and "ffff5050" or (left < 1800 and "ffffd100" or "ff9d9d9d")
	return format("|c%s%s%s%s|r", color, short and "" or "передать: ", exact and "" or "~", ns.Duration(left))
end

-- предупреждение: неразданный предмет, а время на передачу кончается
local function CheckWarnings()
	local s = ns.Session()
	if not s or not Settings().tradeWarn or not ns.CanManageLoot() then return end
	for _, e in ipairs(s.loot) do
		local left = ns.TradeLeft(e)
		if left and left > 0 then
			for i, limit in ipairs(WARN) do
				local key = "warned" .. i
				if left <= limit and not e[key] then
					e[key] = true
					local who = e.winner and ("выиграл " .. e.winner) or (e.result and "никто не выиграл" or "не разыгран")
					ns.Print(format("|cffff5050на передачу осталось %s:|r %s (%s).", ns.Duration(left), e.link, who))
				end
			end
		end
	end
end

local warnTimer
local function WarnLoop()
	CheckWarnings()
	warnTimer = ns.After(60, WarnLoop)
end
ns.OnLoad(function() warnTimer = ns.After(30, WarnLoop) end)

-------------------------------------------------------------------------------
-- мой обмен: кому отдал предмет из списка розыгрыша — тот его и получил

local trade = {}

local function Snapshot()
	trade.items = {}
	for i = 1, 6 do
		local link = GetTradePlayerItemLink(i)
		if link then tinsert(trade.items, link) end
	end
end

ns.On("TRADE_SHOW", function()
	trade = {target = UnitName("NPC"), items = {}}
end)
ns.On("TRADE_PLAYER_ITEM_CHANGED", function() if trade.target then Snapshot() end end)
ns.On("TRADE_ACCEPT_UPDATE", function() if trade.target then Snapshot() end end)

-- обмен состоялся (тестам — напрямую)
function ns.OnTradeComplete(target, links)
	if not ns.Session() or not target then return end
	for _, link in ipairs(links or {}) do
		local id = ns.ItemId(link)
		if id and #ns.LootByItem(id) > 0 then ns.AutoReceiver(id, target, "обмен") end
	end
end

ns.On("UI_INFO_MESSAGE", function(msg)
	if msg == ERR_TRADE_COMPLETE and trade.target then
		ns.OnTradeComplete(trade.target, trade.items)
		trade = {}
	end
end)
