-- Проверка версии. Аддон WoW не может сам скачать обновление, поэтому RaidMinus узнаёт о новой
-- версии от других игроков с RaidMinus: при входе в игру и в рейд он шлёт свою версию по скрытому
-- каналу «RaidMinus» в рейд (группу) и гильдию. Увидел версию новее — пишет в чат, где скачать;
-- увидел старее — шепчет её владельцу свою, чтобы тот тоже узнал. Новые версии — на GitHub (ns.RELEASES).

local _, ns = ...

local format, tonumber, ipairs = string.format, tonumber, ipairs

local PREFIX = "RaidMinus"
local RESEND = 300 -- сек: не чаще раза в 5 минут в один канал

local lastSent, replied, told = {}, {}, false
local inGroup = false

-- «0.10.2» > «0.9.9»
function ns.VersionNewer(a, b)
	local pa, pb = {}, {}
	for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
	for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x > y end
	end
	return false
end

local function Send(channel, target)
	local key = channel .. (target or "")
	if lastSent[key] and GetTime() - lastSent[key] < RESEND then return end
	lastSent[key] = GetTime()
	SendAddonMessage(PREFIX, "V:" .. ns.VERSION, channel, target)
end

function ns.AnnounceVersion()
	if not ns.DB.settings.versionCheck or ns.VERSION == "?" then return end
	if GetNumRaidMembers() > 0 then
		Send("RAID")
	elseif GetNumPartyMembers() > 0 then
		Send("PARTY")
	end
	if IsInGuild() then Send("GUILD") end
end

function ns.OnVersionMessage(msg, channel, sender)
	if sender == ns.PlayerName() or not ns.DB.settings.versionCheck then return end
	local v = tostring(msg):match("^V:(%S+)")
	if not v then return end
	if ns.VersionNewer(v, ns.VERSION) then
		if not ns.newest or ns.VersionNewer(v, ns.newest) then ns.newest = v end
		if not told then
			told = true
			ns.Print(format("есть новая версия |cffffd100%s|r (у %s), у вас %s. Скачать: %s", v, sender, ns.VERSION, ns.RELEASES))
		end
	elseif ns.VersionNewer(ns.VERSION, v) and not replied[sender] then
		replied[sender] = true
		SendAddonMessage(PREFIX, "V:" .. ns.VERSION, "WHISPER", sender)
	end
end

function ns.VersionInfo()
	local tail = ns.newest and format(", есть новее: |cffffd100%s|r", ns.newest) or ""
	ns.Print(format("версия %s%s. Новые версии: %s", ns.VERSION, tail, ns.RELEASES))
end

ns.On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
	if prefix == PREFIX then ns.OnVersionMessage(msg, channel, sender) end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
	ns.After(15, ns.AnnounceVersion)
end)

-- вошёл в рейд или группу — сказать версию её участникам
for _, event in ipairs({"RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED"}) do
	ns.On(event, function()
		local now = GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
		if now and not inGroup then ns.After(5, ns.AnnounceVersion) end
		inGroup = now
	end)
end
