local namespace = select(2, ...) -- Get the namespace table from the addon
local Order = namespace.require("Order")
local Craft = namespace.require("Craft")
local EnhancedFrame = namespace.require("EnhancedFrame")


-- ============================================================
-- Persistence Class
-- ============================================================
-- @type Persistence
-- @field learned_crafts table    Map of item_id -> Craft object for learned recipes
-- @field orders        table    Map of order.unique_id -> Order object
-- @field profile_settings table Profile-specific settings (can be expanded for multi-profile support)
local Persistence = {}
Persistence.__index = Persistence
Persistence.DEFAULT_PROFILE = {
    name = "default",
    minimap = {
        hide = false,
    },
}

Persistence.FACTORY_SAVEDVARIABLE = {
    profile_settings = {},
    learned_crafts = {},
    orders = {},
    ValidateSavedVariableStructure = function()
    if not LittleShopSavedVariables then
        LittleShopSavedVariables = {}
    end
    for key, default_value in pairs(Persistence.FACTORY_SAVEDVARIABLE) do
        if LittleShopSavedVariables[key] == nil then
            LittleShopSavedVariables[key] = default_value
        end
    end
end
}

-- Creates a new Persistence instance
-- Mimic profile behavior by instancing the persistence class. This allows for future expansion to support multiple profiles.
-- @return Persistence
function Persistence:New()
    local instance = setmetatable({}, Persistence)
    instance.learned_crafts = {}   -- Map of learned items keyed by itemID: itemID -> craft object
    instance.orders = {}
    instance.profile_settings = {} -- Profile settings for the addon, can be expanded in the future
    return instance
end

-- Initializes persistence with saved data from WoW's SavedVariables
-- Restores metatables to Craft and Order instances (lost during serialization)
-- @param profile_name string Optional profile name; defaults to 'default'
-- @return Persistence self
function Persistence:Initialize(...)
    Persistence.FACTORY_SAVEDVARIABLE.ValidateSavedVariableStructure()
    local profile_name = ... or Persistence.DEFAULT_PROFILE.name
    if LittleShopSavedVariables then
        self.profile_settings = LittleShopSavedVariables.profile_settings[profile_name] or {}
        self.learned_crafts = LittleShopSavedVariables.learned_crafts or {}
        self.orders = LittleShopSavedVariables.orders or {}

        -- Restore metatables to persisted Craft instances
        -- (Serialization loses metatable info; we reattach them when loading)
        for item_id, craft_data in pairs(self.learned_crafts) do
            setmetatable(craft_data, Craft)
        end

        -- Restore metatables to persisted Order instances
        for order_id, order_data in pairs(self.orders) do
            setmetatable(order_data, Order)
        end
    end
    return self
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

-- Learned Crafts Management
function Persistence:AddCraftableItem(craft)
    self.learned_crafts[craft.item_id] = craft
    if self.on_crafts_changed then
        self.on_crafts_changed()
    end
end

function Persistence:RemoveCraftableItem(craft)
    self.learned_crafts[craft.item_id] = nil
end

function Persistence:CraftableItemCountSize()
    local count = 0
    for _ in pairs(self.learned_crafts) do
        count = count + 1
    end
    return count
end

-- ============================================================
-- Getter / Setters
-- =============================================================
function Persistence:GetCraftableItem(item_id)
    return self.learned_crafts[item_id]
end

function Persistence:IsCraftableItemLearned(item_id)
    return self.learned_crafts[item_id] ~= nil
end

function Persistence:SetCraftableItem(craft)
    self.learned_crafts[craft.item_id] = craft
end

function Persistence:MergeLearnedCrafts(new_crafts)
    if not new_crafts or next(new_crafts) == nil then
        LOGGER.CONSOLE.warn("No new crafts to merge into persistence. Skipping merge.")
        return
    end
    for item_id, new_craft in pairs(new_crafts) do
        if self.learned_crafts[item_id] then
            self.learned_crafts[item_id]:AddCrafters(new_craft:GetCrafters()) -- Merge crafters if the item already exists
        else
            -- New item, just add it
            self.learned_crafts[item_id] = new_craft
        end
    end
    if self.on_crafts_changed then
        self.on_crafts_changed()
    end
    LOGGER.CONSOLE.info("In total " .. self:CraftableItemCountSize() .. " craft in persistence.")
end



-- ==============================================================
-- Character Class
-- ==============================================================

-- @type Character
-- @field name  string Character name
-- @field realm string Realm (server) name
-- @field guid  string WoW player GUID
local Character = {}
Character.__index = Character

-- Creates a new Character instance
-- @param name string Character name
-- @param realm string Realm name
-- @param guid string Player GUID
-- @return Character
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

-- @type Crafter
-- @field name       string Character name (inherited from Character)
-- @field realm      string Realm name (inherited from Character)
-- @field guid       string Player GUID (inherited from Character)
-- @field profession string Profession name (e.g. "Blacksmithing", "Tailoring")
local Crafter = {}
Crafter.__index = Crafter

-- Creates a new Crafter instance (extends Character)
-- @param character Character object containing name, realm, guid
-- @param profession string Profession name
-- @return Crafter
function Crafter:New(character, profession)
    local instance = Character:New(character.name, character.realm, character.guid)
    setmetatable(instance, Crafter)
    instance.profession = profession
    return instance
end

-- ============================================================
-- LittleShop Class
-- ============================================================

-- @type LittleShop
-- @field is_active          boolean Whether the addon service is currently running
-- @field persistence        Persistence Instance managing saved data
-- @field current_character  Crafter Current character's crafter profile
-- @field META_FRAME         Frame WoW event registration frame
-- @field _order_provider    DataProvider UI data provider for order display
-- @field _crafts_provider   DataProvider UI data provider for learned crafts display
-- @field main_frame         Frame Main UI frame (nil until initialized)
-- @field order_frame        Frame Order management UI frame
-- @field manage_frame       Frame Settings/management UI frame
-- @field profile_frame      Frame Profile UI frame
local LittleShop = {}
LittleShop.__index = LittleShop

-- Static class variables
LittleShop.SOUNDS = {
    LFC_DETECTED = 120 -- Sound kit ID for raid warning sound (good for alerts)
}
LittleShop.KEYWORDS = { "lfc", "lfm", "looking for", "lf", "craft" }
LittleShop.APP_NAME = "LittleShop"

-- Creates a new LittleShop addon instance
-- @return LittleShop
function LittleShop:New()
    local instance = setmetatable({}, LittleShop)
    instance.is_active = false
    instance.persistence = Persistence:New()
    instance.current_character = nil -- Initialize crafter tracking

    -- TODO: Setup the profile loading and saving mechanism for the addon. This will allow users to have different profiles for different characters or playstyles.

    -- Global abstract frame for register of events
    instance.EVENT_FRAME = CreateFrame("Frame")
    instance.main_frame = nil
    instance.order_frame = nil
    instance._order_provider = CreateDataProvider()
    instance._crafts_provider = CreateDataProvider() -- Data provider for learned crafts
    instance.manage_frame = nil
    instance.profile_frame = nil
    instance.minimap_button = LittleShop.MINIMAP_BUTTON.GetInstance(instance) -- Imported 
    return instance
end



-- =============================================================
-- LittleShop API Methods
-- =============================================================

-- Gets the current character's crafter profile
-- @return Crafter or nil
function LittleShop:GetCurrentCrafter()
    return self.current_character
end

-- Sets the current character's crafter profile
-- @param character Crafter object to set as current
-- @return void
function LittleShop:SetCurrentCrafter(character)
    self.current_character = character
end

-- Adds an order to both persistence and UI data provider
-- @param orderData Order object to add
-- @return void
function LittleShop:AddOrder(orderData)
    self.persistence:AddOrder(orderData)
    self._order_provider:Insert(orderData)
end

-- Removes an order from both persistence and UI data provider
-- @param order Order object to remove
-- @return void
function LittleShop:RemoveOrder(order)
    self.persistence:RemoveOrder(order)
    self._order_provider:RemoveByIndex(order.unique_id)
end

-- Clears all orders from persistence and UI data provider
-- @return void
function LittleShop:ResetOrders()
    self.persistence:ResetOrders()
    self._order_provider:Flush()
end

-- Gets the UI data provider for order display
-- @return DataProvider
function LittleShop:GetProvider()
    return self._order_provider
end

-- Checks if the addon service is currently active
-- @return boolean
function LittleShop:IsActive()
    return self.is_active
end

-- Gets the persistence layer instance
-- @return Persistence
function LittleShop:Persistence()
    return self.persistence
end

-- Extracts item ID from a WoW item link
-- Item link format: |cFF0070dditem:item_id:...|h[Item Name]|h|r
-- @param item_link string WoW item hyperlink
-- @return number item_id or nil if extraction fails
function LittleShop:ParseItemIdFromLink(item_link)
    if not item_link then return nil end
    return string.match(item_link, "item:(%d+)")
end

-- Deactivates the addon service
-- @return void
function LittleShop:DeactivateService()
    LOGGER.CONSOLE.info("Deactivating Little Shop Service...")
    self.is_active = false
    LOGGER.CONSOLE.info("Little Shop Service Deactivated.")
end

-- Toggles visibility of the main frame
-- Initializes frame on first call
-- @return void
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
        local is_learned = self.persistence:IsCraftableItemLearned(item_id)

        local order = Order:New(unique_id, message, player_name, player_realm, guid, item_link,
            nil, timestamp, {
                is_lfc = has_lfc_keyword,
                is_learned = is_learned
            })

        order.state = is_learned and Order.ORDER_STATE.PENDING or Order.ORDER_STATE.UNLEARNED
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
                    local craft = Craft:New(itemID, item_link, { [self:GetCurrentCrafter().name] = true }, recipeID)
                    learned_crafts[itemID] = craft
                    count = count + 1
                end
            end
        end
    end
    LOGGER.CONSOLE.info("LittleShop found " ..
        count ..
        " craftable items for " ..
        self:GetCurrentCrafter().name .. " on realm " .. self:GetCurrentCrafter().realm)
    return learned_crafts
end

-- ============================================================
-- API Event Registration and Handling
--============================================================

LittleShop.EVENTS = {}
-- Registers a WoW API event and binds it to a handler function
-- @param event string WoW event name (e.g. "PLAYER_LOGIN", "PLAYER_LOGOUT")
-- @param handler function Function to call when event fires: handler(self, event, ...)
-- @return function The handler function
function LittleShop:RegisterEvent(event, handler)
    if not self.EVENT_FRAME then
        self.EVENT_FRAME = CreateFrame("Frame")
    end
    self.EVENT_FRAME:RegisterEvent(event)
    self.EVENT_FRAME:SetScript("OnEvent", function(frame, event, ...)
        handler(self, event, ...)
    end)
    return handler
end

-- Binds multiple WoW events to handlers defined in self.EVENTS table
-- @param events table Array of event names to bind
-- @return void
function LittleShop:BindEvents(events)
    for _, event in ipairs(events) do
        self:RegisterEvent(event, function(self, event, ...)
            LOGGER.CONSOLE.info("Event triggered: " .. event)
            if self.EVENTS[event] then
                self.EVENTS[event](self, event, ...)
            end
        end)
    end
end

function LittleShop.EVENTS:PLAYER_LOGIN()
    LOGGER.CONSOLE.info("Player logged in. Initializing Little Shop...")
    local player_name = UnitName("player")
    local player_realm = GetRealmName()
    local player_guid = UnitGUID("player")
    self.current_character = Crafter:New(Character:New(player_name, player_realm, player_guid), nil)
    self:SetCurrentCrafter(self.current_character)

    -- Activate service
    LOGGER.CONSOLE.info("Activating Little Shop Service...")
    if not self.main_frame then
        self:BuildUI()
    end
    self.persistence:Initialize()
    self.persistence:MergeLearnedCrafts(self:ScanCraftableItems())

    self.is_active = true


    LOGGER.CONSOLE.info("Little Shop Service Activated. Use /showshop to toggle the order board.")
end

function LittleShop.EVENTS:CHAT_MSG_CHANNEL(event, ...)
    self:OnChatDetectedEvent(event, ...)
end

function LittleShop.EVENTS:CHAT_MSG_SAY(event, ...)
    self:OnChatDetectedEvent(event, ...)
end

function LittleShop.EVENTS:ADDON_LOADED(event, addon_name)
    if addon_name == "LittleShop" then
        LOGGER.CONSOLE.info("Little Shop Addon Loaded.")
    end
end


-- ============================================================
-- SINGLETON ASSETS
-- ===========================================================
LittleShop.MINIMAP_BUTTON = {
    littleshop = nil,
    dbname = "LittleShopMinimapButton",
    icon = "Interface\\Icons\\INV_Chest_Cloth_17",
    tooltip = "LittleShop - Left-click to toggle the order board. Right-click to activate/deactivate the service.",
    OnClick = function(frame, button)
        if button == "LeftButton" then
            -- Left-click: toggle the main frame and service

            LittleShop.MINIMAP_BUTTON.littleshop:ToggleShow()
        elseif button == "RightButton" then
            -- Right-click: placeholder for context menu or alternate action
            if not LittleShop.MINIMAP_BUTTON.littleshop:IsActive() then
                LittleShop.MINIMAP_BUTTON.littleshop:ActivateService()
            else
                LittleShop.MINIMAP_BUTTON.littleshop:DeactivateService()
            end
        end
    end,
    -- Initializes the minimap button with LibDBIcon
    -- @param littleshopdependency LittleShop instance (addon singleton)
    -- @return table MINIMAP_BUTTON config (with icon registered)
    GetInstance = function(littleshopdependency)
        LittleShop.MINIMAP_BUTTON.littleshop = littleshopdependency
        
        local icon = LibStub("LibDBIcon-1.0")
        local minimap_button = LibStub("LibDataBroker-1.1"):NewDataObject(
            LittleShop.MINIMAP_BUTTON.dbname, 
            {
                type = "UI",
                text = LittleShop.MINIMAP_BUTTON.tooltip,
                icon = LittleShop.MINIMAP_BUTTON.icon,
                OnClick = LittleShop.MINIMAP_BUTTON.OnClick,
            }
        )
        
        -- Use DEFAULT_PROFILE.minimap as fallback if persistence not yet initialized
        -- (persistence initializes on PLAYER_LOGIN, but this is called at New())
        local minimap_config = littleshopdependency:Persistence():CurrentProfile().minimap
        if not minimap_config then
            minimap_config = Persistence.DEFAULT_PROFILE.minimap
            LOGGER.CONSOLE.info("Using default minimap config (persistence not yet initialized)")
        end
        
        icon:Register("LittleShop", minimap_button, minimap_config)
        return LittleShop.MINIMAP_BUTTON
    end
}

function LittleShop:BuildUI()

    -- Create a frame to handle the profile and saved 
    self.profile_frame = CreateFrame("Frame","LFC_Profile_Frame", UIParent, "BasicFrameTemplate")
    self.profile_frame.TitleText:SetText("Little Shop - Learned Crafts")
    self.profile_frame:SetSize(400, 400)
    self.profile_frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self.profile_frame:SetMovable(true)
    self.profile_frame:EnableMouse(true)
    self.profile_frame:RegisterForDrag("LeftButton")
    self.profile_frame:SetScript("OnDragStart", self.profile_frame.StartMoving)
    self.profile_frame:SetScript("OnDragStop", self.profile_frame.StopMovingOrSizing)
    
    -- Create content frame inside profile frame for the scrolling list
    local crafts_frame = CreateFrame("Frame", "LFC_Crafts_Frame", self.profile_frame, "BackdropTemplate")
    crafts_frame:SetSize(380, 330)
    crafts_frame:SetPoint("TOPLEFT", self.profile_frame, "TOPLEFT", 10, -30)
    
    -- CRAFTS FRAME BACKDROP
    crafts_frame:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    crafts_frame:SetBackdropColor(0, 0, 0, 0.5)
    crafts_frame:SetBackdropBorderColor(1, 0.8, 0, 0.5)
    
    -- Element: Scroll Box List for crafts
    local crafts_scroll_box = CreateFrame("Frame", nil, crafts_frame, "WowScrollBoxList")
    crafts_scroll_box:SetPoint("TOPLEFT", crafts_frame, "TOPLEFT", 4, -10)
    crafts_scroll_box:SetPoint("BOTTOMRIGHT", crafts_frame, "BOTTOMRIGHT", -22, 0)
    
    -- Element: Scroll Bar for crafts
    local crafts_scroll_bar = CreateFrame("EventFrame", nil, crafts_frame, "MinimalScrollBar")
    crafts_scroll_bar:SetPoint("TOPLEFT", crafts_scroll_box, "TOPRIGHT", 4, 0)
    crafts_scroll_bar:SetPoint("BOTTOMLEFT", crafts_scroll_box, "BOTTOMRIGHT", 4, 10)
    
    -- Element: Scroll Box List View for crafts
    local crafts_item_spacing = 2
    local crafts_view = CreateScrollBoxListLinearView(crafts_item_spacing, crafts_item_spacing, crafts_item_spacing, crafts_item_spacing, crafts_item_spacing)
    crafts_view:SetElementExtent(20) -- Row height
    crafts_scroll_box:SetView(crafts_view)
    ScrollUtil.InitScrollBoxListWithScrollBar(crafts_scroll_box, crafts_scroll_bar, crafts_view)
    
    -- Item initializer: assign craft data to each row button
    crafts_view:SetElementInitializer("Button", function(button, element)
        if not button.text then
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            button.text:SetPoint("LEFT", 10, 0)
            
            local highlight = button:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.2)
            
            button:SetSize(250, 20)
        end
        
        -- Display craft item link
        button.text:SetText(element.item_link or ("Item ID: " .. tostring(element.item_id)))
        
        button:SetScript("OnClick", function()
            LOGGER.CONSOLE.list({
                "Craft Details:",
                "Item ID: " .. tostring(element.item_id),
                "Item Link: " .. tostring(element.item_link),
                "Recipe ID: " .. tostring(element.recipe_id),
                "Crafters: " .. tostring(element.crafters and #element.crafters or 0)
            })
        end)
    end)
    
    -- Create data provider for learned crafts
    for item_id, craft in pairs(self.persistence.learned_crafts) do
        self._crafts_provider:Insert(craft)
    end
    
    crafts_scroll_box:SetDataProvider(self._crafts_provider, ScrollBoxConstants.RetainScrollPosition)
    -- Bind provider refresh to persistence changes
    self.persistence.on_crafts_changed = function()
        self._crafts_provider:Flush()
        for item_id, craft in pairs(self.persistence.learned_crafts) do
            self._crafts_provider:Insert(craft)
        end
    end


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
    self.order_frame:SetBackdropColor(0, 0, 0, 1)
    self.order_frame:SetBackdropBorderColor(1, 0.8, 0, 1)

    self.manage_frame = CreateFrame("Frame", "LFC_Manage_Frame", self.main_frame)
    LOGGER.CONSOLE.info("Creating Manage Frame...")
    self.manage_frame:SetSize(250, 300)
    self.manage_frame:SetPoint("TOPRIGHT", self.main_frame, "TOPRIGHT", -10, -30)

    -- Grid of buttons in MANAGEFRAME
    local ROWS        = 3
    local COLS        = 3
    local BUTTON_SIZE = 40
    local SPACING     = 10

    -- Create a grid of buttons
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
end

local littleshop = LittleShop:New()
littleshop:BindEvents({
    "PLAYER_LOGIN",
    "PLAYER_LOGOUT",
    "ADDON_LOADED",
    "CHAT_MSG_SAY"
})