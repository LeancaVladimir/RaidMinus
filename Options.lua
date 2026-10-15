-- Окно настроек (AceConfig): общие настройки (объявления, розыгрыш, добыча, клавиши, обновления)
-- и своды правил (название, обмен строкой). Сами правила правятся во вкладке «Правила» главного окна.

local _, ns = ...

local format = string.format
local ipairs, tostring, tonumber = ipairs, tostring, tonumber

local APP = "RaidMinus"
local ACD, ACR
local importText = ""

local function RS() return ns.ActiveRuleset() end

local function Changed()
	ns.Refresh()
	if ACR then ACR:NotifyChange(APP) end
end

local function SettingGet(info) return ns.DB.settings[info[#info]] end

-- без NotifyChange: иначе ползунок перестраивается посреди перетаскивания
local function SettingSet(info, v)
	ns.DB.settings[info[#info]] = v
	ns.Refresh()
end

-- клавиша из «Назначения клавиш»
local function Binding(action, name, order, desc)
	return {
		type = "keybinding", name = name, order = order, desc = desc,
		get = function() return GetBindingKey(action) end,
		set = function(_, key)
			if InCombatLockdown() then
				ns.Print("клавиши меняются только вне боя.")
				return
			end
			local old = GetBindingKey(action)
			if old then SetBinding(old) end
			if key and key ~= "" then SetBinding(key, action) end
			SaveBindings(GetCurrentBindingSet())
		end,
	}
end

local options = {
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
					desc = "У каждого правила можно выбрать своё (вкладка «Правила», поле «Объявление»).",
					values = {instant = "сразу после клика", combat = "после боя (в бою копятся)", off = "не объявлять"},
				},
				whisper = {type = "toggle", name = "Отвечать на !минус в шёпот", order = 3, width = "full"},
				whisperOthers = {type = "toggle", name = "Разрешить узнавать чужие минусы (!минус Имя)", order = 4, width = "full"},
				hideWhispers = {type = "toggle", name = "Прятать эти команды и ответы из моего чата", order = 5, width = "full"},

				hdrRoll = {type = "header", name = "Розыгрыш", order = 10},
				rollTime = {type = "range", name = "Время на ролл, сек", order = 11, min = 10, max = 120, step = 5},
				tieTime = {type = "range", name = "Переролл ничьей, сек", order = 12, min = 5, max = 60, step = 5},
				rollMax = {
					type = "input", name = "Засчитывать /roll 1-N, N =", order = 13,
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
				watchOthers = {
					type = "toggle", name = "Чужой ролл: предмет в список, броски считаю с минусами", order = 15, width = "full",
					desc = "Лидер, ассистент или ответственный за добычу пишет в рейд «ролл [предмет]» — предмет попадает в список, а аддон молча считает броски с минусами. В чат — только по кнопке «Закончить розыгрыш» или «Итог в чат».",
				},

				hdrLoot = {type = "header", name = "Добыча", order = 20},
				lootDesc = {type = "description", order = 20.1, fontSize = "medium",
					name = "Аддон сам узнаёт, что упало с босса, даже если тело открывали не вы, и записывает важное в розыгрыш. Окно «Добыча» (/rm добыча) листает боссов стрелками и показывает, что не включено."},
				lootFilter = {
					type = "select", name = "Что разыгрывать", order = 21, width = "double",
					values = {heroic = "гер. снаряжение ЦЛК 25, жетоны, маунт (осколки, саронит — нет)", epic = "все эпики (кроме мусора)"},
				},
				lootMinIlvl = {
					type = "range", name = "Предметы не из ЦЛК 25 гер.: уровень от", order = 22, min = 200, max = 290, step = 1,
					disabled = function() return ns.DB.settings.lootFilter ~= "heroic" end,
					desc = "Для «гер. снаряжения»: предмет, которого нет в таблице добычи ЦЛК 25 гер., проходит, если он эпический, надевается и его уровень не ниже этого.",
				},
				lootAuto = {type = "toggle", name = "Прошедшее фильтр сразу добавлять в розыгрыш", order = 23, width = "full"},
				lootPopup = {
					type = "select", name = "Окно «Добыча» открывать само", order = 24, width = "double",
					values = {new = "при новой добыче", missing = "только если что-то не в розыгрыше", off = "не открывать"},
				},
				srcCorpse = {type = "toggle", name = "Источник: тело, которое открыл я", order = 25, width = "full"},
				srcRaidRoll = {type = "toggle", name = "Источник: тело открыл другой с аддоном RaidRoll", order = 26, width = "full",
					desc = "RaidRoll рассылает добычу тела всему рейду по скрытому каналу — так видно добычу, даже если тело открыли не вы."},
				srcChat = {type = "toggle", name = "Источник: строки «Вася получает добычу: [предмет]»", order = 27, width = "full"},
				srcList = {type = "toggle", name = "Источник: список ссылок от лидера, ассистента или ответственного", order = 28, width = "full"},

				hdrQuick = {type = "header", name = "Быстрые минусы и клавиши", order = 30},
				keyTarget = Binding("RAIDMINUS_TARGET", "Минус цели (меню 1-9)", 31,
					"Возьмите игрока рейда в цель и нажмите: у курсора меню правил текущего босса и быстрых «Общих», цифра — поставить."),
				keyCompact = Binding("RAIDMINUS_COMPACT", "Мини-панель", 32),
				keyToggle = Binding("RAIDMINUS_TOGGLE", "Окно RaidMinus", 33),
				keyLoot = Binding("RAIDMINUS_LOOT", "Окно «Добыча»", 34),
				compactAuto = {type = "toggle", name = "Мини-панель сама появляется на пуле босса, если окно закрыто", order = 35, width = "full"},

				hdrOther = {type = "header", name = "Прочее", order = 40},
				reloadPrompt = {
					type = "toggle", name = "После убийства босса предлагать /reload", order = 41, width = "full",
					desc = "WoW записывает данные аддонов на диск только при /reload и выходе: при вылете игры минусы рейда пропадут. "
						.. "Если стоит SkadaDiscord, он делает /reload сам, и окно не появится.",
				},
				minimap = {
					type = "toggle", name = "Кнопка у миникарты", order = 42, width = "full",
					get = function() return not ns.DB.minimap.hide end,
					set = function(_, v)
						ns.DB.minimap.hide = not v
						if ns.DBI then
							if v then ns.DBI:Show("RaidMinus") else ns.DBI:Hide("RaidMinus") end
						end
					end,
				},
				versionCheck = {
					type = "toggle", name = "Узнавать о новой версии от других игроков с RaidMinus", order = 43, width = "full",
					desc = "Аддон сам не скачивает обновления. Он сообщает о новой версии, если она есть у кого-то в рейде или гильдии. Скачать: " .. ns.RELEASES,
				},
				version = {type = "description", order = 44, name = function()
					return format("|cff9d9d9dВерсия %s%s. Новые версии: %s|r", ns.VERSION,
						ns.newest and (", есть новее: |cffffd100" .. ns.newest .. "|r|cff9d9d9d") or "", ns.RELEASES)
				end},
			},
		},
		sets = {
			type = "group", name = "Своды правил", order = 2,
			args = {
				desc = {type = "description", order = 0, fontSize = "medium",
					name = "Правила свода правятся во вкладке «Правила» главного окна (/rm правила). Здесь — название и обмен строкой."},
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
	},
}

function ns.OpenOptions(tab)
	if tab == "rules" then
		ns.ShowTab("rules")
		return
	end
	if not ACD then
		ns.Print("окно настроек недоступно (нет AceConfig).")
		return
	end
	ACD:Open(APP)
	if tab then ACD:SelectGroup(APP, tab) end
end

ns.OnLoad(function()
	local AceConfig = LibStub("AceConfig-3.0", true)
	ACD = LibStub("AceConfigDialog-3.0", true)
	ACR = LibStub("AceConfigRegistry-3.0", true)
	if not AceConfig or not ACD then return end
	AceConfig:RegisterOptionsTable(APP, options)
	ACD:SetDefaultSize(APP, 760, 620)
end)
