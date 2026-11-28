-- Deffar Profession Profit: the map pin. A click on a recipe the character has not learned (Catalog.lua) that a vendor sells pins the
-- vendor on the world map: the game's own user waypoint (the pin a right-click on the map puts down), super-tracked so the arrow points to it,
-- and the world map opened on it. A second click on the same recipe takes the pin away. The calls are the ones the installed Dungeon Master
-- addon (2.0.3, Forever interface 16001) uses for its quest-giver pins; whether Forever answers them is a HYPOTHESIS here until seen
-- (plans/api-facts.md FOR-0203), so each is capability-checked and a missing one says so instead of doing nothing.
local addonName, F = ...
local W = {}
F.Waypoint = W

-- The name of a map ("Stormwind City"), nil when the client does not say.
function W.MapName(map)
    if not F.Has(_G.C_Map, "GetMapInfo") then return nil end
    local info = _G.C_Map.GetMapInfo(map)
    return F.Table(info) and F.String(info.name) and info.name or nil
end

-- Whether the user waypoint is this point already. point = { map = uiMapID, x = 0-100, y = 0-100 }.
function W.Pinned(point)
    if not F.Has(_G.C_Map, "GetUserWaypoint") then return false end
    local wp = _G.C_Map.GetUserWaypoint()
    return F.Table(wp) and wp.uiMapID == point.map and F.Table(wp.position)
        and math.abs(wp.position.x - point.x / 100) < 0.0005 and math.abs(wp.position.y - point.y / 100) < 0.0005
end

-- A gold ring closes in on the pin a few times, so the player sees where it is on a big map. One frame is made once, on the world map's canvas
-- (so it moves and zooms with the map), and reused. Returns true when it started; false when the client lacks what it needs (no ring then, the pin
-- itself is unaffected).
function W.Pulse(point)
    local map = _G.WorldMapFrame
    if not (F.Table(map) and F.Has(map, "GetCanvas") and type(_G.CreateFrame) == "function") then return false end
    local canvas = map:GetCanvas()
    if not (F.Table(canvas) and F.Has(canvas, "GetWidth")) then return false end
    local style = F.Style.PULSE
    local ring = W.ring
    if not ring then
        ring = _G.CreateFrame("Frame", nil, canvas)
        if not (F.Has(ring, "CreateAnimationGroup") and F.Has(ring, "CreateTexture")) then return false end
        ring:SetFrameStrata("HIGH")
        -- the triangles are drawn first, on a lower layer, so the ring is over them; they keep their own brown (normal blending)
        local triangles = ring:CreateTexture(nil, "ARTWORK")
        triangles:SetAllPoints()
        triangles:SetTexture(style.TRIANGLES)
        local texture = ring:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetTexture(style.TEXTURE)
        texture:SetBlendMode("ADD")
        local group = ring:CreateAnimationGroup()
        group:SetLooping("REPEAT")
        local grow = group:CreateAnimation("Scale")
        grow:SetScaleFrom(style.FROM, style.FROM)
        grow:SetScaleTo(style.TO, style.TO)
        grow:SetDuration(style.CLOSE)
        grow:SetOrder(1)
        local show = group:CreateAnimation("Alpha")
        show:SetFromAlpha(0)
        show:SetToAlpha(1)
        show:SetDuration(style.FADE_IN)
        show:SetOrder(1)
        local fade = group:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(style.FADE_OUT)
        fade:SetOrder(2)
        -- the triangles turn clockwise a quarter of a circle in each pulse: split over the two orders so it is steady through the pulse (the
        -- picture looks the same after a quarter turn, so the restart of the next pulse is not seen). A Rotation turns a texture, so the
        -- animation is pointed at it; a client without SetTarget keeps the ring and the triangles stand still.
        local turnFirst = group:CreateAnimation("Rotation")
        local turnLast = group:CreateAnimation("Rotation")
        if F.Has(turnFirst, "SetTarget") and F.Has(turnLast, "SetTarget") then
            local share = style.CLOSE / (style.CLOSE + style.FADE_OUT)
            turnFirst:SetTarget(triangles)
            turnFirst:SetDegrees(-style.DEGREES * share)
            turnFirst:SetDuration(style.CLOSE)
            turnFirst:SetOrder(1)
            turnLast:SetTarget(triangles)
            turnLast:SetDegrees(-style.DEGREES * (1 - share))
            turnLast:SetDuration(style.FADE_OUT)
            turnLast:SetOrder(2)
        end
        group:SetScript("OnLoop", function()
            ring.loops = ring.loops + 1
            if ring.loops >= style.LOOPS then group:Stop(); ring:Hide() end
        end)
        ring.group = group
        W.ring = ring
    end
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local size = math.max(width, height) * style.SIZE
    ring:SetSize(size, size)
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", canvas, "TOPLEFT", width * point.x / 100, -height * point.y / 100)
    ring.loops = 0
    ring:Show()
    ring.group:Stop()
    ring.group:Play()
    return true
end

-- Pins the point, or takes the pin away when it is already there. Returns "set" or "cleared", or nil and why ("api": the client lacks a call,
-- "map": that map takes no pin).
function W.Toggle(point)
    local map = _G.C_Map
    local ui = _G.UiMapPoint
    if not (F.Has(map, "SetUserWaypoint") and F.Has(map, "CanSetUserWaypointOnMap") and F.Table(ui) and F.Has(ui, "CreateFromCoordinates")) then
        return nil, "api"
    end
    if W.Pinned(point) and F.Has(map, "ClearUserWaypoint") then
        map.ClearUserWaypoint()
        return "cleared"
    end
    if not map.CanSetUserWaypointOnMap(point.map) then return nil, "map" end
    map.SetUserWaypoint(ui.CreateFromCoordinates(point.map, point.x / 100, point.y / 100))
    if F.Has(_G.C_SuperTrack, "SetSuperTrackedUserWaypoint") then _G.C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    -- the world map opens on it (a keyboard player; a gamepad player's own map opening is left alone)
    local pad = _G.InputUtil and F.Has(_G.InputUtil, "IsGamepadUIEnabled") and _G.InputUtil.IsGamepadUIEnabled()
    if type(_G.OpenWorldMap) == "function" and not pad then
        _G.OpenWorldMap(point.map)
        local frame = _G.WorldMapFrame
        if F.Table(frame) and F.Has(_G.C_Timer, "After") then
            _G.C_Timer.After(0.1, function()
                if frame:IsShown() and frame:GetMapID() == point.map then
                    if F.Has(frame, "PanAndZoomTo") then frame:PanAndZoomTo(point.x / 100, point.y / 100) end
                    W.Pulse(point)
                end
            end)
        end
    end
    return "set"
end
