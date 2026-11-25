-- Deffar Profession Profit: lifecycle. Settings, events and slash commands.
--
-- What it does: /dpp opens a window listing the current character's learned cooking recipes with
-- the material cost (Auctionator price or a saved vendor price, whichever is lower), the vendor sell
-- price of the food, and the average profit at the character's Master Chef rank. Recipes are saved
-- whenever a profession window lists them, vendor buy prices whenever a merchant window is open.
--
-- SavedVariables: DeffarProfessionProfitDB, account-wide, schema version 1:
--   version, crafts (1-100000, the crafts used for the tooltip's range), sort / sortDesc, ownedFree,
--   profitOnly, showAH (booleans), rankOverride (0-5 or absent = read from the game), left/top
--   (window position, optional), cookingLine (the Cooking skill line the Cooking window reported, optional),
--   vendorBuy[itemID] = { c = copper per unit, t = time seen, l = limited stock? },
--   chars["Full Name"] = { recipes = { [recipeID] = { name, out, qMin, qMax, r = { { qty, ids } } } },
--                          rank = { value, seen }, cast = { [recipeID] = seconds one cast took } }.
--   odds (50-99, default 90: the chance of finishing ahead the [A] button's price limits aim for), margin (0-100,
--   default 10: the least profit on cost, in percent, those limits leave), budget
--   (gold, 1-100000000, or absent = all the character's gold: the most an [A] list may cost; Shopping.lua),
--   bought[itemID] = { n = units, c = copper paid, p = last unit price, t = time } (auction purchases, Bought.lua),
--   luck[recipeID] = { name, out, y, ranks = { [rank] = { c, x, o } } } (also under chars[name].luck), luckScope
--   ("session" | "char" | "life"), luckLeft/luckTop (window position): see Luck.lua.
-- (cookingLine, cast and the luck fields were added after the first release; all optional, so no version change.)
-- A file saved by a newer version is used read-only in memory (never overwritten). Per-character data
-- is keyed by the full character name only, no realm.
local addonName, F = ...

local DEFAULTS = { version = 1, crafts = 100, sort = "profit", sortDesc = true,
    ownedFree = false, profitOnly = false, showAH = false, odds = 90, margin = 10 }
local LUCK_SORT_KEYS = { item = true, c = true, x = true, exp = true, real = true, luck = true, spent = true,
    gained = true, profit = true, hour = true }   -- the /dpp luck column headings (LuckUI.lua)
local SORT_KEYS = { name = true, mats = true, vendor = true, ah = true, profit = true, margin = true, odds = true, rank = true }

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------

local function Initialize()
    if F.loaded then return end
    local saved = _G.DeffarProfessionProfitDB
    if type(saved) == "table" and type(saved.version) == "number" and saved.version > DEFAULTS.version then
        -- Saved by a newer version of this addon: defaults in memory, never overwrite it.
        F.readOnly = true
        F.db = { version = DEFAULTS.version, crafts = DEFAULTS.crafts, sort = DEFAULTS.sort, sortDesc = true,
            ownedFree = false, profitOnly = false, marginOnly = true, minProfitCopper = 100, minOdds = 30, maxAge = 1, showAH = false, sellAH = false, odds = DEFAULTS.odds, margin = DEFAULTS.margin, autoQuantity = true, bagReserve = 2, autoSearch = true, vendorBuy = {}, chars = {}, luck = {}, bought = {}, items = {} }
    else
        if type(saved) ~= "table" then saved = {} end
        _G.DeffarProfessionProfitDB = saved
        saved.version = DEFAULTS.version
        if not F.Integer(saved.crafts, 1, 100000) then saved.crafts = DEFAULTS.crafts end
        if type(saved.sort) ~= "string" or not SORT_KEYS[saved.sort] then saved.sort = DEFAULTS.sort end
        if type(saved.sortDesc) ~= "boolean" then saved.sortDesc = DEFAULTS.sortDesc end
        if type(saved.ownedFree) ~= "boolean" then saved.ownedFree = DEFAULTS.ownedFree end
        if type(saved.profitOnly) ~= "boolean" then saved.profitOnly = DEFAULTS.profitOnly end
        if type(saved.showAH) ~= "boolean" then saved.showAH = DEFAULTS.showAH end
        if not F.Integer(saved.maxAge, 0, 99) then saved.maxAge = 1 end   -- days: the oldest price the Enchanting list trusts
        if type(saved.craftTime) ~= "boolean" then saved.craftTime = true end   -- print the time of a Create All
        if type(saved.noDisenchant) ~= "table" then saved.noDisenchant = {} end   -- items the player says cannot be disenchanted
        if type(saved.gone) ~= "table" then saved.gone = {} end            -- items searched for and not found (Disenchant.lua)
        if not F.Integer(saved.minOdds, 0, 100) then saved.minOdds = 30 end   -- percent: the least chance one disenchant must pay
        -- the least profit an Enchanting item must show, in COPPER (silver and copper boxes); it was a whole number of silver (`minProfit`)
        if not (F.Number(saved.minProfitCopper) and saved.minProfitCopper >= 0) then
            saved.minProfitCopper = (F.Integer(saved.minProfit, 0, 1000000) and saved.minProfit or 1) * 100
        end
        if type(saved.marginOnly) ~= "boolean" then saved.marginOnly = true end   -- the Enchanting tab lists only items that return the Margin
        if type(saved.sellAH) ~= "boolean" then saved.sellAH = false end   -- profit from selling at the auction house instead of to a vendor
        if type(saved.sellDE) ~= "boolean" then saved.sellDE = false end   -- profit from disenchanting the result (needs Enchanting)
        if saved.sellAH and saved.sellDE then saved.sellDE = false end    -- one basis at a time
        if not F.Integer(saved.rankOverride, 0, F.RANK_MAX) then saved.rankOverride = nil end
        if not F.Integer(saved.odds, 50, 99) then saved.odds = DEFAULTS.odds end
        if not F.Integer(saved.margin, 0, 100) then saved.margin = DEFAULTS.margin end
        if not F.Integer(saved.buyCrafts, 1, 100000) then saved.buyCrafts = nil end   -- absent: as many crafts as the budget allows
        if type(saved.autoQuantity) ~= "boolean" then saved.autoQuantity = true end
        if not F.Integer(saved.bagReserve, 0, 20) then saved.bagReserve = 2 end
        if type(saved.autoSearch) ~= "boolean" then saved.autoSearch = true end
        if not (type(saved.luckSort) == "string" and LUCK_SORT_KEYS[saved.luckSort]) then saved.luckSort = "c" end
        if type(saved.luckSortDesc) ~= "boolean" then saved.luckSortDesc = true end
        if not F.PROFESSIONS[saved.tab] then saved.tab = "cooking" end
        local luckDef = F.TabDef(saved.luckTab)
        if not (luckDef and (luckDef.store or luckDef.disenchant or luckDef.sales)) then saved.luckTab = "cooking" end   -- the /dpp luck window's own tab
        if type(saved.salesCrafted) ~= "boolean" then saved.salesCrafted = true end   -- the AH sales tab lists only items the player crafted
        if type(saved.luckAH) ~= "table" then saved.luckAH = {} end   -- recipes sold at the auction house: left out of the luck money totals
        if type(saved.sales) ~= "table" then saved.sales = {} end   -- what auctions brought in, all characters (Sales.lua)
        if type(saved.salesCreatedSeen) ~= "boolean" then saved.salesCreatedSeen = false end   -- AUCTION_HOUSE_AUCTION_CREATED has been seen (FOR-0197)
        for _, key in ipairs(F.TABS) do   -- the skill line each profession's window reported (cooking's is cookingLine)
            if key ~= "cooking" and not F.Integer(saved[key .. "Line"], 1, 2147483647) then saved[key .. "Line"] = nil end
        end
        if not F.Integer(saved.budget, 1, 100000000) then saved.budget = nil end   -- gold; absent = all the character's gold
        if not (F.Number(saved.left) and F.Number(saved.top)) then saved.left, saved.top = nil, nil end
        if not F.Number(saved.minimapAngle) then saved.minimapAngle = nil end   -- the minimap button's place, in degrees (Minimap.lua)
        if type(saved.minimapHidden) ~= "boolean" then saved.minimapHidden = false end
        if type(saved.vendorBuy) ~= "table" then saved.vendorBuy = {} end
        if type(saved.chars) ~= "table" then saved.chars = {} end
        if type(saved.luck) ~= "table" then saved.luck = {} end
        if type(saved.bought) ~= "table" then saved.bought = {} end
        if type(saved.lots) ~= "table" then saved.lots = {} end   -- purchases as lots, used oldest first (Bought.lua)
        if type(saved.items) ~= "table" then saved.items = {} end   -- icon/quality/name of items seen (F.ItemMeta)
        if saved.luckScope ~= "char" and saved.luckScope ~= "life" then saved.luckScope = "session" end
        if not (F.Number(saved.luckLeft) and F.Number(saved.luckTop)) then saved.luckLeft, saved.luckTop = nil, nil end
        F.db = saved
    end
    F.loaded = true
    F.Bought.Snapshot()   -- the purse now is the starting point for the auction-house cost tracking
    F.HookCrafts()        -- Create All prints how long the batch takes (Data.lua)
    F.Sales.Hook()        -- postings and the mail of sold auctions feed the AH sales tab (Sales.lua)
    F.Minimap.Create()    -- the button on the minimap (Minimap.lua)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local waiting = {}

-- Runs fn once after `delay` seconds however many times it is asked for in between.
local function Later(key, delay, fn)
    if waiting[key] then return end
    waiting[key] = true
    C_Timer.After(delay, function()
        waiting[key] = nil
        fn()
    end)
end

local function RefreshWindow()
    if F.UI.IsShown() then F.UI.Refresh() end
    if F.LuckUI.IsShown() then F.LuckUI.Refresh() end   -- its icons arrive with the item data too
end

-- The Enchanting list is rebuilt at most every 2 s while its items load (Disenchant.lua), so a last burst of item data
-- needs one more redraw after the pause; it repeats until the list is up to date, and only while the window is open.
local function LateItems()
    Later("itemsLate", 2.2, function()
        if F.Disenchant.Pending() and F.UI.IsShown() then
            RefreshWindow()
            if F.Disenchant.Pending() then LateItems() end
        end
    end)
end

-- Auctionator saves every price it learns (a scan, a search, the Selling tab) through its price database's SetPrice
--. Watching
-- that call lets the window redraw by itself a moment after new prices arrive instead of waiting to be reopened.
-- The redraw is debounced: a full scan writes thousands of prices in a burst.
-- One redraw for a burst of price writes. The Enchanting tab is redrawn less often (3 s: its numbers are rewritten for every
-- row), and once the writes have stopped after a scan (300 or more of them) its list is rebuilt, so the new bargains appear and
-- the sold ones go; during a search or a scan the rows themselves stay where they are (Disenchant.lua).
local lastBurst = 0
local function PriceTick()
    local d = F.Disenchant
    local growing = d.burst ~= lastBurst
    lastBurst = d.burst
    if not growing then
        if d.burst >= 300 then d.Invalidate() end
        d.burst, lastBurst = 0, 0
    end
    RefreshWindow()
    if growing and F.UI.IsShown() then Later("prices", F.Tab() == "enchanting" and 3 or 0.5, PriceTick) end   -- look again once it is quiet
end

function F.OnAuctionPrice(key)
    F.Disenchant.PricesChanged(key)
    if F.UI.IsShown() then Later("prices", F.Tab() == "enchanting" and 3 or 0.5, PriceTick) end
end

-- Hooks Auctionator.Database:SetPrice once the database exists (it is created after this addon loads, so this is
-- tried whenever the window opens and when the auction house opens). Returns true when the hook is in place.
function F.HookAuctionator()
    if F.priceHooked then return true end
    local auctionator = _G.Auctionator
    local database = type(auctionator) == "table" and auctionator.Database or nil
    if type(database) ~= "table" or type(database.SetPrice) ~= "function" or type(hooksecurefunc) ~= "function" then return false end
    hooksecurefunc(database, "SetPrice", function(_, key) F.OnAuctionPrice(key) end)   -- (self, dbKey, price, available)
    F.priceHooked = true
    return true
end

local function CacheNow()
    local result, reason = F.CacheRecipes()
    F.lastRecipeScan = result or { failed = reason }
    -- Output items that were not cached yet are asked for; GET_ITEM_INFO_RECEIVED runs this again.
    F.recachePending = result ~= nil and result.pending > 0
    F.Craft.Refresh()   -- the + button on the profession window
    RefreshWindow()
end

local function OnMerchant()
    local saved = F.ScanMerchant()
    F.lastMerchantScan = saved
    F.Vendor.Refresh()
    RefreshWindow()
end

-- Crafting time, for the Profit/hr column: how long the player's own cast of one of the saved recipes took,
-- from UNIT_SPELLCAST_START to UNIT_SPELLCAST_SUCCEEDED. The recipe ID is the spell ID (FOR-0177). Saved
-- per character on the recipe's first cook (Data.lua F.RecordCast) and used instead of the assumed 3 s.
-- A cast that is interrupted or fails is dropped; an instant extra SUCCEEDED does not end the timing.
local casting   -- { id = spellID, guid = castGUID or nil, started = GetTime() }

local function OnCastStart(unit, guid, spellID)
    if unit ~= "player" then return end
    casting = nil
    if not F.Integer(spellID, 1, 2147483647) then return end   -- a secret or odd spell ID: not measured
    local char = F.Char()
    local recipe, prof = F.FindRecipe(spellID)
    if not (char and recipe) then return end
    casting = { id = spellID, guid = F.String(guid) and guid or nil, started = GetTime() }
    -- which saved recipe a "You create:" line belongs to when two make the same item (Luck.lua)
    F.craftNow = { id = spellID, time = GetTime() }
    if prof == "cooking" then F.cookingNow = { id = spellID, time = GetTime() } end
end

-- The luck counter: a "You create:" chat line is one craft (Luck.lua, FOR-0179). Both chat events are
-- listened to because which one carries the line is unverified; Luck.Handle ignores the same text twice.
local function OnCreateLine(event, text)
    local recipe = F.Luck.Handle(event, text)
    local disenchanted = event == "CHAT_MSG_LOOT" and F.Luck.HandleLoot(text)   -- what a disenchant gave (Luck.lua)
    if (recipe or disenchanted) and F.LuckUI.IsShown() then F.LuckUI.Refresh() end
end

-- Disenchanting: the item named as the cast's target, then the cast finishing (Luck.lua).
local function OnCastSent(unit, target, guid, spellID)
    if unit ~= "player" or not F.Integer(spellID, 1, 2147483647) then return end
    F.lastSent = { id = spellID, target = F.String(target) and target or nil }   -- shown by /dpp status, to see what the game sends
    if F.Luck.IsDisenchant(spellID) then F.Luck.DisenchantSent(target) end
end

local function OnCastSucceeded(unit, guid, spellID)
    if unit == "player" and F.Integer(spellID, 1, 2147483647) and F.Luck.IsDisenchant(spellID) then
        if F.Luck.DisenchantDone() and F.LuckUI.IsShown() then F.LuckUI.Refresh() end
        return
    end
    if unit ~= "player" or not casting then return end
    if not F.Integer(spellID, 1, 2147483647) or spellID ~= casting.id then return end
    if casting.guid and F.String(guid) and guid ~= casting.guid then return end
    local seconds = GetTime() - casting.started
    if F.RecordCast(spellID, seconds) then
        casting = nil
        F.lastCast = { id = spellID, seconds = seconds }
        RefreshWindow()
    elseif seconds > 60 then
        casting = nil
    end
end

local function OnCastEnded(unit, guid, spellID)
    if unit ~= "player" or not casting then return end
    if F.Integer(spellID, 1, 2147483647) and spellID == casting.id then casting = nil end
end

-- FOR-0009: recognized-but-rejected registrations must not report success.
for _, event in ipairs({"ADDON_LOADED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED",
    "PLAYER_EQUIPMENT_CHANGED", "MERCHANT_SHOW", "MERCHANT_UPDATE", "GET_ITEM_INFO_RECEIVED", "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED",
    "CHAT_MSG_LOOT", "CHAT_MSG_TRADESKILLS", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_PURCHASE_COMPLETED", "PLAYER_MONEY",
    "AUCTION_HOUSE_SHOW_COMMODITY_WON_NOTIFICATION", "COMMODITY_SEARCH_RESULTS_UPDATED",
    "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED", "AUCTION_HOUSE_CLOSED",
    "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_MULTISELL_FAILURE", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED"}) do
    local ok, registered = pcall(driver.RegisterEvent, driver, event)
    if not ok or registered == false or not driver:IsEventRegistered(event) then F.eventIssues[event] = true end
end
-- Player-only: these fire for every unit in the world, so ask for the player's own.
for _, event in ipairs({"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED"}) do
    local ok, registered = pcall(driver.RegisterUnitEvent, driver, event, "player")
    if not ok then ok, registered = pcall(driver.RegisterEvent, driver, event) end   -- (the handlers check the unit too)
    if not ok or registered == false or not driver:IsEventRegistered(event) then F.eventIssues[event] = true end
end

-- Auction-house cost tracking (Bought.lua, FOR-0180): the purse is read when the window opens and on every
-- change; a commodity purchase notification (item, quantity) charges the gold that just left to the item.
local function OnAuctionPurchase(item, quantity)
    F.Bought.OnPurchase(item, quantity)
    if F.LuckUI.IsShown() then F.LuckUI.Refresh() end
end

driver:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then Initialize() end
        return
    end
    if not F.loaded then return end
    if event == "UNIT_SPELLCAST_SENT" then OnCastSent(arg1, arg2, arg3, arg4); return end
    if event == "UNIT_SPELLCAST_START" then OnCastStart(arg1, arg2, arg3); return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then OnCastSucceeded(arg1, arg2, arg3); return end
    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then OnCastEnded(arg1, arg2, arg3); return end
    if event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_TRADESKILLS" then OnCreateLine(event, arg1); return end
    if event == "PLAYER_MONEY" then F.Bought.OnMoney(); return end
    if event == "PLAYER_EQUIPMENT_CHANGED" then   -- Cookie's Stirring Rod on or off: the craft times change (Data.lua F.RodWorn)
        local before = F.RodCached()
        F.RodChanged()
        if F.RodWorn() ~= before then   -- (an unread state counts as changed)
            RefreshWindow()
            if F.LuckUI.IsShown() then F.LuckUI.Refresh() end
            F.Craft.Refresh()
        end
        return
    end
    if event == "AUCTION_HOUSE_SHOW" then F.Bought.Snapshot(); F.HookAuctionator(); F.Bought.HookBids(); F.Sales.Hook(); F.Disenchant.ListenScans(); return end
    -- the AH sales tab (Sales.lua): a post going through or failing, and the mailbox
    if event == "AUCTION_HOUSE_AUCTION_CREATED" then F.Sales.OnCreated(arg1); return end
    if event == "AUCTION_MULTISELL_FAILURE" then F.Sales.OnFailed(event); return end
    if event == "MAIL_SHOW" then F.Sales.Hook(); F.Sales.OnInboxChanged(); return end
    if event == "MAIL_INBOX_UPDATE" or event == "MAIL_CLOSED" then F.Sales.OnInboxChanged(); return end
    if event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then F.Bought.OnPurchaseCompleted(arg1); return end   -- gear: what was paid (Bought.lua)
    if event == "AUCTION_HOUSE_CLOSED" then F.Disenchant.Invalidate(); return end   -- the Enchanting list is rebuilt next time it is drawn
    if event == F.Bought.EVENT then OnAuctionPurchase(arg1, arg2); return end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then F.OnCommoditySearch(arg1); return end
    -- the vendor "+" button (Vendor.lua): open/closed state at once, the button itself a moment later
    if event == "MERCHANT_SHOW" then F.Vendor.OnMerchantShow()
    elseif event == "MERCHANT_CLOSED" then F.Vendor.OnMerchantClosed(); return
    elseif event == "PLAYER_REGEN_DISABLED" then F.Vendor.Cancel("you entered combat."); return
    elseif event == "BAG_UPDATE_DELAYED" then
        if F.Luck.BagsChanged() and F.LuckUI.IsShown() then F.LuckUI.Refresh() end
        if F.Vendor.open then Later("vendorbag", 0.2, F.Vendor.Refresh) end
        if F.Craft.button and F.Craft.button:IsShown() then Later("craftbag", 0.3, F.Craft.Refresh) end   -- (the + on the profession window follows the bags)
        return
    end
    if event == "TRADE_SKILL_SHOW" then F.HookCrafts() end   -- (again, in case the profession API was not there at load)
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "NEW_RECIPE_LEARNED" then
        Later("recipes", 0.5, CacheNow)
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        Later("merchant", 0.3, OnMerchant)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        F.Disenchant.ItemsArrived()
        if F.recachePending or F.UI.IsShown() or F.LuckUI.IsShown() then
            Later("items", 0.3, function()
                if F.recachePending then CacheNow() else RefreshWindow() end
            end)
            LateItems()
        end
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "TRAIT_NODE_CHANGED" then
        Later("rank", 0.5, RefreshWindow)   -- the rank is read again whenever the window repaints
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function Count(map)
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    return n
end

local REASONS = { api = "the game's API is missing", config = "no legacy config was returned",
    node = "the Master Chef node was not returned", shape = "the node did not look as expected" }

local function Status()
    F.Print("version " .. F.VERSION .. ".")
    F.Print(F.AuctionatorLoaded() and ("Auctionator: loaded" .. (F.priceHooked and ", the window redraws when it learns new prices." or ", price updates are not being watched yet (open the window or the auction house)."))
        or "Auctionator: not loaded (vendor prices you have seen are used).")
    F.Print("Enchanting [A] search: " .. (F.Disenchant.abortGuard and "leaving the auction house page does not remove an item from the list."
        or "not watching for aborted searches yet (press [A] on a row with the auction house open)."))
    local live, reason = F.ReadRank()
    local rank, source = F.CurrentRank()
    F.Print("Master Chef rank in use: " .. rank .. " (" .. source .. "). Live read: "
        .. (live and (live .. "/" .. F.RANK_MAX) or ("failed - " .. (REASONS[reason] or tostring(reason)))) .. ".")
    local char, key = F.Char()
    F.Print("Character: " .. tostring(key) .. ", " .. (char and Count(char.recipes) or 0) .. " cooking and "
        .. (char and Count(char.engineering) or 0) .. " engineering and " .. (char and Count(char.tailoring) or 0) .. " tailoring recipe(s) saved.")
    local cookRank, engRank, tailRank = F.SkillRank(F.PROFESSIONS.cooking.line), F.SkillRank(F.PROFESSIONS.engineering.line), F.SkillRank(F.PROFESSIONS.tailoring.line)
    F.Print("Skill ranks read: Cooking " .. tostring(cookRank) .. ", Engineering " .. tostring(engRank) .. ", Tailoring " .. tostring(tailRank)
        .. " (nil: not readable). Tabs shown: "
        .. table.concat(F.VisibleTabs(), ", ") .. ".")
    local last = F.crafts.last
    F.Print("Create All time: hook " .. (F.crafts.hooked and "installed" or "NOT installed (no C_TradeSkillUI.CraftRecipe)") .. ", "
        .. F.crafts.seen .. " craft request(s) seen" .. (last and (", the last for recipe " .. last.id .. " x" .. last.casts) or "")
        .. (F.db.craftTime == false and ", printing is off" or "") .. ".")
    F.Print(F.Sales.StatusText())
    local de = F.Luck.de
    F.Print(string.format("Disenchants: %d cast(s) started, %d finished (%d with no start seen), %d counted; the item named by the cast %d time(s), found from the bags %d time(s), from the bags alone %d time(s), %d time(s) more than one kind of gear had left; %d loot line(s) seen after one, %d Enchanting material(s) counted (%d from before the cast ended).",
        de.casts, de.done, de.noTarget, de.counted, de.byName, de.byBags, de.fromBags or 0, de.ambiguous or 0, de.lines, de.attributed, de.early))
    F.Print("Last cast sent: " .. (F.lastSent and ("spell " .. F.lastSent.id .. ", target " .. tostring(F.lastSent.target)) or "none yet") .. ".")
    F.Print("Last profession window seen: " .. (F.lastWindow and (tostring(F.lastWindow.name) .. " (skill line " .. tostring(F.lastWindow.id)
        .. (F.lastWindow.parent and (", parent " .. tostring(F.lastWindow.parent)) or "") .. ")") or "none yet")
        .. ". Engineering skill line used to open its window: " .. F.ProfessionLine("engineering")
        .. (F.Integer(F.db.engineeringLine, 1, 2147483647) and " (reported by the game)" or " (the assumed default)") .. ".")
    local scan = F.lastRecipeScan
    if scan and scan.failed then
        F.Print("Last recipe scan failed: " .. (REASONS[scan.failed] or tostring(scan.failed)) .. ".")
    elseif scan then
        F.Print("Last recipe scan (" .. tostring(scan.prof) .. "): " .. scan.seen .. " listed, " .. scan.saved .. " saved, " .. scan.removed
            .. " removed, " .. scan.pending .. " waiting for item data.")
    else
        F.Print("No recipe scan yet: open your Cooking window.")
    end
    F.Print("Cooking skill line used to open the window: " .. F.CookingLine()
        .. (F.Integer(F.db.cookingLine, 1, 2147483647) and " (reported by the game)" or " (the assumed default)")
        .. ". Cast times measured for " .. (char and (Count(char.cast) + Count(char.castRod)) or 0) .. " recipe(s), Cookie's Stirring Rod "
            .. (F.RodWorn() and "worn" or "not worn") .. (char and char.rodRatio and string.format(" (ratio learned: %.2f)", char.rodRatio) or "")
        .. (F.lastCast and (", last " .. string.format("%.2f", F.lastCast.seconds) .. " s") or "") .. ".")
    local skipped = {}
    for reason, n in pairs(F.Luck.skipped) do skipped[#skipped + 1] = reason .. " " .. n end
    table.sort(skipped)
    local byEvent = {}
    for event, n in pairs(F.Luck.perEvent) do byEvent[#byEvent + 1] = event .. " " .. n end
    table.sort(byEvent)
    F.Print("Luck counter: " .. F.Luck.seen .. " \"You create:\" line(s) seen this session"
        .. (#byEvent > 0 and (" (" .. table.concat(byEvent, ", ") .. ")") or "")
        .. ", " .. F.Luck.duplicates .. " duplicate(s) ignored, " .. F.Luck.merged .. " split line(s) merged into their craft"
        .. (#skipped > 0 and (", not counted: " .. table.concat(skipped, ", ")) or "") .. ".")
    local lost = {}
    for reason, n in pairs(F.Bought.skipped) do lost[#lost + 1] = reason .. " " .. n end
    table.sort(lost)
    F.Print("Gear purchases: " .. F.Bought.gearSeen .. " bid(s) seen this session, " .. F.Bought.gearRecorded .. " purchase(s) recorded.")
    F.Print("Auction purchases: " .. F.Bought.seen .. " commodity purchase(s) seen this session, "
        .. Count(F.db.bought) .. " material(s) with a tracked price"
        .. (#lost > 0 and (", not used: " .. table.concat(lost, ", ")) or "") .. ".")
    F.Print("Create All + button: " .. (F.Craft.button and "created on the profession window" or
        (F.Craft.noFrame and "no ProfessionsFrame found on this client" or "created the first time a profession window of yours opens")) .. ".")
    F.Print("Vendor + button: " .. (F.Vendor.button and "created on the merchant window" or
        (F.Vendor.noFrame and "no MerchantFrame found on this client" or "created the first time a vendor opens")) .. ".")
    F.Print(Count(F.db.vendorBuy) .. " vendor buy price(s) saved"
        .. (F.lastMerchantScan and (" (the last merchant visit saved " .. F.lastMerchantScan .. ")") or "") .. ".")
    local missing = {}
    for event in pairs(F.eventIssues) do missing[#missing + 1] = event end
    if #missing > 0 then
        table.sort(missing)
        F.Print("Events the client rejected: " .. table.concat(missing, ", "))
    end
    if F.readOnly then F.Print("Saved settings are from a newer version; changes are not saved.") end
end

local function Help()
    F.Print("shows which of your Cooking, Engineering and Tailoring recipes make a profit. Commands:")
    print("  /dpp - open or close the window")
    print("  /dpp rank auto|0-5 - the Master Chef rank to use (auto reads it from the game)")
    print("  /dpp crafts <number> - how many crafts the hover tooltip's range covers (now " .. F.db.crafts .. "); [A] uses /dpp buy")
    print("  /dpp odds 50-99 - the chance of finishing ahead that [A]'s price limits aim for (now " .. F.db.odds .. "%)")
    print("  /dpp buy <crafts>|max - how many crafts [A] buys for (now " .. (F.db.buyCrafts and (F.db.buyCrafts .. " crafts") or "as many as your budget allows") .. ")")
    print("  /dpp bags 0-20 - the bag slots the vendor + button keeps free (now " .. (F.db.bagReserve or 2) .. ")")
    print("  /dpp autosearch on|off - [A] opens Auctionator's Shopping tab and searches the new list (now " .. (F.db.autoSearch ~= false and "on" or "off") .. ")")
    print("  /dpp autoqty on|off - lower Auctionator's buy quantity to the units under the price limit (now " .. (F.db.autoQuantity ~= false and "on" or "off") .. ")")
    print("  /dpp margin 0-100 - the least profit on cost (percent) that [A]'s price limits leave (now " .. F.db.margin .. "%)")
    print("  /dpp budget <gold>|all - the most [A]'s lists may cost (now " .. (F.db.budget and (F.db.budget .. " gold") or "all your gold") .. ")")
    print("  /dpp cooking | engineering | tailoring | enchanting - open the window on that profession's tab")
    print("  /dpp luck - the luck counter: extra results seen against the Master Chef chance (/dpp luck reset clears this session)")
    print("  /dpp status - what was read and saved")
    print("  /dpp minimap on|off - show or hide the minimap button (drag it to move it)")
    print("  /dpp crafttime on|off - print how long a Create All takes (DPP Craft time: 15m)")
    print("  /dpp sales - the luck window's AH sales tab: what your auctions really brought in, deposits included")
    print("  /dpp de - what the Enchanting tab found in Auctionator's data")
    print("Open your Cooking (and Engineering, Tailoring) window once so the recipes are saved, and visit vendors so their prices are saved.")
end

SLASH_DEFFARPROFESSIONPROFIT1 = "/dpp"
SlashCmdList.DEFFARPROFESSIONPROFIT = function(message)
    if not F.loaded then return end
    local command, argument = (message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "" or command == "toggle" or command == "show" then
        F.UI.Toggle()
    elseif command == "cooking" or command == "engineering" or command == "tailoring" or command == "enchanting" or command == "tab" then
        local key = command == "tab" and argument or command
        if not F.PROFESSIONS[key] then
            F.Print("usage: /dpp cooking, /dpp engineering, /dpp tailoring, /dpp enchanting (or /dpp tab cooking|engineering|tailoring|enchanting).")
            return
        end
        if not F.UI.IsShown() then F.UI.Show() end
        F.UI.SelectTab(key)
    elseif command == "rank" then
        if argument == "auto" then
            F.db.rankOverride = nil
            F.Print("Master Chef rank: auto (read from the game).")
        elseif F.Integer(tonumber(argument), 0, F.RANK_MAX) then
            F.db.rankOverride = tonumber(argument)
            F.Print("Master Chef rank set to " .. F.db.rankOverride .. " by hand.")
        else
            F.Print("usage: /dpp rank auto, or /dpp rank 0-" .. F.RANK_MAX .. ".")
            return
        end
        RefreshWindow()
    elseif command == "crafts" then
        local number = tonumber(argument)
        if not F.Integer(number, 1, 100000) then
            F.Print("usage: /dpp crafts 1-100000 (the number of crafts the tooltip's range covers).")
        else
            F.db.crafts = number
            F.Print("the tooltip range now covers " .. number .. " crafts.")
        end
    elseif command == "odds" then
        local number = tonumber(argument)
        if not F.Integer(number, 50, 99) then
            F.Print("usage: /dpp odds 50-99 (the chance of finishing ahead that the [A] button's price limits aim for; now " .. F.db.odds .. ").")
        else
            F.db.odds = number
            F.Print("the [A] button's price limits now aim for a " .. number .. "% chance of finishing ahead.")
            if F.UI.IsShown() then F.UI.Refresh() end
        end
    elseif command == "buy" then
        local number = tonumber(argument)
        if argument == "max" or argument == "all" or argument == "" then
            F.db.buyCrafts = nil
            F.Print("[A] lists now buy for as many crafts as your budget allows (within the price limits).")
        elseif F.Integer(number, 1, 100000) then
            F.db.buyCrafts = number
            F.Print("[A] lists now buy for " .. number .. " crafts (less if your budget cannot buy that many).")
        else
            F.Print("usage: /dpp buy <crafts>, or /dpp buy max (as many as your budget allows).")
            return
        end
        if F.UI.IsShown() then F.UI.Refresh() end
    elseif command == "bags" then
        local number = tonumber(argument)
        if not F.Integer(number, 0, 20) then
            F.Print("usage: /dpp bags 0-20 (the bag slots the vendor + button keeps free; now " .. (F.db.bagReserve or 2) .. ").")
        else
            F.db.bagReserve = number
            F.Print("the vendor + button now keeps " .. number .. " bag slot(s) free.")
        end
    elseif command == "autosearch" then
        if argument == "on" or argument == "off" then
            F.db.autoSearch = argument == "on"
            F.Print("[A] " .. (argument == "on" and "now opens Auctionator's Shopping tab and searches the new list." or "now only creates the list."))
        else
            F.Print("usage: /dpp autosearch on|off (now " .. (F.db.autoSearch ~= false and "on" or "off") .. "). At the auction house, [A] opens Auctionator's Shopping tab and searches the new list; you still click the item and Buy yourself.")
        end
    elseif command == "autoqty" then
        if argument == "on" or argument == "off" then
            F.db.autoQuantity = argument == "on"
            F.Print("lowering Auctionator's buy quantity to the units under your limit: " .. argument .. ".")
        else
            F.Print("usage: /dpp autoqty on|off (now " .. (F.db.autoQuantity ~= false and "on" or "off") .. "). When you open an item from an [A] list, the quantity box is lowered to the units at or under the price limit.")
        end
    elseif command == "margin" then
        local number = tonumber(argument)
        if not F.Integer(number, 0, 100) then
            F.Print("usage: /dpp margin 0-100 (the least profit on cost, in percent, that the [A] button's price limits leave; now " .. F.db.margin .. ").")
        else
            F.db.margin = number
            F.Print("the [A] button's price limits now leave at least " .. number .. "% margin on cost.")
            if F.UI.IsShown() then F.UI.Refresh() end
        end
    elseif command == "budget" then
        local number = tonumber(argument)
        if argument == "all" or argument == "" then
            F.db.budget = nil
            F.Print("budget: all your gold (the most the [A] button's lists may cost).")
        elseif F.Integer(number, 1, 100000000) then
            F.db.budget = number
            F.Print("budget: " .. number .. " gold (never more than you hold).")
        else
            F.Print("usage: /dpp budget <gold>, or /dpp budget all.")
            return
        end
        if F.UI.IsShown() then F.UI.Refresh() end
    elseif command == "luck" then
        if argument == "reset" then
            F.Luck.ResetSession()
            F.Print("luck counter: this session's counts cleared (character and lifetime counts are kept).")
            if F.LuckUI.IsShown() then F.LuckUI.Refresh() end
        else
            F.LuckUI.Toggle()
        end
    elseif command == "sales" then
        F.db.luckTab = "auction"
        if F.LuckUI.IsShown() then F.LuckUI.Refresh() else F.LuckUI.Toggle() end
    elseif command == "de" then
        for _, line in ipairs(F.Disenchant.Report()) do F.Print(line) end
    elseif command == "paid" then
        -- /dpp paid [item link] 40s x3 : what was paid for pieces bought before purchases were tracked
        local rest = (message or ""):match("^%s*%S+%s*(.-)%s*$") or ""
        local link = rest:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)") or rest:match("(|Hitem:.-|h%[.-%]|h)")
        local copper, count, id
        if link then
            local from, to = rest:find(link, 1, true)
            local remainder = rest:sub(1, from - 1) .. " " .. rest:sub(to + 1)
            count = tonumber(remainder:match("[xX]%s*(%d+)")) or 1
            copper = F.Bought.ParseMoney((remainder:gsub("[xX]%s*%d+", "")))
            id = copper and F.Bought.Paid(link, copper, count)
        end
        if id then
            F.Print(string.format("noted: %d x %s at %s each; the average paid is now %s.", count, link, F.Money(copper),
                F.Money(math.floor((F.Bought.Average(id)) + 0.5))))
            if F.LuckUI.IsShown() then F.LuckUI.Refresh() end
        else
            F.Print("usage: /dpp paid [shift-click the item] 40s x3   (the price of one: 1g 20s, 40s or 35c; x3 = how many; adds to what is remembered)")
        end
    elseif command == "nodisenchant" then
        -- /dpp nodisenchant [item]  hides an item that cannot be disenchanted; "remove [item]" shows it again; no item lists them
        local rest = (message or ""):match("^%s*%S+%s*(.-)%s*$") or ""
        local remove = rest:lower():match("^remove%s") ~= nil
        local id = tonumber(rest:match("|Hitem:(%d+)"))
        if id and remove then
            F.Print(F.Disenchant.Unblock(id) and "that item is listed again." or "that item was not hidden.")
        elseif id then
            F.Disenchant.Block(id, rest:match("|h%[(.-)%]|h"))
            F.Print("hidden from the Enchanting list: " .. (rest:match("|h%[(.-)%]|h") or ("item " .. id)) .. ". (/dpp nodisenchant remove [item] undoes it.)")
        else
            local names = {}
            for name in pairs(F.Disenchant.NEVER) do names[#names + 1] = name end
            for itemID, name in pairs(F.db.noDisenchant or {}) do names[#names + 1] = (F.String(name) and name or ("item " .. itemID)) end
            table.sort(names)
            F.Print("not disenchantable, hidden from the Enchanting list: " .. (#names > 0 and table.concat(names, ", ") or "none")
                .. ". Add one with /dpp nodisenchant [shift-click the item], or Ctrl-click a row.")
        end
    elseif command == "minimap" then
        local on = F.Minimap.Toggle(argument == "on" and true or argument == "off" and false or nil)
        F.Print("the minimap button is now " .. (on and "shown." or "hidden.") .. (on and not F.Minimap.button and " (this client has no minimap to put it on.)" or ""))
    elseif command == "crafttime" then
        F.db.craftTime = (argument == "on") or (argument ~= "off" and not F.db.craftTime)
        F.Print("the time of Create All is now " .. (F.db.craftTime and "printed to the chat (DPP Craft time: 15m)." or "not printed."))
    elseif command == "status" then
        Status()
    else
        Help()
    end
end
