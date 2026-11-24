-- Deffar Profession Profit: what selling at the auction house really brings in. A ledger per item name, shown as the "AH sales" tab of the luck window (LuckUI.lua):
--
--   p  units put up for sale (a unit put up again after it came back counts once: see r)   a  auctions posted
--   r  units put up again after coming back unsold (cancel, expiry); e - r is what is back and not up again
--   d  deposits paid when posting     (copper; refunded inside the sale money when it sells, kept by the house when it does not)
--   s  units sold                     m  money received for them (the mail's money: price - the 5% cut + the deposit back)
--   e  units that came back unsold    (expired or cancelled: the deposit stays lost, it was counted when posting)
--
-- Net = m - d, so a sale nets price less the cut and an unsold auction nets minus its deposit. Profit (the luck window's column) is
-- that less the crafting cost of the units sold (Aggregate's costOf). What is still listed is
-- p - s - e. It is only what happened while this addon was loaded: units posted before then have no deposit on record, and a
-- sale or return with more units than posted is marked so (the "*" in the window).
--
-- Where each number comes from (all UNVERIFIED on Forever, FOR-0197; /dpp salestrace prints every step):
--   posting   hooksecurefunc on C_AuctionHouse.PostCommodity / PostItem (declared in the client's AuctionHouseDocumentation):
--             the item is read from the ItemLocation, the deposit from CalculateCommodityDeposit / CalculateItemDeposit; the
--             post counts once AUCTION_HOUSE_AUCTION_CREATED is seen (a failed post must not cost a deposit). Until that event
--             has been seen once on this install, a post counts after a few seconds without a failure instead.
--   sold      the sale mail, when its money is taken (TakeInboxMoney / AutoLootMailItem, hooked after the call): GetInboxInvoiceInfo
--             says "seller" and names the item and the count; GetInboxHeaderInfo says how much money. "Sale Pending" invoices
--             (seller_temp_invoice, the 1 hour payment delay) carry no money and are ignored.
--   unsold    an "Auction expired" / "Auction canceled" mail, when its item is taken (TakeInboxItem / AutoLootMailItem).
local _, F = ...
local S = {}
F.Sales = S

S.session = {}
S.counts = { posts = 0, created = 0, sold = 0, returned = 0, dropped = 0 }   -- for /dpp status
S.pending = {}        -- posts waiting for the game to say they went through: { name, id, units, deposit, time }
local MAX = 2147483647
local CONFIRM_WAIT = 4
local taken = {}      -- mails already counted since the inbox last updated (a mail is hooked by more than one take call)

---------------------------------------------------------------------------
-- The ledger
---------------------------------------------------------------------------

-- The three tables a figure is added to: this session, this character, the account (Luck.lua has the same three scopes).
local function Roots()
    local list = { S.session }
    if F.db then
        local char = F.Char()
        if char then
            if type(char.sales) ~= "table" then char.sales = {} end
            list[#list + 1] = char.sales
        end
        if type(F.db.sales) ~= "table" then F.db.sales = {} end
        list[#list + 1] = F.db.sales
    end
    return list
end

function S.Root(scope)
    if scope == "session" then return S.session end
    if not F.db then return nil end
    if scope == "life" then
        if type(F.db.sales) ~= "table" then F.db.sales = {} end
        return F.db.sales
    end
    if scope == "char" then
        local char = F.Char()
        if char and type(char.sales) ~= "table" then char.sales = {} end
        return char and char.sales or nil
    end
    return nil
end

-- The client puts a count in these mails' subjects ("Auction canceled: Briny Seafood Stew (79)"): never part of the item's name, or each
-- count would be a row of its own.
local function Clean(name)
    if not F.String(name) then return name end
    return (name:gsub("%s*%(%d+%)%s*$", ""))
end

local function Add(name, id, fields)
    name = Clean(name)
    if not (F.String(name) and name ~= "") then return end
    for _, root in ipairs(Roots()) do
        local entry = root[name]
        if type(entry) ~= "table" then entry = { p = 0, a = 0, d = 0, s = 0, m = 0, e = 0 }; root[name] = entry end
        if F.Integer(id, 1, MAX) then entry.id = id end
        for key, value in pairs(fields) do
            if key == "p" then
                -- Units that came back unsold (cancel, expiry) and are put up again are one unit listed twice, not two units
                --. They are counted
                -- in r instead; the deposit and the auction still count in full, they were really paid.
                local back = math.max(0, (F.Number(entry.e) and entry.e or 0) - (F.Number(entry.r) and entry.r or 0))
                local again = math.min(value, back)
                entry.r = (F.Number(entry.r) and entry.r or 0) + again
                entry.p = (F.Number(entry.p) and entry.p or 0) + (value - again)
            else
                entry[key] = (F.Number(entry[key]) and entry[key] or 0) + value
            end
        end
    end
end

-- The item ID a name was seen with (a sale or a return only names the item).
local function IdFor(name)
    name = Clean(name)
    for _, root in ipairs(Roots()) do
        local entry = root[name]
        if type(entry) == "table" and F.Integer(entry.id, 1, MAX) then return entry.id end
    end
    return nil
end

-- An item ID for a name when no post of it was watched (a sale or a return only names the item, so its row had no icon).
-- Looked up in what the addon already knows by name: the items it has loaded and saved, the
-- crafts it has counted, then the client (GetItemInfoInstant takes a name only for an item it has already seen; unverified).
local function ResolveID(name)
    if not F.db then return nil end
    if type(F.db.items) == "table" then
        for id, saved in pairs(F.db.items) do
            if type(saved) == "table" and saved.name == name and F.Integer(id, 1, MAX) then return id end
        end
    end
    if type(F.db.luck) == "table" then
        for _, entry in pairs(F.db.luck) do
            if type(entry) == "table" and entry.name == name and F.Integer(entry.out, 1, MAX) then return entry.out end
        end
    end
    local api = _G.C_Item
    if F.Has(api, "GetItemInfoInstant") then
        local id = api.GetItemInfoInstant(name)
        if F.Integer(id, 1, MAX) then return id end
    end
    return nil
end

function S.Reset()
    S.session = {}
end

-- Deletes one item's row from a scope's ledger ("session", "char" or "life"): the luck window's delete button. Returns whether
-- there was one. The other scopes keep their own copy of the item.
function S.Delete(scope, name)
    local root = S.Root(scope)
    if root and F.String(name) and root[name] ~= nil then
        root[name] = nil
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- A correction by hand
---------------------------------------------------------------------------

-- What `units` more sold units of an item would have brought in at today's Auctionator price: the price less the house's cut, plus the
-- deposit back (an estimate: the deposit paid so far over the units listed so far, per unit). Returns copper and the price of one, or
-- nil when Auctionator has no price for it.
function S.MarketValue(scope, name, id, units)
    if not F.Integer(units, 1, MAX) then return nil end
    local price = F.Integer(id, 1, MAX) and F.AuctionPrice(id) or nil
    if not (F.Number(price) and price > 0) then return nil end
    local value = math.floor(price * units * (1 - F.AH_CUT))
    local root = S.Root(scope)
    local entry = root and root[Clean(name)]
    if type(entry) == "table" and F.Number(entry.p) and entry.p > 0 and F.Number(entry.d) and entry.d > 0 then
        value = value + math.floor(entry.d / entry.p * units)
    end
    return value, price
end

-- Adds sales that were missed to one item of one scope's ledger ("session", "char" or "life"): `units` more sold and `money` more
-- received. Returns whether it was done (the item has to be in the ledger already).
function S.Adjust(scope, name, units, money)
    local root = S.Root(scope)
    local entry = root and F.String(name) and root[name]
    if type(entry) ~= "table" then return false end
    if not (F.Integer(units, 1, 100000) and F.Number(money) and money >= 0) then return false end
    entry.s = (F.Number(entry.s) and entry.s or 0) + units
    entry.m = (F.Number(entry.m) and entry.m or 0) + math.floor(money + 0.5)
    return true
end

---------------------------------------------------------------------------
-- Posting
---------------------------------------------------------------------------

local function ItemName(location, id)
    local api = _G.C_Item
    local name = F.Has(api, "GetItemName") and location and api.GetItemName(location) or nil
    if not F.String(name) and F.Has(api, "GetItemNameByID") and id then name = api.GetItemNameByID(id) end
    if not F.String(name) and id then name = F.ItemMeta(id).name end
    return F.String(name) and name or nil
end

-- The post as the game was asked for it. kind is "commodity" (PostCommodity(location, duration, quantity, unitPrice)) or
-- "item" (PostItem(location, duration, quantity, bid, buyout)). Returns true when it is waiting for confirmation.
function S.OnPost(kind, location, duration, quantity)
    if not (F.Integer(quantity, 1, MAX) and F.Integer(duration, 1, 100000)) then
        S.counts.dropped = S.counts.dropped + 1
        return false
    end
    local api, auction = _G.C_Item, _G.C_AuctionHouse
    local id = F.Has(api, "GetItemID") and location and api.GetItemID(location) or nil
    if not F.Integer(id, 1, MAX) then
        S.counts.dropped = S.counts.dropped + 1
        return false
    end
    local deposit
    if kind == "commodity" and F.Has(auction, "CalculateCommodityDeposit") then
        deposit = auction.CalculateCommodityDeposit(id, duration, quantity)
    elseif kind == "item" and F.Has(auction, "CalculateItemDeposit") then
        deposit = auction.CalculateItemDeposit(location, duration, quantity)
    end
    if not (F.Number(deposit) and deposit >= 0) then deposit = 0 end
    local name = ItemName(location, id)
    if not name then
        S.counts.dropped = S.counts.dropped + 1
        return false
    end
    S.counts.posts = S.counts.posts + 1
    S.pending[#S.pending + 1] = { name = name, id = id, units = quantity, deposit = math.floor(deposit), time = GetTime() }
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(CONFIRM_WAIT + 0.5, S.Expire) end
    return true
end

local function Commit(post)
    Add(post.name, post.id, { p = post.units, a = 1, d = post.deposit })
end

-- AUCTION_HOUSE_AUCTION_CREATED(auctionID): the oldest waiting post went through.
function S.OnCreated(auctionID)
    if F.db and not F.db.salesCreatedSeen then F.db.salesCreatedSeen = true end   -- the event exists and fires: no fallback needed any more
    local post = table.remove(S.pending, 1)
    if not post then return nil end
    S.counts.created = S.counts.created + 1
    Commit(post)
    return post
end

-- A post that failed (AUCTION_MULTISELL_FAILURE, an error from the house): nothing was charged.
function S.OnFailed(reason)
    local post = table.remove(S.pending, 1)
    if post then
        S.counts.dropped = S.counts.dropped + 1
    end
    return post
end

-- Posts still waiting after a few seconds: counted when the creation event has never been seen on this install (it may not
-- exist or may not fire), otherwise dropped (it did not go through).
function S.Expire()
    local now = GetTime()
    local keep = {}
    for _, post in ipairs(S.pending) do
        if now - post.time >= CONFIRM_WAIT then
            if F.db and not F.db.salesCreatedSeen then Commit(post)
            else S.counts.dropped = S.counts.dropped + 1 end
        else
            keep[#keep + 1] = post
        end
    end
    S.pending = keep
    if F.LuckUI and F.LuckUI.IsShown() then F.LuckUI.Refresh() end
end

---------------------------------------------------------------------------
-- The mail
---------------------------------------------------------------------------

-- "Auction expired: %s" -> a pattern that finds the name in a subject.
local function SubjectPattern(global)
    local text = _G[global]
    if not F.String(text) then return nil end
    return "^" .. text:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)") .. "$"
end

-- The item an "expired" or "canceled" mail is about, from its subject; nil for any other mail.
local function ReturnedName(subject)
    if not F.String(subject) then return nil end
    for _, global in ipairs({ "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT" }) do
        local pattern = SubjectPattern(global)
        local name = pattern and subject:match(pattern)
        if name then return name end
    end
    return nil
end

local function Header(index)
    if type(GetInboxHeaderInfo) ~= "function" then return nil end
    local _, _, sender, subject, money, _, _, itemCount = GetInboxHeaderInfo(index)   -- (icon, stationery, sender, subject, money, COD, daysLeft, itemCount, ...)
    return sender, subject, F.Number(money) and money or 0, itemCount
end

-- Called after a take call on mail `index` (TakeInboxMoney, TakeInboxItem, AutoLootMailItem): counts a sale whose money is being
-- taken, or an unsold auction whose item is. Returns "sold", "returned" or nil.
-- What an expired or canceled auction's mail holds: { name, id, units }. A returned auction of many units comes back as several
-- stacks, one per attachment slot. `slot` is one slot (TakeInboxItem takes one attachment at a time); nil is every slot (AutoLootMailItem).
-- If no slot can be read, the count the client puts in the subject, "(79)", is used.
local function ReturnedItems(index, slot, subject)
    local name, id, units = nil, nil, 0
    if type(GetInboxItem) == "function" then
        local first, last = slot or 1, slot or (F.Integer(_G.ATTACHMENTS_MAX_RECEIVE, 1, 50) and _G.ATTACHMENTS_MAX_RECEIVE or 16)
        for n = first, last do
            local itemName, itemID, _, count = GetInboxItem(index, n)
            if F.String(itemName) or F.Integer(itemID, 1, MAX) then
                if not name and F.String(itemName) then name = itemName end
                if not id and F.Integer(itemID, 1, MAX) then id = itemID end
                units = units + (F.Integer(count, 1, MAX) and count or 1)
            end
        end
    end
    if units == 0 then
        local shown = tonumber(subject:match("%((%d+)%)%s*$"))
        units = F.Integer(shown, 1, MAX) and shown or 1
    end
    return name, id, units
end

function S.OnTake(index, what, slot)
    if not F.Integer(index, 1, 100000) then return nil end
    local _, subject, money = Header(index)
    if not F.String(subject) then return nil end
    local key = index .. ":" .. subject .. ":" .. money   -- (not `what`: AutoLootMailItem and TakeInboxMoney can both be called for one mail)
    if what == "item" and F.Integer(slot, 1, 50) then key = key .. ":" .. slot end   -- (one call per attachment: each is its own take)
    if taken[key] then return nil end
    -- a sale: an invoice from the seller's side, with money in the mail
    if money > 0 and type(GetInboxInvoiceInfo) == "function" then
        local invoiceType, itemName, _, _, _, deposit, _, _, _, _, count = GetInboxInvoiceInfo(index)
        if invoiceType == "seller" and F.String(itemName) then
            local units = F.Integer(count, 1, MAX) and count or 1
            taken[key] = true
            Add(itemName, IdFor(itemName), { s = units, m = money })
            S.counts.sold = S.counts.sold + 1
            if F.LuckUI and F.LuckUI.IsShown() then F.LuckUI.Refresh() end
            return "sold"
        end
    end
    -- unsold: the item comes back
    local name = ReturnedName(subject)
    if name and (what == "item" or what == "all") and type(GetInboxItem) == "function" then
        local itemName, itemID, units = ReturnedItems(index, what == "item" and F.Integer(slot, 1, 50) and slot or nil, subject)
        taken[key] = true
        if F.String(itemName) then name = itemName else name = name:gsub("%s*%(%d+%)%s*$", "") end   -- (the subject's own name carries the count)
        Add(name, itemID, { e = units })
        S.counts.returned = S.counts.returned + 1
        if F.LuckUI and F.LuckUI.IsShown() then F.LuckUI.Refresh() end
        return "returned"
    end
    return nil
end

-- The inbox changed (a mail was taken or deleted): the same index may be a different mail now.
function S.OnInboxChanged()
    taken = {}
end

---------------------------------------------------------------------------
-- Totals (one row per item, for the luck window's AH sales tab)
---------------------------------------------------------------------------

-- { items = { { id (the name), name, out (item ID), c = listed, x = sold, o = unsold, d, m, net, waiting, partial } },
--   total = the same sums, recipes = how many items }
-- `keep(name, itemID)`, when given, says which items to list (the luck window's "Crafted" box); the others are only counted in `hidden`
-- and are left out of the totals too.
-- `costOf(name, itemID)`, when given, is the crafting cost of one unit in copper (Luck.UnitCosts) or nil: profit = net minus that
-- cost for each unit SOLD (a unit that came back unsold is still in the bags, its materials are not lost, its deposit is), so a
-- cancelled auction lowers profit by its deposit only, and profit each moves down with it. Without a cost an item's profit is its net.
function S.Aggregate(scope, keep, costOf)
    local out = { items = {}, recipes = 0, hidden = 0, total = { c = 0, a = 0, x = 0, o = 0, d = 0, m = 0, net = 0, waiting = 0, partial = false,
        profit = 0, crafting = 0, nocost = 0 } }
    local root = S.Root(scope)
    if not root then return out end
    local total = out.total
    for name, entry in pairs(root) do
        if type(entry) == "table" and F.String(name) and keep and not keep(name, F.Integer(entry.id, 1, MAX) and entry.id or nil) then
            out.hidden = out.hidden + 1
        elseif type(entry) == "table" and F.String(name) then
            local function N(key) return F.Number(entry[key]) and entry[key] >= 0 and entry[key] or 0 end
            if not F.Integer(entry.id, 1, MAX) then
                local found = ResolveID(name)
                if found then entry.id = found end   -- kept, so the icon is there next time without another search
            end
            -- o: units that came back and are not up again; r: units put up again after coming back (not in c a second time)
            local item = { id = name, name = name, prof = "auction", c = N("p"), a = N("a"), x = N("s"), o = math.max(0, N("e") - N("r")), r = N("r"),
                d = N("d"), m = N("m"), out = F.Integer(entry.id, 1, MAX) and entry.id or nil }
            item.net = item.m - item.d
            item.unitCost = costOf and costOf(name, item.out) or nil
            item.crafting = item.unitCost and math.floor(item.unitCost * item.x + 0.5) or 0   -- the materials of the units sold
            item.profit = item.net - item.crafting
            item.waiting = math.max(0, item.c - item.x - item.o)
            item.partial = item.x + item.o > item.c   -- units posted before this addon was watching: their deposit is not on record
            out.items[#out.items + 1] = item
            out.recipes = out.recipes + 1
            for _, key in ipairs({ "c", "a", "x", "o", "d", "m", "net", "waiting", "profit", "crafting" }) do total[key] = total[key] + item[key] end
            if item.x > 0 and not item.unitCost then total.nocost = total.nocost + 1 end
            if item.partial then total.partial = true end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------

local hooked = {}

local function Hook(owner, ownerName, name, fn)
    local key = ownerName .. "." .. name
    if hooked[key] then return true end
    if not (type(hooksecurefunc) == "function" and owner and type(owner[name]) == "function") then return false end
    hooksecurefunc(owner, name, fn)
    hooked[key] = true
    return true
end

-- Installs what can be installed; called at load and when the auction house or the mailbox opens (the API may appear later).
-- Returns how many of the five hooks are in place.
function S.Hook()
    local auction = _G.C_AuctionHouse
    Hook(auction, "C_AuctionHouse", "PostCommodity", function(location, duration, quantity) S.OnPost("commodity", location, duration, quantity) end)
    Hook(auction, "C_AuctionHouse", "PostItem", function(location, duration, quantity) S.OnPost("item", location, duration, quantity) end)
    Hook(_G, "_G", "TakeInboxMoney", function(index) S.OnTake(index, "money") end)
    Hook(_G, "_G", "TakeInboxItem", function(index, slot) S.OnTake(index, "item", slot) end)
    Hook(_G, "_G", "AutoLootMailItem", function(index) S.OnTake(index, "all") end)
    local n = 0
    for _ in pairs(hooked) do n = n + 1 end
    return n
end

function S.Hooked()
    local list = {}
    for key in pairs(hooked) do list[#list + 1] = key end
    table.sort(list)
    return list
end

-- A line for /dpp status.
function S.StatusText()
    local c = S.counts
    return string.format("AH sales: %d of 5 hook(s) installed; this session %d post(s) seen, %d counted as created, %d not counted, %d sale mail(s) and %d returned mail(s) read; the creation event %s.",
        #S.Hooked(), c.posts, c.created, c.dropped, c.sold, c.returned, (F.db and F.db.salesCreatedSeen) and "has been seen" or "not seen yet")
end
