-- Вкладка «Добыча»: лента рейда — что упало с каждого босса, сгруппировано по страницам (LootList.lua).
-- Видно, что в розыгрыше, что не включено (жёлтым) и что скрыл фильтр. «+» — в розыгрыш, «−» — убрать.
-- Клик по заголовку босса сворачивает его; окно «Добыча» (◀ ▶) открывает тот же список по боссам.

local _, ns = ...
local UI = ns.UI

local format, tinsert, tconcat = string.format, table.insert, table.concat
local ipairs, pairs = ipairs, pairs

local ROWS, ROW_H = 21, 22
local FILTERS = {{"all", "Все", 52}, {"missing", "Не включено", 96}, {"hidden", "Скрыто фильтром", 120}}

local list, summary, sources, pills = nil, nil, nil, {}

local function Filter() return ns.ui.dropFilter or "all" end

local function ClassOf(name)
	local s = ns.Session()
	local p = s and s.roster[name]
	return p and p.class
end

-- статус предмета: текст и можно ли нажать «+» / «−»
function ns.DropItemStatus(item)
	local e = item.loot and ns.LootById(item.loot)
	if e then
		if e.winner then return "|cff60e860выиграл|r " .. ns.ColorName(e.winner, ClassOf(e.winner)), "minus" end
		if ns.roll and ns.roll.loot == e.id and ns.roll.state == "open" then return "|cffffd100ролл...|r", nil end
		return "|cff60e860в розыгрыше|r", "minus"
	end
	if item.wanted then return item.removed and "|cffffd100убран из розыгрыша|r" or "|cffffd100не включено|r", "plus" end
	return "|cff707070скрыто: " .. tostring(item.why or "фильтр") .. "|r", "plus"
end

function ns.PageTitle(page)
	return page.boss and ns.Section(page.boss).name or page.title or "Добыча"
end

function ns.PageMeta(page)
	local parts = {date("%H:%M", page.t)}
	local src = ns.SourceText(page.src)
	if src ~= "" then tinsert(parts, src) end
	return tconcat(parts, " · ")
end

local function HiddenNames(page)
	local names = {}
	for _, item in ipairs(page.items) do
		if not item.wanted and not item.loot then
			local name = GetItemInfo(item.link or item.id) or tostring(item.link):match("%[(.-)%]") or ("#" .. item.id)
			tinsert(names, name)
		end
	end
	return names
end

local function Items()
	local filter = Filter()
	local out = {}
	local drops = ns.Drops()
	for i = #drops, 1, -1 do -- новые сверху
		local page = drops[i]
		local rows = {}
		for _, item in ipairs(page.items) do
			local missing = ns.ItemMissing(item)
			local hidden = not item.wanted
			if (filter == "all" and (not hidden or item.loot)) or (filter == "missing" and missing) or (filter == "hidden" and hidden) then
				tinsert(rows, {page = page, item = item})
			end
		end
		local hiddenNames = filter == "all" and HiddenNames(page) or {}
		if #rows > 0 or (filter == "all" and #hiddenNames > 0 and page.boss) then
			tinsert(out, {header = page})
			if not ns.ui.collapsed[page.id] then
				for _, r in ipairs(rows) do tinsert(out, r) end
				if #hiddenNames > 0 then tinsert(out, {note = "скрыто фильтром: " .. tconcat(hiddenNames, ", ")}) end
			end
		end
	end
	return out
end

local function MakeRow(row)
	row.icon = UI.ItemIcon(row, 18)
	row.icon:SetPoint("LEFT", 22, 0)
	row.arrow = UI.Text(row, "GameFontNormal", "CENTER")
	row.arrow:SetPoint("LEFT", 2, 0)
	row.arrow:SetWidth(14)
	row.btn = UI.FlatButton(row, "+", 24, 18, function(self)
		local x = self:GetParent().item
		if not x or not x.item then return end
		if self.action == "plus" then ns.IncludeDropItem(x.page, x.item) else ns.ExcludeDropItem(x.page, x.item) end
	end, "ghost")
	row.btn:SetPoint("RIGHT", -4, 0)
	row.status = UI.Text(row, "GameFontHighlightSmall", "RIGHT")
	row.status:SetPoint("RIGHT", row.btn, "LEFT", -8, 0)
	row.status:SetWidth(170)
	row.kind = UI.Text(row, "GameFontDisableSmall", "LEFT")
	row.kind:SetPoint("RIGHT", row.status, "LEFT", -8, 0)
	row.kind:SetWidth(110)
	row.text = UI.Text(row, "GameFontHighlight")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", row.kind, "LEFT", -6, 0)
	row.text:SetHeight(14)

	row:SetScript("OnClick", function(self)
		local x = self.item
		if not x then return end
		if x.header then
			ns.ui.collapsed[x.header.id] = not ns.ui.collapsed[x.header.id] or nil
			ns.RefreshUI()
		elseif x.item and IsModifiedClick("CHATLINK") then
			ChatEdit_InsertLink(x.item.link)
		end
	end)
	UI.Tooltip(row, function(tt, self)
		local x = self.item
		if not x then return false end
		if x.header then
			local wanted, inRoll, missing, hidden = ns.DropCounts(x.header)
			tt:SetText(ns.PageTitle(x.header))
			tt:AddLine(ns.PageMeta(x.header), 0.7, 0.7, 0.7, true)
			tt:AddLine(format("Важных: %d, в розыгрыше: %d, не включено: %d, скрыто: %d", wanted, inRoll, missing, hidden), 1, 1, 1, true)
			tt:AddLine("Клик — свернуть / развернуть", 0.6, 0.6, 0.6)
			return
		end
		if not x.item then return false end
		tt:SetHyperlink(x.item.link)
	end)
end

local function DrawRow(row, x)
	row.bg:SetTexture(0, 0, 0, 0)
	if x.header then
		local page = x.header
		local _, _, missing = ns.DropCounts(page)
		row.icon:Hide()
		row.btn:Hide()
		row.arrow:Show()
		row.arrow:SetText(ns.ui.collapsed[page.id] and "+" or "-")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.text:SetText("|cffffd100" .. ns.PageTitle(page) .. "|r  |cff8e8e9b" .. ns.PageMeta(page) .. "|r")
		row.kind:SetText("")
		row.status:SetText(missing > 0 and format("|cffffd100не включено: %d|r", missing) or "")
		row.bg:SetTexture(0.1, 0.11, 0.15, 1)
		return
	end
	row.arrow:Hide()
	if x.note then
		row.icon:Hide()
		row.btn:Hide()
		row.text:SetText("|cff707070" .. x.note .. "|r")
		row.kind:SetText("")
		row.status:SetText("")
		return
	end
	local item = x.item
	row.icon:Show()
	row.icon:SetItem(item.id, item.link)
	row.text:SetText(item.link)
	row.kind:SetText(ns.LootKind(item.id, item.link))
	local status, action = ns.DropItemStatus(item)
	row.status:SetText(status)
	if action then
		row.btn.action = action
		row.btn:SetLabel(action == "plus" and "+" or "-")
		row.btn.tooltip = function(tt)
			tt:SetText(action == "plus" and "Добавить в розыгрыш" or "Убрать из розыгрыша")
		end
		row.btn:Show()
	else
		row.btn:Hide()
	end
	if ns.ItemMissing(item) then row.bg:SetTexture(1, 0.82, 0, 0.07) end
end

local function Create(f)
	summary = UI.Text(f, "GameFontNormal")
	summary:SetPoint("TOPLEFT", 2, -4)
	local prev
	for i = #FILTERS, 1, -1 do
		local key = FILTERS[i][1]
		local b = UI.FlatButton(f, FILTERS[i][2], FILTERS[i][3], 20, function()
			ns.ui.dropFilter = key
			ns.RefreshUI()
		end, "pill")
		if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", 0, -2) end
		pills[key] = b
		prev = b
	end

	list = UI.List(f, ROWS, ROW_H, MakeRow)
	list:SetPoint("TOPLEFT", 0, -28)
	list:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	list.redraw = ns.RefreshUI

	local addAll = UI.Button(f, "Добавить всё не включённое", 200, function() ns.IncludeAllMissing() end)
	addAll:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)
	local window = UI.Button(f, "Окно по боссам", 130, function() ns.ShowLootWindow() end)
	window:SetPoint("LEFT", addAll, "RIGHT", 6, 0)
	local roll = UI.Button(f, "К розыгрышу", 110, function() ns.ShowTab("loot") end)
	roll:SetPoint("LEFT", window, "RIGHT", 6, 0)
	sources = UI.Text(f, "GameFontDisableSmall", "RIGHT")
	sources:SetPoint("LEFT", roll, "RIGHT", 10, 0)
	sources:SetPoint("RIGHT", list, "RIGHT", 0, 0)
end

local function SourcesLine()
	local set = ns.DB.settings
	local function mark(on, name) return (on and "|cff60e860" or "|cff707070") .. name .. "|r" end
	return "Источники: " .. tconcat({
		mark(set.srcCorpse, "моё тело"), mark(set.srcRaidRoll, "RaidRoll"), mark(set.srcChat, "чат лута"), mark(set.srcList, "список"),
	}, " · ") .. (set.lootAuto and "" or " · |cffffd100без автодобавления|r")
end

local function Update()
	ns.RecheckDrops()
	local total, inRoll, missing, hidden = 0, 0, 0, 0
	for _, page in ipairs(ns.Drops()) do
		local w, i, m, h = ns.DropCounts(page)
		total, inRoll, missing, hidden = total + w, inRoll + i, missing + m, hidden + h
	end
	summary:SetText(format("Важной добычи: %d  |cff9d9d9d· в розыгрыше %d · %s · скрыто фильтром %d|r", total, inRoll,
		missing > 0 and ("|cffffd100не включено " .. missing .. "|r|cff9d9d9d") or "не включено 0", hidden))
	for key, b in pairs(pills) do b:SetSelected(Filter() == key) end
	local items = Items()
	if #items == 0 then
		items = {{note = Filter() == "all" and "Добыча появится сама: когда кто-то откроет тело (у вас или у него RaidRoll), получит предмет или скинет список." or "Пусто."}}
	end
	list:Draw(items, DrawRow)
	sources:SetText(SourcesLine())
end

ns.RegisterPage("drops", Create, Update)
