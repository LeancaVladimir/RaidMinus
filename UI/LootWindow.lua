-- Окно «Добыча»: по боссу на страницу, ◀ ▶ листают прошлых боссов (как RaidRoll Loot Tracker).
-- Открывается само, когда появилась новая добыча (настройка lootPopup). Видно, что из важного
-- в розыгрыше, а что нет: жёлтая плашка сверху ведёт на страницу, где что-то не включено.
-- Данные — страницы ns.Drops() (LootList.lua); вкладка «Добыча» в главном окне — тот же список лентой.

local _, ns = ...
local UI = ns.UI

local format, tinsert = string.format, table.insert
local ipairs = ipairs

local W, ROWS, ROW_H = 400, 8, 34
local ALERT = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
local PREV, NEXT = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage", "Interface\\Buttons\\UI-SpellbookIcon-NextPage"
local PILL_W, PILLS_PER_ROW = 72, 5

-- стрелка листания, как в книге заклинаний: картинки -Up, -Down, -Disabled
local function PageButton(parent, base, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(32)
	b:SetHeight(32)
	b:SetNormalTexture(base .. "-Up")
	b:SetPushedTexture(base .. "-Down")
	b:SetDisabledTexture(base .. "-Disabled")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b:SetScript("OnClick", onClick)
	function b:SetEnabledFlat(on)
		if on then self:Enable() else self:Disable() end
	end
	return b
end

local panel, title, sub, meta, prevBtn, nextBtn, warn, list, hiddenText, addAll
local pills = {}

local function Pages()
	-- страницы, где есть хоть что-то важное (треш с одним саронитом не нужен)
	local out = {}
	for _, page in ipairs(ns.Drops()) do
		local wanted = ns.DropCounts(page)
		local forced = false
		for _, item in ipairs(page.items) do
			if item.loot then forced = true end
		end
		if wanted > 0 or forced or page.boss then tinsert(out, page) end
	end
	return out
end

local function CurrentIndex(pages)
	for i, page in ipairs(pages) do
		if page.id == ns.ui.dropPage then return i end
	end
	ns.ui.dropPage = pages[#pages] and pages[#pages].id
	return #pages
end

local function Go(i)
	local pages = Pages()
	if pages[i] then ns.ui.dropPage = pages[i].id end
	ns.RefreshLootWindow()
end

local function MakeRow(row)
	row.icon = UI.ItemIcon(row, 28)
	row.icon:SetPoint("LEFT", 4, 0)
	row.btn = UI.FlatButton(row, "+ Включить", 84, 20, function(self)
		local x = self:GetParent().item
		if not x then return end
		if self.action == "plus" then ns.IncludeDropItem(x.page, x.item) else ns.ExcludeDropItem(x.page, x.item) end
	end, "ghost")
	row.btn:SetPoint("RIGHT", -4, 0)
	row.status = UI.Text(row, "GameFontHighlightSmall", "RIGHT")
	row.status:SetPoint("RIGHT", -6, 0)
	row.status:SetWidth(110)
	row.name = UI.Text(row, "GameFontHighlight")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
	row.name:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
	row.name:SetHeight(14)
	row.kind = UI.Text(row, "GameFontDisableSmall")
	row.kind:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
	row.kind:SetPoint("RIGHT", row.status, "LEFT", -6, 0)

	row:SetScript("OnClick", function(self)
		local x = self.item
		if x and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(x.item.link) end
	end)
	UI.Tooltip(row, function(tt, self)
		if not self.item then return false end
		tt:SetHyperlink(self.item.item.link)
	end)
end

local function DrawRow(row, x)
	local item = x.item
	row.icon:SetItem(item.id, item.link)
	row.name:SetText(item.link)
	local level = select(4, GetItemInfo(item.link or item.id))
	local kind = ns.LootKind(item.id, item.link)
	row.kind:SetText(kind .. (level and level > 100 and (" · ilvl " .. level) or ""))
	local status, action = ns.DropItemStatus(item)
	row.bg:SetTexture(0, 0, 0, 0)
	if action == "plus" and item.wanted then
		row.status:Hide()
		row.btn.action = "plus"
		row.btn:SetLabel("+ Включить")
		row.btn:Show()
		row.bg:SetTexture(1, 0.82, 0, 0.07)
	else
		row.btn:Hide()
		row.status:Show()
		row.status:SetText(status)
	end
end

local function Create()
	panel = CreateFrame("Frame", "RaidMinusLootFrame", UIParent)
	panel:SetWidth(W)
	panel:SetHeight(470)
	panel:SetFrameStrata("HIGH")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.DB.dropPos = {point, relPoint, x, y}
	end)
	local pos = ns.DB.dropPos
	if pos then
		panel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 270, -110) -- справа от окна добычи игры
	end
	tinsert(UISpecialFrames, "RaidMinusLootFrame")

	UI.Panel(panel)
	UI.TitleBar(panel, "Raid|cffff5050Minus|r: добыча")

	prevBtn = PageButton(panel, PREV, function() Go(CurrentIndex(Pages()) - 1) end)
	prevBtn:SetPoint("TOPLEFT", 10, -36)
	nextBtn = PageButton(panel, NEXT, function() Go(CurrentIndex(Pages()) + 1) end)
	nextBtn:SetPoint("TOPRIGHT", -10, -36)
	title = UI.Text(panel, "GameFontNormalLarge", "CENTER")
	title:SetPoint("TOPLEFT", prevBtn, "TOPRIGHT", 6, 0)
	title:SetPoint("TOPRIGHT", nextBtn, "TOPLEFT", -6, 0)
	sub = UI.Text(panel, "GameFontDisableSmall", "CENTER")
	sub:SetPoint("TOP", title, "BOTTOM", 0, -3)
	meta = UI.Text(panel, "GameFontHighlightSmall", "CENTER")
	meta:SetPoint("TOPLEFT", 12, -74)
	meta:SetPoint("TOPRIGHT", -12, -74)

	warn = UI.FlatButton(panel, "", W - 20, 22, nil, "ghost")
	warn:SetPoint("TOPLEFT", 10, -92)
	warn.noFit = true
	warn:SetBackdropColor(1, 0.82, 0, 0.1)
	warn.label:SetJustifyH("LEFT")
	warn:SetTextColor(UI.GOLD)

	list = UI.List(panel, ROWS, ROW_H, MakeRow)
	list:SetPoint("TOPLEFT", 10, -118)
	list:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
	list.redraw = ns.RefreshLootWindow

	hiddenText = UI.Text(panel, "GameFontDisableSmall")
	hiddenText:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 4, -5)
	hiddenText:SetPoint("RIGHT", list, "RIGHT", -4, 0)
	hiddenText:SetHeight(12)

	addAll = UI.Button(panel, "Добавить всё", 120, function()
		local pages = Pages()
		ns.IncludeAllMissing(pages[CurrentIndex(pages)])
	end)
	addAll:SetPoint("BOTTOMLEFT", 10, 10)
	local open = UI.Button(panel, "Розыгрыш", 100, function() ns.ShowTab("loot") end)
	open:SetPoint("BOTTOMRIGHT", -10, 10)
	local feed = UI.Button(panel, "Лента", 80, function() ns.ShowTab("drops") end)
	feed:SetPoint("RIGHT", open, "LEFT", -4, 0)
end

local function PillFor(i)
	local b = pills[i]
	if b then return b end
	b = UI.FlatButton(panel, "", PILL_W, 20, function(self) Go(self.index) end, "pill")
	b.noFit = true -- кнопки стоят сеткой
	local col, line = (i - 1) % PILLS_PER_ROW, math.floor((i - 1) / PILLS_PER_ROW)
	b:SetPoint("TOPLEFT", list, "BOTTOMLEFT", col * (PILL_W + 3), -22 - line * 23)
	pills[i] = b
	return b
end

function ns.RefreshLootWindow()
	if not panel or not panel:IsShown() then return end
	if not ns.Session() then
		panel:Hide()
		return
	end
	local pages = Pages()
	local idx = CurrentIndex(pages)
	local page = pages[idx]
	if not page then
		title:SetText("Добычи пока нет")
		sub:SetText("")
		meta:SetText("Появится сама, когда кто-то откроет тело босса.")
		list:Draw({}, DrawRow)
		warn:Hide()
		hiddenText:SetText("")
		prevBtn:SetEnabledFlat(false)
		nextBtn:SetEnabledFlat(false)
		for _, b in ipairs(pills) do b:Hide() end
		panel:SetHeight(240)
		return
	end
	title:SetText(ns.PageTitle(page))
	sub:SetText(format("босс %d из %d%s", idx, #pages, idx == #pages and " · последний" or ""))
	meta:SetText(ns.PageMeta(page))
	prevBtn:SetEnabledFlat(idx > 1)
	nextBtn:SetEnabledFlat(idx < #pages)

	-- где что-то не включено
	local _, _, here = ns.DropCounts(page)
	local firstMissing
	for i, p in ipairs(pages) do
		if not firstMissing and select(3, ns.DropCounts(p)) > 0 then firstMissing = i end
	end
	if here > 0 then
		warn:SetLabel(format("|T%s:14|t  На этой странице не в розыгрыше: %d", ALERT, here))
		warn:SetScript("OnClick", nil)
		warn:Show()
	elseif firstMissing then
		local p = pages[firstMissing]
		warn:SetLabel(format("|T%s:14|t  Не включено: %s — %d · открыть", ALERT, ns.PageTitle(p), select(3, ns.DropCounts(p))))
		warn:SetScript("OnClick", function() Go(firstMissing) end)
		warn:Show()
	else
		warn:Hide()
	end

	local items, hidden = {}, {}
	for _, item in ipairs(page.items) do
		if item.wanted or item.loot then
			tinsert(items, {page = page, item = item})
		else
			tinsert(hidden, GetItemInfo(item.link or item.id) or tostring(item.link):match("%[(.-)%]") or ("#" .. item.id))
		end
	end
	list:Draw(items, DrawRow)
	hiddenText:SetText(#hidden > 0 and ("Скрыто фильтром: " .. table.concat(hidden, ", ")) or "")
	if select(3, ns.DropCounts(page)) > 0 then addAll:Enable() else addAll:Disable() end

	-- быстрый переход: по кнопке на босса
	local lines = math.max(1, math.ceil(#pages / PILLS_PER_ROW))
	for i = 1, math.max(#pages, #pills) do
		local p = pages[i]
		if p then
			local b = PillFor(i)
			b.index = i
			local missing = select(3, ns.DropCounts(p))
			b:SetLabel((p.boss and ns.ShortName(p.boss) or "Прочее") .. (missing > 0 and " |cffffd100!|r" or ""))
			b:SetSelected(i == idx)
			b:Show()
		elseif pills[i] then
			pills[i]:Hide()
		end
	end
	panel:SetHeight(118 + ROWS * ROW_H + 8 + 22 + lines * 23 + 40)
end

-- pageId — открыть страницу (нет — последнюю)
function ns.ShowLootWindow(pageId)
	if not ns.Session() then
		ns.Print("рейд не начат.")
		return
	end
	if not panel then Create() end
	if pageId then ns.ui.dropPage = pageId end
	ns.RecheckDrops()
	panel:Show()
	ns.RefreshLootWindow()
end

function ns.HideLootWindow()
	if panel then panel:Hide() end
end
