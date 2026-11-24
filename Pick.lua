-- Forever Profession Profit: clicking a recipe row opens the Cooking window and selects that recipe
--. Modelled on ProfPlanner's Pick.lua, which found on Forever (its notes,
-- Nov 10) that C_TradeSkillUI.OpenRecipe alone is only applied at the window's next list refresh, so a
-- refresh is forced with the window's own search text (nothing changes for the player), and that
-- selecting through Blizzard's recipe-list code taints confirmation popups, so none of that is used
-- here: only the documented C_TradeSkillUI calls, and only from the click that asked for it (a call
-- from a timer is blocked, ProfPlanner 1.2.2-beta20). Never in combat.
--
-- Unverified on Forever until FOR-0178 is answered: whether C_TradeSkillUI.OpenTradeSkill(skillLineID)
-- is allowed for an addon and what Cooking's skill line is. If it is not, the click says to open the
-- Cooking window yourself and still selects the recipe once it is open.
local _, F = ...

-- Wowhead Forever lists Cooking as skill 185 (/forever/skill=185/cooking, FOR-0177). The Cooking window
-- reports its own skill line as it lists food (Data.lua F.CacheRecipes) and that value replaces this one.
F.COOKING_LINE = 185

function F.CookingLine()
    local saved = F.db and F.db.cookingLine
    if F.Integer(saved, 1, 2147483647) then return saved end
    return F.COOKING_LINE
end

-- The skill line a profession's window is opened with: what the game reported for that window (saved by
-- Data.lua F.CacheRecipes), else the assumed default (Engineering's 202 is a HYPOTHESIS until reported, FOR-0189).
function F.ProfessionLine(prof)
    if prof == "cooking" or not F.PROFESSIONS[prof] then return F.CookingLine() end
    local saved = F.db and F.db[prof .. "Line"]
    if F.Integer(saved, 1, 2147483647) then return saved end
    return F.PROFESSIONS[prof].line
end

local function ProfessionWindow()
    for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame" }) do
        local frame = _G[name]
        if type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() then return frame end
    end
    return nil
end

-- Another player's profession window (a linked profession) cannot be driven (ProfPlanner Recorder.lua:156).
local function IsOthersWindow(api)
    for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
        if F.Has(api, name) and api[name]() == true then return true end
    end
    return false
end

-- Whether the open window is another player's (Craft.lua).
function F.OthersWindow() return IsOthersWindow(_G.C_TradeSkillUI) end

local function SearchText()
    local window = _G.ProfessionsFrame
    local page = type(window) == "table" and window.CraftingPage or nil
    local list = type(page) == "table" and page.RecipeList or nil
    local box = (type(list) == "table" and list.SearchBox) or _G.TradeSkillFrameSearchBox
    if type(box) == "table" and type(box.GetText) == "function" then
        local text = box:GetText()
        if F.String(text) then return text end
    end
    return ""
end

-- The recipe the window has selected, or nil when this window cannot tell.
local function SelectedID()
    local window = _G.ProfessionsFrame
    local page = type(window) == "table" and window.CraftingPage or nil
    local form = type(page) == "table" and page.SchematicForm or nil
    if type(form) == "table" and type(form.GetRecipeInfo) == "function" then
        local info = form:GetRecipeInfo()
        if F.Table(info) and F.Integer(info.recipeID, 1, 2147483647) then return info.recipeID end
    end
    return nil
end

-- The recipe selected in the open profession window, or nil when no profession window is showing or it cannot
-- tell (the vendor "+" button uses it to buy for just that recipe; ProfPlanner reads the same
-- ProfessionsFrame.CraftingPage.SchematicForm:GetRecipeInfo() on this client, Pick.lua:67-71, Sellers.lua:121-124).
function F.SelectedRecipeID()
    if not ProfessionWindow() then return nil end
    return SelectedID()
end

-- Opens the profession's window (Cooking unless `prof` says otherwise) if it is not showing and selects recipe
-- `id` in it. Returns true, or false and a sentence saying why not.
function F.OpenRecipe(id, name, prof)
    prof = F.PROFESSIONS[prof] and prof or "cooking"
    local label = F.PROFESSIONS[prof].name
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, "recipes cannot be opened in combat."
    end
    local api = _G.C_TradeSkillUI
    if not F.Has(api, "OpenRecipe") then
        return false, "this client has no function to select a recipe."
    end
    local line = F.ProfessionLine(prof)
    local window = ProfessionWindow()
    if window and IsOthersWindow(api) then
        return false, "that is another player's profession window: open your own " .. label .. " window."
    end

    -- Which profession the open window shows, when it says (a different one must be switched to Cooking).
    local current
    if window and F.Has(api, "GetBaseProfessionInfo") then
        local profession = api.GetBaseProfessionInfo()
        if F.Table(profession) and F.Integer(profession.professionID, 1, 2147483647) then current = profession.professionID end
    end
    if not window or (current and current ~= line) then
        if not F.Has(api, "OpenTradeSkill") then
            return false, "open your " .. label .. " window first, then click the recipe again."
        end
        local opened = api.OpenTradeSkill(line)
        if opened == false then
            return false, "the game would not open the " .. label .. " window (skill line " .. line
                .. "). Open it yourself, then click the recipe again."
        end
    end

    api.OpenRecipe(id)
    -- OpenRecipe is only applied at the next list refresh (ProfPlanner Pick.lua): ask for one with the
    -- text already in the window's search box.
    if F.Has(api, "SetRecipeItemNameFilter") then api.SetRecipeItemNameFilter(SearchText()) end

    if type(C_Timer) == "table" and C_Timer.After then
        C_Timer.After(0.5, function()
            local selected = SelectedID()
            if selected ~= nil and selected ~= id then
                F.Print("couldn't switch the " .. label .. " window to " .. tostring(name or id)
                    .. ". Click it in the window's list (clear the window's search or filters if it isn't there).")
            end
        end)
    end
    return true
end
