-- Вкладка «Розыгрыш»: слева добыча (сама собирается: что залутал я, что выбрано в окошке «Добыча»,
-- что объявил в ролл ответственный за добычу; вручную — shift+клик в поле или перетащить предмет),
-- справа ролл выбранного предмета: роль, бросок, минусы, итог, допуск; победитель — со звездой.

local _, ns = ...
local UI = ns.UI

local format = string.format
local ipairs, floor = ipairs, math.floor

local LOOT_ROWS, LOOT_H, ROLL_ROWS, ROLL_H = 13, 22, 13, 18
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local DIAMOND = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3"

local lootList, rollList, input, removeBtn
local itemBtn, catText, stateText, startBtn, finishBtn, cancelBtn, chatBtn, testBtn, foreignBtn, offBtn
local shownWinner, shownTie -- для строк таблицы

local function SelectedLoot()
	local e = ns.ui.loot and ns.LootById(ns.ui.loot)
	if not e then
		local s = ns.Session()
		e = s and s.loot[#s.loot]
		ns.ui.loot = e and e.id
	end
	return e
end

local function AddFromCursor()
	local kind, _, link = GetCursorInfo()
	if kind == "item" and link then
		ClearCursor()
		ns.AddLoot(link, "manual")
	end
end

local function ClassOf(name)
	local s = ns.Session()
	local p = s and s.roster[name]
	return p and p.class
end

-------------------------------------------------------------------------------
-- строки

local function MakeLootRow(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetWidth(18)
	row.icon:SetHeight(18)
	row.icon:SetPoint("LEFT", 2, 0)
	row.winner = UI.Text(row, "GameFontHighlightSmall", "RIGHT")
	row.winner:SetPoint("RIGHT", -4, 0)
	row.winner:SetWidth(90)
	row.name = UI.Text(row, "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.name:SetPoint("RIGHT", row.winner, "LEFT", -4, 0)

	row:SetScript("OnClick", function(self)
		if not self.item then return end
		if IsModifiedClick("CHATLINK") then
			ChatEdit_InsertLink(self.item.link)
			return
		end
		ns.ui.loot = self.item.id
		ns.RefreshUI()
	end)
	row:SetScript("OnReceiveDrag", AddFromCursor)
	UI.Tooltip(row, function(tt, self)
		local e = self.item
		if not e then return false end
		tt:SetHyperlink(e.link)
		tt:AddLine(" ")
		tt:AddLine("Категория: " .. ns.CategoryName(e.cat), 0.6, 0.8, 1)
		tt:AddLine("Откуда: " .. ns.LootSourceText(e), 0.6, 0.8, 1, true)
		if e.boss then tt:AddLine("Босс: " .. ns.ShortName(e.boss), 0.6, 0.8, 1) end
	end)
end

local function DrawLootRow(row, e)
	local texture = select(10, GetItemInfo(e.link))
	row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
	row.name:SetText(e.link)
	local r = ns.roll
	if r and r.loot == e.id and r.state == "open" then
		row.winner:SetText(r.watch and "|cff69ccf0считаю...|r" or "|cffffd100ролл...|r")
	elseif e.winner then
		row.winner:SetText("|T" .. STAR .. ":12|t " .. ns.ColorName(e.winner, ClassOf(e.winner)))
	elseif e.result and e.result.tie then
		row.winner:SetText("|cffffd100ничья|r")
	elseif e.result then
		row.winner:SetText("|cff9d9d9dникто|r")
	else
		row.winner:SetText("")
	end
	UI.Select(row, ns.ui.loot == e.id)
end

local function Col(row, x, width, justify)
	local fs = UI.Text(row, "GameFontHighlightSmall", justify)
	fs:SetPoint("LEFT", x, 0)
	fs:SetWidth(width)
	return fs
end

local COLS = {
	{"place", "#", 18, 18, "RIGHT"}, {"name", "Игрок", 40, 100}, {"role", "Роль", 142, 52},
	{"roll", "Ролл", 196, 34, "RIGHT"}, {"mod", "±", 232, 40, "RIGHT"}, {"final", "Итог", 274, 38, "RIGHT"},
	{"status", "", 320, 90},
}

local function MakeRollRow(row)
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetWidth(14)
	row.mark:SetHeight(14)
	row.mark:SetPoint("LEFT", 2, 0)
	for _, c in ipairs(COLS) do row[c[1]] = Col(row, c[3], c[4], c[5]) end
	-- подсказка: за что у игрока минусы
	UI.Tooltip(row, function(tt, self)
		local e = self.item
		if not e then return false end
		tt:SetText(ns.ColorName(e.name, ClassOf(e.name)))
		tt:AddLine("Итого: " .. ns.StateText(e.name, true), 1, 1, 1)
		for _, ev in ipairs(ns.PlayerEvents(e.name)) do
			tt:AddDoubleLine(ns.ShortName(ev.boss) .. ": " .. ns.ShortText(ev.text), ns.ValueColor(ev.value), 0.9, 0.9, 0.9)
		end
	end)
end

local function DrawRollRow(row, e, i)
	local winner = e.name == shownWinner
	local tie = shownTie and shownTie[e.name]
	if winner then
		row.mark:SetTexture(STAR)
		row.mark:Show()
		row.bg:SetTexture(1, 0.82, 0, 0.18)
	elseif tie then
		row.mark:SetTexture(DIAMOND)
		row.mark:Show()
		row.bg:SetTexture(0, 0, 0, 0)
	else
		row.mark:Hide()
		row.bg:SetTexture(0, 0, 0, 0)
	end
	row.place:SetText(e.ok and i or "")
	row.name:SetText(ns.ColorName(e.name, ClassOf(e.name)))
	local role, cur = ns.PlayerRole(e.name)
	local roleText = ns.RoleName(role, true)
	if cur and role and cur ~= role then roleText = roleText .. "|cffff9020*|r" end
	row.role:SetText(roleText)
	row.roll:SetText(e.roll)
	row.mod:SetText(e.mod and e.mod ~= 0 and ns.ValueColor(e.mod) or "")
	row.final:SetText(e.ok and ("|cffffffff" .. e.final .. "|r") or ("|cff707070" .. tostring(e.final) .. "|r"))
	local st
	if winner then
		st = "|cffffd100победитель|r"
	elseif tie then
		st = "|cffffd100ничья|r"
	elseif not e.ok then
		st = "|cffff6060" .. tostring(e.reason) .. "|r"
	else
		st = ""
	end
	if e.extra then st = st .. format(" |cff9d9d9d(+%d бросок)|r", e.extra) end
	row.status:SetText(st)
end

-------------------------------------------------------------------------------
-- вкладка

local function Create(f)
	local title = UI.Text(f, "GameFontNormal")
	title:SetPoint("TOPLEFT", 2, -4)
	title:SetText("Добыча")

	lootList = UI.List(f, LOOT_ROWS, LOOT_H, MakeLootRow)
	lootList:SetPoint("TOPLEFT", 0, -24)
	lootList:SetWidth(310)
	lootList:EnableMouse(true)
	lootList:SetScript("OnReceiveDrag", AddFromCursor)
	lootList:SetScript("OnMouseUp", AddFromCursor)
	lootList.redraw = ns.RefreshUI

	input = UI.EditBox(f, 210, "shift+клик по предмету", function(self)
		local text = self:GetText()
		if text ~= "" then ns.AddLootFromText(text, false) end
		self:SetText("")
	end)
	input:SetPoint("TOPLEFT", lootList, "BOTTOMLEFT", 6, -6)
	input:SetScript("OnReceiveDrag", AddFromCursor)
	-- shift+клик по предмету, пока поле в фокусе, вставляет ссылку сюда
	hooksecurefunc("ChatEdit_InsertLink", function(link)
		if input:HasFocus() and link and link:find("|Hitem:") then input:Insert(link) end
	end)
	local add = UI.Button(f, "Добавить", 86, function()
		local text = input:GetText()
		if text ~= "" then ns.AddLootFromText(text, false) end
		input:SetText("")
		input:ClearFocus()
	end)
	add:SetPoint("LEFT", input, "RIGHT", 6, 0)
	removeBtn = UI.Button(f, "Убрать из списка", 130, function() ns.RemoveLoot(SelectedLoot()) end)
	removeBtn:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -6)

	-- правая часть: ролл
	itemBtn = CreateFrame("Button", nil, f)
	itemBtn:SetPoint("TOPLEFT", lootList, "TOPRIGHT", 14, 24)
	itemBtn:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	itemBtn:SetHeight(22)
	itemBtn.text = UI.Text(itemBtn, "GameFontNormalLarge")
	itemBtn.text:SetPoint("LEFT", 2, 0)
	itemBtn.text:SetPoint("RIGHT", 0, 0)
	UI.Tooltip(itemBtn, function(tt)
		local e = SelectedLoot()
		if not e then return false end
		tt:SetHyperlink(e.link)
	end)

	catText = UI.Text(f, "GameFontHighlightSmall")
	catText:SetPoint("TOPLEFT", itemBtn, "BOTTOMLEFT", 2, -2)
	catText:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	stateText = UI.Text(f, "GameFontHighlight")
	stateText:SetPoint("TOPLEFT", catText, "BOTTOMLEFT", 0, -6)
	stateText:SetPoint("RIGHT", f, "RIGHT", 0, 0)

	rollList = UI.List(f, ROLL_ROWS, ROLL_H, MakeRollRow)
	rollList:SetPoint("TOPLEFT", lootList, "TOPRIGHT", 14, -60)
	rollList:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	rollList.redraw = ns.RefreshUI

	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("BOTTOMLEFT", rollList, "TOPLEFT", 4, 0)
	head:SetPoint("RIGHT", rollList, "RIGHT", -26, 0)
	head:SetHeight(14)
	for _, c in ipairs(COLS) do
		local fs = UI.Text(head, "GameFontDisableSmall", c[5])
		fs:SetPoint("LEFT", c[3], 0)
		fs:SetWidth(c[4])
		fs:SetText(c[2])
	end

	startBtn = UI.Button(f, "Начать ролл", 120, function()
		local e = SelectedLoot()
		if not e then return end
		if e.result and e.result.tie then ns.StartRoll(e, e.result.tie) else ns.StartRoll(e) end
	end)
	startBtn:SetPoint("TOPLEFT", rollList, "BOTTOMLEFT", 0, -6)
	finishBtn = UI.Button(f, "Закончить розыгрыш", 150, function() ns.FinishRoll(true) end)
	finishBtn:SetPoint("LEFT", startBtn, "RIGHT", 4, 0)
	UI.Tooltip(finishBtn, function(tt)
		tt:SetText("Закончить розыгрыш")
		tt:AddLine("Перестать принимать броски, посчитать итог с минусами и написать его в рейд: каждый игрок отдельной строкой, победитель со звездой.", 1, 1, 1, true)
	end)
	cancelBtn = UI.Button(f, "Отменить", 80, function() ns.CancelRoll() end)
	cancelBtn:SetPoint("LEFT", finishBtn, "RIGHT", 4, 0)
	offBtn = UI.Button(f, "Ролл на офф-спек", 130, function()
		local e = SelectedLoot()
		if e then ns.StartRoll(e, nil, nil, true) end
	end)
	offBtn:SetPoint("TOPLEFT", startBtn, "BOTTOMLEFT", 0, -4)
	UI.Tooltip(offBtn, function(tt)
		tt:SetText("Ролл на офф-спек")
		tt:AddLine("Второй ролл, если на основной спек никто не взял. Минусы считаются так же.", 1, 1, 1, true)
	end)
	chatBtn = UI.Button(f, "Итог в чат", 100, function() ns.AnnounceResult(SelectedLoot()) end)
	chatBtn:SetPoint("LEFT", offBtn, "RIGHT", 4, 0)
	UI.Tooltip(chatBtn, function(tt)
		tt:SetText("Написать итог этого предмета в рейд ещё раз")
	end)
	testBtn = UI.Button(f, "Тест-броски", 100, function() ns.TestRolls() end)
	testBtn:SetPoint("TOPLEFT", offBtn, "BOTTOMLEFT", 0, -4)
	foreignBtn = UI.Button(f, "Тест: чужой ролл", 130, function() ns.TestForeignRoll() end)
	foreignBtn:SetPoint("LEFT", testBtn, "RIGHT", 4, 0)
	UI.Tooltip(foreignBtn, function(tt)
		tt:SetText("Тест: ролл объявил ответственный за добычу")
		tt:AddLine("Холпал объявляет ролл предмета из списка, выдуманные игроки бросают. Аддон молча считает с минусами — итог в чат по «Закончить розыгрыш».", 1, 1, 1, true)
	end)
end

local function StateLine(s, e, r, live)
	if live then
		local left = floor(r.ends - GetTime() + 0.5)
		if left < 0 then left = 0 end
		if r.watch then
			return format("|cff69ccf0Ролл объявил %s — считаю с минусами|r · бросили: %d · закроется сам через %d сек",
				tostring(r.watch), #r.entries, left)
		end
		local what = r.only and "Переролл ничьей" or (r.off and "Ролл на офф-спек" or "Идёт ролл")
		return format("|cffffd100%s: %d сек|r · бросили: %d", what, left, #r.entries)
	end
	local res = e.result
	if not res then return "|cff9d9d9dНе разыгран|r" end
	local tail = (res.watched and not res.announced) and " · |cffff9020в чат не писал|r" or ""
	if res.winner then
		return format("Победитель%s: |T%s:14|t %s (%s)%s", res.off and " (офф-спек)" or "", STAR,
			ns.ColorName(res.winner, ClassOf(res.winner)), ns.RollText(res), tail)
	end
	if res.tie then
		return "|cffffd100Ничья: " .. table.concat(res.tie, ", ") .. "|r — «Переролл ничьей» перекинет только их"
	end
	return "|cffff6060Никто не допущен или никто не бросил|r" .. tail
end

local function Update()
	local s = ns.Session()
	local e = SelectedLoot()
	lootList:Draw(s.loot, DrawLootRow)
	if e then removeBtn:Enable() else removeBtn:Disable() end
	if s.test then
		testBtn:Show()
		foreignBtn:Show()
	else
		testBtn:Hide()
		foreignBtn:Hide()
	end

	local r = ns.roll
	local live = r and e and r.loot == e.id and r.state == "open"

	if not e then
		itemBtn.text:SetText("|cff9d9d9dВыберите предмет слева|r")
		catText:SetText("Сюда сама попадает добыча: что вы залутали, что добавили из окошка «Добыча», что объявил в ролл ответственный за добычу.")
		stateText:SetText("")
		shownWinner, shownTie = nil, nil
		rollList:Draw({}, DrawRollRow)
		for _, b in ipairs({startBtn, finishBtn, cancelBtn, chatBtn, offBtn}) do b:Disable() end
		return
	end

	itemBtn.text:SetText(e.link)
	catText:SetText("Категория: " .. ns.CategoryName(e.cat) .. "  ·  " .. ns.LootSourceText(e))
	stateText:SetText(StateLine(s, e, r, live))

	local entries
	shownWinner, shownTie = nil, nil
	if live then
		ns.ComputeRoll(r)
		entries = r.entries
	elseif e.result then
		entries = e.result.entries
		shownWinner = e.result.winner
		if e.result.tie then
			shownTie = {}
			for _, name in ipairs(e.result.tie) do shownTie[name] = true end
		end
	else
		entries = {}
	end
	rollList:Draw(entries, DrawRollRow)

	local busy = r and r.state == "open" and not r.watch
	if busy then
		startBtn:Disable()
		offBtn:Disable()
	else
		startBtn:Enable()
		offBtn:Enable()
	end
	if live then
		startBtn:SetText("Начать ролл")
	elseif e.result and e.result.tie then
		startBtn:SetText("Переролл ничьей")
	elseif e.result then
		startBtn:SetText("Переиграть")
	else
		startBtn:SetText("Начать ролл")
	end
	if live then
		finishBtn:Enable()
		cancelBtn:Enable()
	else
		finishBtn:Disable()
		cancelBtn:Disable()
	end
	if e.result and not live then chatBtn:Enable() else chatBtn:Disable() end
end

ns.RegisterPage("loot", Create, Update)
