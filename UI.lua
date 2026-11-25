-- Deffar Profession Profit: the window (/dpp). Same flat look as Forever Delete Junk and Forever Loot Value
-- (black 0.92 panel, 1px grey edge, gold title, dark rows, flat square buttons and checkboxes).
-- A sortable, paged list of the current character's learned recipes (a tab per profession: Cooking, and
-- Engineering for items a vendor buys) with what they cost, what the item sells for to a vendor, and the
-- expected profit per craft and per hour (Cooking: at the Master Chef rank; Engineering has no extra-result chance). Click a row to open it in the Cooking window (Pick.lua); [A] makes an Auctionator shopping list
-- of its materials (Shopping.lua). Every column is sized to its widest text on each refresh. Plain
-- addon-owned frames only; nothing here is protected or secure.
local _, F = ...
local U = {}
F.UI = U

local SIDE, GAP, ICON, ABTN = 8, 6, 16, 18   -- ABTN: the [A] button's width
local PAGE, ROW_H, ROW_GAP = 12, 22, 1
local NAME_MIN, NAME_MAX = 100, 230          -- the recipe column fits its longest name inside this
local MIN_WIDTH = F.Style.BASE_WIDTH          -- the least width of a window, the luck window's too (Style.lua); the header's boxes need 640 of it
local COL_PAD = 2
local COUNT_MIN = 9                            -- the count column: about a character and a half
-- The profession tab row sits under the title bar like Forever Delete Junk's (flat tabs, a thin rule beneath);
-- everything below it is that much lower (TAB_SHIFT).
local HANDLE_H = 30                          -- the title bar: the drag handle covers it
local TAB_Y, TAB_H, TAB_W = HANDLE_H, 24, 92
local TAB_SHIFT = TAB_H + 1
-- The toolbar under the tabs: rows of controls (BarSpec), each led by a caption naming its group, laid out left to right by PlaceBar
-- (no coordinates of their own). The rows and everything under them sit lower the more rows the tab has: SetBarRows.
local ROW_PITCH = 24
local CHECK_Y = 38 + TAB_SHIFT               -- the first toolbar row, from the window's top edge
local BUDGET_Y, BUY_Y = 62 + TAB_SHIFT, 86 + TAB_SHIFT   -- (where the controls are first created; PlaceBar moves them)
local HEAD_Y, ROWS_Y, FOOT_Y                 -- the column headings, the first row, the footer: SetBarRows
local barRows = 0
local function SetBarRows(n)
    barRows = n
    HEAD_Y = CHECK_Y + (n - 1) * ROW_PITCH + 26
    ROWS_Y = HEAD_Y + 18
    FOOT_Y = ROWS_Y + PAGE * (ROW_H + ROW_GAP) + 4
end
SetBarRows(3)

local GOLD, TEXT, GREY = {1, 0.82, 0}, {0.90, 0.90, 0.92}, {0.70, 0.70, 0.73}
local GREEN, RED, ORANGE = {0.35, 0.90, 0.35}, {1, 0.40, 0.40}, {1, 0.65, 0.20}
local DIVIDER = {0.30, 0.30, 0.30}
-- Forever Delete Junk's flat look: rows alternate between two dark shades, tabs have no border.
local ROW, ROWALT = {0.035, 0.035, 0.04, 0.9}, {0.065, 0.065, 0.073, 1}
local TAB_BAR, TAB_ON, TAB_HOVER = {0.035, 0.035, 0.04, 1}, {0.085, 0.07, 0.02, 1}, {0.07, 0.07, 0.075, 1}
local QUALITY = F.Style.QUALITY   -- (Style.lua: the colours the windows share)
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Columns after the name, left to right. `sort` is the key a click on the heading sorts by.
local COLS = {
    { key = "level",  head = "Level",     sort = "level" },     -- the Enchanting tab only: the item's level
    { key = "mats",   head = "Materials", sort = "mats" },
    { key = "vendor", head = "Vendor",    sort = "vendor" },
    { key = "ah",     head = "AH",        sort = "ah", optional = true },
    { key = "profit", head = "Profit",    sort = "profit" },
    { key = "hour",   head = "Profit/hr", sort = "hour" },
    { key = "margin", head = "Margin",    sort = "margin" },
    { key = "odds",   head = "Odds",      sort = "odds" },      -- the Enchanting tab only: the chance one disenchant pays
    { key = "rank",   head = "Needs",     sort = "rank" },
}

-- The detail panel (shift-click a row): one line per material under the clicked row.
local HEAD_H, LINE_H, DETAIL_MAX, DETAIL_PAD = 15, 47, 9, 8   -- LINE_H: a material's text line, its colour bar and a line of air before the next
local DETAIL_FIG = 18   -- how far below a material's first row (name and bar) its figures are
local BLOCK_PAD = 8     -- the air above and below a material's content, between its dividers; LINE_H = 8 + 30 + 8 + the divider
local LINE_H_PLAIN = 2 * BLOCK_PAD + 12 + 1   -- a material without a bar (vendor, owned): one row, name and figures together, no empty row above
local DETAIL_QTY, DETAIL_ICON = 26, 18   -- the material's name starts after its quantity ("2x") and its icon, DETAIL_PAD + this
-- The colour bar under an auction material: zones from 0 to GAUGE_SCALE x the highest price (green, orange,
-- red; Calc.PriceBand) with a tick at the highest price and a white marker at today's price.
local GAUGE_W, GAUGE_H, GAUGE_SCALE = 310, 8, 1.3
local BAND_COLORS = { green = {0.20, 0.70, 0.20, 0.60}, orange = {0.85, 0.50, 0.10, 0.60}, red = {0.80, 0.20, 0.20, 0.60} }
local BAND_TEXT = { green = GREEN, orange = ORANGE, red = RED }
-- Right edge (from the panel's right edge) and width of each right-hand column of the panel.
local DCOL = {
    now  = { right = -146, w = 78 },
    max  = { right = -62,  w = 80 },
    room = { right = -(DETAIL_PAD + GAUGE_W + 6), w = 50 },   -- in front of the bar: on its row, just left of it
}
-- What a name leaves free. On the row of a bar (the bar is GAUGE_W wide, as it was when the figures had a Source column too), the bar's left
-- edge, the pads, a gap, the quantity and the icon; on a row without a bar (vendor, owned) only the figures' columns are to its right.
local DCOL_LEFT = GAUGE_W + 2 * DETAIL_PAD + 4 + DETAIL_QTY + DETAIL_ICON + 56   -- (+ the Room figure's 50 and its gap, left of the bar)
local DCOL_LEFT_NOBAR = 146 + 78 + DETAIL_PAD + 4 + DETAIL_QTY + DETAIL_ICON
local SAGE_RGB = { 0.647, 0.722, 0.541 }   -- the quantity's colour (Style.SAGE)

local state = { page = 1, proc = true, de = false, search = "" }   -- state.search: the search box's text, lower case, not saved   -- state.expanded: the recipe ID whose detail panel is open; state.proc: the tab in use has an extra-result chance (Cooking)
local ShowTip, ShowProfitTip   -- a row's hover tooltips (defined below): U.Refresh rebuilds an open one with the new numbers
local frame, rows, headings = nil, {}, {}
local data   -- { list = the rows shown (filtered and sorted), info = Data.BuildRows info }

local function Color(texture, color)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

local function Box(target, fill, border)
    local background = target:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(target)
    Color(background, fill)
    local edges = {}
    for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
        local edge = target:CreateTexture(nil, "BORDER")
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT", target, side .. "LEFT")
            edge:SetPoint(side .. "RIGHT", target, side .. "RIGHT")
            edge:SetHeight(1)
        else
            edge:SetPoint("TOP" .. side, target, "TOP" .. side)
            edge:SetPoint("BOTTOM" .. side, target, "BOTTOM" .. side)
            edge:SetWidth(1)
        end
        Color(edge, border)
        edges[#edges + 1] = edge
    end
    return background, edges
end

local function Text(parent, template, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    local c = color or TEXT
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

local function SetText(fs, text, color)
    fs:SetText(text)
    local c = color or TEXT
    fs:SetTextColor(c[1], c[2], c[3])
end

---------------------------------------------------------------------------
-- Small widgets (same look as the Loot Value stats window)
---------------------------------------------------------------------------

-- The game's own button:
-- UIPanelButtonTemplate, the standard gold-framed button. Hover and click are added with HookScript / SetScript by the caller.
local function MakeNativeButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(text or "")
    if text and #text > 0 and F.Has(button, "SetNormalFontObject") then
        button:SetNormalFontObject("GameFontNormalSmall")   -- (a short label in a narrow button: the small font fits)
        button:SetHighlightFontObject("GameFontHighlightSmall")
    end
    return button
end

local function PaintButton(button)
    local fill, border = {0.06, 0.06, 0.07}, {0.34, 0.34, 0.37}
    if button.hover then fill = {0.10, 0.10, 0.12} end
    -- a button can be "ready" (a golden border: what it does is possible now) or "idle" (greyed out: it is not) (SetReady)
    if button.gold then border = GOLD end
    if button.idle then fill = {0.04, 0.04, 0.045} end
    Color(button.fill, fill)
    for _, edge in ipairs(button.edges) do Color(edge, border) end
    local c = button.idle and {0.36, 0.36, 0.38} or (button.accent or TEXT)
    button.label:SetTextColor(c[1], c[2], c[3])
end

-- Ready (golden border) or idle (greyed out) for a button made by MakeButton.
local function SetReady(button, ready)
    button.gold = ready == true
    button.idle = ready ~= true
    PaintButton(button)
end

-- A flat tab (Forever Delete Junk's PaintFlat): grey text on the bar, gold text on a warm fill with a gold underline when selected.
local function PaintTab(tab)
    local fill, text = TAB_BAR, GREY
    if tab.selected then fill, text = TAB_ON, GOLD end
    if tab.hover and not tab.selected then fill, text = TAB_HOVER, TEXT end
    Color(tab.fill, fill)
    tab.label:SetTextColor(text[1], text[2], text[3])
    tab.marker:SetShown(tab.selected == true)
end

-- The profession tabs: a flat row under the title bar, a gold label and underline on the one in use, a thin rule beneath.
-- The row is below the drag handle, so nothing covers a tab (an earlier placement inside the title bar lost the click).
-- Shared with the luck window (LuckUI.lua). Returns { [profession key] = tab }; the caller sets `.selected` and calls PaintTab.
-- One flat tab button (the look above); the caller positions it and sets `.selected`.
local function MakeTab(parent, label, width, height, onClick)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(width, height)
    tab:RegisterForClicks("LeftButtonUp")
    tab.fill = tab:CreateTexture(nil, "BACKGROUND")
    tab.fill:SetAllPoints()
    tab.label = Text(tab, nil, GREY, "CENTER")
    tab.label:SetPoint("CENTER")
    tab.label:SetText(label)
    tab.marker = tab:CreateTexture(nil, "ARTWORK")
    tab.marker:SetPoint("BOTTOMLEFT", 2, 1)
    tab.marker:SetPoint("BOTTOMRIGHT", -2, 1)
    tab.marker:SetHeight(2)
    Color(tab.marker, GOLD)
    tab:SetScript("OnEnter", function(self) self.hover = true; PaintTab(self) end)
    tab:SetScript("OnLeave", function(self) self.hover = false; PaintTab(self) end)
    tab:SetScript("OnClick", onClick)
    PaintTab(tab)
    return tab
end

local function MakeTabStrip(frame, onSelect, keys)
    local strip = frame:CreateTexture(nil, "BACKGROUND")
    strip:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -TAB_Y)
    strip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -TAB_Y)
    strip:SetHeight(TAB_H)
    Color(strip, TAB_BAR)
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(TAB_Y + TAB_H))
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(TAB_Y + TAB_H))
    rule:SetHeight(1)
    Color(rule, DIVIDER)
    local tabs = {}
    local previous
    for _, key in ipairs(keys or F.TAB_ORDER) do
        local tab = MakeTab(frame, F.TabDef(key).name, TAB_W, TAB_H, function() onSelect(key) end)
        if previous then tab:SetPoint("LEFT", previous, "RIGHT", 0, 0)
        else tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -TAB_Y) end
        tabs[key] = tab
        previous = tab
    end
    return tabs
end

-- Shows the tabs of `visible` (keys, in order) side by side from the left and hides the rest.
local function LayoutTabs(frame, tabs, visible)
    local previous
    for key, tab in pairs(tabs) do
        if not F.IsVisibleTab(visible, key) then tab:Hide() end
    end
    for _, key in ipairs(visible) do   -- (in the order given: the luck window has a tab the main window does not)
        local tab = tabs[key]
        if tab then
            tab:ClearAllPoints()
            if previous then tab:SetPoint("LEFT", previous, "RIGHT", 0, 0)
            else tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -TAB_Y) end
            tab:Show()
            previous = tab
        end
    end
end

local function MakeButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.fill, button.edges = Box(button, {0.06, 0.06, 0.07}, {0.34, 0.34, 0.37})
    button.label = Text(button, nil, TEXT, "CENTER")
    button.label:SetPoint("CENTER")
    button.label:SetText(text)
    button:SetScript("OnEnter", function(self) self.hover = true; PaintButton(self) end)
    button:SetScript("OnLeave", function(self) self.hover = false; PaintButton(self) end)
    return button
end

local function PaintCheck(box)
    local border = box.hover and {0.62, 0.62, 0.66} or {0.34, 0.34, 0.37}
    for _, edge in ipairs(box.edges) do Color(edge, border) end
end

-- The hover text of a toolbar control, in the shared look (Style.lua): a spec { "Title", { "grey label", "figure" }, ...,
-- { text = "a line", color = {r, g, b} }, { hint = "Click: ..." } } (or a function returning one), or a plain string (old style, white).
local function ShowControlTip(owner, tip)
    if type(GameTooltip) ~= "table" or not tip then return end
    if type(tip) == "function" then tip = tip() end
    local St = F.Style
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:ClearLines()
    if type(tip) == "string" then
        GameTooltip:AddLine(tip, 1, 1, 1, true)
    else
        St.Title(GameTooltip, tip[1])
        for index = 2, #tip do
            local row = tip[index]
            if row.hint then
                St.Hint(GameTooltip, row.hint)
            elseif row.text then
                local c = row.color or { 1, 1, 1 }
                GameTooltip:AddLine(row.text, c[1], c[2], c[3], true)
            else
                St.Line(GameTooltip, row[1], row[2])
            end
        end
    end
    GameTooltip:Show()
end

local TIPS = {}
U.TIPS, U.ShowTip = TIPS, ShowControlTip   -- (Build reaches them through U: it is at the limit of upvalues a Lua function may have)
-- the toolbar controls' hover specs, by control (filled in below, read when the pointer is over the control)

local function MakeCheck(parent, label, tip, x, y, onClick)
    local box = CreateFrame("Button", nil, parent)
    box:SetSize(140, 18)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local square = CreateFrame("Frame", nil, box)
    square:SetSize(14, 14)
    square:SetPoint("LEFT", box, "LEFT", 0, 0)
    box.fill, box.edges = Box(square, {0.06, 0.06, 0.07}, {0.34, 0.34, 0.37})
    box.mark = square:CreateTexture(nil, "ARTWORK")
    box.mark:SetSize(8, 8)
    box.mark:SetPoint("CENTER", square, "CENTER")
    Color(box.mark, GOLD)
    box.label = Text(box, nil, TEXT)
    box.label:SetPoint("LEFT", square, "RIGHT", 6, 0)
    box.label:SetText(label)
    box:SetScript("OnEnter", function(self)
        self.hover = true; PaintCheck(self)
        ShowControlTip(self, tip)
    end)
    box:SetScript("OnLeave", function(self)
        self.hover = false; PaintCheck(self)
        if type(GameTooltip) == "table" then GameTooltip:Hide() end
    end)
    box:SetScript("OnClick", onClick)
    return box
end

---------------------------------------------------------------------------
-- Rows: sort and filter
---------------------------------------------------------------------------

-- The heading of a column. In "Sell at AH" mode the sale column holds the price after the auction house's cut and the
-- comparison column the vendor price.
local function ColHead(col)
    if state.de then   -- the Enchanting tab: items to buy and disenchant
        if col.key == "mats" then return "AH price" end
        if col.key == "vendor" then return "Disenchant" end
        if col.key == "ah" then return "Vendor" end
        if col.key == "margin" then return "Return" end
        if col.key == "odds" then return "Odds" end
    end
    if F.db and F.db.sellAH == true then
        if col.key == "vendor" then return "AH net" end
        if col.key == "ah" then return "Vendor" end
    end
    if F.SellDE() then
        if col.key == "vendor" then return "DE net" end
        if col.key == "ah" then return "Vendor" end
    end
    return col.head
end

local function SellAH() return F.db ~= nil and F.db.sellAH == true end
local function SellDE() return F.SellDE() end

local function SortKey(row, key)
    local ev = row.ev
    if key == "name" then return (row.name or ""):lower() end
    if key == "mats" then return ev.complete and ev.cost or (ev.cost > 0 and ev.cost or nil) end
    if key == "vendor" then return ev.value end
    if key == "ah" then
        if state.de or SellAH() or SellDE() then return row.vendorValue end
        return row.ahValue
    end
    if key == "profit" then return ev.profit end
    if key == "hour" then return ev.perHour end
    if key == "margin" then return ev.margin end
    if key == "odds" then return row.de and row.de.odds or nil end
    if key == "level" then return row.de and row.de.level or nil end
    if key == "rank" then
        if ev.needRank == nil then return nil end
        return ev.needRank == -1 and 99 or ev.needRank
    end
    return nil
end

local function Arrange(list)
    local db = F.db
    local key, desc = db.sort or "profit", db.sortDesc ~= false
    if key == "rank" and not state.proc then key = "profit" end   -- the rank column only exists where there is a rank
    if (key == "odds" or key == "level") and not state.de then key = "profit" end
    if key == "hour" and state.de then key = "profit" end        -- and nothing is crafted on the Enchanting tab
    table.sort(list, function(a, b)
        local x, y = SortKey(a, key), SortKey(b, key)
        if x == nil and y == nil then return a.name < b.name end
        if x == nil then return false end      -- recipes without the figure sink to the bottom
        if y == nil then return true end
        if x == y then return a.name < b.name end
        if desc then return x > y end
        return x < y
    end)
end

-- No sort arrow in the text: the column the list is sorted by is gold instead, the others grey.
local function HeadingText(col)
    return ColHead(col)
end

local function HeadingColor(sortKey)
    return (F.db and (F.db.sort or "profit") or "profit") == sortKey and GOLD or GREY
end

local function Pages()
    return math.max(1, math.ceil(#data.list / PAGE))
end

---------------------------------------------------------------------------
-- Cell text (also what the column widths are measured from)
---------------------------------------------------------------------------

local function NeedText(ev, rank)
    if ev.needRank == nil then return "-", GREY end
    if ev.needRank == -1 then return "never", RED end
    if ev.needRank == 0 then return "any", GREEN end
    return "R" .. ev.needRank, ev.needRank <= rank and GREEN or ORANGE
end

-- Returns cells[key] = { text, color } for one row.
local function Cells(d, rank)
    local ev = d.ev
    local cells = {}
    if ev.missing > 0 then
        cells.mats = { ev.cost > 0 and (F.Money(ev.cost) .. " |cffff9933+?|r") or "|cffff9933?|r", TEXT }
    else
        cells.mats = { F.Money(ev.cost), TEXT }
    end
    if ev.status == "loading" then cells.vendor = { "...", GREY }
    elseif ev.status == "nosell" then cells.vendor = { SellDE() and "can't disenchant" or (SellAH() and "no AH price" or "can't sell"), GREY }
    else cells.vendor = { F.Money(ev.value), TEXT } end
    local other
    if state.de or SellAH() or SellDE() then other = d.vendorValue else other = d.ahValue end
    cells.ah = other and { F.Money(other), TEXT } or { "-", GREY }

    if d.de then cells.level = d.de.level and { tostring(math.floor(d.de.level)), GREY } or { "-", GREY } end
    if d.de and d.de.odds then
        local odds = d.de.odds
        cells.odds = { string.format("%d%%", math.floor(odds + 0.5)), odds >= 70 and GREEN or (odds >= 35 and ORANGE or RED) }
    end
    if ev.status == "ok" then
        cells.profit = { F.ProfitText(ev.profit), TEXT }   -- green above zero, red below, with a + or - (the text carries its colour)
        cells.hour = ev.perHour and { F.ProfitText(ev.perHour) .. " |cff8a8a8a/hr|r", TEXT } or { "-", GREY }
        if ev.margin then
            cells.margin = { string.format("%+.0f%%", ev.margin * 100), ev.profit >= 0 and GREEN or RED }
        else
            cells.margin = { ev.profit > 0 and "free" or "-", ev.profit > 0 and GREEN or GREY }
        end
        local text, color = NeedText(ev, rank)
        cells.rank = { text, color }
    elseif ev.status == "noprice" then
        cells.profit, cells.hour = { "no price", ORANGE }, { "-", GREY }
        cells.margin, cells.rank = { "-", GREY }, { "-", GREY }
    elseif ev.status == "nosell" then
        cells.profit, cells.hour = { "-", GREY }, { "-", GREY }
        cells.margin, cells.rank = { "-", GREY }, { "-", GREY }
    else
        cells.profit, cells.hour = { "...", GREY }, { "-", GREY }
        cells.margin, cells.rank = { "-", GREY }, { "-", GREY }
    end
    return cells
end

local function Measure(text)
    frame.measure:SetText(text)
    local width = frame.measure:GetStringWidth()
    return F.Number(width) and math.ceil(width) or 0
end

-- The widest text in each column over every row (not just the page, so paging never changes the
-- width), the heading included.
-- How many one craft makes, for the count column: a whole number as it is (2), a varying yield as its
-- average (1.5). The standard text colour for every count.
local function CountCell(ev)
    local made = ev.yield or 1
    local text = (made == math.floor(made)) and string.format("%d", made) or string.format("%.1f", made)
    return { text, TEXT }
end

local function ComputeWidths(list, rank)
    local widths = { name = Measure("Recipe"), count = 0 }
    for _, col in ipairs(COLS) do widths[col.key] = Measure(ColHead(col)) end
    for _, d in ipairs(list) do
        d.cells = Cells(d, rank)
        d.count = CountCell(d.ev)
        widths.count = math.max(widths.count, Measure(d.count[1]))
        widths.name = math.max(widths.name, Measure(d.name or ""))
        for key, cell in pairs(d.cells) do
            if widths[key] then widths[key] = math.max(widths[key], Measure(cell[1])) end
        end
    end
    widths.name = math.max(NAME_MIN, math.min(NAME_MAX, widths.name + 2))
    widths.count = math.max(COUNT_MIN, widths.count + 2)
    for _, col in ipairs(COLS) do widths[col.key] = widths[col.key] + COL_PAD end
    return widths
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

-- [A] [icon] [count] [name]: the count is how many the recipe makes (1 for most, 2 or more for the rest).
-- Its column is only as wide as its widest text (at least COUNT_MIN), so the name starts where Layout puts it.
local nameX = SIDE + 3 + ABTN + 4 + ICON + 3 + COUNT_MIN + 3   -- where the recipe name starts, from the window's left edge

local function ActiveColumns()
    local list = {}
    for _, col in ipairs(COLS) do
        if (not col.optional or (F.db and F.db.showAH == true and not state.de)) and (col.key ~= "rank" or state.proc) and (col.key ~= "odds" or state.de) and (col.key ~= "level" or state.de) and not (state.de and col.key == "hour") then list[#list + 1] = col end
    end
    return list
end

-- Positions every heading, cell and the window width for the visible columns.
local function Layout(widths)
    nameX = SIDE + 3 + ABTN + 4 + ICON + 3 + widths.count + 3
    local active, cols = {}, {}
    for _, col in ipairs(ActiveColumns()) do
        cols[#cols + 1] = { key = col.key, w = widths[col.key] }
        active[col.key] = true
    end
    -- The table rule shared with the luck window: the number columns hug their content at the
    -- right edge and the name column takes the spare width, so the window has no empty strip. The window is at least MIN_WIDTH, as
    -- wide as the luck window when that is wider ("the menus the same width"), and wider only when the columns need it.
    local opts = { gap = GAP, nameX = nameX, minName = widths.name, rightPad = SIDE + 5, width = MIN_WIDTH }
    local _, _, _, needed = F.Style.Columns(cols, opts)
    local natural = math.max(MIN_WIDTH, needed)
    state.natural = natural
    opts.width = natural
    if F.LuckUI and F.LuckUI.NaturalWidth then opts.width = math.max(natural, F.LuckUI.NaturalWidth()) end
    local pos, nameW, width = F.Style.Columns(cols, opts)
    for _, col in ipairs(ActiveColumns()) do col.x, col.w = pos[col.key].x, pos[col.key].w end
    frame:SetWidth(width)
    headings.name:ClearAllPoints()
    headings.name:SetPoint("TOPLEFT", frame, "TOPLEFT", nameX, -HEAD_Y)
    headings.name:SetWidth(nameW)
    for _, col in ipairs(COLS) do
        local heading = headings[col.key]
        if active[col.key] then
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", frame, "TOPLEFT", col.x, -HEAD_Y)
            heading:SetWidth(col.w)
            heading.label:SetText(HeadingText(col))
            local c = HeadingColor(col.sort)
            heading.label:SetTextColor(c[1], c[2], c[3])
            heading:Show()
        else
            heading:Hide()
        end
    end
    headings.name.label:SetText(HeadingText({ head = state.de and "Item" or "Recipe", sort = "name" }))
    local nameColor = HeadingColor("name")
    headings.name.label:SetTextColor(nameColor[1], nameColor[2], nameColor[3])
    for _, row in ipairs(rows) do
        row:SetWidth(width - 2 * SIDE)
        row.count:SetWidth(widths.count)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", nameX - SIDE, 0)
        row.name:SetWidth(nameW)
        row.nameHit:ClearAllPoints()
        row.nameHit:SetPoint("LEFT", row.name, "LEFT", 0, 0)
        row.nameHit:SetSize(nameW, ROW_H)
        for _, col in ipairs(COLS) do
            local cell = row.cell[col.key]
            if active[col.key] then
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", col.x - SIDE, 0)
                cell:SetWidth(col.w)
                cell:Show()
            else
                cell:Hide()
            end
            if col.key == "profit" then   -- the hover square over the Profit cell
                row.profitHit:ClearAllPoints()
                if active.profit then
                    row.profitHit:SetPoint("LEFT", row, "LEFT", col.x - SIDE, 0)
                    row.profitHit:SetSize(col.w, ROW_H)
                    row.profitHit:Show()
                else
                    row.profitHit:Hide()
                end
            end
        end
    end
    frame.note:SetWidth(width - 2 * (SIDE + 4))
    frame.empty:SetWidth(width - 60)
    frame.detail:SetWidth(width - 2 * SIDE)
    frame.detail.head:SetWidth(width - 2 * SIDE - 2 * DETAIL_PAD)
    return width
end

---------------------------------------------------------------------------
-- Tooltips that do not blink. A tooltip that is already showing on a row is changed in place: when only the words
-- of its lines changed (a count went up) just their text is set, and when nothing changed it is not touched at
-- all. ClearLines + AddLine + Show, and SetOwner above all, hide and show the tooltip again, which blinks after
-- every craft. It is only rebuilt when it is not showing on that row yet or its number of lines changed.
---------------------------------------------------------------------------

-- Another addon can hide the shared GameTooltip while the pointer is still on one of our rows: the installed
-- ExtendedVendorForever calls GameTooltip:Hide() from CloseBagSortMenu on every bag update (BagSort.lua:1300,
-- 1448), which is after every craft. That addon cannot be
-- changed from here, so when anyone but us hides the tooltip while the pointer is on the row it was showing
-- for, it is shown again at once, in the same frame, and nothing blinks. Our own hide (OnLeave) clears the row's
-- hover flag first, so it is never undone.
local lastTip, restoring, hideHooked

local function RememberTip(row, redo)
    lastTip = { row = row, redo = redo }
    if hideHooked or type(hooksecurefunc) ~= "function" or type(GameTooltip) ~= "table" or not F.Has(GameTooltip, "Hide") then return end
    hideHooked = true
    hooksecurefunc(GameTooltip, "Hide", function()
        local last = lastTip
        if restoring or not last then return end
        local row = last.row
        -- a row whose tooltip belongs to one part of it (the luck window: the item column) goes by that part
        local region = row.tipRegion or row.nameHit or row
        local over = type(region.IsMouseOver) == "function" and region:IsMouseOver() == true
        local hovering = row.tipHover
        if hovering == nil then hovering = row.hover == true end
        if hovering and over and row:IsShown() then
            restoring = true
            last.redo(row)
            restoring = false
        end
    end)
end

-- Collects AddLine / AddDoubleLine calls (same arguments as GameTooltip's) so they can be compared first.
local function NewTip()
    local tip = { lines = {} }
    function tip:AddLine(text, r, g, b, wrap)
        self.lines[#self.lines + 1] = { text = tostring(text), r = r or 1, g = g or 1, b = b or 1, wrap = wrap }
    end
    function tip:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
        self.lines[#self.lines + 1] = { text = tostring(left), right = tostring(right),
            r = lr or 1, g = lg or 1, b = lb or 1, rr = rr or 1, rg = rg or 1, rb = rb or 1 }
    end
    return tip
end

-- Sets the text of the tooltip's existing lines. Returns false when that cannot be done (a different number of
-- lines, or the line fonts are not reachable), true when the tooltip now shows these lines.
local function UpdateInPlace(lines)
    if GameTooltip:NumLines() ~= #lines then return false end
    local changed = false
    for index, line in ipairs(lines) do
        local left, right = _G["GameTooltipTextLeft" .. index], _G["GameTooltipTextRight" .. index]
        if not (F.Has(left, "GetText") and F.Has(left, "SetText")) then return false end
        if line.right ~= nil and not (F.Has(right, "GetText") and F.Has(right, "SetText")) then return false end
        if (left:GetText() or "") ~= line.text then left:SetText(line.text); changed = true end
        if line.right ~= nil and (right:GetText() or "") ~= line.right then right:SetText(line.right); changed = true end
    end
    if changed then GameTooltip:Show() end   -- lays it out again for the new widths; no hide, no blink
    return true
end

local function ShowLines(row, tip, refresh)
    local lines = tip.lines
    local showing = refresh and F.Has(GameTooltip, "IsOwned") and F.Has(GameTooltip, "IsShown")
        and GameTooltip:IsOwned(row) and GameTooltip:IsShown()
    if showing and F.Has(GameTooltip, "NumLines") and UpdateInPlace(lines) then return end
    if not showing then GameTooltip:SetOwner(row, "ANCHOR_CURSOR_RIGHT") end
    GameTooltip:ClearLines()
    for _, line in ipairs(lines) do
        if line.right ~= nil then
            GameTooltip:AddDoubleLine(line.text, line.right, line.r, line.g, line.b, line.rr, line.rg, line.rb)
        else
            GameTooltip:AddLine(line.text, line.r, line.g, line.b, line.wrap)
        end
    end
    GameTooltip:Show()
end

-- A child of a row with a tooltip of its own (the icon's item tooltip, a button): while the pointer is on it the row's own tooltip is
-- not shown. The row's OnLeave is a no-op
-- while the pointer is still inside the row (the re-anchor guard), so its hover flag, which the tooltip restore below goes by, is
-- cleared here, and when the pointer comes back onto the row, or leaves it, the row's own scripts run.
local function KeepRowTipOff(row, child)
    local function Script(name)
        if F.Has(row, "GetScript") then return row:GetScript(name) end
        return row.scripts and row.scripts[name]
    end
    child:HookScript("OnEnter", function() row.hover = false end)
    child:HookScript("OnLeave", function()
        local over = type(row.IsMouseOver) == "function" and row:IsMouseOver() == true
        if over then row.hover = true end
        local script = Script(over and "OnEnter" or "OnLeave")
        if type(script) == "function" then script(row) end
    end)
end

-- A mouse-enabled square over a row's icon: the pointer on it shows the game's own item tooltip.
-- `itemOf(row)` gives the item ID. The row's own tooltip is hidden when the pointer moves onto the icon (the row gets OnLeave) and
-- comes back when it leaves it. Clicks go through to the row.
local function MakeIconTip(row, itemOf)
    local hit = CreateFrame("Frame", nil, row)
    hit:SetAllPoints(row.icon)
    hit:EnableMouse(true)
    if F.Has(hit, "SetPropagateMouseClicks") then hit:SetPropagateMouseClicks(true) end
    hit:SetScript("OnEnter", function(self)
        local id = itemOf(row)
        if not (F.Integer(id, 1, 2147483647) and type(GameTooltip) == "table") then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if F.Has(GameTooltip, "SetItemByID") then GameTooltip:SetItemByID(id) else GameTooltip:SetHyperlink("item:" .. id) end
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    KeepRowTipOff(row, hit)
    row.iconHit = hit
    return hit
end

-- Anchors `target` to the top left of `parent` at (x, y down), but only when that is not where it already is.
-- ClearAllPoints + SetPoint on a frame under the pointer makes the game drop and re-find the frame under the
-- mouse: OnLeave (the tooltip is hidden) and OnEnter (shown again), a blink after every redraw. A redraw
-- happens after every craft, so a row that has not moved must not be re-anchored.
local function PlaceTopLeft(target, parent, x, y)
    if target.placedX == x and target.placedY == y and target.placedParent == parent then return end
    target:ClearAllPoints()
    target:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    target.placedX, target.placedY, target.placedParent = x, y, parent
end

-- Puts every row, the footer and the detail panel's gap at their heights. `openIndex` is the page
-- row the detail panel sits under (nil: no panel) and `extra` the height it adds, so the rows below
-- it and the whole footer move down by that much. Nothing that has not moved is anchored again.
local function PlaceVertical(openIndex, extra)
    for index, row in ipairs(rows) do
        local y = ROWS_Y + (index - 1) * (ROW_H + ROW_GAP)
        if openIndex and index > openIndex then y = y + extra end
        PlaceTopLeft(row, frame, SIDE, y)
    end
    local foot = FOOT_Y + (openIndex and extra or 0)
    if frame.dividerAt ~= foot then
        frame.dividerAt = foot
        frame.divider:ClearAllPoints()
        frame.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -foot)
        frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -foot)
        frame.luckButton:ClearAllPoints()
        frame.luckButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -(foot + 8))
        frame.refreshButton:ClearAllPoints()
        frame.refreshButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(SIDE + 68), -(foot + 8))
    end
    PlaceTopLeft(frame.prev, frame, SIDE, foot + 8)
    PlaceTopLeft(frame.next, frame, SIDE + 32, foot + 8)
    PlaceTopLeft(frame.pageText, frame, SIDE + 70, foot + 11)
    PlaceTopLeft(frame.note, frame, SIDE + 4, foot + 34)
    return foot
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------

-- A row is lit gold-ish while the mouse is on it and slightly while its detail panel is open.
local function PaintFill(row)
    if row.hover then
        Color(row.fill, {0.075, 0.065, 0.025, 0.95})
    elseif row.data and state.expanded == row.data.id then
        Color(row.fill, {0.055, 0.05, 0.02, 0.95})
    else
        Color(row.fill, row.alt and ROWALT or ROW)   -- every second row a little lighter
    end
end

-- The materials the player makes themselves for a row, as a sentence (empty when none): they are counted by their own
-- materials because that is cheaper than buying them (Data.lua F.Flatten).
local function ViaText(via)
    if not via or #via == 0 then return "" end
    local parts = {}
    for _, v in ipairs(via) do
        parts[#parts + 1] = F.QtyText(v.units) .. "x " .. (F.ItemMeta(v.id).name or ("Item " .. v.id))
            .. " (" .. F.Money(math.floor(v.per + 0.5)) .. " each" .. (v.market and (", buying " .. F.Money(v.market)) or "") .. ")"
    end
    return " You craft: " .. table.concat(parts, ", ") .. "."
end

-- What the bar means, on hover, with the real prices.
local function Code(c) return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end

local function ShowGaugeTip(gauge)
    local info = gauge.info
    if not info or type(GameTooltip) ~= "table" then return end
    local St = F.Style
    GameTooltip:SetOwner(gauge, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(St.ItemLabel(info.id) .. (info.total and " whole craft" or " price gauge"), GOLD[1], GOLD[2], GOLD[3])
    local function Line(left, right) GameTooltip:AddDoubleLine(left, right, St.DIM[1], St.DIM[2], St.DIM[3], 1, 1, 1) end
    Line(info.total and "All materials today" or "Today's price", F.Money(math.floor(info.unit + 0.5)) .. St.Grey(" (" .. math.floor(info.ratio * 100 + 0.5) .. "%)"))
    Line(info.total and (info.proc and string.format("Avg return per craft (+%d%% extra)", math.floor(F.Calc.Chance(info.rank) * 100 + 0.5)) or "The craft sells for") or "Highest price that breaks even", F.Money(math.floor(info.limit + 0.5)))
    if info.marginAt and info.marginAt > 0 then
        Line(St.Paint(St.TEAL, "Your Margin") .. St.Grey(" (" .. info.marginPct .. "%)"), F.Money(math.floor(info.marginAt + 0.5)))
    end
    local green, red = info.limit * info.greenAt, info.limit * info.redAt
    GameTooltip:AddLine(" ")
    -- the percentages: the craft's margin at the zone's edges (the whole craft, and a material on a tab without a rank bonus), or on a
    -- Master Chef tab's material the share of the break-even price the zone ends at (see the sentence below)
    local calc = F.Calc
    local gTag, oTag, rTag
    if info.proc and not info.total then
        gTag, oTag, rTag = " (up to " .. math.floor(calc.BAND_GREEN * 100 + 0.5) .. "%)", " (" .. math.floor(calc.BAND_GREEN * 100 + 0.5) .. "-" .. math.floor(calc.BAND_RED * 100 + 0.5) .. "%)",
            " (" .. math.floor(calc.BAND_RED * 100 + 0.5) .. "-100%)"
    else
        gTag, oTag, rTag = " (" .. math.floor(calc.MARGIN_GREEN * 100 + 0.5) .. "%+)", " (" .. math.floor(calc.MARGIN_RED * 100 + 0.5) .. "-" .. math.floor(calc.MARGIN_GREEN * 100 + 0.5) .. "%)",
            " (under " .. math.floor(calc.MARGIN_RED * 100 + 0.5) .. "%)"
    end
    Line(Code(GREEN) .. "Green|r" .. St.Grey(gTag), "up to " .. F.Money(math.floor(green + 0.5)))
    Line(Code(ORANGE) .. "Orange|r" .. St.Grey(oTag), F.Money(math.floor(green + 0.5)) .. St.Grey(" to ") .. F.Money(math.floor(red + 0.5)))
    Line(Code(RED) .. "Red|r" .. St.Grey(rTag), F.Money(math.floor(red + 0.5)) .. St.Grey(" to ") .. F.Money(math.floor(info.limit + 0.5)))
    GameTooltip:AddLine((info.proc and not info.total)
        and string.format("Zones: %d%% and %d%% of break-even.", math.floor(F.Calc.BAND_GREEN * 100 + 0.5), math.floor(F.Calc.BAND_RED * 100 + 0.5))
        or (info.total and "Zones: a margin of 20% and of 5% on all materials together." or "Zones: the prices that leave a 20% and a 5% margin."),
        St.DIM[1], St.DIM[2], St.DIM[3], true)
    GameTooltip:Show()
end

-- A short tooltip for one line of the bar: the break-even line, the Margin line or today's price.
local function ShowLineTip(hit)
    local gauge, kind = hit.gauge, hit.kind
    local info = gauge and gauge.info
    if not info or type(GameTooltip) ~= "table" then return end
    local St = F.Style
    GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local function Each(copper) return F.Money(math.floor(copper + 0.5)) .. (info.total and "" or St.Grey(" each")) end
    local function Sentence(text) GameTooltip:AddLine(text, St.DIM[1], St.DIM[2], St.DIM[3], true) end
    local function Line(left, right) GameTooltip:AddDoubleLine(left, right, St.DIM[1], St.DIM[2], St.DIM[3], 1, 1, 1) end
    if kind == "limit" then
        GameTooltip:AddLine(info.total and "Break-even cost" or "Break-even price", GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine(Each(info.limit))
        Sentence(info.total and "What the craft sells for: all materials together must cost less."
            or (info.proc and string.format("Highest price that still pays (rank %d).", info.rank or 0) or "Highest price that still pays."))
    elseif kind == "margin" then
        GameTooltip:AddLine("Your Margin" .. St.Grey(" (" .. info.marginPct .. "%)"), GOLD[1], GOLD[2], GOLD[3])   -- (gold, like the other two titles)
        GameTooltip:AddLine(Each(info.marginAt) .. St.Grey(info.total and " for all materials at most" or " at most"))
        if info.profitAtMargin then Line("Profit per craft there", St.Signed(info.profitAtMargin)) end
        if F.Number(info.profitNow) then Line("Profit per craft today", St.Signed(info.profitNow)) end
    else
        GameTooltip:AddLine(info.total and "All materials today" or "Today's price", GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine(Each(info.unit) .. St.Grey(" (" .. math.floor(info.ratio * 100 + 0.5) .. "% of break-even)"))
    end
    GameTooltip:Show()
end

-- Fills the detail panel for one row and returns its height. For every material that is bought from
-- the auction house it shows the highest price that still breaks even at the rank in use (Calc.lua
-- sets `maxUnit`); vendor materials have a fixed price, so they get no limit.
local function PaintDetail(d)
    local panel, ev = frame.detail, d.ev
    local lines = {}
    local moreCount = 0   -- materials past what the panel has room for
    if ev.status == "ok" then
        -- one short line; the table below speaks for itself
        local explain = state.proc and string.format("Break-even price per material at rank %d.", ev.rank) or "Break-even price per material."
        if d.de then explain = "Break-even price to buy it, from what it disenchants for." end
        explain = explain .. string.format(" Teal line: your Margin (%d%%).", F.Integer(F.db.margin, 0, 100) and F.db.margin or 10)
        panel.head:SetText(explain .. ViaText(d.via))
        -- an Enchanting row buys one thing, the item itself, at its auction house price; it breaks even at what it disenchants for
        local reagents = ev.reagents
        if d.de then reagents = { { id = d.itemID, qty = 1, unit = ev.cost, total = ev.cost, maxUnit = math.floor(ev.expected), de = true } } end
        for _, line in ipairs(reagents) do
            local item = F.ItemMeta(line.id)
            local cells = { qty = { F.QtyText(line.qty) .. "x", SAGE_RGB }, name = { item.name or ("Item " .. tostring(line.id)), QUALITY[item.quality or 1] or TEXT },
                now = { "", TEXT }, max = { "", GREY }, room = { "", GREY }, id = line.id, icon = item.icon }
            if d.de then cells.name = { d.name, QUALITY[item.quality or 1] or TEXT } end
            if line.free then
                cells.max, cells.now[1] = { "owned", GREY }, "free"
            elseif line.unit then
                local _, source = F.UnitCost(line.id)
                if line.de then source = "ah" end   -- (the gear piece is bought at the auction house)
                cells.now[1] = F.Money(line.unit)
                local saved = F.db.vendorBuy and F.db.vendorBuy[line.id]
                local vendorUnit = type(saved) == "table" and F.Number(saved.c) and saved.c or nil
                if source == "ah" then
                    local age = F.AuctionAge(line.id)
                    if line.maxUnit and line.maxUnit < 1 then
                        cells.max = { "none", RED }
                    elseif line.maxUnit and vendorUnit and line.maxUnit >= vendorUnit then
                        -- a vendor sells it for less than the limit, so the auction price can never be the problem
                        cells.max = { "any", GREEN }
                    elseif line.maxUnit then
                        cells.max = { F.Money(line.maxUnit), TEXT }
                        local room = (line.maxUnit - line.unit) / line.unit
                        local ratio = line.unit / line.maxUnit
                        local calc = F.Calc
                        local band, greenAt, redAt = calc.PriceBand(ratio), calc.BAND_GREEN, calc.BAND_RED
                        if not state.proc then
                            -- the zones are the prices at which the WHOLE craft's margin would be 20% and 5%, as a share of the
                            -- break-even price; the colour is the craft's margin today (no margin = a free material: green)
                            band = ev.margin and calc.MarginBand(ev.margin) or "green"
                            greenAt = math.min(1, (calc.PriceAtMargin(ev, line, calc.MARGIN_GREEN) or 0) / line.maxUnit)
                            redAt = math.min(1, (calc.PriceAtMargin(ev, line, calc.MARGIN_RED) or 0) / line.maxUnit)
                        end
                        cells.room = { string.format("%+.0f%%", room * 100), BAND_TEXT[band] or TEXT }
                        -- The Margin box's cutoff: the price at
                        -- which the whole craft's margin is the one set, every other material at today's price; a teal line on the bar.
                        local marginPct = F.Integer(F.db.margin, 0, 100) and F.db.margin or 10
                        local marginAt = calc.PriceAtMargin(ev, line, marginPct / 100)
                        -- the real figures behind the Margin line's tooltip: the craft's profit at that price and today, per craft
                        local profitAtMargin = marginAt and (ev.expected - (ev.cost - line.total + marginAt * line.qty)) or nil
                        cells.gauge = { ratio = ratio, band = band, greenAt = greenAt, redAt = redAt, unit = line.unit, limit = line.maxUnit,
                            id = line.id, proc = state.proc, rank = ev.rank, marginPct = marginPct, marginAt = marginAt,
                            profitAtMargin = profitAtMargin, profitNow = ev.profit, marginNow = ev.margin, qty = line.qty }
                    end
                else
                    cells.max = { "vendor", GREY }   -- (with the first row of its block empty above, plainly a vendor price)
                end
            else
                cells.now = { "no price", ORANGE }
            end
            lines[#lines + 1] = cells
        end
        -- The whole craft: one more bar at the bottom, in the same zones, for the total
        -- cost of the materials against what the craft sells for. Green: a margin of at least 20%; orange: 5% to 20%; red: under 5%;
        -- past the line: a loss. The teal line is the Margin box's cutoff, the white bar the materials' total today.
        if #lines > DETAIL_MAX - 1 then
            moreCount = #lines - (DETAIL_MAX - 1)
            for index = #lines, DETAIL_MAX, -1 do lines[index] = nil end
        end
        if not d.de and F.Number(ev.expected) and ev.expected > 0 and F.Number(ev.cost) then   -- (an Enchanting row's one line is the whole)
            local calc = F.Calc
            local marginPct = F.Integer(F.db.margin, 0, 100) and F.db.margin or 10
            local band = ev.margin and calc.MarginBand(ev.margin) or "green"
            local cutoff = ev.expected / (1 + marginPct / 100)   -- the most all the materials may cost and still make the Margin set
            lines[#lines + 1] = {
                qty = { F.QtyText(ev.yield or 1) .. "x", SAGE_RGB }, name = { "Whole craft", TEXT },
                now = { F.Money(ev.cost), TEXT }, max = { F.Money(math.floor(ev.expected + 0.5)), TEXT },
                room = { ev.margin and string.format("%+.0f%%", ev.margin * 100) or "-", BAND_TEXT[band] or TEXT },
                id = d.item.id, icon = d.item.icon,
                gauge = { total = true, ratio = ev.cost / ev.expected, band = band, greenAt = 1 / (1 + calc.MARGIN_GREEN), redAt = 1 / (1 + calc.MARGIN_RED),
                    unit = ev.cost, limit = ev.expected, id = d.item.id, proc = state.proc, rank = ev.rank, marginPct = marginPct, marginAt = cutoff,
                    profitAtMargin = ev.expected - cutoff, profitNow = ev.profit, marginNow = ev.margin },
            }
        end
    elseif ev.status == "noprice" then
        panel.head:SetText("A material has no price yet.")
    elseif ev.status == "nosell" then
        panel.head:SetText(SellDE() and "The result cannot be disenchanted." or (SellAH() and "No Auctionator price for the result." or "No vendor sell price."))
    else
        panel.head:SetText("Loading item data.")
    end

    local headH = F.Number(panel.head:GetStringHeight()) and math.ceil(panel.head:GetStringHeight()) or 12
    local y = DETAIL_PAD - 2 + headH + 4
    local shown = math.min(#lines, DETAIL_MAX)
    local function Put(fs, key, top, left)
        fs:ClearAllPoints()
        if key == "qty" then
            fs:SetPoint("TOPLEFT", panel, "TOPLEFT", DETAIL_PAD, -top)
            fs:SetWidth(DETAIL_QTY - 2)
        elseif key == "name" then
            fs:SetPoint("TOPLEFT", panel, "TOPLEFT", DETAIL_PAD + DETAIL_QTY + DETAIL_ICON, -top)
            fs:SetWidth(math.max(40, panel:GetWidth() - (left or DCOL_LEFT)))
        else
            fs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", DCOL[key].right, -top)
            fs:SetWidth(DCOL[key].w)
        end
    end
    panel.heads.name:SetShown(shown > 0)
    if shown == 0 then panel.roomHit:Hide() end
    for _, key in ipairs({ "now", "max", "room" }) do panel.heads[key]:SetShown(shown > 0) end
    if shown > 0 then
        for _, key in ipairs({ "now", "max", "room" }) do Put(panel.heads[key], key, y) end
        panel.roomHit:ClearAllPoints()
        panel.roomHit:SetPoint("TOPRIGHT", panel, "TOPRIGHT", DCOL.room.right, -y)
        panel.roomHit:Show()
        panel.heads.name:ClearAllPoints()
        panel.heads.name:SetPoint("TOPLEFT", panel, "TOPLEFT", DETAIL_PAD, -y)   -- "Material" over the quantity, the icon and the name
        panel.heads.name:SetWidth(math.max(40, panel:GetWidth() - DCOL_LEFT))
        y = y + HEAD_H
        panel.topDivider:ClearAllPoints()
        panel.topDivider:SetPoint("TOPLEFT", panel, "TOPLEFT", DETAIL_PAD, -(y - 1))
        panel.topDivider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -DETAIL_PAD, -(y - 1))
        panel.topDivider:Show()
    else
        panel.topDivider:Hide()
    end
    for index = 1, DETAIL_MAX do
        local widgets, cells = panel.lines[index], lines[index]
        local by = y + BLOCK_PAD   -- where the block's content starts: as far below the divider above as the divider below is under it
        -- A material with a bar (an auction price) has its name on the first row with the bar and its figures below. One without
        -- (vendor, owned, no price) has its name on the figures' row and the first row empty above it, so it is plain at a glance that
        -- there is no bar.
        local nameTop = by
        local blockH = (cells and cells.gauge) and LINE_H or LINE_H_PLAIN
        for _, key in ipairs({ "qty", "name", "now", "max", "room" }) do
            if cells and index <= shown then
                -- the quantity, the icon and the name, and the bar, are the block's first row; the source and the prices under the bar
                --
                -- the Room figure of a bar is in front of it, on the first row; the other figures are under it
                -- (a material without a bar has everything on one row; with one, the figures are under the bar)
                local top = by
                if cells.gauge and key ~= "qty" and key ~= "name" and key ~= "room" then top = by + DETAIL_FIG end
                Put(widgets[key], key, top, not cells.gauge and DCOL_LEFT_NOBAR or nil)
                SetText(widgets[key], cells[key][1], cells[key][2])
                widgets[key]:Show()
            else
                widgets[key]:Hide()
            end
        end
        -- the material's icon, with the game's item tooltip on it
        local holder = widgets.holder
        if cells and index <= shown then
            holder:ClearAllPoints()
            holder:SetPoint("TOPLEFT", panel, "TOPLEFT", DETAIL_PAD + DETAIL_QTY, -(nameTop - 1))
            holder.itemID = cells.id
            holder.icon:SetTexture(cells.icon or UNKNOWN_ICON)
            holder:Show()
        else
            holder.itemID = nil
            holder:Hide()
        end
        -- the colour bar, only for a material with an auction limit
        local gauge = widgets.gauge
        local info = cells and index <= shown and cells.gauge or nil
        gauge.info = info
        gauge.ratio, gauge.band = info and info.ratio, info and info.band
        gauge.greenAt, gauge.redAt = info and info.greenAt, info and info.redAt
        if info then
            gauge:ClearAllPoints()
            gauge:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -DETAIL_PAD, -(by - 2))
            local greenW = info.greenAt / GAUGE_SCALE * GAUGE_W
            local orangeW = (info.redAt - info.greenAt) / GAUGE_SCALE * GAUGE_W
            gauge.zones.green:SetSize(greenW, GAUGE_H)
            gauge.zones.green:ClearAllPoints(); gauge.zones.green:SetPoint("LEFT", gauge, "LEFT", 0, 0)
            gauge.zones.orange:SetSize(orangeW, GAUGE_H)
            gauge.zones.orange:ClearAllPoints(); gauge.zones.orange:SetPoint("LEFT", gauge, "LEFT", greenW, 0)
            gauge.zones.red:SetSize(GAUGE_W - greenW - orangeW, GAUGE_H)
            gauge.zones.red:ClearAllPoints(); gauge.zones.red:SetPoint("LEFT", gauge, "LEFT", greenW + orangeW, 0)
            gauge.tick:ClearAllPoints()
            gauge.tick:SetPoint("LEFT", gauge, "LEFT", GAUGE_W / GAUGE_SCALE, 0)
            -- what lies past the line (the price is over the limit: the craft loses money) is dimmed
            local limitAt = GAUGE_W / GAUGE_SCALE
            gauge.over:ClearAllPoints()
            gauge.over:SetPoint("LEFT", gauge, "LEFT", limitAt, 0)
            gauge.over:SetSize(GAUGE_W - limitAt, GAUGE_H)
            local at = math.min(info.ratio, GAUGE_SCALE) / GAUGE_SCALE * GAUGE_W
            local markerAt = math.max(0, math.min(GAUGE_W - 3, at - 1.5))
            gauge.marker:ClearAllPoints()
            gauge.marker:SetPoint("LEFT", gauge, "LEFT", markerAt, 0)
            gauge.markerBG:ClearAllPoints()
            gauge.markerBG:SetPoint("LEFT", gauge, "LEFT", markerAt - 1, 0)
            -- a square over each line to hover (ShowLineTip), centred on it
            local function Hit(name, center)
                local hit = gauge.hits[name]
                hit:ClearAllPoints()
                hit:SetPoint("LEFT", gauge, "LEFT", math.max(0, math.min(GAUGE_W - 7, center - 3.5)), 0)
                hit:Show()
            end
            Hit("limit", limitAt)
            Hit("today", markerAt + 1.5)
            if info.marginAt and info.marginAt > 0 then
                local marginX = math.max(0, math.min(GAUGE_W - 2, math.min(info.marginAt / info.limit, GAUGE_SCALE) / GAUGE_SCALE * GAUGE_W - 1))
                gauge.margin:ClearAllPoints()
                gauge.margin:SetPoint("LEFT", gauge, "LEFT", marginX, 0)
                gauge.margin:Show()
                Hit("margin", marginX + 1)
                -- what lies past the Margin cutoff (a price that leaves less than the margin set) is greyed out and hatched with slashes
                --
                local pastW = GAUGE_W - marginX - 2
                gauge.cut:ClearAllPoints()
                gauge.cut:SetPoint("LEFT", gauge, "LEFT", marginX + 2, 0)
                gauge.cut:SetSize(math.max(0, pastW), GAUGE_H)
                gauge.cut:SetShown(pastW > 0)
                local unit = Measure("/ ")
                local count = unit > 0 and math.floor((pastW - 4) / unit) or 0
                gauge.hatch:ClearAllPoints()
                gauge.hatch:SetPoint("LEFT", gauge, "LEFT", marginX + 5, 1)   -- (1 px up: the slashes sat a pixel low, past the bar's bottom edge)
                gauge.hatch:SetText(count > 0 and string.rep("/ ", count) or "")
                gauge.hatch:SetShown(count > 0)
            else
                gauge.margin:Hide()
                gauge.cut:Hide()
                gauge.hatch:Hide()
                gauge.hits.margin:Hide()
            end
            gauge:Show()
        else
            gauge:Hide()
            for _, hit in pairs(gauge.hits) do hit:Hide() end
        end
        -- a thin divider under each material, the last one too, so it is plain which figures and which bar belong to which material
        --
        local divider = widgets.divider
        if cells and index <= shown then
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", panel, "TOPLEFT", DETAIL_PAD, -(y + blockH - 1))
            divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -DETAIL_PAD, -(y + blockH - 1))
            divider:Show()
        else
            divider:Hide()
        end
        if cells and index <= shown then y = y + blockH end
    end
    if moreCount > 0 then
        panel.more:SetText("+" .. moreCount .. " more material(s) not shown")
        panel.more:ClearAllPoints()
        panel.more:SetPoint("TOPLEFT", panel, "TOPLEFT", DETAIL_PAD, -y)
        panel.more:Show()
        y = y + HEAD_H
    else
        panel.more:Hide()
    end
    local height = y + DETAIL_PAD - 2
    panel:SetHeight(height)
    return height
end

local function PaintRow(row, d)
    row.data = d
    PaintFill(row)
    row.icon:SetTexture(d.item.icon or UNKNOWN_ICON)
    -- the row whose detail panel is open (shift-click) has its name in gold, the colour of the column sorted by
    local only = d.unknown and F.Catalog.OnlySide(d.recipe) or nil   -- (a recipe only the other side's vendor sells: said in the name)
    SetText(row.name, d.name .. (only and (" " .. F.Style.RED .. "(" .. only .. " only)|r") or ""),
        (state.expanded ~= nil and state.expanded == d.id) and GOLD or (d.unknown and F.Style.RUST) or QUALITY[d.item.quality or 1] or TEXT)   -- (earthy red: not learned)
    SetText(row.count, d.count[1], d.count[2])
    for key, cell in pairs(d.cells) do
        if row.cell[key] then SetText(row.cell[key], cell[1], cell[2]) end
    end
    row.abtn:SetShown(F.ShoppingAvailable())
end

local function DateText(stamp)
    if type(date) == "function" and F.Number(stamp) and stamp > 0 then return date("%Y-%m-%d", stamp) end
    return "an earlier session"
end

local function RankLine(info)
    if not info.proc then
        return "", GREY   -- (only Cooking has an extra-result chance to name)
    end
    local chance = info.rank * F.Calc.PER_RANK
    local head = string.format("Master Chef %d/%d: %d%% extra result", info.rank, F.RANK_MAX, chance)
    if info.source == "game" then return head, TEXT end
    if info.source == "manual" then return head .. " |cff8a8a8a(set)|r", TEXT end
    if info.source == "saved" then
        return head .. " (last read " .. DateText(info.seen) .. ")", ORANGE
    end
    return "Master Chef rank unknown: using 0. Use the Rank button.", ORANGE
end

-- "3 h ago", "12 min ago", "2 d ago".
local function AgoText(seconds)
    if not F.Number(seconds) or seconds < 0 then return "?" end
    if seconds < 90 then return "just now" end
    if seconds < 5400 then return math.floor(seconds / 60 + 0.5) .. " min ago" end
    if seconds < 172800 then return math.floor(seconds / 3600 + 0.5) .. " h ago" end
    return math.floor(seconds / 86400 + 0.5) .. " d ago"
end

-- Only what needs attention; how things are worked out is in the tooltips.
local function NoteText(info)
    local notes = {}
    if info.disenchant and info.builtAt then
        -- where the list comes from: Auctionator's saved prices, read at this time (it never asks the auction house)
        notes[#notes + 1] = string.format("Built %s from %s saved prices%s%s.", type(date) == "function" and date("%H:%M:%S", info.builtAt) or "?",
            tostring(info.keys or "?"), info.scanAt and (", full scan started " .. AgoText(F.Now() - info.scanAt)) or "",
            info.newest and (info.newest == 0 and ", prices seen today" or (", newest price " .. info.newest .. " d old")) or "")
    end
    if not F.AuctionatorLoaded() then
        notes[#notes + 1] = "Auctionator not loaded."
    elseif info.oldest and info.oldest >= 1 then
        notes[#notes + 1] = string.format("Prices up to %d d old.", math.floor(info.oldest))
    end
    if info.missing > 0 then notes[#notes + 1] = info.missing .. " recipe(s) lack a price." end
    if info.loading > 0 then notes[#notes + 1] = info.loading .. (info.disenchant and " item(s) loading." or " price(s) loading.") end
    local why = info.disenchant and state.why or nil
    if why and (why.loss + why.ret + why.profit + why.odds + (why.old or 0)) > 0 then
        local parts = {}
        if why.loss > 0 then parts[#parts + 1] = why.loss .. " lose money" end
        if why.ret > 0 then parts[#parts + 1] = why.ret .. " under Min return" end
        if why.profit > 0 then parts[#parts + 1] = why.profit .. " under Min profit" end
        if why.odds > 0 then parts[#parts + 1] = why.odds .. " under Min odds" end
        if (why.old or 0) > 0 then parts[#parts + 1] = why.old .. " with a price older than Max age" end
        notes[#notes + 1] = "Hidden: " .. table.concat(parts, ", ") .. " (an item can miss several)."
    end
    if (info.assumedTime or 0) > 0 then notes[#notes + 1] = "Per hour assumes " .. F.DEFAULT_CAST .. " s per craft until measured." end
    return table.concat(notes, " ")
end

-- "Full scan ready" / "Full scan in 12:34": Auctionator's 15 minutes between full scans.
function U.UpdateScanText()
    if not frame or not frame.scanText then return end
    frame.scanText:SetShown(state.de == true)
    if not state.de then return end
    local left = F.Disenchant.ScanCooldown()
    if left <= 0 then
        SetText(frame.scanText, "Full scan ready", GREEN)
    else
        SetText(frame.scanText, string.format("Full scan in %d:%02d", math.floor(left / 60), math.floor(left % 60)), ORANGE)
    end
end


-- What each toolbar control says on hover: short labelled lines, figures coloured by meaning (a percent teal, a loss red, "free" green,
-- an unlearned recipe's earthy red), clicks in the hint blue.
local function AHCut() return F.Style.Percent(math.floor(F.AH_CUT * 100 + 0.5) .. "%") end

function TIPS.profitOnly()
    local St = F.Style
    local tip = { "Profitable only", { "Hides", St.Paint(St.RED, "recipes at a loss") } }
    if state.proc then tip[#tip + 1] = { "Profit counts", "Master Chef extras (Rank)" } end
    return tip
end
function TIPS.ownedFree()
    return { "Owned mats free", { "Mats you hold", F.Style.Paint(F.Style.GREEN, "free") }, { "Needs", "enough for 1 craft" } }
end
function TIPS.showAH()
    if (F.db and F.db.sellAH == true) or F.SellDE() then return { "Vendor column", { "Adds", "vendor price" } } end
    return { "AH column", { "Adds", "AH price (last scan)" } }
end
function TIPS.sellAH()
    return { "Sell at AH", { "Values by", "AH price" }, { "Minus", AHCut() .. " cut" }, { "Replaces", "vendor price" } }
end
function TIPS.sellDE()
    return { "Disenchant", { "Values by", "dust and essences" }, { "Minus", AHCut() .. " cut" }, { "Only", "uncommon+ gear" }, { "Needs", "Enchanting" } }
end
function TIPS.known()
    local St = F.Style
    return { "Known recipes", { "Ticked", "learned only" }, { "Unticked", "all, unlearned " .. St.Paint(St.RUSTCODE, "in red") } }
end
function TIPS.max()
    return { "Max", { "Buys", "as many as the budget allows" }, { "Untick", "to type a number" } }
end
function TIPS.budget()
    return { "Budget", { "[A] spends", "at most this, in gold" }, { "Empty", "all gold held" } }
end
function TIPS.odds()
    local St = F.Style
    return { "Confidence", { "[A] price limits", "aim to beat break-even" }, { "Chance", St.Percent("50-99%") }, { "Higher", "lower prices" } }
end
function TIPS.margin()
    local St = F.Style
    if state.de then
        return { "Min return", { "Lists", "items returning this or more" }, { "Range", St.Percent("0-100%") }, { "Also", "caps [A]'s price" } }
    end
    return { "Min margin", { "[A] price limits", "leave this profit" }, { "Range", St.Percent("0-100%") }, { "Used", "the lower of this and Confidence" } }
end
function TIPS.buy()
    return { "Buy for", { "[A] buys", "this many crafts" }, { "Empty", "Max" }, { "Capped by", "budget, price limits" } }
end
function TIPS.minProfit()
    return { "Min profit", { "Lists", "items earning this or more" }, { "0 and 0", "everything that pays" } }
end
function TIPS.minOdds()
    return { "Min odds", { "Lists", "items whose 1 disenchant pays" }, { "Range", F.Style.Percent("0-100%") }, { "0", "off" } }
end
function TIPS.maxAge()
    return { "Max age", { "Price age", "0 today, 1 + yesterday" }, { "Older", F.Style.Paint(F.Style.RED, "never listed") } }
end
function TIPS.quality()
    return { "Quality", { "Shows", "one quality" }, { "Then", "Level names its results" } }
end
function TIPS.level()
    return { "Level", { "Shows", "one item level range" }, { "Pick a quality", "to see its results" } }
end
function TIPS.search()
    return { "Search", { "Matches", "part of a name" }, { "Esc", "clears" } }
end
function TIPS.rank()
    local c = frame and frame.rankColor or TEXT
    local tip = { "Master Chef rank" }
    if frame and F.String(frame.rankLine) and frame.rankLine ~= "" then tip[#tip + 1] = { text = frame.rankLine, color = c } end
    tip[#tip + 1] = { hint = "Click: Auto, then 0-5" }
    return tip
end

-- The Enchanting tab's level dropdown. One entry per item level range of Auctionator's disenchant table (Disenchant.lua D.Bracket:
-- { lowest item level, highest, then triples of percent, quantity, item }) that some listed item falls in; with a quality chosen,
-- only that quality's ranges, each named by what it disenchants into (the same range gives other results at another quality).
function U.RangeKey(bracket)
    return string.format("%d-%d", bracket[1], bracket[2])
end

local function RangeEntries()
    local found, list = {}, {}
    for _, row in ipairs(state.all or {}) do
        local bracket = row.de and row.de.bracket
        if bracket and (not state.deQuality or (row.item and row.item.quality == state.deQuality)) then
            local key = U.RangeKey(bracket)
            if not found[key] then
                found[key] = { key = key, low = bracket[1], high = bracket[2], bracket = bracket }
                list[#list + 1] = found[key]
            end
        end
    end
    table.sort(list, function(a, b)
        if a.low ~= b.low then return a.low < b.low end
        return a.high < b.high
    end)
    return list
end

-- What a range disenchants into: the ids of its results, once each (the dropdown shows their icons, a hover names them).
local function RangeResults(entry)
    local ids, seen = {}, {}
    for x = 3, #entry.bracket, 3 do
        local id = entry.bracket[x + 2]
        if F.Integer(id, 1, 2147483647) and (entry.bracket[x] or 0) > 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    return ids
end

local function RangeText(entry)
    local text = entry.key
    if state.deQuality then   -- (one quality: the range has one set of results, shown as icons)
        for _, id in ipairs(RangeResults(entry)) do
            local icon = F.ItemMeta(id).icon
            if icon then text = text .. " |T" .. tostring(icon) .. ":14|t" end
        end
    end
    return text
end

local QUALITY_NAMES = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }

local function QualityText(quality)
    if not quality then return "All qualities" end
    return F.Style.QualityCode(quality) .. QUALITY_NAMES[quality] .. "|r"
end

function U.Refresh()
    if not frame or not frame:IsShown() then return end
    local db = F.db
    local visible = F.VisibleTabs()
    if not F.IsVisibleTab(visible, F.Tab()) then db.tab = visible[1] end   -- the saved tab is a profession this character lacks
    LayoutTabs(frame, frame.tabs, visible)
    local tab = F.Tab()
    local list, info = F.BuildRows(tab)
    state.proc = info.proc
    state.de = info.disenchant == true
    local spec = U.BarSpec(tab)
    if #spec ~= barRows then   -- (another number of toolbar rows: everything under them moves)
        SetBarRows(#spec)
        state.sig = nil
        frame.empty:ClearAllPoints()
        frame.empty:SetPoint("TOP", frame, "TOP", 0, -(ROWS_Y + 50))
    end
    state.all = state.de and list or nil   -- (every item worked out, for the level dropdown's entries)
    for key, button in pairs(frame.tabs) do
        button.selected = key == tab
        PaintTab(button)
    end
    frame.rankButton:SetShown(info.proc)
    frame.refreshButton:SetShown(info.disenchant == true)
    U.UpdateScanText()
    -- The Enchanting list holds hundreds of rows: when nothing that shapes it changed (a page turn, a mouse-over redraw) the
    -- filtered, sorted, measured list of the last repaint is reused instead of being built and measured again.
    local sig
    if info.disenchant then
        sig = table.concat({ F.Disenchant.version, tostring(info.unavailable), tostring(db.sort), tostring(db.sortDesc), tostring(state.deQuality), tostring(state.deRange),
            tostring(db.margin), tostring(db.minProfitCopper), tostring(db.minOdds), tostring(db.maxAge), tostring(db.showAH), state.search }, "|")
    end
    local shown = {}
    local reuse = sig ~= nil and sig == state.sig and data ~= nil and data.list ~= nil
    if reuse then
        shown = data.list
        data.info = info
    end
    local why = { loss = 0, ret = 0, profit = 0, odds = 0, old = 0 }   -- how many each Enchanting filter hid (an item can fail several)
    for _, row in ipairs(reuse and {} or list) do
        local keep
        if state.de then
            -- the Enchanting tab: only what returns at least the Margin on its price
            local need = (F.Integer(db.margin, 0, 100) and db.margin or 10) / 100
            local least = (F.Number(db.minProfitCopper) and db.minProfitCopper >= 0) and db.minProfitCopper or 100   -- copper
            local odds = F.Integer(db.minOdds, 0, 100) and db.minOdds or 30
            local noLoss = row.ev.profit > 0
            local enoughReturn = row.ev.margin ~= nil and row.ev.margin >= need
            local enoughProfit = row.ev.profit >= least
            local enoughOdds = row.de.odds == nil or row.de.odds >= odds   -- (an item whose odds cannot be worked out is not held to them)
            local maxAge = F.Disenchant.MaxAge()   -- (a price older than a day is not in the list at all)
            local fresh = row.de.age == nil or row.de.age <= maxAge        -- Auctionator never forgets a price: how old this one is
            keep = noLoss and enoughReturn and enoughProfit and enoughOdds and fresh   -- (the filters always apply, as the boxes are edited)
            if not noLoss then why.loss = why.loss + 1 end
            if noLoss and not enoughReturn then why.ret = why.ret + 1 end       -- (losses are counted once, as losses)
            if noLoss and not enoughProfit then why.profit = why.profit + 1 end
            if noLoss and not enoughOdds then why.odds = why.odds + 1 end
            if noLoss and not fresh then why.old = (why.old or 0) + 1 end
            -- the quality and the item level range: the bracket of Auctionator's disenchant table the item falls in
            if keep and state.deQuality and not (row.item and row.item.quality == state.deQuality) then keep = false end
            if keep and state.deRange then
                local bracket = row.de.bracket
                keep = bracket ~= nil and U.RangeKey(bracket) == state.deRange
            end
        else
            keep = not db.profitOnly or (row.ev.profit and row.ev.profit > 0)
        end
        -- the search box: the recipe's or the item's name contains what was typed
        if keep and state.search ~= "" then
            local hay = (tostring(row.name or "") .. "\n" .. tostring(row.item and row.item.name or "")):lower()
            keep = hay:find(state.search, 1, true) ~= nil
        end
        if keep then shown[#shown + 1] = row end
    end
    local revision = info.disenchant and F.Disenchant.revision or nil
    if info.disenchant then
        -- items searched for and not found are taken out of the list as drawn, the rest stays where it is
        local gone = F.Disenchant.TakeGone()
        if reuse and #gone > 0 then
            for _, row in ipairs(gone) do
                for index, shownRow in ipairs(shown) do
                    if shownRow == row then table.remove(shown, index); break end
                end
            end
            state.page = math.max(1, math.min(state.page, Pages()))
        end
    end
    if not reuse then
        Arrange(shown)
        data = { list = shown, info = info }
        state.sig, state.rev, state.why = sig, revision, why
        if info.disenchant then F.Disenchant.TakeChange() end   -- (all of it is drawn: nothing is pending)
        state.page = math.max(1, math.min(state.page, Pages()))
        Layout(ComputeWidths(shown, info.rank))
    elseif state.rev ~= revision then
        -- only numbers changed (a price was saved): the rows keep their place. A gear piece's price rewrites that row's cells
        -- alone; a material's price (every row's disenchant value) rewrites them all.
        state.rev = revision
        local change = F.Disenchant.TakeChange()
        if change.all then
            Layout(ComputeWidths(shown, info.rank))
        else
            for _, d in ipairs(change.rows) do d.cells = Cells(d, info.rank) end
        end
    end

    if not frame.budgetBox.focused then
        frame.budgetBox:SetText(db.budget and tostring(db.budget) or "")
    end
    if not frame.oddsBox.focused then frame.oddsBox:SetText(tostring(F.Integer(db.odds, 50, 99) and db.odds or 90)) end
    if not frame.marginBox.focused then frame.marginBox:SetText(tostring(F.Integer(db.margin, 0, 100) and db.margin or 10)) end
    if not frame.buyBox.focused then frame.buyBox:SetText(db.buyCrafts and tostring(db.buyCrafts) or "") end
    frame.maxCheck.mark:SetShown(db.buyCrafts == nil)
    frame.profitOnly.mark:SetShown(db.profitOnly == true)
    frame.ownedFree.mark:SetShown(db.ownedFree == true)
    frame.showAH.mark:SetShown(db.showAH == true)
    frame.sellAH.mark:SetShown(db.sellAH == true)
    frame.sellDE.mark:SetShown(db.sellDE == true)
    frame.known.mark:SetShown(db.showUnlearned ~= true)
    frame.showAH.label:SetText((db.sellAH == true or F.SellDE()) and "Vendor column" or "AH column")
    frame.marginLabel:SetText(state.de and "Min return:" or "Min margin:")
    frame.qualityButton.label:SetText(QualityText(state.deQuality))
    frame.levelButton.label:SetText(state.deRange and ("Level " .. state.deRange) or "All levels")
    U.PlaceBar(spec)
    frame.budgetHint:SetShown(frame.ctl.budget.shown and db.budget == nil)
    if not state.de then frame.qualityButton.popup:Hide(); frame.levelButton.popup:Hide() end
    local minProfit = (F.Number(db.minProfitCopper) and db.minProfitCopper >= 0) and db.minProfitCopper or 100
    if not frame.minBox.focused then frame.minBox:SetText(tostring(math.floor(minProfit / 100))) end
    if not frame.minCopperBox.focused then frame.minCopperBox:SetText(tostring(minProfit % 100)) end
    if not frame.minOddsBox.focused then frame.minOddsBox:SetText(tostring(F.Integer(db.minOdds, 0, 100) and db.minOdds or 30)) end
    if not frame.maxAgeBox.focused then frame.maxAgeBox:SetText(tostring(F.Disenchant.MaxAge())) end
    frame.rankButton.label:SetText(F.Integer(db.rankOverride, 0, F.RANK_MAX) and ("Rank: " .. db.rankOverride .. " (set)") or "Rank: Auto")
    frame.rankLine, frame.rankColor = RankLine(info)   -- (the Rank button's tooltip says it)

    local first = (state.page - 1) * PAGE
    for index = 1, PAGE do
        local row, entry = rows[index], shown[first + index]
        if entry then
            PaintRow(row, entry)
            row:Show()
        else
            row.data = nil
            row:Hide()
        end
    end

    -- the detail panel, when the shift-clicked recipe is on this page
    local openIndex, extra
    if state.expanded then
        for index = 1, PAGE do
            local entry = shown[first + index]
            if entry and entry.id == state.expanded then openIndex = index; break end
        end
    end
    if openIndex then
        extra = PaintDetail(rows[openIndex].data) + ROW_GAP
        PlaceTopLeft(frame.detail, frame, SIDE, ROWS_Y + openIndex * (ROW_H + ROW_GAP))
        frame.detail:Show()
    else
        frame.detail:Hide()
    end
    local foot = PlaceVertical(openIndex, extra or 0)

    if #shown == 0 then
        if info.unavailable then
            frame.empty:SetText("Needs Auctionator with a scan of the auction house.")
        elseif state.search ~= "" and #list > 0 then
            frame.empty:SetText("Nothing in the list matches \"" .. frame.searchBox:GetText() .. "\". Clear the search box to see the rest.")
        elseif info.disenchant and info.count == 0 then
            frame.empty:SetText(info.loading > 0 and "Loading item data." or "No gear in Auctionator's last scan disenchants for a value. Scan the auction house.")
        elseif info.count == 0 then
            local name = F.PROFESSIONS[info.prof].name
            frame.empty:SetText("No " .. name:lower() .. " recipes saved. Open your " .. name .. " window once.")
        elseif state.de and (state.deQuality ~= nil or state.deRange ~= nil) then
            frame.empty:SetText("Nothing in this quality and level range meets the filters. Pick \"All qualities\" and \"All levels\", or loosen the filters.")
        elseif state.de then
            local best
            for _, row in ipairs(list) do
                if row.ev.margin and (not best or row.ev.margin > best) then best = row.ev.margin end
            end
            frame.empty:SetText(string.format("Nothing meets Min return %d%%, Min profit %s, Min odds %d%% and Max age %dd%s. %d item(s) are listed. Loosen the filters.",
                F.Integer(db.margin, 0, 100) and db.margin or 10, F.Money(minProfit),
                F.Integer(db.minOdds, 0, 100) and db.minOdds or 30, F.Disenchant.MaxAge(),
                best and string.format("; the best returns %+d%%", math.floor(best * 100 + 0.5)) or "", #list))
        elseif db.profitOnly and not state.de then
            frame.empty:SetText("No profitable recipe. Untick \"Profitable only\" to see all.")
        else
            frame.empty:SetText("Nothing to show.")
        end
        frame.empty:Show()
    else
        frame.empty:Hide()
    end

    -- (the Enchanting list also holds losing items up to a cap, so "of" there is the number of items worked out, not the list length)
    local total = (state.de and info.stats and info.stats.listed) or #list
    frame.pageText:SetText("Page " .. state.page .. "/" .. Pages() .. "   " .. #shown .. (state.de and " item(s)" or " recipe(s)")
        .. (#shown ~= total and (" of " .. total) or ""))
    frame.prev:SetShown(Pages() > 1)
    frame.next:SetShown(Pages() > 1)

    frame.note:SetText(NoteText(info))
    local height = frame.note:GetStringHeight()
    -- the footer's room: 10 px under the page buttons, or under the note when
    -- there is one (it sits 8 px below the buttons)
    local noteH = F.Number(height) and math.ceil(height) or 0
    local content = noteH > 0 and (foot + 34 + noteH + 10) or (foot + 36)
    state.contentH = content
    -- as tall as the luck window when that needs more
    local tall = content
    if F.LuckUI and F.LuckUI.NaturalHeight then tall = math.max(content, F.LuckUI.NaturalHeight()) end
    frame:SetHeight(tall)

    -- A tooltip open on a row is rebuilt with the new figures (prices, counts) instead of being left stale or
    -- closed by the redraw; the row under the mouse may now hold another recipe after a re-sort. One whose row
    -- is gone is closed.
    for _, row in ipairs(rows) do
        local over = row.tipHover == true   -- (the pointer is on the item name or the Profit cell)
        if row:IsShown() and row.data then
            if over then (row.tipKind == "profit" and ShowProfitTip or ShowTip)(row, true) end
        elseif row.tipHover and type(GameTooltip) == "table" and F.Has(GameTooltip, "IsOwned") and GameTooltip:IsOwned(row) then
            row.tipHover = false
            GameTooltip:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------


-- A row has two tooltips, as in the luck window: over the item name the short facts
-- about it (ShowTip), over the Profit cell how the profit is worked out (ShowProfitTip). Colours and helpers: Style.lua.
function ShowTip(row, refresh)
    local d = row.data
    if not d or type(GameTooltip) ~= "table" then return end
    local ev = d.ev
    local St = F.Style
    local tip = NewTip()    -- the lines are collected first; ShowLines puts them on the tooltip (see NewTip)
    RememberTip(row, ShowTip)
    tip:AddLine((d.de and d.item.icon) and ("|T" .. tostring(d.item.icon) .. ":16|t " .. d.name) or d.name, GOLD[1], GOLD[2], GOLD[3])
    if d.de then
        F.Disenchant.TipLines(tip, d)
        ShowLines(row, tip, refresh)
        return
    end
    if d.unknown then   -- not learned: the same coloured pieces as the chat line says (Catalog.lua)
        tip:AddLine(F.Catalog.Status(d.recipe, F.Tab()))
        local source = F.Catalog.SourceLine(d.recipe)
        if source then tip:AddLine(source) end
        local bind = F.Catalog.Bind(d.recipe)   -- BoP or BoE, so a drop is not a surprise
        if bind then   -- earthy green: Binds on Equip (can be bought from a player), earthy red: Binds on Pickup (the hard one); other: grey
            local code = (bind == "Binds on Equip" and St.MOSSCODE) or (bind == "Binds on Pickup" and St.RUSTCODE) or St.GREYTEXT
            tip:AddLine(St.Paint(code, bind), 1, 1, 1)
        end
    end
    St.Line(tip, "Makes", St.Count(ev.yield == math.floor(ev.yield) and tostring(ev.yield) or string.format("%.1f", ev.yield))
        .. (d.item.id and (" x " .. St.ItemLabel(d.item.id)) or ""))
    if d.via and #d.via > 0 then   -- (a material the player crafts instead of buying)
        for _, v in ipairs(d.via) do
            tip:AddDoubleLine("You craft " .. St.Paint(St.SAGE, F.QtyText(v.units) .. "x") .. " " .. St.ItemLabel(v.id),
                F.Money(math.floor(v.per + 0.5)) .. " each", 0.5, 0.9, 0.5, 1, 1, 1)
        end
    end
    if ev.status == "noprice" then St.Note(tip, "A material has no price yet, so no profit is shown.") end
    -- what the clicks do, one short line each
    if d.unknown then
        local _, vendor = F.Catalog.Vendor(d.recipe)
        if vendor and vendor.map then tip:AddLine("Ctrl-click: Pin the vendor", 0.5, 0.8, 1) end
    else
        tip:AddLine("Click: Open recipe", 0.5, 0.8, 1)
    end
    tip:AddLine("Shift-click: Price limits", 0.5, 0.8, 1)
    ShowLines(row, tip, refresh)
end

function ShowProfitTip(row, refresh)
    local d = row.data
    if not d or type(GameTooltip) ~= "table" then return end
    local ev = d.ev
    local St = F.Style
    local tip = NewTip()
    RememberTip(row, ShowProfitTip)
    tip:AddLine("Profit: " .. d.name, GOLD[1], GOLD[2], GOLD[3])
    if d.de then   -- the Enchanting tab: what it costs, what it disenchants for, the profit and what it turns into
        F.Disenchant.ProfitLines(tip, d)
        ShowLines(row, tip, refresh)
        return
    end
    if ev.status ~= "ok" then
        if ev.status == "noprice" then St.Note(tip, "A material has no price yet, so no profit is shown.")
        elseif ev.status == "nosell" then
            tip:AddLine(SellDE() and "This cannot be disenchanted." or (SellAH() and "Auctionator has no price for this." or "This has no vendor sell price."), GREY[1], GREY[2], GREY[3], true)
        else
            tip:AddLine("Item data is still loading.", GREY[1], GREY[2], GREY[3])
        end
        ShowLines(row, tip, refresh)
        return
    end
    St.Line(tip, "Materials", ev.missing > 0 and (F.Money(ev.cost) .. " +?") or F.Money(ev.cost))
    if state.proc then   -- the average craft with the Master Chef extras (a whole craft's tooltip says the same)
        St.Line(tip, "Avg return " .. St.Grey("(+" .. math.floor(ev.chance * 100 + 0.5) .. "% extra)"), F.Money(math.floor(ev.expected + 0.5)))
    else
        St.Line(tip, "Sells for", F.Money(ev.value))
    end
    St.Line(tip, "Profit", St.Signed(ev.profit))
    if ev.perHour then St.Line(tip, "Per hour", St.Signed(ev.perHour)) end
    ShowLines(row, tip, refresh)
end

local function ShowShoppingTip(button)
    local row = button:GetParent()
    if type(GameTooltip) ~= "table" or not row.data then return end
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:ClearLines()
    if row.data.de then
        GameTooltip:AddLine("Search it at the auction house", GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine("Click: Search", 0.5, 0.8, 1)
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(string.format("Profession Profit - %s", row.data.name), GOLD[1], GOLD[2], GOLD[3])   -- the Auctionator list it makes
    GameTooltip:AddLine("Click: Make the list", 0.5, 0.8, 1)
    local ctx = F.PlanShopping(row.data)
    local function Line(left, right) GameTooltip:AddDoubleLine(left, right, F.Style.DIM[1], F.Style.DIM[2], F.Style.DIM[3], 1, 1, 1) end
    if ctx.plan then
        Line("Buys", ctx.plan.crafts .. " crafts" .. (ctx.plan.limitedBy and " (budget)" or ""))
        Line("At most", F.Money(ctx.plan.spend))
    elseif ctx.why == "margin" then
        GameTooltip:AddLine("Earns too little for the odds and margin.", RED[1], RED[2], RED[3], true)
    elseif ctx.why == "budget" then
        GameTooltip:AddLine("The budget is too small for the odds.", RED[1], RED[2], RED[3], true)
    elseif ctx.why == "notok" then
        GameTooltip:AddLine("A material has no price: quantities only.", ORANGE[1], ORANGE[2], ORANGE[3], true)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

function U.Place()
    if not frame then return end
    frame:ClearAllPoints()
    local db = F.db
    if db and F.Number(db.left) and F.Number(db.top) then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.left, db.top)
    else
        -- The top left is the fixed point, never the centre: the window's height changes when the footer text or
        -- a detail panel does, and a centred window moves its top edge by half of that, sliding the rows under the
        -- pointer (the tooltip blinks and the row under it changes).
        frame:SetPoint("TOPLEFT", UIParent, "CENTER", -330, 300)
    end
end

local function SortBy(key)
    local db = F.db
    if (db.sort or "profit") == key then
        db.sortDesc = not (db.sortDesc ~= false)
    else
        db.sort = key
        db.sortDesc = not (key == "name" or key == "mats" or key == "rank")
    end
    state.page = 1
    U.Refresh()
end

local function CycleRank()
    local db = F.db
    local current = db.rankOverride
    if not F.Integer(current, 0, F.RANK_MAX) then db.rankOverride = 0
    elseif current >= F.RANK_MAX then db.rankOverride = nil
    else db.rankOverride = current + 1 end
    U.Refresh()
end

local function Toggle(key)
    F.db[key] = not (F.db[key] == true)
    -- what a result is worth is one basis at a time: the vendor's price, the auction house's, or its disenchant
    if key == "sellAH" and F.db.sellAH then F.db.sellDE = false end
    if key == "sellDE" and F.db.sellDE then F.db.sellAH = false end
    state.page = 1
    U.Refresh()
end

local function BuildDropdowns()
    -- Enchanting tab: a quality dropdown and a level dropdown (on the row the recipe tabs use for Buy for). A flat button that opens a
    -- list under it; a click outside the list closes it.
    local function MakeDropdown(x, width, Items, Pick, tip)
        local button = MakeButton(frame, "", width, 18)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -BUY_Y)
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", button, "LEFT", 6, 0)
        button.label:SetPoint("RIGHT", button, "RIGHT", -14, 0)
        button.label:SetJustifyH("LEFT")
        button.arrow = Text(button, nil, GREY, "RIGHT")
        button.arrow:SetPoint("RIGHT", button, "RIGHT", -5, 0)
        button.arrow:SetText("v")
        local popup = CreateFrame("Frame", nil, frame)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:EnableMouse(true)
        Box(popup, {0.04, 0.04, 0.05}, {0.45, 0.45, 0.5})
        popup:Hide()
        popup.entries = {}
        popup:SetScript("OnUpdate", function(self)
            local down = type(IsMouseButtonDown) == "function" and IsMouseButtonDown("LeftButton")
            if down and not (self:IsMouseOver() or button:IsMouseOver()) then self:Hide() end
        end)
        button.popup = popup
        function button.Open()
            local list = Items()
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -1)
            local widest = 0
            for index, item in ipairs(list) do
                local entry = popup.entries[index]
                if not entry then
                    entry = CreateFrame("Button", nil, popup)
                    entry:SetHeight(18)
                    entry.hover = entry:CreateTexture(nil, "HIGHLIGHT")
                    entry.hover:SetAllPoints()
                    Color(entry.hover, { 1, 1, 1, 0.1 })
                    entry.label = Text(entry, nil, TEXT)
                    entry.label:SetPoint("LEFT", entry, "LEFT", 6, 0)
                    entry.label:SetPoint("RIGHT", entry, "RIGHT", -6, 0)
                    entry:SetScript("OnClick", function(self) popup:Hide(); Pick(self.value) end)
                    entry:SetScript("OnEnter", function(self)   -- what the entry's range disenchants into, when it has results to name
                        if type(GameTooltip) ~= "table" or not self.ids then return end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:ClearLines()
                        for _, id in ipairs(self.ids) do GameTooltip:AddLine(F.Style.ItemLabel(id), 1, 1, 1) end
                        GameTooltip:Show()
                    end)
                    entry:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
                    popup.entries[index] = entry
                end
                entry:ClearAllPoints()
                entry:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -1 - (index - 1) * 18)
                entry.value, entry.ids = item.value, item.ids
                entry.label:SetText(item.text)
                local w = entry.label:GetStringWidth()
                if F.Number(w) and w > widest then widest = w end
                entry:Show()
            end
            -- as wide as its longest entry needs (6 px each side), no wider
            local width = math.max(math.ceil(widest) + 14, 50)
            popup:SetSize(width, #list * 18 + 2)
            for index = 1, #list do popup.entries[index]:SetWidth(width - 2) end
            for index = #list + 1, #popup.entries do popup.entries[index]:Hide() end
            popup:Show()
        end
        button:SetScript("OnClick", function()
            if popup:IsShown() then popup:Hide() else button.Open() end
        end)
        button:HookScript("OnEnter", function(self) ShowControlTip(self, tip) end)
        button:HookScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
        frame:HookScript("OnHide", function() popup:Hide() end)
        return button
    end
    frame.qualityLabel = Text(frame, nil, GREY)
    frame.qualityLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 6, -(BUY_Y + 3))
    frame.qualityLabel:SetText("Quality:")
    frame.qualityButton = MakeDropdown(SIDE + 6 + 52, 92, function()
        local list = { { value = false, text = QualityText(nil) } }
        for quality = 2, 4 do list[#list + 1] = { value = quality, text = QualityText(quality) } end
        return list
    end, function(value)
        state.deQuality = value or nil
        state.deRange = nil   -- (the ranges are the quality's own)
        state.page = 1
        U.Refresh()
    end, TIPS.quality)
    frame.levelLabel = Text(frame, nil, GREY)
    frame.levelLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 6 + 52 + 92 + 10, -(BUY_Y + 3))
    frame.levelLabel:SetText("Level:")
    frame.levelButton = MakeDropdown(SIDE + 6 + 52 + 92 + 40 + 6, 92, function()
        local list = { { value = false, text = "All levels" } }
        for _, entry in ipairs(RangeEntries()) do
            list[#list + 1] = { value = entry.key, text = RangeText(entry), ids = state.deQuality and RangeResults(entry) or nil }
        end
        return list
    end, function(value)
        state.deRange = value or nil
        state.page = 1
        U.Refresh()
    end, TIPS.level)
    frame.deOnly = { frame.qualityLabel, frame.qualityButton, frame.levelLabel, frame.levelButton }
end

---------------------------------------------------------------------------
-- The toolbar. Controls are grouped in rows under a caption (View / Value / Shopping, or View / Filters on the Enchanting tab) and laid
-- out left to right by their own width, so nothing has a coordinate of its own and nothing can overlap; a right-aligned control (Search,
-- Rank) is anchored to the window's right edge. Every control is made once (Build); BarSpec says which ones the tab in use shows.
---------------------------------------------------------------------------

local CAPTION_W, BAR_GAP = 58, 12

function U.BarSpec(tab)
    local def = F.PROFESSIONS[tab] or {}
    if def.disenchant then
        return {
            { cap = "View", left = { "quality", "level" }, right = { "search" } },
            { cap = "Filters", left = { "margin", "minProfit", "minOdds", "maxAge" } },
        }
    end
    return {
        { cap = "View", left = { "profitOnly", "known" }, right = { "search" } },
        { cap = "Value", left = { "ownedFree", "showAH", "sellAH", "sellDE" }, right = { "rank" } },
        { cap = "Shopping", left = { "budget", "odds", "margin", "buy", "max" } },
    }
end

local function PartWidth(part)
    if part.text then
        local width = part.w:GetStringWidth()
        return F.Number(width) and width or 0
    end
    local width = part.w:GetWidth()
    return F.Number(width) and width or 0
end

-- `parts`: { { w = widget, text = true when it is a label, gap = px after the previous part }, ... } in reading order. Each part after
-- the first is anchored to the one before, so the control is as wide as its parts and moves as one. `side = "right"` anchors the last
-- part to the window's right edge and the others leftwards of it.
local function MakeControl(name, parts, options)
    options = options or {}
    local ctl = { name = name, parts = parts, side = options.side, show = options.show, fit = options.fit }
    if ctl.side == "right" then
        for index = #parts - 1, 1, -1 do
            parts[index].w:ClearAllPoints()
            parts[index].w:SetPoint("RIGHT", parts[index + 1].w, "LEFT", -(parts[index + 1].gap or 4), 0)
        end
        ctl.root = parts[#parts].w
    else
        for index = 2, #parts do
            parts[index].w:ClearAllPoints()
            parts[index].w:SetPoint("LEFT", parts[index - 1].w, "RIGHT", parts[index].gap or 4, 0)
        end
        ctl.root = parts[1].w
    end
    function ctl.width()
        if ctl.fit then ctl.fit() end
        local total = 0
        for index, part in ipairs(parts) do total = total + PartWidth(part) + (index > 1 and (part.gap or 4) or 0) end
        return total
    end
    function ctl.Show(on)
        ctl.shown = on
        for _, part in ipairs(parts) do part.w:SetShown(on) end
    end
    frame.ctl[name] = ctl
    return ctl
end

local function CheckControl(name, box, options)
    options = options or {}
    options.fit = function()
        local width = box.label:GetStringWidth()
        box:SetWidth(20 + (F.Number(width) and width or 0) + 4)
    end
    return MakeControl(name, { { w = box } }, options)
end

local function Field(label, box, tail)
    local parts = { { w = label, text = true }, { w = box, gap = 4 } }
    if tail then parts[#parts + 1] = { w = tail.w, text = tail.text, gap = tail.gap or 3 } end
    return parts
end

-- Makes the controls of the toolbar from the widgets Build created (the widgets keep their own look and scripts).
local function BuildBar(p)
    frame.ctl = {}
    frame.captions = {}
    for index = 1, 3 do
        frame.captions[index] = Text(frame, nil, GREY)
    end
    CheckControl("profitOnly", frame.profitOnly)
    CheckControl("known", frame.known, { show = function() return F.Catalog.Has(F.Tab()) end })
    CheckControl("ownedFree", frame.ownedFree)
    CheckControl("showAH", frame.showAH)
    CheckControl("sellAH", frame.sellAH)
    CheckControl("sellDE", frame.sellDE, { show = function()
        return (F.PROFESSIONS[F.Tab()] or {}).gear == true and F.ProfessionKnown("enchanting")   -- (only a character with Enchanting can disenchant, and only gear)
    end })
    CheckControl("max", frame.maxCheck)
    MakeControl("rank", { { w = frame.rankButton } }, { side = "right", show = function() return state.proc end })
    MakeControl("search", { { w = frame.searchLabel, text = true }, { w = frame.searchBox, gap = 6 } }, { side = "right" })
    MakeControl("budget", Field(p.budgetLabel, frame.budgetBox, { w = p.coin }))
    MakeControl("odds", Field(p.oddsLabel, frame.oddsBox, { w = p.oddsPercent, text = true }))
    MakeControl("margin", Field(frame.marginLabel, frame.marginBox, { w = p.marginPercent, text = true }))
    MakeControl("buy", Field(p.buyLabel, frame.buyBox))
    MakeControl("quality", Field(frame.qualityLabel, frame.qualityButton))
    MakeControl("level", Field(frame.levelLabel, frame.levelButton))
    MakeControl("minProfit", { { w = frame.minLabel, text = true }, { w = frame.minBox, gap = 4 }, { w = frame.minCoin, gap = 3 },
        { w = frame.minCopperBox, gap = 4 }, { w = frame.minCopperCoin, gap = 3 } })
    MakeControl("minOdds", Field(frame.minOddsLabel, frame.minOddsBox, { w = frame.minOddsPercent, text = true }))
    MakeControl("maxAge", Field(frame.maxAgeLabel, frame.maxAgeBox, { w = frame.maxAgeUnit, text = true }))
    p.buyUnit:Hide()   -- ("crafts" after the Buy for box: its tooltip says it)
    frame.budgetHint:ClearAllPoints()   -- "all gold", inside the empty Budget box
    frame.budgetHint:SetPoint("RIGHT", frame.budgetBox, "RIGHT", -6, 0)
    frame.budgetHint:SetText("all gold")
end

local function PlaceControl(ctl, point, x, y)
    local root = ctl.root
    if root.barPoint ~= point or root.barX ~= x or root.barY ~= y then
        root.barPoint, root.barX, root.barY = point, x, y
        root:ClearAllPoints()
        if point == "LEFT" then
            root:SetPoint("LEFT", frame, "TOPLEFT", x, -(y + 9))
        else
            root:SetPoint("RIGHT", frame, "TOPRIGHT", -SIDE, -(y + 9))
        end
    end
end

-- Puts the controls of `spec` (U.BarSpec) in their rows; every other control is hidden.
function U.PlaceBar(spec)
    local active = {}
    for index, row in ipairs(spec) do
        local y = CHECK_Y + (index - 1) * ROW_PITCH
        local caption = frame.captions[index]
        caption:SetText(row.cap)
        caption:ClearAllPoints()
        caption:SetPoint("LEFT", frame, "TOPLEFT", SIDE + 6, -(y + 9))
        caption:Show()
        local x = SIDE + 6 + CAPTION_W
        for _, name in ipairs(row.left) do
            local ctl = frame.ctl[name]
            if ctl and (not ctl.show or ctl.show()) then
                active[name] = true
                PlaceControl(ctl, "LEFT", x, y)
                x = x + ctl.width() + BAR_GAP
            end
        end
        for _, name in ipairs(row.right or {}) do
            local ctl = frame.ctl[name]
            if ctl and (not ctl.show or ctl.show()) then
                active[name] = true
                PlaceControl(ctl, "RIGHT", 0, y)
            end
        end
    end
    for index = #spec + 1, #frame.captions do frame.captions[index]:Hide() end
    for name, ctl in pairs(frame.ctl) do ctl.Show(active[name] == true) end
end

local function Build()
    frame = CreateFrame("Frame", "DeffarProfessionProfitFrame", UIParent)
    frame:SetSize(MIN_WIDTH, FOOT_Y + 90)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:Hide()
    Box(frame, {0, 0, 0, 0.92}, {0.20, 0.20, 0.20})
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "DeffarProfessionProfitFrame" end

    frame.measure = Text(frame, nil, TEXT)   -- never shown: only used to measure text widths
    frame.measure:Hide()

    local handle = CreateFrame("Frame", nil, frame)
    handle:SetPoint("TOPLEFT", 34, 0)   -- (starts right of the Luck button: a handle over it would take its clicks)
    handle:SetPoint("TOPRIGHT", -34, 0)
    handle:SetHeight(HANDLE_H)
    frame.handle = handle
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() frame:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local left, top = frame:GetLeft(), frame:GetTop()
        if F.db and F.Number(left) and F.Number(top) then F.db.left, F.db.top = left, top end
        U.Place()
    end)

    -- The luck window: a button reading [L] at the top left, exactly where and as wide as the luck window's
    -- back button (22 x 18), in the addon's own flat style.
    -- It does what the footer's Luck button does: this window hides and the luck window takes its place.
    frame.luckTop = MakeButton(frame, "[L]", 22, 18)
    frame.luckTop:SetPoint("TOPLEFT", 8, -6)
    frame.luckTop:SetScript("OnClick", function() F.LuckUI.OpenFrom(frame) end)
    frame.luckTop:HookScript("OnEnter", function(self)
        if type(GameTooltip) ~= "table" then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Luck: crafts, extras and what the auctions brought in", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.luckTop:HookScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    local title = Text(frame, "GameFontNormal", GOLD)
    title:SetPoint("TOPLEFT", 36, -10)
    title:SetText("Profession Profit")
    local close = MakeButton(frame, "X", 22, 18)
    close:SetPoint("TOPRIGHT", -8, -6)
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.tabs = MakeTabStrip(frame, function(key) U.SelectTab(key) end)

    -- Cooking's Rank button: the right end of the checkbox row. No line of text says the rank: its tooltip does.
    frame.rankButton = MakeButton(frame, "Rank: Auto", 104, 20)
        frame.rankButton:SetScript("OnClick", CycleRank)
    frame.rankButton:HookScript("OnEnter", function(self) U.ShowTip(self, U.TIPS.rank) end)
    frame.rankButton:HookScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)

    frame.profitOnly = MakeCheck(frame, "Profitable only", U.TIPS.profitOnly, SIDE + 6, -CHECK_Y,
        function() Toggle("profitOnly") end)
    frame.ownedFree = MakeCheck(frame, "Owned mats free", U.TIPS.ownedFree,
        SIDE + 6 + 124, -CHECK_Y, function() Toggle("ownedFree") end)
    frame.showAH = MakeCheck(frame, "AH column", U.TIPS.showAH,
        SIDE + 6 + 248, -CHECK_Y, function() Toggle("showAH") end)
    frame.sellAH = MakeCheck(frame, "Sell at AH", U.TIPS.sellAH,
        SIDE + 6 + 372, -CHECK_Y, function() Toggle("sellAH") end)
    -- the same profit from DISENCHANTING the result instead (Tailoring crafts: cloth gear): only when the character has Enchanting
    frame.sellDE = MakeCheck(frame, "Disenchant", U.TIPS.sellDE,
        SIDE + 6 + 496, -CHECK_Y, function() Toggle("sellDE") end)
    -- on the Budget row, at the right: unticked, the profession's recipes the character has not learned are listed too (Catalog.lua)
    frame.known = MakeCheck(frame, "Known recipes", U.TIPS.known,
        0, 0, function() Toggle("showUnlearned") end)

    -- Budget and odds for the [A] button (Shopping.lua): flat one-line number boxes. `commit(text)` runs when
    -- Enter is pressed or the box loses focus; Escape puts the saved value back.
    local function MakeInput(x, width, maxLetters, current, commit, tip, y)
        local box = CreateFrame("EditBox", nil, frame)
        box:SetSize(width, 18)
        box:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -(y or BUDGET_Y))
        box.fill, box.edges = Box(box, {0.06, 0.06, 0.07}, {0.34, 0.34, 0.37})
        box:SetFontObject("GameFontHighlightSmall")
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(maxLetters)
        box:SetTextInsets(5, 5, 0, 0)
        box:SetJustifyH("RIGHT")
        box:SetScript("OnEditFocusGained", function(self)
            self.focused = true
            for _, edge in ipairs(self.edges) do Color(edge, GOLD) end
        end)
        box:SetScript("OnEditFocusLost", function(self)
            self.focused = false
            for _, edge in ipairs(self.edges) do Color(edge, {0.34, 0.34, 0.37}) end
            commit(self:GetText())
            U.Refresh()
        end)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(self) self:SetText(current()); self:ClearFocus() end)
        box:SetScript("OnTextChanged", function(self) if frame.budgetHint then frame.budgetHint:SetShown(not state.de and frame.budgetBox:GetText() == "") end end)
        box:SetScript("OnEnter", function(self) U.ShowTip(self, tip) end)
        box:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
        return box
    end
    local label = Text(frame, nil, GREY)
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 6, -(BUDGET_Y + 3))
    label:SetText("Budget:")
    frame.budgetBox = MakeInput(SIDE + 6 + 50, 60, 8,
        function() return F.db.budget and tostring(F.db.budget) or "" end,
        function(text)
            local number = tonumber(text)
            F.db.budget = (number and number >= 1) and math.floor(number) or nil
        end,
        U.TIPS.budget)
    local coin = frame:CreateTexture(nil, "ARTWORK")
    coin:SetSize(12, 12)
    coin:SetPoint("LEFT", frame.budgetBox, "RIGHT", 4, 0)
    coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    frame.budgetHint = Text(frame, nil, GREY)
    frame.budgetHint:SetPoint("LEFT", coin, "RIGHT", 6, 0)
    frame.budgetHint:SetText("empty = all gold")
    local oddsLabel = Text(frame, nil, GREY)
    oddsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 6 + 250, -(BUDGET_Y + 3))
    oddsLabel:SetText("Confidence:")
    frame.oddsBox = MakeInput(SIDE + 6 + 250 + 38, 34, 2,
        function() return tostring(F.Integer(F.db.odds, 50, 99) and F.db.odds or 90) end,
        function(text)
            local number = tonumber(text)
            if F.Integer(number, 50, 99) then F.db.odds = number end
        end,
        U.TIPS.odds)
    local percent = Text(frame, nil, GREY)
    percent:SetPoint("LEFT", frame.oddsBox, "RIGHT", 4, 0)
    percent:SetText("%")
    local marginLabel = Text(frame, nil, GREY)
    marginLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 6 + 344, -(BUDGET_Y + 3))
    marginLabel:SetText("Min margin:")
    frame.marginBox = MakeInput(SIDE + 6 + 344 + 48, 34, 3,
        function() return tostring(F.Integer(F.db.margin, 0, 100) and F.db.margin or 10) end,
        function(text)
            local number = tonumber(text)
            if F.Integer(number, 0, 100) then F.db.margin = number end
        end,
        U.TIPS.margin)
    local marginPercent = Text(frame, nil, GREY)
    marginPercent:SetPoint("LEFT", frame.marginBox, "RIGHT", 4, 0)
    marginPercent:SetText("%")
    frame.marginLabel = marginLabel

    -- Enchanting tab: the least profit an item must show to be listed, in silver AND copper. Saved in copper as db.minProfitCopper.
    local MIN_PROFIT_TIP = U.TIPS.minProfit
    local function MinProfitCurrent()
        return F.Number(F.db.minProfitCopper) and F.db.minProfitCopper >= 0 and F.db.minProfitCopper or 100
    end
    local function CommitMinProfit()   -- either box was left: the two together are the setting
        local silver = tonumber(frame.minBox:GetText()) or 0
        local copper = tonumber(frame.minCopperBox:GetText()) or 0
        if F.Integer(silver, 0, 1000000) and F.Integer(copper, 0, 99) then F.db.minProfitCopper = silver * 100 + copper end
    end
    frame.minLabel = Text(frame, nil, GREY)
    frame.minLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 6 + 140, -(BUDGET_Y + 3))
    frame.minLabel:SetText("Min profit:")
    frame.minBox = MakeInput(SIDE + 6 + 140 + 62, 40, 5,
        function() return tostring(math.floor(MinProfitCurrent() / 100)) end, CommitMinProfit, MIN_PROFIT_TIP)
    frame.minCoin = frame:CreateTexture(nil, "ARTWORK")
    frame.minCoin:SetSize(12, 12)
    frame.minCoin:SetPoint("LEFT", frame.minBox, "RIGHT", 3, 0)
    frame.minCoin:SetTexture("Interface\\MoneyFrame\\UI-SilverIcon")
    frame.minCopperBox = MakeInput(SIDE + 6 + 140 + 62 + 58, 28, 2,
        function() return tostring(MinProfitCurrent() % 100) end, CommitMinProfit, MIN_PROFIT_TIP)
    frame.minCopperCoin = frame:CreateTexture(nil, "ARTWORK")
    frame.minCopperCoin:SetSize(12, 12)
    frame.minCopperCoin:SetPoint("LEFT", frame.minCopperBox, "RIGHT", 3, 0)
    frame.minCopperCoin:SetTexture("Interface\\MoneyFrame\\UI-CopperIcon")

    -- Enchanting tab: the least chance, in percent, that ONE disenchant of the item brings in more than it cost (the Odds column)
    frame.minOddsLabel = Text(frame, nil, GREY)
    frame.minOddsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 6 + 322, -(BUDGET_Y + 3))
    frame.minOddsLabel:SetText("Min odds:")
    frame.minOddsBox = MakeInput(SIDE + 6 + 322 + 56, 34, 3,
        function() return tostring(F.Integer(F.db.minOdds, 0, 100) and F.db.minOdds or 30) end,
        function(text)
            local number = tonumber(text)
            if F.Integer(number, 0, 100) then F.db.minOdds = number end
        end,
        U.TIPS.minOdds)
    frame.minOddsPercent = Text(frame, nil, GREY)
    frame.minOddsPercent:SetPoint("LEFT", frame.minOddsBox, "RIGHT", 4, 0)
    frame.minOddsPercent:SetText("%")

    -- Enchanting tab: the oldest price, in days, the list trusts (Auctionator keeps a price until a newer one replaces it, so an item
    -- sold since the last scan stays in its database): 0 = seen today
    frame.maxAgeLabel = Text(frame, nil, GREY)
    frame.maxAgeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 6 + 442, -(BUDGET_Y + 3))
    frame.maxAgeLabel:SetText("Max age:")
    frame.maxAgeBox = MakeInput(SIDE + 6 + 442 + 52, 28, 2,
        function() return tostring(F.Disenchant.MaxAge()) end,
        function(text)
            local number = tonumber(text)
            if F.Integer(number, 0, F.Disenchant.MAX_AGE) then F.db.maxAge = number end
        end,
        U.TIPS.maxAge)
    frame.maxAgeUnit = Text(frame, nil, GREY)
    frame.maxAgeUnit:SetPoint("LEFT", frame.maxAgeBox, "RIGHT", 4, 0)
    frame.maxAgeUnit:SetText("d")

    -- How many crafts [A] buys for: a number, or Max = as many as the budget allows (within the price limits).
    -- Max is ticked while no number is set (db.buyCrafts == nil).
    local buyLabel = Text(frame, nil, GREY)
    buyLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 6, -(BUY_Y + 3))
    buyLabel:SetText("Buy for:")
    frame.buyBox = MakeInput(SIDE + 6 + 50, 56, 6,
        function() return F.db.buyCrafts and tostring(F.db.buyCrafts) or "" end,
        function(text)
            local number = tonumber(text)
            F.db.buyCrafts = (number and number >= 1) and math.min(math.floor(number), 100000) or nil
        end,
        U.TIPS.buy,
        BUY_Y)
    local buyUnit = Text(frame, nil, GREY)
    buyUnit:SetPoint("LEFT", frame.buyBox, "RIGHT", 4, 0)
    buyUnit:SetText("crafts")
    frame.maxCheck = MakeCheck(frame, "Max", U.TIPS.max,
        SIDE + 6 + 50 + 56 + 50, -BUY_Y, function()
            if F.db.buyCrafts == nil then
                F.db.buyCrafts = F.Integer(F.db.crafts, 1, 100000) and F.db.crafts or 100   -- a number to start from
            else
                F.db.buyCrafts = nil
            end
            U.Refresh()
        end)
    frame.maxCheck:SetHeight(18)

    -- Search: narrows the list on every tab to the recipes or items whose name contains the text, as you
    -- type. Not saved. Escape clears it (a second Escape leaves the box).
    local function ApplySearch(text)
        state.search = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        state.page = 1
        U.Refresh()
    end
    local search = CreateFrame("EditBox", nil, frame)
    search:SetSize(170, 18)
    search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -BUY_Y)
    search.fill, search.edges = Box(search, {0.06, 0.06, 0.07}, {0.34, 0.34, 0.37})
    search:SetFontObject("GameFontHighlightSmall")
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetTextInsets(5, 5, 0, 0)
    search:SetScript("OnEditFocusGained", function(self) for _, edge in ipairs(self.edges) do Color(edge, GOLD) end end)
    search:SetScript("OnEditFocusLost", function(self) for _, edge in ipairs(self.edges) do Color(edge, {0.34, 0.34, 0.37}) end end)
    search:SetScript("OnTextChanged", function(self) ApplySearch(self:GetText()) end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end   -- (SetText runs OnTextChanged)
    end)
    search:SetScript("OnEnter", function(self) U.ShowTip(self, U.TIPS.search) end)
    search:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    frame.searchBox = search
    frame.searchLabel = Text(frame, nil, GREY)
    frame.searchLabel:SetPoint("RIGHT", search, "LEFT", -6, 0)
    frame.searchLabel:SetText("Search:")

    BuildDropdowns()

    -- the toolbar's controls, laid out by U.PlaceBar (U.Refresh)
    BuildBar({ budgetLabel = label, coin = coin, oddsLabel = oddsLabel, oddsPercent = percent, marginPercent = marginPercent,
        buyLabel = buyLabel, buyUnit = buyUnit })

    local function Heading(key, text, sortKey, justify)
        local heading = CreateFrame("Button", nil, frame)
        heading:SetSize(NAME_MIN, 14)
        heading.label = Text(heading, nil, GREY, justify)
        heading.label:SetAllPoints()
        heading.label:SetText(text)
        heading:SetScript("OnEnter", function(self) self.label:SetTextColor(TEXT[1], TEXT[2], TEXT[3]) end)
        heading:SetScript("OnLeave", function(self) local c = HeadingColor(sortKey); self.label:SetTextColor(c[1], c[2], c[3]) end)
        heading:SetScript("OnClick", function() SortBy(sortKey) end)
        headings[key] = heading
        return heading
    end
    Heading("name", "Recipe", "name", "LEFT"):SetPoint("TOPLEFT", frame, "TOPLEFT", nameX, -HEAD_Y)
    for _, col in ipairs(COLS) do Heading(col.key, col.head, col.sort, "RIGHT") end

    for index = 1, PAGE do
        local row = CreateFrame("Button", nil, frame)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -(ROWS_Y + (index - 1) * (ROW_H + ROW_GAP)))
        row:SetSize(MIN_WIDTH - 2 * SIDE, ROW_H)
        row:RegisterForClicks("LeftButtonUp")
        row:Hide()
        row.fill = row:CreateTexture(nil, "BACKGROUND")
        row.fill:SetAllPoints()
        row.alt = index % 2 == 0
        Color(row.fill, row.alt and ROWALT or ROW)

        -- [A]: Auctionator shopping list for this recipe's materials
        row.abtn = MakeButton(row, "A", ABTN, ROW_H - 6)
        row.abtn.accent = GOLD
        row.abtn.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        row.abtn:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.abtn:SetScript("OnClick", function(self)
            local parent = self:GetParent()
            if not parent.data then return end
            if parent.data.de then F.Disenchant.Search(parent.data) else F.SendShoppingList(parent.data) end
        end)
        row.abtn:HookScript("OnEnter", ShowShoppingTip)
        KeepRowTipOff(row, row.abtn)
        row.abtn:HookScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON, ICON)
        row.icon:SetPoint("LEFT", row, "LEFT", 3 + ABTN + 4, 0)
        MakeIconTip(row, function(r) local d = r.data; return d and ((d.item and d.item.id) or d.itemID) end)
        row.count = Text(row, nil, TEXT, "CENTER")
        row.count:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
        row.count:SetWidth(COUNT_MIN)
        row.name = Text(row, nil, TEXT)
        row.name:SetPoint("LEFT", row, "LEFT", nameX - SIDE, 0)
        row.name:SetWidth(NAME_MIN)
        row.cell = {}
        for _, col in ipairs(COLS) do row.cell[col.key] = Text(row, nil, TEXT, "RIGHT") end

        -- the row's tooltips: over the item name, and over the Profit cell (placed with the columns, Layout)
        local function MakeHit(kind, show)
            local hit = CreateFrame("Frame", nil, row)
            hit:SetSize(NAME_MIN, ROW_H)
            hit:EnableMouse(true)
            if F.Has(hit, "SetPropagateMouseClicks") then hit:SetPropagateMouseClicks(true) end
            -- (the row's highlight follows the pointer over these squares too: a child gives the row no OnEnter, and leaving a child
            -- straight out of the row gives it no OnLeave, which left rows stuck with the hover colour)
            hit:SetScript("OnEnter", function()
                row.hover = true; PaintFill(row)
                row.tipHover, row.tipKind, row.tipRegion = true, kind, hit; show(row)
            end)
            hit:SetScript("OnLeave", function()
                row.tipHover = false
                if type(GameTooltip) == "table" then GameTooltip:Hide() end
                if not (type(row.IsMouseOver) == "function" and row:IsMouseOver()) then row.hover = false; PaintFill(row) end
            end)
            return hit
        end
        row.nameHit = MakeHit("item", function(r) ShowTip(r) end)
        row.profitHit = MakeHit("profit", function(r) ShowProfitTip(r) end)

        -- click: open the Cooking window and select this recipe; shift-click: open or close the
        -- detail panel under it
        row:SetScript("OnClick", function(self)
            if not self.data then return end
            if self.data.de then
                if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then   -- Shift-click: the highest price to pay (the detail panel)
                    state.expanded = (state.expanded ~= self.data.id) and self.data.id or nil
                    if type(GameTooltip) == "table" then GameTooltip:Hide() end
                    U.Refresh()
                    return
                end
                if type(IsControlKeyDown) == "function" and IsControlKeyDown() then   -- Ctrl-click: this cannot be disenchanted
                    if type(GameTooltip) == "table" then GameTooltip:Hide() end
                    F.Disenchant.Block(self.data.itemID, self.data.item and self.data.item.name)
                    F.Print((self.data.item and self.data.item.name or ("item " .. self.data.itemID)) .. " hidden: it cannot be disenchanted (/dpp nodisenchant remove [item] undoes it).")
                    return
                end
                F.Disenchant.Search(self.data)   -- the Enchanting tab: search the auction house
                return
            end
            if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
                state.expanded = (state.expanded ~= self.data.id) and self.data.id or nil
                if type(GameTooltip) == "table" then GameTooltip:Hide() end
                U.Refresh()
                return
            end
            if self.data.unknown then   -- not learned: there is no recipe to open
                F.Catalog.Click(self.data.recipe, F.Tab(), type(IsControlKeyDown) == "function" and IsControlKeyDown() == true)   -- (Ctrl: pin the vendor)
                return
            end
            local ok, problem = F.OpenRecipe(self.data.id, self.data.name, F.Tab())
            if not ok then F.Print(problem) end
        end)
        row:SetScript("OnEnter", function(self)
            self.hover = true
            PaintFill(self)   -- (the tooltips belong to the name and to the Profit cell: nameHit, profitHit)
        end)
        row:SetScript("OnLeave", function(self)
            -- A leave while the pointer is still on the row is the game re-finding the frame after a redraw, not
            -- the pointer going away: keep the tooltip (hiding it here is the blink).
            if type(self.IsMouseOver) == "function" and self:IsMouseOver() then return end
            self.hover = false
            PaintFill(self)
            if type(GameTooltip) == "table" then GameTooltip:Hide() end
        end)
        rows[index] = row
    end

    -- the detail panel (shift-click a row): a header sentence, column headings and one line per material
    local detail = CreateFrame("Frame", nil, frame)
    detail:SetSize(MIN_WIDTH - 2 * SIDE, 60)
    detail:Hide()
    Box(detail, {0.045, 0.042, 0.02, 0.96}, {0.36, 0.30, 0.08})
    detail.head = Text(detail, nil, GREY)
    detail.head:SetPoint("TOPLEFT", detail, "TOPLEFT", DETAIL_PAD, -(DETAIL_PAD - 2))
    detail.head:SetWordWrap(true)
    detail.head:SetJustifyV("TOP")
    detail.heads, detail.lines = {}, {}
    local HEADS = { name = "Material", now = "Price each", max = "Highest price", room = "Room" }
    for key, label in pairs(HEADS) do
        detail.heads[key] = Text(detail, nil, GREY, key == "name" and "LEFT" or "RIGHT")
        detail.heads[key]:SetText(label)
    end
    detail.topDivider = detail:CreateTexture(nil, "BORDER")   -- under the headings: the first material's box has a top edge too
    detail.topDivider:SetHeight(1)
    Color(detail.topDivider, {0.30, 0.28, 0.16, 0.9})
    detail.topDivider:Hide()
    -- hovering the "Room" heading says what it means
    detail.roomHit = CreateFrame("Frame", nil, detail)
    detail.roomHit:SetSize(DCOL.room.w, HEAD_H)
    detail.roomHit:EnableMouse(true)
    detail.roomHit:Hide()
    detail.roomHit:SetScript("OnEnter", function(self)
        if type(GameTooltip) ~= "table" then return end
        local St = F.Style
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Room", GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine("How much the price could rise from today's before this material makes the craft stop paying (the break-even price), as a share of today's price. +73% means it could cost 73% more. Coloured like the bar: green plenty, orange tight, red barely.",
            St.DIM[1], St.DIM[2], St.DIM[3], true)
        GameTooltip:Show()
    end)
    detail.roomHit:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    for index = 1, DETAIL_MAX do
        local widgets = {}
        for key in pairs(HEADS) do widgets[key] = Text(detail, nil, TEXT, key == "name" and "LEFT" or "RIGHT") end
        widgets.qty = Text(detail, nil, TEXT, "LEFT")   -- "2x", before the icon
        widgets.divider = detail:CreateTexture(nil, "BORDER")   -- under the material
        widgets.divider:SetHeight(1)
        Color(widgets.divider, {0.30, 0.28, 0.16, 0.9})
        widgets.divider:Hide()
        -- the material's icon: a small square with the game's item tooltip on it (the same as on the list's icons)
        local holder = CreateFrame("Frame", nil, detail)
        holder:SetSize(16, 16)
        holder.icon = holder:CreateTexture(nil, "ARTWORK")
        holder.icon:SetAllPoints()
        holder:Hide()
        MakeIconTip(holder, function(h) return h.itemID end)
        widgets.holder = holder
        -- the colour bar: a dark track, three zones, a thin line at the highest price, what lies past it dimmed, and a white bar
        -- (with a dark edge) at today's price; hovering it explains them (ShowGaugeTip)
        local gauge = CreateFrame("Frame", nil, detail)
        gauge:SetSize(GAUGE_W, GAUGE_H + 8)
        gauge:Hide()
        gauge:EnableMouse(true)
        gauge.back = gauge:CreateTexture(nil, "BACKGROUND")
        gauge.back:SetSize(GAUGE_W + 2, GAUGE_H + 2)
        gauge.back:SetPoint("LEFT", gauge, "LEFT", -1, 0)
        Color(gauge.back, {0.02, 0.02, 0.02, 0.95})
        gauge.zones = {}
        for band, color in pairs(BAND_COLORS) do
            gauge.zones[band] = gauge:CreateTexture(nil, "ARTWORK")
            Color(gauge.zones[band], color)
        end
        gauge.over = gauge:CreateTexture(nil, "ARTWORK", nil, 1)
        Color(gauge.over, {0, 0, 0, 0.45})
        gauge.tick = gauge:CreateTexture(nil, "OVERLAY")
        gauge.tick:SetSize(1, GAUGE_H + 6)
        Color(gauge.tick, {1, 1, 1, 0.80})
        gauge.cut = gauge:CreateTexture(nil, "ARTWORK", nil, 2)   -- past the Margin cutoff: greyed out
        Color(gauge.cut, {0.30, 0.30, 0.32, 0.62})
        gauge.hatch = Text(gauge, nil, {0.92, 0.92, 0.94})        -- ... and hatched with slashes
        gauge.hatch:SetAlpha(0.45)
        gauge.margin = gauge:CreateTexture(nil, "OVERLAY")   -- the Margin box's cutoff: a teal line, a little taller than the bar
        gauge.margin:SetSize(2, GAUGE_H + 8)
        Color(gauge.margin, {0.56, 0.71, 0.66, 1})
        gauge.markerBG = gauge:CreateTexture(nil, "OVERLAY")
        gauge.markerBG:SetSize(5, GAUGE_H + 8)
        Color(gauge.markerBG, {0, 0, 0, 0.85})
        gauge.marker = gauge:CreateTexture(nil, "OVERLAY", nil, 1)
        gauge.marker:SetSize(3, GAUGE_H + 8)
        Color(gauge.marker, {1, 1, 1, 1})
        -- a small square over each line (the break-even line, the Margin line, today's price): its own short tooltip
        gauge.hits = {}
        for _, kind in ipairs({ "limit", "margin", "today" }) do
            local hit = CreateFrame("Frame", nil, gauge)
            hit:SetSize(7, GAUGE_H + 8)
            hit:SetFrameLevel(gauge:GetFrameLevel() + 2)
            hit:EnableMouse(true)
            hit:Hide()
            hit.gauge, hit.kind = gauge, kind
            hit:SetScript("OnEnter", function(self) ShowLineTip(self) end)
            hit:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
            gauge.hits[kind] = hit
        end
        gauge:SetScript("OnEnter", function(self) ShowGaugeTip(self) end)
        gauge:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
        widgets.gauge = gauge
        detail.lines[index] = widgets
    end
    detail.more = Text(detail, nil, GREY)
    frame.detail = detail

    frame.empty = Text(frame, nil, GREY, "CENTER")
    frame.empty:SetPoint("TOP", frame, "TOP", 0, -(ROWS_Y + 50))
    frame.empty:SetWordWrap(true)

    frame.divider = frame:CreateTexture(nil, "BORDER")
    frame.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -FOOT_Y)
    frame.divider:SetHeight(1)
    Color(frame.divider, DIVIDER)

    frame.prev = MakeButton(frame, "<", 28, 18)
    frame.prev:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -(FOOT_Y + 8))
    frame.next = MakeButton(frame, ">", 28, 18)
    frame.next:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 32, -(FOOT_Y + 8))
    frame.pageText = Text(frame, nil, GREY)
    frame.pageText:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 70, -(FOOT_Y + 11))
    -- opens the luck window (/dpp luck), at the right end of the page row
    frame.luckButton = MakeButton(frame, "Luck", 64, 18)
    frame.luckButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -(FOOT_Y + 8))
    frame.luckButton:SetScript("OnClick", function() F.LuckUI.OpenFrom(frame) end)   -- this window hides, the luck window takes its place
    -- Enchanting tab: rebuilds the list from Auctionator's prices (it otherwise holds still, only its numbers update)
    frame.refreshButton = MakeButton(frame, "Refresh", 64, 18)
    frame.refreshButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(SIDE + 68), -(FOOT_Y + 8))
    frame.refreshButton:SetScript("OnClick", function(self)
        F.Disenchant.Invalidate(); state.page = 1; U.Refresh()
        -- feedback: the list is rebuilt from Auctionator's saved prices (no auction-house query), so it is instant
        local info = data and data.info
        if info and info.disenchant then
            F.Print(string.format("Enchanting list rebuilt from Auctionator's saved prices: %s prices read%s, %d items worked out, %d shown%s. This does not search the auction house: scan it with Auctionator for new prices.",
                tostring(info.keys or "?"), info.ms and string.format(" in %.2f s", info.ms / 1000) or "", info.stats and info.stats.listed or info.count,
                data.list and #data.list or 0, info.scanAt and (". Last full scan started " .. AgoText(F.Now() - info.scanAt)
                    .. (info.newest and (info.newest == 0 and ", prices seen today" or (", newest price " .. info.newest .. " d old")) or "")) or ""))
        end
        self.label:SetText("Refreshed")   -- the button says so for a moment
        if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(1.5, function() self.label:SetText("Refresh") end)
        else
            self.label:SetText("Refresh")
        end
    end)
    frame.refreshButton:HookScript("OnEnter", function(self)
        if type(GameTooltip) ~= "table" then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Rebuilds the list from the prices Auctionator has saved. It does not ask the auction house, which is why it is instant: scan with Auctionator to get new prices. Until you press it the items stay where they are and only their numbers update, so a search does not move the list.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.refreshButton:HookScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    -- Cooldown of Auctionator's full scan, to the left of Refresh: live while the Enchanting tab shows
    frame.scanText = Text(frame, nil, GREY, "RIGHT")
    frame.scanText:SetPoint("RIGHT", frame.refreshButton, "LEFT", -8, 0)
    frame.scanTicker = CreateFrame("Frame", nil, frame)
    frame.scanTicker.wait = 0
    frame.scanTicker:SetScript("OnUpdate", function(self, elapsed)
        self.wait = self.wait + (tonumber(elapsed) or 0)
        if self.wait < 0.5 then return end
        self.wait = 0
        U.UpdateScanText()
    end)
    local function Turn(delta)
        local target = state.page + delta
        if data and target >= 1 and target <= Pages() then state.page = target; U.Refresh() end
    end
    frame.prev:SetScript("OnClick", function() Turn(-1) end)
    frame.next:SetScript("OnClick", function() Turn(1) end)
    frame:SetScript("OnMouseWheel", function(_, delta) Turn(delta > 0 and -1 or 1) end)

    frame.note = Text(frame, nil, GREY)
    frame.note:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + 4, -(FOOT_Y + 34))
    frame.note:SetWordWrap(true)
    frame.note:SetJustifyV("TOP")

    U.Place()
end

-- The flat widgets and colours, shared with the luck window (LuckUI.lua) instead of copied there.
U.W = { ShowTip = ShowControlTip, SetReady = SetReady, ABTN = ABTN, MakeCheck = MakeCheck, KeepRowTipOff = KeepRowTipOff, MakeNativeButton = MakeNativeButton, MakeIconTip = MakeIconTip, MakeTab = MakeTab, MakeTabStrip = MakeTabStrip, LayoutTabs = LayoutTabs, PaintTab = PaintTab, TAB_SHIFT = TAB_SHIFT, RememberTip = RememberTip, NewTip = NewTip, ShowLines = ShowLines, PlaceTopLeft = PlaceTopLeft, Box = Box, Text = Text, SetText = SetText, MakeButton = MakeButton, PaintButton = PaintButton, Color = Color,
    GOLD = GOLD, TEXT = TEXT, GREY = GREY, GREEN = GREEN, RED = RED, ORANGE = ORANGE, DIVIDER = DIVIDER,
    QUALITY = QUALITY, UNKNOWN_ICON = UNKNOWN_ICON }

U.TAB_Y, U.HANDLE_H = TAB_Y, HANDLE_H   -- (tests: the tab row must lie below the drag handle)
-- The width this window's columns need (the luck window matches the wider of the two windows), and the height its content needs.
function U.NaturalWidth() return state.natural or MIN_WIDTH end
function U.NaturalHeight() return state.contentH or 0 end
function U.Frame() return frame end
function U.Row(index) return rows[index] end   -- (tests)
function U.IsShown() return frame ~= nil and frame:IsShown() end
function U.Hide() if frame then frame:Hide() end end

function U.Show()
    if not frame then Build() end
    if F.HookAuctionator then F.HookAuctionator() end   -- redraw by itself when Auctionator learns new prices (Core.lua)
    state.page = 1
    state.expanded = nil
    if F.Tab() == "enchanting" and F.Disenchant then F.Disenchant.Invalidate() end   -- a fresh list each time the window is opened
    frame:Show()
    U.Refresh()
end

function U.Toggle()
    if frame and frame:IsShown() then frame:Hide() else U.Show() end
end

-- The luck window's back button: this window opens with its top left where the luck window's was. That
-- position is not saved (dragging the window still saves its own, which /dpp uses). Plain screen coordinates, as in LuckUI.PlaceBeside.
function U.ShowAt(left, top)
    U.Show()
    if frame and F.Number(left) and F.Number(top) then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
end

-- Switches the list to a profession's tab (a click on a tab, or /dpp cooking | engineering); true when it exists.
function U.SelectTab(key)
    if not F.PROFESSIONS[key] then return false end
    if key == "enchanting" and F.db.tab ~= "enchanting" then F.Disenchant.Invalidate() end   -- a fresh list on arriving
    F.db.tab = key
    state.page, state.expanded = 1, nil
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
    U.Refresh()
    return true
end

-- The open detail panel as text (tests): nil when no panel is open.
function U.Detail()
    if not frame or not frame.detail:IsShown() then return nil end
    local out = { head = frame.detail.head:GetText(), lines = {}, height = frame.detail:GetHeight() }
    for index = 1, DETAIL_MAX do
        local widgets = frame.detail.lines[index]
        if widgets.name:IsShown() then
            out.lines[#out.lines + 1] = { name = widgets.qty:GetText() .. " " .. widgets.name:GetText(), qty = widgets.qty:GetText(), item = widgets.holder.itemID,
                now = widgets.now:GetText(),
                max = widgets.max:GetText(), room = widgets.room:GetText(),
                gauge = widgets.gauge:IsShown(), band = widgets.gauge.band, ratio = widgets.gauge.ratio,
                greenAt = widgets.gauge.greenAt, redAt = widgets.gauge.redAt }
        end
    end
    return out
end

-- What the current page shows, as text (tests and /dpp status).
function U.Visible()
    local out = {}
    if not frame then return out end
    for index = 1, PAGE do
        local row = rows[index]
        if row and row:IsShown() and row.data then
            out[#out + 1] = { name = row.name:GetText(), count = row.count:GetText(), mats = row.cell.mats:GetText(), vendor = row.cell.vendor:GetText(),
                profit = row.cell.profit:GetText(), hour = row.cell.hour:GetText(),
                margin = row.cell.margin:GetText(), rank = row.cell.rank:GetText(), odds = row.cell.odds:GetText(), level = row.cell.level:GetText() }
        end
    end
    return out
end
