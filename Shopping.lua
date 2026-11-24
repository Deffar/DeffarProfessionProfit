-- Forever Profession Profit: the [A] button on a row makes an Auctionator shopping list of the recipe's
-- materials. Auctionator calls: CreateShoppingList(caller, name,
-- searchStrings), which replaces a list of the same name and, at the auction house, starts searching, and
-- ConvertToSearchString(caller, { searchString, isExact, quantity, maxPrice }) (Auctionator\Source\API\v1\
-- ShoppingLists.lua, FOR-0178; maxPrice is in copper, the string holds gold: Search\Advanced.lua).
--
-- Each auction material gets a maximum price and a quantity:
--   * the highest price per unit that still gives at least the chosen odds (/fpp odds, default 90%) of
--     finishing at or above break-even over the crafts being bought (/fpp buy N, default: as many as the
--     budget allows, see F.ShoppingSettings), every
--     auction material allowed the same multiple of today's price so buying them all at their caps together
--     still meets the odds;
--   * and no higher than the price that still leaves the minimum margin on cost (/fpp margin, default 10%);
--   * the number of crafts is cut until buying that many materials at their caps fits the budget (the
--     Budget box, or all the character's gold when it is empty);
--   * quantity per material = quantity one craft needs x those crafts minus what the character holds.
-- A material that is cheaper at a vendor (or only has a saved vendor price) is left out and named, since
-- there is nothing to find on the auction house. A recipe with no complete profit (a material without a
-- price) gets quantities only, no maximum price. Whether Auctionator filters by price per unit and what its
-- quantity field does in a list are unverified (FOR-0181).
local _, F = ...

local function AuctionatorAPI()
    local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
    if type(api) == "table" and type(api.CreateShoppingList) == "function" then return api end
    return nil
end

F.ShoppingAPI = AuctionatorAPI   -- (the Enchanting tab's search, Disenchant.lua)

function F.ShoppingAvailable()
    return AuctionatorAPI() ~= nil
end

-- One search term: exact item name, how many and (when given) the most to pay per unit, in copper. Older
-- Auctionator versions differ in what ConvertToSearchString takes, so a plain quoted name is the fallback.
local function SearchString(api, name, quantity, maxPrice)
    if type(api.ConvertToSearchString) == "function" then
        local ok, text = pcall(api.ConvertToSearchString, F.CALLER,
            { searchString = name, isExact = true, quantity = quantity, maxPrice = maxPrice })
        if ok and F.String(text) and text ~= "" then return text end
    end
    return '"' .. name .. '"'
end

F.SearchString = SearchString

-- Deletes the lists this addon made earlier (every list named "Profession Profit - ...") except `keep`, so each [A] press leaves one list
-- instead of one per recipe or item (FOR-0187). Auctionator's list manager is an internal, not its API (FOR-0187): every piece is checked, and a
-- failure leaves the old lists as they were. Returns how many were deleted.
F.LIST_PREFIX = "Profession Profit - "
function F.ClearOldLists(keep)
    local auctionator = _G.Auctionator
    local manager = type(auctionator) == "table" and type(auctionator.Shopping) == "table" and auctionator.Shopping.ListManager or nil
    if not (type(manager) == "table" and F.Has(manager, "GetCount") and F.Has(manager, "GetByIndex") and F.Has(manager, "Delete")) then return 0 end
    local names = {}
    for index = 1, manager:GetCount() do
        local ok, list = pcall(manager.GetByIndex, manager, index)
        local name = ok and type(list) == "table" and F.Has(list, "GetName") and list:GetName() or nil
        if F.String(name) and name ~= keep and name:sub(1, #F.LIST_PREFIX) == F.LIST_PREFIX then names[#names + 1] = name end
    end
    local deleted = 0
    for _, name in ipairs(names) do
        if pcall(manager.Delete, manager, name) then deleted = deleted + 1 end
    end
    return deleted
end

-- The numbers behind the button, also shown in its tooltip: crafts wanted, odds (percent), the budget in
-- copper (nil when the purse cannot be read and none is set) and the character's gold.
function F.ShoppingSettings()
    local db = F.db
    local crafts = F.Integer(db.crafts, 1, 100000) and db.crafts or 100   -- the tooltip's range; also the fallback below
    local odds = F.Integer(db.odds, 50, 99) and db.odds or 90
    local margin = F.Integer(db.margin, 0, 100) and db.margin or 10   -- percent of cost
    local gold = F.Bought and F.Bought.Money() or nil
    local budget = gold                                    -- empty box: all the gold
    if F.Integer(db.budget, 1, 100000000) then
        budget = db.budget * 10000
        if gold and gold < budget then budget = gold end   -- never more than is held
    end
    -- How many crafts the list is for: the /fpp buy number when set; otherwise as many as the budget allows
    -- (the plan cuts this down to what the budget buys within the price limits); when neither a budget nor
    -- the purse can be read, the tooltip's crafts setting, so an unreadable purse never asks for 100000.
    local fill = false
    if F.Integer(db.buyCrafts, 1, 100000) then
        crafts = db.buyCrafts
    elseif budget then
        crafts, fill = 100000, true
    end
    return crafts, odds, budget, gold, margin, fill
end

-- What buying for `row` (a row from F.BuildRows) would look like: { crafts, odds, budget, plan, why, extra }.
-- `plan` is Calc.PlanBuy's answer; `why` is its reason when there is none ("notok" = the recipe has no
-- complete profit, so no price limit can be worked out).
function F.PlanShopping(row)
    local crafts, odds, budget, _, margin, fill = F.ShoppingSettings()
    local result = { crafts = crafts, odds = odds, budget = budget, margin = margin, fill = fill }
    result.opts = {
        odds = odds / 100, crafts = crafts, budget = budget, margin = margin / 100, owned = F.Owned,
        buy = function(line)
            local _, source = F.UnitCost(line.id)
            return source == "ah"
        end,
    }
    result.plan, result.why, result.extra = F.Calc.PlanBuy(row.ev, result.opts)
    return result
end

---------------------------------------------------------------------------
-- Opening and searching the new list. The buying stays with the player: the game requires a real click to spend gold
-- at the auction house, and this addon never confirms a purchase. What it does after creating a list, at the
-- auction house and when /fpp autosearch is on:
--   1. shows Auctionator's Shopping tab BEFORE creating the list: Auctionator's Shopping frame only listens for a
--      new list (ListImportFinished, which then selects and expands it) while it is showing
--      (Source\Tabs\Shopping\Mixins\Main.lua:255-257, 290-292). The tab's id is "AuctionatorTabs_Shopping"
--      (Source_ModernAH\Tabs\Main.lua:19-26, TabContainer.lua:30) and LibAHTab:SetSelected switches to it
--      (Libs_ModernAH\LibAHTab\LibAHTab.lua:83-106), exactly as clicking the tab does;
--   2. after the list exists, asks Auctionator to search it with the event its own Search button fires
--      (Tab.Events.ListSearchRequested, Main.lua:259-265: it expands the list and searches it unless Auctionator's
--      own "automatically scan for shopping list items" option already did, so there is one search).
-- These are Auctionator internals, not its public API: each piece is checked and a missing one is skipped
-- silently (the list is still created). FOR-0187.
---------------------------------------------------------------------------

local SHOPPING_TAB = "AuctionatorTabs_Shopping"
local busSource = {}

-- Shows the Shopping tab when the auction house is open and another tab is showing. True when it is showing after.
function F.ShowShoppingTab()
    local window = _G.AuctionHouseFrame
    if type(window) ~= "table" or not F.Has(window, "IsShown") or not window:IsShown() then return false end
    local shopping = _G.AuctionatorShoppingFrame
    if type(shopping) == "table" and F.Has(shopping, "IsShown") and shopping:IsShown() then return true end
    -- LibStub is a TABLE (callable through its metatable) in the game, not a function: ask it with :GetLibrary.
    local stub = _G.LibStub
    local lib = (type(stub) == "table" or type(stub) == "function") and F.Has(stub, "GetLibrary") and stub:GetLibrary("LibAHTab-1-0", true) or nil
    if F.Has(lib, "DoesIDExist") and F.Has(lib, "SetSelected") and lib:DoesIDExist(SHOPPING_TAB) then
        lib:SetSelected(SHOPPING_TAB)
        return true
    end
    -- Otherwise click the tab's own button, which runs the same SetSelected (TabContainer.lua:30-32 makes it a global).
    local button = _G[SHOPPING_TAB]
    if type(button) == "table" and F.Has(button, "Click") then
        button:Click()
        return type(shopping) == "table" and F.Has(shopping, "IsShown") and shopping:IsShown() or true
    end
    return false
end

-- Asks Auctionator to search the list called `name`. True when the request was sent.
function F.SearchShoppingList(name)
    local window = _G.AuctionHouseFrame
    if type(window) ~= "table" or not F.Has(window, "IsShown") or not window:IsShown() then return false end   -- nothing to search away from the auction house
    local auctionator = _G.Auctionator
    local shopping = type(auctionator) == "table" and auctionator.Shopping or nil
    local events = type(shopping) == "table" and shopping.Tab and shopping.Tab.Events or nil
    local manager = type(shopping) == "table" and shopping.ListManager or nil
    local bus = type(auctionator) == "table" and auctionator.EventBus or nil
    if not (type(events) == "table" and events.ListSearchRequested and F.Has(manager, "GetByName")
        and F.Has(bus, "RegisterSource") and F.Has(bus, "Fire") and F.Has(bus, "UnregisterSource")) then return false end
    local list = manager:GetByName(name)
    if not list then return false end
    bus:RegisterSource(busSource, "ForeverProfessionProfit")
    bus:Fire(busSource, events.ListSearchRequested, list)
    bus:UnregisterSource(busSource)
    return true
end

---------------------------------------------------------------------------
-- How deep the price limit goes. Auctionator's price limit
-- only keeps the item in the results while its CHEAPEST unit is at or under it (Source_ModernAH\Search\
-- Filters\Price.lua checks browseResult.minPrice), and its quantity is just the amount preselected in the
-- buy dialog (purchaseQuantity); the units bought climb the price ladder past the limit. So when the game
-- reports the item's listings, this counts the units at or under the limit and says how many to buy.
-- C_AuctionHouse.GetNumCommoditySearchResults / GetCommoditySearchResultInfo are retail names, unverified
-- on Forever (FOR-0182); COMMODITY_SEARCH_RESULTS_UPDATED with the item ID as its first argument was seen.
---------------------------------------------------------------------------

F.activeCaps = {}   -- [itemID] = { cap = copper per unit, need = units asked for, name } from the last [A] press

-- The units listed at or under `cap` (copper per unit) for a commodity whose listings the game has loaded:
-- { units, cost, cheapest, nextPrice, levels }, or nil and why.
function F.CommodityDepth(itemID, cap)
    local api = _G.C_AuctionHouse
    if not (F.Has(api, "GetNumCommoditySearchResults") and F.Has(api, "GetCommoditySearchResultInfo")) then return nil, "api" end
    local count = api.GetNumCommoditySearchResults(itemID)
    if not F.Integer(count, 0, 100000) then return nil, "count" end
    local ladder = {}
    for index = 1, count do
        local info = api.GetCommoditySearchResultInfo(itemID, index)
        if F.Table(info) and F.Integer(info.quantity, 1, 2147483647) and F.Number(info.unitPrice) and info.unitPrice >= 0 then
            ladder[#ladder + 1] = { quantity = info.quantity, price = info.unitPrice }
        end
    end
    table.sort(ladder, function(a, b) return a.price < b.price end)
    local depth = { units = 0, cost = 0, levels = #ladder, cheapest = ladder[1] and ladder[1].price or nil }
    for _, step in ipairs(ladder) do
        if step.price <= cap then
            depth.units = depth.units + step.quantity
            depth.cost = depth.cost + step.quantity * step.price
        elseif not depth.nextPrice then
            depth.nextPrice = step.price
        end
    end
    return depth
end

-- Auctionator's commodity buy window (Source_ModernAH\Tabs\Buying\Commodity\Mixins\Main.lua: the global
-- frame AuctionatorBuyCommodityFrame, its numeric quantity box DetailsContainer.Quantity whose OnTextChanged
-- sets the quantity to buy). Returns the box when the window is open on this item, else nil.
local function BuyQuantityBox(itemID)
    local window = _G.AuctionatorBuyCommodityFrame
    if type(window) ~= "table" or window.expectedItemID ~= itemID or not F.Has(window, "IsShown") or not window:IsShown() then return nil end
    local details = window.DetailsContainer
    local box = type(details) == "table" and details.Quantity or nil
    if F.Has(box, "GetText") and F.Has(box, "SetNumber") then return box end
    return nil
end

-- COMMODITY_SEARCH_RESULTS_UPDATED(itemID): says in chat how many units are at or under the limit of an item
-- the last [A] list asked for, and lowers Auctionator's quantity box to that many (never raises it, and
-- never past what is still to buy after what you already got; /fpp autoqty off leaves the box alone).
-- Repeats are skipped unless the answer changed, so a quantity you type yourself is not fought.
local function EvaluateDepth(itemID)
    local active = F.Integer(itemID, 1, 2147483647) and F.activeCaps[itemID] or nil
    if not active then return end
    local cap = active.cap
    local depth, why = F.CommodityDepth(itemID, cap)
    if not depth then
        if not active.warned then
            active.warned = true
            F.Print("cannot read the " .. active.name .. " listings (" .. tostring(why) .. "): check the unit price in the buy window yourself against the limit of " .. F.Money(active.cap) .. " each.")
        end
        return
    end
    -- what is still to buy: the list's quantity less what has come into the bags since it was made
    local gained = math.max(0, F.Owned(itemID) - (active.owned0 or 0))
    local remaining = math.max(0, active.need - gained)
    -- The limit was worked out for the crafts the list asked for. If fewer units than that are listed under
    -- it, fewer crafts are bought and the odds need a lower price (less luck averaged out), so the limit is
    -- lowered until it fits the crafts that the units under it make. It only ever goes down.
    if active.ev and active.opts then
        local held = F.Owned(itemID)
        for _ = 1, 25 do
            local crafts = math.floor((held + math.min(depth.units, remaining)) / (active.qty or 1))
            local tighter = (F.Calc.PlanCaps(active.ev, active.opts, crafts) or {})[active.index] or 0
            if tighter >= cap then break end
            cap = tighter
            if cap < 1 then
                depth = { units = 0, cost = 0, levels = depth.levels, cheapest = depth.cheapest }
                break
            end
            depth = F.CommodityDepth(itemID, cap) or depth
        end
    end
    -- (the key leaves out the number of price levels and the cost, so a ladder that is still filling in or a
    -- refresh that changes nothing says nothing again)
    local target = math.min(depth.units, remaining)
    local key = target .. ":" .. cap .. ":" .. remaining
    if active.lastKey == key then return end
    active.lastKey = key
    local limit = F.Money(cap)
    -- lower the buy window's quantity box when it is open on this item and shows more than the target
    local set = false
    if target >= 1 and F.db.autoQuantity ~= false then
        local box = BuyQuantityBox(itemID)
        local shown = box and tonumber(box:GetText())
        if shown and shown > target then
            box:SetNumber(target)
            set = true
        end
    end
    -- Only what needs your attention gets a line: nothing under the limit, or fewer units than the quantity
    -- box would buy. When every unit still to buy is under the limit there is nothing to say.
    -- (a drop of a copper or two is not worth saying)
    local lowered = (active.cap - cap) / active.cap >= 0.02 and (" (limit lowered to " .. limit .. ")") or ""
    if remaining == 0 then
        F.Print(string.format("%s: you already have the %d you asked for.", active.name, active.need))
    elseif depth.units == 0 then
        F.Print(string.format("%s: none at or under %s%s.", active.name, limit,
            depth.cheapest and (" (cheapest " .. F.Money(depth.cheapest) .. ")") or ""))
    elseif depth.units < remaining then
        F.Print(string.format("%s: %d of %d under %s%s - %s %d.", active.name, depth.units, remaining, limit, lowered,
            set and "quantity set to" or "set the quantity to", target))
    end
end

-- The game fires COMMODITY_SEARCH_RESULTS_UPDATED several times while a ladder loads and after every
-- purchase: one evaluation a moment after the last of a burst is enough (without a timer, at once).
local pendingDepth = {}
function F.OnCommoditySearch(itemID)
    if not (F.Integer(itemID, 1, 2147483647) and F.activeCaps[itemID]) then return end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return EvaluateDepth(itemID) end
    if pendingDepth[itemID] then return end
    pendingDepth[itemID] = true
    C_Timer.After(0.4, function()
        pendingDepth[itemID] = nil
        EvaluateDepth(itemID)
    end)
end

-- The most to pay at the auction house for one material of a row: the plan's limit (odds, margin, budget), and
-- never more than a vendor charges for it. The vendor price is the saved price per unit from the last visit (1s2c for a bundle of 5 is 20.4c), rounded
-- down, so the auction house is only used when it is no dearer than the vendor. nil when there is no limit at all.
function F.MaterialCap(plan, index, id)
    local cap = plan and plan.caps[index] or nil
    local saved = F.db.vendorBuy and F.db.vendorBuy[id]
    local vendorUnit = type(saved) == "table" and F.Number(saved.c) and saved.c > 0 and saved.c or nil
    if vendorUnit then
        local vendorCap = math.max(1, math.floor(vendorUnit))   -- (never 0: Auctionator reads a maximum of 0 as "no maximum")
        cap = cap and math.min(cap, vendorCap) or vendorCap
    end
    return cap
end

-- Returns how many search terms went into the list, or nil when no list could be made.
function F.SendShoppingList(row)
    local api = AuctionatorAPI()
    if not api then
        F.Print("Auctionator is not loaded, or is too old to take shopping lists.")
        return nil
    end
    local ctx = F.PlanShopping(row)
    local plan = ctx.plan
    if ctx.why == "margin" then
        F.Print(string.format("no list made for %s: no price for its auction materials gives %d%% odds of finishing ahead%s with a %d%% margin (the food earns too little). Lower the odds with /fpp odds or the margin with /fpp margin.",
            row.name, ctx.odds, ctx.fill and "" or (" over " .. ctx.crafts .. " crafts"), ctx.margin))
        return 0
    elseif ctx.why == "budget" then
        F.Print(string.format("no list made for %s: your budget (%s) cannot buy even the fewest crafts that give %d%% odds (that needs about %s).",
            row.name, ctx.budget and F.Money(ctx.budget) or "none", ctx.odds, F.Money(ctx.extra or 0)))
        return 0
    end
    local crafts = plan and plan.crafts or ctx.crafts

    local terms, vendor, enough, unnamed, caps = {}, {}, {}, 0, {}
    for index, line in ipairs(row.ev.reagents) do
        local id = line.id
        local name = id and F.ItemMeta(id).name or nil
        local need = (id and (math.ceil(line.qty * crafts - 1e-9) - F.Owned(id))) or 0   -- whole units
        local _, source = F.UnitCost(id)
        if not id then
            unnamed = unnamed + 1
        elseif need <= 0 then
            enough[#enough + 1] = name or ("item " .. id)
        elseif not name then
            unnamed = unnamed + 1            -- the game has not loaded its name yet
        elseif source == "vendor" then
            vendor[#vendor + 1] = need .. "x " .. name
        else
            local cap = F.MaterialCap(plan, index, id)
            terms[#terms + 1] = SearchString(api, name, need, cap)
            caps[#caps + 1] = { name = name, need = need, cap = cap, unit = line.unit }
            if cap then   -- what the buy-depth check (F.OnCommoditySearch) needs, including the rules to tighten the limit
                F.activeCaps[id] = { cap = cap, need = need, name = name, owned0 = F.Owned(id),
                    ev = row.ev, opts = ctx.opts, index = index, qty = line.qty }
            end
        end
    end

    if #terms == 0 then
        if #vendor > 0 then
            F.Print("nothing to buy at the auction house. From a vendor: " .. table.concat(vendor, ", ") .. ".")
        elseif unnamed > 0 then
            F.Print("the game has not loaded the material names yet; try again in a moment.")
        else
            -- Say which setting made the number: a fixed "Buy for" counts what is held toward it and stops there;
            -- Max (fill the budget) only gets here when the budget itself is spent.
            local fixed = F.Integer(F.db.buyCrafts, 1, 100000) and F.db.buyCrafts or nil
            F.Print("nothing to buy: you already hold enough for " .. crafts .. " crafts of " .. row.name
                .. (fixed and (". \"Buy for\" is set to " .. fixed .. " crafts: tick Max in the window (or /fpp buy max) to keep buying within your limits.")
                    or (ctx.fill and " (the most your budget buys within the price limits)." or ".")))
        end
        return 0
    end

    local listName = "Profession Profit - " .. row.name
    local auto = F.db.autoSearch ~= false
    if auto then                                  -- first, so the Shopping tab is listening when the list appears
        local window = _G.AuctionHouseFrame
        local atAuctionHouse = type(window) == "table" and F.Has(window, "IsShown") and window:IsShown()
        if not F.ShowShoppingTab() and atAuctionHouse and not F.tabWarned then
            F.tabWarned = true   -- said once per session, so a missing piece is never a silent failure
            F.Print("could not switch Auctionator to its Shopping tab, so open it and pick the list yourself ('/fpp autosearch off' stops this note).")
        end
    end
    F.ClearOldLists(listName)
    local ok, problem = pcall(api.CreateShoppingList, F.CALLER, listName, terms)
    if not ok then
        F.Print("Auctionator did not accept the list: " .. tostring(problem))
        return nil
    end
    if auto then F.SearchShoppingList(listName) end
    -- One line for the list (the rest is in the [A] tooltip), and one more only if something was left out.
    local bits, below = {}, false
    for _, entry in ipairs(caps) do
        bits[#bits + 1] = entry.name .. (entry.cap and (" up to " .. F.Money(entry.cap)) or "")
        if entry.cap and entry.unit and entry.cap < entry.unit then below = true end
    end
    local line = string.format("%s: %s for %d crafts", listName, table.concat(bits, ", "), crafts)
    if plan then
        line = line .. " (at most " .. F.Money(plan.spend)
            .. (plan.limitedBy and string.format(", cut from %d crafts by your budget", plan.wanted) or "") .. ")"
        if below then line = line .. " |cffff6666Limit is below today's price: nothing may be listed that cheap.|r" end
    else
        line = line .. " (no price limit: a material has no price yet)"
    end
    F.Print(line)
    local left = {}
    if #vendor > 0 then left[#left + 1] = "from a vendor " .. table.concat(vendor, ", ") end
    if #enough > 0 then left[#left + 1] = "already held " .. table.concat(enough, ", ") end
    if unnamed > 0 then left[#left + 1] = unnamed .. " not loaded yet (click again)" end
    if #left > 0 then print("  Left out: " .. table.concat(left, "; ") .. ".") end
    return #terms
end
