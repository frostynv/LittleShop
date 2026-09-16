local namespace = select(2, ...) -- Get the namespace table from the addon
local Order = namespace.require("order")
local Craft = namespace.require("craft")
local Character = namespace.require("character")
local Crafter = namespace.require("crafter")
local EnhancedFrame = namespace.require("enhancedframe")
local Event = namespace.require("event")
local EventSpace = namespace.require("eventspace")
local Persistence = namespace.require("persistence")
local WowUtil = namespace.require("wowutil")

-- ============================================================
-- LittleShop Class
-- ============================================================

-- @type LittleShop
-- @field is_active          boolean Whether the addon service is currently running
-- @field persistence        Persistence Instance managing saved data
-- @field current_character  Crafter Current character's crafter profile
-- @field EVENT_FRAME        Frame WoW event registration frame
-- @field _order_provider    DataProvider UI data provider for order display
-- @field _crafts_provider   DataProvider UI data provider for learned crafts display
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
    -- Initialize instance variables
    instance.is_active = false
    instance.persistence = Persistence:New()
    instance.current_character = nil -- Initialize crafter tracking
    -- Global abstract frame for register of events
    instance.EVENT_FRAME = CreateFrame("Frame")

    -- UI Elements (created dynamically via FRAMES system)
    instance._order_provider = nil
    instance._crafts_provider = nil
    instance.minimap_button = nil
    
    -- Event system for decoupled communication between persistence and UI
    instance.PERSISTENCE_EVENTS = EventSpace:New()
    
    -- Register persistence-related events
    instance.PERSISTENCE_EVENTS:RegisterEvent(Event:New("CRAFTS_CHANGED"))
    
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
    self:GetOrderProvider():Insert(orderData)
end

-- Removes an order from both persistence and UI data provider
-- @param order Order object to remove
-- @return void
function LittleShop:RemoveOrder(order)
    self.persistence:RemoveOrder(order)
    self:GetOrderProvider():RemoveByIndex(order.unique_id)
end

-- Clears all orders from persistence and UI data provider
-- @return void
function LittleShop:ResetOrders()
    self.persistence:ResetOrders()
    self:GetOrderProvider():Flush()
end

-- Gets the UI data provider for order display
-- @return DataProvider
function LittleShop:GetProvider()
    return self:GetOrderProvider()
end

-- Gets or lazily creates the order data provider
-- @return DataProvider
function LittleShop:GetOrderProvider()
    if not self._order_provider then
        self._order_provider = CreateDataProvider()
    end
    return self._order_provider
end

-- Gets or lazily creates the crafts data provider
-- @return DataProvider
function LittleShop:GetCraftsProvider()
    if not self._crafts_provider then
        self._crafts_provider = CreateDataProvider()
    end
    return self._crafts_provider
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
function LittleShop:ToggleUI()
    local main_frame = self.FRAMES:GetFrame("main_frame")
    if not main_frame then
        return
    end
    if main_frame:IsShown() then
        main_frame:Hide()
    else
        main_frame:Show()
    end
end

function LittleShop:ToggleService()
    if self.is_active then
        self:DeactivateService()
    else
        self:ActivateService()
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
        local item_id = WowUtil.ParseItemIdFromLink(item_link)
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
                local itemID = WowUtil.ParseItemIdFromLink(item_link)
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
    self.persistence:Initialize()
    self.persistence:SetEventSpace(self.PERSISTENCE_EVENTS)
    self.persistence:MergeLearnedCrafts(self:ScanCraftableItems())
    self.is_active = true

    LOGGER.CONSOLE.info("Activating Little Shop Service...")
    self:BuildUI()

    -- Initialize minimap button
    self.minimap_button = LittleShop.MINIMAP_BUTTON.GetInstance({
        onClick = function(frame, button)
            if button == "LeftButton" then
                self:ToggleUI()
            elseif button == "RightButton" then
                self:ToggleService()
            end
        end
    }) -- Imported from singleton

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
    DEFAULT = {
        hide = false,
        minimapPos = 220,
        lock = false,
        tooltipText =
        "Little Shop - Left-click to toggle the order board. Right-click to activate/deactivate the service.",
        icon = "Interface\\Icons\\INV_Chest_Cloth_17",
        onClick = function(frame, button)
            if button == "LeftButton" then
                LOGGER.CONSOLE.info("Minimap button left-clicked.")
            elseif button == "RightButton" then
                LOGGER.CONSOLE.info("Minimap button right-clicked.")
            end
        end
    },
    dbname = "LittleShopMinimapButton",

    -- Initializes the minimap button with LibDBIcon
    -- @param littleshopdependency LittleShop instance (addon singleton)
    -- @return table Icon instance (for show/hide control)
    GetInstance = function(param)
        local icon = LibStub("LibDBIcon-1.0")
        local minimap_button = LibStub("LibDataBroker-1.1"):NewDataObject(
            LittleShop.MINIMAP_BUTTON.dbname,
            {
                type = "data source",
                text = param.text or LittleShop.MINIMAP_BUTTON.DEFAULT.tooltipText,
                icon = param.icon or LittleShop.MINIMAP_BUTTON.DEFAULT.icon,
                OnClick = param.onClick or LittleShop.MINIMAP_BUTTON.DEFAULT.onClick,
            }
        )
        -- Use DEFAULT_PROFILE.minimap as fallback if persistence not yet initialized
        -- (persistence initializes on PLAYER_LOGIN, but this is called at New())
        icon:Register("LittleShop", minimap_button, param.config or LittleShop.MINIMAP_BUTTON.DEFAULT)
        return icon
    end
}

-- ============================================================
-- Dynamic Frame Management with Metatable
-- ============================================================

LittleShop.FRAMES = {
    _frames = {}, -- Internal cache of created frames
}

-- Metatable for dynamic frame access and creation
local framesMeta = {
    -- Dynamic frame access: LittleShop.FRAMES.frame_name creates/retrieves frame
    __index = function(self, key)
        -- Avoid recursion for internal methods
        if key == "_frames" then
            return rawget(self, "_frames")
        end
        
        -- Check if frame already exists in cache
        local cached_frame = rawget(self, "_frames")[key]
        if cached_frame then
            return cached_frame
        end
        
        -- Check if it's a function call (New, AddFrame, GetFrame, RemoveFrame)
        local method = rawget(self, key)
        if type(method) == "function" then
            return method
        end
        return nil -- Return nil for unknown keys
    end,
    
    __tostring = function(self)
        return "LittleShop.FRAMES (Dynamic Frame Manager)"
    end
}

-- Creates a new frame with the given name, parent, and template
-- @param name string Frame name
-- @param parent Frame Parent frame (optional)
-- @param template string Frame template (optional)
-- @return Frame
function LittleShop.FRAMES:New(name, parent, template)
    local frame = CreateFrame("Frame", name, parent or UIParent, template or "BasicFrameTemplate")
    EnhancedFrame:New(frame) -- Mixin event handling capabilities and store parent reference
    return frame
end

-- Creates a new frame and registers it in the frame manager
-- @param name string Frame name and identifier
-- @param parent Frame Parent frame (optional)
-- @param template string Frame template (optional)
-- @return Frame
function LittleShop.FRAMES:Add(name, parent, template)
    local frame = self:New(name, parent, template)
    self:AddFrame(name, frame)
    return frame
end

-- Registers a frame in the frame manager
-- @param name string Identifier for the frame
-- @param frame Frame Frame object to register
-- @return void
function LittleShop.FRAMES:AddFrame(name, frame)
    self._frames[name] = frame
end

-- Retrieves a frame by identifier
-- @param name string Frame identifier
-- @return Frame or nil
function LittleShop.FRAMES:GetFrame(name)
    return self._frames[name]
end

-- Removes a frame from the manager
-- @param name string Frame identifier
-- @return void
function LittleShop.FRAMES:RemoveFrame(name)
    self._frames[name] = nil
end

setmetatable(LittleShop.FRAMES, framesMeta)

function LittleShop:BuildUI()
    local crafts_provider = self:GetCraftsProvider()
    local order_provider = self:GetOrderProvider()

    -- ============================================================
    -- Profile Frame
    -- ============================================================
    local profile_frame = self.FRAMES:Add("ProfileFrame", UIParent, "BasicFrameTemplate")
    profile_frame.TitleText:SetText("Little Shop - Learned Crafts")
    profile_frame:SetSize(400, 400)
    profile_frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    profile_frame:SetMovable(true)
    profile_frame:EnableMouse(true)
    profile_frame:RegisterForDrag("LeftButton")
    profile_frame:SetScript("OnDragStart", profile_frame.StartMoving)
    profile_frame:SetScript("OnDragStop", profile_frame.StopMovingOrSizing)

    -- ============================================================
    -- Crafts Frame (inside profile_frame)
    -- ============================================================
    local crafts_frame = self.FRAMES:Add("CraftsFrame", profile_frame, "BackdropTemplate")
    crafts_frame:SetSize(380, 330)
    crafts_frame:SetPoint("TOPLEFT", profile_frame, "TOPLEFT", 10, -30)
    crafts_frame:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    crafts_frame:SetBackdropColor(0, 0, 0, 0.5)
    crafts_frame:SetBackdropBorderColor(1, 0.8, 0, 0.5)

    -- Element: Scroll Box List for crafts
    local crafts_scroll_box = CreateFrame("Frame", "CraftsScrollBox", crafts_frame, "WowScrollBoxList")
    crafts_scroll_box:SetPoint("TOPLEFT", crafts_frame, "TOPLEFT", 4, -10)
    crafts_scroll_box:SetPoint("BOTTOMRIGHT", crafts_frame, "BOTTOMRIGHT", -22, 0)

    -- Element: Scroll Bar for crafts
    local crafts_scroll_bar = CreateFrame("EventFrame", "CraftsScrollBar", crafts_frame, "MinimalScrollBar")
    crafts_scroll_bar:SetPoint("TOPLEFT", crafts_scroll_box, "TOPRIGHT", 4, 0)
    crafts_scroll_bar:SetPoint("BOTTOMLEFT", crafts_scroll_box, "BOTTOMRIGHT", 4, 10)

    -- Element: Scroll Box List View for crafts
    local crafts_item_spacing = 2
    local crafts_view = CreateScrollBoxListLinearView(crafts_item_spacing, crafts_item_spacing, crafts_item_spacing,
        crafts_item_spacing, crafts_item_spacing)
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
        crafts_provider:Insert(craft)
    end

    crafts_scroll_box:SetDataProvider(crafts_provider, ScrollBoxConstants.RetainScrollPosition)
    
    -- Subscribe crafts_frame to persistence changes via EventSpace
    crafts_frame:On(self.PERSISTENCE_EVENTS, "CRAFTS_CHANGED", function()
        crafts_provider:Flush()
        for item_id, craft in pairs(self.persistence.learned_crafts) do
            crafts_provider:Insert(craft)
        end
    end)

    -- ============================================================
    -- Main Frame
    -- ============================================================
    local main_frame = self.FRAMES:Add("MainFrame", UIParent, "BasicFrameTemplate")
    main_frame.TitleText:SetText("Little Shop - Your Order Board")
    main_frame:SetSize(700, 400)
    main_frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    main_frame:SetMovable(true)
    main_frame:EnableMouse(true)
    main_frame:RegisterForDrag("LeftButton")
    main_frame:SetScript("OnDragStart", main_frame.StartMoving)
    main_frame:SetScript("OnDragStop", main_frame.StopMovingOrSizing)

    -- ============================================================
    -- Order Frame (inside main_frame)
    -- ============================================================
    local order_frame = self.FRAMES:Add("OrderFrame", main_frame, "BackdropTemplate")
    order_frame:SetSize(400, 300)
    order_frame:SetPoint("TOPLEFT", main_frame, "TOPLEFT", 10, -30)
    order_frame:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    order_frame:SetBackdropColor(0, 0, 0, 1)
    order_frame:SetBackdropBorderColor(1, 0.8, 0, 1)

    -- ============================================================
    -- Manage Frame (inside main_frame)
    -- ============================================================
    local manage_frame = self.FRAMES:Add("ManageFrame", main_frame)
    manage_frame:SetSize(250, 300)
    manage_frame:SetPoint("TOPRIGHT", main_frame, "TOPRIGHT", -10, -30)
    LOGGER.CONSOLE.info("Creating Manage Frame...")

    -- Grid of buttons in manage frame
    local ROWS        = 3
    local COLS        = 3
    local BUTTON_SIZE = 40
    local SPACING     = 10

    for row = 1, ROWS do
        for col = 1, COLS do
            local btn = CreateFrame("Button", nil, manage_frame, "UIPanelButtonTemplate")
            btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
            btn:SetText(row .. "," .. col)
            local xOffset = (col - 1) * (BUTTON_SIZE + SPACING) + SPACING
            local yOffset = -(row - 1) * (BUTTON_SIZE + SPACING) - SPACING
            btn:SetPoint("TOPLEFT", manage_frame, "TOPLEFT", xOffset, yOffset)
        end
    end

    -- Element: Scroll Box List
    local scroll_box = CreateFrame("Frame", "OrderScrollBox", orderFrame, "WowScrollBoxList")
    scroll_box:SetPoint("TOPLEFT", order_frame, "TOPLEFT", 4, -10)
    scroll_box:SetPoint("BOTTOMRIGHT", order_frame, "BOTTOMRIGHT", -22, 0)

    -- Element: Scroll Bar
    local scroll_bar = CreateFrame("EventFrame", "OrderScrollBar", order_frame, "MinimalScrollBar")
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

    scroll_box:SetDataProvider(order_provider, ScrollBoxConstants.RetainScrollPosition)
end

-- Program starts here
local littleshop = LittleShop:New()
littleshop:BindEvents({
    "PLAYER_LOGIN",
    "PLAYER_LOGOUT",
    "ADDON_LOADED",
    "CHAT_MSG_SAY"
})
