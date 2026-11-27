-- Deffar Profession Profit: the nearest vendor of a material. A material a vendor sells (the generated MaterialVendorData.lua) gets a line in its
-- icon's tooltip in the detail panel naming the nearest vendor of this character's side, and a click on the icon pins that vendor on the map
-- (Waypoint.lua). Nothing here runs by itself: it is asked when the pointer is on an icon or the icon is clicked, never per frame.
--
-- Distance: both the player and a vendor are put on the continent's own grid (C_Map.GetWorldPosFromMapPos) and compared there, in yards, as the
-- installed Profession Planner does for its vendor list (its method, written here; none of its code or data is used). Two spots on different
-- continents, or a player the client gives no position for (an instance), have no distance: the vendor in the player's zone comes first, then the
-- cheapest. Whether Forever answers these calls is checked in game (plans/api-facts.md FOR-0203 is the pin's hypothesis); each is capability-checked.
local addonName, F = ...
local M = {}
F.MatVendors = M

local worldCache = {}   -- npc id -> { continent, x, y } on the continent grid, or false when the client cannot say (a vendor never moves)

-- x, y are 0-1 on the map `map`. Returns continent, x, y in yards, or nil.
local function WorldPos(map, x, y)
    if not (F.Has(_G.C_Map, "GetWorldPosFromMapPos") and type(_G.CreateVector2D) == "function") then return nil end
    local continent, pos = _G.C_Map.GetWorldPosFromMapPos(map, _G.CreateVector2D(x, y))
    if continent == nil or not (F.Table(pos) and F.Number(pos.x) and F.Number(pos.y)) then return nil end
    return continent, pos.x, pos.y
end

local function VendorWorld(id, npc)
    local cached = worldCache[id]
    if cached ~= nil then return cached or nil end
    local continent, x, y = WorldPos(npc.map, npc.x / 100, npc.y / 100)
    worldCache[id] = continent and { continent, x, y } or false
    return worldCache[id] or nil
end

-- The player's map and, when the client gives it, the position on the continent grid.
function M.Player()
    local map = F.Has(_G.C_Map, "GetBestMapForUnit") and _G.C_Map.GetBestMapForUnit("player") or nil
    local world
    if map and F.Has(_G.C_Map, "GetPlayerMapPosition") then
        local pos = _G.C_Map.GetPlayerMapPosition(map, "player")
        if F.Table(pos) and F.Has(pos, "GetXY") then
            local px, py = pos:GetXY()
            if F.Number(px) and F.Number(py) then
                local continent, x, y = WorldPos(map, px, py)
                if continent then world = { continent, x, y } end
            end
        end
    end
    return map, world
end

-- The vendors that sell `itemID` to this character's side, nearest first: { id, npc, cost, limited, distance (yards, nil when unknown),
-- sameZone }. The ones with a distance come first, then the one in the player's zone, then the cheapest. Empty for a material no vendor sells.
function M.For(itemID)
    local data = F.MATERIAL_VENDORS
    local sold = F.Table(data) and F.Table(data.items) and data.items[itemID]
    if not F.Table(sold) then return {} end
    local faction = type(_G.UnitFactionGroup) == "function" and _G.UnitFactionGroup("player") or nil
    local side = faction == "Alliance" and "A" or (faction == "Horde" and "H" or nil)
    local map, mine = M.Player()
    local out = {}
    for _, row in ipairs(sold) do
        local npc = data.npcs[row[1]]
        if npc and (not npc.side or not side or npc.side == side) then
            local entry = { id = row[1], npc = npc, cost = row[2], limited = row[3] == true, sameZone = map ~= nil and npc.map == map }
            local world = mine and VendorWorld(row[1], npc)
            if world and world[1] == mine[1] then
                entry.distance = math.sqrt((world[2] - mine[2]) ^ 2 + (world[3] - mine[3]) ^ 2)
            end
            out[#out + 1] = entry
        end
    end
    table.sort(out, function(a, b)
        if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
        if a.distance and b.distance and a.distance ~= b.distance then return a.distance < b.distance end
        if a.sameZone ~= b.sameZone then return a.sameZone end
        if a.cost ~= b.cost then return a.cost < b.cost end
        return a.id < b.id
    end)
    return out
end

-- "Wulan, Stormwind City" and how far: "420 yd" in the same zone or on the same continent, otherwise nothing.
function M.Describe(entry)
    local text = entry.npc.name .. ", " .. entry.npc.zone
    if entry.distance then text = text .. string.format(" (%d yd)", math.floor(entry.distance + 0.5)) end
    return text
end

-- Adds the nearest vendor to a tooltip: one line, then the click hint under a blank line (the same shape as the other hints). Does nothing for a
-- material no vendor sells to this side.
function M.AddTip(tip, itemID)
    local list = M.For(itemID)
    if #list == 0 then return false end
    tip:AddLine(" ")
    tip:AddLine("Vendor: " .. M.Describe(list[1]) .. (#list > 1 and string.format(" +%d more", #list - 1) or ""), 1, 0.82, 0.4)
    tip:AddLine("Ctrl-click: Pin the nearest vendor", 0.5, 0.8, 1)
    return true
end

-- A Ctrl-click on a material's icon or name: pins the nearest vendor on the map, a second Ctrl-click takes the pin away. The only thing it says in the chat.
function M.Click(itemID)
    local list = M.For(itemID)
    local entry = list[1]
    if not entry then return false end
    local S = F.Style
    local npc = entry.npc
    local place = (F.Waypoint.MapName(npc.map) or npc.zone) .. string.format(" (%.1f, %.1f)", npc.x, npc.y)
    local result, why = F.Waypoint.Toggle(npc)
    if result == "set" then F.Print("Map pin: " .. S.Paint(S.SAND, npc.name) .. ", " .. place .. ", sells " .. F.ItemLink(itemID) .. ". Ctrl-click again to remove it.")
    elseif result == "cleared" then F.Print("Map pin removed.")
    elseif why == "map" then F.Print("This map takes no pin: " .. S.Paint(S.SAND, npc.name) .. ", " .. place .. ".")
    else F.Print("This client has no map pin call: " .. S.Paint(S.SAND, npc.name) .. ", " .. place .. ".") end
    return true
end
