-- Deffar Profession Profit: the Enchanting tab. Not recipes but a buy list: every weapon and armour piece in Auctionator's last
-- scan, ranked by what disenchanting it is worth against what it costs at the auction house.
--
-- The odds are Auctionator's own: it ships a Forever disenchant table (Source_Classic\Enchant, loaded for game type
-- camelot, Auctionator.toc 44) and its public API turns an item ID into the average value of its disenchant at today's
-- dust and essence prices, `Auctionator.API.v1.GetDisenchantPriceByItemID` (Source\API\v1\GetDisenchantPrice.lua).
-- Both were read from the installed addon, not run (FOR-0191). The items come from its price database,
-- `Auctionator.Database.db`: keys are the item ID, or "gr:<itemID>:<suffix>" for a random-suffix item, and `.m` is the
-- last seen lowest price (Source\Database\Mixin.lua, Source\Utilities\DBKeyFromLink.lua). That table is an internal, not
-- the stable API, so everything here is checked and the tab says so when a piece is missing.
--
-- value = Auctionator's disenchant value x (1 - the auction house cut): the dust is sold at the auction house. profit =
-- value - the item's price; the return is profit / price. The item must be learned-skill-eligible to disenchant: the
-- skill needed rises with item level and is not checked here.
local _, F = ...
local D = {}
F.Disenchant = D

-- Every item that pays is kept; of the ones that lose money only the best, up to this many rows in all. (Cutting by absolute profit
-- first hid the cheap items with a high return behind expensive ones with a tiny one.)
-- Items that cannot be disenchanted although they are weapons or armour of the right quality. Built in by name (lower case, the item's own name), and the
-- player can add more: `db.noDisenchant[itemID] = name`, with a Ctrl-click on a row or /dpp nodisenchant.
D.NEVER = { ["lesser magic wand"] = true, ["greater magic wand"] = true, ["lesser mystic wand"] = true, ["greater mystic wand"] = true }   -- the enchanter-made wands

function D.Blocked(itemID, name)
    if F.String(name) and D.NEVER[name:lower()] then return true end
    local saved = F.db and F.db.noDisenchant
    return type(saved) == "table" and saved[itemID] ~= nil
end

local MAX_ROWS = 2000
local GEAR = { [2] = true, [4] = true }   -- weapon and armour item classes (what Auctionator disenchants)
local GOOD, EPIC = 2, 4              -- item qualities that disenchant: uncommon, rare, epic

local function API()
    local auctionator = _G.Auctionator
    local api = type(auctionator) == "table" and type(auctionator.API) == "table" and auctionator.API.v1 or nil
    if type(api) == "table" and type(api.GetDisenchantPriceByItemID) == "function" then return api end
    return nil
end

local function PriceDatabase()
    local auctionator = _G.Auctionator
    local database = type(auctionator) == "table" and auctionator.Database or nil
    if type(database) == "table" and type(database.db) == "table" then return database end
    return nil
end

function D.Available()
    return API() ~= nil and PriceDatabase() ~= nil
end

-- The gear keys of the price database, and each item's disenchant value: both kept until a price changes
-- (F.OnAuctionPrice), since a window redraw happens often and the database holds thousands of keys.
local candidates
local values = {}

-- The finished list is kept too: turning a
-- page repaints the window, which used to rebuild every row from the database each time.
--
-- And it holds still while the player works: a search makes Auctionator save new prices, and rebuilding and re-sorting the list on each
-- of those moved and removed the rows under the pointer. Now a price change only updates the NUMBERS of the rows already in
-- the list, in place (D.revision counts these), at most every 2 s; the rows themselves, their order and which are shown change
-- only on a full rebuild (D.version counts those): when the window is opened, the tab is chosen, the Refresh button is pressed,
-- the auction house is closed, a scan has finished, or, a few times at most, while items were still loading.
local cache, dirty, stale = nil, false, false
local builtAt, updatedAt = 0, -math.huge
D.version = 0                        -- counts full rebuilds: the window re-filters and re-sorts when it changes
D.revision = 0                       -- counts in-place updates of the numbers: the window redraws the cells
D.burst = 0                          -- price changes since the last quiet moment (a scan is thousands of them)
local MAX_LOAD_REBUILDS = 8

local function Clock()
    return type(GetTime) == "function" and GetTime() or 0
end

-- Which rows a price change touches: the price of a gear piece changes that row alone (its disenchant value does not depend on it); the price of an
-- Enchanting material (dust, essence, shard) changes what every row disenchants for, so it touches them all.
local changedKeys, changedAll = {}, false
local pendingRows, pendingAll = {}, false   -- what the window has not drawn yet: the rows changed, or everything

local function IsMaterial(id)
    if not F.Has(C_Item, "GetItemInfoInstant") then return false end
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(id)
    return class == 7 and subclass == 12
end

-- Items searched at the auction house and not found. Auctionator only writes a price when a search FINDS the item, so a sold one keeps its last price
-- forever; the search's own result is the one thing that says it is gone. `D.gone[dbKey]` keeps it out of the list until
-- Auctionator writes a price for that key again (a scan or a search that finds it).
-- It is saved (`db.gone[key] = { p = the price it had, t = when }`) so a reload does not bring it back, and it is let back only when
-- Auctionator writes a DIFFERENT price for the key (a new listing), not when the same old price is saved again. Entries older than a week are forgotten.
local GONE_DAYS = 7
local function Gone()
    local db = F.db
    if not db then return {} end
    if type(db.gone) ~= "table" then db.gone = {} end
    return db.gone
end
function D.IsGone(key)
    local entry = Gone()[key]
    if type(entry) ~= "table" then return false end
    if F.Now() - (F.Number(entry.t) and entry.t or 0) > GONE_DAYS * 86400 then Gone()[key] = nil; return false end
    return true
end
local goneRows = {}                      -- removed since the window last looked: it takes them out of its shown list

function D.TakeGone()
    local rows = goneRows
    goneRows = {}
    return rows
end

-- A full rebuild on the next redraw.
function D.Invalidate()
    candidates, values, cache, dirty, stale = nil, {}, nil, false, false
    changedKeys, changedAll, pendingRows, pendingAll = {}, false, {}, false
end

-- Auctionator saved the price of `key` (its price database key): the numbers of the rows it touches are refreshed on the next
-- redraw, the list itself is left alone.
function D.PricesChanged(key)
    stale = true
    D.burst = D.burst + 1
    if type(key) == "string" and Gone()[key] then   -- a new price for a removed item means it is listed again; the same old one does not
        local database = PriceDatabase()
        local entry = database and database.db[key]
        local now = type(entry) == "table" and entry.m or nil
        if now ~= Gone()[key].p then Gone()[key] = nil end
    end
    local id = type(key) == "string" and tonumber(key:match("^(%d+)$")) or nil
    if type(key) ~= "string" then
        changedAll, values = true, {}                    -- (no key given: assume everything)
    elseif id and IsMaterial(id) then
        changedAll, values = true, {}
    else
        changedKeys[key] = true
    end
end

-- What changed since the window last asked: { all = true } or { rows = { row, ... } }, then forgotten.
function D.TakeChange()
    local change = { all = pendingAll, rows = pendingRows }
    pendingRows, pendingAll = {}, false
    return change
end

function D.ItemsArrived()
    if cache and cache.info.loading > 0 and cache.loads < MAX_LOAD_REBUILDS then dirty = true end
end

function D.Pending()
    return dirty or stale
end

local function Candidates(database)
    if candidates then return candidates end
    local list = {}
    local instant = F.Has(C_Item, "GetItemInfoInstant")
    for key in pairs(database.db) do
        if type(key) == "string" then
            local id, suffix = key:match("^(%d+)$"), nil
            if not id then id, suffix = key:match("^gr:(%d+):(.+)$") end
            id = tonumber(id)
            if id then
                local class
                if instant then class = select(6, C_Item.GetItemInfoInstant(id)) end
                if class == nil or GEAR[class] then list[#list + 1] = { key = key, id = id, suffix = suffix } end
            end
        end
    end
    candidates = list
    return list
end

-- The price of one result item for the odds: essences Auctionator combines count at its rate, as its own disenchant value does.
local function MakeUnit()
    local constants = _G.Auctionator and _G.Auctionator.Constants
    local mapping = type(constants) == "table" and constants.DisenchantingMatMapping or nil
    local memo = {}
    return function(id)
        local price = memo[id]
        if price == nil then
            price = F.AuctionPrice(id)
            local greater = type(mapping) == "table" and mapping[id] or nil
            if greater then
                local upper = F.AuctionPrice(greater)
                if price and upper and price * 3 > upper then price = math.floor(upper / 3) end
            end
            memo[id] = price or false
            price = memo[id]
        end
        return price or nil
    end
end

-- Sets a row's figures from today's price and disenchant value (a new row, or an update in place).
local function Apply(row, price, gross)
    local net = math.floor(gross * (1 - F.AH_CUT))
    local profit = net - price
    local ev, de = row.ev, row.de
    ev.cost, ev.value, ev.expected, ev.baseProfit, ev.profit, ev.sellEach = price, net, net, profit, profit, net
    ev.margin = price > 0 and profit / price or nil
    de.price, de.gross, de.net = price, gross, net
end

-- The average value of ONE disenchant of an item, in copper after the auction house's cut: the figure a recipe tab uses when it values
-- a crafted piece by disenchanting it. nil while the
-- item's data has not loaded (a status of its own, "loading"), 0 when it cannot be disenchanted (not weapon or armour of uncommon to
-- epic quality, blacklisted, or no bracket) or its results have no price.
function D.ValueOf(itemID)
    local meta = F.ItemMeta(itemID)
    if meta.class == nil or meta.quality == nil then return nil end
    if not (GEAR[meta.class] and meta.quality >= GOOD and meta.quality <= EPIC) or D.Blocked(itemID, meta.name) then return 0 end
    local bracket = D.Bracket(itemID)
    if not bracket then return nil end   -- (the link's item level may not be known yet)
    return math.floor(D.Gross(bracket, MakeUnit()) * (1 - F.AH_CUT))
end

-- Returns rows, info in the shape F.BuildRows gives for a recipe tab: each row has `ev` (the fields the columns read:
-- cost = the item's price, value = the disenchant value after the cut) and `de` (the figures behind it).
-- When Auctionator last STARTED a full scan of the auction house (seconds since 1970), nil when it does not say. It keeps one
-- stamp per kind of auction-house client (TimeOfLastReplicateScan, TimeOfLastGetAllScan: Source_ModernAH / Source_LegacyAH
-- FullScan\Mixins\Frame.lua) and sets it when the scan begins, not when it ends; the newer of the two is the scan that was done
--.
local function LastScan()
    local auctionator = _G.Auctionator
    local state = type(auctionator) == "table" and auctionator.SavedState or nil
    if type(state) ~= "table" then return nil end
    local newest
    for _, at in ipairs({ state.TimeOfLastReplicateScan or 0, state.TimeOfLastGetAllScan or 0 }) do
        if F.Number(at) and at > 0 and (not newest or at > newest) then newest = at end
    end
    return newest
end

-- Seconds until Auctionator lets another full scan start: it needs 15 minutes since the last one began (modern client:
-- CanInitiate in Source_ModernAH\FullScan\Mixins\Frame.lua; the classic client's own GetAll limit is the same 15 minutes), 0 when
-- one can start now or no scan is on record.
local SCAN_WAIT = 15 * 60
function D.ScanCooldown()
    local at = LastScan()
    if not at then return 0 end
    return math.max(0, SCAN_WAIT - (F.Now() - at))
end

local function Build()
    local started = type(debugprofilestop) == "function" and debugprofilestop() or nil
    local info = { prof = "enchanting", proc = false, disenchant = true, rank = 0, source = "none", count = 0, missing = 0, loading = 0 }
    local api, database = API(), PriceDatabase()
    if not (api and database) then
        info.unavailable = true
        return {}, info
    end
    local rows = {}
    local unit = MakeUnit()
    local list = Candidates(database)
    local stats = { candidates = #list, noPrice = 0, notDisenchantable = 0, noValue = 0, positive = 0 }
    info.stats = stats
    for _, c in ipairs(list) do
        local entry = database.db[c.key]
        local price = type(entry) == "table" and entry.m or nil
        if D.IsGone(c.key) then
            stats.gone = (stats.gone or 0) + 1
        elseif not (F.Number(price) and price > 0) then
            stats.noPrice = stats.noPrice + 1
        else
            local meta = F.ItemMeta(c.id)
            if meta.quality == nil or meta.class == nil or not meta.name then
                info.loading = info.loading + 1
            elseif not (GEAR[meta.class] and meta.quality >= GOOD and meta.quality <= EPIC) or D.Blocked(c.id, meta.name) then
                stats.notDisenchantable = stats.notDisenchantable + 1
            else
                local gross = values[c.id]
                if gross == nil then
                    local bracket = D.Bracket(c.id)
                    if bracket then
                        gross = D.Gross(bracket, unit)
                    else   -- (no table of its own for it: Auctionator's own figure, when it has one)
                        local ok, value = pcall(api.GetDisenchantPriceByItemID, F.CALLER, c.id)
                        gross = (ok and F.Number(value)) and value or false
                    end
                    if gross == 0 then gross = false end
                    values[c.id] = gross
                end
                if not (gross and gross > 0) then
                    stats.noValue = stats.noValue + 1
                else
                    local net = math.floor(gross * (1 - F.AH_CUT))
                    local profit = net - price
                    if profit > 0 then stats.positive = stats.positive + 1 end
                    local name = c.suffix and (meta.name .. " " .. c.suffix) or meta.name
                    local age = F.Has(database, "GetPriceAge") and database:GetPriceAge(c.key) or nil   -- days since the price was last seen
                    rows[#rows + 1] = { id = c.key, itemID = c.id, name = name, item = meta, via = {},
                        vendorValue = (meta.sell and meta.sell > 0) and meta.sell or nil,
                        ev = { status = "ok", rank = 0, chance = 0, reagents = {}, missing = 0, complete = true, yield = 1,
                            cost = price, value = net, expected = net, baseProfit = profit, profit = profit,
                            margin = price > 0 and profit / price or nil, sellEach = net },
                        de = { key = c.key, price = price, gross = gross, net = net, searchName = name, age = age } }
                end
            end
        end
    end
    stats.listed = #rows
    table.sort(rows, function(a, b)
        if a.ev.profit ~= b.ev.profit then return a.ev.profit > b.ev.profit end
        return a.name < b.name
    end)
    D.lastRows = rows
    local paying = 0
    for index, row in ipairs(rows) do
        if row.ev.profit > 0 then paying = index else break end   -- (sorted: the paying ones come first)
    end
    for index = #rows, math.max(paying, MAX_ROWS) + 1, -1 do rows[index] = nil end
    info.count = #rows
    -- the odds of a single disenchant paying (only for the rows kept): essences the player can combine count at Auctionator's
    -- rate, as its own disenchant value does
    for _, row in ipairs(rows) do
        row.de.bracket = D.Bracket(row.itemID)   -- kept, so an update in place does not look it up again
        row.de.odds = row.de.bracket and D.ProfitChance(row.de.bracket, row.de.price, unit) or nil
    end
    -- how old the prices behind the list are (the oldest one shown)
    if F.Has(database, "GetPriceAge") then
        local oldest
        for _, row in ipairs(rows) do
            local age = database:GetPriceAge(row.de.key)
            if age and (not oldest or age > oldest) then oldest = age end
        end
        info.oldest = oldest
        -- and the freshest: 0 means some price was seen today (the scan did write prices)
        local newest
        for _, row in ipairs(rows) do
            local age = row.de.age
            if age and (not newest or age < newest) then newest = age end
        end
        info.newest = newest
    end
    info.keys, info.builtAt, info.scanAt = #list, F.Now(), LastScan()
    info.ms = started and (debugprofilestop() - started) or nil
    return rows, info
end

-- /dpp de: what the tab saw in Auctionator's data, to tell a bug from an auction house without bargains.
function D.Report()
    local lines = {}
    if not D.Available() then
        return { "Auctionator's price database or disenchant API is missing." }
    end
    D.Invalidate()   -- a fresh build, so the counts are today's
    local rows, info = D.Rows()
    local s = info.stats
    lines[#lines + 1] = string.format("price database: %d gear keys; %d without a price, %d not uncommon-or-better gear, %d with no disenchant value (dust prices unknown?), %d still loading.",
        s.candidates, s.noPrice, s.notDisenchantable, s.noValue, info.loading)
    lines[#lines + 1] = string.format("listed %d, of which %d with a profit above 0 (value after the %d%% cut minus the AH price).",
        s.listed, s.positive, math.floor(F.AH_CUT * 100 + 0.5))
    local function Show(title, list)
        for index = 1, math.min(3, #list) do
            local row = list[index]
            lines[#lines + 1] = string.format("%s %d: %s - price %s, disenchants for %s (%s after the cut), profit %s.", title, index,
                row.name, F.Money(row.de.price), F.Money(row.de.gross), F.Money(row.de.net), F.ProfitText(row.ev.profit))
        end
    end
    Show("best profit", rows)
    local byValue = {}
    for _, row in ipairs(rows) do byValue[#byValue + 1] = row end
    table.sort(byValue, function(a, b) return a.de.gross > b.de.gross end)
    Show("highest disenchant value", byValue)
    return lines
end

-- Auctionator's own lines for what an item disenchants into ("  37.5% 1 Strange Dust"), nil when it has none to give.
function D.Breakdown(itemID)
    local auctionator = _G.Auctionator
    local enchant = type(auctionator) == "table" and auctionator.Enchant or nil
    if not (type(enchant) == "table" and type(enchant.GetDisenchantBreakdown) == "function" and F.Has(C_Item, "GetItemInfo")) then return nil end
    local data = { C_Item.GetItemInfo(itemID) }
    if not F.String(data[2]) then return nil end
    local ok, lines = pcall(enchant.GetDisenchantBreakdown, data[2], data)
    if ok and type(lines) == "table" and #lines > 0 then return lines end
    return nil
end

-- The numbers of the rows a price change touched, from today's prices (every row when a material's price changed); no row is
-- added, removed or moved. `byKey` is the cache's index of its rows by database key.
local function UpdateRows(rows, byKey)
    local api, database = API(), PriceDatabase()
    if not (api and database) then return end
    local unit = MakeUnit()
    local function Update(row, recompute)
        local entry = database.db[row.de.key]
        local price = type(entry) == "table" and entry.m or nil
        if F.Number(price) and price > 0 then
            local gross = row.de.gross
            if recompute then
                if row.de.bracket then
                    local value = D.Gross(row.de.bracket, unit)
                    if value > 0 then gross = value end
                else
                    local ok, value = pcall(api.GetDisenchantPriceByItemID, F.CALLER, row.itemID)
                    if ok and F.Number(value) and value > 0 then gross = value end
                end
            end
            Apply(row, price, gross)
            row.de.age = F.Has(database, "GetPriceAge") and database:GetPriceAge(row.de.key) or row.de.age
        end
        row.de.odds = row.de.bracket and D.ProfitChance(row.de.bracket, row.de.price, unit) or nil
    end
    if changedAll then
        for _, row in ipairs(rows) do Update(row, true) end
        pendingAll = true
    else
        for key in pairs(changedKeys) do
            local row = byKey[key]
            if row then Update(row, false); pendingRows[#pendingRows + 1] = row end
        end
    end
    changedKeys, changedAll = {}, false
end

function D.Rows()
    if cache and not (dirty and Clock() - builtAt >= 2) then
        if stale and Clock() - updatedAt >= 2 then
            UpdateRows(cache.rows, cache.byKey)
            stale, updatedAt = false, Clock()
            D.revision = D.revision + 1
        end
        return cache.rows, cache.info
    end
    local loads = cache and (cache.loads + 1) or 0   -- rebuilds made because items were still loading
    local rows, info = Build()
    if info.unavailable then return rows, info end   -- (not kept: Auctionator may load later)
    local byKey = {}
    for _, row in ipairs(rows) do byKey[row.de.key] = row end
    cache = { rows = rows, info = info, loads = loads, byKey = byKey }
    changedKeys, changedAll, pendingRows, pendingAll = {}, false, {}, true   -- (a fresh list: the window draws all of it)
    dirty, stale, builtAt, updatedAt = false, false, Clock(), -math.huge   -- (the first update after a build is not made to wait)
    D.version = D.version + 1
    D.revision = D.revision + 1
    return rows, info
end

-- What an item disenchants into, from Auctionator's own table (Auctionator.Constants.DisenchantingProbability[class][quality],
-- a list of brackets { lowest item level, highest, then triples: percent, quantity, itemID }, the same lookup its
-- Atr_FindDEentry does; an internal, FOR-0191): { { id, chance (percent), average (items per disenchant) }, ... } with
-- every outcome of one item added together (low / high: the fewest and most items when it drops; average: items per
-- disenchant over all disenchants, so chance x quantity), the most valuable first. nil when the table, the item or its level is not
-- available.
-- Corrections to Auctionator's table, from Wowhead Forever (FOR-0193). Same shape as its brackets: { lowest item level, highest,
-- then triples of percent, quantity, itemID }, one triple per possible result of a single disenchant. Checked before its table.
--   Epic weapons and armour, item level 56 to 85: 80% one Nexus Crystal, 20% two to four Large Brilliant Shards (an equal third
--   each). Auctionator has 100% Nexus Crystal; Wowhead's recorded disenchants of "Lifestone" (item level 56, epic) are 22 of 28
--   Nexus Crystal and 6 of 28 Large Brilliant Shard (quantity 2-4 shown on its icon), and its Disenchant page has epics 56-83 giving
--   Large Brilliant Shard 21% and 56-85 Nexus Crystal 84%. Wowhead's pages say these counts are from Classic Era; the same rule is
--   assumed up to item level 85, which is UNVERIFIED above 56.
local NEXUS, LARGE_BRILLIANT = 20725, 14344
local EPIC_56_85 = { 56, 85, 80, 1, NEXUS, 20 / 3, 2, LARGE_BRILLIANT, 20 / 3, 3, LARGE_BRILLIANT, 20 / 3, 4, LARGE_BRILLIANT }
D.OVERRIDES = { [2] = { [4] = { EPIC_56_85 } }, [4] = { [4] = { EPIC_56_85 } } }   -- [item class][quality] = brackets

-- The bracket of Auctionator's table an item falls in (its class, quality and item level): { low, high, then triples of
-- percent, quantity, itemID }, nil when the table, the item or its level is not available. Each triple is one possible
-- result of a single disenchant and the triples add up to 100%.
function D.Bracket(itemID)
    local auctionator = _G.Auctionator
    local constants = type(auctionator) == "table" and auctionator.Constants or nil
    local table_ = type(constants) == "table" and constants.DisenchantingProbability or nil
    if not F.Has(C_Item, "GetItemInfo") then return nil end
    local data = { C_Item.GetItemInfo(itemID) }
    local link, quality, class = data[2], data[3], data[12]
    if not (F.String(link) and F.Integer(quality, 0, 10) and F.Integer(class, 0, 100)) then return nil end
    local levelOf = C_Item.GetDetailedItemLevelInfo or _G.GetDetailedItemLevelInfo
    local level = type(levelOf) == "function" and levelOf(link) or nil
    if not F.Number(level) then return nil end
    local keys = type(constants) == "table" and constants.DisenchantingProbabilityKeys or nil
    local low, high = keys and keys.LOW or 1, keys and keys.HIGH or 2
    local function Find(brackets)
        if type(brackets) ~= "table" then return nil end
        for _, entry in pairs(brackets) do
            if type(entry) == "table" and F.Number(entry[low]) and F.Number(entry[high]) and level >= entry[low] and level <= entry[high] then
                return entry
            end
        end
        return nil
    end
    local mine = D.OVERRIDES[class]
    local entry = Find(mine and mine[quality])
    if entry then return entry end
    if type(table_) ~= "table" then return nil end
    return type(table_[class]) == "table" and Find(table_[class][quality]) or nil
end

-- What one disenchant of a bracket is worth on average, in copper: the sum of chance x quantity x unit price over its results
-- (the same sum as Auctionator's own, `Atr_CalcDisenchantPrice`, but over the bracket above, so a correction applies).
-- `unit(itemID)` is the price of one result (nil: none, worth nothing).
function D.Gross(entry, unit)
    local total = 0
    for x = 3, #entry, 3 do
        local percent, quantity, id = entry[x], entry[x + 1], entry[x + 2]
        if F.Number(percent) and F.Number(quantity) and F.Integer(id, 1, 2147483647) then
            local each = unit(id)
            if each then total = total + percent * quantity * each end
        end
    end
    return math.floor(total / 100)
end

-- The chance, in percent, that ONE disenchant of an item bought at `price` brings in more than that after the auction
-- house's cut. Each triple of
-- the bracket is one outcome with its own value (quantity x the unit price x (1 - cut)); the chances of the outcomes that beat
-- the price are added. `unit(itemID)` is the unit price (nil: none, that outcome counts as worth nothing).
function D.ProfitChance(entry, price, unit)
    local chance = 0
    for x = 3, #entry, 3 do
        local percent, quantity, id = entry[x], entry[x + 1], entry[x + 2]
        if F.Number(percent) and F.Number(quantity) and F.Integer(id, 1, 2147483647) then
            local each = unit(id)
            if each and math.floor(quantity * each * (1 - F.AH_CUT)) > price then chance = chance + percent end
        end
    end
    return chance
end

function D.Outcomes(itemID)
    local entry = D.Bracket(itemID)
    if entry then
        do
            local byItem, list = {}, {}
            for x = 3, #entry, 3 do
                local percent, quantity, id = entry[x], entry[x + 1], entry[x + 2]
                if F.Number(percent) and F.Number(quantity) and F.Integer(id, 1, 2147483647) and percent > 0 then
                    local out = byItem[id]
                    if not out then out = { id = id, chance = 0, average = 0, low = quantity, high = quantity }; byItem[id] = out; list[#list + 1] = out end
                    out.chance = out.chance + percent
                    out.average = out.average + percent * quantity / 100   -- per disenchant, the misses counted: chance x quantity
                    if quantity < out.low then out.low = quantity end
                    if quantity > out.high then out.high = quantity end
                end
            end
            for _, out in ipairs(list) do out.price = F.AuctionPrice(out.id) end
            table.sort(list, function(a, b)
                local x, y = a.average * (a.price or 0), b.average * (b.price or 0)
                if x ~= y then return x > y end
                return a.id < b.id
            end)
            return list
        end
    end
    return nil
end

local function IconText(icon, size)
    if icon == nil then return "" end
    return "|T" .. tostring(icon) .. ":" .. size .. "|t "
end

-- The highest price worth paying for a row's item at the Margin set (what [A] searches with): its price after the cut over (1 + margin).
function D.Cap(de)
    local margin = F.Integer(F.db.margin, 0, 100) and F.db.margin or 10
    return math.floor(de.net / (1 + margin / 100)), margin
end

-- What an item disenchants into, one line per result in the shared look (Style.lua): "[icon] Name" and, on the right, the chance
-- and how many come when it does. With `worth` (the Profit tooltip) what that is worth when it drops follows: "= 1s - 2s (50c each)".
function D.TipOutcomes(tip, itemID, worth)
    local outcomes = D.Outcomes(itemID)
    if not outcomes then return end
    local St = F.Style
    local names = _G.Auctionator and _G.Auctionator.Constants and _G.Auctionator.Constants.DisenchantingItemName
    tip:AddLine(" ")
    tip:AddLine("Disenchants into", St.DIM[1], St.DIM[2], St.DIM[3])
    for _, out in ipairs(outcomes) do
        local meta = F.ItemMeta(out.id)
        local label
        if meta.name then
            label = St.ItemLabel(out.id)
        else
            label = IconText(meta.icon, 14) .. ((type(names) == "table" and names[out.id]) or ("Item " .. out.id))
        end
        local quantity = out.low == out.high and tostring(out.low) or (out.low .. "-" .. out.high)
        local right = St.Percent((string.format("%.1f", out.chance):gsub("%.0$", "")) .. "%") .. St.Grey(" x") .. St.Paint(St.SAGE, quantity)
        if worth then
            if out.price then
                local sum = F.Money(out.low * out.price)
                if out.high ~= out.low then sum = sum .. St.Grey(" - ") .. F.Money(out.high * out.price) end
                right = right .. St.Grey(" = ") .. sum .. St.Grey(" (") .. F.Money(out.price) .. St.Grey(" each)")
            else
                right = right .. St.Grey(" = no price")
            end
        end
        tip:AddDoubleLine(label, right, 1, 1, 1, 1, 1, 1)
    end
end

-- The row tooltip over the item name (tip is the collector UI.lua's NewTip returns): short facts, in the shared look.
function D.TipLines(tip, d)
    local St = F.Style
    local de = d.de
    tip:AddLine("Click: search it at the auction house.", 0.5, 0.8, 1)
    tip:AddLine("Shift-click: the highest price to pay.", 0.5, 0.8, 1)
    tip:AddLine("Ctrl-click: it cannot be disenchanted, hide it.", 0.5, 0.8, 1)
    local database = PriceDatabase()
    local age = database and F.Has(database, "GetPriceAge") and database:GetPriceAge(de.key) or nil
    St.Line(tip, "AH price", F.Money(de.price) .. ((age and age >= 1) and St.Grey(string.format(" (%d d old)", math.floor(age))) or ""))
    if d.vendorValue then St.Line(tip, "Vendor sell price", F.Money(d.vendorValue)) end
    D.TipOutcomes(tip, d.itemID, false)
end

-- The tooltip over the Profit / Return cell: how the profit is worked out.
function D.ProfitLines(tip, d)
    local St = F.Style
    local de, ev = d.de, d.ev
    St.Line(tip, "AH price (to buy)", F.Money(de.price))
    St.Line(tip, "Disenchants for (average)", F.Money(de.gross))
    St.Line(tip, string.format("After the %d%% AH cut", math.floor(F.AH_CUT * 100 + 0.5)), F.Money(de.net))
    St.Line(tip, "Profit", St.Signed(ev.profit))
    if ev.margin then St.Line(tip, "Return", St.Percent(string.format("%.0f%%", ev.margin * 100))) end
    if de.odds then St.Line(tip, "Chance one disenchant pays", St.Percent(math.floor(de.odds + 0.5) .. "%")) end
    local cap, margin = D.Cap(de)
    if cap >= 1 then St.Line(tip, St.Grey("Highest price to pay (") .. St.Percent(margin .. "%") .. St.Grey(")"), F.Money(cap)) end
    D.TipOutcomes(tip, d.itemID, true)
end

-- Makes the Auctionator list "Profession Profit - Disenchant" with this one item, at the highest price that still leaves the
-- margin on cost (/dpp margin, default 10%), and searches it when the auction house is open (as the [A] button does).
function D.Search(row)
    local api = F.ShoppingAPI and F.ShoppingAPI()
    if not api then
        F.Print("Auctionator is not loaded, or is too old to take shopping lists.")
        return nil
    end
    local de = row.de
    local cap, margin = D.Cap(de)
    if cap < 1 then
        F.Print(row.name .. " is not worth buying at any price with a " .. margin .. "% margin.")
        return nil
    end
    local listName = "Profession Profit - Disenchant"
    local auto = F.db.autoSearch ~= false
    if auto then F.ShowShoppingTab() end
    D.Listen()
    D.searching = { key = de.key, itemID = row.itemID, name = de.searchName, time = Clock() }   -- what the search finds (or not) is read in `listener` above
    F.ClearOldLists(listName)   -- one list at a time, whichever tab made the earlier ones
    local ok, problem = pcall(api.CreateShoppingList, F.CALLER, listName, { F.SearchString(api, de.searchName, 1, cap) })
    if not ok then
        F.Print("Auctionator did not accept the list: " .. tostring(problem))
        return nil
    end
    if auto then F.SearchShoppingList(listName) end
    F.Print(string.format("%s: %s up to %s (disenchants for about %s after the AH cut; today's price %s).",
        listName, row.name, F.Money(cap), F.Money(de.net), F.Money(de.price)))
    return cap
end

-- Takes a row out of the list (it was searched for and is not there).
function D.Remove(key)
    local database = PriceDatabase()
    local entry = database and database.db[key]
    Gone()[key] = { p = type(entry) == "table" and entry.m or nil, t = F.Now() }
    if not cache then return end
    for index, row in ipairs(cache.rows) do
        if row.de.key == key then
            table.remove(cache.rows, index)
            cache.byKey[key] = nil
            cache.info.count = math.max(0, cache.info.count - 1)
            goneRows[#goneRows + 1] = row
            D.revision = D.revision + 1
            return
        end
    end
end

-- Auctionator's shopping search events (its event bus, an internal: FOR-0187; everything is checked). When the search this addon
-- just made for an item ends and its results do not hold the item, it is gone, or at least not at a price that still pays (the
-- search carries the highest price worth paying), so it leaves the list.
--
-- Only the end of OUR search counts. Starting a search first stops the one running (Source\Tabs\Shopping\Mixins\Main.lua DoSearch -> AbortSearch), which
-- announces ITS end, with whatever it had, just before ours starts: so the search is only watched from the start event that carries
-- our term, a later start of another search cancels the watch, and the results must be seen not to hold the item (a placeholder
-- entry for "no results", item 1217, does not count as holding it).
local listener = {}

local function SearchEvents()
    local auctionator = _G.Auctionator
    local tab = type(auctionator) == "table" and type(auctionator.Shopping) == "table" and auctionator.Shopping.Tab or nil
    local events = type(tab) == "table" and tab.Events or nil
    if type(events) == "table" and F.String(events.SearchStart) and F.String(events.SearchEnd) then return events end
    return nil
end

-- Whether a search's results hold anything real (true when they cannot be read). The search is for one exact item name, so ANY
-- entry that is not the placeholder Auctionator adds for "no results" (item 1217, `noneAvailable`, quantity 0) means the item is
-- there: judging by the item ID alone removed items still on the auction house.
local function HoldsItem(results, itemID)
    if type(results) ~= "table" then return true end
    for _, entry in ipairs(results) do
        if type(entry) == "table" and not entry.noneAvailable then
            local id = type(entry.itemKey) == "table" and entry.itemKey.itemID or nil
            local text = F.String(entry.itemString) and entry.itemString or nil
            local placeholder = id == 1217 or (text ~= nil and text:find("^item:1217[ :]") ~= nil)
            local empty = F.Number(entry.totalQuantity) and entry.totalQuantity <= 0
            if not placeholder and not empty then return true end
        end
    end
    return false
end
D.HoldsItem = HoldsItem   -- (tests)

local function TermsInclude(terms, name)
    if type(terms) ~= "table" or not F.String(name) then return false end
    for _, term in ipairs(terms) do
        if F.String(term) and term:find(name, 1, true) then return true end
    end
    return false
end

-- A search that is ABORTED announces its end too, with whatever it had loaded so far (Auctionator Source\Search\Mixins\MultiSearchMixin.lua
-- AbortSearch calls the completion callback), and with the default setting (no entry for terms without results) that is an empty list
-- exactly like a search that really found nothing. Auctionator aborts a search when the player leaves it: collapsing the list, opening
-- the buy screen for a result, switching tab or closing the house, pressing Search again (Source\Tabs\Shopping\Mixins\Main.lua StopSearch).
-- Leaving the page while it was still loading made items with dozens of listings disappear from the list (human report, 2026-11-24).
-- So the abort is wrapped on the shopping tab's search provider (the global frame AuctionatorShoppingFrame, FOR-0187): an end that
-- arrives while an abort is running is not an answer. Without that frame the old behaviour stays and /dpp status says so.
local aborting = false
function D.GuardAborts()
    local frame = _G.AuctionatorShoppingFrame
    local provider = type(frame) == "table" and frame.SearchProvider or nil
    if type(provider) ~= "table" or type(provider.AbortSearch) ~= "function" then return D.abortGuard == true end
    if provider.dppGuarded then D.abortGuard = true; return true end
    local original = provider.AbortSearch
    provider.AbortSearch = function(self, ...)
        local was = aborting
        aborting = true
        local result = original(self, ...)   -- (the end event is fired from inside this call)
        aborting = was
        return result
    end
    provider.dppGuarded = true
    D.abortGuard = true
    return true
end

local removal   -- { key } of an item whose search ended with nothing real, waiting a moment to be sure the search was not stopped for a new one

function listener:ReceiveEvent(eventName, data)
    local events = SearchEvents()
    if not events then return end
    if aborting and eventName == events.SearchEnd then return end   -- the end of a search the player left: it says nothing about the item
    local search = D.searching
    if search and Clock() - search.time > 120 then D.searching = nil; search = nil end
    if eventName == events.SearchStart then
        -- a search starting after an "end" with nothing: that end was the old search being stopped for this one. Judge by this search instead.
        removal = nil
        if not search then return end
        if not search.started then
            if TermsInclude(data, search.name) then search.started = true end   -- ours has begun
        elseif not TermsInclude(data, search.name) then
            D.searching = nil   -- another search began while ours was running: ours was cut short
        end
        return
    end
    if not (search and search.started) then return end   -- the end of an earlier search, stopped by ours
    if HoldsItem(data, search.itemID) then
        D.searching, removal = nil, nil
        return
    end
    -- nothing real: wait a moment, and only if no new search starts meanwhile is the item gone
    local mine = { key = search.key }
    removal = mine
    local function Confirm()
        if removal ~= mine then return end   -- a search started since: it decides
        removal = nil
        if D.searching == search then D.searching = nil end
        D.Remove(mine.key)
        if F.UI and F.UI.IsShown() then F.UI.Refresh() end
    end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(0.6, Confirm) else Confirm() end
end

local listening = false
function D.Listen()
    D.GuardAborts()
    if listening then return true end
    local auctionator = _G.Auctionator
    local bus = type(auctionator) == "table" and auctionator.EventBus or nil
    local events = SearchEvents()
    if not (type(bus) == "table" and F.Has(bus, "Register") and events) then return false end
    bus:Register(listener, { events.SearchStart, events.SearchEnd })
    listening = true
    return true
end
D.listener = listener   -- (tests)

-- Adds an item to the player's list of things that cannot be disenchanted, taking it (every price of it) out of the list at once.
function D.Block(itemID, name)
    if not (F.db and F.Integer(itemID, 1, 2147483647)) then return false end
    if type(F.db.noDisenchant) ~= "table" then F.db.noDisenchant = {} end
    F.db.noDisenchant[itemID] = F.String(name) and name or (F.ItemMeta(itemID).name or true)
    if cache then
        for index = #cache.rows, 1, -1 do
            local row = cache.rows[index]
            if row.itemID == itemID then
                table.remove(cache.rows, index)
                cache.byKey[row.de.key] = nil
                cache.info.count = math.max(0, cache.info.count - 1)
                goneRows[#goneRows + 1] = row
            end
        end
        D.revision = D.revision + 1
    end
    if F.UI and F.UI.IsShown() then F.UI.Refresh() end
    return true
end

function D.Unblock(itemID)
    if F.db and type(F.db.noDisenchant) == "table" and F.db.noDisenchant[itemID] ~= nil then
        F.db.noDisenchant[itemID] = nil
        D.Invalidate()   -- the item is back on the next draw
        return true
    end
    return false
end

