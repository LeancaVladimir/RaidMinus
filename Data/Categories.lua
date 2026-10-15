-- Категории лута — для подписи в объявлении ролла: «Ролл [предмет] (оружие с Лича)».
-- Тринкет определяется по слоту, оружие с Лича — по списку предметов (ЦЛК 25 об. и гер., из AtlasLoot).

local _, ns = ...

ns.CATEGORIES = {
	{key = "trinket", name = "тринкеты"},
	{key = "lk_weapon", name = "оружие с Лича"},
	{key = "loot", name = "остальной лут"},
}

local LK_WEAPONS = {
	-- 25 обычный
	[50426] = true, [50427] = true, [50070] = true, [50012] = true, [50428] = true,
	[49997] = true, [50425] = true, [50429] = true, [49981] = true,
	-- 25 героический
	[50736] = true, [50732] = true, [50730] = true, [50737] = true, [50734] = true,
	[50738] = true, [50735] = true, [50731] = true, [50733] = true,
}

local names = {}
for _, c in ipairs(ns.CATEGORIES) do names[c.key] = c.name end

function ns.CategoryName(key) return names[key or ""] or tostring(key) end

function ns.ItemId(link)
	return tonumber(tostring(link or ""):match("item:(%d+)"))
end

function ns.ItemCategory(link)
	local id = ns.ItemId(link)
	if id and LK_WEAPONS[id] then return "lk_weapon" end
	local equipLoc = select(9, GetItemInfo(link))
	if equipLoc == "INVTYPE_TRINKET" then return "trinket" end
	return "loot"
end
