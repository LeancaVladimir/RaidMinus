-- Общие элементы окна: панели, кнопки, поля ввода, подсказки и списки с прокруткой.
-- Внешний вид как у SkadaDiscord: плоский тёмный фон, полоса заголовка.

local _, ns = ...

local UI = {}
ns.UI = UI

local FLAT = "Interface\\Buttons\\WHITE8X8"
local counter = 0

local function NextName(kind)
	counter = counter + 1
	return "RaidMinus" .. kind .. counter
end

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
	box:SetBackdropColor(0, 0, 0, 0.45)
	box:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
	return box
end

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
		row:GetHighlightTexture():SetVertexColor(0.45, 0.54, 0.85, 0.2)
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
		row.bg:SetTexture(0.85, 0.3, 0.3, 0.3)
	else
		row.bg:SetTexture(0, 0, 0, 0)
	end
end
