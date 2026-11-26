-- Deffar Profession Profit: the luck window (/dpp luck). One row per cooked item (icon and name, like the
-- Delete Junk and Loot Value lists) with its crafts, extra results, expected extras, the real extra-result
-- percentage and luck in standard deviations, and the money outcome: materials spent and the vendor value
-- of what was made, for this session, this character or the whole account. A total row sums them and the
-- text under it gives the outcome beside what average luck would have made. It repaints on every counted
-- craft (Core.lua calls LuckUI.Refresh). Per-rank figures are in each row's tooltip. The widgets come from
-- UI.lua (U.W). Plain addon-owned frames only.
--
-- Tabs: one per profession, like the main window. Cooking has every column; a profession
-- with no extra-result chance (Engineering) has no luck, so its tab shows only item, crafts, spent, gained, profit and
-- per hour, in a narrower window.
local _, F = ...
local U = {}
F.LuckUI = U

local W = F.UI.W
local SIDE, ROW_H, ROW_GAP, ICON = 8, 22, 1, 16
local WIDTH = F.Style.BASE_WIDTH   -- the window's width now: ApplyLayout sets it (Style.Columns)
local need = F.Style.BASE_WIDTH    -- the least width this tab's columns fit in (the main window reads it, NaturalWidth)
local need_h = 0                   -- the height its content needs (NaturalHeight)
local armed = nil   -- the AH sales row whose delete button was clicked once (its item name): the next click deletes it
local GAP, COL_PAD, NAME_MIN = 6, 2, 100   -- the gap between columns, their padding, the name column's least width (it takes the rest)
local TAB_SHIFT = W.TAB_SHIFT          -- the tab row under the title bar pushes everything below it down
local FILTER_Y, HEAD_Y = 36 + TAB_SHIFT, 62 + TAB_SHIFT   -- the scope row (Session / Character / Lifetime), then the headings
local ROWS_Y = 80 + TAB_SHIFT
local MAX_ROWS = 14   -- rows on a page: what fits the main window's height with the Total row and the footer
local page = 1         -- the page shown (1 = the first MAX_ROWS rows of the sorted list)
local search = ""      -- the search box's text, lower case: only items whose name contains it are listed; not saved

-- The columns after the name. Their widths are their content's (ApplyLayout, Style.Columns), not fixed.
local COLS = {
    { key = "c",      head = "Crafts" },
    { key = "x",      head = "Extras" },
    { key = "exp",    head = "Expected" },
    { key = "real",   head = "Real %" },
    { key = "luck",   head = "Luck" },
    { key = "spent",  head = "Spent" },
    { key = "gained", head = "Gained" },
    { key = "profit", head = "Profit" },
    { key = "hour",   head = "Per hr" },
    { key = "avg",    head = "Each" },     -- the Enchanting tab only: gained per disenchant
}
local NAME_X, NAME_W = SIDE + 3 + ICON + 5, 150
local BTN_W, BTN_H = W.ABTN, ROW_H - 6   -- the size of the main window's [A] button: the check box and the delete button are the same
local CHECK_W = W.ABTN + 4          -- a recipe tab's rows start the icon and name this much further right (as after the [A] button): the "sold at the AH" check
local DEL_RED, DEL_RED_HOVER = { 0.80, 0.12, 0.12 }, { 1, 0.30, 0.30 }   -- the delete button's disc
local CHECK_X = 3                   -- sits to the left of them, this far from the row's left edge (where the [A] button is)

-- Which columns a kind of tab shows, left to right. A profession with an extra-result chance (Cooking) shows crafts, extras and the
-- extra %; one without (Engineering, Tailoring) only the crafts and the money.
local KEYS_PROC = { "c", "x", "real", "spent", "gained", "profit", "hour" }
local KEYS_PLAIN = { "c", "spent", "gained", "profit", "hour" }
-- Disenchanting (Luck.lua): the count, what it gave, and that per disenchant; nothing is spent or crafted.
local KEYS_DISENCHANT = { "c", "spent", "gained", "profit", "avg" }
-- AH sales (Sales.lua): the same cells read as listed, sold, unsold, deposits paid, money received, profit and profit per item sold
-- (money received less deposits less the crafting cost of what was sold).
local KEYS_SALES = { "c", "x", "exp", "spent", "gained", "profit", "avg" }
local SALES = { heads = { c = "Listed", x = "Sold", exp = "Unsold", spent = "Deposits", gained = "Received", profit = "Profit", avg = "Profit each" } }

-- Whether THIS character's own counts hold anything for a profession: such a tab stays even when the skill reads as not
-- learned (a dropped profession keeps its history). Other characters' counts in the account-wide totals do not keep it
--.
local function HasLuck(key)
    if key == "auction" then return true end   -- (its tab explains itself while empty)
    local char = F.Char()
    for _, entry in pairs(char and char.luck or {}) do
        if type(entry) == "table" and (entry.prof or "cooking") == key then return true end
    end
    return false
end

local function ProfKey()
    local key = F.db and F.db.luckTab
    local def = F.TabDef(key)
    return (def and (def.store or def.disenchant or def.sales)) and key or "cooking"
end

-- The keys of the columns a profession's tab shows.
local function TabKeys(prof)
    local def = F.TabDef(prof)
    if def.sales then return KEYS_SALES end
    if def.disenchant then return KEYS_DISENCHANT end
    return def.proc and KEYS_PROC or KEYS_PLAIN
end

-- Whether a tab shows a column.
local function KeyShown(prof, key)
    for _, k in ipairs(TabKeys(prof)) do
        if k == key then return true end
    end
    return false
end

local frame, rows = nil, {}

local function Scope()
    local scope = F.db and F.db.luckScope
    return (scope == "char" or scope == "life") and scope or "session"
end

-- A scope button: gold text and underline when it is the one in use, lighter grey text under the pointer.
local function PaintScope(scope)
    local color = scope.selected and W.GOLD or (scope.hover and W.TEXT or W.GREY)
    scope.label:SetTextColor(color[1], color[2], color[3])
    scope.marker:SetShown(scope.selected == true)
end

local function Percent(value) return string.format("%.1f%%", value * 100) end

local function LuckText(z)
    if not F.Number(z) then return "-", W.GREY end
    return string.format("%+.1f SD", z), (z > 0.5 and W.GREEN) or (z < -0.5 and W.RED) or W.TEXT
end

-- The AH sales tab's cells (Sales.lua): a "*" on the net when some units were listed before the addon was watching.
local function SalesCells(r)
    return {
        c = { tostring(r.c), W.TEXT }, x = { tostring(r.x), W.TEXT }, exp = { tostring(r.o), W.TEXT },
        spent = { F.Money(r.d), W.TEXT }, gained = { F.Money(r.m), W.TEXT },
        profit = { F.ProfitText(r.profit or r.net) .. (r.partial and " |cffff9933*|r" or ""), W.TEXT },
        avg = r.x > 0 and { F.ProfitText(math.floor((r.profit or r.net) / r.x)), W.TEXT } or { "-", W.GREY },
    }
end

-- Cell texts for one item (or the total, which has the same fields): { [key] = { text, color } }.
local function Cells(r)
    if ProfKey() == "auction" then return SalesCells(r) end
    local cells = {
        c = { tostring(r.c), W.TEXT }, x = { tostring(r.x), W.TEXT },
        exp = { string.format("%.1f", r.expected), W.TEXT },
        real = { r.c > 0 and Percent(r.x / r.c) or "-", W.TEXT },
    }
    local rankZero = r.ranks and r.ranks[0] and r.ranks[0].x > 0
    if rankZero then cells.luck = { "extras?!", W.RED }   -- nothing is expected at rank 0: the assumption would be wrong
    else cells.luck = { LuckText(r.z) } end
    -- the money: the vendor figures, or for an item marked as sold at the AH its crafts at today's AH prices (Luck.lua ahView), as the
    -- "Auction House" row under the Total does for all of those together; "AH" when Auctionator has no price for it
    local m = r
    if r.ah then m = r.ahView or { k = 0 } end
    if r.ah and not r.ahView then
        cells.spent, cells.gained, cells.profit, cells.hour = { "AH", W.GREY }, { "AH", W.GREY }, { "AH", W.GREY }, { "AH", W.GREY }
    elseif m.k > 0 then
        local star = m.u > 0 and " |cffff9933*|r" or ""
        cells.spent = { F.Money(m.s) .. star, W.TEXT }
        cells.gained = { F.Money(m.g) .. star, W.TEXT }
        local profit = m.g - m.s
        cells.profit = { F.ProfitText(profit), W.TEXT }   -- "+45s" in green, "-20s" in red (the text carries its colour)
        -- profit per hour of casting: the real profit of the priced crafts over their casting time (crafts x seconds
        -- per craft), so it follows how many were cooked; buying and selling time are not in it
        if m.secs and m.secs > 0 then
            cells.hour = { F.ProfitText(profit * 3600 / m.secs) .. " |cff8a8a8a/hr|r", W.TEXT }
        else
            cells.hour = { "-", W.GREY }
        end
    else
        cells.spent, cells.gained, cells.profit, cells.hour = { "-", W.GREY }, { "-", W.GREY }, { "-", W.GREY }, { "-", W.GREY }
    end
    cells.avg = (m.k > 0 and (not r.ah or r.ahView)) and { F.Money(math.floor(m.g / m.k)), W.TEXT } or { "-", W.GREY }
    return cells
end

local function Fill(cellTable, cells, color)
    for key, text in pairs(cellTable) do
        local cell = cells[key]
        if cell then
            text:SetText(cell[1])
            local c = cell[2] or color or W.TEXT
            text:SetTextColor(c[1], c[2], c[3])
        end
    end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

-- The tooltips. A row has two: over the item column the short facts about the item (ShowTip), over the Profit cell how that profit was
-- worked out with the real figures. Their colours and line helpers are Style.lua's, shared
-- with the main window.
local St = F.Style
local DIM, Line, Note, Signed, Paint = St.DIM, St.Line, St.Note, St.Signed, St.Paint
local SAGE, SAND = St.SAGE, St.SAND
local Items, Crafts, Seconds, Grey, ItemLabel = St.Items, St.Crafts, St.Seconds, St.Grey, St.ItemLabel

-- What each control of the window says on hover: the same short labelled lines as the main window's toolbar (UI.lua ShowControlTip).
local TIPS = {}
function TIPS.ah() return { "Sold at AH", { "Counts", "at AH prices" }, { "Row", "Auction House, not Vendor" } } end
function TIPS.del(armed)
    if armed then return { "Delete row", { text = "Click again to delete", color = { 1, 0.4, 0.4 } } } end
    return { "Delete row", { "Scope", "this one only" }, { hint = "Click twice" } }
end
function TIPS.edit() return { "Add sales", { "For", "mail looted without the addon" } } end
function TIPS.back() return { "Profession Profit", { hint = "Click: Back" } } end
function TIPS.session() return { "Session", { "Counts", "since login or reload" } } end
function TIPS.char() return { "Character", { "Counts", "this character, saved" } } end
function TIPS.life() return { "Lifetime", { "Counts", "all characters, saved" } } end
function TIPS.reset() return { "Reset session", { "Clears", "this session's counts" } } end
function TIPS.crafted() return { "Crafted", { "Shows", "items you crafted" }, { "Untick", "every item you sold" } } end
function TIPS.search() return { "Search", { "Matches", "part of an item's name" }, { "Total row", "counts the whole list" }, { "Esc", "clears" } } end
function TIPS.market()
    return { "Current Market Values", { "Counts", "units at today's AH price" }, { "Minus", St.Percent("5%") .. " cut, deposit back" }, { "Unticked", "type the money" } }
end

-- Over the item column: what the item is and how many were counted.
local function ShowTip(row, refresh)
    local item = row.item
    if not item or type(GameTooltip) ~= "table" then return end
    local tip = W.NewTip()    -- the lines are collected first; ShowLines puts them on the tooltip (see NewTip)
    W.RememberTip(row, ShowTip)
    tip:AddLine(item.name, W.GOLD[1], W.GOLD[2], W.GOLD[3])
    local prof = item.prof or "cooking"
    if prof == "auction" then
        Line(tip, "Listed", Paint(SAGE, tostring(item.c)) .. (item.a > 0 and Grey("  (" .. item.a .. " auctions)") or ""))
        Line(tip, "Sold", Paint(SAGE, tostring(item.x)))
        Line(tip, "Unsold, not up again", Paint(SAGE, tostring(item.o)))
        if item.r > 0 then Line(tip, "Put up again", Paint(SAGE, tostring(item.r))) end
        Line(tip, "Still listed or in the mail", Paint(SAGE, tostring(item.waiting)))
        if item.partial then Note(tip, "Some listed before this was watched") end
        W.ShowLines(row, tip, refresh)
        return
    end
    local proc = F.PROFESSIONS[prof].proc
    if F.PROFESSIONS[prof].disenchant then
        St.Hint(tip, "Shift-click: Results vs the table")
        Line(tip, "Disenchanted", Paint(SAGE, tostring(item.c)))
        local list = {}
        for id, quantity in pairs(item.res or {}) do list[#list + 1] = { id = id, quantity = quantity } end
        table.sort(list, function(a, b)
            if a.quantity ~= b.quantity then return a.quantity > b.quantity end
            return a.id < b.id
        end)
        for _, entry in ipairs(list) do
            tip:AddDoubleLine("  " .. ItemLabel(entry.id), Paint(SAGE, tostring(entry.quantity)) .. Grey(string.format(" (%.2f each)", item.c > 0 and entry.quantity / item.c or 0)), 1, 1, 1, 1, 1, 1)
        end
        W.ShowLines(row, tip, refresh)
        return
    end
    if proc then
        Line(tip, "Makes per craft", Paint(SAGE, tostring(item.y)))
        Line(tip, "Crafts", Paint(SAND, tostring(item.c)))
        Line(tip, "Extras", Paint(SAGE, tostring(item.x)))
        local used = 0
        for rank = 0, F.RANK_MAX do if item.ranks[rank] then used = used + 1 end end
        if used > 1 then   -- (crafted at more than one rank: how each rank went)
            for rank = 0, F.RANK_MAX do
                local r = item.ranks[rank]
                if r then Line(tip, string.format("Master Chef %d/%d", rank, F.RANK_MAX), Crafts(r.c) .. Grey(", ") .. Paint(SAGE, r.x .. " extra")) end
            end
        end
        if item.o > 0 then Note(tip, item.o .. " odd-quantity crafts left out") end
    else
        Line(tip, "Crafts", Paint(SAND, tostring(item.c)))
    end
    if item.ah then Note(tip, "Sold at AH: AH prices, Auction House row") end
    W.ShowLines(row, tip, refresh)
end

-- Over the Profit cell: the profit worked out, with the figures behind it.
local function ShowProfitTip(row, refresh)
    local item = row.item
    if not item or type(GameTooltip) ~= "table" then return end
    local tip = W.NewTip()
    W.RememberTip(row, ShowProfitTip)
    tip:AddLine("Profit: " .. item.name, W.GOLD[1], W.GOLD[2], W.GOLD[3])
    local prof = item.prof or "cooking"
    if prof == "auction" then
        Line(tip, "Received (after the 5% cut)", F.Money(item.m))
        Line(tip, "Deposits paid", F.Money(item.d))
        if item.c + item.r > 0 and item.o + item.r > 0 then
            Line(tip, "  lost on units that came back", F.Money(math.floor(item.d * (item.o + item.r) / (item.c + item.r))))
        end
        Line(tip, "Received less deposits", Signed(item.net))
        if item.unitCost then
            Line(tip, Grey("Crafting: ") .. Paint(SAGE, item.x .. " sold") .. Grey(" x ") .. F.Money(math.floor(item.unitCost)), F.Money(item.crafting))
        elseif item.x > 0 then
            Note(tip, "No crafting cost: auctions only")
        end
        Line(tip, "Profit", Signed(item.profit))
        if item.x > 0 then Line(tip, "Per unit sold", Signed(math.floor(item.profit / item.x))) end
        W.ShowLines(row, tip, refresh)
        return
    end
    if F.PROFESSIONS[prof].disenchant then
        if item.k > 0 then
            Line(tip, "Spent (AH price paid, else Auctionator)", F.Money(item.s))
            Line(tip, "Gained (results at AH prices, less the cut)", F.Money(item.g))
            Line(tip, "Profit", Signed(item.g - item.s))
            Line(tip, "Per disenchant", Signed(math.floor((item.g - item.s) / item.k)))
            if item.u > 0 then Note(tip, item.u .. " unpriced disenchants left out") end
        else
            tip:AddLine("No money figures yet.", DIM[1], DIM[2], DIM[3], true)
        end
        W.ShowLines(row, tip, refresh)
        return
    end
    local view = item.ahView   -- sold at the AH: the crafts at today's Auctionator price less the cut
    if item.ah and not view then
        Note(tip, "No AH price: see the AH sales tab")
    elseif view or item.k > 0 then
        local made = view and view.g or item.g
        local profit = made - item.s
        local units = item.c * (F.Number(item.y) and item.y or 1) + item.x
        if view then
            Line(tip, Grey("Made: ") .. Items(math.floor(view.units + 0.5)) .. Grey(" x ") .. F.Money(view.net) .. Grey(" (AH, after the cut)"), F.Money(made))
        elseif item.u == 0 and units > 0 then
            Line(tip, Grey("Made: ") .. Items(units) .. Grey(" x ") .. F.Money(math.floor(item.g / units)), F.Money(item.g))
        else
            Line(tip, "Made, at the vendor price", F.Money(item.g))
        end
        Line(tip, Grey("Materials: ") .. Crafts(item.k) .. Grey(" x ") .. F.Money(math.floor(item.s / item.k)), F.Money(item.s))
        Line(tip, "Profit", Signed(profit))
        if item.secs and item.secs > 0 then Line(tip, "Per hour", Signed(profit * 3600 / item.secs)) end
    else
        tip:AddLine("No money figures: no price or vendor sale", DIM[1], DIM[2], DIM[3], true)
    end
    -- the materials: what the counted crafts really used (each from the oldest purchases first, Bought.lua lots), or, for crafts
    -- counted before lots were kept, the recipe with the price the next unit would be counted at
    local char = F.Char()
    local recipe = char and (F.RecipesOf(char, prof) or {})[item.id]
    local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
    local hasMaterials = (type(item.mats) == "table" and next(item.mats) ~= nil)
        or (not item.ah and type(recipe) == "table" and type(recipe.r) == "table" and #recipe.r > 0)
    if hasMaterials and not shift then
        St.Hint(tip, "Shift: Materials used")   -- (the list of what the crafts used is shown while Shift is held)
    elseif type(item.mats) == "table" and next(item.mats) ~= nil then
        tip:AddLine(" ")
        tip:AddLine("Materials used (oldest purchases first)", DIM[1], DIM[2], DIM[3])
        local ids = {}
        for id in pairs(item.mats) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local m = item.mats[id]
            if type(m) == "table" and F.Number(m.n) and m.n > 0 then
                local right = F.Money(math.floor(m.c / m.n + 0.5)) .. " each"
                if (m.m or 0) >= m.n then right = right .. " |cff8a8a8amarket price|r"
                elseif (m.m or 0) > 0 then right = right .. " |cff8a8a8a(" .. m.m .. " of " .. m.n .. " at market)|r"
                else right = right .. " |cff8a8a8afrom your purchases|r" end
                tip:AddDoubleLine("  " .. ItemLabel(id) .. " " .. Paint(SAGE, "x" .. m.n), right, 1, 1, 1, 1, 1, 1)
            end
        end
    elseif not item.ah and type(recipe) == "table" and type(recipe.r) == "table" and #recipe.r > 0 then
        tip:AddLine(" ")
        tip:AddLine("Materials per craft (no purchase detail)", DIM[1], DIM[2], DIM[3], true)
        for _, reagent in ipairs(recipe.r) do
            local unit, source, units, id = F.Luck.MaterialPrice(reagent)
            local right
            if not unit then right = "|cffff9933no price|r"
            elseif source == "paid" then right = F.Money(unit) .. " |cff8a8a8anext purchase used|r"
            else right = F.Money(unit) .. " |cff8a8a8amarket price|r" end
            tip:AddDoubleLine("  " .. (id and ItemLabel(id, tonumber(reagent.qty) or 1) or ("Item " .. tostring(reagent.ids and reagent.ids[1]))), right, 1, 1, 1, 1, 1, 1)
        end
    end
    if item.u > 0 and item.k > 0 then Note(tip, item.u .. " unpriced crafts left out") end
    W.ShowLines(row, tip, refresh)
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------

local function PaintFill(row)
    if row.hover then W.Color(row.fill, { 0.075, 0.065, 0.025, 0.95 })
    elseif row.last then W.Color(row.fill, { 0.055, 0.05, 0.02, 0.95 })
    else W.Color(row.fill, row.alt and { 0.065, 0.065, 0.073, 1 } or { 0.035, 0.035, 0.04, 0.9 }) end   -- every second row lighter (as in Forever Delete Junk)
end

---------------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------------

-- The headings: key -> label. "item" sorts by name. A click sorts by that column; a second click on the same one
-- reverses it. The default is crafts, most first (what the list always did). Saved in luckSort / luckSortDesc.
local HEADINGS = { item = "Item", c = "Crafts", x = "Extras", exp = "Expected", real = "Extra %", luck = "Luck",
    spent = "Spent", gained = "Gained", profit = "Profit", hour = "Per hr", avg = "Each" }

-- The number (or text) an item row is sorted by for a column; nil when it has none (it then sinks to the bottom,
-- whichever way the list is sorted).
local function SortValue(item, key)
    if key == "item" then return (item.name or ""):lower() end
    local money = item   -- (an item sold at the AH is sorted by its AH figures; none without a price)
    if item.ah and (key == "spent" or key == "gained" or key == "avg" or key == "profit" or key == "hour") then
        if not item.ahView then return nil end
        money = item.ahView
    end
    if item.prof == "auction" then   -- (Sales.lua: the same cells, other figures)
        if key == "c" then return item.c end
        if key == "x" then return item.x end
        if key == "exp" then return item.o end
        if key == "spent" then return item.d end
        if key == "gained" then return item.m end
        if key == "profit" then return item.profit end
        if key == "avg" then return item.x > 0 and item.profit / item.x or nil end
        return nil
    end
    if key == "c" then return item.c end
    if key == "x" then return item.x end
    if key == "exp" then return item.expected end
    if key == "real" then return item.c > 0 and item.x / item.c or nil end
    if key == "luck" then return item.z end
    if key == "spent" then return money.k > 0 and money.s or nil end
    if key == "gained" then return money.k > 0 and money.g or nil end
    if key == "avg" then return money.k > 0 and money.g / money.k or nil end
    if key == "profit" then return money.k > 0 and (money.g - money.s) or nil end
    if key == "hour" then return (money.k > 0 and money.secs and money.secs > 0) and ((money.g - money.s) * 3600 / money.secs) or nil end
    return nil
end

local function SortKey()
    local key = F.db and F.db.luckSort
    if not HEADINGS[key] then return "c" end
    if key ~= "item" then
        for _, col in ipairs(COLS) do
            if col.key == key and not KeyShown(ProfKey(), key) then return "c" end   -- a column this tab does not show
        end
    end
    return key
end

local function SortDesc()
    return not (F.db and F.db.luckSortDesc == false)
end

local function Arrange(items)
    local key, desc = SortKey(), SortDesc()
    table.sort(items, function(a, b)
        local x, y = SortValue(a, key), SortValue(b, key)
        if x == nil and y == nil then return a.name < b.name end
        if x == nil then return false end      -- an item without the figure sinks to the bottom
        if y == nil then return true end
        if x == y then return a.name < b.name end
        if desc then return x > y end
        return x < y
    end)
end

local function HeadText(key)
    local text = HEADINGS[key]
    if key == "c" and F.TabDef(ProfKey()).disenchant then text = "Disenchants" end
    if F.TabDef(ProfKey()).sales and SALES.heads[key] then text = SALES.heads[key] end
    return text
end

local function SortBy(key)
    local db = F.db
    page = 1
    if SortKey() == key then
        db.luckSortDesc = not SortDesc()
    else
        db.luckSort = key
        db.luckSortDesc = key ~= "item"     -- names run A to Z first, every number biggest first
    end
    U.Refresh()
end

-- The width of a text, measured on a hidden string (frame.measure).
local function Measure(text)
    frame.measure:SetText(text)
    local width = frame.measure:GetStringWidth()
    return F.Number(width) and math.ceil(width) or 0
end

-- Sizes the window and places the columns for a tab and its data, by the rule both windows share (Style.Columns): the number columns are as wide as their widest text over every row (not just the page, so paging never moves them),
-- the heading included, and sit at the right edge; the name column takes the spare width. The window is at least Style.BASE_WIDTH and
-- as wide as the main window when that is wider. Only re-placed when something changed (a re-anchored frame under the pointer
-- blinks its tooltip).
local function ApplyLayout(prof, data)
    local St = F.Style
    local def = F.TabDef(prof)
    -- the left column: a check on each recipe row (sold at the AH); on an AH sales row the delete button and the add-missed-sales button
    local lead = def.sales and (CHECK_W + BTN_W + 2) or (def.store ~= nil and CHECK_W or 0)
    local keys = TabKeys(prof)
    local widths = {}
    for _, key in ipairs(keys) do widths[key] = Measure(HeadText(key)) end
    local nameMin = Measure(HeadText("item"))
    local function Take(r)
        local cells = Cells(r)
        for _, key in ipairs(keys) do
            local cell = cells[key]
            if cell then widths[key] = math.max(widths[key], Measure(cell[1])) end
        end
    end
    for _, item in ipairs(data.items) do Take(item) end
    if data.recipes > 0 then Take(data.total) end
    if data.ahTotal and data.ahTotal.count > 0 then Take(data.ahTotal) end
    -- The name column has a fixed least width and takes whatever is left. A name is never measured into the window's width: a long one is cut by its
    -- column (the game ends it with "...") and the whole name is in the tooltip.
    nameMin = NAME_MIN
    local cols = {}
    for _, key in ipairs(keys) do cols[#cols + 1] = { key = key, w = widths[key] + COL_PAD } end
    local nameX = NAME_X + lead
    local opts = { gap = GAP, nameX = nameX, minName = nameMin, rightPad = SIDE + 5, width = St.BASE_WIDTH }
    local _, _, _, needed = St.Columns(cols, opts)
    need = math.max(St.BASE_WIDTH, needed)
    opts.width = math.max(need, F.UI.NaturalWidth and F.UI.NaturalWidth() or 0)
    local pos, nameW, width = St.Columns(cols, opts)

    local parts = { prof, width, nameX, nameW }
    for _, col in ipairs(cols) do parts[#parts + 1] = col.key .. ":" .. pos[col.key].x .. ":" .. pos[col.key].w end
    local signature = table.concat(parts, "|")
    if frame.layoutSig == signature then return end
    frame.layoutSig = signature
    WIDTH = width
    frame:SetWidth(WIDTH)
    local function Place(row)
        row:SetWidth(WIDTH - 2 * SIDE)
        row.name:SetWidth(nameW)
        if row.nameHit then row.nameHit:SetWidth(nameW) end
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", row, "LEFT", 3 + lead, 0)   -- (the name follows the icon)
        for _, col in ipairs(COLS) do
            local at = pos[col.key]
            local cell = row.cell[col.key]
            if at then
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", at.x - SIDE, 0)
                cell:SetWidth(at.w)
                cell:Show()
            else
                cell:Hide()
            end
            if col.key == "profit" and row.profitHit then   -- the hover square over the Profit cell
                row.profitHit:ClearAllPoints()
                if at then
                    row.profitHit:SetPoint("LEFT", row, "LEFT", at.x - SIDE, 0)
                    row.profitHit:SetSize(at.w, ROW_H)
                    row.profitHit:Show()
                else
                    row.profitHit:Hide()
                end
            end
        end
    end
    for _, row in ipairs(rows) do Place(row) end
    Place(frame.total)
    Place(frame.ahTotal)
    for _, col in ipairs(COLS) do
        local heading = frame.heads[col.key]
        local at = pos[col.key]
        if at then
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", frame, "TOPLEFT", at.x, -HEAD_Y)   -- exactly its column: a click belongs to one heading only
            heading:SetWidth(at.w)
            heading:Show()
        else
            heading:Hide()
        end
    end
    frame.ahHead:SetShown(def.store ~= nil)
    frame.heads.item:ClearAllPoints()
    frame.heads.item:SetPoint("TOPLEFT", frame, "TOPLEFT", nameX, -HEAD_Y)
    frame.heads.item:SetWidth(nameW)
    frame.summary:SetWidth(WIDTH - 2 * (SIDE + 6))
    frame.note:SetWidth(WIDTH - 2 * (SIDE + 6))
end

function U.SelectTab(key)
    local def = F.TabDef(key)
    if not (def and (def.store or def.disenchant or def.sales)) then return false end
    F.db.luckTab = key
    page = 1
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
    U.Refresh()
    return true
end

---------------------------------------------------------------------------
-- The detail panel of an Enchanting row: what the disenchants gave, result by result,
-- against what the disenchant table says to expect, and whether it is above or below.
---------------------------------------------------------------------------

local expanded            -- the item (luck entry key) whose panel is open
local DETAIL_PAD, DETAIL_LINE, DETAIL_MAX = 8, 16, 8

-- { head, lines = { { id, name, got, expected, diff } }, foot, over }: the results the disenchant table lists (what each disenchant is
-- expected to give: chance x quantity) and any other result that came, with the quantity received, the quantity expected over this
-- many disenchants and the difference; `over` is the difference in copper at today's prices after the AH cut.
function U.DetailData(item)
    local out = { lines = {} }
    local outcomes = F.Disenchant.Outcomes(item.out)
    local res = item.res or {}
    local seen = {}
    local over, priced = 0, false
    local function Add(id, expectedEach)
        local got = F.Integer(res[id], 0, 2147483647) and res[id] or 0
        local expected = expectedEach * item.c
        out.lines[#out.lines + 1] = { id = id, name = F.ItemMeta(id).name or ("Item " .. id), got = got, expected = expected, diff = got - expected }
        local price = F.AuctionPrice(id)
        if price then over = over + (got - expected) * price * (1 - F.AH_CUT); priced = true end
        seen[id] = true
    end
    for _, outcome in ipairs(outcomes or {}) do Add(outcome.id, outcome.average) end
    local extras = {}
    for id in pairs(res) do if not seen[id] then extras[#extras + 1] = id end end
    table.sort(extras)
    for _, id in ipairs(extras) do Add(id, 0) end   -- received but not in the table
    out.head = outcomes
        and string.format("Disenchanted %d time(s): what came out against what the table expects.", item.c)
        or string.format("Disenchanted %d time(s). No estimate: the item's information is not loaded yet.", item.c)
    if outcomes and priced then
        out.over = math.floor(over)
        out.foot = (over >= 0 and "Above" or "Below") .. " the estimate by about " .. F.Money(math.floor(math.abs(over) + 0.5))
            .. " (today's prices, after the AH cut)." .. (item.c < 20 and " With so few disenchants luck swings it a lot." or "")
    end
    return out
end

local function PaintDetail(item)
    local panel = frame.detail
    local data = U.DetailData(item)
    panel:SetWidth(WIDTH - 2 * SIDE)
    panel.head:SetText(data.head)
    local y = DETAIL_PAD + 16
    for _, key in ipairs({ "name", "got", "exp", "diff" }) do panel.cols[key]:SetShown(#data.lines > 0) end
    if #data.lines > 0 then y = y + DETAIL_LINE end
    for index = 1, DETAIL_MAX do
        local widgets, line = panel.lines[index], data.lines[index]
        if line then
            local meta = F.ItemMeta(line.id)
            widgets.name:SetText((meta.icon and ("|T" .. tostring(meta.icon) .. ":14|t ") or "") .. line.name)
            widgets.got:SetText(tostring(line.got))
            widgets.exp:SetText(string.format("%.1f", line.expected))
            local color = line.diff >= 0.5 and W.GREEN or (line.diff <= -0.5 and W.RED or W.GREY)
            widgets.diff:SetText(string.format("%+.1f", line.diff))
            widgets.diff:SetTextColor(color[1], color[2], color[3])
            for _, text in pairs(widgets) do text:Show() end
            y = y + DETAIL_LINE
        else
            for _, text in pairs(widgets) do text:Hide() end
        end
    end
    panel.foot:SetText(data.foot or "")
    if data.over then
        local color = data.over >= 0 and W.GREEN or W.RED
        panel.foot:SetTextColor(color[1], color[2], color[3])
    end
    panel.foot:SetShown(data.foot ~= nil)
    if data.foot then y = y + DETAIL_LINE + 2 end
    panel.shownData = data
    panel:SetHeight(y + DETAIL_PAD)
    return y + DETAIL_PAD
end

function U.Detail()   -- (tests) the open panel as text, or nil
    if not frame or not frame.detail or not frame.detail:IsShown() then return nil end
    return frame.detail.shownData
end

-- A tooltip open on a row is rebuilt with the new counts (a craft was just counted) instead of being closed or left stale by the redraw;
-- the row under the mouse may now hold another item after a re-sort. One whose row is gone is closed. Also run when Shift is pressed or
-- released: the Profit tooltip shows the materials only while it is held.
local function RedoTips()
    for _, row in ipairs(rows) do
        local over = row.tipHover == true   -- (the pointer is on the item column or the Profit cell)
        if row:IsShown() and row.item then
            if over then (row.tipKind == "profit" and ShowProfitTip or ShowTip)(row, true) end
        elseif row.tipHover and type(GameTooltip) == "table" and F.Has(GameTooltip, "IsOwned") and GameTooltip:IsOwned(row) then
            row.tipHover = false
            GameTooltip:Hide()
        end
    end
end

function U.Refresh()
    if not frame or not frame:IsShown() then return end
    local visible = F.VisibleTabs(HasLuck, F.LUCK_TABS)
    if not F.IsVisibleTab(visible, ProfKey()) then F.db.luckTab = visible[1] end
    W.LayoutTabs(frame, frame.tabs, visible)
    local prof = ProfKey()
    local def = F.TabDef(prof)
    local proc = def.proc
    for key, tab in pairs(frame.tabs) do
        tab.selected = key == prof
        W.PaintTab(tab)
    end
    local data
    if def.sales then
        local crafted = not F.db or F.db.salesCrafted ~= false
        data = F.Sales.Aggregate(Scope(), crafted and F.Luck.CraftedFilter() or nil, F.Luck.UnitCosts())
    else
        data = F.Luck.Aggregate(Scope(), nil, prof)
    end
    frame.crafted:SetShown(def.sales == true)
    frame.crafted.mark:SetShown(not F.db or F.db.salesCrafted ~= false)
    frame.reset:SetShown(Scope() == "session")   -- (Character and Lifetime are not reset from here)
    local listed = #data.items
    if search ~= "" then
        local kept = {}
        for _, item in ipairs(data.items) do
            if (item.name or ""):lower():find(search, 1, true) then kept[#kept + 1] = item end
        end
        data.items = kept
    end
    Arrange(data.items)
    frame.itemCount = #data.items
    ApplyLayout(prof, data)   -- (after the data: the columns are as wide as what they hold)
    local total = data.total
    for key, heading in pairs(frame.heads) do
        heading.label:SetText(HeadText(key))
        local c = SortKey() == key and W.GOLD or W.GREY   -- the column sorted by is gold (there is no arrow)
        heading.label:SetTextColor(c[1], c[2], c[3])
    end
    for _, key in ipairs({ "session", "char", "life" }) do
        local scope = frame.scopes[key]
        scope.selected = key == Scope()
        PaintScope(scope)
    end

    local last = F.Luck.last
    if last and (last.prof or "cooking") ~= prof then last = nil end   -- another tab's craft
    local pages = math.max(1, math.ceil(#data.items / MAX_ROWS))
    page = math.max(1, math.min(page, pages))
    local first = (page - 1) * MAX_ROWS
    local shown = math.max(0, math.min(#data.items - first, MAX_ROWS))
    for index = 1, MAX_ROWS do
        local row, item = rows[index], data.items[first + index]
        if item and index <= shown then
            local meta = item.out and F.ItemMeta(item.out) or {}
            row.item = item
            row.last = last ~= nil and last.id == item.id
            row.icon:SetTexture(meta.icon or W.UNKNOWN_ICON)
            local q = W.QUALITY[meta.quality or 1] or W.TEXT
            row.name:SetText(item.name)
            row.name:SetTextColor(q[1], q[2], q[3])
            if def.disenchant and expanded ~= nil and expanded == item.id then   -- its detail panel is open (shift-click): gold, as in the main window
                row.name:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
            end
            if def.sales and armed == item.id then   -- the delete button was clicked once: say so where the name is
                row.name:SetText("Are you sure?")
                row.name:SetTextColor(W.RED[1], W.RED[2], W.RED[3])
            end
            Fill(row.cell, Cells(item))
            row.check:SetShown(def.store ~= nil)
            row.check.mark:SetShown(item.ah == true)
            row.del:SetShown(def.sales == true)
            row.edit:SetShown(def.sales == true)
            PaintFill(row)
            row:Show()
        else
            row.item = nil
            row:Hide()
        end
    end

    -- the open detail panel (shift-click on an Enchanting row) sits under its row and pushes the rows below it down
    local openIndex
    if def.disenchant and expanded then
        for index = 1, shown do
            if data.items[first + index].id == expanded then openIndex = index; break end
        end
    end
    local extra = 0
    if openIndex then
        extra = PaintDetail(data.items[first + openIndex]) + ROW_GAP
        W.PlaceTopLeft(frame.detail, frame, SIDE, ROWS_Y + openIndex * (ROW_H + ROW_GAP))
        frame.detail:Show()
    else
        frame.detail:Hide()
    end
    for index = 1, MAX_ROWS do
        W.PlaceTopLeft(rows[index], frame, SIDE, ROWS_Y + (index - 1) * (ROW_H + ROW_GAP) + ((openIndex and index > openIndex) and extra or 0))
    end

    -- Under the Total row only what the table cannot say: why the list is
    -- empty, what a "*" means, what is hidden, a missing hook. Normally there is nothing.
    local lines = {}
    if def.sales then
        if data.recipes == 0 then
            lines[#lines + 1] = (data.hidden or 0) > 0 and "Nothing here that you crafted." or "Nothing counted yet."
            lines[#lines + 1] = "An auction counts when the house confirms it (its deposit comes off); a sale when you take its money from the mail; an unsold one when you take its item back."
        end
        if total.partial then lines[#lines + 1] = "* listed before this was watched: its deposit is not counted." end
        if (data.hidden or 0) > 0 then lines[#lines + 1] = data.hidden .. " other item(s) you sold are not shown: untick Crafted to see them." end
        local hooks = #F.Sales.Hooked()
        if hooks < 5 then lines[#lines + 1] = "Only " .. hooks .. " of 5 auction and mail hooks are in place yet: open the auction house and the mailbox (/dpp status)." end
    elseif def.disenchant then
        if total.c == 0 then
            lines[#lines + 1] = "Nothing counted yet."
            if F.Luck.de.casts == 0 then lines[#lines + 1] = "No disenchant seen since login." end
        elseif total.u > 0 then
            lines[#lines + 1] = "* " .. total.u .. " disenchant(s) unpriced."
        end
    elseif data.recipes > 0 then
        local unpriced = total.u + ((data.ahTotal and data.ahTotal.u) or 0)
        if unpriced > 0 then lines[#lines + 1] = "* " .. unpriced .. " craft(s) unpriced." end
    else
        lines[#lines + 1] = "Nothing counted yet."
        if F.Luck.seen == 0 then lines[#lines + 1] = "No craft message seen since login." end
    end
    frame.summary:SetText(table.concat(lines, "\n"))
    local height = frame.summary:GetStringHeight()
    local summaryH = #lines > 0 and (F.Number(height) and math.ceil(height) or 40) or 0
    local hasTotal = data.recipes > 0
    local ahCount = data.ahTotal and data.ahTotal.count or 0
    if search ~= "" and listed > 0 and #data.items == 0 then   -- the search matched nothing
        hasTotal = false
        lines = { "Nothing in this list matches the search." }
        frame.summary:SetText(lines[1])
        local h = frame.summary:GetStringHeight()
        summaryH = F.Number(h) and math.ceil(h) or 14
    end
    local block = summaryH > 0 and (4 + summaryH) or 0   -- the notes under the Total row
    -- one more row under the Total: the items marked as sold at the AH, added up at today's AH prices (tabs with recipes only)
    -- The main row is "Vendor" on a tab with recipes (the items not ticked); it is left out when every item is ticked.
    local hasAH = hasTotal and ahCount > 0
    local hasVendor = hasTotal and data.recipes - ahCount > 0
    local vendorH = hasVendor and ROW_H or 0
    local ahH = hasAH and (ROW_H + (hasVendor and 2 or 0)) or 0
    local rowsH = vendorH + ahH
    frame.total.name:SetText(def.store ~= nil and "Vendor" or "Total")

    -- The footer is the main window's: the window is
    -- as tall as the main window, the divider 36 px above its bottom, and what ends just above the divider (here the Total row or the
    -- notes under it) ends 5 px above it, as the main window's last row does. With several pages the Total row is pinned there, so a
    -- short last page does not leave a taller gap; with one page there is no divider and the Total row sits right under the last item.
    local totalNatural = ROWS_Y + (pages > 1 and MAX_ROWS or shown) * (ROW_H + ROW_GAP) + 4 + extra
    need_h = totalNatural + rowsH + block + 5 + 36
    local tall = math.max(need_h, F.UI.NaturalHeight and F.UI.NaturalHeight() or 0)
    local at = tall - 36
    local totalY = totalNatural
    if pages > 1 then totalY = at - 5 - block - rowsH end
    if hasVendor then
        W.PlaceTopLeft(frame.total, frame, SIDE, totalY)   -- only when it has moved (a redraw happens after every craft)
        Fill(frame.total.cell, Cells(total))
        frame.total:Show()
    else
        frame.total:Hide()
    end
    if hasAH then
        W.PlaceTopLeft(frame.ahTotal, frame, SIDE, totalY + vendorH + (hasVendor and 2 or 0))
        Fill(frame.ahTotal.cell, Cells(data.ahTotal))
        frame.ahTotal:Show()
    else
        frame.ahTotal:Hide()
    end
    local summaryY = totalY + (hasTotal and (rowsH + 4) or 6)
    frame.summary:ClearAllPoints()
    frame.summary:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 6, -summaryY)
    frame.summary:SetHeight(summaryH)
    frame.note:ClearAllPoints()
    frame.note:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 6, -(summaryY + summaryH))
    frame.prev:SetShown(pages > 1)
    frame.next:SetShown(pages > 1)
    frame.pageText:SetShown(pages > 1)
    frame.divider:SetShown(pages > 1)
    if pages > 1 then
        frame.divider:ClearAllPoints()
        frame.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -at)
        frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -at)
        W.PlaceTopLeft(frame.prev, frame, SIDE, at + 8)
        W.PlaceTopLeft(frame.next, frame, SIDE + 32, at + 8)
        W.PlaceTopLeft(frame.pageText, frame, SIDE + 70, at + 11)
        frame.pageText:SetText("Page " .. page .. "/" .. pages .. "   " .. #data.items .. ((def.sales or def.disenchant) and " item(s)" or " recipe(s)"))
    end
    frame:SetHeight(tall)
    -- the main window is as tall as this one: when this one needs more than the main window last measured, the main window is laid out again
    if F.UI and F.UI.IsShown() and F.UI.Frame() and F.UI.Frame():GetHeight() ~= tall then F.UI.Refresh() end

    RedoTips()
end

function U.Row(index) return rows[index] end   -- (tests)
function U.Width() return WIDTH end            -- (tests)
function U.Heading(key) return frame and frame.heads[key] end   -- (tests)

function U.Place()
    if not frame then return end
    frame:ClearAllPoints()
    local db = F.db
    if db and F.Number(db.luckLeft) and F.Number(db.luckTop) then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.luckLeft, db.luckTop)
    else
        -- The top left is the fixed point, never the centre: the window's height changes whenever the text under
        -- the list does (after every craft), and a centred window moves its top edge by half of that, sliding the
        -- rows under the pointer so the game sees it leave one row and enter another (the tooltip blinks).
        frame:SetPoint("TOPLEFT", UIParent, "CENTER", -(WIDTH / 2) + 60, 140)
    end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

-- One row's widgets: the fill, the icon, the name and a right-justified text per column.
local function BuildRow(parent, button)
    local row = CreateFrame(button and "Button" or "Frame", nil, parent)
    row:SetSize(WIDTH - 2 * SIDE, ROW_H)
    row.fill = row:CreateTexture(nil, "BACKGROUND")
    row.fill:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.name = W.Text(row, nil, W.TEXT)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetWidth(NAME_W)
    if button then   -- the list's rows (not the total): the box that marks an item as sold at the auction house
        local check = CreateFrame("Button", nil, row)
        check:SetSize(BTN_W, BTN_H)
        check:SetPoint("LEFT", row, "LEFT", CHECK_X, 0)
        local square = CreateFrame("Frame", nil, check)
        square:SetAllPoints()   -- (the box fills the button, like the [A] button)
        check.edges = select(2, W.Box(square, { 0.06, 0.06, 0.07 }, { 0.34, 0.34, 0.37 }))
        check.mark = square:CreateTexture(nil, "ARTWORK")
        check.mark:SetSize(9, 9)
        check.mark:SetPoint("CENTER", square, "CENTER")
        W.Color(check.mark, W.GOLD)
        check:SetScript("OnClick", function()
            if row.item then F.Luck.ToggleAH(row.item.id); U.Refresh() end
        end)
        check:SetScript("OnEnter", function(self)
            for _, edge in ipairs(self.edges) do W.Color(edge, { 0.62, 0.62, 0.66 }) end
            W.ShowTip(self, TIPS.ah)
        end)
        check:SetScript("OnLeave", function(self)
            for _, edge in ipairs(self.edges) do W.Color(edge, { 0.34, 0.34, 0.37 }) end
            if type(GameTooltip) == "table" then GameTooltip:Hide() end
        end)
        row.check = check
        W.KeepRowTipOff(row, check)

        -- AH sales tab: delete this row. A red disc with a slash, drawn from bars; two clicks, the first
        -- turns the row's name into "Are you sure?". Leaving the button cancels.
        local del = W.MakeNativeButton(row, "", BTN_W, BTN_H)   -- (the game's own button; the red disc is drawn on it)
        del:SetPoint("LEFT", row, "LEFT", CHECK_X, 0)
        del.discs, del.slashes = {}, {}
        local function Bar(list, x, y, w, h, color)
            local bar = del:CreateTexture(nil, "OVERLAY")
            bar:SetSize(w, h)
            bar:SetPoint("TOPLEFT", del, "TOPLEFT", math.floor((BTN_W - 12) / 2) + x, -(math.floor((BTN_H - 12) / 2) + y))
            W.Color(bar, color)
            list[#list + 1] = bar
        end
        for y, span in ipairs({ { 4, 4 }, { 2, 8 }, { 1, 10 }, { 0, 12 }, { 0, 12 }, { 0, 12 }, { 0, 12 }, { 0, 12 }, { 0, 12 }, { 1, 10 }, { 2, 8 }, { 4, 4 } }) do
            Bar(del.discs, span[1], y - 1, span[2], 1, DEL_RED)
        end
        for step = 0, 4 do Bar(del.slashes, 3 + step, 7 - step, 2, 2, { 1, 1, 1 }) end   -- the "/"
        local function Tint(color) for _, bar in ipairs(del.discs) do W.Color(bar, color) end end
        local function Tip(self)
            W.ShowTip(self, TIPS.del(row.item and armed == row.item.id))
        end
        del:SetScript("OnClick", function(self)
            local item = row.item
            if not (item and item.prof == "auction") then return end
            if armed == item.id then
                armed = nil
                F.Sales.Delete(Scope(), item.id)
            else
                armed = item.id
            end
            U.Refresh()
            Tip(self)
        end)
        del:HookScript("OnEnter", function(self) Tint(DEL_RED_HOVER); Tip(self) end)
        del:HookScript("OnLeave", function()
            Tint(DEL_RED)
            if type(GameTooltip) == "table" then GameTooltip:Hide() end
            if armed ~= nil then armed = nil; U.Refresh() end
        end)
        row.del = del
        W.KeepRowTipOff(row, del)

        -- AH sales tab: add sales that were missed. A "+" beside the delete button opens the edit window.
        local edit = W.MakeButton(row, "+", BTN_W, BTN_H)
        edit:SetPoint("LEFT", row, "LEFT", CHECK_X + BTN_W + 2, 0)
        edit:SetScript("OnClick", function()
            if row.item and row.item.prof == "auction" then U.OpenEdit(row.item) end
        end)
        edit:HookScript("OnEnter", function(self) W.ShowTip(self, TIPS.edit) end)
        edit:HookScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
        row.edit = edit
        W.KeepRowTipOff(row, edit)
        W.MakeIconTip(row, function(r) return r.item and r.item.out end)

        -- The row's extra information (ShowTip) shows only over the item column, not over the icon, the left column or the number
        -- columns. A square over the name; clicks go through to the row (shift-click on Enchanting).
        local hit = CreateFrame("Frame", nil, row)
        hit:SetPoint("LEFT", row.name, "LEFT", 0, 0)
        hit:SetSize(NAME_W, ROW_H)
        hit:EnableMouse(true)
        if F.Has(hit, "SetPropagateMouseClicks") then hit:SetPropagateMouseClicks(true) end
        -- (the row's highlight follows the pointer over these squares too: a child does not give the row an OnEnter, and leaving a
        -- child straight out of the row gives it no OnLeave, which left rows stuck gold)
        hit:SetScript("OnEnter", function()
            row.hover = true; PaintFill(row)
            row.tipHover, row.tipKind, row.tipRegion = true, "item", hit; ShowTip(row)
        end)
        hit:SetScript("OnLeave", function()
            row.tipHover = false
            if type(GameTooltip) == "table" then GameTooltip:Hide() end
            if not (type(row.IsMouseOver) == "function" and row:IsMouseOver()) then row.hover = false; PaintFill(row) end
        end)
        row.nameHit = hit

        -- the same over the Profit cell: how the profit was worked out (placed with the columns, ApplyLayout)
        local profitHit = CreateFrame("Frame", nil, row)
        profitHit:SetSize(70, ROW_H)
        profitHit:EnableMouse(true)
        if F.Has(profitHit, "SetPropagateMouseClicks") then profitHit:SetPropagateMouseClicks(true) end
        profitHit:SetScript("OnEnter", function()
            row.hover = true; PaintFill(row)
            row.tipHover, row.tipKind, row.tipRegion = true, "profit", profitHit; ShowProfitTip(row)
        end)
        profitHit:SetScript("OnLeave", function()
            row.tipHover = false
            if type(GameTooltip) == "table" then GameTooltip:Hide() end
            if not (type(row.IsMouseOver) == "function" and row:IsMouseOver()) then row.hover = false; PaintFill(row) end
        end)
        row.profitHit = profitHit
    end
    row.cell = {}
    for _, col in ipairs(COLS) do
        local text = W.Text(row, nil, W.TEXT, "RIGHT")
        text:SetPoint("LEFT", row, "LEFT", 0, 0)   -- (placed with the columns, ApplyLayout)
        text:SetWidth(40)
        row.cell[col.key] = text
    end
    return row
end

-- A flat one-line box, like the main window's search box.
local function EditBox(parent, width, numeric)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 18)
    box.fill, box.edges = W.Box(box, { 0.06, 0.06, 0.07 }, { 0.34, 0.34, 0.37 })
    box:SetFontObject("GameFontHighlightSmall")
    box:SetAutoFocus(false)
    if numeric then box:SetNumeric(true) end
    box:SetMaxLetters(numeric and 6 or 16)
    box:SetTextInsets(5, 5, 0, 0)
    box:SetScript("OnEditFocusGained", function(self) for _, edge in ipairs(self.edges) do W.Color(edge, W.GOLD) end; self:HighlightText() end)   -- (a click selects it all)
    box:SetScript("OnEditFocusLost", function(self) for _, edge in ipairs(self.edges) do W.Color(edge, { 0.34, 0.34, 0.37 }) end end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function Build()
    frame = CreateFrame("Frame", "DeffarProfessionProfitLuckFrame", UIParent)
    frame:SetSize(WIDTH, 360)
    frame:SetFrameStrata("DIALOG")
    frame:RegisterEvent("MODIFIER_STATE_CHANGED")   -- Shift pressed or released over a Profit cell: its tooltip is redrawn
    frame:SetScript("OnEvent", function() RedoTips() end)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    W.Box(frame, { 0, 0, 0, 0.92 }, { 0.20, 0.20, 0.20 })
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "DeffarProfessionProfitLuckFrame" end

    local handle = CreateFrame("Frame", nil, frame)
    handle:SetPoint("TOPLEFT", 34, 0)   --
    handle:SetPoint("TOPRIGHT", -34, 0)
    handle:SetHeight(30)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() frame:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local left, top = frame:GetLeft(), frame:GetTop()
        if F.db and F.Number(left) and F.Number(top) then F.db.luckLeft, F.db.luckTop = left, top end
        U.Place()
    end)

    -- Back to the main window: the return arrow at the top left, left of the title. Drawn from plain
    -- coloured bars, no game texture (the one tried first looked wrong): an arrowhead pointing left on the top line, which runs right,
    -- turns down and comes back left along the bottom:
    --   <-----
    --        |
    --     ----
    local back = W.MakeButton(frame, "", 22, 18)   --
    back:SetPoint("TOPLEFT", 8, -6)
    back.bars = {}
    local function Bar(x, y, w, h)   -- (in points from the arrow's top left, which sits 4 across and 3 down in the button)
        local bar = back:CreateTexture(nil, "OVERLAY")
        bar:SetSize(w, h)
        bar:SetPoint("TOPLEFT", back, "TOPLEFT", 4 + x, -(3 + y))
        W.Color(bar, W.TEXT)
        back.bars[#back.bars + 1] = bar
    end
    Bar(0, 2, 2, 2); Bar(2, 1, 1, 4); Bar(3, 0, 1, 6)   -- the arrowhead, pointing left (a stepped triangle, 6 tall)
    Bar(4, 2, 9, 2)                                      -- the top line
    Bar(11, 2, 2, 8)                                     -- down
    Bar(5, 8, 8, 2)                                      -- the bottom line, back left
    local function Tint(color) for _, bar in ipairs(back.bars) do W.Color(bar, color) end end
    back:SetScript("OnClick", function() U.Back() end)
    back:HookScript("OnEnter", function(self)
        Tint(W.GOLD)
        W.ShowTip(self, TIPS.back)
    end)
    back:HookScript("OnLeave", function() Tint(W.TEXT); if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    frame.back = back
    local title = W.Text(frame, "GameFontNormal", W.GOLD)
    title:SetPoint("TOPLEFT", 36, -10)
    title:SetText("Cook Luck")
    local close = W.MakeButton(frame, "X", 22, 18)
    close:SetPoint("TOPRIGHT", -8, -6)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.tabs = W.MakeTabStrip(frame, function(key) U.SelectTab(key) end, F.LUCK_TABS)

    -- Session / Character / Lifetime: a filter on the list below, so a lighter control than the profession tabs: plain
    -- text on its own row above the headings, the one in use gold with a thin underline.
    frame.scopes = {}
    local x = SIDE + 6
    for _, spec in ipairs({ { "session", "Session", 64 }, { "char", "Character", 76 }, { "life", "Lifetime", 64 } }) do
        local scope = CreateFrame("Button", nil, frame)
        scope:SetSize(spec[3], 20)
        scope:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -FILTER_Y)
        scope:RegisterForClicks("LeftButtonUp")
        scope.label = W.Text(scope, nil, W.GREY, "CENTER")
        scope.label:SetAllPoints()
        scope.label:SetText(spec[2])
        scope.marker = scope:CreateTexture(nil, "ARTWORK")
        scope.marker:SetPoint("BOTTOMLEFT", 4, 0)
        scope.marker:SetPoint("BOTTOMRIGHT", -4, 0)
        scope.marker:SetHeight(2)
        W.Color(scope.marker, W.GOLD)
        scope:SetScript("OnClick", function() F.db.luckScope = spec[1]; page = 1; U.Refresh() end)
        scope:SetScript("OnEnter", function(self)
            self.hover = true
            PaintScope(self)
            W.ShowTip(self, TIPS[spec[1]])
        end)
        scope:SetScript("OnLeave", function(self)
            self.hover = false
            PaintScope(self)
            if type(GameTooltip) == "table" then GameTooltip:Hide() end
        end)
        PaintScope(scope)
        frame.scopes[spec[1]] = scope
        x = x + spec[3] + 4
    end
    local reset = W.MakeButton(frame, "Reset session", 96, 20)
    reset:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(SIDE + 282), -FILTER_Y)   -- (left of the Crafted box; only on the Session scope, Refresh)
    reset:SetScript("OnClick", function() F.Luck.ResetSession(); U.Refresh() end)
    reset:HookScript("OnEnter", function(self) W.ShowTip(self, TIPS.reset) end)
    reset:HookScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    frame.reset = reset
    -- AH sales tab: list only what the player crafted, so random sold items do not show. On by default.
    -- The addon's own check box (the same as the main window's), at the right end of the row, right of Reset session.
    frame.crafted = W.MakeCheck(frame, "Crafted", TIPS.crafted, 0, 0,
        function()
            F.db.salesCrafted = not (F.db.salesCrafted ~= false)
            page = 1
            U.Refresh()
        end)
    frame.crafted:SetSize(70, 18)
    frame.crafted:ClearAllPoints()
    frame.crafted:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(SIDE + 208), -(FILTER_Y + 1))   -- (left of the search box)

    -- Search:
    -- at the right end of that row. Filters the list on every tab to the items whose name contains the text, as you type; not saved.
    frame.searchLabel = W.Text(frame, nil, W.GREY)
    frame.searchLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(SIDE + 156), -(FILTER_Y + 4))
    frame.searchLabel:SetWidth(44)
    frame.searchLabel:SetText("Search:")
    frame.searchBox = EditBox(frame, 150, false)
    frame.searchBox:SetMaxLetters(40)
    frame.searchBox:SetTextInsets(5, 18, 0, 0)   -- (room for the x at the right)
    W.AddClear(frame.searchBox)
    frame.searchBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -(FILTER_Y + 1))
    frame.searchBox:SetScript("OnTextChanged", function(self)
        W.ClearShown(self)
        search = (self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        page = 1
        U.Refresh()
    end)
    frame.searchBox:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end   -- (SetText runs OnTextChanged)
    end)
    frame.searchBox:SetScript("OnEnter", function(self) W.ShowTip(self, TIPS.search) end)
    frame.searchBox:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)

    -- the column headings are buttons: a click sorts by that column (Refresh puts the arrow on the sorted one)
    frame.heads = {}
    local function Heading(key, x, width, justify)
        local heading = CreateFrame("Button", nil, frame)
        heading:SetSize(width, 14)
        heading:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -HEAD_Y)
        heading.label = W.Text(heading, nil, W.GREY, justify)
        heading.label:SetAllPoints()
        heading.label:SetText(HEADINGS[key])
        heading:SetScript("OnEnter", function(self) self.label:SetTextColor(W.TEXT[1], W.TEXT[2], W.TEXT[3]) end)
        heading:SetScript("OnLeave", function(self) local c = SortKey() == key and W.GOLD or W.GREY; self.label:SetTextColor(c[1], c[2], c[3]) end)
        heading:SetScript("OnClick", function() SortBy(key) end)
        frame.heads[key] = heading
    end
    Heading("item", NAME_X, NAME_W, "LEFT")
    -- the heading of the check column: the same height as the other headings and its text centred in it the same way, so the headings
    -- are one row (it sat a pixel or two higher as a bare text)
    frame.ahHead = CreateFrame("Frame", nil, frame)
    frame.ahHead:SetSize(BTN_W + 4, 14)
    frame.ahHead:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + CHECK_X - 2, -HEAD_Y)
    frame.ahHead.label = W.Text(frame.ahHead, nil, W.GREY, "CENTER")
    frame.ahHead.label:SetAllPoints()
    frame.ahHead.label:SetText("AH")
    for _, col in ipairs(COLS) do
        -- (the heading is as wide as its column, no wider: the sort arrows that needed 16 px more are gone, and a wider one overlapped its neighbour)
        Heading(col.key, 0, 40, "RIGHT")   -- (placed with the columns, ApplyLayout)
    end

    for index = 1, MAX_ROWS do
        local row = BuildRow(frame, true)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -(ROWS_Y + (index - 1) * (ROW_H + ROW_GAP)))
        row.alt = index % 2 == 0
        PaintFill(row)
        row:Hide()
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnClick", function(self)
            -- shift-click an Enchanting row: open or close its detail panel
            if not (self.item and F.TabDef(self.item.prof or "cooking").disenchant) then return end
            if not (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) then return end
            expanded = (expanded ~= self.item.id) and self.item.id or nil
            if type(GameTooltip) == "table" then GameTooltip:Hide() end
            U.Refresh()
        end)
        row:SetScript("OnEnter", function(self) self.hover = true; PaintFill(self) end)   -- (the tooltip belongs to the item column, nameHit)
        row:SetScript("OnLeave", function(self)
            -- (see UI.lua: a leave with the pointer still on the row is a re-anchor, not the pointer leaving)
            if type(self.IsMouseOver) == "function" and self:IsMouseOver() then return end
            self.hover = false; PaintFill(self)
            if type(GameTooltip) == "table" then GameTooltip:Hide() end
        end)
        rows[index] = row
    end

    -- the detail panel of an Enchanting row (shift-click): a heading, a column heading, one line per result and a closing line
    local detail = CreateFrame("Frame", nil, frame)
    detail:SetSize(WIDTH - 2 * SIDE, 60)
    detail:Hide()
    W.Box(detail, { 0.045, 0.042, 0.02, 0.96 }, { 0.36, 0.30, 0.08 })
    detail.head = W.Text(detail, nil, W.GREY)
    detail.head:SetPoint("TOPLEFT", detail, "TOPLEFT", DETAIL_PAD, -(DETAIL_PAD - 2))
    detail.cols, detail.lines = {}, {}
    local COLUMNS = { name = { "LEFT", 8, 220 }, got = { "RIGHT", -196, 60 }, exp = { "RIGHT", -112, 76 }, diff = { "RIGHT", -28, 76 } }
    local LABELS = { name = "Result", got = "Got", exp = "Expected", diff = "Difference" }
    local function Place(text, key, y)
        local at = COLUMNS[key]
        text:SetWidth(at[3])
        if at[1] == "LEFT" then text:SetPoint("TOPLEFT", detail, "TOPLEFT", at[2], -y)
        else text:SetPoint("TOPRIGHT", detail, "TOPRIGHT", at[2], -y) end
    end
    for key, at in pairs(COLUMNS) do
        detail.cols[key] = W.Text(detail, nil, W.GREY, at[1])
        detail.cols[key]:SetText(LABELS[key])
        Place(detail.cols[key], key, DETAIL_PAD + 16)
    end
    for index = 1, DETAIL_MAX do
        local widgets = {}
        for key, at in pairs(COLUMNS) do
            widgets[key] = W.Text(detail, nil, W.TEXT, at[1])
            Place(widgets[key], key, DETAIL_PAD + 16 + DETAIL_LINE * index)
        end
        detail.lines[index] = widgets
    end
    detail.foot = W.Text(detail, nil, W.TEXT)
    detail.foot:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", DETAIL_PAD, DETAIL_PAD)
    frame.detail = detail

    frame.total = BuildRow(frame, false)
    W.Color(frame.total.fill, { 0.09, 0.075, 0.02, 0.95 })
    frame.total.name:SetText("Total")
    frame.total.name:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
    frame.total.icon:Hide()
    frame.total.name:ClearAllPoints()
    frame.total.name:SetPoint("LEFT", frame.total, "LEFT", 6, 0)
    frame.total:Hide()

    frame.ahTotal = BuildRow(frame, false)   -- under it: the items sold at the AH at their prices
    W.Color(frame.ahTotal.fill, { 0.09, 0.075, 0.02, 0.95 })
    frame.ahTotal.name:SetText("Auction House")
    frame.ahTotal.name:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
    frame.ahTotal.icon:Hide()
    frame.ahTotal.name:ClearAllPoints()
    frame.ahTotal.name:SetPoint("LEFT", frame.ahTotal, "LEFT", 6, 0)
    frame.ahTotal:Hide()

    frame.measure = W.Text(frame, nil, W.TEXT)   -- never shown: only used to measure text widths
    frame.measure:Hide()
    frame.summary = W.Text(frame, nil, W.TEXT)
    frame.summary:SetWidth(WIDTH - 2 * (SIDE + 6))
    frame.summary:SetWordWrap(true)
    frame.summary:SetJustifyV("TOP")

    frame.divider = frame:CreateTexture(nil, "BORDER")   -- above the page buttons, as in the main window
    frame.divider:SetHeight(1)
    W.Color(frame.divider, W.DIVIDER)
    frame.divider:Hide()
    frame.prev = W.MakeButton(frame, "<", 28, 18)
    frame.next = W.MakeButton(frame, ">", 28, 18)
    frame.pageText = W.Text(frame, nil, W.GREY)
    local function Turn(delta)
        local target = page + delta
        local last = math.max(1, math.ceil((frame.itemCount or 0) / MAX_ROWS))
        if target >= 1 and target <= last then page = target; U.Refresh() end
    end
    frame.prev:SetScript("OnClick", function() Turn(-1) end)
    frame.next:SetScript("OnClick", function() Turn(1) end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) Turn(delta > 0 and -1 or 1) end)
    frame.note = W.Text(frame, nil, W.GREY)      -- (kept empty: the sizing code below counts its height)
    frame.note:SetWidth(WIDTH - 2 * (SIDE + 6))
    frame.note:SetWordWrap(true)
    frame.note:SetJustifyV("TOP")

    U.Place()
end

-- The width this window's table needs on the tab in use (the main window is at least this wide).
function U.NaturalWidth() return need end
function U.NaturalHeight() return need_h end

---------------------------------------------------------------------------
-- The edit window of an AH sales row: how many units were sold that the addon did not see, and what they brought in, either the money typed or, with
-- "Current Market Values" ticked, today's Auctionator price less the cut (plus the deposit back, estimated). It adds to the row's
-- figures in the scope shown (Session, Character or Lifetime).
---------------------------------------------------------------------------

local editFrame

-- What the window says it will add, and whether it can: sets e.units and e.money (nil until they are valid).
local function EditPreview()
    local e = editFrame
    local units = tonumber(e.qty:GetText())
    e.units = F.Integer(units, 1, 100000) and units or nil
    e.money = nil
    local market = e.market.mark:IsShown()
    e.moneyLabel:SetShown(not market)
    e.moneyBox:SetShown(not market)
    local note
    if not e.units then
        note = "Type how many were sold."
    elseif market then
        local value, price = F.Sales.MarketValue(Scope(), e.item.name, e.item.out, e.units)
        if value then
            e.money = value
            note = string.format("Adds %d sold and about %s received: %s each at the AH, less the 5%% cut, plus the deposit back.", e.units, F.Money(value), F.Money(price))
        else
            note = "Auctionator has no price for this item: untick the box and type the money."
        end
    else
        e.money = F.Bought.ParseMoney(e.moneyBox:GetText())
        note = e.money and string.format("Adds %d sold and %s received.", e.units, F.Money(e.money)) or "Type the money received in total, like 3g20s."
    end
    e.preview:SetText(note .. "\n|cff8a8a8aApplies to: " .. (F.Luck.SCOPES[Scope()] or Scope()) .. ".|r")
end

local function BuildEdit()
    local e = CreateFrame("Frame", "DeffarProfessionProfitLuckEdit", frame)
    editFrame = e
    e:SetSize(340, 196)
    e:SetFrameStrata("DIALOG")
    e:SetFrameLevel(frame:GetFrameLevel() + 20)
    e:EnableMouse(true)
    e:Hide()
    W.Box(e, { 0.02, 0.02, 0.025, 0.98 }, { 0.36, 0.30, 0.08 })
    e.title = W.Text(e, "GameFontNormal", W.GOLD)
    e.title:SetPoint("TOPLEFT", 12, -10)
    e.title:SetText("Add sales you missed")
    e.itemText = W.Text(e, nil, W.TEXT)
    e.itemText:SetPoint("TOPLEFT", 12, -30)
    e.itemText:SetWidth(316)
    local qtyLabel = W.Text(e, nil, W.GREY)
    qtyLabel:SetPoint("TOPLEFT", 12, -56)
    qtyLabel:SetText("Units sold:")
    e.qty = EditBox(e, 70, true)
    e.qty:SetPoint("TOPLEFT", e, "TOPLEFT", 104, -53)
    e.qty:SetScript("OnTextChanged", function() EditPreview() end)
    e.market = W.MakeCheck(e, "Current Market Values", TIPS.market,
        12, -80, function(self)
            self.mark:SetShown(not self.mark:IsShown())
            EditPreview()
        end)
    e.market:SetSize(220, 18)
    e.market.mark:SetShown(true)
    e.moneyLabel = W.Text(e, nil, W.GREY)
    e.moneyLabel:SetPoint("TOPLEFT", 12, -106)
    e.moneyLabel:SetText("Money received:")
    e.moneyBox = EditBox(e, 120, false)
    e.moneyBox:SetPoint("TOPLEFT", e, "TOPLEFT", 104, -103)
    e.moneyBox:SetScript("OnTextChanged", function() EditPreview() end)
    e.preview = W.Text(e, nil, W.TEXT)
    e.preview:SetPoint("TOPLEFT", 12, -130)
    e.preview:SetWidth(316)
    e.preview:SetHeight(34)
    e.preview:SetWordWrap(true)
    e.preview:SetJustifyV("TOP")
    e.add = W.MakeButton(e, "Add", 70, 20)
    e.add:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -88, 10)
    e.add:SetScript("OnClick", function()
        EditPreview()
        if not (e.units and e.money) then
            F.Print("Type how many were sold" .. (e.market.mark:IsShown() and "" or " and the money received") .. ".")
            return
        end
        if F.Sales.Adjust(Scope(), e.item.name, e.units, e.money) then
            F.Print(string.format("Added %d sold and %s received to %s (%s).", e.units, F.Money(e.money), e.item.name, F.Luck.SCOPES[Scope()] or Scope()))
        end
        e:Hide()
        U.Refresh()
    end)
    e.cancel = W.MakeButton(e, "Cancel", 70, 20)
    e.cancel:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -12, 10)
    e.cancel:SetScript("OnClick", function() e:Hide() end)
    e.qty:SetScript("OnEscapePressed", function() e:Hide() end)
    e.moneyBox:SetScript("OnEscapePressed", function() e:Hide() end)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "DeffarProfessionProfitLuckEdit" end
    e:SetPoint("CENTER", frame, "CENTER", 0, 20)
end

-- Opens the window for an AH sales row (the aggregate item: item.name is the ledger key, item.out the item ID).
function U.OpenEdit(item)
    if not frame or type(item) ~= "table" or not F.String(item.name) then return end
    if not editFrame then BuildEdit() end
    local e = editFrame
    e.item = item
    e.itemText:SetText(item.name)
    e.qty:SetText("")
    e.moneyBox:SetText("")
    e.market.mark:SetShown(true)
    e:Show()
    EditPreview()
    e.qty:SetFocus()
end

function U.Edit() return editFrame end   -- (tests)

function U.IsShown() return frame ~= nil and frame:IsShown() end
function U.Hide() if frame then frame:Hide() end end
function U.Frame() return frame end

-- Opened from the main window's Luck button: beside that window with the top edges level, so
-- the two do not overlap, on its left instead when there is no room on the right. Not saved: dragging the window still
-- saves its own position, which /dpp luck uses. Plain screen coordinates, so the top left stays the fixed point (see Place).
function U.PlaceBeside(main)
    if not (frame and main) then return end
    local left, right, top = main:GetLeft(), main:GetRight(), main:GetTop()
    if not (F.Number(left) and F.Number(right) and F.Number(top)) then return end
    local width, screen = frame:GetWidth(), UIParent:GetWidth()
    local x = right + 6
    if F.Number(width) and F.Number(screen) and x + width > screen then x = math.max(0, left - width - 6) end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top)
end

-- The main window's Luck button: the main window hides and this one opens with its top left exactly
-- where the main window's was. Not saved, like PlaceBeside.
function U.OpenFrom(main)
    local left = main and main:GetLeft()
    local top = main and main:GetTop()
    if main then main:Hide() end
    U.Show()
    if frame and F.Number(left) and F.Number(top) then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
end

-- The back button: this window closes and the main window opens with its top left where this one's was.
function U.Back()
    local left = frame and frame:GetLeft()
    local top = frame and frame:GetTop()
    if frame then frame:Hide() end
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
    F.UI.ShowAt(left, top)
end

function U.Show(beside)
    if not frame then Build() end
    frame:Show()
    U.Refresh()   -- sets the width this tab needs, which the placement below measures
    if beside then U.PlaceBeside(beside) end
end

function U.Toggle(beside)
    if frame and frame:IsShown() then frame:Hide() else U.Show(beside) end
end

-- What the table shows, as text (tests): one line per item row, then the total row last.
function U.Visible()
    local out = {}
    if not frame then return out end
    local function Line(row, name)
        local line = { name = name }
        for _, col in ipairs(COLS) do line[col.key] = row.cell[col.key]:GetText() end
        return line
    end
    for index = 1, MAX_ROWS do
        local row = rows[index]
        if row:IsShown() and row.item then out[#out + 1] = Line(row, row.name:GetText()) end
    end
    if frame.total:IsShown() then out[#out + 1] = Line(frame.total, frame.total.name:GetText()) end
    if frame.ahTotal:IsShown() then out[#out + 1] = Line(frame.ahTotal, "Auction House") end
    return out, frame.summary:GetText(), F.Luck.SCOPES[Scope()]
end
