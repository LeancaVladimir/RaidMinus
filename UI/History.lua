-- Вкладка «История»: текущий рейд и прошлые (20 последних, без тестовых).
-- Слева список рейдов, справа — «Добыча»: предмет, победитель и как посчитано (ролл ± минусы = итог),
-- кто фактически получил; или «Игроки»: сумма за рейд, записи, что выиграл. «Отчёт» — текст для Discord.

local _, ns = ...
local UI = ns.UI

local format, tinsert, tconcat = string.format, table.insert, table.concat
local ipairs, pairs = ipairs, pairs

local RAID_ROWS, RAID_H, ROWS, ROW_H = 13, 36, 22, 21
local RAID_W = 250

local raids, list, title, sub, pills, reportBtn = nil, nil, nil, nil, {}, nil

local function Sessions()
	local out = {}
	local s = ns.Session()
	if s and not s.test then tinsert(out, s) end
	for _, h in ipairs(ns.DB.history) do tinsert(out, h) end
	return out
end

local function Selected()
	local all = Sessions()
	local sel = ns.ui.histSel and all[ns.ui.histSel] or all[1]
	return sel, all
end

local function ItemName(link) return tostring(link):match("%[(.-)%]") or tostring(link) end

local function Kills(s)
	local n = 0
	for _ in pairs(s.killed or {}) do n = n + 1 end
	return n
end

local function ClassOf(s, name)
	local p = s.roster and s.roster[name]
	return p and p.class
end

-- «57 -20 = 37» или «57»
local function RollShort(res)
	if not res or not res.roll then return "" end
	if not res.mod or res.mod == 0 then return tostring(res.roll) end
	return format("%d %s = %d", res.roll, ns.ValueText(res.mod), res.final)
end

-- сумма игрока в рейде s (не только в текущем)
local function PlayerTotals(s)
	local out, order = {}, {}
	local function get(name)
		if not out[name] then
			out[name] = {name = name, total = 0, minus = 0, plus = 0, events = {}, items = {}}
			tinsert(order, out[name])
		end
		return out[name]
	end
	for _, ev in ipairs(s.events or {}) do
		if ev.status ~= "cancelled" then
			local p = get(ev.player)
			p.total = p.total + (ev.value or 0)
			if (ev.value or 0) < 0 then p.minus = p.minus + 1 else p.plus = p.plus + 1 end
			tinsert(p.events, ev)
		end
	end
	for _, e in ipairs(s.loot or {}) do
		local who = e.receiver or e.winner
		if who then tinsert(get(who).items, e) end
	end
	table.sort(order, function(a, b)
		if a.total ~= b.total then return a.total < b.total end
		return a.name < b.name
	end)
	return order
end

-------------------------------------------------------------------------------
-- отчёт для Discord: простой текст без ссылок и цветов

function ns.RaidReport(s)
	local lines = {}
	local ended = s.ended and date(" — %H:%M", s.ended) or ""
	tinsert(lines, format("RaidMinus: рейд %s%s, РЛ %s, свод «%s»", date("%d.%m.%Y %H:%M", s.started), ended,
		tostring(s.leader), tostring(s.ruleset)))
	local kills = {}
	for _, sec in ipairs(ns.SECTIONS) do
		if s.killed and s.killed[sec.key] then tinsert(kills, sec.short) end
	end
	if #kills > 0 then tinsert(lines, "Боссы: " .. tconcat(kills, ", ")) end
	tinsert(lines, "")
	tinsert(lines, "ДОБЫЧА")
	for _, e in ipairs(s.loot or {}) do
		local res = e.result
		local what
		if e.winner then
			local roll = RollShort(res)
			what = e.winner .. (roll ~= "" and (" (" .. roll .. ")") or "")
		elseif res and res.tie then
			what = "ничья: " .. tconcat(res.tie, ", ")
		elseif res then
			what = "никто"
		else
			what = "не разыгран"
		end
		if e.receiver and e.receiver ~= e.winner then what = what .. " · получил " .. e.receiver end
		tinsert(lines, format("%s: %s — %s", ns.ShortName(e.boss), ItemName(e.link), what))
	end
	tinsert(lines, "")
	tinsert(lines, "МИНУСЫ И ПЛЮСЫ")
	for _, p in ipairs(PlayerTotals(s)) do
		if #p.events > 0 then
			local parts = {}
			for _, ev in ipairs(p.events) do
				tinsert(parts, format("%s: %s %s", ns.ShortName(ev.boss), ns.EventChat(ev), ns.ValueText(ev.value)))
			end
			tinsert(lines, format("%s %s — %s", p.name, ns.ValueText(p.total), tconcat(parts, "; ")))
		end
	end
	return tconcat(lines, "\n")
end

local reportFrame, reportEdit
local function ShowReport(s)
	if not reportFrame then
		reportFrame = CreateFrame("Frame", "RaidMinusReportFrame", UIParent)
		reportFrame:SetWidth(560)
		reportFrame:SetHeight(420)
		reportFrame:SetPoint("CENTER")
		reportFrame:SetFrameStrata("DIALOG")
		reportFrame:EnableMouse(true)
		reportFrame:SetMovable(true)
		reportFrame:RegisterForDrag("LeftButton")
		reportFrame:SetScript("OnDragStart", reportFrame.StartMoving)
		reportFrame:SetScript("OnDragStop", reportFrame.StopMovingOrSizing)
		UI.Panel(reportFrame)
		UI.TitleBar(reportFrame, "Raid|cffff5050Minus|r: отчёт — Ctrl+A, Ctrl+C и вставьте в Discord")
		local scroll = CreateFrame("ScrollFrame", "RaidMinusReportScroll", reportFrame, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 12, -36)
		scroll:SetPoint("BOTTOMRIGHT", -32, 12)
		reportEdit = CreateFrame("EditBox", nil, scroll)
		reportEdit:SetMultiLine(true)
		reportEdit:SetMaxLetters(0)
		reportEdit:SetFontObject(ChatFontNormal)
		reportEdit:SetWidth(510)
		reportEdit:SetAutoFocus(false)
		reportEdit:SetScript("OnEscapePressed", function() reportFrame:Hide() end)
		scroll:SetScrollChild(reportEdit)
		tinsert(UISpecialFrames, "RaidMinusReportFrame")
	end
	reportEdit:SetText(ns.RaidReport(s))
	reportFrame:Show()
	reportEdit:SetFocus()
	reportEdit:HighlightText()
end

-------------------------------------------------------------------------------
-- строки

local function MakeRaidRow(row)
	row.top = UI.Text(row, "GameFontHighlight")
	row.top:SetPoint("TOPLEFT", 6, -3)
	row.top:SetPoint("RIGHT", -4, 0)
	row.bottom = UI.Text(row, "GameFontDisableSmall")
	row.bottom:SetPoint("BOTTOMLEFT", 6, 4)
	row.bottom:SetPoint("RIGHT", -4, 0)
	row:SetScript("OnClick", function(self)
		ns.ui.histSel = self.index
		ns.RefreshUI()
	end)
end

local function DrawRaidRow(row, s, i)
	row.index = i
	local current = s == ns.Session()
	row.top:SetText((current and "|cff60e860сейчас|r  " or "") .. date("%d.%m %H:%M", s.started) .. "  " .. tostring(s.leader))
	local active = 0
	for _, ev in ipairs(s.events or {}) do
		if ev.status ~= "cancelled" then active = active + 1 end
	end
	row.bottom:SetText(format("боссов %d · добычи %d · записей %d", Kills(s), #(s.loot or {}), active))
	UI.Select(row, (ns.ui.histSel or 1) == i)
end

local function Col(row, x, width, justify)
	local fs = UI.Text(row, "GameFontHighlightSmall", justify)
	fs:SetPoint("LEFT", x, 0)
	fs:SetWidth(width)
	fs:SetHeight(14)
	return fs
end

local function MakeRow(row)
	row.a = Col(row, 4, 64)
	row.b = Col(row, 70, 250)
	row.c = Col(row, 324, 170)
	row.d = Col(row, 498, 150)
	UI.Tooltip(row, function(tt, self)
		local x = self.item
		if not x then return false end
		if x.loot then
			tt:SetHyperlink(x.loot.link)
			local res = x.loot.result
			if res and res.entries and #res.entries > 0 then
				tt:AddLine(" ")
				for i, en in ipairs(res.entries) do
					if i > 12 then break end
					tt:AddDoubleLine(en.name, format("%d %s = %d%s", en.roll, ns.ValueText(en.mod or 0), en.final or en.roll,
						en.ok and "" or (" (" .. tostring(en.reason) .. ")")), 1, 1, 1, 0.8, 0.8, 0.8)
				end
			end
			return
		end
		if x.player then
			tt:SetText(x.player.name)
			for _, ev in ipairs(x.player.events) do
				tt:AddDoubleLine(ns.ShortName(ev.boss) .. ": " .. ns.EventChat(ev), ns.ValueColor(ev.value), 0.9, 0.9, 0.9)
			end
			for _, e in ipairs(x.player.items) do tt:AddLine(e.link) end
			return
		end
		return false
	end)
	row:SetScript("OnClick", function(self)
		local x = self.item
		if x and x.loot and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(x.loot.link) end
	end)
end

local function DrawRow(row, x)
	local s = x.s
	if x.loot then
		local e = x.loot
		row.a:SetText("|cff9d9d9d" .. ns.ShortName(e.boss) .. "|r")
		row.b:SetText(e.link)
		local res = e.result
		if e.winner then
			local roll = RollShort(res)
			row.c:SetText(ns.ColorName(e.winner, ClassOf(s, e.winner)) .. (roll ~= "" and ("  |cff9d9d9d" .. roll .. "|r") or ""))
		elseif res and res.tie then
			row.c:SetText("|cffffd100ничья|r")
		elseif res then
			row.c:SetText("|cff9d9d9dникто|r")
		else
			row.c:SetText("|cff707070не разыгран|r")
		end
		if e.receiver and e.receiver ~= e.winner then
			row.d:SetText("|cffff9020получил|r " .. ns.ColorName(e.receiver, ClassOf(s, e.receiver)))
		else
			row.d:SetText("")
		end
	else
		local p = x.player
		row.a:SetText(ns.ValueColor(p.total))
		row.b:SetText(ns.ColorName(p.name, ClassOf(s, p.name)))
		row.c:SetText(format("|cff9d9d9dминусов %d, плюсов %d|r", p.minus, p.plus))
		local names = {}
		for _, e in ipairs(p.items) do tinsert(names, ItemName(e.link)) end
		row.d:SetText(#names > 0 and ("|cffa335ee" .. tconcat(names, ", ") .. "|r") or "")
	end
end

-------------------------------------------------------------------------------

local function Create(f)
	local head = UI.Text(f, "GameFontNormalSmall")
	head:SetPoint("TOPLEFT", 4, -2)
	head:SetText("Рейды")
	raids = UI.List(f, RAID_ROWS, RAID_H, MakeRaidRow)
	raids:SetPoint("TOPLEFT", 0, -18)
	raids:SetWidth(RAID_W)
	raids.redraw = ns.RefreshUI

	title = UI.Text(f, "GameFontNormal")
	title:SetPoint("TOPLEFT", RAID_W + 12, -2)
	sub = UI.Text(f, "GameFontDisableSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)

	reportBtn = UI.FlatButton(f, "Отчёт для Discord", nil, 22, function()
		local s = Selected()
		if s then ShowReport(s) end
	end, "ghost")
	reportBtn:SetPoint("TOPRIGHT", 0, 0)
	local prev = reportBtn
	for _, m in ipairs({{"players", "Игроки"}, {"loot", "Добыча"}}) do
		local key = m[1]
		local b = UI.FlatButton(f, m[2], 70, 22, function()
			ns.ui.histMode = key
			ns.RefreshUI()
		end, "pill")
		b:SetPoint("RIGHT", prev, "LEFT", -6, 0)
		pills[key] = b
		prev = b
	end

	list = UI.List(f, ROWS, ROW_H, MakeRow)
	list:SetPoint("TOPLEFT", RAID_W + 10, -34)
	list:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	list.redraw = ns.RefreshUI
end

local function Update()
	local s, all = Selected()
	raids:Draw(all, DrawRaidRow)
	local mode = ns.ui.histMode or "loot"
	for key, b in pairs(pills) do b:SetSelected(key == mode) end
	if not s then
		title:SetText("Истории пока нет")
		sub:SetText("Здесь будут прошлые рейды (тестовые не сохраняются).")
		list:Draw({}, DrawRow)
		reportBtn:SetEnabledFlat(false)
		return
	end
	reportBtn:SetEnabledFlat(true)
	title:SetText(format("%s — РЛ %s", date("%d.%m.%Y %H:%M", s.started), tostring(s.leader)))
	sub:SetText(format("свод «%s» · боссов %d · добычи %d", tostring(s.ruleset), Kills(s), #(s.loot or {})))
	local items = {}
	if mode == "loot" then
		for _, e in ipairs(s.loot or {}) do tinsert(items, {s = s, loot = e}) end
	else
		for _, p in ipairs(PlayerTotals(s)) do tinsert(items, {s = s, player = p}) end
	end
	list:Draw(items, DrawRow)
end

ns.RegisterPage("history", Create, Update)
