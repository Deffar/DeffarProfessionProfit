-- Deffar Profession Profit: a "+" button beside the profession window that presses Create All on the most profitable craft the player has
-- the materials for, without selecting the recipe first.
--
-- How: the button sits on the profession window (ProfessionsFrame) when it is one of the saved professions (Cooking, Engineering,
-- Tailoring) and it is the player's own window. A click works out, for each saved recipe of that profession, how many whole crafts the
-- bags allow (every reagent's units held, over the quantity one craft takes), takes the one with the best profit per craft in Profession
-- Profit's numbers (BuildRows: the rank in use, prices now) among those with at least one craft, and calls
-- C_TradeSkillUI.CraftRecipe(recipeID, numCrafts): what the window's Create All button calls (FOR-0195). A craft that loses money is not
-- started: it says so. HYPOTHESIS (FOR-0198), not yet seen on Forever: that an addon's hardware click may call CraftRecipe for a recipe
-- that is not selected in the window.
local _, F = ...
local C = {}
F.Craft = C

local MAX = 2147483647

-- The profession (cooking, engineering, tailoring, leatherworking) the open window is, or nil when it is neither one of those nor the player's own.
function C.WindowProfession()
    local api = _G.C_TradeSkillUI
    if not F.Has(api, "GetBaseProfessionInfo") then return nil end
    if F.OthersWindow and F.OthersWindow() then return nil end
    local info = api.GetBaseProfessionInfo()
    if not F.Table(info) then return nil end
    local cooking = F.CookingLine()
    if info.professionID == cooking or info.parentProfessionID == cooking then return "cooking" end
    return F.WindowProfession and F.WindowProfession(info) or nil
end

-- How many whole crafts of a recipe the bags allow (0 when a reagent is short). A reagent that can be filled by more than one item
-- counts what is held of all of them.
function C.Crafts(recipe)
    if type(recipe) ~= "table" or type(recipe.r) ~= "table" or #recipe.r == 0 then return 0 end
    local crafts
    for _, reagent in ipairs(recipe.r) do
        local have = 0
        for _, id in ipairs(type(reagent.ids) == "table" and reagent.ids or {}) do have = have + F.Owned(id) end
        local per = tonumber(reagent.qty) or 1
        local n = per > 0 and math.floor(have / per) or 0
        crafts = crafts and math.min(crafts, n) or n
    end
    return crafts or 0
end

-- The icon of a requirement (a cooking fire, an Iron Oven) for the tooltip: the picture the entry itself carries (icon / iconID /
-- texture / fileID, if the game gives one), else the item of that name (an Iron Oven or a tool), else the spell of that name (a
-- Cooking Fire), else nil. Remembered by name. Which of these Forever answers is unverified (FOR-0198).
C.icons = {}
function C.RequirementIcon(name, entry)
    if C.icons[name] then return C.icons[name] end
    local icon
    if type(entry) == "table" then icon = entry.icon or entry.iconID or entry.texture or entry.fileID end
    if not icon and F.Has(_G.C_Item, "GetItemInfoInstant") then
        local _, _, _, _, itemIcon = _G.C_Item.GetItemInfoInstant(name)
        icon = itemIcon
    end
    if not icon and F.Has(_G.C_Spell, "GetSpellInfo") then
        local info = _G.C_Spell.GetSpellInfo(name)
        icon = F.Table(info) and info.iconID or nil
    end
    if icon then C.icons[name] = icon end
    return icon
end

-- What a recipe needs besides its materials that is not met now (a cooking fire, an Iron Oven): the names of the requirements that
-- C_TradeSkillUI.GetRecipeRequirements(recipeID) says are not met (an entry with `met == false`, FOR-0198), joined, and the list;
-- nil when all are met or the client cannot say.
function C.Unmet(recipeID)
    local api = _G.C_TradeSkillUI
    if not F.Has(api, "GetRecipeRequirements") then return nil end
    local requirements = api.GetRecipeRequirements(recipeID)
    local names = {}
    for _, requirement in ipairs(type(requirements) == "table" and requirements or {}) do
        if type(requirement) == "table" and (requirement.met == false or requirement.isMet == false) then
            names[#names + 1] = F.String(requirement.name) and requirement.name or "a requirement"
            if F.String(requirement.name) then C.RequirementIcon(requirement.name, requirement) end   -- (remember its icon now)
        end
    end
    if #names == 0 then return nil end
    return table.concat(names, ", "), names
end

-- The craft to make: { id, name, profit (copper per craft), crafts }, the one with the best profit per craft among the profession's
-- saved recipes the bags allow at least one craft of and whose requirements are met; nil when there is none. The second value says whether
-- any recipe could be made by the materials, the third lists those skipped for an unmet requirement ({ name, profit, needs }).
local function Entry(row, crafts)
    local ev = row.ev
    return { id = row.id, name = row.name, recipe = row.recipe, profit = ev and ev.profit, crafts = crafts, out = row.recipe.out, expected = ev and ev.expected,
        factor = (ev and F.Number(ev.sellEach) and ev.sellEach > 0 and F.Number(ev.expected)) and ev.expected / ev.sellEach or nil }
end

function C.Best(prof)
    local rows = F.BuildRows(prof)
    local best, any
    local skipped, makeable = {}, {}
    for _, row in ipairs(rows or {}) do
        local crafts = row.unknown and 0 or C.Crafts(row.recipe)   -- (a recipe the character has not learned cannot be made)
        if crafts >= 1 then
            local needs, names = C.Unmet(row.id)
            if needs then
                local entry = Entry(row, crafts)   -- (the same fields as a craft that can start: the tooltip lists it the same way)
                entry.needs, entry.names = needs, names
                skipped[#skipped + 1] = entry
            else
                any = true
                local profit = row.ev and row.ev.profit
                if F.Number(profit) then
                    local entry = Entry(row, crafts)
                    makeable[#makeable + 1] = entry
                    if not best or profit > best.profit then best = entry end
                end
            end
        end
    end
    table.sort(makeable, function(a, b) return a.profit > b.profit end)
    table.sort(skipped, function(a, b) return (a.profit or -math.huge) > (b.profit or -math.huge) end)
    return best, any == true, skipped, makeable
end

-- Recipes the bags hold the main material of (what no vendor sells: the meat) but not enough of a supply (something a vendor sells, so a
-- vendor price has been saved for it: the apples, the water) for all the crafts that material allows: { out, name, crafts, missing = { { id,
-- need = units still lacking } } }, the fewest crafts first (the order the vendor "+" buys in). `crafts` is what the main material allows.
function C.Shortages(prof)
    local sold = F.db and type(F.db.vendorBuy) == "table" and F.db.vendorBuy or {}
    local function IsSupply(ids)
        for _, id in ipairs(type(ids) == "table" and ids or {}) do
            if type(sold[id]) == "table" then return true end
        end
        return false
    end
    local function Held(ids)
        local have = 0
        for _, id in ipairs(type(ids) == "table" and ids or {}) do have = have + F.Owned(id) end
        return have
    end
    local list = {}
    for _, row in ipairs(F.BuildRows(prof) or {}) do
        local recipe = row.recipe
        if not row.unknown and type(recipe) == "table" and type(recipe.r) == "table" then
            local crafts
            for _, reagent in ipairs(recipe.r) do
                if not IsSupply(reagent.ids) then
                    local n = math.floor(Held(reagent.ids) / (tonumber(reagent.qty) or 1))
                    crafts = crafts and math.min(crafts, n) or n
                end
            end
            if crafts and crafts >= 1 then
                local missing = {}
                for _, reagent in ipairs(recipe.r) do
                    if IsSupply(reagent.ids) and F.Integer((reagent.ids or {})[1], 1, MAX) then
                        local lacking = crafts * (tonumber(reagent.qty) or 1) - Held(reagent.ids)
                        if lacking > 0 then missing[#missing + 1] = { id = reagent.ids[1], need = lacking } end
                    end
                end
                if #missing > 0 then list[#list + 1] = { out = recipe.out, name = row.name, crafts = crafts, missing = missing } end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.crafts ~= b.crafts then return a.crafts < b.crafts end
        return a.name < b.name
    end)
    return list
end

-- "Skipped Roast Raptor: needs Iron Oven." for the skipped recipes that would have paid better than `best` (all of them when none).
local function SkippedText(skipped, best)
    local parts = {}
    for _, s in ipairs(skipped or {}) do
        if not best or (F.Number(s.profit) and s.profit > best.profit) then parts[#parts + 1] = s.name .. " (needs " .. s.needs .. ")" end
    end
    if #parts == 0 then return "" end
    return " Skipped, a requirement is missing: " .. table.concat(parts, ", ") .. "."
end

-- The made item as a clickable link ([Item] in chat), else its name.
local function ItemText(best)   -- (best: any { out, name } entry)
    return F.ItemLink(best.out, best.name)
end

-- What one craft sells for, whatever the panel's sell mode is (a mode only changes the profit the recipes are ranked by): to a vendor, or
-- at the auction house (Shift): the Auctionator price less the AH cut. Times the items a craft is expected to give. nil without a price.
function C.VendorValue(entry)
    local sell = F.Integer(entry.out, 1, MAX) and F.ItemMeta(entry.out).sell or nil
    if not (F.Number(sell) and sell > 0 and entry.factor) then return nil end
    return math.floor(sell * entry.factor)
end

function C.AuctionValue(entry)
    local ah = F.AuctionPrice(entry.out)
    if not (ah and entry.factor) then return nil end
    return math.floor(math.floor(ah * (1 - F.AH_CUT)) * entry.factor)
end

-- What a click would do, as lines for the tooltip and the chat: { text, ok } where ok is whether a craft would start.
function C.Plan(prof)
    local best, any, skipped = C.Best(prof)
    local why = SkippedText(skipped, best)
    if not best then
        if #skipped > 0 and not any then return "You hold the materials, but a requirement is missing.", false, nil, why end
        return any and "No profit can be worked out for what you can make (a price is missing)." or "You do not hold the materials for any saved recipe.", false, nil, why
    end
    -- (a craft that loses money is still made: the player asked for it, and the tooltip shows the loss; the best of them is the one made)
    -- "[Item] x46 | 6m 12s": the made item, the number of crafts and how long they take (the profit is in the tooltip, not the chat)
    return C.Line(best), true, best, why
end

-- "[Item] x46 | 6m 12s": the made item, the number of crafts and how long they take (the profit is in the tooltip, not the chat)
function C.Line(entry)
    local each, source = F.CraftSeconds(entry.id)
    return string.format("%s x%d | %s%s", ItemText(entry), entry.crafts, (source == "default" or source == "scaled") and "~" or "", F.DurationText(entry.crafts * each))
end

-- After a craft was asked for: when the game has not started it a moment later (no cast, no repeating craft), say so with what it told us: the
-- error line it printed (UI_ERROR_MESSAGE, watched for that moment only) and what it says about the recipe (human report 2026-11-27: the chooser
-- click printed the chat line but "no craft starts", cause unknown, so the game's own answer is shown). Only where the client has the calls to
-- tell a started craft (UnitCastingInfo or IsRecipeRepeating); nothing otherwise.
local function WatchStart(entry, pending, via, onFail)
    local api = _G.C_TradeSkillUI
    local canTell = type(_G.UnitCastingInfo) == "function" or F.Has(api, "IsRecipeRepeating")
    if not (canTell and F.Has(_G.C_Timer, "After") and type(_G.CreateFrame) == "function") then return end
    C.watching = { error = nil }
    if not C.errorFrame then
        C.errorFrame = _G.CreateFrame("Frame")
        C.errorFrame:SetScript("OnEvent", function(_, _, first, second)
            if C.watching then C.watching.error = type(second) == "string" and second or (type(first) == "string" and first or nil) end
        end)
    end
    C.errorFrame:RegisterEvent("UI_ERROR_MESSAGE")
    _G.C_Timer.After(0.7, function()
        local seen = C.watching
        C.watching = nil
        C.errorFrame:UnregisterEvent("UI_ERROR_MESSAGE")
        local started = (type(_G.UnitCastingInfo) == "function" and _G.UnitCastingInfo("player") ~= nil)
            or (F.Has(api, "IsRecipeRepeating") and api.IsRecipeRepeating() == true)
        if started then return end
        if onFail then onFail() end
        local info = F.Has(api, "GetRecipeInfo") and api.GetRecipeInfo(entry.id) or nil
        local facts = {}
        if F.Table(info) then
            facts[#facts + 1] = "learned " .. tostring(info.learned)
            if info.craftable ~= nil then facts[#facts + 1] = "craftable " .. tostring(info.craftable) end
            if info.numAvailable ~= nil then facts[#facts + 1] = "can make " .. tostring(info.numAvailable) end
        end
        -- what the game counts it can make from the bags, against the crafts asked for, and the shape of the recipe's material slots (quantity x number of
        -- items a slot accepts): a count of 0, or a slot with several choices, would say why the call was ignored
        if F.Has(api, "GetCraftableCount") then
            local count = api.GetCraftableCount(entry.id)
            facts[#facts + 1] = "game counts " .. tostring(count) .. " of the " .. tostring(entry.crafts) .. " asked"
        end
        facts[#facts + 1] = "asked recipe " .. tostring(entry.id) .. " through " .. tostring(via) .. ", window shows recipe " .. tostring(F.SelectedRecipeID and F.SelectedRecipeID() or nil)
        -- whether the window's own Create All / Create button is enabled for it now: a disabled one means the game itself does not allow the craft
        local page = type(_G.ProfessionsFrame) == "table" and _G.ProfessionsFrame.CraftingPage or nil
        if type(page) == "table" then
            for _, key in ipairs({ "CreateAllButton", "CreateButton" }) do
                local button = page[key]
                if type(button) == "table" and F.Has(button, "IsEnabled") then facts[#facts + 1] = "window " .. key .. " enabled " .. tostring(button:IsEnabled()) end
            end
            -- the requirement text the window shows under the recipe, when it has one
            local form = page.SchematicForm
            if type(form) == "table" and type(form.Details) == "table" and type(form.Details.StatLines) == "table" then facts[#facts + 1] = "has stat lines" end
        end
        if F.Table(entry.recipe) and F.Table(entry.recipe.r) then
            local slots = {}
            for _, reagent in ipairs(entry.recipe.r) do slots[#slots + 1] = tostring(reagent.qty) .. "x" .. tostring(type(reagent.ids) == "table" and #reagent.ids or 0) end
            facts[#facts + 1] = "slots " .. table.concat(slots, " ")
        end
        F.Print("the game did not start " .. (F.String(entry.name) and entry.name or "the craft") .. ": "
            .. (seen and seen.error and ("it said \"" .. seen.error .. "\"") or "it gave no message")
            .. (#facts > 0 and ("; its own info: " .. table.concat(facts, ", ")) or "") .. "."
            .. (pending and " The window shows another recipe: click this one in its list, then here again (the addon does not select it for you: that blocks Create All)." or ""))
    end)
end

-- Starts Create All on an entry ({ id, crafts, ... }) the way the window's own button does (FOR-0195). Prints the chat line once per 10 s.
function C.Start(entry, text, onFail)
    local api = _G.C_TradeSkillUI
    if not F.Has(api, "CraftRecipe") then F.Print("this client has no function to start a craft."); return end
    -- double-click guard: a second click within half a second does nothing (and says so: a click that starts nothing must not be silent). It was 2 s,
    -- which blocked the human's next craft after stopping one ("press +, choose, it starts, stop it, press + and choose again").
    if not F.Throttle("craftclick", 0.5) then F.Print("wait a moment: a craft was just started."); return end
    -- (FOR-0214) The human's BugGrabber log (2026-11-27): "[ADDON_ACTION_BLOCKED] AddOn 'DeffarProfessionProfit' tried to call the protected function" with the stack
    -- CreateAll -> Blizzard_ProfessionsTransaction CraftRecipe -> this file: crafting is a protected call, and the game blocks it while the execution is
    -- tainted. The + crafted all the Hot Wolf Ribs, a recipe the human had selected in the window's list themselves; the Sliders were blocked after the
    -- addon had selected them (CraftingPage:SelectRecipe / OpenRecipe run in insecure code and leave the recipe data tainted until a secure selection
    -- replaces it). So the addon never selects a recipe for a craft: the selected recipe is crafted with the window's own Create All, any other with a plain
    -- CraftRecipe(id, n) (what the + button did on 2026-11-24), and when the game does not start it the player is told to select it in the window's list.
    local function Go(pending)
        F.skipTimeLine = entry.id   -- (this line has the time, so the CraftRecipe hook does not print its own for this call)
        local page = type(_G.ProfessionsFrame) == "table" and _G.ProfessionsFrame.CraftingPage or nil
        if type(page) ~= "table" then page = nil end
        local createAll, via   -- the window's Create All: its method, else a click on its button
        if page and F.Has(page, "CreateAll") then createAll, via = function() page:CreateAll() end, "CreateAll"
        elseif page and type(page.CreateAllButton) == "table" and F.Has(page.CreateAllButton, "Click") then createAll, via = function() page.CreateAllButton:Click() end, "the Create All button" end
        if createAll and F.SelectedRecipeID and F.SelectedRecipeID() == entry.id then
            createAll()
        else
            via = "CraftRecipe"
            api.CraftRecipe(entry.id, entry.crafts)
        end
        F.skipTimeLine = nil
        if F.Throttle("craftsay" .. entry.id, 10) then F.Print(text or C.Line(entry)) end
        WatchStart(entry, pending, via, onFail)
    end
    local selected = F.SelectedRecipeID and F.SelectedRecipeID() or nil
    Go(selected ~= nil and selected ~= entry.id)
end

function C.Click()
    local prof = C.WindowProfession()
    if not prof then F.Print("this is not one of your Profession Profit professions."); return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then F.Print("crafting cannot be started from here in combat."); return end
    local api = _G.C_TradeSkillUI
    if not F.Has(api, "CraftRecipe") then F.Print("this client has no function to start a craft."); return end
    -- a recipe chosen in the chooser is crafted by this click (its crafts counted again from the bags); a choice that can no longer be made is dropped
    if C.chosen then
        local chosen = C.chosen
        C.chosen = nil
        local crafts = F.Table(chosen.recipe) and C.Crafts(chosen.recipe) or 0
        if crafts >= 1 then
            chosen.crafts = crafts
            C.Start(chosen)
            return
        end
    end
    -- two or more recipes that gain money share a material you cannot cover for both: the player chooses which one (C.Conflict), but only after the
    -- crafts that share nothing with them (human: "craft Hot Wolf Ribs first, then when the next step includes the shared meat, the list appears")
    local group, free = C.Conflict(prof)
    if group then
        if free then C.Start(free, C.Line(free)); return end
        C.ToggleChooser(group)
        return
    end
    local text, ok, best = C.Plan(prof)
    if not ok then F.Print(text); return end
    C.Start(best, text)
end

-- Recipes that compete for the materials in the bags (human request, 2026-11-27: Lean Venison against Savory Stag Sliders, both made from the Stag
-- Meat held, one sold to a vendor and the other at the auction house). A recipe is a candidate when the bags allow a craft of it, its requirements
-- are met, every material is priced and it gains money in at least one of the two views: sold to a vendor, or sold at the auction house (less its
-- cut), either way minus what the materials cost now. Candidates compete when they share a material that is not a vendor supply (the meat, not the
-- spices: a vendor sells those) and the bags hold less of it than all of them would use for the crafts each could make. Returns the largest group
-- { entries = { { id, name, out, crafts, recipe, vendorProfit, ahProfit, value, total } most total first }, material = the shared item id }, or nil.
-- Losers in both views never take part: when only one gains money there is nothing to choose. The second value is the best craft that shares no
-- material with the group and earns something (the most profit per craft, requirements met), when there is one: it is made first.
function C.Conflict(prof)
    local sold = F.db and type(F.db.vendorBuy) == "table" and F.db.vendorBuy or {}
    local entries = {}
    for _, row in ipairs(F.BuildRows(prof) or {}) do
        local ev = row.ev
        if not row.unknown and F.Table(row.recipe) and F.Table(row.recipe.r) and F.Table(ev) and ev.complete == true and F.Number(ev.cost) then
            local crafts = C.Crafts(row.recipe)
            if crafts >= 1 and not C.Unmet(row.id) then
                local entry = Entry(row, crafts)
                entry.recipe, entry.cost = row.recipe, ev.cost
                -- what a craft brings in: the items a craft gives and the chance of one more (Master Chef), whatever the sell mode (Calc.Evaluate)
                if F.Number(ev.yield) then entry.factor = ev.yield + (F.Number(ev.chance) and ev.chance or 0) end
                local vendor, auction = C.VendorValue(entry), C.AuctionValue(entry)
                entry.vendorProfit = vendor and vendor - ev.cost or nil
                entry.ahProfit = auction and auction - ev.cost or nil
                local top = math.max(entry.vendorProfit or -math.huge, entry.ahProfit or -math.huge)
                if top > 0 then
                    entry.value, entry.total = top, top * crafts
                    entries[#entries + 1] = entry
                end
            end
        end
    end
    if #entries < 2 then return nil end
    -- who competes for what: the units of each bag material the crafts each could make would use
    local users = {}   -- item id -> { { entry, units } }
    for _, entry in ipairs(entries) do
        for _, reagent in ipairs(entry.recipe.r) do
            local first = type(reagent.ids) == "table" and reagent.ids[1] or nil
            if first and type(sold[first]) ~= "table" then
                local per = tonumber(reagent.qty) or 1
                for _, id in ipairs(reagent.ids) do
                    users[id] = users[id] or {}
                    users[id][#users[id] + 1] = { entry = entry, units = entry.crafts * per }
                end
            end
        end
    end
    local parent = {}
    local function Find(e) while parent[e] and parent[e] ~= e do e = parent[e] end return e end
    for _, entry in ipairs(entries) do parent[entry] = entry end
    local contended = {}   -- { item id, one entry that uses it } for every material the bags cannot cover for all its users
    for id, list in pairs(users) do
        if #list >= 2 then
            local units = 0
            for _, use in ipairs(list) do units = units + use.units end
            if units > F.Owned(id) then
                for index = 2, #list do
                    local a, b = Find(list[1].entry), Find(list[index].entry)
                    if a ~= b then parent[b] = a end
                end
                contended[#contended + 1] = { id = id, entry = list[1].entry }
            end
        end
    end
    table.sort(contended, function(a, b) return a.id < b.id end)
    local groups = {}
    for _, entry in ipairs(entries) do
        local root = Find(entry)
        groups[root] = groups[root] or { entries = {} }
        table.insert(groups[root].entries, entry)
    end
    local best
    for root, group in pairs(groups) do
        if #group.entries >= 2 then
            table.sort(group.entries, function(a, b)
                if a.total ~= b.total then return a.total > b.total end
                return a.id < b.id
            end)
            for _, c in ipairs(contended) do
                if Find(c.entry) == root then group.material = c.id; break end
            end
            if not best or group.entries[1].total > best.entries[1].total then best = group end
        end
    end
    if not best then return nil end
    local inGroup = {}
    for _, member in ipairs(best.entries) do inGroup[member.id] = true end
    local free
    local _, _, _, makeable = C.Best(prof)
    for _, candidate in ipairs(makeable or {}) do   -- (most profit first)
        if not inGroup[candidate.id] and F.Number(candidate.profit) and candidate.profit > 0 then free = candidate; break end
    end
    return best, free
end

-- The chooser: a small panel beside the "+" with one row per competing recipe. The pointer on a row lights it and dims the others; a click
-- starts Create All on that recipe, for all the crafts the bags allow it alone. It goes away on a click elsewhere, when the window closes,
-- and when the bags no longer hold a conflict.
local ROW_H, ROW_GAP, PAD = 26, 2, 6

local function Chooser()
    if C.flyout then return C.flyout end
    local W = F.UI.W
    local flyout = CreateFrame("Frame", nil, C.button)
    -- the widths of the columns: measured once, from the widest text each can hold
    local measure = W.Text(flyout, nil, W.GOLD, "LEFT")
    local function Width(text)
        measure:SetText(text)
        local width = math.ceil(measure:GetStringWidth() or 0)
        if width <= 0 then width = #(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 7 end   -- (a client that gives no width yet: a column of nothing hides its text)
        return width
    end
    flyout.amountW, flyout.viewW = Width(F.Style.Signed(999999)) + 2, Width("AH") + 2
    flyout.measureText = Width   -- (the name column is measured the same way, per opening)
    if F.Has(flyout, "SetFrameStrata") then flyout:SetFrameStrata("DIALOG") end
    flyout.fill, flyout.edges = W.Box(flyout, { 0.04, 0.04, 0.05 }, { 0.34, 0.34, 0.37 })
    flyout.rows = {}
    flyout:EnableMouse(true)
    flyout:SetScript("OnUpdate", function(self)
        if type(IsMouseButtonDown) == "function" and IsMouseButtonDown("LeftButton") and not (self:IsMouseOver() or (C.button and C.button:IsMouseOver())) then self:Hide() end
    end)
    flyout:Hide()
    C.flyout = flyout
    return flyout
end

local function RowTip(row)
    if type(GameTooltip) ~= "table" then return end
    local S, entry = F.Style, row.entry
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    S.StartRules()
    S.Title(GameTooltip, entry.name)
    if entry.vendorProfit then GameTooltip:AddLine(S.PerTotal(entry.vendorProfit, entry.vendorProfit * entry.crafts, "Sells:"), 1, 1, 1) end
    if entry.ahProfit then GameTooltip:AddLine(S.PerTotal(entry.ahProfit, entry.ahProfit * entry.crafts, "AH:"), 1, 1, 1) end
    GameTooltip:Show()
    S.FitRules(GameTooltip)
end

local GREY_BORDER = { 0.34, 0.34, 0.37 }

-- The rows' borders: the row the pointer is on is golden and the others are dimmed; the row that earns most in the view shown (the vendor view, or
-- the auction house view with Shift) has a green border whatever the view and even when every figure is a loss (then the smallest loss), and the
-- rest are grey. Two pixels thick, so it reads at a glance.
local function PaintBorders(flyout)
    local W = F.UI.W
    local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
    for _, row in ipairs(flyout.rows) do
        if row:IsShown() then
            local kind, color = nil, GREY_BORDER
            if flyout.lit == row then kind, color = "hover", W.GOLD
            elseif row.top then kind, color = "green", W.GREEN end
            row.borderKind = kind
            for index, edge in ipairs(row.edges) do
                W.Color(edge, color)
                if index <= 2 then edge:SetHeight(kind and 2 or 1) else edge:SetWidth(kind and 2 or 1) end
            end
            row.dimmed = flyout.lit ~= nil and flyout.lit ~= row   -- (the pointer is on another row)
            row:SetAlpha(row.dimmed and 0.35 or 1)
        end
    end
end

local function Dim(flyout, lit)
    flyout.lit = lit
    PaintBorders(flyout)
end

function C.HideChooser()
    if C.flyout then C.flyout:Hide() end
end

-- What every row of the chooser says now: without Shift the vendor view ("Sells" and the gain per craft when a vendor buys the result), with Shift
-- the auction house view ("AH" and the gain after its cut); "-" when that view has no price. The view label and the amount sit in the same columns
-- on every row (the amount right-aligned in a width that holds the largest figure the game shows, 99g 99s 99c).
function C.PaintChooser()
    local flyout = C.flyout
    if not (flyout and flyout:IsShown()) then return end   -- (a real frame has IsShown(), not the stub's `shown` field)
    local S = F.Style
    local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
    local topRow, topTotal
    for _, row in ipairs(flyout.rows) do
        local entry = row.entry
        if row:IsShown() and entry then
            local profit = entry.vendorProfit
            if shift then profit = entry.ahProfit end   -- (not "a and b or c": no AH price must stay "-", not fall back to the vendor figure)
            row.view:SetText(shift and S.Paint(S.GOLDCODE, "AH") or "")   -- (the vendor view needs no label)
            row.value:SetText(profit and S.Signed(profit) or S.Grey("-"))
            row.top = false
            -- the one that earns most in this view: the most total from the crafts the bags allow, a loss too (the smallest loss); a row with no price
            -- in this view does not take part
            if profit and (not topTotal or profit * entry.crafts > topTotal) then topRow, topTotal = row, profit * entry.crafts end
        end
    end
    if topRow then topRow.top = true end
    PaintBorders(flyout)
end

function C.ToggleChooser(group)
    local flyout = Chooser()
    if flyout:IsShown() then flyout:Hide(); return end
    local S, W = F.Style, F.UI.W
    -- the name column is as wide as the longest "Name xN" and no wider: the least distance from the names to the columns on their right
    local labels, nameW = {}, 0
    for index, entry in ipairs(group.entries) do
        local meta = F.ItemMeta(entry.out)
        labels[index] = S.Paint(S.QualityCode(meta.quality or 1), entry.name) .. " " .. S.Paint(S.SAND, "x" .. entry.crafts)
        nameW = math.max(nameW, flyout.measureText(labels[index]))
    end
    nameW = nameW + 2
    flyout.rowW = 5 + 18 + 6 + nameW + 8 + flyout.viewW + 8 + flyout.amountW + 6
    for index, entry in ipairs(group.entries) do
        local row = flyout.rows[index]
        if not row then
            row = W.MakeButton(flyout, "", flyout.rowW, ROW_H)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", row, "LEFT", 5, 0)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.label:SetJustifyH("LEFT")
            -- the pointer on the icon shows the item itself, as every icon in the addon does (UI.lua MakeIconTip); the row stays lit while it is there
            W.MakeIconTip(row, function(r) return r.entry and r.entry.out end)
            row.iconHit:HookScript("OnEnter", function() Dim(flyout, row) end)
            -- from the right: the amount (right-aligned), then the view label ("AH" with Shift)
            row.value = W.Text(row, nil, W.GOLD, "RIGHT")
            row.value:SetWidth(flyout.amountW)
            row.value:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.view = W.Text(row, nil, W.GOLD, "LEFT")
            row.view:SetWidth(flyout.viewW)
            row.view:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
            row:HookScript("OnEnter", function(self) Dim(flyout, self); RowTip(self) end)
            row:HookScript("OnLeave", function() Dim(flyout, nil); if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
            row:SetScript("OnClick", function(self)
                local picked = self.entry
                if not picked then
                    flyout:Hide()
                    F.Print("the chooser row has no recipe: close it and press + again.")
                    return
                end
                -- (FOR-0214) ONE click again, tried the way Codex ranked first (2026-11-27 discussion): the craft is asked for BEFORE the panel is hidden (the earlier
                -- version hid it first and the game blocked the call, "protected function"; the cause was never established, hiding the click's own
                -- ancestor is one suspect). When the game still does not start it, the choice is kept and the player is told to click the +, the path
                -- that started a craft in game (the Hot Wolf Ribs, then the Sliders on 2026-11-27).
                C.Start(picked, nil, function()
                    C.chosen = picked
                    F.Print("chosen " .. (F.String(picked.name) and picked.name or "the recipe") .. " x" .. tostring(picked.crafts) .. ": click + to craft it.")
                end)
                flyout:Hide()
            end)
            flyout.rows[index] = row
        end
        row.entry = entry
        local meta = F.ItemMeta(entry.out)
        row.icon:SetTexture(meta.icon)
        row.label:SetText(labels[index])
        row.label:SetWidth(nameW)
        row:SetWidth(flyout.rowW)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", flyout, "TOPLEFT", PAD, -(PAD + (index - 1) * (ROW_H + ROW_GAP)))
        row:SetAlpha(1)
        row:Show()
    end
    for index = #group.entries + 1, #flyout.rows do flyout.rows[index]:Hide() end
    flyout:SetSize(flyout.rowW + PAD * 2, PAD * 2 + #group.entries * ROW_H + (#group.entries - 1) * ROW_GAP)
    flyout:ClearAllPoints()
    flyout:SetPoint("LEFT", C.button, "RIGHT", 4, 0)
    flyout:Show()
    C.PaintChooser()
end

local function Tip(button)
    if type(GameTooltip) ~= "table" then return end
    local S = F.Style   -- the palette every Profession Profit tooltip uses (Style.lua), not colours of its own
    local prof = C.WindowProfession()
    local best, any, skipped, makeable = C.Best(prof or "cooking")
    local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    S.StartRules()
    S.Title(GameTooltip, shift and "Create All (AH)" or "Create All")
    if C.chosen then S.Good(GameTooltip, "Chosen: " .. tostring(C.chosen.name) .. ". Click to craft it.") end
    local group, free
    if prof then group, free = C.Conflict(prof) end
    if group then
        local material = F.ItemMeta(group.material).name or "A material"
        S.Reason(GameTooltip, free and (free.name .. " first, then choose between the recipes that share " .. material .. ".") or (material .. " is shared: click to choose a recipe."))
    end
    if prof then
        -- laid out like the vendor "+" (Vendor.lua): a rule under the title, then per dish
        --   Craft: [icon] Item xN
        --   +V per (T total): the vendor price of a craft, with Shift the auction house price after the cut
        --   a rule before the next dish. Every recipe the bags allow and whose requirements are met, the most profitable first (that is
        --   the one a click makes); when a requirement (a fire, an Iron Oven) keeps every one of them from starting, the recipes it holds
        --   back are listed the same way. Below them the dishes the meat could make if the supplies were there:
        --   Craft: [icon] Item xN
        --   Missing: [icon] Supply xY      (one line for each supply lacking)
        local _, ok = C.Plan(prof)
        local listed = (#makeable == 0 and not ok) and skipped or makeable
        local shortages = C.Shortages(prof)
        if #listed > 0 or #shortages > 0 then S.Rule(GameTooltip) end
        for index, entry in ipairs(listed) do
            if index > 8 then GameTooltip:AddLine("...", S.DIM[1], S.DIM[2], S.DIM[3]); break end
            if index > 1 then S.Rule(GameTooltip) end
            GameTooltip:AddLine(S.Paint(S.GOLDCODE, "Craft: ") .. S.ItemQty(entry.out, entry.name, entry.crafts, S.SAND), 1, 1, 1)
            -- what one craft sells for: to a vendor, or with Shift held at the auction house (after its cut), both whatever the sell mode
            local value = shift and C.AuctionValue(entry) or (not shift and C.VendorValue(entry)) or nil
            if value then
                GameTooltip:AddLine(S.PerTotal(value, value * entry.crafts, shift and "AH:" or "Sells:"), 1, 1, 1)
            else
                GameTooltip:AddLine(S.Grey(shift and "No auction house price." or "A vendor does not buy it."), 1, 1, 1)
            end
        end
        for index, short in ipairs(shortages) do
            if index > 3 then GameTooltip:AddLine("...", S.DIM[1], S.DIM[2], S.DIM[3]); break end
            if index > 1 or #listed > 0 then S.Rule(GameTooltip) end
            GameTooltip:AddLine(S.Paint(S.GOLDCODE, "Craft: ") .. S.ItemQty(short.out, short.name, short.crafts, S.SAND), 1, 1, 1)
            for _, m in ipairs(short.missing) do
                GameTooltip:AddLine(S.Paint(S.RED, "Missing:") .. " " .. S.ItemQty(m.id, F.ItemMeta(m.id).name or ("Item " .. m.id), m.need, S.SAGE), 1, 1, 1)
            end
        end
        -- greyed out: a short reason in the tooltip's grey (the missing requirements are named only here, not in the chat line)
        if not ok then
            local missing, seen = {}, {}
            for _, s in ipairs(skipped) do
                for _, name in ipairs(s.names or {}) do
                    if not seen[name] then seen[name] = true; missing[#missing + 1] = name end
                end
            end
            -- (with only a requirement missing, the items listed above are what you hold the materials for: no sentence needed)
            if not (#makeable == 0 and #missing > 0) and #shortages == 0 then S.Reason(GameTooltip, any and "A price is missing." or "No materials.") end
            if #missing > 0 then
                local shown = {}
                for index, name in ipairs(missing) do
                    local icon = C.RequirementIcon(name)
                    shown[index] = (icon and ("|T" .. tostring(icon) .. ":0|t ") or "") .. name
                end
                S.Missing(GameTooltip, table.concat(shown, ", "))
            end
        end
    end
    GameTooltip:Show()
    S.FitRules(GameTooltip)
end

-- Where the window's own Create All / quantity box / Create row is, as a height above the window's bottom edge, and how tall its
-- buttons are (nil when the window does not say): the "+" is put on that row, outside the window's right edge.
local function CreateRow(parent)
    local page = parent.CraftingPage
    local create = type(page) == "table" and (page.CreateButton or page.CreateAllButton) or nil
    if type(create) == "table" and F.Has(create, "GetCenter") and F.Has(parent, "GetBottom") then
        local _, centre = create:GetCenter()
        local bottom = parent:GetBottom()
        if F.Number(centre) and F.Number(bottom) then
            return centre - bottom, F.Has(create, "GetHeight") and create:GetHeight() or nil
        end
    end
    return nil
end

-- Puts the button on that row (or, when the window has no such row to read, at its bottom right corner).
function C.Place()
    local parent, button = _G.ProfessionsFrame, C.button
    if not (button and type(parent) == "table") then return end
    button:ClearAllPoints()
    local y = CreateRow(parent)   --
    if y then
        button:SetPoint("LEFT", parent, "BOTTOMRIGHT", 4, y)
    else
        button:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 4, 30)
    end
end

-- Creates the button on the profession window the first time it is needed (ProfessionsFrame is the usual name; with no such frame there
-- is no button and /dpp status says so).
function C.EnsureButton()
    if C.button then return C.button end
    local parent = _G.ProfessionsFrame
    if type(parent) ~= "table" or not F.Has(parent, "GetFrameLevel") or not F.UI or not F.UI.W then
        C.noFrame = true
        return nil
    end
    local button = F.UI.W.MakeButton(parent, "+", 35, 29)   --
    if F.Has(button.label, "SetFontObject") then button.label:SetFontObject("GameFontNormalLarge") end
    button:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 4, 30)   -- (C.Place puts it on the Create row)
    button.accent = F.UI.W.GOLD
    button.label:SetTextColor(F.UI.W.GOLD[1], F.UI.W.GOLD[2], F.UI.W.GOLD[3])
    button:SetScript("OnClick", function() C.Click() end)
    button:HookScript("OnEnter", function(self) C.hover = true; Tip(self) end)
    button:HookScript("OnLeave", function() C.hover = false; if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    -- pressing or releasing Shift while the pointer is on the button redraws the tooltip
    button:RegisterEvent("MODIFIER_STATE_CHANGED")
    button:SetScript("OnEvent", function(self)
        if C.hover then Tip(self) end
        C.PaintChooser()   -- (an open chooser shows the vendor view, or the auction house view while Shift is held)
    end)
    -- the golden / grey state follows what changes without a bag change (walking away from a cooking fire): checked once a second
    -- while the button is shown, and the tooltip with it while the pointer is on the button
    local waited = 0
    button:SetScript("OnUpdate", function(self, elapsed)
        waited = waited + (elapsed or 0)
        if waited < 1 then return end
        waited = 0
        if self:IsShown() then
            C.Refresh()
            if C.hover then Tip(self) end   -- a tooltip open on the button is redrawn too
        end
    end)
    button:HookScript("OnHide", function() C.HideChooser(); C.chosen = nil end)
    button:Hide()
    C.button = button
    return button
end

-- Shows the button on a window of one of the saved professions, hides it otherwise.
function C.Refresh()
    local window = _G.ProfessionsFrame
    if type(window) ~= "table" or type(window.IsShown) ~= "function" or not window:IsShown() then
        if C.button then C.button:Hide() end
        return
    end
    local button = C.EnsureButton()
    if button then
        local prof = C.WindowProfession()
        button:SetShown(prof ~= nil)
        C.Place()
        -- a golden border when a craft would start (materials held, requirements met, it pays), greyed out when none would
        if prof then
            local _, ready = C.Plan(prof)
            F.UI.W.SetReady(button, ready)
            if C.flyout and C.flyout:IsShown() and not C.Conflict(prof) then C.HideChooser() end   -- (the bags changed: nothing left to choose)
        end
    end
end
