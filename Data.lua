-- Deffar Profession Profit: data. Accessible-value guards, price lookups, the saved vendor-price and recipe
-- caches, the Master Chef rank read, and the list of rows the window shows. No frames (UI.lua) and
-- no event registration (Core.lua). The arithmetic is in Calc.lua.
local addonName, F = ...
F.VERSION = "0.43.11"
F.CALLER = addonName   -- Auctionator wants the calling addon's name as its first argument
F.eventIssues = {}

-- Master Chef: legacy Professions tree 1187, node 110289, five ranks (FOR-0174).
F.RANK_TREE, F.RANK_NODE, F.RANK_MAX = 1187, 110289, 5
-- Cooked food: item class Consumable (0), subclass Food & Drink (5) (FOR-0176).
F.FOOD_CLASS, F.FOOD_SUBCLASS = 0, 5

local MAX_INT = 9007199254740991

-- Same accessible-value guards the other Forever addons use (FOR-0008/0009 pattern).
function F.SafetyAvailable()
    return type(issecretvalue) == "function" and type(canaccessvalue) == "function"
        and type(issecrettable) == "function" and type(canaccesstable) == "function"
end

function F.Readable(value)
    return F.SafetyAvailable() and not issecretvalue(value) and canaccessvalue(value)
end

function F.Table(value)
    return F.Readable(value) and type(value) == "table"
        and not issecrettable(value) and canaccesstable(value)
end

function F.Has(object, method)
    return F.Table(object) and F.Readable(object[method]) and type(object[method]) == "function"
end

function F.String(value)
    return F.Readable(value) and type(value) == "string"
end

function F.Number(value)
    return F.Readable(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function F.Integer(value, minimum, maximum)
    return F.Number(value) and value >= minimum and value <= maximum and value == math.floor(value)
end

function F.Print(message)
    print("|cffffd100Deffar Profession Profit|r " .. message)
end

-- Spam guard: true when `key` has not been
-- let through in the last `seconds`, and then marks it as let through now. Without a clock it lets everything through.
local throttled = {}
function F.Throttle(key, seconds)
    if type(GetTime) ~= "function" then return true end
    local now = GetTime()
    local last = throttled[key]
    if last and now - last < seconds and now >= last then return false end
    throttled[key] = now
    return true
end

local function Now()
    return type(time) == "function" and time() or 0
end
F.Now = Now

---------------------------------------------------------------------------
-- Money text: gold / silver / copper coloured like the game's coins. Copper is dropped once there
-- is gold, to keep the columns narrow. A negative amount gets a red minus. Values are rounded to
-- the nearest copper (an expected profit is an average and is rarely a whole number).
---------------------------------------------------------------------------

local GOLD_C, SILVER_C, COPPER_C = "|cffffd700", "|cffc7c7cf", "|cffeda55f"
local PROFIT_C, LOSS_C, EVEN_C = "|cff59e659", "|cffff6666", "|cffb0b0b8"   -- the colours UI.lua uses for green, red, grey

function F.Money(copper)
    if not F.Number(copper) then return "?" end
    local negative = copper < 0
    local value = math.floor(math.abs(copper) + 0.5)
    local gold = math.floor(value / 10000)
    local silver = math.floor(value % 10000 / 100)
    local rest = value % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = GOLD_C .. gold .. "g|r" end
    if silver > 0 then parts[#parts + 1] = SILVER_C .. silver .. "s|r" end
    if rest > 0 and gold == 0 then parts[#parts + 1] = COPPER_C .. rest .. "c|r" end
    local text = #parts == 0 and (COPPER_C .. "0c|r") or table.concat(parts, "")   -- (no space between gold, silver and copper: 3s20c)
    if negative and value > 0 then text = "|cffff6060-|r" .. text end
    return text
end

-- A profit or loss: one colour for the whole text (the coin colours of F.Money would override a cell's
-- colour), a "+" or "-" in front, green above zero, red below, grey at zero (after rounding to a copper).
function F.ProfitText(copper)
    if not F.Number(copper) then return "?" end
    local value = math.floor(math.abs(copper) + 0.5)
    if value == 0 then return EVEN_C .. "0c|r" end
    local gold = math.floor(value / 10000)
    local silver = math.floor(value % 10000 / 100)
    local rest = value % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if rest > 0 and gold == 0 then parts[#parts + 1] = rest .. "c" end
    local text = table.concat(parts, "")
    if copper > 0 then return PROFIT_C .. "+" .. text .. "|r" end
    return LOSS_C .. "-" .. text .. "|r"
end

---------------------------------------------------------------------------
-- Character
---------------------------------------------------------------------------

-- The character's full name, saved without a realm. On Forever UnitName("player") returns only the
-- first word of a two-part name while GetUnitName("player", true) returns the whole name (FOR-0168);
-- everything runs on one realm, so a realm suffix is dropped, never keyed on.
function F.CharKey()
    if type(GetUnitName) ~= "function" then return nil end
    local name = GetUnitName("player", true)
    if not (F.String(name) and name ~= "") then return nil end
    return name:match("^[^-]+")
end

-- The professions the window has a tab for. `store` is the field of the character's entry that holds that profession's saved recipes;
-- `proc` is whether the profession has a chance of an extra result (only Cooking's Master Chef does). `line` is the skill line:
-- Cooking 185 is Wowhead Forever's (FOR-0177); Engineering 202 is the classic skill line and a HYPOTHESIS here until
-- the window reports it (FOR-0189): the open window is also recognised by its profession name.
F.TABS = { "cooking", "engineering", "tailoring" }          -- the professions with saved recipes (their luck, their stores)
F.LUCK_TABS = { "cooking", "engineering", "tailoring", "enchanting", "auction" }   -- the luck window's tabs: Enchanting counts disenchants (Luck.lua)
F.TAB_ORDER = { "cooking", "engineering", "tailoring", "enchanting" }   -- the main window's tabs: Enchanting is a buy list of auction-house gear (Disenchant.lua)
F.PROFESSIONS = {
    cooking = { key = "cooking", name = "Cooking", store = "recipes", proc = true, line = 185 },
    engineering = { key = "engineering", name = "Engineering", store = "engineering", proc = false, line = 202 },
    -- Tailoring works like Engineering: the learned recipes whose result a vendor buys, no rank and no extra
    -- result. 197 is the classic Tailoring skill line, the same family as Cooking 185 and Engineering 202: a HYPOTHESIS until the
    -- window reports it (FOR-0196); the open window is also recognised by its profession name.
    tailoring = { key = "tailoring", name = "Tailoring", store = "tailoring", proc = false, line = 197 },
    -- no recipes and no store: its rows are items from Auctionator's last scan. 333 is the classic Enchanting skill line,
    -- the same family as the verified Cooking 185 and Lockpicking 633 (FOR-0177, FOR-0151); not read on Forever yet.
    enchanting = { key = "enchanting", name = "Enchanting", proc = false, line = 333, disenchant = true },
}

-- The luck window's tab for what auctions really brought in. Not a profession: it has no
-- recipes, no skill line and no main-window tab, so it lives beside F.PROFESSIONS; F.TabDef finds either.
F.SALES_TAB = { key = "auction", name = "AH sales", proc = false, sales = true }
function F.TabDef(key)
    return F.PROFESSIONS[key] or (key == "auction" and F.SALES_TAB) or nil
end

-- The tab in use (saved), "cooking" when none or an unknown one is saved.
function F.Tab()
    local saved = F.db and F.db.tab
    return F.PROFESSIONS[saved] and saved or "cooking"
end

-- The rank of a skill line (C_SkillInfo.GetSkillLineInfoByID, official-declared: FOR-0151), 0 when the character has no
-- such skill, nil when it cannot be read at all (the API is missing or the call fails).
local function SkillRank(line)
    if not F.Has(C_SkillInfo, "GetSkillLineInfoByID") then return nil end
    local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, line)
    if not ok then return nil end
    if F.Table(info) and F.Integer(info.rank, 0, 100000) then return info.rank end
    if info == nil then return 0 end
    return nil
end
F.SkillRank = SkillRank

-- Whether this character has a profession.
-- Recipes saved from its window prove it; otherwise its skill line must have a rank. A profession whose skill cannot be
-- read is treated as learned: a tab is never hidden on a guess (the Engineering skill line 202 is still a HYPOTHESIS,
-- FOR-0189; opening the profession window once saves its recipes and shows the tab either way).
function F.ProfessionKnown(key)
    local def = F.PROFESSIONS[key]
    if not def then return false end
    local char = F.Char()
    local store = char and char[def.store]
    if type(store) == "table" and next(store) ~= nil then return true end
    local rank = SkillRank(def.line)
    if rank == nil then return true end
    return rank > 0
end

-- The tabs to show, in order: the learned professions plus any `also(key)` says to keep (the luck window keeps a
-- profession that has counts). Never empty: Cooking stands in when nothing else qualifies.
function F.VisibleTabs(also, order)
    local list = {}
    for _, key in ipairs(order or F.TAB_ORDER) do
        if F.ProfessionKnown(key) or (also and also(key)) then list[#list + 1] = key end
    end
    if #list == 0 then list[1] = "cooking" end
    return list
end

function F.IsVisibleTab(list, key)
    for _, shown in ipairs(list) do
        if shown == key then return true end
    end
    return false
end

-- This character's saved recipes of one profession (a table, or nil without a character).
function F.RecipesOf(char, prof)
    local def = F.PROFESSIONS[prof]
    return def and type(char) == "table" and char[def.store] or nil
end

-- The saved recipe a spell/recipe ID belongs to on this character, and its profession key; nil when none.
function F.FindRecipe(id)
    local char = F.Char()
    if not char then return nil end
    for _, key in ipairs(F.TABS) do
        local recipe = char[F.PROFESSIONS[key].store][id]
        if type(recipe) == "table" then return recipe, key end
    end
    return nil
end

-- This character's saved entry:
-- { recipes = { [recipeID] = recipe } (cooking), engineering = { [recipeID] = recipe }, rank = { value, seen },
--   cast = { [recipeID] = seconds measured }, castRod = { [recipeID] = seconds measured with the rod worn }, rodRatio = learned }.
function F.Char()
    local db = F.db
    if not db then return nil end
    local key = F.CharKey()
    if not key then return nil end
    local entry = db.chars[key]
    if type(entry) ~= "table" then entry = {}; db.chars[key] = entry end
    if type(entry.recipes) ~= "table" then entry.recipes = {} end
    for _, key in ipairs(F.TABS) do   -- one store per profession (cooking's is `recipes`)
        local store = F.PROFESSIONS[key].store
        if type(entry[store]) ~= "table" then entry[store] = {} end
    end
    if type(entry.cast) ~= "table" then entry.cast = {} end
    if type(entry.castRod) ~= "table" then entry.castRod = {} end   -- the same, measured with Cookie's Stirring Rod worn
    if type(entry.luck) ~= "table" then entry.luck = {} end
    return entry, key
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

local meta = {}

-- Name, quality, icon, vendor sell price and class of an item from the client's item cache, filled in
-- as it arrives (layout confirmed in FOR-0176). `sell` stays nil until the item is cached, so "not
-- loaded yet" is never mistaken for "cannot be sold" (sell == 0).
--
-- Before the client has the item (after every reload), the icon, quality and name come from a small saved cache
-- (`db.items[id] = { icon, quality, name }`, written whenever the item is read), and the icon and class also from
-- GetItemInfoInstant, which needs no item cache. `sell` is never taken from the saved cache, so "not loaded yet" stays
-- distinct from "cannot be sold".
function F.ItemMeta(id)
    local m = meta[id]
    if not m then
        m = { id = id }
        meta[id] = m
        local saved = F.db and type(F.db.items) == "table" and F.db.items[id]
        if type(saved) == "table" then
            if F.String(saved.name) and saved.name ~= "" then m.name = saved.name end
            if F.Integer(saved.quality, 0, 10) then m.quality = saved.quality end
            if saved.icon ~= nil and (type(saved.icon) == "number" or type(saved.icon) == "string") then m.icon = saved.icon end
        end
    end
    if m.sell ~= nil and m.class ~= nil and m.name and m.bindRead then return m end
    if not m.icon and F.Has(C_Item, "GetItemInfoInstant") then
        local _, _, _, _, icon, classID, subclassID = C_Item.GetItemInfoInstant(id)
        if F.Readable(icon) and (type(icon) == "number" or type(icon) == "string") then m.icon = icon end
        if m.class == nil and F.Integer(classID, 0, 100) then m.class = classID end
        if m.subclass == nil and F.Integer(subclassID, 0, 100) then m.subclass = subclassID end
    end
    if F.Has(C_Item, "GetItemInfo") then
        local name, _, quality, _, _, _, _, stack, _, icon, sell, classID, subclassID, bindType = C_Item.GetItemInfo(id)
        if F.String(name) and name ~= "" then m.name = name end
        if F.Integer(stack, 1, 100000) then m.stack = stack end   -- the 8th return: how many fit in one bag slot
        if F.Integer(quality, 0, 10) then m.quality = quality end
        if F.Readable(icon) and (type(icon) == "number" or type(icon) == "string") then m.icon = icon end
        if F.Integer(sell, 0, MAX_INT) then m.sell = sell end
        if F.Integer(classID, 0, 100) then m.class = classID end
        if F.Integer(subclassID, 0, 100) then m.subclass = subclassID end
        if F.String(name) and name ~= "" then m.bindRead = true end   -- (read once the item is there, so the early return above does not skip it)
        if F.Integer(bindType, 0, 10) then m.bind = bindType end   -- the 14th return: 0 none, 1 on pickup, 2 on equip, 3 on use (FOR-0204, a HYPOTHESIS on Forever)
        if m.sell ~= nil and F.db and type(F.db.items) == "table" and m.name and m.quality and m.icon then
            local saved = F.db.items[id]   -- the item is really loaded now: keep what the next session needs
            if type(saved) ~= "table" then saved = {}; F.db.items[id] = saved end
            saved.name, saved.quality, saved.icon = m.name, m.quality, m.icon
        end
    end
    if (m.sell == nil or not m.name) and not m.requested and F.Has(C_Item, "RequestLoadItemDataByID") then
        m.requested = true   -- ask once; GET_ITEM_INFO_RECEIVED refreshes the window
        C_Item.RequestLoadItemDataByID(id)
    end
    return m
end

function F.IsFood(m)
    return m ~= nil and m.class == F.FOOD_CLASS and m.subclass == F.FOOD_SUBCLASS
end

function F.Owned(id)
    local count
    if F.Has(C_Item, "GetItemCount") then count = C_Item.GetItemCount(id)
    elseif type(GetItemCount) == "function" then count = GetItemCount(id) end
    return F.Integer(count, 0, MAX_INT) and count or 0
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

function F.AuctionatorLoaded()
    local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
    return (api and api.GetAuctionPriceByItemID) and true or false
end

-- Auctionator's price from your last scan (FOR-0166). Optional dependency: a missing addon or a call
-- that errors just means "no AH price".
function F.AuctionPrice(id)
    if not F.AuctionatorLoaded() then return nil end
    local ok, price = pcall(_G.Auctionator.API.v1.GetAuctionPriceByItemID, F.CALLER, id)
    if ok and F.Integer(price, 1, MAX_INT) then return price end
    return nil
end

-- The auction house keeps 5% of a sale; the profit figures use the price after it.
F.AH_CUT = 0.05

-- What one item brings in when sold: the vendor price, or in "Sell at AH" mode the Auctionator price less the
-- auction house's cut. 0 means it cannot be sold that way (no vendor price / no Auctionator price); nil: the item is
-- not loaded yet (vendor mode only).
function F.SellPrice(id)
    if F.db and F.db.sellDE == true then
        return F.Disenchant.ValueOf(id)   -- the average of what it disenchants into (Disenchant.lua): nil while its data loads, 0 if it cannot be
    end
    if F.db and F.db.sellAH == true then
        local ah = F.AuctionPrice(id)
        return ah and math.floor(ah * (1 - F.AH_CUT)) or 0
    end
    return F.ItemMeta(id).sell
end

-- Days since the item was last seen in the auction house; nil when never seen or older than 21 days
-- (Auctionator\Source\API\v1\GetAuctionAge.lua).
function F.AuctionAge(id)
    local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
    if not (api and api.GetAuctionAgeByItemID) then return nil end
    local ok, age = pcall(api.GetAuctionAgeByItemID, F.CALLER, id)
    if ok and F.Number(age) and age >= 0 then return age end
    return nil
end

-- What it costs to get one of an item: the cheaper of the Auctionator price and the vendor buy price
-- saved when a merchant was visited. Returns cost, source ("ah" or "vendor"), ah, vendor.
function F.UnitCost(id)
    local ah = F.AuctionPrice(id)
    local saved = F.db and F.db.vendorBuy and F.db.vendorBuy[id]
    local vendor = (type(saved) == "table" and F.Number(saved.c) and saved.c > 0) and saved.c or nil
    if ah and vendor then
        if ah <= vendor then return ah, "ah", ah, vendor end
        return vendor, "vendor", ah, vendor
    end
    if ah then return ah, "ah", ah, nil end
    if vendor then return vendor, "vendor", nil, vendor end
    return nil, nil, nil, nil
end

---------------------------------------------------------------------------
-- Vendor buy prices, saved whenever a merchant window is open.
-- C_MerchantFrame.GetItemInfo rows: name, price, stackCount, numAvailable (-1 = unlimited),
-- hasExtendedCost (FOR-0176). `price` is for a whole stack of `stackCount` (as ProfPlanner reads it),
-- so the saved value is per unit. Token-priced rows are skipped. The price shown may include a
-- reputation discount, so the time it was seen is saved with it.
---------------------------------------------------------------------------

local function IsGear(id)
    if not F.Has(C_Item, "GetItemInfoInstant") then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
    return F.Integer(classID, 0, 100) and (classID == 2 or classID == 4)   -- weapons and armour are never reagents
end

-- Returns how many rows were saved, or nil when the merchant API is missing.
function F.ScanMerchant()
    local db = F.db
    if not db or type(GetMerchantNumItems) ~= "function" or type(GetMerchantItemID) ~= "function"
        or not F.Has(C_MerchantFrame, "GetItemInfo") then
        return nil
    end
    local count = GetMerchantNumItems()
    if not F.Integer(count, 0, 1000) then return nil end
    local saved, stamp = 0, Now()
    for index = 1, count do
        local id = GetMerchantItemID(index)
        local info = C_MerchantFrame.GetItemInfo(index)
        if F.Integer(id, 1, 2147483647) and F.Table(info) and F.Integer(info.price, 1, MAX_INT)
            and info.hasExtendedCost ~= true and not IsGear(id) then
            local stack = F.Integer(info.stackCount, 1, 100000) and info.stackCount or 1
            local entry = { c = info.price / stack, t = stamp }
            if F.Integer(info.numAvailable, 0, MAX_INT) then entry.l = true end   -- limited stock
            db.vendorBuy[id] = entry
            saved = saved + 1
        end
    end
    return saved
end

---------------------------------------------------------------------------
-- Learned recipes, saved per character whenever a profession window lists them (FOR-0175).
-- Only learned recipes whose output is cooked food are kept. Existing entries are only changed or
-- removed by what the window reports, so opening another profession never empties the list.
---------------------------------------------------------------------------

-- A recipe's reagents: every slot that is not marked optional, as { qty, ids = { itemID, ... } }.
-- A recipe with no readable reagent is not saved at all: a missing cost would read as free food.
local function ReadReagents(schematic)
    local slots = schematic.reagentSlotSchematics
    if not F.Table(slots) then return nil end
    local reagents = {}
    for _, slot in ipairs(slots) do
        if F.Table(slot) and slot.required ~= false then
            local qty = slot.quantityRequired
            local options = slot.reagents
            if F.Integer(qty, 1, 100000) and F.Table(options) then
                local ids = {}
                for _, option in ipairs(options) do
                    if F.Table(option) and F.Integer(option.itemID, 1, 2147483647) then ids[#ids + 1] = option.itemID end
                end
                if #ids > 0 then reagents[#reagents + 1] = { qty = qty, ids = ids } end
            end
        end
    end
    if #reagents == 0 then return nil end
    return reagents
end

-- Which profession (other than Cooking) a profession window (C_TradeSkillUI.GetBaseProfessionInfo) is: by its skill line or its
-- parent's, else by its name (FOR-0189, FOR-0196); nil for any other window. The answer is only used to decide which saved list
-- a window feeds.
local function WindowProfession(info)
    if not F.Table(info) then return nil end
    local name = F.String(info.professionName) and info.professionName:lower() or ""
    for _, key in ipairs(F.TABS) do
        local def = F.PROFESSIONS[key]
        if key ~= "cooking" then
            if info.professionID == def.line or info.parentProfessionID == def.line then return key end
            if name:find(def.name:lower(), 1, true) ~= nil then return key end
        end
    end
    return nil
end

F.WindowProfession = WindowProfession   -- (Craft.lua: which saved profession the open window is)

-- Returns { seen = recipes listed, saved = kept, removed = dropped, pending = outputs not cached yet, prof = the
-- profession the window was taken for }, or nil and a reason ("api", "character"). An Engineering window feeds
-- the engineering list (any learned recipe whose output a vendor buys); every other window feeds the cooking
-- list exactly as before (food only).
function F.CacheRecipes()
    local api = _G.C_TradeSkillUI
    if not (F.Has(api, "GetAllRecipeIDs") and F.Has(api, "GetRecipeInfo") and F.Has(api, "GetRecipeSchematic")) then
        return nil, "api"
    end
    local char = F.Char()
    if not char then return nil, "character" end
    local ids = api.GetAllRecipeIDs()
    if not F.Table(ids) then return nil, "api" end
    local window = F.Has(api, "GetBaseProfessionInfo") and api.GetBaseProfessionInfo() or nil
    local profession = WindowProfession(window)   -- nil: the Cooking window, or any other (food only)
    local store = profession and char[F.PROFESSIONS[profession].store] or char.recipes
    F.lastWindow = F.Table(window) and { id = window.professionID, parent = window.parentProfessionID,
        name = window.professionName, engineering = profession == "engineering", prof = profession or "cooking" } or nil
    local result = { seen = 0, saved = 0, removed = 0, pending = 0, prof = profession or "cooking" }
    for _, id in ipairs(ids) do
        if F.Integer(id, 1, 2147483647) then
            result.seen = result.seen + 1
            local info = api.GetRecipeInfo(id)
            if F.Table(info) then
                if info.learned == true then
                    local schematic = api.GetRecipeSchematic(id, false)
                    local output = F.Table(schematic) and schematic.outputItemID or nil
                    if F.Integer(output, 1, 2147483647) then
                        local item = F.ItemMeta(output)
                        if item.class == nil then
                            result.pending = result.pending + 1
                        elseif profession then
                            -- Kept even when no vendor buys the result: it may be a material of another recipe the player can
                            -- make (blasting powder, a bolt of cloth); F.BuildRows leaves such a recipe out of the list.
                            local reagents = ReadReagents(schematic)
                            if reagents then
                                local qMin = F.Integer(schematic.quantityMin, 1, 100000) and schematic.quantityMin or 1
                                local qMax = F.Integer(schematic.quantityMax, qMin, 100000) and schematic.quantityMax or qMin
                                store[id] = { name = F.String(info.name) and info.name or item.name,
                                    out = output, qMin = qMin, qMax = qMax, r = reagents }
                                result.saved = result.saved + 1
                            elseif store[id] then
                                store[id] = nil
                                result.removed = result.removed + 1
                            end
                        elseif F.IsFood(item) then
                            local reagents = ReadReagents(schematic)
                            local qMin = F.Integer(schematic.quantityMin, 1, 100000) and schematic.quantityMin or 1
                            local qMax = F.Integer(schematic.quantityMax, qMin, 100000) and schematic.quantityMax or qMin
                            if reagents then
                                char.recipes[id] = { name = F.String(info.name) and info.name or item.name,
                                    out = output, qMin = qMin, qMax = qMax, r = reagents }
                                result.saved = result.saved + 1
                            end
                        end
                    end
                elseif info.learned == false and store[id] then
                    store[id] = nil
                    result.removed = result.removed + 1
                end
            end
        end
    end
    -- A window that listed cooked food is the Cooking window: remember its skill line so a click on a
    -- recipe can open it again (Pick.lua).
    if result.saved > 0 and F.Table(window) and F.Integer(window.professionID, 1, 2147483647) then
        if profession then F.db[profession .. "Line"] = window.professionID else F.db.cookingLine = window.professionID end
    end
    return result
end

---------------------------------------------------------------------------
-- Master Chef rank
---------------------------------------------------------------------------

-- Reads the rank from the traits system. FOR-0174: C_Traits.GetConfigIDByTreeID(1187) and
-- C_Traits.GetNodeInfo(config, 110289) gave currentRank 3 / maxRanks 5 with the legacy window never
-- opened. The node is only trusted when it reports five ranks, the shape that was observed.
-- Returns the rank, or nil and a reason.
function F.ReadRank()
    local traits = _G.C_Traits
    if not (F.Has(traits, "GetConfigIDByTreeID") and F.Has(traits, "GetNodeInfo")) then return nil, "api" end
    local config = traits.GetConfigIDByTreeID(F.RANK_TREE)
    if not F.Integer(config, 1, MAX_INT) then return nil, "config" end
    local node = traits.GetNodeInfo(config, F.RANK_NODE)
    if not F.Table(node) then return nil, "node" end
    if F.Integer(node.currentRank, 0, F.RANK_MAX) and node.maxRanks == F.RANK_MAX then
        return node.currentRank
    end
    return nil, "shape"
end

-- The rank the numbers use, and where it came from: "manual" (override), "game" (read now), "saved"
-- (the last good read for this character) or "unknown" (nothing readable: rank 0 is used).
function F.CurrentRank()
    local db = F.db
    if db and F.Integer(db.rankOverride, 0, F.RANK_MAX) then return db.rankOverride, "manual" end
    local live = F.ReadRank()
    local char = F.Char()
    if live then
        if char then char.rank = { value = live, seen = Now() } end
        return live, "game"
    end
    if char and type(char.rank) == "table" and F.Integer(char.rank.value, 0, F.RANK_MAX) then
        return char.rank.value, "saved", char.rank.seen
    end
    return 0, "unknown"
end

---------------------------------------------------------------------------
-- Time per craft, for the profit-per-hour column. In order of trust:
--   measured: the time between UNIT_SPELLCAST_START and _SUCCEEDED of the recipe's own cast, saved per
--             character the first time the recipe is cooked (a recipe's ID is its spell ID: the Basic
--             Campfire recipe 1229737 is Wowhead Forever's spell 1229737, FOR-0177);
--   game:     C_Spell.GetSpellInfo(recipeID).castTime in milliseconds, when the client returns one
--             (unverified on Forever until FOR-0177's probe is answered);
--   default:  3 seconds. Every one of 53 cooking recipe spells read on Wowhead Forever is a "3 sec
--             cast" (the Basic Campfire, not food, is 10 sec): COMMUNITY-REPORTED, FOR-0177.
---------------------------------------------------------------------------

F.DEFAULT_CAST = 3
local MIN_CAST, MAX_CAST = 0.3, 60   -- a measured time outside this is a glitch (interrupted, lagged), not a cast

-- Cookie's Stirring Rod:
-- a cast measured with it worn is kept apart (char.castRod), so wearing or removing it never makes a saved time wrong. A recipe measured
-- only without (or only with) the rod is scaled by the ratio between the two: learned from a recipe measured both ways (char.rodRatio),
-- until then 1/1.25 = 0.8. HYPOTHESIS (FOR-0199): "25% faster" is read as casting 1.25 times as fast.
F.ROD_ITEM = 5198
F.ROD_RATIO = 0.8
local rodWorn   -- cached; PLAYER_EQUIPMENT_CHANGED clears it (F.RodChanged)

function F.RodChanged() rodWorn = nil end
function F.RodCached() return rodWorn end   -- what was last read (nil: not read since the last equipment change)

function F.RodWorn()
    if rodWorn ~= nil then return rodWorn end
    if type(GetInventoryItemID) ~= "function" then return false end   -- (not cached: the game may not be ready)
    local found = false
    for slot = 1, 19 do
        if GetInventoryItemID("player", slot) == F.ROD_ITEM then found = true; break end
    end
    rodWorn = found
    return found
end

function F.RodRatio()
    local char = F.Char()
    local learned = char and char.rodRatio
    if F.Number(learned) and learned >= 0.4 and learned <= 0.95 then return learned end
    return F.ROD_RATIO
end

function F.RecordCast(id, seconds)
    local char = F.Char()
    if not (char and F.Integer(id, 1, 2147483647) and F.Number(seconds)) then return false end
    if seconds < MIN_CAST or seconds > MAX_CAST then return false end
    local store = F.RodWorn() and char.castRod or char.cast
    store[id] = seconds
    -- a recipe timed both ways teaches the ratio (used for the recipes timed only one way)
    local plain, fast = char.cast[id], char.castRod[id]
    if F.Number(plain) and F.Number(fast) and plain > 0 then
        local ratio = fast / plain
        if ratio >= 0.4 and ratio <= 0.95 then char.rodRatio = ratio end
    end
    return true
end

-- Returns seconds, source ("measured", "game" or "default").
local function Valid(seconds) return F.Number(seconds) and seconds >= MIN_CAST and seconds <= MAX_CAST end

function F.CraftSeconds(id)
    local char = F.Char()
    local rod = F.RodWorn()
    local measured = char and (rod and char.castRod or char.cast)[id]
    if Valid(measured) then return measured, "measured" end
    -- timed only the other way: scaled by the rod's ratio ("scaled")
    local other = char and (rod and char.cast or char.castRod)[id]
    if Valid(other) then return rod and other * F.RodRatio() or other / F.RodRatio(), "scaled" end
    if F.Has(_G.C_Spell, "GetSpellInfo") then
        local info = _G.C_Spell.GetSpellInfo(id)
        local ms = F.Table(info) and info.castTime or nil
        if F.Number(ms) and ms > 0 and ms / 1000 <= MAX_CAST then return ms / 1000, "game" end
    end
    return F.DEFAULT_CAST, "default"
end

---------------------------------------------------------------------------
-- How long a batch of crafts takes. The profession window's Create All / Create N calls
-- C_TradeSkillUI.CraftRecipe(recipeID, numCasts, ...) (a HYPOTHESIS on Forever until seen: FOR-0195), which is watched with a
-- post-hook; the time is the number of casts x the recipe's cast time (F.CraftSeconds: measured, else the game's, else 3 s).
---------------------------------------------------------------------------

-- 900 -> "15m", 3920 -> "1h 5m 20s", 45 -> "45s": the parts that are zero are left out.
function F.DurationText(seconds)
    if not F.Number(seconds) or seconds < 0 then return "?" end
    seconds = math.floor(seconds + 0.5)
    local hours, minutes, rest = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
    local parts = {}
    if hours > 0 then parts[#parts + 1] = hours .. "h" end
    if minutes > 0 then parts[#parts + 1] = minutes .. "m" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "s" end
    return table.concat(parts, " ")
end

F.crafts = { seen = 0 }   -- for /dpp status

-- C_TradeSkillUI.CraftRecipe(recipeID, numCasts): prints the total time when more than one cast was asked for. "~" when the cast
-- time is only the 3 s assumed for a recipe nothing is known about.
function F.OnCraft(recipeID, numCasts)
    if not (F.Integer(recipeID, 1, 2147483647) and F.Integer(numCasts, 1, 1000000)) then return end
    F.crafts.seen = F.crafts.seen + 1
    F.crafts.last = { id = recipeID, casts = numCasts }
    if numCasts < 2 or not F.db or F.db.craftTime == false then return end
    if F.skipTimeLine == recipeID then return end   -- the "+" button's own chat line has the time (Craft.lua)
    local each, source = F.CraftSeconds(recipeID)
    -- one line per recipe per 10 s, however often Create All is pressed
    if not F.Throttle("time" .. recipeID, 10) then return end
    F.Print("Craft time: " .. ((source == "default" or source == "scaled") and "~" or "") .. F.DurationText(numCasts * each))
end

local craftsHooked = false
function F.HookCrafts()
    if craftsHooked then return true end
    local api = _G.C_TradeSkillUI
    if not (F.Has(api, "CraftRecipe") and type(hooksecurefunc) == "function") then return false end
    hooksecurefunc(api, "CraftRecipe", function(recipeID, numCasts) F.OnCraft(recipeID, numCasts) end)
    craftsHooked = true
    F.crafts.hooked = true
    return true
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Materials the player can make themselves. A material that one of this character's saved recipes (either profession) makes is
-- costed at the cheaper of buying it (Auctionator or a vendor, F.UnitCost) and making it from its own materials,
-- worked out the same way down the chain; one nobody here can make (a bar: no smelting) is buy-only. A recipe whose
-- cheapest route makes something is FLATTENED before it is evaluated: that material's line is replaced by the
-- materials of the recipe that makes it, so every later step (profit, price limits, the [A] list, the vendor +
-- button) sees only what must really be bought. Making it is only chosen when strictly cheaper than buying.
---------------------------------------------------------------------------

local CRAFT_DEPTH = 4   -- how many recipes deep a chain is followed (stone -> powder -> dynamite is two)

-- The per-refresh state: which saved recipe makes each item, and memos of prices and routes.
function F.CraftContext()
    local ctx = { producers = {}, market = {}, routes = {} }
    local char = F.Char()
    if not char then return ctx end
    for _, key in ipairs(F.TABS) do
        for id, recipe in pairs(char[F.PROFESSIONS[key].store]) do
            if type(recipe) == "table" and F.Integer(recipe.out, 1, 2147483647) and type(recipe.r) == "table" and #recipe.r > 0 then
                local qMin = tonumber(recipe.qMin) or 1
                local qMax = tonumber(recipe.qMax) or qMin
                local yield = (qMin + qMax) / 2
                local held = ctx.producers[recipe.out]
                if yield >= 1 and (not held or id < held.id) then
                    ctx.producers[recipe.out] = { id = id, recipe = recipe, yield = yield }
                end
            end
        end
    end
    return ctx
end

-- { cost = copper per unit by the cheapest route, market = the price to buy it (or nil), craft = the producer used when
-- making it is cheaper }; cost is nil when it cannot be priced. `path` holds the items being worked out (a cycle guard).
local function Route(ctx, id, depth, path)
    local known = ctx.routes[id]
    if known then return known end
    local market = ctx.market[id]
    if market == nil then
        market = F.UnitCost(id) or false
        ctx.market[id] = market
    end
    market = market or nil
    local result = { cost = market, market = market }
    local producer = ctx.producers[id]
    if producer and depth < CRAFT_DEPTH and not path[id] then
        path[id] = true
        local total, priced = 0, true
        for _, reagent in ipairs(producer.recipe.r) do
            local cheapest
            for _, option in ipairs(type(reagent.ids) == "table" and reagent.ids or {}) do
                local sub = Route(ctx, option, depth + 1, path)
                if sub.cost and (not cheapest or sub.cost < cheapest) then cheapest = sub.cost end
            end
            if not cheapest then priced = false; break end
            total = total + cheapest * (tonumber(reagent.qty) or 1)
        end
        path[id] = nil
        if priced then
            local each = total / producer.yield
            if not market or each < market then result.cost, result.craft = each, producer end
        end
    end
    if not producer or next(path) == nil then ctx.routes[id] = result end   -- (a result worked out inside a cycle guard is not kept)
    return result
end

-- Returns the recipe's materials with every craft-it-cheaper material replaced by its own materials, { reagent ... }
-- with fractional quantities where a recipe makes several; via = { { id, units, crafts, per, market, recipeID } ... }
-- for the items made by the player (empty when nothing is); and the extra casting time in seconds those crafts take.
function F.Flatten(recipe, ctx)
    local lines, order, via, viaOrder, seconds = {}, {}, {}, {}, 0
    local db = F.db
    local function addRaw(ids, qty)
        local key = table.concat(ids, ",")
        local line = lines[key]
        if line then line.qty = line.qty + qty
        else
            line = { qty = qty, ids = ids }
            lines[key] = line
            order[#order + 1] = line
        end
    end
    local function expand(reagent, qty, depth, path)
        local ids = type(reagent.ids) == "table" and reagent.ids or {}
        local bestID, best
        for _, id in ipairs(ids) do
            local route = Route(ctx, id, depth, path)
            if route.cost and (not best or route.cost < best.cost) then bestID, best = id, route end
        end
        local held = bestID and db and db.ownedFree == true and F.Owned(bestID) >= qty
        if best and best.craft and not held and not path[bestID] then
            local producer = best.craft
            local crafts = qty / producer.yield
            local entry = via[bestID]
            if not entry then
                entry = { id = bestID, units = 0, crafts = 0, per = best.cost, market = best.market, recipeID = producer.id }
                via[bestID] = entry
                viaOrder[#viaOrder + 1] = entry
            end
            entry.units, entry.crafts = entry.units + qty, entry.crafts + crafts
            seconds = seconds + crafts * (F.CraftSeconds(producer.id))
            path[bestID] = true
            for _, sub in ipairs(producer.recipe.r) do
                expand(sub, crafts * (tonumber(sub.qty) or 1), depth + 1, path)
            end
            path[bestID] = nil
        else
            addRaw(ids, qty)
        end
    end
    for _, reagent in ipairs(recipe.r or {}) do expand(reagent, tonumber(reagent.qty) or 1, 0, {}) end
    return order, viaOrder, seconds
end

-- A quantity for display: 2, or 1.5 when a recipe's yield made it fractional.
function F.QtyText(qty)
    if not F.Number(qty) then return "?" end
    if math.abs(qty - math.floor(qty + 0.5)) < 1e-9 then return string.format("%d", math.floor(qty + 0.5)) end
    return (string.format("%.2f", qty):gsub("0+$", ""):gsub("%.$", ""))
end

-- One row per saved recipe of a profession (default: the tab in use) for the current character, each with its
-- Calc.Evaluate result at the current rank (a profession without an extra-result chance is always rank 0, source
-- "none"). Returns rows, info where info = { prof, proc, rank, source, seen, count, missing (rows with an
-- unknown material price), oldest (oldest Auctionator price age in days that a row used) }.
function F.BuildRows(prof)
    local db = F.db
    local rows = {}
    prof = F.PROFESSIONS[prof] and prof or F.Tab()
    if F.PROFESSIONS[prof].disenchant then return F.Disenchant.Rows() end
    local proc = F.PROFESSIONS[prof].proc
    local rank, source, seen = 0, "none", nil
    if proc then rank, source, seen = F.CurrentRank() end
    local info = { prof = prof, proc = proc, rank = rank, source = source, seen = seen, count = 0, missing = 0, loading = 0 }
    local char = F.Char()
    if not (db and char) then return rows, info end
    local recipes = F.RecipesOf(char, prof)

    local costMemo, ownedMemo = {}, {}
    local env = {
        unitCost = function(id)
            local memo = costMemo[id]
            if memo == nil then
                local cost, from = F.UnitCost(id)
                memo = { cost, from }
                costMemo[id] = memo
            end
            return memo[1]
        end,
        owned = function(id)
            local count = ownedMemo[id]
            if count == nil then count = F.Owned(id); ownedMemo[id] = count end
            return count
        end,
        sell = F.SellPrice,
    }
    local opts = { ownedFree = db.ownedFree == true }
    local craftCtx = F.CraftContext()

    local oldest
    -- One row for a recipe: a learned one (the character's saved recipes), or with `unknown` one of the profession's catalog
    -- (Catalog.lua) that the character has not learned, listed when "Known recipes" is unticked.
    local function Add(id, recipe, unknown)
        if type(recipe) == "table" and F.Integer(recipe.out, 1, 2147483647) and type(recipe.r) == "table"
            and (proc or F.ItemMeta(recipe.out).sell ~= 0 or (db.sellAH == true and F.AuctionPrice(recipe.out))
                or (db.sellDE == true and (F.Disenchant.ValueOf(recipe.out) or 1) > 0)) then   -- (a result nobody buys is only ever a material)
            local item = F.ItemMeta(recipe.out)
            if unknown and not F.IsFood(item) then return end   -- (a learned recipe is only kept for food; the catalog's wait for the item data)
            local seconds, secondsFrom = F.CraftSeconds(id)
            -- Materials the player makes cheaper than they can buy them: costed by their own materials, and their
            -- casting time added to this recipe's.
            local flat, via, extra = F.Flatten(recipe, craftCtx)
            local evRecipe = recipe
            if #via > 0 then
                evRecipe = { out = recipe.out, qMin = recipe.qMin, qMax = recipe.qMax, r = flat }
                seconds = seconds + extra
            end
            env.seconds = function() return seconds end
            local ev = F.Calc.Evaluate(evRecipe, rank, env, opts)
            ev.secondsFrom = secondsFrom
            info.count = info.count + 1
            if secondsFrom == "default" then info.assumedTime = (info.assumedTime or 0) + 1 end
            if ev.status == "noprice" then info.missing = info.missing + 1 end
            if ev.status == "loading" then info.loading = info.loading + 1 end
            for _, line in ipairs(ev.reagents) do
                if line.unit and not line.free and line.id then
                    env.unitCost(line.id)   -- (memoised: this only makes sure the source is noted)
                    local memo = costMemo[line.id]
                    if memo and memo[2] == "ah" then
                        local age = F.AuctionAge(line.id)
                        if age and (not oldest or age > oldest) then oldest = age end
                    end
                end
            end
            -- the optional AH comparison: what the finished food would fetch on the auction house
            local ah = F.AuctionPrice(recipe.out)
            local vendor = item.sell   -- vendorValue is the other side of the comparison column in "Sell at AH" mode
            rows[#rows + 1] = { id = id, recipe = recipe, ev = ev, item = item, via = via, unknown = unknown or nil,
                ahValue = ah and ah * ev.yield or nil,
                vendorValue = (vendor and vendor > 0) and vendor * ev.yield or nil,
                name = recipe.name or item.name or ("Recipe " .. id) }
        end
    end
    for id, recipe in pairs(recipes) do Add(id, recipe, false) end
    if db.showUnlearned == true and F.CATALOG and F.CATALOG[prof] then
        for id, recipe in pairs(F.CATALOG[prof]) do
            if not recipes[id] then Add(id, recipe, true) end
        end
    end
    info.oldest = oldest
    return rows, info
end
