-- Deffar Profession Profit: what a food does (its Well Fed buff), for the Cooking tab's Effect dropdown. The addon holds no table of food effects: the
-- effect is read from the food's own tooltip text in the game (so a new food needs nothing here) and sorted by the stat words in it.
-- The tooltip is read through a hidden GameTooltip (SetItemByID, then the TextLeft lines), the classic way; UNVERIFIED on Forever until the human
-- opens the dropdown in game (plans/addons/DeffarProfessionProfit.md). The words are English: another client language lists nothing under a stat.
local _, F = ...

local E = {}
F.Effects = E

-- The dropdown's entries, in order: { key, text, words that put a food in it }. "all" shows every food, "other" is a buff that none of the stat words
-- above names, "none" a food that only restores health.
E.CATEGORIES = {
    { key = "all", text = "All" },
    { key = "stamina", text = "Stamina", words = { "stamina" } },
    { key = "strength", text = "Strength", words = { "strength" } },
    { key = "agility", text = "Agility", words = { "agility" } },
    { key = "intellect", text = "Intellect", words = { "intellect" } },
    { key = "spirit", text = "Spirit", words = { "spirit" } },
    { key = "spell", text = "Spell damage", words = { "spell damage", "damage done by magical spells", "spell power" } },
    { key = "healing", text = "Healing", words = { "healing" } },
    { key = "mana", text = "Mana regen", words = { "mana per 5", "mana every 5", "mana regeneration" } },
    { key = "health", text = "Health regen", words = { "health per 5", "health every 5", "health regeneration" } },
    { key = "fishing", text = "Fishing", words = { "fishing" } },
    { key = "other", text = "Other buff" },
    { key = "none", text = "No buff" },
}

local BY_KEY = {}
for _, entry in ipairs(E.CATEGORIES) do BY_KEY[entry.key] = entry end

-- Only Cooking has foods to sort.
function E.CanFilter(tab)
    return tab == "cooking"
end

-- The saved choice when it names an entry, else nil (= All).
function E.Valid(key)
    if key == nil or key == "all" then return nil end
    return BY_KEY[key] and key or nil
end

function E.Text(key)
    return (BY_KEY[key] or BY_KEY.all).text
end

-- What a tooltip's text gives: { buff = true, stamina = true, ... }. A buff is a Well Fed line or a duration in minutes; a stat word counts whole.
function E.Classify(text)
    local lower = tostring(text or ""):lower()
    local set = {}
    for _, entry in ipairs(E.CATEGORIES) do
        for _, word in ipairs(entry.words or {}) do
            if lower:find(word, 1, true) then set[entry.key] = true; break end
        end
    end
    if lower:find("well fed", 1, true) or lower:find("%d+ min") or next(set) then set.buff = true end
    return set
end

-- Whether a set (E.Classify) is in the dropdown's entry `key`.
function E.InSet(set, key)
    if key == nil or key == "all" then return true end
    if key == "none" then return set.buff ~= true end
    if key == "other" then
        if not set.buff then return false end
        for _, entry in ipairs(E.CATEGORIES) do
            if entry.words and set[entry.key] then return false end
        end
        return true
    end
    return set[key] == true
end

local scan   -- the hidden tooltip, false when it could not be made
local cache = {}   -- [itemID] = a set; only for a tooltip that was fully loaded
local texts = {}   -- [itemID] = that tooltip's text (for the amounts)

local function ScanTip()
    if scan ~= nil then return scan or nil end
    scan = false
    if type(CreateFrame) == "function" then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "DeffarProfessionProfitScanTip", nil, "GameTooltipTemplate")
        if ok and type(tip) == "table" and (F.Has(tip, "SetItemByID") or F.Has(tip, "SetHyperlink")) and F.Has(tip, "NumLines") then scan = tip end
    end
    return scan or nil
end

-- The tooltip text of an item, or nil when the game has not loaded it (the first line is not there yet, or no "Use:" line: the item data is still coming;
-- GET_ITEM_INFO_RECEIVED redraws the window then).
local function TooltipText(itemID)
    local tip = ScanTip()
    if not tip then return nil end
    if type(UIParent) == "table" then tip:SetOwner(UIParent, "ANCHOR_NONE") end
    tip:ClearLines()
    if F.Has(tip, "SetItemByID") then tip:SetItemByID(itemID) else tip:SetHyperlink("item:" .. itemID) end
    local lines = {}
    for index = 1, tip:NumLines() do
        local left = _G["DeffarProfessionProfitScanTipTextLeft" .. index]
        local text = left and left.GetText and left:GetText() or nil
        if F.String(text) then lines[#lines + 1] = text end
    end
    local joined = table.concat(lines, "\n")
    if #lines < 2 or joined:find(_G.RETRIEVING_ITEM_INFO or "Retrieving item information", 1, true) then return nil end
    if not joined:lower():find((_G.ITEM_SPELL_TRIGGER_ONUSE or "Use:"):lower(), 1, true) then return nil end   -- a food always has a Use: line
    return joined
end

-- The set of an item (cached once read), or nil while the game has not loaded its tooltip.
function E.Of(itemID)
    if not F.Integer(itemID, 1, 2147483647) then return nil end
    if cache[itemID] then return cache[itemID] end
    if F.Has(F, "ItemMeta") then F.ItemMeta(itemID) end   -- (asks the game for the item's data; the read below then finds it)
    local text = TooltipText(itemID)
    if not text then return nil end
    cache[itemID] = E.Classify(text)
    texts[itemID] = text
    return cache[itemID]
end

-- False when this client gives no tooltip to read (the dropdown then says so instead of waiting for ever).
function E.Available()
    return ScanTip() ~= nil
end

-- Forgets what was read (the tests; and a language change would need it).
function E.ForgetAll()
    cache, texts = {}, {}
end

-- Whether an entry is a stat with a number to show (Stamina, Agility ... : not All, Other buff or No buff).
function E.HasStat(key)
    return BY_KEY[key] ~= nil and BY_KEY[key].words ~= nil
end

-- How much of the stat `key` the food gives, read from its tooltip ("gain 8 Stamina", "Increases Agility by 10", "Restores 8 mana per 5 sec": the number
-- right before the stat word, else the first one after it in the same sentence); the highest when several words fit. nil when it is not loaded or
-- no number is found.
function E.Amount(itemID, key)
    local entry = BY_KEY[key]
    if not (entry and entry.words) or not E.Of(itemID) then return nil end
    local lower = texts[itemID]:lower()
    local best
    for _, word in ipairs(entry.words) do
        local from = 1
        while true do
            local first, last = lower:find(word, from, true)
            if not first then break end
            local number = lower:sub(math.max(1, first - 12), first - 1):match("(%d+)%s*$")
            if not number then
                local tail = lower:sub(last + 1, last + 40)
                number = (tail:match("^[^%.]*") or tail):match("(%d+)")
            end
            number = tonumber(number)
            if number and (not best or number > best) then best = number end
            from = last + 1
        end
    end
    return best
end

-- true / false when the item is (not) in the entry `key`, nil while its tooltip is not loaded.
function E.Has(itemID, key)
    if key == nil or key == "all" then return true end
    local set = E.Of(itemID)
    if not set then return nil end
    return E.InSet(set, key)
end
