-- Deffar Profession Profit: the luck counter. Counts every craft of a saved cooking recipe from the game's own
-- chat line ("You create: [Tender Wolf Steak]." or "You create: [Tender Wolf Steak]x2.") and records
-- whether Master Chef's extra result happened, split by Master Chef rank, for this session (memory only),
-- this character and the whole account.
--
-- An extra result is ONE more item than the recipe's normal quantity: for a recipe that makes 1 the line says
-- x2, and for one that makes 2 (Undermine Clam Chowder) it says x3, not x4 (FOR-0185). A quantity that is neither
-- the normal one nor one more is counted as "other" and kept out of the luck maths, so a wrong guess about how
-- extras look shows up as a number instead of skewing the result. A recipe whose quantity varies
-- (qMin ~= qMax) cannot be told apart, so it is not counted.
--
-- Saved shape (all optional, so the schema version stays 1):
--   F.db.luck[recipeID] and char.luck[recipeID] = { name, out = itemID, y = normal quantity,
--       ranks = { [masterChefRank] = { c = crafts, x = extra results, o = other quantities,
--           k = crafts that could be priced, u = crafts that could not, s = their material cost, g = the
--           vendor value of what they made, e = what the average craft at that rank would have made
--           (s, g and e are copper) } } }
-- Session stats have the same shape in L.session and are never saved.
--
-- Other professions: a craft of a saved Engineering recipe is counted the same way, filed under rank 0 with
-- entry.prof = "engineering" (absent = cooking, so older data is unchanged). Every craft is one craft (`c`) whatever
-- its quantity, there are no extras, and the money is the real quantity from the chat line x the vendor price.
--
-- Which chat event carries the line, and the exact global format strings, are unverified on Forever
-- (FOR-0179): both CHAT_MSG_LOOT and CHAT_MSG_TRADESKILLS are listened to, and the same text arriving
-- from the second event within half a second is ignored.
local _, F = ...
local L = {}
F.Luck = L

L.session = {}
L.seen = 0            -- chat lines that were a "You create:" line (any recipe)
L.perEvent = {}       -- event -> how many of those lines it delivered (a line sent by both events counts for each)
L.duplicates = 0      -- lines ignored because the other event had just delivered the same text
L.merged = 0          -- lines added into the craft before them (one craft, items in several stacks)
L.skipped = {}        -- reason -> count, for lines that were not counted
local MAX = 2147483647
local DUPLICATE_WINDOW = 0.5   -- seconds
local recent             -- { text, event, time } of the last counted line

L.SCOPES = { session = "This session", char = "This character", life = "Lifetime (all characters)" }

-- Is this saved recipe the one being cast right now (Core.lua sets F.craftNow on every profession's cast start;
-- F.cookingNow is the older cooking-only hint)?
local function Hinted(id)
    for _, hint in ipairs({ F.craftNow or false, F.cookingNow or false }) do
        if hint and hint.id == id and GetTime() - hint.time < 15 then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Reading the chat line
---------------------------------------------------------------------------

-- Fallbacks are the English strings of Blizzard's GlobalStrings LOOT_ITEM_CREATED_SELF(_MULTIPLE).
local FORMATS = { single = { "LOOT_ITEM_CREATED_SELF", "You create: %s." },
    multi = { "LOOT_ITEM_CREATED_SELF_MULTIPLE", "You create: %sx%d." } }
local patterns = {}

-- A Lua pattern from a format string: %s becomes a capture of anything, %d one of digits.
local function PatternFromFormat(format)
    if type(format) ~= "string" or format:find("%$", 1, true) then return nil end   -- positional formats: use English
    local escaped = format:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
    escaped = escaped:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. escaped .. "$"
end

local function Pattern(kind)
    local p = patterns[kind]
    if p then return p end
    local name, english = FORMATS[kind][1], FORMATS[kind][2]
    p = PatternFromFormat(rawget(_G, name)) or PatternFromFormat(english)
    -- a loot line is read with or without its closing full stop
    if p and kind:sub(1, 4) == "loot" then p = p:gsub("%%%.%$$", "%%.?$") end
    patterns[kind] = p
    return p
end

-- message -> itemID, quantity; nil when it is not a "You create:" line (or is not readable).
function L.Parse(message)
    if not F.String(message) then return nil end
    local link, quantity = message:match(Pattern("multi"))   -- first: the single pattern would also match this
    if link then
        quantity = tonumber(quantity)
    else
        link = message:match(Pattern("single"))
        quantity = 1
    end
    if not link or not quantity or quantity < 1 then return nil end
    local id = tonumber(link:match("|Hitem:(%d+)"))
    if not F.Integer(id, 1, MAX) then return nil end
    return id, quantity
end

---------------------------------------------------------------------------
-- Stores
---------------------------------------------------------------------------

-- The root table for a scope ("session", "char", "life"), or nil when there is none (no character yet).
function L.Root(scope)
    if scope == "session" then return L.session end
    if scope == "life" then
        if not F.db then return nil end
        if type(F.db.luck) ~= "table" then F.db.luck = {} end
        return F.db.luck
    end
    if scope == "char" then
        local char = F.Char()
        return char and char.luck or nil
    end
    return nil
end

-- Data saved before 2026-11-22 (rule 1) took an extra result for a recipe that makes N to be 2N items. For a
-- recipe that makes 2 or more the real extra is N + 1, so every proc was filed as "other" (`o`) and the average
-- value `e` assumed a second batch. This moves those crafts into `c` and `x` (an approximation: every old `o` is
-- taken to be a proc) and rescales `e`, which is exact because all priced crafts of a bucket share one rank:
-- e = sum(sell * N * (1 + p)) becomes sum(sell * (N + p)), a factor of (N + p) / (N * (1 + p)). Recipes that
-- make 1 are unchanged. Runs once per entry (entry.rule = 2); FOR-0185.
local function Migrate(entry)
    if type(entry) ~= "table" or entry.rule == 2 or type(entry.ranks) ~= "table" then return end
    entry.rule = 2
    local normal = F.Integer(entry.y, 1, MAX) and entry.y or 1
    if normal < 2 then return end
    for rank, b in pairs(entry.ranks) do
        if type(b) == "table" and F.Integer(rank, 0, F.RANK_MAX) then
            local o = F.Integer(b.o, 0, MAX) and b.o or 0
            b.c = (F.Integer(b.c, 0, MAX) and b.c or 0) + o
            b.x = (F.Integer(b.x, 0, MAX) and b.x or 0) + o
            b.o = 0
            if F.Number(b.e) and b.e > 0 then
                local p = F.Calc.Chance(rank)
                b.e = b.e * (normal + p) / (normal * (1 + p))
            end
        end
    end
end
L.Migrate = Migrate   -- (tests)

local function Entry(root, id, recipe, normal, prof)
    local entry = root[id]
    if type(entry) ~= "table" then entry = { rule = 2 }; root[id] = entry end   -- a new entry starts on the new rule
    Migrate(entry)
    entry.name, entry.out, entry.y = recipe.name, recipe.out, normal
    entry.prof = prof ~= "cooking" and prof or nil
    if type(entry.ranks) ~= "table" then entry.ranks = {} end
    return entry
end

-- Counters are whole numbers; the money fields are copper and may carry a fraction (expected gain).
local function Money(value) return F.Number(value) and value >= 0 and value or 0 end

local function Bucket(entry, rank)
    local b = entry.ranks[rank]
    if type(b) ~= "table" then b = {}; entry.ranks[rank] = b end
    for _, key in ipairs({ "c", "x", "o", "k", "u" }) do
        if not F.Integer(b[key], 0, MAX) then b[key] = 0 end
    end
    for _, key in ipairs({ "s", "g", "e" }) do b[key] = Money(b[key]) end
    return b
end

-- What one craft of the recipe costs in materials and what one of the food sells for to a vendor. A
-- material's price is the average the character really paid at the auction house when Bought.lua tracked
-- it, else the cheaper of the current auction and saved vendor price; a material already held is NOT
-- free here. Copper, or nil when any price is unknown.
function L.MaterialPrice(reagent)
    local best, source, units, bestID
    for _, id in ipairs(type(reagent.ids) == "table" and reagent.ids or {}) do
        local unit, from, count
        local paid = F.Bought.NextPrice(id)   -- the oldest purchase still unused (Bought.lua lots)
        if paid then unit, from, count = paid, "paid", F.Bought.LotUnits(id)
        else
            unit = F.UnitCost(id)
            from = "market"
        end
        if unit and (not best or unit < best) then best, source, units, bestID = unit, from, count, id end
    end
    return best, source, units, bestID
end

-- Uses the materials of one craft: each reagent from the oldest purchases first (Bought.Take), any units
-- no purchase covers (looted, gathered, bought before lots were kept) at the market price. Returns the copper the craft cost, or nil
-- when some unit has no price at all; and, always, what was used: { { id, units, copper, market = units priced at market } }.
-- The lots are used up even when the cost is unknown: the materials are gone.
local function CraftCost(recipe)
    if type(recipe.r) ~= "table" or #recipe.r == 0 then return nil, {} end
    local total, known, used = 0, true, {}
    for _, reagent in ipairs(recipe.r) do
        local _, _, _, id = L.MaterialPrice(reagent)
        if not id then id = type(reagent.ids) == "table" and reagent.ids[1] or nil end
        local qty = tonumber(reagent.qty) or 1
        if F.Integer(id, 1, MAX) then
            local copper, taken, left = F.Bought.Take(id, qty)
            local market = 0
            if left > 0 then
                local unit = F.UnitCost(id)
                if unit then copper = copper + left * unit; market = left else known = false end
            end
            total = total + copper
            used[#used + 1] = { id = id, units = qty, copper = copper, market = market }
        else
            known = false
        end
    end
    return known and total or nil, used
end

-- Adds one craft's materials to an entry's running totals: entry.mats[itemID] = { n = units used, c = copper they cost, m = of them at market }.
local function AddMaterials(entry, used)
    if type(entry.mats) ~= "table" then entry.mats = {} end
    for _, line in ipairs(used) do
        local m = entry.mats[line.id]
        if type(m) ~= "table" then m = { n = 0, c = 0, m = 0 }; entry.mats[line.id] = m end
        m.n, m.c, m.m = m.n + line.units, m.c + line.copper, m.m + line.market
    end
end

-- The rank to file a craft under: the real Master Chef rank, never the hand-set one used for what-ifs.
local function RankNow()
    local live = F.ReadRank()
    if live then return live end
    local char = F.Char()
    if char and type(char.rank) == "table" and F.Integer(char.rank.value, 0, F.RANK_MAX) then return char.rank.value end
    return nil
end

local function Skip(reason)
    L.skipped[reason] = (L.skipped[reason] or 0) + 1
    return nil, reason
end

-- Counts one craft of itemID that produced `quantity` items. Returns the recipe ID and what it was
-- ("normal", "extra" or "other"), or nil and why it was not counted.
function L.Record(itemID, quantity)
    local char = F.Char()
    if not char then return Skip("nocharacter") end
    -- Which saved recipe makes this item? If several do, the one being cast right now, else a cooking one before an
    -- engineering one, the lowest ID first.
    local hinted, best
    for _, key in ipairs(F.TABS) do
        for id, recipe in pairs(F.RecipesOf(char, key) or {}) do
            if type(recipe) == "table" and recipe.out == itemID then
                if Hinted(id) then
                    hinted = hinted or { id = id, prof = key, recipe = recipe }
                elseif not best or (best.prof == key and id < best.id) then
                    best = { id = id, prof = key, recipe = recipe }
                end
            end
        end
    end
    local pick = hinted or best
    if not pick then return Skip("norecipe") end
    local found, prof, recipe = pick.id, pick.prof, pick.recipe
    local proc = F.PROFESSIONS[prof].proc
    local normal, rank
    if proc then
        normal = F.Integer(recipe.qMin, 1, MAX) and recipe.qMin == recipe.qMax and recipe.qMin or nil
        if not normal then return Skip("variableyield") end
        rank = RankNow()
        if not rank then return Skip("norank") end
    else
        normal = F.Integer(recipe.qMin, 1, MAX) and recipe.qMin or 1
        rank = 0
    end

    local kind, field = "other", "o"
    if not proc or quantity == normal then kind, field = "normal", "c"
    elseif quantity == normal + 1 then kind, field = "extra", "c" end
    -- The money outcome counts every craft whatever its quantity: the cost of one craft, and what the
    -- items it really made sell for to a vendor, next to what the average craft at this rank would make.
    local cost, used = CraftCost(recipe)
    local sell = F.Integer(recipe.out, 1, MAX) and F.ItemMeta(recipe.out).sell or nil
    if not sell then cost = nil end                            -- (the vendor price is not loaded yet)
    if cost and not proc and sell == 0 then cost = nil end   -- nothing a vendor buys (a material such as powder): no money figures
    for _, scope in ipairs({ "session", "char", "life" }) do
        local root = L.Root(scope)
        if root then
            local entry = Entry(root, found, recipe, normal, prof)
            local b = Bucket(entry, rank)
            if kind == "other" then b.o = b.o + 1
            else
                b.c = b.c + 1
                if kind == "extra" then b.x = b.x + 1 end
            end
            if cost then
                AddMaterials(entry, used)
                b.k = b.k + 1
                b.s = b.s + cost
                b.g = b.g + quantity * sell
                b.e = b.e + (proc and sell * (normal + F.Calc.Chance(rank)) or quantity * sell)     -- the average craft: the normal quantity plus one with chance p
            else
                b.u = b.u + 1
            end
        end
    end
    L.last = { id = found, name = recipe.name, quantity = quantity, kind = kind, rank = rank, prof = prof, time = GetTime() }
    return found, kind
end

-- One craft can print SEVERAL "You create:" lines: when its items do not fit one stack the game prints one line
-- per stack they land in. Counting each
-- line as a craft counted that craft twice, as two normal crafts, and lost its extra result. Lines for the
-- same item that arrive within COALESCE seconds of the previous one are added into ONE craft, which is
-- recorded when no further line comes. A cast takes 3 s (FOR-0177), so two crafts are never that close.
-- FOR-0186.
local COALESCE = 0.6
local pending, scheduled, scheduledAt

local function Commit()
    local p = pending
    pending = nil
    if not p then return end
    local recipe = L.Record(p.id, p.quantity)
    if recipe then
        L.lastEvent = p.event
        if F.LuckUI and F.LuckUI.IsShown() then F.LuckUI.Refresh() end
    end
end

local function Tick()
    scheduled = false
    if not pending then return end
    -- A line that came in after this timer was set may still be followed by another: record the craft once the
    -- lines have been quiet for the whole window, waiting only for the rest of it.
    local quiet = GetTime() - pending.last
    if pending.last > scheduledAt and quiet < COALESCE then
        scheduled, scheduledAt = true, GetTime()
        C_Timer.After(COALESCE - quiet, Tick)
    else
        Commit()
    end
end

-- Adds one parsed line to the craft in progress (starting it, or recording the previous one first).
-- Without a timer every line is its own craft. Returns the recipe ID and kind only in that case.
function L.Add(id, quantity, event)
    local now = GetTime()
    if pending and (pending.id ~= id or now - pending.last > COALESCE) then Commit() end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        local recipe, kind = L.Record(id, quantity)
        if recipe then L.lastEvent = event end
        return recipe, kind
    end
    if pending then
        pending.quantity = pending.quantity + quantity
        pending.last = now
        L.merged = L.merged + 1
    else
        pending = { id = id, quantity = quantity, last = now, event = event }
    end
    if not scheduled then
        scheduled, scheduledAt = true, now
        C_Timer.After(COALESCE, Tick)
    end
    return true, "queued"
end

-- A chat line from `event`: counts it when it is a "You create:" line for a saved recipe (merged with the other
-- lines of the same craft, see above). Returns the recipe ID and kind when it was recorded at once (no timer),
-- or true when it was queued.
function L.Handle(event, text)
    local id, quantity = L.Parse(text)
    if not id then return nil end
    L.seen = L.seen + 1
    L.perEvent[event] = (L.perEvent[event] or 0) + 1
    local now = GetTime()
    if recent and recent.text == text and recent.event ~= event and now - recent.time < DUPLICATE_WINDOW then
        L.duplicates = L.duplicates + 1
        return nil, "duplicate"   -- the same line from the other chat event
    end
    recent = { text = text, event = event, time = now }
    return L.Add(id, quantity, event)
end

-- Marks a recipe (its luck entry key) as sold at the auction house, or clears it. Returns whether it is marked now.
function L.ToggleAH(id)
    if not (F.db and F.Integer(id, 1, MAX)) then return false end
    if type(F.db.luckAH) ~= "table" then F.db.luckAH = {} end
    local on = F.db.luckAH[id] ~= true
    F.db.luckAH[id] = on or nil
    return on
end

-- Which items this player has crafted (the luck counter has seen it made): a function (item name, item ID) -> true or false, for the
-- AH sales tab's "Crafted" box.
-- From every saved luck entry of this character and the account, a recipe's name and the name and ID of what it makes; a
-- disenchant entry is not a craft. An item crafted before the luck counter existed is not known.
function L.CraftedFilter()
    local names, ids = {}, {}
    for _, scope in ipairs({ "session", "char", "life" }) do
        for _, entry in pairs(L.Root(scope) or {}) do
            if type(entry) == "table" and entry.prof ~= "enchanting" then
                if F.String(entry.name) then names[entry.name] = true end
                if F.Integer(entry.out, 1, MAX) then
                    ids[entry.out] = true
                    local made = F.ItemMeta(entry.out).name
                    if F.String(made) then names[made] = true end
                end
            end
        end
    end
    return function(name, id) return names[name] == true or (id ~= nil and ids[id] == true) end
end

-- What one unit of an item cost to craft, from the crafts the luck counter has priced (the money it recorded when each was made:
-- "the crafting cost that we spent in the moment"): a function (item name, item ID) -> copper per unit, or nil when this item was
-- never crafted and priced. Averaged over every saved craft of the account (a recipe that several craft the same item pools them):
-- the materials spent divided by the units those crafts made, the normal quantity and the extra results together.
function L.UnitCosts()
    local byName, byId = {}, {}
    local function Put(map, key, spent, units)
        if key == nil then return end
        local e = map[key]
        if not e then e = { s = 0, u = 0 }; map[key] = e end
        e.s, e.u = e.s + spent, e.u + units
    end
    for _, entry in pairs(L.Root("life") or {}) do
        if type(entry) == "table" and entry.prof ~= "enchanting" and type(entry.ranks) == "table" then
            local y = F.Integer(entry.y, 1, MAX) and entry.y or 1
            local spent, units = 0, 0
            for _, b in pairs(entry.ranks) do
                if type(b) == "table" and F.Number(b.k) and b.k > 0 and F.Number(b.c) and b.c > 0 and F.Number(b.s) then
                    spent = spent + b.s
                    units = units + b.k * (y + (F.Number(b.x) and b.x or 0) / b.c)   -- units per craft: y, plus the extra results' share
                end
            end
            if units > 0 then
                Put(byName, entry.name, spent, units)
                if F.Integer(entry.out, 1, MAX) then
                    Put(byId, entry.out, spent, units)
                    Put(byName, F.ItemMeta(entry.out).name, spent, units)
                end
            end
        end
    end
    return function(name, id)
        local e = (id and byId[id]) or byName[name]
        if e and e.u > 0 then return e.s / e.u end
        return nil
    end
end

function L.ResetSession()
    L.session = {}
    L.last = nil
    if L.ClearDisenchant then L.ClearDisenchant() end   -- (defined with the disenchant code below)
end

---------------------------------------------------------------------------
-- Totals
---------------------------------------------------------------------------

-- Adds up a scope for one recipe (filterID) or all, of one profession (`prof`, default cooking). Returns
-- { items = { one per recipe, most crafts first: { id, name, out, y, c, x, o, expected, z, sd, worth,
--       s, g, e, k, u, ranks = { [rank] = { c, x, o, stats = Calc.LuckStats } } } },
--   ranks = the same per-rank sums over every item, total = { c, x, o, expected, variance, z, sd, s, g, e, k, u },
--   recipes = how many recipes, worth = copper the extras are worth above or below the average
--   (vendor price of the food), worthKnown = false when a sell price was not loaded yet }
-- Money, all copper: s = material cost of the priced crafts (prices when cooked), g = vendor value of the
-- items those crafts made, e = what the average craft at that rank would have made, k = priced crafts,
-- u = crafts that could not be priced (a price was unknown), so s, g and e leave them out; secs = the casting time of
-- the k priced crafts in seconds (sec = seconds per craft, secFrom = where it came from).
function L.Aggregate(scope, filterID, prof)
    prof = prof or "cooking"
    local root = L.Root(scope)
    local out = { items = {}, ranks = {}, recipes = 0, worth = 0, worthKnown = true,
        total = { c = 0, x = 0, o = 0, expected = 0, variance = 0, s = 0, g = 0, e = 0, k = 0, u = 0, secs = 0 },
        -- the items marked as sold at the auction house, added up on their own at today's AH prices (count = how many are marked,
        -- unpriced = those Auctionator has no price for: their crafts count, their money does not)
        ahTotal = { c = 0, x = 0, o = 0, expected = 0, variance = 0, s = 0, g = 0, k = 0, u = 0, secs = 0, count = 0, unpriced = 0 } }
    if not root then return out end
    local C, total = F.Calc, out.total
    for id, entry in pairs(root) do
        if type(entry) == "table" and type(entry.ranks) == "table" and (not filterID or id == filterID)
            and (entry.prof or "cooking") == prof then
            Migrate(entry)
            local item = { id = id, prof = prof, name = F.String(entry.name) and entry.name or ("Recipe " .. tostring(id)),
                out = F.Integer(entry.out, 1, MAX) and entry.out or nil,
                y = F.Integer(entry.y, 1, MAX) and entry.y or 1,
                res = type(entry.res) == "table" and entry.res or nil,   -- disenchants: what came out, itemID -> quantity
                c = 0, x = 0, o = 0, expected = 0, variance = 0, worth = 0, s = 0, g = 0, e = 0, k = 0, u = 0, ranks = {},
                mats = type(entry.mats) == "table" and entry.mats or nil }   -- (what the crafts used: Bought lots, see AddMaterials)
            local sell = item.out and F.ItemMeta(item.out).sell or nil
            for rank, b in pairs(entry.ranks) do
                if F.Integer(rank, 0, F.RANK_MAX) and type(b) == "table" then
                    local c = F.Integer(b.c, 0, MAX) and b.c or 0
                    local x = F.Integer(b.x, 0, MAX) and b.x or 0
                    local o = F.Integer(b.o, 0, MAX) and b.o or 0
                    if c + o > 0 then
                        local p = C.Chance(rank)
                        item.ranks[rank] = { c = c, x = x, o = o }
                        item.c, item.x, item.o = item.c + c, item.x + x, item.o + o
                        item.expected = item.expected + c * p
                        item.variance = item.variance + c * p * (1 - p)
                        local k = F.Integer(b.k, 0, MAX) and b.k or 0
                        local u = F.Integer(b.u, 0, MAX) and b.u or 0
                        item.k, item.u = item.k + k, item.u + u
                        item.s, item.g, item.e = item.s + Money(b.s), item.g + Money(b.g), item.e + Money(b.e)
                        if sell then item.worth = item.worth + (x - c * p) * sell else out.worthKnown = false end   -- an extra is one item
                        local r = out.ranks[rank] or { c = 0, x = 0, o = 0 }
                        r.c, r.x, r.o = r.c + c, r.x + x, r.o + o
                        out.ranks[rank] = r
                    end
                end
            end
            if item.c + item.o > 0 then
                local luck = C.LuckTotal(item.x, item.expected, item.variance)
                item.z, item.sd = luck.z, luck.sd
                for rank, r in pairs(item.ranks) do r.stats = C.LuckStats(r.c, r.x, rank) end
                out.items[#out.items + 1] = item
                out.recipes = out.recipes + 1
                out.worth = out.worth + item.worth
                -- An item the player sells at the auction house (L.ToggleAH) is not in the main total (the "Vendor" row): all of it, its crafts, extras and
                -- luck as well as its money, moves to out.ahTotal below, which values it at AH prices.
                item.ah = prof ~= "enchanting" and F.db ~= nil and type(F.db.luckAH) == "table" and F.db.luckAH[id] == true
                if not item.ah then
                    for _, key in ipairs({ "c", "x", "o", "expected", "variance", "s", "g", "e", "k", "u" }) do
                        total[key] = total[key] + item[key]
                    end
                end
                -- Casting time of the priced crafts (the ones the money figures cover): seconds per craft (the
                -- measured cast, else the game's, else 3 s: Data.lua F.CraftSeconds) x those crafts, for the per-hour
                -- profit. A recipe ID is its spell ID (FOR-0177). Buying and selling time are not counted.
                item.sec, item.secFrom = F.CraftSeconds(id)
                item.secs = item.k * item.sec
                if not item.ah then total.secs = total.secs + item.secs end
                if item.ah then
                    -- Its money at the auction house is what the AH sales ledger of the same scope recorded for the units SOLD (Sales.Recorded):
                    -- Gained = money received less deposits paid (m - d), never today's price. Spent = the materials of those units, at the average
                    -- unit cost of this item's priced crafts (item.s over the units they made). Casting time = those units' share of the crafts.
                    -- Crafts not sold (yet) are not counted. Nothing sold on record: no ahView (the cells say so).
                    local at = out.ahTotal
                    for _, key in ipairs({ "c", "x", "o", "expected", "variance" }) do at[key] = at[key] + item[key] end
                    at.count = at.count + 1
                    local names = {}
                    if F.String(entry.name) then names[entry.name] = true end
                    local made = item.out and F.ItemMeta(item.out).name or nil
                    if F.String(made) then names[made] = true end
                    local rec = F.Sales and F.Sales.Recorded(scope, item.out, names) or nil
                    if rec then
                        local perCraft = item.c > 0 and (item.y + item.x / item.c) or item.y   -- units one craft makes, extras included
                        local spent, unpriced = 0, item.c
                        if item.k > 0 and item.c > 0 then
                            spent = math.floor(item.s / (item.k * perCraft) * rec.sold + 0.5)   -- the average cost of one unit, times the units sold
                            unpriced = item.u
                        end
                        item.ahView = { s = spent, g = rec.net, k = rec.sold, u = unpriced, secs = rec.sold / perCraft * item.sec, sold = rec.sold,
                            received = rec.m, deposits = rec.d, partial = rec.partial, recorded = true }
                        at.s, at.g, at.k, at.u, at.secs = at.s + spent, at.g + rec.net, at.k + rec.sold, at.u + unpriced, at.secs + item.ahView.secs
                    else
                        at.unpriced = at.unpriced + 1
                    end
                end
            end
        end
    end
    table.sort(out.items, function(a, b)
        if a.c + a.o ~= b.c + b.o then return a.c + a.o > b.c + b.o end
        return a.name < b.name
    end)
    for rank, r in pairs(out.ranks) do r.stats = C.LuckStats(r.c, r.x, rank) end
    local luck = C.LuckTotal(total.x, total.expected, total.variance)
    total.z, total.sd = luck.z, luck.sd
    local ahLuck = C.LuckTotal(out.ahTotal.x, out.ahTotal.expected, out.ahTotal.variance)
    out.ahTotal.z, out.ahTotal.sd = ahLuck.z, ahLuck.sd
    return out
end

---------------------------------------------------------------------------
-- Disenchanting (FOR-0192). Counted from three things the game sends, all HYPOTHESES on Forever until seen (FOR-0192;
-- `/dpp status` shows how many of each were seen):
--   * UNIT_SPELLCAST_SENT for the Disenchant spell (13262, the classic ID): its second argument names the target item,
--     which is found in the bags to get its item ID. Two pieces of one item with different suffixes share the item ID, so
--     they are one row, named by the item's own name without the suffix (F.ItemMeta).
--   * UNIT_SPELLCAST_SUCCEEDED for the same spell: one disenchant.
--   * the "You receive loot:" lines that follow (within 30 s) for Enchanting materials (item class 7, subclass 12): what
--     it gave, worth the Auctionator price less the auction house's cut. Nothing is "spent": what the item cost is not known.
-- Saved like a craft: entry key L.DE_BASE + itemID, entry.prof = "enchanting", rank 0, c = disenchants, k = those priced,
-- u = those with an unpriced result, g = gained (copper), entry.res = { [itemID] = quantity received }.
---------------------------------------------------------------------------

L.DE_BASE = 1000000000
L.DISENCHANT_SPELL = 13262
-- what was seen, for /dpp status: casts of the spell, items found by name / by what left the bags, loot lines seen while a
-- disenchant was being counted, Enchanting materials among them, those that arrived before the cast finished
L.de = { casts = 0, byName = 0, byBags = 0, missing = 0, lines = 0, attributed = 0, early = 0, done = 0, noTarget = 0, counted = 0 }
local deTarget   -- { id = itemID or nil, before = bag snapshot, time } of the cast in progress
local pending    -- { id, time, before, counted, unpriced } the disenchant whose loot is being counted
local early = {} -- Enchanting materials looted just before the cast was seen to finish: { id, quantity, time }
local lastBags, recentGone   -- last bag snapshot; the weapon or armour piece that left the bags lately: { id, time }
local lastSentAt              -- when the last Disenchant cast was sent (the bags changing just after it are that cast's)

FORMATS.lootSingle = { "LOOT_ITEM_SELF", "You receive loot: %s." }
FORMATS.lootMulti = { "LOOT_ITEM_SELF_MULTIPLE", "You receive loot: %sx%d." }

local function ParseLoot(message)
    if not F.String(message) then return nil end
    local link, quantity = message:match(Pattern("lootMulti"))
    if link then quantity = tonumber(quantity)
    else link = message:match(Pattern("lootSingle")); quantity = 1 end
    if not link or not quantity or quantity < 1 then return nil end
    local id = tonumber(link:match("|Hitem:(%d+)"))
    if not F.Integer(id, 1, MAX) then return nil end
    return id, quantity
end
L.ParseLoot = ParseLoot

-- The Disenchant spell: its classic ID, or any spell with its name (the ID is a HYPOTHESIS on Forever, FOR-0192).
function L.IsDisenchant(spellID)
    if spellID == L.DISENCHANT_SPELL then return true end
    if not (F.Has(C_Spell, "GetSpellName") and F.Integer(spellID, 1, MAX)) then return false end
    local name = C_Spell.GetSpellName(spellID)
    if not F.String(name) or name == "" then return false end
    local known = C_Spell.GetSpellName(L.DISENCHANT_SPELL)
    return name == known or name:lower() == "disenchant"
end

-- Every bag slot's item: { ["bag:slot"] = { id, count, name } }.
local function Snapshot()
    local api = _G.C_Container
    local out = {}
    if not (F.Has(api, "GetContainerNumSlots") and F.Has(api, "GetContainerItemInfo")) then return out end
    for bag = 0, (tonumber(_G.NUM_BAG_SLOTS) or 4) + 1 do
        local slots = api.GetContainerNumSlots(bag)
        if F.Integer(slots, 0, 500) then
            for slot = 1, slots do
                local info = api.GetContainerItemInfo(bag, slot)
                if F.Table(info) and F.Integer(info.itemID, 1, MAX) then
                    out[bag .. ":" .. slot] = { id = info.itemID, count = F.Integer(info.stackCount, 1, MAX) and info.stackCount or 1,
                        name = F.String(info.hyperlink) and info.hyperlink:match("%[(.-)%]") or nil }
                end
            end
        end
    end
    return out
end

local function IsGear(id)
    if not F.Has(C_Item, "GetItemInfoInstant") then return false end
    local class = select(6, C_Item.GetItemInfoInstant(id))
    return class == 2 or class == 4
end

-- The item ID of the bag item named `name` (the cast's target text), nil when none is found.
local function FindByName(snapshot, name)
    for _, item in pairs(snapshot) do
        if item.name == name then return item.id end
    end
    return nil
end

-- Items held per item ID: { [itemID] = total count } of a snapshot.
local function Totals(snapshot)
    local totals = {}
    for _, item in pairs(snapshot) do totals[item.id] = (totals[item.id] or 0) + item.count end
    return totals
end

-- The weapon or armour piece the bags no longer hold: the one that was disenchanted, when the cast's target text did not name it
-- (on Forever it never does: UNIT_SPELLCAST_SENT's target is nil for Disenchant, FOR-0192). Compared by how many of each item
-- are held, not by slot, so items moving between slots do not matter. nil when none (or more than one kind) left.
local function FindByRemoval(before)
    local was, now = Totals(before), Totals(Snapshot())
    local gone, found = nil, 0
    for id, count in pairs(was) do
        if (now[id] or 0) < count and IsGear(id) then gone, found = id, found + 1 end
    end
    if found > 1 then L.de.ambiguous = (L.de.ambiguous or 0) + 1 end
    if found == 1 then return gone end
    return nil
end

local function DisenchantRoots()
    local list = {}
    for _, scope in ipairs({ "session", "char", "life" }) do
        local root = L.Root(scope)
        if root then list[#list + 1] = root end
    end
    return list
end

local function DisenchantEntry(root, itemID)
    local key = L.DE_BASE + itemID
    local entry = root[key]
    if type(entry) ~= "table" then entry = { rule = 2 }; root[key] = entry end
    local name = F.ItemMeta(itemID).name
    if name then entry.name = name elseif not entry.name then entry.name = "Item " .. itemID end
    entry.out, entry.y, entry.prof = itemID, 1, "enchanting"
    if type(entry.ranks) ~= "table" then entry.ranks = {} end
    if type(entry.res) ~= "table" then entry.res = {} end
    return entry
end

-- A disenchant in progress is forgotten (the session was reset).
function L.ClearDisenchant()
    deTarget, pending, early, recentGone, lastSentAt = nil, nil, {}, nil, nil
end

local Settle   -- (defined below, with the counting it uses)

-- BAG_UPDATE_DELAYED: a safety net for a Disenchant cast whose events were missed (the second of two in a row was not counted):
-- notes the one weapon or armour piece that left the bags with no Disenchant cast sent in the 8 s before, so Enchanting materials
-- looted within 10 s can be put to it.
function L.BagsChanged()
    local now = Snapshot()
    local seen = lastSentAt and GetTime() - lastSentAt < 8   -- a Disenchant cast was just seen: the cast events handle this piece
    if lastBags and not seen then
        local gone, found = nil, 0
        for key, item in pairs(lastBags) do
            local at = now[key]
            if (not at or at.id ~= item.id or at.count < item.count) and IsGear(item.id) then
                if gone ~= item.id then found = found + 1 end
                gone = item.id
            end
        end
        if found == 1 then recentGone = { id = gone, time = GetTime() } end
    end
    lastBags = now
    -- a disenchant waiting for its item to leave the bags: it may have now
    if pending and not pending.id and Settle(pending) then return true end
    return false
end

-- UNIT_SPELLCAST_SENT of the Disenchant spell: remembers the bags, and which item it names when the text matches one.
function L.DisenchantSent(target)
    L.de.casts = L.de.casts + 1
    lastSentAt = GetTime()
    pending, early = nil, {}   -- the previous disenchant's loot is over: a new cast starts
    local before = Snapshot()
    local id = F.String(target) and FindByName(before, target) or nil
    if id then L.de.byName = L.de.byName + 1 end
    deTarget = { id = id, before = before, time = GetTime() }
end

-- One disenchant of `id` counted.
local function Count(p)
    p.counted = true
    L.de.counted = L.de.counted + 1
    -- What the item cost is not known; its Auctionator price now (the lowest buyout last seen) stands for it. With no price the disenchant has no money figures.
    -- (what the character really paid, when purchases of it were tracked, Bought.lua; else Auctionator's price)
    local paid = F.Bought and F.Bought.Average(p.id)
    local price = paid or F.AuctionPrice(p.id)
    p.spent = price
    if not price then p.unpriced = true end
    for _, root in ipairs(DisenchantRoots()) do
        local bucket = Bucket(DisenchantEntry(root, p.id), 0)
        bucket.c = bucket.c + 1
        if price then bucket.k, bucket.s = bucket.k + 1, bucket.s + price else bucket.u = bucket.u + 1 end
    end
end

-- The item of a disenchant, found from what left the bags when the text did not name it (the bag may update a moment after the cast
-- finishes, so this is tried again with each loot line). True when it is known.
local function Resolve(p)
    if p.id then return true end
    p.id = p.before and FindByRemoval(p.before) or nil
    if p.id then L.de.byBags = L.de.byBags + 1 end
    return p.id ~= nil
end

-- One Enchanting material received for the disenchant `p`: the quantity into what it gave, worth the Auctionator price less the cut.
local function Attribute(p, id, quantity)
    L.de.attributed = L.de.attributed + 1
    local price = F.AuctionPrice(id)
    local value = price and math.floor(quantity * price * (1 - F.AH_CUT)) or nil
    for _, root in ipairs(DisenchantRoots()) do
        local entry = DisenchantEntry(root, p.id)
        local bucket = Bucket(entry, 0)
        entry.res[id] = (F.Integer(entry.res[id], 0, MAX) and entry.res[id] or 0) + quantity
        if not p.unpriced then
            if value then
                bucket.g = bucket.g + value
            else   -- a result with no price: this disenchant leaves the money figures, what it had added so far with it
                bucket.k, bucket.u = math.max(0, bucket.k - 1), bucket.u + 1
                bucket.s = math.max(0, bucket.s - (p.spent or 0))
                bucket.g = math.max(0, bucket.g - (p.gained or 0))
            end
        end
    end
    if not p.unpriced then
        if value then p.gained = (p.gained or 0) + value else p.unpriced = true end
    end
end

-- The item of a disenchant is found and its held loot lines are counted. The game takes a disenchanted item out of the bags a
-- moment AFTER its loot is taken, so
-- the loot lines wait here until the bags show it gone, instead of being thrown away. True when settled.
function Settle(p)
    if not Resolve(p) then return false end
    if not p.counted then Count(p) end
    local lines = p.lines
    p.lines = nil
    for _, line in ipairs(lines or {}) do
        Attribute(p, line.id, line.quantity)
        L.de.late = (L.de.late or 0) + 1
    end
    return true
end

-- Looks again a few times at half-second steps in case no bag event comes.
local function Retry(p, attempt)
    if not (type(C_Timer) == "table" and type(C_Timer.After) == "function") then return end
    C_Timer.After(0.6, function()
        if p ~= pending or p.id then return end   -- another disenchant has begun, or it was found meanwhile
        if Settle(p) then
            if F.LuckUI and F.LuckUI.IsShown() then F.LuckUI.Refresh() end
        elseif attempt < 10 then
            Retry(p, attempt + 1)
        end
    end)
end

-- UNIT_SPELLCAST_SUCCEEDED of the Disenchant spell. True when a disenchant is now being counted (its item is known at once, or
-- is found from the bags with its first loot line).
function L.DisenchantDone()
    local target = deTarget
    deTarget = nil
    L.de.done = L.de.done + 1
    if not target then L.de.noTarget = L.de.noTarget + 1; return false end   -- a cast finished that no SENT was seen for
    pending = { id = target.id, before = target.before, time = GetTime() }
    if Resolve(pending) then Count(pending) else Retry(pending, 1) end
    -- loot lines that arrived before the cast was seen to finish
    local now = GetTime()
    for _, line in ipairs(early) do
        if now - line.time < 5 and Resolve(pending) then
            if not pending.counted then Count(pending) end
            Attribute(pending, line.id, line.quantity)
            L.de.early = L.de.early + 1
        end
    end
    early = {}
    return pending.counted
end

-- A "You receive loot:" line: an Enchanting material (trade goods, enchanting: dust, essence, shard, crystal) within 30 s of a
-- disenchant is counted into it. True when it was counted.
function L.HandleLoot(text)
    local id, quantity = ParseLoot(text)
    if not id or not F.Has(C_Item, "GetItemInfoInstant") then
        return false
    end
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(id)
    if class ~= 7 or subclass ~= 12 then return false end
    local now = GetTime()
    if recentGone and now - recentGone.time < 10 and not (pending and pending.time >= recentGone.time) then
        pending = { id = recentGone.id, time = now }   -- a piece left the bags with no cast seen for it (a missed event): it was disenchanted
        recentGone = nil
        L.de.fromBags = (L.de.fromBags or 0) + 1
        Count(pending)
    end
    if not (pending and now - pending.time <= 30) then
        pending = nil
        if deTarget then   -- the cast is still in progress, or its end was not seen: keep the line for it
            early[#early + 1] = { id = id, quantity = quantity, time = now }
            if #early > 20 then table.remove(early, 1) end
        end
        return false
    end
    L.de.lines = L.de.lines + 1
    if not Resolve(pending) then
        -- the bags still hold the item: keep the line until they show it gone (BagsChanged, or the retries)
        pending.lines = pending.lines or {}
        pending.lines[#pending.lines + 1] = { id = id, quantity = quantity }
        if not pending.retrying then pending.retrying = true; Retry(pending, 1) end
        return false
    end
    if not pending.counted then Count(pending) end
    Attribute(pending, id, quantity)
    return true
end
