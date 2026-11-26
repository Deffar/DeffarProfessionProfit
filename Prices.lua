-- Deffar Profession Profit: where auction house prices come from. Auctionator (its price API; the Enchanting tab and the [A] lists also use its
-- internals) or TradeSkillMaster (its public TSM_API price sources). One answer for the rest of the addon: F.Prices.Price(id) in copper or nil,
-- F.Prices.Age(id) in days or nil, and which features the chosen addon can serve.
--
-- TSM, read from the installed TradeSkillMaster 4.15.9 and checked in game by the human (2026-11-26; plans/addons/TSM-integration.md):
--   * TSM_API.GetCustomPriceValue(source, "i:<itemID>") gives a price. DBMinBuyout was 26, 114 and 300 where Auctionator had 28, 114 and 320
--     (Linen Cloth, Strange Dust, Buzzard Wing). The data is the TSM Desktop App's download (AppHelper addon) loaded at login, about an hour old,
--     so there is no price age to read (TSM shows "46 min ago" in its own tooltip only).
--   * "Destroy" is TSM's disenchant value of a gear item (1147 copper for item 4318).
--   * TSM has no API to make a shopping list and none to list every priced item: the [A] button and the Enchanting tab need Auctionator.
-- The ledger entries for third-party addons stay out of plans/api-facts.md.
local _, F = ...
local P = {}
F.Prices = P

-- The TSM price sources the addon tries, the chosen one first (db.tsmSource, default DBMinBuyout); a missing source just gives nil.
P.TSM_SOURCES = { "DBMinBuyout", "AHDBMinBuyout", "DBMarket", "DBRecent" }

function P.AuctionatorLoaded()
    local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
    return (api and api.GetAuctionPriceByItemID) and true or false
end

function P.TSMLoaded()
    local api = _G.TSM_API
    return type(api) == "table" and type(api.GetCustomPriceValue) == "function"
end

-- The addon the prices come from first: "auctionator", "tsm" or nil. db.ahAddon is "auto" (TSM when it is loaded: someone who runs TSM uses it as
-- the main auction addon and Auctionator is the extra source; human decision 2026-11-26), "tsm" or "auctionator"; a choice that is not loaded
-- falls back to the other one. The other addon, when loaded, is the backup for an item the first one has no price for (P.Lookup).
function P.Addon()
    local choice = F.db and F.db.ahAddon
    local auctionator, tsm = P.AuctionatorLoaded(), P.TSMLoaded()
    if choice == "auctionator" and auctionator then return "auctionator" end
    if tsm then return "tsm" end
    if auctionator then return "auctionator" end
    return nil
end

function P.BothLoaded()
    return P.AuctionatorLoaded() and P.TSMLoaded()
end

function P.Name()
    local addon = P.Addon()
    return addon == "tsm" and "TSM" or (addon == "auctionator" and "Auctionator" or nil)
end

-- The TSM price source in use first.
function P.TSMSource()
    local chosen = F.db and F.String(F.db.tsmSource) and F.db.tsmSource ~= "" and F.db.tsmSource or nil
    return chosen or P.TSM_SOURCES[1]
end

local function TSMValue(source, id)
    local ok, value = pcall(_G.TSM_API.GetCustomPriceValue, source, "i:" .. tostring(id))
    if ok and F.Number(value) and value >= 1 then return math.floor(value) end
    return nil
end

function P.TSMPrice(id)
    if not (P.TSMLoaded() and F.Integer(id, 1, 2147483647)) then return nil end
    local first = P.TSMSource()
    local price = TSMValue(first, id)
    if price then return price end
    for _, source in ipairs(P.TSM_SOURCES) do   -- (a source the user has no data for, or does not have: the next one)
        if source ~= first then
            price = TSMValue(source, id)
            if price then return price end
        end
    end
    return nil
end

-- TSM's disenchant value of a gear item (what its disenchant results are worth, before the auction house cut); nil when it has none.
function P.DestroyValue(id)
    if not (P.TSMLoaded() and F.Integer(id, 1, 2147483647)) then return nil end
    return TSMValue("Destroy", id)
end

local function AuctionatorPrice(id)
    if not P.AuctionatorLoaded() then return nil end
    local ok, price = pcall(_G.Auctionator.API.v1.GetAuctionPriceByItemID, F.CALLER, id)
    if ok and F.Integer(price, 1, 2147483647) then return price end
    return nil
end

-- The price of one item in copper and the addon it came from ("tsm" or "auctionator"): the preferred addon first, the other one when it has none.
function P.Lookup(id)
    local first = P.Addon()
    if first == nil then return nil end
    local second = first == "tsm" and "auctionator" or "tsm"
    for _, addon in ipairs({ first, second }) do
        local price = addon == "tsm" and P.TSMPrice(id) or (addon == "auctionator" and AuctionatorPrice(id) or nil)
        if price then return price, addon end
    end
    return nil
end

-- The price of one item in copper, nil without one (FOR-0166 for Auctionator's call).
function P.Price(id)
    return (P.Lookup(id))
end

-- Days since the item was last seen in the auction house; nil when never seen, older than 21 days (Auctionator\Source\API\v1\GetAuctionAge.lua),
-- or when the price came from TSM, which does not say.
function P.Age(id)
    local _, source = P.Lookup(id)
    if source ~= "auctionator" then return nil end
    local api = _G.Auctionator.API.v1
    if not api.GetAuctionAgeByItemID then return nil end
    local ok, age = pcall(api.GetAuctionAgeByItemID, F.CALLER, id)
    if ok and F.Number(age) and age >= 0 then return age end
    return nil
end

-- Whether TSM's auction window is open (its public API): the [T] button only searches there.
function P.TSMAuctionVisible()
    local api = _G.TSM_API
    if not (type(api) == "table" and type(api.IsUIVisible) == "function") then return false end
    local ok, visible = pcall(api.IsUIVisible, "AUCTION")
    return ok and visible == true
end

-- TSM's Browse search box, typed into by the T button (the experiment of 2026-11-26, human request: "as few steps as possible, as with Auctionator").
-- TSM has no search API, so this goes through its frames, which is fragile and written to fail quietly (the caller falls back to linking the item):
--   * its Browse search page has an input (LibTSMUI BaseInput: an EditBox in a frame that also holds a FontString with the hint "Search the auction house",
--     App\AuctionUI\Shopping.lua); typing there is a SetText, then its own OnTextChanged (with userInput = true, which TSM requires) and OnEnterPressed
--     scripts, which start the search (ACTION_START_FILTER_INPUT_SEARCH reads the input's value);
--   * the page that shows the results has an "Exit Scan" button (App\AuctionUI\ExitScanButton.lua) that goes back to the search page.
-- The hint and the button text are TSM's English strings: another client language finds nothing and falls back.
P.TSM_BROWSE_HINT = "Search the auction house"
P.TSM_EXIT_SCAN = "Exit Scan"

local function EachFrame(visit)
    if type(EnumerateFrames) ~= "function" then return nil end
    local frame = EnumerateFrames()
    while frame do
        local ok, found = pcall(visit, frame)   -- (a frame that will not answer, a forbidden one for instance, is skipped)
        if ok and found then return found end
        frame = EnumerateFrames(frame)
    end
    return nil
end

local function HasText(frame, wanted, partial)
    if type(frame.GetRegions) ~= "function" then return false end
    for _, region in ipairs({ frame:GetRegions() }) do
        if type(region) == "table" and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" and type(region.GetText) == "function" then
            local text = region:GetText()
            if type(text) == "string" and (partial and text:find(wanted, 1, true) or text == wanted) then return true end
        end
    end
    return false
end

-- How far up from an EditBox its hint text is: 0 the box itself, 1 its parent frame, 2 and 3 further up; nil when none holds it. TSM's input keeps the
-- hint in the frame that wraps the box, which the first version of this looked at only (the human found T worked only after a search: on the landing
-- page the box was not recognised).
local function HintLevel(frame)
    local node = frame
    for level = 0, 3 do
        if not node then return nil end
        if HasText(node, P.TSM_BROWSE_HINT, false) then return level end
        node = type(node.GetParent) == "function" and node:GetParent() or nil
    end
    return nil
end

-- The visible Browse search input of TSM's auction window (the box whose hint is nearest), or nil (not on Browse, an unknown language).
function P.TSMBrowseBox()
    local best, bestLevel
    EachFrame(function(frame)
        if type(frame.GetObjectType) == "function" and frame:GetObjectType() == "EditBox" and frame:IsVisible() then
            local level = HintLevel(frame)
            if level and (not bestLevel or level < bestLevel) then best, bestLevel = frame, level end
        end
        return nil   -- (every frame is looked at: the nearest hint wins)
    end)
    return best, bestLevel
end

-- What the visible edit boxes look like, for /dpp tsmfind: up to 6 lines.
function P.TSMDescribeBoxes()
    local lines = {}
    local function Texts(node)
        local out = {}
        if node and type(node.GetRegions) == "function" then
            for _, region in ipairs({ node:GetRegions() }) do
                if type(region) == "table" and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" and type(region.GetText) == "function" then
                    local text = region:GetText()
                    if type(text) == "string" and text ~= "" then out[#out + 1] = text:sub(1, 28) end
                end
            end
        end
        return table.concat(out, " | ")
    end
    EachFrame(function(frame)
        if #lines < 6 and type(frame.GetObjectType) == "function" and frame:GetObjectType() == "EditBox" and frame:IsVisible() then
            local parent = type(frame.GetParent) == "function" and frame:GetParent() or nil
            lines[#lines + 1] = string.format("visible EditBox: own texts [%s], parent texts [%s], hint level %s", Texts(frame), Texts(parent), tostring(HintLevel(frame)))
        end
        return nil
    end)
    return lines
end

function P.TSMExitScanButton()
    return EachFrame(function(frame)
        if type(frame.GetObjectType) == "function" and frame:GetObjectType() == "Button" and frame:IsVisible() and HasText(frame, P.TSM_EXIT_SCAN, true) then return frame end
    end)
end

-- Types `text` into the Browse search box and starts the search. Returns true, or false and why ("nobox", "noscript").
function P.TSMTypeAndSearch(text)
    local box = P.TSMBrowseBox()
    if not box then return false, "nobox" end
    local changed, enter = box:GetScript("OnTextChanged"), box:GetScript("OnEnterPressed")
    if type(changed) ~= "function" or type(enter) ~= "function" then return false, "noscript" end
    box:SetText(text)
    local ok1 = pcall(changed, box, true)   -- (userInput = true: TSM ignores a program's own SetText)
    local ok2 = pcall(enter, box)
    return ok1 and ok2, (ok1 and ok2) and nil or "error"
end

-- Switching between TSM's auction window and the game's own, for the A and T buttons (human report: with both addons loaded, [A] made its list behind
-- TSM's window and the results could not be seen). TSM adds a tab "TSM_AH_TAB" to the auction house frame with LibAHTab (App\AuctionUI\Core.lua,
-- LibTSMWoW\Source\API\AuctionHouse.lua AddTab) whose click shows its window, and its window has a "WoW UI" button (LibTSMUI ApplicationFrame) that shows the
-- game's. Both are clicked here the way the player would; each says whether a click was sent.
function P.AuctionHouseOpen()
    local frame = _G.AuctionHouseFrame
    return type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() == true
end

function P.TSMShowWindow()
    local stub = _G.LibStub
    local lib = (type(stub) == "table" or type(stub) == "function") and type(stub.GetLibrary) == "function" and stub:GetLibrary("LibAHTab-1-0", true) or nil
    local button = lib and type(lib.GetButton) == "function" and lib:GetButton("TSM_AH_TAB") or nil
    if type(button) == "table" and type(button.Click) == "function" then
        pcall(button.Click, button)
        return true
    end
    return false
end

function P.TSMShowDefaultUI()
    local button = EachFrame(function(frame)
        if type(frame.GetObjectType) == "function" and frame:GetObjectType() == "Button" and frame:IsVisible() and HasText(frame, "WoW UI", true) then return frame end
    end)
    if button and type(button.Click) == "function" then
        pcall(button.Click, button)
        return true
    end
    return false
end

-- What the addon in use cannot do, for the buttons that go grey: the words of a hover, or nil when it can.
function P.CannotShop()
    if P.TSMLoaded() and not P.AuctionatorLoaded() then return "TSM has no shopping-list API" end
    return nil
end

function P.CannotEnchant()
    if P.TSMLoaded() and not P.AuctionatorLoaded() then return "TSM has no list of priced items" end
    return nil
end
