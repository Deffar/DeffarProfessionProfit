-- Deffar Profession Profit: the arithmetic. Pure functions only: no game calls, no frames, no saved data,
-- so a test can load this file alone. Prices come in through the `env` table Data.lua builds.
--
-- Master Chef (Forever legacy Professions tree, FOR-0174): each rank, 0-5, gives a 10% chance that
-- a cook "creates an extra result". The extra result is ONE
-- more item, whatever the recipe makes (FOR-0185). One craft yields `yield` items, plus one more with probability p:
--     expected output  = yield + p
--     expected profit  = sell * (yield + p) - material cost
-- For a recipe that makes 1 this is the same as the earlier yield * (1 + p).
local _, F = ...
local C = {}
F.Calc = C

C.MAX_RANK = 5
C.PER_RANK = 10          -- percent per rank
C.Z90 = 1.645            -- half-width of the central 90% of a normal distribution, in standard deviations

local function IsNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Rank (anything) -> chance 0..0.5 and the clamped whole rank.
function C.Chance(rank)
    if not IsNumber(rank) then return 0, 0 end
    rank = math.floor(rank)
    if rank < 0 then rank = 0 elseif rank > C.MAX_RANK then rank = C.MAX_RANK end
    return rank * C.PER_RANK / 100, rank
end

-- Standard normal cumulative distribution (Abramowitz and Stegun 7.1.26, error under 1.5e-7).
function C.Phi(z)
    if not IsNumber(z) then return nil end
    local x = math.abs(z) / math.sqrt(2)
    local t = 1 / (1 + 0.3275911 * x)
    local poly = ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t
    local erf = 1 - poly * math.exp(-x * x)
    if z < 0 then erf = -erf end
    return 0.5 * (1 + erf)
end

-- recipe = { out = itemID, qMin, qMax, r = { { qty = n, ids = { itemID, ... } }, ... } }
--   (ids lists alternatives for one reagent slot; the cheapest known one is used)
-- rank = Master Chef rank (clamped to 0-5)
-- env.unitCost(itemID) -> copper per unit or nil (unknown)
-- env.owned(itemID)    -> how many the character holds
-- env.sell(itemID)     -> vendor sell price of one item: nil (not loaded yet), 0 (cannot be sold), copper
-- env.seconds(recipe)  -> seconds one craft takes (optional; without it there is no per-hour figure)
-- opts.ownedFree       -> true: a reagent the character already holds enough of costs nothing
-- Returns a table; `status` is "ok", "noprice" (a material has no known price), "nosell" (the food
-- cannot be sold to a vendor) or "loading" (its sell price is not known yet). `profit` is only set
-- when status is "ok".
function C.Evaluate(recipe, rank, env, opts)
    local chance, whole = C.Chance(rank)
    local out = { rank = whole, chance = chance, reagents = {}, missing = 0, cost = 0 }

    local qMin = tonumber(recipe.qMin) or 1
    local qMax = tonumber(recipe.qMax) or qMin
    if not IsNumber(qMin) or qMin < 1 then qMin = 1 end
    if not IsNumber(qMax) or qMax < qMin then qMax = qMin end
    out.yield = (qMin + qMax) / 2

    for _, reagent in ipairs(recipe.r or {}) do
        local qty = tonumber(reagent.qty) or 1
        local line = { qty = qty, ids = reagent.ids }
        local ids = reagent.ids or {}
        line.id = ids[1]
        if opts and opts.ownedFree then
            for _, id in ipairs(ids) do
                if (env.owned(id) or 0) >= qty then
                    line.id, line.free = id, true
                    break
                end
            end
        end
        if not line.free then
            local best
            for _, id in ipairs(ids) do
                local unit = env.unitCost(id)
                if unit and (not best or unit < best) then best, line.id = unit, id end
            end
            if best then
                line.unit, line.total = best, best * qty
                out.cost = out.cost + line.total
            else
                out.missing = out.missing + 1
            end
        else
            line.unit, line.total = 0, 0
        end
        out.reagents[#out.reagents + 1] = line
    end
    out.complete = out.missing == 0 and #out.reagents > 0

    local sell = env.sell(recipe.out)
    out.sellEach = sell
    if sell == nil then
        out.status = "loading"
    elseif sell <= 0 then
        out.status = "nosell"
    elseif not out.complete then
        out.status = "noprice"
        out.value = sell * out.yield
    else
        out.status = "ok"
    end

    if out.status == "ok" then
        out.value = sell * out.yield                       -- what one craft sells for with no extra result
        out.expected = out.value + sell * chance           -- the average over many crafts: a proc adds one item
        out.baseProfit = out.value - out.cost
        out.profit = out.expected - out.cost
        out.margin = out.cost > 0 and out.profit / out.cost or nil
        out.needRank = -1                                  -- -1: not profitable even at rank 5
        for r = 0, C.MAX_RANK do
            if out.value + sell * (r * C.PER_RANK / 100) - out.cost >= 0 then out.needRank = r; break end
        end
        -- Highest unit price for each bought material at which the average profit is still 0, with every
        -- other material left at today's price: (expected - the other materials) / quantity, rounded
        -- down so paying exactly that is still not a loss. Can be 0 or negative: the other materials
        -- alone already cost more than the food is worth.
        for _, line in ipairs(out.reagents) do
            if line.unit and not line.free and line.qty > 0 then
                line.maxUnit = math.floor((out.expected - (out.cost - line.total)) / line.qty)
            end
        end
        -- Per hour: crafting back to back with the materials to hand, so it is a ceiling that ignores
        -- buying the materials and selling the food.
        local seconds = env.seconds and env.seconds(recipe)
        if IsNumber(seconds) and seconds > 0 then
            out.seconds = seconds
            out.perHour = out.profit * 3600 / seconds
            out.craftsPerHour = 3600 / seconds
        end
    end
    return out
end

-- The inverse of Phi: the z with Phi(z) = q, by bisection. nil unless 0 < q < 1.
function C.NormalInverse(q)
    if not IsNumber(q) or q <= 0 or q >= 1 then return nil end
    local lo, hi = -10, 10
    for _ = 1, 80 do
        local mid = (lo + hi) / 2
        if C.Phi(mid) < q then lo = mid else hi = mid end
    end
    return (lo + hi) / 2
end

-- What to buy at the auction house for `crafts` crafts of an evaluated recipe, and the highest price per
-- unit to pay, so that the chance of finishing at or above break-even is at least `odds`, inside a budget.
--   opts.odds    chance of finishing ahead, 0.5-0.99 (the normal approximation used by C.Spread)
--   opts.crafts  the crafts wanted
--   opts.margin  optional minimum margin on cost as a fraction (0.10 = expected profit at least 10% of the cost)
--   opts.budget  copper available (nil: no limit)
--   opts.owned   function(itemID) -> how many the character holds
--   opts.buy     function(line) -> true when the material is bought at the auction house (not a vendor)
-- Every auction material is allowed the same multiple m of today's price, so buying all of them at their
-- caps together still meets the odds: with n crafts the profit is n * (expected - fixed - m * auction)
-- and must reach z * sd, where sd = yield * sell * sqrt(n * p * (1 - p)) (C.Spread) and z = NormalInverse(odds).
-- Returns { crafts = n, scale = m, caps = { [reagent index] = copper per unit }, spend = the most the
-- purchase can cost, wanted = opts.crafts, limitedBy = "budget" or nil, z = z },
-- or nil and why: "notok" (the recipe has no complete profit), "nothing" (no auction material),
-- "margin" (at today's prices even the full crafts cannot meet the odds; `scale` is returned as a second value)
-- or "budget" (the budget cannot buy even the fewest crafts that meet the odds; the cost is the second value).
-- (PlanBuy below does the work; Setup holds the price rules it shares with PlanCaps.)
local function Setup(ev, opts)
    if not ev or ev.status ~= "ok" then return nil, "notok" end
    local z = C.NormalInverse(opts.odds) or 0
    local lines, fixed, auction = {}, 0, 0
    local others = {}   -- the materials that are not bought at the auction house (a vendor's spices): their cost counts against the budget too
    for index, line in ipairs(ev.reagents) do
        if not line.free and line.unit then
            if opts.buy(line) then
                lines[#lines + 1] = { index = index, line = line }
                auction = auction + line.total
            else
                fixed = fixed + line.total
                others[#others + 1] = line
            end
        end
    end
    if #lines == 0 or auction <= 0 then return nil, "nothing" end
    local sdPerRoot = ev.sellEach * math.sqrt(ev.chance * (1 - ev.chance))   -- sd = this * sqrt(crafts): a proc is one item

    -- A minimum margin on cost: expected - cost >= margin * cost, so cost <= expected / (1 + margin). That is
    -- one price multiple whatever the number of crafts; the odds give another that grows with it, and the
    -- lower of the two is used.
    local marginScale
    if opts.margin and opts.margin > 0 then marginScale = (ev.expected / (1 + opts.margin) - fixed) / auction end
    local function Scale(n)
        local m = (ev.expected - fixed - z * sdPerRoot / math.sqrt(n)) / auction
        if marginScale and marginScale < m then m = marginScale end
        return m
    end
    local function Caps(n)
        local m, caps = Scale(n), {}
        if m <= 0 then return nil, m end
        for _, entry in ipairs(lines) do
            local cap = math.floor(entry.line.unit * m)
            if cap < 1 then return nil, m end        -- a maximum price of 0 would mean "no maximum" to Auctionator
            caps[entry.index] = cap
        end
        return caps, m
    end
    local function Spend(n, caps)
        local total = 0
        for _, entry in ipairs(lines) do
            local need = math.max(0, math.ceil(n * entry.line.qty - 1e-9) - (opts.owned(entry.line.id) or 0))   -- whole units (a made material can need a fraction per craft)
            total = total + need * caps[entry.index]
        end
        -- what the other materials cost for `n` crafts, at today's price, less what is held: the budget is what the WHOLE run may cost, so the meat does
        -- not leave nothing for the spices (human report 2026-11-27: it bought more meat than there was gold left to buy the vendor materials)
        for _, line in ipairs(others) do
            local need = math.max(0, math.ceil(n * line.qty - 1e-9) - (opts.owned(line.id) or 0))
            total = total + need * line.unit
        end
        return total
    end
    return { Caps = Caps, Spend = Spend, z = z }
end

-- The price caps (copper per unit, by reagent index) for exactly `n` crafts, under the same odds and margin
-- rules as PlanBuy, or nil when no price meets them. Fewer crafts need lower prices (less time for the luck
-- to average out), so the limit for a smaller purchase than planned is lower than the one the list was sent with.
function C.PlanCaps(ev, opts, n)
    local setup = Setup(ev, opts)
    if not setup or not IsNumber(n) or n < 1 then return nil end
    return (setup.Caps(math.floor(n)))
end

function C.PlanBuy(ev, opts)
    local setup, why = Setup(ev, opts)
    if not setup then return nil, why end
    local wanted = math.floor(opts.crafts or 0)
    if wanted < 1 then return nil, "nothing" end
    local Caps, Spend, z = setup.Caps, setup.Spend, setup.z
    local caps, m = Caps(wanted)
    if not caps then return nil, "margin", m end
    -- the fewest crafts for which the odds can be met at all (more crafts narrow the spread, so this only
    -- gets easier with n): a bisection on the same test
    local low, high = 1, wanted
    while low < high do
        local mid = math.floor((low + high) / 2)
        if Caps(mid) then high = mid else low = mid + 1 end
    end
    local fewest = low
    local best = wanted
    if opts.budget then
        -- the most crafts the budget buys: spend only grows with n, so this is the last n that fits
        local fewestCost = Spend(fewest, Caps(fewest))
        if fewestCost > opts.budget then return nil, "budget", fewestCost end
        local lo, hi = fewest, wanted
        while lo < hi do
            local mid = math.ceil((lo + hi) / 2)
            if Spend(mid, Caps(mid)) <= opts.budget then lo = mid else hi = mid - 1 end
        end
        best = lo
    end
    local finalCaps, finalScale = Caps(best)
    return { crafts = best, scale = finalScale, caps = finalCaps, spend = Spend(best, finalCaps),
        wanted = wanted, limitedBy = best < wanted and "budget" or nil, z = z }
end

-- How today's price compares with the highest price that still breaks even (maxUnit), for the colour bar in
-- the detail panel: ratio = price / highest price. Green is well under the limit, orange is normal, red is
-- at or over it (or within 5% of it, where a small price move turns the craft into a loss).
-- Margin bands for a profession with no extra-result chance (Engineering): the colour is the WHOLE craft's margin (profit / cost), not one material's share of
-- its own limit, which called a cheap part "green" on a craft that barely earned anything. Below 5% is red, 5% to 20%
-- orange, 20% and over green; 0% (break-even) is the limit tick on the bar.
C.MARGIN_RED, C.MARGIN_GREEN = 0.05, 0.20

function C.MarginBand(margin)
    if not IsNumber(margin) then return nil end
    if margin >= C.MARGIN_GREEN then return "green" end
    if margin >= C.MARGIN_RED then return "orange" end
    return "red"
end

-- The unit price of one material (a line of Evaluate's reagents) at which the whole craft's margin would be `margin`,
-- every other material at today's price: cost = expected / (1 + margin). Never below 0. nil without a complete profit.
function C.PriceAtMargin(ev, line, margin)
    if not (ev and ev.status == "ok" and line and IsNumber(line.qty) and line.qty > 0 and IsNumber(line.total)) then return nil end
    local allowed = ev.expected / (1 + margin) - (ev.cost - line.total)
    return math.max(0, allowed / line.qty)
end

C.BAND_GREEN = 0.70      -- up to 70% of the limit: at least about 43% of room
C.BAND_RED = 0.95        -- above 95% of the limit

function C.PriceBand(ratio)
    if not IsNumber(ratio) or ratio < 0 then return nil end
    if ratio <= C.BAND_GREEN then return "green" end
    if ratio <= C.BAND_RED then return "orange" end
    return "red"
end

-- Luck: `extras` extra results seen in `crafts` crafts at Master Chef rank `rank`. Each craft is a yes/no
-- draw with chance p, so the count has mean crafts * p and standard deviation sqrt(crafts * p * (1 - p)).
-- z is how many standard deviations the real count is from the mean (nil when there is no spread to
-- measure against: no crafts, or rank 0 where nothing is expected).
function C.LuckStats(crafts, extras, rank)
    local p = C.Chance(rank)
    local out = { crafts = crafts, extras = extras, p = p, expected = crafts * p,
        sd = math.sqrt(crafts * p * (1 - p)), actual = crafts > 0 and extras / crafts or nil }
    if out.sd > 0 then out.z = (extras - out.expected) / out.sd end
    return out
end

-- The same for several ranks added together (the total row): expected and variance are sums.
function C.LuckTotal(extras, expected, variance)
    local out = { extras = extras, expected = expected, sd = variance > 0 and math.sqrt(variance) or 0 }
    if out.sd > 0 then out.z = (extras - expected) / out.sd end
    return out
end

-- Profit over `crafts` crafts. The extra result is a yes/no draw per craft, so the total profit is
-- `crafts * profit` on average with a standard deviation of sell * sqrt(crafts * p * (1 - p)): a proc
-- adds one item whatever the recipe makes. low/high bound the middle 90% (normal approximation);
-- `ahead` is the chance of finishing at or above zero, from the same approximation.
function C.Spread(ev, crafts)
    if not ev or ev.status ~= "ok" or not IsNumber(crafts) or crafts < 1 then return nil end
    crafts = math.floor(crafts)
    local p = ev.chance
    local total = ev.profit * crafts
    local sd = ev.sellEach * math.sqrt(crafts * p * (1 - p))
    local ahead
    if sd > 0 then ahead = C.Phi(total / sd) else ahead = total >= 0 and 1 or 0 end
    return { crafts = crafts, total = total, sd = sd,
        low = total - C.Z90 * sd, high = total + C.Z90 * sd, ahead = ahead }
end
