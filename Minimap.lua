-- Deffar Profession Profit: the minimap button. Left-click opens or closes the window, right-click the luck window, drag moves it
-- around the minimap edge. The angle is saved (db.minimapAngle, degrees) and /dpp minimap shows or hides the button (db.minimapHidden).
-- No library: the button is built here with the game's standard minimap button textures, so it looks like the other addons' buttons.
local addonName, F = ...
local M = {}
F.Minimap = M

local DEFAULT_ANGLE = 225   -- bottom left of the minimap
local EDGE = 5              -- how far the button's centre sits outside the minimap's radius

-- The button's offset from the minimap's centre for an angle in degrees: on a circle, or on the square's edge for a square minimap.
function M.Offset(angle, radius, square)
    local rad = math.rad(angle)
    local x, y = math.cos(rad) * radius, math.sin(rad) * radius
    if square then
        local limit = radius   -- the half width plus the gap: the button rides the edge of the square
        x = math.max(-limit, math.min(limit, x * math.sqrt(2)))
        y = math.max(-limit, math.min(limit, y * math.sqrt(2)))
    end
    return x, y
end

local function Radius()
    local minimap = _G.Minimap
    local width = minimap and type(minimap.GetWidth) == "function" and minimap:GetWidth() or 140
    return width / 2 + EDGE
end

local function IsSquare()
    return type(_G.GetMinimapShape) == "function" and tostring(_G.GetMinimapShape()):find("SQUARE", 1, true) ~= nil
end

function M.Place()
    local button, minimap = M.button, _G.Minimap
    if not (button and minimap) then return end
    local angle = F.db and F.Number(F.db.minimapAngle) and F.db.minimapAngle or DEFAULT_ANGLE
    local x, y = M.Offset(angle, Radius(), IsSquare())
    button:ClearAllPoints()
    button:SetPoint("CENTER", minimap, "CENTER", x, y)
end

-- While dragging: the angle from the minimap's centre to the pointer.
local function Drag(self)
    local minimap = _G.Minimap
    if not (minimap and F.db and type(GetCursorPosition) == "function") then return end
    local mx, my = minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = minimap:GetEffectiveScale()
    if not (F.Number(mx) and F.Number(my) and F.Number(cx) and F.Number(cy) and F.Number(scale) and scale > 0) then return end
    F.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    M.Place()
end

local function Tip(self)
    if type(GameTooltip) ~= "table" then return end
    local S = F.Style
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    S.Title(GameTooltip, "Deffar Profession Profit")
    S.Line(GameTooltip, "Left-click", "Open")
    S.Line(GameTooltip, "Right-click", "Luck and AH sales")
    S.Line(GameTooltip, "Drag", "Move")
    GameTooltip:Show()
end

function M.Create()
    if M.button then return M.button end
    local minimap = _G.Minimap
    if type(minimap) ~= "table" or not F.Has(minimap, "GetCenter") then M.noMinimap = true; return nil end
    local button = CreateFrame("Button", "DeffarProfessionProfitMinimapButton", minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("anyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\AddOns\\" .. addonName .. "\\icon.tga")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then F.LuckUI.Toggle() else F.UI.Toggle() end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", Drag); if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", Tip)
    button:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    M.button = button
    M.Place()
    M.Refresh()
    return button
end

-- Shown unless the player hid it with /dpp minimap.
function M.Refresh()
    if M.button then M.button:SetShown(not (F.db and F.db.minimapHidden)) end
end

function M.Toggle(on)
    if not F.db then return nil end
    if on == nil then on = F.db.minimapHidden == true end
    F.db.minimapHidden = not on
    if on and not M.button then M.Create() end
    M.Refresh()
    return on
end
