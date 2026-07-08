-- LFC Service Class:
-- This class will encapsulate all LFC related functionalities

-- Activation Script (must stay in global scope)
SLASH_ACTIVATE_LFC_DETECTION1 = "/littleshop"
SLASH_ACTIVATE_LFC_PANEL1 = "/showshop"
SlashCmdList["ACTIVATE_LFC_DETECTION"] = function()
    _LS_SELF.ActivateService()
end
SlashCmdList["ACTIVATE_LFC_PANEL"] = function()
    _LS_SELF.ToggleFrame()
end

APP_NAME = "LittleShop"

_LS_SELF = {
    -- Debug configuration
    -- Global Variables (member variables)
    WATCHLIST = {},
    MAINFRAME = nil,
    ORDERFRAME = nil,              -- This will hold the current orders detected in chat
    MANAGEFRAME = nil,
    SOUNDS = { LFC_DETECTED = 120, -- Sound kit ID for raid warning sound (good for alerts)
    },

    --[[
        ORDER MANAGEMENT SYSTEM
    ]]
    ORDERS = {
        --[[
            External API:
        ]]
        ORDER_STATE = {
            NONDECISIVE = -3, -- Not sure if it's an craftable order
            UNLEARNED = -2,   -- Unlearned
            HIDDEN = -1,      -- Special usage state
            COMPLETE = 0,     -- Order has been completed
            PENDING = 1,      -- Order that is detected but no whisper follow up
            UNFULFILLED = 2,  -- Order that has been followed up but not completed
            FULFILLED = 3,    -- Order that has been followed up and completed
        },

        -- Create a new empty order object based on the template
        CreateOrderObject = function()
            local order = {}

            for key, value in pairs(_LS_SELF.ORDERS._DATA_TEMPLATE) do
                order[key] = value
            end
            return order
        end,

        ParseItemIdFromLink = function(item_link)
            if not item_link then
                return nil
            end
            local item_id = string.match(item_link, "item:(%d+)")
            return item_id
        end,

        -- Wrapper methods for convenient access to scroll box service
        AddOrder = function(orderData)
            table.insert(_LS_SELF.ORDERS._data, orderData)
            _LS_SELF.ORDERS._INT_SCROLL_BOX_SERVICE.AddOrder(orderData)
        end,

        GetDataProvider = function()
            return _LS_SELF.ORDERS._INT_SCROLL_BOX_SERVICE.GetProvider()
        end,

        --[[
            Internal definition
            ]]
        _data = {},
        _DATA_TEMPLATE = {
            -- Player information
            unique_id =
            "A unique identifier for the order, could be a combination of player name and item ID or a timestamp",
            message = "Full chat message text",
            player = {
                name = "player_name",
                guid = "player_guid",
                realm = "player_realm"
            },
            -- Item information
            item_link = "item_link", -- The ID of the item mentioned in the message (if any)
            -- Order information
            order_state = "the state of the order (e.g., pending, fulfilled, etc.)",
            timestamp = "the time when the order was detected",
            -- Flags for additional information
            flags = {
                is_lfc = false,     -- Whether the message contains an LFC keyword
                is_learned = false, -- Whether the player has learned the recipe for the item
            }
        },

        --[[
            External Dependencies:
        ]]
        _INT_SCROLL_BOX_SERVICE = {
            DATA_PROVIDER = CreateDataProvider(),
            -- This will be used to populate the scroll box with orders

            AddOrder = function(orderData)
                _LS_SELF.ORDERS._INT_SCROLL_BOX_SERVICE.DATA_PROVIDER:Insert(orderData)
            end,
            RemoveOrder = function(order)
                _LS_SELF.ORDERS._INT_SCROLL_BOX_SERVICE.DATA_PROVIDER:RemoveByIndex(order.unique_id) -- Assuming unique_id is used as the index for simplicity
            end,
            ResetOrders = function()
                _LS_SELF.ORDERS._INT_SCROLL_BOX_SERVICE.DATA_PROVIDER:Flush()
            end,

            GetProvider = function()
                return _LS_SELF.ORDERS._INT_SCROLL_BOX_SERVICE.DATA_PROVIDER
            end
        }
    },

    -- Ochestration Function - First function to be called when activate the addon
    ActivateService = function()
        LOGGER.CONSOLE.info("Activating Little Shop Service...")
        -- Initialize the frame if it hasn't been created yet
        if not _LS_SELF.MAINFRAME then
            _LS_SELF.InitializeFrame()
        end

        _LS_SELF.InitializeWatchList() -- Populate the watchlist with the player's current profession recipes
        LOGGER.CONSOLE.info("Initializing watchlist with " .. tostring(#_LS_SELF.WATCHLIST) .. " craftable items.")
        LOGGER.CONSOLE.info("Little Shop Service Activated. Use /showshop to toggle the order board.")
    end,

    ToggleFrame = function()
        if not _LS_SELF.MAINFRAME then
            _LS_SELF.InitializeFrame()
        end
        if _LS_SELF.MAINFRAME:IsShown() then
            _LS_SELF.MAINFRAME:Hide()
        else
            _LS_SELF.MAINFRAME:Show()
        end
    end,

    InitializeFrame = function()
        -- Set titleString
        _LS_SELF.MAINFRAME = CreateFrame("Frame", "LFC_Main_Frame", UIParent, "BasicFrameTemplate")
        _LS_SELF.MAINFRAME.TitleText:SetText("Little Shop - Your Order Board")
        _LS_SELF.MAINFRAME:SetSize(700, 400)
        _LS_SELF.MAINFRAME:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        _LS_SELF.MAINFRAME:SetMovable(true)
        _LS_SELF.MAINFRAME:EnableMouse(true)
        _LS_SELF.MAINFRAME:RegisterForDrag("LeftButton")
        _LS_SELF.MAINFRAME:SetScript("OnDragStart", _LS_SELF.MAINFRAME.StartMoving)
        _LS_SELF.MAINFRAME:SetScript("OnDragStop", _LS_SELF.MAINFRAME.StopMovingOrSizing)

        _LS_SELF.ORDERFRAME = CreateFrame("Frame", "LFC_Order_Frame", _LS_SELF.MAINFRAME, "BackdropTemplate")
        _LS_SELF.ORDERFRAME:SetSize(400, 300)
        _LS_SELF.ORDERFRAME:SetPoint("TOPLEFT", _LS_SELF.MAINFRAME, "TOPLEFT", 10, -30)

        -- ORDERFRAME BACKDROP
        _LS_SELF.ORDERFRAME:SetBackdrop({
            -- Background texture (a solid white square we can color later)
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",

            -- Border texture (The classic WoW tooltip border)
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",

            -- How thick the border is in pixels
            edgeSize = 16,

            -- How far the background shrinks inward so it doesn't overlap the border
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })

        -- Set the Colors (Red, Green, Blue, Alpha)
        -- Black background, 50% opaque
        _LS_SELF.ORDERFRAME:SetBackdropColor(0, 0, 0, 0.5)
        -- Gold border, 50% opaque
        _LS_SELF.ORDERFRAME:SetBackdropBorderColor(1, 0.8, 0, 0.5)

        _LS_SELF.MANAGEFRAME = CreateFrame("Frame", "LFC_Manage_Frame", _LS_SELF.MAINFRAME)
        LOGGER.CONSOLE.info("Creating Manage Frame...")
        _LS_SELF.MANAGEFRAME:SetSize(250, 300)
        _LS_SELF.MANAGEFRAME:SetPoint("TOPRIGHT", _LS_SELF.MAINFRAME, "TOPRIGHT", -10, -30)

        -- LFC_SERVICE.MANAGEFRAME:SetBackdrop({
        --     -- Background texture (a solid white square we can color later)
        --     bgFile = "Interface\\ChatFrame\\ChatFrameBackground",

        --     -- Border texture (The classic WoW tooltip border)
        --     edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",

        --     -- How thick the border is in pixels
        --     edgeSize = 16,

        --     -- How far the background shrinks inward so it doesn't overlap the border
        --     insets = { left = 4, right = 4, top = 4, bottom = 4 }
        -- })

        -- -- Set the Colors (Red, Green, Blue, Alpha)
        -- -- Black background, 50% opaque
        -- LFC_SERVICE.MANAGEFRAME:SetBackdropColor(0, 0, 0, 0.0)
        -- -- Gold border, 50% opaque
        -- LFC_SERVICE.MANAGEFRAME:SetBackdropBorderColor(1, 0.8, 0, 0.5)

        -- 2. Define grid properties
        local ROWS = 3
        local COLS = 3
        local BUTTON_SIZE = 40
        local SPACING = 10

        -- 3. Loop to generate and position the grid elements
        for row = 1, ROWS do
            for col = 1, COLS do
                -- Create a button inside the grid container
                local btn = CreateFrame("Button", nil, _LS_SELF.MANAGEFRAME, "UIPanelButtonTemplate")
                btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
                btn:SetText(row .. "," .. col)

                -- Calculate math offsets from the top-left corner of the container
                local xOffset = (col - 1) * (BUTTON_SIZE + SPACING) + SPACING
                local yOffset = -(row - 1) * (BUTTON_SIZE + SPACING) - SPACING

                -- Anchor the button visually
                btn:SetPoint("TOPLEFT", _LS_SELF.MANAGEFRAME, "TOPLEFT", xOffset, yOffset)
            end
        end


        -- Element: Scroll Box List
        local scroll_box = CreateFrame("Frame", nil, _LS_SELF.ORDERFRAME, "WowScrollBoxList")
        scroll_box:SetPoint("TOPLEFT", _LS_SELF.ORDERFRAME, "TOPLEFT", 4, -10)
        scroll_box:SetPoint("BOTTOMRIGHT", _LS_SELF.ORDERFRAME, "BOTTOMRIGHT", -22, 0)

        -- Element: Scroll Bar
        local scroll_bar = CreateFrame("EventFrame", nil, _LS_SELF.ORDERFRAME, "MinimalScrollBar")
        scroll_bar:SetPoint("TOPLEFT", scroll_box, "TOPRIGHT", 4, 0)
        scroll_bar:SetPoint("BOTTOMLEFT", scroll_box, "BOTTOMRIGHT", 4, 10)

        -- Element: Scroll Box List View
        local itemSpacing = 2
        local view = CreateScrollBoxListLinearView(itemSpacing, itemSpacing, itemSpacing, itemSpacing, itemSpacing)
        view:SetElementExtent(20) -- WARNING: This is required to set the height of each row. Crash will occur if not defined.
        scroll_box:SetView(view)
        ScrollUtil.InitScrollBoxListWithScrollBar(scroll_box, scroll_bar, view)

        -- Item initializer: Iterate through each button in the scroll box and assign data
        -- 'elementData' is the raw data we pass into the DataProvider below
        view:SetElementInitializer("Button", function(button, element)
            -- First time initialization of button
            if not button.text then
                button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                button.text:SetPoint("LEFT", 10, 0)

                -- Optional: Make it highlight when hovered
                local highlight = button:CreateTexture(nil, "HIGHLIGHT")
                highlight:SetAllPoints()
                highlight:SetColorTexture(1, 1, 1, 0.2)

                button:SetSize(250, 20) -- Set the size of each row
            end
            -- Update the button's text based on the element data (e.g., item link or message)
            local timeData = element.timestamp
            button.text:SetText("[" .. string.format("%02d:%02d", timeData.hour, timeData.min) .. "] [" .. (element.player.name or "N/A") .. "] " .. (element.item_link or element.message))


            button:SetScript("OnClick", function()
                LOGGER.CONSOLE.list({
                    "Order Details:",
                    "Unique ID: " .. tostring(element.unique_id),
                    "Player: " .. tostring(element.player.name) .. " (" .. tostring(element.player.realm or "") .. ")",
                    "Item Link: " .. tostring(element.item_link),
                    "Message: " .. tostring(element.message),
                    "State: " .. tostring(element.state),
                    "Timestamp: " .. string.format("%02d:%02d:%02d", timeData.hour, timeData.min, timeData.sec),
                    "Flags: is_lfc=" .. tostring(element.flags.is_lfc) .. ", is_learned=" .. tostring(element.flags.is_learned)
                })
            end)
        end)
        scroll_box:SetDataProvider(_LS_SELF.ORDERS.GetDataProvider(), ScrollBoxConstants.RetainScrollPosition)

        _LS_SELF.MAINFRAME:RegisterEvent("CHAT_MSG_CHANNEL") -- Listens to Trade Chat and other channels (Great for production!)
        _LS_SELF.MAINFRAME:RegisterEvent("CHAT_MSG_SAY")     -- Listens to normal /say (Great for testing!)
        _LS_SELF.MAINFRAME:SetScript("OnEvent", _LS_SELF.OnChatDetectedEvent)
    end,

    --[[
        Event Handler for Chat Detection
        Doc:
            https://warcraft.wiki.gg/wiki/CHAT_MSG_SAY
            https://warcraft.wiki.gg/wiki/CHAT_MSG_CHANNEL
        ]]
    KEYWORDS = { "lfc", "lfm", "looking for", "lf", "craft" }, -- Expandable list of keywords to detect LFC messages
    OnChatDetectedEvent = function(self, event, ...)
        local message, _, _, _, _, _, _, _, channel_name, _, _, guid = ...
        local timestamp = date("*t") -- Capture the timestamp when the message is detected

        -- Caching player information
        local _, _, _, _, _, player_name, player_realm = GetPlayerInfoByGUID(guid)

        -- Scan for LFC keywords (this can be expanded in the future to include more variations and languages)
        local lower_chat_text = string.lower(message)
        local has_lfc_keyword = false -- Pass the chat message to the ScanChat function for processing
        for _, keyword in ipairs(_LS_SELF.KEYWORDS) do
            if string.match(lower_chat_text, keyword) then
                has_lfc_keyword = true
                break
            end
        end
        -- Scan for item links
        -- WoW item link format: |cnIQx|Hitem:payload|h[text]|h|r
        -- where x is Enum.ItemQuality (can be numeric or other formats)
        local item_link = string.match(message, "|cnIQ[^|]+|H[^|]+|h.-%|h|r")
        
        -- Create a data object for the data provider
        local order = _LS_SELF.ORDERS.CreateOrderObject() -- Ensure the data provider is initialized
        order.unique_id = guid .. "_" .. timestamp.day .. timestamp.hour .. timestamp.min .. timestamp.sec     -- Example unique ID
        order.message = message
        order.player = {
            name = player_name,
            realm = player_realm,
            guid = guid
        }
        order.item_link = item_link
        order.state = _LS_SELF.ORDERS.ORDER_STATE.PENDING -- Default state for new orders
        order.timestamp = timestamp                          -- The time when the order was detected
        order.flags = {
            is_lfc = has_lfc_keyword,
            is_learned = item_link and _LS_SELF.WATCHLIST[_LS_SELF.ORDERS.ParseItemIdFromLink(item_link)] ~= nil
        }
        if item_link then
            _LS_SELF.ORDERS.AddOrder(order) -- Add the order data to the provider
            LOGGER.CONSOLE.info("New order from " .. tostring(guid) .. ": " .. tostring(item_link))
            PlaySound(_LS_SELF.SOUNDS.LFC_DETECTED) -- Play a sound when a new order is detected
        end
    end,


    ScanCraftableItems = function()
        local items = {}
        -- Fetch all recipe IDs available to the player
        local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
        if not recipeIDs or #recipeIDs == 0 then
            LOGGER.CONSOLE.warn("No craftable recipes found for the player. Watchlist will be empty.")
            return {}
        end

        local count = 0
        for _, recipeID in ipairs(recipeIDs) do
            local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)

            -- Verify validity of the recipeInfo (varies by profession, expansion, and other personal factors)
            if recipeInfo and recipeInfo.learned then
                -- Extract itemID from the recipe's item link
                local item_link = C_TradeSkillUI.GetRecipeItemLink(recipeID)
                if item_link then
                    local itemID = string.match(item_link, "item:(%d+)")
                    if itemID ~= nil then
                        -- Use itemID as key in map for O(1) lookup speed
                        items[itemID] = item_link
                        count = count + 1
                    end
                end
            end
        end
        LOGGER.CONSOLE.info("LS Found " .. count .. " craftable items for the player.")
        return items
    end,


    InitializeWatchList = function()
        -- This function can be expanded in the future to include more complex logic for populating the watchlist
        _LS_SELF.WATCHLIST = _LS_SELF.ScanCraftableItems()
    end,
}


-- Activate the service when the addon is loaded
_LS_SELF.ActivateService()
