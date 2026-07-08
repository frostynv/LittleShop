-- LittleShop Addon
APP_NAME = "LittleShop"
-- Order and Item classes are defined in order.lua, loaded before this file.

-- Capture class references from global scope (exported by order.lua and item.lua)
-- to avoid repeated global lookups while keeping namespace pollution minimal
local Order = _G.Order
local Craft = _G.Craft


-- ============================================================
-- Persistence Class
-- ============================================================
local Persistence = {}
Persistence.__index = Persistence

-- Mimic profile behavior by instancing the persistence class. This allows for future expansion to support multiple profiles.
function Persistence:New()
    local instance = setmetatable({}, Persistence)
    instance.profile_settings = {}   -- Profile settings for the current user
    instance.learned_crafts = {}     -- Map of learned items keyed by itemID: itemID -> craft object
    instance.orders = {}
    instance.current_character = nil -- Initialize crafter tracking
    return instance
end

function Persistence:Init()
    -- Load saved variables from the global scope (LittleShopSavedVariables)
    if not LittleShopSavedVariables then
        LittleShopSavedVariables = {}
    end
    self.profile_settings = LittleShopSavedVariables.profile or {}
    self.learned_crafts = LittleShopSavedVariables.learned_crafts or {}
    self.orders = LittleShopSavedVariables.orders or {}
end

function Persistence:CurrentCrafter()
    return self.current_character
end

function Persistence:SetCurrentCrafter(character)
    self.current_character = character
end

function Persistence:CurrentProfile()
    return self.profile_settings
end

function Persistence:AddOrder(order)
    self.orders[order.unique_id] = order
end

function Persistence:GetOrder(order)
    return self.orders[order.unique_id]
end

function Persistence:RemoveOrder(order)
    self.orders[order.unique_id] = nil
end

function Persistence:ResetOrders()
    self.orders = {}
end

function Persistence:AddCraftableItem(craft)
    self.learned_crafts[craft.item_id] = craft
end

function Persistence:RemoveCraftableItem    (craft)
    self.learned_crafts[craft.item_id] = nil
end

function Persistence:SetCraftableItem(craft)
    self.learned_crafts[craft.item_id] = craft
end

function Persistence:MergeLearnedCrafts(new_crafts)
    for item_id, new_craft in pairs(new_crafts) do
        if self.learned_crafts[item_id] then
            self.learned_crafts[item_id]:AddCrafter(new_craft.crafter) -- Merge crafters if the item already exists
        else
            -- New item, just add it
            self.learned_crafts[item_id] = new_craft
        end
    end
end



-- ==============================================================
-- Character Class
-- ==============================================================

local Character = {}
Character.__index = Character

function Character:New(name, realm, guid)
    local instance = setmetatable({}, Character)
    instance.name = name
    instance.realm = realm
    instance.guid = guid
    return instance
end

-- ==============================================================
-- Crafter Class
-- ==============================================================
local Crafter = {}
Crafter.__index = Crafter

function Crafter:New(character, profession)
    local instance = Character:New(character.name, character.realm, character.guid)
    setmetatable(instance, Crafter)
    instance.profession = profession
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

function LittleShop:New()
    local instance = setmetatable({}, LittleShop)
    instance.is_active = false
    instance.persistence = Persistence:New()

    -- TODO: Setup the profile loading and saving mechanism for the addon. This will allow users to have different profiles for different characters or playstyles.
    instance.main_frame = nil
    instance.order_frame = nil
    instance._order_provider = CreateDataProvider()
    instance.manage_frame = nil
    instance.profile_frame = nil
    return instance
end

function LittleShop:AddOrder(orderData)
    self.persistence:AddOrder(orderData)
    self._order_provider:Insert(orderData)
end

function LittleShop:RemoveOrder(order)
    self.persistence:RemoveOrder(order)
    self._order_provider:RemoveByIndex(order.unique_id)
end

function LittleShop:ResetOrders()
    self.persistence:ResetOrders()
    self._order_provider:Flush()
end

function LittleShop:GetProvider()
    return self._order_provider
end

function LittleShop:IsActive()
    return self.is_active
end

function LittleShop:Persistence()
    return self.persistence
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
    self.persistence:Init()
    self.learned_crafts = self:ScanCraftableItems()
    self.is_active = true
    LOGGER.CONSOLE.info("Little Shop Service Activated. Use /showshop to toggle the order board.")
end

function LittleShop:DeactivateService()
    LOGGER.CONSOLE.info("Deactivating Little Shop Service...")
    self.is_active = false
    LOGGER.CONSOLE.info("Little Shop Service Deactivated.")
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
        -- self.Persistence.SAVED_VARIABLES = LittleShopSavedVariables
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

    scroll_box:SetDataProvider(self._order_provider, ScrollBoxConstants.RetainScrollPosition)

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
        local item_id = self:ParseItemIdFromLink(item_link)
        local is_item_learned = self.learned_crafts and self.learned_crafts[item_id] ~= nil
        
        local order = Order:New(unique_id, message, player_name, player_realm, guid, item_link,
            nil, timestamp, {
                is_lfc = has_lfc_keyword,
                is_learned = is_item_learned
            })
        
        if is_item_learned then
            order.state = Order.ORDER_STATE.PENDING
        else
            order.state = Order.ORDER_STATE.UNLEARNED
        end

        self:AddOrder(order)
        LOGGER.CONSOLE.info("New order from " .. player_realm .. "-" .. player_name .. ": " .. tostring(item_link))
        PlaySound(self.SOUNDS.LFC_DETECTED)
    end
end

function LittleShop:ScanCraftableItems()
    -- Load the player's professions and open the corresponding trade C_TradeSkillUI
    -- Use Item class for encapsulation of item data (item_id, item_link, crafter, profession)
    local learned_crafts = {}
    -- Info: We can only get the list of craftable recipes, althought LFC will call for items.
    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
    if not recipeIDs or #recipeIDs == 0 then
        LOGGER.CONSOLE.warn("No craftable recipes found for the player. Learned crafts will be empty.")
        return {}
    end

    local count = 0
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        -- Case: include only learned recipes (craftable items).
        if recipeInfo and recipeInfo.learned then
            -- Fetch item information
            --     Fetch profession information for the recipe
            --     Fetch item link for the recipe
            -- https://warcraft.wiki.gg/wiki/API_C_TradeSkillUI.GetProfessionInfoByRecipeID
            local item_link = C_TradeSkillUI.GetRecipeItemLink(recipeID)
            if item_link then
                -- Info: We decided on itemid as the key for tables + encapsulating identifier for a craftable recipe
                local itemID = string.match(item_link, "item:(%d+)")
                -- Case: Corruption of data or edge cases
                if itemID ~= nil then
                    local craft = Craft:New(itemID, item_link, { [self:Persistence():CurrentCrafter().name] = true }, recipeID)
                    learned_crafts[itemID] = craft
                    count = count + 1
                end
            end
        end
    end
    LOGGER.CONSOLE.info("LittleShop found " ..
        count ..
        " craftable items for " ..
        self:Persistence():CurrentCrafter().name .. " on realm " .. self:Persistence():CurrentCrafter().realm)
    return learned_crafts
end

-- ============================================================
-- Addon Bootstrap (must stay in global scope)
-- ============================================================
local littleshop = LittleShop:New()

-- Minimap Button Setup
LittleShop.MINIMAP_BUTTON = {
    icon = "Interface\\Icons\\INV_Chest_Cloth_17",
    tooltip = "LittleShop - Left-click to toggle the order board. Right-click to activate/deactivate the service.",
    OnClick = function(frame, button)
        if button == "LeftButton" then
            -- Left-click: toggle the main frame and service

            littleshop:ToggleShow()
        elseif button == "RightButton" then
            -- Right-click: placeholder for context menu or alternate action
            if not littleshop:IsActive() then
                littleshop:ActivateService()
            else
                littleshop:DeactivateService()
            end
        end
    end
}
local addon = LibStub("AceAddon-3.0"):NewAddon("LittleShop")
local minimap_button = LibStub("LibDataBroker-1.1"):NewDataObject("LITTLESHOP_UI_MINIMAP_BUTTON", {
    type = "UI",
    text = LittleShop.MINIMAP_BUTTON.tooltip,
    icon = LittleShop.MINIMAP_BUTTON.icon,
    OnClick = LittleShop.MINIMAP_BUTTON.OnClick,
})

-- Minimap button library
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
    icon:Register("LittleShop", minimap_button, self.db.profile.minimap)

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
