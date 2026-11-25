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
        if F.Table(frame) and F.Has(frame, "PanAndZoomTo") and F.Has(_G.C_Timer, "After") then
            _G.C_Timer.After(0.1, function()
                if frame:IsShown() and frame:GetMapID() == point.map then frame:PanAndZoomTo(point.x / 100, point.y / 100) end
            end)
        end
    end
    return "set"
end
