-- Deffar Profession Profit: what the cooking materials really cost at the auction house. When the game reports a
-- commodity purchase (AUCTION_HOUSE_SHOW_COMMODITY_WON_NOTIFICATION, with the item and the quantity: the
-- same moment it prints "You won an auction for Buzzard Wing (x100)") the gold that just left the
-- character's purse is charged to that item, so the luck window's Spent figure can use what was really paid
-- instead of an estimate. Cooking materials are commodities; gear is not covered.
--
-- How the gold is found: the purse is read when the auction house opens and on every PLAYER_MONEY; each
-- drop is remembered with its time. When a purchase notification arrives, the drops from the previous 2
-- seconds that no earlier purchase used are its cost (the money may leave a moment before or after).
-- Purchases that arrive together (several stacks) share the drops in proportion to quantity x Auctionator
-- price. Gold spent in those same seconds on something else (a deposit, a vendor) would be charged by mistake.
--
-- Only items that are a material of a saved cooking recipe are kept; every other purchase is ignored.
-- Saved: F.db.bought[itemID] = { n = units bought, c = copper paid for them, p = last unit price, t = time }, and F.db.lots[itemID] = { { q = units left, p = unit price paid, t = time }, ... }
-- oldest first: every purchase is a lot, and each craft takes its materials from the oldest lots first (first in, first out), so a
-- craft's cost is what the units it used were really bought for. Units with no lot (looted, gathered, bought before lots were
-- kept) are priced at market by the caller. The lots are not matched to what is in the bags: a material sold or used another
-- way keeps its lot until crafts use it up. At most MAX_LOTS lots an item; past that the two oldest are merged at their average.
-- Evidence (FOR-0180): the notification's payload was observed by a probe on the client; the chat
-- line itself reached no CHAT_MSG_* event. Not yet confirmed: that GetMoney() has dropped within the 2 seconds
-- (three retries at 0.6 s cover a later update) and that the first argument stays a plain name.
local _, F = ...
local B = {}
F.Bought = B

B.EVENT = "AUCTION_HOUSE_SHOW_COMMODITY_WON_NOTIFICATION"
B.seen = 0           -- purchase notifications seen
B.skipped = {}       -- reason -> count
B.drops, B.pending = {}, {}
local MAX = 2147483647
local LOOKBACK, FLUSH_DELAY, MAX_RETRIES = 2, 0.6, 3   -- seconds, seconds, tries
local retries, scheduled = 0, false

local function Skip(reason)
    B.skipped[reason] = (B.skipped[reason] or 0) + 1
    return nil, reason
end

---------------------------------------------------------------------------
-- The purse
---------------------------------------------------------------------------

-- Copper the character holds, or nil when it cannot be read. (Over 214,000 gold does not fit
-- F.Integer's range, so this checks the number itself.)
function B.Money()
    if type(GetMoney) ~= "function" then return nil end
    local money = GetMoney()
    if F.Number(money) and money >= 0 then return money end
    return nil
end

-- The purse at this moment becomes the starting point (the auction house just opened, or the addon loaded).
function B.Snapshot()
    B.baseline = B.Money()
end

-- PLAYER_MONEY: a drop since the last reading is remembered with its time; a rise just moves the starting point.
function B.OnMoney()
    local now = B.Money()
    if not now then return end
    if B.baseline and now < B.baseline then
        local time = GetTime()
        B.drops[#B.drops + 1] = { time = time, amount = B.baseline - now }
        while #B.drops > 0 and time - B.drops[1].time > 30 do table.remove(B.drops, 1) end
    end
    B.baseline = now
end

---------------------------------------------------------------------------
-- Which item
---------------------------------------------------------------------------

-- Every item that is a material of a saved recipe (cooking or engineering), on any character: { [itemID] = true }.
function B.Reagents()
    local set = {}
    for _, char in pairs(F.db and F.db.chars or {}) do
        for _, key in ipairs(F.TABS) do
            local store = type(char) == "table" and char[F.PROFESSIONS[key].store] or nil
            for _, recipe in pairs(type(store) == "table" and store or {}) do
                for _, reagent in ipairs(type(recipe) == "table" and type(recipe.r) == "table" and recipe.r or {}) do
                    for _, id in ipairs(type(reagent.ids) == "table" and reagent.ids or {}) do
                        if F.Integer(id, 1, MAX) then set[id] = true end
                    end
                end
            end
        end
    end
    return set
end

-- An item ID, a link or a plain name -> the itemID of a cooking material, or nil.
function B.Resolve(item)
    local reagents = B.Reagents()
    if type(item) == "number" then return reagents[item] and item or nil end
    if not F.String(item) then return nil end
    local id = tonumber(item:match("|Hitem:(%d+)"))
    if id then return reagents[id] and id or nil end
    local name = item:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%[", ""):gsub("%]$", ""):lower()
    for candidate in pairs(reagents) do
        local meta = F.ItemMeta(candidate)
        if meta.name and meta.name:lower() == name then return candidate end
    end
    return nil
end

---------------------------------------------------------------------------
-- Charging the gold
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Lots
---------------------------------------------------------------------------

local MAX_LOTS = 300

local function Lots(id, create)
    local db = F.db
    if not db then return nil end
    if type(db.lots) ~= "table" then
        if not create then return nil end
        db.lots = {}
    end
    local list = db.lots[id]
    if type(list) ~= "table" then
        if not create then return nil end
        list = {}
        db.lots[id] = list
    end
    return list
end

local function GoodLot(lot)
    return type(lot) == "table" and F.Number(lot.q) and lot.q > 0 and F.Number(lot.p) and lot.p >= 0
end

-- One purchase: `quantity` units at `unit` copper each, behind the lots already there (they are used oldest first).
function B.AddLot(id, quantity, unit)
    if not (F.Integer(quantity, 1, MAX) and F.Number(unit) and unit >= 0) then return end
    local list = Lots(id, true)
    if not list then return end
    local last = list[#list]
    if GoodLot(last) and math.abs(last.p - unit) < 0.5 then
        last.q = last.q + quantity   -- the same price as the newest lot: one lot
    else
        list[#list + 1] = { q = quantity, p = unit, t = F.Now() }
    end
    while #list > MAX_LOTS do
        local a, b = list[1], list[2]
        if GoodLot(a) and GoodLot(b) then
            a.p = (a.p * a.q + b.p * b.q) / (a.q + b.q)
            a.q = a.q + b.q
            table.remove(list, 2)
        else
            table.remove(list, 1)
        end
    end
end

-- The unit price of the oldest lot (what the next unit used costs), or nil when there is none.
function B.NextPrice(id)
    local list = Lots(id, false)
    if not list then return nil end
    for _, lot in ipairs(list) do
        if GoodLot(lot) then return lot.p end
    end
    return nil
end

-- How many units the lots hold.
function B.LotUnits(id)
    local list = Lots(id, false)
    local units = 0
    for _, lot in ipairs(list or {}) do
        if GoodLot(lot) then units = units + lot.q end
    end
    return units
end

-- Uses `quantity` units from the oldest lots. Returns the copper those units were bought for, how many came from lots, and how many
-- were not covered by any lot (the caller prices those at market).
function B.Take(id, quantity)
    local list = Lots(id, false)
    local copper, taken = 0, 0
    local left = quantity
    while list and left > 0 and #list > 0 do
        local lot = list[1]
        if not GoodLot(lot) then
            table.remove(list, 1)
        else
            local n = math.min(lot.q, left)
            copper, taken, left = copper + n * lot.p, taken + n, left - n
            lot.q = lot.q - n
            if lot.q <= 0 then table.remove(list, 1) end
        end
    end
    return copper, taken, left
end

function B.Record(id, quantity, copper)
    local db = F.db
    if not db then return end
    if type(db.bought) ~= "table" then db.bought = {} end
    local entry = db.bought[id]
    if type(entry) ~= "table" then entry = {}; db.bought[id] = entry end
    local n = F.Integer(entry.n, 0, MAX) and entry.n or 0
    local c = (F.Number(entry.c) and entry.c >= 0) and entry.c or 0
    entry.n, entry.c, entry.p, entry.t = n + quantity, c + copper, copper / quantity, F.Now()
    B.AddLot(id, quantity, copper / quantity)
    B.last = { id = id, quantity = quantity, copper = copper, time = GetTime() }
end

-- The average unit price paid for an item and how many units that covers; nil when nothing was tracked.
function B.Average(id)
    local entry = F.db and type(F.db.bought) == "table" and F.db.bought[id]
    if type(entry) == "table" and F.Integer(entry.n, 1, MAX) and F.Number(entry.c) and entry.c >= 0 then
        return entry.c / entry.n, entry.n
    end
    return nil
end

local function Schedule(delay)
    if scheduled then return end
    scheduled = true
    C_Timer.After(delay, function()
        scheduled = false
        B.Flush()
    end)
end

-- Charges the pending purchases with the unused gold drops from just before the first of them.
function B.Flush()
    if #B.pending == 0 then return end
    local from = B.pending[1].time - LOOKBACK
    local spend, used = 0, {}
    for _, drop in ipairs(B.drops) do
        if not drop.used and drop.time >= from then spend = spend + drop.amount; used[#used + 1] = drop end
    end
    if spend <= 0 then
        retries = retries + 1
        if retries <= MAX_RETRIES then Schedule(FLUSH_DELAY) return end   -- the purse may not have updated yet
        retries = 0
        B.skipped.nomoney = (B.skipped.nomoney or 0) + #B.pending
        B.pending = {}
        return
    end
    retries = 0
    for _, drop in ipairs(used) do drop.used = true end
    local weights, total = {}, 0
    for index, line in ipairs(B.pending) do
        weights[index] = line.quantity * (F.AuctionPrice(line.id) or 1)
        total = total + weights[index]
    end
    for index, line in ipairs(B.pending) do B.Record(line.id, line.quantity, spend * weights[index] / total) end
    B.pending = {}
end

-- AUCTION_HOUSE_SHOW_COMMODITY_WON_NOTIFICATION(item, quantity). When the item is a cooking material it is
-- queued and charged a moment later (Flush), once the purse has updated. Returns true when queued.
function B.OnPurchase(item, quantity)
    if not F.Integer(quantity, 1, MAX) then return nil end
    B.seen = B.seen + 1
    local id = B.Resolve(item)
    if not id then return Skip("notamaterial") end
    B.pending[#B.pending + 1] = { time = GetTime(), id = id, quantity = quantity }
    Schedule(FLUSH_DELAY)
    return true
end

---------------------------------------------------------------------------
-- Gear. Gear is not a commodity: it
-- is bought one auction at a time with C_AuctionHouse.PlaceBid(auctionID, amount) (HasRestrictions: an addon cannot call it, but can
-- watch it with hooksecurefunc), and AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID) says it went through (both declared in the client's
-- AuctionHouseDocumentation, FOR-0194; not yet seen on Forever). The item is read from C_AuctionHouse.GetAuctionInfoByID(auctionID)
-- (AuctionInfo.itemKey.itemID) when the bid is placed. What was paid is saved in the same F.db.bought as a material, so
-- B.Average(itemID) is what the character really paid per piece; the luck window's Enchanting tab uses it as what a disenchanted
-- piece cost.
---------------------------------------------------------------------------

B.bids = {}          -- [auctionID] = { id, amount }: bids placed, until the purchase is reported
B.gearSeen, B.gearRecorded = 0, 0   -- for /dpp status

function B.OnBid(auctionID, amount)
    if not (F.Integer(auctionID, 1, MAX) and F.Number(amount) and amount > 0) then return end
    B.gearSeen = B.gearSeen + 1
    local api = _G.C_AuctionHouse
    local info = F.Has(api, "GetAuctionInfoByID") and api.GetAuctionInfoByID(auctionID) or nil
    local id = F.Table(info) and F.Table(info.itemKey) and info.itemKey.itemID or nil
    if not F.Integer(id, 1, MAX) and F.Table(info) and F.String(info.itemLink) then id = tonumber(info.itemLink:match("|Hitem:(%d+)")) end
    if not F.Integer(id, 1, MAX) then return Skip("nobiditem") end
    B.bids[auctionID] = { id = id, amount = amount, time = GetTime() }
end

-- AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID): the bid that was placed went through (a buyout): what was paid is the price of one.
function B.OnPurchaseCompleted(auctionID)
    local bid = B.bids[auctionID]
    if not bid then return nil end
    B.bids[auctionID] = nil
    B.Record(bid.id, 1, bid.amount)
    B.gearRecorded = B.gearRecorded + 1
    return bid.id
end

local bidsHooked = false
function B.HookBids()
    if bidsHooked then return true end
    local api = _G.C_AuctionHouse
    if not (F.Has(api, "PlaceBid") and type(hooksecurefunc) == "function") then return false end
    hooksecurefunc(api, "PlaceBid", function(auctionID, amount) B.OnBid(auctionID, amount) end)
    bidsHooked = true
    return true
end

-- /dpp paid [item link] 40s x3: adds purchases made before they were tracked (price of one, how many).
function B.Paid(link, copper, count)
    local id = F.String(link) and tonumber(link:match("|Hitem:(%d+)")) or nil
    if not (F.Integer(id, 1, MAX) and F.Number(copper) and copper > 0 and F.Integer(count, 1, 100000)) then return nil end
    B.Record(id, count, copper * count)
    return id
end

-- "40s", "1g 20s", "2g50s5c", "125" (silver by default is NOT assumed: a bare number is copper) -> copper, or nil.
function B.ParseMoney(text)
    if not F.String(text) then return nil end
    local total, found = 0, false
    for amount, unit in text:gmatch("(%d+)%s*([gsc])") do
        total = total + tonumber(amount) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
        found = true
    end
    if found then return total end
    local bare = tonumber(text:match("^%s*(%d+)%s*$"))
    return bare
end

