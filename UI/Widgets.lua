-- Общие элементы окон: панели, кнопки, плоские кнопки (вкладки, строки, «таблетки», переключатели),
-- выпадающие списки, поля ввода, подсказки и списки с прокруткой.
-- Внешний вид: плоский тёмный фон, полоса заголовка с красной чертой, золотой текст выбранного.

local _, ns = ...

local UI = {}
ns.UI = UI

local FLAT = "Interface\\Buttons\\WHITE8X8"
local counter = 0

local function NextName(kind)
	counter = counter + 1
	return "RaidMinus" .. kind .. counter
end

UI.GOLD = {1, 0.82, 0}
UI.MUTED = {0.56, 0.56, 0.61}

function UI.Flat(f, layer, r, g, b, a)
	local t = f:CreateTexture(nil, layer)
	t:SetTexture(r, g, b, a or 1)
	return t
end

function UI.Panel(f, alpha)
	f:SetBackdrop({bgFile = FLAT, edgeFile = FLAT, edgeSize = 1})
	f:SetBackdropColor(0.06, 0.06, 0.08, alpha or 0.95)
	f:SetBackdropBorderColor(0, 0, 0, 1)
end

function UI.Box(parent)
	local box = CreateFrame("Frame", nil, parent)
	box:SetBackdrop({bgFile = FLAT, edgeFile = FLAT, edgeSize = 1})
	box:SetBackdropColor(0, 0, 0, 0.4)
	box:SetBackdropBorderColor(0.16, 0.18, 0.22, 1)
	return box
end

-- полоса заголовка; возвращает текст заголовка и кнопку закрытия
function UI.TitleBar(f, text)
	local bg = UI.Flat(f, "ARTWORK", 0.16, 0.18, 0.24, 1)
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("TOPRIGHT", -1, -1)
	bg:SetHeight(26)
	local accent = UI.Flat(f, "OVERLAY", 0.85, 0.3, 0.3, 1)
	accent:SetPoint("TOPLEFT", bg, "BOTTOMLEFT")
	accent:SetPoint("TOPRIGHT", bg, "BOTTOMRIGHT")
	accent:SetHeight(2)
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("LEFT", bg, "LEFT", 10, 0)
	title:SetText(text)
	local close = CreateFrame("Button", NextName("Close"), f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 3, 3)
	return title, close
end

function UI.Button(parent, text, width, onClick)
	local b = CreateFrame("Button", NextName("Button"), parent, "UIPanelButtonTemplate")
	b:SetWidth(width)
	b:SetHeight(22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

function UI.Text(parent, template, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	return fs
end

function UI.Check(parent, label, onClick)
	local cb = CreateFrame("CheckButton", NextName("Check"), parent, "UICheckButtonTemplate")
	cb:SetWidth(22)
	cb:SetHeight(22)
	_G[cb:GetName() .. "Text"]:SetText(label)
	cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	return cb
end

-------------------------------------------------------------------------------
-- плоские кнопки: style = tab | row | pill | ghost | seg

local STYLES = {
	tab = {bg = {0.08, 0.09, 0.12, 1}, border = {0.16, 0.18, 0.22, 1}, text = {0.72, 0.72, 0.76},
		selBg = {0.14, 0.15, 0.22, 1}, selText = UI.GOLD, hover = {0.12, 0.13, 0.18, 1}, font = "GameFontHighlight"},
	row = {bg = {0, 0, 0, 0}, border = {0, 0, 0, 0}, text = {0.86, 0.86, 0.89},
		selBg = {0.29, 0.11, 0.13, 1}, selText = {1, 1, 1}, hover = {0.11, 0.12, 0.17, 1}, font = "GameFontHighlight"},
	pill = {bg = {0.08, 0.09, 0.12, 1}, border = {0.21, 0.23, 0.29, 1}, text = {0.78, 0.78, 0.82},
		selBg = {1, 0.82, 0, 1}, selBorder = {1, 0.82, 0, 1}, selText = {0.06, 0.06, 0.09}, hover = {0.13, 0.14, 0.19, 1}},
	seg = {bg = {0.08, 0.09, 0.12, 1}, border = {0.21, 0.23, 0.29, 1}, text = {0.78, 0.78, 0.82},
		selBg = {1, 0.82, 0, 1}, selBorder = {1, 0.82, 0, 1}, selText = {0.06, 0.06, 0.09}, hover = {0.13, 0.14, 0.19, 1}},
	ghost = {bg = {0.11, 0.11, 0.15, 1}, border = {0.21, 0.23, 0.29, 1}, text = {0.87, 0.87, 0.9},
		selBg = {0.29, 0.11, 0.13, 1}, selText = {1, 1, 1}, hover = {0.16, 0.17, 0.22, 1}},
}

local function Paint(b)
	local st = b.style
	local bg = (b.selected and st.selBg) or (b.hover and st.hover) or st.bg
	b:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
	local bd = (b.selected and st.selBorder) or st.border
	b:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
	local tc = b.disabled and UI.MUTED or (b.selected and st.selText) or b.textColor or st.text
	b.label:SetTextColor(tc[1], tc[2], tc[3])
end

function UI.FlatButton(parent, text, width, height, onClick, style)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(width)
	b:SetHeight(height or 22)
	b.style = STYLES[style or "ghost"]
	b:SetBackdrop({bgFile = FLAT, edgeFile = FLAT, edgeSize = 1})
	b.label = b:CreateFontString(nil, "OVERLAY", b.style.font or "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", 8, 0)
	b.label:SetPoint("RIGHT", -8, 0)
	b.label:SetJustifyH(style == "row" and "LEFT" or "CENTER")
	b.label:SetText(text or "")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if onClick then b:SetScript("OnClick", onClick) end
	b:SetScript("OnEnter", function(self)
		self.hover = true
		Paint(self)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if self.tooltip(GameTooltip, self) == false then GameTooltip:Hide() else GameTooltip:Show() end
		end
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		Paint(self)
		GameTooltip:Hide()
	end)
	function b:SetLabel(t) self.label:SetText(t or "") end
	function b:SetSelected(on)
		self.selected = on and true or nil
		Paint(self)
	end
	function b:SetTextColor(c)
		self.textColor = c
		Paint(self)
	end
	function b:SetEnabledFlat(on)
		self.disabled = not on or nil
		if on then self:Enable() else self:Disable() end
		Paint(self)
	end
	Paint(b)
	return b
end

-- переключатель из нескольких кнопок: options = {{key, text, width}}; onSelect(key)
function UI.Seg(parent, options, onSelect)
	local seg = CreateFrame("Frame", nil, parent)
	seg.buttons = {}
	local x = 0
	for _, o in ipairs(options) do
		local key = o[1]
		local b = UI.FlatButton(seg, o[2], o[3] or 80, 22, function()
			seg:SetValue(key)
			onSelect(key)
		end, "seg")
		b:SetPoint("LEFT", x, 0)
		x = x + (o[3] or 80) - 1
		seg.buttons[key] = b
	end
	seg:SetWidth(x + 1)
	seg:SetHeight(22)
	function seg:SetValue(key)
		self.value = key
		for k, b in pairs(self.buttons) do b:SetSelected(k == key) end
	end
	return seg
end

-- выпадающий список: getItems() -> {{key, text}}, onSelect(key); dd:SetValue(key, text)
local menuFrame
function UI.Dropdown(parent, width, getItems, onSelect)
	local dd = UI.FlatButton(parent, "", width, 22, nil, "ghost")
	dd.label:SetJustifyH("LEFT")
	local arrow = UI.Text(dd, "GameFontDisableSmall", "RIGHT")
	arrow:SetPoint("RIGHT", -2, 0)
	arrow:SetText("|TInterface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up:18|t")
	dd.label:SetPoint("RIGHT", -20, 0)
	dd:SetScript("OnClick", function(self)
		if not menuFrame then menuFrame = CreateFrame("Frame", "RaidMinusDropMenu", UIParent, "UIDropDownMenuTemplate") end
		local menu = {}
		for _, it in ipairs(getItems()) do
			local key = it[1]
			menu[#menu + 1] = {text = it[2], checked = key == self.value, func = function()
				self:SetValue(key, it[2])
				onSelect(key)
			end}
		end
		EasyMenu(menu, menuFrame, self, 0, 0, "MENU")
	end)
	function dd:SetValue(key, text)
		self.value = key
		self:SetLabel(text)
	end
	return dd
end

-- кнопка-картинка (галочка, крест)
function UI.IconButton(parent, texture, size, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(size or 18)
	b:SetHeight(size or 18)
	b:SetNormalTexture(texture)
	b:SetHighlightTexture(texture, "ADD")
	b:SetScript("OnClick", onClick)
	return b
end

-- fill(GameTooltip, виджет) заполняет подсказку; вернуть false — не показывать
function UI.Tooltip(widget, fill)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if fill(GameTooltip, self) == false then
			GameTooltip:Hide()
		else
			GameTooltip:Show()
		end
	end)
	widget:SetScript("OnLeave", GameTooltip_Hide)
end

-- поле ввода с серой подсказкой внутри, пока пусто
function UI.EditBox(parent, width, placeholder, onEnter)
	local e = CreateFrame("EditBox", NextName("Edit"), parent, "InputBoxTemplate")
	e:SetWidth(width)
	e:SetHeight(20)
	e:SetAutoFocus(false)
	e:SetScript("OnEnterPressed", function(self)
		if onEnter then onEnter(self) end
		self:ClearFocus()
	end)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	if placeholder then
		local hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("LEFT", 2, 0)
		hint:SetText(placeholder)
		local function Update()
			if e:HasFocus() or e:GetText() ~= "" then hint:Hide() else hint:Show() end
		end
		e:HookScript("OnEditFocusGained", Update)
		e:HookScript("OnEditFocusLost", Update)
		e:HookScript("OnTextChanged", Update)
		e.UpdateHint = Update
	end
	return e
end

-- список с прокруткой: rows строк высотой rowH; make(row, i) оформляет строку.
-- box:Draw(items, draw) рисует видимую часть; box.redraw вызывается при прокрутке.
function UI.List(parent, rows, rowH, make)
	local box = UI.Box(parent)
	box:SetHeight(rows * rowH + 8)
	box.rows = {}
	local scroll = CreateFrame("ScrollFrame", NextName("Scroll"), box, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -26, 4)
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, rowH, function()
			if box.redraw then box.redraw() end
		end)
	end)
	box.scroll = scroll

	for i = 1, rows do
		local row = CreateFrame("Button", nil, box)
		row:SetHeight(rowH)
		row:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4 - (i - 1) * rowH)
		row:SetPoint("RIGHT", box, "RIGHT", -26, 0)
		row:SetHighlightTexture(FLAT)
		row:GetHighlightTexture():SetVertexColor(0.45, 0.54, 0.85, 0.15)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:EnableMouseWheel(true)
		row:SetScript("OnMouseWheel", function(_, delta) ScrollFrameTemplate_OnMouseWheel(scroll, delta) end)
		row.bg = UI.Flat(row, "BACKGROUND", 0, 0, 0, 0)
		row.bg:SetAllPoints()
		make(row, i)
		box.rows[i] = row
	end

	function box:Draw(items, draw)
		FauxScrollFrame_Update(scroll, #items, rows, rowH)
		local offset = FauxScrollFrame_GetOffset(scroll)
		for i = 1, rows do
			local row, item = self.rows[i], items[offset + i]
			row.item = item
			if item then
				draw(row, item, offset + i)
				row:Show()
			else
				row:Hide()
			end
		end
	end

	return box
end

-- подсветка выбранной строки
function UI.Select(row, on)
	if on then
		row.bg:SetTexture(0.29, 0.11, 0.13, 1)
	else
		row.bg:SetTexture(0, 0, 0, 0)
	end
end

-- цветная метка правила: красная — автоматика, оранжевая — видно, кто нарушил, белая — вручную
function UI.KindMark(row)
	local t = row:CreateTexture(nil, "ARTWORK")
	t:SetTexture(FLAT)
	t:SetWidth(5)
	t:SetHeight(14)
	return t
end

-- значок предмета с рамкой цвета качества
function UI.ItemIcon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(size)
	f:SetHeight(size)
	f:SetBackdrop({bgFile = FLAT, edgeFile = FLAT, edgeSize = 1})
	f:SetBackdropColor(0, 0, 0, 1)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetPoint("TOPLEFT", 1, -1)
	f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	function f:SetItem(id, link)
		local _, _, q, _, _, _, _, _, _, tex = GetItemInfo(link or id)
		self.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
		local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 4]
		if c then self:SetBackdropBorderColor(c.r, c.g, c.b, 1) else self:SetBackdropBorderColor(0.64, 0.21, 0.93, 1) end
	end
	return f
end
