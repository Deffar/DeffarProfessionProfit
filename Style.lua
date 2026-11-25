-- Deffar Profession Profit: the look the windows share. One place for the tooltip palette and the helpers that build tooltip text, used by the main window (UI.lua) and
-- the luck window (LuckUI.lua). A new window or tooltip uses these instead of choosing colours of its own; plans/addons/DeffarProfessionProfit.md
-- has the style guide. Plain functions and tables only: no frames, no saved data.
--
-- Numbers have a colour by what they count, muted and earthy rather than flashy:
--   items and units   sage      crafts   sand      seconds   clay      percentages   dusty teal
--   money keeps its own gold, silver and copper (F.Money), a profit has only its sign coloured (Signed), the words between
--   are the tooltip's grey, an item is its icon and its name in the item's quality colour (ItemLabel).
local _, F = ...
local S = {}
F.Style = S

S.DIM = { 0.7, 0.7, 0.73 }            -- the left side of a tooltip line
S.ORANGE = { 1, 0.65, 0.2 }            -- a remark
S.RUST = { 0.78, 0.38, 0.33 }            -- an earthy red: a recipe the character has not learned (a name in the main window)
S.RUSTCODE = "|cffc76152"                      -- the same as a colour code (chat lines)
S.MOSS = { 0.45, 0.65, 0.35 }            -- an earthy green: the easy one of a pair (Binds on Equip); RUST is the hard one (Binds on Pickup)
S.MOSSCODE = "|cff73a659"
S.QUALITY = { [0] = {0.62, 0.62, 0.62}, [1] = {0.90, 0.90, 0.92}, [2] = {0.12, 1, 0},
    [3] = {0, 0.44, 0.87}, [4] = {0.64, 0.21, 0.93}, [5] = {1, 0.50, 0} }

local SAGE, SAND, CLAY, TEAL, GREYTEXT = "|cffa5b88a", "|cffd2b787", "|cffc98f6e", "|cff8fb5a8", "|cffb3b3ba"
S.SAGE, S.SAND, S.CLAY, S.TEAL, S.GREYTEXT = SAGE, SAND, CLAY, TEAL, GREYTEXT
S.GREEN, S.RED = "|cff59e659", "|cffff6666"
S.GOLDCODE = "|cffffd100"   -- the title gold as a colour code (the "Craft:" label of the "+" tooltips)   -- the + and - of a profit; also "you have it" and "something is missing"

function S.Paint(code, text) return code .. text .. "|r" end

function S.Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

function S.Items(n) return S.Paint(SAGE, S.Plural(n, "item", "items")) end      -- "26 items"
function S.Crafts(n) return S.Paint(SAND, S.Plural(n, "craft", "crafts")) end   -- "18 crafts"
function S.Seconds(text) return S.Paint(CLAY, text) end                          -- "3.0 s"
function S.Percent(text) return S.Paint(TEAL, text) end                          -- "44%"
function S.Count(n) return S.Paint(SAGE, tostring(n)) end                        -- a bare number of items or units
function S.Grey(text) return S.Paint(GREYTEXT, text) end

-- A profit in a tooltip: only the sign is coloured (green +, red -), the amount keeps the gold, silver and copper of any money. The
-- table cells keep F.ProfitText, which colours all of it.
function S.Signed(copper)
    if not F.Number(copper) then return "?" end
    local value = math.floor(math.abs(copper) + 0.5)
    if value == 0 then return F.Money(0) end
    return (copper > 0 and (S.GREEN .. "+|r") or (S.RED .. "-|r")) .. F.Money(value)
end

-- "|cffrrggbb" for an item quality (0 grey ... 5 orange).
function S.QualityCode(quality)
    local c = S.QUALITY[quality or 1] or S.QUALITY[1]
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- "2x [icon] Name": the item's icon in front and the name in its quality colour, like Disenchant Buddy's tooltip (an item not loaded
-- yet shows "Item 123" until it is).
function S.ItemLabel(id, quantity)
    local meta = F.ItemMeta(id)
    return (quantity and (quantity .. "x ") or "") .. (meta.icon and ("|T" .. tostring(meta.icon) .. ":0|t ") or "")
        .. S.QualityCode(meta.quality) .. (meta.name or ("Item " .. tostring(id))) .. "|r"
end

-- A tooltip line: a grey label on the left, the figure on the right. `tip` is the collecting tip of UI.lua (NewTip) or the game's tooltip.
function S.Line(tip, left, right)
    tip:AddDoubleLine(left, right, S.DIM[1], S.DIM[2], S.DIM[3], 1, 1, 1)
end

-- The pieces of the "+" buttons' tooltips (and of any new tooltip), so that no tooltip builds its own look:
--   S.Title(tip, "Create All")                       the gold title line
--   S.ItemQty(id, name, 5, S.SAND)                   "[icon] Item x5"  (S.SAND for crafts, S.SAGE for items to buy)
--   S.PerTotal(profit, total [, "AH"])               "+2s20c per (+11s total)": signed money, grey words, optional grey label
--   S.Reason(tip, "Nothing to buy.")                 a short reason in the tooltip grey (not orange)
function S.Title(tip, text) tip:AddLine(text, 1, 0.82, 0) end

-- A divider line in a tooltip: a row of grey underscores as wide as the tooltip is. The width is only known once the tooltip is shown
-- (the other lines make it), so a rule starts as one underscore (it must not make the tooltip wider) and S.FitRules, called right after
-- Show, fills it. Where the game's tooltip lines cannot be reached (the tests) it is a fixed row.
-- The line numbers are the game's own (GameTooltip:NumLines); S.StartRules forgets the rules of an earlier tooltip.
S.rules = {}
function S.StartRules() S.rules = {} end
function S.Rule(tip)
    local reachable = type(tip.NumLines) == "function" and type(_G.GameTooltipTextLeft1) == "table"
    tip:AddLine(S.Paint(S.GREYTEXT, reachable and "_" or string.rep("_", 24)), 1, 1, 1)
    if reachable then S.rules[#S.rules + 1] = tip:NumLines() end
end
function S.FitRules(tip)
    local rules = S.rules
    S.rules = {}
    if #rules == 0 or type(tip.GetWidth) ~= "function" or type(tip.CreateFontString) ~= "function" then return end
    if not S.ruleMeasure then
        S.ruleMeasure = tip:CreateFontString(nil, "ARTWORK", "GameTooltipText")   -- (the tooltip's own font, never shown)
        S.ruleMeasure:Hide()
    end
    S.ruleMeasure:SetText("_")
    local unit, width = S.ruleMeasure:GetStringWidth(), tip:GetWidth()
    if not (F.Number(unit) and unit > 0 and F.Number(width)) then return end
    local count = math.max(4, math.floor((width - 22) / unit))   -- (the tooltip keeps about 10 px at each side of its text)
    for _, index in ipairs(rules) do
        local line = _G["GameTooltipTextLeft" .. index]
        if type(line) == "table" then line:SetText(S.Paint(S.GREYTEXT, string.rep("_", count))) end
    end
    tip:Show()
end

-- The click lines of a tooltip ("Click: Open recipe"): the hint blue, one short line each.
S.HINT = { 0.5, 0.8, 1 }
function S.Hint(tip, text) tip:AddLine(text, S.HINT[1], S.HINT[2], S.HINT[3]) end

function S.Reason(tip, text) tip:AddLine(text, S.DIM[1], S.DIM[2], S.DIM[3], true) end

-- "You hold the materials." in green, and "Missing: a, b" with a red label and the names in white (a state of the button, not a remark)
function S.Good(tip, text) tip:AddLine(S.Paint(S.GREEN, text), 1, 1, 1, true) end
function S.Missing(tip, names) tip:AddLine(S.Paint(S.RED, "Missing:") .. " " .. names, 1, 1, 1, true) end

function S.ItemQty(id, name, quantity, code)
    local label = F.Integer(id, 1, 2147483647) and S.ItemLabel(id) or name
    return label .. " " .. S.Paint(code or S.SAND, "x" .. quantity)
end

function S.PerTotal(each, total, label)
    return (label and (S.Grey(label .. " ")) or "") .. S.Signed(each) .. S.Grey(" per (") .. S.Signed(total) .. S.Grey(" total)")
end

function S.Note(tip, text)   -- an orange remark that wraps
    tip:AddLine(text, S.ORANGE[1], S.ORANGE[2], S.ORANGE[3], true)
end

---------------------------------------------------------------------------
-- Columns
---------------------------------------------------------------------------

S.BASE_WIDTH = 660   -- the least width of a window: both windows start from it, and a window is only wider when its columns need it

-- One rule for the tables of both windows. The number columns are as wide as their content, a small gap apart, and sit at the right
-- edge; the name column is the flexible one and takes whatever width is left, so there is no empty strip at the right and a wider
-- window gives the names more room. `cols` is the visible columns left to right, { { key, w } }; `opts` is { gap, nameX (where the
-- name starts, from the window's left edge), minName (the least the name column may get), rightPad (the margin at the right),
-- width (the width asked for, 0 for none) }. Returns positions ({ [key] = { x, w } }, x from the window's left edge), the name
-- column's width, the window width (the asked width, or more when the columns need it) and the least width that fits them.
function S.Columns(cols, opts)
    local total = 0
    for _, c in ipairs(cols) do total = total + c.w end
    local need = opts.nameX + opts.minName + #cols * opts.gap + total + opts.rightPad
    local width = math.max(opts.width or 0, need)
    local right = width - opts.rightPad
    local pos = {}
    for i = #cols, 1, -1 do
        local c = cols[i]
        pos[c.key] = { x = right - c.w, w = c.w }
        right = right - c.w - opts.gap
    end
    return pos, right - opts.nameX, width, need
end
