-- Окно настроек (AceConfig): общие настройки, своды правил (новый, копия, обмен строкой)
-- и редактор правил по разделам. Таблица правил пересобирается после каждой правки.

local _, ns = ...

local format = string.format
local ipairs, tostring, tonumber = ipairs, tostring, tonumber

local APP = "RaidMinus"
local ACD, ACR
local importText = ""
local options

local function RS() return ns.ActiveRuleset() end

local BuildRules

local function Changed()
	BuildRules()
	ns.Refresh()
	if ACR then ACR:NotifyChange(APP) end
end

local function SettingGet(info) return ns.DB.settings[info[#info]] end

-- без NotifyChange: иначе ползунок перестраивается посреди перетаскивания
local function SettingSet(info, v)
	ns.DB.settings[info[#info]] = v
	ns.Refresh()
end

-------------------------------------------------------------------------------
-- редактор правил

-- метка вида правила: красная — автоматика, оранжевая — видно, кто нарушил, белая — вручную
local function KindTag(rule)
	local kind = ns.RuleKind(rule)
	return "|c" .. ns.KIND_HEX[kind] .. "[" .. ns.KIND_NAMES[kind] .. "]|r"
end

local function Toggle(name, order, desc, get, set)
	return {type = "toggle", name = name, order = order, desc = desc, get = get, set = function(_, v) set(v) Changed() end}
end

local function RuleArgs(rule)
	local d = ns.Detector(rule.auto)
	local args = {
		enabled = Toggle("Включено", 1, "Выключенное правило серое в окне /rm; автоправило перестаёт ловить.",
			function() return not rule.off end, function(v) rule.off = (not v) or nil end),
		value = {
			type = "input", name = "Очки", order = 3, width = "half",
			get = function() return tostring(rule.value) end,
			validate = function(_, v)
				if not tonumber(v) then return "Нужно число: -20, 10 или 0" end
				return true
			end,
			set = function(_, v)
				rule.value = tonumber(v)
				Changed()
			end,
		},
		kick = Toggle("Кик", 4, "Пометка «на кик»: пока запись не снята, игрок не побеждает в ролле.",
			function() return rule.kick end, function(v) rule.kick = v or nil end),
		up = {
			type = "execute", name = "Выше", order = 10, width = "half",
			func = function()
				ns.MoveRule(RS(), rule, -1)
				Changed()
			end,
		},
		down = {
			type = "execute", name = "Ниже", order = 11, width = "half",
			func = function()
				ns.MoveRule(RS(), rule, 1)
				Changed()
			end,
		},
	}
	if d then
		args.instant = Toggle("Ставить сразу", 2, "Находку сразу ставить игроку минусом, без вкладки «На проверку». Снять можно в журнале.",
			function() return rule.instant end, function(v) rule.instant = v or nil end)
		args.how = {type = "description", order = 0, name = "|cff9d9d9dКак ловится: " .. d.how .. "|r"}
		for i, p in ipairs(d.params or {}) do
			local pkey = p.key
			args["p_" .. pkey] = {
				type = "input", name = p.name, order = 5 + i * 0.1, width = "half",
				get = function() return tostring(ns.RuleParam(rule, pkey)) end,
				validate = function(_, v)
					local n = tonumber(v)
					if not n or n < 0 then return "Нужно число, например " .. p.default end
					return true
				end,
				set = function(_, v)
					rule.params = rule.params or {}
					rule.params[pkey] = tonumber(v)
					Changed()
				end,
			}
		end
	else
		args.text = {
			type = "input", name = "Текст", order = 0.5, width = "double",
			get = function() return rule.text end,
			set = function(_, v)
				v = strtrim(v)
				if v ~= "" then rule.text = v end
				Changed()
			end,
		}
		args.who = Toggle("Видно, кто нарушил", 2, "Оранжевая метка: нарушителя видно (журнал боя, Skada). Без неё — белая: кто виноват, решает РЛ.",
			function() return rule.who end, function(v) rule.who = v or nil end)
		args.del = {
			type = "execute", name = "Удалить", order = 12, width = "half",
			confirm = true, confirmText = "Удалить правило «" .. rule.text .. "»?",
			func = function()
				ns.RemoveRule(RS(), rule)
				Changed()
			end,
		}
	end
	return args
end

function BuildRules()
	local rs = RS()
	local args = {
		desc = {
			type = "description", order = 0,
			name = "Свод «" .. rs.name .. "». Сменить свод, создать новый или поделиться строкой — вкладка «Своды правил».\n\n"
				.. "Слева разделы: боссы, «Общее» (на любом боссе) и «Плюсы». Правка сразу видна в окне /rm; "
				.. "уже поставленные минусы не меняются.\n\n"
				.. "|c" .. ns.KIND_HEX.auto .. "[автоматика]|r — встроенное правило, ловит аддон (по умолчанию -10, на проверку).\n"
				.. "|c" .. ns.KIND_HEX.known .. "[видно, кто нарушил]|r — нарушителя видно, ставите вы.\n"
				.. "|c" .. ns.KIND_HEX.manual .. "[вручную]|r — кто виноват, решаете вы (например, баф по просьбе).",
		},
	}
	for i, sec in ipairs(ns.SECTIONS) do
		local key = sec.key
		local list = ns.RulesFor(rs, key)
		local group = {
			type = "group", order = i, args = {},
			name = format("%s |cff9d9d9d(%d)|r", sec.name, #list),
		}
		for j, rule in ipairs(list) do
			local title = KindTag(rule) .. "  " .. ns.ValueColor(rule.value) .. "  " .. ns.RuleText(rule)
			if rule.off then title = title .. "  |cff707070(выключено)|r" end
			if rule.instant then title = title .. "  |cffffd100(сразу)|r" end
			group.args[rule.id] = {type = "group", inline = true, order = j, name = title, args = RuleArgs(rule)}
		end
		group.args.add = {
			type = "execute", name = "Добавить правило", order = 1000,
			func = function()
				ns.AddRule(RS(), key)
				Changed()
			end,
		}
		args[key] = group
	end
	options.args.rules.args = args
end

-------------------------------------------------------------------------------
-- таблица настроек

options = {
	type = "group",
	name = "RaidMinus",
	childGroups = "tab",
	args = {
		general = {
			type = "group", name = "Общие", order = 1,
			get = SettingGet, set = SettingSet,
			args = {
				hdrChat = {type = "header", name = "Объявления и шёпот", order = 1},
				announce = {
					type = "select", name = "Объявлять минусы в рейд", order = 2, width = "double",
					values = {instant = "сразу после клика", combat = "после боя (в бою копятся)", off = "не объявлять"},
				},
				whisper = {type = "toggle", name = "Отвечать на !минус в шёпот", order = 3, width = "full"},
				whisperOthers = {type = "toggle", name = "Разрешить узнавать чужие минусы (!минус Имя)", order = 4, width = "full"},
				hideWhispers = {type = "toggle", name = "Прятать эти команды и ответы из моего чата", order = 5, width = "full"},

				hdrRoll = {type = "header", name = "Розыгрыш", order = 10},
				rollTime = {type = "range", name = "Время на ролл, сек", order = 11, min = 10, max = 120, step = 5},
				tieTime = {type = "range", name = "Переролл ничьей, сек", order = 12, min = 5, max = 60, step = 5},
				rollMax = {
					type = "input", name = "Засчитывать /roll 1–N, N =", order = 13,
					get = function() return tostring(ns.DB.settings.rollMax) end,
					validate = function(_, v)
						local n = tonumber(v)
						if not n or n < 2 or n ~= math.floor(n) then return "Нужно целое число, например 100" end
						return true
					end,
					set = function(_, v) ns.DB.settings.rollMax = tonumber(v) end,
				},
				rollLines = {type = "range", name = "Строк итога в рейд", order = 13.5, min = 3, max = 25, step = 1,
					desc = "Итог ролла пишется в рейд построчно: каждый игрок отдельным сообщением, победитель со звездой. Не засчитанные — ещё до 5 строк."},
				rollCountdown = {type = "toggle", name = "Напоминать «осталось 10 сек»", order = 14, width = "full"},
				collectLoot = {type = "toggle", name = "Собирать в список добычу, которую лутаю я", order = 15, width = "full"},
				dropPanel = {type = "toggle", name = "Показывать окошко «Добыча», когда открываю тело или ответственный скидывает список", order = 15.1, width = "full"},
				autoDropLoot = {type = "toggle", name = "Добавлять такую добычу в список сразу, без кнопки «+»", order = 15.2, width = "full"},
				watchOthers = {
					type = "toggle", name = "Чужой ролл: предмет в список, броски считаю с минусами", order = 15.3, width = "full",
					desc = "Лидер, ассистент или ответственный за добычу пишет в рейд «ролл [предмет]» — предмет попадает в список, а аддон молча считает броски с минусами. В чат — только по кнопке «Закончить розыгрыш» или «Итог в чат».",
				},
				lootQuality = {
					type = "select", name = "Какую добычу собирать", order = 16,
					values = {[2] = "необычную и выше", [3] = "редкую и выше", [4] = "эпическую и выше"},
				},

				hdrOther = {type = "header", name = "Прочее", order = 20},
				reloadPrompt = {
					type = "toggle", name = "После убийства босса предлагать /reload", order = 21, width = "full",
					desc = "WoW записывает данные аддонов на диск только при /reload и выходе: при вылете игры минусы рейда пропадут. "
						.. "Если стоит SkadaDiscord, он делает /reload сам, и окно не появится.",
				},
				minimap = {
					type = "toggle", name = "Кнопка у миникарты", order = 22, width = "full",
					get = function() return not ns.DB.minimap.hide end,
					set = function(_, v)
						ns.DB.minimap.hide = not v
						if ns.DBI then
							if v then ns.DBI:Show("RaidMinus") else ns.DBI:Hide("RaidMinus") end
						end
					end,
				},
			},
		},
		sets = {
			type = "group", name = "Своды правил", order = 2,
			args = {
				active = {
					type = "select", name = "Свод для рейда", order = 1, width = "double",
					values = function()
						local t = {}
						for _, rs in ipairs(ns.DB.rulesets) do t[rs.id] = rs.name end
						return t
					end,
					get = function() return RS().id end,
					set = function(_, v)
						ns.SetActiveRuleset(v)
						Changed()
					end,
				},
				name = {
					type = "input", name = "Название", order = 2, width = "double",
					get = function() return RS().name end,
					set = function(_, v)
						v = strtrim(v)
						if v ~= "" then ns.RenameRuleset(RS(), v) end
						Changed()
					end,
				},
				hdrNew = {type = "header", name = "Новый свод", order = 10},
				create = {
					type = "execute", name = "Новый пустой свод", order = 12,
					desc = "Только встроенные автоправила — свои правила добавьте во вкладке «Правила».",
					func = function()
						local rs = ns.EmptyRuleset("Новый свод")
						ns.SetActiveRuleset(rs.id)
						Changed()
					end,
				},
				copy = {
					type = "execute", name = "Копия текущего", order = 13,
					func = function()
						local rs = ns.CopyRuleset(RS())
						ns.SetActiveRuleset(rs.id)
						Changed()
					end,
				},
				delete = {
					type = "execute", name = "Удалить текущий", order = 14,
					confirm = true, confirmText = "Удалить текущий свод правил?",
					disabled = function() return #ns.DB.rulesets < 2 end,
					func = function()
						ns.DeleteRuleset(RS())
						Changed()
					end,
				},
				hdrShare = {type = "header", name = "Поделиться", order = 20},
				export = {
					type = "input", name = "Экспорт текущего свода: выделите строку и скопируйте (Ctrl+C)", order = 21,
					width = "full", multiline = 5,
					get = function() return ns.ExportRuleset(RS()) end,
					set = function() end,
				},
				import = {
					type = "input", name = "Импорт: вставьте строку RM1:... (Ctrl+V) и нажмите «Принять»", order = 22,
					width = "full", multiline = 5,
					get = function() return importText end,
					set = function(_, v)
						local rs, err = ns.ImportRuleset(v)
						if rs then
							importText = ""
							ns.SetActiveRuleset(rs.id)
							ns.Print(format("импортирован свод «%s», правил: %d.", rs.name, #rs.rules))
						else
							importText = v
							ns.Print("импорт не удался: " .. tostring(err))
						end
						Changed()
					end,
				},
			},
		},
		rules = {
			type = "group", name = "Правила", order = 3, childGroups = "tree",
			args = {},
		},
	},
}

function ns.OpenOptions(tab)
	if not ACD then
		ns.Print("окно настроек недоступно (нет AceConfig).")
		return
	end
	BuildRules()
	ACD:Open(APP)
	if tab == "rules" then
		ACD:SelectGroup(APP, "rules", ns.ui.viewBoss or ns.CurrentBoss() or ns.SECTIONS[1].key)
	elseif tab then
		ACD:SelectGroup(APP, tab)
	end
end

ns.OnLoad(function()
	local AceConfig = LibStub("AceConfig-3.0", true)
	ACD = LibStub("AceConfigDialog-3.0", true)
	ACR = LibStub("AceConfigRegistry-3.0", true)
	if not AceConfig or not ACD then return end
	BuildRules()
	AceConfig:RegisterOptionsTable(APP, options)
	ACD:SetDefaultSize(APP, 860, 640)
end)
