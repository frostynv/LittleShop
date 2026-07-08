-- LittleShop Addon
APP_NAME = "LittleShop"


-- ============================================================
-- Order Class
-- ============================================================
local Order = {}
Order.__index = Order

-- Static class variables
Order.ORDER_STATE = {
    NONDECISIVE = -3, -- Not sure if it's a craftable order
    UNLEARNED = -2,   -- Unlearned
    HIDDEN = -1,      -- Special usage state
    COMPLETE = 0,     -- Order has been completed
    PENDING = 1,      -- Order that is detected but no whisper follow up
    UNFULFILLED = 2,  -- Order that has been followed up but not completed
    FULFILLED = 3,    -- Order that has been followed up and completed
}

function Order:new(unique_id, message, player_name, player_realm, guid, item_link, state, timestamp, flags)
    local instance = setmetatable({}, Order)
    instance.unique_id = unique_id
    instance.message = message
    instance.player = {
        name = player_name,
        realm = player_realm,
        guid = guid
    }
    instance.item_link = item_link
    instance.state = state or Order.ORDER_STATE.PENDING
    instance.timestamp = timestamp
    instance.flags = flags or {
        is_lfc = false,
        is_learned = false
    }
    return instance
end

local LittleShopPersistence = {}
LittleShopPersistence.__index = LittleShopPersistence
LittleShopPersistence.SAVED_VARIABLES = {
    ORDERS = {},
    WATCHLIST = {}
}

-- @type table
LittleShopSavedVariables = LittleShopSavedVariables or {}


-- Mimic profile behavior by instancing the persistence class. This allows for future expansion to support multiple profiles.
function LittleShopPersistence:new()
    local instance = setmetatable({}, LittleShopPersistence)
    instance.profile_settings = {}
    return instance
end

function LittleShopPersistence:AddOrder(order)
    table.insert(self.SAVED_VARIABLES.ORDERS, order)
end

function LittleShopPersistence:GetOrder(order)
    return self.SAVED_VARIABLES.ORDERS[order.unique_id]
end

-- ==============================================================

local LittleShopItem = {}
LittleShopItem.__index = LittleShopItem

function LittleShopItem:new(item_id, item_link, crafter, profession)
    local instance = setmetatable({}, LittleShopItem)
    instance.item_id = item_id
    instance.item_link = item_link
    instance.crafter = crafter       -- Optional
    instance.profession = profession -- Optional
    return instance
end

local LittleShopCharacter = {}
LittleShopCharacter.__index = LittleShopCharacter

function LittleShopCharacter:new(name, realm, guid)
    local instance = setmetatable({}, LittleShopCharacter)
    instance.name = name
    instance.realm = realm
    instance.guid = guid
    return instance
end

-- ============================================================
-- LittleShop Class
-- ============================================================
local LittleShop = {}
LittleShop.__index = LittleShop

-- Static class variables

LittleShop.SOUNDS = {
    LFC_DETECTED = 120 -- Sound kit ID for raid warning sound (good for alerts)
}
LittleShop.KEYWORDS = { "lfc", "lfm", "looking for", "lf", "craft" }


LittleShop.Persistence = LittleShopPersistence:new()


function LittleShop:new()
    local instance = setmetatable({}, LittleShop)
    instance.watchlist = {}
    instance.main_frame = nil
    instance.order_frame = nil
    instance.manage_frame = nil
    instance.profile_frame = nil
    instance.orders = {
        _data = {},
        _data_provider = CreateDataProvider(),
        AddOrder = function(orderData)
            table.insert(instance.orders._data, orderData)
            instance.orders._data_provider:Insert(orderData)
        end,
        RemoveOrder = function(order)
            instance.orders._data_provider:RemoveByIndex(order.unique_id)
        end,
        ResetOrders = function()
            instance.orders._data_provider:Flush()
        end,
        GetProvider = function()
            return instance.orders._data_provider
        end
    }
    return instance
end

function LittleShop:ParseItemIdFromLink(item_link)
    if not item_link then return nil end
    return string.match(item_link, "item:(%d+)")
end

function LittleShop:ActivateService()
    LOGGER.CONSOLE.info("Activating Little Shop Service...")
    if not self.main_frame then
        self:InitializeFrame()
        self.main_frame:SetScript("OnLoad", function()
        end)
    end
    self:InitializeWatchList()
    LOGGER.CONSOLE.info("Little Shop Service Activated. Use /showshop to toggle the order board.")
end

function LittleShop:ToggleShow()
    if not self.main_frame then
        self:InitializeFrame()
    end
    if self.main_frame:IsShown() then
        self.main_frame:Hide()
    else
        self.main_frame:Show()
    end
end

function LittleShop:InitializeFrame()
    self.profile_frame = CreateFrame("Frame")
    self.profile_frame:RegisterEvent("PLAYER_LOGIN")
    self.profile_frame:SetScript("OnEvent", function()
        if not LittleShopSavedVariables then
            LittleShopSavedVariables = {}
        end
        self.Persistence.SAVED_VARIABLES = LittleShopSavedVariables
    end)


    self.main_frame = CreateFrame("Frame", "LFC_Main_Frame", UIParent, "BasicFrameTemplate")
    self.main_frame.TitleText:SetText("Little Shop - Your Order Board")
    self.main_frame:SetSize(700, 400)
    self.main_frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    self.main_frame:SetMovable(true)
    self.main_frame:EnableMouse(true)
    self.main_frame:RegisterForDrag("LeftButton")
    self.main_frame:SetScript("OnDragStart", self.main_frame.StartMoving)
    self.main_frame:SetScript("OnDragStop", self.main_frame.StopMovingOrSizing)

    self.order_frame = CreateFrame("Frame", "LFC_Order_Frame", self.main_frame, "BackdropTemplate")
    self.order_frame:SetSize(400, 300)
    self.order_frame:SetPoint("TOPLEFT", self.main_frame, "TOPLEFT", 10, -30)

    -- ORDERFRAME BACKDROP
    self.order_frame:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    self.order_frame:SetBackdropColor(0, 0, 0, 0.5)
    self.order_frame:SetBackdropBorderColor(1, 0.8, 0, 0.5)

    self.manage_frame = CreateFrame("Frame", "LFC_Manage_Frame", self.main_frame)
    LOGGER.CONSOLE.info("Creating Manage Frame...")
    self.manage_frame:SetSize(250, 300)
    self.manage_frame:SetPoint("TOPRIGHT", self.main_frame, "TOPRIGHT", -10, -30)

    -- Grid of buttons in MANAGEFRAME
    local ROWS        = 3
    local COLS        = 3
    local BUTTON_SIZE = 40
    local SPACING     = 10

    for row = 1, ROWS do
        for col = 1, COLS do
            local btn = CreateFrame("Button", nil, self.manage_frame, "UIPanelButtonTemplate")
            btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
            btn:SetText(row .. "," .. col)
            local xOffset = (col - 1) * (BUTTON_SIZE + SPACING) + SPACING
            local yOffset = -(row - 1) * (BUTTON_SIZE + SPACING) - SPACING
            btn:SetPoint("TOPLEFT", self.manage_frame, "TOPLEFT", xOffset, yOffset)
        end
    end

    -- Element: Scroll Box List
    local scroll_box = CreateFrame("Frame", nil, self.order_frame, "WowScrollBoxList")
    scroll_box:SetPoint("TOPLEFT", self.order_frame, "TOPLEFT", 4, -10)
    scroll_box:SetPoint("BOTTOMRIGHT", self.order_frame, "BOTTOMRIGHT", -22, 0)

    -- Element: Scroll Bar
    local scroll_bar = CreateFrame("EventFrame", nil, self.order_frame, "MinimalScrollBar")
    scroll_bar:SetPoint("TOPLEFT", scroll_box, "TOPRIGHT", 4, 0)
    scroll_bar:SetPoint("BOTTOMLEFT", scroll_box, "BOTTOMRIGHT", 4, 10)

    -- Element: Scroll Box List View
    local itemSpacing = 2
    local view = CreateScrollBoxListLinearView(itemSpacing, itemSpacing, itemSpacing, itemSpacing, itemSpacing)
    view:SetElementExtent(20) -- WARNING: Required to set row height. Crash will occur if not defined.
    scroll_box:SetView(view)
    ScrollUtil.InitScrollBoxListWithScrollBar(scroll_box, scroll_bar, view)

    -- Item initializer: assign data to each row button
    view:SetElementInitializer("Button", function(button, element)
        if not button.text then
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            button.text:SetPoint("LEFT", 10, 0)

            local highlight = button:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.2)

            button:SetSize(250, 20)
        end

        local timeData = element.timestamp
        button.text:SetText("[" ..
            string.format("%02d:%02d", timeData.hour, timeData.min) ..
            "] [" .. (element.player.name or "N/A") .. "] " .. (element.item_link or element.message))

        button:SetScript("OnClick", function()
            LOGGER.CONSOLE.list({
                "Order Details:",
                "Unique ID: " .. tostring(element.unique_id),
                "Player: " .. tostring(element.player.name) .. " (" .. tostring(element.player.realm or "") .. ")",
                "Item Link: " .. tostring(element.item_link),
                "Message: " .. tostring(element.message),
                "State: " .. tostring(element.state),
                "Timestamp: " .. string.format("%02d:%02d:%02d", timeData.hour, timeData.min, timeData.sec),
                "Flags: is_lfc=" ..
                tostring(element.flags.is_lfc) .. ", is_learned=" .. tostring(element.flags.is_learned)
            })
        end)
    end)

    scroll_box:SetDataProvider(self.orders.GetProvider(), ScrollBoxConstants.RetainScrollPosition)

    self.main_frame:RegisterEvent("CHAT_MSG_CHANNEL") -- Listens to Trade Chat and other channels (Great for production!)
    self.main_frame:RegisterEvent("CHAT_MSG_SAY")     -- Listens to normal /say (Great for testing!)
    -- Capture addon instance in a closure: WoW passes the frame as 'self' to OnEvent
    local addon = self
    self.main_frame:SetScript("OnEvent", function(frame, event, ...)
        addon:OnChatDetectedEvent(event, ...)
    end)
end

--[[
    Event Handler for Chat Detection
    Doc:
        https://warcraft.wiki.gg/wiki/CHAT_MSG_SAY
        https://warcraft.wiki.gg/wiki/CHAT_MSG_CHANNEL
]]
function LittleShop:OnChatDetectedEvent(event, ...)
    local message, _, _, _, _, _, _, _, channel_name, _, _, guid = ...
    local timestamp = date("*t")

    local _, _, _, _, _, player_name, player_realm = GetPlayerInfoByGUID(guid)

    local lower_chat_text = string.lower(message)
    local has_lfc_keyword = false
    for _, keyword in ipairs(self.KEYWORDS) do
        if string.match(lower_chat_text, keyword) then
            has_lfc_keyword = true
            break
        end
    end

    -- WoW item link format: |cnIQx|Hitem:payload|h[text]|h|r
    local item_link = string.match(message, "|cnIQ[^|]+|H[^|]+|h.-%|h|r")

    if item_link then
        local unique_id = guid .. "_" .. timestamp.day .. timestamp.hour .. timestamp.min .. timestamp.sec
        local order = Order:new(unique_id, message, player_name, player_realm, guid, item_link,
            Order.ORDER_STATE.PENDING, timestamp, {
                is_lfc = has_lfc_keyword,
                is_learned = self.watchlist[self:ParseItemIdFromLink(item_link)] ~= nil
            })

        self.orders.AddOrder(order)
        LOGGER.CONSOLE.info("New order from " .. tostring(guid) .. ": " .. tostring(item_link))
        PlaySound(self.SOUNDS.LFC_DETECTED)
    end
end

function LittleShop:ScanCraftableItems()
    -- Load the player's professions and open the corresponding trade C_TradeSkillUI

    local items = {}
    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
    if not recipeIDs or #recipeIDs == 0 then
        LOGGER.CONSOLE.warn("No craftable recipes found for the player. Watchlist will be empty.")
        return {}
    end

    local count = 0
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned then
            local item_link = C_TradeSkillUI.GetRecipeItemLink(recipeID)
            if item_link then
                local itemID = string.match(item_link, "item:(%d+)")
                if itemID ~= nil then
                    items[itemID] = item_link
                    count = count + 1
                end
            end
        end
    end
    LOGGER.CONSOLE.info("LS Found " .. count .. " craftable items for the player.")
    return items
end

function LittleShop:InitializeWatchList()
    self.watchlist = self:ScanCraftableItems()
end

-- ============================================================
-- Addon Bootstrap (must stay in global scope)
-- ============================================================
local littleshop = LittleShop:new()
littleshop:ActivateService()

-- Minimap Button Setup
LittleShop.MINIMAP_BUTTON = {
    icon = "Interface\\Icons\\INV_Chest_Cloth_17",
    tooltip = "Little Shop - Click to toggle the order board.",
    OnClick = function()
        littleshop:ToggleShow()
    end
}
local addon = LibStub("AceAddon-3.0"):NewAddon("Bunnies")
local bunnyLDB = LibStub("LibDataBroker-1.1"):NewDataObject("LITTLESHOP_UI_MINIMAP_BUTTON", {
    type = "UI",
    text = LittleShop.MINIMAP_BUTTON.tooltip,
    icon = LittleShop.MINIMAP_BUTTON.icon,
    OnClick = LittleShop.MINIMAP_BUTTON.OnClick,
})
local icon = LibStub("LibDBIcon-1.0")

-- Activate the service when the addon is loaded
function addon:OnInitialize()
    -- Assuming you have a ## SavedVariables: LittleShopSavedVariables line in your TOC
    self.db = LibStub("AceDB-3.0"):New("LittleShopSavedVariables", {
        profile = {
            minimap = {
                hide = false,
            },
        },
    })
    icon:Register("LittleShop", bunnyLDB, self.db.profile.minimap)

    LOGGER.CONSOLE.info("LittleShop Addon Initialized.")
    LOGGER.CONSOLE.info("Saved Variables Loaded: " .. tostring(LittleShopSavedVariables))
end

--[[
Slash Command Handlers
]]    

SLASH_LITTLESHOP_BOOT = "/littleshop"
SLASH_LITTLESHOP_TOGGLE_SHOW = "/showshop"
SlashCmdList["LITTLESHOP_BOOT"] = function()
    littleshop:ActivateService()
end
SlashCmdList["LITTLESHOP_TOGGLE_SHOW"] = function()
    littleshop:ToggleShow()
end



