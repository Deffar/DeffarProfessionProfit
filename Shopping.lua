-- Deffar Profession Profit: the [A] button on a row makes an Auctionator shopping list of the recipe's
-- materials. Auctionator calls: CreateShoppingList(caller, name,
-- searchStrings), which replaces a list of the same name and, at the auction house, starts searching, and
-- ConvertToSearchString(caller, { searchString, isExact, quantity, maxPrice }) (Auctionator\Source\API\v1\
-- ShoppingLists.lua, FOR-0178; maxPrice is in copper, the string holds gold: Search\Advanced.lua).
--
-- Each auction material gets a maximum price and a quantity:
--   * the highest price per unit that still gives at least the chosen odds (/dpp odds, default 90%) of
--     finishing at or above break-even over the crafts being bought (/dpp buy N, default: as many as the
--     budget allows, see F.ShoppingSettings), every
--     auction material allowed the same multiple of today's price so buying them all at their caps together
--     still meets the odds;
--   * and no higher than the price that still leaves the minimum margin on cost (/dpp margin, default 10%);
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

-- Every [A] is a fresh scan: what the character already holds is NOT taken off what is bought (human, 2026-11-27: "you have 100 murloc eyes in
-- inventory, buy X more" is not wanted; buy everything within the margin, odds and budget). The plan, the list quantities and the buy-depth check all
-- count held units as 0; only what is bought AFTER the click is counted (`owned0` is the bag count at the click, `won` the purchases), so the quantity
-- box still goes back to 0 when everything asked for has been bought.
local function NoneHeld() return 0 end

-- The numbers behind the button, also shown in its tooltip: crafts wanted, odds (percent), the budget in
-- copper (nil when the purse cannot be read and none is set) and the character's gold.
function F.ShoppingSettings()
    local db = F.db
    local crafts, fill = 100000, true   -- as many as the budget allows: no fixed number (with no readable purse either, the most there is)
    local odds = F.Integer(db.odds, 50, 99) and db.odds or 90
    local margin = F.Integer(db.margin, 0, 999) and db.margin or 10   -- percent of cost
    local gold = F.Bought and F.Bought.Money() or nil
    local budget = gold                                    -- empty box: all the gold
    if F.Integer(db.budget, 1, 100000000) then
        budget = db.budget * 10000
        if gold and gold < budget then budget = gold end   -- never more than is held
    end
    -- How many crafts the list is for: the /dpp buy number when set; otherwise as many as the budget allows
    -- (the plan cuts this down to what the budget buys within the price limits).
    if F.Integer(db.buyCrafts, 1, 100000) then
        crafts, fill = db.buyCrafts, false
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
        odds = odds / 100, crafts = crafts, budget = budget, margin = margin / 100, owned = NoneHeld,
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
-- auction house and when /dpp autosearch is on:
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
    bus:RegisterSource(busSource, "DeffarProfessionProfit")
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
-- never past what is still to buy after what you already got; /dpp autoqty off leaves the box alone).
-- Repeats are skipped unless the answer changed, so a quantity you type yourself is not fought.
-- Auctionator may set the quantity box again after we lowered it (it preselects the list's quantity when the results arrive): the lowered target
-- is checked again a few times in the next seconds and only ever lowered (a number typed later is never fought: this stops after 3 looks).
local function EnforceQuantity(itemID, target, tries)
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    C_Timer.After(0.8, function()
        local active = F.activeCaps[itemID]
        if not active or active.target ~= target or F.db.autoQuantity == false or target < 1 then return end
        local box = BuyQuantityBox(itemID)
        local shown = box and tonumber(box:GetText())
        if shown and shown > target then
            box:SetNumber(target)
            active.reapplied = (active.reapplied or 0) + 1
        end
        if tries > 1 then EnforceQuantity(itemID, target, tries - 1) end
    end)
end

-- The crafts the auction house lets this material make, from what its listings held when they were last read (`units` under the limit, `seenHeld`
-- what was in the bags then) and what is in the bags NOW: units bought since are no longer there to buy, and what is held counts. Worked out when
-- asked, never kept: right after a purchase the bags may not have the bought units yet, and a number kept from then is wrong (human report
-- 2026-11-26: "murloc eye allows only 11 crafts" after buying 500 eyes). nil until the material's listings have been read.
local function CraftsOf(a, id)
    if not (a and a.seenHeld) then return nil end
    local now = F.Owned(id)
    local bought = math.max(0, now - (a.owned0 or 0))   -- bought since the click: what was held before it counts for nothing
    local unitsLeft = math.max(0, (a.units or 0) - math.max(0, now - a.seenHeld))
    local remainingNow = math.max(0, (a.need or 0) - bought)
    return math.floor((bought + math.min(unitsLeft, remainingNow)) / (a.qty or 1))
end

local function EvaluateDepth(itemID)
    local active = F.Integer(itemID, 1, 2147483647) and F.activeCaps[itemID] or nil
    if not active then return end
    active.evals = (active.evals or 0) + 1   -- (/dpp depth)
    local cap = active.cap
    local item = F.ItemLink(itemID, active.name)   -- (the material, as a link in every line below)
    local depth, why = F.CommodityDepth(itemID, cap)
    if not depth then
        if not active.warned then
            active.warned = true
            F.Print("cannot read " .. item .. " listings (" .. tostring(why) .. "): check each unit against " .. F.Money(active.cap) .. ".")
        end
        return
    end
    -- what is still to buy: the list's quantity less what has come into the bags since it was made
    -- (the bags lag behind a purchase: "You won an auction for x569" is said before the 569 are counted, so what the won notifications added up to
    -- (`won`, Bought.lua OnPurchase) counts as well; whichever is larger; human report 2026-11-27: "169 of 569 under" right after buying the 569)
    local gained = math.max(0, F.Owned(itemID) - (active.owned0 or 0), active.won or 0)
    local remaining = math.max(0, active.need - gained)
    -- The limit was worked out for the crafts the list asked for. If fewer units than that are listed under
    -- it, fewer crafts are bought and the odds need a lower price (less luck averaged out), so the limit is
    -- lowered until it fits the crafts that the units under it make. It only ever goes down.
    local list, qty = active.list, active.qty or 1
    local others = math.huge   -- the crafts the OTHER materials of the list allow, as far as their listings have been seen
    if list then
        for _, id in ipairs(list.order) do
            local crafts = id ~= itemID and CraftsOf(list.materials[id], id) or nil
            if crafts and crafts < others then others = crafts end
        end
    end
    if active.ev and active.opts then
        for _ = 1, 25 do
            local crafts = math.min(math.floor((gained + math.min(depth.units, remaining)) / qty), others)
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
    -- the crafts the units under the limit make; the list's fewest decides: a material that is plentiful is only bought for the crafts the scarcest
    -- one allows (2 Murloc Eye and 1 Tender Crab Meat a craft: 108 eyes make 54 crafts, so 54 crab meat, not hundreds)
    local held = F.Owned(itemID)   -- (kept for CraftsOf's "bought since" and /dpp depth; never counted toward what is wanted)
    local craftsHere = math.floor((gained + math.min(depth.units, remaining)) / qty)
    local limitedBy
    if list then
        active.units, active.seenHeld = depth.units, held   -- (read by CraftsOf, for this material's turn as one of the others)
        if others < craftsHere then
            local byLimit = math.max(0, others * qty - gained)
            if byLimit < target then
                target = byLimit
                for _, id in ipairs(list.order) do
                    if id ~= itemID and CraftsOf(list.materials[id], id) == others then limitedBy = id; break end
                end
            end
        end
    end
    local key = target .. ":" .. cap .. ":" .. remaining .. ":" .. tostring(others < math.huge and others or "-")
    active.target, active.units, active.others, active.heldSeen = target, depth.units, others < math.huge and others or nil, held
    if active.lastKey == key then return end
    active.lastKey = key
    local limit = F.Money(cap)
    -- lower the buy window's quantity box when it is open on this item and shows more than the target
    local set = false
    if F.db.autoQuantity ~= false then
        local box = BuyQuantityBox(itemID)
        local shown = box and tonumber(box:GetText())
        active.boxSeen, active.boxShown = box ~= nil, shown
        if target >= 1 then
            if shown and shown > target then
                box:SetNumber(target)
                set = true
            end
        elseif depth.units == 0 and remaining > 0 and shown and shown ~= 0 then
            box:SetNumber(0)   -- nothing at or under the limit: the old quantity is no use (and is not left for a careless click); Auctionator's box takes a 0 (human, 2026-11-26)
            set = true
        elseif remaining == 0 and shown and shown ~= 0 then
            box:SetNumber(0)   -- everything asked for is bought: the box goes back to 0 as it does when nothing is under the limit (human, 2026-11-27)
            set = true
        end
        if set and target >= 1 then EnforceQuantity(itemID, target, 3) end
    end
    -- Only what needs your attention gets a line: nothing under the limit, or fewer units than the quantity
    -- box would buy. When every unit still to buy is under the limit there is nothing to say.
    -- (a drop of a copper or two is not worth saying)
    local lowered = (active.cap - cap) / active.cap >= 0.02 and (" (limit lowered to " .. limit .. ")") or ""
    if remaining == 0 then
        F.Print(string.format("%s: already have the %d%s.", item, active.need, set and "; quantity set to 0" or ""))
    elseif depth.units == 0 then
        F.Print(string.format("%s: none at or under %s%s%s.", item, limit,
            depth.cheapest and (" (cheapest " .. F.Money(depth.cheapest) .. ")") or "", set and "; quantity set to 0" or ""))
    elseif limitedBy then
        F.Print(string.format("%s: %d under %s, but %s allows only %d crafts - %s %d.", item, depth.units, limit,
            F.ItemLink(limitedBy, list.materials[limitedBy] and list.materials[limitedBy].name), others, set and "quantity set to" or "set quantity to", target))
    elseif depth.units < remaining then
        F.Print(string.format("%s: %d of %d under %s%s - %s %d.", item, depth.units, remaining, limit, lowered,
            set and "quantity set to" or "set quantity to", target))
    end
    -- this material is now the one that decides the crafts: say what that means for the other materials of the list (their windows
    -- may already have been seen, or are still to be opened)
    if list and not limitedBy and craftsHere <= others and craftsHere < (list.announced or list.planned or math.huge) and craftsHere < (list.planned or math.huge) then
        list.announced = craftsHere
        local parts = {}
        for _, id in ipairs(list.order) do
            local e = list.materials[id]
            if id ~= itemID and e then
                local want = math.max(0, craftsHere * (e.qty or 1))
                if want < e.need then parts[#parts + 1] = want .. " " .. F.ItemLink(id, e.name) end
            end
        end
        if #parts > 0 then
            F.Print(string.format("%s allows only %d crafts: buy %s.", item, craftsHere, table.concat(parts, ", ")))
        end
    end
end

-- /dpp depth: what the last [A] list knows about each of its auction materials, to tell why a quantity box was or was not lowered.
function F.DepthReport()
    local lines, any = {}, false
    for id, a in pairs(F.activeCaps) do
        any = true
        local list = a.list
        local crafts = list and CraftsOf(a, id)
        lines[#lines + 1] = string.format("%s: limit %s each, wanted %s, held at the list %s now %s; seen %dx%s; units under it %s, crafts it allows %s, others allow %s, target %s; buy window %s%s%s.",
            F.ItemLink(id, a.name), F.Money(a.cap or 0), tostring(a.need), tostring(a.owned0), tostring(F.Owned(id)), a.evals or 0,
            (a.evals or 0) == 0 and " (its listings have not been read: open its buy window)" or "", tostring(a.units), tostring(crafts), tostring(a.others or "-"), tostring(a.target),
            a.boxSeen == nil and "not looked at" or (a.boxSeen and ("found, showed " .. tostring(a.boxShown)) or "NOT found"), a.reapplied and (", lowered again " .. a.reapplied .. "x") or "",
            a.warned and ", listings unreadable" or "")
    end
    if not any then lines[1] = "no [A] list made yet this session." end
    return lines
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

---------------------------------------------------------------------------
-- TSM: the [T] button. TSM has no shopping-list API, but it replaces the game's ChatEdit_InsertLink and HandleModifiedItemClick with wrappers
-- that, when no chat box takes the link, start a Browse search for that item in its auction window (TradeSkillMaster\LibTSMWoW\Source\API\Item.lua
-- HookLink, App\AuctionUI\Core.lua ACTION_HANDLE_ITEM_LINKED -> Shopping ACTION_START_ITEM_SEARCH). Linking an item here is the same as a
-- shift-click on it, so each press searches ONE material of the recipe: the next one at every press, and the chat line gives its quantity and the
-- most to pay per unit (TSM's search has no limit of its own). Read from the installed TSM, UNVERIFIED in game (plans/addons/TSM-integration.md).
---------------------------------------------------------------------------

F.tsmCursor = {}   -- [recipe name] = the index of the material the next press searches

-- The auction materials of a row, the way the [A] list works them out: { { id, name, need, cap }, ... } and the context (nil, ctx when no list
-- could be made: ctx.why says why).
function F.ShoppingMaterials(row)
    local ctx = F.PlanShopping(row)
    if ctx.why == "margin" or ctx.why == "budget" then return nil, ctx end
    local plan = ctx.plan
    local crafts = plan and plan.crafts or ctx.crafts
    local list = {}
    for index, line in ipairs(row.ev.reagents) do
        local id = line.id
        if id then
            local need = math.ceil(line.qty * crafts - 1e-9)   -- (held units are not taken off: every search is a fresh scan)
            local _, source = F.UnitCost(id)
            if need > 0 and source ~= "vendor" then
                list[#list + 1] = { id = id, name = F.ItemMeta(id).name, need = need, cap = F.MaterialCap(plan, index, id) }
            end
        end
    end
    return list, ctx
end

-- "<item>/exact/<most per unit>/x<quantity>": TSM's filter for one material (LibTSMService\Source\Item\ItemFilter.lua: `exact`, a money string, `x<n>`);
-- a Browse filter string holds several of them separated by ";" (LibTSMApp\Source\Shopping\Internal\FilterSearch.lua splits on it), so one search covers
-- every material of the recipe. nil for a material without a name.
local function TSMFilter(entry)
    if not entry.name then return nil end
    if entry.cap then
        local gold, silver, copper = math.floor(entry.cap / 10000), math.floor(entry.cap % 10000 / 100), entry.cap % 100
        local price = (gold > 0 and (gold .. "g") or "") .. (silver > 0 and (silver .. "s") or "") .. (copper > 0 and (copper .. "c") or "")
        return entry.name .. "/exact/" .. price .. "/x" .. entry.need
    end
    return entry.name .. "/exact/x" .. entry.need
end

-- One press of [T]: searches the recipe's auction materials in TSM's Browse tab, all in one search with the price limit and the quantity of each (the
-- filter is typed into TSM's search box for the player: Prices.lua TSMTypeAndSearch). When the box cannot be found (not on Browse, an unknown TSM
-- language, a changed TSM) it falls back to linking one material, the next at every press, and prints its filter. Returns true when a search was started.
function F.TSMSearch(row)
    if not F.Prices.TSMAuctionVisible() then
        F.Print("open TSM's auction window on its Browse tab first (it does the searching).")
        return false
    end
    local list, ctx = F.ShoppingMaterials(row)
    local craft = F.ItemLink(row.recipe and row.recipe.out or row.itemID, row.name)
    if not list then
        F.Print(ctx.why == "margin" and (craft .. " earns too little for the odds and margin: nothing to buy.") or (craft .. ": the budget is too small for the odds."))
        return false
    end
    if #list == 0 then
        F.Print("nothing to buy at the auction house for " .. craft .. ".")
        return false
    end
    -- 1. typed: every material in one search
    local parts, shown = {}, {}
    for _, entry in ipairs(list) do
        local filter = TSMFilter(entry)
        if filter then
            parts[#parts + 1] = filter
            shown[#shown + 1] = string.format("%s x%d%s", F.ItemLink(entry.id, entry.name), entry.need, entry.cap and (" <= " .. F.Money(entry.cap)) or "")
        end
    end
    if #parts > 0 then
        local function Typed()
            local ok, done, why = pcall(F.Prices.TSMTypeAndSearch, table.concat(parts, ";"))
            if not ok then return false, tostring(done) end
            return done, why
        end
        local done, why = Typed()
        if not done then   -- on the results page: Exit Scan goes back to the search page, then try again
            local ok, back = pcall(F.Prices.TSMExitScanButton)
            if ok and back and type(back.Click) == "function" then
                pcall(back.Click, back)
                done, why = Typed()
            end
        end
        if done then
            F.Print("TSM: " .. table.concat(shown, ", "))
            return true
        end
        F.tsmWhy = why   -- (/dpp tsmfind says it)
    end
    -- 2. linked: one material per press (TSM turns a linked item into a search when no chat box takes it)
    if type(ChatEdit_GetActiveWindow) == "function" and ChatEdit_GetActiveWindow() ~= nil then
        F.Print("close the chat box first: a linked item goes into it, not into the search.")
        return false
    end
    local index = F.tsmCursor[row.name] or 1
    if index > #list then index = 1 end
    local entry = list[index]
    local link
    if F.Has(_G.C_Item, "GetItemInfo") then link = select(2, _G.C_Item.GetItemInfo(entry.id)) end
    if not (F.String(link) and link:find("|Hitem:", 1, true)) then
        F.Print((entry.name or ("item " .. entry.id)) .. ": the game has not loaded the item yet, press again in a moment.")
        return false
    end
    if type(ChatEdit_InsertLink) ~= "function" then
        F.Print("this client has no ChatEdit_InsertLink, so TSM cannot be asked to search.")
        return false
    end
    F.tsmCursor[row.name] = index + 1
    ChatEdit_InsertLink(link)
    local filter = TSMFilter(entry)
    F.Print(string.format("TSM %d/%d: %s - buy %d%s.%s", index, #list, link, entry.need, entry.cap and (" up to " .. F.Money(entry.cap) .. " each") or "",
        filter and (" Or type: " .. filter) or "") .. (F.tsmWhy and (" (typing into TSM failed: " .. tostring(F.tsmWhy) .. ")") or ""))
    return true
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
    local craft = F.ItemLink(row.recipe and row.recipe.out or row.itemID, row.name)   -- the finished item, as a link in the chat lines below
    if ctx.why == "margin" then
        F.Print(string.format("no list made for %s: no price for its auction materials gives %d%% odds of finishing ahead%s with a %d%% margin (the food earns too little). Lower the odds with /dpp odds or the margin with /dpp margin.",
            craft, ctx.odds, ctx.fill and "" or (" over " .. ctx.crafts .. " crafts"), ctx.margin))
        return 0
    elseif ctx.why == "budget" then
        F.Print(string.format("no list made for %s: your budget (%s) cannot buy even the fewest crafts that give %d%% odds (that needs about %s).",
            craft, ctx.budget and F.Money(ctx.budget) or "none", ctx.odds, F.Money(ctx.extra or 0)))
        return 0
    end
    local crafts = plan and plan.crafts or ctx.crafts

    local terms, vendor, unnamed, caps = {}, {}, 0, {}
    -- what the auction house lets this list buy, shared by its materials (EvaluateDepth): crafts need ALL their materials, so the one with
    -- the fewest units under its limit decides how many of every other one is worth buying
    local listState = { crafts = {}, materials = {}, order = {}, planned = crafts }
    for index, line in ipairs(row.ev.reagents) do
        local id = line.id
        local name = id and F.ItemMeta(id).name or nil
        local need = (id and math.ceil(line.qty * crafts - 1e-9)) or 0   -- whole units; what is held is not taken off (fresh scan)
        local _, source = F.UnitCost(id)
        if not id then
            unnamed = unnamed + 1
        elseif need <= 0 then
            -- (a material the recipe does not use: nothing to buy)
        elseif not name then
            unnamed = unnamed + 1            -- the game has not loaded its name yet
        elseif source == "vendor" then
            vendor[#vendor + 1] = need .. "x " .. F.ItemLink(id, name)
        else
            local cap = F.MaterialCap(plan, index, id)
            terms[#terms + 1] = SearchString(api, name, need, cap)
            caps[#caps + 1] = { name = name, id = id, need = need, cap = cap, unit = line.unit }
            if cap then   -- what the buy-depth check (F.OnCommoditySearch) needs, including the rules to tighten the limit
                F.activeCaps[id] = { cap = cap, need = need, name = name, craft = craft, owned0 = F.Owned(id),
                    ev = row.ev, opts = ctx.opts, index = index, qty = line.qty, list = listState }
                listState.materials[id] = F.activeCaps[id]
                listState.order[#listState.order + 1] = id
            end
        end
    end

    if #terms == 0 then
        if #vendor > 0 then
            F.Print("nothing to buy at the auction house. From a vendor: " .. table.concat(vendor, ", ") .. ".")
        elseif unnamed > 0 then
            F.Print("the game has not loaded the material names yet; try again in a moment.")
        else
            F.Print("nothing to buy for " .. craft .. ".")
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
            F.Print("could not switch Auctionator to its Shopping tab, so open it and pick the list yourself ('/dpp autosearch off' stops this note).")
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
        bits[#bits + 1] = F.ItemLink(entry.id, entry.name) .. (entry.cap and (" up to " .. F.Money(entry.cap)) or "")
        if entry.cap and entry.unit and entry.cap < entry.unit then below = true end
    end
    -- one short line: the finished item, how many crafts, the most it can cost, then each material with its price limit.
    -- (with no fixed number of crafts the wanted count is only "as many as possible" (100000): the budget cut it, which is all the line says)
    local count = (plan and plan.limitedBy and not ctx.fill) and string.format("%d of %d", crafts, plan.wanted) or tostring(crafts)
    local line
    if plan then
        line = string.format("%s for %s crafts, max %s%s: %s", craft, count, F.Money(plan.spend), plan.limitedBy and " (budget)" or "", table.concat(bits, ", "))
        if below then line = line .. " |cffff6666Limit below today's price.|r" end
    else
        line = string.format("%s for %s crafts, no price limit (a price is missing): %s", craft, count, table.concat(bits, ", "))
    end
    F.Print(line)
    local left = {}
    if #vendor > 0 then left[#left + 1] = "vendor " .. table.concat(vendor, ", ") end
    if unnamed > 0 then left[#left + 1] = unnamed .. " not loaded" end
    if #left > 0 then print("  Left out: " .. table.concat(left, "; ") .. ".") end
    return #terms
end
