-- Главное окно: строка рейда с кнопками, вкладки «Минусы», «Журнал», «Розыгрыш»; кнопка у миникарты.
-- Вкладки регистрируются из UI\Players.lua, UI\Log.lua, UI\Loot.lua через ns.RegisterPage.

local _, ns = ...
local UI = ns.UI

local format, date = string.format, date

local W, H = 780, 520
local TABS = {
	{key = "players", name = "Минусы"},
	{key = "log", name = "Журнал"},
	{key = "loot", name = "Розыгрыш"},
	{key = "queue", name = "На проверку"},
}

local frame, content, status, noSession
local startBtn, testBtn, endBtn, testBossBtn
local tabButtons, pages = {}, {}

-- состояние окна (не сохраняется)
ns.ui = {tab = "players", selected = {}}

function ns.RegisterPage(key, create, update)
	pages[key] = {create = create, update = update}
end

local function PageFrame(key)
	local page = pages[key]
	if not page.frame then
		page.frame = CreateFrame("Frame", nil, content)
		page.frame:SetAllPoints(content)
		page.create(page.frame)
	end
	return page.frame
end

local function StatusText()
	local s = ns.Session()
	if not s then return "|cff9d9d9dРейд не начат|r" end
	local parts = {}
	if s.test then parts[#parts + 1] = "|cffffd100ТЕСТ|r" end
	parts[#parts + 1] = "рейд с " .. date("%H:%M", s.started)
	if s.boss then parts[#parts + 1] = "сейчас: " .. ns.BossText(s.boss, s.pulls[s.boss]) end
	local n = 0
	for _ in pairs(ns.here) do n = n + 1 end
	parts[#parts + 1] = "игроков: " .. n
	return table.concat(parts, "  ·  ")
end

function ns.RefreshUI()
	if not frame or not frame:IsShown() then return end
	local s = ns.Session()
	status:SetText(StatusText())
	if s then
		startBtn:Hide()
		testBtn:Hide()
		endBtn:Show()
	else
		startBtn:Show()
		testBtn:Show()
		endBtn:Hide()
	end
	if s and s.test then testBossBtn:Show() else testBossBtn:Hide() end
	local waiting = #ns.QueueList()
	tabButtons.queue:SetText(waiting > 0 and format("|cffffd100На проверку (%d)|r", waiting) or "На проверку")
	for _, tab in ipairs(TABS) do
		local b = tabButtons[tab.key]
		if tab.key == ns.ui.tab then b:Disable() else b:Enable() end
	end
	for key, page in pairs(pages) do
		if page.frame and (key ~= ns.ui.tab or not s) then page.frame:Hide() end
	end
	if not s then
		noSession:Show()
		return
	end
	noSession:Hide()
	local f = PageFrame(ns.ui.tab)
	f:Show()
	pages[ns.ui.tab].update(f)
end

-- быстрое обновление во время ролла (таймер, новые броски)
function ns.RefreshRoll()
	if frame and frame:IsShown() and ns.ui.tab == "loot" then ns.RefreshUI() end
end

function ns.ShowTab(key)
	ns.ui.tab = key
	ns.ShowWindow()
end

-- DBM сообщил о пуле: показываем правила этого босса
function ns.OnBossChanged(key)
	ns.ui.viewBoss = key
end

function ns.OnLootAdded(e)
	ns.ui.loot = e.id
end

local function CreateWindow()
	frame = CreateFrame("Frame", "RaidMinusFrame", UIParent)
	frame:SetWidth(W)
	frame:SetHeight(H)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.DB.pos = {point, relPoint, x, y}
	end)
	frame:SetScript("OnShow", ns.RefreshUI)
	local pos = ns.DB.pos
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("CENTER")
	end
	tinsert(UISpecialFrames, "RaidMinusFrame") -- закрытие по Esc

	UI.Panel(frame)
	UI.TitleBar(frame, "Raid|cffff5050Minus|r |cffaaaaaav" .. ns.VERSION .. "|r")

	-- строка рейда
	local settingsBtn = UI.Button(frame, "Настройки", 90, function() ns.OpenOptions("general") end)
	settingsBtn:SetPoint("TOPRIGHT", -10, -36)
	local rulesBtn = UI.Button(frame, "Правила", 80, function() ns.OpenOptions("rules") end)
	rulesBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -4, 0)
	endBtn = UI.Button(frame, "Завершить рейд", 120, function() ns.ConfirmEndSession() end)
	endBtn:SetPoint("RIGHT", rulesBtn, "LEFT", -12, 0)
	testBtn = UI.Button(frame, "Тест", 60, function() ns.StartSession(true) end)
	testBtn:SetPoint("RIGHT", rulesBtn, "LEFT", -12, 0)
	UI.Tooltip(testBtn, function(tt)
		tt:SetText("Тестовый рейд")
		tt:AddLine("25 выдуманных игроков. Объявления и шёпот печатаются только у вас, в чат ничего не уходит.", 1, 1, 1, true)
	end)
	startBtn = UI.Button(frame, "Начать рейд", 110, function() ns.StartSession() end)
	startBtn:SetPoint("RIGHT", testBtn, "LEFT", -4, 0)
	testBossBtn = UI.Button(frame, "Тест: босс", 100, function() ns.TestBoss() end)
	testBossBtn:SetPoint("RIGHT", endBtn, "LEFT", -4, 0)
	UI.Tooltip(testBossBtn, function(tt)
		tt:SetText("Тест: убить следующего босса")
		tt:AddLine("Пул и убийство босса, «автоминусы» по его правилам во вкладку «На проверку», шёпот !минус от наказанного и окошко с добычей. В чат ничего не уходит.", 1, 1, 1, true)
	end)

	status = UI.Text(frame, "GameFontHighlight")
	status:SetPoint("TOPLEFT", 12, -40)
	status:SetPoint("RIGHT", testBossBtn, "LEFT", -8, 0)
	status:SetHeight(16) -- одна строка, лишнее обрезается

	-- вкладки
	local prev
	for _, tab in ipairs(TABS) do
		local key = tab.key
		local b = UI.Button(frame, tab.name, 110, function() ns.ShowTab(key) end)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 10, -66) end
		tabButtons[key] = b
		prev = b
	end

	content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 10, -96)
	content:SetPoint("BOTTOMRIGHT", -10, 10)

	noSession = CreateFrame("Frame", nil, content)
	noSession:SetAllPoints(content)
	local text = UI.Text(noSession, "GameFontHighlight", "CENTER")
	text:SetPoint("CENTER", 0, 20)
	text:SetWidth(520)
	text:SetText("Рейд не начат.\n\n«Начать рейд» — аддон запомнит состав и начнёт журнал минусов.\n"
		.. "«Тест» — попробовать на 25 выдуманных игроках, в чат ничего не уходит.\n\n"
		.. "|cff9d9d9dПравила — кнопка «Правила» или /rm правила. Все команды — /rm помощь.|r")
end

function ns.ShowWindow()
	if not frame then CreateWindow() end
	frame:Show()
	ns.RefreshUI()
end

function ns.ToggleWindow()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		ns.ShowWindow()
	end
end

-------------------------------------------------------------------------------
-- кнопка у миникарты

function ns.UpdateLDB()
	if not ns.ldb then return end
	local s = ns.Session()
	ns.ldb.text = s and (s.test and "RaidMinus: тест" or "RaidMinus: рейд") or "RaidMinus"
end

ns.OnLoad(function()
	local LDB = LibStub("LibDataBroker-1.1", true)
	if not LDB then return end
	ns.ldb = LDB:NewDataObject("RaidMinus", {
		type = "launcher",
		text = "RaidMinus",
		icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
		OnClick = function(_, button)
			if button == "RightButton" then ns.OpenOptions("rules") else ns.ToggleWindow() end
		end,
		OnTooltipShow = function(tt)
			tt:AddLine("Raid|cffff5050Minus|r |cffaaaaaav" .. ns.VERSION .. "|r")
			local s = ns.Session()
			if s then
				local active = 0
				for _, ev in ipairs(s.events) do
					if ev.status ~= "cancelled" then active = active + 1 end
				end
				tt:AddLine(format("%s: записей %d, добычи %d", s.test and "Тестовый рейд" or "Рейд", active, #s.loot), 1, 1, 1)
			else
				tt:AddLine("Рейд не начат", 0.6, 0.6, 0.6)
			end
			tt:AddLine(" ")
			tt:AddLine("ЛКМ: окно", 0.7, 0.7, 0.7)
			tt:AddLine("ПКМ: правила", 0.7, 0.7, 0.7)
		end,
	})
	ns.UpdateLDB()
	local DBI = LibStub("LibDBIcon-1.0", true)
	if DBI then
		DBI:Register("RaidMinus", ns.ldb, ns.DB.minimap)
		ns.DBI = DBI
	end
end)
