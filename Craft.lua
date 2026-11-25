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

-- The profession (cooking, engineering, tailoring) the open window is, or nil when it is neither one of those nor the player's own.
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
    return { id = row.id, name = row.name, profit = ev and ev.profit, crafts = crafts, out = row.recipe.out, expected = ev and ev.expected,
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
    if F.Has(_G.C_Item, "GetItemInfo") and F.Integer(best.out, 1, MAX) then
        local _, link = _G.C_Item.GetItemInfo(best.out)
        if F.String(link) and link ~= "" then return link end
    end
    return best.name
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
    local each, source = F.CraftSeconds(best.id)
    return string.format("%s x%d | %s%s", ItemText(best), best.crafts, (source == "default" or source == "scaled") and "~" or "", F.DurationText(best.crafts * each)),
        true, best, why
end

function C.Click()
    local prof = C.WindowProfession()
    if not prof then F.Print("this is not one of your Profession Profit professions."); return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then F.Print("crafting cannot be started from here in combat."); return end
    local api = _G.C_TradeSkillUI
    if not F.Has(api, "CraftRecipe") then F.Print("this client has no function to start a craft."); return end
    local text, ok, best = C.Plan(prof)
    if not ok then F.Print(text); return end
    -- spam guard: a second click within 2 s does nothing, and the same recipe's line is printed once per 10 s
    if not F.Throttle("craftclick", 2) then return end
    F.skipTimeLine = best.id   -- (this line has the time, so the CraftRecipe hook does not print its own for this call)
    api.CraftRecipe(best.id, best.crafts)
    F.skipTimeLine = nil
    if F.Throttle("craftsay" .. best.id, 10) then F.Print(text) end
end

local function Tip(button)
    if type(GameTooltip) ~= "table" then return end
    local S = F.Style   -- the palette every Profession Profit tooltip uses (Style.lua), not colours of its own
    local prof = C.WindowProfession()
    local best, any, skipped, makeable = C.Best(prof or "cooking")
    local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    S.Title(GameTooltip, shift and "Create All (AH)" or "Create All")
    if prof then
        -- every recipe the bags allow and whose requirements are met, the most profitable first (that is the one a click makes);
        -- when a requirement (a fire, an Iron Oven) keeps every one of them from starting, the recipes it holds back are listed the same way:
        --   [icon] Item xN
        --   +V per (T total): the vendor price of a craft, with Shift the auction house price after the cut
        local _, ok = C.Plan(prof)
        local listed = (#makeable == 0 and not ok) and skipped or makeable
        for index, entry in ipairs(listed) do
            if index > 8 then GameTooltip:AddLine("...", S.DIM[1], S.DIM[2], S.DIM[3]); break end
            GameTooltip:AddLine(S.ItemQty(entry.out, entry.name, entry.crafts, S.SAND), 1, 1, 1)
            -- what one craft sells for: to a vendor, or with Shift held at the auction house (after its cut), both whatever the sell mode
            local value = shift and C.AuctionValue(entry) or (not shift and C.VendorValue(entry)) or nil
            if value then
                GameTooltip:AddLine(S.PerTotal(value, value * entry.crafts), 1, 1, 1)
            else
                GameTooltip:AddLine(S.Grey(shift and "No auction house price." or "A vendor does not buy it."), 1, 1, 1)
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
            if not (#makeable == 0 and #missing > 0) then S.Reason(GameTooltip, any and "A price is missing." or "No materials.") end
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
    button:SetScript("OnEvent", function(self) if C.hover then Tip(self) end end)
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
        end
    end
end
