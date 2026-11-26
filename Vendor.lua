-- Deffar Profession Profit: the "+" button at a vendor. With a vendor window open, the
-- button buys the cooking materials the vendor sells (Soothing Spices, Hot Spices, Ice Cold Milk...) until you
-- hold enough for the crafts the materials you ALREADY hold can make, instead of shift-clicking 20 at a time.
--
-- How much is enough: for every saved recipe of this character, the crafts its auction-house materials allow
-- (those no vendor sells: bag count / quantity per craft, the smallest across them), times the quantity of the
-- vendor's material per craft. Materials a vendor sells (this one or one whose price was saved) are supplies to
-- top up, not limits. Recipes limited by the same material (two recipes both using Tender Wolf Meat) count once,
-- the larger need; recipes limited by different materials add up. What is bought is the shortfall, rounded up to
-- the vendor's bundle size, within the stock, the gold held and the bag room (partial stacks, then free slots,
-- always leaving /dpp bags free slots, default 2). With a recipe selected in the open Cooking window the
-- plan is for that recipe alone.
--
-- Buying follows the pattern of the installed ExtendedVendorForever (Restock.lua:216-310): one BuyMerchantItem
-- (item index, number of ITEMS, a multiple of the bundle up to GetMerchantItemMaxStack) per batch, then wait for
-- the bag count to confirm it before the next, re-reading the vendor each time; a failure or an unconfirmed
-- purchase stops the run and says so, never retries; combat or closing the vendor stops it. The click that
-- starts it authorises one finite plan, shown in the button's tooltip first. FOR-0183: the semantics are taken
-- from that addon's source, not probed on this client.
local _, F = ...
local V = {}
F.Vendor = V

V.open = false          -- a vendor window is open (MERCHANT_SHOW / MERCHANT_CLOSED)
V.run = nil             -- the purchase in progress
local CONFIRM_SECONDS, STEP = 5, 0.1

---------------------------------------------------------------------------
-- What the vendor sells
---------------------------------------------------------------------------

-- { [itemID] = { index, bundle = items per purchase, price = copper per bundle, stock = items left or nil } }
-- for the rows paid for in gold only. nil when the merchant API is missing.
function V.Offers()
    if type(GetMerchantNumItems) ~= "function" or type(GetMerchantItemID) ~= "function" or not F.Has(C_MerchantFrame, "GetItemInfo") then
        return nil
    end
    local count = GetMerchantNumItems()
    if not F.Integer(count, 0, 1000) then return nil end
    local offers = {}
    for index = 1, count do
        local id = GetMerchantItemID(index)
        local info = C_MerchantFrame.GetItemInfo(index)
        if F.Integer(id, 1, 2147483647) and F.Table(info) and F.Integer(info.price, 1, 2147483647) and info.hasExtendedCost ~= true then
            local bundle = F.Integer(info.stackCount, 1, 100000) and info.stackCount or 1
            offers[id] = { index = index, bundle = bundle, price = info.price,
                stock = F.Integer(info.numAvailable, 0, 2147483647) and info.numAvailable or nil }
        end
    end
    return offers
end

---------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------

local function Held(ids)
    local total = 0
    for _, id in ipairs(ids) do total = total + F.Owned(id) end
    return total
end

-- Free slots in the ordinary bags (family 0), or nil when the bag API cannot be read. The reagent bag and other
-- special bags are not counted, so the room is never overestimated. C_Container.GetContainerNumFreeSlots returns
-- (free, family) on Forever 1.60.1: the installed ExtendedVendorForever uses it (BagSort.lua:491-492, Compat.lua:16-20).
local function FreeSlots()
    local container = _G.C_Container
    if not (F.Has(container, "GetContainerNumFreeSlots") and F.Has(container, "GetContainerNumSlots")
        and F.Has(container, "GetContainerItemID") and F.Has(container, "GetContainerItemInfo")) then return nil end
    local last = F.Integer(_G.NUM_BAG_SLOTS, 0, 20) and _G.NUM_BAG_SLOTS or 4
    local free = 0
    for bag = 0, last do
        local n, family = container.GetContainerNumFreeSlots(bag)
        if F.Integer(n, 0, 1000) and (family == nil or family == 0) then free = free + n end
    end
    return free
end

-- How many more of an item fit into stacks the character already has (partial stacks in the ordinary bags).
local function PartialRoom(itemID, stackSize)
    local container = _G.C_Container
    local last = F.Integer(_G.NUM_BAG_SLOTS, 0, 20) and _G.NUM_BAG_SLOTS or 4
    local room = 0
    for bag = 0, last do
        local slots = container.GetContainerNumSlots(bag)
        if F.Integer(slots, 0, 1000) then
            for slot = 1, slots do
                if container.GetContainerItemID(bag, slot) == itemID then
                    local info = container.GetContainerItemInfo(bag, slot)
                    local count = F.Table(info) and info.stackCount or nil
                    if F.Integer(count, 1, 100000) and count < stackSize then room = room + (stackSize - count) end
                end
            end
        end
    end
    return room
end

local function BagReserve()
    return F.Integer(F.db and F.db.bagReserve, 0, 20) and F.db.bagReserve or 2
end

-- The shortfalls this vendor can fill: { rows = { { id, name, index, bundle, price, have, target, buy, cost,
-- for = { recipe names } } }, cost = total copper, short = true when the gold held cut something }, or nil
-- and why ("api", "nochar").
function V.Plan()
    local offers = V.Offers()
    if not offers then return nil, "api" end
    local char = F.Char()
    if not char then return nil, "nochar" end

    -- With a saved recipe (cooking or engineering) selected in the open profession window the plan is for that recipe
    -- alone; otherwise for all the recipes of the tab in use (Cooking unless the window's Engineering tab is showing).
    local selected = F.SelectedRecipeID and F.SelectedRecipeID() or nil
    local pool = F.RecipesOf(char, F.Tab()) or {}   -- (the Enchanting tab has no recipes)
    if selected then
        local chosen = F.FindRecipe(selected)
        if chosen then pool = { [selected] = chosen } else selected = nil end
    end

    -- A material is a SUPPLY (something to top up to match the rest) when this vendor sells it or any vendor does
    -- (a vendor price has been saved for it); the others (auction house materials such as the clams or the meat)
    -- set how many crafts there are to buy supplies for. Otherwise Hot Spices bought at another vendor would block
    -- buying milk here just because none are held yet.
    local function IsSupply(ids)
        for _, id in ipairs(ids or {}) do
            if offers[id] or (type(F.db.vendorBuy) == "table" and type(F.db.vendorBuy[id]) == "table") then return true end
        end
        return false
    end

    -- need[vendorItemID][limitingMaterialID] = { need = items, recipe = name }: the larger need per limiting material
    local need = {}
    local blocked = {}   -- recipes that use something sold here but have none of a limiting material: { recipe, material }
    local covered = {}   -- recipes that use something sold here and have materials for { crafts } crafts
    local unsized = {}   -- recipes that use something sold here but whose materials are all vendor items
    local craftCtx = F.CraftContext()
    for recipeID, recipe in pairs(pool) do
        if type(recipe) == "table" and type(recipe.r) == "table" and (not selected or recipeID == selected) then
            -- what must really be bought: a material the player makes cheaper than buying it is replaced by its own materials
            local flat, via = F.Flatten(recipe, craftCtx)
            local reagents = #via > 0 and flat or recipe.r
            local crafts, limiting
            for _, reagent in ipairs(reagents) do
                if not IsSupply(reagent.ids) then
                    local made = math.floor(Held(reagent.ids or {}) / (tonumber(reagent.qty) or 1))
                    if not crafts or made < crafts then crafts, limiting = made, (reagent.ids or {})[1] end
                end
            end
            local usesHere = false
            for _, reagent in ipairs(reagents) do
                for _, id in ipairs(reagent.ids or {}) do if offers[id] then usesHere = true end end
            end
            if usesHere then
                if crafts == 0 and limiting then
                    blocked[#blocked + 1] = { recipe = recipe.name, material = F.ItemMeta(limiting).name or ("item " .. limiting) }
                elseif crafts and crafts > 0 then
                    covered[#covered + 1] = { recipe = recipe.name, crafts = crafts }
                elseif not crafts then
                    unsized[#unsized + 1] = { recipe = recipe.name }   -- every material is a vendor item: nothing held to size it by
                end
            end
            if crafts and crafts > 0 and limiting then
                for _, reagent in ipairs(reagents) do
                    for _, id in ipairs(reagent.ids or {}) do
                        if offers[id] then
                            local byLimit = need[id] or {}
                            need[id] = byLimit
                            local items = crafts * (tonumber(reagent.qty) or 1)
                            if not byLimit[limiting] or items > byLimit[limiting].need then
                                byLimit[limiting] = { need = items, recipe = recipe.name, crafts = crafts, out = recipe.out, per = tonumber(reagent.qty) or 1 }
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    local gold = F.Bought and F.Bought.Money() or nil
    table.sort(blocked, function(a, b) return a.recipe < b.recipe end)
    table.sort(covered, function(a, b) return a.recipe < b.recipe end)
    table.sort(unsized, function(a, b) return a.recipe < b.recipe end)
    local plan = { rows = {}, cost = 0, selected = selected and pool[selected].name or nil, reserve = BagReserve(),
        blocked = blocked, covered = covered, unsized = unsized, groups = {} }
    local slotsLeft = FreeSlots()          -- shared by every row: each new stack takes one
    if not slotsLeft then plan.bagUnknown = true end
    local ids = {}
    for id in pairs(need) do ids[#ids + 1] = id end
    table.sort(ids)

    -- The supplies the vendor sells, with what the bags can take of each (partial stacks first, then free slots).
    local cands, byId = {}, {}
    for _, id in ipairs(ids) do
        local offer = offers[id]
        local cand = { id = id, offer = offer, target = 0, have = F.Owned(id), left = F.Owned(id), recipes = {}, bought = 0 }
        local stack = F.ItemMeta(id).stack
        if not slotsLeft or not stack then
            plan.bagUnknown = true   -- (the bag space or the stack size cannot be read: nothing of it is bought, fail closed)
            plan.unreadable = plan.unreadable or F.ItemMeta(id).name or ("Item " .. id)
        else
            cand.stack, cand.room = stack, PartialRoom(id, stack)
            cands[#cands + 1] = cand
            byId[id] = cand
        end
        for _, entry in pairs(need[id]) do cand.target = cand.target + entry.need end
    end

    -- GROUPS: the recipes limited by the same material share one group (their need of a supply is the larger one, counted once). The
    -- group with the FEWEST crafts is served first and in full (all its supplies, in step) before the next one gets any: with meat for
    -- 74 Buzzard Wing and 287 Tiger Meat crafts, the Buzzard Wing supplies come first. Gold and bag room are what is left over.
    local groups, groupOf = {}, {}
    for _, id in ipairs(ids) do
        for limiting, entry in pairs(need[id]) do
            local group = groupOf[limiting]
            if not group then
                group = { limiting = limiting, crafts = entry.crafts, items = {}, recipes = {}, info = {}, dishes = {} }
                groupOf[limiting] = group
                groups[#groups + 1] = group
            end
            group.crafts = math.min(group.crafts, entry.crafts)
            group.items[id] = (group.items[id] or 0) + entry.need
            group.recipes[#group.recipes + 1] = entry.recipe
            local info = group.info[entry.recipe]   -- the dish: what it is, how many crafts the held material allows, what it takes of each supply
            if not info then
                info = { name = entry.recipe, out = entry.out, crafts = entry.crafts, per = {} }
                group.info[entry.recipe] = info
                group.dishes[#group.dishes + 1] = info
            end
            info.per[id] = entry.per
        end
    end
    table.sort(groups, function(a, b)
        if a.crafts ~= b.crafts then return a.crafts < b.crafts end
        return a.limiting < b.limiting
    end)

    local usable = slotsLeft and math.max(0, slotsLeft - plan.reserve) or 0
    local function Slots(cand, amount) return amount > 0 and math.ceil(math.max(0, amount - cand.room) / cand.stack) or 0 end
    local function TakenBy(adds)   -- the slots every supply would take with `adds` on top of what is bought already
        local slots = 0
        for _, cand in ipairs(cands) do slots = slots + Slots(cand, cand.bought + (adds[cand.id] or 0)) end
        return slots
    end
    local function Fits(adds, spent)
        local cost = spent
        for id, amount in pairs(adds) do cost = cost + amount / byId[id].offer.bundle * byId[id].offer.price end
        return TakenBy(adds) <= usable and (not gold or cost <= gold), cost
    end
    local spent = 0
    for _, group in ipairs(groups) do
        -- what this group still lacks of each supply, in whole bundles, within what the vendor has left
        local short, heldUsed = {}, {}
        for id, wanted in pairs(group.items) do
            local cand = byId[id]
            if cand then
                local held = math.min(cand.left, wanted)
                heldUsed[id] = held
                cand.left = cand.left - held
                local lack = math.ceil((wanted - held) / cand.offer.bundle) * cand.offer.bundle
                if cand.offer.stock then lack = math.min(lack, math.floor((cand.offer.stock - cand.bought) / cand.offer.bundle) * cand.offer.bundle) end
                if lack > 0 then short[id] = lack end
            end
        end
        if next(short) then
            local function Share(fraction)
                local adds = {}
                for id, lack in pairs(short) do adds[id] = math.floor(lack * fraction / byId[id].offer.bundle) * byId[id].offer.bundle end
                return adds
            end
            local fits, cost = Fits(Share(1), spent)
            local share = 1
            if not fits then
                if gold and cost > gold then plan.short = true end
                if TakenBy(Share(1)) > usable then plan.bagShort = true end
                local low, high = 0, 1
                for _ = 1, 40 do
                    local mid = (low + high) / 2
                    if (Fits(Share(mid), spent)) then low = mid else high = mid end
                end
                share = low
            end
            local adds = Share(share)
            -- a bundle that did not fit at the even share goes to whichever supply it still fits, one bundle at a time
            if share < 1 then
                local grew = true
                while grew do
                    grew = false
                    for _, id in ipairs(ids) do
                        local lack = short[id]
                        local cand = byId[id]
                        if lack and (adds[id] or 0) + cand.offer.bundle <= lack then
                            adds[id] = (adds[id] or 0) + cand.offer.bundle
                            if (Fits(adds, spent)) then grew = true else adds[id] = adds[id] - cand.offer.bundle end
                        end
                    end
                end
            end
            local _, now = Fits(adds, spent)
            spent = now
            local named = false
            for id, amount in pairs(adds) do
                if amount > 0 then byId[id].bought = byId[id].bought + amount; named = true end
            end
            if named then
                for id, amount in pairs(adds) do
                    if amount > 0 then
                        for _, name in ipairs(group.recipes) do byId[id].recipes[#byId[id].recipes + 1] = name end
                    end
                end
                -- what this group's purchase is for, as the tooltip shows it: the dishes it makes possible and the supplies bought for them
                local record = { dishes = {}, rows = {}, cost = 0 }
                for _, id in ipairs(ids) do
                    local amount = adds[id]
                    if amount and amount > 0 then
                        local cand = byId[id]
                        local cost = amount / cand.offer.bundle * cand.offer.price
                        record.cost = record.cost + cost
                        record.rows[#record.rows + 1] = { id = id, name = F.ItemMeta(id).name or ("Item " .. id), buy = amount, cost = cost }
                    end
                end
                for _, info in ipairs(group.dishes) do
                    local covered = info.crafts
                    for id, per in pairs(info.per) do
                        covered = math.min(covered, math.floor(((heldUsed[id] or 0) + (adds[id] or 0)) / per))
                    end
                    if covered > 0 then record.dishes[#record.dishes + 1] = { name = info.name, out = info.out, crafts = covered } end
                end
                table.sort(record.dishes, function(a, b) return a.name < b.name end)
                plan.groups[#plan.groups + 1] = record
            end
        end
    end
    for _, cand in ipairs(cands) do
        if cand.bought > 0 then
            local cost = cand.bought / cand.offer.bundle * cand.offer.price
            plan.cost = plan.cost + cost
            table.sort(cand.recipes)
            local names, seen = {}, {}
            for _, name in ipairs(cand.recipes) do
                if not seen[name] then seen[name] = true; names[#names + 1] = name end
            end
            plan.rows[#plan.rows + 1] = { id = cand.id, name = F.ItemMeta(cand.id).name or ("Item " .. cand.id), index = cand.offer.index,
                bundle = cand.offer.bundle, price = cand.offer.price, have = cand.have, target = cand.target, buy = cand.bought, cost = cost,
                ["for"] = names }
        end
    end
    return plan
end

-- Why there is nothing to buy, in at most three short pieces (what is covered, what is missing). nil when the plan
-- has nothing to say (this vendor sells nothing the recipes use).
function V.WhyEmpty(plan)
    local parts = {}
    for _, c in ipairs(plan.covered or {}) do
        parts[#parts + 1] = string.format("%s: you already hold enough for its %d crafts", c.recipe, c.crafts)
    end
    for _, b in ipairs(plan.blocked or {}) do
        parts[#parts + 1] = string.format("%s needs %s and you hold none, so there is nothing to buy supplies for", b.recipe, b.material)
    end
    for _, u in ipairs(plan.unsized or {}) do
        parts[#parts + 1] = string.format("%s has only vendor materials, so there is no held material to size the purchase by", u.recipe)
    end
    if #parts == 0 then return nil end
    local shown = {}
    for index = 1, math.min(3, #parts) do shown[index] = parts[index] end
    return table.concat(shown, "; ") .. (#parts > 3 and (" (+" .. (#parts - 3) .. " more)") or "")
end

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------

local function Finish(run, reason)
    if V.run ~= run then return end
    V.run = nil
    local bits = {}
    for _, row in ipairs(run.rows) do
        if (row.done or 0) > 0 then bits[#bits + 1] = row.done .. " " .. row.name end
    end
    local bought = #bits > 0 and ("bought " .. table.concat(bits, ", ")) or "nothing bought"
    F.Print(reason and (bought .. ". Stopped: " .. reason) or ("vendor: " .. bought .. " (" .. F.Money(run.spent or 0) .. ")."))
    V.Refresh()
end

function V.Cancel(reason)
    if V.run then Finish(V.run, reason or "cancelled.") end
end

local function Continue(run)
    if V.run ~= run then return end
    if not V.open then Finish(run, "the vendor window closed."); return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then Finish(run, "you are in combat."); return end
    if run.waiting then
        local pending = run.waiting
        if F.Owned(pending.id) >= pending.expected then
            pending.row.done = (pending.row.done or 0) + pending.amount
            run.spent = (run.spent or 0) + pending.amount / pending.row.bundle * pending.row.price
            run.waiting = nil
        elseif GetTime() >= pending.deadline then
            Finish(run, "a purchase was not confirmed (bag space, a stock limit or a game prompt?).")
            return
        else
            C_Timer.After(STEP, function() Continue(run) end)
            return
        end
    end
    while run.position <= #run.rows do
        local row = run.rows[run.position]
        local remaining = row.buy - (row.sent or 0)
        if remaining <= 0 then
            run.position = run.position + 1
        else
            local offers = V.Offers()
            local offer = offers and offers[row.id]
            if not offer or offer.bundle ~= row.bundle or offer.price ~= row.price then
                Finish(run, "the vendor's offer changed.")
                return
            end
            local maximum = type(GetMerchantItemMaxStack) == "function" and GetMerchantItemMaxStack(offer.index) or row.bundle
            local amount = math.min(remaining, math.floor(maximum / row.bundle) * row.bundle)
            if amount <= 0 then Finish(run, "this vendor cannot sell that bundle."); return end
            row.sent = (row.sent or 0) + amount
            run.waiting = { id = row.id, row = row, amount = amount, expected = F.Owned(row.id) + amount, deadline = GetTime() + CONFIRM_SECONDS }
            local ok = pcall(BuyMerchantItem, offer.index, amount)
            if not ok then Finish(run, "the purchase could not be sent."); return end
            C_Timer.After(STEP, function() Continue(run) end)
            return
        end
    end
    Finish(run)
end

-- The "+" click: buys the whole plan shown in the tooltip. Returns true when a purchase was started.
function V.Buy()
    if V.run then return false, "already buying" end
    if not V.open then return false, "no vendor window" end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        F.Print("cannot buy in combat.")
        return false, "combat"
    end
    if type(BuyMerchantItem) ~= "function" then
        F.Print("this client has no BuyMerchantItem: the + button cannot buy.")
        return false, "api"
    end
    local plan, why = V.Plan()
    if not plan then F.Print("cannot read the vendor (" .. tostring(why) .. ").") return false, why end
    if plan.bagUnknown then
        F.Print("cannot read your bag space or a stack size, so nothing is bought (the + button keeps " .. plan.reserve .. " bag slots free).")
        return false, "bags"
    end
    if #plan.rows == 0 then
        local why = V.WhyEmpty(plan)
        F.Print(plan.bagShort and ("no room: your bags would have fewer than " .. plan.reserve .. " free slots left.")
            or (plan.short and "nothing to buy: you cannot afford any of it.")
            or (why and ("nothing to buy here: " .. why .. "."))
            or "nothing to buy here: this vendor sells none of the materials your recipes use.")
        return false, "empty"
    end
    V.run = { rows = plan.rows, position = 1, spent = 0 }
    V.Refresh()   -- greyed out while it buys
    Continue(V.run)
    return true
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------

-- Why a greyed-out button buys nothing, as short lines in the tooltip grey (Style.lua): { lines of text }. The chat line a click prints
-- (V.WhyEmpty) is the longer one.
local function IdleLines(plan)
    if not plan then return { "Cannot read this vendor." } end
    if plan.bagUnknown then return { "Cannot read your bag space." } end
    if plan.bagShort then return { "No bag space." } end
    if plan.short then return { "Cannot afford it." } end
    -- (no list of the recipes that are covered or missing materials: the tooltip is only about what would be bought)
    return { "Nothing to buy." }
end

local function Tip(button)
    if type(GameTooltip) ~= "table" then return end
    local S = F.Style   -- the palette every Profession Profit tooltip uses (Style.lua), not colours of its own
    local plan = V.Plan()
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:ClearLines()
    S.StartRules()
    S.Title(GameTooltip, "Buy materials")
    if V.run then
        S.Reason(GameTooltip, "Buying...")
    elseif not plan or #plan.rows == 0 then
        if plan and plan.selected then S.Reason(GameTooltip, "For " .. plan.selected) end
        local lines = IdleLines(plan)
        for _, line in ipairs(lines) do S.Reason(GameTooltip, line) end
    else
        --   ____________        a line under the title, then for each dish:
        --   Craft: [icon] Dish xN   the dish the held material is for, and how many crafts the purchase covers
        --   Buy: [icon] Supply xY   each supply bought for it
        --   Cost: 24s42c            what that costs
        --   ____________            a line before the next dish; the total follows the last one directly
        S.Rule(GameTooltip)
        local shown = 0
        for index, group in ipairs(plan.groups) do
            if shown >= 8 then GameTooltip:AddLine("...", S.DIM[1], S.DIM[2], S.DIM[3]); break end
            if index > 1 then S.Rule(GameTooltip) end
            for _, dish in ipairs(group.dishes) do
                GameTooltip:AddLine(S.Paint(S.GOLDCODE, "Craft: ") .. S.ItemQty(dish.out, dish.name, dish.crafts, S.SAND), 1, 1, 1)
            end
            for _, row in ipairs(group.rows) do
                shown = shown + 1
                GameTooltip:AddLine(S.Paint(S.GREEN, "Buy: ") .. S.ItemQty(row.id, row.name, row.buy, S.SAGE), 1, 1, 1)
            end
            GameTooltip:AddLine(S.Grey("Cost: ") .. F.Money(group.cost), 1, 1, 1)
        end
        GameTooltip:AddLine(" ")   -- (an empty line above the total)
        S.Line(GameTooltip, "Total", F.Money(plan.cost))
        if plan.short then S.Reason(GameTooltip, "Limited by your gold.") end
        if plan.bagShort then S.Reason(GameTooltip, "Limited by bag space.") end
        if plan.bagUnknown then S.Reason(GameTooltip, "Cannot read bag space or stack size" .. (plan.unreadable and (": " .. plan.unreadable) or "") .. ".") end
    end
    GameTooltip:Show()
    S.FitRules(GameTooltip)   -- (the lines are as wide as the tooltip the other lines made)
end

-- Creates the button on the merchant window the first time it is needed. The merchant frame's name is the
-- usual one (MerchantFrame); if it does not exist there is no button and /dpp status says so.
function V.EnsureButton()
    if V.button then return V.button end
    local parent = _G.MerchantFrame
    if type(parent) ~= "table" or not F.Has(parent, "GetFrameLevel") or not F.UI or not F.UI.W then
        V.noFrame = true
        return nil
    end
    local button = F.UI.W.MakeButton(parent, "+", 35, 29)   --
    if F.Has(button.label, "SetFontObject") then button.label:SetFontObject("GameFontNormalLarge") end
    button:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 4, 30)   -- outside the merchant window's right edge, near its bottom (the Create All "+" sits at the profession window's bottom right too)
    button.accent = F.UI.W.GOLD
    button.label:SetTextColor(F.UI.W.GOLD[1], F.UI.W.GOLD[2], F.UI.W.GOLD[3])
    button:SetScript("OnClick", function() V.Buy() end)
    button:HookScript("OnEnter", Tip)
    button:HookScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    button:Hide()
    V.button = button
    return button
end

-- True when this vendor sells a material of one of the character's saved recipes. The button is shown for
-- such a vendor whatever is held (the tooltip then says whether there is anything to buy), so selecting a
-- recipe in the Cooking window needs no refresh of the button.
function V.Relevant()
    local offers = V.Offers()
    if not offers then return false end
    for id in pairs(F.Bought and F.Bought.Reagents() or {}) do
        if offers[id] then return true end
    end
    return false
end

function V.Refresh()
    if not V.open then
        if V.button then V.button:Hide() end
        return
    end
    local button = V.EnsureButton()
    if not button then return end
    -- always there while a vendor is open: a golden border when it sells a material of your recipes, greyed out when it does not
    -- and while a purchase is running (it stays, it is not hidden)
    button:Show()
    F.UI.W.SetReady(button, not V.run and V.Relevant())
end

function V.OnMerchantShow()
    V.open = true
    V.Refresh()
end

function V.OnMerchantClosed()
    V.open = false
    V.Cancel("the vendor window closed.")
    V.Refresh()
end
