-- Главное окно (вариант A, «пульт РЛа»): заголовок со статусом рейда, вкладки, лента последнего
-- действия с «Отменить»; кнопка у миникарты. Вкладки регистрируются через ns.RegisterPage:
-- UI\Players.lua (Минусы), UI\Log.lua, UI\Loot.lua (Розыгрыш), UI\DropsTab.lua (Добыча),
-- UI\Queue.lua (На проверку), UI\RulesTab.lua (Правила — работает и без рейда).

local _, ns = ...
local UI = ns.UI

local format, date, tconcat = string.format, date, table.concat

local W, H = 960, 640
local TABS = {
	{key = "players", name = "Минусы", w = 80},
	{key = "log", name = "Журнал", w = 76},
	{key = "loot", name = "Розыгрыш", w = 90},
	{key = "drops", name = "Добыча", w = 86},
	{key = "queue", name = "На проверку", w = 112},
	{key = "rules", name = "Правила", w = 80, noSession = true},
}

local frame, content, status, noSession, feedText, undoBtn
local startBtn, testBtn, endBtn, testBossBtn
local tabButtons, pages = {}, {}

-- состояние окна (не сохраняется)
ns.ui = {tab = "players", selected = {}, collapsed = {}}

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
	if not s then return "|cff9d9d9dрейд не начат|r" end
	local parts = {}
	if s.test then parts[#parts + 1] = "|cffffd100ТЕСТ|r" end
	parts[#parts + 1] = "рейд с " .. date("%H:%M", s.started)
	parts[#parts + 1] = "свод «" .. tostring(s.ruleset) .. "»"
	if s.boss then parts[#parts + 1] = "сейчас: |cff60e860" .. ns.BossText(s.boss, s.pulls[s.boss]) .. "|r" end
	local n = 0
	for _ in pairs(ns.here) do n = n + 1 end
	parts[#parts + 1] = "игроков: " .. n
	return tconcat(parts, "  ·  ")
end

local function TabLabel(tab)
	if tab.key == "queue" then
		local n = #ns.QueueList()
		if n > 0 then return format("%s |cffff6060%d|r", tab.name, n) end
	elseif tab.key == "drops" and ns.Session() then
		local n = ns.MissingTotal()
		if n > 0 then return format("%s |cffffd100%d|r", tab.name, n) end
	end
	return tab.name
end

local function FeedLine()
	local f = ns.ui.feed
	if not f then
		return "|cff9d9d9dВыберите игроков справа и нажмите правило. Ctrl — несколько, Shift — весь класс.|r"
	end
	return f
end

function ns.RefreshUI()
	if ns.RefreshCompact then ns.RefreshCompact() end
	if ns.RefreshLootWindow then ns.RefreshLootWindow() end
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
	for _, tab in ipairs(TABS) do
		local b = tabButtons[tab.key]
		b:SetLabel(TabLabel(tab))
		b:SetSelected(tab.key == ns.ui.tab)
	end
	feedText:SetText(FeedLine())
	if #ns.LastGroup() > 0 then undoBtn:SetEnabledFlat(true) else undoBtn:SetEnabledFlat(false) end

	local current
	for _, tab in ipairs(TABS) do
		if tab.key == ns.ui.tab then current = tab end
	end
	for key, page in pairs(pages) do
		if page.frame and (key ~= ns.ui.tab or (not s and not current.noSession)) then page.frame:Hide() end
	end
	if not s and not current.noSession then
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

-- поставили минусы кликом: строка в ленте (и всплывашка, если окно закрыто)
function ns.OnEventsAdded(made)
	local names = {}
	for _, ev in ipairs(made) do names[#names + 1] = ev.player end
	local ev = made[1]
	local mode = ev.ann or ns.DB.settings.announce
	local when = mode == "off" and "без объявления" or (mode == "instant" and "объявлю сразу" or "объявлю после боя")
	ns.ui.feed = format("Поставлено: %s %s (%s) · |cff9d9d9d%s|r", tconcat(names, ", "), ns.ValueColor(ev.value),
		ns.EventChat(ev), when)
	if (not frame or not frame:IsShown()) and ns.ShowToast then ns.ShowToast(made) end
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
	local title = UI.TitleBar(frame, "Raid|cffff5050Minus|r |cffaaaaaav" .. ns.VERSION .. "|r")
	status = UI.Text(frame, "GameFontHighlightSmall")
	status:SetPoint("LEFT", title, "RIGHT", 14, 0)
	status:SetPoint("RIGHT", frame, "TOPRIGHT", -34, -14)
	status:SetHeight(14)

	-- вкладки
	local prev
	for _, tab in ipairs(TABS) do
		local key = tab.key
		local b = UI.FlatButton(frame, tab.name, tab.w, 26, function() ns.ShowTab(key) end, "tab")
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("TOPLEFT", 10, -36) end
		tabButtons[key] = b
		prev = b
	end
	local line = UI.Flat(frame, "ARTWORK", 0.16, 0.18, 0.22, 1)
	line:SetPoint("TOPLEFT", 10, -62)
	line:SetPoint("TOPRIGHT", -10, -62)
	line:SetHeight(1)

	-- кнопки справа от вкладок
	local settingsBtn = UI.FlatButton(frame, "Настройки", 84, 22, function() ns.OpenOptions("general") end, "ghost")
	settingsBtn:SetPoint("TOPRIGHT", -10, -36)
	local miniBtn = UI.FlatButton(frame, "Мини", 54, 22, function()
		frame:Hide()
		ns.ShowCompact()
	end, "ghost")
	miniBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -4, 0)
	miniBtn.tooltip = function(tt)
		tt:SetText("Мини-панель")
		tt:AddLine("Маленькая панель поверх игры: цель, быстрые кнопки правил босса, счётчики. Окно закроется.", 1, 1, 1, true)
	end
	endBtn = UI.Button(frame, "Завершить рейд", 120, function() ns.ConfirmEndSession() end)
	endBtn:SetPoint("RIGHT", miniBtn, "LEFT", -8, 0)
	testBtn = UI.Button(frame, "Тест", 60, function() ns.StartSession(true) end)
	testBtn:SetPoint("RIGHT", miniBtn, "LEFT", -8, 0)
	UI.Tooltip(testBtn, function(tt)
		tt:SetText("Тестовый рейд")
		tt:AddLine("25 выдуманных игроков. Объявления и шёпот печатаются только у вас, в чат ничего не уходит.", 1, 1, 1, true)
	end)
	startBtn = UI.Button(frame, "Начать рейд", 110, function() ns.StartSession() end)
	startBtn:SetPoint("RIGHT", testBtn, "LEFT", -4, 0)
	testBossBtn = UI.Button(frame, "Тест: босс", 92, function() ns.TestBoss() end)
	testBossBtn:SetPoint("RIGHT", endBtn, "LEFT", -4, 0)
	UI.Tooltip(testBossBtn, function(tt)
		tt:SetText("Тест: убить следующего босса")
		tt:AddLine("Пул и убийство босса, «автоминусы» по его правилам, шёпот !минус от наказанного и добыча — как будто тело открыл ответственный с RaidRoll. В чат ничего не уходит.", 1, 1, 1, true)
	end)

	content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 10, -70)
	content:SetPoint("BOTTOMRIGHT", -10, 38)

	-- лента: последнее действие и «Отменить»
	local feed = CreateFrame("Frame", nil, frame)
	feed:SetPoint("BOTTOMLEFT", 1, 1)
	feed:SetPoint("BOTTOMRIGHT", -1, 1)
	feed:SetHeight(30)
	local feedBg = UI.Flat(feed, "BACKGROUND", 0.08, 0.09, 0.11, 1)
	feedBg:SetAllPoints()
	local feedLine = UI.Flat(feed, "ARTWORK", 0.16, 0.18, 0.22, 1)
	feedLine:SetPoint("TOPLEFT")
	feedLine:SetPoint("TOPRIGHT")
	feedLine:SetHeight(1)
	undoBtn = UI.FlatButton(feed, "Отменить", 84, 20, function() ns.UndoLast() end, "ghost")
	undoBtn:SetPoint("RIGHT", -8, 0)
	undoBtn.tooltip = function(tt)
		tt:SetText("Отменить последний клик")
		tt:AddLine("Если минус ещё не объявлен — удаляется молча, если объявлен — снимается с объявлением.", 1, 1, 1, true)
	end
	feedText = UI.Text(feed, "GameFontHighlightSmall")
	feedText:SetPoint("LEFT", 12, 0)
	feedText:SetPoint("RIGHT", undoBtn, "LEFT", -10, 0)
	feedText:SetHeight(14)

	noSession = CreateFrame("Frame", nil, content)
	noSession:SetAllPoints(content)
	local text = UI.Text(noSession, "GameFontHighlight", "CENTER")
	text:SetPoint("CENTER", 0, 20)
	text:SetWidth(560)
	text:SetText("Рейд не начат.\n\n«Начать рейд» — аддон запомнит состав и начнёт журнал минусов.\n"
		.. "«Тест» — попробовать на 25 выдуманных игроках, в чат ничего не уходит.\n\n"
		.. "|cff9d9d9dПравила можно править и без рейда — вкладка «Правила». Все команды — /rm помощь.|r")
end

function ns.ShowWindow()
	if not frame then CreateWindow() end
	frame:Show()
	ns.RefreshUI()
end

function ns.HideWindow()
	if frame then frame:Hide() end
end

function ns.WindowShown() return frame and frame:IsShown() end

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
			if button == "RightButton" then ns.ToggleCompact() else ns.ToggleWindow() end
		end,
		OnTooltipShow = function(tt)
			tt:AddLine("Raid|cffff5050Minus|r |cffaaaaaav" .. ns.VERSION .. "|r")
			if ns.newest then tt:AddLine("Есть новая версия " .. ns.newest .. ": " .. ns.RELEASES, 1, 0.82, 0, true) end
			local s = ns.Session()
			if s then
				local active = 0
				for _, ev in ipairs(s.events) do
					if ev.status ~= "cancelled" then active = active + 1 end
				end
				tt:AddLine(format("%s: записей %d, добычи в розыгрыше %d", s.test and "Тестовый рейд" or "Рейд", active, #s.loot), 1, 1, 1)
				local missing = ns.MissingTotal()
				if missing > 0 then tt:AddLine("Добыча не в розыгрыше: " .. missing, 1, 0.82, 0) end
			else
				tt:AddLine("Рейд не начат", 0.6, 0.6, 0.6)
			end
			tt:AddLine(" ")
			tt:AddLine("ЛКМ: окно", 0.7, 0.7, 0.7)
			tt:AddLine("ПКМ: мини-панель", 0.7, 0.7, 0.7)
		end,
	})
	ns.UpdateLDB()
	local DBI = LibStub("LibDBIcon-1.0", true)
	if DBI then
		DBI:Register("RaidMinus", ns.ldb, ns.DB.minimap)
		ns.DBI = DBI
	end
end)
