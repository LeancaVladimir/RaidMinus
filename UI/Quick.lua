-- Быстрые минусы в бою (из варианта C):
--   «минус цели» — клавиша (Назначение клавиш → RaidMinus) открывает у курсора меню правил текущего
--     босса и быстрых «Общих» с цифрами 1–9: цифра — поставить цели (или выбранным в окне), Esc — закрыть;
--   мини-панель — маленькое окно поверх игры: кому, быстрые кнопки, счётчики «проверка» и «добыча»;
--   всплывашка — после клика вне окна: что поставлено и «Отменить».

local _, ns = ...
local UI = ns.UI

local format, tinsert, tconcat = string.format, table.insert, table.concat
local ipairs, floor = ipairs, math.floor

local MAX_MENU, MAX_QUICK = 12, 10
local MODIFIERS = {LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true}
local MENU_W, ROW_H = 300, 22

BINDING_HEADER_RAIDMINUS = "RaidMinus"
BINDING_NAME_RAIDMINUS_TOGGLE = "Окно RaidMinus"
BINDING_NAME_RAIDMINUS_COMPACT = "Мини-панель"
BINDING_NAME_RAIDMINUS_TARGET = "Минус цели (меню с цифрами 1-9)"
BINDING_NAME_RAIDMINUS_LOOT = "Окно «Добыча»"

function RaidMinus_Toggle() ns.ToggleWindow() end
function RaidMinus_ToggleCompact() ns.ToggleCompact() end
function RaidMinus_TargetMenu() ns.TargetMenu() end
function RaidMinus_LootWindow() ns.ShowLootWindow() end

-------------------------------------------------------------------------------
-- кому и какие правила

-- цель из рейда, иначе выбранные в окне
function ns.QuickTargets()
	local s = ns.Session()
	if not s then return {} end
	local target = UnitExists("target") and UnitIsPlayer("target") and UnitName("target")
	if target and s.roster[target] then return {target}, true end
	return ns.SelectedNames()
end

-- правила для быстрых кнопок: включённые правила текущего босса (с автоматикой — её можно поставить
-- и вручную), затем «Общие» с пометкой «быстрая»; пока быстрых нет — первые «Общие»
function ns.QuickRules()
	local rs = ns.ActiveRuleset()
	local out = {}
	local boss = ns.CurrentBoss() or ns.ui.viewBoss
	if boss and boss ~= "general" then
		for _, r in ipairs(ns.RulesFor(rs, boss)) do
			if not r.off then tinsert(out, r) end
		end
	end
	local quick = 0
	for _, r in ipairs(ns.RulesFor(rs, "general")) do
		if not r.off and r.quick then
			tinsert(out, r)
			quick = quick + 1
		end
	end
	if quick == 0 then
		local added = 0
		for _, r in ipairs(ns.RulesFor(rs, "general")) do
			if not r.off and added < 4 then
				tinsert(out, r)
				added = added + 1
			end
		end
	end
	return out
end

local function ApplyQuick(rule)
	local names = ns.QuickTargets()
	if #names == 0 then
		ns.Print("нет цели из рейда и никто не выбран в окне.")
		return
	end
	ns.AddEvents(names, rule)
end

local function ValueLabel(r)
	if r.kick and r.value == 0 then return "|cffff5050кик|r" end
	return ns.ValueColor(r.value)
end

local function WhoText()
	local names, isTarget = ns.QuickTargets()
	if #names == 0 then return "|cff9d9d9dнет цели — выберите игрока в окне или возьмите в цель|r" end
	if #names == 1 then
		local s = ns.Session()
		local p = s and s.roster[names[1]]
		local role = ns.PlayerRole(names[1])
		return format("%s %s %s · итого %s", isTarget and "Цель:" or "Выбран:", ns.ColorName(names[1], p and p.class),
			ns.RoleName(role, true), ns.StateText(names[1], true))
	end
	return format("Выбрано: %d (%s)", #names, tconcat(names, ", "))
end

-------------------------------------------------------------------------------
-- меню у курсора

local menu, menuRows, menuTimer = nil, {}, nil

local function CloseMenu()
	if menu then menu:Hide() end
	ns.Cancel(menuTimer)
end

local function MenuRow(i)
	local row = menuRows[i]
	if row then return row end
	row = UI.FlatButton(menu, "", MENU_W - 8, ROW_H, function(self)
		CloseMenu()
		if self.rule then ApplyQuick(self.rule) end
	end, "row")
	row:SetPoint("TOPLEFT", 4, -30 - (i - 1) * ROW_H)
	row.label:SetFontObject("GameFontHighlightSmall")
	row.label:SetPoint("RIGHT", -48, 0)
	row.num = UI.Text(row, "GameFontNormal", "CENTER")
	row.num:SetPoint("LEFT", 2, 0)
	row.num:SetWidth(16)
	row.label:SetPoint("LEFT", 26, 0)
	row.value = UI.Text(row, "GameFontHighlight", "RIGHT")
	row.value:SetPoint("RIGHT", -6, 0)
	row.value:SetWidth(40)
	menuRows[i] = row
	return row
end

local function CreateMenu()
	menu = CreateFrame("Frame", "RaidMinusTargetMenu", UIParent)
	menu:SetWidth(MENU_W)
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	UI.Panel(menu)
	local head = UI.Flat(menu, "ARTWORK", 0.16, 0.18, 0.24, 1)
	head:SetPoint("TOPLEFT", 1, -1)
	head:SetPoint("TOPRIGHT", -1, -1)
	head:SetHeight(22)
	local accent = UI.Flat(menu, "OVERLAY", 0.85, 0.3, 0.3, 1)
	accent:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
	accent:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
	accent:SetHeight(2)
	menu.title = UI.Text(menu, "GameFontHighlightSmall")
	menu.title:SetPoint("LEFT", head, "LEFT", 8, 0)
	menu.title:SetPoint("RIGHT", head, "RIGHT", -8, 0)
	menu.hint = UI.Text(menu, "GameFontDisableSmall")
	menu.hint:SetText("1-9 — поставить · 0 — окно · Esc — закрыть")
	menu:EnableKeyboard(true)
	menu:SetScript("OnKeyDown", function(self, key)
		if MODIFIERS[key] then return end -- Shift/Ctrl/Alt сами по себе меню не закрывают
		local n = tonumber(key)
		if n == 0 then
			CloseMenu()
			ns.ShowTab("players")
		elseif n and menuRows[n] and menuRows[n]:IsShown() and menuRows[n].rule then
			CloseMenu()
			ApplyQuick(menuRows[n].rule)
		else
			CloseMenu() -- любая другая клавиша закрывает меню (и не идёт в игру один раз)
		end
	end)
	tinsert(UISpecialFrames, "RaidMinusTargetMenu")
end

function ns.TargetMenu()
	if not ns.Session() then
		ns.Print("рейд не начат.")
		return
	end
	local names = ns.QuickTargets()
	if #names == 0 then
		ns.Print("возьмите игрока рейда в цель (или выберите в окне) и нажмите клавишу ещё раз.")
		return
	end
	if not menu then CreateMenu() end
	local s = ns.Session()
	local boss = ns.CurrentBoss()
	local who = #names == 1 and ns.ColorName(names[1], s.roster[names[1]] and s.roster[names[1]].class) or (#names .. " игроков")
	menu.title:SetText(format("Минус: %s  |cff8e8e9b%s|r", who, boss and ns.BossText(boss, s.pulls[boss]) or ""))
	local list = ns.QuickRules()
	local n = math.min(#list, MAX_MENU)
	for i = 1, math.max(n, #menuRows) do
		local r = list[i]
		if r and i <= n then
			local row = MenuRow(i)
			row.rule = r
			row.num:SetText(i <= 9 and tostring(i) or "")
			row:SetLabel(ns.RuleText(r))
			row.value:SetText(ValueLabel(r))
			local c = ns.KIND_COLORS[ns.RuleKind(r)]
			row:SetTextColor(r.boss == "general" and {1, 0.88, 0.6} or c)
			row:Show()
		elseif menuRows[i] then
			menuRows[i]:Hide()
		end
	end
	menu.hint:ClearAllPoints()
	menu.hint:SetPoint("TOPLEFT", 8, -34 - n * ROW_H)
	menu:SetHeight(30 + n * ROW_H + 24)
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 20, y / scale + 10)
	menu:Show()
	ns.Cancel(menuTimer)
	menuTimer = ns.After(10, CloseMenu)
end

-------------------------------------------------------------------------------
-- мини-панель

local compact, who, info, quickButtons, counters = nil, nil, nil, {}, {}

local function CreateCompact()
	compact = CreateFrame("Frame", "RaidMinusCompact", UIParent)
	compact:SetWidth(368)
	compact:SetFrameStrata("MEDIUM")
	compact:SetClampedToScreen(true)
	compact:SetMovable(true)
	compact:EnableMouse(true)
	compact:RegisterForDrag("LeftButton")
	compact:SetScript("OnDragStart", compact.StartMoving)
	compact:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.DB.compactPos = {point, relPoint, x, y}
	end)
	local pos = ns.DB.compactPos
	if pos then
		compact:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		compact:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -180)
	end
	UI.Panel(compact)
	local title, close = UI.TitleBar(compact, "Raid|cffff5050Minus|r")
	close:SetScript("OnClick", function() ns.HideCompact() end)
	info = UI.Text(compact, "GameFontHighlightSmall")
	info:SetPoint("LEFT", title, "RIGHT", 10, 0)
	info:SetPoint("RIGHT", compact, "TOPRIGHT", -54, -14)
	info:SetHeight(14)
	local expand = UI.FlatButton(compact, "Окно", 44, 18, function()
		ns.HideCompact()
		ns.ShowTab("players")
	end, "ghost")
	expand:SetPoint("TOPRIGHT", -26, -5)

	who = UI.Text(compact, "GameFontHighlightSmall")
	who:SetPoint("TOPLEFT", 10, -36)
	who:SetPoint("RIGHT", compact, "RIGHT", -10, 0)
	who:SetHeight(14)

	for i = 1, MAX_QUICK do
		local b = UI.FlatButton(compact, "", 172, 24, function(self)
			if self.rule then ApplyQuick(self.rule) end
		end, "ghost")
		b.noFit = true -- кнопки стоят сеткой в два столбца
		b.label:SetJustifyH("LEFT")
		b.label:SetFontObject("GameFontHighlightSmall")
		b.label:SetPoint("RIGHT", -36, 0)
		b.value = UI.Text(b, "GameFontHighlightSmall", "RIGHT")
		b.value:SetPoint("RIGHT", -6, 0)
		b.value:SetWidth(32)
		local col, line = (i - 1) % 2, floor((i - 1) / 2)
		b:SetPoint("TOPLEFT", 10 + col * 176, -56 - line * 27)
		b.tooltip = function(tt, self)
			if not self.rule then return false end
			tt:SetText(ns.RuleText(self.rule), 1, 1, 1, true)
			tt:AddLine("Ставится цели из рейда или выбранным в окне", 0.7, 0.7, 0.7, true)
		end
		quickButtons[i] = b
	end

	local function Counter(text, w, onClick)
		local b = UI.FlatButton(compact, text, w, 20, onClick, "ghost")
		tinsert(counters, b)
		return b
	end
	counters.queue = Counter("Проверка", 96, function() ns.ShowTab("queue") end)
	counters.drops = Counter("Добыча", 90, function() ns.ShowLootWindow() end)
	counters.undo = Counter("Отменить", 80, function() ns.UndoLast() end)
	compact:SetScript("OnUpdate", function(self, elapsed)
		self.t = (self.t or 0) + elapsed
		if self.t > 1 then
			self.t = 0
			ns.RefreshCompact()
		end
	end)
end

function ns.RefreshCompact()
	if not compact or not compact:IsShown() then return end
	local s = ns.Session()
	if not s then
		info:SetText("|cff9d9d9dрейд не начат|r")
	else
		local boss = s.boss
		local f = ns.CurrentFight and ns.CurrentFight()
		local fightText = ""
		if f and not f.over and InCombatLockdown() then
			local sec = floor(GetTime() - f.start)
			fightText = format(" · |cffff8040в бою %d:%02d|r", floor(sec / 60), sec % 60)
		end
		info:SetText((boss and ns.BossText(boss, s.pulls[boss]) or "босс не пулили") .. fightText)
	end
	who:SetText(WhoText())
	local list = ns.QuickRules()
	local shown = 0
	for i, b in ipairs(quickButtons) do
		local r = list[i]
		if r then
			b.rule = r
			b:SetLabel((i <= 9 and ("|cffffd100" .. i .. "|r ") or "") .. ns.ShortText(ns.RuleText(r)))
			b.value:SetText(ValueLabel(r))
			b:Show()
			shown = i
		else
			b.rule = nil
			b:Hide()
		end
	end
	local lines = math.max(1, math.ceil(shown / 2))
	local y = -56 - lines * 27 - 4
	local queue = #ns.QueueList()
	counters.queue:SetLabel(queue > 0 and format("Проверка |cffff6060%d|r", queue) or "Проверка")
	local missing = s and ns.MissingTotal() or 0
	counters.drops:SetLabel(missing > 0 and format("Добыча |cffffd100%d|r", missing) or "Добыча")
	counters.undo:SetEnabledFlat(#ns.LastGroup() > 0)
	counters.queue:ClearAllPoints()
	counters.queue:SetPoint("TOPLEFT", 10, y)
	counters.drops:ClearAllPoints()
	counters.drops:SetPoint("LEFT", counters.queue, "RIGHT", 4, 0)
	counters.undo:ClearAllPoints()
	counters.undo:SetPoint("LEFT", counters.drops, "RIGHT", 4, 0)
	compact:SetHeight(-y + 30)
end

function ns.ShowCompact()
	if not compact then CreateCompact() end
	compact:Show()
	ns.RefreshCompact()
end

function ns.HideCompact()
	if compact then compact:Hide() end
end

function ns.ToggleCompact()
	if compact and compact:IsShown() then ns.HideCompact() else ns.ShowCompact() end
end

-- пул босса: мини-панель сама (настройка), если большое окно закрыто
function ns.OnBossPull()
	if ns.DB.settings.compactAuto and not ns.WindowShown() then ns.ShowCompact() end
end

ns.On("PLAYER_TARGET_CHANGED", function() ns.RefreshCompact() end)

-------------------------------------------------------------------------------
-- всплывашка «поставлено · Отменить»

local toast, toastText, toastUndo, toastTimer

local function CreateToast()
	toast = CreateFrame("Frame", "RaidMinusToast", UIParent)
	toast:SetWidth(420)
	toast:SetHeight(36)
	toast:SetFrameStrata("DIALOG")
	toast:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180)
	UI.Panel(toast)
	toastUndo = UI.FlatButton(toast, "Отменить", 96, 22, function()
		ns.UndoLast()
		toast:Hide()
	end, "ghost")
	toastUndo:SetPoint("RIGHT", -8, 0)
	toastText = UI.Text(toast, "GameFontHighlightSmall")
	toastText:SetPoint("LEFT", 10, 0)
	toastText:SetPoint("RIGHT", toastUndo, "LEFT", -8, 0)
	toastText:SetHeight(14)
end

function ns.ShowToast(made)
	if not toast then CreateToast() end
	local names = {}
	for _, ev in ipairs(made) do names[#names + 1] = ev.player end
	local ev = made[1]
	toastText:SetText(format("%s %s · %s", tconcat(names, ", "), ns.ValueColor(ev.value), ns.EventChat(ev)))
	toast:Show()
	local left = 6
	toastUndo:SetLabel("Отменить (" .. left .. ")")
	ns.Cancel(toastTimer)
	local function Tick()
		left = left - 1
		if left <= 0 then
			toast:Hide()
			return
		end
		toastUndo:SetLabel("Отменить (" .. left .. ")")
		toastTimer = ns.After(1, Tick)
	end
	toastTimer = ns.After(1, Tick)
end
