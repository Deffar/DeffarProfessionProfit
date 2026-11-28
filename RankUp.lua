-- Deffar Profession Profit: the golden "?" beside the window's X button. It tells how the character gets the NEXT profession rank (Apprentice to
-- Journeyman, Journeyman to Expert, Expert to Artisan) for the tab in use: the skill against what the rank needs, where to go (a trainer, a vendor
-- that sells a skill book, or a quest giver), and the book's price in the auction house. A click pins the nearest such place on the world map, with
-- the same ring as every other pin here (Waypoint.lua). The steps are the generated RankUpData.lua (tools/dpp_catalog/gen_rankups.py); a profession
-- with no steps there gets no button, so a new tab only needs its data.
-- Nothing here runs by itself: the button is updated by U.Refresh and the tooltip is built when the pointer is on it.
--
-- The rank a character has is its skill line's maxRank (C_SkillInfo.GetSkillLineInfoByID, FOR-0151 declares the call; that it fills `maxRank` is a
-- HYPOTHESIS until seen, plans/api-facts.md FOR-0215). Without it the next step is the first one whose rank spell the character does not know.
local addonName, F = ...
local R = {}
F.RankUp = R

local worldCache = {}   -- npc id -> { continent, x, y } on the continent grid, or false (a trainer never moves)

local function Side()
    local faction = type(_G.UnitFactionGroup) == "function" and _G.UnitFactionGroup("player") or nil
    return faction == "Alliance" and "A" or (faction == "Horde" and "H" or nil)
end

-- The skill of a profession: rank and the highest rank it can reach now (maxRank). nil when the character has no such skill or the client says
-- nothing; the second value is nil when only the rank can be read.
function R.Skill(key)
    local def = F.PROFESSIONS[key]
    local api = _G.C_SkillInfo
    if not def or not F.Has(api, "GetSkillLineInfoByID") then return nil end
    local ok, info = pcall(api.GetSkillLineInfoByID, def.line)
    if not ok or not F.Table(info) or not F.Integer(info.rank, 1, 100000) then return nil end
    return info.rank, F.Integer(info.maxRank, 1, 100000) and info.maxRank or nil
end

local function Known(spell)
    local book = _G.C_SpellBook
    if F.Has(book, "IsSpellKnown") then return book.IsSpellKnown(spell) == true end
    return type(_G.IsSpellKnown) == "function" and _G.IsSpellKnown(spell) == true
end

-- The step the character is on: the one that raises the rank cap it has now. nil when the profession has no steps, or the cap is the top one.
function R.Step(key, max)
    local steps = F.Table(F.RANKUP) and F.RANKUP[key]
    if not F.Table(steps) then return nil end
    if max then
        for _, step in ipairs(steps) do
            if step.cap == max then return step end
        end
        return nil
    end
    for _, step in ipairs(steps) do
        if not Known(step.spell) then return step end
    end
    return nil
end

-- The places a step is done at that this character's side can use, nearest first: { id, npc, distance (yards, nil when unknown), sameZone }.
-- The ones with a distance come first (same continent), then the one in the player's zone, then by name (so the answer is steady).
function R.Places(step)
    local data = F.RANKUP
    local ids = step.how == "trainer" and step.trainers or (step.how == "book" and step.vendors or (step.quest and (step.quest.givers or { step.quest.giver }) or {}))
    local side = Side()
    local map, mine = F.MatVendors.Player()
    local out = {}
    for _, id in ipairs(ids) do
        local npc = data.npcs[id]
        if npc and (not npc.side or not side or npc.side == side) then
            local entry = { id = id, npc = npc, sameZone = map ~= nil and npc.map ~= nil and npc.map == map }
            local world = npc.map and worldCache[id]   -- (an NPC inside an instance has no spot on a map: named, never pinned)
            if npc.map and world == nil then
                local continent, x, y = F.MatVendors.WorldPos(npc.map, npc.x / 100, npc.y / 100)
                world = continent and { continent, x, y } or false
                worldCache[id] = world
            end
            if mine and world and world[1] == mine[1] then
                entry.distance = math.sqrt((world[2] - mine[2]) ^ 2 + (world[3] - mine[3]) ^ 2)
            end
            out[#out + 1] = entry
        end
    end
    table.sort(out, function(a, b)
        if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
        if a.distance and b.distance and a.distance ~= b.distance then return a.distance < b.distance end
        if a.sameZone ~= b.sameZone then return a.sameZone end
        if a.npc.name ~= b.npc.name then return a.npc.name < b.npc.name end
        return a.id < b.id
    end)
    return out
end

-- The nearest trainer of this character's side that can teach a recipe learned at `skill` in a profession: the trainers of the rank-up step that
-- raises the cap above that skill (Journeyman's up to 150, Expert's up to 225, Artisan's above), else those of the last step that is done at a
-- trainer (Cooking's later steps are a book and a quest, its trainers are the first step's). A trainer teaches a recipe, not only a rank: this is
-- the data's best guess of where, not a list of who teaches which recipe. Returns the place ({ id, npc, distance, sameZone }) or nil.
function R.TrainerPlace(prof, skill)
    local steps = F.Table(F.RANKUP) and F.RANKUP[prof]
    if not F.Table(steps) then return nil end
    local want = (F.Integer(skill, 1, 9999) and skill > 225) and 3 or ((F.Integer(skill, 1, 9999) and skill > 150) and 2 or 1)
    local use
    for index, step in ipairs(steps) do
        if step.how == "trainer" and index <= want then use = step end
    end
    use = use or steps[1]
    if not (use and use.how == "trainer") then return nil end
    return R.Places(use)[1]
end

-- Everything the tooltip and the click need for a profession, or nil when there is nothing to say (no skill, no data, the top rank is reached):
-- { key, rank, max (the cap now), need (the skill the step wants), ok (rank >= need), step, places }.
function R.Info(key)
    local rank, max = R.Skill(key)
    if not rank then return nil end
    local step = R.Step(key, max)
    if not step then return nil end
    return { key = key, rank = rank, max = step.cap, need = step.need, ok = rank >= step.need, step = step, places = R.Places(step) }
end

-- "Ironforge (420 yd)": the zone and how far, when the client says.
local function Where(entry)
    local text = entry.npc.zone
    if entry.distance then text = text .. string.format(" (%d yd)", math.floor(entry.distance + 0.5)) end
    return text
end

-- The tooltip: the skill (green once it reaches what the step needs, red below it), who and where, the book's price. `tip` is the collecting tip of
-- UI.lua (NewTip) or the game's tooltip.
function R.AddTip(tip, key)
    local S = F.Style
    local info = R.Info(key)
    if not info then return false end
    local step = info.step
    -- "63/75 (50)": the skill, the cap, and in brackets the skill the step needs. All green once the skill reaches it; below it the skill and the
    -- bracket are red (the cap stays white).
    local need = "(" .. info.need .. ")"
    local skill
    if info.ok then
        skill = S.Paint(S.GREEN, info.rank .. "/" .. info.max .. " " .. need)
    else
        skill = S.Paint(S.RED, tostring(info.rank)) .. "/" .. info.max .. " " .. S.Paint(S.RED, need)
    end
    S.Line(tip, "Skill", skill)
    if F.Integer(step.level, 1, 100) then   -- the player level the rank wants: green once the character has it
        local level = type(_G.UnitLevel) == "function" and _G.UnitLevel("player") or nil
        S.Line(tip, "Level", S.Paint((F.Number(level) and level >= step.level) and S.GREEN or S.RED, tostring(step.level)))
    end
    local first = info.places[1]
    if step.how == "trainer" then
        S.Line(tip, "Trainer", first and first.npc.name or "none for your side")
    elseif step.how == "book" then
        S.Line(tip, "Book", S.ItemLabel(step.item))
        S.Line(tip, "Vendor", first and first.npc.name or "none for your side")
    elseif step.how == "quest" then
        S.Line(tip, "Quest", step.quest.name)
        S.Line(tip, "Quest giver", first and first.npc.name or "none for your side")
    end
    if first then S.Line(tip, "Location", Where(first)) end
    if step.how == "book" then
        local price = F.Has(F.Prices, "Price") and F.Prices.Price(step.item) or nil
        if price then S.Line(tip, "AH:", S.ItemLabel(step.item) .. " " .. F.Money(price)) end
    end
    if first and first.npc.map then
        tip:AddLine(" ")
        S.Hint(tip, "Click to see location")
    end
    return true
end

-- A click: pins the nearest place on the map (a second click takes the pin away), with the ring. What it says in the chat is the same shape as
-- the vendor pin's.
function R.Click(key)
    local info = R.Info(key)
    local first = info and info.places[1]
    if not first then return false end
    local S = F.Style
    local npc = first.npc
    if not npc.map then
        F.Print(S.Paint(S.SAND, npc.name) .. ", " .. npc.zone .. ": there is no map spot to pin for it.")
        return true
    end
    local place = (F.Waypoint.MapName(npc.map) or npc.zone) .. string.format(" (%.1f, %.1f)", npc.x, npc.y)
    local role = info.step.how == "trainer" and "trains " or (info.step.how == "book" and "sells the book for " or "gives the quest for ")
    local result, why = F.Waypoint.Toggle(npc)
    if result == "set" then
        F.Print("Map pin: " .. S.Paint(S.SAND, npc.name) .. ", " .. place .. ", " .. role .. info.step.rank .. ". Click again to remove it.")
    elseif result == "cleared" then
        F.Print("Map pin removed.")
    elseif why == "map" then
        F.Print("This map takes no pin: " .. S.Paint(S.SAND, npc.name) .. ", " .. place .. ".")
    else
        F.Print("This client has no map pin call: " .. S.Paint(S.SAND, npc.name) .. ", " .. place .. ".")
    end
    return true
end

-- The golden "?" at the top right, left of the X button (22 wide at 8 from the edge): a square box with a gold "?". `make` is UI.lua's MakeButton,
-- `showTip(self, lines)` UI.lua's tooltip shower; the button shows for a tab that has a next rank to tell about (R.Update).
function R.Attach(frame, make, newTip, showLines)
    local button = make(frame, "?", 18, 18)
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -6)
    button.label:SetTextColor(1, 0.82, 0)
    button:SetScript("OnClick", function() R.Click(F.Tab()) end)
    button:HookScript("OnEnter", function(self)
        local tip = newTip()
        if R.AddTip(tip, F.Tab()) then showLines(self, tip) end
    end)
    button:HookScript("OnLeave", function() if type(_G.GameTooltip) == "table" then _G.GameTooltip:Hide() end end)
    frame.rankUpButton = button
    return button
end

-- Shows or hides the button for the tab in use: shown only when that profession has a next rank to tell about.
function R.Update(frame)
    local button = frame and frame.rankUpButton
    if not button then return end
    button:SetShown(R.Info(F.Tab()) ~= nil)
end
